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
##     would collide against 2,100 city boxes. "Must not bump" is free: no body
##     cannot push anyone. The work is making it visibly YIELD.
##   * Yield: clear → cruise; lane blocked (local player + car ahead) →
##     decelerate smoothly with move_toward to stop short; stopped + still
##     blocked > hold-off → HONK with per-car cooldown; blocked far too long →
##     recycle out of sight (never drive through the player).
##   * Budget: hard TRAFFIC_MAX (16 web / 32 desktop, was 30/60) rendered via ONE
##     MultiMeshInstance3D (one mesh, one shared StandardMaterial3D, colour
##     variety via per-instance colours, never a material per car) → 1 draw call.
##     Density cut roughly in half on web (≈1 car per 35m of avenue within the
##     110m bubble) so gaps read, not clumps; SPAWN_RADIUS kept at 110m so
##     VISIBLE_POP_GUARD (90m) still hides recycles.
##   * Bubble spawns around the local player inside BudapestPlan.rect(), recycles
##     when out of range or on non-carriageway, sleeps outside the city.
##   * Feet at y = 0 by construction. Cars stay on the carriageway — the
##     AVENUE_HALF_WIDTH (8 m) band on every CITY_AVENUE_EVERY-th grid line, one
##     side of the centreline so opposite directions do not overlap.
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
# Minimum centre-to-centre spacing at spawn/recycle — one car-length, crowd precedent MIN_WALKER_SPACING.
const MIN_CAR_SPACING: float = 5.0

# Cruise speeds — city traffic, comfortable read.
const CRUISE_MIN: float = 4.0
const CRUISE_MAX: float = 6.5
const ACCELERATION: float = 5.0
const DECELERATION: float = 9.0

# Yield distances: start braking at YIELD_DISTANCE, aim to stop STOP_DISTANCE short.
# STOP_DISTANCE is centre-to-centre with a car-length term so a queued pair shows a visible gap.
const YIELD_DISTANCE: float = 18.0
const STOP_DISTANCE: float = 6.7  # 4.5 + CAR_LENGTH*0.5 (was 4.5 centre-to-centre, looked touching)
const LATERAL_TOLERANCE: float = 3.2
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
var _cars: Array[Dictionary] = []

var _multimesh_node: MultiMeshInstance3D = null

const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

static var _shared_material: StandardMaterial3D = null
static var _shared_mesh: ArrayMesh = null
static var _box_cache: Dictionary = {}

static func _get_shared_material() -> StandardMaterial3D:
	if _shared_material == null:
		_shared_material = StandardMaterial3D.new()
		_shared_material.vertex_color_use_as_albedo = true
		_shared_material.vertex_color_is_srgb = true
		_shared_material.roughness = 0.78
		_shared_material.metallic = 0.08
		_shared_material.cull_mode = BaseMaterial3D.CULL_BACK
	return _shared_material

static func _box_mesh(size: Vector3) -> BoxMesh:
	if not _box_cache.has(size):
		var bm := BoxMesh.new()
		bm.size = size
		_box_cache[size] = bm
	return _box_cache[size]

static func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var arrays: Array = _box_mesh(size).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices:
		st.set_color(col)
		st.set_normal(normals[i])
		st.add_vertex(center + verts[i])

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
	_update_traffic_spawns(player_pos)
	_update_cars(delta, player_pos)

# ============================================================================
# QUERIES
# ============================================================================

func _find_player() -> Node3D:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node3D:
		return p
	return null

func _is_near_budapest(player_pos: Vector3) -> bool:
	return PLAN_SCRIPT.rect().grow(100.0).has_point(Vector2(player_pos.x, player_pos.z))

const WALKABLE_LANDMARK_IDS: Dictionary = {
	"heroes_square": true,
	"budapest_eye": true,
	"vaci_utca": true,
	"shoes_on_the_danube": true,
	"chain_bridge": true,
	"liberty_bridge": true,
	"elisabeth_bridge": true,
	"margaret_bridge": true,
	"margaret_island": true,
	"buda_castle": true,
	"matthias": true,
	"citadella": true,
}

static func _is_inside_solid_landmark(x: float, z: float) -> bool:
	for slot: Dictionary in PLAN_SCRIPT.SLOTS:
		var slot_id: String = slot.get("id", "")
		if WALKABLE_LANDMARK_IDS.has(slot_id):
			continue
		var spos: Vector3 = slot["pos"]
		var r: float = slot["radius"]
		var dx: float = x - spos.x
		var dz: float = z - spos.z
		if dx * dx + dz * dz < r * r:
			return true
	return false

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
	for other: Dictionary in _cars:
		if not other["active"]:
			continue
		if not exclude.is_empty() and other == exclude:
			continue
		var ow: Vector3 = _car_world_pos(other)
		if world_pos.distance_to(ow) < MIN_CAR_SPACING:
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

func _distance_to_block_ahead(car: Dictionary, player_pos: Vector3) -> float:
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
	# Check cars ahead — index loop to avoid Dictionary deep-compare (==) vs identity
	var c_dist := INF
	var car_idx := _cars.find(car)
	for j in _cars.size():
		if j == car_idx:
			continue
		var other: Dictionary = _cars[j]
		if not other["active"]:
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
	car["active"] = true

func _update_traffic_spawns(player_pos: Vector3) -> void:
	# Recycle out of sight: far cars always, near off-carriageway cars U-turn instead of popping.
	const VISIBLE_POP_GUARD: float = 90.0
	for car: Dictionary in _cars:
		if not car["active"]:
			var seg := _find_spawn_segment_near(player_pos)
			if seg.is_empty():
				break
			_assign_car_from_segment(car, seg)
		else:
			var wpos: Vector3 = _car_world_pos(car)
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

func _update_cars(delta: float, player_pos: Vector3) -> void:
	# Bulk buffer with use_colors=true: stride 16 (12 transform + 4 colour floats
	# r,g,b,a). One MultiMesh = 1 draw call, colour variety via per-instance colour
	# off the manager's own _rng, still one shared mesh and one shared material.
	if _multimesh_node == null:
		return
	var mm: MultiMesh = _multimesh_node.multimesh
	var count: int = 0
	var buf := PackedFloat32Array()
	buf.resize(_traffic_max * 16)
	for car: Dictionary in _cars:
		if not car["active"]:
			continue
		var block_dist: float = _distance_to_block_ahead(car, player_pos)
		var target: float = target_speed_for_distance(block_dist, float(car["cruise_speed"]))
		var cur: float = float(car["speed"])
		var next: float
		if target < cur:
			next = move_toward(cur, target, DECELERATION * delta)
		else:
			next = move_toward(cur, target, ACCELERATION * delta)
		car["speed"] = next

		var is_blocked: bool = (block_dist < YIELD_DISTANCE and next < 0.25)
		if is_blocked:
			car["blocked_time"] = float(car["blocked_time"]) + delta
			car["honk_cooldown"] = maxf(0.0, float(car["honk_cooldown"]) - delta)
			if float(car["blocked_time"]) >= HONK_HOLDOFF and float(car["honk_cooldown"]) <= 0.0:
				_try_honk(car, player_pos)
				car["honk_cooldown"] = HONK_COOLDOWN
		else:
			if float(car["blocked_time"]) > 0.0:
				car["blocked_time"] = maxf(0.0, float(car["blocked_time"]) - delta * 2.0)
			car["honk_cooldown"] = maxf(0.0, float(car["honk_cooldown"]) - delta)

		var h: Vector2 = car["heading_dir"]
		var base: Vector3 = car["pos"]
		base += Vector3(h.x, 0.0, h.y) * float(car["speed"]) * delta
		car["pos"] = base

		var wpos: Vector3 = _car_world_pos(car)
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
	if _multimesh_node != null:
		_multimesh_node.multimesh.visible_instance_count = 0
	for car: Dictionary in _cars:
		car["active"] = false
		car["speed"] = 0.0
		car["blocked_time"] = 0.0
		car["honk_cooldown"] = 0.0
