extends SceneTree
## Headless self-check: THE HQ'S CIVILIAN STAFF — plan-derived loops, two
## MultiMeshes, no collider, and bodies that actually walk them.
##
##   godot --headless --path . --script res://scripts/tower_staff_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1.
##
## Bead `godot-test1-buyt.3`. `tower_guard_selfcheck.gd` is the shape — the other
## population in this building, checked from the same angles — and `TowerProbe` is
## the shared rig.
##
## WHAT IT GUARDS, and why each is worth a check:
##
##  1. **THE LOOPS ARE WALKABLE, AND CONTINUOUS.** A loop is derived from ASCII
##     nobody wrote it for, so the failure mode is a staffer strolling through a
##     wall — and it is invisible from anywhere but inside that corridor. Every
##     consecutive waypoint pair on every loop, INCLUDING THE WRAP FROM LAST TO
##     FIRST, must be exactly one four-connected cell apart and must not cross a
##     cell the router refuses. That is the direct test: it compares the BUILT PATH
##     against the PLAN, not against the function that produced it, so a leg that
##     was straight-lined because `plan_route` came back empty fails here however
##     healthy the arithmetic around it looked. Three negative controls run with
##     it, because a walkability test that cannot fail is worse than none.
##  2. **THE DERIVATION IS DETERMINISTIC.** The tower is one of the project's two
##     authored exceptions: nothing in its plan is seeded or hashed, and two peers
##     in one room must watch the same staff walk the same corridors. Asserted
##     three ways — the table rebuilt from a CLEARED cache is byte-identical, it is
##     still byte-identical after the global RNG has been re-seeded and drawn from
##     between the builds, and the source carries no `randf`, no `hash(` and no
##     `run_seed`.
##  3. **NO COLLIDER, NO GROUP, ANYWHERE UNDER `Staff`.** The load-bearing one. A
##     staff body with any collider is a movable wall in a 1.94 m corridor that
##     `tower_selfcheck`'s flood fill cannot see — read `tower_staff.gd`'s header.
##     Asserted by WALKING THE SUBTREE, never by reading the source: a collider
##     added by a scene, by a tween or by a future archetype is caught the same way
##     one typed into this file would be.
##  4. **TWO DRAWS, ONE MATERIAL.** Two `MultiMeshInstance3D`, shadows off, sharing
##     ONE `Material` by identity — across two separately built interiors, which is
##     the only form of the assertion a per-build `duplicate()` cannot pass.
##  5. **THE BODIES MOVE, AND THEY MOVE ALONG THE PATH.** Driven for two seconds of
##     simulated time. Every staffer's drawn position must change, must stay inside
##     `TowerInterior.inside_walls()`, must sit ON its own loop's polyline, and must
##     not have travelled further than `WALK_SPEED` allows. Read out of the
##     MultiMesh BUFFER — the thing the engine is handed — and not out of the
##     records that decided it.
##  6. **THE POPULATION RESETS** on the shell's own `player_entered`, exactly as the
##     guards do, and the opened set does not.
##
## The draw budget the two MultiMeshes moved (38 -> 40) is asserted where it lives,
## by `tower_interior_selfcheck`'s check 5.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## Floating-point slack on geometry that is supposed to be EXACTLY on a cell
## centre. The grid is 1.94 m, so this is four orders of magnitude under the
## smallest thing that could be wrong.
const EPS: float = 1e-3

## How long check 5 walks the staff for, in simulated seconds, and the frame it
## chops that into. Two seconds at 1.1 m/s is 2.2 m — more than one plan cell, so
## a staffer that moved must have crossed a waypoint, and short enough that a
## corner cannot turn the displacement back to nothing.
const WALK_SECONDS: float = 2.0
const WALK_STEP: float = 1.0 / 60.0

## How far off its mark a re-entered staffer may be found, in metres.
##
## NOT `EPS`, AND THE REASON IS THE SAME ONE `tower_guard_selfcheck`'s
## `POST_SETTLE_EPS` is written around. Check 6 reads the population one PROCESS
## FRAME after the doorway signal, and the building's own `_process` walks the
## staff on that frame by whatever delta the frame took — unbounded on a loaded CI
## runner. The question the check asks is "was the population RESET to its marks,
## not left where it stood?", and it first walks them SIX SECONDS (6.6 m at
## `WALK_SPEED`, asserted) away, so a quarter of a metre separates the two answers
## by more than an order of magnitude while admitting every stray frame the runner
## sneaks in.
const RESET_SETTLE_EPS: float = 0.25

## The tokens check 2 refuses to find in `tower_staff.gd`. `budapest_selfcheck`'s
## list, and `hash(` catches the CALL rather than the word for its reason.
const BANNED_TOKENS: Array[String] = ["run_seed", "randf", "randi", "hash("]

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_boot()


func _boot() -> void:
	TowerProbe.fresh_store()
	# ONE FRAME BEFORE ANYTHING — a node added to `root` from inside `_initialize()`
	# is not `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (tower_shell_selfcheck's note).
	await process_frame
	await _run()


func _run() -> void:
	_check_the_loops_are_walkable()
	_check_the_derivation_is_deterministic()
	await _check_no_collider_and_no_group()
	await _check_two_draws_one_material()
	await _check_the_bodies_walk_their_loops()
	await _check_the_population_resets_on_re_entry()
	_report()


# ============================================================================
# CHECK 1 — the loops are walkable, and continuous
# ============================================================================

func _check_the_loops_are_walkable() -> void:
	"""
	Check 1. Every waypoint of every loop stands on a cell a body may cross, and
	every step between two of them is one four-connected cell.

	WHY THE ADJACENCY TEST IS THE WHOLE CHECK. `TowerStaff` builds a lap by routing
	consecutive room centres and CONCATENATING the results, and `plan_route`
	returns every cell centre of the way — so on a correct build the path is a
	chain of single cell steps and nothing else. The one way a staffer can walk
	through a wall is a leg that was not routed: a pair the plan cannot connect,
	joined by a straight line anyway. That leg is a jump of many cells, and this is
	what sees it. The WRAP from the last waypoint back to the first is tested with
	the rest, because a lap that is open is a lap with one teleport in it.

	AND THREE NEGATIVE CONTROLS, because every assertion above is of the form "no
	waypoint was bad", which is true of an empty list and of a test that cannot
	discriminate:

	  * the router refuses a destination inside the shell's wall (21b's control);
	  * `_cell_step` reports a straight-lined path — the same loop's first waypoint
	    joined directly to its midpoint — as MANY cells, not one;
	  * a `#` found between two open cells on a real plan row reads as refused;
	  * and, on that same pair, the ROUTER's asymmetry — it walks out of a wall
	    cell and never into one — which is the measured fact `_storey_stops()`'s
	    filter exists for and the only thing that makes `_storey_loop()`'s ~2n
	    group peel correct.

	It also fails outright on a building with no loops at all, which is what a
	derivation that silently stopped reading the plans would leave behind.
	"""
	var table := TowerStaff.loops()
	if table.size() < 2:
		_fail("the plans derive %d staff loop(s) — a building nobody walks, and"
				% table.size() + " every assertion in this check would be vacuous")
		Sentinel.done("the_loops_are_walkable")
		return
	var waypoints := 0
	for loop: Dictionary in table:
		var floor_index: int = loop["floor"]
		var path: PackedVector3Array = loop["path"]
		var rows: Array = TowerPlans.storey(floor_index)["rows"]
		waypoints += path.size()
		if path.size() < 2:
			_fail("storey %d's loop has %d waypoint(s) — that is not a lap"
				% [floor_index, path.size()])
			continue
		for i: int in path.size():
			var here: Vector3 = path[i]
			# ...AND THE WRAP WITH THEM: `(i + 1) % size` is the closing leg.
			var next: Vector3 = path[(i + 1) % path.size()]
			var cell := TowerInterior._plan_cell_of(here)
			var ch := TowerInterior._plan_char(rows, cell)
			if not TowerInterior._route_open(ch):
				_fail("storey %d waypoint %d stands at %s, on cell %s = '%s', which"
					% [floor_index, i, str(here), str(cell), ch]
					+ " the router itself refuses to cross")
			if not is_equal_approx(here.y, TowerInterior.FLOOR_Y[floor_index]):
				_fail("storey %d waypoint %d is at y %.3f, not on its slab at %.3f"
					% [floor_index, i, here.y, TowerInterior.FLOOR_Y[floor_index]])
			var step := _cell_step(here, next)
			if step != 1:
				_fail("storey %d steps %d cells from waypoint %d %s to %s — a leg"
					% [floor_index, step, i, str(cell),
						str(TowerInterior._plan_cell_of(next))]
					+ " that long was straight-lined, not routed, so a staffer"
					+ " walks through whatever is between them")
	# --- Negative control A: the router is reading the plan at all (21b's).
	var walled := Vector3(TowerPlans.PLAN_HALF + 1.0, 0.0, 0.0)
	if not TowerInterior.plan_route(0, Vector3.ZERO, walled).is_empty():
		_fail("the router found a way into the shell's wall — it is not reading"
				+ " the plan, and every loop above is worth nothing")
	# --- Negative control B: `_cell_step` can say "no".
	var probe: PackedVector3Array = table[0]["path"]
	var straight := _cell_step(probe[0], probe[probe.size() / 2])
	if straight <= 1:
		_fail("a straight line across storey %d's whole loop measures %d cell(s) —"
			% [int(table[0]["floor"]), straight]
			+ " the adjacency test cannot tell a routed leg from a jump")
	# --- Negative control C: a leg that spans a wall is seen as one.
	var wall := _find_wall_between_open_cells()
	if wall.x < 0:
		_fail("no `.#.` run exists on any shipped plan — controls C and D below"
				+ " have nothing to measure and prove nothing")
	elif TowerInterior._route_open(TowerInterior._plan_char(
			TowerPlans.storey(wall.z)["rows"], Vector2i(wall.x, wall.y))):
		_fail("a leg deliberately drawn across a '#' on a shipped plan read as"
				+ " clear — the walkability test above proves nothing")
	else:
		# --- Control D: THE ROUTER IS ASYMMETRIC, WHICH IS WHY STOPS ARE FILTERED.
		# `plan_route` seeds its BFS with the START cell without asking whether that
		# cell is open, so it routes OUT of a wall and never INTO one. `TowerStaff`
		# leans on reachability being an EQUIVALENCE relation to find each storey's
		# largest group in ~2n routes instead of n², and the only thing that makes
		# that true is `_storey_stops()` dropping any stop that is not itself
		# route-open. Measured here rather than asserted in prose: the day the router
		# refuses a closed start cell, this control fails and that filter can go.
		var rows: Array = TowerPlans.storey(wall.z)["rows"]
		var solid := _cell_centre(wall.z, Vector2i(wall.x, wall.y))
		var open_side := _cell_centre(wall.z, Vector2i(wall.x - 1, wall.y))
		if TowerInterior.plan_route(wall.z, solid, open_side).is_empty():
			_fail("the router would not leave the wall cell %s on storey %d — the"
				% [str(Vector2i(wall.x, wall.y)), wall.z]
				+ " asymmetry TowerStaff._storey_stops() filters against is gone,"
				+ " and that filter is now unexplained code")
		if not TowerInterior.plan_route(wall.z, open_side, solid).is_empty():
			_fail("the router walked INTO the wall cell %s on storey %d, which"
				% [str(Vector2i(wall.x, wall.y)), wall.z]
				+ " contradicts control C on the same two cells")
	print("tower staff: %d loops, %d waypoints, %s" % [table.size(), waypoints,
		str(_loop_summary(table))])
	Sentinel.done("the_loops_are_walkable")


func _cell_step(from: Vector3, to: Vector3) -> int:
	"""Manhattan distance in plan cells between two interior-local points. One is
	a four-connected step; zero is a repeat; anything else is a jump."""
	var a := TowerInterior._plan_cell_of(from)
	var b := TowerInterior._plan_cell_of(to)
	return absi(a.x - b.x) + absi(a.y - b.y)


func _find_wall_between_open_cells() -> Vector3i:
	"""
	A real `.#.` run on a shipped plan: `(column, row, floor)`, or `x = -1`.

	FOUND ON THE PLANS RATHER THAN FABRICATED, so controls C and D are made of the
	same characters the check above reads and cannot drift away from them.
	"""
	for floor_index: int in TowerPlans.floors():
		var rows: Array = TowerPlans.storey(floor_index)["rows"]
		for r: int in rows.size():
			var line := String(rows[r])
			for c: int in range(1, line.length() - 1):
				if line[c] != TowerPlans.WALL_CHAR:
					continue
				if TowerInterior._route_open(line[c - 1]) \
						and TowerInterior._route_open(line[c + 1]):
					return Vector3i(c, r, floor_index)
	return Vector3i(-1, -1, -1)


func _cell_centre(floor_index: int, cell: Vector2i) -> Vector3:
	"""One plan cell's centre in interior-local metres, on its own slab."""
	return Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
			TowerInterior.FLOOR_Y[floor_index],
			TowerInterior._grid_z(float(cell.y) + 0.5))


func _loop_summary(table: Array) -> Array:
	"""One printable row per loop: storey, stops kept, lap length."""
	var out: Array = []
	for loop: Dictionary in table:
		out.append("f%d:%s:%.0fm" % [int(loop["floor"]),
			"".join(loop["stops"] as Array), float(loop["length"])])
	return out


# ============================================================================
# CHECK 2 — the derivation is deterministic
# ============================================================================

func _check_the_derivation_is_deterministic() -> void:
	"""
	Check 2. The same plans give the same loops, twice, and after the global RNG
	has moved underneath them.

	THE CACHE IS THE TRAP THIS CHECK IS WRITTEN AROUND. `TowerStaff.loops()` memoizes
	into a `static var`, so "build it twice and compare" against the LIVE function
	compares an object with itself and passes whatever the derivation does. The
	cache is therefore CLEARED between the two builds, and the comparison is over
	the float arrays rather than over the dictionaries' identity.

	AND THE RNG IS MOVED BETWEEN THEM, which is the part a grep cannot do. Godot's
	global `randf()` stream is re-seeded and drawn from between build two and build
	three; a derivation that reached for an RNG anywhere — directly, or three calls
	down inside a helper this file does not name — comes back with different stops.
	`set_run_seed()` is deliberately NOT what is moved here: it is `EndlessTerrain`'s
	setter and the tower's plans are a `const` that no seed is ever handed to, so
	standing a terrain up would prove less than this does at far greater cost. What
	it would add — that the file never names the seed at all — the grep below makes
	directly.
	"""
	var first := _loops_snapshot()
	TowerStaff._loops_cache = []
	var second := _loops_snapshot()
	if first != second:
		_fail("rebuilding the staff loops from a cleared cache gave a different"
				+ " table — the derivation is not a pure function of the plans")
	seed(0x5EED_BEEF)
	for _i in 32:
		randf()
	TowerStaff._loops_cache = []
	var third := _loops_snapshot()
	seed(1)
	for _i in 7:
		randi()
	TowerStaff._loops_cache = []
	var fourth := _loops_snapshot()
	if third != first or fourth != first:
		_fail("re-seeding the global RNG between two builds changed the staff"
				+ " loops — something in the derivation is drawing from it")
	# ...and the source itself — `budapest_selfcheck`'s check 1, scanner and control
	# and all. EVERY LINE, COMMENTS INCLUDED, which is that check's rule and not an
	# oversight: a scanner that had to tell a docstring from a statement is a
	# scanner with a hiding place in it, so the PROSE in `tower_staff.gd` may not
	# spell these tokens either, and its header says so.
	var source := FileAccess.get_file_as_string("res://scripts/tower_staff.gd")
	if source.is_empty():
		_fail("scripts/tower_staff.gd is unreadable — the scan below would pass on"
				+ " an empty string and prove nothing")
	var hits := _scan_banned(source)
	if not hits.is_empty():
		_fail("tower_staff.gd contains %s — the tower is an AUTHORED exception and"
			% ", ".join(hits) + " nothing in its plan may be seeded, hashed or drawn")
	# THE NEGATIVE CONTROL, verbatim from `budapest_selfcheck`: a scanner with a
	# typo in its token list passes a clean file perfectly, so it is shown a string
	# that must trip it.
	var control := _scan_banned("var x := hash(Vector3i(1, 2, run_seed))\n")
	if control.size() < 2:
		_fail("check 2's scanner did not flag a line containing BOTH of the two"
				+ " worst tokens (found %d) — the scan above proved nothing"
				% control.size())
	print("tower staff: the loop table is byte-identical over 4 builds and 2 RNG"
			+ " re-seeds; %d lines scanned for %s, %d hits (control: %d)"
			% [source.split("\n").size(), ", ".join(BANNED_TOKENS), hits.size(),
				control.size()])
	Sentinel.done("the_derivation_is_deterministic")


func _scan_banned(text: String) -> Array[String]:
	"""Every (token, line) the banned list appears at, as printable strings."""
	var out: Array[String] = []
	var lines := text.split("\n")
	for i in range(lines.size()):
		for token: String in BANNED_TOKENS:
			if lines[i].contains(token):
				out.append("%s on line %d" % [token, i + 1])
	return out


func _loops_snapshot() -> Array:
	"""The whole loop table flattened to comparable values — floors, stops kept and
	every waypoint. `Dictionary` equality is by reference in GDScript, so the
	comparison has to be made of the numbers themselves."""
	var out: Array = []
	for loop: Dictionary in TowerStaff.loops():
		var row: Array = [int(loop["floor"]), str(loop["stops"]),
			"%.6f" % float(loop["length"])]
		for point: Vector3 in (loop["path"] as PackedVector3Array):
			row.append("%.6f,%.6f,%.6f" % [point.x, point.y, point.z])
		out.append(row)
	return out


# ============================================================================
# CHECK 3 — no collider, no group
# ============================================================================

func _check_no_collider_and_no_group() -> void:
	"""
	Check 3. Nothing under `Staff` is a `CollisionObject3D` and nothing under it is
	in any group.

	THE LOAD-BEARING INVARIANT OF THIS WHOLE FEATURE, and it is worth stating why
	once more where it is measured rather than only where it is decided:
	`tower_selfcheck` is a grid flood fill over corridors ONE OR TWO CELLS wide
	(`PLAN_CELL` = 1.94 m). The player's `collision_mask` is 5, which MASKS layer 3
	— the layer `ambience_proxies.gd` puts the crowd's pool bodies on. So any
	collider that walks these corridors is a movable wall the softlock audit cannot
	see, and the only safe amount is none.

	THE GROUP HALF IS THE SAME SIZE OF MISTAKE IN A DIFFERENT DIRECTION. A node in
	"crocodile" is swept by `crocodile_lod_manager`, scattered by the Stink Wave,
	read by `hunt_director` and synced by `mp_croc_sync`; one in "player" is
	followed by the camera and chased. None of that is true of a filing clerk.

	WALKED, NOT GREPPED. A source grep would pass a collider that arrived from a
	scene, from a `duplicate()` or from the next archetype somebody welds. The
	subtree is what ships.
	"""
	var interior := await TowerProbe.make_interior(self)
	var staff := interior.get_node_or_null("Staff")
	if staff == null:
		_fail("the interior built no `Staff` node — check 3 would pass on nothing")
		interior.queue_free()
		await process_frame
		Sentinel.done("no_collider_and_no_group")
		return
	var seen := 0
	for node: Node in _subtree(staff):
		seen += 1
		if node is CollisionObject3D:
			_fail("`%s` under Staff is a %s — a staff body with ANY collider is a"
				% [node.name, node.get_class()] + " movable wall in a 1.94 m"
				+ " corridor that tower_selfcheck's flood fill cannot see")
		if node is Area3D or node is CollisionShape3D:
			_fail("`%s` under Staff is a %s — staff have no volume of any kind"
				% [node.name, node.get_class()])
		var groups := node.get_groups()
		if not groups.is_empty():
			_fail("`%s` under Staff is in group(s) %s — staff join none, or the LOD"
				% [node.name, str(groups)] + " manager, the Stink Wave and the hunt"
				+ " director all take hold of the office furniture")
	if seen < 2:
		_fail("the Staff subtree holds %d node(s) — expected the two archetype"
			% seen + " MultiMeshes, so this check measured an empty branch")
	# THE COUNT, OFF THE BUILT POPULATION AND NEVER OFF THE TABLE — check 12's rule
	# in `tower_guard_selfcheck`. A builder that silently stopped writing instances
	# would otherwise be reported as a full population by the arithmetic that was
	# meant to be standing it up.
	var built := TowerStaff.walkers(interior)
	var per_storey: Dictionary = {}
	for walker: Dictionary in built:
		var floor_index: int = walker["floor"]
		per_storey[floor_index] = int(per_storey.get(floor_index, 0)) + 1
	for floor_index: int in per_storey:
		if int(per_storey[floor_index]) > TowerStaff.STAFF_PER_STOREY:
			_fail("storey %d carries %d staff, over STAFF_PER_STOREY of %d — this"
				% [floor_index, int(per_storey[floor_index]),
					TowerStaff.STAFF_PER_STOREY]
				+ " building is a stealth problem, not a chase")
	var want: int = TowerStaff.loops().size() * TowerStaff.STAFF_PER_STOREY
	if built.size() != want:
		_fail("the building drew %d staff where %d loops x %d per storey is %d"
			% [built.size(), TowerStaff.loops().size(),
				TowerStaff.STAFF_PER_STOREY, want])
	print("tower staff: %d bodies over %d storeys, %d nodes under Staff, no"
		% [built.size(), per_storey.size(), seen] + " collider and no group")
	interior.queue_free()
	await process_frame
	Sentinel.done("no_collider_and_no_group")


func _subtree(node: Node) -> Array[Node]:
	"""Every descendant of `node`, `node` itself included."""
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_subtree(child))
	return out


# ============================================================================
# CHECK 4 — two draws, one material
# ============================================================================

func _check_two_draws_one_material() -> void:
	"""
	Check 4. Exactly two `MultiMeshInstance3D`, shadows off, sharing ONE `Material`.

	TWO INTERIORS, AND THAT IS THE POINT. One interior would pass a build that
	calls `CityAgents.gradient_material()` once PER BUILD and hands the same fresh
	object to both of its archetypes — which is a material per tower, and the exact
	thing `crowd_manager`'s "never `duplicate()` per instance" invariant forbids.
	Compared by IDENTITY (`!=` on the object), not by equality of shader or
	parameters, because two materials with the same numbers are still two draws.

	The budget those two nodes cost (`DRAW_BUDGET` 38 -> 40, surfaces 49 -> 51) is
	asserted in `tower_interior_selfcheck`'s check 5, where the constant lives.
	"""
	var a := await TowerProbe.make_interior(self)
	var b := await TowerProbe.make_interior(self)
	var racks_a := _staff_racks(a)
	var racks_b := _staff_racks(b)
	if racks_a.size() != TowerStaff.ARCHETYPE_COUNT:
		_fail("the interior built %d staff MultiMeshInstance3D, expected %d — one"
			% [racks_a.size(), TowerStaff.ARCHETYPE_COUNT] + " per archetype, and"
			+ " that count IS the declared draw cost")
		a.queue_free()
		b.queue_free()
		await process_frame
		Sentinel.done("two_draws_one_material")
		return
	var shared: Material = racks_a[0].material_override
	if shared == null:
		_fail("the staff MultiMeshes carry no material_override at all")
	for rack: MultiMeshInstance3D in racks_a + racks_b:
		if rack.material_override != shared:
			_fail("`%s` wears its own material instance — ONE material for both"
				% rack.name + " archetypes and every tower, or it is not one draw"
				+ " apiece")
		if rack.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("`%s` casts shadows — the fauna/crowd precedent and this whole"
				% rack.name + " building switch them off")
		if rack.multimesh == null or rack.multimesh.mesh == null:
			_fail("`%s` has no mesh to draw" % rack.name)
			continue
		if rack.multimesh.transform_format != MultiMesh.TRANSFORM_3D:
			_fail("`%s` is not a 3D-transform MultiMesh" % rack.name)
		var surfaces: int = rack.multimesh.mesh.get_surface_count()
		if surfaces != 1:
			_fail("`%s`'s welded body submits %d surfaces, not 1 — a MultiMesh"
				% [rack.name, surfaces] + " draws once PER SURFACE, so the two-draw"
				+ " claim is only true of a single-surface weld")
	# The two archetypes must be two different bodies, or "scientists and engineers"
	# is one population wearing one coat.
	if racks_a.size() == 2 and racks_a[0].multimesh != null \
			and racks_a[1].multimesh != null \
			and racks_a[0].multimesh.mesh == racks_a[1].multimesh.mesh:
		_fail("both staff archetypes draw the SAME mesh — the owner asked for"
				+ " white coats and blue overalls, and that is one of them")
	print("tower staff: %d racks x 2 interiors share one %s, shadows off"
		% [racks_a.size(), shared.get_class() if shared != null else "<null>"])
	a.queue_free()
	b.queue_free()
	await process_frame
	Sentinel.done("two_draws_one_material")


func _staff_racks(interior: Node) -> Array[MultiMeshInstance3D]:
	"""The `MultiMeshInstance3D`s under the interior's `Staff` node, in order."""
	var out: Array[MultiMeshInstance3D] = []
	var staff := interior.get_node_or_null("Staff")
	if staff == null:
		return out
	for child: Node in staff.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
	return out


# ============================================================================
# CHECK 5 — the bodies move, and they move along the path
# ============================================================================

func _check_the_bodies_walk_their_loops() -> void:
	"""
	Check 5. Two seconds of ticking moves every staffer, along its own loop, no
	faster than it walks, and never out of the building.

	FOUR ASSERTIONS AND FOUR DIFFERENT HALF-IMPLEMENTATIONS:

	  * IT MOVED. A population that is standing still is the one failure the owner
	    would see from the door, and a tick that computed everything and forgot to
	    push the buffer looks exactly like it.
	  * IT IS ON ITS PATH. The drawn position is measured against the loop's own
	    POLYLINE — the thing the plan produced — and not against the pose function
	    that placed it. That is the assertion this file exists for: a body that is
	    drawn a plan cell off, or on the right floor's loop but the wrong floor's
	    slab, cannot be reported healthy by the arithmetic that put it there.
	  * IT DID NOT TELEPORT. Displacement is a CHORD, so it can never exceed the
	    arc — `WALK_SPEED * WALK_SECONDS` is therefore a hard ceiling, and a tick
	    that advanced by frames instead of seconds, or that spent a coarse-tick bank
	    twice, breaks it.
	  * IT IS INDOORS. `inside_walls()` is what the building answers "are you in a
	    room" with, and a loop derived off the end of a grid would put a staffer in
	    the shell's masonry.

	READ OUT OF THE MULTIMESH BUFFER through `TowerStaff.walkers()`, never out of
	the walker records: the buffer is what the engine is handed, and under
	`--headless` it is also the only one of the two that round-trips
	(`TowerDossiers.refresh()`'s measurement).
	"""
	var interior := await TowerProbe.make_interior(self)
	var before := TowerStaff.walkers(interior)
	if before.is_empty():
		_fail("no staff are drawn in a freshly built interior — check 5 has nothing"
				+ " to walk")
		interior.queue_free()
		await process_frame
		Sentinel.done("the_bodies_walk_their_loops")
		return
	var steps := int(WALK_SECONDS / WALK_STEP)
	for _i in steps:
		TowerStaff.tick(interior, WALK_STEP)
	var after := TowerStaff.walkers(interior)
	if after.size() != before.size():
		_fail("walking for %.1f s changed the population from %d to %d"
			% [WALK_SECONDS, before.size(), after.size()])
	var ceiling: float = TowerStaff.WALK_SPEED * float(steps) * WALK_STEP + EPS
	var loops_by_floor: Dictionary = {}
	for loop: Dictionary in TowerStaff.loops():
		loops_by_floor[int(loop["floor"])] = loop
	var worst := 0.0
	var shortest := INF
	for i: int in mini(before.size(), after.size()):
		var from: Vector3 = before[i]["position"]
		var to: Vector3 = after[i]["position"]
		var floor_index: int = after[i]["floor"]
		var moved := from.distance_to(to)
		shortest = minf(shortest, moved)
		if moved <= EPS:
			_fail("the staffer on storey %d has not moved in %.1f s — it is drawn"
				% [floor_index, WALK_SECONDS] + " standing at %s" % str(to))
		if moved > ceiling:
			_fail("the staffer on storey %d covered %.3f m in %.1f s, over the"
				% [floor_index, moved, WALK_SECONDS]
				+ " %.3f m WALK_SPEED allows — that is a teleport, not a walk"
				% ceiling)
		if not TowerInterior.inside_walls(to):
			_fail("the staffer on storey %d walked to %s, which is not inside the"
				% [floor_index, str(to)] + " building's walls")
		if not loops_by_floor.has(floor_index):
			_fail("a staffer reports storey %d, which derives no loop" % floor_index)
			continue
		var off := _distance_to_path(loops_by_floor[floor_index]["path"], to)
		worst = maxf(worst, off)
		if off > TowerPlans.PLAN_CELL * 0.5:
			_fail("the staffer on storey %d is drawn %.3f m off its own loop at %s"
				% [floor_index, off, str(to)]
				+ " — it is not walking the path the plan derived")
		var slab: float = TowerInterior.FLOOR_Y[floor_index]
		if to.y < slab - EPS or to.y > slab + TowerStaff.WALK_BOB_AMOUNT + EPS:
			_fail("the staffer on storey %d is drawn at y %.3f, off its slab at"
				% [floor_index, to.y] + " %.3f (the bob is %.3f)"
				% [slab, TowerStaff.WALK_BOB_AMOUNT])
	# THE CONTROL FOR `_distance_to_path`: it must be able to report a body that is
	# NOT on its loop. Without this the "off by less than half a cell" assertion is
	# indistinguishable from a function that answers zero for everything.
	var probe: PackedVector3Array = TowerStaff.loops()[0]["path"]
	var adrift := _distance_to_path(probe, probe[0] + Vector3(0.0, 0.0, 12.0))
	if adrift < 1.0:
		_fail("a point 12 m off a loop measures %.3f m from it — the on-the-path"
			% adrift + " test cannot tell where a staffer is")
	print("tower staff: %d bodies walked %.1f s, shortest move %.2f m, worst"
		% [after.size(), WALK_SECONDS, shortest]
		+ " distance off path %.4f m" % worst)
	interior.queue_free()
	await process_frame
	Sentinel.done("the_bodies_walk_their_loops")


func _distance_to_path(path: PackedVector3Array, at: Vector3) -> float:
	"""
	How far `at` is from the nearest point of the CLOSED polyline `path`, on the
	horizontal plane.

	Horizontal because the drawn origin carries the walk BOB in y, which is a
	deliberate few centimetres off the slab; the slab itself is asserted separately.
	"""
	var flat := Vector3(at.x, 0.0, at.z)
	var best := INF
	for i: int in path.size():
		var a: Vector3 = path[i]
		var b: Vector3 = path[(i + 1) % path.size()]
		var nearest := Geometry3D.get_closest_point_to_segment(flat,
				Vector3(a.x, 0.0, a.z), Vector3(b.x, 0.0, b.z))
		best = minf(best, flat.distance_to(nearest))
	return best


# ============================================================================
# CHECK 6 — the population resets on re-entry
# ============================================================================

func _check_the_population_resets_on_re_entry() -> void:
	"""
	Check 6. Crossing the doorway stands the staff back at the start of their loops
	and leaves the opened gates alone.

	"STRUCTURE PERSISTS; POPULATION RESETS" IS ONE SENTENCE WITH TWO HALVES, and
	this is the staff's half of `tower_guard_selfcheck`'s check 13. It is driven
	through the SHELL'S OWN `player_entered` signal rather than by calling
	`TowerStaff.reset()`, because THE WIRING IS THE PART THAT CAN BE MISSING: an
	interior that never connects resets nothing in the real game and everything in
	a check that calls the function itself.

	The staff are walked well away from their marks first, so a handler that fired
	and did nothing cannot pass by leaving them where they already were.
	"""
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no TowerInterior under the shell — check 6 has nothing to measure")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_population_resets_on_re_entry")
		return
	shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
	var opened_before: Array = shell.call("opened_ids")

	var staff_before := interior.get_node_or_null("Staff")
	var marks := TowerStaff.walkers(interior)
	if marks.is_empty():
		_fail("the tower stood up no staff at all — check 6 would pass on an empty"
				+ " building")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_population_resets_on_re_entry")
		return
	# Walk them a long way off their marks — six seconds is over five metres, which
	# no settle, bob or rounding can account for.
	for _i in int(6.0 / WALK_STEP):
		TowerStaff.tick(interior, WALK_STEP)
	var wandered := TowerStaff.walkers(interior)
	var drift := 0.0
	for i: int in mini(marks.size(), wandered.size()):
		drift = maxf(drift, (marks[i]["position"] as Vector3).distance_to(
				wandered[i]["position"]))
	if drift < 1.0:
		_fail("six seconds of walking moved the staff at most %.3f m — check 6"
			% drift + " cannot tell a reset from doing nothing")

	# THE REAL TRIGGER: the shell's own emission, not the private handler.
	shell.emit_signal("player_entered", null)
	await process_frame

	var staff_after := interior.get_node_or_null("Staff")
	if staff_after == null or staff_after == staff_before:
		_fail("the doorway crossing did not rebuild the Staff container — either"
				+ " nothing is connected to player_entered, or the reset reuses it")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_population_resets_on_re_entry")
		return
	var after := TowerStaff.walkers(interior)
	if after.size() != marks.size():
		_fail("re-entry left %d staff where there were %d"
			% [after.size(), marks.size()])
	for i: int in mini(marks.size(), after.size()):
		var want: Vector3 = marks[i]["position"]
		var got: Vector3 = after[i]["position"]
		if got.distance_to(want) > RESET_SETTLE_EPS:
			_fail("the storey %d staffer came back at %s, not on its mark %s"
				% [int(after[i]["floor"]), str(got), str(want)])
		if int(after[i]["archetype"]) != int(marks[i]["archetype"]):
			_fail("the storey %d staffer came back in the other archetype's coat"
				% int(after[i]["floor"]))
	var opened_after: Array = shell.call("opened_ids")
	if opened_after != opened_before:
		_fail("re-entry changed the opened set from %s to %s — structure persists,"
				% [str(opened_before), str(opened_after)] + " only the population resets")
	print("tower staff: re-entry put %d bodies back on their marks (they had"
		% after.size() + " drifted %.2f m), opened set %s untouched"
		% [drift, str(opened_after)])
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("the_population_resets_on_re_entry")


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
