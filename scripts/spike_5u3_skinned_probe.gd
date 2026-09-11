extends SceneTree
## SPIKE godot-test1-5u3.1 — the Godot-side assert on the skinned hero .glb.
##
## Instantiates the .glb `scripts/build_hero.py` just wrote, finds its
## Skeleton3D and prints the four numbers the bead asks the PR for: bone count,
## bounding-box height, how far the feet sit off y=0, and which way the body
## faces. NOT a `scripts/*_selfcheck.gd` — this is a spike probe, not a gate, so
## CI's shard sweep never picks it up.
##
##   godot --headless --path . --script res://scripts/spike_5u3_skinned_probe.gd
##
## FACING is measured on the RIG, not on the mesh: `ball_*` (the toe bone) sits
## in front of `foot_*` (the ankle), so `ball.z < foot.z` is "the toes point
## toward -Z", i.e. the body faces the way every hero in this game faces. It
## beats an eye-sphere centroid because the eyes are joined into the body mesh
## and cannot be isolated once imported.

const GLB := "res://assets/models/characters/teibi_parts/teibi_skinned.glb"
const WANT_BONES := 53
## The BODY is built to 1.78 m crown-to-heel; Teibi's beret nub adds ~5.5 cm on
## top, the same 1.835 m the z3e.10 Blender checkpoint recorded. The band is the
## bead's 1.75-1.82 widened by exactly that hat.
const MIN_HEIGHT := 1.75
const MAX_HEIGHT := 1.86
const FEET_TOLERANCE := 0.04

func _initialize() -> void:
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_error("[PROBE] cannot load " + GLB)
		quit(1)
		return
	var root := scene.instantiate()
	get_root().add_child(root)

	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_error("[PROBE] no Skeleton3D under " + GLB)
		quit(1)
		return
	var skel := skels[0] as Skeleton3D
	print("[PROBE] scene tree: ", _tree_line(root))
	print("[PROBE] bones: ", skel.get_bone_count(), " (want ", WANT_BONES, ")")

	var aabb := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var height := aabb.size.y
	var feet := aabb.position.y
	print("[PROBE] height: %.4f m (y %.4f .. %.4f)" % [height, feet, feet + height])
	print("[PROBE] feet off y=0: %.4f m" % feet)

	var toes_ahead := true
	for side in ["l", "r"]:
		var ball := _bone_pos(skel, "ball_" + side)
		var foot := _bone_pos(skel, "foot_" + side)
		print("[PROBE] %s toe z %.4f vs ankle z %.4f" % [side, ball.z, foot.z])
		toes_ahead = toes_ahead and ball.z < foot.z
	var head := _bone_pos(skel, "head")
	var upperarm_l := _bone_pos(skel, "upperarm_l")
	print("[PROBE] head bone at ", head.snappedf(0.0001),
			"  upperarm_l at ", upperarm_l.snappedf(0.0001))
	print("[PROBE] faces -Z: ", toes_ahead, " | left arm at -X: ", upperarm_l.x < 0.0)

	# The bone axes the procedural column has to rotate about — MakeHuman bones
	# carry rolls, so "swing the thigh about X" is only true if the thigh's local
	# X actually runs across the body. Printed, never assumed.
	for bone in ["thigh_l", "calf_l", "upperarm_l", "lowerarm_l", "spine_02", "head"]:
		var idx := skel.find_bone(bone)
		var b := skel.get_bone_rest(idx).basis
		print("[PROBE] rest basis %-10s x=%s y=%s z=%s" % [bone,
				b.x.snappedf(0.001), b.y.snappedf(0.001), b.z.snappedf(0.001)])

	var ok := skel.get_bone_count() == WANT_BONES \
			and height >= MIN_HEIGHT and height <= MAX_HEIGHT \
			and absf(feet) <= FEET_TOLERANCE \
			and toes_ahead and upperarm_l.x < 0.0
	print("[PROBE] ", "PROBE OK" if ok else "PROBE FAILED")
	quit(0 if ok else 1)

func _bone_pos(skel: Skeleton3D, name: String) -> Vector3:
	var idx := skel.find_bone(name)
	if idx < 0:
		push_error("[PROBE] no bone " + name)
		return Vector3.ZERO
	return (skel.global_transform * skel.get_bone_global_rest(idx)).origin

func _tree_line(node: Node, depth: int = 0) -> String:
	var s := " ".repeat(depth) + node.name + ":" + node.get_class()
	for c in node.get_children():
		s += "\n" + _tree_line(c, depth + 1)
	return s
