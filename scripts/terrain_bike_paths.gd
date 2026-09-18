class_name BikePaths
extends RefCounted
## ============================================================================
## THE BICYCLE PATHS — short seeded strips laid across the field biomes
## ============================================================================
## Epic `godot-test1-z2yv`, child `.1`. Owner, 2026-09-18 (Russian, paraphrased):
## *"in our field biomes there should be BICYCLE PATHS stretched here and there,
## with various TRAFFIC LIGHTS and ROAD SIGNS along them"*.
##
## This bead ships the PATHS and nothing that stands on them: a strip, a dashed
## centre line and bare poles. The four authored sign kinds and the cycling
## traffic head are `.2`; the bike-stand rack at each end is `.3`; the rental
## bike itself is a later epic. Everything here is built so those three can hang
## off a marker instead of re-deriving a position.
##
## A `class_name`d library of STATIC functions that RECEIVES the terrain as its
## first argument and calls `terrain.create_box` / `terrain.scarcity_at` /
## `terrain.world_to_chunk` back through the reference — the `terrain_features.gd`
## / `terrain_waypoints.gd` / `coin_road.gd` idiom, and the eleventh family to be
## written in it. `extends RefCounted` and everything `static`: this is a
## namespace, not a node. `terrain` is typed `Node3D` for `landmark_builders.gd`'s
## reason — `endless_terrain.gd` declares no `class_name`.
##
## ----------------------------------------------------------------------------
## THE SHAPE: A POLYLINE SEEDED AT ITS ORIGIN CHUNK, NOT PER-CHUNK SEGMENTS
## ----------------------------------------------------------------------------
## `_bike_path_at(terrain, origin)` is a pure function of (origin chunk,
## `run_seed`) on its OWN salt and its OWN coordinate primes — the ARTIFACT /
## CAMP / CHEST idiom (`terrain_features.gd`'s `_camp_at`, whose docstring writes
## the determinism contract out in full). It rolls the whole path at once: a
## rarity roll, a start point, a heading, a length, and then a heading-integrated
## walk that lays `BIKE_STATION_SPACING`-metre stations until the length runs out
## or a station is BLOCKED.
##
## EVERY CHUNK WITHIN REACH OF AN ORIGIN EVALUATES THE SAME FUNCTION and draws
## only the segments whose MIDPOINT lies in itself. That is the coin road's rule
## one family along, and it is what dissolves the seam problem: geometry may
## overhang a chunk edge, nothing is ever cut, and a chunk loaded on its own
## draws exactly what it would have drawn beside its neighbours.
##
## ----------------------------------------------------------------------------
## NOT ONE DRAW FROM ANY EXISTING STREAM
## ----------------------------------------------------------------------------
## Everything here comes from this family's own salt + primes, from its own turn
## hash, or from a PRIVATE fixed-seed builder generator. The shared chunk / biome
## / coin / crocodile streams are the sequences they were before bike paths
## existed, which is why `spawn_bike_paths = false` yields a byte-identical world
## — `bike_path_selfcheck` check 1 is that statement, measured through the
## shipped `create_chunk` on both sides.
##
## ----------------------------------------------------------------------------
## BLOCKED = TRUNCATED, NEVER GAPPED
## ----------------------------------------------------------------------------
## `station_blocked()` is PURE in (position, seed), so every chunk that evaluates
## an origin truncates its path at the SAME station — which is the only reason a
## per-chunk draw of a shared polyline can agree with itself at all. The walk
## keeps the prefix and stops; it never resumes past the block, and a path left
## shorter than `BIKE_PATH_MIN_STATIONS` is dropped whole. No river crossings and
## no road crossings: the field bridges are k-indexed ROAD machinery, and a
## crossing would put road coins on the strip.
##
## ----------------------------------------------------------------------------
## CUBE ONLY, AND ZERO NEW MULTIMESH BUCKETS
## ----------------------------------------------------------------------------
## Every box below is `ChunkBatch.BoxKind.CUBE`. A `CYLINDER` mast (the city
## band's choice for its signal masts) would be +1 draw call on every
## PLAINS/SNOW/FOREST chunk that carries a path, and the epic refuses it:
## `batch_selfcheck` check 5's `KIND_CAP_BY_NAME` table needs no row changed, and
## `bike_path_selfcheck` check 5 makes that unfailable rather than a promise.
##
## ----------------------------------------------------------------------------
## THE MEMO LIVES ON THE TERRAIN NODE
## ----------------------------------------------------------------------------
## `_bike_path_cache` is declared in `endless_terrain.gd` and reset in
## `_drop_seeded_memos()`, like every other seeded memo (`_landmark_sites_cache`,
## `_field_bridge_cache`). NOT a `static var` here: memo state a
## `_drop_seeded_memos()` cannot reach survives every re-seed and hands a
## multiplayer joiner the wrong world — `chunk_stream_selfcheck` check 6c fails
## the build for it.

# ============================================================================
# THE SEED: THIS FAMILY'S OWN SALT AND ITS OWN COORDINATE PRIMES
# ============================================================================
#
# The primes are NEW. Already spoken for elsewhere in this world engine:
# 73856093/19349663 (artifacts), 83492791/15485863 (the biome offset),
# 40960001/26463089 (camps), 96174811/18266587 (the scarcity roll),
# 86028121/50331653 (chests), 40499/86969 and 83492791/28411639 (predators).
# Sharing a pair would correlate two features: a chunk that hosts a camp would
# thereby be likelier (or never) to host a path, which is the one thing an
# independent stream exists to prevent.
const BIKE_HASH_PRIME_X: int = 32452843
const BIKE_HASH_PRIME_Y: int = 49979687

## "BIKE PATH"-ish; arbitrary fixed constant, XORed into `run_seed` so this
## family's stream is its own even where the primes would agree.
const BIKE_PATH_SALT: int = 0xB1_1E9A7

## The TURN hash's own salt and primes — see `_bike_turn()` for why this family
## may not call `CoinRoad._road_turn`.
const BIKE_TURN_SALT: int = 0xB1_1E70A
const BIKE_TURN_PRIME_X: int = 27644437
const BIKE_TURN_PRIME_Y: int = 6291469
const BIKE_TURN_PRIME_I: int = 12582917

# ============================================================================
# THE PATH'S SHAPE
# ============================================================================

## Chance of a path at an origin chunk BEFORE scarcity thins it. Read with the
## epic's "here and there": at k = 1 (the HQ corridor and the city) roughly one
## chunk in twelve starts a path, and since a path crosses several chunks the
## corridor reads as furnished rather than as a scatter of stubs.
const BIKE_PATH_CHANCE: float = 0.085

## Metres between stations. The strip is one box per SEGMENT, so this is also the
## strip's box length and the granularity the truncation speaks in.
const BIKE_STATION_SPACING: float = 5.0

## A path shorter than this after truncation is dropped whole: a two-station stub
## is litter, not a bicycle path.
const BIKE_PATH_MIN_STATIONS: int = 6

## ...and the longest one a roll can produce: 24 stations is ~115 m of strip.
const BIKE_PATH_MAX_STATIONS: int = 24

## THE SCAN RADIUS ARITHMETIC, written down because getting it wrong is the exact
## bug this whole shape exists to prevent. A path reaches at most
## BIKE_PATH_MAX_STATIONS * BIKE_STATION_SPACING metres from its origin chunk, so
## a chunk must evaluate every origin within that many metres of itself or a path
## silently truncates at a chunk seam — the one failure mode that looks like a
## content bug rather than a crash. A max-station count that outgrows the radius
## is therefore a two-line edit, and `scan_radius_chunks()` derives the second
## line from the first so it cannot be forgotten.
const BIKE_PATH_MAX_REACH: float = BIKE_PATH_MAX_STATIONS * BIKE_STATION_SPACING

## Per-station turn, degrees. The walk is a bounded random walk about the path's
## INITIAL heading (see `_bike_path_at`), so this is a gentle bend over the whole
## length rather than a wiggle you can see between two stations.
const BIKE_TURN_RATE_DEG: float = 7.0

## How hard the heading is pulled back toward the path's initial bearing each
## station, and how far it may ever stray from it. Without them a 24-station
## random walk can curl back on itself and cross its own strip.
const BIKE_HEADING_RESTORE: float = 0.12
const BIKE_MAX_HEADING_DEG: float = 42.0

# ============================================================================
# BLOCKING — the tests a station must pass, cheapest first
# ============================================================================

## How far a station must stay from the coin road's centreline. THE SAME NUMBER
## as `TerrainFeatures.ARTIFACT_ROAD_CLEARANCE`, deliberately: the coin swath is
## one width, and a second opinion about it would put a bike path under the
## road's coins.
const BIKE_ROAD_CLEARANCE: float = 14.0

## Extra margin around a waypoint circle. `TerrainWaypoints.RING_RADIUS` is the
## paint; a strip that stopped exactly at the rim would still read as running
## into it, so the station clears the disc by a stride.
const BIKE_WAYPOINT_MARGIN: float = 3.0

# ============================================================================
# THE GEOMETRY
# ============================================================================

## The strip: 2.4 m wide (two bikes abreast) and 6 cm proud of the ground — paint
## you walk over, not a kerb you trip on.
const BIKE_PATH_WIDTH: float = 2.4
const BIKE_PATH_THICKNESS: float = 0.06

## The dashed centre line, one short box per station, sitting ON the strip.
const BIKE_DASH_LENGTH: float = 1.6
const BIKE_DASH_WIDTH: float = 0.16
const BIKE_DASH_THICKNESS: float = 0.03

## The poles: a square post beside the strip, every `BIKE_POLE_STRIDE` stations.
## A FIXED STRIDE and not a roll, so `.2` has a deterministic set of sites to
## hang sign plates and traffic heads on.
const BIKE_POLE_STRIDE: int = 4
const BIKE_POLE_WIDTH: float = 0.16
const BIKE_POLE_HEIGHT: float = 2.6
## How far the post's centre stands off the strip's centre line.
const BIKE_POLE_OFFSET: float = BIKE_PATH_WIDTH * 0.5 + 0.45
## The footprint radius a post claims. The half-diagonal of the post plus a hand's
## width, the `_camp_hut` convention — a yawed square under-covers its own corner.
const BIKE_POLE_RADIUS: float = BIKE_POLE_WIDTH * 0.71 + 0.15

## Brick red, the colour Budapest paints its bike lanes; bone white for the dashes
## and a cool grey for the posts.
const BIKE_STRIP_COLOR: Color = Color(0.55, 0.26, 0.20)
const BIKE_DASH_COLOR: Color = Color(0.88, 0.87, 0.82)
const BIKE_POLE_COLOR: Color = Color(0.44, 0.45, 0.47)

# ============================================================================
# THE MARKER
# ============================================================================

## The bare Node3D this family leaves in a chunk, found BY GROUP the way every
## system in this project finds things. `.2` hangs sign plates and traffic heads
## off it and `.3` hangs the stand off the path's ends.
const BIKE_PATH_GROUP: String = "bike_path"
const BIKE_PATH_MARKER_NAME: String = "BikePathMarker"

## The memo's ceiling, in origins. An endless walk visits unboundedly many
## origins, so the dictionary is CLEARED WHOLE when it passes this — safe because
## the function is pure and a dropped entry rebuilds identically, and cheaper
## than an LRU nobody would maintain. 4096 origins is ~10 km square of field at
## chunk_size 50, comfortably more than a session ever has resident.
const BIKE_MEMO_CAP: int = 4096


# ============================================================================
# PLACEMENT — the pure function of (origin chunk, run_seed)
# ============================================================================

static func scan_radius_chunks(terrain: Node3D) -> int:
	"""
	How many chunks out a chunk must look for the origins whose paths can reach it.

	@param terrain: The `EndlessTerrain`, for `chunk_size`.
	@return: The half-width of the scan square, in chunks.

	Derived from `BIKE_PATH_MAX_REACH` rather than typed, so a longer path cannot
	outgrow the scan and truncate at chunk seams — see that constant's note. The
	`+ 1` covers the start offset, which may put the first station anywhere inside
	the origin chunk rather than at its centre. With chunk_size 50 and a 120 m
	path this is 4, so 9x9 = 81 memo lookups per chunk, each a dictionary hit or
	one hash and an early-out.
	"""
	return int(ceil(BIKE_PATH_MAX_REACH / terrain.chunk_size)) + 1


static func bike_path_at(terrain: Node3D, origin: Vector2i) -> Array[Dictionary]:
	"""
	THE PATH THAT STARTS IN `origin`, memoized on the terrain node.

	@param origin: The candidate origin chunk.
	@return: The path's stations as `{ "pos": Vector2 (world XZ), "heading": float
	         (radians) }` in walk order, or `[]` for the overwhelming majority of
	         chunks. Read-only to callers — it is the cache entry itself, because
	         it is asked once per chunk per origin in reach.

	The memo lives on the TERRAIN (`_bike_path_cache`, dropped by
	`_drop_seeded_memos()`), never on this static family: see the banner.
	"""
	var cache: Dictionary = terrain._bike_path_cache
	if cache.has(origin):
		return cache[origin]
	# CAP AND CLEAR, not evict: the function is pure, so a dropped entry rebuilds
	# identically and the only cost of being wrong is one recomputation.
	if cache.size() > BIKE_MEMO_CAP:
		cache.clear()
	var path: Array[Dictionary] = _bike_path_at(terrain, origin)
	cache[origin] = path
	return path


static func _bike_path_at(terrain: Node3D, origin: Vector2i) -> Array[Dictionary]:
	"""
	Roll and walk the path at `origin`. `_camp_at` / `_artifact_at` for a polyline.

	@param origin: The origin chunk to decide for.
	@return: The station list, or `[]`.

	THE DETERMINISM CONTRACT, the same one `_camp_at`'s docstring writes out:
	- INDEPENDENT STREAM. A private RNG on this family's own salt and its own
	  coordinate primes. No draw from the shared chunk RNG is consumed, inserted
	  or moved, so every existing block, crocodile and coin stays where it was.
	- WITHIN A RUN. The same origin yields the identical path however often its
	  chunks unload and regenerate, and every chunk in reach of it agrees, because
	  the walk and every blocking test are pure in (position, `run_seed`).
	- ACROSS RUNS. `new_run()` re-rolls `run_seed`, so the paths land elsewhere.

	THE DRAW ORDER IS FIXED AND IS PART OF THE WORLD: (a) the rarity roll, (b) the
	start offset inside the origin chunk, (c) the heading, (d) the length in
	stations. Never reorder them and never insert one — an extra draw here moves
	every bike path in the world, which is CLAUDE.md's rule applied to this
	family's own stream rather than to the shared one.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(origin.x * BIKE_HASH_PRIME_X, origin.y * BIKE_HASH_PRIME_Y,
			terrain.run_seed ^ BIKE_PATH_SALT))

	# (a) THE RARITY ROLL — scarcity, form 2 (the roll is against `chance * k`), at
	# the ORIGIN chunk and NEVER EXEMPT. Paths cluster near the HQ corridor and the
	# city and are gone by SCARCITY_PLAIN_DISTANCE, like everything else that is
	# not a predator, a boss or a road coin.
	var k: float = terrain.scarcity_at(terrain.chunk_to_world(origin))
	if rng.randf() >= BIKE_PATH_CHANCE * k:
		return []

	# (b) THE START, anywhere inside the origin chunk. `chunk_to_world` returns the
	# CENTRE, so the corner is the multiplication; the offset is what keeps paths
	# off a lattice you could see from the minimap.
	var size: float = terrain.chunk_size
	var start := Vector2(float(origin.x) * size + rng.randf() * size,
			float(origin.y) * size + rng.randf() * size)

	# (c) THE BEARING, any direction. Unlike the coin road this polyline has no
	# monotone axis to keep: it is a thing people cross the field ON, not the
	# corridor the world is strung along.
	var heading0: float = rng.randf() * TAU

	# (d) THE LENGTH, in stations.
	var count: int = rng.randi_range(BIKE_PATH_MIN_STATIONS, BIKE_PATH_MAX_STATIONS)

	# --- THE WALK. Truncate at the first blocked station: keep the prefix, drop
	# everything after, never resume past the block.
	var stations: Array[Dictionary] = []
	var pos := start
	var heading := heading0
	for i in count:
		if station_blocked(terrain, pos):
			break
		stations.append({ "pos": pos, "heading": heading })
		heading = _next_heading(terrain, origin, heading0, heading, i)
		pos += Vector2(cos(heading), sin(heading)) * BIKE_STATION_SPACING

	if stations.size() < BIKE_PATH_MIN_STATIONS:
		return []
	return stations


static func next_station(terrain: Node3D, origin: Vector2i, heading0: float,
		station: Dictionary, i: int) -> Dictionary:
	"""
	One step of the walk above, as a function other code can call.

	@param heading0: The path's initial bearing — the heading the restore term
	                 pulls back toward (station 0's `heading`).
	@param station: The station to step FROM.
	@param i: Its index, which is what the turn hash is keyed on.
	@return: The next station, `{ "pos", "heading" }`, blocked or not.

	IT EXISTS FOR `bike_path_selfcheck` CHECK 3, and that is worth the seam: the
	check must ask "is the station AFTER the last one blocked?" to tell a
	truncation from a path that simply ran out of length, and the only alternative
	is a second copy of this recurrence inside the check — which would then agree
	with a broken one. `_bike_path_at` calls the same two lines.
	"""
	var heading: float = _next_heading(terrain, origin, heading0, float(station["heading"]), i)
	var pos: Vector2 = (station["pos"] as Vector2) \
			+ Vector2(cos(heading), sin(heading)) * BIKE_STATION_SPACING
	return { "pos": pos, "heading": heading }


static func _next_heading(terrain: Node3D, origin: Vector2i, heading0: float,
		heading: float, i: int) -> float:
	"""
	The heading-integrated recurrence, `coin_road.gd`'s `_road_extend_to_x` note
	ported to a polyline with no preferred axis:

	    heading[i+1] = heading0 + clamp( (heading[i] - heading0) * (1 - RESTORE)
	                                     + turn(i), -CAP, +CAP )

	The road restores toward 0 because its X must stay monotone; a bike path has
	no such axis, so it restores toward its OWN initial bearing instead. That is
	the same statement in a rotated frame, and it is what keeps a 24-station walk
	a gentle bend rather than a spiral that crosses its own strip.
	"""
	var cap: float = deg_to_rad(BIKE_MAX_HEADING_DEG)
	var drift: float = (heading - heading0) * (1.0 - BIKE_HEADING_RESTORE) \
			+ _bike_turn(terrain, origin, i)
	return heading0 + clampf(drift, -cap, cap)


static func _bike_turn(terrain: Node3D, origin: Vector2i, i: int) -> float:
	"""
	This family's OWN signed per-station turn, radians.

	@return: A deterministic angle in [-BIKE_TURN_RATE_DEG, +BIKE_TURN_RATE_DEG].

	IT MAY NOT BE `CoinRoad._road_turn`, and this is the whole reason the family
	carries a turn hash at all: that one is keyed on the station index `k` ALONE,
	so every bike path in the world would bend by the same angle at its own
	station 3 — every path wobbling in lockstep with the coin road and with each
	other. Keying on the ORIGIN as well as the index is what makes two paths in
	one biome two different paths.

	One hash per station, folded the way `_road_hash01` folds its own: mask to 24
	positive bits (hash() may return negatives) and normalise to [0, 1).
	"""
	var h: int = hash(Vector3i(
			origin.x * BIKE_TURN_PRIME_X + i * BIKE_TURN_PRIME_I,
			origin.y * BIKE_TURN_PRIME_Y,
			terrain.run_seed ^ BIKE_TURN_SALT))
	var unit: float = float(h & 0xFFFFFF) / float(0x1000000) * 2.0 - 1.0
	return deg_to_rad(BIKE_TURN_RATE_DEG) * unit


static func station_blocked(terrain: Node3D, p: Vector2) -> bool:
	"""
	May a station stand at this world XZ?

	@param p: The candidate station, WORLD space (x, z).
	@return: true when the path must stop here.

	PURE IN (POSITION, SEED) — every one of the seven tests below is, and that is
	the load-bearing property: it is why every chunk that evaluates an origin
	truncates its path at the SAME station, and therefore why a per-chunk draw of
	a shared polyline can agree with itself across a seam at all.

	CHEAPEST FIRST, because the overwhelming majority of stations are rejected by
	nothing and pay for every test: two rectangle tests, then a memoized
	dictionary hit, then two noise evaluations, then eleven distances, and only
	then the road's station cache — which may EXTEND that cache and is by some way
	the most expensive answer here.
	"""
	# 1. The authored city. Its streets are its own and a procedural strip across
	#    Váci utca is exactly the thing `in_budapest()` exists to refuse.
	if terrain.in_budapest(p.x, p.y):
		return true

	# 2. The tower's exclusion disc, with a station's own stride as the radius so
	#    the strip stops before it reaches in rather than when its centre does.
	if terrain.tower_excludes(p.x, p.y, BIKE_STATION_SPACING):
		return true

	# 3. A field landmark's site. `landmark_sites()` returns chunk -> kind, so the
	#    CHUNK test IS the disc test and it is cheaper than one — a memoized
	#    dictionary hit against a table that is built once per run.
	if TerrainLandmarks.landmark_sites(terrain).has(terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))):
		return true

	# 4. The mountain massif — impassable box stone, so a strip into it is a strip
	#    into a wall.
	if terrain.biome_at(p.x, p.y) == terrain.Biome.MOUNTAIN:
		return true

	# 5. The rivers. NO CROSSINGS: the field bridges are k-indexed ROAD machinery
	#    (`terrain_bridges.gd`), so a bike path cannot be given one, and a strip
	#    that forded a river would be a strip you wade.
	if terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
		return true

	# 6. The waypoint circles. Eleven of them in the world, so this is eleven
	#    distances against a table that is pure arithmetic over the road cache.
	var clear: float = TerrainWaypoints.RING_RADIUS + BIKE_WAYPOINT_MARGIN
	for site: Dictionary in TerrainWaypoints.waypoint_sites(terrain):
		var at: Vector3 = site["pos"]
		if Vector2(p.x - at.x, p.y - at.z).length() < clear:
			return true

	# 7. The coin road's swath, last because it is the one test that may grow the
	#    station cache. NO CROSSINGS here either: a crossing would put road coins
	#    on the strip. `_road_lateral_distance` returns INF when no station falls
	#    in its scan window — "far off-road in X" and "no road here" both mean
	#    clear — so the comparison, not a null test, is the whole reading of it.
	return terrain._road_lateral_distance(p.x, p.y, BIKE_ROAD_CLEARANCE) < BIKE_ROAD_CLEARANCE


# ============================================================================
# THE SPAWNER
# ============================================================================

static func spawn_bike_path_in_chunk(terrain: Node3D, chunk_pos: Vector2i,
		parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Draw this chunk's share of every path that reaches it.

	@param chunk_pos: The chunk being built.
	@param parent_chunk: The chunk mesh — the markers parent here, so they unload
	                     with the chunk and nothing leaks.
	@param obstacles: READ for the pole skip and APPENDED to, one footprint per
	                  pole. The strip and the dashes append nothing: they are
	                  paint, and `terrain_waypoints.gd`'s "no footprint, and why"
	                  is the same argument.
	@param block_batch / block_body: The chunk's visual batch and collision body.

	ASSIGNMENT BY MIDPOINT. A segment (and the station at its HEAD) is drawn by
	the chunk its midpoint falls in, and by no other. Geometry may overhang the
	seam; nothing is ever cut. That is the coin road's rule, one family along.

	THE CUBE-BUCKET INVARIANT, written down because `.2` depends on it:
	`_build_block_multimesh` buckets by KIND and emits in ENUM order, so a box's
	MultiMesh instance index is its position among the CUBE ENTRIES ONLY — never
	its index in `block_batch`. The counts recorded on the marker are valid
	because this spawner runs after the city splitter and because everything after
	it (the field bridges, and nothing else) only APPENDS: no later spawner
	inserts, reorders or removes an entry, so an index taken here still points at
	the same box when the MultiMesh is built.
	"""
	if not terrain.spawn_bike_paths:
		return

	# A PRIVATE generator with a FIXED seed, `terrain_waypoints.gd`'s note in full:
	# `create_box` always draws its colour ramp and its roughness from whatever
	# generator it is handed (that is how it keeps the shared chunk stream's
	# sequence intact for everybody else), and every one of those values is
	# discarded here because `color_override` is set. Passing our own means those
	# draws land nowhere near the chunk's stream; FIXING the seed means the batch
	# entry is byte-stable, which is what check 1's A/B compares.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0

	var batch_start: int = block_batch.size()
	# Where this family's first box lands in the CUBE bucket — see the docstring.
	var cube_start: int = _cube_count(block_batch)
	var cube_cursor: int = cube_start
	var chunk_origin: Vector3 = terrain.chunk_to_world(chunk_pos)
	var corner := Vector2(chunk_origin.x - terrain.chunk_size * 0.5,
			chunk_origin.z - terrain.chunk_size * 0.5)

	var markers: Array[Node3D] = []
	var radius: int = scan_radius_chunks(terrain)
	for ox in range(chunk_pos.x - radius, chunk_pos.x + radius + 1):
		for oy in range(chunk_pos.y - radius, chunk_pos.y + radius + 1):
			var origin := Vector2i(ox, oy)
			var stations: Array[Dictionary] = bike_path_at(terrain, origin)
			if stations.is_empty():
				continue
			var built: Dictionary = _draw_path_share(terrain, chunk_pos, corner, origin,
					stations, rng, obstacles, block_batch, block_body, cube_cursor)
			cube_cursor = built["cube_cursor"]
			if (built["segments"] as PackedInt32Array).is_empty():
				continue
			markers.append(_make_marker(origin, built, parent_chunk))

	# EVERY MARKER CARRIES THE WHOLE FAMILY'S SLICE, not only its own path's. The
	# `gag_start` / `gag_count` idiom (`terrain_features.gd`'s camp story gag,
	# consumed by `camp_story_selfcheck`): what the kill-switch A/B needs is ONE
	# contiguous range it can cut out of the batch to compare the rest byte for
	# byte, and this spawner's boxes are exactly that range however many paths
	# happen to cross this chunk.
	var batch_count: int = block_batch.size() - batch_start
	for marker: Node3D in markers:
		marker.set_meta("batch_start", batch_start)
		marker.set_meta("batch_count", batch_count)
		# The same range in CUBE BUCKET coordinates. Every box this family builds
		# is a CUBE, so the count is the same number — only the offset differs,
		# and it is the offset `.2` needs and the one check 1 slices the built
		# MultiMesh with.
		marker.set_meta("cube_start", cube_start)


static func _draw_path_share(terrain: Node3D, chunk_pos: Vector2i, corner: Vector2,
		origin: Vector2i, stations: Array[Dictionary], rng: RandomNumberGenerator,
		obstacles: Array, block_batch: Array, block_body: StaticBody3D,
		cube_cursor: int) -> Dictionary:
	"""
	One origin's segments, insofar as they belong to `chunk_pos`.

	@param corner: The chunk's -X/-Z corner in world XZ. Every `create_box` in this
	               project takes a CHUNK-LOCAL centre, so this is what the world-
	               space station positions are measured against.
	@param cube_cursor: How many CUBE entries the batch holds already.
	@return: `{ "segments": PackedInt32Array, "poles": PackedInt32Array,
	            "cube_cursor": int }` — the segment indices drawn here, the CUBE
	          bucket index of each pole built here, and the advanced cursor.
	"""
	var segments := PackedInt32Array()
	var poles := PackedInt32Array()
	for i in range(stations.size() - 1):
		var a: Vector2 = stations[i]["pos"]
		var b: Vector2 = stations[i + 1]["pos"]
		var mid: Vector2 = (a + b) * 0.5
		if terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y)) != chunk_pos:
			continue
		segments.append(i)

		# A yaw turns the box's local +X toward -Z, while the walk measures its
		# heading as (cos h, sin h) in (x, z) — so the yaw that points a box along
		# the segment is the NEGATED heading. The studs in `terrain_waypoints.gd`
		# are the same arithmetic.
		var head: float = stations[i + 1]["heading"]
		var yaw: float = -head
		var local_mid: Vector2 = mid - corner

		# --- THE STRIP: one flat box per segment, no collision and NO FOOTPRINT.
		# The waypoint disc's precedent: the strip is paint, you walk over it.
		terrain.create_box(
				Vector3(local_mid.x, BIKE_PATH_THICKNESS * 0.5, local_mid.y),
				Vector3(a.distance_to(b), BIKE_PATH_THICKNESS, BIKE_PATH_WIDTH),
				yaw, rng, block_batch, block_body, 0.0, BIKE_STRIP_COLOR, false,
				ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1

		# --- THE CENTRE LINE: one short dash at the segment's HEAD station, on top
		# of the strip. Also paint.
		var head_pos: Vector2 = b - corner
		terrain.create_box(
				Vector3(head_pos.x, BIKE_PATH_THICKNESS + BIKE_DASH_THICKNESS * 0.5, head_pos.y),
				Vector3(BIKE_DASH_LENGTH, BIKE_DASH_THICKNESS, BIKE_DASH_WIDTH),
				yaw, rng, block_batch, block_body, 0.0, BIKE_DASH_COLOR, false,
				ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1

		# --- THE POLE, at a FIXED station stride so `.2` has a deterministic set
		# of sites. It stands beside the strip, on the segment's left.
		if (i + 1) % BIKE_POLE_STRIDE != 0:
			continue
		var side := Vector2(-sin(head), cos(head)) * BIKE_POLE_OFFSET
		var at: Vector2 = head_pos + side
		# A pole whose site already falls inside a footprint is SKIPPED — the pole
		# only. The strip still runs past it: paint over a boulder is fine, a post
		# THROUGH one is not.
		if _footprint_taken(obstacles, at):
			continue
		terrain.create_box(
				Vector3(at.x, BIKE_POLE_HEIGHT * 0.5, at.y),
				Vector3(BIKE_POLE_WIDTH, BIKE_POLE_HEIGHT, BIKE_POLE_WIDTH),
				yaw, rng, block_batch, block_body, 0.0, BIKE_POLE_COLOR, true,
				ChunkBatch.BoxKind.CUBE)
		poles.append(cube_cursor)
		cube_cursor += 1
		# NON-CLIMBABLE: a post has no top to stand on, and its "top" is 2.6 m up
		# (`terrain_biomes.gd`'s masts, end of the street-furniture block).
		obstacles.append({
			"pos": Vector3(at.x, 0.0, at.y),
			"radius": BIKE_POLE_RADIUS,
			"top": BIKE_POLE_HEIGHT,
			"climbable": false,
		})

	return { "segments": segments, "poles": poles, "cube_cursor": cube_cursor }


static func _make_marker(origin: Vector2i, built: Dictionary,
		parent_chunk: MeshInstance3D) -> Node3D:
	"""
	One bare Node3D per path present in this chunk — no mesh, no script, no
	physics — found BY GROUP and parented to the chunk so it is freed when the
	chunk unloads. The landmark / waypoint marker precedent: no registry to keep
	in step and nothing to leak.

	@return: The marker, so the caller can stamp the family's batch slice on it
	         once every path in the chunk has been drawn.
	"""
	var marker := Node3D.new()
	marker.name = BIKE_PATH_MARKER_NAME
	marker.add_to_group(BIKE_PATH_GROUP)
	marker.set_meta("origin", origin)
	# Which of the path's segments this chunk drew. `.2` and `.3` never have to
	# re-derive the midpoint rule from a position, and `bike_path_selfcheck` check
	# 2 can assert the union across a field is a perfect cover without owning a
	# second copy of that rule — a copy which would then agree with a broken one.
	marker.set_meta("segments", built["segments"])
	# Each pole's CUBE BUCKET index (see the spawner's docstring — it is NOT the
	# batch index), so `.2` can colour a lamp with one `set_instance_color`.
	marker.set_meta("poles", built["poles"])
	parent_chunk.add_child(marker)
	return marker


# ============================================================================
# HELPERS
# ============================================================================

static func _cube_count(block_batch: Array) -> int:
	"""
	How many entries in the batch so far are CUBEs.

	`create_box` always writes `kind`, so the default below is for the hand-built
	batches the self-checks hand around — the same allowance
	`ChunkBatch._build_block_multimesh` makes, and for the same reason.
	"""
	var n := 0
	for entry: Variant in block_batch:
		if (entry as Dictionary).get("kind", ChunkBatch.BoxKind.CUBE) == ChunkBatch.BoxKind.CUBE:
			n += 1
	return n


static func _footprint_taken(obstacles: Array, at: Vector2) -> bool:
	"""
	Would a post at this CHUNK-LOCAL spot stand inside something already built?

	The chunk's own `obstacles` list is the shared currency: blocks, biome content,
	artifacts, camps, chests and the city's plateaus are all in it by the time this
	spawner runs, which is exactly why the call site sits where it does.
	"""
	for o: Variant in obstacles:
		var entry: Dictionary = o
		var pos: Vector3 = entry["pos"]
		if Vector2(pos.x - at.x, pos.z - at.y).length() < float(entry["radius"]) + BIKE_POLE_RADIUS:
			return true
	return false
