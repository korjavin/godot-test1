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
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## How far off-axis a measurement may sit before we call it wrong. The boom is
## 8.25 m long, so metre-scale slop is still unambiguous about which SIDE of the
## body the camera is on.
const EPS: float = 0.05

var _failures: Array[String] = []


func _initialize() -> void:
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
		print("SELFCHECK OK")
		quit(0)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		_report()
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
		_report()
		return

	var camera: Camera3D = player.get_node_or_null("CameraPivot/CameraArm/Camera3D")
	var model: Node3D = player.get_node_or_null("CharacterModel")
	if camera == null or model == null:
		_fail("camera rig or CharacterModel missing from %s" % PLAYER_SCENE)
		_report()
		return

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

	player.queue_free()
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
