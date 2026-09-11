extends RefCounted
## THE SINE LIMB RIG — the pose this game has always drawn, MOVED behind the
## `hero_rig.gd` seam (bd godot-test1-5u3.2). Not one number, not one sign and
## not one branch changed: every line below is `player_animation.gd`'s or
## `remote_avatar.gd`'s own write, with the rest value it reads spelled `_rest`
## instead of `original_rotations` / `rest_rotations`.
##
## THE NODE-NAME CONTRACT, unchanged and still the whole rig for these heroes:
## `LeftArm` / `RightArm` / `LeftLeg` / `RightLeg` under `Body`, found by EXACT
## NAME, plus an OPTIONAL `Head` whose absence is not an error — a row with
## `head_deg` simply draws nothing. A scene that spells one of the four
## differently binds nothing (`bind()` false), and the model stands frozen
## exactly as it did before this file existed.
##
## WHY BOTH CALLERS FIT THE SAME SIX WRITES. The local player drives the cycle
## off `animation_time`; the remote mirror drives it off a distance-accumulated
## `stride_phase` with an amplitude that fades in with speed. Written out, those
## two are the SAME pose expression with a different `arm_swing` / `leg_swing`
## handed in — so the caller keeps its own clock and this file cannot make the
## mirror diverge from the body it is a picture of.
##
## WHAT THIS DOES NOT TOUCH: the `Body` node. Its bob, lean, sway and the
## landing squash stay with the caller for both rig kinds — see `hero_rig.gd`.

## The four limbs and the optional head, by exact name under `Body`.
var _left_arm: Node3D = null
var _right_arm: Node3D = null
var _left_leg: Node3D = null
var _right_leg: Node3D = null
var _head: Node3D = null

## The `Body` node itself — written by the caller, READ here only by `measure()`
## so one accessor answers the whole pose.
var _body: Node3D = null

## The rest-pose table this pose is an offset from: `capture_rest_pose()`'s
## dictionary, keyed `left_arm` / `right_arm` / `left_leg` / `right_leg` /
## `head` / `body` onto `Vector3` rotations. Captured while the model was still
## untouched, so re-activating a character mid-stride never drifts it.
var _rest: Dictionary = {}


func kind() -> String:
	return "limbs"


func bind(body: Node3D, rest: Dictionary) -> bool:
	"""
	Find the limbs under `body` and adopt `rest` as the pose they swing around.

	SILENT, deliberately: `remote_avatar.gd` binds through this same seam on
	every peer's model swap, and that path printed nothing before the seam
	existed. The local swap log keeps its one line, in
	`PlayerAnimation.setup_animation_references()`, where only the local player
	reaches it.

	@return false when the four limbs are not all there — the caller then holds
	        no rig at all and every pose function returns early, which is the
	        "frozen model" behaviour the exact-name contract has always had.
	"""
	_body = body
	_rest = rest
	_left_arm = body.get_node_or_null("LeftArm")
	_right_arm = body.get_node_or_null("RightArm")
	_left_leg = body.get_node_or_null("LeftLeg")
	_right_leg = body.get_node_or_null("RightLeg")
	_head = body.get_node_or_null("Head")
	return _left_arm != null and _right_arm != null \
			and _left_leg != null and _right_leg != null


func has_head() -> bool:
	return _head != null and _rest.has("head")


func rest_pose() -> void:
	"""Snap every limb (and the head) back to the cached rest rotation."""
	if _left_arm and _rest.has("left_arm"):
		_left_arm.rotation = _rest["left_arm"]
	if _right_arm and _rest.has("right_arm"):
		_right_arm.rotation = _rest["right_arm"]
	if _left_leg and _rest.has("left_leg"):
		_left_leg.rotation = _rest["left_leg"]
	if _right_leg and _rest.has("right_leg"):
		_right_leg.rotation = _rest["right_leg"]
	if _head and _rest.has("head"):
		_head.rotation = _rest["head"]


func locomotion(arm_swing: float, leg_swing: float, arm_asym: float) -> void:
	"""
	One frame of the walk/run cycle: arms and legs swinging in diagonal
	opposition on X, the LEFT arm carrying the row's asymmetry.

	The two swings arrive already scaled by the caller — `stride * amplitude`
	locally, `sin(stride_phase) * amount * amplitude` on the mirror — which is
	exactly what makes those two the same pose.
	"""
	_left_arm.rotation.x = _rest["left_arm"].x + arm_swing * arm_asym
	_right_arm.rotation.x = _rest["right_arm"].x - arm_swing

	_left_leg.rotation.x = _rest["left_leg"].x - leg_swing
	_right_leg.rotation.x = _rest["right_leg"].x + leg_swing


func head_bobble(angle: float) -> void:
	"""The optional head's roll, `angle` radians off its rest."""
	if _head and _rest.has("head"):
		_head.rotation.z = _rest["head"].z + angle


func relax_head(weight: float) -> void:
	"""Ease the head bobble back to rest (1.0 snaps)."""
	if _head and _rest.has("head"):
		_head.rotation.z = lerp(_head.rotation.z, float(_rest["head"].z), weight)


func idle(weight: float) -> void:
	"""Ease the four limbs' forward/back swing back to rest."""
	_left_arm.rotation.x = lerp(_left_arm.rotation.x, float(_rest["left_arm"].x), weight)
	_right_arm.rotation.x = lerp(_right_arm.rotation.x, float(_rest["right_arm"].x), weight)

	_left_leg.rotation.x = lerp(_left_leg.rotation.x, float(_rest["left_leg"].x), weight)
	_right_leg.rotation.x = lerp(_right_leg.rotation.x, float(_rest["right_leg"].x), weight)


func air(spread: float, tuck: float, weight: float) -> void:
	"""
	The airborne pose: arms rolled out to the sides (the wing beat is already
	inside `spread`), forward/back swing cleared so the wings sit level, legs
	tucked forward.

	`weight` is how fast the legs get there — the local player eases them (0.2
	a frame), the remote mirror snaps (1.0), exactly as both did before.
	"""
	_right_arm.rotation.z = _rest["right_arm"].z + spread
	_left_arm.rotation.z = _rest["left_arm"].z - spread
	# Clear any leftover forward/back swing from walking so the wings sit level.
	_right_arm.rotation.x = _rest["right_arm"].x
	_left_arm.rotation.x = _rest["left_arm"].x

	_left_leg.rotation.x = lerp(_left_leg.rotation.x, _rest["left_leg"].x + tuck, weight)
	_right_leg.rotation.x = lerp(_right_leg.rotation.x, _rest["right_leg"].x + tuck, weight)


func drop_wings() -> void:
	"""Touchdown: the arm roll back to the sides, nothing else."""
	if _left_arm and _rest.has("left_arm"):
		_left_arm.rotation.z = _rest["left_arm"].z
	if _right_arm and _rest.has("right_arm"):
		_right_arm.rotation.z = _rest["right_arm"].z


func sidestep(splay: float, reach: float, lift_left: bool, lift: float,
		arm_bias: float, arm_swing: float) -> void:
	"""
	One frame of the sideways shuffle, rolled on Z so it reads as sideways and
	never fights the walk's X. The two legs open and close around the lean;
	whichever is currently reaching gets `lift` on top (`lift_left` is the
	caller's `cycle * direction >= 0.0` — see `sidestep_pose()`'s note on why
	the step's sign belongs in that test).
	"""
	_left_leg.rotation.z = _rest["left_leg"].z + splay + reach
	_right_leg.rotation.z = _rest["right_leg"].z + splay - reach
	if lift_left:
		_left_leg.rotation.z += lift
	else:
		_right_leg.rotation.z += lift

	_left_arm.rotation.z = _rest["left_arm"].z - arm_bias - arm_swing
	_right_arm.rotation.z = _rest["right_arm"].z - arm_bias + arm_swing


func reset_roll() -> void:
	"""Every limb's sideways roll back to rest — the sidestep is the only pose
	that writes it, so nothing else puts it back."""
	if _left_arm and _rest.has("left_arm"):
		_left_arm.rotation.z = _rest["left_arm"].z
	if _right_arm and _rest.has("right_arm"):
		_right_arm.rotation.z = _rest["right_arm"].z
	if _left_leg and _rest.has("left_leg"):
		_left_leg.rotation.z = _rest["left_leg"].z
	if _right_leg and _rest.has("right_leg"):
		_right_leg.rotation.z = _rest["right_leg"].z


func measure() -> Dictionary:
	"""
	THE POSE, AS NUMBERS — the one accessor `gait_selfcheck` and
	`capture_selfcheck` read instead of reaching for limb nodes, so the checks
	are rig-agnostic and a skinned hero is measurable by the same bounds.

	EVERY ROTATION IS OFF REST, in radians; `body_y` is the `Body` node's own
	metres (its rest is 0 by `restore_rest_pose()`). Off-rest rather than
	absolute because that is what all four reading sites already computed by
	hand — and because on a skeleton "absolute" has no shared meaning: the rest
	pose is wherever MakeHuman left the bone.
	`head_z` is ABSENT when the model has no head, mirroring the
	`original_rotations.has("head")` guard every pose function already carries.
	"""
	var out: Dictionary = {
		"left_arm_x": _left_arm.rotation.x - float(_rest["left_arm"].x),
		"right_arm_x": _right_arm.rotation.x - float(_rest["right_arm"].x),
		"left_leg_x": _left_leg.rotation.x - float(_rest["left_leg"].x),
		"right_leg_x": _right_leg.rotation.x - float(_rest["right_leg"].x),
		"left_arm_z": _left_arm.rotation.z - float(_rest["left_arm"].z),
		"right_arm_z": _right_arm.rotation.z - float(_rest["right_arm"].z),
		"left_leg_z": _left_leg.rotation.z - float(_rest["left_leg"].z),
		"right_leg_z": _right_leg.rotation.z - float(_rest["right_leg"].z),
		"body_y": _body.position.y,
		"body_x": _body.rotation.x - float(_rest["body"].x),
		"body_z": _body.rotation.z - float(_rest["body"].z),
	}
	if has_head():
		out["head_z"] = _head.rotation.z - float(_rest["head"].z)
	return out
