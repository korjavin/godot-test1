extends SceneTree
"""
PRIMM SWORDS SELFCHECK — sheathed katanas crossed on Primm's back.

Covers `godot-test1-z629`: the Swords BoneAttachment3D on spine_03, on the local
hero AND on the remote mirror (same scene, rebound per instance — a hologram
keeps its swords).

1. Local:  Swords exists on Body, is a BoneAttachment3D, names spine_03, uses
   the external skeleton, its path resolves to the same Skeleton3D the limb
   rig found by type, `get_skeleton()` is bound at runtime, and the instanced
   prop carries real geometry (> 100 verts — an empty import fails here).
2. Mirror: RemoteAvatar setup + set_character(1) keeps the Swords node with
   the same bone name, a bound skeleton, and real geometry.
3. Clearance: at rest pose the blade tips stay outside the coat-tails volume
   (> 5 mm — a rub is a fail), with silhouette pins (|tip x| and hilt height)
   catching a gross misplacement a pure clearance test would miss.

Sentinel contract: isolate first, done() last in _run(), finish() at report.
"""

const Sentinel = preload("res://scripts/selfcheck_sentinel.gd")
const RemoteAvatar = preload("res://scripts/remote_avatar.gd")

const PRIMM_SCENE: String = "res://scenes/characters/primm.tscn"
const SWORDS_NODE: String = "Swords"
const SPINE_BONE: StringName = &"spine_03"
const EXTERNAL_PATH: String = "../Mesh/Armature/Skeleton3D"
const MIN_PROP_VERTS: int = 100
const TIP_LOCAL_Z: float = -0.55
const HILT_LOCAL_Z: float = 0.2
const CLEARANCE_MIN_M: float = 0.005
const TIP_SPREAD_MIN: float = 0.30
const TIP_SPREAD_MAX: float = 0.45
const HILT_TOP_MIN: float = 1.50
const HILT_TOP_MAX: float = 1.65

var _failures: Array = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	var packed: PackedScene = load(PRIMM_SCENE)
	if packed == null or not packed.can_instantiate():
		_failures.append("primm scene missing or not instantiable: %s" % PRIMM_SCENE)
		_report()
		return
	var fixture: Node = packed.instantiate()
	root.add_child(fixture)
	var avatar: Node3D = RemoteAvatar.new()
	root.add_child(avatar)
	avatar.setup("swords-probe")
	avatar.set_character(1)
	await process_frame
	_check_local_attachment(fixture)
	_check_remote_mirror(avatar)
	_check_clearance(fixture)
	fixture.queue_free()
	avatar.queue_free()
	_report()


func _skeleton_by_type(body: Node) -> Skeleton3D:
	var found: Array = body.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D


func _prop_verts(swords: Node) -> PackedVector3Array:
	var verts := PackedVector3Array()
	for mi in swords.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in arrays[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
	return verts


func _check_local_attachment(fixture: Node) -> void:
	var body: Node = fixture.get_node_or_null("Body")
	if body == null:
		_failures.append("local: no Body under primm.tscn root")
		Sentinel.done("local")
		return
	var skeleton: Skeleton3D = _skeleton_by_type(body)
	if skeleton == null:
		_failures.append("local: no Skeleton3D under Body")
		Sentinel.done("local")
		return
	var swords := body.get_node_or_null(SWORDS_NODE) as BoneAttachment3D
	if swords == null:
		_failures.append("local: no Swords BoneAttachment3D under Body")
		Sentinel.done("local")
		return
	if swords.bone_name != SPINE_BONE:
		_failures.append("local: Swords.bone_name is %s, want spine_03" % swords.bone_name)
	if not swords.use_external_skeleton:
		_failures.append("local: Swords.use_external_skeleton is off")
	if String(swords.external_skeleton) != EXTERNAL_PATH:
		_failures.append("local: Swords.external_skeleton is %s, want %s" % [swords.external_skeleton, EXTERNAL_PATH])
	var target: Node = swords.get_node_or_null(swords.external_skeleton)
	if target != skeleton:
		_failures.append("local: Swords.external_skeleton does not resolve to the rig skeleton")
	if swords.get_skeleton() != skeleton:
		_failures.append("local: Swords.get_skeleton() is not bound to the rig skeleton")
	var mesh_node: Node = swords.get_node_or_null("Mesh")
	if mesh_node == null:
		_failures.append("local: Swords has no Mesh instancing child")
		Sentinel.done("local")
		return
	if _prop_verts(swords).size() < MIN_PROP_VERTS:
		_failures.append("local: Swords prop carries no real geometry")
	Sentinel.done("local")


func _check_remote_mirror(avatar: Node3D) -> void:
	if avatar.character_node == null:
		_failures.append("mirror: set_character(1) left no character_node")
		Sentinel.done("mirror")
		return
	var body: Node = avatar.character_node.get_node_or_null("Body")
	if body == null:
		_failures.append("mirror: no Body under remote primm")
		Sentinel.done("mirror")
		return
	var swords := body.get_node_or_null(SWORDS_NODE) as BoneAttachment3D
	if swords == null:
		_failures.append("mirror: remote primm lost its Swords node")
		Sentinel.done("mirror")
		return
	if swords.bone_name != SPINE_BONE:
		_failures.append("mirror: Swords.bone_name is %s, want spine_03" % swords.bone_name)
	if swords.get_skeleton() == null:
		_failures.append("mirror: remote Swords.get_skeleton() is unbound")
	if _prop_verts(swords).size() < MIN_PROP_VERTS:
		_failures.append("mirror: remote Swords prop carries no real geometry")
	Sentinel.done("mirror")


func _tail_box_world(fixture: Node) -> AABB:
	var box := AABB()
	var touched := false
	for mi in fixture.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		if swords_subtree(mi):
			continue
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in arrays[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = xf * v
				if absf(w.x) <= 0.42 and w.y >= 0.65 and w.y <= 1.00 and w.z > 0.0:
					if not touched:
						box.position = w
						touched = true
					else:
						box = box.expand(w)
	return box


func swords_subtree(mi: Node) -> bool:
	var n: Node = mi
	while n != null:
		if n.name == SWORDS_NODE:
			return true
		n = n.get_parent()
	return false


func _check_clearance(fixture: Node) -> void:
	var body: Node = fixture.get_node_or_null("Body")
	var swords := body.get_node_or_null(SWORDS_NODE) as BoneAttachment3D
	if swords == null:
		_failures.append("clearance: no Swords node to measure")
		Sentinel.done("clearance")
		return
	var box: AABB = _tail_box_world(fixture)
	if box.size == Vector3.ZERO:
		_failures.append("clearance: coat-tails volume came back empty")
		Sentinel.done("clearance")
		return
	var tip_min := INF
	var tip_spread := 0.0
	var hilt_top := -INF
	for mi in swords.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf: Transform3D = (mi as MeshInstance3D).global_transform
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in arrays[Mesh.ARRAY_VERTEX]:
				if v.z < TIP_LOCAL_Z:
					var w: Vector3 = xf * v
					tip_min = minf(tip_min, _point_box_distance(w, box))
					tip_spread = maxf(tip_spread, absf(w.x))
				elif v.z > HILT_LOCAL_Z:
					hilt_top = maxf(hilt_top, (xf * v).y)
	if tip_min == INF:
		_failures.append("clearance: no blade-tip verts found in the prop")
		Sentinel.done("clearance")
		return
	if tip_min < CLEARANCE_MIN_M:
		_failures.append("clearance: closest tip is %.1f mm from the tails (min 5)" % (tip_min * 1000.0))
	if tip_spread < TIP_SPREAD_MIN or tip_spread > TIP_SPREAD_MAX:
		_failures.append("clearance: tip spread |x| is %.3f m, want 0.30..0.45" % tip_spread)
	if hilt_top < HILT_TOP_MIN or hilt_top > HILT_TOP_MAX:
		_failures.append("clearance: hilt top is %.3f m high, want 1.50..1.65" % hilt_top)
	Sentinel.done("clearance")


func _point_box_distance(p: Vector3, box: AABB) -> float:
	var dx: float = maxf(box.position.x - p.x, 0.0) + maxf(p.x - (box.position.x + box.size.x), 0.0)
	var dy: float = maxf(box.position.y - p.y, 0.0) + maxf(p.y - (box.position.y + box.size.y), 0.0)
	var dz: float = maxf(box.position.z - p.z, 0.0) + maxf(p.z - (box.position.z + box.size.z), 0.0)
	return Vector3(dx, dy, dz).length()


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)
