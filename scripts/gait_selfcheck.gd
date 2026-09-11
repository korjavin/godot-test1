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
## (`scenes/characters/teibi.tscn`), a model with no `LeftArm` at all. Windman
## joined him on the bone rig at bead 5u3.5; Primm and Phoboman are still on the
## limb rig, and checks 1-7 — which run every hero in `CHARACTERS`, the skinned
## ones included — still measure exactly what they measured, through
## `rig.measure()`, on whichever driver each took.
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
	"""
	var packed: PackedScene = load(SKINNED_FIXTURE)
	if packed == null:
		_fail("could not load %s — the skinned driver has no fixture to prove "
				% SKINNED_FIXTURE + "itself on, so nothing below ran")
		Sentinel.done("skinned")
		Sentinel.done("skinned_joints")
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
	#     THE ORACLE IS A HERO STILL ON LIMBS, and the epic keeps taking them: it
	#     was Teibi until bead godot-test1-5u3.3 made him the fixture above, then
	#     Windman until bead 5u3.5 migrated him too, and Primm goes at 5u3.6. So it
	#     is PHOBOMAN, who is the END of that line rather than the next name on it:
	#     his sphere body stays on the limb rig for good by owner ruling (epic 5u3
	#     NOTES, "yes, sphere"), which is what guarantees this oracle always has
	#     somebody left to be. The guard right below is what makes each hand-off
	#     loud rather than silent: it fails the moment this name picks up a
	#     Skeleton3D, so the check can never compare the bone driver against itself
	#     and call it agreement.
	player.set_active_character(_hero_index("phoboman"))
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

	fixture.queue_free()
	Sentinel.done("skinned")


func _measure_skinned_joints(anim, fixture: Node3D) -> void:
	"""
	(h) and (i) — the two things `measure()` cannot answer, measured on the
	SKELETON in its own space.

	(i) is the load-bearing one. `_set_axis()` writes `P⁻¹·E·P·R`, `_axis()`
	reads `P·(pose·R⁻¹)·P⁻¹`, and the `P` terms cancel — so every assertion
	built on `measure()` passes for ANY invertible conjugation basis, the wrong
	one included. `get_bone_global_pose()` is outside that algebra: it is where
	the bone actually ends up. A thigh swung about the SKELETON's X carries the
	knee forward and back along ±Z, the way this hero faces; a thigh swung about
	its own MakeHuman-rolled X (`thigh_l`'s local X reads (0.89, 0.21, -0.41))
	carries it sideways. Caching the bone's own global rest basis instead of its
	parent's in `bind()` is a one-line edit that nothing else in this repo can
	see, and it is exactly the mistake the driver's banner exists to prevent.

	(h) rides the same two poses: the knee bends on the BACK-swing only, which
	pulls the foot closer to the hip than the straight forward-swing leg, and the
	elbow opens from 24 to 6 degrees across the arm's own swing, which moves the
	hand toward and away from the shoulder. Those are the two joints the limb rig
	HAS — every hero scene hangs a `LowerArm` under its `LeftArm` — and has never
	once moved.
	"""
	var found: Array[Node] = fixture.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		_fail("skinned fixture: no Skeleton3D under the fixture to measure in "
				+ "skeleton space — (h) and (i) did not run")
		Sentinel.done("skinned_joints")
		return
	var skel: Skeleton3D = found[0] as Skeleton3D
	var hip: int = skel.find_bone("thigh_l")
	var knee: int = skel.find_bone("calf_l")
	var foot: int = skel.find_bone("foot_l")
	var shoulder: int = skel.find_bone("upperarm_l")
	var hand: int = skel.find_bone("hand_l")
	if hip < 0 or knee < 0 or foot < 0 or shoulder < 0 or hand < 0:
		_fail("skinned fixture: the rig has no thigh_l/calf_l/foot_l or "
				+ "upperarm_l/hand_l chain to measure")
		Sentinel.done("skinned_joints")
		return

	# Straight down the driver, not through `animate_walking()`: this needs the
	# two extremes of ONE swing with nothing else written on top.
	var swing: float = deg_to_rad(SKINNED_JOINT_SWING_DEG)
	# LEFT leg forward / LEFT arm forward is one swing each way: the leg takes
	# `-leg_swing` and the arm `+arm_swing`, which is the diagonal (c) asserts.
	anim.rig.rest_pose()
	anim.rig.locomotion(swing, -swing, 1.0)   # leg FORWARD (knee straight), elbow 24 deg
	var knee_front: Vector3 = skel.get_bone_global_pose(knee).origin
	var reach_front: float = skel.get_bone_global_pose(foot).origin.distance_to(
			skel.get_bone_global_pose(hip).origin)
	var arm_bent: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)
	anim.rig.rest_pose()
	anim.rig.locomotion(-swing, swing, 1.0)   # leg BACK (knee flexed), elbow 6 deg
	var knee_back: Vector3 = skel.get_bone_global_pose(knee).origin
	var reach_back: float = skel.get_bone_global_pose(foot).origin.distance_to(
			skel.get_bone_global_pose(hip).origin)
	var arm_straight: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)

	var travel: Vector3 = knee_front - knee_back
	if travel.length() <= SKINNED_JOINT_TRAVEL_M:
		_fail("skinned fixture: swinging the thigh %.0f deg either way moved the knee "
				% SKINNED_JOINT_SWING_DEG + "only %.4f m in skeleton space — the bone "
				% travel.length() + "pose is not reaching the skeleton at all")
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

	if reach_back >= reach_front - SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: hip-to-foot measured %.4f m on the back-swing and "
				% reach_back + "%.4f m on the forward one — the knee must FLEX behind "
				% reach_front + "the body and stay straight in front of it, which is "
				+ "the joint the limb rig has never had")

	# THE ELBOW'S NEUTRAL IS THE SAME ON EVERY PATH — round 1's fix, and the one
	# joint write that lives OUTSIDE `locomotion()`. Standing still must ease the
	# forearm to `ELBOW_BEND_DEG`, not straighten it: easing it to zero is what
	# made a skinned hero's arms straighten over half a second and then snap back
	# 15 degrees on the first walking frame, and it is also what made a standing
	# LOCAL hero differ from a standing REMOTE one (the mirror has no idle branch
	# — it calls `locomotion()` with both swings at zero).
	anim.rig.rest_pose()
	anim.rig.locomotion(0.0, 0.0, 1.0)
	var arm_neutral: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)
	for i: int in RELAX_FRAMES:
		anim.rig.idle(0.1)
	var arm_idle: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)
	if absf(arm_idle - arm_neutral) > SKINNED_ELBOW_M:
		_fail("skinned fixture: standing still settled the arm at %.4f m shoulder-to-"
				% arm_idle + "hand where the neutral walk pose holds it at %.4f m — "
				% arm_neutral + "the elbow's rest must be the same on every path, or "
				+ "it straightens while you stand and snaps back the frame you walk")

	# ...and so do the OTHER two paths that write the joints. `measure()` exposes
	# neither the forearm nor the calf (its keys are the limb rig's, or the shared
	# bounds would stop meaning the same thing), so without these three distances
	# `rest_pose()`'s and `air()`'s joint writes could be deleted green.
	anim.rig.rest_pose()
	var arm_at_rest: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)
	if absf(arm_at_rest - arm_neutral) > SKINNED_ELBOW_M:
		_fail("skinned fixture: `rest_pose()` left the arm at %.4f m shoulder-to-hand "
				% arm_at_rest + "where the neutral pose holds it at %.4f m — restoring "
				% arm_neutral + "the rest pose must restore the elbow's neutral bend "
				+ "too, or a character swap draws one frame of straightened arms")

	# The AIR pose straightens the knee and holds the elbow at its neutral: a leg
	# tucked with a knee still flexed from the last stride is the airborne version
	# of the leftover roll `drop_wings()` clears. GOING AIRBORNE OUT OF A STRIDE,
	# because that is the only way the assertion can see the straightening at all —
	# from a rest pose the knee is already straight and the check would be vacuous.
	anim.rig.locomotion(-swing, swing, 1.0)
	for i: int in RELAX_FRAMES:
		anim.rig.air(deg_to_rad(72.0), deg_to_rad(10.0), 0.2)
	var arm_air: float = skel.get_bone_global_pose(hand).origin.distance_to(
			skel.get_bone_global_pose(shoulder).origin)
	var leg_air: float = skel.get_bone_global_pose(foot).origin.distance_to(
			skel.get_bone_global_pose(hip).origin)
	if absf(arm_air - arm_neutral) > SKINNED_ELBOW_M:
		_fail("skinned fixture: airborne, the arm sat at %.4f m shoulder-to-hand where "
				% arm_air + "the neutral pose holds it at %.4f m — the wings must beat "
				% arm_neutral + "with the elbow at its neutral bend")
	if absf(leg_air - reach_front) > SKINNED_KNEE_FLEX_M:
		_fail("skinned fixture: airborne, hip-to-foot measured %.4f m against the "
				% leg_air + "straight leg's %.4f m — the tuck must STRAIGHTEN the knee, "
				% reach_front + "or a leg goes up still bent from the last stride")

	if arm_bent >= arm_straight - SKINNED_ELBOW_M:
		_fail("skinned fixture: shoulder-to-hand measured %.4f m at the arm's forward "
				% arm_bent + "extreme and %.4f m at its back one — the elbow must "
				% arm_straight + "TRACK the shoulder (`ELBOW_TRACK_RATIO` off a "
				+ "`ELBOW_BEND_DEG` neutral), so the hand comes in as the arm swings "
				+ "forward. A constant or missing elbow write measures no difference "
				+ "at all, and `measure()` does not expose the forearm.")

	Sentinel.done("skinned_joints")


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
