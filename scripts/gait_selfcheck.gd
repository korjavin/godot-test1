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
		_report()
		return

	_check_catalogue()

	var player: Node3D = packed.instantiate()
	root.add_child(player)
	await process_frame
	await physics_frame

	if player.anim.left_arm == null or player.anim.character_body == null:
		_fail("player.tscn produced no limb references — the Body/LeftArm/... "
				+ "node-name contract is broken, and no pose below could be measured")
		Sentinel.done("bounds")
		Sentinel.done("expression")
		Sentinel.done("relax")
		Sentinel.done("personality")
		Sentinel.done("footsteps")
		Sentinel.done("sidestep")
		player.queue_free()
		_report()
		return

	_check_bounds(player)
	_check_relax(player)
	_check_personality(player)
	_check_footsteps(player)
	_check_sidestep(player)

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
		var head_rest: float = 0.0
		if player.anim.character_head and player.anim.original_rotations.has("head"):
			head_rest = float(player.anim.original_rotations["head"].z)

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
				for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
					var limb: Node3D = player.anim.get(key)
					if limb == null:
						continue
					if not is_finite(limb.rotation.x):
						bad_finite = true
						continue
					worst_limb = maxf(worst_limb, absf(limb.rotation.x))
					if key == "left_arm" or key == "right_arm":
						reach[key] = maxf(float(reach[key]), absf(
								limb.rotation.x - float(player.anim.original_rotations[key].x)))
				var body: Node3D = player.anim.character_body
				if not is_finite(body.position.y) or not is_finite(body.rotation.z) \
						or not is_finite(body.rotation.x):
					bad_finite = true
				else:
					worst_y_lo = minf(worst_y_lo, body.position.y)
					worst_y_hi = maxf(worst_y_hi, body.position.y)
					var body_rest: Vector3 = player.anim.original_rotations["body"]
					reach["sway"] = maxf(float(reach["sway"]), absf(body.rotation.z - body_rest.z))
					reach["lean"] = maxf(float(reach["lean"]), absf(body.rotation.x - body_rest.x))
				if player.anim.character_head:
					if not is_finite(player.anim.character_head.rotation.z):
						bad_finite = true
					else:
						worst_head = maxf(worst_head,
								absf(player.anim.character_head.rotation.z - head_rest))
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
			if axis == "head" and player.anim.character_head == null:
				continue  # optional node, per the row's own docs
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
			if not is_finite(player.anim.left_leg.rotation.x) \
					or not is_finite(player.anim.character_body.position.y):
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
		var body_rest: Vector3 = player.anim.original_rotations["body"]
		if absf(player.anim.character_body.rotation.x - body_rest.x) > 1e-6:
			_fail("%s: a sidestep straight out of a walk left the body pitched %.4f rad "
					% [hero, absf(player.anim.character_body.rotation.x - body_rest.x)]
					+ "off rest — the gait's lean is stuck on")
		if player.anim.character_head and player.anim.original_rotations.has("head"):
			var head_rest: float = float(player.anim.original_rotations["head"].z)
			if absf(player.anim.character_head.rotation.z - head_rest) > 1e-6:
				_fail("%s: a sidestep straight out of a walk left the head %.4f rad off "
						% [hero, absf(player.anim.character_head.rotation.z - head_rest)]
						+ "rest — the gait's bobble is stuck on")
		player.step_direction = 0.0

	Sentinel.done("relax")


func _off_rest(player: Node3D) -> float:
	"""How far the three gait-only axes are from rest, in radians (the worst one)."""
	var body_rest: Vector3 = player.anim.original_rotations["body"]
	var worst: float = maxf(absf(player.anim.character_body.rotation.x - body_rest.x),
			absf(player.anim.character_body.rotation.z - body_rest.z))
	if player.anim.character_head and player.anim.original_rotations.has("head"):
		worst = maxf(worst, absf(
				player.anim.character_head.rotation.z - float(player.anim.original_rotations["head"].z)))
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
	var out: Array[float] = []
	for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
		var limb: Node3D = player.anim.get(key)
		out.append(0.0 if limb == null else limb.rotation.x)
	var body: Node3D = player.anim.character_body
	# The bob is metres and everything else radians; it rides the same array
	# because the assertion is "these two moments are not the same pose", and a
	# 0.03 m bob is well above the epsilon either way.
	out.append(body.position.y)
	out.append(body.rotation.z)
	out.append(body.rotation.x)
	if player.anim.character_head:
		out.append(player.anim.character_head.rotation.z)
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
				var s_gap: float = anim.left_leg.rotation.z - anim.right_leg.rotation.z
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
		for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
			var limb: Node3D = anim.get(key)
			if limb == null:
				continue
			var off: float = absf(limb.rotation.z - float(anim.original_rotations[key].z))
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
		var leg: float = anim.left_leg.rotation.z - anim.right_leg.rotation.z
		out["leg_min"] = minf(float(out["leg_min"]), leg)
		out["leg_max"] = maxf(float(out["leg_max"]), leg)
		var arm: float = anim.left_arm.rotation.z - anim.right_arm.rotation.z
		out["arm_min"] = minf(float(out["arm_min"]), arm)
		out["arm_max"] = maxf(float(out["arm_max"]), arm)
		out["bob"] = maxf(float(out["bob"]), absf(anim.character_body.position.y))
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
	return [anim.left_leg.rotation.z, anim.right_leg.rotation.z,
			anim.left_arm.rotation.z, anim.right_arm.rotation.z,
			anim.character_body.position.y]
