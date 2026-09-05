extends Node3D
## Ambient car traffic in Budapest: cars on the carriageways that yield to heroes.
##
## Owner verbatim: "there might be cars on the budapest street, they should
## not bump into heroes, instead stop and honk if they can't move".
##
## This manager (scripts/traffic_manager.gd, added once under Main in main.tscn,
## in group "traffic") is the ENTIRE feature — copying the crowd_manager / fauna
## precedent:
##   * Pure ambience, outside the run_seed determinism contract: its own
##     randomize()d RNG drives colours, cruise speeds and spawn jitter.
##   * Cars join NO group and carry NO collision bodies or Area3Ds. A car with a
##     body would be grabbed by the Stink Wave, LOD manager, hunt director, and
##     would collide against 2,100 city boxes. The work is making it visibly YIELD.
##   * Solid anyway (bead 8gw.21): the MANAGER owns CAR_PROXY_POOL colliders that
##     follow the nearest few cars to the local player, on the fauna layer that
##     only the player masks — so a hero bumps a bumper and slides along it while
##     the cars themselves stay transforms in a buffer, in no group, with no
##     draw call added. "Must not bump" is still not the body's job and never
##     was: a car that could reach the hero has already YIELDED, because half a
##     car's width plus a player radius (0.925 + 0.5) is well inside
##     LATERAL_TOLERANCE (3.2) and a yield begins YIELD_DISTANCE (18 m) out.
##     traffic_selfcheck asserts that margin and drives the stop.
##   * Yield: clear → cruise; lane blocked (local player + car ahead) →
##     decelerate smoothly with move_toward to stop short; stopped + still
##     blocked > hold-off → HONK with per-car cooldown; blocked far too long →
##     recycle out of sight (never drive through the player).
##   * Budget: hard TRAFFIC_MAX (16 web / 32 desktop, was 30/60) rendered via ONE
##     MultiMeshInstance3D (one mesh, one shared ShaderMaterial on the world's
##     own block shader since bead y1o.15, colour
##     variety via per-instance colours, never a material per car) → 1 draw call.
##     Density cut roughly in half on web (≈1 car per 35m of avenue within the
##     110m bubble) so gaps read, not clumps; SPAWN_RADIUS kept at 110m so
##     VISIBLE_POP_GUARD (90m) still hides recycles.
##   * Bubble spawns around the local player inside BudapestPlan.rect(), recycles
##     when out of range or on non-carriageway, sleeps outside the city.
##   * Feet at y = 0 by construction. Cars stay on the carriageway — the
##     AVENUE_HALF_WIDTH (8 m) band on every CITY_AVENUE_EVERY-th grid line, one
##     side of the centreline so opposite directions do not overlap.
##   * Budget (bead 8gw.22): a car the CAMERA cannot see is ticked COARSELY — a
##     few times a second, by the real elapsed time — never frozen and never
##     deleted. The rule and its rate live in scripts/ambience_lod.gd. ONE
##     decision per car per frame (`lod_step`), taken in _update_traffic_spawns
##     and spent by _update_cars, which is what keeps is_traffic_walkable the
##     FIRST branch of every tick a car actually takes: a car that did not step
##     cannot have driven into the Danube, and one that did was checked in the
##     same pass that let it.
##   * CITIZENS TOO (bead 8gw.23): the crowd is another blocker in the same yield
##     path — _distance_to_citizen_ahead reads crowd_manager's own seam and feeds
##     target_speed_for_distance beside the hero's distance, so a walker on the
##     carriageway is braked for rather than driven through. The other direction
##     is blocks_crossing, which the crowd asks before stepping off a kerb. Both
##     through the group with a has_method guard (a preload between these two
##     managers would be a cycle), so either one alone behaves as it did before.
##   * ponytail: cars drive at y = 0 only and never on bridge decks. The deck is
##     a dry rect 12 m up (BudapestPlan.BRIDGE_DECK_TOP) that needs
##     bridge_surface_y — that is a second problem; a car at y = 0 under a bridge
##     is worse than no car on it. This bead leaves DRY_RECTS dry and skips them.

# ============================================================================
# CONSTANTS — budgets, distances, speeds, yield, honk
# ============================================================================

const TRAFFIC_MAX_DESKTOP: int = 32
const TRAFFIC_MAX_WEB: int = 16

const SPAWN_RADIUS: float = 110.0
const DESPAWN_RADIUS: float = 145.0
const SPAWN_MIN_DIST: float = 14.0

const CAR_LENGTH: float = 4.4
const CAR_WIDTH: float = 1.85
# Spawn/recycle clearance — centre distance wants free air, not just non-overlap.
# This is INTENTIONALLY larger than opposite-lane separation (4.8 m) so a spawn
# candidate near an oncoming car is rejected for clearance, even though two
# cars passing abreast at 4.8 m do NOT interpenetrate (lateral gap 4.8 > CAR_WIDTH 1.85).
const MIN_CAR_SPACING: float = 5.0

# Cruise speeds — city traffic, comfortable read.
const CRUISE_MIN: float = 4.0
const CRUISE_MAX: float = 6.5
const ACCELERATION: float = 5.0
const DECELERATION: float = 9.0

# Yield distances: start braking at YIELD_DISTANCE, aim to stop STOP_DISTANCE short.
# STOP_DISTANCE is centre-to-centre with a car-length term so a queued pair shows a visible gap.
# STOP_DISTANCE (6.7) > MIN_CAR_SPACING (5.0) is intentional: STOP governs the
# in-lane queue gap (visible bumper gap), MIN_CAR_SPACING governs spawn clearance;
# a legitimately queued pair sits at ~6.7, which is > spawn clearance, not a conflict.
const YIELD_DISTANCE: float = 18.0
const STOP_DISTANCE: float = 6.7  # 4.5 + CAR_LENGTH*0.5 (was 4.5 centre-to-centre, looked touching)
const LATERAL_TOLERANCE: float = 3.2

# How far BEHIND the crossing point a car still counts as blocking it: half a car
# plus a citizen's own half-width and a little air. See `blocks_crossing`.
const CROSSING_REAR_CLEAR: float = CAR_LENGTH * 0.5 + 0.9
const LATERAL_TOLERANCE_CAR: float = 2.4

# Honk timing — one annoyed honk every few seconds, not a siren.
const HONK_HOLDOFF: float = 1.1
const HONK_COOLDOWN: float = 3.5
const HONK_AUDIBLE_RADIUS: float = 55.0

# If a car is blocked far too long, recycle it out of sight rather than let a
# queue of frozen cars accumulate. Do NOT drive through the player.
const STUCK_RECYCLE_TIME: float = 10.0

# Lane offset from the avenue centreline (right-hand traffic). Opposite
# directions get opposite signs via the heading-perp, so they do not overlap.
const LANE_OFFSET: float = 2.4

# Locality gate for the queue scan (bead 8gw.22). _distance_to_block_ahead used to
# do the full per-axis decomposition against EVERY other car — quadratic, and
# measured at 0.30 ms/frame for 32 cars before anything else in the tick was paid.
# A pair can only ever change the answer when it passes BOTH the forward test
# (0 < fwd < YIELD_DISTANCE + 1) and the lateral one (<= LATERAL_TOLERANCE_CAR),
# so two cars that matter are under sqrt((YIELD+1)^2 + LAT^2) ~ 19.2 m apart in
# WORLD position, and base (centreline) positions differ from world ones by at
# most one lane offset each. This per-axis box reject is therefore strictly
# conservative — it changes no answer, it just refuses to compute one.
# Deliberately not a spatial hash: it is 32 cars, and a hash is a structure to
# keep in step with every spawn and recycle.
const QUEUE_SCAN_RANGE: float = YIELD_DISTANCE + 1.0 + 2.0 * LANE_OFFSET + LATERAL_TOLERANCE_CAR

# Car palette — per-instance colours through MultiMesh instance colours.
const CAR_PALETTE: Array[Color] = [
	Color(0.85, 0.18, 0.18),  # red
	Color(0.18, 0.32, 0.68),  # blue
	Color(0.92, 0.92, 0.88),  # white
	Color(0.14, 0.14, 0.15),  # black
	Color(0.76, 0.76, 0.72),  # silver
	Color(0.18, 0.55, 0.28),  # green dark
	Color(0.82, 0.65, 0.18),  # taxi yellow
	Color(0.55, 0.35, 0.18),  # brown
]

# ============================================================================
# STATE
# ============================================================================

var _rng := RandomNumberGenerator.new()
var _traffic_max: int = TRAFFIC_MAX_DESKTOP

# Each record:
#   pos: Vector3            # base on avenue centreline (y=0)
#   heading_dir: Vector2    # unit on XZ, axis-aligned along street grid
#   facing_yaw: float
#   cruise_speed: float
#   speed: float            # current
#   color: Color
#   blocked_time: float
#   honk_cooldown: float
#   honk_count: int         # for selfcheck seam
#   active: bool
#   lod_debt: float         # seconds banked while out of view — ambience_lod.gd's
#   lod_step: float         # seconds to advance THIS frame; 0.0 = not this car's tick
var _cars: Array[Dictionary] = []

var _multimesh_node: MultiMeshInstance3D = null

## The pooled proxy colliders (CAR_PROXY_POOL of them, the MANAGER's nodes —
## never a car's). See ambience_proxies.gd.
var _proxies: RefCounted = null

const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

## The shared "coarse-tick what we cannot see" rule — see its header.
const AmbienceLod := preload("res://scripts/ambience_lod.gd")

## The shared pooled-proxy collider — read its header for why the cars themselves
## stay bodiless and why nothing here can shove a hero.
const AmbienceProxies := preload("res://scripts/ambience_proxies.gd")

## HOW MANY CARS CAN TOUCH THE HERO AT ONCE. MEASURED, not guessed: over six runs
## of 3,600 frames each, standing the hero ON a carriageway at four city
## locations at the desktop cap of 32, the most cars ever simultaneously inside
## CAR_PROXY_REACH was THREE (a car in each direction plus one queued behind).
## Four is that with a car's worth of headroom, and like the crowd's pool it is a
## CONSTANT: it does not grow with TRAFFIC_MAX.
const CAR_PROXY_POOL: int = 4

## How near a car must be to be given a body. Contact happens at ~2.7 m off the
## nose (half of CAR_LENGTH plus a player radius); 8 m is comfortably more than a
## frame of closing speed even head-on, and a car this close has long since begun
## to yield.
const CAR_PROXY_REACH: float = 8.0

## The car's footprint half-extents (front is local -Z, the mesh convention) and
## the collider's height — the chassis and cabin, not the roof trim.
const CAR_PROXY_HALF := Vector2(CAR_WIDTH * 0.5, CAR_LENGTH * 0.5)
const CAR_PROXY_HEIGHT: float = 1.15

## How tall the welded car mesh is, tyre contact patch to roof trim — the span
## the top-lit gradient is measured over (bead `godot-test1-y1o.15`). It is NOT
## `CAR_PROXY_HEIGHT`, which happens to be the same number for an unrelated
## reason (that one is a collider, deliberately "the chassis and cabin, not the
## roof trim"); a shading span and a physics box must not be one constant.
const CAR_MESH_TOP: float = 1.15

static var _shared_material: ShaderMaterial = null
static var _shared_mesh: ArrayMesh = null

static func _get_shared_material() -> Material:
	## The ONE material of the ONE traffic MultiMesh — now the WORLD'S OWN block
	## shader (bead `godot-test1-y1o.15`, style direction A), the crowd's change
	## one file along and for the same reason: a flat-lit car parked against a
	## gradient-shaded street reads as a decal.
	##
	## `_add_box` welds every box at its BODY offset, so model-space `VERTEX.y`
	## runs wheels-to-roof over the whole car — `height_range`'s reason to exist.
	## The paint still arrives through `COLOR` (the mesh's vertex colours times
	## the per-instance colour of a `use_colors` MultiMesh), so `albedo` stays at
	## its white default.
	##
	## THREE StandardMaterial3D PROPERTIES ARE GONE. `cull_mode = CULL_BACK` is
	## `world_block.gdshader`'s own `render_mode`, so that one is free.
	## `vertex_color_is_srgb` has no equivalent either, and dropping it makes the
	## cars a shade brighter on desktop — see the crowd's copy of that note for
	## why it is the consistent answer and for what about it was NOT measured.
	## `metallic = 0.08` HAS no equivalent: the shader writes ALBEDO and
	## ROUGHNESS and nothing else, so the cars lose a very slight sheen. That is
	## the bead's own call — if the owner misses it, it is one more uniform on a
	## shader every chunk in the world already runs.
	##
	## The BUILD is `CityAgents.gradient_material` since bead
	## `godot-test1-ftn.22`; the lazy singleton stays here, because "ONE material
	## for the one traffic MultiMesh" is this manager's invariant and
	## `traffic_selfcheck` asserts it off the live `material_override`.
	if _shared_material == null:
		_shared_material = CityAgents.gradient_material(CAR_MESH_TOP, 0.78)
	return _shared_material

static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	## One-line forwarder to `CityAgents.add_box` (bead `godot-test1-ftn.22`),
	## which is where the body lives now — shared with `crowd_manager.gd`, whose
	## copy was verbatim. The 13 call sites below keep their spelling.
	CityAgents.add_box(st, center, size, col)

static func _get_car_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body_col := Color(0.82, 0.82, 0.82)
	var body_dark := Color(0.18, 0.18, 0.20)
	var glass := Color(0.55, 0.68, 0.78, 0.88)
	var wheel_col := Color(0.08, 0.08, 0.09)
	var light_white := Color(0.96, 0.96, 0.90)
	var light_red := Color(0.78, 0.15, 0.14)

	# Lower body (chassis) 4.4 x 1.9, height 0.6, center y 0.30, front is -Z
	_add_box(st, Vector3(0.0, 0.30, 0.0), Vector3(1.85, 0.60, 4.4), body_col)
	# Cabin / roof  — slightly narrower, sits on top, length ~2.2, height 0.55, y 0.30+0.3+0.275=0.875
	_add_box(st, Vector3(0.0, 0.86, -0.20), Vector3(1.70, 0.52, 2.2), body_col)
	# Windshield / windows (tinted glass band around cabin)
	_add_box(st, Vector3(0.0, 0.88, -0.20), Vector3(1.72, 0.30, 2.0), glass)
	# Wheels — 4 small boxes at corners, bottom touches y=0 (center y 0.22, height 0.44)
	_add_box(st, Vector3(-0.82, 0.22, 1.2), Vector3(0.28, 0.44, 0.58), wheel_col)
	_add_box(st, Vector3(0.82, 0.22, 1.2), Vector3(0.28, 0.44, 0.58), wheel_col)
	_add_box(st, Vector3(-0.82, 0.22, -1.2), Vector3(0.28, 0.44, 0.58), wheel_col)
	_add_box(st, Vector3(0.82, 0.22, -1.2), Vector3(0.28, 0.44, 0.58), wheel_col)
	# Headlights (front = -Z face)
	_add_box(st, Vector3(-0.55, 0.32, -2.21), Vector3(0.26, 0.16, 0.04), light_white)
	_add_box(st, Vector3(0.55, 0.32, -2.21), Vector3(0.26, 0.16, 0.04), light_white)
	# Tail lights (rear = +Z)
	_add_box(st, Vector3(-0.62, 0.38, 2.21), Vector3(0.22, 0.12, 0.04), light_red)
	_add_box(st, Vector3(0.62, 0.38, 2.21), Vector3(0.22, 0.12, 0.04), light_red)
	# Subtle roof dark trim
	_add_box(st, Vector3(0.0, 1.13, -0.20), Vector3(1.68, 0.04, 2.18), body_dark)

	_shared_mesh = st.commit()
	return _shared_mesh

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	add_to_group("traffic")
	_rng.randomize()
	_traffic_max = TRAFFIC_MAX_WEB if OS.has_feature("web") else TRAFFIC_MAX_DESKTOP

	var mm_inst := MultiMeshInstance3D.new()
	mm_inst.name = "TrafficCars"
	mm_inst.material_override = _get_shared_material()
	mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _get_car_mesh()
	mm.instance_count = _traffic_max
	mm.visible_instance_count = 0
	mm_inst.multimesh = mm
	add_child(mm_inst)
	_multimesh_node = mm_inst

	# The pooled colliders. Built here so they exist for a manager driven
	# straight out of a harness, exactly like the MultiMesh above.
	_proxies = AmbienceProxies.new()
	# `yields: false` — a car is SOLID and stays solid. The crowd's anti-trap
	# yield is a crowd problem (a pedestrian walks into you and keeps walking);
	# a car brakes 18 m out and stops 6.7 m short, stands only on a carriageway
	# and leaves 5.6 m of open road past its far flank, so it can never pin
	# anybody — and a car you could walk through after a beat is exactly what the
	# owner did not ask for. See ambience_proxies.gd's header.
	_proxies.build(self, CAR_PROXY_POOL, CAR_PROXY_HALF, CAR_PROXY_HEIGHT,
		CAR_PROXY_REACH, false)

	_cars.clear()
	for i in _traffic_max:
		_cars.append({
			"pos": Vector3.ZERO,
			"heading_dir": Vector2(1.0, 0.0),
			"facing_yaw": 0.0,
			"cruise_speed": 5.0,
			"speed": 0.0,
			"color": CAR_PALETTE[i % CAR_PALETTE.size()],
			"blocked_time": 0.0,
			"honk_cooldown": 0.0,
			"honk_count": 0,
			"active": false,
			"lod_debt": 0.0,
			"lod_step": 0.0,
		})

func _process(delta: float) -> void:
	var player := _find_player()
	if player == null:
		_hide_all()
		return
	var player_pos: Vector3 = player.global_position
	if not _is_near_budapest(player_pos):
		_hide_all()
		return
	# Whose tick is it this frame? Asked ONCE per frame off the ACTIVE CAMERA
	# (never the player — the FRONT view looks backward along the hero), and
	# spent by both passes below. Empty planes (no camera) = everything visible.
	var planes: Array[Plane] = AmbienceLod.view_planes(get_viewport())
	# Open the proxy pool's candidate buffer: the nearest few cars are picked up
	# INSIDE _update_cars' existing loop (offer()), so the collision shares
	# 8gw.22's one pass per car and adds no scan of its own.
	_proxies.begin(player_pos)
	_update_traffic_spawns(delta, player_pos, planes)
	_update_cars(delta, player_pos, true)
	_proxies.commit(delta, player_pos)

# ============================================================================
# QUERIES
# ============================================================================

# THE THREE LOOKUPS BELOW ARE ONE-LINE FORWARDERS to `scripts/city_agents.gd`
# (bead `godot-test1-ftn.22`), which is where the bodies live now — shared with
# `crowd_manager.gd`, whose copies were verbatim. `WALKABLE_LANDMARK_IDS` went
# with them: two copies of a table naming which slots are open plazas is exactly
# the drift this refactor is against, and it is aliased back here because
# `is_traffic_walkable` reads through the alias and so may anything else.
const WALKABLE_LANDMARK_IDS := CityAgents.WALKABLE_LANDMARK_IDS

func _find_player() -> Node3D:
	return CityAgents.find_player(get_tree())

func _is_near_budapest(player_pos: Vector3) -> bool:
	return CityAgents.is_near_budapest(player_pos)

static func _is_inside_solid_landmark(x: float, z: float) -> bool:
	return CityAgents.is_inside_solid_landmark(x, z)

static func _is_on_avenue_carriageway(x: float, z: float) -> bool:
	# Distance to nearest AVENUE line (every CITY_AVENUE_EVERY-th grid line) < AVENUE_HALF_WIDTH
	var pitch: float = PLAN_SCRIPT.STREET_PITCH
	var ave_pitch: float = pitch * float(PLAN_SCRIPT.CITY_AVENUE_EVERY)
	var gate_x: float = PLAN_SCRIPT.GATE.x
	# Nearest avenue X
	var k := roundf((x - gate_x) / ave_pitch)
	var ave_x := gate_x + k * ave_pitch
	var dx := absf(x - ave_x)
	# Nearest avenue Z (gate.z == 0)
	var m := roundf(z / ave_pitch)
	var ave_z := m * ave_pitch
	var dz := absf(z - ave_z)
	var nearest := minf(dx, dz)
	return nearest < PLAN_SCRIPT.AVENUE_HALF_WIDTH

static func is_traffic_walkable(x: float, z: float) -> bool:
	# Same refusals as crowd, plus carriageway and off-bridge-decks.
	if not PLAN_SCRIPT.contains(x, z):
		return false
	if PLAN_SCRIPT.danube_wet(x, z):
		return false
	if PLAN_SCRIPT.plateau_top_at(x, z) > 0.0:
		return false
	if _is_inside_solid_landmark(x, z):
		return false
	if PLAN_SCRIPT.is_dry(x, z):
		return false
	if not _is_on_avenue_carriageway(x, z):
		return false
	return true

static func _car_world_pos(car: Dictionary) -> Vector3:
	var base: Vector3 = car["pos"]
	var h: Vector2 = car["heading_dir"]
	var perp := Vector3(-h.y, 0.0, h.x)
	return base + perp * LANE_OFFSET

func _is_occupied_near(world_pos: Vector3, exclude: Dictionary = {}) -> bool:
	# Crowd precedent MIN_WALKER_SPACING — reject candidate within a car-length of any live car.
	# This is a SPAWN clearance test (centre distance), intentionally larger than
	# opposite-lane separation, not the overlap assertion — see MIN_CAR_SPACING comment.
	for other: Dictionary in _cars:
		if not other["active"]:
			continue
		# Locality reject before the exclude compare (a Dictionary deep-compare)
		# and before _car_world_pos: MIN_CAR_SPACING is the whole reach of this
		# test, and base positions are within one lane offset of world ones.
		var obase: Vector3 = other["pos"]
		if absf(obase.x - world_pos.x) > MIN_CAR_SPACING + LANE_OFFSET \
				or absf(obase.z - world_pos.z) > MIN_CAR_SPACING + LANE_OFFSET:
			continue
		if not exclude.is_empty() and other == exclude:
			continue
		var ow: Vector3 = _car_world_pos(other)
		if world_pos.distance_to(ow) < MIN_CAR_SPACING:
			return true
	return false

static func _cars_overlap(world_a: Vector3, heading_a: Vector2, world_b: Vector3, heading_b: Vector2) -> bool:
	# Box overlap — per-axis in car's own frame, same decomposition as _distance_to_block_ahead.
	# Two 4.4×1.85 boxes overlap only if BOTH longitudinal < CAR_LENGTH and lateral < CAR_WIDTH
	# in either car's frame. Opposite lanes at 4.8 m lateral have ~3 m air gap, so no overlap.
	var delta := Vector2(world_b.x - world_a.x, world_b.z - world_a.z)
	# Frame A
	var perp_a := Vector2(-heading_a.y, heading_a.x)
	if absf(delta.dot(heading_a)) < CAR_LENGTH - 0.01 and absf(delta.dot(perp_a)) < CAR_WIDTH - 0.01:
		return true
	# Frame B (covers orthogonal orientation swap)
	var perp_b := Vector2(-heading_b.y, heading_b.x)
	if absf(delta.dot(heading_b)) < CAR_LENGTH - 0.01 and absf(delta.dot(perp_b)) < CAR_WIDTH - 0.01:
		return true
	return false

# ============================================================================
# YIELD — the actual ask (exposed seams for selfcheck mutation testing)
# ============================================================================

static func target_speed_for_distance(block_dist: float, cruise: float) -> float:
	# Pure function: maps forward block distance to desired speed.
	if block_dist == INF or block_dist >= YIELD_DISTANCE:
		return cruise
	if block_dist <= STOP_DISTANCE:
		return 0.0
	var t := (block_dist - STOP_DISTANCE) / (YIELD_DISTANCE - STOP_DISTANCE)
	return cruise * clampf(t, 0.0, 1.0)

func _distance_to_block_ahead(car: Dictionary, player_pos: Vector3, car_idx: int = -1) -> float:
	var wpos: Vector3 = _car_world_pos(car)
	var h: Vector2 = car["heading_dir"]
	# Check player first
	var p_dist := INF
	var to_p := Vector2(player_pos.x - wpos.x, player_pos.z - wpos.z)
	var fwd := to_p.dot(h)
	if fwd > 0.0 and fwd < YIELD_DISTANCE + 2.0:
		var perp := Vector2(-h.y, h.x)
		var lat := absf(to_p.dot(perp))
		if lat <= LATERAL_TOLERANCE:
			p_dist = fwd
	# Check cars ahead — index loop to avoid Dictionary deep-compare (==) vs identity.
	# The caller passes its own index; the `find` fallback is for a direct caller
	# and is itself a linear Dictionary compare, which is exactly what the loop
	# below refuses to pay per pair.
	var c_dist := INF
	if car_idx < 0:
		car_idx = _cars.find(car)
	var base: Vector3 = car["pos"]
	for j in _cars.size():
		if j == car_idx:
			continue
		var other: Dictionary = _cars[j]
		if not other["active"]:
			continue
		# Locality reject BEFORE any vector work — see QUEUE_SCAN_RANGE.
		var obase: Vector3 = other["pos"]
		if absf(obase.x - base.x) > QUEUE_SCAN_RANGE or absf(obase.z - base.z) > QUEUE_SCAN_RANGE:
			continue
		var ow: Vector3 = _car_world_pos(other)
		var to_c := Vector2(ow.x - wpos.x, ow.z - wpos.z)
		var fwd_c := to_c.dot(h)
		if fwd_c <= 0.0 or fwd_c >= YIELD_DISTANCE + 1.0:
			continue
		# Only queue same-direction cars (dot of headings > 0.6)
		var oh: Vector2 = other["heading_dir"]
		if h.dot(oh) < 0.6:
			continue
		var perp2 := Vector2(-h.y, h.x)
		var lat2 := absf(to_c.dot(perp2))
		if lat2 <= LATERAL_TOLERANCE_CAR:
			if fwd_c < c_dist:
				c_dist = fwd_c
	# Nearest blocker
	return minf(p_dist, c_dist)

func _distance_to_citizen_ahead(car: Dictionary) -> float:
	## THE CITIZENS, through the SAME yield/brake path as the hero (bead 8gw.23).
	##
	## Owner: "crowds in budapest still go through cars, not good, fix". Neither a
	## citizen nor a car has a body — the pooled proxies exist only for the hero —
	## so nothing physical was ever going to stop this. The fix is the shipped
	## brake: a citizen on the carriageway is a blocker at a distance, and
	## target_speed_for_distance does the rest.
	##
	## Deliberately its OWN function rather than a fourth clause inside
	## `_distance_to_block_ahead`: that function's answer is pinned byte-for-byte
	## against an independent all-pairs oracle (traffic_selfcheck check 8), and
	## the oracle is about the CAR queue's locality gate. Keeping the crowd term
	## out of it leaves that measurement meaning exactly what it says.
	##
	## Discovery is the project rule — the group, has_method-guarded, so a build
	## with no crowd (a harness, a standalone scene) degrades to INF, i.e. today.
	if not is_inside_tree():
		return INF
	var crowd := get_tree().get_first_node_in_group("crowd")
	if crowd == null or not crowd.has_method("blocking_citizen_distance"):
		return INF
	return crowd.blocking_citizen_distance(_car_world_pos(car), car["heading_dir"] as Vector2,
			YIELD_DISTANCE + 2.0, LATERAL_TOLERANCE)


func blocks_crossing(from: Vector3, to: Vector3, heading: Vector2) -> bool:
	## THE CROWD'S SEAM (bead 8gw.23): may a citizen at `from`, walking `heading`,
	## take a step to `to`? False unless the step ENTERS a carriageway with a car
	## inside its braking distance of the spot.
	##
	## Three refusals, and each is a bug avoided:
	##   * already ON the carriageway => allowed. Stopping somebody mid-crossing
	##     parks them in the traffic; the car brakes for them instead.
	##   * the step does not reach a carriageway => allowed, nothing to wait for.
	##   * a car on the SAME axis as the walker is not being crossed — it is
	##     driving up the avenue the citizen walks along, which is the car's
	##     problem, not the citizen's. Without this a walker on an avenue would
	##     stand still forever with a car creeping behind it.
	##
	## THE DISTANCE IS MEASURED TO THE CROSSING POINT, NOT TO THE WALKER. That is
	## the whole of the rule and it was got wrong once: a citizen at the kerb is
	## 10 m to the side of the lane it is about to enter, so asking "is the next
	## 4 cm step inside a car's path" is false at every kerb and true only once
	## the walker is already in the road — where the first refusal has taken over.
	## The point to ask about is where the walker's LINE meets the car's, which is
	## what a person at a kerb actually judges.
	## The distance is the car's own YIELD_DISTANCE — the kerb rule and the brake
	## are two readings of one number.
	if _is_on_avenue_carriageway(from.x, from.z):
		return false
	if not _is_on_avenue_carriageway(to.x, to.z):
		return false
	for car: Dictionary in _cars:
		if not car["active"]:
			continue
		var h: Vector2 = car["heading_dir"]
		if absf(h.dot(heading)) > 0.6:
			continue
		var perp := Vector2(-h.y, h.x)
		var denom := heading.dot(perp)
		if absf(denom) < 0.1:
			continue  # very nearly parallel after all; nothing is being crossed
		var wpos: Vector3 = _car_world_pos(car)
		var to_p := Vector2(to.x - wpos.x, to.z - wpos.z)
		# Walk `to` along the citizen's own heading until it sits on the car's line.
		var travel := -to_p.dot(perp) / denom
		# ...but the walker's line is INFINITE, and the car's is too. Without this
		# bound a citizen stepping onto the z = 0 avenue is held by a car on the
		# PARALLEL z = 248 avenue, because their lines still cross — 248 m up the
		# walker's line, which is not a crossing anybody is about to make. A
		# crossing is at most the carriageway's own width away: the walker starts
		# at a kerb (AVENUE_HALF_WIDTH out) and the lane it must clear is nearer
		# still, so twice the half-width is the whole of the geometry.
		if absf(travel) > 2.0 * PLAN_SCRIPT.AVENUE_HALF_WIDTH:
			continue
		var cross := to_p + heading * travel
		var fwd := cross.dot(h)
		# THE CAR'S BODY, NOT ITS CENTRE. `fwd > 0` released the walker the instant
		# the centre passed the crossing, while 2.2 m of car was still across it —
		# and a car STOPPED by the hero ahead straddles it indefinitely, so the
		# walker stepped into a stationary car and the car, looking only forward,
		# never saw it. Release once the rear bumper is clear by a body's width.
		if fwd > -CROSSING_REAR_CLEAR and fwd <= YIELD_DISTANCE:
			return true
	return false


func _try_honk(car: Dictionary, player_pos: Vector3) -> void:
	# Distance-attenuated: skip if player too far; otherwise fire sound.
	var wpos: Vector3 = _car_world_pos(car)
	var d := Vector2(wpos.x - player_pos.x, wpos.z - player_pos.z).length()
	if d > HONK_AUDIBLE_RADIUS:
		return
	car["honk_count"] = int(car["honk_count"]) + 1
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm != null and sm.has_method("play_car_horn"):
		sm.play_car_horn(d)

# ============================================================================
# SPAWN / RECYCLE
# ============================================================================

func _find_spawn_segment_near(player_pos: Vector3) -> Dictionary:
	# Find a valid avenue-aligned placement near the player.
	var pitch: float = PLAN_SCRIPT.STREET_PITCH
	var ave_pitch: float = pitch * float(PLAN_SCRIPT.CITY_AVENUE_EVERY)
	var gate_x: float = PLAN_SCRIPT.GATE.x
	for attempt in 20:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(SPAWN_MIN_DIST, SPAWN_RADIUS)
		var cand_x := player_pos.x + cos(angle) * dist
		var cand_z := player_pos.z + sin(angle) * dist

		# Decide avenue orientation: snap to nearest avenue line
		var use_ns: bool = _rng.randf() < 0.5  # NS avenue (constant x) vs EW (constant z)
		var base_x: float
		var base_z: float
		var heading: Vector2
		if use_ns:
			var k := roundf((cand_x - gate_x) / ave_pitch)
			base_x = gate_x + k * ave_pitch
			base_z = roundf(cand_z / pitch) * pitch
			heading = Vector2(0.0, 1.0) if _rng.randf() < 0.5 else Vector2(0.0, -1.0)
		else:
			var m := roundf(cand_z / ave_pitch)
			base_z = m * ave_pitch
			base_x = roundf((cand_x - gate_x) / pitch) * pitch
			heading = Vector2(1.0, 0.0) if _rng.randf() < 0.5 else Vector2(-1.0, 0.0)

		var base := Vector3(base_x, 0.0, base_z)
		var perp := Vector3(-heading.y, 0.0, heading.x)
		var wpos := base + perp * LANE_OFFSET
		if not is_traffic_walkable(wpos.x, wpos.z):
			continue
		# Also ensure the road ahead for a step is still carriageway (not hitting a plateau edge immediately)
		var ahead := wpos + Vector3(heading.x, 0.0, heading.y) * 6.0
		if not is_traffic_walkable(ahead.x, ahead.z):
			continue
		if _is_occupied_near(wpos):
			continue
		return {"pos": base, "heading": heading}
	return {}

func _assign_car_from_segment(car: Dictionary, seg: Dictionary) -> void:
	## Single home of the 7-line spawn/recycle assignment (review nit: was copy-pasted 3×).
	car["pos"] = seg["pos"]
	car["heading_dir"] = seg["heading"]
	var h: Vector2 = seg["heading"]
	car["facing_yaw"] = atan2(-h.x, -h.y)
	car["cruise_speed"] = _rng.randf_range(CRUISE_MIN, CRUISE_MAX)
	car["speed"] = car["cruise_speed"] * 0.9
	car["color"] = CAR_PALETTE[_rng.randi() % CAR_PALETTE.size()]
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = _rng.randf_range(0.0, 1.0)
	car["honk_count"] = 0
	car["lod_debt"] = 0.0
	car["active"] = true

func _update_traffic_spawns(delta: float, player_pos: Vector3, planes: Array[Plane] = []) -> void:
	# Recycle out of sight: far cars always, near off-carriageway cars U-turn instead of popping.
	#
	# THIS IS ALSO WHERE THE COARSE TICK IS DECIDED, once per car per frame, and
	# written to `lod_step` for _update_cars to spend. Deciding it here is what
	# keeps is_traffic_walkable the FIRST branch of every tick a car takes: the
	# same pass that grants the step re-checks the ground the car is standing on.
	# `planes` empty (no camera) => everything visible => byte-for-byte today.
	const VISIBLE_POP_GUARD: float = 90.0
	# EVERY car must get its decision, which is why the "no walkable street near
	# the player" case sets a flag and carries on instead of breaking out of the
	# loop as it used to: a car the loop never reached would keep LAST frame's
	# `lod_step` and spend it a second time. The retry storm that `break` existed
	# to prevent is prevented by the flag — no further _find_spawn_segment_near.
	var spawn_exhausted: bool = false
	for car: Dictionary in _cars:
		if not car["active"]:
			car["lod_step"] = delta  # nowhere to stand yet: never coarse-ticked
			if spawn_exhausted:
				continue
			var seg := _find_spawn_segment_near(player_pos)
			if seg.is_empty():
				spawn_exhausted = true
				continue
			_assign_car_from_segment(car, seg)
		else:
			var wpos: Vector3 = _car_world_pos(car)
			car["lod_step"] = AmbienceLod.step_delta(car, delta, AmbienceLod.is_visible_at(planes, wpos))
			if float(car["lod_step"]) <= 0.0:
				continue  # not this car's tick — it drives later, by the banked time
			var flat_dist := Vector2(wpos.x - player_pos.x, wpos.z - player_pos.z).length()
			var walkable := is_traffic_walkable(wpos.x, wpos.z)
			if flat_dist > DESPAWN_RADIUS or not walkable:
				if not walkable and flat_dist <= VISIBLE_POP_GUARD:
					# Would pop in plain view — U-turn (not junction turning) instead of vanishing.
					var h: Vector2 = car["heading_dir"]
					var rev := Vector2(-h.x, -h.y)
					var new_base: Vector3 = car["pos"] + Vector3(rev.x, 0, rev.y) * 1.0
					var new_perp: Vector3 = Vector3(-rev.y, 0, rev.x)
					var new_wpos: Vector3 = new_base + new_perp * LANE_OFFSET
					if _is_occupied_near(new_wpos, car):
						# New lane occupied — still would interpenetrate, so recycle out of sight instead
						var seg2 := _find_spawn_segment_near(player_pos)
						if not seg2.is_empty():
							_assign_car_from_segment(car, seg2)
						else:
							car["active"] = false
					else:
						car["heading_dir"] = rev
						car["facing_yaw"] = atan2(-rev.x, -rev.y)
						car["pos"] = new_base
						car["blocked_time"] = 0.0
				else:
					var seg := _find_spawn_segment_near(player_pos)
					if not seg.is_empty():
						_assign_car_from_segment(car, seg)
					else:
						car["active"] = false
			elif car["blocked_time"] > STUCK_RECYCLE_TIME:
				# Permanently blocked — recycle out of sight, never drive through.
				var seg := _find_spawn_segment_near(player_pos)
				if not seg.is_empty():
					_assign_car_from_segment(car, seg)
				else:
					car["active"] = false

func _update_cars(delta: float, player_pos: Vector3, lod_gated: bool = false) -> void:
	# Bulk buffer with use_colors=true: stride 16 (12 transform + 4 colour floats
	# r,g,b,a). One MultiMesh = 1 draw call, colour variety via per-instance colour
	# off the manager's own _rng, still one shared mesh and one shared material.
	#
	# `lod_gated` false means every car steps by `delta` — what a harness driving
	# this function directly wants, and byte-for-byte what a camera-less scene
	# produces anyway. `_process` passes true and each car spends the `lod_step`
	# decided in _update_traffic_spawns: 0.0 means it is not its tick, so it is
	# DRAWN WHERE IT STANDS and drives on its next one. Never skipped out of the
	# buffer, never deleted — the traffic is never a hole.
	if _multimesh_node == null:
		return
	var mm: MultiMesh = _multimesh_node.multimesh
	var count: int = 0
	var buf := PackedFloat32Array()
	buf.resize(_traffic_max * 16)
	for ci in _cars.size():
		var car: Dictionary = _cars[ci]
		if not car["active"]:
			continue
		# The coarse tick: the REAL elapsed time since this car last drove.
		var step_dt: float = float(car["lod_step"]) if lod_gated else delta
		if step_dt > 0.0:
			var block_dist: float = minf(_distance_to_block_ahead(car, player_pos, ci),
					_distance_to_citizen_ahead(car))
			var target: float = target_speed_for_distance(block_dist, float(car["cruise_speed"]))
			var cur: float = float(car["speed"])
			var next: float
			if target < cur:
				next = move_toward(cur, target, DECELERATION * step_dt)
			else:
				next = move_toward(cur, target, ACCELERATION * step_dt)
			car["speed"] = next

			var is_blocked: bool = (block_dist < YIELD_DISTANCE and next < 0.25)
			if is_blocked:
				car["blocked_time"] = float(car["blocked_time"]) + step_dt
				car["honk_cooldown"] = maxf(0.0, float(car["honk_cooldown"]) - step_dt)
				if float(car["blocked_time"]) >= HONK_HOLDOFF and float(car["honk_cooldown"]) <= 0.0:
					_try_honk(car, player_pos)
					car["honk_cooldown"] = HONK_COOLDOWN
			else:
				if float(car["blocked_time"]) > 0.0:
					car["blocked_time"] = maxf(0.0, float(car["blocked_time"]) - step_dt * 2.0)
				car["honk_cooldown"] = maxf(0.0, float(car["honk_cooldown"]) - step_dt)

			var h: Vector2 = car["heading_dir"]
			var base: Vector3 = car["pos"]
			base += Vector3(h.x, 0.0, h.y) * float(car["speed"]) * step_dt
			car["pos"] = base

		var wpos: Vector3 = _car_world_pos(car)
		# The proxy pool rides THIS loop — world position and facing already in
		# hand, so being solid costs a box reject per car.
		_proxies.offer(Vector3(wpos.x, 0.0, wpos.z), float(car["facing_yaw"]))
		var basis := Basis().rotated(Vector3.UP, float(car["facing_yaw"]))
		var t := Transform3D(basis, Vector3(wpos.x, 0.0, wpos.z))
		var base_idx := count * 16
		buf[base_idx + 0] = t.basis.x.x
		buf[base_idx + 1] = t.basis.y.x
		buf[base_idx + 2] = t.basis.z.x
		buf[base_idx + 3] = t.origin.x
		buf[base_idx + 4] = t.basis.x.y
		buf[base_idx + 5] = t.basis.y.y
		buf[base_idx + 6] = t.basis.z.y
		buf[base_idx + 7] = t.origin.y
		buf[base_idx + 8] = t.basis.x.z
		buf[base_idx + 9] = t.basis.y.z
		buf[base_idx + 10] = t.basis.z.z
		buf[base_idx + 11] = t.origin.z
		var col: Color = car["color"]
		buf[base_idx + 12] = col.r
		buf[base_idx + 13] = col.g
		buf[base_idx + 14] = col.b
		buf[base_idx + 15] = col.a
		count += 1
		if count >= _traffic_max:
			break
	# Park remainder at far away so they are not visible even if count miscounts
	for i in range(count, _traffic_max):
		var b := i * 16
		# identity basis, origin far away, transparent
		buf[b + 0] = 1; buf[b + 1] = 0; buf[b + 2] = 0; buf[b + 3] = 9999.0
		buf[b + 4] = 0; buf[b + 5] = 1; buf[b + 6] = 0; buf[b + 7] = 9999.0
		buf[b + 8] = 0; buf[b + 9] = 0; buf[b + 10] = 1; buf[b + 11] = 9999.0
		buf[b + 12] = 1; buf[b + 13] = 1; buf[b + 14] = 1; buf[b + 15] = 0
	mm.buffer = buf
	mm.visible_instance_count = count

func _hide_all() -> void:
	# The colliders go with the cars, or a hero leaving the city keeps bumping
	# into ghosts parked at the last pose the pool held.
	if _proxies != null:
		_proxies.sleep()
	if _multimesh_node != null:
		_multimesh_node.multimesh.visible_instance_count = 0
	for car: Dictionary in _cars:
		car["active"] = false
		car["speed"] = 0.0
		car["blocked_time"] = 0.0
		car["honk_cooldown"] = 0.0
