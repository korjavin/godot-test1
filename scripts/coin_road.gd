class_name CoinRoad
extends RefCounted
## ============================================================================
## THE COIN ROAD — the one trail every coin in the world rides
## ============================================================================
## Lifted out of `endless_terrain.gd` whole by bd `godot-test1-ftn.7`, in the
## idiom the four extractions before it settled (`terrain_props.gd`,
## `terrain_structures.gd`, `terrain_features.gd`, `terrain_biomes.gd`,
## `terrain_predators.gd`): a `class_name`d library of STATIC functions that
## RECEIVES the terrain as its first argument and calls
## `terrain.chunk_to_world` / `terrain.world_to_chunk` / `terrain._settle_coin_y`
## back through the reference. `extends RefCounted` and everything `static`: this
## is a namespace, not a node.
##
## ----------------------------------------------------------------------------
## THE STATION CACHE STAYED ON THE TERRAIN, AND THAT IS THE DESIGN DECISION
## ----------------------------------------------------------------------------
## The bead offered two shapes for `road_stations` / `road_k_min` / `road_k_max`
## — state on a node the terrain owns, or instance methods on a helper it
## instantiates once. It is neither: the FUNCTIONS moved and the STATE did not,
## and there are three independent reasons, any one of which would be enough.
##
##   1. `_drop_seeded_memos()` is deliberately ONE function under the seed write
##      (bd `godot-test1-bvq`, PR #276) clearing SEVEN caches derived from this
##      centreline — the stations, the terminal-station memo, the field bridges,
##      their wet-metre memo, the approach corridor's bridges and coin line, the
##      museum mile's site table and the altitude spike's road polyline. Its own
##      comment says why it is one function and not eleven lines copied into
##      every door. Moving three of the seven onto a helper splits exactly that.
##   2. `minimap_hud` reads `road_stations`, `road_k_min` and `road_k_max` as
##      MEMBERS through the `terrain` group, and `minimap_selfcheck` asserts them
##      by name. Six more self-checks (budapest, field_bridge, enemy_spawn, wade,
##      tower_shell, landmark_sites) read them the same way.
##   3. The cache is not the road's private business. It is world state with the
##      lifetime of a run, and the run's seed is the terrain's.
##
## So this file is pure geometry over state it is HANDED — which is also what
## keeps it static like its four siblings, rather than the one stateful odd one
## out in the family.
##
## ----------------------------------------------------------------------------
## WHAT DID NOT COME WITH IT
## ----------------------------------------------------------------------------
## * **The `@export var road_*` config** (spacing, widths, slots, chance, turn
##   rate, heading cap). A static library has no inspector — `terrain_features`
##   learned that when three `spawn_*` exports moved on its first pass and four
##   self-checks caught it. They are read as `terrain.road_coin_spacing`, which
##   changes no behaviour.
## * **The GEO LANDMARKS.** The museum mile is strung along this centreline, so
##   the road is its COORDINATE SYSTEM — but that is exactly the relationship
##   `terrain_biomes._biome_spot_ok` has with `_road_lateral_distance` and
##   `terrain_predators` has with `_road_station`, and neither of those became
##   road code. A geo landmark is the LANDMARK family (`landmark_builders.gd`
##   already holds `LANDMARKS` and `CITY_LANDMARKS`, and `spawn_landmark_in_chunk`
##   calls straight into it); its own bead, its own A/B. What ftn.4 recorded as
##   the blocker — "its site table is `run_seed`-memoized INSTANCE state that
##   `_drop_seeded_memos()` owns" — is dissolved by this bead rather than by
##   moving it here: the road's cache is that same kind of state, and the answer
##   above is that the state stays put while the functions leave.
## * **The FIELD BRIDGES.** A different bead (`godot-test1-06o.2`), a different
##   banner, its own memo trio; it merely reads this centreline.
##
## ----------------------------------------------------------------------------
## THE CONSUMERS STILL STOP AT `T`, AND `_road_extend_to_x` STILL DOES NOT
## ----------------------------------------------------------------------------
## `_road_terminal_k()` is the last station at or west of `ROAD_TERMINAL_X`, and
## the four numbered caps on it (road coins, road clearance, road bosses, the
## minimap's drawn line) plus CAP 5 (field bridges) and CAP 6 (`_alt_road_segments`)
## are unchanged by the move. `_road_extend_to_x` is deliberately UNCAPPED — it is
## the station cache, and a cache that stops growing hangs every forward loop that
## walks it until it passes an X.


## Heading restoring pull toward +X applied every station BEFORE the turn noise:
## heading *= (1 - ROAD_RESTORE). Without it the random turns would random-walk the
## heading and pin it against the cap; this gentle pull keeps the road trending
## forward and gives it a natural "return to course" feel after a bend.
const ROAD_RESTORE: float = 0.06

## Fixed seed mixed into the per-station hash for the CENTERLINE, distinct from the
## per-chunk object/crocodile seeds (it is its OWN world). The per-run run_seed is
## mixed in alongside it, so the road is stable for the duration of a run but takes
## a different path each run. Changing this constant reshapes every road ever rolled.
const ROAD_WORLD_SEED: int = 0x5_0AD  # "ROAD"-ish; arbitrary fixed constant

## Separate fixed seed for the per-slice COIN SCATTER RNG (the lateral/along-road jitter
## and the per-coin spawn chance). Kept distinct from ROAD_WORLD_SEED so reshaping the
## scatter doesn't move the centerline, and vice-versa.
const ROAD_COIN_SEED: int = 0xC0_1A  # "coin"-ish; arbitrary fixed constant

## Chance that a scattered road coin spawns as a rare purple GEM worth 10 (see
## coin.gd make_gem). Rolled as one extra draw from the same per-station scatter
## RNG right after a coin's position draws, so gem placement is exactly as
## deterministic and seam-correct as the coins themselves.
const ROAD_GEM_CHANCE: float = 0.04

## How fast the band width breathes (radians of cos() per station). Lower = the band
## swells wide and narrows over MORE stations. At 0.08 the cosine's period is
## ~2π/0.08 ≈ 78 stations, so the width cycles slowly enough to feel smooth, not pulsey.
const ROAD_WIDTH_FREQ: float = 0.08

## Difficulty gradient: the coin band NARROWS with distance. Over the first
## ROAD_NARROW_STATIONS stations the oscillating width is lerped toward a floor of
## road_width_min * ROAD_NARROW_FLOOR_FACTOR, so far into a run the coin swath is a
## tight ribbon that demands precise steering to keep the streak alive.
const ROAD_NARROW_STATIONS: int = 2000
const ROAD_NARROW_FLOOR_FACTOR: float = 0.4

## Fraction of road_coin_spacing a coin may jitter ALONG the road from its slice center
## (±this × spacing). Without it, every slice's coins would sit on the same cross-line
## and the eye would read regular rows; this staggers them so the swath looks organic.
const ROAD_COIN_LONG_JITTER: float = 0.5

## THE ROAD'S TERMINAL X — where the coin road stops being the thing you follow
## and the city takes over (bead godot-test1-8gw.3).
##
## The centreline's Z is a function of run_seed (only station 0 is fixed), so a
## road that wandered on would arrive at Budapest's west edge at a different Z
## every run — and Budapest is AUTHORED at a fixed rect. The road therefore ends
## at a TERMINAL STATION west of the gate, and BudapestPlan.road_approach_point()
## eases the corridor from that station's Z to the gate's z = 0 (see
## spawn_approach_coins_in_chunk).
##
## 1450 is 150 m west of the gate (BudapestPlan.GATE.x = 1600) — far enough that
## the last road boss (BOSS_INTERVAL_STATIONS at ~6 m/station) can never be
## standing in the gate district, close enough that the corridor's ease is short
## enough to read as one continuous route rather than a dogleg.
const ROAD_TERMINAL_X: float = 1450.0


# ============================================================================
# COIN ROAD MATH (deterministic, pure-in-k parametric centerline + coin placement)
# ============================================================================
#
# Everything below is a pure function of the station index `k`, ROAD_WORLD_SEED, and
# the per-run run_seed (constant for the whole run). There is no per-chunk RNG and no
# per-frame state, so the road is identical for a given `k` no matter which chunk asks
# for it or in what order — that is what makes the trail seamless across chunk
# boundaries and reproducible on revisit. Only a new seed changes it, and the
# memos derived from it are dropped where that seed is WRITTEN — see
# `_drop_seeded_memos()`.

static func _road_hash01(terrain: Node3D, k: int) -> float:
	"""
	Deterministic pseudo-random float in [0, 1) for station `k`.

	@param k: Station index (may be negative).
	@return: A stable [0,1) value; same `k` always yields the same result.

	EDUCATIONAL NOTE:
	- We mix `k` with the fixed ROAD_WORLD_SEED via Godot's hash(), so the road's
	  randomness is reproducible (no RNG state) yet distinct from the seeds used for
	  blocks/crocodiles. hash() returns a 32-bit-ish int; we fold it into [0,1) by
	  masking to a positive range and dividing by that range's size.
	"""
	# Three ints in a Vector3i give hash() plenty to mix; run_seed rides along as a
	# real third input so each run gets its own road shape (constant within a run).
	var h := hash(Vector3i(k, ROAD_WORLD_SEED, terrain.run_seed))
	# Mask to 24 positive bits and normalise to [0, 1). (Plenty of resolution for an
	# angle, and avoids sign issues from hash() possibly returning negatives.)
	return float(h & 0xFFFFFF) / float(0x1000000)

static func _road_turn(terrain: Node3D, k: int) -> float:
	"""
	Signed per-station turn angle (radians) for station `k`.

	@param k: Station index.
	@return: A deterministic angle in [-road_turn_rate_deg, +road_turn_rate_deg],
	         expressed in radians; this is the heading "jitter" added at station `k`.

	EDUCATIONAL NOTE:
	- _road_hash01 gives [0,1); we remap it to [-1,1] and scale by the configured
	  turn rate. This is the only source of curviness in the path.
	"""
	var signed_unit := _road_hash01(terrain, k) * 2.0 - 1.0  # [0,1) -> [-1,1)
	return deg_to_rad(terrain.road_turn_rate_deg) * signed_unit

static func _road_extend_to_x(terrain: Node3D, x_min: float, x_max: float) -> void:
	"""
	Grow the station cache (in BOTH directions, contiguously from station 0) until the
	cached centerline spans the world X-range [x_min, x_max].

	@param x_min: Smallest world X that must be covered by a cached station.
	@param x_max: Largest world X that must be covered by a cached station.

	EDUCATIONAL NOTE — the heading-integrated recurrence (the heart of the road):
	  heading[k+1] = clamp( heading[k]*(1-ROAD_RESTORE) + turn_noise(k), -CAP, +CAP )
	  center[k+1]  = center[k] + _road_spacing() * Vector2(cos heading[k], sin heading[k])
	The backward step (k-1) MIRRORS this exactly so the cache stays a single pure
	function of `k`: from station k we know heading[k-1] is whatever produced heading[k]
	via the forward rule, but rather than invert the clamp we simply recompute the
	backward heading with the same recurrence using turn_noise(k-1) and the heading we
	are stepping FROM. Concretely, to add station (k-1) we treat (k-1) as the "current"
	station and station k as its "next": heading[k-1] is derived so that stepping it
	forward lands at center[k], and center[k-1] is found by stepping BACKWARD from
	center[k] along heading[k-1]. (See the symmetric construction below.)

	Because |heading| < 90° (asserted), cos(heading) > 0 always, so each forward step
	strictly INCREASES X and each backward step strictly DECREASES it. That monotonicity
	is what makes "extend until we span this X-range" terminate and gives every chunk a
	bounded, contiguous range of stations.
	"""
	# Safety: the whole monotonic-X guarantee depends on the heading staying under 90°.
	# road_max_heading_deg is an @export, so a designer could set it >= 90 — and an
	# assert is STRIPPED in release builds, so it can't be our only guard. If the cap
	# were >= 90, cos(heading) could reach 0 or go negative and the "extend until X
	# reaches the target" while-loops below would stop advancing in X and HANG (or run
	# the road backward). We therefore use a CLAMPED effective cap everywhere in here;
	# the assert stays as a loud editor-time warning, but the clamp is what actually
	# keeps release builds safe. _road_max_heading() returns the same clamped value so
	# every road helper agrees on the cap.
	assert(terrain.road_max_heading_deg < 90.0,
		"road_max_heading_deg must be < 90 so the centerline's X stays strictly increasing")
	# The same termination depends on the STEP distance being strictly positive: a zero or
	# negative road_coin_spacing freezes/reverses X so the while-loops below never reach
	# their target and HANG. Loud editor-time hint; _road_spacing() is the release-safe guard.
	assert(terrain.road_coin_spacing > 0.0,
		"road_coin_spacing must be > 0 so each station strictly advances the centerline's X")

	var max_heading := _road_max_heading(terrain)
	# Clamped effective step distance — strictly positive, so X always advances and the
	# extend loops below terminate. At the default 6.0 this is inert (returns 6.0).
	var spacing := _road_spacing(terrain)

	# First-time seeding: station 0 at world origin, heading along +X (0 rad).
	if terrain.road_k_min > terrain.road_k_max:
		terrain.road_stations = { 0: { "center": Vector2(0.0, 0.0), "heading": 0.0 } }
		terrain.road_k_min = 0
		terrain.road_k_max = 0

	# Grow FORWARD (increasing k) until the last cached station's X reaches x_max.
	# We append station (k+1) computed from station k's center+heading.
	while _road_station(terrain, terrain.road_k_max).center.x < x_max:
		var cur: Dictionary = _road_station(terrain, terrain.road_k_max)
		var cur_heading: float = cur.heading
		# New center: step the (clamped) spacing along the CURRENT heading.
		var next_center: Vector2 = cur.center + spacing * Vector2(cos(cur_heading), sin(cur_heading))
		# New heading for the NEXT step: restore toward +X, add this station's turn, clamp.
		var next_heading: float = clampf(
			cur_heading * (1.0 - ROAD_RESTORE) + _road_turn(terrain, terrain.road_k_max),
			-max_heading, max_heading)
		# O(1) Dictionary insert keyed by the new station index (no array-shift).
		terrain.road_stations[terrain.road_k_max + 1] = { "center": next_center, "heading": next_heading }
		terrain.road_k_max += 1

	# Grow BACKWARD (decreasing k) until the first cached station's X reaches x_min.
	# To prepend station (k-1) we need heading[k-1] and center[k-1] such that stepping
	# station (k-1) FORWARD reproduces station k. We mirror the forward rule:
	#   - heading[k-1] is the heading that, after restore+turn(k-1)+clamp, yields
	#     heading[k]. Inverting the clamp+restore exactly is not generally possible, so
	#     we instead define the backward heading directly with the SAME recurrence shape
	#     using turn_noise(k-1), which keeps the cache a deterministic function of k.
	#   - center[k-1] = center[k] - _road_spacing() * dir(heading[k-1]).
	while _road_station(terrain, terrain.road_k_min).center.x > x_min:
		var first: Dictionary = _road_station(terrain, terrain.road_k_min)
		var first_heading: float = first.heading
		# Reconstruct the heading at (k-1). Forward rule from (k-1) to (k) is:
		#   heading[k] = clamp(heading[k-1]*(1-RESTORE) + turn(k-1), ...)
		# Solve for heading[k-1] (un-clamped form, which is exact whenever heading[k]
		# is off the cap — and on the cap the road is straightened anyway, so the small
		# discrepancy is invisible and, crucially, still fully deterministic in k):
		var prev_heading: float = clampf(
			(first_heading - _road_turn(terrain, terrain.road_k_min - 1)) / (1.0 - ROAD_RESTORE),
			-max_heading, max_heading)
		# Step BACKWARD from the first cached center along the reconstructed heading
		# (same clamped, strictly-positive spacing as the forward step).
		var prev_center: Vector2 = first.center - spacing * Vector2(cos(prev_heading), sin(prev_heading))
		# O(1) Dictionary insert keyed by (k-1) — this is the whole reason the cache is a
		# Dictionary and not an Array: an Array would need push_front here (O(n) shift).
		terrain.road_stations[terrain.road_k_min - 1] = { "center": prev_center, "heading": prev_heading }
		terrain.road_k_min -= 1

static func _road_max_heading(terrain: Node3D) -> float:
	"""
	The EFFECTIVE heading cap in radians: road_max_heading_deg clamped to [0, 89°].

	@return: deg_to_rad(clamp(road_max_heading_deg, 0, 89)).

	EDUCATIONAL NOTE:
	- road_max_heading_deg is an @export a designer can set to anything. The road's
	  monotonic-X guarantee (and thus loop termination in _road_extend_to_x) requires
	  the cap to stay strictly under 90°. Asserts are stripped from release builds, so
	  we ALSO clamp at read time here — every road helper routes its cap through this so
	  a misconfigured export can never make the centerline stall or run backward.
	"""
	return deg_to_rad(clampf(terrain.road_max_heading_deg, 0.0, 89.0))

static func _road_spacing(terrain: Node3D) -> float:
	"""
	The EFFECTIVE per-station step distance (world metres): road_coin_spacing clamped
	to a small positive minimum.

	@return: maxf(road_coin_spacing, 0.1).

	EDUCATIONAL NOTE:
	- road_coin_spacing is an @export a designer can set to anything, but it is the STEP
	  magnitude in the recurrence (center advances by spacing * (cos heading, sin heading)
	  each station). The "extend until the centerline spans this X-range" while-loops in
	  _road_extend_to_x only terminate while X keeps strictly advancing — which requires
	  the step to be strictly POSITIVE. A spacing of 0 freezes X (loop never reaches its
	  target → editor/game HANG); a negative spacing runs X backward (same hang). Asserts
	  are stripped from release builds, so — exactly like _road_max_heading() — we ALSO
	  clamp at read time here and route EVERY road step through this. At the default 6.0
	  the clamp is inert (returns 6.0), so coin positions are unchanged.
	"""
	return maxf(terrain.road_coin_spacing, 0.1)

static func _road_station(terrain: Node3D, k: int) -> Dictionary:
	"""
	Return the cached station Dictionary { center: Vector2, heading: float } for index
	`k`. ASSUMES `k` is within [road_k_min, road_k_max] (callers extend the cache
	first). The cache is a Dictionary keyed directly by `k`, so this is an O(1) lookup.
	"""
	return terrain.road_stations[k]

static func _road_first_k_at_or_after_x(terrain: Node3D, x: float) -> int:
	"""
	Return the smallest cached station index `k` whose centerline X is >= `x`, by binary
	search over [road_k_min, road_k_max]. If every cached station is left of `x`, returns
	road_k_max + 1 (an empty window).

	@param x: World X to search for.
	@return: First station index with center.x >= x (clamped to the cached range).

	EDUCATIONAL NOTE:
	- ASSUMES the cache already spans `x` (callers _road_extend_to_x first) and relies on
	  the road's centerline X being STRICTLY INCREASING in `k` (guaranteed by the < 90°
	  heading cap) — that monotonicity is exactly what makes a binary search valid. This
	  lets a chunk jump straight to its station window in O(log cache) instead of scanning
	  every cached station from road_k_min (which would be O(cache size) = O(distance from
	  origin) on every chunk load).
	"""
	var lo: int = terrain.road_k_min
	var hi: int = terrain.road_k_max
	# Standard lower-bound binary search: narrow toward the first index satisfying
	# center.x >= x. `lo` ends one past the last station strictly left of x.
	while lo <= hi:
		var mid: int = lo + (hi - lo) / 2  # integer division → floor of the midpoint
		if _road_station(terrain, mid).center.x < x:
			lo = mid + 1
		else:
			hi = mid - 1
	return lo

static func _road_terminal_k(terrain: Node3D) -> int:
	"""
	The LAST station of the coin road: the largest `k` whose centreline X is at or
	west of ROAD_TERMINAL_X. Every road CONSUMER stops here (bead godot-test1-8gw.3).

	@return: The terminal station index. Memoized for the run in
	         `_road_terminal_k_cache`, which `set_run_seed()` drops beside the
	         station cache it is derived from (`_drop_seeded_memos()`).

	WHY THE CAP IS ON THE CONSUMERS AND NOT ON _road_extend_to_x.
	It would be tempting to simply stop growing the cache past the terminal. That
	HANGS the game. _road_extend_to_x's forward loop runs `while` the cached X has
	not yet reached the requested x_max — a cache that refuses to grow past T never
	reaches any x_max east of T and spins forever. And all three binary-search
	callers (_road_first_k_at_or_after_x's own contract, the coin scan and the boss
	scan) ASSUME the cache spans whatever X they asked for; a short cache silently
	answers them with the terminal station for every chunk in the city. So the
	centreline cache stays infinite and honest — it is the five things that READ it
	(road coins, road clearance, road bosses, the minimap line, and the
	FIELD_ALTITUDE spike's flat corridor `_alt_road_segments`) that stop at T.

	The definition is the one the machinery already provides: extend so the cache
	covers T, binary-search the first station at or after T, and step back one. The
	road's X is strictly increasing in `k`, so that is exactly "the last station at
	or west of T" and there is no edge case in between.
	"""
	if terrain._road_terminal_k_cache != terrain.ROAD_TERMINAL_K_UNSET:
		return terrain._road_terminal_k_cache
	_road_extend_to_x(terrain, ROAD_TERMINAL_X, ROAD_TERMINAL_X)
	terrain._road_terminal_k_cache = _road_first_k_at_or_after_x(terrain, ROAD_TERMINAL_X) - 1
	return terrain._road_terminal_k_cache

static func _road_width(terrain: Node3D, k: int) -> float:
	"""
	Smoothly-varying coin BAND width (metres) at station `k`, oscillating between
	road_width_min and road_width_max.

	@param k: Station index.
	@return: Width in [road_width_min * ROAD_NARROW_FLOOR_FACTOR, road_width_max]
	         (the upper reaches only near the origin; distance narrows the range).

	EDUCATIONAL NOTE:
	- A low-frequency cosine of `k` gives a slow, smooth swell/narrowing of the band
	  (no per-station jumps), so the coin swath visibly breathes wide and narrow as you
	  travel. We remap cos()'s [-1,1] to [0,1] then lerp between the bounds.
	- Difficulty gradient: the whole band then narrows with distance, lerping toward
	  road_width_min * ROAD_NARROW_FLOOR_FACTOR over the first ROAD_NARROW_STATIONS
	  stations. Still a pure function of `k`, so determinism within a run holds. The
	  seam-scan `pad` in spawn_coins_in_chunk stays a safe upper bound: narrowing only
	  ever SHRINKS the band below maxf(road_width_min, road_width_max).
	"""
	var t := (cos(float(k) * ROAD_WIDTH_FREQ) + 1.0) * 0.5  # smooth [0,1], period ~78 stations
	var width := lerpf(terrain.road_width_min, terrain.road_width_max, t)
	var narrow_t := clampf(float(absi(k)) / float(ROAD_NARROW_STATIONS), 0.0, 1.0)
	return lerpf(width, terrain.road_width_min * ROAD_NARROW_FLOOR_FACTOR, narrow_t)

static func _road_coins_at(terrain: Node3D, k: int) -> Array:
	"""
	Deterministic list of world-space coin positions SCATTERED across the road band at
	station `k`. Replaces the old one-coin-on-a-smooth-weave model: instead of a single
	coin on a tidy line, each station drops a few coins at RANDOM lateral offsets within
	±band/2 of the centerline (plus a little along-road jitter), so the road reads as a
	loose swath of territory a few coins wide rather than an obvious conga-line.

	@param k: Station index (the cache MUST already cover it — callers extend first).
	@return: Array of { "pos": Vector3, "gem": bool } dictionaries "owned" by station
	         `k` — `pos` is the world-space coin position, `gem` marks the rare purple
	         gem variant (ROAD_GEM_CHANCE). May be EMPTY when the per-coin spawn rolls
	         come up short — that is exactly what keeps the trail sparse and irregular.
	         Three slots in ten are then dropped outright by the 30% thinning at the
	         bottom of the loop; see there for why that lives here and not on the
	         station spacing.

	EDUCATIONAL NOTE — why this stays deterministic & seam-correct:
	- The scatter RNG is seeded ONLY from `k` (+ ROAD_COIN_SEED + the run-constant
	  run_seed), so a station's coins are
	  identical no matter which chunk computes them or in what order — the property the
	  seam bucketing in spawn_coins_in_chunk relies on. Each coin is still assigned to
	  whichever chunk its FINAL position lands in, so there are no gaps or duplicates.
	- A coin's offset from the centerline is bounded by band/2 (lateral) plus
	  ROAD_COIN_LONG_JITTER*spacing (along-road); spawn_coins_in_chunk's `pad` is derived
	  from exactly that bound so the scan window can never miss a scattered coin at a seam.
	"""
	# CAP 1 OF 5 — the road's coins stop at the terminal station (bead
	# godot-test1-8gw.3). Past T the coin line is the city's authored approach
	# corridor instead (spawn_approach_coins_in_chunk), so a road coin here would
	# be a second, wandering trail crossing the avenue.
	#
	# The cap is on this CONSUMER and not on _road_extend_to_x because that
	# function's forward loop only terminates while the cached X keeps advancing
	# toward the requested x_max — refusing to grow past T hangs it outright, and
	# its three binary-search callers all assume the cache spans any X. Skipping a
	# station perturbs no other station: every station's scatter RNG is seeded from
	# `k` alone, so there is no shared stream here to keep in step.
	if k > _road_terminal_k(terrain):
		return []

	var st: Dictionary = _road_station(terrain, k)
	var center: Vector2 = st.center
	var heading: float = st.heading
	# Unit vectors ALONG (tangent) and PERPENDICULAR (left-hand normal) to the heading,
	# in the XZ plane. Vector2.x -> world X, Vector2.y -> world Z.
	var tangent := Vector2(cos(heading), sin(heading))
	var perp := Vector2(-sin(heading), cos(heading))
	var half_band := _road_width(terrain, k) * 0.5

	# Per-station RNG seeded purely from `k` (+ a coin-specific seed + this run's seed):
	# deterministic and load-order independent within a run. The draw order below is
	# fixed, so the coin set is stable; new_run() re-rolls run_seed for a fresh scatter.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k, ROAD_COIN_SEED, terrain.run_seed))

	var coins: Array = []
	for slot in terrain.road_coin_slots:
		# Rolling each slot (rather than always placing a coin) is what makes the swath
		# sparse and irregular instead of a regular grid. A skipped slot still consumes
		# one draw, so the RNG sequence — and thus every later coin — stays deterministic.
		if rng.randf() >= terrain.road_coin_chance:
			continue
		var lat := rng.randf_range(-1.0, 1.0) * half_band                               # across the band
		var lon := rng.randf_range(-1.0, 1.0) * ROAD_COIN_LONG_JITTER * _road_spacing(terrain)  # along the road
		var p := center + perp * lat + tangent * lon
		# One extra draw AFTER the position: is this coin a rare gem? The draw order
		# (chance, lat, lon, gem) is fixed, so the whole station stays deterministic.
		var gem := rng.randf() < ROAD_GEM_CHANCE
		# THE 30% THINNING (owner, 2026-09-02, bead godot-test1-7ed: "scale down
		# amount of coins, 30% less"), and it is here rather than on
		# road_coin_spacing DELIBERATELY. That export is the road's STATION STEP,
		# not a coin gap: _road_extend_to_x integrates the centerline by it, so
		# widening it to 8.6 would move every station, every boss (which owns every
		# BOSS_INTERVAL_STATIONS-th one), and the terminal station the city's
		# approach corridor hangs off. So the SPACING IS UNTOUCHED and the coin is
		# thinned PER STATION instead.
		#
		# A POST-DRAW SKIP, exactly like the river/spawn-bubble rejections in
		# spawn_crocodiles_in_chunk: all four of this slot's draws are already spent
		# above, and the test itself is a pure function of (k, slot) that costs the
		# stream nothing. The surviving coins therefore sit byte-for-byte where they
		# always sat — this drops 3 of every 10 slots, it does not re-scatter the
		# road. posmod because stations west of the origin have negative k.
		#
		# Interleaving on (k * slots + slot) rather than on `slot` alone is what
		# keeps the pattern from landing on the same slot index every station (which
		# at road_coin_slots == 3 would thin one third of the band's WIDTH instead of
		# one third of its coins): over any 10 consecutive stations the residues 0..29
		# are hit once each, so exactly 9 of 30 slots go.
		if posmod(k * terrain.road_coin_slots + slot, 10) < 3:
			continue
		coins.append({ "pos": Vector3(p.x, terrain.COIN_GROUND_HEIGHT, p.y), "gem": gem })
	return coins

static func _road_lateral_distance(terrain: Node3D, world_x: float, world_z: float, clearance: float) -> float:
	"""
	Minimum distance (world metres, XZ plane) from the point (world_x, world_z)
	to any road centerline station near it. Used by artifact placement to keep
	landmarks off the coin road (see ARTIFACT_ROAD_CLEARANCE) and by biome
	geometry to keep the coin swath clear (see _biome_spot_ok).

	@param world_x, world_z: World-space point to test.
	@param clearance: The distance the caller is about to compare against. Only
	                  used to size the scan window — pass the SAME value you test
	                  with, or the answer may be capped short of it. Deliberately
	                  has NO default: a default is exactly the footgun this
	                  parameter exists to close.
	@return: Distance to the nearest scanned station centre, or INF when no
	         station falls in the scan window (the point is far off-road in X —
	         "very far from the road" and "no road here" both mean "clear").

	EDUCATIONAL NOTE:
	- We only need to know whether the point is WITHIN `clearance` of the
	  centerline, so scanning the stations inside a padded X-window around the
	  point suffices: any station outside that window is already further away in X
	  alone than the clearance we test against. The pad adds two station spacings
	  so the sampled polyline can't cut a corner past the window edge. Deriving the
	  pad from the caller's own clearance is what keeps that guarantee true for
	  every caller — an earlier version hardcoded ARTIFACT_ROAD_CLEARANCE, which
	  left MOUNTAIN_ROAD_CLEARANCE (24) a hair under the honest-answer bound.
	- Same manual-counter scan as spawn_coins_in_chunk — NOT `for k in range(...)`,
	  which would eagerly materialise an O(total cached suffix) int Array per call
	  just to visit a handful of stations (see the allocation note there).
	- Reads only the station cache (pure in `k`), so the answer for a given point
	  is deterministic and load-order independent.
	"""
	var pad := clearance + _road_spacing(terrain) * 2.0
	_road_extend_to_x(terrain, world_x - pad, world_x + pad)

	var best := INF
	var k := _road_first_k_at_or_after_x(terrain, world_x - pad)
	# CAP 2 OF 5 — the road's CLEARANCE stops at the terminal station too (bead
	# godot-test1-8gw.3): east of T there is no road, so nothing out there should be
	# shoved aside to keep a coin swath clear that does not exist. Past T the scan
	# window is empty and this returns INF, which every caller already reads as
	# "nowhere near the road" — the same answer it has always given for a point far
	# off-road in X, so no caller needed an edit. The ONE stretch that still wants a
	# clear swath is the approach corridor, added back below the loop.
	#
	# The cap is on this CONSUMER and not on _road_extend_to_x: that function's
	# forward loop hangs if the cache stops growing (see _road_terminal_k), and the
	# _road_extend_to_x call above is what makes the binary search below valid.
	var k_last := mini(terrain.road_k_max, _road_terminal_k(terrain))
	while k <= k_last:
		var st: Dictionary = _road_station(terrain, k)
		k += 1
		if st.center.x > world_x + pad:
			break  # past the window — X only grows from here, so stop
		var d := Vector2(world_x, world_z).distance_to(st.center)
		if d < best:
			best = d
	# CAP 2's ONE SEAM — between the terminal station and the gate the APPROACH
	# CORRIDOR carries the trail (spawn_approach_coins_in_chunk), so it inherits the
	# clearance the road used to give this stretch. Drop it and a massif, a forest,
	# a camp or a geo landmark can be generated straight across the walk into
	# Budapest: massifs are climbable: false, so _settle_coin_y skips every coin
	# behind one and the line into the city dead-ends against a wall. East of the
	# gate there is nothing to keep clear — in_budapest() has already turned every
	# one of those spawners off inside the rect.
	#
	# Asked as a distance to the corridor as a CURVE — BudapestPlan.road_approach_distance,
	# the same pure geometry the coin line rides, so the swath and the coins stay
	# on one centreline with no second copy of the corridor here. NOT the corridor
	# point at this candidate's own X: the road's Z at the terminal is seeded and
	# the smoothstep can be far steeper than 45 degrees, on which a same-X reading
	# overstates the distance by sqrt(1 + slope^2) and waves a massif through at a
	# few metres (see that function).
	# The window is the corridor's own X span WIDENED BY THE CLEARANCE, because the
	# nearest point of a curve is not at the candidate's X: a candidate `clearance`
	# metres west of the terminal can still be inside the swath, and one further
	# west than that cannot be (the corridor's X never goes below the terminal's).
	if world_x > ROAD_TERMINAL_X - clearance and world_x < BudapestPlan.GATE.x + clearance:
		var terminal: Vector2 = _road_station(terrain, _road_terminal_k(terrain)).center
		# THE Z REJECT IS NOT AN OPTIMIZATION FOR ITS OWN SAKE. road_approach_distance
		# walks ~150 polyline segments, and this runs once per PLACEMENT CANDIDATE —
		# _spawn_forest_content alone tries up to FOREST_TREES_MAX per chunk — on the
		# handful of chunk columns either side of T, which are exactly the frames the
		# player is walking into Budapest on. The corridor's Z never leaves
		# [min(terminal.z, GATE.z), max(...)], so a point outside that span grown by
		# `clearance` is provably further than `clearance` away and skipping it can
		# only leave `best` capped short of the clearance — which this function's
		# contract above already says may happen, and which its one caller
		# (_biome_spot_ok, comparing `< clearance`) cannot tell apart.
		var lo := minf(terminal.y, BudapestPlan.GATE.z) - clearance
		var hi := maxf(terminal.y, BudapestPlan.GATE.z) + clearance
		if world_z > lo and world_z < hi:
			best = minf(best, BudapestPlan.road_approach_distance(terminal, Vector2(world_x, world_z)))
	return best

static func spawn_coins_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Lay this chunk's slice of the COIN ROAD — the single continuous, deterministic
	trail that carries every coin in the world (see the COIN ROAD math section above
	and the COIN ROAD CONFIGURATION section near the top).

	The road centerline is a pure, deterministic function of the integer station index
	`k`. Each station then SCATTERS a few coins at random offsets within a band around
	the centerline (see _road_coins_at), so the trail reads as a loose swath of territory
	a few coins wide — not a single line — while still being a clear "go this way" route.
	Off-road areas get NO coins. Everything is seeded only from `k` (+ the road seeds), so
	it regenerates byte-identically and is seam-correct.

	@param chunk_pos: Chunk coordinates this body is generating coins for.
	@param parent_chunk: The chunk mesh the coins attach to (it sits at the chunk
	                     center, so we store coin positions chunk-LOCAL — relative to
	                     that center — exactly like blocks/crocodiles).
	@param obstacles: Block footprints (with their top heights) from
	                  spawn_objects_in_chunk, used to perch a road coin on a climbable
	                  block (or skip it) when the road runs through a block footprint.

	EDUCATIONAL NOTE — why this is seam-correct (no gaps, no duplicates):
	- The road is global and station-indexed, but each chunk generates independently.
	  A station whose coin lands exactly on a chunk seam must be spawned by EXACTLY
	  one chunk. We guarantee that by bucketing each coin to the chunk its FINAL world
	  position falls in: `world_to_chunk(coin_world) == chunk_pos`. Every other chunk
	  that scans the same station skips it, so it is spawned once and only once.
	- Because |heading| < 90° keeps the centerline's world X strictly increasing in
	  `k`, a chunk's X-range maps to a CONTIGUOUS range of stations. We extend the
	  shared station cache to span this chunk's (widened) X-range, then scan it.
	- Off-road is empty: only stations whose coin actually lands inside this chunk
	  spawn anything, so far-from-road chunks spawn zero coins.
	"""
	if not terrain.spawn_coins or terrain.coin_scene == null:
		return

	# This chunk's world center and its world X-range. We pad the range because a
	# station's CENTERLINE can sit just outside the chunk while one of its scattered coins
	# falls back inside it — widening the scanned X-range makes sure we never miss such a
	# coin (a missed coin = a permanent gap, since no other chunk would scan that station).
	#
	# SEAM-CORRECTNESS INVARIANT: pad MUST be >= the largest amount a scattered coin's WORLD
	# X can differ from its station's centerline X. A coin is offset up to band/2
	# PERPENDICULAR to the heading and up to ROAD_COIN_LONG_JITTER*spacing ALONG it. The X
	# projections of those (sin·lat and cos·lon) are each bounded by their magnitude, so the
	# worst-case X excursion is band/2 + ROAD_COIN_LONG_JITTER*spacing. The band's largest
	# value is maxf(road_width_min, road_width_max) — NOT bare road_width_max — so a designer
	# swapping the bounds (min > max) still can't under-pad. We DERIVE pad from exactly that
	# geometry (plus a small margin) so the invariant survives retuning of width OR spacing.
	var center: Vector3 = terrain.chunk_to_world(chunk_pos)
	var half_chunk: float = terrain.chunk_size / 2.0
	var x0: float = center.x - half_chunk
	var x1: float = center.x + half_chunk
	var pad := maxf(terrain.road_width_min, terrain.road_width_max) * 0.5 + ROAD_COIN_LONG_JITTER * _road_spacing(terrain) + 2.0

	# Grow the shared station cache so it covers this chunk's widened X-range. The
	# cache is a pure function of `k`, so this is idempotent across chunks and load
	# order doesn't matter — it just grows contiguously and is reused.
	_road_extend_to_x(terrain, x0 - pad, x1 + pad)

	# Find the FIRST station whose centerline X is >= the window start by binary search.
	# Because X is strictly increasing in `k`, the window of stations covering this chunk
	# is a contiguous range, and we can jump straight to its start instead of scanning
	# the whole cache from road_k_min (which would be O(total cache) = O(distance from
	# origin) every chunk load — a latent web-perf regression). The loop over the window
	# then touches only O(window) stations, independent of how far the road has grown.
	#
	# WHY a `while` (NOT `for k in range(k_start, road_k_max + 1)`): in GDScript `range(a, b)`
	# eagerly MATERIALISES a full Array of every int in [a, b) before the loop body runs.
	# Even though we `break` the instant a station's X passes the window, that array is
	# already allocated at size O(road_k_max - k_start) = O(total cached suffix). After the
	# player runs far in +X (road_k_max large) then backtracks/respawns to an early chunk
	# (small k_start), every one of up to ~121 chunk loads per boundary crossing would alloc
	# a huge int array just to visit a handful of stations — defeating the O(window) intent
	# and churning memory. A manual counter allocates nothing, so the early break makes the
	# scan truly O(window) in BOTH iteration AND allocation. Same stations, same order →
	# byte-identical coins.
	# THIS CHUNK'S FIELD BRIDGES, looked up ONCE for the whole coin scan rather
	# than per coin (bead godot-test1-06o.2). A coin that lands on a deck rides
	# the deck; every other coin takes the ground rule below, untouched.
	var bridges: Array = terrain.field_bridges_near(x0 - pad, x1 + pad) if terrain.spawn_field_bridges else []

	var k_start := _road_first_k_at_or_after_x(terrain, x0 - pad)
	# We index stations with the captured `cur_k` and advance the cursor `k` once at the
	# TOP of every iteration (before any `continue`), so both early-skip paths below still
	# move forward — a `while` has no implicit step, so a `continue` past an unincremented
	# counter would spin forever. The `break` (window exhausted) exits outright, no step
	# needed. Iteration order over k is identical to the old `for k in range(...)`.
	var k := k_start
	while k <= terrain.road_k_max:
		var cur_k := k
		k += 1
		var st: Dictionary = _road_station(terrain, cur_k)
		var cx: float = st.center.x
		if cx > x1 + pad:
			break  # past this chunk's window — and X only grows from here, so stop

		# This station scatters a handful of coins across the band; place each one that
		# actually lands inside THIS chunk. Each entry is { "pos": Vector3, "gem": bool }.
		for cw in _road_coins_at(terrain, cur_k):
			var cw_pos: Vector3 = cw.pos
			# Bucket by final chunk: spawn this coin only from the chunk it actually lands
			# in. This is what makes seams gap-free and duplicate-free.
			if terrain.world_to_chunk(cw_pos) != chunk_pos:
				continue

			# Convert to chunk-LOCAL (relative to the chunk center, like every other
			# chunk-parented node), so the coin sits at the right world spot.
			var local := Vector3(cw_pos.x - center.x, cw_pos.y, cw_pos.z - center.z)

			# Perch-or-skip against the chunk's block footprints. The rule lives in
			# _settle_coin_y (ONE home, shared with artifact reward coins so the two
			# spawners can never drift apart); INF means "skip this coin".
			local.y = terrain._settle_coin_y(local.x, local.z, local.y, obstacles)
			if is_inf(local.y):
				continue

			# ...and against THE TOWER, which is authored geometry and therefore in
			# no chunk's `obstacles` list for _settle_coin_y to have seen. Same
			# post-draw `continue`, same rule (a coin inside stone is dropped, not
			# moved) — see tower_blocks_coin for why the road is filtered here
			# rather than excluded wholesale.
			if terrain.tower_blocks_coin(cw_pos.x, local.y, cw_pos.z):
				continue

			# ...and LAST, the field bridge: a coin standing over a deck rides the
			# deck instead of the river bed under it (bead godot-test1-06o.2), at
			# the ramp's own height where the deck is climbing. The city's deck
			# line is the precedent (_place_city_coin) and this is its one
			# difference: `_settle_coin_y` still ran, ABOVE. There it is skipped
			# because the perch rule is about the ground under a column and a
			# 12 m deck has none — here a road boss stands ON the crossing (a
			# river station dispatches the crocodile), and its footprint is the
			# one thing under a deck that must still refuse a coin outright.
			# enemy_spawn_selfcheck check 14 is what that ordering keeps green.
			for row_v: Variant in bridges:
				var deck_y: float = terrain._field_bridge_surface_on(row_v, cw_pos)
				if deck_y > -INF:
					local.y = deck_y + terrain.COIN_GROUND_HEIGHT
					break

			# Spawn the coin (position is local to the chunk, like blocks/crocodiles).
			# A gem entry is upgraded BEFORE entering the tree (make_gem recolours a
			# duplicated material and scales the whole pickup — see coin.gd).
			var coin = terrain.coin_scene.instantiate()
			coin.position = local
			if cw.gem:
				coin.make_gem()
			parent_chunk.add_child(coin)
