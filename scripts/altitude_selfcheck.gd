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
##   5. THE FLOOR IS THE FIELD. `_ensure_chunk_ground` builds a HeightMapShape3D
##      on the visual mesh's OWN vertex grid (READ OFF THE MESH, never re-derived
##      — a re-derivation is how the builder's wrong grid formula went unnoticed)
##      with the flag on and today's
##      BoxShape3D with it off, and the stored samples times the shape's uniform
##      scale are height_at() to the millimetre — the ground you stand on and the
##      ground the vertex shader drew are the same surface. Check 5, which also
##      PRINTS the per-chunk build cost, because that build lands inside
##      update_chunks' synchronous safety-ring path and the microseconds are a
##      report deliverable rather than a budget anybody has measured yet.
##   6. THE FIELD IS WALKABLE. The gradient magnitude over a one-metre step stays
##      under 45 degrees everywhere, so the heightfield is terrain and not scenery
##      you slide off — and the mountain band's own worst slope is printed beside
##      the jump apex, because MOUNTAIN IMPASSABILITY is the flat-world consumer
##      with the most to lose and the report has to reason about it with numbers.
##      Check 6.
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

## How many road stations either side of the origin check 3 SAMPLES FOR FLATNESS.
## The corridor is a curve, so sampling it means sampling the ROAD rather than a box
## around it. It is not the range the chord deviation is measured over — that one is
## derived from ALT_ROAD_SEG_MAX / ALT_ROAD_SEG_STRIDE in the check itself, because
## the bound has to hold at the window's outermost nodes and not only where the
## player is standing.
const FLAT_ROAD_STATIONS: int = 40

## Check 3's window-slide leg: how many coarse nodes it plants ramp probes on, and
## how many chunk-boundary crossings it walks them past. 30 nodes is ~1.4 km of
## road, comfortably wider than the 20 x 50 m walk, so every probe spends a stretch
## of the walk inside the residency where the assertion bites.
const WINDOW_PROBE_STATIONS: int = 30
const WINDOW_PROBE_STEPS: int = 20

## Check 6's road-skirt leg: offsets across the road corridor's 40 m ramp, from the
## flat edge to the open field. 9 is enough to straddle the smoothstep's steepest
## middle on both banks of every walked station.
const SKIRT_PROBE_STEPS: int = 9

## Check 6's RIVER-skirt leg. The river skirt is the tightest of the four and it is
## the only one whose width is not a constant: clause 3 ramps in FIELD units, from
## RIVER_HALF_WIDTH to RIVER_HALF_WIDTH * ALT_RIVER_SKIRT_K, so its width in metres
## is that 0.0175 of biome field divided by the LOCAL |grad _biome_noise| — about
## 5-10 m against the road's authored 40, carrying the full plains amplitude to
## zero across it. So it cannot be walked like the road (there is no polyline) and
## the uniform box under-samples its tail: ~5.5% of the box lands in the band, so
## 20,000 uniform points give it ~1,100 and find 0.59 where 10,000 hits find 0.82.
## Rejection-sampled to a HIT count, with an attempt cap so a field that stopped
## producing rivers fails loudly instead of spinning.
const RIVER_SKIRT_HITS: int = 10000
const RIVER_SKIRT_MAX_ATTEMPTS: int = 400000

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

## `player_controller.gd`, for check 6's jump apex. The apex is RECOMPUTED off
## JUMP_VELOCITY and gravity rather than restated — tower_interior_selfcheck's
## _jump_apex verbatim, and for the same reason: the number is only meaningful in
## the report if it still tracks the jump anyone actually retunes.
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"

## The chunks check 5 grounds. Nine of them, deliberately spread: (0, 0) and its
## neighbours sit inside the refreshed road window (so the corridor clause is
## live in the sampled heights), the far ones do not, and one lands on the HQ
## disc — three different mask regimes through one code path.
const GROUND_CHUNKS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1),
	Vector2i(-8, 0), Vector2i(40, 17), Vector2i(-33, -26), Vector2i(7, -19),
	Vector2i(2, 60),
]

## Tolerance on a heightmap sample, in metres. Two sources, both bounded and both
## far below anything a player could stand on: the stored value is an f32 (a
## PackedFloat32Array is the shape's storage) of a height under ~25 m, so ~1e-6;
## and the sample POSITION is now the PlaneMesh's own f32 vertex coordinate while
## the builder walks the same grid in f64, so the two evaluate height_at() at
## points up to an f32 ulp apart on a field whose steepest slope is ~0.8 m/m.
## MEASURED worst 1.1e-4 m across the nine chunks (it was 4.8e-7 while this check
## re-derived the builder's own f64 positions and therefore could not see a wrong
## grid at all — see the note over the grid read in check 5). A millimetre keeps a
## 9x margin over that and is still two orders under a visible seam.
const HEIGHTMAP_EPSILON: float = 1e-3

## Check 6's sample count per seed, and the step it measures the slope over. ONE
## METRE because that is the unit the claim is made in ("height delta per metre")
## and it is the scale a CharacterBody3D's floor test works at; 20,000 points over
## the +/- 5 km box hits every band of the amplitude ladder thousands of times.
const WALK_SAMPLES: int = 20000
const WALK_STEP: float = 1.0

## The slope the field may not exceed, in metres per metre. 1.0 is 45 degrees —
## Godot's own default floor_max_angle is 45 degrees, so a steeper face is a wall
## the player slides off rather than ground they walk up, and a field that grew
## one would be handing the mountain massifs a ramp round the side.
const MAX_WALKABLE_SLOPE: float = 1.0

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
	_check_ground_collision()
	_check_field_is_walkable()
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

	# NOBODY IN THE GAME MAY WRITE alt_force. Reading the default back off a fresh
	# node (above) cannot see a writer anywhere in scripts/ — and alt_force is a
	# plain public var whose whole contract, stated in its own docstring and in
	# alt_enabled()'s, is that only a self-check ever assigns it. pause_selfcheck
	# scans the same glob for `tree.paused` writers for the same reason: an
	# invariant a source scan can settle should not be left to review.
	var writer_re := RegEx.new()
	if writer_re.compile("alt_force\\s*=[^=]") != OK:
		_fail("the alt_force-writer regex would not compile — check 1's source scan would pass vacuously")
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		_fail("could not open res://scripts — check 1's source scan would pass vacuously")
		Sentinel.done("flag_is_off")
		return
	var names: PackedStringArray = dir.get_files()
	if names.size() < 20:
		_fail("res://scripts listed only %d files — check 1's source scan would pass vacuously" % names.size())
	for name: String in names:
		if not name.ends_with(".gd") or name.ends_with("_selfcheck.gd"):
			continue  # the seam exists FOR the checks; they are the sanctioned writers
		var source: String = FileAccess.get_file_as_string("res://scripts/" + name)
		if writer_re.search(source) != null:
			_fail("scripts/%s assigns alt_force — it is the self-check seam alone, and a game script writing it turns the spike on for players while the shipped FIELD_ALTITUDE is still false" % name)

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
		# below sit well inside of _alt_road_window() from.
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
		# Once, not per station: the arguments never change and growing the cache is
		# the expensive part of this leg.
		t._road_extend_to_x(-SAMPLE_HALF, SAMPLE_HALF)
		# THE CHORD DEVIATION ITSELF, measured on the shipped cache over the WHOLE
		# window and not just the stretch the flat sampling below walks. This is what
		# binds ALT_ROAD_SEG_STRIDE to ALT_ROAD_FLAT_HALF, and without it raising the
		# stride would quietly walk the coin road onto a hill while every other leg of
		# this check still passed — so the walked range is DERIVED from the corridor's
		# own constants (`half * stride` stations either side is exactly the node span
		# _alt_road_segments builds), never a literal of its own. A separate loop
		# because the flat/alive sampling is the expensive half and only has to prove
		# the promise where the player is; the bound has to hold at every node the
		# shader and the baked heightmap read, including the outermost pair.
		var dev_stations: int = t.ALT_ROAD_SEG_MAX / 2 * t.ALT_ROAD_SEG_STRIDE
		var worst_dev := 0.0
		for i in dev_stations * 2 + 1:
			var kd: int = mini(i - dev_stations, terminal)
			var cd: Vector2 = t._road_station(kd).center
			worst_dev = maxf(worst_dev, t._alt_road_distance(cd.x, cd.y))
		for i in FLAT_ROAD_STATIONS * 2 + 1:
			var k: int = mini(i - FLAT_ROAD_STATIONS, terminal)
			var st: Dictionary = t._road_station(k)
			var c: Vector2 = st.center
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
		print("[altitude] seed %d: worst road-station offset from the coarse polyline %.2f m over +/-%d stations (bound %.1f m, %d segments)" % [
			seed_value, worst_dev, dev_stations, t.ALT_ROAD_SEG_DEV_MAX, t._alt_road_segs.size()])
		_assert_flat(t, seed_value, "road corridor", on_road)
		_assert_alive(t, seed_value, "road corridor", off_road)

		# THE WINDOW MAY SLIDE; THE CORRIDOR MAY NOT. A chunk's collision
		# HeightMapShape3D is baked ONCE off height_at() and never rebuilt, while
		# the shader re-evaluates the corridor live off the last-pushed window. So
		# height_at() at a FIXED world point has to answer the same metre whichever
		# nearby centre the window was built from, or the floor drifts away from the
		# surface drawn over it while the player walks. Before the stride-lattice
		# snap in _alt_road_segments this measured 2.19 m along the coin road — the
		# spike's own control — and nothing here could see it.
		#
		# Walked in chunk_size steps because update_chunks refreshes the window on a
		# chunk-boundary crossing, and sampled only inside the ground that is
		# actually loaded and therefore baked — the desktop residency half-width.
		#
		# ...CAPPED BY WHAT THE WINDOW REALLY REACHES, which is not the residency.
		# The window is ALT_ROAD_SEG_MAX segments in STATIONS, and a curving stretch
		# advances as little as 1.25 m of X per station (the `ponytail:` ceiling on
		# clause 4 of _alt_flat_mask), so a probe can sit inside 250 m and still fall
		# off the polyline's end — where _alt_road_distance answers INF from one
		# window and a real distance from the next. That is the DOCUMENTED ceiling,
		# not the lattice-snap bug this leg exists to catch, so it must not be
		# measured here; the cap is taken from the shipped cache below, per window.
		var residency: float = float(t.render_distance) * t.chunk_size
		var probe_pts: Array[Vector2] = []
		for i in WINDOW_PROBE_STATIONS:
			var st_p: Dictionary = t._road_station(i * t.ALT_ROAD_SEG_STRIDE)
			var c_p: Vector2 = st_p.center
			var n_p := Vector2(-sin(st_p.heading), cos(st_p.heading))
			# Off the centreline and inside the skirt: on the RAMP, where the
			# corridor distance actually moves the height. A point on the centreline
			# is 0.0 from every window and would pass vacuously.
			probe_pts.append(c_p + n_p * (t.ALT_ROAD_FLAT_HALF + t.ALT_ROAD_SKIRT * 0.5))
		var worst_slide := 0.0
		var slide_at := Vector2.ZERO
		var slide_compared := 0
		var base_center: float = probe_pts[0].x
		for step in WINDOW_PROBE_STEPS:
			var cx: float = base_center + float(step) * t.chunk_size
			t._alt_road_refresh(cx)
			var reach: float = minf(residency, _alt_window_reach(t, cx))
			var heights: Array[float] = []
			for q: Vector2 in probe_pts:
				heights.append(t.height_at(q.x, q.y))
			t._alt_road_refresh(cx + t.chunk_size)
			reach = minf(reach, _alt_window_reach(t, cx))
			for j in probe_pts.size():
				var q2: Vector2 = probe_pts[j]
				if absf(q2.x - cx) > reach:
					continue
				slide_compared += 1
				var slide: float = absf(heights[j] - t.height_at(q2.x, q2.y))
				if slide > worst_slide:
					worst_slide = slide
					slide_at = q2
		if slide_compared == 0:
			_fail("seed %d: the window-slide leg compared no probe at all — every one fell outside both windows' X reach, so the lattice snap is unmeasured" % seed_value)
		if worst_slide > HEIGHT_EPSILON:
			_fail("seed %d: height_at%s moved %.4f m when the road window slid one chunk — the corridor's chord nodes are not snapped to the stride lattice, so a chunk's baked floor no longer matches the surface the shader draws over it" % [
				seed_value, str(slide_at), worst_slide])
		t._alt_road_refresh(0.0)

		t.free()
	Sentinel.done("flat_zones")


func _alt_window_reach(t: Node, center_x: float) -> float:
	"""
	How far in X the CURRENTLY CACHED corridor window actually reaches either side
	of `center_x`.

	@param t: The terrain, with _alt_road_segs already refreshed.
	@param center_x: The X the window was refreshed around.
	@return: Metres, the SMALLER of the two ends' reach. 0.0 for an empty cache.

	The window is ALT_ROAD_SEG_MAX segments in STATIONS, and a station advances as
	little as 1.25 m of X on a stretch at the 78-degree heading cap, so the X reach
	is a property of the road's shape and cannot be written down. Measured off the
	polyline the shipped code just built, which is the only honest answer.
	"""
	var segs: PackedVector4Array = t._alt_road_segs
	if segs.is_empty():
		return 0.0
	var west: float = segs[0].x
	var east: float = segs[segs.size() - 1].z
	return maxf(0.0, minf(center_x - west, east - center_x))


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
	# Off the constant map, not off a terrain node stood up to read one const.
	var consts: Dictionary = (load(TERRAIN_SCRIPT) as GDScript).get_script_constant_map()
	var cpu_seg_max: int = consts["ALT_ROAD_SEG_MAX"]
	if gpu_seg_max < cpu_seg_max:
		_fail("ground.gdshader's ALT_ROAD_SEG_MAX is %d against the GDScript's %d — the road corridor would lose its far segments on the GPU while the CPU still flattens them" % [
			gpu_seg_max, cpu_seg_max])

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
	# ---- b'. every DECLARED DEFAULT equals the constant it is named after -----
	# The shader's own header claims "Every default below equals the GDScript
	# constant of the same name … a shader loaded by a check that never ran
	# _apply_biome_shader_params still computes the shipped field". Leg (b) only
	# measures the value PUSHED, so without this a retuned ALT_CELL_SIZE leaves
	# `uniform float alt_cell_size = 260.0;` stale and the editor preview — and any
	# future check that loads the shader without the terrain — draws a field nobody
	# ships. Only the array uniforms are exempt (a GLSL array default carries no
	# meaningful value); BOTH SHAPES ARE PARSED, float and vec2, because the
	# float-only version of this leg could not see either vec2 — and alt_offset,
	# the one uniform that moves every hill in the world at once, was declared
	# vec2(0.0) against ALT_OFFSET_SALT (37, 71) with nothing red.
	var default_re := RegEx.new()
	default_re.compile("uniform\\s+float\\s+(alt_\\w+)\\s*=\\s*([-0-9.]+)\\s*;")
	var default_vec2_re := RegEx.new()
	default_vec2_re.compile("uniform\\s+vec2\\s+(alt_\\w+)\\s*=\\s*vec2\\(([^)]*)\\)\\s*;")
	var defaults_checked := 0
	var default_seen: Dictionary = {}
	for m: RegExMatch in default_re.search_all(shader_text):
		var uniform_name := m.get_string(1)
		default_seen[uniform_name] = true
		if uniform_name == "alt_enabled":
			continue  # the gate; its 0.0 default IS the inert-default idiom
		var const_name := uniform_name.to_upper()
		if not consts.has(const_name):
			continue  # leg (b) already failed this one by name
		if absf(m.get_string(2).to_float() - float(consts[const_name])) > 1e-6:
			_fail("ground.gdshader declares '%s = %s' but %s is %s — the shader's own header promises they are equal, and a material nobody fed draws a field nobody ships" % [
				uniform_name, m.get_string(2), const_name, str(consts[const_name])])
		defaults_checked += 1
	var vec2_defaults_checked := 0
	for m: RegExMatch in default_vec2_re.search_all(shader_text):
		var uniform_name := m.get_string(1)
		default_seen[uniform_name] = true
		var const_name := uniform_name.to_upper()
		if uniform_name == "alt_offset":
			const_name = "ALT_OFFSET_SALT"  # the one uniform not named after its const
		if not consts.has(const_name):
			continue  # leg (b) already failed this one by name
		# `vec2(a)` is GLSL's splat, so one argument means both components.
		var parts := m.get_string(2).split(",", false)
		var declared_default := Vector2.ZERO
		if parts.size() == 1:
			declared_default = Vector2.ONE * parts[0].strip_edges().to_float()
		elif parts.size() == 2:
			declared_default = Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
		else:
			_fail("ground.gdshader declares '%s = vec2(%s)' — neither the splat nor the two-component form, so check 4 cannot read its default" % [
				uniform_name, m.get_string(2)])
		if declared_default.distance_to(consts[const_name] as Vector2) > 1e-6:
			_fail("ground.gdshader declares '%s = %s' but %s is %s — the shader's own header promises they are equal, and a material nobody fed draws a field nobody ships" % [
				uniform_name, str(declared_default), const_name, str(consts[const_name])])
		vec2_defaults_checked += 1
	if defaults_checked == 0 or vec2_defaults_checked == 0:
		_fail("check 4 parsed %d float and %d vec2 alt_* uniform defaults out of ground.gdshader — the declared-default leg passed vacuously" % [
			defaults_checked, vec2_defaults_checked])
	# THE EXPECTATION IS THE DECLARED SET, NOT THE REGEX HITS. Both patterns above
	# require an `= <literal>`, so `uniform float alt_foo;` — legal GLSL, defaulted
	# to 0.0 by the compiler — matched neither, was never compared to anything, and
	# the two non-vacuity counters above still passed on its siblings. That is
	# exactly the uniform the header's promise is about: the one an editor preview
	# or a check that never ran _apply_biome_shader_params draws a dead field from.
	# The array is exempt (a GLSL array default carries no meaningful value) and so
	# is its count, which leg (c) asserts against the cache instead.
	for uniform_name: String in declared.keys():
		if uniform_name in ["alt_road_seg", "alt_road_seg_count"]:
			continue
		if not default_seen.has(uniform_name):
			_fail("ground.gdshader declares '%s' with no literal default — GLSL gives it 0.0, so a material nobody fed draws a field nobody ships, and check 4's default leg cannot see it at all" % uniform_name)

	# ALT_OFFSET_SALT's PUSHED value by hand, since it is the one uniform not named
	# after the constant it carries and so leg (b) skips it.
	if (mat.get_shader_parameter("alt_offset") as Vector2).distance_to(t.ALT_OFFSET_SALT) > 1e-6:
		_fail("alt_offset was pushed as %s, not ALT_OFFSET_SALT %s — the GPU's altitude field would be domain-shifted away from the CPU's" % [
			str(mat.get_shader_parameter("alt_offset")), str(t.ALT_OFFSET_SALT)])

	# ---- c. the road array's packing ----------------------------------------
	var segs: PackedVector4Array = mat.get_shader_parameter("alt_road_seg")
	var seg_count: int = mat.get_shader_parameter("alt_road_seg_count")
	# THE CLAMP IS THE ONLY THING HERE THAT CAN HIDE A BUG, so it is the only thing
	# worth asserting. `segs.size() == ALT_ROAD_SEG_MAX` and `seg_count ==
	# _alt_road_segs.size()` are both true BY CONSTRUCTION —
	# _alt_road_seg_uniform() resizes to the constant on its first statement and
	# _alt_road_segments' build loop already caps the cache at it — so the pair of
	# comparisons this leg used to make were values against themselves. What is not
	# guaranteed is that the cache FITS: _apply_biome_shader_params pushes
	# mini(cache, MAX), so a polyline that outgrew the GLSL array is silently
	# TRUNCATED on the GPU while _alt_road_distance() still walks all of it on the
	# CPU — the GPU and the collision heightmap flattening two different corridors,
	# with no error anywhere.
	if t._alt_road_segs.size() > t.ALT_ROAD_SEG_MAX:
		_fail("the CPU corridor cache holds %d segments against ALT_ROAD_SEG_MAX %d — the push clamps to the array size, so the GPU flattens a shorter corridor than the collision heightmap does" % [
			t._alt_road_segs.size(), t.ALT_ROAD_SEG_MAX])
	if seg_count <= 0:
		_fail("alt_road_seg_count is %d after a refresh — the shader flattens no corridor at all while the CPU's heightmap flattens %d segments" % [
			seg_count, t._alt_road_segs.size()])
	# ...and the PADDING really is inert. The shader never reads past the count, but
	# a padder that re-packed or reordered would show up here first.
	for i in range(seg_count, segs.size()):
		if segs[i] != Vector4.ZERO:
			_fail("alt_road_seg[%d] is %s past alt_road_seg_count %d — the padded tail is not zeros, so the array is not the cache verbatim" % [
				i, str(segs[i]), seg_count])
			break
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

	print("[altitude] shader parity: %d alt_* uniforms declared and pushed (%d value-checked, %d default-checked), array %d >= %d, %d road segments packed and chained" % [
		declared.size(), value_checked, defaults_checked, gpu_seg_max, t.ALT_ROAD_SEG_MAX, seg_count])
	t.free()
	Sentinel.done("shader_parity")


func _check_ground_collision() -> void:
	"""
	Check 5. THE FLOOR IS THE FIELD.

	`_ensure_chunk_ground` is the one place a chunk gets something to stand on, and
	it runs inside update_chunks' SYNCHRONOUS safety-ring path — the floor is the
	whole fall-through guarantee. So this check has three jobs:

	  a. WITH THE FLAG OFF the shape is still a BoxShape3D of exactly
	     Vector3(chunk_size, 0.1, chunk_size), and ground_collision_usec_total is
	     still 0. That is the merge condition restated where the collision half of
	     it lives; chunk_stream_selfcheck asserts the same box from the other side.
	  b. WITH THE FLAG ON the shape is a HeightMapShape3D whose stored samples,
	     multiplied back by the CollisionShape3D's uniform scale, equal height_at()
	     at the corresponding world points. THAT PRODUCT IS THE POINT: the heights
	     are pre-divided by the scale so the scale can be uniform, and a check that
	     read map_data raw would happily pass a floor sitting at a third of the
	     height the player sees. The scale is asserted uniform for the same reason.
	  c. THE COST, PRINTED. The per-chunk build lands in the synchronous path, so
	     its microseconds are a REPORT deliverable (docs/field-altitude-spike.md),
	     not an assertion — a threshold typed in here would be a number nobody
	     measured pretending to be a budget.
	"""
	# --- a. the flag OFF ------------------------------------------------------
	var flat := _make_terrain(SEEDS[0])
	var flat_chunk: Node = flat._ensure_chunk_ground(GROUND_CHUNKS[0])
	var flat_shape := _ground_collision_shape(flat_chunk)
	if flat_shape == null:
		_fail("the flag-off chunk grew no CollisionShape3D at all — every chunk's floor is its fall-through guarantee")
	elif not (flat_shape.shape is BoxShape3D):
		_fail("the flag-off chunk's ground shape is a %s, not a BoxShape3D — the merge condition is that FIELD_ALTITUDE false is byte for byte today's world" % flat_shape.shape.get_class())
	else:
		var want := Vector3(flat.chunk_size, 0.1, flat.chunk_size)
		if (flat_shape.shape as BoxShape3D).size != want:
			_fail("the flag-off ground box is %s, not %s — chunk_stream_selfcheck asserts this box from the other side" % [
				str((flat_shape.shape as BoxShape3D).size), str(want)])
		if flat_shape.scale != Vector3.ONE:
			_fail("the flag-off ground shape is scaled %s — the flat path must not touch the transform" % str(flat_shape.scale))
	if flat.ground_collision_usec_total != 0:
		_fail("ground_collision_usec_total is %d with the flag off — the timed heightmap block was entered on the flat path" % flat.ground_collision_usec_total)
	flat.free()

	# --- b. the flag ON -------------------------------------------------------
	var t := _make_terrain(SEEDS[0])
	t.alt_force = true
	# The shipped refresh seam, so the corridor clause is LIVE in the heights the
	# chunks around the origin sample (check 3's note, one check along).
	t._alt_road_refresh(0.0)
	# THE GRID IS READ OFF THE SHIPPED MESH, never re-derived. This check used to
	# recompute `side` and `cell` with the same formula the builder used, so when
	# that formula was wrong (GROUND_SUBDIVISIONS + 1 for a PlaneMesh that is
	# actually GROUND_SUBDIVISIONS + 2 vertices across) the assertion agreed with
	# the bug and the floor was quietly a different interpolant of height_at() from
	# the surface drawn over it. The mesh's own vertex array is the only
	# independent witness there is.
	#
	# COUNT, SPACING **AND ORIGIN**, and the third one is why the two sorted
	# coordinate lists below are kept rather than reduced to a `cell`: an earlier
	# version recovered mesh_x[0] and then threw it away, sampling at
	# `origin - half + i * cell` — the builder's own formula, character for
	# character. A builder that sampled at cell centres, or mirrored Z, or
	# transposed the row-major index would have been reproduced verbatim here and
	# certified. The loop below indexes mesh_x / mesh_z DIRECTLY, so the sample
	# positions are the mesh's vertices and nothing about the grid is re-derived.
	var ground_verts: PackedVector3Array = t._get_shared_ground_mesh() \
			.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	var distinct_x: Dictionary = {}
	var distinct_z: Dictionary = {}
	for v: Vector3 in ground_verts:
		distinct_x[snappedf(v.x, 1e-4)] = true
		distinct_z[snappedf(v.z, 1e-4)] = true
	var mesh_side: int = distinct_x.size()
	var mesh_x: Array = distinct_x.keys()
	mesh_x.sort()
	var mesh_z: Array = distinct_z.keys()
	mesh_z.sort()
	var mesh_cell: float = float(mesh_x[1]) - float(mesh_x[0])
	var side: int = t.ALT_GROUND_SIDE
	var cell: float = t.alt_ground_cell()
	if mesh_side != side or distinct_z.size() != side:
		_fail("the shared ground PlaneMesh is %d x %d vertices but ALT_GROUND_SIDE is %d — the collision grid is not the visual mesh's grid and the floor is an approximation of the surface you see" % [
			mesh_side, distinct_z.size(), side])
	if not is_equal_approx(mesh_cell, cell):
		_fail("the shared ground PlaneMesh's vertex spacing is %.6f m but alt_ground_cell() is %.6f m — the heightmap samples land between the drawn vertices" % [
			mesh_cell, cell])
	# ALT_AMP_MAX HAS TO BOUND THE WHOLE LADDER, not the rung it is spelled from.
	# The custom_aabb below is sized from it, so a retune that raises ALT_AMP_SNOW
	# past ALT_AMP_MOUNTAIN would leave every cull volume in the world short while
	# `const ALT_AMP_MAX := ALT_AMP_MOUNTAIN` still read as "the tallest rung".
	# GDScript cannot call maxf() in a const, so the maximum is asserted here.
	for amp_name: String in ["ALT_AMP_DESERT", "ALT_AMP_PLAINS", "ALT_AMP_CITY",
			"ALT_AMP_FOREST", "ALT_AMP_MOUNTAIN", "ALT_AMP_SNOW"]:
		if float(t.get(amp_name)) > t.ALT_AMP_MAX:
			_fail("%s is %.1f m, over ALT_AMP_MAX %.1f — every displaced chunk's custom_aabb is shorter than the field it bounds and hilltops are culled on screen" % [
				amp_name, float(t.get(amp_name)), t.ALT_AMP_MAX])
	var worst := 0.0
	var sampled := 0
	for chunk_pos: Vector2i in GROUND_CHUNKS:
		var node: Node = t._ensure_chunk_ground(chunk_pos)
		var cs := _ground_collision_shape(node)
		if cs == null or not (cs.shape is HeightMapShape3D):
			_fail("chunk %s built a %s with the flag ON — the displaced ground has no floor that follows it" % [
				str(chunk_pos), "nothing" if cs == null else cs.shape.get_class()])
			continue
		var shape: HeightMapShape3D = cs.shape
		if shape.map_width != side or shape.map_depth != side:
			_fail("chunk %s heightmap is %dx%d, not %dx%d — the collision grid has left the visual mesh's grid and the floor is an approximation of the surface you see" % [
				str(chunk_pos), shape.map_width, shape.map_depth, side, side])
			continue
		# UNIFORM, and equal to the metres-per-cell the heights were divided by.
		# A non-uniform scale is a Godot warning and unsupported by the physics
		# server; a uniform one of the WRONG size is a floor at the wrong height
		# with no warning anywhere, which is why the value is asserted too.
		if not is_equal_approx(cs.scale.x, cell) or cs.scale != Vector3.ONE * cs.scale.x:
			_fail("chunk %s heightmap scale is %s, not a uniform %.6f (alt_ground_cell())" % [
				str(chunk_pos), str(cs.scale), cell])
			continue
		# THE SHAPE HAS TO BE WHERE THE CHUNK IS. Every sample below is derived
		# from chunk_to_world(), so a shape (or the StaticBody3D between it and the
		# chunk) offset in X, Y or Z leaves all 324 comparisons per chunk passing
		# while the floor sits somewhere the vertex shader drew nothing. The
		# heightmap is centred on its own node by Godot, so "centred on the chunk"
		# is exactly "both intervening transforms are identity".
		if cs.position != Vector3.ZERO:
			_fail("chunk %s heightmap shape is offset %s from its body — the floor is displaced from the surface the vertex shader drew, and every sample below would still agree" % [
				str(chunk_pos), str(cs.position)])
			continue
		var ground_body := cs.get_parent() as Node3D
		if ground_body == null or ground_body.position != Vector3.ZERO:
			_fail("chunk %s ground body is offset %s from the chunk" % [
				str(chunk_pos), "missing" if ground_body == null else str(ground_body.position)])
			continue
		# THE CULL VOLUME, the other thing a vertex-displaced chunk needs and the
		# renderer cannot work out for itself: the shared PlaneMesh's AABB is flat,
		# so without a per-instance custom_aabb a hilltop is culled with the quad
		# under it. Asserted to CONTAIN this chunk's real height range, which also
		# pins ALT_AMP_MAX to the ladder — a rung raised past it fails here.
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.custom_aabb.size == Vector3.ZERO:
			_fail("chunk %s has no custom_aabb with the flag on — the displaced ground is frustum-culled against a zero-height box and hillsides pop at the screen edge" % str(chunk_pos))
			continue
		var origin: Vector3 = t.chunk_to_world(chunk_pos)
		var data: PackedFloat32Array = shape.map_data
		# THE MESH'S OWN VERTICES, offset to this chunk. Not `origin - half + i *
		# cell`: see the note above the grid read — that formula is the builder's,
		# and a check that repeats it agrees with the builder about a wrong grid.
		for iz in side:
			var world_z: float = origin.z + float(mesh_z[iz])
			for ix in side:
				var world_x: float = origin.x + float(mesh_x[ix])
				# UN-SCALED: the stored sample times the scale is the metres the
				# player stands at, and height_at is the metres the shader drew.
				var got: float = float(data[iz * side + ix]) * cs.scale.y
				var delta: float = absf(got - t.height_at(world_x, world_z))
				worst = maxf(worst, delta)
				# Against the cull volume, in the chunk's OWN local space (which is
				# what custom_aabb is in). This is what makes ALT_AMP_MAX a measured
				# bound rather than a hand-picked rung of the ladder.
				if not mesh_node.custom_aabb.has_point(Vector3(world_x - origin.x, got, world_z - origin.z)):
					_fail("chunk %s: the displaced surface reaches %.3f m at (%.1f, %.1f), outside custom_aabb %s — that hillside is culled while it is on screen, and ALT_AMP_MAX no longer bounds the amplitude ladder" % [
						str(chunk_pos), got, world_x, world_z, str(mesh_node.custom_aabb)])
				sampled += 1
		if worst > HEIGHTMAP_EPSILON:
			_fail("chunk %s: the collision heightmap is %.6f m off height_at() — the floor you stand on is not the ground you see" % [
				str(chunk_pos), worst])
			break
	if t.ground_collision_usec_total <= 0:
		_fail("ground_collision_usec_total is still 0 after %d flag-on chunks — the counter perf_overlay polls measures nothing" % GROUND_CHUNKS.size())
	# THE REPORT NUMBER (plan, Task 5): the synchronous safety ring is 9 chunks on
	# a boundary crossing, so per-chunk microseconds times nine is the frame this
	# spike would add to a crossing.
	print("[altitude] ground collision: %d chunks, %d us total, %.1f us per chunk (%d grid samples, worst %.9f m off height_at)" % [
		GROUND_CHUNKS.size(), t.ground_collision_usec_total,
		float(t.ground_collision_usec_total) / float(GROUND_CHUNKS.size()), sampled, worst])
	t.free()
	Sentinel.done("ground_collision")


func _check_field_is_walkable() -> void:
	"""
	Check 6. THE FIELD IS WALKABLE — and the mountains are still walls.

	The heightfield may not hand the player a slope they can walk up where the
	flat world had a wall: MOUNTAIN IMPASSABILITY is a block massif you go around,
	and it rests on the jump apex (3.61 m) sitting under MOUNTAIN_MIN_LAYER_HEIGHT.
	A field steeper than MAX_WALKABLE_SLOPE would be scenery the player slides off
	rather than terrain; a field with a *gentle* rise against a massif wall is the
	residual risk, and this check prints the numbers the report reasons about it
	with rather than pretending to settle it.

	The slope is the gradient MAGNITUDE over a one-metre step in each axis, so a
	diagonal ridge is measured at its steepest and not at its axis-aligned
	shoulder. Sampled per seed, and the MOUNTAIN band is tracked separately
	because that band carries the biggest amplitude in the ladder by a factor of
	six and it is the only one impassability depends on.
	"""
	var apex := _jump_apex()
	if apex <= 0.0:
		_fail("could not read the jump apex out of player_controller — check 6's mountain reasoning would print nothing")
	for seed_value: int in SEEDS:
		var t := _make_terrain(seed_value)
		t.alt_force = true
		t._alt_road_refresh(0.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var worst_mountain := 0.0
		var mountain_samples := 0
		for i in WALK_SAMPLES:
			var x := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var z := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var h: float = t.height_at(x, z)
			var dx: float = (t.height_at(x + WALK_STEP, z) - h) / WALK_STEP
			var dz: float = (t.height_at(x, z + WALK_STEP) - h) / WALK_STEP
			var slope := Vector2(dx, dz).length()
			if slope > worst:
				worst = slope
				worst_at = Vector2(x, z)
			if t.biome_at(x, z) == t.Biome.MOUNTAIN:
				mountain_samples += 1
				worst_mountain = maxf(worst_mountain, slope)
		# THE SKIRTS, MEASURED RATHER THAN INHERITED, AND THERE ARE TWO LEGS BECAUSE
		# THE FOUR SKIRTS FAIL THE BOX IN TWO DIFFERENT WAYS. A skirt is where the
		# steepest ground in the field is by construction — a mask ramping the band's
		# whole amplitude to zero across it — and the ±5 km box above samples none of
		# them the way they need sampling.
		#
		# The ROAD's (this leg) it essentially never hits at all: the corridor only
		# exists within _alt_road_window() of the window centre, so it is walked as
		# the curve it is, straight across the ramp at every station.
		#
		# The RIVER's (the leg below) it hits constantly and still under-measures,
		# which is the subtler failure and the one worth the second loop.
		var worst_skirt := 0.0
		var skirt_at := Vector2.ZERO
		var skirt_samples := 0
		t._road_extend_to_x(-SAMPLE_HALF, SAMPLE_HALF)
		for i in FLAT_ROAD_STATIONS * 2 + 1:
			var st: Dictionary = t._road_station(mini(i - FLAT_ROAD_STATIONS, t._road_terminal_k()))
			var c: Vector2 = st.center
			var n := Vector2(-sin(st.heading), cos(st.heading))
			# Straight across the ramp, both banks, at SKIRT_PROBE_STEPS offsets —
			# the whole smoothstep including its steepest middle.
			for j in SKIRT_PROBE_STEPS:
				var frac: float = float(j) / float(SKIRT_PROBE_STEPS - 1)
				var off: float = t.ALT_ROAD_FLAT_HALF + frac * t.ALT_ROAD_SKIRT
				for side: float in [1.0, -1.0]:
					var q: Vector2 = c + n * side * off
					var hq: float = t.height_at(q.x, q.y)
					var sdx: float = (t.height_at(q.x + WALK_STEP, q.y) - hq) / WALK_STEP
					var sdz: float = (t.height_at(q.x, q.y + WALK_STEP) - hq) / WALK_STEP
					var s: float = Vector2(sdx, sdz).length()
					skirt_samples += 1
					if s > worst_skirt:
						worst_skirt = s
						skirt_at = q
		# THE RIVER SKIRT, THE TIGHTEST OF THE FOUR — rejection-sampled, because it
		# is the one skirt with no geometry to walk. Its band is a FIELD interval
		# (RIVER_HALF_WIDTH .. * ALT_RIVER_SKIRT_K), so the test here is the same
		# expression _alt_flat_mask's clause 3 and is_river_at() both read, and the
		# points that pass it are exactly the bank. The band is ~5.5% of the box, so
		# the uniform loop above already lands ~1,100 points on it — this leg exists
		# for the TAIL: ten thousand hits find ~0.82 where those 1,100 find ~0.59,
		# and the report's headroom against MAX_WALKABLE_SLOPE is read off this one.
		var worst_river := 0.0
		var river_at := Vector2.ZERO
		var river_hits := 0
		var river_attempts := 0
		var river_inner: float = t.RIVER_HALF_WIDTH
		var river_outer: float = t.RIVER_HALF_WIDTH * t.ALT_RIVER_SKIRT_K
		while river_hits < RIVER_SKIRT_HITS and river_attempts < RIVER_SKIRT_MAX_ATTEMPTS:
			river_attempts += 1
			var rx := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var rz := rng.randf_range(-SAMPLE_HALF, SAMPLE_HALF)
			var d: float = absf(t._biome_noise(rx, rz) - t.RIVER_LEVEL)
			if d <= river_inner or d >= river_outer:
				continue
			river_hits += 1
			var hr: float = t.height_at(rx, rz)
			var rdx: float = (t.height_at(rx + WALK_STEP, rz) - hr) / WALK_STEP
			var rdz: float = (t.height_at(rx, rz + WALK_STEP) - hr) / WALK_STEP
			var sr: float = Vector2(rdx, rdz).length()
			if sr > worst_river:
				worst_river = sr
				river_at = Vector2(rx, rz)
		if river_hits < RIVER_SKIRT_HITS:
			_fail("seed %d: only %d of %d sampled points landed on a river BANK — the tightest skirt in the field would be reported off a sample that does not exist" % [
				seed_value, river_hits, river_attempts])
		# THE FIELD HAS TO BE ALIVE FIRST. Every assertion below is an UPPER bound,
		# so a height_at() that returned 0.0 everywhere — the whole heightfield
		# deleted, or alt_force silently stopping — leaves worst, worst_skirt and
		# worst_mountain all exactly 0.0 and this check green. Checks 2-5 all go
		# red on a dead field; this was the only one that did not, and the printed
		# report numbers below would have been read off zero samples.
		if worst <= 0.0 or worst_skirt <= 0.0 or worst_river <= 0.0:
			_fail("seed %d: the field is FLAT (worst slope %.6f, road skirt %.6f, river skirt %.6f) with the spike forced on — check 6's bounds would pass on a heightfield that does not exist" % [
				seed_value, worst, worst_skirt, worst_river])
		if mountain_samples == 0:
			_fail("seed %d: not one of the %d samples landed in the MOUNTAIN band — the mountain figure this check reports, and the impassability argument that reads it, would be printed off nothing" % [
				seed_value, WALK_SAMPLES])
		if worst > MAX_WALKABLE_SLOPE:
			_fail("seed %d: the field reaches %.3f m per metre at (%.1f, %.1f), over MAX_WALKABLE_SLOPE %.1f — that face is a wall the player slides off, not ground" % [
				seed_value, worst, worst_at.x, worst_at.y, MAX_WALKABLE_SLOPE])
		if worst_skirt > MAX_WALKABLE_SLOPE:
			_fail("seed %d: the road corridor's SKIRT reaches %.3f m per metre at (%.1f, %.1f), over MAX_WALKABLE_SLOPE %.1f — the coin road sits at the bottom of a wall" % [
				seed_value, worst_skirt, skirt_at.x, skirt_at.y, MAX_WALKABLE_SLOPE])
		if worst_river > MAX_WALKABLE_SLOPE:
			_fail("seed %d: a river BANK reaches %.3f m per metre at (%.1f, %.1f), over MAX_WALKABLE_SLOPE %.1f — the wading band is at the bottom of a levee, not a ramp" % [
				seed_value, worst_river, river_at.x, river_at.y, MAX_WALKABLE_SLOPE])
		# REPORT NUMBERS, all on one line (plan, Task 5): the field's worst slope,
		# the worst inside the band impassability depends on, the worst on each of
		# the two skirts that are measured rather than inherited, and the jump apex
		# the massif walls are sized against. The RIVER figure is the one the
		# report's headroom is read off — it is the largest of the four.
		print("[altitude] seed %d: max slope %.3f m/m (mountain band %.3f over %d samples, road skirt %.3f over %d, river skirt %.3f over %d), jump apex %.4f m, bound %.1f" % [
			seed_value, worst, worst_mountain, mountain_samples, worst_skirt, skirt_samples,
			worst_river, river_hits, apex, MAX_WALKABLE_SLOPE])
		t.free()
	Sentinel.done("field_is_walkable")


func _ground_collision_shape(chunk_node: Node) -> CollisionShape3D:
	"""
	The one CollisionShape3D under a chunk's ground StaticBody3D, or null.

	Walked rather than $-pathed because the nodes are unnamed, and because
	_ensure_chunk_ground is the only thing that has run on this chunk here — a
	fully populated chunk also carries the BLOCK body, which is a different
	StaticBody3D and not this one's business.
	"""
	for body: Node in chunk_node.get_children():
		if body is StaticBody3D:
			for child: Node in body.get_children():
				if child is CollisionShape3D:
					return child
	return null


func _jump_apex() -> float:
	"""
	The player's unaided jump apex in metres, JUMP_VELOCITY^2 / (2 * gravity) —
	tower_interior_selfcheck._jump_apex verbatim, and recomputed rather than
	restated for the same reason: the number is only worth printing in the report
	if it still tracks the jump somebody might retune.
	"""
	var script: GDScript = load(PLAYER_SCRIPT)
	var probe: Object = script.new()
	var g: float = float(probe.get("gravity"))
	var v: float = float(script.get_script_constant_map().get("JUMP_VELOCITY", 0.0))
	if probe is Node:
		(probe as Node).free()
	if g <= 0.0 or v <= 0.0:
		return 0.0
	return v * v / (2.0 * g)


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
	## fragment()'s colour chain with six metres in place of six colours, chained
	## low-to-high over the same thresholds and blend.
	##
	## HONEST ABOUT WHAT THIS IS: unlike _oracle_pair_f32, which is transcribed from
	## the GLSL and is the whole basis of check 2's bit-exactness leg, this one is a
	## SAME-LANGUAGE transcription of _alt_amplitude. It catches a one-sided edit of
	## the ladder (a threshold paired with the wrong amplitude, a rung dropped) and
	## it binds height_at()'s composition to a ladder written out independently — it
	## does NOT prove the GLSL's ladder is the same ladder. What binds the GPU is
	## check 4: every alt_amp_* uniform declared, pushed, and equal to the constant
	## it is named after, defaults included. The ORDER of the GLSL's rungs is the
	## one thing neither check sees; it is the parity contract's edited-together
	## rule, same as biome_noise's.
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
