class_name IntroVideo
## ============================================================================
## INTRO FILM — a browser <video> element over the Godot canvas, web only
## ============================================================================
## The 47.5 s opening film that plays when a web player presses PLAY SOLO. It is
## static-only (no node, no scene, no autoload): all of its state lives in the
## browser, on `window.__ck_intro`, and `start_overlay.gd` drives it with three
## calls — `preload_element()` at boot, `start()` on the press, `is_finished()`
## once a frame.
##
## ----------------------------------------------------------------------------
## Why this is a DOM element and not a VideoStreamPlayer
## ----------------------------------------------------------------------------
## Godot 4.5's `VideoStreamPlayer` decodes **Ogg Theora and nothing else**. The
## film is H.264 + AAC, and transcoding it is the wrong trade twice over: Theora
## would come out LARGER, and a `res://` video is bundled into the export pack, so
## a 20 MB intro would have to finish downloading before the game could boot at
## all.
##
## The browser already has a hardware H.264 decoder and an HTTP range-request
## client. Handing it a `<video src=…>` streams the film from the CDN — playback
## starts after ~38 KB, because the file was remuxed with `+faststart` so its
## `moov` index sits at offset 32 instead of at the end of the file. (If the film
## is ever regenerated, `ffmpeg -i episode.mp4 -c copy -movflags +faststart` has to
## be re-applied before upload, or streaming silently regresses to
## download-then-play.) `JavaScriptBridge` DOM work is an established pattern in
## this project — `mobile_sensors.gd` attaches real event listeners and
## `best_run_store.gd` drives `localStorage` — so this is the cheap road, not the
## clever one.
##
## ----------------------------------------------------------------------------
## THE FILM IS NEVER ALLOWED TO BLOCK PLAY
## ----------------------------------------------------------------------------
## This is the invariant every branch below is written to. A missing element, a
## `document.body` that is not there yet, an unreachable URL, a decode error, a
## rejected `play()` promise, a JS exception inside the poll, a stream that never
## produces a frame — **all of them report "finished"**, and the overlay then runs
## its ordinary dismiss. There is no path where the player is left looking at a
## black rectangle, and no path where `is_finished()` can answer `false` forever:
## the two watchdog budgets below (`START_TIMEOUT_SEC` until the first frame,
## `STALL_TIMEOUT_SEC` between frames after that) are the backstop for the one
## case the DOM raises no event for — a stream that simply goes quiet, including a
## `play()` promise that neither resolves nor rejects.
##
## What "finished" must NOT mean is "the world may run now": the caller releases
## the pause on this answer, so a wrong one used to be worth a mauling. That is fixed
## on the caller's side — `start_overlay._dismiss()` tears this element down
## before it unpauses, whatever made it decide the film was over — which is why
## failing open here is still the right trade.
##
## ----------------------------------------------------------------------------
## Autoplay WITH SOUND, and why the fallback exists
## ----------------------------------------------------------------------------
## The film has an AAC track, and browsers block audible autoplay without user
## activation. The PLAY SOLO press IS activation — but Godot dispatches input on
## its own `requestAnimationFrame` tick, **not synchronously inside the DOM click
## handler**, so this rides *sticky* activation (the page has been interacted
## with) rather than *transient* activation (we are inside the handler). Sticky is
## what all three engines actually gate `play()` on, so it works; but it is not a
## guarantee, so a rejected `play()` retries MUTED and shows an unmute button —
## whose click is unambiguously transient activation. Sound, or the film muted
## with one obvious way to fix it. Never a silent black screen.
##
## ----------------------------------------------------------------------------
## Skip is held in JS, not in GDScript
## ----------------------------------------------------------------------------
## The tree is paused behind the film and a DOM overlay above the canvas can hold
## focus, so `Input.is_key_pressed` is not a signal to trust here. The hold lives
## entirely in `window` keydown/keyup listeners plus a `setTimeout`, and the
## progress bar is one CSS width transition of exactly `SKIP_HOLD_SEC`. Godot only
## ever polls the single `done` flag.

# ============================================================================
# TUNABLES
# ============================================================================

## The film, on the project's existing Cloudflare R2 bucket behind its
## already-configured custom domain. Public and unauthenticated by design — it is
## what the web build fetches.
const VIDEO_URL: String = "https://img.cc.wandergeek.org/intro/episode.mp4"

## The ending film uses this same browser lifecycle. Keeping its address beside
## the intro URL makes the two supported films explicit without introducing a
## second DOM player implementation.
const GAME_OVER_VIDEO_URL: String = "https://img.cc.wandergeek.org/game_over.mp4"

## How long SPACE has to be held to skip. A hold rather than a tap so a player
## resting on the key (SPACE is also `jump`) does not lose the film by accident,
## and long enough to read the bar filling but short enough not to feel like a
## punishment.
const SKIP_HOLD_SEC: float = 1.0

## The "never hang" backstop: how long playback may make NO progress before the
## film gives up and the game starts.
##
## It is a **rolling** watchdog — armed at `start()` (with `START_TIMEOUT_SEC`,
## the cold-fetch budget) and re-armed with THIS value by every `timeupdate` —
## rather than a start-only one, because "the stream never began"
## and "the stream stopped halfway" are the same bug to the player and the DOM
## fires no event that reliably covers the second. `ended` and `error` are not
## guaranteed for a connection that simply goes quiet, `stalled`/`waiting` are
## advisory and recoverable, and on a phone there is no keyboard to skip with. One
## timer that only survives while `currentTime` keeps moving covers a dead CDN, a
## `play()` promise that never settles, and a mid-film stall with no special case
## for any of them. Generous, because a slow phone on a slow network is not a
## failure — but finite, because a paused world behind a frozen film is.
const STALL_TIMEOUT_SEC: float = 8.0

## The FIRST-FRAME budget: how long the browser gets between the press and the
## first `timeupdate` before the film gives up. Deliberately far longer than the
## rolling value above, because the two measure different things. Once the film is
## playing the connection is warm and the buffer is full, so eight quiet seconds
## really do mean it died; but the first `timeupdate` has to wait on a cold DNS
## lookup, a TLS handshake, a CDN cache miss and the first frames of a 21.7 MB
## file, and none of that is a failure — it is a slow link doing exactly what it
## should. Arming the rolling value at `start()` made those two indistinguishable
## and tore the film down mid-fetch (godot-test1-4x4). Still finite, because the
## film may never hang the game.
const START_TIMEOUT_SEC: float = 30.0

## The JS scratchpad key, in the same `window`-property style `mobile_sensors.gd`
## uses for its retained callbacks.
const JS_STATE: String = "window.__ck_intro"

## The class stamped on every overlay root this file builds, so teardown can be
## driven off the DOM instead of off the scratchpad.
##
## `finish()` used to detach `root` — the element the state object it was reached
## through happens to hold — and `discard()` did nothing at all when the
## scratchpad was already null. Those two together are the only shape in which the
## reported symptom (a film frozen on its last frame that nothing takes down) is
## reachable: an element on screen that `%s` no longer points at has no owner and
## no exit. Sweeping BY CLASS makes teardown total — every root this file ever
## built goes, whether or not anybody still holds a reference to it — which costs
## one `querySelectorAll` on a path that runs once per film.
const ROOT_CLASS: String = "ck-film-root"


# ============================================================================
# PUBLIC API — all three are safe to call anywhere, on any platform
# ============================================================================

## Build the (hidden) `<video>` and its overlay chrome, so the browser can buffer
## the film while the player reads the start menu and playback begins immediately
## on the press. Idempotent, and a no-op off-web.
static func preload_element(video_url: String = VIDEO_URL) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(_create_js(video_url), true)


## Show the film and start playback. Returns **true only if the browser actually
## took it** — false off-web, false when the element could not be built, false
## when the source already failed to load. A false answer means the caller must
## start the game exactly as it does today.
static func start(video_url: String = VIDEO_URL) -> bool:
	if not OS.has_feature("web"):
		return false
	# Build-if-missing rather than assuming `preload_element()` ran and survived:
	# the film plays on EVERY PLAY SOLO press (owner decision — no first-visit
	# flag, no persistence), and a finished film tears its own element down, so a
	# second press would otherwise have nothing to show.
	JavaScriptBridge.eval(_create_js(video_url), true)
	return JavaScriptBridge.eval(_start_js(), true) == true


## The start snippet: reveal, arm the skip listeners and the hang backstop, and
## hand playback to the browser.
##
## The labels are baked in HERE, not at create time, because the player can switch
## language on the start card after boot — see `start_overlay.gd`'s locale row.
## `TranslationServer.translate` is the static form of `tr()`; this file has no
## instance to call `tr()` on, and CLAUDE.md's rule 2 (translate explicitly
## wherever text is composed at runtime) applies all the same — a DOM element is
## not a `Control` and gets none of Godot's auto-translation.
static func _start_js() -> String:
	return """
		(function(){
			try {
				var s = %s;
				if (!s || s.done) { return false; }
				/* The source already failed to load. Tear the dead element down
				   through the single exit rather than just declining — otherwise a
				   hidden <video> with its retained buffers outlives the whole
				   session for a film that is never going to play. */
				if (s.failed) { s.finish(); return false; }
				if (s.started) { return true; }
				s.started = true;
				s.hint.textContent = %s;
				s.unmute.textContent = %s;
				s.root.style.display = 'block';
				try { s.video.currentTime = 0; } catch (e) {}
				window.addEventListener('keydown', s.onKeyDown, true);
				window.addEventListener('keyup', s.onKeyUp, true);
				/* Armed with the FIRST-FRAME budget, not the rolling one: nothing
				   has been fetched yet. Every later arming comes from `timeupdate`
				   and takes the (much shorter) default. */
				s.armWatchdog(%d);
				var p = s.video.play();
				if (p && p.catch) {
					p.catch(function(){
						/* Audible autoplay refused: muted always plays, and the
						   button's own click is transient activation. */
						s.video.muted = true;
						s.unmute.style.display = 'block';
						var q = s.video.play();
						if (q && q.catch) { q.catch(function(){ s.fail(); }); }
					});
				}
				return true;
			} catch (e) { return false; }
		})()
	""" % [
		JS_STATE,
		JSON.stringify(String(TranslationServer.translate("Hold SPACE to skip"))),
		JSON.stringify(String(TranslationServer.translate("Unmute"))),
		int(START_TIMEOUT_SEC * 1000.0),
	]


## Throw the (possibly still buffering) element away without ever showing it —
## what MULTIPLAYER does, because that press opens a panel instead of starting a
## game and the film is never coming. `preload="auto"` is a hint the browser is
## free to take seriously, so leaving a live 20 MB source attached for a whole
## multiplayer session is bandwidth nobody asked for. Routed through the same
## single `finish` exit as every other ending, so the teardown is the one that is
## already known to be complete. Idempotent, and a no-op off-web.
static func discard() -> void:
	if not OS.has_feature("web"):
		return
	# The sweep runs UNCONDITIONALLY, not just when there is a state object to
	# call `finish()` on: a null scratchpad used to mean "nothing to do", which is
	# exactly wrong for the one case this needs to cover — an orphaned root still
	# on screen. See ROOT_CLASS.
	JavaScriptBridge.eval(
		"(function(){try{var s=%s;if(s){s.finish();}%s}catch(e){}})()"
		% [JS_STATE, _sweep_js()], true)


## Detach every overlay root this file ever built, releasing each one's source
## first so a still-decoding element cannot go on playing audio off-screen.
## Idempotent by construction (a swept element is no longer in the document) and
## safe to run when there is nothing to sweep.
static func _sweep_js() -> String:
	return """
		var q = document.querySelectorAll('.%s');
		for (var i = 0; i < q.length; i++) {
			var vs = q[i].getElementsByTagName('video');
			for (var j = 0; j < vs.length; j++) {
				try { vs[j].pause(); vs[j].removeAttribute('src'); vs[j].load(); } catch (e) {}
			}
			if (q[i].parentNode) { q[i].parentNode.removeChild(q[i]); }
		}
	""" % ROOT_CLASS


## True once the film has ended, been skipped, or failed. **Fails open**: off-web,
## on a missing element, on a non-boolean answer or on any JS exception this is
## `true`, because the only thing worse than losing the intro is not being able to
## start the game.
static func is_finished() -> bool:
	if not OS.has_feature("web"):
		return true
	var js := "(function(){try{var s=%s;return !s||!!s.done;}catch(e){return true;}})()" % JS_STATE
	var answer: Variant = JavaScriptBridge.eval(js, true)
	return typeof(answer) != TYPE_BOOL or bool(answer)


## How far into the film the browser has actually got, in seconds — or `-1.0`
## when there is nothing to ask (off-web, no element, a JS exception).
##
## This is the ONE fact that separates a film that is playing from a film that is
## wedged, and it exists so the GODOT side can watch for a stall on its own clock
## instead of trusting the browser's `setTimeout` to still be alive. Everything
## below `is_finished()` — the `ended` listener, the rolling watchdog, `finish()`
## itself — lives in the same JS state machine, so if that machine stops, every
## backstop in it stops with it and `is_finished()` answers `false` forever. A
## number Godot can compare against the number it saw last frame is outside that
## machine, which is the whole point. See `start_overlay._film_stalled()`.
static func progress() -> float:
	if not OS.has_feature("web"):
		return -1.0
	var js := "(function(){try{var s=%s;return (s&&s.video)?s.video.currentTime:-1;}" % JS_STATE \
		+ "catch(e){return -1;}})()"
	var answer: Variant = JavaScriptBridge.eval(js, true)
	if typeof(answer) != TYPE_FLOAT and typeof(answer) != TYPE_INT:
		return -1.0
	return float(answer)


## True when the last started film failed while loading or playing. The result
## survives `finish()` so callers can choose the fallback panel instead of
## treating a dead stream like a deliberate end or skip. Off-web is false.
static func was_failed() -> bool:
	if not OS.has_feature("web"):
		return false
	var js := "(function(){try{return !!window.__ck_intro_failed;}catch(e){return true;}})()"
	var answer: Variant = JavaScriptBridge.eval(js, true)
	return typeof(answer) != TYPE_BOOL or bool(answer)


# ============================================================================
# INTERNAL — the element, built once
# ============================================================================

## The create snippet. Idempotent (returns early when the state object already
## exists) and total: it returns `false` rather than throwing when there is no
## `document.body` to attach to.
##
## Everything is inline styles on plain elements rather than a stylesheet — the
## same reason the rest of this game's UI is built in code and ships no assets:
## one place to read, nothing to keep in sync.
static func _create_js(video_url: String = VIDEO_URL) -> String:
	return """
		(function(){
			try {
				if (%s) {
					if (%s.video_url === %s) { return true; }
					%s.finish();
				}
				if (!document || !document.body) { return false; }
				window.__ck_intro_failed = false;

				var root = document.createElement('div');
				/* The handle teardown is driven off — see ROOT_CLASS. */
				root.className = '%s';
				root.style.cssText = 'position:fixed;left:0;top:0;width:100%%;height:100%%;' +
					'z-index:2147483000;background:#000;display:none;';

				var v = document.createElement('video');
				v.src = %s;
				v.preload = 'auto';
				/* MANDATORY on iOS Safari: without it playback is yanked into the
				   system fullscreen player, over the game and out of our control. */
				v.playsInline = true;
				v.setAttribute('playsinline', '');
				v.setAttribute('webkit-playsinline', '');
				v.style.cssText = 'position:absolute;left:0;top:0;width:100%%;height:100%%;' +
					'object-fit:contain;background:#000;';
				root.appendChild(v);

				var hint = document.createElement('div');
				hint.style.cssText = 'position:absolute;left:0;right:0;bottom:7%%;text-align:center;' +
					'color:#fff;opacity:.85;pointer-events:none;text-shadow:0 1px 4px #000;' +
					'font:600 16px system-ui,-apple-system,sans-serif;';
				root.appendChild(hint);

				/* The hold indicator: one bar whose width transition lasts exactly
				   the hold, so the animation the player reads and the timeout that
				   actually skips cannot disagree about how much longer to hold. */
				var track = document.createElement('div');
				track.style.cssText = 'position:absolute;left:50%%;bottom:4%%;width:220px;height:4px;' +
					'margin-left:-110px;border-radius:2px;background:rgba(255,255,255,.25);' +
					'pointer-events:none;';
				var bar = document.createElement('div');
				bar.style.cssText = 'width:0;height:100%%;border-radius:2px;background:#fff;';
				track.appendChild(bar);
				root.appendChild(track);

				var unmute = document.createElement('button');
				unmute.style.cssText = 'position:absolute;right:16px;top:16px;display:none;' +
					'padding:10px 16px;border:0;border-radius:8px;cursor:pointer;' +
					'background:rgba(0,0,0,.66);color:#fff;' +
					'font:600 16px system-ui,-apple-system,sans-serif;';
				root.appendChild(unmute);

				var s = {
					root: root, video: v, hint: hint, bar: bar, unmute: unmute,
					video_url: %s,
					done: false, started: false, failed: false,
					holdTimer: null, stallTimer: null, seen: {}
				};

				/* The rolling no-progress watchdog. Re-armed from scratch every time
				   `currentTime` moves, so it can only ever fire on a film that has
				   genuinely stopped. `ms` is the budget for THIS arming: `start()`
				   passes the generous first-frame one (nothing is fetched yet), and
				   `timeupdate` omits it for the tight rolling default. See
				   START_TIMEOUT_SEC / STALL_TIMEOUT_SEC. */
				s.armWatchdog = function(ms){
					/* Nothing to watch until the film is actually on screen — a
					   `timeupdate` during preload must not arm a timer that would
					   tear the buffered element down behind the menu. */
					if (!s.started) { return; }
					if (s.stallTimer) { clearTimeout(s.stallTimer); }
					s.stallTimer = setTimeout(s.fail, ms || %d);
				};

				/* THE SINGLE EXIT. Every ending — natural end, skip, decode error,
				   both play() rejections, the stall watchdog, the MULTIPLAYER
				   discard that never shows the film at all — comes through here, and
				   it leaves NOTHING over the canvas: listeners off, source released,
				   element detached, scratchpad cleared. Idempotent, because several
				   of those can race. */
				s.fail = function(){
					s.failed = true;
					s.finish();
				};

				s.finish = function(){
					if (s.done) { return; }
					s.done = true;
					window.__ck_intro_failed = !!s.failed;
					if (s.holdTimer) { clearTimeout(s.holdTimer); s.holdTimer = null; }
					if (s.stallTimer) { clearTimeout(s.stallTimer); s.stallTimer = null; }
					window.removeEventListener('keydown', s.onKeyDown, true);
					window.removeEventListener('keyup', s.onKeyUp, true);
					/* BY CLASS, not `root`: this element's own root carries it, and
					   so does any earlier one that lost its owner. See ROOT_CLASS. */
					%s
					%s = null;
				};

				unmute.onclick = function(){
					v.muted = false;
					unmute.style.display = 'none';
					var p = v.play();
					if (p && p.catch) { p.catch(function(){}); }
				};

				/* THE FILM IS MODAL, so it swallows EVERY key, not just its own.
				   These are registered on `window` in the CAPTURE phase, which is the
				   topmost target there is, so `stopPropagation()` here means Godot's
				   own canvas/document listeners never see the event at all. Without
				   it the game is still listening behind the video — the tree is
				   paused, but every PROCESS_MODE_ALWAYS overlay (help card, skill
				   tree, MP panel) is not, and one stray keypress would open a panel
				   invisibly behind the film and be sitting over a running world the
				   moment `_dismiss()` releases the pause.
				   `preventDefault()` stays SPACE-only: it suppresses the browser's
				   own default action (page scroll), which is ours to cancel for the
				   skip key and nobody else's business for the rest. */
				s.swallow = function(e){
					e.stopPropagation();
					if (e.stopImmediatePropagation) { e.stopImmediatePropagation(); }
					if (e.code === 'Space' || e.key === ' ') { e.preventDefault(); return true; }
					return false;
				};
				s.keyOf = function(e){ return e.code || e.key; };
				s.onKeyDown = function(e){
					s.seen[s.keyOf(e)] = true;
					if (!s.swallow(e)) { return; }
					/* Key auto-repeat fires keydown over and over while held — the
					   first one owns the timer and the rest are ignored, or every
					   repeat would restart the hold and it could never complete. */
					if (s.holdTimer) { return; }
					bar.style.transition = 'width %ss linear';
					bar.style.width = '100%%';
					s.holdTimer = setTimeout(s.finish, %d);
				};
				s.onKeyUp = function(e){
					/* ONLY swallow the release of a press WE swallowed. The obvious
					   victim otherwise is the SPACE that launched the film: PLAY SOLO
					   has SPACE as its shortcut, so that keydown reached Godot before
					   these listeners existed, and eating its keyup would leave
					   `jump`/`ui_accept` latched down — the next press is then no
					   longer a transition and the player's first jump after the film
					   is silently eaten. */
					var k = s.keyOf(e);
					if (!s.seen[k]) { return; }
					delete s.seen[k];
					if (!s.swallow(e)) { return; }
					if (s.holdTimer) { clearTimeout(s.holdTimer); s.holdTimer = null; }
					bar.style.transition = 'width .15s ease-out';
					bar.style.width = '0';
				};

				v.addEventListener('ended', s.finish);
				/* An error BEFORE playback (unreachable URL, wrong content type)
				   must not tear the element down — `start()` would only rebuild it
				   and hit the same wall. Mark it failed instead, so `start()`
				   answers false and the game begins with no film and no delay. */
				v.addEventListener('error', function(){
					if (s.started) { s.fail(); } else { s.failed = true; }
				});
				/* `timeupdate` is the only "playback actually moved" signal the DOM
				   offers, and it is exactly what the watchdog should live on. */
				v.addEventListener('timeupdate', function(){ s.armWatchdog(); });

				document.body.appendChild(root);
				%s = s;
				return true;
			} catch (e) { return false; }
		})()
	""" % [
		JS_STATE,
		JS_STATE,
		JSON.stringify(video_url),
		JS_STATE,
		ROOT_CLASS,
		JSON.stringify(video_url),
		JSON.stringify(video_url),
		int(STALL_TIMEOUT_SEC * 1000.0),
		_sweep_js(),
		JS_STATE,
		String.num(SKIP_HOLD_SEC, 3),
		int(SKIP_HOLD_SEC * 1000.0),
		JS_STATE,
	]
