extends SceneTree
## ============================================================================
## VOICE SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/voice_selfcheck.gd
##
## Guards the PURE HALF of the voice layer (epic `godot-test1-xtr`): the parser,
## the relay gate, the mode setting, the mic key and the two things about this
## feature that a headless machine can still see — that it is inert off-web and
## that it never stops under a pause. Explicit `if`s rather than `assert`s, for
## the reason `mp_selfcheck.gd` gives: asserts are stripped from release builds
## and this file's value is that it still works against one a year from now.
##
## WHAT IT CANNOT SEE, and why that is the whole shape of the file: voice is a
## browser feature. `getUserMedia`, `RTCPeerConnection`, the `<audio>` elements
## and every level meter live behind `JavaScriptBridge`, which does not exist on
## a headless build at all. So nothing below asserts anything about media. What
## it asserts is the GDScript that decides WHAT CROSSES THE BRIDGE — which is
## also exactly the half a hostile peer can reach.
##
## WHAT IT GUARDS, and why each is worth a check:
##
##  1. **THE PARSER**, `MpCodec.decode_vc()`. A `vc` payload rides the same open
##     lobby relay as the mesh's own signalling, so it is unvalidated peer input;
##     its next stop is a `JavaScriptBridge` call on a SINGLE-THREADED web export,
##     which is main-thread cost a hostile peer would otherwise set the size of.
##     Driven against the shapes a peer that is not speaking this protocol sends,
##     with honest offer/answer/ice round-trips beside them — a parser that
##     answered `{}` for everything would pass every rejection on its own.
##
##  2. **THE MEMBERSHIP GATE**, on a REAL `MpManager` rather than read as text.
##     Room codes are public over `/rooms`, so the relay reaches anyone who ever
##     joined; a peer that has left must not still be able to renegotiate
##     somebody's microphone. The bead offered a textual reading of the arm as
##     the cheap option — this drives `_on_lobby_relay()` itself instead
##     (`mp_selfcheck._room_manager`'s idiom: the real object with no socket
##     under it), because a text scan proves the CALL is written and not that the
##     payload is really dropped. The `no mp key -> return` precedence is driven
##     the same way, with a payload carrying neither key.
##
##  3. **THE MODE SURVIVES A RESTART AND THE MIC DOES NOT.** Owner ruling
##     2026-09-04: the default is always-on WITH THE MIC STARTING OFF. So the
##     mode round-trips through the store and a fresh node's `_tx` is false
##     whatever the store said — the second half is the ruling, and it is the
##     half a "restore what you had" refactor would quietly break. A corrupted
##     stored value falls back to the default rather than to push-to-talk, which
##     is the safe direction (a hold-to-talk key nobody knows about is a mic that
##     never opens; the reverse is a mic that never closes).
##
##  4. **V IS FREE.** `voice_mic` is a rebindable gameplay action, but the key it
##     ships bound to still has to be free on the day it ships, against BOTH real
##     sources: every other input action, and every raw-keycode panel constant.
##     `city_map_selfcheck`'s registry and scanner, borrowed rather than copied —
##     the `debug_teleport_selfcheck` precedent — so a future panel key is
##     compared here the day its constant lands.
##
##  5. **THE HELP ROW.** `help_selfcheck` already asserts the card carries a row
##     for every action globally; this is one line so that a deleted voice row
##     names the voice feature in its failure instead of a card table.
##
##  6. **NO JS BOOLEAN CROSSES THE BRIDGE.** Godot 4.5.stable's web template
##     marshals a JS boolean back through `JavaScriptBridge` as a corrupted
##     Variant (bd memory `godot-test1-web-builds-godot-4-5-stable`, and the
##     whole of `godot-test1-8f8`). `intro_selfcheck` scans every `scripts/*.gd`
##     for the three shapes; this one reads the `VOICE_JS` module out of
##     `voice_chat.gd` AS TEXT and scans that block alone, so the failure names
##     the voice module and cannot be diluted by a rename of the file.
##
## 6b. **THE VALUES `VOICE_JS` MIRRORS BY HAND.** A string of JavaScript cannot
##     `preload` a `Color` or a `const`, so the cartoon camera's film palette
##     (bead `godot-test1-xtr.11`) and the self-view's reserved tile key (bead
##     `godot-test1-xtr.14`) are typed twice. The palette in particular CANNOT be
##     bound by `hero_hud_selfcheck` check 8's hex grep — it is deliberately
##     written as rgb triples so that grep does not fire — so it is bound here by
##     value instead.
##
## 6f. **THE FACE CROP'S VENDORING** (bead `godot-test1-xtr.12`). The detector's
##     worst failure is the invisible one: a vendored file lost, a url renamed or
##     the `build.yml` copy deleted all land on the centre crop, which is the MVP
##     and looks like a working game. So every `faceUrl()` in the module is
##     checked against the tree, the licence is checked beside it, `build.yml` is
##     read for the copy AND its assertion, and `cropBox` is read for the centre
##     square that IS the fallback rung. The arithmetic is deliberately not here
##     — a wrong lerp shows up in one glance at a tile.
##
##  7. **INERT OFF-WEB.** Every public method called on a real node on a build
##     with no bridge at all: an unguarded `JavaScriptBridge` touch is a
##     `SCRIPT ERROR`, which CI treats as red, and a runtime error would abort
##     the function and let this file print OK anyway (hence the sentinel). The
##     driven list is checked FOR COMPLETENESS against the script's own method
##     list, so a public method added by a later voice bead is covered the day it
##     lands rather than the day somebody remembers this file.
##
##  8. **PROCESS_MODE_ALWAYS.** Voice keeps flowing under every overlay and under
##     the room-wide P (epic ruling): the media path is the browser's and never
##     stops, so a GD half that stopped would stall a handshake mid-flight.
##     `pause_selfcheck` owns "nothing assigns `.paused`" globally; the assertion
##     here is that this file is in that population and that the node really
##     carries the mode.
##
## 8b. **`debug_line()` ANSWERS SOMETHING IN A ROOM** (bead `godot-test1-xtr.15`).
##     Check 7 meets it only off-web, where it returns on its first line — so an
##     EMPTY answer in a real browser room failed nothing here. This forces
##     `_is_web` on over a `RoomStub` (check 7b's idiom in `hero_hud_selfcheck`)
##     and drives the mode and transmit halves at both ends, with "out of the
##     room it is empty" as the negative control. The \fo ROW is the other half
##     and lives in `perf_selfcheck` guard 7, which drives a real overlay under a
##     real pause — that is where the shipped bug actually was.
##
##  9. **WHAT V ACTUALLY DOES**, driven on the shipped `_poll_input()` with
##     `Input.action_press` / `action_release` (`mobile_input`'s synthesis idiom,
##     and no bridge needed because `_tx` is GDScript state). Always-on TOGGLES,
##     push-to-talk HOLDS, and a mode switch while the key is held drops the mic
##     — the last is the one that leaks an open microphone if it regresses.
##
## 10. **HUD VOICE / CAMERA SWITCHES ABOVE MP BUTTON** (bead `godot-test1-xtr.20`).
##     Guards the three switches stacked above the MP button on the gameplay HUD:
##     one state and two views (shared handlers, lockstep labels across HUD and panel,
##     mutual sync in both directions, camera blocked reporting, visibility gated
##     on available and online, zero second state variables declared).
##
## ...and OVER ALL TEN, the completion sentinel: a GDScript runtime error aborts
## only the function it lands in, so a check that dies halfway simply stops
## asserting and the file prints OK. See `scripts/selfcheck_sentinel.gd`.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const VoiceChat := preload("res://scripts/voice_chat.gd")
const HelpOverlay := preload("res://scripts/help_overlay.gd")
const CityMapSelfcheck: GDScript = preload("res://scripts/city_map_selfcheck.gd")
const IntroSelfcheck: GDScript = preload("res://scripts/intro_selfcheck.gd")
## The roster the hero accessories (bead `godot-test1-xtr.13`) are bound to. The
## SCRIPT, never an instance: `CHARACTERS` is a const and nothing here needs a
## body to ask it.
const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")
const MultiplayerUIScript: GDScript = preload("res://scripts/mp_ui.gd")

## The action the whole of bead `godot-test1-xtr.2` hangs off.
const MIC_ACTION: StringName = &"voice_mic"

## A `Node` in group `"mp"` reduced to the ONE method `VoiceChat._is_in_room()`
## asks for. It is a stub and not a real `MpManager` on purpose: check 9 is about
## the key, and a real manager would drag a lobby, a socket and a state machine
## into a question that only needs "yes, there is a room".
class RoomStub extends Node:
	var online: bool = true

	func is_online() -> bool:
		return online


## The two questions `_tile_fraction` asks a hero row, and nothing else. A real
## `hero_hud` would drag the whole portrait widget into a question about ONE early
## return; `hero_hud_selfcheck` owns the real row, and this owns the refusal.
class RowStub extends Node:
	var captive: String = ""

	func tile_state(hero: String) -> int:
		return VoiceChat.HERO_HUD_STATE_CAPTIVE if hero == captive else 0

	func tile_rect(_hero: String) -> Rect2:
		return Rect2(0.0, 0.0, 80.0, 80.0)


## A stub voice node for driving `mp_ui.gd` (check 10, bead `godot-test1-xtr.20`).
## Answers `is_available()` and the six seams: set_mic_muted / is_mic_muted /
## set_deafened / is_deafened / set_camera_enabled / is_camera_on / camera_denied.
class VoiceUiStub extends Node:
	var available: bool = true
	var mic_muted: bool = false
	var deafened: bool = false
	var camera_on: bool = false
	var denied: bool = false
	var mode: int = 0
	var tx: bool = false

	signal mode_changed(mode: int)
	signal tx_changed(tx: bool)
	signal mic_denied_changed(denied: bool)
	signal camera_changed(on: bool)

	func is_available() -> bool:
		return available

	func is_mic_muted() -> bool:
		return mic_muted

	func set_mic_muted(v: bool) -> void:
		mic_muted = v

	func is_deafened() -> bool:
		return deafened

	func set_deafened(v: bool) -> void:
		deafened = v

	func is_camera_on() -> bool:
		return camera_on

	func set_camera_enabled(v: bool) -> void:
		camera_on = v

	func camera_denied() -> bool:
		return denied

	func get_mode() -> int:
		return mode

	func is_tx() -> bool:
		return tx


var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before it answers null to `get_tree()` — the lesson
	# `pause_selfcheck` and `minimap_selfcheck` both record at length.
	await process_frame

	_check_vc_parser()
	_check_relay_gate()
	_check_setting_roundtrip()
	_check_volume_roundtrip()
	_check_mic_key_free()
	_check_help_row()
	_check_no_js_bool()
	_check_style_mirrors()
	_check_ice_restart()
	_check_video_health()
	_check_sender_heal()
	_check_face_crop()
	_check_inert_offweb()
	_check_always_process()
	_check_debug_line_in_a_room()
	await _check_mic_key_semantics()
	_check_hud_voice_switches()

	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for line: String in _failures:
		printerr("FAIL: " + line)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE PARSER — `MpCodec.decode_vc()` against hostile payloads
# ============================================================================

func _check_vc_parser() -> void:
	"""
	THE HONEST PAYLOADS ARE TESTED FIRST AND THEY ARE THE POINT: a parser that
	answered `{}` for everything would pass every rejection below, so the
	acceptances are what stop this check being vacuous — `mp_selfcheck`'s rule for
	its seven sibling trust boundaries, one family along.
	"""
	# --- The acceptances, byte for byte -------------------------------------
	var sdp: String = "v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
	for kind: String in ["offer", "answer"]:
		var out: Dictionary = MpCodec.decode_vc({"vc": kind, "sdp": sdp})
		if out.get("vc", "") != kind or out.get("sdp", "") != sdp:
			_fail("decode_vc mangled an honest %s: %s" % [kind, str(out)])

	# An ICE batch, with the two shapes that are legitimate and look wrong: an
	# END-OF-CANDIDATES marker is an EMPTY `cand` and must survive (it is what
	# tells the far end gathering is finished), and `mline` arrives from the LOBBY
	# RELAY, where `JSON.parse_string` hands every number back as a FLOAT.
	var ice: Dictionary = MpCodec.decode_vc({"vc": "ice", "c": [
		{"cand": "candidate:1 1 udp 2113937151 192.0.2.1 50000 typ host", "mid": "0", "mline": 0.0},
		{"cand": "", "mid": "audio", "mline": 3.0},
	]})
	var batch: Array = ice.get("c", []) as Array
	if ice.get("vc", "") != "ice" or batch.size() != 2:
		_fail("decode_vc dropped an honest ice batch: %s" % str(ice))
	elif not batch[0].get("cand", "").begins_with("candidate:") \
			or batch[1].get("cand", null) != "" \
			or typeof(batch[1].get("mline", null)) != TYPE_INT \
			or int(batch[1]["mline"]) != 3:
		_fail("decode_vc mangled an honest ice batch: %s" % str(batch))

	# --- ...and everything a peer that is not speaking this protocol sends ---
	var long_sdp: String = "v".repeat(MpCodec.MAX_VC_SDP + 1)
	var long_mid: String = "m".repeat(MpCodec.MAX_VC_MID + 1)
	var long_cand: String = "c".repeat(MpCodec.MAX_VC_CAND + 1)
	var overflow: Array = []
	for i: int in MpCodec.MAX_VC_ICE + 1:
		overflow.append({"cand": "candidate:%d" % i, "mid": "0", "mline": 0})
	var hostile: Array[Dictionary] = [
		{"sdp": sdp},                                          # no `vc` at all
		{"vc": 7, "sdp": sdp},                                 # `vc` is a number
		{"vc": "chat", "sdp": sdp},                            # a kind this build does not know
		{"vc": "offer"},                                       # no sdp
		{"vc": "offer", "sdp": 1},                             # sdp is an int
		{"vc": "offer", "sdp": true},                          # ...or a bool
		{"vc": "offer", "sdp": null},                          # ...or null
		{"vc": "offer", "sdp": []},                            # ...or an array
		{"vc": "offer", "sdp": ""},                            # ...or empty
		{"vc": "answer", "sdp": long_sdp},                     # over MAX_VC_SDP
		{"vc": "ice"},                                         # no candidate array
		{"vc": "ice", "c": "candidate:1"},                     # `c` is a string
		{"vc": "ice", "c": []},                                # ...or empty
		{"vc": "ice", "c": overflow},                          # ...or over MAX_VC_ICE
		{"vc": "ice", "c": ["candidate:1"]},                   # entry is not a dictionary
		{"vc": "ice", "c": [{"mid": "0", "mline": 0}]},        # no cand
		{"vc": "ice", "c": [{"cand": 1, "mid": "0", "mline": 0}]},      # cand is a number
		{"vc": "ice", "c": [{"cand": null, "mid": "0", "mline": 0}]},   # ...or null
		{"vc": "ice", "c": [{"cand": long_cand, "mid": "0", "mline": 0}]},
		{"vc": "ice", "c": [{"cand": "x", "mid": "", "mline": 0}]},     # mid is empty
		{"vc": "ice", "c": [{"cand": "x", "mid": long_mid, "mline": 0}]},
		{"vc": "ice", "c": [{"cand": "x", "mid": 0, "mline": 0}]},      # mid is a number
		{"vc": "ice", "c": [{"cand": "x", "mid": "0"}]},                # no mline
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": "0"}]},  # mline is a string
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": 1.5}]},  # ...a JSON float where an int is meant
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": -1}]},   # ...negative
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": MpCodec.MAX_VC_MLINE + 1}]},
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": INF}]},  # ...or not finite at all
		{"vc": "ice", "c": [{"cand": "x", "mid": "0", "mline": NAN}]},
	]
	for payload: Dictionary in hostile:
		if not MpCodec.decode_vc(payload).is_empty():
			_fail("decode_vc accepted the hostile payload %s" % str(payload))
	Sentinel.done("vc_parser")


# ============================================================================
# 2. THE MEMBERSHIP GATE — driven on a real MpManager
# ============================================================================

func _check_relay_gate() -> void:
	"""
	`_on_lobby_relay()` -> `_forward_voice()`, on the REAL object with no socket
	and no mesh under it (`mp_selfcheck._room_manager`'s idiom). Both gates are
	`mp_manager`'s job rather than the voice module's, and neither can be seen by
	reading the arm: what has to be true is that nothing is EMITTED.
	"""
	var mp: Node = MpManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	# `_forward_voice` walks `_members` and reads nothing else — no lobby, no
	# state machine and no socket are involved in either gate.
	mp._members = [{"id": "alice", "name": "Alice"}]
	var seen: Array = []
	mp.voice_relay.connect(func(from: String, payload: Dictionary) -> void:
		seen.append([from, payload]))

	var sdp: String = "v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"

	# The POSITIVE CONTROL first, or every refusal below is satisfied by a seam
	# that forwards nothing at all.
	mp._on_lobby_relay("alice", {"vc": "offer", "sdp": sdp})
	if seen.size() != 1 or str(seen[0][0]) != "alice" \
			or (seen[0][1] as Dictionary).get("sdp", "") != sdp:
		_fail("a member's honest vc offer did not reach voice_relay (%d emissions)" % seen.size())
	seen.clear()

	# THE MEMBERSHIP GATE. Room codes are public, so the relay reaches anyone who
	# joined; a peer that has left must not be able to renegotiate a microphone.
	mp._on_lobby_relay("stranger", {"vc": "offer", "sdp": sdp})
	if not seen.is_empty():
		_fail("a vc payload from a non-member reached voice_relay — the relay is "
			+ "open to anyone who knows the room code")
	seen.clear()

	# THE SHAPE GATE, on the same arm: a member is still peer input.
	mp._on_lobby_relay("alice", {"vc": "offer", "sdp": 42})
	mp._on_lobby_relay("alice", {"vc": "chat", "sdp": sdp})
	if not seen.is_empty():
		_fail("a malformed vc payload from a MEMBER reached voice_relay — "
			+ "decode_vc is not on this path")
	seen.clear()

	# THE PRECEDENCE the bead names: `no mp key -> return` still runs above the
	# `mp` dispatch, so a payload with NEITHER key is ignored in silence rather
	# than reaching `str(payload["mp"])`, which would abort the handler.
	mp._on_lobby_relay("alice", {"hello": 1})
	mp._on_lobby_relay("alice", {})
	if not seen.is_empty():
		_fail("a payload with no vc key reached voice_relay")

	mp.free()
	Sentinel.done("relay_gate")


# ============================================================================
# 3. THE MODE ROUND-TRIPS, THE MIC DOES NOT
# ============================================================================

func _check_setting_roundtrip() -> void:
	"""
	Through the store seam `Sentinel.isolate_user_state()` already redirected, so
	this reads and writes a file private to this process and never the player's.
	Off-web `_load_mode()` / `_save_mode()` take the `ConfigFile` branch, which is
	the one a headless build can drive; the `localStorage` branch is the same two
	strings through `BestRunStore.ls_*` and has no headless existence at all.
	"""
	# A fresh profile is ALWAYS_ON — the default, and the owner's ruling.
	var first: Node = _voice_node()
	if first.get_mode() != VoiceChat.Mode.ALWAYS_ON:
		_fail("a voice node on an empty profile came up in %s, not ALWAYS_ON"
			% first.get_mode())

	# ...and switching it persists.
	first.set_mode(VoiceChat.Mode.PUSH_TO_TALK)
	first.free()
	var second: Node = _voice_node()
	if second.get_mode() != VoiceChat.Mode.PUSH_TO_TALK:
		_fail("PUSH_TO_TALK did not survive a restart — a fresh node loaded %s"
			% second.get_mode())

	# THE MIC STARTS OFF, whatever the store said. This is the owner's ruling of
	# 2026-09-04 and the half a "restore what you had" refactor breaks silently:
	# the MODE is remembered, the TRANSMIT state never is.
	if second.is_tx():
		_fail("a fresh node came up transmitting with PUSH_TO_TALK stored — "
			+ "the mic must start off in BOTH modes (owner ruling 2026-09-04)")
	second.free()

	# A CORRUPTED STORED VALUE falls back to the DEFAULT, not to push-to-talk: a
	# hold-to-talk key nobody was told about is a mic that never opens, and the
	# other direction is a mic that never closes.
	for junk: Variant in ["", "PUSH_TO_TALK", "2", 17, "always_on\n", {"mode": 1}]:
		var cfg := ConfigFile.new()
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "mode", junk)
		if cfg.save(BestRunStore.config_path) != OK:
			_fail("could not write the isolated store — check 3 would pass vacuously")
			break
		var node: Node = _voice_node()
		if node.get_mode() != VoiceChat.Mode.ALWAYS_ON:
			_fail("the stored value %s loaded as %s, not the ALWAYS_ON default"
				% [str(junk), node.get_mode()])
		if node.is_tx():
			_fail("a fresh node came up transmitting after a corrupted store")
		node.free()

	# ...and the honest spellings still load, or the fallback above is passing
	# because NOTHING is ever read.
	for spelling: String in ["push_to_talk", "1"]:
		var cfg := ConfigFile.new()
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "mode", spelling)
		cfg.save(BestRunStore.config_path)
		var node: Node = _voice_node()
		if node.get_mode() != VoiceChat.Mode.PUSH_TO_TALK:
			_fail("the stored spelling %s did not load as PUSH_TO_TALK" % spelling)
		node.free()

	DirAccess.remove_absolute(BestRunStore.config_path)
	Sentinel.done("setting_roundtrip")


# ============================================================================
# 3b. THE INCOMING VOLUME ROUND-TRIPS, CLAMPS, AND SURVIVES A DEAFEN
# ============================================================================

func _check_volume_roundtrip() -> void:
	"""
	The bead's four promises about the volume dial (godot-test1-xtr.9), driven
	through the same isolated store check 3 uses.

	The last one is the interesting one and the one a refactor breaks silently:
	DEAFEN AND VOLUME ARE SEPARATE AXES. Deafen is `<audio>.muted` and the volume
	is `<audio>.volume`, so "the volume is remembered under a deafen" holds with
	no code saving or restoring anything — and any future `set_deafened()` that
	starts writing the volume (to 0 on the way in, to 1 on the way out) turns this
	check red, which is exactly the mutation the bead named.
	"""
	# A fresh profile is FULL volume, and the constant is what says so.
	var first: Node = _voice_node()
	if not is_equal_approx(first.get_volume(), VoiceChat.VOLUME_DEFAULT):
		_fail("a voice node on an empty profile came up at volume %f, not the %f default"
			% [first.get_volume(), VoiceChat.VOLUME_DEFAULT])

	# CLAMPED, not rejected and not wrapped — a `<audio>.volume` outside 0..1
	# throws, so the GD side may never hand one across.
	for pair: Array in [[2.5, 1.0], [-1.0, 0.0], [1.0, 1.0], [0.0, 0.0], [0.4, 0.4]]:
		first.set_volume(float(pair[0]))
		if not is_equal_approx(first.get_volume(), float(pair[1])):
			_fail("set_volume(%f) settled at %f, expected %f"
				% [pair[0], first.get_volume(), pair[1]])

	# ...and it persists. 0.4 is what the loop above left set.
	first.free()
	var second: Node = _voice_node()
	if not is_equal_approx(second.get_volume(), 0.4):
		_fail("volume 0.4 did not survive a restart — a fresh node loaded %f"
			% second.get_volume())

	# DEAFEN DOES NOT TOUCH IT, in either direction.
	second.set_deafened(true)
	if not is_equal_approx(second.get_volume(), 0.4):
		_fail("deafening changed the volume to %f — deafen is `muted`, volume is "
			% second.get_volume() + "`volume`, and they are separate axes")
	second.set_deafened(false)
	if not is_equal_approx(second.get_volume(), 0.4):
		_fail("undeafening reset the volume to %f instead of leaving the remembered "
			% second.get_volume() + "0.4 alone (bead godot-test1-xtr.9's named mutation)")
	second.free()

	# A CORRUPTED STORED VALUE is FULL volume, never silence: a room that cannot
	# be heard and offers no reason why is the worst failure this dial has.
	for junk: Variant in ["", "loud", "-5", "101", 1.5, {"volume": 50}, "50.5"]:
		var cfg := ConfigFile.new()
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "volume", junk)
		if cfg.save(BestRunStore.config_path) != OK:
			_fail("could not write the isolated store — check 3b would pass vacuously")
			break
		var node: Node = _voice_node()
		if not is_equal_approx(node.get_volume(), VoiceChat.VOLUME_DEFAULT):
			_fail("the stored volume %s loaded as %f, not the %f default"
				% [str(junk), node.get_volume(), VoiceChat.VOLUME_DEFAULT])
		node.free()

	# ...and an honest one still loads, or the fallback above is passing because
	# NOTHING is ever read.
	var honest := ConfigFile.new()
	honest.set_value(BestRunStore.CONFIG_VOICE_SECTION, "volume", "35")
	honest.save(BestRunStore.config_path)
	var loaded: Node = _voice_node()
	if not is_equal_approx(loaded.get_volume(), 0.35):
		_fail("the stored volume 35 loaded as %f, not 0.35" % loaded.get_volume())
	loaded.free()

	DirAccess.remove_absolute(BestRunStore.config_path)
	Sentinel.done("volume_roundtrip")


func _voice_node() -> Node:
	"""A real `voice_chat.gd` in the tree, so `_ready()` (and with it `_load_mode()`
	and the web gate) has actually run."""
	var node := Node.new()
	node.set_script(VoiceChat)
	root.add_child(node)
	return node


# ============================================================================
# 4. V IS FREE
# ============================================================================

func _check_mic_key_free() -> void:
	"""
	`city_map_selfcheck`'s registry and scanner, borrowed rather than copied — the
	`debug_teleport_selfcheck` precedent. `voice_mic` IS an input action, so its
	own row is skipped when scanning the input map; the panel keys are raw
	keycodes outside the map and nothing in the engine would ever report one.
	"""
	if not InputMap.has_action(MIC_ACTION):
		_fail("the input map has no `%s` action — bead xtr.2's key does not exist" % MIC_ACTION)
		Sentinel.done("mic_key_free")
		return

	var keys: Array[int] = _mic_keycodes()
	if keys.is_empty():
		_fail("`%s` is bound to no key at all — it can never be pressed" % MIC_ACTION)
		Sentinel.done("mic_key_free")
		return

	for key: int in keys:
		# --- Against every OTHER input action -------------------------------
		# BARE PRESSES ONLY, `tower_lift_selfcheck`'s and `debug_teleport`'s rule:
		# Godot ships built-in `ui_text_*` actions on modified keys, and a modified
		# event is a different chord rather than a collision.
		for action: StringName in InputMap.get_actions():
			if action == MIC_ACTION:
				continue
			for event: InputEvent in InputMap.action_get_events(action):
				var as_key := event as InputEventKey
				if as_key == null:
					continue
				if as_key.ctrl_pressed or as_key.alt_pressed \
						or as_key.meta_pressed or as_key.shift_pressed:
					continue
				if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
					_fail("`%s` (%s) is also bound to the input action \"%s\""
						% [MIC_ACTION, OS.get_keycode_string(key), action])

		# --- ...and against every raw-keycode panel -------------------------
		var claimed: String = CityMapSelfcheck._owner_claiming(
			key, CityMapSelfcheck.panel_key_owners())
		if not claimed.is_empty():
			_fail("`%s` (%s) is already %s — a panel key is not rebindable, so both "
				% [MIC_ACTION, OS.get_keycode_string(key), claimed]
				+ "surfaces would fire on one press, forever")

	# NEGATIVE CONTROLS on the borrowed scanner, `city_map_selfcheck`'s own: two of
	# the rows in that registry are arrays of ARRAYS, and a flat probe alone passes
	# against a scanner that silently aborts on the nested ones.
	if CityMapSelfcheck._owner_claiming(keys[0], [[[keys[0]], "a fake flat owner"]]).is_empty():
		_fail("the borrowed key scan missed a fake FLAT owner — it cannot detect a real collision")
	if CityMapSelfcheck._owner_claiming(keys[0], [[[[keys[0]]], "a fake nested owner"]]).is_empty():
		_fail("the borrowed key scan missed a fake NESTED owner — the two nested rows "
			+ "in the registry are not really being compared")
	Sentinel.done("mic_key_free")


# ============================================================================
# 5. THE HELP ROW
# ============================================================================

func _check_help_row() -> void:
	"""
	`help_selfcheck` asserts this globally over its whole action table; the one
	line here exists so a deleted voice row fails with the VOICE feature's name on
	it. A key the player is never told about is a feature that does not exist.
	"""
	var keys: Array[int] = _mic_keycodes()
	if keys.is_empty():
		_fail("`%s` is bound to no key, so the help card cannot name one" % MIC_ACTION)
		Sentinel.done("help_row")
		return
	var legend: String = OS.get_keycode_string(keys[0])
	var found := false
	for row: Array in HelpOverlay.visible_rows(false):
		if String(row[0]).contains(legend) and String(row[1]).to_lower().contains("voice"):
			found = true
			break
	if not found:
		_fail("the desktop help card carries no row whose key names %s and whose "
			% legend + "description names voice — the mic key is undiscoverable")
	Sentinel.done("help_row")


func _mic_keycodes() -> Array[int]:
	var keys: Array[int] = []
	if not InputMap.has_action(MIC_ACTION):
		return keys
	for event: InputEvent in InputMap.action_get_events(MIC_ACTION):
		var as_key := event as InputEventKey
		if as_key == null:
			continue
		var code: int = int(as_key.physical_keycode)
		if code == 0:
			code = int(as_key.keycode)
		if code != 0 and not keys.has(code):
			keys.append(code)
	return keys


# ============================================================================
# 6. NO JS BOOLEAN CROSSES THE BRIDGE
# ============================================================================

func _check_no_js_bool() -> void:
	"""
	The `VOICE_JS` module read out of `voice_chat.gd` AS TEXT and scanned for the
	three shapes that hand a boolean back through `JavaScriptBridge` — the
	`intro_selfcheck` idiom, its constant, deliberately blunt. Godot 4.5.stable
	marshals a JS boolean into a corrupted Variant: `== true` is false and
	stringifying it aborts the reader silently (bd memory
	`godot-test1-web-builds-godot-4-5-stable`, bead `godot-test1-8f8`). A snippet
	that wants a boolean answer writes `? 1 : 0` and the reader compares
	numerically.
	"""
	# NEGATIVE CONTROL FIRST. Every assertion below is "we found nothing", which is
	# also what a matcher looking for the wrong thing reports.
	# (`intro_selfcheck`'s own global scan exempts `*_selfcheck.gd` precisely so a
	# check can hold the shape it is banning, which is why this reads plainly.)
	if _js_bool_offence("(function(){try{return !!s.done;}catch(e){return true;}})()").is_empty():
		_fail("the boolean-return matcher does not flag the snippet godot-test1-8f8 "
			+ "actually shipped — check 6 would pass vacuously")

	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — check 6 "
			% module.length() + "would pass vacuously")
		Sentinel.done("no_js_bool")
		return
	# The block has to be the real one, or the extraction is reading a comment.
	if not module.contains("window.ckVoice"):
		_fail("the extracted VOICE_JS block does not mention window.ckVoice — the "
			+ "extraction is reading the wrong text")
	if not module.contains("stats:"):
		_fail("the extracted VOICE_JS block does not export stats")
	var offence: String = _js_bool_offence(module)
	if not offence.is_empty():
		_fail("voice_chat.gd's VOICE_JS hands a JS boolean back over the bridge "
			+ "(`%s`) — answer `? 1 : 0` and compare numerically (godot-test1-8f8)"
			% offence)
	Sentinel.done("no_js_bool")


# ============================================================================
# 6b. THE THREE VALUES VOICE_JS MIRRORS BY HAND (beads xtr.11 / xtr.14)
# ============================================================================

func _check_style_mirrors() -> void:
	"""
	A string of JavaScript cannot `preload` anything, so the cartoon camera's film
	palette and the self-view's tile key are TYPED TWICE — once in GDScript, once
	inside `VOICE_JS`. That is the drift this check exists for, and both mirrors
	are load-bearing:

	  * `STYLE_INK` / `STYLE_BONE` are `HudTheme.INK` / `HudTheme.BONE` as rgb
	    triples, which is the shape they must be in: `hero_hud_selfcheck` check 8
	    greps `scripts/` for the six film HEXES and they may be typed in
	    `hud_theme.gd` alone (CLAUDE.md records the non-hex spelling as the
	    sanctioned escape). So they cannot be bound by that grep, and this binds
	    them by VALUE instead.
	  * `SELF_TILE` is `SELF_LEVEL_KEY`, the reserved key the self-view's tile and
	    the browser's own microphone level both travel under. A key that drifted
	    would put nobody's picture anywhere and say nothing about it.

	Read as TEXT, so the assertions are all "we found the right number" — which is
	also what a matcher looking in the wrong place would report if it found
	nothing. Each therefore fails LOUDLY on no match rather than passing.
	"""
	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — check 6b "
			% module.length() + "would pass vacuously")
		Sentinel.done("style_mirrors")
		return

	_check_js_triple(module, "STYLE_INK", HudTheme.INK)
	_check_js_triple(module, "STYLE_BONE", HudTheme.BONE)
	# AND THAT THEY ARE SPENT. Binding a DECLARATION says nothing about the paint
	# loop: an edge colour changed from `STYLE_INK` to a literal drifts from the
	# palette on every inked contour while the declaration still matches. That
	# mutation was driven and these three counts are what fail it — each name is
	# declared once and used at least once.
	# The counts are the REAL SITES, not a token floor: INK is declared, is the
	# ramp's ground band and is the ink the edge test paints; BONE is declared and
	# is the ramp's highlight. A threshold slack enough to survive losing one of
	# them is the vacuous check this is replacing.
	_check_js_used(module, "STYLE_INK", 3)
	_check_js_used(module, "STYLE_BONE", 2)

	var key := RegEx.create_from_string("var\\s+SELF_TILE\\s*=\\s*'([^']*)'")
	var hit: RegExMatch = key.search(module) if key != null else null
	if hit == null:
		_fail("VOICE_JS declares no `var SELF_TILE = '...'` — the self-view's "
			+ "reserved tile key (bead godot-test1-xtr.14) is unreadable, so this "
			+ "check cannot bind it to SELF_LEVEL_KEY")
	elif hit.get_string(1) != VoiceChat.SELF_LEVEL_KEY:
		_fail("VOICE_JS's SELF_TILE is '%s' but voice_chat.SELF_LEVEL_KEY is '%s' — "
			% [hit.get_string(1), VoiceChat.SELF_LEVEL_KEY]
			+ "the self-view's rect would be pushed under a key the browser does "
			+ "not draw")
	# Declared once, then asked by `tileEl`, by `tileLive` and by the two ends of
	# the self-view itself: four real sites, so losing any one of them to a
	# hard-coded 'me' takes the count under the floor.
	#
	# ponytail: the count is the binding, not a scan for stray `'me'` literals —
	# that fires on the word in a COMMENT, and a check that has to be worked
	# around by rewording prose is a check nobody keeps.
	_check_js_used(module, "SELF_TILE", 4)

	# --- THE FORCED RULE ITSELF (owner ruling 2026-09-06) -------------------
	# "A receiver never sees the raw face" is the whole of bead xtr.11, and until
	# these three lines it was asserted by NOTHING: `return S.styled ? S.styled :
	# S.cam;` ships the unstyled webcam and every check in the suite stays green.
	# Both halves are needed — the first says the send path asks for the styled
	# stream, the second says the styled stream is the only thing that answer can
	# ever be — because either alone leaves the other path open.
	var attach: String = _js_function_body(module, "attachCam")
	if attach.is_empty():
		_fail("VOICE_JS has no `function attachCam(` — check 6b cannot see what the "
			+ "send path attaches, which is the forced rule's whole subject")
	else:
		if not attach.contains("styleStream()"):
			_fail("attachCam does not ask styleStream() for its track — the cartoon "
				+ "(bead godot-test1-xtr.11) is FORCED for the room, so the styled "
				+ "canvas is the only source a sender may attach")
		if attach.contains("S.cam"):
			_fail("attachCam names S.cam — that is the RAW device, and the owner's "
				+ "ruling is that a receiver never sees the raw face")
	var forced := RegEx.create_from_string(
		"function\\s+styleStream\\(\\)\\s*\\{\\s*return S\\.styled;\\s*\\}")
	if forced == null or forced.search(module) == null:
		_fail("styleStream() is not exactly `return S.styled;` — a fallback there "
			+ "(`S.styled || S.cam`, `S.styled ? S.styled : S.cam`) is how the "
			+ "unstyled face reaches a peer on the one browser that cannot capture "
			+ "a canvas. The degrade is NO VIDEO (owner ruling 2026-09-06)")

	# --- THE STRENGTH KNOBS (bead godot-test1-xtr.16) -----------------------
	# The owner drives these from the browser console, so nothing in GDScript
	# calls them and nothing but this reads them. Four things have to hold, and
	# each is invisible in a diff: the SHIPPED defaults (a knob whose default
	# drifted silently restyles every room), the paint loop really reading them
	# (a leftover `STYLE_LEVELS` literal makes `setStyle(8, ...)` a no-op with an
	# undefined ramp slot behind it), the PERSISTENCE (an experiment that does not
	# survive a reload is not the knob that was asked for), and the four numbers
	# reaching \fo, which is where the owner reads back what is live.
	if not module.contains("var STYLE_DEFAULT = [8, 0.4, 0, 0.6];"):
		_fail("VOICE_JS declares no `var STYLE_DEFAULT = [8, 0.4, 0, 0.6]` — the "
			+ "cartoon camera's shipped look (the owner's own dial, bead "
			+ "godot-test1-xtr.22, superseding xtr.16's [4, 1.0, 1, 0.45]) is what "
			+ "the knobs fall back to and what a fresh profile paints; a drifted "
			+ "default restyles every room silently")
	var paint_body: String = _js_function_body(module, "paint")
	if paint_body.is_empty():
		_fail("VOICE_JS has no `function paint(` — the strength knobs' subject is gone")
	else:
		for needle: String in ["S.style[0]", "S.style[1]", "S.style[2]"]:
			if not paint_body.contains(needle):
				_fail("paint() does not read `%s` — a hard-coded level count, mix or "
					% needle + "edge flag makes setStyle() a no-op, and a stale level "
					+ "count indexes a ramp slot that is not there")
		if not paint_body.contains("* keep + "):
			_fail("paint() no longer blends the band colour over the ORIGINAL pixel — "
				+ "`mix` is the whole of the owner's \"a bit less agressive\", and "
				+ "without the blend the ramp REPLACES the face at every setting")
	var set_style: String = _js_function_body(module, "setStyle")
	if set_style.is_empty():
		_fail("VOICE_JS has no `function setStyle(` — there is no knob to turn")
	else:
		if not set_style.contains("STYLE_KEY"):
			_fail("setStyle does not persist under STYLE_KEY — an experiment that dies "
				+ "on reload is not the console knob the bead ships")
		var num: String = _js_function_body(module, "styleNum")
		if not num.contains("=== ''"):
			_fail("styleNum does not reject a BLANK field before Number() — "
				+ "`Number('')` is 0 and finite, so a hand-edited `4,,1,0.45` clamps "
				+ "instead of falling back, and a blank `mix` clamps to the one "
				+ "setting that turns the cartoon off (codex review 2026-09-06)")
		# THE MIX FLOOR (orchestrator ruling 2026-09-06). `styleStream()` guarantees
		# the wire carries the CANVAS and never the device track, which is the
		# transport half of "a receiver never sees the raw face". The PICTURE half
		# is this: at mix 0 the ramp replaces nothing and the canvas carries the
		# crop unposterized, i.e. the raw face at 128 px. Both halves are asserted
		# — a floor that is declared 0, or a clamp that stops reading it, is the
		# same bug spelled two ways.
		if not module.contains("var STYLE_MIX_MIN = "):
			_fail("VOICE_JS declares no `var STYLE_MIX_MIN` — `mix` would clamp to 0, "
				+ "where the ramp replaces nothing and the canvas carries the crop "
				+ "UNPOSTERIZED (the raw face at 128 px), which is what the owner's "
				+ "\"a receiver never sees the raw face\" is about")
		else:
			var floor_re := RegEx.create_from_string(
				"var\\s+STYLE_MIX_MIN\\s*=\\s*([0-9.]+)\\s*;")
			var floor_hit: RegExMatch = floor_re.search(module) if floor_re != null else null
			if floor_hit == null or float(floor_hit.get_string(1)) <= 0.0:
				_fail("VOICE_JS's STYLE_MIX_MIN is not above zero — a floor of 0 is no "
					+ "floor, and the softest setting anyone can dial would ship the "
					+ "unposterized crop")
		if not set_style.contains("styleNum(mix, STYLE_MIX_MIN, 1"):
			_fail("setStyle does not clamp `mix` UP TO STYLE_MIX_MIN — the constant "
				+ "binds nothing unless the one clamp reads it, and a stored row from "
				+ "before the floor is raised to it only because loadStyle comes "
				+ "through here")
		if not set_style.contains("styleNum(levels, 2, 8"):
			_fail("setStyle does not clamp `levels` to 2..8 — one band is not a picture "
				+ "and nine is not a cel look; a hand-edited localStorage row reaches "
				+ "this function unchecked")
	for knob: String in ["' l' + S.style[0]", "' m' + S.style[1]",
			"' e' + S.style[2]", "' s' + S.style[3]"]:
		if not module.contains(knob):
			_fail("formatStats does not print `%s` — \fo is where the owner reads "
				% knob.strip_edges() + "back which four numbers are actually live")

	# --- BLANK, NEVER DELETE (the self-view's sticky wedge) ------------------
	# `hideSelf` deleting the rect instead of blanking it leaves GDScript's change
	# gate holding a rect the browser has forgotten, so a fast camera off/on shows
	# the room your face and shows you nothing, for the rest of the room. It is
	# green everywhere without this line.
	var hide_self: String = _js_function_body(module, "hideSelf")
	if hide_self.is_empty():
		_fail("VOICE_JS has no `function hideSelf(` — the self-view's teardown "
			+ "(bead godot-test1-xtr.14) is unreadable")
	else:
		if not hide_self.contains("blankTile(SELF_TILE)"):
			_fail("hideSelf does not blankTile(SELF_TILE) — the rect must SURVIVE a "
				+ "camera toggle, or `placeTile` has nothing to place when it comes "
				+ "back and the change gate pushes nothing")
		# The CALL, not the word: `hideSelf`'s own comment names `hideTile` as the
		# slow path's job, and a check worked around by rewording prose is a check
		# nobody keeps. The other spelling (`hideTile('me')`) takes `SELF_TILE`'s
		# use count under its floor above, so both shapes are covered.
		if hide_self.contains("hideTile(SELF_TILE)"):
			_fail("hideSelf calls hideTile() — that DELETES the remembered rect, "
				+ "which is the wedge `blankTile`'s own comment documents. Deleting "
				+ "is `_poll_tiles`' job, on the slow path where the camera is "
				+ "really off")

	# --- AND THE CAPTIVE REFUSAL, DRIVEN (xtr.14 rule 3) ---------------------
	# `_tile_fraction` is the ONE home of the pad and of "a captive tile takes no
	# picture", for the teammate's tile and for the self-view alike. Deleting that
	# early return is green everywhere else — `hero_hud_selfcheck` only reads the
	# call site as text — so the rule is executed here against the smallest row a
	# GDScript can be handed. A captive hero must answer EMPTY and a free one must
	# not, or the check would pass on a function that refused everybody.
	var node: Node = _voice_node()
	var row := RowStub.new()
	row.captive = "primm"
	var free_rect: Rect2 = node._tile_fraction(row, "windman", Vector2(800.0, 600.0))
	if free_rect.size.x <= 0.0 or free_rect.size.y <= 0.0:
		_fail("_tile_fraction answered EMPTY for a FREE hero (%s) — the self-view "
			% free_rect + "and every teammate tile would be refused a picture")
	var captive_rect: Rect2 = node._tile_fraction(row, "primm", Vector2(800.0, 600.0))
	if captive_rect.size.x > 0.0 or captive_rect.size.y > 0.0:
		_fail("_tile_fraction answered %s for a CAPTIVE hero — the cell bars are "
			% captive_rect + "drawn across the whole tile and no inset saves them, "
			+ "so a captive tile takes no picture at all (bead xtr.14 rule 3)")
	row.free()
	node.free()

	# --- THE HERO ACCESSORY (bead godot-test1-xtr.13) ------------------------
	# The tint says which palette you are in; the ACCESSORY says who you are, and
	# at 92 px it is the half that actually names the hero. None of it is visible
	# to a headless machine — it is a dozen fillRects on a canvas in a browser — so
	# the shipped text is the pin, exactly as it is for the cartoon above.
	#
	# WHY THE ORDER IS ASSERTED. The owner ruled the accessory is drawn CLEAN over
	# the inked face; moving the call one line up, above `putImageData`, is a
	# one-character edit that puts it UNDER the posterize instead — the cyan visor
	# comes out in four bands and the ruling is silently reversed. An index compare
	# is the only thing that can see it.
	var acc: String = _js_function_body(module, "paintAccessory")
	if acc.is_empty():
		_fail("VOICE_JS has no `function paintAccessory(` — the hero's blindfold / "
			+ "goggles / beret / fishbowl (bead godot-test1-xtr.13) is what makes a "
			+ "tinted face read as THAT hero at 92 px, and it is gone")
	else:
		var roster: Array[String] = []
		for entry: Dictionary in PlayerScript.CHARACTERS:
			roster.append(str(entry.get("name", "")))
		for hero: String in ACCESSORY_HEROES:
			if not roster.has(hero):
				_fail("ACCESSORY_HEROES names `%s`, which is not a CHARACTERS row "
					% hero + "any more — a renamed hero must not silently lose the "
					+ "accessory that names him at 92 px")
			if acc.contains("'%s'" % hero):
				continue
			_fail("paintAccessory does not draw for `%s` — the four shipped "
				% hero + "portraits are the art contract (owner ruling 2026-09-06)")

	var body: String = _js_function_body(module, "paint")
	var put: int = body.find("putImageData")
	var call: int = body.find("paintAccessory(")
	if body.is_empty() or put < 0 or call < 0:
		_fail("VOICE_JS's `paint()` no longer both posterizes and draws the hero "
			+ "accessory — bead godot-test1-xtr.13's whole output is that one call")
	elif call < put:
		_fail("paint() draws the accessory BEFORE putImageData, so it goes through "
			+ "the posterize instead of over it — the owner ruled it is drawn CLEAN "
			+ "over the inked face (2026-09-06), and Primm's cyan visor banded into "
			+ "four levels is what this reverses")

	# THE FACE BOX IS WHAT IT IS REGISTERED ON, and with no detector `S.faceBox` is
	# the centre square — so the fallback is the same arithmetic and not a second
	# path. A `paintAccessory` that stopped reading the box would paint a fixed
	# centre guess that slides off the face the moment the player moves, which is
	# exactly why this bead came third.
	var on_canvas: String = _js_function_body(module, "faceOnCanvas")
	if on_canvas.is_empty() or not on_canvas.contains("S.faceBox") \
			or not on_canvas.contains("FACE_ZOOM"):
		_fail("VOICE_JS has no `faceOnCanvas` reading `S.faceBox` and dividing "
			+ "`FACE_ZOOM` back out — the accessory would sit on a fixed centre "
			+ "guess rather than on the face the tracker found (bead xtr.13)")

	# AND THE NAME HAS TO REACH THE BROWSER. It rides `setStyleTint`'s fourth
	# argument rather than a second bridge function; both ends are asserted,
	# because either half alone is a hero that never changes his hat.
	if not module.contains("function (r, g, b, hero)"):
		_fail("VOICE_JS's setStyleTint no longer takes the hero NAME — the tint is "
			+ "a colour and cannot say which SHAPE to draw (bead xtr.13)")
	var gd: String = FileAccess.get_file_as_string("res://scripts/voice_chat.gd")
	if not gd.contains("_ck.setStyleTint(int(tint.r8), int(tint.g8), int(tint.b8), hero)"):
		_fail("_push_style_tint no longer pushes the hero name beside the tint, so "
			+ "the browser draws no accessory at all (bead xtr.13)")

	Sentinel.done("style_mirrors")


func _js_function_body(module: String, name: String) -> String:
	## One `function <name>(...) { … }` out of `VOICE_JS`, or "" if there is none.
	## Every function in that module is indented one tab and closed by `\n\t}`, so
	## the first such line after the header is the end — blunt, and blunt is right
	## for a check whose job is to read the shipped text rather than parse JS.
	var start: int = module.find("function %s(" % name)
	if start < 0:
		return ""
	var end: int = module.find("\n\t}", start)
	if end < 0:
		return ""
	return module.substr(start, end - start)


func _check_js_used(module: String, name: String, want: int) -> void:
	## `name` must appear at least `want` times in `VOICE_JS`: once where it is
	## declared and once per place the value is really spent.
	var seen: int = module.count(name)
	if seen < want:
		_fail("VOICE_JS names `%s` %d time(s), expected at least %d — a constant "
			% [name, seen, want]
			+ "that is declared and not SPENT binds nothing, which is how a "
			+ "literal in the paint loop drifts from HudTheme in silence")


func _check_js_triple(module: String, name: String, want: Color) -> void:
	## One `var NAME = [r, g, b];` in `VOICE_JS`, against the `HudTheme` colour it
	## is a copy of. 0-255 channels, which is the only unit a canvas has.
	var re := RegEx.create_from_string(
		"var\\s+%s\\s*=\\s*\\[\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\]" % name)
	var hit: RegExMatch = re.search(module) if re != null else null
	if hit == null:
		_fail("VOICE_JS declares no `var %s = [r, g, b]` — the cartoon camera's " % name
			+ "film palette (bead godot-test1-xtr.11) cannot be bound to HudTheme")
		return
	var got := Vector3i(int(hit.get_string(1)), int(hit.get_string(2)), int(hit.get_string(3)))
	var expect := Vector3i(want.r8, want.g8, want.b8)
	if got != expect:
		_fail("VOICE_JS's %s is %s but the HudTheme colour it mirrors is %s — the "
			% [name, got, expect] + "cartoon camera would paint a palette the rest "
			+ "of the HUD does not use")


func _js_bool_offence(source: String) -> String:
	for line: String in source.split("\n"):
		for banned: String in IntroSelfcheck.JS_BOOL_RETURNS:
			if line.contains(banned):
				return line.strip_edges()
	return ""


# ============================================================================
# 6b. A FAILED ICE TRANSPORT REBUILDS ITSELF
# ============================================================================

## The spellings that together ARE the recovery, in the order the browser reaches
## them: the handler that notices, the states it acts on, and the calls that
## repair. Each is spelled as CODE rather than as a bare word, because the
## explanation beside the call names `restartIce()` too — a check on the word
## alone survives the deletion of the call it guards, which is not a
## hypothetical: it is what the first draft of this check did, measured.
## The four heroes the shipped portraits give an accessory to (bead
## `godot-test1-xtr.13`, owner ruling 2026-09-06: windman blindfold, primm
## goggles, teibi beret, phoboman fishbowl helmet). It is a LIST rather than
## `CHARACTERS` itself because a fifth hero deliberately draws nothing — the
## bead's own acceptance, `hero_hud`'s "a missing portrait is not an error" rule
## — but every name in it is bound to the real roster below, so a hero RENAMED
## in `CHARACTERS` fails here instead of quietly losing his hat.
const ACCESSORY_HEROES: Array[String] = ["windman", "primm", "teibi", "phoboman"]


const ICE_RESTART_NEEDLES: Array[String] = [
	"pc.oniceconnectionstatechange",
	"pc.restartIce()",
	# R2's two states, and BOTH of them: `failed` alone is what shipped before
	# bead godot-test1-xtr.19 and is exactly the half that never fired.
	"st === 'failed'",
	"st === 'disconnected'",
	# R1 — the rollback that unwedges a PC whose offer was lost.
	"type: 'rollback'",
	"'have-local-offer'",
	# R3 — the fingerprint compare and the one-PC rebuild it triggers.
	"a=fingerprint:",
	"healRemoteRebuilt",
]

## R2's bound, R1's bound and R3's, each as the CONSTANT that carries it. A rung
## with no bound is the re-offer loop the pre-xtr.19 ruling refused to risk, so
## the bound is the thing this check is really pinning: `_check_js_used` demands
## each name appear twice — declared, and SPENT.
const HEAL_BOUND_CONSTS: Array[String] = [
	"HEAL_OFFER_TIMEOUT_MS",
	"HEAL_OFFER_TRIES_MAX",
	"HEAL_ICE_HOLD_MS",
	"HEAL_ICE_COOLDOWN_MS",
	"HEAL_ICE_TRIES_MAX",
	"HEAL_REBUILD_COOLDOWN_MS",
]

## The exact spelling of the retired guard. It is the NEGATIVE control: a
## `disconnected` that is acted on only behind a timer and a cap cannot be
## written as the bare "act on anything that is not failed" test this replaced.
const BARE_ICE_GUARD: String = "iceConnectionState !== 'failed'"


func _check_ice_restart() -> void:
	"""
	`VOICE_JS` read as TEXT again — this file's own `_check_no_js_bool` idiom, but
	its OWN check with its own stamp, because the two ask unrelated questions and
	a later edit that retires the boolean scan must not take this with it.

	WHAT IT DEFENDS. `members(json)` closes a `RTCPeerConnection` only when the id
	LEAVES `_members`, so a live member whose own end has died is never rebuilt by
	anything: the peer stays listed, stays un-muted, keeps its video tile, and is
	silent for the rest of the room with no status line and nothing retrying. The
	repairs all ride the perfect-negotiation queue out over the existing `"vc"`
	relay as ordinary offers — there is no new signalling kind to test and
	`MpCodec.decode_vc` is untouched (check 1 proves that half byte for byte). The
	only thing a headless check CAN see is that the code is still there.

	THIS CHECK WAS REWRITTEN BY BEAD `godot-test1-xtr.19` AND THE OLD RULING IS
	REVERSED. It used to pin `iceConnectionState !== 'failed'` as a THIRD needle,
	with this docstring explaining that `'disconnected'` is transient and
	self-healing and that acting on it turns the handler into a re-offer loop on
	every path blip. The fear was real; the ruling was wrong about the case the
	owner reported. Chrome reaches `failed` only when ICE consent freshness
	expires (~30 s) and sometimes never leaves `disconnected` at all, so a coturn
	allocation expiring or a NAT rebind left a pair silent — audio AND video — for
	the life of the room, under a handler watching a state it would never see. The
	answer to a loop is a BOUND, not a blind spot: so `'disconnected'` is now acted
	on behind a 5 s hold, one restart per 15 s and three in a row, and what this
	check pins is that every one of those bounds is still a spent constant. The
	retired bare guard is asserted ABSENT, which is this check's negative control.

	THE OTHER THREE RUNGS ARE PINNED THE SAME WAY, because each is invisible to
	every other check in the suite: a lost offer rolled back (R1), the one-PC
	rebuild the REMOTE detects off a changed `a=fingerprint:` (R3 — and that
	compare is the whole reason no `vc` kind was added), and a paused element
	re-played (R4).
	"""
	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — check 6b "
			% module.length() + "would pass vacuously")
		Sentinel.done("ice_restart")
		return

	for needle: String in ICE_RESTART_NEEDLES:
		if module.contains(needle):
			continue
		_fail("voice_chat.gd's VOICE_JS is missing `%s`, so a peer whose own end "
			% needle + "has died (a NAT rebind, an expiring coturn allocation, a "
			+ "lost offer, a dead DTLS transport) stays stuck for the whole life "
			+ "of the room — nothing else rebuilds a still-listed member's "
			+ "connection (beads godot-test1-xtr.7 and godot-test1-xtr.19)")

	# --- THE BOUNDS, which are what make acting on `disconnected` safe ---------
	for name: String in HEAL_BOUND_CONSTS:
		_check_js_used(module, name, 2)

	# --- THE NEGATIVE CONTROL -------------------------------------------------
	if module.contains(BARE_ICE_GUARD):
		_fail("VOICE_JS still spells `%s`, the pre-xtr.19 guard: acting on every "
			% BARE_ICE_GUARD + "state that is not `failed` is the unbounded "
			+ "re-offer loop this ladder replaced with a held timer and a cap")

	# --- R1, R3 AND R4 IN THE FUNCTIONS THAT OWN THEM -------------------------
	# Scoped to bodies rather than the whole module, because the essays above them
	# name every one of these calls to explain the measurement — and a check that
	# a reworded comment satisfies is a check nobody keeps.
	var arm: String = _js_function_body(module, "healArmOffer")
	if arm.is_empty():
		_fail("VOICE_JS has no `function healArmOffer(` — R1's offer timeout, the "
			+ "only thing that unwedges a PC left in `have-local-offer` by a lost "
			+ "offer, is gone")
	elif not (arm.contains("type: 'rollback'") and arm.contains("HEAL_OFFER_TRIES_MAX")):
		_fail("healArmOffer no longer rolls a timed-out offer back under "
			+ "HEAL_OFFER_TRIES_MAX — an unbounded rollback is a re-offer loop and "
			+ "an absent one is the wedge (bead godot-test1-xtr.19 R1)")

	var recv: String = _js_function_body(module, "recv")
	if recv.is_empty():
		_fail("VOICE_JS has no `function recv(` — check 6b cannot see how an "
			+ "incoming offer reaches a connection")
	elif not (recv.contains("healRemoteRebuilt") and recv.contains("healSwap")):
		_fail("recv no longer detects a REBUILT remote off its fingerprint and "
			+ "swaps our PC for a fresh one, so a one-sided rebuild leaves the "
			+ "other end applying the new offer to its old PC — where the DTLS "
			+ "fingerprint differs and setRemoteDescription rejects, swallowed "
			+ "(bead godot-test1-xtr.19 R3)")

	var swap: String = _js_function_body(module, "healSwap")
	if swap.is_empty():
		_fail("VOICE_JS has no `function healSwap(` — R3's rebuild is gone")
	else:
		if not (swap.contains("close(id)") and swap.contains("open(id)")):
			_fail("healSwap no longer does close(id) then open(id) — the rebuild "
				+ "has to re-run `open`, which is what re-attaches the mic and the "
				+ "cartoon track so the fresh offer carries everything")
		if not swap.contains("S.tiles[id] = keep"):
			_fail("healSwap no longer carries the tile rect across the rebuild: "
				+ "`close` forgets it while GDScript's `_pushed_tiles` still holds "
				+ "the identical fraction, so a track that comes back inside one "
				+ "5 Hz poll window is never given a rect and the tile stays dark "
				+ "for the rest of the room (hideSelf's wedge, remote side)")

	var paused: String = _js_function_body(module, "healPaused")
	if paused.is_empty() or not paused.contains(".paused"):
		_fail("VOICE_JS has no `function healPaused(` reading `.paused` — a "
			+ "<video> that paused after `showVideo`'s one swallowed play() shows "
			+ "its last frame forever behind a perfectly healthy track (bead "
			+ "godot-test1-xtr.19 R4)")

	var tick: String = _js_function_body(module, "sampleTick")
	if tick.is_empty() or not tick.contains("healPaused()"):
		_fail("healPaused is not driven from sampleTick — R4 with no clock is a "
			+ "function nothing calls")

	# --- THE EVIDENCE \fo SHOWS ----------------------------------------------
	var fmt: String = _js_function_body(module, "formatStats")
	if fmt.is_empty() or not fmt.contains(" heal="):
		_fail("formatStats does not emit ` heal=` — which rung fired is then "
			+ "unmeasurable in \\fo, and every rung here is bounded precisely so "
			+ "that its firing is worth reading (bead godot-test1-xtr.19)")

	Sentinel.done("ice_restart")


# ============================================================================
# 6d. A STUCK PICTURE IS MEASURABLE (bead godot-test1-xtr.17)
# ============================================================================

## The six per-peer keys plus the two sender-side ones that together name all
## four classes of stuck picture the bead enumerates. Spelled with their `=` so
## the check is reading a FORMAT and not a word that also appears in prose.
const VIDEO_STAT_KEYS: Array[String] = [
	" ice=", " con=", " sig=", " sdp=", " vin=", " vout=", " paint=", " src=",
]


func _check_video_health() -> void:
	"""
	`VOICE_JS` read as TEXT once more (this file's `_check_no_js_bool` idiom), for
	the half of bead `godot-test1-xtr.17` a headless machine can reach.

	WHAT IT DEFENDS. Before this bead nothing in the game could tell a frozen
	picture from a working one: `sampleStats()` read audio `inbound-rtp` and the
	selected candidate pair, so a receiver whose `framesDecoded` had stopped, a
	sender whose paint loop had stalled, a transport in `failed` and a peer wedged
	in `have-local-offer` all reported an identical row. Deleting any one of the
	assertions below is green everywhere else in the suite — the numbers only
	exist in a browser — so the text IS the pin.

	THE ORDER MATTERS. The keys must be inside `formatStats`, because that is the
	one function whose answer reaches \\fo; `framesDecoded`/`framesEncoded` must be
	inside `sampleStats`, because a key with nothing collecting its number prints
	`-` forever and looks like a working feature.
	"""
	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — check 6d "
			% module.length() + "would pass vacuously")
		Sentinel.done("video_health")
		return

	var fmt: String = _js_function_body(module, "formatStats")
	if fmt.is_empty():
		_fail("VOICE_JS has no `function formatStats(` — the \\fo row's whole "
			+ "vocabulary is unreadable")
	else:
		for key: String in VIDEO_STAT_KEYS:
			if not fmt.contains(key):
				_fail("formatStats does not emit `%s` — that class of stuck picture "
					% key.strip_edges() + "(bead godot-test1-xtr.17) is invisible in "
					+ "\\fo, which is the whole of what this bead ships")

	var sample: String = _js_function_body(module, "sampleStats")
	if sample.is_empty():
		_fail("VOICE_JS has no `function sampleStats(` — nothing collects the "
			+ "numbers formatStats prints")
	else:
		for needle: String in ["framesDecoded", "framesEncoded", "markStall(",
				"localDescription.sdp.length", "signalingState"]:
			if not sample.contains(needle):
				_fail("sampleStats does not read `%s` — the matching key in the \\fo "
					% needle + "row would print a placeholder forever, which reads "
					+ "exactly like a healthy peer")

	# --- THE RECEIVER'S MARK, AND THAT A RE-PLACE KEEPS IT ------------------
	# `placeTile` rewrites `cssText` wholesale, so a mark applied anywhere else is
	# cleared by the next resize or rect push. That is the one ordering bug this
	# feature has, and it is invisible in a diff.
	var place: String = _js_function_body(module, "placeTile")
	if place.is_empty():
		_fail("VOICE_JS has no `function placeTile(` — check 6d cannot see whether "
			+ "the stall mark survives a re-place")
	elif not place.contains("stallFilter(id)"):
		_fail("placeTile does not append stallFilter(id) — it rewrites cssText "
			+ "wholesale, so the dim would be cleared by the next resize or rect "
			+ "push and a stuck tile would look live again")
	var filt: String = _js_function_body(module, "stallFilter")
	if filt.is_empty():
		_fail("VOICE_JS has no `function stallFilter(` — a receiver whose "
			+ "framesDecoded stopped is drawn exactly like a live one")
	else:
		if not filt.contains("grayscale(1)") or not filt.contains("brightness("):
			_fail("stallFilter does not dim with grayscale/brightness — it reads `%s`"
				% filt.strip_edges())
		# NO HUE, and that is a repo rule rather than taste: `hero_hud_selfcheck`
		# check 8 greps `scripts/` for the six film hexes and they may be typed in
		# `hud_theme.gd` alone, so the mark must be spelled in the two things CSS
		# can do without naming a colour at all.
		if filt.contains("#") or filt.contains("rgb("):
			_fail("stallFilter names a colour — the film palette may not be typed "
				+ "outside hud_theme.gd (hero_hud_selfcheck check 8), which is why "
				+ "the mark is a filter")
	if not module.contains("var STALL_SAMPLES = 3;"):
		_fail("VOICE_JS does not declare `var STALL_SAMPLES = 3` — the bead's three "
			+ "seconds at the 1 Hz sample rate. One sample is noise (a keyframe "
			+ "gap, a tab that just came back) and would flicker every tile")

	# --- AND THE SAMPLER HAS A CLOCK THAT IS NOT \fo ------------------------
	# `sampleStats` used to be driven by `stats()` alone, which only runs while the
	# perf overlay is open. A stall mark that needs a debug overlay to appear is a
	# debug feature, not a fix.
	var vp: String = _js_function_body(module, "videoPeers")
	if vp.is_empty() or not vp.contains("sampleTick()"):
		_fail("videoPeers() does not call sampleTick() — the health sample would "
			+ "run only while \\fo is open, so no player would ever see a tile dim")

	# --- THE ROW IS WRAPPED, DRIVEN ON THE SHIPPED HELPER -------------------
	# \fo's Label neither autowraps nor clips and the audio half alone already
	# reaches the right edge, so the video half has to start a second line or it
	# is drawn off screen — which is the same as not shipping it. The live
	# `stats()` string needs a browser; this drives the transformation that is
	# applied to it, on a sample of the real format.
	var node: Node = _voice_node()
	var sample_row: String = ("Voice: mode=ALWAYS tx=0 ns=1 ec=1 agc=1 peers=1 "
		+ "rtt=42ms loss=0.0% style=0.42ms l8 m0.40 e0 s0.60 "
		+ "ice=connected con=connected sig=stable "
		+ "sdp=5312 vin=12 vout=12 paint=61 src=1")
	var wrapped: String = str(node._wrap_stats(sample_row))
	var lines: PackedStringArray = wrapped.split("\n")
	if lines.size() != 2:
		_fail("_wrap_stats left the \\fo row on %d line(s) — the video half is "
			% lines.size() + "drawn past the right edge of the window")
	elif not lines[1].contains("vin=") or not lines[0].contains("loss="):
		_fail("_wrap_stats split the row in the wrong place: `%s`" % wrapped)
	# ...and a row with no video half is untouched, which is what a bridge that
	# said nothing (`_ck` null, the module not installed) still produces.
	var audio_only: String = "Voice: mode=PTT tx=1 ns=0 ec=0 agc=0 peers=0 rtt=- loss=0.0%"
	if str(node._wrap_stats(audio_only)) != audio_only:
		_fail("_wrap_stats rewrote a row with no video half")
	node.free()
	Sentinel.done("video_health")


# ============================================================================
# 6e. THE SENDER HEALS ITSELF (bead godot-test1-xtr.18)
# ============================================================================

func _check_sender_heal() -> void:
	"""
	`VOICE_JS` as TEXT again, for the three root causes of "video gets stuck and
	there is no way to restart it" — every one of which lives in a browser this
	suite cannot open, so the shipped text is the only thing a headless check can
	hold.

	1. THE CAMERA TOGGLE MUST NOT GROW THE SDP. `addTrack` only reuses a
	   transceiver that has never sent, so a `removeTrack`/`addTrack` pair per
	   toggle appends a video m-section every time. MEASURED in a two-tab room on
	   the debug web export: 3,090 chars audio-only, 9,338 with the camera, and
	   **16,586 after ONE off/on** — past the old `MAX_VC_SDP`, so the receiver
	   dropped the offer (`MpCodec: dropped vc offer with a 16586-char sdp` in its
	   console), the toggler sat in `have-local-offer` for the rest of the room and
	   nine further toggles changed nothing. `replaceTrack` renegotiates nothing.
	2. A FROZEN DEVICE MUST BE NOTICED AND SAID OUT LOUD. The receiver cannot see
	   it — framesDecoded keeps advancing on a repainted still — so the sender
	   re-acquires and, failing that, paints a card INTO the canvas, which travels
	   as pixels to every receiver on every build.
	3. A HIDDEN TAB MUST KEEP PAINTING, which is the Worker clock.

	Deleting any of these is green everywhere else in the suite.
	"""
	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — check 6e "
			% module.length() + "would pass vacuously")
		Sentinel.done("sender_heal")
		return

	# --- 1. NEVER remove/add the video sender again --------------------------
	# Scoped to the two function BODIES rather than the whole module, because the
	# essay above `attachCam` names the retired call to explain the measurement —
	# and a check worked around by rewording prose is a check nobody keeps.
	# `_js_function_body` starts at the `function` keyword, so that essay is out of
	# scope by construction and these two are the whole of the video send path.
	var attach: String = _js_function_body(module, "attachCam")
	var detach: String = _js_function_body(module, "detachCam")
	if attach.is_empty() or detach.is_empty():
		_fail("VOICE_JS has no attachCam/detachCam — check 6e cannot see how the "
			+ "camera toggle reaches a connection")
	else:
		if attach.contains("removeTrack") or detach.contains("removeTrack"):
			_fail("the video send path still calls removeTrack — every camera off/on "
				+ "then appends a video m-section to the offer (MEASURED: 9,338 -> "
				+ "16,586 chars on ONE toggle), the receiver drops it over "
				+ "MAX_VC_SDP and the pair wedges in have-local-offer for the rest "
				+ "of the room (godot-test1-xtr.18)")
		if not attach.contains("replaceTrack("):
			_fail("attachCam does not replaceTrack onto an existing sender — a "
				+ "second addTrack is what grows the SDP past MAX_VC_SDP")
		if not attach.contains("p.pc.addTrack("):
			_fail("attachCam never addTrack()s — the FIRST attach has to create the "
				+ "sender, or no video is ever negotiated at all")
		if not attach.contains("150000"):
			_fail("attachCam no longer sets the 150 kbps cap (owner ruling) on the "
				+ "sender it creates")
		if not detach.contains("replaceTrack(null)"):
			_fail("detachCam does not replaceTrack(null) — switching the camera off "
				+ "must stop the RTP while KEEPING the sender, which is what makes "
				+ "the next ON a heal instead of a second m-section")
		if detach.contains("p.vsend = null"):
			_fail("detachCam drops p.vsend — the next attachCam would addTrack a "
				+ "second sender, which is the whole bug")
	# ...and the belt on the receiving side, for a sender on an OLD build that
	# still grows. The lobby's own frame cap is the real outer bound.
	if MpCodec.MAX_VC_SDP < 32768:
		_fail("MpCodec.MAX_VC_SDP is %d — a real audio+video offer measured 9,338 "
			% MpCodec.MAX_VC_SDP + "chars and an old build's toggled one 16,586, so "
			+ "the bound belongs at the lobby's own 32 KB frame cap (server/conn.go "
			+ "maxPayload) rather than at half of it")

	# --- 2. THE FROZEN SOURCE, AND THAT IT IS SAID IN PIXELS ----------------
	var watch: String = _js_function_body(module, "camWatch")
	if watch.is_empty() or not watch.contains("t.onended"):
		_fail("VOICE_JS has no camWatch() hooking the device track's onended — a "
			+ "camera taken by another app, a shut lid or an unplugged device "
			+ "leaves the last frame painted forever, which no receiver can detect")
	if _js_function_body(module, "recam").is_empty():
		_fail("VOICE_JS has no recam() — nothing re-acquires a device that ended")
	if not module.contains("var STYLE_RECAM_MAX = 3;"):
		_fail("VOICE_JS does not bound the re-acquisition at STYLE_RECAM_MAX = 3 — "
			+ "a device that is gone for good would hammer getUserMedia for the "
			+ "life of the room")
	var card: String = _js_function_body(module, "paintCard")
	if card.is_empty():
		_fail("VOICE_JS has no paintCard() — the sender's frozen source reaches "
			+ "every receiver as a still picture with nothing saying so")
	else:
		# The palette, because a card drawn in some other colour is a card that
		# does not read as this game's (and a HEX here fails check 8 instead).
		if not card.contains("STYLE_INK") or not card.contains("STYLE_BONE"):
			_fail("paintCard does not draw in STYLE_INK/STYLE_BONE — the film "
				+ "palette is the only one this HUD has")
		if card.contains("#"):
			_fail("paintCard types a hex colour — the six film hexes may be typed "
				+ "in hud_theme.gd alone (hero_hud_selfcheck check 8)")
	# The STALE BRANCH IS IN paint(), which is the only function both clocks call.
	var paint_fn: String = _js_function_body(module, "paint")
	if paint_fn.is_empty():
		_fail("VOICE_JS has no function paint( — the whole cartoon camera is gone")
	else:
		if not paint_fn.contains("paintCard()") or not paint_fn.contains("recam()"):
			_fail("paint() does not reach the stale branch (recam + paintCard) — the "
				+ "card would exist and never be drawn")
		if not paint_fn.contains("currentTime"):
			_fail("paint() does not watch the source's currentTime — that is the ONE "
				+ "signal that sees an ended track, a muted one and a stopped "
				+ "decoder alike")
	if not module.contains("var STYLE_STALE_MS = 2000;"):
		_fail("VOICE_JS does not declare STYLE_STALE_MS = 2000 — a card with no "
			+ "grace period flickers on every legitimate device hiccup")

	# --- 3. THE BACKGROUND CLOCK --------------------------------------------
	var worker: String = _js_function_body(module, "styleWorker")
	if worker.is_empty() or not worker.contains("new Worker("):
		_fail("VOICE_JS has no styleWorker() building a real Worker — rVFC never "
			+ "fires in a hidden tab and setInterval is throttled to 1 Hz there, so "
			+ "a sender who tabs away drops every receiver to a slideshow")
	if not module.contains("var STYLE_WORKER_SRC ="):
		_fail("VOICE_JS declares no STYLE_WORKER_SRC — there is nothing for the "
			+ "worker to run")
	if _js_function_body(module, "pushFrame").is_empty():
		_fail("VOICE_JS has no pushFrame() — captureStream samples a canvas only "
			+ "when it is PRESENTED, so a hidden tab's painted frames never reach "
			+ "the encoder without an explicit requestFrame()")
	elif not module.contains("requestFrame()"):
		_fail("VOICE_JS never calls requestFrame() on the capture track")
	# The worker REPLACES the watchdog rather than running beside it; a build that
	# armed both would paint at 12 + 12 + 2 a second on a visible tab.
	var start: String = _js_function_body(module, "styleStart")
	if not start.is_empty() and start.contains("styleWatchdog()"):
		_fail("styleStart arms styleWatchdog() directly — it must go through "
			+ "styleClock(), which prefers the worker and falls back to the 2 Hz "
			+ "watchdog only where there is none")
	Sentinel.done("sender_heal")


func _voice_js_module() -> String:
	"""The text between `const VOICE_JS`'s two triple-quotes, or "" if either end
	moved. The delimiter is built at runtime so this file can hold it without
	terminating its own strings."""
	var fence: String = '"'.repeat(3)
	var source: String = FileAccess.get_file_as_string("res://scripts/voice_chat.gd")
	var decl: int = source.find("const VOICE_JS")
	if decl < 0:
		return ""
	var start: int = source.find(fence, decl)
	if start < 0:
		return ""
	start += fence.length()
	var end: int = source.find(fence, start)
	if end < 0:
		return ""
	return source.substr(start, end - start)


# ============================================================================
# 7. INERT OFF-WEB
# ============================================================================

## Every public method on `voice_chat.gd`, with the arguments to call it with.
## A method NOT listed fails check 7 by name — the whole point is that a later
## voice bead's new public surface is proved bridge-free the day it lands, not
## the day somebody remembers this file exists.
const PUBLIC_CALLS: Array = [
	["is_available", []],
	["mic_denied", []],
	["get_mode", []],
	["set_mode", [1]],
	["is_tx", []],
	["set_mic_muted", [true]],
	["is_mic_muted", []],
	["set_deafened", [true]],
	["is_deafened", []],
	# The incoming volume (bead godot-test1-xtr.9).
	["set_volume", [0.5]],
	["get_volume", []],
	["set_peer_muted", ["deadbeef", true]],
	["is_peer_muted", ["deadbeef"]],
	["is_speaking", ["deadbeef"]],
	["apply_levels", ["deadbeef:42.0,me:0.1,,bad,x:y"]],
	# The camera (bead godot-test1-xtr.6) — web-only exactly like the microphone.
	["set_camera_enabled", [true]],
	["is_camera_on", []],
	["camera_denied", []],
	# Telemetry readout for \fo (bead godot-test1-xtr.4).
	["debug_line", []],
	# The hero row's two questions (bead godot-test1-xtr.8) — both must answer the
	# NOTHING case off-web without ever reaching for `_ck`.
	["mic_badge", []],
	["is_hero_speaking", ["windman"]],
]


func _check_face_crop() -> void:
	"""
	THE FACE-REGISTERED CROP'S VENDORING (bead `godot-test1-xtr.12`), and this
	check exists because that feature's worst failure is INVISIBLE.

	Every other way the detector can fail announces itself: a browser with no
	`OffscreenCanvas`, a 404, a throw — all of them land on the centre crop,
	which is the MVP and looks like a working game. So does a build that shipped
	no detector at all. A url renamed in `VOICE_JS` that the lock no longer
	fetches, a row dropped from `vendor.lock`, or the fetch step deleted from
	`build.yml` produce a picture NOBODY CAN TELL from the intended one — they
	cost the owner the exact fix they asked for and report nothing.

	THE BINARIES ARE NOT IN THE TREE (they are ~12 MB, fetched at build time), so
	what is checked is the MANIFEST and the two callers of the fetch script —
	which is the stronger end anyway, because the lock is what CI actually
	downloads and `fetch_vendor.sh` refuses any file whose sha256 misses.

	So the four things asserted here are all of that class, and none of them is
	the crop ARITHMETIC: a wrong lerp or a wrong zoom is visible in one glance at
	a tile, and the maths is driven in a browser at review time.

	ponytail: no JS unit test in CI. This repo has no node toolchain and the
	logic that would need one fails visibly; add one when a second JS module
	arrives that a headless check cannot reach.
	"""
	var module: String = _voice_js_module()
	if module.length() < 500:
		_fail("could not read VOICE_JS out of voice_chat.gd (%d chars) — the face "
			% module.length() + "crop check would pass vacuously")
		Sentinel.done("face_crop")
		return

	# --- 1. EVERY URL THE MODULE ASKS FOR IS A ROW IN THE LOCK ---------------
	# THE BINARIES ARE NOT IN THE TREE — they are ~12 MB and are fetched at build
	# time by `scripts/fetch_vendor.sh` against `vendor.lock`, so this cannot
	# check the files and must check the MANIFEST instead. That is the stronger
	# end anyway: the lock is what CI fetches, and `fetch_vendor.sh` already
	# refuses to install anything whose sha256 does not match it.
	#
	# Reading the names OUT of the shipped text rather than listing them here is
	# what makes a rename fail: a list would simply stop describing the module.
	var dir: String = "res://web/vendor/mediapipe/"
	var lf: FileAccess = FileAccess.open(dir + "vendor.lock", FileAccess.READ)
	if lf == null:
		_fail("web/vendor/mediapipe/vendor.lock is missing — it is the only place "
			+ "the detector's version, urls and checksums are written, so the "
			+ "build has nothing to fetch and every player gets the centre crop")
		Sentinel.done("face_crop")
		return
	var lock: String = lf.get_as_text()
	lf.close()

	# The lock's `file`/`model` rows, as dest -> sha.
	var locked: Dictionary = {}
	var pkg: String = ""
	for line: String in lock.split("\n"):
		var row: PackedStringArray = line.strip_edges().split(" ", false)
		if row.size() < 2 or row[0].begins_with("#"):
			continue
		if row[0] == "npm":
			pkg = row[1]
		elif (row[0] == "file" or row[0] == "model") and row.size() >= 4:
			locked[row[1]] = row[2]
	if pkg.is_empty():
		_fail("vendor.lock names no `npm` package — the fetch has no version to pin")
	if locked.size() < 3:
		_fail("vendor.lock lists %d file/model row(s) — expected at least the " % locked.size()
			+ "bundle, the wasm loader, the wasm binary and the model")
	for dest: String in locked:
		var sha: String = String(locked[dest])
		if sha.length() != 64 or sha.to_lower() != sha or not sha.is_valid_hex_number():
			_fail("vendor.lock's row for `%s` has no valid sha256 (%s) — the fetch " % [dest, sha]
				+ "would install whatever the network handed it")

	var asked: Array[String] = []
	var from: int = 0
	while true:
		var i: int = module.find("faceUrl('", from)
		if i < 0:
			break
		var start: int = i + "faceUrl('".length()
		var end: int = module.find("'", start)
		if end < 0:
			break
		asked.append(module.substr(start, end - start))
		from = end
	if asked.size() < 3:
		_fail("VOICE_JS asks for %d vendored file(s) via faceUrl() — expected the "
			% asked.size() + "bundle, the wasm directory and the model, so either "
			+ "the detector's loader is gone or it stopped going through faceUrl()")
	for rel: String in asked:
		# The wasm DIRECTORY is passed whole to `FilesetResolver.forVisionTasks`,
		# which appends `/vision_wasm_internal.js` and `.wasm` itself — so the
		# directory argument is checked as the two files it really stands for.
		var wanted: Array[String] = [rel]
		if rel == "wasm":
			wanted = ["wasm/vision_wasm_internal.js", "wasm/vision_wasm_internal.wasm"]
		for w: String in wanted:
			if not locked.has(w):
				_fail("VOICE_JS loads `%s`, which vendor.lock does not fetch — " % w
					+ "the file would 404 and every player would silently fall back "
					+ "to the centre crop, which is the picture the owner asked to "
					+ "have fixed")

	# --- 2. THE LICENCE SHIPS BESIDE THE CODE -------------------------------
	# `assets/fonts/OFL.txt`'s rule: a vendored Apache-2.0 artifact carries its
	# licence in the tree it is redistributed from. This one IS committed —
	# it is the licence, not a 12 MB binary.
	if not FileAccess.file_exists(dir + "LICENSE"):
		_fail("web/vendor/mediapipe/LICENSE is missing — MediaPipe is Apache-2.0 "
			+ "and this build redistributes it, so the licence ships beside the "
			+ "files (the assets/fonts/OFL.txt rule)")

	# --- 3. THE BUILD REALLY FETCHES AND INSTALLS THEM ----------------------
	# The lock being right proves nothing on its own: both deploy targets are cut
	# from `build/web`, and the Godot export writes only the game into it. Without
	# the fetch the detector 404s in production and nowhere else — and the game
	# looks exactly the same, which is why this is asserted as TEXT.
	if not FileAccess.file_exists("res://scripts/fetch_vendor.sh"):
		_fail("scripts/fetch_vendor.sh is missing — nothing fetches or verifies the "
			+ "vendored detector, and the lock describes a download nobody makes")
	var wf: FileAccess = FileAccess.open("res://.github/workflows/build.yml", FileAccess.READ)
	if wf == null:
		_fail("could not read .github/workflows/build.yml")
	else:
		var yml: String = wf.get_as_text()
		wf.close()
		if not yml.contains("sh scripts/fetch_vendor.sh build/web"):
			_fail("build.yml no longer installs the vendored detector into build/web "
				+ "via scripts/fetch_vendor.sh — it would be fetched and then absent "
				+ "from both deploy targets, and the game would look fine")
		if not yml.contains("sh scripts/fetch_vendor.sh\n"):
			_fail("build.yml no longer runs the fetch BEFORE the export — a bad pin "
				+ "or an unreachable registry would fail after the export instead of "
				+ "in seconds")
	# The developer rig runs the SAME script, which is the whole reason it is one.
	var sf: FileAccess = FileAccess.open("res://serve.sh", FileAccess.READ)
	if sf != null:
		var sh: String = sf.get_as_text()
		sf.close()
		if not sh.contains("scripts/fetch_vendor.sh"):
			_fail("serve.sh no longer installs the vendored detector — a local debug "
				+ "export would serve the game with no detector, so the developer rig "
				+ "and CI would disagree about what the camera does")

	# --- 4. THE FALLBACK RUNG IS STILL THE MVP'S CENTRE CROP ----------------
	# `cropBox` answers the centre square whenever there is no fresh face, and
	# THAT expression is the whole of "the detector's absence is invisible to the
	# receiver". If it is ever rewritten into something else, a browser on the
	# fallback rung stops matching the build that shipped before this bead.
	var crop: String = _js_function_body(module, "cropBox")
	if crop.is_empty():
		_fail("VOICE_JS has no `function cropBox(` — the crop box this bead moved "
			+ "is gone")
	else:
		if not (crop.contains("vw / 2") and crop.contains("vh / 2")
				and crop.contains("vw < vh ? vw : vh")):
			_fail("cropBox no longer spells the MVP's centre square (vw/2, vh/2, "
				+ "min(vw, vh)) — that expression IS the fallback rung every "
				+ "browser without a detector lands on")
		if not crop.contains("FACE_LOST_MS"):
			_fail("cropBox no longer expires a stale face target against "
				+ "FACE_LOST_MS — a player who walked away would leave the crop "
				+ "parked on the chair they left")

	Sentinel.done("face_crop")


func _check_inert_offweb() -> void:
	"""
	Headless there is no `JavaScriptBridge` at all, so an unguarded call is a
	`SCRIPT ERROR` — which CI treats as red, and which would abort the function
	and let this file print OK anyway if the sentinel were not watching.
	"""
	if OS.has_feature("web"):
		# Not a failure, just nothing this check can say — and unreachable in
		# practice, since Godot cannot be run headless as a web export.
		Sentinel.done("inert_offweb")
		return

	var node: Node = _voice_node()
	if node.is_available():
		_fail("is_available() answered true off-web — the whole file is supposed "
			+ "to be gated on OS.has_feature(\"web\")")

	if node.debug_line() != "":
		_fail("debug_line() answered non-empty off-web — voice is web-only")

	# THE CAMERA IS THE SAME PROMISE ONE FEATURE ALONG (bead godot-test1-xtr.6).
	# Driving it below proves it reaches no bridge; this proves it does not quietly
	# take EFFECT either — a camera reading as ON with no browser under it is a lie
	# `mp_ui` and every future reader of `is_camera_on()` would inherit.
	node.set_camera_enabled(true)
	if node.is_camera_on() or node.camera_denied():
		_fail("off-web set_camera_enabled(true) took effect (on=%s denied=%s) — the "
			% [node.is_camera_on(), node.camera_denied()]
			+ "camera is web-only like the rest of the file")

	# --- COMPLETENESS: the list must name every public method ---------------
	var driven: Dictionary = {}
	for call_row: Array in PUBLIC_CALLS:
		driven[String(call_row[0])] = true
	for entry: Dictionary in (node.get_script() as Script).get_script_method_list():
		var name: String = String(entry.get("name", ""))
		if name.begins_with("_") or driven.has(name):
			continue
		_fail("voice_chat.gd's public `%s()` is not driven by check 7 — add it to "
			% name + "PUBLIC_CALLS so it is proved to touch no bridge off-web")

	for call_row: Array in PUBLIC_CALLS:
		var name: String = String(call_row[0])
		if not node.has_method(name):
			_fail("PUBLIC_CALLS names `%s()`, which voice_chat.gd does not have" % name)
			continue
		node.callv(name, call_row[1] as Array)

	# NOTHING may have reached the browser: both bridge handles are still null and
	# the module was never started. (`_running` true off-web would mean `_start()`
	# ran, which is a `JavaScriptBridge.eval`.)
	if node._ck != null or node._send_cb != null or node._running:
		_fail("voice_chat.gd touched the browser off-web (_ck=%s _send_cb=%s _running=%s)"
			% [node._ck, node._send_cb, node._running])
	node.free()
	Sentinel.done("inert_offweb")


# ============================================================================
# 8. PROCESS_MODE_ALWAYS
# ============================================================================

func _check_always_process() -> void:
	"""
	Voice keeps flowing under every overlay and under the room-wide P (epic ruling
	2026-09-04): the media path is the browser's and never stops, so a GD half
	that stopped would strand a handshake mid-flight. `pause_selfcheck` owns
	"nothing in `scripts/*.gd` assigns `.paused`" globally — the half asserted
	here is that this file is inside that population, so a voice module that
	started pausing the tree could not hide behind a scan it was exempt from.
	"""
	var node: Node = _voice_node()
	if node.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("voice_chat.gd's process_mode is %s, not PROCESS_MODE_ALWAYS — voice "
			% node.process_mode + "would stop under every overlay")
	node.free()

	var source: String = FileAccess.get_file_as_string("res://scripts/voice_chat.gd")
	if source.is_empty():
		_fail("could not read voice_chat.gd — check 8 would pass vacuously")
		Sentinel.done("always_process")
		return
	# `pause_selfcheck`'s own rule, spelled the same way: the member, an `=` that
	# is not an `==`. Reading `get_tree().paused` as a CONDITION stays legal.
	var re := RegEx.create_from_string("\\.paused\\s*=[^=]")
	if re != null and re.search(source) != null:
		_fail("voice_chat.gd assigns `.paused` — `PauseHub` is the only writer "
			+ "(CLAUDE.md), and a voice module must not be a tenth pauser")
	Sentinel.done("always_process")


# ============================================================================
# 8b. `debug_line()` ANSWERS SOMETHING IN A ROOM
# ============================================================================

func _check_debug_line_in_a_room() -> void:
	"""
	`debug_line()` executed rather than short-circuited (bead `godot-test1-xtr.15`).

	THIS IS THE PRODUCER'S HALF ONLY. What the \\fo overlay does with the answer —
	the group lookup, the `has_method` guard, the append, and whether the node is
	ticked at all — is `perf_selfcheck` guard 7's, which drives a real overlay
	under a real paused tree. Neither can see the other's half, and the shipped
	bug was in that one.

	Check 7 only ever meets it OFF-web, where its first line returns "" and the
	assertion is that it does. So the whole body — the two early-return operands,
	the mode/tx spelling and the bridge fallback — ran nowhere in this suite, and
	an empty answer in a real room would have failed nothing. `hero_hud_selfcheck`
	check 7b's idiom: force `_is_web` on and hang a `RoomStub` off `_mp`, which is
	exactly what a browser in a room presents to these two operands.

	`_ck` stays null, which is a real state (the `/ice` round trip has not landed
	yet, or the module failed to install) and the one the bridge fallback exists
	for — so this drives the branch where the browser says nothing and the row
	must STILL name the mode and the transmit state. What it cannot reach is the
	live `stats()` string, which needs a browser; `_check_no_js_bool` and check 6b
	read that half as TEXT.
	"""
	var node: Node = _voice_node()
	var room := RoomStub.new()
	node._is_web = true
	node._mp = room

	var line: String = node.debug_line()
	if line.is_empty():
		_fail("debug_line() answered EMPTY on the web in a room — there is nothing "
			+ "for \\fo to draw on the one build this telemetry exists for")
	if not line.begins_with("Voice: mode="):
		_fail("debug_line() answered `%s`, which perf_overlay would draw as a row "
			% line + "that does not say what it is")
	# The two things this half of the line is FOR: which mode V is in, and whether
	# the microphone is open right now. Both driven at both ends, because a line
	# that always said ALWAYS/0 would satisfy a `contains` on one state. The mode
	# is SET rather than assumed: `_load_mode()` reads the store, which check 3
	# has already written in this process.
	node.set_mode(VoiceChat.Mode.ALWAYS_ON)
	line = node.debug_line()
	if not line.contains("mode=ALWAYS") or not line.contains("tx=0"):
		_fail("always-on with the mic closed reads `%s`" % line)
	node.set_mode(VoiceChat.Mode.PUSH_TO_TALK)
	node._tx = true
	line = node.debug_line()
	if not line.contains("mode=PTT") or not line.contains("tx=1"):
		_fail("push-to-talk with the mic open reads `%s` — the row is not tracking "
			% line + "the two states it exists to show")
	# The bridge fallback: no `_ck`, so the stats half is the placeholder rather
	# than a truncated line.
	if not line.contains("peers="):
		_fail("with no bridge the row is `%s` — the stats half must degrade to the "
			% line + "placeholder, not vanish")
	# AND THE NEGATIVE CONTROL, which is the half check 7 already owns from the
	# other side: out of the room there is nothing to report.
	room.online = false
	if node.debug_line() != "":
		_fail("debug_line() answered non-empty outside a room")

	node.free()
	room.free()
	Sentinel.done("debug_line_in_a_room")


# ============================================================================
# 9. WHAT V ACTUALLY DOES
# ============================================================================

func _check_mic_key_semantics() -> void:
	"""
	The shipped `_poll_input()`, driven with `Input.action_press` /
	`action_release` — `mobile_input`'s synthesis idiom, and no bridge is needed
	because `_tx` is GDScript state and `_set_tx()`'s only browser line is behind
	`_is_web and _running`.

	`_mp` is assigned here rather than found: off-web `_ready()` returns before the
	group lookup (it is inert by design, check 7), so the room a key press needs
	has to be handed in. Everything under test after that is the shipped function.
	"""
	var node: Node = _voice_node()
	var room := RoomStub.new()
	room.add_to_group("mp")
	root.add_child(room)
	node._mp = room

	# --- ALWAYS_ON: the key TOGGLES ----------------------------------------
	node.set_mode(VoiceChat.Mode.ALWAYS_ON)
	if node.is_tx():
		_fail("set_mode(ALWAYS_ON) left the mic open")
	await _tap(node)
	if not node.is_tx():
		_fail("ALWAYS_ON: the first press of %s did not open the mic" % MIC_ACTION)
	await _tap(node)
	if node.is_tx():
		_fail("ALWAYS_ON: the second press did not close the mic — the key must "
			+ "TOGGLE (owner ruling 2026-09-04), not latch")

	# --- PUSH_TO_TALK: the key HOLDS ---------------------------------------
	node.set_mode(VoiceChat.Mode.PUSH_TO_TALK)
	if node.is_tx():
		_fail("set_mode(PUSH_TO_TALK) left the mic open")
	Input.action_press(MIC_ACTION)
	await process_frame
	node._poll_input()
	if not node.is_tx():
		_fail("PUSH_TO_TALK: holding %s did not open the mic" % MIC_ACTION)
	# ...and it STAYS open while held, or push-to-talk is a toggle with extra steps.
	await process_frame
	node._poll_input()
	if not node.is_tx():
		_fail("PUSH_TO_TALK: the mic closed while the key was still held")

	# --- A MODE SWITCH WHILE HELD DROPS THE MIC ----------------------------
	# This is the one that leaks an open microphone: a hold-to-talk key released
	# into always-on would otherwise leave the mic open with nobody holding it.
	node.set_mode(VoiceChat.Mode.ALWAYS_ON)
	if node.is_tx():
		_fail("switching mode with %s held left the mic open" % MIC_ACTION)
	Input.action_release(MIC_ACTION)
	await process_frame

	# --- AND LEAVING THE ROOM DROPS IT TOO ---------------------------------
	await _tap(node)
	if not node.is_tx():
		_fail("ALWAYS_ON: the mic did not reopen after the mode round trip")
	room.online = false
	node._poll_input()
	if node.is_tx():
		_fail("the mic stayed open after the room went away — nothing off-room may "
			+ "keep transmitting")

	node.free()
	room.free()
	Sentinel.done("mic_key_semantics")


func _tap(node: Node) -> void:
	"""One press-and-release of the mic action, polled on the press frame.

	`Input.is_action_just_pressed()` compares the action's press frame against the
	CURRENT one, so the poll has to happen on the same frame as the press and the
	release has to be a frame later — which is exactly what a real key does and
	what a loop of `action_press` in one frame does not."""
	Input.action_press(MIC_ACTION)
	node._poll_input()
	await process_frame
	Input.action_release(MIC_ACTION)
	node._poll_input()
	await process_frame


# ============================================================================
# 10. HUD VOICE / CAMERA SWITCHES ABOVE MP BUTTON (bead godot-test1-xtr.20)
# ============================================================================

func _check_hud_voice_switches() -> void:
	"""
	HUD voice and camera toggles stacked above the MP button (bead godot-test1-xtr.20).

	Guards:
	  1. ONE STATE, TWO VIEWS: HUD buttons and MP panel buttons share the same handlers
	     and the same underlying voice state. Pressing a HUD toggle flips the stub
	     and updates both panel and HUD button labels in the same tick.
	  2. REVERSE SYNC: Mutating the voice state from the stub / panel side updates the
	     HUD button text when `_update_voice_ui()` is called.
	  3. CAMERA REFUSAL: When camera is denied, both HUD and panel camera buttons display
	     'Camera blocked' and become disabled.
	  4. VISIBILITY GATING: Hidden when `is_available()` is false or when offline.
	  5. TEXT INVARIANTS: Each HUD button's `pressed` signal connects to the panel's
	     handler, and `mp_ui.gd` declares no new state variables holding mic/deafen/camera
	     state (zero second state variables).
	  6. NEGATIVE CONTROLS: Mutated text checks fail against invalid handlers or injected
	     state variables.
	"""
	var room := RoomStub.new()
	room.online = true
	room.add_to_group("mp")
	root.add_child(room)

	var voice := VoiceUiStub.new()
	voice.available = true
	voice.add_to_group("voice")
	root.add_child(voice)

	var ui: Control = MultiplayerUIScript.new()
	root.add_child(ui)

	# Initial refresh to populate the button labels and visibility
	ui._update_voice_ui()
	ui._process(0.0)

	var hud_mic: Button = ui.get_node_or_null("HudMicButton")
	var hud_deaf: Button = ui.get_node_or_null("HudDeafenButton")
	var hud_cam: Button = ui.get_node_or_null("HudCameraButton")

	if hud_mic == null or hud_deaf == null or hud_cam == null:
		_fail("HUD voice buttons were not created as children of MultiplayerUI")
		ui.free()
		room.free()
		voice.free()
		Sentinel.done("hud_voice_switches")
		return

	# Initial visibility: online and available -> all three HUD buttons visible
	if not (hud_mic.visible and hud_deaf.visible and hud_cam.visible):
		_fail("HUD voice switches should be visible when online and voice is available")

	# Initial labels
	if hud_mic.text != "Mute mic" or ui._mic_mute_button.text != "Mute mic":
		_fail("Initial mic button label mismatch: hud='%s' panel='%s'" % [hud_mic.text, ui._mic_mute_button.text])
	if hud_deaf.text != "Deafen" or ui._deafen_button.text != "Deafen":
		_fail("Initial deafen button label mismatch: hud='%s' panel='%s'" % [hud_deaf.text, ui._deafen_button.text])
	if hud_cam.text != "Camera off" or ui._camera_button.text != "Camera off":
		_fail("Initial camera button label mismatch: hud='%s' panel='%s'" % [hud_cam.text, ui._camera_button.text])

	# --- 1. PRESS HUD MIC BUTTON: flips stub and updates panel text in same tick ---
	hud_mic.pressed.emit()
	if not voice.is_mic_muted():
		_fail("Pressing HudMicButton did not call set_mic_muted(true)")
	if ui._mic_mute_button.text != "Mic muted":
		_fail("Panel mic button text did not update to 'Mic muted' in same tick (got '%s')" % ui._mic_mute_button.text)
	if hud_mic.text != "Mic muted":
		_fail("HudMicButton text did not update to 'Mic muted' in same tick (got '%s')" % hud_mic.text)

	# Flip from panel side and assert HUD text follows
	voice.set_mic_muted(false)
	ui._update_voice_ui()
	if hud_mic.text != "Mute mic" or ui._mic_mute_button.text != "Mute mic":
		_fail("HUD mic text did not follow panel-side stub flip: hud='%s' panel='%s'" % [hud_mic.text, ui._mic_mute_button.text])

	# --- 2. PRESS HUD DEAFEN BUTTON: flips stub and updates panel text in same tick ---
	hud_deaf.pressed.emit()
	if not voice.is_deafened():
		_fail("Pressing HudDeafenButton did not call set_deafened(true)")
	if ui._deafen_button.text != "Deafened":
		_fail("Panel deafen button text did not update to 'Deafened' in same tick (got '%s')" % ui._deafen_button.text)
	if hud_deaf.text != "Deafened":
		_fail("HudDeafenButton text did not update to 'Deafened' in same tick (got '%s')" % hud_deaf.text)

	# Flip from panel side and assert HUD text follows
	voice.set_deafened(false)
	ui._update_voice_ui()
	if hud_deaf.text != "Deafen" or ui._deafen_button.text != "Deafen":
		_fail("HUD deafen text did not follow panel-side stub flip: hud='%s' panel='%s'" % [hud_deaf.text, ui._deafen_button.text])

	# --- 3. PRESS HUD CAMERA BUTTON: flips stub and updates panel text in same tick ---
	hud_cam.pressed.emit()
	if not voice.is_camera_on():
		_fail("Pressing HudCameraButton did not call set_camera_enabled(true)")
	if ui._camera_button.text != "Camera on":
		_fail("Panel camera button text did not update to 'Camera on' in same tick (got '%s')" % ui._camera_button.text)
	if hud_cam.text != "Camera on":
		_fail("HudCameraButton text did not update to 'Camera on' in same tick (got '%s')" % hud_cam.text)

	# Flip from panel side and assert HUD text follows
	voice.set_camera_enabled(false)
	ui._update_voice_ui()
	if hud_cam.text != "Camera off" or ui._camera_button.text != "Camera off":
		_fail("HUD camera text did not follow panel-side stub flip: hud='%s' panel='%s'" % [hud_cam.text, ui._camera_button.text])

	# Camera refused (camera_denied = true)
	voice.denied = true
	ui._update_voice_ui()
	if hud_cam.text != "Camera blocked" or not hud_cam.disabled:
		_fail("HUD camera button did not show 'Camera blocked' / disabled on permission denial")
	if ui._camera_button.text != "Camera blocked" or not ui._camera_button.disabled:
		_fail("Panel camera button did not show 'Camera blocked' / disabled on permission denial")
	voice.denied = false
	ui._update_voice_ui()

	# --- 4. ASSERT HIDDEN WHEN is_available() IS FALSE ---
	voice.available = false
	ui._update_voice_ui()
	ui._process(0.0)
	if hud_mic.visible or hud_deaf.visible or hud_cam.visible:
		_fail("HUD voice switches remained visible when voice.is_available() was false")

	# Also assert hidden when offline
	voice.available = true
	room.online = false
	ui._update_voice_ui()
	ui._process(0.0)
	if hud_mic.visible or hud_deaf.visible or hud_cam.visible:
		_fail("HUD voice switches remained visible when offline")

	# Clean up instantiated nodes
	ui.free()
	room.free()
	voice.free()

	# --- 5. TEXT ASSERTIONS & NEGATIVE CONTROLS ---
	var source: String = FileAccess.get_file_as_string("res://scripts/mp_ui.gd")
	if source.is_empty():
		_fail("Could not read res://scripts/mp_ui.gd for text assertion")
		Sentinel.done("hud_voice_switches")
		return

	var err_bindings := _verify_hud_voice_bindings(source)
	if not err_bindings.is_empty():
		_fail(err_bindings)

	# Negative control for handler bindings
	var mutated_bindings := source.replace("_on_mic_mute_pressed", "_on_wrong_mic_handler")
	if _verify_hud_voice_bindings(mutated_bindings).is_empty():
		_fail("Negative control failed: modified handler binding passed undetected")

	var err_vars := _verify_no_state_vars(source)
	if not err_vars.is_empty():
		_fail(err_vars)

	# Negative control for state variables
	var mutated_vars := source + "\nvar _mic_state_flag: bool = false\n"
	if _verify_no_state_vars(mutated_vars).is_empty():
		_fail("Negative control failed: injected state variable passed undetected")

	Sentinel.done("hud_voice_switches")


func _verify_hud_voice_bindings(source: String) -> String:
	var mic_bound: bool = source.contains("_hud_mic_button = _make_button(\"Mute mic\", _on_mic_mute_pressed)") \
		or source.contains("_hud_mic_button.pressed.connect(_on_mic_mute_pressed)")
	if not mic_bound:
		return "HudMicButton is not bound to _on_mic_mute_pressed in mp_ui.gd"

	var deafen_bound: bool = source.contains("_hud_deafen_button = _make_button(\"Deafen\", _on_deafen_pressed)") \
		or source.contains("_hud_deafen_button.pressed.connect(_on_deafen_pressed)")
	if not deafen_bound:
		return "HudDeafenButton is not bound to _on_deafen_pressed in mp_ui.gd"

	var camera_bound: bool = source.contains("_hud_camera_button = _make_button(\"Camera off\", _on_camera_pressed)") \
		or source.contains("_hud_camera_button.pressed.connect(_on_camera_pressed)")
	if not camera_bound:
		return "HudCameraButton is not bound to _on_camera_pressed in mp_ui.gd"

	return ""


func _verify_no_state_vars(source: String) -> String:
	var regex := RegEx.create_from_string("(?m)^var\\s+([a-zA-Z0-9_]+)")
	var allowed_new: Array[String] = ["_hud_mic_button", "_hud_deafen_button", "_hud_camera_button"]
	var allowed_old: Array[String] = ["_mic_state_label", "_mic_mute_button", "_deafen_button", "_camera_button"]
	for m: RegExMatch in regex.search_all(source):
		var var_name: String = m.get_string(1)
		if var_name in allowed_new:
			continue
		for kw: String in ["mic", "deafen", "camera"]:
			if kw in var_name.to_lower():
				if not var_name in allowed_old:
					return "found unauthorized voice state variable '%s' declared in mp_ui.gd" % var_name
	return ""

