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
## The payoff is bead .6: a camera track is `pc.addTrack(videoTrack)` and one
## renegotiation — no new signalling family, no second connection, no rework. It
## is also what lets the microphone arrive LATE: a connection is opened the
## moment a member appears, with a `recvonly` audio transceiver if the permission
## prompt has not been answered yet, and adding the real track when it lands just
## renegotiates.
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
## see the essay at the top of `intro_video.gd`). Every function in the module
## below answers a NUMBER, and `intro_selfcheck`'s blunt textual scan of every
## `scripts/*.gd` for `return true;` / `return false;` / `return !` covers this
## file the day it lands.
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

## The browser half, installed once at `window.ckVoice` on the first room join —
## the `intro_video.gd` idiom: one GD const string, one `JavaScriptBridge.eval`,
## all the state on `window` where the media actually lives.
##
## API, all of it answering a number: `start(selfId, iceJson, sendCallback)`,
## `members(idsJson)` (the diff that opens and closes connections),
## `recv(fromId, payloadJson)`, `stop()`, `micState()`, `frames()`.
##
## `recv` and not `signal`, which is what the design named it: `signal` is a
## GDScript keyword and `_ck.signal(...)` is a parser hazard on this side of the
## bridge for no gain on the other.
##
## EVERY SIGNALLING OPERATION FOR A PEER IS SERIALISED on that peer's own promise
## chain (`queue`). Without it the answerer's ICE can reach the offerer before
## its `setRemoteDescription(answer)` promise has resolved — `addIceCandidate`
## then rejects and that candidate is simply lost, which is a connection that
## silently never comes up on exactly the NAT pairs that needed it. The chain is
## also what makes the perfect-negotiation collision test read a settled
## `signalingState` instead of racing one.
const VOICE_JS: String = """
(function () {
	if (window.ckVoice) { return 1; }

	/* `gen` is the ROOM GENERATION, bumped by stop(). A getUserMedia prompt can
	   sit on screen for as long as the player likes, so its promise routinely
	   outlives the room it was asked for; every continuation compares against it
	   rather than trusting that it is still wanted. */
	var S = { self: '', cfg: null, peers: {}, stream: null, mic: 0, send: null, frames: 0, retry: 0, gen: 0, tx: 0 };


	/* One relayed frame out. Counted for bead .4's readout — the lobby meters
	   every sender at 120 frames burst / 30 per second (server/conn.go), which is
	   what the ICE batching below exists to stay inside of. */
	function post(id, obj) {
		if (!S.send) { return 0; }
		S.frames = S.frames + 1;
		try { S.send(id, JSON.stringify(obj)); } catch (e) { }
		return 1;
	}

	/* Serialise everything that touches one connection's signalling state. */
	function queue(p, job) {
		p.q = p.q.then(job).catch(function () { });
		return 1;
	}

	/* Remote audio is a DOM <audio> element, because Godot has no MediaStream
	   input — nothing about voice can go through the game's audio bus. */
	function play(id, stream) {
		var p = S.peers[id];
		if (!p || !document || !document.body) { return 0; }
		if (!p.audio) {
			var a = document.createElement('audio');
			a.autoplay = true;
			a.className = 'ck-voice';
			a.setAttribute('playsinline', '');
			a.style.display = 'none';
			document.body.appendChild(a);
			p.audio = a;
		}
		p.audio.srcObject = stream;
		var pr = p.audio.play();
		if (pr && pr.catch) { pr.catch(function () { retry(); }); }
		return 1;
	}

	/* The Host/Join click is the user activation play() wants, but it is sticky
	   rather than transient (Godot dispatches input on its own rAF tick), so a
	   rejection is possible. One listener, once, retries every element. */
	function retry() {
		if (S.retry) { return 0; }
		S.retry = 1;
		window.addEventListener('pointerdown', function () {
			S.retry = 0;
			for (var k in S.peers) {
				var a = S.peers[k].audio;
				if (a) { var q = a.play(); if (q && q.catch) { q.catch(function () { }); } }
			}
		}, { once: true });
		return 1;
	}

	function attach(p) {
		if (!S.stream || p.sent) { return 0; }
		var t = S.stream.getAudioTracks()[0];
		if (!t) { return 0; }
		/* Attaching fires onnegotiationneeded, which is the whole reason this is
		   perfect negotiation and not a one-shot handshake. */
		try { p.pc.addTrack(t, S.stream); p.sent = 1; } catch (e) { }
		return 1;
	}

	function setTx(val) {
		var active = (val === 1 || val === '1' || val === true) ? 1 : 0;
		S.tx = active;
		if (S.stream) {
			var ts = S.stream.getAudioTracks();
			for (var i = 0; i < ts.length; i++) { ts[i].enabled = (active === 1); }
		}
		return active;
	}

	function flush(id) {

		var p = S.peers[id];
		if (!p) { return 0; }
		p.timer = null;
		if (!p.cand.length) { return 0; }
		post(id, { vc: 'ice', c: p.cand.splice(0, 32) });
		if (p.cand.length) { p.timer = setTimeout(function () { flush(id); }, 100); }
		return 1;
	}

	function open(id) {
		if (S.peers[id] || !id || id === S.self) { return 0; }
		var pc = new RTCPeerConnection(S.cfg || {});
		/* POLITE = the lexicographically HIGHER id, mirroring the game mesh's
		   "the lower id offers" so both families agree on who yields. */
		var p = {
			pc: pc, polite: (S.self > id), making: 0, sent: 0,
			audio: null, cand: [], timer: null, q: Promise.resolve()
		};
		S.peers[id] = p;

		pc.onnegotiationneeded = function () {
			queue(p, function () {
				p.making = 1;
				return pc.setLocalDescription().then(function () {
					post(id, { vc: pc.localDescription.type, sdp: pc.localDescription.sdp });
				}).catch(function () { }).then(function () { p.making = 0; });
			});
		};

		/* TRICKLE, never a fully-gathered offer: the lobby caps one payload at
		   32 KB and an SDP with every candidate inlined approaches 10 KB. Batched
		   per 100 ms so the frame meter never sees a candidate storm. */
		pc.onicecandidate = function (ev) {
			var c = ev.candidate;
			p.cand.push({
				cand: c ? c.candidate : '',
				mid: (c && c.sdpMid) ? c.sdpMid : '0',
				mline: (c && c.sdpMLineIndex != null) ? c.sdpMLineIndex : 0
			});
			if (!p.timer) { p.timer = setTimeout(function () { flush(id); }, 100); }
		};

		pc.ontrack = function (ev) {
			play(id, (ev.streams && ev.streams[0]) ? ev.streams[0] : new MediaStream([ev.track]));
		};

		/* No microphone yet (still asking, or refused) — take the m-line anyway
		   so the handshake happens and this peer can at least LISTEN. */
		if (S.stream) { attach(p); }
		else { try { pc.addTransceiver('audio', { direction: 'recvonly' }); } catch (e) { } }
		return 1;
	}

	function close(id) {
		var p = S.peers[id];
		if (!p) { return 0; }
		if (p.timer) { clearTimeout(p.timer); }
		if (p.audio) {
			p.audio.srcObject = null;
			if (p.audio.parentNode) { p.audio.parentNode.removeChild(p.audio); }
		}
		try { p.pc.close(); } catch (e) { }
		delete S.peers[id];
		return 1;
	}

	function mic() {
		if (S.mic) { return 0; }
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) { S.mic = 3; return 0; }
		S.mic = 1;
		var gen = S.gen;
		/* NOISE SUPPRESSION IS THE BROWSER'S OWN — three constraints, no DSP of
		   ours (epic ruling: an RNNoise worklet only if .4 measures these red). */
		navigator.mediaDevices.getUserMedia({
			audio: { noiseSuppression: true, echoCancellation: true, autoGainControl: true },
			video: false
		}).then(function (st) {
			/* A grant that lands after the room went away RELEASES the device
			   instead of adopting it: stop() cannot cancel this promise, and a
			   tab left recording outside the room it asked for is the worst
			   possible way to get this wrong. */
			if (gen !== S.gen) {
				var stale = st.getTracks();
				for (var j = 0; j < stale.length; j++) { stale[j].stop(); }
				return;
			}
			S.stream = st;
			/* THE MIC STARTS OFF. The track exists on every connection so .2's V
			   key is one flag flip, but it transmits silence until then. */
			var ts = st.getAudioTracks();
			for (var i = 0; i < ts.length; i++) { ts[i].enabled = (S.tx === 1); }
			S.mic = 2;
			for (var k in S.peers) { attach(S.peers[k]); }
		/* A late REFUSAL is stale too — left alone it would suppress the next
		   room's prompt and report a denial nobody made this time. */
		}).catch(function () { if (gen === S.gen) { S.mic = 3; } });
		return 1;
	}

	function members(json) {
		var ids;
		try { ids = JSON.parse(json); } catch (e) { return 0; }
		if (!ids || !ids.length) { ids = []; }
		var want = {};
		var i;
		for (i = 0; i < ids.length; i++) { want[ids[i]] = 1; }
		for (var k in S.peers) { if (!want[k]) { close(k); } }
		for (i = 0; i < ids.length; i++) { open(ids[i]); }
		return 1;
	}

	function recv(id, json) {
		var m;
		try { m = JSON.parse(json); } catch (e) { return 0; }
		if (!S.peers[id]) { open(id); }
		var p = S.peers[id];
		if (!p) { return 0; }
		if (m.vc === 'ice') {
			queue(p, function () {
				var jobs = [];
				for (var i = 0; i < m.c.length; i++) {
					var e = m.c[i];
					var c = e.cand ? { candidate: e.cand, sdpMid: e.mid, sdpMLineIndex: e.mline } : null;
					jobs.push(p.pc.addIceCandidate(c).catch(function () { }));
				}
				return Promise.all(jobs);
			});
			return 1;
		}
		queue(p, function () {
			/* MDN's perfect negotiation: an impolite peer ignores a colliding
			   offer, a polite one rolls its own back (implicitly, inside
			   setRemoteDescription) and answers. */
			var collision = (m.vc === 'offer') && (p.making || p.pc.signalingState !== 'stable');
			if (!p.polite && collision) { return; }
			return p.pc.setRemoteDescription({ type: m.vc, sdp: m.sdp }).then(function () {
				if (m.vc !== 'offer') { return; }
				return p.pc.setLocalDescription().then(function () {
					post(id, { vc: p.pc.localDescription.type, sdp: p.pc.localDescription.sdp });
				});
			});
		});
		return 1;
	}

	function stop() {
		S.gen = S.gen + 1;
		S.tx = 0;
		for (var k in S.peers) { close(k); }
		S.peers = {};
		/* Release the capture device too, or the tab keeps its recording
		   indicator lit after leaving a room with nothing to transmit into. */
		if (S.stream) {
			var ts = S.stream.getTracks();
			for (var i = 0; i < ts.length; i++) { ts[i].stop(); }
			S.stream = null;
		}
		S.mic = 0;
		return 1;
	}

	window.ckVoice = {
		start: function (selfId, cfgJson, send) {
			S.self = String(selfId);
			S.send = send;
			try { S.cfg = JSON.parse(cfgJson); } catch (e) { S.cfg = {}; }
			mic();
			return 1;
		},
		members: members,
		recv: recv,
		stop: stop,
		setTx: setTx,
		txState: function () { return S.tx; },
		micState: function () { return S.mic; },
		frames: function () { return S.frames; }
	};

	return 1;
})()
"""

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

var _accum: float = 0.0


func _ready() -> void:
	add_to_group("voice")
	# Voice must keep flowing under every overlay and under the room-wide pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_mode()
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
	_accum += delta
	if _accum < POLL_INTERVAL:
		return
	_accum = 0.0
	_tick()



# ============================================================================
# THE POLL
# ============================================================================

func _tick() -> void:
	"""
	Reconcile the browser with the room, once every `POLL_INTERVAL`. Idempotent
	from top to bottom: every step asks what is true now rather than remembering
	what happened, so a missed signal or a late HTTP reply costs half a second and
	never a stuck handshake.
	"""
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


func _start(ice: Dictionary) -> bool:
	"""Install the browser module and hand it our id, the ICE config and the send seam."""
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
	return true


func _push_members() -> void:
	"""
	Hand the browser the room minus ourselves; it opens a connection for every id
	it has not seen and closes the ones that went away. The DIFF is the module's
	because the connections are, and doing it there is what keeps a leave from
	ever leaving an `<audio>` element behind.
	"""
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
	"""
	Say once, through the manager's own status line, that the microphone was
	refused. A denial is listen-only and NOT an error: the room joined, the remote
	voices play, and there is no retry loop — the next prompt is the next room.
	"""
	var state: Variant = _ck.micState()
	if typeof(state) != TYPE_INT and typeof(state) != TYPE_FLOAT:
		return
	var mic: int = int(state)
	if mic == _reported_mic or mic != MIC_DENIED:
		return
	_reported_mic = mic
	if _mp.has_signal("status"):
		_mp.emit_signal("status", MIC_BLOCKED_STATUS)


func _teardown() -> void:
	"""
	Close every connection, remove every `<audio>` element and release the capture
	device. Idempotent, and called from both ends — the poll noticing the room is
	gone, and this node leaving the tree.
	"""
	_set_tx(false)
	# ABOVE the `_running` guard: a room can end while the start-up window is

	# still open, and a queue that survived it would replay the last room's
	# handshake into the next one.
	_pending.clear()
	if not _running:
		return
	_running = false
	_pushed_members = ""
	_reported_mic = MIC_IDLE
	if _ck != null:
		_ck.stop()


# ============================================================================
# THE TWO SIGNALLING DIRECTIONS
# ============================================================================

func _on_js_send(args: Array) -> void:
	"""
	OUTBOUND. The browser has a payload for one peer; the lobby is ours to reach.
	`args` is `[peerId, jsonString]` — the module hands over JSON rather than a JS
	object because a `Dictionary` is what `send_signal_to` serialises, and one
	parse here is what keeps the bridge's marshalling out of the wire format.
	"""
	if args.size() < 2 or _mp == null or not is_instance_valid(_mp):
		return
	if not _mp.has_method("send_voice"):
		return
	var parsed: Variant = JSON.parse_string(str(args[1]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_mp.send_voice(str(args[0]), parsed as Dictionary)


func _flush_pending() -> void:
	"""Replay what arrived during the start-up window, in arrival order."""
	if _pending.is_empty():
		return
	var queued: Array = _pending
	_pending = []
	for entry: Array in queued:
		_ck.recv(str(entry[0]), JSON.stringify(entry[1]))


func _on_voice_relay(from: String, payload: Dictionary) -> void:
	"""
	INBOUND. Already through `MpCodec.decode_vc()` and already proved to come from
	a current room member — `MpManager._forward_voice()` owns both gates, so the
	only thing left here is to get it across the bridge.

	EXCEPT IN ONE WINDOW, AND DROPPING IT THERE DEADLOCKS THE PAIR (codex review
	2026-09-04). An incumbent sees a joiner the moment the lobby says so and
	offers straight away; the joiner's own module cannot start until its `/ice`
	round trip lands, which is later. Discarded, that offer never comes again —
	`onnegotiationneeded` fired once — and when the joiner then offers, an
	IMPOLITE incumbent reads its own unanswered local offer as a collision and
	ignores the joiner's too. Neither side ever answers. So the window is
	BUFFERED, `MpManager._pending_signals`'s answer to the same shape of race one
	signalling family along.
	"""
	if not _running or _ck == null:
		if _mp != null and is_instance_valid(_mp) and _pending.size() < MAX_PENDING_RELAYS:
			_pending.append([from, payload])
		return
	_ck.recv(from, JSON.stringify(payload))


func _on_room_changed(code: String, _members: Array) -> void:
	"""
	A leave tears everything down on the spot rather than at the next poll — half
	a second of a voice that is no longer in your room is half a second too much.
	A join or a membership change only wakes the poll, which is where the ICE
	config and the mic state are looked at anyway.
	"""
	_set_tx(false)
	if code.is_empty():
		_teardown()
		return
	_accum = POLL_INTERVAL


# ============================================================================
# TRANSMIT MODE & INPUT POLLING (bead godot-test1-xtr.2)
# ============================================================================

func get_mode() -> Mode:
	return _mode


func set_mode(new_mode: Mode) -> void:
	"""
	Switch between ALWAYS_ON and PUSH_TO_TALK.
	Switching mode resets _tx to false (a hold-to-talk key released into
	always-on must not leave the mic open).
	"""
	var changed: bool = (_mode != new_mode)
	if changed:
		_mode = new_mode
		_save_mode()
		mode_changed.emit(_mode)
	_set_tx(false)


func is_tx() -> bool:
	return _tx


func get_tx() -> bool:
	return _tx


func _is_in_room() -> bool:
	return _mp != null and is_instance_valid(_mp) and _mp.has_method("is_online") and bool(_mp.is_online())


func _poll_input() -> void:
	"""
	Poll the voice_mic action every frame in _process under PROCESS_MODE_ALWAYS.
	Works under tree pause and room-wide pause.
	ALWAYS_ON: Input.is_action_just_pressed("voice_mic") flips _tx.
	PUSH_TO_TALK: _tx = Input.is_action_pressed("voice_mic").
	Pushed to JS only on change via _set_tx().
	"""
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
	"""
	Load voice mode from localStorage ck_voice_mode on web, or ConfigFile [voice] section
	at BestRunStore.config_path on desktop. Default ALWAYS_ON.
	"""
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
	"""
	Persist voice mode only (never _tx) to localStorage ck_voice_mode on web, or
	ConfigFile [voice] section at BestRunStore.config_path on desktop.
	"""
	var mode_str := "push_to_talk" if _mode == Mode.PUSH_TO_TALK else "always_on"
	if OS.has_feature("web"):
		BestRunStore.ls_set(BestRunStore.LS_VOICE_MODE, mode_str)
	else:
		var cfg := ConfigFile.new()
		cfg.load(BestRunStore.config_path)
		cfg.set_value(BestRunStore.CONFIG_VOICE_SECTION, "mode", mode_str)
		cfg.save(BestRunStore.config_path)

