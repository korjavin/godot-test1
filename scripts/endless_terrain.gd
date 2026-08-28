extends Node3D
## Endless Terrain Generator
##
## This script creates an "endless" field by generating terrain chunks
## around the player and removing chunks that are far away.
##
## EDUCATIONAL NOTES:
## - This uses a technique called "chunk-based terrain generation"
## - Chunks are created/destroyed dynamically based on player position
## - This is how games like Minecraft create infinite worlds!

# ============================================================================
# SECTION 1: TERRAIN CONFIGURATION
# ============================================================================

## Size of each terrain chunk (in meters)
## Larger chunks = fewer chunks needed, but more memory per chunk
@export var chunk_size: float = 50.0

## How many chunks to render around the player in each direction
## Higher values = you can see further, but more GPU/CPU usage
@export var render_distance: int = 5

## Reduced render distance used ONLY on the web (WebGL) build (see _ready()).
##
## WHY WEB GETS A SMALLER VIEW:
## render_distance is squared into the number of active chunks — desktop's 5 means
## (2*5+1)² = 121 chunks live at once, each carrying a ground mesh, a block MultiMesh,
## a block-collision body, ~10 crocodiles and some coins. In a browser that is a LOT
## of draw calls, physics bodies and AI to keep alive, and it's the single biggest CPU/
## GPU cost. Dropping to 3 means only (2*3+1)² = 49 chunks — roughly 2.5× fewer chunks,
## i.e. ~2.5× fewer crocodiles/bodies/draw calls to simulate and render every frame.
## That's the largest single web performance win in this plan.
##
## The catch is that a smaller view normally reveals the "edge of the world" — the last
## ring of chunks just stops, with sky beyond it. We hide that edge with depth fog (set
## up below in _ready) coloured like the sky horizon, so the nearer world edge
## dissolves into the sky and the field still FEELS endless. Desktop keeps the full 5
## chunks of view and gets a much thinner fog (see FOG_DENSITY_DESKTOP below).
##
## TUNABLE: 3 is a good default. If the visible world feels too tight in the browser,
## bump this to 4 (and, if you do, you may want to lower the fog density a touch so the
## fog still sits just inside the new, larger view).
const WEB_RENDER_DISTANCE: int = 3

# ----------------------------------------------------------------------------
# UNIVERSAL DEPTH FOG (see _setup_fog)
# ----------------------------------------------------------------------------
##
## Fog runs on EVERY platform now — desktop and editor included. This is an intentional,
## owner-sanctioned desktop visual change: the ONE deliberate exception to this repo's
## "visual changes are web-gated" rule. On web the fog is thick and masks the reduced
## view distance (its original job); on desktop it is a thin depth haze that dissolves
## the far horizon instead of showing a hard world edge. Only the DENSITY stays
## platform-gated, because density is a view-distance/perf concern, not a look concern.
##
## Fog colour: the sky horizon colour from main.tscn's ProceduralSkyMaterial
## (sky_horizon_color = ground_horizon_color = 0.85, 0.86, 0.80). Matching the horizon
## makes the fogged-out world edge blend seamlessly into the sky instead of reading as a
## coloured haze. CONTRACT: if the sky horizon colour ever changes, this constant moves
## with it — all three values are one colour.
const FOG_COLOR: Color = Color(0.85, 0.86, 0.80)

## Exponential fog density, WEB value. The reduced web view reaches render_distance(3) ×
## chunk_size(50) = ~150 m to the nearest chunk edge and ~175 m to the far corner, so we
## want visibility to fade out around there. 0.005 gives roughly ~150–250 m of visibility
## (exponential fog has no hard cutoff — it thickens with distance), which tucks the chunk
## boundary into the haze without fogging the playable area near the player.
## TUNABLE: raise toward 0.006 for a closer/denser edge, lower toward 0.004 for a more
## open feel (or if you bump WEB_RENDER_DISTANCE to 4).
const FOG_DENSITY_WEB: float = 0.005

## Exponential fog density, DESKTOP/EDITOR value. Desktop sees ~250–275 m of chunks
## (render_distance 5), so the fog must sit much further out: 0.0022 is a soft depth
## haze that only reads near the far edge of the view, giving aerial perspective
## without eating the playable area.
const FOG_DENSITY_DESKTOP: float = 0.0022

## Terrain height variation (for future procedural generation)
## Currently we use a flat plane, but this allows for hills/valleys
@export var terrain_height: float = 0.0

## The material to apply to terrain chunks
## You can customize this in the Godot editor! Typed as the base Material so
## it accepts EITHER a StandardMaterial3D or a ShaderMaterial — when left
## empty, _ready() builds the default ShaderMaterial running
## assets/shaders/ground.gdshader (a vertex-noise two-green blend).
@export var terrain_material: Material

## Enable/disable object spawning on terrain
@export var spawn_objects: bool = true

## Number of objects to spawn per chunk (approximately)
## Higher values = more cluttered terrain
@export var objects_per_chunk: int = 12

## Minimum distance between objects (in meters)
## Higher values = more space for player movement
@export var min_object_spacing: float = 5.0

## Object size range (random between min and max)
@export var object_size_min: float = 1.0
@export var object_size_max: float = 2.5

## Chance (0..1) that a chunk gets one "feature" structure — a barrier wall, a
## run-through lane, a gate or a terraced mound — for variety. Kept moderate so
## structures show up often enough to be interesting but the field doesn't feel
## crowded. This is the GLOBAL default; see _structure_chance_at() for the one
## per-territory deviation (mountain, where massifs already dominate).
@export var structure_chance: float = 0.5

## How many blocks long a wall / corridor is (random between min and max).
@export var wall_min_length: int = 4
@export var wall_max_length: int = 7

# ----------------------------------------------------------------------------
# THEMED SCATTERED PROPS — the re-skin of the old bare cube / cube-tower scatter
# ----------------------------------------------------------------------------
# The scatter loop in spawn_objects_in_chunk is UNCHANGED in everything that has
# consequences — same position draws, same min_object_spacing, same river skip,
# same DESERT_BLOCK_KEEP_EVERY target, same footprint entry. The only thing that
# changed is the GEOMETRY emitted at an accepted spot: instead of one cube (plus
# an occasional cube tower, which is why the old `stack_chance` / `stack_max_extra`
# exports are gone — the cairn and slab-stack VARIANTS are those towers now), a
# themed prop builder runs, chosen by biome_at at the PROP'S OWN position so the
# themes feather across a biome edge exactly like the biome content does.
#
# SHARED-STREAM RULE (the one thing a prop builder may never break): the chunk's
# RNG pays a FIXED cost per accepted spot — one randf_range for `size`, then ONE
# randi() as the prop SEED — whatever the variant. Builders run on a PRIVATE
# RandomNumberGenerator built from that seed (the artifact/camp private-RNG
# pattern, one level down) and are handed no shared rng at all, so a 3-box stump
# and an 8-box bone pile advance the chunk stream identically and prop complexity
# can never reshuffle the crocodiles, coins or structures that draw after them.
# Byte-identity with the PRE-prop world is deliberately not preserved (the same
# licence CLAUDE.md's biome feature-skip note takes); within-run purity is, and
# it holds unconditionally because every placement is still a pure function of
# chunk coords + run_seed.

## Footprint radius of a prop as a fraction of its drawn `size`. Every builder
## keeps ALL of its geometry — including tilted decoration — inside this radius
## of the prop's centre, so the returned radius stays an HONEST bound: it is what
## _settle_coin_y perches road coins against, what spawn_crocodiles_in_chunk
## keeps its NPCs out of, and what the mountain massifs avoid-list reads.
##
## 0.71 IS THE BARE CUBE'S OWN FACTOR, kept deliberately: the footprint rule is
## then literally unchanged from the cubes, so `size` still means the same thing,
## the range is still 0.71-1.78 m, and the value stays under MOUNTAIN_AVOID_RADIUS
## (2.0) — props remain "fair game" to bury in a massif exactly as cubes were, and
## the constant chain around that inequality needed no re-derivation.
const PROP_RADIUS_FACTOR: float = 0.71

## THE CLIMBABILITY CONTRACT, as a number. A prop that records `climbable: true`
## must be mountable from flat ground in steps no taller than this, each step
## landing on a FLAT (untilted) top — that is the "rest spot from crocodiles"
## role the bare cubes carried, and it breaks difficulty silently if it is lost.
## 2.6 sits under the player's jump apex (JUMP_VELOCITY^2 / 2*gravity = 3.6125 m)
## with room for the arc, and matches the old 2.5 m single-cube step that has
## been the proven size since the first chunk was generated.
## prop_selfcheck.gd measures the emitted geometry against this, per variant.
const PROP_MAX_STEP: float = 2.6

## --- Prop palettes. Deliberately distinct from the warm RAMP_* block ramps (the
## feature structures still use those), the artifacts' grey-green, the camps'
## bone white and the landmarks' place-specific colours — a themed prop should
## read as belonging to its BIOME, not to the generic block palette.
const PROP_BOULDER_A := Color(0.54, 0.52, 0.47)   # plains fieldstone …
const PROP_BOULDER_B := Color(0.40, 0.39, 0.36)   # … to darker granite
const PROP_RUIN_STONE := Color(0.68, 0.64, 0.55)  # cut, weathered masonry
const PROP_HAY := Color(0.79, 0.66, 0.31)         # straw bale
const PROP_CRATE := Color(0.44, 0.31, 0.18)       # cart timber
const PROP_SANDSTONE_A := Color(0.82, 0.67, 0.43) # wind-worn desert sandstone …
const PROP_SANDSTONE_B := Color(0.66, 0.50, 0.32) # … to its shaded underside
const PROP_BONE := Color(0.89, 0.87, 0.79)        # sun-bleached bone
const PROP_MOSS_ROCK := Color(0.39, 0.44, 0.32)   # damp forest boulder
const PROP_MOSS_CAP := Color(0.26, 0.41, 0.23)    # the moss growing on it
const PROP_STUMP := Color(0.35, 0.25, 0.16)       # cut stump / root flare
const PROP_LOG := Color(0.44, 0.32, 0.21)         # fallen log bark
const PROP_SCREE_A := Color(0.57, 0.57, 0.59)     # mountain scree …
const PROP_SCREE_B := Color(0.39, 0.40, 0.43)     # … to shadowed rock
const PROP_CAIRN := Color(0.50, 0.49, 0.46)       # stacked cairn slabs

## --- CITY palette. Eight new colours for a whole territory, and the count is a
## decision rather than an accident: the phase-1 rule is that every colour added
## is one more thing for a MultiMesh of boxes to fail to be distinct from, so the
## city reuses PROP_CRATE for every piece of timber it owns (doors, stall
## counters, market crates) and PROP_RUIN_STONE for its paving and garden walls,
## and spends new constants only where a city is unmistakable: limewashed
## plaster, a tiled or slated roof, and the three signal lamps.
##
## THE PLASTER RAMP IS DELIBERATELY BRIGHTER THAN EVERY OTHER TERRITORY'S STONE
## (r 0.71-0.87 against a highest-elsewhere 0.82 at the desert's sandstone, which
## is two bands away and can never touch it). That is not taste — prop_selfcheck
## requires each territory's stone_a to lie off every other territory's ramp, and
## the near-miss it is dodging is the mountain's PROP_SCREE_A, which sits almost
## exactly on a cooler grey plaster ramp.
const CITY_PLASTER_A := Color(0.87, 0.85, 0.79)   # limewashed wall, sunlit …
const CITY_PLASTER_B := Color(0.71, 0.66, 0.58)   # … to weathered render
const CITY_ROOF_TILE := Color(0.55, 0.29, 0.21)   # terracotta pantile
const CITY_ROOF_SLATE := Color(0.33, 0.34, 0.37)  # slate roof / awning canvas
const CITY_METAL := Color(0.26, 0.27, 0.29)       # lamp post, signal mast, head
const CITY_LAMP_AMBER := Color(0.96, 0.82, 0.36)  # bright ALBEDO, never emissive
const CITY_LAMP_RED := Color(0.86, 0.24, 0.20)
const CITY_LAMP_GREEN := Color(0.32, 0.76, 0.36)

## --- SNOW palette. FOUR new colours for a whole territory — the leanest of the
## six, and deliberately so: a tundra is a place with almost nothing in it, so the
## one thing it must not do is arrive with a paint box. Ice gets a ramp (it is the
## territory's stone), snow gets one flat near-white, and dead timber gets one
## grey-brown. Everything BONE reuses PROP_BONE, which the desert's bone pile
## already defines — the desert band (n < 0.34) and the snow band (n >= 0.83) can
## never touch, and a mammoth's ribs and a camel's ribs are honestly the same
## colour, so a fifth constant would buy nothing but one more near-white for a
## MultiMesh of boxes to fail to be distinct from.
##
## SNOW_ICE_A IS THE ONLY ONE WITH A CONSTRAINT ON IT: prop_selfcheck requires each
## territory's structure `stone_a` to lie off every other territory's ramp, and the
## near-miss it is dodging here is CITY_PLASTER_A — a bright off-white that a
## desaturated pale ice would sit straight on top of. The blue cast (b 0.96 against
## a red 0.80) is what separates them, not the brightness.
const SNOW_ICE_A := Color(0.80, 0.90, 0.96)     # sunlit glacier ice …
const SNOW_ICE_B := Color(0.50, 0.66, 0.80)     # … to its blue shadowed core
const SNOW_PACK := Color(0.95, 0.96, 0.98)      # wind-packed drift snow
const SNOW_DEADWOOD := Color(0.47, 0.44, 0.42)  # frost-bleached dead timber

# ----------------------------------------------------------------------------
# THEMED FEATURE STRUCTURES — the same re-skin, one scale up from the props
# ----------------------------------------------------------------------------
# spawn_feature_structure used to pick wall / corridor / gate / Mayan step-pyramid
# from ONE global table, so the identical grey boxes stood in every region and the
# pyramid (the owner's "especially ugly") stood in all four. It now picks from a
# PER-TERRITORY table and dresses whichever ROLE it picked in that territory's
# materials — exactly the phase-1 prop move, one scale up:
#
#   * THE FOUR ROLES ARE FIXED and each keeps its gameplay job. A wall is a
#     barrier with a walkable ridge; a corridor is a lane you sprint down; a gate
#     is a thing you run under; the mound is the climbable stepped centrepiece
#     with a platform on top — the pyramid's ROLE, none of its look.
#   * WHAT CHANGES PER TERRITORY is the mix (which roles come up, and how often),
#     the palette, and a handful of shape knobs in STRUCTURE_THEMES below. That is
#     what makes a desert colonnade, a forest log bridge and a mountain fort out of
#     three lines of table instead of twelve builders.
#   * ONE rng.randf() PICK DRAW, exactly as before. The biome is read from
#     chunk_center — a pure function of chunk coords — so choosing the table costs
#     no draw at all and the dispatch stays post-draw.
#   * TRIM NEVER GOES ON A WALKABLE TOP. Themed clutter (rubble, moss, cornices,
#     capstones) is `collide = false` and either beside the structure or a thin
#     film over it; the box whose top face a platform or a climbable footprint
#     names is always an untilted, colliding, full-size one. That is prop rule 2
#     restated for structures, and prop_selfcheck.gd measures it.
#
# DRAW-COUNT CONSEQUENCE, stated plainly: the builders draw a different number of
# randoms than they used to, so a chunk's scattered blocks, crocodiles and coins
# shuffle relative to the pre-theme world. That is the same licence the biome
# feature-skip note and the phase-1 prop re-skin already took — WITHIN-RUN purity
# is the load-bearing half, and it holds unconditionally because every placement
# is still a pure function of chunk coords + run_seed.

## The gate's three dressings. A `gate_style` in STRUCTURE_THEMES picks one.
const STRUCT_GATE_ARCH: int = 0   # broken arch: one stunted pillar, a stub lintel
const STRUCT_GATE_LINTEL: int = 1 # intact monumental gate (+ a cornice if capped)
const STRUCT_GATE_LOG: int = 2    # a felled giant on two stumps — a WALKABLE deck

## The widest a mound terrace can reach in WORLD X/Z as a fraction of base_size.
## A terrace is a (w, d) slab turned by up to MOUND_TERRACE_YAW, so its rotated
## world half-extent is 0.5 * (w * cos + d * sin) — at the base terrace's widest
## (d == w == base_size) and the full yaw, 0.5 * (cos 0.35 + sin 0.35) = 0.641 of
## base_size, NOT the 0.5 the unrotated half-width suggests. That difference is up
## to 2.8 m on a 20 m mound, which is enough to hang a terrace over the chunk seam
## — and a mound's mesh and collision belong to ONE chunk, so the overhang would
## vanish the moment that chunk unloaded while its neighbour stayed loaded.
## 0.65 bounds 0.641 with slack; it stays under the footprint radius factor 0.71,
## so the obstacle circle is still an honest bound on the stone.
const MOUND_ROT_EXTENT: float = 0.65

## The most a terrace may be turned. Bounded rather than free because
## MOUND_ROT_EXTENT above is derived from it — widen one and re-derive the other.
const MOUND_TERRACE_YAW: float = 0.35

## Lateral wobble (metres) allowed per terrace of a terraced mound. Bounded, not
## chosen by eye: the mound's footprint radius is base_size * 0.71 and a terrace
## above the base is at most 0.72 * base_size wide, i.e. 0.51 * base_size of
## half-diagonal, so 0.9 m of wobble still fits inside the declared radius for the
## smallest mound the builder can draw (8 m base: 4.07 + 0.9 = 4.97 < 5.68).
const MOUND_TERRACE_JITTER: float = 0.9

## Mountain chunks build a feature structure a bit less often — massifs already
## dominate the skyline there, and a fort stub competing with a 20 m wall of rock
## reads as clutter. THIS IS A THRESHOLD, NOT AN EXTRA ROLL: _structure_chance_at
## scales the number the ONE existing rng.randf() is compared against, so no draw
## is inserted anywhere and the gate stays a pure function of chunk coords (the
## same discipline DESERT_BLOCK_KEEP_EVERY follows for scattered blocks).
const MOUNTAIN_STRUCTURE_CHANCE_FACTOR: float = 0.55

## Cumulative pick thresholds for the four roles, in the order
## [wall, corridor, gate, mound]. A role whose band has zero width never comes up
## in that territory — which is how mountain drops the mound (a soft terraced
## hill next to a massif is the one shape that reads as a mistake) without a
## special case in the dispatch.
const STRUCTURE_MIX: Dictionary = {
	Biome.PLAINS: [0.30, 0.55, 0.75, 1.00],   # the shipped mix, unchanged
	Biome.DESERT: [0.22, 0.52, 0.72, 1.00],   # colonnades and mesas carry the desert
	Biome.FOREST: [0.32, 0.60, 0.86, 1.00],   # log bridges are the forest signature
	Biome.MOUNTAIN: [0.42, 0.74, 1.00, 1.00], # fort walls and watchtower bases only
	Biome.CITY: [0.26, 0.60, 0.80, 1.00],     # the ALLEY is the city's signature
	Biome.SNOW: [0.40, 0.68, 0.84, 1.00],     # wind-break walls carry the tundra
}

## Per-territory dressing. Every colour is one the phase-1 prop palette already
## defines — a territory should read as ONE place, so its structures are cut from
## the same stone as its scenery, and a re-theme that needed four new colours
## would just be four more things for a MultiMesh of boxes to fail to be distinct
## from. Knobs:
##   stone_a/stone_b  the two ends of the ramp every solid box is sampled from
##   trim             collide=false clutter (rubble, moss, fallen stones)
##   cap              collide=false film over a top (Color alpha 0 = no cap)
##   gap_chance       chance a wall/lane segment is missing (ruin), 0 = solid
##   double_chance    chance a wall segment doubles up into a hump/battlement
##   lane_spaced      true = the lane's sides are column PAIRS, not solid walls
##   lintel_chance    chance a spaced pair is bridged overhead (portico beam)
##   gate_style       one of STRUCT_GATE_*
const STRUCTURE_THEMES: Dictionary = {
	# PLAINS — a ruin in a meadow. Gaps and fallen stone; the shipped mix and
	# the shipped solid lane, re-cut in weathered masonry instead of grey boxes.
	Biome.PLAINS: {
		"stone_a": PROP_RUIN_STONE, "stone_b": PROP_BOULDER_B, "trim": PROP_BOULDER_A,
		"cap": Color(0.0, 0.0, 0.0, 0.0),
		"gap_chance": 0.20, "double_chance": 0.30,
		"lane_spaced": false, "lintel_chance": 0.0,
		"gate_style": STRUCT_GATE_ARCH,
	},
	# DESERT — a temple bleached by the sun. The lane becomes a COLONNADE (column
	# pairs, half of them still carrying their lintel), which keeps the sprint
	# lane intact while reading nothing like a wall.
	Biome.DESERT: {
		"stone_a": PROP_SANDSTONE_A, "stone_b": PROP_SANDSTONE_B, "trim": PROP_SANDSTONE_B,
		"cap": Color(0.0, 0.0, 0.0, 0.0),
		"gap_chance": 0.08, "double_chance": 0.10,
		"lane_spaced": true, "lintel_chance": 0.55,
		"gate_style": STRUCT_GATE_LINTEL,
	},
	# FOREST — overgrown stone and dead wood. The lane is a corridor of standing
	# dead trunks; the gate is a felled giant you can walk along.
	Biome.FOREST: {
		"stone_a": PROP_MOSS_ROCK, "stone_b": PROP_STUMP, "trim": PROP_LOG,
		"cap": PROP_MOSS_CAP,
		"gap_chance": 0.25, "double_chance": 0.15,
		"lane_spaced": true, "lintel_chance": 0.0,
		"gate_style": STRUCT_GATE_LOG,
	},
	# MOUNTAIN — a stone fort. Solid (no gaps), heavily battlemented, capped in
	# pale slab; no mound, because the massifs are the hills here.
	Biome.MOUNTAIN: {
		"stone_a": PROP_SCREE_A, "stone_b": PROP_SCREE_B, "trim": PROP_SCREE_B,
		"cap": PROP_CAIRN,
		"gap_chance": 0.0, "double_chance": 0.45,
		"lane_spaced": false, "lintel_chance": 0.0,
		"gate_style": STRUCT_GATE_LINTEL,
	},
	# CITY — a street block. The four roles need no new builder to read as urban:
	# the SOLID lane (lane_spaced false) is two building faces with an alley
	# between them, which is why the lane band is the widest here; the wall is a
	# render boundary wall with the occasional parapet (double_chance) and a tiled
	# cap; the gate is a monumental arch over a street; the mound is a stepped
	# plaza. Timber trim is PROP_CRATE — scaffold and stacked goods against a wall.
	Biome.CITY: {
		"stone_a": CITY_PLASTER_A, "stone_b": CITY_PLASTER_B, "trim": PROP_CRATE,
		"cap": CITY_ROOF_TILE,
		"gap_chance": 0.10, "double_chance": 0.35,
		"lane_spaced": false, "lintel_chance": 0.0,
		"gate_style": STRUCT_GATE_LINTEL,
	},
	# SNOW — ice cut into blocks and left to weather. The wall is a wind-break with
	# a snow cornice on every doubled hump (`cap` SNOW_PACK, which is also the free
	# visual rhyme with the massif snow caps one band down); the lane is an avenue
	# of standing ice pillars (lane_spaced, no lintel — ice does not span); the gate
	# is a broken arch, because the intact version reads as built rather than
	# frozen; and the mound is a drift barrow. Trim is dead timber, the only warm
	# thing in the territory and therefore the only thing that reads at all against
	# the white.
	Biome.SNOW: {
		"stone_a": SNOW_ICE_A, "stone_b": SNOW_ICE_B, "trim": SNOW_DEADWOOD,
		"cap": SNOW_PACK,
		"gap_chance": 0.22, "double_chance": 0.25,
		"lane_spaced": true, "lintel_chance": 0.0,
		"gate_style": STRUCT_GATE_ARCH,
	},
}

## Enable/disable crocodile spawning on terrain
@export var spawn_crocodiles: bool = true

## Number of crocodiles to spawn per chunk
## Higher values = more dangerous terrain!
@export var crocodiles_per_chunk: int = 10

## Minimum distance between crocodiles (in meters)
@export var min_crocodile_spacing: float = 3.0

## How much clear space (in meters) to keep between a crocodile and the nearest
## block. This stops crocodiles from spawning partially buried inside blocks.
@export var min_object_clearance: float = 1.5

## Radius (in metres) of the crocodile-free bubble around the world origin — the
## spawn point every run and every restart begins on.
##
## Without it the FIRST run of a session gets no spawn protection at all: the
## player's own clear_nearby_crocodiles() sweep only runs on respawn/restart, so a
## fresh boot drops the player into a chunk holding ~10 crocodiles with nothing
## keeping them off (0,0) — several sit inside their own `detection_radius` (15
## for a crocodile) and start chasing on frame one, and every species' chase_speed
## beats WALK_SPEED (5.0) by construction. Both used to be the consts
## DETECTION_RADIUS / BASE_CHASE_SPEED; they are SPECIES rows now, which is why
## this bubble is stated as a radius and not as "bigger than the one number".
## Enforced here, in world generation, rather than as another sweep: it is a pure
## function of position, so it holds identically for new_run() and needs no
## ordering dance with the player's _ready(), which runs before any chunk exists.
## Matches the player's SPAWN_SAFE_RADIUS (the post-respawn sweep radius) — the two
## are the same rule enforced from the two ends; keep them in step if either moves.
const SPAWN_SAFE_RADIUS: float = 25.0

# ----------------------------------------------------------------------------
# THE TOWER SITE — GastroDefense HQ (epic godot-test1-3iy, phase 1)
# ----------------------------------------------------------------------------
##
## The tower is ONE authored building at ONE place in the world, and this phase is
## only two things: everybody agrees WHERE that place is (tower_site()), and
## nothing procedural is allowed to stand there (tower_excludes()). No tower
## geometry ships here — the shell is phase 2, and it must sit on the disc these
## constants describe rather than restate a number of its own.

## Distance from the world origin, along -X, to the tower's NOMINAL site (metres).
##
## Owner-ruled at 400 m (2026-08-27): far enough to be a journey, near enough to
## walk to. It is well outside SPAWN_SAFE_RADIUS (25), so the spawn bubble and this
## disc can never touch, and outside the initial render ring (render_distance 5 ×
## chunk_size 50 = 250 m), so the site is not generated on frame 0.
##
## An @export rather than a const because it is the one knob the site has — a
## designer may move the tower, and tower_site_selfcheck.gd drives it far out of
## the sampled field to prove the A/B (with the exclusion effectively off, every
## chunk comes out byte-identical). tower_site() re-derives itself when it changes.
@export var tower_site_distance: float = 400.0

## Radius (metres) of the tower's EXCLUSION DISC, centred on tower_site().
##
## Two jobs in one number: it is the area world generation keeps clear, and it is
## the budget phase 2's shell has to fit inside (share the constant, never restate
## the number). 30 m is a little over half a chunk — a large-HQ footprint plus its
## yard — and it costs the field ~1.1 chunks of content, once, in a whole world.
##
## HOW CLEAR IS CLEAR: spawners routed through _biome_spot_ok are handed the
## candidate's own radius, so their whole FOOTPRINT stays outside the disc. The
## scattered props, the four feature structures, the crocodiles and the bosses are
## judged on their CENTRE plus a conservative extent — the same currency the
## `obstacles` list uses everywhere else in this file, and the same shape as their
## own river tests, which are centre tests for the same reason.
##
## What is deliberately NOT excluded is the COIN ROAD. It is a parametric line
## through the whole world and cutting a hole in it would break "follow the coins";
## phase 2 owns whatever the road does at the tower door. Bosses ARE excluded —
## a 6× crocodile wedged in the doorway is a different problem from a coin.
const TOWER_RADIUS: float = 30.0

## Extra clearance (metres) every tower rejection adds on top of the candidate's
## own declared radius.
##
## WHY A DECLARED RADIUS IS NOT THE WHOLE THING. The `radius` a spawner hands to
## _biome_spot_ok is an OVERLAP footprint — how much ground the thing claims — and
## for several builders it is deliberately smaller than the silhouette, because
## overhanging decoration is allowed to overlap its neighbours (that is what makes
## a forest read as a forest). A tree declares its TRUNK (0.75 * 0.71 + 0.3 =
## 0.83 m) and then spreads a canopy TREE_CANOPY_WIDTH_MAX (3.4) wide — up to
## 2.4 m from the trunk once yawed, so ~1.6 m past what it declared. A frozen
## tree's bare branch (FROZEN_TREE_BRANCH_LEN 1.5) does the same, smaller.
##
## Threading a second "visual extent" argument through every biome caller to
## recover 1.6 m would be a lot of machinery for a leaf; one constant, added once
## inside tower_excludes, keeps the whole disc clear of overhang instead — and it
## costs nothing but a slightly wider reservation.
##
## 2.5 m clears both known cases with room to spare. Anything built later that
## overhangs its declared footprint by MORE than this belongs on this line.
## (Found by codex review, 2026-08-28: run seed 1 grew a canopy 32.03 m out whose
## leaves reached 29.81 m, i.e. 0.19 m inside the disc.)
const TOWER_DECOR_OVERHANG: float = 2.5

## THE DRY-SITE NUDGE — step of the candidate lattice, and how many rings of it.
##
## is_river_at() ignores Y by contract (the world is flat and a river is a tint),
## and the player's wading test is XZ-only, so a tower standing on a river band
## would wade on every floor. The site therefore scans a FIXED lattice — candidates
## TOWER_NUDGE_STEP apart, ring by ring outward from the nominal site, out to
## TOWER_NUDGE_RINGS rings (200 m of reach) — and takes the first whose whole
## footprint disc is dry.
##
## FIXED, NEVER RANDOM: the scan consumes no RNG draw of any kind. The river field
## is already a pure function of run_seed, so the answer is one too. And it is
## TOTAL: a seed whose rivers soak the entire corridor still terminates, on the
## DRIEST candidate the lattice found. If that ever stops being good enough, widen
## the lattice — never reach for a random retry.
const TOWER_NUDGE_STEP: float = 25.0
const TOWER_NUDGE_RINGS: int = 8

## Spacing (metres) of the river samples laid over a candidate footprint disc.
##
## The sampling is CONSERVATIVE, not merely fine: each sample stands for its whole
## cell, so the test is widened by BIOME_NOISE_MAX_SLOPE over half that cell's
## diagonal (see _tower_wet_samples). That makes the step a cost/tightness knob
## rather than a correctness one — a coarser grid is still safe, it just refuses
## more dry-ish sites. 2 m widens the band by ~1.4x, which is tight enough that the
## nominal site is usually still accepted, at ~830 samples per candidate: paid ONCE
## per run and then memoized, and in the common case for exactly one candidate.
##
## 5 m WAS TRIED AND IS WRONG WITHOUT THE MARGIN. A plain boolean grid at 5 m
## reported a dry site for run seeds 750, 99 and 106 that a 2 m sweep found 24, 1
## and 3 wet points in (codex review, 2026-08-28) — a river is only ~8 m wide where
## the field is shallow, and arbitrarily narrow where it is steep.
const TOWER_SAMPLE_STEP: float = 2.0

## How near the player must come to tower_site() before the shell is INSTANCED
## (metres). Phase 2's lazy-load radius.
##
## Generous on purpose, and the generosity is the whole design. The shell is one
## scene of nine boxes — a rounding error next to a chunk — so the cost of building
## it early is nothing, while the cost of building it LATE is a building popping
## into existence in front of the player. 320 m clears the desktop render distance
## (250 m) and both fog ranges by a wide margin, and it is checked only when the
## player crosses a CHUNK boundary (50 m), so the worst case still instances the
## tower ~270 m out — far past anything that can be seen.
##
## Below this radius the horizon impostor is what the player is looking at (see
## TowerShell.build_impostor), so the swap happens where neither is visible.
const TOWER_LOAD_RADIUS: float = 320.0

## The tower's authored scene. Instanced ONCE per run, parented to this manager and
## never to a chunk — the fauna precedent (CLAUDE.md): chunk unloading must not be
## able to free a building the player is standing in.
const TOWER_SHELL_SCENE: PackedScene = preload("res://scenes/tower/tower_shell.tscn")

## The tower's INTERIOR, added as a child of the shell the moment the shell is
## instanced (phase 3).
##
## IT IS ASSEMBLED HERE RATHER THAN INSIDE `tower_shell.tscn` FOR ONE REASON: the
## interior reads the shell's constants (`OUTER_HALF`, `WALL_THICK`) so its floor
## plan can never drift from the walls it is inside, and a shell that also referred
## to the interior would be a cyclic `class_name` dependency Godot refuses to load.
## One arrow, one direction — and this manager, which already owns the shell's
## lifetime, is the natural place to put the two together.
const TOWER_INTERIOR_SCENE: PackedScene = preload("res://scenes/tower/tower_interior.tscn")

## Chance (0..1) that a given walkable structure top (mound summit / wall ridge)
## gets a rare crocodile patrolling it. Kept moderate so they're an occasional
## surprise, not on every structure.
@export var platform_crocodile_chance: float = 0.4

## How far ABOVE a platform's `top` (its tallest stone, NOT the surface it paces)
## a patrol guard is dropped in, so gravity settles it onto the structure.
##
## THIS IS THE PENETRATION DEPTH WHEN THE DROP-IN HEIGHT IS WRONG, which is why
## it is a named constant rather than a literal at the one call site: a guard
## dropped from a height that some stone in its own footprint reaches ends up
## this far INSIDE that stone. See the platform "top" note in spawn_wall.
const PLATFORM_SPAWN_HEIGHT: float = 0.6

## How far in from a platform's edge the guard's spawn point is drawn, so it
## lands cleanly on the surface rather than half off it. Read by
## enemy_spawn_selfcheck.gd, which walks the same inset ellipse at every angle.
const PLATFORM_SPAWN_EDGE_INSET: float = 1.0

## Enable/disable collectible coin spawning on terrain
@export var spawn_coins: bool = true

## Coin placement heights (metres). Coins live on the COIN ROAD (see the section
## below), not scattered per chunk, so there are only two cases now:
## - road coins float just above the grass, grabbed by walking over them
## - when the road runs over a climbable block, the coin perches this far above
##   that block's top surface instead of being buried (see spawn_coins_in_chunk)
const COIN_GROUND_HEIGHT: float = 0.9
const COIN_BLOCK_OFFSET: float = 0.6

## Extra clearance (metres) added to a block's footprint radius when deciding whether
## a road coin sits "over" that block. The ~1 m margin makes the test hug slightly
## WIDER than the block itself, so a coin grazing a block's edge perches on top rather
## than clipping into the side. Shared by _point_over_block and the perch loop so the
## overlap rule has exactly one definition (see _block_overlaps).
const COIN_BLOCK_OVERLAP_MARGIN: float = 1.0

## Clearance (metres) added to every face of a tower box when deciding whether a
## road coin is inside the building (see tower_blocks_coin).
##
## A coin is a 0.35 m disc and a GEM is that times GEM_SCALE (1.6), i.e. 0.56 m at
## its widest — so a point test alone would leave a gem half-sunk into a wall face
## and still call it clear. 0.7 covers the widest pickup with margin, and errs the
## only direction that is safe: it drops a coin that was merely grazing the stone
## rather than leaving one embedded in it.
const COIN_TOWER_CLEARANCE: float = 0.7

# ----------------------------------------------------------------------------
# COIN ROAD CONFIGURATION (the meandering parametric trail that carries coins)
# ----------------------------------------------------------------------------
##
## EDUCATIONAL NOTE — what "the coin road" is and why it is built this way:
## Instead of scattering coins randomly per chunk (no direction, no journey), all
## coins live on ONE continuous road that snakes across the infinite world and
## always trends forward along +X. The road is a *parametric* path: we sample it
## at integer "station" indices `k` (one coin candidate per station). Station 0
## sits at the world origin (where the player spawns) heading straight along +X,
## so the player is on the road the instant the game starts.
##
## The whole shape is a PURE, DETERMINISTIC function of the station index `k` and the
## seeds (ROAD_WORLD_SEED + this run's run_seed, fixed for the duration of a run) —
## there is NO per-chunk RNG and NO per-frame state in the geometry. That is what lets
## the trail line up seamlessly across chunk seams and regenerate byte-for-byte
## identically when a chunk is revisited. A new run re-rolls run_seed, so the NEXT
## road takes a different path (see the run_seed doc block below).
##
## The path is built by integrating a heading angle station-by-station (see the
## recurrence in _road_extend_to_x). A gentle restoring pull and a hard heading cap
## (< 90°) keep the centerline's X STRICTLY INCREASING in `k`, so a chunk's X-range
## maps to a bounded, contiguous range of stations — which is what makes per-chunk
## coverage finite and seam-correct. The road still reads as a real road with broad
## curves, zig-zags and steep diagonal bends; it just never reverses net direction.

## World-metres between consecutive coin "slices" along the road centerline (the STEP
## of the path). Each slice scatters a few coins across the band, so this sets how often
## a new clump of coins appears as you travel — NOT the gap between individual coins.
## Larger = sparser road.
@export var road_coin_spacing: float = 6.0

## The coin BAND width (metres) varies smoothly between these bounds. Coins are scattered
## at RANDOM lateral offsets within ±band/2 of the centerline (NOT on a single line), so
## the road reads as a swath of territory a few coins wide rather than a conga-line. Bump
## these up for a wider, more spread-out trail; down for a tighter path. (~10–20 m shows
## roughly 3–4 coins across at the default density.)
@export var road_width_min: float = 10.0
@export var road_width_max: float = 20.0

## Coins CONSIDERED per slice, and the chance each one actually spawns. Average coins per
## slice = road_coin_slots * road_coin_chance. Lower the chance for a sparser, less obvious
## trail; raise it (or the slots) for a denser swath. Keeping the average near ~1 makes the
## band feel like scattered territory, not a carpet. Skipped slots are what give the road
## its irregular, "not so obvious" look.
@export var road_coin_slots: int = 3
@export var road_coin_chance: float = 0.4

## Maximum per-station heading jitter magnitude (degrees). Larger = curvier / tighter
## zig-zags. This is the amplitude of the deterministic turn noise added each station.
@export var road_turn_rate_deg: float = 18.0

## Heading cap measured from the +X axis (degrees). The integrated heading is clamped
## to ±this. MUST stay < 90° so cos(heading) is always > 0 and the centerline's X
## keeps increasing with `k` (asserted in _road_extend_to_x). 78° still allows steep,
## road-like diagonal bends while guaranteeing forward progress.
@export var road_max_heading_deg: float = 78.0

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

# ----------------------------------------------------------------------------
# BOSS CROCODILES (deterministic, station-indexed placement along the coin road)
# ----------------------------------------------------------------------------
## A boss crocodile stands on the road every BOSS_INTERVAL_STATIONS stations —
## at 6 m/station that's one boss roughly every 300 m of road. Boss index `i`
## (1, 2, 3, ...) owns station k = i * BOSS_INTERVAL_STATIONS; station 0 is the
## player spawn and the road trends +X, so only forward stations get bosses.
const BOSS_INTERVAL_STATIONS: int = 50

## Size schedule: boss `i` scales the whole croc body by
## min(BOSS_BASE_SCALE * (1 + (i-1) * BOSS_GROWTH), BOSS_MAX_SCALE)
## → 2.5, 3.375, 4.25, 5.125, 6.0, 6.0, ... Each boss is visibly bigger than the
## last until the cap. BOSS_BASE_SCALE (2.5x) is clearly bigger than the biggest
## regular croc's random +25% size roll, so a boss always reads as "not a normal one".
const BOSS_BASE_SCALE: float = 2.5
const BOSS_GROWTH: float = 0.35
const BOSS_MAX_SCALE: float = 6.0

## A small deterministic lateral offset off the centerline (±this, in meters), so
## bosses don't all stand dead-center on the road like a row of toll booths.
const BOSS_LATERAL_MAX: float = 4.0

## Spawn a bit AHEAD of the owning station along the road tangent, so the player
## sees the boss looming up the road rather than materializing beside them.
const BOSS_FORWARD_OFFSET: float = 8.0

## How much ground a boss actually occupies, per unit of body scale. The
## crocodile's collision capsule LIES DOWN (piglet_crocodile.tscn rotates the
## 1.4 m capsule onto its side), so its widest horizontal reach is half that
## length — 0.7 m at body scale 1. Multiplying by the boss's scale is the whole
## point: a 6x boss needs ~4.2 m of clearance from a block where a normal
## crocodile needs ~0.7, so the fixed min_object_clearance that the ordinary
## crocodile spawner uses would be far too small here.
const BOSS_FOOTPRINT_RADIUS_PER_SCALE: float = 0.7

## How many deterministic lateral candidates a boss tries before it is skipped
## entirely (the same "try a few spots, else give up" shape as artifacts). Every
## candidate comes from the SAME BOSS_SEED stream and the FIRST one is exactly
## the draw that existed before this list did, so the boss schedule (which
## station, what size) and the placement of every unobstructed boss are
## byte-for-byte what they were.
const BOSS_PLACE_TRIES: int = 4

## Fixed seed for the boss placement RNG — its OWN independent hash stream (like
## ROAD_COIN_SEED), mixed with the boss index and run_seed as
## hash(Vector3i(i, BOSS_SEED, run_seed)). It never consumes a draw from any
## existing chunk/coin/croc RNG sequence, so adding bosses regenerates the rest
## of the procedural world byte-for-byte identically.
const BOSS_SEED: int = 0xB0_55  # "BOSS"-ish; arbitrary fixed constant

## Fixed salt for the per-crocodile SIZE/SPEED roll seed — its OWN independent
## hash stream (the BOSS_SEED / ARTIFACT_SALT / CAMP_SALT pattern). See
## _croc_roll_seed() below: it consumes ZERO draws from the crocodile spawner's
## RNG, so every crocodile's POSITION is byte-for-byte what it was before the
## rolls were determinized — only the size/speed a crocodile rolls for itself
## changed, from "randomize() per instance" to "a pure function of chunk coords,
## croc index and run_seed".
const CROC_ROLL_SALT: int = 0xC20_C  # "CROC"-ish; arbitrary fixed constant

# ----------------------------------------------------------------------------
# ARTIFACTS (rare deterministic "lost civilization" landmarks, off the road)
# ----------------------------------------------------------------------------
##
## An artifact is a rare, weathered landmark (a leaning monolith, a broken arch,
## a stone circle, a half-buried colossus head, a spiral of steps) built entirely
## from the same block primitives as ordinary chunk scenery — its stone rides the
## chunk's MultiMesh + BlockCollision body, so it costs zero extra draw calls.
## Placement uses its OWN independent hash stream (the BOSS_SEED / ROAD_COIN_SEED
## pattern): a private RNG seeded from chunk coords + run_seed ^ ARTIFACT_SALT.
## It consumes NO draw from the shared chunk RNG, so on the ~19 of 20 chunks
## without an artifact the generated world is byte-for-byte identical to before.
##
## The determinism contract, spelled out:
## - INDEPENDENT STREAM: _artifact_at() is a pure function of chunk coords +
##   run_seed. No draw from the shared chunk RNG is consumed, inserted, or
##   moved — every existing block/crocodile/coin stays exactly where it was.
## - WITHIN A RUN: a revisited chunk regenerates the identical artifact (same
##   shape, same spot, same stones), just like blocks and crocodile positions.
## - ACROSS RUNS: new_run() re-rolls run_seed, so artifacts land elsewhere —
##   run 2 is a fresh world, artifacts included.
## - PER-CHUNK PARENTING: everything an artifact spawns (accents, coins, gem)
##   is a child of the chunk MeshInstance3D, so it unloads with the chunk and
##   nothing leaks.
## - RENDER SPLIT: all SOLID geometry routes through create_box into the
##   chunk's single MultiMesh + single BlockCollision body (zero extra draws,
##   zero extra bodies); only the GLOW accents are real MeshInstance3Ds — at
##   most ARTIFACT_MAX_ACCENTS of them, cast_shadow OFF.
##
## Honest deferral: an optional proximity "shimmer" hum per artifact was
## SKIPPED. sound_manager.get_loop_player() returns a non-positional
## AudioStreamPlayer, so a per-artifact 3D hum would need a new positional
## audio path plus a per-frame proximity scan against artifact centres —
## out of proportion to the quiet polish it buys.

## Kill switch, mirrors spawn_coins / spawn_crocodiles.
@export var spawn_artifacts: bool = true

## Per-chunk chance of ROLLING an artifact, before the candidate loop rejects
## spots on the road, in a river, or on stone already in the chunk. Measured
## survival across a 61x61 field is 59.5%, so 0.08 lands ~1 built artifact per 24
## chunks — the same rarity the 0.05 roll produced when placement was unchecked
## and the one-per-15-to-25 target band. Retuned alongside the overlap test: with
## rejections added and the chance left at 0.05 the rate fell to 1 per 38.
## Rarity is also the draw-call budget (see ARTIFACT_MAX_ACCENTS below).
const ARTIFACT_CHANCE: float = 0.08

## Fixed salt XORed into run_seed for the artifact hash stream — same spirit as
## BOSS_SEED / ROAD_COIN_SEED: an arbitrary constant that keeps this stream
## independent of every other deterministic spawn site.
const ARTIFACT_SALT: int = 0xA27_1FA

## Candidate spots tried inside a chunk before giving up (a try is rejected when
## it lands too close to the coin road, in a river, or on stone that is already
## there — see spawn_artifact_in_chunk, which owns the loop).
const ARTIFACT_PLACE_TRIES: int = 4

## Placement radius (metres) — the WIDEST footprint any of the five shapes can
## return, used by the candidate test because the real radius is only known once
## the builder has run. Bounded by the stone circle, the widest of the five:
##     stone circle: ring_r (4..6) + 1.0        -> 7.0   <- the max
##     arch:         radius (fixed 5.0) + 1.0   -> 6.0
##     spiral:       spiral_r (3..4) + 1.2      -> 5.2
##     colossus head: 3.2      monolith: 2.5
## Must stay under ARTIFACT_EDGE_MARGIN (12) or an artifact could straddle a chunk
## seam. Retune any builder's radius and this moves with it.
const ARTIFACT_RADIUS: float = 7.0

## Minimum lateral distance from the road centerline. The widest coin band
## half-width is road_width_max * 0.5 = 10, so 14 keeps artifacts clear of the
## coin swath (never on the road, always a deliberate detour) while still
## leaving them visible from it.
const ARTIFACT_ROAD_CLEARANCE: float = 14.0

## Keeps the whole artifact inside its chunk so nothing straddles a seam
## (an artifact is spawned and parented by exactly one chunk).
const ARTIFACT_EDGE_MARGIN: float = 12.0

## Weathered stone palette — deliberately DISTINCT from the curated block ramps
## (RAMP_SANDSTONE_* / RAMP_SLATE_* / RAMP_MOSS_*): neutral desaturated greys
## plus a dead-moss green, no warm sandstone undertone, no blue slate. The point
## is that an artifact reads as "from another age" next to ordinary blocks.
const ARTIFACT_STONE_A := Color(0.40, 0.41, 0.39)
const ARTIFACT_STONE_B := Color(0.60, 0.61, 0.58)
const ARTIFACT_MOSS := Color(0.33, 0.40, 0.30)
const ARTIFACT_MOSS_MAX: float = 0.35  # max lerp toward moss per stone

## Emissive accent glow: cold cyan — nothing else in the world is this colour.
## main.tscn has glow_enabled with glow_hdr_threshold = 0.85, so an emission
## energy of 3.0 pushes the accents over the threshold and they bloom for free.
const ARTIFACT_GLOW_COLOR := Color(0.45, 0.95, 1.0)
const ARTIFACT_GLOW_ENERGY: float = 3.0

## Hard cap on real emissive MeshInstance3Ds per artifact — the draw-call
## budget. Accents can't join the block MultiMesh (one shared non-emissive
## material), so each is a real instance; rarity × this cap keeps the worst
## case on screen to a handful of extra unshadowed draws.
const ARTIFACT_MAX_ACCENTS: int = 4

## Coin reward: 3-5 ordinary coins ring the artifact's base (ring radius =
## footprint radius + a pad in [PAD_MIN, PAD_MAX]) plus exactly one gem at the
## centre — the incentive to detour off the coin road.
const ARTIFACT_COIN_MIN: int = 3
const ARTIFACT_COIN_MAX: int = 5
const ARTIFACT_COIN_RING_PAD_MIN: float = 1.5
const ARTIFACT_COIN_RING_PAD_MAX: float = 4.0

# ----------------------------------------------------------------------------
# NOMAD CAMPS (rare dome-hut villages of caravan herders, off the road)
# ----------------------------------------------------------------------------
##
## A camp is a loose circle of 3-6 white/bone DOME huts (an igloo read, built from
## stacked shrinking box tiers) around a dark stone fire pit with one glowing
## ember, plus crates/bundles and tether posts. It is the ARTIFACTS section's twin
## in every structural way — its own independent hash stream, all solid geometry
## through create_box into the chunk's ONE MultiMesh + ONE BlockCollision body,
## one emissive MeshInstance3D for the ember — and differs only in flavour:
##
## - PALETTE: bone white huts + dark stone + weathered wood. Deliberately distinct
##   from BOTH the warm RAMP_* block ramps (sandstone/slate/olive) AND the
##   artifacts' desaturated grey-green: a camp should read as "someone LIVES here",
##   not "ruins".
## - EMBER: warm ORANGE, where the artifacts' accents are cold cyan. Two glows,
##   two meanings, no ambiguity at a distance.
## - NO GEM: a camp pays a couple of ordinary scattered coins. The guaranteed gem
##   stays the artifacts' distinction, so the two landmark types keep separate
##   reward identities.
## - CALM POCKET: the camp's single round footprint is what keeps crocodiles out
##   (see spawn_camp_in_chunk) — the herders' home is a place to breathe.
##
## Determinism contract: identical to the artifact one — pure function of chunk
## coords + run_seed, ZERO draws from the shared chunk RNG, so the ~30 of 31 chunks
## without a camp regenerate byte-for-byte as they did before camps existed.

## Kill switch, mirrors spawn_artifacts / spawn_biome_content / spawn_coins.
@export var spawn_camps: bool = true

## Per-chunk chance of hosting a camp, BEFORE the placement rejections in
## spawn_camp_in_chunk. Those rejections are severe and that is why this number
## looks large: a camp needs a CAMP_RADIUS (9.4 m) circle clear of the ~12
## scattered blocks a chunk already holds, and 12 exclusion discs of radius
## (9 + block radius) cover more than a chunk's area, so most tries lose. Measured
## over 5 x 121 startup chunks with the roll forced to 1.0: 14% of rolled camps
## survive all four tries (overlap rejects ~86% of failures, road and river the
## rest). 0.18 x 14% ≈ ONE CAMP PER 31 CHUNKS as actually built — measured over
## 8 x 121 chunks at this value, 31 camps — against the artifacts' ~1 per 24, so
## a village still reads as the rarer find. Retune by MEASURING, not by algebra:
## the survival rate depends on the block density the biome mix produces.
## (Those runs were measured at CAMP_RADIUS 9.0; the 9.4 it takes to bound the
## huts is marginally stricter, so the built rate is a shade under 1 in 31.)
const CAMP_CHANCE: float = 0.18

## Fixed salt XORed into run_seed for the camp hash stream — same spirit as
## ARTIFACT_SALT / BIOME_SALT / BOSS_SEED / ROAD_COIN_SEED: an arbitrary constant
## that keeps this stream independent of every other deterministic spawn site.
const CAMP_SALT: int = 0xCA_1117  # "CAMP"-ish; arbitrary fixed constant

## Candidate spots tried inside a chunk before giving up. The tries live in
## spawn_camp_in_chunk, not in _camp_at, so each one is judged by _biome_spot_ok
## against the finished obstacle list — the test that actually rejects. Kept at 4:
## raising it to 16 was measured at 36% survival vs 14%, but four cheap tries plus
## a higher CAMP_CHANCE reaches the same built rate, and letting crowded chunks
## lose is what puts camps in open ground where a village belongs.
const CAMP_PLACE_TRIES: int = 4

## Radius of the camp circle: the fire pit sits at the centre and the huts ring
## it, so this covers the whole village plus a walking margin. It MUST cover the
## widest hut on the outermost ring, because the same number is both the
## placement test (_biome_spot_ok) and the footprint appended afterwards:
##     CAMP_HUT_RING_MAX + (CAMP_HUT_WIDTH_MAX * 0.71 + 0.3)
##     6.5              + (3.6 * 0.71 + 0.3) = 9.36    <= 9.4  ✓
## At 9.0 the outer third of a metre of hut stone stood in ground the placement
## test never checked; 9.4 makes the circle a true bound, which is also why no
## per-hut footprint is appended (spawn_camp_in_chunk, step 5).
const CAMP_RADIUS: float = 9.4

## Minimum lateral distance from the coin-road centerline.
##
## INVARIANT — "no boss ever stands inside a camp". The camp test measures the
## distance to STATION CENTRES (that is all _road_lateral_distance computes), and
## a boss does NOT stand on its station centre: _boss_at offsets it
## BOSS_FORWARD_OFFSET (8.0 m) along the tangent AND up to BOSS_LATERAL_MAX
## (4.0 m) across it. Both legs must appear in the bound, or the invariant is
## checked against a number 8 m smaller than the real one:
##     CAMP_ROAD_CLEARANCE > CAMP_RADIUS + sqrt(BOSS_FORWARD_OFFSET^2 + BOSS_LATERAL_MAX^2)
##     22.0                > 9.4         + sqrt(8.0^2 + 4.0^2) = 9.4 + 8.94 = 18.34  ✓
## i.e. 3.66 m of slack, not the 8.6 the lateral leg alone suggests. (The real
## clearance is larger still — stations are only _road_spacing() 6 m apart, so
## the boss is in practice ~4.5 m from its NEAREST station centre rather than
## 8.94 — but the hypotenuse is the bound that holds without assuming anything
## about station spacing.) That inequality is the WHOLE boss exclusion —
## spawn_bosses_in_chunk needs no edit and no extra test. Re-check this line if
## ANY of the four constants named in it is retuned, BOSS_FORWARD_OFFSET included.
##
## 22 also clears the widest coin swath (road_width_max * 0.5 = 10 m) by a wide
## margin, so camp coins can never be confused with road coins.
const CAMP_ROAD_CLEARANCE: float = 22.0

## Keeps the whole camp inside its own chunk so no hut straddles a seam (same rule
## as ARTIFACT_EDGE_MARGIN). MUST exceed CAMP_RADIUS: 12.0 > 9.4 ✓.
## With chunk_size 50 that still leaves a 26x26 m placement box.
const CAMP_EDGE_MARGIN: float = 12.0

## --- Hut geometry: an igloo read from 2-3 stacked, shrinking box tiers.
const CAMP_HUT_MIN: int = 3
const CAMP_HUT_MAX: int = 6
const CAMP_HUT_RING_MIN: float = 4.0   # hut distance from the fire pit
const CAMP_HUT_RING_MAX: float = 6.5
const CAMP_HUT_WIDTH_MIN: float = 2.6  # widest (ground) tier
const CAMP_HUT_WIDTH_MAX: float = 3.6
const CAMP_HUT_TIER_MIN: int = 2
const CAMP_HUT_TIER_MAX: int = 3
const CAMP_HUT_TIER_HEIGHT: float = 0.9   # each tier's height
const CAMP_HUT_TIER_SHRINK: float = 0.62  # each tier's width vs the one below
const CAMP_HUT_YAW_JITTER: float = 0.25   # per-tier yaw wobble (radians)
## Door height MUST stay under CAMP_HUT_TIER_HEIGHT (0.9): the doorway sits on
## the ground tier's outer face, and the tier above is narrower (TIER_SHRINK), so
## anything taller than one tier pokes out over the roofline as a dark nub.
const CAMP_HUT_DOOR_SIZE := Vector3(0.7, 0.8, 0.5)

## --- Fire pit: a ring of small dark stones + one emissive ember at the centre.
const CAMP_FIRE_STONES: int = 7
const CAMP_FIRE_RING_RADIUS: float = 1.1
const CAMP_FIRE_STONE_SIZE := Vector3(0.45, 0.35, 0.45)
const CAMP_EMBER_SIZE := Vector3(0.6, 0.35, 0.6)

## --- Props: crates/bundles and tall thin tether posts on a ring between the
## fire and the huts.
const CAMP_CRATE_MIN: int = 3
const CAMP_CRATE_MAX: int = 6
const CAMP_CRATE_SIZE_MIN: float = 0.5
const CAMP_CRATE_SIZE_MAX: float = 0.9
const CAMP_POST_MIN: int = 2
const CAMP_POST_MAX: int = 3
const CAMP_POST_SIZE := Vector3(0.22, 1.8, 0.22)
const CAMP_PROP_RING_MIN: float = 2.0
const CAMP_PROP_RING_MAX: float = 4.0

## --- Palette. Bone white for the hut shells (a spot on A→B per tier), near-black
## stone for the fire ring, weathered brown for wood. See the banner above: this
## is deliberately neither the warm RAMP_* ramps nor the artifacts' grey-green.
const CAMP_HUT_A := Color(0.88, 0.87, 0.82)
const CAMP_HUT_B := Color(0.74, 0.73, 0.69)
const CAMP_STONE := Color(0.22, 0.21, 0.20)
const CAMP_WOOD := Color(0.42, 0.31, 0.20)

## Ember glow: WARM ORANGE (the artifacts' accents are cold cyan). main.tscn's
## glow_hdr_threshold is 0.85, so an energy of 2.5 blooms for free.
const CAMP_EMBER_COLOR := Color(1.0, 0.55, 0.18)
const CAMP_EMBER_ENERGY: float = 2.5

## Coin reward: a couple of scattered coins near the fire. NO gem — see the banner.
const CAMP_COIN_MIN: int = 2
const CAMP_COIN_MAX: int = 4

# ----------------------------------------------------------------------------
# TREASURE CHESTS (small, common, opened on touch for a coin shower)
# ----------------------------------------------------------------------------
##
## The third landmark in the artifact / camp family, and deliberately the SMALLEST
## and COMMONEST of the three — a snack, not a monument. The reward hierarchy is
## the whole reason each exists at its own rarity:
##
##   artifact  ~1 chunk in 23  huge ruin, 3-5 coins AND the one guaranteed GEM
##   camp      ~1 chunk in 31  a whole village, 2-4 coins, no gem
##   chest     ~1 chunk in 13  a 1.3 m box, 8-15 coins in a burst, NO GEM
##
## A chest gets NO gem for exactly the reason a camp gets none: the guaranteed gem
## is the artifacts' distinction, and handing one to the commonest landmark in the
## world would flatten "an ancient prize worth a detour" into "a box I walked past".
##
## Structurally this is the artifact/camp recipe with nothing added:
##   - _chest_at()          the rarity roll ALONE, on its own independent hash
##                          stream (CHEST_SALT + its own coordinate primes), so it
##                          consumes ZERO draws from the shared chunk RNG.
##   - spawn_chest_in_chunk() holds the candidate loop, because that is the only
##                          place `obstacles` exists — see _chest_at's docstring
##                          for why putting the loop in the roll is the bug both
##                          artifacts and camps had to have moved out of it.
##   - all wood and brass goes through create_box into the chunk's ONE MultiMesh
##     and ONE BlockCollision body, so a chest costs ZERO extra draw calls and
##     ZERO extra physics bodies. Its single non-batched node is the open trigger.
##
## OPENED STATE IS PER-RUN AND CHUNK-LOCAL, ON PURPOSE. A chest is rebuilt closed
## when its chunk unloads and regenerates — there is no opened-chest registry.
## That is exactly what ROAD COINS already do (they respawn with their chunk too),
## and the road's strictly-increasing X (see the coin-road section) makes walking
## far enough backwards to re-farm a chest a deliberate, slow act rather than an
## accident. A registry would need per-run persistence keyed by a stable chest id
## and would buy nothing a player would notice; skipped.

## Kill switch, mirroring spawn_artifacts / spawn_camps.
@export var spawn_chests: bool = true

## Probability that a chunk ROLLS a chest. This is NOT the built rate: the
## candidate loop below rejects spots that are in a river, too near the coin road,
## or overlapping stone already in the chunk.
##
## MEASURED (throwaway headless generator sweep, 41x41 = 1681 chunks, run_seed
## 12345): 136 chunks rolled a chest and 134 BUILT one — 98.5% survival, i.e.
## 1 built chest per 12.5 chunks, inside the intended 1-in-12-to-15 band.
##
## Survival is that high because CHEST_RADIUS (1.5 m) is a sixth of a camp's 9.4
## and a fifth of an artifact's 7.0: the overlap test, which rejects 86% of camp
## candidates, almost never fires on something this small, and four tries make the
## remaining road/river rejections cheap. Survival barely moves with the chance, so
## the built rate scales essentially linearly — 0.05 would give ~1 in 20, 0.14 ~1
## in 7. Note 0.08 is coincidentally the same number as ARTIFACT_CHANCE and means
## something completely different there: an artifact survives placement only 59.5%
## of the time, so the same roll yields 1 in 23.
const CHEST_CHANCE: float = 0.08

## Salt for the chest's independent hash stream, in the ARTIFACT_SALT / CAMP_SALT /
## BIOME_SALT / BOSS_SEED family: an arbitrary fixed constant XORed into run_seed so
## this stream can never collide with (or perturb) any other deterministic site.
const CHEST_SALT: int = 0xC4_E57  # "CHEST"-ish; arbitrary fixed constant

## Coordinate multiplier primes for the chest stream, deliberately DIFFERENT from
## every other stream in this file — object/artifact (73856093 / 19349663), camp
## (40960001 / 26463089), biome (83492791 / 15485863) and croc-roll (179424673 /
## 32452843) — so no two streams can correlate on a shared lattice.
const CHEST_HASH_PRIME_X: int = 86028121
const CHEST_HASH_PRIME_Y: int = 50331653

## Candidate spots tried before giving up on this chunk's chest. Every try failing
## means NO chest — a chest fused into a mountain massif is worse than no chest, and
## a higher CHEST_CHANCE reaches the same built rate.
const CHEST_PLACE_TRIES: int = 4

## Footprint radius, and the value handed to _biome_spot_ok as "the widest this
## could be". The chest box is 1.3 x 0.9 m, whose rotated half-diagonal is 0.79 m;
## 1.5 rounds that generously up so a chest never quite touches a neighbouring
## block, and it is also the radius of the obstacle appended to `obstacles`
## (crocodile spawn rejection + the road-coin perch rule).
const CHEST_RADIUS: float = 1.5

## Minimum distance from the coin-road CENTERLINE. Equal to road_width_max / 2
## (10 m), the outer edge of the widest coin scatter band, so a chest is never
## standing in the middle of the trail you are already following — it always sits
## at the swath's edge or beyond, which is what makes finding one feel like
## looking around rather than walking forward. A road coin CAN still perch on the
## lid at the exact boundary; that is harmless because the chest footprint is
## climbable (see spawn_chest_in_chunk).
const CHEST_ROAD_CLEARANCE: float = 10.0

## Keep candidate spots this far inside the chunk. MUST exceed CHEST_RADIUS (1.5)
## so no chest box straddles a seam, and it also exceeds TreasureChest's
## TRIGGER_RADIUS (2.0) so the whole pickup volume stays in its own chunk.
const CHEST_EDGE_MARGIN: float = 4.0

## Chest geometry (metres). The body is a squat box, the lid a slab tilted open.
const CHEST_BODY_SIZE := Vector3(1.3, 0.75, 0.9)
const CHEST_LID_SIZE := Vector3(1.36, 0.26, 0.96)
## How far the lid leans back off the body, radians about its local X axis. Enough
## to read as "already ajar" at a distance without looking knocked off.
const CHEST_LID_TILT_MIN: float = 0.35
const CHEST_LID_TILT_MAX: float = 0.6
## The brass band across the chest's waist. Visual only (collide = false) — it is
## 6 cm of trim and the body box underneath already carries the collision.
const CHEST_BAND_SIZE := Vector3(1.34, 0.14, 0.94)

## Palette — dark oiled wood and warm brass, deliberately distinct from the warm
## RAMP_* block ramps, the artifacts' grey-green stone and the camps' bone white.
const CHEST_WOOD := Color(0.30, 0.19, 0.11)
const CHEST_BRASS := Color(0.72, 0.55, 0.20)

## Payout: how many SINGLE-coin awards a chest pays, and over how long. The count
## is drawn from the chest's own seeded RNG, so it is deterministic within a run.
## See treasure_chest.gd for why this is N x collect_coin(1) and never
## collect_coin(N): the streak machinery counts pickups, not value.
const CHEST_COINS_MIN: int = 8
const CHEST_COINS_MAX: int = 15
## Comfortably inside the player's STREAK_WINDOW (2.5 s), so the whole burst is
## one unbroken streak chain.
const CHEST_BURST_DURATION: float = 0.8

## The chest's one non-batched node.
const TREASURE_CHEST_SCRIPT := preload("res://scripts/treasure_chest.gd")

# ----------------------------------------------------------------------------
# GEO LANDMARKS (rare recognizable famous places)
# ----------------------------------------------------------------------------
##
## The FOURTH member of the artifact / camp / chest landmark family, and the one
## that carries the game's educational identity: walk far enough and you come over
## a rise to find Stonehenge, the Moai of Easter Island, the Pyramids of Giza, the
## Golden Gate Bridge, the Statue of Liberty, the Plaza Mayor, the Eiffel Tower or
## the Taj Mahal, and a small card tells you one true thing about it.
##
## The bar the owner set is "not necessarily ideal, but RECOGNIZABLE": blocky
## code-built sculpture in the house style, read at a glance from 30 m away, not
## an architectural model. Every builder therefore spends its box budget on the
## one or two silhouette features a person actually identifies the place by (the
## trilithons, the brow line, the stepped triangle, the orange towers and cable,
## the crown and torch, the arcade, the four splayed legs, the dome and minarets)
## and nothing at all on detail that vanishes at distance.
##
## The reward hierarchy this slots into, and why each rarity is what it is:
##
##   chest     ~1 chunk in 13   a 1.3 m box, 8-15 coins in a burst, NO GEM
##   artifact  ~1 chunk in 23   huge ruin, 3-5 coins AND the one guaranteed GEM
##   camp      ~1 chunk in 31   a whole village, 2-4 coins, no gem
##   landmark  ~1 chunk in 40-60  a famous place, 3-5 coins, NO GEM, plus a fact
##
## REWARD DECISION — a small coin ring (LANDMARK_COIN_MIN..MAX, 3-5 ordinary
## coins) and DELIBERATELY NO GEM. This is exactly the rule that kept gems out of
## camps and chests: the guaranteed gem is the ARTIFACTS' distinction, and a
## fourth source of one would flatten "an ancient prize worth a detour" into
## "another thing I walked past". But a landmark sits LANDMARK_ROAD_CLEARANCE
## (22 m) off the coin road, so a destination with no reward at all is a trap that
## teaches players not to detour — and the detour is the whole feature. A ring
## without a gem pays for the walk without touching the hierarchy above it. The
## real reward is the card (see scripts/landmark_toast.gd); the coins are the
## apology for the distance.
##
## Structurally this is the chest/camp/artifact recipe with NOTHING added:
##   - _landmark_at()             the rarity roll ALONE, on its own independent
##                                hash stream (LANDMARK_SALT + its own coordinate
##                                primes), so it consumes ZERO draws from the
##                                shared chunk RNG.
##   - spawn_landmark_in_chunk()  holds the candidate loop, because that is the
##                                only place `obstacles` exists — see
##                                _landmark_at's docstring for why putting the
##                                loop in the roll is the bug BOTH artifacts and
##                                camps had to have dug out of them.
##   - all stone goes through create_box into the chunk's ONE MultiMesh and ONE
##     BlockCollision body, so a whole Eiffel Tower costs ZERO extra draw calls
##     and ZERO extra physics bodies. The only non-batched nodes a landmark may
##     add are at most ONE emissive accent (three of the eight builders spend it;
##     see the accent-budget note by LANDMARK_EDGE_MARGIN) and one script-free
##     marker Node3D (which has no mesh and no physics either).
##
## THE REGISTRY AND THE BUILDERS LIVE IN scripts/landmark_builders.gd, NOT HERE.
## That file holds the palette, the LANDMARKS registry (pure data — builder method
## NAME, English name, English fact, footprint radius) and one static builder per
## place; this file holds the POLICY that places them: how rare they are, which
## hash stream decides it, how far off the road they sit, how the reward ring and
## the crocodile-exclusion footprint are sized. Adding a famous place is ONE
## builder function, ONE registry entry and TWO ui.csv rows, and touches nothing
## in this file, in the toast, or in the self-check.
##
## ponytail: NO per-landmark ambient audio — the same deferral, for the same
## reason, that the artifacts recorded above. sound_manager.get_loop_player()
## returns a NON-POSITIONAL AudioStreamPlayer, so a monument hum that grew as you
## approached the Eiffel Tower would need a whole new positional audio path
## (AudioStreamPlayer3D, which nothing in this project uses yet) plus a per-frame
## proximity scan against landmark centres — out of proportion to the quiet
## polish it buys, and the toast already marks the arrival. Upgrade path: an
## AudioStreamPlayer3D parented to the marker Node3D that spawn_landmark_in_chunk
## already creates, which then frees with the chunk for free.

## Kill switch, mirroring spawn_artifacts / spawn_camps / spawn_chests. The
## measurement sweep needs it to generate the same field with and without
## landmarks and diff the two.
@export var spawn_landmarks: bool = true

## Probability that a chunk ROLLS a landmark. This is NOT the built rate: the
## candidate loop in spawn_landmark_in_chunk rejects spots that are in a river,
## too near the coin road, or overlapping stone already in the chunk — and a
## 9.5 m circle is camp-sized, so the overlap test rejects a great deal.
##
## MEASURED, never derived by algebra — the survival rate depends on the block
## density the biome mix happens to produce, which is why every sibling constant
## carries its own number (CAMP_CHANCE 0.18 -> 14% survival -> 1 per 31;
## CHEST_CHANCE 0.08 -> 98.5% -> 1 per 12.5, the same roll meaning wildly
## different things). Throwaway headless sweep over a 41x41 = 1681 chunk field
## with every spawner that runs BEFORE this one on (crocodiles and coins spawn
## after it and cannot reach its candidate loop): 224 chunks ROLLED a landmark
## and 32 BUILT one — 14.3% survival, 1 built landmark per 52.5 chunks, all
## eight kinds appearing.
##
## MEASURE ACROSS SEEDS, NOT ONE. That first figure is a SINGLE run_seed, and the
## rate is far more seed-dependent than the sibling constants' are, because what
## rejects a candidate here is overlap with a chunk's biome content — so a seed
## whose biome offset lands more of the field in sparse desert builds many more
## landmarks than one that lands it in forest. Five further seeds over 25x25 = 625
## chunks each: 1 per 52.1, 28.4, 41.7, 56.8 and 52.1 (survival 12.4-25.0%).
## AGGREGATED over all six sweeps — 4806 chunks, 673 rolled, 104 built — that is
## 15.5% survival and 1 built landmark per 46.2 chunks, inside the intended
## 1-per-40-60 band and deliberately rarer than the artifacts' 1-in-23, because
## these are destinations rather than scenery. So 0.15 stands as measured, with
## the honest caveat that any ONE world sits somewhere in 1-per-28..57.
## Survival is camp-like (~15%) rather than chest-like (98.5%) for the same reason
## a camp's is: the overlap test rejects almost everything for a 9.5 m circle and
## almost nothing for a 1.5 m one.
## Re-measure this pair — over SEVERAL seeds — if the radius, the clearances or
## the biome mix change.
##
## WAVE 3 RETUNE, 0.15 -> 0.19, AND IT IS NOT ABOUT THE KIND COUNT. Adding kinds
## cannot move the built rate at all — _landmark_at draws randf() then
## randi_range(0, size - 1), and randi_range consumes exactly one draw whatever
## its range, so the seed handed to the spawner and therefore the SPOT are
## bit-identical however many places exist (measured again at 28 kinds: over a
## 17x17 field x 6 seeds the same 30 chunks built a landmark before and after,
## and 1704/1704 landmark-free chunks were byte-identical). What moved is the
## judgement about where in the intended 1-per-40-60 band this should sit.
##
## MEASURED ON THIS BRANCH, one harness, all three rows the same 17x17 field:
##   18 kinds, chance 0.15, 40 seeds (11560 chunks): 1652 rolled, 201 built —
##      12.2% survival, 1 per 57.5
##   28 kinds, chance 0.15, 60 seeds (17340 chunks): 2487 rolled, 309 built —
##      12.4% survival, 1 per 56.1  (unchanged, as the paragraph above requires)
##   28 kinds, chance 0.19, 60 seeds (17340 chunks): 3217 rolled, 402 built —
##      12.5% survival, 1 per 43.1
## Survival is flat across all three because the candidate loop judges a spot
## against the chunk's geometry and knows nothing about how often it is asked, so
## the rate scales with the chance almost exactly: 56.1 * 0.15 / 0.19 = 44.3
## predicted against 43.1 measured. 0.15 had drifted to the SPARSE EDGE of the
## band while each individual place got 28 times rarer than it was at eight kinds;
## 0.19 puts the category back in the middle of the band (1 per 43) without
## touching the "landmarks are destinations, not scenery" rarity that keeps them
## well behind the artifacts' 1-in-23.
##
## WAVE 4 (the German pack, 28 -> 38 kinds): SWEPT AGAIN AND NOT RETUNED. The
## epic's rule is to re-measure at every new kind count, and this time the sweep
## was pointed straight at the claim the paragraph above makes rather than at the
## rate — because the rate is the thing that claim says CANNOT move, and a rate
## measured on a different harness cannot tell the two apart.
##
## So the harness digested the whole BUILT SET — every built chunk's coords and
## its landmark's spot to a millimetre, over the same 17x17 field x 60 seeds
## (17340 chunks) — and was run twice against the same code, once with all 38
## registry entries and once with the ten wave-4 entries cut back out:
##   38 kinds: 3245 rolled, 357 built, digest 4242030217
##   28 kinds: 3245 rolled, 357 built, digest 4242030217
## BIT-IDENTICAL. Not "the same rate" — the same chunks, in the same places. That
## is randi_range consuming exactly one draw whatever its range, measured rather
## than argued, and it is the property that makes appending kinds free forever.
##
## The rate that harness reports is 11.0% survival, 1 per 48.6 — inside the
## intended 1-per-40-60 band, so LANDMARK_CHANCE stayed at 0.19 there. It is NOT
## comparable to the three rows above (different harness: coins, chests and
## crocodiles disabled, and its own seed set), which is precisely why the digest
## is the measurement that decided this and the rate is only the sanity check.
##
## WAVE 5 RETUNE, 0.19 -> 0.21 (38 -> 48 kinds, the epic's target reached). The
## digest was re-run FIRST, because no rate means anything until the append-is-free
## property is confirmed at the new kind count: same 17x17 field x 60 seeds (17340
## chunks), run twice against the same code, once with all 48 registry entries and
## once with landmark_builders.gd checked back out at 38:
##   48 kinds: 3286 rolled, 359 built, digest 403935944
##   38 kinds: 3286 rolled, 359 built, digest 403935944
## BIT-IDENTICAL again — the same chunks, in the same places, to the millimetre.
##
## THEN THE RATE, swept on that same harness across three chances. Survival is flat
## across all three, as it has to be: the candidate loop judges a spot against the
## chunk's geometry and knows nothing about how often it is asked.
##   0.19: 3286 rolled, 359 built — 10.9% survival, 1 per 48.3
##   0.21: 3646 rolled, 391 built — 10.7% survival, 1 per 44.3
##   0.23: 3958 rolled, 424 built — 10.7% survival, 1 per 40.9
## The 0.19 row is what forced the change, and NOT because the kind count moved —
## it cannot, and that is now measured twice. It is that this harness puts 0.19 at
## 1 per 48.3, the SPARSE END of the band, while the wave-3 retune that chose 0.19
## believed on its own cruder harness that it was setting 1 per 43 — "the middle of
## the band", in that paragraph's own words. 0.21 is the smallest step that makes
## the constant match the intent already written beside it: 1 per 44.3 measured,
## mid-band, and still 1.9x rarer than the artifacts' 1-in-23, which is the
## "destinations, not scenery" margin every one of these retunes has protected.
##
## 0.23 WAS MEASURED AND NOT TAKEN. It hits the epic's "1-per-40-ish" phrasing
## exactly, but taking it would move the design target from mid-band to the dense
## end — a judgement the sweep does not force. The sweep only shows where 0.19
## actually landed, so the retune goes only as far as that.
const LANDMARK_CHANCE: float = 0.21

## Fixed salt XORed into run_seed for the landmark hash stream, in the
## ARTIFACT_SALT / CAMP_SALT / CHEST_SALT / BIOME_SALT / BOSS_SEED family: an
## arbitrary fixed constant that keeps this stream independent of every other
## deterministic spawn site, so it can never collide with (or perturb) one.
const LANDMARK_SALT: int = 0x1A_D3A2C  # "LANDMARK"-ish; arbitrary fixed constant

## Coordinate multiplier primes for the landmark stream, deliberately DIFFERENT
## from every other stream in this file — object/artifact (73856093 / 19349663),
## camp (40960001 / 26463089), biome (83492791 / 15485863), chest (86028121 /
## 50331653) and croc-roll (179424673 / 32452843) — so no two streams can
## correlate on a shared lattice (which would put, say, every landmark in a
## chunk that also rolled a camp).
const LANDMARK_HASH_PRIME_X: int = 32452867
const LANDMARK_HASH_PRIME_Y: int = 49979687

## Candidate spots tried inside a chunk before giving up. Every try failing means
## NO LANDMARK — the same call artifacts and camps both make, and the right one:
## the Eiffel Tower sticking out of a mountain massif reads far worse than a
## chunk without one, and a higher LANDMARK_CHANCE reaches the same built rate.
const LANDMARK_PLACE_TRIES: int = 4

## The WIDEST footprint any registry entry may declare, and therefore the value
## handed to _biome_spot_ok as "the widest this thing could be" — the house rule,
## because the real shape is only known after its builder has run. Every
## LandmarkBuilders.LANDMARKS[i].radius must be <= this; landmark_selfcheck.gd
## asserts both that and that each declared radius is a TRUE BOUND on the stone
## its builder emits.
##
## IT IS A GLOBAL BOUND, SO IT ONLY MOVES WHEN THE WIDEST PLACE DOES. Every entry
## added since it was set fits under 9.5 by design (the widest is the Colosseum's
## 9.4), which is why the whole inequality chain hanging off it — the edge margin,
## the boss-exclusion road clearance, the coin-ring pad — is untouched by a wave
## of new landmarks. Raising it is not a one-line change: LANDMARK_ROAD_CLEARANCE
## and LANDMARK_EDGE_MARGIN both have to be re-derived from it (see their own
## comments, and the four inequalities landmark_selfcheck.gd re-checks).
const LANDMARK_RADIUS: float = 9.5

## Minimum lateral distance from the coin-road centerline.
##
## INVARIANT — "no boss ever stands inside a landmark", exactly the camp's
## arithmetic. The test measures distance to STATION CENTRES (that is all
## _road_lateral_distance computes), and a boss does NOT stand on its station
## centre: _boss_at offsets it BOSS_FORWARD_OFFSET (8.0 m) along the tangent AND
## up to BOSS_LATERAL_MAX (4.0 m) across it, so BOTH legs belong in the bound:
##     LANDMARK_ROAD_CLEARANCE > LANDMARK_RADIUS + sqrt(BOSS_FORWARD_OFFSET^2 + BOSS_LATERAL_MAX^2)
##     22.0                    > 9.5             + sqrt(8.0^2 + 4.0^2) = 9.5 + 8.94 = 18.44  ✓
## i.e. 3.56 m of slack, NOT the 8.5 the lateral leg alone suggests. That single
## inequality IS the whole boss exclusion — spawn_bosses_in_chunk needs no edit
## and no extra test. Re-check this line if ANY of the four constants named in it
## is retuned, BOSS_FORWARD_OFFSET included.
##
## 22 is also comfortably above road_width_max / 2 (10 m), the outer edge of the
## widest coin scatter band, so the coin swath stays clear of the stone and a
## landmark reads as an OFF-ROAD DESTINATION you deliberately detour to rather
## than something you trip over while following the trail.
const LANDMARK_ROAD_CLEARANCE: float = 22.0

## Keeps the whole landmark inside its own chunk so nothing straddles a seam
## (same rule as ARTIFACT_EDGE_MARGIN / CAMP_EDGE_MARGIN).
## MUST exceed LANDMARK_RADIUS: 12.0 > 9.5 ✓ — landmark_selfcheck.gd asserts it.
## With chunk_size 50 that still leaves a 26x26 m placement box, so landmarks
## spread around their chunk instead of piling into its centre.
const LANDMARK_EDGE_MARGIN: float = 12.0

## THE EMISSIVE-ACCENT BUDGET IS A RULE FOR BUILDER AUTHORS, NOT A CONSTANT.
## An accent is a real extra MeshInstance3D and therefore a real extra DRAW CALL,
## which is the one cost that does not batch — so a builder spends at most ONE,
## and only where a real light belongs (Liberty's torch, the Eiffel beacon, Giza's
## gilded capstone; the other five spend none). This was a `const` of 4 for one
## commit, which was a comment wearing a type: nothing read it, no builder or
## dispatch path enforced it, and a const nothing checks is worse than a sentence
## because it reads like a guard. If a budget ever needs ENFORCING, count the
## _spawn_artifact_accent calls in spawn_landmark_in_chunk rather than re-adding a
## number beside them.

## Coin reward: a small ring round the base. NO GEM — see the banner above.
const LANDMARK_COIN_MIN: int = 3
const LANDMARK_COIN_MAX: int = 5
## How far outside the shape's own radius the ring sits, so the coins are found
## by walking AROUND the landmark rather than by clipping into it.
##
## THE MAX IS BOUNDED BY THE EDGE MARGIN, NOT CHOSEN BY EYE, and this is the one
## place the landmark recipe could NOT just copy the artifacts'. A landmark centre
## sits at most (chunk_size / 2 - LANDMARK_EDGE_MARGIN) from the chunk centre on
## each axis, so a reward coin stays inside its own chunk only while
##     LANDMARK_RADIUS + LANDMARK_COIN_RING_PAD_MAX <= LANDMARK_EDGE_MARGIN
## i.e. 9.5 + 2.0 = 11.5 <= 12.0 ✓ (landmark_selfcheck.gd asserts it). The
## artifacts' identical 1.5/4.0 pair is safe there only because ARTIFACT_RADIUS is
## 7.0 (7.0 + 4.0 = 11.0 < 12.0); at the landmarks' camp-sized 9.5 the same pair
## reached 13.4 and a coin near a chunk edge could land OUTSIDE the chunk that
## owns it — settled by _settle_coin_y against a footprint list describing the
## wrong ground, and freed when the wrong chunk unloads. Rare (0 hits in a 41x41
## sweep: it needs a landmark near an edge midpoint AND a large pad roll) but the
## bound costs nothing, so it is a bound rather than a note.
const LANDMARK_COIN_RING_PAD_MIN: float = 1.5
const LANDMARK_COIN_RING_PAD_MAX: float = 2.0


# ----------------------------------------------------------------------------
# BIOME FIELD CONFIGURATION (desert / plains / forest / mountain + rivers)
# ----------------------------------------------------------------------------
##
## ponytail: the ground stays a FLAT y = 0 plane. Mountains are block massifs you
## walk AROUND and rivers are flat tinted wading bands, because a real heightfield
## would break coin heights (COIN_GROUND_HEIGHT), the coin-road placement, the
## crocodiles' gravity settle, the player spawn at (0, 2, 0) and the per-chunk box
## ground collision all at once. Upgrade path if a real heightfield is ever wanted:
## give the ground mesh vertex displacement plus a MATCHING CPU height function,
## then make every y-placement site (COIN_GROUND_HEIGHT, croc spawn y, the spawn
## point, block bases) ask that function instead of assuming 0.
##
## The whole biome system is ONE octave of world-space value noise (see
## _biome_noise below). Thresholding its 0..1 output gives the six bands; a thin
## CONTOUR of it (|n - RIVER_LEVEL| < RIVER_HALF_WIDTH) gives winding rivers for
## free — a river is wherever the field crosses one particular level, which is
## exactly the shape of a contour line on a map: long, winding, and never a blob.

## Kill switch for all biome GEOMETRY (cacti, trees, mountain massifs), mirroring
## spawn_artifacts / spawn_coins. The biome FIELD itself (ground tint, rivers,
## wading) is not affected — this only silences the content spawner.
@export var spawn_biome_content: bool = true

## Enum for readability at every call site (biome_at returns one of these).
## NOTE: there is deliberately no Biome.RIVER — a river is an OVERLAY on whatever
## biome the ground under it is, tested separately with is_river_at().
##
## CITY IS APPENDED, NEVER INSERTED, even though its BAND sits between plains and
## forest. The enum's integer values index tables outside this file —
## minimap_hud.gd's BIOME_NAMES is the live one — so inserting CITY at position 2
## would silently relabel every forest and mountain on the map. Band ORDER is a
## property of the thresholds in biome_at(), not of the enum's numbering.
## SNOW follows the same rule and happens to be appended in band order anyway (it
## is the topmost band); that is a coincidence, not a licence to insert the next one.
enum Biome { PLAINS, DESERT, FOREST, MOUNTAIN, CITY, SNOW }

## Fixed salt XORed into run_seed for every biome hash stream — same spirit as
## ARTIFACT_SALT / BOSS_SEED / ROAD_COIN_SEED: an arbitrary constant that keeps
## this stream independent of every other deterministic spawn site.
const BIOME_SALT: int = 0xB10_11E

## Salt for desert oasis placement decisions (independent hash stream).
const OASIS_SALT: int = 0x0A_5157  # "OASIS" ish

## Salt for desert dune placement decisions (independent hash stream).
const DUNE_SALT: int = 0xD0_1D4E  # "DUNE" ish

## Noise wavelength in metres. Chunks are 50 m, so a biome cell spans ~8 chunks:
## big enough that you walk through a region rather than past it, small enough
## that a ~1 km run crosses several.
const BIOME_CELL_SIZE: float = 400.0

## Thresholds splitting the 0..1 noise into the six bands:
##   n < DESERT_MAX          -> DESERT
##   n < PLAINS_MAX          -> PLAINS   (still the widest band: the shipped look
##   n < CITY_MAX            -> CITY      stays the most common thing you see)
##   n < FOREST_MAX          -> FOREST
##   n < MOUNTAIN_MAX        -> MOUNTAIN
##   otherwise               -> SNOW     (the rarest — above the treeline)
##
## EVERY BAND SPLIT IN THIS FILE HAS BEEN MEASURED, NEVER GUESSED. Value noise is
## bell-shaped around 0.5, so a band's AREA share is nothing like its threshold
## width and the only honest way to place a new band is to sample the real field.
## Over 1.44 M samples spread across 16 run seeds:
##
##   4-band  (0.34 / 0.62  / —    / 0.82 / —   )  desert 27.4  plains 42.8  city  0.0  forest 23.1  mtn 6.7  snow 0.0
##   5-band  (0.34 / 0.575 / 0.66 / 0.82 / —   )  desert 27.4  plains 36.3  city 12.1  forest 17.5  mtn 6.7  snow 0.0
##   THIS    (0.34 / 0.575 / 0.66 / 0.75 / 0.83)  desert 27.4  plains 36.3  city 12.1  forest 10.7  mtn 7.6  snow 6.0
##
## THE SNOW BAND WAS CUT OUT OF FOREST, NOT OUT OF MOUNTAIN, and that is forced by
## the arithmetic rather than chosen: the whole shipped tail above BIOME_FOREST_MAX
## was only 6.7% of the world, so carving snow off the TOP of mountain (the obvious
## reading of "snow above the treeline") would have left mountain at 1-2% — a band
## you would go a run without seeing. Instead the treeline moved DOWN
## (BIOME_FOREST_MAX 0.82 -> 0.75), which widens the cold tail, and the tail is then
## split at BIOME_MOUNTAIN_MAX 0.83 into rock below and snow above. Mountain comes
## out slightly MORE common than it shipped (6.7 -> 7.6%), snow lands at 6.0% (the
## bottom of the 6-10% the design asked for), and desert / plains / city are
## byte-identical because none of their thresholds moved. Walking +X, a snow region
## is crossed every ~3131 m on average (median gap 2255 m) and the crossing itself
## runs ~267 m (median 215 m) — a long trudge across a cold place, which is the
## read a tundra wants.
##
## THREE INEQUALITIES TO RE-CHECK IF THESE MOVE (prop_selfcheck.gd asserts all of
## them, so a retune that breaks one fails in CI rather than in a screenshot):
##   1. RIVER_LEVEL (0.5) must stay strictly inside the PLAINS band, i.e.
##      BIOME_DESERT_MAX < 0.493 and BIOME_PLAINS_MAX > 0.507 (the river band is
##      RIVER_LEVEL +/- RIVER_HALF_WIDTH). At 0.575 the visual plains->city blend
##      does not even begin until 0.525, so no city tint reaches the water either.
##   2. Every INTERIOR band must be at least ~2 * BIOME_BLEND (0.10) wide, or its
##      colour never reaches full strength between its two smoothstep blends. City
##      is 0.085 (midpoint renders 96.8% city), forest 0.09 (98.6%) and MOUNTAIN
##      0.08 (94.5%) — mountain is now the tightest and the one to watch. Snow is
##      exempt by construction: it is the topmost band, so it has only a lower edge
##      and reaches full strength outright.
##   3. The chain must stay strictly increasing. A threshold typed out of order
##      leaves the constants looking fine and makes one territory unreachable.
const BIOME_DESERT_MAX: float = 0.34
const BIOME_PLAINS_MAX: float = 0.575
const BIOME_CITY_MAX: float = 0.66
const BIOME_FOREST_MAX: float = 0.75
const BIOME_MOUNTAIN_MAX: float = 0.83

## River contour: the band is the set of points whose noise value sits within
## RIVER_HALF_WIDTH of RIVER_LEVEL. Width in metres ≈ RIVER_HALF_WIDTH / |∇n|;
## MEASURED over a 4 km field, one octave at a 400 m wavelength has a mean
## gradient near 0.0017 /m, so 0.007 gives crossings with a median of ~11 m along
## +X (a perpendicular width of roughly 8-9 m — a couple of wading strides).
## The earlier 0.02 was tuned from a guessed 0.005 /m gradient and made 6.7% of
## the world water, with a median crossing of 31 m.
##
## ponytail: value noise has ZERO gradient at every lattice corner, so wherever a
## 400 m corner hashes near RIVER_LEVEL the contour still widens into an
## occasional lake (measured p95 crossing 61 m, worst case a few hundred). Rare
## enough to be a landmark rather than a bug; if it ever grates, gate the band on
## a minimum |∇n| or drive the contour from a second, higher-frequency octave.
const RIVER_LEVEL: float = 0.5
const RIVER_HALF_WIDTH: float = 0.007

## Upper bound on how fast the biome field can change, in NOISE UNITS PER METRE.
##
## _biome_value_noise is one octave of smoothstep-weighted value noise over
## BIOME_CELL_SIZE cells whose corner values live in 0..1. The smoothstep weight
## f*f*(3-2f) has derivative 6f(1-f), which peaks at 1.5, so along either axis the
## field can move at most 1.5 per unit of noise space, and the gradient MAGNITUDE
## at most sqrt(1.5^2 + 1.5^2) = 2.1213. Divide by the cell size and that is
## metres. (_biome_noise's 0..1 clamp only ever flattens the field, so the bound
## survives it.)
##
## WHAT IT IS FOR: turning a SAMPLED river test into a PROVEN one. A grid of
## is_river_at() calls can step clean over a band that happens to be narrow where
## it crosses — a river's width on the ground is set by the local gradient, and
## nothing bounds it from below. Widen the test by this slope times the furthest a
## point can sit from the nearest sample, and "no sample was wet" stops being an
## inference. _tower_wet_samples is the first user.
const BIOME_NOISE_MAX_SLOPE: float = 2.1213 / BIOME_CELL_SIZE

## Noise-space half-width of the soft colour transition between biomes, used as
## a smoothstep radius in the ground shader. Purely cosmetic: gameplay reads the
## hard thresholds above, the eye reads this blend.
const BIOME_BLEND: float = 0.05

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
const TREE_CANOPY_LAYER_HEIGHT: float = 1.0
const TREE_CANOPY_TAPER: float = 0.68     # each layer up is this fraction as wide
const TREE_TRUNK_COLOR := Color(0.34, 0.24, 0.16)
const TREE_LEAF_COLOR := Color(0.16, 0.36, 0.19)

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
## every flat roof in a city is one jump from the pavement and a city block is a
## field of croc-free perches. That is what pays for the reduced croc density
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

## HOUSE — the roof slab: how far it oversails the walls, and how thick it is. The
## slab is collide = false, so the surface the player actually stands on is the
## HULL top (the height recorded as the footprint's `top`) and the slab is a thin
## film over it — exactly the rule STRUCTURE_THEMES' `cap` follows. Keep it thin:
## the film is what the player's feet are inside while standing on the roof.
const CITY_ROOF_EAVES: float = 0.25
const CITY_ROOF_THICKNESS: float = 0.14

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

## CITY — the crocodile TARGET is divided by this in the city band. Owner call
## (2026-08-26): a city is not croc-free, it is quieter. This is a DESIGN number
## exactly like DESERT_BLOCK_KEEP_EVERY and the distance gradient, not a perf
## trim, so the "entity counts are never reduced as an optimization" convention is
## intact. Like the desert's, it lowers a TARGET and inserts NO RNG DRAW anywhere:
## the surviving crocodiles are byte-for-byte the FIRST target/N of the undivided
## stream, in the same positions, with the tail simply not spawned.
const CITY_CROC_DIVISOR: float = 2.5

# ============================================================================
# WHICH PREDATOR A BIOME GETS
# ============================================================================
## The whole species dispatch, and it is a TABLE LOOKUP ON A PURE FUNCTION —
## `biome_at(chunk_centre)` — with ZERO RNG draws behind it. Read that as the
## hard constraint it is, not as a style preference:
##
##   The chunk's crocodile RNG is ONE shared stream. Every position in the chunk
##   is the sequence of draws that came before it, so a single extra draw here
##   would slide every crocodile in every chunk to a different spot — a whole new
##   world, for free, on a change that was only ever supposed to swap a mesh.
##   That is why species is DISPATCH and not a roll: variety comes from the biome
##   field, which the world already has, and costs the stream nothing.
##
## It is the same trick, for the same reason, as CITY_CROC_DIVISOR right above
## and DESERT_BLOCK_KEEP_EVERY: derive from the biome, never draw for it.
##
## A biome with no entry gets the crocodile — which is why PLAINS is absent
## rather than spelled out as "crocodile". Absent is the statement: nothing about
## its spawning changed, and with the epic complete PLAINS is the one band that
## still keeps the original animal.
##
## ADDING A SPECIES (asc.3/.5/.6/.9 each added exactly one) is three things and
## no more: a row in `SPECIES` in piglet_crocodile_ai.gd, a .tscn beside
## sand_viper.tscn, and one line here. No new script, no subclass, no branch in
## the spawner — and, as the mountain cougar and the city alley hound below
## demonstrate, not even necessarily a new `match` arm: those two SHARE one
## ("burst"), because a pounce and an alley sprint differ only in numbers.
##
## The name must match a key of that SPECIES table. A typo does not crash: the
## AI's _ready() warns and falls back to the crocodile row, and _species_scene()
## below falls back to the crocodile scene, so a mistake here is a visibly wrong
## animal rather than a dead chunk.
const BIOME_SPECIES: Dictionary = {
	Biome.DESERT: {
		"species": "sand_viper",
		"scene": "res://scenes/characters/sand_viper.tscn",
	},
	## The forest is the one band that already crowds the player's SIGHT — it is
	## the densest tree cover in the world — so it is the right one to put an
	## enemy in that crowds their SPACE. The wolf's pack steering (see
	## piglet_crocodile_ai.pack_steer_point) has each animal swing to its own slot
	## on a ring, and trunks are what make that read: the wolf you lost behind one
	## is the wolf arriving from the side.
	Biome.FOREST: {
		"species": "timber_wolf",
		"scene": "res://scenes/characters/timber_wolf.tscn",
	},
	## The tundra is the band this file's SNOW section calls the HOSTILE one —
	## nothing thinned, the full distance-scaled croc density, and the only shelter
	## the ice you can climb onto. It is also the most OPEN ground in the world (a
	## handful of dead trees per chunk and a lot of nothing between them), which is
	## the one place a straight-line charger belongs: the frost bear's committed
	## charge (see piglet_crocodile_ai.charge_steer_point) is only fair if you can
	## see it coming and have somewhere to step, and both of those are what open
	## ground is. The forest is the exact inverse — put this animal among trunks
	## and it would spend its life shouldering into them.
	Biome.SNOW: {
		"species": "frost_bear",
		"scene": "res://scenes/characters/frost_bear.tscn",
	},
	## A massif band is a MAZE — impassable block walls with long straight
	## corridors between them (see the MOUNTAIN section: mountains are things you
	## route around, never terrain you climb). That is the one place a burst
	## predator belongs. The cougar's pounce (see piglet_crocodile_ai's
	## burst_cycle_factor) is the only thing in this game that goes above
	## MAX_CHASE_SPEED, and it is only fair where a corridor gives you the sight
	## line to see it start and the walls give its recovery leg somewhere to break
	## line of sight. Put it on the open tundra and it would be a 11 m/s animal
	## visible from 40 m; put the bear in here and it would shoulder into rock.
	Biome.MOUNTAIN: {
		"species": "mountain_cougar",
		"scene": "res://scenes/characters/mountain_cougar.tscn",
	},
	## The city is the SAFE band — CITY_CROC_DIVISOR above divides its predator
	## target by 2.5 and the roofs are the real shelter — and that is exactly why
	## its animal is the one with the tightest escape margin in the game. Density
	## and danger are separate dials: this band turns the first one down, so the
	## few hounds that are here are individually harder to shake (the alley sprint
	## runs the same burst arm as the cougar at half the cycle length). The band
	## stays safe because you meet one, not six.
	Biome.CITY: {
		"species": "alley_hound",
		"scene": "res://scenes/characters/alley_hound.tscn",
	},
}

## WHICH BOSS GUARDS A ROAD STATION — the BIOME_SPECIES rule, one feature over.
##
## Same shape ({species, scene}), same fallback (an entry-less biome gets the
## crocodile), same hard NO-RNG-DRAW constraint. What differs is the POINT it is
## keyed on, and that difference is the whole reason this table is separate.
##
## A BOSS IS NOT CHUNK-KEYED. Boss `i` owns station k = i * BOSS_INTERVAL_STATIONS
## (see the BOSS CROCODILES section), and that station's CENTRE is the one
## coordinate it has that is pure in `i` + run_seed. So the dispatch keys on the
## station centre — never on the candidate the boss ends up standing on, which
## spawn_bosses_in_chunk picks out of BOSS_PLACE_TRIES lateral offsets by testing
## them against THIS chunk's obstacle layout: that point varies with geometry and
## can sit the far side of a biome boundary, and the boss KIND has to be a pure
## function of `i` alone or two peers sharing a run_seed put a different animal on
## the same road. (It is not keyed on the claiming chunk's centre either, for the
## same reason BIOME_SPECIES is: a chunk centre is what a CHUNK's predators are
## dispatched on, and a boss is a station's, not a chunk's.)
##
## THE RIVER RULE COMES FIRST and it is the owner's, verbatim: "river -
## crocodile". A station standing in the water is guarded by the animal that
## belongs in water, whatever band the noise field puts it in.
##
## THIS TABLE SHIPS EMPTY, AND THAT IS THE POINT. Every boss is still a crocodile
## and the generated world is byte-identical to the one before this seam existed:
## the dispatch is pure function calls (biome_at / is_river_at — the
## allocation-free public API, no RNG anywhere under either) inserted at a spot
## where no draw is made, so the BOSS_SEED stream consumes the same draws in the
## same order it always did. A single extra draw would slide every boss in the
## world, which is the same rule CLAUDE.md states for BIOME_SPECIES and
## CITY_CROC_DIVISOR. The snow titan and the forest dragon each land as ONE ROW
## here, exactly as a predator lands as one row in BIOME_SPECIES.
##
## Degrade rules are BIOME_SPECIES': a name that is not a SPECIES row warns from
## the AI's _ready() and behaves as a crocodile, and a scene that fails to load
## falls back to the crocodile scene — a visibly wrong animal, never a boss-less
## station.
const BIOME_BOSS: Dictionary = {
	## The snow band's guardian: the TITAN, a slow HMM3-style giant archer that
	## barely pursues and instead throws a dodgeable thunder bolt. The first row
	## this table has ever had — everything above about the shape of it (station
	## centre, no RNG draw, river-first) was written for exactly this line.
	Biome.SNOW: {
		"species": "titan",
		"scene": "res://scenes/characters/titan.tscn",
	},
}

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
## PROPS (the phase-1 machinery — see _prop_ice_rock and friends), because they are
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
# SECTION 2: INTERNAL STATE
# ============================================================================

## Preloaded crocodile scene for spawning. Still the DEFAULT species' scene and
## still the seam the kill switch and every self-check harness assign by hand, so
## the non-crocodile species are cached separately below rather than folding this
## one into a dictionary and quietly demoting it.
var crocodile_scene: PackedScene

## Scenes for the NON-crocodile species, keyed by Biome (see BIOME_SPECIES).
## Loaded on first use rather than in _ready() because a run may never walk into a
## desert; the dictionary exists so a desert chunk does not re-`load()` per chunk
## once nothing else is holding the scene alive.
var _species_scenes: Dictionary = {}

## Scenes for the NON-crocodile BOSS species, keyed by Biome (see BIOME_BOSS).
## Its own cache and not _species_scenes': both are keyed by Biome, but a band's
## boss and its ordinary predator are different animals, so one dictionary would
## have them overwrite each other's entry.
var _boss_scenes: Dictionary = {}

## Preloaded coin scene for spawning
var coin_scene: PackedScene

# ----------------------------------------------------------------------------
# COIN ROAD STATION CACHE (the integrated centerline, computed once, never reset)
# ----------------------------------------------------------------------------
##
## The road centerline is sampled at integer station indices `k`. Each cached entry
## is a Dictionary { center: Vector2, heading: float }, where `center` is the
## centerline position in world (x, z) coordinates — note we pack WORLD Z into the
## Vector2's `.y` field — and `heading` is the integrated heading angle (radians)
## from +X used to step to the NEXT station.
##
## We key the cache by `k` in a Dictionary (NOT a contiguous Array) so that extending
## the road in the -X direction is O(1) per station: an Array would force `push_front`,
## which shifts every existing element (O(n) per insert → O(n²) over a long backward
## walk). A Dictionary insert is O(1) and an index lookup `road_stations[k]` is O(1),
## regardless of how far the road has grown either way. The cache still holds a
## CONTIGUOUS range [road_k_min, road_k_max]; it just doesn't pay the array-shift cost.
##
## The cache grows from station 0 outward in BOTH directions (forward for k>0, backward
## for k<0) as chunks request coverage, and is NEVER invalidated — the road is static
## and infinite, and every station is a pure function of `k` + the fixed seed, so a
## cached value is correct forever and independent of load order.
var road_stations: Dictionary = {}

## Inclusive station-index bounds of what `road_stations` currently holds. They start
## "empty" (min > max); the first _road_extend_to_x seeds station 0 and sets both to 0.
var road_k_min: int = 1
var road_k_max: int = 0

## Reference to the player node to track their position
var player: Node3D

## Dictionary to store active chunks
## Key: Vector2i (chunk coordinates), Value: MeshInstance3D (the chunk)
var active_chunks: Dictionary = {}

## Last player chunk position (to detect when to update chunks)
var last_player_chunk: Vector2i = Vector2i(999999, 999999)

# ----------------------------------------------------------------------------
# FRAME-SPIKE TELEMETRY COUNTERS (read-only for everybody else)
# ----------------------------------------------------------------------------
## Lifetime totals of chunks built and freed. `perf_overlay.gd` samples these
## once per frame and records the DELTA next to any frame that spiked, which is
## how "the world froze for 60 ms" becomes "the world froze for 60 ms while it
## built 3 chunks and freed 5". Monotonic and never reset (not even by
## `new_run`) so a sampler can always subtract two readings without worrying
## about a wrap — the overlay's own reset just re-baselines its previous value.
##
## Deliberately plain ints incremented at the two (three, counting new_run's
## bulk free) sites that change `active_chunks`, not a signal: the sampler polls
## at its own rate and must never be able to perturb generation.
var chunks_created_total: int = 0
var chunks_removed_total: int = 0

# ----------------------------------------------------------------------------
# TIME-SLICED CHUNK GENERATION (one chunk per frame, nearest-first)
# ----------------------------------------------------------------------------
##
## Building EVERY missing chunk in a single frame is what caused the startup
## freeze: 49 chunks on web (121 on desktop) of mesh + collision + crocodile +
## coin generation in one go is a multi-second hitch on a phone. Instead,
## update_chunks() now builds only a small SAFETY RING synchronously and queues
## the rest here; _process() then drains the queue at exactly ONE chunk per
## frame — ~40 pending chunks become ~0.7 s of progressive fill hidden behind
## the fog, instead of one frozen frame.
##
## DETERMINISM NOTE — generation ORDER cannot change the world. Every chunk's
## content is seeded purely from its own coords + run_seed (hash(Vector3i(...))),
## and the road station cache grows contiguously outward from station 0 via a
## recurrence that is pure in the station index `k` (see _road_extend_to_x) —
## whichever chunk happens to request coverage first, station k always comes out
## identical. So building chunks over 40 frames instead of 1 produces a
## byte-identical world.

## Chunks within Chebyshev distance <= SYNC_RING of the player's chunk get their
## GROUND built SYNCHRONOUSLY in update_chunks. This is the load-bearing safety
## guarantee: the player (walking, or teleported to spawn by new_run/restart) can
## only ever reach an adjacent chunk this frame, so ring 1 having ground means
## they can never stand over — or fall through — an unbuilt chunk while the rest
## of the world fills in progressively. 9 chunks at startup/new_run, at most 3
## new ring chunks on a normal boundary crossing.
const SYNC_RING: int = 1

## THE SYNC RING IS GROUND ONLY, AND THAT SPLIT IS THE WHOLE POINT (bead
## godot-test1-6mh.3). What the safety guarantee above actually needs is a floor
## under the player's feet — a shared PlaneMesh plus one 50x0.1x50 box shape.
## What it USED to build was the entire chunk: ~12 props, a feature structure,
## biome geometry, artifacts/camps/landmarks/chests, 10 crocodile scene
## instantiations and the chunk's slice of the coin road. None of that can drop
## anybody through the world, and all of it is where the time goes.
##
## MEASURED (M4 desktop, opengl3, the 3x3 startup ring, median of 3 run seeds):
##   whole chunks  7.08 ms   <- what update_chunks used to do synchronously
##   ground only   0.18 ms   <- what it does now (2.5% of it)
##   worst frame   0.98 ms   <- the heaviest single chunk the drain then carries
## The remaining 97% moved into the existing one-chunk-per-frame `pending_chunks`
## drain, which already had to be safe for every chunk past ring 1. The phase-1
## boot spike this bead chases (`[SPIKE] 150.0 ms SEVERE | chunks +10/-0`) scales
## the same way: it was 10 whole chunks in one frame, and it is now 9 grounds
## plus one populate.
##
## Ordering is untouched, so determinism is untouched: a chunk's content is a
## pure function of its own coords + run_seed, so building the floor on frame 0
## and the content on frame 4 produces exactly the bytes a single-frame build
## produced (see the determinism note above `pending_chunks`).
##
## Chunks that have ground but no content yet — keys only, `true` values, for the
## same O(1)-membership reason `chunks_to_load` uses a Dictionary. They are in
## `active_chunks` and in the tree from the moment their ground exists, so
## everything that iterates chunks keeps working; this is the one flag that says
## "still owes its content", which is what stops update_chunks from skipping them
## as already-loaded and lets create_chunk finish the job later.
var bare_chunks: Dictionary = {}

## Missing chunks awaiting progressive creation, sorted nearest-first (squared
## distance to the player's chunk). Rebuilt from scratch on every update_chunks
## call — it only runs on boundary crossings, so a full rebuild is cheap and
## simpler than incremental surgery: it dedupes for free (each position comes
## from iterating the unique-keyed chunks_to_load Dictionary once) and
## naturally drops queued chunks that fell back out of range.
##
## The sync-ring chunks are queued here TOO, not instead: they were given ground
## synchronously and still owe their content, so they ride the same drain as
## everybody else — first, because the queue is sorted nearest-first.
var pending_chunks: Array[Vector2i] = []

## Chunks that fell OUT of range and are awaiting their queue_free(), drained by
## _process at one chunk per frame — the exact mirror of pending_chunks, and it
## exists for the exact mirror of the reason (bead godot-test1-6mh.2).
##
## Teardown was the one half of chunk streaming still done in a single frame: a
## boundary crossing drops a whole COLUMN of chunks (2 x render_distance + 1 —
## 7 on web, 11 on desktop), and a chunk is not one node but a mesh + two
## collision bodies + its crocodiles, coins, props and landmark nodes, so that
## column is several hundred nodes queue_free()d at once, every ~7 s of walking.
## Draining it one chunk per frame spreads the same work over as many frames.
##
## THE CHUNK STAYS FULLY ALIVE UNTIL ITS TURN — still in `active_chunks`, still
## in the tree, still colliding. That is what makes the queue safe rather than
## merely deferred, and it is why only positions are queued:
##
##   * NO DOUBLE FREE — remove_chunk() is the only freer and it erases from
##     `active_chunks` in the same breath, so a stale position drains to a no-op.
##   * NO RE-SERVED CORPSE — a chunk the player walks back onto is never a freed
##     node handed out again; it simply never left, and the rebuild-from-scratch
##     below drops it from this queue. (Same rebuild discipline as
##     pending_chunks: it only runs on boundary crossings, dedupes for free, and
##     drops entries that fell back into range.)
##   * NO LEAK — `update_chunks` re-derives the queue from `active_chunks` on
##     every crossing, so anything still loaded and out of range is queued again
##     next time, and _process drains anything beyond the ceiling described
##     there in the same frame. Chunks that fall out of range faster than the
##     queue drains are therefore still freed at the rate they arrive; only the
##     steady-state trickle is throttled.
##
## Costs a few chunks' worth of memory for a few frames, and makes the F3
## "Chunks" readout briefly count them — both correct: they ARE still loaded.
##
## NOT used by new_run()'s bulk free, deliberately: that one drops OLD-WORLD
## geometry while the new world builds on top of it, so a throttled teardown
## would leave the previous run's blocks standing inside the new one for a
## second. A restart is allowed to hitch; a walk is not.
var pending_removals: Array[Vector2i] = []

# ----------------------------------------------------------------------------
# FOCUS POINTS (multiplayer: keep chunks loaded around FAR TEAMMATES too)
# ----------------------------------------------------------------------------
##
## THE BOUNDARY, AND IT IS ABSOLUTE: focus points decide only WHICH CHUNKS STAY
## LOADED. They never touch what a chunk CONTAINS. Every chunk's content is a
## pure function of its own coords + `run_seed` (see the determinism note above
## `pending_chunks`), and generation ORDER already cannot change it, so a chunk
## built because a teammate stands on it is byte-for-byte the chunk the local
## player would have built by walking there. Nothing below reads a focus point
## during generation, and nothing may ever be added that does.
##
## WHY THIS EXISTS (bead godot-test1-s86.14): the room master simulates the
## crocodiles for everybody, but it can only simulate the ones ITS OWN terrain
## has loaded. A peer more than `render_distance` × `chunk_size` away (150 m on
## web) therefore got no samples for its neighbours and they fell back to local
## simulation after `MpManager.CROC_SYNC_TIMEOUT`. `set_focus_points()` closes
## that: `crocodile_lod_manager.gd` — which already builds exactly this array,
## master-gated, on its throttled scan — hands it here, and the union of peer
## areas stays loaded.
##
## FOCUS_RING IS 1, AND THAT IS A DERIVATION RATHER THAN A GUESS. A 3×3 block of
## `chunk_size` (50 m) chunks around the chunk a peer stands in guarantees at
## least 50 m of loaded ground in every direction from that peer (worst case: the
## peer on a chunk edge, 50 m to the far side of the neighbouring chunk), which
## covers `crocodile_lod_manager.SIM_RADIUS` (45) — the radius inside which a
## crocodile is awake, and therefore the radius inside which the master has
## anything to publish at all. A ring of 2 would be 25 chunks per peer for
## crocodiles nobody is awake for.
const FOCUS_RING: int = 1

## HARD MEMORY CAP, and the reason there is one: the union of peer areas
## MULTIPLIES the active chunk count, and the web build is the platform this
## whole file's perf work exists to protect. At most `MAX_FOCUS_POINTS` points
## are honoured (a room holds 4 players, so 3 teammates) and at most
## `MAX_FOCUS_CHUNKS` chunks are admitted BEYOND the ones the local player's own
## square already covers. Worst case on web is 49 + 27 = 76 active chunks
## (+55%); on desktop 121 + 27 = 148 (+22%). Points past the cap are dropped
## rather than rotated, so the set is stable frame to frame — a peer whose
## chunks flicker in and out would be worse than a peer with none.
##
## The cap is also the trust bound: these positions originate in presence
## packets, i.e. peer input, and `MpManager` bounds them by `MAX_PRESENCE_COORD`
## (huge) rather than by anything the terrain could afford. A peer claiming to
## stand 1e6 m away costs 9 useless chunks here, never more.
const MAX_FOCUS_POINTS: int = 3
const MAX_FOCUS_CHUNKS: int = 27

## The chunks focus points currently pin, as Dictionary KEYS (value `true`) for
## the same O(1)-membership reason `chunks_to_load` uses one. Empty offline and
## on a non-master, which is what makes single-player byte-for-byte unchanged:
## `update_chunks` iterates nothing extra and `_process` never re-triggers.
var focus_chunks: Dictionary = {}

## Set when `focus_chunks` actually CHANGED, so `_process` can re-run
## `update_chunks` off a boundary crossing. Without it a teammate walking into
## fresh territory would pin nothing until the LOCAL player happened to cross a
## chunk edge, which is exactly the far-apart case this feature is for.
var focus_dirty: bool = false

## PER-RUN WORLD SEED — makes run 2 a different world from run 1.
##
## EDUCATIONAL NOTE — the determinism contract:
## Every "random" thing in the world (block layout, crocodile positions, the road's
## shape, the coin scatter) is derived from a pure hash of its coordinates — chunk
## coords for chunk content, station index `k` for the road. That purity is what
## lets a chunk regenerate byte-identically when you walk away and come back, and
## what lets the coin road line up seamlessly across chunk seams.
##
## `run_seed` is mixed into EVERY one of those hash sites as a third hash input
## (via Vector3i — a real extra input, not arithmetic that could alias two seeds
## onto the same value). It is rolled ONCE per run and never changes mid-run, so:
##   - WITHIN a run: every seed site is still a pure function of (coords | k),
##     because run_seed is a constant — revisited chunks regenerate identically
##     and the coin seam-claiming (world_to_chunk(coin) == chunk_pos) still holds.
##   - ACROSS runs: new_run() re-rolls it, so every hash changes and the next run
##     gets a genuinely different world layout.
##
## We roll it with a local RandomNumberGenerator (randomize() + randi()) instead of
## the global randi() so we don't disturb the global RNG state other scripts use.
var run_seed: int = 0

## The landmark builders, held as a SCRIPT OBJECT rather than referenced as the
## `LandmarkBuilders` class, purely so `call()` works on it.
##
## `LandmarkBuilders.call(name, ...)` is a PARSE ERROR — GDScript refuses
## `Object.call()` on a class expression ("Cannot call non-static function
## call() on the class ... directly. Make an instance instead.") — while a
## GDScript-TYPED variable holds a real `Object` at runtime and dispatches the
## script's static methods perfectly. `landmark_selfcheck.gd` reaches the same
## builders the same way, which is why the two agree by construction.
##
## Constants are the other half: `LandmarkBuilders.LANDMARKS` is a compile-time
## constant lookup and is written that way at its two call sites, so the registry
## stays checked at parse time while only the dynamic dispatch goes through here.
var _landmark_builders: GDScript = preload("res://scripts/landmark_builders.gd")

## Per-run DOMAIN OFFSET for the biome noise field, in noise-space units.
##
## EDUCATIONAL NOTE — why this exists at all instead of just hashing run_seed:
## the biome field has to be evaluated in TWO places, GDScript (gameplay: where
## the rivers and mountains are) and GLSL (the ground shader: what colour the
## ground is). A shader uniform cannot take a 64-bit int seed, and re-deriving a
## hash from one inside GLSL would be a second thing to keep in sync. So the run
## seed reaches the GPU as a plain vec2 SHIFT of the noise domain: sampling the
## same noise at a different place is exactly as good as reseeding it, and it is
## one uniform. Rolled by _roll_biome_offset() from its own RNG stream.
var biome_offset: Vector2 = Vector2.ZERO

## MEMO for tower_site(). The site is a pure function of (run_seed via the biome
## field, tower_site_distance), but finding it costs a few hundred noise
## evaluations and _biome_spot_ok asks for it at every candidate spot in the
## world — so it is found once and re-derived only when one of those two inputs
## changes. Two scalar compares per call, no allocation. `_tower_site_dist` starts
## negative, a distance no caller can supply, so the first call always computes.
var _tower_site_cache: Vector3 = Vector3.ZERO
var _tower_site_seed: int = 0
var _tower_site_dist: float = -1.0

## The tower's two bodies, both parented to THIS manager (never to a chunk) and
## both a pure function of the run seed, so multiplayer needs no packet for either.
##
##   * `_tower_shell` is the real building. Null until the player first comes within
##     TOWER_LOAD_RADIUS, then never freed for the rest of the run — a bounded,
##     known cost, and freeing it would only trade nine boxes for a pop-in.
##   * `_tower_impostor` is the fog-exempt horizon silhouette, built at _ready() and
##     alive for the whole session; it is HIDDEN, not freed, once the shell exists,
##     because new_run() needs it back.
var _tower_shell: Node3D = null
var _tower_impostor: Node3D = null

# ----------------------------------------------------------------------------
# SHARED RESOURCES FOR MULTIMESH BLOCK RENDERING (created once, reused forever)
# ----------------------------------------------------------------------------
##
## EDUCATIONAL NOTE — what a MultiMesh is and why we use it here:
## Previously every decorative block was its own MeshInstance3D with its OWN
## BoxMesh and its OWN StandardMaterial3D. With ~12 scattered objects + stacks +
## big feature structures per chunk and 121 active chunks, that is *thousands* of
## separate meshes and materials — and the GPU has to issue a separate "draw call"
## for each one. Draw calls are expensive (especially in a browser/WebGL), so this
## is the main thing that makes the web build stutter.
##
## A MultiMesh fixes this. It is ONE mesh (a single unit cube) drawn MANY times in
## a SINGLE draw call. Each "instance" gets its own Transform3D (so we can scale +
## rotate + move the unit cube to land exactly where a block should be) and its own
## per-instance Color (so each block keeps its individual earthy colour). One
## MultiMeshInstance3D per chunk therefore renders every block in that chunk with
## essentially one draw call instead of dozens — a huge win, with no visual change.
##
## We keep TWO resources shared across ALL chunks (creating them once avoids
## re-allocating identical resources for every chunk):
##   1. a unit (1×1×1) BoxMesh — the geometry every instance reuses; per-instance
##      scale in the transform stretches it to each block's real dimensions.
##   2. a StandardMaterial3D with `vertex_color_use_as_albedo = true` — this tells
##      the shader to use each instance's per-instance Color AS its albedo, so the
##      single shared material still paints every block its own earthy colour.

## Lazily-created shared unit BoxMesh (size 1×1×1). The MultiMesh instance
## transforms carry the per-axis scale, so this single cube becomes every block.
var _shared_unit_box_mesh: BoxMesh

## The single ground PlaneMesh shared by every chunk (see _get_shared_ground_mesh).
var _shared_ground_mesh: PlaneMesh

## Lazily-created shared material for the block MultiMesh. `vertex_color_use_as_albedo`
## lets one material show each instance's individual colour. Per-instance roughness
## is NOT supported by MultiMesh (only transform + color are per-instance), so we
## bake a single representative roughness here (0.85, mid-range of the old
## 0.7–1.0 spread). The visual difference is negligible.
##
## COLOUR SPACE: we leave `vertex_color_is_srgb` at its default (false) on purpose —
## the Compatibility (web) renderer IGNORES that flag, so we can't rely on it. Instead
## create_box pre-converts each instance colour with `srgb_to_linear()` before storing
## it, so the per-instance colour is already linear and matches what the OLD
## `albedo_color` (sRGB→linear) path produced. See the COLOUR SPACE note in create_box.
var _shared_block_material: StandardMaterial3D

## Lazily-created shared material for artifact glow accents (rune strips, eyes,
## missing keystones — see the ARTIFACTS section). ONE material shared by every
## accent in the world, same lazy-singleton discipline as _shared_block_material.
var _shared_artifact_glow_material: StandardMaterial3D

## Lazily-created shared material for the nomad camps' fire-pit embers (see the
## NOMAD CAMPS banner). Same lazy-singleton discipline as the artifact glow above:
## ONE material for every ember that will ever be spawned, never one per camp.
var _shared_camp_ember_material: StandardMaterial3D

## A representative roughness for the shared block material. The old per-block code
## picked a random roughness in [0.7, 1.0]; since MultiMesh can't vary roughness
## per instance, we use one mid-range value for all blocks. (We still CONSUME the
## same RNG call in create_box so the deterministic world layout is unchanged.)
const SHARED_BLOCK_ROUGHNESS: float = 0.85

## Curated block colour ramps (Task 8 of the rendering pass). The old code rolled
## each colour channel independently, which gave muddy, uncoordinated blocks. Now
## each of the three block "families" is a hand-picked two-colour RAMP sharing a
## warm undertone, and a block samples its ramp with ONE lerp — so every block
## still varies, but along an art-directed line instead of a random RGB cube.
## (The RNG draw count in create_box is unchanged — see the determinism note there.)
const RAMP_SANDSTONE_A := Color(0.72, 0.58, 0.42)  # warm sandstone …
const RAMP_SANDSTONE_B := Color(0.65, 0.38, 0.28)  # … to terracotta
const RAMP_SLATE_A := Color(0.38, 0.40, 0.45)      # slate …
const RAMP_SLATE_B := Color(0.55, 0.58, 0.63)      # … to blue-grey
const RAMP_MOSS_A := Color(0.42, 0.45, 0.26)       # olive …
const RAMP_MOSS_B := Color(0.30, 0.42, 0.28)       # … to moss

func _get_shared_unit_box_mesh() -> BoxMesh:
	"""
	Returns the shared unit (1×1×1) BoxMesh used by every block MultiMesh,
	creating it on first use. One cube reused everywhere; per-instance transforms
	scale it to each block's real size.
	"""
	if _shared_unit_box_mesh == null:
		_shared_unit_box_mesh = BoxMesh.new()
		_shared_unit_box_mesh.size = Vector3.ONE  # unit cube; scaled per-instance
	return _shared_unit_box_mesh

func _get_shared_ground_mesh() -> PlaneMesh:
	"""
	Returns the ONE PlaneMesh shared by every chunk's ground, creating it on first
	use. All chunks are the same size, so a single mesh serves them all — the old
	code allocated a fresh subdivided PlaneMesh per chunk for no benefit. 16×16
	subdivisions give the vertex density the vertex-noise ground shader needs.
	The material comes from terrain_material, which _ready() finalizes before
	any chunk can be created, so assigning it once here is safe.
	"""
	if _shared_ground_mesh == null:
		_shared_ground_mesh = PlaneMesh.new()
		_shared_ground_mesh.size = Vector2(chunk_size, chunk_size)
		_shared_ground_mesh.subdivide_width = 16
		_shared_ground_mesh.subdivide_depth = 16
		_shared_ground_mesh.material = terrain_material
	return _shared_ground_mesh

func _get_shared_block_material() -> StandardMaterial3D:
	"""
	Returns the shared block material used by every block MultiMesh, creating it on
	first use. `vertex_color_use_as_albedo = true` makes each MultiMesh instance's
	per-instance Color show up as that block's albedo, so one material can paint all
	the earthy browns/grays/mossy greens.
	"""
	if _shared_block_material == null:
		_shared_block_material = StandardMaterial3D.new()
		# THE key line: take the per-instance vertex colour and use it as albedo.
		_shared_block_material.vertex_color_use_as_albedo = true
		# Single representative roughness (see SHARED_BLOCK_ROUGHNESS note above).
		_shared_block_material.roughness = SHARED_BLOCK_ROUGHNESS
	return _shared_block_material

func _get_artifact_glow_material() -> StandardMaterial3D:
	"""
	Returns the shared emissive material for artifact glow accents, creating it on
	first use (same lazy-singleton shape as _get_shared_block_material). The
	emission energy (3.0) sits well above main.tscn's glow_hdr_threshold (0.85),
	so the already-paid glow post-process picks these up and they bloom for free —
	no extra render passes. UNSHADED because a glowing rune should not go dark
	when it falls inside the key light's shadow.
	"""
	if _shared_artifact_glow_material == null:
		_shared_artifact_glow_material = StandardMaterial3D.new()
		_shared_artifact_glow_material.albedo_color = ARTIFACT_GLOW_COLOR
		_shared_artifact_glow_material.emission_enabled = true
		_shared_artifact_glow_material.emission = ARTIFACT_GLOW_COLOR
		_shared_artifact_glow_material.emission_energy_multiplier = ARTIFACT_GLOW_ENERGY
		_shared_artifact_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _shared_artifact_glow_material

func _get_camp_ember_material() -> StandardMaterial3D:
	"""
	Returns the shared emissive material for nomad-camp fire-pit embers, creating it
	on first use — the artifact glow material's twin in every way except colour.
	WARM ORANGE where the artifacts are cold cyan, so a glow at a distance always
	says which landmark it belongs to. CAMP_EMBER_ENERGY (2.5) sits above main.tscn's
	glow_hdr_threshold (0.85), so the already-paid glow post-process blooms it for
	free, and UNSHADED keeps an ember lit when the camp falls into shadow.
	"""
	if _shared_camp_ember_material == null:
		_shared_camp_ember_material = StandardMaterial3D.new()
		_shared_camp_ember_material.albedo_color = CAMP_EMBER_COLOR
		_shared_camp_ember_material.emission_enabled = true
		_shared_camp_ember_material.emission = CAMP_EMBER_COLOR
		_shared_camp_ember_material.emission_energy_multiplier = CAMP_EMBER_ENERGY
		_shared_camp_ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _shared_camp_ember_material

func _spawn_artifact_accent(parent_chunk: MeshInstance3D, local_pos: Vector3, dimensions: Vector3, yaw: float, tilt: float, material: StandardMaterial3D = null) -> void:
	"""
	Spawns one emissive accent box (a rune strip, an eye, a missing keystone, a camp
	ember) as a REAL MeshInstance3D parented to the chunk (per-chunk parenting rule:
	it unloads with the chunk). Accents cannot join the block MultiMesh — that batch
	has one shared NON-emissive material — so each accent is a genuine extra draw
	call. That is exactly why artifacts are rare and capped at ARTIFACT_MAX_ACCENTS
	accents each (and why a camp spawns exactly ONE ember): worst case on screen is a
	handful of extra unshadowed draws.
	Same Basis(UP, yaw) * Basis(RIGHT, tilt) rotation order as create_box, so an
	accent can sit flush on a tilted stone.

	@param material: OPTIONAL emissive material. Null (the default) keeps the
	                 artifacts' cyan glow, so every pre-existing call site is
	                 unchanged; nomad camps pass _get_camp_ember_material() to reuse
	                 this whole spawn path for their warm-orange ember. Both are
	                 shared singletons — never pass a per-instance material here.
	"""
	var accent := MeshInstance3D.new()
	accent.mesh = _get_shared_unit_box_mesh()  # shared cube; transform carries the size
	accent.transform = Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)).scaled_local(dimensions), local_pos)
	accent.material_override = _get_artifact_glow_material() if material == null else material
	# A fist-sized glowing strip casting a shadow would cost a shadow-pass draw
	# for no visible payoff — accents glow, they don't shade.
	accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_chunk.add_child(accent)

# ============================================================================
# INITIALIZATION
# ============================================================================

func _roll_run_seed() -> void:
	"""
	Roll a fresh per-run world seed. A throwaway local RNG (randomize() seeds it
	from entropy) keeps the global RNG state untouched. Shared by _ready() and
	new_run() so the two sites can't drift apart.
	"""
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.randomize()
	# Both seed paths (rolled here, or forced from outside) converge on
	# set_run_seed, so the biome re-roll below can never be forgotten by one of them.
	set_run_seed(seed_rng.randi())


func set_run_seed(value: int) -> void:
	"""
	Assign this run's world seed explicitly. THE ONLY PLACE run_seed IS WRITTEN.

	Every deterministic hash site in this file mixes run_seed in, and the biome
	field's domain offset is DERIVED from it — so an assignment that skips the
	_roll_biome_offset() below leaves the ground shader drawing the old run's blue
	river bands while is_river_at() reports the new run's, i.e. the blue you see and
	the wading you feel part company. Route every run_seed write through here.

	Callers: _roll_run_seed() (the ordinary random path) and new_run(forced_seed)
	(multiplayer — every peer in a room is handed the same seed so they walk the
	same world).
	"""
	run_seed = value
	_roll_biome_offset()
	# Find the tower's site NOW, on the frame that already pays for a whole new
	# world, rather than lazily on whatever frame the first chunk near it asks.
	# The scan is a few hundred noise evaluations in the worst case — invisible
	# here, a measurable spike if it landed mid-stream. Must come AFTER
	# _roll_biome_offset(): the site is read off the river field that call rolls.
	tower_site()
	# And move the tower's two bodies to wherever that just put the site. THIS is
	# why the reset hangs off the seed write rather than off new_run(): every path
	# that can move the site — _ready's roll, a restart, a multiplayer peer being
	# handed the room's seed — goes through here, so none of them can forget.
	_tower_reset()


func _roll_biome_offset() -> void:
	"""
	Derive this run's biome noise domain offset from run_seed.

	Uses its OWN RandomNumberGenerator seeded hash(Vector3i(BIOME_SALT, 0, run_seed))
	— an independent stream in the same shape as _boss_at / _artifact_at, so it
	consumes zero draws from any chunk/coin/croc RNG and the rest of the world is
	byte-identical to a run without biomes.

	The range is 0..289 noise cells, which covers EVERY distinct field: _biome_hash2
	wraps its lattice point with mod(p, 289.0), so shifting the offset by a whole
	289 lands on exactly the same field. A wider range would buy no extra variety
	and would cost precision — the shader is fp32, where an offset near 4096 has a
	ULP of 4.9e-4 noise units (~0.2 m of world), quantising every river edge onto a
	visible 0.2 m staircase and widening the CPU/GPU parity gap for nothing.
	"""
	var offset_rng := RandomNumberGenerator.new()
	offset_rng.seed = hash(Vector3i(BIOME_SALT, 0, run_seed))
	biome_offset = Vector2(
		offset_rng.randf_range(0.0, 289.0),
		offset_rng.randf_range(0.0, 289.0)
	)


func _apply_biome_shader_params() -> void:
	"""
	Push the biome field's parameters onto the shared ground material, so the tint
	the player SEES agrees with the biome/river the CPU DECIDES (biome_at /
	is_river_at). This is the other half of the shader-parity contract documented on
	_biome_noise: the two noise implementations are identical only if they are fed
	identical constants.

	Called from _ready() (right after the default ShaderMaterial is built) and from
	new_run() (right after _roll_run_seed, which re-rolls biome_offset — the visible
	biome layout has to move with the new run's world).

	EDUCATIONAL NOTE — only the PARITY-CRITICAL parameters are pushed. The four biome
	colours are left to the shader's own uniform defaults, exactly like green_a /
	green_b: they are pure art with no GDScript counterpart, so an art pass can retint
	the material in the editor without anyone touching this script.

	The `is ShaderMaterial` guard keeps the @export escape hatch intact: assign any
	StandardMaterial3D as terrain_material in the editor and this silently does
	nothing instead of erroring on set_shader_parameter.
	"""
	if not (terrain_material is ShaderMaterial):
		return

	var mat := terrain_material as ShaderMaterial
	mat.set_shader_parameter("biome_offset", biome_offset)
	mat.set_shader_parameter("biome_cell_size", BIOME_CELL_SIZE)
	mat.set_shader_parameter("biome_desert_max", BIOME_DESERT_MAX)
	mat.set_shader_parameter("biome_plains_max", BIOME_PLAINS_MAX)
	# The city band's upper edge. Parity-critical like its siblings: the band the
	# player SEES paved has to be the band spawn_biome_content_in_chunk fills with
	# houses. The city COLOUR stays a shader default (pure art), same rule as the
	# other four.
	mat.set_shader_parameter("biome_city_max", BIOME_CITY_MAX)
	mat.set_shader_parameter("biome_forest_max", BIOME_FOREST_MAX)
	# The mountain/snow split. Parity-critical for the same reason as its siblings:
	# the ground the player sees turn white has to be the ground
	# spawn_biome_content_in_chunk fills with ice rocks and mammoth bones. The snow
	# COLOUR stays a shader default (pure art), same rule as the other five.
	mat.set_shader_parameter("biome_mountain_max", BIOME_MOUNTAIN_MAX)
	mat.set_shader_parameter("river_level", RIVER_LEVEL)
	mat.set_shader_parameter("river_half_width", RIVER_HALF_WIDTH)
	mat.set_shader_parameter("biome_blend", BIOME_BLEND)


func _ready() -> void:
	"""
	Initialize the terrain system.
	"""
	# Roll this run's world seed FIRST, before any chunk can possibly generate — every
	# seed site mixes it in, so it must exist before the first hash.
	_roll_run_seed()

	# Join the "terrain" group so other systems (player restart) can find us without
	# hard references — the same group-based wiring used for "player"/"crocodile".
	add_to_group("terrain")

	# WEB-ONLY: shrink the view distance BEFORE any chunks are generated.
	#
	# We set this here at the very top of _ready (and chunk generation is driven later
	# from _process via update_chunks, which reads render_distance fresh each time), so
	# simply lowering render_distance now is enough — the FIRST chunk update will already
	# use the reduced value, and no full-size ring of chunks is ever built on web.
	#
	# `OS.has_feature("web")` is true only in the exported HTML5/WebGL build, so desktop
	# and the editor keep the exported render_distance (5) and are completely unaffected.
	# See the WEB_RENDER_DISTANCE comment above for why the web build wants fewer chunks
	# and how the fog (set up below) hides the resulting nearer world edge.
	if OS.has_feature("web"):
		render_distance = WEB_RENDER_DISTANCE

	# Load the crocodile scene for spawning
	crocodile_scene = load("res://scenes/characters/piglet_crocodile.tscn")
	if not crocodile_scene:
		push_warning("Failed to load crocodile scene!")
		spawn_crocodiles = false

	# Load the coin scene for spawning
	coin_scene = load("res://scenes/collectibles/coin.tscn")
	if not coin_scene:
		push_warning("Failed to load coin scene!")
		spawn_coins = false

	# Find the player in the scene tree
	# We'll use this to track where to generate terrain
	await get_tree().process_frame  # Wait for scene to be fully ready
	player = get_tree().get_first_node_in_group("player")

	if not player:
		push_warning("No player found! Add the player to the 'player' group.")
		return

	# Create default material if none provided.
	# The built-in default is the ground vertex-noise shader (two greens blended
	# by a per-VERTEX world-space noise — see assets/shaders/ground.gdshader for
	# why it's nearly free and seamless across chunks). The @export escape hatch
	# still wins: assign ANY Material in the editor and this block is skipped.
	if not terrain_material:
		var ground_material := ShaderMaterial.new()
		ground_material.shader = load("res://assets/shaders/ground.gdshader")
		terrain_material = ground_material

	# Feed the biome field to the shader. Safe to call unconditionally — it no-ops on a
	# non-ShaderMaterial. run_seed (and with it biome_offset) was rolled at the top of
	# _ready(), so the uniforms match the field every other system reads.
	_apply_biome_shader_params()

	# Enable the depth fog on ALL platforms (thick on web to mask the reduced view
	# distance, thin on desktop as a horizon haze — see _setup_fog). Done after the
	# player is found (so we know the scene tree is ready) but it only touches the
	# WorldEnvironment, not the player.
	_setup_fog()

	print("Endless Terrain System initialized!")
	# Log the platform and the EFFECTIVE render distance so it's obvious in the web
	# console which value the build is actually running with (3 on web, 5 on desktop).
	print("Platform: ", "WEB" if OS.has_feature("web") else "DESKTOP/EDITOR")
	print("Chunk size: ", chunk_size, "m")
	print("Render distance: ", render_distance, " chunks")
	print("Crocodiles per chunk: ", crocodiles_per_chunk if spawn_crocodiles else 0)

func _setup_fog() -> void:
	"""
	Enable depth fog on the scene's WorldEnvironment — on EVERY platform.

	This is an intentional, owner-sanctioned desktop visual change: the one deliberate
	exception to this repo's "visual changes are web-gated" rule (see the FOG_COLOR
	comment block up top). Only the DENSITY differs per platform — that's a
	view-distance/perf concern, so it stays gated:
	  - web:     FOG_DENSITY_WEB (0.005)      — thick, masks the reduced render distance
	  - desktop: FOG_DENSITY_DESKTOP (0.0022) — thin depth haze; the long view's horizon
	                                            dissolves instead of ending at a hard edge
	"""
	# Find the WorldEnvironment. EndlessTerrain doesn't hold a hard reference to it, but in
	# main.tscn the two are SIBLINGS under the root "Main" node, so a sibling lookup via our
	# parent is the simplest robust way to reach it. Guard every step with null checks so a
	# differently-structured scene degrades gracefully (no fog) instead of crashing.
	var parent_node := get_parent()
	if parent_node == null:
		return
	var world_env := parent_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env == null:
		push_warning("Fog: no sibling WorldEnvironment found; skipping fog setup.")
		return

	var env: Environment = world_env.environment
	if env == null:
		push_warning("Fog: WorldEnvironment has no Environment resource; skipping fog.")
		return

	# DEFENSIVE COPY: the Environment is an inline SubResource shared with the editor scene.
	# We duplicate it and assign the copy back BEFORE enabling fog, so we mutate a
	# per-instance copy at runtime rather than the shared resource — the editor's saved
	# scene never sees the fog values. (We pass false so it copies the resource itself,
	# not its deep sub-resources like the Sky, which we want to keep sharing.)
	env = env.duplicate(false)
	world_env.environment = env

	# Enable exponential depth fog tinted like the sky horizon. Property names below are the
	# Godot 4.5 Environment fog API:
	#   - fog_enabled            : turn fog on
	#   - fog_light_color        : the fog's colour (matches the sky horizon → seamless edge)
	#   - fog_density            : exponential density (controls how quickly distance fades);
	#                              the one platform-gated value — see _setup_fog's docstring
	#   - fog_sun_scatter        : 0.15 = a gentle bright streak toward the warm key light,
	#                              so the haze reads sunlit instead of flat grey
	#   - fog_aerial_perspective : 0 = don't blend the sky into fog for distant geometry
	var density: float = FOG_DENSITY_WEB if OS.has_feature("web") else FOG_DENSITY_DESKTOP
	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = density
	env.fog_sun_scatter = 0.15
	env.fog_aerial_perspective = 0.0

	print("Fog enabled (density ", density, ", colour ", FOG_COLOR, ")")

func _process(_delta: float) -> void:
	"""
	Update terrain chunks every frame based on player position.

	EDUCATIONAL NOTE:
	- We only update when the player moves to a new chunk
	- This prevents unnecessary updates every frame
	"""
	if not player:
		return

	# Calculate which chunk the player is currently in
	var player_chunk := world_to_chunk(player.global_position)

	# Only update if player moved to a different chunk — OR if the multiplayer
	# focus set changed under us (a teammate crossed a chunk edge, joined or
	# left). Without the second half a far peer's ground would only be pinned
	# when the LOCAL player happened to cross a boundary, which is precisely the
	# far-apart case set_focus_points() exists for.
	if player_chunk != last_player_chunk or focus_dirty:
		focus_dirty = false
		update_chunks(player_chunk)
		last_player_chunk = player_chunk
		# THE TOWER'S ONLY PER-FRAME COST, which is to say none: it rides the
		# boundary crossing the chunk streamer already pays for, so walking a
		# whole run nowhere near the site costs one distance test per 50 m.
		_tower_stream(player.global_position)

	# TIME-SLICED FILL: build exactly ONE queued chunk per frame (see the
	# pending_chunks comment in SECTION 2). The queue is sorted nearest-first,
	# so the chunks the player is most likely to see next appear first, and the
	# per-frame cost is bounded by one chunk's generation instead of dozens.
	# (No duplicate-work check needed: the queue is rebuilt from scratch on every
	# boundary crossing from a unique-keyed Dictionary, and between crossings only
	# this line pops it, so a position can never be built twice. A queued position
	# CAN already be in active_chunks — that is the safety ring, floored
	# synchronously and still owing its content — and create_chunk expects it.)
	if not pending_chunks.is_empty():
		create_chunk(pending_chunks.pop_front())

	# TIME-SLICED TEARDOWN: free ONE queued chunk per frame, the mirror of the
	# fill above (see the pending_removals comment in SECTION 2). The queue is
	# sorted farthest-first, so the chunk the player is least likely to walk back
	# onto goes first. remove_chunk() re-checks `active_chunks`, so a position
	# that was already freed drains harmlessly.
	#
	# ...PLUS THE OVERFLOW, which is what makes this a throttle and not a leak.
	# One per frame keeps up only while the events that queue chunks are further
	# apart than their backlog is long, which they always are in practice, but
	# nothing enforces it — so past a ceiling the debt is paid in the same frame
	# rather than carried forward, and `active_chunks` can never creep upward
	# event after event.
	#
	# THE CEILING IS THE LARGEST BACKLOG A SINGLE LEGITIMATE EVENT CAN PRODUCE,
	# so no legitimate event ever trips it and every one of them stays fully
	# time-sliced. Two events queue chunks, and they can coincide:
	#   * a boundary crossing drops a COLUMN — 2 x render_distance + 1 (7 on web,
	#     11 on desktop);
	#   * a multiplayer peer leaving (or the room emptying) releases the whole
	#     pinned set at once — up to MAX_FOCUS_CHUNKS (27), which is exactly the
	#     burst this change exists to spread out, so it must sit UNDER the
	#     ceiling, not over it.
	# Anything past their sum is a rate no event produces, i.e. a backlog that is
	# actually falling behind, and freeing it now is the correct answer.
	var drain: int = 1 + maxi(0,
			pending_removals.size() - (2 * render_distance + 1 + MAX_FOCUS_CHUNKS))
	while drain > 0 and not pending_removals.is_empty():
		remove_chunk(pending_removals.pop_front())
		drain -= 1

# ============================================================================
# CHUNK MANAGEMENT FUNCTIONS
# ============================================================================

func set_focus_points(points: Array) -> void:
	"""
	Keep chunks loaded around these extra world positions as well as around the
	player — the multiplayer "far teammate" hook (bead godot-test1-s86.14).

	THIS ONLY EVER DECIDES WHICH CHUNKS STAY LOADED. It cannot, and must never,
	influence what a chunk contains: chunk content is a pure function of the
	chunk's own coords + `run_seed`, so a chunk pinned by a teammate is
	byte-identical to the one the local player would build by walking there. See
	the `focus_chunks` banner in SECTION 2.

	Call it as often as you like — an unchanged set is a no-op (one Dictionary
	compare), so the 9 Hz caller in `crocodile_lod_manager.gd` costs nothing
	while nobody moves between chunks. An EMPTY array releases every pinned
	chunk, which is what a non-master (or a peer leaving a room) publishes.

	@param points: world positions. At most `MAX_FOCUS_POINTS` are honoured and
	    at most `MAX_FOCUS_CHUNKS` chunks are pinned; see those constants for why
	    the cap exists and what it costs on web.
	"""
	var pinned: Dictionary = {}
	var honoured: int = 0
	for point: Variant in points:
		if not (point is Vector3):
			continue  # Peer input; a malformed entry is skipped, never trusted.
		if honoured >= MAX_FOCUS_POINTS:
			break
		honoured += 1
		var center := world_to_chunk(point as Vector3)
		for x in range(-FOCUS_RING, FOCUS_RING + 1):
			for z in range(-FOCUS_RING, FOCUS_RING + 1):
				if pinned.size() >= MAX_FOCUS_CHUNKS:
					break
				pinned[Vector2i(center.x + x, center.y + z)] = true

	# NO-OP ON AN UNCHANGED SET. `focus_dirty` is what makes `_process` rebuild
	# the chunk field off a boundary crossing, and rebuilding it 9 times a second
	# for a stationary room would throw away the "only on boundary crossings"
	# rule the whole time-slicing design rests on.
	if pinned == focus_chunks:
		return
	focus_chunks = pinned
	focus_dirty = true

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	"""
	Converts a world position to chunk coordinates.

	@param world_pos: Position in 3D world space
	@return Vector2i: Chunk coordinates (we only use X and Z, not Y)

	EDUCATIONAL NOTE:
	- We divide the world into a grid of chunks
	- Each chunk has integer coordinates
	- Example: Position (75, 0, -25) with chunk_size=50 -> Chunk (1, 0)
	"""
	return Vector2i(
		int(floor(world_pos.x / chunk_size)),
		int(floor(world_pos.z / chunk_size))
	)

func chunk_to_world(chunk_pos: Vector2i) -> Vector3:
	"""
	Converts chunk coordinates to world position (center of chunk).

	@param chunk_pos: Chunk coordinates
	@return Vector3: World position at the center of the chunk
	"""
	return Vector3(
		chunk_pos.x * chunk_size + chunk_size / 2.0,
		terrain_height,
		chunk_pos.y * chunk_size + chunk_size / 2.0
	)

func update_chunks(player_chunk: Vector2i) -> void:
	"""
	Updates which chunks are visible based on player position.
	Creates new chunks in range, removes chunks out of range.

	@param player_chunk: The chunk coordinates where the player is

	EDUCATIONAL NOTE:
	- This is the "magic" that makes the terrain endless
	- We maintain a square of chunks around the player
	- As the player moves, we add/remove chunks at the edges
	"""

	# STEP 1: Find all chunks that SHOULD be loaded.
	#
	# We store them as Dictionary KEYS (value `true`), not an Array, because the
	# membership test in STEP 2 (`in`) is an O(1) hash lookup on a Dictionary but a
	# LINEAR scan on an Array — with 121 desktop chunks that Array version was
	# 121×121 comparisons per boundary crossing. Same semantics, hash-speed lookup.
	var chunks_to_load: Dictionary = {}

	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos := Vector2i(player_chunk.x + x, player_chunk.y + z)
			chunks_to_load[chunk_pos] = true

	# STEP 1b: ...plus the chunks pinned by multiplayer focus points, so the room
	# master keeps simulating the crocodiles standing next to a FAR teammate.
	# Purely additive — a focus chunk is an ordinary chunk built from its own
	# coords + run_seed, and nothing downstream can tell why it was asked for.
	# `focus_chunks` is empty offline and on a non-master, so single player and
	# every non-master peer take exactly the loop above and nothing else.
	for chunk_pos: Vector2i in focus_chunks:
		chunks_to_load[chunk_pos] = true

	# STEP 2: Queue the chunks that are too far away for TIME-SLICED teardown.
	#
	# Rebuilt from scratch, exactly like pending_chunks in STEP 3 and for the
	# same reasons: this only runs on boundary crossings, so a fresh derivation
	# from `active_chunks` is cheap, dedupes for free, and drops any chunk that
	# came back into range (which is also what makes walking back over a queued
	# chunk safe — it never left the tree). _process drains it at one chunk per
	# frame; anything still out of range is simply re-queued next crossing.
	pending_removals.clear()

	for chunk_pos in active_chunks.keys():
		if chunk_pos not in chunks_to_load:
			pending_removals.append(chunk_pos)

	# Farthest-first — the mirror of the fill's nearest-first. The chunk deepest
	# behind the player is the one least likely to be walked back onto, so it is
	# the one whose nodes we can afford to destroy first.
	pending_removals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - player_chunk).length_squared() > (b - player_chunk).length_squared())

	# STEP 3: Create new chunks that don't exist yet — TIME-SLICED.
	#
	# Only the SAFETY RING (Chebyshev distance <= SYNC_RING around the player —
	# the chunks the player could physically reach this frame) is touched right
	# now, and even there only its GROUND: the floor is the entire safety
	# guarantee, and it is ~3% of a chunk's build cost (see the bare_chunks
	# comment in SECTION 2 for the measurement). EVERY missing chunk — ring
	# included — then goes into pending_chunks, which _process drains at one
	# chunk per frame, nearest-first, so the ring's content lands first.
	#
	# Rebuilding the queue from scratch here is deliberate: this only runs on
	# boundary crossings, and a fresh build both dedupes for free and drops any
	# previously-queued chunk that fell out of range. Generation ORDER doesn't
	# matter for content — see the determinism note above pending_chunks in
	# SECTION 2.
	pending_chunks.clear()

	for chunk_pos in chunks_to_load:
		# A chunk that is loaded AND populated needs nothing. A chunk that is
		# loaded but still bare (ground laid on an earlier crossing, content not
		# drained yet) must stay in the queue, or it would sit there floorless
		# forever — this is the one place that would silently leak an empty chunk.
		if chunk_pos in active_chunks and chunk_pos not in bare_chunks:
			continue
		var cheb := maxi(absi(chunk_pos.x - player_chunk.x), absi(chunk_pos.y - player_chunk.y))
		if cheb <= SYNC_RING:
			_ensure_chunk_ground(chunk_pos)
		pending_chunks.append(chunk_pos)

	# Nearest-first: sort by squared distance to the player's chunk so the fill
	# grows outward from the player (the far edge, hidden by fog, comes last).
	pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - player_chunk).length_squared() < (b - player_chunk).length_squared())

func _ensure_chunk_ground(chunk_pos: Vector2i) -> MeshInstance3D:
	"""
	Lay a chunk's GROUND — the shared plane mesh plus its collision box — and
	register it, or hand back the node if it already exists.

	@param chunk_pos: Chunk coordinates
	@return MeshInstance3D: the chunk node, ready to be populated

	This is the cheap half of create_chunk, split out so update_chunks can give
	the safety ring a floor without paying for its contents (see the bare_chunks
	comment in SECTION 2 for the measurement that motivated the split). It is
	IDEMPOTENT on purpose: it is called both from the synchronous safety path and
	again from create_chunk when the same chunk's turn comes up in the queue, and
	building a second mesh + body over the first would leak the first one.

	The chunk enters `active_chunks` here, at ground time — everything that
	iterates chunks (removal, the F3 count, the multiplayer focus set) therefore
	sees it from the moment it can be stood on, which is the only moment that
	matters to any of them.
	"""
	if chunk_pos in active_chunks:
		return active_chunks[chunk_pos]

	# Create a new MeshInstance to hold the chunk's visual geometry
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Chunk_%d_%d" % [chunk_pos.x, chunk_pos.y]

	# All chunks share ONE PlaneMesh resource (see _get_shared_ground_mesh) —
	# allocating a fresh subdivided mesh per chunk was pure waste.
	mesh_instance.mesh = _get_shared_ground_mesh()

	# A flat ground plane can only ever shadow itself — skip it in the shadow
	# passes entirely. Blocks/crocs still cast onto it; it just casts nothing.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Position the chunk in the world
	mesh_instance.position = chunk_to_world(chunk_pos)

	# Add the GROUND collision so the player doesn't fall through the plane.
	#
	# DESIGN CHOICE (Task 5 — consolidated collision): we keep the GROUND collision
	# in its OWN StaticBody3D, SEPARATE from the per-chunk *block* body created in
	# create_chunk. The ground is a single shape created once per chunk, so folding
	# it into the block body would save exactly one node and only muddle the code —
	# there is no meaningful win. The real win is collapsing the MANY per-block
	# bodies (one per decorative cube/slab — dozens per chunk) into a single body;
	# that's what the block_body there does. Ground and blocks share the same
	# default collision layer/mask, so keeping them in two bodies is purely
	# cosmetic, not behavioural.
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()

	box_shape.size = Vector3(chunk_size, 0.1, chunk_size)
	collision_shape.shape = box_shape

	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)

	# Add to scene and register in our dictionary. `bare_chunks` is the debt note:
	# create_chunk clears it once the content is in.
	add_child(mesh_instance)
	active_chunks[chunk_pos] = mesh_instance
	bare_chunks[chunk_pos] = true
	return mesh_instance

func create_chunk(chunk_pos: Vector2i) -> void:
	"""
	Creates a new terrain chunk at the specified chunk coordinates.

	@param chunk_pos: Chunk coordinates where to create the terrain

	EDUCATIONAL NOTE:
	- We create a simple flat plane mesh procedurally
	- Each chunk is a MeshInstance3D with collision
	- In advanced games, you could add noise/procedural generation here!
	"""

	# ALREADY POPULATED? NOTHING TO DO. Loaded-and-not-bare is the exact inverse
	# of the "still owes its content" test update_chunks uses, so this is the same
	# statement in one place: content is additive (props, coins, crocodiles all
	# get PARENTED to the chunk), so a second run over a finished chunk would
	# double everything in it rather than overwrite it. The guard lives here, in
	# the shared function, so `build_ring_now()` below can populate a chunk out of
	# band and leave its stale entry in `pending_chunks` to drain to a harmless
	# no-op — the same way remove_chunk() re-checks `active_chunks`.
	if chunk_pos in active_chunks and chunk_pos not in bare_chunks:
		return

	# The ground half — freshly laid, or already there because this chunk is one
	# of the safety-ring chunks update_chunks floored synchronously.
	var mesh_instance := _ensure_chunk_ground(chunk_pos)
	bare_chunks.erase(chunk_pos)

	# Spawn objects in this chunk if enabled. This returns the footprint of every
	# block placed (walls included) so crocodiles can avoid spawning inside them,
	# and fills `platforms` with walkable structure tops for patrolling crocodiles.
	var obstacles: Array = []
	var platforms: Array = []

	# ------------------------------------------------------------------------
	# The two halves of every chunk's decorative blocks (created together,
	# consumed separately):
	#
	#   1. block_batch — the VISUAL half (Task 4). As blocks are created they no
	#      longer instance their own MeshInstance3D; each appends a
	#      { "transform": Transform3D, "color": Color } entry here, and AFTER
	#      generation we build ONE MultiMeshInstance3D rendering all of them in a
	#      single draw call.
	#
	#   2. block_body — the COLLISION half (Task 5). ONE StaticBody3D for the WHOLE
	#      chunk's blocks; each block adds its own CollisionShape3D child to it
	#      (instead of every block getting its own StaticBody3D). For STATIC
	#      geometry a single body with many shape children is physically IDENTICAL
	#      to many one-shape bodies — Godot collides against each shape the same
	#      way regardless of how the shapes are grouped under bodies — but it cuts
	#      the node count for blocks by ~25× (one body instead of one-per-block),
	#      which is a big web/CPU win with zero collision change.
	#
	# We create block_body up front and thread it (alongside block_batch) down the
	# whole spawn call chain so create_box can hang each block's shape on it.
	var block_batch: Array = []
	var block_body := StaticBody3D.new()
	block_body.name = "BlockCollision"
	# Default collision layer/mask (1/1) — IDENTICAL to the old per-block bodies,
	# which never set them. Leaving the defaults keeps player collision and
	# crocodile avoidance raycasts hitting blocks exactly as before.

	if spawn_objects:
		obstacles = spawn_objects_in_chunk(chunk_pos, platforms, block_batch, block_body)

	# Rare lost-civilization artifact (independent ARTIFACT_SALT hash stream — no
	# shared RNG draws consumed). ORDERING REQUIREMENT: this must run AFTER
	# spawn_objects_in_chunk (so its footprint appends to the finished obstacles
	# list) and BEFORE _build_block_multimesh / the block_body attach below, so
	# the artifact's stone joins the chunk's single MultiMesh draw call and its
	# single consolidated collision body.
	spawn_artifact_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# Biome geometry — cacti / trees / massifs, depending on the biome under this
	# chunk's centre (independent BIOME_SALT hash stream, no shared RNG draws
	# consumed). SAME ORDERING REQUIREMENT as the artifact above, for the same
	# reasons: after spawn_objects_in_chunk so its footprints append to the
	# finished obstacles list, and before _build_block_multimesh / the block_body
	# attach so all its stone and wood joins the chunk's ONE MultiMesh draw call
	# and ONE collision body.
	spawn_biome_content_in_chunk(chunk_pos, obstacles, block_batch, block_body)

	# Rare nomad camp — a dome-hut village round a fire pit (independent CAMP_SALT
	# hash stream, no shared RNG draws consumed). SAME ORDERING REQUIREMENT as the
	# artifact and the biome content above, for the same reasons: after them so it
	# can re-check its spot against the finished obstacles list (and append its own
	# footprint to it), and before _build_block_multimesh / the block_body attach so
	# all its hut shell, stone and wood joins the chunk's ONE MultiMesh draw call
	# and ONE collision body. Note it runs BEFORE spawn_crocodiles_in_chunk below —
	# that is what lets its single footprint keep crocodiles out of the camp.
	spawn_camp_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# A rare geo landmark — a recognizable famous place (independent LANDMARK_SALT
	# hash stream, no shared RNG draws consumed). SAME ORDERING REQUIREMENT as the
	# three above, for the same two reasons: (a) it must run after them so its
	# candidate loop is judged against the finished obstacles list (and its own
	# footprint appends to it), and before _build_block_multimesh / the block_body
	# attach so all its stone joins the chunk's ONE MultiMesh draw call and ONE
	# collision body; (b) it must run BEFORE the chest so a chest is never placed
	# inside a landmark — the chest keeps its "last of the family" position, and the
	# only behavioural consequence is that in a landmark chunk the chest's candidate
	# loop now also has to clear the landmark footprint. It runs BEFORE
	# spawn_crocodiles_in_chunk below, which is what lets its single footprint keep
	# crocodiles out of the monument.
	spawn_landmark_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# A treasure chest — the small, common third member of the artifact/camp family
	# (independent CHEST_SALT hash stream, no shared RNG draws consumed). SAME
	# ORDERING REQUIREMENT as the three above, for the same reasons: after them so
	# its candidate loop is judged against the finished obstacles list (and its own
	# footprint appends to it), and before _build_block_multimesh / the block_body
	# attach so its wood and brass join the chunk's ONE MultiMesh draw call and ONE
	# collision body. It runs LAST of the five so a chest can never be placed inside
	# a camp, an artifact or a landmark — the reverse order would let a camp be
	# pitched on top of a chest that was already there.
	spawn_chest_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# Build the chunk's batched block visuals. If any blocks were placed, collapse
	# them all into one MultiMeshInstance3D parented to this chunk (so it is freed
	# automatically when the chunk unloads, like every other per-chunk node).
	if not block_batch.is_empty():
		_build_block_multimesh(mesh_instance, block_batch)

	# Attach the chunk's single block-collision body — but only if it actually
	# collected shapes. A chunk with no blocks (rare) would otherwise leave an empty
	# StaticBody3D in the tree; an empty body is harmless (it never collides), but we
	# free it to keep the node count honest. If it has shapes, parent it to the chunk
	# so it unloads automatically when the chunk does (same per-chunk parenting rule
	# as the MultiMesh visuals and everything else).
	if block_body.get_child_count() > 0:
		mesh_instance.add_child(block_body)
	else:
		block_body.queue_free()

	# Spawn crocodiles in this chunk if enabled
	if spawn_crocodiles:
		spawn_crocodiles_in_chunk(chunk_pos, mesh_instance, obstacles)
		# Rare crocodiles that patrol an elevated platform (mound summit / wall ridge)
		spawn_platform_crocodiles(chunk_pos, mesh_instance, platforms)
		# Rare BOSS crocodiles guarding the coin road (deterministic, station-
		# indexed — its own BOSS_SEED hash stream, no shared RNG draws consumed).
		# Gets `obstacles` like its siblings so a 2.5x-6x boss is never wedged
		# inside a wall/mound/tree/mountain right on the player's path.
		spawn_bosses_in_chunk(chunk_pos, mesh_instance, obstacles)

	# Lay this chunk's slice of the coin road (deterministic station-indexed trail;
	# coins sit at ground height, perching on a climbable block where the road
	# crosses one — see spawn_coins_in_chunk).
	if spawn_coins:
		spawn_coins_in_chunk(chunk_pos, mesh_instance, obstacles)

	# TELEMETRY, counted HERE and not in _ensure_chunk_ground: the counter exists
	# to explain frame spikes (see its comment in SECTION 2), and after the
	# ground/content split it is the content that costs anything — ~97% of a
	# chunk. Counting the ground instead would credit the cheap frame and report
	# "+0 chunks" on the frame that actually did the work.
	chunks_created_total += 1

func spawn_objects_in_chunk(chunk_pos: Vector2i, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> Array:
	"""
	Spawns this chunk's ground clutter: themed scattered props (see _build_prop)
	and — sometimes — one themed feature structure (barrier wall / run-through
	lane / gate / terraced mound, dressed for the territory it stands in).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param platforms: Out-param; feature structures append walkable-top descriptors
	                  here for patrolling crocodiles.
	@param block_batch: Out-param; each block created appends its
	                  { "transform": Transform3D, "color": Color } here so the
	                  caller can render them all as one MultiMesh (visual batching).
	@param block_body: The chunk's single shared block-collision StaticBody3D; each
	                  block adds its CollisionShape3D child to this body (Task 5).
	@return Array of obstacle footprints ({ "pos": Vector3, "radius": float }) so
	        the crocodile spawner can keep its NPCs out of the blocks.

	EDUCATIONAL NOTE:
	- We use chunk coordinates as a seed for deterministic randomness
	- This means the same chunk always generates the same objects
	- Objects are parented to the chunk so they're removed when chunk is removed
	"""

	# Use chunk coordinates (+ this run's seed) to create a unique but consistent seed.
	# Within a run the same chunk always regenerates the same objects; across runs the
	# mixed-in run_seed makes the layout fresh (see the run_seed doc block up top).
	var seed_value := hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Half the chunk width — handy for keeping things inside the chunk bounds.
	var half_chunk := chunk_size / 2.0

	# World-space centre of this chunk. Block positions below are chunk-LOCAL, so
	# every biome/river question (which is asked in WORLD space, because the biome
	# field is one continuous world-space field) adds this first.
	var chunk_center := chunk_to_world(chunk_pos)

	# Footprints of every block we place, returned so crocodiles can avoid them.
	var obstacles: Array = []

	# Occasionally build one feature structure first (wall / lane / gate / mound),
	# so scattered blocks can be placed around it (the scatter loop below checks
	# against these footprints).
	#
	# The THRESHOLD is per-territory (see _structure_chance_at) while the DRAW is
	# not: one rng.randf() either way, so the shared chunk stream is unaffected by
	# which biome this chunk sits in.
	if rng.randf() < _structure_chance_at(chunk_center):
		spawn_feature_structure(rng, half_chunk, chunk_center, obstacles, platforms, block_batch, block_body)

	# Is this a DESERT chunk? A desert keeps only one scattered block in
	# DESERT_BLOCK_KEEP_EVERY, which is what makes it read as sparse.
	#
	# EDUCATIONAL NOTE — WHY THIS IS A TARGET AND NOT A ROLL: the obvious
	# "rng.randf() < 0.33" inside the loop would insert a draw into the SHARED
	# chunk stream, and every block, structure, crocodile and coin drawn after it
	# would shift. Lowering the loop's TARGET instead adds no draw at all.
	#
	# (An earlier version keyed the skip off the loop's `attempts` counter. That
	# was silently a no-op: max_attempts is objects_per_chunk * 3 and the keep-rule
	# was `attempts % 3`, leaving exactly objects_per_chunk eligible attempts — so
	# the quota still filled and a desert kept ~84% of its blocks, not a third.)
	var desert_chunk := biome_at(chunk_center.x, chunk_center.z) == Biome.DESERT
	var object_target := objects_per_chunk
	if desert_chunk:
		object_target = maxi(1, objects_per_chunk / DESERT_BLOCK_KEEP_EVERY)

	# Store positions of scattered objects to check spacing between them
	var spawned_positions: Array[Vector3] = []

	# Try to spawn objects with proper spacing
	var attempts := 0
	var max_attempts := objects_per_chunk * 3  # Allow multiple attempts per object

	while spawned_positions.size() < object_target and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		# Leave some margin from edges for better appearance
		var margin := 2.0
		var random_x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var random_z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var object_pos := Vector3(random_x, 0, random_z)

		# Check if this position is far enough from other scattered objects...
		var valid_position := true
		for existing_pos in spawned_positions:
			if object_pos.distance_to(existing_pos) < min_object_spacing:
				valid_position = false
				break

		# ...and not sitting on top of a wall block we placed above.
		if valid_position:
			for ob in obstacles:
				if Vector2(random_x - ob.pos.x, random_z - ob.pos.z).length() < min_object_spacing:
					valid_position = false
					break

		# ...and not standing in a river. Blocks in the water would break the
		# "wade across, don't climb" read of a river band.
		#
		# EDUCATIONAL NOTE — WHY THIS TEST SITS HERE, after the draws:
		# random_x/random_z have already been drawn, so the RNG has already
		# advanced. Rejecting here is a `continue` exactly like the spacing test
		# above — it removes a placement without inserting or removing a draw, so
		# every chunk that does NOT touch a river regenerates byte-identically to
		# before biomes existed. Testing BEFORE the draws (or drawing a fresh
		# position on rejection) would shift the whole stream and reshuffle the
		# world. Same discipline in every biome exclusion below.
		if valid_position and is_river_at(chunk_center + object_pos):
			valid_position = false

		# ...and not on the tower's site. Same post-draw rule as the river test
		# directly above, for the same reason. object_size_max * PROP_RADIUS_FACTOR
		# is the widest a prop can ever be (prop_selfcheck measures that bound), so
		# passing it keeps the prop's BOXES out of the disc and not just its centre.
		if valid_position and tower_excludes(
				chunk_center.x + object_pos.x, chunk_center.z + object_pos.z,
				object_size_max * PROP_RADIUS_FACTOR):
			valid_position = false

		if not valid_position:
			continue

		# ----- THE PROP: exactly TWO draws from the shared chunk stream ----------
		# `size` is the prop's overall scale (the same draw the bare cube used) and
		# the randi() below is the PROP SEED. Both are unconditional, so the chunk
		# stream advances by the same amount at every accepted spot no matter which
		# biome we are in or which variant the private RNG picks — that fixed cost
		# is what lets prop complexity change freely without reshuffling the
		# crocodiles, coins and structures that draw from this same stream.
		# (See the THEMED SCATTERED PROPS banner in SECTION 1.)
		var size := rng.randf_range(object_size_min, object_size_max)
		var prop_seed := rng.randi()
		spawned_positions.append(object_pos)

		# Everything below this line runs on the PRIVATE prop RNG. _build_prop is
		# handed no shared rng at all, which is what makes the rule above
		# structural rather than a discipline somebody has to remember.
		var prop := _build_prop(
			Vector3(random_x, 0.0, random_z), size, prop_seed, chunk_center, block_batch, block_body
		)

		# Record the footprint exactly as the bare cube did — same keys, same
		# meaning. `radius` is an honest bound on every box the builder emitted
		# (prop_selfcheck.gd measures that), `top` is the flat surface a coin may
		# perch on, and `climbable` says whether it is a rest spot at all: the one
		# variant with no usable top (the desert bone pile — a heap of tilted ribs)
		# records false, so _settle_coin_y SKIPS a road coin over it rather than
		# floating one, exactly as it does over a tree canopy.
		obstacles.append({
			"pos": Vector3(random_x, 0, random_z),
			"radius": prop.radius,
			"top": prop.top,
			"climbable": prop.climbable,
		})

	return obstacles

func _structure_chance_at(chunk_center: Vector3) -> float:
	"""
	How likely THIS chunk is to get a feature structure.

	@param chunk_center: World-space centre of the chunk.
	@return: structure_chance, scaled down in the mountain band.

	A THRESHOLD, NOT A ROLL. spawn_objects_in_chunk still draws exactly one
	rng.randf() and compares it against this number, so no draw is inserted or
	removed anywhere and the shared chunk stream is untouched by the biome —
	the same discipline DESERT_BLOCK_KEEP_EVERY follows by lowering a TARGET
	rather than rolling per candidate. biome_at is a pure function of world
	position, so the gate stays a pure function of chunk coords + run_seed.

	The consequence when the gate DOES reject is the documented one: the whole
	structure's draw sequence is skipped, so that mountain chunk's scattered
	blocks land differently than they would have. Within-run purity is unharmed.
	"""
	if biome_at(chunk_center.x, chunk_center.z) == Biome.MOUNTAIN:
		return structure_chance * MOUNTAIN_STRUCTURE_CHANCE_FACTOR
	return structure_chance

func _structure_stone(theme: Dictionary, rng: RandomNumberGenerator) -> Color:
	"""
	One solid box's colour, sampled off this territory's two-colour ramp.

	@param theme: A STRUCTURE_THEMES row.
	@param rng: The chunk's seeded RNG — one draw, so the sequence cost of a
	            themed box is a constant the builders can reason about.
	@return: The colour to hand create_box as its color_override.

	One lerp off a curated pair, exactly like the RAMP_* blocks it replaces —
	so a structure varies stone to stone without any territory's structures
	ever sharing a colour with another's. prop_selfcheck.gd measures that: it
	requires every emitted colour to lie on its own theme's segment, and the
	four segments to be pairwise distinct.
	"""
	var a: Color = theme["stone_a"]
	var b: Color = theme["stone_b"]
	return a.lerp(b, rng.randf())

func spawn_feature_structure(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Pick and build one "feature" structure for variety, dressed in the territory
	it stands in: a barrier wall, a run-through lane, a gate, or a terraced mound.
	Walls, mounds and the forest's log bridge also register a walkable top
	(platforms) that a patrolling crocodile can be placed on.

	@param rng: The chunk's seeded RNG (so the choice is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World-space centre of the chunk. TWO jobs: it picks the
	                  territory (a pure function of chunk coords, so choosing the
	                  mix and the palette costs no RNG draw), and each builder
	                  turns its chunk-LOCAL centre into a world position for the
	                  river test — structures never stand in the water.
	@param obstacles: Footprint list each piece is appended to (crocodiles + coins)
	@param platforms: Walkable-top descriptors for patrolling crocodiles
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body, threaded down to
	                  create_box so each block's shape hangs on it (Task 5)

	THE MAYAN STEP-PYRAMID IS GONE and is not coming back here. The owner called
	it out as the ugliest thing in the field, and the ROLE it played — a climbable
	stepped centrepiece with a flat platform top — is now spawn_terraced_mound's.
	A properly-built Giza trio exists, in the geo-landmark registry
	(landmark_builders.gd), where a named recognizable DESTINATION belongs;
	territories stay anonymous ambience. Don't reintroduce a "nicer pyramid" here.

	EDUCATIONAL NOTE — the river rule for structures: a structure is placed as ONE
	object, so it gets ONE test, on its chosen centre, taken right after the draws
	that produced that centre. A footprint-vs-band intersection test would be more
	precise and much fiddlier for a band that winds; a centre test is enough to keep
	walls and mounds out of the water, which is all the rule is for.

	ONE PICK DRAW, POST-DRAW DISPATCH. The `rng.randf()` below is the same single
	draw the global table used; only the thresholds it is compared against are now
	per-territory (STRUCTURE_MIX). A band of zero width is how mountain declines
	the mound with no special case here.
	"""
	var biome := biome_at(chunk_center.x, chunk_center.z)
	var theme: Dictionary = STRUCTURE_THEMES[biome]
	var mix: Array = STRUCTURE_MIX[biome]

	var pick := rng.randf()
	if pick < mix[0]:
		spawn_wall(rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)
	elif pick < mix[1]:
		spawn_corridor(rng, half_chunk, chunk_center, theme, obstacles, block_batch, block_body)
	elif pick < mix[2]:
		spawn_gate(rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)
	else:
		spawn_terraced_mound(rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)

func spawn_terraced_mound(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a terraced mound — the climbable stepped centrepiece that REPLACES the
	Mayan step-pyramid. A plains ruin mound, a desert mesa, a forest tor: 2-4 wide
	irregular terraces, each yawed and nudged off the one below, with a flat top
	you can stand on.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the base
	@param theme: This territory's STRUCTURE_THEMES row
	@param obstacles: Footprint list (one entry for the whole base, with the top
	                  height as its top so a coin can perch up there)
	@param platforms: Gets the flat top registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)

	WHY THIS IS NOT A PYRAMID, in the two ways that matter:
	  * FEW, WIDE terraces (2-4, each 1.2-2.2 m) instead of 3-15 thin concentric
	    slabs. That is what makes it read as a weathered hill rather than a temple.
	  * Every terrace is a NON-SQUARE slab carrying its own yaw and a lateral
	    nudge, so no two edges line up and there is no axis to sight down.

	WHAT IT KEEPS, because these are the pyramid's gameplay job and not its look:
	  * ONE round footprint of radius base_size * 0.71 with the summit as its top.
	    That radius stays well above MOUNTAIN_AVOID_RADIUS (2.0) at every drawable
	    base size (8 m base -> 5.68 m), so a massif still refuses to grow through a
	    mound exactly as it refused to grow through a pyramid.
	  * A PLATFORM at the summit, so patrol crocodiles keep their perch.
	  * A CLIMBABLE ladder: terrace height is drawn at or under PROP_MAX_STEP, so
	    every step up is inside the player's jump arc. prop_selfcheck.gd measures
	    the emitted boxes rather than trusting this comment.
	"""
	# Bases run from a modest hummock to a real mesa. Terraces are FEW and TALL,
	# which is the whole difference from a ziggurat.
	var base_size := rng.randf_range(8.0, 20.0)
	var terraces := rng.randi_range(2, 4)
	# Capped at PROP_MAX_STEP: a terrace taller than the jump arc turns the
	# "climbable" footprint into a lie and floats any road coin that perches on it.
	var terrace_h := minf(rng.randf_range(1.2, 2.2), PROP_MAX_STEP)

	# Keep the whole base inside the chunk. The jitter allowance is in the bound
	# because an upper terrace may sit that far off the base's centre.
	# The ROTATED extent, not the half-width — see MOUND_ROT_EXTENT for why the
	# difference is load-bearing at a chunk seam.
	var limit := half_chunk - (base_size * MOUND_ROT_EXTENT + 1.0 + MOUND_TERRACE_JITTER)
	if limit <= 0.0:
		return  # chunk too small for this mound; skip it
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# No mounds in the water (centre test, taken right after the centre draws).
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if is_river_at(chunk_center + Vector3(cx, 0.0, cz)) \
			or tower_excludes(chunk_center.x + cx, chunk_center.z + cz, half_chunk):
		return

	var y := 0.0
	var w := base_size
	var top_span := base_size * 0.5   # the summit slab's own half-width (for the cap)
	var top_half := base_size * 0.5   # the largest AXIS-ALIGNED square inside it
	var top_x := cx
	var top_z := cz

	for i in terraces:
		# The base terrace sits square on the spot so the footprint circle is
		# honest; everything above it wanders.
		var jx := 0.0
		var jz := 0.0
		if i > 0:
			jx = rng.randf_range(-MOUND_TERRACE_JITTER, MOUND_TERRACE_JITTER)
			jz = rng.randf_range(-MOUND_TERRACE_JITTER, MOUND_TERRACE_JITTER)
		var d := w * rng.randf_range(0.78, 1.0)
		# YAW, never tilt: a yawed box still presents a flat top to stand on,
		# which is what the climb ladder and the patrol platform both need.
		var yaw := rng.randf_range(-MOUND_TERRACE_YAW, MOUND_TERRACE_YAW)
		create_box(
			Vector3(cx + jx, y + terrace_h * 0.5, cz + jz), Vector3(w, terrace_h, d), yaw,
			rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
		)
		y += terrace_h
		# THE PLATFORM MUST BE MEASURED IN THE SLAB'S OWN YAW FRAME. set_confinement
		# clamps a patrol crocodile against WORLD X/Z extents, but the summit slab is
		# turned by `yaw`, so the largest axis-aligned square that really fits inside
		# a (w, d) box turned by yaw has half-extent min(w, d)/2 / (|cos| + |sin|) —
		# the corner of the square projects onto BOTH box axes. Take the plain
		# half-width and a guard paces off the corner of a yawed summit and falls:
		# measured before this divisor, a 11.34 x 9.87 slab at yaw 0.087 registered
		# 4.63 m of half-extent whose corner reached 5.02 m along the slab's own Z,
		# past its 4.93 m half-depth.
		top_span = minf(w, d) * 0.5
		top_half = top_span / (absf(cos(yaw)) + absf(sin(yaw)))
		top_x = cx + jx
		top_z = cz + jz
		w *= rng.randf_range(0.58, 0.72)

	# A thin themed film over the summit — snow-pale slab on a mountain fort's
	# stub, moss on a forest tor. collide = false, so it cannot raise or roughen
	# the surface the platform and the climbable footprint both name.
	var cap: Color = theme["cap"]
	if cap.a > 0.0:
		create_box(
			Vector3(top_x, y + 0.06, top_z), Vector3(top_span * 1.9, 0.12, top_span * 1.9),
			rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, cap, false
		)

	# Fallen stone shed off the terraces, ringed OUTSIDE the base slab but inside
	# the declared footprint radius, so it never obstructs the climb.
	var trim: Color = theme["trim"]
	for _i in 3:
		var ts := base_size * rng.randf_range(0.05, 0.09)
		var ta := rng.randf_range(0.0, TAU)
		var ring := base_size * 0.58
		create_box(
			Vector3(cx + cos(ta) * ring, ts * 0.4, cz + sin(ta) * ring),
			Vector3(ts, ts * 0.8, ts * 1.2), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4), trim, false
		)

	# One footprint for the whole base; top = summit height. Mounds are climbable
	# via their terraces, so a coin on the summit is reachable (just a climb).
	#
	# ponytail: ONE CIRCLE WITH ONE TOP is the whole vocabulary the coin and
	# crocodile rules speak (the same ceiling CLAUDE.md records for landmarks), so
	# a road coin landing near the rim is perched at the SUMMIT height with only
	# the base terrace under it. That is inherited from the pyramid, not
	# introduced here, and it is the cheaper end of it: measured over 25x25 chunks
	# x 4 seeds, perched road coins with no floor under them went 15 -> 13 and the
	# worst air gap 4.43 m -> 2.86 m (coins buried IN stone stayed 0). The real fix
	# is a richer footprint (per-tier tops, or a solid-centre height) in
	# _settle_coin_y, which every landmark, camp and artifact would have to learn
	# — deliberately out of this bead.
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": base_size * 0.71, "top": y, "climbable": true })

	# Register the flat summit as a patrol platform (if it's big enough to stand on).
	# `top` equals `center.y` here — the summit slab IS the tallest SOLID thing in
	# its own footprint (the themed cap above it is collide = false, and the fallen
	# trim is ringed outside the slab), so the patrol guard's drop-in height is the
	# surface height. A wall's is not; see the platform "top" note in spawn_wall
	# for why the two are separate fields at all.
	var plat_half := top_half - 0.3
	if plat_half > 0.4:
		platforms.append({ "center": Vector3(top_x, y, top_z), "half": Vector2(plat_half, plat_half), "top": y })

func spawn_gate(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a gate: two uprights with a beam across the top, leaving an opening to
	walk through. The territory decides which KIND of gate:

	  * STRUCT_GATE_LINTEL (desert, mountain) — the shipped monumental gate. The
	    pillars are about as tall as a full jump, so reaching the coin that perches
	    on the lintel is genuinely hard: hop onto a pillar, then up onto the beam.
	    That's intentional "hard to reach" gameplay and is deliberately NOT held to
	    the PROP_MAX_STEP climb rule.
	  * STRUCT_GATE_ARCH (plains) — the same gate, broken: one pillar stunted, the
	    beam a stub that no longer spans the opening.
	  * STRUCT_GATE_LOG (forest) — a felled giant across two stumps. The deck is
	    low and wide enough to be a WALKABLE TOP, so this one registers a patrol
	    platform and a climbable perch, and its whole height stays inside
	    PROP_MAX_STEP so you can hop straight onto it from the ground.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the gate
	@param theme: This territory's STRUCTURE_THEMES row
	@param obstacles: Footprint list (pillars, plus a perch on the beam)
	@param platforms: Gets the log bridge's deck registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var style := int(theme["gate_style"])
	var log_bridge := style == STRUCT_GATE_LOG

	var pillar_w := rng.randf_range(1.3, 1.8)
	# ONE height draw for every style, scaled rather than re-drawn, so the draw
	# count does not depend on the territory. A log bridge's stumps are low: the
	# 0.40 factor puts the finished deck at 1.98-2.54 m, i.e. inside PROP_MAX_STEP
	# (2.6) and therefore mountable from flat ground in a single hop.
	var pillar_h := rng.randf_range(2.7, 3.1)
	if log_bridge:
		pillar_h *= 0.40
	var depth := rng.randf_range(1.3, 2.0)
	if log_bridge:
		depth *= 1.15  # a giant trunk is deep enough to walk along
	var opening := rng.randf_range(3.0, 4.5)
	var lintel_h := rng.randf_range(0.9, 1.3)
	var total_w := opening + 2.0 * pillar_w  # full span across both uprights

	# A broken arch loses one upright to time. Drawn unconditionally so the
	# sequence is style-independent; only used by the arch.
	var stunt := rng.randf_range(0.5, 0.72)
	var stub := rng.randf_range(0.45, 0.7)

	# Pillars are separated along X (and you walk through along Z) or vice-versa.
	var along_x := rng.randf() < 0.5

	# Conservative bound that fits the gate whichever way it's turned.
	var limit := half_chunk - (total_w * 0.5 + 1.0)
	if limit <= 0.0:
		return
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# No gates in the water (centre test, taken right after the centre draws).
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if is_river_at(chunk_center + Vector3(cx, 0.0, cz)) \
			or tower_excludes(chunk_center.x + cx, chunk_center.z + cz, half_chunk):
		return

	# Distance from the gate centre to each pillar's centre.
	var half_span := opening * 0.5 + pillar_w * 0.5

	for pillar_sign in 2:
		var s := -1.0 if pillar_sign == 0 else 1.0
		var px: float = cx + (s * half_span if along_x else 0.0)
		var pz: float = cz + (0.0 if along_x else s * half_span)
		# The broken arch's second upright is a stump.
		var ph := pillar_h
		if style == STRUCT_GATE_ARCH and pillar_sign == 1:
			ph *= stunt
		# Pillar is pillar_w across the span axis and `depth` across the other.
		var pillar_dims: Vector3 = Vector3(pillar_w, ph, depth) if along_x else Vector3(depth, ph, pillar_w)
		create_box(
			Vector3(px, ph * 0.5, pz), pillar_dims, 0.0,
			rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
		)
		# Each pillar is its own footprint, so crocodiles can still pass through
		# the opening between them.
		# `guarded` only for the log bridge — it is the one gate style that registers
		# a patrol deck, so it is the one whose stone a massif must keep off.
		obstacles.append({ "pos": Vector3(px, 0, pz), "radius": maxf(pillar_w, depth) * 0.71, "top": ph, "climbable": true, "guarded": log_bridge })

	# The beam. An arch's is a shortened stub pushed back over the tall upright;
	# every style keeps it UNTILTED, because a tilted beam has no flat top and the
	# perch footprint below promises one.
	var beam_w := total_w
	var beam_shift := 0.0
	if style == STRUCT_GATE_ARCH:
		beam_w = total_w * stub
		beam_shift = -(total_w - beam_w) * 0.5  # slid onto the surviving pillar
	var beam_dims: Vector3 = Vector3(beam_w, lintel_h, depth) if along_x else Vector3(depth, lintel_h, beam_w)
	var beam_x: float = cx + (beam_shift if along_x else 0.0)
	var beam_z: float = cz + (0.0 if along_x else beam_shift)
	create_box(
		Vector3(beam_x, pillar_h + lintel_h * 0.5, beam_z), beam_dims, 0.0,
		rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
	)

	var beam_top := pillar_h + lintel_h

	# A cornice over an intact lintel — collide = false, so it can never raise the
	# surface the perch footprint (and, for a log bridge, the platform) names.
	var cap: Color = theme["cap"]
	if cap.a > 0.0 and not log_bridge:
		var cornice: Vector3 = Vector3(beam_w * 1.06, 0.16, depth * 1.2) if along_x else Vector3(depth * 1.2, 0.16, beam_w * 1.06)
		create_box(
			Vector3(beam_x, beam_top + 0.08, beam_z), cornice, 0.0,
			rng, block_batch, block_body, 0.0, cap, false
		)

	# Register the beam centre as a coin perch. For a log bridge it is a genuine
	# rest spot one hop off the ground; for the other styles it is the shipped
	# deliberately-awkward one.
	obstacles.append({ "pos": Vector3(beam_x, 0, beam_z), "radius": 1.0, "top": beam_top, "climbable": true, "guarded": log_bridge })

	# THE LOG BRIDGE IS THE ONE GATE WITH A WALKABLE DECK, so it is the one gate
	# that feeds spawn_platform_crocodiles. Half-extents are the beam's own, inset
	# so a patrol never paces off the end.
	#
	# `top` equals `center.y` here — the beam IS the tallest solid thing in its own
	# footprint, and the one thing that could stand above it (the cornice) is built
	# only for a NON-log-bridge gate, so it can never be over this deck. See the
	# platform "top" note in spawn_wall for why the field exists at all: the patrol
	# guard is dropped in from it, and a `top` that under-declares its stone puts
	# the guard inside that stone.
	if log_bridge:
		var half_along := beam_w * 0.5 - 0.4
		var half_across := depth * 0.5 - 0.3
		var deck_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
		if half_along > 1.0 and half_across > 0.2:
			platforms.append({ "center": Vector3(beam_x, beam_top, beam_z), "half": deck_half, "top": beam_top })

func spawn_corridor(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a corridor: two parallel two-block-high sides with a gap between them
	that the player can sprint down. THE LANE IS THE POINT — it is the one feature
	structure with movement value, so every territory's re-dress keeps a clear
	run-through, and only the SIDES change:

	  * solid walls (plains ruin lane, mountain fort passage), or
	  * COLUMN PAIRS with `lane_spaced` (a desert temple colonnade, a forest
	    corridor of standing dead trunks), some of them still bridged overhead by
	    a portico beam.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  corridor's midpoint
	@param theme: This territory's STRUCTURE_THEMES row
	@param obstacles: Footprint list each block is appended to
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var block_size := rng.randf_range(1.8, 2.4)
	var step := block_size * 0.98
	var length := rng.randi_range(wall_min_length + 1, wall_max_length + 1)
	# Width of the walkable gap between the two sides.
	var gap := rng.randf_range(2.5, 4.0)

	var along_x := rng.randf() < 0.5
	var limit := half_chunk - 2.0

	# Trim the corridor if it's longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Bail if the chunk can't fit the corridor's width.
	if limit - gap * 0.5 <= -limit + gap * 0.5:
		return
	var start := rng.randf_range(-limit, limit - span)
	# Centreline of the corridor on the perpendicular axis.
	var center_perp := rng.randf_range(-limit + gap * 0.5, limit - gap * 0.5)

	# No corridors in the water. The corridor's centre is the midpoint of its run
	# along one axis and the centreline on the other (centre test, taken right
	# after the draws that fixed both).
	var mid_along := start + span * 0.5
	var corridor_center: Vector3 = Vector3(mid_along, 0.0, center_perp) if along_x else Vector3(center_perp, 0.0, mid_along)
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if is_river_at(chunk_center + corridor_center) \
			or tower_excludes(chunk_center.x + corridor_center.x, chunk_center.z + corridor_center.z, half_chunk):
		return

	var spaced: bool = theme["lane_spaced"]
	var gap_chance: float = theme["gap_chance"]
	var lintel_chance: float = theme["lintel_chance"]
	var trim: Color = theme["trim"]

	for i in length:
		# A colonnade stands on every OTHER slot — that is what turns the same
		# loop into columns instead of a wall, at the cost of no extra draw.
		if spaced and i % 2 == 1:
			continue

		var along := start + i * step
		# A ruin is missing pieces. Post-draw skip, exactly like the scatter
		# loop's river test: the draw has already happened, so nothing shifts.
		var fallen := rng.randf() < gap_chance

		for side_sign in 2:
			var side := -1.0 if side_sign == 0 else 1.0
			var perp := center_perp + side * gap * 0.5
			var x := along if along_x else perp
			var z := perp if along_x else along

			if fallen:
				# Rubble where the section came down: visual-only, and no
				# footprint, because nothing solid stands here any more.
				var rs := block_size * rng.randf_range(0.28, 0.42)
				create_box(
					Vector3(x, rs * 0.4, z), Vector3(rs, rs * 0.75, rs * 1.15),
					rng.randf_range(0.0, TAU), rng, block_batch, block_body,
					rng.randf_range(-0.45, 0.45), trim, false
				)
				continue

			# Two blocks tall so it reads as an enclosed passage. Sheer and taller
			# than a jump, so it's not climbable (no coins perch on the roof).
			create_box(
				Vector3(x, block_size * 0.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
			)
			create_box(
				Vector3(x, block_size * 1.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
			)
			obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": 2.0 * block_size, "climbable": false })

		# A portico beam bridging the pair, well above head height so the sprint
		# lane is untouched. NO FOOTPRINT: footprints model ground occupancy and
		# there is nothing on the ground under a beam — a crocodile walks under it
		# and a road coin may sit beneath it, both correctly.
		if spaced and not fallen and lintel_chance > 0.0 and rng.randf() < lintel_chance:
			var beam_span := gap + block_size
			var beam_dims: Vector3 = Vector3(block_size * 0.8, block_size * 0.55, beam_span) if along_x else Vector3(beam_span, block_size * 0.55, block_size * 0.8)
			var bx := along if along_x else center_perp
			var bz := center_perp if along_x else along
			create_box(
				Vector3(bx, 2.0 * block_size + block_size * 0.275, bz), beam_dims, 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
			)

func spawn_wall(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a single barrier wall — a line of touching blocks the player must run
	around — somewhere inside the chunk, dressed in this territory's stone: a
	broken-backed plains ruin, a low desert temple wall, an overgrown forest wall,
	a solid battlemented mountain fort wall.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  wall's midpoint
	@param theme: This territory's STRUCTURE_THEMES row
	@param obstacles: Footprint list to append each wall block to (for crocodiles)
	@param platforms: Gets the wall ridge registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)

	THE RIDGE PLATFORM IS THE LONGEST UNBROKEN RUN, not the whole span, and that
	is the one behavioural change a ruined wall forced. A doubled hump is fine to
	pace over (the shipped comment's point — the guard's feelers turn it back), but
	a MISSING segment is a hole, and a crocodile confined to a ridge box spanning
	one would walk into thin air. So the run is broken by gaps only; a territory
	with gap_chance 0 registers exactly the ridge it always did.
	"""
	# Uniform block size so the wall reads as one solid line.
	var block_size := rng.randf_range(1.6, 2.4)
	# Step slightly less than the block size so neighbours overlap — no gaps.
	var step := block_size * 0.98
	var length := rng.randi_range(wall_min_length, wall_max_length)

	# Run the wall along X or along Z.
	var along_x := rng.randf() < 0.5
	var margin := 2.0
	var limit := half_chunk - margin

	# Distance from the first block centre to the last. Trim the wall if it would
	# be longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Pick where the wall starts along its axis, and its fixed perpendicular coord.
	var start := rng.randf_range(-limit, limit - span)
	var fixed := rng.randf_range(-limit, limit)

	# Midpoint of the wall's run — used for the river test here; the patrol ridge
	# at the bottom of this function is measured off its own surviving run.
	var mid_along := start + (length - 1) * step * 0.5

	# No walls in the water (centre test, taken right after the draws that placed
	# the wall).
	var wall_center: Vector3 = Vector3(mid_along, 0.0, fixed) if along_x else Vector3(fixed, 0.0, mid_along)
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if is_river_at(chunk_center + wall_center) \
			or tower_excludes(chunk_center.x + wall_center.x, chunk_center.z + wall_center.z, half_chunk):
		return

	var gap_chance: float = theme["gap_chance"]
	var double_chance: float = theme["double_chance"]
	var cap: Color = theme["cap"]
	var trim: Color = theme["trim"]

	# Longest unbroken run of standing segments — see the docstring.
	var run_start := 0
	var run_len := 0
	var best_start := 0
	var best_len := 0

	# Each section's own top, so the patrol platform below can take the MAXIMUM over
	# the surviving run it actually registers rather than over the whole wall. A
	# fallen section keeps its 0.0 and is never inside a run by construction. See
	# the platform "top" note at the bottom of this function for why the maximum
	# (and not the walkable height) is what the patrol spawner needs.
	var section_top := PackedFloat32Array()
	section_top.resize(length)

	for i in length:
		var along := start + i * step
		var x := along if along_x else fixed
		var z := fixed if along_x else along

		# This section fell. Post-draw skip: the randf() above has already
		# advanced the stream, so removing the block inserts no draw anywhere.
		if rng.randf() < gap_chance:
			if run_len > best_len:
				best_len = run_len
				best_start = run_start
			run_len = 0
			# Its stones, scattered where they landed. Visual-only trim, and no
			# footprint — nothing solid stands here now.
			var rs := block_size * rng.randf_range(0.26, 0.4)
			create_box(
				Vector3(x, rs * 0.4, z), Vector3(rs, rs * 0.75, rs * 1.15),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body,
				rng.randf_range(-0.45, 0.45), trim, false
			)
			continue

		if run_len == 0:
			run_start = i
		run_len += 1

		# Wall blocks are axis-aligned (yaw 0) so they sit flush against each other.
		create_box(
			Vector3(x, block_size * 0.5, z), Vector3(block_size, block_size, block_size), 0.0,
			rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
		)
		var top := block_size
		# A single-block section is low enough to hop onto; a doubled one is not.
		var climbable := true

		# Now and then double a section up so the wall isn't a uniform single row.
		if rng.randf() < double_chance:
			create_box(
				Vector3(x, block_size * 1.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(theme, rng)
			)
			top = 2.0 * block_size
			climbable = false
			# A capstone crowns the HUMP only, never the ridge — the ridge is the
			# surface a patrol paces and a player stands on. collide = false makes
			# it inert either way; keeping it off the ridge keeps the rule simple.
			if cap.a > 0.0:
				create_box(
					Vector3(x, top + 0.07, z), Vector3(block_size * 1.05, 0.14, block_size * 1.05), 0.0,
					rng, block_batch, block_body, 0.0, cap, false
				)

		section_top[i] = top
		# `guarded` marks stone that a patrol crocodile is going to be dropped onto,
		# and it exists for exactly one reader: _spawn_mountain_content's avoid-list.
		# A massif must clear it whatever its radius or height — see the note there.
		obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": top, "climbable": climbable, "guarded": true })

	if run_len > best_len:
		best_len = run_len
		best_start = run_start

	# Register the surviving ridge as a thin patrol platform (a crocodile can pace
	# it end to end). Surface is the single-block height; doubled humps just become
	# obstacles its feelers turn it back at.
	#
	# WHY THE DICT CARRIES BOTH `center.y` AND `top`, and why they differ here:
	# `center.y` is the SURFACE the guard paces — the single-block height, and the
	# height set_confinement is handed (which reads only .x/.z, so nothing else
	# consumes it). `top` is the TALLEST SOLID STONE standing anywhere inside the
	# platform's footprint, which for a wall is the doubled humps.
	# spawn_platform_crocodiles drops its guard in from `top`, not from `center.y`,
	# and that distinction is the whole bug this pair exists to close: a share of a
	# wall's sections are doubled, occupying y in [block_size, 2 * block_size], and
	# the spawner picks a point at a RANDOM ANGLE along the ridge with no idea
	# which sections those are. Dropping in at `center.y + PLATFORM_SPAWN_HEIGHT`
	# therefore put the guard INSIDE a hump whenever the angle landed on one —
	# penetrating by up to the full drop-in offset. Measured over a 17x17 chunk
	# field on four run seeds: 3-7 patrol crocodiles per field stood in solid
	# stone, i.e. 12-18% of every platform guard the world spawned, and EVERY
	# crocodile-in-stone in the whole field was one of them (the ground and boss
	# spawners, which do test `obstacles`, were clean at 0). Dropping in from the
	# maximum instead lands the guard on the ridge or on a hump's top face and
	# gravity settles it either way.
	#
	# The maximum is taken over the SURVIVING RUN this platform actually covers,
	# not over the whole wall: a hump in a section that fell, or in a stretch on
	# the far side of a gap, is not inside this footprint and would only lift the
	# drop-in for nothing. The hump capstones are collide = false, so they are
	# correctly not part of it.
	if best_len > 0:
		var ridge_along := start + (best_start + (best_len - 1) * 0.5) * step
		var ridge_center: Vector3 = Vector3(ridge_along, block_size, fixed) if along_x else Vector3(fixed, block_size, ridge_along)
		var half_along := (best_len - 1) * step * 0.5 + block_size * 0.5 - 0.4
		var half_across := block_size * 0.5 - 0.3
		var ridge_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
		var ridge_top := block_size
		for i in range(best_start, best_start + best_len):
			ridge_top = maxf(ridge_top, section_top[i])
		if half_along > 1.0 and half_across > 0.2:
			platforms.append({ "center": ridge_center, "half": ridge_half, "top": ridge_top })

# ============================================================================
# THEMED SCATTERED PROPS
# ============================================================================
# Everything below runs on a PRIVATE RandomNumberGenerator seeded from the one
# randi() the scatter loop drew for it. NONE of these functions takes the chunk
# RNG, which is what makes the fixed-shared-stream-cost rule structural instead
# of a discipline somebody has to remember. Draw as many or as few numbers as a
# variant needs.
#
# THREE RULES EVERY BUILDER OBEYS, because breaking any of them fails silently:
#
#  1. EVERY BOX STAYS INSIDE `size * PROP_RADIUS_FACTOR` OF THE PROP CENTRE.
#     That radius is the number returned, and it is what _settle_coin_y perches
#     road coins against, what spawn_crocodiles_in_chunk keeps crocodiles out of,
#     and what the massif avoid-list reads. A box poking outside it means a
#     crocodile spawned inside stone or a coin buried in it, with no error
#     anywhere. The bound used when sizing an offset decoration is half its own
#     3D DIAGONAL (`0.5 * dims.length()`), because a box carrying both a yaw and
#     a tilt can present a corner in any direction. prop_selfcheck.gd measures the
#     real emitted corners rather than trusting these comments.
#
#  2. A CLIMBABLE PROP IS ACTUALLY CLIMBABLE. The box whose top face is the
#     returned `top` is UNTILTED (a tilted box has no flat top to stand on) and
#     centred on the prop, and the untilted collidable tops form a ladder from
#     the ground up with no gap over PROP_MAX_STEP. Tilted decoration is welcome
#     — it is what stops a prop reading as a box — but it goes BESIDE the prop,
#     never on the surface the contract promises. This is the "rest spot from
#     crocodiles" role the bare cubes carried.
#
#  3. 3-8 BOXES, OF WHICH 1-3 COLLIDE. The whole chunk draws in one MultiMesh
#     whatever the box count, so instances are nearly free — but each colliding
#     box is a real CollisionShape3D node on the chunk's shared body, and that is
#     the budget the per-chunk node count lives on. Trim (chips, rubble, root
#     flares, ribs, loose stones) passes `collide = false`, exactly as a forest
#     canopy does.

func _build_prop(local: Vector3, size: float, prop_seed: int, chunk_center: Vector3, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Build ONE themed scattered prop at a spot the scatter loop already accepted.

	@param local: The prop's chunk-LOCAL position, y = 0 (it sits on the ground).
	@param size: The prop's overall scale — the same object_size_min..max draw the
	             bare cube used, so props inherit the field's existing size spread.
	@param prop_seed: The one randi() the chunk stream paid for this prop. Every
	                  choice below hangs off it, so the prop is a pure function of
	                  chunk coords + run_seed like everything else in generation.
	@param chunk_center: World centre of the chunk — the prop's own WORLD position
	                     is what picks the theme (see below).
	@param block_batch / block_body: The chunk's single MultiMesh batch and single
	                     collision body. A prop adds ZERO draw calls and at most
	                     three collision shapes.
	@return { "radius": float, "top": float, "climbable": bool } — the footprint
	        the caller appends to `obstacles`, in exactly the shape the bare cube
	        used to append.

	THE THEME IS PICKED PER POSITION, NOT PER CHUNK CENTRE. That is deliberate and
	it is the same rule the biome content builders follow: a chunk straddling a
	forest edge grows stumps on the wooded half and boulders on the open half, so
	the transition follows the noise contour instead of stopping dead on a straight
	chunk seam. One extra noise evaluation per prop (~12 a chunk) buys it.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = prop_seed

	match biome_at(chunk_center.x + local.x, chunk_center.z + local.z):
		Biome.DESERT:
			match rng.randi_range(0, 2):
				0:
					return _prop_sandstone_stack(local, size, rng, block_batch, block_body)
				1:
					return _prop_broken_column(local, size, rng, block_batch, block_body)
				_:
					return _prop_bone_pile(local, size, rng, block_batch, block_body)
		Biome.FOREST:
			match rng.randi_range(0, 2):
				0:
					return _prop_mossy_boulder(local, size, rng, block_batch, block_body)
				1:
					return _prop_tree_stump(local, size, rng, block_batch, block_body)
				_:
					return _prop_log_pile(local, size, rng, block_batch, block_body)
		Biome.MOUNTAIN:
			match rng.randi_range(0, 1):
				0:
					return _prop_scree_cluster(local, size, rng, block_batch, block_body)
				_:
					return _prop_cairn(local, size, rng, block_batch, block_body)
		Biome.CITY:
			match rng.randi_range(0, 2):
				0:
					return _prop_crate_stack(local, size, rng, block_batch, block_body)
				1:
					return _prop_garden_wall(local, size, rng, block_batch, block_body)
				_:
					return _prop_paving_stack(local, size, rng, block_batch, block_body)
		Biome.SNOW:
			match rng.randi_range(0, 2):
				0:
					return _prop_ice_rock(local, size, rng, block_batch, block_body)
				1:
					return _prop_snow_drift(local, size, rng, block_batch, block_body)
				_:
					return _prop_frozen_stump(local, size, rng, block_batch, block_body)
		_:  # PLAINS — also the fallback, so a future biome band still gets props.
			match rng.randi_range(0, 2):
				0:
					return _prop_boulder_cluster(local, size, rng, block_batch, block_body)
				1:
					return _prop_ruin_fragment(local, size, rng, block_batch, block_body)
				_:
					return _prop_bale_pile(local, size, rng, block_batch, block_body)

# ----- PLAINS ---------------------------------------------------------------

func _prop_boulder_cluster(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — a field boulder with two smaller rocks nestled against it.

	The big rock is the climbable one, so it stays UNTILTED and its top face is
	the returned `top`. The companions carry the tilt that stops the whole thing
	reading as a cube, and they sit beside it rather than on it (rule 2 above).
	3 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var w := size * 0.9
	var h := minf(size * 0.85, PROP_MAX_STEP)
	var yaw := rng.randf_range(0.0, TAU)

	create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.92), yaw,
		rng, block_batch, block_body, 0.0, PROP_BOULDER_A.lerp(PROP_BOULDER_B, rng.randf())
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.28, 0.42)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * 0.32
		create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.9, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.35, 0.35),
			PROP_BOULDER_A.lerp(PROP_BOULDER_B, rng.randf())
		)

	return { "radius": r, "top": h, "climbable": true }

func _prop_ruin_fragment(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — a stub of broken wall with one block fallen off it and rubble around.

	The wall stub is the climbable perch (untilted, flat top). 4 boxes, 2 collide
	— the chips are trim and would only make the base a snag to walk into.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	# The tallest prop step in the set, and deliberately capped at the bare cube's
	# own proven 2.5 m rather than at PROP_MAX_STEP: a stub that needed the very
	# last centimetre of the jump arc would be a rest spot only in theory.
	var h := minf(size * 1.05, 2.5)

	create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(size * 0.85, h, size * 0.42), yaw,
		rng, block_batch, block_body, 0.0, PROP_RUIN_STONE
	)

	# The fallen block, tilted where it came to rest, thrown clear of the wall face.
	var bs := size * rng.randf_range(0.30, 0.42)
	var ba := yaw + PI * 0.5 + rng.randf_range(-0.5, 0.5)
	create_box(
		local + Vector3(cos(ba) * size * 0.32, bs * 0.42, sin(ba) * size * 0.32),
		Vector3(bs, bs * 0.85, bs * 1.1), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(0.2, 0.5), PROP_RUIN_STONE
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.12, 0.22)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.45)
		create_box(
			local + Vector3(cos(a) * ring, cs * 0.4, sin(a) * ring),
			Vector3(cs, cs * 0.7, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4), PROP_RUIN_STONE, false
		)

	return { "radius": r, "top": h, "climbable": true }

func _prop_bale_pile(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — two stacked hay bales with a cart crate against them and loose planks.

	The two-bale stack IS the old cube tower, re-skinned: both tiers are untilted
	and each is one easy step, so the climb the towers provided survives intact.
	5 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)

	var h1 := minf(size * 0.66, PROP_MAX_STEP)
	var w1 := size * 0.82
	create_box(
		local + Vector3(0.0, h1 * 0.5, 0.0), Vector3(w1, h1, w1 * 0.9), yaw,
		rng, block_batch, block_body, 0.0, PROP_HAY
	)

	var h2 := minf(h1 * 0.8, PROP_MAX_STEP)
	var w2 := w1 * 0.78
	create_box(
		local + Vector3(0.0, h1 + h2 * 0.5, 0.0), Vector3(w2, h2, w2 * 0.9),
		yaw + rng.randf_range(-0.4, 0.4), rng, block_batch, block_body, 0.0, PROP_HAY
	)

	var cs := size * rng.randf_range(0.22, 0.34)
	var ca := rng.randf_range(0.0, TAU)
	create_box(
		local + Vector3(cos(ca) * size * 0.38, cs * 0.5, sin(ca) * size * 0.38),
		Vector3(cs, cs, cs), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(-0.25, 0.25), PROP_CRATE
	)

	for _i in 2:
		var pl := size * rng.randf_range(0.30, 0.45)
		var pa := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.25, 0.40)
		create_box(
			local + Vector3(cos(pa) * ring, size * 0.05, sin(pa) * ring),
			Vector3(pl, size * 0.08, size * 0.16), pa + rng.randf_range(-0.5, 0.5),
			rng, block_batch, block_body, rng.randf_range(-0.15, 0.15), PROP_CRATE, false
		)

	return { "radius": r, "top": h1 + h2, "climbable": true }

# ----- DESERT ---------------------------------------------------------------

func _prop_sandstone_stack(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — 2-3 wind-worn sandstone slabs stacked and shrinking, with one broken
	flake leaning at the base.

	The slabs are untilted so the stack climbs; the flake is the tilted character
	and sits BESIDE the stack, never on the top slab. 3-4 boxes, 2-3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var tiers := rng.randi_range(2, 3)
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.88
	var top := 0.0

	for _i in tiers:
		var th := minf(size * rng.randf_range(0.42, 0.68), PROP_MAX_STEP)
		create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.82),
			yaw + rng.randf_range(-0.3, 0.3), rng, block_batch, block_body, 0.0,
			PROP_SANDSTONE_A.lerp(PROP_SANDSTONE_B, rng.randf() * 0.7)
		)
		top += th
		w *= 0.82

	var fs := size * rng.randf_range(0.30, 0.45)
	var fa := rng.randf_range(0.0, TAU)
	create_box(
		local + Vector3(cos(fa) * size * 0.32, fs * 0.5, sin(fa) * size * 0.32),
		Vector3(fs, fs * 1.2, fs * 0.25), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(0.5, 0.9), PROP_SANDSTONE_B, false
	)

	return { "radius": r, "top": top, "climbable": true }

func _prop_broken_column(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — a half-buried column: one surviving drum still standing on its broken
	flat top, the toppled shaft lying beside it, chips around the base.
	4 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var dw := size * 0.62
	var dh := minf(size * rng.randf_range(0.7, 1.0), PROP_MAX_STEP)

	create_box(
		local + Vector3(0.0, dh * 0.5, 0.0), Vector3(dw, dh, dw), yaw,
		rng, block_batch, block_body, 0.0, PROP_SANDSTONE_A
	)

	# The fallen shaft, offset PERPENDICULAR to its own long axis so its length
	# stays inside the radius (offsetting along the axis would push a corner out).
	var sa := rng.randf_range(0.0, TAU)
	var sl := size * rng.randf_range(0.55, 0.75)
	var perp := Vector3(cos(sa + PI * 0.5), 0.0, sin(sa + PI * 0.5)) * size * 0.26
	create_box(
		local + perp + Vector3(0.0, dw * 0.28, 0.0),
		Vector3(sl, dw * 0.56, dw * 0.56), sa,
		rng, block_batch, block_body, rng.randf_range(-0.15, 0.15),
		PROP_SANDSTONE_A.lerp(PROP_SANDSTONE_B, 0.5)
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.12, 0.20)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.8, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5), PROP_SANDSTONE_B, false
		)

	return { "radius": r, "top": dh, "climbable": true }

func _prop_bone_pile(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — a bleached ribcage scattered in the sand. THE ONE NON-CLIMBABLE
	VARIANT: a heap of tilted ribs has no flat top to stand on, so it honestly
	records climbable = false and _settle_coin_y SKIPS a road coin over it rather
	than floating one on a surface that is not there (the tree-canopy rule).

	Keeping it to one variant of eleven is deliberate — the bare cubes' rest-spot
	role is the thing this whole re-skin must not quietly delete, so desert still
	offers two climbable props in three and every other biome offers three.
	5-7 boxes, 1 collides (the skull lump, so the heap is not walk-through).
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var ss := size * rng.randf_range(0.30, 0.42)

	create_box(
		local + Vector3(0.0, ss * 0.45, 0.0), Vector3(ss, ss * 0.85, ss * 1.15), yaw,
		rng, block_batch, block_body, rng.randf_range(-0.2, 0.2), PROP_BONE
	)

	for _i in rng.randi_range(4, 6):
		var rib := size * rng.randf_range(0.35, 0.60)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.0, 0.22)
		create_box(
			local + Vector3(cos(a) * ring, size * rng.randf_range(0.05, 0.18), sin(a) * ring),
			Vector3(rib, size * 0.07, size * 0.09), a + rng.randf_range(-0.6, 0.6),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5), PROP_BONE, false
		)

	return { "radius": r, "top": ss * 0.9, "climbable": false }

# ----- FOREST ---------------------------------------------------------------

func _prop_mossy_boulder(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — a damp boulder wearing a cap of moss, with two small rocks at its foot.

	The moss cap COLLIDES and its top face is the returned `top`, so you stand on
	the moss rather than clipping into it — and the rock height is derived from
	PROP_MAX_STEP minus the cap, so cap + rock together still clear in one jump
	however object_size_max is retuned. 4 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var cap_h := size * 0.14
	var bh := minf(size * 0.72, PROP_MAX_STEP - cap_h)
	var bw := size * 0.88

	create_box(
		local + Vector3(0.0, bh * 0.5, 0.0), Vector3(bw, bh, bw * 0.9), yaw,
		rng, block_batch, block_body, 0.0, PROP_MOSS_ROCK
	)
	create_box(
		local + Vector3(0.0, bh + cap_h * 0.5, 0.0), Vector3(bw * 0.96, cap_h, bw * 0.87), yaw,
		rng, block_batch, block_body, 0.0, PROP_MOSS_CAP
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.22, 0.34)
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.34, cs * 0.4, sin(a) * size * 0.34),
			Vector3(cs, cs * 0.75, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.45, 0.45), PROP_MOSS_ROCK, false
		)

	return { "radius": r, "top": bh + cap_h, "climbable": true }

func _prop_tree_stump(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — a wide cut stump with three root flares splaying out at ground level.

	The roots are VISUAL ONLY: they spread past the stump's own width, and making
	them solid would turn every stump into a ring of ankle-height snags. The flat
	saw-cut top is the perch. 4 boxes, 1 collides.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var sw := size * 0.86
	var sh := minf(size * rng.randf_range(0.55, 0.80), PROP_MAX_STEP)

	create_box(
		local + Vector3(0.0, sh * 0.5, 0.0), Vector3(sw, sh, sw * 0.94), yaw,
		rng, block_batch, block_body, 0.0, PROP_STUMP
	)

	for i in 3:
		var a := yaw + TAU * float(i) / 3.0 + rng.randf_range(-0.35, 0.35)
		var rl := size * rng.randf_range(0.36, 0.50)
		create_box(
			local + Vector3(cos(a) * size * 0.36, size * 0.09, sin(a) * size * 0.36),
			Vector3(rl, size * 0.18, size * 0.22), a,
			rng, block_batch, block_body, rng.randf_range(-0.25, -0.05), PROP_STUMP, false
		)

	return { "radius": r, "top": sh, "climbable": true }

func _prop_log_pile(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — two felled logs side by side with a third laid across them, plus a
	couple of loose branches.

	The upper log's top face is flat and one short step up, so the pile stays a
	rest spot. 5 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var a := rng.randf_range(0.0, TAU)
	var log_len := size * 0.9
	var log_d := size * 0.30
	var perp := Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5)) * log_d * 0.55

	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		create_box(
			local + perp * s + Vector3(0.0, log_d * 0.5, 0.0),
			Vector3(log_len, log_d, log_d), a,
			rng, block_batch, block_body, 0.0, PROP_LOG
		)

	create_box(
		local + Vector3(0.0, log_d * 1.5, 0.0),
		Vector3(log_len * 0.85, log_d, log_d), a + rng.randf_range(-0.5, 0.5),
		rng, block_batch, block_body, 0.0, PROP_LOG
	)

	for _i in 2:
		var bl := size * rng.randf_range(0.25, 0.40)
		var ba := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		create_box(
			local + Vector3(cos(ba) * ring, size * 0.05, sin(ba) * ring),
			Vector3(bl, size * 0.10, size * 0.12), ba + rng.randf_range(-0.6, 0.6),
			rng, block_batch, block_body, rng.randf_range(-0.3, 0.3), PROP_LOG, false
		)

	return { "radius": r, "top": log_d * 2.0, "climbable": true }

# ----- MOUNTAIN -------------------------------------------------------------

func _prop_scree_cluster(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	MOUNTAIN — one flat slab of fallen rock with 3-4 shattered chips tumbled round
	it. The slab is the perch; the chips carry the tilt. 4-5 boxes, 1 collides.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var sw := size * 0.84
	var sh := minf(size * rng.randf_range(0.45, 0.70), PROP_MAX_STEP)

	create_box(
		local + Vector3(0.0, sh * 0.5, 0.0), Vector3(sw, sh, sw * 0.88), yaw,
		rng, block_batch, block_body, 0.0, PROP_SCREE_A.lerp(PROP_SCREE_B, rng.randf())
	)

	for _i in rng.randi_range(3, 4):
		var cs := size * rng.randf_range(0.16, 0.30)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.8, cs * 1.2), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.6, 0.6),
			PROP_SCREE_A.lerp(PROP_SCREE_B, rng.randf()), false
		)

	return { "radius": r, "top": sh, "climbable": true }

func _prop_cairn(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	MOUNTAIN — a three-slab cairn with two loose stones at its foot. THIS IS THE
	OLD CUBE TOWER, re-skinned: the tallest prop in the set, all three tiers
	untilted and each one a short step, so the tower's climb survives its cube.

	NO CAPSTONE ON TOP, deliberately — a tilted stone crowning the cairn would
	look right and quietly destroy the flat surface the climbability contract
	promises. The loose stones go beside it instead. 5 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.72
	var top := 0.0

	for _i in 3:
		var th := minf(size * rng.randf_range(0.38, 0.58), PROP_MAX_STEP)
		create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.9),
			yaw + rng.randf_range(-0.5, 0.5), rng, block_batch, block_body, 0.0,
			PROP_CAIRN.lerp(PROP_SCREE_B, rng.randf() * 0.5)
		)
		top += th
		w *= 0.8

	for _i in 2:
		var cs := size * rng.randf_range(0.18, 0.28)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.32, 0.44)
		create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.85, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
			PROP_CAIRN.lerp(PROP_SCREE_B, rng.randf() * 0.5), false
		)

	return { "radius": r, "top": top, "climbable": true }

# ----- CITY -----------------------------------------------------------------
#
# Street clutter, at the same scale the bare cubes were: crates against a wall, a
# low garden wall with its planter, a pallet of paving slabs from the roadworks.
# All three keep the climbability contract (the box whose top face is the returned
# `top` is untilted, colliding and centred on the prop), and all three reuse the
# existing PROP_CRATE / PROP_RUIN_STONE timber and stone rather than adding a
# colour — the CITY_* palette is spent on the buildings, which is where a person
# actually reads "city".

func _prop_crate_stack(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — two market crates stacked against each other with a third tipped over
	beside them. The stack is the perch: both crates untilted, colliding and
	centred, each one a short step. The tipped crate carries the tilt and is trim.
	3 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.62
	var top := 0.0

	for i in 2:
		var th := minf(size * rng.randf_range(0.42, 0.60), PROP_MAX_STEP)
		create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.95),
			yaw + rng.randf_range(-0.25, 0.25), rng, block_batch, block_body, 0.0,
			PROP_CRATE.lerp(CITY_PLASTER_B, rng.randf() * 0.35)
		)
		top += th
		w *= 0.88

	# The tipped crate. Its offset is bounded by half its own 3D diagonal
	# (cs * 0.866 for a near-cube), because a box carrying a yaw AND a tilt can
	# present a corner in any direction: 0.30 + 0.32 * 0.866 = 0.577 of size,
	# inside PROP_RADIUS_FACTOR 0.71.
	var cs := size * rng.randf_range(0.24, 0.32)
	var a := rng.randf_range(0.0, TAU)
	create_box(
		local + Vector3(cos(a) * size * 0.30, cs * 0.45, sin(a) * size * 0.30),
		Vector3(cs, cs * 0.9, cs), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
		PROP_CRATE.lerp(CITY_PLASTER_B, rng.randf() * 0.35), false
	)

	return { "radius": r, "top": top, "climbable": true }

func _prop_garden_wall(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — a stub of low garden wall with a planter box set against it and a
	couple of pots tipped at its foot.

	The wall is the perch and is CENTRED on the prop, which is the part that
	matters: prop_selfcheck's climb ladder only counts untilted colliding boxes
	whose footprint covers the prop's centre, so a pair of offset wall segments
	with nothing in the middle would be a prop that records climbable = true and
	has nothing to stand on. 4 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var h := minf(size * rng.randf_range(0.55, 0.80), PROP_MAX_STEP)
	var wall_len := size * 1.02
	var wall_d := size * 0.28

	create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(wall_len, h, wall_d), yaw,
		rng, block_batch, block_body, 0.0,
		PROP_RUIN_STONE.lerp(CITY_PLASTER_B, rng.randf())
	)

	# Planter, set against the wall's face. Reach = 0.40 + 0.5*hypot(0.34, 0.34)
	# = 0.64 of size, inside the declared 0.71.
	var pw := size * 0.34
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var normal := Vector3(cos(yaw + PI * 0.5), 0.0, sin(yaw + PI * 0.5))
	create_box(
		local + normal * (size * 0.40 * side) + Vector3(0.0, pw * 0.5, 0.0),
		Vector3(pw, pw, pw), yaw, rng, block_batch, block_body, 0.0, PROP_CRATE
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.13, 0.18)
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.42, cs * 0.45, sin(a) * size * 0.42),
			Vector3(cs, cs * 1.1, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4),
			CITY_ROOF_TILE, false
		)

	return { "radius": r, "top": h, "climbable": true }

func _prop_paving_stack(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — a pallet of paving slabs from the roadworks, with a couple of loose
	slabs leaning against it. Flat, wide and low: the shortest climb in the set.
	4-5 boxes, 2-3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.72
	var top := 0.0

	for _i in rng.randi_range(2, 3):
		var th := minf(size * rng.randf_range(0.22, 0.34), PROP_MAX_STEP)
		create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.82),
			yaw + rng.randf_range(-0.12, 0.12), rng, block_batch, block_body, 0.0,
			PROP_RUIN_STONE.lerp(CITY_METAL, rng.randf() * 0.35)
		)
		top += th
		w *= 0.94

	# Loose slabs, leaning. Half their 3D diagonal is 0.5 * |(0.50, 0.09, 0.42)|
	# = 0.338 of size, so a 0.34 ring reaches 0.678 — inside the declared 0.71.
	for _i in 2:
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.34, size * 0.10, sin(a) * size * 0.34),
			Vector3(size * 0.50, size * 0.09, size * 0.42), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.7, 0.7),
			PROP_RUIN_STONE.lerp(CITY_METAL, rng.randf() * 0.35), false
		)

	return { "radius": r, "top": top, "climbable": true }

# ----- SNOW -----------------------------------------------------------------
#
# The tundra's small clutter, at the same scale the bare cubes were. All three are
# CLIMBABLE, and in this one territory that is a design statement rather than an
# incidental: snow is the most hostile band in the game (croc density is the
# ordinary distance-scaled figure — only the city thins it), so the ice you can
# stand on top of is the whole of the rest-from-crocodiles role out here. Every
# perch is therefore an untilted, colliding, centred box whose top face IS the
# returned `top`; the shards, scour lumps and broken branches carry the tilt and
# sit beside the prop, never on it.

func _prop_ice_rock(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — a flat-topped block of glacier ice with two or three shards split off it
	and leaning against its flanks. The block is the perch. 3-4 boxes, 1 collides.

	OPAQUE, never transparent: the blue-white ramp is what has to read as ice, and
	an alpha-blended box would cost fill rate on a mobile GPU AND drop out of the
	chunk's one MultiMesh (which has a single opaque material) for the privilege.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.86
	var h := minf(size * rng.randf_range(0.60, 0.95), PROP_MAX_STEP)

	create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.90), yaw,
		rng, block_batch, block_body, 0.0, SNOW_ICE_A.lerp(SNOW_ICE_B, rng.randf() * 0.7)
	)

	# The split shards. Half a shard's 3D diagonal is
	# 0.5 * |(0.16, 0.55, 0.20)| = 0.303 of size, so a 0.38 ring reaches 0.683 —
	# inside the declared 0.71, whatever yaw and tilt it ends up carrying.
	for _i in rng.randi_range(2, 3):
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.38, size * 0.24, sin(a) * size * 0.38),
			Vector3(size * 0.16, size * 0.55, size * 0.20), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.55, 0.55),
			SNOW_ICE_A.lerp(SNOW_ICE_B, rng.randf()), false
		)

	return { "radius": r, "top": h, "climbable": true }

func _prop_snow_drift(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — a wind-packed drift: two wide shallow tiers with a couple of scour lumps
	tumbled off the lee side. The lowest, widest prop in the whole set — a drift is
	a shape the wind made, so it spreads rather than stacks. 4-5 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	# Half-diagonal of the base tier is 0.5 * |(0.95, 0.85)| = 0.637 of size, so
	# even at full yaw the widest tier stays inside the declared 0.71.
	var w := size * 0.95
	var top := 0.0

	for _i in 2:
		var th := minf(size * rng.randf_range(0.20, 0.32), PROP_MAX_STEP)
		create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.89),
			yaw + rng.randf_range(-0.18, 0.18), rng, block_batch, block_body, 0.0,
			SNOW_PACK.lerp(SNOW_ICE_A, rng.randf() * 0.5)
		)
		top += th
		w *= 0.80

	# Scour lumps. Half a lump's 3D diagonal at its widest is
	# 0.5 * 0.22 * |(1, 0.7, 1.3)| = 0.196 of size; a 0.42 ring reaches 0.616.
	for _i in rng.randi_range(1, 2):
		var cs := size * rng.randf_range(0.14, 0.22)
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.42, cs * 0.42, sin(a) * size * 0.42),
			Vector3(cs, cs * 0.7, cs * 1.3), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.35, 0.35),
			SNOW_PACK.lerp(SNOW_ICE_A, rng.randf() * 0.5), false
		)

	return { "radius": r, "top": top, "climbable": true }

func _prop_frozen_stump(local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — the frost-split stump of a dead tree, with two or three broken branch
	stubs still jutting out of it and a cap of drifted snow on the break.

	The stump is the perch, so the snow cap is a THIN FILM over it (collide = false,
	the STRUCTURE_THEMES `cap` arrangement) rather than another tier: the surface
	the player stands on is the stump's own top face, which is the height returned.
	4-6 boxes, 1 collides.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.62
	# Capped at the bare cube's proven 2.5 m rather than at PROP_MAX_STEP (2.6), the
	# same call _prop_ruin_fragment makes and for the same reason: a perch that
	# needed the very last centimetre of the jump arc is a rest spot only on paper.
	var h := minf(size * rng.randf_range(0.70, 1.05), 2.5)

	create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.94), yaw,
		rng, block_batch, block_body, 0.0, SNOW_DEADWOOD
	)

	# Snow on the break: a film, not a step. 6 cm of it at size 1.
	create_box(
		local + Vector3(0.0, h + size * 0.03, 0.0), Vector3(w * 1.05, size * 0.06, w * 0.99),
		yaw, rng, block_batch, block_body, 0.0, SNOW_PACK, false
	)

	# Broken branch stubs. Half a stub's 3D diagonal is
	# 0.5 * |(0.10, 0.42, 0.10)| = 0.222 of size; a 0.24 ring reaches 0.462.
	for _i in rng.randi_range(2, 3):
		var a := rng.randf_range(0.0, TAU)
		create_box(
			local + Vector3(cos(a) * size * 0.24, h * rng.randf_range(0.45, 0.85), sin(a) * size * 0.24),
			Vector3(size * 0.10, size * 0.42, size * 0.10), a,
			rng, block_batch, block_body, rng.randf_range(0.7, 1.2), SNOW_DEADWOOD, false
		)

	return { "radius": r, "top": h, "climbable": true }

func create_block(center_pos: Vector3, size: float, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Create one cube block. Thin wrapper over create_box for the common case where
	all three dimensions are equal (scattered blocks, towers, walls, corridors).

	@param block_batch: Out-param forwarded to create_box for MultiMesh batching.
	@param block_body: The chunk's shared block-collision body, forwarded to
	                  create_box so this block's shape hangs on it (Task 5).
	"""
	create_box(center_pos, Vector3(size, size, size), yaw, rng, block_batch, block_body)

func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0), collide: bool = true) -> void:
	"""
	Register one box for rendering AND register its physics collision shape. Used for
	cube blocks and for the flat slabs that make up terraced mounds.

	VISUALS vs COLLISION are DECOUPLED (Tasks 4 + 5 of the perf plan):
	- VISUALS (Task 4): this function no longer instances a MeshInstance3D +
	  StandardMaterial3D per block. Instead it appends one
	  { "transform": Transform3D, "color": Color } entry to `block_batch`. The caller
	  (create_chunk) later turns the whole batch into ONE MultiMeshInstance3D, so all
	  of a chunk's blocks draw in a single draw call instead of dozens (see SECTION
	  2's MultiMesh notes and _build_block_multimesh below). The blocks look EXACTLY
	  the same — same shapes, sizes, yaw and earthy-colour ranges — only how they're
	  SUBMITTED to the GPU changed.
	- COLLISION (Task 5): this function no longer creates a per-block StaticBody3D.
	  Instead it adds just a CollisionShape3D (with a BoxShape3D) as a child of the
	  CHUNK'S SINGLE shared `block_body`, positioning/rotating that shape node where
	  the block is.

	  WHY ONE BODY WITH MANY SHAPES == MANY ONE-SHAPE BODIES (for static geometry):
	  a StaticBody3D's job is to give its CollisionShape3D children a physics presence
	  in the world; the body itself doesn't move (static). Godot's physics engine
	  collides against each individual SHAPE — at that shape's own world transform —
	  regardless of whether the shapes are spread across many bodies or grouped under
	  one. The OLD code put each block's shape at the block's transform via the BODY's
	  position/rotation (shape sat at the body's local origin). The NEW code puts that
	  same transform directly on the CollisionShape3D node instead (it's a Node3D, so
	  it has its own position/rotation), giving the shape the IDENTICAL world placement.
	  So the player still can't walk through a block, and a crocodile's avoidance
	  raycast still hits it, byte-for-byte as before — we've only changed how the
	  collision nodes are GROUPED, not where any collision surface is. The payoff is
	  ~25× fewer nodes for blocks (one body per chunk instead of one per block), a real
	  CPU/web win with zero behavioural change.

	  The MultiMesh (block_batch → MultiMeshInstance3D) and this collision body are the
	  TWO HALVES of each chunk's blocks: one renders them, one collides with them.

	@param center_pos: Box centre position, local to the chunk (Y is the centre,
	                   so pass height/2 to sit a box on the ground)
	@param dimensions: Full box size on each axis (width, height, depth)
	@param yaw: Y rotation in radians (0 to keep faces axis-aligned)
	@param rng: The chunk's seeded RNG, used for the random earthy colour
	@param block_batch: Out-param; we append this block's per-instance transform +
	                   colour here for the chunk's MultiMesh.
	@param block_body: The chunk's single shared StaticBody3D; we add this block's
	                   CollisionShape3D child to it (see WHY note above).
	@param tilt: OPTIONAL rotation about the local X axis (radians), applied AFTER
	             yaw. Used by the lost-civilization artifacts for leaning stones.
	             Defaults to 0.0 — the extra Basis is then the identity, so every
	             existing call site produces a bit-for-bit identical transform.
	@param color_override: OPTIONAL colour that replaces the curated-ramp pick when
	                       its alpha > 0 (the default is fully transparent = inert).
	                       Used by artifacts for their weathered palette.
	@param collide: OPTIONAL — when false the box is VISUAL ONLY: it still joins the
	                chunk's MultiMesh batch, but no CollisionShape3D is created for
	                it. Defaults to true, so every pre-existing call site behaves
	                exactly as before. WHY IT EXISTS: forest tree CANOPIES are pure
	                decoration — you walk under leaves, and they sit above head
	                height anyway — so a forest chunk pays collision shapes for its
	                TRUNKS only instead of 3-4x that for trunk + canopy layers. Like
	                `tilt` and `color_override` this changes NO RNG behaviour: the
	                colour and roughness draws above happen identically whatever
	                `collide` is, so the deterministic world layout is untouched.
	"""
	# ----- Pick the block colour from a curated ramp -----------------------------
	# IMPORTANT (determinism): the chunk's world layout is seeded from this same RNG.
	# If we changed how many random numbers we draw here, every later block/crocodile/
	# coin in the chunk would shift. The COLOURS changed (per-channel randoms → curated
	# ramps, see the RAMP_* consts up top), but the DRAWS did not: same randi_range(0,2)
	# selector, then per branch the SAME number of randf_range calls with the SAME
	# argument ranges as the old code. The FIRST draw in each branch becomes the ramp
	# position `t` (normalised to 0..1 via inverse_lerp of its own range); the extra
	# draws that used to feed the other channels are consumed and DISCARDED purely to
	# advance the RNG — exactly like the roughness discard below. Keeping the calls
	# textually parallel to the old ones makes the sequence preservation auditable.
	var chosen_color: Color
	var color_choice := rng.randi_range(0, 2)
	match color_choice:
		0:  # Warm sandstone → terracotta (was: brown rocks, 3 draws — still 3)
			var t := inverse_lerp(0.3, 0.5, rng.randf_range(0.3, 0.5))
			rng.randf_range(0.2, 0.4)  # discarded — RNG-sequence padding (see note above)
			rng.randf_range(0.1, 0.3)  # discarded — RNG-sequence padding
			chosen_color = RAMP_SANDSTONE_A.lerp(RAMP_SANDSTONE_B, t)
		1:  # Slate → blue-grey (was: gray stones, 1 draw — still 1)
			var t := inverse_lerp(0.3, 0.6, rng.randf_range(0.3, 0.6))
			chosen_color = RAMP_SLATE_A.lerp(RAMP_SLATE_B, t)
		2:  # Olive → moss (was: dark green, 3 draws — still 3)
			var t := inverse_lerp(0.1, 0.3, rng.randf_range(0.1, 0.3))
			rng.randf_range(0.3, 0.5)  # discarded — RNG-sequence padding
			rng.randf_range(0.1, 0.3)  # discarded — RNG-sequence padding
			chosen_color = RAMP_MOSS_A.lerp(RAMP_MOSS_B, t)

	# Still DRAW the roughness random value to keep the RNG sequence identical to the
	# old code (so the procedural world is unchanged). The value itself is discarded:
	# MultiMesh can't vary roughness per instance, so the shared material uses one
	# representative roughness (SHARED_BLOCK_ROUGHNESS). The visual difference between
	# a fixed 0.85 and the old 0.7–1.0 spread is negligible. We DON'T store the result —
	# the CALL must stay (it advances the RNG), but the value is unused, so calling
	# randf_range purely for its determinism side effect is enough.
	rng.randf_range(0.7, 1.0)

	# ----- Optional colour override (artifacts) ----------------------------------
	# Applied AFTER the ramp match on purpose: the ramp draws above belong to the
	# CALLER'S RNG stream and must always happen to keep that stream's sequence
	# intact. Ordinary chunk blocks pass the shared chunk RNG (where skipping draws
	# would shift the whole world); artifacts pass their own private RNG, so the
	# discarded draws cost nothing. Either way the shared-stream discipline of this
	# function stays untouched — we only swap which colour VALUE gets used.
	if color_override.a > 0.0:
		chosen_color = color_override

	# ----- Append this block to the chunk's MultiMesh batch (VISUALS) ------------
	# A MultiMesh instance is just a Transform3D applied to the shared UNIT cube.
	# We build the basis as: rotate around UP by `yaw`, THEN scale each LOCAL axis by
	# `dimensions` — so the 1×1×1 cube becomes a (w, h, d) box turned by yaw. The
	# transform origin is `center_pos`, which is LOCAL to the chunk (same convention
	# the old per-block MeshInstance3D.position used). Because the MultiMeshInstance3D
	# is parented to the chunk at local origin, these local transforms land the blocks
	# in exactly the same spots as before.
	#
	# WHY `scaled_local` (NOT `scaled`): the order of scale vs rotation matters.
	#   * `Basis.scaled(dimensions)` post-multiplies each ROW → it scales in the
	#     PARENT/global frame, composing as `S * R`.
	#   * `Basis.scaled_local(dimensions)` scales in the basis's OWN/local frame
	#     (after the rotation), composing as `R * S`.
	# The collision path below builds a BoxShape3D sized to `dimensions` on a
	# CollisionShape3D that is THEN rotated by `yaw` — i.e. local-space scale, `R * S`.
	# We match that here with `scaled_local` so the rendered box and its collision
	# shape share the EXACT same transform. For an axis-aligned cube or a yaw of 0 the
	# two orders are identical, so every block in the game today looks the same either
	# way; but for a FUTURE non-uniform block at a non-zero yaw, `S * R` would shear /
	# mis-scale the visual relative to the (unchanged) collision shape — a latent
	# desync. Using `scaled_local` keeps visual and collision in lockstep for all cases.
	#
	# COLOUR SPACE (must match the old look exactly): the OLD per-block code set
	# `StandardMaterial3D.albedo_color = chosen_color`, and Godot treats albedo_color as
	# sRGB — it converts sRGB→linear before lighting, which slightly DARKENS the value.
	# A MultiMesh per-instance colour, however, is fed straight into the shader as the
	# vertex colour: with `vertex_color_is_srgb = false` (the default, and the ONLY
	# value the web/Compatibility renderer honours) that sRGB→linear step is skipped, so
	# the raw colour would render brighter/washed-out — a visible regression on desktop
	# AND web. To reproduce the old albedo output renderer-agnostically, we convert the
	# colour to linear OURSELVES here (`srgb_to_linear()`) so the final linear albedo
	# equals srgb_to_linear(chosen_color), exactly as the old material produced. This is
	# a pure value transform on an already-computed Color — it consumes NO RNG, so the
	# deterministic world layout is unchanged.
	#
	# TILT (artifacts): the rotation is built ONCE as `Basis(UP, yaw) * Basis(RIGHT,
	# tilt)` — yaw first, then a lean about the local X axis — and that SAME `rot` is
	# used for both halves: the visual gets `rot.scaled_local(dimensions)` (still the
	# `R * S` order documented above) and the collision shape below gets plain `rot`
	# on its own transform. Sharing one basis is what keeps a TILTED box's visual and
	# collision in lockstep. With the default `tilt == 0.0` the extra Basis is the
	# identity, so this transform is bit-for-bit what the yaw-only code produced.
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	block_batch.append({
		"transform": Transform3D(rot.scaled_local(dimensions), center_pos),
		"color": chosen_color.srgb_to_linear(),
	})

	# ----- Register the collision shape on the CHUNK'S shared body (COLLISION) ----
	# Instead of giving this block its OWN StaticBody3D (the old, node-heavy way), we
	# create just a CollisionShape3D and hang it on the chunk's single `block_body`.
	# The shape node carries the block's transform itself: we set its local
	# position = center_pos and rotation.y = yaw — the SAME chunk-local convention the
	# visual MultiMesh instance uses, and the same transform the old per-block body
	# applied. Because block_body is parented to the chunk (and the chunk is placed in
	# the world), this shape lands at the IDENTICAL world position/orientation the old
	# per-block body produced, so collision is byte-for-byte unchanged.
	#
	# Default collision layer/mask (1/1) — block_body never sets them, exactly like the
	# old per-block bodies, so the player's collision and crocodile avoidance raycasts
	# keep hitting blocks the same way.
	# The shape reuses the SAME `rot` basis the visual used (see the TILT note
	# above) via a whole-transform assignment — for the default tilt of 0 this is
	# exactly the old `position = center_pos; rotation.y = yaw` pair, and for a
	# tilted artifact stone it keeps collision matched to the leaning visual.
	#
	# VISUAL-ONLY BOXES: `collide == false` returns here, having already appended
	# the visual instance and consumed the exact same RNG draws. Only the physics
	# node is skipped — see the @param note above for why canopies want this.
	if not collide:
		return

	var collision_shape := CollisionShape3D.new()
	collision_shape.transform = Transform3D(rot, center_pos)

	var box_shape := BoxShape3D.new()
	box_shape.size = dimensions
	collision_shape.shape = box_shape

	# Add to the shared per-chunk body. (block_body is parented to the chunk by
	# create_chunk once generation finishes, so all these shapes unload with the chunk.)
	block_body.add_child(collision_shape)

func _build_block_multimesh(parent_chunk: MeshInstance3D, block_batch: Array) -> void:
	"""
	Turn a chunk's whole batch of blocks into ONE MultiMeshInstance3D, so every block
	in the chunk renders in a single draw call (instead of one draw call per block).

	@param parent_chunk: The chunk mesh — we parent the MultiMeshInstance3D to it so it
	                    is freed automatically when the chunk unloads (same per-chunk
	                    parenting rule everything else follows).
	@param block_batch: The list of { "transform": Transform3D, "color": Color } entries
	                    create_box appended while building this chunk's blocks.

	EDUCATIONAL NOTE — how a MultiMesh renders many blocks in one draw call:
	- A MultiMesh holds ONE `mesh` (here the shared unit cube) plus a flat buffer of
	  per-instance data. We tell it the data layout up front:
	    * `transform_format = TRANSFORM_3D` — each instance carries a full 3D transform
	      (its basis encodes per-axis scale + yaw; its origin is the block centre).
	    * `use_colors = true` — each instance ALSO carries a Color. Paired with the
	      shared material's `vertex_color_use_as_albedo`, that colour becomes the
	      block's albedo, so every block keeps its own earthy shade from one material.
	- `instance_count` must be set BEFORE writing instances; it allocates the buffer.
	- The GPU then draws the unit cube `instance_count` times in essentially one draw
	  call. Fewer draw calls = the big web/WebGL performance win this task is after.
	"""
	# Build the MultiMesh and declare its per-instance data layout.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D  # per-instance 3D transform
	mm.use_colors = true                          # per-instance colour (earthy shade)
	mm.mesh = _get_shared_unit_box_mesh()         # one unit cube shared by all chunks
	mm.instance_count = block_batch.size()        # allocate the instance buffer

	# Fill in each instance's transform (size+yaw+position) and colour.
	for i in block_batch.size():
		var entry: Dictionary = block_batch[i]
		mm.set_instance_transform(i, entry["transform"])
		mm.set_instance_color(i, entry["color"])

	# Wrap the MultiMesh in a MultiMeshInstance3D so it lives in the scene tree.
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BlockMultiMesh"
	mmi.multimesh = mm
	# One shared material for every block; vertex_color_use_as_albedo lets the
	# per-instance colours show through (see _get_shared_block_material).
	mmi.material_override = _get_shared_block_material()

	# Parent at the chunk's LOCAL origin: the instance transforms are already local to
	# the chunk (create_box used chunk-local `center_pos`), and the chunk mesh itself
	# is positioned in the world — so the blocks land exactly where they did before.
	parent_chunk.add_child(mmi)

func spawn_crocodiles_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Spawns crocodile NPCs within a terrain chunk.

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach crocodiles to
	@param obstacles: Block footprints to keep crocodiles out of, so they don't
	                  spawn partially buried inside a block (see spawn_objects_in_chunk)

	EDUCATIONAL NOTE:
	- Crocodiles are spawned dynamically with the terrain
	- They are parented to the chunk so they're removed when chunk is removed
	- This creates an endless stream of enemies as you explore
	"""

	if not crocodile_scene:
		return

	# Use chunk coordinates (+ this run's seed) to create a unique but consistent seed.
	# Different multipliers than the object seed give different positions than objects;
	# run_seed makes crocodile placement differ run-to-run (constant within a run).
	var seed_value := hash(Vector3i(chunk_pos.x * 83492791, chunk_pos.y * 28411639, run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Calculate the world position of this chunk's corner
	var chunk_world_pos := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0

	# Store positions of spawned crocodiles to check spacing
	var spawned_positions: Array[Vector3] = []

	# Difficulty gradient: chunks farther from origin (along the road's +X axis) hold
	# MORE crocodiles — +1 per 6 chunks of |x| distance, capped at +8 over the base.
	# A pure function of chunk coords, so within-run determinism is untouched (the
	# same chunk always regenerates the same count). The LOD manager keeps the extra
	# distant crocodiles cheap: they are slept (frozen, monitoring off), never removed.
	var chunk_croc_target := crocodiles_per_chunk + mini(8, absi(chunk_pos.x) / 6)

	# CITY — the one band whose croc target is divided (owner call, 2026-08-26: a
	# city is not croc-free, it is QUIETER; the roofs are the real safety).
	#
	# A TARGET, NOT A ROLL, exactly like DESERT_BLOCK_KEEP_EVERY: the biome is a
	# pure function of chunk coords, so the branch costs no RNG draw and inserts
	# none. The consequence is worth stating precisely — the surviving crocodiles
	# are byte-for-byte the FIRST target/N of the undivided stream, standing in the
	# same positions, with the tail simply never spawned. Nothing shifts.
	#
	# This is a DESIGN number (the difficulty gradient's sibling), not a perf trim,
	# so the "entity counts are never reduced as an optimization" convention holds.
	var chunk_biome: Biome = biome_at(chunk_world_pos.x, chunk_world_pos.z)
	if chunk_biome == Biome.CITY:
		chunk_croc_target = maxi(1, int(roundf(float(chunk_croc_target) / CITY_CROC_DIVISOR)))

	# WHICH PREDATOR THIS CHUNK GETS — one table lookup on the biome already
	# resolved above, and NOT ONE RNG DRAW (see BIOME_SPECIES for why that is a
	# constraint rather than a preference). The whole chunk gets one species,
	# because the biome field is what varies and it varies at the ~8-chunk scale
	# of BIOME_CELL_SIZE; picking per crocodile would need a draw, and a draw is
	# exactly what is not allowed here.
	#
	# `rng` is untouched by any of this, so a PLAINS chunk generates the identical
	# crocodiles it always did, down to the last float.
	#
	# The crocodile stays the default, and a biome with no BIOME_SPECIES entry
	# never even reaches the load: PLAINS takes the `crocodile_scene` it always
	# took. A species whose scene fails to load also falls back rather than
	# spawning nothing — same degrade-don't-crash rule as the AI's own unknown-
	# species warning, and a visibly wrong animal beats an invisibly empty chunk.
	var chunk_species: String = "crocodile"
	var species_scene: PackedScene = crocodile_scene
	if BIOME_SPECIES.has(chunk_biome):
		var row: Dictionary = BIOME_SPECIES[chunk_biome]
		if not _species_scenes.has(chunk_biome):
			_species_scenes[chunk_biome] = load(row["scene"])
			if not _species_scenes[chunk_biome]:
				push_warning("endless_terrain: failed to load %s, using the crocodile"
						% row["scene"])
		var scene: PackedScene = _species_scenes[chunk_biome]
		if scene:
			chunk_species = row["species"]
			species_scene = scene

	# Try to spawn crocodiles with proper spacing
	var attempts := 0
	var max_attempts := chunk_croc_target * 5  # Allow multiple attempts per crocodile

	while spawned_positions.size() < chunk_croc_target and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		var margin := 3.0  # Keep away from edges
		var random_x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var random_z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var crocodile_pos := Vector3(random_x, 0.5, random_z)  # Y=0.5 to spawn above ground

		# Check if this position is far enough from existing crocodiles
		var valid_position := true
		for existing_pos in spawned_positions:
			if crocodile_pos.distance_to(existing_pos) < min_crocodile_spacing:
				valid_position = false
				break

		# Also reject positions that overlap a block, so crocodiles never spawn
		# partially inside one. We compare horizontal distance against the block's
		# footprint radius plus a clearance margin.
		if valid_position:
			for ob in obstacles:
				var horizontal := Vector2(crocodile_pos.x - ob.pos.x, crocodile_pos.z - ob.pos.z).length()
				if horizontal < ob.radius + min_object_clearance:
					valid_position = false
					break

		# Crocodiles don't stand in rivers — the water is the player's, and a river
		# reads as a small safe(r) crossing. Rejected AFTER the position draws, so
		# the candidate itself costs the stream nothing extra — but a rejection
		# still skips the successful spawn's `rotation.y` draw below, so the rest
		# of this chunk's crocodile positions shift. Deterministic within a run
		# (is_river_at is pure), just not identical to a river-free chunk.
		#
		# chunk_croc_target is deliberately NOT reduced: density is a DESIGN number
		# (the difficulty gradient), never trimmed for a biome. The while loop's
		# generous retry budget (5 tries per crocodile) simply finds dry spots
		# instead, so a chunk merely grazed by a river keeps its full count; only a
		# chunk almost entirely under water ends up with fewer.
		if valid_position and is_river_at(chunk_world_pos + crocodile_pos):
			valid_position = false

		# Keep the spawn point clear (see SPAWN_SAFE_RADIUS). Same post-draw `continue`
		# discipline as the river skip directly above — the candidate's own draws are
		# already spent, so nothing upstream shifts; only the handful of chunks touching
		# the origin bubble are affected, and identically on every run.
		var croc_world := chunk_world_pos + crocodile_pos
		if valid_position and Vector2(croc_world.x, croc_world.z).length() < SPAWN_SAFE_RADIUS:
			valid_position = false

		# Keep the tower's site clear too — the same rule as the spawn bubble above
		# (a fixed disc nothing procedural may stand in), enforced with the same
		# post-draw `continue`. min_object_clearance is the margin the block test
		# already uses for "a crocodile is not a point".
		if valid_position and tower_excludes(croc_world.x, croc_world.z, min_object_clearance):
			valid_position = false

		if not valid_position:
			continue

		# Instantiate this chunk's predator (crocodile everywhere but the desert)
		var crocodile_instance = species_scene.instantiate()
		# NAMED "Crocodile_…" WHATEVER THE SPECIES, deliberately. The name is this
		# spawn SLOT's identity, not a label: piglet_crocodile_ai.croc_id_for()
		# hashes it into the room-wide id multiplayer syncs on, and
		# enemy_spawn_selfcheck classifies ground spawns by the prefix. Species is
		# a pure function of position, so every peer already agrees on it — a
		# per-species prefix would only churn every id for nothing.
		crocodile_instance.name = "Crocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, spawned_positions.size()]

		# Position relative to chunk
		crocodile_instance.position = crocodile_pos

		# Random initial rotation for variety
		crocodile_instance.rotation.y = rng.randf_range(0, TAU)

		# CALL-ORDER CONTRACT (the setup_as_boss shape): hand over the deterministic
		# size/speed roll seed BEFORE add_child, so the croc's _ready() sees it and
		# seeds its own rng from it instead of randomize()ing. Non-negative index =
		# the ground crocodile stream (see _croc_roll_seed).
		crocodile_instance.setup_roll_seed(_croc_roll_seed(chunk_pos, spawned_positions.size()))
		# SAME CALL-ORDER CONTRACT, and it is the reason `species` is a plain
		# public field: _ready() is where it is resolved into `spec` and where the
		# size/speed rolls that READ that spec happen, so assigning it after
		# add_child() would roll a crocodile's numbers onto a viper's body.
		crocodile_instance.species = chunk_species

		# Add to chunk (so it gets removed when chunk is removed)
		parent_chunk.add_child(crocodile_instance)
		spawned_positions.append(crocodile_pos)

func spawn_platform_crocodiles(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> void:
	"""
	Place rare crocodiles that patrol an elevated structure top (a terraced mound's
	summit, a wall ridge or a forest log bridge). They can't jump or climb, so each is confined to its platform —
	it paces around but never walks off the edge (see set_confinement in the AI).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach the crocodiles to
	@param platforms: Walkable-top descriptors
	                  ({ "center": Vector3, "half": Vector2, "top": float }) —
	                  `center.y` is the surface the guard paces, `top` is the
	                  TALLEST stone inside the footprint, which is what the guard
	                  is dropped in from (see the note in spawn_wall).
	"""
	if not crocodile_scene or platforms.is_empty():
		return

	# Chunk coords + run_seed, like every other seed site (see the run_seed doc block).
	var seed_value := hash(Vector3i(chunk_pos.x * 40499, chunk_pos.y * 86969, run_seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var count := 0
	for platform in platforms:
		# Only some platforms get a guard, so they stay a rare surprise.
		if rng.randf() > platform_crocodile_chance:
			continue

		var center: Vector3 = platform.center
		var half: Vector2 = platform.half

		# Start a little in from the edges so it lands cleanly on the surface.
		var ang := rng.randf_range(0.0, TAU)
		var sx := maxf(0.0, half.x - PLATFORM_SPAWN_EDGE_INSET) * cos(ang)
		var sz := maxf(0.0, half.y - PLATFORM_SPAWN_EDGE_INSET) * sin(ang)

		var crocodile := crocodile_scene.instantiate()
		crocodile.name = "PatrolCrocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, count]
		# Spawn just above the TALLEST stone in the platform's footprint, not above
		# the paced surface, so gravity settles it onto the ridge or onto a hump
		# instead of dropping it INSIDE one. `sx`/`sz` above pick a random angle
		# along the platform and nothing here knows which sections are doubled, so
		# the maximum is the only height that is clear at every angle — see the
		# platform "top" note in spawn_wall for the measurement.
		crocodile.position = Vector3(center.x + sx, platform.top + PLATFORM_SPAWN_HEIGHT, center.z + sz)
		crocodile.rotation.y = rng.randf_range(0.0, TAU)
		# Same BEFORE-add_child contract as the ground spawner above. NEGATIVE indices
		# (-1, -2, …) keep the platform guards on their own slice of the roll stream,
		# so platform guard #0 and ground crocodile #0 in the same chunk don't roll
		# the identical size and speed.
		crocodile.setup_roll_seed(_croc_roll_seed(chunk_pos, -1 - count))
		parent_chunk.add_child(crocodile)

		# Confine it to this platform (in world space) so it can never wander off.
		if crocodile.has_method("set_confinement"):
			var center_global: Vector3 = parent_chunk.global_position + center
			crocodile.set_confinement(center_global, half)

		count += 1

func _croc_roll_seed(chunk_pos: Vector2i, index: int) -> int:
	"""
	Deterministic seed for one crocodile's per-instance SIZE/SPEED rolls.

	@param chunk_pos: Chunk that spawns the crocodile
	@param index: Which crocodile in that chunk. Ground crocodiles pass their
	              spawn slot (0, 1, 2, …); platform guards pass -1 - count, so the
	              two spawners can never hand the same seed to two crocodiles in
	              the same chunk.
	@return: Seed to hand the instance via setup_roll_seed()

	This is its OWN independent hash stream — the _boss_at / _artifact_at /
	_camp_at pattern — mixing chunk coords, the croc index and run_seed with
	coordinate primes distinct from the object (73856093 / 19349663), biome
	(83492791 / 15485863) and camp (40960001 / 26463089) streams. It draws from NO
	RandomNumberGenerator at all, so the crocodile spawner's own sequence — and
	therefore every crocodile POSITION — is byte-for-byte unchanged.

	WHY it exists: multiplayer needs every peer to compute identical crocodile
	spawn state from the shared run_seed. Everything else in world generation was
	already a pure function of chunk coords + run_seed; the crocodile's size/speed
	rolls were the one single-player-era exception (a randomize()d per-instance
	RNG), and this is what closes it.
	"""
	return hash(Vector3i(
		chunk_pos.x * 179424673 + index,
		chunk_pos.y * 32452843,
		run_seed ^ CROC_ROLL_SALT
	))

func _boss_at(i: int) -> Dictionary:
	"""
	Deterministic placement + size for boss index `i` (>= 1). Pure function of
	`i` + run_seed via the independent BOSS_SEED hash stream — no shared RNG is
	touched, so the rest of the world regenerates byte-identically.

	@param i: Boss index (1-based). Owns station k = i * BOSS_INTERVAL_STATIONS.
	          ASSUMES the station cache already covers `k` (callers
	          _road_extend_to_x first, like _road_coins_at).
	@return: { "positions": Array[Vector3] (world-space candidates, best first),
	           "scale": float (body scale) }.

	EDUCATIONAL NOTE:
	- The RNG draws ONLY lateral offsets (BOSS_PLACE_TRIES draws, fixed order),
	  so boss placement is stable within a run: revisiting a chunk regenerates
	  the identical boss. Across runs, run_seed changes BOTH the road and this
	  stream, so bosses land elsewhere.
	- positions[0] is the ONE draw this function used to make, and it is drawn
	  FIRST, so it is bit-identical to the pre-obstacle-check behaviour. The
	  extra candidates are appended AFTER it and only ever consulted when the
	  spawner rejects an earlier one for standing in a block footprint — nothing
	  in the schedule (station, size, rarity) moves.
	- Y sits a little above ground; gravity settles the body (the croc's capsule
	  bottom is at its origin, so this works at any scale).
	"""
	var k := i * BOSS_INTERVAL_STATIONS
	var st: Dictionary = _road_station(k)
	var heading: float = st.heading
	# Same tangent/perp construction as _road_coins_at (XZ plane; Vector2.x ->
	# world X, Vector2.y -> world Z).
	var tangent := Vector2(cos(heading), sin(heading))
	var perp := Vector2(-sin(heading), cos(heading))

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(i, BOSS_SEED, run_seed))
	# Candidate lateral offsets, drawn in one fixed order. The first draw is the
	# original (and overwhelmingly the used) one; the rest are fallbacks for a
	# boss whose primary spot happens to sit inside a block/tree/mountain
	# footprint — see spawn_bosses_in_chunk.
	var positions: Array[Vector3] = []
	for _try in BOSS_PLACE_TRIES:
		var lateral := rng.randf_range(-1.0, 1.0) * BOSS_LATERAL_MAX
		var p: Vector2 = st.center + tangent * BOSS_FORWARD_OFFSET + perp * lateral
		positions.append(Vector3(p.x, 0.6, p.y))

	# Size schedule: boss 1 is exactly BOSS_BASE_SCALE, each successive boss is
	# BOSS_GROWTH of base bigger, capped at BOSS_MAX_SCALE (see the consts above).
	var body_scale := minf(BOSS_BASE_SCALE * (1.0 + float(i - 1) * BOSS_GROWTH), BOSS_MAX_SCALE)
	return { "positions": positions, "scale": body_scale }

func _boss_row_at(station_centre: Vector2) -> Dictionary:
	"""
	Which animal guards the boss station whose centreline point is `station_centre`.

	@param station_centre: The OWNING STATION's centre in world coordinates,
	                       packed the way the road cache packs it (Vector2.x is
	                       world X, Vector2.y is world Z). Pure in the boss index
	                       + run_seed, which is what makes this answer pure in the
	                       boss index too — see BIOME_BOSS for why it must be.
	@return: { "species": String, "scene": PackedScene }. Never empty: the
	         crocodile is the fallback for a river station, for a band with no
	         BIOME_BOSS row, and for a row whose scene fails to load.

	NOT ONE RNG DRAW, and that is a constraint rather than a preference (CLAUDE.md's
	determinism section; the same rule BIOME_SPECIES and CITY_CROC_DIVISOR are held
	to). biome_at() and is_river_at() are the pure, allocation-free public API — one
	noise evaluation each, no shared stream touched — so inserting this call left
	_boss_at's BOSS_SEED stream consuming byte-identical draws in the same order.

	With BIOME_BOSS empty every path here returns the crocodile, which is the seam
	landing with zero behaviour change.
	"""
	var fallback := { "species": "crocodile", "scene": crocodile_scene }
	# Rivers first, and unconditionally: the owner's rule is that water is the
	# crocodile's, whichever band the noise field says the station stands in.
	if is_river_at(Vector3(station_centre.x, 0.0, station_centre.y)):
		return fallback
	var biome: Biome = biome_at(station_centre.x, station_centre.y)
	if not BIOME_BOSS.has(biome):
		return fallback
	var row: Dictionary = BIOME_BOSS[biome]
	# Lazily loaded and cached per band, exactly like _species_scenes: a run may
	# never walk far enough to meet a snow boss, and the one that does should not
	# re-load() the scene at every station.
	if not _boss_scenes.has(biome):
		_boss_scenes[biome] = load(row["scene"])
		if not _boss_scenes[biome]:
			push_warning("endless_terrain: boss scene %s failed to load, using the crocodile"
					% row["scene"])
	var scene: PackedScene = _boss_scenes[biome]
	if not scene:
		return fallback
	return { "species": String(row["species"]), "scene": scene }


func spawn_bosses_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Spawn this chunk's boss crocodiles — the rare road-guarding giants placed every
	BOSS_INTERVAL_STATIONS stations along the coin road (see the BOSS CROCODILES
	config section near the top).

	Follows spawn_coins_in_chunk's seam-claim pattern exactly: extend the shared
	station cache over this chunk's padded X-window, walk the boss indices whose
	stations fall inside it, and spawn ONLY the bosses whose FINAL world position
	lands in THIS chunk (world_to_chunk(pos) == chunk_pos) — each boss is claimed
	by exactly one chunk, so there are no seam gaps or duplicates.

	A boss is 2.5x–6x the size of a normal crocodile and stands ON the road, so a
	boss wedged into a wall/mound/tree/mountain sits right on the player's path.
	Each boss therefore walks its deterministic candidate list (see _boss_at) and
	takes the first spot clear of every footprint in `obstacles`, exactly like the
	sibling spawners — and is skipped entirely if none is clear.

	THE CLAIM RULE (why the candidate walk stops early): `obstacles` only
	describes THIS chunk, so a chunk can only judge candidates that land inside
	itself. The loop therefore stops at the first candidate outside this chunk —
	from there on, another chunk owns the decision. That makes duplicates
	impossible: a chunk can only spawn a boss whose FIRST candidate already lies
	inside it, and only one chunk can contain that first candidate. The price is
	that a boss whose first candidate is blocked and whose next clear candidate
	falls in a NEIGHBOURING chunk is skipped rather than moved — a rare
	no-boss-here, which is an outcome the design already allows.

	@param chunk_pos: Chunk coordinates this call is generating bosses for.
	@param parent_chunk: The chunk mesh to attach bosses to. Chunk parenting is a
	                     FEATURE here: outrunning a boss far enough unloads its
	                     chunk and frees the boss with it — which reads to the
	                     player as "you escaped it".
	@param obstacles: This chunk's block footprints ({ pos (chunk-LOCAL), radius,
	                  top, climbable }), as built by spawn_objects_in_chunk and
	                  extended by the artifact/biome builders.
	"""
	if not crocodile_scene:
		return

	# Padded chunk X-window, same shape as the coin scan: a boss's world X can
	# differ from its station's centerline X by at most the forward offset plus
	# the lateral offset (each projection is bounded by its magnitude), so this
	# pad guarantees no boss near a seam is ever missed by the chunk that owns it.
	var center := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0
	var x0 := center.x - half_chunk
	var x1 := center.x + half_chunk
	var pad := BOSS_LATERAL_MAX + BOSS_FORWARD_OFFSET + 2.0

	_road_extend_to_x(x0 - pad, x1 + pad)

	# Smallest boss index whose station could fall at/after the window start:
	# round the first in-window station up to the next interval multiple. Bosses
	# start at index 1 — station 0 is the player spawn, no boss there.
	var k_start := _road_first_k_at_or_after_x(x0 - pad)
	var i := maxi(1, ceili(float(k_start) / float(BOSS_INTERVAL_STATIONS)))
	while true:
		var cur_i := i
		i += 1
		var k := cur_i * BOSS_INTERVAL_STATIONS
		# Past the cache = past this chunk's padded window (the cache spans it and
		# centerline X is strictly increasing in k), so we're done either way.
		if k > road_k_max:
			break
		# The station's centreline point, read ONCE: it bounds the window scan
		# below AND it is what this boss's species is dispatched on (see
		# _boss_row_at) — the only coordinate a boss has that is pure in `cur_i`.
		var station_centre: Vector2 = _road_station(k).center
		if station_centre.x > x1 + pad:
			break

		# WHICH BOSS THIS STATION GETS, decided HERE — above the candidate walk,
		# and that position in the function is the point. Dispatching on the
		# station centre is what makes the boss KIND a pure function of `cur_i`;
		# the walk below only decides WHERE the animal stands (or whether it fits
		# at all), by testing BOSS_PLACE_TRIES offsets against this chunk's
		# geometry. Compute the kind before `local_pos` exists and keying on the
		# placed candidate — which is neither pure in `cur_i` nor guaranteed to be
		# in the same biome band — is not a mistake that can be made by accident.
		# Pure function calls, no RNG draw, so the stream below is untouched.
		var boss_row: Dictionary = _boss_row_at(station_centre)

		var boss: Dictionary = _boss_at(cur_i)
		var boss_scale: float = boss.scale
		# Clearance this boss needs, SCALED BY ITS SIZE — a 6x boss reaches ~4.2 m
		# where a normal crocodile reaches ~0.7, so the crocodile spawner's fixed
		# min_object_clearance would be nowhere near enough (see the constant).
		var footprint: float = BOSS_FOOTPRINT_RADIUS_PER_SCALE * boss_scale

		# Walk the deterministic candidates: take the first one that is both ours
		# (the claim rule in the docstring) and clear of every footprint.
		var local_pos := Vector3.ZERO
		var placed := false
		for candidate in boss.positions:
			# Exactly-one-chunk claim: the moment a candidate lands elsewhere, that
			# chunk owns the rest of this boss's decision — stop, don't skip ahead.
			if world_to_chunk(candidate) != chunk_pos:
				break
			# Obstacle footprints are stored chunk-LOCAL, so compare in that space.
			var local := Vector3(candidate.x - center.x, candidate.y, candidate.z - center.z)
			var clear := true
			for ob in obstacles:
				var horizontal := Vector2(local.x - ob.pos.x, local.z - ob.pos.z).length()
				if horizontal < ob.radius + footprint:
					clear = false
					break
			# The tower's site is one more thing a boss may not stand in — its own
			# scaled footprint again, so a 6x boss cannot lean into the doorway.
			# Post-draw by construction: _boss_at already computed this whole
			# candidate list on its own hash stream, so skipping one costs nothing.
			if clear and tower_excludes(candidate.x, candidate.z, footprint):
				clear = false
			if clear:
				local_pos = local
				placed = true
				break
		# Not ours, or every candidate of ours was buried in geometry: no boss here.
		if not placed:
			continue

		var croc = boss_row["scene"].instantiate()
		# THE NAME IS "BossCrocodile_%d" FOR EVERY SPECIES, deliberately. croc_id
		# derives from the deterministic node name, so it is this body's
		# multiplayer identity, and enemy_spawn_selfcheck's sweep classifies
		# bodies by exactly these three prefixes. A per-species name would buy
		# nothing and churn both.
		croc.name = "BossCrocodile_%d" % cur_i
		# Chunk-LOCAL position (relative to the chunk center), like every other
		# chunk-parented node. Default rotation — the wander AI turns it within a
		# second anyway, and drawing a rotation would add an RNG draw for nothing.
		croc.position = local_pos
		# CALL-ORDER CONTRACT, one line longer than it used to be: `species`
		# BEFORE setup_as_boss BEFORE add_child. _ready() runs on add_child
		# (terrain-parented) and it is where BOTH halves are read — it resolves
		# `spec` from `species` exactly once, and it sees the boss flags and skips
		# the random speed/size rolls in favour of the schedule. Assign either one
		# after add_child and the body keeps a crocodile's spec, or takes rolls a
		# boss must not have, with no error anywhere. This is the same contract
		# the ground spawner's `species` assignment has, for the same reason.
		croc.species = boss_row["species"]
		croc.setup_as_boss(boss.scale)
		parent_chunk.add_child(croc)

func _artifact_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic artifact placement for one chunk — the _boss_at of artifacts.
	Pure function of chunk coords + run_seed via the independent ARTIFACT_SALT
	hash stream: it consumes NO draw from the shared chunk RNG, so every existing
	block/crocodile/coin is exactly where it was before artifacts existed.

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when this chunk has no artifact (the ~19-in-20 case); otherwise
	         { "seed": int } — the seed for the artifact's private RNG, which
	         spawn_artifact_in_chunk uses for placement, shape and geometry.

	WHY THE CANDIDATE LOOP IS NOT HERE — same split, for the same reason, as
	_camp_at / spawn_camp_in_chunk: when this runs the chunk has no geometry yet,
	so the only tests available are road + river, and neither rejects the thing
	that actually matters. Judging candidates here left artifacts placed with NO
	obstacle test at all: measured over a 61x61 chunk field, 51.5% of artifacts
	interpenetrated a scattered block or a feature structure, one of them buried
	16.5 m deep inside a pyramid — taking its coin ring and its ONE guaranteed gem,
	the whole reason to detour off the road, into the stone with it. That is
	exactly the fused-solids bug _camp_spot_clear exists to prevent, one landmark
	over. The loop therefore lives in spawn_artifact_in_chunk, where `obstacles`
	exists.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL artifact (same spot, same
	  shape, same stones) no matter how often it unloads and regenerates: the RNG
	  is seeded purely from chunk coords + run_seed, and every draw downstream
	  comes off that one seeded stream in a fixed order.
	- Across runs, new_run() re-rolls run_seed, so artifacts land elsewhere.
	- The road-clearance test reads the station cache (pure in `k`), the river test
	  reads the biome field (pure in world position + run_seed), and the overlap
	  test reads the chunk's own obstacle list (pure in chunk coords + run_seed) —
	  so all three are load-order independent: rejection is a property of the
	  POSITION, not of when the chunk happened to generate.
	"""
	var rng := RandomNumberGenerator.new()
	# Same coordinate mixing as the chunk object seed, but salted so this stream
	# never collides with (or perturbs) any other deterministic spawn site.
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ ARTIFACT_SALT))

	# Rarity roll — most chunks bail here. This is the ONLY draw taken from the
	# stream at this point; the rest happen in spawn_artifact_in_chunk off an RNG
	# re-seeded from `seed`, so the two stay a single fixed sequence per chunk.
	if rng.randf() >= ARTIFACT_CHANCE:
		return {}

	return { "seed": rng.randi() }

# ============================================================================
# ARTIFACT SHAPE BUILDERS (the five code-built "lost civilization" landmarks)
# ============================================================================
#
# Every builder shares ONE signature and ONE contract:
#   _artifact_<shape>(center, rng, parent_chunk, block_batch, block_body)
#     -> { "radius": float, "top": float, "gem_offset": Vector3 }
# - ALL solid stone goes through create_box(..., tilt, _artifact_stone_color(rng)),
#   so it joins the chunk's single block MultiMesh and single BlockCollision body:
#   an artifact's stone costs ZERO extra draw calls and ZERO extra physics bodies.
# - ALL glow goes through _spawn_artifact_accent — real MeshInstance3Ds, at most
#   ARTIFACT_MAX_ACCENTS per artifact. That is the entire per-artifact draw budget.
# - `rng` is the artifact's PRIVATE RNG (seeded from _artifact_at's "seed"), so
#   builders draw as freely as they like without touching any shared stream.
# - The returned radius/top approximate the footprint for the chunk's `obstacles`
#   list (crocodile spawn rejection + the coin perch rule). Conservative (a touch
#   generous) is fine; exact is not required.
# - gem_offset is where the single reward gem goes, as an offset from `center` on
#   the ground plane: Vector3.ZERO for the shapes with an open middle, and a step
#   clear of the stone for the two whose centre is solid (monolith, colossus
#   head) so the prize is never spawned inside a block.

func _artifact_stone_color(rng: RandomNumberGenerator) -> Color:
	"""
	One weathered stone colour: a random spot on the ARTIFACT_STONE_A → B grey
	ramp, then pushed a random amount (up to ARTIFACT_MOSS_MAX) toward dead-moss
	green. Every stone comes out a slightly different grey-green — deliberately
	DISTINCT from the warm/blue curated RAMP_* block colours, so an artifact reads
	as "from another age" at a glance.
	"""
	var grey := ARTIFACT_STONE_A.lerp(ARTIFACT_STONE_B, rng.randf())
	return grey.lerp(ARTIFACT_MOSS, rng.randf() * ARTIFACT_MOSS_MAX)

func _artifact_monolith(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 0 — LEANING HALF-BURIED MONOLITH: one tall slab sunk into the ground at
	a drunken angle, with three glowing rune strips stacked up its exposed face.
	The tilt is the whole point (it is why create_box grew the tilt parameter).
	"""
	var yaw := rng.randf_range(0.0, TAU)
	# Lean 0.12..0.25 rad to a random side — enough to read as "toppling for a
	# thousand years", not enough to look knocked over.
	var tilt := rng.randf_range(0.12, 0.25) * (1.0 if rng.randf() < 0.5 else -1.0)
	var dims := Vector3(1.8, 8.0, 1.1)
	var buried := rng.randf_range(1.2, 2.2)
	# Centre BELOW y=0 by `buried`, so the base is swallowed by the ground.
	var slab_center := center + Vector3(0.0, dims.y / 2.0 - buried, 0.0)
	create_box(slab_center, dims, yaw, rng, block_batch, block_body, tilt, _artifact_stone_color(rng))
	# Three rune strips up the slab's front (+Z) face. Positions are rotated by
	# the SAME yaw*tilt basis as the slab, then pushed just past the face along
	# its normal so each strip sits proud of the stone instead of z-fighting it.
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	for i in 3:
		var local_offset := Vector3(0.0, 0.6 + 1.5 * float(i), dims.z / 2.0 + 0.06)
		_spawn_artifact_accent(parent_chunk, slab_center + rot * local_offset, Vector3(1.1, 0.35, 0.08), yaw, tilt)
	# Horizontal reach ≈ half width + the lean's horizontal throw; 2.5 covers it.
	# gem_offset: the centre column is solid slab, so the prize sits just off the
	# runed face where the player can actually reach it (rotated by the slab yaw).
	return {
		"radius": 2.5,
		"top": slab_center.y + (dims.y / 2.0) * cos(tilt),
		"gem_offset": Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, dims.z / 2.0 + 1.2),
	}

func _artifact_arch(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 1 — BROKEN ARCH OF FLOATING STONES: 7-9 rough blocks along a vertical
	half-circle, with 1-2 consecutive stones MISSING so the arc reads as broken;
	a single glowing accent hangs in the gap — the keystone that is not there.
	(Static geometry needs no support, so the remaining stones simply float.)
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var radius := 5.0
	var count := rng.randi_range(7, 9)
	var gap_len := rng.randi_range(1, 2)
	# Gap somewhere in the upper body of the arc — never the feet, so both ends
	# still stand on the ground and the silhouette stays readable as an arch.
	var gap_start := rng.randi_range(2, count - 2 - gap_len)
	var rot_arch := Basis(Vector3.UP, yaw)
	var i := 0
	while i < count:
		var a := PI * float(i) / float(count - 1)  # 0..PI sweeps foot → top → foot
		if i >= gap_start and i < gap_start + gap_len:
			i += 1
			continue  # the broken part — no stone, no RNG draws (sequence still fixed: gap indices were drawn above)
		var pos := center + rot_arch * Vector3(cos(a) * radius, sin(a) * radius, 0.0)
		var dims := Vector3(rng.randf_range(1.1, 1.5), rng.randf_range(0.9, 1.3), 1.0)
		create_box(pos, dims, yaw + rng.randf_range(-0.15, 0.15), rng, block_batch, block_body, rng.randf_range(-0.2, 0.2), _artifact_stone_color(rng))
		i += 1
	# The missing keystone: one accent floating at the gap's mid-angle.
	var a_mid := PI * (float(gap_start) + float(gap_len - 1) / 2.0) / float(count - 1)
	_spawn_artifact_accent(parent_chunk, center + rot_arch * Vector3(cos(a_mid) * radius, sin(a_mid) * radius, 0.0), Vector3(0.7, 0.7, 0.7), yaw, 0.0)
	# Hollow centre — the gem sits on the ground under the arch (offset ZERO).
	return { "radius": radius + 1.0, "top": radius + 1.0, "gem_offset": Vector3.ZERO }

func _artifact_stone_circle(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 2 — CIRCLE OF TILTED STANDING STONES: 6-9 slabs on a ring, each facing
	the centre and leaning drunkenly inward or outward, around a low central slab
	with one wide flat glowing panel lying on its top face.
	"""
	var base_yaw := rng.randf_range(0.0, TAU)
	var ring_r := rng.randf_range(4.0, 6.0)
	var count := rng.randi_range(6, 9)
	# Low central slab — the "altar" the glow panel lies on.
	var slab_dims := Vector3(3.0, 0.6, 3.0)
	create_box(center + Vector3(0.0, slab_dims.y / 2.0, 0.0), slab_dims, base_yaw, rng, block_batch, block_body, 0.0, _artifact_stone_color(rng))
	var tallest_top := slab_dims.y
	var i := 0
	while i < count:
		var a := base_yaw + TAU * float(i) / float(count)
		# yaw = PI/2 - a points the slab's local Z (its thin depth axis) along the
		# radial direction — i.e. the slab FACES the centre — which makes tilt
		# (about local X, the tangent) lean it radially inward/outward.
		var stone_yaw := PI / 2.0 - a
		var lean := rng.randf_range(-0.3, 0.3)
		var stone_dims := Vector3(1.3, rng.randf_range(2.8, 4.0), 0.7)
		var sink := rng.randf_range(0.3, 0.7)  # half-buried, like the monolith
		var pos := center + Vector3(cos(a) * ring_r, stone_dims.y / 2.0 - sink, sin(a) * ring_r)
		create_box(pos, stone_dims, stone_yaw, rng, block_batch, block_body, lean, _artifact_stone_color(rng))
		tallest_top = maxf(tallest_top, pos.y + (stone_dims.y / 2.0) * cos(lean))
		i += 1
	# One wide, nearly-flat glow panel on the centre slab's top face.
	_spawn_artifact_accent(parent_chunk, center + Vector3(0.0, slab_dims.y + 0.05, 0.0), Vector3(2.0, 0.08, 2.0), base_yaw, 0.0)
	# Offset ZERO: the gem sits dead centre, hovering just over the glowing altar
	# slab (COIN_GROUND_HEIGHT 0.9 clears its 0.6 top) — the obvious prize spot.
	return { "radius": ring_r + 1.0, "top": tallest_top, "gem_offset": Vector3.ZERO }

func _artifact_colossus_head(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 3 — HALF-BURIED COLOSSUS HEAD: a huge jaw box sunk into the ground, a
	narrower brow box stacked on top, a slab nose on the front face, all sharing
	one yaw so they read as a single fallen statue; two glowing eyes inset under
	the brow. Ozymandias, in cubes.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _artifact_stone_color(rng)  # ONE colour for the whole head — it is one statue, not a pile
	var jaw := Vector3(3.6, 2.4, 3.0)
	var jaw_center := center + Vector3(0.0, jaw.y / 2.0 - rng.randf_range(0.8, 1.4), 0.0)
	create_box(jaw_center, jaw, yaw, rng, block_batch, block_body, 0.0, stone)
	# Brow: narrower, pushed slightly back so the face has a step.
	var brow := Vector3(3.2, 1.4, 2.4)
	var brow_center := jaw_center + rot * Vector3(0.0, jaw.y / 2.0 + brow.y / 2.0, -0.3)
	create_box(brow_center, brow, yaw, rng, block_batch, block_body, 0.0, stone)
	# Nose: a thin slab proud of the jaw's front (+Z) face, reaching up to the brow.
	var nose := Vector3(0.8, 1.7, 0.6)
	create_box(jaw_center + rot * Vector3(0.0, jaw.y / 2.0 + 0.2, jaw.z / 2.0 - 0.1), nose, yaw, rng, block_batch, block_body, 0.0, stone)
	# Two eyes, inset just under the brow's front face, either side of the nose.
	for side in [-1.0, 1.0]:
		var eye_pos := brow_center + rot * Vector3(side * 0.9, -brow.y / 2.0 - 0.15, brow.z / 2.0 + 0.05)
		_spawn_artifact_accent(parent_chunk, eye_pos, Vector3(0.5, 0.3, 0.12), yaw, 0.0)
	# gem_offset: the centre column is solid head, so the prize lies on the ground
	# in front of the face — under its gaze, and reachable.
	return {
		"radius": 3.2,
		"top": brow_center.y + brow.y / 2.0,
		"gem_offset": rot * Vector3(0.0, 0.0, jaw.z / 2.0 + 1.2),
	}

func _artifact_spiral_steps(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 4 — SPIRAL OF STEPS TO NOWHERE: 10-16 floating step slabs winding up a
	helix, each facing the centre so its long edge follows the curve (a climbable
	staircase); one glowing accent hovers over the final, highest step — the
	destination that is not there.
	"""
	var base_a := rng.randf_range(0.0, TAU)
	var spiral_r := rng.randf_range(3.0, 4.0)
	var count := rng.randi_range(10, 16)
	var rise := 0.55  # per-step climb — jumpable by every character
	var step_dims := Vector3(1.6, 0.4, 0.9)
	var last_pos := center
	var last_yaw := 0.0
	var i := 0
	while i < count:
		var a := base_a + 0.6 * float(i)
		var pos := center + Vector3(cos(a) * spiral_r, step_dims.y / 2.0 + rise * float(i), sin(a) * spiral_r)
		# Same face-the-centre yaw as the stone circle: local Z radial, long X tangent.
		last_yaw = PI / 2.0 - a
		create_box(pos, step_dims, last_yaw, rng, block_batch, block_body, 0.0, _artifact_stone_color(rng))
		last_pos = pos
		i += 1
	# The non-destination: one small glow hovering above the top step.
	_spawn_artifact_accent(parent_chunk, last_pos + Vector3(0.0, 0.6, 0.0), Vector3(0.5, 0.5, 0.5), last_yaw, 0.0)
	# The helix winds AROUND an empty core, so the gem sits on the ground at the
	# centre of the spiral (offset ZERO) — you walk into the eye of the staircase.
	return { "radius": spiral_r + 1.2, "top": rise * float(count - 1) + step_dims.y, "gem_offset": Vector3.ZERO }

func spawn_artifact_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's artifact, if _artifact_at says it has one (~1 in 20), plus
	its coin reward. Called from create_chunk AFTER spawn_objects_in_chunk and
	BEFORE _build_block_multimesh / the block_body attach, so the artifact's stone
	joins the chunk's single MultiMesh and single BlockCollision body.

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — accents and reward coins parent here
	                     (per-chunk parenting rule: they unload with the chunk).
	@param obstacles: The chunk's block-footprint list — READ to reject candidate
	                  spots that would bury the artifact in existing stone, then
	                  appended to with the artifact's own footprint (see below).
	@param block_batch / block_body: The chunk's visual batch + collision body,
	                                 threaded through to create_box.
	"""
	if not spawn_artifacts:
		return
	var art := _artifact_at(chunk_pos)
	if art.is_empty():
		return

	# Everything below draws from ONE private RNG seeded by _artifact_at's roll, so
	# each builder can consume as many draws as its shape needs without any other
	# stream caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = art.seed

	var chunk_center := chunk_to_world(chunk_pos)
	# Candidates stay ARTIFACT_EDGE_MARGIN (12) inside the chunk so the whole
	# artifact (widest footprint ARTIFACT_RADIUS 7.0 < the margin) never straddles
	# a seam.
	var half := chunk_size / 2.0 - ARTIFACT_EDGE_MARGIN

	# Try a few candidate spots; accept the FIRST one that clears the road, the
	# water AND the stone already in this chunk. The road rejection is what
	# produces the off-road bias and the hard "never on the centerline" rule;
	# the overlap rejection is what keeps the landmark readable (see _artifact_at
	# for the 51.5%-interpenetration measurement that put it here). Every try
	# failing means NO artifact — a monolith fused into a mountain massif reads
	# worse than a chunk without one, which is the same call camps make.
	# _biome_spot_ok is the single home of that whole rule; ARTIFACT_RADIUS is the
	# widest any of the five shapes can be, since the real one is only known after
	# its builder runs.
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < ARTIFACT_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if _biome_spot_ok(chunk_center, local_x, local_z, ARTIFACT_RADIUS, ARTIFACT_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	# Which of the five shapes.
	var kind := rng.randi_range(0, 4)
	var center := Vector3(local_x, 0.0, local_z)

	var footprint: Dictionary
	match kind:
		0: footprint = _artifact_monolith(center, rng, parent_chunk, block_batch, block_body)
		1: footprint = _artifact_arch(center, rng, parent_chunk, block_batch, block_body)
		2: footprint = _artifact_stone_circle(center, rng, parent_chunk, block_batch, block_body)
		3: footprint = _artifact_colossus_head(center, rng, parent_chunk, block_batch, block_body)
		_: footprint = _artifact_spiral_steps(center, rng, parent_chunk, block_batch, block_body)

	# --- The reward: a ring of ordinary coins around the base + ONE gem at the
	# artifact's centre (the incentive to detour off the coin road). Guarded like
	# every other coin spawn; these are ordinary chunk-local coins parented to the
	# chunk — the road's station-claim logic is not involved in any way.
	#
	# ORDER MATTERS: the artifact's own footprint is appended to `obstacles` only
	# AFTER these coins are placed. Its footprint is a CIRCLE, but three of the
	# five shapes (arch, stone circle, spiral) are mostly HOLLOW — settling their
	# reward coins against that circle would perch them on the silhouette top,
	# i.e. floating several metres up in open air. Placing the reward first means
	# it settles only against real block stone, so it lies on the ground where the
	# player can actually pick it up.
	if spawn_coins and coin_scene != null:
		var coin_count := rng.randi_range(ARTIFACT_COIN_MIN, ARTIFACT_COIN_MAX)
		var ring_radius: float = footprint.radius + rng.randf_range(ARTIFACT_COIN_RING_PAD_MIN, ARTIFACT_COIN_RING_PAD_MAX)
		var i := 0
		while i < coin_count:
			i += 1
			var a := rng.randf_range(0.0, TAU)
			var cx := center.x + cos(a) * ring_radius
			var cz := center.z + sin(a) * ring_radius
			# Same perch-or-skip rule as road coins (one home: _settle_coin_y):
			# the ring can graze a neighbouring block, so a coin perches on a
			# climbable top or is dropped under a sheer wall.
			var cy := _settle_coin_y(cx, cz, COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin := coin_scene.instantiate()
			coin.position = Vector3(cx, cy, cz)
			parent_chunk.add_child(coin)

		# Exactly ONE gem, at the artifact's centre — offset by the shape's own
		# `gem_offset` for the two shapes whose centre is solid stone (monolith,
		# colossus head), so the prize sits at the foot of the landmark instead of
		# inside it. Hollow shapes return ZERO and keep the gem dead centre.
		# make_gem() BEFORE add_child, per coin.gd's contract (it fetches nodes
		# with get_node, not @onready).
		var gem_pos: Vector3 = center + footprint.gem_offset
		var gem_y := _settle_coin_y(gem_pos.x, gem_pos.z, COIN_GROUND_HEIGHT, obstacles)
		if not is_inf(gem_y):
			var gem := coin_scene.instantiate()
			gem.position = Vector3(gem_pos.x, gem_y, gem_pos.z)
			gem.make_gem()
			parent_chunk.add_child(gem)

	# Register the artifact as one round obstacle footprint, exactly like a normal
	# block. CONSEQUENCE (deliberate): crocodiles reject spawn points inside it,
	# and any ROAD coin whose column crosses it PERCHES on its top (climbable =
	# true) instead of being buried in the stone — artifact stone behaves like
	# ordinary block stone everywhere downstream.
	# ponytail: a hollow artifact (arch/circle/spiral) can float a road coin over
	# its empty middle, because one circle+top is the whole footprint vocabulary
	# the coin rule speaks. Erring this way never BURIES a coin in stone, which is
	# the failure the rule exists to prevent; if it ever looks wrong, give the
	# footprint a per-shape "solid centre height" rather than a taller vocabulary.
	obstacles.append({ "pos": center, "radius": footprint.radius, "top": footprint.top, "climbable": true })

# ============================================================================
# NOMAD CAMPS (rare dome-hut villages — see the NOMAD CAMPS constant banner)
# ============================================================================

func _camp_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic nomad-camp placement for one chunk — _artifact_at for camps,
	line for line. Pure function of chunk coords + run_seed via the independent
	CAMP_SALT hash stream: it consumes NO draw from the shared chunk RNG, so every
	existing block/crocodile/coin/artifact is exactly where it was before camps
	existed.

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when this chunk has no camp (the overwhelming majority); otherwise
	         { "seed": int (seeds the camp builders' AND the candidate loop's own
	           private RNG) }.
	         There is no "kind": a camp is ONE layout whose variety comes from the
	         builder RNG (hut count, ring radii, yaws), not from a shape enum.
	         There is no "local" either — WHERE the camp goes is decided in
	         spawn_camp_in_chunk, see below.

	WHY THE CANDIDATE LOOP IS NOT HERE (it used to be, measured and moved):
	this function runs before the chunk has any geometry, so the only tests it can
	make are the road and the river — and those reject almost nothing (measured:
	11 of 121 chunks). The test that actually rejects is the obstacle overlap
	against the chunk's ~12 scattered blocks plus its biome geometry, which needs
	the finished `obstacles` list and therefore lives in spawn_camp_in_chunk. With
	the loop here, all four tries varied a test that always passed and the single
	surviving spot then met the real test once: ~9% of rolled camps were built, so
	camps landed ~10x rarer than intended. The loop now sits where `obstacles`
	exists, so all CAMP_PLACE_TRIES tries vary the test that does the rejecting.

	EDUCATIONAL NOTE — the determinism contract (identical to _artifact_at's):
	- WITHIN A RUN the same chunk yields the IDENTICAL camp (same builder seed, and
	  hence the same candidate sequence downstream) no matter how often it unloads
	  and regenerates — the RNG is seeded purely from chunk coords + run_seed, and
	  its draw order is fixed (chance roll, then the builder seed).
	- ACROSS RUNS new_run() re-rolls run_seed, so camps land elsewhere.
	- The placement tests downstream read the station cache (pure in `k`), the
	  biome field (pure in world position + run_seed) and the chunk's own
	  obstacles (rebuilt identically from the chunk RNG), so all three are
	  load-order independent: a rejection is a property of the POSITION and the
	  CHUNK, not of when the chunk happened to generate.
	"""
	var rng := RandomNumberGenerator.new()
	# DIFFERENT coordinate primes from the artifact stream (73856093 / 19349663)
	# and the biome stream (83492791 / 15485863), so camp placement can never
	# correlate with either — a chunk that hosts an artifact is not thereby more
	# (or less) likely to host a camp.
	rng.seed = hash(Vector3i(chunk_pos.x * 40960001, chunk_pos.y * 26463089, run_seed ^ CAMP_SALT))

	# 1. Rarity roll — the overwhelming majority of chunks bail here.
	if rng.randf() >= CAMP_CHANCE:
		return {}

	# 2. A further seed for the camp's own RNG, which both picks the spot and
	# builds the geometry, so neither cares how many draws the other needs.
	return { "seed": rng.randi() }

# ----------------------------------------------------------------------------
# CAMP GEOMETRY BUILDERS (dome huts, fire pit, crates + tether posts)
# ----------------------------------------------------------------------------
#
# The ARTIFACT SHAPE BUILDERS' contract, reused wholesale:
# - ALL solid geometry goes through create_box(..., color_override), so a whole
#   village joins the chunk's single block MultiMesh and single BlockCollision
#   body: a camp costs ZERO extra draw calls and ZERO extra physics bodies.
# - The ONE exception is the ember, a real MeshInstance3D through
#   _spawn_artifact_accent — one extra unshadowed draw per camp, that's the lot.
# - `rng` is always the camp's PRIVATE RNG (seeded from _camp_at's "seed"), so
#   these builders draw as freely as their geometry needs without ever touching
#   the shared chunk stream.
# - Small decoration (doorways, fire stones) is spawned with collide = false, the
#   same call create_box already grew for forest canopies: ankle-high scenery you
#   should be able to walk over is not worth a CollisionShape3D each.

func _camp_hut(center: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Build ONE dome hut: 2-3 stacked box tiers, widest on the ground and each one
	narrower than the tier below, which is what turns a stack of cubes into an
	igloo read at a glance. The top tier is also SHORTER (its height takes the same
	CAMP_HUT_TIER_SHRINK factor), so the silhouette caps off as a dome rather than
	ending in a flat chimney. Each tier gets its own small yaw wobble, so no two
	huts look stamped from the same mould.

	@param center: Hut centre on the ground (chunk-local, y = 0).
	@param yaw: Facing. The doorway goes on the hut's local +Z face, so the caller
	            points +Z at the fire pit and every door faces the flames.
	@param rng: The camp's private RNG (see the section note above).
	@param block_batch / block_body: The chunk's visual batch + collision body.
	@return: { "radius": float, "top": float } — a conservative footprint for the
	         chunk's `obstacles` list, same shape the artifact builders return.
	"""
	var base_width := rng.randf_range(CAMP_HUT_WIDTH_MIN, CAMP_HUT_WIDTH_MAX)
	var tiers := rng.randi_range(CAMP_HUT_TIER_MIN, CAMP_HUT_TIER_MAX)
	var width := base_width
	var y := 0.0  # running height of the stack: the top of the tier placed so far
	var i := 0
	while i < tiers:
		# The last tier is squashed as well as narrowed — that is the dome cap.
		var tier_height: float = CAMP_HUT_TIER_HEIGHT * (CAMP_HUT_TIER_SHRINK if i == tiers - 1 else 1.0)
		var tier_yaw := yaw + rng.randf_range(-CAMP_HUT_YAW_JITTER, CAMP_HUT_YAW_JITTER)
		# Bone white, a fresh spot on the A→B ramp per tier so the shell is not one
		# flat colour (the artifacts' _artifact_stone_color trick, one lerp).
		var shell := CAMP_HUT_A.lerp(CAMP_HUT_B, rng.randf())
		create_box(center + Vector3(0.0, y + tier_height / 2.0, 0.0), Vector3(width, tier_height, width), tier_yaw, rng, block_batch, block_body, 0.0, shell)
		y += tier_height
		width *= CAMP_HUT_TIER_SHRINK
		i += 1

	# The doorway: one small dark box set into the fire-facing (+Z) wall. Half of it
	# sits inside the shell, so it reads as an opening rather than a porch.
	# collide = false — it is a 0.5 m thick decoration flush with a wall that
	# already collides, so a shape here would only add cost.
	var door_offset := Basis(Vector3.UP, yaw) * Vector3(0.0, CAMP_HUT_DOOR_SIZE.y / 2.0, base_width / 2.0)
	create_box(center + door_offset, CAMP_HUT_DOOR_SIZE, yaw, rng, block_batch, block_body, 0.0, CAMP_STONE, false)

	# Radius is the half-DIAGONAL of the widest tier (tiers are yawed, so the
	# half-width would under-cover a corner), plus a little for the doorway.
	return { "radius": base_width * 0.71 + 0.3, "top": y }

func _camp_fire_pit(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build the camp's heart: a ring of CAMP_FIRE_STONES small dark stones around the
	centre plus ONE emissive ember sitting in the middle of them.

	The ember is the camp's ENTIRE extra draw budget — one unshadowed MeshInstance3D
	through the shared _spawn_artifact_accent path, carrying the shared warm-orange
	material. The stones are ordinary batched boxes with collide = false: they are
	ankle-high scenery you should be able to step over, and skipping them saves
	CAMP_FIRE_STONES collision shapes per camp for no visible difference.

	@param center: Fire-pit centre on the ground (chunk-local, y = 0).
	@param rng: The camp's private RNG.
	@param parent_chunk: The chunk mesh — the ember parents here so it unloads with
	                     the chunk (per-chunk parenting rule).
	@param block_batch / block_body: The chunk's visual batch + collision body.
	"""
	var base_angle := rng.randf_range(0.0, TAU)
	var i := 0
	while i < CAMP_FIRE_STONES:
		# Even spacing round the ring plus a nudge, so it looks laid by hand.
		var a := base_angle + TAU * float(i) / float(CAMP_FIRE_STONES) + rng.randf_range(-0.15, 0.15)
		var r := CAMP_FIRE_RING_RADIUS + rng.randf_range(-0.12, 0.12)
		var pos := center + Vector3(cos(a) * r, CAMP_FIRE_STONE_SIZE.y / 2.0, sin(a) * r)
		create_box(pos, CAMP_FIRE_STONE_SIZE, rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_STONE, false)
		i += 1

	# The one ember. Sits just clear of the ground so it never z-fights the plane.
	_spawn_artifact_accent(parent_chunk, center + Vector3(0.0, CAMP_EMBER_SIZE.y / 2.0 + 0.05, 0.0), CAMP_EMBER_SIZE, rng.randf_range(0.0, TAU), 0.0, _get_camp_ember_material())

func _camp_props(center: Vector3, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, huts: Array) -> void:
	"""
	Scatter the lived-in clutter on a jittered ring between the fire and the huts:
	a few weathered crates/bundles and 2-3 tall thin tether posts (where the pack
	beasts would be tied). Both are solid — they are knee-to-chest height, so they
	keep their collision and you walk around them like any block.

	@param center: Camp centre (chunk-local, y = 0); the ring is measured from here.
	@param rng: The camp's private RNG.
	@param block_batch / block_body: The chunk's visual batch + collision body.
	@param huts: The huts already built ({ "pos", "radius" }), so a prop never ends
	             up buried in a wall — see _camp_spot_clear.

	A candidate that lands in a hut is DROPPED, not retried: the counts are pure
	ambience, and one crate fewer reads better than a loop that can still fail.

	EACH ACCEPTED PROP JOINS THE TEST LIST. Testing only against the huts was the
	same bug one scale down: 3-6 crates and 2-3 posts share ONE 2.0-4.0 m ring, so
	two crates land within a crate's width of each other often — measured a third of
	camps had an interpenetrating solid pair, and both crates and posts collide, so
	it was a merged blob the player walked into.

	DETERMINISM, HONESTLY: a drop does NOT consume the same draws as a placement —
	it skips create_box's yaw argument plus its colour selector, ramp and discarded
	roughness draws (and a dropped hut skips the whole of _camp_hut). That is
	harmless ONLY because this rng is private to the camp and the placement/rarity
	streams are decided before any geometry is drawn. Never lift this drop-mid-build
	pattern onto a shared chunk stream.
	"""
	# huts is the caller's list — copy it, so growing it here can never leak a prop
	# into the hut footprints the caller still holds.
	var solids: Array = huts.duplicate()

	var crates := rng.randi_range(CAMP_CRATE_MIN, CAMP_CRATE_MAX)
	var i := 0
	while i < crates:
		i += 1
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(CAMP_PROP_RING_MIN, CAMP_PROP_RING_MAX)
		# Cubes, not slabs: one size draw keeps a crate reading as a crate.
		var s := rng.randf_range(CAMP_CRATE_SIZE_MIN, CAMP_CRATE_SIZE_MAX)
		var pos := center + Vector3(cos(a) * r, s / 2.0, sin(a) * r)
		var crate_radius := s * 0.71
		if not _camp_spot_clear(pos, crate_radius, solids):
			continue
		create_box(pos, Vector3(s, s, s), rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_WOOD)
		solids.append({ "pos": pos, "radius": crate_radius })

	var posts := rng.randi_range(CAMP_POST_MIN, CAMP_POST_MAX)
	i = 0
	while i < posts:
		i += 1
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(CAMP_PROP_RING_MIN, CAMP_PROP_RING_MAX)
		var pos := center + Vector3(cos(a) * r, CAMP_POST_SIZE.y / 2.0, sin(a) * r)
		var post_radius := CAMP_POST_SIZE.x * 0.71
		if not _camp_spot_clear(pos, post_radius, solids):
			continue
		create_box(pos, CAMP_POST_SIZE, rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_WOOD)
		solids.append({ "pos": pos, "radius": post_radius })

func _camp_spot_clear(pos: Vector3, radius: float, solids: Array) -> bool:
	"""
	True when a `radius` circle at `pos` clears every solid thing built so far
	({ "pos", "radius" } records). It is the camp's ONE overlap rule, and every
	solid the camp builds is judged by it against everything solid before it:

	- PROPS vs PROPS: 3-6 crates and 2-3 posts all sit on the same 2.0-4.0 m ring,
	  so without this a third of camps had at least one interpenetrating pair.
	- PROPS vs huts: the prop ring (CAMP_PROP_RING_*) and the hut ring
	  (CAMP_HUT_RING_*) touch at 4 m, but a hut is up to 2.9 m of radius around ITS
	  ring position, so its stone reaches inward to ~1.1 m — well into the prop
	  band. Without this test roughly a fifth of all props spawned inside a hut
	  wall, and props collide, so the player bumped geometry they could not see.
	- HUTS vs each other: the ring radius is drawn PER HUT over a 2.5 m range and
	  the angle is jittered, so evenly-spaced slots are no guarantee. At
	  CAMP_HUT_MAX (6) the nominal step is TAU/6 = 1.047 rad and the ±0.25 jitter
	  can shrink an adjacent gap to 0.547 rad; two huts both at CAMP_HUT_RING_MIN
	  are then 2 * 4.0 * sin(0.547/2) = 2.16 m apart while their radii sum to at
	  least 4.29 m. Measured over 163 camps with the roll forced to 1.0 BEFORE this
	  test existed: 38% of camps had a pair of fused, interpenetrating domes — 35 of
	  36 six-hut camps and half of the five-hut ones. Both huts collide, so that was
	  a merged, unreadable blob the player walked into. After: 0 of 175.
	"""
	for other in solids:
		if Vector2(pos.x - other.pos.x, pos.z - other.pos.z).length() < other.radius + radius:
			return false
	return true

func spawn_camp_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's nomad camp, if _camp_at says it has one. Called from
	create_chunk AFTER spawn_biome_content_in_chunk and BEFORE
	_build_block_multimesh / the block_body attach, so every hut, stone, crate and
	post joins the chunk's SINGLE MultiMesh draw call and its SINGLE
	BlockCollision body — a whole village costs one extra draw call (the ember)
	and zero extra physics bodies.

	That ordering is also WHY the camp's candidate-spot loop lives here rather
	than in _camp_at: by this point the chunk's scattered blocks, feature
	structure, artifact and biome geometry are all in `obstacles`, so every try
	can be judged against the test that actually rejects (see _camp_at's docstring
	for the measurement that moved it).

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — the ember and the camp's coins parent
	                     here (per-chunk parenting rule: they unload with it).
	@param obstacles: The chunk's block-footprint list. Read to place the camp,
	                  then extended with ONE round footprint over the whole
	                  village, which is what keeps crocodiles out — see the bottom.
	@param block_batch / block_body: The chunk's visual batch + collision body.
	"""
	if not spawn_camps:
		return
	var camp := _camp_at(chunk_pos)
	if camp.is_empty():
		return

	# The camp's OWN RNG, seeded by _camp_at's "seed" draw: it picks the spot AND
	# feeds every builder, so each consumes as many draws as it needs without the
	# placement roll (or any other stream) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = camp.seed

	var chunk_center := chunk_to_world(chunk_pos)
	# Candidates stay CAMP_EDGE_MARGIN (> CAMP_RADIUS) inside the chunk so the
	# whole village fits in one chunk and never straddles a seam.
	var half := chunk_size / 2.0 - CAMP_EDGE_MARGIN

	# Try a few spots; accept the FIRST that clears _biome_spot_ok — the single
	# home of the "would something solid here spoil what is already there?" rule,
	# covering river + road clearance + overlap with everything already placed in
	# one call. The road half of it is also the BOSS exclusion, see
	# CAMP_ROAD_CLEARANCE. Bailing after every try is deliberate: a camp shoved
	# through a mountain massif reads far worse than a chunk with no camp, and
	# camps are ambience — nothing downstream expects one to exist.
	var center := Vector3.ZERO
	var placed := false
	var tries := 0
	while tries < CAMP_PLACE_TRIES and not placed:
		tries += 1
		center = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		placed = _biome_spot_ok(chunk_center, center.x, center.z, CAMP_RADIUS, CAMP_ROAD_CLEARANCE, obstacles)
	if not placed:
		return

	# 1. The fire pit at the camp's heart — built first because everything else is
	# arranged around it (the huts face it, the props ring it).
	_camp_fire_pit(center, rng, parent_chunk, block_batch, block_body)

	# 2. The huts, on a jittered ring around the fire. Angles are evenly spread and
	# then nudged, so the circle reads as pitched by people rather than stamped by
	# a compass, and each hut is yawed so its doorway (+Z, see _camp_hut) points at
	# the flames.
	var hut_count := rng.randi_range(CAMP_HUT_MIN, CAMP_HUT_MAX)
	var base_angle := rng.randf_range(0.0, TAU)
	var hut_footprints: Array = []
	var camp_top := 0.0
	var h := 0
	while h < hut_count:
		var a := base_angle + TAU * float(h) / float(hut_count) + rng.randf_range(-0.25, 0.25)
		var r := rng.randf_range(CAMP_HUT_RING_MIN, CAMP_HUT_RING_MAX)
		var hut_center := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		h += 1
		# A hut that would grow through a neighbour is DROPPED, same rule as the
		# props below: an evenly-spaced slot is no guarantee once the ring radius is
		# drawn per hut and the angle is jittered (see _camp_spot_clear for the
		# arithmetic). The test uses CAMP_HUT_WIDTH_MAX because _camp_hut draws the
		# real width itself — testing conservatively costs a hut now and then, which
		# is cheaper than a rebuilt one and reads as a village pitched around what
		# fits. A camp is 3-6 huts MINUS these drops — measured 3.7 built on
		# average, and 6-hut camps now land as 4s and 5s.
		if not _camp_spot_clear(hut_center, CAMP_HUT_WIDTH_MAX * 0.71 + 0.3, hut_footprints):
			continue
		# Point the hut's local +Z back at the fire: Basis(UP, yaw) * (0,0,1) is
		# (sin yaw, 0, cos yaw), and we want that to equal -(cos a, sin a).
		var yaw := atan2(-cos(a), -sin(a))
		var footprint := _camp_hut(hut_center, yaw, rng, block_batch, block_body)
		# Only "pos"/"radius" — this list never reaches `obstacles` (see step 5), so
		# the "top"/"climbable" an obstacle record carries would be read by nothing.
		hut_footprints.append({ "pos": hut_center, "radius": footprint.radius })
		camp_top = maxf(camp_top, footprint.top)

	# 3. The lived-in clutter, on its own tighter ring between fire and huts. The
	# huts go in FIRST so the props can be tested against them: the two rings
	# touch, and a hut is nearly 3 m of radius around its ring position.
	_camp_props(center, rng, block_batch, block_body, hut_footprints)

	# 4. A couple of scattered coins by the fire — a small "someone lives here"
	# reward, NOT a treasure haul. There is deliberately NO GEM: the guaranteed gem
	# is the ARTIFACTS' distinction (see spawn_artifact_in_chunk), and giving camps
	# one too would flatten the difference between "an ancient prize worth a detour"
	# and "a village you happened to walk through".
	#
	# These are ordinary chunk-local coins parented to the chunk. They CANNOT
	# collide with the road's station-claim logic: a camp centre is at least
	# CAMP_ROAD_CLEARANCE (22 m) from the road centerline while the widest scatter
	# band reaches road_width_max / 2 (10 m) plus ROAD_COIN_LONG_JITTER, so the two
	# coin populations never share ground — no double-claim, no gap.
	#
	# ORDER MATTERS, exactly as for the artifact reward: these settle through
	# _settle_coin_y BEFORE the camp's own footprint is appended below. Settling
	# after would meet a non-climbable CAMP_RADIUS circle covering the whole
	# village and skip every single coin.
	if spawn_coins and coin_scene != null:
		var coin_count := rng.randi_range(CAMP_COIN_MIN, CAMP_COIN_MAX)
		var c := 0
		while c < coin_count:
			c += 1
			var a := rng.randf_range(0.0, TAU)
			# Just outside the fire stones (CAMP_FIRE_RING_RADIUS) and inside the
			# prop RING (CAMP_PROP_RING_MIN). That compares ring centres, so it is
			# not a guarantee: a crate's own half-diagonal reaches inward to
			# 2.0 - 0.9 * 0.71 = 1.36 m, under the coin band's 1.9 m outer edge, and
			# ~2% of camp coins do land on a crate. Harmless, so deliberately not
			# tested: a crate is at most CAMP_CRATE_SIZE_MAX (0.9) tall, which is
			# exactly COIN_GROUND_HEIGHT, so the coin rests on the lid, and the
			# pickup sphere (0.6 m) far exceeds the crate's 0.45 m half-width, so it
			# stays collectible from any side.
			var r := CAMP_FIRE_RING_RADIUS + rng.randf_range(0.4, 0.8)
			var cx := center.x + cos(a) * r
			var cz := center.z + sin(a) * r
			# Same perch-or-skip rule as every other coin (one home).
			var cy := _settle_coin_y(cx, cz, COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin := coin_scene.instantiate()
			coin.position = Vector3(cx, cy, cz)
			parent_chunk.add_child(coin)

	# 5. ONE round footprint over the whole camp circle. THIS IS THE CROCODILE
	# EXCLUSION, and it needs no edit anywhere else: spawn_crocodiles_in_chunk
	# already rejects any spawn candidate within ob.radius + min_object_clearance of
	# a footprint, so a CAMP_RADIUS circle simply reads as "occupied" and the camp
	# stays the calm pocket it is meant to be — with NO EDIT to the crocodile
	# spawner. Its retry budget absorbs the rejections, so the croc COUNT is
	# unchanged; the positions are not. A rejected candidate skips the successful
	# spawn's `rotation.y` draw, so the rest of that chunk's crocodile stream
	# shifts — same as the river skip just above it. Harmless (within-run
	# determinism holds: the camp is a pure function of chunk coords + run_seed),
	# but do not read this as "camp chunks generate crocodiles byte-identically".
	# climbable = false: a road coin over a camp would be skipped rather than
	# perched on thin air. That cannot happen given CAMP_ROAD_CLEARANCE, but the
	# rule stays honest either way.
	# ONE circle is enough: CAMP_RADIUS is chosen to bound the widest hut on the
	# outermost ring (9.36 <= 9.4, see the constant), so per-hut footprints would
	# add 3-6 entries to a list every _settle_coin_y / _point_over_block call scans
	# and reject nothing the circle does not already reject. `hut_footprints` stays
	# a local, read by _camp_props above.
	obstacles.append({ "pos": center, "radius": CAMP_RADIUS, "top": camp_top, "climbable": false })

# ============================================================================
# TREASURE CHESTS (see the TREASURE CHESTS constant banner)
# ============================================================================

func _chest_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic treasure-chest placement for one chunk — _artifact_at / _camp_at
	for chests, same shape, same guarantees. Pure function of chunk coords +
	run_seed via the independent CHEST_SALT hash stream, so it consumes NO draw
	from the shared chunk RNG: every block, crocodile and coin the generator
	produced before chests existed is still exactly where it was.

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when this chunk rolled no chest (the ~12-in-13 case); otherwise
	         { "seed": int } — the seed for the chest's private RNG, which
	         spawn_chest_in_chunk uses for placement, geometry and payout.

	WHY THERE IS NO CANDIDATE LOOP HERE. This is the landmine both artifacts and
	camps had to be dug out of, and it is worth restating rather than cross-
	referencing: when this function runs the chunk has NO GEOMETRY YET. The only
	tests available are river and road, and neither rejects the thing that actually
	matters — overlap with the chunk's ~12 scattered blocks and its feature
	structure. Camps measured 11 rejections in 121 chunks from river+road alone,
	then ~9% survival once the real test was applied where it belongs, landing
	camps ~10x rarer than the constant said. So the CHEST_PLACE_TRIES loop lives in
	spawn_chest_in_chunk, where `obstacles` exists, and this function does exactly
	one thing: roll.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL chest (same spot, same lid
	  angle, same payout) however often it unloads and regenerates: the RNG is
	  seeded purely from chunk coords + run_seed, and every draw downstream comes
	  off that one stream in a fixed order.
	- Across runs, new_run() re-rolls run_seed, so chests land elsewhere.
	- Whether a candidate is ACCEPTED is likewise load-order independent: the road
	  test reads the station cache (pure in `k`), the river test reads the biome
	  field (pure in world position + run_seed) and the overlap test reads the
	  chunk's own obstacle list (pure in chunk coords + run_seed).
	"""
	var rng := RandomNumberGenerator.new()
	# Own coordinate primes AND own salt — see the CHEST_HASH_PRIME_* constants for
	# why they differ from every other stream in this file.
	rng.seed = hash(Vector3i(chunk_pos.x * CHEST_HASH_PRIME_X, chunk_pos.y * CHEST_HASH_PRIME_Y, run_seed ^ CHEST_SALT))

	# The rarity roll — most chunks bail here, and this is the ONLY draw taken from
	# the stream at this point. The rest happen in spawn_chest_in_chunk off an RNG
	# re-seeded from `seed`, so the two together stay one fixed sequence per chunk.
	if rng.randf() >= CHEST_CHANCE:
		return {}

	return { "seed": rng.randi() }


func spawn_chest_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's treasure chest, if _chest_at says it has one. Called from
	create_chunk AFTER spawn_biome_content_in_chunk / spawn_camp_in_chunk and
	BEFORE _build_block_multimesh + the block_body attach, so the chest's wood and
	brass join the chunk's SINGLE MultiMesh draw call and its SINGLE BlockCollision
	body — a chest costs ZERO extra draw calls and ZERO extra physics bodies. Its
	one non-batched node is the open trigger (treasure_chest.gd), which has no mesh.

	That ordering is also WHY the candidate loop lives here rather than in
	_chest_at: by this point the chunk's scattered blocks, feature structure,
	artifact, biome geometry and camp are all in `obstacles`, so every try is judged
	against the test that actually rejects.

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — the trigger parents here (per-chunk
	                     parenting rule: it unloads with the chunk, which is also
	                     what makes a chest regenerate closed; see the banner).
	@param obstacles: The chunk's footprint list. READ to place the chest, then
	                  appended to with the chest's own small climbable footprint.
	@param block_batch / block_body: The chunk's visual batch + collision body.
	"""
	if not spawn_chests:
		return
	var chest := _chest_at(chunk_pos)
	if chest.is_empty():
		return

	# The chest's OWN RNG, seeded by _chest_at's roll: it picks the spot AND feeds
	# the geometry AND draws the payout, so each consumes as many draws as it needs
	# without the rarity roll (or any other stream) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = chest.seed

	var chunk_center := chunk_to_world(chunk_pos)
	# Candidates stay CHEST_EDGE_MARGIN (> CHEST_RADIUS, and > the trigger radius)
	# inside the chunk, so neither the box nor its pickup sphere straddles a seam.
	var half := chunk_size / 2.0 - CHEST_EDGE_MARGIN

	# Try a few spots; accept the FIRST that clears _biome_spot_ok — the single home
	# of the river + road-clearance + overlap rule. The road half is what keeps
	# chests off the coin swath (see CHEST_ROAD_CLEARANCE); the overlap half is what
	# stops one appearing half-swallowed by a wall. Bailing after every try is
	# deliberate and matches artifacts and camps: nothing downstream expects a chest.
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < CHEST_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if _biome_spot_ok(chunk_center, local_x, local_z, CHEST_RADIUS, CHEST_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	var center := Vector3(local_x, 0.0, local_z)
	var yaw := rng.randf_range(0.0, TAU)

	# --- The box itself. All three parts go through create_box, so all three land
	# in the chunk's one MultiMesh; only the body carries collision.
	# The body sits ON the ground: centre at half its height.
	create_box(center + Vector3(0.0, CHEST_BODY_SIZE.y / 2.0, 0.0), CHEST_BODY_SIZE, yaw, rng, block_batch, block_body, 0.0, CHEST_WOOD)

	# The brass band across the waist — collide = false, exactly like a tree canopy
	# or a camp fire stone: it is 6 cm of trim sitting inside the body's own
	# collision box, so a shape for it would be pure cost.
	create_box(center + Vector3(0.0, CHEST_BODY_SIZE.y * 0.55, 0.0), CHEST_BAND_SIZE, yaw, rng, block_batch, block_body, 0.0, CHEST_BRASS, false)

	# The lid, TILTED OPEN. This is the same `tilt` parameter the artifacts' leaning
	# monolith uses, and create_box applies it identically to the visual basis and to
	# the CollisionShape3D transform, so the lid you see is the lid you bump into.
	#
	# THE LID IS HINGED, NOT JUST TILTED, and the difference is visible. create_box
	# rotates a box about its own CENTRE, so simply tilting a lid parked on the rim
	# drives its rear half straight down through the body — at the widest angle here
	# the back corner would sink 0.25 m into a 0.75 m box, reading as a lid melting
	# into the chest rather than opening. So we place the centre where a lid hinged
	# on the REAR RIM would actually end up: take the hinge at (0, body top, -half
	# depth), and rotate the lid's rest offset from that hinge, (0, +half height,
	# +half depth), by the same angle. Three lines of trig, and the lid pivots.
	#
	# Sign: Basis(RIGHT, t) sends z toward -y, so a POSITIVE tilt would push the
	# FRONT edge down. The lid opens with a negative tilt and `theta` below is the
	# positive open angle.
	var theta := rng.randf_range(CHEST_LID_TILT_MIN, CHEST_LID_TILT_MAX)
	var hy := CHEST_LID_SIZE.y * 0.5
	var hz := CHEST_LID_SIZE.z * 0.5
	var lid_local := Vector3(
		0.0,
		CHEST_BODY_SIZE.y + hy * cos(theta) + hz * sin(theta),
		-hz - hy * sin(theta) + hz * cos(theta)
	)
	create_box(center + Basis(Vector3.UP, yaw) * lid_local, CHEST_LID_SIZE, yaw, rng, block_batch, block_body, -theta, CHEST_WOOD)

	# --- The open trigger: the chest's ONE non-batched node. No mesh, no material,
	# so the F3 overlay's draw-call count does not move. Parented to the chunk like
	# every other per-chunk node, so it frees with the chunk.
	#
	# The payout count is drawn from the chest's own RNG, so two visits to the same
	# chunk in one run find the same chest holding the same number of coins.
	var coin_count := rng.randi_range(CHEST_COINS_MIN, CHEST_COINS_MAX)
	var trigger := Area3D.new()
	trigger.name = "TreasureChest"
	trigger.set_script(TREASURE_CHEST_SCRIPT)
	# Centred on the box so the sphere reaches equally from every side.
	trigger.position = center + Vector3(0.0, CHEST_BODY_SIZE.y / 2.0, 0.0)
	parent_chunk.add_child(trigger)
	# setup() AFTER add_child, per treasure_chest.gd's contract (it builds its own
	# CollisionShape3D child and connects its own signal there) — the same
	# add-then-setup shape ability_effect.gd uses.
	trigger.setup(coin_count, CHEST_BURST_DURATION)

	# --- One small CLIMBABLE footprint. Climbable is the right call for a 1 m box:
	# a road coin whose column crosses it perches on the lid (reachable, and a nice
	# accident) instead of being skipped, which is what a non-climbable footprint
	# would do — that rule exists for trees and cacti, where the top is 5 m up in a
	# canopy. Crocodiles reject spawn candidates inside the footprint either way, so
	# a chest is never found already occupied by a crocodile standing in it.
	#
	# MEASURED (same sweep, 17x17 chunks with every spawner on, chests on vs off):
	# the only chunks whose block MultiMesh changed are the 20 that actually built a
	# chest, and NOT ONE crocodile or coin moved anywhere — 289/289 chunks identical
	# on both. That is stronger than camps manage (a 9.4 m camp circle does shift the
	# croc stream), because a 1.5 m circle plus min_object_clearance is a 3 m disc in
	# a 50 m chunk and the croc spawner's retry budget never had to touch it here.
	# The mechanism still exists in principle — a rejected croc candidate skips the
	# successful spawn's rotation.y draw — so do not read this as a guarantee, only
	# as "this footprint is small enough that it did not fire". Within-run
	# determinism holds unconditionally either way (the chest is a pure function of
	# chunk coords + run_seed): the same sweep regenerated 289 chunks twice and got
	# byte-identical blocks, crocodiles, coins and chest spots both times.
	#
	# MULTIPLAYER (phase 1, known and accepted): opening is per-peer and local — the
	# trigger fires for whoever walks into their OWN copy, and a chest one peer has
	# opened still stands closed for another. Contested-chest arbitration belongs to
	# the same claim machinery the epic defers for coins (godot-test1-s86.5).
	obstacles.append({ "pos": center, "radius": CHEST_RADIUS, "top": CHEST_BODY_SIZE.y, "climbable": true })

# ============================================================================
# GEO LANDMARKS (see the GEO LANDMARKS constant banner)
# ============================================================================

func _landmark_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic geo-landmark placement for one chunk — _chest_at / _camp_at /
	_artifact_at for famous places, same shape, same guarantees. Pure function of
	chunk coords + run_seed via the independent LANDMARK_SALT hash stream, so it
	consumes NO draw from the shared chunk RNG: every block, crocodile and coin the
	generator produced before landmarks existed is still exactly where it was in
	every chunk that does not build one.

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when this chunk rolled no landmark (the overwhelming majority);
	         otherwise { "seed": int, "kind": int } — the seed for the landmark's
	         private RNG (spawn_landmark_in_chunk uses it for placement, geometry
	         and the coin ring) and the index into LANDMARKS of WHICH famous place
	         this is.

	WHY THERE IS NO CANDIDATE LOOP HERE. This is the landmine that BOTH artifacts
	and camps had to be dug out of, and it is worth restating rather than cross-
	referencing, because the next person to add a landmark family member will reach
	for it again: when this function runs, THE CHUNK HAS NO GEOMETRY YET. The only
	tests available are river and road, and neither rejects the thing that actually
	matters — overlap with the chunk's ~12 scattered blocks, its feature structure,
	its biome trees and massifs, its artifact and its camp. Camps measured 11
	rejections in 121 chunks from river+road alone, i.e. ~91% of rolled camps
	"survived" a test that checked nothing, and then ~9% survived once the real
	test was applied where it belongs — landing camps roughly 10x rarer than the
	constant said, with no error anywhere. So the LANDMARK_PLACE_TRIES loop lives
	in spawn_landmark_in_chunk, where `obstacles` exists, and this function does
	exactly two things: roll whether, and roll which.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL landmark (same place, same
	  spot, same stone jitter, same coin ring) however often it unloads and
	  regenerates: the RNG is seeded purely from chunk coords + run_seed, and every
	  draw downstream comes off that one stream in a fixed order.
	- Across runs, new_run() re-rolls run_seed, so a new world puts different
	  places in different chunks.
	- MULTIPLAYER NEEDS ZERO WORK because of exactly that: run_seed is already
	  shared by every peer in a room, so every peer generates the same landmark in
	  the same chunk by construction. No packet, no claim, no sync.
	- Whether a candidate is ACCEPTED is likewise load-order independent: the road
	  test reads the station cache (pure in `k`), the river test reads the biome
	  field (pure in world position + run_seed) and the overlap test reads the
	  chunk's own obstacle list (pure in chunk coords + run_seed).
	"""
	var rng := RandomNumberGenerator.new()
	# Own coordinate primes AND own salt — see the LANDMARK_HASH_PRIME_* constants
	# for why they differ from every other stream in this file.
	rng.seed = hash(Vector3i(chunk_pos.x * LANDMARK_HASH_PRIME_X, chunk_pos.y * LANDMARK_HASH_PRIME_Y, run_seed ^ LANDMARK_SALT))

	# The rarity roll — almost every chunk bails here, and this is the ONLY draw
	# taken from the stream at this point. The rest happen in
	# spawn_landmark_in_chunk off an RNG re-seeded from `seed`, so the two together
	# stay one fixed sequence per chunk.
	if rng.randf() >= LANDMARK_CHANCE:
		return {}

	# WHICH place. Drawn here rather than in the spawner so the kind is decided by
	# the same pure function as the rarity: a chunk's landmark identity is known
	# without building anything, which is what lets the measurement sweep report a
	# per-kind distribution over a field it never renders.
	#
	# UNIFORM OVER THE WHOLE REGISTRY, and deliberately expressed as
	# `LandmarkBuilders.LANDMARKS.size()` rather than a number: appending places to
	# the registry widens this draw for free and keeps every kind equally likely,
	# which is the only property the rarity story rests on (the BUILT rate is set by
	# LANDMARK_CHANCE and the candidate loop, and is completely independent of how
	# many kinds there are — adding ten places makes each one rarer without making
	# landmarks as a whole any rarer).
	var kind := rng.randi_range(0, LandmarkBuilders.LANDMARKS.size() - 1)

	return { "seed": rng.randi(), "kind": kind }



func spawn_landmark_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's geo landmark, if _landmark_at says it has one, plus its coin
	ring and its marker node. Called from create_chunk AFTER spawn_camp_in_chunk and
	BEFORE spawn_chest_in_chunk (and therefore before _build_block_multimesh + the
	block_body attach), so every box the builder emits joins the chunk's SINGLE
	MultiMesh draw call and SINGLE BlockCollision body — a whole Eiffel Tower costs
	zero extra draw calls and zero extra physics bodies.

	That ordering is also WHY the candidate loop lives here rather than in
	_landmark_at: by this point the chunk's scattered blocks, feature structure,
	artifact, biome geometry and camp are all in `obstacles`, so every try is judged
	against the test that actually rejects. Both artifacts and camps had to have
	that loop dug back OUT of their roll for exactly this reason.

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — the reward coins, any emissive accent and
	                     the marker Node3D parent here (per-chunk parenting rule:
	                     they are freed automatically when the chunk unloads, so
	                     there is no registry to keep in step and nothing to leak).
	@param obstacles: The chunk's footprint list. READ to place the landmark, then
	                  appended to with the landmark's own single footprint.
	@param block_batch / block_body: The chunk's visual batch + collision body,
	                                 threaded through to create_box.
	"""
	if not spawn_landmarks:
		return
	var lm := _landmark_at(chunk_pos)
	if lm.is_empty():
		return

	# The landmark's OWN private RNG, seeded from _landmark_at's roll: it picks the
	# spot AND feeds the builder AND draws the coin ring, so each consumes as many
	# draws as it needs without the rarity roll (or any other stream) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = lm.seed

	var chunk_center := chunk_to_world(chunk_pos)
	# Candidates stay LANDMARK_EDGE_MARGIN (12 > LANDMARK_RADIUS 9.5) inside the
	# chunk, so nothing the builder emits straddles a seam.
	var half := chunk_size / 2.0 - LANDMARK_EDGE_MARGIN

	# Try a few spots; accept the FIRST that clears _biome_spot_ok — the single home
	# of the river + road-clearance + overlap rule (do not write a second copy). The
	# road half is what makes a landmark an off-road DESTINATION rather than
	# something you trip over on the trail; the overlap half is what keeps the
	# silhouette readable.
	#
	# EVERY TRY FAILING MEANS NO LANDMARK — the same call artifacts and camps both
	# make, and the right one here too: the Eiffel Tower sticking out of a mountain
	# massif reads far worse than a chunk without one, and a higher LANDMARK_CHANCE
	# reaches the same built rate. LANDMARK_RADIUS is handed over as "the widest this
	# could be", because the shape's real radius is only known after its builder has
	# run (the house rule every sibling spawner follows).
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < LANDMARK_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if _biome_spot_ok(chunk_center, local_x, local_z, LANDMARK_RADIUS, LANDMARK_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	var center := Vector3(local_x, 0.0, local_z)

	# --- Build it. The registry is pure data (and lives with its builders in
	# scripts/landmark_builders.gd), so the dispatch is one call() on a method-name
	# String and adding a famous place touches no code here at all. `builder` being
	# a String rather than a Callable is what lets LANDMARKS be a `const`; the cost
	# is that a typo'd method name is caught at call time, which is why
	# landmark_selfcheck.gd calls every builder in the table.
	#
	# `self` is passed as the builder's first argument because the builders are
	# STATIC on LandmarkBuilders: they hold no state, they only need this terrain's
	# create_box / _spawn_artifact_accent. Object.call() dispatches a GDScript
	# static method exactly as it dispatched these when they were methods here.
	var entry: Dictionary = LandmarkBuilders.LANDMARKS[lm.kind]
	var footprint: Dictionary = _landmark_builders.call(entry.builder, self, center, rng, parent_chunk, block_batch, block_body)

	# --- The reward: a small ring of ordinary coins round the base, and
	# DELIBERATELY NO GEM (the guaranteed gem stays the artifacts' distinction — see
	# the REWARD DECISION in the constant banner). These are ordinary chunk-local
	# coins parented to the chunk; the road's station-claim logic is not involved.
	#
	# ORDER MATTERS, and this is the same ordering gotcha artifacts and camps both
	# carry: the landmark's own footprint is appended to `obstacles` only AFTER these
	# coins are settled. That footprint is a CIRCLE with a `top`, but Stonehenge, the
	# Plaza Mayor and the Golden Gate are mostly HOLLOW — settling their reward coins
	# against that circle would perch them on the silhouette top, i.e. floating
	# several metres up in open air over an empty middle. Settling first means they
	# meet only real block stone and land where the player can actually pick them up.
	if spawn_coins and coin_scene != null:
		var coin_count := rng.randi_range(LANDMARK_COIN_MIN, LANDMARK_COIN_MAX)
		var ring_radius: float = footprint.radius + rng.randf_range(LANDMARK_COIN_RING_PAD_MIN, LANDMARK_COIN_RING_PAD_MAX)
		var i := 0
		while i < coin_count:
			i += 1
			var a := rng.randf_range(0.0, TAU)
			var cx := center.x + cos(a) * ring_radius
			var cz := center.z + sin(a) * ring_radius
			# Same perch-or-skip rule as road coins (one home: _settle_coin_y): the
			# ring can graze a neighbouring block, so a coin perches on a climbable
			# top or is dropped under a sheer wall.
			var cy := _settle_coin_y(cx, cz, COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin := coin_scene.instantiate()
			coin.position = Vector3(cx, cy, cz)
			parent_chunk.add_child(coin)

	# --- The marker: the landmark's only other non-batched node, and it has no mesh,
	# no script and no physics — a bare Node3D costs ZERO draw calls and ZERO
	# physics. It exists so scripts/landmark_toast.gd can find landmarks the way
	# EVERY other system in this project finds things: BY GROUP, never by reference
	# (CLAUDE.md "Node discovery is group-based"). Parenting it to the chunk means it
	# is freed automatically when the chunk unloads, so there is no registry to keep
	# in step, nothing to leak, and a landmark that streams back in re-registers
	# itself for free.
	#
	# The four metas are the whole contract with the toast: the English name and
	# fact (which ARE the translation keys — CLAUDE.md Localization RULE 1), the
	# shape's real radius, so the toast can measure "within ~15 m of the STONE"
	# rather than "within 15 m of a point" and a small statue and a wide plaza both
	# trigger where they look like they should, and the REGISTRY INDEX — which is
	# what lets the toast ask LandmarkBuilders.quiz_options() for two plausible
	# wrong answers. The index is carried rather than re-derived because the name
	# is a translation key, not an identity: looking the row up by name would break
	# the moment two places shared one.
	var marker := Node3D.new()
	marker.name = "LandmarkMarker"
	marker.position = center
	marker.add_to_group("landmark")
	marker.set_meta("name_key", entry.name)
	marker.set_meta("fact_key", entry.fact)
	marker.set_meta("radius", footprint.radius)
	marker.set_meta("kind", lm.kind)
	parent_chunk.add_child(marker)

	# --- ONE round footprint, and it is NON-CLIMBABLE, unlike a chest's. These are
	# 5-18 m tall, so a road coin perched on the "top" of the circle would float
	# unreachably high — the same call the tree/canopy and cactus footprints make.
	# _settle_coin_y therefore SKIPS a road coin whose column crosses a landmark
	# instead of stranding it in the sky.
	#
	# This single footprint IS the crocodile exclusion: spawn_crocodiles_in_chunk
	# already rejects candidates within ob.radius + min_object_clearance of a
	# footprint, so a landmark reads as a calm pocket with NO EDIT to the crocodile
	# spawner. Known consequence, exactly as camps document it: the croc COUNT is
	# unchanged (the retry budget absorbs the rejections) but the croc POSITIONS in a
	# landmark chunk DO shift, because a rejected candidate skips the successful
	# spawn's rotation.y draw and shifts the rest of that chunk's croc stream.
	# Within-run determinism still holds unconditionally — the footprint is a pure
	# function of chunk coords + run_seed.
	#
	# ponytail: one circle + one top is the whole footprint vocabulary the coin and
	# crocodile rules speak, so a hollow landmark reserves its empty middle too. That
	# errs toward "no coin here" rather than "a coin buried in stone", which is the
	# failure the rule exists to prevent; if it ever looks wrong, give the footprint
	# a per-shape solid-centre height rather than a richer vocabulary.
	obstacles.append({ "pos": center, "radius": footprint.radius, "top": footprint.top, "climbable": false })
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

func _oasis_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic oasis placement for one desert chunk — the pattern of _artifact_at
	/ _camp_at applied to rare water features. Pure function of chunk coords + run_seed
	on its own independent hash stream (OASIS_SALT): consumes NO draw from the shared
	biome RNG, so every existing cactus/dune is exactly where it was before oases existed.

	@return: {} when this chunk has no oasis (the common case); otherwise { "seed": int }
	         used by _spawn_desert_oasis for placement and geometry.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ OASIS_SALT))

	if rng.randf() >= OASIS_CHANCE:
		return {}

	return { "seed": rng.randi() }

func _dune_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic sand dune placement for one desert chunk — same split-placement
	pattern as oases, with its own independent DUNE_SALT hash stream.

	@return: {} when this chunk has no dunes; otherwise { "seed": int } for dune RNG.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ DUNE_SALT))

	if rng.randf() >= DUNE_CHANCE:
		return {}

	return { "seed": rng.randi() }

func spawn_biome_content_in_chunk(chunk_pos: Vector2i, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	if not spawn_biome_content:
		return

	# Own stream. Different coordinate multipliers than the chunk-object /
	# artifact streams (which both use 73856093 / 19349663) so the two hash
	# sequences never correlate — biome content and artifacts must not agree
	# about where "interesting" spots are.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(chunk_pos.x * 83492791, chunk_pos.y * 15485863, run_seed ^ BIOME_SALT))

	var center := chunk_to_world(chunk_pos)
	match biome_at(center.x, center.z):
		Biome.DESERT:
			_spawn_desert_content(center, rng, obstacles, block_batch, block_body)
		Biome.FOREST:
			_spawn_forest_content(center, rng, obstacles, block_batch, block_body)
		Biome.MOUNTAIN:
			_spawn_mountain_content(center, rng, obstacles, block_batch, block_body)
		Biome.CITY:
			_spawn_city_content(center, rng, obstacles, block_batch, block_body)
		Biome.SNOW:
			_spawn_snow_content(center, rng, obstacles, block_batch, block_body)
		_:
			# PLAINS is the baseline look — the ordinary scattered blocks ARE its
			# content, so it deliberately builds nothing extra here.
			pass


func _biome_spot_ok(chunk_center: Vector3, local_x: float, local_z: float, radius: float, road_clearance: float, obstacles: Array) -> bool:
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
	if is_river_at(Vector3(world_x, 0.0, world_z)):
		return false
	# The tower's site is kept clear of everything procedural (see TOWER_RADIUS).
	# Judged with the candidate's OWN radius — the same "widest this could be"
	# number the overlap test below uses — so the thing's whole footprint stays
	# outside the disc, not merely its centre.
	if tower_excludes(world_x, world_z, radius):
		return false
	if _road_lateral_distance(world_x, world_z, road_clearance) < road_clearance:
		return false
	for ob in obstacles:
		if Vector2(local_x - ob.pos.x, local_z - ob.pos.z).length() < radius + ob.radius:
			return false
	return true


func _spawn_desert_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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

	A cactus is 2-3 thin tall green boxes stacked, sometimes with one short arm box
	off to the side — enough silhouette to read at distance, four boxes at most.
	"""
	var half := chunk_size / 2.0 - 3.0
	var count := rng.randi_range(CACTUS_MIN, CACTUS_MAX)

	for _i in count:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)
		# Rejections are `continue`s AFTER the position draws, so a rejected cactus
		# costs a spot and not a shift in this (or any) RNG sequence.
		if not _biome_spot_ok(chunk_center, local_x, local_z, CACTUS_WIDTH_MAX * 1.2, CACTUS_ROAD_CLEARANCE, obstacles):
			continue
		# Edge feathering, same rule as the forest and the mountains: the chunk
		# CENTRE chose this builder, but each cactus re-tests the biome at its OWN
		# position, so the sand dissolves into the plain along the noise contour
		# instead of stopping dead on a straight chunk seam.
		if biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != Biome.DESERT:
			continue

		var width := rng.randf_range(CACTUS_WIDTH_MIN, CACTUS_WIDTH_MAX)
		var segments := rng.randi_range(2, 3)
		var yaw := rng.randf_range(0.0, TAU)
		var top_y := 0.0

		for _s in segments:
			var seg_h := rng.randf_range(CACTUS_SEGMENT_MIN, CACTUS_SEGMENT_MAX)
			create_box(
				Vector3(local_x, top_y + seg_h * 0.5, local_z),
				Vector3(width, seg_h, width),
				yaw, rng, block_batch, block_body, 0.0, CACTUS_COLOR
			)
			top_y += seg_h

		# Optional arm: a short horizontal box budding from the middle of the stack.
		if rng.randf() < CACTUS_ARM_CHANCE:
			var arm_len := width * rng.randf_range(2.0, 3.0)
			var arm_y := top_y * rng.randf_range(0.45, 0.7)
			# Push the arm out along its OWN long axis, which create_box orients with
			# Basis(UP, yaw) — that maps local +X to (cos yaw, 0, -sin yaw). Writing
			# the +sin form here rotates the offset the wrong way round, so the arm
			# gets shoved sideways instead of outwards and floats detached from the
			# trunk (worst at yaw = 45 deg, where the two are 90 deg apart).
			var arm_dir := (Basis(Vector3.UP, yaw) * Vector3.RIGHT) * (arm_len * 0.5 + width * 0.5)
			create_box(
				Vector3(local_x, arm_y, local_z) + arm_dir,
				Vector3(arm_len, width, width),
				yaw, rng, block_batch, block_body, 0.0, CACTUS_COLOR
			)

		# NOT climbable: a cactus is a thing you walk around, and a coin perched on
		# a spiky 3 m pole would be unreachable anyway (see _settle_coin_y).
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": width * 1.2, "top": top_y, "climbable": false })

	# Rare oases and dunes. Placements are deterministic on their own hash streams
	# (like artifacts/camps), so they consume zero draws from the biome RNG and
	# cacti are byte-identically placed whether oases/dunes exist or not.
	var chunk_pos := world_to_chunk(chunk_center)
	var oasis_data := _oasis_at(chunk_pos)
	if not oasis_data.is_empty():
		var oasis_rng := RandomNumberGenerator.new()
		oasis_rng.seed = oasis_data["seed"]
		_spawn_desert_oasis(chunk_center, chunk_pos, oasis_rng, obstacles, block_batch, block_body)

	var dune_data := _dune_at(chunk_pos)
	if not dune_data.is_empty():
		var dune_rng := RandomNumberGenerator.new()
		dune_rng.seed = dune_data["seed"]
		_spawn_desert_dunes(chunk_center, chunk_pos, dune_rng, obstacles, block_batch, block_body)


func _spawn_desert_oasis(chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build one desert oasis: a flat water slab, palm trees, reeds, and climbable boulders.
	Uses the split-placement pattern: this function tries OASIS_PLACE_TRIES candidates
	and picks the first one that passes _biome_spot_ok (not in river, far from road,
	no overlap with existing obstacles).
	"""
	var half := chunk_size / 2.0 - OASIS_RADIUS - 2.0
	for _try in OASIS_PLACE_TRIES:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)

		if not _biome_spot_ok(chunk_center, local_x, local_z, OASIS_RADIUS, OASIS_ROAD_CLEARANCE, obstacles):
			continue

		# Build water slab: a flat disk (visual only, collide=false)
		create_box(
			Vector3(local_x, OASIS_WATER_TOP_Y - OASIS_WATER_DEPTH * 0.5, local_z),
			Vector3(OASIS_WATER_RADIUS * 2.0, OASIS_WATER_DEPTH, OASIS_WATER_RADIUS * 2.0),
			0.0, rng, block_batch, block_body, 0.0, OASIS_WATER_COLOR, false
		)

		# Dark rim: a slightly wider ring to frame the water
		var rim_radius := OASIS_WATER_RADIUS * 1.15
		create_box(
			Vector3(local_x, OASIS_RIM_TOP_Y - OASIS_WATER_DEPTH * 0.5, local_z),
			Vector3(rim_radius * 2.0, OASIS_WATER_DEPTH, rim_radius * 2.0),
			0.0, rng, block_batch, block_body, 0.0, OASIS_WATER_RIM_COLOR, false
		)

		# Non-climbable footprint so coins don't perch on water
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": OASIS_RADIUS, "top": OASIS_WATER_TOP_Y, "climbable": false })

		# Palm trees around the oasis
		var palm_count := rng.randi_range(OASIS_PALM_MIN, OASIS_PALM_MAX)
		for _p in palm_count:
			var palm_angle := rng.randf_range(0.0, TAU)
			var palm_dist := rng.randf_range(OASIS_WATER_RADIUS * 1.15, OASIS_WATER_RADIUS * 2.0)
			var palm_x := local_x + cos(palm_angle) * palm_dist
			var palm_z := local_z + sin(palm_angle) * palm_dist

			# Keep palm within chunk bounds
			if absf(palm_x) > chunk_size * 0.5 - 2.0 or absf(palm_z) > chunk_size * 0.5 - 2.0:
				continue

			var trunk_yaw := rng.randf_range(0.0, TAU)
			# Trunk (colliding)
			create_box(
				Vector3(palm_x, OASIS_PALM_TRUNK_HEIGHT * 0.5, palm_z),
				Vector3(OASIS_PALM_TRUNK_WIDTH, OASIS_PALM_TRUNK_HEIGHT, OASIS_PALM_TRUNK_WIDTH),
				trunk_yaw, rng, block_batch, block_body, 0.0, Color(0.40, 0.32, 0.22)
			)

			# Fronds (visual only, collide=false) — 4 layers fanning out
			for _f in OASIS_PALM_FROND_COUNT:
				var frond_height := OASIS_PALM_TRUNK_HEIGHT - 0.5
				var frond_yaw := trunk_yaw + (TAU / OASIS_PALM_FROND_COUNT) * _f
				create_box(
					Vector3(palm_x, frond_height + 0.3, palm_z),
					Vector3(OASIS_PALM_FROND_WIDTH, 0.6, 0.4),
					frond_yaw, rng, block_batch, block_body, 0.0, Color(0.28, 0.48, 0.28), false
				)

			# Small trunk footprint
			obstacles.append({ "pos": Vector3(palm_x, 0, palm_z), "radius": OASIS_PALM_TRUNK_WIDTH * 0.71, "top": OASIS_PALM_TRUNK_HEIGHT, "climbable": false })

		# Climbable boulders scattered around. The 0.8 upper bound is not taste: the ring
		# max plus OASIS_BOULDER_SIZE_MAX * 0.7 has to stay inside OASIS_RADIUS, or a
		# boulder lands outside the circle _biome_spot_ok actually cleared.
		var boulder_count := rng.randi_range(OASIS_BOULDER_MIN, OASIS_BOULDER_MAX)
		for _b in boulder_count:
			var boulder_angle := rng.randf_range(0.0, TAU)
			var boulder_dist := rng.randf_range(OASIS_WATER_RADIUS * 1.5, OASIS_RADIUS * 0.8)
			var boulder_x := local_x + cos(boulder_angle) * boulder_dist
			var boulder_z := local_z + sin(boulder_angle) * boulder_dist

			# Keep within chunk
			if absf(boulder_x) > chunk_size * 0.5 - 1.5 or absf(boulder_z) > chunk_size * 0.5 - 1.5:
				continue

			var boulder_size := rng.randf_range(OASIS_BOULDER_SIZE_MIN, OASIS_BOULDER_SIZE_MAX)
			# Climbable rocks (collide=true) — round-ish color
			create_box(
				Vector3(boulder_x, boulder_size * 0.5, boulder_z),
				Vector3(boulder_size, boulder_size * 0.8, boulder_size),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0,
				Color(0.55, 0.48, 0.40), true
			)
			obstacles.append({ "pos": Vector3(boulder_x, 0, boulder_z), "radius": boulder_size * 0.7, "top": boulder_size * 0.8, "climbable": true })

		# Optional reed clusters around the edge
		if rng.randf() < OASIS_REED_CHANCE:
			for _r in rng.randi_range(1, 3):
				var reed_angle := rng.randf_range(0.0, TAU)
				var reed_x := local_x + cos(reed_angle) * OASIS_WATER_RADIUS * 1.05
				var reed_z := local_z + sin(reed_angle) * OASIS_WATER_RADIUS * 1.05
				# Thin visual-only reeds (collide=false)
				create_box(
					Vector3(reed_x, 1.0, reed_z),
					Vector3(0.3, 2.0, 0.3),
					rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0,
					Color(0.35, 0.45, 0.25), false
				)

		# Success — one oasis placed
		return


func _spawn_desert_dunes(chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build sand dunes: low, wide, climbable mounds (~1.5 m max height). Same split-placement
	pattern as oases: DUNE_PLACE_TRIES candidates, pick the first that passes spot checks.
	"""
	var half := chunk_size / 2.0 - DUNE_WIDTH_MAX * 0.71
	for _try in DUNE_PLACE_TRIES:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)

		if not _biome_spot_ok(chunk_center, local_x, local_z, DUNE_WIDTH_MAX * 0.71, DUNE_ROAD_CLEARANCE, obstacles):
			continue

		# Pick dune height and width
		var height := rng.randf_range(DUNE_HEIGHT_MIN, DUNE_HEIGHT_MAX)
		var width := rng.randf_range(DUNE_WIDTH_MIN, DUNE_WIDTH_MAX)

		# Build dune as a slightly tapered stack (wider at base, narrower at top)
		var layer_height := height / 2.0  # two layers
		var base_width := width
		var top_width := width * 0.75
		var color := DUNE_COLOR_A.lerp(DUNE_COLOR_B, rng.randf())

		# Base layer (wider)
		create_box(
			Vector3(local_x, layer_height * 0.5, local_z),
			Vector3(base_width, layer_height, base_width),
			rng.randf_range(0.0, 0.3), rng, block_batch, block_body, 0.0, color
		)

		# Top layer (narrower, for taper)
		create_box(
			Vector3(local_x, layer_height + layer_height * 0.5, local_z),
			Vector3(top_width, layer_height, top_width),
			rng.randf_range(0.0, 0.3), rng, block_batch, block_body, 0.0, color
		)

		# Climbable footprint (slightly conservative to stay within chunk)
		var footprint_radius := width * 0.5
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": footprint_radius, "top": height, "climbable": true })

		# Success — one dune placed
		return


func _spawn_forest_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	FOREST — many simple trees: one solid trunk box plus a stack of visual-only
	canopy boxes.

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One NON-climbable footprint per trunk.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	PERF (the reason a forest is affordable at all): 25-40 trees × ~4 boxes are all
	create_box entries, so they join the chunk's ONE MultiMeshInstance3D — a forest
	chunk is the SAME single block draw call as a plains chunk. Only the trunks pay
	a CollisionShape3D: the canopies pass collide = false, which is exactly why that
	parameter exists. Leaves you can walk under cost nothing but instances.

	EDGE FEATHERING: each tree re-tests biome_at at ITS OWN position, not just the
	chunk centre's. Without that, a forest would stop dead along a straight chunk
	seam; with it, the tree line follows the noise contour and the wood dissolves
	into the plain the way a real one does. One extra noise eval per candidate.
	"""
	# Canopy slabs are yawed, so the half-DIAGONAL is what has to stay inside the
	# chunk (same reasoning as MOUNTAIN_EDGE_MARGIN). A flat 2.0 m margin left the
	# widest canopy poking 0.4 m past the seam, where it would vanish with its own
	# chunk while the neighbour still renders.
	var half := chunk_size / 2.0 - TREE_CANOPY_WIDTH_MAX * 0.71
	var count := rng.randi_range(FOREST_TREES_MIN, FOREST_TREES_MAX)

	for _i in count:
		var local_x := rng.randf_range(-half, half)
		var local_z := rng.randf_range(-half, half)
		var world_x := chunk_center.x + local_x
		var world_z := chunk_center.z + local_z
		# Both rejections are post-draw `continue`s (see _spawn_desert_content).
		# The radius is the widest a TRUNK can be — the canopy is visual-only, and
		# leaves brushing a nearby block is exactly what a real wood looks like.
		if not _biome_spot_ok(chunk_center, local_x, local_z, TREE_TRUNK_WIDTH_MAX * 0.71 + 0.3, FOREST_ROAD_CLEARANCE, obstacles):
			continue
		if biome_at(world_x, world_z) != Biome.FOREST:
			continue

		var trunk_w := rng.randf_range(TREE_TRUNK_WIDTH_MIN, TREE_TRUNK_WIDTH_MAX)
		var trunk_h := rng.randf_range(TREE_TRUNK_HEIGHT_MIN, TREE_TRUNK_HEIGHT_MAX)
		var yaw := rng.randf_range(0.0, TAU)

		# Trunk: solid, so you bump into it and crocodiles' raycasts see it.
		create_box(
			Vector3(local_x, trunk_h * 0.5, local_z),
			Vector3(trunk_w, trunk_h, trunk_w),
			yaw, rng, block_batch, block_body, 0.0, TREE_TRUNK_COLOR
		)

		# Canopy: 2-3 shrinking slabs stacked from just below the trunk top, each
		# VISUAL ONLY (collide = false) — you walk under a tree, not into its leaves.
		var layers := rng.randi_range(TREE_CANOPY_LAYERS_MIN, TREE_CANOPY_LAYERS_MAX)
		var canopy_w := rng.randf_range(TREE_CANOPY_WIDTH_MIN, TREE_CANOPY_WIDTH_MAX)
		var canopy_y := trunk_h - TREE_CANOPY_LAYER_HEIGHT * 0.3
		for _l in layers:
			create_box(
				Vector3(local_x, canopy_y + TREE_CANOPY_LAYER_HEIGHT * 0.5, local_z),
				Vector3(canopy_w, TREE_CANOPY_LAYER_HEIGHT, canopy_w),
				yaw, rng, block_batch, block_body, 0.0, TREE_LEAF_COLOR, false
			)
			canopy_y += TREE_CANOPY_LAYER_HEIGHT * 0.8
			canopy_w *= TREE_CANOPY_TAPER

		# Footprint stops at the TRUNK top, and is NOT climbable, on purpose: a
		# climbable footprint would let _settle_coin_y perch a road coin on the
		# obstacle's `top`, and with the canopy height that coin would float 5 m up
		# a tree where nobody can reach it. Non-climbable means such a coin is
		# SKIPPED instead. Crocodiles read the same footprint and steer around the
		# trunk.
		obstacles.append({ "pos": Vector3(local_x, 0, local_z), "radius": trunk_w * 0.71 + 0.3, "top": trunk_h, "climbable": false })


func _spawn_mountain_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	var half := chunk_size / 2.0 - MOUNTAIN_EDGE_MARGIN
	var count := rng.randi_range(MOUNTAIN_MASSIF_MIN, MOUNTAIN_MASSIF_MAX)

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
			if _biome_spot_ok(chunk_center, local_x, local_z, MOUNTAIN_BASE_WIDTH_MAX * 0.71 + MOUNTAIN_LAYER_JITTER, MOUNTAIN_ROAD_CLEARANCE, avoid) \
					and biome_at(wx, wz) == Biome.MOUNTAIN:
				placed = true
		if not placed:
			continue

		var height := rng.randf_range(MOUNTAIN_HEIGHT_MIN, MOUNTAIN_HEIGHT_MAX)
		var base_w := rng.randf_range(MOUNTAIN_BASE_WIDTH_MIN, MOUNTAIN_BASE_WIDTH_MAX)
		# The layer count falls straight out of the height: every step must be too
		# tall to jump onto. Without that rule an 8 m massif split into 7 layers is
		# a 1.14 m staircase with a 1.7 m ledge at each level — a walkable ziggurat,
		# which would break the "impassable, you go around" contract that the whole
		# mountains-as-blocks design rests on under the flat-world invariant. With
		# heights of 8-20 m this gives 2-5 layers.
		var layers := maxi(2, int(height / MOUNTAIN_MIN_LAYER_HEIGHT))
		var snowy := height >= MOUNTAIN_SNOW_HEIGHT
		# Index of the first snow layer. Always leaves at least one rock layer
		# showing: a 14-15.9 m massif gets exactly 3 layers, and a flat
		# "top MOUNTAIN_SNOW_LAYERS" rule would paint 2 of those 3 white, so the
		# peak read as a snow pillar rather than rock wearing a cap.
		var snow_from := maxi(1, layers - MOUNTAIN_SNOW_LAYERS)
		var layer_h := height / float(layers)

		var width := base_w
		var y := 0.0
		for layer_index in layers:
			# The top boxes of a tall massif are forced white: a snow cap is the
			# cheapest possible "this one is high" signal.
			var is_snow := snowy and layer_index >= snow_from
			var color: Color = MOUNTAIN_SNOW_COLOR if is_snow else MOUNTAIN_ROCK_A.lerp(MOUNTAIN_ROCK_B, rng.randf())
			var jitter_x := rng.randf_range(-MOUNTAIN_LAYER_JITTER, MOUNTAIN_LAYER_JITTER)
			var jitter_z := rng.randf_range(-MOUNTAIN_LAYER_JITTER, MOUNTAIN_LAYER_JITTER)
			create_box(
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
		var footprint := { "pos": Vector3(local_x, 0, local_z), "radius": base_w * 0.71 + MOUNTAIN_LAYER_JITTER, "top": height, "climbable": false }
		obstacles.append(footprint)
		avoid.append(footprint)


func _spawn_city_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	CITY — small flat-roofed houses, market stalls under awnings, and traffic
	signals / lamp posts along the street lines.

	@param chunk_center: World centre of the chunk (create_box takes chunk-LOCAL).
	@param rng: The biome stream's private RNG.
	@param obstacles: One footprint per building — CLIMBABLE for houses (see
	                  below), non-climbable for stalls and street furniture.
	@param block_batch / block_body: The chunk's single MultiMesh + collision body.

	EVERY HOUSE ROOF IS A REST SPOT, and that is this territory's whole gameplay
	contribution. `CITY_HOUSE_HEIGHT_MAX` is `PROP_MAX_STEP` (2.6), so a hull top
	is one jump from the pavement; the footprint records `climbable: true` at that
	hull height, so crocodiles keep off it and `_settle_coin_y` perches a road coin
	on it rather than skipping. Every other biome's content is non-climbable — the
	city is the one that gives the bare cubes' role back at scale.

	CROC DENSITY IS REDUCED HERE and it is the ONE band where that is true; the
	division lives in spawn_crocodiles_in_chunk (see CITY_CROC_DIVISOR), not here.

	THE STREET READ COSTS TWO LINES, and there is deliberately NO road network:
	candidate positions are snapped to a coarse CITY_BLOCK_PITCH grid with jitter,
	and house yaws are quantised to quarter turns. Parallel facades along shared
	lines is what reads as a town. See the CITY banner in SECTION 1.

	EDGE FEATHERING: like the forest and the mountains, every candidate re-tests
	biome_at at ITS OWN position, so a city dissolves into the plain along the
	noise contour instead of stopping dead on a chunk seam.

	PERF: everything here is a create_box entry, so a city chunk is the SAME single
	block draw call as a plains chunk; only hulls, counters and masts pay a
	CollisionShape3D. There are ZERO emissive accent nodes — lamps are bright
	albedo boxes in the batch.
	"""
	var half := chunk_size / 2.0 - CITY_HOUSE_RADIUS_MAX

	# ---- HOUSES ------------------------------------------------------------
	for _i in rng.randi_range(CITY_HOUSE_TRIES_MIN, CITY_HOUSE_TRIES_MAX):
		var local_x := _city_snap(rng.randf_range(-half, half), rng)
		var local_z := _city_snap(rng.randf_range(-half, half), rng)
		# Quarter-turn yaw plus a little slop: facades line up along the grid.
		var yaw := float(rng.randi_range(0, 3)) * (PI * 0.5) + rng.randf_range(-0.08, 0.08)
		var width := rng.randf_range(CITY_HOUSE_WIDTH_MIN, CITY_HOUSE_WIDTH_MAX)
		var depth := width * rng.randf_range(CITY_HOUSE_DEPTH_FACTOR_MIN, CITY_HOUSE_DEPTH_FACTOR_MAX)
		var height := rng.randf_range(CITY_HOUSE_HEIGHT_MIN, CITY_HOUSE_HEIGHT_MAX)
		var wall := CITY_PLASTER_A.lerp(CITY_PLASTER_B, rng.randf())
		var roof := CITY_ROOF_TILE if rng.randf() < 0.6 else CITY_ROOF_SLATE
		var windows := rng.randi_range(1, 2)
		# The snap can push a candidate back outside the margin, so clamp rather
		# than redraw — a redraw would be a draw, and every rejection in this file
		# is a post-draw `continue` for exactly that reason.
		local_x = clampf(local_x, -half, half)
		local_z = clampf(local_z, -half, half)
		if not _biome_spot_ok(chunk_center, local_x, local_z, CITY_HOUSE_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != Biome.CITY:
			continue

		var local := Vector3(local_x, 0.0, local_z)
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		var front := Vector3(-sin(yaw), 0.0, cos(yaw))

		# Hull: the ONLY colliding box, and the one whose top face the footprint
		# names. Untilted, full size, centred — the climbability contract.
		create_box(
			local + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth),
			yaw, rng, block_batch, block_body, 0.0, wall
		)

		# Roof: a thin film over the hull top, collide = false, oversailing the
		# walls as eaves. The player stands on the HULL, inside this film — the
		# same arrangement STRUCTURE_THEMES' `cap` uses over a wall's ridge, and
		# the reason CITY_ROOF_THICKNESS is small.
		create_box(
			local + Vector3(0.0, height + CITY_ROOF_THICKNESS * 0.5, 0.0),
			Vector3(width + CITY_ROOF_EAVES * 2.0, CITY_ROOF_THICKNESS, depth + CITY_ROOF_EAVES * 2.0),
			yaw, rng, block_batch, block_body, 0.0, roof, false
		)

		# Door, on the front face. Visual only — it is inside the hull's own
		# collision box, so making it solid would buy nothing but a snag.
		var door_h := height * 0.62
		create_box(
			local + front * (depth * 0.5) + Vector3(0.0, door_h * 0.5, 0.0),
			Vector3(width * 0.24, door_h, 0.10), yaw,
			rng, block_batch, block_body, 0.0, PROP_CRATE, false
		)

		# Windows, spread along the front. Same reasoning: trim, never solid.
		for w in windows:
			var offset := (float(w) - float(windows - 1) * 0.5) * width * 0.32
			create_box(
				local + front * (depth * 0.5) + right * (offset + width * 0.26)
						+ Vector3(0.0, height * 0.62, 0.0),
				Vector3(width * 0.16, height * 0.22, 0.10), yaw,
				rng, block_batch, block_body, 0.0, CITY_ROOF_SLATE, false
			)

		# ONE circle per house, CLIMBABLE, with the hull top as its height. The
		# radius is the honest bound on the roof slab's rotated half-diagonal, so
		# it is above MOUNTAIN_AVOID_RADIUS (2.0) — deliberately, see the constant.
		obstacles.append({
			"pos": local,
			"radius": 0.5 * sqrt(pow(width + CITY_ROOF_EAVES * 2.0, 2.0) + pow(depth + CITY_ROOF_EAVES * 2.0, 2.0)),
			"top": height,
			"climbable": true,
		})

	# ---- MARKET STALLS -----------------------------------------------------
	for _i in rng.randi_range(CITY_STALL_TRIES_MIN, CITY_STALL_TRIES_MAX):
		var sx := _city_snap(rng.randf_range(-half, half), rng)
		var sz := _city_snap(rng.randf_range(-half, half), rng)
		var syaw := float(rng.randi_range(0, 3)) * (PI * 0.5) + rng.randf_range(-0.15, 0.15)
		var sw := rng.randf_range(CITY_STALL_WIDTH_MIN, CITY_STALL_WIDTH_MAX)
		var canvas := CITY_ROOF_TILE if rng.randf() < 0.5 else CITY_ROOF_SLATE
		sx = clampf(sx, -half, half)
		sz = clampf(sz, -half, half)
		if not _biome_spot_ok(chunk_center, sx, sz, CITY_STALL_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if biome_at(chunk_center.x + sx, chunk_center.z + sz) != Biome.CITY:
			continue

		var s_local := Vector3(sx, 0.0, sz)
		var s_right := Vector3(cos(syaw), 0.0, sin(syaw))

		# Counter — solid, so you bump into it and the crocodiles' raycasts see it.
		create_box(
			s_local + Vector3(0.0, CITY_STALL_COUNTER_HEIGHT * 0.5, 0.0),
			Vector3(sw, CITY_STALL_COUNTER_HEIGHT, sw * 0.5), syaw,
			rng, block_batch, block_body, 0.0, PROP_CRATE
		)
		# Awning + its two posts — all visual, you walk under a stall.
		create_box(
			s_local + Vector3(0.0, CITY_STALL_AWNING_HEIGHT, 0.0),
			Vector3(sw * 1.25, 0.12, sw * 0.85), syaw,
			rng, block_batch, block_body, rng.randf_range(-0.14, 0.14), canvas, false
		)
		for p in 2:
			var s := 1.0 if p == 0 else -1.0
			create_box(
				s_local + s_right * (sw * 0.5 * s) + Vector3(0.0, CITY_STALL_AWNING_HEIGHT * 0.5, 0.0),
				Vector3(0.10, CITY_STALL_AWNING_HEIGHT, 0.10), syaw,
				rng, block_batch, block_body, 0.0, CITY_METAL, false
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
		var lx := _city_snap(rng.randf_range(-half, half), rng)
		var lz := _city_snap(rng.randf_range(-half, half), rng)
		var lyaw := float(rng.randi_range(0, 3)) * (PI * 0.5)
		var lh := rng.randf_range(CITY_LIGHT_HEIGHT_MIN, CITY_LIGHT_HEIGHT_MAX)
		var is_signal := rng.randf() < CITY_SIGNAL_CHANCE
		lx = clampf(lx, -half, half)
		lz = clampf(lz, -half, half)
		if not _biome_spot_ok(chunk_center, lx, lz, CITY_LIGHT_RADIUS_MAX, CITY_ROAD_CLEARANCE, obstacles):
			continue
		if biome_at(chunk_center.x + lx, chunk_center.z + lz) != Biome.CITY:
			continue

		var l_local := Vector3(lx, 0.0, lz)
		var l_front := Vector3(-sin(lyaw), 0.0, cos(lyaw))

		# Mast — the one colliding box.
		create_box(
			l_local + Vector3(0.0, lh * 0.5, 0.0),
			Vector3(CITY_LIGHT_MAST_WIDTH, lh, CITY_LIGHT_MAST_WIDTH), lyaw,
			rng, block_batch, block_body, 0.0, CITY_METAL
		)

		if is_signal:
			# Head + the three-lamp stack. The stack IS the silhouette that says
			# "traffic light" at 30 m, which is why the three lamp colours are the
			# only colours the city palette spends on furniture. BRIGHT ALBEDO,
			# never emissive: this is one MultiMesh instance each, not a node.
			var head_h := CITY_LIGHT_LAMP * 3.4
			create_box(
				l_local + Vector3(0.0, lh + head_h * 0.5, 0.0),
				Vector3(CITY_LIGHT_LAMP * 1.5, head_h, CITY_LIGHT_LAMP * 1.4), lyaw,
				rng, block_batch, block_body, 0.0, CITY_METAL, false
			)
			var lamps := [CITY_LAMP_RED, CITY_LAMP_AMBER, CITY_LAMP_GREEN]
			for j in 3:
				create_box(
					l_local + l_front * (CITY_LIGHT_LAMP * 0.75)
							+ Vector3(0.0, lh + head_h - CITY_LIGHT_LAMP * (0.7 + float(j) * 1.05), 0.0),
					Vector3(CITY_LIGHT_LAMP, CITY_LIGHT_LAMP, CITY_LIGHT_LAMP * 0.4), lyaw,
					rng, block_batch, block_body, 0.0, lamps[j], false
				)
		else:
			# Lamp post: a cantilever arm with one shade on the end.
			var arm := rng.randf_range(0.7, 1.1)
			create_box(
				l_local + l_front * (arm * 0.5) + Vector3(0.0, lh, 0.0),
				Vector3(0.09, 0.09, arm), lyaw, rng, block_batch, block_body, 0.0, CITY_METAL, false
			)
			create_box(
				l_local + l_front * arm + Vector3(0.0, lh - CITY_LIGHT_LAMP * 0.5, 0.0),
				Vector3(CITY_LIGHT_LAMP * 1.6, CITY_LIGHT_LAMP, CITY_LIGHT_LAMP * 1.6), lyaw,
				rng, block_batch, block_body, 0.0, CITY_LAMP_AMBER, false
			)

		# NON-climbable: a mast has no top to stand on, and its "top" is 4 m up.
		obstacles.append({
			"pos": l_local,
			"radius": CITY_LIGHT_RADIUS_MAX,
			"top": lh,
			"climbable": false,
		})


func _spawn_snow_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	var branch_reach := FROZEN_TREE_BRANCH_LEN * 0.42 + 0.5 * Vector3(FROZEN_TREE_BRANCH_LEN, 0.22, 0.22).length()
	var tree_half := chunk_size / 2.0 - (FROZEN_TREE_TRUNK_WIDTH_MAX * 0.71 + branch_reach)
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
		if not _biome_spot_ok(chunk_center, local_x, local_z, FROZEN_TREE_TRUNK_WIDTH_MAX * 0.71 + 0.3, FROZEN_TREE_ROAD_CLEARANCE, obstacles):
			continue
		if biome_at(chunk_center.x + local_x, chunk_center.z + local_z) != Biome.SNOW:
			continue

		var trunk_w := rng.randf_range(FROZEN_TREE_TRUNK_WIDTH_MIN, FROZEN_TREE_TRUNK_WIDTH_MAX)
		var trunk_h := rng.randf_range(FROZEN_TREE_HEIGHT_MIN, FROZEN_TREE_HEIGHT_MAX)
		var yaw := rng.randf_range(0.0, TAU)

		# Trunk: solid, so you bump into it and the crocodiles' raycasts see it.
		create_box(
			Vector3(local_x, trunk_h * 0.5, local_z), Vector3(trunk_w, trunk_h, trunk_w),
			yaw, rng, block_batch, block_body, 0.0, SNOW_DEADWOOD
		)

		# Bare branches — no canopy, that is the point of a dead tree. Visual only:
		# you walk under them exactly as you walk under a forest canopy.
		for _b in rng.randi_range(2, 3):
			var a := rng.randf_range(0.0, TAU)
			var by := trunk_h * rng.randf_range(0.55, 0.92)
			var dir := Vector3(cos(a), 0.0, sin(a)) * (FROZEN_TREE_BRANCH_LEN * 0.42)
			create_box(
				Vector3(local_x, by, local_z) + dir,
				Vector3(FROZEN_TREE_BRANCH_LEN, 0.22, 0.22),
				a + PI * 0.5, rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
				SNOW_DEADWOOD, false
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
	var mammoth_half := chunk_size / 2.0 - MAMMOTH_EDGE_MARGIN
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
			if _biome_spot_ok(chunk_center, mx, mz, MAMMOTH_RADIUS, MAMMOTH_ROAD_CLEARANCE, obstacles) \
					and biome_at(chunk_center.x + mx, chunk_center.z + mz) == Biome.SNOW:
				placed = true
		if not placed:
			# Every try failing means NO skeleton. A mammoth shoved through a stand
			# of trees reads worse than a chunk without one — the camp's rule.
			continue

		var top := _snow_mammoth(Vector3(mx, 0.0, mz), rng, block_batch, block_body)

		obstacles.append({
			"pos": Vector3(mx, 0, mz),
			"radius": MAMMOTH_RADIUS,
			"top": top,
			"climbable": false,
		})


func _snow_mammoth(local: Vector3, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
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
	var spine_len := rng.randf_range(MAMMOTH_SPINE_LEN_MIN, MAMMOTH_SPINE_LEN_MAX)
	var pairs := rng.randi_range(MAMMOTH_RIB_PAIRS_MIN, MAMMOTH_RIB_PAIRS_MAX)
	var rib_top := MAMMOTH_RIB_HEIGHT * cos(MAMMOTH_RIB_TILT)
	var bone := PROP_BONE.lerp(SNOW_ICE_B, rng.randf() * 0.18)

	# --- RIBS. Each pair is two thin boxes whose BASES sit wide on the ground and
	# whose TOPS lean in over the spine. The tilt sign is what does that: a tilt
	# about the box's local X sends its up-vector toward local +Z, so the rib on
	# the -Z side takes a POSITIVE tilt and its mirror a negative one. Get the sign
	# backwards and the ribcage splays outward like a flower, which looks wrong and
	# raises nothing.
	for i in pairs:
		var t := (float(i) + 0.5) / float(pairs)
		var x := -spine_len * (0.08 + 0.84 * t)
		var rib_h := MAMMOTH_RIB_HEIGHT * rng.randf_range(0.88, 1.05)
		for s: float in [-1.0, 1.0]:
			create_box(
				local + fwd * x + side * (MAMMOTH_RIB_HALF_SPREAD * s)
						+ Vector3(0.0, rib_h * 0.5 * cos(MAMMOTH_RIB_TILT), 0.0),
				Vector3(0.16, rib_h, 0.30), yaw,
				rng, block_batch, block_body, -MAMMOTH_RIB_TILT * s,
				bone, false
			)

	# --- SPINE. One slab lying along the top of the ribcage, and one of the two
	# boxes that collide. It spans exactly x in [-spine_len, 0], so the footprint's
	# rear reach is spine_len and needs no separate bound.
	var spine_top := rib_top + 0.30
	create_box(
		local + fwd * (-spine_len * 0.5) + Vector3(0.0, rib_top + 0.15, 0.0),
		Vector3(spine_len, 0.30, 0.45), yaw,
		rng, block_batch, block_body, 0.0, bone
	)

	# --- SKULL. The other colliding box: a blunt mass at the front, which is what
	# the tusks have to come out of for the pair to read as one animal.
	create_box(
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
			var dir := fwd * sin(tilt) + Vector3.UP * cos(tilt)
			create_box(
				pos + dir * (seg_len * 0.5), Vector3(0.18, seg_len, 0.18),
				tusk_yaw, rng, block_batch, block_body, tilt, bone, false
			)
			pos += dir * seg_len

	return spine_top


func _city_snap(value: float, rng: RandomNumberGenerator) -> float:
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

func _biome_hash2(p: Vector2) -> float:
	"""
	GDScript port of `hash2` in assets/shaders/ground.gdshader.

	@param p: Lattice point.
	@return: Pseudo-random value in 0..1, a pure function of `p`.

	SHADER-PARITY CONTRACT: this function, _biome_value_noise and _biome_noise are
	line-for-line ports of their GLSL twins. EDIT THEM TOGETHER — if the CPU and
	GPU copies drift, the blue band the player SEES stops matching the wading zone
	the player FEELS, which is the one bug this whole arrangement exists to avoid.

	The mod(p, 289.0) wrap is not decoration: see the PRECISION note in the shader
	(world X reaches kilometres and fp32 hashing collapses out there). It is kept
	here so both copies tile at exactly the same place.

	EVERY STEP RUNS THROUGH Vector2, AND THAT IS THE POINT. Vector2 stores `real_t`
	= float32, so round-tripping a value through one is the only float32 cast
	GDScript has — bare GDScript scalars are float64. This hash AMPLIFIES: `v`
	reaches ~9.2e3 before the final fract, where an fp32 ULP is ~1e-3, so a
	last-bit difference upstream comes out ~200x larger at the end. Computing any
	step in float64 therefore does NOT give "the same answer, more precisely" — it
	gives a different hash. Measured against a strict-fp32 model of the GLSL, the
	old float64 version diverged by mean 3.1e-3 / max 1.0, with 8% of lattice
	corners past RIVER_HALF_WIDTH (0.007) — i.e. ~20% of river area disagreed
	between the blue band drawn and the wading zone felt, the exact failure this
	contract exists to prevent. Every operation below is therefore fp32-on-fp32,
	matching the GLSL bit-for-bit (verified over all 289x289 lattice corners).
	Do not "simplify" any line back to scalar arithmetic.
	"""
	var q := Vector2(fposmod(p.x, 289.0), fposmod(p.y, 289.0))
	q *= Vector2(0.1031, 0.1030)
	q = Vector2(q.x - floorf(q.x), q.y - floorf(q.y))
	# Vector2.dot() is real_t (fp32) arithmetic — GLSL's dot(p, p.yx + 33.33).
	q += Vector2.ONE * q.dot(Vector2(q.y, q.x) + Vector2(33.33, 33.33))
	# Both halves of fract((p.x + p.y) * p.x) forced through fp32 rounding.
	var v := Vector2(q.x + q.y, 0.0).x
	v = Vector2(v * q.x, 0.0).x
	return v - floorf(v)


func _biome_value_noise(p: Vector2) -> float:
	"""
	GDScript port of `value_noise` in assets/shaders/ground.gdshader: one octave of
	value noise — hash the four corners of the lattice cell `p` falls in, blend with
	the smoothstep weight f*f*(3-2f) so the gradient stays continuous.

	@param p: Sample point in noise space (world metres / BIOME_CELL_SIZE).
	@return: Value in 0..1.
	"""
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a := _biome_hash2(i)
	var b := _biome_hash2(i + Vector2(1.0, 0.0))
	var c := _biome_hash2(i + Vector2(0.0, 1.0))
	var d := _biome_hash2(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


func _biome_noise(world_x: float, world_z: float) -> float:
	"""
	THE biome field: one octave of value noise at wavelength BIOME_CELL_SIZE,
	domain-shifted by this run's biome_offset. Every biome question in the game —
	which biome, is this a river, what colour is the ground — is a readout of this
	single number, which is why regions and rivers agree with each other for free.

	@param world_x, world_z: World-space point (metres).
	@return: Field value clamped to 0..1.

	SHADER-PARITY CONTRACT: mirrors `biome_noise` in ground.gdshader exactly (same
	offset, same 1/BIOME_CELL_SIZE scale, same clamp). Edit both together.

	GDScript floats are doubles while GLSL runs fp32, so _biome_hash2 goes to some
	trouble to force every step through fp32 (see the note there — the naive
	double version is NOT a harmless last-bit difference, it moves the waterline
	by metres). With that done the two copies agree bit-for-bit on every lattice
	corner, which is far cheaper than uploading a field texture or reading
	anything back from the GPU.

	ponytail: the residual risk is a driver that contracts the dot() into an FMA,
	which would re-diverge (and could differ between desktop GL and mobile
	WebGL2). Upgrade path if that ever shows up: hash the wrapped INTEGER lattice
	indices with uint bit ops (GLSL ES 3.00 has them, GDScript ints are exact), so
	there is no float precision left to match — it changes the field, so
	RIVER_HALF_WIDTH would need re-tuning by eye.
	"""
	var p := Vector2(world_x, world_z) / BIOME_CELL_SIZE + biome_offset
	return clampf(_biome_value_noise(p), 0.0, 1.0)


func biome_at(world_x: float, world_z: float) -> Biome:
	"""
	Classify a world position into one of the six biomes.

	@param world_x, world_z: World-space point (metres).
	@return: The Biome band the field falls in at that point.

	Pure function, no RNG, no allocation — safe to call from any spawner in any
	order. Rivers are NOT a return value here: they are an overlay, tested with
	is_river_at().
	"""
	var n := _biome_noise(world_x, world_z)
	if n < BIOME_DESERT_MAX:
		return Biome.DESERT
	if n < BIOME_PLAINS_MAX:
		return Biome.PLAINS
	if n < BIOME_CITY_MAX:
		return Biome.CITY
	if n < BIOME_FOREST_MAX:
		return Biome.FOREST
	if n < BIOME_MOUNTAIN_MAX:
		return Biome.MOUNTAIN
	return Biome.SNOW


func is_river_at(world_pos: Vector3) -> bool:
	"""
	Is this world position inside a river band?

	@param world_pos: World-space position (Y is ignored — the world is flat).
	@return: true when the point sits within RIVER_HALF_WIDTH of the RIVER_LEVEL
	         contour of the biome field.

	THE PUBLIC GAMEPLAY API: the player polls this once per physics tick for the
	wading slowdown, and the terrain's own spawners call it to keep blocks,
	structures and crocodiles out of the water. One noise evaluation, zero
	allocation — cheap enough for a per-frame call.

	EDUCATIONAL NOTE — why a contour makes a river: thresholding noise gives you
	BLOBS (regions), but the boundary BETWEEN two thresholds is a contour line, and
	contour lines are long, thin and winding — exactly a river. So a river costs no
	extra field, no path integration and no state: it is the same number the biome
	colours read, just asked a different question.
	"""
	return absf(_biome_noise(world_pos.x, world_pos.z) - RIVER_LEVEL) < RIVER_HALF_WIDTH


func tower_site() -> Vector3:
	"""
	Where the tower stands this run — the ONE position the whole tower epic
	parents to (shell, impostor, minimap marker, door, interior).

	@return: Ground-level world position (y = 0) of the tower's centre.

	PURE, ZERO RNG DRAWS, MEMOIZED. It reads nothing but tower_site_distance and
	the biome field (which is itself a pure function of run_seed), so the same run
	answers the same thing forever, every peer in a multiplayer room agrees for
	free, and no spawner's stream is disturbed by asking. Never call an RNG from
	anywhere under here: a single draw from the shared chunk stream slides every
	crocodile in the world (see the determinism section of CLAUDE.md).
	"""
	if _tower_site_dist == tower_site_distance and _tower_site_seed == run_seed:
		return _tower_site_cache
	_tower_site_cache = _tower_scan_dry_site()
	_tower_site_seed = run_seed
	_tower_site_dist = tower_site_distance
	return _tower_site_cache


func _tower_scan_dry_site() -> Vector3:
	"""
	The dry-site nudge: walk the fixed candidate lattice out from the nominal site
	and return the first candidate whose whole footprint disc is out of the water.

	@return: The chosen site, y = 0.

	TOTAL BY CONSTRUCTION. The lattice is bounded (TOWER_NUDGE_RINGS rings of
	TOWER_NUDGE_STEP), so the scan always ends; and if a seed's rivers soak every
	candidate, it ends on the DRIEST one rather than failing or randomizing. The
	ring-by-ring order is what makes "nudge" honest — the site moves as little as
	the water allows, and ring 0 (the nominal site) is tried first.
	"""
	var base_x := -tower_site_distance
	var driest := Vector2(base_x, 0.0)
	var driest_wet := 0x7FFFFFFF

	for ring in TOWER_NUDGE_RINGS + 1:
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				# Ring by ring outward: only the SHELL of each square is new, the
				# interior was covered by a smaller ring already.
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cx := base_x + float(dx) * TOWER_NUDGE_STEP
				var cz := float(dz) * TOWER_NUDGE_STEP
				var wet := _tower_wet_samples(cx, cz)
				if wet == 0:
					return Vector3(cx, 0.0, cz)
				if wet < driest_wet:
					driest_wet = wet
					driest = Vector2(cx, cz)

	# Every candidate had water in it. Deterministic, documented, and still a
	# site — see the TOWER_NUDGE_STEP block on why this beats retrying at random.
	push_warning("endless_terrain: no fully dry tower site within %d rings; using the driest (%d wet samples)"
			% [TOWER_NUDGE_RINGS, driest_wet])
	return Vector3(driest.x, 0.0, driest.y)


func _tower_wet_samples(center_x: float, center_z: float) -> int:
	"""
	How many of a candidate footprint's river samples land in the water.

	@param center_x, center_z: Candidate site centre, world space.
	@return: Count of wet samples — 0 means the whole disc is dry.

	A GRID, NOT A RIM: a river winds, so a ring of samples around the rim would let
	a band slip across the middle of the disc unseen.

	AND A WIDENED GRID, NOT A PLAIN ONE. Each sample stands for the whole cell
	around it, so the band it is tested against is widened by the most the field can
	move from the sample to the furthest point of that cell — BIOME_NOISE_MAX_SLOPE
	over half the cell diagonal. Zero wet samples is then a PROOF that no point of
	the disc is in the water, rather than the hope that no band was narrow enough to
	hide between two samples. It is stated on the noise value directly because
	is_river_at() bakes in the un-widened RIVER_HALF_WIDTH; the two agree exactly
	when the margin is zero.

	The count (rather than a bool) is what lets the scan above fall back to the
	driest candidate instead of to nothing.
	"""
	# Furthest any point can sit from the nearest sample is half the cell diagonal.
	var margin := TOWER_SAMPLE_STEP * 0.5 * sqrt(2.0) * BIOME_NOISE_MAX_SLOPE
	var half_width := RIVER_HALF_WIDTH + margin
	# One step of slack on the rim too, so the samples cover the whole disc and not
	# just every disc point that happens to have a sample inside it.
	var reach := TOWER_RADIUS + TOWER_SAMPLE_STEP
	var wet := 0
	var steps := int(ceilf(reach / TOWER_SAMPLE_STEP))
	for ix in range(-steps, steps + 1):
		for iz in range(-steps, steps + 1):
			var ox := float(ix) * TOWER_SAMPLE_STEP
			var oz := float(iz) * TOWER_SAMPLE_STEP
			if Vector2(ox, oz).length() > reach:
				continue
			if absf(_biome_noise(center_x + ox, center_z + oz) - RIVER_LEVEL) < half_width:
				wet += 1
	return wet


func tower_excludes(world_x: float, world_z: float, radius: float = 0.0) -> bool:
	"""
	Is this spot inside the tower's exclusion disc?

	@param world_x, world_z: The candidate spot, WORLD space (the `obstacles` list
	                         is chunk-local; convert before calling, as every other
	                         world-space test in this file does).
	@param radius: The candidate's own footprint radius, so a thing is rejected
	               before it can REACH into the disc rather than only when its
	               centre is in it. Callers with no meaningful radius pass none —
	               TOWER_DECOR_OVERHANG is added on top either way, because a
	               declared footprint is an overlap claim and not a silhouette.
	@return: true when the spot must not be built on.

	THE SINGLE HOME of the tower-clearance rule, in the same spirit as
	_biome_spot_ok is for placement legality and SPAWN_SAFE_RADIUS is for the spawn
	bubble. Pure and allocation-free, safe to call from any spawner in any order.

	POST-DRAW ONLY. Every call site rejects AFTER the draws that produced the
	candidate, exactly like the river and spawn-bubble rejections beside it: the
	stream must still advance or the whole world downstream of it shifts.
	"""
	var site := tower_site()
	var keep_out := TOWER_RADIUS + radius + TOWER_DECOR_OVERHANG
	return Vector2(world_x - site.x, world_z - site.z).length() < keep_out


func tower_blocks_coin(world_x: float, world_y: float, world_z: float) -> bool:
	"""
	Would a coin at this world point be buried inside the tower's stonework?

	@param world_x, world_y, world_z: The settled coin position, WORLD space.
	@return: true when the coin must be skipped.

	WHY THIS EXISTS AT ALL. Phase 1 deliberately left the COIN ROAD out of
	`tower_excludes()` — it is one parametric line through the whole world and
	cutting a hole in it would break "follow the coins" — and explicitly left the
	question of what the road does at the tower door to this phase. This is that
	answer, and it is the smallest one: a coin the walls would swallow is dropped,
	and every other coin on the road is untouched, so the trail still runs past the
	door and into the yard. (Run seed 56 lays a road coin 9.15 m out and 5.36 m
	across from the site centre, i.e. inside the -Z door jamb — found by codex
	review, 2026-08-28.)

	THE SAME RULE `_settle_coin_y` ALREADY APPLIES to a non-climbable block top, for
	the same reason: a coin you can see and cannot reach is worse than no coin. It
	is a separate function only because the tower is authored geometry and therefore
	in no chunk's `obstacles` list — there is nothing for `_settle_coin_y` to read.

	POST-DRAW ONLY, like every other rejection in this file: the caller `continue`s
	AFTER the draws that produced the candidate, so the road's stream still advances
	and the rest of the world is unmoved. Pure and allocation-free on the common
	path — the disc test rejects before the box table is ever asked for.
	"""
	var site := tower_site()
	var dx := world_x - site.x
	var dz := world_z - site.z
	# Cheap disc reject first: every coin in the world that is not at the tower pays
	# one length() and nothing else.
	if Vector2(dx, dz).length() > TOWER_RADIUS:
		return false
	# BOTH TABLES — the shell's stonework AND the interior's, because a coin walled
	# into the vault or standing inside the upper slab is exactly as unreachable as
	# one inside a jamb, and the road runs straight through the building.
	for box: Dictionary in TowerShell.boxes() + TowerInterior.boxes():
		# Only the SOLID boxes. The yard slab is 3 cm of paint and the beacon is a
		# light 24 m up; a coin is welcome to sit on either.
		if not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if absf(dx - pos.x) < half.x + COIN_TOWER_CLEARANCE \
				and absf(world_y - pos.y) < half.y + COIN_TOWER_CLEARANCE \
				and absf(dz - pos.z) < half.z + COIN_TOWER_CLEARANCE:
			return true
	return false


func tower_shell() -> Node3D:
	"""
	The instanced tower, or null while the player has never been near it.

	@return: The live `TowerShell` node, or null.

	The public seam for phase 3 (the interior) and for the self-check. Everything
	else about the tower is reachable through the "tower" group the shell joins;
	this exists because "is it built yet" is a question the group answers with an
	empty array either way.
	"""
	return _tower_shell if is_instance_valid(_tower_shell) else null


func _tower_stream(player_pos: Vector3) -> void:
	"""
	Instance the tower shell the first time the player comes near its site, and
	retire the horizon impostor when it does.

	@param player_pos: The local player's world position.

	CALLED ONLY ON A CHUNK BOUNDARY CROSSING (see _process), never per frame — the
	bead's "no polling storm": at cruising speed that is one distance test every few
	seconds, and once the shell exists it is one validity test and a return.

	The shell is parented to THIS NODE, deliberately. A chunk-parented building
	would be freed the moment the player walked far enough for its chunk to unload,
	which for a 400 m destination is most of the time — the same reason
	fauna_manager parents its herds to itself (CLAUDE.md).
	"""
	if is_instance_valid(_tower_shell):
		return
	var site := tower_site()
	if not _tower_in_load_range(player_pos, site):
		# ...and the MULTIPLAYER FOCUS SET, which is the same question asked about
		# somebody else's player. `set_focus_points` pins the chunks around every
		# teammate precisely because the master SIMULATES what is in them, and
		# crocodiles are master-simulated (CLAUDE.md) — so a master still 400 m out
		# while a teammate walks into the tower would be running that teammate's
		# crocodiles against a world with no tower in it, walking them straight
		# through walls the teammate's own shell then refuses (codex review,
		# 2026-08-28). The shell has to exist wherever it is being simulated, not
		# only wherever it is being looked at.
		#
		# Bounded by MAX_FOCUS_CHUNKS (27) and reached only on a boundary crossing
		# or a focus change, so it is at most 27 length() calls a few times a second
		# — and never once solo, where `focus_chunks` is empty by construction.
		var reached := false
		for chunk_pos: Vector2i in focus_chunks:
			if _tower_in_load_range(chunk_to_world(chunk_pos), site):
				reached = true
				break
		if not reached:
			return
	_tower_shell = TOWER_SHELL_SCENE.instantiate() as Node3D
	# The interior goes in BEFORE the shell enters the tree, so the whole building
	# arrives in one frame and `TowerInterior._ready()` can already see the shell as
	# its parent (which is where the opened-gate set lives).
	_tower_shell.add_child(TOWER_INTERIOR_SCENE.instantiate())
	add_child(_tower_shell)
	# LOCAL position with a WORLD coordinate, exactly as create_chunk parks a chunk
	# (`mesh_instance.position = chunk_to_world(...)`): this node is the world-space
	# frame everything under it is placed in. It is also the only form that is safe
	# on a terrain that is not in the tree yet — `set_run_seed()` is reachable there
	# and `global_position` is rejected outright (codex review, 2026-08-28).
	_tower_shell.position = site
	# The silhouette has done its job — the real thing is now standing in the same
	# place, and two towers in one spot z-fight.
	if is_instance_valid(_tower_impostor):
		_tower_impostor.visible = false


func _tower_in_load_range(from: Vector3, site: Vector3) -> bool:
	"""Is this world point near enough the site to want the shell built? XZ only —
	the world is flat and the tower is not going anywhere vertically."""
	return Vector2(from.x - site.x, from.z - site.z).length() <= TOWER_LOAD_RADIUS


func _tower_reset() -> void:
	"""
	Put the tower back to "not built yet, and visible on the horizon" — at the
	CURRENT site, which a new run has just moved.

	Called from new_run() after the seed is set and before any chunk is rebuilt.
	The shell is the one thing in this file that survives a chunk wipe, so it is
	also the one thing a new run has to free by hand; the impostor is repositioned
	rather than rebuilt, because its geometry does not depend on the seed.
	"""
	if is_instance_valid(_tower_shell):
		_tower_shell.queue_free()
	_tower_shell = null
	if not is_instance_valid(_tower_impostor):
		_tower_impostor = TowerShell.build_impostor()
		add_child(_tower_impostor)
	# LOCAL, for the reason _tower_stream gives — and it matters most HERE, because
	# set_run_seed() (this function's only caller) is routinely called on a terrain
	# that is not in the tree: mp_selfcheck, prop_selfcheck and enemy_spawn_selfcheck
	# all build one that way.
	_tower_impostor.position = tower_site()
	_tower_impostor.visible = true


# ============================================================================
# COIN ROAD MATH (deterministic, pure-in-k parametric centerline + coin placement)
# ============================================================================
#
# Everything below is a pure function of the station index `k`, ROAD_WORLD_SEED, and
# the per-run run_seed (constant for the whole run). There is no per-chunk RNG and no
# per-frame state, so the road is identical for a given `k` no matter which chunk asks
# for it or in what order — that is what makes the trail seamless across chunk
# boundaries and reproducible on revisit. Only new_run() (a fresh run) changes it.

func _road_hash01(k: int) -> float:
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
	var h := hash(Vector3i(k, ROAD_WORLD_SEED, run_seed))
	# Mask to 24 positive bits and normalise to [0, 1). (Plenty of resolution for an
	# angle, and avoids sign issues from hash() possibly returning negatives.)
	return float(h & 0xFFFFFF) / float(0x1000000)

func _road_turn(k: int) -> float:
	"""
	Signed per-station turn angle (radians) for station `k`.

	@param k: Station index.
	@return: A deterministic angle in [-road_turn_rate_deg, +road_turn_rate_deg],
	         expressed in radians; this is the heading "jitter" added at station `k`.

	EDUCATIONAL NOTE:
	- _road_hash01 gives [0,1); we remap it to [-1,1] and scale by the configured
	  turn rate. This is the only source of curviness in the path.
	"""
	var signed_unit := _road_hash01(k) * 2.0 - 1.0  # [0,1) -> [-1,1)
	return deg_to_rad(road_turn_rate_deg) * signed_unit

func _road_extend_to_x(x_min: float, x_max: float) -> void:
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
	assert(road_max_heading_deg < 90.0,
		"road_max_heading_deg must be < 90 so the centerline's X stays strictly increasing")
	# The same termination depends on the STEP distance being strictly positive: a zero or
	# negative road_coin_spacing freezes/reverses X so the while-loops below never reach
	# their target and HANG. Loud editor-time hint; _road_spacing() is the release-safe guard.
	assert(road_coin_spacing > 0.0,
		"road_coin_spacing must be > 0 so each station strictly advances the centerline's X")

	var max_heading := _road_max_heading()
	# Clamped effective step distance — strictly positive, so X always advances and the
	# extend loops below terminate. At the default 6.0 this is inert (returns 6.0).
	var spacing := _road_spacing()

	# First-time seeding: station 0 at world origin, heading along +X (0 rad).
	if road_k_min > road_k_max:
		road_stations = { 0: { "center": Vector2(0.0, 0.0), "heading": 0.0 } }
		road_k_min = 0
		road_k_max = 0

	# Grow FORWARD (increasing k) until the last cached station's X reaches x_max.
	# We append station (k+1) computed from station k's center+heading.
	while _road_station(road_k_max).center.x < x_max:
		var cur: Dictionary = _road_station(road_k_max)
		var cur_heading: float = cur.heading
		# New center: step the (clamped) spacing along the CURRENT heading.
		var next_center: Vector2 = cur.center + spacing * Vector2(cos(cur_heading), sin(cur_heading))
		# New heading for the NEXT step: restore toward +X, add this station's turn, clamp.
		var next_heading: float = clampf(
			cur_heading * (1.0 - ROAD_RESTORE) + _road_turn(road_k_max),
			-max_heading, max_heading)
		# O(1) Dictionary insert keyed by the new station index (no array-shift).
		road_stations[road_k_max + 1] = { "center": next_center, "heading": next_heading }
		road_k_max += 1

	# Grow BACKWARD (decreasing k) until the first cached station's X reaches x_min.
	# To prepend station (k-1) we need heading[k-1] and center[k-1] such that stepping
	# station (k-1) FORWARD reproduces station k. We mirror the forward rule:
	#   - heading[k-1] is the heading that, after restore+turn(k-1)+clamp, yields
	#     heading[k]. Inverting the clamp+restore exactly is not generally possible, so
	#     we instead define the backward heading directly with the SAME recurrence shape
	#     using turn_noise(k-1), which keeps the cache a deterministic function of k.
	#   - center[k-1] = center[k] - _road_spacing() * dir(heading[k-1]).
	while _road_station(road_k_min).center.x > x_min:
		var first: Dictionary = _road_station(road_k_min)
		var first_heading: float = first.heading
		# Reconstruct the heading at (k-1). Forward rule from (k-1) to (k) is:
		#   heading[k] = clamp(heading[k-1]*(1-RESTORE) + turn(k-1), ...)
		# Solve for heading[k-1] (un-clamped form, which is exact whenever heading[k]
		# is off the cap — and on the cap the road is straightened anyway, so the small
		# discrepancy is invisible and, crucially, still fully deterministic in k):
		var prev_heading: float = clampf(
			(first_heading - _road_turn(road_k_min - 1)) / (1.0 - ROAD_RESTORE),
			-max_heading, max_heading)
		# Step BACKWARD from the first cached center along the reconstructed heading
		# (same clamped, strictly-positive spacing as the forward step).
		var prev_center: Vector2 = first.center - spacing * Vector2(cos(prev_heading), sin(prev_heading))
		# O(1) Dictionary insert keyed by (k-1) — this is the whole reason the cache is a
		# Dictionary and not an Array: an Array would need push_front here (O(n) shift).
		road_stations[road_k_min - 1] = { "center": prev_center, "heading": prev_heading }
		road_k_min -= 1

func _road_max_heading() -> float:
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
	return deg_to_rad(clampf(road_max_heading_deg, 0.0, 89.0))

func _road_spacing() -> float:
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
	return maxf(road_coin_spacing, 0.1)

func _road_station(k: int) -> Dictionary:
	"""
	Return the cached station Dictionary { center: Vector2, heading: float } for index
	`k`. ASSUMES `k` is within [road_k_min, road_k_max] (callers extend the cache
	first). The cache is a Dictionary keyed directly by `k`, so this is an O(1) lookup.
	"""
	return road_stations[k]

func _road_first_k_at_or_after_x(x: float) -> int:
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
	var lo := road_k_min
	var hi := road_k_max
	# Standard lower-bound binary search: narrow toward the first index satisfying
	# center.x >= x. `lo` ends one past the last station strictly left of x.
	while lo <= hi:
		var mid := lo + (hi - lo) / 2  # integer division → floor of the midpoint
		if _road_station(mid).center.x < x:
			lo = mid + 1
		else:
			hi = mid - 1
	return lo

func _road_width(k: int) -> float:
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
	var width := lerpf(road_width_min, road_width_max, t)
	var narrow_t := clampf(float(absi(k)) / float(ROAD_NARROW_STATIONS), 0.0, 1.0)
	return lerpf(width, road_width_min * ROAD_NARROW_FLOOR_FACTOR, narrow_t)

func _road_coins_at(k: int) -> Array:
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
	var st: Dictionary = _road_station(k)
	var center: Vector2 = st.center
	var heading: float = st.heading
	# Unit vectors ALONG (tangent) and PERPENDICULAR (left-hand normal) to the heading,
	# in the XZ plane. Vector2.x -> world X, Vector2.y -> world Z.
	var tangent := Vector2(cos(heading), sin(heading))
	var perp := Vector2(-sin(heading), cos(heading))
	var half_band := _road_width(k) * 0.5

	# Per-station RNG seeded purely from `k` (+ a coin-specific seed + this run's seed):
	# deterministic and load-order independent within a run. The draw order below is
	# fixed, so the coin set is stable; new_run() re-rolls run_seed for a fresh scatter.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(k, ROAD_COIN_SEED, run_seed))

	var coins: Array = []
	for _slot in road_coin_slots:
		# Rolling each slot (rather than always placing a coin) is what makes the swath
		# sparse and irregular instead of a regular grid. A skipped slot still consumes
		# one draw, so the RNG sequence — and thus every later coin — stays deterministic.
		if rng.randf() >= road_coin_chance:
			continue
		var lat := rng.randf_range(-1.0, 1.0) * half_band                               # across the band
		var lon := rng.randf_range(-1.0, 1.0) * ROAD_COIN_LONG_JITTER * _road_spacing()  # along the road
		var p := center + perp * lat + tangent * lon
		# One extra draw AFTER the position: is this coin a rare gem? The draw order
		# (chance, lat, lon, gem) is fixed, so the whole station stays deterministic.
		var gem := rng.randf() < ROAD_GEM_CHANCE
		coins.append({ "pos": Vector3(p.x, COIN_GROUND_HEIGHT, p.y), "gem": gem })
	return coins

func _road_lateral_distance(world_x: float, world_z: float, clearance: float) -> float:
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
	var pad := clearance + _road_spacing() * 2.0
	_road_extend_to_x(world_x - pad, world_x + pad)

	var best := INF
	var k := _road_first_k_at_or_after_x(world_x - pad)
	while k <= road_k_max:
		var st: Dictionary = _road_station(k)
		k += 1
		if st.center.x > world_x + pad:
			break  # past the window — X only grows from here, so stop
		var d := Vector2(world_x, world_z).distance_to(st.center)
		if d < best:
			best = d
	return best

func spawn_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
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
	if not spawn_coins or coin_scene == null:
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
	var center := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0
	var x0 := center.x - half_chunk
	var x1 := center.x + half_chunk
	var pad := maxf(road_width_min, road_width_max) * 0.5 + ROAD_COIN_LONG_JITTER * _road_spacing() + 2.0

	# Grow the shared station cache so it covers this chunk's widened X-range. The
	# cache is a pure function of `k`, so this is idempotent across chunks and load
	# order doesn't matter — it just grows contiguously and is reused.
	_road_extend_to_x(x0 - pad, x1 + pad)

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
	var k_start := _road_first_k_at_or_after_x(x0 - pad)
	# We index stations with the captured `cur_k` and advance the cursor `k` once at the
	# TOP of every iteration (before any `continue`), so both early-skip paths below still
	# move forward — a `while` has no implicit step, so a `continue` past an unincremented
	# counter would spin forever. The `break` (window exhausted) exits outright, no step
	# needed. Iteration order over k is identical to the old `for k in range(...)`.
	var k := k_start
	while k <= road_k_max:
		var cur_k := k
		k += 1
		var st: Dictionary = _road_station(cur_k)
		var cx: float = st.center.x
		if cx > x1 + pad:
			break  # past this chunk's window — and X only grows from here, so stop

		# This station scatters a handful of coins across the band; place each one that
		# actually lands inside THIS chunk. Each entry is { "pos": Vector3, "gem": bool }.
		for cw in _road_coins_at(cur_k):
			var cw_pos: Vector3 = cw.pos
			# Bucket by final chunk: spawn this coin only from the chunk it actually lands
			# in. This is what makes seams gap-free and duplicate-free.
			if world_to_chunk(cw_pos) != chunk_pos:
				continue

			# Convert to chunk-LOCAL (relative to the chunk center, like every other
			# chunk-parented node), so the coin sits at the right world spot.
			var local := Vector3(cw_pos.x - center.x, cw_pos.y, cw_pos.z - center.z)

			# Perch-or-skip against the chunk's block footprints. The rule lives in
			# _settle_coin_y (ONE home, shared with artifact reward coins so the two
			# spawners can never drift apart); INF means "skip this coin".
			local.y = _settle_coin_y(local.x, local.z, local.y, obstacles)
			if is_inf(local.y):
				continue

			# ...and against THE TOWER, which is authored geometry and therefore in
			# no chunk's `obstacles` list for _settle_coin_y to have seen. Same
			# post-draw `continue`, same rule (a coin inside stone is dropped, not
			# moved) — see tower_blocks_coin for why the road is filtered here
			# rather than excluded wholesale.
			if tower_blocks_coin(cw_pos.x, local.y, cw_pos.z):
				continue

			# Spawn the coin (position is local to the chunk, like blocks/crocodiles).
			# A gem entry is upgraded BEFORE entering the tree (make_gem recolours a
			# duplicated material and scales the whole pickup — see coin.gd).
			var coin := coin_scene.instantiate()
			coin.position = local
			if cw.gem:
				coin.make_gem()
			parent_chunk.add_child(coin)

func _settle_coin_y(local_x: float, local_z: float, ground_y: float, obstacles: Array) -> float:
	"""
	The SINGLE home of the coin perch-or-skip rule, shared by road coins
	(spawn_coins_in_chunk) and artifact reward coins (spawn_artifact_in_chunk) so
	the two spawners can never drift apart.

	@param local_x, local_z: The coin's column, chunk-LOCAL (same frame as ob.pos).
	@param ground_y: The y to use when the column is over open ground.
	@param obstacles: The chunk's block-footprint list.
	@return: The y to place the coin at, or INF meaning "skip this coin".

	If the column runs over a block footprint, a ground-height coin would be
	buried. A coin must clear EVERYTHING it overlaps, not just whatever block we'd
	like to perch it on — so the TALLEST overlapping block governs:
	  - if the tallest overlap is climbable, perch on its top (which is above every
	    other block the coin covers, so nothing buries it);
	  - if the tallest overlap is NON-climbable (a sheer wall/roof higher than a
	    jump), skip the coin entirely (return INF). Perching on a SHORTER climbable
	    block here would leave the coin embedded inside that taller wall — visually
	    buried and effectively unreachable, which is worse than dropping one coin
	    (structures are sparse, so the visible trail stays intact).

	We scan ALL overlapping blocks (never break on the first) to find that tallest
	top. obstacles is in a fixed order and the strict `>` keeps the FIRST block on
	a tie, so this stays a pure deterministic function of the obstacles list.
	"""
	if not _point_over_block(local_x, local_z, obstacles):
		return ground_y
	var found := false
	var tallest_top := 0.0
	var tallest_climbable := false
	for ob in obstacles:
		if _block_overlaps(local_x, local_z, ob):
			# Strict `>` keeps the FIRST block on a tie (deterministic).
			if not found or ob.top > tallest_top:
				tallest_top = ob.top
				tallest_climbable = ob.get("climbable", false)
				found = true
	if not tallest_climbable:
		return INF
	return tallest_top + COIN_BLOCK_OFFSET

func _block_overlaps(x: float, z: float, ob: Dictionary) -> bool:
	"""
	True if the (x, z) column falls within block `ob`'s footprint, padded outward by
	COIN_BLOCK_OVERLAP_MARGIN so coins grazing the edge count as "over" the block.

	@param x, z: Column to test (chunk-LOCAL XZ, same frame as ob.pos).
	@param ob: One block obstacle entry with `pos` (Vector2) and `radius` (float).
	@return: Whether the column hugs the block's (padded) footprint.

	This is the single home of the coin-vs-block overlap rule: both _point_over_block
	(does ANY block cover this coin?) and the perch loop (WHICH covered block is the
	highest climbable one?) call it, so the test and its margin can't drift apart.
	"""
	return Vector2(x - ob.pos.x, z - ob.pos.z).length() < ob.radius + COIN_BLOCK_OVERLAP_MARGIN

func _point_over_block(x: float, z: float, obstacles: Array) -> bool:
	"""
	True if the (x, z) column is over (or hugging) a block footprint, so we don't
	drop a road coin inside a block (it perches on the block's top instead).
	"""
	for ob in obstacles:
		if _block_overlaps(x, z, ob):
			return true
	return false

func remove_chunk(chunk_pos: Vector2i) -> void:
	"""
	Removes a chunk from the scene to save memory.

	@param chunk_pos: Chunk coordinates to remove

	EDUCATIONAL NOTE:
	- We use queue_free() instead of free() for safety
	- This ensures the node is removed at a safe time
	- We also remove it from our dictionary to free memory
	"""
	if chunk_pos in active_chunks:
		var chunk = active_chunks[chunk_pos]
		chunk.queue_free()
		active_chunks.erase(chunk_pos)
		# A chunk can be freed while it still owes its content (grounded on one
		# crossing, walked away from before the queue reached it). Clearing the
		# debt note here is what stops a re-created chunk from inheriting it.
		bare_chunks.erase(chunk_pos)
		chunks_removed_total += 1

func new_run(forced_seed = null, around: Vector2i = Vector2i.ZERO) -> void:
	"""
	Reset the world for a brand-new run: set the per-run seed and rebuild
	everything derived from it. Called by player_controller.restart_game() (via the
	"terrain" group) BEFORE the player is teleported back to the (0,2,0) spawn.

	forced_seed is deliberately UNTYPED with a null default rather than an int
	sentinel: 0 is a perfectly legitimate seed value, so there is no int that could
	mean "no seed given". Passing one (multiplayer hands every peer in a room the
	same seed) makes this run that exact world; omitting it keeps the solo path
	byte-identical to before this parameter existed.

	`around` is the chunk the rebuild centres on, defaulting to the spawn chunk
	(0,0) — so BOTH existing call sites (player_controller.restart_game() and
	mp_manager._receive_seed(), neither of which passes it) behave byte-identically
	to before this parameter existed. A mid-run multiplayer joiner passes the chunk
	it is about to be PLACED in instead of the origin, so the synchronous SYNC_RING
	ground in step 4 lands under ITS feet in the same frame — exactly the guarantee
	the spawn-chunk build gives a restart, just centred somewhere else.

	EDUCATIONAL NOTE — the order matters:
	1. Set run_seed — re-rolled at random, or taken from forced_seed. Every hash
	   site mixes it in, so all downstream content (blocks, crocodiles, road,
	   coins) comes out of that one number.
	2. Clear the road station cache — its entries were computed with the OLD seed
	   and would poison the new road (the cache is "correct forever" only while the
	   seed is constant). Reset the bounds to the empty sentinel (min > max) exactly
	   as declared, so the next _road_extend_to_x re-seeds station 0. Also clear both
	   pending queues — anything queued was computed for the old world.
	3. Free every active chunk and clear the dictionary — old-world geometry.
	4. Rebuild around chunk `around` (the spawn chunk (0,0) unless a caller says
	   otherwise) via update_chunks — which floors that chunk + SYNC_RING ring 1
	   SYNCHRONOUSLY and queues everything, content included, for progressive
	   fill. The respawned player is teleported into that chunk this SAME frame,
	   so that ring-1 ground is the load-bearing guarantee that they land on solid
	   new-world ground instead of falling through a hole; the scenery around them
	   arrives over the next few frames, exactly as it does when they walk into
	   fresh territory. Setting last_player_chunk to `around` keeps _process from
	   redundantly rebuilding.
	"""
	# 1. New seed (same roll as _ready()), or the one we were handed. Both paths
	# re-roll biome_offset (set_run_seed does it), so the ground shader has to be
	# re-fed immediately after — otherwise the new run's rivers would be walked
	# through while the OLD run's blue bands are drawn.
	if forced_seed == null:
		_roll_run_seed()
	else:
		set_run_seed(int(forced_seed))
	_apply_biome_shader_params()

	# 2. Road cache back to its declared empty state, and BOTH old-world pending
	# queues emptied (update_chunks below rebuilds them for the new world anyway;
	# clearing here just makes the invariant explicit). The removal queue in
	# particular holds bare coordinates, and step 3 is about to free everything
	# they name — leaving stale ones around a rebuild that re-uses the same
	# coordinates is how a brand-new chunk would get freed a frame later.
	road_stations = {}
	road_k_min = 1
	road_k_max = 0
	pending_chunks.clear()
	pending_removals.clear()

	# 3. Drop every old-world chunk (queue_free is the safe removal, as in remove_chunk).
	# The bulk free bypasses remove_chunk, so count it here or the telemetry
	# would under-report the single biggest removal event in the game.
	chunks_removed_total += active_chunks.size()
	for chunk_pos in active_chunks.keys():
		active_chunks[chunk_pos].queue_free()
	active_chunks.clear()
	# Nothing is owed content any more — every chunk that owed it is gone.
	bare_chunks.clear()

	# 4. Rebuild the ring around `around` synchronously (+ queue the rest) so the
	# player teleported into that chunk has ground under them this frame.
	update_chunks(around)
	last_player_chunk = around
	# The seed write above already reset the tower (set_run_seed -> _tower_reset),
	# but `last_player_chunk` was just pinned, so _process will not cross a boundary
	# and re-stream on its own — the player would arrive at the site to find no
	# building, no collision and no doorway until they walked a whole chunk away and
	# back.
	#
	# TESTED AGAINST `around`, NOT AGAINST THE PLAYER, and that distinction is the
	# whole point (codex review, 2026-08-28). `around` is where the player is ABOUT
	# to be: on a restart it is the spawn chunk they are teleported to a moment
	# later, and on a mid-run multiplayer join it is the anchor chunk they are
	# placed in — in both cases the teleport happens AFTER this call, so reading
	# `player.global_position` here measures where they used to be. Same reasoning as
	# the synchronous ring in step 4, which floors `around` for exactly that reason.
	_tower_stream(chunk_to_world(around))

	print("New run started (run_seed = %d)" % run_seed)

func build_ring_now(around: Vector2i) -> void:
	"""
	Populate the safety ring around `around` THIS FRAME instead of over the next
	few, i.e. pay back on the spot the content debt `update_chunks` normally
	leaves for the one-chunk-per-frame drain.

	@param around: chunk coordinates at the centre of the ring

	FOR THE ONE CALLER THAT PROBES THE WORLD RATHER THAN WALKING INTO IT.
	Ground-first streaming is safe for anybody who arrives on foot: the floor is
	under them immediately and the scenery catches up around them. A mid-run
	multiplayer joiner is the exception — `MpManager._apply_join_placement()`
	rebuilds the world around the group and then has `join_at()` ask the physics
	space for a clear spot and sweep the crocodiles off it, and a question asked
	of a world whose blocks and crocodiles have not been built yet gets the
	answer "all clear" for every candidate. So that path, and only that path,
	buys the ring's content up front and pays the one-frame hitch it used to pay
	anyway.

	Cost is bounded by the ring, not the render distance: 9 chunks, the exact
	build `update_chunks` used to do synchronously on every new_run.

	Stale queue entries are deliberately left alone — `create_chunk` returns
	immediately for an already-populated chunk, so the drain reaching one later
	is a no-op.
	"""
	for x in range(around.x - SYNC_RING, around.x + SYNC_RING + 1):
		for z in range(around.y - SYNC_RING, around.y + SYNC_RING + 1):
			create_chunk(Vector2i(x, z))

# ============================================================================
# DEBUG FUNCTIONS
# ============================================================================

func get_chunk_count() -> int:
	"""
	Returns the number of currently active chunks.
	Useful for performance monitoring.
	"""
	return active_chunks.size()

func _to_string() -> String:
	"""
	Debug information about the terrain system.
	"""
	return "EndlessTerrain[Chunks: %d, Player Chunk: %s]" % [
		get_chunk_count(),
		last_player_chunk
	]
