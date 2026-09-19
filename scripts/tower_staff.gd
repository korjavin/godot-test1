class_name TowerStaff
extends RefCounted
## THE HQ'S CIVILIAN STAFF — scientists in white coats and engineers in blue
## overalls, walking the storeys of the GD-SURVEY building (bead
## `godot-test1-buyt.3`, epic `godot-test1-buyt`).
##
## OWNER, 2026-09-18: "Inside the GD-SURVEY HQ there should be STAFF walking
## around — scientists in white coats, engineers in blue overalls — going about
## the storeys." This file is the BODIES AND THEIR LOOPS and nothing else: staff
## walk, staff are visible, staff do nothing. The sighting, the klaxon and the
## guard's converge are bead `godot-test1-buyt.4`'s and are deliberately absent
## here — a population you can see walking is a thing to look at on its own, and
## splitting it off is what let .1, .2 and .3 land in parallel.
##
## `tower_guards.gd` IS THE TEMPLATE, verbatim where it fits: `class_name`, every
## function `static`, no instance state, the interior handed in as an argument,
## and the population parented to the BUILDING rather than to a chunk that
## unloads out from under it. Read that file's header for the parenting argument;
## it is the same argument and it is not repeated here.
##
## THE PARAMETER IS TYPED, and that is the one place this file differs from
## `TowerGuards`. Its two `interior` parameters are untyped because
## `tower_interior.gd` const-aliases four of its names back, and a type annotation
## is a parse-time reference just like a `const`, so the pair would be a cycle.
## NOTHING IS ALIASED BACK FROM HERE — the interior's whole surface is one
## `TowerStaff.reset(self)` in `_ready()`, one in `_on_tower_doorway`, and one
## `TowerStaff.tick(self, delta)` in `_process`, all inside function bodies. That
## is the `TowerDressing` / `TowerDossiers` shape and it keeps the const direction
## one way, so the type can stay on.
##
## ============================================================================
## WHY THERE IS NO COLLIDER, AND WHY THAT IS NOT A PERFORMANCE DECISION
## ============================================================================
##
## Staff are MultiMesh instances. They carry NO `CollisionObject3D` of any kind,
## they are in NO group, they are not a `SPECIES` row and they are not skinned.
## The hard constraint — the one that is not a preference and may not be traded
## away for a nicer-looking body later — is THE SOFTLOCK AUDIT:
##
##   `tower_selfcheck` is a `TowerGraph` walk plus a GRID FLOOD FILL over the 40 x
##   40 plans, whose corridors are ONE OR TWO CELLS wide (`TowerPlans.PLAN_CELL`
##   is 1.94 m). `TowerGuards`' header states why a guard is safe in that world:
##   "the player is collision mask 1 and walks THROUGH a predator, so a guard
##   standing in a doorway is a threat and never a wall." A staff body with ANY
##   collider does not get that. `ambience_proxies.gd`'s pool — the crowd's answer
##   to the same question — sits on layer 3, and `scenes/player.tscn` has
##   `collision_mask = 5`, which MASKS LAYER 3. So a pooled proxy in a 1.94 m
##   corridor is a MOVABLE WALL THE FLOOD FILL CANNOT SEE, and the crowd's
##   anti-trap machinery (the STUCK window, `SOFT_SECONDS`) was written for 8 m
##   avenues, not for a doorway. `ambience_proxies.gd`'s own header — "Nothing
##   else may use it; this is scenery collision, never a gameplay body" — is
##   honoured by not reaching for it.
##
## The other three reasons are in the epic and are ordinary: two draw calls for a
## ten-storey building against 10–20 `Skeleton3D`s writing bone rotations inside
## the one room the owner asks the player to spend the most time in; a node in
## "crocodile" would be swept by `crocodile_lod_manager`, scattered by the Stink
## Wave and synced by `mp_croc_sync`, none of which is true of a filing clerk; and
## `CityAgents.add_box` already IS the recipe, so there is no Blender lane, no
## `.glb` and no `scripts/predator_parts.py` rebuild gate.
##
## THE ACCEPTED CEILING, written down so nobody re-litigates it silently: staff
## are BOX FIGURES and they read at corridor distance, not close up. If the owner
## later wants them skinned, the seam to change is `_archetype_mesh()` below and
## nothing else cares — the loops, and .4's detection, are about a position and a
## facing.
##
## ============================================================================
## WHERE THE LOOPS COME FROM — THE PLAN, AND NO NEW GLYPH
## ============================================================================
##
## `TowerPlans`' character table is full (A–Z less S, P, G, D, L are room letters)
## and a staff glyph would have to be edited into all ten `STOREYS` rows before
## one staffer walked. It is not needed. Every storey already declares a `rooms`
## dict, and two readers are already shipped:
##
##   * `TowerInterior.plan_room_rect(floor, room_id)` — one room's cell bbox.
##   * `TowerInterior.plan_route(floor, from, to)` — the four-connected BFS over
##     the same const grid that the lure already walks a guard along. It returns
##     EVERY cell centre of the way in interior-local metres, or EMPTY when the
##     plan offers none.
##
## So a storey's loop is its rooms' centre cells, routed pairwise and closed. Zero
## RNG, zero hashing, zero seeding, zero plan edits — and a storey that gains a
## room gains a stop the day its plan row lands, which is the extension rule this
## building is built around (`_build_lure_pads()`'s precedent for `P`, verbatim).
##
## ============================================================================
## MEASURED, ON THE SHIPPED PLANS (2026-09-19) — three numbers that shaped this
## ============================================================================
##
##  1. ALL 57 ROOM BBOX CENTRES LAND ON A ROUTE-OPEN CELL today. They are still
##     filtered (`_route_open`), for a reason that is structural rather than
##     defensive — see `_storey_stops()`.
##  2. ANCHORING ON THE FIRST ROOM IN THE DICT LEAVES STOREY 5 EMPTY. Floor index
##     4's first room is `s5_boardroom`, which is behind the stair riddle's mass,
##     so nothing else on the floor is reachable from it and a whole storey would
##     have had no staff for no reason a player could see. `_storey_loop()` takes
##     the LARGEST reachable group instead; that recovered 7 of 8 rooms there and
##     5 of 7 on the cell block. See its docstring for why that costs ~2n routes
##     and not n².
##  3. THE LOOPS ARE LONG: 78 m (floor 0) to 718 m (floor 4), a lap of 71 to 653
##     seconds at `WALK_SPEED`. That is the number to look at if the owner says
##     one staffer per storey reads empty — see `STAFF_PER_STOREY`.
##
## ============================================================================
## RESERVED FOR BEAD `godot-test1-buyt.4` — the owner's detection defaults
## ============================================================================
##
## Recorded here rather than implemented, because this bead raises no alarm and a
## const with no reader is dead code. When .4 writes the sighting test, the owner's
## numbers are ~7 m of reach and a ~90-degree cone: NARROWER AND SHORTER than the
## guard's own 9 m / 120 degrees (`species_table.gd`'s `tower_guard` row), so that
## staff make a corridor dangerous to loiter in while the GUARD stays the thing
## that actually catches you. The stake does not move: a staffer never touches the
## player, has no `captures_hero` and no `coin_setback`, and the only consequence
## of being seen is that the storey's own guard walks to where you were.

## The shared ambience budget — "only those moving who we can see", without
## freezing. Reused rather than re-derived: that file exists precisely so the rule
## and its tick rate are ONE number, and a null camera (every headless check)
## degrades to "everything is visible", which is full rate.
const AmbienceLod := preload("res://scripts/ambience_lod.gd")

# ============================================================================
# THE POPULATION — one owner ruling and one retune knob
# ============================================================================

## HOW MANY STAFF WALK ONE STOREY'S LOOP.
##
## ONE, and it is the same stealth-tempo argument that makes
## `TowerGuards.GUARDS_PER_STOREY_MAX` one: this building is a stealth problem,
## not a chase, and a corridor with two moving bodies in it stops being something
## you can watch, time and walk past. Staff cannot capture you, but from behind
## they look exactly like the thing that can, and that is the point of them.
##
## THE RETUNE KNOB, with the measurement behind it. If the owner says "staff
## walking around" reads EMPTY at one, the number that makes it empty is not this
## const, it is the LAP: the derived loops run 78 m to 718 m, which is 71 to 653
## seconds at `WALK_SPEED`, so on the big floors one staffer is out of sight most
## of the time. Raising this to 2 spreads the extra bodies EVENLY along the same
## loop (`reset()` starts staffer k at `k / n` of the way round), so two is two
## encounters a lap and not two bodies walking in step.
##
## ASSERTED FROM THE BUILT POPULATION, never from the table — `tower_guard_selfcheck`
## check 12's rule: a builder that quietly stopped writing instances would
## otherwise be reported as a full population by the table it was meant to be
## standing up.
const STAFF_PER_STOREY: int = 1

## An office corridor pace, and deliberately SLOWER than the guard's 1.4 m/s
## patrol (`species_table.gd`'s `tower_guard` row). Two populations moving at one
## speed read as one population; the half-second-per-metre difference is what lets
## you tell, down a corridor, which of the two shapes ahead of you is the one that
## can arrest you.
const WALK_SPEED: float = 1.1

## Radians of stride phase per metre travelled, and the bob/sway/pitch amplitudes
## the phase drives — `crowd_manager.gd`'s idiom and its numbers. A PURE FUNCTION
## OF METRES WALKED, so there is no per-instance animation state to keep, to reset
## or (when .4 or a room ever wants it) to sync, and no `AnimationPlayer` anywhere
## near it (CLAUDE.md: the pose is a function of phase).
const STRIDE_FREQUENCY: float = 4.2
const WALK_BOB_AMOUNT: float = 0.045
const WALK_SWAY_AMOUNT: float = 0.035
const WALK_PITCH_AMOUNT: float = 0.015

# ============================================================================
# THE TWO ARCHETYPES
# ============================================================================

const ARCHETYPE_SCIENTIST: int = 0
const ARCHETYPE_ENGINEER: int = 1
const ARCHETYPE_COUNT: int = 2

const ARCHETYPE_NAMES: Array[String] = ["Scientists", "Engineers"]

## How tall the TALLER archetype's welded mesh is, boots to hat — the span the
## top-lit gradient is measured over. `crowd_manager.CITIZEN_MESH_TOP`'s rule and
## its reasoning: one number for both, and it is the MAXIMUM because the span is a
## divisor — a shorter body simply tops out short of full colour, whereas a span
## UNDER a body's height clamps its whole head flat and throws the gradient away
## over the part you actually look at. The engineer's hard hat is the top of it.
const STAFF_MESH_TOP: float = 1.80

## Surface roughness handed to `CityAgents.gradient_material`. Higher than the
## crowd's 0.85: a lab coat and a boiler suit are matte cloth under the interior's
## flat white ceiling panels, and a specular highlight indoors reads as plastic.
const STAFF_ROUGHNESS: float = 0.95

## ONE material for BOTH MultiMeshes, for the whole process. `crowd_manager`'s
## invariant exactly ("never `duplicate()` per instance"), and like the crowd's it
## is asserted off the LIVE `material_override` by identity rather than read off
## this variable. `static` for the reason `_guard_scene` is: there is one tower,
## but a self-check builds a dozen.
static var _shared_material: ShaderMaterial = null

## The two welded meshes, built once per process.
static var _archetype_meshes: Array = [null, null]

## The derived loops, built once per process. `TowerPlans.STOREYS` is a `const`, so
## the answer cannot change within a run — `TowerGuards._guard_table_cache`'s
## reason, verbatim.
##
## AND THE CACHE IS LOAD-BEARING, NOT A MICRO-OPTIMISATION. MEASURED on this
## machine, 2026-09-19: the cold build is 52 ms and the cached read is a
## microsecond. That 52 ms is ~110 BFS runs over 1600-cell grids (about 2n routes
## per storey — see `_storey_loop()`), and it is paid ONCE per process, inside
## `TowerInterior._ready()`, which already costs 155 ms on its own and happens once
## per run when the tower streams in. A second interior — twelve of them in the
## self-checks — pays nothing.
##
## `ponytail:` THE CEILING IS THAT IT IS 110 BFS RUNS AND NOT ONE FLOOD FILL. The
## reachability groups could be had from a single labelling pass per storey, at
## maybe a twentieth of the cost, but that is a SECOND traversal of `_route_open`
## living beside `plan_route`'s — and this building's whole routing story is that
## there is one of those. If the plans ever grow to where 52 ms at stream-in shows
## on a `\\fo` trace, that is the upgrade, and it belongs in `tower_plan_boxes.gd`
## next to the router rather than here.
static var _loops_cache: Array = []


static func shared_material() -> ShaderMaterial:
	"""The one ambience material both MultiMeshes wear, lazily built."""
	if _shared_material == null:
		_shared_material = CityAgents.gradient_material(STAFF_MESH_TOP, STAFF_ROUGHNESS)
	return _shared_material

# ============================================================================
# THE LOOPS — derived from the ASCII plans, and from nothing else
# ============================================================================

static func loops() -> Array:
	"""
	Every storey's patrol loop, derived from its `rooms` dict. Cached per process.

	@return: rows shaped `{floor, stops, path, arc, length}` —
	    `stops` the room letters kept (for the self-check's message),
	    `path` a `PackedVector3Array` of interior-local waypoints, closed (the
	    last leg ends back on the first waypoint),
	    `arc` a `PackedFloat32Array` of cumulative distances, `arc[i]` being the
	    walk from `path[0]` to `path[i]`, and `length` the whole lap.

	A STOREY WITH NO LOOP IS ABSENT, exactly as a storey with no `G` is absent
	from `TowerGuards.guard_posts_table()`. Storey 2 is one today: it draws two
	rooms and the identity mass stands between them, so there is no round trip.

	NOT SEEDED, NOT HASHED, NOT RANDOM. The run's seed, the hash spellings and the
	RNG calls are all absent from this file, and `tower_staff_selfcheck` scans every
	line of it for them — the way `budapest_selfcheck` scans `budapest_plan.gd`, and
	under the same rule its `BANNED_TOKENS` sets: THE PROSE HERE MAY NOT SPELL THEM
	EITHER, because a scanner that had to tell a comment from a statement would be a
	scanner with somewhere to hide. The tower is one of the project's two authored
	exceptions and its population has to be as deterministic as its walls, or two
	peers in one room would watch different buildings.
	"""
	if not _loops_cache.is_empty():
		return _loops_cache
	var out: Array = []
	for floor_index: int in TowerPlans.floors():
		var loop := _storey_loop(floor_index)
		if not loop.is_empty():
			out.append(loop)
	_loops_cache = out
	return out


static func _storey_stops(floor_index: int) -> Array:
	"""
	One storey's candidate stops: the centre cell of every room it declares.

	@return: rows shaped `{letter, cell, point}`, in the `rooms` dict's own
	    iteration order — which is the order the plan is written in, and therefore
	    the order the rooms are laid out along the ring.

	THE CENTRE OF THE BBOX, not of the letter's cells. `plan_room_rect()` is the
	lookup every hand-built part of this building is already placed from, and on
	the shipped plans all 57 of those centres land on a route-open cell (measured
	2026-09-19).

	THE `_route_open` FILTER IS STRUCTURAL, not defensive, even though nothing
	fails it today. `plan_route()` seeds its BFS with the START cell WITHOUT asking
	whether that cell is open — so a stop on a wall, a stair lane or a shut gate
	could still route OUTWARD while nothing could route back to it, and
	reachability would stop being symmetric. `_storey_loop()` below leans on that
	symmetry to find the largest group in ~2n routes instead of n², so this filter
	is what makes that argument true rather than lucky. The first L-shaped or
	ring-shaped room somebody draws is when it starts mattering.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return []
	var rows: Array = plan["rows"]
	var out: Array = []
	for letter: String in plan["rooms"]:
		var rect := TowerInterior.plan_room_rect(floor_index, String(plan["rooms"][letter]))
		if rect.size == Vector2i.ZERO:
			continue
		var cell := rect.position + rect.size / 2
		if cell.y < 0 or cell.y >= rows.size():
			continue
		var line := String(rows[cell.y])
		if cell.x < 0 or cell.x >= line.length():
			continue
		if not TowerInterior._route_open(line[cell.x]):
			continue
		out.append({
			"letter": letter,
			"cell": cell,
			"point": Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
					TowerInterior.FLOOR_Y[floor_index],
					TowerInterior._grid_z(float(cell.y) + 0.5)),
		})
	return out


static func _storey_loop(floor_index: int) -> Dictionary:
	"""
	One storey's closed loop, or `{}` when its plan offers no round trip.

	THE LARGEST REACHABLE GROUP OF STOPS, IN PLAN ORDER, ROUTED PAIRWISE AND
	CLOSED. Two things in that sentence were measured rather than chosen:

	WHY A GROUP AND NOT "SKIP WHAT THE FIRST ROOM CANNOT REACH". Anchoring on the
	first room in the dict leaves STOREY 5 WITH NO STAFF AT ALL: its first room is
	`s5_boardroom`, which is behind the stair riddle's mass, so the router
	(correctly — `_route_open` refuses a `D`) reports every other room on the floor
	unreachable and the whole storey falls out. Which room a plan happens to list
	first is not a thing the owner authored, so it must not decide whether a storey
	is populated. Taking the largest group instead recovered 7 of 8 rooms there and
	5 of 7 on the cell block, and changed nothing on the other eight storeys.

	AND WHY THAT COSTS ~2n ROUTES AND NOT n². Because every stop is on a route-open
	cell (see `_storey_stops`), "A can reach B" is an EQUIVALENCE relation over the
	stops — a BFS over a fixed cell predicate is symmetric and transitive. So one
	route from a seed enumerates that seed's WHOLE group, and peeling groups off
	costs one route per stop rather than one per pair. On the twelve-room storey 4
	that is eleven BFS runs instead of sixty-six, and the whole table is ten
	storeys' worth, once per process, off a `const` grid.

	THE CLOSING LEG NEEDS NO SPECIAL CASE, for the same reason: every kept stop is
	in one equivalence class, so if the walk out routed, the walk home routes. A
	loop this function returns is CONTINUOUS by construction — there is no leg that
	was straight-lined because the plan offered no way, and a staffer therefore
	never walks through a wall. `tower_staff_selfcheck` asserts that off the built
	path rather than trusting this paragraph.
	"""
	var stops := _storey_stops(floor_index)
	if stops.size() < 2:
		return {}
	# Peel the stops into reachability groups, one route per stop.
	var group: Array = []
	var pending: Array = []
	for i in stops.size():
		pending.append(i)
	while not pending.is_empty():
		# `from` and not `seed`: `seed()` is a global function, and a local that
		# shadows it in a file whose whole claim is "nothing here is seeded" would
		# be the one word a reader stops on.
		var from: int = pending[0]
		var here: Array = [from]
		var rest: Array = []
		for j: int in pending.slice(1):
			if TowerInterior.plan_route(floor_index, stops[from]["point"],
					stops[j]["point"]).is_empty():
				rest.append(j)
			else:
				here.append(j)
		if here.size() > group.size():
			group = here
		pending = rest
	if group.size() < 2:
		return {}
	# ...and walk them in PLAN ORDER. `here` is built by scanning `pending` in
	# order and `pending` starts in plan order, so the group already is — sorted
	# anyway, because "the dict's own iteration order" is the contract and a future
	# peel that reordered would break it silently.
	group.sort()

	var path := PackedVector3Array()
	var arc := PackedFloat32Array()
	var letters: Array[String] = []
	path.append(stops[group[0]]["point"])
	arc.append(0.0)
	for k: int in group.size():
		letters.append(String(stops[group[k]]["letter"]))
		var to: Vector3 = stops[group[(k + 1) % group.size()]]["point"]
		var leg := TowerInterior.plan_route(floor_index, stops[group[k]]["point"], to)
		for point: Vector3 in leg:
			var last := path[path.size() - 1]
			# `plan_route` ends on the destination, whose cell centre the previous
			# leg's last waypoint already is — a zero-length step, dropped so the
			# arc table has no duplicate entry to divide by.
			if point.is_equal_approx(last):
				continue
			arc.append(arc[arc.size() - 1] + last.distance_to(point))
			path.append(point)
	var lap: float = arc[arc.size() - 1]
	# THE LAP DOES NOT REPEAT ITS OWN FIRST WAYPOINT. The closing leg ends ON the
	# first stop, so the raw walk finishes standing where it started — and left in,
	# that duplicate is a zero-length segment at the seam, which `_loop_pose()` can
	# park a staffer on and which makes the closed polyline's last step a step of
	# nothing. Dropped, with `lap` taken BEFORE the drop so the closing leg's length
	# is still in the total: the loop is `path[n-1] -> path[0]` and the distance
	# home is `lap - arc[n-1]`, which is what `_loop_pose()` reads.
	if path.size() > 2 and path[path.size() - 1].is_equal_approx(path[0]):
		path.remove_at(path.size() - 1)
		arc.remove_at(arc.size() - 1)
	if path.size() < 2 or lap <= 0.0:
		return {}
	return {
		"floor": floor_index,
		"stops": letters,
		"path": path,
		"arc": arc,
		"length": lap,
	}


static func _loop_pose(loop: Dictionary, distance: float) -> Array:
	"""
	Where a staffer stands and which way it faces, `distance` metres round a lap.

	@return: `[Vector3 interior-local position, float yaw, int segment index]`.

	The segment index is handed back so `tick()` can resume the scan from it: the
	walk is monotone, so following a body round a 370-waypoint loop is one compare
	a frame rather than a binary search, and the wrap resets it to zero.
	"""
	var arc: PackedFloat32Array = loop["arc"]
	var path: PackedVector3Array = loop["path"]
	var seg := 0
	while seg + 1 < arc.size() and arc[seg + 1] <= distance:
		seg += 1
	var from: Vector3 = path[seg]
	# The last waypoint closes onto the first — the lap is a loop, not a line.
	var to: Vector3 = path[(seg + 1) % path.size()]
	var span: float = (arc[seg + 1] if seg + 1 < arc.size() else float(loop["length"])) - arc[seg]
	var at: Vector3 = from if span <= 0.0 else from.lerp(to, clampf((distance - arc[seg]) / span, 0.0, 1.0))
	var heading := to - from
	# A yaw of 0 faces -Z for a body welded facing the viewer, which is what
	# `crowd_manager` writes and what `CityAgents.add_box`'s worked examples are
	# built to; the same `atan2(-x, -z)` therefore puts a staffer's face down its
	# own direction of travel.
	var yaw: float = atan2(-heading.x, -heading.z) if heading.length_squared() > 0.0 else 0.0
	return [at, yaw, seg]

# ============================================================================
# THE POPULATION — free everything and stand it back up
# ============================================================================

static func reset(interior: TowerInterior) -> void:
	"""
	Free every staffer and stand `STAFF_PER_STOREY` of them back on each loop.

	THE WHOLE PERSISTENCE CONTRACT, and like the guards' it is implemented by what
	is NOT here: nothing reads a save, nothing writes one and no staff state
	survives this call. "Structure persists; population resets" — one monotone
	union set (the opened gates, on the shell) plus this function and
	`TowerGuards.reset()`.

	IDEMPOTENT. Called from `_ready()` and again from `_on_tower_doorway` every
	time the local player crosses the door in either direction, exactly as the
	guards are, and the second call simply throws the first's nodes away.

	NO DEFERRAL, and that is the one thing that differs from `TowerGuards.reset()`.
	A guard is deferred because `set_confinement()` takes WORLD coordinates and the
	shell is still standing at the terrain's origin during `_ready()`. A staffer's
	transform is a MultiMesh instance under the interior, so it is interior-LOCAL
	by construction and there is no world-space question to get wrong.
	"""
	if is_instance_valid(interior._staff):
		# `remove_child` BEFORE `queue_free` — `TowerGuards.reset()`'s note: a queued
		# node keeps its name until the frame ends, so adding the replacement first
		# would hit a duplicate "Staff" and the ENGINE would rename the new one.
		var retired: Node3D = interior._staff
		interior.remove_child(retired)
		retired.queue_free()
	interior._staff = Node3D.new()
	interior._staff.name = "Staff"
	interior.add_child(interior._staff)
	interior._staff_walkers.clear()

	var table := loops()
	var per_archetype: Array[int] = [0, 0]
	for loop: Dictionary in table:
		for k: int in STAFF_PER_STOREY:
			# ALTERNATING, NOT DRAWN. Which coat a staffer wears is (storey, index)
			# parity — deterministic, free, and it puts both archetypes in the
			# building without a single call to an RNG this file is not allowed to
			# have.
			var archetype: int = (int(loop["floor"]) + k) % ARCHETYPE_COUNT
			interior._staff_walkers.append({
				"floor": int(loop["floor"]),
				"archetype": archetype,
				"loop": loop,
				# EVENLY SPACED ROUND THE LAP, so raising STAFF_PER_STOREY buys
				# more encounters rather than a conga line.
				"dist": float(loop["length"]) * float(k) / float(STAFF_PER_STOREY),
				"seg": 0,
				"slot": -1,
				"lod_debt": 0.0,
			})
			per_archetype[archetype] += 1

	for a: int in ARCHETYPE_COUNT:
		var node := MultiMeshInstance3D.new()
		node.name = "Staff%s" % ARCHETYPE_NAMES[a]
		node.material_override = shared_material()
		# Shadows off — the fauna/crowd precedent, and `TowerInterior._no_shadow`'s
		# rule for everything in this building.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_colors = false
		mesh.mesh = _archetype_mesh(a)
		mesh.instance_count = per_archetype[a]
		mesh.visible_instance_count = 0
		node.multimesh = mesh
		interior._staff.add_child(node)
	# Put them on their marks now, so a building nobody has ticked yet still has
	# its staff standing in it rather than stacked at the origin.
	tick(interior, 0.0)


static func tick(interior: TowerInterior, delta: float) -> void:
	"""
	Walk every staffer and push both MultiMeshes' transforms, once per frame.

	THE ONE `_process` FOR THE WHOLE BUILDING calls this — the interior's rule, and
	it is already skipped outright while the interior is not drawn, which is most
	of a run.

	TWO SEPARATE GATES, and they are not the same question:

	  * THE COARSE TICK (`AmbienceLod`) asks whether the CAMERA can see this
	    staffer, and answers with how long it should advance by. Out of view it
	    banks the time and spends the whole bank a few times a second, so an unseen
	    corridor keeps walking rather than freezing into statues — read that file's
	    header for why a freeze looks wrong. A null camera (headless, a standalone
	    scene) degrades to "everything visible", which is full rate.
	  * THE STOREY WINDOW asks whether this staffer's FLOOR is being drawn at all.
	    The interior hides every storey but the player's and its neighbours, and a
	    staffer is not a child of a storey container (one MultiMesh spans ten
	    floors, the dossier rack's problem exactly), so one on a hidden floor is
	    written OUT OF THE VISIBLE COUNT rather than left walking inside a slab.
	    `_drawn_floor < 0` means no frame has decided a window yet, and then
	    everything is drawn — `TowerDossiers.refresh()`'s degrade, verbatim.

	WRITTEN AS ONE `buffer` PER ARCHETYPE, never `set_instance_transform`. It is
	the crowd's rule for throughput, and in this building it is also a correctness
	one: the per-instance setter writes through to the RenderingServer and reads
	back from it, and under `--headless` — every self-check, all of CI — that is
	the dummy driver, so the write vanishes and the read answers identity.
	`buffer` round-trips on the resource. (`TowerDossiers.refresh()` found this.)
	"""
	# A HALF-BUILT `Staff` NODE IS NOT TICKED. `reset()` is the only thing that
	# creates the archetypes and it creates all of them, so this can only be a
	# building mid-teardown or one a future edit broke — and the standalone-degrade
	# rule this project runs on says answer nothing rather than fault. It is also
	# what keeps a mutation that drops an archetype failing on the self-check's
	# named assertion instead of on a null dereference three files away.
	if not is_instance_valid(interior._staff) \
			or interior._staff.get_child_count() < ARCHETYPE_COUNT:
		return
	var planes := AmbienceLod.view_planes(interior.get_viewport() if interior.is_inside_tree() else null)
	var window: bool = interior._drawn_floor >= 0 \
			and interior._drawn_floor < TowerInterior.FLOOR_Y.size()

	var buffers: Array[PackedFloat32Array] = []
	var counts: Array[int] = []
	for a: int in ARCHETYPE_COUNT:
		var node := interior._staff.get_child(a) as MultiMeshInstance3D
		var buf := PackedFloat32Array()
		buf.resize(node.multimesh.instance_count * 12)
		buffers.append(buf)
		counts.append(0)

	for walker: Dictionary in interior._staff_walkers:
		var loop: Dictionary = walker["loop"]
		var length: float = loop["length"]
		var pose := _loop_pose(loop, float(walker["dist"]))
		var at: Vector3 = pose[0]
		# The frustum test wants WORLD metres; everything else here is local.
		var seen := AmbienceLod.is_visible_at(planes, interior.global_position + at)
		var step: float = AmbienceLod.step_delta(walker, delta, seen)
		if step > 0.0:
			var moved: float = float(walker["dist"]) + WALK_SPEED * step
			# A lap is a lap: wrapping rather than clamping is what makes this a
			# LOOP, and `fposmod` is right however many laps one coarse tick covers.
			walker["dist"] = fposmod(moved, length)
			pose = _loop_pose(loop, float(walker["dist"]))
			at = pose[0]
		walker["seg"] = int(pose[2])

		# WHICH BUFFER SLOT THIS STAFFER LANDED IN, or -1 for one the window is not
		# drawing. `walkers()` reads the transform back out of the buffer through
		# it, so the seam the self-check measures is the one the ENGINE is handed
		# rather than the arithmetic that produced it — and it cannot drift out of
		# step with the gate below, because it is written by the gate.
		walker["slot"] = -1
		var drawn: bool = not window \
				or TowerInterior._floor_visible(int(walker["floor"]), interior._drawn_floor)
		if not drawn:
			continue
		var a: int = int(walker["archetype"])
		var idx: int = counts[a]
		if idx * 12 >= buffers[a].size():
			continue
		walker["slot"] = idx
		# The stride is a pure function of METRES WALKED — no per-instance animation
		# clock, so a staffer that spent the last second out of view comes back into
		# it mid-stride rather than resetting its feet.
		var phase: float = float(walker["dist"]) * STRIDE_FREQUENCY
		var basis := Basis().rotated(Vector3.UP, float(pose[1])) \
				.rotated(Vector3(0, 0, 1), sin(phase) * WALK_SWAY_AMOUNT) \
				.rotated(Vector3(1, 0, 0), sin(phase * 2.0) * WALK_PITCH_AMOUNT)
		var origin := at + Vector3(0.0, absf(sin(phase * 2.0)) * WALK_BOB_AMOUNT, 0.0)
		var base: int = idx * 12
		var buf: PackedFloat32Array = buffers[a]
		buf[base + 0] = basis.x.x
		buf[base + 1] = basis.y.x
		buf[base + 2] = basis.z.x
		buf[base + 3] = origin.x
		buf[base + 4] = basis.x.y
		buf[base + 5] = basis.y.y
		buf[base + 6] = basis.z.y
		buf[base + 7] = origin.y
		buf[base + 8] = basis.x.z
		buf[base + 9] = basis.y.z
		buf[base + 10] = basis.z.z
		buf[base + 11] = origin.z
		counts[a] = idx + 1

	for a: int in ARCHETYPE_COUNT:
		var node := interior._staff.get_child(a) as MultiMeshInstance3D
		node.multimesh.buffer = buffers[a]
		node.multimesh.visible_instance_count = counts[a]


static func walkers(interior: TowerInterior) -> Array:
	"""
	Every live staffer's storey, archetype and interior-LOCAL position.

	@return: a fresh Array of `{ "floor": int, "archetype": int, "position": Vector3 }`.

	The seam the self-check measures the population through, and it reads the
	MultiMesh BUFFER rather than the walker records — `TowerGuards.posts()`'s rule
	one step further. A record says where a staffer ought to be; the buffer is what
	the engine is actually handed, so a tick that computed a fine pose and wrote it
	into the wrong archetype's slot, or never pushed it, fails here instead of
	being reported as healthy by the arithmetic that produced it.
	"""
	var out: Array = []
	if not is_instance_valid(interior._staff):
		return out
	for walker: Dictionary in interior._staff_walkers:
		var slot: int = int(walker.get("slot", -1))
		if slot < 0:
			continue  # on a storey the window is not drawing this frame
		var node := interior._staff.get_child(int(walker["archetype"])) as MultiMeshInstance3D
		if node == null or slot >= node.multimesh.visible_instance_count:
			continue
		var buf: PackedFloat32Array = node.multimesh.buffer
		var base: int = slot * 12
		out.append({
			"floor": int(walker["floor"]),
			"archetype": int(walker["archetype"]),
			"position": Vector3(buf[base + 3], buf[base + 7], buf[base + 11]),
		})
	return out

# ============================================================================
# THE MESHES — `CityAgents.add_box`, and two palettes
# ============================================================================

static func _archetype_mesh(archetype: int) -> ArrayMesh:
	"""
	One archetype's welded body, built once per process and shared by every
	instance of it.

	`CityAgents.add_box()` is the welder both ambience managers build their
	composite meshes with and `crowd_manager._get_archetype_mesh()` is four worked
	humanoid examples; these two are that recipe with an office palette. Every box
	is welded at its BODY offset, feet at y = 0, so model-space `VERTEX.y` runs
	boots-to-hat over the whole figure — which is what `STAFF_MESH_TOP` and the
	material's `height_range` exist for.

	THIS FUNCTION IS THE UPGRADE SEAM the epic names: if the owner later wants
	staff skinned, everything above it — the loops, the walk, the draw budget, and
	.4's detection — is about a position and a facing and does not care.
	"""
	if _archetype_meshes[archetype] != null:
		return _archetype_meshes[archetype]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.91, 0.76, 0.66)
	if archetype == ARCHETYPE_SCIENTIST:
		# THE SCIENTIST (1.75 m): a white lab coat over dark trousers, a clipboard
		# under one arm and safety glasses. The coat is the read at corridor
		# distance — it is the brightest thing on the floor after the walls.
		var coat := Color(0.95, 0.96, 0.97)
		var trousers := Color(0.22, 0.24, 0.30)
		var shoes := Color(0.10, 0.10, 0.11)
		var hair := Color(0.26, 0.19, 0.14)
		var glasses := Color(0.30, 0.42, 0.50)
		var clipboard := Color(0.78, 0.62, 0.36)
		_box(st, Vector3(-0.13, 0.06, 0.02), Vector3(0.15, 0.12, 0.28), shoes)
		_box(st, Vector3(0.13, 0.06, 0.02), Vector3(0.15, 0.12, 0.28), shoes)
		_box(st, Vector3(-0.13, 0.44, 0.0), Vector3(0.16, 0.64, 0.18), trousers)
		_box(st, Vector3(0.13, 0.44, 0.0), Vector3(0.16, 0.64, 0.18), trousers)
		# The coat: a long torso box and a skirt that hangs past the hips, which is
		# the whole silhouette of the archetype.
		_box(st, Vector3(0.0, 0.86, 0.0), Vector3(0.44, 0.34, 0.24), coat)
		_box(st, Vector3(0.0, 1.18, 0.0), Vector3(0.46, 0.34, 0.26), coat)
		_box(st, Vector3(0.0, 1.19, -0.135), Vector3(0.04, 0.32, 0.02), trousers)  # the placket
		_box(st, Vector3(-0.28, 1.08, 0.0), Vector3(0.12, 0.54, 0.14), coat)
		_box(st, Vector3(0.28, 1.08, 0.0), Vector3(0.12, 0.54, 0.14), coat)
		_box(st, Vector3(-0.28, 0.78, 0.0), Vector3(0.10, 0.10, 0.12), skin)
		_box(st, Vector3(0.28, 0.78, 0.0), Vector3(0.10, 0.10, 0.12), skin)
		_box(st, Vector3(0.30, 0.92, -0.12), Vector3(0.03, 0.22, 0.17), clipboard)
		_box(st, Vector3(0.0, 1.40, 0.0), Vector3(0.14, 0.10, 0.14), skin)  # the neck
		_box(st, Vector3(0.0, 1.58, 0.0), Vector3(0.28, 0.28, 0.28), skin)
		_box(st, Vector3(0.0, 1.70, 0.0), Vector3(0.30, 0.10, 0.30), hair)
		_box(st, Vector3(0.0, 1.60, -0.145), Vector3(0.26, 0.06, 0.02), glasses)
	else:
		# THE ENGINEER (1.80 m to the crown of the hat): blue overalls over a grey
		# tee, a tool belt and a yellow hard hat. The hat is the read — it is the
		# one saturated warm colour in a building painted off-white.
		var overalls := Color(0.18, 0.32, 0.58)
		var tee := Color(0.72, 0.74, 0.76)
		var boots := Color(0.16, 0.13, 0.11)
		var helmet := Color(0.96, 0.76, 0.14)
		var belt := Color(0.34, 0.26, 0.18)
		var tool := Color(0.55, 0.57, 0.60)
		_box(st, Vector3(-0.14, 0.09, 0.02), Vector3(0.17, 0.18, 0.30), boots)
		_box(st, Vector3(0.14, 0.09, 0.02), Vector3(0.17, 0.18, 0.30), boots)
		_box(st, Vector3(-0.14, 0.46, 0.0), Vector3(0.18, 0.56, 0.20), overalls)
		_box(st, Vector3(0.14, 0.46, 0.0), Vector3(0.18, 0.56, 0.20), overalls)
		_box(st, Vector3(0.0, 0.80, 0.0), Vector3(0.48, 0.14, 0.28), belt)
		_box(st, Vector3(0.22, 0.76, -0.14), Vector3(0.07, 0.18, 0.05), tool)
		_box(st, Vector3(0.0, 1.06, 0.0), Vector3(0.48, 0.42, 0.28), overalls)
		# The bib's straps over the tee's shoulders — two stripes that say
		# "overalls" from behind, which is the angle you usually see one from.
		_box(st, Vector3(0.0, 1.34, 0.0), Vector3(0.44, 0.16, 0.26), tee)
		_box(st, Vector3(-0.14, 1.34, -0.115), Vector3(0.09, 0.18, 0.03), overalls)
		_box(st, Vector3(0.14, 1.34, -0.115), Vector3(0.09, 0.18, 0.03), overalls)
		_box(st, Vector3(-0.29, 1.14, 0.0), Vector3(0.12, 0.26, 0.15), tee)
		_box(st, Vector3(0.29, 1.14, 0.0), Vector3(0.12, 0.26, 0.15), tee)
		_box(st, Vector3(-0.29, 0.86, 0.0), Vector3(0.11, 0.32, 0.13), skin)
		_box(st, Vector3(0.29, 0.86, 0.0), Vector3(0.11, 0.32, 0.13), skin)
		_box(st, Vector3(0.0, 1.47, 0.0), Vector3(0.14, 0.10, 0.14), skin)
		_box(st, Vector3(0.0, 1.64, 0.0), Vector3(0.28, 0.26, 0.28), skin)
		_box(st, Vector3(0.0, 1.77, 0.0), Vector3(0.32, 0.12, 0.32), helmet)
		_box(st, Vector3(0.0, 1.72, -0.20), Vector3(0.30, 0.04, 0.10), helmet)  # the brim
	_archetype_meshes[archetype] = st.commit()
	return _archetype_meshes[archetype]


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	"""One-line forwarder to `CityAgents.add_box` — `crowd_manager._add_box`'s
	precedent, and what keeps the two archetypes above readable as tables."""
	CityAgents.add_box(st, center, size, col)
