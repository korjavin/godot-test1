extends SceneTree
## Headless self-check for the room event log (bead godot-test1-k4j).
##
##   godot --headless --path . --script res://scripts/event_log_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints the first failure and exits 1.
##
## WHAT IT GUARDS, check by check — every one driven on the SHIPPED node
## against mp/voice/player stubs (the `hero_hud_selfcheck` idiom), never on a
## copy. EACH CHECK ENDS WITH A NEGATIVE CONTROL in the suite's sense: a
## corrupted ring, snapshot or rect driven beside the live one and asserted to
## FAIL the same bound — a check that cannot fail is the shape `crowd`
## check 10/12 and `hero_hud` check 6b exist to stop.
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
##   7. THE SENDER ROLL-CALL. The camera getter reads the cached roll-call,
##      never the placement set and never the bridge — stubs cannot see the
##      difference, so the shipped bodies are read (the suite's source-grep
##      idiom), and each clause is fired on a violating sample so the clauses
##      themselves can fail.
##   8. THE CAPTIVE SETTLE WINDOW. A set arriving one tick after the join
##      prints nothing (re-baselined, not diffed); a genuine grab-and-release
##      past the window prints both; the same standing set with the window
##      forced shut prints (the control proves the quiet is the window).
##   9. THE CAMERA GRACE. Senders first seen inside CAMERA_GRACE_TICKS of the
##      room start baseline silently; a sender first seen after it prints once.
##   10. THE LOCAL EDGE UNDER PUSH-TO-TALK. A PTT press/release prints nothing;
##      back in activity mode the same edges print.

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


## The MP manager's stand-in: the seams the log reads, nothing else — including
## the leave behaviour the disconnect guard depends on.
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

	func go_offline() -> void:
		## Mirrors `MpManager.leave()`: offline and anonymous in the same call.
		online = false
		me = ""


## The voice module's stand-in: the seams the log diffs, all held state.
class StubVoice extends Node:
	var available: bool = true
	var tx: bool = false
	var mode: int = 0
	var deafened: bool = false
	var speaking: Dictionary = {}
	var video: Array = []

	func is_available() -> bool:
		return available

	func is_tx() -> bool:
		return tx

	func get_mode() -> int:
		return mode

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
	failure = _check_captive_settle()
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
	failure = _check_sender_rollcall()
	if not failure.is_empty():
		return failure
	failure = _check_camera_grace()
	if not failure.is_empty():
		return failure
	failure = _check_local_ptt()
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
		# Window one: a third peer joins, takes primm, is captured and freed.
		mp.members.append({"id": "id-ann", "name": "Ann"})
		t = _step(log, t)
		mp.holders["primm"] = "id-ann"
		t = _step(log, t)
		player.captive_heroes["primm"] = true
		t = _step(log, t)
		player.captive_heroes.erase("primm")
		t = _step(log, t)
		failure = _expect_lines(log, [
			"[00:01] Ann joined",
			"[00:02] Ann now plays Primm",
			"[00:03] Primm was captured",
			"[00:04] Primm was freed",
		])
		# Window two: Bob talks through a pause (debounced: two quiet ticks
		# print NOTHING, the third prints off), then his camera cycles. Bob
		# holds no hero — his camera line proves the log never consults the
		# roster for video.
		if failure.is_empty():
			voice.speaking["id-bob"] = true
			t = _step(log, t)
			voice.speaking.erase("id-bob")
			t = _step(log, t)
			if log.line_count() != 5:
				failure = "one quiet tick after speech printed — the debounce holds two"
			else:
				t = _step(log, t)
				if log.line_count() != 5:
					failure = "two quiet ticks after speech printed — the debounce holds two"
		if failure.is_empty():
			t = _step(log, t)
			voice.video = ["id-bob"]
			t = _step(log, t)
			voice.video = []
			t = _step(log, t)
			failure = _expect_lines(log, [
				"[00:03] Primm was captured",
				"[00:04] Primm was freed",
				"[00:05] Bob: mic on",
				"[00:08] Bob: mic off",
				"[00:09] Bob: camera on",
				"[00:10] Bob: camera off",
			])
		# Window three: our mic cycles, we deafen and undeafen.
		if failure.is_empty():
			voice.tx = true
			t = _step(log, t)
			voice.tx = false
			t = _step(log, t)
			voice.deafened = true
			t = _step(log, t)
			voice.deafened = false
			t = _step(log, t)
			failure = _expect_lines(log, [
				"[00:09] Bob: camera on",
				"[00:10] Bob: camera off",
				"[00:11] Self: mic on",
				"[00:12] Self: mic off",
				"[00:13] Deafened",
				"[00:14] Undeafened",
			])
		if failure.is_empty():
			# The full paint path, headless: card plus six fading strings,
			# through the real canvas notification (a direct `_draw()` call
			# is refused draw commands outside its notification).
			log.queue_redraw()
			await process_frame
		if failure.is_empty():
			# THE CONTROL: the same oracle on a corrupted ring must FAIL —
			# otherwise this check could pass on anything.
			var corrupt := _wired_log()
			var clog: Control = corrupt["log"]
			var cmp: StubMp = corrupt["mp"]
			cmp.members.append({"id": "id-ann", "name": "Ann"})
			clog._now_msec = 600000
			clog._tick()
			cmp.members.append({"id": "id-cat", "name": "Cat"})
			clog._now_msec = 601000
			clog._tick()
			(clog._lines as Array)[0] = {"text": "[00:00] BOGUS", "born": 600000}
			if _expect_lines(clog, ["[08:20] Ann joined", "[08:21] Cat joined"]).is_empty():
				failure = "the oracle passed a corrupted ring — this check cannot fail"
			_free_wired(corrupt)
	_free_wired(wired)
	Sentinel.done("lines_in_order")
	return failure


func _step(log: Control, t: int) -> int:
	"""Advance the driven clock one second and run one tick."""
	log._now_msec = t + 1000
	log._tick()
	return t + 1000


func _check_camera_grace() -> String:
	## PER PEER, not per room (review round 1): an id's camera inside its own
	## grace baselines silently, past it prints — and a peer joining mid-room
	## gets a grace of its own rather than the room's expired one.
	var failure := ""
	var wired := _wired_log()
	var log: Control = wired["log"]
	var mp: StubMp = wired["mp"]
	var voice: StubVoice = wired["voice"]
	var t: int = 100000
	# Bob is standing at seed: his track two ticks later is standing state.
	voice.video = ["id-bob"]
	t = _step(log, t)
	if log.line_count() != 0:
		failure = "a standing camera printed inside its grace — %d lines, want none" \
				% log.line_count()
	else:
		# The track drops (an off line, expected), Ann joins mid-room, and her
		# track two ticks later is standing state under her OWN grace.
		voice.video = []
		t = _step(log, t)
		mp.members.append({"id": "id-ann", "name": "Ann"})
		t = _step(log, t)
		voice.video = ["id-ann"]
		t = _step(log, t)
		# Bob's track comes back five ticks past his first sighting: news, one
		# line — while Ann, already baselined, stays silent.
		voice.video = ["id-ann", "id-bob"]
		t = _step(log, t)
		failure = _expect_lines(log, [
			"[00:02] Bob: camera off",
			"[00:03] Ann joined",
			"[00:05] Bob: camera on",
		])
	_free_wired(wired)
	Sentinel.done("camera_grace")
	return failure


func _check_local_ptt() -> String:
	## Under push-to-talk the local mic edge prints nothing: every press and
	## release would be an on/off pair churning the ring, while the held key is
	## the indicator (bead godot-test1-tgx). Activity mode still prints both.
	var failure := ""
	var wired := _wired_log()
	var log: Control = wired["log"]
	var voice: StubVoice = wired["voice"]
	var t: int = 100000
	voice.mode = VOICE_SCRIPT.Mode.PUSH_TO_TALK
	voice.tx = true
	t = _step(log, t)
	voice.tx = false
	t = _step(log, t)
	if log.line_count() != 0:
		failure = "a PTT press/release printed %d lines — the local edge is not muted" \
				% log.line_count()
	else:
		# Back in activity mode the same edges print — the mute tracks the
		# mode, and the state was still tracked underneath.
		voice.mode = VOICE_SCRIPT.Mode.ALWAYS_ON
		voice.tx = true
		t = _step(log, t)
		voice.tx = false
		t = _step(log, t)
		failure = _expect_lines(log, [
			"[00:03] Self: mic on",
			"[00:04] Self: mic off",
		])
	_free_wired(wired)
	Sentinel.done("local_ptt")
	return failure


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
	## Full alpha until the two-second tail, four quantized steps after,
	## dropped past TTL — and the steps a real tick actually paints.
	var failure := ""
	var log: Control = _fresh_log()
	for age: int in [0, 5999, 6000]:
		if log.line_alpha_at(age) != 1.0:
			failure = "age %d paints %.2f, not full — the fade starts early" % [age, log.line_alpha_at(age)]
			break
	if failure.is_empty():
		for pair: Array in [[6500, 0.75], [7000, 0.5], [7500, 0.25], [7999, 0.25]]:
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
		# THE CONTROL: an independent formula swept across the whole life must
		# agree at every step — if the shipped fade changes shape, this (not
		# just the named points above) goes red.
		for age: int in range(0, 8101, 53):
			var want := 0.0
			if age < 6000:
				want = 1.0
			elif age < 8000:
				want = float(int(ceil(float(8000 - age) / 2000.0 * 4.0))) / 4.0
			if log.line_alpha_at(age) != want:
				failure = "age %d paints %.2f, oracle says %.2f — fade shape drifted" \
						% [age, log.line_alpha_at(age), want]
				break
	if failure.is_empty():
		# THE CONTROL: the oracle sweep above must DISAGREE with a wrong-shape
		# tail — otherwise it guards the points, not the shape, and a three-step
		# fade would pass it. The sweep runs over a three-step `line_alpha_at`
		# STUB (review round 1: reading the shipped fade here agrees whenever
		# the fade is right and hides behind the guard whenever it is wrong, so
		# it can never go red) and must disagree at >= 1 age.
		var discriminates := false
		for age: int in range(0, 8101, 53):
			var want := 0.0
			if age < 6000:
				want = 1.0
			elif age < 8000:
				want = float(int(ceil(float(8000 - age) / 2000.0 * 4.0))) / 4.0
			if _three_step_alpha(age) != want:
				discriminates = true
				break
		if not discriminates:
			failure = "the oracle agrees with a three-step tail everywhere — the sweep cannot fail"
	if failure.is_empty():
		# The painted sequence a real tick takes through the tail: four
		# distinct alphas off `_painted` itself, then the drop — a one-second
		# tail would paint two levels here, not four.
		var wired := _wired_log()
		var tlog: Control = wired["log"]
		var tmp: StubMp = wired["mp"]
		tmp.members.append({"id": "id-ann", "name": "Ann"})
		tlog._now_msec = 200000
		tlog._tick()
		var painted: Array = []
		for step: int in [6000, 6500, 7000, 7500]:
			tlog._now_msec = 200000 + step
			tlog._tick()
			if tlog.line_count() != 1:
				failure = "the tailed line vanished at +%d ms — the sequence measured nothing" % step
				break
			painted.append(float(((tlog._painted as Array)[0] as Array)[1]))
		if failure.is_empty():
			if painted != [1.0, 0.75, 0.5, 0.25]:
				failure = "ticks painted %s, not [1.0, 0.75, 0.5, 0.25] — the tail is not four steps" \
						% str(painted)
			else:
				tlog._now_msec = 208000
				tlog._tick()
				if tlog.line_count() != 0:
					failure = "the tailed line survived to +8000 ms — TTL drops nothing"
		_free_wired(wired)
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


static func _three_step_alpha(age: int) -> float:
	## Wrong-shape stub for the fade control: the same full head, a THREE-step
	## tail, gone past TTL. The four-step oracle must disagree with it
	## somewhere in the tail, or the sweep guards points and not shape.
	if age < 6000:
		return 1.0
	if age < 8000:
		return float(int(ceil(float(8000 - age) / 2000.0 * 3.0))) / 3.0
	return 0.0


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
	if failure.is_empty():
		# THE CONTROL: an overfull ring, built by hand past the cap, must FAIL
		# the same oracle — otherwise "six" is never actually enforced.
		var fat: Control = _fresh_log()
		for i: int in 7:
			(fat._lines as Array).append({"text": "L%d" % i, "born": 700000 + i})
		if fat.line_count() != 7:
			failure = "the hand-built ring holds %d, not 7 — the control measured nothing" \
					% fat.line_count()
		elif _expect_lines(fat, ["L1", "L2", "L3", "L4", "L5", "L6"]).is_empty():
			failure = "the oracle passed a seven-line ring — the cap is unenforced"
		fat.queue_free()
	_free_wired(wired)
	Sentinel.done("cap")
	return failure


func _check_captive_settle() -> String:
	## A joiner's first sight of the captive set is STANDING STATE, not news:
	## `welcome` empties it and the room's real set lands after, so the window
	## re-baselines silently and only genuine changes after it print. The stub
	## models the race the suite otherwise never sees — the set arriving one
	## tick after the join.
	var failure := ""
	var wired := _wired_log()
	var log: Control = wired["log"]
	var player: StubPlayer = wired["player"]
	# The room's set lands 500 ms after the join, mid-window: silence.
	player.captive_heroes["primm"] = true
	log._now_msec = 100500
	log._tick()
	if log.line_count() != 0:
		failure = "a set arriving 500 ms after the join printed %d lines — standing state is not news" \
				% log.line_count()
	else:
		# Past the window the same set is trusted — and still silent, because
		# the window re-baselined it instead of diffing it.
		log._now_msec = 101600
		log._tick()
		if log.line_count() != 0:
			failure = "the settled standing set printed %d lines — the window diffed instead of baselining" \
					% log.line_count()
		else:
			# ...while a genuine grab-and-release after settle prints both.
			player.captive_heroes.erase("primm")
			log._now_msec = 102000
			log._tick()
			player.captive_heroes["primm"] = true
			log._now_msec = 102500
			log._tick()
			failure = _expect_lines(log, [
				"[00:02] Primm was freed",
				"[00:02] Primm was captured",
			])
	if failure.is_empty():
		# THE CONTROL: the same standing set with the window forced SHUT must
		# FAIL the silence bound — otherwise the quiet above proves a dead diff,
		# not a window. A fresh log whose room started an hour ago is settled on
		# its first tick, so the standing cell prints as news.
		var shut := _wired_log()
		var slog: Control = shut["log"]
		var splayer: StubPlayer = shut["player"]
		splayer.captive_heroes["primm"] = true
		slog._room_start_msec = 0
		slog._now_msec = 100500
		slog._tick()
		if slog.line_count() != 1 or not slog.line_text(0).contains("Primm was captured"):
			failure = "a settled standing set printed %d lines — the window-shut drive cannot fail" \
					% slog.line_count()
		_free_wired(shut)
	_free_wired(wired)
	Sentinel.done("captive_settle")
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
	elif log.would_paint():
		failure = "solo would paint — the gate must be shut with no snapshot"
	else:
		# THE CONTROL: a forged non-empty snapshot must STILL not paint with no
		# voice module — otherwise the quiet above proves an empty ring, not the
		# voice gate that actually shuts solo.
		(log._painted as Array).append(["forged", 1.0])
		if log.would_paint():
			failure = "a forged snapshot painted voiceless — the gate reads the ring, not the module"
		(log._painted as Array).clear()
		# THE CONTROL (contrast): the same machinery in a room DOES track, so
		# the zero above is the degrade and not a dead tick.
		var contrast := _wired_log()
		var clog: Control = contrast["log"]
		var cmp: StubMp = contrast["mp"]
		cmp.members.append({"id": "id-ann", "name": "Ann"})
		clog._now_msec = 800000
		clog._tick()
		if clog.line_count() != 1 or not clog.line_text(0).contains("Ann joined"):
			failure = "the wired log tracked nothing either — the solo zero proves nothing"
		elif not clog.would_paint():
			failure = "a room with lines would not paint — the gate is shut for everyone"
		_free_wired(contrast)
	if failure.is_empty():
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
	elif log.would_paint():
		failure = "a voiceless room would paint — tracking is not painting"
	_free_wired(wired)
	if not failure.is_empty():
		Sentinel.done("solo_draws_nothing")
		return failure
	# Room end through an honest leave: offline AND anonymous in the same call,
	# like `MpManager.leave()` — our own id must not read as disconnected, and
	# the lines must still want paint (the gate outlives the room).
	wired = _wired_log()
	log = wired["log"]
	var mp: StubMp = wired["mp"]
	mp.members.append({"id": "id-ann", "name": "Ann"})
	log._now_msec = 400000
	log._tick()
	mp.go_offline()
	log._now_msec = 401000
	log._tick()
	failure = _expect_lines(log, [
		"[05:00] Ann joined",
		"[05:01] Bob disconnected",
		"[05:01] Ann disconnected",
	])
	if failure.is_empty() and not log.would_paint():
		failure = "offline lines would not paint — the disconnect kind is invisible again"
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
		failure = _assert_fit(rects)
		if failure.is_empty() and not text.contains('script = ExtResource("35_eventlog")'):
			failure = "EventLogHUD is not wired to the event-log script in main.tscn"
		if failure.is_empty():
			# THE CONTROL: the same rules on a scene with the log shoved
			# 182 px up must FAIL — otherwise "clears its neighbours" is
			# unprovable.
			var tampered: String = text.replace("offset_top = 282.0", "offset_top = 100.0")
			if tampered == text:
				failure = "the control scene has no 282.0 to move — it measured nothing"
			else:
				var moved := {}
				for name: String in ["EventLogHUD", "CoinLabel", "AbilityHUD"]:
					moved[name] = _scene_rect(tampered, name)
				if _assert_fit(moved).is_empty():
					failure = "the rules cleared a log sitting on AbilityHUD — they cannot fail"
	Sentinel.done("corner_fit")
	return failure


func _assert_fit(rects: Dictionary) -> String:
	"""The corner rules on three design-space rects: readable, below
	AbilityHUD's airspace, 360 wide, six lines tall, overlapping neither
	neighbour."""
	if (rects["EventLogHUD"] as Rect2) == Rect2():
		return "EventLogHUD has no readable top-right rect in main.tscn"
	var log_rect: Rect2 = rects["EventLogHUD"]
	if log_rect.position.y < 282.0:
		return "EventLogHUD starts at y=%.0f, inside AbilityHUD's airspace" % log_rect.position.y
	if log_rect.size.x < 360.0:
		return "EventLogHUD is %.0f px wide — the log card is 360" % log_rect.size.x
	if log_rect.size.y < 6.0 * (14.0 + 4.0) + 2.0 * 12.0:
		return "EventLogHUD is %.0f px tall — six body lines need 132" % log_rect.size.y
	for neighbour: String in ["CoinLabel", "AbilityHUD"]:
		if (rects[neighbour] as Rect2) != Rect2() \
				and log_rect.intersects(rects[neighbour] as Rect2):
			return "EventLogHUD overlaps %s at design width" % neighbour
	return ""


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


func _check_sender_rollcall() -> String:
	## The camera source is the cached SENDER roll-call, never the placement
	## set and never a fresh bridge round trip: the getter reads the cache
	## `_poll_tiles` fills from its `videoPeers()` parse (plus self on the
	## reported camera), so a capture or a hero-less peer keeps sending while
	## their tile is down (review rounds 1-2). Stubs cannot see the difference,
	## so the shipped bodies are read instead (the suite's source-grep idiom:
	## `pause_selfcheck`, `hero_hud` check 8).
	var failure := ""
	var source: String = FileAccess.get_file_as_string("res://scripts/voice_chat.gd")
	if source.is_empty():
		failure = "cannot read voice_chat.gd — this check measured nothing"
	elif not source.contains("func video_peer_ids()"):
		failure = "video_peer_ids() not found — the camera seam moved"
	else:
		failure = _rollcall_violation(source)
	if failure.is_empty():
		# THE CONTROL: each clause must fire on a violating sample — otherwise a
		# clause that can never fail guards nothing (the skin hex-oracle idiom).
		# Review round 1: three of the four samples tripped clause 1, so
		# clauses 3-6 were never exercised. Each sample below carries the
		# prefix that satisfies every earlier clause, so it violates ONLY its
		# own — one sample per clause, six clauses, six samples.
		var good_getter := "func video_peer_ids() -> Array:\n" \
				+ "\tvar ids := _video_senders.keys()\n" \
				+ "\tif _reported_cam:\n" \
				+ "\t\tids.append(\"me\")\n" \
				+ "\treturn ids\n"
		var bad: Array = [
			["func video_peer_ids() -> Array:\n\treturn []",
				"never reads the sender cache",
				"a getter with no cache read"],
			["func video_peer_ids() -> Array:\n\treturn _video_senders.keys()",
				"never reads the reported camera",
				"a self-view with no reported camera"],
			["func video_peer_ids() -> Array:\n\tvar s := _video_senders\n\tvar c := _reported_cam\n\treturn JavaScriptBridge.videoPeers()",
				"calls the bridge itself",
				"a bridge round trip"],
			["func video_peer_ids() -> Array:\n\tvar s := _video_senders\n\tvar c := _reported_cam\n\treturn _pushed_tiles.keys()",
				"reads the placement set",
				"the placement set"],
			[good_getter + "func _poll_tiles() -> void:\n\tpass",
				"never fills the sender cache",
				"a poll that never fills the cache"],
			[good_getter + "func _poll_tiles() -> void:\n\t_video_senders = senders",
				"clears the sender cache",
				"a poll that fills the cache but never clears it"],
		]
		for sample: Array in bad:
			var verdict := _rollcall_violation(str(sample[0]))
			if verdict.is_empty():
				failure = "the roll-call clauses passed %s — they cannot fail" % str(sample[2])
				break
			if not verdict.contains(str(sample[1])):
				failure = "%s tripped another clause (%s) — clauses hide behind each other" \
						% [str(sample[2]), verdict]
				break
	Sentinel.done("sender_rollcall")
	return failure


func _rollcall_violation(source: String) -> String:
	"""The first roll-call clause this source violates, or "" — one predicate
	for the shipped module and the violating samples alike, so the control
	above measures the clauses and not the samples."""
	var code := _code_of(source, "func video_peer_ids()")
	if code.strip_edges().is_empty():
		# A bare snippet has no getter to judge — it is judged as a getter.
		code = source
	if not code.contains("_video_senders"):
		return "video_peer_ids() never reads the sender cache — the log's 2 Hz pays a round trip"
	if not code.contains("_reported_cam"):
		return "video_peer_ids() never reads the reported camera — the self-view is lost"
	if code.contains("videoPeers("):
		return "video_peer_ids() calls the bridge itself — it is not bridge-free"
	if code.contains("_pushed_tiles"):
		return "video_peer_ids() reads the placement set — a capture would print camera off"
	if not source.contains("_video_senders = senders"):
		return "_poll_tiles never fills the sender cache from its videoPeers() parse"
	if not source.contains("_video_senders.clear()"):
		return "nothing clears the sender cache when the tile poll stands down — it goes stale"
	return ""


func _code_of(source: String, head: String) -> String:
	"""That function's code with docstrings and comments stripped: the shape,
	not the prose, so a comment mentioning a call cannot satisfy a clause."""
	var start: int = source.find(head)
	if start < 0:
		return ""
	var stop: int = source.find("\n# ===", start)
	var body: String = source.substr(start, stop - start) if stop >= 0 else source.substr(start)
	var code_lines: Array = []
	var in_doc := false
	for line: String in body.split("\n"):
		var bare: String = line.strip_edges()
		if bare.begins_with('"""'):
			in_doc = not in_doc
			continue
		if in_doc or bare.begins_with("#"):
			continue
		code_lines.append(line)
	return "\n".join(code_lines)


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
		# THE CONTROL: the oracle must fire on a known-bad sample, or a clean
		# widget proves the regex blind rather than the file clean.
		elif hex.search("draw it Color(#ff0000) red") == null:
			failure = "the hex oracle missed #ff0000 — it cannot fail"
	if failure.is_empty():
		if LOG_SCRIPT.SELF_KEY != VOICE_SCRIPT.SELF_LEVEL_KEY:
			failure = "SELF_KEY '%s' is not the voice module's '%s' — self-view maps to the wrong peer" \
					% [LOG_SCRIPT.SELF_KEY, VOICE_SCRIPT.SELF_LEVEL_KEY]
		elif VOICE_SCRIPT.SELF_LEVEL_KEY != "me":
			failure = "the voice module's self key is '%s', not 'me' — both mirrors drifted together" \
					% VOICE_SCRIPT.SELF_LEVEL_KEY
		elif LOG_SCRIPT.VOICE_MODE_PTT != VOICE_SCRIPT.Mode.PUSH_TO_TALK:
			failure = "VOICE_MODE_PTT '%d' is not the voice module's PUSH_TO_TALK — PTT suppression mutes the wrong mode" \
					% LOG_SCRIPT.VOICE_MODE_PTT
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
