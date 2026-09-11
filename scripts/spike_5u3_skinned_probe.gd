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
## `build_hero.py`'s `reframe()` scales the BODY to exactly `row["height"]`
## crown-to-heel — 1.78 m for Teibi — so the measured box can only ever be
## 1.78 plus whatever an accessory sticks out above it. Teibi's beret nub adds
## 5.5 cm (measured 1.8349, and the z3e.10 Blender checkpoint recorded the same
## 1.835 on the same body). The floor stays at the bead's 1.75 — a hat cannot
## lower it, and a body that came out short is exactly what it is there to catch
## — and only the ceiling is raised, to 1.86, which clears the measured 1.8349
## by 2.5 cm and would still fail a second hat.
const MIN_HEIGHT := 1.75
const MAX_HEIGHT := 1.86
const FEET_TOLERANCE := 0.04
## `build_hero.py`'s ARMS_DOWN_DEG, and how far the exported rest may sit from it.
const ARMS_DOWN_DEG := 5.0
const ARM_ANGLE_TOLERANCE := 1.0

func _initialize() -> void:
	var scene := load(GLB) as PackedScene
	if scene == null:
		push_error("[PROBE] cannot load " + GLB)
		quit(1)
		return
	# NOT added to the tree: `_initialize()` runs before the root window is in
	# one, so every `global_transform` here would answer identity AND log an
	# error. `_relative()` composes the same transform from the local ones.
	var root := scene.instantiate() as Node3D

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
		var box := _relative(mi, root) * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	var height := aabb.size.y
	var feet := aabb.position.y
	print("[PROBE] height: %.4f m (y %.4f .. %.4f)" % [height, feet, feet + height])
	print("[PROBE] feet off y=0: %.4f m" % feet)

	var toes_ahead := true
	var skel_at := _relative(skel, root)
	for side in ["l", "r"]:
		var ball := _bone_pos(skel, skel_at, "ball_" + side)
		var foot := _bone_pos(skel, skel_at, "foot_" + side)
		print("[PROBE] %s toe z %.4f vs ankle z %.4f" % [side, ball.z, foot.z])
		toes_ahead = toes_ahead and ball.z < foot.z
	# THE REST POSE, SIGNED. `build_hero.py`'s trap 5 swings both upper arms out of
	# MakeHuman's A-pose and bakes the result as rest; that is a chain of `bpy.ops`
	# mode switches, `modifier_apply` and `pose.armature_apply`, i.e. the classic
	# silent-no-op shape, and NOTHING ELSE HERE WOULD CATCH IT: an A-posed rig has
	# the same bone count, the same crown-to-heel height (arms at 41.3 degrees reach
	# neither above the crown nor below the heel), the same feet and the same toes,
	# and `upperarm_l.x` is the shoulder JOINT, which sits at -X at any arm angle.
	# The magnitude alone is not enough either — an arm swung the WRONG WAY is off
	# vertical by exactly the angle asked for. So: each arm must hang within
	# ARM_ANGLE_TOLERANCE of ARMS_DOWN_DEG off straight down AND lean OUTWARD, away
	# from the body's mid-line, which is the sign the unsigned `Vector.angle()` in
	# the builder's own log cannot see.
	var arms_ok := true
	for side in ["l", "r"]:
		var shoulder := _bone_pos(skel, skel_at, "upperarm_" + side)
		var elbow := _bone_pos(skel, skel_at, "lowerarm_" + side)
		var arm := (elbow - shoulder).normalized()
		var off := rad_to_deg(arm.angle_to(Vector3.DOWN))
		var outward: bool = signf(arm.x) == signf(shoulder.x)
		print("[PROBE] upperarm_%s hangs %.2f deg off vertical, dir %s, outward: %s"
				% [side, off, arm.snappedf(0.0001), outward])
		arms_ok = arms_ok and outward \
				and absf(off - ARMS_DOWN_DEG) <= ARM_ANGLE_TOLERANCE

	var head := _bone_pos(skel, skel_at, "head")
	var upperarm_l := _bone_pos(skel, skel_at, "upperarm_l")
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
			and toes_ahead and upperarm_l.x < 0.0 and arms_ok
	print("[PROBE] ", "PROBE OK" if ok else "PROBE FAILED")
	# Nothing owns this scene — it was never added to the tree — so free it here
	# or Godot reports leaked RIDs at exit, which reads exactly like a defect.
	root.free()
	quit(0 if ok else 1)

func _bone_pos(skel: Skeleton3D, skel_at: Transform3D, name: String) -> Vector3:
	var idx := skel.find_bone(name)
	if idx < 0:
		push_error("[PROBE] no bone " + name)
		return Vector3.ZERO
	return (skel_at * skel.get_bone_global_rest(idx)).origin

func _relative(node: Node3D, root: Node3D) -> Transform3D:
	"""`node`'s transform in `root`'s space, composed from the local ones —
	`global_transform` needs the node to be inside a SceneTree and this scene
	deliberately is not."""
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t

func _tree_line(node: Node, depth: int = 0) -> String:
	var s := " ".repeat(depth) + node.name + ":" + node.get_class()
	for c in node.get_children():
		s += "\n" + _tree_line(c, depth + 1)
	return s
