extends Control
## Room event log — the temporal MP log on the right of the HUD (bead
## godot-test1-k4j, owner: "write events like player joined, player
## disconnected, voice on/off and so on in temporal log on the right side").
##
## Six lines, newest at the bottom, each living LINE_TTL seconds and fading over
## its last one: who joined / left / disconnected, who picked up which hero,
## captures and liberations, mic on/off per peer, camera on/off per peer, local
## deafen on/off — each stamped mm:ss of room time.
##
## DISCOVERY-BASED AND POLLED, like every other widget in this HUD: the room,
## the voice module and the player are found through their groups behind
## `has_method` guards, and ONE 2 Hz snapshot compare per tick decides whether
## a line is appended — never per frame, and never through a new MP verb, a new
## codec parser or an `mp_manager` edit. Signals were considered and refused:
## `room_changed` / `heroes_changed` would give member edges sooner, but the
## log would still need the same poll for voice, camera and captives — two edge
## paths with two orderings — while a 2 Hz poll keeps every domain in one
## deterministic append order per tick (members, heroes, captives, mic, camera,
## deafen) for a latency nobody asked to remove.
##
## WHAT EACH LINE NAMES. Joins, leaves, disconnects, mic edges and hero swaps
## name the MEMBER ("%s joined"); camera edges name the SENDING PEER's member
## name off the module's sender roll-call (placement-independent, so a capture
## never reads as "camera off"; the self-view reads as our own); hero swaps and
## captures name the HERO, capitalized like every other surface ("%s now plays
## %s", "%s was captured"), because the roster is the thing that changed hands
## there. A remote "mic on" is immediate off the voice module's held levels —
## a silent peer is indistinguishable from a muted one, so it means "started
## making noise" — while "mic off" needs MIC_OFF_SILENT_TICKS quiet ticks in a
## row, or every conversational pause evicts the lines the log exists to show.
## "Disconnected" is the room-end edge: peers we held when the room went away,
## as opposed to peers who left while it stood — and the paint gate outlives
## the room on purpose, so those lines fade out on screen instead of vanishing
## with the room that wrote them.
##
## It is READ-ONLY and INPUT-FREE: `MOUSE_FILTER_IGNORE`, `FOCUS_NONE`, no
## pause claim ever (a frozen tree simply stops its tick), and nothing here
## writes game state — the roster, the captives and the voice module need no
## edit, except the one read-only `video_peer_ids()` view on the module's
## sender roll-call. Solo, or with no voice module, the node draws NOTHING and
## its
## frame cost is one accumulator add (the group lookups happen on the 2 Hz
## tick, never per frame) — tracking is not painting: a voiceless room keeps
## its room domains current invisibly and only the voice domain reseeds.
##
## Painting is `_draw` off `HudTheme` consts — BONE body text on an INK card —
## with `HudTheme.theme()` adopted on the root for the panel-bead convention.
## No hex literal lives in this file (`hero_hud_selfcheck` check 8 greps).

## The roster's one definition, reached the way `hero_hud` reaches it: the
## script's const, not a copy. (A SCRIPT dependency, not a node reference —
## the live player is still found through the "player" group.)
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")

## How often the room is re-read: the other HUD readers' 2 Hz. A join is at
## most half a second late on screen, which is nothing against an 8 s line.
const POLL_INTERVAL: float = 0.5
## The ring: six lines, newest at the bottom, each living eight seconds.
const MAX_LINES: int = 6
const LINE_TTL: float = 8.0
## The fade runs over the line's last TWO seconds and is QUANTIZED on purpose:
## this widget repaints only when its snapshot changes (the HUD idiom), so a
## smooth alpha would repaint every frame for eight seconds a line. At the
## 2 Hz tick the tail takes four real samples — 1.0, 0.75, 0.5, 0.25 — so a
## line costs one append repaint, up to three fade-step repaints, and its drop
## (review round 2: a one-second tail paints two levels, not four).
const FADE_TAIL: float = 2.0
const FADE_STEPS: int = 4

## Consecutive silent 2 Hz ticks before a peer reads as "mic off" (review
## round 1): the module holds speech for 150 ms, so sampling it raw prints an
## off/on pair per conversational pause and evicts the lines the log exists to
## show. "Mic on" stays immediate; 1.5 s of quiet means hung up, not pausing.
const MIC_OFF_SILENT_TICKS: int = 3

## Ticks after an id is first seen in the room during which its camera baselines
## silently instead of printing (bead godot-test1-tgx, review round 1): remote
## tracks arrive after the voice module starts (and a peer can join mid-room),
## so a global window off the room start still floods — every already-live
## camera would read as a fresh "camera on" a moment later. PER PEER, not per
## room: the first sighting of the id stamps it (see `_member_since`), and a
## camera inside that id's grace is standing state while one past it is news.
## The MIC_OFF_SILENT_TICKS shape — a count of 2 Hz ticks, not a clock.
const CAMERA_GRACE_TICKS: int = 3

## Msec after the room start during which the captive set is re-baselined
## silently instead of diffed (review round 2): `welcome` EMPTIES the set and
## the room's real one lands after, over the `room` verb and the join
## snapshot's `cap` — diffing the empty moment prints every standing cell as a
## fresh grab. DERIVED from `MpManager.JOIN_SNAPSHOT_WAIT`, not a second
## hand-written 1500 (bead godot-test1-tgx): the two windows are one fact, and
## a copy would let them drift. The live manager is asked first through
## `_join_settled()` (which also settles early once the snapshots are in), and
## this is the fallback a stub — or an old manager — runs on.
const CAPTIVE_SETTLE_MSEC: int = int(MpManager.JOIN_SNAPSHOT_WAIT * 1000.0)

## Colours, and they all come off `HudTheme` — see the file banner.
const COLOR_GROUND: Color = Color(HudTheme.INK, HudTheme.PANEL_ALPHA)
const COLOR_TEXT: Color = HudTheme.BONE

## `voice_chat.SELF_LEVEL_KEY`, mirrored rather than preloaded — the browser
## reports our own microphone and self-view under "me", never under our lobby
## id (see `is_hero_speaking`). `event_log_selfcheck` binds the two spellings
## the way `hero_hud_selfcheck` binds the mic numbers.
const SELF_KEY: String = "me"

## `voice_chat.Mode.PUSH_TO_TALK`, mirrored rather than preloaded (the SELF_KEY
## precedent — bead godot-test1-tgx): under push-to-talk every key press and
## release would print a mic on/off pair and churn the six-line ring, while the
## held key itself is the indicator the log would duplicate. Local tx lines are
## drawn in activity mode only; the state is still tracked, so leaving PTT
## diffs honestly. `event_log_selfcheck` binds the two spellings.
const VOICE_MODE_PTT: int = 1

## Cached room + voice + player references, re-fetched when they go away.
var _mp: Node = null
var _voice: Node = null
var _player: Node = null

## Tick accumulator (seconds). The frame path is this add and one compare.
var _accum: float = 0.0

## The ring: `{ "text": String, "born": int }` (msec on the log's clock),
## oldest first. Compared by `_process`, painted by `_draw`, never the same.
var _lines: Array = []

## Room clock: msec the current room started, on the log's clock. Re-armed on
## every join; the mm:ss stamp is born-minus-start.
var _room_start_msec: int = 0
## Tick clock: 2 Hz ticks since the node existed. The per-peer camera grace
## counts ticks off first sightings (see `_member_since`).
var _tick_count: int = 0
## First tick each lobby id was seen in the room, stamped in `_seed_room()`
## for the initial set and in `_diff_members()` for joiners. A camera inside
## its id's grace baselines silently; past it, it prints. Never stamped for
## "me" (the self-view is not a lobby id): a self camera appearing mid-room
## is news, and the seed baselines the opening set silently anyway.
var _member_since: Dictionary = {}
## Whether the baselines below describe the room we are in. False reseeds
## everything silently — the join that must not flood the log with four swaps.
var _baselined: bool = false
## Late arrivals reseed their own domain silently: a player or voice module
## that appears mid-room must not report its standing state as events.
var _capt_seeded: bool = false
var _vox_seeded: bool = false

## Last-tick snapshots. `_members` is id -> display name; `_holders` is hero ->
## lobby id; `_captives` is hero -> true; `_speech_on` / `_video` are id ->
## true, with `_speech_quiet` counting consecutive silent ticks per id.
var _members: Dictionary = {}
var _holders: Dictionary = {}
var _captives: Dictionary = {}
var _tx: bool = false
var _speech_on: Dictionary = {}
var _speech_quiet: Dictionary = {}
var _video: Dictionary = {}
var _deafened: bool = false

## Our own lobby id, captured in `_seed_room()` while `my_id()` still answers.
## `leave()` clears it to "" in the same call that drops us offline, so asking
## the manager at room-loss time would report every member — including us — as
## disconnected (review round 1).
var _my_id: String = ""

## Last painted snapshot: line texts plus per-line alpha steps, so the fade
## repaints on step changes and on nothing else.
var _painted: Array = []

## Clock override, msec, or -1 for the wall clock. A headless check sets it and
## drives fades and TTLs without sleeping; the shipped game never touches it.
var _now_msec: int = -1


func _ready() -> void:
	add_to_group("event_log")
	theme = HudTheme.theme()
	# An overlay must never eat clicks or steal focus (the HUD voice-switch
	# precedent asserts FOCUS_NONE on its own buttons for the same reason).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _now() -> int:
	"""Msec on the log's clock — the wall, or the check's override."""
	if _now_msec >= 0:
		return _now_msec
	return Time.get_ticks_msec()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_INTERVAL:
		return
	_accum = 0.0
	_tick()


func _tick() -> void:
	## One 2 Hz snapshot compare: append lines on DIFF, age the ring, repaint
	## only when the painted snapshot moved.
	_tick_count += 1
	if _mp == null or not is_instance_valid(_mp):
		_mp = get_tree().get_first_node_in_group("mp") if is_inside_tree() else null
	if _voice == null or not is_instance_valid(_voice):
		_voice = get_tree().get_first_node_in_group("voice") if is_inside_tree() else null
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var online: bool = _mp != null and _mp.has_method("is_online") \
		and _mp.has_method("get_members") and bool(_mp.is_online())
	var voice_ok: bool = _voice != null and _voice.has_method("is_available") \
		and bool(_voice.is_available())
	if not online:
		_lose_room()
		# The room is gone but its lines are not: they age out on screen
		# (review round 1 — a "disconnected" nobody can see is no line).
		_age_lines()
		_repaint_on_change()
		return
	if not _baselined:
		_seed_room()
	# The room domains track with or without a voice module, so a join during
	# an outage is late rather than lost. The voice domain below is the only
	# one gated: it reseeds on return instead, or its standing state would
	# flood back as events. Either way the node draws nothing voiceless (see
	# `_draw`) — tracking is not painting.
	_diff_members()
	_diff_holders()
	_diff_captives()
	if not voice_ok:
		_vox_seeded = false
		_age_lines()
		_repaint_on_change()
		return
	_diff_voice()
	_age_lines()
	_repaint_on_change()


func _lose_room() -> void:
	## The room went away (or never existed): everyone we held gets a
	## "disconnected" line, and every baseline is forgotten so the next join
	## reseeds silently instead of reporting standing state as events.
	if _baselined:
		for id: String in _members:
			if id == _my_id:
				continue
			_append(tr("%s disconnected") % _members[id])
		_baselined = false
	_members = {}
	_holders = {}
	_captives = {}
	_tick_count = 0
	_member_since = {}
	_tx = false
	_speech_on = {}
	_speech_quiet = {}
	_video = {}
	_deafened = false
	_my_id = ""
	_capt_seeded = false
	_vox_seeded = false


func _seed_room() -> void:
	## A new room: forget the old log (its mm:ss belonged to another room),
	## stamp the clock, and read every domain once WITHOUT appending. Captives
	## seed only with a live player in hand — a player arriving mid-room
	## reseeds through `_capt_seeded` instead, or its standing cell reads as a
	## fresh grab.
	_lines.clear()
	_room_start_msec = _now()
	if _mp != null and _mp.has_method("my_id"):
		_my_id = str(_mp.my_id())
	_members = _read_members()
	for id: String in _members:
		_member_since[id] = _tick_count
	_holders = _read_holders()
	_captives = _read_captives()
	_capt_seeded = _player != null and is_instance_valid(_player)
	_tx = _read_tx()
	_speech_on = _read_speaking()
	_speech_quiet = {}
	_video = _read_video()
	_vox_seeded = true
	_deafened = _read_deafened()
	_baselined = true


func _read_members() -> Dictionary:
	"""Lobby id -> display name, us included. Empty with no manager."""
	var out: Dictionary = {}
	if _mp == null or not _mp.has_method("get_members"):
		return out
	for row: Variant in _mp.get_members():
		if row is Dictionary and str((row as Dictionary).get("id", "")) != "":
			out[str((row as Dictionary)["id"])] = _clean_name(
				str((row as Dictionary).get("name", "")))
	return out


func _clean_name(name: String) -> String:
	## A member name is drawn on one line, so line breaks are flattened. Names
	## are lobby input, so this is hygiene, not style; a "%" in a name is safe
	## as-is (it is the substitution ARGUMENT, never the format).
	if name.is_empty():
		return "?"
	return name.replace("\n", " ").replace("\r", " ")


func _hero_names() -> PackedStringArray:
	"""The roster, in `CHARACTERS` order — the heroes a swap can name."""
	var out := PackedStringArray()
	for entry: Variant in PLAYER_SCRIPT.CHARACTERS:
		out.append(String((entry as Dictionary)["name"]))
	return out


func _read_holders() -> Dictionary:
	"""Hero -> lobby id holding him, for heroes somebody holds."""
	var out: Dictionary = {}
	if _mp == null or not _mp.has_method("hero_holder"):
		return out
	for hero: String in _hero_names():
		var holder := str(_mp.hero_holder(hero))
		if holder != "":
			out[hero] = holder
	return out


func _read_captives() -> Dictionary:
	"""Hero -> true for heroes in a cell. Empty with no (or an old) player."""
	var out: Dictionary = {}
	if _player == null or not is_instance_valid(_player):
		return out
	if not ("captive_heroes" in _player):
		return out
	var set: Variant = _player.get("captive_heroes")
	if set is Dictionary:
		for hero: Variant in (set as Dictionary):
			out[str(hero)] = true
	return out


func _read_tx() -> bool:
	"""Is the LOCAL microphone transmitting? False with no voice seam."""
	if _voice == null or not _voice.has_method("is_tx"):
		return false
	return bool(_voice.is_tx())


func _local_tx_muted() -> bool:
	"""Are local mic lines suppressed? True under push-to-talk (see
	VOICE_MODE_PTT). False with no voice seam, or a module too old to name a
	mode — the back-compat default is drawn lines, not silence."""
	if _voice == null or not _voice.has_method("get_mode"):
		return false
	return int(_voice.get_mode()) == VOICE_MODE_PTT


func _read_speaking() -> Dictionary:
	"""Member id -> true for peers making noise right now (the module's held
	levels). A silent peer is indistinguishable from a muted one — see the
	banner — so this set IS the per-peer "mic on" truth."""
	var out: Dictionary = {}
	if _voice == null or not _voice.has_method("is_speaking"):
		return out
	for id: String in _members:
		if bool(_voice.is_speaking(id)):
			out[id] = true
	return out


func _read_video() -> Dictionary:
	"""Member id -> true for peers SENDING video (the module's sender
	roll-call, read through its one accessor — never the placed tiles, so a
	capture reads as nothing at all). The self-view reads as our own id so
	every camera line names a member the same way."""
	var out: Dictionary = {}
	if _voice == null or not _voice.has_method("video_peer_ids"):
		return out
	var holders: Array = _voice.video_peer_ids()
	var me := ""
	if _mp != null and _mp.has_method("my_id"):
		me = str(_mp.my_id())
	for id: Variant in holders:
		if str(id) == SELF_KEY:
			if me != "":
				out[me] = true
		elif _members.has(str(id)):
			out[str(id)] = true
	return out


func _read_deafened() -> bool:
	"""Are we deafened? False with no voice seam."""
	if _voice == null or not _voice.has_method("is_deafened"):
		return false
	return bool(_voice.is_deafened())


func _member_name(id: String) -> String:
	"""That member's display name, or the raw id for a peer the roster never
	named (a hold outliving its holder by milliseconds)."""
	return str(_members.get(id, id))


func _my_name() -> String:
	"""Our own display name, for the local mic lines."""
	if _mp != null and _mp.has_method("my_id"):
		return _member_name(str(_mp.my_id()))
	return "?"


func _stamp() -> String:
	"""mm:ss of room time, the prefix on every appended line."""
	var sec: int = int((_now() - _room_start_msec) / 1000)
	return "%02d:%02d" % [sec / 60, sec % 60]


func _append(line: String) -> void:
	## Ring-append one already-composed line: newest at the bottom, the oldest
	## scrolling off past MAX_LINES.
	_lines.append({"text": "[%s] %s" % [_stamp(), line], "born": _now()})
	while _lines.size() > MAX_LINES:
		_lines.pop_front()


func _diff_members() -> void:
	var cur := _read_members()
	for id: String in cur:
		if not _members.has(id):
			_member_since[id] = _tick_count
			_append(tr("%s joined") % cur[id])
	for id: String in _members:
		if not cur.has(id):
			_append(tr("%s left") % _members[id])
	_members = cur


func _diff_holders() -> void:
	var cur := _read_holders()
	for hero: String in cur:
		if str(_holders.get(hero, "")) != cur[hero] and cur[hero] != "":
			_append(tr("%s now plays %s") % [_member_name(cur[hero]), hero.capitalize()])
	_holders = cur


func _captives_settled() -> bool:
	## May the captive set be diffed yet? The live manager answers through its
	## own settle test; anything else runs the clock against the room start.
	if _mp != null and _mp.has_method("_join_settled"):
		return bool(_mp.call("_join_settled"))
	return _now() - _room_start_msec >= CAPTIVE_SETTLE_MSEC


func _diff_captives() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var cur := _read_captives()
	if not _capt_seeded:
		_captives = cur
		_capt_seeded = true
		return
	if not _captives_settled():
		# Still inside the join settle window: keep re-baselining silently.
		_captives = cur
		return
	for hero: String in cur:
		if not _captives.has(hero):
			_append(tr("%s was captured") % hero.capitalize())
	for hero: String in _captives:
		if not cur.has(hero):
			_append(tr("%s was freed") % hero.capitalize())
	_captives = cur


func _diff_voice() -> void:
	if not _vox_seeded:
		_tx = _read_tx()
		_speech_on = _read_speaking()
		_speech_quiet = {}
		_video = _read_video()
		_deafened = _read_deafened()
		_vox_seeded = true
		return
	var tx := _read_tx()
	if tx != _tx:
		if not _local_tx_muted():
			if tx:
				_append(tr("%s: mic on") % _my_name())
			else:
				_append(tr("%s: mic off") % _my_name())
		_tx = tx
	# Speech edges, DEBOUNCED (review round 1 — see MIC_OFF_SILENT_TICKS):
	# "on" is immediate, "off" needs three silent ticks in a row. A peer who
	# leaves mid-sentence is scrubbed with the roster, silently — the "left"
	# line already said it.
	var speaking := _read_speaking()
	for id: String in speaking:
		_speech_quiet[id] = 0
		if not _speech_on.has(id):
			_append(tr("%s: mic on") % _member_name(id))
			_speech_on[id] = true
	for id: String in _speech_on.keys():
		if speaking.has(id):
			continue
		if not _members.has(id):
			_speech_on.erase(id)
			_speech_quiet.erase(id)
			continue
		var quiet: int = int(_speech_quiet.get(id, 0)) + 1
		_speech_quiet[id] = quiet
		if quiet >= MIC_OFF_SILENT_TICKS:
			_append(tr("%s: mic off") % _member_name(id))
			_speech_on.erase(id)
			_speech_quiet.erase(id)
	for id: String in _video.keys():
		if not _members.has(id):
			_video.erase(id)
	var video := _read_video()
	for id: String in video:
		if _video.has(id):
			continue
		# Still inside THIS ID's grace: a standing camera, absorbed by the
		# `_video = video` below with no line. Past it the camera is news.
		# Unstamped ids (notably "me", which is no lobby id) read as news —
		# the seed baselines the opening set silently anyway.
		var since: int = int(_member_since.get(id, -1000000))
		if _tick_count - since > CAMERA_GRACE_TICKS:
			_append(tr("%s: camera on") % _member_name(id))
	for id: String in _video:
		if not video.has(id):
			_append(tr("%s: camera off") % _member_name(id))
	_video = video
	var deaf := _read_deafened()
	if deaf != _deafened:
		_append(tr("Undeafened") if not deaf else tr("Deafened"))
		_deafened = deaf


func _age_lines() -> void:
	"""Drop lines past LINE_TTL. The fade needs no write: `_draw` derives the
	quantized alpha from the birth it already holds."""
	var cutoff: int = _now() - int(LINE_TTL * 1000.0)
	while not _lines.is_empty() and int((_lines[0] as Dictionary)["born"]) <= cutoff:
		_lines.pop_front()


func line_alpha_at(age_msec: int) -> float:
	"""That age's paint alpha, QUANTIZED: full until the last FADE_TAIL, then
	FADE_STEPS steps to zero — a pure function, so `_draw` and the check agree
	by construction. Past TTL is zero (the line is already dropped above)."""
	var ttl := int(LINE_TTL * 1000.0)
	if age_msec >= ttl:
		return 0.0
	var tail := int(FADE_TAIL * 1000.0)
	if age_msec < ttl - tail:
		return 1.0
	var left: int = ttl - age_msec
	return float(int(ceil(float(left) / float(tail) * float(FADE_STEPS)))) / float(FADE_STEPS)


func line_count() -> int:
	"""Lines in the ring — the headless-readable half of `_draw`."""
	return _lines.size()


func line_text(index: int) -> String:
	"""That line's composed text, or "" out of range."""
	if index < 0 or index >= _lines.size():
		return ""
	return str((_lines[index] as Dictionary)["text"])


func line_alpha(index: int) -> float:
	"""That line's current paint alpha, or 0.0 out of range."""
	if index < 0 or index >= _lines.size():
		return 0.0
	return line_alpha_at(_now() - int((_lines[index] as Dictionary)["born"]))


func _repaint_on_change() -> void:
	## The HUD widget idiom: repaint only when the painted snapshot moved — a
	## line added or dropped, or a fade step changed. The timestamp text is
	## composed at birth and never rewritten, so it cannot move this.
	var painted: Array = []
	for i: int in _lines.size():
		painted.append([line_text(i), line_alpha(i)])
	if painted != _painted:
		_painted = painted
		queue_redraw()


func would_paint() -> bool:
	## The paint gate, headless-readable: something to show, and a voice
	## module to show it for. Deliberately NOT the room — the offline tick
	## ages the ring instead of clearing it, so a "disconnected" fades out on
	## screen after leaving (review round 1: a line nobody can see is no line).
	## Solo stays silent through the empty snapshot; a voiceless room through
	## the voice gate.
	if _painted.is_empty():
		return false
	return _voice != null and _voice.has_method("is_available") \
		and bool(_voice.is_available())


func _draw() -> void:
	## Painted from the tick snapshot only, through `would_paint()`.
	if not would_paint():
		return
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_GROUND)
	var font: Font = HudTheme.body_font()
	var y := float(HudTheme.CARD_PADDING) + float(HudTheme.BODY_FONT_SIZE)
	for i: int in _painted.size():
		var color := Color(COLOR_TEXT, float((_painted[i] as Array)[1]))
		font.draw_string(get_canvas_item(), Vector2(float(HudTheme.CARD_PADDING), y),
			str((_painted[i] as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			HudTheme.BODY_FONT_SIZE, color)
		y += float(HudTheme.BODY_FONT_SIZE) + 4.0
