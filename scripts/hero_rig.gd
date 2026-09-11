class_name HeroRig
extends RefCounted
## THE RIG-KIND SEAM (bd godot-test1-5u3.2, epic `5u3` — skinned heroes).
##
## A hero model is posed by ONE of two drivers, and this file is the only place
## that knows both exist:
##
##   * `hero_rig_limbs.gd`   — the sine limb rig this game shipped with. `Body`
##                             with `LeftArm` / `RightArm` / `LeftLeg` /
##                             `RightLeg` (and an optional `Head`) under it,
##                             found by EXACT NAME, rotations written per node.
##   * `hero_rig_skeleton.gd`— a skinned hero on a `Skeleton3D`: the same two
##                             sines written onto BONES, so knees and elbows
##                             bend.
##
## THE SCENE IS THE FLAG. There is no exported switch and no per-hero table
## entry: a character scene that brings a `Skeleton3D` gets the skinned driver,
## anything else keeps the limb driver byte-for-byte. That is what lets the four
## heroes migrate ONE AT A TIME (children `5u3.3`, `.5`, `.6`, `.7`) with the
## game playable after every one of them.
##
## THE CALLERS — `player_animation.gd` (local), `remote_avatar.gd` (mirror) and,
## for the one authored still pose, `tower_interior.gd` (a jailed hero's slump,
## bd godot-test1-6su) — reach THIS file through its `class_name` and nothing
## below it, so the pose contract has exactly one import site (CLAUDE.md: a
## family reaches a sibling through the node that owns the state). No driver
## knows about any caller, so there is no cycle to make.
##
## WHAT THE DRIVERS DO NOT OWN: the clock. The caller keeps `animation_time` (or
## the remote's distance-driven `stride_phase`), computes the two sines, fires
## the footstep on the stride's sign flip, and writes the `Body` NODE's bob,
## lean and sway — for BOTH rig kinds, because every hero scene has a `Body`
## above whatever is under it and the landing squash, `capture_rest_pose()` and
## Teibi's resize all already ride it. The drivers write LIMB pose only. That is
## what keeps the local hero and the remote mirror the same pure function of
## (hero, phase, gait state) with nothing added to the presence packet.

const LIMB_RIG: GDScript = preload("res://scripts/hero_rig_limbs.gd")
const SKELETON_RIG: GDScript = preload("res://scripts/hero_rig_skeleton.gd")


static func for_body(body: Node3D, rest: Dictionary) -> RefCounted:
	"""
	Pick this model's driver and bind it, or return null if nothing here can be
	posed (the "frozen model" case the limb contract has always allowed: a scene
	that spells a limb differently loads, stands still and errors nowhere).

	DISCOVERY IS BY TYPE, never by `$`-path: `find_children("*", "Skeleton3D")`
	with `owned` false, because the skeleton arrives inside an INSTANCED `.glb`
	and is owned by that scene, not by ours.

	@param body: the character's `Body` node — every hero scene has one
	@param rest: the rest-pose table `PlayerAnimation.capture_rest_pose()` read
	             off the model while it was still untouched. The limb driver
	             animates as offsets from it; the skinned driver uses the
	             skeleton's own bone rests for the limbs and reads only the `body`
	             key, which is the caller's, not either rig's.
	"""
	if body == null:
		return null
	var skeletons: Array[Node] = body.find_children("*", "Skeleton3D", true, false)
	var rig: RefCounted = SKELETON_RIG.new() if not skeletons.is_empty() else LIMB_RIG.new()
	return rig if rig.bind(body, rest) else null
