class_name BikePaths
extends RefCounted
## ============================================================================
## THE BICYCLE PATHS — short seeded strips laid across the field biomes
## ============================================================================
## Epic `godot-test1-z2yv`, children `.1` and `.2`. Owner, 2026-09-18 (Russian,
## paraphrased): *"in our field biomes there should be BICYCLE PATHS stretched
## here and there, with various TRAFFIC LIGHTS and ROAD SIGNS along them"*.
##
## `.1` laid the PATHS — a strip, a dashed centre line and bare poles. `.2` put
## the four authored SIGNS and the cycling TRAFFIC HEAD on those poles (see "WHAT
## STANDS ON THE POLES" below). The bike-stand rack at each end is `.3` and the
## rental bike itself is a later epic; both hang off this family's marker instead
## of re-deriving a position.
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
## existed, so with `spawn_bike_paths = false` every other box in the world is
## where it was. `bike_path_selfcheck` check 1 is that statement, measured
## through the shipped `create_chunk` on both sides.
##
## WITH ONE SANCTIONED EXCEPTION, and it is a FOOTPRINT rather than a draw: a
## pole appends `{pos, radius, top, climbable}` to `obstacles`, which the
## crocodile, boss and hunter spawners read a few lines later in `create_chunk`.
## A candidate inside a footprint is rejected, and `terrain_predators.gd`'s own
## note says what follows — "a rejection still skips the successful spawn's
## `rotation.y` draw below, so the rest of this chunk's crocodile positions
## shift". That is the shared-currency mechanism camps, chests and artifacts all
## use, not a stream this family touched, and check 1 tests node-for-node
## equality only on the chunks where this family appended NO footprint, which is
## where the claim is exactly true.
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
## WHAT STANDS ON THE POLES: FOUR AUTHORED SIGNS, AND A HEAD THAT CYCLES
## ----------------------------------------------------------------------------
## (Child `.2`.) Every pole carries EXACTLY ONE top, and which one is a HASH
## DISPATCH of (origin chunk, station index) through the fixed `POLE_TOPS` table.
## A DISPATCH COSTS NO DRAW — CLAUDE.md, "dispatch (which species, which box kind,
## which boss) costs no draw" — and an `rng.randi()` here instead would consume a
## draw from this family's own stream and move every station of every path in the
## world. The kill-switch A/B (`bike_path_selfcheck` check 1) is byte-identical
## with the signs on, and that is the statement.
##
## A SIGN is a plate CUBE plus one to three pictogram CUBEs standing on the face a
## rider approaches, in the palette the city's own street furniture already spends
## (`terrain.CITY_METAL` and the three `terrain.CITY_LAMP_*`). NO TEXT AND NO
## GLYPH NODES: a sign reads by SILHOUETTE and COLOUR — never a `Label3D`, never a
## font, never a texture. That is a design ruling first, and it is also exactly
## why this family is invisible to `locale_selfcheck`: there is no string here for
## a German translation to overflow, and there may never be one.
##
## THE SIGNAL HEAD is the city band's three-lamp stack, copied from
## `terrain_biomes.gd`'s street furniture (the `if is_signal:` arm) rather than
## called into it — a static family reaches a sibling family through the node that
## owns the state, and there is no state here to own. Bright ALBEDO and never
## emissive, CUBEs and not SPHEREs, for the reasons written at the original.
##
## ----------------------------------------------------------------------------
## PLACEMENT IS SEEDED; THE CYCLE IS AMBIENCE
## ----------------------------------------------------------------------------
## WHERE a head stands is the seed's business (it rode in on `.1`'s stations and
## the dispatch above). WHICH LAMP IS LIT is not: it is one `Timer` per head on a
## `randomize()`d phase and dwell, which is CLAUDE.md's ambience rule — "ambience
## is deliberately OUTSIDE the contract on a `randomize()`d RNG. Don't wire it to
## the seed". NEVER SEEDED AND NEVER ON THE WIRE: two peers standing at the same
## light see different lamps lit, and that is the accepted ruling, the same one
## the clear clouds, the birds, the crowd and the traffic already ship under.
##
## The build therefore draws all three lenses DIM, so the geometry stays a pure
## function of the seed; a head is dark for less than one dwell after its chunk
## loads and then cycles G -> A -> R forever.
##
## THE WRITE IS `set_instance_color` AT A CUBE-BUCKET INDEX, and that index is the
## one fragile thing in this family. `ChunkBatch._build_block_multimesh` buckets by
## KIND and emits in ENUM order, so a lamp's MultiMesh instance index is its
## position among the CUBE ENTRIES ONLY — never its index in `block_batch`. The
## index recorded here is valid because the city splitter has already run and
## because everything after this spawner only APPENDS. `bike_path_selfcheck`
## check 9 measures that against the SHIPPED bucketing function rather than
## against a copy of its rule, and carries its own off-by-one control — an index
## that is one out still writes a box, just the wrong one, and nothing else in
## the world would ever notice. (Reading the colour back is not available to it:
## MultiMesh instance data is write-only under the headless dummy renderer, which
## that check's docstring measures and writes down.)
##
## `srgb_to_linear()` ON EVERY WRITE IS NOT OPTIONAL: `create_box` stores its
## colour already linearised (`chunk_batch.gd`'s COLOUR SPACE paragraph says why),
## so a raw `Color` written here would make one lamp visibly brighter than every
## other box in the world, on desktop and on web alike.
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
# The primes are NEW, and that was checked against the whole tree rather than
# against the handful a reader remembers. Already spoken for elsewhere in this
# world engine: 73856093/19349663 (artifacts), 83492791/15485863 (the biome
# offset), 40960001/26463089 (camps), 96174811/18266587 (the scarcity roll),
# 86028121/50331653 (chests), 32452867/49979687 (the landmark sites),
# 122949829/104395301 (hunters), 141650939/175961107 (the Danube), 179424673 and
# 32452843 (the crocodile roll), 40499/86969 and 83492791/28411639 (predators),
# 57859/31337 (the camp story) and 92821 (the road's figures).
#
# Sharing a pair would correlate two features: a chunk that hosts a camp would
# thereby be likelier (or never) to host a path, which is the one thing an
# independent stream exists to prevent. `grep -rhoE '[0-9]{5,10}' scripts/` is
# the check the next author owes, and it is how these two were chosen.
const BIKE_HASH_PRIME_X: int = 67867979
const BIKE_HASH_PRIME_Y: int = 34019651

## "BIKE PATH"-ish; arbitrary fixed constant, XORed into `run_seed` so this
## family's stream is its own even where the primes would agree.
const BIKE_PATH_SALT: int = 0xB1_1E9A7

## The TURN hash's own salt and primes — see `_bike_turn()` for why this family
## may not call `CoinRoad._road_turn`.
const BIKE_TURN_SALT: int = 0xB1_1E70A
const BIKE_TURN_PRIME_X: int = 55621459
const BIKE_TURN_PRIME_Y: int = 71378569
const BIKE_TURN_PRIME_I: int = 15485917

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
# WHAT STANDS ON THE POLE — the dispatch, the four signs, the signal head
# ============================================================================

## The TOP dispatch's own salt and primes, chosen the way the two pairs above
## were: `grep -rl` over `scripts/` finds all three of these nowhere else. They
## are only ever fed to `hash()`, never to an RNG — see `_pole_top`.
const BIKE_TOP_SALT: int = 0xB1_1E516E
const BIKE_TOP_PRIME_X: int = 30402457
const BIKE_TOP_PRIME_Y: int = 24036583
const BIKE_TOP_PRIME_I: int = 20996011

## The sentinel `POLE_TOPS` uses for "a traffic head, not a sign". Negative so it
## can never be read as an index into `SIGN_KINDS` by accident.
const POLE_TOP_SIGNAL: int = -1

## THE DISPATCH TABLE, and the whole of the "how often" question. One fold of one
## hash indexes it, so adding a kind or retuning the mix costs NO DRAW and moves
## nothing: the stations, the strip and the poles are exactly where they were.
## Eight sign slots to one signal, because a working traffic light out in an empty
## field is a joke that stops being funny at every fourth pole — at this mix a
## typical path carries five or six signs and about one head every other path.
const POLE_TOPS: Array[int] = [0, 1, 2, 3, 0, 1, 2, 3, POLE_TOP_SIGNAL]

## Palette KEYS, resolved through `_palette()` against the terrain's own constants.
## The table below is a `const`, and `terrain.CITY_METAL` is not a constant
## expression — a family reaches the city's palette through the node that owns it.
const PAL_METAL: int = 0
const PAL_RED: int = 1
const PAL_AMBER: int = 2
const PAL_GREEN: int = 3

## How thick a sign plate is, and how far its pictogram stands proud of the face.
const SIGN_PLATE_DEPTH: float = 0.05
const SIGN_PIP_DEPTH: float = 0.035
## The plate's centre height on the 2.6 m post — eye level for a rider, and it
## keeps the tallest plate's top under the post's own.
const SIGN_CENTRE_Y: float = 2.05

## THE FOUR AUTHORED SIGNS. Indexed by the dispatch above, and each one differs
## from the other three in PLATE COLOUR, PLATE SHAPE and PIP COUNT at once, so it
## reads at 30 m as a silhouette rather than as a thing you walk up to and study.
##   `plate`: (width across the path, height).  `pip`: one pictogram box, same.
##   `pips`:  each pictogram's offset on the plate face, (across, up).
## No text, no glyph node, no texture — see the banner, and `locale_selfcheck`.
const SIGN_KINDS: Array[Dictionary] = [
	# 0 — ROUTE. A tall green plate with one bar across it: this strip is a bike
	#     lane and it goes that way.
	{
		"plate": Vector2(0.44, 0.60), "plate_color": PAL_GREEN,
		"pip": Vector2(0.30, 0.07), "pip_color": PAL_METAL,
		"pips": [Vector2(0.0, 0.0)],
	},
	# 1 — YIELD. An amber square with two stacked bars: give way, junction ahead.
	{
		"plate": Vector2(0.46, 0.46), "plate_color": PAL_AMBER,
		"pip": Vector2(0.26, 0.06), "pip_color": PAL_METAL,
		"pips": [Vector2(0.0, 0.09), Vector2(0.0, -0.09)],
	},
	# 2 — STOP. A wide, short red plate with one fat bar: the no-entry silhouette.
	{
		"plate": Vector2(0.62, 0.34), "plate_color": PAL_RED,
		"pip": Vector2(0.40, 0.11), "pip_color": PAL_METAL,
		"pips": [Vector2(0.0, 0.0)],
	},
	# 3 — CROSSING. A metal square with three upright amber bars: a zebra, which is
	#     the one pictogram in this set that is literally what it depicts.
	{
		"plate": Vector2(0.50, 0.50), "plate_color": PAL_METAL,
		"pip": Vector2(0.07, 0.34), "pip_color": PAL_AMBER,
		"pips": [Vector2(-0.14, 0.0), Vector2(0.0, 0.0), Vector2(0.14, 0.0)],
	},
]

## One lamp box, a side. The city's own is 0.22 on a 4 m mast (`CITY_LIGHT_LAMP`);
## this head sits on a 2.6 m bike-path post, so it is scaled down to match.
const BIKE_LAMP: float = 0.16

## How far an UNLIT lens is darkened from its own colour. The stack must still read
## as a traffic light with every lamp off — which is how every head looks for its
## first fraction of a dwell after a chunk loads.
const BIKE_LAMP_DIM: float = 0.62

## The lamp the cycle lights, by phase: G -> A -> R. The stack is built top-down
## RED, AMBER, GREEN (the city's order), so phase 0 lights lamp 2.
const SIGNAL_LIT: Array[int] = [2, 1, 0]

## The dwell between steps, seconds, rolled once per head off a `randomize()`d RNG.
## THE FLOOR IS A PERFORMANCE NUMBER, not a taste one: `set_instance_color` dirties
## the whole instance buffer and a field chunk's CUBE bucket carries several
## hundred boxes, so a head must never be a per-frame writer. With the phase rolled
## the same way, heads in one chunk are staggered for free.
const SIGNAL_DWELL_MIN: float = 2.2
const SIGNAL_DWELL_MAX: float = 4.5

## The per-head Timer's node name. It is a CHILD OF THE MARKER (which is a child of
## the chunk), so it is freed with the chunk like every other per-chunk node — and
## it stays out of the chunk's own child list, which `bike_path_selfcheck` check 1
## compares node for node to catch a stray draw.
const SIGNAL_TIMER_NAME: String = "BikeSignalCycle"

## The CUBE bucket's node name, which is what `_build_block_multimesh` calls the
## MultiMeshInstance3D it emits for `BoxKind.CUBE` (every other kind is suffixed).
const CUBE_BUCKET_NAME: String = "BlockMultiMesh"

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
	# The waypoint table, read ONCE for the whole walk rather than once per
	# station — it is pure in `run_seed` and rebuilding it is the most expensive
	# thing in the predicate after the road cache. See `_station_blocked`.
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()

	var stations: Array[Dictionary] = []
	var pos := start
	var heading := heading0
	for i in count:
		if _station_blocked(terrain, pos, waypoints):
			break
		stations.append({ "pos": pos, "heading": heading })
		heading = _next_heading(terrain, origin, heading0, heading, i)
		var step: Vector2 = pos + Vector2(cos(heading), sin(heading)) * BIKE_STATION_SPACING
		# ...and the water BETWEEN the two, which the station pitch is too coarse
		# to see on its own. Truncating here keeps the prefix that ends at `pos`.
		if segment_blocked(terrain, pos, step):
			break
		pos = step

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

	THE ONE-ARGUMENT FORM, for callers with a single point to test (the walk's
	own is `_station_blocked` below, which is handed the waypoint table once for
	the whole path instead of rebuilding it per station).
	"""
	return _station_blocked(terrain, p, terrain.waypoint_sites())


static func segment_blocked(terrain: Node3D, a: Vector2, b: Vector2) -> bool:
	"""
	Does the SEGMENT between two legal stations cross water?

	@return: true when the path must stop at `a` rather than reach `b`.

	THE HALF-STEP RIVER SAMPLE, and it exists because the station pitch is coarse
	against the one feature in the field that is thin. `RIVER_HALF_WIDTH`'s own
	measurement note (`endless_terrain.gd`) puts a band at roughly 8-9 m across at
	the mean gradient — but the gradient varies, and wherever it is steep the band
	drops under `BIKE_STATION_SPACING` and a 5 m step can put one station on each
	dry side of it. The strip between them would then be laid across the water,
	which is the exact case `station_blocked`'s river test says cannot happen.

	Only the river is sampled here, and that is the whole of the reasoning: every
	other blocking feature is wide against the pitch — the road's swath is 14 m,
	the tower's disc is padded by a full station stride, the mountain band and the
	city rect are hundreds of metres, and a 5.6 m waypoint clearance can only be
	clipped in its outer half-metre. Re-running all seven tests at the midpoint
	would double the walk's cost to re-answer six questions that were never in
	doubt.

	ponytail: this halves the effective pitch to 2.5 m rather than making the test
	continuous, so a band under 2.5 m across could still be stepped over. If one
	ever is, the upgrade is a swept test along the segment rather than a third
	sample point.
	"""
	return terrain.is_river_at(Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5))


static func _station_blocked(terrain: Node3D, p: Vector2, waypoints: Array[Dictionary]) -> bool:
	"""
	`station_blocked` with the waypoint table passed in.

	@param p: The candidate station, WORLD space (x, z).
	@param waypoints: `terrain.waypoint_sites()`, read ONCE per walk. That table
	                  is not memoized — every call allocates eleven rows and runs
	                  six binary searches with a river re-walk each — and it is
	                  loop-invariant here, being pure in `run_seed`.
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
	if terrain.landmark_sites().has(terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))):
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
	#    distances against a table the caller built once for the whole walk.
	var clear: float = TerrainWaypoints.RING_RADIUS + BIKE_WAYPOINT_MARGIN
	for site: Dictionary in waypoints:
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
	# THE CHUNK-LOCAL FRAME IS CENTRED ON THE CHUNK NODE, not on its corner:
	# `create_chunk` sets `mesh_instance.position = chunk_to_world(chunk_pos)` and
	# `chunk_to_world` returns the chunk's CENTRE, so a chunk-local coordinate runs
	# [-chunk_size/2, +chunk_size/2] and a world point converts by subtracting the
	# centre. `terrain_bridges.gd` is the closest precedent — a world-space
	# polyline drawn per chunk by this same midpoint rule — and it subtracts the
	# centre too.
	var chunk_centre: Vector3 = terrain.chunk_to_world(chunk_pos)
	var centre := Vector2(chunk_centre.x, chunk_centre.z)

	var markers: Array[Node3D] = []
	var radius: int = scan_radius_chunks(terrain)
	for ox in range(chunk_pos.x - radius, chunk_pos.x + radius + 1):
		for oy in range(chunk_pos.y - radius, chunk_pos.y + radius + 1):
			var origin := Vector2i(ox, oy)
			var stations: Array[Dictionary] = bike_path_at(terrain, origin)
			if stations.is_empty():
				continue
			var built: Dictionary = _draw_path_share(terrain, chunk_pos, centre, origin,
					stations, rng, obstacles, block_batch, block_body, cube_cursor)
			cube_cursor = built["cube_cursor"]
			if (built["segments"] as PackedInt32Array).is_empty():
				continue
			markers.append(_make_marker(terrain, origin, built, parent_chunk))

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


static func _draw_path_share(terrain: Node3D, chunk_pos: Vector2i, centre: Vector2,
		origin: Vector2i, stations: Array[Dictionary], rng: RandomNumberGenerator,
		obstacles: Array, block_batch: Array, block_body: StaticBody3D,
		cube_cursor: int) -> Dictionary:
	"""
	One origin's segments, insofar as they belong to `chunk_pos`.

	@param centre: The chunk's CENTRE in world XZ — the position of the chunk node
	               itself. Every `create_box` in this project takes a CHUNK-LOCAL
	               centre, and chunk-local is relative to that node, so this is
	               what the world-space station positions are measured against.
	@param cube_cursor: How many CUBE entries the batch holds already.
	@return: `{ "segments", "poles", "tops", "signals", "cube_cursor" }` — the
	          segment indices drawn here, the CUBE-bucket index of each pole built
	          here, the top each of those poles carries (a `SIGN_KINDS` index or
	          `POLE_TOP_SIGNAL`, one entry per pole), the CUBE-bucket index of each
	          signal head's FIRST lens, and the advanced cursor.
	"""
	var segments := PackedInt32Array()
	var poles := PackedInt32Array()
	var tops := PackedInt32Array()
	var signals := PackedInt32Array()
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
		var local_mid: Vector2 = mid - centre

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
		var head_pos: Vector2 = b - centre
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

		# --- AND WHAT STANDS ON IT (child `.2`): one sign, or one signal head.
		# A HASH DISPATCH and not a draw — see `_pole_top` and the banner. It is
		# reached only here, AFTER the footprint skip above, so a pole that was
		# never built carries no top either and `tops` stays parallel to `poles`.
		var top: int = _pole_top(terrain, origin, i + 1)
		tops.append(top)
		if top == POLE_TOP_SIGNAL:
			# THE OFF-BY-ONE LIVES ON THIS LINE. `_build_signal_head` emits the head
			# box FIRST and the three lenses after it, so lamp 0 stands one past the
			# cursor as it is now. `bike_path_selfcheck` check 9 asks the SHIPPED
			# `_build_block_multimesh` where this lens really lands and compares.
			signals.append(cube_cursor + 1)
			cube_cursor = _build_signal_head(terrain, at, head, yaw, rng,
					block_batch, block_body, cube_cursor)
		else:
			cube_cursor = _build_sign(terrain, top, at, head, yaw, rng,
					block_batch, block_body, cube_cursor)

	return {
		"segments": segments, "poles": poles, "tops": tops, "signals": signals,
		"cube_cursor": cube_cursor,
	}


static func _make_marker(terrain: Node3D, origin: Vector2i, built: Dictionary,
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
	# batch index), so a lamp is one `set_instance_color` away.
	marker.set_meta("poles", built["poles"])
	# What each of those poles carries, one entry per pole, and the CUBE-bucket
	# index of each signal head's first lens. `bike_path_selfcheck` checks 7 and 9
	# read both, and `.3` gets the path's ends the same way.
	marker.set_meta("tops", built["tops"])
	marker.set_meta("signals", built["signals"])
	parent_chunk.add_child(marker)
	_plant_signal_timers(terrain, marker, built["signals"])
	return marker


# ============================================================================
# THE POLE'S TOP — the dispatch and the two things it can build
# ============================================================================

static func _pole_top(terrain: Node3D, origin: Vector2i, i: int) -> int:
	"""
	What the pole at station `i` of the path from `origin` carries.

	@return: an index into `SIGN_KINDS`, or `POLE_TOP_SIGNAL`.

	A HASH DISPATCH AND NOT A DRAW, which is the one thing this function exists to
	be. CLAUDE.md: "Dispatch (which species, which box kind, which boss) costs no
	draw." An `rng.randi_range(0, 4)` here would read identically and would move
	every station of every bike path in the world, because this family's walk rolls
	its start, its bearing and its length off one stream and a fifth draw slides all
	three. `bike_path_selfcheck` check 1 is the measurement of that.

	Keyed on the ORIGIN as well as the station index for `_bike_turn`'s reason: on
	the index alone every path in the world would carry the same sign at its own
	fourth pole.

	Folded to a POSITIVE int before the modulo — `hash()` may return a negative, and
	a negative modulo in GDScript is negative, which would index the table backwards
	and (with this table) still return a legal kind. That is the sort of bug that
	never crashes.
	"""
	var h: int = hash(Vector3i(
			origin.x * BIKE_TOP_PRIME_X + i * BIKE_TOP_PRIME_I,
			origin.y * BIKE_TOP_PRIME_Y,
			terrain.run_seed ^ BIKE_TOP_SALT))
	return POLE_TOPS[(h & 0x7FFFFFFF) % POLE_TOPS.size()]


static func _palette(terrain: Node3D, key: int) -> Color:
	"""
	One of the city's four street-furniture colours, by `PAL_*` key.

	Through the TERRAIN, which re-exports `TerrainProps`' palette, and not by
	reaching into `TerrainProps` directly: a static family reaches a sibling family
	through the node that owns the state (CLAUDE.md's conventions). The keys exist
	because `SIGN_KINDS` is a `const` and a terrain constant is not a constant
	expression.
	"""
	match key:
		PAL_RED:
			return terrain.CITY_LAMP_RED
		PAL_AMBER:
			return terrain.CITY_LAMP_AMBER
		PAL_GREEN:
			return terrain.CITY_LAMP_GREEN
		_:
			return terrain.CITY_METAL


static func lamp_color(terrain: Node3D, lamp: int, lit: bool) -> Color:
	"""
	One lens's colour, top-down: 0 red, 1 amber, 2 green (the city's stack order).

	@param lit: false for the darkened lens the BUILD draws and the cycle leaves on
	            the two lamps it is not lighting.
	@return: The raw sRGB colour. EVERY WRITE PATH LINEARISES IT ITSELF —
	         `create_box` on the way into the batch, `write_lamps` on the way into
	         the MultiMesh — so this must not be pre-linearised here.

	Public because `bike_path_selfcheck` check 9 asserts the built colours against
	it rather than against a second copy of this table.
	"""
	var bright: Color = _palette(terrain, [PAL_RED, PAL_AMBER, PAL_GREEN][lamp])
	return bright if lit else bright.darkened(BIKE_LAMP_DIM)


static func _build_sign(terrain: Node3D, kind: int, at: Vector2, head: float,
		yaw: float, rng: RandomNumberGenerator, block_batch: Array,
		block_body: StaticBody3D, cube_cursor: int) -> int:
	"""
	One authored sign on the post at chunk-local `at`.

	@param kind: An index into `SIGN_KINDS`.
	@param head: The segment's heading, radians — the walk's own, from which the
	             plate's facing is derived.
	@param yaw: The box yaw the rest of this family uses, `-head`.
	@return: The advanced CUBE cursor.

	THE PLATE FACES BACK ALONG THE PATH, so a rider riding the strip reads it head
	on. Under `Basis(UP, yaw)` with `yaw == -head`, local +X maps to `(cos head, sin
	head)` — the direction of travel — so the plate is THIN IN X and the pictogram
	stands proud on its -X face.

	NO COLLISION on any of it: you may ride through a sign plate, which is the
	waypoint paint's ruling and the reason check 1's collision-shape delta is still
	exactly the pole count. No footprint either — the post beneath it owns the one
	footprint this family claims.
	"""
	var row: Dictionary = SIGN_KINDS[kind]
	var plate: Vector2 = row["plate"]
	terrain.create_box(
			Vector3(at.x, SIGN_CENTRE_Y, at.y),
			Vector3(SIGN_PLATE_DEPTH, plate.y, plate.x),
			yaw, rng, block_batch, block_body, 0.0,
			_palette(terrain, int(row["plate_color"])), false, ChunkBatch.BoxKind.CUBE)
	cube_cursor += 1

	var dir := Vector2(cos(head), sin(head))
	var side := Vector2(-sin(head), cos(head))
	var face: Vector2 = at - dir * (SIGN_PLATE_DEPTH * 0.5 + SIGN_PIP_DEPTH * 0.5)
	var pip: Vector2 = row["pip"]
	var pip_color: Color = _palette(terrain, int(row["pip_color"]))
	for off_v: Variant in (row["pips"] as Array):
		var off: Vector2 = off_v
		var p: Vector2 = face + side * off.x
		terrain.create_box(
				Vector3(p.x, SIGN_CENTRE_Y + off.y, p.y),
				Vector3(SIGN_PIP_DEPTH, pip.y, pip.x),
				yaw, rng, block_batch, block_body, 0.0, pip_color, false,
				ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1
	return cube_cursor


static func _build_signal_head(terrain: Node3D, at: Vector2, head: float, yaw: float,
		rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D,
		cube_cursor: int) -> int:
	"""
	The three-lamp stack on the post at chunk-local `at`.

	@return: The advanced CUBE cursor. THE HEAD BOX IS EMITTED FIRST and the three
	         lenses in top-down order after it, which is the layout the caller's
	         `signals.append(cube_cursor + 1)` and `SIGNAL_LIT` both assume.

	COPIED FROM `terrain_biomes.gd`'s street furniture — the `if is_signal:` arm of
	its city-light loop, nine lines — rather than called into it: a static family
	reaches a sibling family through the node that owns the state, and there is no
	state here to own. The proportions are that block's, scaled from the city's
	`CITY_LIGHT_LAMP` 0.22 on a 4 m mast to `BIKE_LAMP` on this family's 2.6 m post.
	Its own note says why the head and the lenses stay CUBEs and not SPHEREs, and
	why the lamps are BRIGHT ALBEDO and never emissive; both hold here, and this
	family adds no bucket either (check 5, check 8).

	THE AXES ARE SWAPPED against the original, and only the axes: the city's masts
	are yawed on their own convention while this family's boxes carry the strip's
	`yaw == -head`, under which local +X is the direction of travel. So the head is
	deep in X and wide in Z, and the lenses stand proud on the -X face — the face a
	rider coming up the strip is looking at.
	"""
	var head_h: float = BIKE_LAMP * 3.4
	terrain.create_box(
			Vector3(at.x, BIKE_POLE_HEIGHT + head_h * 0.5, at.y),
			Vector3(BIKE_LAMP * 1.4, head_h, BIKE_LAMP * 1.5),
			yaw, rng, block_batch, block_body, 0.0, terrain.CITY_METAL, false,
			ChunkBatch.BoxKind.CUBE)
	cube_cursor += 1

	var dir := Vector2(cos(head), sin(head))
	var face: Vector2 = at - dir * (BIKE_LAMP * 0.75)
	for j in 3:
		# DIM AT BUILD TIME, every one of them. The lit lamp is the cycle's business
		# and the cycle is `randomize()`d ambience, so nothing the seed can see may
		# depend on it — check 10 is that statement.
		terrain.create_box(
				Vector3(face.x,
						BIKE_POLE_HEIGHT + head_h - BIKE_LAMP * (0.7 + float(j) * 1.05),
						face.y),
				Vector3(BIKE_LAMP * 0.4, BIKE_LAMP, BIKE_LAMP),
				yaw, rng, block_batch, block_body, 0.0, lamp_color(terrain, j, false),
				false, ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1
	return cube_cursor


# ============================================================================
# THE CYCLE — ambience, on a randomize()d clock, never on the seed
# ============================================================================

static func _plant_signal_timers(terrain: Node3D, marker: Node3D,
		signals: PackedInt32Array) -> void:
	"""
	One `Timer` per signal head in this chunk, each cycling its own three lenses.

	@param signals: Each head's FIRST lens, in CUBE-bucket coordinates.

	`randomize()`, DELIBERATELY, and this is the whole of the ruling: placement is
	the seed's (the stations, the poles, the dispatch), the cycle is AMBIENCE and
	CLAUDE.md puts ambience outside the determinism contract on a `randomize()`d
	RNG. Two peers standing at the same light therefore see different lamps lit;
	that is accepted and recorded, the same ruling the clear clouds, the birds, the
	crowd and the traffic ship under. DO NOT seed this and do not put it on the
	wire.

	THE PHASE IS THE FIRST WAIT and it is what staggers the heads for free: a
	`set_instance_color` dirties the whole instance buffer of a bucket that carries
	several hundred boxes on a field chunk, so what must never happen is every head
	in view writing on one frame. With the dwell floored at `SIGNAL_DWELL_MIN` and
	the phase uniform inside it, two heads landing on the same frame twice running
	is not a thing this can do.

	PARENTED TO THE MARKER, which is parented to the chunk: freed with the chunk
	like every other per-chunk node, and out of the chunk's own child list, which
	`bike_path_selfcheck` check 1 compares node for node.
	"""
	if signals.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# The two colour tables the tick writes, resolved ONCE here because the Timer is
	# all the tick gets: it has no terrain to ask, by design — a per-chunk node that
	# held a reference to the terrain would outlive nothing and confuse everything.
	var bright := PackedColorArray()
	var dim := PackedColorArray()
	for j in 3:
		bright.append(lamp_color(terrain, j, true))
		dim.append(lamp_color(terrain, j, false))
	for base: int in signals:
		var dwell: float = rng.randf_range(SIGNAL_DWELL_MIN, SIGNAL_DWELL_MAX)
		var timer := Timer.new()
		timer.name = SIGNAL_TIMER_NAME
		timer.one_shot = false
		# AUTOSTART rather than `start()`: the chunk is not in the tree yet when the
		# spawner runs, and `start()` on a detached Timer is an error. Autostart
		# begins the moment the chunk enters.
		timer.autostart = true
		timer.wait_time = maxf(0.05, rng.randf() * dwell)
		timer.set_meta("lamp0", base)
		timer.set_meta("dwell", dwell)
		timer.set_meta("phase", rng.randi_range(0, 2))
		timer.set_meta("bright", bright)
		timer.set_meta("dim", dim)
		timer.timeout.connect(Callable(BikePaths, "tick_signal").bind(timer))
		marker.add_child(timer)


static func tick_signal(timer: Timer) -> void:
	"""
	One step of one head's cycle: G -> A -> R, written into the chunk's CUBE bucket.

	Public because `bike_path_selfcheck` check 9 drives it — through the Timer's own
	`timeout` signal, so the connection above is under test too.

	EVERY EARLY-OUT HERE IS A REAL CASE, not defensive padding: a chunk whose batch
	was empty grows no `BlockMultiMesh` at all (`create_chunk` skips the build), and
	a Timer can fire on the frame its chunk is being torn down. Both mean "no lamp to
	write", and neither is an error.
	"""
	var mm: MultiMesh = signal_multimesh(timer)
	if mm == null:
		return
	var base: int = int(timer.get_meta("lamp0", -1))
	if base < 0 or base + 3 > mm.instance_count:
		return
	var phase: int = (int(timer.get_meta("phase", 0)) + 1) % 3
	timer.set_meta("phase", phase)
	# The first wait was the PHASE, a fraction of the dwell; every one after it is
	# the dwell itself. Idempotent, so it costs nothing to write on every tick.
	timer.wait_time = float(timer.get_meta("dwell", SIGNAL_DWELL_MIN))
	write_lamps(mm, base, phase,
			timer.get_meta("bright") as PackedColorArray,
			timer.get_meta("dim") as PackedColorArray)


static func signal_multimesh(timer: Node) -> MultiMesh:
	"""
	The CUBE bucket of the chunk a signal Timer belongs to, or null.

	Timer -> marker -> chunk -> `BlockMultiMesh`. Named rather than inlined so the
	self-check can ask the same question the tick asks.
	"""
	var marker: Node = timer.get_parent()
	if marker == null or marker.get_parent() == null:
		return null
	var node: Node = marker.get_parent().get_node_or_null(CUBE_BUCKET_NAME)
	if node == null or not (node is MultiMeshInstance3D):
		return null
	return (node as MultiMeshInstance3D).multimesh


static func write_lamps(mm: MultiMesh, base: int, phase: int,
		bright: PackedColorArray, dim: PackedColorArray) -> void:
	"""
	Light lamp `SIGNAL_LIT[phase]` of the head whose first lens is instance `base`,
	and darken the other two.

	`srgb_to_linear()` IS NOT OPTIONAL. `create_box` stores its colour already
	linearised (`chunk_batch.gd`'s COLOUR SPACE paragraph: a per-instance MultiMesh
	colour is fed straight to the shader as a vertex colour and skips the sRGB step
	a material would have done), so a raw `Color` written here would render one lamp
	visibly brighter than every other box in the world, on desktop and on web.

	THE INDEX IS A CUBE-BUCKET INDEX, never a `block_batch` index — see the banner.
	An index one out still writes a perfectly valid instance, which is why check 9
	reads the colour back and controls it against `base + 1`.
	"""
	var lit: int = SIGNAL_LIT[phase]
	for j in 3:
		var c: Color = bright[j] if j == lit else dim[j]
		mm.set_instance_color(base + j, c.srgb_to_linear())


# ============================================================================
# HELPERS
# ============================================================================

static func _cube_count(block_batch: Array) -> int:
	"""
	How many entries in the batch so far land in the CUBE bucket.

	BOTH of `_build_block_multimesh`'s allowances, because the answer has to be
	the bucket's own and not a second opinion about it: an entry with NO `kind`
	reads as a CUBE (which is how a self-check hands this a batch without
	restating the key), and so does an entry whose `kind` is not in the enum at
	all (which is how that function keeps a bad value from vanishing into a bucket
	its loop never visits). Counting either one differently would slide every
	`cube_start` this family records, and `.2` colours a lamp by that index.
	"""
	var n := 0
	for entry: Variant in block_batch:
		var kind: int = (entry as Dictionary).get("kind", ChunkBatch.BoxKind.CUBE)
		if ChunkBatch.BoxKind.find_key(kind) == null:
			kind = ChunkBatch.BoxKind.CUBE
		if kind == ChunkBatch.BoxKind.CUBE:
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
