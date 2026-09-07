class_name TerrainBiomes
extends RefCounted
## WHAT EACH BAND IS MADE OF — the eight biome content builders, the spot test
## every one of them places through, and the oasis / dune site rolls — lifted
## whole out of endless_terrain.gd by bead godot-test1-ftn.5.
##
## MECHANICAL EXTRACTION. Not one number, draw, order or comment changed: the
## bodies below are byte-identical to the ones that were in the world engine bar
## the `terrain.` the reference costs, and the 625-chunk A/B in the PR is what
## says so. A bug found on the way out was a separate bead, not a fix here.
##
## THE SHAPE IS `landmark_builders.gd`'s and `terrain_predators.gd`'s (the ftn
## epic's FRAMEWORK): a static library that RECEIVES the terrain and calls
## `terrain.create_box` / `terrain.biome_at` / `terrain.is_river_at` back through
## it. `create_chunk` still owns the call-order list and calls
## `TerrainBiomes.spawn_biome_content_in_chunk(self, ...)` from it.
##
## THE BIOME FIELD DELIBERATELY DID NOT MOVE. `_biome_noise`, `biome_at`,
## `is_river_at` and the `Biome` enum stay in `endless_terrain.gd`: the noise is
## one half of the CPU/GPU PARITY CONTRACT with `ground.gdshader` and has to sit
## beside the rest of the world's geometry, `biome_at` / `is_river_at` are the
## public API half the project calls, and the enum cannot move at all while a
## `const` Dictionary in that file is keyed by it. This file is the CONTENT; the
## FIELD is still the terrain's.
##
## `_biome_spot_ok` IS ONE FUNCTION AND STAYS ONE. It is the single home of the
## river / road-clearance / footprint-overlap rule that every builder here places
## through, and the reason placement is split in two (a rarity roll on its own
## hash stream, then a candidate loop where `obstacles` exists). Splitting it per
## biome is how the four clauses drift apart.
##
## THE TUNING CONSTANTS MOVED HERE AFTER ALL (bead godot-test1-ftn.27) — the
## follow-up this paragraph used to file. The three content banners plus the
## oasis/dune salts below are byte-identical to the terrain's, comments and
## all; the spenders here read them bare, and the nineteen names a third file
## reads are aliased back on the terrain, so every self-check that reads them
## off the terrain's `get_script_constant_map()` is untouched.
##
## THE ENTRY POINT KEEPS A FORWARDER on the terrain, `create_box`'s precedent
## (bead godot-test1-ftn.1): `spawn_biome_content_in_chunk` and `_biome_spot_ok`
## are called from a dozen self-checks and from sibling spawners that were not
## in this cut, so rewriting every call site is the opposite of a mechanical
## move.


## Salt for desert oasis placement decisions (independent hash stream).
const OASIS_SALT: int = 0x0A_5157  # "OASIS" ish

## Salt for desert dune placement decisions (independent hash stream).
const DUNE_SALT: int = 0xD0_1D4E  # "DUNE" ish

# ----------------------------------------------------------------------------
# BIOME CONTENT TUNING (what each biome actually BUILDS)
# ----------------------------------------------------------------------------
##
## Every value below feeds the three builders in the BIOME CONTENT section. They
## all spend the same currency — create_box entries in the chunk's single
## MultiMesh — so "more content" costs instances, not draw calls.

## DESERT — sparsity is achieved by dividing the ordinary scattered-block TARGET
## by N (see spawn_objects_in_chunk). Deliberately a target and NOT an RNG roll:
## an extra draw there would shift the shared chunk stream and reshuffle every
## block, crocodile and coin in the chunk.
const DESERT_BLOCK_KEEP_EVERY: int = 3

## DESERT — cactus stacks: how many candidates, how big, how far from the road.
## They are the only thing a desert ADDS; the emptiness comes from the skip above.
## NOTE: crocodile density is completely UNCHANGED in a desert (see
## spawn_crocodiles_in_chunk) — a desert reads empty through DECORATION only,
## per the project's "entity counts are never reduced" rule.
const CACTUS_MIN: int = 4
const CACTUS_MAX: int = 9
## 12 m, not 10: a cactus footprint is NON-climbable, so _settle_coin_y SKIPS any
## road coin it overlaps rather than perching one on top (unlike the ordinary
## scattered blocks, which are climbable and may stand on the swath freely). At
## exactly road_width_max * 0.5 = 10 a cactus sits on the outermost coin lane and
## punches silent holes in the trail; 12 clears the swath plus a cactus radius.
const CACTUS_ROAD_CLEARANCE: float = 12.0
const CACTUS_WIDTH_MIN: float = 0.45
const CACTUS_WIDTH_MAX: float = 0.75
const CACTUS_SEGMENT_MIN: float = 0.9   # height of one stacked segment
const CACTUS_SEGMENT_MAX: float = 1.6
const CACTUS_ARM_CHANCE: float = 0.45   # chance of one short side "arm" box
const CACTUS_COLOR := Color(0.24, 0.42, 0.24)

## FOREST — tree budget per forest chunk. 25-40 trees × ~4 boxes each still ride
## the chunk's ONE MultiMesh, so a forest chunk is the same single block draw
## call as a plains chunk; only the trunks add collision shapes.
const FOREST_TREES_MIN: int = 25
const FOREST_TREES_MAX: int = 40

## FOREST — minimum distance from the coin-road centerline. The widest coin band
## half-width is road_width_max * 0.5 = 10, so 14 keeps the whole scattered coin
## swath tree-free and the road followable through a wood.
const FOREST_ROAD_CLEARANCE: float = 14.0

## FOREST — trunk and canopy proportions. The canopy is 2-3 boxes of decreasing
## size stacked on the trunk top, each built with collide = false (visual only).
const TREE_TRUNK_WIDTH_MIN: float = 0.45
const TREE_TRUNK_WIDTH_MAX: float = 0.75
const TREE_TRUNK_HEIGHT_MIN: float = 2.2
const TREE_TRUNK_HEIGHT_MAX: float = 3.8
const TREE_CANOPY_LAYERS_MIN: int = 2
const TREE_CANOPY_LAYERS_MAX: int = 3
const TREE_CANOPY_WIDTH_MIN: float = 2.2  # widest (bottom) canopy layer
const TREE_CANOPY_WIDTH_MAX: float = 3.4
const TREE_CANOPY_LAYER_HEIGHT: float = 1.0  # legacy slab height: crown seat dip (0.3m) and seam lean bound
const TREE_CANOPY_TAPER: float = 0.68     # each layer up is this fraction as wide
const TREE_TRUNK_COLOR := Color(0.34, 0.24, 0.16)
const TREE_LEAF_COLOR := Color(0.16, 0.36, 0.19)

## FOREST — THE ANTI-MINECRAFT SET (bead godot-test1-u7a, owner: "trees are too
## minecraft-ish, we need own style"). Every one of these is a TRANSFORM or a
## COLOUR, because that is all a MultiMesh instance can carry: the chunk keeps its
## ONE unit-cube batch and its ONE draw call, and a forest chunk emits exactly the
## same number of instances it always did. What changed is that no two of them
## line up any more.
##
##   * TREE_LEAF_COLOR_WARM is the far end of a per-tree tint ramp. The flat single
##     green was the loudest half of the Minecraft read — a wood of identically
##     coloured slabs reads as one material, not as foliage.
##   * TREE_CANOPY_YAW_STEP turns each canopy layer 45 deg against the one below.
##     A square has 90 deg symmetry, so the stack alternates 0 / 45 / 0 and the
##     silhouette from any angle is an interference pattern of two squares — an
##     octagon-ish crown instead of a column of aligned cubes. Costs NO rng draw.
##   * TREE_CANOPY_DEPTH_RATIO makes each layer a rectangle rather than a square,
##     so the alternating yaw actually crosses instead of repeating. The half
##     diagonal of a (w, w*0.84) plan is 0.65*w, UNDER the 0.71*w a square costs,
##     so the chunk-seam bound below stays an over-estimate.
##   * TREE_TRUNK_TILT_MAX leans the trunk. A tree leans; a fence post does not.
##     The canopy is offset to follow the leaning trunk's axis (see the builder).
const TREE_LEAF_COLOR_WARM := Color(0.33, 0.46, 0.15)  # sun-struck yellow-green
const TREE_LEAF_CROWN_LIFT: float = 0.40  # how far the TOP layer is pushed toward warm
const TREE_CANOPY_YAW_STEP: float = PI * 0.25  # 45 deg per layer up
const TREE_CANOPY_DEPTH_RATIO: float = 0.84    # plan is a rectangle, not a square
const TREE_CANOPY_WIDTH_JITTER_MIN: float = 0.78
const TREE_CANOPY_WIDTH_JITTER_MAX: float = 1.06
const TREE_TRUNK_TILT_MAX: float = 0.08  # radians of lean, either way
const TREE_CANOPY_TILT_MAX: float = 0.16   # radians, alternating sign per layer
const TREE_CANOPY_SLIDE: float = 0.14      # fraction of a layer's width it slides off axis

## FOREST — THE CANOPY IS A BLOB, NOT A SLAB (bead godot-test1-y1o.2, epic y1o
## "get rid of blocks"; the honest caveat u7a's developer left behind — "still
## built from boxes, still reads as low-poly blocks at distance"). u7a's whole
## set above is transforms and colours, because a batch entry could not carry a
## SHAPE; bead y1o.1 gave it one, and the forest is its first consumer. Every
## canopy layer is now `ChunkBatch.BoxKind.SPHERE` — the shared unit sphere at
## UNIT_SPHERE_RADIAL x UNIT_SPHERE_RINGS (8 x 4, faceted on purpose: the facets
## ARE style direction A, and that one number lives in chunk_batch.gd so the
## whole world's roundness is retuned in one place).
##
## NOT ONE RNG DRAW MOVED. The two numbers below are DERIVED from the width this
## layer already drew, so the biome stream is byte-identical and every site after
## the forest in the same chunk stays where it was — which is what makes this
## bead's A/B against master read "only `kind` and the canopy box dimensions".
##
##   * TREE_CANOPY_BLOB_HEIGHT: a sphere squashed into u7a's flat 1.0 m slab box
##     is a flying saucer, and three of them a pagoda. A blob is nearly as tall as
##     it is wide, so its height comes off its own width.
##   * TREE_CANOPY_BLOB_OVERLAP: the next blob starts HALF way up the last one, so
##     the crown is one lumpy mass rather than beads on a string. Under 0.5 the
##     blobs fuse into a ball; over it they separate and the tree is a lollipop
##     stack again.
##
## The crown's `canopy_y` also stopped being a layer CENTRE and became the crown's
## FOOT — see the builder. A blob is up to 2.5 m tall where a slab was 1.0, and
## centring it on the old y hung a fat crown down to head height on a short trunk.
const TREE_CANOPY_BLOB_HEIGHT: float = 0.70
const TREE_CANOPY_BLOB_OVERLAP: float = 0.50

## MOUNTAIN — massifs per mountain chunk. Each is a stack of shrinking boxes, so
## a "range" is 2-4 crude peaks per chunk and the biome band is several chunks
## across.
const MOUNTAIN_MASSIF_MIN: int = 2
const MOUNTAIN_MASSIF_MAX: int = 4
const MOUNTAIN_PLACE_TRIES: int = 5      # candidate spots tried per massif
const MOUNTAIN_HEIGHT_MIN: float = 8.0
const MOUNTAIN_HEIGHT_MAX: float = 20.0
const MOUNTAIN_BASE_WIDTH_MIN: float = 7.0
const MOUNTAIN_BASE_WIDTH_MAX: float = 13.0
const MOUNTAIN_LAYER_TAPER: float = 0.74  # each layer up is this fraction as wide
const MOUNTAIN_LAYER_JITTER: float = 0.5  # metres of lateral wobble per layer

## MOUNTAIN — minimum height of one layer, in metres. A massif is only "walk
## around it" if you cannot simply hop up its steps: the player's jump apex is
## 3.61 m (see the gravity note in CLAUDE.md), so every step has to clear that.
## This is what SETS the layer count (height / this, floored at 2), which is why
## there is no layer-count roll: with heights of 8-20 m a massif is 2-5 layers,
## and a wide short one is a couple of sheer slabs rather than a climbable
## ziggurat. (An earlier version drew a 4-7 layer count and clamped it with this;
## the clamp always won, so the draw was dead and the "4-7 layers" it implied
## never happened.)
const MOUNTAIN_MIN_LAYER_HEIGHT: float = 4.0

## MOUNTAIN — keeps the base well inside the chunk so a massif never straddles a
## seam (same idea as ARTIFACT_EDGE_MARGIN, bigger because a massif is bigger).
## Layers are YAWED, so the reach from the centre is the rotated half-diagonal,
## not the half-width: MOUNTAIN_BASE_WIDTH_MAX * 0.71 + MOUNTAIN_LAYER_JITTER =
## 9.73 m — the same expression the footprint radius uses below. 10.0 covers it
## and still leaves a 30 x 30 m placement box, wide enough that 2-4 massifs
## spread across the chunk instead of piling into the middle of every one and
## reading as a per-chunk grid.
const MOUNTAIN_EDGE_MARGIN: float = 10.0

## MOUNTAIN — footprint radius above which an already-placed obstacle is treated
## as "do not bury this" when siting a massif. Scattered props top out at
## object_size_max * 0.71 = 1.78 m and are deliberately fair game (see
## _spawn_mountain_content); artifacts start at 2.5 m, and an artifact sealed
## inside 20 m of rock takes its coin ring and its guaranteed gem with it.
const MOUNTAIN_AVOID_RADIUS: float = 2.0

## MOUNTAIN — ...but a WIDE thing is not the only thing worth avoiding: a TALL
## one is a ladder. A stacked block tower reaches ~6.4 m with a radius of only
## 1.78 m, so the radius rule alone lets one stand right against a massif whose
## first ledge is MOUNTAIN_MIN_LAYER_HEIGHT (4 m) up — a 1.6 m hop onto the
## summit, well inside the player's 3.61 m jump apex, which quietly breaks the
## "impassable, you walk around it" contract the whole mountains-as-blocks design
## rests on. So anything taller than one jump is avoided too, whatever its width.
## Only a minority of towers clear this, so massifs still find room to generate.
const MOUNTAIN_AVOID_TOP: float = 3.61

## MOUNTAIN — the road clearance is what cuts a CANYON through a range: the
## massifs simply refuse to stand near the centerline, so the coin road threads
## between them. Comfortably larger than FOREST_ROAD_CLEARANCE (a tree you can
## sidestep; a massif you would have to walk minutes around). Any value is safe:
## _road_lateral_distance sizes its station scan window from the clearance it is
## given, so the answer stays honest however far this is pushed.
const MOUNTAIN_ROAD_CLEARANCE: float = 24.0

## MOUNTAIN — a massif at least this tall gets its top layers forced snow-white.
const MOUNTAIN_SNOW_HEIGHT: float = 14.0
const MOUNTAIN_SNOW_LAYERS: int = 2      # how many top layers turn to snow
const MOUNTAIN_SNOW_COLOR := Color(0.92, 0.94, 0.96)

# ----------------------------------------------------------------------------
# CITY — small houses, market stalls, traffic lights and lamp posts
# ----------------------------------------------------------------------------
##
## THE ROOFS ARE THE POINT. Every biome so far took the rest-from-crocodiles role
## AWAY (a cactus, a tree trunk and a massif all record NON-climbable footprints,
## so a road coin over one is skipped rather than perched). The city gives it back
## at scale: every house is capped at CITY_HOUSE_HEIGHT_MAX = PROP_MAX_STEP, so
## every roof EAVE in a city is one jump from the pavement and a city block is a
## field of croc-free perches. (It said "every FLAT roof" until bead y1o.5 made
## them pitched and y1o.36 made the pitch solid: what you land on is the eave,
## flush with the hull top, and the ridge is walked up to.) That is what pays for
## the reduced croc density
## below reading as "a safer place" rather than as "an emptier place".
##
## NO EMISSIVE ANYTHING, and the budget spent is exactly ZERO of the four
## _spawn_artifact_accent slots an artifact may use. Lamps and signals are BRIGHT
## ALBEDO boxes in the chunk's one MultiMesh — a city of glowing traffic lights is
## the single fastest way to turn a batched territory into dozens of real
## MeshInstance3D nodes with an unshaded material each.
##
## THERE IS NO STREET NETWORK AND THERE IS NOT GOING TO BE ONE. A road network is
## a layout system (graph, intersections, parcels, frontage) that this engine has
## no use for anywhere else, and the coin road already IS the one road in the
## world — it threads through a city as its main street for free, because
## CITY_ROAD_CLEARANCE keeps the buildings off the coin swath. What produces the
## street READ instead costs two lines: candidate positions are snapped to a
## coarse CITY_BLOCK_PITCH grid with a little jitter, and house yaws are quantised
## to quarter turns. Rows of parallel facades along shared lines is what a person
## recognises as a town; a real network is not.

## How many house SITES are tried per city chunk. A house footprint is ~2.5-3.5 m
## and _biome_spot_ok rejects any overlap with the ~12 scattered props already in
## the chunk, so this is a candidate count, not a house count — measured, it
## yields roughly 4-7 built houses per chunk.
const CITY_HOUSE_TRIES_MIN: int = 10
const CITY_HOUSE_TRIES_MAX: int = 16

## Market stall and street-light candidate counts, same "tries, not results" rule.
const CITY_STALL_TRIES_MIN: int = 2
const CITY_STALL_TRIES_MAX: int = 5
const CITY_LIGHT_TRIES_MIN: int = 4
const CITY_LIGHT_TRIES_MAX: int = 7

## Minimum distance from the coin-road centerline. 13, like FOREST_ROAD_CLEARANCE
## (14) and for the same arithmetic: the widest coin band half-width is
## road_width_max * 0.5 = 10, so this keeps the whole scattered coin swath clear
## of buildings and the road stays followable — the city's "main street".
## Houses record CLIMBABLE footprints, so unlike a tree a house standing on the
## swath would perch coins on its roof rather than punch holes in the trail; 13 is
## still the right number, because a coin trail that climbs a building is a trail
## the player has to leave the ground to follow.
const CITY_ROAD_CLEARANCE: float = 13.0

## Coarse grid the candidate positions snap to, plus the wobble left on top of it.
## The pitch is a bit wider than the widest house so neighbours on the same line
## do not touch; the jitter keeps the grid from reading as graph paper.
const CITY_BLOCK_PITCH: float = 9.0
const CITY_BLOCK_JITTER: float = 1.3

## HOUSE — hull proportions. HEIGHT_MAX IS THE CLIMBABILITY CONTRACT AS A NUMBER:
## it must stay <= PROP_MAX_STEP (2.6), or the roofs stop being reachable from
## flat ground and the whole "the city is the rest spot" design silently dies.
const CITY_HOUSE_WIDTH_MIN: float = 3.0
const CITY_HOUSE_WIDTH_MAX: float = 4.4
const CITY_HOUSE_DEPTH_FACTOR_MIN: float = 0.70   # depth as a fraction of width
const CITY_HOUSE_DEPTH_FACTOR_MAX: float = 1.00
const CITY_HOUSE_HEIGHT_MIN: float = 2.0
const CITY_HOUSE_HEIGHT_MAX: float = 2.6

## HOUSE — how far the roof oversails the walls. Since bead godot-test1-y1o.36 the
## eave is SOLID: it is the lip of the pitch, at exactly the hull top, hanging
## `CITY_ROOF_EAVES` past the wall — so it is also the surface a hero jumping from
## the pavement lands on, which is why `CITY_HOUSE_HEIGHT_MAX` is the number held
## against PROP_MAX_STEP and the ridge is not.
##
## CITY_ROOF_THICKNESS is the FLAT slab of Budapest's authored GATE DISTRICT
## houses (`_spawn_district_houses`), which are pure CUBE and deliberately
## untouched by this bead — the procedural band's roof is a WEDGE and has no
## thickness, it has a pitch.
const CITY_ROOF_EAVES: float = 0.25
const CITY_ROOF_THICKNESS: float = 0.14

## THE ROOF'S RISE, as a fraction of the roofed DEPTH (bead godot-test1-y1o.5).
## A `BoxKind.WEDGE` roof needs a height to be a pitch at all, and this is where
## it comes from: it is DERIVED from the house the roof is going on, so it costs
## no RNG draw (a draw here would slide every later object in the chunk) and a
## deep house gets a deep roof rather than every roof being the same slab.
##
## IT IS NOW A WALKABLE SURFACE AND THEREFORE A CEILING, not a taste knob (bead
## godot-test1-y1o.36). The ridge is at the middle of the roofed depth, so each
## slope's rise over run is `2 * CITY_ROOF_RISE_FACTOR` — and that has to stay
## under `TowerInterior.PLAN_RAMP_MAX_SLOPE` (0.575), the project's one "no
## traversal may demand more than this" number, or the hero slides back down the
## roof he just jumped onto. 0.34 was 0.68 and was over it; 0.28 is a slope of
## 0.56 (~29 degrees), which still reads as a terraced-town pitch and no longer
## reads as alpine. `prop_selfcheck` check 7 asserts the arithmetic against
## `PLAN_RAMP_MAX_SLOPE` directly, so this constant cannot drift back up quietly.
##
## Changing it moves NO RNG DRAW — the rise is derived from the depth already
## drawn — so the only thing that differs from the pre-bead world is the roof
## entries' own dimensions.
const CITY_ROOF_RISE_FACTOR: float = 0.28

## HOUSE — the widest footprint a house can claim, used as the "widest this could
## be" radius handed to _biome_spot_ok before the real width is drawn:
## 0.5 * hypot(W_MAX + 2*EAVES, W_MAX + 2*EAVES) = 0.5 * hypot(4.9, 4.9) = 3.47.
##
## THIS IS DELIBERATELY ABOVE MOUNTAIN_AVOID_RADIUS (2.0) and that is the correct
## side to be on, not an oversight: a chunk straddling the city/forest/mountain
## feather can hold both, and a massif is supposed to refuse to grow through a
## house exactly as it refuses to grow through an artifact or a mound.
const CITY_HOUSE_RADIUS_MAX: float = 3.47

## STALL — a market counter under an awning. NON-climbable on purpose even though
## the counter is only ~1 m: the awning hangs over it, so a road coin perched on
## the counter would sit inside canvas. Non-climbable means _settle_coin_y skips
## it instead (the cactus / tree-canopy call).
const CITY_STALL_WIDTH_MIN: float = 1.8
const CITY_STALL_WIDTH_MAX: float = 2.8
const CITY_STALL_COUNTER_HEIGHT: float = 1.0
const CITY_STALL_AWNING_HEIGHT: float = 2.3
const CITY_STALL_RADIUS_MAX: float = 2.2

## STREET FURNITURE — a traffic signal (mast + head + three lamps) or a lamp post
## (mast + arm + one lamp), rolled per candidate. Thin, so its footprint is small
## and NON-climbable (a mast has no top to stand on).
const CITY_LIGHT_HEIGHT_MIN: float = 3.2
const CITY_LIGHT_HEIGHT_MAX: float = 4.4
const CITY_LIGHT_MAST_WIDTH: float = 0.20
const CITY_LIGHT_LAMP: float = 0.22       # one signal lamp box, a side
const CITY_LIGHT_RADIUS_MAX: float = 0.95
const CITY_SIGNAL_CHANCE: float = 0.55    # else a lamp post

# ----------------------------------------------------------------------------
# SNOW — frozen dead trees and mammoth skeletons on an open tundra
# ----------------------------------------------------------------------------
##
## WHAT MAKES THIS BAND DIFFERENT FROM ITS NEIGHBOURS, in one line each: the city
## is the SAFE territory (roofs everywhere, croc target divided), the mountain is
## the IMPASSABLE one (massifs you route around), and the snow is the HOSTILE one —
## croc density is the ordinary distance-scaled figure, nothing is thinned, and the
## only shelter is the ice you can climb onto. That is why all three SNOW props
## record climbable footprints and everything the builder below adds does not.
##
## THE BUILDER ADDS THE BIG, SPARSE THINGS ONLY. Ice rocks and drifts are SCATTERED
## PROPS (the phase-1 machinery — see TerrainProps' _prop_ice_rock and friends), because they are
## exactly the 0.7-1.8 m clutter the bare cubes used to be. What lives here is what
## a prop cannot be: a 4 m dead tree, and a skeleton the size of a small building.

## Frozen dead trees per snow chunk. Deliberately far below the forest's 25-40: a
## tundra is not a thinned wood, it is open ground with the occasional dead thing
## standing in it, and the emptiness between them is the whole read.
const FROZEN_TREE_MIN: int = 6
const FROZEN_TREE_MAX: int = 14

## Same arithmetic as FOREST_ROAD_CLEARANCE (14) one notch tighter: the widest coin
## band half-width is road_width_max * 0.5 = 10, so 12 keeps the scattered coin
## swath clear of trunks. It can be tighter than the forest's because these trees
## are bare — there is no canopy to close over the trail.
const FROZEN_TREE_ROAD_CLEARANCE: float = 12.0

const FROZEN_TREE_TRUNK_WIDTH_MIN: float = 0.34
const FROZEN_TREE_TRUNK_WIDTH_MAX: float = 0.60
const FROZEN_TREE_HEIGHT_MIN: float = 2.6
const FROZEN_TREE_HEIGHT_MAX: float = 4.6
const FROZEN_TREE_BRANCH_LEN: float = 1.5   # one bare branch box, long side
## The deadwood half of bead godot-test1-u7a's restyle. Same rule as the forest's:
## transforms and colours only, no new instances, no new draw call. A dead tree
## leans harder than a living one (nothing is holding it up), each branch is a
## different length rather than the same stick four times, and the timber runs from
## bleached grey to wet-rot brown per tree instead of one flat frost colour.
## The branch multiplier NEVER exceeds 1.0 on purpose: `branch_reach` below is the
## chunk-seam bound, and shrink-only keeps it an over-estimate with no edit there.
const FROZEN_TREE_TILT_MAX: float = 0.11    # radians of lean, either way
const FROZEN_TREE_BRANCH_JITTER_MIN: float = 0.58
const SNOW_DEADWOOD_DARK := Color(0.31, 0.27, 0.24)  # the wet-rot end of the ramp

## MAMMOTH SKELETONS — the territory's marquee prop, and the one place in this file
## where create_box's `tilt` is doing work nothing else could do: a rib is a thin
## box that has to lean INWARD over the spine, and a tusk is a curve made of three
## boxes each leaning further forward than the last.
##
## THE TUSK CURVE NEEDS A YAW OF +PI/2 AND THAT IS NOT A HACK, IT IS THE ONLY WAY.
## create_box offers a yaw (about world Y) and a tilt (about the box's own local X
## AFTER that yaw), so a plain tilt tips a box SIDEWAYS relative to the skeleton's
## axis — fine for a rib, useless for a tusk, which has to sweep FORWARD. Turning
## the box a quarter turn first swings its local X round to the skeleton's lateral
## axis, and the tilt then tips it along the skeleton's length. This is the same
## limitation landmark_builders.gd records on the Kinderdijk sails (there is no
## roll about the third axis at all); a tusk is the shape that happens to fit
## through the gap.
##
## NOT CLIMBABLE, NO NAME, NO TOAST, NO REWARD. It is ambient texture, not a cz3
## destination — the epic's territories-versus-landmarks split — and non-climbable
## for the tree-canopy reason: the footprint is a 5 m circle whose "top" is the
## spine ridge, so a road coin perched on it would float over open ground inside a
## ribcage. _settle_coin_y skips it instead.
const MAMMOTH_MAX: int = 2                  # candidates per snow chunk, 0-2
const MAMMOTH_PLACE_TRIES: int = 4
const MAMMOTH_RADIUS: float = 5.0           # the honest bound; MEASURED at 4.21
const MAMMOTH_ROAD_CLEARANCE: float = 16.0  # > MAMMOTH_RADIUS + road_width_max/2
const MAMMOTH_EDGE_MARGIN: float = 8.0      # > MAMMOTH_RADIUS, so never on a seam
const MAMMOTH_SPINE_LEN_MIN: float = 3.2
const MAMMOTH_SPINE_LEN_MAX: float = 4.2
const MAMMOTH_RIB_PAIRS_MIN: int = 4
const MAMMOTH_RIB_PAIRS_MAX: int = 5
const MAMMOTH_RIB_HEIGHT: float = 1.7
const MAMMOTH_RIB_TILT: float = 0.70        # radians, leaning in over the spine
const MAMMOTH_RIB_HALF_SPREAD: float = 0.90 # rib base offset either side of centre
## Tusk segments, front to tip: [length, tilt]. The tilt SHRINKS along the curve,
## which is what makes a tusk leave the skull almost horizontal and curl upward.
const MAMMOTH_TUSK_SEGMENTS: Array = [[0.95, 1.35], [0.85, 0.95], [0.70, 0.55]]

## MOUNTAIN — grey scree ramp for the rock itself. Cooler and flatter than both
## the warm RAMP_* block colours and the artifacts' grey-green, so a massif reads
## as bare rock rather than as a very large block or a ruin.
const MOUNTAIN_ROCK_A := Color(0.42, 0.42, 0.44)
const MOUNTAIN_ROCK_B := Color(0.58, 0.57, 0.55)

## DESERT OASIS — rare flat-water pool with palm trees, reeds, and climbable boulders.
## ~1 in 8 desert chunks. Water is visual-only (collide=false), with a non-climbable
## footprint so coins don't perch. Palms (trunk + fronds) and boulders are solid.
const OASIS_CHANCE: float = 0.12  # ~1 in 8
const OASIS_PLACE_TRIES: int = 4
## Placement/clearance radius. Bounds the WHOLE oasis — water, palms AND boulders —
## which is what makes the _biome_spot_ok call below an honest test. NOT the water size.
const OASIS_RADIUS: float = 8.0
## Water slab radius, deliberately a SEPARATE constant. Shrinking one constant for both
## jobs would pull the spot check in to ~3 m while boulders still scattered to ~6 m, so
## boulders would land inside cacti the check had just cleared — the fused-camp-huts bug
## one scale down. Every ring below is rebased on whichever radius actually bounds it.
const OASIS_WATER_RADIUS: float = 3.0  # ~6 m across, inside the design's 4-7 m
const OASIS_ROAD_CLEARANCE: float = 16.0
const OASIS_WATER_DEPTH: float = 0.1  # visual slab thickness (y height)
## Both slabs sit ABOVE the y = 0 ground plane, water above rim. The ground, the rim top
## and the water top sharing y = 0 is three coplanar surfaces, and a MultiMesh has no
## depth sort, so that is guaranteed z-fighting — the pool flickers instead of reading as
## water. Pushing the rim BELOW the ground is not the fix either: the ground plane is
## opaque, so a buried rim is simply invisible. Keep both offsets distinct and positive.
const OASIS_RIM_TOP_Y: float = 0.02
const OASIS_WATER_TOP_Y: float = 0.05
const OASIS_WATER_COLOR := Color(0.20, 0.55, 0.75)
const OASIS_WATER_RIM_COLOR := Color(0.15, 0.45, 0.65)
const OASIS_PALM_MIN: int = 2
const OASIS_PALM_MAX: int = 4
const OASIS_PALM_TRUNK_WIDTH: float = 0.6
const OASIS_PALM_TRUNK_HEIGHT: float = 4.5
const OASIS_PALM_FROND_WIDTH: float = 3.0
const OASIS_PALM_FROND_COUNT: int = 4
## The palm half of bead godot-test1-u7a. The old crown was four full-length slabs
## centred ON the trunk at one height with no tilt — a flat plus-sign hat, which is
## the single most Minecraft-shaped thing in the file. Now each frond starts AT the
## crown and hangs outward and DOWN.
##
## THE FROND'S LONG AXIS MOVED FROM LOCAL X TO LOCAL Z, and that is the whole trick:
## create_box's `tilt` is a rotation about the box's local X, so a frond lying along
## X only ROLLS about its own length (invisible on a slab) while one lying along Z
## PITCHES — which is droop. No new create_box parameter was needed for it.
##
## Drooping only ever REDUCES the horizontal span (cos of the droop), and the frond
## now reaches from the trunk instead of through it, so the crown is no wider than
## it was; OASIS_PALM_EDGE_MARGIN grew only for the new trunk lean.
const OASIS_PALM_TILT_MAX: float = 0.10   # radians — a palm curves, it does not stand to attention
const OASIS_PALM_DROOP_MIN: float = 0.20  # radians below horizontal, per palm
const OASIS_PALM_DROOP_MAX: float = 0.38
const OASIS_PALM_DROOP_ALT: float = 1.45  # every other frond droops this much harder
const OASIS_PALM_FROND_JITTER_MIN: float = 0.70  # shrink-only, so the span stays bounded
const OASIS_PALM_EDGE_MARGIN: float = 2.6
const OASIS_PALM_FROND_COLOR := Color(0.28, 0.48, 0.28)
const OASIS_BOULDER_MIN: int = 3
const OASIS_BOULDER_MAX: int = 6
const OASIS_BOULDER_SIZE_MIN: float = 0.8
const OASIS_BOULDER_SIZE_MAX: float = 1.8
const OASIS_REED_CHANCE: float = 0.8  # 80% of oases get reeds

## DESERT DUNES — low sandy mounds that are climbable. ~1 in 5 desert chunks.
## Dunes are short and wide (≤1.5 m tall) to read as walkable hills, not obstacles.
const DUNE_CHANCE: float = 0.20  # ~1 in 5
const DUNE_PLACE_TRIES: int = 3
const DUNE_HEIGHT_MIN: float = 0.8
const DUNE_HEIGHT_MAX: float = 1.5
const DUNE_WIDTH_MIN: float = 6.0
const DUNE_WIDTH_MAX: float = 12.0
const DUNE_ROAD_CLEARANCE: float = 14.0  # keep dunes off the coin path
const DUNE_COLOR_A := Color(0.70, 0.60, 0.45)  # sandy
const DUNE_COLOR_B := Color(0.60, 0.50, 0.35)  # darker sandy


# ============================================================================
# BIOME CONTENT (the geometry each biome adds on top of the ordinary blocks)
# ============================================================================
#
# One entry point, one independent RNG stream, three builders. Structured
# exactly like the artifact spawner above and for the same reasons:
#   - INDEPENDENT STREAM: seeded from chunk coords + run_seed ^ BIOME_SALT, so it
#     consumes ZERO draws from the shared chunk RNG — every block, crocodile and
#     coin the old generator produced is still exactly where it was.
#   - BATCHED: every solid thing built here goes through create_box into the
#     chunk's single MultiMesh (block_batch) and single BlockCollision body
#     (block_body), so a forest chunk is still ONE block draw call.
#   - FOOTPRINTS: each thing built appends a round obstacle to `obstacles`, which
#     later spawners (crocodiles, coins) already know how to read.

static func _oasis_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic oasis placement for one desert chunk — the pattern of _artifact_at
	/ _camp_at applied to rare water features. Pure function of chunk coords + run_seed
	on its own independent hash stream (OASIS_SALT): consumes NO draw from the shared
	biome RNG, so every existing cactus/dune is exactly where it was before oases existed.

	@return: {} when this chunk has no oasis (the common case); otherwise { "seed": int }
	         used by _spawn_desert_oasis for placement and geometry.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, terrain.run_seed ^ OASIS_SALT))

	# Scarcity thins oases to plain terrain at 4 km — the artifact/camp/chest/
	# landmark form: the SAME roll compared against chance * k, no new draw on this
	# stream, so a desert near the centre keeps exactly the oases it always had.
	# The whole oasis is one roll, which is why its palms, boulders and reeds need
	# no k of their own.
	if rng.randf() >= OASIS_CHANCE * terrain.scarcity_at(terrain.chunk_to_world(chunk_pos)):
		return {}

	return { "seed": rng.randi() }

static func _dune_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic sand dune placement for one desert chunk — same split-placement
	pattern as oases, with its own independent DUNE_SALT hash stream.

	@return: {} when this chunk has no dunes; otherwise { "seed": int } for dune RNG.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, terrain.run_seed ^ DUNE_SALT))

	# Scarcity, same form and same reason as _oasis_at above.
	if rng.randf() >= DUNE_CHANCE * terrain.scarcity_at(terrain.chunk_to_world(chunk_pos)):
		return {}

	return { "seed": rng.randi() }

static func spawn_biome_content_in_chunk(terrain: Node3D, chunk_pos: Vector2i, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's biome-specific geometry (cacti / trees / massifs). Called
	from create_chunk AFTER spawn_artifact_in_chunk and BEFORE
	_build_block_multimesh / the block_body attach, so the geometry joins the
	chunk's single MultiMesh and single collision body and its footprints are in
	`obstacles` before crocodiles and coins are placed.

	@param chunk_pos: Chunk coordinates being generated.
	@param obstacles: The chunk's block-footprint list; builders append theirs.
	@param block_batch / block_body: The chunk's visual batch + collision body,
	                                 threaded through to create_box.

	The CHUNK CENTRE decides the biome for the whole chunk's content budget (how
	many trees, how many massifs); individual builders re-test biome_at at each
	object's OWN position, which is what feathers a forest edge across a chunk
	seam instead of stopping dead at it.

	NOTE (deviation from the plan's stated signature): there is no parent_chunk
	param. Everything a biome builds is a create_box entry — no builder has a node
	to parent — so the argument would be dead weight at every call site.
	"""
	# BUDAPEST — no biome geometry in the city (DEC-9). The rect forces the CITY
	# band, so this would draw _spawn_city_content's procedural blocks straight
	# through the authored streets. NOT tower_excludes(): per-system answers, and
	# the Danube's crocodiles are the system that says yes.
	var biome_center: Vector3 = terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(biome_center.x, biome_center.z):
		return

	if not terrain.spawn_biome_content:
		return

	# Own stream. Different coordinate multipliers than the chunk-object /
	# artifact streams (which both use 73856093 / 19349663) so the two hash
	# sequences never correlate — biome content and artifacts must not agree
	# about where "interesting" spots are.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 83492791, chunk_pos.y * 15485863, terrain.run_seed ^ terrain.BIOME_SALT))

	var center: Vector3 = terrain.chunk_to_world(chunk_pos)
	match terrain.biome_at(center.x, center.z):
		terrain.Biome.DESERT:
			_spawn_desert_content(terrain, center, rng, obstacles, block_batch, block_body)
		terrain.Biome.FOREST:
			_spawn_forest_content(terrain, center, rng, obstacles, block_batch, block_body)
		terrain.Biome.MOUNTAIN:
			_spawn_mountain_content(terrain, center, rng, obstacles, block_batch, block_body)
		terrain.Biome.CITY:
			_spawn_city_content(terrain, center, rng, obstacles, block_batch, block_body)
		terrain.Biome.SNOW:
			_spawn_snow_content(terrain, center, rng, obstacles, block_batch, block_body)
		_:
			# PLAINS is the baseline look — the ordinary scattered blocks ARE its
			# content, so it deliberately builds nothing extra here.
			pass


static func _biome_spot_ok(terrain: Node3D, chunk_center: Vector3, local_x: float, local_z: float, radius: float, road_clearance: float, obstacles: Array) -> bool:
	"""
	The single home of the "is this a legal spot for biome geometry" rule.

	@param chunk_center: World centre of the chunk (create_box and `obstacles` are
	                     both chunk-LOCAL; the river/road field is asked in WORLD
	                     space, so the conversion happens here once).
	@param local_x, local_z: Candidate position, chunk-local.
	@param radius: Footprint radius of the thing about to be built, used for the
	               overlap test. Pass the WIDEST the thing could be — the actual
	               width is usually drawn after this call, and reordering the draws
	               to know it exactly would shift the biome stream for nothing.
	@param road_clearance: Minimum distance to the coin-road centerline (metres).
	@param obstacles: Footprints already placed in this chunk (scattered blocks,
	                  feature structures, artifacts, and earlier biome geometry).
	@return: true when the spot is NOT in a river, NOT on the tower's site, is at
	         least `road_clearance` from the road centerline, and overlaps nothing
	         already placed.

	WHY THE TESTS LIVE TOGETHER: they answer one question — "would putting
	something solid here spoil what is already there?". Rivers must stay wadeable
	(a tree in the water is nonsense and a massif would dam it), the coin road must
	stay followable — a forest leaves the coin swath clear, and a mountain range
	leaves a canyon through itself, purely by asking for a bigger clearance — and
	nothing may grow THROUGH something else: without the overlap test a massif
	(radius ~7 m, covering an eighth of a chunk) entombs the scattered blocks under
	it and trees sprout out of walls. The overlap test also gives massifs their
	mutual spacing for free, since each appends its own footprint before the next
	is tried.

	Callers pass DIFFERENT clearances (trees a little, massifs a lot), which is why
	the clearance is a parameter rather than a constant read in here; it is handed
	straight to _road_lateral_distance, which sizes its scan window from it.

	THE RIVER TEST IS LIVE — do not delete it as dead code. It is inert for the
	three BIOME callers (cactus/forest/mountain), because RIVER_LEVEL (0.5) sits
	inside the PLAINS band and those three only ever place geometry in
	desert/forest/mountain. But spawn_camp_in_chunk is a fourth caller and camps are
	PLAINS-CAPABLE, so for camps this branch actually rejects — it is the whole of
	the "no village pitched mid-river" rule. The other river exclusions live in the
	plains-capable spawners: the scattered-block scatter, the four feature-structure
	builders, the crocodiles and _artifact_at.

	ponytail: like every other caller, the test is asked at the spot's CENTRE only,
	not over its `radius`. For a 1-2 m cactus that is exact; for a 9.4 m camp it
	means a village centred near a bank can still put a hut in the band (~5% of
	camps, by the measured ~8 m band width). Cosmetic — a river is a flat tint with
	no mesh — so it is left alone; the upgrade is four extra is_river_at evals at
	`radius` on the cardinals.
	"""
	var world_x := chunk_center.x + local_x
	var world_z := chunk_center.z + local_z
	if terrain.is_river_at(Vector3(world_x, 0.0, world_z)):
		return false
	# The tower's site is kept clear of everything procedural (see TOWER_RADIUS).
	# Judged with the candidate's OWN radius — the same "widest this could be"
	# number the overlap test below uses — so the thing's whole footprint stays
	# outside the disc, not merely its centre.
	if terrain.tower_excludes(world_x, world_z, radius):
		return false
	if terrain._road_lateral_distance(world_x, world_z, road_clearance) < road_clearance:
		return false
	for ob in obstacles:
		if Vector2(local_x - ob.pos.x, local_z - ob.pos.z).length() < radius + ob.radius:
			return false
	return true


static func _spawn_desert_content(terrain: Node3D, chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	DESERT — a handful of cactus stacks on an otherwise thinned-out plain.

	@param chunk_center: World centre of the chunk (positions handed to create_box
	                     are chunk-LOCAL; the biome/road questions are asked in
	                     WORLD space, so the two are converted here).
	@param rng: The biome stream's private RNG — draws here touch nothing else.
	@param obstacles: Each cactus appends one small NON-climbable footprint.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	The emptiness of a desert is NOT made here — it is made by the one-in-N skip in
	spawn_objects_in_chunk. This function only adds the thing that says "desert" at
	a glance. Crocodile density is deliberately UNCHANGED in a desert: the project
	rule is that entity counts are never trimmed, so a desert feels empty through
	decoration alone.

	A cactus is 2-3 thin tall green CYLINDERS stacked, sometimes with one short arm
	off to the side — enough silhouette to read at distance, four boxes at most.

	`BoxKind.CYLINDER` on the SEGMENTS since bead godot-test1-y1o.4: a saguaro is a
	fluted column, which is what the shared unit cylinder draws, and stacking three
	of them at one yaw reads as one trunk because the facets line up.

	THE COLLIDER FOLLOWS THE KIND AND THAT IS A REAL CHANGE, contrary to this
	bead's own note — which was written before `collision_shape_for` existed
	(bead y1o.10). A segment is `width x width` in plan, so its radial aspect is
	exactly 1.0 and it hangs a `CylinderShape3D` of radius `width * 0.5` rather
	than the old box. The shape COUNT is untouched and the collider is INSCRIBED,
	so this can only ever un-block a spot that used to be stone, and the footprint
	below is NON-CLIMBABLE, so nothing stands on the difference. It is also simply
	the right shape for a round trunk — refusing it would mean special-casing the
	desert out of the machinery the epic just built.

	THE ARM IS A CYLINDER TOO, LAID DOWN — the two quarter turns that do it are
	derived at the call site and explained there. A cube arm on round trunks was
	tried first and rendered, and it read as a square nub bolted onto a column;
	that picture is why the arm's dimensions are allowed to swap.
	"""
	var half = terrain.chunk_size / 2.0 - 3.0
	var count = rng.randi_range(CACTUS_MIN, CACTUS_MAX)
	var chunk_pos_cactus: Vector2i = terrain.world_to_chunk(chunk_center)
	var k_cactus: float = terrain.scarcity_at(chunk_center)

	for _i in count:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)
		# Rejections are `continue`s AFTER the position draws, so a rejected cactus
		# costs a spot and not a shift in this (or any) RNG sequence.
		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, CACTUS_WIDTH_MAX * 1.2, CACTUS_ROAD_CLEARANCE, obstacles):
			continue
		# Edge feathering, same rule as the forest and the mountains: the chunk
		# CENTRE chose this builder, but each cactus re-tests the biome at its OWN
		# position, so the sand dissolves into the plain along the noise contour
		# instead of stopping dead on a straight chunk seam.
		if terrain.biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != terrain.Biome.DESERT:
			continue

		var width = rng.randf_range(CACTUS_WIDTH_MIN, CACTUS_WIDTH_MAX)
		var segments := rng.randi_range(2, 3)
		var yaw := rng.randf_range(0.0, TAU)
		# Per-object scarcity, post-draw and after the three unconditional draws
		# above — the forest's rule, for the forest's reason. Before bead
		# `godot-test1-bn8` the desert read k only as the `k_cactus <= 0` bail
		# above, so a desert kept EVERY cactus right up to the 4 km line and then
		# lost the lot in one chunk: the "one rule for all" the owner asked for is
		# a gradient here, not a cliff.
		if not terrain._scarcity_keep(chunk_pos_cactus, _i, k_cactus):
			continue
		var top_y := 0.0

		for _s in segments:
			var seg_h = rng.randf_range(CACTUS_SEGMENT_MIN, CACTUS_SEGMENT_MAX)
			terrain.create_box(
				Vector3(local_x, top_y + seg_h * 0.5, local_z),
				Vector3(width, seg_h, width),
				yaw, rng, block_batch, block_body, 0.0, CACTUS_COLOR,
				true, ChunkBatch.BoxKind.CYLINDER
			)
			top_y += seg_h

		# Optional arm: a short horizontal box budding from the middle of the stack.
		if rng.randf() < CACTUS_ARM_CHANCE:
			var arm_len = width * rng.randf_range(2.0, 3.0)
			var arm_y := top_y * rng.randf_range(0.45, 0.7)
			# Push the arm out along its OWN long axis, which create_box orients with
			# Basis(UP, yaw) — that maps local +X to (cos yaw, 0, -sin yaw). Writing
			# the +sin form here rotates the offset the wrong way round, so the arm
			# gets shoved sideways instead of outwards and floats detached from the
			# trunk (worst at yaw = 45 deg, where the two are 90 deg apart).
			var arm_dir = (Basis(Vector3.UP, yaw) * Vector3.RIGHT) * (arm_len * 0.5 + width * 0.5)
			# THE ARM IS A CYLINDER LAID DOWN, and the quarter turns are the whole
			# of it (bead godot-test1-y1o.4). The unit cylinder's axis is LOCAL Y
			# while the arm's LENGTH has always been on local X, so passing CYLINDER
			# with the old dimensions draws a flat disc standing on edge — which is
			# what the first render of this bead showed, square nubs on round
			# trunks, and it looked worse than the boxes it replaced.
			#
			# `create_box` builds `Basis(UP, yaw) * Basis(RIGHT, tilt)`, so local +Y
			# comes out at `(sin yaw', 0, cos yaw')` once tilt is a quarter turn.
			# Setting `yaw' = yaw + PI/2` makes that `(cos yaw, 0, -sin yaw)` — which
			# is exactly the direction `arm_dir` above already points, because that
			# is local +X under the ORIGINAL yaw. So the drum lies along the arm.
			# The length moves into the Y slot to match, and `arm_dir` and the centre
			# are untouched: same volume, same place, same reach out of the trunk.
			#
			# NOT ONE RNG DRAW MOVED — both turns are constants and the dimensions
			# are the same two numbers in a different order (bead y1o.2's canopy
			# rule). The collider follows the kind and becomes a CylinderShape3D of
			# radius `width * 0.5` about that same axis, which is the honest shape
			# for a round limb; the shape COUNT is unchanged and the cactus footprint
			# is non-climbable, so nothing stands on the difference.
			#
			# `ponytail:` THE JOINT IS TANGENT, NOT SUNK, and that is a known
			# cosmetic ceiling rather than an oversight. `arm_dir` puts the arm's
			# inner cap plane exactly `width * 0.5` from the trunk axis — flush
			# against the flat face of a BOX trunk, but only touching a ROUND one
			# along a single line, so from a high or oblique angle a crescent of air
			# up to `width * 0.5` (0.22-0.37 m) shows at the T. The fix is one number
			# (pull `arm_dir` in by about `width * 0.25`) and it costs no RNG draw —
			# but it MOVES this entry's origin, which is more than "only the
			# silhouette changed", so it belongs to a bead that is allowed to move
			# geometry and should be judged on a render rather than on arithmetic.
			terrain.create_box(
				Vector3(local_x, arm_y, local_z) + arm_dir,
				Vector3(width, arm_len, width),
				yaw + PI * 0.5, rng, block_batch, block_body, PI * 0.5, CACTUS_COLOR,
				true, ChunkBatch.BoxKind.CYLINDER
			)

		# NOT climbable: a cactus is a thing you walk around, and a coin perched on
		# a spiky 3 m pole would be unreachable anyway (see _settle_coin_y).
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": width * 1.2, "top": top_y, "climbable": false })

	# Rare oases and dunes. Placements are deterministic on their own hash streams
	# (like artifacts/camps), so they consume zero draws from the biome RNG and
	# cacti are byte-identically placed whether oases/dunes exist or not.
	var chunk_pos: Vector2i = terrain.world_to_chunk(chunk_center)
	var oasis_data := _oasis_at(terrain, chunk_pos)
	if not oasis_data.is_empty():
		var oasis_rng := RandomNumberGenerator.new()
		oasis_rng.seed = oasis_data["seed"]
		_spawn_desert_oasis(terrain, chunk_center, chunk_pos, oasis_rng, obstacles, block_batch, block_body)

	var dune_data := _dune_at(terrain, chunk_pos)
	if not dune_data.is_empty():
		var dune_rng := RandomNumberGenerator.new()
		dune_rng.seed = dune_data["seed"]
		_spawn_desert_dunes(terrain, chunk_center, chunk_pos, dune_rng, obstacles, block_batch, block_body)


static func _spawn_desert_oasis(terrain: Node3D, chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build one desert oasis: a flat water slab, palm trees, reeds, and climbable boulders.
	Uses the split-placement pattern: this function tries OASIS_PLACE_TRIES candidates
	and picks the first one that passes _biome_spot_ok (not in river, far from road,
	no overlap with existing obstacles).
	"""
	var half = terrain.chunk_size / 2.0 - OASIS_RADIUS - 2.0
	for _try in OASIS_PLACE_TRIES:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)

		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, OASIS_RADIUS, OASIS_ROAD_CLEARANCE, obstacles):
			continue

		# Build water slab: a flat disk (visual only, collide=false)
		terrain.create_box(
			Vector3(local_x, OASIS_WATER_TOP_Y - OASIS_WATER_DEPTH * 0.5, local_z),
			Vector3(OASIS_WATER_RADIUS * 2.0, OASIS_WATER_DEPTH, OASIS_WATER_RADIUS * 2.0),
			0.0, rng, block_batch, block_body, 0.0, OASIS_WATER_COLOR, false
		)

		# Dark rim: a slightly wider ring to frame the water
		var rim_radius = OASIS_WATER_RADIUS * 1.15
		terrain.create_box(
			Vector3(local_x, OASIS_RIM_TOP_Y - OASIS_WATER_DEPTH * 0.5, local_z),
			Vector3(rim_radius * 2.0, OASIS_WATER_DEPTH, rim_radius * 2.0),
			0.0, rng, block_batch, block_body, 0.0, OASIS_WATER_RIM_COLOR, false
		)

		# Non-climbable footprint so coins don't perch on water
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": OASIS_RADIUS, "top": OASIS_WATER_TOP_Y, "climbable": false })

		# Palm trees around the oasis
		var palm_count = rng.randi_range(OASIS_PALM_MIN, OASIS_PALM_MAX)
		for _p in palm_count:
			var palm_angle := rng.randf_range(0.0, TAU)
			var palm_dist = rng.randf_range(OASIS_WATER_RADIUS * 1.15, OASIS_WATER_RADIUS * 2.0)
			var palm_x = local_x + cos(palm_angle) * palm_dist
			var palm_z = local_z + sin(palm_angle) * palm_dist

			# Keep palm within chunk bounds. The margin carries the trunk's lean now
			# (see OASIS_PALM_TILT_MAX); the drooping fronds span LESS than the old
			# flat ones did, so they did not move it.
			if absf(palm_x) > terrain.chunk_size * 0.5 - OASIS_PALM_EDGE_MARGIN or absf(palm_z) > terrain.chunk_size * 0.5 - OASIS_PALM_EDGE_MARGIN:
				continue

			var trunk_yaw := rng.randf_range(0.0, TAU)
			# Two unconditional per-palm draws: the trunk's curve and how hard this
			# palm's crown hangs.
			var palm_lean = rng.randf_range(-OASIS_PALM_TILT_MAX, OASIS_PALM_TILT_MAX)
			var droop = rng.randf_range(OASIS_PALM_DROOP_MIN, OASIS_PALM_DROOP_MAX)
			# Trunk (colliding) — `BoxKind.CYLINDER` since bead godot-test1-y1o.4.
			# The unit cylinder's axis is LOCAL Y, which is exactly the axis
			# `palm_lean` already leans, so a curved palm trunk costs nothing but
			# the kind. It is square in plan (radial aspect 1.0), so it also hangs
			# a real CylinderShape3D — the shape COUNT is unchanged, the collider
			# is inscribed, and the footprint below stays non-climbable.
			terrain.create_box(
				Vector3(palm_x, OASIS_PALM_TRUNK_HEIGHT * 0.5, palm_z),
				Vector3(OASIS_PALM_TRUNK_WIDTH, OASIS_PALM_TRUNK_HEIGHT, OASIS_PALM_TRUNK_WIDTH),
				trunk_yaw, rng, block_batch, block_body, palm_lean, Color(0.40, 0.32, 0.22),
				true, ChunkBatch.BoxKind.CYLINDER
			)

			# Fronds (visual only, collide=false) — each starts at the crown and
			# hangs outward and down, alternating how far (see the const block).
			var crown = Vector3(palm_x, OASIS_PALM_TRUNK_HEIGHT - 0.15, palm_z) \
					+ Vector3(sin(trunk_yaw), 0.0, cos(trunk_yaw)) * sin(palm_lean) * (OASIS_PALM_TRUNK_HEIGHT * 0.5)
			for _f in OASIS_PALM_FROND_COUNT:
				var flen = OASIS_PALM_FROND_WIDTH * rng.randf_range(OASIS_PALM_FROND_JITTER_MIN, 1.0)
				var frond_yaw = trunk_yaw + (TAU / OASIS_PALM_FROND_COUNT) * _f
				var f_droop = droop * (1.0 if _f % 2 == 0 else OASIS_PALM_DROOP_ALT)
				var frond_rot := Basis(Vector3.UP, frond_yaw) * Basis(Vector3.RIGHT, f_droop)
				# A FROND IS A CONE, TIP OUT (bead godot-test1-y1o.4), and getting
				# the tip pointing the right way is the whole of this edit.
				#
				# The unit cone tapers along LOCAL Y (tip at +Y), while the frond's
				# LENGTH has always been on local Z — so passing CONE with the old
				# dimensions draws a squat pyramid pointing at the sky. Two DERIVED
				# changes fix it and nothing else moves:
				#   * the length moves from the Z slot to the Y slot, so the taper
				#     runs down the frond;
				#   * the tilt gains a quarter turn, which maps local +Y onto the
				#     direction local +Z used to face — i.e. outward, along the
				#     frond, which is where the tip belongs. `frond_rot` above is
				#     unchanged and still places the CENTRE, so the frond hangs off
				#     exactly the crown point and at exactly the droop it did.
				# Both are functions of numbers already drawn: NOT ONE RNG DRAW
				# MOVED, which is bead y1o.2's canopy rule and the reason this
				# bead's A/B still reads "kind, plus these fronds' dimensions".
				# Fronds pass collide = false, so no collision shape moved either.
				terrain.create_box(
					crown + frond_rot * Vector3(0.0, 0.0, flen * 0.5),
					Vector3(0.42, flen, 0.30),
					frond_yaw, rng, block_batch, block_body, f_droop + PI * 0.5,
					OASIS_PALM_FROND_COLOR, false, ChunkBatch.BoxKind.CONE
				)

			# Small trunk footprint
			obstacles.append({ "pos": Vector3(palm_x, 0, palm_z), "radius": OASIS_PALM_TRUNK_WIDTH * 0.71, "top": OASIS_PALM_TRUNK_HEIGHT, "climbable": false })

		# Climbable boulders scattered around. The 0.8 upper bound is not taste: the ring
		# max plus OASIS_BOULDER_SIZE_MAX * 0.7 has to stay inside OASIS_RADIUS, or a
		# boulder lands outside the circle _biome_spot_ok actually cleared.
		var boulder_count = rng.randi_range(OASIS_BOULDER_MIN, OASIS_BOULDER_MAX)
		for _b in boulder_count:
			var boulder_angle := rng.randf_range(0.0, TAU)
			var boulder_dist = rng.randf_range(OASIS_WATER_RADIUS * 1.5, OASIS_RADIUS * 0.8)
			var boulder_x = local_x + cos(boulder_angle) * boulder_dist
			var boulder_z = local_z + sin(boulder_angle) * boulder_dist

			# Keep within chunk
			if absf(boulder_x) > terrain.chunk_size * 0.5 - 1.5 or absf(boulder_z) > terrain.chunk_size * 0.5 - 1.5:
				continue

			var boulder_size = rng.randf_range(OASIS_BOULDER_SIZE_MIN, OASIS_BOULDER_SIZE_MAX)
			# Climbable rocks (collide=true) — and since bead godot-test1-y1o.3 they
			# are `BoxKind.ROCK`, the one kind whose lid is flat AT the box top, so
			# the footprint appended below still records a surface you land on.
			terrain.create_box(
				Vector3(boulder_x, boulder_size * 0.5, boulder_z),
				Vector3(boulder_size, boulder_size * 0.8, boulder_size),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0,
				Color(0.55, 0.48, 0.40), true, ChunkBatch.BoxKind.ROCK
			)
			obstacles.append({ "pos": Vector3(boulder_x, 0, boulder_z), "radius": boulder_size * 0.7, "top": boulder_size * 0.8, "climbable": true })

		# Optional reed clusters around the edge
		if rng.randf() < OASIS_REED_CHANCE:
			for _r in rng.randi_range(1, 3):
				var reed_angle := rng.randf_range(0.0, TAU)
				var reed_x = local_x + cos(reed_angle) * OASIS_WATER_RADIUS * 1.05
				var reed_z = local_z + sin(reed_angle) * OASIS_WATER_RADIUS * 1.05
				# Thin visual-only reeds (collide=false)
				terrain.create_box(
					Vector3(reed_x, 1.0, reed_z),
					Vector3(0.3, 2.0, 0.3),
					rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0,
					Color(0.35, 0.45, 0.25), false
				)

		# Success — one oasis placed
		return


static func _spawn_desert_dunes(terrain: Node3D, chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build sand dunes: low, wide, climbable mounds (~1.5 m max height). Same split-placement
	pattern as oases: DUNE_PLACE_TRIES candidates, pick the first that passes spot checks.

	THE DUNE STAYS TWO CUBES, and bead godot-test1-y1o.4 asked for that decision
	rather than assuming it: "a flattened SPHERE for the LOWER tier ONLY IF the top
	tier keeps a CUBE-collided flat top the coin/climb rule needs, else leave dunes
	as they are and say so". The gameplay half of the condition passes — the top
	tier is a separate entry and would have kept its cube and its `BoxShape3D` flat
	top at `height`, which is what the climbable footprint and `_settle_coin_y`
	promise. It was BUILT that way, rendered, and refused ON THE PICTURE:

	  A dune is 6-12 m wide and each tier is only 0.4-0.75 m tall, so an inscribed
	  sphere there is not a mound but a LENS ~1/16th as tall as it is wide. Its
	  surface has already fallen most of the way to the ground by the time it
	  reaches the top tier's footprint (at the upper cube's own half-width the lens
	  is 0.13 m below that cube's flat base), so the square top tier visibly
	  OVERHANGS into open air on all four sides — a slab balanced on a saucer. Two
	  honest cubes read better than that.

	The two ways to make a real dune both move geometry, which is not this bead's
	to move: give the lower tier the height a hemisphere needs (changing dimensions
	the A/B is written against), or draw the whole dune as ONE squashed sphere and
	give up the flat cube top the climb contract rests on. `ponytail:` if a rounded
	dune is wanted, that is its own bead and it starts by choosing which of those
	two costs is acceptable.
	"""
	var half = terrain.chunk_size / 2.0 - DUNE_WIDTH_MAX * 0.71
	for _try in DUNE_PLACE_TRIES:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)

		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, DUNE_WIDTH_MAX * 0.71, DUNE_ROAD_CLEARANCE, obstacles):
			continue

		# Pick dune height and width
		var height = rng.randf_range(DUNE_HEIGHT_MIN, DUNE_HEIGHT_MAX)
		var width = rng.randf_range(DUNE_WIDTH_MIN, DUNE_WIDTH_MAX)

		# Build dune as a slightly tapered stack (wider at base, narrower at top)
		var layer_height = height / 2.0  # two layers
		var base_width = width
		var top_width = width * 0.75
		var color = DUNE_COLOR_A.lerp(DUNE_COLOR_B, rng.randf())

		# Base layer (wider). STILL A CUBE — see the docstring.
		terrain.create_box(
			Vector3(local_x, layer_height * 0.5, local_z),
			Vector3(base_width, layer_height, base_width),
			rng.randf_range(0.0, 0.3), rng, block_batch, block_body, 0.0, color
		)

		# Top layer (narrower, for taper)
		terrain.create_box(
			Vector3(local_x, layer_height + layer_height * 0.5, local_z),
			Vector3(top_width, layer_height, top_width),
			rng.randf_range(0.0, 0.3), rng, block_batch, block_body, 0.0, color
		)

		# Climbable footprint (slightly conservative to stay within chunk)
		var footprint_radius = width * 0.5
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": footprint_radius, "top": height, "climbable": true })

		# Success — one dune placed
		return


static func _spawn_forest_content(terrain: Node3D, chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	FOREST — many simple trees: one solid trunk BOX plus a stack of visual-only
	canopy BLOBS (bead godot-test1-y1o.2 — the canopy layers are the world's first
	non-cube batch entries; see the TREE_CANOPY_BLOB_* block above).

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One NON-climbable footprint per trunk.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	PERF (the reason a forest is affordable at all): 25-40 trees × ~4 boxes are all
	create_box entries, so a forest chunk is TWO block draw calls — the cube bucket
	(trunks) and the sphere bucket (canopies) — against a plains chunk's one. That
	+1 is the whole cost of this restyle and it is paid by forest chunks ALONE:
	every other biome and every Budapest chunk passes no kind and emits exactly the
	one node it always did (batch_selfcheck check 5 sweeps the biomes for it,
	budapest_selfcheck check 4 the city). The box COUNT is unchanged — the same
	create_box calls in the same order. Only the trunks pay a CollisionShape3D: the
	canopies pass collide = false, which is exactly why that parameter exists (and
	is also the rule a non-cube kind has to obey, since a shape carries no kind).
	Leaves you can walk under cost nothing but instances.

	EDGE FEATHERING: each tree re-tests biome_at at ITS OWN position, not just the
	chunk centre's. Without that, a forest would stop dead along a straight chunk
	seam; with it, the tree line follows the noise contour and the wood dissolves
	into the plain the way a real one does. One extra noise eval per candidate.
	"""
	# Canopy slabs are yawed, so the half-DIAGONAL is what has to stay inside the
	# chunk (same reasoning as MOUNTAIN_EDGE_MARGIN). A flat 2.0 m margin left the
	# widest canopy poking 0.4 m past the seam, where it would vanish with its own
	# chunk while the neighbour still renders.
	#
	# The lean added by TREE_TRUNK_TILT_MAX slides the canopy sideways along the
	# trunk's own axis, so the margin now carries that offset too. It is written as
	# the arithmetic rather than a number: the highest canopy centre sits about
	# three layer-heights above the trunk's mid-point, and sin(lean) times that is
	# how far it can travel. Retune the lean or the layer height and this follows.
	#
	# STILL AN OVER-ESTIMATE after y1o.2 made the layers blobs: the tallest crown
	# this builder can draw puts its top blob's centre 4.3 m over the trunk's
	# mid-point against the 4.9 m below, and a sphere inscribed in the same box
	# reaches LESS far sideways than the slab did. prop_selfcheck check 10 measures
	# the real reach against the real seam either way, which is what would catch a
	# retune that broke the estimate rather than this comment.
	var lean_reach = sin(TREE_TRUNK_TILT_MAX) * (TREE_TRUNK_HEIGHT_MAX * 0.5 + TREE_CANOPY_LAYER_HEIGHT * 3.0)
	var widest_layer = TREE_CANOPY_WIDTH_MAX * TREE_CANOPY_WIDTH_JITTER_MAX
	var half = terrain.chunk_size / 2.0 - (widest_layer * (0.71 + TREE_CANOPY_SLIDE) + lean_reach)
	var count = rng.randi_range(FOREST_TREES_MIN, FOREST_TREES_MAX)
	var chunk_pos_forest: Vector2i = terrain.world_to_chunk(chunk_center)
	var k_forest: float = terrain.scarcity_at(chunk_center)

	for _i in count:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)
		var world_x := chunk_center.x + local_x
		var world_z := chunk_center.z + local_z
		# Both rejections are post-draw `continue`s (see _spawn_desert_content).
		# The radius is the widest a TRUNK can be — the canopy is visual-only, and
		# leaves brushing a nearby block is exactly what a real wood looks like.
		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, TREE_TRUNK_WIDTH_MAX * 0.71 + 0.3, FOREST_ROAD_CLEARANCE, obstacles):
			continue
		if terrain.biome_at(world_x, world_z) != terrain.Biome.FOREST:
			continue

		var trunk_w = rng.randf_range(TREE_TRUNK_WIDTH_MIN, TREE_TRUNK_WIDTH_MAX)
		var trunk_h = rng.randf_range(TREE_TRUNK_HEIGHT_MIN, TREE_TRUNK_HEIGHT_MAX)
		var yaw := rng.randf_range(0.0, TAU)
		# The two anti-Minecraft per-tree draws, taken UNCONDITIONALLY and in a fixed
		# order right here — above the scarcity roll, so a thinned tree cannot make
		# the stream depend on the roll's branch. `leaf_t` mixes this tree's foliage
		# somewhere along TREE_LEAF_COLOR -> TREE_LEAF_COLOR_WARM (no two trees the
		# same green); `lean` is the trunk's tilt.
		var leaf_t := rng.randf()
		var lean = rng.randf_range(-TREE_TRUNK_TILT_MAX, TREE_TRUNK_TILT_MAX)
		if not terrain._scarcity_keep(chunk_pos_forest, _i, k_forest):
			continue

		# Trunk: solid, so you bump into it and crocodiles' raycasts see it.
		terrain.create_box(
			Vector3(local_x, trunk_h * 0.5, local_z),
			Vector3(trunk_w, trunk_h, trunk_w),
			yaw, rng, block_batch, block_body, lean, TREE_TRUNK_COLOR
		)

		# Canopy: 2-3 shrinking slabs stacked from just below the trunk top, each
		# VISUAL ONLY (collide = false) — you walk under a tree, not into its leaves.
		#
		# THE CANOPY RIDES THE LEANING TRUNK. create_box's tilt is Basis(UP, yaw) *
		# Basis(RIGHT, lean), which tips the box's local +Y toward its local +Z — so
		# the trunk's axis drifts along the world direction of that local +Z,
		# (sin yaw, 0, cos yaw), by sin(lean) per metre above the trunk box's CENTRE.
		# Leaving the canopy on the vertical would hang the crown off the side of a
		# leaning trunk, which is the one way this could look worse than a cube.
		var lean_dir := Vector3(sin(yaw), 0.0, cos(yaw)) * sin(lean)
		var layers = rng.randi_range(TREE_CANOPY_LAYERS_MIN, TREE_CANOPY_LAYERS_MAX)
		var canopy_w = rng.randf_range(TREE_CANOPY_WIDTH_MIN, TREE_CANOPY_WIDTH_MAX)
		# `canopy_y` is the crown's FOOT, not a layer centre: a blob is up to 2.5 m
		# tall where u7a's slab was 1.0, so centring one here would hang the leaves
		# of a fat crown down past a short trunk's head height. Still dipped
		# TREE_CANOPY_LAYER_HEIGHT * 0.3 into the trunk top so no gap shows.
		var canopy_y = trunk_h - TREE_CANOPY_LAYER_HEIGHT * 0.3
		var leaf_base = TREE_LEAF_COLOR.lerp(TREE_LEAF_COLOR_WARM, leaf_t)
		for _l in layers:
			# One draw per layer, so no two layers of one tree are the same width —
			# the taper alone made every tree the same tapering stack.
			var w = canopy_w * rng.randf_range(TREE_CANOPY_WIDTH_JITTER_MIN, TREE_CANOPY_WIDTH_JITTER_MAX)
			# Both DERIVED from the width just drawn, so neither costs an rng draw
			# and neither can move a spawn — the whole reason this bead's diff
			# against master is `kind` plus these dimensions and nothing else.
			var blob_h = w * TREE_CANOPY_BLOB_HEIGHT
			var mid_y = canopy_y + blob_h * 0.5
			# Crown lift: the top of a real canopy catches the light. Derived from
			# the layer INDEX, so it costs no draw.
			var crown := 0.0 if layers <= 1 else float(_l) / float(layers - 1)
			var layer_yaw = yaw + TREE_CANOPY_YAW_STEP * float(_l)
			# THE LAST TWO ARE FREE — both derived from values already drawn, so
			# neither costs an rng draw and neither can move a spawn. A flat-topped
			# stack of level slabs is the shape that still read as a cube once the
			# colours and the yaw were fixed, so each layer PITCHES (alternating
			# sign, magnitude off this tree's own leaf_t) and SLIDES off the trunk
			# axis along its own yaw. Both bounded by the constants, both measured
			# by prop_selfcheck's forest seam clause.
			var layer_tilt = TREE_CANOPY_TILT_MAX * (0.4 + 0.6 * leaf_t) * (1.0 if _l % 2 == 0 else -1.0)
			var slide = Vector3(sin(layer_yaw), 0.0, cos(layer_yaw)) * (w * TREE_CANOPY_SLIDE * crown)
			# BoxKind.SPHERE, and the trunk above deliberately stays a CUBE: the
			# unit sphere is inscribed in the unit cube, so `dimensions` still means
			# this blob's BOUNDING BOX and every reach/seam bound in this file and
			# in prop_selfcheck stays the over-estimate it always was. A canopy is
			# also already collide = false, which is the rule ChunkBatch's BoxKind
			# banner asks of a non-cube kind (its collision shape would still be a
			# box). The plan stays a RECTANGLE (TREE_CANOPY_DEPTH_RATIO), so the
			# blobs are squashed ellipsoids the yaw step still turns visibly —
			# a stack of perfect spheres is rotationally symmetric and reads as one
			# smooth ball.
			terrain.create_box(
				Vector3(local_x, mid_y, local_z) + lean_dir * (mid_y - trunk_h * 0.5) + slide,
				Vector3(w, blob_h, w * TREE_CANOPY_DEPTH_RATIO),
				layer_yaw, rng, block_batch, block_body, layer_tilt,
				leaf_base.lerp(TREE_LEAF_COLOR_WARM, crown * TREE_LEAF_CROWN_LIFT), false,
				ChunkBatch.BoxKind.SPHERE
			)
			canopy_y += blob_h * TREE_CANOPY_BLOB_OVERLAP
			canopy_w *= TREE_CANOPY_TAPER

		# Footprint stops at the TRUNK top, and is NOT climbable, on purpose: a
		# climbable footprint would let _settle_coin_y perch a road coin on the
		# obstacle's `top`, and with the canopy height that coin would float 5 m up
		# a tree where nobody can reach it. Non-climbable means such a coin is
		# SKIPPED instead. Crocodiles read the same footprint and steer around the
		# trunk.
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": trunk_w * 0.71 + 0.3, "top": trunk_h, "climbable": false })


static func _spawn_mountain_content(terrain: Node3D, chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	MOUNTAIN — 2-4 impassable massifs, each a stack of progressively smaller boxes.

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One NON-climbable footprint per massif, with its real height.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	THE FLAT-WORLD INVARIANT IS WHY THIS EXISTS AT ALL: the ground stays a flat
	y = 0 plane (see the ponytail note in the BIOME FIELD CONFIGURATION block), so a
	mountain is not raised terrain — it is a pile of ordinary blocks, 8-20 m tall
	and several metres wide, that you walk AROUND. It rides the chunk's single
	MultiMesh and single collision body like everything else.

	THE ROAD IS NEVER BLOCKED: every massif must sit at least
	MOUNTAIN_ROAD_CLEARANCE from the coin-road centerline. That one rule is what
	carves a canyon through a range for free — the peaks refuse to stand near the
	road, so the road threads between them and stays followable.

	Per layer the box is narrower, a touch shorter, randomly yawed and laterally
	jittered, so a massif reads as a crude rocky peak rather than a wedding cake.
	"""
	var half = terrain.chunk_size / 2.0 - MOUNTAIN_EDGE_MARGIN
	var count = rng.randi_range(MOUNTAIN_MASSIF_MIN, MOUNTAIN_MASSIF_MAX)

	# MASSIFS ARE EXEMPT FROM THE SCARCITY GRADIENT — owner ruling 2026-09-04, bead
	# `godot-test1-bn8`, and the ONE builder in this file with no k in it at all.
	# Everything else the world draws is decoration and thins to plain terrain at
	# 4 km; a massif is not decoration, it is the impassable wall the flat-world
	# invariant substitutes for raised terrain (see the docstring above). Thinned,
	# a mountain band 4 km out is a plains band painted grey, and the "you walk
	# AROUND a mountain" contract quietly stops existing exactly where the player
	# is least likely to report it. This used to read `k_mtn = scarcity_at(...)`
	# plus a per-massif post-draw roll; both are deliberately gone, and
	# `scarcity_selfcheck` asserts the far mountain band still builds stone while
	# every other family in the same chunks builds none.

	# Massifs are NOT checked against the whole `obstacles` list. A massif's
	# footprint radius is ~9.7 m, so demanding clearance from all dozen scattered
	# blocks would cover the entire chunk and mountains would essentially stop
	# generating. Overlapping a scattered block is also harmless — the block ends up
	# INSIDE the rock, invisible, at worst reading as a boulder at the foot of the
	# flank.
	#
	# What DOES matter goes in this list: every massif placed so far (without it,
	# 2-4 peaks drawn from the same box merge into one lumpy blob), plus anything
	# already in the chunk too big to be a scattered block — in practice an artifact
	# or a feature structure. Burying an artifact hides its emissive accents, its
	# coin ring and the one guaranteed gem that is its whole reward, and that is
	# cheap to avoid: see MOUNTAIN_AVOID_RADIUS.
	# ...and so does anything TALL enough to be climbed onto the massif from (see
	# MOUNTAIN_AVOID_TOP) — a block tower is narrow but it is still a staircase.
	#
	# ...and so does anything a PATROL CROCODILE is going to be dropped onto, which
	# is what the `guarded` key marks (spawn_wall's blocks and the log bridge's
	# stone). This third clause closes the one hazard CLAUDE.md recorded as
	# deliberately unfired: a wall block's footprint is only block_size * 0.71 =
	# 1.14-1.70 m wide and a doubled section tops out at 2 * block_size = 3.2 m, so
	# BOTH of the tests above miss it (radius < MOUNTAIN_AVOID_RADIUS 2.0, top <
	# MOUNTAIN_AVOID_TOP 3.61) and a massif was free to grow straight over a ridge,
	# burying the guard in rock the platform descriptor knows nothing about. It went
	# unfired through 4 x 289 chunks — and then fired the moment the snow band's
	# threshold retune reshuffled the field, at 1.14 m deep, caught by
	# enemy_spawn_selfcheck.gd's check 1 exactly as that note predicted it would be.
	# The mound needs no marking: its footprint radius is base_size * 0.71 >= 5.68,
	# so the first clause has always covered it.
	var avoid: Array = []
	for ob in obstacles:
		if ob.radius >= MOUNTAIN_AVOID_RADIUS or ob.top >= MOUNTAIN_AVOID_TOP or ob.get("guarded", false):
			avoid.append(ob)

	for _i in count:
		# Try a few spots; take the first that clears the road, the river and is
		# still inside the mountain band at its OWN position (edge feathering, same
		# as the forest). Every draw happens whether or not a try is accepted.
		var local_x := 0.0
		var local_z := 0.0
		var placed := false
		var tries := 0
		while tries < MOUNTAIN_PLACE_TRIES and not placed:
			tries += 1
			local_x = rng.randf_range(-half, half)
			local_z = rng.randf_range(-half, half)
			var wx := chunk_center.x + local_x
			var wz := chunk_center.z + local_z
			# MOUNTAIN_BASE_WIDTH_MAX is the widest base that could be drawn below —
			# the real width is drawn after this test, and reordering the draws to
			# know it exactly would shift the biome stream for nothing.
			if _biome_spot_ok(terrain, chunk_center, local_x, local_z, MOUNTAIN_BASE_WIDTH_MAX * 0.71 + MOUNTAIN_LAYER_JITTER, MOUNTAIN_ROAD_CLEARANCE, avoid) \
					and terrain.biome_at(wx, wz) == terrain.Biome.MOUNTAIN:
				placed = true
		if not placed:
			continue

		var height = rng.randf_range(MOUNTAIN_HEIGHT_MIN, MOUNTAIN_HEIGHT_MAX)
		var base_w = rng.randf_range(MOUNTAIN_BASE_WIDTH_MIN, MOUNTAIN_BASE_WIDTH_MAX)
		# (No scarcity roll here — massifs are exempt; see the note above `avoid`.)
		# The layer count falls straight out of the height: every step must be too
		# tall to jump onto. Without that rule an 8 m massif split into 7 layers is
		# a 1.14 m staircase with a 1.7 m ledge at each level — a walkable ziggurat,
		# which would break the "impassable, you go around" contract that the whole
		# mountains-as-blocks design rests on under the flat-world invariant. With
		# heights of 8-20 m this gives 2-5 layers.
		var layers = maxi(2, int(height / MOUNTAIN_MIN_LAYER_HEIGHT))
		var snowy = height >= MOUNTAIN_SNOW_HEIGHT
		# Index of the first snow layer. Always leaves at least one rock layer
		# showing: a 14-15.9 m massif gets exactly 3 layers, and a flat
		# "top MOUNTAIN_SNOW_LAYERS" rule would paint 2 of those 3 white, so the
		# peak read as a snow pillar rather than rock wearing a cap.
		var snow_from = maxi(1, layers - MOUNTAIN_SNOW_LAYERS)
		var layer_h = height / float(layers)

		var width = base_w
		var y := 0.0
		for layer_index in layers:
			# The top boxes of a tall massif are forced white: a snow cap is the
			# cheapest possible "this one is high" signal.
			var is_snow = snowy and layer_index >= snow_from
			var color: Color = MOUNTAIN_SNOW_COLOR if is_snow else MOUNTAIN_ROCK_A.lerp(MOUNTAIN_ROCK_B, rng.randf())
			var jitter_x = rng.randf_range(-MOUNTAIN_LAYER_JITTER, MOUNTAIN_LAYER_JITTER)
			var jitter_z = rng.randf_range(-MOUNTAIN_LAYER_JITTER, MOUNTAIN_LAYER_JITTER)
			terrain.create_box(
				Vector3(local_x + jitter_x, y + layer_h * 0.5, local_z + jitter_z),
				Vector3(width, layer_h, width),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, color
			)
			y += layer_h
			width *= MOUNTAIN_LAYER_TAPER

		# One footprint for the whole massif, NOT climbable and carrying the real
		# top height: crocodiles avoid it, and a road coin that would otherwise be
		# perched 15 m up a peak is skipped instead (see _settle_coin_y). It goes
		# into `avoid` too, so the next massif keeps its distance from it.
		var footprint = { "pos": Vector3(local_x, 0, local_z), "radius": base_w * 0.71 + MOUNTAIN_LAYER_JITTER, "top": height, "climbable": false }
		obstacles.append(footprint)
		avoid.append(footprint)


static func _spawn_city_content(terrain: Node3D, chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	CITY — small flat-roofed houses, market stalls under awnings, and traffic
	signals / lamp posts along the street lines.

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One footprint per building — CLIMBABLE for houses (see
	                  below), non-climbable for stalls and street furniture.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	EVERY HOUSE ROOF IS A REST SPOT, and since bead godot-test1-y1o.36 that is
	literal: the WEDGE roof COLLIDES, so you land on its eave (flush with the hull
	top — `CITY_HOUSE_HEIGHT_MAX` is `PROP_MAX_STEP` (2.6), one jump from the
	pavement) and walk up the pitch to the ridge, which is where the footprint's
	`top` is recorded and where `_settle_coin_y` perches a road coin. That makes a
	house TWO collision shapes, hull and roof, and it is the only thing in the band
	that is more than one. Every other biome's content is non-climbable — the city
	is the one that gives the bare cubes' role back at scale.

	CROC DENSITY IS REDUCED HERE and it is the ONE band where that is true; the
	division lives in spawn_crocodiles_in_chunk (see CITY_CROC_DIVISOR), not here.

	THE STREET READ COSTS TWO LINES, and there is deliberately NO road network:
	candidate positions are snapped to a coarse CITY_BLOCK_PITCH grid with jitter,
	and house yaws are quantised to quarter turns. Parallel facades along shared
	lines is what reads as a town. See the CITY banner in SECTION 1.

	EDGE FEATHERING: like the forest and the mountains, every candidate re-tests
	biome_at at ITS OWN position, so a city dissolves into the plain along the
	noise contour instead of stopping dead on a chunk seam.

	PERF: everything here is a create_box entry, so the band still costs NO node
	per object; only hulls, ROOFS, counters and masts pay a CollisionShape3D, and there
	are ZERO emissive accent nodes — lamps are bright albedo entries in the batch.
	Since bead godot-test1-y1o.5 a city-band chunk is no longer ONE block draw
	call, though: the wedge roofs and the cylinder masts are two more buckets in
	`ChunkBatch._build_block_multimesh`, which is what `batch_selfcheck` check 5's
	per-biome cap is for. That is the cost the pitched roof is bought with.
	"""
	var half = terrain.chunk_size / 2.0 - CITY_HOUSE_RADIUS_MAX
	var chunk_pos_city: Vector2i = terrain.world_to_chunk(chunk_center)
	var k_city: float = terrain.scarcity_at(chunk_center)

	# ---- HOUSES ------------------------------------------------------------
	for _i in rng.randi_range(CITY_HOUSE_TRIES_MIN, CITY_HOUSE_TRIES_MAX):
		var local_x := _city_snap(terrain, rng.randf_range(-half, half), rng)
		var local_z := _city_snap(terrain, rng.randf_range(-half, half), rng)
		# Quarter-turn yaw plus a little slop: facades line up along the grid.
		var yaw := float(rng.randi_range(0, 3)) * (PI * 0.5) + rng.randf_range(-0.08, 0.08)
		var width = rng.randf_range(CITY_HOUSE_WIDTH_MIN, CITY_HOUSE_WIDTH_MAX)
		var depth = width * rng.randf_range(CITY_HOUSE_DEPTH_FACTOR_MIN, CITY_HOUSE_DEPTH_FACTOR_MAX)
		var height = rng.randf_range(CITY_HOUSE_HEIGHT_MIN, CITY_HOUSE_HEIGHT_MAX)
		var wall = terrain.CITY_PLASTER_A.lerp(terrain.CITY_PLASTER_B, rng.randf())
		var roof = terrain.CITY_ROOF_TILE if rng.randf() < 0.6 else terrain.CITY_ROOF_SLATE
		var windows := rng.randi_range(1, 2)
		# Per-object scarcity: own hash stream, post-draw skip so k=1 stays identical.
		if not terrain._scarcity_keep(chunk_pos_city, _i, k_city):
			continue
		# The snap can push a candidate back outside the margin, so clamp rather
		# than redraw — a redraw would be a draw, and every rejection in this file
		# is a post-draw `continue` for exactly that reason.
		local_x = clampf(local_x, -half, half)
		local_z = clampf(local_z, -half, half)
		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, CITY_HOUSE_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if terrain.biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != terrain.Biome.CITY:
			continue

		var local := Vector3(local_x, 0.0, local_z)
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		var front := Vector3(-sin(yaw), 0.0, cos(yaw))

		# Hull: the ONLY colliding box, and the one whose top face the footprint
		# names. Untilted, full size, centred — the climbability contract.
		terrain.create_box(
			local + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth),
			yaw, rng, block_batch, block_body, 0.0, wall
		)

		# Roof: a PITCHED wedge over the hull top, and SOLID since bead
		# godot-test1-y1o.36 (owner ruling 2026-09-05, "make roofs standable"). It
		# used to be `collide = false` trim over the hull's flat top, which meant
		# the band's advertised rest spot put the hero INSIDE the pitch. Now
		# `ChunkBatch.collision_shape_for` gives a WEDGE a ConvexPolygonShape3D of
		# the drawn prism, so you land on the eave — flush with the hull top,
		# oversailing the wall by CITY_ROOF_EAVES — and walk up the slope.
		#
		# IT IS THE HOUSE'S SECOND COLLIDER AND THE ONLY ONE, so a building is two
		# shapes and not one; `prop_selfcheck` check 7 counts it as
		# `footprints + climbable` rather than loosening to a bound.
		#
		# THE RIDGE RUNS ALONG LOCAL X, which is the house's `width` — so a house
		# is gabled on its narrow ends and the slopes face the long walls, the way
		# a terrace is. `dimensions.z` is what the pitch is measured over, hence
		# the rise coming off the roofed DEPTH (see CITY_ROOF_RISE_FACTOR).
		var roof_d = depth + CITY_ROOF_EAVES * 2.0
		var roof_rise = roof_d * CITY_ROOF_RISE_FACTOR
		terrain.create_box(
			local + Vector3(0.0, height + roof_rise * 0.5, 0.0),
			Vector3(width + CITY_ROOF_EAVES * 2.0, roof_rise, roof_d),
			yaw, rng, block_batch, block_body, 0.0, roof, true,
			ChunkBatch.BoxKind.WEDGE
		)

		# Door, on the front face. Visual only — it is inside the hull's own
		# collision box, so making it solid would buy nothing but a snag.
		var door_h = height * 0.62
		terrain.create_box(
			local + front * (depth * 0.5) + Vector3(0.0, door_h * 0.5, 0.0),
			Vector3(width * 0.24, door_h, 0.10), yaw,
			rng, block_batch, block_body, 0.0, terrain.PROP_CRATE, false
		)

		# Windows, spread SYMMETRICALLY about the door and sitting ABOVE its head.
		# Both halves of that matter and both were wrong: a `+ width * 0.26` bias
		# used to push the whole run onto one side (a two-window facade came out
		# lopsided with a blank wall opposite), and at `height * 0.62` the inner
		# window's box spanned the door's own box — same front face, same local Z
		# extent, same yaw, so the two were exactly COPLANAR and z-fought in the
		# chunk's one MultiMesh. Door head is 0.62h and the window is 0.22h tall,
		# so 0.78h clears it for every window count, centred one included.
		for w in windows:
			var offset = (float(w) - float(windows - 1) * 0.5) * width * 0.32
			terrain.create_box(
				local + front * (depth * 0.5) + right * offset
						+ Vector3(0.0, height * 0.78, 0.0),
				Vector3(width * 0.16, height * 0.22, 0.10), yaw,
				rng, block_batch, block_body, 0.0, terrain.CITY_ROOF_SLATE, false
			)

		# ONE circle per house, CLIMBABLE, with THE RIDGE as its height (bead
		# godot-test1-y1o.36 — it was the hull top while the roof was trim). `top`
		# is the highest SOLID point over the footprint's own centre column, which
		# is what `_settle_coin_y` perches a coin on: with the roof solid, the hull
		# top is inside stone, so a coin recorded there is buried in the roof and
		# unreachable. The ridge line runs along local X straight through this
		# centre, so a coin on the centre column stands ON the ridge.
		#
		# AND HERE IS WHAT THAT COSTS, because `top` is a SCALAR over a DISC and a
		# ridge is a LINE. `_settle_coin_y` perches every column the footprint
		# covers at the ridge height, so a coin displaced along local Z FLOATS
		# `2 * CITY_ROOF_RISE_FACTOR * |dz|` over the pitch beneath it — up to the
		# full rise at the eave, and up to `ridge + COIN_BLOCK_OFFSET` over bare
		# ground out in the annulus between the roof edge and the footprint's
		# radius. Before this bead every such coin sat 0.6 m over the walkable hull
		# top. It is still COLLECTIBLE (the pickup radius plus a 2 m capsule
		# standing on the pitch reaches it) and the alternative buries it in stone,
		# so the ridge is the right answer — but it is a real cost and not a
		# rounding one. The only live consumer is the geo-landmark reward ring,
		# which has no biome exclusion and runs after biome content; road coins
		# cannot reach a house at all (CITY_ROAD_CLEARANCE 13 m against a 3.47 m
		# radius). A per-column perch would mean `obstacles` carrying a shape
		# instead of a top, which is the footprint currency's whole simplicity.
		#
		# THE JUMP IS STILL MEASURED AT THE EAVE, not here. `PROP_MAX_STEP` asks
		# "can this be mounted from flat ground", and what you land on is the eave
		# — flush with `height`, which `CITY_HOUSE_HEIGHT_MAX` caps at exactly
		# PROP_MAX_STEP. The ridge is above that on purpose and is reached by
		# WALKING, which is the whole of the ruling; check 7 asserts both halves.
		#
		# The radius is the honest bound on the roof slab's rotated half-diagonal, so
		# it is above MOUNTAIN_AVOID_RADIUS (2.0) — deliberately, see the constant.
		obstacles.append({
			"pos": local,
			"radius": 0.5 * sqrt(pow(width + CITY_ROOF_EAVES * 2.0, 2.0) + pow(depth + CITY_ROOF_EAVES * 2.0, 2.0)),
			"top": height + roof_rise,
			"climbable": true,
		})

	# ---- MARKET STALLS -----------------------------------------------------
	for _i in rng.randi_range(CITY_STALL_TRIES_MIN, CITY_STALL_TRIES_MAX):
		var sx := _city_snap(terrain, rng.randf_range(-half, half), rng)
		var sz := _city_snap(terrain, rng.randf_range(-half, half), rng)
		var syaw := float(rng.randi_range(0, 3)) * (PI * 0.5) + rng.randf_range(-0.15, 0.15)
		var sw = rng.randf_range(CITY_STALL_WIDTH_MIN, CITY_STALL_WIDTH_MAX)
		var canvas = terrain.CITY_ROOF_TILE if rng.randf() < 0.5 else terrain.CITY_ROOF_SLATE
		# Per-object scarcity for stalls (offset 1000 to decorrelate from houses).
		if not terrain._scarcity_keep(chunk_pos_city, _i + 1000, k_city):
			continue
		sx = clampf(sx, -half, half)
		sz = clampf(sz, -half, half)
		if not _biome_spot_ok(terrain, chunk_center, sx, sz, CITY_STALL_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if terrain.biome_at(chunk_center.x + sx, chunk_center.z + sz) != terrain.Biome.CITY:
			continue

		var s_local := Vector3(sx, 0.0, sz)
		var s_right := Vector3(cos(syaw), 0.0, sin(syaw))

		# Counter — solid, so you bump into it and the crocodiles' raycasts see it.
		terrain.create_box(
			s_local + Vector3(0.0, CITY_STALL_COUNTER_HEIGHT * 0.5, 0.0),
			Vector3(sw, CITY_STALL_COUNTER_HEIGHT, sw * 0.5), syaw,
			rng, block_batch, block_body, 0.0, terrain.PROP_CRATE
		)
		# Awning + its two posts — all visual, you walk under a stall.
		terrain.create_box(
			s_local + Vector3(0.0, CITY_STALL_AWNING_HEIGHT, 0.0),
			Vector3(sw * 1.25, 0.12, sw * 0.85), syaw,
			rng, block_batch, block_body, rng.randf_range(-0.14, 0.14), canvas, false
		)
		for p in 2:
			var s := 1.0 if p == 0 else -1.0
			terrain.create_box(
				s_local + s_right * (sw * 0.5 * s) + Vector3(0.0, CITY_STALL_AWNING_HEIGHT * 0.5, 0.0),
				Vector3(0.10, CITY_STALL_AWNING_HEIGHT, 0.10), syaw,
				rng, block_batch, block_body, 0.0, terrain.CITY_METAL, false
			)
		# NON-climbable: the awning hangs over the counter, so a road coin perched
		# on it would sit inside canvas. Skipped is the right answer.
		obstacles.append({
			"pos": s_local,
			"radius": sw * 0.68,
			"top": CITY_STALL_COUNTER_HEIGHT,
			"climbable": false,
		})

	# ---- TRAFFIC SIGNALS / LAMP POSTS --------------------------------------
	for _i in rng.randi_range(CITY_LIGHT_TRIES_MIN, CITY_LIGHT_TRIES_MAX):
		var lx := _city_snap(terrain, rng.randf_range(-half, half), rng)
		var lz := _city_snap(terrain, rng.randf_range(-half, half), rng)
		var lyaw := float(rng.randi_range(0, 3)) * (PI * 0.5)
		var lh = rng.randf_range(CITY_LIGHT_HEIGHT_MIN, CITY_LIGHT_HEIGHT_MAX)
		var is_signal = rng.randf() < CITY_SIGNAL_CHANCE
		# Per-object scarcity for lights (offset 2000).
		if not terrain._scarcity_keep(chunk_pos_city, _i + 2000, k_city):
			continue
		lx = clampf(lx, -half, half)
		lz = clampf(lz, -half, half)
		if not _biome_spot_ok(terrain, chunk_center, lx, lz, CITY_LIGHT_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if terrain.biome_at(chunk_center.x + lx, chunk_center.z + lz) != terrain.Biome.CITY:
			continue

		var l_local := Vector3(lx, 0.0, lz)
		var l_front := Vector3(-sin(lyaw), 0.0, cos(lyaw))

		# Mast — the one colliding box, and a `BoxKind.CYLINDER` since bead
		# godot-test1-y1o.5: a pole is the shape a cylinder IS, and the entry is
		# already square in plan so this is a pure kind flip with not one
		# dimension moved. Its collider follows the kind (a `CylinderShape3D` of
		# the inscribed radius, `ChunkBatch.collision_shape_for`'s designed
		# behaviour) — same shape COUNT, and a round pole is what you were
		# bumping into anyway.
		terrain.create_box(
			l_local + Vector3(0.0, lh * 0.5, 0.0),
			Vector3(CITY_LIGHT_MAST_WIDTH, lh, CITY_LIGHT_MAST_WIDTH), lyaw,
			rng, block_batch, block_body, 0.0, terrain.CITY_METAL, true,
			ChunkBatch.BoxKind.CYLINDER
		)

		if is_signal:
			# Head + the three-lamp stack. The stack IS the silhouette that says
			# "traffic light" at 30 m, which is why the three lamp colours are the
			# only colours the city palette spends on furniture. BRIGHT ALBEDO,
			# never emissive: this is one MultiMesh instance each, not a node.
			#
			# THE HEAD AND THE LENSES STAY CUBES, and that is bead y1o.5's one
			# deliberate departure from its own sketch ("lamp heads -> SPHERE").
			# Two reasons, and the second is the load-bearing one: a signal head
			# IS a box in the world, so a ball on a pole would be less like a
			# traffic light and not more; and a SPHERE here is a whole extra
			# MultiMeshInstance3D on every city-band chunk (see the KIND_CAP
			# table in batch_selfcheck) bought for a 0.22 m object nobody looks
			# at. The mast and the lamp shade take CYLINDER instead — one new
			# bucket for the whole street-furniture family.
			var head_h = CITY_LIGHT_LAMP * 3.4
			terrain.create_box(
				l_local + Vector3(0.0, lh + head_h * 0.5, 0.0),
				Vector3(CITY_LIGHT_LAMP * 1.5, head_h, CITY_LIGHT_LAMP * 1.4), lyaw,
				rng, block_batch, block_body, 0.0, terrain.CITY_METAL, false
			)
			var lamps = [terrain.CITY_LAMP_RED, terrain.CITY_LAMP_AMBER, terrain.CITY_LAMP_GREEN]
			for j in 3:
				terrain.create_box(
					l_local + l_front * (CITY_LIGHT_LAMP * 0.75)
							+ Vector3(0.0, lh + head_h - CITY_LIGHT_LAMP * (0.7 + float(j) * 1.05), 0.0),
					Vector3(CITY_LIGHT_LAMP, CITY_LIGHT_LAMP, CITY_LIGHT_LAMP * 0.4), lyaw,
					rng, block_batch, block_body, 0.0, lamps[j], false
				)
		else:
			# Lamp post: a cantilever arm with one shade on the end.
			var arm := rng.randf_range(0.7, 1.1)
			terrain.create_box(
				l_local + l_front * (arm * 0.5) + Vector3(0.0, lh, 0.0),
				Vector3(0.09, 0.09, arm), lyaw, rng, block_batch, block_body, 0.0, terrain.CITY_METAL, false
			)
			# The shade is a DRUM (`BoxKind.CYLINDER`), the bucket the mast has
			# already paid for — see the traffic-light note below for why this is
			# not the SPHERE the bead sketched.
			terrain.create_box(
				l_local + l_front * arm + Vector3(0.0, lh - CITY_LIGHT_LAMP * 0.5, 0.0),
				Vector3(CITY_LIGHT_LAMP * 1.6, CITY_LIGHT_LAMP, CITY_LIGHT_LAMP * 1.6), lyaw,
				rng, block_batch, block_body, 0.0, terrain.CITY_LAMP_AMBER, false,
				ChunkBatch.BoxKind.CYLINDER
			)

		# NON-climbable: a mast has no top to stand on, and its "top" is 4 m up.
		obstacles.append({
			"pos": l_local,
			"radius": CITY_LIGHT_RADIUS_MAX,
			"top": lh,
			"climbable": false,
		})


static func _spawn_snow_content(terrain: Node3D, chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	SNOW — bare frozen trees scattered thinly, and the occasional mammoth skeleton.

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One NON-climbable footprint per trunk, one per skeleton.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	EVERYTHING HERE IS NON-CLIMBABLE, and that is the deliberate half of the
	territory's shape. The three SNOW scattered props (ice rock, drift, stump) carry
	the whole rest-from-crocodiles role out here; a dead tree's top is 4 m up in the
	branches and a skeleton's "top" is its spine ridge with a ribcage arched over
	it, so a road coin perched on either would be unreachable. Non-climbable means
	_settle_coin_y SKIPS such a coin instead — the cactus / tree-canopy call.

	CROC DENSITY IS UNTOUCHED. The city is the one band whose target is divided
	(owner call, and it buys back the safety with its roofs); snow is deliberately
	the hostile end of the same spectrum, so nothing here thins the pack.

	EDGE FEATHERING: like every other biome builder, each candidate re-tests
	biome_at at ITS OWN position, so a tundra dissolves into the rock along the
	noise contour instead of stopping dead on a chunk seam.

	PERF: every box is a create_box entry, so a snow chunk is the SAME single block
	draw call as a plains chunk. A whole mammoth pays exactly TWO CollisionShape3Ds
	(the skull and the spine); its 8-10 ribs and 6 tusk segments are visual-only
	trim, the forest-canopy rule at a different scale.
	"""
	# ---- FROZEN DEAD TREES -------------------------------------------------
	# THE SEAM MARGIN AND THE FOOTPRINT RADIUS ARE TWO DIFFERENT NUMBERS HERE, the
	# same split the forest makes and for the same two reasons.
	#
	# The seam margin has to bound EVERY box, visual-only ones included — a branch
	# that hangs over the seam vanishes when its chunk unloads while the neighbour
	# is still drawn, and a disappearing branch looks exactly as broken as a
	# disappearing trunk. A branch is OFFSET from the trunk and THEN carries a yaw
	# and a tilt, so its reach is the offset PLUS half its own 3D diagonal — writing
	# only the half-diagonal (the bound a prop builder's centred decoration needs)
	# understates it by the offset, which is 0.63 m of the 1.40 and measured 24.81 m
	# of a 25.00 m seam over just fourteen chunks.
	#
	# The lean added by FROZEN_TREE_TILT_MAX carries the branches sideways with the
	# trunk, so the margin gains sin(lean) times the tallest trunk. Written as the
	# arithmetic, so retuning the lean or the height retunes this with it.
	var branch_reach = FROZEN_TREE_BRANCH_LEN * 0.42 + 0.5 * Vector3(FROZEN_TREE_BRANCH_LEN, 0.22, 0.22).length()
	branch_reach += sin(FROZEN_TREE_TILT_MAX) * FROZEN_TREE_HEIGHT_MAX
	var tree_half = terrain.chunk_size / 2.0 - (FROZEN_TREE_TRUNK_WIDTH_MAX * 0.71 + branch_reach)
	var chunk_pos_snow: Vector2i = terrain.world_to_chunk(chunk_center)
	var k_snow: float = terrain.scarcity_at(chunk_center)
	for _i in rng.randi_range(FROZEN_TREE_MIN, FROZEN_TREE_MAX):
		var local_x := rng.randf_range(-tree_half, tree_half)
		var local_z := rng.randf_range(-tree_half, tree_half)
		# The FOOTPRINT, by contrast, bounds the TRUNK only — the forest's rule
		# verbatim: branches are collide = false, so nothing can be stuck inside one,
		# and demanding clearance for the whole span would space dead trees out like
		# massifs. `+ 0.3` is the forest's own slack figure.
		#
		# Both rejections are post-draw `continue`s, the discipline every removal in
		# this file follows: the draws still advance the stream.
		if not _biome_spot_ok(terrain, chunk_center, local_x, local_z, FROZEN_TREE_TRUNK_WIDTH_MAX * 0.71 + 0.3, FROZEN_TREE_ROAD_CLEARANCE, obstacles):
			continue
		if terrain.biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != terrain.Biome.SNOW:
			continue

		var trunk_w = rng.randf_range(FROZEN_TREE_TRUNK_WIDTH_MIN, FROZEN_TREE_TRUNK_WIDTH_MAX)
		var trunk_h = rng.randf_range(FROZEN_TREE_HEIGHT_MIN, FROZEN_TREE_HEIGHT_MAX)
		var yaw := rng.randf_range(0.0, TAU)
		# The two per-tree restyle draws, unconditional and above the scarcity roll —
		# the forest builder's rule, for the forest builder's reason.
		var wood_t := rng.randf()
		var lean_snow = rng.randf_range(-FROZEN_TREE_TILT_MAX, FROZEN_TREE_TILT_MAX)
		var wood = terrain.SNOW_DEADWOOD.lerp(SNOW_DEADWOOD_DARK, wood_t)
		# Same axis arithmetic the forest canopy uses: create_box tips local +Y
		# toward local +Z, whose world direction under this yaw is (sin, 0, cos).
		var lean_dir_snow := Vector3(sin(yaw), 0.0, cos(yaw)) * sin(lean_snow)
		# Per-object scarcity for snow trees: own hash stream, no draw.
		if not terrain._scarcity_keep(chunk_pos_snow, _i, k_snow):
			continue

		# Trunk: solid, so you bump into it and the crocodiles' raycasts see it.
		terrain.create_box(
			Vector3(local_x, trunk_h * 0.5, local_z), Vector3(trunk_w, trunk_h, trunk_w),
			yaw, rng, block_batch, block_body, lean_snow, wood
		)

		# Bare branches — no canopy, that is the point of a dead tree. Visual only:
		# you walk under them exactly as you walk under a forest canopy.
		for _b in rng.randi_range(2, 3):
			var a := rng.randf_range(0.0, TAU)
			var by = trunk_h * rng.randf_range(0.55, 0.92)
			# One draw per branch: four identical sticks is the read this bead is
			# here to kill. Shrink-only (see FROZEN_TREE_BRANCH_JITTER_MIN).
			var blen = FROZEN_TREE_BRANCH_LEN * rng.randf_range(FROZEN_TREE_BRANCH_JITTER_MIN, 1.0)
			var dir = Vector3(cos(a), 0.0, sin(a)) * (blen * 0.42)
			terrain.create_box(
				Vector3(local_x, by, local_z) + dir + lean_dir_snow * (by - trunk_h * 0.5),
				Vector3(blen, 0.22, 0.22),
				a + PI * 0.5, rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
				wood.lerp(SNOW_DEADWOOD_DARK, 0.25), false
			)

		# Footprint stops at the TRUNK top and is NOT climbable — the forest's rule,
		# for the forest's reason.
		obstacles.append({
			"pos": Vector3(local_x, 0, local_z),
			"radius": trunk_w * 0.71 + 0.3,
			"top": trunk_h,
			"climbable": false,
		})

	# ---- MAMMOTH SKELETONS -------------------------------------------------
	var mammoth_half = terrain.chunk_size / 2.0 - MAMMOTH_EDGE_MARGIN
	for _i in rng.randi_range(0, MAMMOTH_MAX):
		# The candidate loop lives HERE rather than in a rarity roll, for the reason
		# camps and artifacts both had theirs moved: this is where `obstacles`
		# exists, and overlap is the test that actually rejects. Every draw happens
		# whether or not a try is accepted.
		var mx := 0.0
		var mz := 0.0
		var placed := false
		var tries := 0
		while tries < MAMMOTH_PLACE_TRIES and not placed:
			tries += 1
			mx = rng.randf_range(-mammoth_half, mammoth_half)
			mz = rng.randf_range(-mammoth_half, mammoth_half)
			if _biome_spot_ok(terrain, chunk_center, mx, mz, MAMMOTH_RADIUS, MAMMOTH_ROAD_CLEARANCE, obstacles) \
					and terrain.biome_at(chunk_center.x + mx, chunk_center.z + mz) == terrain.Biome.SNOW:
				placed = true
		if not placed:
			# Every try failing means NO skeleton. A mammoth shoved through a stand
			# of trees reads worse than a chunk without one — the camp's rule.
			continue
		# Per-object scarcity, post-draw (every placement try above has drawn) and
		# immediately before the ~17 draws _snow_mammoth spends. Offset 1000 so a
		# skeleton and the tree of the same index above do not share a roll — the
		# city's houses/stalls/lights precedent.
		if not terrain._scarcity_keep(chunk_pos_snow, _i + 1000, k_snow):
			continue

		var top := _snow_mammoth(terrain, Vector3(mx, 0.0, mz), rng, block_batch, block_body)

		obstacles.append({
			"pos": Vector3(mx, 0, mz),
			"radius": MAMMOTH_RADIUS,
			"top": top,
			"climbable": false,
		})


static func _snow_mammoth(terrain: Node3D, local: Vector3, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	"""
	Build one mammoth skeleton and return the height of its spine ridge.

	@param local: Chunk-local position of the ribcage's rear end (see the frame
	              note below); the skeleton lies along its own yaw from there.
	@param rng: The biome stream's private RNG.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.
	@return: The top of the spine slab — the `top` its footprint records.

	16-18 boxes, EXACTLY TWO OF WHICH COLLIDE (the skull and the spine slab). The
	ribs and the tusks are silhouette, and a silhouette does not need to be solid;
	making them solid would take one skeleton from 2 collision shapes to 18 and put
	a snag in the middle of the tundra for no gameplay at all.

	THE FRAME: everything below is written in the skeleton's own coordinates —
	local +X runs nose-forward along the animal, local Z is lateral — and every
	offset is rotated into the chunk by `yaw` before it is handed to create_box.
	The spine spans x in [-spine_len, 0] and the skull sits at x = +0.7, so the
	piece is roughly centred on `local` and the one round footprint circle is a
	tight-ish bound in both directions rather than a tight one forward and a wasteful
	one behind.

	A SKELETON READS BY SILHOUETTE AND NOTHING ELSE, which is the whole reason the
	box budget is spent where it is: two tusk curves and a row of rib arches are what
	a person names a mammoth by at 30 m. There are deliberately no legs, no pelvis
	and no detail — at that distance they are noise, and every one would be another
	box in the chunk's MultiMesh.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var fwd := Vector3(cos(yaw), 0.0, -sin(yaw))   # Basis(UP, yaw) * Vector3.RIGHT
	var side := Vector3(sin(yaw), 0.0, cos(yaw))   # Basis(UP, yaw) * Vector3.BACK
	var spine_len = rng.randf_range(MAMMOTH_SPINE_LEN_MIN, MAMMOTH_SPINE_LEN_MAX)
	var pairs = rng.randi_range(MAMMOTH_RIB_PAIRS_MIN, MAMMOTH_RIB_PAIRS_MAX)
	var rib_top = MAMMOTH_RIB_HEIGHT * cos(MAMMOTH_RIB_TILT)
	var bone = terrain.PROP_BONE.lerp(terrain.SNOW_ICE_B, rng.randf() * 0.18)

	# --- RIBS. Each pair is two thin boxes whose BASES sit wide on the ground and
	# whose TOPS lean in over the spine. The tilt sign is what does that: a tilt
	# about the box's local X sends its up-vector toward local +Z, so the rib on
	# the -Z side takes a POSITIVE tilt and its mirror a negative one. Get the sign
	# backwards and the ribcage splays outward like a flower, which looks wrong and
	# raises nothing.
	for i in pairs:
		var t := (float(i) + 0.5) / float(pairs)
		var x = -spine_len * (0.08 + 0.84 * t)
		var rib_h = MAMMOTH_RIB_HEIGHT * rng.randf_range(0.88, 1.05)
		for s: float in [-1.0, 1.0]:
			terrain.create_box(
				local + fwd * x + side * (MAMMOTH_RIB_HALF_SPREAD * s)
						+ Vector3(0.0, rib_h * 0.5 * cos(MAMMOTH_RIB_TILT), 0.0),
				Vector3(0.16, rib_h, 0.30), yaw,
				rng, block_batch, block_body, -MAMMOTH_RIB_TILT * s,
				bone, false
			)

	# --- SPINE. One slab lying along the top of the ribcage, and one of the two
	# boxes that collide. It spans exactly x in [-spine_len, 0], so the footprint's
	# rear reach is spine_len and needs no separate bound.
	var spine_top = rib_top + 0.30
	terrain.create_box(
		local + fwd * (-spine_len * 0.5) + Vector3(0.0, rib_top + 0.15, 0.0),
		Vector3(spine_len, 0.30, 0.45), yaw,
		rng, block_batch, block_body, 0.0, bone
	)

	# --- SKULL. The other colliding box: a blunt mass at the front, which is what
	# the tusks have to come out of for the pair to read as one animal.
	terrain.create_box(
		local + fwd * 0.70 + Vector3(0.0, 0.60, 0.0),
		Vector3(1.40, 1.15, 1.25), yaw,
		rng, block_batch, block_body, 0.0, bone
	)

	# --- TUSKS. Two curves of three boxes, walked segment by segment from the
	# skull's front face. See the MAMMOTH_TUSK_SEGMENTS banner for why the yaw
	# carries a quarter turn: it is the only way to make a box lean along the
	# skeleton's LENGTH rather than across it.
	var tusk_yaw := yaw + PI * 0.5
	for s: float in [-1.0, 1.0]:
		var pos := local + fwd * 1.35 + side * (0.40 * s) + Vector3(0.0, 0.45, 0.0)
		for seg_variant: Variant in MAMMOTH_TUSK_SEGMENTS:
			var seg: Array = seg_variant
			var seg_len: float = float(seg[0])
			var tilt: float = float(seg[1])
			# The segment's own up-vector, in world terms: Basis(UP, yaw + PI/2) *
			# Basis(RIGHT, tilt) * UP works out to fwd * sin(tilt) + UP * cos(tilt).
			var dir = fwd * sin(tilt) + Vector3.UP * cos(tilt)
			terrain.create_box(
				pos + dir * (seg_len * 0.5), Vector3(0.18, seg_len, 0.18),
				tusk_yaw, rng, block_batch, block_body, tilt, bone, false
			)
			pos += dir * seg_len

	return spine_top


static func _city_snap(terrain: Node3D, value: float, rng: RandomNumberGenerator) -> float:
	"""
	Snap one chunk-local coordinate onto the city's coarse street grid, plus a
	little jitter so the result reads as a town rather than as graph paper.

	@param value: The raw chunk-local coordinate already drawn by the caller.
	@param rng: The biome stream's private RNG — one draw, for the jitter.
	@return: The snapped coordinate.

	The snap is world-independent (it works in CHUNK-local space) on purpose: a
	world-space grid would have to survive the chunk-local/world conversion at
	every call site for nothing, since a 50 m chunk is a whole number of 9 m
	pitches nowhere and the grid is a READ, not a layout system. Neighbouring
	chunks therefore have their own street lines, which is exactly what a town
	that grew looks like.
	"""
	return roundf(value / CITY_BLOCK_PITCH) * CITY_BLOCK_PITCH + rng.randf_range(-CITY_BLOCK_JITTER, CITY_BLOCK_JITTER)

# ============================================================================
# BIOME FIELD (one noise field; six biomes + rivers read out of it)
# ============================================================================
#
# ponytail: the ground stays a FLAT y = 0 plane — see the full note in the BIOME
# FIELD CONFIGURATION block at the top of the file for why (coin heights, road
# placement, croc gravity settle, spawn, and the box ground collision all assume
# it) and for the heightfield upgrade path.
#
# Everything below is a PURE function of world position plus biome_offset (which
# is constant for a whole run), so:
#   - a revisited chunk classifies identically no matter when it is built, which
#     is what makes the time-sliced, arbitrary-order chunk generation safe;
#   - no RNG stream is touched anywhere in here — there are no draws at all.
