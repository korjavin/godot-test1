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
##   1b. Crocodiles submerge too, deeper (RIVER_SINK_DEPTH), and there the same
##      mistake is worse than a broken invariant: moving the BODY instead of the
##      model changes where a hidden crocodile can bite you from, which is a
##      difficulty change nobody asked for and nobody can see. Bosses get the
##      depth scaled by the engine rather than by code, so a "fix" that divides by
##      boss_scale looks reasonable and is wrong — check 7 pins it.
##   3. The wade drag must never take the RUN gait under the crocodile chase cap
##      (MAX_CHASE_SPEED), or a river becomes an inescapable trap. That is a
##      cross-file inequality between two constants that nothing else checks.
##   4. **The gait modifier is INVERTED** (bead `godot-test1-kov`): nothing held
##      is the FAST gait and holding Shift is the slow one. That mapping is ONE
##      line in `_physics_process`, it has no visible symptom other than the game
##      feeling wrong, and re-inverting it would leave every other speed
##      assertion in this file green — they all set `is_running` by hand. Check 5
##      is the only one that presses the real action and reads the shipped
##      `calculate_current_speed()` behind it.
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
## Crocodiles wade too (checks 6 and 7) — deeper, because they lie low.
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## The crocodile's model sink depth, read from its row of the AI's SPECIES table
## (the sink is a per-species trait — it is measured off one particular GLB), for
## the same "read it from the file that owns it" reason as CROC_SCRIPT above.
const CROC_SINK_DEPTH: float = CROC_SCRIPT.SPECIES["crocodile"]["river_sink_depth"]

## Metre / m-per-second slop. The effects measured here are 0.35 m and ~2.5 m/s,
## so a centimetre of tolerance is still unambiguous.
const EPS: float = 0.01

## Slop for measurements taken off the crocodile's DRAWN model, which is never
## perfectly still: a paused crocodile still breathes at BREATHE_AMOUNT (0.012 m)
## on the very property the sink moves. The two ends of each comparison are drawn
## at UNRELATED breathing phases, so the budget is the peak-to-peak swing
## (2 * 0.012) and not the amplitude — 0.02 was too tight and failed the dry
## return by 0.022 (measured). Still six times under the 0.18 m effect.
## Measurements that dodge the animation entirely (model_base_y, the body, the
## capsule) use the tighter EPS.
const CROC_EPS: float = 0.03

## Top of the crocodile mesh in MODEL-LOCAL metres, read out of
## assets/models/characters/piglet_crocodile.glb's POSITION accessor (y spans
## -0.036 .. +0.240). Used to turn the model's world y into "how much of the
## animal is still above the river plane", which is the thing the feature is
## actually about — see _check_croc_sink's absolute band.
const CROC_MESH_TOP: float = 0.240

## The band the visible ridge must land in, at scale 1. Both ends are the check:
## below MIN the crocodile has vanished under an opaque ground plane (unfair —
## the danger telegraph is not a substitute for being able to see the animal at
## all), above MAX it is not hidden and the feature does nothing. Measured today:
## 0.058 m. The band is what fails if the SCENE changes rather than the script —
## lift the CollisionShape3D and the body no longer settles with its origin on
## the ground, which moves the whole model up and no displacement test notices.
const CROC_RIDGE_MIN: float = 0.02
const CROC_RIDGE_MAX: float = 0.10

## Deterministic per-instance roll seed for check 6's crocodile — the terrain's
## setup_roll_seed() contract used by a harness instead of by a chunk. Swept over
## seeds 0..399: this is the one whose size roll lands closest to 1.000 (1.00017),
## so the ridge band above, which was measured at scale 1, is compared against a
## scale-1 crocodile. Any seed makes the check deterministic; this one also makes
## it MEAN what its comment says. Check 7's boss needs none — the is_boss branch
## takes no size roll at all.
const CROC_ROLL_SEED: int = 230

## Boss scale used by check 7. Deliberately BOSS_MAX_SCALE, the biggest the
## terrain's schedule ever builds — if the proportional sink holds anywhere it
## holds here, and a 9x error is impossible to write off as slop.
const BOSS_TEST_SCALE: float = 9.0

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


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there. Reporting here would print a verdict at frame 0,
	# before a single physics tick had run — a vacuous pass.
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
	await _check_default_gait(player, terrain)
	await _check_remote_avatar(terrain)

	# Freed BEFORE the crocodile checks: a live player in the same tiny test world
	# is inside DETECTION_RADIUS of everything, so the crocodile would chase, bite
	# and play its chomp animation over the top of the measurement.
	player.queue_free()
	await _frames(2)
	await _check_croc_sink(terrain)
	await _check_boss_sink_scales(terrain)

	_report()


func _check_croc_sink(terrain: StubTerrain) -> void:
	"""
	CHECK 6 — a crocodile standing in a river sinks its MODEL, and only its model.

	Same shape as CHECK 1 one species over, and it exists for the same reason: a
	sink written to the body or the capsule instead looks identical on screen and
	silently changes where the crocodile can bite you from. So the effect is
	measured on the drawn model while the body y and the CollisionShape3D are
	asserted UNMOVED — this is visual danger, not a mechanics change.

	Negative controls, both of them: the dry measurement at each end (a sink
	applied unconditionally passes "it sank" and fails "it came back out"), and an
	AIRBORNE crocodile held over the river, which must not sink — grounded-only is
	the same rule the player's `is_wading` follows.
	"""
	var packed: PackedScene = load(CROC_SCENE)
	if packed == null:
		_fail("croc: could not load %s" % CROC_SCENE)
		Sentinel.done("croc_sink")
		return
	var croc: CharacterBody3D = packed.instantiate()
	# CALL-ORDER CONTRACT, the same one check 7 states for setup_as_boss: the seed
	# must be handed over BEFORE add_child, because _ready() is where the rolls
	# happen. WITHOUT IT this check is a coin flip. An unseeded crocodile falls
	# back to rng.randomize() and applies the +/-25% SIZE_RANDOM_FACTOR to the
	# whole body, which scales model.global_position.y while CROC_MESH_TOP below
	# is a fixed model-local constant — so the absolute ridge came out anywhere in
	# 0.015..0.105 m and fell outside the 0.02..0.10 band about one run in four.
	# Every DISPLACEMENT assertion beside it was unaffected (they are relative),
	# which is exactly why the flake looked like a phantom. CROC_ROLL_SEED is the
	# seed nearest a 1.000 size roll, so the band — measured at scale 1 — means
	# what it says rather than being tested against some other crocodile's size.
	croc.setup_roll_seed(CROC_ROLL_SEED)
	croc.position = Vector3(20.0, 0.5, 0.0)
	root.add_child(croc)
	await _frames(SETTLE_FRAMES)

	if not croc.has_method("_tick_river_sink"):
		_fail("croc: no _tick_river_sink() on %s — did the script fail to attach? "
				% CROC_SCENE + "(a fresh clone needs `godot --headless --path . --import`)")
		croc.queue_free()
		Sentinel.done("croc_sink")
		return
	var model: Node3D = croc.get_node_or_null("Model")
	var capsule: Node3D = croc.get_node_or_null("CollisionShape3D")
	if model == null or capsule == null:
		_fail("croc: Model or CollisionShape3D missing from %s" % CROC_SCENE)
		croc.queue_free()
		Sentinel.done("croc_sink")
		return
	if not croc.is_on_floor():
		_fail("croc: never settled on the test floor (y=%.2f)" % croc.global_position.y)
		croc.queue_free()
		Sentinel.done("croc_sink")
		return
	if croc.terrain == null:
		_fail("croc: did not resolve the terrain in _ready() — the sink can never "
				+ "fire (is the stub in group \"terrain\" before the croc is added?)")

	# Stand it still. A wandering crocodile's bob is up to BOB_AMOUNT * 1.6 = 4 cm,
	# which would swamp CROC_EPS; paused it breathes at BREATHE_AMOUNT (1.2 cm),
	# which CROC_EPS is sized to absorb.
	croc.is_paused = true
	croc.pause_time_remaining = 1e9

	terrain.river = false
	await _frames(SETTLE_FRAMES)
	var dry_model_y: float = model.position.y
	var dry_body_y: float = croc.global_position.y
	var dry_capsule_y: float = capsule.position.y
	if absf(dry_model_y - croc.model_rest_y) > CROC_EPS:
		_fail("croc: model sits %.3f m off its rest height on DRY land, expected 0"
				% (dry_model_y - croc.model_rest_y))

	# ONE frame of river, not thirty: the offset must EASE. A snap-to-depth
	# implementation passes the settled measurement below and fails this one.
	# Read off model_base_y rather than the drawn position — the ease step at
	# 60 Hz is ~1.5 cm, the same order as the idle breathing on top of it.
	terrain.river = true
	await physics_frame
	var stepped: float = croc.model_rest_y - croc.model_base_y
	if stepped <= 0.0 or stepped >= CROC_SINK_DEPTH:
		_fail("croc: after ONE frame in the river the model is %.3f m down — it must "
				% stepped + "be part way (0 < d < %.2f), i.e. eased, not snapped"
				% CROC_SINK_DEPTH)

	await _frames(SETTLE_FRAMES)
	var wet: float = dry_model_y - model.position.y
	if absf(wet - CROC_SINK_DEPTH) > CROC_EPS:
		_fail("croc: model settled %.3f m down in the river, expected %.2f"
				% [wet, CROC_SINK_DEPTH])

	# ABSOLUTE, not relative: how much of the animal is still above the river
	# plane. Everything else here measures DISPLACEMENT, which stays perfect
	# while the whole crocodile sits higher than it should — the body settles
	# with its origin on the ground only because the capsule lies on its side
	# (local centre 0.16, vertical half-extent = radius 0.16, so its bottom is
	# at body y = 0). Move the CollisionShape3D in the scene and the sink still
	# eases exactly 0.18 m onto a crocodile that is no longer in the water.
	var ridge: float = model.global_position.y + CROC_MESH_TOP
	if ridge < CROC_RIDGE_MIN or ridge > CROC_RIDGE_MAX:
		_fail("croc: %.3f m of crocodile is left above the river plane, expected "
				% ridge + "%.2f..%.2f — below that it has vanished entirely, above it "
				% [CROC_RIDGE_MIN, CROC_RIDGE_MAX]
				+ "it is not hidden at all (is the body still settling with its "
				+ "origin on the ground?)")

	# THE POINT OF THE WHOLE CHECK. Submersion is a picture: the body and the
	# capsule stand exactly where they did dry, so bite range is byte-identical.
	# Mutation-tested: sinking the CollisionShape3D fails BOTH lines below.
	# Honest limit — writing `position.y` alone does NOT fail them, because the
	# floor pushes the body straight back out on the same move_and_slide; that
	# mutation also leaves bite range unchanged, so it is not the bug guarded here.
	if absf(croc.global_position.y - dry_body_y) > EPS:
		_fail("croc: the BODY moved %.3f m — submersion must be a model offset only "
				% (croc.global_position.y - dry_body_y)
				+ "(flat-world invariant, and bite range must not change)")
	if absf(capsule.position.y - dry_capsule_y) > EPS:
		_fail("croc: the CollisionShape3D moved %.3f m — submersion must never touch "
				% (capsule.position.y - dry_capsule_y) + "collision")

	# AIRBORNE over the river — the grounded-only negative control. Held above the
	# floor every frame so gravity cannot land it mid-measurement.
	for _i in SETTLE_FRAMES:
		croc.global_position.y = 4.0
		croc.velocity = Vector3.ZERO
		await physics_frame
	if croc.is_on_floor():
		_fail("croc: could not stage the airborne case — still on the floor")
	elif absf(croc.model_base_y - croc.model_rest_y) > EPS:
		_fail("croc: model stayed %.3f m down while AIRBORNE over a river — "
				% (croc.model_rest_y - croc.model_base_y)
				+ "flying over water is not wading")

	# Dry land again — it must come back OUT.
	terrain.river = false
	croc.global_position = Vector3(20.0, 0.5, 0.0)
	await _frames(SETTLE_FRAMES)
	if absf(model.position.y - dry_model_y) > CROC_EPS:
		_fail("croc: model stayed %.3f m down after leaving the river, expected 0"
				% (dry_model_y - model.position.y))

	croc.queue_free()
	Sentinel.done("croc_sink")


func _check_boss_sink_scales(terrain: StubTerrain) -> void:
	"""
	CHECK 7 — a boss sinks in PROPORTION, with no boss-specific code.

	RIVER_SINK_DEPTH is a model-LOCAL offset and _ready() scales the whole body by
	boss_scale, so the engine scales the sink for free: the submerged fraction is
	identical at every size, which is what "a proportional snout" means. Measured
	in WORLD space so the free ride is what is actually asserted — dividing the
	depth by boss_scale "to compensate", or hoisting the offset onto the unscaled
	body, both break this and neither breaks anything visible on a regular croc.
	"""
	var packed: PackedScene = load(CROC_SCENE)
	if packed == null:
		_fail("boss: could not load %s" % CROC_SCENE)
		Sentinel.done("boss_sink_scales")
		return
	var croc: CharacterBody3D = packed.instantiate()
	# CALL-ORDER CONTRACT: setup_as_boss() must run BEFORE add_child, because
	# _ready() is what applies the scale.
	croc.setup_as_boss(BOSS_TEST_SCALE)
	croc.position = Vector3(-20.0, 0.5, 0.0)
	root.add_child(croc)
	await _frames(SETTLE_FRAMES)

	var model: Node3D = croc.get_node_or_null("Model")
	if model == null or not croc.is_on_floor():
		_fail("boss: model missing, or the boss never settled on the test floor")
		croc.queue_free()
		Sentinel.done("boss_sink_scales")
		return
	if absf(croc.scale.y - BOSS_TEST_SCALE) > EPS:
		_fail("boss: body scale is %.2f, expected setup_as_boss(%.1f) to apply it"
				% [croc.scale.y, BOSS_TEST_SCALE])
	croc.is_paused = true
	croc.pause_time_remaining = 1e9

	terrain.river = false
	await _frames(SETTLE_FRAMES)
	var dry_world_y: float = model.global_position.y

	terrain.river = true
	await _frames(SETTLE_FRAMES)
	var sunk: float = dry_world_y - model.global_position.y
	var want: float = CROC_SINK_DEPTH * BOSS_TEST_SCALE
	if absf(sunk - want) > CROC_EPS * BOSS_TEST_SCALE:
		_fail("boss: a %.1fx boss sank %.3f m in world space, expected %.3f "
				% [BOSS_TEST_SCALE, sunk, want]
				+ "(RIVER_SINK_DEPTH * boss_scale) — the sink is a model-LOCAL "
				+ "offset and must ride the body scale, not compensate for it")

	terrain.river = false
	croc.queue_free()
	Sentinel.done("boss_sink_scales")


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
		Sentinel.done("remote_avatar")
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
	Sentinel.done("remote_avatar")


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
	Sentinel.done("sink")


func _check_first_person_eyes(player: CharacterBody3D, terrain: StubTerrain) -> void:
	"""
	CHECK 2 — first person dips by the same amount, so submersion is FELT and not
	merely watched. Negative control: the dry eye height, which must be the one
	the view has always had.
	"""
	var arm: SpringArm3D = player.get_node_or_null("CameraPivot/CameraArm")
	if arm == null:
		_fail("eyes: CameraArm missing from %s" % PLAYER_SCENE)
		Sentinel.done("first_person_eyes")
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
	Sentinel.done("first_person_eyes")


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
		Sentinel.done("jump")
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
		Sentinel.done("jump")
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
	Sentinel.done("jump")


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
	Sentinel.done("speed")


func _check_default_gait(player: CharacterBody3D, terrain: StubTerrain) -> void:
	"""
	CHECK 5 — THE GAIT MODIFIER IS INVERTED: no key held is the FAST gait, and
	holding the modifier is the SLOW one (owner ruling 2026-09-03, bead
	`godot-test1-kov`). Ducking still wins over both.

	This is the ONE check that drives the real input action end to end — press the
	action the way a player does, let a physics frame run `_physics_process`'s
	STEP 4, then read the SHIPPED `calculate_current_speed()`. It deliberately
	does NOT set `is_running` by hand (which is what every other speed assertion
	in this file does): the whole bug class here lives in the ONE line that maps
	the action to that flag, and a check that writes the flag itself cannot see it.

	The assertion is the ORDERING and not a number. Re-deriving `RUN_SPEED *
	CHARACTER_SPEED * gait_mult` here would be a second copy of the branch under
	test, and a copy that inverted with it would pass. `default > held`, strictly,
	is what a reverted inversion cannot satisfy — and being strict is also the
	vacuity guard: a rig where `_physics_process` never ran reports two equal
	speeds and fails.

	The action name is still "run" for the historical reason `player_controller`
	records at the read site.
	"""
	# Dry land: a previous check may have left the stub river on, and the gait
	# ordering is the thing under test here — not the drag.
	terrain.river = false
	await _reground(player)
	if not player.is_on_floor():
		_fail("gait: player never regrounded — STEP 4's duck clause needs is_on_floor()")
		Sentinel.done("default_gait")
		return

	# Nothing held: the DEFAULT gait.
	Input.action_release("run")
	Input.action_release("duck")
	await _frames(2)
	var default_running: bool = player.is_running
	var default_speed: float = player.calculate_current_speed()

	# The modifier held: the SLOW gait.
	Input.action_press("run")
	await _frames(2)
	var held_running: bool = player.is_running
	var held_speed: float = player.calculate_current_speed()

	# Ducking OVER the default gait — Ctrl has to beat both sides of the flip.
	Input.action_release("run")
	Input.action_press("duck")
	await _frames(2)
	var duck_running: bool = player.is_running
	var duck_ducking: bool = player.is_ducking
	Input.action_release("duck")
	await _frames(2)

	if not default_running:
		_fail("gait: NOTHING held and is_running is false — the default gait is the "
				+ "slow one, which is the pre-`kov` behaviour the owner reversed")
	if held_running:
		_fail("gait: the modifier is held and is_running is still true — holding it "
				+ "must SLOW the hero, not speed it up")
	if default_speed <= held_speed:
		_fail("gait: the default gait is %.2f m/s against %.2f held — the default "
				% [default_speed, held_speed] + "must be strictly FASTER (equal speeds "
				+ "also mean _physics_process never ran and this check is vacuous)")
	# The catchable-walk chain, restated where the DEFAULT side of it now sits: the
	# fast gait is what a player gets for free, so it is the one that has to clear
	# the chase cap. The slow gait is deliberately below it — that is the whole
	# point of a modifier that makes you catchable on purpose.
	if default_speed <= CROC_SCRIPT.MAX_CHASE_SPEED:
		_fail("gait: the DEFAULT gait is %.2f m/s, at or under MAX_CHASE_SPEED (%.2f) "
				% [default_speed, CROC_SCRIPT.MAX_CHASE_SPEED]
				+ "— nothing held would no longer escape")
	if not duck_ducking:
		_fail("gait: Ctrl did not duck, so the ducking-wins assertion below is vacuous")
	elif duck_running:
		_fail("gait: ducking with nothing else held still reports is_running — ducking "
				+ "must win over the default gait exactly as it won over the old one")

	print("gait: default %.2f m/s (running), modifier held %.2f m/s (walking)"
			% [default_speed, held_speed])
	Sentinel.done("default_gait")
