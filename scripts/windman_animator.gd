extends Node3D
## Windman Character Animator
##
## This script bridges the simple animation system with the Windman skeleton.
## It provides limb nodes that can be animated by the player controller
## while actually controlling the underlying skeleton bones.

## References to skeleton bones
var skeleton: Skeleton3D = null
var bone_indices: Dictionary = {}

## Limb proxy nodes (these are animated by the player controller)
@onready var left_arm_proxy: Node3D = $LeftArm if has_node("LeftArm") else null
@onready var right_arm_proxy: Node3D = $RightArm if has_node("RightArm") else null
@onready var left_leg_proxy: Node3D = $LeftLeg if has_node("LeftLeg") else null
@onready var right_leg_proxy: Node3D = $RightLeg if has_node("RightLeg") else null

func _ready() -> void:
	"""
	Initialize the animator by finding the skeleton and bone indices.
	"""
	# Try to find the skeleton in the model
	var model = get_node_or_null("Body/WindmanModel")
	if model:
		skeleton = find_skeleton(model)

	if skeleton:
		# Cache bone indices for faster access
		bone_indices["LeftUpperArm"] = skeleton.find_bone("LeftUpperArm")
		bone_indices["RightUpperArm"] = skeleton.find_bone("RightUpperArm")
		bone_indices["LeftUpperLeg"] = skeleton.find_bone("LeftUpperLeg")
		bone_indices["RightUpperLeg"] = skeleton.find_bone("RightUpperLeg")

		print("Windman animator initialized with skeleton")
	else:
		print("Windman animator: No skeleton found, animations will be limited")

func find_skeleton(node: Node) -> Skeleton3D:
	"""
	Recursively search for a Skeleton3D node.
	"""
	if node is Skeleton3D:
		return node

	for child in node.get_children():
		var result = find_skeleton(child)
		if result:
			return result

	return null

func _process(_delta: float) -> void:
	"""
	Update skeleton bones based on proxy node rotations.
	This allows the simple animation system to control the skeleton.
	"""
	if not skeleton:
		return

	# Apply proxy rotations to skeleton bones
	if left_arm_proxy and bone_indices.has("LeftUpperArm"):
		var bone_idx = bone_indices["LeftUpperArm"]
		if bone_idx >= 0:
			var pose = skeleton.get_bone_pose_rotation(bone_idx)
			# Apply rotation from proxy to bone
			var target_rotation = Quaternion.from_euler(Vector3(left_arm_proxy.rotation.x, 0, 0))
			skeleton.set_bone_pose_rotation(bone_idx, pose.slerp(target_rotation, 0.3))

	if right_arm_proxy and bone_indices.has("RightUpperArm"):
		var bone_idx = bone_indices["RightUpperArm"]
		if bone_idx >= 0:
			var pose = skeleton.get_bone_pose_rotation(bone_idx)
			var target_rotation = Quaternion.from_euler(Vector3(right_arm_proxy.rotation.x, 0, 0))
			skeleton.set_bone_pose_rotation(bone_idx, pose.slerp(target_rotation, 0.3))

	if left_leg_proxy and bone_indices.has("LeftUpperLeg"):
		var bone_idx = bone_indices["LeftUpperLeg"]
		if bone_idx >= 0:
			var pose = skeleton.get_bone_pose_rotation(bone_idx)
			var target_rotation = Quaternion.from_euler(Vector3(left_leg_proxy.rotation.x, 0, 0))
			skeleton.set_bone_pose_rotation(bone_idx, pose.slerp(target_rotation, 0.3))

	if right_leg_proxy and bone_indices.has("RightUpperLeg"):
		var bone_idx = bone_indices["RightUpperLeg"]
		if bone_idx >= 0:
			var pose = skeleton.get_bone_pose_rotation(bone_idx)
			var target_rotation = Quaternion.from_euler(Vector3(right_leg_proxy.rotation.x, 0, 0))
			skeleton.set_bone_pose_rotation(bone_idx, pose.slerp(target_rotation, 0.3))
