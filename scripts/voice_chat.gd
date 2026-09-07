extends Node
## ============================================================================
## VOICE CHAT — a browser-native audio mesh beside the game mesh. WEB ONLY.
## ============================================================================
## One `RTCPeerConnection` per room member carrying an audio track and nothing
## else, opened by the browser itself, signalled over the lobby relay this
## project already has with payloads tagged `"vc"` where the game mesh's own
## frames are tagged `"mp"`. Zero new servers, zero new lobby verbs, zero new
## Traefik routes: `MpManager._on_lobby_relay` was already written to ignore a
## payload without an `"mp"` key because "later phases share this same relay",
## and this is the first later phase.
##
## ----------------------------------------------------------------------------
## WEB ONLY — TWICE OVER, AND SAY BOTH
## ----------------------------------------------------------------------------
## BY DECISION (owner ruling 2026-09-04): voice and video ship on the web build
## alone. The desktop/editor build is a development target and gets nothing, and
## mobile is out of scope entirely — no touch button, no mobile clause anywhere
## in this feature.
##
## BY ENGINE LIMITATION, independently: Godot's `WebRTCPeerConnection` — the
## built-in web implementation and the `webrtc-native` GDExtension alike —
## exposes DATA CHANNELS ONLY. There is no `add_track`, no `MediaStream`, no
## microphone input. So voice can never ride `MpManager`'s existing connections,
## and the desktop build has no media-capable client to give it to. Even a
## self-hosted SFU would not change that (it still needs a media client), which
## is one of the reasons the epic rejected one.
##
## The gate is `OS.has_feature("web")`, exactly like `mobile_sensors.gd`: off the
## web export this node sets `process` off, connects to nothing and never touches
## `JavaScriptBridge`, so a headless self-check or a desktop run instances it and
## sees nothing happen at all.
##
## ----------------------------------------------------------------------------
## THE SPLIT: WHAT LIVES IN GDSCRIPT AND WHAT LIVES IN THE BROWSER
## ----------------------------------------------------------------------------
## The browser owns everything media: `getUserMedia`, the peer connections, ICE,
## the `<audio>` elements. GDScript owns the three things the browser cannot see
## — who is in the room, how a payload reaches them, and whether the payload is
## one this build is willing to act on. That is the whole of the seam:
##
##   * outbound — the JS module calls a RETAINED `JavaScriptBridge.create_callback`
##     with `(peerId, jsonString)`; this file parses it and hands it to
##     `MpManager.send_voice()`.
##   * inbound — `MpManager.voice_relay` fires with a payload already through
##     `MpCodec.decode_vc()` and already proved to come from a current member;
##     this file re-serialises it into `ckVoice.recv()`.
##
## The module itself lives in `scripts/voice_js.gd` (`class VoiceJs`, one const
## `SRC`), aliased here as `VOICE_JS` — this file holds the GDScript half only.
##
## The manager is found through group `"mp"` with `has_method` / `has_signal`
## guards (CLAUDE.md: group-based discovery, never a hard reference), so a scene
## run standalone degrades to silence instead of erroring.
##
## ----------------------------------------------------------------------------
## PERFECT NEGOTIATION FROM DAY ONE — this is what makes video cheap later
## ----------------------------------------------------------------------------
## Every connection is built with MDN's perfect-negotiation pattern rather than a
## one-shot offer/answer: `onnegotiationneeded` re-offers over the same `"vc"`
## tag whenever the set of tracks changes, and a glare is resolved by the POLITE
## peer yielding. Polite is the lexicographically HIGHER lobby id, which mirrors
## `mp_manager`'s own "the lower id offers" rule so both signalling families
## agree about who gives way.
##
## The payoff was bead .6, and it came out exactly that size: the camera is
## `pc.addTrack(videoTrack)` and one renegotiation, with no new signalling family,
## no second connection and no rework (see the VIDEO section at the foot). It
## is also what lets the microphone arrive LATE: a connection is opened the
## moment a member appears, with a `recvonly` audio transceiver if the permission
## prompt has not been answered yet, and adding the real track when it lands just
## renegotiates.
##
## **PERFECT NEGOTIATION ASSUMES RELIABLE SIGNALLING AND OURS IS A BEST-EFFORT
## RELAY**, which is the fourth rung the pattern does not come with (bead
## `godot-test1-xtr.19`). `post()` swallows every failure and `MpCodec.decode_vc`
## drops a malformed or oversized payload with a `push_warning` nobody reads, so
## an offer can simply vanish — and a PC left in `have-local-offer` can never fire
## `onnegotiationneeded` again, has nothing for `restartIce()` to ride, and (when
## impolite) treats every later offer as a collision to ignore. So an unanswered
## offer ROLLS ITSELF BACK on a timer, which returns the state to stable and lets
## the browser re-offer by itself. That is R1 of the heal ladder in `VOICE_JS`;
## R2 restarts ICE on a HELD `disconnected`, R3 rebuilds the one PC on both ends
## off a changed `a=fingerprint:`, and R4 re-plays a paused element. Every rung is
## bounded, and `heal=` in \fo says which one fired.
##
## ----------------------------------------------------------------------------
## THE MIC STARTS OFF (owner ruling 2026-09-04)
## ----------------------------------------------------------------------------
## The default mode is always-on, but the track is attached to every connection
## with `enabled = false`. What this bead ships alone is therefore "everyone
## hears, nobody transmits", which is the safe half; bead .2's V key is what
## flips the flag. Permission is asked ONCE per room join and a denial degrades
## to listen-only with one status line — never a retry loop.
##
## ----------------------------------------------------------------------------
## NO JS BOOLEAN MAY CROSS THE BRIDGE
## ----------------------------------------------------------------------------
## Godot 4.5.stable's web template marshals a JS boolean back through
## `JavaScriptBridge` as a corrupted Variant (bd memory
## `godot-test1-web-builds-godot-4-5-stable`, and the whole of godot-test1-8f8 —
## see the essay at the top of `intro_video.gd`). Every function in
## `scripts/voice_js.gd`'s module answers a NUMBER, and `intro_selfcheck`'s
## blunt textual scan of every `scripts/*.gd` for `return true;` /
## `return false;` / `return !` covers it the day it lands.
##
## ----------------------------------------------------------------------------
## PAUSE
## ----------------------------------------------------------------------------
## `PROCESS_MODE_ALWAYS`, and this file writes `get_tree().paused` nowhere (which
## `pause_selfcheck` scans for). Voice keeps flowing under every overlay and
## under the room-wide P — the media path is the browser's and never stops, so
## the GD half must not stop either or the poll below would stall mid-handshake.

const BestRunStore := preload("res://scripts/best_run_store.gd")

## Mode enum for voice chat transmission (bead godot-test1-xtr.2).
enum Mode {
	ALWAYS_ON = 0,
	PUSH_TO_TALK = 1,
}

signal mode_changed(mode: Mode)
signal tx_changed(active: bool)
signal mic_denied_changed(denied: bool)
## The camera's permission prompt came back (bead godot-test1-xtr.6). The press
## itself is synchronous, so this is the ASYNC half — granted, or refused — and
## it exists so the MP panel's button can stop saying "asking" without polling.
signal camera_changed(on: bool)

# ============================================================================
# TUNABLES
# ============================================================================


## How often the room is reconciled with the browser (seconds). Everything this
## node does is idempotent bookkeeping — is there a room, is the ICE config in
## yet, who is in it, did the permission prompt come back — so it is a POLL and
## not a web of signals: `MpManager.ice_config()` is empty until an HTTP round
## trip lands, which no membership signal is going to tell us about. 2 Hz is far
## faster than a human joins a room and is nothing next to a frame.
const POLL_INTERVAL: float = 0.5

## `ckVoice.micState()`'s answer. Numbers, never booleans (see the header), and
## declared here so the two languages cannot drift.
const MIC_IDLE: int = 0
const MIC_ASKING: int = 1
const MIC_GRANTED: int = 2
const MIC_DENIED: int = 3

## The one status line this bead owns, reported through `MpManager.status` so it
## lands in the MP panel beside every other room message. A plain literal: the
## translation key IS the English source string (CLAUDE.md's localization rule 1)
## and the panel's `Label` auto-translates it.
const MIC_BLOCKED_STATUS: String = "Voice: microphone blocked — listening only"

## Most relayed payloads held while the browser module is starting. See
## `_on_voice_relay()` for why the window exists; the cap is here because
## everything in that queue is peer input and an incumbent could otherwise be
## made to buffer without limit by a joiner that simply never finishes joining.
## An offer plus a few ICE batches per incumbent, against a 4-peer room.
const MAX_PENDING_RELAYS: int = 48

## THE SPEAKING INDICATOR (bead godot-test1-xtr.3). `ckVoice.levels()` is asked
## ten times a second — one bridge call, one string, every peer in it — and a
## level at or over the threshold RE-ARMS a hold rather than setting a boolean.
## The hold is the whole point: speech is gaps, and a dot driven straight off the
## instantaneous level strobes between syllables. 150 ms is short enough that
## silence still reads as silence inside the bead's 300 ms budget.
const LEVELS_INTERVAL: float = 0.1
const SPEAK_THRESHOLD: float = 8.0
const SPEAK_HOLD_MSEC: int = 150

## The key `levels()` reports the local microphone under. A lobby id is 32 hex
## characters, so this can never be one.
const SELF_LEVEL_KEY: String = "me"

## THE CAMERA (bead godot-test1-xtr.6). `ckVoice.camState()`'s answer, the mic's
## numbers one feature along — never booleans, see the header.
const CAM_IDLE: int = 0
const CAM_ASKING: int = 1
const CAM_ON: int = 2
const CAM_DENIED: int = 3

## How often the video tiles are reconciled with the hero row. The row is pinned
## to a screen corner, and the browser re-places a tile against the new canvas box
## on its own `resize` listener, so 5 Hz is generous — it is mostly the rate at
## which a hero CHANGES HANDS or a camera comes and goes. It is ALSO what covers a
## resize that changes the window's ASPECT: `hero_hud.tile_rect` answers in WINDOW
## pixels, and an aspect change moves which axis binds the stretch (and, under the
## desktop's `keep`, the letterbox margin) while the divisor changes on both — so
## such a resize really does move the fraction, and this poll pushes it in 200 ms.
const TILE_INTERVAL: float = 0.2

## How far inside a tile the picture is drawn, AS A FRACTION OF THE TILE — enough to
## leave `hero_hud`'s frame, its active ring and its SPEAKING ring showing around the
## video.
##
## IT WAS 3 ABSOLUTE PIXELS, AND THAT WAS ONLY EVER RIGHT BY ACCIDENT (bead
## `godot-test1-xtr.10`). `hero_hud.tile_rect()` used to answer in 1920x1080 DESIGN
## pixels, so a constant pad was a constant DESIGN pad; it answers in WINDOW pixels
## now, where 3 px is 3/s design px — 2.0 at the retina s = 1.5 the camera bug was
## reported from. `hero_hud` draws the speaking ring in a band `RING_INSET` (3) to
## `RING_INSET + RING_WIDTH` (5) DESIGN px inside the tile, so a 2 px pad puts the
## picture straight over the green ring, which is the row's only "who is talking"
## read. A fraction clears that band at every scale, which is the whole point.
##
## The number is `(RING_INSET + RING_WIDTH) / TILE_SIZE` in `hero_hud`'s terms —
## 5 / 92 since the tile grew from 80 to 92 (bead `godot-test1-y1o.37`), and the
## denominator is the half that rots silently: a stale 80 still passes check 6b's
## `>=`, it just eats 0.75 design px more of the picture than the ring needs.
## MIRRORED rather than preloaded exactly like `HERO_HUD_STATE_CAPTIVE` below — and
## `hero_hud_selfcheck` check 6b binds it to those real consts through the real
## stretched rect, so it cannot drift and cannot go back to an absolute grow.
##
## The overlay is ABOVE the canvas, so anything it covers is simply gone, which is why
## a CAPTIVE tile takes no picture at all: its cell bars are drawn ACROSS the whole
## tile and no inset can save them, and they are the one state this row says with a
## shape rather than a brightness. `_poll_tiles` skips those.
const TILE_INSET_FRAC: float = 5.0 / 92.0

## `hero_hud.STATE_CAPTIVE`, mirrored rather than preloaded — the row is found
## through its group like every other widget here, and a preload would be a hard
## reference the discovery convention refuses. `hero_hud_selfcheck` check 6 binds
## the two numbers so this cannot drift.
const HERO_HUD_STATE_CAPTIVE: int = 3

const VOICE_JS := VoiceJs.SRC

# ============================================================================
# STATE
# ============================================================================

## True only on the HTML5 export. Gates every `JavaScriptBridge` touch, so this
## whole file is inert (and never errors) on desktop, in the editor and headless.
var _is_web: bool = false

## `window.ckVoice`, and the callback the module calls to send a frame. BOTH are
## held in member vars for this node's lifetime: a `JavaScriptBridge` callback is
## garbage-collected the moment nothing references it, which silently detaches it
## from the JS that is still calling it (`mobile_sensors.gd` documents the same
## trap for its DOM listeners).
var _ck: JavaScriptObject = null
var _send_cb: JavaScriptObject = null

## The `mp` group's manager, cached after the first lookup.
var _mp: Node = null

## True while the browser module is running for a room — i.e. between the first
## tick that had both a room and an ICE config, and the teardown.
var _running: bool = false

## Validated relays that arrived before the browser module was running, as
## `[from, payload]` pairs in arrival order. See `_on_voice_relay()`.
var _pending: Array = []

## The member list last pushed into JS, as the JSON we pushed, so the diff costs
## a string compare per poll and no allocation when nothing changed.
var _pushed_members: String = ""

## The mic state we have already reported through `MpManager.status`. Reported
## ONCE per room, which is the difference between a status line and a nag.
var _reported_mic: int = MIC_IDLE

## Voice chat transmission mode: Mode.ALWAYS_ON (default) or Mode.PUSH_TO_TALK.
## Persisted to ConfigFile on desktop and localStorage on web.
var _mode: Mode = Mode.ALWAYS_ON

## Mic transmit state. Starts FALSE at every join in BOTH modes.
var _tx: bool = false

## The last room code seen through _on_room_changed, to distinguish real room
## transitions from roster-only updates (which emit room_changed with the same code).
var _last_code: String = ""

var _accum: float = 0.0

## THE ESCAPE HATCHES (bead godot-test1-xtr.3), mirrored here so the panel can
## label its buttons without a bridge call and so `_start()` can re-push them
## onto a module that outlives one room. Session state: nothing writes them to
## `BestRunStore` or `localStorage`, unlike `_mode`.
var _mic_muted: bool = false
var _deafened: bool = false

## INCOMING voice volume, 0.0-1.0 (bead godot-test1-xtr.9). Unlike the three
## switches above this one IS persisted, through the same `[voice]` /
## `localStorage` seam `_mode` uses — how loud other people are is a property of
## your speakers, not of the room you happen to be in. It is a third axis over
## the same `<audio>` elements rather than a variation on deafen, which is what
## makes "deafen remembers the volume" true with no code: `set_deafened()` never
## reads or writes this.
var _volume: float = 1.0
var _peer_muted: Dictionary = {}

## `id -> the msec at which its dot goes out`, re-armed by every loud sample.
var _speaking_until: Dictionary = {}

## `id -> the last value pushed into that peer's avatar`, so a highlight is
## written on the EDGE and a name tag is not re-modulated ten times a second.
var _speaking_pushed: Dictionary = {}

var _levels_accum: float = 0.0

## THE CAMERA (bead godot-test1-xtr.6). OFF BY DEFAULT and per ROOM: `_teardown()`
## clears it exactly as the JS `stop()` does, because a capture device is not
## something to leave running into the next room on the strength of an old press.
var _camera_on: bool = false

## The camera state we last told anybody about, so `camera_changed` fires on the
## EDGE — the prompt's answer — and not once a poll.
var _reported_cam: int = CAM_IDLE

## `peer id -> the tile rect last pushed`, as FRACTIONS of the canvas. The push is
## change-gated off this, so a still hero row costs one bridge call per poll and
## no DOM writes at all.
var _pushed_tiles: Dictionary = {}

## `peer id -> true` for everyone SENDING video, parsed out of the same
## `videoPeers()` string one function down — the sender roll-call the room
## event log diffs (bead godot-test1-k4j). Read, never re-parsed: the getter
## stays bridge-free and the log's 2 Hz costs no extra round trip.
var _video_senders: Dictionary = {}

var _tile_accum: float = 0.0

## The hero whose colour the browser's cartoon ramp was last built from (bead
## `godot-test1-xtr.11`), so the push is change-gated exactly like `_pushed_tiles`.
## Empty means "nothing pushed", which is also what a re-join has to see.
var _pushed_tint_hero: String = ""


func _ready() -> void:
	add_to_group("voice")
	# Voice must keep flowing under every overlay and under the room-wide pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_mode()
	_load_volume()
	_is_web = OS.has_feature("web")
	if not _is_web:
		set_process(false)
		return

	_mp = get_tree().get_first_node_in_group("mp")
	if _mp == null:
		set_process(false)
		return
	if _mp.has_signal("voice_relay"):
		_mp.connect("voice_relay", _on_voice_relay)
	if _mp.has_signal("room_changed"):
		_mp.connect("room_changed", _on_room_changed)


func _exit_tree() -> void:
	_teardown()


func _process(delta: float) -> void:
	_poll_input()
	_levels_accum += delta
	if _levels_accum >= LEVELS_INTERVAL:
		_levels_accum = 0.0
		_poll_levels()
	_tile_accum += delta
	if _tile_accum >= TILE_INTERVAL:
		_tile_accum = 0.0
		_poll_tiles()
	_accum += delta
	if _accum < POLL_INTERVAL:
		return
	_accum = 0.0
	_tick()



# ============================================================================
# THE POLL
# ============================================================================

func _tick() -> void:
	## Reconcile the browser with the room, once every `POLL_INTERVAL`. Idempotent
	## from top to bottom: every step asks what is true now rather than remembering
	## what happened, so a missed signal or a late HTTP reply costs half a second and
	## never a stuck handshake.
	if _mp == null or not is_instance_valid(_mp) or not _mp.has_method("is_online"):
		return
	if not _mp.is_online():
		_teardown()
		return
	if not _mp.has_method("ice_config") or not _mp.has_method("get_members"):
		return
	var ice: Dictionary = _mp.ice_config()
	# Empty until `/ice` lands — and forever in `lobby_only`, which is a headless
	# dev mode with no mesh and therefore nothing for voice to ride beside.
	if ice.is_empty():
		return
	if not _running and not _start(ice):
		return
	# BEFORE `_push_members()` on purpose: a replayed payload from somebody who
	# has since left opens a connection in the module, and the membership diff
	# that runs next is what closes it again.
	_flush_pending()
	_push_members()
	_report_mic()
	_report_camera()


func _start(ice: Dictionary) -> bool:
	## Install the browser module and hand it our id, the ICE config and the send seam.
	var installed: Variant = JavaScriptBridge.eval(VOICE_JS, true)
	# A number, never a boolean — see the header. Anything else means the eval
	# threw, and there is no voice on this browser; the room is unaffected.
	if typeof(installed) != TYPE_INT and typeof(installed) != TYPE_FLOAT:
		push_warning("VoiceChat: window.ckVoice failed to install — voice is off this session")
		set_process(false)
		return false
	_ck = JavaScriptBridge.get_interface("ckVoice")
	if _ck == null:
		push_warning("VoiceChat: window.ckVoice is missing after install — voice is off this session")
		set_process(false)
		return false
	if _send_cb == null:
		_send_cb = JavaScriptBridge.create_callback(_on_js_send)
	_ck.start(_mp.my_id() if _mp.has_method("my_id") else "", JSON.stringify(ice), _send_cb)
	_running = true
	_ck.setTx(1 if _tx else 0)
	# EVERY SWITCH IS REPLAYED HERE, and the per-peer set is the one that matters
	# (codex review 2026-09-04). A room's members are known from the `welcome`
	# frame, but this module cannot start until the `/ice` round trip lands — so
	# the panel is live and mutable for a second or two while `_running` is false,
	# and a Mute pressed in that window would otherwise sit in `_peer_muted`
	# reading "Muted" over a peer nobody had told the browser about. `_teardown()`
	# clears the set exactly as the JS `stop()` does, so this replays a window's
	# worth of presses and never the last room's.
	_ck.setMicMuted(1 if _mic_muted else 0)
	_ck.setDeafened(1 if _deafened else 0)
	# The volume is the one replayed value that came off DISK rather than out of
	# this session's window of presses — every room starts at the remembered one.
	_ck.setVolume(_volume_pct())
	_ck.setCamera(1 if _camera_on else 0)
	for id: Variant in _peer_muted:
		_ck.setPeerMuted(str(id), 1)
	return true


func _push_members() -> void:
	## Hand the browser the room minus ourselves; it opens a connection for every id
	## it has not seen and closes the ones that went away. The DIFF is the module's
	## because the connections are, and doing it there is what keeps a leave from
	## ever leaving an `<audio>` element behind.
	var ids: Array = []
	var you: String = _mp.my_id() if _mp.has_method("my_id") else ""
	for member: Variant in _mp.get_members():
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var id: String = str((member as Dictionary).get("id", ""))
		if id.is_empty() or id == you:
			continue
		ids.append(id)
	ids.sort()
	var json: String = JSON.stringify(ids)
	if json == _pushed_members:
		return
	_pushed_members = json
	_ck.members(json)


func _report_mic() -> void:
	## Say once, through the manager's own status line, that the microphone was
	## refused. A denial is listen-only and NOT an error: the room joined, the remote
	## voices play, and there is no retry loop — the next prompt is the next room.
	var state: Variant = _ck.micState()
	if typeof(state) != TYPE_INT and typeof(state) != TYPE_FLOAT:
		return
	var mic: int = int(state)
	if mic == _reported_mic or mic != MIC_DENIED:
		return
	_reported_mic = mic
	mic_denied_changed.emit(true)
	if _mp.has_signal("status"):
		_mp.emit_signal("status", MIC_BLOCKED_STATUS)


func _report_camera() -> void:
	## Watch the permission prompt come back and say so ONCE. A refusal is not an
	## error and gets no retry loop — the button below simply stops offering, exactly
	## as the microphone's status line does one feature along.
	var state: Variant = _ck.camState()
	if typeof(state) != TYPE_INT and typeof(state) != TYPE_FLOAT:
		return
	var cam: int = int(state)
	if cam == _reported_cam:
		return
	_reported_cam = cam
	if cam == CAM_DENIED:
		_camera_on = false
	if cam == CAM_ON or cam == CAM_DENIED:
		camera_changed.emit(cam == CAM_ON)


func _teardown() -> void:
	## Close every connection, remove every `<audio>` element and release the capture
	## device. Idempotent, and called from both ends — the poll noticing the room is
	## gone, and this node leaving the tree.
	_last_code = ""
	_set_tx(false)
	# Every dot goes out and every name tag is handed back its own colour before
	# the avatars are freed — a highlight left on is a highlight nothing will ever
	# clear. Per-peer mutes go with the room, mirroring the JS `stop()`.
	_clear_speaking()
	_peer_muted.clear()
	# THE CAMERA IS PER ROOM (see `_camera_on`), and the JS `stop()` releases the
	# device and removes every <video> — this side only has to agree about it, and
	# has to agree ABOVE the `_running` guard for the same reason `_pending` does.
	_pushed_tiles.clear()
	# The next room may hand us a different hero, and the browser module is about
	# to be stopped: forget what we pushed so the change gate re-pushes.
	_pushed_tint_hero = ""
	var had_camera: bool = _camera_on
	_camera_on = false
	_reported_cam = CAM_IDLE
	if had_camera:
		camera_changed.emit(false)
	# ABOVE the `_running` guard: a room can end while the start-up window is

	# still open, and a queue that survived it would replay the last room's
	# handshake into the next one.
	_pending.clear()
	var had_denial: bool = (_reported_mic == MIC_DENIED)
	_reported_mic = MIC_IDLE
	if had_denial:
		mic_denied_changed.emit(false)
	if not _running:
		return
	_running = false
	_pushed_members = ""
	if _ck != null:
		_ck.stop()


# ============================================================================
# THE TWO SIGNALLING DIRECTIONS
# ============================================================================

func _on_js_send(args: Array) -> void:
	## OUTBOUND. The browser has a payload for one peer; the lobby is ours to reach.
	## `args` is `[peerId, jsonString]` — the module hands over JSON rather than a JS
	## object because a `Dictionary` is what `send_signal_to` serialises, and one
	## parse here is what keeps the bridge's marshalling out of the wire format.
	if args.size() < 2 or _mp == null or not is_instance_valid(_mp):
		return
	if not _mp.has_method("send_voice"):
		return
	var parsed: Variant = JSON.parse_string(str(args[1]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_mp.send_voice(str(args[0]), parsed as Dictionary)


func _flush_pending() -> void:
	## Replay what arrived during the start-up window, in arrival order.
	if _pending.is_empty():
		return
	var queued: Array = _pending
	_pending = []
	for entry: Array in queued:
		_ck.recv(str(entry[0]), JSON.stringify(entry[1]))


func _on_voice_relay(from: String, payload: Dictionary) -> void:
	## INBOUND. Already through `MpCodec.decode_vc()` and already proved to come from
	## a current room member — `MpManager._forward_voice()` owns both gates, so the
	## only thing left here is to get it across the bridge.

	## EXCEPT IN ONE WINDOW, AND DROPPING IT THERE DEADLOCKS THE PAIR (codex review
	## 2026-09-04). An incumbent sees a joiner the moment the lobby says so and
	## offers straight away; the joiner's own module cannot start until its `/ice`
	## round trip lands, which is later. Discarded, that offer never comes again —
	## `onnegotiationneeded` fired once — and when the joiner then offers, an
	## IMPOLITE incumbent reads its own unanswered local offer as a collision and
	## ignores the joiner's too. Neither side ever answers. So the window is
	## BUFFERED, `MpManager._pending_signals`'s answer to the same shape of race one
	## signalling family along.
	if not _running or _ck == null:
		if _mp != null and is_instance_valid(_mp) and _pending.size() < MAX_PENDING_RELAYS:
			_pending.append([from, payload])
		return
	_ck.recv(from, JSON.stringify(payload))


func _on_room_changed(code: String, _members: Array) -> void:
	## A leave tears everything down on the spot rather than at the next poll — half
	## a second of a voice that is no longer in your room is half a second too much.
	## A join or a membership change only wakes the poll, which is where the ICE
	## config and the mic state are looked at anyway.
	if code != _last_code:
		_last_code = code
		_set_tx(false)
	if code.is_empty():
		_teardown()
		return
	_accum = POLL_INTERVAL


# ============================================================================
# TRANSMIT MODE & INPUT POLLING (bead godot-test1-xtr.2)
# ============================================================================

func is_available() -> bool:
	return _is_web


func mic_denied() -> bool:
	if not _is_web:
		return false
	if _ck != null:
		var state: Variant = _ck.micState()
		if typeof(state) == TYPE_INT or typeof(state) == TYPE_FLOAT:
			return int(state) == MIC_DENIED
	return _reported_mic == MIC_DENIED


func get_mode() -> Mode:
	return _mode


func set_mode(new_mode: Mode) -> void:
	## Switch between ALWAYS_ON and PUSH_TO_TALK.
	## Switching mode resets _tx to false (a hold-to-talk key released into
	## always-on must not leave the mic open).
	var changed: bool = (_mode != new_mode)
	if changed:
		_mode = new_mode
		_save_mode()
		mode_changed.emit(_mode)
	_set_tx(false)


func is_tx() -> bool:
	return _tx


func debug_line() -> String:
	## One-line debug summary for perf_overlay (\fo).
	## Returns "" when not in a room or off-web.
	## Otherwise: 'Voice: mode=PTT tx=1 ns=1 ec=1 agc=1 peers=3 rtt=42/55/61ms loss=0.0%'
	if not _is_web or not _is_in_room():
		return ""
	var mode_str := "PTT" if _mode == Mode.PUSH_TO_TALK else "ALWAYS"
	var tx_str := "1" if is_tx() else "0"
	var js_stats := ""
	if _ck != null and _running:
		var raw: Variant = _ck.stats()
		if typeof(raw) == TYPE_STRING:
			js_stats = str(raw)
	if js_stats.is_empty():
		js_stats = "ns=0 ec=0 agc=0 peers=0 rtt=- loss=0.0%"
	return _wrap_stats("Voice: mode=%s tx=%s %s" % [mode_str, tx_str, js_stats])


## The video half onto its own line (bead godot-test1-xtr.17).
##
## The browser answers ONE string — that is `levels()`'s rule and the reason the
## bridge is cheap — but \fo's Label neither autowraps nor clips, and the audio
## half alone already reaches the right edge of a 1152 px window at font 18. So
## the row is split HERE, where the width problem is, rather than by teaching the
## JS about a newline it cannot even spell inside a GDScript `\"\"\"` block.
##
## Keyed on `ice=`, the first video key, so a build whose bridge answered nothing
## (the placeholder above) is returned byte for byte unchanged.
func _wrap_stats(line: String) -> String:
	return line.replace(" ice=", "\n  ice=")


func _is_in_room() -> bool:
	return _mp != null and is_instance_valid(_mp) and _mp.has_method("is_online") and bool(_mp.is_online())


func _poll_input() -> void:
	## Poll the voice_mic action every frame in _process under PROCESS_MODE_ALWAYS.
	## Works under tree pause and room-wide pause.
	## ALWAYS_ON: Input.is_action_just_pressed("voice_mic") flips _tx.
	## PUSH_TO_TALK: _tx = Input.is_action_pressed("voice_mic").
	## Pushed to JS only on change via _set_tx().
	if not _is_in_room():
		if _tx:
			_set_tx(false)
		return
	match _mode:
		Mode.ALWAYS_ON:
			if Input.is_action_just_pressed("voice_mic"):
				_set_tx(not _tx)
		Mode.PUSH_TO_TALK:
			var held: bool = Input.is_action_pressed("voice_mic")
			if held != _tx:
				_set_tx(held)


func _set_tx(active: bool) -> void:
	if _tx == active:
		return
	_tx = active
	if _is_web and _running and _ck != null:
		_ck.setTx(1 if _tx else 0)
	tx_changed.emit(_tx)


func _load_mode() -> void:
	## Load voice mode from localStorage ck_voice_mode on web, or ConfigFile [voice] section
	## at BestRunStore.config_path on desktop. Default ALWAYS_ON.
	var loaded_mode := Mode.ALWAYS_ON
	if OS.has_feature("web"):
		var raw: String = BestRunStore.ls_get(BestRunStore.LS_VOICE_MODE)
		if raw == "push_to_talk" or raw == "1":
			loaded_mode = Mode.PUSH_TO_TALK
		elif raw == "always_on" or raw == "0":
			loaded_mode = Mode.ALWAYS_ON
	else:
		var cfg := ConfigFile.new()
		if cfg.load(BestRunStore.config_path) == OK:
			var val: Variant = cfg.get_value(BestRunStore.CONFIG_VOICE_SECTION, "mode", "always_on")
			if str(val) == "push_to_talk" or str(val) == "1":
				loaded_mode = Mode.PUSH_TO_TALK
			else:
				loaded_mode = Mode.ALWAYS_ON

	_mode = loaded_mode


func _save_mode() -> void:
	## Persist voice mode only (never _tx) to localStorage ck_voice_mode on web, or
	## ConfigFile [voice] section at BestRunStore.config_path on desktop.
	var mode_str := "push_to_talk" if _mode == Mode.PUSH_TO_TALK else "always_on"
	if OS.has_feature("web"):
		BestRunStore.ls_set(BestRunStore.LS_VOICE_MODE, mode_str)
	else:
		var cfg := ConfigFile.new()
		cfg.load(BestRunStore.config_path)
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "mode", mode_str)
		cfg.save(BestRunStore.config_path)


# ============================================================================
# INCOMING VOICE VOLUME (bead godot-test1-xtr.9)
# ============================================================================
## ONE slider in the MP panel's voice section, applied as `<audio>.volume` on
## every remote peer. Three things it deliberately is not:
##
##  * NOT a fourth escape hatch — deafen is still the switch and volume is the
##    dial. They are separate axes on the same elements (`muted` vs `volume`), so
##    the volume is simply remembered under a deafen and is back the moment it is
##    lifted, with nothing saving or restoring anything.
##  * NOT per peer. One control, one number, no new packet — a per-peer dial was
##    the bead's optional half and is skipped: the member row already carries the
##    one control it can fit (Mute), and the escape hatch a hostile mic needs is
##    binary anyway.
##  * NOT the microphone's. This is the RECEIVE side only; the browser's
##    `autoGainControl` owns the send side and no slider should fight it.
##
## Stored as an integer PERCENT string in the same `[voice]` / `localStorage`
## seam `_mode` uses, which is also the unit the bridge and the slider speak, so
## the fraction exists in exactly one place: this file's public API.


## The persisted key's spelling and the default, kept beside each other so a
## corrupted value and a missing one land on the same number.
const VOLUME_DEFAULT: float = 1.0


func get_volume() -> float:
	## Incoming voice volume, 0.0 (silent) to 1.0 (unattenuated).
	return _volume


func set_volume(value: float) -> void:
	## Set and persist the incoming voice volume. Clamped rather than rejected — a
	## slider hands us its own range and a stored file hands us anything at all, and
	## `<audio>.volume` throws outside 0..1.
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _volume):
		return
	_volume = clamped
	_save_volume()
	if _is_web and _running and _ck != null:
		_ck.setVolume(_volume_pct())


func _volume_pct() -> int:
	## The bridge's and the store's unit. A NUMBER crosses, never a boolean.
	return int(roundf(_volume * 100.0))


func _load_volume() -> void:
	## Load the volume from `localStorage` on web or the `[voice]` ConfigFile section
	## on desktop, exactly as `_load_mode()` does. Anything unreadable — absent,
	## empty, non-numeric, out of range — is `VOLUME_DEFAULT`, because a stored value
	## nobody can explain must not be able to make the room silent.
	var raw: String = ""
	if OS.has_feature("web"):
		raw = BestRunStore.ls_get(BestRunStore.LS_VOICE_VOLUME)
	else:
		var cfg := ConfigFile.new()
		if cfg.load(BestRunStore.config_path) == OK:
			raw = str(cfg.get_value(BestRunStore.CONFIG_VOICE_SECTION, "volume", ""))
	if not raw.is_valid_int():
		_volume = VOLUME_DEFAULT
		return
	var pct: int = raw.to_int()
	if pct < 0 or pct > 100:
		_volume = VOLUME_DEFAULT
		return
	_volume = float(pct) / 100.0


func _save_volume() -> void:
	if OS.has_feature("web"):
		BestRunStore.ls_set(BestRunStore.LS_VOICE_VOLUME, str(_volume_pct()))
	else:
		var cfg := ConfigFile.new()
		cfg.load(BestRunStore.config_path)
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "volume", str(_volume_pct()))
		cfg.save(BestRunStore.config_path)


# ============================================================================
# MUTE / DEAFEN / PER-PEER MUTE, AND THE SPEAKING INDICATOR (bead xtr.3)
# ============================================================================
## Three switches and one poll. THE SWITCHES ARE RECEIVE-SIDE OR SEND-SIDE AND
## NOTHING IS SIGNALLED — a peer whose microphone is a scream is exactly the peer
## who will not cooperate with a request to stop, so per-peer mute is
## `<audio>.muted` on THIS browser, deafen is all of them, and the mic mute is
## our own `track.enabled`. Nobody is told and nobody has to agree.
##
## MUTE WINS OVER V. `_tx` is the V key's answer and this file never overwrites
## it; the JS `applyMic()` transmits on `tx AND NOT micMuted`, so un-muting
## restores whatever V last said in whichever mode is current.
##
## SESSION STATE, NEVER PERSISTED — a mute is about the room you are in, not
## about you forever, so nothing here touches `BestRunStore`. Per-peer mutes are
## dropped at teardown on both sides of the bridge, which is also the documented
## ceiling: a peer who leaves and rejoins gets a FRESH lobby id and is therefore
## not muted any more.


func set_mic_muted(on: bool) -> void:
	if _mic_muted == on:
		return
	_mic_muted = on
	if _is_web and _running and _ck != null:
		_ck.setMicMuted(1 if on else 0)


func is_mic_muted() -> bool:
	return _mic_muted


func set_deafened(on: bool) -> void:
	if _deafened == on:
		return
	_deafened = on
	if _is_web and _running and _ck != null:
		_ck.setDeafened(1 if on else 0)


func is_deafened() -> bool:
	return _deafened


func set_peer_muted(id: String, on: bool) -> void:
	if id.is_empty():
		return
	if bool(_peer_muted.get(id, false)) == on:
		return
	if on:
		_peer_muted[id] = true
	else:
		_peer_muted.erase(id)
	if _is_web and _running and _ck != null:
		_ck.setPeerMuted(id, 1 if on else 0)


func is_peer_muted(id: String) -> bool:
	return bool(_peer_muted.get(id, false))


func is_speaking(id: String) -> bool:
	## Is that peer (or `SELF_LEVEL_KEY`, the local microphone) making noise right
	## now? Read by the MP panel's dots every frame and by `_push_speaking()` for the
	## name tags — a dictionary lookup, so polling it is free.
	return int(_speaking_until.get(id, 0)) > Time.get_ticks_msec()


func _poll_levels() -> void:
	## ONE bridge call, ONE string, every peer in it. A per-peer call would be four
	## `JavaScriptBridge` round trips ten times a second on a single-threaded web
	## export, which is the cost this format exists to avoid — and a per-peer
	## BOOLEAN could not cross the bridge at all (see the header).

	## Everything the string says is treated as untrusted text: it is our own module
	## talking, but it arrives as a Variant through a bridge that has been wrong
	## before, so a malformed pair is skipped rather than parsed optimistically.
	if not _running or _ck == null:
		if not _speaking_until.is_empty() or not _speaking_pushed.is_empty():
			_clear_speaking()
		return
	var raw: Variant = _ck.levels()
	if typeof(raw) != TYPE_STRING:
		return
	apply_levels(str(raw))


func apply_levels(raw: String) -> void:
	## Parse one levels string and re-arm the holds. Split out from the bridge call
	## so the format has a seam that can be driven without a browser — the bridge is
	## the one thing a headless check can never stand up.
	var now: int = Time.get_ticks_msec()
	for entry: String in raw.split(",", false):
		var parts: PackedStringArray = entry.split(":")
		if parts.size() != 2 or parts[0].is_empty() or not parts[1].is_valid_float():
			continue
		if parts[1].to_float() >= SPEAK_THRESHOLD:
			_speaking_until[parts[0]] = now + SPEAK_HOLD_MSEC
	_push_speaking()


func _push_speaking() -> void:
	## Drive the remote avatars' name tags, on the EDGE only.

	## The avatar is reached BY NODE NAME under the manager (`Peer_<id>`, the name
	## `_add_peer()` gives it) rather than through a new getter on `MpManager`: the
	## epic holds this feature's manager diff to the three-function voice seam, and a
	## `get_node_or_null` plus `has_method` is the same group-discovery degrade
	## everything else here uses. A build whose avatar predates `set_speaking` simply
	## shows no highlight.
	var stale: Array = []
	for id: Variant in _speaking_until:
		if int(_speaking_until[id]) <= Time.get_ticks_msec():
			stale.append(id)
	for id: Variant in stale:
		_speaking_until.erase(id)

	# The union of "speaking now" and "was told it was speaking" — the second half
	# is what turns a highlight back OFF.
	var ids: Dictionary = {}
	for id: Variant in _speaking_until:
		ids[id] = true
	for id: Variant in _speaking_pushed:
		ids[id] = true
	for id: Variant in ids:
		if str(id) == SELF_LEVEL_KEY:
			continue
		var on: bool = _speaking_until.has(id)
		if bool(_speaking_pushed.get(id, false)) == on:
			continue
		if on:
			_speaking_pushed[id] = true
		else:
			_speaking_pushed.erase(id)
		var avatar: Node = _avatar_for(str(id))
		if avatar != null:
			avatar.set_speaking(on)


func _avatar_for(id: String) -> Node:
	if _mp == null or not is_instance_valid(_mp) or id.is_empty():
		return null
	var avatar: Node = _mp.get_node_or_null("Peer_%s" % id)
	if avatar == null or not avatar.has_method("set_speaking"):
		return null
	return avatar


func _clear_speaking() -> void:
	for id: Variant in _speaking_pushed.keys():
		var avatar: Node = _avatar_for(str(id))
		if avatar != null:
			avatar.set_speaking(false)
	_speaking_pushed.clear()
	_speaking_until.clear()


# ============================================================================
# THE HERO ROW'S TWO QUESTIONS (bead godot-test1-xtr.8)
# ============================================================================
## The MP panel and the name tags are both places you have to be LOOKING to see
## that voice is working; the portrait row is on screen always. It asks two
## questions and they live here rather than in `hero_hud.gd` for the same reason
## `_poll_tiles` does: the hero -> HOLDER mapping is the lobby's, `SELF_LEVEL_KEY`
## is the browser module's, and "is there voice at all" is `_is_in_room()`. A row
## that re-derived any of that would be a second copy of this file's state.
##
## Both answer the NOTHING case for a row that is not in a room, not on the web
## or has no voice node at all, which is what keeps the row byte-identical to the
## one bead .7 shipped everywhere but a live browser room.


## `mic_badge()`'s answer. Numbers, and NONE means "draw nothing" — the badge is
## about the local microphone, so a row with no voice has no honest badge to draw
## rather than a grey one that implies a mic exists.
const MIC_BADGE_NONE: int = 0
const MIC_BADGE_OFF: int = 1     # a mic, idle: always-on with V off, or PTT unheld
const MIC_BADGE_TX: int = 2      # open and transmitting right now
const MIC_BADGE_MUTED: int = 3   # muted by hand — mute WINS over the mode
const MIC_BADGE_DENIED: int = 4  # the browser refused the microphone


func mic_badge() -> int:
	## What the local microphone is doing, as one of the `MIC_BADGE_*` numbers.

	## The ORDER is the priority the row draws: a denied mic can never transmit, and
	## a hand mute beats whatever the mode says (`applyMic()` in the browser module
	## is `tx && !muted`, and this is that rule read back out).

	## IT READS `_reported_mic`, NOT `mic_denied()`, AND THAT IS THE WHOLE POINT OF
	## THIS COMMENT. Its caller is a HUD widget's `_process`, so this runs 60 times a
	## second in a browser room, and `mic_denied()` asks `_ck.micState()` — a
	## `JavaScriptBridge` round trip — on every call. Every other bridge reader in
	## this file is throttled and one-call-per-poll for exactly that reason
	## (`LEVELS_INTERVAL` 10 Hz, `TILE_INTERVAL` 5 Hz, `POLL_INTERVAL` 2 Hz), and the
	## permission answer is the slowest-moving fact here: it changes once per room
	## join, when the user answers a prompt. `_report_mic()` already refreshes
	## `_reported_mic` off that same 2 Hz `_tick` and fires `mic_denied_changed` on
	## the edge, so the cached value is never more than half a second stale and the
	## frame path pays nothing. `mp_ui` keeps the live read — it asks once per panel
	## refresh, not once per frame.
	if not _is_web or not _is_in_room():
		return MIC_BADGE_NONE
	if _reported_mic == MIC_DENIED:
		return MIC_BADGE_DENIED
	if _mic_muted:
		return MIC_BADGE_MUTED
	if _tx:
		return MIC_BADGE_TX
	return MIC_BADGE_OFF


func is_hero_speaking(hero: String) -> bool:
	## Is the peer HOLDING that hero making noise right now?

	## The hero row is the LOCAL roster — four heroes, not four players — so a
	## speaking ring resolves through the lobby's `hero_holder()`, exactly like the
	## camera tiles of bead .6. The hero WE hold is the one exception: the browser
	## reports our own microphone under `SELF_LEVEL_KEY` and never under our lobby
	## id, because `S.peers` is remote peers only.

	## Everything is `has_method`-guarded and degrades to false: no manager, a
	## manager that predates `hero_holder`, a hero nobody holds.
	if not _is_web or not _is_in_room() or hero.is_empty():
		return false
	if _mp == null or not is_instance_valid(_mp) or not _mp.has_method("hero_holder"):
		return false
	var holder: String = str(_mp.hero_holder(hero))
	if holder.is_empty():
		return false
	if _mp.has_method("my_id") and holder == str(_mp.my_id()):
		return is_speaking(SELF_LEVEL_KEY)
	return is_speaking(holder)


func video_peer_ids() -> Array:
	## Who is SENDING video right now, as lobby ids — the sender roll-call
	## `_poll_tiles` parses out of `_ck.videoPeers()` (cached in
	## `_video_senders`), plus `SELF_LEVEL_KEY` when our own camera is reported
	## on. Deliberately NOT the placed-tile set: a captive or hero-less peer
	## still sends, and their tile coming down must never read as "camera off"
	## (review round 1).

	## A read-only view over cached state for the room event log (bead
	## godot-test1-k4j): bridge-free — the round trip happens once per tile poll,
	## not once per reader — and empty off the web or outside a room like every
	## other reader here.
	var out: Array = []
	for id: String in _video_senders:
		if id != SELF_LEVEL_KEY:
			out.append(id)
	if _reported_cam == CAM_ON and not out.has(SELF_LEVEL_KEY):
		out.append(SELF_LEVEL_KEY)
	return out


# ============================================================================
# VIDEO — THE CAMERA IN THE TEAMMATE'S HERO TILE (bead godot-test1-xtr.6)
# ============================================================================
## ADDITIVE, and that is the whole design: the camera is one more track on the
## connections bead .1 already built, so it is `addTrack` plus the renegotiation
## `onnegotiationneeded` already does over the same `vc` tag — no second
## `RTCPeerConnection`, no second signalling family, no `mp_codec` parser and no
## `mp_manager` edit. Switching it off is `removeTrack` and the same one
## renegotiation back.
##
## OPT-IN AND OFF BY DEFAULT (owner ruling 2026-09-04). The permission prompt is
## asked on the first press of the MP panel's Camera button and never on a join,
## so a player who never presses it is never asked; a refusal sticks for the room.
##
## WHERE THE PICTURE GOES: the tile of the hero that peer HOLDS. The hero row is
## the LOCAL roster — four heroes, not four players — so "in place of their hero
## portrait" resolves through the lobby's `hero_holder()`, which is also exactly
## `hero_hud`'s STATE_HELD (somebody else has him). Nobody's own tile is ever
## covered, because `S.peers` in the browser never contains ourselves.
##
## THE RENDER PATH IS A DOM OVERLAY, not frame copies (the bead weighed both).
## The browser decodes and composites, so the per-frame cost on this
## single-threaded export is ZERO; GDScript's whole contribution is a rect at
## 5 Hz, pushed only when it changes, in fractions of the canvas so the browser
## owns `devicePixelRatio` and every resize. The fallback if the overlay ever
## fights the canvas is the ImageTexture copy path, and it is written down in the
## bead rather than built here.


func set_camera_enabled(on: bool) -> void:
	# Off-web this may not so much as flip the flag: the panel row it is pressed
	# from is hidden behind `is_available()` there, and a camera that reads as ON
	# with no browser under it is a lie every reader of `is_camera_on()` inherits.
	if not _is_web:
		return
	if _camera_on == on:
		return
	# A refusal is not a state to toggle back into: asking again on every press is
	# the retry loop the epic rules out.
	if on and camera_denied():
		return
	_camera_on = on
	# `_pushed_tiles` is deliberately NOT cleared, and since the self-view (bead
	# `godot-test1-xtr.14`) put our OWN tile in it that is load-bearing rather than
	# merely harmless: most of the dictionary is the pictures TEAMMATES are sending,
	# which switching your own camera off does not take down, and the `me` row is a
	# rect the browser's `hideSelf` deliberately keeps too — so a fast off/on inside
	# one `_report_camera` window brings the picture straight back instead of leaving
	# both ends waiting for the other.
	if _is_web and _running and _ck != null:
		_ck.setCamera(1 if on else 0)
	camera_changed.emit(on)


func is_camera_on() -> bool:
	return _camera_on


func camera_denied() -> bool:
	if not _is_web or _ck == null:
		return false
	var state: Variant = _ck.camState()
	if typeof(state) != TYPE_INT and typeof(state) != TYPE_FLOAT:
		return false
	return int(state) == CAM_DENIED


func _poll_tiles() -> void:
	## Put every live remote picture over the tile of the hero its peer holds.

	## ONE bridge call for the roll-call (`videoPeers()`, `levels()`'s one-string
	## rule), then at most one `setTile` per peer whose rect actually MOVED — the
	## hero row is pinned to a screen corner, so in the steady state that is nothing
	## at all. The browser re-places the pictures against the new canvas box on its own
	## `resize` listener, so this poll stays silent through a resize that keeps the
	## window's ASPECT; one that changes it moves the fraction too (`tile_rect` answers
	## in window pixels, and an aspect change moves the binding axis of the stretch and
	## the letterbox margin) and the change-gate below pushes the new one.

	## Everything is `has_method`-guarded and degrades to no pictures: a scene with no
	## hero row, a manager that predates `hero_holder`, a peer holding no hero.
	if not _running or _ck == null:
		_pushed_tiles.clear()
		_video_senders.clear()
		return
	var raw: Variant = _ck.videoPeers()
	if typeof(raw) != TYPE_STRING:
		return
	var senders: Dictionary = {}
	for id: String in str(raw).split(",", false):
		senders[id] = true
	_video_senders = senders.duplicate()

	var live: Dictionary = {}
	var hud: Node = get_tree().get_first_node_in_group("hero_hud")
	_push_style_tint(hud)
	var win: Vector2 = Vector2(get_window().size) if get_window() != null else Vector2.ZERO
	var row_ready: bool = hud != null and hud.has_method("tile_rect") \
		and hud.has_method("hero_names") and hud.has_method("tile_state") \
		and win.x > 0.0 and win.y > 0.0
	var mp_ready: bool = _mp != null and is_instance_valid(_mp)
	if row_ready and mp_ready and _mp.has_method("hero_holder") and not senders.is_empty():
		for hero: String in hud.hero_names():
			var holder: String = str(_mp.hero_holder(hero))
			# Not a sender covers "nobody holds him", "I hold him" and "he has no
			# camera" in one test: our own id is never in the browser's peer set.
			if not senders.has(holder):
				continue
			var frac: Rect2 = _tile_fraction(hud, hero, win)
			if frac.size.x <= 0.0:
				continue
			live[holder] = true
			if _pushed_tiles.get(holder, Rect2()) == frac:
				continue
			_pushed_tiles[holder] = frac
			_ck.setTile(holder, frac.position.x, frac.position.y, frac.size.x, frac.size.y)

	# THE SELF-VIEW (bead godot-test1-xtr.14): our own outgoing picture on the tile
	# of the hero we DRIVE, through this same path. `CAM_ON` and not `_camera_on` is
	# the test, because the latter is only what was asked for — while the permission
	# prompt is up there is no stream and the browser would place an empty element.
	# `senders` says nothing about us: `S.peers` is remote peers only.
	if row_ready and mp_ready and _reported_cam == CAM_ON and _mp.has_method("my_hero"):
		var mine: String = str(_mp.my_hero())
		if not mine.is_empty():
			var self_frac: Rect2 = _tile_fraction(hud, mine, win)
			if self_frac.size.x > 0.0:
				live[SELF_LEVEL_KEY] = true
				if _pushed_tiles.get(SELF_LEVEL_KEY, Rect2()) != self_frac:
					_pushed_tiles[SELF_LEVEL_KEY] = self_frac
					_ck.setTile(SELF_LEVEL_KEY, self_frac.position.x, self_frac.position.y,
						self_frac.size.x, self_frac.size.y)

	# A hero handed back, a camera switched off, a peer gone: whatever we placed
	# and can no longer justify comes down. The browser also hides on its own
	# `mute`/`ended`, which is the half this poll cannot see in time.
	for id: Variant in _pushed_tiles.keys():
		if live.has(id):
			continue
		_pushed_tiles.erase(id)
		_ck.hideTile(str(id))


func _tile_fraction(hud: Node, hero: String, win: Vector2) -> Rect2:
	## Where a picture goes for one hero, as a fraction of the canvas — or an EMPTY
	## rect where no picture may be drawn at all.

	## ONE home for the two refusals, because a teammate's tile and our own
	## (bead `godot-test1-xtr.14`) have to answer them the same way:

	##   * A CAPTIVE TILE KEEPS ITS BARS. They are drawn across the whole tile, so no
	##     inset leaves them visible — and a benched peer still HOLDS the hero they
	##     are locked up as, which is exactly when this fires. It is the same for the
	##     hero we drive ourselves.
	##   * A tile smaller than its own padding has nothing left to draw in.

	## The pad is a FRACTION of the tile, never a pixel count: `tile_rect` is in WINDOW
	## pixels, so an absolute pad shrinks in design space as the window grows and eats
	## `hero_hud`'s speaking ring. Taken off the width so a tile that is not square (it
	## always is) still pads evenly.
	if int(hud.tile_state(hero)) == HERO_HUD_STATE_CAPTIVE:
		return Rect2()
	var tile: Rect2 = hud.tile_rect(hero)
	var pad: float = tile.size.x * TILE_INSET_FRAC
	if tile.size.x <= pad * 2.0 or tile.size.y <= pad * 2.0:
		return Rect2()
	var inset: Rect2 = tile.grow(-pad)
	return Rect2(inset.position / win, inset.size / win)


# ============================================================================
# THE CARTOON CAMERA'S HERO TINT (bead godot-test1-xtr.11)
# ============================================================================
## FORCED FOR THE ROOM (owner ruling 2026-09-06): the styled canvas track is the
## only video track that is ever attached, so there is no toggle here, no button
## in the MP panel, no `ui.csv` row and nothing in the `[voice]` store. The whole
## GDScript half of the effect is the four numbers below — the browser owns the
## pixels, as it owns the tiles.


func _push_style_tint(hud: Node) -> void:
	## Tell the browser which hero's colour to tint the mid-tones with.

	## It is the hero this peer DRIVES (`MpManager.my_hero()`), not the active tile:
	## the face in the picture is the player's, and the character they are playing is
	## the one the room reads them as. `hero_hud.gd`'s badge rule, one feature along.

	## CHANGE-GATED like `_pushed_tiles`, so in the steady state this whole function
	## is one `my_hero()` and a string compare — the browser is only reached when the
	## hero really changes hands.

	## THE TABLE IS `hero_hud.HERO_COLORS` AND IS NOT COPIED. It is read off the row's
	## own SCRIPT through the group node this poll already resolved — a mirrored copy
	## of four colours is four chances to drift, and `hero_hud.gd` may not be edited
	## to hand them out (the tile geometry is two other beads'). A row it has no
	## colour for, or no row at all, degrades to a neutral grey and still cartoons.
	if _ck == null or not _running:
		return
	# THE GATE IS KEYED ON THE HERO, SO THE ROW HAS TO BE THERE TO ANSWER FOR HIM.
	# With no `hero_hud` the answer is the grey fallback, and latching that would
	# leave a hero who is never asked about again wearing it for the whole room.
	if hud == null:
		return
	var hero: String = ""
	if _mp != null and is_instance_valid(_mp) and _mp.has_method("my_hero"):
		hero = str(_mp.my_hero())
	if hero == _pushed_tint_hero:
		return
	_pushed_tint_hero = hero
	var tint: Color = _hero_tint(hud, hero)
	# AND THE NAME WITH IT (bead godot-test1-xtr.13). The ACCESSORY the browser
	# draws over the face — Windman's blindfold, Primm's goggles, Teibi's beret,
	# Phoboman's fishbowl — is a SHAPE, which no colour can name and no table on
	# this side can hold. It is a fourth ARGUMENT rather than a second bridge
	# function because this is already the one writer and it is already gated on
	# exactly this hero: a swap (R, or a capture reassignment) repaints the
	# accessory on the next 5 Hz poll and renegotiates nothing.
	_ck.setStyleTint(int(tint.r8), int(tint.g8), int(tint.b8), hero)


func _hero_tint(hud: Node, hero: String) -> Color:
	## A hero with no colour — offline, benched, or a `CHARACTERS` entry the row
	## has no row for — gets the grey `hero_hud` gives such a tile, and that grey is
	## read out of the SAME constant map as the table beside it (`FALLBACK_COLOR`)
	## rather than hand-copied: it is right there, and a mirrored colour is a
	## mirrored colour. The literal is only for a row that answers neither.
	var consts: Dictionary = {}
	if hud != null and hud.get_script() != null:
		consts = (hud.get_script() as Script).get_script_constant_map()
	var fallback: Variant = consts.get("FALLBACK_COLOR", null)
	if typeof(fallback) != TYPE_COLOR:
		fallback = Color(0.55, 0.55, 0.60)
	if hero.is_empty():
		return fallback as Color
	var colors: Variant = consts.get("HERO_COLORS", null)
	if typeof(colors) != TYPE_DICTIONARY:
		return fallback as Color
	var row: Variant = (colors as Dictionary).get(hero, null)
	if typeof(row) != TYPE_COLOR:
		return fallback as Color
	return row as Color
