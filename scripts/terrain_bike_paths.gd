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
## STANDS ON THE POLES" below). `.3` stands ONE bike-stand rack at every NETWORK
## ANCHOR a trunk touches (see "THE ANCHOR RACKS" below), and the rental bike
## itself is a later epic; it hangs off the rack's marker instead of re-deriving
## a position.
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
## THE SHAPE: ANCHORED POLYLINES, DRAWN PER CHUNK BY THE MIDPOINT RULE
## ----------------------------------------------------------------------------
## A trunk is a homing walk between two anchors of `bike_network.gd`'s graph
## (`_trunk_route`) — a pure function of (edge, `run_seed`) that consumes no RNG
## at all: no rarity roll (the edge exists or it does not), no start offset (the
## anchor IS the start), no bearing roll (the target IS the bearing) and no
## length roll (the target IS the length).
##
## EVERY CHUNK A ROUTE'S BOUNDING BOX TOUCHES EVALUATES THE SAME WALK and draws
## only the segments whose MIDPOINT lies in itself. That is the coin road's rule
## one family along, and it is what dissolves the seam problem: geometry may
## overhang a chunk edge, nothing is ever cut, and a chunk loaded on its own
## draws exactly what it would have drawn beside its neighbours.
##
## RETIRED, bead `godot-test1-pnvb.10` (owner ruling 2026-09-20): the spur tier —
## short origin-seeded side streets that aimed at the nearest trunk. Measured 137
## surviving stubs across 8 seeds, every one one-ended by construction, so the
## tier was deleted outright rather than parked at chance 0.0; its branches come
## back as deterministic landmark side-links in `godot-test1-pnvb.11`.
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
## BLOCKING: ABANDONED WHOLE, NEVER TRUNCATED
## ----------------------------------------------------------------------------
## A route that stops halfway is the litter this epic exists to remove, so a
## trunk is NEVER truncated: it steers around the mountain massif (`_trunk_skirt`)
## or is abandoned whole past `TRUNK_DETOUR_MAX`; it stops AT Budapest's rect
## edge, where the gate anchor sits; it crosses rivers on real field decks
## (child `godot-test1-pnvb.3`) and leaves the gap standing where no deck stands;
## and the tower discs, the waypoint circles, the landmark chunks and the coin
## road's swath stop the WALK whole mid-span (`_trunk_blocked`) while the route's
## OWN endpoints stop only the PAINT at draw time (`trunk_keep_out`), so a trunk
## reaches its anchor and draws none of the last stretch.
##
## The seven-test truncation walk (`station_blocked`) was the spur tier's and
## retired with it (`godot-test1-pnvb.10`); `segment_blocked()`'s half-step river
## sample stays — the trunk draw skip asks it of every wet segment.
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
## He is describing what the spur tier did: a path 30 to 120 m in a field
## kilometres across, on a rolled bearing, truncated by every blocking test — by
## construction starting nowhere, ending nowhere and connecting to nothing. That
## tier is retired (`godot-test1-pnvb.10`, owner ruling 2026-09-20); what follows
## is the trunk tier, now the family's only walk.
##
## A TRUNK is a
## polyline between two named anchors of `bike_network.gd`'s graph — the HQ, the
## teleport circles, the corridor landmarks and Budapest's gate. Everything below
## the walk is shared drawing machinery: the same strip, the same dash, the same
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
## length roll (the target IS the length).
##
## ### BLOCKING IS DIFFERENT, AND THAT IS THE CRUX
## The retired spur walk truncated at all seven tests. A trunk must not, or it
## stops leading anywhere, so each test is re-decided:
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
## A trunk is kilometres long and no bounded neighbourhood scan can find it. So
## this tier does what `terrain_bridges.gd`'s `approach_bridges()` already does
## with the authored city corridor: build every route ONCE per run, memoize it on
## the terrain (`_bike_trunk_cache`), and per chunk reject on each trunk's
## BOUNDING BOX. Only the survivors are walked, and then by the SHIPPED MIDPOINT
## RULE, unchanged. (The origin-chunk radius scan retired with the spur tier in
## `godot-test1-pnvb.10`.)
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
## with distance exactly as the ruling demands, and connectivity survives. There
## is no second tier any more: the spur tier's form-2 rarity roll retired with it
## (`godot-test1-pnvb.10`).
##
## **IT IS CHEAP, AND CHEAP IS NOT UNNECESSARY. DO NOT DELETE IT.** Owner Ruling 3
## made trunk endpoints corridor-only, and k is exactly 1 across the whole of
## `SCARCITY_CORRIDOR_RECT` union `BudapestPlan.rect()` — so in practice the route
## exemption almost never fires and the furniture is almost never thinned. The
## rule still has to be TRUE AT THE EDGES: a trunk bowing outside the corridor
## mid-span (measured — it happens), a retuned `SCARCITY_CORRIDOR_RECT`, a moved
## tower (`tower_site_selfcheck` drives it far out), a seed whose road wanders
## near the half-width's edge (contained since PR #457 measured the 775 m
## envelope against the 1000 m half-width — see `bike_network.gd`'s EDGE CASE
## section and bead `godot-test1-q184` — and guarded by `scarcity_selfcheck`
## check 4 rather than merely hoped).
## **AN EXEMPTION DELETED BECAUSE IT LOOKED UNUSED IS THE BUG.** Check T3a drives
## both code paths directly at a synthetic k = 0 rather than hunting for a seed
## that happens to reach one, precisely so that neither half can rot unnoticed.
##
## ----------------------------------------------------------------------------
## THE MEMO LIVES ON THE TERRAIN NODE
## ----------------------------------------------------------------------------
## `_bike_trunk_cache` (the trunk routes) is declared in `endless_terrain.gd`
## and reset in `_drop_seeded_memos()`, like every other seeded memo
## (`_landmark_sites_cache`, `_field_bridge_cache`). NOT a `static var` here:
## memo state a `_drop_seeded_memos()` cannot reach survives every re-seed and
## hands a multiplayer joiner the wrong world — `chunk_stream_selfcheck` check 6
## fails the build for it. (The spur memo `_bike_path_cache` retired with its
## tier in `godot-test1-pnvb.10`.)

# ============================================================================
# THE SEED: THIS FAMILY'S OWN SALTS AND COORDINATE PRIMES
# ============================================================================
#
# The turn hash's and the top dispatch's salts and primes are NEW, and that was
# checked against the whole tree rather than against the handful a reader
# remembers. Already spoken for elsewhere in this world engine: 73856093/19349663
# (artifacts), 83492791/15485863 (the biome offset), 40960001/26463089 (camps),
# 96174811/18266587 (the scarcity roll), 86028121/50331653 (chests),
# 32452867/49979687 (the landmark sites), 122949829/104395301 (hunters),
# 141650939/175961107 (the Danube), 179424673 and 32452843 (the crocodile roll),
# 40499/86969 and 83492791/28411639 (predators), 57859/31337 (the camp story)
# and 92821 (the road's figures) — plus 67867979/34019651, this family's own
# spur-walk pair, retired with that tier in `godot-test1-pnvb.10` (the pair is
# free now, but a new stream still owes the grep below rather than a guess).
#
# Sharing a pair would correlate two features: a chunk that hosts a camp would
# thereby be likelier (or never) to host a path, which is the one thing an
# independent stream exists to prevent. `grep -rhoE '[0-9]{5,10}' scripts/` is
# the check the next author owes, and it is how these were chosen.

## The TURN hash's own salt and primes — see `_bike_turn()` for why this family
## may not call `CoinRoad._road_turn`.
const BIKE_TURN_SALT: int = 0xB1_1E70A
const BIKE_TURN_PRIME_X: int = 55621459
const BIKE_TURN_PRIME_Y: int = 71378569
const BIKE_TURN_PRIME_I: int = 15485917

# ============================================================================
# THE PATH'S SHAPE
# ============================================================================

## Metres between stations. The strip is one box per SEGMENT, so this is also the
## strip's box length and the granularity the truncation speaks in.
const BIKE_STATION_SPACING: float = 5.0

## Per-station turn, degrees. The walk is a bounded random walk about the route's
## INITIAL bearing (see `_trunk_route`), so this is a gentle bend over the whole
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

## THE CROSSING ANGLE (child `godot-test1-pnvb.4`, Part A). A trunk may cross the
## coin road's swath mid-span where the acute angle between its own heading and
## the road station's heading EXCEEDS this. 45 degrees is the midpoint between
## "alongside" (0) and "square" (90): a shallower crossing lays a long run of
## strip under the coin line, which is the case the refusal's coin argument is
## really about, while a steeper one is across and gone in a few segments. The
## WALK goes through and the PAINT still stops — the shipped keep-out draw skip
## gaps every segment the swath touches, so no coin can land on a strip because
## no strip is there. `bike_path_selfcheck` C3 pins this number as a literal.
const BIKE_ROAD_CROSSING_MIN_DEG: float = 45.0

## How far either side of a road gap a trunk pole stands that still reads as
## flanking the crossing, in SEGMENTS. The swath is 28 m across (two
## `BIKE_ROAD_CLEARANCE`), so a square crossing gaps ~6 segments and an oblique
## one up to ~8; poles stand every `BIKE_POLE_STRIDE` = 4 segments, so 8 each
## way always reaches the first drawn pole past the paint gap on both sides.
## Those poles carry the CROSSING zebra (`BIKE_CROSSING_SIGN`), forced over the
## dispatch. `bike_path_selfcheck` C1 pins the window's effect, not the number.
const TRUNK_CROSSING_FLANK_SEGMENTS: int = 8

## Extra margin around a waypoint circle. `TerrainWaypoints.RING_RADIUS` is the
## paint; a strip that stopped exactly at the rim would still read as running
## into it, so the station clears the disc by a stride.
const BIKE_WAYPOINT_MARGIN: float = 3.0

# ============================================================================
# TIER 1 — THE TRUNK ROUTE (see the banner)
# ============================================================================

## The pseudo-origin ROW a trunk's turn hash is keyed on. `_bike_turn` and
## `_pole_top` are keyed on `(origin.x, origin.y, station)`, and a trunk has no
## origin chunk — it has an ANCHOR PAIR. Packing the pair into x with
## `TRUNK_TURN_ROW` as y reuses both hashes VERBATIM rather than writing a second
## copy of either, which is what the bead asks for and what stops two turn tables
## drifting apart.
##
## KEYED ON THE PAIR AND NOT ON THE EDGE ID, and that is load-bearing for child
## `.7`: an edge id is the pair's rank in the emitted table, so it does not exist
## until the edge set is chosen — but choosing the set means walking the
## candidates, and a walk keyed on the id cannot be walked before it is chosen.
## The pair is stable before, during and after selection, so the walk the graph
## tests is bit-for-bit the walk the spawner draws. Direction is immaterial for
## free now: the key packs the UNORDERED pair, so (i, j) and (j, i) are one walk.
##
## The row is out of the world rather than merely unlikely: chunk y = 777000 at
## `chunk_size` 50 is 38,850 km from the origin, so no real origin chunk the
## streamer can ever reach shares a key with a trunk.
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

## The pair-packing stride for the turn key above: key.x = min * STRIDE + max.
## Anchor indices sit in the dozens, so 4096 is injective with room for a world
## of anchors, and the y row keeps trunk keys off every real origin exactly as
## the note above argues.
const TRUNK_TURN_PAIR_STRIDE: int = 4096

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
## the smallest thing that can be drawn at all — and that floor is all there is:
## a trunk's length is its anchors' business and two anchors 8 m apart deserve
## the 8 m of paint that joins them. (The retired spur tier dropped stubs under
## six stations whole; that gate went with it in `godot-test1-pnvb.10`.)
const TRUNK_MIN_STATIONS: int = 2

## THE ROAD LANE (bead godot-test1-pnvb.9). When BOTH anchors of a pair sit on
## the coin road's own stations, the trunk is NOT a walk: it is the road's line,
## offset. Stations = [anchor_a] + [road_station(k).center + left(heading) *
## TRUNK_LANE_OFFSET for k in ka..kb] + [anchor_b].
##
## TRUNK_LANE_OFFSET = 18.0, measured: at 18 m, 0-3 stations of ~370 read inside
## the 14 m swath at tight bends, 0 keep-out rings and 0 tower hits. The first
## and last stations ARE the anchors, so `_strict_link`'s exact snap holds and
## two lanes sharing a circle meet to the bit; the connector into the circle is
## gapped at draw time by the swath and ring keep-outs and reads as the stand
## approach. Every station carries its road station's heading (the dash/pole yaw
## needs it); there is no `_bike_turn` — the lane inherits the road's own
## curvature (CoinRoad's recurrence), which is what a highway-side bike road
## looks like. The pitch is CoinRoad._road_spacing(), read off the terrain and
## never retyped here. Rivers go to bike_trunk_bridges() like every route (.3,
## unchanged).
##
## ONE FIXED SIDE world-wide (owner ruling 2026-09-20): TRUNK_LANE_SIDE on the
## file's own left normal, the same one the poles stand on — a pure function
## with no per-seed side choice. `bike_path_selfcheck` B1 pins the sign.
const TRUNK_LANE_OFFSET: float = 18.0
const TRUNK_LANE_SIDE: float = 1.0
## How near an anchor must stand to its road station to count as ON the road.
## A road circle IS its station's centre verbatim (`terrain_waypoints.gd`), so
## the distance is exactly 0; the door circle stands hundreds of metres off and
## the gate ~150 m past the terminal. Anything in (0, 50) answers identically
## on every CI seed; 1.0 m is the honest spelling of "~0".
const TRUNK_LANE_ANCHOR_SNAP: float = 1.0

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

## `SIGN_KINDS` index of the CROSSING zebra (child `godot-test1-pnvb.4`, Part A).
## Forced over `_pole_top`'s dispatch result at the poles flanking a road
## crossing — an override of the dispatched value, never a draw.
const BIKE_CROSSING_SIGN: int = 3

## THE DISPATCH TABLE, and the whole of the "how often" question. One fold of one
## hash indexes it, so adding a kind or retuning the mix costs NO DRAW and moves
## nothing: the stations, the strip and the poles are exactly where they were.
## Eight sign slots to one signal, because a working traffic light out in an empty
## field is a joke that stops being funny at every fourth pole.
##
## WHAT THAT MIX ACTUALLY PRODUCES, counted rather than guessed (round 1 found the
## first version of this paragraph was out by a factor of two, and it is the number
## the next author retunes `BIKE_POLE_STRIDE` or this table against). A route of
## `n` stations carries `floor((n - 1) / BIKE_POLE_STRIDE)` poles, minus the ones
## the `_footprint_taken` skip takes. At 8:1 that is about one head per nine poles.
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
## off it; the racks stand on their own markers (see below).
const BIKE_PATH_GROUP: String = "bike_path"
const BIKE_PATH_MARKER_NAME: String = "BikePathMarker"

## THE ANCHOR RACKS (bead `godot-test1-z2yv.3`, re-specified 2026-09-19 by the
## owner's network ruling): ONE rack per NETWORK ANCHOR a trunk touches, at the
## anchor's settled site and never adrift in the field. A Sheffield stand in silhouette —
## one low rail plus three thin hoop uprights — CUBE only, through `create_box`
## off this family's fixed-seed builder RNG, parented to the chunk. NO MECHANICS
## AT ALL: no Area3D, no input, no HUD, no coin cost, no `player_abilities`
## entry. The rental is a later epic; this bead lays the anchor it will read —
## one bare `Node3D` per rack in group `bike_stand`, carrying `anchor: int` (the
## index into `BikeNetwork.anchors()`) and `pos: Vector3` (world).
const BIKE_STAND_GROUP: String = "bike_stand"
const BIKE_STAND_MARKER_NAME: String = "BikeStand"

## The rack's fixed geometry, never rolled: the rail the wheels lean against and
## the three uprights the locks go round.
const RACK_RAIL_LENGTH: float = 2.2
const RACK_RAIL_HEIGHT: float = 0.08
const RACK_RAIL_DEPTH: float = 0.12
const RACK_RAIL_Y: float = 0.5
const RACK_UPRIGHT_WIDTH: float = 0.09
const RACK_UPRIGHT_HEIGHT: float = 1.0
const RACK_UPRIGHT_DEPTH: float = 0.09
const RACK_UPRIGHT_COUNT: int = 3
const RACK_COLOR: Color = Color(0.13, 0.34, 0.29)

## ONE footprint for the whole rack, not one per upright — the footprint
## vocabulary is a circle plus a top, and a rack is one obstacle.
const RACK_RADIUS: float = 1.4
const RACK_TOP: float = 1.0

## WHERE it stands, IN TWO PHASES. The anchor's own position is INSIDE a
## keep-out by construction — the HQ anchor is the tower's centre, a waypoint
## anchor its circle's, a landmark anchor its chunk's, the gate the road's swath
## — so the site is the NEAREST of these fixed offsets, in this order, that
## clears the shipped `trunk_keep_out` stencil. Nearest-first is the property
## and the table is the mechanism. Costs no draw: the anchor table is pure in
## `run_seed` and the stencil rolls nothing.
##
## Phase 1 (`rack_site`) is keep-outs ONLY and therefore pure in (anchor,
## `run_seed`): every chunk agrees on it, exactly one chunk contains it, and
## that chunk OWNS the rack — `rack_owners()` settles the map once per run.
## Phase 2 (`rack_build_site`) runs in the owner alone and takes the nearest
## candidate that is homed there and reads free against the owner's OWN
## `obstacles` (`_footprint_taken`). A taken owner builds no rack and plants no
## marker, because a marker with no rack under it is a lie the rental epic
## would build on.
##
## THE OWNER IS THE SITE'S CHUNK, NEVER THE ANCHOR'S. An 80 m ring puts the HQ
## rack two chunks east of its anchor; geometry parented — and a footprint
## appended — anywhere but where it stands unloads with the wrong chunk and
## reserves the wrong obstacles list. `bike_path_selfcheck` R1 asserts every
## marker, footprint and box centre is in the building chunk for exactly this.
const RACK_SITE_DISTANCES: Array[float] = [6.0, 10.0, 16.0, 24.0, 36.0, 52.0, 80.0]
const RACK_SITE_DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
]

## How far a rack's boxes may stand from their anchor, metres: the last ring
## above plus the rail's half-length. Stated literally because
## `bike_path_selfcheck` R3 (the world tie) asserts it.
const RACK_ANCHOR_REACH: float = 82.0

## The plan-extent the keep-out test covers around a site: the rail's half-length
## plus one box-depth of margin, on the rack's axis. The rack's yaw is fixed 0,
## so its boxes stand on the X axis through the site — `rack_site()` asks the
## shipped `trunk_keep_out` of the site AND both rail ends, because T5 sweeps box
## centres and a site that clears with a rail end inside a keep-out is the exact
## defect it exists for. (Rotate the rack and this stencil must grow with it.)
## `_footprint_taken` needs no stencil: it adds the radii, so the one test at
## the site already covers the whole stand.
const RACK_EXTENT: float = 1.25

# ============================================================================
# THE PARKED BIKES (bead `godot-test1-z2yv.9`)
# ============================================================================
#
# Owner ruling 8, 2026-09-20: "2-3 CUBE bike silhouettes at every rack (chunk
# content, inside the family's batch slice, no footprint of their own — inside
# the rack's)". A parked bike never moves, so it IS chunk content and goes
# through `create_box` like the rack itself — never a MeshInstance3D per rack.
# The ridden bike (a generated .glb) is a different object and never appears.
#
# ONE BIKE PER HOOP, hence 3: a bike stands PERPENDICULAR to the rail — its two
# wheels fore and aft across it, the frame spanning them, the saddle toward one
# end on alternating sides per slot — so two slots never overlap in X however
# close the hoops stand. The third is not clutter by construction. (That is the
# geometry argument for 3 over 2; a screenshot is not possible headless, so the
# in-game read is the owner's — this const is the whole of that change.)
#
# THE ±0.5 m WHEEL SPAN THE BEAD SKETCHES DOES NOT FIT THE FOOTPRINT: a 0.7 m
# wheel at a corner hoop (1.1 m out) reaches 1.41 m radially, past the
# persisted RACK_RADIUS 1.4 the spawners read. The span below is ±0.45 m, so
# the farthest wheel corner stands at 1.385 m — every wheel and frame corner
# stays inside the rack's own circle, which is the bound acceptance 3 asserts
# literally. Raising the span means raising RACK_RADIUS, which is persisted
# state and the owner's call, not this bead's.
#
# CONSTANT PALETTE, NO DRAW AT ALL: the slot's tint is a dispatch on the hoop
# index — dispatch costs no draw (CLAUDE.md) — never a roll. The boxes are
# placed from the rack's site and the hoop offsets, which are already known,
# AFTER the rack's last draw so every existing box lands where it did.
# `create_box` still draws its discarded ramp/roughness values from the
# family's private fixed-seed builder rng — that function's contract, and
# unobservable (every family colour is an override) — but no tint, no offset
# and no choice here costs a draw in any stream: R1's rack counts and
# chunk_stream_selfcheck print the same numbers before and after.
#
# VISUAL-ONLY (`collide = false`): the rail and the hoops already block, and
# paint appends no shape — check 1's shape equation holds with bikes standing
# in the chunk, and R1/R3 keep counting rail + upright shapes only.
const PARKED_BIKES_PER_RACK: int = 3
## Two 0.7 m wheel plates, thin in X: the discs stand perpendicular to the rail.
const PARKED_BIKE_WHEEL_DIMS := Vector3(0.06, 0.7, 0.7)
const PARKED_BIKE_WHEEL_Y: float = 0.35
## Fore/aft half-span of the wheel pair — ±0.45 m, see the footprint note above.
const PARKED_BIKE_WHEEL_HALF_SPAN: float = 0.45
## The frame bar, 1.0 m long, yawed PI/2 at build so it spans the wheel pair.
const PARKED_BIKE_FRAME_DIMS := Vector3(1.0, 0.08, 0.06)
const PARKED_BIKE_FRAME_Y: float = 0.55
## Saddle/bar lump, toward one wheel — alternating ends per slot.
const PARKED_BIKE_SADDLE_DIMS := Vector3(0.2, 0.06, 0.1)
const PARKED_BIKE_SADDLE_Y: float = 0.85
const PARKED_BIKE_SADDLE_END: float = 0.3
## One silhouette tint per slot, all three from this family's own consts.
const PARKED_BIKE_COLORS: Array[Color] = [BIKE_STRIP_COLOR, BIKE_DASH_COLOR, BIKE_POLE_COLOR]

# ============================================================================
# THE HEADING RECURRENCE — the shipped walk's turn math, kept for the trunks
# ============================================================================

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


static func segment_blocked(terrain: Node3D, a: Vector2, b: Vector2) -> bool:
	"""
	Does the SEGMENT between two legal stations cross water?

	@return: true when the path must stop at `a` rather than reach `b`.

	THE HALF-STEP RIVER SAMPLE, and it exists because the station pitch is coarse
	against the one feature in the field that is thin. `RIVER_HALF_WIDTH`'s own
	measurement note (`endless_terrain.gd`) puts a band at roughly 8-9 m across at
	the mean gradient — but the gradient varies, and wherever it is steep the band
	drops under `BIKE_STATION_SPACING` and a 5 m step can put one station on each
	dry side of it. The strip between them would then be laid across the water —
	which is why this sample exists: no station test stands guard over the ground
	between two stations.

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


static func trunks(terrain: Node3D) -> Array[Dictionary]:
	"""
	EVERY TRUNK IN THE WORLD, walked once per run and memoized on the terrain.

	@param terrain: The `EndlessTerrain`.
	@return: Rows of `{ id: int (the edge id), stations: Array[Dictionary] in the
	         walk order `_draw_path_share` expects, box: Rect2 (the world XZ box
	         every piece of this trunk's STONE stands inside — the route's own,
	         padded by one segment length, MERGED with each deck's, because a ramp
	         foot reaches a ramp run past the last station it was built from),
	         from: Vector2, to: Vector2, bridges: Array (the field-bridge rows this
	         route's river crossings need, child `.3`) }`, for the edges that
	         produced a route at all. The memo itself, not a copy — it is asked
	         once per chunk.

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
	measures 0.065-0.072 ms per corridor chunk and 0.376 ms on one
	carrying a deck, where it mitres two rail lines and walks the slabs.
Child `.4` re-measured 0.67 ms on a crossing chunk (plus the flank window per trunk
pole), seed 20260904; the memo cold call is ~56 ms there at 33 routes, up from a
dozen, because steep crossings now walk to full length instead of dying at the swath.
Still once per run and sub-ms per chunk. (The spur tier's 0.17 ms A/B-chunk line
retired with it in `godot-test1-pnvb.10`.)
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
	# Read ONCE for every edge: the table is not memoized
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
		#
		# NOT EXERCISED BY ANY CI SEED (measured, mutation M12: deleting the merge
		# leaves the whole suite green), and said plainly for the reason the marker
		# guard in the spawner says it. A deck mid-route sits well inside the route's
		# own padded box; the merge bites only where a crossing is near an extreme
		# station, or where a foot push carries a ramp sideways past one. It costs one
		# `Rect2.merge` per deck, and `bike_path_selfcheck` B1b is the assertion that
		# fires the day a seed lines one up.
		var box: Rect2 = _trunk_box(route)
		for row_v: Variant in decks:
			box = box.merge((row_v as Dictionary)["box"] as Rect2)
		out.append({
			"id": int(edge["id"]),
			"a": int(edge["a"]),
			"b": int(edge["b"]),
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
		# ...AND THE POINTS THE BOXES STAND ON, not the points the polyline bends at.
		# A slab is centred on its segment's midpoint and a RAMP is one box up to
		# 34 m long, so its centre sits as much as 17 m from the nearest vertex of
		# `poly` — a screen over the vertices alone would pass a ramp lying squarely
		# inside a keep-out. `row["screen"]` is built from the shipped slab table, so
		# this owns no second idea of where the stone is.
		#
		# NOT EXERCISED BY ANY CI SEED EITHER (measured, mutation M13: screening the
		# vertices alone leaves the suite green) — no seed has yet grown a long pushed
		# ramp whose midpoint lands in a keep-out its own ends miss. T5 is what goes
		# red the day one does, and it would name a box rather than a rule, so this is
		# where the rule is written down.
		var pad: float = row["rail"]
		var clear: bool = true
		for pt: Vector2 in (row["screen"] as PackedVector2Array):
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


static func _trunk_turn_key(a: int, b: int) -> Vector2i:
	"""
	The turn-and-top hash key for the trunk between anchors a and b: the
	unordered pair packed into x on `TRUNK_TURN_ROW` (see its note and
	`TRUNK_TURN_PAIR_STRIDE`). Stable before the edge set is chosen, while it
	is chosen and after — which is what lets the graph test-walk a candidate
	pair and get bit-for-bit the walk the spawner will draw for it.
	"""
	return Vector2i(mini(a, b) * TRUNK_TURN_PAIR_STRIDE + maxi(a, b), TRUNK_TURN_ROW)


static func trunk_pair_walk(terrain: Node3D, anchors: Array[Dictionary], a: int, b: int,
		reason: Array[String]) -> Array[Dictionary]:
	"""
	The route the trunk between anchors a and b WOULD draw, walked to test it.

	@param anchors: `terrain.bike_anchors()`, the table the candidate pair indexes.
	@param reason: OUT, the walk's refusal ("" when the pair draws): one of
	               "mountain", "city", "road", "site", "lost" or "short" — the
	               walk's own vocabulary, and deliberately NOT the lake: that
	               verdict lives in the bridge scan over the finished edge set,
	               and asking it here would recurse through the memo this answer
	               feeds (`trunk_abandoned`'s note). The graph records these at
	               selection time; the draw tier reports the lake at draw time.
	@return: The stations, or [] when the walk is abandoned whole.

	THE QUESTION THE GRAPH ASKS (bead godot-test1-pnvb.7): `BikeNetwork.edges()`
	reaches this through the terrain's forwarder, never by name, and walks every
	candidate pair before the edge set is chosen — so the repair joins components
	with links that actually draw instead of ones the walk abandons. COSTS NO
	DRAW: the walk is `_bike_turn` hashes on the pair key, never a roll.
	"""
	return _trunk_route(terrain, anchors, {"a": a, "b": b}, reason)


static func _trunk_gate_lane(terrain: Node3D, anchors: Array[Dictionary], ai: int, bi: int,
		gate_end: int) -> Array[Dictionary]:
	"""
	THE GATE'S LANE (bead godot-test1-pnvb.9, round 2): one end is a road
	circle on its station (`circle_end`), the other the gate (`gate_end`).

	@param ai / @param bi: The edge's two anchor indices, in edge order.
	@param gate_end: Which of the two is the gate.
	@return: `[circle] + [offset stations ka..k_term] + [gate]`, ordered from
	           `ai` to `bi` — or [] when the circle is not on its station or
	           stands past the terminal (impossible: every road circle stands
	           west of it; the [] is the honest fallback).

	The offset stations are the same arithmetic as `_trunk_lane`'s, same side,
	same pitch, same headings. The last one stands at the authored end of the
	road; the approach from it to the gate is ONE straight segment carrying
	the terminal's road heading for its yaw, and the first station IS the
	circle and the last IS the gate, so `_strict_link` snaps exactly both
	ways. No `_bike_turn`, no RNG, no walk test of any kind: a lane cannot be
	refused, which is the point — the homing walk died "road" on the
	corridor's last stretch on every seed whose road runs at the gate.
	"""
	var circle_end: int = bi if gate_end == ai else ai
	var pc: Vector2 = anchors[circle_end]["pos"]
	var pg: Vector2 = anchors[gate_end]["pos"]
	var nc: Dictionary = road_station_near(terrain, pc)
	if nc.is_empty():
		return []
	var cc: Vector2 = (nc["station"] as Dictionary)["center"]
	if pc.distance_to(cc) > TRUNK_LANE_ANCHOR_SNAP:
		return []
	var ka: int = int(nc["k"])
	var k_term: int = terrain._road_terminal_k()
	if ka > k_term:
		return []
	# The span, warmed like every other road consumer warms it — and never
	# past the terminal: the top end IS the terminal station.
	var pad: float = BIKE_ROAD_CLEARANCE + terrain._road_spacing() * 2.0
	terrain._road_extend_to_x(pc.x - pad, (terrain._road_station(k_term)["center"] as Vector2).x)
	var offs: Array[Dictionary] = []
	var k: int = ka
	while true:
		var st: Dictionary = terrain._road_station(k)
		var c: Vector2 = st["center"]
		var h: float = float(st["heading"])
		offs.append({
				"pos": c + Vector2(-sin(h), cos(h)) * (TRUNK_LANE_SIDE * TRUNK_LANE_OFFSET),
				"heading": h })
		if k == k_term:
			break
		k += 1
	var term_h: float = float(offs[offs.size() - 1]["heading"])
	var stations: Array[Dictionary] = [{
			"pos": pc, "heading": float((nc["station"] as Dictionary)["heading"]) }]
	stations.append_array(offs)
	stations.append({"pos": pg, "heading": term_h})
	if gate_end == ai:
		stations.reverse()
	return stations


static func _trunk_lane(terrain: Node3D, anchors: Array[Dictionary], ai: int, bi: int) -> Array[Dictionary]:
	"""
	THE ROAD'S OWN LINE, OFFSET (bead godot-test1-pnvb.9) — or [] when this pair
	is not a road pair, and `_trunk_route` walks instead.

	@param ai / @param bi: The edge's two anchor indices into `anchors`.
	@return: `[anchor_a] + [road_station(k).center + left * offset for k in
	           ka..kb] + [anchor_b]`, every station carrying its road station's
	           heading — or, for a circle-gate pair, the circle's anchor plus
	           the offset stations to the last one plus the gate anchor — or []
	           when the pair is neither.

	A ROAD PAIR IS TWO KIND_WAYPOINT ROWS (the `1` below is
	`BikeNetwork.KIND_WAYPOINT` by value: this family reaches that one through
	the terrain, never by name — CLAUDE.md Conventions) that `road_station_near`
	sits on a station at distance ~0. Every field circle but the door circle
	does (`terrain_waypoints.gd` returns the station centre verbatim); the door
	circle and the gate stand far off, so the geometric test alone would do —
	the kind test is the belt to its braces.

	A CIRCLE-GATE PAIR (round 2: one KIND_WAYPOINT row on its station, one
	KIND_GATE row — the `3` below is `BikeNetwork.KIND_GATE` by value) is ALSO
	a lane: the road's offset stations from the circle's station to the LAST
	station (`_road_terminal_k`, the authored end of the road), then ONE
	straight approach segment from that last lane station to the gate anchor.
	The approach's midpoint sits inside the swath, so the draw tier gaps the
	whole segment and the paint ends where the road does — but the ROUTE
	reaches the gate, which is what the chain is. The gate anchor is never
	handed to `road_station_near` and no span is ever extended past
	`ROAD_TERMINAL_X`: past the terminal there are no stations, only the
	approach.

	COSTS NO DRAW: arithmetic over the road cache. The span is clamped at
	`ROAD_TERMINAL_X` (the cache stays honest past it, but no lane ever needs
	it — every road circle stands west of the terminal).
	"""
	var kind_a: int = int(anchors[ai]["kind"])
	var kind_b: int = int(anchors[bi]["kind"])
	var gate_end: int = -1
	if kind_a == 1 and kind_b == 1:
		pass
	elif kind_a == 1 and kind_b == 3:
		gate_end = bi
	elif kind_a == 3 and kind_b == 1:
		gate_end = ai
	else:
		return []
	if gate_end >= 0:
		return _trunk_gate_lane(terrain, anchors, ai, bi, gate_end)
	var pa: Vector2 = anchors[ai]["pos"]
	var pb: Vector2 = anchors[bi]["pos"]
	var na: Dictionary = road_station_near(terrain, pa)
	var nb: Dictionary = road_station_near(terrain, pb)
	if na.is_empty() or nb.is_empty():
		return []
	var ca: Vector2 = (na["station"] as Dictionary)["center"]
	var cb: Vector2 = (nb["station"] as Dictionary)["center"]
	if pa.distance_to(ca) > TRUNK_LANE_ANCHOR_SNAP or pb.distance_to(cb) > TRUNK_LANE_ANCHOR_SNAP:
		return []
	# The span, warmed contiguously like every other road consumer warms it.
	var pad: float = BIKE_ROAD_CLEARANCE + terrain._road_spacing() * 2.0
	terrain._road_extend_to_x(minf(pa.x, pb.x) - pad,
			minf(maxf(pa.x, pb.x) + pad, terrain.ROAD_TERMINAL_X))
	var stations: Array[Dictionary] = [{
			"pos": pa, "heading": float((na["station"] as Dictionary)["heading"]) }]
	var ka: int = int(na["k"])
	var kb: int = int(nb["k"])
	var step: int = 1 if ka <= kb else -1
	var k: int = ka
	while true:
		var st: Dictionary = terrain._road_station(k)
		var c: Vector2 = st["center"]
		var h: float = float(st["heading"])
		stations.append({
				"pos": c + Vector2(-sin(h), cos(h)) * (TRUNK_LANE_SIDE * TRUNK_LANE_OFFSET),
				"heading": h })
		if k == kb:
			break
		k += step
	stations.append({
			"pos": pb, "heading": float((nb["station"] as Dictionary)["heading"]) })
	return stations


static func _trunk_route(terrain: Node3D, anchors: Array[Dictionary], edge: Dictionary,
		reason: Array[String] = []) -> Array[Dictionary]:
	"""
	THE HOMING WALK from one anchor to the other. A pure function of (edge id,
	`run_seed`), and it consumes no RNG at all.

	@param anchors: `terrain.bike_anchors()`, passed in because the caller walks
	                every edge against the same table.
	@param reason: Optional single-element out-parameter for `trunk_abandoned`.
	@return: The stations, `{ "pos": Vector2, "heading": float }`, or `[]`.

	THE RECURRENCE IS `_next_heading()`: this walk passes THE BEARING TO ITS TARGET,
	RECOMPUTED HERE AT EVERY STATION, as `heading0`. The restore term therefore
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
	site, so `_next_heading` stays a shared recurrence rather than growing a
	trunk-shaped special case.

	ARRIVAL IS AN ASSIGNMENT. Inside one `BIKE_STATION_SPACING` of the target the
	last station is written to the anchor's own `Vector2`, so two trunks sharing
	an anchor hold EXACTLY the same terminal position and the owner's intersection
	is exact rather than within a tolerance. The first station is the other anchor
	by the same assignment, which is why an anchor shared as one edge's `a` and
	another's `b` still meets to the bit.
	"""
	if not reason.is_empty():
		reason[0] = ""
	# THE LANE FIRST: a road pair never walks.
	var lane: Array[Dictionary] = _trunk_lane(terrain, anchors, int(edge["a"]), int(edge["b"]))
	if not lane.is_empty():
		return lane
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

	var key := _trunk_turn_key(int(edge["a"]), int(edge["b"]))
	# The waypoint table, read ONCE for the whole walk — it is pure in `run_seed`
	# and rebuilding it per station is the walk's most expensive answer.
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
		# ...EXCEPT THE CANYON (bead godot-test1-pnvb.9): MOUNTAIN ground within
		# the road's clearance is the pass, not a wall — the walk goes through
		# and the paint stays off it (the swath member gaps the road bed, the
		# pass gap below gaps the rest).
		if terrain.biome_at(step.x, step.y) == terrain.Biome.MOUNTAIN \
				and not _in_canyon(terrain, step):
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
		if _trunk_blocked(terrain, step, waypoints, from, to, want, reason):
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
		from: Vector2, to: Vector2, heading: float, reason: Array[String] = []) -> bool:
	"""
	May a TRUNK station stand at this world XZ? The seven station tests the retired
	spur walk used, re-decided for a route that has to lead somewhere.

	@param from / @param to: This edge's own two anchors. Inside
	                         `TRUNK_APPROACH_RADIUS` of either, EVERY test below is
	                         skipped, the coin road included — the walk is entitled
	                         to reach its own anchor. The PAINT is not: the same
	                         tests run again at draw time through `trunk_keep_out`.
	@param heading: The heading the walk used to reach `p`. It is only read where
	                         the swath is the SOLE refusal (child `godot-test1-pnvb.4`,
	                         Part A): a near-perpendicular crossing walks through,
	                         a shallow one is abandoned whole.
	@return: true when the trunk must be abandoned whole.

	FOUR OF THE SEVEN ARE HERE. The mountain is the caller's (it skirts before it
	gives up), Budapest's rect is the caller's (it truncates there rather than
	abandoning), and the rivers do not block a trunk at all any more — `.3` bridges
	them and until then the segment is simply not drawn.

	PURE IN (POSITION, SEED): the
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
	# Split for the REPORT and not for the rule: the discs refuse outright, while
	# the road refusal is conditional on the crossing angle (child
	# `godot-test1-pnvb.4`, Part A) — so the road is tested on its own, after the
	# discs, and last because it is the one test that may grow the station cache.
	if trunk_keep_out(terrain, p, waypoints, false):
		if not reason.is_empty():
			reason[0] = "site"
		return true
	if _road_swath(terrain, p):
		if _trunk_road_crossing_ok(terrain, p, heading):
			return false
		if not reason.is_empty():
			reason[0] = "road"
		return true
	return false


static func _road_swath(terrain: Node3D, p: Vector2) -> bool:
	"""
	Is this world XZ inside the coin road's clearance swath?

	THE ONE SPELLING OF IT IN THIS TIER, and `trunk_keep_out` calls it too rather
	than writing the comparison out a second time — `BIKE_ROAD_CLEARANCE`'s own note
	says a second opinion about that number is what puts a bike path under the
	road's coins, and two literal copies fifty lines apart is exactly how a second
	opinion starts.

	`_trunk_blocked` also uses it to decide WHICH BUCKET a refusal is reported in —
	"road" or "site" — which is a report and not a rule.
	"""
	return terrain._road_lateral_distance(p.x, p.y, BIKE_ROAD_CLEARANCE) < BIKE_ROAD_CLEARANCE

static func _in_canyon(terrain: Node3D, p: Vector2) -> bool:
	"""
	Is this world XZ inside the coin road's canyon — MOUNTAIN-road-clearance of
	the centreline (bead godot-test1-pnvb.9)? The massif builder keeps massif
	CENTRES clear of the road, but `biome_at()` is noise and still says MOUNTAIN
	inside the pass, where no box stands — so the canyon is passable ground to
	the walk and a paint gap to the draw tier (the pass gap below). Same
	`_road_lateral_distance` idiom as `_road_swath`, with the massif's own
	clearance instead of the swath's.
	"""
	var c: float = terrain.MOUNTAIN_ROAD_CLEARANCE
	return terrain._road_lateral_distance(p.x, p.y, c) < c


static func road_station_near(terrain: Node3D, p: Vector2) -> Dictionary:
	"""
	The road station judging world XZ `p` (child `godot-test1-pnvb.4`, round 2).
	
	THE ONE SEAM for station picking, shared by the walk (`_trunk_road_crossing_ok`)
	and `bike_path_selfcheck` C3: an earlier revision picked the station twice with
	a `best_k = -1` sentinel in both places, and station indices go NEGATIVE west
	of the origin -- so every western crossing was refused and the check was blind
	to it through the same sentinel. There is no int sentinel left to share:
	this returns `{k, station}` for the nearest of the two stations straddling
	`p.x` (cache extended, binary-searched, clamped -- the shipped idiom), or `{}`
	when no station stands near. Pure, costs no draw.
	"""
	var pad: float = BIKE_ROAD_CLEARANCE + terrain._road_spacing() * 2.0
	terrain._road_extend_to_x(p.x - pad, p.x + pad)
	var k0: int = terrain._road_first_k_at_or_after_x(p.x)
	var k_last: int = mini(terrain.road_k_max, terrain._road_terminal_k())
	var best := {}
	var best_d: float = INF
	for k: int in [k0 - 1, k0]:
		if k < terrain.road_k_min or k > k_last:
			continue
		var st: Dictionary = terrain._road_station(k)
		var d: float = Vector2(p.x, p.y).distance_to(st["center"])
		if d < best_d:
			best_d = d
			best = {"k": k, "station": st}
	return best


static func _trunk_road_crossing_ok(terrain: Node3D, p: Vector2, heading: float) -> bool:
	"""
	May this trunk step cross the coin road HERE, at this heading?
	
	@param p: The candidate step, WORLD space (x, z) — already known to be inside
	         the swath. @param heading: The heading the walk used to reach it.
	@return: true when the crossing is near-perpendicular (child `godot-test1-pnvb.4`,
	         Part A) and the walk may continue; false keeps the shipped refusal.
	
	THE ACUTE ANGLE, not the signed difference: running ALONGSIDE the road in
	either direction reads ~0 and stays refused, crossing it square reads ~PI/2.
	The road heading comes through `road_station_near` (the one seam C3 shares),
	`terrain._road_extend_to_x` — the same binary-search idiom every other road
	consumer uses (`terrain._road_first_k_at_or_after_x`). The nearest of the two
	stations straddling `p.x` is the heading read, so a point between two stations
	is judged by the closer centreline — and a refusal is the default when no
	station is near, which cannot happen behind `_road_swath` but must still be
	the safe answer.
	
	PURE IN (POSITION, SEED) like everything else in the walk, and it costs no
	draw: two hashes' worth of cache lookups and one comparison.
	"""
	var near: Dictionary = road_station_near(terrain, p)
	if near.is_empty():
		return false
	var road_heading: float = float((near["station"] as Dictionary)["heading"])
	var diff: float = absf(wrapf(heading - road_heading, -PI, PI))
	return minf(diff, PI - diff) > deg_to_rad(BIKE_ROAD_CROSSING_MIN_DEG)



static func trunk_keep_out(terrain: Node3D, p: Vector2,
		waypoints: Array[Dictionary], include_road: bool = true) -> bool:
	"""
	Is this world XZ somewhere this family must not draw — the tower's disc, a
	teleport circle, a landmark's chunk, or the coin road's swath?

	@param waypoints: `terrain.waypoint_sites()`, read once by the caller.
	@return: true when nothing this family builds may stand here.

	THREE CALLERS, AND THE FIRST TWO ARE THE TWO HALVES OF ONE RULING (owner,
	2026-09-19):

	  * `_trunk_blocked` asks it of a station the route is NOT heading for, and
	    abandons the trunk whole — an obstacle.
	  * `_draw_path_share` asks it of a segment the route IS heading for, and
	    DRAWS NOTHING THERE — a destination the route stops at the edge of.
	  * `_drawable_decks` (child `.3`) asks it of a river deck's own points, and
	    drops the deck — the same ruling as the second, applied to the one piece of
	    this family's stone that is not laid along the route's own line.

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
	# THAT SENTENCE NOW COVERS THE WHOLE FAMILY. It once did not: the draw-time
	# guards in `_draw_path_share` were gated on `edge_id >= 0` while the spur tier
	# still walked, and a spur pole planted `BIKE_POLE_OFFSET` = 1.65 m to the side
	# of a cleared station could land in the swath — a pre-existing spur-tier gap
	# nobody widened and nobody closed, because closing it would have moved
	# footprints and the crocodiles behind them. The spur tier retired in
	# `godot-test1-pnvb.10`; the guards below are unconditional now, and T5 asserts
	# every box and footprint in the chunk.
	#
	# `include_road` is for `_trunk_blocked` ONLY (child `godot-test1-pnvb.4`): the
	# walk must tell a destination-disc refusal from a road refusal, because the road
	# one is now conditional on the crossing angle while the discs refuse outright.
	# Every other caller — the draw-time skip, `_drawable_decks`, T5 — passes the
	# default and sees all four members exactly as before.
	return _road_swath(terrain, p) if include_road else false


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
			if terrain.biome_at(q.x, q.y) != terrain.Biome.MOUNTAIN or _in_canyon(terrain, q):
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
	Draw this chunk's share of every trunk route that reaches it.

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
	# --- THE ANCHOR RACKS (bead `godot-test1-z2yv.3`): one per NETWORK ANCHOR a
	# trunk touches, at the anchor's settled site, never adrift in the field.
	#
	# OWNED BY THE SITE'S CHUNK, NEVER THE ANCHOR'S. The anchor's own position
	# is inside a keep-out by construction and an 80 m ring puts the HQ rack two
	# chunks east of it, so building from the anchor's chunk would parent the
	# geometry — and append the footprint — to a chunk the rack does not stand
	# in. `rack_owners()` settles the owner map once per run (pure, hence one
	# owner by construction — two trunks meeting at one waypoint share that
	# anchor's single rack) and only the owner builds, settling the final site
	# against its OWN obstacles.
	#
	# FIRST, BEFORE THE TRUNKS' BOXES. Check 7c reads a pole's top as the
	# contiguous run of boxes after its post, so racks emitted last would let a
	# rack box walk into the last pole's top run and fail a correct world; with
	# the racks first every recorded CUBE index is still taken after them, and
	# the family's batch entries stay the ONE contiguous range check 1 slices.
	var owners: Dictionary = rack_owners(terrain)
	var anchors_here: Array[Dictionary] = terrain.bike_anchors()
	var stands_once: Array = terrain.waypoint_sites()
	for anchor_index: int in touched_anchors(terrain):
		if not owners.has(anchor_index):
			continue  # no keep-out-clearing candidate anywhere: honest skip
		if owners[anchor_index] != chunk_pos:
			continue
		var apos: Vector2 = anchors_here[anchor_index]["pos"]
		var site: Vector2 = rack_build_site(terrain, apos, chunk_pos,
				stands_once, obstacles, centre)
		if site == Vector2.INF:
			continue
		cube_cursor = _build_rack(terrain, anchor_index, site, centre, rng,
				obstacles, block_batch, block_body, cube_cursor, parent_chunk,
				markers)
	# --- THE TRUNKS, found by BOUNDING BOX and not by a radius scan.
	# A trunk is kilometres long, so no bounded neighbourhood sweep of origins can
	# see one; `approach_bridges()`'s shape is what finds them instead (see the
	# banner). Tens of `Rect2.intersects` per chunk against a table built once
	# per run. (The origin-chunk scan for the retired spur tier stood here until
	# `godot-test1-pnvb.10`.)
	#
	# INSIDE THE FAMILY'S ONE SLICE. The batch range this spawner stamps on every
	# marker below covers every trunk crossing the chunk, so the kill switch still
	# cuts ONE contiguous run out of the batch however many routes cross it —
	# which is exactly what check 1 needs.
	var half: float = terrain.chunk_size * 0.5
	var chunk_rect := Rect2(centre - Vector2(half, half),
			Vector2(terrain.chunk_size, terrain.chunk_size))
	# k AT THE CHUNK'S CENTRE, read ONCE, for the FURNITURE only — the route itself
	# is exempt and is drawn whatever this says. `_scarcity_keep`'s own docstring
	# asks for the chunk centre rather than the object's position.
	var k: float = terrain.scarcity_at(chunk_centre)
	# The teleport circles, read ONCE for every trunk in this chunk — `waypoint_sites()`
	# allocates eleven rows and runs six binary searches per call and is pure in
	# `run_seed`, so it is loop-invariant over the whole chunk build.
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	var shares: Array[Dictionary] = []
	for trunk: Dictionary in trunks(terrain):
		if not (trunk["box"] as Rect2).intersects(chunk_rect):
			continue
		var edge_id: int = int(trunk["id"])
		var key := _trunk_turn_key(int(trunk["a"]), int(trunk["b"]))
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
		cube_cursor: int, edge_id: int, k: float = 1.0,
		waypoints: Array[Dictionary] = []) -> Dictionary:
	"""
	One polyline's segments, insofar as they belong to `chunk_pos`.

	@param centre: The chunk's CENTRE in world XZ — the position of the chunk node
	               itself. Every `create_box` in this project takes a CHUNK-LOCAL
	               centre, and chunk-local is relative to that node, so this is
	               what the world-space station positions are measured against.
	@param origin: The key this polyline's turn and top hashes are keyed on — the
	               trunk's pair-packed key (`_trunk_turn_key`).
	@param cube_cursor: How many CUBE entries the batch holds already.
	@param edge_id: The trunk's edge id: which route this share belongs to, and
	                the scarcity band the furniture's form-3 roll reads.
	@param k: `scarcity_at()` at the chunk centre, for the furniture's form-3 roll.
	@param waypoints: `terrain.waypoint_sites()`, read ONCE per chunk by the caller
	                  and handed down for `trunk_keep_out` — that table is not
	                  memoized and rebuilding it per segment would be the most
	                  expensive thing in the spawner.
	@return: `{ "segments", "poles", "tops", "signals", "cube_cursor" }` — the
	          segment indices drawn here, the CUBE-bucket index of each pole built
	          here, the top each of those poles carries (a `SIGN_KINDS` index or
	          `POLE_TOP_SIGNAL`, one entry per pole), the CUBE-bucket index of each
	          signal head's FIRST lens, and the advanced cursor.

	ONE BODY FOR EVERY ROUTE, deliberately: the strip, the dash, the pole, the four
	signs, the head, the marker metas, the CUBE-bucket cursor discipline — and a
	second copy of this function is how two routes would drift a centimetre apart
	and nobody would see it for a month.
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
		# --- THE WATER. A trunk is not stopped by a river any more
		# (`_trunk_blocked` dropped the test), so the segment across one is not
		# painted AT GROUND LEVEL — child `.3` carries it over on a DECK instead,
		# emitted by the caller from `trunk["bridges"]` at deck height. What is left
		# here is the ground-level skip, and it is what keeps a strip out of the
		# water whether a deck was built or not: where a crossing was refused (no dry
		# abutment, or water running off the end of the route) the gap `.2` shipped
		# simply stays. Both ends and the midpoint are sampled, because a station may
		# stand IN the water.
		if (terrain.is_river_at(Vector3(a.x, 0.0, a.y))
				or terrain.is_river_at(Vector3(b.x, 0.0, b.y))
				or segment_blocked(terrain, a, b)):
			continue

		# --- THE DESTINATION'S OWN KEEP-OUT DISC, and it covers the
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
		if (trunk_keep_out(terrain, a, waypoints)
				or trunk_keep_out(terrain, b, waypoints)
				or trunk_keep_out(terrain, (a + b) * 0.5, waypoints)):
			continue

		# --- THE PASS GAP (bead godot-test1-pnvb.9). A trunk through the canyon
		# runs over ground that reads MOUNTAIN with no box on it, so a strip
		# there would be paint on a massif face the route only borrows. A
		# draw-time skip beside the river/keep-out skips: the station list is
		# untouched and no RNG is involved — the route continues through the
		# pass and the strip resumes past it.
		if terrain.biome_at(mid.x, mid.y) == terrain.Biome.MOUNTAIN:
			continue

		# RECORDED AFTER BOTH SKIPS: this list is what the chunk DREW, not what the
		# midpoint rule assigned it. A chunk whose whole share is water or keep-out
		# draws nothing and must therefore leave no MARKER either — an empty Node3D
		# standing 35 m from the tower is exactly what `tower_site_selfcheck` refuses,
		# and a marker that promises geometry there would be a lie to `.3` and `.4`
		# as well. A wet gap is found by walking the route against `is_river_at`, the
		# same question the line above asks, rather than by a meta that could go stale.
		segments.append(i)

		# A yaw turns the box's local +X toward -Z, while a direction in (x, z)
		# is (cos h, sin h) — so the yaw that points a box along the segment is
		# the NEGATED segment angle (the studs in `terrain_waypoints.gd` are the
		# same arithmetic). Deliberately NOT the station heading: a walk steps
		# along its heading so the two agree, but a lane carries its ROAD
		# station's heading and on a bend the chord between two offset stations
		# runs off it — yawing paint by the heading would lay the strip across
		# its own segment (bead godot-test1-pnvb.9, caught by T1). The dash rides
		# the same yaw — it is the strip's centre line. The poles' side and the
		# sign facing still read the station heading.
		var head: float = stations[i + 1]["heading"]
		var yaw: float = -(b - a).angle()
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
		# --- THE POLE'S OWN KEEP-OUT. It stands `BIKE_POLE_OFFSET` to the
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
		if trunk_keep_out(terrain, at + centre, waypoints):
			continue
		# --- SCARCITY, FORM 3. THE ROUTE ABOVE IS EXEMPT AND THE
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
		if not terrain._scarcity_keep(chunk_pos,
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
		# --- THE CROSSING ZEBRA (child `godot-test1-pnvb.4`, Part A). A
		# pole flanking a road gap carries the CROSSING sign whatever the dispatch
		# said — an override of the dispatched value, never a draw.
		if _pole_flanks_road_crossing(terrain, stations, i):
			top = BIKE_CROSSING_SIGN
		tops.append(top)
		if top == POLE_TOP_SIGNAL:
			# THE OFF-BY-ONE LIVES ON THIS LINE. `_build_signal_head` emits the head
			# box FIRST and the three lenses after it, so lamp 0 stands one past the
			# cursor as it is now. `bike_path_selfcheck` check 9 asks the SHIPPED
			# `_build_block_multimesh` where this lens really lands and compares.
			signals.append(cube_cursor + 1)
			# The segment's own angle, not the station heading: the builders
			# face their plates along it, and a lane carries its road
			# station's heading, which runs off the chord on a bend (bead
			# godot-test1-pnvb.9 — check 7 caught the plates standing proud).
			# For a walk the two agree, so nothing there moves.
			var facing: float = (b - a).angle()
			cube_cursor = _build_signal_head(terrain, at, facing, yaw, rng,
					block_batch, block_body, cube_cursor)
		else:
			var facing: float = (b - a).angle()
			cube_cursor = _build_sign(terrain, top, at, facing, yaw, rng,
					block_batch, block_body, cube_cursor)

	return {
		"segments": segments, "poles": poles, "tops": tops, "signals": signals,
		"cube_cursor": cube_cursor,
	}


static func _make_marker(terrain: Node3D, origin: Vector2i, built: Dictionary,
		parent_chunk: MeshInstance3D, edge_id: int) -> Node3D:
	"""
	One bare Node3D per path present in this chunk — no mesh, no script, no
	physics — found BY GROUP and parented to the chunk so it is freed when the
	chunk unloads. The landmark / waypoint marker precedent: no registry to keep
	in step and nothing to leak.

	@param edge_id: The trunk's edge id — which route this marker belongs to.
	@return: The marker, so the caller can stamp the family's batch slice on it
	         once every path in the chunk has been drawn.
	"""
	var marker := Node3D.new()
	marker.name = BIKE_PATH_MARKER_NAME
	marker.add_to_group(BIKE_PATH_GROUP)
	# THE KEY THIS POLYLINE'S HASHES ARE KEYED ON: `Vector2i(edge_id,
	# TRUNK_TURN_ROW)`, the trunk's pair-packed key. It rides under the one name
	# `origin` because every consumer that reads it is asking the same question —
	# "which polyline is this?" — and the trunk row is out of the world (see
	# `TRUNK_TURN_ROW`), so it can never collide with a real chunk.
	marker.set_meta("origin", origin)
	# ...AND WHICH ROUTE, so a consumer can tell one trunk's share from another's
	# without re-deriving anything from the position. (The -1 the retired spur
	# tier wore here is gone with it; every marker now carries a real edge id.)
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


static func touched_anchors(terrain: Node3D) -> Array[int]:
	"""
	Every anchor index a trunk touches, least first: both ends of every edge in
	`terrain.bike_edges()`.

	@param terrain: The `EndlessTerrain`.
	@return: Sorted anchor indices into `terrain.bike_anchors()`.

	DERIVED FROM THE TRUNK SET and never from a second opinion about where the
	corridor is (owner ruling 2026-09-19, amendment to bead `godot-test1-z2yv.3`):
	an anchor with no incident edge gets no rack, whatever kind it is. COSTS NO
	DRAW — the edge set is a hash dispatch over a table already pure in
	`run_seed`.
	"""
	var out: Array[int] = []
	for edge: Dictionary in terrain.bike_edges():
		for key: String in ["a", "b"]:
			var idx: int = int(edge[key])
			if not out.has(idx):
				out.append(idx)
	out.sort()
	return out


static func rack_owners(terrain: Node3D) -> Dictionary:
	"""
	Each anchor's rack-owner chunk, settled ONCE PER RUN: `{ index: Vector2i }`.
	Anchors with no keep-out-clearing candidate anywhere are simply absent.

	Memoized in `terrain._bike_trunk_cache` beside the routes: same lifecycle
	(dropped by `_drop_seeded_memos()`), no new terrain var, no static state.
	The per-chunk hook asks it for every touched anchor, so computing the map
	per chunk instead of per run would bill every chunk for the whole anchor
	table's search.
	"""
	var cache: Dictionary = terrain._bike_trunk_cache
	if cache.has("rack_owners"):
		return cache["rack_owners"]
	var owners := {}
	var anchors: Array[Dictionary] = terrain.bike_anchors()
	var waypoints: Array[Dictionary] = terrain.waypoint_sites()
	for i in anchors.size():
		var site: Vector2 = rack_site(terrain, anchors[i]["pos"], waypoints)
		if site == Vector2.INF:
			continue
		owners[i] = terrain.world_to_chunk(Vector3(site.x, 0.0, site.y))
	cache["rack_owners"] = owners
	return owners


static func rack_site(terrain: Node3D, anchor_pos: Vector2,
		waypoints: Array[Dictionary]) -> Vector2:
	"""
	The anchor's PRELIMINARY rack site (world XZ): the nearest fixed offset
	clearing the keep-out stencil, or `Vector2.INF` when none does.

	@param anchor_pos: The anchor's world XZ, from `terrain.bike_anchors()`.
	@param waypoints: `terrain.waypoint_sites()`, for `trunk_keep_out`.
	@return: The nearest clearing offset, or `Vector2.INF`.

	KEEP-OUTS ONLY and therefore PURE in (anchor, `run_seed`) — no obstacles
	read, no draw rolled — so every chunk agrees on it and exactly one chunk
	contains it: that chunk owns the rack (`rack_owners()`). The owner then
	settles the FINAL site against its own obstacles (`rack_build_site`); the
	preliminary site is where the owner is, not necessarily where the rack ends
	up, and `bike_path_selfcheck` R1 knows the difference.
	"""
	for dist: float in RACK_SITE_DISTANCES:
		for dir: Vector2 in RACK_SITE_DIRECTIONS:
			var site: Vector2 = anchor_pos + dir * dist
			if _site_keep_out(terrain, site, waypoints):
				continue
			return site
	return Vector2.INF


static func _site_keep_out(terrain: Node3D, site: Vector2,
		waypoints: Array[Dictionary]) -> bool:
	"""
	The stencil one rack candidate must clear: the shipped `trunk_keep_out` —
	the tower's disc, a teleport circle, a landmark's chunk, the coin road's
	swath — at the site AND at both rail ends (`RACK_EXTENT`). T5 sweeps box
	centres, so a site that clears with a box inside a keep-out is the exact
	defect it exists for.
	"""
	return trunk_keep_out(terrain, site, waypoints) \
			or trunk_keep_out(terrain, site + Vector2(RACK_EXTENT, 0.0), waypoints) \
			or trunk_keep_out(terrain, site - Vector2(RACK_EXTENT, 0.0), waypoints)


static func rack_build_site(terrain: Node3D, anchor_pos: Vector2, owner: Vector2i,
		waypoints: Array[Dictionary], obstacles: Array, centre: Vector2) -> Vector2:
	"""
	The FINAL rack site: the nearest candidate that clears the stencil, is
	homed in `owner`, and reads free against the owner's OWN `obstacles` — or
	`Vector2.INF`, in which case no rack is built and no marker planted.

	Runs in the owner chunk only. The homing filter is what keeps dedup by
	construction under site ownership: without it every chunk whose square a
	candidate falls in would build one.
	"""
	for dist: float in RACK_SITE_DISTANCES:
		for dir: Vector2 in RACK_SITE_DIRECTIONS:
			var site: Vector2 = anchor_pos + dir * dist
			if terrain.world_to_chunk(Vector3(site.x, 0.0, site.y)) != owner:
				continue
			if _site_keep_out(terrain, site, waypoints):
				continue
			if _footprint_taken(obstacles, site - centre, RACK_RADIUS):
				continue
			return site
	return Vector2.INF


static func _build_rack(terrain: Node3D, anchor_index: int, site: Vector2,
		centre: Vector2, rng: RandomNumberGenerator, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D, cube_cursor: int,
		parent_chunk: MeshInstance3D, markers: Array[Node3D]) -> int:
	"""
	The rack at world-XZ `site`: one low rail, `RACK_UPRIGHT_COUNT` thin hoop
	uprights, ONE footprint for the whole stand, and the bare `bike_stand`
	marker the rental epic will read.

	@param anchor_index: The index into `terrain.bike_anchors()` this rack stands
	                     for — the marker's `anchor` meta.
	@param centre: The building chunk's centre in world XZ.
	@return: The advanced CUBE cursor.

	CUBE ONLY, through `create_box` off the family's fixed-seed builder RNG like
	everything else, so the boxes land inside the family's
	batch_start/batch_count slice. The marker carries the WORLD position: it
	outlives any one chunk's frame and the rental epic must not re-derive it.
	Plus PARKED_BIKES_PER_RACK four-CUBE parked-bike silhouettes (bead
	`godot-test1-z2yv.9`), one per hoop after the uprights: visual-only, no
	footprint, constant palette — the const block carries the why.
	"""
	var at: Vector2 = site - centre
	terrain.create_box(
			Vector3(at.x, RACK_RAIL_Y, at.y),
			Vector3(RACK_RAIL_LENGTH, RACK_RAIL_HEIGHT, RACK_RAIL_DEPTH),
			0.0, rng, block_batch, block_body, 0.0, RACK_COLOR, true,
			ChunkBatch.BoxKind.CUBE)
	cube_cursor += 1
	for u in RACK_UPRIGHT_COUNT:
		var x: float = at.x - RACK_RAIL_LENGTH * 0.5 \
				+ RACK_RAIL_LENGTH * float(u) / float(RACK_UPRIGHT_COUNT - 1)
		terrain.create_box(
				Vector3(x, RACK_UPRIGHT_HEIGHT * 0.5, at.y),
				Vector3(RACK_UPRIGHT_WIDTH, RACK_UPRIGHT_HEIGHT, RACK_UPRIGHT_DEPTH),
				0.0, rng, block_batch, block_body, 0.0, RACK_COLOR, true,
				ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1
	# THE PARKED BIKES (bead `godot-test1-z2yv.9`): one four-CUBE silhouette per
	# hoop, AFTER the rack's last draw so every existing box lands where it did.
	# Perpendicular to the rail on alternating sides, constant palette, no
	# footprint of their own — the const block carries the geometry argument.
	for b in PARKED_BIKES_PER_RACK:
		var hx: float = at.x - RACK_RAIL_LENGTH * 0.5 \
				+ RACK_RAIL_LENGTH * float(b) / float(maxi(1, PARKED_BIKES_PER_RACK - 1))
		var side: float = 1.0 if b % 2 == 0 else -1.0
		var tint: Color = PARKED_BIKE_COLORS[b % PARKED_BIKE_COLORS.size()]
		for w in [-1.0, 1.0]:
			terrain.create_box(
					Vector3(hx, PARKED_BIKE_WHEEL_Y, at.y + w * PARKED_BIKE_WHEEL_HALF_SPAN),
					PARKED_BIKE_WHEEL_DIMS, 0.0, rng, block_batch, block_body, 0.0,
					tint, false, ChunkBatch.BoxKind.CUBE)
			cube_cursor += 1
		terrain.create_box(
				Vector3(hx, PARKED_BIKE_FRAME_Y, at.y),
				PARKED_BIKE_FRAME_DIMS, PI * 0.5, rng, block_batch, block_body, 0.0,
				tint, false, ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1
		terrain.create_box(
				Vector3(hx, PARKED_BIKE_SADDLE_Y, at.y + side * PARKED_BIKE_SADDLE_END),
					PARKED_BIKE_SADDLE_DIMS, 0.0, rng, block_batch, block_body, 0.0,
					tint, false, ChunkBatch.BoxKind.CUBE)
		cube_cursor += 1
	# NON-CLIMBABLE, like the poles: a stand has no top to stand on.
	obstacles.append({
		"pos": Vector3(at.x, 0.0, at.y),
		"radius": RACK_RADIUS,
		"top": RACK_TOP,
		"climbable": false,
	})
	var stand := Node3D.new()
	# SUFFIXED BY ANCHOR, because dedup is by construction: one anchor lives in
	# exactly one chunk, so the name is unique among siblings and Godot never
	# @-renames it into a bare class label in someone else's diagnostics.
	stand.name = "%s%d" % [BIKE_STAND_MARKER_NAME, anchor_index]
	stand.add_to_group(BIKE_STAND_GROUP)
	stand.set_meta("anchor", anchor_index)
	stand.set_meta("pos", Vector3(site.x, 0.0, site.y))
	# POSITIONED AT THE SITE, chunk-local. A bare marker left at the chunk
	# origin claims one place in its metas and stands in another — and the
	# tower's disc counts nodes, so a stand's node and its `pos` must agree.
	stand.position = Vector3(at.x, 0.0, at.y)
	parent_chunk.add_child(stand)
	markers.append(stand)
	return cube_cursor


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


static func _pole_flanks_road_crossing(terrain: Node3D, stations: Array[Dictionary], seg_i: int) -> bool:
	"""
	Does the pole on segment `seg_i` flank a road crossing?
	
	True when any segment within `TRUNK_CROSSING_FLANK_SEGMENTS` has its midpoint
	inside the coin swath — i.e. this pole stands just past the paint gap the
	shipped keep-out draw skip leaves where the WALK went through. Asked of the
	shipped `_road_lateral_distance` comparison, the same one C1 re-measures.
	Pure, costs no draw, and called only where a trunk pole is actually built.
	"""
	var lo: int = maxi(0, seg_i - TRUNK_CROSSING_FLANK_SEGMENTS)
	var hi: int = mini(stations.size() - 2, seg_i + TRUNK_CROSSING_FLANK_SEGMENTS)
	for o in range(lo, hi + 1):
		var a: Vector2 = stations[o]["pos"]
		var b: Vector2 = stations[o + 1]["pos"]
		var mid: Vector2 = (a + b) * 0.5
		if terrain._road_lateral_distance(mid.x, mid.y, BIKE_ROAD_CLEARANCE) < BIKE_ROAD_CLEARANCE:
			return true
	return false


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


static func _footprint_taken(obstacles: Array, at: Vector2, radius: float = BIKE_POLE_RADIUS) -> bool:
	"""
	Would a thing of this CHUNK-LOCAL footprint radius stand inside something
	already built at this spot?

	The chunk's own `obstacles` list is the shared currency: blocks, biome content,
	artifacts, camps, chests and the city's plateaus are all in it by the time this
	spawner runs, which is exactly why the call site sits where it does. The
	candidate asks with its OWN radius — a post with the pole's, a rack with the
	stand's — because the currency only works when the asker spends what it is.
	"""
	for o: Variant in obstacles:
		var entry: Dictionary = o
		var pos: Vector3 = entry["pos"]
		if Vector2(pos.x - at.x, pos.z - at.y).length() < float(entry["radius"]) + radius:
			return true
	return false
