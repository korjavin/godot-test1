extends SceneTree
## ============================================================================
## CAMERA VIEW CYCLE SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/view_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: `player_controller._apply_view_mode()` places the camera by
## handing the SpringArm3D a basis, and the arm then slides the camera along its
## own +Z. Nothing about that fails loudly — a sign error puts the "front" camera
## BEHIND the hero (i.e. an ordinary third-person view with a mirrored pitch) and
## the only symptom is that the feature quietly does not exist. On a headless
## machine there is no picture to eyeball, so the placement is MEASURED: where
## the camera ends up relative to the body, which way it looks, and whether the
## model is visible — the three things each view is defined by.
##
## The mouse-wheel zoom is measured here too, for the same reason: it is a factor
## folded into `_third_person_arm_target()`, so the only proof that it reaches the
## picture is the arm's own `spring_length` arriving at the zoomed length. The
## clamp and the three refusals (free cursor, paused tree, first person) are all
## silent failures otherwise — a missing clamp puts the camera in orbit and a
## missing guard zooms a frozen game.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## How far off-axis a measurement may sit before we call it wrong. The boom is
## 8.25 m long, so metre-scale slop is still unambiguous about which SIDE of the
## body the camera is on.
const EPS: float = 0.05

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# `_initialize()` cannot await, so the measuring half runs as its own coroutine
	# and reports from in there — the tree keeps processing until it calls quit().
	# Reporting HERE would print a verdict at frame 0, before a single check ran
	# (and before the arm has ever ticked): a vacuous pass, the exact failure the
	# sibling selfchecks in this repo document.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("run")
		_report()
		Sentinel.done("run")
		return
	var player: Node3D = packed.instantiate()
	root.add_child(player)
	# A node added from _initialize() gets its _ready() DEFERRED, and the spring
	# arm only repositions its children on its own physics tick — so nothing is
	# measurable until a couple of physics frames have actually run.
	await physics_frame
	await physics_frame

	if not player.has_method("_apply_view_mode"):
		_fail("player has no _apply_view_mode() — did the script fail to attach? "
				+ "(a fresh clone needs `godot --headless --path . --import` first)")
		Sentinel.done("run")
		_report()
		Sentinel.done("run")
		return

	var camera: Camera3D = player.get_node_or_null("CameraPivot/CameraArm/Camera3D")
	var model: Node3D = player.get_node_or_null("CharacterModel")
	if camera == null or model == null:
		_fail("camera rig or CharacterModel missing from %s" % PLAYER_SCENE)
		Sentinel.done("run")
		_report()
		Sentinel.done("run")
		return

	# BUDAPEST Z-FIGHTING FIX (bead 8gw.17): the default near=0.05 / far=4000 gives an
	# 80,000:1 ratio and 0.06 m CITY_WINDOW_PROUD flickers on gl_compatibility.
	# 0.2 buys 4x depth precision (0.25 would be 5x) for zero draw cost; 0.25 looked
	# safe from the SpringArm3D 8.25 m + 0.25 margin, but first-person bypasses the
	# arm (spring_length = 0, camera on body's axis), so the nearest geometry is
	# one capsule radius away — 0.5 m normally, 0.225 m for small Teibi (0.5 * 0.45).
	# Far stays 4000 — the HQ horizon impostor is fog-exempt and must remain.
	if not is_equal_approx(camera.near, 0.2):
		_fail("Camera3D.near is %.4f, expected 0.2 — Budapest 0.06 m proud bands z-fight at the default 0.05 (bead 8gw.17)" % camera.near)
	if not is_equal_approx(camera.far, 4000.0):
		_fail("Camera3D.far is %.1f, expected 4000 — lowering it pops the fog-exempt HQ horizon impostor" % camera.far)
	# Derived ceiling so a future raise knows the bound without rediscovering the alcove:
	# capsule radius (scenes/player.tscn CapsuleShape3D default 0.5 m) * TEIBI_SCALE_SMALL.
	var base_radius: float = 0.5
	# Read the constant from the player script rather than restating 0.45.
	var teibi_small: float = float(player.get_script().get_script_constant_map().get("TEIBI_SCALE_SMALL", 0.45))
	if teibi_small == 0.0:
		teibi_small = 0.45
	var small_radius: float = base_radius * teibi_small
	if camera.near >= small_radius - 0.001:
		_fail("Camera3D.near %.4f must be < small-Teibi capsule radius %.4f (0.5 * TEIBI_SCALE_SMALL %.2f) — first-person would clip walls in the 1.2 m alcove" % [camera.near, small_radius, teibi_small])

	# Three views, three measurements. `forward` is the body's facing (-Z, the
	# Godot convention this controller moves along); `ahead` is how far along it
	# the camera sits, signed — negative is behind the hero, positive in front.
	await _check_view(player, camera, model, player.ViewMode.THIRD_PERSON,
			"third-person", -1.0, true)
	await _check_view(player, camera, model, player.ViewMode.FIRST_PERSON,
			"first-person", 0.0, false)
	await _check_view(player, camera, model, player.ViewMode.FRONT,
			"front", 1.0, true)

	# The cycle itself: C must land on each view once and come back round.
	var seen: Array[int] = []
	player.view_mode = player.ViewMode.THIRD_PERSON
	for i in 4:
		seen.append(player.view_mode)
		player.view_mode = (player.view_mode + 1) % player.ViewMode.size()
	var expected: Array[int] = [
		player.ViewMode.THIRD_PERSON,
		player.ViewMode.FIRST_PERSON,
		player.ViewMode.FRONT,
		player.ViewMode.THIRD_PERSON,
	]
	if seen != expected:
		_fail("view cycle is %s, expected %s" % [seen, expected])

	await _check_zoom(player, player.get_node_or_null("CameraPivot/CameraArm"))

	player.queue_free()
	Sentinel.done("run")
	_report()


func _check_view(player: Node3D, camera: Camera3D, model: Node3D, mode: int,
		label: String, want_ahead_sign: float, want_model_visible: bool) -> void:
	"""
	Put the player in one view, let the spring arm settle, and measure it.

	@param want_ahead_sign: +1 camera must sit in FRONT of the body, -1 behind,
	                        0 essentially on it (first-person).
	@param want_model_visible: whether $CharacterModel must be on screen.
	"""
	player.view_mode = mode
	player._apply_view_mode()
	await physics_frame
	await physics_frame

	var forward: Vector3 = -player.global_transform.basis.z
	var to_camera: Vector3 = camera.global_position - player.global_position
	var ahead: float = to_camera.dot(forward)

	if want_ahead_sign > 0.0 and ahead <= EPS:
		_fail("%s view: camera is %.2f m along the facing axis — it must be IN FRONT "
				% [label, ahead] + "of the hero (a flipped boom basis is the usual cause)")
	elif want_ahead_sign < 0.0 and ahead >= -EPS:
		_fail("%s view: camera is %.2f m along the facing axis — it must be BEHIND the hero"
				% [label, ahead])
	elif want_ahead_sign == 0.0 and absf(ahead) > 1.0:
		_fail("%s view: camera is %.2f m off the body along its facing axis — first-person "
				% [label, ahead] + "must sit at the eyes")

	# A camera in front is only useful if it looks BACK: its own -Z must point at
	# the hero. (In third-person that same test passes trivially, so it is worth
	# asserting for every view — it is what "you can see your own face" means.)
	var look: Vector3 = -camera.global_transform.basis.z
	if want_ahead_sign != 0.0 and look.dot(-to_camera.normalized()) <= 0.0:
		_fail("%s view: camera does not look toward the hero" % label)

	if model.visible != want_model_visible:
		_fail("%s view: CharacterModel.visible is %s, expected %s"
				% [label, model.visible, want_model_visible])
	Sentinel.done("view")


## The closest INDOOR boom the wheel may ask for, in metres (bead
## godot-test1-hwwv). INDOOR_ARM_LENGTH × CAMERA_ZOOM_MIN = 3.85 × 0.25 = 0.96 m
## must stay above this, or the camera sits inside the hero's head: measured
## with a headless probe at 0.25 (arm arrives at 0.9625 m; camera to
## Phoboman's Head-node centre 1.16 m; Teibi/Windman geometry ≈ 0.94 m to head
## centre, worst-case giant-Teibi clearance ≈ 0.65 m) against Camera3D.near 0.2
## — so 0.5 keeps more than twice the near plane of room even in the worst
## case, and a future MIN below ~0.13 fails loudly here instead of clipping.
const INDOOR_CLOSE_MIN_M: float = 0.5


func _check_zoom(player: Node3D, arm: SpringArm3D) -> void:
	"""
	The mouse-wheel zoom: the clamp, the multiplicative notch, the arm actually
	arriving at the zoomed length, the closest indoor zoom staying out of the
	hero's head, and the three states where a wheel notch must do nothing.

	The arm is read rather than the target, on purpose — `_third_person_arm_target()`
	returning the right number proves nothing if the ease path never runs.
	"""
	if arm == null:
		_fail("CameraPivot/CameraArm missing — cannot measure the wheel zoom")
		Sentinel.done("zoom")
		return
	var consts: Dictionary = player.get_script().get_script_constant_map()
	var zoom_min: float = float(consts.get("CAMERA_ZOOM_MIN", 0.5))
	var zoom_max: float = float(consts.get("CAMERA_ZOOM_MAX", 2.0))
	var zoom_step: float = float(consts.get("CAMERA_ZOOM_STEP", 0.15))

	player.view_mode = player.ViewMode.THIRD_PERSON
	player._apply_view_mode()
	await physics_frame
	var base_length: float = arm.spring_length

	# THE NOTCH IS MULTIPLICATIVE (bead godot-test1-hwwv): two notches out from
	# 1.0 land on (1 + step)^2. An additive notch would give 1 + 2 * step
	# instead — same first notch, different second — so this is the assertion
	# that tells the two models apart.
	player.camera_zoom = 1.0
	player.zoom_camera(zoom_step)
	player.zoom_camera(zoom_step)
	var two_notches: float = (1.0 + zoom_step) * (1.0 + zoom_step)
	if not is_equal_approx(player.camera_zoom, two_notches):
		_fail("two wheel notches out left camera_zoom at %.4f, expected (1 + step)^2 = %.4f — "
				% [player.camera_zoom, two_notches] + "the notch is not multiplicative")
	# OUT to the stop. 1.15^10 ≈ 4.05 crosses from 1.0 to MAX, so 20 notches is
	# twice what the trip needs — anything but CAMERA_ZOOM_MAX here means the
	# clamp is gone.
	player.camera_zoom = 1.0
	for i in 20:
		player.zoom_camera(zoom_step)
	if not is_equal_approx(player.camera_zoom, zoom_max):
		_fail("20 wheel notches out left camera_zoom at %.3f, expected the CAMERA_ZOOM_MAX clamp %.3f"
				% [player.camera_zoom, zoom_max])
	# `_tick_arm_length()` walks there at ARM_EASE_SPEED; the widened range
	# lengthened the trip (8.25 to 33 m is 25 m at 18 m/s ≈ 83 frames), so 120
	# physics frames is two seconds — far more than the trip needs.
	for i in 120:
		await physics_frame
	if not is_equal_approx(arm.spring_length, base_length * zoom_max):
		_fail("boom settled at %.3f m after zooming out, expected %.3f m (%.2f m * %.2f) — "
				% [arm.spring_length, base_length * zoom_max, base_length, zoom_max]
				+ "the zoom factor is not reaching _third_person_arm_target()")

	# IN to the other stop, from the far end: 1.15^20 ≈ 16.4 covers the whole 16x
	# range, so 40 notches is twice that — anything but CAMERA_ZOOM_MIN here
	# means the clamp is gone.
	for i in 40:
		player.zoom_camera(-zoom_step)
	if not is_equal_approx(player.camera_zoom, zoom_min):
		_fail("40 wheel notches in left camera_zoom at %.3f, expected the CAMERA_ZOOM_MIN clamp %.3f"
				% [player.camera_zoom, zoom_min])
	# Same arithmetic down: 33 to 2 m is 31 m at 18 m/s ≈ 104 frames, so 150.
	for i in 150:
		await physics_frame
	if not is_equal_approx(arm.spring_length, base_length * zoom_min):
		_fail("boom settled at %.3f m after zooming in, expected %.3f m (%.2f m * %.2f)"
				% [arm.spring_length, base_length * zoom_min, base_length, zoom_min])

	# THE CLOSEST INDOOR ZOOM stays out of the hero's head (bead
	# godot-test1-hwwv). Driven through the shipped path — indoor boom, real
	# notches to the MIN stop, the real ease — and the arm is read, not the
	# target. Then the arrived length must clear INDOOR_CLOSE_MIN_M, which is
	# what stops a future MIN from putting the camera inside the head. Runs
	# here, right after the outdoor MIN arrival while the view is still
	# third-person (control (c) below commandeers the arm for first-person),
	# so the ease trip is 1.1 m and 60 frames is plenty.
	player.set_indoor_camera(true)
	for i in 40:
		player.zoom_camera(-zoom_step)
	for i in 60:
		await physics_frame
	var indoor_arm: float = float(consts.get("INDOOR_ARM_LENGTH", 3.85))
	if not is_equal_approx(player.camera_zoom, zoom_min):
		_fail("40 wheel notches in left indoor camera_zoom at %.3f, expected the MIN clamp %.3f"
				% [player.camera_zoom, zoom_min])
	if not is_equal_approx(arm.spring_length, indoor_arm * zoom_min):
		_fail("indoor boom settled at %.3f m after zooming in, expected %.3f m (%.2f m * %.2f)"
				% [arm.spring_length, indoor_arm * zoom_min, indoor_arm, zoom_min])
	if indoor_arm * zoom_min < INDOOR_CLOSE_MIN_M:
		_fail("closest indoor boom %.3f m (%.2f m indoor * %.2f MIN) is under the %.2f m "
				% [indoor_arm * zoom_min, indoor_arm, zoom_min, INDOOR_CLOSE_MIN_M]
				+ "head clearance — the camera would sit inside the hero's head")
	player.set_indoor_camera(false)

	# NEGATIVE CONTROL (a): no captured mouse. Fed as a real event through the
	# shipped `_input()` handler. Headless `Input.mouse_mode` reads VISIBLE whatever
	# `_ready()` asked for (capture_selfcheck documents this), which is exactly the
	# free-cursor case — but assert it, so the control cannot pass for the wrong
	# reason. It can only tell "the MOUSE_MODE_CAPTURED guard is there" from "it was
	# removed", and is blind to the block itself; `_pin_wheel_block()` below covers
	# what it cannot.
	player.camera_zoom = 1.0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_fail("headless mouse_mode is CAPTURED — the free-cursor control below would be vacuous")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	player._input(ev)
	if not is_equal_approx(player.camera_zoom, 1.0):
		_fail("a wheel event with the cursor FREE moved camera_zoom to %.3f — the "
				% player.camera_zoom + "MOUSE_MODE_CAPTURED guard is gone from _input()")

	# NEGATIVE CONTROL (b): a paused tree. Each control re-arms the factor, so a
	# broken guard fails its OWN control instead of cascading into the next one's.
	player.camera_zoom = 1.0
	paused = true
	player.zoom_camera(zoom_step)
	paused = false
	if not is_equal_approx(player.camera_zoom, 1.0):
		_fail("zoom_camera() moved camera_zoom to %.3f while the tree was PAUSED"
				% player.camera_zoom)

	# NEGATIVE CONTROL (c): first person, where there is no boom to zoom.
	player.camera_zoom = 1.0
	player.view_mode = player.ViewMode.FIRST_PERSON
	player._apply_view_mode()
	player.zoom_camera(zoom_step)
	if not is_equal_approx(player.camera_zoom, 1.0):
		_fail("zoom_camera() moved camera_zoom to %.3f in FIRST_PERSON" % player.camera_zoom)
	if not is_equal_approx(arm.spring_length, 0.0):
		_fail("first-person boom is %.3f m, expected 0 — the zoom must not reach the commandeered arm"
				% arm.spring_length)

	# The FRONT view snaps through the same `_apply_view_mode()` line, so it gets
	# the zoom for free. Prove it, and leave the file as we found it.
	player.camera_zoom = zoom_max
	player.view_mode = player.ViewMode.FRONT
	player._apply_view_mode()
	if not is_equal_approx(arm.spring_length, base_length * zoom_max):
		_fail("front view snapped the boom to %.3f m, expected the zoomed %.3f m"
				% [arm.spring_length, base_length * zoom_max])
	# Restore by assignment: 4.0 × 1.15^-k never lands on 1.0 (ln 4 / ln 1.15 is
	# not an integer), so stepping back from the clamp cannot return the
	# shipped framing.
	player.camera_zoom = 1.0
	player.view_mode = player.ViewMode.THIRD_PERSON
	player._apply_view_mode()
	_pin_wheel_block()
	Sentinel.done("zoom")


func _pin_wheel_block() -> void:
	"""
	Pin the wheel half of `_input()` BY SOURCE, the way
	`capture_selfcheck._check_escape_leaves_the_ending_cursor_free()` pins the ESC
	arm and for the same measured reason: headless ignores
	`Input.set_mouse_mode(CAPTURED)`, so an event-fed probe can only ever observe
	the free-cursor branch.

	WITHOUT THIS, EVERY ASSERTION ABOVE PASSES ON A DELETED FEATURE. They all drive
	`zoom_camera()` by hand, and the one event-fed control asserts the zoom did NOT
	move — which is also what a missing wheel block produces. So is a swapped
	UP/DOWN pair (zoom inverted), a dropped `pressed` filter (every notch counted
	twice, once for the press and once for the release), and the same sign on both
	arms. Nothing else in the suite names MOUSE_BUTTON_WHEEL, and help_selfcheck's
	action audit skips the "Wheel" row because it is not an input-map action.

	Not a folded-in part of `_check_zoom`: this reads source and asserts nothing
	about the running player, and mixing the two would hide which one went red.
	"""
	var src: String = FileAccess.get_file_as_string("res://scripts/player_controller.gd")
	if src.is_empty():
		_fail("could not read player_controller.gd to pin the wheel block")
		return
	var anchor := "if wheel != null and wheel.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:"
	var at: int = src.find(anchor)
	if at == -1:
		_fail("the wheel block is gone from player_controller._input() (looked for `%s`)"
				% anchor + " — the wheel does nothing for players and every assertion "
				+ "in _check_zoom still passes, because they all call zoom_camera() by hand")
		return
	# The block is six lines; 400 characters is the same window capture_selfcheck
	# uses on the ESC arm and reaches well past the last `elif` without running
	# into the ESC handler below.
	var block: String = src.substr(at, 400)
	if not block.contains("MOUSE_BUTTON_WHEEL_UP:\n\t\t\tzoom_camera(-CAMERA_ZOOM_STEP)"):
		_fail("wheel UP no longer calls zoom_camera(-CAMERA_ZOOM_STEP) — forward must "
				+ "bring the camera IN, and a swapped pair inverts the zoom silently")
	if not block.contains("MOUSE_BUTTON_WHEEL_DOWN:\n\t\t\tzoom_camera(CAMERA_ZOOM_STEP)"):
		_fail("wheel DOWN no longer calls zoom_camera(CAMERA_ZOOM_STEP) — back must take "
				+ "the camera OUT")
