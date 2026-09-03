extends SceneTree
## ============================================================================
## BUILD VERSION WATCH SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/build_version_selfcheck.gd
##
## WHAT THIS CAN AND CANNOT GUARD, stated up front:
##
## The half that lives in the browser — that `HTTPRequest` really reaches
## `version.json`, that `location.reload()` really replaces the page, that nginx
## really answers the poll with a fresh body — is browser behaviour, and a
## headless Godot has no DOM, no network and no `JavaScriptBridge`. It is not
## verifiable here and is not claimed to be.
##
## ponytail: the fetch/reload pair is verified by hand on a real deploy (open the
## tab, push a commit, watch it reload at the game-over screen). A headless HTTP
## harness would exercise Godot's own `HTTPRequest`, not our logic.
##
## WHAT IS CHECKABLE IS EVERY DECISION, and that is what is here:
##
##  1. **The bake contract.** `BUILD_SHA` in the repository must still be the
##     placeholder, and its line must still match the pattern CI's `sed` anchors
##     on. A real SHA committed by hand would make every developer's build claim
##     to be that build; a renamed const would make CI's rewrite a silent no-op,
##     and a no-op bake produces a client that fetches the current marker, agrees
##     with it and never reloads — the exact failure this feature exists to catch.
##     (Run this on a clean checkout. Inside a CI job that has already run its bake
##     step the const is a real SHA and this one check reports it — correctly.)
##
##  2. **The web gate.** Off-web the node must build nothing and process nothing,
##     without ever touching `JavaScriptBridge` — the desktop-safety shape
##     `MobileSensors` and `IntroVideo` carry.
##
##  3. **The latch.** Only a well-formed marker naming a DIFFERENT build latches
##     it. Garbage, a 404, a transport failure, an object with no `sha`, and the
##     matching SHA itself all leave it exactly as they found it.
##
##  4. **NEVER MID-RUN.** A latched update must sit there for as many frames as it
##     takes. Reloading mid-run destroys the player's distance, coins and rescues,
##     which is strictly worse than one more session on an old build — so this is
##     the assertion the whole feature is worth having.
##
##  5. **THE SAFE POINT HAS TO HOLD, NOT MERELY OCCUR.** The game-over screen
##     appears in the physics step and `_process` runs in the idle step of the same
##     engine iteration, so a visibility-only test reloads the page on the frame
##     the player dies: no distance, no coin tally, no "NEW BEST!", and the `/best`
##     POST fired microseconds earlier torn out mid-flight. `SAFE_DWELL_SEC` is
##     what fixes that, and one frame at a safe point must NOT be enough.
##
##  6. **BUT IT MUST ACTUALLY FIRE**, at both safe points, exactly once — with a
##     negative control, because "no reload mid-run" is also true of a node that
##     can never reload at all.
##
##  7. **A room outranks both safe points**, and the test is `is_busy()`, not
##     `is_online()`: a join sits in CONNECTING for seconds before a room exists,
##     and joining from the game-over screen is a supported flow, so the narrower
##     test left exactly that press open to a reload that abandons it.
##
##  8. **An empty world is not a safe world.** With no `mp`, no `start_overlay` and
##     no `game_over_ui` in their groups — a scene run standalone — every lookup
##     degrades to "not safe", never to "reload now".
##
## `location.reload()` is unreachable headlessly, so `Watch` below overrides the
## one-line `_reload_now()` seam and counts calls — the same trick
## `intro_selfcheck.gd`'s `FilmOverlay` plays on the film's browser calls.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const BuildVersion := preload("res://scripts/build_version.gd")
const SCRIPT_PATH: String = "res://scripts/build_version.gd"

## Comfortably past `SAFE_DWELL_SEC`, so "drove it long enough" is never the
## reason a check fails.
const LONG_ENOUGH: float = BuildVersion.SAFE_DWELL_SEC + 1.0


## The real watch with its single browser call stubbed out, so every decision
## above it can be driven on a build that has no DOM.
class Watch extends BuildVersion:
	var reloads: int = 0

	func _reload_now() -> void:
		reloads += 1


## Stand-in for `mp_manager.gd`, in the `mp` group. Only `is_busy()` is reached —
## and `is_online()` is here too, deliberately, so a watch that regressed to the
## narrower test would still find a method and still pass its other checks while
## failing the CONNECTING one.
class FakeMp extends Node:
	var state: String = "offline"

	func is_online() -> bool:
		return state == "in_room"

	func is_busy() -> bool:
		return state != "offline"


## Stand-in for `start_overlay.gd`, in the `start_overlay` group. Only
## `is_showing()` is reached.
class FakeStartOverlay extends Node:
	var showing: bool = true

	func is_showing() -> bool:
		return showing


var _failures: Array[String] = []

# The world the watch looks at, rebuilt fresh for each scenario.
var _watch: Watch = null
var _mp: FakeMp = null
var _start: FakeStartOverlay = null
var _game_over: Control = null


## `_initialize()` runs before the root window is live, so a node added there is
## parented but never gets `_ready()`. Same one-frame wait `intro_selfcheck.gd`
## and `minimap_selfcheck.gd` open with; `_initialize()` cannot await, so the body
## is its own coroutine.
## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_check_bake_contract()
	_check_web_gate()
	_check_latch()
	_check_never_mid_run()
	_check_the_safe_point_has_to_hold()
	_check_fires_at_the_start_card()
	_check_fires_at_game_over()
	_check_room_outranks_the_safe_points()
	_check_an_empty_world_is_not_safe()
	_finish()


func _finish() -> void:
	_teardown()
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE BAKE CONTRACT
# ============================================================================

## CI rewrites one line of `build_version.gd` before the export and greps to prove
## it landed. Both ends of that deal are asserted here: the value the repository
## carries, and the shape of the line the `sed` is anchored on.
func _check_bake_contract() -> void:
	if BuildVersion.BUILD_SHA != BuildVersion.UNVERSIONED_SHA:
		_fail("BUILD_SHA is %s, not the %s placeholder — a real SHA committed by " \
			% [BuildVersion.BUILD_SHA, BuildVersion.UNVERSIONED_SHA] \
			+ "hand makes every local and editor build claim to be that build")

	var source: String = FileAccess.get_file_as_string(SCRIPT_PATH)
	if source.is_empty():
		_fail("could not read %s to check the line CI rewrites" % SCRIPT_PATH)
		Sentinel.done("bake_contract")
		return
	# The exact anchor `.github/workflows/build.yml` seds on. Reshape this line and
	# the bake becomes a silent no-op: the client then fetches the current marker,
	# agrees with it, and never reloads anybody.
	var baked := RegEx.create_from_string("(?m)^const BUILD_SHA: String = \"[^\"]*\"$")
	if baked.search(source) == null:
		_fail("no `const BUILD_SHA: String = \"...\"` line at the start of a line in " \
			+ "%s — the CI bake step's sed would silently match nothing and " % SCRIPT_PATH \
			+ "the exported build would carry the placeholder forever")

	# Silence is part of the contract and cannot be asserted from the outside: the
	# static one-shot JSON helper pushes an engine ERROR of its own on malformed
	# input, so a proxy serving an HTML error page would print one to the player's
	# console every single poll. The instance parser returns the failure instead.
	# Matched WITH its opening paren so that describing the rule in a comment — as
	# this file and that one both do — is not itself a violation.
	if source.contains("JSON.parse_string("):
		_fail("build_version.gd calls the static JSON parser — it pushes an engine " \
			+ "ERROR on every unparseable body, so one broken proxy spams the " \
			+ "console for as long as the tab is open. Use JSON.new().parse().")
	Sentinel.done("bake_contract")


# ============================================================================
# 2. THE WEB GATE
# ============================================================================

## Off-web the node must be completely inert: no `JavaScriptBridge` (which would
## error on desktop), no `HTTPRequest`, no `Timer`, no per-frame processing.
func _check_web_gate() -> void:
	if OS.has_feature("web"):
		# Nothing this check can say — Godot cannot run headless as a web export,
		# so in practice this branch is unreachable.
		Sentinel.done("web_gate")
		return

	var watch := Watch.new()
	root.add_child(watch)

	if watch._watch_enabled():
		_fail("_watch_enabled() answered true off-web — a desktop build would " \
			+ "reach JavaScriptBridge and error")
	if watch.is_processing():
		_fail("the watch is still processing off-web — it must be a total no-op " \
			+ "outside the browser")
	if watch._http != null:
		_fail("the watch built an HTTPRequest off-web")
	if not watch._base_url.is_empty():
		_fail("the watch resolved a base url off-web (%s) — that can only have " \
			% watch._base_url + "come from JavaScriptBridge")
	for child: Node in watch.get_children():
		_fail("the watch parented a %s off-web — nothing may be built there" \
			% child.get_class())
	if not watch.is_in_group("build_version"):
		_fail("the watch is not in the `build_version` group — group discovery is " \
			+ "this project's only wiring")
	if watch.process_mode != Node.PROCESS_MODE_ALWAYS:
		_fail("the watch is not PROCESS_MODE_ALWAYS — both safe points can be " \
			+ "reached with the tree paused, so it would never act on either")

	# The poll must survive being driven with nothing built, because that is
	# exactly the state a desktop build leaves it in.
	watch._poll()

	watch.free()
	Sentinel.done("web_gate")


# ============================================================================
# 3. THE LATCH
# ============================================================================

## Only a well-formed marker naming a different build may latch. Every other
## answer the network can produce is "no answer".
func _check_latch() -> void:
	var other: String = "0000000000000000000000000000000000000000"

	# Nothing that is not a marker for a different build may latch.
	var quiet: Array[Array] = [
		["an empty body", ""],
		["a truncated body", "{\"sha\": \"abc"],
		["a proxy error page", "<html><body>502</body></html>"],
		["a JSON array", "[\"%s\"]" % other],
		["a bare JSON string", "\"%s\"" % other],
		["an object with no sha", "{\"build\": \"%s\"}" % other],
		["a non-string sha", "{\"sha\": 17}"],
		["a null sha", "{\"sha\": null}"],
		["an empty sha", "{\"sha\": \"\"}"],
		["the SAME sha", "{\"sha\": \"%s\"}" % BuildVersion.BUILD_SHA],
	]
	for case: Array in quiet:
		var watch := _fresh_watch()
		watch.note_version_body(case[1] as String)
		if watch._pending:
			_fail("%s latched an update — every unusable answer must be silent, " \
				% case[0] + "or a flaky proxy reloads the whole player base")
		_teardown()

	# ...and a marker naming a different build must.
	var latching := _fresh_watch()
	latching.note_version_body("{\"sha\": \"%s\"}" % other)
	if not latching._pending:
		_fail("a marker naming a different build did NOT latch — the feature does " \
			+ "nothing at all")
	# It stays latched even if the marker later agrees again (a rollback, or a
	# stale CDN copy served on the next tick). The reload is already owed.
	latching.note_version_body("{\"sha\": \"%s\"}" % BuildVersion.BUILD_SHA)
	if not latching._pending:
		_fail("a later agreeing marker un-latched a reload that was already owed")
	_teardown()

	# The transport gate above `note_version_body()`: a good body behind a failed
	# request or a non-200 must change nothing.
	var body := ("{\"sha\": \"%s\"}" % other).to_utf8_buffer()
	var refused: Array[Array] = [
		["a failed transport", HTTPRequest.RESULT_CANT_CONNECT, 200],
		["a 404", HTTPRequest.RESULT_SUCCESS, 404],
		["a 500", HTTPRequest.RESULT_SUCCESS, 500],
	]
	for case: Array in refused:
		var watch := _fresh_watch()
		watch._on_request_completed(
			case[1] as int, case[2] as int, PackedStringArray(), body)
		if watch._pending:
			_fail("%s latched an update — only a 200 that parsed may" % case[0])
		_teardown()
	Sentinel.done("latch")


# ============================================================================
# 4. NEVER MID-RUN
# ============================================================================

## The assertion the feature is worth having. A run is in progress: the start card
## is gone and the game-over screen is not up. A pending update must sit there.
func _check_never_mid_run() -> void:
	var watch := _fresh_watch()
	_start.showing = false
	_game_over.visible = false
	watch._pending = true

	_drive(watch, LONG_ENOUGH * 3.0)

	if watch.reloads != 0:
		_fail("the tab reloaded in the middle of a run (%d times) — the player's " \
			% watch.reloads + "distance, coins and rescues are gone, which is worse " \
			+ "than running an old build")
	if not watch._pending:
		_fail("the pending update was dropped mid-run instead of being held — the " \
			+ "player would stay on the old build until they reload by hand")
	_teardown()
	Sentinel.done("never_mid_run")


# ============================================================================
# 5. THE SAFE POINT HAS TO HOLD
# ============================================================================

## The game-over screen becomes visible in the physics step and `_process` runs in
## the idle step of the SAME engine iteration. Without a dwell the player dies and
## the page reloads before a single frame of their final score is drawn — and the
## `/best` POST `best_run_store` fires on that same death never completes.
func _check_the_safe_point_has_to_hold() -> void:
	for screen: String in ["the start card", "the game-over screen"]:
		var watch := _fresh_watch()
		_start.showing = screen == "the start card"
		_game_over.visible = screen != "the start card"
		watch._pending = true

		# One frame — the frame the screen appeared on.
		watch._process(1.0 / 60.0)
		if watch.reloads != 0:
			_fail("the tab reloaded on the FIRST frame of %s — the player never " \
				% screen + "sees the screen, and anything still settling behind it " \
				+ "(the /best POST) is torn out mid-flight")

		# Most of the dwell, but not all of it.
		_drive(watch, BuildVersion.SAFE_DWELL_SEC * 0.5)
		if watch.reloads != 0:
			_fail("the tab reloaded on %s before SAFE_DWELL_SEC had elapsed" % screen)

		# The moment must also be spendable — otherwise this check passes for a
		# dwell so long nothing ever reloads. (Check 6 asserts the count; this is
		# only the ordering.)
		_drive(watch, LONG_ENOUGH)
		if watch.reloads == 0:
			_fail("the dwell on %s never expired — the reload is owed forever and " \
				% screen + "the feature does nothing")
		_teardown()
	Sentinel.done("the_safe_point_has_to_hold")


# ============================================================================
# 6. IT MUST ACTUALLY FIRE
# ============================================================================

## Pre-run safe point: the start card still owns the screen, so there is nothing
## in memory for a reload to destroy.
func _check_fires_at_the_start_card() -> void:
	var watch := _fresh_watch()
	_start.showing = true
	_game_over.visible = false

	# NEGATIVE CONTROL. Without it, "no reload mid-run" above is equally true of a
	# node whose reload path is broken outright.
	_drive(watch, LONG_ENOUGH)
	if watch.reloads != 0:
		_fail("the tab reloaded on the start card with NO update pending — the " \
			+ "latch is not gating anything")

	watch._pending = true
	_drive(watch, LONG_ENOUGH)
	if watch.reloads != 1:
		_fail("a pending update at the start card produced %d reloads, expected 1" \
			% watch.reloads)
	if watch._pending:
		_fail("the latch survived the reload — `location.reload()` returns at once " \
			+ "and several more frames run, so each of them would fire again")

	# Those following frames, for real.
	_drive(watch, LONG_ENOUGH * 2.0)
	if watch.reloads != 1:
		_fail("the watch fired %d times over the frames after the reload — a " \
			% watch.reloads + "reload storm, not a reload")
	_teardown()
	Sentinel.done("fires_at_the_start_card")


## Post-run safe point: the game-over screen is up, so the run is already spent.
func _check_fires_at_game_over() -> void:
	var watch := _fresh_watch()
	_start.showing = false
	_game_over.visible = true
	watch._pending = true

	_drive(watch, LONG_ENOUGH)
	if watch.reloads != 1:
		_fail("a pending update at the game-over screen produced %d reloads, " \
			% watch.reloads + "expected 1 — the post-run safe point does not work")
	_teardown()
	Sentinel.done("fires_at_game_over")


# ============================================================================
# 7. A ROOM OUTRANKS BOTH SAFE POINTS
# ============================================================================

## Reloading drops this peer out of the mesh mid-session, which costs the other
## players their teammate. So an open room is unsafe even on the two screens that
## are otherwise the safest moments there are — and so is a join still CONNECTING,
## which `is_online()` alone does not see.
func _check_room_outranks_the_safe_points() -> void:
	for screen: String in ["the start card", "the game-over screen"]:
		for state: String in ["connecting", "in_room"]:
			var watch := _fresh_watch()
			_mp.state = state
			_start.showing = screen == "the start card"
			_game_over.visible = screen != "the start card"
			watch._pending = true

			_drive(watch, LONG_ENOUGH * 2.0)
			if watch.reloads != 0:
				_fail("the tab reloaded on %s while multiplayer was %s — " \
					% [screen, state] \
					+ ("the peer drops out of the mesh and its teammates lose it" \
						if state == "in_room" \
						else "the join is abandoned in flight and the button just " \
							+ "appears to do nothing (is_online() does not see " \
							+ "CONNECTING; is_busy() does)"))
			if not watch._pending:
				_fail("the pending update was dropped instead of held while %s" % state)

			# Leaving is what makes it safe, and it must then fire.
			_mp.state = "offline"
			_drive(watch, LONG_ENOUGH)
			if watch.reloads != 1:
				_fail("leaving the room on %s (from %s) did not release the held " \
					% [screen, state] + "reload (%d)" % watch.reloads)
			_teardown()
	Sentinel.done("room_outranks_the_safe_points")


# ============================================================================
# 8. AN EMPTY WORLD IS NOT A SAFE WORLD
# ============================================================================

## The documented degrade: with none of the three nodes present — a scene run
## standalone, or this node dropped into a bare tree — every lookup must fall
## through to "not safe". Falling through to "safe" would reload a live game.
func _check_an_empty_world_is_not_safe() -> void:
	_teardown()
	var watch := Watch.new()
	root.add_child(watch)
	watch._pending = true

	_drive(watch, LONG_ENOUGH * 2.0)

	if watch.reloads != 0:
		_fail("the tab reloaded with no mp / start_overlay / game_over_ui in the " \
			+ "tree — a missing node must read as `not safe`, never as `reload now`")
	watch.free()
	Sentinel.done("an_empty_world_is_not_safe")


# ============================================================================
# THE FAKE WORLD
# ============================================================================

## Run `_process` for `seconds` of game time, in 60 Hz steps. The watch is
## `set_process(false)` off-web (check 2 asserts it), so every scenario drives it
## by hand — the same way `intro_selfcheck.gd` drives the start overlay.
func _drive(watch: Watch, seconds: float) -> void:
	var step: float = 1.0 / 60.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		watch._process(step)
		elapsed += step


## A live watch plus the three group-discovered nodes it reads, all under the tree
## root so `_ready()` really runs. Fakes rather than the real scripts: the watch's
## contract with each of them is one method or one property, and standing up
## `mp_manager.gd` (a socket) or the real start overlay (which takes the tree's
## pause) to answer a single bool would test those files, not this one.
func _fresh_watch() -> Watch:
	_teardown()

	_mp = FakeMp.new()
	_mp.add_to_group("mp")
	root.add_child(_mp)

	_start = FakeStartOverlay.new()
	_start.add_to_group("start_overlay")
	root.add_child(_start)

	_game_over = Control.new()
	_game_over.add_to_group("game_over_ui")
	root.add_child(_game_over)

	_watch = Watch.new()
	root.add_child(_watch)
	return _watch


## Free the fake world immediately — `queue_free()` would leave the nodes in their
## groups until the end of the frame, and every scenario builds a new set inside
## the same frame.
func _teardown() -> void:
	for node: Node in [_watch, _mp, _start, _game_over]:
		if node != null:
			node.free()
	_watch = null
	_mp = null
	_start = null
	_game_over = null
