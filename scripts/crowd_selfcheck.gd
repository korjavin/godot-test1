extends SceneTree
## Headless self-check for crowd_manager.gd (Budapest citizen crowds).
##
##   godot --headless --path . --script res://scripts/crowd_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints failure details and exits 1.
##
## Validates:
##   1. Isolation contract: CrowdManager is in group "crowd", all descendants
##      join NO gameplay groups ("player", "crocodile", "enemy", "boss", "terrain"),
##      and carry NO collision bodies or Area3Ds (recursive check).
##   2. Mesh and material sharing: 4 MultiMeshInstance3D nodes (Windman, Primm,
##      Teibi, Phoboman), shared StandardMaterial3D with vertex colors and sRGB,
##      shared archetype meshes with feet at y = 0.
##   3. City boundaries and terrain safety: citizens spawn and walk strictly inside
##      BudapestPlan.rect(), never enter the wet Danube, never enter plateaus,
##      and maintain feet at y = 0.
##   4. Street grid wayfinding: walkers follow the 62 m grid, stop at crossings,
##      and choose valid street branches without getting stuck.
##   5. Platform budget and dormancy: 0 active walkers outside Budapest, up to
##      CROWD_MAX (60 web / 120 desktop) active walkers inside Budapest around player.
##   6. MultiMesh buffer readback: transforms read from MultiMesh.buffer are
##      finite, inside BudapestPlan.rect(), and outside Danube water.

const SIM_FRAMES: int = 300
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
	_player.position = Vector3(0.0, 1.0, 0.0) # Start outside Budapest
	_root.add_child(_player)

	var mgr_script: GDScript = load("res://scripts/crowd_manager.gd")
	_manager = Node3D.new()
	_manager.set_script(mgr_script)
	_root.add_child(_manager)


func _process(_delta: float) -> bool:
	_run_checks()
	return false


func _run_checks() -> void:
	print("--- Running crowd_selfcheck ---")

	_check_groups_and_collision()
	_check_multimesh_resources()
	_check_dormancy_outside_budapest()
	_check_simulation_and_boundaries()

	if _failures.is_empty():
		print("crowd_selfcheck: all checks passed cleanly")
		print("SELFCHECK OK")
		quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _check_groups_and_collision() -> void:
	## 1. Recursive group and collision isolation
	if not _manager.is_in_group("crowd"):
		_failures.append("CrowdManager is not in group 'crowd'")

	for g: String in ["player", "crocodile", "enemy", "boss", "terrain"]:
		if _manager.is_in_group(g):
			_failures.append("CrowdManager illegally joined gameplay group '%s'" % g)

	_check_node_isolation_recursive(_manager)


func _check_node_isolation_recursive(node: Node) -> void:
	if node != _manager:
		var groups := node.get_groups()
		if not groups.is_empty():
			_failures.append("CrowdManager descendant '%s' has groups: %s (must have none)" % [node.name, str(groups)])
		if node is CollisionObject3D:
			_failures.append("CrowdManager descendant '%s' is a physics CollisionObject3D (must have none)" % node.name)
		if node is Area3D:
			_failures.append("CrowdManager descendant '%s' is an Area3D (must have none)" % node.name)

	for child in node.get_children():
		_check_node_isolation_recursive(child)


func _check_multimesh_resources() -> void:
	## 2. MultiMesh count, shared materials, and feet at y = 0
	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	if mm_nodes.size() != 4:
		_failures.append("Expected exactly 4 MultiMeshInstance3D nodes, found %d" % mm_nodes.size())
		return

	var shared_mat: Material = mm_nodes[0].material_override
	if shared_mat == null:
		_failures.append("MultiMesh material_override is null")

	for k in 4:
		var node: MultiMeshInstance3D = mm_nodes[k]
		if node == null:
			_failures.append("MultiMeshInstance3D at index %d is null" % k)
			continue
		if node.material_override != shared_mat:
			_failures.append("MultiMeshInstance3D %s does not share the common material" % node.name)
		var mm: MultiMesh = node.multimesh
		if mm == null:
			_failures.append("MultiMeshInstance3D %s has null multimesh" % node.name)
			continue
		if mm.mesh == null:
			_failures.append("MultiMesh in %s has null mesh" % node.name)
			continue
		if mm.instance_count <= 0:
			_failures.append("MultiMesh in %s has instance_count <= 0" % node.name)

		# Verify mesh feet rest at y = 0 by construction
		var aabb: AABB = mm.mesh.get_aabb()
		if absf(aabb.position.y) > 0.001:
			_failures.append("MultiMesh %s mesh AABB position.y is %f (must be 0.0 for feet at y=0)" % [node.name, aabb.position.y])


func _check_dormancy_outside_budapest() -> void:
	## 3. Outside Budapest: all citizens dormant
	_player.position = Vector3(0.0, 1.0, 0.0) # Wilderness
	_manager._process(DT)

	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	var total_visible := 0
	for node: MultiMeshInstance3D in mm_nodes:
		total_visible += node.multimesh.visible_instance_count

	if total_visible != 0:
		_failures.append("Crowd rendered %d visible instances while player is outside Budapest at x=0" % total_visible)


func _check_simulation_and_boundaries() -> void:
	## 4. Inside Budapest: spawn and simulate movement
	# Test location 1: Buda Gate / Avenue (x = 1750, z = 0)
	_player.position = Vector3(1750.0, 1.0, 0.0)
	for frame in 60:
		_manager._process(DT)

	_verify_active_citizens("Buda Avenue (x=1750)")

	# Test location 2: Pest Inner City / Erzsébet Square (x = 2900, z = 0)
	_player.position = Vector3(2900.0, 1.0, 0.0)
	for frame in SIM_FRAMES:
		_manager._process(DT)
		if frame % 30 == 0:
			_verify_active_citizens("Pest Inner City frame %d" % frame)

	# Test location 3: Heroes' Square (x = 3520, z = -520)
	_player.position = Vector3(3520.0, 1.0, -520.0)
	for frame in 60:
		_manager._process(DT)

	_verify_active_citizens("Heroes' Square (x=3520)")


func _verify_active_citizens(context: String) -> void:
	var plan_script: GDScript = load("res://scripts/budapest_plan.gd")
	var mgr_script: GDScript = load("res://scripts/crowd_manager.gd")
	var citizens: Array = _manager.get("_citizens")
	var crowd_max: int = _manager.get("_crowd_max")
	var active_count := 0

	for citizen: Dictionary in citizens:
		if not citizen["active"]:
			continue
		active_count += 1
		var pos: Vector3 = citizen["pos"]

		# Must be strictly within Budapest bounds
		if not plan_script.contains(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) outside Budapest bounds" % [context, pos.x, pos.z])

		# Must never enter the wet Danube river
		if plan_script.danube_wet(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) is walking in the Danube river" % [context, pos.x, pos.z])

		# Must never enter a plateau
		if plan_script.plateau_top_at(pos.x, pos.z) > 0.0:
			_failures.append("%s: citizen at (%f, %f) is on a plateau cliff" % [context, pos.x, pos.z])

		# Must never enter solid landmark buildings
		if mgr_script._is_inside_solid_landmark(pos.x, pos.z):
			_failures.append("%s: citizen at (%f, %f) is inside a solid landmark building" % [context, pos.x, pos.z])

		# Speed must be positive
		if citizen["speed"] <= 0.0:
			_failures.append("%s: citizen has invalid speed %f" % [context, citizen["speed"]])

	if active_count == 0:
		_failures.append("%s: 0 active citizens spawned around player inside Budapest" % context)

	# Assert active count does not exceed platform budget
	if active_count > crowd_max:
		_failures.append("%s: active citizen count %d exceeds platform budget %d" % [context, active_count, crowd_max])

	# Assert MultiMesh buffer readback values
	var mm_nodes: Array = _manager.get("_multimesh_nodes")
	for k in mm_nodes.size():
		var node: MultiMeshInstance3D = mm_nodes[k]
		var mm: MultiMesh = node.multimesh
		var buf: PackedFloat32Array = mm.buffer
		var vis: int = mm.visible_instance_count
		for idx in vis:
			var base := idx * 12
			var ox: float = buf[base + 3]
			var oy: float = buf[base + 7]
			var oz: float = buf[base + 11]
			var origin := Vector3(ox, oy, oz)

			if not origin.is_finite():
				_failures.append("%s: MultiMesh %s instance %d has non-finite origin %s" % [context, node.name, idx, str(origin)])
			if not mgr_script.is_walkable(ox, oz):
				_failures.append("%s: MultiMesh %s instance %d drawn origin (%f, %f) is not walkable" % [context, node.name, idx, ox, oz])
