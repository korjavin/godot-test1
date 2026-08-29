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
##   3. **THE DEMAND IS ACTUALLY REACHABLE.** Check 3a derives one rank of Long
##      Step from `Progression.SKILL_TREES` and `PRIMM_BLINK_DISTANCE` and asserts
##      the gate opens for it, because it once did not: 6.0 x 1.20 is
##      7.199999999999999 and a bare `>=` against 7.2 refused the exact rank the
##      gate advertises, while printing "needs 7.2 m, reads 7.2 m". Nothing
##      structural noticed; playing the game did.
##   3b. THE RAMP IS THE STAIR, AND IT IS FLUSH. Godot's CharacterBody3D has no
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
##   8. **EARNED STATE SURVIVES THE PROCESS.** Check 10 is phase 5's acceptance,
##      driven headlessly: open a gate, throw the tower away, build a new one, and
##      the gate is open — geometry and all. Then a second writer stores an id
##      this tower never heard of and the tower opens another, and BOTH survive,
##      because the merge is a union and not an overwrite. The stale-copy case is
##      the one a naive check misses: a store that simply overwrote would pass
##      every round-trip assertion above it and still silently re-lock a gate
##      somebody earned.
##   9. VISIBILITY GATING. Check 9 drives the policy directly at storey counts this
##      building does not have (so phase 8 inherits a correct gate rather than
##      discovering it needs one) and then confirms the live rig hides the whole
##      interior from across the field and shows it from inside.
##  10. **THE CELL BLOCK HAS NO WAY ROUND IT.** Check 11 is phase 8's structural
##      half, and it exists because a gap in the spine wall would not look like a
##      bug — it would look like a corridor. The four rescue spines are the ONLY
##      thing `tower_selfcheck`'s softlock audit has to work with; a 12 cm slot
##      beside a pier makes every identity gate in the wing decorative and turns
##      that audit's SELFCHECK OK into a statement about a building nobody built.
##      So the spine line and the cell row are SAMPLED for solidity rather than
##      derived from the same arithmetic that placed them.
##  11. **THE WING'S ACCEPTANCE WALK.** Check 12: a spine door refuses the wrong
##      hero and opens for the right one standing still; its mass and its shape
##      sink together; ANY hero walking into an occupied cell frees the captive,
##      the frame goes dark, the authored staging disappears — and stays gone
##      across a rebuilt tower, because that one fact is the only liberation state
##      that persists.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"
## The AI's SPECIES table, for check 12's "which row did this body actually
## resolve" test. Read rather than restated, so a renamed row fails by name.
const CROC_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"

## Throwaway save file this check points `BestRunStore.config_path` at for its
## whole run. NOTHING HERE MAY OPEN THE MACHINE'S `user://best_run.cfg`: a shell
## hydrates from the store on entering the tree and WRITES THROUGH on every gate
## it opens, so without the redirect checks 7, 8 and 10 would each store tower
## ids into a developer's real profile — the trap `progression_selfcheck.gd`
## documents at length, one step worse because this one writes.
const LOCAL_STORE_PATH: String = "user://tower_interior_selfcheck_best_run.cfg"

## An id no gate in this game has. Check 10 uses it as "what a second writer
## already put on disk", which is the stale copy the union has to survive.
const FOREIGN_ID: String = "tower_selfcheck_foreign_stop"

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
	## Every hero the tower told this player it had freed, in order. The phase-9
	## seam: `TowerInterior._liberate` calls `hero_freed` only when the player has
	## one, so today's real player is never told and nobody is ever locked out —
	## and check 12 asserts the call HAPPENS, which is the half a null-safe seam
	## normally cannot prove.
	var freed: Array[String] = []

	func hero_name() -> String:
		return hero

	func phase_reach() -> float:
		return reach

	func hit_by_crocodile(_attacker: Node = null) -> void:
		hits += 1

	func hero_freed(who: String) -> void:
		freed.append(who)


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# THE STORE SEAM FIRST, before any shell can exist — see LOCAL_STORE_PATH.
	BestRunStore.config_path = LOCAL_STORE_PATH
	_fresh_store()
	# ONE FRAME BEFORE ANYTHING — a node added to `root` from inside _initialize()
	# is not `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (tower_shell_selfcheck's note).
	await process_frame
	await _run()


func _run() -> void:
	_check_plan_fits_the_shell()
	_check_no_jump_gated_climb()
	_check_the_demand_is_actually_reachable()
	_check_ramp_is_the_stair()
	await _check_headroom_clears_the_camera()
	await _check_node_shape()
	await _check_materials_are_shared_and_already_toon()
	await _check_gate_lifecycle()
	await _check_opened_state_is_reapplied()
	await _check_visibility_gating()
	await _check_earned_state_survives_a_relaunch()
	_check_the_wing_has_no_way_round_it()
	await _check_spines_and_liberation()
	await _check_guards_stand_their_posts()
	await _check_guards_reset_on_re_entry()
	await _check_the_leash_holds_under_a_chase()
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

func _check_the_demand_is_actually_reachable() -> void:
	"""
	Check 3a. The reading the demand gate's own comment promises — one rank of Long
	Step — really does open it, computed the way the game computes it.

	THIS CHECK EXISTS BECAUSE THE GATE ONCE REFUSED IT. `PRIMM_BLINK_DISTANCE` times
	one rank's 1.20 is 7.199999999999999, `DEMAND_TARGET` is 7.2, and a bare `>=`
	turned "a skill point away" into "unreachable" while the label read
	"needs 7.2 m, reads 7.2 m" — a lie no structural assertion in this file noticed
	and only playing the game found. So the number is now DERIVED from
	`Progression.SKILL_TREES` and `player_controller` rather than restated: retune
	Long Step, or the blink, or the demand, and this says whether the gate is still
	a rank away or has quietly become a wall.
	"""
	var per_rank := 0.0
	var max_ranks := 0
	for node: Dictionary in Progression.SKILL_TREES.get("primm", []):
		if String(node.get("effect", "")) == "primm_blink":
			per_rank = float(node.get("per_rank", 0.0))
			max_ranks = int(node.get("max_ranks", 0))
	if per_rank <= 0.0:
		_fail("primm has no primm_blink skill node — the demand gate is calibrated against nothing")
		return
	var base: float = float(load(PLAYER_SCRIPT).get_script_constant_map().get("PRIMM_BLINK_DISTANCE", 0.0))
	var one_rank := base * (1.0 + per_rank)
	var maxed := base * (1.0 + per_rank * float(max_ranks))
	print("phase reach: base %.4f, one rank %.4f, maxed %.4f; demand %.2f" % [
		base, one_rank, maxed, TowerInterior.DEMAND_TARGET])

	if TowerInterior.demand_met(base):
		_fail("an UNSKILLED Primm already meets the demand (%.4f >= %.2f) — the gate demands nothing" % [
			base, TowerInterior.DEMAND_TARGET])
	if not TowerInterior.demand_met(one_rank):
		_fail("one rank of Long Step reads %.15f and the gate wants %.2f — it refuses the very rank it advertises" % [
			one_rank, TowerInterior.DEMAND_TARGET])
	if not TowerInterior.demand_met(maxed):
		_fail("a MAXED Primm cannot open the demand gate — it is a wall, not a demand")
	# And the ladder must agree with the door: a passing reading fills it.
	if TowerInterior.demand_ratio(one_rank) < 1.0:
		_fail("the calibration ladder is short of full (%.4f) on a reading that opens the gate" % [
			TowerInterior.demand_ratio(one_rank)])
	if TowerInterior.demand_ratio(base) >= 1.0:
		_fail("the ladder reads full for an unskilled Primm")


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
		if box.has("sweep"):
			# A SWEPT PART IS MOVING ON THE FRAME THIS CHECK READS IT, so its table
			# position is the top of its stroke and not where it is now — asserting
			# equality would fail on correct geometry the first time the clock ticked.
			# The two axes it never moves on are still exact, and the one it does move
			# on is held to the stroke `press_y` is allowed to produce. That is a
			# STRICTER statement than the equality it replaces: a press mis-built a
			# metre off, or animated past its own lintel, fails here.
			if not is_equal_approx(placed.x, box["pos"].x) \
					or not is_equal_approx(placed.z, box["pos"].z):
				_fail("swept mesh %s stands at %s but its box says %s (x/z must not move)" % [
					box["name"], placed, box["pos"]])
			var top := TowerInterior.PRESS_TOP
			var bottom := TowerInterior.PRESS_BOTTOM
			if placed.y < bottom - EPS or placed.y > top + EPS:
				_fail("swept mesh %s is at y = %.4f, outside its %.2f .. %.2f stroke" % [
					box["name"], placed.y, bottom, top])
		elif not placed.is_equal_approx(box["pos"]):
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
	# Three pads (demand, identity, checkpoint), one hazard per rotor bar, and the
	# wing's own: four spine pads, four cell volumes and the crawl press's hazard.
	# COUNTED AND NOT CAPPED — an Area3D nobody meant to build is a trigger that
	# fires, and every one of these fourteen is named in this file.
	var want_areas := 5 + TowerInterior.SPINE_DOORS.size() + TowerGraph.HEROES.size() + 1
	if areas != want_areas:
		_fail("the interior has %d Area3D, expected %d (3 pads + 2 rotor hazards + %d spine pads + %d cells + 1 press)" % [
			areas, want_areas, TowerInterior.SPINE_DOORS.size(), TowerGraph.HEROES.size()])

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
	# The checkpoint, the bands and the cell frames each own a second colour they
	# swap to (lit, lit, and DARK for a cell that has been emptied); those materials
	# exist from the moment anything asks for them.
	const SWAPPED: int = 3
	var want := colors.size() + SWAPPED + 2
	if distinct.size() > want:
		_fail("the interior holds %d materials, expected at most %d (%d moving colours + %d swapped + 2 batch)" % [
			distinct.size(), want, colors.size(), SWAPPED])

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
	# This check asserts "a fresh tower has nothing open", so it starts from a
	# profile that has nothing in it — an earlier check's write-through would
	# otherwise hydrate straight into the assertion.
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("the tower has no TowerInterior child — the interior is not being assembled")
		await _clear(null, shell)
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
		await _clear(hero, shell)
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
		await _clear(hero, shell)
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
		await _clear(hero, shell)
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
	_fresh_store()  # the set below is meant to be the WHOLE set — see check 7's note
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
	## Everything under `node`, EXCEPT the vault's gem and the guards.
	##
	## The gem is `coin.tscn` — a foreign scene with its own Area3D and its own
	## MeshInstance3D, deliberately reused rather than reinvented. Counting its parts
	## as the interior's would make every count in checks 5 and 6 off by one and,
	## worse, hand its material to the ToonShading assertion, which is a claim about
	## the tower's palette and not about the collectible's.
	##
	## `Guards` is the same exclusion for the same reason, one bead later:
	## `tower_guard.tscn` is a foreign scene too — the shared predator script, a
	## `.glb` chassis and its own collision body — and its meshes are styled by the
	## AI's own `_style_model_meshes` at run time, exactly like every other predator
	## in the world. Counting them would put the building over a DRAW_BUDGET that is
	## a claim about STATIC GEOMETRY (see check 5's docstring: the batch, the 67
	## draw calls, the frame spikes), and would hand a `.glb`'s materials to a
	## palette assertion they were never part of. The guards are not unmeasured for
	## it — check 12 counts and places them, and check 13 resets them.
	var out: Array[Node] = []
	for child: Node in node.get_children():
		if String(child.name) == "VaultGem" or String(child.name) == "Guards":
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


func _clear(hero: Node, shell: Node) -> void:
	"""
	Free a check's probe player and tower before bailing out.

	NOT TIDINESS. A check that `return`s on a failure and leaves its probe in the
	tree leaves a second node in group "player", and the next check's
	`get_first_node_in_group("player")` picks one of them at random — so one real
	failure grows a train of invented ones in checks that are fine. (Happened while
	this file was being written: a missing `IdentityTrigger` reported itself as "the
	interior still draws with the player 240 m away".)
	"""
	if hero != null:
		hero.queue_free()
	if shell != null:
		shell.queue_free()
	await process_frame


func _settle_physics() -> void:
	## Four physics frames — the number `tower_shell_selfcheck` MEASURED: a body added
	## and positioned in the same frame is reported by an area on the THIRD frame, so
	## two reads as "nothing fired" and passes every mutant.
	for _i in 4:
		await physics_frame


# ============================================================================
# CHECK 10 — the earned state survives the process (bead godot-test1-3iy.5)
# ============================================================================

func _check_earned_state_survives_a_relaunch() -> void:
	"""
	Check 10. Open a gate, quit, relaunch: the gate is still open. Then merge with
	a stale copy and lose nothing.

	THE ACCEPTANCE, DRIVEN HEADLESSLY. Check 8 proves the tower comes up open when
	the set is HANDED to it; this proves the set gets there on its own, across a
	tower that no longer exists. The two halves are separate on purpose — check 8
	still passes with no save layer at all.

	(c) IS THE HALF A NAIVE CHECK MISSES, and it is the one the landmine is about.
	A store that wrote the tower's own set over the file instead of merging into it
	passes every round-trip assertion above — the gate you just opened is in the
	set you just wrote — while silently dropping anything a second writer stored in
	between. Since the set is monotone, dropping an id IS re-locking a gate
	somebody earned, which is exactly what must never happen. So the check puts a
	foreign id on disk behind this tower's back and demands both survive.
	"""
	_fresh_store()

	# --- (a) a fresh profile builds a shut tower, and opening a gate reaches disk ---
	var first := await _make_tower()
	if not first.opened_ids().is_empty():
		_fail("a tower built against an empty save came up with %s already open" % [
			first.opened_ids()])
	first.mark_opened(TowerInterior.GATE_IDENTITY)
	var written := BestRunStore.tower_opened_ids()
	if written.size() != 1 or written[0] != TowerInterior.GATE_IDENTITY:
		_fail("opening a gate never reached the save — the store holds %s" % [written])
	# "Quit." Nothing of this run's tower survives into the next one: the shell IS
	# the in-memory set, so freeing it is the strongest form of the quit.
	first.queue_free()
	await process_frame

	# --- (b) "relaunch": a brand-new tower, open, geometry and all ---
	var second := await _make_tower()
	if not second.is_opened(TowerInterior.GATE_IDENTITY):
		_fail("a gate opened before the quit came back shut after the relaunch")
	var interior := second.get_node_or_null("TowerInterior") as TowerInterior
	var mass := interior.find_child("IdentityMass", true, false) as MeshInstance3D
	var mass_rest := 0.0
	for box: Dictionary in TowerInterior.boxes():
		if box["name"] == "IdentityMass":
			mass_rest = box["pos"].y
	if absf(mass.position.y - (mass_rest + TowerInterior.MASS_TRAVEL)) > EPS:
		_fail("the relaunched tower knew the gate was open and rebuilt the mass shut (y = %.2f, wanted %.2f)" % [
			mass.position.y, mass_rest + TowerInterior.MASS_TRAVEL])

	# --- (c) the stale copy: a second writer stores an id this tower never saw ---
	BestRunStore.merge_tower_opened_ids([FOREIGN_ID])
	second.mark_opened(TowerInterior.GATE_DEMAND)
	var merged := BestRunStore.tower_opened_ids()
	for want: String in [TowerInterior.GATE_IDENTITY, TowerInterior.GATE_DEMAND, FOREIGN_ID]:
		if not merged.has(want):
			_fail("the merge dropped %s — it overwrote instead of unioning, so the store holds %s" % [
				want, merged])
	second.queue_free()
	await process_frame

	# --- (d) the bound, at both ends ---
	# MAX + 8 candidates on top of the three real ids, so an unbounded store would
	# come back well past the cap and a bounded one lands exactly on it.
	var bulk: Array[String] = []
	for i in BestRunStore.MAX_TOWER_IDS + 8:
		bulk.append("tower_selfcheck_bulk_%d" % i)
	BestRunStore.merge_tower_opened_ids(bulk)
	var bounded := BestRunStore.tower_opened_ids()
	if bounded.size() != BestRunStore.MAX_TOWER_IDS:
		_fail("the stored tower set is %d ids, not the %d bound" % [
			bounded.size(), BestRunStore.MAX_TOWER_IDS])

	# --- (e) a corrupt or hand-edited record reads as "nothing earned" ---
	_fresh_store()
	var cfg := ConfigFile.new()
	cfg.set_value(BestRunStore.CONFIG_TOWER_SECTION, BestRunStore.CONFIG_TOWER_KEY,
		"{not json at all")
	cfg.save(LOCAL_STORE_PATH)
	if not BestRunStore.tower_opened_ids().is_empty():
		_fail("a corrupt tower record read as opened gates: %s" % [
			BestRunStore.tower_opened_ids()])
	# A well-formed array with junk in it keeps the good entries and drops the rest,
	# including the duplicate — this is a SET.
	cfg.set_value(BestRunStore.CONFIG_TOWER_SECTION, BestRunStore.CONFIG_TOWER_KEY,
		JSON.stringify(["tower_ok", 5, "", "tower_ok", {"a": 1}]))
	cfg.save(LOCAL_STORE_PATH)
	var salvaged := BestRunStore.tower_opened_ids()
	if salvaged.size() != 1 or salvaged[0] != "tower_ok":
		_fail("a half-junk tower record did not salvage to exactly its one real id: %s" % [
			salvaged])
	_fresh_store()


# ============================================================================
# CHECK 11 — the cell block has no way round it (bead godot-test1-3iy.8)
# ============================================================================

func _check_the_wing_has_no_way_round_it() -> void:
	"""
	Check 11. The wing's two runs tile exactly, every spine mass really fills its
	doorway, and the press is a challenge rather than a formality.

	WHY SAMPLING AND NOT ARITHMETIC. `_spine_door_x` and `_spine_pier_x` are derived
	from the same two widths, so asserting they add up would be asking the formula
	whether it agrees with itself. What matters is the WORLD: walk the spine line in
	5 cm steps and ask the box table whether there is stone or a shut mass at head
	height. A pier one width short, a mass narrower than its doorway, a fifth door
	authored into a four-door span — all of them are a hole, and a hole in that wall
	is a route the softlock audit does not model and cannot see.
	"""
	var span := TowerInterior.wing_span()
	var doors := TowerInterior.SPINE_DOORS.size()
	var laid := float(doors) * TowerInterior.SPINE_DOOR_W \
			+ float(doors - 1) * TowerInterior.SPINE_PIER_W
	if absf(laid - span) > EPS:
		_fail("%d spine doors and %d piers lay out %.3f m across a %.3f m wing" % [
			doors, doors - 1, laid, span])
	var cells := TowerGraph.HEROES.size()
	var cells_laid := float(cells) * TowerInterior._cell_width() \
			+ float(cells - 1) * TowerInterior.CELL_DIVIDER
	if absf(cells_laid - span) > EPS:
		_fail("%d cells and %d dividers lay out %.3f m across a %.3f m wing" % [
			cells, cells - 1, cells_laid, span])

	# (a) The spine line is solid from end to end while every gate is shut. Head
	#     height, because that is where a gap would be walked through.
	var head := TowerInterior.headroom() * 0.5
	var x := TowerInterior.SLAB_X0 + 0.02
	while x < TowerInterior.INNER_HALF:
		if not _solid_at(x, TowerInterior.SPINE_Z, head):
			_fail("the spine wall has a hole at x = %.2f — the four identity gates can be walked round" % x)
			break
		x += 0.05
	# ...and the cell row, so a captive's recess is a recess and not a through-way.
	x = TowerInterior.SLAB_X0 + 0.02
	var open_run := 0.0
	var widest := 0.0
	while x < TowerInterior.INNER_HALF:
		if _solid_at(x, TowerInterior.INNER_HALF - 0.5, head):
			open_run = 0.0
		else:
			open_run += 0.05
			widest = maxf(widest, open_run)
		x += 0.05
	# The widest unbroken opening across the cells' back line must be one cell, not
	# two: a missing divider reads as a cell block with a corridor behind it.
	if widest > TowerInterior._cell_width() + 0.1:
		_fail("the cell row has a %.2f m unbroken opening but a cell is %.2f m — a divider is missing" % [
			widest, TowerInterior._cell_width()])

	# (b) Every mass fills its doorway to the ceiling and stands in the spine line.
	var by_name := {}
	for box: Dictionary in TowerInterior.boxes():
		by_name[String(box["name"])] = box
	var wanted: Array[String] = []
	for i in doors:
		var door: Dictionary = TowerInterior.SPINE_DOORS[i]
		var gid := String(door["gate"])
		var gate: Dictionary = TowerGraph.gate(gid)
		if String(gate.get("class", "")) != TowerGraph.CLASS_IDENTITY:
			_fail("the building's spine door '%s' is not an identity gate in TOWER_GRAPH" % gid)
			continue
		var who := String(gate["identity"])
		if wanted.has(who):
			_fail("two spine doors both open for %s — one hero has two spines and another has none" % who)
		wanted.append(who)
		var mass: Dictionary = by_name.get(String(door["mass"]), {})
		if mass.is_empty():
			_fail("spine door '%s' names a mass '%s' the interior does not build" % [
				gid, String(door["mass"])])
			continue
		if not is_equal_approx(mass["size"].x, TowerInterior.SPINE_DOOR_W):
			_fail("%s is %.2f m wide in a %.2f m doorway — you can walk past it" % [
				String(door["mass"]), mass["size"].x, TowerInterior.SPINE_DOOR_W])
		if not is_equal_approx(mass["size"].y, TowerInterior.headroom()):
			_fail("%s is %.2f m tall under a %.2f m ceiling — you can get over it" % [
				String(door["mass"]), mass["size"].y, TowerInterior.headroom()])
		if not is_equal_approx(mass["pos"].x, TowerInterior._spine_door_x(i)):
			_fail("%s stands at x = %.3f, not in doorway %d at x = %.3f" % [
				String(door["mass"]), mass["pos"].x, i, TowerInterior._spine_door_x(i)])
	for hero: String in TowerGraph.HEROES:
		if not wanted.has(hero):
			_fail("no spine door in the building opens for %s — his rescue spine is not built" % hero)

	# (c) A sunk mass leaves NOTHING in its doorway. A lip of any height is a wall
	#     in this engine, so "nearly flush" is the same bug as "shut".
	var open_top := TowerInterior.headroom() * 0.5 - TowerInterior.SPINE_TRAVEL \
			+ TowerInterior.headroom() * 0.5
	if open_top > 0.0:
		_fail("a fully sunk spine mass still stands %.3f m proud of the floor — that is a step, and this engine has no step-up" % open_top)

	# (d) The press: it must actually close the crawl, and it must actually open it.
	var press: Dictionary = by_name.get("CrawlPress", {})
	if press.is_empty():
		_fail("the maintenance crawl has no press — the challenge gate is decorative")
		return
	# WHERE it is, before HOW it moves. Check 5 only asserts the mesh agrees with
	# its own table row, so a row nudged sideways builds a press in the middle of a
	# wall and satisfies every assertion about itself.
	var press_half: Vector3 = press["size"] * 0.5
	if press["pos"].x - press_half.x < TowerInterior.CRAWL_X0 - EPS \
			or press["pos"].x + press_half.x > TowerInterior.CRAWL_X1 + EPS:
		_fail("the press spans x = %.2f .. %.2f but the crawl doorway is %.2f .. %.2f — it stamps a wall" % [
			press["pos"].x - press_half.x, press["pos"].x + press_half.x,
			TowerInterior.CRAWL_X0, TowerInterior.CRAWL_X1])
	if not is_equal_approx(press["pos"].z, TowerInterior.WING_Z):
		_fail("the press stands at z = %.2f, not on the wing wall at z = %.2f" % [
			press["pos"].z, TowerInterior.WING_Z])
	var half_h: float = press["size"].y * 0.5
	if TowerInterior.PRESS_BOTTOM - half_h > EPS:
		_fail("the press bottoms out %.2f m off the floor — you can walk under it and the crawl asks nothing" % (
			TowerInterior.PRESS_BOTTOM - half_h))
	var gap := TowerInterior.PRESS_TOP - half_h
	if gap < PLAYER_HEIGHT:
		_fail("the press leaves only %.2f m under it at the top of its stroke — a %.1f m player can never get through" % [
			gap, PLAYER_HEIGHT])
	if TowerInterior.PRESS_TOP + half_h > TowerInterior.CRAWL_LINTEL_Y + EPS:
		_fail("the press rises to %.2f m through a lintel at %.2f m" % [
			TowerInterior.PRESS_TOP + half_h, TowerInterior.CRAWL_LINTEL_Y])
	# The stroke reaches both ends and never leaves them.
	var lowest := TowerInterior.PRESS_TOP
	var highest := TowerInterior.PRESS_BOTTOM
	for step in 200:
		var y := TowerInterior.press_y(TowerInterior.PRESS_PERIOD * float(step) / 200.0)
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	if lowest < TowerInterior.PRESS_BOTTOM - EPS or highest > TowerInterior.PRESS_TOP + EPS:
		_fail("press_y ranges %.3f .. %.3f, outside its declared %.2f .. %.2f stroke" % [
			lowest, highest, TowerInterior.PRESS_BOTTOM, TowerInterior.PRESS_TOP])
	if absf(lowest - TowerInterior.PRESS_BOTTOM) > 0.01 or absf(highest - TowerInterior.PRESS_TOP) > 0.01:
		_fail("press_y only sweeps %.3f .. %.3f of its %.2f .. %.2f stroke — the crawl is never really shut or never really open" % [
			lowest, highest, TowerInterior.PRESS_BOTTOM, TowerInterior.PRESS_TOP])
	print("cell block: %d spine doors of %.2f m, %d cells of %.2f m across %.2f m; press %.2f .. %.2f m" % [
		doors, TowerInterior.SPINE_DOOR_W, cells, TowerInterior._cell_width(), span,
		TowerInterior.PRESS_BOTTOM, TowerInterior.PRESS_TOP])


func _solid_at(x: float, z: float, y: float) -> bool:
	"""
	Is there a solid interior box at this point, with every gate SHUT?

	@return: true when some collidable, untilted box in `boxes()` contains it.

	`boxes()` is the plan in its closed state, which is exactly the state check 11
	wants: the question is whether a route exists BEFORE anybody opens anything.
	The ramp is skipped for the same reason check 2 skips it — a tilted slab's AABB
	claims stone it does not have.
	"""
	for box: Dictionary in TowerInterior.boxes():
		if not box["collide"] or box.has("rot"):
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if absf(pos.x - x) <= half.x and absf(pos.z - z) <= half.z and absf(pos.y - y) <= half.y:
			return true
	return false


# ============================================================================
# CHECK 12 — the wing's acceptance walk (bead godot-test1-3iy.8)
# ============================================================================

func _check_spines_and_liberation() -> void:
	"""
	Check 12. The bead's acceptance, driven under real physics:

	  a. A fresh tower holds exactly the authored captive, with his staging in the
	     cell and the other three frames dark.
	  b. A WRONG HERO on a spine pad opens nothing; the right hero standing on the
	     SAME pad without moving opens it. Same two-step as check 7(b)/(c), and for
	     the same reason: a `body_entered` latch passes the first and fails this.
	  c. Mesh and collision shape both sink the full travel.
	  d. LIBERATION IS PERFORMED BY SOMEBODY ELSE. The probe walks into Primm's cell
	     holding WINDMAN and Primm walks out — which is the whole of "uniform cells,
	     performable by any single hero", and the assertion a hero test would fail.
	     The freed hero is handed to the player on the same frame.
	  e. An empty cell does nothing at all, and writes nothing.
	  f. A NEW TOWER, built from the store: no captive, no staging. That is the only
	     liberation state that survives a relaunch, and check 10's stale-copy lesson
	     is why it goes through the same union merge.
	  g. `set_captive()` — phase 9's seam — puts somebody back in, and freeing him
	     costs the opened set nothing, because systemic captivity is per-run.
	"""
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("the tower has no TowerInterior child")
		await _clear(null, shell)
		return

	# (a) the starting state
	if interior.captives() != [TowerInterior.AUTHORED_CAPTIVE]:
		_fail("a fresh tower holds %s, expected only the authored captive %s" % [
			interior.captives(), TowerInterior.AUTHORED_CAPTIVE])
	var staging := interior.find_child("PrimmContainment", true, false) as MeshInstance3D
	if staging == null or not staging.visible:
		_fail("the authored staging is not in the cell on a fresh tower")
	for hero: String in TowerGraph.HEROES:
		var frame := interior.find_child("CellFrame%s" % hero.capitalize(), true, false) as MeshInstance3D
		if frame == null:
			_fail("%s has no containment frame — his cell cannot show whether it is occupied" % hero)
			continue
		var want_lit := hero == TowerInterior.AUTHORED_CAPTIVE
		var lit := frame.material_override == TowerInterior._material(TowerInterior.COLOR_CELL)
		if lit != want_lit:
			_fail("%s's cell reads %s but he is %s" % [
				hero, "occupied" if lit else "empty",
				"captive" if want_lit else "free"])

	var hero_body := ProbePlayer.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	hero_body.add_child(shape)
	hero_body.add_to_group("player")
	root.add_child(hero_body)

	# (b) one spine door: the wrong hero, then the right one, without moving.
	var door: Dictionary = TowerInterior.SPINE_DOORS[0]
	var gate_id := String(door["gate"])
	var wants := TowerGraph.identity_of(gate_id)
	var wrong := "teibi" if wants != "teibi" else "windman"
	var pad_area := interior.get_node_or_null("Floor0/SpineTrigger1") as Area3D
	if pad_area == null:
		_fail("there is no SpineTrigger1 Area3D — the first spine door has no pad")
		await _clear(hero_body, shell)
		return
	var mass := interior.find_child(String(door["mass"]), true, false) as MeshInstance3D
	var mass_rest: float = mass.position.y
	hero_body.hero = wrong
	hero_body.global_position = pad_area.global_position
	await _settle_physics()
	interior._process(0.1)
	if shell.is_opened(gate_id):
		_fail("%s opened '%s', which answers to %s — the spine door is keyed on nobody" % [
			wrong, gate_id, wants])
	hero_body.hero = wants
	interior._process(0.1)
	if not shell.is_opened(gate_id):
		_fail("%s standing on '%s's pad did not open it — the door latched on who walked in" % [
			wants, gate_id])

	# (c) mesh and shape sink together, the full travel
	for _i in 30:
		interior._process(0.1)
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	var mass_shape := body.get_node_or_null("%sShape" % String(door["mass"])) as CollisionShape3D
	if absf(mass.position.y - (mass_rest - TowerInterior.SPINE_TRAVEL)) > 0.01:
		_fail("%s stopped at %.2f m, expected %.2f m" % [
			String(door["mass"]), mass.position.y, mass_rest - TowerInterior.SPINE_TRAVEL])
	if mass_shape == null or absf(mass_shape.position.y - mass.position.y) > EPS:
		_fail("%s's collision shape did not sink with its mesh — the doorway is still walled" % [
			String(door["mass"])])

	# (d) liberation, performed by SOMEBODY ELSE
	var cell_area := interior.get_node_or_null(
		"Floor0/CellTrigger%s" % TowerInterior.AUTHORED_CAPTIVE.capitalize()) as Area3D
	if cell_area == null:
		_fail("there is no cell volume for %s — his cell cannot be entered" % TowerInterior.AUTHORED_CAPTIVE)
		await _clear(hero_body, shell)
		return
	hero_body.hero = "windman" if TowerInterior.AUTHORED_CAPTIVE != "windman" else "teibi"
	hero_body.global_position = cell_area.global_position
	await _settle_physics()
	if interior.is_captive(TowerInterior.AUTHORED_CAPTIVE):
		_fail("%s walked into %s's cell and nothing happened — liberation is asking who you are" % [
			hero_body.hero, TowerInterior.AUTHORED_CAPTIVE])
	if hero_body.freed != [TowerInterior.AUTHORED_CAPTIVE]:
		_fail("the player was told %s was freed, expected [%s] — the roster seam did not fire" % [
			hero_body.freed, TowerInterior.AUTHORED_CAPTIVE])
	if staging != null and staging.visible:
		_fail("the authored staging is still in the cell after the first rescue")
	if not shell.is_opened(TowerInterior.RESCUE_DONE):
		_fail("the first rescue was not written into the tower's opened set")

	# (e) an empty cell writes nothing
	var before: Array = shell.opened_ids()
	var freed_before: Array = hero_body.freed.duplicate()
	var other := "teibi" if TowerInterior.AUTHORED_CAPTIVE != "teibi" else "phoboman"
	var empty_area := interior.get_node_or_null("Floor0/CellTrigger%s" % other.capitalize()) as Area3D
	hero_body.global_position = cell_area.global_position + Vector3(0.0, 0.0, -30.0)
	await _settle_physics()
	hero_body.global_position = empty_area.global_position
	await _settle_physics()
	if shell.opened_ids() != before:
		_fail("walking into an empty cell changed the tower's opened set: %s -> %s" % [
			before, shell.opened_ids()])
	if hero_body.freed != freed_before:
		_fail("walking into an empty cell freed somebody: %s became %s" % [
			freed_before, hero_body.freed])

	# (g) phase 9's seam, on this same tower: put somebody back in and free him.
	interior.set_captive(other, true)
	if not interior.is_captive(other):
		_fail("set_captive() did not hold %s" % other)
	var frame_other := interior.find_child("CellFrame%s" % other.capitalize(), true, false) as MeshInstance3D
	if frame_other.material_override != TowerInterior._material(TowerInterior.COLOR_CELL):
		_fail("%s's cell did not light up when he was taken" % other)
	hero_body.global_position = cell_area.global_position + Vector3(0.0, 0.0, -30.0)
	await _settle_physics()
	hero_body.global_position = empty_area.global_position
	await _settle_physics()
	if interior.is_captive(other):
		_fail("%s was not freed by walking into his cell" % other)
	if shell.opened_ids() != before:
		# The whole point of the split: only the AUTHORED rescue persists, because
		# systemic captivity happens over and over inside one run.
		_fail("freeing a systemically-taken hero wrote %s into the save; only the authored rescue may persist" % [
			shell.opened_ids()])

	hero_body.queue_free()
	shell.queue_free()
	await process_frame

	# (f) a NEW tower, built from what is on disk
	var again := await _make_tower()
	var inside := again.get_node_or_null("TowerInterior") as TowerInterior
	if inside == null:
		_fail("the rebuilt tower has no interior")
		await _clear(null, again)
		return
	if not inside.captives().is_empty():
		_fail("a tower rebuilt after the first rescue still holds %s" % [inside.captives()])
	var staging_again := inside.find_child("PrimmContainment", true, false) as MeshInstance3D
	if staging_again != null and staging_again.visible:
		_fail("the authored staging came back on a rebuilt tower — the first rescue did not survive the process")
	if not again.is_opened(String(TowerInterior.SPINE_DOORS[0]["gate"])) :
		_fail("the spine door opened in this run came back shut on a rebuilt tower")
	again.queue_free()
	await process_frame


# ============================================================================
# CHECK 12 — the guards are standing, on the right posts, in the right rows
# ============================================================================

## How much room a guard's body needs around its post before "clear of the
## stonework" means anything. The `tower_guard.tscn` capsule is 0.1875 m in
## radius; this is comfortably over it, so a post that merely GRAZES a jamb is a
## failure rather than a lucky pass. Read as: nothing solid may come within this
## of a post, at any height a standing body occupies.
const GUARD_BODY_CLEARANCE: float = 0.45

## How tall a standing guard is, for the same test. The capsule is 1.35 m; a
## little over it, so a post under the crawl lintel (top at 2.8 m, underside 2.0)
## or under a raised mass would be caught.
const GUARD_BODY_HEIGHT: float = 1.6

func _check_guards_stand_their_posts() -> void:
	"""
	Check 12. Three guards, on their authored posts, carrying the guard ROW, each
	leashed to a box that is inside its own storey.

	FOUR FAILURES, AND EVERY ONE OF THEM IS SILENT IN THE GAME:

	  * A POST INSIDE THE STONEWORK. The body settles half in a jamb, `move_and_slide`
	    shoves it somewhere arbitrary on the first frame, and what you see is a guard
	    standing somewhere nobody authored. Measured against BOTH box tables — the
	    interior's and the shell's — because a post that is clear of the furniture
	    and buried in the outer wall is exactly as wrong.
	  * `species` ASSIGNED AFTER `add_child`. The body would run on the CROCODILE's
	    row: a 15 m detection radius indoors, a crocodile's gait, and no
	    `coin_setback`, so it would take a HEART instead of coins and the whole
	    ruling would be silently undone. Asserted on the resolved `spec`, not on the
	    `species` string, because the string is right in both worlds — only `spec`
	    knows which row `_ready()` actually read.
	  * A LEASH THAT WAS NEVER APPLIED. `is_confined` false means a guard walks out
	    of the building, or off the upper slab and down into the courtyard.
	  * A LEASH BOX BIGGER THAN ITS STOREY. The upper guard's box must stay over the
	    slab and WEST of the secure partition — that second half is what makes the
	    checkpoint beyond the identity gate a safe haven by construction, which the
	    setback path in `player_controller` relies on and cannot check for itself.

	The count is taken from the BODIES IN THE TREE (`guard_posts()`), never from
	`GUARD_POSTS.size()`, so a spawner that quietly stopped instancing fails here
	instead of being reported as three guards by a check reading the same table it
	is meant to be auditing.
	"""
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no TowerInterior under the shell — check 12 has nothing to measure")
		await _clear(null, shell)
		return

	var live: Array = interior.guard_posts()
	if live.size() != TowerInterior.GUARD_POSTS.size():
		_fail("the tower stood up %d guard(s) for %d authored post(s)"
			% [live.size(), TowerInterior.GUARD_POSTS.size()])
	if live.size() < 2:
		_fail("only %d guard(s) in the building — the owner ruling is two or three"
			% live.size())

	var guard_row: Dictionary = load(CROC_SCRIPT).get_script_constant_map() \
			.get("SPECIES", {}).get(TowerInterior.GUARD_SPECIES, {})
	if guard_row.is_empty():
		_fail("SPECIES has no '%s' row — every guard would fall back to a crocodile"
			% TowerInterior.GUARD_SPECIES)

	var guards := interior.get_node_or_null("Guards")
	if guards == null:
		_fail("the interior has no Guards container — nothing was ever stood up")
		await _clear(null, shell)
		return

	for i in TowerInterior.GUARD_POSTS.size():
		var authored: Dictionary = TowerInterior.GUARD_POSTS[i]
		var label: String = String(authored["name"])
		var body := guards.get_node_or_null("TowerGuard%s" % label) as Node3D
		if body == null:
			_fail("no guard body for the '%s' post" % label)
			continue

		# THE ROW IT ACTUALLY RESOLVED. `spec` is written once, in `_ready()`, from
		# whatever `species` held at that moment — so this is the call-order contract
		# measured at the only place it leaves a trace.
		var got: Variant = body.get("spec")
		if not (got is Dictionary) or (got as Dictionary) != guard_row:
			_fail("the '%s' guard resolved %s, not the '%s' row — `species` was"
					% [label, ("no spec" if not (got is Dictionary)
						else "a different row"), TowerInterior.GUARD_SPECIES]
					+ " assigned after add_child, so it is running on the fallback")

		# ...and the leash.
		if not bool(body.get("is_confined")):
			_fail("the '%s' guard is not confined — it can walk out of the building"
				% label)
		var want_centre: Vector3 = interior.global_position + (authored["patrol_center"] as Vector3)
		var got_centre: Vector3 = body.get("confine_center")
		var got_half: Vector2 = body.get("confine_half")
		if got_centre.distance_to(want_centre) > EPS:
			_fail("the '%s' guard is leashed to %s, not to its authored %s — the box"
					% [label, str(got_centre), str(want_centre)]
					+ " was computed before the shell was parked on the site")
		if got_half != (authored["patrol_half"] as Vector2):
			_fail("the '%s' guard's leash box is %s, not the authored %s"
				% [label, str(got_half), str(authored["patrol_half"])])

		# THE POST IS STANDABLE. Both tables, at every height a body occupies.
		var post: Vector3 = interior.global_position + (authored["post"] as Vector3)
		var blocker := _solid_near(post)
		if blocker != "":
			_fail("the '%s' post at %s is inside '%s' — the body would settle in the"
					% [label, str(authored["post"]), blocker]
					+ " stonework and be shoved somewhere nobody authored")

		# THE BODY IS INSIDE ITS OWN BOX. A post outside its leash is clamped to the
		# boundary on frame one, which moves a guard nobody moved.
		var off := body.global_position - want_centre
		if absf(off.x) > got_half.x + EPS or absf(off.z) > got_half.y + EPS:
			_fail("the '%s' guard stands outside its own leash box and is clamped"
					% label + " onto the boundary on its first frame")

		# THE BOX IS INSIDE ITS STOREY. Walked as the four corners of the leash box
		# at the post's own height: a guard may not be able to reach a spot the
		# building has no floor under.
		for corner: Vector3 in [
				Vector3(got_half.x, 0.0, got_half.y), Vector3(got_half.x, 0.0, -got_half.y),
				Vector3(-got_half.x, 0.0, got_half.y), Vector3(-got_half.x, 0.0, -got_half.y)]:
			var at := want_centre + corner
			if not _standable(at.x, at.z, post.y):
				_fail("the '%s' guard's leash box reaches (%.2f, %.2f), where its"
						% [label, at.x, at.z] + " storey has no floor — it can walk"
						+ " off the edge and land on the one below")

	print("tower guards: %d on post, leashed to their own storeys" % live.size())
	await _clear(null, shell)


func _solid_near(world_pos: Vector3) -> String:
	## The name of the first solid box a standing body at `world_pos` would be
	## inside of, or "" when the spot is clear. Both tables — the interior's
	## furniture and the shell's outer walls — because either one buries a guard.
	var half := Vector3(GUARD_BODY_CLEARANCE, GUARD_BODY_HEIGHT * 0.5, GUARD_BODY_CLEARANCE)
	var body_centre := Vector3(world_pos.x, world_pos.y + GUARD_BODY_HEIGHT * 0.5, world_pos.z)
	for box: Dictionary in TowerInterior.boxes() + TowerShell.boxes():
		if not box["collide"]:
			continue
		# The ramp is the one tilted box in either table and an AABB test over it is
		# a lie in both directions; it is also 5 m from the nearest post. Skipped by
		# name rather than silently mistested.
		if String(box["name"]) == "Ramp":
			continue
		if _overlaps(body_centre, half * 2.0, box["pos"], box["size"]):
			return String(box["name"])
	return ""


func _standable(x: float, z: float, foot_y: float) -> bool:
	## Is there a solid top at `foot_y` under (x, z)? Ground level is the world's
	## own floor and always true; anything else has to be a box the interior really
	## builds, which is what makes the upper storey's leash box measurable at all.
	if is_zero_approx(foot_y):
		return true
	for box: Dictionary in TowerInterior.boxes():
		if not box["collide"] or String(box["name"]) == "Ramp":
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if absf(pos.y + half.y - foot_y) > EPS:
			continue
		if absf(x - pos.x) <= half.x and absf(z - pos.z) <= half.z:
			return true
	return false


# ============================================================================
# CHECK 13 — the population resets, and nothing else does
# ============================================================================

func _check_guards_reset_on_re_entry() -> void:
	"""
	Check 13. Cross the doorway and every guard is a FRESH body on its post; the
	opened gates are untouched.

	THIS IS THE WHOLE PERSISTENCE CONTRACT FOR PHASE 6 and it is implemented by an
	absence, which is exactly the kind of thing that ships broken and looks fine.
	Three assertions, and each one kills a different plausible half-implementation:

	  * FRESH INSTANCES, not repositioned ones. A reset that teleports the same
	    bodies back leaves a chasing guard chasing, a bitten guard's pause running,
	    and a leash recomputed against nothing. Measured on the object ids, so
	    "moved it back" cannot pass.
	  * THE STATE IS GONE WITH THEM. The old body is put into a chase before the
	    reset and the new one must not be in one — the id test alone would pass a
	    reset that re-instanced and then copied the state across.
	  * THE OPENED SET IS UNTOUCHED. "Structure persists, population resets" is one
	    sentence with two halves, and a reset that reached into the shell's set
	    would undo phase 5 from the inside. A gate is opened before the crossing and
	    must still be open after it.

	Driven through the SHELL'S OWN `player_entered` SIGNAL rather than by calling
	`reset_guards()`, because the wiring is the part that can be missing: an
	interior that never connects resets nothing in the real game and everything in
	a check that calls the function itself.
	"""
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no TowerInterior under the shell — check 13 has nothing to measure")
		await _clear(null, shell)
		return

	shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
	var opened_before: Array = shell.call("opened_ids")

	var guards := interior.get_node_or_null("Guards")
	var before_ids: Array = []
	for child in guards.get_children():
		before_ids.append(child.get_instance_id())
		# Put every one of them into a state a reset has to lose, and walk it off
		# its post so a no-op reset cannot pass by leaving things where they are.
		child.set("is_chasing", true)
		(child as Node3D).global_position += Vector3(2.0, 0.0, 2.0)
	if before_ids.is_empty():
		_fail("no guards to reset — check 13 would pass against an empty building")
		await _clear(null, shell)
		return

	# THE REAL TRIGGER. `_on_door_body_entered` filters to group "player", so this
	# is the shell's own emission — the signal, not the private handler.
	shell.emit_signal("player_entered", null)
	await process_frame

	var after := interior.get_node_or_null("Guards")
	if after == null or after == guards:
		_fail("the doorway crossing did not rebuild the Guards container — either"
				+ " nothing is connected to player_entered, or the reset reuses it")
		await _clear(null, shell)
		return

	var after_ids: Array = []
	for child in after.get_children():
		after_ids.append(child.get_instance_id())
	if after_ids.size() != before_ids.size():
		_fail("re-entry left %d guard(s) where there were %d"
			% [after_ids.size(), before_ids.size()])
	for id_v: Variant in after_ids:
		if before_ids.has(id_v):
			_fail("re-entry kept guard %s alive — the population is repositioned,"
					% str(id_v) + " not reset, so whatever it was doing survives")

	for i in TowerInterior.GUARD_POSTS.size():
		var authored: Dictionary = TowerInterior.GUARD_POSTS[i]
		var body := after.get_node_or_null("TowerGuard%s" % String(authored["name"])) as Node3D
		if body == null:
			_fail("the '%s' post is empty after re-entry" % authored["name"])
			continue
		var want: Vector3 = interior.global_position + (authored["post"] as Vector3) \
				+ Vector3(0.0, TowerInterior.GUARD_SPAWN_LIFT, 0.0)
		if body.global_position.distance_to(want) > EPS:
			_fail("the '%s' guard came back at %s, not on its post %s"
				% [authored["name"], str(body.global_position), str(want)])
		if bool(body.get("is_chasing")):
			_fail("the '%s' guard came back already chasing — the reset re-instanced"
					% authored["name"] + " the body but carried its state across")

	var opened_after: Array = shell.call("opened_ids")
	if opened_after != opened_before:
		_fail("re-entry changed the opened set from %s to %s — structure persists,"
				% [str(opened_before), str(opened_after)] + " only the population resets")
	print("tower guards: re-entry rebuilt %d fresh bodies, opened set %s untouched"
		% [after_ids.size(), str(opened_after)])
	await _clear(null, shell)


# ============================================================================
# CHECK 14 — the leash HOLDS, under real physics, against a real chase
# ============================================================================

## How long check 14 lets a guard try to reach a quarry it cannot have.
const LEASH_PROBE_SECONDS: float = 8.0

## How far outside its own leash box the probe quarry stands. Over the row's
## detection radius it would never be seen; under the two bodies' capsule radii it
## would be BITTEN, and a bite teleports the quarry (the guard setback) which takes
## the load off the leash halfway through the probe. 1.5 m is comfortably between.
const LEASH_PROBE_GAP: float = 1.5

func _check_the_leash_holds_under_a_chase() -> void:
	"""
	Check 14. A guard that has seen the player and is running at it stays inside
	its own box and on its own storey — for the whole chase.

	THE DIFFERENCE BETWEEN THIS AND CHECK 12 IS THE DIFFERENCE BETWEEN A DECLARED
	LEASH AND A LEASH. Check 12 asserts `set_confinement` was called with the right
	numbers; this one runs the shipped `_physics_process` with a real player in the
	tree, a real chase, real gravity and real `move_and_slide`, and measures where
	the body actually ends up. A confinement that was applied but never enforced —
	`_steer_within_platform` unhooked from the frame, `_clamp_to_platform` moved
	below the early return — passes check 12 and fails here.

	THE QUARRY IS PLACED JUST OUTSIDE THE BOX AND WELL INSIDE DETECTION, which is
	the one arrangement that makes the chase pull AGAINST the leash every frame. A
	player standing in the middle of the box would be caught in a second and prove
	nothing.

	AND THE STOREY IS MEASURED, not just the XZ box: `_clamp_to_platform` does not
	touch Y (nothing in this game does — the world is flat and gravity settles), so
	"never left its floor" is a claim about the box being over solid ground, which
	is check 12's corner walk, plus this: the body's own feet never fell.
	"""
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var guards: Node = interior.get_node_or_null("Guards") if interior != null else null
	if guards == null:
		_fail("no guards in the building — check 14 has nothing to chase with")
		await _clear(null, shell)
		return

	# The UPPER guard, because it is the one with somewhere to fall to. Chosen by
	# height off the authored table, never by index, so re-ordering the posts moves
	# this with them.
	var authored: Dictionary = TowerInterior.GUARD_POSTS[0]
	for post: Dictionary in TowerInterior.GUARD_POSTS:
		if (post["post"] as Vector3).y > (authored["post"] as Vector3).y:
			authored = post
	var body: Node3D = guards.get_node_or_null("TowerGuard%s" % String(authored["name"])) as Node3D
	var centre: Vector3 = interior.global_position + (authored["patrol_center"] as Vector3)
	var half: Vector2 = authored["patrol_half"]
	var floor_y: float = (authored["post"] as Vector3).y + interior.global_position.y

	# A real player, standing `LEASH_PROBE_GAP` outside the box's +Z face — inside
	# the row's detection radius, outside the leash, and far enough out that a guard
	# pinned on the boundary cannot actually reach it (a bite would teleport the
	# quarry through the setback path and take the load off mid-probe).
	var hero: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	root.add_child(hero)
	hero.global_position = Vector3(centre.x, floor_y + 0.2,
			centre.z + half.y + LEASH_PROBE_GAP)
	# LEFT FULLY SIMULATED, and that is a finding rather than an oversight: a
	# predator only smells a GROUNDED quarry (`_update_chase_state` asks
	# `is_on_floor()`, which is the jump hatch), and a body with its physics
	# switched off never runs `move_and_slide` and is therefore never on a floor.
	# A frozen probe reads as "airborne" forever and no guard in the game would
	# ever chase it — the check would have measured a leash under no load and said
	# so, which is exactly what it did the first time this was written. There is no
	# input in a headless run, so the quarry stands still on its own.
	# ...and NOW stand the guards up, through the shipped reset. A predator resolves
	# its quarry once, from group "player", in a `call_deferred` off its own
	# `_ready()` — so the bodies the tower built before this probe existed found no
	# player and would never chase anything. In the real game the player is in the
	# tree long before the tower streams in; here the order has to be arranged.
	interior.reset_guards()
	await process_frame
	guards = interior.get_node_or_null("Guards")
	body = guards.get_node_or_null("TowerGuard%s" % String(authored["name"])) as Node3D
	await _settle_physics()

	var ticks := int(LEASH_PROBE_SECONDS / (1.0 / 60.0))
	var chased := false
	var worst := 0.0
	for _i in ticks:
		await physics_frame
		if bool(body.get("is_chasing")):
			chased = true
		var off := body.global_position - centre
		worst = maxf(worst, maxf(absf(off.x) - half.x, absf(off.z) - half.y))
		if body.global_position.y < floor_y - 1.0:
			_fail("the '%s' guard fell off its storey (y %.2f, floor %.2f) while chasing"
				% [authored["name"], body.global_position.y, floor_y])
			break

	if not chased:
		_fail("the '%s' guard never chased the probe standing %.1f m away — check 14"
				% [authored["name"], half.y + LEASH_PROBE_GAP] + " measured a leash"
				+ " under no load, which every mutant passes")
	if worst > EPS:
		_fail("the '%s' guard reached %.3f m outside its leash box while chasing —"
				% [authored["name"], worst] + " the confinement was declared but is"
				+ " not enforced every frame")

	# ---- THE HARD BACKSTOP, ON ITS OWN -------------------------------------
	# The steer (`_steer_within_platform`) and the clamp (`_clamp_to_platform`) are
	# two separate mechanisms and the chase above only exercises the first: with the
	# clamp deleted the steer alone still held the box for the whole eight seconds,
	# so that probe passes a mutant that removed the backstop entirely. The backstop
	# exists for what the steer cannot out-vote — turn lag, a bite lunge, a shove
	# from another body — so it is measured the only way that is honest: SHOVE the
	# guard clean out of its box and require the very next physics frame to have put
	# it back.
	body.global_position = centre + Vector3(half.x + 3.0, 0.0, half.y + 3.0)
	await physics_frame
	var shoved := body.global_position - centre
	if absf(shoved.x) > half.x + EPS or absf(shoved.z) > half.y + EPS:
		_fail("the '%s' guard was shoved %s outside its box and stayed there — the"
				% [authored["name"], str(Vector2(absf(shoved.x) - half.x,
					absf(shoved.z) - half.y))]
				+ " hard clamp is gone, so anything the steer cannot out-vote"
				+ " (a lunge, a shove) leaves a guard off its floor for good")

	# ...and the NEGATIVE CONTROL for the whole check: the same shove, on a body
	# whose leash was never applied, must NOT come back. Without it "it was inside
	# the box" is also true of a guard that simply never went anywhere.
	body.set("is_confined", false)
	body.global_position = centre + Vector3(half.x + 3.0, 0.0, half.y + 3.0)
	await physics_frame
	var loose := body.global_position - centre
	if absf(loose.x) <= half.x + EPS and absf(loose.z) <= half.y + EPS:
		_fail("an UNCONFINED body was pulled back into the box too — the probe is"
				+ " measuring something other than the leash")

	print("tower guards: the leash held a %.0f s chase, worst excursion %.4f m,"
		% [LEASH_PROBE_SECONDS, worst] + " and re-caught a shove")
	await _clear(hero, shell)


func _fresh_store() -> void:
	"""
	Delete the throwaway save, so the next assertion starts from a clean profile.

	Never the real one: `LOCAL_STORE_PATH` is this file's own file and
	`BestRunStore.config_path` is pointed at it before any shell exists.
	"""
	DirAccess.remove_absolute(LOCAL_STORE_PATH)


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
