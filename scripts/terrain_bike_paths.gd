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
## ============================================================================
## TIER 1 — THE TRUNK ROUTES (epic `godot-test1-pnvb`, child `.2`)
## ============================================================================
## Owner, 2026-09-19, having played what the paragraphs above describe (Russian,
## paraphrased): *"they are TOO SMALL and TOO RANDOM. They should look like a REAL
## ROAD NETWORK — they should LEAD somewhere, be long, maybe even cross via
## BRIDGES, you should be able to GET TO BUDAPEST along them, and there should be
## INTERSECTIONS."*
##
## He is describing exactly what the spur tier does. A path is 30 to 120 m in a
## field kilometres across; its bearing is `rng.randf() * TAU`; and every one of
## `_station_blocked`'s seven tests TRUNCATES it. By construction it starts
## nowhere, ends nowhere and connects to nothing.
##
## So a SECOND TIER, on top of the first rather than in place of it. A TRUNK is a
## polyline between two named anchors of `bike_network.gd`'s graph — the HQ, the
## teleport circles, the corridor landmarks and Budapest's gate. Everything below
## the walk is the spur tier's, unchanged: the same strip, the same dash, the same
## pole, the same four signs, the same head, the same midpoint assignment rule,
## the same marker, the same single emission site, the same CUBE bucket.
##
## ### THE HOMING WALK — the shipped recurrence with a pursuit term
## `_next_heading()` restores toward `heading0`. A trunk passes it THE BEARING TO
## ITS TARGET, RECOMPUTED AT EVERY STATION, and that is the entire change: the
## restore term becomes a pursuit term, so the walk wanders enough to read as a
## road that follows the ground and still always arrives. `_bike_turn()` is reused
## VERBATIM, keyed on the EDGE ID in place of the origin chunk.
##
## Arrival is an ASSIGNMENT and not a tolerance: within one `BIKE_STATION_SPACING`
## of the target the last station is written to the anchor's own `Vector2`. THAT
## IS WHAT MAKES THE OWNER'S INTERSECTIONS EXACT — two trunks sharing an anchor
## meet at it to the bit, because both are defined to end there. There is no "did
## they meet?" query anywhere, no lattice and no snapping tolerance.
##
## ### A TRUNK CONSUMES NOT ONE RNG DRAW, FROM ANY STREAM INCLUDING THIS FAMILY'S
## The graph is a hash dispatch (`bike_network.gd`). The route is `_bike_turn`, a
## hash. There is no rarity roll (the edge exists or it does not), no start offset
## (the anchor IS the start), no bearing roll (the target IS the bearing) and no
## length roll (the target IS the length). A trunk is strictly CHEAPER in draws
## than a spur, which rolls all four. The spur stream in `_bike_path_at` is
## untouched by this tier — same four draws, same order.
##
## ### BLOCKING IS DIFFERENT, AND THAT IS THE CRUX
## A spur TRUNCATES at all seven tests. A trunk must not, or it stops leading
## anywhere, so each test is re-decided:
##   * THE MOUNTAIN massif is still impassable stone. A trunk that meets one
##     STEERS AROUND IT (`_trunk_skirt`), and if it cannot clear inside
##     `TRUNK_DETOUR_MAX` stations it is ABANDONED WHOLE. Never truncated: half a
##     trunk is the litter this epic exists to remove.
##   * THE RIVERS DO NOT BLOCK ANY MORE, AND `.3` HAS LANDED: a crossing is
##     carried on a real field DECK, built by `FieldBridges._field_bridge_row_from`
##     through the terrain's forwarder and emitted at this family's own single
##     emission site. A segment over water is still never painted AT GROUND LEVEL —
##     the deck is the paint there — and where a crossing is refused (no dry
##     abutment, or a keep-out) the gap `.2` shipped simply stays. The one thing
##     that can still stop a whole trunk is a LAKE: past
##     `FieldBridges.FIELD_BRIDGE_MAX_SPAN` of walked water the edge is abandoned,
##     reported as "lake" by `trunk_abandoned`. Nothing softlocks — a bike path is
##     never anyone's only route.
##   * THE COIN ROAD is where the WALK and the PAINT part company, and `.4` owns
##     what is left. A trunk that meets the swath MID-SPAN — away from both of its
##     own anchors — is still abandoned whole, and `bike_path_selfcheck` check 3
##     PRINTS how many that is on every seed; that number is `.4`'s case. But the
##     swath is ALSO inside `trunk_keep_out`, so within `TRUNK_APPROACH_RADIUS` of
##     its own anchor a trunk may WALK the corridor and draws none of it. That
##     matters because `BudapestPlan.GATE` sits DEAD CENTRE in the swath (the road's
##     approach corridor ends exactly there), so the alternative — refusing the road
##     before the exemption — abandons every edge incident on the gate and the
##     owner's *"get to Budapest along them"* becomes unreachable. Measured on all
##     three CI seeds, in round 2 of this bead's review. No coin can land on a strip
##     because no strip is there.
##   * BUDAPEST's rect still stops a trunk, AT THE RECT EDGE. The gate anchor is
##     ON that edge (x = 1600), which is how *"you should be able to get to
##     Budapest along them"* comes out true. An edge with one end inside the rect
##     is walked FROM THE OUTSIDE END so it leads into the city rather than dying
##     on its first station; an edge with both ends inside is not drawn at all,
##     because Budapest's streets are authored and `in_budapest()` exists to refuse
##     a procedural strip across Váci utca.
##   * THE TOWER DISC, THE WAYPOINT CIRCLES AND THE LANDMARK SITES are now
##     DESTINATIONS. They keep refusing every trunk that is not heading for them,
##     and they are skipped inside `TRUNK_APPROACH_RADIUS` of this edge's OWN two
##     endpoints — one radius, derived from the largest of them (the tower's 65 m
##     disc), because a trunk to the HQ has to be allowed to reach the HQ. THE WALK
##     IS LET THROUGH AND THE PAINT IS NOT: the HQ anchor is the tower's own centre,
##     so `_draw_path_share` asks `trunk_keep_out()` again at draw time and emits
##     nothing — no strip, no dash, no pole, no footprint — inside the disc. Owner
##     ruling, 2026-09-19, after `tower_site_selfcheck` caught the first build of
##     this bead standing collision shapes 19.9 m from the tower: stop the trunk at
##     the disc, never exempt the trunk from the disc.
##
## ### FINDING A TRUNK FROM A CHUNK: A BOUNDING BOX, NOT A RADIUS SCAN
## `scan_radius_chunks()` works because a spur reaches 120 m. A TRUNK IS
## KILOMETRES LONG AND NO BOUNDED NEIGHBOURHOOD SCAN CAN FIND IT. So this tier
## does what `terrain_bridges.gd`'s `approach_bridges()` already does with the
## authored city corridor: build every route ONCE per run, memoize it on the
## terrain (`_bike_trunk_cache`), and per chunk reject on each trunk's BOUNDING
## BOX. Only the survivors are walked, and then by the SHIPPED MIDPOINT RULE,
## unchanged. `scan_radius_chunks()` stays exactly as it is, for the spur tier.
##
## ----------------------------------------------------------------------------
## SCARCITY: THE ROUTE IS TOPOLOGY AND EXEMPT; THE FURNITURE IS CONTENT AND THINNED
## ----------------------------------------------------------------------------
## This is the split the epic turns on, and both halves are implemented.
##
## **THE ROUTE IS EXEMPT.** No `scarcity_at()` gate on whether a trunk exists, nor
## on whether a segment of strip or dash is drawn. The justification is
## `scarcity_at()`'s OWN banner, on the geo landmarks, and it is quoted here
## because the argument is what makes the exemption legitimate:
##
## > *"since bead godot-test1-bcf each kind exists exactly ONCE IN THE WORLD, so
## > there is no population for a gradient to thin and multiplying a single
## > existence by k would be a lottery rather than a thinning."*
##
## A TRUNK IS A SINGLETON ON IDENTICAL GROUNDS. There is no population of "the
## HQ-to-Museum trunk" for k to thin; multiplying one existence by k is a lottery,
## and the lottery's losing ticket is a DISCONNECTED NETWORK. The trunk tier is
## the landmark exemption extended to the edges of a graph whose vertices already
## hold it. CLAUDE.md names it in plain words as the second of the world's two
## scarcity exemptions, beside the mountain massif (owner Ruling 4, 2026-09-19:
## *"a rule nobody can see is a rule someone breaks next month"*).
##
## **THE FURNITURE IS NOT EXEMPT.** Every pole — and therefore every sign and
## every traffic head standing on one — goes through `terrain._scarcity_keep()`,
## FORM 3, a post-draw `continue` immediately before the pole's first
## `create_box`. A trunk far out is bare paint with nothing on it: content thins
## with distance exactly as the ruling demands, and connectivity survives.
## SPURS ARE NEVER EXEMPT and stay on form 2, unchanged from `z2yv.1`.
##
## **IT IS CHEAP, AND CHEAP IS NOT UNNECESSARY. DO NOT DELETE IT.** Owner Ruling 3
## made trunk endpoints corridor-only, and k is exactly 1 across the whole of
## `SCARCITY_CORRIDOR_RECT` union `BudapestPlan.rect()` — so in practice the route
## exemption almost never fires and the furniture is almost never thinned. The
## rule still has to be TRUE AT THE EDGES: a trunk bowing outside the corridor
## mid-span (measured — it happens), a retuned `SCARCITY_CORRIDOR_RECT`, a moved
## tower (`tower_site_selfcheck` drives it far out), a seed whose road wanders
## past the 129 m envelope that rect's own comment claims (it does — see
## `bike_network.gd`'s EDGE CASE section and bead `godot-test1-q184`).
## **AN EXEMPTION DELETED BECAUSE IT LOOKED UNUSED IS THE BUG.** Check T3a drives
## both code paths directly at a synthetic k = 0 rather than hunting for a seed
## that happens to reach one, precisely so that neither half can rot unnoticed.
##
## ----------------------------------------------------------------------------
## THE MEMO LIVES ON THE TERRAIN NODE
## ----------------------------------------------------------------------------
## `_bike_path_cache` (the spurs) and `_bike_trunk_cache` (the trunk routes) are
## both declared in `endless_terrain.gd` and reset in `_drop_seeded_memos()`, like
## every other seeded memo (`_landmark_sites_cache`, `_field_bridge_cache`). NOT
## `static var`s here: memo state a `_drop_seeded_memos()` cannot reach survives
## every re-seed and hands a multiplayer joiner the wrong world —
## `chunk_stream_selfcheck` check 6c fails the build for it.

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
# TIER 1 — THE TRUNK ROUTE (see the banner)
# ============================================================================

## The pseudo-origin ROW a trunk's turn hash is keyed on. `_bike_turn` and
## `_pole_top` are keyed on `(origin.x, origin.y, station)`, and a trunk has no
## origin chunk — it has an EDGE ID. Passing `Vector2i(edge_id, TRUNK_TURN_ROW)`
## reuses both hashes VERBATIM rather than writing a second copy of either, which
## is what the bead asks for and what stops two turn tables drifting apart.
##
## The row is out of the world rather than merely unlikely: chunk y = 777000 at
## `chunk_size` 50 is 38,850 km from the origin, so no spur origin the streamer
## can ever reach shares a key with a trunk.
##
## AND THE COLLISION ARGUMENT SURVIVES THE INT32 NARROWING, which is the bound that
## actually applies and not the 64-bit one an earlier draft of this comment claimed
## (round 1 of the review). `origin.y * BIKE_TURN_PRIME_Y` is ~5.5e13 and goes into
## a `Vector3i` component, whose values are limited to 32 bits — the wrap is silent
## and deterministic, and `scripts/budapest_streamer.gd` records the same thing one
## family along. It is still collision-free because `BIKE_TURN_PRIME_Y` is ODD and
## therefore invertible mod 2^32, so only `origin.y == TRUNK_TURN_ROW` can land on
## this row. RETUNE AGAINST THAT and not against 64 bits: a row of 3e9 would not
## survive the narrowing as a distinct value at all.
const TRUNK_TURN_ROW: int = 777000

## How far past the straight-line station count a homing walk may wander before
## it is abandoned. The walk's heading is clamped to `BIKE_MAX_HEADING_DEG` of the
## bearing to the target, so every station closes the gap by at least
## `BIKE_STATION_SPACING * cos(42 deg)` = 3.7 m — a factor of 1.35 is the
## arithmetic floor and 3.0 leaves room for the mountain skirt below. A trunk that
## has not arrived by then is ABANDONED WHOLE and check 3 counts it.
const TRUNK_MAX_STATION_FACTOR: float = 3.0

## Inside this of either of the edge's OWN endpoints, the tower disc, the waypoint
## circles, the landmark sites AND THE COIN ROAD'S SWATH stop refusing the WALK:
## they are this trunk's DESTINATION, not an obstacle. They do not stop refusing the
## PAINT — `trunk_keep_out` runs them all again at draw time, so a trunk walks the
## last stretch to its anchor and draws none of it. The road is in that list because
## `BudapestPlan.GATE` sits dead centre in the swath; see `_trunk_blocked`, and the
## banner. DERIVED FROM THE LARGEST OF THEM — the
## tower's `TOWER_RADIUS` is 65 m, so a trunk to the HQ anchor (which is the
## tower's own centre) has to be allowed the last 65 m — plus one station stride.
## Typed here rather than read off the terrain because `EndlessTerrain` declares
## no `class_name` and a `const` cannot call a method; the number is asserted
## against `terrain.TOWER_RADIUS` in `bike_path_selfcheck` check 3 so it cannot
## drift from the disc it was derived from.
const TRUNK_APPROACH_RADIUS: float = 65.0 + BIKE_STATION_SPACING

## The mountain skirt: how far each try swings the heading, and how many tries.
## Eight times 18 degrees reaches +/-144 degrees, so a trunk can turn back on
## itself to leave a pocket it walked into. Both signs are tried at every
## magnitude, nearest first, so the route hugs the massif rather than jumping.
const TRUNK_SKIRT_DEG: float = 18.0
const TRUNK_SKIRT_TRIES: int = 8

## How many CONSECUTIVE stations a trunk may spend skirting a massif before it is
## abandoned whole. At 5 m a station that is 120 m of wall followed, which is more
## than any massif the corridor holds (measured: the worst edge of the three CI
## seeds meets 115 m of MOUNTAIN on a straight line between its anchors). Past it
## the honest answer is that the two anchors are not connectable by a bike path.
const TRUNK_DETOUR_MAX: int = 24

## A route shorter than this is not a trunk. Two stations is one segment, which is
## the smallest thing that can be drawn at all — the length floor a SPUR needs
## (`BIKE_PATH_MIN_STATIONS`, "a two-station stub is litter") does not apply here,
## because a trunk's length is its anchors' business and two anchors 8 m apart
## deserve the 8 m of paint that joins them.
const TRUNK_MIN_STATIONS: int = 2

## THE FORM-3 INDEX OFFSET FOR TRUNK FURNITURE, AND IT IS PART OF THE WORLD.
## `terrain._scarcity_keep(chunk_pos, index, k)` hashes the index, so every family
## sharing a chunk needs its own band or two families' poles are thinned together
## (`terrain_biomes.gd` spends `_i + 1000` on the city's stalls and `_i + 2000` on
## its lights). This tier takes 3000 upward, and the EDGE STRIDE inside it is what
## keeps two trunks crossing one chunk from sharing a roll at the same station
## index. 4096 is comfortably past the longest route the station ceiling permits.
## CHANGING EITHER NUMBER MOVES EVERY THINNED TRUNK POLE IN THE WORLD.
const TRUNK_SCARCITY_INDEX_OFFSET: int = 3000
const TRUNK_SCARCITY_EDGE_STRIDE: int = 4096

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
## field is a joke that stops being funny at every fourth pole.
##
## WHAT THAT MIX ACTUALLY PRODUCES, counted rather than guessed (round 1 found the
## first version of this paragraph was out by a factor of two, and it is the number
## the next author retunes `BIKE_PATH_CHANCE`, `BIKE_POLE_STRIDE` or this table
## against). A path of `n` stations carries `floor((n - 1) / BIKE_POLE_STRIDE)`
## poles, and `n` is uniform on [6, 24], so the mean is 59/19 = 3.1 poles — BEFORE
## truncation and the `_footprint_taken` skip take more. At 8:1 that is about 2.8
## signs a path and one head roughly every third path.
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

## HOW FAR FORWARD OF THE POST'S CENTRE THE PLATE STANDS, and it is derived rather
## than typed because getting it wrong is invisible in every count and every index:
## a plate centred on the post is INSIDE it (the post is `BIKE_POLE_WIDTH` square,
## so it spans +/- 0.08 along the approach axis and the plate is 0.05 thick), and
## every sign reads with a grey bar down its middle. The plate's BACK face touches
## the post's FRONT face. `_build_sign` carries the full reasoning and the
## self-check's clearance assertion measures it off the drawn boxes.
const SIGN_STANDOFF: float = BIKE_POLE_WIDTH * 0.5 + SIGN_PLATE_DEPTH * 0.5
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
# TIER 1 — THE TRUNK ROUTE: the homing walk between two anchors
# ============================================================================

static func trunks(terrain: Node3D) -> Array[Dictionary]:
	"""
	EVERY TRUNK IN THE WORLD, walked once per run and memoized on the terrain.

	@param terrain: The `EndlessTerrain`.
	@return: Rows of `{ id: int (the edge id), stations: Array[Dictionary] in the
	         walk order `_draw_path_share` expects, box: Rect2 (the route's
	         bounding box in world XZ, padded by one segment length), from: Vector2,
	         to: Vector2, bridges: Array (the field-bridge rows this route's river
	         crossings need, child `.3`) }`, for the edges that produced a route at
	         all. The memo itself, not a copy — it is asked once per chunk.

	AN EDGE THAT WAS ABANDONED IS SIMPLY ABSENT, which is the only honest shape:
	a half trunk is the litter this epic exists to remove, so the alternatives are
	a whole route or none. `bike_path_selfcheck` check 3 counts the absences and
	prints why each one happened.

	BUILT ALL AT ONCE rather than per edge on demand: the per-chunk lookup rejects
	on every trunk's bounding box, so the first chunk of the run needs all of them
	whatever the memo's shape. See `_bike_trunk_cache`'s declaration.

	WHAT IT COSTS, MEASURED on the three CI seeds rather than estimated: the COLD
	call is 6.8 to 12.0 ms — 17 to 32 edges walked at 5 m a station, each station
	asking the road's lateral distance, the landmark table and eleven waypoints,
	and then each surviving route walked again at half that pitch against the river
	field for child `.3`'s bridge scan — and it is paid ONCE per run, by whichever
	chunk streams in first. (It was 6.3 ms before `.3`, and 8 to 17 ms when that
	scan sampled at the approach corridor's metre; `bike_trunk_bridges` carries the
	reasoning for the pitch it settled on.) Every chunk after it pays a dictionary
	hit and tens of `Rect2.intersects`: the whole of `spawn_bike_path_in_chunk`,
	BOTH TIERS, measures 0.065-0.072 ms per corridor chunk and 0.376 ms on one
	carrying a deck, where it mitres two rail lines and walks the slabs.
	`bike_path_selfcheck` check T4 prints the memo's size every run.

	COSTS NO DRAW. See the banner: the graph is a dispatch and the walk is a hash.
	"""
	var cache: Dictionary = terrain._bike_trunk_cache
	if cache.has("trunks"):
		return cache["trunks"]
	var out: Array[Dictionary] = []
	# THROUGH THE TERRAIN'S FORWARDERS and never `BikeNetwork` by name — CLAUDE.md,
	# Conventions: a static family reaches a sibling family through the node that
	# owns the state, because a class-name reference is a parse-time edge and `.4`
	# is about to add one the other way.
	var anchors: Array[Dictionary] = terrain.bike_anchors()
	# Read ONCE for every edge, `_station_blocked`'s note: the table is not memoized
	# and it is pure in `run_seed`, so it is loop-invariant here.
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	for edge: Dictionary in terrain.bike_edges():
		var route: Array[Dictionary] = _trunk_route(terrain, anchors, edge)
		if route.size() < TRUNK_MIN_STATIONS:
			continue
		# --- THE RIVERS (child `.3`). A trunk crosses one ON A REAL DECK, built by
		# the shipped `FieldBridges._field_bridge_row_from` through the terrain's
		# forwarder — the family reaches its sibling through the node that owns the
		# state, never by name. A LAKE (past FIELD_BRIDGE_MAX_SPAN of walked water)
		# abandons the whole edge, because a half trunk is the litter this epic
		# exists to remove and a bike path is never anyone's only route, so nothing
		# can softlock either way.
		var water: Dictionary = terrain.bike_trunk_bridges(
				_trunk_poly(route), BIKE_PATH_WIDTH * 0.5, BIKE_STATION_SPACING)
		if bool(water["refused"]):
			continue
		var decks: Array = _drawable_decks(terrain, water["rows"], waypoints)
		# THE ROUTE'S BOX HAS TO HOLD THE DECKS TOO. A deck's ramp foot stands a
		# whole ramp run plus its push budget PAST the last station it was built
		# from, and the box is what the per-chunk lookup rejects on — so a chunk
		# holding nothing but that ramp would reject the trunk before the deck pass
		# ever ran, and the ramp would silently never be drawn. Merging is free:
		# the box is a rejection filter, so a wider one costs a few `Rect2` tests
		# and the midpoint rule still decides who draws what.
		var box: Rect2 = _trunk_box(route)
		for row_v: Variant in decks:
			box = box.merge((row_v as Dictionary)["box"] as Rect2)
		out.append({
			"id": int(edge["id"]),
			"stations": route,
			"box": box,
			"from": route[0]["pos"],
			"to": route[-1]["pos"],
			"bridges": decks,
		})
	cache["trunks"] = out
	return out


static func _trunk_poly(route: Array[Dictionary]) -> PackedVector2Array:
	## A route's station positions alone — what the bridge scan walks.
	var out := PackedVector2Array()
	for station: Dictionary in route:
		out.append(station["pos"])
	return out


static func _drawable_decks(terrain: Node3D, rows: Array,
		waypoints: Array[Dictionary]) -> Array:
	"""
	The decks of `rows` this family is ALLOWED to draw — the keep-out rule applied
	to the stone as well as to the paint.

	A DECK IS PAINT WITH COLLISION, so it is exactly what `trunk_keep_out` is for:
	`bike_path_selfcheck` T5 sweeps EVERY box this family emits against the tower's
	disc, the teleport circles, the landmark chunks and the coin road's swath, and a
	sixteen-box deck inside one would be the same defect as a post inside one (three
	of the five failures that check exists for were collision shapes). The walk's
	endpoint exemption lets a trunk REACH its own anchor through a disc; it has
	never let it build there.

	FILTERED HERE AND NOT AT DRAW TIME, so the row is absent from
	`field_bridges_near()` too — a registered deck nobody draws would tell
	`field_bridge_surface_y` there is stone where a player finds water.

	A dropped deck leaves the un-painted gap `.2` already ships. It is rare — a
	crossing has to fall inside a disc — and `bike_path_selfcheck` B2 counts it.
	"""
	var out: Array = []
	for row_v: Variant in rows:
		var row: Dictionary = row_v
		# THE STONE, NOT THE WALKING LINE. A parapet is cantilevered `row["rail"]`
		# outboard of the centreline, and the LANDMARK keep-out is a chunk boundary
		# with no margin at all — so a deck point a metre outside one puts its rail
		# inside it, and T5 sweeps box centres. The four corners of the rail square
		# are enough for that: a chunk boundary is axis-aligned, so the square's
		# extreme point in the direction that crosses it is a corner. The other
		# three keep-outs carry margins well past it (5 m at the tower, 3 m at a
		# circle, 14 m at the road) and were never in doubt.
		#
		# IT IS THE BOX CENTRE AND NOT THE STONE'S OUTER FACE, which is the same
		# ruling the strip already ships under: a box may overhang a boundary the
		# way any box overhangs a chunk seam, and what may not stand inside one is
		# a thing. MEASURED over B2's eight seeds and 24 crossings: 11 decks with no
		# lateral test at all, 10 with this one, and 8 when the offset used was the
		# stone's outer reach instead — a quarter of the world's crossings for
		# 0.25 m of parapet edge, which is a trade nobody would make. The 1 deck
		# this test does cost is a crossing whose rail really did reach a keep-out.
		var pad: float = row["rail"]
		var clear: bool = true
		for pt: Vector2 in (row["poly"] as PackedVector2Array):
			for corner: Vector2 in [Vector2.ZERO, Vector2(pad, pad), Vector2(pad, -pad),
					Vector2(-pad, pad), Vector2(-pad, -pad)]:
				if trunk_keep_out(terrain, pt + corner, waypoints):
					clear = false
					break
			if not clear:
				break
		if clear:
			out.append(row)
	return out


static func trunk_abandoned(terrain: Node3D, edge: Dictionary) -> String:
	"""
	WHY the trunk on `edge` does not exist, or "" when it does.

	@return: One of "", "lake" (child `.3`: a river crossing wider than
	         `FieldBridges.FIELD_BRIDGE_MAX_SPAN` of walked water — standing water
	         rather than a river, and no deck is built over it), "city" (both anchors
	         inside Budapest's authored rect),
	         "mountain" (walled in, or still skirting after `TRUNK_DETOUR_MAX`
	         stations), "road" (the coin road's swath, which `.4` owns), "site" (a
	         waypoint circle, a landmark or the tower disc it was not heading for),
	         "lost" (the station ceiling ran out) or "short" (it stopped at
	         Budapest's rect edge with fewer than `TRUNK_MIN_STATIONS` stations —
	         the common case is an edge that starts AT the gate, which sits exactly
	         on the boundary, and heads into the city).

	THE KEY SET IS A CONTRACT, not a description: `bike_path_selfcheck` check 3
	prints the histogram and `.3` / `.4` build their case on it, so a seventh exit
	added to `_trunk_route` owes a line here. Round 1 of the review caught "short"
	missing from this list.

	PUBLIC AND SEPARATE FROM THE WALK because `bike_path_selfcheck` check 3 has to
	report the reasons rather than a count, and because the ONE number that makes
	`godot-test1-pnvb.4`'s case is how many trunks the coin road is costing the
	network today. The walk itself records the reason as it goes; this is the
	reader.
	"""
	var reason: Array[String] = [""]
	_trunk_route(terrain, terrain.bike_anchors(), edge, reason)
	if reason[0] != "":
		return reason[0]
	# THE WALK SUCCEEDED AND THE EDGE IS STILL ABSENT, so the water refused it —
	# `trunks()` is the only other place an edge is dropped, and the lake is the only
	# reason it drops one (child `.3`). Asked of the MEMO rather than re-scanned, so
	# this reader can never disagree with the table it reports on.
	for trunk: Dictionary in trunks(terrain):
		if int(trunk["id"]) == int(edge["id"]):
			return ""
	return "lake"


static func _trunk_route(terrain: Node3D, anchors: Array[Dictionary], edge: Dictionary,
		reason: Array[String] = []) -> Array[Dictionary]:
	"""
	THE HOMING WALK from one anchor to the other. A pure function of (edge id,
	`run_seed`), and it consumes no RNG at all.

	@param anchors: `terrain.bike_anchors()`, passed in because the caller walks
	                every edge against the same table.
	@param reason: Optional single-element out-parameter for `trunk_abandoned`.
	@return: The stations, `{ "pos": Vector2, "heading": float }`, or `[]`.

	THE RECURRENCE IS `_next_heading()`, UNCHANGED, with one substitution: where a
	spur passes its fixed initial bearing as `heading0`, a trunk passes THE BEARING
	TO ITS TARGET, RECOMPUTED HERE AT EVERY STATION. The restore term therefore
	pulls the walk toward the anchor instead of toward a heading it rolled once,
	which is the difference between a wander and a road, and the clamp to
	`BIKE_MAX_HEADING_DEG` of that bearing is what guarantees arrival.

	THE WRAP ON THE INCOMING HEADING IS LOAD-BEARING AND EASY TO MISS. `heading0`
	moves every station, so `heading - heading0` can come out near +/-TAU where the
	two straddle the +/-PI cut — a pure artefact of the angle's representation that
	the clamp would then read as a huge drift and pin at the cap, spiralling the
	trunk. `wrapf(..., -PI, PI)` puts the difference on the short way round before
	`_next_heading` ever sees it, and re-adding `bearing` keeps the argument in the
	shape that function's own arithmetic expects. It is done HERE, at the call
	site, so `_next_heading` itself stays the spur tier's verbatim.

	ARRIVAL IS AN ASSIGNMENT. Inside one `BIKE_STATION_SPACING` of the target the
	last station is written to the anchor's own `Vector2`, so two trunks sharing
	an anchor hold EXACTLY the same terminal position and the owner's intersection
	is exact rather than within a tolerance. The first station is the other anchor
	by the same assignment, which is why an anchor shared as one edge's `a` and
	another's `b` still meets to the bit.
	"""
	if not reason.is_empty():
		reason[0] = ""
	var from: Vector2 = anchors[int(edge["a"])]["pos"]
	var to: Vector2 = anchors[int(edge["b"])]["pos"]
	# WALKED FROM THE END OUTSIDE THE CITY. The rect stops a trunk, so an edge whose
	# `a` happens to be a city waypoint would otherwise die on its first station and
	# the route that leads INTO Budapest — the owner's headline — would never be
	# drawn. Direction is otherwise immaterial: the turn hash is keyed on the edge
	# id, not on the walk order, so this is a pure function either way.
	if _anchor_in_city(terrain, from) and not _anchor_in_city(terrain, to):
		var swap: Vector2 = from
		from = to
		to = swap
	if _anchor_in_city(terrain, from):
		# Both ends authored. Budapest's streets are its own.
		if not reason.is_empty():
			reason[0] = "city"
		return []

	var key := Vector2i(int(edge["id"]), TRUNK_TURN_ROW)
	# The waypoint table, read ONCE for the whole walk — `_station_blocked`'s note.
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var ceiling: int = int(ceil(
			from.distance_to(to) / BIKE_STATION_SPACING * TRUNK_MAX_STATION_FACTOR)) + 1

	var stations: Array[Dictionary] = []
	var pos: Vector2 = from
	var heading: float = (to - from).angle()
	var detour: int = 0
	var arrived: bool = false
	var at_rect: bool = false
	for i in ceiling:
		stations.append({ "pos": pos, "heading": heading })
		if pos.distance_to(to) <= BIKE_STATION_SPACING:
			# THE SNAP — an assignment, never a tolerance. See the docstring.
			stations.append({ "pos": to, "heading": (to - pos).angle() })
			arrived = true
			break
		var bearing: float = (to - pos).angle()
		var want: float = _next_heading(terrain, key, bearing,
				bearing + wrapf(heading - bearing, -PI, PI), i)
		var step: Vector2 = pos + Vector2(cos(want), sin(want)) * BIKE_STATION_SPACING

		# --- THE MASSIF. Steer around it, or be abandoned whole; never truncated.
		if terrain.biome_at(step.x, step.y) == terrain.Biome.MOUNTAIN:
			var skirt: float = _trunk_skirt(terrain, pos, want)
			detour += 1
			if is_nan(skirt) or detour > TRUNK_DETOUR_MAX:
				if not reason.is_empty():
					reason[0] = "mountain"
				return []
			want = skirt
			step = pos + Vector2(cos(want), sin(want)) * BIKE_STATION_SPACING
		else:
			detour = 0

		# --- THE AUTHORED CITY stops the trunk AT THE RECT EDGE. The one blocking
		# test that truncates rather than abandons, because the prefix outside the
		# rect is a real road that leads to the city and the owner asked for it.
		if terrain.in_budapest(step.x, step.y):
			# ...UNLESS THE STEP HAS ARRIVED. The gate stands ON the boundary and the
			# walk comes in at an angle, so a station one stride from it can already
			# be a metre inside the rect. Breaking there would leave the route 6 m
			# short of the one anchor the owner's *"get to Budapest along them"* is
			# about, with nothing to show for it but a strip that stops in a field.
			# The arrival snap wins, and the bound is on the STEP, so the final
			# segment — measured from `pos`, one stride behind it — is at most TWO
			# strides of paint. That is 10 m, which can never be a long strip laid
			# across an authored street, and the gate sits on the boundary anyway.
			if step.distance_to(to) <= BIKE_STATION_SPACING:
				stations.append({ "pos": to, "heading": (to - pos).angle() })
				arrived = true
			else:
				at_rect = true
			break
		if _trunk_blocked(terrain, step, waypoints, from, to, reason):
			return []
		heading = want
		pos = step

	if not arrived and not at_rect:
		# The ceiling ran out in open field. A trunk that ends nowhere is exactly
		# the defect the owner reported, so it does not exist.
		if not reason.is_empty():
			reason[0] = "lost"
		return []
	if stations.size() < TRUNK_MIN_STATIONS:
		if not reason.is_empty():
			reason[0] = "short"
		return []
	return stations


static func _trunk_blocked(terrain: Node3D, p: Vector2, waypoints: Array[Dictionary],
		from: Vector2, to: Vector2, reason: Array[String] = []) -> bool:
	"""
	May a TRUNK station stand at this world XZ? `_station_blocked`'s seven tests,
	re-decided for a route that has to lead somewhere.

	@param from / @param to: This edge's own two anchors. Inside
	                         `TRUNK_APPROACH_RADIUS` of either, EVERY test below is
	                         skipped, the coin road included — the walk is entitled
	                         to reach its own anchor. The PAINT is not: the same
	                         tests run again at draw time through `trunk_keep_out`.
	@return: true when the trunk must be abandoned whole.

	FOUR OF THE SEVEN ARE HERE. The mountain is the caller's (it skirts before it
	gives up), Budapest's rect is the caller's (it truncates there rather than
	abandoning), and the rivers do not block a trunk at all any more — `.3` bridges
	them and until then the segment is simply not drawn.

	PURE IN (POSITION, SEED), like the spur predicate and for the same reason: the
	route is rebuilt from scratch every time the memo is dropped, and every chunk
	that draws a share of it must get the identical polyline back.
	"""
	# THE ENDPOINT EXEMPTION, AND IT COVERS THE ROAD TOO — which took two rounds of
	# review to get right, so the reasoning is written out rather than assumed.
	#
	# Round 1 found the road being exempted here while the banner claimed it was
	# not, and the fix was to test the road FIRST and never exempt it. Round 2 found
	# what that costs: `BudapestPlan.GATE` is (1600, 0) and the coin road's APPROACH
	# CORRIDOR ends exactly there, so `_road_lateral_distance` at the gate anchor is
	# 0.0 — the gate sits dead centre in the swath. Testing the road first therefore
	# abandons EVERY edge incident on the gate, and the gate is the anchor this
	# whole epic is pointed at: *"you should be able to GET TO BUDAPEST along them"*.
	# Measured on all three CI seeds.
	#
	# SO THE WALK IS EXEMPT AND THE PAINT IS NOT — the same ruling the tower disc
	# already ships under, and the mechanism the epic prescribes for the road:
	# `trunk_keep_out` carries the swath, so `_draw_path_share` draws NOTHING within
	# `BIKE_ROAD_CLEARANCE` of the centreline and no coin can land on a strip
	# because no strip is there. What round 1's finding was actually about — 70 m of
	# strip down the middle of the coin swath — is now impossible, and the gate is
	# reachable again.
	#
	# `godot-test1-pnvb.4` STILL OWNS THE CROSSING. A trunk that meets the swath
	# MID-SPAN, away from either of its own anchors, is still abandoned whole below;
	# check 3 prints how many that is, and that number is still `.4`'s case.
	if p.distance_to(from) < TRUNK_APPROACH_RADIUS or p.distance_to(to) < TRUNK_APPROACH_RADIUS:
		return false
	# Split for the REPORT and not for the rule: `trunk_keep_out` would answer both,
	# but check 3's histogram tells "road" from "site" and `.4`'s case is the first
	# number. The road is last because it is the one test that may grow the station
	# cache.
	if trunk_keep_out(terrain, p, waypoints):
		if not reason.is_empty():
			reason[0] = "site" if not _road_swath(terrain, p) else "road"
		return true
	return false


static func _road_swath(terrain: Node3D, p: Vector2) -> bool:
	"""
	Is this world XZ inside the coin road's clearance swath?

	THE ONE SPELLING OF IT IN THIS TIER, and `trunk_keep_out` calls it too rather
	than writing the comparison out a second time — `BIKE_ROAD_CLEARANCE`'s own note
	says a second opinion about that number is what puts a bike path under the
	road's coins, and two literal copies fifty lines apart is exactly how a second
	opinion starts. (`_station_blocked` test 7 is the spur tier's copy and predates
	this; it is left alone because this bead does not touch that walk.)

	`_trunk_blocked` also uses it to decide WHICH BUCKET a refusal is reported in —
	"road" or "site" — which is a report and not a rule.
	"""
	return terrain._road_lateral_distance(p.x, p.y, BIKE_ROAD_CLEARANCE) < BIKE_ROAD_CLEARANCE


static func trunk_keep_out(terrain: Node3D, p: Vector2,
		waypoints: Array[Dictionary]) -> bool:
	"""
	Is this world XZ somewhere this family must not draw — the tower's disc, a
	teleport circle, a landmark's chunk, or the coin road's swath?

	@param waypoints: `terrain.waypoint_sites()`, read once by the caller.
	@return: true when nothing this family builds may stand here.

	TWO CALLERS, AND THEY ARE THE TWO HALVES OF ONE RULING (owner, 2026-09-19):

	  * `_trunk_blocked` asks it of a station the route is NOT heading for, and
	    abandons the trunk whole — an obstacle.
	  * `_draw_path_share` asks it of a segment the route IS heading for, and
	    DRAWS NOTHING THERE — a destination the route stops at the edge of.

	THE SECOND CALLER EXISTS BECAUSE OF A REAL COLLISION, and it is worth writing
	down so nobody removes it as belt-and-braces. The HQ anchor is
	`tower_site()` — the tower's OWN CENTRE — so a trunk ending there is entitled
	by `TRUNK_APPROACH_RADIUS` to walk its last 65 m straight through the keep-out
	disc that exists to protect the building's authored approach, and the first
	build of this bead did: `tower_site_selfcheck` failed with a marker 35.4 m from
	the tower site and three collision shapes at 19.9, 40.1 and 59.8 m. The two
	rules are each correct on their own and were never considered together.

	THE RULING IS TO STOP THE PAINT, NOT TO EXEMPT IT. The tower is one of this
	project's two authored exceptions and a generated strip has no business inside
	its disc — while a trunk that terminates cleanly at the boundary still leads to
	the HQ in every sense the owner asked for: you can see where it goes, and you
	walk the last 65 m. The same shape of problem belongs to every other
	destination, so this tests all of them rather than only the one that failed.

	THE FOURTH MEMBER IS NOT A DESTINATION AND NOT A DISC. The coin road's swath
	joined this predicate in round 2 of the review, and it is different in kind from
	the other three: a world-spanning linear corridor rather than a point the route
	is heading for, and the one test here that may GROW the road station cache. It
	is in the same predicate because it wants the same answer — the route may walk
	there and may not paint there — and that is the whole of what the two callers
	below ask.

	IT IS A DRAW-TIME SKIP AND NOT A WALK-TIME TRUNCATION — the epic's own coin-road
	shape. The station list is unchanged, the topology `godot-test1-pnvb.1` built is
	untouched, and no RNG is involved at all: the builder generator is fixed-seed
	and this predicate is a hash-free pure function of position.
	"""
	if terrain.tower_excludes(p.x, p.y, BIKE_STATION_SPACING):
		return true
	if terrain.landmark_sites().has(terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))):
		return true
	var clear: float = TerrainWaypoints.RING_RADIUS + BIKE_WAYPOINT_MARGIN
	for site: Dictionary in waypoints:
		var at: Vector3 = site["pos"]
		if Vector2(p.x - at.x, p.y - at.z).length() < clear:
			return true
	# ...AND THE COIN ROAD'S SWATH, last because it is the one test that may grow the
	# station cache. IT IS HERE AND NOT ONLY IN `_trunk_blocked` because the harm the
	# road's refusal exists to prevent is PAINT UNDER COINS, and paint is what this
	# predicate stops: with the road in it, no strip, dash, pole or footprint A TRUNK
	# emits can stand within `BIKE_ROAD_CLEARANCE` of the centreline, whatever the
	# walk was allowed to do. `bike_path_selfcheck` T5 asserts that over every box
	# and every footprint in the chunk.
	#
	# THE SPUR TIER IS NOT COVERED BY THAT SENTENCE, and the distinction is exact
	# rather than pedantic: both draw-time guards in `_draw_path_share` are gated on
	# `edge_id >= 0`. A spur's STATIONS clear the swath (`_station_blocked` test 7)
	# but its POLE is planted `BIKE_POLE_OFFSET` = 1.65 m to the side and nothing
	# re-tests it, so a spur running beside the road with a station at 14.0-15.65 m
	# lateral can put a post in the swath. That is a pre-existing spur-tier gap this
	# bead does not widen and does not close — closing it would remove a footprint
	# and move the crocodiles that footprint displaces, which is a change to the spur
	# tier this bead is meant to leave alone. T5 is deliberately TIER-BLIND, so if a
	# seed ever lines one up the build goes red and that is the right outcome: a
	# finding, not a false alarm.
	return _road_swath(terrain, p)


static func _anchor_in_city(terrain: Node3D, p: Vector2) -> bool:
	"""
	Is this ANCHOR inside Budapest's authored rect, STRICTLY, by a station stride?

	@return: true when a trunk may not start or end here at all.

	THE PLAIN `in_budapest()` IS NOT THE RIGHT TEST HERE, and it took a measurement
	to see it. `Rect2.has_point` is INCLUSIVE on its minimum edge and
	`BudapestPlan.GATE` stands exactly on it (x = 1600, the rect's west face) — so
	the city's own FRONT DOOR reads as "inside the city", every edge touching it
	was refused with reason "city", and the one anchor the owner's *"you should be
	able to GET TO BUDAPEST along them"* is about got no trunk on any seed. Measured
	on all three CI seeds before this function existed.

	ONE STATION STRIDE OF SLACK IS WHAT TELLS THE DOOR FROM THE STREET BEHIND IT,
	and the margin is wide: the gate is ON the boundary and the nearest city
	waypoint (`wp_gate`) is 124 m past it. Tested on all four sides rather than on
	the west alone, because a rect is a rect and the next authored anchor need not
	sit on the face this bug was found on.
	"""
	return terrain.in_budapest(p.x, p.y) \
			and terrain.in_budapest(p.x - BIKE_STATION_SPACING, p.y) \
			and terrain.in_budapest(p.x + BIKE_STATION_SPACING, p.y) \
			and terrain.in_budapest(p.x, p.y - BIKE_STATION_SPACING) \
			and terrain.in_budapest(p.x, p.y + BIKE_STATION_SPACING)


static func _trunk_skirt(terrain: Node3D, pos: Vector2, heading: float) -> float:
	"""
	A heading that steps CLEAR of the massif, or NAN when the walk is walled in.

	@param heading: The heading the homing recurrence wanted, which lands in stone.
	@return: The nearest heading either side of it whose step is out of MOUNTAIN.

	BOTH SIGNS AT EVERY MAGNITUDE, POSITIVE FIRST AND NEAREST FIRST, so the route
	hugs the massif's edge instead of jumping across it, and so the choice is a
	property of the ground rather than of a roll — this consumes no RNG, like
	everything else in the tier.

	IT IS A CRAB-WALK AND NOT A PATHFINDER, honestly. The next station's clamp pulls
	the heading straight back toward the target, i.e. back at the wall, so a long
	massif is followed by alternating between the pursuit term and this skirt. That
	makes lateral progress along the face, and `TRUNK_DETOUR_MAX` is the ceiling on
	how long it may go on before the two anchors are declared unconnectable.
	ponytail: an A* over the biome field would route around a whole massif; it is
	not written because the corridor's massifs are 100 m across, not 1 km, and the
	trunks that fail here are counted and printed rather than silently lost.
	"""
	for n in range(1, TRUNK_SKIRT_TRIES + 1):
		for sign_v: float in [1.0, -1.0]:
			var h: float = heading + sign_v * deg_to_rad(TRUNK_SKIRT_DEG) * float(n)
			var q: Vector2 = pos + Vector2(cos(h), sin(h)) * BIKE_STATION_SPACING
			if terrain.biome_at(q.x, q.y) != terrain.Biome.MOUNTAIN:
				return h
	return NAN


static func _trunk_box(stations: Array[Dictionary]) -> Rect2:
	"""
	A route's bounding box in world XZ, padded by one segment length.

	THE PAD IS A MARGIN AND NOT A REQUIREMENT, and the difference is measured
	rather than asserted. The reasoning for it is real: a chunk is claimed by a
	segment whose MIDPOINT falls inside it, and the strip box drawn for that
	segment is a station stride long, so geometry legitimately overhangs the box
	the stations alone describe. But a chunk is 50 m and a stride is 5, so at the
	shipped `chunk_size` an unpadded box loses nothing — `bike_path_selfcheck`
	check 2d is GREEN with the pad removed entirely, and that is stated here rather
	than left for somebody to discover while trusting a control that does not
	exist. What 2d does catch is a lookup wrong by more than half a chunk: a pad of
	-30 m and an `encloses` in place of the spawner's `intersects` both turn it red.

	So the pad is kept as headroom against a smaller `chunk_size` or a longer
	stride, not as a bug fix, and the next author owes no more than that.
	"""
	var box := Rect2(stations[0]["pos"], Vector2.ZERO)
	for station: Dictionary in stations:
		box = box.expand(station["pos"])
	return box.grow(BIKE_STATION_SPACING)


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

	# --- TIER 1: THE TRUNKS, found by BOUNDING BOX and not by a radius scan.
	# A trunk is kilometres long, so the 9x9 sweep of origin chunks above cannot
	# see one; `approach_bridges()`'s shape is what replaces it (see the banner).
	# Tens of `Rect2.intersects` per chunk against a table built once per run.
	#
	# AFTER THE SPURS AND INSIDE THE SAME SLICE. The batch range this spawner
	# stamps on every marker below covers both tiers, so the kill switch still cuts
	# ONE contiguous run out of the batch however many paths and trunks cross the
	# chunk — which is exactly what check 1 needs and the only ordering requirement
	# either tier has against the other.
	var half: float = terrain.chunk_size * 0.5
	var chunk_rect := Rect2(centre - Vector2(half, half),
			Vector2(terrain.chunk_size, terrain.chunk_size))
	# k AT THE CHUNK'S CENTRE, read ONCE, for the FURNITURE only — the route itself
	# is exempt and is drawn whatever this says. `_scarcity_keep`'s own docstring
	# asks for the chunk centre rather than the object's position.
	var k: float = terrain.scarcity_at(chunk_centre)
	# The teleport circles, read ONCE for every trunk in this chunk — `waypoint_sites()`
	# allocates eleven rows and runs six binary searches per call and is pure in
	# `run_seed`, so it is loop-invariant here exactly as it is in the spur walk.
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var shares: Array[Dictionary] = []
	for trunk: Dictionary in trunks(terrain):
		if not (trunk["box"] as Rect2).intersects(chunk_rect):
			continue
		var edge_id: int = int(trunk["id"])
		var key := Vector2i(edge_id, TRUNK_TURN_ROW)
		var built: Dictionary = _draw_path_share(terrain, chunk_pos, centre, key,
				trunk["stations"], rng, obstacles, block_batch, block_body, cube_cursor,
				edge_id, k, waypoints)
		cube_cursor = built["cube_cursor"]
		shares.append({ "key": key, "edge": edge_id, "built": built,
				"bridges": trunk["bridges"] })

	# --- THE BRIDGES (child `.3`): where a route crosses a river the paint stops and
	# a DECK carries it over.
	#
	# EMITTED HERE, at this family's single emission site, and never from
	# `FieldBridges.spawn_field_bridges_in_chunk` — that spawner runs AFTER this one,
	# so a deck drawn there would split this family's batch entries into two ranges
	# and `bike_path_selfcheck` check 1 could no longer cut ONE contiguous run out of
	# the CUBE bucket. The bridge family is asked only for the ROW (at `trunks()`) and
	# for the emission of one, both of which draw nothing of their own.
	#
	# AND AFTER EVERY ROUTE'S OWN BOXES, IN A SECOND PASS, which is what makes the
	# CUBE-bucket bookkeeping unable to go wrong rather than merely correct: every
	# index a marker records — each pole, each signal's first lens — is taken before
	# the first deck box exists, so no arithmetic here can slide one. Interleaving the
	# two needed `cube_cursor` advanced by the deck's own box count, and check 9's
	# lamp assertion would only have caught it on a chunk that happened to carry both
	# a deck and a later trunk's signal head.
	#
	# THE DECK IS THE PAINT. Its slabs are emitted in BIKE_STRIP_COLOR, so the red line
	# reads as continuous over the water and there is no second flat box lying on the
	# stone at ground height — the defect B2 exists to catch. Each slab takes the
	# centre rule for itself, exactly as a road deck's does.
	#
	# SCARCITY DOES NOT REACH IT: a deck is ROUTE, not furniture, and the route is the
	# epic's named exemption (CLAUDE.md, the second of the two). A crossing with no
	# deck is a gap in the road, not a thinner one.
	for share: Dictionary in shares:
		var before: int = block_batch.size()
		for row_v: Variant in (share["bridges"] as Array):
			# REJECTED ON THE ROW'S OWN BOX FIRST. A trunk's box can reach a 10x10
			# block of chunks and one deck is 40 m of that, so without this every
			# chunk the ROUTE touches would mitre two rail lines and walk every slab
			# of a bridge kilometres away. The box is the deck's stone, trim included.
			if not ((row_v as Dictionary)["box"] as Rect2).intersects(chunk_rect):
				continue
			terrain.emit_field_bridge_in_chunk(row_v, chunk_pos, chunk_centre, rng,
					block_batch, block_body, BIKE_STRIP_COLOR, false)
		# A MARKER WHENEVER THIS CHUNK DREW ANYTHING FOR THIS TRUNK, DECKS INCLUDED —
		# and a chunk holding only the middle of a crossing really does draw a deck and
		# no strip, because the wet segments over it are the ones that are never
		# painted. Check 1 slices the batch using `batch_start` / `cube_start` off the
		# FIRST marker in the chunk, so a deck with no marker beside it is a run of
		# boxes the A/B cannot cut out, and this family would read as having moved
		# somebody else's geometry. `bike_path_selfcheck` B1 asserts the marker.
		#
		# NOT EXERCISED BY ANY CI SEED, and both halves are said plainly because the
		# second is what makes the first worth writing down. A deck is 20-50 m long
		# against a 50 m chunk, so the chunk holding the middle of a crossing has so far
		# always held a dry segment of the same trunk as well — B1 prints the count and
		# it is 0 on seed 20260904 today (measured, mutation M9: deleting the
		# `block_batch.size() == before` clause leaves the whole suite green). It costs
		# one integer compare and the first seed that lines a crossing up with a chunk
		# seam would otherwise turn check 1 red for a reason nobody could read.
		if ((share["built"]["segments"] as PackedInt32Array).is_empty()
				and block_batch.size() == before):
			continue
		markers.append(_make_marker(terrain, share["key"], share["built"], parent_chunk,
				int(share["edge"])))

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
		cube_cursor: int, edge_id: int = -1, k: float = 1.0,
		waypoints: Array[Dictionary] = []) -> Dictionary:
	"""
	One polyline's segments, insofar as they belong to `chunk_pos`.

	@param centre: The chunk's CENTRE in world XZ — the position of the chunk node
	               itself. Every `create_box` in this project takes a CHUNK-LOCAL
	               centre, and chunk-local is relative to that node, so this is
	               what the world-space station positions are measured against.
	@param origin: The key this polyline's turn and top hashes are keyed on — a
	               SPUR's origin chunk, or `Vector2i(edge_id, TRUNK_TURN_ROW)`.
	@param cube_cursor: How many CUBE entries the batch holds already.
	@param edge_id: -1 for a spur; the trunk's edge id otherwise. IT IS THE TIER
	                SWITCH as well as the id, and the only two things it changes
	                are marked TRUNK ONLY below.
	@param k: `scarcity_at()` at the chunk centre, for the trunk furniture's form-3
	          roll. Ignored for a spur, whose thinning happened at its rarity roll.
	@param waypoints: `terrain.waypoint_sites()`, read ONCE per chunk by the caller
	                  and handed down for `trunk_keep_out` — that table is not
	                  memoized and rebuilding it per segment would be the most
	                  expensive thing in the spawner. Ignored for a spur.
	@return: `{ "segments", "poles", "tops", "signals", "cube_cursor" }` — the
	          segment indices drawn here, the CUBE-bucket index of each pole built
	          here, the top each of those poles carries (a `SIGN_KINDS` index or
	          `POLE_TOP_SIGNAL`, one entry per pole), the CUBE-bucket index of each
	          signal head's FIRST lens, and the advanced cursor.

	ONE BODY FOR BOTH TIERS, deliberately. Everything a trunk draws is what a spur
	draws — the strip, the dash, the pole, the four signs, the head, the marker
	metas, the CUBE-bucket cursor discipline — and a second copy of this function
	is how the two would drift a centimetre apart and nobody would see it for a
	month. A spur passes neither optional argument and is therefore BYTE-IDENTICAL
	to what it was before this tier existed, which is what keeps check 1 green.
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
		# --- TRUNK ONLY: THE WATER. A trunk is not stopped by a river any more
		# (`_trunk_blocked` dropped the test), so the segment across one is not
		# painted AT GROUND LEVEL — child `.3` carries it over on a DECK instead,
		# emitted by the caller from `trunk["bridges"]` at deck height. What is left
		# here is the ground-level skip, and it is what keeps a strip out of the
		# water whether a deck was built or not: where a crossing was refused (no dry
		# abutment, or water running off the end of the route) the gap `.2` shipped
		# simply stays. Both ends and the midpoint are sampled, because a station may
		# stand IN the water.
		if edge_id >= 0 and (terrain.is_river_at(Vector3(a.x, 0.0, a.y))
				or terrain.is_river_at(Vector3(b.x, 0.0, b.y))
				or segment_blocked(terrain, a, b)):
			continue

		# --- TRUNK ONLY: THE DESTINATION'S OWN KEEP-OUT DISC, and it covers the
		# STRIP, THE DASH, THE POLE AND ITS FOOTPRINT because it is a `continue`
		# above all four. `_trunk_blocked` let the WALK through here — the anchor
		# this route ends at is inside one of these discs and it is entitled to
		# reach it — and this is where the PAINT stops instead. Owner ruling,
		# 2026-09-19: stop the trunk at the disc, never exempt the trunk from the
		# disc. `trunk_keep_out` carries the reasoning and the measurement.
		#
		# BOTH ENDS AND THE MIDPOINT, so a segment straddling the boundary is refused
		# rather than half-drawn — and the midpoint is not redundant, because the
		# LANDMARK test is a CHUNK test and not a disc: two stations in neighbouring
		# chunks can straddle a landmark's own chunk with neither of them in it.
		# Measured: without the midpoint, one box and one footprint survived in a
		# disc on seed 20260904, and check T5 named both.
		if edge_id >= 0 and (trunk_keep_out(terrain, a, waypoints)
				or trunk_keep_out(terrain, b, waypoints)
				or trunk_keep_out(terrain, (a + b) * 0.5, waypoints)):
			continue

		# RECORDED AFTER BOTH SKIPS: this list is what the chunk DREW, not what the
		# midpoint rule assigned it. A chunk whose whole share is water or keep-out
		# draws nothing and must therefore leave no MARKER either — an empty Node3D
		# standing 35 m from the tower is exactly what `tower_site_selfcheck` refuses,
		# and a marker that promises geometry there would be a lie to `.3` and `.4`
		# as well. A wet gap is found by walking the route against `is_river_at`, the
		# same question the line above asks, rather than by a meta that could go stale.
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
		# --- TRUNK ONLY: THE POLE'S OWN KEEP-OUT. It stands `BIKE_POLE_OFFSET` to the
		# SIDE of the strip, so a post can reach into a keep-out the segment itself
		# cleared — and the post is the one thing this family emits that carries
		# COLLISION and a FOOTPRINT, which is what `tower_site_selfcheck` saw. Tested
		# in WORLD space, because `at` is chunk-local by this point.
		#
		# IT IS NOT REDUNDANT, AND IT IS ALSO NOT EXERCISED BY ANY CI SEED — both
		# halves said plainly, because the second is what makes the first worth
		# writing down. The segment test above subsumes this for the two CIRCULAR
		# keep-outs: the tower's is padded by a full station stride and a waypoint
		# circle's by 3 m, and the post leans in by only 1.65 m. It does NOT subsume
		# it for the LANDMARK test, which is a SQUARE chunk boundary — a station
		# 0.5 m outside a landmark's chunk puts its post inside. Deleting this line
		# leaves `bike_path_selfcheck` T5 green today (measured, mutation M9) and a
		# post through a monument the first seed that lines one up.
		if edge_id >= 0 and trunk_keep_out(terrain, at + centre, waypoints):
			continue
		# --- TRUNK ONLY: SCARCITY, FORM 3. THE ROUTE ABOVE IS EXEMPT AND THE
		# FURNITURE IS NOT — the split this epic turns on, and the banner carries
		# the whole justification. A post-draw `continue` immediately before the
		# pole's first `create_box`, which is what form 3 means (`_scarcity_keep`'s
		# own docstring), so a trunk far out is continuous paint with nothing
		# standing on it. The index band is `TRUNK_SCARCITY_*` and it is part of the
		# world.
		#
		# IT ALMOST NEVER FIRES, BECAUSE OWNER RULING 3 MADE TRUNK ENDPOINTS
		# CORRIDOR-ONLY AND k IS 1 ACROSS THE CORRIDOR. That is not a reason to
		# delete it: it still has to be true where a route bows outside the corridor
		# mid-span (measured — it happens), and if `SCARCITY_CORRIDOR_RECT` is ever
		# re-measured against the road it is supposed to contain (bead
		# godot-test1-q184) it will fire a great deal more. AN EXEMPTION DELETED
		# BECAUSE IT LOOKED UNUSED IS THE BUG — check T3a drives both halves of this
		# split directly at a synthetic k = 0 so neither can rot unnoticed.
		if edge_id >= 0 and not terrain._scarcity_keep(chunk_pos,
				TRUNK_SCARCITY_INDEX_OFFSET + edge_id * TRUNK_SCARCITY_EDGE_STRIDE + i, k):
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
		parent_chunk: MeshInstance3D, edge_id: int = -1) -> Node3D:
	"""
	One bare Node3D per path present in this chunk — no mesh, no script, no
	physics — found BY GROUP and parented to the chunk so it is freed when the
	chunk unloads. The landmark / waypoint marker precedent: no registry to keep
	in step and nothing to leak.

	@param edge_id: -1 for a spur, the trunk's edge id otherwise.
	@return: The marker, so the caller can stamp the family's batch slice on it
	         once every path in the chunk has been drawn.
	"""
	var marker := Node3D.new()
	marker.name = BIKE_PATH_MARKER_NAME
	marker.add_to_group(BIKE_PATH_GROUP)
	# THE KEY THIS POLYLINE'S HASHES ARE KEYED ON, which for a spur is its origin
	# chunk and for a trunk is `Vector2i(edge_id, TRUNK_TURN_ROW)`. Both tiers
	# carry it under the one name because every consumer that reads it is asking
	# the same question — "which polyline is this?" — and the trunk row is out of
	# the world (see `TRUNK_TURN_ROW`), so it can never collide with a real origin.
	marker.set_meta("origin", origin)
	# ...AND WHICH TIER, so `.3` and `.4` can tell a trunk marker from a spur
	# marker without re-deriving anything from the position. -1 is a spur.
	marker.set_meta("edge", edge_id)
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

	...AND IT STANDS OFF THE POST'S FRONT FACE, which is the whole of `SIGN_STANDOFF`
	and was round 1's major finding. A plate centred on `at` — the post's own centre —
	is INSIDE the post: the post is `BIKE_POLE_WIDTH` square, so it occupies
	+/- 0.08 m along the approach axis, while a plate is `SIGN_PLATE_DEPTH` = 0.05
	thick and its pictogram only reaches 0.06. Every sign would have had a grey
	0.16 m bar straight down its middle, cutting ROUTE's and STOP's single bar into
	two stubs and swallowing CROSSING's centre bar whole — so the "three upright
	bars" would render as two and PIP COUNT, one of the three axes the four kinds are
	told apart by, would be corrupted. The plate's BACK face now touches the post's
	FRONT face, and `bike_path_selfcheck`'s clearance check measures that off the
	drawn boxes rather than trusting this paragraph.

	NO COLLISION on any of it: you may ride through a sign plate, which is the
	waypoint paint's ruling and the reason check 1's collision-shape delta is still
	exactly the pole count. No footprint either — the post beneath it owns the one
	footprint this family claims.
	"""
	var row: Dictionary = SIGN_KINDS[kind]
	var plate: Vector2 = row["plate"]
	var dir := Vector2(cos(head), sin(head))
	var side := Vector2(-sin(head), cos(head))
	# Forward of the post, by the post's half-width plus the plate's own — see above.
	var stand: Vector2 = at - dir * SIGN_STANDOFF
	terrain.create_box(
			Vector3(stand.x, SIGN_CENTRE_Y, stand.y),
			Vector3(SIGN_PLATE_DEPTH, plate.y, plate.x),
			yaw, rng, block_batch, block_body, 0.0,
			_palette(terrain, int(row["plate_color"])), false, ChunkBatch.BoxKind.CUBE)
	cube_cursor += 1

	var face: Vector2 = stand - dir * (SIGN_PLATE_DEPTH * 0.5 + SIGN_PIP_DEPTH * 0.5)
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
		# AUTOSTART rather than `start()`, and the reason is the CHECK'S chunk and not
		# the game's: `create_chunk` parents its chunk before it calls any spawner, so
		# on the production path the Timer enters the tree live and `start()` would
		# work. `bike_path_selfcheck` calls this same spawner on a bare
		# `MeshInstance3D.new()` that never enters a tree, where `Timer.start()` trips
		# its own `ERR_FAIL_COND(!is_inside_tree())` and the Timer simply never runs.
		#
		# AND CI WOULD NOT TELL YOU. That guard prints an engine `ERROR:` from C++,
		# not a `SCRIPT ERROR:`, and the gate in `build.yml` is the exit code, the
		# `SELFCHECK OK` line and a grep for `SCRIPT ERROR`. A `start()` here would
		# leave the fixture's Timer inert with every assertion still passing and the
		# shard still green — so this comment, and not the build, is what stands
		# between the next author and a dead check. Autostart is the spelling that is
		# correct in both places: it begins when (and if) the Timer enters a tree.
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
	An index one out still writes a perfectly valid instance, and nothing in the game
	would report it. That is why check 9 exists, and why it does NOT read the colour
	back: MultiMesh instance data is write-only under the headless dummy renderer, so
	a read would return black at every index and pass with any base. It compares the
	recorded index against what the shipped `_build_block_multimesh` does with the
	very batch this family wrote. Read that check before editing this function.
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
