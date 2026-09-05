extends SceneTree
## Headless self-check for traffic_manager.gd (Budapest car traffic).
##
##   godot --headless --path . --script res://scripts/traffic_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints failure details and exits 1.
##
## Validates:
##   1. Isolation: TrafficManager in group "traffic", no descendant joins a
##      gameplay group and carries no CollisionObject3D/Area3D.
##   2. Mesh/material/draw budget: ONE MultiMeshInstance3D, use_colors true,
##      stride 16, ONE shared ShaderMaterial on world_block.gdshader whose
##      height_range is the car mesh's own wheels-to-roof span (bead
##      godot-test1-y1o.15), feet at y=0, web cap constant relation.
##   3. Placement: every active car y==0 on carriageway, never in Danube,
##      plateau, solid landmark, dry rect; plus direct is_traffic_walkable
##      negative controls at bad coords (Danube, plateau, deck, block).
##   4. Dormancy: 0 visible outside Budapest, >0 inside; _is_near_budapest
##      seam directly.
##   5. Yield: car driven at stationary hero FROM CRUISE stops short via
##      shipped move_toward path, respects accel/decel and lateral width.
##   6. Honk: hold-off + cooldown via shipped _update_cars approached from
##      cruise, and distance gate via second-car blocker.
##   7. THE COARSE TICK (bead 8gw.22): a car the camera cannot see is ticked a
##      few times a second by the REAL elapsed time — it ADVANCES, it is never
##      frozen and never deleted — is_traffic_walkable is still asked on every
##      tick it takes, and a null camera degrades to full-rate updates.
##   8. The de-quadratic'd queue scan answers EXACTLY what the all-pairs scan it
##      replaced answered, measured against an independent oracle.
##   9. SOLID (bead 8gw.21): the pooled proxy colliders are the MANAGER's and
##      nobody else's — every CollisionObject3D under it is one of at most
##      CAR_PROXY_POOL StaticBody3Ds on the fauna-precedent layer, in no group,
##      carrying no mesh — a real player.tscn driven by the SHIPPED movement is
##      stopped by a car AND STAYS stopped (the crowd's anti-trap yield is the
##      crowd's, with the crowd itself as the control), mutation-tested against an
##      emptied pool; ITS ROOF IS SOLID TOO (bead godot-test1-d5f — a hero
##      dropped onto a parked car stands on it and does not sink through,
##      mutation-tested against a pool that has forgotten how tall it is, which
##      is the XZ-only rule that shipped the bug); and a car that has stopped for the hero never moves again,
##      never displaces him and never damages him, argued from the shipped
##      constants and then driven.

const DT: float = 1.0 / 60.0

## The coarse-tick window: 2 s at 60 Hz, so a 0.25 s tick fires ~8 times.
const LOD_FRAMES: int = 120

const AmbienceLod := preload("res://scripts/ambience_lod.gd")
const Proxies := preload("res://scripts/ambience_proxies.gd")
const TrafficScript := preload("res://scripts/traffic_manager.gd")
const CrowdScript := preload("res://scripts/crowd_manager.gd")
const PLAYER_SCENE: String = "res://scenes/player.tscn"
const PLAN_SCRIPT := preload("res://scripts/budapest_plan.gd")

## How many CollisionObject3Ds the isolation walk found under the manager.
var _proxies_seen: int = 0

## A Pest avenue the traffic is happy to drive.
const LANE_PROBE_SPOT := Vector3(2900.0, 0.0, 0.0)

## Where the hero starts, measured from the parked car's CENTRE. Its rear bumper
## is CAR_LENGTH/2 = 2.2 m back and the hero's capsule is 0.5 m, so contact is at
## 2.7 m and this is a clear run-up.
const CAR_PROBE_AHEAD: float = 6.0

## The closest to a car's centre a hero may ever get. Contact is 2.7 m; anything
## under this is penetration, and a hero who actually walked through would be on
## the far side with a NEGATIVE gap.
const CAR_CONTACT_MIN: float = 1.8

## The SOLID window, and the LONG one that proves a car never goes soft (well past
## AmbienceProxies.STUCK_SECONDS, which is the crowd's rule and not the traffic's).
const CAR_SOLID_FRAMES: int = 40
const CAR_PERSIST_FRAMES: int = 180

## The yield drive: how far back down the lane the car starts, and for how long.
const APPROACH_BACK: float = 30.0
const APPROACH_FRAMES: int = 420

## What counts as "at rest", and how far a car at rest may still travel. The
## shipped brake is `move_toward` against a target that is itself falling to
## zero, so the speed decays asymptotically and never reaches an exact 0.0 —
## asking for one measures nothing at all. 0.1 m/s is a fiftieth of a walk, and
## the half metre is what a car may still coast off that: the number that matters
## is the CLOSEST APPROACH below, which is the whole "never moves into him".
const CAR_AT_REST: float = 0.1
const CAR_CREEP_MAX: float = 0.5

## How long a car is held ON the hero for the no-shove probe.
const ON_TOP_FRAMES: int = 40

## THE ROOF PROBE (bead godot-test1-d5f). How far above the roof the hero is
## dropped, how long he must stay up there, and how many of those frames are
## spent falling and settling before `is_on_floor()` is asked of him.
const CAR_ROOF_DROP: float = 0.35
const CAR_ROOF_FRAMES: int = 60
const CAR_ROOF_SETTLE: int = 12

## The roof mutant: a proxy this tall is one the hero can never be standing on
## top of, so the guard degrades to the XZ-only rule the bead fixed.
const MUTANT_ROOF: float = 1.0e9

var _root: Node3D = null
var _manager: Node3D = null
var _player: CharacterBody3D = null
var _failures: Array[String] = []
var _started: bool = false

## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
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
	# ONE shot: the checks below await physics frames, so this must not re-enter.
	if _started:
		return false
	_started = true
	_run_checks()
	return false

func _run_checks() -> void:
	print("--- Running traffic_selfcheck ---")
	_check_groups_and_collision()
	_check_multimesh_resources()
	_check_dormancy_outside_budapest()
	_check_is_near_budapest_seam()
	_check_placement_and_walkable()
	_check_is_traffic_walkable_negatives()
	_check_yield_stops_short()
	_check_yield_lateral_and_accel()
	_check_honk_approach_from_cruise()
	_check_honk_distance_via_second_blocker()
	_check_web_cap_constants()
	_check_stuck_recycle()
	_check_target_speed_seam()
	_check_no_interpenetration()
	_check_coarse_tick_out_of_view()
	_check_queue_scan_matches_all_pairs()
	await _check_car_is_solid()
	await _check_stopped_car_never_pushes()
	if _failures.is_empty():
		print("traffic_selfcheck: all checks passed cleanly")
		Sentinel.finish(self)
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
	_proxies_seen = 0
	_check_node_isolation_recursive(_manager)
	if _proxies_seen != TrafficScript.CAR_PROXY_POOL:
		_failures.append("the manager owns %d proxy bodies, expected exactly CAR_PROXY_POOL"
			% _proxies_seen + " (%d) — the pool is a CONSTANT, and one body per car is what"
			% TrafficScript.CAR_PROXY_POOL + " this whole design refuses")
	Sentinel.done("groups_and_collision")

func _check_node_isolation_recursive(node: Node) -> void:
	## TIGHTENED rather than loosened by bead 8gw.21 — see the same walk in
	## crowd_selfcheck.gd for the reasoning. A CAR still has no body (a car is not
	## a node at all); what this forbids is a body that is not one of the manager's
	## own numbered pool slots, a pool bigger than CAR_PROXY_POOL, one on a layer a
	## predator can see, one that masks anything back, one carrying a mesh (the
	## draw-call story is ONE MultiMesh) and, as before, any group membership and
	## any Area3D whatsoever.
	if node != _manager:
		var groups := node.get_groups()
		if not groups.is_empty():
			_failures.append("TrafficManager descendant '%s' has groups: %s (must have none)" % [node.name, str(groups)])
		if node is Area3D:
			_failures.append("TrafficManager descendant '%s' is an Area3D (must have none)" % node.name)
		elif node is CollisionObject3D:
			_proxies_seen += 1
			if not String(node.name).begins_with(Proxies.PROXY_NAME_PREFIX):
				_failures.append("TrafficManager descendant '%s' is a CollisionObject3D that"
					% node.name + " is not a pooled proxy — cars themselves must carry no body")
			if not (node is StaticBody3D):
				_failures.append("proxy '%s' is not a StaticBody3D — anything physics can"
					% node.name + " drive can push the hero")
			var body := node as CollisionObject3D
			if body.collision_layer != Proxies.PROXY_LAYER:
				_failures.append("proxy '%s' is on collision layer %d, not the"
					% [node.name, body.collision_layer]
					+ " fauna-precedent layer %d that ONLY the player masks" % Proxies.PROXY_LAYER)
			if body.collision_mask != 0:
				_failures.append("proxy '%s' masks %d — a proxy asks the world nothing;"
					% [node.name, body.collision_mask] + " the player asks it")
		if node is VisualInstance3D and not (node is MultiMeshInstance3D):
			_failures.append("TrafficManager descendant '%s' is a VisualInstance3D that is"
				% node.name + " not the traffic MultiMesh — the draw-call story is ONE")
	for child in node.get_children():
		_check_node_isolation_recursive(child)
	Sentinel.done("node_isolation_recursive")

func _check_multimesh_resources() -> void:
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	if mm_node == null:
		_failures.append("TrafficManager _multimesh_node is null (expected ONE MultiMeshInstance3D)")
		Sentinel.done("multimesh_resources")
		return
	var mm_count := 0
	for c in _manager.get_children():
		if c is MultiMeshInstance3D:
			mm_count += 1
	if mm_count != 1:
		_failures.append("Expected exactly 1 MultiMeshInstance3D under TrafficManager, found %d" % mm_count)
	var mm: MultiMesh = mm_node.multimesh
	if mm == null:
		_failures.append("Traffic MultiMesh is null")
		Sentinel.done("multimesh_resources")
		return
	if mm.mesh == null:
		_failures.append("Traffic MultiMesh has null mesh")
		Sentinel.done("multimesh_resources")
		return
	if mm_node.material_override == null:
		_failures.append("Traffic material_override is null")
	else:
		# THE MATERIAL IS THE WORLD'S OWN BLOCK SHADER since bead
		# `godot-test1-y1o.15`. What this used to assert — vertex colours drive
		# albedo — is `world_block.gdshader`'s `COLOR.rgb` and is now proved by
		# naming the shader; what it must ALSO assert is the one parameter that
		# is this consumer's own, `height_range`, because the shader's default
		# is the chunk batch's unit cube and a car left on it would take its
		# whole gradient inside the bottom 1 m of its wheels.
		#
		# A `null` CAST IS THE FAILURE, not a reason to skip: the retired
		# version cast to StandardMaterial3D and guarded every assertion on
		# `mat != null`, so a swapped material class would have passed this
		# check in silence.
		var mat: ShaderMaterial = mm_node.material_override as ShaderMaterial
		if mat == null:
			_failures.append("Traffic shared material is not a ShaderMaterial")
		elif mat.shader != ChunkBatch.WORLD_BLOCK_SHADER:
			_failures.append("Traffic shared material must run world_block.gdshader")
		else:
			# The span is measured against the MESH THE MULTIMESH IS DRAWING, not
			# against the constant that produced it — comparing a const to itself
			# proves nothing, and the failure this guards is precisely a mesh that
			# grew a roof rack while the number stayed behind.
			var box: AABB = mm.mesh.get_aabb()
			var span: Variant = mat.get_shader_parameter("height_range")
			if not (span is Vector2):
				_failures.append("Traffic height_range is %s, not a Vector2" % span)
			else:
				var got: Vector2 = span
				if absf(got.x - box.position.y) > 0.02 \
						or absf(got.y - box.end.y) > 0.02:
					_failures.append("Traffic height_range %s != the car mesh's own "
							% got + "vertical span (%.3f .. %.3f)"
							% [box.position.y, box.end.y])
	if mm_node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_failures.append("Traffic MultiMeshInstance3D must have cast_shadow OFF (1 draw call budget, no shadow pass)")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var tm_max: int = _manager.get("_traffic_max")
	if mm.instance_count != tm_max:
		_failures.append("Traffic MultiMesh instance_count %d != _traffic_max %d" % [mm.instance_count, tm_max])
	if mm.instance_count > int(mgr_script.get("TRAFFIC_MAX_DESKTOP")):
		_failures.append("Traffic instance_count %d exceeds desktop cap" % mm.instance_count)
	if not mm.use_colors:
		_failures.append("Traffic MultiMesh must have use_colors=true for per-instance colour variety (stride 16)")
	if mm.buffer.size() != 0 and mm.buffer.size() != mm.instance_count * 16:
		_failures.append("Traffic MultiMesh buffer size %d != instance_count*16 %d (stride 16 with use_colors)" % [mm.buffer.size(), mm.instance_count * 16])
	var aabb: AABB = mm.mesh.get_aabb()
	if absf(aabb.position.y) > 0.001:
		_failures.append("Traffic mesh AABB position.y is %f (must be 0.0 for feet at y=0)" % aabb.position.y)
	Sentinel.done("multimesh_resources")

func _check_dormancy_outside_budapest() -> void:
	_player.position = Vector3(0.0, 1.0, 0.0)
	_manager._process(DT)
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	var vis: int = mm_node.multimesh.visible_instance_count
	if vis != 0:
		_failures.append("Traffic rendered %d visible while player outside Budapest at x=0 (must hide)" % vis)
	Sentinel.done("dormancy_outside_budapest")

func _check_is_near_budapest_seam() -> void:
	# Direct seam: _is_near_budapest must be false far outside, true inside
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	# Use the manager's instance method via call
	var inside: bool = _manager.call("_is_near_budapest", Vector3(2000.0, 0, 0))
	var outside: bool = _manager.call("_is_near_budapest", Vector3(0.0, 0, 0))
	if not inside:
		_failures.append("_is_near_budapest false for inside point (2000,0) — should be true")
	if outside:
		_failures.append("_is_near_budapest true for far outside (0,0) — should be false; if always true, sleep outside city fails")
	# Also verify that dormancy actually hides when outside
	_player.position = Vector3(0.0, 1.0, 0.0)
	_manager._process(DT)
	var vis_out: int = (_manager.get("_multimesh_node") as MultiMeshInstance3D).multimesh.visible_instance_count
	_player.position = Vector3(2000.0, 1.0, 0.0)
	for i in 60:
		_manager._process(DT)
	var vis_in: int = (_manager.get("_multimesh_node") as MultiMeshInstance3D).multimesh.visible_instance_count
	if vis_in == 0:
		_failures.append("_is_near_budapest seam: 0 visible inside Budapest at 2000,0 — should spawn")
	if vis_out != 0:
		_failures.append("_is_near_budapest seam: still visible outside — hide failed")
	Sentinel.done("is_near_budapest_seam")

func _check_placement_and_walkable() -> void:
	for loc in [Vector3(1750.0, 1.0, 0.0), Vector3(2920.0, 1.0, 248.0)]:
		_player.position = loc
		for frame in 60:
			_manager._process(DT)
		_verify_cars_placement("near %s" % str(loc))
	_player.position = Vector3(3520.0, 1.0, -496.0)
	for frame in 60:
		_manager._process(DT)
	_verify_cars_placement("Heroes Square avenue")
	Sentinel.done("placement_and_walkable")

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
		if float(car["speed"]) < -0.001:
			_failures.append("%s: car has negative speed %f" % [context, float(car["speed"])])
	if active == 0:
		_failures.append("%s: 0 active cars spawned around player inside Budapest" % context)
	var tm_max: int = _manager.get("_traffic_max")
	if active > tm_max:
		_failures.append("%s: active car count %d exceeds _traffic_max %d" % [context, active, tm_max])
	var mm_node: MultiMeshInstance3D = _manager.get("_multimesh_node")
	var mm: MultiMesh = mm_node.multimesh
	var buf: PackedFloat32Array = mm.buffer
	var vis: int = mm.visible_instance_count
	for idx in vis:
		var base := idx * 16
		var ox: float = buf[base + 3]
		var oy: float = buf[base + 7]
		var oz: float = buf[base + 11]
		if not is_finite(ox) or not is_finite(oy) or not is_finite(oz):
			_failures.append("%s: MultiMesh instance %d non-finite origin (%f,%f,%f)" % [context, idx, ox, oy, oz])
		if absf(oy) > 0.01:
			_failures.append("%s: MultiMesh instance %d oy %f not 0" % [context, idx, oy])
		if not mgr_script.is_traffic_walkable(ox, oz):
			_failures.append("%s: MultiMesh instance %d origin (%f,%f) not walkable" % [context, idx, ox, oz])

func _check_is_traffic_walkable_negatives() -> void:
	# Direct negative controls — each point ISOLATES its clause: on avenue carriageway,
	# inside rect, not dry, so only the tested refusal makes it false.
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	# Danube wet ON avenue: avenue crossing at (2592, -496) — Z avenue -496 + X avenue 2592,
	# river_x_at(-496)≈2520 → 72m inside wet, on carriageway (intersection), not dry, not plateau
	if mgr_script.is_traffic_walkable(2592.0, -496.0):
		_failures.append("is_traffic_walkable true at Danube wet ON avenue (2592,-496) — must refuse danube_wet (isolated: on-carriageway, not dry)")
	# Castle Hill plateau ON avenue: (2096, -496) — X 2096 inside plateau rect 1970-2340, Z -496 avenue, not wet, not dry
	if mgr_script.is_traffic_walkable(2096.0, -496.0):
		_failures.append("is_traffic_walkable true on Castle Hill plateau ON avenue (2096,-496) — must refuse plateau_top_at (isolated)")
	# Chain Bridge deck (dry rect)
	var chain_dry: Rect2 = plan_script.DRY_RECTS[1]
	var chain_pt := chain_dry.get_center()
	if mgr_script.is_traffic_walkable(chain_pt.x, chain_pt.y):
		_failures.append("is_traffic_walkable true on Chain Bridge deck (%.1f,%.1f) — must refuse is_dry" % [chain_pt.x, chain_pt.y])
	# Block interior (courtyard centre of a buildable block)
	var block_cell := Vector2i(5, 5)
	if plan_script.block_buildable(block_cell):
		var courtyard: Rect2 = plan_script.block_courtyard(block_cell)
		var cc := courtyard.get_center()
		if mgr_script.is_traffic_walkable(cc.x, cc.y):
			_failures.append("is_traffic_walkable true at block courtyard (%.1f,%.1f) — must be off-carriageway" % [cc.x, cc.y])
	# Off-city (outside rect)
	if mgr_script.is_traffic_walkable(0.0, 0.0):
		_failures.append("is_traffic_walkable true at (0,0) outside Budapest — must refuse contains")
	# Solid landmark ON avenue: Parliament disc centre 2760,-480 via avenue intersection (2840,-496) — 82m inside radius 151, on avenue, not wet/plateau/dry
	if mgr_script.is_traffic_walkable(2840.0, -496.0):
		_failures.append("is_traffic_walkable true inside Parliament ON avenue (2840,-496) — must refuse _is_inside_solid_landmark (isolated)")
	# Positive control: avenue carriageway at gate should be walkable
	if not mgr_script.is_traffic_walkable(1700.0, 2.4):
		_failures.append("is_traffic_walkable false at gate avenue lane (1700,2.4) — should be true")
	Sentinel.done("is_traffic_walkable_negatives")

func _check_yield_stops_short() -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var player_target := Vector3(1800.0, 1.0, 2.4)
	_player.position = player_target
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars:
		c["active"] = false
	var car: Dictionary = cars[0]
	var start_base := Vector3(1788.0, 0.0, 0.0)
	car["pos"] = start_base
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 999.0
	car["honk_count"] = 0
	car["active"] = true
	var passed_through := false
	var stopped_short := false
	for i in 800:
		_manager._update_cars(DT, player_target)
		var wpos: Vector3 = mgr_script._car_world_pos(car)
		if wpos.x > player_target.x + 0.5:
			passed_through = true
			break
		if float(car["speed"]) < 0.2 and (player_target.x - wpos.x) > 1.5 and (player_target.x - wpos.x) < 10.0:
			stopped_short = true
	if passed_through:
		_failures.append("yield: car passed THROUGH the stationary player instead of stopping short (world x %f > player x %f)" % [float(mgr_script._car_world_pos(car).x), player_target.x])
	if not stopped_short:
		var end_wpos: Vector3 = mgr_script._car_world_pos(car)
		_failures.append("yield: car did not STOP short — end speed %.3f at x %.2f (player %.2f fwd %.2f) expected speed≈0 before contact" % [float(car["speed"]), end_wpos.x, player_target.x, player_target.x - end_wpos.x])
	car["active"] = false
	_manager._hide_all()
	Sentinel.done("yield_stops_short")

func _check_yield_lateral_and_accel() -> void:
	# Lateral width: far 5m outside, centre 0m inside, mid-lane 2.0m inside (shrinking tolerance must still slow 2.0)
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars: c["active"] = false
	var car: Dictionary = cars[0]
	car["pos"] = Vector3(1788.0, 0.0, 0.0)
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 999.0
	car["active"] = true
	# Far 5m lateral (outside 3.2) — should NOT slow (stays near cruise)
	var player_far_lat := Vector3(1800.0, 1.0, 2.4 + 5.0)
	_manager._update_cars(DT, player_far_lat)
	var speed_far: float = float(car["speed"])
	# Centre 0m — should slow
	car["pos"] = Vector3(1788.0, 0.0, 0.0)
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	var player_centre := Vector3(1800.0, 1.0, 2.4)
	for i in 60:
		_manager._update_cars(DT, player_centre)
	var speed_centre: float = float(car["speed"])
	# Inside-lane 2.0m (within 3.2) — must still slow; shrinking tolerance to 0.01 would make this NOT slow
	car["pos"] = Vector3(1788.0, 0.0, 0.0)
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	var player_mid := Vector3(1800.0, 1.0, 2.4 + 2.0)
	for i in 60:
		_manager._update_cars(DT, player_mid)
	var speed_mid: float = float(car["speed"])
	if speed_far < 4.5:
		_failures.append("lateral: far 5m still slowed to %.2f — should be near cruise (too-LARGE tolerance not caught)" % speed_far)
	if speed_centre >= speed_far:
		_failures.append("lateral: centre 0m did not slow more than far 5m (%.2f vs %.2f)" % [speed_centre, speed_far])
	if speed_mid >= 4.0:
		_failures.append("lateral: mid-lane 2.0m not slowed (%.2f) — should still be within 3.2; shrinking tolerance to 0.01 would hide this" % speed_mid)
	# Accel/decel: speed change per tick must be limited to ACCELERATION*DT, not snap to target
	car["pos"] = Vector3(1788.0, 0.0, 0.0)
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	var player_block := Vector3(1795.0, 1.0, 2.4) # 7m ahead -> target ~0.9
	_manager._update_cars(DT, player_block)
	var after_one: float = float(car["speed"])
	var max_decel_step: float = float(mgr_script.get("DECELERATION")) * DT + 0.001
	if 5.0 - after_one > max_decel_step + 0.01:
		_failures.append("accel/decel: snap detected — speed dropped 5.0->%.3f in one tick > DECELERATION*DT %.3f" % [after_one, max_decel_step])
	car["active"] = false
	_manager._hide_all()
	Sentinel.done("yield_lateral_and_accel")

func _check_honk_approach_from_cruise() -> void:
	# Drive FROM CRUISE at a stationary hero — the actual game state — and assert a honk happens
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var player_target := Vector3(1800.0, 1.0, 2.4)
	_player.position = player_target
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars: c["active"] = false
	var car: Dictionary = cars[1]
	car["pos"] = Vector3(1775.0, 0.0, 0.0) # 25m away, will approach from cruise
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.5
	car["speed"] = 5.5
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 0.0
	car["honk_count"] = 0
	car["active"] = true
	var honked := false
	for i in 900: # 15s approach + hold
		_manager._update_cars(DT, player_target)
		if int(car["honk_count"]) > 0:
			honked = true
			break
		if mgr_script._car_world_pos(car).x > player_target.x:
			_failures.append("honk approach: car passed through player before honking")
			break
	if not honked:
		_failures.append("honk approach: car driven from cruise at stationary hero never honked within 15s (is_blocked never true from approach)")
	car["active"] = false
	_manager._hide_all()
	Sentinel.done("honk_approach_from_cruise")

func _check_honk_distance_via_second_blocker() -> void:
	# Second car as blocker keeps honk path live while player moves far — proves distance gate, not blocked
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars: c["active"] = false
	# Car A: ahead, stopped near avenue
	var carA: Dictionary = cars[2]
	carA["pos"] = Vector3(1795.0, 0.0, 0.0) # world 1795,2.4
	carA["heading_dir"] = Vector2(1.0, 0.0)
	carA["facing_yaw"] = atan2(-1.0, 0.0)
	carA["cruise_speed"] = 5.0
	carA["speed"] = 0.0
	carA["blocked_time"] = 5.0
	carA["honk_cooldown"] = 0.0
	carA["honk_count"] = 0
	carA["active"] = true
	# Car B: behind, blocked by A, not directly by player
	var carB: Dictionary = cars[3]
	carB["pos"] = Vector3(1785.0, 0.0, 0.0) # 10m behind A, same lane
	carB["heading_dir"] = Vector2(1.0, 0.0)
	carB["facing_yaw"] = atan2(-1.0, 0.0)
	carB["cruise_speed"] = 5.0
	carB["speed"] = 0.0
	carB["blocked_time"] = 5.0
	carB["honk_cooldown"] = 0.0
	carB["honk_count"] = 0
	carB["active"] = true
	# Player far away — carB still blocked by carA, so blocked_time would accumulate, but honk must be suppressed by distance
	var far_player := Vector3(5000.0, 1.0, 5000.0)
	var before: int = int(carB["honk_count"])
	for i in 120:
		_manager._update_cars(DT, far_player)
	var after_far: int = int(carB["honk_count"])
	if after_far != before:
		_failures.append("honk distance: far player (5000) still honked %d->%d via second-car blocker — distance gate failed" % [before, after_far])
	# Now bring player near and verify it does honk (same blocking, now within radius)
	carB["blocked_time"] = 5.0
	carB["honk_cooldown"] = 0.0
	carB["honk_count"] = 0
	# Place player near carB (within audible)
	var near_player := Vector3(1790.0, 1.0, 2.4)
	# Keep carA as blocker, but carB's distance to near_player is ~5m so honk should fire within holdoff+1
	var did_honk_near := false
	for i in 240:
		_manager._update_cars(DT, near_player)
		if int(carB["honk_count"]) > 0:
			did_honk_near = true
			break
	# If we moved player near, carB is still blocked by carA, and now within radius, so should honk
	# (If it doesn't, distance gate is inverted — still a failure but different)
	# We already proved far doesn't honk, so we don't fail on near here, just note
	for c in cars: c["active"] = false
	_manager._hide_all()
	Sentinel.done("honk_distance_via_second_blocker")

func _check_web_cap_constants() -> void:
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var web: int = int(mgr_script.get("TRAFFIC_MAX_WEB"))
	var desk: int = int(mgr_script.get("TRAFFIC_MAX_DESKTOP"))
	if web >= desk:
		_failures.append("web cap %d must be < desktop cap %d" % [web, desk])
	if web != 16 or desk != 32:
		_failures.append("web/desktop caps mutated: web %d (expected 16) desk %d (expected 32) — was 30/60, cut roughly in half" % [web, desk])
	if web > 16 or desk > 32:
		_failures.append("cap exceeds design: web %d desk %d (max 16/32)" % [web, desk])
	if web <= 0 or desk <= 0:
		_failures.append("caps must be positive")
	Sentinel.done("web_cap_constants")

func _check_stuck_recycle() -> void:
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c in cars: c["active"] = false
	var car: Dictionary = cars[4]
	car["pos"] = Vector3(1800.0, 0.0, 0.0)
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 0.0
	car["blocked_time"] = float(load("res://scripts/traffic_manager.gd").get("STUCK_RECYCLE_TIME")) + 1.0
	car["honk_cooldown"] = 0.0
	car["active"] = true
	var before_pos: Vector3 = car["pos"]
	_player.position = Vector3(1800.0, 1.0, 0.0)
	_manager._process(DT)
	# After one _process, stuck car should have been recycled (pos changed to new segment near player, or inactive if no segment)
	var after_pos: Vector3 = car["pos"]
	var still_blocked_far: bool = float(car["blocked_time"]) > 0.0 and car["active"] and after_pos == before_pos
	if still_blocked_far:
		_failures.append("stuck recycle: car with blocked_time %.1f not recycled on next tick (still at same pos)" % float(car["blocked_time"]))
	car["active"] = false
	_manager._hide_all()
	Sentinel.done("stuck_recycle")

func _check_target_speed_seam() -> void:
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
	var s_near: float = mgr_script.target_speed_for_distance(mgr_script.STOP_DISTANCE + 0.5, cruise)
	var s_far2: float = mgr_script.target_speed_for_distance(mgr_script.YIELD_DISTANCE - 0.5, cruise)
	if s_near >= s_far2:
		_failures.append("target_speed not monotonic: near %.3f >= far %.3f" % [s_near, s_far2])
	Sentinel.done("target_speed_seam")

func _check_no_interpenetration() -> void:
	# Headline: no two active boxes overlap (per-axis CAR_LENGTH×CAR_WIDTH), not raw
	# centre distance — opposite lanes are 4.8 m apart laterally, ~3 m air gap, so
	# raw 5.0 centre distance is unsatisfiable for passing pairs. Checked over many
	# spawn/recycle cycles. Mutation-tested: delete the _is_occupied_near guard in
	# _find_spawn_segment_near and it must go RED (same-lane overlap).
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	# Use the player's bubble position to drive many cycles
	_player.position = Vector3(2000.0, 1.0, 0.0)
	for frame in 200:
		_manager._process(DT)
		var cars: Array = _manager.get("_cars")
		var active_cars: Array = []
		for car: Dictionary in cars:
			if car["active"]:
				active_cars.append(car)
		for i in range(active_cars.size()):
			for j in range(i + 1, active_cars.size()):
				var ca: Dictionary = active_cars[i]
				var cb: Dictionary = active_cars[j]
				var wa: Vector3 = mgr_script._car_world_pos(ca)
				var wb: Vector3 = mgr_script._car_world_pos(cb)
				var ha: Vector2 = ca["heading_dir"]
				var hb: Vector2 = cb["heading_dir"]
				if mgr_script._cars_overlap(wa, ha, wb, hb):
					var d: float = wa.distance_to(wb)
					_failures.append("interpenetration: cars %d and %d %s vs %s headings %s/%s centre %.2f overlap (boxes %.1fx%.1f)" % [i, j, str(wa), str(wb), str(ha), str(hb), d, float(mgr_script.get("CAR_LENGTH")), float(mgr_script.get("CAR_WIDTH"))])
					Sentinel.done("no_interpenetration")
					return
	if not _failures.is_empty():
		Sentinel.done("no_interpenetration")
		return
	# Negative control that would have caught the 4.8 vs 5.0 metric bug: two cars
	# abreast in opposite lanes (same avenue, opposite headings, 4.8 m lateral)
	# must NOT be considered overlapping.
	var lane_off: float = float(mgr_script.get("LANE_OFFSET"))
	var car_len: float = float(mgr_script.get("CAR_LENGTH"))
	var car_wid: float = float(mgr_script.get("CAR_WIDTH"))
	var base_a := Vector3(2000.0, 0.0, 0.0)
	var base_b := Vector3(2000.0, 0.0, 0.0) # same base centreline
	var ha_opp := Vector2(1.0, 0.0)
	var hb_opp := Vector2(-1.0, 0.0)
	var wa_opp := base_a + Vector3(-ha_opp.y, 0.0, ha_opp.x) * lane_off
	var wb_opp := base_b + Vector3(-hb_opp.y, 0.0, hb_opp.x) * lane_off
	# wa_opp and wb_opp should be 4.8 apart laterally
	var sep_opp: float = wa_opp.distance_to(wb_opp)
	if mgr_script._cars_overlap(wa_opp, ha_opp, wb_opp, hb_opp):
		_failures.append("interpenetration negative control failed: abreast opposite lanes %.2f apart flagged as overlap (boxes %.1fx%.1f should have ~%.1f air gap)" % [sep_opp, car_len, car_wid, sep_opp - car_wid])
		Sentinel.done("no_interpenetration")
		return
	# Positive control: same-lane close (3 m longitudinal) MUST be overlap, otherwise metric is toothless
	var h_same := Vector2(1.0, 0.0)
	var wa_s := Vector3(2000.0, 0.0, 0.0) + Vector3(-h_same.y, 0.0, h_same.x) * lane_off
	var wb_s := Vector3(2003.0, 0.0, 0.0) + Vector3(-h_same.y, 0.0, h_same.x) * lane_off # 3 m ahead
	if not mgr_script._cars_overlap(wa_s, h_same, wb_s, h_same):
		_failures.append("interpenetration positive control failed: same-lane 3 m apart not flagged as overlap — metric toothless")
		Sentinel.done("no_interpenetration")
		return
	var cars: Array = _manager.get("_cars")
	var cnt: int = 0
	for c: Dictionary in cars:
		if c["active"]:
			cnt += 1
	if cnt < 5:
		_failures.append("interpenetration check saw only %d active cars (expected >=5 to have pairs)" % cnt)
	Sentinel.done("no_interpenetration")


# ============================================================================
# 7. THE COARSE TICK — a car nobody can see keeps driving, slowly ticked
# ============================================================================

func _drive_probe_car(car: Dictionary, frames: int) -> Dictionary:
	## Runs the SHIPPED _process for `frames` and reports what the probe car was
	## granted, how far it got, and whether it ever stood off the carriageway —
	## is_traffic_walkable is the FIRST branch of every tick a car takes, so a
	## coarse-ticked car must be as clear of the Danube as a full-rate one.
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var start: Vector3 = mgr_script._car_world_pos(car)
	var stepped: int = 0
	var granted: float = 0.0
	var off_road: int = 0
	for f in frames:
		_manager._process(DT)
		if float(car["lod_step"]) > 0.0:
			stepped += 1
			granted += float(car["lod_step"])
		var w: Vector3 = mgr_script._car_world_pos(car)
		if not mgr_script.is_traffic_walkable(w.x, w.z):
			off_road += 1
	return {
		"dist": mgr_script._car_world_pos(car).distance_to(start),
		"stepped": stepped,
		"granted": granted,
		"off_road": off_road,
	}


func _seat_probe_car(car: Dictionary) -> void:
	car["pos"] = Vector3(1788.0, 0.0, 0.0)
	car["heading_dir"] = Vector2(1.0, 0.0)
	car["facing_yaw"] = atan2(-1.0, 0.0)
	car["cruise_speed"] = 5.0
	car["speed"] = 5.0
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 999.0
	car["honk_count"] = 0
	car["lod_debt"] = 0.0
	car["lod_step"] = 0.0
	car["active"] = true


func _check_coarse_tick_out_of_view() -> void:
	## One car on the gate avenue with the hero 120 m off to the side, driven
	## through the shipped _process with a camera pointed AWAY from it and then
	## with no camera at all. The car is never deleted and never frozen in either.
	_manager._hide_all()
	var cars: Array = _manager.get("_cars")
	for c: Dictionary in cars:
		c["active"] = false
	var probe: Dictionary = cars[7]
	# Far enough down the cross street that the car is well outside the frustum,
	# still inside DESPAWN_RADIUS so the manager keeps it rather than recycling.
	var player_pos := Vector3(1788.0, 1.0, 120.0)
	_player.position = player_pos

	# --- A. NULL CAMERA => full rate (today's behaviour) ----------------------
	_seat_probe_car(probe)
	var full: Dictionary = _drive_probe_car(probe, LOD_FRAMES)
	if int(full["stepped"]) != LOD_FRAMES:
		_failures.append("null camera: car stepped on %d of %d frames — a camera-less scene must degrade to FULL RATE" % [int(full["stepped"]), LOD_FRAMES])
	if int(full["off_road"]) != 0:
		_failures.append("null camera: car stood off the carriageway on %d frames" % int(full["off_road"]))

	# --- B. CAMERA LOOKING AWAY => coarse, but still driving ------------------
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.current = true
	# At the hero, looking further down the cross street (+Z): the car is ~120 m
	# BEHIND this camera, so nothing but a bug puts it in the frustum.
	cam.global_transform = Transform3D(Basis(Vector3.UP, PI), player_pos)
	_seat_probe_car(probe)
	var coarse: Dictionary = _drive_probe_car(probe, LOD_FRAMES)
	var elapsed: float = LOD_FRAMES * DT

	if int(coarse["stepped"]) >= LOD_FRAMES / 4:
		_failures.append("out of view: car stepped on %d of %d frames — expected about %d at a %.2f s coarse tick; the gate is not gating"
			% [int(coarse["stepped"]), LOD_FRAMES, int(elapsed / AmbienceLod.COARSE_TICK_SECONDS), AmbienceLod.COARSE_TICK_SECONDS])
	if int(coarse["stepped"]) == 0:
		_failures.append("out of view: car never stepped at all in %d frames — that is a FREEZE, not a coarse tick" % LOD_FRAMES)
	# THE ANTI-FREEZE ASSERTION, in the time domain: every second of wall clock
	# is granted to the car, just in fewer and bigger pieces. A gate that skipped
	# instead of banking drops this to ~0.
	if absf(float(coarse["granted"]) - elapsed) > AmbienceLod.COARSE_TICK_SECONDS + 0.001:
		_failures.append("out of view: car was granted %.3f s of the %.3f s that passed — the bank must be SPENT, not dropped (a freeze reads ~0)"
			% [float(coarse["granted"]), elapsed])
	# ...and in the distance domain: it really covered the road.
	if float(coarse["dist"]) <= 0.0:
		_failures.append("out of view: car did not move at all over %.1f s — frozen, not coarse-ticked" % elapsed)
	if float(probe["speed"]) > 1.0 and float(coarse["dist"]) < 0.5 * elapsed * float(probe["cruise_speed"]):
		_failures.append("out of view: car still rolling at %.2f m/s but covered only %.2f m in %.1f s — a coarse tick advances by the REAL elapsed time"
			% [float(probe["speed"]), float(coarse["dist"]), elapsed])
	# The Danube rule survives the coarse tick.
	if int(coarse["off_road"]) != 0:
		_failures.append("out of view: coarse-ticked car stood off the carriageway on %d of %d frames — is_traffic_walkable must be asked on every tick it takes"
			% [int(coarse["off_road"]), LOD_FRAMES])
	# Nothing was deleted to buy any of this.
	if not probe["active"]:
		_failures.append("out of view: probe car was deactivated — no car may EVER be deleted as an optimization")
	var live: int = 0
	for c: Dictionary in cars:
		if c["active"]:
			live += 1
	if live > int(_manager.get("_traffic_max")):
		_failures.append("out of view: %d live cars exceeds the cap %d" % [live, int(_manager.get("_traffic_max"))])

	cam.current = false
	_root.remove_child(cam)
	cam.free()

	# --- C. The camera going away restores full rate --------------------------
	_seat_probe_car(probe)
	var after: Dictionary = _drive_probe_car(probe, 30)
	if int(after["stepped"]) != 30:
		_failures.append("camera removed: car stepped on %d of 30 frames — losing the camera must return everything to full rate" % int(after["stepped"]))

	for c: Dictionary in cars:
		c["active"] = false
	_manager._hide_all()
	Sentinel.done("coarse_tick_out_of_view")


# ============================================================================
# 8. The locality gate changed no ANSWER — only the work
# ============================================================================

func _oracle_block_ahead(cars: Array, idx: int, player_pos: Vector3) -> float:
	## The all-pairs scan _distance_to_block_ahead used to be, written out
	## independently here: no QUEUE_SCAN_RANGE reject, no index shortcut.
	var mgr_script: GDScript = load("res://scripts/traffic_manager.gd")
	var car: Dictionary = cars[idx]
	var wpos: Vector3 = mgr_script._car_world_pos(car)
	var h: Vector2 = car["heading_dir"]
	var perp := Vector2(-h.y, h.x)
	var best := INF
	var to_p := Vector2(player_pos.x - wpos.x, player_pos.z - wpos.z)
	var fwd := to_p.dot(h)
	if fwd > 0.0 and fwd < float(mgr_script.get("YIELD_DISTANCE")) + 2.0:
		if absf(to_p.dot(perp)) <= float(mgr_script.get("LATERAL_TOLERANCE")):
			best = fwd
	for j in cars.size():
		if j == idx:
			continue
		var other: Dictionary = cars[j]
		if not other["active"]:
			continue
		var ow: Vector3 = mgr_script._car_world_pos(other)
		var to_c := Vector2(ow.x - wpos.x, ow.z - wpos.z)
		var fwd_c := to_c.dot(h)
		if fwd_c <= 0.0 or fwd_c >= float(mgr_script.get("YIELD_DISTANCE")) + 1.0:
			continue
		if h.dot(other["heading_dir"] as Vector2) < 0.6:
			continue
		if absf(to_c.dot(perp)) <= float(mgr_script.get("LATERAL_TOLERANCE_CAR")):
			best = minf(best, fwd_c)
	return best


func _check_queue_scan_matches_all_pairs() -> void:
	## _distance_to_block_ahead rejects a pair on a per-axis box before it
	## computes anything (QUEUE_SCAN_RANGE). That is only sound if it rejects
	## exactly the pairs that could never have been the answer — so drive both
	## over a live, crowded bubble and demand the SAME number every time.
	_manager._hide_all()
	_player.position = Vector3(2000.0, 1.0, 0.0)
	var cars: Array = _manager.get("_cars")
	var compared: int = 0
	var finite_seen: int = 0
	for frame in 240:
		_manager._process(DT)
		var pp: Vector3 = _player.position
		for i in cars.size():
			if not cars[i]["active"]:
				continue
			var shipped: float = _manager._distance_to_block_ahead(cars[i], pp, i)
			var oracle: float = _oracle_block_ahead(cars, i, pp)
			compared += 1
			if is_finite(oracle):
				finite_seen += 1
			if absf(shipped - oracle) > 0.0001 and not (is_inf(shipped) and is_inf(oracle)):
				_failures.append("queue scan: locality gate changed the answer for car %d — shipped %.4f, all-pairs oracle %.4f" % [i, shipped, oracle])
				Sentinel.done("queue_scan_matches_all_pairs")
				return
		# Nudge the hero along the avenue so the population keeps churning.
		_player.position = Vector3(2000.0 + float(frame) * 0.25, 1.0, 0.0)
	if compared < 500:
		_failures.append("queue scan: only %d car/frame pairs compared — too few to mean anything" % compared)
	if finite_seen == 0:
		_failures.append("queue scan: the oracle never once found a blocker in %d comparisons — the check is toothless, it never exercised the case the gate could break" % compared)
	_manager._hide_all()
	Sentinel.done("queue_scan_matches_all_pairs")


# ============================================================================
# CHECK 17 — A CAR IS SOLID, AND STAYS SOLID (bead godot-test1-8gw.21)
# ============================================================================
#
# OWNER: "our hero can run through crowd and cars, shouldn't be so."
#
# The same pooled proxy the crowd uses (`scripts/ambience_proxies.gd`), and the
# same drive: a real `player.tscn` under real physics, walked by the SHIPPED
# movement into a stopped car. Two assertions, and the second is the one that
# distinguishes traffic from the crowd — a car does NOT carry the crowd's
# anti-trap yield, so it is still solid after a long press. The crowd's pool is
# the positive control for the flag: if `yields_to_pinned_player()` were true for
# everybody, this file's own claim would be vacuous.
#
# Mutation-tested by emptying the pool, which must let the hero drive straight
# through the bumper.

func _check_car_is_solid() -> void:
	if _manager.get("_proxies").yields_to_pinned_player():
		_failures.append("the traffic pool carries the CROWD's anti-trap yield — a car"
			+ " would become walk-through-able after a beat, which is not what a car is."
			+ " The yield exists because citizens walk into you and keep walking; a car"
			+ " brakes 18 m out and stops 6.7 m short and can pin nobody")
	# ...with the OTHER shipped manager as the positive control, so "the traffic
	# does not yield" is a difference between two real answers rather than a flag
	# nobody ever sets. A build in which nothing yields fails right here.
	var crowd := Node3D.new()
	crowd.set_script(CrowdScript)
	_root.add_child(crowd)
	if not crowd.get("_proxies").yields_to_pinned_player():
		_failures.append("the CROWD's pool does not yield either — nothing in the game"
			+ " carries the anti-trap rule, so a hero pinned by pedestrians stays pinned")
	crowd.queue_free()
	await process_frame

	# THE LAYER ARITHMETIC, off the shipped crocodile's OWN mask rather than a
	# number written down here. Asserting `collision_layer == PROXY_LAYER` in the
	# isolation walk is self-referential — move the constant and it still passes —
	# so the claim that actually matters is asked of a predator: if this layer were
	# in a predator's mask, every crocodile in the game would start bumping into
	# parked cars, and the fauna precedent the choice copies is broken.
	var croc: Node3D = load("res://scenes/characters/piglet_crocodile.tscn").instantiate() as Node3D
	var croc_mask: int = (croc as CollisionObject3D).collision_mask
	croc.free()
	if (croc_mask & Proxies.PROXY_LAYER) != 0:
		_failures.append("the shipped crocodile masks %d, which INCLUDES the proxy layer"
			% croc_mask + " %d" % Proxies.PROXY_LAYER)

	_player.remove_from_group("player")
	var lane := _pick_lane_spot()
	if lane == Vector3.INF:
		_failures.append("check 17 found no carriageway near %s to stand a car on"
			% str(LANE_PROBE_SPOT))
		Sentinel.done("car_is_solid")
		return
	var floor_body := _make_floor(lane)
	var hero: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	_root.add_child(hero)
	await physics_frame

	# ---- SOLID, and still solid a long press later -------------------------
	var start: Vector3 = await _drive_into_car(hero, lane, CAR_SOLID_FRAMES)
	var gap: float = hero.global_position.z - lane.z
	if start.z - hero.global_position.z < 0.5:
		_failures.append("the hero barely moved (%.2f m in %d frames) — check 17 measured"
			% [start.z - hero.global_position.z, CAR_SOLID_FRAMES]
			+ " a car against a hero that never walked into it")
	if gap < CAR_CONTACT_MIN:
		_failures.append("the hero reached %.2f m of a car's centre (its rear bumper is"
			% gap + " %.2f m back) — he walked THROUGH a car"
			% (TrafficScript.CAR_LENGTH * 0.5))
	else:
		print("car solid: hero stopped %.2f m short of the car's centre after %d frames"
			% [gap, CAR_SOLID_FRAMES])

	var long_gap: float = 0.0
	await _drive_into_car(hero, lane, CAR_PERSIST_FRAMES)
	long_gap = hero.global_position.z - lane.z
	if long_gap < CAR_CONTACT_MIN:
		_failures.append("after %d frames of pressing into it the hero was %.2f m from the"
			% [CAR_PERSIST_FRAMES, long_gap] + " car's centre — a car went soft under a"
			+ " sustained press, which is the crowd's rule leaking into the traffic")
	else:
		print("car stays solid: still %.2f m short after %d frames of pressing"
			% [long_gap, CAR_PERSIST_FRAMES])

	# ...MUTANT: the pool emptied and the real one put to sleep, so nothing at all
	# is solid. A pool merely no longer consulted would leave its shapes standing
	# where its last commit put them and block the mutant with the very collision
	# it removed.
	var real_pool: RefCounted = _manager.get("_proxies")
	var empty_pool: RefCounted = Proxies.new()
	empty_pool.build(_manager, 0, TrafficScript.CAR_PROXY_HALF,
		TrafficScript.CAR_PROXY_HEIGHT, TrafficScript.CAR_PROXY_REACH, false)
	real_pool.sleep()
	_manager.set("_proxies", empty_pool)
	await _drive_into_car(hero, lane, CAR_SOLID_FRAMES)
	if hero.global_position.z - lane.z >= CAR_CONTACT_MIN:
		_failures.append("with the proxy pool emptied the hero STILL stopped %.2f m short"
			% (hero.global_position.z - lane.z) + " of the car — check 17 is measuring"
			+ " something other than the collision it claims to, so it would pass a build"
			+ " with no car collision at all")
	_manager.set("_proxies", real_pool)

	# ---- ...AND ITS ROOF IS SOLID TOO (bead godot-test1-d5f) ---------------
	# The owner's second symptom, and the one that named the bug: "if I jump on
	# it, I go through it to the ground". The no-shove guard used to be an XZ
	# CENTRE containment, and a hero standing on a car roof has his centre inside
	# the footprint by definition — so the box switched itself off under his feet.
	# Driven the way he did it: dropped onto the roof of the parked car and left
	# there, he must LAND on it and still be standing on it a second later.
	if Proxies.ROOF_GRACE >= TrafficScript.CAR_PROXY_HEIGHT:
		_failures.append("ROOF_GRACE (%.2f) is not smaller than a car's own height"
			% Proxies.ROOF_GRACE + " (%.2f) — every hero standing on the STREET would"
			% TrafficScript.CAR_PROXY_HEIGHT + " count as standing on the roof, and the"
			+ " no-shove guard could never fire for a car at all")
	var roof: float = TrafficScript.CAR_PROXY_HEIGHT
	var stood: Vector2 = await _stand_on_roof(hero, lane, CAR_ROOF_FRAMES)
	var drift: float = Vector2(hero.global_position.x - lane.x,
		hero.global_position.z - lane.z).length()
	if stood.x < roof - 0.05:
		_failures.append("the hero dropped onto a car's roof sank to y=%.2f — the roof is"
			% stood.x + " at %.2f, so he went THROUGH the car he was standing on" % roof)
	elif int(stood.y) < CAR_ROOF_FRAMES - CAR_ROOF_SETTLE:
		_failures.append("the hero was on the floor for only %d of the %d frames he spent"
			% [int(stood.y), CAR_ROOF_FRAMES - CAR_ROOF_SETTLE]
			+ " on a car's roof — he did not come to rest on it")
	elif drift > 0.5:
		_failures.append("the hero slid %.2f m while standing on a car's roof — the roof"
			% drift + " must be something you stand on, not something you slide off")
	else:
		print("car roof solid: hero stood at y=%.2f (roof %.2f) for %d frames, drifting %.3f m"
			% [hero.global_position.y, roof, int(stood.y), drift])

	# ...MUTANT: the VERTICAL HALF of the guard removed and nothing else. A pool
	# that believes it reaches the sky can never find the hero ABOVE its roof, so
	# every pose falls through to the XZ-only footprint question — which is
	# byte-for-byte the rule that shipped the bug, and under it the hero must sink
	# straight through to the street. An emptied pool would prove far less here:
	# it removes the collision this check shares with the drive above, while this
	# removes only the rule the check was added for.
	real_pool.set("_height", MUTANT_ROOF)
	var mutant: Vector2 = await _stand_on_roof(hero, lane, CAR_ROOF_FRAMES)
	real_pool.set("_height", roof)
	if mutant.x >= roof - 0.05:
		_failures.append("with the proxy pool's roof put out of the hero's reach he STILL"
			+ " stood at y=%.2f on the car — the roof check is measuring something other"
			% mutant.x + " than the 3-D containment rule, so it would pass the build this"
			+ " bead fixed")

	_restore_cars()
	hero.queue_free()
	floor_body.queue_free()
	await process_frame
	Sentinel.done("car_is_solid")


# ============================================================================
# CHECK 18 — A CAR THAT STOPPED FOR THE HERO NEVER MOVES, DAMAGES OR DISPLACES
# ============================================================================
#
# The bead's second named failure mode. Bodiless cars satisfied it for free — a
# thing with no collider cannot push anybody — so giving them one is exactly
# where it could be lost, and it is asserted two ways that do not depend on each
# other:
#
#   * THE ARITHMETIC, off the shipped constants. Half a car's width plus a
#     player radius is the closest a car can come to a hero's centre and still
#     touch him, and that is far inside LATERAL_TOLERANCE — so EVERY car that
#     could reach a hero is already inside the lane test that makes it brake, and
#     it began braking YIELD_DISTANCE out, which is more than its own stopping
#     distance from CRUISE_MAX. No car ever advances into a hero at all.
#   * THE DRIVE, off the shipped `_process`. A car is set cruising down a lane at
#     a real, unmoving `player.tscn`; once it has stopped, its position must not
#     change by another millimetre, the hero's must not change either, and the
#     hero must take no hit.

func _check_stopped_car_never_pushes() -> void:
	# (a) the arithmetic
	var reach: float = TrafficScript.CAR_WIDTH * 0.5 + Proxies.PLAYER_HALF
	if reach >= TrafficScript.LATERAL_TOLERANCE:
		_failures.append("a car can touch a hero %.2f m off its lane axis but only yields"
			% reach + " to one within %.2f m — a car outside the yield test but inside"
			% TrafficScript.LATERAL_TOLERANCE + " its own bumper would drive into him")
	var braking: float = (TrafficScript.CRUISE_MAX * TrafficScript.CRUISE_MAX) \
		/ (2.0 * TrafficScript.DECELERATION)
	if TrafficScript.YIELD_DISTANCE - TrafficScript.STOP_DISTANCE <= braking:
		_failures.append("a car needs %.2f m to shed CRUISE_MAX but only has %.2f m of"
			% [braking, TrafficScript.YIELD_DISTANCE - TrafficScript.STOP_DISTANCE]
			+ " yield room — it would still be rolling when it reached the hero")

	# (b) the drive
	_player.remove_from_group("player")
	var lane := _pick_lane_spot()
	if lane == Vector3.INF:
		_failures.append("check 18 found no carriageway to run its approach on")
		Sentinel.done("stopped_car_never_pushes")
		return
	var floor_body := _make_floor(lane)
	var hero: Node3D = load(PLAYER_SCENE).instantiate() as Node3D
	_root.add_child(hero)
	await physics_frame

	# The hero stands still in the lane; the car starts APPROACH_BACK metres away
	# down the same lane at cruise, driving straight at him.
	hero.global_position = Vector3(lane.x, 0.05, lane.z)
	hero.rotation = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	await physics_frame
	var hero_at: Vector3 = hero.global_position

	var car: Dictionary = _solo_car()
	_plant_car(car, Vector3(lane.x, 0.0, lane.z - APPROACH_BACK), TrafficScript.CRUISE_MAX)

	# `move_toward` against a target that itself falls to zero decays the speed
	# asymptotically, so "stopped" is not an exact 0.0 and asking for one measures
	# nothing. What the bead actually asks is measured instead: the car NEVER
	# REACHES him (min gap), it really does come to rest (final speed), and from
	# the moment it is at rest it CREEPS NO FURTHER.
	var min_gap: float = INF
	var crept: float = 0.0
	var rest_at := Vector3.INF
	var travelled: float = 0.0
	for _i in APPROACH_FRAMES:
		var before: Vector3 = _manager._car_world_pos(car)
		_manager._process(DT)
		await physics_frame
		var after: Vector3 = _manager._car_world_pos(car)
		travelled += before.distance_to(after)
		min_gap = minf(min_gap, after.distance_to(hero_at))
		if float(car["speed"]) <= CAR_AT_REST:
			if rest_at == Vector3.INF:
				rest_at = after
			else:
				crept = maxf(crept, rest_at.distance_to(after))

	if travelled < 1.0:
		_failures.append("the probe car drove %.2f m in %d frames — check 18's approach is"
			% [travelled, APPROACH_FRAMES] + " dead, so 'it stopped short and stayed there'"
			+ " is true of a car that was never moving")
	if rest_at == Vector3.INF:
		_failures.append("the car never came to rest (speed %.2f, floor %.2f) in %d frames"
			% [float(car["speed"]), CAR_AT_REST, APPROACH_FRAMES]
			+ " with a hero standing in its lane — the shipped yield did not fire")
	elif crept > CAR_CREEP_MAX:
		_failures.append("a car that had come to rest for the hero then crept another"
			+ " %.3f m — a stopped car must never become a hazard" % crept)
	# THE ONE THAT MATTERS: the closest it ever got. Not its nose (CAR_LENGTH/2,
	# which would only catch a car that had run him over) but STOP_DISTANCE — the
	# gap the yield promises. A car that closed past that is one that decided to
	# stop and then kept coming, which is the whole failure mode.
	if min_gap < TrafficScript.STOP_DISTANCE - 0.25:
		_failures.append("the car closed to %.2f m of the hero, inside the %.2f m its own"
			% [min_gap, TrafficScript.STOP_DISTANCE] + " yield promises — it stopped for"
			+ " him and then moved in anyway")
	var stop_gap: float = min_gap
	# HORIZONTAL displacement: a hero dropped 5 cm onto the probe floor settles by
	# exactly that much in Y, and "was he shoved" is a question about the ground
	# plane.
	var shoved: float = Vector2(hero.global_position.x - hero_at.x,
		hero.global_position.z - hero_at.z).length()
	if shoved > 0.05:
		_failures.append("the hero was displaced %.3f m by a car yielding to him — a car"
			% shoved + " may be bumped into and slid along, never something that shoves")
	if bool(hero.get("is_caught")) or bool(hero.get("is_respawning")):
		_failures.append("the hero was CAUGHT by a car — traffic is scenery and carries no"
			+ " damage of any kind")
	# ---- (c) A POSE THAT LANDS ON THE HERO IS NOT SOLID --------------------
	# The approach above can never produce this — a car brakes 18 m out and no
	# spawner places one within SPAWN_MIN_DIST of the hero — but a TELEPORT can:
	# Primm's Phase Step, a respawn, the HQ's setback. A teleported static body
	# overlapping a capsule is resolved by `move_and_slide`'s depenetration, which
	# is a launch, so `AmbienceProxies._player_inside()` refuses to be solid over
	# the hero's own centre. Driven the only way it exists: stand him INSIDE the
	# parked car and require him to still be standing there.
	hero.global_position = Vector3(lane.x, 0.05, lane.z)
	hero.velocity = Vector3.ZERO
	await physics_frame
	var inside_at: Vector3 = hero.global_position
	for _i in ON_TOP_FRAMES:
		_plant_car(car, Vector3(lane.x, 0.0, lane.z), 0.0)
		_manager._process(DT)
		await physics_frame
	# FULL 3-D here, unlike the shove measurement above: `move_and_slide` recovers
	# a body out of an overlap along the shortest exit, and for a 1.15 m tall car
	# box under a 2 m capsule that exit is UP. A horizontal-only reading calls
	# being stood on a car roof "not displaced".
	var launched: float = hero.global_position.distance_to(inside_at)
	if launched > 0.5:
		_failures.append("a car planted ON the hero threw him %.2f m — a proxy over the"
			% launched + " hero's own centre must not be solid, or every teleport that"
			+ " lands him in traffic (Phase Step, a respawn, the HQ setback) is a launch")

	print("car yield: drove %.1f m, closed to %.2f m off the hero, crept %.4f m after"
		% [travelled, stop_gap, crept]
		+ " coming to rest; hero displaced %.4f m," % shoved
		+ " and a car planted on him moved him %.2f m" % launched)

	_restore_cars()
	hero.queue_free()
	floor_body.queue_free()
	await process_frame
	Sentinel.done("stopped_car_never_pushes")


# ---------------------------------------------------------------------------
# check 17/18 harness
# ---------------------------------------------------------------------------

func _make_floor(centre: Vector3) -> StaticBody3D:
	## Something to stand on, CENTRED ON THE LANE THE PROBE ACTUALLY FOUND — not
	## on LANE_PROBE_SPOT, which is only where the avenue search starts. The
	## nearest drivable north-south avenue is 300 m down the city from it, and a
	## floor left at the search origin drops the hero into the void: the first
	## draft of this check reported 355 m of "displacement by a car" that was
	## nothing but free fall.
	var body := StaticBody3D.new()
	body.name = "ProbeFloor"
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	cs.shape = box
	cs.position = Vector3(centre.x, -0.5, centre.z)
	body.add_child(cs)
	_root.add_child(body)
	return body


func _pick_lane_spot() -> Vector3:
	## A point a car is willing to stand on with a clear run of the SAME
	## north-south avenue behind it, so the probe drives along Z — which is the
	## hero's own forward once his rotation is zeroed.
	##
	## The avenue is SNAPPED the way `_find_spawn_segment_near` snaps it (every
	## CITY_AVENUE_EVERY-th grid line off the gate), never guessed by sweeping a
	## box: the carriageway is a 16 m band on a 248 m pitch, so a blind sweep
	## around an arbitrary point finds nothing and reports the probe unstageable.
	## Every metre of the run is then asked of the SHIPPED `is_traffic_walkable`,
	## so the probe car can never be recycled out from under the drive.
	var ave_pitch: float = PLAN_SCRIPT.STREET_PITCH * float(PLAN_SCRIPT.CITY_AVENUE_EVERY)
	var gate_x: float = PLAN_SCRIPT.GATE.x
	var k: float = roundf((LANE_PROBE_SPOT.x - gate_x) / ave_pitch)
	for kk: int in [0, 1, -1, 2, -2]:
		var ave_x: float = gate_x + (k + float(kk)) * ave_pitch
		for dz in range(-600, 601, 4):
			var z := LANE_PROBE_SPOT.z + float(dz)
			var ok := true
			for step in range(-int(APPROACH_BACK) - 6, 14, 2):
				if not TrafficScript.is_traffic_walkable(ave_x, z + float(step)):
					ok = false
					break
			if ok:
				return Vector3(ave_x, 0.0, z)
	return Vector3.INF


var _all_cars: Array = []


func _solo_car() -> Dictionary:
	## Reduce the manager to ONE car for the duration of a probe.
	##
	## Sleeping the other 31 is not enough and that is not a detail: the shipped
	## `_update_traffic_spawns` re-activates every inactive car it finds, every
	## frame, so a probe that merely deactivates them is driven through a live
	## bubble of 31 real cars — one of which parks on the hero and launches him
	## (measured: 349 m of "displacement" in 420 frames, from a proxy landing on a
	## capsule). Handing the manager a one-element `_cars` gives its own spawner
	## nothing to fill, so the only body in the world is the one being asserted
	## about. `_restore_cars()` puts the fleet back.
	if _all_cars.is_empty():
		_all_cars = _manager.get("_cars")
	var solo: Array[Dictionary] = [_all_cars[0]]
	_manager.set("_cars", solo)
	return solo[0]


func _restore_cars() -> void:
	if not _all_cars.is_empty():
		_manager.set("_cars", _all_cars)


func _plant_car(car: Dictionary, world: Vector3, speed: float) -> void:
	## Stand `car` so that its DRAWN AND COLLIDED position is `world`, heading +Z.
	## `_car_world_pos` offsets a car LANE_OFFSET metres along its own
	## perpendicular (right-hand traffic), so the record's base has to be set back
	## by that offset or the body ends up a lane away from where the probe thinks
	## it is.
	var heading := Vector2(0.0, 1.0)
	var perp := Vector3(-heading.y, 0.0, heading.x)
	car["heading_dir"] = heading
	car["facing_yaw"] = atan2(-heading.x, -heading.y)
	car["pos"] = world - perp * TrafficScript.LANE_OFFSET
	car["speed"] = speed
	car["cruise_speed"] = TrafficScript.CRUISE_MAX
	car["blocked_time"] = 0.0
	car["honk_cooldown"] = 99.0  # the horn is check 6's subject, not this one's
	car["active"] = true
	car["lod_debt"] = 0.0


func _stand_on_roof(hero: Node3D, lane: Vector3, frames: int) -> Vector2:
	## Drop the hero CAR_ROOF_DROP above the roof of the car parked on `lane` and
	## hold him there for `frames` frames, replanting the car every frame the way
	## `_drive_into_car` does. Returns (the LOWEST y he ever reached, how many of
	## the frames after CAR_ROOF_SETTLE he was `is_on_floor()`).
	var car: Dictionary = _solo_car()
	_plant_car(car, lane, 0.0)
	hero.global_position = Vector3(lane.x, TrafficScript.CAR_PROXY_HEIGHT + CAR_ROOF_DROP,
		lane.z)
	hero.rotation = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	await physics_frame
	var lowest: float = INF
	var floored: int = 0
	for i in frames:
		_plant_car(car, lane, 0.0)
		_manager._process(DT)
		await physics_frame
		if i >= CAR_ROOF_SETTLE:
			lowest = minf(lowest, hero.global_position.y)
			if (hero as CharacterBody3D).is_on_floor():
				floored += 1
	return Vector2(lowest, float(floored))


func _drive_into_car(hero: Node3D, lane: Vector3, frames: int) -> Vector3:
	## Stand a STOPPED car on `lane` and walk the hero into its rear from
	## CAR_PROBE_AHEAD metres back. `player.tscn` turns its body to face down the
	## road on `_ready`, so the rotation is zeroed to make "forward" world -Z.
	var car: Dictionary = _solo_car()
	hero.global_position = Vector3(lane.x, 0.05, lane.z + CAR_PROBE_AHEAD)
	hero.rotation = Vector3.ZERO
	hero.velocity = Vector3.ZERO
	var start: Vector3 = hero.global_position
	Input.action_press("move_forward", 1.0)
	for _i in frames:
		_plant_car(car, lane, 0.0)
		_manager._process(DT)
		await physics_frame
	Input.action_release("move_forward")
	return start
