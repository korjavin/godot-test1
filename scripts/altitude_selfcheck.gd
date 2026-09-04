extends SceneTree
## Headless self-check: THE FIELD ALTITUDE SPIKE (bead godot-test1-ope.1).
##
##   godot --headless --path . --script res://scripts/altitude_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the same
## shape as tower_site_selfcheck.gd, and it exists for the same reason: every way
## of breaking a noise field looks like ordinary scenery from the outside.
##
## WHAT IT GUARDS. The spike ships behind `FIELD_ALTITUDE = false`, so it has two
## halves and this file asserts both:
##
##   1. THE FLAG IS OFF, AND OFF MEANS EXACTLY 0.0. Not "small", not "flat
##      enough" — the flat world is what ships, every other self-check in the
##      project asserts against y = 0, and a height field that leaked one
##      millimetre would fail them in ways that read as unrelated bugs. Check 1.
##   2. THE CPU AND THE GPU COMPUTE THE SAME FIELD. `height_at()` here and
##      `field_height()` in assets/shaders/ground.gdshader are the same function
##      in two languages under the same contract `_biome_noise` / `biome_noise`
##      already live under: same constants, same fp32, edited together. GDScript
##      floats are f64 and GLSL runs f32, so the port routes every step through
##      Vector2 (the only fp32 cast GDScript has) — and check 2 is what proves
##      that routing is still there, by re-deriving the field a second time
##      straight off the GLSL text and demanding bit-exact agreement.
##
## CHECK 2 CARRIES ITS OWN NEGATIVE CONTROL, and it is the point of the check: a
## naive f64 oracle (bare scalars, no Vector2 anywhere) must DISAGREE with the
## shipped port at a large fraction of points. Without that leg, "the two agree"
## is also what you get when the fp32 routing has been quietly simplified away
## and both copies are f64 — which is precisely the regression _biome_hash2's
## docstring records as having moved the waterline by metres.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches. They are not a
## failure — same note as enemy_spawn_selfcheck.gd's header.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

## THE END-OF-CHECK SENTINEL — see scripts/selfcheck_sentinel.gd.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## Seeds. Three is plenty: every check here is about the FUNCTION, and the only
## per-seed input is biome_offset (a domain shift), so more seeds buy more of the
## same field rather than more coverage.
const SEEDS: Array[int] = [20260904, 1, 424242]

## Sample count per seed. 10,000 points over the +/- 5 km box below is roughly one
## sample per 10,000 m^2 — dense enough that the altitude field's 260 m cells are
## each hit dozens of times.
const SAMPLES: int = 10000

## Half-width of the sampled box, in metres. 5 km covers the whole distance a run
## realistically walks (Budapest's gate is 1.7 km out) plus the mod(289) noise wrap
## at ~11.5 km is deliberately NOT reached, so the samples exercise the field
## rather than its tiling.
const SAMPLE_HALF: float = 5000.0

## Tolerance on the composed height, in metres. The noise itself must be BIT-exact
## (the oracle is the same arithmetic in the same order), so this only absorbs the
## amplitude ladder's lerpf/smoothstep, which GDScript evaluates in f64 on both
## sides. 1e-4 m is a tenth of a millimetre.
const HEIGHT_EPSILON: float = 1e-4

## How much of the sample the f64 negative control must disagree on before the
## fp32 routing counts as proven. Measured well above 1% in practice; the low bar
## is deliberate, because the assertion is "the two are different fields", not a
## tuned divergence rate.
const F64_DISAGREE_MIN_FRACTION: float = 0.01

## What counts as a disagreement for the control, in metres. A millimetre: far
## above HEIGHT_EPSILON, so the two legs can never both pass on the same noise.
const F64_DISAGREE_EPSILON: float = 1e-3

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING: a node added to `root` from inside _initialize()
	# is not is_inside_tree() until the first frame (enemy_spawn_selfcheck's note).
	await process_frame
	_run()


func _run() -> void:
	_check_flag_is_off()
	_check_fp32_parity()
	_report()


# ============================================================================
# CHECKS
# ============================================================================

func _check_flag_is_off() -> void:
	"""
	Check 1. THE FLAG IS OFF AND OFF MEANS EXACTLY 0.0.

	The merge condition of the whole spike: with FIELD_ALTITUDE false the world is
	byte for byte the flat world every other consumer in this project is written
	against. Equality against 0.0 is exact on purpose — there is no epsilon that
	makes "the ground moved a bit" acceptable to _settle_coin_y.

	It also asserts the const ITSELF is false in the committed tree, because a
	branch that shipped the flip would otherwise pass this check trivially: every
	sample would be non-zero and the loop would report the first one, but a reader
	deserves the direct message.
	"""
	var terrain := _make_terrain(SEEDS[0])
	if terrain.FIELD_ALTITUDE:
		_fail("FIELD_ALTITUDE is true in the committed tree — the spike ships false (see the flag's docstring)")
	if terrain.alt_force:
		_fail("alt_force defaults to true — the self-check seam must be off for the game")
	terrain.free()

	for seed_value: int in SEEDS:
		var t := _make_terrain(seed_value)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i in SAMPLES:
			var x := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var z := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var h: float = t.height_at(x, z)
			if h != 0.0:
				_fail("seed %d: height_at(%.1f, %.1f) = %.9f with the flag off — the flat world is not flat" % [
					seed_value, x, z, h])
				break
		t.free()
	Sentinel.done("flag_is_off")


func _check_fp32_parity() -> void:
	"""
	Check 2. THE fp32 PARITY — the acceptance the bead names.

	Two oracles, written HERE and derived from the GLSL text rather than from the
	GDScript being tested, so this is a re-derivation and not a tautology:

	  * _oracle_pair_f32 — hash2 / value_noise / the two-octave sum, every step
	    routed through Vector2 exactly as GLSL rounds every step to f32. It must
	    agree with the shipped _alt_value_noise_pair BIT-EXACTLY, and the composed
	    height to HEIGHT_EPSILON.
	  * _oracle_pair_f64 — the same recipe in bare GDScript scalars, i.e. f64.
	    It must DISAGREE, at more than F64_DISAGREE_MIN_FRACTION of points. That
	    leg is what gives the first one teeth: without it, both halves being
	    quietly f64 would pass.

	The flag is forced ON through `alt_force` (the self-check seam) so the shipped
	height_at() composes a real height here; check 1 owns the flag-off promise.
	"""
	for seed_value: int in SEEDS:
		var t := _make_terrain(seed_value)
		t.alt_force = true
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var noise_mismatches := 0
		var height_mismatches := 0
		var worst_height := 0.0
		var f64_disagreements := 0
		for i in SAMPLES:
			var x := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var z := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var p: Vector2 = Vector2(x, z) / t.ALT_CELL_SIZE + t.biome_offset + t.ALT_OFFSET_SALT

			var shipped: float = t._alt_value_noise_pair(p)
			var oracle: float = _oracle_pair_f32(p, t)
			if shipped != oracle:
				noise_mismatches += 1

			# The composed height, straight off the plan's recipe, against the
			# shipped one. The amplitude ladder is re-derived too.
			var amp: float = _oracle_amplitude(t._biome_noise(x, z), t)
			var expected: float = (oracle - 0.5) * 2.0 * amp
			var got: float = t.height_at(x, z)
			var delta := absf(got - expected)
			worst_height = maxf(worst_height, delta)
			if delta > HEIGHT_EPSILON:
				height_mismatches += 1

			if absf(_oracle_pair_f64(p, t) - shipped) * amp > F64_DISAGREE_EPSILON:
				f64_disagreements += 1

		if noise_mismatches > 0:
			_fail("seed %d: %d/%d altitude noise samples differ from the fp32 oracle — the Vector2 routing has drifted" % [
				seed_value, noise_mismatches, SAMPLES])
		if height_mismatches > 0:
			_fail("seed %d: %d/%d composed heights differ by more than %.6f m (worst %.6f)" % [
				seed_value, height_mismatches, SAMPLES, HEIGHT_EPSILON, worst_height])
		var fraction := float(f64_disagreements) / float(SAMPLES)
		if fraction < F64_DISAGREE_MIN_FRACTION:
			_fail("seed %d: the f64 control agreed with the shipped port at %.2f%% of points — fp32 routing is NOT being exercised (negative control failed)" % [
				seed_value, (1.0 - fraction) * 100.0])
		print("[altitude] seed %d: noise bit-exact, worst height delta %.9f m, f64 control disagrees at %.1f%% of points" % [
			seed_value, worst_height, fraction * 100.0])
		t.free()
	Sentinel.done("fp32_parity")


# ============================================================================
# THE ORACLES — written off assets/shaders/ground.gdshader, not off the port
# ============================================================================

func _oracle_hash2_f32(p: Vector2) -> float:
	## GLSL: p = mod(p, 289.0); p = fract(p * vec2(0.1031, 0.1030));
	##       p += dot(p, p.yx + 33.33); return fract((p.x + p.y) * p.x);
	## Every line lands in a Vector2 so every intermediate is rounded to f32,
	## which is what a GLSL vec2 does at every assignment.
	var q := Vector2(fposmod(p.x, 289.0), fposmod(p.y, 289.0))
	# The multiplier is built as a Vector2 FIRST, and that is not cosmetic: a bare
	# GDScript 0.1031 is an f64 literal, and multiplying by it rounds a different
	# constant into the answer than GLSL's f32 vec2 does. Measured: 65% of samples
	# differ, which is the whole class of bug this oracle exists to catch.
	q = q * Vector2(0.1031, 0.1030)
	q = Vector2(q.x - floorf(q.x), q.y - floorf(q.y))
	var d := q.dot(Vector2(q.y, q.x) + Vector2(33.33, 33.33))
	q = q + Vector2(d, d)
	var v := Vector2(q.x + q.y, 0.0).x
	v = Vector2(v * q.x, 0.0).x
	return v - floorf(v)


func _oracle_value_noise_f32(p: Vector2) -> float:
	## GLSL value_noise(): four corner hashes, smoothstep weights, two mixes.
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a := _oracle_hash2_f32(i)
	var b := _oracle_hash2_f32(i + Vector2(1.0, 0.0))
	var c := _oracle_hash2_f32(i + Vector2(0.0, 1.0))
	var d := _oracle_hash2_f32(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


func _oracle_pair_f32(p: Vector2, t: Node3D) -> float:
	## GLSL alt_value_noise_pair(): the broad octave plus ALT_DETAIL_WEIGHT of a
	## shifted ALT_DETAIL_SCALE octave, weights summing to 1.
	var w := Vector2(1.0 - t.ALT_DETAIL_WEIGHT, t.ALT_DETAIL_WEIGHT)
	var broad := Vector2(_oracle_value_noise_f32(p) * w.x, 0.0).x
	var detail := Vector2(
			_oracle_value_noise_f32(p * t.ALT_DETAIL_SCALE + t.ALT_DETAIL_SHIFT) * w.y, 0.0).x
	return Vector2(broad + detail, 0.0).x


func _oracle_hash2_f64(p: Vector2) -> float:
	## THE NEGATIVE CONTROL: the identical recipe with no Vector2 anywhere, so
	## every intermediate stays a GDScript double. This is the "obvious" port, and
	## it computes a DIFFERENT field — see _biome_hash2's docstring.
	var px := fposmod(p.x, 289.0)
	var py := fposmod(p.y, 289.0)
	px = px * 0.1031
	py = py * 0.1030
	px = px - floorf(px)
	py = py - floorf(py)
	var d := px * (py + 33.33) + py * (px + 33.33)
	px += d
	py += d
	var v := (px + py) * px
	return v - floorf(v)


func _oracle_value_noise_f64(p: Vector2) -> float:
	var ix := floorf(p.x)
	var iy := floorf(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var a := _oracle_hash2_f64(Vector2(ix, iy))
	var b := _oracle_hash2_f64(Vector2(ix + 1.0, iy))
	var c := _oracle_hash2_f64(Vector2(ix, iy + 1.0))
	var d := _oracle_hash2_f64(Vector2(ix + 1.0, iy + 1.0))
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


func _oracle_pair_f64(p: Vector2, t: Node3D) -> float:
	var wide: float = 1.0 - t.ALT_DETAIL_WEIGHT
	return _oracle_value_noise_f64(p) * wide \
			+ _oracle_value_noise_f64(p * t.ALT_DETAIL_SCALE + t.ALT_DETAIL_SHIFT) * t.ALT_DETAIL_WEIGHT


func _oracle_amplitude(biome_value: float, t: Node3D) -> float:
	## GLSL alt_amplitude(): fragment()'s colour chain with six metres in place of
	## six colours, chained low-to-high over the same thresholds and blend.
	var amp: float = t.ALT_AMP_DESERT
	amp = lerpf(amp, t.ALT_AMP_PLAINS,
			smoothstep(t.BIOME_DESERT_MAX - t.BIOME_BLEND, t.BIOME_DESERT_MAX + t.BIOME_BLEND, biome_value))
	amp = lerpf(amp, t.ALT_AMP_CITY,
			smoothstep(t.BIOME_PLAINS_MAX - t.BIOME_BLEND, t.BIOME_PLAINS_MAX + t.BIOME_BLEND, biome_value))
	amp = lerpf(amp, t.ALT_AMP_FOREST,
			smoothstep(t.BIOME_CITY_MAX - t.BIOME_BLEND, t.BIOME_CITY_MAX + t.BIOME_BLEND, biome_value))
	amp = lerpf(amp, t.ALT_AMP_MOUNTAIN,
			smoothstep(t.BIOME_FOREST_MAX - t.BIOME_BLEND, t.BIOME_FOREST_MAX + t.BIOME_BLEND, biome_value))
	amp = lerpf(amp, t.ALT_AMP_SNOW,
			smoothstep(t.BIOME_MOUNTAIN_MAX - t.BIOME_BLEND, t.BIOME_MOUNTAIN_MAX + t.BIOME_BLEND, biome_value))
	return amp


# ============================================================================
# HELPERS
# ============================================================================

func _make_terrain(seed_value: int) -> Node3D:
	## A REAL terrain node in the tree, not a stub — the chunk_stream_selfcheck
	## recipe. It never streams on its own: `_ready` finds no node in group
	## "player", so `player` stays null and `_process` returns immediately.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
