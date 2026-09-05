extends SceneTree
## Headless self-check: THE CELL BLOCK'S LURE COMPLETES — check 21c, and nothing
## else.
##
##   godot --headless --path . --script res://scripts/tower_block_lure_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1.
##
## SPLIT OUT OF `tower_interior_selfcheck.gd` BY BEAD `godot-test1-ftn.25` — the
## ftn.13 shape: the check NUMBER and the check NAME are exactly what they were, not
## one assertion moved, and this file owns its own Sentinel set, its own
## `isolate_user_state()` and its own report site.
##
## ONE CHECK IN ONE FILE, AND THE REASON IS THE CLOCK. This errand is sixty metres
## of route walked by a real body under real physics at a patrol pace, plus the hold
## and the walk off the plate: **fifty-five seconds**, against about eight for the
## twenty-two checks left in `tower_interior_selfcheck.gd` and twenty-five for the
## six in `tower_guard_selfcheck.gd`. A CI shard cannot break a file apart, so
## while this check shared a file with the other twenty-eight it was a ninety-second
## brick the packer had to build a bin around. On its own it is the pole it actually
## is, and everything else in the tower runs in the time of a short check.
##
## `ponytail:` it stays a minute. The cost is the walk, the walk is the assertion,
## and the only ways to shorten it are to move the plate or to stop measuring the
## floor the campaign ends on. If the suite ever needs this back under thirty
## seconds the lever is `--fixed-fps` on the whole suite, not a weaker check here.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". The check below stamps
## itself at its exit; the report site asks whether the stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_boot()


func _boot() -> void:
	# THE STORE SEAM FIRST, before any shell can exist — see BestRunStore.config_path.
	TowerProbe.fresh_store()
	# ONE FRAME BEFORE ANYTHING — a node added to `root` from inside _initialize()
	# is not `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (tower_shell_selfcheck's note).
	await process_frame
	await _run()


func _run() -> void:
	await _check_the_block_floor_lure_completes()
	_report()


# ============================================================================
# CHECK 21c — THE CLIMAX FLOOR'S LURE, DRIVEN (bead godot-test1-3iy.24)
# ============================================================================
#
# Check 21 drives the FIRST storey drawing both a `G` and a `P`, which is the
# ground floor and an 11.6 m errand; 21b routes the other seventeen pairs on the
# plans, with no body in them. THE ONE ERRAND THE CAMPAIGN ACTUALLY SPENDS is
# neither: the cell block's, where you pull the sentry off the muster floor to
# reach the doorway. It is 60 m of route on the far side of the building from the
# floor 21 measures, and until bead `godot-test1-3iy.24` moved these two plates
# out of the service corridor it did not complete at all — the guard walked into
# the block's doorway, wedged on the jamb and gave up on `INVESTIGATE_STALL_TIME`,
# which every check in this file was happy with.
#
# So this is the acceptance for that move and nothing else. The lure's rules are
# check 21's and are not re-asked here; what is measured is that on THIS floor the
# errand completes — it arrives at the plate, it stands facing it, and it walks
# off again when the hold runs out.

## The pace slack on the derived budget: turns, the obstacle feelers, and the sniff
## pause the body may be standing in when the plate goes off.
const LURE_SLOW_LANE: float = 1.6


func _check_the_block_floor_lure_completes() -> void:
	"""
	Check 21c. The cell block's guard walks the length of the muster floor to a
	plate, holds on it, and walks off it again.

	THE BUDGET IS DERIVED AND THAT IS THE POINT. `LURE_WALK_BUDGET` is 18 s because
	the ground floor's nearest plate is 11.6 m from its post; the same constant here
	would be a coin toss on a walk five times as long, and a coin toss is not an
	assertion. The budget is the PLAN'S OWN route length over the BODY'S OWN worst
	sustained pace — a wander speed oscillates between `min_wander_speed_factor` and
	1.0 of the instance's rolled `move_speed`, and the slow half of that swing is
	what a budget has to survive — times `LURE_SLOW_LANE`. Move a plate, retune the
	row, and the number this check holds the guard to moves with it.
	"""
	var floor_index := TowerInterior.block_floor()
	if floor_index < 0:
		_fail("no storey draws the cell block — check 21c has no climax to drive")
		Sentinel.done("the_block_floor_lure_completes")
		return
	var post: Dictionary = TowerInterior._plan_guard_post(floor_index)
	var cells := TowerInterior.pad_cells(TowerPlans.storey(floor_index))
	if post.is_empty() or cells.is_empty():
		_fail("the cell block's storey draws %d plates and %s guard post — the floor"
				% [cells.size(), "no" if post.is_empty() else "a"]
				+ " the campaign ends on is the one floor whose lure has to work")
		Sentinel.done("the_block_floor_lure_completes")
		return

	# The plate this guard reaches soonest, measured on the ROUTE it would walk and
	# not as the crow flies — the two disagree by 20 m on this floor.
	var from: Vector3 = post["post"]
	var pad_index := -1
	var route_len := INF
	for i: int in cells.size():
		var route := TowerInterior.plan_route(floor_index, from,
				TowerInterior.pad_point(floor_index, i))
		if route.is_empty():
			continue
		var walked_plan := 0.0
		var at := from
		for point: Vector3 in route:
			walked_plan += Vector2(point.x - at.x, point.z - at.z).length()
			at = point
		if walked_plan < route_len:
			route_len = walked_plan
			pad_index = i
	if pad_index < 0:
		_fail("the plan offers this guard no way to either of the block floor's"
				+ " plates — check 21b would have said so; this drive cannot run")
		Sentinel.done("the_block_floor_lure_completes")
		return

	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no interior in the tower — check 21c has nothing to press")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_block_floor_lure_completes")
		return

	# A probe player in the tree before `reset_guards()`, because a predator resolves
	# its quarry once from group "player" in a deferred call off its own `_ready()`
	# (check 14's note). Parked in the muster floor's far north-west corner: tens of
	# metres outside the row's 9 m detection, and — the trap check 21 fell into —
	# nowhere near either plate, which a standing body would press.
	var park := Vector3(TowerInterior._grid_x(3.5), TowerInterior.FLOOR_Y[floor_index] + 0.2,
			TowerInterior._grid_z(3.5))
	if park.distance_to(from) < TowerProbe.LURE_PARK_MIN:
		_fail("the probe's corner is %.1f m from the post — it would be smelled"
				% park.distance_to(from))
	var hero: Node3D = load(TowerProbe.PLAYER_SCENE).instantiate() as Node3D
	root.add_child(hero)
	hero.global_position = interior.global_position + park
	interior.reset_guards()
	await process_frame
	for _i in 30:
		await physics_frame   # Let it land: a guard is stood up `GUARD_SPAWN_LIFT` high.

	var guard: Node3D = interior.call("_guard_on", floor_index) as Node3D
	if guard == null:
		_fail("storey %d draws a `G` but the building stood no guard on it" % floor_index)
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_block_floor_lure_completes")
		return
	var pad: Vector3 = interior.pad_world(floor_index, pad_index)
	var spec: Dictionary = guard.get("spec")
	var pace: float = float(guard.get("move_speed_instance")) \
			* float(spec["min_wander_speed_factor"])
	if pace <= 0.0:
		_fail("the guard resolved a zero patrol pace — the budget below is infinite")
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_block_floor_lure_completes")
		return
	var budget: float = route_len / pace * LURE_SLOW_LANE
	if not interior.lure_guard(floor_index, pad_index):
		_fail("the block floor's plate %d diverted nobody" % pad_index)
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_block_floor_lure_completes")
		return

	# ---- THE WALK, then the HOLD, then off the plate again --------------------
	var arrive: float = float(load(TowerProbe.CROC_SCRIPT).get_script_constant_map()["INVESTIGATE_ARRIVE"])
	var reached := 0.0
	var closest := INF
	for _i in int(budget / (1.0 / 60.0)):
		await physics_frame
		reached += 1.0 / 60.0
		closest = minf(closest, Vector2(guard.global_position.x - pad.x,
				guard.global_position.z - pad.z).length())
		if closest <= arrive:
			break
	if closest > arrive:
		_fail(("the block floor's guard got %.1f m from its plate in %.0f s, walking a"
				+ " %.1f m route at %.2f m/s — the climax's lure does not complete")
				% [closest, budget, route_len, pace])
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_block_floor_lure_completes")
		return

	# THE HOLD IS THE PAYLOAD: 120 degrees of cone pointing at a plate, on the far
	# side of the floor from the doorway you are walking to.
	var facing_off := 0.0
	var moved := 0.0
	for _i in 30:
		await physics_frame
		moved = maxf(moved, Vector2(guard.velocity.x, guard.velocity.z).length())
		facing_off = maxf(facing_off, absf(angle_difference(float(guard.rotation.y),
				atan2(pad.x - guard.global_position.x, pad.z - guard.global_position.z))))
	if moved > TowerProbe.TELEGRAPH_STILL_SPEED:
		_fail("the guard kept moving at %.2f m/s on its plate — the hold is a stand" % moved)
	if facing_off > TowerProbe.LURE_FACING_EPS:
		_fail("the guard held %.3f rad off the plate it walked to" % facing_off)

	# ...AND IT LEAVES THE PLATE ON ITS OWN FEET when the hold runs out. Measured as
	# the plate getting further away rather than as arrival at the post (check 21's
	# probe (f), for its reason): the walk home is another minute of physics, and
	# what can actually break is a sentry that stands on this plate for the rest of
	# the run — which is the same failure at a hundredth of the runtime.
	var left := false
	for _i in int((TowerInterior.LURE_HOLD_SECONDS + 6.0) / (1.0 / 60.0)):
		await physics_frame
		if Vector2(guard.global_position.x - pad.x,
				guard.global_position.z - pad.z).length() > arrive * 2.0:
			left = true
			break
	if not left:
		_fail("the guard's hold ran out on the block floor and it never walked off the"
				+ " plate — the lure parks the climax's sentry for good")
	print("tower lure: storey %d plate %d — %.1f m of route walked in %.1f s (budget %.0f s at %.2f m/s), held %.3f rad off, walked back off the plate"
		% [floor_index, pad_index, route_len, reached, budget, pace, facing_off])
	await TowerProbe.clear(self, hero, shell)
	Sentinel.done("the_block_floor_lure_completes")


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
