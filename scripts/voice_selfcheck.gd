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
## ...and OVER ALL NINE, the completion sentinel: a GDScript runtime error aborts
## only the function it lands in, so a check that dies halfway simply stops
## asserting and the file prints OK. See `scripts/selfcheck_sentinel.gd`.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const VoiceChat := preload("res://scripts/voice_chat.gd")
const HelpOverlay := preload("res://scripts/help_overlay.gd")
const CityMapSelfcheck: GDScript = preload("res://scripts/city_map_selfcheck.gd")
const IntroSelfcheck: GDScript = preload("res://scripts/intro_selfcheck.gd")

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
	_check_inert_offweb()
	_check_always_process()
	_check_debug_line_in_a_room()
	await _check_mic_key_semantics()

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
	if not module.contains("var STYLE_DEFAULT = [4, 1.0, 1, 0.45];"):
		_fail("VOICE_JS declares no `var STYLE_DEFAULT = [4, 1.0, 1, 0.45]` — the "
			+ "cartoon camera's shipped look (bead godot-test1-xtr.16) is what the "
			+ "knobs fall back to and what a fresh profile paints; a drifted default "
			+ "restyles every room silently")
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

## The three spellings that together ARE the recovery (bead `godot-test1-xtr.7`),
## in the order the browser reaches them: the handler that notices, the state it
## acts on, and the call that repairs.
##
## Each is spelled as CODE rather than as a bare word, because the explanation
## beside the call names `restartIce()` too — a check on the word alone survives
## the deletion of the call it guards, which is not a hypothetical: it is what the
## first draft of this check did, measured.
const ICE_RESTART_NEEDLES: Array[String] = [
	"pc.oniceconnectionstatechange",
	"iceConnectionState !== 'failed'",
	"pc.restartIce()",
]


func _check_ice_restart() -> void:
	"""
	`VOICE_JS` read as TEXT again — this file's own `_check_no_js_bool` idiom, but
	its OWN check with its own stamp, because the two ask unrelated questions and
	a later edit that retires the boolean scan must not take this with it.

	WHAT IT DEFENDS. `members(json)` closes a `RTCPeerConnection` only when the id
	LEAVES `_members`, so a live member whose transport has died is never rebuilt
	by anything: the peer stays listed, stays un-muted, keeps its video tile, and
	is silent for the rest of the room with no status line and nothing retrying.
	`open()` answers that by restarting ICE, which rides the perfect-negotiation
	queue out over the existing `"vc"` relay as an ordinary offer — so there is no
	new signalling kind here to test, and `MpCodec.decode_vc` is untouched. The
	only thing a headless check CAN see is that the code is still there.

	THE STATE GUARD IS ONE OF THE THREE ON PURPOSE. `'disconnected'` is transient
	and self-healing; acting on it turns the handler into a re-offer loop on every
	path blip. A check that pinned only the handler and the call passed happily
	with `'failed'` swapped for `'disconnected'` — so the comparison is pinned too.
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
		_fail("voice_chat.gd's VOICE_JS is missing `%s`, so a PeerConnection that "
			% needle + "drops to iceConnectionState 'failed' (a NAT rebind, an "
			+ "expiring coturn allocation, a path break) stays dead for the whole "
			+ "life of the room — nothing else rebuilds a still-listed member's "
			+ "connection (godot-test1-xtr.7)")
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
		+ "rtt=42ms loss=0.0% style=0.42ms l4 m1.00 e1 s0.45 "
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
