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
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const StartOverlay := preload("res://scripts/start_overlay.gd")

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
	_check_play_solo_desktop_path()
	_check_multiplayer_never_plays()
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

	# The tunables the browser half is built from.
	if not IntroVideo.VIDEO_URL.begins_with("https://"):
		_fail("VIDEO_URL must be an https URL (a web build on https cannot load " \
			+ "mixed content), got %s" % IntroVideo.VIDEO_URL)
	if IntroVideo.SKIP_HOLD_SEC <= 0.0:
		_fail("SKIP_HOLD_SEC must be positive, or a stray SPACE tap skips the film")
	if IntroVideo.START_TIMEOUT_SEC <= IntroVideo.SKIP_HOLD_SEC:
		_fail("START_TIMEOUT_SEC (%f) must exceed SKIP_HOLD_SEC (%f) — the hang " \
			% [IntroVideo.START_TIMEOUT_SEC, IntroVideo.SKIP_HOLD_SEC] \
			+ "backstop firing before a deliberate skip can complete is a bug")


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
	if not start_js.contains("s.startTimer = setTimeout(s.finish"):
		_fail("_start_js() no longer arms the start timeout — a stalled stream " \
			+ "would hang the start menu forever")

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
	# "no leftover element over the canvas" is an acceptance criterion.
	if not js.contains("removeChild"):
		_fail("_create_js() never detaches its element — the overlay would survive " \
			+ "the film and sit on top of the running game")
	# Both of these route into `finish`, and finish is the only thing that ever
	# flips the flag Godot polls. Lose either and a failed load hangs the menu.
	for listener: String in ["'ended'", "'error'"]:
		if not js.contains("addEventListener(%s" % listener):
			_fail("_create_js() has no %s listener — that failure path would never " \
				% listener + "report finished and the game would never start")


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
## "simplification" and it is wrong.
func _check_multiplayer_never_plays() -> void:
	var overlay: Control = _make_overlay()
	if overlay == null:
		return

	overlay._on_multiplayer_pressed()

	if overlay._intro_playing:
		_fail("MULTIPLAYER started the intro film — it opens a panel rather than a " \
			+ "game and must never play it")
	if not overlay._dismissed:
		_fail("MULTIPLAYER no longer dismisses the start overlay")

	overlay.queue_free()
	paused = false


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
