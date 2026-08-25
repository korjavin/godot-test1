extends SceneTree
## ============================================================================
## RIVER WADING SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/wade_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: wading is three effects that all fail SILENTLY.
##
##   1. The submersion is a VISUAL offset on $CharacterModel and nothing else.
##      Move it to the body or the collision shape instead and the game still
##      runs — it just breaks the flat-world invariant every y-placement site in
##      the project depends on, with no error anywhere. So this measures the
##      model AND asserts the body y and the capsule did NOT move.
##   2. The weaker jump keys off `is_wading`, which is only true while grounded.
##      Read it one step too late in _physics_process and it is the PREVIOUS
##      frame's answer — which is wrong exactly once, on a coyote-time jump off
##      a river bank, i.e. the one case the spec calls out and the one case no
##      amount of playing notices.
##   3. The wade drag must never take the RUN gait under the crocodile chase cap
##      (MAX_CHASE_SPEED), or a river becomes an inescapable trap. That is a
##      cross-file inequality between two constants that nothing else checks.
##
## Every check carries a NEGATIVE CONTROL — a dry-land measurement that must NOT
## show the effect — because "the number changed" is also true of a bug that
## changes it always.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")
## The crocodile's chase-speed cap, read from the file that owns it rather than
## re-typed here — the whole point of check 3 is that the two must stay in step.
const CROC_SCRIPT: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")

## Metre / m-per-second slop. The effects measured here are 0.35 m and ~2.5 m/s,
## so a centimetre of tolerance is still unambiguous.
const EPS: float = 0.01

## Physics frames to run for an ease to finish. The sink eases over ~0.2 s; 30
## frames at 60 Hz is 0.5 s, comfortably past it.
const SETTLE_FRAMES: int = 30

var _failures: Array[String] = []


## A terrain stand-in: the ONE method player_controller and remote_avatar ask
## for, with a switch on it. Using the real endless_terrain would make "is this
## spot a river" a search problem; the contract under test is only that the
## player reacts to the answer.
class StubTerrain:
	extends Node
	var river: bool = false
	func is_river_at(_pos: Vector3) -> bool:
		return river


func _initialize() -> void:
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there. Reporting here would print a verdict at frame 0,
	# before a single physics tick had run — a vacuous pass.
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


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		_report()
		return

	# Something to stand on. The world is flat at y = 0 by invariant, so this box
	# is simply a 60 m slab whose TOP is the ground plane.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	var terrain := StubTerrain.new()
	root.add_child(terrain)
	terrain.add_to_group("terrain")

	var player: CharacterBody3D = packed.instantiate()
	# Placed BEFORE add_child: a node added from _initialize() is not yet
	# is_inside_tree(), and global_position errors out there (the same trap
	# best_run_e2e.gd documents for HTTPRequest).
	player.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(player)

	# A node added from _initialize() gets its _ready() DEFERRED, and the body has
	# to fall onto the slab before is_on_floor() — which gates wading — is true.
	await _frames(SETTLE_FRAMES)

	if not player.has_method("_apply_wade_sink"):
		_fail("player has no _apply_wade_sink() — did the script fail to attach? "
				+ "(a fresh clone needs `godot --headless --path . --import` first)")
		_report()
		return
	if not player.is_on_floor():
		_fail("player never settled on the test floor (y=%.2f) — every check below "
				% player.global_position.y + "needs is_on_floor()")
		_report()
		return

	var model: Node3D = player.get_node_or_null("CharacterModel")
	var capsule: Node3D = player.get_node_or_null("CollisionShape3D")
	if model == null or capsule == null:
		_fail("CharacterModel or CollisionShape3D missing from %s" % PLAYER_SCENE)
		_report()
		return

	await _check_sink(player, terrain, model, capsule)
	await _check_first_person_eyes(player, terrain)
	await _check_jump(player, terrain)
	_check_speed(player)
	await _check_remote_avatar(terrain)

	player.queue_free()
	_report()


func _check_remote_avatar(terrain: StubTerrain) -> void:
	"""
	CHECK 5 — a teammate standing in a river sinks too, worked out LOCALLY from
	the position presence already carries (nothing was added to the packet).

	Two negative controls, because there are two ways to get this wrong and both
	look fine on screen most of the time: a peer on DRY ground must not sink, and
	an AIRBORNE peer over a river must not either — presence carries the on-floor
	bit precisely so "flying over water is not wading" holds for remotes as well.
	"""
	var avatar := RemoteAvatar.new()
	root.add_child(avatar)
	avatar.setup("selfcheck-peer")
	var model_root: Node3D = avatar.model_root
	if model_root == null:
		_fail("remote: RemoteAvatar.setup() built no model_root")
		avatar.queue_free()
		return

	# Dry, grounded — the baseline.
	terrain.river = false
	avatar.receive_state(Vector3.ZERO, 0.0, 0, 0.0, true)
	await _frames(SETTLE_FRAMES)
	if absf(model_root.position.y) > EPS:
		_fail("remote: teammate model sits %.3f m down on dry land, expected 0"
				% model_root.position.y)

	# Airborne over the river — the on-floor negative control.
	terrain.river = true
	avatar.receive_state(Vector3.ZERO, 0.0, 0, 0.0, false)
	await _frames(SETTLE_FRAMES)
	if absf(model_root.position.y) > EPS:
		_fail("remote: teammate model sank %.3f m while AIRBORNE over a river — "
				% -model_root.position.y + "flying over water is not wading")

	# Grounded in the river — the effect.
	avatar.receive_state(Vector3.ZERO, 0.0, 0, 0.0, true)
	await _frames(SETTLE_FRAMES)
	var sunk: float = -model_root.position.y
	if absf(sunk - PLAYER_SCRIPT.WADE_SINK_DEPTH) > EPS:
		_fail("remote: teammate model settled %.3f m down in the river, expected %.2f "
				% [sunk, PLAYER_SCRIPT.WADE_SINK_DEPTH]
				+ "(the same depth the local player uses)")

	terrain.river = false
	avatar.queue_free()


func _check_sink(player: CharacterBody3D, terrain: StubTerrain, model: Node3D,
		capsule: Node3D) -> void:
	"""
	CHECK 1 — the model sinks, eases, comes back out, and NOTHING physical moves.

	The negative control is the dry measurement at both ends: a sink applied
	unconditionally would pass "it sank" and fail "it came back".
	"""
	terrain.river = false
	await _frames(SETTLE_FRAMES)

	if player.is_wading:
		_fail("sink: player reports wading with the stub terrain answering false")
	if absf(model.position.y) > EPS:
		_fail("sink: model sits at y=%.3f on DRY land, expected 0" % model.position.y)
	var dry_body_y: float = player.global_position.y
	var dry_capsule_y: float = capsule.position.y

	# One frame of river, not thirty: the offset must EASE. A snap-to-depth
	# implementation passes the settled measurement below and fails this one.
	terrain.river = true
	await physics_frame
	var stepped: float = -model.position.y
	if stepped <= 0.0 or stepped >= PLAYER_SCRIPT.WADE_SINK_DEPTH:
		_fail("sink: after ONE frame in the river the model is %.3f m down — it must "
				% stepped + "be part way (0 < d < %.2f), i.e. eased, not snapped"
				% PLAYER_SCRIPT.WADE_SINK_DEPTH)

	await _frames(SETTLE_FRAMES)
	if not player.is_wading:
		_fail("sink: player does not report wading over the stub river")
	var wet: float = -model.position.y
	if absf(wet - PLAYER_SCRIPT.WADE_SINK_DEPTH) > EPS:
		_fail("sink: model settled %.3f m down in the river, expected %.2f"
				% [wet, PLAYER_SCRIPT.WADE_SINK_DEPTH])

	# THE FLAT-WORLD INVARIANT. Submersion is a picture; the body and the capsule
	# stand exactly where they did on dry land.
	if absf(player.global_position.y - dry_body_y) > EPS:
		_fail("sink: the BODY moved %.3f m — submersion must be a model offset only, "
				% (player.global_position.y - dry_body_y)
				+ "never a change to the player's y (flat-world invariant)")
	if absf(capsule.position.y - dry_capsule_y) > EPS:
		_fail("sink: the CollisionShape3D moved %.3f m — submersion must never touch "
				% (capsule.position.y - dry_capsule_y) + "collision")

	terrain.river = false
	await _frames(SETTLE_FRAMES)
	if absf(model.position.y) > EPS:
		_fail("sink: model stayed %.3f m down after leaving the river, expected 0"
				% -model.position.y)


func _check_first_person_eyes(player: CharacterBody3D, terrain: StubTerrain) -> void:
	"""
	CHECK 2 — first person dips by the same amount, so submersion is FELT and not
	merely watched. Negative control: the dry eye height, which must be the one
	the view has always had.
	"""
	var arm: SpringArm3D = player.get_node_or_null("CameraPivot/CameraArm")
	if arm == null:
		_fail("eyes: CameraArm missing from %s" % PLAYER_SCENE)
		return
	var previous_mode: int = player.view_mode
	player.view_mode = player.ViewMode.FIRST_PERSON
	player._apply_view_mode()

	terrain.river = false
	await _frames(SETTLE_FRAMES)
	var dry_eye: float = arm.transform.origin.y

	terrain.river = true
	await _frames(SETTLE_FRAMES)
	var wet_eye: float = arm.transform.origin.y

	var dip: float = dry_eye - wet_eye
	if absf(dip - PLAYER_SCRIPT.WADE_SINK_DEPTH) > EPS:
		_fail("eyes: first-person eye height dropped %.3f m in the river, expected %.2f "
				% [dip, PLAYER_SCRIPT.WADE_SINK_DEPTH]
				+ "(the eyes must ride the same offset the model does)")

	terrain.river = false
	await _frames(SETTLE_FRAMES)
	player.view_mode = previous_mode
	player._apply_view_mode()


func _check_jump(player: CharacterBody3D, terrain: StubTerrain) -> void:
	"""
	CHECK 3 — the jump is weaker from the water, and ONLY from the water.

	Three measurements: dry (the negative control — full power), wet (weakened by
	exactly WADE_JUMP_FACTOR), and a COYOTE jump taken one frame after leaving a
	river bank, which must be at full power because it is not pushed off water.
	That last one is what fails if `is_wading` is read a frame late.
	"""
	var full: float = PLAYER_SCRIPT.JUMP_VELOCITY

	terrain.river = false
	var dry: float = await _jump_and_measure(player)
	if absf(dry - full) > EPS:
		_fail("jump: a jump from DRY ground left at %.2f m/s, expected JUMP_VELOCITY "
				% dry + "%.2f — the wade factor must not touch it" % full)

	terrain.river = true
	var wet: float = await _jump_and_measure(player)
	var want_wet: float = full * PLAYER_SCRIPT.WADE_JUMP_FACTOR
	if absf(wet - want_wet) > EPS:
		_fail("jump: a jump from the RIVER left at %.2f m/s, expected %.2f "
				% [wet, want_wet] + "(JUMP_VELOCITY * WADE_JUMP_FACTOR)")
	if wet >= dry:
		_fail("jump: wading jump (%.2f) is not weaker than the dry one (%.2f)"
				% [wet, dry])

	# COYOTE: stand in the river, then step off into the air and jump within the
	# coyote window. is_wading is false the moment we are airborne, so this is a
	# jump off a bank, not off water — full power.
	terrain.river = true
	await _reground(player)
	await _frames(4)  # long enough to be grounded AND wading again
	if not player.is_wading:
		_fail("jump: could not stage the coyote case — player is not wading")
		return
	# Step off the ledge AND press in the same breath. The press is pushed and the
	# body is lifted clear of the floor at the same instant, so (with the one-frame
	# input delay in _press_jump) the jump fires on frame F+1 — the FIRST frame the
	# controller believes it is airborne, and the only frame at which the coyote
	# window and a stale `is_wading` disagree. Stage it one frame later and even a
	# frame-late is_wading has caught up, so the check passes over the very bug it
	# exists to find (measured: it did).
	player.global_position.y += 3.0
	player.velocity = Vector3.ZERO
	Input.action_press("jump")
	await physics_frame       # F runs: still believes grounded, un-grounds itself
	await physics_frame       # F+1 runs: airborne, inside the coyote window, jumps
	Input.action_release("jump")
	var coyote: float = player.velocity.y
	if player.is_on_floor():
		_fail("jump: could not stage the coyote case — player never left the floor")
		return
	if coyote <= 0.0:
		_fail("jump: the coyote jump never fired (velocity.y=%.2f) — the coyote "
				% coyote + "window may have lapsed before the press")
	elif absf(coyote - full) > EPS:
		_fail("jump: a COYOTE jump off a river bank left at %.2f m/s, expected the "
				% coyote + "full %.2f — it started in the air, not in the water "
				% full + "(is_wading read one frame late is the usual cause)")

	terrain.river = false
	await _reground(player)


func _jump_and_measure(player: CharacterBody3D) -> float:
	"""Put the player back on the ground, let the wade state settle, jump."""
	await _reground(player)
	await _frames(4)
	return await _press_jump(player)


func _press_jump(player: CharacterBody3D) -> float:
	"""
	Synthesize one `jump` press and report the upward velocity it produced.

	Input.action_press sets the POLLED state, which is what _physics_process
	reads (the same mechanism mobile_input.gd drives the game with). The jump
	frame applies no gravity — the body is still grounded when velocity.y is
	written — so the value read straight after is the launch speed itself.
	"""
	# TIMING GOTCHA, and it is not cosmetic: a press synthesized from a
	# `physics_frame` handler is stamped with the NEXT physics frame, so the frame
	# the tree runs immediately after the press does NOT see is_action_just_pressed
	# — the one after it does. Hence TWO awaits: the first runs the frame that
	# misses the press, the second runs the frame that jumps, and we read at its
	# end while velocity.y still holds the launch speed (move_and_slide preserves
	# an upward velocity leaving the ground, and the next frame's gravity has not
	# run yet). With one await the press is released before anything ever sees it
	# and the jump silently never fires — measured.
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	return player.velocity.y


func _reground(player: CharacterBody3D) -> void:
	"""Drop the player back onto the test floor and wait until it is standing."""
	player.global_position = Vector3(0.0, 0.5, 0.0)
	player.velocity = Vector3.ZERO
	for _i in SETTLE_FRAMES:
		await physics_frame
		if player.is_on_floor():
			return


func _check_speed(player: CharacterBody3D) -> void:
	"""
	CHECK 4 — the drag bites walking, and the run gait stays above the crocodile
	chase cap. Negative control: the dry speeds, which must be untouched.

	calculate_current_speed() is called directly rather than measured off the
	body, because the body's speed is also shaped by MOVE_ACCELERATION ramping
	and by friction — the gait is the thing under test.
	"""
	player.is_ducking = false
	player.is_running = false

	player.is_wading = false
	var walk_dry: float = player.calculate_current_speed()
	player.is_wading = true
	var walk_wet: float = player.calculate_current_speed()
	if absf(walk_wet - walk_dry * PLAYER_SCRIPT.WADE_SPEED_FACTOR) > EPS:
		_fail("speed: walking is %.2f m/s wading against %.2f dry, expected the "
				% [walk_wet, walk_dry] + "WADE_SPEED_FACTOR %.2f share"
				% PLAYER_SCRIPT.WADE_SPEED_FACTOR)
	if walk_wet >= walk_dry:
		_fail("speed: wading walk (%.2f) is not slower than the dry walk (%.2f)"
				% [walk_wet, walk_dry])

	player.is_running = true
	player.is_wading = false
	var run_dry: float = player.calculate_current_speed()
	player.is_wading = true
	var run_wet: float = player.calculate_current_speed()
	player.is_running = false
	player.is_wading = false

	if run_wet < PLAYER_SCRIPT.WADE_RUN_MIN_SPEED - EPS:
		_fail("speed: the RUN gait drops to %.2f m/s in a river, under the "
				% run_wet + "WADE_RUN_MIN_SPEED floor of %.2f"
				% PLAYER_SCRIPT.WADE_RUN_MIN_SPEED)
	# The floor exists for exactly one reason: running always escapes. A river
	# whose drag takes the run under the chase cap is an inescapable trap, and
	# crossings are not length-bounded.
	if run_wet <= CROC_SCRIPT.MAX_CHASE_SPEED:
		_fail("speed: running while wading (%.2f m/s) does not outpace the crocodile "
				% run_wet + "chase cap MAX_CHASE_SPEED (%.2f) — a river would be an "
				% CROC_SCRIPT.MAX_CHASE_SPEED + "inescapable trap")
	if run_dry <= CROC_SCRIPT.MAX_CHASE_SPEED:
		_fail("speed: running on DRY land (%.2f m/s) does not outpace MAX_CHASE_SPEED "
				% run_dry + "(%.2f) — this is not a wading bug" % CROC_SCRIPT.MAX_CHASE_SPEED)
