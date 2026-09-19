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
##     it, because a walkability test that cannot fail is worse than none. Every
##     STOP is also checked against the cell bbox a separate scan of the ASCII says
##     its room occupies — the assertion that catches an axis swap, which puts a
##     body in the wrong room while every build-versus-build comparison agrees.
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
##  4. **TWO DRAWS, ONE MATERIAL, AND A GRADIENT SPAN THAT FITS.** Two
##     `MultiMeshInstance3D`, shadows off, sharing ONE `Material` by identity —
##     across two separately built interiors, which is the only form of the
##     assertion a per-build `duplicate()` cannot pass. `STAFF_MESH_TOP` is
##     measured against the live `AABB` of the welded bodies, because a span under
##     the tallest one clamps its head flat and nothing else would ever say so.
##  5. **THE BODIES MOVE, AND THEY MOVE ALONG THE PATH.** Driven for two seconds of
##     simulated time. Every staffer's drawn position must change, must stay inside
##     `TowerInterior.inside_walls()`, must sit ON its own loop's polyline, and must
##     not have travelled further than `WALK_SPEED` allows — and the cell it is
##     drawn on is read back out of the storey's own ASCII `rows` string and must
##     not be one the router refuses. Read out of the MultiMesh BUFFER — the thing
##     the engine is handed — and not out of the records that decided it.
##  6. **THE STOREY WINDOW WRITES HIDDEN STAFF OUT OF THE DRAW.** Staff are not
##     children of a storey container — one MultiMesh spans ten floors — so the
##     interior's `visible = false` cannot hide them and `tick()` drops them out of
##     `visible_instance_count` instead. Every other probe in this file runs with
##     `_drawn_floor` at -1, where that branch is never taken, so this one drives
##     all ten windows and asserts against `_floor_visible` itself. Its control is
##     that the gate made BOTH decisions over the sweep.
##  7. **THE POPULATION RESETS** on the shell's own `player_entered`, exactly as the
##     guards do, and the opened set does not.
##  8. **THE SIGHTING TEST, AND EACH OF ITS FOUR CONDITIONS INVERTED** (bead
##     `godot-test1-buyt.4`). Storey, radius, cone and a march of plan cells — all
##     four have to say yes, and each one is turned off in isolation while the
##     other three are held. Every geometry is read out of the ASCII: a straight
##     open run, a `. # .` triple and a `D` cell with its own gate id. The one that
##     cannot be faked is the wall: a pair inside the radius, dead in the cone, and
##     refused only because the plan says there is stone between them.
##  9. **THE ALARM IS PER STOREY, BOUNDED, PULSED AND ROUTED.** One storey lit
##     leaves the others dark; a storey whose alarm is up refuses the next raise
##     and re-arms once it expires; the klaxon is pulsed BY THE TIMER and counted
##     over a whole alarm with a bound on both sides (a build that pulsed every
##     frame passes "did it sound"); and the `publish` flag decides mesh-and-caption
##     versus room-log-only, which is what stops two peers echoing one sighting.
## 10. **A STAFFER ACTUALLY RAISES IT, AND ONLY AFTER THE TELEGRAPH BEAT.** Driven
##     through the shipped `tick()` with the hero on the staffer's own next
##     waypoint. Half the beat must leave the storey dark; the second half must
##     light it; and a hero standing BEHIND the same staffer lights nothing.
## 11. **THE GUARD CONVERGES ON THE SIGHTING AND WALKS HOME**, as a real body under
##     real physics — to a room centre that is neither its post nor a lure plate,
##     so a build wired to the wrong thing cannot arrive. Every guard on every
##     other storey must still be on its post afterwards: convergence is
##     single-storey by three shipped rulings, not by omission.
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
## `POST_SETTLE_EPS` is written around. Check 7 reads the population one PROCESS
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
	await _check_the_storey_window_hides_them()
	await _check_the_population_resets_on_re_entry()
	_check_the_sighting_test()
	await _check_the_alarm_state()
	await _check_a_staffer_raises_the_alarm()
	await _check_the_guard_converges()
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
			# ...AND IT STANDS IN THE MIDDLE OF ITS CELL, not on the boundary.
			# `plan_route` emits cell CENTRES and `_storey_stops` derives them with
			# `+ 0.5`; drop that half-cell anywhere in the chain and every body
			# walks the lane's edge instead of its lane. Nothing above notices —
			# the boundary of cell c still floors to cell c, so the character test
			# passes and the polyline moves with it — which is exactly why this is
			# asserted as a number rather than inferred.
			var centre_x := TowerInterior._grid_x(float(cell.x) + 0.5)
			var centre_z := TowerInterior._grid_z(float(cell.y) + 0.5)
			if not is_equal_approx(here.x, centre_x) \
					or not is_equal_approx(here.z, centre_z):
				_fail("storey %d waypoint %d is at (%.3f, %.3f) but the centre of"
					% [floor_index, i, here.x, here.z]
					+ " cell %s is (%.3f, %.3f) — the staff walk the edge of the"
					% [str(cell), centre_x, centre_z] + " lane, not the lane")
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
	# EVERY STOP LANDS INSIDE THE ROOM IT CLAIMS, read back out of the PLAN.
	#
	# This is the assertion that catches the class of bug a count cannot. `path[0]`
	# and every stop on it were produced by `_grid_x(cell.x + 0.5)` /
	# `_grid_z(cell.y + 0.5)`; this converts them BACK to a cell with
	# `_plan_cell_of()` and asks whether that cell is inside the bbox a completely
	# separate scan of the ASCII (`plan_room_rect`) says the room occupies. A
	# derivation that read the wrong room's rect, that swapped the x and z axes —
	# the classic, and the one that puts a body tens of metres away in a different
	# room while every build-versus-build comparison stays perfectly consistent —
	# or that lost the `+ 0.5` and landed on a boundary, fails here. Nothing in this
	# block is compared against another thing `TowerStaff` computed.
	var stops_checked := 0
	for loop: Dictionary in table:
		var floor_index: int = loop["floor"]
		var rooms: Dictionary = TowerPlans.storey(floor_index)["rooms"]
		var path: PackedVector3Array = loop["path"]
		for letter: String in (loop["stops"] as Array):
			if not rooms.has(letter):
				_fail("storey %d's loop claims a stop in room '%s', which its plan"
					% [floor_index, letter] + " does not declare")
				continue
			var rect := TowerInterior.plan_room_rect(floor_index,
					String(rooms[letter]))
			# The stop is on the lap by construction, so find it there: the first
			# waypoint whose cell is inside the room is the stop for that room.
			var landed := false
			for point: Vector3 in path:
				if rect.has_point(TowerInterior._plan_cell_of(point)):
					landed = true
					break
			stops_checked += 1
			if not landed:
				_fail("storey %d's loop never enters room '%s', whose plan cells"
					% [floor_index, letter] + " are %s — the stop derived for it is"
					% str(rect) + " somewhere else in the building")
	if stops_checked < table.size():
		_fail("only %d stops were checked against a room rect over %d loops — the"
			% [stops_checked, table.size()] + " room-rect assertion is not running")
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
	# STAFF_MESH_TOP IS MEASURED OFF THE WELDED MESH, not taken on trust. It is the
	# divisor the top-lit gradient is computed over, so a value UNDER the tallest
	# body clamps that body's head flat at full colour and throws the gradient away
	# over the part you actually look at — and it is a number nothing else would
	# ever contradict, because a wrong gradient renders perfectly happily. Compared
	# against the live `AABB`, which is the mesh the engine draws.
	#
	# It shipped at 1.80 against a crown of 1.83 (the hard hat is welded at centre
	# 1.77 with a size of 0.12, and `add_box` emits `centre + vertex`), which is
	# exactly the silent 3 cm this assertion exists to catch. FEET AT ZERO is
	# asserted with it: the whole "boots-to-hat" span only means anything if the
	# weld starts on the floor.
	var tallest := 0.0
	for rack: MultiMeshInstance3D in racks_a:
		var box: AABB = rack.multimesh.mesh.get_aabb()
		tallest = maxf(tallest, box.position.y + box.size.y)
		if absf(box.position.y) > EPS:
			_fail("`%s`'s welded body starts at y %.3f, not with its feet on the"
				% [rack.name, box.position.y] + " floor — the gradient span and the"
				+ " walk both assume a body welded at zero")
	if not is_equal_approx(tallest, TowerStaff.STAFF_MESH_TOP):
		_fail("the tallest welded staff body tops out at %.3f m but STAFF_MESH_TOP"
			% tallest + " is %.3f — the gradient span is measured over the wrong"
			% TowerStaff.STAFF_MESH_TOP + " height, and a span UNDER the body"
			+ " clamps its head flat at full colour")
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
		# THE DRAWN POSITION, READ BACK OUT OF THE ASCII THAT AUTHORED THE STOREY.
		# `to` came out of the MultiMesh BUFFER — the transform the engine is handed
		# — and this converts it to a plan cell and asks the storey's own `rows`
		# string what is drawn there. A staffer rendered in a wall, off the grid, or
		# tens of metres from the plan it was derived from fails on the character,
		# whatever the arithmetic that placed it agreed with.
		var rows: Array = TowerPlans.storey(floor_index)["rows"] \
				if not TowerPlans.storey(floor_index).is_empty() else []
		if rows.is_empty():
			_fail("a staffer reports storey %d, which has no plan rows" % floor_index)
		else:
			var cell := TowerInterior._plan_cell_of(to)
			var ch := TowerInterior._plan_char(rows, cell)
			if not TowerInterior._route_open(ch):
				_fail("the staffer on storey %d is drawn at %s, which is plan cell"
					% [floor_index, str(to)] + " %s = '%s' — a cell the router"
					% [str(cell), ch] + " itself refuses, so it is being rendered"
					+ " inside the stonework")
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
# CHECK 6 — the storey window writes hidden staff out of the draw
# ============================================================================

func _check_the_storey_window_hides_them() -> void:
	"""
	Check 6. A staffer on a storey the interior is not drawing is written OUT of
	`visible_instance_count`, and one on the drawn storey or its neighbours is not.

	THE OTHER HALF OF `tick()`'s GATING, and until this check existed nothing in the
	suite touched it. `window` is `interior._drawn_floor >= 0`, `_drawn_floor` is
	written only by `TowerInterior._update_visibility()`, and that function returns
	early when there is no player — so every other probe in this file runs with
	`_drawn_floor` at -1, `window` false and `drawn` true for everybody. The branch
	that matters was executed nowhere and asserted nowhere.

	WHY IT MATTERS ENOUGH TO DRIVE DIRECTLY. Staff are NOT children of a storey
	container: one MultiMesh spans ten floors, which is the dossier rack's problem
	exactly, and a storey container's `visible = false` therefore cannot hide them.
	Without this gate a staffer on floor 9 is drawn walking inside floor 4's slab
	while the player stands on it, which is the kind of thing that looks like a
	rendering bug and is a gating bug.

	`_drawn_floor` IS SET DIRECTLY rather than by standing a player up inside the
	building, because what is under test is `TowerStaff.tick()`'s reading of that
	field, not `_update_visibility()`'s writing of it — that half is
	`tower_interior_selfcheck`'s check 3. Driving it here would make this check fail
	on a camera bug in another file.

	THE EXPECTATION IS DERIVED FROM `_floor_visible`, NOT RESTATED. That is the
	function `tick()` calls, so a check carrying its own `absi(a - b) <= 1` would
	stop agreeing with the building the day `FLOOR_NEIGHBOURS` grows an irregular
	row — which is the whole reason that table exists.
	"""
	var interior := await TowerProbe.make_interior(self)
	var floors: Array[int] = []
	for loop: Dictionary in TowerStaff.loops():
		floors.append(int(loop["floor"]))
	if floors.size() < 3:
		_fail("only %d storeys carry staff — check 6 cannot tell a window from"
			% floors.size() + " 'everything is drawn'")
		interior.queue_free()
		await process_frame
		Sentinel.done("the_storey_window_hides_them")
		return
	var hid := 0
	var showed := 0
	for window: int in TowerInterior.FLOOR_Y.size():
		interior._drawn_floor = window
		TowerStaff.tick(interior, 0.0)
		var drawn: Array[int] = []
		for walker: Dictionary in TowerStaff.walkers(interior):
			drawn.append(int(walker["floor"]))
		for floor_index: int in floors:
			var want := TowerInterior._floor_visible(floor_index, window)
			var got := drawn.has(floor_index)
			if want:
				showed += 1
			else:
				hid += 1
			if want and not got:
				_fail("with the window on storey %d, the staffer on storey %d is"
					% [window, floor_index] + " not drawn, though the interior"
					+ " draws that floor")
			elif got and not want:
				_fail("with the window on storey %d, the staffer on storey %d is"
					% [window, floor_index] + " still drawn — it is walking inside"
					+ " a slab the player cannot see through")
		# ...and the COUNT, which is the thing the engine actually reads. A `slot`
		# left stale from the previous window would keep a body on screen while
		# `walkers()` reported it gone.
		var visible := 0
		for a: int in TowerStaff.ARCHETYPE_COUNT:
			var rack := interior._staff.get_child(a) as MultiMeshInstance3D
			visible += rack.multimesh.visible_instance_count
		if visible != drawn.size():
			_fail("with the window on storey %d the MultiMeshes draw %d instances"
				% [window, visible] + " but %d staff report drawn" % drawn.size())
	# THE CONTROL: over the ten windows the gate must have said BOTH things. A test
	# that only ever saw "drawn" — which is exactly what every other check in this
	# file sees — cannot fail on a gate that is wired backwards.
	if hid == 0 or showed == 0:
		_fail("over %d windows the gate hid %d staff and showed %d — it never made"
			% [TowerInterior.FLOOR_Y.size(), hid, showed] + " both decisions, so"
			+ " this check would pass on a gate wired either way round")
	print("tower staff: over %d storey windows the gate hid %d and drew %d"
		% [TowerInterior.FLOOR_Y.size(), hid, showed])
	interior.queue_free()
	await process_frame
	Sentinel.done("the_storey_window_hides_them")


# ============================================================================
# CHECK 7 — the population resets on re-entry
# ============================================================================

func _check_the_population_resets_on_re_entry() -> void:
	"""
	Check 7. Crossing the doorway stands the staff back at the start of their loops
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
		_fail("no TowerInterior under the shell — check 7 has nothing to measure")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_population_resets_on_re_entry")
		return
	shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
	var opened_before: Array = shell.call("opened_ids")

	var staff_before := interior.get_node_or_null("Staff")
	var marks := TowerStaff.walkers(interior)
	if marks.is_empty():
		_fail("the tower stood up no staff at all — check 7 would pass on an empty"
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
		_fail("six seconds of walking moved the staff at most %.3f m — check 7"
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


# ============================================================================
# CHECK 8 — the sighting test: four conditions, and each one inverted
# ============================================================================

func _check_the_sighting_test() -> void:
	"""
	Check 8. `TowerStaff.sees()` answers yes only when the storey, the radius, the
	cone AND the march of plan cells all say yes — and no when any ONE of them is
	turned off while the other three are held.

	EVERY GEOMETRY IN THIS CHECK IS READ OUT OF THE ASCII, never written down here:
	a straight run of route-open cells for the three that are about arithmetic, a
	`. # .` triple for the wall, and a `D` cell with its own gate id for the door.
	A check that typed its own coordinates would agree with a build that had drawn
	the plan somewhere else.

	THE INVERSIONS ARE ISOLATED, which is the part that makes them worth running.
	The far quarry is placed ON THE CLEAR RUN and the march is asserted CLEAR there
	before the radius is asserted to refuse it, so "no" cannot be the wall
	answering; the cone is turned by rotating the YAW ALONE, which moves nothing
	the other three tests read. Both sides of the cone's edge are pinned, so a
	360-degree implementation fails one and a blind one fails the other.
	"""
	var run := _straight_open_run()
	if run.is_empty():
		_fail("no storey draws a straight open run long enough to measure a %.1f m"
				% TowerStaff.SIGHT_RADIUS + " sighting — check 8 would pass vacuously")
		Sentinel.done("the_sighting_test")
		return
	var floor_index: int = int(run["floor"])
	var eye: Vector3 = run["from"]
	var dir: Vector3 = run["dir"]
	var yaw: float = atan2(-dir.x, -dir.z)

	# ---- THE POSITIVE, first and load-bearing: a staffer looking down its own
	# corridor at somebody two cells away sees them. Everything below is a refusal,
	# and a `sees()` that answered false to everything would pass all of them.
	var near: Vector3 = eye + dir * (TowerPlans.PLAN_CELL * 2.0)
	if not TowerStaff.sees(floor_index, eye, yaw, near):
		_fail("a staffer on storey %d did not see a hero %.1f m dead ahead of it down"
				% [floor_index, TowerPlans.PLAN_CELL * 2.0] + " an open corridor")

	# ---- (a) THE RADIUS, with the march proved clear at the far point so that the
	# refusal can only be the distance.
	var far: Vector3 = eye + dir * (TowerStaff.SIGHT_RADIUS + 0.5)
	if not TowerStaff.line_of_sight(floor_index, eye, far):
		_fail("check 8's far mark is behind a wall — the radius inversion would be"
				+ " measuring the march instead")
	elif TowerStaff.sees(floor_index, eye, yaw, far):
		_fail("a staffer saw a hero %.1f m away, past its own %.1f m reach"
				% [TowerStaff.SIGHT_RADIUS + 0.5, TowerStaff.SIGHT_RADIUS])
	var inside: Vector3 = eye + dir * (TowerStaff.SIGHT_RADIUS - 0.3)
	if TowerStaff.line_of_sight(floor_index, eye, inside) \
			and not TowerStaff.sees(floor_index, eye, yaw, inside):
		_fail("a staffer did not see a hero %.1f m away, INSIDE its own %.1f m reach"
				% [TowerStaff.SIGHT_RADIUS - 0.3, TowerStaff.SIGHT_RADIUS]
				+ " — the radius is shorter than the const says")

	# ---- (b) THE CONE, both sides of its own edge, by turning the yaw and nothing
	# else. The mesh faces -Z at yaw 0, so this is the rotation a player sees.
	var half := deg_to_rad(TowerStaff.SIGHT_CONE_DEG * 0.5)
	if not TowerStaff.sees(floor_index, eye, yaw + half - 0.09, near):
		_fail("a hero %.0f degrees off a staffer's heading was outside a %.0f-degree"
				% [rad_to_deg(half - 0.09), TowerStaff.SIGHT_CONE_DEG] + " cone")
	if TowerStaff.sees(floor_index, eye, yaw + half + 0.09, near):
		_fail("a hero %.0f degrees off a staffer's heading was INSIDE its %.0f-degree"
				% [rad_to_deg(half + 0.09), TowerStaff.SIGHT_CONE_DEG]
				+ " cone — the cone is wider than the const says")
	if TowerStaff.sees(floor_index, eye, yaw + PI, near):
		_fail("a staffer saw a hero standing directly BEHIND it — walking behind one"
				+ " is the move the cone exists to allow")

	# ---- (c) THE STOREY. The same x and z, lifted to another floor's walking
	# surface: a cone test is blind to height and these are stacked slabs.
	var other := -1
	for candidate: int in TowerInterior.FLOOR_Y.size():
		if candidate != floor_index:
			other = candidate
			break
	if other >= 0:
		var upstairs := Vector3(near.x, TowerInterior.FLOOR_Y[other], near.z)
		if TowerStaff.sees(floor_index, eye, yaw, upstairs):
			_fail("a staffer on storey %d saw a hero standing on storey %d at the same"
					% [floor_index, other] + " x/z — it is looking through a slab")

	# ---- (d) THE MARCH: a wall between, read out of a `. # .` triple in the ASCII.
	var wall := _walled_pair()
	if wall.is_empty():
		_fail("no storey draws an open cell, a wall and an open cell in a row —"
				+ " check 8's line-of-sight inversion has nothing to stand behind")
	else:
		var wall_floor: int = int(wall["floor"])
		var wall_eye: Vector3 = wall["from"]
		var wall_at: Vector3 = wall["to"]
		var wall_yaw: float = atan2(-(wall_at.x - wall_eye.x), -(wall_at.z - wall_eye.z))
		# The pair is inside the radius and dead in the cone BY CONSTRUCTION, so the
		# only thing left to refuse it is the wall — which is the whole assertion:
		# a sighting that fired through one would land here and nowhere else.
		var gap: float = Vector2(wall_at.x - wall_eye.x, wall_at.z - wall_eye.z).length()
		if gap > TowerStaff.SIGHT_RADIUS:
			_fail("check 8(d)'s walled pair is %.1f m apart, past the %.1f m reach —"
					% [gap, TowerStaff.SIGHT_RADIUS] + " the refusal would be the radius")
		if TowerStaff.line_of_sight(wall_floor, wall_eye, wall_at):
			_fail("the march crossed a `%s` cell on storey %d and called it clear"
					% [TowerPlans.WALL_CHAR, wall_floor])
		if TowerStaff.sees(wall_floor, wall_eye, wall_yaw, wall_at):
			_fail("a staffer on storey %d saw a hero THROUGH A WALL %.1f m away"
					% [wall_floor, gap])

	# ---- (e) A DOOR IS AN OCCLUDER ONLY WHILE IT IS SHUT, and the answer comes
	# from the interior's own opened set rather than from a second opinion here.
	var door := _gated_pair()
	if door.is_empty():
		_fail("no storey draws a gate cell with open floor either side of it —"
				+ " check 8's door clause has nothing to look through")
	else:
		var door_floor: int = int(door["floor"])
		var shut := func(_id: String) -> bool: return false
		var opened := func(id: String) -> bool: return id == String(door["gate"])
		if TowerStaff.line_of_sight(door_floor, door["from"], door["to"], shut):
			_fail("the march looked straight through the CLOSED gate `%s` on storey %d"
					% [String(door["gate"]), door_floor])
		if not TowerStaff.line_of_sight(door_floor, door["from"], door["to"], opened):
			_fail("the march refused the OPEN gate `%s` on storey %d — an open doorway"
					% [String(door["gate"]), door_floor] + " is a doorway")
		# ...and with nobody to ask, a door is shut: a standalone interior with no
		# shell over it has no opened set at all.
		if TowerStaff.line_of_sight(door_floor, door["from"], door["to"]):
			_fail("with no opened set to consult, gate `%s` read as OPEN — a building"
					% String(door["gate"]) + " with no shell must not see through its doors")
	print("tower staff: sighting %.1f m / %.0f deg measured on storey %d; wall pair %s,"
			% [TowerStaff.SIGHT_RADIUS, TowerStaff.SIGHT_CONE_DEG, floor_index,
			"f%d" % int(wall.get("floor", -1))]
			+ " gate pair %s `%s`" % ["f%d" % int(door.get("floor", -1)),
			String(door.get("gate", ""))])
	Sentinel.done("the_sighting_test")


func _cell_point(floor_index: int, cell: Vector2i) -> Vector3:
	"""One plan cell's centre, in interior-local metres on that storey's surface."""
	return Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
			TowerInterior.FLOOR_Y[floor_index],
			TowerInterior._grid_z(float(cell.y) + 0.5))


func _straight_open_run() -> Dictionary:
	"""
	The first straight line of route-open cells long enough to measure a sighting
	over, as `{floor, from, dir}` — `from` the first cell's centre in local metres
	and `dir` a unit step along the run.

	LONG ENOUGH means past `SIGHT_RADIUS` plus a cell, so the radius inversion has
	somewhere clear to stand. Rows first, then columns; both axes are searched
	because which one a corridor runs along is the plan's business, not this file's.
	"""
	var want: int = int(ceil((TowerStaff.SIGHT_RADIUS + TowerPlans.PLAN_CELL)
			/ TowerPlans.PLAN_CELL)) + 1
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		if plan.is_empty():
			continue
		var rows: Array = plan["rows"]
		for axis: int in 2:
			var outer: int = rows.size() if axis == 0 else String(rows[0]).length()
			for a: int in outer:
				var run := 0
				var inner: int = String(rows[0]).length() if axis == 0 else rows.size()
				for b: int in inner:
					var cell := Vector2i(b, a) if axis == 0 else Vector2i(a, b)
					if TowerInterior._route_open(TowerInterior._plan_char(rows, cell)):
						run += 1
					else:
						run = 0
					if run < want:
						continue
					var step := Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
					var start := cell - step * (run - 1)
					return {
						"floor": floor_index,
						"from": _cell_point(floor_index, start),
						"dir": (_cell_point(floor_index, start + step)
								- _cell_point(floor_index, start)).normalized(),
					}
	return {}


func _walled_pair() -> Dictionary:
	"""
	The first `open, wall, open` triple in any storey's ASCII, as
	`{floor, from, to}` in local metres — two cells a staffer could reach across
	with exactly one `#` in between.
	"""
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		if plan.is_empty():
			continue
		var rows: Array = plan["rows"]
		for r: int in rows.size():
			var line := String(rows[r])
			for c in range(1, line.length() - 1):
				if line[c] != TowerPlans.WALL_CHAR:
					continue
				if not TowerInterior._route_open(line[c - 1]) \
						or not TowerInterior._route_open(line[c + 1]):
					continue
				return {
					"floor": floor_index,
					"from": _cell_point(floor_index, Vector2i(c - 1, r)),
					"to": _cell_point(floor_index, Vector2i(c + 1, r)),
				}
	return {}


func _gated_pair() -> Dictionary:
	"""
	The first gate cell with route-open floor on BOTH sides along one axis, as
	`{floor, gate, from, to}` — the two cells a doorway stands between.

	The gate id comes out of the storey's own `gates` dict, keyed `"c,r"`, which is
	the one binding between a `D` character and a gate (`TowerGates.gate_slots()`).
	A check that named a gate itself would stop measuring the day one was renamed.
	"""
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		if plan.is_empty():
			continue
		var rows: Array = plan["rows"]
		var gates: Dictionary = plan["gates"]
		for key: String in gates:
			var parts := key.split(",")
			if parts.size() != 2:
				continue
			var cell := Vector2i(int(parts[0]), int(parts[1]))
			if TowerInterior._plan_char(rows, cell) != TowerPlans.GATE_CHAR:
				continue
			for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if not TowerInterior._route_open(TowerInterior._plan_char(rows, cell - step)) \
						or not TowerInterior._route_open(
								TowerInterior._plan_char(rows, cell + step)):
					continue
				return {
					"floor": floor_index,
					"gate": String(gates[key]),
					"from": _cell_point(floor_index, cell - step),
					"to": _cell_point(floor_index, cell + step),
				}
	return {}


# ============================================================================
# CHECK 9 — the alarm: per storey, bounded, pulsed, routed, and cleared
# ============================================================================

## The three nodes an alarm talks to, reduced to the one method each and put in
## the group the interior finds them by. Source strings rather than scenes, the
## `mp_selfcheck` idiom: what is being measured is which of them is called, and a
## stub that can only count is a stub that cannot answer for the wrong reason.
const SOUND_STUB_SOURCE := """extends Node
var klaxons: int = 0
func play_klaxon() -> void:
	klaxons += 1
"""
const MP_STUB_SOURCE := """extends Node
var published: Array = []
func publish_alarm(floor_index: int, local_xz: Vector2) -> bool:
	published.append([floor_index, local_xz])
	return true
"""
const CAPTION_STUB_SOURCE := """extends Node
var captions: Array = []
func post_caption(msg: String, _duration: float = 0.0) -> bool:
	captions.append(msg)
	return true
"""
const LOG_STUB_SOURCE := """extends Node
var lines: Array = []
func note_event(line: String) -> void:
	lines.append(line)
"""


func _stub(source: String, group: String) -> Node:
	"""One group-discovered stub in the tree. Freed by the caller."""
	var script := GDScript.new()
	script.source_code = source
	script.reload()
	var node: Node = script.new()
	node.add_to_group(group)
	root.add_child(node)
	return node


func _check_the_alarm_state() -> void:
	"""
	Check 9. `TowerInterior.raise_alarm()` and the timer behind it.

	  (a) PER STOREY. Raising on one floor leaves every other floor's alarm down —
	      the whole reason the state is a dictionary keyed by floor and not a flag.
	  (b) BOUNDED. A storey whose alarm is up refuses the next raise outright, so a
	      staffer standing in a doorway cannot stack errands or spend the `alrm`
	      verb's budget; and it re-arms once the timer has run out, so an alarm is
	      a window and not a fuse.
	  (c) THE KLAXON IS PULSED BY THE TIMER, not started and forgotten: bead
	      godot-test1-buyt.1 shipped a ~0.6 s ONE-SHOT on purpose. Counted over a
	      whole alarm and bounded on BOTH sides — a build that pulsed every frame
	      passes a "did it sound" test and deafens the player.
	  (d) THE PUBLISH FLAG IS THE ECHO GATE. `publish = true` reaches the mesh and
	      says so on this screen's caption; `publish = false` — the `alrm` replay
	      path — reaches NEITHER, and puts its line in the room log instead. Two
	      peers that both re-published would echo one sighting round the room for
	      as long as the room lasted.
	  (e) A GARBAGE SIGHTING IS REFUSED: a storey the plans do not draw, or a point
	      that is not a number. `MpCodec.decode_alrm()` already refuses both on the
	      wire; this is the same refusal at the other door, where the caller is a
	      staffer rather than a packet.
	  (f) CROSSING THE DOORWAY CLEARS EVERY ALARM, with the population.
	"""
	var interior := await TowerProbe.make_interior(self) as TowerInterior
	var sound := _stub(SOUND_STUB_SOURCE, "sound_manager")
	var mp := _stub(MP_STUB_SOURCE, "mp")
	var caption := _stub(CAPTION_STUB_SOURCE, "world_caption")
	var log_hud := _stub(LOG_STUB_SOURCE, "event_log")
	var floors: int = TowerInterior.FLOOR_Y.size()
	var lit: int = mini(4, floors - 1)
	var spot := Vector2(3.0, -2.0)

	# ---- (a) and the raise itself -------------------------------------------
	if not interior.raise_alarm(lit, spot):
		_fail("raise_alarm refused an honest sighting on storey %d" % lit)
	if absf(interior.alarm_seconds_left(lit) - TowerInterior.ALARM_SECONDS) > EPS:
		_fail("storey %d's alarm stands at %.2f s, not the %.2f s it was raised for"
				% [lit, interior.alarm_seconds_left(lit), TowerInterior.ALARM_SECONDS])
	for other: int in floors:
		if other != lit and interior.alarm_seconds_left(other) > 0.0:
			_fail("raising storey %d's alarm also lit storey %d — the alarm is a"
					% [lit, other] + " building-wide flag, not a per-storey state")

	# ---- (b) the bound -------------------------------------------------------
	if interior.raise_alarm(lit, spot):
		_fail("a second alarm was accepted on storey %d while its first was still"
				% lit + " up — an alarm that queues is a button to hold down")

	# ---- (c) the pulse, over a whole alarm -----------------------------------
	var lit_at_raise: int = int(sound.get("klaxons"))
	if lit_at_raise != 1:
		_fail("raising an alarm sounded the klaxon %d times, expected exactly one"
				% lit_at_raise)
	var step: float = 1.0 / 60.0
	var ticks: int = int(ceil(TowerInterior.ALARM_SECONDS / step)) + 4
	for _i in ticks:
		interior._tick_alarm(step)
	var pulses: int = int(sound.get("klaxons")) - lit_at_raise
	var want: int = int(TowerInterior.ALARM_SECONDS / TowerInterior.ALARM_PULSE)
	if pulses < want - 1 or pulses > want + 1:
		_fail("a %.0f s alarm pulsed the klaxon %d times; at one every %.1f s it should"
				% [TowerInterior.ALARM_SECONDS, pulses, TowerInterior.ALARM_PULSE]
				+ " pulse about %d" % want)
	if interior.alarm_seconds_left(lit) > 0.0:
		_fail("storey %d's alarm was still up %.1f s after it was raised"
				% [lit, TowerInterior.ALARM_SECONDS])
	var quiet: int = int(sound.get("klaxons"))
	for _i in 120:
		interior._tick_alarm(step)
	if int(sound.get("klaxons")) != quiet:
		_fail("the klaxon kept sounding after every alarm had expired")
	# ...and it re-arms.
	if not interior.raise_alarm(lit, spot):
		_fail("storey %d refused a fresh alarm after its own had expired — an alarm"
				% lit + " is a window, not a fuse")

	# ---- (d) the publish flag ------------------------------------------------
	if (mp.get("published") as Array).size() != 2:
		_fail("the two published alarms reached the mesh %d times"
				% (mp.get("published") as Array).size())
	else:
		var sent: Array = (mp.get("published") as Array)[0]
		if int(sent[0]) != lit or (sent[1] as Vector2) != spot:
			_fail("the sighting reached the mesh as %s, not storey %d at %s"
					% [str(sent), lit, str(spot)])
	if (caption.get("captions") as Array).size() != 2:
		_fail("a staffer's own sighting did not put a caption on this screen")
	if not (log_hud.get("lines") as Array).is_empty():
		_fail("our OWN sighting wrote a line into the room log — the log is for the"
				+ " alarms we did not cause")
	var relayed: int = mini(lit + 1, floors - 1)
	if relayed == lit:
		relayed = maxi(lit - 1, 0)
	var published_before: int = (mp.get("published") as Array).size()
	var captions_before: int = (caption.get("captions") as Array).size()
	if not interior.raise_alarm(relayed, spot, false):
		_fail("a relayed alarm was refused on storey %d" % relayed)
	if (mp.get("published") as Array).size() != published_before:
		_fail("a REPLAYED alarm went back out on the mesh — two peers would echo one"
				+ " sighting round the room for as long as the room lasted")
	if (caption.get("captions") as Array).size() != captions_before:
		_fail("a relayed alarm captioned this screen, which never saw anything")
	if (log_hud.get("lines") as Array).size() != 1:
		_fail("a relayed alarm wrote %d lines into the room log, expected one"
				% (log_hud.get("lines") as Array).size())
	elif String((log_hud.get("lines") as Array)[0]) != tr(TowerInterior.ALARM_LOG_LINE):
		_fail("the room log line was %s, not the translated %s"
				% [str((log_hud.get("lines") as Array)[0]), TowerInterior.ALARM_LOG_LINE])

	# ---- (e) garbage ---------------------------------------------------------
	for bad: int in [-1, floors, floors + 7]:
		if interior.raise_alarm(bad, spot):
			_fail("an alarm was raised on storey %d, which the plans do not draw" % bad)
	if interior.raise_alarm(maxi(floors - 1, 0), Vector2(NAN, 0.0)):
		_fail("an alarm was raised at a sighting point that is not a number")

	# ---- (f) the reset -------------------------------------------------------
	interior._on_tower_doorway(null)
	for any: int in floors:
		if interior.alarm_seconds_left(any) > 0.0:
			_fail("storey %d's alarm survived a doorway crossing — the guards are"
					% any + " re-posted on that signal, so the errand has no body left")

	print("tower staff: storey %d's alarm ran %.0f s and pulsed the klaxon %d times;"
			% [lit, TowerInterior.ALARM_SECONDS, pulses]
			+ " %d published, %d captioned, %d logged"
			% [(mp.get("published") as Array).size(),
			(caption.get("captions") as Array).size(),
			(log_hud.get("lines") as Array).size()])
	sound.queue_free()
	mp.queue_free()
	caption.queue_free()
	log_hud.queue_free()
	interior.queue_free()
	await process_frame
	Sentinel.done("the_alarm_state")


# ============================================================================
# CHECK 10 — a staffer actually raises it, and only after the telegraph beat
# ============================================================================

func _check_a_staffer_raises_the_alarm() -> void:
	"""
	Check 10. The wiring, driven through the shipped `tick()`: a hero standing in a
	staffer's cone raises that storey's alarm — AFTER the telegraph beat and not
	before — and a hero standing behind the same staffer raises nothing.

	THE HERO IS PUT ON THE STAFFER'S OWN NEXT WAYPOINT, which is one route-open cell
	ahead of it along its loop. That is dead in the cone, inside the radius and
	clear by construction — the loop is continuous (check 1) — so nothing here is
	balanced on a coordinate this file guessed.

	THE BEAT IS THE ASSERTION WITH TEETH. Half of `SIGHT_TELEGRAPH` is driven first
	and the storey must still be dark: a build that raised on the first frame in
	the cone passes every "did it fire" test and makes every corner a coin flip.
	Its control is the second half, which must then raise it.
	"""
	var interior := await TowerProbe.make_interior(self) as TowerInterior
	if interior._staff_walkers.is_empty():
		_fail("the building stood up no staff — check 10 has nobody to be seen by")
		interior.queue_free()
		await process_frame
		Sentinel.done("a_staffer_raises_the_alarm")
		return
	var walker: Dictionary = interior._staff_walkers[0]
	var loop: Dictionary = walker["loop"]
	var path: PackedVector3Array = loop["path"]
	var floor_index: int = int(walker["floor"])
	# Park the staffer ON its first waypoint, so its heading is the leg to the
	# second one and the hero can stand on the end of it.
	walker["dist"] = 0.0
	walker["seen"] = 0.0
	var hero := Node3D.new()
	root.add_child(hero)
	hero.global_position = interior.global_position + path[1]
	interior._player = hero

	# ---- THE BEAT ------------------------------------------------------------
	var step: float = 1.0 / 60.0
	var half: int = int(TowerStaff.SIGHT_TELEGRAPH * 0.5 / step)
	for _i in half:
		TowerStaff.tick(interior, step)
	if float(walker["seen"]) <= 0.0:
		_fail("a hero standing %.1f m dead ahead of a staffer on storey %d was not"
				% [path[0].distance_to(path[1]), floor_index] + " noticed at all")
	if interior.alarm_seconds_left(floor_index) > 0.0:
		_fail("the alarm went up after %.2f s, inside the %.2f s telegraph beat —"
				% [float(half) * step, TowerStaff.SIGHT_TELEGRAPH]
				+ " backing out of a doorway has to be a move")
	for _i in half + 8:
		TowerStaff.tick(interior, step)
	if interior.alarm_seconds_left(floor_index) <= 0.0:
		_fail("a hero stood in a staffer's cone for %.2f s on storey %d and no alarm"
				% [float(2 * half + 8) * step, floor_index] + " ever went up")

	# ---- THE CONTROL: behind it, and out of the cone -------------------------
	# A fresh storey, so the bound in check 9(b) cannot be what keeps this dark.
	var behind := -1
	for candidate: Dictionary in interior._staff_walkers:
		if int(candidate["floor"]) != floor_index:
			behind = interior._staff_walkers.find(candidate)
			break
	if behind < 0:
		_fail("only one storey carries staff — check 10's control has nowhere to run")
	else:
		var other: Dictionary = interior._staff_walkers[behind]
		var other_loop: Dictionary = other["loop"]
		var other_path: PackedVector3Array = other_loop["path"]
		other["dist"] = 0.0
		other["seen"] = 0.0
		# One cell the OTHER way: the staffer walks from path[0] towards path[1],
		# so the far side of path[0] is squarely behind it.
		hero.global_position = interior.global_position \
				+ other_path[0] + (other_path[0] - other_path[1])
		for _i in int(TowerStaff.SIGHT_TELEGRAPH * 3.0 / step):
			TowerStaff.tick(interior, step)
		if interior.alarm_seconds_left(int(other["floor"])) > 0.0:
			_fail("a staffer on storey %d raised the alarm on a hero standing BEHIND"
					% int(other["floor"]) + " it")

	print("tower staff: a hero %.2f m ahead of the staffer on storey %d was dark at"
			% [path[0].distance_to(path[1]), floor_index]
			+ " %.2f s and lit at %.2f s (beat %.2f s); behind it, nothing"
			% [float(half) * step, float(2 * half + 8) * step,
			TowerStaff.SIGHT_TELEGRAPH])
	interior._player = null
	hero.queue_free()
	interior.queue_free()
	await process_frame
	Sentinel.done("a_staffer_raises_the_alarm")


# ============================================================================
# CHECK 11 — the guard converges on the sighting, and walks home afterwards
# ============================================================================

## How long check 11 gives a guard to walk to the sighting, in seconds.
## `tower_guard_selfcheck`'s own lure budget, for the same walk over the same plan.
const CONVERGE_BUDGET: float = 18.0

## The shortest errand check 11 will accept, in metres of ROUTE. Comfortably past
## `INVESTIGATE_ARRIVE` (1.6 m) and past a wander's own drift, so "it arrived"
## cannot be "it was standing there".
const CONVERGE_MIN_WALK: float = 8.0

## How close to its post the guard has to get back to for the return to count.
## Loose on purpose: what is being measured is "it came back", and a body settling
## onto a slab at the end of a route is allowed a metre of it.
const HOME_EPS: float = 2.0


func _check_the_guard_converges() -> void:
	"""
	Check 11. A raised alarm walks the storey's REAL guard to the sighting point,
	holds it there for the alarm's own duration, and then walks it home.

	THE SIGHTING IS NOT A PLATE AND NOT THE POST. It is a room centre several metres
	off the post, so a build that had wired the alarm to `lure_guard()`'s plate, or
	one that did nothing at all, cannot reach it. That is the assertion a wrong
	implementation cannot satisfy: the body has to arrive at the cell the ALARM
	named.

	THE HOLD IS ASSERTED AS A VALUE and then wound forward, rather than waited out.
	`ALARM_SECONDS` of standing still is twelve seconds of real physics for one
	number, and the number is readable the frame the errand is taken — so the check
	reads it there and then spends its frames on the WALK HOME, which is the part
	that can only be measured by watching.

	NOTHING HERE MOVES A SECOND BODY. The converging guard is the SIGHTING STOREY'S
	OWN, and every other guard in the building must still be standing on its post
	when this is over: `GUARDS_PER_STOREY_MAX` is 1, `plan_route` is a single-storey
	BFS and `set_confinement` leashes a guard to its own floor, so a cross-storey
	converge would have to break all three (see `TowerInterior._send_guard_to`).
	"""
	var shell := await TowerProbe.make_tower(self)
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("no interior under the tower — check 11 has nothing to raise")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_guard_converges")
		return

	# WHICH STOREY AND WHICH POINT ARE THE PLANS' BUSINESS: the SHORTEST walk, over
	# every storey that draws a `G`, from that post to a room centre at least
	# `CONVERGE_MIN_WALK` metres of ROUTE away. Shortest because the budget below is
	# real physics and a 39 m errand is half a minute of it; at least that far
	# because a sighting the guard is already standing on measures nothing.
	#
	# ROUTE length and not straight-line: the plan is a maze and the two disagree by
	# a factor of three on some floors.
	var floor_index := -1
	var sighting := Vector3.INF
	var walk := INF
	for candidate: int in TowerPlans.floors():
		var post: Dictionary = TowerInterior._plan_guard_post(candidate)
		if post.is_empty():
			continue
		var from: Vector3 = post["post"]
		for stop: Dictionary in TowerStaff._storey_stops(candidate):
			var route := TowerInterior.plan_route(candidate, from, stop["point"])
			if route.is_empty():
				continue
			var length := from.distance_to(route[0])
			for i in range(1, route.size()):
				length += route[i - 1].distance_to(route[i])
			if length < CONVERGE_MIN_WALK or length >= walk:
				continue
			floor_index = candidate
			sighting = stop["point"]
			walk = length
	if floor_index < 0:
		_fail("no storey carries a guard post with a room centre at least %.0f m of"
				% CONVERGE_MIN_WALK + " route away — check 11 would pass vacuously")
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_guard_converges")
		return

	# NO PROBE PLAYER, and that is deliberate rather than an omission: an
	# ACQUISITION CANCELS AN ERRAND (`_abandon_investigation`), so a hero parked
	# anywhere a guard can smell turns this check into a measurement of the chase.
	# `tower_guard_selfcheck` check 21 parks one because it goes on to measure the
	# spot; this check only needs the walk, and the walk needs nobody to be seen.
	interior.reset_guards()
	await process_frame
	for _i in 30:
		await physics_frame

	var guard: Node3D = interior.call("_guard_on", floor_index) as Node3D
	if guard == null:
		_fail("storey %d draws a `G` but stood no guard on it" % floor_index)
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_guard_converges")
		return
	var post := guard.global_position

	if not interior.raise_alarm(floor_index, Vector2(sighting.x, sighting.z), false):
		_fail("the alarm on storey %d was refused" % floor_index)
		await TowerProbe.clear(self, null, shell)
		Sentinel.done("the_guard_converges")
		return
	if not bool(guard.get("is_investigating")):
		_fail("the alarm on storey %d woke no guard — the converge is a flag nothing"
				% floor_index + " acts on")
	elif absf(float(guard.get("_investigate_hold")) - TowerInterior.ALARM_SECONDS) > EPS:
		_fail("the guard holds the sighting for %.1f s, not the alarm's own %.1f s —"
				% [float(guard.get("_investigate_hold")), TowerInterior.ALARM_SECONDS]
				+ " it would walk home with the klaxon still sounding")

	# ---- THE WALK OUT --------------------------------------------------------
	var arrive: float = float(load(TowerProbe.CROC_SCRIPT)
			.get_script_constant_map()["INVESTIGATE_ARRIVE"])
	var target := interior.global_position + sighting
	var arrived := false
	var best := INF
	for _i in int(CONVERGE_BUDGET * 60.0):
		await physics_frame
		var gap: float = Vector2(guard.global_position.x - target.x,
				guard.global_position.z - target.z).length()
		best = minf(best, gap)
		if gap <= arrive:
			arrived = true
			break
	if not arrived:
		_fail("the guard never reached the sighting %.1f m of route from its post in"
				% walk + " %.0f s (closest %.1f m) — the alarm converges on nothing"
				% [CONVERGE_BUDGET, best])

	# ---- NOBODY ELSE TOOK THE ERRAND ----------------------------------------
	# Measured off `is_investigating` and NOT off where the bodies are standing: a
	# guard that is not on an errand is still WANDERING its own beat, so a position
	# test here would fail on a perfectly correct build. The errand flag is exactly
	# what a cross-storey converge would have to set, and the only thing that sets
	# it is `investigate_point()`.
	var strays: Array[String] = []
	for other: Node in interior._guards.get_children():
		if other == guard or not (other is Node3D):
			continue
		if bool(other.get("is_investigating")):
			strays.append(other.name)
	if not strays.is_empty():
		_fail("storey %d's alarm put %s on an errand as well — convergence is"
				% [floor_index, str(strays)] + " SINGLE-STOREY by three shipped"
				+ " rulings (see TowerInterior._send_guard_to)")
	if not bool(guard.get("is_investigating")) and arrived:
		_fail("the guard that walked to the sighting is not the one the alarm named")

	# ---- THE WALK HOME -------------------------------------------------------
	# The HOLD's length was asserted above, off the value the errand was taken with;
	# spending twelve seconds of real physics watching a body stand still would
	# measure the same number again. Wound forward, so these frames buy the walk
	# back — which is the half that can only be seen by watching.
	guard.set("_investigate_hold", 0.05)
	var home := false
	for _i in int(CONVERGE_BUDGET * 60.0):
		await physics_frame
		if not bool(guard.get("is_investigating")) \
				and guard.global_position.distance_to(post) <= HOME_EPS:
			home = true
			break
	if arrived and not home:
		_fail("the guard never got back to its post after the alarm (it stands %.1f m"
				% guard.global_position.distance_to(post) + " away, investigating=%s)"
				% str(guard.get("is_investigating")))

	print("tower staff: storey %d's guard walked %.1f m of route to the sighting"
			% [floor_index, walk] + " (arrived=%s, home=%s), %d other guards idle"
			% [str(arrived), str(home), interior._guards.get_child_count() - 1])
	await TowerProbe.clear(self, null, shell)
	Sentinel.done("the_guard_converges")


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
