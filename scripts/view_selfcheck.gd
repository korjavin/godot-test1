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


func _check_zoom(player: Node3D, arm: SpringArm3D) -> void:
	"""
	The mouse-wheel zoom: the clamp, the arm actually arriving at the zoomed
	length, and the three states where a wheel notch must do nothing.

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

	# OUT to the stop. 20 notches is well past the 0.15 * n it takes to cross the
	# range, so anything but CAMERA_ZOOM_MAX here means the clamp is gone.
	for i in 20:
		player.zoom_camera(zoom_step)
	if not is_equal_approx(player.camera_zoom, zoom_max):
		_fail("20 wheel notches out left camera_zoom at %.3f, expected the CAMERA_ZOOM_MAX clamp %.3f"
				% [player.camera_zoom, zoom_max])
	# `_tick_arm_length()` walks there at ARM_EASE_SPEED; 60 physics frames is a
	# full second, far more than the trip needs.
	for i in 60:
		await physics_frame
	if not is_equal_approx(arm.spring_length, base_length * zoom_max):
		_fail("boom settled at %.3f m after zooming out, expected %.3f m (%.2f m * %.2f) — "
				% [arm.spring_length, base_length * zoom_max, base_length, zoom_max]
				+ "the zoom factor is not reaching _third_person_arm_target()")

	# IN to the other stop, from the far end: 40 notches covers the whole range twice.
	for i in 40:
		player.zoom_camera(-zoom_step)
	if not is_equal_approx(player.camera_zoom, zoom_min):
		_fail("40 wheel notches in left camera_zoom at %.3f, expected the CAMERA_ZOOM_MIN clamp %.3f"
				% [player.camera_zoom, zoom_min])
	for i in 60:
		await physics_frame
	if not is_equal_approx(arm.spring_length, base_length * zoom_min):
		_fail("boom settled at %.3f m after zooming in, expected %.3f m (%.2f m * %.2f)"
				% [arm.spring_length, base_length * zoom_min, base_length, zoom_min])

	# NEGATIVE CONTROL (a): no captured mouse. Fed as a real event through the
	# shipped `_input()` handler, so this tests the wheel wiring and not just the
	# seam. Headless `Input.mouse_mode` reads VISIBLE whatever `_ready()` asked for
	# (capture_selfcheck documents this), which is exactly the free-cursor case —
	# but assert it, so the control cannot pass for the wrong reason.
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
	# Restore by assignment: 0.5 + n * 0.15 never lands on 1.0, so stepping back
	# from the clamp cannot return the shipped framing.
	player.camera_zoom = 1.0
	player.view_mode = player.ViewMode.THIRD_PERSON
	player._apply_view_mode()
	Sentinel.done("zoom")
