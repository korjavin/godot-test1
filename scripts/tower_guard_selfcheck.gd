extends SceneTree
## Headless self-check: THE HQ'S GUARDS STAND, RESET, STAY LEASHED AND ANSWER THE
## LURE PLATES.
##
##   godot --headless --path . --script res://scripts/tower_guard_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1.
##
## SPLIT OUT OF `tower_interior_selfcheck.gd` BY BEAD `godot-test1-ftn.25` — the
## ftn.13 shape (enemy_spawn / budapest precedent): the check NUMBERS and the check
## NAMES are exactly what they were, not one assertion moved, and this file owns its
## own Sentinel set, its own `isolate_user_state()` and its own report site. The
## split is by RUNTIME, not by taste: the interior's other twenty-two checks add up
## to about eight seconds and these five are eighty, because every one of them is a
## real body walking a real floor under real physics. A CI shard cannot break a file
## apart, so a file the size of the old one is a brick the packer has to build a bin
## around.
##
## WHAT IT GUARDS, and why each is worth a check:
##
##  12. **THE GUARDS ARE STANDING, ON THE RIGHT POSTS, IN THE RIGHT ROWS.** Where a
##      guard stands is a `G` in an ASCII plan, so a plan edit moves a body — and a
##      post that lands inside a wall, or two on one storey (`GUARDS_PER_STOREY_MAX`
##      is an owner ruling, not a preference), looks like nothing at all until you
##      are in the room. Counted off the BODIES in the tree, never off the table.
##      Check 12 also asserts the capsule fits every doorway it is expected to walk
##      through, because a sentry wedged on a jamb patrols nothing.
##  13. **THE POPULATION RESETS, AND NOTHING ELSE DOES.** The owner's rule is
##      "structure persists; population resets" — so re-entering the building stands
##      the guards back on their posts and leaves every earned gate open. Check 13
##      drives the shell's own `player_entered` signal and asserts both halves.
##  14. **THE LEASH HOLDS, UNDER A REAL CHASE.** A guard that has seen you and is
##      running at you must still never leave its storey. This is the one claim in
##      the building that cannot be made structurally: `set_confinement()` is a
##      per-frame clamp, and the only honest question is what a body does over eight
##      seconds of full-speed pursuit against it.
##  21. **THE LURE.** A `P` plate pulls the storey's guard off its post at patrol
##      pace, holds it facing the plate, and gives it back. Check 21 drives the first
##      storey drawing both a `G` and a `P`; check 21b then routes the other
##      seventeen (post, plate) pairs on the plans with no body in them, because
##      exactly one of the eighteen has a clear straight line and a lure that steered
##      by bearing would walk seventeen guards into a wall.
##
## The cell block's own errand — check 21c, sixty metres of route on the climax
## floor — is `tower_block_lure_selfcheck.gd`: one check, one minute, its own file
## for exactly that reason.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

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

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
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
	await _check_guards_stand_their_posts()
	_check_guard_capsule_fits_the_doors()
	await _check_guards_reset_on_re_entry()
	await _check_the_leash_holds_under_a_chase()
	await _check_the_lure_diverts_a_guard()
	_report()


# ============================================================================
# CHECK 12 — the guards are standing, on the right posts, in the right rows
# ============================================================================

## How much room a guard's body needs around its post before "clear of the
## stonework" means anything: nothing solid may come within this of a post, at
## any height a standing body occupies, so a post that merely GRAZES a jamb is
## a failure rather than a lucky pass. Derived from the LIVE capsule (see
## `guard_body_clearance`), never hand-copied — the next chassis growth scales
## the threshold instead of silently shrinking its headroom.
const GUARD_CLEARANCE_FACTOR: float = 1.0667  # == 0.45 at the 2.25x radius

static var _guard_capsule_radius: float = -1.0


static func guard_body_clearance() -> float:
	"""Room a guard's body needs around its post, from the live capsule.

	The `tower_guard.tscn` capsule radius times GUARD_CLEARANCE_FACTOR (which
	reproduces the old hand-copied 0.45 at the 2.25x radius, so the threshold
	is unchanged today). Falls back to 0.45 when the scene is unreadable —
	everything downstream fails loudly in that case anyway.
	"""
	if _guard_capsule_radius < 0.0:
		_guard_capsule_radius = 0.45 / GUARD_CLEARANCE_FACTOR
		var scene := TowerInterior.guard_scene()
		if scene != null:
			var probe := scene.instantiate() as Node3D
			var shape_node := probe.find_child("CollisionShape3D", true, false) as CollisionShape3D
			var capsule := (shape_node.shape if shape_node != null else null) as CapsuleShape3D
			if capsule != null:
				_guard_capsule_radius = capsule.radius
			probe.free()
	return _guard_capsule_radius * GUARD_CLEARANCE_FACTOR

## How tall a standing guard is, for the same test. The chassis stands 2.25 m
## (the capsule lies on the travel axis, so it is the MODEL's height that this
## has to cover, not the capsule's 3.0375 m length); a little over it, so a post
## under the crawl lintel (top at 2.8 m, underside 2.0) or under a raised mass
## would be caught.
const GUARD_BODY_HEIGHT: float = 2.4

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
	    row: a 15 m detection radius indoors, a crocodile's gait, a 120° view cone
	    it never had, its own `coin_setback` instead of the guard's, and — the one
	    that undoes the ruling outright — no `sweep_exempt` and no immunities, so
	    the respawn sweep would clear the floor and a Stink Wave would empty the
	    building. Asserted on the resolved `spec`, not on the `species` string,
	    because the string is right in both worlds — only `spec` knows which row
	    `_ready()` actually read.
	  * A LEASH THAT WAS NEVER APPLIED. `is_confined` false means a guard walks out
	    of the building, or off the upper slab and down into the courtyard.
	  * A LEASH BOX BIGGER THAN ITS STOREY. The upper guard's box must stay over the
	    slab and WEST of the secure partition — that second half is what makes the
	    checkpoint beyond the secure door a safe haven by construction, which the
	    setback path in `player_controller` relies on and cannot check for itself.

	The count is taken from the BODIES IN THE TREE (`guard_posts()`), never from
	the table, so a spawner that quietly stopped instancing fails here
	instead of being reported as three guards by a check reading the same table it
	is meant to be auditing.
	"""
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no TowerInterior under the shell — check 12 has nothing to measure")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("guards_stand_their_posts")
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
	# ...AND THE OTHER HALF, ON THE PLANS THEMSELVES. The body count above cannot
	# see a storey that drew TWO `G` cells: `_plan_guard_post` takes the first and
	# stops, so an invalid plan stands up exactly one guard and reads as correct
	# here. Counting the markers is what makes the ruling a property of the DESIGN
	# RECORD — the grid is what an author edits — and not merely of the reader.
	for floor_index: int in TowerPlans.floors():
		var plan: Dictionary = TowerPlans.storey(floor_index)
		var marks := 0
		for row_v: Variant in plan["rows"]:
			marks += String(row_v).count(TowerPlans.POST_CHAR)
		if marks > TowerInterior.GUARDS_PER_STOREY_MAX:
			_fail("storey %d's plan draws %d '%s' posts, over GUARDS_PER_STOREY_MAX"
					% [floor_index + 1, marks, TowerPlans.POST_CHAR]
					+ " of %d — the derived reader takes the first and silently"
					% TowerInterior.GUARDS_PER_STOREY_MAX + " drops the rest, so the"
					+ " body count above would report this floor as correct")

	for floor_v: Variant in per_storey:
		if int(per_storey[floor_v]) > TowerInterior.GUARDS_PER_STOREY_MAX:
			_fail("storey %d carries %d guards, over the owner's GUARDS_PER_STOREY_MAX"
					% [int(floor_v) + 1, int(per_storey[floor_v])]
					+ " of %d — two on one floor turns a room the player is meant to"
					% TowerInterior.GUARDS_PER_STOREY_MAX + " time and walk past into"
					+ " a chase")

	var guard_row: Dictionary = load(TowerProbe.CROC_SCRIPT).get_script_constant_map() \
			.get("SPECIES", {}).get(TowerInterior.GUARD_SPECIES, {})
	if guard_row.is_empty():
		_fail("SPECIES has no '%s' row — every guard would fall back to a crocodile"
			% TowerInterior.GUARD_SPECIES)

	var guards := interior.get_node_or_null("Guards")
	if guards == null:
		_fail("the interior has no Guards container — nothing was ever stood up")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("guards_stand_their_posts")
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
		var blocker := _solid_near(post, float(authored["yaw"]))
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
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("guards_stand_their_posts")


func _solid_near(world_pos: Vector3, yaw: float) -> String:
	## The name of the first solid box a standing body at `world_pos`, facing `yaw`,
	## would be inside of, or "" when the spot is clear. Both tables — the interior's
	## furniture and the shell's outer walls — because either one buries a guard.
	## `all_boxes()` is every storey's plan boxes and the hand-built parts among
	## them — since bd godot-test1-dn8 there is no second table, so the walls a post
	## could be buried in are all in there.
	##
	## A DISC WAS NOT ENOUGH ONCE THE CHASSIS GREW (bead `godot-test1-6bj`). The
	## capsule is 2.025 m long and a plan cell is 1.94 m, so the body reaches into
	## the NEIGHBOURING cells along its facing, and a symmetric
	## `GUARD_BODY_CLEARANCE` box measured only the 0.28125 m radius — it passed a
	## post standing broadside inside a corridor wall. The footprint is therefore
	## measured off `tower_guard.tscn`'s own shape, turned to the spawn yaw, and
	## then widened to at least the old clearance on both axes so the margin that
	## test bought is still bought.
	var span := _guard_footprint(yaw)
	var half := Vector3(span.size.x * 0.5, GUARD_BODY_HEIGHT * 0.5, span.size.y * 0.5)
	var body_centre := Vector3(world_pos.x + span.position.x + half.x,
			world_pos.y + GUARD_BODY_HEIGHT * 0.5,
			world_pos.z + span.position.y + half.z)
	for box: Dictionary in TowerInterior.all_boxes() + TowerShell.boxes():
		if not box["collide"]:
			continue
		# The ramp is the one tilted box in either table and an AABB test over it is
		# a lie in both directions; it is also 5 m from the nearest post. Skipped by
		# name rather than silently mistested.
		if String(box["name"]) == "Ramp":
			continue
		if TowerProbe.overlaps(body_centre, half * 2.0, box["pos"], box["size"]):
			return String(box["name"])
	return ""


func _guard_footprint(yaw: float) -> Rect2:
	## The ground footprint a guard standing at the origin facing `yaw` occupies, as
	## a Rect2 in (x, z) RELATIVE TO THE POST — asymmetric, because the capsule is
	## offset back along the body (the chassis is built forward of its origin).
	##
	## READ OFF `tower_guard.tscn`, never restated here: the capsule's own transform
	## and dimensions are the thing under test, so a scene whose shape stopped
	## matching its model must not be measured against a copy of the number it used
	## to carry. Degrades to the plain derived-clearance disc if the scene is
	## ever reshaped into something this cannot read.
	var clearance := guard_body_clearance()
	var lo := Vector2(-clearance, -clearance)
	var hi := Vector2(clearance, clearance)
	var scene := TowerInterior.guard_scene()
	if scene != null:
		var probe := scene.instantiate()
		var shape_node := probe.find_child("CollisionShape3D", true, false) as CollisionShape3D
		var capsule := (shape_node.shape if shape_node != null else null) as CapsuleShape3D
		if capsule != null:
			# The two HEMISPHERE CENTRES in body space, turned to the spawn yaw, then
			# inflated by the radius: that is the capsule's exact ground AABB.
			# `CapsuleShape3D.height` is tip to tip, caps included, so the centres are
			# a radius short of each end — take `height * 0.5` for the reach and the
			# inflation below counts both caps twice, quietly lengthening the body by
			# a whole diameter and failing posts that are fine.
			var turn := Basis(Vector3.UP, yaw)
			var axis: Vector3 = turn * (shape_node.transform.basis.y.normalized())
			var mid: Vector3 = turn * shape_node.position
			var reach: Vector3 = axis * maxf(capsule.height * 0.5 - capsule.radius, 0.0)
			var r: float = capsule.radius
			for x: float in [mid.x - reach.x, mid.x + reach.x]:
				lo.x = minf(lo.x, x - r)
				hi.x = maxf(hi.x, x + r)
			for z: float in [mid.z - reach.z, mid.z + reach.z]:
				lo.y = minf(lo.y, z - r)
				hi.y = maxf(hi.y, z + r)
		probe.free()
	return Rect2(lo, hi - lo)


func _check_guard_capsule_fits_the_doors() -> void:
	"""
	Check 12b. The real guard capsule fits a spine door, clears every storey,
	and does NOT fit the crawl alcove.

	The capsule AND the model height are read off a live `tower_guard.tscn`
	instance — the `_guard_footprint` discipline — because the whole claim is
	about the body this bead grew, and a copy of 0.84 here would keep passing
	after a retune broke the scene. Three assertions:

	  * DOORWAY: the capsule's diameter clears one PLAN_CELL (a spine door is
	    one cell wide). The capsule lies on the travel axis, so length along
	    travel never gates a doorway — width does.
	  * STOREYS: the model's height clears every planned storey's air.
	  * CRAWL: the capsule's vertical extent passes under DOSSIER_CRAWL_CLEAR
	    (pinned, so outgrowing it fails) — and the alcove stays guard-free by
	    ROUTING, not by height: it is a dead end (check 20) and no post,
	    patrol lane or lure plate is inside it. The old mesh-height clause
	    stated something false of the physics body, which is the capsule.
	"""
	var scene := TowerInterior.guard_scene()
	if scene == null:
		_fail("check 12b: tower_guard.tscn is missing — the fit cannot be measured")
		Sentinel.done("guard_capsule_fits_the_doors")
		return
	var probe := scene.instantiate() as Node3D
	var shape_node := probe.find_child("CollisionShape3D", true, false) as CollisionShape3D
	var capsule := (shape_node.shape if shape_node != null else null) as CapsuleShape3D
	if capsule == null:
		_fail("check 12b: tower_guard.tscn has no readable capsule — the fit cannot be measured")
		probe.free()
		Sentinel.done("guard_capsule_fits_the_doors")
		return
	var diameter := capsule.radius * 2.0
	var door := TowerPlans.PLAN_CELL
	if diameter >= door:
		_fail("check 12b: the guard's %.2f m capsule does not fit a %.2f m spine door" % [diameter, door])
	# Measured from the probe ROOT, not the Model node: a retune of the model's
	# in-game size is a transform on Model itself, and measuring under it would
	# bless that away (the F1 mutation: Model scaled 2.5x must fail the storey
	# clause, not print 2.25 m).
	var tall := _visual_height(probe)
	if tall <= 0.0:
		_fail("check 12b: tower_guard.tscn draws no mesh — the height cannot be measured")
		probe.free()
		Sentinel.done("guard_capsule_fits_the_doors")
		return
	var capsule_hi := capsule.radius * 2.0
	if capsule_hi >= TowerDossiers.DOSSIER_CRAWL_CLEAR:
		_fail("check 12b: the guard's %.2f m capsule no longer fits under the crawl lintel (%.2f m)" % [
			capsule_hi, TowerDossiers.DOSSIER_CRAWL_CLEAR])
	var low := INF
	for floor_index: int in TowerPlans.floors():
		low = minf(low, TowerInterior.plan_clear_height(floor_index))
	if tall >= low:
		_fail("check 12b: the %.2f m guard does not clear a %.2f m storey" % [tall, low])
	print("guard capsule: %.2f m wide through %.2f m doors, %.2f m tall under %.2f m ceilings, %.2f m capsule passes under the %.2f m crawl (alcove guard-free by routing, check 20), clearance %.4f" % [
		diameter, door, tall, low, capsule_hi, TowerDossiers.DOSSIER_CRAWL_CLEAR,
		guard_body_clearance()])
	probe.free()
	Sentinel.done("guard_capsule_fits_the_doors")


func _visual_height(body: Node3D) -> float:
	## Top of the highest drawn mesh under `body`, in body space — the number a
	## lintel or a ceiling actually meets. Walks every MeshInstance3D (the hunter
	## exports welded, but the mesh count is the exporter's business, not this
	## check's), composing each node's LOCAL transform down from `body`, so
	## nesting never silently drops a part and the probe never needs the tree —
	## `get_global_transform()` on an unparented probe logs an inside-tree
	## condition and answers identity, which would bless any nested transform
	## away. 0 when nothing is drawn at all.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var stack: Array = [[body, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n := item[0] as Node3D
		var xf: Transform3D = item[1]
		if n == null:
			continue
		for c in n.get_children():
			var cn := c as Node3D
			if cn != null:
				stack.append([cn, xf * cn.transform])
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := xf * mi.get_aabb()
		lo.x = minf(lo.x, box.position.x)
		lo.y = minf(lo.y, box.position.y)
		lo.z = minf(lo.z, box.position.z)
		hi.x = maxf(hi.x, box.end.x)
		hi.y = maxf(hi.y, box.end.y)
		hi.z = maxf(hi.z, box.end.z)
	if lo.x >= INF:
		return 0.0
	return hi.y - lo.y


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
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no TowerInterior under the shell — check 13 has nothing to measure")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("guards_reset_on_re_entry")
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
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("guards_reset_on_re_entry")
		return

	# THE REAL TRIGGER. `_on_door_body_entered` filters to group "player", so this
	# is the shell's own emission — the signal, not the private handler.
	shell.emit_signal("player_entered", null)
	await process_frame

	var after := interior.get_node_or_null("Guards")
	if after == null or after == guards:
		_fail("the doorway crossing did not rebuild the Guards container — either"
				+ " nothing is connected to player_entered, or the reset reuses it")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("guards_reset_on_re_entry")
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
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("guards_reset_on_re_entry")


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
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var guards: Node = interior.get_node_or_null("Guards") if interior != null else null
	if guards == null:
		_fail("no guards in the building — check 14 has nothing to chase with")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_leash_holds_under_a_chase")
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
	var hero: Node3D = load(TowerProbe.PLAYER_SCENE).instantiate() as Node3D
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
	await TowerProbe.settle_physics(self)

	# UNDO WHATEVER THE BUILDING LANDED WHILE WE WERE STAGING, and then keep it from
	# landing anything else — the same landmine `capture_selfcheck._make_player`
	# documents, which bit here the day the coin bill became universal (bead
	# godot-test1-0bc). The probe stands inside the guard's own reach, so a
	# hit is not a slow-machine race but a certainty, and since that bead EVERY hit
	# taken inside the HQ ends at `setback_point()`: the quarry vanishes to the
	# doorway plate nine floors down, the guard has nothing to smell, and check 14
	# reports a leash it never put under load. (Before the bead the same hit spent a
	# heart and respawned in place, which is why this staging survived so long.)
	#
	# Held with the shipped BLINK i-frames rather than by re-planting the body:
	# blinking does not freeze movement, so the guard is still chasing a live
	# `CharacterBody3D`, and it goes through `hit_by_crocodile()`'s one early return
	# instead of inventing a second way to be invulnerable.
	hero.is_caught = false
	hero.caught_timer = 0.0
	hero.caught_setback = 0.0
	hero.is_respawning = false
	hero.respawn_timer = 0.0
	hero.global_position = Vector3(centre.x, floor_y + 0.2, centre.z + half.y + LEASH_PROBE_GAP)

	var ticks := int(LEASH_PROBE_SECONDS / (1.0 / 60.0))
	var chased := false
	var worst := 0.0
	## The fastest the body moved on any frame of its telegraph — see the beat
	## assertion in the loop below.
	var telegraph_speed := 0.0
	for _i in ticks:
		# HOLD IT LOOKING AT THE QUARRY UNTIL IT ACQUIRES. A guard's detection has
		# been CONED since phase 17 (120 degrees, on the acquisition edge only,
		# after a 0.6 s telegraph it has to hold the arc for), so a body left on
		# whatever heading its wander picked acquires the probe if and when it
		# happens to turn — which makes this check's verdict a coin flip on a
		# mechanic that is not its subject. The cone itself is measured by
		# enemy_spawn_selfcheck's check 8e; what THIS check owns is the leash, and
		# a leash is only under load while a chase is on. Dropped the moment the
		# chase starts, so every frame that is actually being measured is the
		# shipped body steering itself.
		if not chased:
			body.rotation.y = atan2(hero.global_position.x - body.global_position.x,
					hero.global_position.z - body.global_position.z)
		# Topped up every frame — see the block above the loop. The window is 2.5 s
		# and the probe runs 8, so one write at the start would wear off halfway.
		hero.respawn_blink_timer = hero.RESPAWN_BLINK_DURATION
		await physics_frame
		# THE BEAT IS A STANDSTILL, measured under real physics because that is the
		# only place it exists: `_update_chase_state` decides the beat, but what
		# freezes the body is the heading override in `_physics_process`. A guard
		# that kept walking through its own warning would turn as it went, roll the
		# quarry back out of its 120 degree cone and reset the clock — a sentry that
		# notices you forever and never engages, which passes every other assertion
		# in this file.
		if not chased and float(body.get("spot_clock")) > 0.0:
			telegraph_speed = maxf(telegraph_speed,
					Vector2(body.velocity.x, body.velocity.z).length())
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
	if telegraph_speed > TowerProbe.TELEGRAPH_STILL_SPEED:
		_fail("the '%s' guard walked at %.2f m/s during its telegraph — the beat is"
				% [authored["name"], telegraph_speed] + " meant to be a standstill,"
				+ " and a body that moves through its own warning turns as it goes,"
				+ " rolls the quarry out of its own cone and resets the clock")
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
	await TowerProbe.clear(self, hero, shell)
	Sentinel.done("the_leash_holds_under_a_chase")


# ============================================================================
# CHECK 21 — THE LURE (bead godot-test1-3iy.22)
# ============================================================================
#
# The `P` plates divert the storey's guard: it walks over at its patrol pace,
# stands facing the plate, and walks back. THE WHOLE THING IS DRIVEN ON A REAL
# BODY UNDER REAL PHYSICS, on the storey the plans actually draw it on, because
# every interesting claim here is about interaction between three systems that
# each pass their own checks — the AI's flag state, the interior's trigger, and
# the leash. A lure that set every flag correctly and never moved a metre, or one
# that moved and never came home, is what this exists to catch.

## How long the guard is given to walk to its plate before the check gives up.
## The nearest authored pad is about 10 m from its post and a guard patrols at
## ~1.2 m/s, so an honest walk lands inside 10 s; the rest is slack for the sniff
## pause it may be standing in when the plate goes off.
const LURE_WALK_BUDGET: float = 18.0

## How far the probe player stands from the guard when it is the guard's turn to
## spot it. Inside the row's 9 m detection, outside its reach — a bite would take
## the body through the setback path mid-probe (check 14's landmine, verbatim).
const LURE_SPOT_GAP: float = 2.5




func _check_the_lure_diverts_a_guard() -> void:
	"""
	Check 21. A plate goes off; the storey's guard walks to it, looks at it, and
	nothing about the lure can be used to puppet it.

	  (a) the walk REACHES the plate and never leaves the confinement box it is
	      being run under — the box is grown to contain the plate and the steer and
	      the hard clamp keep running the whole way, which is the difference
	      between a bigger leash and no leash;
	  (b) detection is untouched: the probe walks into the guard's cone and is
	      acquired through the ordinary telegraph, and that acquisition cancels the
	      errand — the guard does not resume walking to the plate afterwards;
	  (c) `investigate_point()` refuses a body that is chasing, biting or already
	      on an errand;
	  (d) the plate refuses a re-press until its hold and cooldown have run;
	  (e) a SLEPT guard still walks: the lure wakes it and `set_lod_active(false)`
	      refuses to put it back down mid-errand. Without this the far plate on a
	      78 m storey lures a body that runs no `_physics_process` at all.
	"""
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no interior in the tower — check 21 has nothing to press")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return

	# WHICH STOREY IS A QUESTION FOR THE PLANS, never a number written here: the
	# first floor that draws both a `G` and a `P`, and the plate NEAREST that post,
	# which is also the one a player would actually use.
	var floor_index := -1
	var pad_index := -1
	var pad_gap := INF
	for candidate: int in TowerPlans.floors():
		var post: Dictionary = TowerInterior._plan_guard_post(candidate)
		if post.is_empty():
			continue
		var cells := TowerInterior.pad_cells(TowerPlans.storey(candidate))
		for i: int in cells.size():
			var gap: float = (TowerInterior.pad_point(candidate, i)
					- (post["post"] as Vector3)).length()
			if floor_index >= 0 and candidate != floor_index:
				continue
			if gap < pad_gap:
				floor_index = candidate
				pad_index = i
				pad_gap = gap
	if floor_index < 0:
		_fail("no planned storey carries both a guard post and a lure plate —"
				+ " check 21 would pass vacuously")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return

	# The probe player, parked on the SAME storey but far outside the guard's 9 m
	# detection — in the tree before `reset_guards()`, because a predator resolves
	# its quarry once from group "player" in a deferred call off its own `_ready()`
	# (check 14's note). Standing on real floor, so it is grounded and therefore
	# smellable when its turn comes; a body in the air is unsmellable forever.
	#
	# ON THE STAIR LANDING, and this file learned that the way you would hope: it
	# was parked on the storey's OTHER plate first, which pressed it — the guard
	# was already on an errand before the check had asked for one. An `s` cell is
	# flush floor and is never a `P`.
	var landing := TowerInterior.landing_rect(floor_index)
	if landing.size == Vector2i.ZERO:
		_fail("storey %d draws no landing to park the probe on" % floor_index)
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return
	var park := Vector3(TowerInterior._grid_x(landing.position.x + landing.size.x * 0.5),
			TowerInterior.FLOOR_Y[floor_index] + 0.2,
			TowerInterior._grid_z(landing.position.y + landing.size.y * 0.5))
	var post_at: Vector3 = TowerInterior._plan_guard_post(floor_index)["post"]
	if park.distance_to(post_at) < TowerProbe.LURE_PARK_MIN:
		_fail("the probe's parking spot is %.1f m from the guard's post — it would"
				% park.distance_to(post_at) + " be smelled before the lure was pressed")
	var hero: Node3D = load(TowerProbe.PLAYER_SCENE).instantiate() as Node3D
	root.add_child(hero)
	hero.global_position = interior.global_position + park
	interior.reset_guards()
	await process_frame
	# LET IT LAND, and half a second rather than `_settle_physics()`'s four frames:
	# a guard is stood up `GUARD_SPAWN_LIFT` over its post and `set_lod_active()`
	# refuses to sleep a body that has not landed — so probe (e) would be measuring
	# that older refusal instead of its own.
	for _i in 30:
		await physics_frame

	var guard: Node3D = interior.call("_guard_on", floor_index) as Node3D
	if guard == null:
		_fail("storey %d draws a `G` but the building stood no guard on it" % floor_index)
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return
	var authored_centre: Vector3 = guard.get("confine_center")
	var authored_half: Vector2 = guard.get("confine_half")
	var pad: Vector3 = interior.pad_world(floor_index, pad_index)
	if not pad.is_finite():
		_fail("pad %d of storey %d has no world position" % [pad_index, floor_index])
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return

	# ---- (e) THE SLEEP, FIRST: press the plate on a body that is asleep --------
	guard.set_lod_active(false)
	if bool(guard.get("lod_active")):
		_fail("the guard refused to sleep before the lure — check 21(e) would"
				+ " have measured nothing")
	if not interior.lure_guard(floor_index, pad_index):
		_fail("the plate on storey %d did not divert the guard" % floor_index)
		await TowerProbe.clear(self, hero, shell)
		Sentinel.done("the_lure_diverts_a_guard")
		return
	if not bool(guard.get("lod_active")):
		_fail("the lure left the guard asleep — a slept body runs no"
				+ " _physics_process, so it neither walks to the plate nor reaches"
				+ " any other peer's screen (mp_manager skips sleepers)")
	guard.set_lod_active(false)
	if not bool(guard.get("lod_active")):
		_fail("the guard was slept mid-errand — set_lod_active must refuse while"
				+ " is_investigating, exactly as it refuses a body that has not landed")

	# ---- (c) the busy refusal, while that errand is live ----------------------
	if guard.call("investigate_point", pad, 5.0):
		_fail("a second lure was accepted mid-errand — a diversion that queues is"
				+ " a puppet string")

	# ---- (a) THE WALK ---------------------------------------------------------
	# The box is grown, frame by frame, to reach whichever waypoint the guard is
	# walking at — so the excursion is measured against the box AS IT STANDS THAT
	# FRAME, which is the only honest reading of "the clamp kept running".
	var arrive: float = float(load(TowerProbe.CROC_SCRIPT).get_script_constant_map()["INVESTIGATE_ARRIVE"])
	var ticks := int(LURE_WALK_BUDGET / (1.0 / 60.0))
	var arrived := false
	var worst := 0.0
	var walked := 0.0
	var shrank := false
	var start := guard.global_position
	for _i in ticks:
		await physics_frame
		var box: Vector2 = guard.get("confine_half")
		var centre: Vector3 = guard.get("confine_center")
		shrank = shrank or box.x < authored_half.x - EPS or box.y < authored_half.y - EPS
		var off := guard.global_position - centre
		worst = maxf(worst, maxf(absf(off.x) - box.x, absf(off.z) - box.y))
		walked = maxf(walked, (guard.global_position - start).length())
		if Vector2(guard.global_position.x - pad.x,
				guard.global_position.z - pad.z).length() <= arrive:
			arrived = true
			break
	if shrank:
		_fail("the lure SHRANK the guard's leash below its authored extents %s"
				% authored_half)
	var grown: Vector2 = guard.get("confine_half")
	var pad_off := Vector2(pad.x - authored_centre.x, pad.z - authored_centre.z)
	if arrived and (absf(pad_off.x) > grown.x or absf(pad_off.y) > grown.y):
		_fail("the leash never grew to contain the plate the guard walked to — the"
				+ " clamp would have stopped it short and the errand never ends")
	if not arrived:
		_fail("the guard never reached its plate %.1f m away in %.0f s (it moved"
				% [pad_gap, LURE_WALK_BUDGET] + " %.1f m) — the lure is a flag" % walked
				+ " nothing acts on, or the leash is holding it back")
	if worst > EPS:
		_fail("the lured guard reached %.3f m outside the box it was being run"
				% worst + " under — the confinement is not enforced during an errand")

	# ---- the HOLD: standing still, looking at the plate ------------------------
	var facing_off := 0.0
	var moved := 0.0
	for _i in 30:
		await physics_frame
		moved = maxf(moved, Vector2(guard.velocity.x, guard.velocity.z).length())
		facing_off = maxf(facing_off, absf(angle_difference(float(guard.rotation.y),
				atan2(pad.x - guard.global_position.x, pad.z - guard.global_position.z))))
	if arrived and moved > TowerProbe.TELEGRAPH_STILL_SPEED:
		_fail("the guard kept moving at %.2f m/s while holding on its plate — the"
				% moved + " hold is what turns the cone away, so it has to be a stand")
	if arrived and facing_off > TowerProbe.LURE_FACING_EPS:
		_fail("the guard held %.3f rad off the plate it walked to — the point of"
				% facing_off + " the diversion is where the 120-degree cone ends up")

	# ---- (b) DETECTION IS UNCHANGED, AND IT CANCELS THE ERRAND ----------------
	# The probe steps into the guard's cone. Nothing about the lure may make it
	# harder or easier to be seen: the acquisition runs the shipped telegraph.
	hero.global_position = guard.global_position + Vector3(0.0, 0.2, LURE_SPOT_GAP)
	var chased := false
	for _i in 300:
		if not chased:
			guard.rotation.y = atan2(hero.global_position.x - guard.global_position.x,
					hero.global_position.z - guard.global_position.z)
		hero.respawn_blink_timer = hero.RESPAWN_BLINK_DURATION
		await physics_frame
		if bool(guard.get("is_chasing")):
			chased = true
			break
	if not chased:
		_fail("an investigating guard never acquired a probe %.1f m inside its own"
				% LURE_SPOT_GAP + " cone — the lure changed detection, which it may not")
	if guard.call("investigate_point", pad, 5.0):
		_fail("a chasing guard took a lure — the diversion may never pull a body"
				+ " off the player it has already committed to")
	var target: Vector3 = guard.get("investigate_target")
	if Vector2(target.x - pad.x, target.z - pad.z).length() < 1.0:
		_fail("the guard is still aimed at its plate after acquiring the player —"
				+ " an errand that survives an acquisition is resumed the moment you"
				+ " break line of sight")
	# ...AND THE GROWTH IS HANDED BACK ON THE SPOT. The errand opened the storey
	# up; the chase that interrupted it must be fought over a beat-sized patch, or
	# a lure is a way to buy a guard that pursues you across the whole floor.
	var chase_box: Vector2 = guard.get("confine_half")
	if absf(chase_box.x - authored_half.x) > EPS or absf(chase_box.y - authored_half.y) > EPS:
		_fail("the guard kept its grown leash %s into the chase (authored %s) —"
				% [chase_box, authored_half] + " an acquisition has to take the"
				+ " growth back, or the lure sells a floor-wide pursuit")

	# ---- IT WALKS HOME, and the leash comes back where it moves nothing --------
	# The probe leaves, the chase drops, and the guard finishes the errand the only
	# way it is allowed to: on its own feet, back down the route it came. Driven
	# rather than teleported, because "restoring the authored box teleports nobody"
	# is only true if the body is standing at the post when it happens.
	hero.global_position = interior.global_position + park
	var home := false
	for _i in ticks:
		await physics_frame
		if not bool(guard.get("is_investigating")):
			home = true
			break
	if not home:
		_fail("the guard never finished its errand and went back on post within"
				+ " %.0f s" % LURE_WALK_BUDGET)
	var post_off := guard.global_position - authored_centre
	if absf(post_off.x) > authored_half.x + EPS or absf(post_off.z) > authored_half.y + EPS:
		_fail("the guard ended its errand %s outside its authored box — the"
				% str(Vector2(post_off.x, post_off.z)) + " restore teleports it back"
				+ " on the next frame, which is a guard that blinks across the floor")
	var back: Vector2 = guard.get("confine_half")
	if absf(back.x - authored_half.x) > EPS or absf(back.y - authored_half.y) > EPS:
		_fail("the guard kept its grown leash after the errand (%s, authored %s) —"
				% [back, authored_half] + " a lure that permanently widens a patrol"
				+ " box is a lure that deletes the beat it was diverting")

	# ---- (f) A HOLD THAT SIMPLY RUNS OUT ends the same way ---------------------
	# The probe above cancelled its errand by being SEEN, which is the interesting
	# path and not the common one. An expiring hold reaches the turn-around
	# through a different door (`_investigate_go_home` rather than
	# `_abandon_investigation`, which refuses a body whose hold is already spent) —
	# and when that door was missing, a guard stood on its plate for the rest of
	# the run with every assertion above still green.
	var beside := guard.global_position + Vector3(0.5, 0.0, 0.0)
	if not guard.call("investigate_point", beside, 0.3):
		_fail("an idle guard back on its post refused a lure")
	var expired := false
	var turned := false
	for _i in 240:
		await physics_frame
		# THE TURN IS THE ASSERTION, not the ending. A body whose expiry never
		# reached the turn-around ALSO stops investigating — one frame later, by
		# handing its leash back where it stands, which on a real errand is a plate
		# tens of metres from the post and a hard clamp that teleports it there.
		# So what is measured is that it aimed at its POST before it finished.
		var aim: Vector3 = guard.get("investigate_target")
		turned = turned or Vector2(aim.x - authored_centre.x,
				aim.z - authored_centre.z).length() < EPS
		if not bool(guard.get("is_investigating")):
			expired = true
			break
	if not expired:
		_fail("the guard never came off a hold that ran out — an expiring hold has"
				+ " to turn the errand round, or the plate parks a sentry for good")
	if not turned:
		_fail("the guard finished a spent hold without ever aiming at its post —"
				+ " it ended the errand where it stood, so on a real plate the hard"
				+ " clamp would have teleported it home")

	# ---- (c) the other two refusals, on an idle body --------------------------
	guard.set("is_biting", true)
	if guard.call("investigate_point", pad, 5.0):
		_fail("a biting guard took a lure")
	guard.set("is_biting", false)

	# ---- (d) THE PLATE'S OWN COOLDOWN ----------------------------------------
	# Driven through the press, not through `lure_guard()`: the cooldown is the
	# half of the anti-puppet rule that lives on the pad, and it is what stops two
	# players alternating a pair to walk a guard wherever they like.
	interior.call("_press_lure_pad", floor_index, pad_index)
	if not bool(guard.get("is_investigating")):
		_fail("stepping on the plate diverted nobody")
	guard.call("_end_investigation")
	interior.call("_press_lure_pad", floor_index, pad_index)
	if bool(guard.get("is_investigating")):
		_fail("the plate re-armed the moment the errand ended — the cooldown has to"
				+ " outlast the walk, or the pair is a joystick")
	interior.call("_tick_lure_pads",
			TowerInterior.LURE_HOLD_SECONDS + TowerInterior.LURE_COOLDOWN)
	interior.call("_press_lure_pad", floor_index, pad_index)
	if not bool(guard.get("is_investigating")):
		_fail("the plate never re-armed — a one-shot lure is a decoration")

	print("tower lure: storey %d plate %d — walked %.1f m to it, worst excursion %.4f m, held %.3f rad off, cancelled on acquisition, walked home, re-armed on its cooldown"
		% [floor_index, pad_index, walked, worst, facing_off])
	await TowerProbe.clear(self, hero, shell)
	_check_every_plate_has_a_way_to_it()
	Sentinel.done("the_lure_diverts_a_guard")


func _check_every_plate_has_a_way_to_it() -> void:
	"""
	Check 21b — THE ROUTER, on the plans, with no physics in the way.

	The walk above is one plate on one storey; this is the other seventeen. It
	exists because the first cut of this bead steered by BEARING, and exactly ONE
	of the building's (post, plate) pairs has a clear straight line — the very one
	a "nearest plate" probe picks. Fifteen guards would have walked into a wall
	while every assertion above stayed green.

	WHAT IS ASSERTED, per storey that draws a `G`:
	  * at least one of its plates is reachable — a storey where neither is means
	    a guard nobody can call;
	  * every route returned is WALKABLE: consecutive corners are axis-aligned and
	    every cell between them is open on the plan. A router that returned the
	    straight line, or cut a corner through stone, fails here;
	  * and the negative control: a destination inside the shell's wall has no
	    route at all, or "reachable" would be true of anything.
	"""
	var pairs := 0
	var routed := 0
	var corners := 0
	for floor_index: int in TowerPlans.floors():
		var post: Dictionary = TowerInterior._plan_guard_post(floor_index)
		if post.is_empty():
			continue
		var from: Vector3 = post["post"]
		var here := 0
		var cells := TowerInterior.pad_cells(TowerPlans.storey(floor_index))
		for i: int in cells.size():
			pairs += 1
			var to := TowerInterior.pad_point(floor_index, i)
			var route := TowerInterior.plan_route(floor_index, from, to)
			if route.is_empty():
				continue
			here += 1
			routed += 1
			corners += route.size()
			var walk := from
			for point: Vector3 in route:
				var bad := _route_leg_blocked(floor_index, walk, point)
				if bad != "":
					_fail("storey %d plate %d: the route's leg %s -> %s %s"
							% [floor_index, i, str(walk), str(point), bad])
				walk = point
			if not walk.is_equal_approx(to):
				_fail("storey %d plate %d: the route ends at %s, not at the plate"
						% [floor_index, i, str(walk)])
		if here == 0:
			_fail("storey %d stands a guard and draws %d plates, and the plan"
					% [floor_index, cells.size()] + " offers a way to none of them")
	# The negative control: the middle of the outer wall is on no floor plan.
	var walled := Vector3(TowerPlans.PLAN_HALF + 1.0, 0.0, 0.0)
	if not TowerInterior.plan_route(0, Vector3.ZERO, walled).is_empty():
		_fail("the router found a way into the shell's wall — it is not reading"
				+ " the plan, and every route above is worth nothing")
	print("tower lure: %d of %d (post, plate) pairs routed, %d corners in total"
		% [routed, pairs, corners])
	Sentinel.done("every_plate_has_a_way_to_it")


func _route_leg_blocked(floor_index: int, from: Vector3, to: Vector3) -> String:
	"""One leg of a route: "" when it is a clear axis-aligned walk, else why not."""
	var plan := TowerPlans.storey(floor_index)
	var rows: Array = plan["rows"]
	var a := TowerInterior._plan_cell_of(from)
	var b := TowerInterior._plan_cell_of(to)
	if a.x != b.x and a.y != b.y:
		return "turns a corner mid-leg (%s -> %s cells)" % [str(a), str(b)]
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var at := a
	while at != b:
		at += step
		var ch := String(rows[at.y])[at.x]
		if not TowerInterior._route_open(ch):
			return "crosses '%s' at cell %s" % [ch, str(at)]
	return ""


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
