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
##   1. THE PLAN FITS AND IS AFFORDABLE. Every box inside the shell's inner faces;
##      a box that drifts out through a wall is invisible from inside and obvious
##      from the yard. Check 1.
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
##   9b. **THE FULL-CUSTODY SCENE'S GEOMETRY.** Check 16: the stand the protocol
##      teleports the party to is inside the service corridor, clear of every box
##      by a body radius, south of the spine wall, and leaves the spring arm room;
##      and the scar's rubble fills a doorway that is genuinely OPEN in the
##      unscarred plan and genuinely stone once taken. Check 17 then DRIVES the
##      scene on a real building: containment re-shuts doors earlier rescues
##      opened and stays shut, the right hero's pad releases it and the wrong
##      hero's does not, the scene gives every earned door back on the way out,
##      and the scar's rubble is drawn AND solid AND still there after a relaunch.
##   9. VISIBILITY GATING. Check 9 drives the policy directly at storey counts this
##      building does not have (so phase 8 inherits a correct gate rather than
##      discovering it needs one) and then confirms the live rig hides the whole
##      interior from across the field and shows it from inside.
##  10. **THE CELL BLOCK HAS NO WAY ROUND IT.** Check 11 is phase 8's structural
##      half, and it exists because a gap in the spine wall would not look like a
##      bug — it would look like a corridor. The four rescue spines are the ONLY
##      thing `tower_selfcheck`'s softlock audit has to work with; a 12 cm slot
##      beside a pier makes every identity gate in the block decorative and turns
##      that audit's SELFCHECK OK into a statement about a building nobody built.
##      So the spine line and the cell row are SAMPLED for solidity rather than
##      derived from the same arithmetic that placed them.
##  11. **THE BLOCK'S ACCEPTANCE WALK.** Check 12: a spine door refuses the wrong
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
## Check 13 reads a re-built guard's position one process frame AFTER the
## doorway signal, and one process frame is an unbounded number of physics ticks
## on a loaded CI runner (up to 8) - gravity settles the spawn lift and the wander
## arm drifts a few centimetres before the assertion runs. The question the check
## asks is "was the population RESET to its posts, not left where it stood?", and
## the displaced bodies sit 2.83 m away, so half a metre still separates the two
## answers while admitting every tick the runner sneaks in. Master went red on
## 2026-08-30 at 4 mm off with EPS; this is the tolerance the measurement earns.
const POST_SETTLE_EPS: float = 0.5

## THE CEILING ON THE ONE INTERIOR COST THE DRAW BUDGET CANNOT SEE: static box
## shapes on the single `InteriorCollision` body, one per solid box.
##
## Measured, not chosen: the ten shipped storeys emit 347 of them, and 420 is that
## with a fifth of headroom for the rooms phases 17+ hang off floors that already
## exist. It is a SECOND yardstick rather than a duplicate of `PLAN_BOX_BUDGET`:
## that one is per storey and catches a floor whose walls stopped merging, this one
## is the whole building and catches a builder that started emitting a shape per
## CELL on floors that each merge fine.
const SHAPE_CEILING: int = 420

var _failures: Array[String] = []


## A stand-in for the player: a real CharacterBody3D on the default collision layer
## and in the "player" group, whose hero and phase reach the check sets directly.
##
## IT IMPLEMENTS THE CONTRACT AND NOTHING ELSE — `hero_name()`, `phase_reach()`,
## `hit_by_crocodile()` and `set_indoor_camera()` are the methods the interior asks
## of a player, so a rename on either side fails here instead of degrading into a
## gate that never opens. Instancing the real `player.tscn` would drag in four
## character models and a camera rig to test four method calls.
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
	## The last thing the building said about the indoor camera. Starts null so
	## "never told at all" is distinguishable from "told false" — check 9 needs the
	## difference, because a seam that is simply never called would otherwise read
	## as a correct answer everywhere the answer happens to be false.
	var indoor: Variant = null

	func hero_name() -> String:
		return hero

	func phase_reach() -> float:
		return reach

	func hit_by_crocodile(_attacker: Node = null) -> void:
		hits += 1

	func hero_freed(who: String) -> void:
		freed.append(who)

	func set_indoor_camera(is_indoor: bool) -> void:
		indoor = is_indoor


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
	await _check_the_interior_is_lit_and_off_white()
	await _check_gate_lifecycle()
	await _check_opened_state_is_reapplied()
	await _check_visibility_gating()
	await _check_earned_state_survives_a_relaunch()
	_check_the_block_has_no_way_round_it()
	_check_the_custody_stand_and_the_scar()
	await _check_the_custody_scene_runs()
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

	THE DOORWAY IS THE INTERESTING HALF: the shell's trigger volume must stay empty
	or walking in is walking into a wall.

	TWO POPULATIONS, TWO BOUNDS, AND THAT IS THE POINT. The hand-authored keep
	(`boxes()`) lives inside the KEEP's inner faces and declares floors 0 and 1; a
	hand-planned storey (`plan_boxes(i)`) is a whole keep wider — it spans the
	SHELL's inner faces, `TowerPlans.PLAN_HALF` — and may declare only its own
	floor. Measuring the plans against the keep's bound would fail every correct
	storey; measuring the keep against the plans' would stop catching a floor plan
	that grew out through the keep wall. So each is asked its own question, and only
	the things that are true of the WHOLE building — name uniqueness, the doorway,
	the shell's wall height — are asked over `all_boxes()`.

	The per-storey budget is asked per storey for the same reason it exists: what
	`PLAN_BOX_BUDGET` stops is one floor's walls quietly ceasing to merge, and a
	total over five storeys would let one floor's chequerboard hide under four
	tidy ones.
	"""
	var keep := TowerInterior.boxes()
	if keep.size() > TowerInterior.BOX_BUDGET:
		_fail("the interior is %d boxes, over its declared BOX_BUDGET of %d" % [
			keep.size(), TowerInterior.BOX_BUDGET])
	print("tower interior: %d keep boxes (budget %d), hall headroom %.2f m, storey %.2f m" % [
		keep.size(), TowerInterior.BOX_BUDGET, TowerInterior.headroom(), TowerInterior.SLAB_Y])

	# `seen` is shared by every call below, so name uniqueness is asked across
	# `all_boxes()` and not merely within each population — two storeys that both
	# called a wall the same thing would collide in `find_child` and in
	# `MOVING_PARTS`, and the second one would silently win.
	var seen := {}
	_fit_boxes(keep, TowerInterior.INNER_HALF, [0, 1], seen)
	for floor_index: int in TowerPlans.floors():
		var plan := TowerInterior.plan_boxes(floor_index)
		if plan.size() > TowerInterior.PLAN_BOX_BUDGET:
			_fail("storey %d emits %d boxes, over PLAN_BOX_BUDGET %d — its walls stopped merging" % [
				floor_index, plan.size(), TowerInterior.PLAN_BOX_BUDGET])
		# Its own floor, plus the one its ramp climbs FROM: a deck belongs to the
		# floor it is walked onto from (the phase-3 ramp is floor 0, not floor 1),
		# and it is the one box of a storey that legitimately says so.
		_fit_boxes(plan, TowerPlans.PLAN_HALF,
				[floor_index, int(TowerPlans.storey(floor_index)["from"])], seen)
		print("  storey %d: %d boxes (budget %d), floor at %.2f m, %.2f m clear" % [
			floor_index, plan.size(), TowerInterior.PLAN_BOX_BUDGET,
			TowerInterior.FLOOR_Y[floor_index], TowerInterior.plan_clear_height(floor_index)])

	# The rotor's two dimensions have to agree with the doorway they guard.
	if TowerInterior.ROTOR_ARM >= TowerInterior.ROTOR_DOOR_HALF:
		_fail("the rotor bars (%.2f m) are longer than their doorway is wide (%.2f m) — they grind the jambs" % [
			TowerInterior.ROTOR_ARM, TowerInterior.ROTOR_DOOR_HALF])
	if TowerInterior.ROTOR_ARM <= TowerInterior.ROTOR_DOOR_HALF * 0.5:
		_fail("the rotor bars are too short to cover half the doorway — nothing to time")


func _fit_boxes(boxes: Array[Dictionary], bound: float, floors: Array[int],
		seen: Dictionary) -> void:
	"""
	One population of boxes: well-formed, uniquely named, on a floor it is allowed
	to claim, and inside the walls that population is drawn against.

	@param bound: The half-width the population must stay inside, on X and Z.
	@param floors: The `floor` indices a box here may declare.
	@param seen: Names already taken, carried ACROSS populations — see check 1.
	"""
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
		if not floors.has(floor_index):
			_fail("%s claims storey %d; its population may only claim %s" % [
				box_name, floor_index, floors])

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
		if absf(pos.x) + reach_x > bound + EPS or absf(pos.z) + reach_z > bound + EPS:
			_fail("%s reaches outside the inner faces it is drawn against (+/-%.2f m)" % [
				box_name, bound])
		# The ramp is exempt from the floor test and only from that one: a tilted slab
		# whose DECK meets the ground at its foot necessarily buries its own underside
		# below it. Where the deck actually lands is check 3's business, and check 3
		# pins it to the millimetre.
		if not box.has("rot") and pos.y - reach_y < -EPS:
			_fail("%s starts below the floor (y = %.2f)" % [box_name, pos.y - reach_y])
		if pos.y + reach_y > TowerShell.WALL_HEIGHT + EPS:
			_fail("%s tops out at %.2f m, over the shell's %.2f m wall" % [
				box_name, pos.y + reach_y, TowerShell.WALL_HEIGHT])

		# THE CORNER SPIRE IS GONE (shell phase 13): its cap was a landing pad for a
		# Windman, and the identity it carried now comes from the building's mass.
		# There is therefore no stone in the -X/-Z corner any more and nothing to
		# keep the plan out of — the shell's inner faces above are the whole test.

		# And the doorway stays a hole. Asked of every population: a planned storey
		# whose ramp came down into the entrance would block the front door as
		# thoroughly as a wall does.
		if _overlaps(pos, box["size"], door["pos"], door["size"]):
			_fail("%s stands in the shell's doorway volume" % box_name)


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

	# (d) THE HAND-PLANNED STOREYS, AS ONE ASSERTION AND NOT AS A SWEEP.
	#
	# The sweep above asks of every box "is its top a ledge somebody could jump
	# from". Over three 40 x 40 storeys that is thousands of pairs, and worse, it is
	# a question whose answer depends on where the boxes happen to be. The builder
	# makes the answer STRUCTURAL instead: `_merge_walls` gives every wall a bottom
	# on its storey's walking surface and a top at its storey's ceiling, and
	# `_plan_slab` hangs every slab UNDER its walking surface. So a plan storey has
	# exactly two kinds of solid — floor and stone that reaches the ceiling — and
	# neither can be a ledge at all: you cannot stand on a slab top (it is the floor
	# you are already standing on) and there is nothing over a box whose top IS the
	# ceiling.
	#
	# "REACHES THE CEILING" AND NOT "IS FULL HEIGHT", since phase 16: the challenge
	# arm of `_plan_gates` hangs a LINTEL over the maintenance crawl's duct, which
	# starts 2.8 m up and runs to the ceiling. Its top is still the ceiling, so it
	# still cannot be a ledge, and the assertion below is the weaker-sounding claim
	# that is actually the true one. What it still refuses is the dangerous shape —
	# a box whose top stops SHORT of the ceiling, which is a step by definition.
	#
	# That is a STRONGER statement than the sweep, not a weaker one. A sweep says
	# "no box in today's plan is a step"; this says "no box any plan can emit is a
	# step", which is what actually has to hold when a designer edits ASCII and
	# nobody re-runs a level review. What it costs is that the builder may never
	# grow a third kind of solid without coming here — which is the point.
	for floor_index: int in TowerPlans.floors():
		var surface: float = TowerInterior.FLOOR_Y[floor_index]
		var clear := TowerInterior.plan_clear_height(floor_index)
		var wall_top := surface + clear
		for box: Dictionary in TowerInterior.plan_boxes(floor_index):
			if not box["collide"] or box.has("rot"):
				continue  # the ramp is MEANT to reach the next storey.
			var top: float = box["pos"].y + box["size"].y * 0.5
			var bottom: float = box["pos"].y - box["size"].y * 0.5
			var is_slab := absf(top - surface) <= EPS \
					and absf(bottom - (surface - TowerInterior.SLAB_THICK)) <= EPS
			var to_ceiling := bottom >= surface - EPS and absf(top - wall_top) <= EPS
			if not (is_slab or to_ceiling):
				_fail("%s spans %.2f .. %.2f m on a storey at %.2f m (ceiling %.2f) — it is neither this floor's slab nor stone reaching its ceiling, so its top is a ledge" % [
					box["name"], bottom, top, surface, wall_top])
		# ...and a wall you cannot see over. A walled-off room whose wall an unaided
		# jump clears is a room with a second entrance nobody drew.
		if clear <= apex:
			_fail("storey %d has %.2f m of clear air on a %.4f m jump" % [
				floor_index, clear, apex])


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
	"""
	Vertical gap between `from_y` and the lowest solid surface above this XZ point.

	OVER `all_boxes()`, so a planned storey's slab is a ceiling like any other — the
	keep now stands INSIDE the building rather than under the sky, and a check that
	only knew the keep's own boxes would report open air where there is 6000 m2 of
	floor slab.
	"""
	var lowest := TowerShell.WALL_HEIGHT * 2.0
	for other: Dictionary in TowerInterior.all_boxes():
		if not other["collide"] or other["name"] == skip:
			continue
		if other.has("rot"):
			lowest = minf(lowest, _ramp_underside_at(other, x, z))
			continue
		var pos: Vector3 = other["pos"]
		var half: Vector3 = other["size"] * 0.5
		if absf(pos.x - x) > half.x or absf(pos.z - z) > half.z:
			continue
		var bottom := pos.y - half.y
		if bottom >= from_y - EPS:
			lowest = minf(lowest, bottom)
	return maxf(0.0, lowest - from_y)


func _ramp_underside_at(ramp: Dictionary, x: float, z: float) -> float:
	"""
	How high ONE ramp's UNDERSIDE is over this XZ point, or a huge number where that
	ramp is not overhead.

	Analytic rather than a bounding box on purpose: a ramp is a rotated slab, and
	its AABB claims stone from its foot's floor to its head's across its whole run —
	which would declare the entire courtyard roofed and quietly disable check 2.

	TAKES ITS RAMP AS A PARAMETER since phase 14, and derives the deck from that
	box's own transform rather than from the keep ramp's constants. There are four
	rotated slabs in this building now (the keep's and one per planned storey), and
	a version that knew only `_ramp_box()` would be silently blind to three of them —
	the same failure the hard-coded call it replaces would have become.
	"""
	var pos: Vector3 = ramp["pos"]
	var size: Vector3 = ramp["size"]
	var away := TowerShell.WALL_HEIGHT * 2.0
	if absf(z - pos.z) > size.z * 0.5:
		return away
	# The deck's two ends, rebuilt exactly as check 3 rebuilds them: the top face,
	# half a thickness along the box's own normal.
	var theta: float = ramp["rot"].z
	var along := Vector2(cos(theta), sin(theta))
	var normal := Vector2(-sin(theta), cos(theta))
	var deck_mid := Vector2(pos.x, pos.y) + normal * (size.y * 0.5)
	var foot := deck_mid - along * (size.x * 0.5)
	var head := deck_mid + along * (size.x * 0.5)
	if x < minf(foot.x, head.x) or x > maxf(foot.x, head.x) \
			or is_equal_approx(foot.x, head.x):
		return away
	var deck := foot.y + (x - foot.x) * (head.y - foot.y) / (head.x - foot.x)
	return deck - size.y / cos(theta)


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

	EVERY ROTATED BODY IN THE BUILDING, since phase 14 — the keep's ramp is now the
	`0 -> 1` case of a loop that also walks one deck per hand-planned storey. The
	expected ends of a plan ramp are derived HERE from the storey's ASCII (the `S`
	lane's two edges, and the `FLOOR_Y` values of `from` and `floor`), not from the
	builder's own `_plan_ramp`, so this is a second opinion and not an echo. And the
	loop is over `all_boxes()` rather than over the storeys, so a fourth rotated
	body nobody expected fails instead of going unmeasured.
	"""
	# What we expect to find, one row per deck: the box, its two end points and a
	# label for the failure text.
	var want: Array[Dictionary] = []
	var keep_ramp: Dictionary = {}
	for box: Dictionary in TowerInterior.boxes():
		if box["name"] == "Ramp":
			keep_ramp = box
	if keep_ramp.is_empty():
		_fail("there is no box called Ramp — the only way between the storeys is gone")
	else:
		want.append({
			"box": keep_ramp, "label": "ramp",
			"foot": Vector2(TowerInterior.RAMP_X0, 0.0),
			"head": Vector2(TowerInterior.SLAB_X0, TowerInterior.SLAB_Y),
		})
	for floor_index: int in TowerPlans.floors():
		var deck: Dictionary = {}
		for box: Dictionary in TowerInterior.plan_boxes(floor_index):
			if box.has("rot"):
				deck = box
		if deck.is_empty():
			_fail("storey %d has no ramp — a floor you cannot walk to" % floor_index)
			continue
		var plan := TowerPlans.storey(floor_index)
		var lane := _stair_lane(plan)
		if lane.is_empty():
			_fail("storey %d's plan draws no '%s' lane" % [floor_index, TowerPlans.STAIR_UP_CHAR])
			continue
		var y_foot: float = TowerInterior.FLOOR_Y[int(plan["from"])]
		var y_head: float = TowerInterior.FLOOR_Y[floor_index]
		var west: float = lane["x_west"]
		var east: float = lane["x_east"]
		want.append({
			"box": deck, "label": "storey %d ramp" % floor_index,
			"foot": Vector2(west if lane["rises_east"] else east, y_foot),
			"head": Vector2(east if lane["rises_east"] else west, y_head),
		})

	var rotated := 0
	for box: Dictionary in TowerInterior.all_boxes():
		if box.has("rot"):
			rotated += 1
	if rotated != want.size():
		_fail("the building holds %d rotated bodies and this check knows about %d" % [
			rotated, want.size()])

	for row: Dictionary in want:
		var box: Dictionary = row["box"]
		var pos: Vector3 = box["pos"]
		var size: Vector3 = box["size"]
		var rot: Vector3 = box["rot"]
		var theta: float = rot.z
		var along := Vector2(cos(theta), sin(theta))
		var normal := Vector2(-sin(theta), cos(theta))
		var deck_mid := Vector2(pos.x, pos.y) + normal * (size.y * 0.5)
		var low := deck_mid - along * (size.x * 0.5)
		var high := deck_mid + along * (size.x * 0.5)
		# `_deck_box` orders its ends so the run is positive, so the box's low end
		# is its WEST end — which is the foot only when the ramp rises east.
		var want_foot: Vector2 = row["foot"]
		var want_head: Vector2 = row["head"]
		var foot := low if want_foot.x <= want_head.x else high
		var head := high if want_foot.x <= want_head.x else low

		if absf(foot.y - want_foot.y) > EPS:
			_fail("the %s's foot is %.3f m off its floor — a step CharacterBody3D cannot climb" % [
				row["label"], foot.y - want_foot.y])
		if absf(foot.x - want_foot.x) > EPS:
			_fail("the %s's foot is at x = %.3f, expected %.3f" % [
				row["label"], foot.x, want_foot.x])
		if absf(head.y - want_head.y) > EPS:
			_fail("the %s's head is %.3f m off the floor above — a lip you would have to jump" % [
				row["label"], head.y - want_head.y])
		if absf(head.x - want_head.x) > EPS:
			_fail("the %s's head is at x = %.3f, expected %.3f" % [
				row["label"], head.x, want_head.x])

		# Godot's CharacterBody3D refuses to treat a surface steeper than
		# `floor_max_angle` (45 degrees by default) as floor: at that point the ramp
		# stops being a stair and becomes a slide.
		var degrees := absf(rad_to_deg(theta))
		if degrees >= 40.0:
			_fail("the %s is %.1f degrees — at 45 the engine stops calling it a floor" % [
				row["label"], degrees])
		# ...and no plan ramp may be steeper than the one that has been walked since
		# phase 3. `PLAN_RAMP_MAX_SLOPE` is that ramp's own slope, so this compares
		# the building against itself and never against a fresh number.
		var slope := absf(tan(theta))
		if slope > TowerInterior.PLAN_RAMP_MAX_SLOPE + EPS:
			_fail("the %s is slope %.4f, steeper than the proven ramp's %.4f" % [
				row["label"], slope, TowerInterior.PLAN_RAMP_MAX_SLOPE])
		print("%s: %.1f degrees (slope %.4f), foot (%.2f, %.2f) head (%.2f, %.2f)" % [
			row["label"], degrees, slope, foot.x, foot.y, head.x, head.y])


func _stair_lane(plan: Dictionary) -> Dictionary:
	"""
	The `S` lane's two X edges and which way it rises, read straight off the ASCII.

	@return: `{x_west, x_east, rises_east}`, or `{}` for a storey with no lane.

	CHECK 3'S SECOND OPINION: the grid arithmetic is written out here rather than
	borrowed from `TowerInterior._grid_x`, so a builder that placed every ramp
	consistently half a cell out would still fail. Two lines of arithmetic is a
	cheap price for the check being independent of the thing it checks.
	"""
	var rows: Array = plan["rows"]
	var c0 := TowerPlans.PLAN_GRID
	var c1 := -1
	var landing_sum := 0.0
	var landings := 0
	for r: int in rows.size():
		var line: String = rows[r]
		for c: int in line.length():
			if line[c] == TowerPlans.STAIR_UP_CHAR:
				c0 = mini(c0, c)
				c1 = maxi(c1, c)
			elif line[c] == TowerPlans.LANDING_CHAR:
				landing_sum += float(c)
				landings += 1
	if c1 < 0 or landings == 0:
		return {}
	var cell := TowerPlans.PLAN_CELL
	return {
		"x_west": -TowerPlans.PLAN_HALF + float(c0) * cell,
		"x_east": -TowerPlans.PLAN_HALF + float(c1 + 1) * cell,
		"rises_east": landing_sum / float(landings) > float(c1),
	}


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
	# THE SAME MEASURED NUMBER, ASKED OF EVERY HAND-PLANNED STOREY. A storey is
	# 4.6 m clear, which is the hall's height by construction — but "by
	# construction" is exactly the kind of claim that stops being true when
	# somebody retunes `STOREY_HEIGHT` for the shell's sake, and a storey the
	# camera does not fit in is 6000 m2 of the-back-of-a-head.
	for floor_index: int in TowerPlans.floors():
		var clear := TowerInterior.plan_clear_height(floor_index)
		print("  storey %d: %.2f m clear, camera needs %.2f m" % [floor_index, clear, need])
		if clear < need:
			_fail("storey %d is %.2f m and the camera needs %.2f m — the spring arm collapses up there" % [
				floor_index, clear, need])
	# ------------------------------------------------------------------
	# THE INDOOR BOOM (bd godot-test1-0nu). Same "measure the live rig" rule as
	# above, for the same reason: the number that matters is the arm's HORIZONTAL
	# reach, which is the length foreshortened by the arm's 14-degree pitch, and
	# reading that off the scene file is how you get a confidently wrong answer.
	#
	# The claim being asserted is the one that picked 3.85: a player standing on
	# the courtyard's CENTRE LINE keeps the whole boom whichever way they face. So
	# the reach, plus the arm's own margin, must fit in half the courtyard's clear
	# width — the span from the upper slab's west edge to the shell's west inner
	# face, derived here rather than restated so a moved wall fails this check.
	var courtyard := TowerInterior.SLAB_X0 + TowerInterior.INNER_HALF
	var outdoor_reach := _camera_reach(player, camera)
	player.call("set_indoor_camera", true)
	# A FEW FRAMES IN, the boom must be ON ITS WAY AND NOT THERE. The tower's
	# doorway is a 6 x 4 m hole the boom trails straight through, so a snap would
	# cut the camera 4.3 m forward on every entry; `_tick_arm_length` eases it
	# instead, and this sample is what fails if somebody puts the snap back.
	await _settle_physics()
	var mid_reach := _camera_reach(player, camera)
	await _ease_arm()
	var indoor_reach := _camera_reach(player, camera)
	print("camera reach: %.2f m outdoors, %.2f m indoors (+ %.2f margin); courtyard %.2f m wide" % [
		outdoor_reach, indoor_reach, arm.margin, courtyard])
	if mid_reach >= outdoor_reach or mid_reach <= indoor_reach:
		_fail("the boom jumped to %.2f m instead of easing between %.2f and %.2f — a doorway is a cut again" % [
			mid_reach, outdoor_reach, indoor_reach])
	if indoor_reach + arm.margin > courtyard * 0.5:
		_fail("the indoor boom reaches %.2f m (+ %.2f margin) into a %.2f m courtyard — it still collapses on its centre line" % [
			indoor_reach, arm.margin, courtyard])
	# ...and the cost half of the same number. A boom that did not actually shorten
	# would pass the line above on a narrow enough courtyard and buy no frame time.
	if indoor_reach >= outdoor_reach * 0.75:
		_fail("the indoor boom is %.2f m against %.2f m outdoors — that is not a shorter arm" % [
			indoor_reach, outdoor_reach])
	# Leaving the room restores the shipped framing exactly. The flag is transient
	# world state; a player who walks out and never gets the outdoor camera back is
	# the mutant this line kills.
	player.call("set_indoor_camera", false)
	await _ease_arm()
	if not is_equal_approx(_camera_reach(player, camera), outdoor_reach):
		_fail("walking out of the room left the camera at %.2f m instead of the shipped %.2f m" % [
			_camera_reach(player, camera), outdoor_reach])

	# The upper storey has no ceiling at all, but it does have a parapet; make sure
	# the shell still has wall left over it, or the "room" is a plinth.
	if TowerShell.WALL_HEIGHT - TowerInterior.SLAB_Y < 2.0:
		_fail("the upper storey has only %.2f m of wall around it — that is a plinth, not a room" % (
			TowerShell.WALL_HEIGHT - TowerInterior.SLAB_Y))
	# The real player joins group "player"; leaving it in the tree would give every
	# later check two candidates for "the local player" and a coin-flip for which.
	player.queue_free()
	await process_frame


func _ease_arm() -> void:
	## Long enough for `_tick_arm_length` to finish its walk: the whole trip is
	## 4.4 m at ARM_EASE_SPEED, about 15 physics frames, and this is comfortably
	## over that with no dependence on the exact rate.
	for _i in 40:
		await physics_frame


func _camera_reach(player: Node3D, camera: Camera3D) -> float:
	"""
	How far BEHIND the hero the settled camera sits, on the horizontal plane —
	the number a wall actually has to make room for. Measured off the live rig,
	never computed from `spring_length` (see check 4's docstring).
	"""
	var offset := camera.global_position - player.global_position
	return Vector2(offset.x, offset.z).length()


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
	var boxes := TowerInterior.all_boxes()
	var meshes := _all_meshes(interior)
	if meshes.size() > TowerInterior.DRAW_BUDGET:
		_fail("the interior builds %d meshes, over its declared DRAW_BUDGET of %d" % [
			meshes.size(), TowerInterior.DRAW_BUDGET])
	print("tower interior: %d meshes drawn (budget %d) for %d boxes" % [
		meshes.size(), TowerInterior.DRAW_BUDGET, boxes.size()])

	# The batched vertices of each storey, once, so the corner test below is a set
	# lookup rather than a re-walk of the mesh per box. Sized off `FLOOR_Y`, like
	# the containers themselves, so a storey added to `TowerPlans` is measured here
	# the day it lands and needs no edit.
	var batch_verts: Array[Dictionary] = []
	for i in TowerInterior.FLOOR_Y.size():
		batch_verts.append(_batch_vertices(interior, i))

	var want_shapes := 0
	for box: Dictionary in boxes:
		if box["collide"]:
			want_shapes += 1
		if not TowerInterior.is_own_node(box):
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
			# The stroke is measured from the storey's own walking surface: the
			# press moved 46 m up with the cell block and its three constants did
			# not change, which is the whole point of `press_y` being a stroke.
			var base: float = TowerInterior.FLOOR_Y[int(box["floor"])]
			var top := base + TowerInterior.PRESS_TOP
			var bottom := base + TowerInterior.PRESS_BOTTOM
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
	# block's own: four spine pads, four cell volumes, the crawl press's hazard and
	# the gallery's vent-purge pad.
	# COUNTED AND NOT CAPPED — an Area3D nobody meant to build is a trigger that
	# fires, and every one of these fifteen is named in this file.
	#
	# A `P` cell still adds NONE — it draws a cyan plate and nothing else, because
	# there are no guards up there yet to purge (phase 17 owns population). What
	# phase 15 added is one trigger per RIDDLE LOCK PAD, and that count is derived
	# from the plans themselves rather than written down, so a riddle authored later
	# is measured the day its cells land and a pad that lost its trigger fails here.
	#
	# Phase 16 adds exactly ONE more: the labyrinth's `LiftStopTrigger`. It is
	# counted off `lift_stop_floor()` rather than written down, so a graph with no
	# such entry — or a plan that stopped carrying its landing — is a build with no
	# trigger and this count follows it down instead of failing on a stale number.
	var lift_stops := 1 if TowerInterior.lift_stop_floor() >= 0 else 0
	var want_areas := 5 + TowerInterior.SPINE_DOORS.size() + TowerGraph.HEROES.size() \
			+ 2 + lift_stops
	var lock_pads := 0
	for plan: Dictionary in TowerPlans.STOREYS:
		lock_pads += (TowerInterior.gate_slots(plan)["pads"] as Array).size()
	want_areas += lock_pads
	if areas != want_areas:
		_fail("the interior has %d Area3D, expected %d (3 pads + 2 rotor hazards + %d spine pads + %d cells + 1 press + 1 purge + %d riddle lock pads + %d lift stop)" % [
			areas, want_areas, TowerInterior.SPINE_DOORS.size(), TowerGraph.HEROES.size(),
			lock_pads, lift_stops])
	# ...and the stop stands where the graph says it does. A trigger built on the
	# wrong storey would still be one `Area3D` and pass the count above.
	if lift_stops == 1:
		var stop := interior.find_child("LiftStopTrigger", true, false) as Area3D
		if stop == null:
			_fail("the interior builds no LiftStopTrigger, but a storey carries the stop's landing")
		else:
			var want_floor := TowerInterior.lift_stop_floor()
			if String(stop.get_parent().name) != "Floor%d" % want_floor:
				_fail("LiftStopTrigger hangs off %s, not the Floor%d container it must hide with" % [
					stop.get_parent().name, want_floor])
			var surface: float = TowerInterior.FLOOR_Y[want_floor]
			if absf(stop.position.y - (surface + 1.0)) > EPS:
				_fail("LiftStopTrigger is at y = %.2f, not one metre over storey %d's %.2f m surface" % [
					stop.position.y, want_floor, surface])

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
		# THE NUMBER THE BATCH DOES NOT HIDE. Every solid box is one static
		# `BoxShape3D` on this one body — the cheapest thing Godot's broadphase
		# holds, and the one interior cost the draw-call budget says nothing about.
		# Two maze storeys added a few hundred of them, so the total is PRINTED
		# rather than discovered, and capped: a plan whose walls stopped merging
		# blows `PLAN_BOX_BUDGET` first, but a builder that started emitting a shape
		# per CELL would sail past both without this line.
		print("tower interior: %d collision shapes on one body (ceiling %d)" % [
			shapes, SHAPE_CEILING])
		if shapes > SHAPE_CEILING:
			_fail("the interior body holds %d collision shapes, over the stated ceiling of %d" % [
				shapes, SHAPE_CEILING])
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
		# A `FLOOR_Y` storey nobody has drawn yet builds an EMPTY batch — no
		# surfaces, so no material, and nothing rendered either. That is a real
		# state of this building (the shell has room for ten storeys and five are
		# authored), so it is skipped rather than failed; check 5's corner test is
		# what would notice a storey that lost geometry it was supposed to have.
		if mesh_a[i].mesh is ArrayMesh and (mesh_a[i].mesh as ArrayMesh).get_surface_count() == 0:
			continue
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
	# `all_boxes()` and `is_own_node()`, which is the SAME question `_ready()` asks
	# when it decides what leaves the batch — a plan storey's riddle mass wears a
	# material exactly as the keep's gates do, and counting only the keep would have
	# left this cap silently unable to see one.
	var colors := {}
	for box: Dictionary in TowerInterior.all_boxes():
		if TowerInterior.is_own_node(box):
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


## The luminance every surface the player can see inside this building must clear.
## The acceptance is "no black regions"; this is the mechanical form of it.
##
## IT IS SET BY THE DARKEST THING THE LEGIBILITY LANGUAGE DELIBERATELY PAINTS, on its
## darkest face. That is the demand gate's cold steel (0.27 luminance) on an underside
## (`_face_shade`'s 0.78), i.e. 0.21 — a MACHINE, and machines are allowed to be
## machine-coloured; the check is here to stop a ROOM going dark. So the bar sits just
## under that and well over black, and the walls carry their own far higher bar below.
## Deepen `_face_shade` or repaint a room dark and this is what says so. The bar is a
## couple of hundredths under the measured darkest so a palette nudge reports as a
## palette nudge rather than as this check, which prints the darkest it saw either way.
const INTERIOR_MIN_LUMINANCE: float = 0.18

## ...and what the WALLS specifically have to clear. A separate, much higher bar,
## because "off-white" is the look and a merely-not-black wall is not it.
const WALL_MIN_LUMINANCE: float = 0.75


func _check_the_interior_is_lit_and_off_white() -> void:
	"""
	Check 6b (bead 99j). The interior reads as a bright, evenly lit corporate floor
	rather than as the black box a sealed roof made of it.

	THIS IS AN EYE TEST ASSERTED HEADLESSLY, and the split is deliberate. A headless
	`gl_compatibility` process cannot render, let alone screenshot, so what a
	self-check CAN pin is the two things a screenshot would have been evidence OF:

	  a. NOTHING IN HERE WAITS FOR A LIGHT. There is no `Light3D` in this building
	     and the shell's roof keeps the key light out, so the batch must be UNSHADED
	     (its vertex colour is what you see, and `_face_shade` is what gives it form)
	     and every matte PER-COLOUR material — the ten moving parts — must carry
	     additive emission in its own colour. The emissive material must not have
	     picked up an emission it multiplies by its own colour: that is how a light
	     panel silently goes dim.

	     `EMISSION_OP_MULTIPLY` is checked for BY NAME and refused, because it is the
	     plausible-looking wrong answer here and this file is where that gets
	     remembered: `emission_operator` combines the emission colour with the
	     emission TEXTURE, not with the albedo, and an unset emission texture samples
	     black — so a multiply material emits nothing at all, on any renderer, while
	     reading in the inspector exactly like one that works.
	  b. THE COLOURS ARE THE ONES THE LOOK NEEDS, on the geometry that really got
	     built. Walls and ceilings off-white, floors mint, a wainscot band on the
	     planned walls — read out of a storey's BATCH VERTEX COLOURS, which is the
	     only place `top_color` and the wainscot split can be observed at all
	     (neither is a box, on purpose: see `_emit_box`). A `top_color` that stopped
	     being wired, or a wall that stopped splitting, fails here by name.

	And the acceptance itself: no surface in the batch is dark. Every vertex colour
	on every storey clears `INTERIOR_MIN_LUMINANCE`, which is what "no black regions"
	means when you cannot take the screenshot.
	"""
	# (a) — the two cached batch materials, asked directly. Both are unshaded: their
	# vertex colours are the whole of what the player sees inside this building.
	for pair: Array in [[TowerInterior._batch_material(false), "matte"],
			[TowerInterior._batch_material(true), "emissive"]]:
		var mat: StandardMaterial3D = pair[0]
		if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			_fail("the %s batch material is not UNSHADED — under the sealed roof it renders black" % pair[1])
		if not mat.vertex_color_use_as_albedo:
			_fail("the %s batch material stopped reading its vertex colours" % pair[1])
	# ...and the per-colour materials the ten moving parts wear, which cannot bake
	# anything into a vertex and self-light with plain additive emission instead.
	var steel := TowerInterior._material(TowerInterior.COLOR_MECHANISM)
	if not steel.emission_enabled:
		_fail("a matte per-colour interior material does not self-light — the moving parts go black while the walls do not")
	if not is_equal_approx(steel.emission_energy_multiplier, TowerInterior.INTERIOR_EMISSION):
		_fail("a matte per-colour material self-lights at %.2f, not INTERIOR_EMISSION (%.2f)" % [
			steel.emission_energy_multiplier, TowerInterior.INTERIOR_EMISSION])
	# THE ONE TRAP, asked of every material this file can reach: an emission that is
	# MULTIPLIED is multiplied by the emission TEXTURE, which is black when unset.
	# It reads like "tint the emission by the albedo" and emits nothing at all.
	for color: Color in [TowerInterior.COLOR_MECHANISM, TowerInterior.COLOR_STONE,
			TowerInterior.COLOR_PANEL, TowerInterior.COLOR_CELL]:
		var mat := TowerInterior._material(color)
		if mat.emission_enabled and mat.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY:
			_fail("an interior material multiplies its emission — with no emission texture that is black, so it emits nothing")

	# (b) — the palette, on the geometry.
	if TowerInterior.COLOR_STONE.get_luminance() < WALL_MIN_LUMINANCE:
		_fail("the walls and ceilings are %.2f luminance, under the %.2f an off-white floor needs" % [
			TowerInterior.COLOR_STONE.get_luminance(), WALL_MIN_LUMINANCE])
	var carpet := TowerInterior.COLOR_CARPET
	if carpet.g <= carpet.r or carpet.g <= carpet.b:
		_fail("COLOR_CARPET is not green-dominant — the floor is supposed to read as mint")
	if carpet.get_luminance() < INTERIOR_MIN_LUMINANCE:
		_fail("COLOR_CARPET is too dark (%.2f) to read as carpet under flat light" % carpet.get_luminance())

	var interior := load(INTERIOR_SCENE).instantiate() as Node3D
	root.add_child(interior)
	await process_frame
	var darkest := 1.0
	var darkest_where := ""
	for floor_index: int in TowerInterior.FLOOR_Y.size():
		var batch := interior.get_node_or_null(
				"Floor%d/Floor%dBatch" % [floor_index, floor_index]) as MeshInstance3D
		if batch == null or batch.mesh == null:
			continue
		var mesh: ArrayMesh = batch.mesh
		var seen := {}
		for surface: int in mesh.get_surface_count():
			var colors: PackedColorArray = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			for c: Color in colors:
				# Vertex colours are written LINEAR (`_emit_box` converts, and the
				# comment there says why), so they come back to sRGB to be measured
				# against the sRGB palette the designer typed.
				var srgb := c.linear_to_srgb()
				var key := _color_key(srgb)
				var lum := srgb.get_luminance()
				if lum < darkest:
					darkest = lum
					darkest_where = "%s on storey %d" % [key, floor_index]
				# Once per DISTINCT colour, not once per vertex: a repainted wall is
				# thousands of vertices and one mistake.
				if lum < INTERIOR_MIN_LUMINANCE and not seen.has(key):
					_fail("storey %d paints a surface %s at %.2f luminance — the interior is supposed to have no dark corners" % [
						floor_index, key, lum])
				seen[key] = true
		# Only the PLANNED storeys are drawn on the grid, and only they carry the
		# carpet-and-wainscot treatment; the keep's two floors are hand-authored
		# furniture and its carpet is one box of its own.
		if not TowerPlans.storey(floor_index).is_empty():
			for want: Array in [
				[TowerInterior.COLOR_STONE, "off-white walls"],
				[TowerInterior.COLOR_CARPET, "a mint floor"],
				[TowerInterior.COLOR_WAINSCOT, "a wainscot band"],
			]:
				if not seen.has(_color_key(want[0])):
					_fail("storey %d's batch has no %s in it — that half of the look is not wired to the geometry" % [
						floor_index, want[1]])
	print("tower interior: batch palette clears %.2f luminance (darkest %.2f, %s)" % [
		INTERIOR_MIN_LUMINANCE, darkest, darkest_where])
	interior.queue_free()
	await process_frame


func _color_key(c: Color) -> String:
	## A colour's identity, rounded past the sRGB/linear round trip's float noise.
	return "%.2f|%.2f|%.2f" % [c.r, c.g, c.b]


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
	# ...and having travelled, it is RETIRED. A mass is as tall as its room, so a
	# fully risen one stands half out of the storey above (this one's centre lands
	# on FLOOR_Y[2] exactly). Asserting the y alone let that ship.
	if mass.visible or (mass_shape != null and not mass_shape.disabled):
		_fail("the fully opened identity mass is still drawn/solid — it is standing 2 m proud of storey 3's floor")

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

	# (g) THE RIDDLE, phase 15: a wrong step resets and clunks, the right sequence
	# opens for good. Driven pad by pad through the real trigger volumes, because
	# the ORDER is the whole mechanism and a lock that latched on "all four pressed"
	# would pass every other assertion in this file.
	for gid: String in TowerInterior.riddle_ids():
		var answer: Array = TowerGraph.gate(gid)["answer"]
		var lock: MeshInstance3D = interior.find_child("*GateMass_%s" % gid, true, false)
		if lock == null or answer.size() < 2:
			_fail("riddle '%s' has no mass or no sequence to enter" % gid)
			continue
		var shut := lock.position.y
		# A deliberately wrong first step: something that is not answer[0].
		var wrong := int(answer[1])
		await _press_pad(hero, interior, gid, wrong)
		if shell.is_opened(gid):
			_fail("riddle '%s' opened on a single wrong pad" % gid)
		if float(interior._riddle_nudge.get(gid, 0.0)) <= 0.0 and int(answer[0]) != wrong:
			_fail("riddle '%s' gave no reaction to a wrong step — the failure is invisible" % gid)
		# THE ORDER IS THE PUZZLE, so the control is the same four pads BACKWARDS.
		# A lock that counted presses rather than reading a sequence passes every
		# other line here and fails this one.
		var backwards := answer.duplicate()
		backwards.reverse()
		for step in backwards:
			await _press_pad(hero, interior, gid, int(step))
		if shell.is_opened(gid):
			_fail(("riddle '%s' opened on its own answer BACKWARDS — the lock is counting "
				+ "presses, not reading an order") % gid)
		# Step off, so the first digit of the real answer reads as a fresh press
		# rather than as the pad the player was already standing on.
		hero.global_position = lock.global_position
		await _settle_physics()
		interior._process(0.05)
		# ...then the sequence, in order, from the top.
		for step in answer:
			await _press_pad(hero, interior, gid, int(step))
		if not shell.is_opened(gid):
			_fail("riddle '%s' did not open on its own answer %s" % [gid, str(answer)])
		for _i in 40:
			interior._process(0.1)
		var travel := TowerInterior.riddle_travel(lock)
		if absf(lock.position.y - (shut + travel)) > 0.01:
			_fail("riddle '%s' stopped at %.2f m, expected %.2f m" % [
				gid, lock.position.y, shut + travel])
		var lock_shape := body.get_node_or_null("%sShape" % lock.name) as CollisionShape3D
		if lock_shape == null or absf(lock_shape.position.y - lock.position.y) > EPS:
			_fail("riddle '%s' opened only visually — its collision shape is still in the way"
				% gid)
		# ...and it is RETIRED at the end of the travel. A mass is as tall as its room,
		# so a fully risen one is a floor-to-ceiling block standing in the storey above
		# — see `_retire`. The spine doors' half of that is asserted at check 12; this
		# is the riddles' half, and `_place_riddle` is the other caller.
		if lock.visible or (lock_shape != null and not lock_shape.disabled):
			_fail(("riddle '%s' finished its travel still drawn and solid — it is now a "
				+ "%.1f m block standing in the storey above") % [
					gid, TowerInterior.riddle_travel(lock)])
		# ...and a sequence COMPLETED BUT NEVER RECORDED starts again from the top
		# instead of indexing past its own answer. That is not hypothetical: the
		# open state lives on the shell, so an interior built with no tower over it
		# — which is what `_make_interior()` does twice in this file — finishes the
		# answer, records nothing and steps on the next pad. Driven directly,
		# because the assertion is about the index and the walk above already
		# covers the trigger path.
		interior._riddle_step[gid] = answer.size()
		interior._press_riddle(gid, int(answer[0]))
		if int(interior._riddle_step[gid]) != 1:
			_fail(("riddle '%s' did not restart a completed-but-unrecorded sequence — it read "
				+ "step %d of a %d-step answer") % [
					gid, int(interior._riddle_step[gid]), answer.size()])

	# (h) THE LIFT STOP, phase 16. Everything else about it is structural — one
	# `Area3D`, on the right storey, at the right height — and a trigger wired to
	# the wrong id, or to nothing, is all of those things. So stand on it: the
	# entry the graph names has to end up in the opened set, and a body that is not
	# the local player must not put it there (the shell filters the doorway; this
	# volume filters itself, and the two are different code).
	var stop_area := interior.find_child("LiftStopTrigger", true, false) as Area3D
	if TowerInterior.lift_stop_floor() >= 0:
		if stop_area == null:
			_fail("a storey carries the lift stop's landing but no LiftStopTrigger to stand on")
		else:
			var passer := Node3D.new()
			interior._on_lift_stop_enter(passer)
			passer.free()
			if shell.is_opened(TowerGraph.ENTRY_LIFT_MAZE):
				_fail("the lift stop armed for a body that is not in group \"player\"")
			hero.global_position = stop_area.global_position
			await _settle_physics()
			if not shell.is_opened(TowerGraph.ENTRY_LIFT_MAZE):
				_fail(("standing on the lift stop did not record '%s' — the trigger is wired "
					+ "to nothing the graph names") % TowerGraph.ENTRY_LIFT_MAZE)

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


func _press_pad(hero: Node3D, interior: TowerInterior, gate_id: String, digit: int) -> void:
	## Stand the probe on one riddle lock pad and let the interior read it.
	##
	## Through the REAL trigger volume and the real poll, not by calling
	## `_press_riddle` — the thing worth asserting is that standing somewhere enters
	## a step, which is the half a direct call would skip straight past.
	var area := interior.find_child("RiddleTrigger_%s_%d" % [gate_id, digit], true, false) as Area3D
	if area == null:
		_fail("riddle '%s' has no trigger volume for pad %d" % [gate_id, digit])
		return
	hero.global_position = area.global_position
	await _settle_physics()
	interior._process(0.05)


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
	var riddles := TowerInterior.riddle_ids()
	shell.opened = {
		TowerInterior.GATE_DEMAND: true,
		TowerInterior.GATE_IDENTITY: true,
		TowerInterior.GATE_CHECKPOINT: true,
	}
	# ...and every riddle, because a solved riddle is in the same monotone set and
	# has to come back solved for the same reason — the sequence is entered once,
	# ever, and a tower that asked for it again after a reload would be re-locking
	# a gate somebody earned.
	for gid: String in riddles:
		shell.opened[gid] = true
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

	for gid2: String in riddles:
		var rest := 0.0
		var mesh := interior.find_child("*GateMass_%s" % gid2, true, false) as MeshInstance3D
		for box: Dictionary in TowerInterior.all_boxes():
			if String(box["name"]).ends_with("GateMass_%s" % gid2):
				rest = box["pos"].y
		if mesh == null:
			_fail("riddle '%s' built no mass at all" % gid2)
			continue
		var travel2 := TowerInterior.riddle_travel(mesh)
		if absf(mesh.position.y - (rest + travel2)) > EPS:
			_fail("a pre-opened tower rebuilt riddle '%s' shut (y = %.2f, wanted %.2f)" % [
				gid2, mesh.position.y, rest + travel2])
		var riddle_shape := body.get_node_or_null("%sShape" % mesh.name) as CollisionShape3D
		if riddle_shape == null or absf(riddle_shape.position.y - mesh.position.y) > EPS:
			_fail("a pre-opened tower left riddle '%s' with its collision shape in the doorway"
				% gid2)
		# `_apply_opened()` snaps a loaded save straight to 1.0, which is the case
		# `_retire` says matters: on this path the mass is never drawn travelling, so
		# a miss here is a solid block in the room above from the moment you walk in.
		if mesh.visible or (riddle_shape != null and not riddle_shape.disabled):
			_fail(("a pre-opened tower left riddle '%s' drawn and solid a storey up — "
				+ "the load path never retired it") % gid2)

	# The set itself is monotone and idempotent — phase 5 merges these with a union.
	shell.mark_opened(TowerInterior.GATE_DEMAND)
	if shell.opened_ids().size() != 3 + riddles.size():
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

	PHASE 16 IS WHERE IT PAYS FOR ITSELF. Ten storeys, and the two heaviest are the
	labyrinth's — so this now asserts three things a five-storey building could not
	be asked: at most three storeys drawn from anywhere (floor 2, whose slab caps
	both the annulus and the keep, is the one four), the cell block hidden from
	every storey more than one below it, and — driven live, standing on each floor
	in turn — that walking up the building REBUILDS NOTHING and only toggles
	`visible`.
	"""
	# PHASE 14 REPLACED THE ARITHMETIC WITH A TABLE, so this asserts the PROPERTIES a
	# visibility relation has to have plus the geometric facts THIS building has —
	# never `FLOOR_NEIGHBOURS` read back to itself, which would check nothing.
	var floors: int = TowerInterior.FLOOR_Y.size()
	for current in floors:
		if not TowerInterior._floor_visible(current, current):
			_fail("floor %d hides itself" % current)
		var seen := 0
		for index in floors:
			# Symmetric: "A touches B" and "B touches A" are the same claim, and a
			# half-written row is exactly how a ceiling ends up solid and invisible.
			if TowerInterior._floor_visible(index, current) \
					!= TowerInterior._floor_visible(current, index):
				_fail("floors %d and %d disagree about whether they touch" % [index, current])
			if TowerInterior._floor_visible(index, current):
				seen += 1
		# The budget half: the window exists to stop the whole building drawing.
		# THREE IS THE RULE AND FLOOR 2 IS THE ONE EXCEPTION — its slab is the
		# ceiling of the annulus AND of the keep's landing, so it touches three
		# storeys and draws four. Everywhere else in a ten-storey building it is
		# yourself plus the storey under you plus the storey over you, which is
		# what "standing on storey 9 draws 8, 9 and 10 and nothing else" means.
		var allowed := 4 if current == 2 else 3
		if seen > allowed:
			_fail("standing on floor %d draws %d storeys, over its allowance of %d — the window has stopped gating" % [
				current, seen, allowed])
	# ...and the building's own geometry, spelled out so a reader can check it
	# against the plan. A slab is the ceiling of everything under it, and floor 2's
	# roofs BOTH the annulus and the keep's landing; floors 3 to 9 are an ordinary
	# stack all the way to the cell block under the sealed roof; nothing else
	# touches.
	var touching: Array[Array] = [[0, 1], [0, 2], [1, 2], [2, 3], [3, 4],
			[4, 5], [5, 6], [6, 7], [7, 8], [8, 9]]
	var apart: Array[Array] = [[0, 3], [0, 4], [1, 3], [1, 4], [2, 4],
			[2, 5], [4, 6], [6, 9], [7, 9], [0, 9]]
	for pair: Array in touching:
		if not TowerInterior._floor_visible(pair[0], pair[1]):
			_fail("floor %d is hidden from floor %d, which it physically touches — "
				% [pair[0], pair[1]] + "that is solid stone nobody can see")
	for pair2: Array in apart:
		if TowerInterior._floor_visible(pair2[0], pair2[1]):
			_fail("floor %d draws from floor %d, which it does not touch" % [
				pair2[0], pair2[1]])
	# THE CELL BLOCK IS NOT VISIBLE FROM THE MAZE, and that is a design claim and
	# not a budget one: the labyrinth is the obstacle, and a player who can see the
	# gallery through the floor while standing in the maze has been told which way
	# to go. Asked of the storey that actually draws the block rather than of "9",
	# so re-planning it onto another floor re-asks the same question there.
	var block := TowerInterior.block_floor()
	if block < 0:
		_fail("no storey draws the cell block — this assertion would pass vacuously")
	else:
		for below in block - 1:
			if TowerInterior._floor_visible(block, below):
				_fail("the cell block (floor %d) draws from floor %d, two storeys or more "
					% [block, below] + "below it — the maze must not show its own exit")
	# EVERY WALKING SURFACE, AND THE AIR JUST UNDER IT. `current_floor` is a walk of
	# `FLOOR_Y` and runs every `_process`, so the assertion is over the whole table
	# rather than over the two storeys this check was written with: standing on a
	# surface reads as that storey, and a hysteresis below it reads as the one
	# beneath. With five storeys an off-by-one in that walk would hide the floor you
	# are standing on.
	for i in TowerInterior.FLOOR_Y.size():
		var surface: float = TowerInterior.FLOOR_Y[i]
		if TowerInterior.current_floor(surface) != i:
			_fail("standing on storey %d (%.2f m) read as storey %d" % [
				i, surface, TowerInterior.current_floor(surface)])
		var below := surface - TowerInterior.FLOOR_HYSTERESIS - 0.1
		var want_below := maxi(i - 1, 0)
		if TowerInterior.current_floor(below) != want_below:
			_fail("%.2f m — a hysteresis under storey %d — read as storey %d, expected %d" % [
				below, i, TowerInterior.current_floor(below), want_below])

	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var hero := ProbePlayer.new()
	hero.add_to_group("player")
	root.add_child(hero)

	hero.global_position = Vector3(TowerInterior.DRAW_RADIUS * 4.0, 0.0, 0.0)
	interior._process(0.05)
	if interior.visible:
		_fail("the interior still draws with the player %.0f m away" % (TowerInterior.DRAW_RADIUS * 4.0))
	if hero.indoor != false:
		_fail("the building told a player %.0f m away that they were indoors (got %s)" % [
			TowerInterior.DRAW_RADIUS * 4.0, hero.indoor])

	hero.global_position = shell.global_position + Vector3(4.0, 0.0, 0.0)
	interior._process(0.05)
	if not interior.visible:
		_fail("the interior does not draw with the player standing inside it")
	# THE POLICY'S OWN ANSWER, not "everything is visible". With five storeys the
	# +/- 1 window finally bites on a live building — a player on the ground floor
	# is shown storeys 0 and 1 and NOT the office floors 11 m over their head — so a
	# check that still asserted "all visible" would be asserting the bug the window
	# exists to prevent. The two statements agreed while the building had two
	# storeys, which is exactly why this had to be rewritten rather than extended.
	for i in TowerInterior.FLOOR_Y.size():
		var floor_node := interior.get_node_or_null("Floor%d" % i) as Node3D
		if floor_node == null:
			_fail("storey %d has no container — visibility gating has nothing to toggle" % i)
			continue
		var want_visible := TowerInterior._floor_visible(i, 0)
		if floor_node.visible != want_visible:
			_fail("storey %d is %s from a player on the ground floor; the policy says %s" % [
				i, "visible" if floor_node.visible else "hidden",
				"visible" if want_visible else "hidden"])
	if hero.indoor != true:
		_fail("the building did not put the indoor camera on a player standing in its entry hall (got %s)" % hero.indoor)

	# WALKING UP THE BUILDING REBUILDS NOTHING. `_update_visibility` is one boolean
	# write per storey and that is the whole claim — the maze's storeys are the
	# heaviest in the building, so a policy that freed and rebuilt a batch on the
	# 8 -> 9 step would be a hitch on exactly the floor the player is being chased
	# across. Driven over EVERY storey, comparing the container instance ids and
	# their child counts before and after: a rebuild changes one or the other.
	var before_ids: Array[int] = []
	var before_children: Array[int] = []
	for i in TowerInterior.FLOOR_Y.size():
		var node := interior.get_node_or_null("Floor%d" % i) as Node3D
		before_ids.append(0 if node == null else node.get_instance_id())
		before_children.append(0 if node == null else node.get_child_count())
	for standing in TowerInterior.FLOOR_Y.size():
		hero.global_position = interior.global_position \
				+ Vector3(4.0, TowerInterior.FLOOR_Y[standing] + 0.1, 0.0)
		interior._process(0.05)
		for i in TowerInterior.FLOOR_Y.size():
			var node2 := interior.get_node_or_null("Floor%d" % i) as Node3D
			if node2 == null or node2.get_instance_id() != before_ids[i] \
					or node2.get_child_count() != before_children[i]:
				_fail("standing on storey %d rebuilt storey %d's container — the window "
					% [standing, i] + "toggles `visible` and does nothing else")
				continue
			var want := TowerInterior._floor_visible(i, standing)
			if node2.visible != want:
				_fail("standing on storey %d, storey %d is %s; the policy says %s" % [
					standing, i, "visible" if node2.visible else "hidden",
					"visible" if want else "hidden"])

	# THE THIRD POSITION IS THE ONE THAT MATTERS: near enough to draw, but OUTSIDE
	# the walls. "Near" and "indoors" are different questions and a gate that
	# answered the first one twice would pass both lines above.
	hero.global_position = shell.global_position \
			+ Vector3(TowerShell.OUTER_HALF + 5.0, 0.0, 0.0)
	interior._process(0.05)
	if hero.indoor != false:
		_fail("the building claimed a player standing 5 m outside its front wall was indoors")
	# ...and the same for a Windman sightseeing over the parapet.
	if TowerInterior.inside_walls(Vector3(0.0, TowerShell.WALL_HEIGHT + 5.0, 0.0)):
		_fail("a point %.0f m over the wall top reads as inside the building" % (TowerShell.WALL_HEIGHT + 5.0))

	# THE BUILDING FREED OUT FROM UNDER A PLAYER STANDING IN IT. Joining a
	# multiplayer room mid-run does exactly this — `new_run()` resets the shell and
	# then teleports, with no respawn to clean up after it — and the room is the
	# only thing that ever clears the indoor boom, so without `_exit_tree` the short
	# arm would stay on for the rest of the session, outdoors.
	hero.global_position = shell.global_position + Vector3(4.0, 0.0, 0.0)
	interior._process(0.05)
	if hero.indoor != true:
		_fail("the probe is not indoors, so the teardown case below would pass vacuously")
	shell.free()
	if hero.indoor != false:
		_fail("freeing the building left the player holding the indoor camera")

	hero.queue_free()
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
		# A floor index carrying no static geometry builds no batch at all (see
		# `_ready`) — an empty mesh is a node and a `DRAW_BUDGET` slot for nothing.
		# That is not a failure here: any box that SHOULD have been batched onto this
		# storey fails the corner test below, by name, which is the better report.
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

func _check_the_block_has_no_way_round_it() -> void:
	"""
	Check 11. The block's two runs are sealed end to end, every spine mass really
	fills its doorway, and the press is a challenge rather than a formality.

	WHY SAMPLING AND NOT ARITHMETIC. The doors, the piers and the recess dividers
	are all `#` and `D` cells on one grid now, so asserting that four doorways and
	three piers add up would be asking the plan whether it agrees with itself. What
	matters is the WORLD: walk the spine line in 5 cm steps and ask the box table
	whether there is stone or a shut mass at head height. A pier that stopped one
	cell short, a mass narrower than its doorway, a fifth `D` run typed into the
	wall — all of them are a hole, and a hole in that wall is a route the softlock
	audit does not model and cannot see.
	"""
	var floor_index := TowerInterior.block_floor()
	if floor_index < 0:
		_fail("no storey draws a '%s' — the cell block is not in the building at all"
			% TowerInterior.BLOCK_ROOM)
		return
	var plan := TowerPlans.storey(floor_index)
	var surface: float = TowerInterior.FLOOR_Y[floor_index]
	var clear := TowerInterior.plan_clear_height(floor_index)
	var head := surface + clear * 0.5
	var by_name := {}
	for box: Dictionary in TowerInterior.all_boxes():
		by_name[String(box["name"])] = box

	# (a) The spine line is solid from end to end while every gate is shut. Head
	#     height, because that is where a gap would be walked through. The line is
	#     the row the four `D` runs are drawn in, and its extent is the corridor's.
	var doors := TowerInterior.SPINE_DOORS.size()
	var first_run: Rect2i = TowerInterior.plan_gate_rect(
		floor_index, String(TowerInterior.SPINE_DOORS[0]["gate"]))
	if first_run.size == Vector2i.ZERO:
		_fail("no '%s' run on storey %d for the first spine door" % [
			TowerPlans.GATE_CHAR, floor_index])
		return
	var corridor := TowerInterior.plan_room_rect(floor_index, "service_stair")
	var gallery := TowerInterior.plan_room_rect(floor_index, TowerInterior.BLOCK_ROOM)
	var spine_z := _grid_centre(first_run.position.y)
	var x := _grid_edge(mini(corridor.position.x, gallery.position.x)) + 0.02
	var x_end := _grid_edge(maxi(corridor.end.x, gallery.end.x))
	while x < x_end:
		if not _solid_at(x, spine_z, head):
			_fail("the spine wall has a hole at x = %.2f — the four identity gates can be walked round" % x)
			break
		x += 0.05
	# ...and the cell row, so a captive's recess is a recess and not a through-way.
	var widest_cell := 0.0
	for hero: String in TowerGraph.HEROES:
		var rect := TowerInterior.plan_room_rect(floor_index, "cell_%s" % hero)
		if rect.size == Vector2i.ZERO:
			_fail("no recess is drawn for %s — his cell cannot be entered" % hero)
			continue
		widest_cell = maxf(widest_cell,
			_grid_edge(rect.end.x) - _grid_edge(rect.position.x))
	var back_z := _grid_centre(TowerInterior.plan_room_rect(
		floor_index, "cell_%s" % String(TowerGraph.HEROES[0])).position.y)
	x = _grid_edge(mini(corridor.position.x, gallery.position.x)) + 0.02
	var open_run := 0.0
	var widest := 0.0
	while x < x_end:
		if _solid_at(x, back_z, head):
			open_run = 0.0
		else:
			open_run += 0.05
			widest = maxf(widest, open_run)
		x += 0.05
	# The widest unbroken opening across the cells' back line must be one recess,
	# not two: a missing divider reads as a cell block with a corridor behind it.
	if widest > widest_cell + 0.1:
		_fail("the cell row has a %.2f m unbroken opening but the widest recess is %.2f m — a divider is missing" % [
			widest, widest_cell])

	# (b) Every mass fills its doorway to the ceiling and stands in the spine line,
	#     and every one has a pad on the side you approach it from.
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
		var run := TowerInterior.plan_gate_rect(floor_index, gid)
		if run.size == Vector2i.ZERO:
			_fail("spine door '%s' has no '%s' run on storey %d" % [
				gid, TowerPlans.GATE_CHAR, floor_index])
			continue
		var door_w := _grid_edge(run.end.x) - _grid_edge(run.position.x)
		var mass: Dictionary = by_name.get(String(door["mass"]), {})
		if mass.is_empty():
			_fail("spine door '%s' names a mass '%s' the interior does not build" % [
				gid, String(door["mass"])])
			continue
		if not is_equal_approx(mass["size"].x, door_w):
			_fail("%s is %.2f m wide in a %.2f m doorway — you can walk past it" % [
				String(door["mass"]), mass["size"].x, door_w])
		if not is_equal_approx(mass["size"].y, clear):
			_fail("%s is %.2f m tall under a %.2f m ceiling — you can get over it" % [
				String(door["mass"]), mass["size"].y, clear])
		if not is_equal_approx(mass["pos"].x, _grid_centre_span(run.position.x, run.end.x)):
			_fail("%s stands at x = %.3f, not in its own doorway at x = %.3f" % [
				String(door["mass"]), mass["pos"].x,
				_grid_centre_span(run.position.x, run.end.x)])
		# THE PAD IS ON THE SIDE YOU WALK UP FROM, which is the corridor and never
		# the gallery — a pad on the far side is a gate you open from inside the
		# room it guards, and nothing else in this file would notice.
		var pad: Dictionary = by_name.get(String(door["pad"]), {})
		if pad.is_empty():
			_fail("spine door '%s' has no pad — its doorway resolved no side to stand on" % gid)
			continue
		var pad_cell := TowerInterior.gate_pad_cell(plan, run)
		if signi(pad_cell.y - run.position.y) \
				!= signi(corridor.position.y - run.position.y):
			_fail("spine door '%s's pad is on the far side of its own doorway — it opens from inside the room it guards" % gid)
	for hero2: String in TowerGraph.HEROES:
		if not wanted.has(hero2):
			_fail("no spine door in the building opens for %s — his rescue spine is not built" % hero2)

	# (c) A sunk mass leaves NOTHING in its doorway. A lip of any height is a wall
	#     in this engine, so "nearly flush" is the same bug as "shut".
	var open_top := clear - TowerInterior.SPINE_TRAVEL
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
	var duct := TowerInterior.plan_gate_rect(floor_index, "maintenance_crawl")
	if duct.size == Vector2i.ZERO:
		_fail("the maintenance crawl has no '%s' run on storey %d" % [
			TowerPlans.GATE_CHAR, floor_index])
		return
	var duct_x0 := _grid_edge(duct.position.x)
	var duct_x1 := _grid_edge(duct.end.x)
	var press_half: Vector3 = press["size"] * 0.5
	if press["pos"].x - press_half.x < duct_x0 - EPS \
			or press["pos"].x + press_half.x > duct_x1 + EPS:
		_fail("the press spans x = %.2f .. %.2f but the crawl doorway is %.2f .. %.2f — it stamps a wall" % [
			press["pos"].x - press_half.x, press["pos"].x + press_half.x,
			duct_x0, duct_x1])
	if not is_equal_approx(press["pos"].z, _grid_centre_span(duct.position.y, duct.end.y)):
		_fail("the press stands at z = %.2f, not in its duct at z = %.2f" % [
			press["pos"].z, _grid_centre_span(duct.position.y, duct.end.y)])
	if int(press["floor"]) != floor_index:
		_fail("the press claims storey %d and its duct is drawn on storey %d" % [
			int(press["floor"]), floor_index])
	# ...and every height below is measured from the STOREY, because that is what
	# `press_y` produces and what `_tick_press` adds the surface to.
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
	# ...and the lintel the challenge arm hung over the same run really is there and
	# really is stone: without it the duct is a doorway with a bar swinging in it.
	var lintel: Dictionary = by_name.get(
		"%sGateLintel_maintenance_crawl" % ("S%dPlan" % floor_index), {})
	if lintel.is_empty():
		_fail("the crawl's duct has no lintel — nothing tells the player it is a duct")
	elif not is_equal_approx(lintel["pos"].y - lintel["size"].y * 0.5,
			surface + TowerInterior.CRAWL_LINTEL_Y):
		_fail("the crawl lintel's underside is at %.2f m, not the declared %.2f m" % [
			lintel["pos"].y - lintel["size"].y * 0.5,
			surface + TowerInterior.CRAWL_LINTEL_Y])
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
	print("cell block: storey %d, %d spine doors, %d recesses up to %.2f m wide; press %.2f .. %.2f m over a %.2f m floor" % [
		floor_index, doors, TowerGraph.HEROES.size(), widest_cell,
		TowerInterior.PRESS_BOTTOM, TowerInterior.PRESS_TOP, surface])


func _grid_edge(cell: int) -> float:
	"""A plan cell EDGE, in interior metres. The grid is square, so one function."""
	return -TowerPlans.PLAN_HALF + float(cell) * TowerPlans.PLAN_CELL


func _grid_centre(cell: int) -> float:
	"""One plan cell's centre, in interior metres."""
	return _grid_edge(cell) + TowerPlans.PLAN_CELL * 0.5


func _grid_centre_span(lo: int, hi: int) -> float:
	"""The centre of a run from cell `lo` to cell edge `hi` (a `Rect2i.end`)."""
	return (_grid_edge(lo) + _grid_edge(hi)) * 0.5


func _solid_at(x: float, z: float, y: float) -> bool:
	"""
	Is there a solid interior box at this point, with every gate SHUT?

	@return: true when some collidable, untilted box in `boxes()` contains it.

	`all_boxes()` is the WHOLE building in its closed state, which is exactly the
	state check 11 wants: the question is whether a route exists BEFORE anybody
	opens anything. It reads the plan storeys too since phase 16, because the cell
	block's walls and its four masses are drawn there now. The ramp is skipped for
	the same reason check 2 skips it — a tilted slab's AABB claims stone it does not
	have.

	AND SO ARE SCAR BOXES (bead godot-test1-3iy.11): "closed state" means every gate
	shut, not every scar taken. A scar is the one thing in this building that
	REMOVES a passage, so counting it here would make the base plan describe a tower
	the softlock audit never walks — and would hide the very drift check 16 exists
	to catch. Check 16 samples them deliberately, and is the only thing that does.
	"""
	for box: Dictionary in TowerInterior.all_boxes():
		if not box["collide"] or box.has("rot") or String(box.get("scar", "")) != "":
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if absf(pos.x - x) <= half.x and absf(pos.z - z) <= half.z and absf(pos.y - y) <= half.y:
			return true
	return false


# ============================================================================
# CHECK 16 — the full-custody protocol's geometry (bead godot-test1-3iy.11)
# ============================================================================

## Half the player's collision capsule. The default `CapsuleShape3D` in
## `player.tscn`, and the reason the stand below needs any clearance at all: a body
## dropped with a wall inside its radius is shoved out of it on the first frame,
## which in a 2 m corridor means shoved through the wall on the far side.
const PLAYER_RADIUS: float = 0.5


func _check_the_custody_stand_and_the_scar() -> void:
	"""
	Check 16. The break-out scene stands the party somewhere real, and the scar it
	can earn is a passage that was open and is now stone.

	TWO THINGS, ONE CHECK, because they are the two ends of the same scene and both
	are invisible in a screenshot until somebody plays twenty minutes to reach it.

	(a) THE STAND. `TowerInterior.custody_stand()` is where the protocol teleports
	    the party. It has to be inside the service corridor, clear of every solid
	    box by a body radius, on the CORRIDOR side of the spine wall (a stand in the
	    gallery would put the party three metres from a cell and there would be no
	    scene at all), and it has to leave the spring arm something to extend into.
	    It is derived from the corridor's own plan cells since phase 16 — it used to
	    be a bare `Vector3`, which is the exact shape of constant that ends up 40 cm
	    inside a wall the day a doorway moves, and phase 16 moved every doorway in
	    this room 46 m upwards.

	(b) THE SCAR. `boxes()` is the UNSCARRED plan — `_solid_at` skips scar boxes for
	    exactly that reason — so the doorway the scar fills must be walkable in it
	    and stone with the scar box counted. That is what stops the two halves of
	    the feature drifting into "the rubble was always there" (a passage the
	    softlock audit thinks exists and the player never had) or "the rubble is
	    scenery" (a scar the audit removes and the player walks straight through).
	"""
	# --- (a) the stand -------------------------------------------------------
	var floor_index := TowerInterior.block_floor()
	if floor_index < 0:
		_fail("no storey draws the cell block — the custody scene has nowhere to open")
		return
	var surface: float = TowerInterior.FLOOR_Y[floor_index]
	var clear := TowerInterior.plan_clear_height(floor_index)
	var corridor := TowerInterior.plan_room_rect(floor_index, "service_stair")
	var stand: Vector3 = TowerInterior.custody_stand()
	var corridor_z0 := _grid_edge(corridor.position.y)
	var corridor_z1 := _grid_edge(corridor.end.y)
	if stand.z <= corridor_z0 or stand.z >= corridor_z1:
		_fail(("the custody stand is at z = %.2f, outside the service corridor's own cells "
			+ "(%.2f .. %.2f) — the break-out would start in the wrong room")
			% [stand.z, corridor_z0, corridor_z1])
	if stand.x <= _grid_edge(corridor.position.x) or stand.x >= _grid_edge(corridor.end.x):
		_fail("the custody stand is at x = %.2f, off the end of the corridor (%.2f .. %.2f)"
			% [stand.x, _grid_edge(corridor.position.x), _grid_edge(corridor.end.x)])
	if stand.y < surface or stand.y + PLAYER_HEIGHT > surface + clear:
		_fail("the custody stand puts a %.1f m body at y = %.2f on a %.2f m floor with %.2f m clear" % [
			PLAYER_HEIGHT, stand.y, surface, clear])

	# Clear of every solid box, sampled around the capsule at knee, waist and head:
	# one point would miss a lintel, and a wall the body's RADIUS reaches into is a
	# body shoved sideways on frame one.
	for angle_step in 16:
		var theta := TAU * float(angle_step) / 16.0
		var px := stand.x + cos(theta) * PLAYER_RADIUS
		var pz := stand.z + sin(theta) * PLAYER_RADIUS
		for probe_y: float in [0.4, 1.0, 1.8]:
			if _solid_at(px, pz, stand.y + probe_y):
				_fail(("the custody stand's body reaches solid geometry at (%.2f, %.2f, %.2f)"
					+ " — the party would be shoved through a wall on the first frame")
					% [px, stand.y + probe_y, pz])
				break

	# ...and it is not standing on a spine pad's trigger, which would fire a door's
	# refusal line on the frame the scene opens, before the player has read anything.
	var plan := TowerPlans.storey(floor_index)
	for i in TowerInterior.SPINE_DOORS.size():
		var run := TowerInterior.plan_gate_rect(
			floor_index, String(TowerInterior.SPINE_DOORS[i]["gate"]))
		if run.size == Vector2i.ZERO:
			continue
		var cell := TowerInterior.gate_pad_cell(plan, run)
		if cell.x < 0:
			continue
		var dx: float = absf(stand.x - _grid_centre(cell.x)) - TowerPlans.PLAN_CELL * 0.5
		var dz: float = absf(stand.z - _grid_centre(cell.y)) \
				- TowerInterior.PAD_TRIGGER_DEPTH * 0.5
		if dx < PLAYER_RADIUS and dz < PLAYER_RADIUS:
			_fail("the custody stand overlaps spine pad %d's trigger" % i)

	# THE CAMERA. Facing the way the protocol turns the body (+X, `SPAWN_FACING_Y`),
	# there has to be more than HALF an arm of corridor behind it, which is the
	# difference between a shot and the back of a head. The plan-grid corridor is
	# long enough that the arm extends fully; the assertion stays the weaker one the
	# constant's comment made, because the claim it protects has not changed.
	var arm: float = _spring_length()
	var behind: float = stand.x - _grid_edge(corridor.position.x)
	if behind < arm * 0.5:
		_fail(("the custody stand leaves the %.2f m spring arm only %.2f m of corridor to "
			+ "back into — the scene opens on the back of the hero's head")
			% [arm, behind])

	# --- (b) the scar --------------------------------------------------------
	var scar_boxes: Array[Dictionary] = []
	for box: Dictionary in TowerInterior.all_boxes():
		if String(box.get("scar", "")) != "":
			scar_boxes.append(box)
	if scar_boxes.is_empty():
		_fail("the interior builds no scar box — the full-custody scar is data only")
		return
	for box: Dictionary in scar_boxes:
		var pos: Vector3 = box["pos"]
		# Open BEFORE. `_solid_at` walks the unscarred plan by construction.
		if _solid_at(pos.x, pos.z, pos.y):
			_fail(("scar box '%s' fills a doorway that is already stone in the unscarred "
				+ "plan — it takes nothing away") % String(box["name"]))
		# ...and stone AFTER, at head height across its whole span, so a scar cannot
		# be a waist-high pile you walk over. Measured from ITS OWN STOREY's walking
		# surface: the rubble moved 46 m up with the cell block.
		var half: Vector3 = box["size"] * 0.5
		var base: float = TowerInterior.FLOOR_Y[int(box["floor"])]
		var head := base + TowerInterior.plan_clear_height(int(box["floor"])) * 0.5 \
				if int(box["floor"]) >= 2 else base + TowerInterior.headroom() * 0.5
		if pos.y - half.y > base + EPS or pos.y + half.y < head:
			_fail(("scar box '%s' spans y = %.2f .. %.2f on a floor at %.2f; a closed "
				+ "passage has to reach from the floor past head height (%.2f)")
				% [String(box["name"]), pos.y - half.y, pos.y + half.y, base, head])

	print("custody scene: stand (%.2f, %.2f, %.2f), %.2f m behind the camera; %d scar box(es)"
		% [stand.x, stand.y, stand.z, behind, scar_boxes.size()])


func _spring_length() -> float:
	"""
	The camera arm's real length, off `player.tscn`, never a literal.

	The same discipline check 4 uses: a shorter arm is a `player_controller`
	decision this file must MOVE with rather than re-assert against.
	"""
	var player: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	var arm: SpringArm3D = player.get_node_or_null("CameraPivot/CameraArm") as SpringArm3D
	var length := arm.spring_length if arm != null else 0.0
	player.free()
	return length


# ============================================================================
# CHECK 17 — the custody scene, driven (bead godot-test1-3iy.11)
# ============================================================================

func _check_the_custody_scene_runs() -> void:
	"""
	Check 17. Raised containment and the scar, on a real building under real frames.

	CHECK 16 IS THE PLAN; THIS IS THE BUILDING. Every failure it catches is one
	where the feature is shipped, green and INERT — the exact shape of bug that
	survives a check which hands itself the input the game never supplies:

	  a. containment that never comes down on doors a hundred rescues opened, so the
	     break-out is walking three metres to a cell and there is no scene;
	  b. containment that comes down and then TWEENS STRAIGHT BACK OPEN, because
	     `_tick_gates` still believes the opened set — same outcome, one frame later;
	  c. a pad that never RELEASES it, which is worse: the scene is unwinnable and
	     every player loses their campaign to a bug;
	  d. a pad that releases it for the WRONG HERO, which is (a) with extra steps;
	  e. rubble that is recorded and never drawn, or drawn and never solid — the
	     permanent consequence the whole bead is about, walked straight through.

	All five are driven through the shipped verbs (`begin_lockdown`, the real pad
	tick, `apply_scar`) on a tower assembled the way `endless_terrain` assembles it.
	"""
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("custody: the tower has no TowerInterior child")
		await _clear(null, shell)
		return

	# A probe standing in the building, because `_process` gates everything on the
	# player being near enough to draw — without one, every tick below is a no-op
	# and every assertion after it would pass on any build at all.
	var hero_body := ProbePlayer.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	hero_body.add_child(shape)
	hero_body.add_to_group("player")
	root.add_child(hero_body)
	hero_body.global_position = shell.global_position + TowerInterior.custody_stand()
	await _settle_physics()

	var door: Dictionary = TowerInterior.SPINE_DOORS[0]
	var gate_id := String(door["gate"])
	var wants := TowerGraph.identity_of(gate_id)
	var wrong := "teibi" if wants != "teibi" else "windman"
	var mass := interior.find_child(String(door["mass"]), true, false) as MeshInstance3D
	var body := interior.get_node_or_null("InteriorCollision") as StaticBody3D
	var mass_shape := body.get_node_or_null("%sShape" % String(door["mass"])) as CollisionShape3D
	if mass == null or mass_shape == null:
		_fail("custody: spine door '%s' has no mass or no collision shape" % gate_id)
		await _clear(hero_body, shell)
		return
	var shut_y: float = mass.position.y
	var open_y: float = shut_y - TowerInterior.SPINE_TRAVEL

	# An EARLIER RESCUE opened this door for good, which is the only starting state
	# in which raised containment means anything at all.
	shell.mark_opened(gate_id)
	for _i in 40:
		interior._process(0.1)
	if absf(mass.position.y - open_y) > 0.01:
		_fail("custody: the earned door never opened, so nothing below is measured")

	# (a) the protocol arrives and shuts it again.
	interior.begin_lockdown()
	if absf(mass.position.y - shut_y) > 0.01:
		_fail("custody: containment was raised and '%s' stayed at %.2f m (open is %.2f) — "
			% [gate_id, mass.position.y, open_y] + "the break-out has nothing to do")
	if absf(mass_shape.position.y - mass.position.y) > EPS:
		_fail("custody: '%s' shut visually and left its doorway walkable" % gate_id)

	# (b) ...and it STAYS shut. The opened set still says this door is open, so a
	#     `_tick_gates` that does not consult the lockdown re-opens it here.
	for _i in 40:
		interior._process(0.1)
	if absf(mass.position.y - shut_y) > 0.01:
		_fail("custody: '%s' tweened back open under lockdown — the opened set beat the "
			% gate_id + "scene and the break-out is three metres of walking")

	# (d) the wrong hero on the pad releases nothing.
	# THE STOREY IS ASKED, NEVER SPELLED: the block is wherever `TowerPlans` draws a
	# cell gallery, and this path is the one place a literal 9 would rot.
	var block := "Floor%d" % TowerInterior.block_floor()
	var pad_area := interior.get_node_or_null("%s/SpineTrigger1" % block) as Area3D
	if pad_area == null:
		_fail("custody: there is no SpineTrigger1 — the first spine door has no pad")
		await _clear(hero_body, shell)
		return
	hero_body.hero = wrong
	hero_body.global_position = pad_area.global_position
	await _settle_physics()
	interior._process(0.1)
	if not interior.is_locked_down(gate_id):
		_fail("custody: %s released containment on '%s', which answers to %s"
			% [wrong, gate_id, wants])

	# (c) the right hero, standing on the SAME pad without moving, does — and the
	#     door really sinks afterwards.
	hero_body.hero = wants
	interior._process(0.1)
	if interior.is_locked_down(gate_id):
		_fail("custody: %s stood on '%s's pad and containment held — the scene is unwinnable"
			% [wants, gate_id])
	for _i in 40:
		interior._process(0.1)
	if absf(mass.position.y - open_y) > 0.01:
		_fail("custody: containment lifted on '%s' and the mass stayed at %.2f m"
			% [gate_id, mass.position.y])

	# ...and ending the scene puts every other door back the way the save says.
	interior.begin_lockdown()
	interior.end_lockdown()
	for _i in 40:
		interior._process(0.1)
	if absf(mass.position.y - open_y) > 0.01:
		_fail("custody: the scene ended and '%s' was left shut — a door the player earned "
			% gate_id + "was taken away by a scene that only borrowed it")

	# (e) THE SCAR. Hidden and non-solid until taken, stone the moment it is.
	var rubble := interior.find_child(TowerInterior.SCAR_BOX, true, false) as MeshInstance3D
	var rubble_shape := body.get_node_or_null(
		"%sShape" % TowerInterior.SCAR_BOX) as CollisionShape3D
	if rubble == null or rubble_shape == null:
		_fail("custody: the interior builds no '%s' mesh + shape" % TowerInterior.SCAR_BOX)
		await _clear(hero_body, shell)
		return
	if rubble.visible or not rubble_shape.disabled:
		_fail("custody: an unscarred tower already shows the collapse (visible %s, solid %s)"
			% [rubble.visible, not rubble_shape.disabled])
	if not interior.apply_scar(TowerGraph.SCAR_CUSTODY):
		_fail("custody: the interior refused its own authored scar '%s'"
			% TowerGraph.SCAR_CUSTODY)
	if not rubble.visible:
		_fail("custody: the world took the scar and the collapse is invisible")
	if rubble_shape.disabled:
		_fail("custody: the collapse is drawn and walkable — the shortcut is not closed")
	if not shell.is_opened(TowerGraph.SCAR_CUSTODY):
		_fail("custody: the scar is geometry only; it never reached the tower's opened set")
	# An id nobody authored must be refused outright, or "exactly one enumerated
	# scar" is whatever the caller felt like.
	if interior.apply_scar("custody_made_up_scar"):
		_fail("custody: the interior accepted an unauthored scar id")
	await _clear(hero_body, shell)

	# ...and a tower REBUILT from the store comes up scarred, which is the whole
	# meaning of permanent. Same union merge, same lesson as check 10.
	var relaunched := await _make_tower()
	var reborn := relaunched.get_node_or_null("TowerInterior") as TowerInterior
	var reborn_rubble := reborn.find_child(TowerInterior.SCAR_BOX, true, false) as MeshInstance3D
	if reborn_rubble == null or not reborn_rubble.visible:
		_fail("custody: a tower rebuilt from the store came up unscarred — the collapse "
			+ "healed itself across a relaunch")
	await _clear(null, relaunched)
	_fresh_store()
	print("custody scene: containment raised, released by %s, and the doorway collapsed" % wants)


# ============================================================================
# CHECK 12 — the cell block's acceptance walk (bead godot-test1-3iy.8)
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
	var block := "Floor%d" % TowerInterior.block_floor()
	var pad_area := interior.get_node_or_null("%s/SpineTrigger1" % block) as Area3D
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
	# ...and a mass that has finished travelling is RETIRED: hidden and non-solid.
	# It is as tall as its room, so a sunk one that stayed drawn and solid would be a
	# four-metre block standing in the middle of the storey below — see `_retire`.
	if mass.visible:
		_fail("%s is still drawn after sinking its full travel — it is standing in the storey below" % [
			String(door["mass"])])
	if mass_shape != null and not mass_shape.disabled:
		_fail("%s is still SOLID after sinking — it is a block in the storey below's floor plan" % [
			String(door["mass"])])

	# (d) liberation, performed by SOMEBODY ELSE
	var cell_area := interior.get_node_or_null(
		"%s/CellTrigger%s" % [block, TowerInterior.AUTHORED_CAPTIVE.capitalize()]) as Area3D
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
	var empty_area := interior.get_node_or_null(
		"%s/CellTrigger%s" % [block, other.capitalize()]) as Area3D
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
	the table, so a spawner that quietly stopped instancing fails here
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
	if live.size() != TowerInterior.guard_posts_table().size():
		_fail("the tower stood up %d guard(s) for %d authored post(s)"
			% [live.size(), TowerInterior.guard_posts_table().size()])
	if live.size() < 2:
		_fail("only %d guard(s) in the building — a tower with no population is not"
			% live.size() + " the stealth problem the epic is about")

	# ---- THE DENSITY RULE, COUNTED OFF THE BODIES ---------------------------
	# Owner ruling 2026-08-30: at most one guard per storey. Read from the tree and
	# NEVER from `guard_posts_table()` — the table is the thing under audit here,
	# and a derived reader that started emitting two posts for one plan storey (a
	# second `G` typed into a grid, a cache merging two floors) would otherwise be
	# reported as correct by a check asking the same function it is checking.
	# Storey is resolved from the body's own height against FLOOR_Y, so a guard
	# that was dropped on the wrong slab lands in the wrong bucket and shows up.
	var per_storey: Dictionary = {}
	for entry: Dictionary in live:
		var at: Vector3 = entry["position"]
		var best := -1
		var best_gap := INF
		for i in TowerInterior.FLOOR_Y.size():
			var gap: float = absf(at.y - (interior.global_position.y + TowerInterior.FLOOR_Y[i]))
			if gap < best_gap:
				best_gap = gap
				best = i
		per_storey[best] = int(per_storey.get(best, 0)) + 1
	for floor_v: Variant in per_storey:
		if int(per_storey[floor_v]) > TowerInterior.GUARDS_PER_STOREY_MAX:
			_fail("storey %d carries %d guards, over the owner's GUARDS_PER_STOREY_MAX"
					% [int(floor_v) + 1, int(per_storey[floor_v])]
					+ " of %d — two on one floor turns a room the player is meant to"
					% TowerInterior.GUARDS_PER_STOREY_MAX + " time and walk past into"
					+ " a chase")

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

	for i in TowerInterior.guard_posts_table().size():
		var authored: Dictionary = TowerInterior.guard_posts_table()[i]
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

	print("tower guards: %d on post, leashed to their own storeys; per storey %s"
			% [live.size(), str(per_storey)])
	await _clear(null, shell)


func _solid_near(world_pos: Vector3) -> String:
	## The name of the first solid box a standing body at `world_pos` would be
	## inside of, or "" when the spot is clear. Both tables — the interior's
	## furniture and the shell's outer walls — because either one buries a guard.
	## `all_boxes()` and not `boxes()`: since the posts are derived from the plans,
	## most of them stand on a PLANNED storey, whose walls the keep's own table has
	## never heard of.
	var half := Vector3(GUARD_BODY_CLEARANCE, GUARD_BODY_HEIGHT * 0.5, GUARD_BODY_CLEARANCE)
	var body_centre := Vector3(world_pos.x, world_pos.y + GUARD_BODY_HEIGHT * 0.5, world_pos.z)
	for box: Dictionary in TowerInterior.all_boxes() + TowerShell.boxes():
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
	## Every storey's boxes, for the same reason `_solid_near` reads them all: a
	## derived post's leash box hangs over a PLAN slab, which `boxes()` cannot see.
	if is_zero_approx(foot_y):
		return true
	for box: Dictionary in TowerInterior.all_boxes():
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

	for i in TowerInterior.guard_posts_table().size():
		var authored: Dictionary = TowerInterior.guard_posts_table()[i]
		var body := after.get_node_or_null("TowerGuard%s" % String(authored["name"])) as Node3D
		if body == null:
			_fail("the '%s' post is empty after re-entry" % authored["name"])
			continue
		var want: Vector3 = interior.global_position + (authored["post"] as Vector3) \
				+ Vector3(0.0, TowerInterior.GUARD_SPAWN_LIFT, 0.0)
		if body.global_position.distance_to(want) > POST_SETTLE_EPS:
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
	var authored: Dictionary = TowerInterior.guard_posts_table()[0]
	for post: Dictionary in TowerInterior.guard_posts_table():
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
	# AIM IT AT THE QUARRY. A guard's detection has been CONED since phase 17
	# (120 degrees, acquisition only), so a body left on whatever heading its
	# wander picked would acquire the probe whenever it happened to turn — which
	# makes this check's verdict a coin flip on a mechanic that is not its subject.
	# The cone itself is measured by enemy_spawn_selfcheck's cone probe; what THIS
	# check owns is the leash, and a leash is only under load while a chase is on.
	# Aiming is safe for the whole telegraph: `wander_turn_rate` is 0.5 rad/s, so
	# the body can drift 17 degrees in the 0.6 s beat against a 60 degree half-cone.
	body.rotation.y = atan2(hero.global_position.x - body.global_position.x,
			hero.global_position.z - body.global_position.z)

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
