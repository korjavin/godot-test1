extends SceneTree
## ============================================================================
## INTRO FILM SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/intro_selfcheck.gd
##
## WHAT THIS CAN AND CANNOT GUARD, stated up front because half of this feature
## is unreachable from here:
##
## The film itself is a browser `<video>` element driven through
## `JavaScriptBridge` (see `intro_video.gd`'s header for why it has to be). A
## headless Godot has no `JavaScriptBridge`, no DOM, no H.264 decoder and no
## network, so **that it actually plays, that autoplay is granted, that holding
## SPACE skips it and that the element is torn down are NOT verifiable here and
## are not claimed to be.** They are browser behaviour and only a browser can
## answer for them.
##
## ponytail: the JS half is verified by hand in a real web build. Building a
## headless DOM harness (jsdom + a node runner + a fake JavaScriptBridge) to
## exercise ~90 lines of one-shot glue would cost more than the glue and would
## still not test the thing that can actually go wrong — a real browser's autoplay
## policy. If this file grows a second video or a second trigger, revisit.
##
## WHAT IS CHECKABLE IS THE HALF THAT CAN SILENTLY BREAK EVERY DESKTOP PLAYER,
## and that is what is here:
##
##  1. **The web gate.** Every entry point must be inert off-web WITHOUT touching
##     `JavaScriptBridge` — the same desktop-safety shape `MobileSensors` carries.
##     `start()` false and `is_finished()` true are what make the desktop path
##     below reduce to the original code.
##
##  2. **The desktop PLAY SOLO path is byte-for-byte the old one.** Pressing it
##     must still dismiss the card, release the tree pause and leave no intro state
##     latched. This is the regression that would ship as "the game no longer
##     starts", and it is checked with a negative control: the tree is asserted
##     PAUSED before the press, or "unpaused after" would be satisfied by an
##     overlay that never paused anything at all.
##
##  3. **MULTIPLAYER never plays the film.** It shares `_dismiss()` with PLAY
##     SOLO, which is exactly why the hook went on `_on_play_solo_pressed()`
##     instead — so this asserts the split held.
##
##  4. **The generated JS survived GDScript's `%` formatting.** The create snippet
##     is a format string full of CSS percentages, every one of which has to be
##     written `%%`. Get one wrong and `String.format` either throws or silently
##     emits a broken stylesheet — in the browser, on the web build, where nobody
##     is looking. Cheap to assert, so it is asserted.
##
##  5. **THE WORLD NEVER RUNS BEHIND THE FILM.** The web branch of
##     `start_overlay._process()` — the one that holds the pause while the film
##     plays — was asserted by nothing at all, and it shipped godot-test1-4x4: the
##     player watched 47 s of film with a live world and a live crocodile behind
##     it, and was mauled by it. Off-web `IntroVideo.is_finished()` is a constant
##     `true`, so that branch cannot be driven for a single frame without a seam;
##     `start_overlay` therefore routes its two browser calls through
##     `_film_finished()` / `_film_teardown()` and `FilmOverlay` below overrides
##     them. What is asserted is the invariant itself, in both directions: while
##     the film is up the tree STAYS paused, and the step that finally unpauses it
##     is the same step that tears the element down — teardown first.
##
##  6. **THE FILM'S END IS WATCHDOG-COVERED FROM BOTH SIDES.** Every backstop the
##     film had lived inside ONE browser state machine, so any way that machine
##     stops is a way `is_finished()` answers `false` forever behind a frozen last
##     frame (godot-test1-3iy.20). The Godot-side stall clock is checked with its
##     own negative control: a film whose position keeps advancing must survive
##     well past the budget, and a film whose position never moves must be given
##     up on inside it, as a FAILURE, with the teardown before the unpause.
##
##  7. **THE FILM'S END NEVER MINTS A WORLD.** The end of the film hands the
##     player an interactive surface and decides nothing; only Play Again reaches
##     `restart_game()` and therefore `BestRunStore.new_game()`. Driven against a
##     counting stand-in in group `"player"`, because the bug is the CALL.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const StartOverlay := preload("res://scripts/start_overlay.gd")
const GameOverUI := preload("res://scripts/game_over_ui.gd")


## The real start overlay with the film's two browser calls stubbed, so check 5
## can hold the film "playing" for as many frames as it likes on a headless build
## that has no DOM. Nothing else is overridden — the pause, the dismissal and the
## ordering under test are all the shipping code's.
class FilmOverlay extends StartOverlay:
	## What `_film_finished()` answers. The check flips it to end the film.
	var film_over: bool = false

	## How many times the element was torn down, and whether the tree was still
	## paused when it happened — which is the ordering the invariant is made of.
	var teardowns: int = 0
	var teardown_saw_paused: bool = false

	## URLs routed through the one shared IntroVideo.start() seam.
	var started_urls: Array[String] = []
	var ending_callbacks: int = 0
	var callback_failed: bool = false
	var film_failed: bool = false

	## What `_film_progress()` answers — the browser's playback position, which is
	## the one number the Godot-side stall backstop watches. Held constant to
	## simulate a wedged film; advanced to simulate a healthy one.
	var film_progress: float = 0.0

	func _start_film(video_url: String) -> bool:
		started_urls.append(video_url)
		return true

	func record_ending_callback(failed: bool) -> void:
		ending_callbacks += 1
		callback_failed = failed

	func _film_failed() -> bool:
		return film_failed

	func _film_finished() -> bool:
		return film_over

	func _film_progress() -> float:
		return film_progress

	func _film_teardown() -> void:
		teardowns += 1
		teardown_saw_paused = get_tree().paused

var _failures: Array[String] = []


## `_initialize()` runs inside `MainLoop::initialize()`, BEFORE the root window is
## live — a node added there is parented but has no `SceneTree`, so `_ready()`
## never fires and every check below would measure an overlay that never woke up.
## The same one-frame wait `minimap_selfcheck.gd` opens with, for the same reason;
## `_initialize()` cannot await, so the body is its own coroutine.
func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_check_web_gate()
	_check_generated_js()
	_check_game_over_film_path()
	_check_play_solo_desktop_path()
	_check_multiplayer_never_plays()
	_check_world_stays_paused_behind_the_film()
	_check_film_end_is_watchdog_covered()
	_check_film_end_never_mints_a_world()
	_finish()


func _finish() -> void:
	# Leave the tree exactly as found — a self-check that quits with the tree
	# paused is harmless today but is a trap for whatever runs after it.
	paused = false
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE WEB GATE
# ============================================================================

## Off-web every entry point must be inert. If any of these reached
## `JavaScriptBridge` the call would error on a desktop build; more importantly,
## a `start()` that answered true here would strand the desktop player behind a
## film that can never finish.
func _check_web_gate() -> void:
	if OS.has_feature("web"):
		# Not a failure — just nothing this check can say. Godot cannot be run
		# headless as a web export, so in practice this branch is unreachable.
		return

	# Must not crash and must not do anything.
	IntroVideo.preload_element()

	if IntroVideo.start():
		_fail("IntroVideo.start() answered true off-web — the desktop PLAY SOLO " \
			+ "path would wait forever for a film that cannot exist")
	if not IntroVideo.is_finished():
		_fail("IntroVideo.is_finished() answered false off-web — it must fail open, " \
			+ "or `_process` never dismisses the start overlay")
	# The stall backstop's input. Off-web it must be inert like the rest — and it
	# must answer the "nothing to ask" sentinel rather than a plausible position,
	# or a desktop build would look like a film frozen at that position.
	if IntroVideo.progress() != -1.0:
		_fail("IntroVideo.progress() answered %f off-web — it must report -1.0 " \
			% IntroVideo.progress() + "without touching JavaScriptBridge")

	# The tunables the browser half is built from.
	if not IntroVideo.VIDEO_URL.begins_with("https://"):
		_fail("VIDEO_URL must be an https URL (a web build on https cannot load " \
			+ "mixed content), got %s" % IntroVideo.VIDEO_URL)
	if not IntroVideo.GAME_OVER_VIDEO_URL.begins_with("https://"):
		_fail("GAME_OVER_VIDEO_URL must be an https URL, got %s" \
			% IntroVideo.GAME_OVER_VIDEO_URL)
	if IntroVideo.SKIP_HOLD_SEC <= 0.0:
		_fail("SKIP_HOLD_SEC must be positive, or a stray SPACE tap skips the film")
	if IntroVideo.STALL_TIMEOUT_SEC <= IntroVideo.SKIP_HOLD_SEC:
		_fail("STALL_TIMEOUT_SEC (%f) must exceed SKIP_HOLD_SEC (%f) — the hang " \
			% [IntroVideo.STALL_TIMEOUT_SEC, IntroVideo.SKIP_HOLD_SEC] \
			+ "backstop firing before a deliberate skip can complete is a bug")
	# The cold fetch of a 21.7 MB film from a standing start is not the same
	# measurement as a gap between two frames of a film already playing, and giving
	# them the same budget is what tore the film down mid-fetch (godot-test1-4x4).
	if IntroVideo.START_TIMEOUT_SEC <= IntroVideo.STALL_TIMEOUT_SEC:
		_fail("START_TIMEOUT_SEC (%f) must exceed STALL_TIMEOUT_SEC (%f) — a slow " \
			% [IntroVideo.START_TIMEOUT_SEC, IntroVideo.STALL_TIMEOUT_SEC] \
			+ "first buffer would be treated as a dead stream and the film killed " \
			+ "before its first frame")
	# Godot's own backstop is a BACKSTOP: it may only ever fire on a film the
	# browser's two watchdogs already failed to catch. Set it below either budget
	# and it becomes a second, tighter policy that kills healthy slow fetches.
	if StartOverlay.FILM_STALL_LIMIT_SEC <= maxf(
			IntroVideo.START_TIMEOUT_SEC, IntroVideo.STALL_TIMEOUT_SEC):
		_fail("start_overlay.FILM_STALL_LIMIT_SEC (%f) does not exceed the browser's " \
			% StartOverlay.FILM_STALL_LIMIT_SEC \
			+ "own watchdog budgets — Godot would pre-empt the film's cold fetch " \
			+ "instead of backstopping a wedged one")

	# `discard()` is the MULTIPLAYER path's teardown. Off-web it must be as inert
	# as the rest — it is called unconditionally from `_on_multiplayer_pressed()`.
	IntroVideo.discard()


# ============================================================================
# 4. THE GENERATED JS
# ============================================================================

## The create snippet is one big GDScript format string. Assert that it came out
## the other side intact: no unconsumed placeholder, no doubled percent left in
## the CSS, and the pieces the acceptance criteria name by hand actually present.
func _check_generated_js() -> void:
	var js: String = IntroVideo._create_js()

	for snippet: Array in [["_create_js()", js], ["_start_js()", IntroVideo._start_js()]]:
		var name: String = snippet[0]
		var source: String = snippet[1]
		if source.contains("%s") or source.contains("%d"):
			_fail("%s left an unconsumed format placeholder — the browser would " % name \
				+ "get a syntax error and the film would silently never appear")
		if source.contains("%%"):
			_fail("%s emitted a literal `%%%%` — a CSS percentage was over-escaped " % name \
				+ "and the overlay will be mis-sized")

	# The start snippet's own load-bearing pieces: the muted retry that keeps a
	# refused audible autoplay from becoming a black screen, and the timeout that
	# is the only backstop against a `play()` promise that never settles.
	var start_js: String = IntroVideo._start_js()
	if not start_js.contains("s.video.muted = true"):
		_fail("_start_js() lost its muted retry — a browser that refuses audible " \
			+ "autoplay would leave the player on a silent black rectangle")
	# Armed WITH THE FIRST-FRAME BUDGET, not bare: a bare call takes the rolling
	# default, which is the mid-film gap and far too short for a cold fetch.
	if not start_js.contains("s.armWatchdog(%d)" % int(IntroVideo.START_TIMEOUT_SEC * 1000.0)):
		_fail("_start_js() no longer arms the stall watchdog with START_TIMEOUT_SEC " \
			+ "— a stream that never plays would hang the start menu forever, and a " \
			+ "slow one would be killed before its first frame")

	# The watchdog has to ROLL. A start-only timeout looks identical in a passing
	# build and hangs the game on any mid-film stall, which fires no `ended`, no
	# `error`, and cannot be skipped at all on a phone.
	if not js.contains("addEventListener('timeupdate'"):
		_fail("_create_js() no longer re-arms the watchdog on `timeupdate` — a film " \
			+ "that stalls after it started playing would pause the world forever")
	# The film is modal. Without capture-phase swallowing, a stray keypress opens a
	# PROCESS_MODE_ALWAYS panel invisibly behind the video, and it is sitting over
	# a running world the moment `_dismiss()` releases the pause.
	if not js.contains("e.stopPropagation()"):
		_fail("_create_js() no longer swallows keys — the game is still listening " \
			+ "behind the film")
	# ...but ONLY the release of a press it swallowed. PLAY SOLO's own shortcut is
	# SPACE, so that keydown reached Godot before the listeners existed; eating its
	# keyup latches `jump` down and the first jump after the film is swallowed too.
	if not js.contains("if (!s.seen[k]) { return; }"):
		_fail("_create_js() swallows keyups it never saw the keydown for — the " \
			+ "SPACE that launched the film would stay latched in Godot")
	# A source that failed during preload must be torn down, not merely declined,
	# or a dead <video> and its buffers outlive the session.
	if not start_js.contains("if (s.failed) { s.finish(); return false; }"):
		_fail("_start_js() declines a failed source without tearing it down — the " \
			+ "hidden element leaks for the rest of the session")

	if not js.contains("width:100%;"):
		_fail("_create_js() lost its `width:100%` — the CSS percentages did not " \
			+ "survive formatting and the video will not fill the canvas")

	# iOS Safari yanks playback into its own fullscreen player without this, over
	# the game and out of our control. It is the single most load-bearing attribute
	# in the snippet and the easiest to drop in a refactor.
	if not js.contains("playsinline"):
		_fail("_create_js() no longer sets `playsinline` — iOS Safari will take the " \
			+ "film fullscreen")
	# Buffering while the player reads the menu is the whole reason the element is
	# built at boot rather than on the press.
	if not js.contains("v.preload = 'auto'"):
		_fail("_create_js() no longer sets preload='auto' — the film will not " \
			+ "buffer behind the start card")
	if not js.contains(IntroVideo.VIDEO_URL):
		_fail("_create_js() does not carry VIDEO_URL — the const is no longer the " \
			+ "single place the film's address lives")
	var ending_js: String = IntroVideo._create_js(IntroVideo.GAME_OVER_VIDEO_URL)
	if not ending_js.contains(IntroVideo.GAME_OVER_VIDEO_URL):
		_fail("_create_js( GAME_OVER_VIDEO_URL ) does not carry the ending film URL")
	for marker: String in ["window.__ck_intro_failed", "s.fail = function()"]:
		if not js.contains(marker):
			_fail("_create_js() lost %s — post-start playback failures would " % marker \
				+ "look like an ordinary end and restart into a broken film")
	# "no leftover element over the canvas" is an acceptance criterion.
	if not js.contains("removeChild"):
		_fail("_create_js() never detaches its element — the overlay would survive " \
			+ "the film and sit on top of the running game")
	# ...and it has to detach BY CLASS, because the reported freeze is precisely an
	# element the scratchpad no longer points at: `root.parentNode.removeChild(root)`
	# can only ever free the one root the caller reached through, and `discard()`
	# used to do nothing at all when the scratchpad was null. Both ends of the
	# teardown must sweep, or an orphaned film has no exit at all.
	var sweep: String = "querySelectorAll('.%s')" % IntroVideo.ROOT_CLASS
	if not js.contains("root.className = '%s'" % IntroVideo.ROOT_CLASS):
		_fail("_create_js() no longer stamps ROOT_CLASS on its overlay root — the " \
			+ "sweep below has nothing to find and an orphaned film stays on screen")
	if not js.contains(sweep):
		_fail("_create_js()'s finish() no longer sweeps by class — a root the " \
			+ "scratchpad has stopped pointing at would never be detached")
	if not IntroVideo._sweep_js().contains(sweep):
		_fail("_sweep_js() does not select ROOT_CLASS — the const is no longer the " \
			+ "single place the teardown handle lives")
	# ...and the sweep has to take the WINDOW listeners with it. They are registered
	# on `window`, not on the root, so detaching the element leaves them swallowing
	# every key in the capture phase — the game would come back keyboard-dead, which
	# is worse than the frozen frame the sweep is clearing.
	if not js.contains("root.__ckOff = function()"):
		_fail("_create_js() no longer hangs its listener-removal handle on the root " \
			+ "— an orphan sweep cannot unregister the capture-phase key swallower")
	if not IntroVideo._sweep_js().contains("__ckOff"):
		_fail("_sweep_js() detaches an orphan without calling its `__ckOff` — the " \
			+ "recovered game is left keyboard-dead for the rest of the session")
	# Both of these route into `finish`, and finish is the only thing that ever
	# flips the flag Godot polls. Lose either and a failed load hangs the menu.
	for listener: String in ["'ended'", "'error'"]:
		if not js.contains("addEventListener(%s" % listener):
			_fail("_create_js() has no %s listener — that failure path would never " \
				% listener + "report finished and the game would never start")


## The game-over branch must use the same shared film seam, while a headless
## game (which has no start overlay and is off-web) still exposes today's panel.
## FilmOverlay supplies the browser result so the end/skip callback can be driven
## without pretending a headless process has a DOM.
func _check_game_over_film_path() -> void:
	var overlay := _make_film_overlay()
	var started := overlay.play_film(
		IntroVideo.GAME_OVER_VIDEO_URL, Callable(overlay, "record_ending_callback"))
	if not started:
		_fail("the shared film seam rejected the game-over film in the driven path")
	if overlay.started_urls.size() != 1 or overlay.started_urls[0] != IntroVideo.GAME_OVER_VIDEO_URL:
		_fail("the game-over path did not route its URL through the shared film seam")
	if not paused:
		_fail("the game-over film did not hold the tree paused")
	overlay.film_over = true
	overlay._process(1.0 / 60.0)
	if overlay.ending_callbacks != 1:
		_fail("the ending film did not invoke its restart callback exactly once")
	if overlay.callback_failed:
		_fail("a normally ended ending film was reported as a failure")
	if overlay._intro_playing or not overlay._dismissed or paused:
		_fail("the ending film callback left the shared overlay or pause latched")

	overlay.queue_free()
	paused = false

	# A post-start failure must reach the callback as failure, so Game Over can
	# show its panel instead of restarting into a broken film loop.
	var failed_overlay := _make_film_overlay()
	failed_overlay.film_failed = true
	failed_overlay.play_film(
		IntroVideo.GAME_OVER_VIDEO_URL, Callable(failed_overlay, "record_ending_callback"))
	failed_overlay.film_over = true
	failed_overlay._process(1.0 / 60.0)
	if failed_overlay.ending_callbacks != 1 or not failed_overlay.callback_failed:
		_fail("a post-start film failure was indistinguishable from end/skip")
	failed_overlay.queue_free()
	paused = false

	# Off-web Game Over remains the panel fallback, with no film state or pause.
	var panel := GameOverUI.new()
	root.add_child(panel)
	panel.show_game_over(3, 12, 12, 3, false)
	if not panel.visible:
		_fail("off-web game over did not show the panel fallback")
	if panel._ending_film_playing:
		_fail("off-web game over latched ending-film state")
	# Automatic film completion must use the same cleanup as Play Again, including
	# killing a pending NEW BEST! pulse before it asks the player to restart.
	panel.new_best_tween = panel.create_tween()
	panel._on_ending_film_finished(false)
	if panel.new_best_tween != null:
		_fail("successful ending completion left the NEW BEST! tween alive")
	panel.queue_free()
	paused = false


# ============================================================================
# 2. + 3. THE OVERLAY, DRIVEN FOR REAL
# ============================================================================

## Build the real `start_overlay.gd` in this tree and press PLAY SOLO. Off-web
## this must behave exactly as it did before the film existed: dismissed, pause
## released, no intro state latched.
func _check_play_solo_desktop_path() -> void:
	var overlay: Control = _make_overlay()
	if overlay == null:
		return

	# NEGATIVE CONTROL. Without this, "the tree is unpaused after the press" is
	# also true of an overlay that never took a pause in the first place — which is
	# the far worse bug, since the world would run live behind the menu.
	if not paused:
		_fail("the start overlay did not pause the tree in _ready() — the world " \
			+ "runs behind the menu and the 'unpaused after PLAY SOLO' assertion " \
			+ "below would pass vacuously")

	overlay._on_play_solo_pressed()

	if overlay._intro_playing:
		_fail("PLAY SOLO latched _intro_playing off-web — the film gate leaked " \
			+ "onto the desktop path")
	if not overlay._dismissed:
		_fail("PLAY SOLO did not dismiss the start overlay off-web — the desktop " \
			+ "path is no longer the original one")
	if paused:
		_fail("the tree is still paused after PLAY SOLO — the game never starts")

	overlay.queue_free()
	paused = false


## MULTIPLAYER dismisses too, and it shares `_dismiss()` with PLAY SOLO. The film
## hangs off `_on_play_solo_pressed()` precisely so this button does not get one;
## assert the split, because moving the hook into `_dismiss()` is the obvious
## "simplification" and it is wrong. (The film's TEARDOWN lives in `_dismiss()`
## and belongs there — that is the opposite direction and the whole of check 5:
## every exit must leave the element gone. It is only the STARTING of the film
## that must not be shared.)
func _check_multiplayer_never_plays() -> void:
	var overlay := _make_film_overlay()

	overlay._on_multiplayer_pressed()

	if overlay._intro_playing:
		_fail("MULTIPLAYER started the intro film — it opens a panel rather than a " \
			+ "game and must never play it")
	if not overlay._dismissed:
		_fail("MULTIPLAYER no longer dismisses the start overlay")
	# It must also THROW THE PRELOADED FILM AWAY: this press opens a panel, so the
	# film is never coming and a still-buffering 20 MB source has no business
	# outliving the press.
	if overlay.teardowns != 1:
		_fail("MULTIPLAYER left the preloaded film's element alive (%d teardowns) " \
			% overlay.teardowns + "— a 20 MB source buffers on into the session")

	overlay.queue_free()
	paused = false


# ============================================================================
# 5. THE WORLD NEVER RUNS BEHIND THE FILM
# ============================================================================

## The bead this check exists for: on desktop web the player watched the intro
## with the game live behind it and was eaten during it. Every candidate cause
## reduces to the same shape — something decided the film was over while its
## element was still on screen, and `_dismiss()` handed back the pause and the
## mouse under a video nobody had taken down.
##
## So the assertion is the invariant, not the cause: while `_intro_playing` is
## latched the tree stays PAUSED however many frames pass, and the one step that
## releases the pause is the same step that dismisses the overlay and tears the
## element down — in that order. A fix that only patched the stall watchdog would
## pass every other check in this file and fail this one.
func _check_world_stays_paused_behind_the_film() -> void:
	var overlay := _make_film_overlay()

	# Enter the web branch by hand. `IntroVideo.start()` cannot be made to answer
	# true off-web (check 1 asserts it must not), and this is exactly the state it
	# would have left behind: film up, card hidden, node still processing.
	overlay._intro_playing = true

	# NEGATIVE CONTROL, as in check 2: without it "still paused during the film"
	# is also true of an overlay that never paused anything.
	if not paused:
		_fail("the start overlay did not pause the tree in _ready() — every " \
			+ "'still paused during the film' assertion below would pass vacuously")

	for frame: int in 3:
		overlay._process(1.0 / 60.0)
		if not paused:
			_fail("the tree unpaused on frame %d with the film still on screen — " \
				% frame + "the world runs, and the crocodile behind the video is " \
				+ "chasing a player who cannot see it (godot-test1-4x4)")
			break
		if overlay._dismissed:
			_fail("the start overlay dismissed itself on frame %d while the film " \
				% frame + "was still playing — it hands back the mouse and the pause")
			break
		if overlay.teardowns != 0:
			_fail("the film's element was torn down on frame %d while it was still " \
				% frame + "playing")
			break

	# The film ends (naturally, by a skip, or by any of the fail-open answers —
	# from here they are indistinguishable, which is the point).
	overlay.film_over = true
	overlay._process(1.0 / 60.0)

	if overlay._intro_playing:
		_fail("the film reported finished and _intro_playing stayed latched — the " \
			+ "overlay would hold the pause forever and the game never starts")
	if not overlay._dismissed:
		_fail("the film finished without dismissing the start overlay")
	if paused:
		_fail("the film finished and the tree is still paused — the game never " \
			+ "starts, which is the one thing the film may never cause")
	if overlay.teardowns != 1:
		_fail("the film finished and its element was torn down %d times — exactly " \
			% overlay.teardowns + "one teardown must happen in the step that unpauses")
	elif not overlay.teardown_saw_paused:
		_fail("the film's element was torn down AFTER the pause was released — for " \
			+ "that window the world was running behind a video still covering the " \
			+ "canvas, which is the bug itself")

	overlay.queue_free()
	paused = false


# ============================================================================
# 6. THE FILM'S END IS WATCHDOG-COVERED FROM BOTH SIDES
# ============================================================================

## The bug this check exists for: the owner's ending film "stopped on the last
## frame" — no restart, no panel, nothing interactive. Every backstop the film had
## lived in ONE browser state machine (`ended`, the rolling `setTimeout`, and
## `finish()` itself), so any way that machine stops is a way `is_finished()`
## answers `false` forever while `_process` politely waits behind a frozen frame.
##
## The fix is a clock OUTSIDE that machine, and this is its acceptance. Two
## subjects, because a backstop that fires on a healthy film is worse than no
## backstop at all:
##
##   * a film whose playback position never moves must be given up on WITHIN the
##     budget, reported as a FAILURE (so Game Over shows its panel rather than
##     treating it as a clean ending), torn down, and the pause released; and
##   * a film whose position keeps advancing must survive far past that same
##     budget untouched — the negative control.
func _check_film_end_is_watchdog_covered() -> void:
	# THE NEGATIVE CONTROL FIRST. A film that is playing normally must not be
	# killed by its own backstop, however long it runs.
	var healthy := _make_film_overlay()
	healthy.play_film(
		IntroVideo.GAME_OVER_VIDEO_URL, Callable(healthy, "record_ending_callback"))
	for step: int in 100:
		healthy.film_progress = float(step)
		healthy._process(1.0)
	if not healthy._intro_playing:
		_fail("the stall backstop tore down a film whose playback was still " \
			+ "advancing — a slow but healthy stream would lose its film")
	if healthy.teardowns != 0 or healthy.ending_callbacks != 0:
		_fail("a progressing film was ended by the stall backstop (%d teardowns, " \
			% healthy.teardowns + "%d callbacks)" % healthy.ending_callbacks)
	healthy.cancel_film()
	healthy.queue_free()
	paused = false

	# THE SUBJECT. `film_over` stays false for the whole run — this is exactly the
	# wedged browser state machine, in which nothing will EVER report finished.
	var wedged := _make_film_overlay()
	wedged.play_film(
		IntroVideo.GAME_OVER_VIDEO_URL, Callable(wedged, "record_ending_callback"))
	wedged.film_progress = 4.0
	if not paused:
		_fail("the film did not pause the tree — every assertion below would pass " \
			+ "vacuously")
	# One second per step, run to twice the budget: comfortably long enough that a
	# missing backstop is a failure and not a rounding question.
	var budget: float = StartOverlay.FILM_STALL_LIMIT_SEC
	for _step: int in int(budget * 2.0) + 2:
		if not wedged._intro_playing:
			break
		wedged._process(1.0)
	if wedged._intro_playing:
		_fail("a film that never reported finished and never advanced was still " \
			+ "playing after %f s — `is_finished()` can stay false with nothing " \
			% (budget * 2.0) + "armed, which is the frozen last frame itself")
		wedged.queue_free()
		paused = false
		return
	if wedged.ending_callbacks != 1:
		_fail("the stall backstop ran the completion callback %d times, not once" \
			% wedged.ending_callbacks)
	if not wedged.callback_failed:
		_fail("a film given up on by the stall backstop was reported as a clean " \
			+ "end — Game Over would treat a dead stream as a finished film")
	if wedged.teardowns != 1:
		_fail("the stall backstop left the film's element up (%d teardowns)" \
			% wedged.teardowns)
	elif not wedged.teardown_saw_paused:
		_fail("the stall backstop released the pause before tearing the element " \
			+ "down — the world runs behind a video still covering the canvas")
	if paused:
		_fail("the stall backstop fired and the tree is still paused — the film " \
			+ "blocked play, which is the one thing it may never do")

	wedged.queue_free()
	paused = false


# ============================================================================
# 7. THE FILM'S END NEVER MINTS A WORLD
# ============================================================================

## The PR #155 regression. `_on_ending_film_finished()` called
## `player.restart_game()` on a clean end, and `restart_game()` calls
## `BestRunStore.new_game()`, which clears the `[world] archived` latch. An
## archived world reopens its ending at boot, so the film played itself through
## and DESTROYED the archive with zero user input — the exact inverse of
## "Continue reopens the ending; only Play Again mints a fresh world".
##
## Driven against a counting stand-in in group `"player"`, because the failure is
## the CALL: with no player in the tree the old code was already silent, and an
## assertion on the archive alone would pass for the wrong reason.
func _check_film_end_never_mints_a_world() -> void:
	var player := RestartSpy.new()
	root.add_child(player)

	var panel := GameOverUI.new()
	root.add_child(panel)

	# Both outcomes, because the whole point is that they now agree: an ended film
	# and a dead stream both hand the player the same interactive surface.
	for failed: bool in [false, true]:
		panel.visible = false
		panel._on_ending_film_finished(failed)
		if not panel.visible:
			_fail("the ending film finished (failed=%s) and left NO interactive " \
				% failed + "surface up — that is the frozen-last-frame report")
		if player.restarts != 0:
			_fail("the ending film finished (failed=%s) and restarted the game by " \
				% failed + "itself — restart_game() reaches BestRunStore.new_game() " \
				+ "and an archived world is destroyed with no user input")
			break

	# ...and the button still does, or Play Again would no longer start anything.
	panel._on_restart_pressed()
	if player.restarts != 1:
		_fail("Play Again ran restart_game() %d times — the button is the ONE " \
			% player.restarts + "route to a fresh world and it has to work")

	panel.queue_free()
	player.queue_free()
	paused = false


## A stand-in for the player, in the `player` group, that counts restarts and does
## nothing else. `game_over_ui` finds the player by group and calls it by name, so
## this is the whole of the seam.
class RestartSpy extends Node:
	var restarts: int = 0

	func _ready() -> void:
		add_to_group("player")

	func restart_game() -> void:
		restarts += 1


## A live `start_overlay.gd` under the tree root, so `_ready()` really runs.
## Returns null (and fails) if the script did not attach — the same cold-clone
## trap `minimap_selfcheck.gd` documents: with an empty global class cache every
## `class_name` type (now including `IntroVideo`) fails to resolve, scripts
## silently do not load, and every assertion above would pass for the worst
## possible reason.
func _make_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_script(StartOverlay)
	root.add_child(overlay)
	if not overlay.has_method("_dismiss"):
		_fail("start_overlay.gd did not attach — run " \
			+ "`godot --headless --path . --import` first to build the global class " \
			+ "cache, or every class_name type fails to resolve and this check " \
			+ "passes vacuously")
		overlay.queue_free()
		return null
	return overlay


## The same overlay with the film's browser calls stubbed — see `FilmOverlay`.
## It needs no attach guard: this is a typed instance of a class that `extends`
## the preloaded script, so if `start_overlay.gd` failed to load (the cold-clone
## trap above) this whole file fails to parse instead of passing vacuously.
func _make_film_overlay() -> FilmOverlay:
	var overlay := FilmOverlay.new()
	root.add_child(overlay)
	return overlay
