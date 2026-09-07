class_name TerrainAltitude
extends RefCounted
## The FIELD_ALTITUDE spike — CPU twin of the ground displacement shader,
## four forced-flat authored zones, and collision heightmap generator.
##
## Extracted from endless_terrain.gd (bead godot-test1-ftn.29, epic godot-test1-ftn).
## See docs/field-altitude-spike.md for the measurement report.

# FIELD ALTITUDE — THE SPIKE FLAG (bead godot-test1-ope.1)
# ----------------------------------------------------------------------------
#
# THE WORLD IS STILL FLAT. This whole block, every alt_* uniform in
# ground.gdshader and every `alt_` function below it exist to MEASURE what a
# vertex-displaced heightfield would cost and what it would break — not to ship
# one. With FIELD_ALTITUDE false the world is byte for byte today's flat world:
# height_at() early-returns 0.0 before touching any noise, _ensure_chunk_ground
# builds the same BoxShape3D it always did, and _apply_biome_shader_params()
# pushes alt_enabled = 0.0 so the shader displaces nothing. THAT IS THE MERGE
# CONDITION — the flag ships false and every self-check is green with it false.
#
# Flipping it true is how the spike's numbers are taken (see
# docs/field-altitude-spike.md): the red-check list, the per-chunk collision
# build cost and the web F3 readings all come from a local flip that is never
# committed.
const FIELD_ALTITUDE: bool = false

## Altitude noise wavelength in metres. Deliberately NOT BIOME_CELL_SIZE (400):
## if the hills shared the biome field's wavelength every ridge would line up
## with a biome edge and the world would read as terraced regions rather than as
## terrain. 260 m is coprime-ish with 400 and still spans ~5 chunks, so a hill is
## something you walk over rather than something you step on.
const ALT_CELL_SIZE: float = 260.0

## Altitude's own domain shift, applied ON TOP of this run's biome_offset. The
## "own hash stream" rule one feature along: without it the height field and the
## biome field would be the same noise read twice, so every mountain band would
## have its peak in exactly the same place as its own classification maximum.
const ALT_OFFSET_SALT: Vector2 = Vector2(37.0, 71.0)

## The second octave: frequency multiplier and its weight in the 0..1 sum. One
## broad octave alone gives smooth blobs; 30% of a 3.1x octave is enough to read
## as ground without adding a slope the walk check would refuse.
const ALT_DETAIL_SCALE: float = 3.1
const ALT_DETAIL_WEIGHT: float = 0.3

## The second octave's own lattice shift, so the two octaves do not share their
## zero-gradient lattice corners (value noise has zero gradient at every corner —
## see the note on RIVER_HALF_WIDTH — and stacking two octaves that agree about
## where those corners are gives visible flat spots on every hilltop).
const ALT_DETAIL_SHIFT: Vector2 = Vector2(17.0, 31.0)

## PER-BIOME AMPLITUDE, in metres: the half-range of the signed height, so a
## MOUNTAIN point swings +/- 22 m. Read out of the biome field with the exact
## smoothstep chain fragment() uses for the six ground colours, so the height a
## band gets and the colour it is painted are the same readout of the same
## number and cannot disagree at a boundary.
##
## The numbers are the SPIKE's, chosen to be legible in a screenshot rather than
## tuned: desert dunes are low, plains are gentle, the NOISE city band is nearly
## paved flat (it is meant to be a town, and Budapest itself is forced flat
## outright by _alt_flat_mask), forest is rolling, mountain is the headline and
## snow sits just under it. Every one of them is a REPORT item, not a shipped
## tuning.
const ALT_AMP_DESERT: float = 2.5
const ALT_AMP_PLAINS: float = 3.5
const ALT_AMP_CITY: float = 1.0
const ALT_AMP_FOREST: float = 6.0
const ALT_AMP_MOUNTAIN: float = 22.0
const ALT_AMP_SNOW: float = 16.0

## The tallest rung of the ladder above, SPELLED from it rather than computed —
## GDScript cannot call maxf() in a const. It is not a shader uniform (nothing in
## ground.gdshader wants it); it is only what _ensure_chunk_ground sizes a
## displaced chunk's custom_aabb from, and the field is a SIGNED half-range so the
## box spans +/- it. Because the spelling is manual, altitude_selfcheck check 5
## asserts it really is the maximum over all six: a retune that raised
## ALT_AMP_SNOW past mountain would otherwise leave every cull volume in the world
## short while this line still read as "the tallest rung".
const ALT_AMP_MAX: float = ALT_AMP_MOUNTAIN

## THE FOUR FORCED-FLAT ZONES' SKIRTS (see _alt_flat_mask below). Each zone is a
## hard inner region where the ground is held at exactly y = 0, plus a smoothstep
## SKIRT out to the number here — the ground has to arrive at the authored zone
## already level, because a step at the boundary is a wall the player walks into
## and a seam the shader draws a crease along.

## Budapest: 120 m outside BudapestPlan.rect(). Wide because the city's own edge
## is a street grid the player walks out of — the skirt has to be longer than the
## STREET_PITCH (62 m) it hands over to, or the last block sits on a slope.
const ALT_CITY_SKIRT: float = 120.0

## The HQ disc: 60 m outside TOWER_RADIUS. Shorter than the city's because the
## thing being protected is one building on a 65 m disc rather than a 2.2 km grid,
## and the tower's own approach is already clear of everything (tower_excludes).
const ALT_TOWER_SKIRT: float = 60.0

## Every river band: the skirt is expressed in FIELD units — a multiple of
## RIVER_HALF_WIDTH — and NOT in metres, which is the whole trick. is_river_at()
## reads the same |_biome_noise - RIVER_LEVEL| < RIVER_HALF_WIDTH test, so the
## flat edge and the wading edge are two readouts of ONE number and can never
## disagree: water stays at y = 0 and the XZ-only wading contract survives with no
## edit anywhere. 3.5 gives a bank about two and a half river-widths wide.
##
## IT IS ALSO THE TIGHTEST SKIRT OF THE FOUR, and the only one whose width is not
## a number written here: the other three ramp over an authored 40-120 m, this one
## ramps over 0.0175 of BIOME FIELD, whose width in metres is that divided by the
## local |grad _biome_noise| — about 5-10 m. So it is the steepest ground the
## spike produces (measured 0.71-0.82 m/m against MAX_WALKABLE_SLOPE 1.0, where
## the road's ramp is 0.17-0.39), a walkable bank rather than a levee but with
## the least headroom in the field. altitude_selfcheck check 6 has a leg of its
## own for it; raising this constant is what widens the bank if a retune needs it.
const ALT_RIVER_SKIRT_K: float = 3.5

## The coin road corridor: flat within 22 m of the centreline, level by 40 m
## beyond that. 22 clears road_width_max/2 and sits just inside the widest road
## clearance any spawner asks for (MOUNTAIN_ROAD_CLEARANCE 24), so the strip that
## is held flat is a strip nothing is allowed to stand in anyway.
##
## THE ROAD IS THE SPIKE'S CONTROL and that is why it is flattened at all (the
## bead offered "accept the road on hills" as the alternative). The coin road is
## where the player walks, so a hilly road sends coin settling, road bosses and
## road clearance red in the same run and the red list stops telling you which
## breakage is the heightfield's.
const ALT_ROAD_FLAT_HALF: float = 22.0
const ALT_ROAD_SKIRT: float = 40.0

## THE COARSE ROAD POLYLINE the corridor is measured against — and the ONE
## geometry BOTH languages read (plan, Task 3). The GPU cannot walk the station
## cache: it is a Dictionary grown on demand, station by station. So the corridor
## arrives as a uniform array, and the CPU reads that SAME array rather than
## re-deriving the distance from the stations — parity by construction beats
## parity by re-derivation, the _city_river_segments() precedent one feature on.
##
## STRIDE 8 — every 8th station, ~48 m of road apart. MEASURED over 5 seeds and
## ±560 m of centreline: the worst fine station sits 9.3 m off the chord between
## its two coarse ends, against a 22 m ALT_ROAD_FLAT_HALF — so the centreline the
## player actually walks is always deep inside the flat strip, which is the only
## thing this corridor has to promise. Stride 4 measures 3.6 m and stride 16
## measures 25.2 m, which is already OUTSIDE the strip: 16 is a road with hills on
## it. 8 is the coarsest stride that still buys the promise.
const ALT_ROAD_SEG_STRIDE: int = 8

## The deviation bound stride 8 buys, rounded up from the measured 9.3 m. Nothing
## in the field reads it: it is the written contract between ALT_ROAD_SEG_STRIDE
## and ALT_ROAD_FLAT_HALF, and altitude_selfcheck's check 3 asserts it, so raising
## the stride fails loudly instead of quietly putting the coin road on a hill.
const ALT_ROAD_SEG_DEV_MAX: float = 12.0

## How many segments the corridor is, and how far the station cache is grown to
## build them. 24 segments — TWELVE EACH SIDE of the player's own station — is
## 12 x 8 x 6 m = 576 m of road either way on a straight stretch, comfortably past
## the 250 m desktop residency half-width (render_distance 5 x chunk_size 50), so
## every loaded chunk's ground sees the same corridor the CPU does.
##
## The X reach _road_extend_to_x is asked for is DERIVED from this and the stride
## by _alt_road_window(), never written down a second time.
##
## THE NODES ARE SNAPPED to a stride lattice (see _alt_road_segments): the window
## slides with the player, but which stations are chord nodes does not, because a
## chunk's collision heightmap is baked once and the shader re-evaluates live.
##
## ALT_ROAD_SEG_MAX is restated in ground.gdshader — a GLSL array is a fixed size —
## the CITY_SHADER_SEG_MAX contract one array along.
const ALT_ROAD_SEG_MAX: int = 24


static func _alt_road_seg_uniform(terrain: Node3D) -> PackedVector4Array:
	"""
	The cached coarse road polyline PADDED to ALT_ROAD_SEG_MAX, for
	ground.gdshader's `alt_road_seg` array uniform — _city_river_segments()'s twin.

	@return: Exactly ALT_ROAD_SEG_MAX entries. The tail past `alt_road_seg_count`
	         is zeros and the shader never reads it, but a GLSL array uniform is a
	         fixed size whatever the polyline's length is, so it has to be filled.

	The entries are copied VERBATIM out of _alt_road_segs — the packing is
	(x1, z1, x2, z2) on both sides and this function must never re-pack them, which
	is the failure altitude_selfcheck check 4's packing leg exists to catch.
	"""
	var segs := PackedVector4Array()
	segs.resize(ALT_ROAD_SEG_MAX)
	assert(terrain._alt_road_segs.size() <= ALT_ROAD_SEG_MAX,
			"_alt_road_segs holds more segments than the GLSL array can carry — the push clamps and the GPU flattens a shorter corridor than the collision heightmap does")
	for i in mini(terrain._alt_road_segs.size(), ALT_ROAD_SEG_MAX):
		segs[i] = terrain._alt_road_segs[i]
	return segs


static func alt_enabled(terrain: Node3D) -> bool:
	"""
	THE ONE GATE every altitude path reads.

	@return: true when the heightfield is live.

	FIELD_ALTITUDE is the shipped answer (false, always) and `alt_force` is the
	self-check's, so `altitude_selfcheck.gd` can drive both halves in one process
	without editing a const. Nothing in the game writes alt_force.
	"""
	return FIELD_ALTITUDE or terrain.alt_force


static func _alt_value_noise_pair(terrain: Node3D, p: Vector2) -> float:
	"""
	The altitude field's two octaves — the GDScript twin of `alt_value_noise_pair`
	in ground.gdshader.

	@param p: Sample point in altitude-noise space (world metres / ALT_CELL_SIZE,
	          already domain-shifted).
	@return: Value in 0..1 (the two weights sum to 1, so the sum cannot leave the
	         range either octave lives in).

	EVERY STEP ROUTED THROUGH Vector2, which is the only fp32 cast GDScript has —
	the whole argument is in _biome_hash2's docstring and it applies with more
	force here, because a hash difference that moved the WATERLINE by metres would
	move a MOUNTAIN by metres. Do not simplify a line of this back to scalar
	arithmetic: bare GDScript floats are f64 and the GPU is f32, and the two give
	different fields rather than the same field at different precisions.
	"""
	# The complement is taken through fp32 too: the shader receives
	# alt_detail_weight as a float32 uniform and computes 1.0 - it in fp32, so
	# rounding the pair here is what makes the two weights bit-identical.
	var w := Vector2(1.0 - ALT_DETAIL_WEIGHT, ALT_DETAIL_WEIGHT)
	var broad := Vector2(terrain._biome_value_noise(p) * w.x, 0.0).x
	var detail := Vector2(terrain._biome_value_noise(p * ALT_DETAIL_SCALE + ALT_DETAIL_SHIFT) * w.y, 0.0).x
	return Vector2(broad + detail, 0.0).x


static func _alt_amplitude(terrain: Node3D, biome_value: float) -> float:
	"""
	How tall the ground is allowed to be where the biome field reads
	`biome_value` — the GDScript twin of `alt_amplitude` in ground.gdshader.

	@param biome_value: A _biome_noise() readout (0..1).
	@return: The half-range of the signed height, in metres.

	IT IS fragment()'s COLOUR CHAIN WITH SIX METRES INSTEAD OF SIX COLOURS —
	chained low-to-high over the same BIOME_*_MAX thresholds with the same
	BIOME_BLEND radius, in the same order (desert, plains, city, forest, mountain,
	snow). That is deliberate and it is the cheap half of the parity contract: the
	amplitude a band gets is the same readout of the same number as the colour it
	is painted, so a band cannot be tall where it looks like sand. A NEW BAND is
	one extra lerpf here and one extra mix() there, exactly as it is for colour.
	"""
	var amp := ALT_AMP_DESERT
	amp = lerpf(amp, ALT_AMP_PLAINS,
			smoothstep(terrain.BIOME_DESERT_MAX - terrain.BIOME_BLEND, terrain.BIOME_DESERT_MAX + terrain.BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_CITY,
			smoothstep(terrain.BIOME_PLAINS_MAX - terrain.BIOME_BLEND, terrain.BIOME_PLAINS_MAX + terrain.BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_FOREST,
			smoothstep(terrain.BIOME_CITY_MAX - terrain.BIOME_BLEND, terrain.BIOME_CITY_MAX + terrain.BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_MOUNTAIN,
			smoothstep(terrain.BIOME_FOREST_MAX - terrain.BIOME_BLEND, terrain.BIOME_FOREST_MAX + terrain.BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_SNOW,
			smoothstep(terrain.BIOME_MOUNTAIN_MAX - terrain.BIOME_BLEND, terrain.BIOME_MOUNTAIN_MAX + terrain.BIOME_BLEND, biome_value))
	return amp


static func _alt_road_window(terrain: Node3D) -> float:
	"""
	How far in X the station cache is grown to build one corridor window.

	@return: Metres either side of the window's centre.

	DERIVED, never hand-multiplied: half the segment budget, times the stations
	each segment spans, times the metres a station is — plus the slack below. A
	written-down 600.0 goes stale the day road_coin_spacing (an @export) or either
	segment constant moves, and the corridor then silently shortens against a
	road_k_max clamp with no error anywhere.

	THE SLACK is what the window is taken in STATIONS rather than in X for: the
	road's heading cap is 78 degrees, so a curving stretch advances as little as
	1.25 m of X per station and the cache has to already hold the station the
	lattice snap asks for. A straight road needs the bare product; anything else
	needs the binary search either side of it to land inside the cache.
	"""
	# _road_spacing(), NOT the raw road_coin_spacing export: asserts are stripped
	# from release builds, so a designer's 0 leaves the stations still stepping by
	# the clamped 0.1 m while this window collapsed to zero — the corridor would
	# silently stop being flattened while the road it belongs to still existed.
	# Every road step routes through that one clamp; so does this one.
	return float(ALT_ROAD_SEG_MAX / 2 * ALT_ROAD_SEG_STRIDE + ALT_ROAD_SEG_STRIDE) \
			* terrain._road_spacing()


static func _alt_road_segments(terrain: Node3D, center_x: float) -> PackedVector4Array:
	"""
	The coin road around `center_x` as a COARSE polyline, packed as (x1, z1, x2, z2)
	segments — the shape ground.gdshader's `alt_road_seg` array uniform wants and
	the shape _alt_road_distance() reads on this side.

	@param center_x: World X the window is centred on (the player's chunk centre).
	@return: Up to ALT_ROAD_SEG_MAX segments, west to east. EMPTY while the spike
	         flag is off, and empty east of the terminal station.

	EVERY ALT_ROAD_SEG_STRIDE-th station is a node, so the segments are ~48 m of
	road each — see ALT_ROAD_SEG_STRIDE for the measurement that says a chord that
	long still keeps the centreline inside ALT_ROAD_FLAT_HALF.

	CAP 5 OF THE ROAD'S CONSUMERS (bead godot-test1-8gw.3, joining CAPs 1-4 — road
	coins, road clearance, road bosses and the minimap line): the walk stops at
	_road_terminal_k(). East of T there is no road to flatten a corridor around.

	ponytail: and there is a GAP between T and the city, which this cap creates and
	nothing else closes. T is at or west of ROAD_TERMINAL_X (1450) and the rect
	starts at BUDAPEST_MIN.x (1600), so the 150 m of authored approach corridor
	(BudapestPlan.road_approach_point, the seam spawn_approach_coins_in_chunk lays
	its coin trail along at y = 0) is outside BOTH flat zones for part of its run:
	clause 1's city skirt is only ALT_CITY_SKIRT (120 m) wide, and clause 4's
	polyline releases ALT_ROAD_FLAT_HALF + ALT_ROAD_SKIRT past the last station.
	Around x = 1500-1520 the product of the two leaves ~70-85 % of the local
	amplitude standing, and those coins would float or bury with the flag on.
	KNOWN SPIKE CEILING, in the report's migration list: the fix is to walk the
	approach centreline into this same polyline (it is a pure function and needs no
	new machinery), which costs ~3 more segments and therefore ALT_ROAD_SEG_MAX in
	both languages. Not done here because the spike ships flag-off and the corridor
	is only the control it measures the field against.

	The cap is on this CONSUMER and not on _road_extend_to_x — that function's
	forward loop hangs if the cache stops growing (see _road_terminal_k) — and the
	extend call below is what makes the binary search after it valid.
	"""
	var segs := PackedVector4Array()
	# The flag first, before the station cache is grown: with the spike off this
	# function must not so much as touch the road, or the "byte for byte today's
	# world" merge condition would rest on the cache being pure (it is, but the
	# claim should not need that argument).
	if not alt_enabled(terrain):
		return segs
	# Grown in X, because that is the only thing _road_extend_to_x speaks — but the
	# window is then taken in STATIONS around the player's own station, NOT as the
	# X range itself. The road's heading cap is 78 degrees, so a curving stretch
	# advances as little as 1.25 m of X per 6 m station: an X-ordered walk starting
	# at center_x - _alt_road_window() spends its whole segment budget hundreds of
	# metres WEST of the player and leaves the ground under their feet uncorridored.
	# Centring on the station is what makes the window a window around the player.
	var reach := _alt_road_window(terrain)
	terrain._road_extend_to_x(center_x - reach, center_x + reach)
	var k_last: int = mini(terrain.road_k_max, terrain._road_terminal_k())
	var half := ALT_ROAD_SEG_MAX / 2  # segments each side of the player's station
	# SNAPPED TO THE STRIDE LATTICE, and this line is load-bearing. The nodes have
	# to be a function of the WORLD, not of where the player is standing: the
	# collision HeightMapShape3D is baked once per chunk off height_at() and never
	# rebuilt, while the shader re-evaluates the corridor live off whatever window
	# was last pushed. An unsnapped k_center advances by ~8 stations per 50 m of
	# walking but not by EXACTLY 8, so every chunk-boundary crossing re-picked a
	# different set of chord nodes, _alt_road_distance() at a fixed world point
	# moved with it, and the floor drifted metres away from the surface drawn over
	# it — measured at 2.19 m along the coin road, which is the spike's control.
	# Snapping makes every node a station k = 0 (mod stride), so the polyline
	# inside the window is bit-identical from every centre.
	var k_center: int = terrain._road_first_k_at_or_after_x(center_x)
	k_center -= posmod(k_center, ALT_ROAD_SEG_STRIDE)
	var k := k_center - half * ALT_ROAD_SEG_STRIDE
	# Clamped ON THE LATTICE — a bare maxi(road_k_min, ...) would put the western
	# end back on an arbitrary station and reintroduce exactly what the snap fixed.
	while k < terrain.road_k_min:
		k += ALT_ROAD_SEG_STRIDE
	var k_end := mini(k_last, k_center + half * ALT_ROAD_SEG_STRIDE)
	var prev := Vector2.ZERO
	var have_prev := false
	while k <= k_end and segs.size() < ALT_ROAD_SEG_MAX:
		var c: Vector2 = terrain._road_station(k).center
		if have_prev:
			segs.append(Vector4(prev.x, prev.y, c.x, c.y))
		prev = c
		have_prev = true
		k += ALT_ROAD_SEG_STRIDE
	return segs


static func _alt_road_refresh(terrain: Node3D, center_x: float) -> void:
	"""
	Rebuild the cached coarse road polyline around `center_x`.

	@param center_x: World X the new window is centred on.

	THE ONE WRITER of _alt_road_segs, so the CPU's corridor and the array
	ground.gdshader is fed can never be built from two different windows. Called
	from update_chunks (chunk-boundary crossings), and it re-pushes the material
	itself: a window that moved on the CPU while the GPU kept the old one is a
	corridor drawn flat where the ground is not, which is the exact disagreement
	the shared array exists to make impossible.

	The re-push goes through _apply_biome_shader_params rather than writing the two
	road uniforms here, because ONE function feeding the ground material is what
	makes the parity contract auditable. It costs ~25 set_shader_parameter calls per
	~50 m of walking, against the several hundred vertices per chunk this saves from
	disagreeing.
	"""
	terrain._alt_road_segs = _alt_road_segments(terrain, center_x)
	terrain._apply_biome_shader_params()


static func _alt_road_distance(terrain: Node3D, world_x: float, world_z: float) -> float:
	"""
	Distance (world metres, XZ) from a point to the CACHED coarse road polyline —
	the GDScript twin of `alt_road_distance` in ground.gdshader.

	@param world_x, world_z: World-space point to test.
	@return: Distance to the nearest segment, or INF when the cache is empty (spike
	         off, or no refresh yet). INF is what the mask already reads as "no road
	         here", so an unbuilt window degrades to full altitude and never to a
	         crash.

	The clamped point-to-segment projection is BudapestPlan.segment_distance() —
	the same arithmetic the Danube polyline and the approach corridor ride, written
	entirely in Vector2 so every intermediate is f32 and matches what the shader
	computes. A second spelling of it here is exactly how the two would drift.
	"""
	var p := Vector2(world_x, world_z)
	var best := INF
	for seg: Vector4 in terrain._alt_road_segs:
		var d := BudapestPlan.segment_distance(p, Vector2(seg.x, seg.y), Vector2(seg.z, seg.w))
		if d < best:
			best = d
	return best


static func _alt_flat_mask(terrain: Node3D, world_x: float, world_z: float, biome_value: float) -> float:
	"""
	HOW MUCH ALTITUDE THIS POINT IS ALLOWED — the GDScript twin of `alt_flat_mask`
	in ground.gdshader.

	@param world_x, world_z: World-space point (metres).
	@param biome_value: The _biome_noise() readout at that point. PASSED IN, not
	                    re-derived: height_at() already has it for the amplitude
	                    ladder, and the shader twin takes it as `b` for the same
	                    reason — the vertex shader evaluates it once and spends it
	                    three times over for the finite-difference normals.
	@return: 1.0 in open field (full altitude), 0.0 inside any authored zone, and
	         a smoothstep ramp across each zone's skirt.

	IT IS A PRODUCT OF FOUR INDEPENDENT 0..1 FACTORS, so a point in two zones is
	FLAT, never twice flat — the four clauses cannot fight, and adding a fifth zone
	one day is one more factor and no re-derivation of the other four.

	THE ZONES ARE THE AUTHORED WORLD, and holding them at exactly 0.0 is what makes
	the spike's red-check list readable: Budapest, the tower interior and every
	wading test are written against a flat world, so if one of them goes red with
	the flag on, the MASK is wrong and the check is right (plan, Task 2).
	"""
	var p := Vector2(world_x, world_z)

	# CLAUSE 1 — BUDAPEST. The authored city, its plateaus, its bridge decks and
	# every DRY_RECTS row live INSIDE this rect, so none of them needs a clause of
	# its own. The rect is BudapestPlan's number and is never restated here — the
	# in_budapest() rule, one function along.
	var city: Rect2 = BudapestPlan.rect()
	# The standard axis-aligned outside distance: per-axis overshoot, clamped at
	# zero so an inside point measures 0 on both axes rather than a negative.
	var city_d := Vector2(
			maxf(maxf(city.position.x - p.x, p.x - city.end.x), 0.0),
			maxf(maxf(city.position.y - p.y, p.y - city.end.y), 0.0)).length()
	var mask := smoothstep(0.0, ALT_CITY_SKIRT, city_d)

	# CLAUSE 2 — THE HQ DISC. Shares TOWER_RADIUS and states no distance of its
	# own, the shell's rule: the building is not batched, not chunk-parented and
	# not rebuilt, so the ground under it may not move by so much as a millimetre.
	var site: Vector3 = terrain.tower_site()
	var tower_d := p.distance_to(Vector2(site.x, site.z))
	mask *= smoothstep(terrain.TOWER_RADIUS, terrain.TOWER_RADIUS + ALT_TOWER_SKIRT, tower_d)

	# CLAUSE 3 — EVERY RIVER BAND, in FIELD units. This is the same
	# |_biome_noise - RIVER_LEVEL| < RIVER_HALF_WIDTH test is_river_at() makes, so
	# the water's edge and the flat edge are one number: rivers stay at y = 0 and
	# wading stays XZ-only with no edit. Deliberately the RAW field, exactly as the
	# shader has it in `b` — the tower and city overrides is_river_at() applies are
	# readout policy, and both of those zones are already flattened above.
	mask *= smoothstep(terrain.RIVER_HALF_WIDTH, terrain.RIVER_HALF_WIDTH * ALT_RIVER_SKIRT_K,
			absf(biome_value - terrain.RIVER_LEVEL))

	# CLAUSE 4 — THE COIN ROAD CORRIDOR. See ALT_ROAD_FLAT_HALF for why the road is
	# the spike's control, and _alt_road_segments for the coarse polyline both
	# languages measure it against. Reading the CACHE rather than the station cache
	# is what makes this clause a pure lookup: height_at() is called once per ground
	# vertex, and growing a Dictionary from there would be a side effect per vertex.
	#
	# ponytail: the window is ALT_ROAD_SEG_MAX segments around the station nearest
	# the last chunk-boundary crossing, so outside it the corridor is simply not
	# flattened — a debug teleport far up the road sees hills on it until the next
	# crossing refreshes the polyline, one chunk of walking away. A hard-curving
	# stretch shortens the window in X too: 96 stations is 576 m of straight road
	# but only ~120 m of a road at the 78-degree heading cap, and 120 m is INSIDE
	# the 250 m desktop residency (and inside web's 150 m) — which is the condition
	# under which the baked-floor guarantee FAILS, not a reassurance. On such a
	# stretch a chunk loaded BY PROXIMITY can have its collision heightmap baked
	# while _alt_road_distance still answers INF over it, and a chunk's floor is
	# baked exactly once; two crossings later the vertex shader flattens a corridor
	# the floor under it still carries as a hill. KNOWN SPIKE CEILING, all of it;
	# the upgrade path is a distance texture (no window at all) or, cheaper, a
	# bigger ALT_ROAD_SEG_MAX in both languages — sized so _alt_road_window() clears
	# the residency half-width at the heading cap and not merely on a straight.
	mask *= smoothstep(ALT_ROAD_FLAT_HALF, ALT_ROAD_FLAT_HALF + ALT_ROAD_SKIRT,
			_alt_road_distance(terrain, world_x, world_z))

	return mask


static func height_at(terrain: Node3D, world_x: float, world_z: float) -> float:
	"""
	THE FIELD'S ALTITUDE at a world position — the GDScript twin of `field_height`
	in ground.gdshader, and the one function every altitude consumer reads.

	@param world_x, world_z: World-space point (metres).
	@return: Ground height in metres, signed around 0. Exactly 0.0 everywhere when
	         the spike flag is off, and exactly 0.0 inside every authored zone.

	RNG-free and side-effect-free — the biome field's contract, because it is the
	same field read a third way. Nothing in this call chain grows a cache or draws
	from a stream.

	IT IS PURE IN (x, z, run_seed) EVERYWHERE EXCEPT CLAUSE 4 of _alt_flat_mask,
	and that exception is the honest version of the contract. Clause 4 reads the
	CACHED coarse road polyline, whose WINDOW slides with the player: the chord
	NODES are snapped to a stride lattice (see _alt_road_segments) so the corridor
	is bit-identical from every centre INSIDE the window, but a point that falls
	off the window's end when the player walks away answers a different height. The
	window reaches _alt_road_window() metres either side, comfortably past the
	250 m desktop residency half-width ON A STRAIGHT ROAD, so there no chunk loaded
	BY PROXIMITY sees it move — which is what makes the baked collision heightmap
	safe. TWO CASES ESCAPE THAT, and neither is exotic: a hard-CURVING stretch,
	where 96 stations is only ~120 m of X and the window ends INSIDE the residency
	(clause 4's note has the arithmetic), and a chunk pinned by set_focus_points()
	(a far multiplayer teammate), loaded at unbounded distance so its floor is baked
	off whatever the local player's window held — possibly no corridor at all. In
	both the floor is baked once and the shader is not, so the two disagree by the
	local amplitude over the corridor. Promoting
	the spike means either making the corridor position-derived (a distance function
	of X, or a texture) or re-baking loaded chunks on refresh; both close the focus
	case with the residency one. See docs/field-altitude-spike.md.
	"""
	# THE FLAG, FIRST LINE AND BEFORE ANY NOISE. With the spike off this is the
	# whole function, so the flat world costs one bool compare and not one hash.
	if not alt_enabled(terrain):
		return 0.0
	var p: Vector2 = Vector2(world_x, world_z) / ALT_CELL_SIZE + (terrain.biome_offset as Vector2) + ALT_OFFSET_SALT
	var n := _alt_value_noise_pair(terrain, p)
	# 0..1 -> -1..1, so the field cuts valleys as well as raising hills and its
	# mean stays at the y = 0 the whole game is written against.
	var signed_unit := Vector2((n - 0.5) * 2.0, 0.0).x
	# ONE _biome_noise() evaluation, spent twice: the amplitude ladder and the flat
	# mask's river clause are both readouts of the same number, and the shader twin
	# passes it to both for the same reason.
	var b: float = terrain._biome_noise(world_x, world_z)
	var h := Vector2(signed_unit * _alt_amplitude(terrain, b), 0.0).x
	return Vector2(h * _alt_flat_mask(terrain, world_x, world_z, b), 0.0).x


static func alt_ground_cell(terrain: Node3D) -> float:
	"""
	Metres between two adjacent ground vertices — the heightmap's cell size and the
	CollisionShape3D's uniform scale, which are the same number by construction.

	@return: chunk_size spread over ALT_GROUND_SIDE - 1 spans (2.941 m at 50 m).

	PUBLIC because altitude_selfcheck reads it back; there is nowhere else the two
	call sites could agree except one function.
	"""
	return terrain.chunk_size / float(terrain.ALT_GROUND_SIDE - 1)


static func _alt_ground_heightmap(terrain: Node3D, chunk_pos: Vector2i) -> HeightMapShape3D:
	"""
	THE FLOOR OF ONE CHUNK, sampled off height_at() — the collision half of the
	spike, and the only altitude code that allocates anything.

	@param chunk_pos: Chunk coordinates.
	@return: A HeightMapShape3D on the chunk's own ALT_GROUND_SIDE^2 grid, in SHAPE
	         units (see the divide below); the caller scales it into metres.

	ONLY EVER CALLED BEHIND alt_enabled(). With the spike off the chunk keeps its
	BoxShape3D and this function is never entered, which is the merge condition.

	THE GRID IS THE VISUAL MESH'S GRID, and ALT_GROUND_SIDE is where that is
	spelled — Godot's `subdivide_width = N` cuts a PlaneMesh into N + 1 quads and
	therefore N + 2 vertices per side, NOT N + 1 (measured: 18 x 18 at 50/17 =
	2.941 m for GROUND_SUBDIVISIONS 16, and the first version of this file sampled
	17 x 17 at 3.125 m and claimed the identity anyway — a floor that was a
	DIFFERENT piecewise-linear interpolant of the same function, 5.2 cm off the
	drawn surface at worst). The sample points below are the PlaneMesh's own vertex
	positions, so the floor and the drawn surface are the same samples of the same
	function and cannot disagree anywhere, not even by an interpolation scheme.
	That identity is free and it is why the plan refuses to raise the subdivision;
	altitude_selfcheck check 5 reads the mesh's real vertex grid rather than
	re-deriving it, because a re-derivation is how the claim went unnoticed.

	Row-major, `map_data[z * map_width + x]`, the Godot layout: x runs along +X and
	z along +Z, both centred on the node, which is exactly how the chunk's own
	square is centred on its MeshInstance3D.
	"""
	var side: int = terrain.ALT_GROUND_SIDE
	var shape := HeightMapShape3D.new()
	shape.map_width = side
	shape.map_depth = side

	# The metres-per-cell the CollisionShape3D's uniform scale will apply. Heights
	# are DIVIDED by it here so that scale multiplies them back to the metres
	# height_at() returned — the alternative, a non-uniform scale of (cell, 1,
	# cell), is a Godot warning and unsupported by the physics server.
	var cell := alt_ground_cell(terrain)
	var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
	var half: float = terrain.chunk_size / 2.0

	var data := PackedFloat32Array()
	data.resize(side * side)
	for iz in side:
		var world_z := origin.z - half + float(iz) * cell
		for ix in side:
			var world_x := origin.x - half + float(ix) * cell
			# + GROUND_COLLISION_TOP: the box this replaces is a SOLID centred on the
			# chunk and the player stands on its top face, half a thickness up. See
			# the const — without this the flag-on floor sits 5 cm below the flag-off
			# one everywhere, forced-flat zones included.
			data[iz * side + ix] = (height_at(terrain, world_x, world_z) + terrain.GROUND_COLLISION_TOP) / cell
	shape.map_data = data
	return shape
