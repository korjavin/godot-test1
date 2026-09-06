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
	var S = {
		self: '', cfg: null, peers: {}, stream: null, mic: 0, send: null,
		frames: 0, retry: 0, gen: 0, tx: 0,
		/* THE ESCAPE HATCHES (bead godot-test1-xtr.3). All three are RECEIVE- or
		   SEND-side flags on this browser and nothing is signalled: a hostile mic
		   is exactly the case where the sender cannot be relied on to cooperate.
		   `muted` is keyed by lobby id and outlives its connection, so a peer that
		   blips through a renegotiation stays muted. */
		deaf: 0, micMuted: 0, muted: {},
		/* INCOMING VOLUME (bead godot-test1-xtr.9), 0-100 as an integer PERCENT
		   because that is the only shape allowed across the bridge — a fraction
		   would round-trip as a float, which is fine, but the percent is also
		   what the panel's slider already is, so there is one unit and no
		   conversion to get wrong. It is a SEPARATE axis from `deaf`/`muted`: an
		   element is silenced by `muted` and quietened by `volume`, so deafening
		   remembers the volume for free and undeafening restores it. */
		vol: 100,
		/* THE CAMERA (bead godot-test1-xtr.6). A SECOND TRACK on the same
		   connections — never a second RTCPeerConnection and never a second
		   signalling family: `addTrack` fires `onnegotiationneeded` and the
		   perfect-negotiation machinery above re-offers over the same `vc` tag.
		   `camWant` is what the player last asked for, `camState` is where the
		   permission prompt got to; the two differ while it is on screen.
		   `tiles` remembers each peer's rect as a FRACTION of the canvas, so a
		   resize is re-applied here at once; GDScript re-measures only when the
		   fraction itself moved, which an aspect-changing resize does. */
		cam: null, camState: 0, camWant: 0, tiles: {},
		/* THE CARTOON CAMERA (bead godot-test1-xtr.11). `cam` above is the RAW
		   device; what is ever ATTACHED to a connection is `styled`, the capture
		   stream of a 2D canvas the paint loop below draws the posterized,
		   hero-tinted, ink-outlined crop into. `styleSrc` is a hidden <video> fed
		   by `cam` (a MediaStream cannot be drawn; an element can), `styleLv` is
		   the per-pixel quantised level the second pass reads to find its edges,
		   and `styleRamp` is the colours that level indexes. `paintMs` is the
		   last frame's cost, reported in `stats()` for \fo.

		   THE STRENGTH KNOBS (bead godot-test1-xtr.16). `style` is the live
		   [levels, mix, edge, shadow], loaded from localStorage at install and
		   rewritten by `setStyle`; `styleTint` is the hero's rgb, remembered so the
		   ramp can be rebuilt when a knob moves rather than only when GDScript
		   pushes a new hero. */
		styled: null, styleSrc: null, styleCanvas: null, styleCtx: null,
		styleLv: null, styleRamp: null, styleRvfc: 0, styleTimer: null,
		styleWatch: null, paintMs: 0, style: null, styleTint: [140, 140, 150],
		/* THE HERO'S NAME (bead godot-test1-xtr.13), pushed beside the tint by the
		   one GDScript writer that already knows it. The tint is a colour and
		   cannot say which ACCESSORY to draw, and a name cannot say which colour
		   to use (`hero_hud.HERO_COLORS` stays the one table, in a language this
		   string cannot read) — so both travel, on one change-gated call. Empty
		   until GDScript speaks, which draws nothing. */
		styleHero: '',
		/* THE SENDER'S SELF-HEAL (bead godot-test1-xtr.18). `styleW` is the Worker
		   whose timer drives the paint loop in a HIDDEN tab, where rVFC never fires
		   and `setInterval` is throttled to 1 Hz; `recamN`/`recamWin`/`recamBusy`
		   bound the device re-acquisition to STYLE_RECAM_MAX a minute so a camera
		   that is gone for good settles on the signal-lost card instead of
		   hammering getUserMedia for the life of the room. */
		styleW: null, recamN: 0, recamWin: 0, recamBusy: 0,
		/* THE FACE-REGISTERED CROP (bead godot-test1-xtr.12). `faceState` is the
		   rung of the ladder this browser landed on — 0 not asked yet, 1 loading,
		   2 the vendored detector in `faceW`, 3 unavailable (centre crop for the
		   life of the room), 4 the browser's own `FaceDetector`. `faceTarget` is
		   where the detector last said the head is, `faceBox` is the box actually
		   drawn, lerping toward it; `faceHit` is when a face was last SEEN, which
		   is what expires a target back to the centre. `faceMs` is the detector's
		   round trip (off this thread on rung 2) and `faceMainMs` is the share of
		   it that was paid HERE — the two numbers the bead asks for separately. */
		faceW: null, faceNative: null, faceNoNative: 0, faceState: 0, faceBusy: 0, faceAt: 0,
		faceSent: 0, faceMs: 0, faceMainMs: 0, faceHit: 0, faceLerpAt: 0,
		faceBox: null, faceTarget: null,
		/* THE SENDER'S OWN HEALTH (bead godot-test1-xtr.17). `paintAt` is when
		   `paint()` last put pixels on the canvas — the only thing that can tell a
		   stalled paint loop from a working one, and reported as `paint=` — and
		   `srcTime`/`srcAt` are the SOURCE's clock: the last `currentTime` seen off
		   `styleSrc` and when it last moved. A frozen device (lid shut, another app
		   took the camera, a backgrounded tab) keeps decoding nothing while the
		   element happily reports its last frame, so a stopped `currentTime` is the
		   one signal that sees all three. */
		paintAt: 0, srcTime: -1, srcAt: 0,
		/* THE SELF-VIEW (bead godot-test1-xtr.14): one more <video>, fed the
		   STYLED stream so what you see of yourself is exactly what the room sees,
		   and placed through the same `S.tiles` / `placeTile` path as every
		   teammate's under the reserved key `SELF_TILE`. */
		selfVideo: null,
		/* THE HEAL TALLY (bead godot-test1-xtr.19), keyed by lobby id and
		   deliberately NOT on the peer row: rung 3 IS `close(id); open(id)`, so a
		   counter living on `p` would be zeroed by the very event it counts. Four
		   slots — [rollback, ice, rebuild, lastRebuildAt] — reported as `heal=`
		   so \fo says which rung fired rather than only that something did. */
		heal: {},
		/* One AudioContext for the whole module, and one AnalyserNode per stream
		   (remote) plus one for the local mic. `levels()` reads them all and
		   answers ONE string — never one bridge call per peer, and never a
		   boolean. */
		ctx: null, meterSelf: null,
		/* STATS TELEMETRY (bead godot-test1-xtr.4). Cached string, sampled at <= 1 Hz
		   only while stats() is polled. */
		statsCache: '', statsSampling: 0, statsLastTime: 0
	};

	/* Lazily built, and RESUMED every time it is asked for: an AudioContext
	   created before the tab's first gesture starts suspended, and a suspended
	   context meters silence. Failure is not an error — no meters means no dots,
	   which is exactly the graceful degrade an escape hatch may not have.

	   `resume()` RETURNS A PROMISE and a blocked one simply never resolves, so a
	   synchronous try/catch proves nothing (codex review 2026-09-04): anything not
	   already running arms the same one-shot gesture listener `<audio>.play()`
	   uses. That path is NOT reachable through play() alone — a muted or deafened
	   element autoplays happily while the context stays suspended, and every
	   analyser would then read zero for the rest of the session. */
	function ctx() {
		if (!S.ctx) {
			var C = window.AudioContext || window.webkitAudioContext;
			if (!C) { return null; }
			try { S.ctx = new C(); } catch (e) { return null; }
		}
		if (S.ctx.state !== 'running') {
			try { S.ctx.resume(); } catch (e) { }
			if (S.ctx.state !== 'running') { retry(); }
		}
		return S.ctx;
	}

	/* An analyser tapping one MediaStream. The stream must ALSO be attached to a
	   playing <audio> element for a remote track to be pumped at all (Chrome), and
	   it always is — `play()` is what calls this. */
	function meter(stream) {
		var c = ctx();
		if (!c || !stream) { return null; }
		try {
			var an = c.createAnalyser();
			an.fftSize = 512;
			var src = c.createMediaStreamSource(stream);
			src.connect(an);
			return { an: an, src: src, buf: new Uint8Array(an.fftSize) };
		} catch (e) { return null; }
	}

	function unmeter(m) {
		if (m && m.src) { try { m.src.disconnect(); } catch (e) { } }
		return 1;
	}

	/* RMS of the time-domain window, scaled to 0-100. A muted MIC reads 0 here
	   for free — `enabled = false` makes the track emit silence — so the local
	   dot needs no separate rule about transmit state. */
	function level(m) {
		if (!m) { return 0; }
		try { m.an.getByteTimeDomainData(m.buf); } catch (e) { return 0; }
		var sum = 0;
		for (var i = 0; i < m.buf.length; i++) {
			var v = (m.buf[i] - 128) / 128;
			sum += v * v;
		}
		var out = Math.round(Math.sqrt(sum / m.buf.length) * 400);
		return out > 100 ? 100 : out;
	}

	/* Deafen and per-peer mute are the same switch on a different set; the
	   volume is the third, independent axis over the same elements.

	   ponytail: `<audio>.volume` is IGNORED on iOS Safari (the element stays at 1
	   and the assignment is silently dropped), so on an iPhone this dial moves the
	   label and nothing else. Accepted: MOBILE IS OUT OF SCOPE for this whole epic
	   by owner ruling 2026-09-04 — no touch control, no mobile verification, no
	   mobile clause in any child — and `muted` and `track.enabled`, which every
	   escape hatch here rides, do work there. The upgrade path if that ruling ever
	   changes is a `GainNode` per remote stream (the analyser graph already has the
	   AudioContext), and it is NOT free: the element has to keep playing for Chrome
	   to pump a remote track at all, so it would have to be muted and routed
	   through the graph, which puts every remote voice behind a context that starts
	   SUSPENDED until a gesture — silence on the platforms that work today, to fix
	   a dial on one that is out of scope. */
	function applyAudio() {
		for (var k in S.peers) {
			var a = S.peers[k].audio;
			if (a) {
				a.muted = (S.deaf === 1 || S.muted[k] === 1);
				a.volume = S.vol / 100;
			}
		}
		return 1;
	}

	/* MIC MUTE WINS over the V state: the track transmits only when the player
	   asked to talk AND has not muted themselves. Un-muting restores whatever V
	   last said, because `S.tx` was never touched. */
	function applyMic() {
		if (!S.stream) { return 0; }
		var on = (S.tx === 1 && S.micMuted === 0);
		var ts = S.stream.getAudioTracks();
		for (var i = 0; i < ts.length; i++) { ts[i].enabled = on; }
		return 1;
	}


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
		/* Re-applied on every track, not just the first: a renegotiation hands us
		   a new stream for a peer whose mute the player set before it arrived. */
		p.audio.muted = (S.deaf === 1 || S.muted[id] === 1);
		p.audio.volume = S.vol / 100;
		unmeter(p.meter);
		p.meter = meter(stream);
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
			/* The same gesture the <audio> elements were waiting for is the one an
			   AudioContext wants, so the meters come alive with the sound. */
			ctx();
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

	/* ------------------------------------------------------------------------
	   THE CAMERA, AND THE TILE IT IS DRAWN IN (bead godot-test1-xtr.6)
	   ------------------------------------------------------------------------
	   The picture is a DOM <video> absolutely positioned over the Godot canvas —
	   `intro_video.gd`'s precedent — and NOT a frame copied through the bridge:
	   the browser decodes and composites it, so a peer's camera costs this
	   single-threaded export nothing per frame. The GDScript half only ever pushes
	   a rect, and only when it changes.

	   THE RECT CROSSES AS FRACTIONS OF THE CANVAS, never pixels. Godot measures in
	   window pixels; the canvas's CSS box is those pixels divided by
	   devicePixelRatio and moved by whatever the page's layout says. Multiplying a
	   fraction by `getBoundingClientRect()` is that whole conversion, and it is
	   also why a resize is re-applied here without waiting for GDScript. It does
	   NOT make the fraction resize-invariant: a resize that KEEPS the window's
	   aspect moves nothing, but one that changes it moves the fraction too (see
	   `hero_hud.tile_rect`), which the 5 Hz poll pushes within 200 ms.

	   ponytail: mounted on `document.body`, so Godot's own canvas-only fullscreen
	   (`DisplayServer.WINDOW_MODE_FULLSCREEN` calls `canvas.requestFullscreen()`)
	   would hide it — reachable only from the touch fullscreen button, and mobile
	   is out of scope by owner ruling. The browser's own F11 sets no
	   `fullscreenElement`, so that one is covered. The documented upgrade path if
	   this ever bites is the bead's ImageTexture frame-copy fallback. */

	function canvasBox() {
		var c = document.getElementById('canvas') || document.querySelector('canvas');
		if (!c || !c.getBoundingClientRect) { return null; }
		return c.getBoundingClientRect();
	}

	/* THE RESERVED TILE KEY FOR OUR OWN PICTURE (bead godot-test1-xtr.14). A lobby
	   id is 32 hex characters, so this can never collide with one, and it is
	   `SELF_LEVEL_KEY` on the GDScript side — the browser already reports the local
	   microphone's level under the same name. */
	var SELF_TILE = 'me';

	/* HOW MANY 1 Hz SAMPLES OF ZERO DECODED FRAMES MAKE A STALL (bead
	   godot-test1-xtr.17). Three, because that is the bead's three seconds and
	   because one is noise: a sample straddling a keyframe gap, a tab that just
	   came back, a peer whose first frame has not landed. */
	var STALL_SAMPLES = 3;

	/* THE RECEIVER'S MARK, AND IT IS A FILTER RATHER THAN A COLOUR. `hero_hud`'s
	   ring is untouched and nothing is drawn under a picture nobody can see: the
	   <video> element itself goes grey and INK-dim, which is the film language
	   spelled in the two things CSS can do without naming a hue. It may NOT name
	   one — `hero_hud_selfcheck` check 8 greps `scripts/` for the six film hexes
	   and they may be typed in `hud_theme.gd` alone.

	   `placeTile` rewrites `cssText` wholesale, so the mark has to be re-applied
	   there or every resize and every rect push clears it. */
	function stallFilter(id) {
		if (id === SELF_TILE) { return ''; }
		var p = S.peers[id];
		if (p && p.stalled === 1) { return 'filter:grayscale(1) brightness(0.35);'; }
		return '';
	}

	/* ONE PEER'S VERDICT, off one sample's framesDecoded DELTA. This is the only
	   class of stuck picture a receiver can see by itself: a sender whose paint
	   loop stopped (a hidden tab, a throw inside paint) stops shipping frames, so
	   the delta goes to zero while the element keeps showing its last one forever.
	   A sender whose DEVICE froze is deliberately not detectable here — the delta
	   keeps advancing — and is captioned in the pixels by the sender instead
	   (bead godot-test1-xtr.18's card). */
	function markStall(id, p, dIn) {
		/* `dIn` is NEGATIVE for "unknown" — the report carried no `framesDecoded`,
		   or this is the peer's first sample. Only a KNOWN zero is a stall: folding
		   unknown into zero would dim every tile on a browser that does not report
		   the field and never let one recover (codex review 2026-09-06). */
		if (p.hasVideo !== 1 || dIn !== 0) {
			p.vinZero = 0;
			if (p.stalled === 1) { p.stalled = 0; placeTile(id); }
			return 0;
		}
		p.vinZero = p.vinZero + 1;
		if (p.vinZero >= STALL_SAMPLES && p.stalled !== 1) {
			p.stalled = 1;
			placeTile(id);
		}
		return 1;
	}

	/* THE TWO QUESTIONS EVERY TILE ASKS, and the only two places the self-view is
	   a special case: which element draws this key, and does it have a picture.
	   Everything below — placing, blanking, the resize walk, GDScript's rect —
	   then treats our own tile exactly like a teammate's. */
	function tileEl(id) {
		if (id === SELF_TILE) { return S.selfVideo; }
		var p = S.peers[id];
		return p ? p.video : null;
	}

	function tileLive(id) {
		/* The self-view is fed by a stream this module built, so there is no
		   `mute`/`unmute` to wait for: the element existing IS the picture. */
		if (id === SELF_TILE) { return S.selfVideo ? 1 : 0; }
		var p = S.peers[id];
		return (p && p.hasVideo === 1) ? 1 : 0;
	}

	function placeTile(id) {
		var el = tileEl(id);
		var t = S.tiles[id];
		if (!el || !t) { return 0; }
		/* A REMEMBERED RECT IS NOT A REASON TO SHOW SOMETHING. `blankTile` keeps the
		   rect through a stall on purpose, so the `resize` listener below — which
		   walks every remembered rect — would otherwise un-blank a frozen frame. */
		if (tileLive(id) !== 1) { return 0; }
		var r = canvasBox();
		if (!r || t[2] <= 0 || t[3] <= 0) { return 0; }
		el.style.cssText = 'position:fixed;pointer-events:none;object-fit:cover;' +
			'background:#000;z-index:2147482000;' +
			'left:' + (r.left + t[0] * r.width) + 'px;' +
			'top:' + (r.top + t[1] * r.height) + 'px;' +
			'width:' + (t[2] * r.width) + 'px;' +
			'height:' + (t[3] * r.height) + 'px;' + stallFilter(id);
		/* Explicit rather than relying on `cssText` having cleared it: this is the
		   one line that undoes a `blankTile`, and it should say so. */
		el.style.display = '';
		return 1;
	}

	function setTile(id, fx, fy, fw, fh) {
		S.tiles[String(id)] = [fx, fy, fw, fh];
		return placeTile(String(id));
	}

	/* TWO WAYS TO TAKE A PICTURE DOWN, and the difference is who owns the rect.
	   `hideTile` is GDScript's — it FORGETS the rect, so the next poll has to push
	   one. `blankTile` is the browser's, for a track that stalled: the rect is kept
	   so `placeTile` can bring the picture straight back. Deleting it there would
	   wedge the tile forever, because a stall and its recovery inside one poll
	   window leave GDScript's change-gate holding the identical rect and pushing
	   nothing, and a row pinned to a screen corner never moves to force the issue. */
	function hideTile(id) {
		delete S.tiles[String(id)];
		return blankTile(id);
	}

	function blankTile(id) {
		var el = tileEl(String(id));
		if (el) { el.style.display = 'none'; }
		return 1;
	}

	/* Re-place every remembered rect against the new canvas box. For a resize that
	   keeps the window's ASPECT that is the whole fix — the fraction did not move.
	   One that CHANGES the aspect moves the fraction as well (the axis that binds
	   the canvas_items stretch changes, and the divisor changes on both), and the
	   GD poll pushes that within 200 ms; this keeps the picture on the canvas in
	   the meantime. */
	function replaceTiles() {
		for (var k in S.tiles) { placeTile(k); }
		return 1;
	}

	function showVideo(id, stream) {
		var p = S.peers[id];
		if (!p || !document || !document.body) { return 0; }
		if (!p.video) {
			var v = document.createElement('video');
			v.autoplay = true;
			/* MUTED, always: the sound is the <audio> element's job, and a second
			   voice out of this element would be an echo of the same peer. */
			v.muted = true;
			v.className = 'ck-voice-cam';
			v.setAttribute('playsinline', '');
			v.style.cssText = 'display:none;';
			document.body.appendChild(v);
			p.video = v;
		}
		p.video.srcObject = stream;
		var pr = p.video.play();
		if (pr && pr.catch) { pr.catch(function () { }); }
		/* Nothing is shown until GDScript says where the tile is — a picture
		   parked at 0,0 over the corner of the screen is worse than none. */
		placeTile(id);
		return 1;
	}

	/* THE SELF-VIEW (bead godot-test1-xtr.14, owner: "file a bead to see own video
	   stream also"). One local element fed the SAME stream the room is being sent,
	   which is the rule that made this depend on the cartoon: a self-view of the
	   raw face would lie about what the other three see.

	   It costs NOTHING on the wire — no track, no signalling, no verb — and
	   nothing on the frame: the browser was already decoding this stream for the
	   encoder, and GDScript's whole contribution is one more rect in the 5 Hz poll
	   it was already running.

	   NOT MIRRORED, and that is a decision rather than an oversight: a video app
	   mirrors your self-view because you are looking at yourself, but this tile is
	   a portrait of the CHARACTER and sits in a row of three others drawn the way
	   the room sees them. */
	function showSelf() {
		var st = styleStream();
		if (!st || !document || !document.body) { return 0; }
		if (!S.selfVideo) {
			var v = document.createElement('video');
			v.autoplay = true;
			/* MUTED, always — and here it is not even an echo question: this is our
			   own microphone coming straight back out of our own speakers. */
			v.muted = true;
			v.className = 'ck-voice-self';
			v.setAttribute('playsinline', '');
			v.style.cssText = 'display:none;';
			document.body.appendChild(v);
			S.selfVideo = v;
		}
		S.selfVideo.srcObject = st;
		var pr = S.selfVideo.play();
		if (pr && pr.catch) { pr.catch(function () { }); }
		/* Nothing is shown until GDScript says where the tile is — `showVideo`'s
		   rule, for the same reason. */
		placeTile(SELF_TILE);
		return 1;
	}

	function hideSelf() {
		/* BLANK, NEVER DELETE THE RECT — `blankTile`'s own rule, and this function
		   is the browser's end of exactly the wedge documented there. GDScript's
		   change gate (`_pushed_tiles`) keeps our rect across a camera toggle, and
		   `_reported_cam` is only refreshed at 2 Hz: an off-press and an on-press
		   inside one of those windows leaves the gate holding a rect the browser
		   had forgotten, so `_poll_tiles` pushes nothing and `showSelf`'s
		   `placeTile` has no rect to place — teammates would still see you while
		   your own tile stayed dark, for the rest of the room. The slow path still
		   deletes it: `_poll_tiles` calls `hideTile('me')` when the camera really
		   is off. */
		blankTile(SELF_TILE);
		if (S.selfVideo) {
			S.selfVideo.srcObject = null;
			if (S.selfVideo.parentNode) { S.selfVideo.parentNode.removeChild(S.selfVideo); }
			S.selfVideo = null;
		}
		return 1;
	}

	/* ------------------------------------------------------------------------
	   THE CARTOON CAMERA (bead godot-test1-xtr.11)
	   ------------------------------------------------------------------------
	   FORCED FOR THE ROOM (owner ruling 2026-09-06): a receiver never sees the raw
	   face, so there is no toggle, no button and nothing persisted — the styled
	   canvas track is the only video track that is ever attached. That is also why
	   this lives on the SENDER: the crop raises the effective resolution before the
	   encoder sees it, the hero is only known here, and the effect travels as
	   PIXELS, so a receiver on an older build gets it too.

	   THE WHOLE COST, measured against the source that already exists: 160x120 at
	   12 fps in, one drawImage (crop + scale, the browser's own path) and two
	   passes over 128x128 out. `stats()` reports the millisecond figure so \fo can
	   read it, which is the before/after evidence the bead asks for.

	   A 2D CANVAS AND NOT WebGL, deliberately: a second GL context beside Godot's
	   on this single-threaded export is contention for a job a CPU loop does in
	   half a millisecond. And the posterize is in the PIXEL LOOP rather than
	   `ctx.filter` — Safari's filter support is unreliable and cannot posterize at
	   all portably. */

	/* The film palette (`hud_theme.gd`: INK, BONE) as rgb triples rather than as
	   its hex strings, and that is a rule and not a style: `hero_hud_selfcheck`
	   check 8 greps `scripts/` for those six hexes, which may be typed in
	   `hud_theme.gd` alone. CLAUDE.md records the non-hex spelling as the
	   sanctioned shape for a value that cannot preload a `Color` — which a string
	   of JavaScript cannot. Keep them in step BY HAND if the palette moves. */
	var STYLE_INK = [19, 23, 27];
	var STYLE_BONE = [230, 228, 216];
	/* Square, because the tile is: `object-fit:cover` was already throwing the
	   160x120 edges away on every receiver, so cropping here spends the 150 kbps
	   cap on the pixels that are actually drawn. */
	var STYLE_SIZE = 128;
	/* THE STRENGTH KNOBS, AND THE SHIPPED LOOK IS THEIR DEFAULT (bead
	   godot-test1-xtr.16, owner: "is it configurable? can we make it a bit less
	   agressive? i'd like to experiment with this").

	   [levels, mix, edge, shadow]. Four bands is the cel look — INK ground, two
	   tinted mid-tones, BONE highlight; three reads as a stencil, five stops
	   reading as steps at all, which is why `levels` alone was never the knob the
	   owner was asking for. `mix` is: how much of the REAL pixel survives the
	   ramp, which before this bead was nothing at all. `edge` is whether a band
	   boundary is inked, and `shadow` is where the ramp's dark tint sits.

	   THE DEFAULT IS THE OWNER'S OWN DIAL (bead `godot-test1-xtr.22`, verbatim:
	   *"i tried and i like window.ckVoice.setStyle(8, 0.4, 0, 0.6) better, let's
	   make it default for everyone"*), superseding xtr.16's aggressive cel look
	   (4, 1.0, 1, 0.45) because it *"makes faces almost unrecognizable"*.
	   Recognisability comes from keeping the real pixel and dropping the ink
	   lines: eight bands read as shading rather than as a stencil, mix 0.4 lets
	   most of the face through (still well clear of `STYLE_MIX_MIN`), edge 0 inks
	   no band boundary, and the darker shadow stop keeps the picture from
	   flattening. A stored `ck_voice_style` row from an earlier experiment still
	   wins over this on that one browser — deliberately, per the same ruling.

	   AND `mix` HAS A FLOOR, BECAUSE THE OWNER'S RULING IS ABOUT THE PICTURE AND
	   NOT ABOUT THE TRANSPORT (codex review 2026-09-06, orchestrator ruling the
	   same day): *"a receiver never sees the raw face"*. `styleStream()` guarantees
	   only that the wire carries the CANVAS capture and never the device track —
	   at mix 0 the ramp replaces nothing, so that canvas carries the crop
	   UNPOSTERIZED, which is the raw face at 128 px and satisfies the ruling in
	   letter and breaks it in fact. So the knob stops at `STYLE_MIX_MIN`, where a
	   quarter of every pixel is still ramp: recognisably stylised at the softest
	   setting anyone can dial. The NUMBER is the orchestrator's and the owner can
	   lower it by ruling — it is this one constant, read by the one clamp, so a
	   stored row from before the floor is raised to it on load like any other
	   out-of-range value.

	   ponytail: a console knob and no panel — the owner chose the numbers this way
	   and they are the defaults below. `setStyle` from the browser console,
	   remembered here so a reload keeps the experiment. */
	var STYLE_DEFAULT = [8, 0.4, 0, 0.6];
	var STYLE_MIX_MIN = 0.25;
	var STYLE_KEY = 'ck_voice_style';
	var STYLE_FPS = 12;
	var STYLE_PERIOD_MS = Math.round(1000 / STYLE_FPS);
	/* The watchdog's period — slow on purpose. It is not a frame rate, it is the
	   longest a frozen paint loop may go unnoticed. Only reached on a browser
	   with no `Worker`/`Blob`; the worker clock below replaced it otherwise. */
	var STYLE_WATCHDOG_MS = 500;
	/* HOW LONG A FROZEN SOURCE IS TOLERATED before the card goes out and a
	   re-acquisition is tried (bead godot-test1-xtr.18). Two seconds, because a
	   camera coming back from a device switch legitimately stalls for about one
	   and a card that flickers is worse than no card. */
	var STYLE_STALE_MS = 2000;
	/* And how often a re-acquisition may be attempted. Three a minute: enough to
	   ride out a lid-open or an app releasing the camera, few enough that a
	   permanently gone device settles on the card instead of hammering
	   getUserMedia for the life of the room. */
	var STYLE_RECAM_MAX = 3;
	var STYLE_RECAM_WINDOW_MS = 60000;

	/* THE BACKGROUND CLOCK'S WHOLE SOURCE (bead godot-test1-xtr.18, root cause 3).
	   `requestVideoFrameCallback` never fires in a hidden tab and `setInterval` is
	   throttled to 1 Hz there, so a sender who tabbed away dropped every receiver
	   to a slideshow. A WORKER's timers are exempt from that throttling, and a
	   page in a voice room is audible, so intensive throttling does not apply
	   either. It answers a NUMBER like everything else in this module — the
	   boolean scan reads this string too. */
	var STYLE_WORKER_SRC = 'var t = 0; onmessage = function (e) { var ms = Number(e.data); if (!(ms > 0)) { ms = 83; } if (t) { clearInterval(t); } t = setInterval(function () { postMessage(1); }, ms); };';

	/* The colours a quantised level indexes, sampled off FOUR control stops: INK,
	   the tint at shadow value, the tint, BONE. Rebuilt when GDScript pushes a new
	   hero and when a knob moves.

	   THE RAMP HAS TO BE `levels` LONG — `paint`'s second pass indexes it by band
	   — so the four stops are RESAMPLED rather than listed. At `levels` 4 the
	   sample points (t = 0, 1, 2, 3 in stop units) land exactly on the stops; at
	   the shipped 8 they interpolate between them, which is the whole of why
	   eight bands read as shading and four read as a stencil. */
	function styleRamp(r, g, b) {
		var sh = S.style[3];
		var stops = [
			STYLE_INK,
			[Math.round(r * sh), Math.round(g * sh), Math.round(b * sh)],
			[r, g, b],
			STYLE_BONE
		];
		var n = S.style[0];
		var out = [];
		for (var i = 0; i < n; i++) {
			var t = n > 1 ? (i * 3) / (n - 1) : 0;
			var j = t | 0;
			if (j > 2) { j = 2; }
			var f = t - j;
			var a = stops[j];
			var c = stops[j + 1];
			out.push([
				Math.round(a[0] + (c[0] - a[0]) * f),
				Math.round(a[1] + (c[1] - a[1]) * f),
				Math.round(a[2] + (c[2] - a[2]) * f)
			]);
		}
		return out;
	}

	function rebuildRamp() {
		S.styleRamp = styleRamp(S.styleTint[0], S.styleTint[1], S.styleTint[2]);
		return 1;
	}

	/* One knob, clamped, with the shipped value as the answer for anything that is
	   not a finite number — which is what a hand-edited localStorage row, a typo in
	   the console and a missing field all look like by the time they get here. */
	function styleNum(v, lo, hi, dflt) {
		/* A BLANK IS NOT A ZERO (codex review 2026-09-06). `Number('')` is 0 and
		   finite, so a hand-edited `4,,1,0.45` would CLAMP rather than fall back —
		   and a blank `mix` clamps to 0, which is the one setting that turns the
		   cartoon off, silently, until somebody sets it again. Rejected before the
		   conversion, where the emptiness is still visible. */
		if (v === null || v === undefined) { return dflt; }
		if (typeof v === 'string' && v.trim() === '') { return dflt; }
		var n = Number(v);
		if (!isFinite(n)) { return dflt; }
		if (n < lo) { return lo; }
		if (n > hi) { return hi; }
		return n;
	}

	/* THE ONE WRITER of the four knobs: clamps, rebuilds the ramp and persists.
	   Stored as one comma-joined row under one key, because four keys is four ways
	   to be half-written. */
	function setStyle(levels, mix, edge, shadow) {
		S.style = [
			Math.round(styleNum(levels, 2, 8, STYLE_DEFAULT[0])),
			styleNum(mix, STYLE_MIX_MIN, 1, STYLE_DEFAULT[1]),
			styleNum(edge, 0, 1, STYLE_DEFAULT[2]) >= 0.5 ? 1 : 0,
			styleNum(shadow, 0, 1, STYLE_DEFAULT[3])
		];
		rebuildRamp();
		try { window.localStorage.setItem(STYLE_KEY, S.style.join(',')); } catch (e) { }
		return 1;
	}

	/* Read at install, so an experiment survives a reload. A row of any other
	   length is not a row this module wrote — take the shipped four. It goes
	   through `setStyle`, which is why a STORED row is clamped by exactly the rules
	   a console call is (`STYLE_MIX_MIN` included) and why there is no second copy
	   of them here: a hand-edited or pre-floor `mix` is raised on load. */
	function loadStyle() {
		var raw = '';
		try { raw = window.localStorage.getItem(STYLE_KEY); } catch (e) { raw = ''; }
		var p = String(raw === null || raw === undefined ? '' : raw).split(',');
		if (p.length !== 4) { p = STYLE_DEFAULT; }
		return setStyle(p[0], p[1], p[2], p[3]);
	}

	/* Before anything can paint, and before `setStyleTint` can be pushed a hero:
	   `styleRamp` reads `S.style`, so the knobs are the first thing this module
	   owns. */
	loadStyle();

	function styleNow() {
		return (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
	}

	/* A CANVAS NOBODY COMPOSITES EMITS NO FRAME. `captureStream(fps)` samples the
	   canvas when it is PRESENTED, so in a hidden tab the worker above can paint
	   all it likes and the encoder still sees nothing. `requestFrame()` is the
	   explicit push for exactly that case — and it is asked for ONLY while hidden,
	   because on a visible tab it would double the frame rate against a fixed
	   150 kbps cap, i.e. spend the budget on twice as many worse frames. */
	function pushFrame() {
		if (!S.styled || !document) { return 0; }
		if (document.visibilityState !== 'hidden') { return 0; }
		var t = S.styled.getVideoTracks()[0];
		if (!t || !t.requestFrame) { return 0; }
		try { t.requestFrame(); } catch (e) { }
		return 1;
	}

	/* THE SIGNAL-LOST CARD (bead godot-test1-xtr.18, root cause 2). A device that
	   ended or muted — lid shut, another app took the camera, the OS privacy
	   switch, a backgrounded Safari — leaves `styleSrc` showing its last frame
	   while `paint()` keeps shipping it: RTP flows, `framesDecoded` advances, no
	   `mute` fires, and the receiver has NOTHING to detect. So the sender says so
	   in PIXELS, which every receiver on every build understands for free and
	   which costs no signalling, no verb and no new packet. The self-view is drawn
	   from the same canvas, so the sender sees it too.

	   INK ground, BONE glyph: a camera body with an INK lens punched back out of
	   it and a BONE slash across it, in fillRects and one rotated bar. NO HEX
	   STRINGS — the palette lives in the two triples above (hero_hud_selfcheck
	   check 8 greps `scripts/` for the six film hexes). */
	/* One rgb triple as a canvas fill string. The triples themselves are the rule
	   (`hero_hud_selfcheck` check 8 greps `scripts/` for the six film hexes, which
	   may be typed in `hud_theme.gd` alone) — this is only how they are spelled at
	   the one place a 2D context wants a string. */
	function rgb(t) {
		return 'rgb(' + t[0] + ',' + t[1] + ',' + t[2] + ')';
	}

	function paintCard() {
		var cx = S.styleCtx;
		if (!cx) { return 0; }
		var n = STYLE_SIZE;
		var ink = rgb(STYLE_INK);
		var bone = rgb(STYLE_BONE);
		try {
			cx.fillStyle = ink;
			cx.fillRect(0, 0, n, n);
			cx.fillStyle = bone;
			/* Body, and the little viewfinder hump on top of it. */
			cx.fillRect(n * 0.22, n * 0.38, n * 0.50, n * 0.30);
			cx.fillRect(n * 0.34, n * 0.32, n * 0.16, n * 0.06);
			/* The lens, punched back to INK so the glyph reads at 92 px. */
			cx.fillStyle = ink;
			cx.fillRect(n * 0.33, n * 0.46, n * 0.16, n * 0.14);
			/* The barrel sticking out of the right-hand side. */
			cx.fillStyle = bone;
			cx.fillRect(n * 0.72, n * 0.44, n * 0.10, n * 0.18);
			/* And the slash. Drawn twice — INK under BONE — so it reads as a bar
			   laid ON the camera rather than as part of it. */
			cx.save();
			cx.translate(n * 0.5, n * 0.5);
			cx.rotate(-Math.PI / 4);
			cx.fillStyle = ink;
			cx.fillRect(n * -0.42, n * -0.07, n * 0.84, n * 0.14);
			cx.fillStyle = bone;
			cx.fillRect(n * -0.40, n * -0.04, n * 0.80, n * 0.08);
			cx.restore();
		} catch (e) { return 0; }
		S.paintAt = styleNow();
		pushFrame();
		return 1;
	}

	/* RE-ACQUIRE THE DEVICE, AND SWAP ONLY THE HIDDEN SOURCE ELEMENT. The canvas
	   capture track on the wire is untouched, so this is a heal with ZERO
	   renegotiation — and it is also why the forced-cartoon rule survives it: the
	   fresh device stream reaches `styleSrc.srcObject` and nothing else, never a
	   connection. Permission is already granted, so there is no second prompt; a
	   refusal sticks as CAM_DENIED exactly like the first one. */
	function recam() {
		if (S.camState !== 2 || S.camWant !== 1 || S.recamBusy === 1) { return 0; }
		if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) { return 0; }
		var now = styleNow();
		if (!S.recamWin || now - S.recamWin > STYLE_RECAM_WINDOW_MS) {
			S.recamWin = now;
			S.recamN = 0;
		}
		if (S.recamN >= STYLE_RECAM_MAX) { return 0; }
		S.recamN = S.recamN + 1;
		S.recamBusy = 1;
		var gen = S.gen;
		navigator.mediaDevices.getUserMedia({
			audio: false,
			video: { width: 160, height: 120, frameRate: 12 }
		}).then(function (st) {
			S.recamBusy = 0;
			if (gen !== S.gen || S.camWant === 0 || !S.styleSrc) {
				stopTracks(st);
				return;
			}
			var old = S.cam;
			S.cam = st;
			camWatch(st);
			S.styleSrc.srcObject = st;
			var pr = S.styleSrc.play();
			if (pr && pr.catch) { pr.catch(function () { }); }
			stopTracks(old);
			/* Re-arm the staleness clock, or the very next paint would card again
			   on the two seconds this took. */
			S.srcTime = -1;
			S.srcAt = styleNow();
		}).catch(function () {
			/* A FAILURE HERE IS NOT A DENIAL, and marking it one is a one-way door
			   (codex review 2026-09-06). Permission was already granted; what
			   rejects at this point is a device that is busy, asleep or briefly
			   gone. Writing CAM_DENIED would fail the `camState !== 2` guard above
			   for the rest of the room — so the three-attempt budget would never be
			   spent, the panel would read "Camera blocked", and all of that while
			   the canvas sender is still attached and would resume the moment the
			   source came back. The rate limiter is the only bound this needs; the
			   signal-lost card is what the room sees meanwhile. */
			S.recamBusy = 0;
		});
		return 1;
	}

	function stopTracks(st) {
		if (!st) { return 0; }
		var ts = st.getTracks();
		for (var i = 0; i < ts.length; i++) { ts[i].stop(); }
		return 1;
	}

	/* The one event the page gets for free when a device disappears. `mute` is
	   deliberately NOT hooked: it is indistinguishable from an ordinary media
	   stall, and the staleness clock in `paint()` below already covers both after
	   two seconds — one signal, not two. */
	function camWatch(st) {
		var t = st ? st.getVideoTracks()[0] : null;
		if (!t) { return 0; }
		t.onended = function () { recam(); };
		return 1;
	}

	/* ------------------------------------------------------------------------
	   THE FACE-REGISTERED CROP (bead godot-test1-xtr.12)
	   ------------------------------------------------------------------------
	   THE MVP CROPPED THE CENTRE SQUARE, AND THE OWNER'S FIELD REPORT IS WHAT
	   THIS IS FOR (2026-09-06, verbatim): *"croping works good on laptops, just
	   great, but on my desktop when camera is a bit far away it doesn't trace
	   head well, it shows me not only face."* A laptop lid puts a face across
	   most of the frame, so the centre square happens to BE the face; a desktop
	   camera two metres away frames a torso, and the centre square of a torso is
	   a chest. So the box has to ZOOM as well as pan — `FACE_ZOOM` times the
	   detected face, which at two metres is a fraction of the source and fills
	   the 92 px tile exactly as the lid does.

	   THE LADDER, and every rung below the first is reached by a browser that
	   simply cannot do the one above:

	     4. `window.FaceDetector`, the Shape Detection API — FREE when it is
	        there (no download, no worker, the platform's own detector). It is
	        Chromium behind #enable-experimental-web-platform-features and is in
	        no shipping browser, so it is taken opportunistically and is never
	        the plan.
	     2. the VENDORED MediaPipe BlazeFace short-range in a Web Worker, which
	        is what actually ships. `web/vendor/mediapipe/` — read its README for
	        the pin, the licence and why the files are ours and not a CDN's.
	     3/0. the CENTRE CROP, i.e. the MVP unchanged: while the module is still
	        downloading, on a browser with no module worker or no
	        `createImageBitmap`, when the files 404, when the detector throws, and
	        when there is simply no face in shot for `FACE_LOST_MS`.

	   The rung is INVISIBLE to every receiver — the same canvas capture track is
	   on the wire either way, so nothing is signalled, no verb is added and a
	   teammate on any build sees a picture rather than an error.

	   IT DOES TAKE A WebGL2 CONTEXT, AND THAT IS FINE BECAUSE OF WHERE. The
	   library's graph runner asks for one on an `OffscreenCanvas(1, 1)` even on
	   the CPU delegate. The bead's "no WebGL context" rule is about CONTENTION
	   with Godot's on this single-threaded export; a context on the worker's
	   thread is not Godot's thread and not Godot's context. Where
	   `OffscreenCanvas` is missing — Safari 16 and older, which the library
	   sniffs for by name — it falls back to `document.createElement('canvas')`
	   and rejects inside a worker, which is rung 3 and a centre crop. Honest
	   ceiling, not a hole.

	   THE COST, and it is deliberately two numbers. Inference is ~5-15 ms and it
	   is paid on the WORKER's thread, which on this single-threaded export is the
	   only thread that is not Godot's frame. What is paid HERE is one
	   `createImageBitmap` of a 160x120 element and one transfer, at 3.3 Hz;
	   `stats()` reports both (`face=` the round trip, `fm` the main-thread
	   share), because a single summed figure would hide exactly the thing the
	   worker was chosen for. */

	/* Relative to the DOCUMENT, never to the origin: the Pages deploy serves the
	   whole export out of `/<repo>/`, so an absolute path would 404 there and
	   settle every Pages player on the centre crop. */
	var FACE_DIR = 'vendor/mediapipe/';
	/* 3.3 Hz. The bead's window is 2-4 and the box is smoothed anyway — a head
	   does not move at 12 Hz, and each call is an ImageBitmap this thread pays
	   for. */
	var FACE_PERIOD_MS = 300;
	/* The smoothing time constant, applied as a REAL exponential over the
	   elapsed milliseconds rather than a fixed per-frame alpha: the paint loop
	   runs at 12 Hz visible, at the worker clock's rate hidden and at 2 Hz on the
	   watchdog, and a fixed alpha would make the crop snap on one and crawl on
	   another. */
	var FACE_LERP_TAU_MS = 300;
	/* Face box -> head. BlazeFace's box is the face alone (brow to chin), which
	   cropped tight is a portrait with the top of the head sliced off. */
	var FACE_ZOOM = 1.8;
	/* And a floor on how far it may zoom in, in SOURCE pixels. A 160x120 device
	   has 120 to give; below this the tile is upscaled mush, and a spuriously
	   tiny detection would otherwise blow one eye up to fill the tile. */
	var FACE_MIN_SIDE = 56;
	/* No face for this long and the box goes home to the centre. The player who
	   stood up must not leave the crop parked on the chair they left. */
	var FACE_LOST_MS = 2000;

	/* THE WORKER, and it is a CLASSIC one loading the IIFE bundle with
	   `importScripts`. THAT IS NOT A STYLE CHOICE — a module worker cannot run
	   this library at all. MediaPipe loads its own wasm loader through

	       if (typeof importScripts !== 'function') { document.createElement('script') … }

	   so on the one branch a module worker takes it reaches for a `document`
	   that no worker has, and `createFromOptions` rejects every time. A classic
	   worker has `importScripts`, which is the branch the library is written
	   for, and it is also as old as Workers themselves — no module-worker
	   support needed, no dynamic `import()` in a worker needed. (This is why the
	   pin is 1.0.1: the 0.10.x line ships ESM and CommonJS only. See the
	   README.)

	   Written as a string here for the same reason `STYLE_WORKER_SRC` is:
	   `intro_selfcheck`'s boolean scan reads `VOICE_JS` as TEXT, so a worker in
	   a file of its own would be a second dialect nothing checks. Every message
	   it sends is a STRING — '+' ready, '!' this browser cannot, '' nothing in
	   shot, and 'x,y,w,h' in source pixels — never a boolean.

	   The urls arrive in the FIRST message rather than being baked in, so the
	   `document.baseURI` resolution happens once, on the thread that has a
	   document. */
	var FACE_WORKER_SRC = ''
		+ 'var D = null;'
		+ 'onmessage = function (e) {'
		+ '  var m = e.data;'
		+ '  if (m.u) {'
		+ '    try {'
		+ '      importScripts(m.u);'
		+ '      var V = self.Vision;'
		+ '      V.FilesetResolver.forVisionTasks(m.w).then(function (fs) {'
		+ '        return V.FaceDetector.createFromOptions(fs, {'
		+ '          baseOptions: { modelAssetPath: m.m, delegate: "CPU" },'
		+ '          runningMode: "IMAGE", minDetectionConfidence: 0.4'
		+ '        });'
		+ '      }).then(function (d) { D = d; postMessage("+"); })'
		+ '        .catch(function () { postMessage("!"); });'
		+ '    } catch (err) { postMessage("!"); }'
		+ '    return;'
		+ '  }'
		+ '  var b = m.b;'
		+ '  var r = "";'
		+ '  if (D && b) {'
		+ '    try {'
		+ '      var out = D.detect(b);'
		+ '      var ds = (out && out.detections) ? out.detections : [];'
		+ '      var best = null;'
		+ '      for (var i = 0; i < ds.length; i++) {'
		+ '        var bb = ds[i].boundingBox;'
		+ '        if (!bb) { continue; }'
		+ '        if (!best || bb.width * bb.height > best.width * best.height) { best = bb; }'
		+ '      }'
		+ '      if (best) { r = best.originX + "," + best.originY + "," + best.width + "," + best.height; }'
		+ '    } catch (err2) { r = ""; }'
		+ '  }'
		+ '  if (b && b.close) { b.close(); }'
		+ '  postMessage(r);'
		+ '};';

	function faceUrl(rel) {
		try { return new URL(FACE_DIR + rel, document.baseURI).href; } catch (e) { return FACE_DIR + rel; }
	}

	/* Called from the first `paint()` that has a real frame, which is the whole
	   of the lazy-load rule: `paint()` only ever runs inside a room, with the
	   camera granted and the styled canvas live, so a player who never presses
	   Camera never asks for a byte of this. A rung-3 verdict is FINAL — a 404 or
	   a missing `Worker` will not fix itself, and retrying would be a 9.5 MB
	   request per paint. */
	function faceStart() {
		if (S.faceState !== 0) { return 0; }
		/* THE FREE RUNG. `fastMode` is BlazeFace's own trade in the platform's
		   spelling: one nearby face, quickly. `faceNoNative` is set once this
		   browser has PROVED it cannot really do it — see `faceNativeFailed`. */
		if (S.faceNoNative !== 1 && typeof FaceDetector !== 'undefined') {
			try {
				S.faceNative = new FaceDetector({ fastMode: true, maxDetectedFaces: 1 });
				S.faceState = 4;
				return 1;
			} catch (e) { S.faceNative = null; }
		}
		if (typeof Worker === 'undefined' || typeof Blob === 'undefined'
			|| typeof createImageBitmap === 'undefined'
			|| !window.URL || !window.URL.createObjectURL) {
			S.faceState = 3;
			return 0;
		}
		var w = null;
		try {
			var url = window.URL.createObjectURL(new Blob([FACE_WORKER_SRC], { type: 'text/javascript' }));
			w = new Worker(url);
			window.URL.revokeObjectURL(url);
		} catch (e2) { w = null; }
		if (!w) {
			S.faceState = 3;
			return 0;
		}
		w.onmessage = function (ev) { faceMessage(String(ev.data)); };
		/* A throw the worker's own try/catch never sees arrives here instead, and
		   it is the same verdict: this browser gets the centre crop. */
		w.onerror = function () { S.faceState = 3; };
		S.faceW = w;
		S.faceState = 1;
		w.postMessage({
			u: faceUrl('vision_bundle.js'),
			w: faceUrl('wasm'),
			m: faceUrl('blaze_face_short_range.tflite')
		});
		return 1;
	}

	function faceMessage(s) {
		if (s === '+') {
			S.faceState = 2;
			return 1;
		}
		if (s === '!') {
			/* Order matters: `faceStop()` resets the rung to 0 so a fresh camera
			   session may try again, and this verdict has to survive it. */
			faceStop();
			S.faceState = 3;
			return 0;
		}
		S.faceBusy = 0;
		S.faceMs = styleNow() - S.faceSent;
		return faceSeen(s);
	}

	/* 'x,y,w,h' in SOURCE pixels -> where the crop should aim. One parser for
	   both detector rungs: the platform's `DOMRect` is formatted into the same
	   string rather than given a second reader. */
	function faceSeen(s) {
		if (!s) { return 0; }
		var p = s.split(',');
		if (p.length !== 4) { return 0; }
		var x = Number(p[0]);
		var y = Number(p[1]);
		var w = Number(p[2]);
		var h = Number(p[3]);
		if (!isFinite(x) || !isFinite(y) || !(w > 0) || !(h > 0)) { return 0; }
		/* The LONGER side, so a box that is taller than it is wide still contains
		   the whole head once it is squared off. */
		S.faceTarget = [x + w / 2, y + h / 2, (w > h ? w : h) * FACE_ZOOM];
		S.faceHit = styleNow();
		return 1;
	}

	/* A RUNG THAT FAILS MUST FALL THROUGH, NOT TRAP (codex review 2026-09-06).
	   `new FaceDetector()` can SUCCEED on a browser whose platform backend is
	   missing and then reject every `detect()` with `NotSupportedError` — Chromium
	   with the flag on and no OS detector under it. Merely clearing `faceBusy`
	   there left `faceState` on rung 4 for the life of the room, so the vendored
	   detector was never loaded and the player kept the centre crop: the exact
	   outcome this bead exists to remove, on a browser that could have done it.

	   So the first native failure retires the rung for this browser — `faceNoNative`
	   is deliberately NOT cleared by `faceStop`, because a missing backend is a
	   property of the browser and not of the room — and re-enters `faceStart`,
	   which now picks the worker. Falling through on the FIRST failure (rather than
	   after a run of them) costs at most one 3.5 MB download on a browser that
	   merely hiccuped, and can only ever move to the rung that actually ships. */
	function faceNativeFailed() {
		S.faceNative = null;
		S.faceNoNative = 1;
		S.faceState = 0;
		S.faceBusy = 0;
		return faceStart();
	}

	/* Rung 4. Async like the worker and rate-limited by the same clock, so the
	   two are one cadence and one set of numbers.

	   BOTH CALLBACKS ARE GATED ON THE DETECTOR THEY WERE ASKED OF (codex review
	   2026-09-06), and that is `S.gen`'s reasoning one promise along: a `detect()`
	   is in flight for as long as it likes, so it routinely outlives the camera it
	   was asked for. `faceStop()` nulls `S.faceNative`, so a completion that lands
	   after teardown finds `d !== S.faceNative` and does nothing. Without it a late
	   REJECTION reached `faceNativeFailed()` and started a whole MediaPipe worker —
	   a 12 MB download — with the camera off, and a late RESOLVE wrote a face
	   target the NEXT session would lerp toward for FACE_LOST_MS. Measured on a
	   deferred-rejection harness: a live worker was created after `faceStop()`. */
	function faceNativeTick(v, now) {
		var d = S.faceNative;
		S.faceAt = now;
		S.faceBusy = 1;
		S.faceSent = now;
		try {
			d.detect(v).then(function (list) {
				if (d !== S.faceNative) { return; }
				S.faceBusy = 0;
				S.faceMs = styleNow() - S.faceSent;
				var best = null;
				for (var i = 0; i < list.length; i++) {
					var b = list[i].boundingBox;
					if (!b) { continue; }
					if (!best || b.width * b.height > best.width * best.height) { best = b; }
				}
				if (best) { faceSeen(best.x + ',' + best.y + ',' + best.width + ',' + best.height); }
			}).catch(function () {
				if (d !== S.faceNative) { return; }
				faceNativeFailed();
			});
		} catch (e) { faceNativeFailed(); }
		return 1;
	}

	/* One dispatch per FACE_PERIOD_MS, and never two in flight: a detector that
	   fell behind must drop frames rather than queue them, or a slow machine
	   would aim the crop at where the head was a second ago. */
	function faceTick(v) {
		if (S.faceState === 0) { faceStart(); }
		var now = styleNow();
		if (S.faceBusy === 1 || now - S.faceAt < FACE_PERIOD_MS) { return 0; }
		if (S.faceState === 4) { return faceNativeTick(v, now); }
		if (S.faceState !== 2) { return 0; }
		S.faceAt = now;
		S.faceBusy = 1;
		S.faceSent = now;
		var t0 = now;
		try {
			createImageBitmap(v).then(function (b) {
				var t1 = styleNow();
				if (!S.faceW) {
					if (b.close) { b.close(); }
					S.faceBusy = 0;
					return;
				}
				S.faceW.postMessage({ b: b }, [b]);
				S.faceMainMs = S.faceMainMs + (styleNow() - t1);
			}).catch(function () { S.faceBusy = 0; });
		} catch (e) { S.faceBusy = 0; }
		/* The synchronous share, assigned before the continuation above adds its
		   own — which runs strictly later, being a promise callback. */
		S.faceMainMs = styleNow() - t0;
		return 1;
	}

	/* WHERE THE CROP ACTUALLY IS, and every rung of the ladder comes out of this
	   one function: with no target, a stale one, or a detector that never
	   answered, `cx/cy/side` are the MVP's centre square to the pixel.

	   Clamped AFTER the lerp rather than before it, so the box that is drawn is
	   always inside the source even while it is still travelling toward a target
	   that hangs over the edge. */
	function cropBox(vw, vh, now) {
		var full = vw < vh ? vw : vh;
		var cx = vw / 2;
		var cy = vh / 2;
		var side = full;
		var t = S.faceTarget;
		if (t && now - S.faceHit <= FACE_LOST_MS) {
			cx = t[0];
			cy = t[1];
			side = t[2];
			if (side < FACE_MIN_SIDE) { side = FACE_MIN_SIDE; }
			if (side > full) { side = full; }
		}
		var b = S.faceBox;
		if (!b) {
			b = [cx, cy, side];
			S.faceBox = b;
		} else {
			var dt = now - S.faceLerpAt;
			if (!(dt > 0)) { dt = 0; }
			/* A tab that was hidden for a minute must not lerp for a minute; one
			   second of catch-up is already a complete transition at this tau. */
			if (dt > 1000) { dt = 1000; }
			var a = 1 - Math.exp(-dt / FACE_LERP_TAU_MS);
			b[0] = b[0] + (cx - b[0]) * a;
			b[1] = b[1] + (cy - b[1]) * a;
			b[2] = b[2] + (side - b[2]) * a;
		}
		S.faceLerpAt = now;
		var s = b[2];
		if (s > full) { s = full; }
		var x = b[0] - s / 2;
		var y = b[1] - s / 2;
		if (x < 0) { x = 0; }
		if (y < 0) { y = 0; }
		if (x + s > vw) { x = vw - s; }
		if (y + s > vh) { y = vh - s; }
		return [x, y, s];
	}

	/* Torn down with the styled canvas, because the detector exists only to aim
	   its crop. The vendored files stay in the browser's HTTP cache, so a camera
	   toggled off and on again costs four conditional requests and no megabytes. */
	function faceStop() {
		if (S.faceW) {
			try { S.faceW.terminate(); } catch (e) { }
			S.faceW = null;
		}
		S.faceNative = null;
		S.faceState = 0;
		S.faceBusy = 0;
		S.faceAt = 0;
		S.faceSent = 0;
		S.faceMs = 0;
		S.faceMainMs = 0;
		S.faceHit = 0;
		S.faceLerpAt = 0;
		S.faceBox = null;
		S.faceTarget = null;
		return 1;
	}

	/* ------------------------------------------------------------------------
	   THE HERO ACCESSORY (bead godot-test1-xtr.13)
	   ------------------------------------------------------------------------
	   "look similar to a character he is playing" — the last of the three
	   follow-ups, and the one that makes a tinted face read as THAT hero at 92 px.
	   The tint (bead .11) says which palette you are in; the ACCESSORY says who
	   you are, because at tile size a hue is a mood and a shape is a name.

	   THE ART IS THE FOUR SHIPPED PORTRAITS and the owner's ruling of 2026-09-06
	   settles what each one is: `assets/portraits/windman.png` is a blue BLINDFOLD
	   band with a red mark across the eyes, `primm.png` cyan VISOR GOGGLES,
	   `teibi.png` a dark BERET on the crown, `phoboman.png` a glass FISHBOWL
	   HELMET around the whole head. (The owner's original message said "Windman's
	   goggles, Primm's beret, Teibi's helmet"; the pictures disagree and the
	   ruling is that the pictures win.)

	   DRAWN CLEAN, AFTER THE POSTERIZE (owner ruling, same day). The stylize pass
	   is `putImageData`; this runs after it, so Primm's cyan stays cyan and the
	   ink edges of the face do not cut the visor into bands. Under the pass would
	   have been one line further up and reads worse at 92 px — the accessory is
	   the thing that has to survive the downscale.

	   VECTOR fillRects AND TWO ARCS, NOT PNGs. The bead offered four data-URI
	   PNGs; four `<img>` loads with their own ready state, ~40 KB of base64 in
	   this string and four committed source files buy nothing a dozen rects do
	   not, and they cannot follow the face box for free the way a parameterised
	   shape does. The colours are rgb TRIPLES like `STYLE_INK`/`STYLE_BONE`, never
	   hex (`hero_hud_selfcheck` check 8), and they are SEMANTIC identity art in
	   `hero_hud.HERO_COLORS`' own sense rather than film-palette colours — the
	   ink and the highlight are the palette's.

	   REGISTERED ON THE FACE BOX the tracker already provides (bead .12), so it
	   follows the head. With no detector — the centre-crop rung — `S.faceBox` IS
	   the centre square, so the same arithmetic lands the accessory on the
	   crop's implied face and there is no second code path to keep in step. */
	var ACC_WINDMAN_BAND = [74, 111, 165];
	var ACC_WINDMAN_MARK = [193, 57, 47];
	var ACC_PRIMM_FRAME = [46, 74, 84];
	var ACC_PRIMM_LENS = [128, 232, 224];
	var ACC_TEIBI_BERET = [43, 50, 69];
	var ACC_PHOBO_RIM = [207, 214, 218];

	/* WHERE THE FACE IS ON THE 128 px CANVAS, as [cx, cy, side] — the detected
	   face, not the crop: `S.faceBox` is the LERPED crop box and the crop is
	   `FACE_ZOOM` times the face, so dividing it back out is the whole mapping.
	   Off the lerped box rather than the raw target so the accessory travels with
	   the picture instead of snapping ahead of it. */
	function faceOnCanvas(box) {
		var n = STYLE_SIZE;
		var b = S.faceBox;
		if (!b || !(box[2] > 0)) { return [n / 2, n / 2, n / FACE_ZOOM]; }
		return [
			(b[0] - box[0]) / box[2] * n,
			(b[1] - box[1]) / box[2] * n,
			(b[2] / FACE_ZOOM) / box[2] * n
		];
	}

	/* A blue band across the eyes with the red mark in the middle of it, inked
	   all round so it reads against a face of any brightness. */
	function accWindman(r, g) {
		var cx = r[0], cy = r[1], s = r[2];
		var w = s * 1.12, h = s * 0.20;
		var x = cx - w / 2, y = cy - s * 0.5 + s * 0.24;
		g.fillStyle = rgb(STYLE_INK);
		g.fillRect(x - s * 0.02, y - s * 0.02, w + s * 0.04, h + s * 0.04);
		g.fillStyle = rgb(ACC_WINDMAN_BAND);
		g.fillRect(x, y, w, h);
		g.fillStyle = rgb(ACC_WINDMAN_MARK);
		g.fillRect(cx - w * 0.17, y, w * 0.34, h);
		return 1;
	}

	/* A dark strap with two cyan lenses in it: the strap is what makes goggles
	   read as goggles rather than as a stripe. */
	function accPrimm(r, g) {
		var cx = r[0], cy = r[1], s = r[2];
		var w = s * 1.10, h = s * 0.19;
		var x = cx - w / 2, y = cy - s * 0.5 + s * 0.25;
		g.fillStyle = rgb(STYLE_INK);
		g.fillRect(x, y - s * 0.02, w, h + s * 0.04);
		g.fillStyle = rgb(ACC_PRIMM_FRAME);
		g.fillRect(x + w * 0.13, y, w * 0.74, h);
		g.fillStyle = rgb(ACC_PRIMM_LENS);
		var lw = w * 0.30, lh = h * 0.58, ly = y + h * 0.21;
		g.fillRect(cx - w * 0.36, ly, lw, lh);
		g.fillRect(cx + w * 0.06, ly, lw, lh);
		return 1;
	}

	/* ABOVE the face box, which is what "on the crown" means when the box is
	   brow-to-chin: an ellipse sitting on the top edge, tipped by nothing at all
	   because a beret that leans is a beret that slides off a moving head.

	   IT SITS AS LOW AS "ON THE CROWN" ALLOWS, and that is measured rather than
	   taste. The crop is `FACE_ZOOM` (1.8) times the face, so the face box's top
	   edge lands at 22% of the canvas and everything above it has 28 px to live
	   in; the first draft put the beret's top at 7 px, and on a detection sitting
	   even slightly high in frame the hat was clipped by the canvas edge. Its top
	   is now `0.24 * side` above the box (11 px on a centred face) with the stalk
	   inside that, so a high detection loses nothing. */
	function accTeibi(r, g) {
		var cx = r[0], cy = r[1], s = r[2];
		var top = cy - s * 0.5;
		var rx = s * 0.58, ry = s * 0.22;
		var yc = top - s * 0.02;
		g.fillStyle = rgb(ACC_TEIBI_BERET);
		g.strokeStyle = rgb(STYLE_INK);
		g.lineWidth = Math.max(1, s * 0.03);
		g.beginPath();
		g.ellipse(cx, yc, rx, ry, 0, 0, Math.PI * 2);
		g.fill();
		g.stroke();
		g.fillStyle = rgb(ACC_TEIBI_BERET);
		g.fillRect(cx - s * 0.03, yc - ry - s * 0.07, s * 0.06, s * 0.09);
		return 1;
	}

	/* A ring around the WHOLE head — the one accessory that is not on the face —
	   plus the BONE highlight that is the only reason it reads as glass rather
	   than as a hoop. The soup is deliberately not drawn: what is inside the
	   helmet is the player's own face, which is the whole point of the feature. */
	function accPhoboman(r, g) {
		var cx = r[0], cy = r[1], s = r[2];
		var rad = s * 0.78;
		var yc = cy - s * 0.06;
		g.strokeStyle = rgb(ACC_PHOBO_RIM);
		g.lineWidth = Math.max(2, s * 0.09);
		g.beginPath();
		g.arc(cx, yc, rad, 0, Math.PI * 2);
		g.stroke();
		g.strokeStyle = rgb(STYLE_INK);
		g.lineWidth = Math.max(1, s * 0.02);
		g.beginPath();
		g.arc(cx, yc, rad + s * 0.055, 0, Math.PI * 2);
		g.stroke();
		g.strokeStyle = rgb(STYLE_BONE);
		g.lineWidth = Math.max(1, s * 0.045);
		g.beginPath();
		g.arc(cx, yc, rad * 0.78, Math.PI * 1.10, Math.PI * 1.42);
		g.stroke();
		return 1;
	}

	/* A HERO WITH NO ACCESSORY DRAWS NOTHING AND LOGS NOTHING — `hero_hud`'s "a
	   missing portrait is not an error" rule, so a fifth `CHARACTERS` entry ships
	   a tinted face and no console noise until somebody draws it one. A plain
	   chain of compares rather than a lookup table on purpose: an object keyed by
	   a name off the wire answers `constructor` and `toString` with functions. */
	function paintAccessory(box) {
		var g = S.styleCtx;
		if (!g) { return 0; }
		var r = faceOnCanvas(box);
		if (!(r[2] > 0)) { return 0; }
		try {
			if (S.styleHero === 'windman') { return accWindman(r, g); }
			if (S.styleHero === 'primm') { return accPrimm(r, g); }
			if (S.styleHero === 'teibi') { return accTeibi(r, g); }
			if (S.styleHero === 'phoboman') { return accPhoboman(r, g); }
		} catch (e) { return 0; }
		return 0;
	}

	function paint() {
		var cx = S.styleCtx;
		var v = S.styleSrc;
		if (!cx || !v) { return 0; }
		/* THE SOURCE'S OWN CLOCK, and it is the one signal that sees every way a
		   source can freeze — an ended track, a muted one, a decoder that stopped,
		   a device that was never going to produce a frame at all. Checked BEFORE
		   the `videoWidth` guard below, or a camera that never decodes returns 0
		   forever and is never carded. It is deliberately NOT gated on
		   `visibilityState`: the orchestrator's ruling of 2026-09-06 is that a
		   hidden sender's receivers get the card within 3 s, so if the worker
		   clock cannot keep the picture alive the card is what they get. */
		var now = styleNow();
		if (v.currentTime !== S.srcTime) {
			S.srcTime = v.currentTime;
			/* A MUTED TRACK IS NOT A LIVE ONE, even while its element keeps
			   ticking (codex review 2026-09-06). A lid closing, an OS privacy
			   switch or another app taking the device MUTES the track: the element
			   goes on playing black frames off the stream's own clock, so
			   `currentTime` alone would refresh this stamp forever and neither the
			   card nor the re-acquisition would ever fire — every receiver would
			   sit on a black tile indefinitely, which is the exact failure this
			   whole rung exists to close. `srcState()` is xtr.17's own reader and
			   answers 1 only for a live track. */
			if (srcState() === 1) { S.srcAt = now; }
		}
		if (!S.srcAt) { S.srcAt = now; }
		if (now - S.srcAt > STYLE_STALE_MS) {
			recam();
			return paintCard();
		}
		var vw = v.videoWidth;
		var vh = v.videoHeight;
		/* Nothing decoded yet — the first frames after a grant. */
		if (!vw || !vh) { return 0; }
		/* ABOVE `t0` ON PURPOSE (bead godot-test1-xtr.12). `style=` has to keep
		   meaning exactly what it meant before this bead or the before/after
		   reading is not a comparison; the detector's own main-thread share is
		   `fm`, reported beside it. */
		faceTick(v);
		var t0 = styleNow();
		var n = STYLE_SIZE;
		/* THE CROP, which is the centre square until a detector says otherwise. */
		var box = cropBox(vw, vh, now);
		try {
			cx.drawImage(v, box[0], box[1], box[2], box[2], 0, 0, n, n);
		} catch (e) { return 0; }
		var img;
		try { img = cx.getImageData(0, 0, n, n); } catch (e) { return 0; }
		var d = img.data;
		var lv = S.styleLv;
		var ramp = S.styleRamp;
		var i, k;
		var levels = S.style[0];
		var mix = S.style[1];
		var inked = S.style[2];
		var keep = 1 - mix;
		var top = levels - 1;
		/* PASS 1 — luminance, quantised. Kept in its own array because pass 2 has
		   to compare a pixel's band with its NEIGHBOURS', which it cannot do once
		   they have been recoloured. */
		for (i = 0, k = 0; k < d.length; i++, k += 4) {
			var l = (d[k] * 0.299 + d[k + 1] * 0.587 + d[k + 2] * 0.114) / 255;
			var q = (l * levels) | 0;
			lv[i] = q > top ? top : q;
		}
		/* PASS 2 — the band's colour, or INK where the band CHANGES. A level edge
		   is exactly the contour a cel artist would ink, and it costs two integer
		   compares against a Sobel's nine multiplies. Right and down only: an
		   outline drawn from both sides of a boundary is two pixels thick.
		   Then the STRENGTH KNOB (bead godot-test1-xtr.16): the band colour blended
		   back over the real pixel. At the shipped mix of 1 that is `d * 0 + c * 1`
		   — an exact integer, and a Uint8ClampedArray store of an exact integer is
		   the assignment this replaced, so the default output is unchanged to the
		   byte. Three multiplies and three adds on 16k pixels is the whole bill. */
		for (i = 0, k = 0; k < d.length; i++, k += 4) {
			var b = lv[i];
			var x = i % n;
			var edge = inked === 1
				&& ((x + 1 < n && lv[i + 1] !== b) || (i + n < lv.length && lv[i + n] !== b));
			var c = edge ? STYLE_INK : ramp[b];
			d[k] = d[k] * keep + c[0] * mix;
			d[k + 1] = d[k + 1] * keep + c[1] * mix;
			d[k + 2] = d[k + 2] * keep + c[2] * mix;
		}
		try { cx.putImageData(img, 0, 0); } catch (e) { return 0; }
		/* THE HERO ACCESSORY (bead godot-test1-xtr.13), and it is AFTER the
		   posterize by owner ruling: drawn clean over the inked face, on the same
		   crop box, so the cyan visor stays cyan and the band edges are not cut
		   into levels. ABOVE the `paintMs` stamp so `style=` in \fo keeps billing
		   everything this frame really cost. */
		paintAccessory(box);
		S.paintMs = styleNow() - t0;
		S.paintAt = styleNow();
		pushFrame();
		return 1;
	}

	/* The paint loop, at the SOURCE's rate rather than the display's:
	   `requestVideoFrameCallback` fires once per decoded frame (12 a second here),
	   so nothing is painted twice and nothing is missed. The interval is the
	   fallback for a browser without it. */
	function styleTick() {
		if (!S.styleCtx) { return 0; }
		paint();
		styleSchedule();
		return 1;
	}

	function styleSchedule() {
		var v = S.styleSrc;
		if (!v || !S.styleCtx) { return 0; }
		if (v.requestVideoFrameCallback) {
			/* The `return` is INSIDE the try on purpose: a registration that throws
			   would otherwise report success and leave nothing driving the loop but
			   the watchdog, i.e. that room at 2 fps. Falling through to the interval
			   costs nothing and is the same answer the browsers without rVFC get. */
			try {
				S.styleRvfc = v.requestVideoFrameCallback(styleTick);
				return 1;
			} catch (e) { }
		}
		if (!S.styleTimer) {
			S.styleTimer = setInterval(paint, STYLE_PERIOD_MS);
		}
		return 1;
	}

	/* THE BACKGROUND CLOCK (bead godot-test1-xtr.18, root cause 3), and it is the
	   WATCHDOG'S REPLACEMENT rather than a third frame rate: rVFC still drives the
	   loop while the tab is visible, and this tick only paints when a whole period
	   has gone by with no frame — which in a visible tab is almost never and in a
	   hidden one is every time. A worker's `setInterval` is exempt from Chrome's
	   1 Hz background throttling, and a page in a voice room is audible, so
	   intensive throttling does not apply either.

	   The Blob URL is revoked immediately: the Worker holds its own reference to
	   the script it was constructed from. Anything missing (`Worker`, `Blob`,
	   `createObjectURL`) or a construction that throws falls through to the old
	   500 ms watchdog, which is what a browser without workers had anyway. */
	function styleWorker() {
		if (S.styleW) { return 1; }
		if (typeof Worker === 'undefined' || typeof Blob === 'undefined') { return 0; }
		if (!window.URL || !window.URL.createObjectURL) { return 0; }
		var w = null;
		try {
			var url = window.URL.createObjectURL(new Blob([STYLE_WORKER_SRC], { type: 'text/javascript' }));
			w = new Worker(url);
			window.URL.revokeObjectURL(url);
		} catch (e) { w = null; }
		if (!w) { return 0; }
		w.onmessage = function () {
			if (styleNow() - S.paintAt >= STYLE_PERIOD_MS) { paint(); }
		};
		w.postMessage(STYLE_PERIOD_MS);
		S.styleW = w;
		return 1;
	}

	/* One of the two, never both: the worker ticks at the frame rate, the
	   watchdog at 2 Hz, and a browser that can run the first does not want the
	   second. */
	function styleClock() {
		if (styleWorker() === 1) { return 1; }
		return styleWatchdog();
	}

	/* THE WATCHDOG, and it is armed even when rVFC is (measured working on Chrome
	   with this very element). `requestVideoFrameCallback` fires when a frame is
	   PRESENTED, and `styleSrc` is `display:none` — an engine that declines to
	   present a non-composited video simply never calls back, and a registration
	   that throws leaves the chain dead too. Either way the room would see a still
	   portrait with no recovery and no telemetry saying so. `paint()` is idempotent
	   and costs a fraction of a millisecond, so a slow second hand is the whole fix.
	   It is not free of the rate, though, and the comment should not pretend it is:
	   with rVFC working this is 12 + 2 paints a second, not 12. */
	function styleWatchdog() {
		if (S.styleWatch) { return 0; }
		S.styleWatch = setInterval(paint, STYLE_WATCHDOG_MS);
		return 1;
	}

	function styleStart() {
		if (S.styled || !S.cam) { return 0; }
		if (!document || !document.body) { return 0; }
		var c = document.createElement('canvas');
		if (!c.captureStream) { return 0; }
		c.width = STYLE_SIZE;
		c.height = STYLE_SIZE;
		var cx = null;
		/* `willReadFrequently` is what keeps a canvas read every frame off the GPU
		   readback path, which is the one way this gets expensive. */
		try { cx = c.getContext('2d', { willReadFrequently: true }); } catch (e) { cx = null; }
		if (!cx) { try { cx = c.getContext('2d'); } catch (e2) { cx = null; } }
		if (!cx) { return 0; }
		/* A MediaStream cannot be drawn; an element can. IN the DOM and hidden,
		   because a detached <video> is not guaranteed to be decoded at all. */
		var v = document.createElement('video');
		v.autoplay = true;
		v.muted = true;
		v.className = 'ck-voice-src';
		v.setAttribute('playsinline', '');
		v.style.cssText = 'display:none;';
		document.body.appendChild(v);
		v.srcObject = S.cam;
		var pr = v.play();
		if (pr && pr.catch) { pr.catch(function () { }); }
		S.styleSrc = v;
		S.styleCanvas = c;
		S.styleCtx = cx;
		S.styleLv = new Uint8Array(STYLE_SIZE * STYLE_SIZE);
		if (!S.styleRamp) { rebuildRamp(); }
		var st = null;
		try { st = c.captureStream(STYLE_FPS); } catch (e) { st = null; }
		if (!st) {
			styleStop();
			return 0;
		}
		S.styled = st;
		/* Armed BEFORE the first paint, so the staleness clock starts here rather
		   than at whatever moment a frame first arrives: a camera that never
		   decodes one gets the card after STYLE_STALE_MS like any other dead
		   source, instead of sitting on a black tile forever. */
		S.srcTime = -1;
		S.srcAt = styleNow();
		S.recamN = 0;
		S.recamWin = 0;
		camWatch(S.cam);
		styleSchedule();
		styleClock();
		return 1;
	}

	function styleStop() {
		faceStop();
		if (S.styleTimer) { clearInterval(S.styleTimer); S.styleTimer = null; }
		if (S.styleWatch) { clearInterval(S.styleWatch); S.styleWatch = null; }
		if (S.styleW) {
			try { S.styleW.terminate(); } catch (e) { }
			S.styleW = null;
		}
		if (S.styleSrc && S.styleRvfc && S.styleSrc.cancelVideoFrameCallback) {
			try { S.styleSrc.cancelVideoFrameCallback(S.styleRvfc); } catch (e) { }
		}
		S.styleRvfc = 0;
		/* Cleared BEFORE the element goes, so a callback already queued for this
		   frame finds nothing to paint into. */
		S.styleCtx = null;
		S.styleCanvas = null;
		S.styleLv = null;
		if (S.styled) {
			var ts = S.styled.getTracks();
			for (var i = 0; i < ts.length; i++) { ts[i].stop(); }
			S.styled = null;
		}
		if (S.styleSrc) {
			S.styleSrc.srcObject = null;
			if (S.styleSrc.parentNode) { S.styleSrc.parentNode.removeChild(S.styleSrc); }
			S.styleSrc = null;
		}
		S.paintMs = 0;
		S.paintAt = 0;
		S.srcTime = -1;
		S.srcAt = 0;
		return 1;
	}

	/* WHAT GOES ON THE WIRE, AND THE RAW DEVICE IS NOT ON THE LIST. The owner's
	   ruling is that a receiver never sees the raw face, so where the browser
	   cannot give us a canvas capture at all the degrade is NO VIDEO — not the
	   unstyled webcam, which is the one outcome the ruling was written to
	   prevent. `attachCam` and `showSelf` both already answer 0 on a null stream,
	   so that degrade costs no branch anywhere. (`canvas.captureStream` is Chrome
	   51+ / Firefox 43+ / Safari 11+, so this is a corner nothing shipping
	   reaches.) */
	function styleStream() {
		return S.styled;
	}

	/* THE DEVICE'S OWN STATE, as the one number `stats()` reports under `src=`
	   (bead godot-test1-xtr.17): 0 none, 1 live, 2 muted, 3 ended. It is the only
	   half of a frozen picture the SENDER can see and the receiver cannot — a
	   muted or ended device keeps the last frame on the canvas and the wire keeps
	   carrying it, so nothing downstream ever notices. Numbers, never a boolean:
	   `track.muted` is compared rather than returned. */
	function srcState() {
		if (!S.cam) { return 0; }
		var t = S.cam.getVideoTracks()[0];
		if (!t) { return 0; }
		if (t.readyState === 'ended') { return 3; }
		if (t.muted === 1 || t.muted === true) { return 2; }
		return 1;
	}

	/* Milliseconds since the last frame `paint()` actually put on the canvas, or
	   -1 if it has never painted one. This is the number that separates class B
	   (the paint loop stalled) from a live sender, and it is only ever readable
	   HERE — a receiver sees the same last frame either way. */
	function paintAge() {
		if (!S.paintAt) { return -1; }
		return Math.round(styleNow() - S.paintAt);
	}

	/* ONE VIDEO SENDER PER CONNECTION, FOR THE LIFE OF THAT CONNECTION (bead
	   godot-test1-xtr.18, and this is the whole of root cause 1).

	   `addTrack` only REUSES a transceiver that has NEVER SENT — Chromium's
	   `RtpTransceiver::has_ever_been_used_to_send()` — so a `removeTrack` /
	   `addTrack` pair per camera toggle appends a NEW video m-section to every
	   later offer and leaves the old one behind as an inactive line, for the life
	   of the PC. MEASURED in a two-tab room on the debug web export: audio alone
	   3,090 chars, the first camera ON 9,338, and after ONE off/on cycle
	   **16,586** — past `MpCodec.MAX_VC_SDP`, so the receiver dropped the offer
	   with a `push_warning` and nothing else, the toggler's PC sat in
	   `have-local-offer` forever, `onnegotiationneeded` could never fire on it
	   again, and (being the impolite peer) it ignored every offer the far side
	   sent from then on. That pair was dead for video, for an ICE restart and for
	   a late microphone — and the gesture that caused it is the Camera button,
	   which is exactly the button the owner reaches for to "restart" a stuck
	   picture.

	   `replaceTrack` swaps the track on an EXISTING sender and renegotiates
	   NOTHING, so the description never grows and there is no offer to lose. The
	   receiver's experience is unchanged: `replaceTrack(null)` stops the RTP and
	   arrives as the same `mute` `removeTrack` did, and the unmute on the way back
	   is the handler `ontrack` already installs. */
	function attachCam(p) {
		var src = styleStream();
		if (!src) { return 0; }
		var t = src.getVideoTracks()[0];
		if (!t) { return 0; }
		if (p.vsend) {
			/* THE HEAL. Also what makes the Camera button work as the manual
			   escape hatch for EVERY class of stuck picture: off/on swaps a fresh
			   canvas track onto the sender the far end is already receiving. The
			   150 kbps cap survives a replaceTrack, so it is not re-applied. */
			try {
				var rp = p.vsend.replaceTrack(t);
				if (rp && rp.catch) { rp.catch(function () { }); }
			} catch (e) { }
			return 1;
		}
		try {
			p.vsend = p.pc.addTrack(t, src);
			/* THE BANDWIDTH BUDGET, and the only place it is written down on this
			   side: 150 kbps caps one portrait-sized stream, so a 4-peer mesh is
			   3 up + 3 down under half a megabit each way. */
			var prm = p.vsend.getParameters();
			/* Only ever EDIT what getParameters handed back: setParameters rejects
			   an encodings array whose length differs from the current one, so
			   inventing an entry is not a fallback, it is a guaranteed rejection.
			   A browser that reports none is uncapped, which is the honest degrade. */
			if (prm.encodings && prm.encodings.length) {
				prm.encodings[0].maxBitrate = 150000;
				var sp = p.vsend.setParameters(prm);
				if (sp && sp.catch) { sp.catch(function () { }); }
			}
		} catch (e) { }
		return 1;
	}

	function detachCam(p) {
		if (!p.vsend) { return 0; }
		/* THE SENDER STAYS. Dropping it is what forced the next `attachCam` to
		   `addTrack` a second m-section — see the essay above. A null track stops
		   the RTP, which the receiver sees as the `mute` it always saw. */
		try {
			var rn = p.vsend.replaceTrack(null);
			if (rn && rn.catch) { rn.catch(function () { }); }
		} catch (e) { }
		return 1;
	}

	function camera(on) {
		var k;
		if (on) {
			if (S.camState === 1 || S.camState === 2) { return S.camState; }
			if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
				S.camState = 3;
				return 3;
			}
			S.camState = 1;
			var gen = S.gen;
			/* Portrait size and portrait frame rate: the picture is drawn in an
			   92 px tile (`hero_hud.TILE_SIZE`), so anything larger is bytes
			   nobody can see. */
			navigator.mediaDevices.getUserMedia({
				audio: false,
				video: { width: 160, height: 120, frameRate: 12 }
			}).then(function (st) {
				/* A grant that lands after the room went away — or after the player
				   changed their mind — RELEASES the device. The mic's rule, and for
				   the camera the tab's recording light makes it visible. */
				if (gen !== S.gen || S.camWant === 0) {
					stopTracks(st);
					if (gen === S.gen) { S.camState = 0; }
					return;
				}
				S.cam = st;
				S.camState = 2;
				/* THE STYLED TRACK IS BUILT BEFORE ANYTHING IS ATTACHED, because
				   `attachCam` sends whatever `styleStream()` answers and a peer
				   that got the raw track would keep it until the next
				   renegotiation. */
				styleStart();
				showSelf();
				for (var q in S.peers) { attachCam(S.peers[q]); }
			}).catch(function () { if (gen === S.gen) { S.camState = 3; } });
			return 1;
		}
		/* ONLY OUR OWN SENDERS. `p.video` and `S.tiles[k]` are the peer's INCOMING
		   picture — hiding them here would black out every teammate because you
		   switched your own camera off. */
		for (k in S.peers) { detachCam(S.peers[k]); }
		/* THE SELF-VIEW AND THE PAINT LOOP GO FIRST, the device last: the canvas
		   capture is fed by an element fed by `S.cam`, so stopping the device under
		   a running loop paints stale frames into a track nobody is sending — and
		   the self-view is drawn from that same canvas, so it comes down with it.
		   `stop()` reaches both through its own `camera(0)`. */
		hideSelf();
		styleStop();
		if (S.cam) {
			stopTracks(S.cam);
			S.cam = null;
		}
		/* ASKING SURVIVES AN OFF-PRESS, and it has to. Dropping back to IDLE lets
		   the next press start a SECOND getUserMedia while the first prompt is
		   still up, and only one of the two streams is ever reachable to stop — the
		   other captures for the life of the page. The pending promise's own
		   `camWant === 0` branch is what releases the device, and it is already
		   correct. A refusal likewise STICKS until the room ends: re-prompting on
		   every press is the retry loop the epic forbids. */
		if (S.camState === 2) { S.camState = 0; }
		return 0;
	}

	/* Who has a live picture right now, as one string — `levels()`'s format rule:
	   one bridge call, never one per peer, and never a boolean. */
	function videoPeers() {
		/* The stall sampler's clock — see `sampleTick`. This call is GDScript's
		   5 Hz tile poll and is the only thing running for the whole life of a
		   room, so the health sample rides it instead of a timer of its own. */
		sampleTick();
		var out = [];
		for (var k in S.peers) { if (S.peers[k].hasVideo === 1) { out.push(k); } }
		return out.join(',');
	}

	function flag(val) {
		return (val === 1 || val === '1' || val === true) ? 1 : 0;
	}

	/* An integer percent 0-100 out of whatever crossed the bridge. GDScript
	   clamps too — this is the browser refusing to set `<audio>.volume` outside
	   0..1, which throws in every engine. */
	function pct(val) {
		var n = Math.round(Number(val));
		/* Unreadable falls to 100, never to 0 — the GDScript loader's rule for the
		   same reason: a value nobody can explain must not silence the room. */
		if (!isFinite(n)) { return 100; }
		if (n < 0) { return 0; }
		return n > 100 ? 100 : n;
	}

	/* One 0-255 colour channel out of whatever crossed the bridge. Unreadable
	   falls to a mid grey rather than to 0, `pct`'s rule: a tint nobody can
	   explain must not paint every face black. */
	function chan(val) {
		var n = Math.round(Number(val));
		if (!isFinite(n)) { return 128; }
		if (n < 0) { return 0; }
		return n > 255 ? 255 : n;
	}

	function setTx(val) {
		S.tx = flag(val);
		applyMic();
		return S.tx;
	}

	/* ------------------------------------------------------------------------
	   THE RECEIVER / TRANSPORT HEAL LADDER (bead godot-test1-xtr.19)
	   ------------------------------------------------------------------------
	   OWNER, 2026-09-06: *"video ... sometimes gets stuck for some of
	   participants, and there is no way to restart it"*. The SENDER's half of that
	   is bead .18 (`replaceTrack`, the re-acquisition, the signal-lost card); this
	   is what a peer does when its OWN end of a pair is dead. Four rungs, in the
	   order the browser reaches them, and EVERY ONE IS BOUNDED — an unbounded rung
	   is a re-offer loop, which is precisely the fear the old `failed`-only guard
	   was written against.

	   R1 A LOST OFFER WEDGES THE PC FOREVER, and there are two silent drop points
	      on the way: `post()` swallows every failure and `MpCodec.decode_vc` drops
	      a malformed or oversized payload with a `push_warning` nobody reads. The
	      PC then sits in `have-local-offer` — `onnegotiationneeded` cannot fire
	      again, `restartIce()` has nothing to ride, and an IMPOLITE peer treats
	      every incoming offer as a collision and ignores it. So an offer that goes
	      unanswered for `HEAL_OFFER_TIMEOUT_MS` is ROLLED BACK: the state returns
	      to stable and the browser re-evaluates its own negotiation-needed flag and
	      re-offers. Bounded at `HEAL_OFFER_TRIES_MAX` in a row, then R3.
	   R2 `disconnected` IS NOW ACTED ON, WHICH REVERSES THE PREVIOUS RULING. It
	      was left alone as "transient and self-healing", and it is — but Chrome
	      reaches `failed` only after ICE consent freshness expires (~30 s) and
	      sometimes never from `disconnected`, so a coturn allocation expiring or a
	      NAT rebind left a pair silent for the life of the room. The re-offer-loop
	      fear is answered by the BOUND rather than by ignoring the state: held for
	      `HEAL_ICE_HOLD_MS`, at most one restart per `HEAL_ICE_COOLDOWN_MS`, at
	      most `HEAL_ICE_TRIES_MAX` in a row, then R3. `failed` still fires at once.
	      Counters reset on `connected`/`completed`.
	   R3 REBUILD ONE PC, ON BOTH ENDS, WITH NO SIGNALLING CHANGE. A one-sided
	      rebuild does not work: the remote applies the fresh PC's offer to its OLD
	      PC, whose DTLS fingerprint differs, and `setRemoteDescription` rejects
	      (swallowed). So the REMOTE detects the rebuild in `recv` off the one thing
	      it already has — an incoming offer whose `a=fingerprint:` differs from the
	      one on `pc.remoteDescription` — and rebuilds first, then applies the offer
	      to a PC that is `stable`. NO new `vc` kind, no `mp_codec` edit, and
	      `mp_manager`'s seam stays three functions; the fingerprint compare is the
	      whole reason a `bye`/`reset` verb is not needed.
	   R4 A PAUSED `<video>` IS ONE LINE. `showVideo` calls `play()` once and
	      swallows the rejection; an element that pauses later (an autoplay policy
	      after a srcObject swap, a media suspend) is never kicked again.

	   TARGET: Chrome and Firefox. Safari is a documented ceiling (orchestrator
	   ruling 2026-09-06) — rollback and `restartIce` are both there, but its ICE
	   state reporting is its own, and mobile is out of scope for the whole epic. */
	var HEAL_OFFER_TIMEOUT_MS = 8000;
	var HEAL_OFFER_TRIES_MAX = 3;
	var HEAL_ICE_HOLD_MS = 5000;
	var HEAL_ICE_COOLDOWN_MS = 15000;
	var HEAL_ICE_TRIES_MAX = 3;
	/* R3's OWN bound, and it is a floor on the CADENCE rather than a budget: the
	   rungs above already gate how fast a peer can reach a rebuild (three 8 s
	   offers, or three restarts 15 s apart), so this only stops the two of them
	   compounding into a rebuild every few seconds on a link that is simply gone.
	   It survives the rebuild because the tally does. */
	var HEAL_REBUILD_COOLDOWN_MS = 30000;

	/* [rollback, ice, rebuild, lastRebuildAt] for one peer, created on demand. */
	function healOf(id) {
		var h = S.heal[id];
		if (!h) { h = [0, 0, 0, 0]; S.heal[id] = h; }
		return h;
	}

	function healBump(id, slot) {
		var h = healOf(id);
		h[slot] = h[slot] + 1;
		return h[slot];
	}

	/* THE RECT SURVIVES THE REBUILD, and that is not a nicety — it is the sticky
	   change-gate `hideSelf` documents, seen from the remote side. `close()`
	   deletes `S.tiles[id]`, but GDScript's `_pushed_tiles` still holds the same
	   fraction; if the fresh track arrives inside one 5 Hz poll window the poll
	   sees the id in `videoPeers()` again, compares an identical rect and pushes
	   NOTHING, leaving the browser with no rect and the tile dark for the rest of
	   the room. Keeping the rect makes GDScript's gate correct instead of wedged —
	   `placeTile` is refused while `tileLive` is 0, so nothing is shown early. */
	function healSwap(id) {
		if (!S.peers[id]) { return 0; }
		var keep = S.tiles[id];
		close(id);
		if (!open(id)) { return 0; }
		if (keep) { S.tiles[id] = keep; }
		return 1;
	}

	/* R3 from OUR side: we gave up on this transport. Rate-limited; the remote
	   half in `recv` deliberately is not, because by then the other end has
	   already spent its own budget and refusing would wedge us against a PC that
	   no longer exists. */
	function healRebuild(id) {
		var h = healOf(id);
		var now = styleNow();
		if (h[3] && now - h[3] < HEAL_REBUILD_COOLDOWN_MS) { return 0; }
		if (!healSwap(id)) { return 0; }
		h[2] = h[2] + 1;
		h[3] = now;
		return 1;
	}

	function healClearOffer(p) {
		if (p.offerTimer) { clearTimeout(p.offerTimer); }
		p.offerTimer = null;
		return 1;
	}

	/* R1. Armed on every offer we POST and cleared the moment a description comes
	   back that returns us to `stable` — an answer, or a colliding offer a polite
	   peer rolled its own back for. */
	function healArmOffer(id, p, pc) {
		healClearOffer(p);
		p.offerTimer = setTimeout(function () {
			p.offerTimer = null;
			/* The peer was rebuilt or left while this was armed. */
			if (S.peers[id] !== p) { return; }
			if (pc.signalingState !== 'have-local-offer') { return; }
			p.offerN = p.offerN + 1;
			if (p.offerN >= HEAL_OFFER_TRIES_MAX) {
				if (healRebuild(id)) { return; }
				/* THE REBUILD WAS REFUSED BY ITS COOLDOWN, AND GIVING UP HERE IS
				   THE ONE THING THIS LADDER MAY NOT DO (codex review 2026-09-06).
				   Three 8 s timeouts spend the budget in 24 s, which is INSIDE the
				   30 s rebuild cooldown, so a peer whose offers are still being
				   lost after one rebuild would return from here having rolled
				   nothing back and armed nothing — and a PC fresh out of `open()`
				   sits in `new`, so R2's watch is not running either. That is the
				   wedge this rung exists to break, re-created by its own bound.
				   So the budget starts again and the rollback below still runs:
				   the BOUND is the 8 s cadence, not a number of attempts, and the
				   next expiry re-asks for the rebuild once the cooldown is out. */
				p.offerN = 0;
			}
			healBump(id, 0);
			queue(p, function () {
				if (pc.signalingState !== 'have-local-offer') { return; }
				return pc.setLocalDescription({ type: 'rollback' }).catch(function () { });
			});
		}, HEAL_OFFER_TIMEOUT_MS);
		return 1;
	}

	function healClearIce(p) {
		if (p.iceTimer) { clearTimeout(p.iceTimer); }
		p.iceTimer = null;
		p.iceN = 0;
		p.iceLast = 0;
		return 1;
	}

	/* R2's ACT. Refused inside the cooldown — the watch below re-arms, so a
	   refusal is a wait and never a dead end, which is what "the intent is not
	   sticky" used to be. */
	function healIce(id, p, pc) {
		if (p.iceN >= HEAL_ICE_TRIES_MAX) { return healRebuild(id); }
		var now = styleNow();
		if (p.iceLast && now - p.iceLast < HEAL_ICE_COOLDOWN_MS) { return 0; }
		p.iceLast = now;
		p.iceN = p.iceN + 1;
		healBump(id, 1);
		/* ON THE PEER'S OWN CHAIN, like every other signalling op here, with the
		   state RE-ASKED once it is our turn: a restart fired across an in-flight
		   renegotiation is the collision `recv` rolls back, and a connection that
		   recovered while queued must not be restarted for nothing. */
		queue(p, function () {
			var st = pc.iceConnectionState;
			if (st !== 'failed' && st !== 'disconnected') { return; }
			try { pc.restartIce(); } catch (e) { }
		});
		return 1;
	}

	/* R2's CLOCK. One self-re-arming timer per peer while the transport is not
	   healthy, so a state that never changes again (Chrome sitting in
	   `disconnected` forever) is still walked up the ladder. It stops on its own
	   the moment the peer recovers, is closed or is rebuilt. */
	function healIceWatch(id, p, pc) {
		/* `healIce` above may have REBUILT this peer on its way here, which closed
		   `p`; arming a clock on a connection nobody holds is five seconds of dead
		   timer and one more way to reason wrongly about this ladder later. */
		if (S.peers[id] !== p) { return 0; }
		if (p.iceTimer) { return 0; }
		p.iceTimer = setTimeout(function () {
			p.iceTimer = null;
			if (S.peers[id] !== p) { return; }
			var st = pc.iceConnectionState;
			if (st === 'connected' || st === 'completed' || st === 'closed') { return; }
			healIce(id, p, pc);
			if (S.peers[id] === p) { healIceWatch(id, p, pc); }
		}, HEAL_ICE_HOLD_MS);
		return 1;
	}

	/* The `a=fingerprint:` line of an SDP, or '' — the DTLS certificate is per
	   RTCPeerConnection, so this string changing in a peer's offer means the peer
	   threw its connection away and built a new one. Every m-section carries the
	   same one, so the first is the answer. */
	function sdpFingerprint(sdp) {
		if (!sdp) { return ''; }
		var s = String(sdp);
		var i = s.indexOf('a=fingerprint:');
		if (i < 0) { return ''; }
		/* `String.fromCharCode(10)` rather than a newline escape: this whole module
		   is a GDScript triple-quoted string, which processes escapes of its own,
		   and one backslash of drift here silently makes every fingerprint compare
		   read to the end of the SDP. */
		var j = s.indexOf(String.fromCharCode(10), i);
		return (j < 0 ? s.substr(i) : s.substring(i, j)).trim();
	}

	/* R3's REMOTE HALF. `!was` is "our PC is fresh" — nothing has been applied to
	   it yet, so there is nothing to have changed and two ends that rebuilt at the
	   same moment do not chase each other. */
	function healRemoteRebuilt(p, sdp) {
		var rd = p.pc.remoteDescription;
		if (!rd) { return 0; }
		var was = sdpFingerprint(rd.sdp);
		var now = sdpFingerprint(sdp);
		if (!was || !now) { return 0; }
		return was === now ? 0 : 1;
	}

	/* R4. A `<video>` that paused after its one `play()` shows its last frame
	   forever with a perfectly healthy track behind it. Asked on the 1 Hz sampler
	   that already walks every peer; `retry()` arms the same one-shot gesture
	   listener a blocked `<audio>` uses. */
	function healPaused() {
		for (var k in S.peers) {
			var p = S.peers[k];
			if (p.hasVideo !== 1 || !p.video || !p.video.paused) { continue; }
			var pr = p.video.play();
			if (pr && pr.catch) { pr.catch(function () { retry(); }); }
		}
		return 1;
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
			audio: null, meter: null, cand: [], timer: null, q: Promise.resolve(),
			video: null, vsend: null, hasVideo: 0,
			/* THE STALL COUNTERS (bead godot-test1-xtr.17). `vinPrev`/`voutPrev` are
			   the last ABSOLUTE framesDecoded/framesEncoded this peer reported, so
			   the sampler can answer a DELTA — which is the number that means "is
			   the picture moving". -1 is "never sampled", which must not read as a
			   frame drop on the first sample. */
			vinPrev: -1, voutPrev: -1, vinZero: 0, stalled: 0,
			/* THE HEAL LADDER'S PER-CONNECTION STATE (bead godot-test1-xtr.19).
			   `offerTimer`/`offerN` are R1's; `iceTimer`/`iceN`/`iceLast` are R2's.
			   All five belong to THIS `RTCPeerConnection` and are meant to die with
			   it — the counts that have to survive a rebuild live in `S.heal`. */
			offerTimer: null, offerN: 0, iceTimer: null, iceN: 0, iceLast: 0
		};
		S.peers[id] = p;

		pc.onnegotiationneeded = function () {
			queue(p, function () {
				p.making = 1;
				return pc.setLocalDescription().then(function () {
					post(id, { vc: pc.localDescription.type, sdp: pc.localDescription.sdp });
					/* R1: the relay is best-effort and `post()` swallows every
					   failure, so an offer that is never answered is armed to roll
					   itself back rather than wedging this PC in
					   `have-local-offer` for the life of the room. */
					if (pc.localDescription.type === 'offer') { healArmOffer(id, p, pc); }
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

		/* A DEAD TRANSPORT REBUILDS ITSELF. A NAT/UDP rebind, a coturn allocation
		   expiring against the 12-per-user quota, or a path break the lobby's TCP
		   socket rides out, all drop the PC to `disconnected` and eventually to
		   `failed` — and nothing else here would ever notice: `members()` only
		   closes a PC when the id LEAVES the room, so a still-listed, still-un-muted
		   peer stays silent for the life of the room. `restartIce()` fires
		   `onnegotiationneeded`, which the perfect-negotiation queue above already
		   turns into a fresh offer over the existing "vc" relay — no new signalling
		   kind and no new PC. Both ends may fire it at once; polite/impolite
		   resolves the glare.

		   `disconnected` IS ACTED ON SINCE BEAD godot-test1-xtr.19, WHICH REVERSES
		   WHAT USED TO BE WRITTEN HERE. The old rule — "the transient state that
		   recovers by itself, and restarting on every blip is a re-offer loop" —
		   is true of the blip and false of the case the owner reported: Chrome
		   reaches `failed` only when ICE consent freshness expires (~30 s) and
		   sometimes never leaves `disconnected` at all, so a whole class of dead
		   pair sat silent forever under a handler that was watching the wrong
		   state. The loop it feared is answered by R2's BOUNDS (a 5 s hold, one
		   restart per 15 s, three in a row, then a rebuild) rather than by
		   declining to look. `failed` still acts immediately.

		   NOT the whole of "my Wi-Fi dropped": a real interface handover changes
		   the IP and kills the lobby WEBSOCKET, and `lobby_client` has no
		   reconnect — `_on_lobby_closed` calls `leave()`, which closes every PC.
		   That race is usually lost to TCP long before ICE gives up, so the cases
		   that actually reach here are the three named above.

		   `connectionState === 'failed'` (DTLS rather than ICE) is deliberately
		   still not hooked, and that is not an omission: a DTLS failure takes the
		   ICE state with it, so R2's watch already walks this pair to R3 — which
		   is the rebuild the old comment named as a fallback and nothing
		   implemented. One clock, not two. */
		pc.oniceconnectionstatechange = function () {
			var st = pc.iceConnectionState;
			if (st === 'connected' || st === 'completed') { healClearIce(p); return; }
			if (st === 'failed') { healIce(id, p, pc); healIceWatch(id, p, pc); return; }
			if (st === 'disconnected') { healIceWatch(id, p, pc); return; }
			/* `new` / `checking` / `closed` are left alone ON PURPOSE. Clearing the
			   counters here would be the hole, not the tidy-up: `restartIce()` puts
			   the transport straight into `checking`, so a reset there hands every
			   restart a fresh budget and the bound this rung is built on stops
			   existing. The watch below re-asks the state on its own clock and stops
			   itself on `closed`. */
		};

		/* KIND-GUARDED, which is what lets an OLD build ignore a camera it does not
		   know about and what keeps a peer's video out of the <audio> element. */
		pc.ontrack = function (ev) {
			if (ev.track && ev.track.kind === 'video') {
				p.hasVideo = 1;
				/* A sender's removeTrack reaches us as `mute`, not as `ended`, so
				   both take the picture down — but a `mute` is also what an
				   ordinary media stall looks like, so it KEEPS the rect and
				   `unmute` puts the same picture straight back. An `ended` track
				   never comes back, so that one drops the rect. */
				ev.track.onmute = function () { p.hasVideo = 0; blankTile(id); };
				ev.track.onended = function () { p.hasVideo = 0; hideTile(id); };
				ev.track.onunmute = function () { p.hasVideo = 1; placeTile(id); };
				showVideo(id, new MediaStream([ev.track]));
				return;
			}
			play(id, (ev.streams && ev.streams[0]) ? ev.streams[0] : new MediaStream([ev.track]));
		};

		/* No microphone yet (still asking, or refused) — take the m-line anyway
		   so the handshake happens and this peer can at least LISTEN. */
		if (S.stream) { attach(p); }
		else { try { pc.addTransceiver('audio', { direction: 'recvonly' }); } catch (e) { } }
		/* A peer that joins while the camera is already on gets it on the first
		   handshake rather than on a second renegotiation. */
		attachCam(p);
		return 1;
	}

	function close(id) {
		var p = S.peers[id];
		if (!p) { return 0; }
		if (p.timer) { clearTimeout(p.timer); }
		/* The heal ladder's two clocks belong to this connection and must not
		   outlive it (bead godot-test1-xtr.19): both callbacks re-check
		   `S.peers[id] !== p` and would do nothing, but a rebuild leaves them
		   ticking against a PC nobody holds for another eight seconds. */
		healClearOffer(p);
		healClearIce(p);
		unmeter(p.meter);
		if (p.audio) {
			p.audio.srcObject = null;
			if (p.audio.parentNode) { p.audio.parentNode.removeChild(p.audio); }
		}
		/* THE PICTURE GOES WITH THE PEER — leaving a room may not leave a <video>
		   on the page, exactly as it may not leave an <audio>. */
		delete S.tiles[id];
		if (p.video) {
			p.video.srcObject = null;
			if (p.video.parentNode) { p.video.parentNode.removeChild(p.video); }
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
			applyMic();
			unmeter(S.meterSelf);
			S.meterSelf = meter(st);
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
		/* A LEAVE DROPS THE HEAL TALLY, A REBUILD DOES NOT — that difference is the
		   whole reason `S.heal` is keyed by id rather than held on the peer row. */
		for (var k in S.peers) { if (!want[k]) { close(k); delete S.heal[k]; } }
		for (i = 0; i < ids.length; i++) { open(ids[i]); }
		return 1;
	}

	function recv(id, json) {
		var m;
		try { m = JSON.parse(json); } catch (e) { return 0; }
		if (!S.peers[id]) { open(id); }
		var p = S.peers[id];
		if (!p) { return 0; }
		/* R3's REMOTE HALF (bead godot-test1-xtr.19), and it happens SYNCHRONOUSLY
		   rather than inside the queued job below: the swap replaces `p.q`, so
		   deciding it on the chain would leave this description on the OLD chain
		   while the next ICE batch went to the new one and arrived first. Deciding
		   it here keeps every job for this peer in arrival order on one chain.
		   Nothing is signalled — the peer rebuilt, and its new certificate says so
		   in the offer it already sends. */
		if (m.vc === 'offer' && healRemoteRebuilt(p, m.sdp) === 1) {
			if (!healSwap(id)) { return 0; }
			p = S.peers[id];
			healBump(id, 2);
		}
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
			}).then(function () {
				/* R1's DISARM, and it is keyed on the STATE rather than on the
				   packet: whatever just happened, being back at `stable` means the
				   negotiation this timer was watching is over and `offerN` — the
				   count of CONSECUTIVE unanswered offers — starts again.

				   IT SITS AFTER THE ANSWER, NOT AFTER THE REMOTE DESCRIPTION
				   (codex review 2026-09-06). An incoming OFFER leaves us in
				   `have-remote-offer`, so a disarm on the first `then` skipped
				   every glare a polite peer resolved: the timer that our own
				   rolled-back offer had armed kept counting, and unanswered
				   timeouts SEPARATED by perfectly successful remote-initiated
				   negotiations added up until the third one tore a healthy
				   connection down. A failure rejects before this runs, so nothing
				   is cleared on the path that should still be counted. */
				if (p.pc.signalingState === 'stable') {
					healClearOffer(p);
					p.offerN = 0;
				}
			});
		});
		return 1;
	}

	/* ONE STRING, one bridge call per poll: "id:level,...,me:level" with every
	   level an INTEGER 0-100. Lobby ids are 32 hex characters
	   (`best_run_store._load_or_make_player_id`), so `:` and `,` can never appear
	   in one and `me` can never collide with one. */
	function levels() {
		var out = [];
		for (var k in S.peers) { out.push(k + ':' + level(S.peers[k].meter)); }
		out.push('me:' + level(S.meterSelf));
		return out.join(',');
	}

	/* TELEMETRY FOR \fo (bead godot-test1-xtr.4).
	   One string: local getSettings() ns/ec/agc as 1/0, peer count, per-peer
	   candidate-pair currentRoundTripTime in ms (or -), and inbound-rtp aggregate
	   packet loss percentage. Sampled at <= 1 Hz only while asked, cached so
	   stats() answers synchronously without stalling the frame. */
	/* One per-peer column, in `rtt=`'s own shape: the peers in `peerKeys` order,
	   joined by `/`, and a bare `-` when there are none. */
	function column(a) {
		if (a && a.length) { return a.join('/'); }
		return '-';
	}

	/* The empty video half, so `stats()`'s synchronous fallback and a sampler that
	   has not answered yet print the same KEYS as a live sample. A row whose keys
	   appear and disappear is a row nobody can read at a glance. */
	function noVideo() {
		return { ice: [], con: [], sig: [], sdp: [], vin: [], vout: [], heal: [] };
	}

	function formatStats(ns, ec, agc, peerKeys, rtts, totalLost, totalRecv, vid) {
		var peerCount = peerKeys.length;
		var rttStr = 'rtt=-';
		if (peerCount > 0 && rtts.length > 0) {
			rttStr = 'rtt=' + rtts.join('/') + 'ms';
		}
		var totalPkts = totalLost + totalRecv;
		var lossRate = totalPkts > 0 ? (totalLost / totalPkts * 100.0) : 0.0;
		var lossStr = 'loss=' + lossRate.toFixed(1) + '%';
		/* THE CARTOON CAMERA'S BILL (bead godot-test1-xtr.11), last painted frame.
		   It is the before/after evidence: the paint runs on the browser's main
		   thread, which on this single-threaded export IS Godot's frame.
		   The four STRENGTH KNOBS ride it (bead godot-test1-xtr.16): the owner
		   experiments from the console, and \fo is where they read back what is
		   actually live — `l` levels, `m` mix, `e` edge, `s` shadow. */
		var styleStr = 'style=' + S.paintMs.toFixed(2) + 'ms'
			+ ' l' + S.style[0] + ' m' + S.style[1].toFixed(2)
			+ ' e' + S.style[2] + ' s' + S.style[3].toFixed(2);
		/* THE VIDEO HALF (bead godot-test1-xtr.17), and it is APPENDED: every key
		   above keeps its spelling and its order, so xtr.15's parse and anybody
		   grepping an old log are untouched.
		   Per peer, in `peerKeys` order: the two transport states, the negotiation
		   state, the size of our own last local description, and the decoded /
		   encoded frame DELTAS over the last sample — which at 12 fps read ~12 and
		   go to 0 the moment a picture stops moving. Then, once for this browser:
		   how long ago the paint loop last put pixels on the canvas, and what the
		   capture device itself is doing. Between them they name all four classes
		   of stuck picture the bead enumerates. */
		var vid2 = vid || noVideo();
		var videoStr = ' ice=' + column(vid2.ice) + ' con=' + column(vid2.con)
			+ ' sig=' + column(vid2.sig) + ' sdp=' + column(vid2.sdp)
			+ ' vin=' + column(vid2.vin) + ' vout=' + column(vid2.vout)
			/* WHICH RUNG OF THE HEAL LADDER FIRED (bead godot-test1-xtr.19), per
			   peer in `peerKeys` order and in the ladder's own order:
			   `rollback:ice:rebuild`. It is a running TALLY rather than an event,
			   because \fo is polled and a one-frame flash is a thing nobody sees;
			   the counts survive a rebuild because `S.heal` is keyed by lobby id
			   and the peer row is not. `0:0:0` for a pair that has never needed
			   healing, which is what a healthy room reads. */
			+ ' heal=' + column(vid2.heal)
			+ ' paint=' + paintAge() + ' src=' + srcState()
			/* THE FACE DETECTOR'S BILL (bead godot-test1-xtr.12), and it is THREE
			   numbers because one would hide the answer. `face=` is the round
			   trip — inference included, and on rung 2 that is the WORKER's
			   thread; `f` is which rung of the ladder this browser landed on
			   (0 not asked, 1 loading, 2 vendored worker, 3 centre crop for good,
			   4 the platform's own); `fm` is what Godot's frame actually paid,
			   which is one `createImageBitmap` and one transfer at 3.3 Hz. */
			+ ' face=' + S.faceMs.toFixed(1) + 'ms f' + S.faceState
			+ ' fm' + S.faceMainMs.toFixed(2);
		return 'ns=' + ns + ' ec=' + ec + ' agc=' + agc + ' peers=' + peerCount + ' ' + rttStr + ' ' + lossStr + ' ' + styleStr + videoStr;
	}

	function readLocalConstraints() {
		var res = { ns: 0, ec: 0, agc: 0 };
		if (S.stream) {
			var tracks = S.stream.getAudioTracks();
			if (tracks && tracks.length > 0 && tracks[0].getSettings) {
				var st = tracks[0].getSettings();
				if (st) {
					res.ns = (st.noiseSuppression === 1 || st.noiseSuppression === true) ? 1 : 0;
					res.ec = (st.echoCancellation === 1 || st.echoCancellation === true) ? 1 : 0;
					res.agc = (st.autoGainControl === 1 || st.autoGainControl === true) ? 1 : 0;
				}
			}
		}
		return res;
	}

	function sampleStats() {
		var gen = S.gen;
		var peerKeys = [];
		var promises = [];
		for (var k in S.peers) {
			peerKeys.push(k);
			var pc = S.peers[k].pc;
			if (pc && pc.getStats) {
				try {
					promises.push(pc.getStats());
				} catch (e) {
					promises.push(Promise.resolve(null));
				}
			} else {
				promises.push(Promise.resolve(null));
			}
		}

		Promise.all(promises).then(function (reports) {
			if (gen !== S.gen) {
				S.statsSampling = 0;
				return 0;
			}
			var lc = readLocalConstraints();
			var rtts = [];
			var totalLost = 0;
			var totalRecv = 0;
			var vid = noVideo();

			for (var i = 0; i < reports.length; i++) {
				var report = reports[i];
				var peerLost = 0;
				var peerRecv = 0;
				var peerRtt = -1;
				/* ABSOLUTE counters this sample, turned into a delta below against
				   the peer's own previous pair. -1 is "the report did not carry
				   one", which is not the same as zero and must not read as a stall.
				   SUMMED over every video record rather than taking the last one
				   (codex review 2026-09-06): a peer on an OLD build has one inactive
				   video m-section per camera toggle it ever made, so `getStats()`
				   carries several `inbound-rtp` video rows. Whichever the iteration
				   happened to end on could be a dead one with a frozen counter,
				   which would dim a perfectly live tile. Every row is monotone, so
				   the sum's DELTA is the live row's growth. */
				var vFrames = [-1, -1];

				if (report && report.forEach) {
					report.forEach(function (stat) {
						if (stat && stat.type === 'inbound-rtp' && (stat.kind === 'video' || stat.mediaType === 'video')) {
							if (typeof stat.framesDecoded === 'number') {
								vFrames[0] = (vFrames[0] < 0 ? 0 : vFrames[0]) + stat.framesDecoded;
							}
						} else if (stat && stat.type === 'outbound-rtp' && (stat.kind === 'video' || stat.mediaType === 'video')) {
							if (typeof stat.framesEncoded === 'number') {
								vFrames[1] = (vFrames[1] < 0 ? 0 : vFrames[1]) + stat.framesEncoded;
							}
						} else if (stat && stat.type === 'inbound-rtp' && (stat.kind === 'audio' || stat.mediaType === 'audio')) {
							if (typeof stat.packetsLost === 'number') {
								peerLost += stat.packetsLost;
							}
							if (typeof stat.packetsReceived === 'number') {
								peerRecv += stat.packetsReceived;
							}
						} else if (stat && stat.type === 'candidate-pair') {
							var isSelected = (stat.selected === 1 || stat.selected === true);
							if (isSelected && typeof stat.currentRoundTripTime === 'number') {
								peerRtt = Math.round(stat.currentRoundTripTime * 1000);
							} else if (peerRtt < 0 && (stat.nominated === 1 || stat.nominated === true || stat.state === 'succeeded') && typeof stat.currentRoundTripTime === 'number') {
								peerRtt = Math.round(stat.currentRoundTripTime * 1000);
							}
						}
					});
				}

				totalLost += peerLost;
				totalRecv += peerRecv;
				rtts.push(peerRtt >= 0 ? String(peerRtt) : '-');

				/* THE PER-PEER HEALTH COLUMN, and the receiver's stall verdict with
				   it (bead godot-test1-xtr.17). A peer that left between the request
				   and its answer simply contributes nothing. */
				var pv = S.peers[peerKeys[i]];
				if (!pv) { continue; }
				/* -1 is UNKNOWN and is NOT zero: the report carried no counter, or
				   this is this peer's first sample. `markStall` refuses to count it
				   and the row prints `-` for it — a zero here would dim every tile
				   on a browser that does not report the field, permanently (codex
				   review 2026-09-06). */
				var dIn = (vFrames[0] >= 0 && pv.vinPrev >= 0) ? (vFrames[0] - pv.vinPrev) : -1;
				var dOut = (vFrames[1] >= 0 && pv.voutPrev >= 0) ? (vFrames[1] - pv.voutPrev) : -1;
				pv.vinPrev = vFrames[0];
				pv.voutPrev = vFrames[1];
				markStall(peerKeys[i], pv, dIn);
				vid.ice.push(pv.pc ? pv.pc.iceConnectionState : '-');
				vid.con.push(pv.pc ? pv.pc.connectionState : '-');
				vid.sig.push(pv.pc ? pv.pc.signalingState : '-');
				/* OUR OWN last offer/answer to this peer, in characters. It is the
				   one number that makes bead xtr.18's root cause visible: a video
				   sender removed and re-added grows the description by a whole
				   m-section per toggle, and `MpCodec.MAX_VC_SDP` drops it silently
				   somewhere past the second one. Flat here means flat on the wire. */
				vid.sdp.push((pv.pc && pv.pc.localDescription) ? pv.pc.localDescription.sdp.length : 0);
				vid.vin.push(dIn >= 0 ? dIn : '-');
				vid.vout.push(dOut >= 0 ? dOut : '-');
				var hp = healOf(peerKeys[i]);
				vid.heal.push(hp[0] + ':' + hp[1] + ':' + hp[2]);
			}

			S.statsCache = formatStats(lc.ns, lc.ec, lc.agc, peerKeys, rtts, totalLost, totalRecv, vid);
			S.statsSampling = 0;
			return 1;
		}).catch(function () {
			S.statsSampling = 0;
			return 0;
		});
	}

	/* THE 1 Hz THROTTLE, LIFTED OUT OF `stats()` (bead godot-test1-xtr.17).
	   The sampler is also what marks a stalled tile, and a mark that only happened
	   while \fo was open would be a debug feature rather than a fix. `videoPeers()`
	   is already called at 5 Hz by `_poll_tiles` for the whole life of a room, so
	   nudging it from there costs no new clock, no new bridge call and no GD edit —
	   the throttle below is what keeps it one `getStats()` per peer per second.

	   ponytail: the ceiling is that the sampler runs only while GDScript is polling
	   tiles, i.e. in a room with the module started. Outside a room there is no
	   picture to mark. */
	function sampleTick() {
		var now = styleNow();
		if (!S.statsSampling && (now - S.statsLastTime >= 1000 || !S.statsLastTime)) {
			S.statsSampling = 1;
			S.statsLastTime = now;
			/* R4 (bead godot-test1-xtr.19) rides this throttle rather than a clock
			   of its own: it is the one loop in the module that already walks every
			   peer once a second for the life of a room. Inside the gate, not above
			   it — `videoPeers()` calls this at 5 Hz. */
			healPaused();
			sampleStats();
		}
		return 1;
	}

	function stats() {
		sampleTick();
		if (S.statsCache) {
			return S.statsCache;
		}
		var lc = readLocalConstraints();
		var peerKeys = [];
		for (var k in S.peers) { peerKeys.push(k); }
		return formatStats(lc.ns, lc.ec, lc.agc, peerKeys, [], 0, 0, noVideo());
	}

	function stop() {
		S.gen = S.gen + 1;
		S.tx = 0;
		S.statsCache = '';
		S.statsSampling = 0;
		S.statsLastTime = 0;
		/* THE CAMERA DIES WITH THE ROOM — the opt-in is per room, and a capture
		   device still running outside the room it was granted for is the worst
		   possible way to get this wrong. Before `close()` so `detachCam` still
		   has connections to take the sender off. */
		S.camWant = 0;
		camera(0);
		S.camState = 0;
		S.tiles = {};
		/* PER-PEER MUTES DIE WITH THE ROOM — they are keyed by lobby id and a
		   mute is about the people you are in a room with. Mic mute and deafen
		   are about YOU and survive to the next room, all three being session
		   state that nothing ever persists. */
		S.muted = {};
		/* AND SO DOES THE HEAL TALLY (bead godot-test1-xtr.19): it is keyed by
		   lobby id, and a rejoin gets a fresh one — a count carried into the next
		   room would report healing that never happened in it. */
		S.heal = {};
		unmeter(S.meterSelf);
		S.meterSelf = null;
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

	/* ONE listener for the whole module, and it is what follows the canvas without
	   a round trip through GDScript — see `replaceTiles` for the one resize shape
	   whose fraction the GD poll still has to re-push. */
	try {
		window.addEventListener('resize', replaceTiles);
		document.addEventListener('fullscreenchange', replaceTiles);
	} catch (e) { }

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
		setMicMuted: function (v) { S.micMuted = flag(v); applyMic(); return S.micMuted; },
		setDeafened: function (v) { S.deaf = flag(v); applyAudio(); return S.deaf; },
		setVolume: function (v) { S.vol = pct(v); applyAudio(); return S.vol; },
		setPeerMuted: function (id, v) {
			var on = flag(v);
			if (on) { S.muted[String(id)] = 1; } else { delete S.muted[String(id)]; }
			applyAudio();
			return on;
		},
		levels: levels,
		stats: stats,
		setCamera: function (v) { S.camWant = flag(v); return camera(S.camWant); },
		camState: function () { return S.camState; },
		/* THE HERO'S IDENTITY (bead godot-test1-xtr.11, plus the NAME since bead
		   godot-test1-xtr.13). Three 0-255 channels rather than a hero name for
		   the TINT, so `hero_hud.HERO_COLORS` stays the one table: a name would
		   need a second copy of it here, in a language that cannot read it. The
		   name rides along anyway because the ACCESSORY is a SHAPE, which no
		   colour can name and no GDScript table can hold — and it is a fourth
		   ARGUMENT rather than a second bridge function because the one writer,
		   `_push_style_tint`, is already change-gated on exactly this hero. An
		   older caller passing three arguments leaves it `undefined`, which draws
		   no accessory and tints as before. */
		setStyleTint: function (r, g, b, hero) {
			S.styleTint = [chan(r), chan(g), chan(b)];
			S.styleHero = (typeof hero === 'string') ? hero : '';
			return rebuildRamp();
		},
		/* THE STRENGTH KNOBS (bead godot-test1-xtr.16), driven from the browser
		   console: `window.ckVoice.setStyle(6, 0.6, 1, 0.5)` softens the picture on
		   every receiver's tile within a frame and is remembered across reloads.
		   `getStyle` answers all four as ONE comma-joined string — one bridge call,
		   and a string rather than the four-number array a bridge cannot marshal. */
		setStyle: setStyle,
		getStyle: function () { return S.style.join(','); },
		setTile: setTile,
		hideTile: hideTile,
		videoPeers: videoPeers,
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
	_report_camera()


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
	mic_denied_changed.emit(true)
	if _mp.has_signal("status"):
		_mp.emit_signal("status", MIC_BLOCKED_STATUS)


func _report_camera() -> void:
	"""
	Watch the permission prompt come back and say so ONCE. A refusal is not an
	error and gets no retry loop — the button below simply stops offering, exactly
	as the microphone's status line does one feature along.
	"""
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
	"""
	Close every connection, remove every `<audio>` element and release the capture
	device. Idempotent, and called from both ends — the poll noticing the room is
	gone, and this node leaving the tree.
	"""
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


func debug_line() -> String:
	"""
	One-line debug summary for perf_overlay (\\fo).
	Returns "" when not in a room or off-web.
	Otherwise: 'Voice: mode=PTT tx=1 ns=1 ec=1 agc=1 peers=3 rtt=42/55/61ms loss=0.0%'
	"""
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
	"""Incoming voice volume, 0.0 (silent) to 1.0 (unattenuated)."""
	return _volume


func set_volume(value: float) -> void:
	"""
	Set and persist the incoming voice volume. Clamped rather than rejected — a
	slider hands us its own range and a stored file hands us anything at all, and
	`<audio>.volume` throws outside 0..1.
	"""
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _volume):
		return
	_volume = clamped
	_save_volume()
	if _is_web and _running and _ck != null:
		_ck.setVolume(_volume_pct())


func _volume_pct() -> int:
	"""The bridge's and the store's unit. A NUMBER crosses, never a boolean."""
	return int(roundf(_volume * 100.0))


func _load_volume() -> void:
	"""
	Load the volume from `localStorage` on web or the `[voice]` ConfigFile section
	on desktop, exactly as `_load_mode()` does. Anything unreadable — absent,
	empty, non-numeric, out of range — is `VOLUME_DEFAULT`, because a stored value
	nobody can explain must not be able to make the room silent.
	"""
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
	"""
	Is that peer (or `SELF_LEVEL_KEY`, the local microphone) making noise right
	now? Read by the MP panel's dots every frame and by `_push_speaking()` for the
	name tags — a dictionary lookup, so polling it is free.
	"""
	return int(_speaking_until.get(id, 0)) > Time.get_ticks_msec()


func _poll_levels() -> void:
	"""
	ONE bridge call, ONE string, every peer in it. A per-peer call would be four
	`JavaScriptBridge` round trips ten times a second on a single-threaded web
	export, which is the cost this format exists to avoid — and a per-peer
	BOOLEAN could not cross the bridge at all (see the header).

	Everything the string says is treated as untrusted text: it is our own module
	talking, but it arrives as a Variant through a bridge that has been wrong
	before, so a malformed pair is skipped rather than parsed optimistically.
	"""
	if not _running or _ck == null:
		if not _speaking_until.is_empty() or not _speaking_pushed.is_empty():
			_clear_speaking()
		return
	var raw: Variant = _ck.levels()
	if typeof(raw) != TYPE_STRING:
		return
	apply_levels(str(raw))


func apply_levels(raw: String) -> void:
	"""
	Parse one levels string and re-arm the holds. Split out from the bridge call
	so the format has a seam that can be driven without a browser — the bridge is
	the one thing a headless check can never stand up.
	"""
	var now: int = Time.get_ticks_msec()
	for entry: String in raw.split(",", false):
		var parts: PackedStringArray = entry.split(":")
		if parts.size() != 2 or parts[0].is_empty() or not parts[1].is_valid_float():
			continue
		if parts[1].to_float() >= SPEAK_THRESHOLD:
			_speaking_until[parts[0]] = now + SPEAK_HOLD_MSEC
	_push_speaking()


func _push_speaking() -> void:
	"""
	Drive the remote avatars' name tags, on the EDGE only.

	The avatar is reached BY NODE NAME under the manager (`Peer_<id>`, the name
	`_add_peer()` gives it) rather than through a new getter on `MpManager`: the
	epic holds this feature's manager diff to the three-function voice seam, and a
	`get_node_or_null` plus `has_method` is the same group-discovery degrade
	everything else here uses. A build whose avatar predates `set_speaking` simply
	shows no highlight.
	"""
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
	"""
	What the local microphone is doing, as one of the `MIC_BADGE_*` numbers.

	The ORDER is the priority the row draws: a denied mic can never transmit, and
	a hand mute beats whatever the mode says (`applyMic()` in the browser module
	is `tx && !muted`, and this is that rule read back out).

	IT READS `_reported_mic`, NOT `mic_denied()`, AND THAT IS THE WHOLE POINT OF
	THIS COMMENT. Its caller is a HUD widget's `_process`, so this runs 60 times a
	second in a browser room, and `mic_denied()` asks `_ck.micState()` — a
	`JavaScriptBridge` round trip — on every call. Every other bridge reader in
	this file is throttled and one-call-per-poll for exactly that reason
	(`LEVELS_INTERVAL` 10 Hz, `TILE_INTERVAL` 5 Hz, `POLL_INTERVAL` 2 Hz), and the
	permission answer is the slowest-moving fact here: it changes once per room
	join, when the user answers a prompt. `_report_mic()` already refreshes
	`_reported_mic` off that same 2 Hz `_tick` and fires `mic_denied_changed` on
	the edge, so the cached value is never more than half a second stale and the
	frame path pays nothing. `mp_ui` keeps the live read — it asks once per panel
	refresh, not once per frame.
	"""
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
	"""
	Is the peer HOLDING that hero making noise right now?

	The hero row is the LOCAL roster — four heroes, not four players — so a
	speaking ring resolves through the lobby's `hero_holder()`, exactly like the
	camera tiles of bead .6. The hero WE hold is the one exception: the browser
	reports our own microphone under `SELF_LEVEL_KEY` and never under our lobby
	id, because `S.peers` is remote peers only.

	Everything is `has_method`-guarded and degrades to false: no manager, a
	manager that predates `hero_holder`, a hero nobody holds.
	"""
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
	"""
	Put every live remote picture over the tile of the hero its peer holds.

	ONE bridge call for the roll-call (`videoPeers()`, `levels()`'s one-string
	rule), then at most one `setTile` per peer whose rect actually MOVED — the
	hero row is pinned to a screen corner, so in the steady state that is nothing
	at all. The browser re-places the pictures against the new canvas box on its own
	`resize` listener, so this poll stays silent through a resize that keeps the
	window's ASPECT; one that changes it moves the fraction too (`tile_rect` answers
	in window pixels, and an aspect change moves the binding axis of the stretch and
	the letterbox margin) and the change-gate below pushes the new one.

	Everything is `has_method`-guarded and degrades to no pictures: a scene with no
	hero row, a manager that predates `hero_holder`, a peer holding no hero.
	"""
	if not _running or _ck == null:
		_pushed_tiles.clear()
		return
	var raw: Variant = _ck.videoPeers()
	if typeof(raw) != TYPE_STRING:
		return
	var senders: Dictionary = {}
	for id: String in str(raw).split(",", false):
		senders[id] = true

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
	"""
	Where a picture goes for one hero, as a fraction of the canvas — or an EMPTY
	rect where no picture may be drawn at all.

	ONE home for the two refusals, because a teammate's tile and our own
	(bead `godot-test1-xtr.14`) have to answer them the same way:

	  * A CAPTIVE TILE KEEPS ITS BARS. They are drawn across the whole tile, so no
	    inset leaves them visible — and a benched peer still HOLDS the hero they
	    are locked up as, which is exactly when this fires. It is the same for the
	    hero we drive ourselves.
	  * A tile smaller than its own padding has nothing left to draw in.

	The pad is a FRACTION of the tile, never a pixel count: `tile_rect` is in WINDOW
	pixels, so an absolute pad shrinks in design space as the window grows and eats
	`hero_hud`'s speaking ring. Taken off the width so a tile that is not square (it
	always is) still pads evenly.
	"""
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
	"""
	Tell the browser which hero's colour to tint the mid-tones with.

	It is the hero this peer DRIVES (`MpManager.my_hero()`), not the active tile:
	the face in the picture is the player's, and the character they are playing is
	the one the room reads them as. `hero_hud.gd`'s badge rule, one feature along.

	CHANGE-GATED like `_pushed_tiles`, so in the steady state this whole function
	is one `my_hero()` and a string compare — the browser is only reached when the
	hero really changes hands.

	THE TABLE IS `hero_hud.HERO_COLORS` AND IS NOT COPIED. It is read off the row's
	own SCRIPT through the group node this poll already resolved — a mirrored copy
	of four colours is four chances to drift, and `hero_hud.gd` may not be edited
	to hand them out (the tile geometry is two other beads'). A row it has no
	colour for, or no row at all, degrades to a neutral grey and still cartoons.
	"""
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
