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

var _failures: Array[String] = []


func _initialize() -> void:
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
		Sentinel.done("personality")
		Sentinel.done("footsteps")
		_report()
		return

	_check_catalogue()

	var player: Node3D = packed.instantiate()
	root.add_child(player)
	await process_frame
	await physics_frame

	if player.left_arm == null or player.character_body == null:
		_fail("player.tscn produced no limb references — the Body/LeftArm/... "
				+ "node-name contract is broken, and no pose below could be measured")
		Sentinel.done("bounds")
		Sentinel.done("expression")
		Sentinel.done("personality")
		Sentinel.done("footsteps")
		player.queue_free()
		_report()
		return

	_check_bounds(player)
	_check_personality(player)
	_check_footsteps(player)

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
	var default_row: Dictionary = PlayerController.GAITS.get("DEFAULT", {})
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
		if not PlayerController.GAITS.has(hero):
			_fail("no GAITS row for hero '%s'" % hero)
		var row: Dictionary = PlayerController.gait_for(hero)
		for key: String in TODAY:
			if not row.has(key):
				_fail("resolved gait for '%s' is missing field '%s'" % [hero, key])
	var unknown: Dictionary = PlayerController.gait_for("no-such-hero")
	for key: String in TODAY:
		if not unknown.has(key) or not is_equal_approx(float(unknown[key]), float(TODAY[key])):
			_fail("gait_for('no-such-hero')['%s'] is not the DEFAULT value — a fifth "
					% key + "character must animate exactly as this game did before GAITS")

	# (c) A typo'd field is the silent failure this catches: it merges in, the
	#     animation never reads it, and the hero walks on the DEFAULT value.
	for hero: String in PlayerController.GAITS:
		for key: String in PlayerController.GAITS[hero]:
			if not TODAY.has(key):
				_fail("GAITS['%s'] carries field '%s', which DEFAULT does not declare — "
						% [hero, key] + "the animation never reads it")
		# (d) The hitch modulates amplitude by `1 + hitch * sin(...)`. At 1.0 or
		#     above that factor reaches zero and then goes NEGATIVE, which
		#     inverts the legs mid-step.
		var amount: float = float(PlayerController.GAITS[hero].get("hitch", 0.0))
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
		if player.character_head and player.original_rotations.has("head"):
			head_rest = float(player.original_rotations["head"].z)

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
				player.animation_time = float(i) * step
				player.animate_walking(step, multiplier)
				for key: String in ["left_arm", "right_arm", "left_leg", "right_leg"]:
					var limb: Node3D = player.get(key)
					if limb == null:
						continue
					if not is_finite(limb.rotation.x):
						bad_finite = true
						continue
					worst_limb = maxf(worst_limb, absf(limb.rotation.x))
					if key == "left_arm" or key == "right_arm":
						reach[key] = maxf(float(reach[key]), absf(
								limb.rotation.x - float(player.original_rotations[key].x)))
				var body: Node3D = player.character_body
				if not is_finite(body.position.y) or not is_finite(body.rotation.z) \
						or not is_finite(body.rotation.x):
					bad_finite = true
				else:
					worst_y_lo = minf(worst_y_lo, body.position.y)
					worst_y_hi = maxf(worst_y_hi, body.position.y)
					var body_rest: Vector3 = player.original_rotations["body"]
					reach["sway"] = maxf(float(reach["sway"]), absf(body.rotation.z - body_rest.z))
					reach["lean"] = maxf(float(reach["lean"]), absf(body.rotation.x - body_rest.x))
				if player.character_head:
					if not is_finite(player.character_head.rotation.z):
						bad_finite = true
					else:
						worst_head = maxf(worst_head,
								absf(player.character_head.rotation.z - head_rest))
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
		var row: Dictionary = PlayerController.gait_for(hero)
		var wants: Dictionary = {
			"sway": float(row["sway_deg"]), "lean": float(row["lean_deg"]),
			"head": float(row["head_deg"]),
		}
		for axis: String in wants:
			var want: float = float(wants[axis])
			if want <= 0.0:
				continue
			if axis == "head" and player.character_head == null:
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
			player.animation_time = far
			player.animate_walking(step, 1.0)
			if not is_finite(player.left_leg.rotation.x) \
					or not is_finite(player.character_body.position.y):
				_fail("%s: the pose went non-finite at animation_time = %.0f s" % [hero, far])

	Sentinel.done("bounds")


# ============================================================================
# CHECK 3 — THE FOUR WALKS DIFFER, AND NONE OF THEM IS A METRONOME
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
		var rate: float = float(PlayerController.gait_for(hero)["stride_rate"])
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
		var rate: float = float(PlayerController.gait_for(hero)["stride_rate"])
		if rate <= 0.0:
			continue
		var period: float = TAU / rate
		var worst: float = 0.0
		var samples: int = int(HITCH_SECONDS / step)
		for i: int in samples:
			var t: float = float(i) * step
			player.animation_time = t
			player.animate_walking(step, 1.0)
			var a: Array[float] = _pose(player)
			player.animation_time = t + period
			player.animate_walking(step, 1.0)
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
		var limb: Node3D = player.get(key)
		out.append(0.0 if limb == null else limb.rotation.x)
	var body: Node3D = player.character_body
	# The bob is metres and everything else radians; it rides the same array
	# because the assertion is "these two moments are not the same pose", and a
	# 0.03 m bob is well above the epsilon either way.
	out.append(body.position.y)
	out.append(body.rotation.z)
	out.append(body.rotation.x)
	if player.character_head:
		out.append(player.character_head.rotation.z)
	return out


# ============================================================================
# CHECK 4 — THE FOOTSTEP BEAT IS THE STRIDE, AND ONLY THE STRIDE
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
			rate = float(PlayerController.gait_for(label)["stride_rate"])
		else:
			player.set_active_character(0)
			player._gait = PlayerController.gait_for("no-such-hero")
			rate = float(player._gait["stride_rate"])

		# Sign 0 is the "just started walking" sentinel: the first sample records
		# its sign silently, exactly as the first frame of a real walk does.
		player._last_walk_sine_sign = 0
		var flips: int = 0
		var previous: int = 0
		for i: int in samples:
			player.animation_time = float(i) * step
			player.animate_walking(step, 1.0)
			var sign_now: int = int(player._last_walk_sine_sign)
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

	# And the rate the DEFAULT row fires at is the one the old literal fired at.
	var default_rate: float = float(PlayerController.gait_for("no-such-hero")["stride_rate"])
	if not is_equal_approx(default_rate, float(TODAY["stride_rate"])):
		_fail("the DEFAULT stride_rate is %.3f, not the pre-table %.3f — every "
				% [default_rate, TODAY["stride_rate"]]
				+ "footstep of an unknown hero would be retimed")

	Sentinel.done("footsteps")
