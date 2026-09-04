extends SceneTree
## Headless self-check: THE FIELD ALTITUDE SPIKE (bead godot-test1-ope.1).
##
##   godot --headless --path . --script res://scripts/altitude_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the same
## shape as tower_site_selfcheck.gd, and it exists for the same reason: every way
## of breaking a noise field looks like ordinary scenery from the outside.
##
## WHAT IT GUARDS. The spike ships behind `FIELD_ALTITUDE = false`, so it has
## three halves and this file asserts all of them:
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
##   3. THE AUTHORED ZONES DO NOT MOVE. Budapest, the HQ disc, every river band
##      and the coin road corridor are held at EXACTLY 0.0 by _alt_flat_mask, so
##      the authored world migrates by not migrating and the spike's red-check
##      list stays readable — a red budapest_selfcheck with the flag on means the
##      MASK is wrong, never the check. Check 3, with a per-zone negative control
##      one full skirt outside, because "flat everywhere" also passes a mask that
##      returns zero.
##   4. THE SHADER IS FED WHAT IT DECLARES. Check 2 proves the CPU port matches an
##      oracle written off the GLSL text; it cannot see a uniform the GLSL
##      declares that GDScript never pushes (the GPU silently keeps its own
##      default and the ground you see is a DIFFERENT field from the one you
##      stand on) nor the reverse. Check 4 is budapest_selfcheck's _check_parity /
##      _check_parity_packing idiom over the `alt_*` block: the declarations and
##      the pushes matched BOTH ways, the shader's array bound at least the
##      GDScript's, and the road array read back OFF THE MATERIAL to prove it is
##      packed (x1, z1, x2, z2) and not, say, (x, z, dx, dz).
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

## Samples per zone in check 3, each leg. 2,000 over a zone is dense enough that
## a mask clause with a hole in it (a sign flip, a skirt read as an inner radius)
## is hit many times over, and small enough that the four legs plus their controls
## stay well under a second.
const FLAT_SAMPLES: int = 2000

## How far past a zone's own skirt the negative control samples, in metres. One
## full skirt again: far enough that smoothstep has certainly reached 1.0, so the
## control is measuring "the field is alive out here" and not the ramp.
const FLAT_CONTROL_MARGIN: float = 300.0

## How many road stations either side of the origin check 3 walks. The corridor is
## a curve, so sampling it means sampling the ROAD rather than a box around it.
const FLAT_ROAD_STATIONS: int = 40

## The ground shader — check 4 reads it as TEXT (for the declarations and the
## array bound) and as a loaded Shader (for the push), exactly as
## budapest_selfcheck's parity check reads it.
const SHADER_PATH: String = "res://assets/shaders/ground.gdshader"

## An `alt_*` uniform the shader must NOT declare. The declared-uniform read is
## the whole basis of check 4, so a read that answered "declared" to everything
## would pass it vacuously — prop_selfcheck's ABSENT_UNIFORM control, one block
## along.
const ABSENT_ALT_UNIFORM: String = "alt_amp_ocean"

## How close a pushed road-segment endpoint must land to a real station centre
## before it counts as that station, in metres. The uniform is a
## PackedVector4Array — Vector4 stores real_t = f32 — so the only error here is
## the f64 -> f32 rounding of a coordinate that can be kilometres from the origin;
## a millimetre is orders of magnitude above that and orders of magnitude below
## the 48 m between two nodes of the polyline.
const SEG_ENDPOINT_EPSILON: float = 1e-3

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
	_check_flat_zones()
	_check_shader_parity()
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
			# The flat mask rides along from the SHIPPED function, deliberately:
			# check 2 is about the NOISE PORT, and check 3 is the mask's own
			# assertion (with its own negative control). Re-deriving the four zones
			# here would buy a second copy of them and no extra coverage.
			var flat: float = t._alt_flat_mask(x, z, t._biome_noise(x, z))
			var expected: float = (oracle - 0.5) * 2.0 * amp * flat
			var got: float = t.height_at(x, z)
			var delta := absf(got - expected)
			worst_height = maxf(worst_height, delta)
			if delta > HEIGHT_EPSILON:
				height_mismatches += 1

			# The control compares the NOISE, so it is measured on the unmasked
			# height — a point inside an authored zone is 0.0 by construction on
			# both sides and would dilute the fraction with agreements that say
			# nothing about the port.
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


func _check_flat_zones() -> void:
	"""
	Check 3. THE FOUR FORCED-FLAT ZONES HOLD.

	With the flag forced ON, every point inside an authored zone must read EXACTLY
	0.0 — not "nearly flat". The authored world (Budapest's 2,025 chunk cells, the
	HQ shell and its interior, every wading band, the coin road the player actually
	walks) is written against y = 0, and the whole point of Task 2 is that those
	consumers migrate by NOT migrating.

	EACH LEG CARRIES ITS OWN NEGATIVE CONTROL, one full skirt plus
	FLAT_CONTROL_MARGIN outside the zone, where SOMETHING must be non-zero. Without
	it a mask that returned 0.0 everywhere — or a height function that never got
	past the flag — would pass every positive leg and prove nothing.
	"""
	for seed_value: int in SEEDS:
		var t := _make_terrain(seed_value)
		t.alt_force = true
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value

		# --- ZONE 1: BUDAPEST -------------------------------------------------
		var city: Rect2 = BudapestPlan.rect()
		var inside: Array[Vector2] = []
		for i in FLAT_SAMPLES:
			inside.append(Vector2(
					rng.randf_range(city.position.x, city.end.x),
					rng.randf_range(city.position.y, city.end.y)))
		_assert_flat(t, seed_value, "budapest", inside)
		# Control: due west of the rect, past the skirt. West because that is the
		# side the player walks in from, so it is the ramp anyone would ever see.
		var city_out: Array[Vector2] = []
		for i in FLAT_SAMPLES:
			city_out.append(Vector2(
					city.position.x - t.ALT_CITY_SKIRT - rng.randf_range(1.0, FLAT_CONTROL_MARGIN),
					rng.randf_range(city.position.y, city.end.y)))
		_assert_alive(t, seed_value, "budapest", city_out)

		# --- ZONE 2: THE HQ DISC ----------------------------------------------
		var site: Vector3 = t.tower_site()
		var centre := Vector2(site.x, site.z)
		var disc: Array[Vector2] = []
		for i in FLAT_SAMPLES:
			# sqrt on the radius so the samples are uniform over the AREA and do
			# not pile up at the middle, where any mask is trivially zero.
			var r: float = sqrt(rng.randf()) * t.TOWER_RADIUS
			var a: float = rng.randf_range(0.0, TAU)
			disc.append(centre + Vector2(cos(a), sin(a)) * r)
		_assert_flat(t, seed_value, "hq disc", disc)
		var disc_out: Array[Vector2] = []
		for i in FLAT_SAMPLES:
			var r2: float = t.TOWER_RADIUS + t.ALT_TOWER_SKIRT + rng.randf_range(1.0, FLAT_CONTROL_MARGIN)
			var a2: float = rng.randf_range(0.0, TAU)
			disc_out.append(centre + Vector2(cos(a2), sin(a2)) * r2)
		_assert_alive(t, seed_value, "hq disc", disc_out)

		# --- ZONE 3: EVERY RIVER BAND -----------------------------------------
		# The band is a level set of the biome field, so it cannot be enumerated —
		# it is FOUND, by rejection sampling the same box the other checks use.
		var wet: Array[Vector2] = []
		var dry: Array[Vector2] = []
		var tries := 0
		while (wet.size() < FLAT_SAMPLES or dry.size() < FLAT_SAMPLES) and tries < 400000:
			tries += 1
			var q := Vector2(rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF),
					rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF))
			var offset: float = absf(t._biome_noise(q.x, q.y) - t.RIVER_LEVEL)
			if offset < t.RIVER_HALF_WIDTH and wet.size() < FLAT_SAMPLES:
				wet.append(q)
			elif offset > t.RIVER_HALF_WIDTH * t.ALT_RIVER_SKIRT_K * 2.0 and dry.size() < FLAT_SAMPLES:
				dry.append(q)
		if wet.size() < FLAT_SAMPLES:
			_fail("seed %d: only found %d/%d river-band points in %d tries — the sampler, not the mask" % [
				seed_value, wet.size(), FLAT_SAMPLES, tries])
		_assert_flat(t, seed_value, "river band", wet)
		_assert_alive(t, seed_value, "river band", dry)

		# --- ZONE 4: THE COIN ROAD CORRIDOR -----------------------------------
		# Walked as the curve it is: FLAT_ROAD_STATIONS stations either side of the
		# origin, every one of them a centre the player really walks over, plus a
		# lateral offset. Stations only at or west of the terminal — CAP 5 OF THE
		# ROAD'S CONSUMERS (bead godot-test1-8gw.3): east of T there is no road, and
		# the approach corridor that carries the walk on from there is inside
		# Budapest's rect and already flat by zone 1.
		#
		# THE SHIPPED REFRESH SEAM IS DRIVEN, not bypassed: the corridor is measured
		# against the COARSE polyline _alt_road_refresh() caches on a chunk-boundary
		# crossing, so a check that sampled height_at() without it would be asserting
		# against an empty window (INF distance, no corridor at all) and would pass
		# for the wrong reason. Centred on the origin, which the ±240 m of stations
		# below sit well inside of ALT_ROAD_WINDOW from.
		t._alt_road_refresh(0.0)
		var terminal: int = t._road_terminal_k()
		var on_road: Array[Vector2] = []
		var off_road: Array[Vector2] = []
		# The polyline is a CHORD across ALT_ROAD_SEG_STRIDE stations, so a fine
		# station can sit up to ALT_ROAD_SEG_DEV_MAX off it (asserted below). The
		# flat strip a sample is guaranteed to be inside is therefore the flat half
		# LESS that deviation — the honest promise the corridor makes, and shrinking
		# the offset is how this leg keeps asking for EXACTLY 0.0 rather than for a
		# tolerance.
		var lateral: float = t.ALT_ROAD_FLAT_HALF - t.ALT_ROAD_SEG_DEV_MAX
		var worst_dev := 0.0
		for i in FLAT_ROAD_STATIONS * 2 + 1:
			var k: int = mini(i - FLAT_ROAD_STATIONS, terminal)
			t._road_extend_to_x(-SAMPLE_HALF, SAMPLE_HALF)
			var st: Dictionary = t._road_station(k)
			var c: Vector2 = st.center
			# THE CHORD DEVIATION ITSELF, measured on the shipped cache: this is what
			# binds ALT_ROAD_SEG_STRIDE to ALT_ROAD_FLAT_HALF, and without it raising
			# the stride would quietly walk the coin road onto a hill while every
			# other leg of this check still passed.
			worst_dev = maxf(worst_dev, t._alt_road_distance(c.x, c.y))
			var n := Vector2(-sin(st.heading), cos(st.heading))  # the road's normal
			for j in 8:
				on_road.append(c + n * rng.randf_range(-1.0, 1.0) * lateral)
				var side: float = 1.0 if j % 2 == 0 else -1.0
				off_road.append(c + n * side * (t.ALT_ROAD_FLAT_HALF + t.ALT_ROAD_SKIRT
						+ t.ALT_ROAD_SEG_DEV_MAX + rng.randf_range(1.0, FLAT_CONTROL_MARGIN)))
		if worst_dev > t.ALT_ROAD_SEG_DEV_MAX:
			_fail("seed %d: a road station sits %.2f m off the coarse polyline, over ALT_ROAD_SEG_DEV_MAX %.1f — lower ALT_ROAD_SEG_STRIDE or the coin road is on a hill" % [
				seed_value, worst_dev, t.ALT_ROAD_SEG_DEV_MAX])
		# The measured deviation is a REPORT number as well as an assertion — it is
		# what says how coarse the polyline is allowed to get.
		print("[altitude] seed %d: worst road-station offset from the coarse polyline %.2f m (bound %.1f m, %d segments)" % [
			seed_value, worst_dev, t.ALT_ROAD_SEG_DEV_MAX, t._alt_road_segs.size()])
		_assert_flat(t, seed_value, "road corridor", on_road)
		_assert_alive(t, seed_value, "road corridor", off_road)

		t.free()
	Sentinel.done("flat_zones")


func _check_shader_parity() -> void:
	"""
	Check 4. THE SHADER IS FED WHAT IT DECLARES — budapest_selfcheck's
	_check_parity / _check_parity_packing idiom over the `alt_*` block.

	Check 2 re-derives the field from the GLSL TEXT and proves the CPU port
	computes it. What it cannot see is the wiring: a uniform ground.gdshader
	declares that _apply_biome_shader_params never pushes keeps the shader's own
	default silently — so the ground the player SEES is a different field from the
	one the collision heightmap is sampled off, with no error anywhere. The reverse
	(a push the GLSL never declares) is discarded just as silently.

	Three legs:

	  a. BOTH DIRECTIONS, on the COMPILED uniform list. Declarations come from
	     `Shader.get_shader_uniform_list()` rather than a text scan, which also
	     means this check fails on a shader that does not compile; the pushes come
	     from endless_terrain.gd's source, because a push is a call site and there
	     is no registry of them to read.
	  b. THE VALUES, derived rather than listed. A pushed `alt_foo` whose
	     UPPER-CASED name is a constant of endless_terrain.gd must equal it — so
	     the naming convention IS the contract and a uniform added tomorrow is
	     covered the day it lands. The three that cannot follow it are named
	     explicitly below and each says why.
	  c. THE PACKING, read back OFF THE MATERIAL. A text scan cannot see that
	     `alt_road_seg[i]` is pushed as (x1, z1, x2, z2) and not (x, z, dx, dz) —
	     the second is a plausible line, it type-checks, and it turns the corridor
	     into a fan of segments radiating from the origin while every other leg of
	     this file still passes.
	"""
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		_fail("could not load %s — the shader half of the altitude parity contract measured nothing (a GLSL error here is a compile failure, not a missing file)" % SHADER_PATH)
		Sentinel.done("shader_parity")
		return
	var declared: Dictionary = {}
	for entry_variant: Variant in shader.get_shader_uniform_list():
		var entry: Dictionary = entry_variant
		var uniform_name := String(entry["name"])
		if uniform_name.begins_with("alt_"):
			declared[uniform_name] = true
	# The vacuity control (prop_selfcheck's ABSENT_UNIFORM): a declared-uniform
	# read that answers "yes" to everything, or to nothing, would pass leg (a)
	# while measuring nothing at all.
	if declared.is_empty() or declared.has(ABSENT_ALT_UNIFORM):
		_fail("the shader's declared alt_* uniform list is not trustworthy (%d entries, has %s: %s) — check 4 would pass vacuously" % [
			declared.size(), ABSENT_ALT_UNIFORM, declared.has(ABSENT_ALT_UNIFORM)])
		Sentinel.done("shader_parity")
		return

	var terrain_text := FileAccess.get_file_as_string(TERRAIN_SCRIPT)
	var pushed: Dictionary = {}
	var push_re := RegEx.new()
	push_re.compile("set_shader_parameter\\(\"(alt_\\w+)\"")
	for m: RegExMatch in push_re.search_all(terrain_text):
		pushed[m.get_string(1)] = true

	# ---- a. both directions --------------------------------------------------
	for uniform_name: String in declared.keys():
		if not pushed.has(uniform_name):
			_fail("ground.gdshader declares '%s' but endless_terrain.gd never pushes it — the GPU keeps its own default and draws a DIFFERENT heightfield from the one the collision shape is sampled off" % uniform_name)
	for uniform_name: String in pushed.keys():
		if not declared.has(uniform_name):
			_fail("endless_terrain.gd pushes '%s' but ground.gdshader declares no such uniform — the value is silently discarded" % uniform_name)

	# The shader's array bound is a number written down in two languages, because a
	# GLSL array uniform is a fixed size. Only ">=" matters: a shader array bigger
	# than the polyline wastes a few registers, one smaller is a count past the end
	# of the array, which is an undefined read in GLSL ES 3.00.
	var shader_text := FileAccess.get_file_as_string(SHADER_PATH)
	var gpu_seg_max := _shader_int(shader_text, "ALT_ROAD_SEG_MAX")
	var probe := _make_terrain(SEEDS[0])
	if gpu_seg_max < probe.ALT_ROAD_SEG_MAX:
		_fail("ground.gdshader's ALT_ROAD_SEG_MAX is %d against the GDScript's %d — the road corridor would lose its far segments on the GPU while the CPU still flattens them" % [
			gpu_seg_max, probe.ALT_ROAD_SEG_MAX])
	probe.free()

	# ---- b + c. drive the SHIPPED push and read it back ----------------------
	# _ready() returns at its "no player" guard long before it builds the default
	# ground material, so the harness stands one up exactly as _ready would — the
	# PUSH itself is still _apply_biome_shader_params, here and in the game.
	var t := _make_terrain(SEEDS[0])
	t.alt_force = true
	var mat := ShaderMaterial.new()
	mat.shader = shader
	t.terrain_material = mat
	# The road window first: _alt_road_refresh is the shipped seam update_chunks
	# runs on a chunk-boundary crossing, and it re-pushes the material itself, so a
	# check that skipped it would be reading back an EMPTY array and would pass for
	# the wrong reason.
	t._alt_road_refresh(0.0)
	t._apply_biome_shader_params()

	# The gate, both ways round: forced on here, and off for the world.
	if float(mat.get_shader_parameter("alt_enabled")) != 1.0:
		_fail("alt_enabled was pushed as %s with the spike forced on — the GPU would draw the flat world under a displaced collision shape" % str(mat.get_shader_parameter("alt_enabled")))
	t.alt_force = false
	t._apply_biome_shader_params()
	if float(mat.get_shader_parameter("alt_enabled")) != 0.0:
		_fail("alt_enabled was pushed as %s with the spike OFF — the merge condition is that the flag-off world is byte for byte flat" % str(mat.get_shader_parameter("alt_enabled")))
	t.alt_force = true
	t._alt_road_refresh(0.0)
	t._apply_biome_shader_params()

	# ---- b. every pushed value equals the constant it is named after ---------
	var consts: Dictionary = (load(TERRAIN_SCRIPT) as GDScript).get_script_constant_map()
	var value_checked := 0
	for uniform_name: String in pushed.keys():
		# The three that cannot follow the naming convention, each for its own
		# reason: the gate is a FUNCTION (alt_enabled(), so the self-check seam
		# works) and is asserted above; the domain shift is ALT_OFFSET_SALT, named
		# for what it is rather than for the uniform; and the road array is data,
		# asserted by leg (c) below.
		if uniform_name in ["alt_enabled", "alt_offset", "alt_road_seg", "alt_road_seg_count"]:
			continue
		var const_name := uniform_name.to_upper()
		if not consts.has(const_name):
			_fail("uniform '%s' has no endless_terrain.gd constant %s — either name it after the constant it carries or add it to check 4's three named exceptions with a reason" % [
				uniform_name, const_name])
			continue
		var got: Variant = mat.get_shader_parameter(uniform_name)
		if got == null:
			_fail("_apply_biome_shader_params never pushed '%s' — the shader silently keeps its own default for it" % uniform_name)
			continue
		var want: Variant = consts[const_name]
		var delta := 0.0
		if got is Vector2:
			delta = (got as Vector2).distance_to(want as Vector2)
		else:
			delta = absf(float(got) - float(want))
		if delta > 1e-6:
			_fail("uniform '%s' was pushed as %s but %s is %s — the hill the player SEES is not the hill they STAND on" % [
				uniform_name, str(got), const_name, str(want)])
		value_checked += 1
	# ALT_OFFSET_SALT by hand, since it is one of the three exceptions and is the
	# one that would silently move every hill in the world.
	if (mat.get_shader_parameter("alt_offset") as Vector2).distance_to(t.ALT_OFFSET_SALT) > 1e-6:
		_fail("alt_offset was pushed as %s, not ALT_OFFSET_SALT %s — the GPU's altitude field would be domain-shifted away from the CPU's" % [
			str(mat.get_shader_parameter("alt_offset")), str(t.ALT_OFFSET_SALT)])

	# ---- c. the road array's packing ----------------------------------------
	var segs: PackedVector4Array = mat.get_shader_parameter("alt_road_seg")
	var seg_count: int = mat.get_shader_parameter("alt_road_seg_count")
	if segs.size() != t.ALT_ROAD_SEG_MAX:
		_fail("alt_road_seg was pushed with %d entries against ALT_ROAD_SEG_MAX %d — a GLSL array uniform is a fixed size and a short push leaves the tail undefined" % [
			segs.size(), t.ALT_ROAD_SEG_MAX])
	if seg_count <= 0 or seg_count != t._alt_road_segs.size():
		_fail("alt_road_seg_count is %d against the CPU cache's %d — the GPU and the collision heightmap would flatten two different corridors" % [
			seg_count, t._alt_road_segs.size()])
	# EVERY ENDPOINT MUST BE A REAL STATION CENTRE. That is what distinguishes the
	# shipped (x1, z1, x2, z2) from the plausible (x, z, dx, dz): the second packs a
	# DELTA into zw, which is a few tens of metres from the origin and is a station
	# centre nowhere on the road. The station set is built independently here, off
	# _road_station over a range wide enough to contain any window.
	t._road_extend_to_x(-SAMPLE_HALF, SAMPLE_HALF)
	var centres: Dictionary = {}
	var k_centre: int = t._road_first_k_at_or_after_x(0.0)
	for k in range(k_centre - 400, k_centre + 400):
		var c: Vector2 = t._road_station(k).center
		centres["%.2f|%.2f" % [c.x, c.y]] = true
	for i in seg_count:
		var seg: Vector4 = segs[i]
		for end_point: Vector2 in [Vector2(seg.x, seg.y), Vector2(seg.z, seg.w)]:
			if not centres.has("%.2f|%.2f" % [end_point.x, end_point.y]):
				_fail("alt_road_seg[%d] has an endpoint at (%.2f, %.2f) that is no road station centre — the array is not packed (x1, z1, x2, z2)" % [
					i, end_point.x, end_point.y])
				break
		# AND THE POLYLINE IS A CHAIN. Segment i's far end is segment i+1's near
		# end: a walk that packed each segment from the same anchor, or reversed
		# one, satisfies the endpoint test above and still draws a fan.
		if i + 1 < seg_count:
			var next_seg: Vector4 = segs[i + 1]
			if Vector2(seg.z, seg.w).distance_to(Vector2(next_seg.x, next_seg.y)) > SEG_ENDPOINT_EPSILON:
				_fail("alt_road_seg[%d] ends at (%.2f, %.2f) but [%d] starts at (%.2f, %.2f) — the corridor is a fan of disconnected chords, not the road" % [
					i, seg.z, seg.w, i + 1, next_seg.x, next_seg.y])
				break

	print("[altitude] shader parity: %d alt_* uniforms declared and pushed (%d value-checked), array %d >= %d, %d road segments packed and chained" % [
		declared.size(), value_checked, gpu_seg_max, t.ALT_ROAD_SEG_MAX, seg_count])
	t.free()
	Sentinel.done("shader_parity")


func _shader_int(shader: String, name: String) -> int:
	"""
	The value of a `const int NAME = n;` line in the shader, or -1 —
	budapest_selfcheck._shader_int verbatim, and the same one-number-in-two-
	languages problem it was written for.
	"""
	for line in shader.split("\n"):
		if not line.contains(name) or not line.contains("="):
			continue
		var tail := line.split("=")[1].strip_edges().replace(";", "")
		if tail.is_valid_int():
			return tail.to_int()
	return -1


func _assert_flat(t: Node3D, seed_value: int, zone: String, points: Array[Vector2]) -> void:
	"""Every one of `points` must read exactly 0.0 — the positive leg of check 3."""
	for q: Vector2 in points:
		var h: float = t.height_at(q.x, q.y)
		if h != 0.0:
			_fail("seed %d: %s is not flat — height_at(%.1f, %.1f) = %.6f m (the mask, not the check)" % [
				seed_value, zone, q.x, q.y, h])
			return


func _assert_alive(t: Node3D, seed_value: int, zone: String, points: Array[Vector2]) -> void:
	"""
	SOMETHING outside the zone must be non-zero — the negative control.

	Deliberately "at least one" and not "most": a control point one skirt out can
	legitimately land in ANOTHER zone (the road crosses rivers, the HQ sits west of
	the city), and the claim being tested is only that the mask is not stuck at
	zero.
	"""
	for q: Vector2 in points:
		if t.height_at(q.x, q.y) != 0.0:
			return
	_fail("seed %d: NOTHING outside the %s zone has any altitude across %d control points — the mask is flattening the whole world (negative control failed)" % [
		seed_value, zone, points.size()])


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
