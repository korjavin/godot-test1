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
## `START_TIMEOUT_SEC` is the backstop for the one case the DOM raises no event
## for (a `play()` promise that neither resolves nor rejects).
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

## How long SPACE has to be held to skip. A hold rather than a tap so a player
## resting on the key (SPACE is also `jump`) does not lose the film by accident,
## and long enough to read the bar filling but short enough not to feel like a
## punishment.
const SKIP_HOLD_SEC: float = 1.0

## The "never hang" backstop: if no frame has been painted this long after
## `start()`, give up and start the game. Armed at `start()` and cleared by the
## first `playing` event, so it only ever fires when playback genuinely never
## began — a stalled CDN, or a `play()` promise that neither settles nor errors.
## Generous, because a slow phone on a slow network is not a failure.
const START_TIMEOUT_SEC: float = 8.0

## The JS scratchpad key, in the same `window`-property style `mobile_sensors.gd`
## uses for its retained callbacks.
const JS_STATE: String = "window.__ck_intro"


# ============================================================================
# PUBLIC API — all three are safe to call anywhere, on any platform
# ============================================================================

## Build the (hidden) `<video>` and its overlay chrome, so the browser can buffer
## the film while the player reads the start menu and playback begins immediately
## on the press. Idempotent, and a no-op off-web.
static func preload_element() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(_create_js(), true)


## Show the film and start playback. Returns **true only if the browser actually
## took it** — false off-web, false when the element could not be built, false
## when the source already failed to load. A false answer means the caller must
## start the game exactly as it does today.
static func start() -> bool:
	if not OS.has_feature("web"):
		return false
	# Build-if-missing rather than assuming `preload_element()` ran and survived:
	# the film plays on EVERY PLAY SOLO press (owner decision — no first-visit
	# flag, no persistence), and a finished film tears its own element down, so a
	# second press would otherwise have nothing to show.
	JavaScriptBridge.eval(_create_js(), true)
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
				if (!s || s.failed || s.done) { return false; }
				if (s.started) { return true; }
				s.started = true;
				s.hint.textContent = %s;
				s.unmute.textContent = %s;
				s.root.style.display = 'block';
				try { s.video.currentTime = 0; } catch (e) {}
				window.addEventListener('keydown', s.onKeyDown, true);
				window.addEventListener('keyup', s.onKeyUp, true);
				s.startTimer = setTimeout(s.finish, %d);
				var p = s.video.play();
				if (p && p.catch) {
					p.catch(function(){
						/* Audible autoplay refused: muted always plays, and the
						   button's own click is transient activation. */
						s.video.muted = true;
						s.unmute.style.display = 'block';
						var q = s.video.play();
						if (q && q.catch) { q.catch(function(){ s.finish(); }); }
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
static func _create_js() -> String:
	return """
		(function(){
			try {
				if (%s) { return true; }
				if (!document || !document.body) { return false; }

				var root = document.createElement('div');
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
					done: false, started: false, failed: false,
					holdTimer: null, startTimer: null
				};

				/* THE SINGLE EXIT. Every ending — natural end, skip, decode error,
				   both play() rejections, the start timeout — comes through here, and
				   it leaves NOTHING over the canvas: listeners off, source released,
				   element detached, scratchpad cleared. Idempotent, because several
				   of those can race. */
				s.finish = function(){
					if (s.done) { return; }
					s.done = true;
					if (s.holdTimer) { clearTimeout(s.holdTimer); s.holdTimer = null; }
					if (s.startTimer) { clearTimeout(s.startTimer); s.startTimer = null; }
					window.removeEventListener('keydown', s.onKeyDown, true);
					window.removeEventListener('keyup', s.onKeyUp, true);
					try { v.pause(); v.removeAttribute('src'); v.load(); } catch (e) {}
					if (root.parentNode) { root.parentNode.removeChild(root); }
					%s = null;
				};

				unmute.onclick = function(){
					v.muted = false;
					unmute.style.display = 'none';
					var p = v.play();
					if (p && p.catch) { p.catch(function(){}); }
				};

				s.onKeyDown = function(e){
					if (e.code !== 'Space' && e.key !== ' ') { return; }
					e.preventDefault();
					/* Key auto-repeat fires keydown over and over while held — the
					   first one owns the timer and the rest are ignored, or every
					   repeat would restart the hold and it could never complete. */
					if (s.holdTimer) { return; }
					bar.style.transition = 'width %ss linear';
					bar.style.width = '100%%';
					s.holdTimer = setTimeout(s.finish, %d);
				};
				s.onKeyUp = function(e){
					if (e.code !== 'Space' && e.key !== ' ') { return; }
					e.preventDefault();
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
					if (s.started) { s.finish(); } else { s.failed = true; }
				});
				v.addEventListener('playing', function(){
					if (s.startTimer) { clearTimeout(s.startTimer); s.startTimer = null; }
				});

				document.body.appendChild(root);
				%s = s;
				return true;
			} catch (e) { return false; }
		})()
	""" % [
		JS_STATE,
		JSON.stringify(VIDEO_URL),
		JS_STATE,
		String.num(SKIP_HOLD_SEC, 3),
		int(SKIP_HOLD_SEC * 1000.0),
		JS_STATE,
	]
