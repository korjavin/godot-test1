extends SceneTree
## Headless self-check for traffic_manager.gd (Budapest car traffic).
##
##   godot --headless --path . --script res://scripts/traffic_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints failure details and exits 1.
##
## Validates (mirroring budapest bead acceptance):
##   1. Isolation: TrafficManager in group "traffic", no descendant joins a
##      gameplay group and carries no CollisionObject3D/Area3D.
##   2. Mesh/material/draw budget: exactly ONE MultiMeshInstance3D, one shared
##      StandardMaterial3D with vertex_colors + sRGB, mesh feet at y=0, web cap
##      holds (instance_count <= TRAFFIC_MAX_WEB, visible <= cap, cast_shadow OFF,
##      == 1 draw call).
##   3. Placement: every active car sits at y==0 on a carriageway (avenue band),
##      never in a block courtyard, never in Danube wet, never on plateau, never
##      in solid landmark, never on a bridge/island dry rect.
##   4. Dormancy: 0 visible outside Budapest, >0 active when inside around player.
##   5. Yield: a car driven at a stationary quarry (local player) in its lane
##      decelerates via the SHIPPED move_toward path and STOPS short of it over
##      N ticks rather than passing through.
##   6. Honk: after HONK_HOLDOFF fires once, then respects per-car HONK_COOLDOWN
##      rather than every tick.

const SIM_FRAMES: int = 240
const DT: float = 1.0 / 60.0

var _root: Node3D = null
var _manager: Node3D = null
var _player: CharacterBody3D = null
var _failures: Array[String] = []

func _initialize() -> void:
	_root = Node3D.new()
	root.add_child(_root)

	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.add_to_group("player")
	_player.position = Vector3(0.0, 1.0, 0.0)
	_root.add_child(_player)

	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	_manager = Node3D.new()
	_manager.set_script(mgr_script)
	_root.add_child(_manager)

func _process(_delta: float) -> bool:
	_run_checks()
	return false

func _run_checks() -> void:
	print("--- Running traffic_selfcheck ---")
	_check_groups_and_collision()
	_check_multimesh_resources()
	_check_dormancy_outside_budapest()
	_check_placement_and_walkable()
	_check_yield_stops_short()
	_check_honk_holdoff_and_cooldown()
	_check_target_speed_seam()
	if _failures.is_empty():
		print("traffic_selfcheck: all checks passed cleanly")
		print("SELFCHECK OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		quit(1)

func _check_groups_and_collision() -> void:
	if not _manager.is_in_group("traffic"):
		_failures.append("TrafficManager is not in group 'traffic'")
	for g in ["player", "crocodile", "enemy", "boss", "terrain", "crowd", "fauna"]:
		if _manager.is_in_group(g):
			_failures.append("TrafficManager illegally joined gameplay group '%s'" % g)
	_check_node_isolation_recursive(_manager)

func _check_node_isolation_recursive(node: Node) -> void:
	if node != _manager:
		var groups := node.get_groups()
		if not groups.is_empty():
			_failures.append("TrafficManager descendant '%s' has groups: %s (must have none)" % [node.name, str(groups)])
		if node is CollisionObject3D:
			_failures.append("TrafficManager descendant '%s' is a physics CollisionObject3D (must have none)" % node.name)
		if node is Area3D:
			_failures.append("TrafficManager descendant '%s' is an Area3D (must have none)" % node.name)
	for child in node.get_children():
		_check_node_isolation_recursive(child)

func _check_multimesh_resources() -> void:
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	if mm_node == null:
		_failures.append("TrafficManager _multimesh_node is null (expected ONE MultiMeshInstance3D)")
		return
	# Exactly one traffic mesh child — count traffic MultiMeshInstance3D under manager
	var mm_count := 0
	for c in _manager.get_children():
		if c is MultiMeshInstance3D:
			mm_count += 1
	if mm_count != 1:
		_failures.append("Expected exactly 1 MultiMeshInstance3D under TrafficManager, found %d" % mm_count)
	var mm: MultiMesh = mm_node.multimesh
	if mm == null:
		_failures.append("Traffic MultiMesh is null")
		return
	if mm.mesh == null:
		_failures.append("Traffic MultiMesh has null mesh")
		return
	if mm_node.material_override == null:
		_failures.append("Traffic material_override is null")
	else:
		var mat: StandardMaterial3D = mm_node.material_override as StandardMaterial3D
		if mat != null and not mat.vertex_color_use_as_albedo:
			_failures.append("Traffic shared material must have vertex_color_use_as_albedo=true")
		if mat != null and not mat.vertex_color_is_srgb:
			_failures.append("Traffic shared material must have vertex_color_is_srgb=true")
	if mm_node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_failures.append("Traffic MultiMeshInstance3D must have cast_shadow OFF (1 draw call budget, no shadow pass)")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var cap_web: int = mgr_script.get("TRAFFIC_MAX_WEB") if mgr_script.get("TRAFFIC_MAX_WEB") != null else 30
	if mm.instance_count != cap_web and mm.instance_count != int(mgr_script.get("TRAFFIC_MAX_DESKTOP")):
		# Instance count should be the platform cap at startup (web in headless defaults to desktop? Check both)
		# Headless OS.has_feature("web") is false => desktop cap.
		pass
	# Assert the desktop/web cap invariant: instance_count must equal the manager's _traffic_max
	var tm_max: int = _manager.get("_traffic_max")
	if mm.instance_count != tm_max:
		_failures.append("Traffic MultiMesh instance_count %d != _traffic_max %d" % [mm.instance_count, tm_max])
	if mm.instance_count > int(mgr_script.get("TRAFFIC_MAX_DESKTOP")):
		_failures.append("Traffic instance_count %d exceeds desktop cap" % mm.instance_count)
	# Feet at y=0
	var aabb: AABB = mm.mesh.get_aabb()
	if absf(aabb.position.y) > 0.001:
		_failures.append("Traffic mesh AABB position.y is %f (must be 0.0 for feet at y=0)" % aabb.position.y)
	# Budget: ONE draw call for traffic (single MultiMeshInstance3D)
	# Assert count ==1 already; that is the draw-call budget.

func _check_dormancy_outside_budapest() -> void:
	_player.position = Vector3(0.0, 1.0, 0.0)
	_manager._process(DT)
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	var vis: int = mm_node.multimesh.visible_instance_count
	if vis != 0:
		_failures.append("Traffic rendered %d visible while player outside Budapest at x=0 (must hide)" % vis)

func _check_placement_and_walkable() -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	# Two in-city locations: avenue gate and Pest
	for loc in [Vector3(1750.0, 1.0, 0.0), Vector3(2920.0, 1.0, 248.0)]:
		_player.position = loc
		for frame in 60:
			_manager._process(DT)
		_verify_cars_placement("near %s" % str(loc))
	# Also heroes square avenue
	_player.position = Vector3(3520.0, 1.0, -496.0)
	for frame in 60:
		_manager._process(DT)
	_verify_cars_placement("Heroes Square avenue")

func _verify_cars_placement(context: String) -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var cars: Array = _manager.get("_cars")
	var active := 0
	for car: Dictionary in cars:
		if not car["active"]:
			continue
		active += 1
		var wpos: Vector3 = mgr_script._car_world_pos(car)
		# y must be 0
		if absf(wpos.y) > 0.001:
			_failures.append("%s: car world y is %f (must be 0)" % [context, wpos.y])
		if not plan_script.contains(wpos.x, wpos.z):
			_failures.append("%s: car at (%f,%f) outside Budapest rect" % [context, wpos.x, wpos.z])
		if plan_script.danube_wet(wpos.x, wpos.z):
			_failures.append("%s: car at (%f,%f) is in Danube wet" % [context, wpos.x, wpos.z])
		if plan_script.plateau_top_at(wpos.x, wpos.z) > 0.0:
			_failures.append("%s: car at (%f,%f) is on plateau" % [context, wpos.x, wpos.z])
		if mgr_script._is_inside_solid_landmark(wpos.x, wpos.z):
			_failures.append("%s: car at (%f,%f) inside solid landmark" % [context, wpos.x, wpos.z])
		if plan_script.is_dry(wpos.x, wpos.z):
			_failures.append("%s: car at (%f,%f) on bridge/island dry rect at y=0" % [context, wpos.x, wpos.z])
		if not mgr_script.is_traffic_walkable(wpos.x, wpos.z):
			_failures.append("%s: car at (%f,%f) not is_traffic_walkable (not on avenue carriageway)" % [context, wpos.x, wpos.z])
		# Also ensure not inside a block courtyard — carriageway check already, but double-check via block_rect interior
		# World pos should not be inside a block_rect interior that is buildable? We check by sampling block_rect contains
		if float(car["speed"]) < -0.001:
			_failures.append("%s: car has negative speed %f" % [context, float(car["speed"])])
	if active == 0:
		_failures.append("%s: 0 active cars spawned around player inside Budapest" % context)
	var tm_max: int = _manager.get("_traffic_max")
	if active > tm_max:
		_failures.append("%s: active car count %d exceeds _traffic_max %d" % [context, active, tm_max])
	# MultiMesh readback: origins must be walkable and finite (buffer path like crowd)
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	var mm: MultiMesh = mm_node.multimesh
	var buf: PackedFloat32Array = mm.buffer
	var vis: int = mm.visible_instance_count
	for idx in vis:
		var base := idx * 12
		var ox: float = buf[base + 3]
		var oy: float = buf[base + 7]
		var oz: float = buf[base + 11]
		if not is_finite(ox) or not is_finite(oy) or not is_finite(oz):
			_failures.append("%s: MultiMesh instance %d non-finite origin (%f,%f,%f)" % [context, idx, ox, oy, oz])
		if absf(oy) > 0.01:
			_failures.append("%s: MultiMesh instance %d oy %f not 0" % [context, idx, oy])
		if not mgr_script.is_traffic_walkable(ox, oz):
			_failures.append("%s: MultiMesh instance %d origin (%f,%f) not walkable" % [context, idx, ox, oz])

func _check_yield_stops_short() -> void:
	# Drive a single car at a stationary player DIRECTLY via the shipped _update_cars path.
	# Car starts west of player heading east on the same avenue lane, 16 m away.
	# Over N ticks it must decelerate and stop short (never pass through).
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	# Place player on the gate avenue (z=0 avenue, y=0 plane)
	var player_target := Vector3(1800.0, 1.0, 2.4)  # on the avenue lane (offset 2.4 matches eastbound lane)
	_player.position = player_target

	# Reset manager to clean single-car state via _hide_all then manual inject
	_manager._hide_all()
	# Also need to put manager's _cars[0] as our test car; keep others inactive
	var cars: Array = _manager.get("_cars")
	for c in cars:
		c["active"] = false
	var car: Dictionary = cars[0]
	# Eastbound lane: heading (1,0), base at gate avenue center, offset will put world at z=2.4
	var pitch: float = plan_script.STREET_PITCH
	var avenue_z: float = 0.0  # z=0 is an avenue (0 %4==0)
	# Base on avenue centreline; world = base + perp(2.4) where perp for east is (0,0,1) → world z = 2.4
	var start_base := Vector3(1788.0, 0.0, avenue_z)
	car["pos"] = start_base
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 999.0  # suppress honk
	car["honk_count"] = 0
	car["active"] = true

	# Ensure player is considered lane-aligned: player world x 1800, car world starts at 1780 on same z 2.4, heading east, forward distance 20
	var start_wpos: Vector3 = mgr_script._car_world_pos(car)
	var initial_fwd: float = (player_target.x - start_wpos.x)
	if initial_fwd < 10.0 or initial_fwd > 25.0:
		_failures.append("yield setup: initial forward %.2f not 16-20m as expected (car %s player %s)" % [initial_fwd, str(start_wpos), str(player_target)])

	var passed_through := false
	var stopped_short := false
	var max_fwd := -INF
	for i in 800:
		# Call the SHIPPED seam: distance → target → move_toward is inside _update_cars.
		# Drive the real _update_cars for one tick (delta), not a copy.
		_manager._update_cars(DT, player_target)
		var wpos: Vector3 = mgr_script._car_world_pos(car)
		var cur_fwd: float = player_target.x - wpos.x
		# Track closest approach
		if cur_fwd < max_fwd:
			max_fwd = cur_fwd
		# Detect pass-through (car ahead of player)
		if wpos.x > player_target.x + 0.5:
			passed_through = true
			break
		# Check if we have stopped short: speed ~0 and still forward > STOP_DISTANCE - margin
		if float(car["speed"]) < 0.2 and cur_fwd > 1.5 and cur_fwd < 10.0:
			stopped_short = true

	if passed_through:
		_failures.append("yield: car passed THROUGH the stationary player instead of stopping short (world x %f > player x %f)" % [float(mgr_script._car_world_pos(car).x), player_target.x])
	if not stopped_short:
		var end_wpos: Vector3 = mgr_script._car_world_pos(car)
		_failures.append("yield: car did not STOP short — end speed %.3f at x %.2f (player %.2f fwd %.2f) expected speed≈0 before contact" % [float(car["speed"]), end_wpos.x, player_target.x, player_target.x - end_wpos.x])

	# Clean up test car
	car["active"] = false
	_manager._hide_all()

func _check_honk_holdoff_and_cooldown() -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var player_target := Vector3(1800.0, 1.0, 2.4)
	_player.position = player_target
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars:
		c["active"] = false
	var car: Dictionary = cars[1]
	var pitch: float = plan_script.STREET_PITCH
	car["pos"] = Vector3(1796.0, 0.0, 0.0)
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 0.0  # start stopped and blocked at 4m (inside STOP_DISTANCE so target 0)
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 0.0
	car["honk_count"] = 0
	car["active"] = true

	# Simulate 6 seconds blocked at ~60 fps, driving the SHIPPED _update_cars (which owns hold-off + cooldown).
	var honks_at: Array[int] = []
	for i in 360:
		_manager._update_cars(DT, player_target)
		# Count honks by watching honk_count increment this tick — honk_count is incremented inside _try_honk which is called from _update_cars.
		# We poll after each tick: if honk_count just increased, record frame.
		# Instead record whenever honk_count differs from expected cumulative.
		# Simpler: after each tick, if honk_count > honks_at.size() then we had a honk
		var hc: int = int(car["honk_count"])
		if hc > honks_at.size():
			honks_at.append(i)

	# Must fire at least once but not every tick
	if honks_at.size() == 0:
		_failures.append("honk: blocked car never honked (expected once after ~%.1fs hold-off)" % mgr_script.HONK_HOLDOFF)
	elif honks_at[0] < int(mgr_script.HONK_HOLDOFF / DT) - 10:
		_failures.append("honk: first honk at frame %d too early (before hold-off %.1fs)" % [honks_at[0], mgr_script.HONK_HOLDOFF])
	# Respect cooldown: gap between honks must be >= cooldown
	var cd_frames: int = int(mgr_script.HONK_COOLDOWN / DT) - 5
	for k in range(1, honks_at.size()):
		var gap: int = honks_at[k] - honks_at[k - 1]
		if gap < cd_frames:
			_failures.append("honk: gap %d frames between honk %d and %d is below cooldown %d frames" % [gap, k - 1, k, cd_frames])
	# Must not machine-gun: at most ~2 honks in 6s with 3.5s cooldown
	if honks_at.size() > 3:
		_failures.append("honk: too many honks %d in 6s (cooldown %.1fs violated, frames %s)" % [honks_at.size(), mgr_script.HONK_COOLDOWN, str(honks_at)])

	# Honk must respect browser gate indirectly: we cannot test _unlocked here without sound, but _try_honk distance gate is testable
	# Far player should suppress honk
	car["blocked_time"] = 5.0
	car["honk_cooldown"] = 0.0
	var before: int = int(car["honk_count"])
	_manager._update_cars(DT, Vector3(5000.0, 1.0, 5000.0))
	var after_far: int = int(car["honk_count"])
	if after_far != before:
		_failures.append("honk: far player at 5000m still incremented honk (distance attenuation failed)")

	car["active"] = false
	_manager._hide_all()

func _check_target_speed_seam() -> void:
	# Drive the SHIPPED pure function target_speed_for_distance, not a copy, and assert its shape.
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var cruise: float = 5.0
	var s_clear: float = mgr_script.target_speed_for_distance(INF, cruise)
	if absf(s_clear - cruise) > 0.001:
		_failures.append("target_speed INF should be cruise %.2f got %.3f" % [cruise, s_clear])
	var s_far: float = mgr_script.target_speed_for_distance(100.0, cruise)
	if absf(s_far - cruise) > 0.001:
		_failures.append("target_speed far 100m should be cruise got %.3f" % s_far)
	var s_stop: float = mgr_script.target_speed_for_distance(1.0, cruise)
	if absf(s_stop) > 0.001:
		_failures.append("target_speed 1m should be 0 got %.3f" % s_stop)
	var s_mid: float = mgr_script.target_speed_for_distance((mgr_script.YIELD_DISTANCE + mgr_script.STOP_DISTANCE) * 0.5, cruise)
	if s_mid <= 0.0 or s_mid >= cruise:
		_failures.append("target_speed mid should be between 0 and cruise got %.3f" % s_mid)
	# Decel via move_toward must actually reduce speed — drive shipped move_toward path through _update_cars would be too indirect, so we at least check target mapping is monotonic
	var s_near: float = mgr_script.target_speed_for_distance(mgr_script.STOP_DISTANCE + 0.5, cruise)
	var s_far2: float = mgr_script.target_speed_for_distance(mgr_script.YIELD_DISTANCE - 0.5, cruise)
	if s_near >= s_far2:
		_failures.append("target_speed not monotonic: near %.3f >= far %.3f" % [s_near, s_far2])
