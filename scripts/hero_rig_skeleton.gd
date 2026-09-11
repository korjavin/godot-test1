extends RefCounted
## THE SKINNED RIG — the same walk, written onto BONES (bd godot-test1-5u3.2,
## epic `5u3`; the column the spike `5u3.1` shot and the owner picked).
##
## THE PICK WAS **PROC** (epic `5u3` NOTES, 2026-09-11): the sine rig
## re-expressed as bone rotations, not clips. The CC0 clip route died on its
## licence (Quaternius QAL v1.0 §3(a) forbids redistributing the files), so
## there is no `AnimationPlayer` here either — the pose is still a pure function
## of (hero, phase, gait state), which is the property that lets a remote mirror
## draw the same walk off a distance-driven phase with nothing added to the
## presence packet.
##
## WHAT A SKELETON BUYS that five whole-limb nodes could not: the joints. A
## knee that bends on the BACK-swing only (a knee that bends on the forward
## swing is the single most puppet-like thing a naive skeletal walk does) and
## an elbow that stays bent and tracks the shoulder.
##
## ### THE BONE-ROLL TRAP — read this before touching a write below
##
## MakeHuman bones carry ROLLS. On the imported `game_engine` rig `thigh_l`'s
## own X axis reads (0.89, 0.21, -0.41) and `upperarm_l`'s reads
## (0.11, -0.99, 0.02), so `set_bone_pose_rotation(idx, Quaternion(RIGHT, a))`
## — a rotation about the BONE's X — swings a leg sideways and spins an arm
## about its own length. **Never write a per-bone axis table**: it is one more
## thing to get wrong per hero, and the next hero's rig will roll differently.
##
## Instead every write here is expressed about the SKELETON's axes and
## conjugated through the bone's PARENT global rest basis — `P⁻¹ · R · P` is the
## same turn written in the space `set_bone_pose_rotation()` expects. That is
## roll-agnostic, so it needs no table and no per-hero tuning (spike `5u3.1`'s
## finding, recorded in `style_shots._pose_skinned()`).
##
## ### WHY THE POSE IS AN EULER TRIPLE, like a node's
##
## `_axis()` / `_set_axis()` read and write ONE component of the skeleton-space
## rotation off rest, leaving the others alone — exactly what `node.rotation.x =`
## does to a `Node3D`. Godot composes both in `EULER_ORDER_YXZ`, so the limb
## driver's writes and these are the same arithmetic on the same triple, and
## `measure()` can hand both to the same bounds.
##
## ### WHAT THIS DOES NOT WRITE
##
## `spine_02`. The body's lean and sway stay on the `Body` NODE above the mesh,
## written by the caller for BOTH rig kinds — one lean, not two (the spike's
## column put it on the spine; doing both would double it). That also keeps the
## landing squash, `capture_rest_pose()`'s `body` key and Teibi's resize working
## with zero lines changed, and keeps `gait_selfcheck`'s body band measuring the
## same thing on either rig.

## MPFB2's `game_engine` rig, UE-mannequin names. The four that stand in for the
## limb rig's four nodes, plus the joints only a skeleton has.
const THIGH: Dictionary = {"left": "thigh_l", "right": "thigh_r"}
const CALF: Dictionary = {"left": "calf_l", "right": "calf_r"}
const UPPERARM: Dictionary = {"left": "upperarm_l", "right": "upperarm_r"}
const LOWERARM: Dictionary = {"left": "lowerarm_l", "right": "lowerarm_r"}
const HEAD: String = "head"

## How much of the leg swing the knee gives back, on the BACK-swing only, and
## the constant elbow bend plus how much of the shoulder's swing the forearm
## tracks on top of it. Spike `5u3.1`'s numbers, shot and ruled on.
const KNEE_FLEX_RATIO: float = 0.8
const ELBOW_BEND_DEG: float = 15.0
const ELBOW_TRACK_RATIO: float = 0.3

## Euler component indices, so the writes below read as axes rather than as 0/2.
const AXIS_X: int = 0
const AXIS_Z: int = 2

var _skel: Skeleton3D = null
var _body: Node3D = null
var _rest: Dictionary = {}

## Per-bone, resolved ONCE at bind because none of it can change afterwards:
## the bone index, the parent's global rest basis (and its inverse) that every
## write conjugates through, and the bone's own rest basis (and its inverse).
## A walk frame touches ten bones, so this is the difference between four
## `find_bone()` string lookups per bone per frame and none.
var _bones: Dictionary = {}


func kind() -> String:
	return "skinned"


func bind(body: Node3D, rest: Dictionary) -> bool:
	"""
	Find the `Skeleton3D` under `body` — BY TYPE, never by path — and cache the
	bases every write needs.

	@param rest: the limb rig's rest table. Unused here and deliberately so: a
	             skeleton carries its own rest pose (`get_bone_rest()`), which is
	             what the exporter baked and what `reset_bone_poses()` returns to.
	@return false when the skeleton is missing the locomotion bones, so an
	        unexpected rig stands frozen instead of half-posed.
	"""
	_body = body
	_rest = rest
	var found: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return false
	_skel = found[0] as Skeleton3D
	var wanted: Array[String] = [HEAD]
	for side: String in ["left", "right"]:
		wanted.append_array([THIGH[side], CALF[side], UPPERARM[side], LOWERARM[side]])
	var missing: Array[String] = []
	for bone: String in wanted:
		var idx: int = _skel.find_bone(bone)
		if idx < 0:
			# The head is optional exactly as the `Head` NODE is: a row with no
			# `head_deg` draws nothing and a rig with no head bone is not broken.
			if bone != HEAD:
				missing.append(bone)
			continue
		var parent: int = _skel.get_bone_parent(idx)
		var p: Basis = Basis.IDENTITY
		if parent >= 0:
			p = Basis(_skel.get_bone_global_rest(parent).basis.get_rotation_quaternion())
		var r: Basis = Basis(_skel.get_bone_rest(idx).basis.get_rotation_quaternion())
		_bones[bone] = {"idx": idx, "p": p, "p_inv": p.inverse(), "r": r, "r_inv": r.inverse()}
	if not missing.is_empty():
		push_warning("HeroRigSkeleton: rig is missing %s — the model will not animate"
				% ", ".join(missing))
		return false
	return true


func has_head() -> bool:
	return _bones.has(HEAD)


func rest_pose() -> void:
	"""Back to the exported rest — every bone, fingers included."""
	_skel.reset_bone_poses()


func locomotion(arm_swing: float, leg_swing: float, arm_asym: float) -> void:
	"""
	One frame of the walk/run cycle, on bones. The four swings are the limb
	rig's four, sign for sign — a positive rotation about the skeleton's +X
	takes a limb hanging down toward -Z, which is the way every hero in this
	game faces, so positive is forward on both rigs.

	The knee and the elbow are the two joints the node rig has and has never
	moved, and they are pure functions of the swing they belong to, so nothing
	here needs a clock the caller is not already keeping.
	"""
	for side: String in ["left", "right"]:
		var mirror: float = -1.0 if side == "left" else 1.0
		var leg: float = mirror * leg_swing
		_set_axis(THIGH[side], AXIS_X, leg)
		# The knee bends only while that leg is BEHIND the body.
		_set_axis(CALF[side], AXIS_X, -maxf(0.0, -leg) * KNEE_FLEX_RATIO)

		var arm: float = -mirror * arm_swing * (arm_asym if side == "left" else 1.0)
		_set_axis(UPPERARM[side], AXIS_X, arm)
		_set_axis(LOWERARM[side], AXIS_X, deg_to_rad(ELBOW_BEND_DEG) + ELBOW_TRACK_RATIO * arm)


func head_bobble(angle: float) -> void:
	if has_head():
		_set_axis(HEAD, AXIS_Z, angle)


func relax_head(weight: float) -> void:
	if has_head():
		_set_axis(HEAD, AXIS_Z, lerp(_axis(HEAD, AXIS_Z), 0.0, weight))


func idle(weight: float) -> void:
	"""Ease the swing out of every joint the walk cycle drives.

	THE ELBOW'S NEUTRAL IS `ELBOW_BEND_DEG`, NOT ZERO, and it is the same on
	every path: `locomotion()` writes the bend plus the shoulder's track, `air()`
	writes the bend alone, and standing still has to ease to the same number or
	the arms straighten over half a second and then snap back 15 degrees on the
	first walking frame. It is also what keeps a standing LOCAL hero and a
	standing REMOTE one identical — the mirror has no idle branch at all, it
	calls `locomotion()` with both swings at zero."""
	for side: String in ["left", "right"]:
		for bone: String in [THIGH[side], CALF[side], UPPERARM[side]]:
			_set_axis(bone, AXIS_X, lerp(_axis(bone, AXIS_X), 0.0, weight))
		_set_axis(LOWERARM[side], AXIS_X,
				lerp(_axis(LOWERARM[side], AXIS_X), deg_to_rad(ELBOW_BEND_DEG), weight))


func air(spread: float, tuck: float, weight: float) -> void:
	"""Arms rolled out to the sides (the beat is already inside `spread`), the
	forward/back swing cleared so the wings sit level, legs tucked forward and
	straightened — a knee left frozen mid-flex is the skinned rig's own version
	of the leftover roll `drop_wings()` clears."""
	for side: String in ["left", "right"]:
		var mirror: float = -1.0 if side == "left" else 1.0
		_set_axis(UPPERARM[side], AXIS_Z, mirror * spread)
		_set_axis(UPPERARM[side], AXIS_X, 0.0)
		_set_axis(LOWERARM[side], AXIS_X, deg_to_rad(ELBOW_BEND_DEG))
		_set_axis(THIGH[side], AXIS_X, lerp(_axis(THIGH[side], AXIS_X), tuck, weight))
		_set_axis(CALF[side], AXIS_X, lerp(_axis(CALF[side], AXIS_X), 0.0, weight))


func drop_wings() -> void:
	for side: String in ["left", "right"]:
		_set_axis(UPPERARM[side], AXIS_Z, 0.0)


func sidestep(splay: float, reach: float, lift_left: bool, lift: float,
		arm_bias: float, arm_swing: float) -> void:
	"""The sideways shuffle, rolled on the skeleton's Z — the limb driver's
	expression, bone for bone."""
	_set_axis(THIGH["left"], AXIS_Z, splay + reach + (lift if lift_left else 0.0))
	_set_axis(THIGH["right"], AXIS_Z, splay - reach + (0.0 if lift_left else lift))
	_set_axis(UPPERARM["left"], AXIS_Z, -arm_bias - arm_swing)
	_set_axis(UPPERARM["right"], AXIS_Z, -arm_bias + arm_swing)


func reset_roll() -> void:
	for side: String in ["left", "right"]:
		_set_axis(UPPERARM[side], AXIS_Z, 0.0)
		_set_axis(THIGH[side], AXIS_Z, 0.0)


func measure() -> Dictionary:
	"""
	The same dictionary the limb driver answers, read back OFF THE SKELETON —
	never off a cached copy of what was written, or a deleted write would still
	measure. See `hero_rig_limbs.measure()` for the contract; the four limb keys
	are the shoulder and hip bones, which are what the limb rig's four nodes are.
	"""
	var body_rest: Vector3 = _rest.get("body", Vector3.ZERO)
	var out: Dictionary = {
		"left_arm_x": _axis(UPPERARM["left"], AXIS_X),
		"right_arm_x": _axis(UPPERARM["right"], AXIS_X),
		"left_leg_x": _axis(THIGH["left"], AXIS_X),
		"right_leg_x": _axis(THIGH["right"], AXIS_X),
		"left_arm_z": _axis(UPPERARM["left"], AXIS_Z),
		"right_arm_z": _axis(UPPERARM["right"], AXIS_Z),
		"left_leg_z": _axis(THIGH["left"], AXIS_Z),
		"right_leg_z": _axis(THIGH["right"], AXIS_Z),
		"body_y": _body.position.y,
		"body_x": _body.rotation.x - body_rest.x,
		"body_z": _body.rotation.z - body_rest.z,
	}
	if has_head():
		out["head_z"] = _axis(HEAD, AXIS_Z)
	return out


# ============================================================================
# THE ONE PLACE A BONE IS READ OR WRITTEN — see the roll trap in the banner
# ============================================================================

func _off_rest(bone: String) -> Basis:
	"""This bone's current rotation off its rest, in SKELETON axes: undo the
	rest, then conjugate the bone-local turn out through the parent's basis."""
	var b: Dictionary = _bones[bone]
	var local: Basis = Basis(_skel.get_bone_pose_rotation(b["idx"])) * (b["r_inv"] as Basis)
	return (b["p"] as Basis) * local * (b["p_inv"] as Basis)


func _axis(bone: String, axis: int) -> float:
	return _off_rest(bone).get_euler()[axis]


func _set_axis(bone: String, axis: int, value: float) -> void:
	"""Write ONE skeleton-space euler component of this bone's rotation off
	rest, leaving the other two — exactly what `node.rotation.x = v` does."""
	var e: Vector3 = _off_rest(bone).get_euler()
	e[axis] = value
	var b: Dictionary = _bones[bone]
	var local: Basis = (b["p_inv"] as Basis) * Basis.from_euler(e) * (b["p"] as Basis)
	_skel.set_bone_pose_rotation(b["idx"],
			(local * (b["r"] as Basis)).get_rotation_quaternion())
