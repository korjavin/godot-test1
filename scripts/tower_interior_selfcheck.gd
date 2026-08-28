extends SceneTree
## Headless self-check: THE TOWER'S INTERIOR IS WALKABLE, ITS GATES WORK, AND ITS
## GATES STAY OPEN.
##
##   godot --headless --path . --script res://scripts/tower_interior_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the shape
## `tower_shell_selfcheck.gd` (phase 2) established, applied to what is inside the
## building rather than to the building.
##
## WHAT IT GUARDS (bead godot-test1-3iy.3), and why each is worth a check. Every one
## of these fails SILENTLY — a level that looks entirely correct in a screenshot and
## is unplayable, or playable in a way it was never meant to be:
##
##   1. THE PLAN FITS AND IS AFFORDABLE. 26 boxes inside a 17.6 m square with a 7 m
##      cube of spire in one corner; a box that drifts into the spire or out through
##      a wall is invisible from inside and obvious from the yard. Check 1.
##   2. **NO JUMP-GATED CLIMB.** The bead's hardest rule and the one this file
##      exists for. The upper storey must be reachable ONLY by the ramp, which means
##      nothing standing under the open sky may be a step up to it — and "standing
##      on" has to mean what the physics engine means, so the check measures the
##      HEADROOM over each candidate and ignores anything a 2 m capsule cannot
##      stand on. The jump apex is recomputed from `player_controller`'s own
##      JUMP_VELOCITY and gravity, never restated, because the whole point is that
##      the day somebody retunes the jump this check fails instead of the level
##      quietly becoming a shortcut. Check 2.
##   3. THE RAMP IS THE STAIR, AND IT IS FLUSH. Godot's CharacterBody3D has no
##      step-up: a lip of ANY height at either end of the ramp is a wall you must
##      jump, i.e. exactly the thing rule 2 forbids, and 12 cm of lip is invisible
##      in every screenshot. Check 3 reconstructs the deck's two ends from the box's
##      real transform and asserts they land on the ground and on the slab.
##   4. THE CAMERA FITS. `CameraArm` is a SpringArm3D and nothing may write
##      `camera.position`, so the only way a room can be comfortable is to be tall
##      enough. Check 4 MEASURES a live rig (the scene file lies — the controller
##      rewrites the arm) and asserts the hall clears where the camera really sits.
##   5. IT IS A BUILDING, NOT CHUNK CONTENT: one StaticBody3D, one mesh per box,
##      materials shared process-wide and already toon so ToonShading declines to
##      duplicate them. Checks 5 and 6 — the shell's discipline, one storey up.
##   6. **THE GATE LIFECYCLE.** Check 7 is the acceptance walk, driven under real
##      physics: a wrong hero on the identity pad opens nothing; the RIGHT hero
##      standing on the same pad WITHOUT MOVING opens it (which is what "keys on who
##      is standing there, not on who walked in" means, and the only form of the
##      assertion a `body_entered` latch cannot pass); the demand gate refuses a
##      short reading with a partway reaction, a lit-band count and an explanation
##      that names the number, then opens for a reading that meets it; and the
##      checkpoint records itself. Collision shapes are asserted to have moved WITH
##      their meshes, because a gate that opened only visually is the worst bug in
##      the file.
##   7. **OPENED STATE IS RE-APPLIED.** Check 8 pre-loads the tower's opened set and
##      asserts a freshly built interior comes up already open, with no frame and no
##      animation. That is the seam phase 5 loads a save through, and it is what
##      makes "walk out, walk back in, still open" a property of the code.
##   8. VISIBILITY GATING. Check 9 drives the policy directly at storey counts this
##      building does not have (so phase 8 inherits a correct gate rather than
##      discovering it needs one) and then confirms the live rig hides the whole
##      interior from across the field and shows it from inside.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"

## How tall the player's capsule is, for the "could anybody actually stand here"
## test in check 2. `player.tscn`'s CollisionShape3D is a default CapsuleShape3D
## (radius 0.5, height 2.0) sat at y = 1, so the body occupies 0 .. 2 m.
const PLAYER_HEIGHT: float = 2.0

## Clearance the hall must keep between the camera's resting height and the
## ceiling, on top of the spring arm's own margin. Small on purpose: this is the
## line between "the arm never moves on flat ground" and "the arm is doing its job",
## not a comfort target.
const CAMERA_CLEARANCE: float = 0.2

## Floating-point slack for geometry that is supposed to be EXACTLY flush.
const EPS: float = 1e-4

var _failures: Array[String] = []


## A stand-in for the player: a real CharacterBody3D on the default collision layer
## and in the "player" group, whose hero and phase reach the check sets directly.
##
## IT IMPLEMENTS THE CONTRACT AND NOTHING ELSE — `hero_name()`, `phase_reach()` and
## `hit_by_crocodile()` are the three methods the interior asks of a player, so a
## rename on either side fails here instead of degrading into a gate that never
## opens. Instancing the real `player.tscn` would drag in four character models and
## a camera rig to test three method calls.
class ProbePlayer extends CharacterBody3D:
	var hero: String = "windman"
	var reach: float = 0.0
	var hits: int = 0

	func hero_name() -> String:
		return hero

	func phase_reach() -> float:
		return reach

	func hit_by_crocodile() -> void:
		hits += 1


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING — a node added to `root` from inside _initialize()
	# is not `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (tower_shell_selfcheck's note).
	await process_frame
	await _run()


func _run() -> void:
	_check_plan_fits_the_shell()
	_check_no_jump_gated_climb()
	_check_ramp_is_the_stair()
	await _check_headroom_clears_the_camera()
	await _check_node_shape()
	await _check_materials_are_shared_and_already_toon()
	await _check_gate_lifecycle()
	await _check_opened_state_is_reapplied()
	await _check_visibility_gating()
	_report()


# ============================================================================
# CHECK 1 — the plan
# ============================================================================

func _check_plan_fits_the_shell() -> void:
	"""
	Check 1. The interior is affordable, well-formed, and entirely inside the walls
	it is supposed to be inside.

	THE SPIRE IS THE INTERESTING HALF. It is a solid 7 m cube of stone filling the
	-X/-Z corner of the keep, and it is the one obstacle in here that is not in this
	file's own table — so a floor plan that grew westward would look perfect in
	`boxes()` and be a room half full of rock. The doorway is the other: the shell's
	trigger volume must stay empty or walking in is walking into a wall.
	"""
	var boxes := TowerInterior.boxes()
	if boxes.size() > TowerInterior.BOX_BUDGET:
		_fail("the interior is %d boxes, over its declared BOX_BUDGET of %d" % [
			boxes.size(), TowerInterior.BOX_BUDGET])
	print("tower interior: %d boxes (budget %d), hall headroom %.2f m, storey %.2f m" % [
		boxes.size(), TowerInterior.BOX_BUDGET, TowerInterior.headroom(), TowerInterior.SLAB_Y])

	var seen := {}
	var inner := TowerInterior.INNER_HALF
	var door: Dictionary = TowerShell.door_trigger_box()
	for box: Dictionary in boxes:
		for field: String in ["name", "pos", "size", "color", "collide", "floor"]:
			if not box.has(field):
				_fail("interior box %s has no \"%s\"" % [box.get("name", "?"), field])
		var box_name: String = box["name"]
		if seen.has(box_name):
			_fail("two interior boxes are both called %s" % box_name)
		seen[box_name] = true
		var floor_index: int = int(box["floor"])
		if floor_index < 0 or floor_index > 1:
			_fail("%s claims storey %d; this building has two" % [box_name, floor_index])

		# A rotor bar sweeps a DISC, so its footprint is its own length in every
		# horizontal direction — measuring its axis-aligned box would miss the tip
		# hitting a jamb a quarter turn later.
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		var reach_x := half.x
		var reach_z := half.z
		var reach_y := half.y
		if not is_zero_approx(float(box.get("spin", 0.0))):
			reach_x = maxf(half.x, half.z)
			reach_z = reach_x
		elif box.has("rot"):
			# The ramp is the one tilted body: its axis-aligned extent is the
			# projection of the tilted one, and using the untilted half-sizes would
			# put its corner a metre outside the wall it actually clears.
			var rot: Vector3 = box["rot"]
			var c := absf(cos(rot.z))
			var s := absf(sin(rot.z))
			reach_x = half.x * c + half.y * s
			reach_y = half.x * s + half.y * c
		if absf(pos.x) + reach_x > inner + EPS or absf(pos.z) + reach_z > inner + EPS:
			_fail("%s reaches outside the shell's inner faces (+/-%.2f m)" % [box_name, inner])
		# The ramp is exempt from the floor test and only from that one: a tilted slab
		# whose DECK meets the ground at its foot necessarily buries its own underside
		# below it. Where the deck actually lands is check 3's business, and check 3
		# pins it to the millimetre.
		if not box.has("rot") and pos.y - reach_y < -EPS:
			_fail("%s starts below the floor (y = %.2f)" % [box_name, pos.y - reach_y])
		if pos.y + reach_y > TowerShell.WALL_HEIGHT + EPS:
			_fail("%s tops out at %.2f m, over the shell's %.2f m wall" % [
				box_name, pos.y + reach_y, TowerShell.WALL_HEIGHT])

		# The spire, from the shell's own numbers rather than a copied literal.
		var spire_edge := -(TowerShell.OUTER_HALF - TowerShell.SPIRE_SIDE)
		if pos.x - half.x < spire_edge and pos.z - half.z < spire_edge:
			_fail("%s reaches into the corner spire's stone (x and z both under %.2f)" % [
				box_name, spire_edge])

		# And the doorway stays a hole.
		if _overlaps(pos, box["size"], door["pos"], door["size"]):
			_fail("%s stands in the shell's doorway volume" % box_name)

	# The rotor's two dimensions have to agree with the doorway they guard.
	if TowerInterior.ROTOR_ARM >= TowerInterior.ROTOR_DOOR_HALF:
		_fail("the rotor bars (%.2f m) are longer than their doorway is wide (%.2f m) — they grind the jambs" % [
			TowerInterior.ROTOR_ARM, TowerInterior.ROTOR_DOOR_HALF])
	if TowerInterior.ROTOR_ARM <= TowerInterior.ROTOR_DOOR_HALF * 0.5:
		_fail("the rotor bars are too short to cover half the doorway — nothing to time")


# ============================================================================
# CHECK 2 — the jump rule
# ============================================================================

func _check_no_jump_gated_climb() -> void:
	"""
	Check 2. The upper storey is reachable by the ramp and by nothing else, and no
	barrier anywhere is one an unaided jump clears.

	THE APEX IS RECOMPUTED, NEVER RESTATED: `JUMP_VELOCITY^2 / (2 * gravity)` out of
	`player_controller` itself. That is the entire value of this check — the level's
	safety is a claim about the player's jump, so it has to be measured against the
	player's actual jump, and the day somebody retunes either number this fails
	instead of the tower quietly becoming climbable.

	"STANDING ON" MEANS WHAT THE ENGINE MEANS. A 2 m capsule cannot stand in a 0.6 m
	slot, so a wall top with the ramp deck just above it is not a step however
	inviting its height looks in the table — and the low wall under the ramp is
	exactly that case. `_headroom_over` is what tells the two apart; without it this
	check would either fail on correct geometry or have to be weakened until it
	passed on incorrect geometry.
	"""
	var apex := _jump_apex()
	print("jump apex %.4f m; upper storey at %.2f m" % [apex, TowerInterior.SLAB_Y])
	if apex <= 0.0:
		_fail("could not read the jump apex out of player_controller — check 2 would pass vacuously")
		return

	# (a) Nothing under the open sky is a step up to the upper storey.
	var ceiling := TowerInterior.SLAB_Y
	for box: Dictionary in TowerInterior.boxes():
		if not box["collide"]:
			continue
		if box.has("rot"):
			continue  # the ramp; it is MEANT to reach the slab — see check 3.
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		var top := pos.y + half.y
		if top >= ceiling - EPS:
			continue  # level with the storey or taller: not a step onto it.
		if top + apex <= ceiling + EPS:
			continue  # too low to matter.
		if _roofed(pos, half):
			continue  # under the slab: a jump from here ends at the ceiling.
		if _headroom_over(box) < PLAYER_HEIGHT:
			continue  # nothing can stand here in the first place.
		_fail("%s is a %.2f m ledge under the open sky: a jump off it reaches %.2f m and the upper storey is at %.2f m" % [
			box["name"], top, top + apex, ceiling])

	# (b) The secure door cannot be jumped from the storey it stands on.
	var partition_top := TowerInterior.SLAB_Y + TowerInterior.UPPER_WALL_HEIGHT
	if partition_top < TowerInterior.SLAB_Y + apex:
		_fail("the secure door is %.2f m tall on a %.2f m floor — a %.4f m jump clears it" % [
			TowerInterior.UPPER_WALL_HEIGHT, TowerInterior.SLAB_Y, apex])
	if TowerShell.WALL_HEIGHT < TowerInterior.SLAB_Y + apex:
		_fail("the shell's %.2f m wall is jumpable from the %.2f m upper floor" % [
			TowerShell.WALL_HEIGHT, TowerInterior.SLAB_Y])

	# (c) ...and the mass filling it is as tall as the door it fills, or the gap
	#     above it is the way through.
	for box: Dictionary in TowerInterior.boxes():
		if box["name"] != "IdentityMass":
			continue
		var top: float = box["pos"].y + box["size"].y * 0.5
		if top < partition_top - EPS:
			_fail("the identity mass tops out at %.2f m inside a %.2f m doorway — you can climb over it" % [
				top, partition_top])


func _jump_apex() -> float:
	"""
	The player's unaided jump apex, in metres, read out of `player_controller`.

	`JUMP_VELOCITY` is a const on the script and `gravity` is a plain var, so this
	builds one bare instance (never added to the tree, so `_ready()` never runs and
	no character model is loaded) purely to read the default off it.
	"""
	var script: GDScript = load(PLAYER_SCRIPT)
	var probe: Object = script.new()
	var g: float = float(probe.get("gravity"))
	var v: float = float(script.get_script_constant_map().get("JUMP_VELOCITY", 0.0))
	if probe is Node:
		(probe as Node).free()
	if g <= 0.0 or v <= 0.0:
		return 0.0
	return v * v / (2.0 * g)


func _roofed(pos: Vector3, half: Vector3) -> bool:
	"""Is this box entirely under the upper slab? (Then a jump off it hits a ceiling.)"""
	return pos.x - half.x >= TowerInterior.SLAB_X0 - EPS \
			and pos.x + half.x <= TowerInterior.INNER_HALF + EPS \
			and absf(pos.z) + half.z <= TowerInterior.INNER_HALF + EPS


func _headroom_over(box: Dictionary) -> float:
	"""
	The best clear height a player could stand in on top of this box, in metres.

	Sampled at the footprint's four corners and its centre and reduced with MAX —
	the question is whether there is ANY spot up there to stand, not whether the
	whole top is clear. Considers the other axis-aligned solids and, analytically,
	the ramp deck, which is the only rotated body in the building and the only thing
	whose bounding box would lie about where its underside actually is.
	"""
	var pos: Vector3 = box["pos"]
	var half: Vector3 = box["size"] * 0.5
	var top := pos.y + half.y
	var best := 0.0
	for dx in [-1.0, 0.0, 1.0]:
		for dz in [-1.0, 0.0, 1.0]:
			var x: float = pos.x + float(dx) * half.x * 0.9
			var z: float = pos.z + float(dz) * half.z * 0.9
			best = maxf(best, _clearance_at(x, z, top, box["name"]))
	return best


func _clearance_at(x: float, z: float, from_y: float, skip: String) -> float:
	"""Vertical gap between `from_y` and the lowest solid surface above this XZ point."""
	var lowest := TowerShell.WALL_HEIGHT * 2.0
	for other: Dictionary in TowerInterior.boxes():
		if not other["collide"] or other["name"] == skip:
			continue
		if other.has("rot"):
			lowest = minf(lowest, _ramp_underside_at(x, z))
			continue
		var pos: Vector3 = other["pos"]
		var half: Vector3 = other["size"] * 0.5
		if absf(pos.x - x) > half.x or absf(pos.z - z) > half.z:
			continue
		var bottom := pos.y - half.y
		if bottom >= from_y - EPS:
			lowest = minf(lowest, bottom)
	return maxf(0.0, lowest - from_y)


func _ramp_underside_at(x: float, z: float) -> float:
	"""
	How high the ramp's UNDERSIDE is over this XZ point, or a huge number where the
	ramp is not overhead.

	Analytic rather than a bounding box on purpose: the ramp is a rotated slab, and
	its AABB claims stone from the floor to the slab across its whole run — which
	would declare the entire courtyard roofed and quietly disable check 2.
	"""
	var ramp: Dictionary = TowerInterior._ramp_box()
	if absf(z - ramp["pos"].z) > ramp["size"].z * 0.5:
		return TowerShell.WALL_HEIGHT * 2.0
	if x < TowerInterior.RAMP_X0 or x > TowerInterior.SLAB_X0:
		return TowerShell.WALL_HEIGHT * 2.0
	var run := TowerInterior.SLAB_X0 - TowerInterior.RAMP_X0
	var deck := TowerInterior.SLAB_Y * (x - TowerInterior.RAMP_X0) / run
	var theta: float = ramp["rot"].z
	return deck - TowerInterior.RAMP_THICK / cos(theta)


# ============================================================================
# CHECK 3 — the ramp
# ============================================================================

func _check_ramp_is_the_stair() -> void:
	"""
	Check 3. The ramp's walking surface starts on the ground and ends on the slab,
	exactly, and is shallow enough to walk up.

	MEASURED OFF THE BOX'S REAL TRANSFORM, not off the constants that produced it.
	The failure this is written for is subtle and total: offsetting a rotated slab
	by half its thickness STRAIGHT DOWN instead of along its own normal leaves the
	deck 12 cm proud of the slab at the top, and Godot's CharacterBody3D has no
	step-up, so the stairs simply end in a wall. From every screenshot the ramp
	looks perfect. So this rebuilds the deck's two end points from `pos`, `rot` and
	`size` and asserts where they land.
	"""
	var ramp: Dictionary = {}
	for box: Dictionary in TowerInterior.boxes():
		if box["name"] == "Ramp":
			ramp = box
	if ramp.is_empty():
		_fail("there is no box called Ramp — the only way between the storeys is gone")
		return

	var pos: Vector3 = ramp["pos"]
	var size: Vector3 = ramp["size"]
	var rot: Vector3 = ramp["rot"]
	var theta: float = rot.z
	var along := Vector2(cos(theta), sin(theta))
	var normal := Vector2(-sin(theta), cos(theta))
	var deck_mid := Vector2(pos.x, pos.y) + normal * (size.y * 0.5)
	var foot := deck_mid - along * (size.x * 0.5)
	var head := deck_mid + along * (size.x * 0.5)

	if absf(foot.y) > EPS:
		_fail("the ramp's foot is %.3f m off the ground — a step CharacterBody3D cannot climb" % foot.y)
	if absf(foot.x - TowerInterior.RAMP_X0) > EPS:
		_fail("the ramp's foot is at x = %.3f, expected %.3f" % [foot.x, TowerInterior.RAMP_X0])
	if absf(head.y - TowerInterior.SLAB_Y) > EPS:
		_fail("the ramp's head is %.3f m off the upper floor — a lip you would have to jump" % (
			head.y - TowerInterior.SLAB_Y))
	if absf(head.x - TowerInterior.SLAB_X0) > EPS:
		_fail("the ramp's head is at x = %.3f, expected the slab's edge %.3f" % [
			head.x, TowerInterior.SLAB_X0])

	# Godot's CharacterBody3D refuses to treat a surface steeper than
	# `floor_max_angle` (45 degrees by default) as floor: at that point the ramp
	# stops being a stair and becomes a slide.
	var degrees := rad_to_deg(theta)
	if degrees >= 40.0:
		_fail("the ramp is %.1f degrees — at 45 the engine stops calling it a floor" % degrees)
	print("ramp: %.1f degrees, foot (%.2f, %.2f) head (%.2f, %.2f)" % [
		degrees, foot.x, foot.y, head.x, head.y])


# ============================================================================
# CHECK 4 — the camera
# ============================================================================

func _check_headroom_clears_the_camera() -> void:
	"""
	Check 4. The one enclosed room in the building is taller than where the camera
	actually floats.

	MEASURED OFF A LIVE RIG, not read out of `player.tscn`. That distinction cost an
	hour and is the whole reason this check is worth having: the scene file's
	`CameraArm` transform is a -14 degree pitch that `player_controller._ready()`
	immediately overwrites, and a SpringArm3D hangs its children along +Z, so
	computing the camera's height from the file gives -0.50 m — the camera
	underground — for a rig that in fact sits 3.50 m up. Any number this check
	derived from the file would have been confidently wrong in the safe direction.
	So it instances the player, lets the controller build its rig, waits for the
	spring arm to settle, and asks where the camera IS.

	`CameraArm` is a SpringArm3D and nothing may write `camera.position` (CLAUDE.md),
	so a low ceiling has exactly one symptom — the arm collapses and the third-person
	view becomes the back of a head — and exactly one fix, which is the room.
	"""
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(player)
	player.global_position = Vector3.ZERO
	await _settle_physics()
	var camera := player.get_node_or_null("CameraPivot/CameraArm/Camera3D") as Camera3D
	var arm := player.get_node_or_null("CameraPivot/CameraArm") as SpringArm3D
	if camera == null or arm == null:
		_fail("the player's camera rig is not at CameraPivot/CameraArm/Camera3D — check 4 would pass vacuously")
		player.queue_free()
		await process_frame
		return

	var camera_y: float = camera.global_position.y - player.global_position.y
	var need := camera_y + arm.margin + CAMERA_CLEARANCE
	print("camera floats %.2f m over the feet (+ %.2f margin); hall headroom %.2f m" % [
		camera_y, arm.margin, TowerInterior.headroom()])
	if camera_y <= 0.0:
		_fail("the camera measured %.2f m over the feet — the rig did not settle" % camera_y)
	if TowerInterior.headroom() < need:
		_fail("the hall is %.2f m and the camera needs %.2f m — the spring arm will collapse on flat ground" % [
			TowerInterior.headroom(), need])
	# The upper storey has no ceiling at all, but it does have a parapet; make sure
	# the shell still has wall left over it, or the "room" is a plinth.
	if TowerShell.WALL_HEIGHT - TowerInterior.SLAB_Y < 2.0:
		_fail("the upper storey has only %.2f m of wall around it — that is a plinth, not a room" % (
			TowerShell.WALL_HEIGHT - TowerInterior.SLAB_Y))
	# The real player joins group "player"; leaving it in the tree would give every
	# later check two candidates for "the local player" and a coin-flip for which.
	player.queue_free()
	await process_frame


# ============================================================================
# CHECK 5 — what gets built
# ============================================================================

func _check_node_shape() -> void:
	"""
	Check 5. Every box got built — the ones that move as their own node, the rest
	welded into their storey's batch — with ONE physics body and one collision shape
	per solid box however it was drawn.

	THE DRAW BUDGET IS THE POINT OF THE COUNT. Built one node per box, the interior
	cost 67 draw calls over the bare shell and took a walk through the hall from 26
	frame-spikes to 190; the batch is what fixed that, and `DRAW_BUDGET` is what
	stops it being undone one `MOVING_PARTS` entry at a time.

	A BATCHED BOX IS CHECKED BY ITS CORNERS, which is the only honest way to ask
	"did this box make it in" of a mesh that is no longer a box: every one of its
	eight corners, in its own rotation, must be a vertex of its storey's batch. A
	builder that dropped a box, or placed it by its centre when the table meant its
	corner, or forgot the ramp's tilt, fails here — and none of those would move any
	count at all.
	"""
	var interior := await _make_interior()
	var boxes := TowerInterior.boxes()
	var meshes := _all_meshes(interior)
	if meshes.size() > TowerInterior.DRAW_BUDGET:
		_fail("the interior builds %d meshes, over its declared DRAW_BUDGET of %d" % [
			meshes.size(), TowerInterior.DRAW_BUDGET])
	print("tower interior: %d meshes drawn (budget %d) for %d boxes" % [
		meshes.size(), TowerInterior.DRAW_BUDGET, boxes.size()])

	# The batched vertices of each storey, once, so the corner test below is a set
	# lookup rather than a re-walk of the mesh per box.
	var batch_verts: Array[Dictionary] = [_batch_vertices(interior, 0), _batch_vertices(interior, 1)]

	var want_shapes := 0
	for box: Dictionary in boxes:
		if box["collide"]:
			want_shapes += 1
		var moving: bool = TowerInterior.MOVING_PARTS.has(String(box["name"])) \
				or not is_zero_approx(float(box.get("spin", 0.0)))
		if not moving:
			for corner: Vector3 in _corners(box):
				if not batch_verts[int(box["floor"])].has(_key(corner)):
					_fail("%s's corner %s is in no vertex of storey %d's batch — the box was dropped or misplaced" % [
						box["name"], corner, box["floor"]])
					break
			continue
		var mesh := interior.find_child(String(box["name"]), true, false) as MeshInstance3D
		if mesh == null:
			_fail("no mesh called %s was built" % box["name"])
			continue
		# A rotor bar's world spot is its pivot plus its own local offset.
		var placed: Vector3 = mesh.position
		if mesh.get_parent() != null and String(mesh.get_parent().name).ends_with("Pivot"):
			placed += (mesh.get_parent() as Node3D).position
		if not placed.is_equal_approx(box["pos"]):
			_fail("mesh %s stands at %s but its box says %s" % [box["name"], placed, box["pos"]])
		var box_mesh := mesh.mesh as BoxMesh
		if box_mesh == null or not box_mesh.size.is_equal_approx(box["size"]):
			_fail("mesh %s is not a BoxMesh of size %s" % [box["name"], box["size"]])

	var bodies := 0
	var areas := 0
	var multimeshes := 0
	for child: Node in _descendants(interior):
		if child is MultiMeshInstance3D:
			multimeshes += 1
		elif child is StaticBody3D:
			bodies += 1
		elif child is Area3D:
			areas += 1
	if multimeshes != 0:
		_fail("the interior holds %d MultiMeshInstance3D — it is authored geometry, not chunk content" % multimeshes)
	if bodies != 1:
		_fail("the interior has %d StaticBody3D, expected exactly one" % bodies)
	# Three pads (demand, identity, checkpoint) and one hazard per rotor bar.
	if areas != 5:
		_fail("the interior has %d Area3D, expected 5 (3 pads + 2 rotor hazards)" % areas)

	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	if body == null:
		_fail("the interior has no InteriorCollision body")
	else:
		var shapes := 0
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
		if shapes != want_shapes:
			_fail("the interior body holds %d collision shapes for %d solid boxes" % [shapes, want_shapes])
	if not interior.is_in_group("tower_interior"):
		_fail("the interior did not join the \"tower_interior\" group")
	if interior.get_child_count() < 3:
		_fail("the interior has no per-storey containers — visibility gating has nothing to toggle")
	interior.queue_free()
	await process_frame


func _check_materials_are_shared_and_already_toon() -> void:
	"""
	Check 6. One material per colour for the whole process, and ToonShading refuses
	to copy any of them.

	TWO INTERIORS, SAME MATERIAL OBJECTS — identical, not merely equal, which is the
	only form of the assertion a per-instance `duplicate()` cannot pass. Then hand
	every mesh to `ToonShading.apply_to_mesh()` and assert it changed nothing, which
	states "toon-compatible" as an effect rather than as a property read.
	"""
	var a := await _make_interior()
	var b := await _make_interior()
	var mesh_a := _all_meshes(a)
	var mesh_b := _all_meshes(b)
	var distinct := {}
	for i in mini(mesh_a.size(), mesh_b.size()):
		var mat_a := _material_of(mesh_a[i])
		if mat_a == null:
			_fail("mesh %s has no material" % mesh_a[i].name)
			continue
		if mat_a != _material_of(mesh_b[i]):
			_fail("mesh %s got a private material per instance — the static cache is not being used" % mesh_a[i].name)
		for surface: Material in _materials_of(mesh_a[i]):
			distinct[surface.get_instance_id()] = true

	# One material per colour a MOVING part wears, plus the batch's own two — and no
	# more. A batched box costs no material at all, which is the other half of what
	# the batch bought.
	var colors := {}
	for box: Dictionary in TowerInterior.boxes():
		if TowerInterior.MOVING_PARTS.has(String(box["name"])) \
				or not is_zero_approx(float(box.get("spin", 0.0))):
			colors[box["color"]] = true
	# The checkpoint and the bands each own a second, LIT colour they swap to; those
	# materials exist from the moment anything asks for them.
	var want := colors.size() + 2 + 2
	if distinct.size() > want:
		_fail("the interior holds %d materials, expected at most %d (%d moving colours + 2 lit + 2 batch)" % [
			distinct.size(), want, colors.size()])

	for mesh: MeshInstance3D in mesh_a:
		var before := _material_of(mesh)
		ToonShading.apply_to_mesh(mesh)
		if mesh.get_surface_override_material(0) != null:
			_fail("ToonShading duplicated the material of %s — it is not already DIFFUSE_TOON" % mesh.name)
		if _material_of(mesh) != before:
			_fail("ToonShading replaced the material of %s" % mesh.name)
	a.queue_free()
	b.queue_free()
	await process_frame


func _material_of(mesh: MeshInstance3D) -> Material:
	## A mesh's material — its override, or its first surface's for a batch.
	if mesh.material_override != null:
		return mesh.material_override
	var array_mesh := mesh.mesh as ArrayMesh
	if array_mesh == null or array_mesh.get_surface_count() == 0:
		return null
	return array_mesh.surface_get_material(0)


func _materials_of(mesh: MeshInstance3D) -> Array[Material]:
	## Every material a mesh actually renders with.
	var out: Array[Material] = []
	if mesh.material_override != null:
		out.append(mesh.material_override)
		return out
	var array_mesh := mesh.mesh as ArrayMesh
	if array_mesh == null:
		return out
	for surface in array_mesh.get_surface_count():
		var mat := array_mesh.surface_get_material(surface)
		if mat != null:
			out.append(mat)
	return out


# ============================================================================
# CHECK 7 — the acceptance walk
# ============================================================================

func _check_gate_lifecycle() -> void:
	"""
	Check 7. The bead's acceptance walk, under real physics.

	IN ORDER, because the order is the point:
	  a. Nothing is open to start with, and the moving parts are where the table put
	     them.
	  b. A WRONG HERO stands on the identity pad and nothing happens.
	  c. THE RIGHT HERO STANDS ON THE SAME PAD WITHOUT MOVING and it opens. This is
	     the whole identity-gate contract — E switches character where you stand, so
	     the gate has to re-ask every frame. A `body_entered` latch passes (b) and
	     fails here, which is exactly why (b) and (c) are two steps and not one.
	  d. The mass's MESH AND ITS COLLISION SHAPE both end up risen. A gate that
	     opened only visually is a wall you can see through.
	  e. A short reading at the demand gate opens nothing, moves the shutter
	     partway, lights a PROPORTIONAL number of calibration bands and prints an
	     explanation naming both numbers. Then a reading that meets the demand opens
	     it for good.
	  f. The checkpoint records itself, and all three ids are in the tower's set.
	"""
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("the tower has no TowerInterior child — the interior is not being assembled")
		return

	# (a) the starting state
	if not shell.opened_ids().is_empty():
		_fail("a fresh tower already has gates open: %s" % [shell.opened_ids()])
	var mass := interior.find_child("IdentityMass", true, false) as MeshInstance3D
	var shutter := interior.find_child("DemandShutter", true, false) as MeshInstance3D
	var mass_rest: float = mass.position.y
	var shutter_rest: float = shutter.position.y

	var hero := ProbePlayer.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	hero.add_child(shape)
	hero.add_to_group("player")
	root.add_child(hero)

	# (b) the wrong hero, standing on the pad
	hero.hero = "windman"
	var pad := interior.find_child("IdentityPad", true, false)
	var pad_area := interior.get_node_or_null("Floor1/IdentityTrigger") as Area3D
	if pad_area == null:
		_fail("there is no IdentityTrigger Area3D on the upper storey")
		return
	hero.global_position = pad_area.global_position
	await _settle_physics()
	interior._process(0.1)
	if shell.is_opened(TowerInterior.GATE_IDENTITY):
		_fail("Windman opened the identity gate — it is not keyed on the hero at all")

	# (c) the right hero, WITHOUT MOVING
	hero.hero = "teibi"
	interior._process(0.1)
	if not shell.is_opened(TowerInterior.GATE_IDENTITY):
		_fail("Teibi standing on the identity pad did not open it — the gate latched on who walked in, not on who is standing there")

	# (d) mesh and collision shape both travel
	for _i in 30:
		interior._process(0.1)
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	var mass_shape := body.get_node_or_null("IdentityMassShape") as CollisionShape3D
	if absf(mass.position.y - (mass_rest + TowerInterior.MASS_TRAVEL)) > 0.01:
		_fail("the identity mass stopped at %.2f m, expected %.2f m" % [
			mass.position.y, mass_rest + TowerInterior.MASS_TRAVEL])
	if mass_shape == null or absf(mass_shape.position.y - mass.position.y) > EPS:
		_fail("the identity mass's collision shape did not travel with its mesh — the doorway still has an invisible wall in it")

	# (e) the demand gate: short, then enough
	var demand_area := interior.get_node_or_null("Floor0/DemandTrigger") as Area3D
	if demand_area == null:
		_fail("there is no DemandTrigger Area3D")
		return
	hero.hero = "primm"
	hero.reach = TowerInterior.DEMAND_TARGET * 0.6
	hero.global_position = demand_area.global_position
	await _settle_physics()
	if shell.is_opened(TowerInterior.GATE_DEMAND):
		_fail("a reading of %.1f m opened a gate calibrated to %.1f m" % [
			hero.reach, TowerInterior.DEMAND_TARGET])
	if interior._nudge <= 0.0:
		_fail("the demand gate gave no partway reaction to a deliberate attempt")
	var lit := _lit_bands(interior)
	var want_lit := int(floor(0.6 * float(TowerInterior.DEMAND_BANDS)))
	if lit != want_lit:
		_fail("the calibration ladder lit %d of %d bands for a 60%% reading, expected %d" % [
			lit, TowerInterior.DEMAND_BANDS, want_lit])
	var label := interior.find_child("DemandLabel", true, false) as Label3D
	if label == null or not label.text.contains("%.1f" % TowerInterior.DEMAND_TARGET):
		_fail("the demand gate's explanation does not name the number it wants: %s" % [
			"<no label>" if label == null else label.text])
	# ...and the shutter moved but did not open.
	interior._process(0.05)
	if absf(shutter.position.y - shutter_rest) < EPS:
		_fail("the shutter did not move at all for a partway reading")
	if shutter.position.y < shutter_rest - TowerInterior.SHUTTER_TRAVEL * TowerInterior.NUDGE_FRACTION - EPS:
		_fail("the shutter's partway reaction went further than NUDGE_FRACTION allows")

	# Grow the reading WITHOUT stepping off the plate — the demand gate's half of
	# "keys on who is standing there". The bands relight live as you cycle heroes,
	# so a full ladder on a shut door is the bug this asserts against.
	hero.reach = TowerInterior.DEMAND_TARGET
	interior._process(0.1)
	if not shell.is_opened(TowerInterior.GATE_DEMAND):
		_fail("the reading grew to meet the calibration while the player stood on the plate and the vault stayed shut")
	if _lit_bands(interior) != TowerInterior.DEMAND_BANDS:
		_fail("the calibration ladder did not relight when the reading changed under a standing player")
	for _i in 30:
		interior._process(0.1)
	var shutter_shape := body.get_node_or_null("DemandShutterShape") as CollisionShape3D
	if absf(shutter.position.y - (shutter_rest - TowerInterior.SHUTTER_TRAVEL)) > 0.01:
		_fail("the shutter stopped at %.2f m, expected %.2f m" % [
			shutter.position.y, shutter_rest - TowerInterior.SHUTTER_TRAVEL])
	if shutter_shape == null or absf(shutter_shape.position.y - shutter.position.y) > EPS:
		_fail("the shutter's collision shape did not sink with its mesh — the vault is still walled off")
	if _lit_bands(interior) != TowerInterior.DEMAND_BANDS:
		_fail("an open demand gate does not show a full calibration ladder")

	# (f) the checkpoint
	var check_area := interior.get_node_or_null("Floor1/CheckpointTrigger") as Area3D
	if check_area == null:
		_fail("there is no CheckpointTrigger Area3D")
		return
	hero.global_position = check_area.global_position
	await _settle_physics()
	if not shell.is_opened(TowerInterior.GATE_CHECKPOINT):
		_fail("standing on the checkpoint did not record it")
	var plate := interior.find_child("CheckpointPlate", true, false) as MeshInstance3D
	if plate.material_override != TowerInterior._material(TowerInterior.COLOR_CHECKPOINT_LIT):
		_fail("the checkpoint did not light up when it was reached")

	var want := [TowerInterior.GATE_CHECKPOINT, TowerInterior.GATE_DEMAND, TowerInterior.GATE_IDENTITY]
	want.sort()
	if shell.opened_ids() != want:
		_fail("the tower's opened set is %s, expected %s" % [shell.opened_ids(), want])

	# And a rotor bar still costs a life, which is the challenge space's whole stake.
	var hazard := interior.find_child("RotorBarLowHazard", true, false) as Area3D
	if hazard == null:
		_fail("the rotor bars carry no hazard volume — the challenge space is decorative")
	else:
		hero.global_position = check_area.global_position + Vector3(0.0, 0.0, 40.0)
		await _settle_physics()
		hero.global_position = hazard.global_position
		await _settle_physics()
		if hero.hits == 0:
			_fail("a rotor bar swept through the player and cost nothing")

	hero.queue_free()
	shell.queue_free()
	await process_frame


func _check_opened_state_is_reapplied() -> void:
	"""
	Check 8. A tower that already knows its gates are open comes up open, before the
	first frame and with no animation.

	THIS IS THE ACCEPTANCE'S "walk out and back in" AS A PROPERTY OF THE CODE. In
	play nothing is freed, so that walk would pass even if `_apply_opened()` did
	nothing at all — which is precisely the mutant this check exists to kill, and
	precisely the seam phase 5 will load a save through. So the check does what
	nothing in play does: it pre-loads the set on the shell and asserts the geometry
	that comes out.
	"""
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.opened = {
		TowerInterior.GATE_DEMAND: true,
		TowerInterior.GATE_IDENTITY: true,
		TowerInterior.GATE_CHECKPOINT: true,
	}
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	root.add_child(shell)
	await process_frame

	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var mass := interior.find_child("IdentityMass", true, false) as MeshInstance3D
	var shutter := interior.find_child("DemandShutter", true, false) as MeshInstance3D
	var plate := interior.find_child("CheckpointPlate", true, false) as MeshInstance3D
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D

	var table := TowerInterior.boxes()
	var mass_rest := 0.0
	var shutter_rest := 0.0
	for box: Dictionary in table:
		if box["name"] == "IdentityMass":
			mass_rest = box["pos"].y
		elif box["name"] == "DemandShutter":
			shutter_rest = box["pos"].y

	if absf(mass.position.y - (mass_rest + TowerInterior.MASS_TRAVEL)) > EPS:
		_fail("a pre-opened tower rebuilt its identity mass shut (y = %.2f, wanted %.2f)" % [
			mass.position.y, mass_rest + TowerInterior.MASS_TRAVEL])
	if absf(shutter.position.y - (shutter_rest - TowerInterior.SHUTTER_TRAVEL)) > EPS:
		_fail("a pre-opened tower rebuilt its vault shutter shut (y = %.2f, wanted %.2f)" % [
			shutter.position.y, shutter_rest - TowerInterior.SHUTTER_TRAVEL])
	if plate.material_override != TowerInterior._material(TowerInterior.COLOR_CHECKPOINT_LIT):
		_fail("a pre-opened tower rebuilt its checkpoint unlit")
	var mass_shape := body.get_node_or_null("IdentityMassShape") as CollisionShape3D
	if mass_shape == null or absf(mass_shape.position.y - mass.position.y) > EPS:
		_fail("a pre-opened tower left the identity mass's collision shape in the doorway")
	var shutter_shape := body.get_node_or_null("DemandShutterShape") as CollisionShape3D
	if shutter_shape == null or absf(shutter_shape.position.y - shutter.position.y) > EPS:
		_fail("a pre-opened tower left the shutter's collision shape sealing the vault")

	# The set itself is monotone and idempotent — phase 5 merges these with a union.
	shell.mark_opened(TowerInterior.GATE_DEMAND)
	if shell.opened_ids().size() != 3:
		_fail("marking an already-open gate changed the set size to %d" % shell.opened_ids().size())
	if not shell.is_opened(TowerInterior.GATE_DEMAND) or shell.is_opened("tower_nonexistent"):
		_fail("is_opened() does not answer the set")

	shell.queue_free()
	await process_frame


# ============================================================================
# CHECK 9 — visibility gating
# ============================================================================

func _check_visibility_gating() -> void:
	"""
	Check 9. The policy, then the rig.

	THE POLICY IS DRIVEN AT STOREY COUNTS THIS BUILDING DOES NOT HAVE, on purpose.
	With two storeys the current-floor +/- 1 window hides nothing, so a live test can
	only ever assert "everything is visible" — which passes whatever the policy says.
	Phase 8's cell block is what makes the window bite, and it should inherit a gate
	that was already correct rather than discover it needs one.
	"""
	for current in 5:
		for index in 5:
			var want := absi(index - current) <= 1
			if TowerInterior._floor_visible(index, current) != want:
				_fail("floor %d should be %s while standing on floor %d" % [
					index, "visible" if want else "hidden", current])
	if TowerInterior.current_floor(0.0) != 0:
		_fail("standing on the ground floor did not read as storey 0")
	if TowerInterior.current_floor(TowerInterior.SLAB_Y) != 1:
		_fail("standing on the upper slab did not read as storey 1")
	if TowerInterior.current_floor(TowerInterior.SLAB_Y - TowerInterior.FLOOR_HYSTERESIS - 0.1) != 0:
		_fail("the storey boundary ignores FLOOR_HYSTERESIS")

	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var hero := ProbePlayer.new()
	hero.add_to_group("player")
	root.add_child(hero)

	hero.global_position = Vector3(TowerInterior.DRAW_RADIUS * 4.0, 0.0, 0.0)
	interior._process(0.05)
	if interior.visible:
		_fail("the interior still draws with the player %.0f m away" % (TowerInterior.DRAW_RADIUS * 4.0))

	hero.global_position = shell.global_position + Vector3(4.0, 0.0, 0.0)
	interior._process(0.05)
	if not interior.visible:
		_fail("the interior does not draw with the player standing inside it")
	for i in 2:
		var floor_node := interior.get_node_or_null("Floor%d" % i) as Node3D
		if floor_node == null or not floor_node.visible:
			_fail("storey %d is hidden from a player standing on the ground floor of a two-storey building" % i)

	hero.queue_free()
	shell.queue_free()
	await process_frame


# ============================================================================
# HELPERS
# ============================================================================

func _make_interior() -> Node3D:
	## A bare interior in the tree — no shell above it, so `_tower()` finds nothing
	## and every gate reads shut. That is what checks 5 and 6 want: the geometry, with
	## no state.
	var interior := load(INTERIOR_SCENE).instantiate() as Node3D
	root.add_child(interior)
	await process_frame
	return interior


func _make_tower() -> Node3D:
	## Shell plus interior, assembled the way endless_terrain assembles them — the
	## interior added BEFORE the shell enters the tree, so it can see its parent.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	root.add_child(shell)
	await process_frame
	return shell


func _batch_vertices(interior: Node3D, floor_index: int) -> Dictionary:
	## Every vertex of one storey's batch, as a set of quantized keys.
	var out := {}
	var batch := interior.get_node_or_null("Floor%d/Floor%dBatch" % [floor_index, floor_index]) as MeshInstance3D
	if batch == null or batch.mesh == null:
		_fail("storey %d has no batched mesh" % floor_index)
		return out
	var mesh: ArrayMesh = batch.mesh
	for surface in mesh.get_surface_count():
		if mesh.surface_get_material(surface) == null:
			_fail("storey %d's batch surface %d has no material" % [floor_index, surface])
		for vertex: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			out[_key(vertex)] = true
	return out


func _corners(box: Dictionary) -> Array[Vector3]:
	## A box's eight corners in interior space, tilt included.
	var half: Vector3 = box["size"] * 0.5
	var basis := Basis.from_euler(box["rot"]) if box.has("rot") else Basis.IDENTITY
	var placed := Transform3D(basis, box["pos"])
	var out: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(placed * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


func _key(v: Vector3) -> String:
	## A vertex's identity, rounded so float noise from a rotation cannot miss.
	return "%.3f|%.3f|%.3f" % [v.x, v.y, v.z]


func _all_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in _descendants(node):
		if child is MeshInstance3D:
			out.append(child)
	return out


func _descendants(node: Node) -> Array[Node]:
	## Everything under `node`, EXCEPT the vault's gem.
	##
	## The gem is `coin.tscn` — a foreign scene with its own Area3D and its own
	## MeshInstance3D, deliberately reused rather than reinvented. Counting its parts
	## as the interior's would make every count in checks 5 and 6 off by one and,
	## worse, hand its material to the ToonShading assertion, which is a claim about
	## the tower's palette and not about the collectible's.
	var out: Array[Node] = []
	for child: Node in node.get_children():
		if String(child.name) == "VaultGem":
			continue
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _lit_bands(interior: TowerInterior) -> int:
	## How many calibration bands are currently showing the lit material.
	var lit := 0
	var on := TowerInterior._material(TowerInterior.COLOR_BAND_LIT)
	for i in TowerInterior.DEMAND_BANDS:
		var band := interior.find_child("Band%d" % (i + 1), true, false) as MeshInstance3D
		if band != null and band.material_override == on:
			lit += 1
	return lit


func _overlaps(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3) -> bool:
	## Axis-aligned three-interval overlap, with a tolerance so two boxes that merely
	## share a face do not read as intersecting.
	const TOUCH: float = 0.001
	var a := a_size * 0.5
	var b := b_size * 0.5
	return absf(a_pos.x - b_pos.x) < a.x + b.x - TOUCH \
			and absf(a_pos.y - b_pos.y) < a.y + b.y - TOUCH \
			and absf(a_pos.z - b_pos.z) < a.z + b.z - TOUCH


func _settle_physics() -> void:
	## Four physics frames — the number `tower_shell_selfcheck` MEASURED: a body added
	## and positioned in the same frame is reported by an area on the THIRD frame, so
	## two reads as "nothing fired" and passes every mutant.
	for _i in 4:
		await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
