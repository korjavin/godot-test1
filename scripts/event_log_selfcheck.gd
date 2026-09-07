extends SceneTree
## Headless self-check for the room event log (bead godot-test1-k4j).
##
##   godot --headless --path . --script res://scripts/event_log_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints the first failure and exits 1.
##
## WHAT IT GUARDS, check by check — every one driven on the SHIPPED node
## against mp/voice/player stubs (the `hero_hud_selfcheck` idiom), never on a
## copy, each with a mutation control:
##
##   1. ONE LINE PER EVENT KIND, IN ORDER. Join, hero swap, capture, liberation,
##      remote mic on/off, remote camera on/off, local mic on/off, deafen — each
##      appended once, in domain order, stamped mm:ss of room time.
##   2. THE FADE. Alpha is full until the last second, quantized steps after
##      (driven clock), and the line is dropped past LINE_TTL.
##   3. THE CAP. Seven events keep six lines; the oldest is gone.
##   4. SOLO (AND VOICELESS) DRAWS NOTHING. No room, or no voice module: no
##      lines, no painted snapshot, the frame path a gated accumulator — plus
##      the room-end "disconnected" edge that seeds them.
##   5. THE CORNER FIT. `EventLogHUD`'s scene rect clears CoinLabel and
##      AbilityHUD at design width and fits six lines — the `hero_hud`
##      check-5 precedent, but for the top-right stack, which that scan skips
##      (anchored offsets are not absolute).
##   6. THE SKIN CONTRACT. No hex literal in the widget (the palette lives in
##      `hud_theme.gd` alone), the root adopts `HudTheme.theme()`, and the
##      mirrored self key is the voice module's own spelling.

const LOG_SCRIPT := preload("res://scripts/event_log_hud.gd")
const VOICE_SCRIPT := preload("res://scripts/voice_chat.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"

## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below
## stamps itself before every return; the report site asks whether every stamp
## was reached. `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## Design width/height the HUD is laid out in (the `hero_hud` corner comment's
## own numbers): right-anchored offsets resolve against these.
const DESIGN_W: float = 1920.0
const DESIGN_H: float = 1080.0


## The MP manager's stand-in: the five members the log reads, nothing else.
class StubMp extends Node:
	var online: bool = true
	var me: String = "id-self"
	var members: Array = []
	var holders: Dictionary = {}

	func is_online() -> bool:
		return online

	func my_id() -> String:
		return me

	func get_members() -> Array:
		return members

	func hero_holder(hero: String) -> String:
		return str(holders.get(hero, ""))


## The voice module's stand-in: the seams the log diffs, all held state.
class StubVoice extends Node:
	var available: bool = true
	var tx: bool = false
	var deafened: bool = false
	var speaking: Dictionary = {}
	var video: Array = []

	func is_available() -> bool:
		return available

	func is_tx() -> bool:
		return tx

	func is_deafened() -> bool:
		return deafened

	func is_speaking(id: String) -> bool:
		return bool(speaking.get(id, false))

	func video_peer_ids() -> Array:
		return video


## The player stand-in: only the captive set, which the log diffs by key.
class StubPlayer extends Node:
	var captive_heroes: Dictionary = {}


func _initialize() -> void:
	Sentinel.isolate_user_state()
	await process_frame
	var restore: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var failure: String = await _run_checks()
	TranslationServer.set_locale(restore)
	if failure.is_empty():
		Sentinel.finish(self)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _run_checks() -> String:
	"""Run every check in order. Returns "" on success, else the first failure."""
	var failure: String = await _check_lines_in_order()
	if not failure.is_empty():
		return failure
	failure = _check_fade_and_removal()
	if not failure.is_empty():
		return failure
	failure = _check_cap()
	if not failure.is_empty():
		return failure
	failure = _check_solo_draws_nothing()
	if not failure.is_empty():
		return failure
	failure = _check_corner_fit()
	if not failure.is_empty():
		return failure
	failure = _check_skin()
	if not failure.is_empty():
		return failure
	return ""


func _fresh_log() -> Control:
	"""One real event-log node, in the tree, ticking only when driven."""
	var log: Control = LOG_SCRIPT.new()
	root.add_child(log)
	log.set_process(false)
	return log


func _wired_log() -> Dictionary:
	"""A log on stubs describing a two-member room, baselined silently."""
	var log: Control = _fresh_log()
	var mp := StubMp.new()
	mp.members = [{"id": "id-self", "name": "Self"}, {"id": "id-bob", "name": "Bob"}]
	root.add_child(mp)
	var voice := StubVoice.new()
	root.add_child(voice)
	var player := StubPlayer.new()
	root.add_child(player)
	log._mp = mp
	log._voice = voice
	log._player = player
	log._now_msec = 100000
	log._tick()
	return {"log": log, "mp": mp, "voice": voice, "player": player}


func _free_wired(wired: Dictionary) -> void:
	for key: String in ["log", "mp", "voice", "player"]:
		(wired[key] as Node).queue_free()


func _check_lines_in_order() -> String:
	## Every event kind appends exactly one line, in domain order, stamped.
	var failure := ""
	var wired := _wired_log()
	var log: Control = wired["log"]
	var mp: StubMp = wired["mp"]
	var voice: StubVoice = wired["voice"]
	var player: StubPlayer = wired["player"]
	if log.line_count() != 0:
		failure = "the join baselined %d lines — room entry must seed silently" % log.line_count()
	else:
		var t: int = 100000
		# Window one: a third peer joins, takes primm, is captured and freed,
		# then Bob's mic cycles — six events, six lines, asserted whole.
		mp.members.append({"id": "id-ann", "name": "Ann"})
		t = _step(log, t)
		mp.holders["primm"] = "id-ann"
		t = _step(log, t)
		player.captive_heroes["primm"] = true
		t = _step(log, t)
		player.captive_heroes.erase("primm")
		t = _step(log, t)
		voice.speaking["id-bob"] = true
		t = _step(log, t)
		voice.speaking.erase("id-bob")
		t = _step(log, t)
		failure = _expect_lines(log, [
			"[00:01] Ann joined",
			"[00:02] Ann now plays primm",
			"[00:03] primm was captured",
			"[00:04] primm was freed",
			"[00:05] Bob: mic on",
			"[00:06] Bob: mic off",
		])
		# Window two: Bob's camera cycles, our mic cycles, we deafen and
		# undeafen — the first window scrolls off, this one is asserted whole.
		if failure.is_empty():
			voice.video = ["id-bob"]
			t = _step(log, t)
			voice.video = []
			t = _step(log, t)
			voice.tx = true
			t = _step(log, t)
			voice.tx = false
			t = _step(log, t)
			voice.deafened = true
			t = _step(log, t)
			voice.deafened = false
			t = _step(log, t)
			failure = _expect_lines(log, [
				"[00:07] Bob: camera on",
				"[00:08] Bob: camera off",
				"[00:09] Self: mic on",
				"[00:10] Self: mic off",
				"[00:11] Deafened",
				"[00:12] Undeafened",
			])
		if failure.is_empty():
			# The full paint path, headless: card plus six fading strings,
			# through the real canvas notification (a direct `_draw()` call
			# is refused draw commands outside its notification).
			log.queue_redraw()
			await process_frame
	_free_wired(wired)
	Sentinel.done("lines_in_order")
	return failure


func _step(log: Control, t: int) -> int:
	"""Advance the driven clock one second and run one tick."""
	log._now_msec = t + 1000
	log._tick()
	return t + 1000


func _expect_lines(log: Control, want: Array) -> String:
	"""The ring holds exactly these composed lines, oldest first."""
	if log.line_count() != want.size():
		return "expected %d lines, hold %d" % [want.size(), log.line_count()]
	for i: int in want.size():
		if log.line_text(i) != want[i]:
			return "line %d is '%s', expected '%s' — order or text drifted" \
					% [i, log.line_text(i), want[i]]
	return ""


func _check_fade_and_removal() -> String:
	## Full alpha until the last second, quantized steps after, dropped past TTL.
	var failure := ""
	var log: Control = _fresh_log()
	for age: int in [0, 6999, 7000]:
		if log.line_alpha_at(age) != 1.0:
			failure = "age %d paints %.2f, not full — the fade starts early" % [age, log.line_alpha_at(age)]
			break
	if failure.is_empty():
		for pair: Array in [[7500, 0.5], [7750, 0.25], [7999, 0.25]]:
			if log.line_alpha_at(pair[0]) != pair[1]:
				failure = "age %d paints %.2f, not %.2f — the fade is not quantized steps" \
						% [pair[0], log.line_alpha_at(pair[0]), pair[1]]
				break
	if failure.is_empty():
		for age: int in [8000, 9000]:
			if log.line_alpha_at(age) != 0.0:
				failure = "age %d paints %.2f — past TTL must be zero" % [age, log.line_alpha_at(age)]
				break
	if failure.is_empty():
		# ...and the line itself is dropped on the tick past TTL, live on the node.
		var wired := _wired_log()
		log.queue_free()
		log = wired["log"]
		var mp: StubMp = wired["mp"]
		mp.members.append({"id": "id-ann", "name": "Ann"})
		log._now_msec = 200000
		log._tick()
		if log.line_count() != 1:
			failure = "one join keeps %d lines — the removal below would free nothing" % log.line_count()
		else:
			log._now_msec = 200000 + 8001
			log._tick()
			if log.line_count() != 0:
				failure = "a line survived 8.001 s — TTL drops nothing"
		_free_wired(wired)
		log = null
	if log != null:
		log.queue_free()
	Sentinel.done("fade_and_removal")
	return failure


func _check_cap() -> String:
	## Seven events keep six lines; the oldest is gone.
	var failure := ""
	var wired := _wired_log()
	var log: Control = wired["log"]
	var mp: StubMp = wired["mp"]
	var t: int = 300000
	log._now_msec = t
	for i: int in 7:
		mp.members.append({"id": "id-%d" % i, "name": "P%d" % i})
		t += 100
		log._now_msec = t
		log._tick()
	if log.line_count() != 6:
		failure = "seven joins keep %d lines, not six" % log.line_count()
	elif not log.line_text(0).contains("P1 joined"):
		failure = "oldest kept line is '%s' — P0 should have scrolled off" % log.line_text(0)
	_free_wired(wired)
	Sentinel.done("cap")
	return failure


func _check_solo_draws_nothing() -> String:
	## No room, or no voice: no lines, no painted snapshot, no errors — and the
	## room-end edge that names the disconnected.
	var failure := ""
	# Solo: nothing in any group. Frames tick the gated accumulator only.
	var log: Control = _fresh_log()
	for i: int in 60:
		log._process(0.016)
	if log.line_count() != 0:
		failure = "solo tracked %d lines with no room at all" % log.line_count()
	elif not (log._painted as Array).is_empty():
		failure = "solo painted without a room — the node must draw nothing"
	else:
		# The accumulator gate, not the groups, decides whether a tick runs.
		log._accum = 0.0
		log._process(0.1)
		if log._accum <= 0.0:
			failure = "a 0.1 s frame consumed the accumulator — the 2 Hz gate never holds"
	log.queue_free()
	if not failure.is_empty():
		Sentinel.done("solo_draws_nothing")
		return failure
	# Voiceless room: the room domains keep tracking invisibly, the voice
	# domain freezes, and nothing reaches the paint snapshot's gate.
	var wired := _wired_log()
	log = wired["log"]
	var voice: StubVoice = wired["voice"]
	var mp2: StubMp = wired["mp"]
	voice.available = false
	mp2.members.append({"id": "id-ann", "name": "Ann"})
	log._now_msec = 500000
	log._tick()
	if log.line_count() != 1 or not log.line_text(0).contains("Ann joined"):
		failure = "a voiceless room stopped tracking members — an outage must delay lines, not lose them"
	_free_wired(wired)
	if not failure.is_empty():
		Sentinel.done("solo_draws_nothing")
		return failure
	# Room end: the peers we held get exactly one "disconnected" each. The
	# room started at the baseline tick (t=100000), hence the 05:00 stamps.
	wired = _wired_log()
	log = wired["log"]
	var mp: StubMp = wired["mp"]
	mp.members.append({"id": "id-ann", "name": "Ann"})
	log._now_msec = 400000
	log._tick()
	mp.online = false
	log._now_msec = 401000
	log._tick()
	failure = _expect_lines(log, [
		"[05:00] Ann joined",
		"[05:01] Bob disconnected",
		"[05:01] Ann disconnected",
	])
	_free_wired(wired)
	Sentinel.done("solo_draws_nothing")
	return failure


func _check_corner_fit() -> String:
	## `EventLogHUD`'s scene rect clears CoinLabel and AbilityHUD at design
	## width and fits six lines — the `hero_hud` check-5 precedent, but for the
	## top-right stack, which that scan skips on purpose (anchored offsets are
	## not absolute, so they resolve against the design width here instead).
	var failure := ""
	var text: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	if text.is_empty():
		failure = "cannot read %s — this check measured nothing" % MAIN_SCENE_PATH
	else:
		var rects := {}
		for name: String in ["EventLogHUD", "CoinLabel", "AbilityHUD"]:
			rects[name] = _scene_rect(text, name)
		if (rects["EventLogHUD"] as Rect2) == Rect2():
			failure = "EventLogHUD has no readable top-right rect in main.tscn"
		else:
			var log_rect: Rect2 = rects["EventLogHUD"]
			if log_rect.position.y < 282.0:
				failure = "EventLogHUD starts at y=%.0f, inside AbilityHUD's airspace" \
						% log_rect.position.y
			elif log_rect.size.x < 360.0:
				failure = "EventLogHUD is %.0f px wide — the log card is 360" % log_rect.size.x
			elif log_rect.size.y < 6.0 * (14.0 + 4.0) + 2.0 * 12.0:
				failure = "EventLogHUD is %.0f px tall — six body lines need 132" % log_rect.size.y
			else:
				for neighbour: String in ["CoinLabel", "AbilityHUD"]:
					if (rects[neighbour] as Rect2) != Rect2() \
							and log_rect.intersects(rects[neighbour] as Rect2):
						failure = "EventLogHUD overlaps %s at design width" % neighbour
						break
		if failure.is_empty() and not text.contains('script = ExtResource("35_eventlog")'):
			failure = "EventLogHUD is not wired to the event-log script in main.tscn"
	Sentinel.done("corner_fit")
	return failure


func _scene_rect(text: String, node_name: String) -> Rect2:
	"""That HUD node's design-space rect from the scene text. Anchored (preset
	1, top-right) offsets resolve against DESIGN_W/H; anything else — missing
	node, absolute layout — reads as Rect2(), which the caller treats as "not
	provable" rather than passing silently."""
	var block := _scene_block(text, node_name)
	if block.is_empty():
		return Rect2()
	var anchors := {"anchor_left": 0.0, "anchor_right": 0.0, "anchor_top": 0.0, "anchor_bottom": 0.0}
	var offsets := {"offset_left": 0.0, "offset_right": 0.0, "offset_top": 0.0, "offset_bottom": 0.0}
	for key: String in anchors:
		anchors[key] = _scene_number(block, key)
	for key: String in offsets:
		offsets[key] = _scene_number(block, key)
	if float(anchors["anchor_left"]) != 1.0 or float(anchors["anchor_right"]) != 1.0 \
			or float(anchors["anchor_top"]) != 0.0 or float(anchors["anchor_bottom"]) != 0.0:
		return Rect2()
	return Rect2(
		DESIGN_W + float(offsets["offset_left"]),
		float(offsets["offset_top"]),
		float(offsets["offset_right"]) - float(offsets["offset_left"]),
		float(offsets["offset_bottom"]) - float(offsets["offset_top"]))


func _scene_block(text: String, node_name: String) -> String:
	"""The `[node name="X" ...]` stanza for that HUD node, or ""."""
	var head := "[node name=\"%s\"" % node_name
	var start: int = text.find(head)
	if start < 0:
		return ""
	var next: int = text.find("\n[node ", start)
	if next < 0:
		return text.substr(start)
	return text.substr(start, next - start)


func _scene_number(block: String, key: String) -> float:
	"""The float after `key = ` in that stanza, or 0.0 when absent."""
	var head := key + " = "
	var start: int = block.find(head)
	if start < 0:
		return 0.0
	return float(block.substr(start + head.length()).get_slice("\n", 0))


func _check_skin() -> String:
	## The skin contract: no hex literal in the widget, the root adopts the
	## theme, and the mirrored self key is the module's own spelling.
	var failure := ""
	var source: String = FileAccess.get_file_as_string("res://scripts/event_log_hud.gd")
	if source.is_empty():
		failure = "cannot read the widget source — this check measured nothing"
	else:
		var hex := RegEx.new()
		hex.compile("#[0-9a-fA-F]{3,8}\\b")
		if hex.search(source) != null:
			failure = "a hex literal lives in event_log_hud.gd — the palette is hud_theme.gd alone"
	if failure.is_empty():
		if LOG_SCRIPT.SELF_KEY != VOICE_SCRIPT.SELF_LEVEL_KEY:
			failure = "SELF_KEY '%s' is not the voice module's '%s' — self-view maps to the wrong peer" \
					% [LOG_SCRIPT.SELF_KEY, VOICE_SCRIPT.SELF_LEVEL_KEY]
	if failure.is_empty():
		var log: Control = _fresh_log()
		if log.theme != HudTheme.theme():
			failure = "the root did not adopt HudTheme.theme() — the panel convention"
		elif log.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			failure = "the log takes mouse input — an overlay must never eat clicks"
		elif log.focus_mode != Control.FOCUS_NONE:
			failure = "the log takes focus — an overlay must never steal it"
		log.queue_free()
	Sentinel.done("skin")
	return failure
