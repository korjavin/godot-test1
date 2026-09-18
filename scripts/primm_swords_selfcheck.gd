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
4. Outward: the shipped prop's saya tubes are Godot-FRONT-facing (codex
	round 1 — the tubes shipped wound inside-out and rendered inverted). Only
	the saya faces are measured, and deliberately: the tsuba sits ON the
	centroid plane, so a centroid dot cannot judge its caps (batch_selfcheck's
	star-shaped requirement), while every saya face stands well off it. Godot's
	front face is the CLOCKWISE one seen from outside, and the importer flips
	winding (measured: trimesh 83% right-hand-outward reads 17% here), so a
	correctly shipped saya reads right-hand-INWARD on every one of its 240
	faces — the generator asserts the source side (positive volume), this
	asserts the shipped side.
5. Grounded slash (bead godot-test1-0mr0.3, review round 1): the room-wide
Twin Flash poses on the GROUND, where the feet never move — a grounded
remote Primm with ABILITY_BIT_SLASH set crosses the arms and shows the hand
pair, and clearing the bit reclaims both on the next gait frames (a slash
that ends mid-air lands sheathed).

Sentinel contract: isolate first, done() last in _run(), finish() at report.
"""

const Sentinel = preload("res://scripts/selfcheck_sentinel.gd")
const RemoteAvatar = preload("res://scripts/remote_avatar.gd")
const PlayerController = preload("res://scripts/player_controller.gd")

const PRIMM_SCENE: String = "res://scenes/characters/primm.tscn"
const SWORDS_NODE: String = "Swords"
const SPINE_BONE: StringName = &"spine_03"
const EXTERNAL_PATH: String = "../Mesh/Armature/Skeleton3D"
const MIN_PROP_VERTS: int = 100
const TIP_LOCAL_Z: float = -0.55
const HILT_LOCAL_Z: float = 0.2
## The saya's vertex colour — the dark indigo-black bytes the generator paints
## ([8, 9, 18, 255]), divided here rather than typed as decimals: the import
## quantizes to float32 and a rounded literal lands outside `is_equal_approx`.
const SAYA_COLOR := Color(8.0 / 255.0, 9.0 / 255.0, 18.0 / 255.0, 1.0)
## Minimum saya faces found (240 ship) and minimum Godot-front fraction.
const SAYA_MIN_FACES: int = 200
const OUTWARD_MIN_FRACTION: float = 0.95
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
	await _check_grounded_slash(avatar)
	_check_clearance(fixture)
	_check_outward(fixture)
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


func _check_grounded_slash(avatar: Node3D) -> void:
	"""
	Review round 1 on PR #437: `_apply_slash_pose()` ran ONLY in the airborne
	branch, so a grounded peer — the common case, Twin Flash never moves the
	feet — kept the katanas on his back, and a slash ending mid-air landed with
	the hand swords stuck drawn. Drive a GROUNDED remote Primm with the
	presence `ab` bit set: the hand pair must show and the arms must cross;
	clear the bit and the next gait frames must sheathe and reclaim.
	"""
	if avatar.character_node == null:
		_failures.append("slash: no character_node — the grounded pose has nothing to cross")
		Sentinel.done("grounded_slash")
		return
	var body: Node = avatar.character_node.get_node_or_null("Body")
	var back: Node = body.get_node_or_null("Swords") if body != null else null
	var left: Node = body.get_node_or_null("SwordL") if body != null else null
	if back == null or left == null:
		_failures.append("slash: remote primm carries no Swords/SwordL pair to swap")
		Sentinel.done("grounded_slash")
		return
	if avatar._rig == null or not avatar._rig.has_method("measure"):
		_failures.append("slash: remote primm bound no measurable rig — the pose has no arms to cross")
		Sentinel.done("grounded_slash")
		return
	# Grounded and standing: the slash never moves the feet, so this is the
	# case the pose exists for.
	avatar.on_floor = true
	avatar.move_speed = 0.0
	avatar.ability_bits = PlayerController.ABILITY_BIT_SLASH
	await process_frame
	await process_frame
	if not bool(left.get("visible")):
		_failures.append("slash: a GROUNDED peer with the slash bit set keeps the hand"
			+ " katanas hidden — the pose ran in the airborne branch only")
	if bool(back.get("visible")):
		_failures.append("slash: a GROUNDED peer with the slash bit set keeps the back"
			+ " pair drawn — the swap never ran on the ground")
	var crossed: Dictionary = avatar._rig.measure()
	if float(crossed.get("left_arm_x", 0.0)) < deg_to_rad(50.0) \
			or float(crossed.get("right_arm_x", 0.0)) < deg_to_rad(50.0):
		_failures.append("slash: a GROUNDED peer with the slash bit set holds his arms at"
			+ " (%.1f, %.1f) deg — the cross never reached the ground" % [
				rad_to_deg(float(crossed.get("left_arm_x", 0.0))),
				rad_to_deg(float(crossed.get("right_arm_x", 0.0)))])
	# The bit drops: the next gait frames sheathe the swords and hand the arms
	# back — `drop_wings()` zeroes the roll and `locomotion()` rewrites both
	# arm axes, so this is the same non-event as the local expiry.
	avatar.ability_bits = 0
	await process_frame
	await process_frame
	if bool(left.get("visible")):
		_failures.append("slash: clearing the bit left the hand katanas drawn on the"
			+ " ground — a slash ending mid-air lands with stuck swords")
	if not bool(back.get("visible")):
		_failures.append("slash: clearing the bit left the back pair hidden — the swap"
			+ " never ran the sheathe half on the ground")
	var rest: Dictionary = avatar._rig.measure()
	if float(rest.get("left_arm_x", 0.0)) > deg_to_rad(30.0) \
			or float(rest.get("right_arm_x", 0.0)) > deg_to_rad(30.0):
		_failures.append("slash: clearing the bit left the arms raised at (%.1f, %.1f)"
			% [rad_to_deg(float(rest.get("left_arm_x", 0.0))),
				rad_to_deg(float(rest.get("right_arm_x", 0.0)))]
			+ " deg — the grounded gait never reclaimed the cross")
	print("grounded slash: the bit crosses a grounded peer's arms and draws the hand pair, clearing it sheathes and reclaims")
	Sentinel.done("grounded_slash")


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


func _check_outward(fixture: Node) -> void:
	var body: Node = fixture.get_node_or_null("Body")
	if body == null:
		_failures.append("outward: no Body under primm.tscn root")
		Sentinel.done("outward")
		return
	var swords := body.get_node_or_null(SWORDS_NODE) as BoneAttachment3D
	if swords == null:
		_failures.append("outward: no Swords node to measure")
		Sentinel.done("outward")
		return
	# Winding is a prop-local property: a rigid instance transform preserves
	# it, so measure in the prop's own frame straight off the surfaces. Only
	# the SAYA faces (all three verts in its colour): the tsuba straddles the
	# centroid plane, where a centroid dot misfires on genuinely outward caps.
	var centroid := Vector3.ZERO
	var centroid_n := 0
	for mi in swords.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				centroid += v
				centroid_n += 1
	centroid /= float(maxi(centroid_n, 1))
	var front := 0
	var saya := 0
	for mi in swords.find_children("*", "MeshInstance3D", true, false):
		var mesh2: Mesh = (mi as MeshInstance3D).mesh
		if mesh2 == null:
			continue
		for s in range(mesh2.get_surface_count()):
			var a2: Array = mesh2.surface_get_arrays(s)
			if a2.size() <= Mesh.ARRAY_COLOR:
				continue
			var verts: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = a2[Mesh.ARRAY_COLOR]
			var idx: PackedInt32Array = a2[Mesh.ARRAY_INDEX]
			var order := PackedInt32Array()
			if idx.is_empty():
				for i in verts.size():
					order.append(i)
			else:
				order = idx
			for t in range(0, order.size() - 2, 3):
				if not cols[order[t]].is_equal_approx(SAYA_COLOR) \
						or not cols[order[t + 1]].is_equal_approx(SAYA_COLOR) \
						or not cols[order[t + 2]].is_equal_approx(SAYA_COLOR):
					continue
				saya += 1
				var v0: Vector3 = verts[order[t]]
				var v1: Vector3 = verts[order[t + 1]]
				var v2: Vector3 = verts[order[t + 2]]
				var normal: Vector3 = (v1 - v0).cross(v2 - v0)
				if normal.length() < 0.000000001:
					continue
				var middle: Vector3 = (v0 + v1 + v2) / 3.0
				# Godot's front face is CLOCKWISE seen from outside, so its
				# right-hand normal points INWARD: dot < 0 IS front-facing.
				if normal.normalized().dot(
						(middle - centroid).normalized()) < 0.0:
					front += 1
	if saya < SAYA_MIN_FACES:
		_failures.append("outward: only %d saya faces found (min %d)"
			% [saya, SAYA_MIN_FACES])
		Sentinel.done("outward")
		return
	var fraction: float = float(front) / float(saya)
	if fraction < OUTWARD_MIN_FRACTION:
		_failures.append("outward: %.0f%% of %d saya faces are Godot-front "
			% [fraction * 100.0, saya] + "(min 95%%)")
	Sentinel.done("outward")


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
