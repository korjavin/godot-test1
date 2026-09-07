class_name FieldBridges
extends RefCounted
## ============================================================================
## THE FIELD BRIDGES — the road crosses a river ON something (bead godot-test1-06o.2)
## ============================================================================
## Lifted out of `endless_terrain.gd` whole by bd `godot-test1-ftn.28`, in the
## idiom the extractions before it settled (`terrain_props.gd`,
## `terrain_structures.gd`, `terrain_features.gd`, `terrain_biomes.gd`,
## `terrain_predators.gd`, `coin_road.gd`, `budapest_streamer.gd`): a `class_name`d
## library of STATIC functions that RECEIVES the terrain as its first argument
## and calls `terrain.chunk_to_world` / `terrain.world_to_chunk` / `terrain.create_box`
## back through the reference. `extends RefCounted` and everything `static`: this
## is a namespace, not a node.
##
## ----------------------------------------------------------------------------
## THE MEMOS STAYED ON THE TERRAIN, AND THAT IS THE DESIGN DECISION
## ----------------------------------------------------------------------------
## The four memo variables — `_field_bridge_cache`, `_field_bridge_wet_cache`,
## `_approach_bridge_cache`, and `_approach_bridge_scanned` — stay on the terrain,
## cleared by `_drop_seeded_memos()`. This is ONE function under the seed write
## clearing every seed-derived cache (bd bvq). A static library holds no run
## state, and the run's seed is the terrain's.
##
## What else stayed on the terrain:
##   * `@export var spawn_field_bridges` (a static library has no inspector).
##   * `_deep_channel_ford` (belongs to the wading section, calls
##     `field_bridge_surface_y` through the forwarder).
##
## Walking height of a field deck, metres. LOW on purpose: the ramps are
## FIELD_BRIDGE_TOP / TowerInterior.PLAN_RAMP_MAX_SLOPE long, so 1.6 m buys a
## 2.8 m approach at the shipped ceiling and the whole bridge stays inside the
## few stations either side of the water. A Budapest deck is at 12 m because
## ships pass under it; nothing passes under this one.
const FIELD_BRIDGE_TOP: float = 1.6

## Deck slab thickness (the box hangs UNDER the walking surface, the city's
## convention, so the ramp tops meet it flush).
const FIELD_BRIDGE_THICKNESS: float = 0.5

## HALF the deck's width. 8 m is wider than it needs to be to walk and narrower
## than every road clearance in play — the smallest is CHEST_ROAD_CLEARANCE
## (10.0, = road_width_max * 0.5), so no prop, chest, camp or landmark can ever
## be standing where a deck lands. field_bridge_selfcheck check 5 asserts that
## inequality against every *_ROAD_CLEARANCE const in this file rather than
## against a number typed here twice.
const FIELD_BRIDGE_HALF_WIDTH: float = 8.0

## The widest crossing that gets a bridge, in metres of centreline walked
## through the water. Past this it is not a river the road crosses, it is a LAKE
## the road runs into — a 300 m causeway would be a landmark nobody authored, so
## the road wades it, and the rivers epic's not-walkable bead owes that case an
## answer of its own (a ford, a detour, or a real crossing).
##
## 120, NOT THE 40 THE BEAD SKETCHED, and the difference is the GRAZING CROSSING.
## A band is ~8-25 m wide, so even a perpendicular crossing is only ~25 m of
## centreline — but the road's heading cap is 78 degrees, and a road running
## nearly ALONG a river walks 8 / cos(78 deg) = 38 m through the same 8 m of
## water, and the span is measured across the deck's whole WIDTH, which finds the
## water a station or two earlier at each bank. Those are the crossings a short
## cap throws away, and they are not lakes. Measured over
## field_bridge_selfcheck's sixteen seeds: at 80 m, 4 of 40 crossings went
## unbridged; at 120 m, one does — and that one is standing water.
const FIELD_BRIDGE_MAX_SPAN: float = 120.0

## How far past the last WET station the deck reaches, in stations. One station
## either side puts both abutments on dry ground with a whole station of margin,
## which is what makes "the ramp foot is dry" a property of the geometry rather
## than of the noise field's exact gradient at one point.
const FIELD_BRIDGE_DRY_STATIONS: int = 1

## Step used when probing the river band for the deck's width, metres. The probe
## is three lanes wide (the centreline and both parapets) so the deck covers the
## water at its EDGES too, not just under the walking line.
const FIELD_BRIDGE_PROBE_STEP: float = 1.0

## How far a ramp foot may be pushed back to get its whole WIDTH onto dry land
## (see _field_bridge_foot). Pushing lengthens the run at a fixed rise, so it can
## only make the ramp gentler; 30 m is far more bank than any measured crossing
## has needed, and check 4 prints the worst push it found.
const FIELD_BRIDGE_FOOT_PUSH_MAX: float = 30.0

## How far a deck may carry on PAST the water at deck height, at each end, to
## reach ground where its abutment's whole 16 m section is dry.
##
## It is not the span cap and it is not the push budget: a river that runs
## ALONGSIDE the road (seed 218 grazes one within 8 m for 186 m, seed 777001 for
## 150 m) leaves no dry section for a foot anywhere near the crossing, and the
## alternative to carrying on at 1.6 m is dragging a RAMP along the water — which
## is under WADE_SURFACE_MAX for its first 2.4 m, i.e. a hero wading on a bridge.
## 300 m covers every grazing stretch field_bridge_selfcheck has measured (the
## longest bank actually walked is ~110 m); past it the crossing is refused and
## the lake rule takes it. It is also the term that dominates
## _field_bridge_reach(), i.e. how many stations a cold window scan walks — 600
## here cost the first query of a run 33 ms, one whole frame-spike budget.
const FIELD_BRIDGE_BANK_WALK_MAX: float = 300.0

## Slop on a slab's own faces when asking whether a point stands on it. A
## millimetre: big enough that the exact edge of a slab answers "yes" whichever
## way the last bit of a dot product falls, small enough to be no geometry.
const EDGE_EPS: float = 0.001

## Slop added to the DERIVED slab stretch at a deck-to-deck joint (see
## _field_bridge_joint_ext, which computes half * tan(turn / 2) — the exact depth
## of the wedge a turn opens at the outer parapet).
##
## THE STRETCH IS ONLY EVER AT A DECK-TO-DECK JOINT, never where a slab meets a
## RAMP. A slab overhanging the head of a ramp is a step down onto it — and a
## step is the one thing CharacterBody3D cannot climb at all, so walking back up
## would be a jump gate outdoors, which is exactly what this bead exists to
## prevent. The ramp and the slab it meets are made COLINEAR instead, so that
## joint opens no wedge at all. field_bridge_selfcheck check 2 samples the wedge
## arc at every joint rather than trusting either half of this argument.
const FIELD_BRIDGE_SLAB_MARGIN: float = 0.05

## The private colour stream, CITY_STREAM_SEED's reason one feature along:
## create_box spends four draws per box on a colour ramp this builder overrides
## anyway, and a draw taken from a stream somebody else reads slides every
## crocodile in the world.
const FIELD_BRIDGE_STREAM_SEED: int = 0x0_6021

## Field decks are the same slate the city's ramps and pavements are cut from —
## one stone vocabulary outdoors, and a colour is not worth a hash stream.
const FIELD_BRIDGE_STONE := Color(0.58, 0.58, 0.60)

## THE TRIM (bead godot-test1-06o.4). Owner on the .2 screenshot, a flat grey
## deck angled across the water: "parapets/pylons" — a bare slab reads as a
## floating plate. So every field bridge is dressed in the CITY'S bridge
## vocabulary (_city_chain_bridge / _city_margaret_bridge are the reference:
## stone edge walls and a portal pair at the bank), scaled from a 12 m Danube
## deck to a 1.6 m field one, through the SAME create_box batch, the SAME centre
## rule and the SAME zero-RNG rule as the deck itself.
##
## THE PARAPET'S INNER FACE IS EXACTLY FIELD_BRIDGE_HALF_WIDTH, which is the
## whole of "it must not narrow the lane": the wall is CANTILEVERED off the deck
## edge rather than standing on it, so the walkable width, `field_bridge_surface_y`,
## every wet probe and every span measurement are byte-for-byte what they were
## and only boxes were added. It reaches DOWN past the deck's own underside too
## (hence the + FIELD_BRIDGE_THICKNESS on its height), which is what gives the
## slab a visible edge beam instead of a paper edge.
##
## It is the ONE colliding piece of trim — a rail you can walk through is not a
## rail — and 1.0 m is chest-high on a hero and far under the jump apex, so it
## fences the drop without fencing anybody in.
##
## KNOWN CEILING, measured (16 seeds, 458 bridge chunks): every spawner that
## drops something near a deck reads `field_bridge_surface_y`, which knows the
## 8 m walking rect and can never see trim — so at a RAMP FOOT, where the rail
## descends through coin and animal height, 3 road coins in 517 stood inside a
## parapet and 1 crocodile in ~450 spawned in one. Both are thin-wall cases that
## depenetration and a 0.6 m pickup sphere resolve, and the alternative is an
## `obstacles` footprint, which this feature is forbidden (it would push
## crocodiles off the road and make _settle_coin_y skip the deck's own coins).
const FIELD_BRIDGE_PARAPET_WIDTH: float = 0.5
const FIELD_BRIDGE_PARAPET_HEIGHT: float = 1.0

## The pylon pair at each bank — the portal the Chain Bridge puts at each end of
## its span, four boxes instead of ninety-two. They stand from the GROUND to
## FIELD_BRIDGE_TOP + rise, so a deck that used to hang in the air is visibly
## carried at both ends, and they straddle the parapet OUTBOARD of its centre
## line (see the builder) so nothing of them is ever over the lane.
##
## NOT FLUSH WITH THE PARAPET, and that is the whole of the offset: a pylon
## whose inner face shares the parapet's plane is two coincident opaque faces at
## every bank of every bridge, i.e. z-fighting on the one thing this bead exists
## to make look right. It is pushed out half a parapet so the two solids
## interpenetrate instead of touching.
##
## NON-COLLIDING, like every other piece of ornament in this game that nobody
## needs to climb: they cost the chunk body no shape, and a post at the very
## edge of a 16 m deck is scenery, not geometry.
##
## The width's real ceiling is `field_bridge_outer_reach()` against the tightest
## *_ROAD_CLEARANCE (check 5) — 2.0 m of headroom over the deck's half-width,
## not check 2's "a metre outside the parapet" control, which reads a box list
## FILTERED to the deck rect and can see no trim at all.
## SQUARE IN PLAN, and it was judged by eye: 0.9 x 1.6 read as a dark FIN
## standing on the deck rather than as a post.
const FIELD_BRIDGE_PYLON_WIDTH: float = 0.9
const FIELD_BRIDGE_PYLON_DEPTH: float = 0.9
const FIELD_BRIDGE_PYLON_RISE: float = 3.2

## Trim tones, FIELD_BRIDGE_STONE's neighbours and consts for its reason: a
## colour is not worth a hash stream, and three flat greys is what tells a
## parapet from a deck from a pylon at 100 m.
const FIELD_BRIDGE_PARAPET_STONE := Color(0.66, 0.65, 0.64)
const FIELD_BRIDGE_PYLON_STONE := Color(0.50, 0.50, 0.53)


static func _field_bridge_run() -> float:
	"""
	The horizontal RUN of one approach ramp, metres.

	Derived from the rise and the slope BUDAPEST'S OWN BRIDGES climb at, read out
	of BudapestPlan rather than restated: the city and the field have one ramp
	feel, and retuning the city's retunes this. The ceiling it must stay under is
	TowerInterior.PLAN_RAMP_MAX_SLOPE — "no traversal outdoors may demand a
	jump-height" is the tower's rule and the same one here — which
	field_bridge_selfcheck check 3 asserts off the built stone, so this derivation
	cannot quietly drift past it.
	"""
	return FIELD_BRIDGE_TOP * BudapestPlan.BRIDGE_RAMP_RUN / BudapestPlan.BRIDGE_DECK_TOP


static func field_bridge_outer_reach() -> float:
	"""
	How far from the walking line ANY of a bridge's stone reaches — the deck's
	half-width plus the widest piece of trim standing outboard of it.

	The number check 5 measures against every *_ROAD_CLEARANCE in this file, and
	it is a DERIVATION rather than FIELD_BRIDGE_HALF_WIDTH read a second time:
	the parapet and the pylons are cantilevered off the deck edge (see the trim
	const block), so the stone now reaches further than the lane does and the
	"no prop can ever stand on a deck" contract is about the stone.
	"""
	return FIELD_BRIDGE_HALF_WIDTH + maxf(FIELD_BRIDGE_PARAPET_WIDTH,
			FIELD_BRIDGE_PARAPET_WIDTH * 0.5 + FIELD_BRIDGE_PYLON_WIDTH)


static func _field_bridge_reach(terrain: Node3D) -> float:
	"""
	How far in X a bridge's stone can reach from its anchor station — the pad
	every X-window scan in this section widens by, spawn_coins_in_chunk's `pad`
	one feature along.

	The span is capped at FIELD_BRIDGE_MAX_SPAN of CENTRELINE (and X advances no
	faster than the centreline does), plus the dry stations either end, plus a
	ramp at each end, plus the slab stretch. Deliberately a loose upper bound: it
	costs a few stations of scanning and it is what makes "no chunk misses a piece
	of a bridge that reaches into it" true by arithmetic.
	"""
	# ONE bank walk and ONE ramp, not two of each: this is how far the stone
	# reaches from its anchor IN ONE DIRECTION, and the scan pads BOTH sides by
	# it. Doubling them made the window 2.9 km wide and the first cold query of a
	# run 33 ms — one frame's whole spike budget, spent walking stations whose
	# decks could never touch the chunk being built.
	return FIELD_BRIDGE_MAX_SPAN \
			+ float(2 * FIELD_BRIDGE_DRY_STATIONS + 2) * terrain._road_spacing() \
			+ _field_bridge_run() + FIELD_BRIDGE_FOOT_PUSH_MAX \
			+ 2.0 * FIELD_BRIDGE_HALF_WIDTH \
			+ FIELD_BRIDGE_BANK_WALK_MAX


static func _field_bridge_dry_across(terrain: Node3D, centre: Vector2, dir: Vector2) -> bool:
	"""
	Is a deck-wide cross-section at `centre` DRY ALL THE WAY ACROSS?

	@param centre: The centreline point, world XZ.
	@param dir: The direction the deck runs in (unit); the section is measured
	            perpendicular to it.
	@return: false the moment any sample of the section stands in a river band.

	THE WHOLE WIDTH, NOT THREE LANES. A river is a contour crossed at an angle, so
	its edge is at a different place on the deck's north side than on its south —
	and a section is 16 m wide. Sampling the centre and the two parapets passed a
	foot with a wet patch 0.5 m inside one edge (seed 12, anchor 122), which is a
	flank a player wades up: the band under a foot slab has no deck over it, so
	the Y-aware wade never sees stone. FIELD_BRIDGE_PROBE_STEP samples, both edges
	included.

	ONE PRIMITIVE, TWO CALLERS — the span walk (is the road in the water here) and
	the abutment probe (is this foot on the bank) are the same question about the
	same rectangle, and they disagreed once. No allocation and no RNG draw: this
	decides WHERE a bridge is, and a single draw would slide every crocodile in
	the world.
	"""
	var perp := Vector2(-dir.y, dir.x)
	var lane := -FIELD_BRIDGE_HALF_WIDTH
	while lane < FIELD_BRIDGE_HALF_WIDTH + FIELD_BRIDGE_PROBE_STEP * 0.5:
		var at := centre + perp * minf(lane, FIELD_BRIDGE_HALF_WIDTH)
		if terrain.is_river_at(Vector3(at.x, 0.0, at.y)):
			return false
		lane += FIELD_BRIDGE_PROBE_STEP
	return true


static func _field_bridge_wet(terrain: Node3D, k: int) -> bool:
	"""
	Is the road IN THE WATER at station `k` — on the CENTRELINE, over the stretch
	of it this station owns?

	@param k: Station index; the cache must already cover it (k-1 and k+1 too).
	@return: true when any centreline sample between the midpoints either side of
	         station `k` stands in a river band.

	THE CENTRELINE, NOT THE WIDTH, AND THAT IS THE WHOLE SPAN RULE. Wading is
	decided where the HERO is, which is the centreline; the 16 m section is about
	where the deck's FEET may stand and belongs to `_field_bridge_foot` alone. A
	span measured on the section counts a road that merely runs ALONGSIDE a river
	as being in it: on seed 218 the road grazes one within 8 m for 186 m, which
	turned an ordinary 18 m crossing into a "lake" and left it unbridged, and on
	seed 777001 a 150 m section-run swallowed two real crossings of 17.5 m and
	65 m. Both are the deep strip bead godot-test1-06o.3 makes impassable.

	IT SAMPLES THE STRETCH, NOT THE POINT, for the corridor scan's reason one
	table along: a station is ~6 m of road and a river band can be narrower, so
	asking only at the station centre steps over one. The window is half a
	station either side, so consecutive stations tile the centreline with no gap
	and no overlap.

	No allocation and no RNG draw: this decides WHERE a bridge is, and a single
	draw would slide every crocodile in the world.
	"""
	return _field_bridge_wet_metres(terrain, k) > 0.0


static func _field_bridge_wet_metres(terrain: Node3D, k: int) -> float:
	"""
	How many metres of the CENTRELINE this station owns are in the water.

	@param k: Station index; the cache must already cover k-1 and k+1.
	@return: The wet length inside the window between the midpoints either side
	         of station `k`, sampled at FIELD_BRIDGE_PROBE_STEP.

	IT IS A LENGTH, NOT A FLAG, because the span cap is a length: adding up
	distances between wet station CENTRES omits the entry station's own share and
	both partial intervals at the banks, which on seed 296 totalled 120.0 m for a
	124.5 m crossing and bridged past the cap. The flag above is this answer
	compared to zero, so the two can never disagree about where the water is.

	MEMOIZED per station, and it is the hot path of the whole feature: every
	station in a scan window is asked as `k` and again as `k - 1`, and the growth
	loops ask it again. `_drop_seeded_memos()` drops it with the bridges it feeds.
	"""
	if terrain._field_bridge_wet_cache.has(k):
		return terrain._field_bridge_wet_cache[k]
	var centre: Vector2 = terrain._road_station(k).center
	var back: Vector2 = (terrain._road_station(k - 1).center + centre) * 0.5 \
			if k - 1 >= terrain.road_k_min else centre
	var fwd: Vector2 = (terrain._road_station(k + 1).center + centre) * 0.5 \
			if k + 1 <= terrain.road_k_max else centre
	var wet := _centreline_wet_metres(terrain, back, fwd)
	terrain._field_bridge_wet_cache[k] = wet
	return wet


static func _field_bridge_out_dir(terrain: Node3D, k: int, sign: int) -> Vector2:
	"""
	The unit direction a ramp at deck end `k` runs AWAY from the deck in —
	westward for `sign` -1, eastward for +1.

	IT IS THE CONTINUATION OF THE LAST DECK SEGMENT, not the next station's
	bearing, because that is the direction `_field_bridge_row_from` gives the
	foot: a ramp colinear with the slab it meets leaves no wedge at the parapet.
	Testing the growth along the road's NEXT segment instead measures a ramp
	nobody builds, and where the road turns the two disagree enough to refuse a
	crossing that would have been fine (seed 777001, station 71).
	"""
	var here: Vector2 = terrain._road_station(k).center
	var inward: Vector2 = terrain._road_station(k - sign).center
	return (here - inward).normalized()


static func _field_bridge_ramp_dry(terrain: Node3D, head: Vector2, foot: Vector2) -> bool:
	"""
	Is the whole RAMP RECTANGLE — every deck-wide section from the deck's end
	`head` down to `foot` — clear of the water?

	The abutment's real question, and the growth loop's too: a ramp that lands on
	a dry section but crosses a shallow on the way is a stretch of bridge under
	WADE_SURFACE_MAX with water beside it, which a hero on the parapet wades.
	"""
	var run := head.distance_to(foot)
	if run <= 0.0:
		return _field_bridge_dry_across(terrain, head, Vector2.RIGHT)
	var dir := (foot - head) / run
	var steps := int(run / FIELD_BRIDGE_PROBE_STEP)
	for i in range(steps + 1):
		if not _field_bridge_dry_across(terrain, head + dir * minf(
				float(i) * FIELD_BRIDGE_PROBE_STEP, run), dir):
			return false
	return _field_bridge_dry_across(terrain, foot, dir)


static func _field_bridge_section_dry(terrain: Node3D, k: int) -> bool:
	"""Is a deck-wide section across station `k` dry all the way across? The
	abutment's question (see _field_bridge_dry_across), asked of a station."""
	var st: Dictionary = terrain._road_station(k)
	var heading: float = st.heading
	return _field_bridge_dry_across(terrain, st.center, Vector2(cos(heading), sin(heading)))


static func _centreline_wet_metres(terrain: Node3D, from: Vector2, to: Vector2) -> float:
	"""
	How many metres of this centreline segment are in a river band, sampled at
	FIELD_BRIDGE_PROBE_STEP.

	EACH SAMPLE OWNS THE INTERVAL AHEAD OF IT, never the interval AND the
	end-point: charging `steps + 1` samples a full step each reports `span +
	step` for a fully wet segment, and summed over a crossing's stations that
	overcounted seed 19's 115.8 m of water as 139.7 m and refused the bridge as a
	lake under a 120 m cap. So a fully wet segment contributes exactly `span`.

	The far end-point belongs to the NEXT segment's first sample — consecutive
	station windows tile the centreline (see _field_bridge_wet_metres), so no
	metre is counted twice and none is missed.

	The one home of "the road is in the water HERE", shared by the station walk,
	the approach corridor's and the span cap.
	"""
	var span := from.distance_to(to)
	var steps := int(span / FIELD_BRIDGE_PROBE_STEP)
	if steps < 1:
		# Shorter than one probe step: one sample, and it owns what there is.
		return span if terrain.is_river_at(Vector3(from.x, 0.0, from.y)) else 0.0
	var step_len: float = span / float(steps)
	var wet := 0.0
	for i in range(steps):
		var at: Vector2 = from.lerp(to, float(i) / float(steps))
		if terrain.is_river_at(Vector3(at.x, 0.0, at.y)):
			wet += step_len
	return wet


static func _field_bridge_foot(terrain: Node3D, head: Vector2, out_dir: Vector2) -> Vector2:
	"""
	Where one ramp's FOOT stands: back along `out_dir` from the deck's end, far
	enough that the whole width of the abutment is on dry land.

	@param head: The deck end this ramp climbs to (a station centre).
	@param out_dir: Unit vector pointing AWAY from the deck, along the ramp.
	@return: The foot point, world XZ — or `Vector2.INF` when no dry foot exists
	         inside the push budget, which REFUSES the whole bridge.

	THE CENTRELINE IS NOT THE ABUTMENT. The foot is a 16 m wide slab at y = 0, so
	a corner of it can stand in the river while its centre is dry — and a player
	walking up that side keeps wading until the ramp has risen past
	WADE_SURFACE_MAX, which is the whole bridge undone on one flank (measured:
	seed 12, station 116, the east foot's north corner). So both corners are
	PROBED, and the foot is pushed further out until they are dry.

	PUSHING IS FREE AND CANNOT BREAK THE SLOPE: the rise is fixed at
	FIELD_BRIDGE_TOP, so a longer run is a GENTLER ramp, always further under
	TowerInterior.PLAN_RAMP_MAX_SLOPE than the base run already is.

	# ponytail: a bank still wet 30 m back is refused rather than merged with the
	# crossing next door. Merging is the richer answer (two spans and one long
	# deck between them) and it is a bead of its own; refusing keeps the promise
	# this file makes — every bridge it builds is standing on dry ground at both
	# ends — and field_bridge_selfcheck counts the refusals.
	"""
	var run := _field_bridge_run()
	var pushed := 0.0
	while pushed <= FIELD_BRIDGE_FOOT_PUSH_MAX:
		var foot := head + out_dir * (run + pushed)
		# THE WHOLE RAMP RECTANGLE, not the foot's section and the centreline. A
		# ramp is under WADE_SURFACE_MAX for its first 2.4 m and it is 16 m wide,
		# so a hero hugging its parapet over a bank shallow wades on a bridge —
		# measured on six seeds, ~1-3 m of one edge each. The rectangle is every
		# section from the deck's end down to the foot.
		if _field_bridge_ramp_dry(terrain, head, foot):
			return foot
		pushed += FIELD_BRIDGE_PROBE_STEP
	# NEVER A KNOWN-WET FOOT. Out of budget the honest answer is that this bank
	# cannot carry an abutment, so the CROSSING is refused and the lake rule takes
	# it (the road wades, and bead godot-test1-06o.3 owes the case an answer) —
	# returning the last point tried would plant a 16 m slab in the river and call
	# it a bridge, which is worse than no bridge because it looks like one.
	return Vector2.INF


static func _field_bridge_joint_ext(dir_a: Vector2, dir_b: Vector2, half: float) -> float:
	"""
	How far each slab must be stretched past a deck-to-deck joint to close the
	wedge of open air the turn opens at the outer parapet.

	@param dir_a, dir_b: The two slabs' unit directions, in order.
	@param half: Half the deck's width.
	@return: The stretch, metres — zero for a straight joint.

	DERIVED, NEVER A CONSTANT, and the constant is why: two rectangles meeting at
	an angle `d` leave a triangle at the outer edge whose depth is
	half * tan(d / 2), and the road's per-station turn is NOT bounded by
	`road_turn_rate_deg` — the recurrence also restores the heading toward +X by
	ROAD_RESTORE, so a station leaving the heading cap can turn further than the
	noise alone allows (measured: a 22.4 degree joint wanting 1.585 m against a
	fixed 1.5). A shipped fixed stretch is one retune of the turn rate away from
	being wrong again, so this is the arithmetic and not a number.

	The margin is EDGE_EPS's cousin: a hair over the exact depth, because the two
	rectangles meet the wedge along its own edges and floating point decides which
	side of them a sample lands on.
	"""
	var dot := clampf(dir_a.dot(dir_b), -1.0, 1.0)
	var turn := acos(dot)
	if turn <= 0.0:
		return 0.0
	return half * tan(turn * 0.5) + FIELD_BRIDGE_SLAB_MARGIN


static func _field_bridge_slabs(row: Dictionary) -> Array:
	"""
	THE SLABS OF ONE BRIDGE — the single description of what the stone is, read
	by the builder that emits it AND by the surface query that answers where you
	can stand.

	@param row: A field_bridge_at() row.
	@return: One entry per slab, in order:
	           "start" / "dir" / "len"   the slab's axis in world XZ (its own
	                                     length, the stretch included)
	           "y_a" / "y_b"             the walking height at each end
	           "half"                    half its width

	ONE TABLE, TWO READERS, and it exists because the two disagreed. The query
	used to be a point-to-POLYLINE distance, which describes a CAPSULE: at a
	joint on the outside of a turn, a point can be within half a deck of the line
	and outside every rectangle the builder actually emitted. `spawn_coins_in_chunk`
	then stood a coin at deck height over open air (seed 26, station 34). A
	rectangle is what is built, so a rectangle is what is asked.

	The heights are the INDEX, not a re-derivation from the profile: the polyline
	is (west ramp foot, every deck station, east ramp foot) by construction, so
	the two end points are at 0 and everything between them is at deck height —
	which also lets the two ramps have DIFFERENT runs (see _field_bridge_foot)
	with no second profile to keep in step.
	"""
	if row.has("slabs"):
		return row["slabs"]   # the row is memoized, so this is once per bridge
	var poly: PackedVector2Array = row["poly"]
	var half: float = row["half"]
	var last := poly.size() - 2   # index of the LAST segment
	var out: Array = []
	for i in range(poly.size() - 1):
		var y_a := 0.0 if i == 0 else FIELD_BRIDGE_TOP
		var y_b := 0.0 if i == last else FIELD_BRIDGE_TOP
		var a: Vector2 = poly[i]
		var seg: Vector2 = poly[i + 1] - a
		# The slab stretch, at deck-to-deck joints ONLY — BOTH ends of it have to
		# be deck. A slab overhanging the head of a ramp is a step you cannot walk
		# back up (see _field_bridge_joint_ext), and stretching the RAMP itself
		# is worse: its top surface is a plane through its two ends, so a longer
		# box at the same heights lifts the whole surface off the profile.
		var deck := i >= 1 and i <= last - 1
		var dir := seg.normalized()
		var ext_a := 0.0
		var ext_b := 0.0
		if deck and i >= 2:
			ext_a = _field_bridge_joint_ext(
					(poly[i] - poly[i - 1]).normalized(), dir, half)
		if deck and i <= last - 2:
			ext_b = _field_bridge_joint_ext(
					dir, (poly[i + 2] - poly[i + 1]).normalized(), half)
		out.append({
			"start": a - dir * ext_a, "dir": dir,
			"len": seg.length() + ext_a + ext_b,
			"y_a": y_a, "y_b": y_b, "half": half,
		})
	row["slabs"] = out
	return out


static func _field_bridge_rail_line(poly: PackedVector2Array, offset: float) -> PackedVector2Array:
	"""
	The walking line offset sideways by `offset` metres, MITRED at every joint —
	the line a parapet's boxes are centred on.

	@param offset: SIGNED lateral offset. The normal is (dir.y, -dir.x), which is
	               the box's own local +X (see spawn_field_bridges_in_chunk).
	@return: One point per point of `poly`, so segment `i` of the result is the
	         rail beside slab `i`.

	A MITRE, NOT ONE OFFSET RECTANGLE PER SLAB, and the difference is the lane.
	A rectangle offset from its own segment stops at the joint's projection, and
	on the INSIDE of a turn that corner lands `offset * cos(turn)` from the NEXT
	segment's line — 7.63 m from a line whose deck reaches 8.0 at the road's
	measured 22.4 degree worst joint, i.e. a rail poking a third of a metre into
	the lane the deck promises (field_bridge_selfcheck check 11 catches exactly
	that). The mitre point lies on BOTH offset lines by construction, so no part
	of the rail is ever nearer the walking line than `offset` — and the OUTER
	corner closes with no wedge for free, which is why the parapet needs no slab
	stretch of its own (_field_bridge_joint_ext stays the deck's).
	"""
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var d_in: Vector2 = (poly[i] - poly[i - 1]).normalized() if i > 0 \
				else (poly[1] - poly[0]).normalized()
		var d_out: Vector2 = (poly[i + 1] - poly[i]).normalized() if i < n - 1 \
				else d_in
		var bis := (Vector2(d_in.y, -d_in.x) + Vector2(d_out.y, -d_out.x)).normalized()
		# Scale the bisector so its projection on either normal is exactly
		# `offset`. Floored because a hairpin sends the mitre to infinity, and
		# the floor is NOT a graceful cap: under it the rail lands at
		# 2 * offset * proj, i.e. INSIDE the lane, which is the very thing this
		# function exists to prevent. It is unreachable on this road — proj is
		# cos(turn / 2) and needs a 120 degree joint against a measured worst of
		# 22.41 (minimum proj over 45 bridges: 0.9809) — so it is a guard against
		# a division, not a supported case. Widen the turn cap and this needs a
		# real answer.
		var proj := maxf(bis.dot(Vector2(d_out.y, -d_out.x)), 0.5)
		out.append(poly[i] + bis * (offset / proj))
	return out


static func field_bridge_at(terrain: Node3D, k0: int) -> Dictionary:
	"""
	THE BRIDGE ANCHORED AT STATION `k0`, or {} when there is none.

	@param k0: Station index. A bridge exists here only when `k0` is a CROSSING
	           ENTRY — wet at `k0`, dry at `k0 - 1` — which is what makes "one
	           bridge per crossing" a definition rather than a de-duplication
	           pass over overlapping candidates.
	@return: {} or a row:
	           "k0" / "k1"   first and last wet station
	           "poly"        the walking line as world XZ points: the west ramp
	                         foot, every deck station, the east ramp foot
	           "along"       cumulative distance along `poly`, same length
	           "half"        half the deck width
	           "run"         the ramp run, so a reader need not re-derive it

	MEMOIZED, because every chunk within a bridge's reach re-asks this and the
	answer is a pure function of (k0, run_seed) through the road cache and the
	river field. `_drop_seeded_memos()` clears it beside the station cache it is
	derived from.

	THE CAP IS A LAKE, NOT A LONGER BRIDGE. Past FIELD_BRIDGE_MAX_SPAN of wet
	centreline the road is not crossing a river, it is running into standing
	water, and a 200 m slab there would be a landmark nobody authored. It wades —
	and the rivers epic's not-walkable bead owes that case an answer of its own.
	"""
	if terrain._field_bridge_cache.has(k0):
		return terrain._field_bridge_cache[k0]

	var empty: Dictionary = {}
	var terminal: int = terrain._road_terminal_k()
	# CAP 5 — the road's consumers stop at the terminal station (bead
	# godot-test1-8gw.3). East of T the route is the city's authored approach
	# corridor and then Budapest itself, whose four bridges are authored over an
	# authored Danube; a seeded field deck in there would be a fifth bridge across
	# the Danube that no plan, no landmark slot and no map knows about.
	if k0 > terminal:
		terrain._field_bridge_cache[k0] = empty
		return empty
	# NOT MEMOIZED, and that distinction is the whole determinism of this table.
	# "The station cache does not reach far enough to answer yet" is a fact about
	# THIS MOMENT, not about the world: remember it and the first chunk to ask
	# early would delete a bridge for the rest of the run, and which chunk asks
	# first is the order the player walked in. Every answer below IS about the
	# world (the road's centreline and the river field, both pure in the seed),
	# so every answer below is remembered.
	if k0 - FIELD_BRIDGE_DRY_STATIONS - 1 < terrain.road_k_min:
		return empty
	# The crossing ENTRY test. Dry behind, wet here.
	if _field_bridge_wet(terrain, k0 - 1) or not _field_bridge_wet(terrain, k0):
		terrain._field_bridge_cache[k0] = empty
		return empty

	# Walk forward to the far bank, ACCUMULATING THE METRES WALKED — never the
	# chord back to the first wet station, which a curved wet run makes shorter
	# than the road really is (measured on seed 72: 84 m walked reading as a
	# 79.2 m chord, so a crossing over the cap was bridged anyway). The cap is
	# metres of water, and a station budget would be one `road_coin_spacing`
	# retune away from meaning something else.
	var k1 := k0
	# THE ENTRY STATION'S OWN WATER COUNTS. `walked` used to start at zero and add
	# only the distances between subsequent wet station CENTRES, which drops the
	# entry's share and both partial intervals at the banks — seed 296's 124.5 m
	# crossing totalled 119.99996 and was bridged as if it were inside the 120 m
	# cap. Every station contributes the wet METRES of the stretch it owns, and
	# consecutive stations tile the centreline, so the sum is the crossing.
	var walked := _field_bridge_wet_metres(terrain, k0)
	while true:
		var next := k1 + 1
		if next + FIELD_BRIDGE_DRY_STATIONS > terminal:
			# The far bank is past the road's last station: no bridge, and that
			# IS about the world, so it is remembered.
			terrain._field_bridge_cache[k0] = empty
			return empty
		if next + FIELD_BRIDGE_DRY_STATIONS > terrain.road_k_max:
			# ...whereas a cache that has not grown that far yet is a fact about
			# this moment — see the un-memoized return above.
			return empty
		if not _field_bridge_wet(terrain, next):
			break
		walked += _field_bridge_wet_metres(terrain, next)
		if walked > FIELD_BRIDGE_MAX_SPAN:
			terrain._field_bridge_cache[k0] = empty   # a lake, see above
			return empty
		k1 = next

	# The deck's stations: every wet one plus FIELD_BRIDGE_DRY_STATIONS of dry
	# ground at each end, so both abutments stand on land with a whole station of
	# margin rather than on the noise field's exact zero crossing...
	var west_k := k0 - FIELD_BRIDGE_DRY_STATIONS
	var east_k := k1 + FIELD_BRIDGE_DRY_STATIONS
	# ...and then further out, at DECK HEIGHT, until the SECTION at each end is
	# dry across its width. THE DECK GROWS, THE RAMP DOES NOT: a river that runs
	# alongside the road for a while (seed 777001 grazes one within 8 m for 150 m)
	# leaves no dry 16 m section for an abutment anywhere near the crossing, and
	# pushing the FOOT out there only drags a ramp — which is under
	# WADE_SURFACE_MAX for its first 2.4 m — along the water. Carrying on at 1.6 m
	# and coming down where the bank is dry is the same stone in the right order.
	# Bounded by FIELD_BRIDGE_MAX_SPAN at each end — the same ceiling the water
	# itself gets, because this growth is the deck following a river bank and a
	# bank is exactly as long as the crossing next to it.
	#
	# THE CACHE IS EXTENDED FIRST, AND THE LOOPS DO NOT READ ITS EDGE. This
	# answer is memoized for the run, so a loop that stopped at whatever the
	# station cache happened to hold would make the BRIDGE SET a function of the
	# order the player walked the chunks in — measured: seed 409 built six
	# bridges ascending and five descending, and in a room two peers would lay
	# different decks over the same water. The k1 walk above returns UN-memoized
	# when the cache is short for exactly this reason; the growth cannot, because
	# it may legitimately want stations 260 m out, so it makes sure they exist.
	var reach_x := FIELD_BRIDGE_BANK_WALK_MAX + FIELD_BRIDGE_FOOT_PUSH_MAX \
			+ 2.0 * _field_bridge_run()
	terrain._road_extend_to_x(terrain._road_station(west_k).center.x - reach_x,
			terrain._road_station(east_k).center.x + reach_x)
	var grown := 0.0
	while grown < FIELD_BRIDGE_BANK_WALK_MAX and not _field_bridge_ramp_dry(
			terrain,
			terrain._road_station(west_k).center,
			terrain._road_station(west_k).center + _field_bridge_out_dir(terrain, west_k, -1)
					* _field_bridge_run()):
		grown += terrain._road_station(west_k).center.distance_to(
			terrain._road_station(west_k - 1).center)
		west_k -= 1
	grown = 0.0
	while east_k + 1 < terminal and grown < FIELD_BRIDGE_BANK_WALK_MAX \
			and not _field_bridge_ramp_dry(
					terrain,
					terrain._road_station(east_k).center,
					terrain._road_station(east_k).center
							+ _field_bridge_out_dir(terrain, east_k, 1) * _field_bridge_run()):
		grown += terrain._road_station(east_k).center.distance_to(
			terrain._road_station(east_k + 1).center)
		east_k += 1
	var pts := PackedVector2Array()
	for k in range(west_k, east_k + 1):
		pts.append(terrain._road_station(k).center)

	# ONE ANCHOR OWNS A DECK. Two crossings on the same bank both grow outward to
	# the same dry ground and produce the SAME row under two anchors — and then
	# every chunk emits every slab twice: double the boxes, double the collision
	# shapes, and a full-length z-fight (7 of 78 seeds, one of them three times
	# over). The WESTERN entry wins, so the rule is: if an earlier entry's deck
	# already covers this crossing, this anchor has nothing to build.
	#
	# It terminates because it only ever looks WEST, and it is cheap because
	# field_bridge_at is memoized — the neighbour it asks was built by the same
	# window scan a moment ago.
	var look := west_k
	while look < k0:
		var earlier: Dictionary = field_bridge_at(terrain, look)
		look += 1
		if earlier.is_empty():
			continue
		if _field_bridge_surface_on(terrain, earlier,
				Vector3(terrain._road_station(k0).center.x, 0.0,
						terrain._road_station(k0).center.y)) > -INF:
			terrain._field_bridge_cache[k0] = empty
			return empty

	var row := _field_bridge_row_from(terrain, pts)
	if not row.is_empty():
		row["k0"] = k0
		row["k1"] = k1
	terrain._field_bridge_cache[k0] = row
	return row


static func _field_bridge_row_from(terrain: Node3D, pts: PackedVector2Array) -> Dictionary:
	"""
	One bridge's geometry from the centreline points its deck stands on.

	@param pts: The deck's own centre points, west to east, the DRY margin point
	            at each end included. At least three.
	@return: The row (see field_bridge_at), or {} when either abutment cannot be
	         put on dry ground — which refuses the whole crossing.

	SHARED BY THE TWO SOURCES OF A CENTRELINE: the seeded road's stations, and the
	AUTHORED approach corridor from the terminal station to Budapest's gate. The
	corridor is not station-indexed and has no `k`, but it is the same walk over
	the same water, and a second copy of the feet-and-profile arithmetic is how
	the two would drift apart.

	The two ramp feet are measured back along the FIRST and forward along the LAST
	deck segment's own direction — colinear rather than tangent-derived, so the
	ramp and the slab it meets share a heading and there is no wedge of open air
	at that joint (which is the one joint the slab stretch is forbidden to cover;
	see _field_bridge_joint_ext).
	"""
	if pts.size() < 3:
		return {}
	var head := (pts[1] - pts[0]).normalized()
	var tail := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var west := _field_bridge_foot(terrain, pts[0], -head)
	var east := _field_bridge_foot(terrain, pts[pts.size() - 1], tail)
	if west == Vector2.INF or east == Vector2.INF:
		return {}   # no dry bank for an abutment — see _field_bridge_foot

	var poly := PackedVector2Array()
	poly.append(west)
	poly.append_array(pts)
	poly.append(east)

	var along := PackedFloat32Array()
	along.append(0.0)
	for i in range(1, poly.size()):
		along.append(along[i - 1] + poly[i].distance_to(poly[i - 1]))

	return { "poly": poly, "along": along, "half": FIELD_BRIDGE_HALF_WIDTH }


static func approach_bridges(terrain: Node3D) -> Array:
	"""
	The bridges on the APPROACH CORRIDOR — the authored line from the road's
	terminal station `T` through Budapest's gate (bead godot-test1-06o.2, round 3).

	@return: Rows in the shape field_bridge_at() returns, west to east. Memoized
	         for the run beside the road's own bridges.

	WHY THE CORRIDOR NEEDS ITS OWN SCAN AND IS NOT AN OVERSIGHT TWICE. The road's
	crossings are found by walking STATIONS, and the road's consumers stop at `T`
	(cap 5) — but the player does not: from `T` the route is
	BudapestPlan.road_approach_point(), ~150 m of authored corridor that
	`spawn_approach_coins_in_chunk` lays a coin line along. That corridor has no
	stations, and the city's river override only starts at the rect's west edge
	(x = 1600), so the PROCEDURAL river is alive underneath it — and on seed 4 it
	crosses one at about x = 1495 with no bridge over it. That is the same softlock
	as any unbridged crossing, on the one stretch of the walk a player cannot go
	around.

	So the corridor is sampled at the road's own station pitch and walked with the
	same crossing rule, and the deck is built by the same
	_field_bridge_row_from() the stations use. It stops at the city rect: inside
	it, the Danube is authored and so are its four bridges.

	ZERO RNG, like the coin line it shadows: the corridor is a pure function of
	the terminal station, which is where the run's seed enters.
	"""
	if not terrain._approach_bridge_cache.is_empty():
		return terrain._approach_bridge_cache
	if terrain._approach_bridge_scanned:
		return terrain._approach_bridge_cache
	terrain._approach_bridge_scanned = true

	var terminal: Vector2 = terrain._road_station(terrain._road_terminal_k()).center
	# East end: the coin line's own — the Danube's west bank. NOT clamped to the
	# city rect, and that is a fix rather than an oversight: a crossing can END on
	# the rect boundary (seed 606060 wades from x = 1589 to the edge at 1600), and
	# a scan that stops at 1600 finds no far bank and builds nothing. Inside the
	# rect `is_river_at` is the AUTHORED Danube and the corridor is the gate avenue
	# — dry — so the walk simply runs out of water there, and the Danube's own
	# crossings stay the four authored bridges: the coin line stops at its west
	# bank, so this scan never reaches midstream to call it a crossing.
	# A FEW METRES PAST THE RECT EDGE, NOT ALL THE WAY TO THE RIVER. Inside
	# Budapest `is_river_at` is the AUTHORED Danube and the corridor is the dry
	# gate avenue, so of the 880 samples this used to take, 730 asked a question
	# with a known answer — 36.7 ms on the first chunk build of a run, which lands
	# in the synchronous spawn ring. What round 3 actually needed past the
	# boundary was the DRY MARGIN of a crossing that ends ON it (seed 606060), and
	# that is one deck-width, not 730 m.
	# The east end is set so the RAMP FOOT — one run past the last deck point —
	# still lands inside that same bound, which is what keeps the corridor's stone
	# out of the gate district (authored from x = 1620) while leaving room for the
	# dry margin of a crossing that ends ON the rect edge.
	var east_x: float = minf(terrain._approach_coin_east_end(),
			BudapestPlan.BUDAPEST_MIN.x + 2.0 * FIELD_BRIDGE_HALF_WIDTH
					- _field_bridge_run())
	if east_x <= terrain.ROAD_TERMINAL_X:
		return terrain._approach_bridge_cache

	# SAMPLED AT THE PROBE STEP, NOT AT THE ROAD'S PITCH. A station is ~6 m of X
	# and a river band can be narrower than that, so a corridor walked station by
	# station steps straight over one and reports dry ground on both sides of
	# water it never asked about (run seed 63: the band at x = 1530-1532 fell
	# between two samples and the corridor got no bridge at all). Detection is
	# cheap and metre-fine; the DECK is decimated back to the road's pitch below,
	# so the stone is the same shape either way.
	var pts := PackedVector2Array()
	# FROM THE TERMINAL STATION, NOT FROM ROAD_TERMINAL_X. `T` is the last station
	# AT OR WEST of that X, so the two are up to a station apart — and the west
	# extension below stops at the terminal station, which left that gap
	# unsampled. On seed 115 the handoff water sits inside it, so the corridor
	# walked straight over the crossing it exists to find.
	# `road_approach_point` answers the terminal itself west of it, so starting
	# here is continuous with the extension and adds no kink.
	var x: float = minf(terrain.ROAD_TERMINAL_X, terminal.x)
	while x <= east_x:
		pts.append(BudapestPlan.road_approach_point(terminal, x))
		x += FIELD_BRIDGE_PROBE_STEP

	# ...and the WEST EXTENSION, which is THE HANDOFF AND HAS EXACTLY ONE OWNER.
	# The road-side builder refuses any crossing whose far bank lies past the last
	# station a road consumer may touch (`k1 + DRY > terminal`), so every crossing
	# still under way within a dry margin of `T` is the corridor's — and the
	# TRIGGER here has to be that same condition, not a probe of the corridor's
	# own first sample. `road_approach_point` answers the terminal itself for
	# every x west of it, so the corridor's line there is a POINT: on seed 203 it
	# reported dry across an axis the road never travels while the road's own
	# section was wet, and on seed 224 the crossing ended at `T - 1` with the
	# terminal dry, so neither side saw it at all.
	var terminal_k: int = terrain._road_terminal_k()
	# THE WEST EXTENSION IS UNCONDITIONAL, and that is the handoff's whole
	# ownership rule. The road side refuses any crossing whose far bank or whose
	# grown deck runs past the last station a road consumer may touch, and west of
	# `T` the corridor is a POINT whose perpendicular is not the road's — so every
	# TRIGGER tried here (the corridor's own first sample, then the road's wet
	# stations near T) missed one shape of the same case. Starting the corridor's
	# line on dry ROAD, always, means the scan below simply sees the crossing;
	# anything the road side really did deck is skipped by the ownership test in
	# the loop, so nothing is built twice.
	if true:
		# Walk back to the last DRY station, then lay the road's own centreline
		# out at the SAME pitch as the corridor's samples — mixing 6 m stations
		# with 1 m samples makes the decimation below skip 36 m of the western
		# half and turn the last deck segment into a chord.
		terrain._road_extend_to_x(terrain._road_station(terminal_k).center.x
				- FIELD_BRIDGE_BANK_WALK_MAX - FIELD_BRIDGE_MAX_SPAN,
			terrain.ROAD_TERMINAL_X)
		var k: int = terminal_k
		var walked_west := 0.0
		while walked_west <= FIELD_BRIDGE_BANK_WALK_MAX:
			k -= 1
			walked_west += terrain._road_station(k).center.distance_to(
					terrain._road_station(k + 1).center)
			# Far enough back that a RAMP fits on dry ground — the same rule the
			# road's own growth stops on, so the corridor's deck can end here.
			if _field_bridge_ramp_dry(terrain, terrain._road_station(k).center,
					terrain._road_station(k).center + _field_bridge_out_dir(terrain, k, -1)
							* _field_bridge_run()):
				break
		var west := PackedVector2Array()
		for j in range(k, terminal_k):
			var from: Vector2 = terrain._road_station(j).center
			var to: Vector2 = terrain._road_station(j + 1).center
			var steps := maxi(1, int(from.distance_to(to) / FIELD_BRIDGE_PROBE_STEP))
			for i in range(steps):
				west.append(from.lerp(to, float(i) / float(steps)))
		west.append_array(pts)
		pts = west

	var i := 0
	while i < pts.size() - 1:
		if _approach_wet(terrain, pts, i) or not _approach_wet(terrain, pts, i + 1):
			i += 1
			continue
		# i is the last DRY sample before the water: walk to the far bank,
		# accumulating metres walked (never the chord — see field_bridge_at).
		var j := i + 1
		var walked := 0.0
		var lake := false
		while j < pts.size() - 1 and _approach_wet(terrain, pts, j):
			walked += pts[j].distance_to(pts[j - 1])
			if walked > FIELD_BRIDGE_MAX_SPAN:
				lake = true
				break
			j += 1
		if lake or j >= pts.size() - 1:
			i = j + 1
			continue
		# ...and the same growth outward until the SECTION at each end is dry
		# across its width (see field_bridge_at): the deck carries on at 1.6 m
		# rather than dragging a ramp along the water.
		# ...growing on the RAMP RECTANGLE, exactly as the road's does: the foot
		# this deck will ask for demands the whole rectangle dry, so a growth that
		# stopped on a dry SECTION would hand it a bank it must refuse.
		# ...growing on the RAMP RECTANGLE, exactly as the road's does — and along
		# the direction the DECIMATED deck will hand its foot, not the 1 m local
		# one. The two differ wherever the corridor bends, and a growth that
		# cleared a ramp nobody builds hands the row a bank it must refuse.
		var stride: int = maxi(1, roundi(terrain._road_spacing() / FIELD_BRIDGE_PROBE_STEP))
		var run := _field_bridge_run()
		var grown := 0.0
		while i > 0 and grown < FIELD_BRIDGE_BANK_WALK_MAX and not \
				_field_bridge_ramp_dry(terrain, pts[i], pts[i] - (pts[
						mini(i + stride, pts.size() - 1)] - pts[i]).normalized() * run):
			grown += pts[i].distance_to(pts[i - 1])
			i -= 1
		grown = 0.0
		while j < pts.size() - 2 and grown < FIELD_BRIDGE_BANK_WALK_MAX and not \
				_field_bridge_ramp_dry(terrain, pts[j], pts[j] + (pts[j] - pts[
						maxi(j - stride, 0)]).normalized() * run):
			grown += pts[j].distance_to(pts[j + 1])
			j += 1

		# THE DECK IS DECIMATED BACK TO THE ROAD'S PITCH (`stride`, above):
		# detection wants metres, but a slab per metre is a hundred boxes and a
		# hundred collision shapes for one crossing. Both ends are kept whatever
		# the stride lands on, so the deck still starts and finishes on the dry
		# samples the walk found.
		var deck := PackedVector2Array()
		var m := i
		while m < j:
			deck.append(pts[m])
			m += stride
		deck.append(pts[j])
		if deck.size() < 3:
			# A crossing narrower than one stride decimates to its two ends, and
			# a deck needs a middle: the row is (dry margin, deck..., dry margin),
			# so two points describe no deck at all. This is exactly the narrow
			# band the fine sampling exists to catch (seed 63's is 5 m wide), so
			# it is the common case here rather than a corner of one.
			deck = PackedVector2Array([pts[i], pts[(i + j) / 2], pts[j]])
		# ...and the ROAD may already have decked this water from its own side of
		# the handoff (its east growth can run to T). One deck, one owner.
		var mid: Vector2 = pts[(i + j) / 2]
		if _field_bridge_decked(terrain, mid, _road_bridges_near(terrain, mid.x, mid.x)):
			i = j + 1
			continue
		var row := _field_bridge_row_from(terrain, deck)
		if not row.is_empty():
			row["k0"] = -1   # the corridor has no station index
			row["k1"] = -1
			terrain._approach_bridge_cache.append(row)
		i = j + 1
	return terrain._approach_bridge_cache


static func _approach_wet(terrain: Node3D, pts: PackedVector2Array, i: int) -> bool:
	"""Is the corridor in the water at sample `i`? THE CENTRELINE, for
	_field_bridge_wet's reason — the samples are already a metre apart, so one
	point each is the whole stretch."""
	return terrain.is_river_at(Vector3(pts[i].x, 0.0, pts[i].y))


static func field_bridges_near(terrain: Node3D, x0: float, x1: float) -> Array:
	"""
	Every field bridge whose stone can reach the world-X window [x0, x1].

	@param x0, x1: The window, world metres. Widened by _field_bridge_reach()
	               before the scan, so a bridge anchored outside it whose deck
	               reaches in is still found.
	@return: Array of rows from field_bridge_at(), west to east.

	Same shape as every other road consumer: extend the station cache over the
	padded window, binary-search its start, walk forward until the centreline
	passes the end. The cache stays uncapped (see _road_terminal_k) — it is this
	CONSUMER that stops at T, inside field_bridge_at.
	"""
	var reach: float = _field_bridge_reach(terrain)
	# One extra station of cache each way so field_bridge_at can ask about
	# (k0 - 1) at the window's western edge and about the dry station past k1 at
	# its eastern one.
	terrain._road_extend_to_x(x0 - reach - terrain._road_spacing() * 2.0,
			x1 + reach + terrain._road_spacing() * 2.0)
	var rows: Array = _road_bridges_near(terrain, x0, x1)
	# ...and the APPROACH CORRIDOR's own, which are not station-indexed and so are
	# not on the walk above. Cheap: the scan is memoized for the run and its rows
	# are rejected on X like any other.
	for row_v: Variant in approach_bridges(terrain):
		var row: Dictionary = row_v
		var poly: PackedVector2Array = row["poly"]
		if poly[poly.size() - 1].x < x0 - reach or poly[0].x > x1 + reach:
			continue
		rows.append(row)
	return rows


static func _road_bridges_near(terrain: Node3D, x0: float, x1: float) -> Array:
	"""
	The STATION-INDEXED half of field_bridges_near — every road bridge whose stone
	can reach the world-X window.

	Its own function because the corridor scan has to ask it: a crossing the road
	side already decks must not be decked a second time from the other side of the
	handoff (see approach_bridges). Splitting it is also what keeps that question
	free of recursion — the corridor asks about ROAD rows, and road rows never ask
	about the corridor.
	"""
	var reach: float = _field_bridge_reach(terrain)
	terrain._road_extend_to_x(x0 - reach - terrain._road_spacing() * 2.0,
			x1 + reach + terrain._road_spacing() * 2.0)
	var rows: Array = []
	var k: int = terrain._road_first_k_at_or_after_x(x0 - reach)
	while k <= terrain.road_k_max:
		var cur_k: int = k
		k += 1
		if terrain._road_station(cur_k).center.x > x1 + reach:
			break
		var row: Dictionary = field_bridge_at(terrain, cur_k)
		if not row.is_empty():
			rows.append(row)
	return rows


static func _field_bridge_decked(terrain: Node3D, at: Vector2, rows: Array) -> bool:
	"""Is this world XZ already on one of these decks?"""
	for row_v: Variant in rows:
		if _field_bridge_surface_on(terrain, row_v, Vector3(at.x, 0.0, at.y)) > -INF:
			return true
	return false


static func field_bridge_surface_y(terrain: Node3D, world_pos: Vector3) -> float:
	"""
	The height of the field-bridge walking surface over this XZ, or -INF when
	there is no bridge here.

	@param world_pos: World position; only X and Z are read.
	@return: The surface Y (FIELD_BRIDGE_TOP across the deck, sloping linearly
	         down each ramp to 0 at its foot), or -INF off the bridge.

	BudapestPlan.bridge_surface_y's field cousin, one dimension curvier: the city
	measures from the ends of an axis-aligned rect, and here the walking line is a
	polyline the road bent, so the parameter is distance ALONG it. Same profile,
	same flush-at-both-ends guarantee.

	It is what stands a road coin on a deck (spawn_coins_in_chunk) and what
	field_bridge_selfcheck measures the built stone against, so the surface the
	coins ride and the surface the boxes draw cannot drift apart.
	"""
	for row_v: Variant in field_bridges_near(terrain, world_pos.x, world_pos.x):
		var y: float = _field_bridge_surface_on(terrain, row_v, world_pos)
		if y > -INF:
			return y
	return -INF


static func field_bridge_stand_y(terrain: Node3D, world_x: float, world_z: float, ground_y: float) -> float:
	"""
	The height a BODY spawns at over this world XZ: its usual ground height, or
	that height above the deck when a field bridge is here.

	@param ground_y: The spawner's own drop height (0.6 for a boss, the
	                 crocodile's settle height, and so on) — kept, not replaced,
	                 so the gravity settle each spawner relies on is unchanged.

	A BODY IS DROPPED AT A GROUND HEIGHT AND SETTLED BY GRAVITY, so one placed at
	0.6 under a deck whose walking surface is 1.6 m up can neither fall onto it
	nor climb out: it clips through the stone or wanders about underneath (seed
	19's third road boss stood in exactly that, and all eight of its candidate
	spots were on the deck).

	A LIFT, NOT A REFUSAL, and the difference is a population. Rejecting the spot
	is the tidier-looking rule and it is what this shipped for one round — but a
	boss on a RIVER station is the one path that dispatches the crocodile, its
	spots are inside the 16 m deck almost by construction, and refusing them
	deleted every river boss in the world (`enemy_spawn_selfcheck` check 11's
	non-vacuity assertion caught it). Standing the animal ON the bridge keeps the
	encounter the road promised.

	Deliberately NOT an `obstacles` footprint: that list is the coin perch rule's
	too, and a footprint here would make `_settle_coin_y` skip the very coins the
	deck is supposed to carry. It costs no RNG draw either, so it can move no
	spawn.
	"""
	var surface: float = field_bridge_surface_y(terrain, Vector3(world_x, 0.0, world_z))
	return ground_y if surface <= -INF else ground_y + surface


static func _field_bridge_surface_on(terrain: Node3D, row: Dictionary, world_pos: Vector3) -> float:
	"""
	field_bridge_surface_y for ONE bridge row (the split exists so the coin
	spawner and the self-check can hold a row they already looked up).

	@return: The surface Y, or -INF when the point is off this bridge's deck.

	Point-to-polyline, the standard projection BudapestPlan.segment_distance
	makes for the Danube, kept here because this one also needs the PARAMETER
	(how far along) and not just the distance.
	"""
	var p := Vector2(world_pos.x, world_pos.z)
	for slab_v: Variant in _field_bridge_slabs(row):
		var slab: Dictionary = slab_v
		var d: Vector2 = p - Vector2(slab["start"])
		var dir: Vector2 = slab["dir"]
		# The slab's own frame: how far along it, and how far off its axis.
		var along: float = d.dot(dir)
		var length: float = slab["len"]
		# A millimetre of tolerance on every face, because the ends and the
		# parapets are exactly where a caller asks: the ramp foot projects to
		# `along` = 0 and a dot product of two normalised vectors lands either
		# side of it, which would answer "no bridge" on the first sample of a
		# metre-by-metre walk of its own deck.
		if along < -EDGE_EPS or along > length + EDGE_EPS:
			continue
		if absf(d.dot(Vector2(-dir.y, dir.x))) > float(slab["half"]) + EDGE_EPS:
			continue
		# The top surface is the plane through the slab's two ends, so the height
		# is one lerp — and a ramp and a deck slab are the same arithmetic.
		return lerpf(float(slab["y_a"]), float(slab["y_b"]),
				clampf(along / length, 0.0, 1.0))
	return -INF


static func spawn_field_bridges_in_chunk(terrain: Node3D, chunk_pos: Vector2i, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Build this chunk's share of every field bridge that reaches into it.

	@param chunk_pos: Chunk coordinates being built.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	SLICED BY THE CENTRE RULE, not by rect intersection, and that is the city's
	own decision read the other way round. A field deck is a chain of ROTATED
	slabs (the road curves; an axis-aligned deck would have to be widened by the
	lateral drift, which at the road's 78 deg heading cap is a 190 m slab for a
	40 m crossing), and CLAUDE.md's rule is that a rotated box cannot be cut into
	boxes and keeps the centre rule. That is safe here for the reason it is not
	safe for the Parliament: every piece is at most a couple of stations long and
	one deck wide, i.e. far smaller than a chunk, so the chunk that owns a piece
	is always within half a chunk of all of it. field_bridge_selfcheck check 2
	asserts that size bound, the budapest_selfcheck check 5 idiom.

	ORDERING: with the city's builders, after everything that fills `obstacles`
	and before _build_block_multimesh — a deck is one draw call's worth of the
	chunk's batch like any cactus. It appends NO footprint (see the const block).

	THE TRIM RIDES THE SAME LOOP (bead godot-test1-06o.4): a parapet per slab
	edge and a pylon pair at each bank, cantilevered OUTBOARD of the deck so the
	walkable lane, the surface query and every wet probe are untouched and only
	boxes were added — see the trim const block for the whole argument. Each
	piece takes the centre rule for ITSELF, because its midpoint is not its
	slab's.

	NO RNG DRAW from anybody's stream: its own private generator at a fixed seed,
	whose colour picks are overridden anyway.
	"""
	if not terrain.spawn_field_bridges:
		return
	var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
	var half_chunk: float = float(terrain.chunk_size) / 2.0
	var rows: Array = field_bridges_near(terrain, centre.x - half_chunk, centre.x + half_chunk)
	if rows.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = FIELD_BRIDGE_STREAM_SEED
	for row_v: Variant in rows:
		var row: Dictionary = row_v
		var poly: PackedVector2Array = row["poly"]
		# The two parapet lines, mitred, one per deck edge — segment `i` of each
		# belongs to slab `i`. Once per row per CHUNK, not once per slab: it is
		# pure in the row (so it is cached nowhere and can leak across no
		# re-seed) and it is a couple of dozen normalises against a window scan
		# this feature already budgets in milliseconds.
		var rail_off: float = float(row["half"]) + FIELD_BRIDGE_PARAPET_WIDTH * 0.5
		var rails: Array[PackedVector2Array] = [
			_field_bridge_rail_line(poly, rail_off),
			_field_bridge_rail_line(poly, -rail_off),
		]
		var slabs := _field_bridge_slabs(row)
		for i in slabs.size():
			var slab: Dictionary = slabs[i]
			var dir: Vector2 = slab["dir"]
			var run_h: float = slab["len"]
			var y_a: float = slab["y_a"]
			var y_b: float = slab["y_b"]
			var half: float = slab["half"]
			var mid: Vector2 = Vector2(slab["start"]) + dir * run_h * 0.5
			var rise := y_b - y_a
			var length := sqrt(run_h * run_h + rise * rise)
			# create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), so a box
			# long in LOCAL Z is tipped by `tilt` and swung to its heading by
			# `yaw` — the derivation _city_ramp_slice spells out. Local +Z lands
			# on (cos(tilt) * sin(yaw), -sin(tilt), cos(tilt) * cos(yaw)), so
			# yaw = atan2(dir.x, dir.y) points it along this segment and
			# tilt = -atan2(rise, run) tips it up that segment's climb.
			var yaw := atan2(dir.x, dir.y)
			var tilt := -atan2(rise, run_h)
			var surface := (y_a + y_b) * 0.5
			if terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y)) == chunk_pos:
				terrain.create_box(
						Vector3(mid.x - centre.x,
								surface - FIELD_BRIDGE_THICKNESS * 0.5,
								mid.y - centre.z),
						Vector3(half * 2.0, FIELD_BRIDGE_THICKNESS, length),
						yaw, rng, block_batch, block_body, tilt,
						FIELD_BRIDGE_STONE)

			# THE PARAPETS — one per edge of this slab, ramps included, because a
			# rail that stops where the deck does is a rail you walk off the side
			# of the approach. A rail segment is parallel to its slab (offset
			# lines are), so it takes the slab's own `yaw`; only its LENGTH moves,
			# which is what a mitre does at a turn.
			#
			# EACH ONE TAKES THE CENTRE RULE FOR ITSELF: a parapet's midpoint is
			# 8.25 m off its slab's, so the chunk that owns the slab is routinely
			# not the chunk that owns the wall — the rule slices a BOX.
			for rail_v: Variant in rails:
				var rail: PackedVector2Array = rail_v
				var r_mid: Vector2 = (rail[i] + rail[i + 1]) * 0.5
				var r_run: float = rail[i].distance_to(rail[i + 1])
				if r_run <= EDGE_EPS:
					continue
				if terrain.world_to_chunk(Vector3(r_mid.x, 0.0, r_mid.y)) != chunk_pos:
					continue
				terrain.create_box(
						Vector3(r_mid.x - centre.x,
								surface + (FIELD_BRIDGE_PARAPET_HEIGHT
										- FIELD_BRIDGE_THICKNESS) * 0.5,
								r_mid.y - centre.z),
						Vector3(FIELD_BRIDGE_PARAPET_WIDTH,
								FIELD_BRIDGE_PARAPET_HEIGHT + FIELD_BRIDGE_THICKNESS,
								sqrt(r_run * r_run + rise * rise)),
						yaw, rng, block_batch, block_body,
						-atan2(rise, r_run), FIELD_BRIDGE_PARAPET_STONE)

		# THE PYLON PAIR AT EACH BANK. The deck's two ends are poly[1] and
		# poly[-2] by construction (_field_bridge_row_from appends a ramp foot
		# outside each of them), and the slab meeting each is COLINEAR with the
		# deck segment beyond it — so the heading is that segment's and there is
		# no fourth description of the bridge's shape to keep in step.
		var last := poly.size() - 1
		for bank in [
			{ "at": poly[1], "dir": (poly[2] - poly[1]).normalized() },
			{ "at": poly[last - 1], "dir": (poly[last - 1] - poly[last - 2]).normalized() },
		]:
			var b_dir: Vector2 = bank["dir"]
			var b_perp := Vector2(b_dir.y, -b_dir.x)
			var b_top := FIELD_BRIDGE_TOP + FIELD_BRIDGE_PYLON_RISE
			for side in [-1.0, 1.0]:
				# OUTBOARD OF THE PARAPET'S CENTRE LINE by half a pylon, so the
				# two solids interpenetrate rather than share a face — see the
				# const block for why flush is z-fighting and not tidiness.
				var at: Vector2 = Vector2(bank["at"]) + b_perp * (side
						* (float(row["half"]) + FIELD_BRIDGE_PARAPET_WIDTH * 0.5
								+ FIELD_BRIDGE_PYLON_WIDTH * 0.5))
				if terrain.world_to_chunk(Vector3(at.x, 0.0, at.y)) != chunk_pos:
					continue
				terrain.create_box(
						Vector3(at.x - centre.x, b_top * 0.5, at.y - centre.z),
						Vector3(FIELD_BRIDGE_PYLON_WIDTH, b_top,
								FIELD_BRIDGE_PYLON_DEPTH),
						atan2(b_dir.x, b_dir.y), rng, block_batch, block_body,
						0.0, FIELD_BRIDGE_PYLON_STONE, false)


