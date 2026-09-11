extends SceneTree
## ============================================================================
## HERO GAIT SELF-CHECK — the walk personality table (bead godot-test1-cne)
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/gait_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: `player_controller.GAITS` turned four literals inside
## `animate_walking()` into a per-hero table, and every failure mode of that
## change is SILENT on a headless machine and easy to miss on a running one:
##
##   * a row with a typo'd field draws the DEFAULT value and looks fine;
##   * an amplitude tuned one notch too far puts a foot under the flat world at
##     y = 0, or a body far enough off its collision capsule to read as detached;
##   * the "unpredictable" claim rests entirely on the hitch sine's period being
##     incommensurate with the stride's — collapse the two and the walk is a
##     metronome again, with nothing failing anywhere;
##   * the footstep SFX fire on the STRIDE sine's sign flip, so a hitch that
##     touched the phase instead of the amplitude would silently retime every
##     footstep and every wading splash in the game.
##
## So the pose is MEASURED: driven on a real `scenes/player.tscn`, through the
## shipped `animate_walking()`, over a 60 s sweep per hero.
##
## SINCE bd godot-test1-5u3.2 every one of those measurements is read through
## ONE accessor, `player.anim.rig.measure()`, instead of off four limb nodes —
## because a hero is no longer always five nodes. That bought check 8, which
## runs the same bounds, the same non-periodicity test and a determinism probe
## against the SKINNED Teibi — since bead godot-test1-5u3.3 the SHIPPED one
## (`scenes/characters/teibi.tscn`), a model with no `LeftArm` at all. The other
## three heroes in `CHARACTERS` are still on the limb rig, and checks 1-7 —
## which run every hero in `CHARACTERS`, Teibi included — still measure exactly
## what they measured, through `rig.measure()`, on whichever driver each took.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const PlayerController := preload("res://scripts/player_controller.gd")

## THE END-OF-CHECK SENTINEL — see scripts/selfcheck_sentinel.gd.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## Pose bounds, straight off the bead. A limb further round than this is not a
## walk cycle any more, and the body band is what keeps the model looking
## attached to a collision capsule that does NOT move with it.
const LIMB_LIMIT_DEG: float = 75.0
const BODY_Y_MIN: float = -0.05
const BODY_Y_MAX: float = 0.10
## The head is optional and only ever bobbles; this is a sanity ceiling on the
## offset from its rest rotation, not a limb bound.
const HEAD_LIMIT_DEG: float = 15.0

## The sweep: 60 s of walking sampled at 240 Hz, which is well inside the
## Nyquist limit of the fastest row (Primm's 10.6 rad/s stride).
const SWEEP_SECONDS: float = 60.0
const SWEEP_HZ: float = 240.0

## The non-periodicity window, and how far apart two poses one stride period
## apart must get before we believe the hitch exists. One degree is far below
## every row's hitch amplitude and far above float noise.
const HITCH_SECONDS: float = 20.0
const HITCH_EPS_DEG: float = 1.0

## Stopping: how many idle frames the eased relax gets, and how close to rest
## the gait's own axes must then be. 120 frames is 2 s at 60 Hz against a 0.15
## per-frame lerp, so a working relax arrives with three orders of magnitude to
## spare and a dropped one is nowhere near.
const RELAX_FRAMES: int = 120
const REST_EPS: float = 0.005

## The footstep window. Chosen so no row's crossing lands within a sample of the
## window's end, which would make the expected count ambiguous by one.
const STEP_SECONDS: float = 10.0

## Today's numbers, written out rather than read from the table — the whole
## point of check 1 is that the DEFAULT row still says what `animate_walking()`
## said as literals before the table existed.
const TODAY: Dictionary = {
	"stride_rate": 8.0, "arm_deg": 30.0, "leg_deg": 40.0, "bob": 0.03,
	"arm_asym": 1.0, "sway_deg": 0.0, "lean_deg": 0.0, "head_deg": 0.0,
	"hitch": 0.0, "phase": 0.0, "idle_rate": 2.0, "idle_bob": 0.01,
}

## THE SIDESTEP SWEEP (bead godot-test1-3ek). Metres of held strafe, and the
## speed the probe drives them at — the cycle is DISTANCE-driven, so what the
## sweep has to cover is ground, not seconds. 6 m is a little over three full
## DEFAULT cycles (TAU / SIDESTEP_PHASE_PER_METRE = 1.96 m each), which is
## enough for every hero's slower or faster rate to close at least one.
const STRAFE_METRES: float = 6.0
const STRAFE_SPEED: float = 5.0

## How far apart two poses in one strafe must get before the cycle counts as a
## cycle. Same reasoning and the same number as `HITCH_EPS_DEG`: far below every
## row's amplitude, far above float noise.
const STRAFE_EPS_DEG: float = 1.0

## How far apart the roster's WIDEST and NARROWEST strafe must be on each of the
## three personality axes (leg amplitude, arm amplitude, step rate).
##
## A SPREAD and not "the four numbers differ", which is the trap this replaced:
## the amplitudes are a SAMPLED max and min of a sine, so four heroes whose
## phases land at slightly different points on the peak read as four distinct
## numbers even with the scaling pinned to 1.0 — measured, they differed in the
## fourth decimal and a distinctness test passed. The rows really spread these by
## 1.9x, 2.0x and 1.6x, so 1.1 is far above the sampling noise and far below
## every real spread.
const PERSONALITY_SPREAD: float = 1.1

## CHECK 8's FIXTURE (bd godot-test1-5u3.2) — the skinned Teibi. It was the
## spike's own scratch scene while no hero shipped skinned; since bead
## godot-test1-5u3.3 it is the SHIPPED hero, so this check now measures the thing
## the game draws rather than a model beside it. Hard-coded rather than "whichever
## CHARACTERS row brings a Skeleton3D", because a fixture that goes looking for
## its own subject reports SELFCHECK OK on the day the last skinned hero is
## mis-wired back onto the limb rig — which is the one thing checks 1-7 cannot
## see either (they measure through `rig.measure()`, whichever driver answers).
const SKINNED_FIXTURE: String = "res://scenes/characters/teibi.tscn"
## Teibi's row asks for no head bobble, and an axis nothing measures is an axis
## that can be deleted in silence — so the fixture runs his row with this forced
## in. Well under `HEAD_LIMIT_DEG`, well over `SKINNED_MOVE_DEG`.
const FIXTURE_HEAD_DEG: float = 5.0
## How far an axis the driver claims must move before we believe it is written,
## and how wide the stride must be open before "which way is this limb going"
## means anything. Same reasoning and the same number as `HITCH_EPS_DEG`.
const SKINNED_MOVE_DEG: float = 1.0
## The fixture's sweep. Shorter than `SWEEP_SECONDS` because a bone pose costs
## a basis conjugation per axis where a node pose costs a float store, and 20 s
## at 240 Hz is still ~16 stride periods of Teibi's slow row at both speeds —
## far more than enough for the envelope and the diagonal.
const SKINNED_SWEEP_SECONDS: float = 20.0
## An arbitrary clock the determinism probe asks twice about — arbitrary on
## purpose: a round number could land on a sine zero and compare two rest poses.
const SKINNED_PROBE_TIME: float = 12.34
## The swing checks (h) and (i) drive the thigh and the shoulder to, either way,
## and how far the knee must then have travelled for the pose to count as having
## reached the skeleton at all. 30 degrees is a probe amplitude, not a hero's: it
## sits inside the fixture's own row (Teibi walks at `leg_deg` 44) and well
## inside `LIMB_LIMIT_DEG`, which is all it has to be — nothing here is measuring
## a `GAITS` value. Teibi's thigh is ~0.45 m, so the two extremes sit ~0.45 m
## apart and 5 cm is far below that and far above the float noise in a bone chain.
const SKINNED_JOINT_SWING_DEG: float = 30.0
const SKINNED_JOINT_TRAVEL_M: float = 0.05
## ...and how much SHORTER the hip-to-foot reach must get on the back-swing,
## where the knee flexes. `KNEE_FLEX_RATIO` 0.8 turns a 30-degree swing into a
## 24-degree bend, which on Teibi's ~0.45 m thigh and calf pulls the foot in by a
## measured 0.031 m. 0.015 is half of that and three times any float noise; a
## deleted or straightened knee write measures exactly 0.
const SKINNED_KNEE_FLEX_M: float = 0.015
## ...and how much of that travel may be SIDEWAYS. A forward/back swing about
## the skeleton's own X carries the knee along ±Z and nowhere else: measured on
## the shipped conjugation the ratio is 7e-8. Conjugating through the bone's own
## rest basis instead of its parent's — the realistic wrong edit, and one
## `measure()` provably cannot see because the basis cancels in it — measures
## 0.195 m sideways against 0.378 m forward, a ratio of 0.52. Anywhere between
## is a rig being turned about a roll it should be agnostic to.
const SKINNED_ROLL_TOLERANCE: float = 0.05
## ...and how much the shoulder-to-hand reach must differ between the two arm
## extremes, where `ELBOW_TRACK_RATIO` 0.3 opens the elbow from 24 to 6 degrees.
## Measured 0.008 m on Teibi's ~0.28 m upper arm and forearm; a deleted or
## constant elbow write measures exactly 0, and the float noise in a three-bone
## chain is five orders below either.
const SKINNED_ELBOW_M: float = 0.003

# ---------------------------------------------------------------------------
# BEAD godot-test1-5u3.9 — the GAIT-QUALITY probes' own numbers
# ---------------------------------------------------------------------------
## How level the SOLE has to be at a contact frame, as |dy| over the length of
## the foot-to-ball vector — i.e. the tangent of its tilt. The ankle gives the
## whole (thigh + knee) chain back, so what is left is the pelvis's own 3-degree
## roll. Deleting the ankle write leaves the sole riding a 30-degree thigh.
const SKINNED_SOLE_LEVEL: float = 0.15
## ...and how far below its own rest height the ball of the foot may go at a
## contact frame. The world is flat at y = 0 (CLAUDE.md) and this rig has no IK,
## so a stance foot RISES on an arc as the hip swings — what must never happen is
## the sole going the other way and sinking through the ground.
const SKINNED_SOLE_SINK_M: float = 0.002
## How much shorter hip-to-foot must get at the peak of a landing squash than
## with no landing at all. `knee_land_deg` 24 on Teibi's ~0.45 m thigh and calf
## pulls the foot in; a deleted `_land` term measures exactly 0.
const SKINNED_LAND_KNEE_M: float = 0.008
## THE COUNTER-ROTATION, as two numbers that have to disagree: the PELVIS must
## roll at full stride and the CHEST above it must not. Measured as the Y
## component of each bone's own left-right axis — the sine of its roll, unit-free
## and independent of how far apart any two bones happen to sit. Delete
## `spine_02`'s counter and the chest rolls with the pelvis, which is the
## marionette this bead exists to stop.
const SKINNED_PELVIS_ROLL: float = 0.015
const SKINNED_CHEST_LEVEL: float = 0.008
## The BREATH: how far the chest bone must travel over one breath cycle, and the
## ceiling it must stay under. 1.1 degrees of pitch at `spine_03` is a few mm —
## big enough to see a body that is alive, small enough not to read as a nod.
const SKINNED_BREATH_M: float = 0.0008
const SKINNED_BREATH_CEILING_M: float = 0.030
## ...and the standing WEIGHT SHIFT, measured the same way and on the same bone:
## `shift_deg` 2.2 of pelvis roll moves a head a metre up the chain by ~0.04 m.
const SKINNED_SHIFT_M: float = 0.004
const SKINNED_SHIFT_CEILING_M: float = 0.120
## THE SHOULDER FOLLOWING ITS ARM: how far the shoulder must travel forward/back
## between the arm's two extremes. `shoulder_swing_deg` 5 on a ~0.17 m clavicle
## moves it ~0.030 m over the pair; a deleted clavicle write moves it 0, because
## `spine_02` cancels the pelvis's twist before it can reach a shoulder.
const SKINNED_SHOULDER_SWING_M: float = 0.004
## ...and the PELVIS TWIST, as the X component of the pelvis's own forward axis —
## the sine of its yaw, read the same unit-free way its roll is.
const SKINNED_PELVIS_TWIST: float = 0.030
## THE SKINNED BAND (bead godot-test1-5u3.9). `measure()` answers the shoulder
## and the hip and deliberately nothing else, so the seven bones this bead added
## need an envelope of their own — and it is measured as the ANGLE FROM REST of
## the bone's own pose quaternion, which needs no conjugation and is therefore a
## reading the driver's own arithmetic cannot flatter. Ceilings in degrees, one
## per bone family (the right side rides the same row).
const SKINNED_BAND_DEG: Dictionary = {
	"calf": 75.0, "foot": 45.0, "lowerarm": 85.0,
	"clavicle": 12.0, "pelvis": 12.0, "spine_02": 12.0, "spine_03": 6.0,
}
## How far apart two drivers at the same clock may draw one bone, as the largest
## difference between any two COMPONENTS of the pose quaternions. It is a
## FLOAT-NOISE tolerance, not a band: the two instances run the same arithmetic
## on the same numbers, so anything above this is a driver reading something it
## was not handed (a clock of its own, the previous frame, an RNG).
##
## COMPONENTS AND NOT `Quaternion.angle_to()`, which cannot resolve this at all:
## it computes `acos(2·dot² - 1)`, and `acos` near 1 turns a one-ULP error in the
## dot product into `sqrt(8·eps)` — 9.8e-4 rad on float32. Two BIT-IDENTICAL
## poses measure zero either way, but two poses one ULP apart measure 0.00098 rad
## through `angle_to` and 6e-8 here (both measured on this bead).
const SKINNED_DETERMINISM_EPS: float = 1e-6
## ...and the same comparison made WITHOUT resetting the two skeletons first, so
## one of them arrives carrying 430 frames of history. `_set_axis` is a
## read-modify-write by design (it is `node.rotation.x = v`), so the components a
## pose path does not write are round-tripped through `get_euler` / `from_euler`
## and a basis conjugation every frame, and in float32 that walks: MEASURED
## 2.2e-5 after 430 frames, against 0 when both are reset. This ceiling is four
## times that and four orders under anything a stray `randf()`, clock read or
## frame-to-frame accumulator would produce.
## `ponytail:` the real fix is for every pose path to STATE its bones' whole
## triples the way `_torso()` now does, which removes the round trip entirely —
## out of this bead's scope because `sidestep()` deliberately inherits the walk's
## thigh pitch, so it cannot state a triple without changing what a strafe draws.
const SKINNED_DRIFT_EPS: float = 1e-4
## The clocks the determinism probe compares at — several, and none of them
## round, so a driver whose hidden state happens to agree at one phase cannot
## pass.
const SKINNED_DETERMINISM_TIMES: Array[float] = [0.37, 3.19, 7.71, 12.34]

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# The measuring half is its own coroutine: `_initialize()` cannot await, and
	# reporting here would print a verdict at frame 0, before the player scene
	# has had a single frame to build itself — a vacuous pass.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("catalogue")
		Sentinel.done("bounds")
		Sentinel.done("expression")
		Sentinel.done("relax")
		Sentinel.done("personality")
		Sentinel.done("footsteps")
		Sentinel.done("sidestep")
		Sentinel.done("skinned")
		Sentinel.done("skinned_joints")
		Sentinel.done("skinned_determinism")
		_report()
		return

	_check_catalogue()

	var player: Node3D = packed.instantiate()
	root.add_child(player)
	await process_frame
	await physics_frame

	if player.anim.rig == null or player.anim.character_body == null:
		_fail("player.tscn bound no pose rig — the Body/LeftArm/... node-name "
				+ "contract is broken (or no Skeleton3D took its place), and no "
				+ "pose below could be measured")
		Sentinel.done("bounds")
		Sentinel.done("expression")
		Sentinel.done("relax")
		Sentinel.done("personality")
		Sentinel.done("footsteps")
		Sentinel.done("sidestep")
		Sentinel.done("skinned")
		Sentinel.done("skinned_joints")
		Sentinel.done("skinned_determinism")
		player.queue_free()
		_report()
		return

	_check_bounds(player)
	_check_relax(player)
	_check_personality(player)
	_check_footsteps(player)
	_check_sidestep(player)
	_check_skinned(player)

	player.queue_free()
	await process_frame
	_report()


# ============================================================================
# CHECK 1 — THE TABLE ITSELF
# ============================================================================

func _check_catalogue() -> void:
	"""
	Every hero has a row, the DEFAULT row is still today's walk, and no row
	carries a field the animation never reads.
	"""
	var default_row: Dictionary = PlayerAnimation.GAITS.get("DEFAULT", {})
	if default_row.is_empty():
		_fail("GAITS has no DEFAULT row — an unknown hero would resolve nothing")
		Sentinel.done("catalogue")
		return

	# (a) The DEFAULT row IS the pre-table cycle, field by field.
	for key: String in TODAY:
		if not default_row.has(key):
			_fail("GAITS DEFAULT is missing field '%s'" % key)
			continue
		if not is_equal_approx(float(default_row[key]), float(TODAY[key])):
			_fail("GAITS DEFAULT['%s'] is %s, but animate_walking() used %s before "
					% [key, default_row[key], TODAY[key]]
					+ "the table existed — an unknown hero must animate as it always did")
	for key: String in default_row:
		if not TODAY.has(key):
			_fail("GAITS DEFAULT carries unexpected field '%s' — add it to this "
					% key + "check's TODAY table with the value that reproduces today's walk")

	# (b) Every playable hero resolves a row of their own, and `gait_for()` is
	#     total: an unknown name must come back as DEFAULT rather than empty.
	for entry: Dictionary in PlayerController.CHARACTERS:
		var hero: String = String(entry["name"])
		if not PlayerAnimation.GAITS.has(hero):
			_fail("no GAITS row for hero '%s'" % hero)
		var row: Dictionary = PlayerAnimation.gait_for(hero)
		for key: String in TODAY:
			if not row.has(key):
				_fail("resolved gait for '%s' is missing field '%s'" % [hero, key])
	var unknown: Dictionary = PlayerAnimation.gait_for("no-such-hero")
	for key: String in TODAY:
		if not unknown.has(key) or not is_equal_approx(float(unknown[key]), float(TODAY[key])):
			_fail("gait_for('no-such-hero')['%s'] is not the DEFAULT value — a fifth "
					% key + "character must animate exactly as this game did before GAITS")

	# (c) A typo'd field is the silent failure this catches: it merges in, the
	#     animation never reads it, and the hero walks on the DEFAULT value.
	for hero: String in PlayerAnimation.GAITS:
		for key: String in PlayerAnimation.GAITS[hero]:
			if not TODAY.has(key):
				_fail("GAITS['%s'] carries field '%s', which DEFAULT does not declare — "
						% [hero, key] + "the animation never reads it")
		# (d) The hitch modulates amplitude by `1 + hitch * sin(...)`. At 1.0 or
		#     above that factor reaches zero and then goes NEGATIVE, which
		#     inverts the legs mid-step.
		var amount: float = float(PlayerAnimation.GAITS[hero].get("hitch", 0.0))
		if amount < 0.0 or amount >= 1.0:
			_fail("GAITS['%s']['hitch'] is %.3f — it must stay in [0, 1) or the "
					% [hero, amount] + "amplitude factor reaches zero and flips the limbs")

	Sentinel.done("catalogue")


# ============================================================================
# CHECK 2 — THE POSE IS BOUNDED, ALWAYS
# ============================================================================

func _check_bounds(player: Node3D) -> void:
	"""
	Sweep every hero's walk over 60 s at 240 Hz, walking AND running, and assert
	the pose never leaves the bead's envelope and never goes non-finite.
	"""
	var limit: float = deg_to_rad(LIMB_LIMIT_DEG)
	var head_limit: float = deg_to_rad(HEAD_LIMIT_DEG)
	var step: float = 1.0 / SWEEP_HZ
	var samples: int = int(SWEEP_SECONDS * SWEEP_HZ)

	for index: int in PlayerController.CHARACTERS.size():
		var hero: String = String(PlayerController.CHARACTERS[index]["name"])
		player.set_active_character(index)

		# The widest excursion each of the row's own axes actually reached, for
		# the "a declared field reaches the pose" assertion below.
		var reach: Dictionary = {"left_arm": 0.0, "right_arm": 0.0,
				"sway": 0.0, "lean": 0.0, "head": 0.0}

		for multiplier: float in [1.0, 1.5]:
			var worst_limb: float = 0.0
			var worst_y_lo: float = 0.0
			var worst_y_hi: float = 0.0
			var worst_head: float = 0.0
			var bad_finite: bool = false
			for i: int in samples:
				player.anim.animation_time = float(i) * step
				player.anim.animate_walking(step, multiplier)
				# THE ONE ACCESSOR (bd godot-test1-5u3.2). `rig.measure()` answers
				# every animated angle OFF REST in radians, `body_y` in metres,
				# and omits `head_z` on a model with no head — for EITHER rig
				# kind, which is what lets check 8 below re-use these same bounds
				# on a skinned hero that has no limb nodes at all. Off rest
				# rather than absolute costs this check nothing: every shipped
				# hero's four limbs rest at rotation.x = 0.
				var m: Dictionary = player.anim.rig.measure()
				for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
					var swing: float = float(m[key + "_x"])
					if not is_finite(swing):
						bad_finite = true
						continue
					worst_limb = maxf(worst_limb, absf(swing))
					if key == "left_arm" or key == "right_arm":
						reach[key] = maxf(float(reach[key]), absf(swing))
				if not is_finite(float(m["body_y"])) or not is_finite(float(m["body_z"])) \
						or not is_finite(float(m["body_x"])):
					bad_finite = true
				else:
					worst_y_lo = minf(worst_y_lo, float(m["body_y"]))
					worst_y_hi = maxf(worst_y_hi, float(m["body_y"]))
					reach["sway"] = maxf(float(reach["sway"]), absf(float(m["body_z"])))
					reach["lean"] = maxf(float(reach["lean"]), absf(float(m["body_x"])))
				if m.has("head_z"):
					if not is_finite(float(m["head_z"])):
						bad_finite = true
					else:
						worst_head = maxf(worst_head, absf(float(m["head_z"])))
						reach["head"] = maxf(float(reach["head"]), worst_head)

			var tag: String = "%s @ x%.1f" % [hero, multiplier]
			if bad_finite:
				_fail("%s: a non-finite value appeared in the pose" % tag)
			if worst_limb > limit:
				_fail("%s: a limb reached %.1f deg on X — the bound is %.1f"
						% [tag, rad_to_deg(worst_limb), LIMB_LIMIT_DEG])
			if worst_y_lo < BODY_Y_MIN or worst_y_hi > BODY_Y_MAX:
				_fail("%s: Body.position.y ranged [%.4f, %.4f] — the band is [%.2f, %.2f]"
						% [tag, worst_y_lo, worst_y_hi, BODY_Y_MIN, BODY_Y_MAX])
			if worst_head > head_limit:
				_fail("%s: the head bobbled %.1f deg off rest — the ceiling is %.1f"
						% [tag, rad_to_deg(worst_head), HEAD_LIMIT_DEG])

		# A FIELD THIS HERO DECLARES MUST REACH THE POSE. Check 1 proves a row's
		# keys are ones the table knows; only this proves the VALUE is wired to
		# something — an axis the walk stopped writing, or a node left out of
		# the rest-pose table so the write is skipped, is otherwise silent.
		var row: Dictionary = PlayerAnimation.gait_for(hero)
		var wants: Dictionary = {
			"sway": float(row["sway_deg"]), "lean": float(row["lean_deg"]),
			"head": float(row["head_deg"]),
		}
		for axis: String in wants:
			var want: float = float(wants[axis])
			if want <= 0.0:
				continue
			if axis == "head" and not player.anim.rig.measure().has("head_z"):
				continue  # optional node (or bone), per the row's own docs
			if float(reach[axis]) < deg_to_rad(want) * 0.5:
				_fail("%s: the row asks for %.1f deg of '%s' but the pose never moved "
						% [hero, want, axis] + "that axis more than %.2f deg off rest"
						% rad_to_deg(float(reach[axis])))
		# The arms are asymmetric by ratio, so the two amplitudes must differ by it.
		var asym: float = float(row["arm_asym"])
		if not is_equal_approx(asym, 1.0) and float(reach["right_arm"]) > 0.0:
			var measured: float = float(reach["left_arm"]) / float(reach["right_arm"])
			if absf(measured - asym) > 0.02:
				_fail("%s: arm_asym is %.3f but the left arm swung %.3f x the right"
						% [hero, asym, measured])
		Sentinel.done("expression")

		# A huge `animation_time` loses precision inside sin() but must stay
		# FINITE — a run left going overnight must not put a NaN into a
		# transform, which surfaces as a physics error rather than a wobble.
		for far: float in [1.0e5, 1.0e6]:
			player.anim.animation_time = far
			player.anim.animate_walking(step, 1.0)
			var far_pose: Dictionary = player.anim.rig.measure()
			if not is_finite(float(far_pose["left_leg_x"])) \
					or not is_finite(float(far_pose["body_y"])):
				_fail("%s: the pose went non-finite at animation_time = %.0f s" % [hero, far])

	Sentinel.done("bounds")


# ============================================================================
# CHECK 3 — STOPPING PUTS THE GAIT'S OWN AXES BACK
# ============================================================================

func _check_relax(player: Node3D) -> void:
	"""
	Walk, then stop, and the waddle has to GO.

	The bead's landmine has two halves: a character SWAP must not carry a lean
	into the next hero (`restore_rest_pose`, covered by check 1's rest table),
	and STOPPING must not leave you standing there rolled 11 degrees with your
	head cocked. The second half is enforced by nothing but the three
	`relax_gait_extras()` calls in `animate_idle` / `animate_sidestep` /
	`animate_jumping` — and dropping one is a silent, permanently-visible bug
	that no other check in this repo can see.

	Driven on the two heroes that actually roll: teibi (sway 5, lean 3) and
	phoboman (sway 11, head 7). A hero whose row asks for none of it would pass
	this vacuously, which is why it is the loud rows that are measured.
	"""
	var step: float = 1.0 / SWEEP_HZ
	for index: int in PlayerController.CHARACTERS.size():
		var hero: String = String(PlayerController.CHARACTERS[index]["name"])
		var row: Dictionary = PlayerAnimation.gait_for(hero)
		if float(row["sway_deg"]) <= 0.0 and float(row["lean_deg"]) <= 0.0 \
				and float(row["head_deg"]) <= 0.0:
			continue  # nothing to put back — see the docstring
		player.set_active_character(index)

		# Walk far enough into the cycle for every one of those axes to be off
		# rest, then confirm it: a probe that measured a pose already at rest
		# would pass no matter what the relax did.
		player.anim.animation_time = 0.4
		player.anim.animate_walking(step, 1.0)
		if _off_rest(player) <= REST_EPS:
			_fail("%s: the walk pose is already at rest, so this check would be "
					% hero + "vacuous — pick a different sample time")

		# IDLE eases back. 120 frames is 2 s at 60 Hz; the lerp is 0.15 a frame,
		# so anything that is still moving has arrived long before that.
		for i: int in RELAX_FRAMES:
			player.anim.animation_time = 0.4 + float(i) * step
			player.anim.animate_idle(step)
		var idle_off: float = _off_rest(player)
		if idle_off > REST_EPS:
			_fail("%s: standing still for %d frames left the body/head %.4f rad off "
					% [hero, RELAX_FRAMES, idle_off]
					+ "rest — the walk gait's roll, lean or head bobble is stuck on")

		# SIDESTEP snaps. It writes the body's roll itself, so only the pitch and
		# the head are this call's business — and they must be exactly at rest.
		player.anim.animation_time = 0.4
		player.anim.animate_walking(step, 1.0)
		player.step_direction = 1.0
		player.anim.animate_sidestep(step)
		var after: Dictionary = player.anim.rig.measure()
		if absf(float(after["body_x"])) > 1e-6:
			_fail("%s: a sidestep straight out of a walk left the body pitched %.4f rad "
					% [hero, absf(float(after["body_x"]))]
					+ "off rest — the gait's lean is stuck on")
		if after.has("head_z") and absf(float(after["head_z"])) > 1e-6:
			_fail("%s: a sidestep straight out of a walk left the head %.4f rad off "
					% [hero, absf(float(after["head_z"]))]
					+ "rest — the gait's bobble is stuck on")
		player.step_direction = 0.0

	Sentinel.done("relax")


func _off_rest(player: Node3D) -> float:
	"""How far the three gait-only axes are from rest, in radians (the worst one).
	`measure()` already answers off rest, so this is just the worst of three."""
	var m: Dictionary = player.anim.rig.measure()
	var worst: float = maxf(absf(float(m["body_x"])), absf(float(m["body_z"])))
	if m.has("head_z"):
		worst = maxf(worst, absf(float(m["head_z"])))
	return worst


# ============================================================================
# CHECK 4 — THE FOUR WALKS DIFFER, AND NONE OF THEM IS A METRONOME
# ============================================================================

func _check_personality(player: Node3D) -> void:
	"""
	(a) No two heroes share a stride period, and (b) no hero's pose repeats at
	their own stride period — which is exactly what "the hitch exists" means.

	(b) is the load-bearing half: a single-sine walk is periodic at its stride
	by construction, so comparing the pose at t and t + T is the one measurement
	that can tell the two-sine gait from the old one.
	"""
	var periods: Dictionary = {}
	for entry: Dictionary in PlayerController.CHARACTERS:
		var hero: String = String(entry["name"])
		var rate: float = float(PlayerAnimation.gait_for(hero)["stride_rate"])
		if rate <= 0.0:
			_fail("'%s' has stride_rate %.3f — a walk cycle needs a positive rate" % [hero, rate])
			continue
		for other: String in periods:
			if is_equal_approx(float(periods[other]), rate):
				_fail("'%s' and '%s' share stride_rate %.3f — their walks are the "
						% [hero, other, rate] + "same cycle, which is what this bead removed")
		periods[hero] = rate

	var eps: float = deg_to_rad(HITCH_EPS_DEG)
	var step: float = 1.0 / SWEEP_HZ
	for index: int in PlayerController.CHARACTERS.size():
		var hero: String = String(PlayerController.CHARACTERS[index]["name"])
		player.set_active_character(index)
		var rate: float = float(PlayerAnimation.gait_for(hero)["stride_rate"])
		if rate <= 0.0:
			continue
		var period: float = TAU / rate
		var worst: float = 0.0
		var samples: int = int(HITCH_SECONDS / step)
		for i: int in samples:
			var t: float = float(i) * step
			player.anim.animation_time = t
			player.anim.animate_walking(step, 1.0)
			var a: Array[float] = _pose(player)
			player.anim.animation_time = t + period
			player.anim.animate_walking(step, 1.0)
			var b: Array[float] = _pose(player)
			for k: int in a.size():
				worst = maxf(worst, absf(a[k] - b[k]))
		if worst <= eps:
			_fail("'%s': the pose one stride period (%.3f s) later differs by at most "
					% [hero, period] + "%.3f deg — the walk repeats exactly, so the hitch "
					% rad_to_deg(worst) + "sine is not doing anything")

	Sentinel.done("personality")


func _pose(player: Node3D) -> Array[float]:
	"""Every animated angle of the current pose, for comparing two moments."""
	return _pose_of(player.anim)


func _pose_of(anim) -> Array[float]:
	"""The same array off ANY bound rig — the local player's or check 8's
	fixture — which is the whole point of routing the read through `measure()`.

	The bob is metres and everything else radians; it rides the same array
	because the assertion is "these two moments are not the same pose", and a
	0.03 m bob is well above the epsilon either way.
	"""
	var m: Dictionary = anim.rig.measure()
	var out: Array[float] = []
	for key: String in ["left_arm_x", "right_arm_x", "left_leg_x", "right_leg_x",
			"body_y", "body_z", "body_x"]:
		out.append(float(m[key]))
	if m.has("head_z"):
		out.append(float(m["head_z"]))
	return out


# ============================================================================
# CHECK 5 — THE FOOTSTEP BEAT IS THE STRIDE, AND ONLY THE STRIDE
# ============================================================================

func _check_footsteps(player: Node3D) -> void:
	"""
	Count the walk sine's sign flips — the trigger every footstep and every
	wading splash in the game hangs off — and compare with the count the row's
	`stride_rate` predicts on its own.

	That comparison is the contract: the hitch scales AMPLITUDE and must never
	touch the phase, so however hard a hero stumbles the number of footfalls per
	second is still 2 * stride_rate / TAU and nothing else. The DEFAULT row is
	driven as a fifth subject, and its count is today's count exactly.
	"""
	var step: float = 1.0 / SWEEP_HZ
	var samples: int = int(STEP_SECONDS / step)

	var subjects: Array = []
	for index: int in PlayerController.CHARACTERS.size():
		subjects.append([String(PlayerController.CHARACTERS[index]["name"]), index])
	# The DEFAULT row, forced onto a live body: this is the only way to measure
	# that an unknown hero still fires footsteps at the pre-table rate.
	subjects.append(["DEFAULT (unknown hero)", -1])

	for subject: Array in subjects:
		var label: String = String(subject[0])
		var index: int = int(subject[1])
		var rate: float = 0.0
		if index >= 0:
			player.set_active_character(index)
			# The rate is read from the TABLE, never off the body — that is what
			# binds the hero to their row. A build that resolved `_gait` once and
			# never again on a swap answers every hero with the first hero's
			# walk, and a self-consistent measurement would never see it.
			rate = float(PlayerAnimation.gait_for(label)["stride_rate"])
		else:
			player.set_active_character(0)
			player.anim._gait = PlayerAnimation.gait_for("no-such-hero")
			rate = float(player.anim._gait["stride_rate"])

		# Sign 0 is the "just started walking" sentinel: the first sample records
		# its sign silently, exactly as the first frame of a real walk does.
		player.anim._last_walk_sine_sign = 0
		var flips: int = 0
		var previous: int = 0
		for i: int in samples:
			player.anim.animation_time = float(i) * step
			player.anim.animate_walking(step, 1.0)
			var sign_now: int = int(player.anim._last_walk_sine_sign)
			if previous != 0 and sign_now != previous:
				flips += 1
			previous = sign_now

		# sin(rate * t) changes sign at t = k * PI / rate, k = 1, 2, ...
		var expected: int = int(floor(STEP_SECONDS * rate / PI))
		if flips != expected:
			_fail("%s: %d footstep triggers in %.0f s, but stride_rate %.3f predicts %d — "
					% [label, flips, STEP_SECONDS, rate, expected]
					+ "the hitch has moved the PHASE, which retimes every footstep "
					+ "and every wading splash in the game")

	# A SWAP MUST NOT FIRE A PHANTOM FOOTSTEP. The trigger is a SIGN CHANGE of
	# `sin(animation_time * stride_rate)` against the last frame's sign, and a
	# swap changes `stride_rate` under a shared `animation_time` — so there is
	# always a moment where the outgoing hero's foot was down and the incoming
	# hero's is up, with no leg having crossed anything. `set_active_character()`
	# clears the sentinel to 0 for exactly that reason; this measures it.
	var flip_found: bool = false
	for a: int in PlayerController.CHARACTERS.size():
		for b: int in PlayerController.CHARACTERS.size():
			if a == b:
				continue
			var rate_a: float = float(PlayerAnimation.gait_for(
					String(PlayerController.CHARACTERS[a]["name"]))["stride_rate"])
			var rate_b: float = float(PlayerAnimation.gait_for(
					String(PlayerController.CHARACTERS[b]["name"]))["stride_rate"])
			# A moment where the two rows genuinely disagree about which foot is
			# down. Without one this assertion would be vacuous, which is why the
			# search is a search and not a hard-coded pair.
			var t: float = -1.0
			for i: int in 400:
				var probe: float = 0.01 + float(i) * 0.01
				if (sin(probe * rate_a) >= 0.0) != (sin(probe * rate_b) >= 0.0):
					t = probe
					break
			if t < 0.0:
				continue
			flip_found = true

			player.set_active_character(a)
			player.anim._last_walk_sine_sign = 0
			player.anim.animation_time = t
			player.anim.animate_walking(step, 1.0)
			var outgoing: int = int(player.anim._last_walk_sine_sign)

			player.set_active_character(b)
			if int(player.anim._last_walk_sine_sign) != 0:
				_fail("swapping %s -> %s left the previous hero's stride sign (%d) on the "
						% [String(PlayerController.CHARACTERS[a]["name"]),
								String(PlayerController.CHARACTERS[b]["name"]), outgoing]
						+ "footstep sentinel — the next frame reads it as a foot planting "
						+ "and fires a phantom footstep or splash")
				continue

			# ...and the hazard was real: the incoming hero's first frame really
			# does record the OPPOSITE sign, which without the clear above is
			# precisely the spurious flip.
			player.anim.animate_walking(step, 1.0)
			if int(player.anim._last_walk_sine_sign) == outgoing:
				_fail("the %s -> %s swap probe picked t = %.2f where the two strides agree "
						% [String(PlayerController.CHARACTERS[a]["name"]),
								String(PlayerController.CHARACTERS[b]["name"]), t]
						+ "— this assertion would pass without the sentinel being cleared")
	if not flip_found:
		_fail("no pair of heroes disagrees about which foot is down at any sampled time — "
				+ "the phantom-footstep assertion above never ran")

	# And the rate the DEFAULT row fires at is the one the old literal fired at.
	var default_rate: float = float(PlayerAnimation.gait_for("no-such-hero")["stride_rate"])
	if not is_equal_approx(default_rate, float(TODAY["stride_rate"])):
		_fail("the DEFAULT stride_rate is %.3f, not the pre-table %.3f — every "
				% [default_rate, TODAY["stride_rate"]]
				+ "footstep of an unknown hero would be retimed")

	Sentinel.done("footsteps")


# ============================================================================
# CHECK 6 — THE SIDESTEP IS A CYCLE, AND ITS PHASE IS METRES
# ============================================================================

func _check_sidestep(player: Node3D) -> void:
	"""
	Holding A / D has to look like STEPPING, not like leaning (bead
	godot-test1-3ek; owner: *"left-right movement should have better animation
	like steps left and right"*).

	Six things:

	  (a) the pose MOVES over a held strafe, and the two legs take TURNS being
	      the one that has reached out — measured as the roll GAP between them
	      taking both signs. The control is the SHIPPED `sidestep_pose()` driven
	      at a FROZEN phase, swept identically, which must FAIL that bound: a
	      lean held for as long as the key is down has one gap, one sign,
	      forever. Driving the shipped function rather than a local copy of the
	      retired pose is the point — a re-implementation could only ever fail
	      the bound by construction, which measures nothing.
	  (b) BOTH DIRECTIONS MIRROR. A left strafe and a right one must reach the
	      same distance, and this is not decoration: the lift used to be steered
	      by `sign(cycle)` alone, which on a LEFT strafe put it on the trailing
	      leg and cancelled half the reach. A one-direction probe was green
	      throughout.
	  (c) the phase is DISTANCE, so the same ground covered at half the speed
	      over twice the frames is the SAME pose. Nothing else in this file can
	      see a regression to `animation_time`, and a time-driven strafe is
	      exactly what the bead replaced.
	  (d) `reset_sidestep_pose()` still puts every limb roll back, because that
	      is the key-order bug `capture_selfcheck` guards from the other side —
	      and it must now also drop the PHASE, or the next strafe starts
	      mid-stride.
	  (e) the FOOTSTEP BEAT, counted the way check 5 counts the walk's: sign
	      flips of the sidestep's own sentinel over a known distance. The `_sfx`
	      call itself is gated on `is_on_floor()`, which no headless harness
	      satisfies, so the sentinel is the measurable half — and it is the half
	      that carries the bug, since the beat IS the phase and the phase is
	      where a retune goes wrong.
	  (f) the per-hero personality is REAL, on all three axes the banner claims:
	      the LEG amplitude (off `leg_deg`), the ARM amplitude (off `arm_deg`)
	      and the step RATE (off `stride_rate`). Each is asserted as a SPREAD
	      across the roster, because "the four numbers are distinct" passes on
	      sampling noise alone — measured, `leg_scale` pinned to 1.0 still gave
	      four amplitudes differing in the fourth decimal.
	"""
	var step: float = 1.0 / SWEEP_HZ
	var eps: float = deg_to_rad(STRAFE_EPS_DEG)
	var frames: int = int(STRAFE_METRES / (STRAFE_SPEED * step))
	var leg_amps: Array[float] = []
	var arm_amps: Array[float] = []
	var beats: Array[float] = []

	for index: int in PlayerController.CHARACTERS.size():
		var hero: String = String(PlayerController.CHARACTERS[index]["name"])
		player.set_active_character(index)
		var anim = player.anim
		var per_direction: Array[float] = []

		for direction: float in [1.0, -1.0]:
			var swept: Dictionary = _strafe_sweep(anim, direction, STRAFE_SPEED, step, frames)
			var gap_min: float = float(swept["leg_min"])
			var gap_max: float = float(swept["leg_max"])
			if gap_min >= -eps or gap_max <= eps:
				_fail("%s (direction %+.0f): over %.1f m of held strafe the roll gap "
						% [hero, direction, STRAFE_METRES]
						+ "between the legs stayed in [%.4f, %.4f] rad — one leg never "
						% [gap_min, gap_max]
						+ "took its turn reaching out, so the strafe is still a static "
						+ "splay and not a stepping cycle")
			per_direction.append(gap_max - gap_min)

			var lift_seen: float = float(swept["bob"])
			if lift_seen <= 0.0:
				_fail("%s (direction %+.0f): the body never left its rest height over a "
						% [hero, direction]
						+ "whole strafe — the bob on the close beat is not being drawn")
			# The bob rides inside the same band the walk is held to, or the model
			# stops looking attached to a collision capsule that does not move.
			if lift_seen > BODY_Y_MAX:
				_fail("%s (direction %+.0f): the strafe bob reached %.4f m, past the "
						% [hero, direction, lift_seen]
						+ "%.4f m the walk cycle is held to" % BODY_Y_MAX)

			# (a)'s CONTROL, on the shipped function: the same sweep with the phase
			# never advancing. A static pose draws ONE gap, so it cannot take both
			# signs — and if it ever does, the bound above has stopped measuring.
			var s_min: float = INF
			var s_max: float = -INF
			for i: int in frames:
				anim.sidestep_pose(0.0, direction)
				var frozen: Dictionary = anim.rig.measure()
				var s_gap: float = float(frozen["left_leg_z"]) - float(frozen["right_leg_z"])
				s_min = minf(s_min, s_gap)
				s_max = maxf(s_max, s_gap)
			if s_min < -eps and s_max > eps:
				_fail("%s (direction %+.0f): a FROZEN phase passed the alternation bound "
						% [hero, direction]
						+ "— the check would not go red on a strafe that stopped moving")

		# (b) THE TWO DIRECTIONS MIRROR.
		if not is_equal_approx(per_direction[0], per_direction[1]):
			_fail("%s: a right strafe reaches %.4f rad and a left one %.4f — the two "
					% [hero, per_direction[0], per_direction[1]]
					+ "directions must mirror, so the reaching leg is being picked off "
					+ "the cycle's sign without the step's")

		# (c) THE PHASE IS METRES. Same ground, half the speed, twice the frames.
		var fast: Array[float] = _strafe_pose(anim, 1.0, STRAFE_SPEED, step, frames)
		var slow: Array[float] = _strafe_pose(anim, 1.0, STRAFE_SPEED * 0.5, step, frames * 2)
		for k: int in fast.size():
			if absf(fast[k] - slow[k]) > 1e-5:
				_fail("%s: the same %.1f m walked at half the speed gave a different pose "
						% [hero, STRAFE_METRES]
						+ "(%.5f vs %.5f) — the sidestep phase is running on TIME, not "
						% [fast[k], slow[k]] + "on distance")
				break

		# (d) RELEASE PUTS IT BACK, phase included.
		player.step_direction = 1.0
		player.velocity = Vector3(0.0, 0.0, STRAFE_SPEED)
		anim.animate_sidestep(step)
		anim.reset_sidestep_pose()
		var released: Dictionary = anim.rig.measure()
		for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
			var off: float = absf(float(released[key + "_z"]))
			if off > 1e-6:
				_fail("%s: releasing the strafe left %s rolled %.5f rad off rest"
						% [hero, key, off])
		if absf(float(anim._sidestep_phase)) > 0.0 or int(anim._last_sidestep_sine_sign) != 0:
			_fail("%s: releasing the strafe kept the cycle's phase (%.4f) or its footstep "
					% [hero, float(anim._sidestep_phase)]
					+ "sentinel (%d) — the next strafe would start mid-stride"
					% int(anim._last_sidestep_sine_sign))
		player.step_direction = 0.0
		player.velocity = Vector3.ZERO

		var measured: Dictionary = _strafe_sweep(anim, 1.0, STRAFE_SPEED, step, frames)
		leg_amps.append(float(measured["leg_max"]) - float(measured["leg_min"]))
		arm_amps.append(float(measured["arm_max"]) - float(measured["arm_min"]))
		beats.append(float(measured["flips"]))
		# (e) THE BEAT IS THE PHASE. One sign flip every PI of phase, and the
		#     phase is metres x the rate — so the count is arithmetic, not a
		#     tuning constant, and a bug that moved the phase instead of the
		#     amplitude would show up here as the wrong number of steps.
		var rate: float = PlayerAnimation.SIDESTEP_PHASE_PER_METRE \
				* float(PlayerAnimation.gait_for(hero)["stride_rate"]) \
				/ float(PlayerAnimation.GAITS["DEFAULT"]["stride_rate"])
		var expected: float = STRAFE_METRES * rate / PI
		if absf(float(measured["flips"]) - expected) > 1.0:
			_fail("%s: %d footstep beats over %.1f m, but the row's rate predicts %.1f "
					% [hero, int(measured["flips"]), STRAFE_METRES, expected]
					+ "— the close beat is not riding the cycle's own phase")

	# (f) THE PERSONALITY IS REAL, on each of the three axes separately.
	for axis: Array in [["leg amplitude", leg_amps, "leg_deg"],
			["arm amplitude", arm_amps, "arm_deg"],
			["step rate", beats, "stride_rate"]]:
		var values: Array = axis[1]
		var lo: float = INF
		var hi: float = -INF
		for v: float in values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		if lo <= 0.0 or hi < lo * PERSONALITY_SPREAD:
			_fail("every hero's strafe %s sits in [%.4f, %.4f] — the rows spread `%s` "
					% [axis[0], lo, hi, axis[2]]
					+ "far wider than that, so that scaling is not reaching the pose")

	Sentinel.done("sidestep")


func _strafe_sweep(anim, direction: float, speed: float, step: float,
		frames: int) -> Dictionary:
	"""
	Drive one held strafe from a clean start and report what it did: the range
	of the LEG roll gap and of the ARM roll gap, the worst body rise, and how
	many times the footstep sentinel flipped (the close beats).
	"""
	anim.player.step_direction = direction
	anim.reset_sidestep_pose()
	var out: Dictionary = {"leg_min": INF, "leg_max": -INF,
			"arm_min": INF, "arm_max": -INF, "bob": 0.0, "flips": 0.0}
	var last_sign: int = 0
	for i: int in frames:
		anim.player.velocity = Vector3(0.0, 0.0, speed)
		anim.animate_sidestep(step)
		var m: Dictionary = anim.rig.measure()
		var leg: float = float(m["left_leg_z"]) - float(m["right_leg_z"])
		out["leg_min"] = minf(float(out["leg_min"]), leg)
		out["leg_max"] = maxf(float(out["leg_max"]), leg)
		var arm: float = float(m["left_arm_z"]) - float(m["right_arm_z"])
		out["arm_min"] = minf(float(out["arm_min"]), arm)
		out["arm_max"] = maxf(float(out["arm_max"]), arm)
		out["bob"] = maxf(float(out["bob"]), absf(float(m["body_y"])))
		var now: int = int(anim._last_sidestep_sine_sign)
		if last_sign != 0 and now != last_sign:
			out["flips"] = float(out["flips"]) + 1.0
		last_sign = now
	anim.player.step_direction = 0.0
	anim.player.velocity = Vector3.ZERO
	return out


func _strafe_pose(anim, direction: float, speed: float, step: float,
		frames: int) -> Array[float]:
	"""Walk one strafe from a clean start and return the pose it ends on."""
	anim.player.step_direction = direction
	anim.reset_sidestep_pose()
	for i: int in frames:
		anim.player.velocity = Vector3(0.0, 0.0, speed)
		anim.animate_sidestep(step)
	anim.player.step_direction = 0.0
	anim.player.velocity = Vector3.ZERO
	var m: Dictionary = anim.rig.measure()
	return [float(m["left_leg_z"]), float(m["right_leg_z"]),
			float(m["left_arm_z"]), float(m["right_arm_z"]),
			float(m["body_y"])]


# ============================================================================
# CHECK 8 — THE SKINNED RIG DRAWS THE SAME WALK (bd godot-test1-5u3.2)
# ============================================================================

func _check_skinned(player: Node3D) -> void:
	"""
	The seam's own subject: a hero with NO limb nodes at all, posed on BONES.

	The fixture is `teibi.tscn` — since bead `5u3.3` the SHIPPED Teibi, and the
	only skinned hero in `CHARACTERS`. It is driven through a SECOND
	`PlayerAnimation` pointed at a fresh instance of that scene for the length of
	this function, rather than through the player's own Teibi, so this check
	writes nothing the four-hero sweep above can see and needs no ordering
	against it: `CHARACTERS` is a const and must stay one.

	Six assertions, every one of them through `rig.measure()` and therefore
	against the very same bounds checks 2 and 4 hold the limb heroes to:

	  (a) the scene really took the skinned driver — the capability flag works,
	      and it is the SCENE that flipped it;
	  (b) the pose stays inside the bead's envelope over the same sweep, walking
	      and running, and never goes non-finite;
	  (c) THE DIAGONAL HOLDS: the left leg goes back while the left arm swings
	      forward, and the two legs are opposed. This is the one thing a flipped
	      bone write breaks while every bound above still passes — a sign error
	      is the failure mode a conjugated rotation invites, so it is measured
	      rather than eyeballed (the PR's first mutation control);
	  (d) the pose does not repeat at the stride period — the hitch reaches the
	      bones, exactly as check 4 asserts it reaches the nodes;
	  (e) THE SAME PHASE GIVES THE SAME POSE, with a `rest_pose()` in between.
	      That is the multiplayer contract as a measurement: a remote mirror
	      re-derives the pose from its own phase and nothing else, so a driver
	      carrying hidden state between frames would diverge on every peer;
	  (f) every axis the driver claims actually MOVES, the head bone included.
	      Teibi's row has `head_deg` 0, so the fixture runs his row with the
	      bobble forced on — an unmeasured write is a write that can be deleted
	      in silence (the PR's second mutation control).

	...and then three things the walk sweep STRUCTURALLY CANNOT see:

	  (g) THE TWO DRIVERS ARE THE SAME POSE — an identical script of driver calls
	      run against the limb rig and the bone rig, compared key by key. The
	      walk sweep above pins all four `*_z` keys to zero (`animate_walking()`
	      opens with `reset_sidestep_pose()`), so without this `sidestep()`,
	      `air()`, `drop_wings()` and `reset_roll()` would have no coverage
	      anywhere in the suite — no shipped hero binds this driver. And equality
	      against the rig this game already ships is a far sharper instrument
	      than a bound: it fails on one flipped sign in any of the ten writes.
	  (h) THE JOINTS — the knee that bends on the back-swing and the elbow that
	      tracks the shoulder. They are the whole reason a skeleton beats five
	      nodes, and `measure()` deliberately does not expose them: its keys are
	      the limb rig's, or the shared bounds would stop meaning the same thing.
	      So they are measured in the skeleton's own space, as the distance from
	      hip to foot and from shoulder to hand — which is what a bent joint is.
	  (i) THE ROLL TRAP ITSELF, and this one is the subtle one. `_set_axis()`
	      writes `P⁻¹·E·P·R` and `_axis()` reads back `P·(pose·R⁻¹)·P⁻¹ = E`: the
	      conjugation basis CANCELS. So `measure()` — and therefore everything
	      above — answers exactly what was written for ANY invertible `P`,
	      including a wrong one. Cache the BONE's own global rest basis instead
	      of its PARENT's in `bind()` and every assertion above still passes
	      while the legs swing sideways about MakeHuman's rolls, which is the
	      one failure the driver's banner spends fifteen lines warning about.
	      The quantity `P` does not cancel out of is where the bone physically
	      ENDS UP, so that is what (i) measures: swing the thigh forward and
	      back, and the knee must travel along the skeleton's ±Z (the way the
	      hero faces), not sideways.

	(g) SURVIVED BEAD godot-test1-5u3.9 UNCHANGED, and that is a design rule
	      rather than luck: every bone that bead added — the calf, the foot, the
	      forearm, the clavicle, the pelvis and the two spine bones — is a bone
	      `measure()` does not expose, so a skinned hero still walks the exact
	      stride the gait row asked for and the two drivers are still the same
	      eleven numbers. What `5u3.9` added instead lives in
	      `_measure_skinned_joints()` beside (h) — the phased knee, the level
	      sole, the lagging elbow, the countered pelvis, the absorbed landing,
	      the breath and a band around all of them, every one measured in the
	      SKELETON's own space — and in `_check_skinned_determinism()`, which
	      asks TWO INSTANCES the same clock and compares every bone of both,
	      because (e) above compares one driver with itself and cannot see a
	      divergence that is per-model.
	"""
	var packed: PackedScene = load(SKINNED_FIXTURE)
	if packed == null:
		_fail("could not load %s — the skinned driver has no fixture to prove "
				% SKINNED_FIXTURE + "itself on, so nothing below ran")
		Sentinel.done("skinned")
		Sentinel.done("skinned_joints")
		Sentinel.done("skinned_determinism")
		return
	var fixture: Node3D = packed.instantiate()
	root.add_child(fixture)

	var anim: PlayerAnimation = PlayerAnimation.new()
	anim.player = player
	# `setup_animation_references()` reads the player's CURRENT character node;
	# borrow it for one call and hand it straight back, so the four heroes above
	# are left exactly as check 6 left them.
	var saved: Node = player.current_character_node
	player.current_character_node = fixture
	# THROUGH THE SEAM, not a hand-rolled copy of it: `capture_rest_pose()` is the
	# one rest-capture, and a skinned model is exactly the case its docstring
	# describes (no limb nodes, so it answers `body` alone).
	anim.original_rotations = PlayerAnimation.capture_rest_pose(fixture)
	anim.setup_animation_references()
	player.current_character_node = saved

	# (a) THE CAPABILITY FLAG.
	if anim.rig == null or String(anim.rig.kind()) != "skinned":
		_fail("%s bound the '%s' rig — a scene carrying a Skeleton3D must take "
				% [SKINNED_FIXTURE, "none" if anim.rig == null else anim.rig.kind()]
				+ "the skinned driver, and nothing else in this check could run")
		fixture.queue_free()
		Sentinel.done("skinned")
		Sentinel.done("skinned_joints")
		Sentinel.done("skinned_determinism")
		return

	anim._gait = PlayerAnimation.gait_for("teibi")
	anim._gait["head_deg"] = FIXTURE_HEAD_DEG

	var limit: float = deg_to_rad(LIMB_LIMIT_DEG)
	var head_limit: float = deg_to_rad(HEAD_LIMIT_DEG)
	var move_eps: float = deg_to_rad(SKINNED_MOVE_DEG)
	var step: float = 1.0 / SWEEP_HZ
	var samples: int = int(SKINNED_SWEEP_SECONDS * SWEEP_HZ)
	var claims: Array[String] = ["left_arm_x", "right_arm_x", "left_leg_x",
			"right_leg_x", "head_z"]
	var reach: Dictionary = {}
	for key: String in claims:
		reach[key] = 0.0

	var bad_finite: bool = false
	var worst_limb: float = 0.0
	var worst_head: float = 0.0
	var y_lo: float = 0.0
	var y_hi: float = 0.0
	var opposed_samples: int = 0
	var broken_samples: int = 0

	for multiplier: float in [1.0, 1.5]:
		for i: int in samples:
			anim.animation_time = float(i) * step
			anim.animate_walking(step, multiplier)
			var m: Dictionary = anim.rig.measure()
			for key: String in claims:
				if not m.has(key):
					continue
				var v: float = float(m[key])
				if not is_finite(v):
					bad_finite = true
					continue
				reach[key] = maxf(float(reach[key]), absf(v))
			for key: String in ["left_arm_x", "right_arm_x", "left_leg_x", "right_leg_x"]:
				worst_limb = maxf(worst_limb, absf(float(m[key])))
			if m.has("head_z"):
				worst_head = maxf(worst_head, absf(float(m["head_z"])))
			if not is_finite(float(m["body_y"])):
				bad_finite = true
			else:
				y_lo = minf(y_lo, float(m["body_y"]))
				y_hi = maxf(y_hi, float(m["body_y"]))

			# (c) THE DIAGONAL, sampled only where the stride is wide enough for
			#     "which way" to mean anything — near the crossing both signs
			#     are noise.
			var ll: float = float(m["left_leg_x"])
			var rl: float = float(m["right_leg_x"])
			var la: float = float(m["left_arm_x"])
			if absf(ll) > move_eps and absf(rl) > move_eps and absf(la) > move_eps:
				opposed_samples += 1
				if signf(ll) == signf(rl) or signf(ll) == signf(la):
					broken_samples += 1

	if bad_finite:
		_fail("skinned fixture: a non-finite value appeared in the pose")
	if worst_limb > limit:
		_fail("skinned fixture: a limb bone reached %.1f deg off rest — the bound "
				% rad_to_deg(worst_limb) + "is %.1f" % LIMB_LIMIT_DEG)
	if y_lo < BODY_Y_MIN or y_hi > BODY_Y_MAX:
		_fail("skinned fixture: Body.position.y ranged [%.4f, %.4f] — the band is "
				% [y_lo, y_hi] + "[%.2f, %.2f]" % [BODY_Y_MIN, BODY_Y_MAX])
	if worst_head > head_limit:
		_fail("skinned fixture: the head bone bobbled %.1f deg off rest — the "
				% rad_to_deg(worst_head) + "ceiling is %.1f" % HEAD_LIMIT_DEG)
	if opposed_samples == 0:
		_fail("skinned fixture: the stride never opened far enough to test the "
				+ "diagonal — assertion (c) would have passed vacuously")
	elif broken_samples > 0:
		_fail("skinned fixture: %d of %d swung samples had the two legs (or the "
				% [broken_samples, opposed_samples]
				+ "left leg and left arm) moving the SAME way — the bone rig's "
				+ "diagonal opposition is inverted somewhere")

	# (d) NOT A METRONOME, measured exactly as check 4 measures it.
	var period: float = TAU / float(anim._gait["stride_rate"])
	var worst_gap: float = 0.0
	for i: int in int(HITCH_SECONDS / step):
		var t: float = float(i) * step
		anim.animation_time = t
		anim.animate_walking(step, 1.0)
		var a: Array[float] = _pose_of(anim)
		anim.animation_time = t + period
		anim.animate_walking(step, 1.0)
		var b: Array[float] = _pose_of(anim)
		for k: int in a.size():
			worst_gap = maxf(worst_gap, absf(a[k] - b[k]))
	if worst_gap <= deg_to_rad(HITCH_EPS_DEG):
		_fail("skinned fixture: the pose one stride period (%.3f s) later differs "
				% period + "by at most %.3f deg — the hitch is not reaching the bones"
				% rad_to_deg(worst_gap))

	# (e) DETERMINISM: the same clock, twice, from two different starting poses.
	anim.animation_time = SKINNED_PROBE_TIME
	anim.animate_walking(step, 1.0)
	var first: Dictionary = anim.rig.measure()
	anim.rig.rest_pose()
	anim.animation_time = SKINNED_PROBE_TIME
	anim.animate_walking(step, 1.0)
	var second: Dictionary = anim.rig.measure()
	for key: String in first:
		if absf(float(first[key]) - float(second[key])) > 1e-6:
			_fail("skinned fixture: '%s' came out %.6f then %.6f at the same clock "
					% [key, float(first[key]), float(second[key])]
					+ "— the driver is carrying state between frames, so two peers "
					+ "drawing the same phase would draw different poses")

	# (f) EVERY CLAIMED AXIS MOVES.
	for key: String in claims:
		if float(reach[key]) <= move_eps:
			_fail("skinned fixture: '%s' never moved more than %.3f deg off rest "
					% [key, rad_to_deg(float(reach[key]))]
					+ "over the whole sweep — the driver claims that axis and is "
					+ "not writing it")

	# (g) THE TWO DRIVERS ARE THE SAME POSE. Hand an identical script of driver
	#     calls to the limb rig and to the bone rig and compare `measure()` key by
	#     key. This is the seam's ACTUAL claim, and it is stronger than any bound:
	#     it catches a flipped sign, a swapped side or a dropped term in ANY of the
	#     ten pose writes — including every Z write, which the walk sweep above
	#     structurally cannot reach (`animate_walking()` opens with
	#     `reset_sidestep_pose()`, pinning all four `*_z` keys to zero). The Z
	#     writes need it most: the sidestep's two legs are `splay + reach` and
	#     `splay - reach`, not a mirrored pair, so (c)'s diagonal is no proxy.
	#
	#     The limb rig is the player's own — the arguments come from this script,
	#     not from a `GAITS` row, so neither side reads a gait at all. Only the
	#     rig-owned keys are compared: `body_*` is written by the CALLER on the
	#     `Body` node, and these two rigs hang off two different bodies.
	#
	#     THE ORACLE IS A HERO STILL ON LIMBS, and since bead godot-test1-5u3.3
	#     that is no longer Teibi — he is the fixture above. Windman takes his
	#     place until bead 5u3.5 migrates him, and the guard right below is what
	#     makes that hand-off safe rather than silent: it fails the moment this
	#     name picks up a Skeleton3D, so the check can never compare the bone
	#     driver against itself and call it agreement.
	player.set_active_character(_hero_index("windman"))
	var limb_poses: Array[Dictionary] = _drive_rig(player.anim.rig)
	var bone_poses: Array[Dictionary] = _drive_rig(anim.rig)
	# THE ORACLE HAS TO BE THE OTHER RIG, and there has to BE a comparison: an
	# empty script or a `player.anim` that somehow bound a skeleton too would
	# make every assertion below vacuous while printing OK.
	if String(player.anim.rig.kind()) != "limbs":
		_fail("the equivalence oracle bound the '%s' rig — it must be the LIMB rig, "
				% player.anim.rig.kind() + "or this compares the bone driver with itself")
	if limb_poses.is_empty() or limb_poses.size() != bone_poses.size():
		_fail("the driver script answered %d poses on the limb rig and %d on the bone "
				% [limb_poses.size(), bone_poses.size()] + "rig — nothing was compared")
	for step_index: int in limb_poses.size():
		var want: Dictionary = limb_poses[step_index]
		var got: Dictionary = bone_poses[step_index]
		for key: String in RIG_KEYS:
			if not want.has(key) or not got.has(key):
				_fail("skinned fixture: step %d of the driver script answered '%s' on "
						% [step_index, "the limb rig" if want.has(key) else "the bone rig"]
						+ "only — both rigs must claim the same keys")
				continue
			if absf(float(want[key]) - float(got[key])) > 1e-6:
				_fail("skinned fixture: at step %d of the driver script the limb rig "
						% step_index + "drew '%s' = %.6f and the bone rig %.6f — the two "
						% [key, float(want[key]), float(got[key])]
						+ "rigs must be the SAME pose written two ways, or a hero changes "
						+ "the way it walks the day it is migrated")

	_measure_skinned_joints(anim, fixture)
	_check_skinned_determinism(player)

	fixture.queue_free()
	Sentinel.done("skinned")


func _at(skel: Skeleton3D, idx: int) -> Vector3:
	"""Where a bone actually ENDS UP, in skeleton space. This is the one quantity
	the driver's conjugation does NOT cancel out of (see the `(i)` note below), so
	every probe in this section is expressed in it rather than in an angle the
	driver could have written any way it liked."""
	return skel.get_bone_global_pose(idx).origin


func _span(skel: Skeleton3D, a: int, b: int) -> float:
	return _at(skel, a).distance_to(_at(skel, b))


func _pose_cycle(anim, phase: float, amp: float, land: float) -> void:
	"""
	ONE DRIVER-LEVEL FRAME of the walk cycle at stride phase `phase`, composed
	exactly the way `PlayerAnimation.animate_walking()` composes it: the two
	swings are `A·sin(φ)` and the quadratures the driver is clocked with are
	`A·cos(φ)`. Straight down the driver rather than through `animate_walking()`
	because these probes need ONE swing at a chosen phase with no gait row, no
	hitch and no `Body` write on top.

	READ THE LEFT LEG OFF IT LIKE THIS: `locomotion()` mirrors, so
	`thigh_l = -A·sin(φ)`. φ = -π/2 is the left leg at its FORWARD extreme (heel
	strike), φ = +π/2 its BACK one (push-off), and φ = π is mid-SWING — the thigh
	passing under the body on its way forward, which is where a human knee is at
	its most bent and where this driver's is too.
	"""
	anim.rig.rest_pose()
	anim.rig.set_clock(0.0, land, amp * cos(phase), amp * cos(phase))
	anim.rig.locomotion(amp * sin(phase), amp * sin(phase), 1.0)


func _measure_skinned_joints(anim, fixture: Node3D) -> void:
	"""
	EVERYTHING `measure()` CANNOT ANSWER, measured on the SKELETON in its own
	space — the roll trap, and every joint bead godot-test1-5u3.9 spent.

	(i) IS STILL THE LOAD-BEARING ONE. `_set_axis()` writes `P⁻¹·E·P·R`, `_axis()`
	reads `P·(pose·R⁻¹)·P⁻¹`, and the `P` terms cancel — so every assertion built
	on `measure()` passes for ANY invertible conjugation basis, the wrong one
	included. `get_bone_global_pose()` is outside that algebra: it is where the
	bone actually ends up. A thigh swung about the SKELETON's X carries the knee
	forward and back along ±Z, the way this hero faces; a thigh swung about its
	own MakeHuman-rolled X (`thigh_l`'s local X reads (0.89, 0.21, -0.41)) carries
	it sideways. Caching the bone's own global rest basis instead of its parent's
	in `bind()` is a one-line edit that nothing else in this repo can see, and it
	is exactly the mistake the driver's banner exists to prevent. IT IS MEASURED
	IN THE PELVIS'S OWN FRAME since bead 5u3.9, because the pelvis now twists with
	the stride and would otherwise carry the knee sideways all by itself — which
	is a feature, and not the thing this assertion is about.

	AND THEN THE GAIT, which is the bead: a knee PHASED against the thigh rather
	than rectified off it (straight at BOTH extremes, deepest mid-swing — the old
	`max(0, -thigh)` knee was deepest at one extreme and straight mid-swing, so
	this pair of clauses is its own mutation control), an ankle that keeps the
	sole level, an elbow that lags its shoulder, a pelvis the spine counters, a
	landing taken through the knees, a chest that breathes, and a band around
	every one of them. None of these bones is in `measure()` — deliberately, so
	that check 8g can still compare the two drivers pose for pose — so without
	this function every one of them could be deleted green.
	"""
	var found: Array[Node] = fixture.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		_fail("skinned fixture: no Skeleton3D under the fixture to measure in "
				+ "skeleton space — (h) and (i) did not run")
		Sentinel.done("skinned_joints")
		return
	var skel: Skeleton3D = found[0] as Skeleton3D
	var b: Dictionary = {}
	for name: String in ["pelvis", "spine_02", "spine_03", "head", "thigh_l",
			"calf_l", "foot_l", "ball_l", "thigh_r", "clavicle_l", "upperarm_l",
			"upperarm_r", "lowerarm_l", "hand_l"]:
		var idx: int = skel.find_bone(name)
		if idx < 0:
			_fail("skinned fixture: the rig has no `%s` bone — the joint probes " % name
					+ "did not run")
			Sentinel.done("skinned_joints")
			return
		b[name] = idx
	var hip: int = b["thigh_l"]
	var knee: int = b["calf_l"]
	var foot: int = b["foot_l"]
	var ball: int = b["ball_l"]
	var shoulder: int = b["upperarm_l"]
	var hand: int = b["hand_l"]

	var swing: float = deg_to_rad(SKINNED_JOINT_SWING_DEG)

	# ---- THE THREE FRAMES THE LEG PROBES LIVE ON -------------------------
	# Heel strike, push-off and mid-swing (see `_pose_cycle`'s docstring).
	_pose_cycle(anim, -PI * 0.5, swing, 0.0)
	var reach_front: float = _span(skel, foot, hip)
	var knee_front: Vector3 = skel.get_bone_global_pose(b["pelvis"]).affine_inverse() \
			* _at(skel, knee)
	var sole_front: Vector3 = _at(skel, ball) - _at(skel, foot)
	var ball_front_y: float = _at(skel, ball).y
	var arm_back: float = _span(skel, hand, shoulder)
	var chest_frame: Transform3D = skel.get_bone_global_pose(b["spine_03"]).affine_inverse()
	var shoulder_back: Vector3 = chest_frame * _at(skel, shoulder)
	var shoulder_r_back: Vector3 = chest_frame * _at(skel, b["upperarm_r"])

	_pose_cycle(anim, PI * 0.5, swing, 0.0)
	var reach_back: float = _span(skel, foot, hip)
	var knee_back: Vector3 = skel.get_bone_global_pose(b["pelvis"]).affine_inverse() \
			* _at(skel, knee)
	var sole_back: Vector3 = _at(skel, ball) - _at(skel, foot)
	var ball_back_y: float = _at(skel, ball).y
	var arm_front: float = _span(skel, hand, shoulder)
	chest_frame = skel.get_bone_global_pose(b["spine_03"]).affine_inverse()
	var shoulder_front: Vector3 = chest_frame * _at(skel, shoulder)
	var shoulder_r_front: Vector3 = chest_frame * _at(skel, b["upperarm_r"])
	# THE ROLL OF A BONE is the Y component of its own left-right axis — a number
	# that needs no second bone to compare against and no unit to be read in.
	var pelvis_roll: float = absf(skel.get_bone_global_pose(b["pelvis"]).basis.x.y)
	var chest_roll: float = absf(skel.get_bone_global_pose(b["spine_03"]).basis.x.y)
	var pelvis_twist: float = absf(skel.get_bone_global_pose(b["pelvis"]).basis.z.x)

	_pose_cycle(anim, PI, swing, 0.0)
	var reach_swing: float = _span(skel, foot, hip)
	var arm_lagged: float = _span(skel, hand, shoulder)

	# The REST the two contact frames are judged against, and the neutral arm
	# every other path has to come back to. The sole is NOT flat at rest — the
	# foot bone runs from the ankle down to the ball — so what the probe below
	# measures is how far each contact frame tilts it AWAY from where a standing
	# hero plants it, never its absolute angle.
	anim.rig.rest_pose()
	var ball_rest_y: float = _at(skel, ball).y
	var sole_rest: Vector3 = (_at(skel, ball) - _at(skel, foot)).normalized()
	var arm_at_rest: float = _span(skel, hand, shoulder)
	_pose_cycle(anim, 0.0, 0.0, 0.0)
	var arm_neutral: float = _span(skel, hand, shoulder)
	var reach_neutral: float = _span(skel, foot, hip)

	# ---- (i) THE ROLL TRAP -----------------------------------------------
	var travel: Vector3 = knee_front - knee_back
	if travel.length() <= SKINNED_JOINT_TRAVEL_M:
		_fail("skinned fixture: swinging the thigh %.0f deg either way moved the knee "
				% SKINNED_JOINT_SWING_DEG + "only %.4f m in the pelvis's frame — the "
				% travel.length() + "bone pose is not reaching the skeleton at all")
	elif absf(travel.x) > absf(travel.z) * SKINNED_ROLL_TOLERANCE:
		_fail("skinned fixture: the knee travelled (%.4f, %.4f, %.4f) m between the "
				% [travel.x, travel.y, travel.z] + "two extremes of the leg swing — a "
				+ "forward/back swing must move it along the skeleton's Z and "
				+ "essentially NOT sideways (measured ratio %.3f, ceiling %.2f). The "
				% [absf(travel.x) / maxf(absf(travel.z), 1e-9), SKINNED_ROLL_TOLERANCE]
				+ "rotation is being applied about a rolled axis instead of the "
				+ "skeleton's: `_set_axis` must conjugate through the PARENT's global "
				+ "rest basis (see the driver's roll-trap banner). `measure()` cannot "
				+ "see this — the conjugation basis cancels in it.")

	# ---- (h1) THE KNEE IS PHASED, NOT RECTIFIED --------------------------
	# Two clauses, and the OLD driver fails both: it flexed on the back-swing, so
	# it measured short at push-off and straight mid-swing — the exact inverse.
	if reach_swing >= minf(reach_front, reach_back) - SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: hip-to-foot measured %.4f m MID-SWING against %.4f m "
				% [reach_swing, reach_front] + "at heel strike and %.4f m at push-off "
				% reach_back + "— the knee must be at its most bent while the leg "
				+ "swings THROUGH, which is the whole difference between a phased "
				+ "knee and one rectified off the thigh angle")
	if absf(reach_front - reach_back) > SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: hip-to-foot measured %.4f m at heel strike and %.4f m "
				% [reach_front, reach_back] + "at push-off — a leg must be STRAIGHT at "
				+ "both extremes of the stride. One short extreme is a knee that bends "
				+ "on one half of the cycle, which is what `5u3.9` replaced.")

	# ---- (h2) THE SOLE IS LEVEL AT CONTACT, AND ABOVE THE GROUND ---------
	for probe: Array in [[sole_front, ball_front_y, "heel strike"],
			[sole_back, ball_back_y, "push-off"]]:
		var sole: Vector3 = probe[0]
		var tilt: float = absf(sole.normalized().y - sole_rest.y)
		if tilt > SKINNED_SOLE_LEVEL:
			_fail("skinned fixture: at %s the sole (foot to ball) tilted %.3f of its "
					% [probe[2], tilt] + "own length out of level — the ankle must "
					+ "counter-rotate the thigh AND the knee, or a planted foot points "
					+ "at the sky (ceiling %.2f)" % SKINNED_SOLE_LEVEL)
		if float(probe[1]) < ball_rest_y - SKINNED_SOLE_SINK_M:
			_fail("skinned fixture: at %s the ball of the foot sat %.4f m BELOW its own "
					% [probe[2], ball_rest_y - float(probe[1])] + "rest height — the "
					+ "world is flat at y = 0, so a contact frame may lift a foot (this "
					+ "rig has no IK) but must never push one through the ground")

	# ---- (h3) THE ELBOW TRACKS ITS SHOULDER, AND LAGS IT -----------------
	if arm_front >= arm_back - SKINNED_ELBOW_M:
		_fail("skinned fixture: shoulder-to-hand measured %.4f m at the arm's forward "
				% arm_front + "extreme and %.4f m at its back one — the elbow must "
				% arm_back + "TRACK the shoulder (`elbow_track_ratio` off an "
				+ "`elbow_bend_deg` neutral), so the hand comes in as the arm swings "
				+ "forward. A constant or missing elbow write measures no difference "
				+ "at all, and `measure()` does not expose the forearm.")
	if arm_lagged >= arm_front - SKINNED_ELBOW_M:
		_fail("skinned fixture: shoulder-to-hand measured %.4f m a QUARTER CYCLE after "
				% arm_lagged + "the forward extreme and %.4f m at it — the elbow's peak "
				% arm_front + "must LAG the shoulder's (`elbow_lag_deg`, off the arm's "
				+ "quadrature), or the forearm is a stick welded to the upper arm")

	# ---- (h4) A LANDING IS ABSORBED THROUGH THE KNEES --------------------
	_pose_cycle(anim, 0.0, swing, 1.0)
	var reach_land: float = _span(skel, foot, hip)
	if reach_land >= reach_neutral - SKINNED_LAND_KNEE_M:
		_fail("skinned fixture: at the peak of a landing squash hip-to-foot measured "
				+ "%.4f m against the standing %.4f m — the knees must take their share "
				% [reach_land, reach_neutral] + "of the impact (`knee_land_deg`), which "
				+ "is the half of a landing the container squash cannot draw")

	# ---- (h5) THE PELVIS TURNS AND THE SPINE TAKES IT BACK ---------------
	if pelvis_roll <= SKINNED_PELVIS_ROLL:
		_fail("skinned fixture: at full stride the pelvis rolled %.4f (sine of its own "
				% pelvis_roll + "tilt) — it must DROP toward the swinging leg, or the "
				+ "walk is hung off two hip joints and nothing above them moves")
	if pelvis_twist <= SKINNED_PELVIS_TWIST:
		_fail("skinned fixture: at full stride the pelvis yawed %.4f (sine of its own "
				% pelvis_twist + "twist) — the transverse rotation is half of what makes "
				+ "a stride a stride, and `spine_02` takes it back so nothing above the "
				+ "waist pays for it")
	# BOTH SHOULDERS, AND SIGNED. A magnitude on one shoulder is passed just as
	# happily by a girdle that swings forward as one slab, which is the thing a
	# shared skeleton-Y turn exists to avoid: the two clavicles extend in opposite
	# X directions, so one angle must send one shoulder forward and the other
	# back. Measured in the CHEST's own frame, so the spine chain below — whose
	# counter-rotation leaves a residual millimetre or two — cannot pass this on
	# the clavicle's behalf.
	var travel_l: float = shoulder_front.z - shoulder_back.z
	var travel_r: float = shoulder_r_front.z - shoulder_r_back.z
	if minf(absf(travel_l), absf(travel_r)) <= SKINNED_SHOULDER_SWING_M:
		_fail("skinned fixture: the shoulders moved %.4f m and %.4f m between the "
				% [travel_l, travel_r] + "arm's two extremes — the clavicle must FOLLOW "
				+ "its own arm (`shoulder_swing_deg`), or the arm is bolted to a rigid "
				+ "chest")
	elif signf(travel_l) == signf(travel_r):
		_fail("skinned fixture: both shoulders travelled the SAME way (%.4f m and "
				% travel_l + "%.4f m) while the two arms swung in opposition — the "
				% travel_r + "shoulder girdle counter-rotates, it does not slide "
				+ "forward as one slab. One skeleton-Y angle on BOTH clavicles is what "
				+ "draws that; per-side angles cancel it.")
	if chest_roll > SKINNED_CHEST_LEVEL:
		_fail("skinned fixture: at full stride the chest rolled %.4f where the pelvis "
				% chest_roll + "rolled %.4f — `spine_02` must take the pelvis's turn "
				% pelvis_roll + "BACK, or the whole upper body rolls with the hips "
				+ "(ceiling %.4f)" % SKINNED_CHEST_LEVEL)

	# ---- (h5b) A STRAFE PUTS BACK EVERY JOINT IT DOES NOT DRIVE ----------
	# `sidestep()` writes the Z axes and nothing else, so every joint bead
	# `5u3.9` added — knee, ankle, clavicle, pelvis, spine — is inherited from
	# whatever stride the strafe interrupted and frozen there for as long as the
	# step is held. Entered OUT OF A STRIDE, because from rest they are already
	# at rest and the assertion would be vacuous. Measured against the rest pose
	# through the same chest frame the shoulder probe uses.
	anim.rig.rest_pose()
	var rest_frame: Transform3D = skel.get_bone_global_pose(b["spine_03"]).affine_inverse()
	var rest_shoulder: Vector3 = rest_frame * _at(skel, shoulder)
	var rest_pelvis_roll: float = absf(skel.get_bone_global_pose(b["pelvis"]).basis.x.y)
	var rest_reach: float = _span(skel, foot, hip)
	# THREE QUARTERS ROUND, not mid-swing: at phase PI the leg is bent but the ARM
	# is at centre, so the clavicle is already at rest and its clause would pass
	# vacuously (measured — the first version of this probe did exactly that).
	# 3*PI/4 opens the arm, the knee AND the pelvis at once.
	_pose_cycle(anim, PI * 0.75, swing, 0.0)
	anim.rig.sidestep(0.2, -0.13, true, 0.08, 0.22, -0.05)
	var strafe_frame: Transform3D = skel.get_bone_global_pose(b["spine_03"]).affine_inverse()
	var strafe_shoulder: Vector3 = strafe_frame * _at(skel, shoulder)
	if strafe_shoulder.distance_to(rest_shoulder) > SKINNED_SHOULDER_SWING_M:
		_fail("skinned fixture: a strafe entered out of a stride left the shoulder "
				+ "%.4f m from where a standing hero holds it — a sidestep drives the Z "
				% strafe_shoulder.distance_to(rest_shoulder) + "axes only, so every "
				+ "joint it does not write has to be PUT BACK or it freezes there for "
				+ "as long as the step is held")
	if absf(skel.get_bone_global_pose(b["pelvis"]).basis.x.y - rest_pelvis_roll) > SKINNED_CHEST_LEVEL:
		_fail("skinned fixture: a strafe entered out of a stride kept the stride's "
				+ "pelvis drop — `_settle_torso(1.0)` is what puts it back")
	if absf(_span(skel, foot, hip) - rest_reach) > SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: a strafe entered out of a stride kept the stride's "
				+ "bent knee (hip-to-foot %.4f m against a standing %.4f m)"
				% [_span(skel, foot, hip), rest_reach])

	# ---- (h6) THE ELBOW'S NEUTRAL IS THE SAME ON EVERY PATH --------------
	# Round 1's fix, and the one joint write that lives OUTSIDE `locomotion()`.
	# Standing still must ease the forearm to `elbow_bend_deg`, not straighten it:
	# easing it to zero is what made a skinned hero's arms straighten over half a
	# second and then snap back 15 degrees on the first walking frame, and it is
	# also what made a standing LOCAL hero differ from a standing REMOTE one (the
	# mirror has no idle branch — it calls `locomotion()` with both swings at zero).
	for i: int in RELAX_FRAMES:
		anim.rig.idle(0.1)
	var arm_idle: float = _span(skel, hand, shoulder)
	if absf(arm_idle - arm_neutral) > SKINNED_ELBOW_M:
		_fail("skinned fixture: standing still settled the arm at %.4f m shoulder-to-"
				% arm_idle + "hand where the neutral walk pose holds it at %.4f m — "
				% arm_neutral + "the elbow's rest must be the same on every path, or "
				+ "it straightens while you stand and snaps back the frame you walk")
	if absf(arm_at_rest - arm_neutral) > SKINNED_ELBOW_M:
		_fail("skinned fixture: `rest_pose()` left the arm at %.4f m shoulder-to-hand "
				% arm_at_rest + "where the neutral pose holds it at %.4f m — restoring "
				% arm_neutral + "the rest pose must restore the elbow's neutral bend "
				+ "too, or a character swap draws one frame of straightened arms")

	# ---- (h7) THE AIR POSE PULLS IN, AND FORGETS THE STRIDE IT LEFT ------
	# A body that has left the ground tucks: the forearms come UP and the knee
	# FOLDS. Both are measured against the neutral pose, and both are entered OUT
	# OF A STRIDE, because from a rest pose the leg is already straight and the
	# assertions would be vacuous. The second entry, from the opposite stride,
	# is the one that catches a pose that merely eases toward wherever it started.
	_pose_cycle(anim, PI * 0.5, swing, 0.0)
	for i: int in RELAX_FRAMES:
		anim.rig.air(deg_to_rad(72.0), deg_to_rad(10.0), 0.2)
	var arm_air: float = _span(skel, hand, shoulder)
	var leg_air: float = _span(skel, foot, hip)
	_pose_cycle(anim, -PI * 0.5, swing, 0.0)
	for i: int in RELAX_FRAMES:
		anim.rig.air(deg_to_rad(72.0), deg_to_rad(10.0), 0.2)
	if arm_air >= arm_neutral - SKINNED_ELBOW_M:
		_fail("skinned fixture: airborne, the arm sat at %.4f m shoulder-to-hand where "
				% arm_air + "the neutral pose holds it at %.4f m — the forearms must "
				% arm_neutral + "come UP at the apex (`air_elbow_deg`)")
	if leg_air >= reach_neutral - SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: airborne, hip-to-foot measured %.4f m against the "
				% leg_air + "straight leg's %.4f m — the tuck must FOLD the knee "
				% reach_neutral + "(`air_knee_deg`), not leave it hanging")
	if absf(_span(skel, foot, hip) - leg_air) > SKINNED_KNEE_FLEX_M \
			or absf(_span(skel, hand, shoulder) - arm_air) > SKINNED_ELBOW_M:
		_fail("skinned fixture: the air pose settled differently out of the two halves "
				+ "of the stride (%.4f vs %.4f m hip-to-foot) — an airborne hero must "
				% [_span(skel, foot, hip), leg_air] + "forget the stride it left, or a "
				+ "jump looks different depending on which foot was down")

	# ---- (h8) STANDING STILL BREATHES ------------------------------------
	# Four clocks across one breath cycle, each posed from rest so nothing but the
	# clock can differ. An idle that does not move the chest is a statue, and an
	# idle that moves it a lot is a nod.
	#
	# MEASURED AT THE HEAD, not on `spine_03` itself: a bone's own origin is set
	# by its PARENTS, so a chest that pitches does not move its own head one
	# micron and the probe would read zero however hard it breathed. The head is
	# the far end of the chain the breath turns. Its Z is the breath (a pitch) and
	# its X the weight shift (the pelvis's roll), which is what lets one loop
	# assert both and neither hide the other.
	var chest_lo: float = INF
	var chest_hi: float = -INF
	var shift_lo: float = INF
	var shift_hi: float = -INF
	for i: int in 16:
		anim.rig.rest_pose()
		anim.rig.set_clock(float(i) * 0.5, 0.0, 0.0, 0.0)
		anim.rig.idle(1.0)
		var head_at: Vector3 = _at(skel, b["head"])
		chest_lo = minf(chest_lo, head_at.z)
		chest_hi = maxf(chest_hi, head_at.z)
		shift_lo = minf(shift_lo, head_at.x)
		shift_hi = maxf(shift_hi, head_at.x)
	var breath: float = chest_hi - chest_lo
	var shift: float = shift_hi - shift_lo
	if shift < SKINNED_SHIFT_M:
		_fail("skinned fixture: over one weight-shift cycle a standing hero swayed "
				+ "%.5f m — standing still has to SHIFT ITS WEIGHT (`shift_deg` at "
				% shift + "`shift_hz`), or it is a hero balanced on both feet forever")
	elif shift > SKINNED_SHIFT_CEILING_M:
		_fail("skinned fixture: a standing hero swayed %.4f m — the ceiling is %.3f m; "
				% [shift, SKINNED_SHIFT_CEILING_M] + "more than that is a stagger")
	if breath < SKINNED_BREATH_M:
		_fail("skinned fixture: over one breath cycle the chest travelled %.5f m — "
				% breath + "standing still has to BREATHE (`breath_deg` at `breath_hz`, "
				+ "off the caller's clock), or the hero is a statue between strides")
	elif breath > SKINNED_BREATH_CEILING_M:
		_fail("skinned fixture: the chest travelled %.4f m over one breath cycle — the "
				% breath + "ceiling is %.3f m; more than that reads as a nod, not a "
				% SKINNED_BREATH_CEILING_M + "breath")

	# ---- (h9) THE SKINNED BAND -------------------------------------------
	# Every bone bead `5u3.9` added, over a real clocked walk sweep, measured as
	# the ANGLE OF ITS POSE FROM ITS OWN REST — a reading with no conjugation in
	# it, so unlike everything built on `measure()` it cannot be flattered by the
	# driver's own algebra.
	var step: float = 1.0 / SWEEP_HZ
	var worst: Dictionary = {}
	for family: String in SKINNED_BAND_DEG:
		worst[family] = 0.0
	for multiplier: float in [1.0, 1.5]:
		for i: int in int(SKINNED_SWEEP_SECONDS * SWEEP_HZ):
			anim.animation_time = float(i) * step
			anim.animate_walking(step, multiplier)
			for family: String in SKINNED_BAND_DEG:
				for name: String in ([family] if skel.find_bone(family) >= 0
						else [family + "_l", family + "_r"]):
					var idx: int = skel.find_bone(name)
					if idx < 0:
						continue
					var off: float = skel.get_bone_pose_rotation(idx).angle_to(
							skel.get_bone_rest(idx).basis.get_rotation_quaternion())
					if not is_finite(off):
						_fail("skinned fixture: `%s` reached a non-finite pose" % name)
						Sentinel.done("skinned_joints")
						return
					worst[family] = maxf(float(worst[family]), off)
	for family: String in SKINNED_BAND_DEG:
		var ceiling: float = deg_to_rad(float(SKINNED_BAND_DEG[family]))
		if float(worst[family]) > ceiling:
			_fail("skinned fixture: `%s` reached %.1f deg off rest over the walk sweep "
					% [family, rad_to_deg(float(worst[family]))] + "— the band is %.1f. "
					% float(SKINNED_BAND_DEG[family]) + "`measure()` answers the shoulder "
					+ "and the hip and nothing else, so this is the only envelope the "
					+ "joints bead `5u3.9` added have.")

	Sentinel.done("skinned_joints")


func _check_skinned_determinism(player: Node3D) -> void:
	"""
	TWO DRIVERS, TWO MODELS, ONE CLOCK — the multiplayer contract as a
	measurement, and the sharpest one in this file (bd godot-test1-5u3.9).

	Check 8(e) already asks one driver the same clock twice. This asks TWO, on two
	separate instances of the hero, walked to that clock along DIFFERENT paths —
	one straight there, one after a long sweep and an idle — and compares EVERY
	BONE of the skeleton, not the eleven keys `measure()` exposes. That is what
	makes it the guard bead `5u3.9` needs: the seven bones it added are invisible
	to `measure()`, so a `randf()` in the pelvis, an accumulator in the breath or
	a knee derived from the previous frame would all pass check 8(e) and diverge
	on every peer.

	THE MUTATION CONTROL is one line: put `randf()` anywhere in
	`hero_rig_skeleton.gd` and this goes red, where every other assertion in this
	file stays green.
	"""
	var packed: PackedScene = load(SKINNED_FIXTURE)
	if packed == null:
		_fail("could not load %s for the determinism probe" % SKINNED_FIXTURE)
		Sentinel.done("skinned_determinism")
		return
	var anims: Array = []
	var skels: Array[Skeleton3D] = []
	var fixtures: Array[Node3D] = []
	for i: int in 2:
		var fixture: Node3D = packed.instantiate()
		root.add_child(fixture)
		var anim: PlayerAnimation = PlayerAnimation.new()
		anim.player = player
		var saved: Node = player.current_character_node
		player.current_character_node = fixture
		anim.original_rotations = PlayerAnimation.capture_rest_pose(fixture)
		anim.setup_animation_references()
		player.current_character_node = saved
		anim._gait = PlayerAnimation.gait_for("teibi")
		anim._gait["head_deg"] = FIXTURE_HEAD_DEG
		var found: Array[Node] = fixture.find_children("*", "Skeleton3D", true, false)
		if anim.rig == null or found.is_empty():
			_fail("the determinism probe could not bind a skinned driver to %s"
					% SKINNED_FIXTURE)
			fixture.queue_free()
			Sentinel.done("skinned_determinism")
			return
		anims.append(anim)
		skels.append(found[0] as Skeleton3D)
		fixtures.append(fixture)

	# INSTANCE B TAKES THE LONG WAY ROUND: a sweep it does not keep, an idle, and
	# an air pose, so that when it is finally asked for the shared clock it is
	# arriving from somewhere else entirely. A driver carrying anything between
	# frames answers differently from the two histories.
	var step: float = 1.0 / SWEEP_HZ
	for i: int in 400:
		anims[1].animation_time = float(i) * step * 3.0
		anims[1].animate_walking(step, 1.5)
	for i: int in 30:
		anims[1].animate_idle(step)
		anims[1].animate_jumping()

	# TWO COMPARISONS, and the first is the one with teeth. `reset` puts both
	# skeletons back to the exported rest before the shared clock, so the two
	# drivers are posed from IDENTICAL state and any difference at all is the
	# driver reading something it was not handed — an RNG, a wall clock, a member
	# it accumulated into. The second asks the same question with one instance
	# arriving out of 430 frames of walking, which is the honest multiplayer case
	# and is therefore allowed the float drift `SKINNED_DRIFT_EPS` documents.
	var worst: float = 0.0
	var worst_bone: String = ""
	var worst_live: float = 0.0
	var worst_live_bone: String = ""
	# THE LIVE SWEEP RUNS FIRST, ALL OF IT. `rest_pose()` restores the exported
	# pose exactly, so a single `reset` pass erases the 430 frames prepared above
	# and every "live" comparison after it would be comparing two instances that
	# had just been made identical — vacuous, and green for the wrong reason.
	for reset: bool in [false, true]:
		for t: float in SKINNED_DETERMINISM_TIMES:
			for j: int in 2:
				if reset:
					anims[j].rig.rest_pose()
				anims[j].animation_time = t
				anims[j].animate_walking(step, 1.0)
			for bone: int in skels[0].get_bone_count():
				var qa: Quaternion = skels[0].get_bone_pose_rotation(bone)
				var qb: Quaternion = skels[1].get_bone_pose_rotation(bone)
				var gap: float = maxf(maxf(absf(qa.x - qb.x), absf(qa.y - qb.y)),
						maxf(absf(qa.z - qb.z), absf(qa.w - qb.w)))
				if reset and gap > worst:
					worst = gap
					worst_bone = skels[0].get_bone_name(bone)
				elif not reset and gap > worst_live:
					worst_live = gap
					worst_live_bone = skels[0].get_bone_name(bone)
	if worst_live > SKINNED_DRIFT_EPS:
		_fail("two skinned drivers walked to the same animation_time down different "
				+ "histories drew `%s` %.8f apart — the ceiling is %.6f, which is the "
				% [worst_live_bone, worst_live, SKINNED_DRIFT_EPS] + "euler round "
				+ "trip's own float drift and nothing else. Anything above it is state.")
	if worst > SKINNED_DETERMINISM_EPS:
		_fail("two skinned drivers posed from rest at the same animation_time drew "
				+ "`%s` %.8f apart — the pose must be a pure function of (hero, "
				% [worst_bone, worst] + "animation_time, gait state) or two peers draw "
				+ "two different heroes. Something in `hero_rig_skeleton.gd` is reading "
				+ "a clock, a previous frame or an RNG it was not handed.")

	for fixture: Node3D in fixtures:
		fixture.queue_free()
	Sentinel.done("skinned_determinism")


## The keys BOTH rigs own, and the ones check 8's equivalence script compares.
## `body_y` / `body_x` / `body_z` are deliberately absent: the caller writes them
## on the `Body` NODE for either rig kind, and the two rigs in that comparison
## hang off two different bodies.
const RIG_KEYS: Array[String] = ["left_arm_x", "right_arm_x", "left_leg_x",
		"right_leg_x", "left_arm_z", "right_arm_z", "left_leg_z", "right_leg_z",
		"head_z"]


func _drive_rig(rig) -> Array[Dictionary]:
	"""
	Run one fixed script of driver calls and return what `measure()` said after
	each. Every number is arbitrary and asymmetric ON PURPOSE — a swapped side or
	a dropped `arm_asym` has to show up, which round numbers and mirrored
	arguments would hide — and every pose method the contract has is exercised:
	`rest_pose`, `locomotion`, `head_bobble`, `relax_head`, `idle`, `air`, `drop_wings`,
	`sidestep`, `reset_roll` and `slump`, the two lerping ones (`idle`, `air`)
	twice so their accumulation is compared too.

	`slump` closes the script because that is the tower's own call order — a
	jailed hero is snapped to rest and then slumped, once (bd godot-test1-6su).
	It is the one pose on the contract no clock drives, so nothing else in this
	suite sweeps it: without this pair of lines a skinned captive could go back
	to standing to attention with every check in the file still green.
	"""
	var out: Array[Dictionary] = []
	rig.rest_pose()
	out.append(rig.measure())
	rig.locomotion(0.31, -0.52, 1.05)
	out.append(rig.measure())
	rig.head_bobble(0.07)
	out.append(rig.measure())
	rig.relax_head(0.4)
	out.append(rig.measure())
	rig.idle(0.25)
	out.append(rig.measure())
	rig.idle(0.25)
	out.append(rig.measure())
	rig.sidestep(0.2, -0.13, true, 0.08, 0.22, -0.05)
	out.append(rig.measure())
	rig.sidestep(0.2, 0.13, false, -0.08, -0.22, 0.05)
	out.append(rig.measure())
	rig.reset_roll()
	out.append(rig.measure())
	rig.air(1.2, 0.17, 0.2)
	out.append(rig.measure())
	rig.air(1.3, 0.17, 0.2)
	out.append(rig.measure())
	rig.drop_wings()
	out.append(rig.measure())
	rig.locomotion(-0.31, 0.52, 0.86)
	out.append(rig.measure())
	rig.rest_pose()
	out.append(rig.measure())
	# Two different numbers, neither round: a driver that swapped the arm and leg
	# arguments, or wrote one of them onto both pairs, has to show up here.
	rig.slump(0.37, -0.14)
	out.append(rig.measure())
	return out


func _hero_index(hero: String) -> int:
	"""`CHARACTERS` index by name, or 0 — the roster is a const and every name in
	it is unique, so this is a lookup and not a search that can fail meaningfully."""
	for index: int in PlayerController.CHARACTERS.size():
		if String(PlayerController.CHARACTERS[index]["name"]) == hero:
			return index
	return 0
