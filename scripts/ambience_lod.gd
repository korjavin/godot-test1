extends RefCounted
## THE AMBIENCE COARSE TICK — "only those moving who we can see", without freezing.
##
## OWNER (2026-09-02, bead godot-test1-8gw.22): "it's better to find a way how not
## to kill performance with cars/crowds, at the same time I want this natural. And
## we may use the same trick - only those moving who we can see".
##
## Shared by BOTH ambience managers (crowd_manager.gd, traffic_manager.gd) because
## the rule and its tick rate must be ONE number: two copies drift, and the two
## managers are the same problem twice. Nothing else may use it — this is a budget
## for scenery, never for anything a predator, a coin or a player can touch.
##
## ----------------------------------------------------------------------------
## A COARSE TICK, NOT A FREEZE — this is the whole design
## ----------------------------------------------------------------------------
## The naive reading of "only update what we can see" is a binary freeze, and it
## looks wrong the first time the player spins around: a street of citizens caught
## mid-stride like statues, then all snapping into motion at once. The owner asked
## for NATURAL in the same sentence. So an out-of-view instance is not skipped, it
## is ticked COARSELY — a few times a second instead of sixty — and when its tick
## comes it advances by the REAL ELAPSED TIME since its last one, not by one
## frame's worth. Cost falls by the tick ratio; nothing is ever static; turning
## around shows a street that has plausibly kept walking.
##
## That is exactly `crocodile_lod_manager.gd`'s shape one step further:
## `_scan_crocodiles(elapsed)` already takes the real elapsed time rather than a
## frame delta for the same reason, and CLAUDE.md's "distant crocodiles are slept,
## NEVER removed" holds here as "never deleted, only ticked slower" — no citizen
## and no car is ever destroyed by this file, and no cap moves.
##
## ----------------------------------------------------------------------------
## THREE TRAPS, handled here rather than discovered in the field
## ----------------------------------------------------------------------------
##  * THE PLAYER IS NOT THE CAMERA. `C` cycles third-person / first-person /
##    FRONT, and the FRONT view looks BACKWARD along the hero — so "in front of
##    the player" is the wrong question in one of the three shipped views. We ask
##    the VIEWPORT for its active camera (the project's discovery rule: never a
##    hard reference, never a `$`-path) and test against that camera's own
##    frustum, which is right in all three by construction.
##  * A MARGIN, or an instance pops into full-rate motion exactly as it enters
##    view. The margin is in world metres on every frustum plane, so it widens the
##    view in all directions (the case that bites is the player TURNING, which a
##    depth-only margin would not cover).
##  * A NULL CAMERA — headless, a self-check harness, a scene run standalone —
##    degrades to "everything is visible", i.e. today's behaviour at full rate.
##    Never to "nothing updates".

## How often an out-of-view instance takes its step. MEASURED, not guessed:
## at the desktop caps (120 citizens + 32 cars) the two managers' per-frame work
## is ~1.30 ms, of which the out-of-view share falls by this ratio — 0.25 s
## against a 60 Hz frame is 15x, which took the ambience budget from 1.30 ms to
## ~0.35 ms with a camera in the scene (see the PR body for the table).
## Faster than this buys little (the cost is already off the profile); slower
## starts to show as a visible hop when an instance enters view mid-step: a
## citizen covers 0.7 m and a car 1.6 m per tick at this rate, both well inside
## the margin below, so every hop happens out of sight.
const COARSE_TICK_SECONDS: float = 0.25

## How far outside the frustum still counts as visible, in metres. It must
## comfortably exceed one coarse tick of travel (1.6 m for the fastest car) so
## that an instance is already running at full rate for several tenths of a
## second before it can appear on screen.
const FRUSTUM_MARGIN: float = 12.0


static func view_planes(vp: Viewport) -> Array[Plane]:
	"""The active camera's frustum planes, or EMPTY when there is no camera —
	empty means 'everything is visible', which is the degrade every headless
	harness and every standalone scene gets."""
	if vp == null:
		return []
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return []
	return cam.get_frustum()


static func is_visible_at(planes: Array[Plane], pos: Vector3) -> bool:
	"""Frustum-plus-FRUSTUM_MARGIN test. `Camera3D.get_frustum()` hands back
	OUTWARD-facing planes (`is_position_in_frustum` rejects on
	`distance_to(p) > 0`), so this is that test with the rejection threshold
	pushed out by the margin. Empty planes => visible, see `view_planes`."""
	if planes.is_empty():
		return true
	for p: Plane in planes:
		if p.distance_to(pos) > FRUSTUM_MARGIN:
			return false
	return true


static func step_delta(rec: Dictionary, delta: float, visible: bool) -> float:
	"""How long this record should advance by THIS frame; 0.0 means 'not its tick'.

	A visible record advances every frame, and carries in whatever debt it built
	up while it was out of view — that carried remainder is what makes coming
	back into view seamless rather than a jump. An out-of-view record banks the
	frame and returns 0.0 until the bank reaches COARSE_TICK_SECONDS, then
	spends the WHOLE bank at once (the real elapsed time, never one frame's
	worth) — which is why it keeps walking instead of standing still."""
	var banked: float = float(rec.get("lod_debt", 0.0))
	if visible:
		rec["lod_debt"] = 0.0
		return delta + banked
	banked += delta
	if banked < COARSE_TICK_SECONDS:
		rec["lod_debt"] = banked
		return 0.0
	rec["lod_debt"] = 0.0
	return banked
