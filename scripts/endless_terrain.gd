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

## THE SUN'S SHADOW, WEB ONLY — the two numbers that kill the band's roof flicker
## (bead godot-test1-6n1). `scenes/main.tscn`'s DirectionalLight3D carries the
## DESKTOP values and is left exactly as it was; `apply_sun_shadow` overwrites
## these two on web and nothing else. The whole argument, the A/B frames and the
## rejected alternatives are `docs/style/6n1-roof-flicker.md`.
##
## WHY IT IS GATED AND NOT GLOBAL. Web ships a 1024 px directional shadow map
## (`project.godot`: `lights_and_shadows/directional_shadow/size.web`) against
## desktop's engine-default 4096. `shadow_normal_bias` is measured in TEXELS, so
## the same number is four times as much world-space offset on web — which is why
## web needed the fix at all, and why applying it to desktop is a pure cost: at
## 4096 there was no acne to remove, and a tripled offset there breaks a
## near-camera THIN caster's shadow (a lamp pole) into a stipple. Measured, and
## that is the whole of CLAUDE.md's "visual changes are web-gated".
##
## WEB_SHADOW_SPLIT_1 is the cascade split, and it is half the fix on its own.
## `directional_shadow_mode` is 1 (two PSSM splits — half the shadow passes, a web
## perf choice), but `directional_shadow_split_1` was left at Godot's default 0.1,
## which is the FOUR-split default: with two splits it gives the near cascade a
## 5.5 m bubble a third-person camera has nothing in and makes the far cascade
## carry 5.5..55 m on that 1024 px map. 0.35 moves the boundary to 19.25 m, so
## both cascades land where the houses are. It costs no extra pass.
##
## WEB_SHADOW_NORMAL_BIAS is the other half and neither works alone: the split
## alone only makes the acne bands finer, and a bias big enough alone (5.0) buys a
## clean roof by pushing the lookup off the occluder altogether — a clean frame
## that is the wrong frame.
const WEB_SHADOW_NORMAL_BIAS: float = 3.0
const WEB_SHADOW_SPLIT_1: float = 0.35

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
# THEMED SCATTERED PROPS — the constants, re-exported from TerrainProps
# ----------------------------------------------------------------------------
# The section itself (the banner, the seventeen builders and these constants'
# real declarations) moved to `scripts/terrain_props.gd` in bead
# godot-test1-ftn.2. Each name is aliased back because each is ALSO read from
# outside the prop family — the feature structures and the biome content share
# every territory palette, and PROP_MAX_STEP is read by budapest_plan.gd and two
# self-checks. This is `species_table.gd`'s `const SPECIES := SpeciesTable.SPECIES`
# precedent: the declaration has one home, and every existing reader (including
# `get_script_constant_map()`) is untouched.
const PROP_RADIUS_FACTOR := TerrainProps.PROP_RADIUS_FACTOR
const PROP_MAX_STEP := TerrainProps.PROP_MAX_STEP
const PROP_BOULDER_A := TerrainProps.PROP_BOULDER_A
const PROP_BOULDER_B := TerrainProps.PROP_BOULDER_B
const PROP_RUIN_STONE := TerrainProps.PROP_RUIN_STONE
const PROP_HAY := TerrainProps.PROP_HAY
const PROP_CRATE := TerrainProps.PROP_CRATE
const PROP_SANDSTONE_A := TerrainProps.PROP_SANDSTONE_A
const PROP_SANDSTONE_B := TerrainProps.PROP_SANDSTONE_B
const PROP_BONE := TerrainProps.PROP_BONE
const PROP_MOSS_ROCK := TerrainProps.PROP_MOSS_ROCK
const PROP_MOSS_CAP := TerrainProps.PROP_MOSS_CAP
const PROP_STUMP := TerrainProps.PROP_STUMP
const PROP_LOG := TerrainProps.PROP_LOG
const PROP_SCREE_A := TerrainProps.PROP_SCREE_A
const PROP_SCREE_B := TerrainProps.PROP_SCREE_B
const PROP_CAIRN := TerrainProps.PROP_CAIRN
const CITY_PLASTER_A := TerrainProps.CITY_PLASTER_A
const CITY_PLASTER_B := TerrainProps.CITY_PLASTER_B
const CITY_ROOF_TILE := TerrainProps.CITY_ROOF_TILE
const CITY_ROOF_SLATE := TerrainProps.CITY_ROOF_SLATE
const CITY_METAL := TerrainProps.CITY_METAL
const CITY_LAMP_AMBER := TerrainProps.CITY_LAMP_AMBER
const CITY_LAMP_RED := TerrainProps.CITY_LAMP_RED
const CITY_LAMP_GREEN := TerrainProps.CITY_LAMP_GREEN
const SNOW_ICE_A := TerrainProps.SNOW_ICE_A
const SNOW_ICE_B := TerrainProps.SNOW_ICE_B
const SNOW_PACK := TerrainProps.SNOW_PACK
const SNOW_DEADWOOD := TerrainProps.SNOW_DEADWOOD

# ----------------------------------------------------------------------------
# BIOME CONTENT TUNING — the constants, re-exported from TerrainBiomes
# ----------------------------------------------------------------------------
# The section itself (the banners, the salts and these constants' real
# declarations) moved to `scripts/terrain_biomes.gd` in bead godot-test1-ftn.27.
# Each name is aliased back because each is ALSO read from outside the biome
# family — sibling spawners, the city plan and self-checks read them off this
# file (including `get_script_constant_map()`). This is the PROP_* block's
# precedent above: the declaration has one home, and every existing reader is
# untouched.
const DESERT_BLOCK_KEEP_EVERY := TerrainBiomes.DESERT_BLOCK_KEEP_EVERY
const FOREST_TREES_MAX := TerrainBiomes.FOREST_TREES_MAX
const MOUNTAIN_ROAD_CLEARANCE := TerrainBiomes.MOUNTAIN_ROAD_CLEARANCE
const TREE_LEAF_COLOR := TerrainBiomes.TREE_LEAF_COLOR
const TREE_LEAF_COLOR_WARM := TerrainBiomes.TREE_LEAF_COLOR_WARM
const TREE_CANOPY_YAW_STEP := TerrainBiomes.TREE_CANOPY_YAW_STEP
const TREE_TRUNK_TILT_MAX := TerrainBiomes.TREE_TRUNK_TILT_MAX
const CITY_HOUSE_WIDTH_MAX := TerrainBiomes.CITY_HOUSE_WIDTH_MAX
const CITY_HOUSE_DEPTH_FACTOR_MAX := TerrainBiomes.CITY_HOUSE_DEPTH_FACTOR_MAX
const CITY_HOUSE_HEIGHT_MAX := TerrainBiomes.CITY_HOUSE_HEIGHT_MAX
const CITY_ROOF_RISE_FACTOR := TerrainBiomes.CITY_ROOF_RISE_FACTOR
const MAMMOTH_EDGE_MARGIN := TerrainBiomes.MAMMOTH_EDGE_MARGIN
const OASIS_PALM_FROND_COUNT := TerrainBiomes.OASIS_PALM_FROND_COUNT
const MAMMOTH_RADIUS := TerrainBiomes.MAMMOTH_RADIUS
const MOUNTAIN_AVOID_RADIUS := TerrainBiomes.MOUNTAIN_AVOID_RADIUS
const MOUNTAIN_HEIGHT_MAX := TerrainBiomes.MOUNTAIN_HEIGHT_MAX
const MOUNTAIN_MIN_LAYER_HEIGHT := TerrainBiomes.MOUNTAIN_MIN_LAYER_HEIGHT
const CITY_ROOF_EAVES := TerrainBiomes.CITY_ROOF_EAVES
const CITY_ROOF_THICKNESS := TerrainBiomes.CITY_ROOF_THICKNESS

# ----------------------------------------------------------------------------
# THEMED FEATURE STRUCTURES — the two tables that could not leave
# ----------------------------------------------------------------------------
# The section's banner, its four role builders and its STRUCT_GATE_* / MOUND_*
# knobs moved to `scripts/terrain_structures.gd` in bead godot-test1-ftn.3. The
# two tables below did NOT, and the reason is a hard one rather than a
# preference: they are KEYED BY `Biome`, an enum declared in this file, and a
# `const` in another script cannot name it (`terrain.Biome.X` resolves on an
# INSTANCE, which no const initialiser has). A table keyed by the world engine's
# own enum is world-engine data anyway; `TerrainStructures` reads these two off
# the terrain it is already handed, and takes the chosen `theme` as a plain
# parameter exactly as the four role builders always did.
#
# NOTHING ELSE IS ALIASED BACK, and that is a MEASUREMENT rather than a change of
# heart from bead ftn.2's wholesale re-export: the seven knobs are read nowhere
# but the builders that moved with them. The palette names below are this file's
# own TerrainProps aliases, so they read exactly as they did.

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
		"gate_style": TerrainStructures.STRUCT_GATE_ARCH,
	},
	# DESERT — a temple bleached by the sun. The lane becomes a COLONNADE (column
	# pairs, half of them still carrying their lintel), which keeps the sprint
	# lane intact while reading nothing like a wall.
	Biome.DESERT: {
		"stone_a": PROP_SANDSTONE_A, "stone_b": PROP_SANDSTONE_B, "trim": PROP_SANDSTONE_B,
		"cap": Color(0.0, 0.0, 0.0, 0.0),
		"gap_chance": 0.08, "double_chance": 0.10,
		"lane_spaced": true, "lintel_chance": 0.55,
		"gate_style": TerrainStructures.STRUCT_GATE_LINTEL,
	},
	# FOREST — overgrown stone and dead wood. The lane is a corridor of standing
	# dead trunks; the gate is a felled giant you can walk along.
	Biome.FOREST: {
		"stone_a": PROP_MOSS_ROCK, "stone_b": PROP_STUMP, "trim": PROP_LOG,
		"cap": PROP_MOSS_CAP,
		"gap_chance": 0.25, "double_chance": 0.15,
		"lane_spaced": true, "lintel_chance": 0.0,
		"gate_style": TerrainStructures.STRUCT_GATE_LOG,
	},
	# MOUNTAIN — a stone fort. Solid (no gaps), heavily battlemented, capped in
	# pale slab; no mound, because the massifs are the hills here.
	Biome.MOUNTAIN: {
		"stone_a": PROP_SCREE_A, "stone_b": PROP_SCREE_B, "trim": PROP_SCREE_B,
		"cap": PROP_CAIRN,
		"gap_chance": 0.0, "double_chance": 0.45,
		"lane_spaced": false, "lintel_chance": 0.0,
		"gate_style": TerrainStructures.STRUCT_GATE_LINTEL,
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
		"gate_style": TerrainStructures.STRUCT_GATE_LINTEL,
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
		"gate_style": TerrainStructures.STRUCT_GATE_ARCH,
	},
}

## Enable/disable crocodile spawning on terrain
@export var spawn_crocodiles: bool = true

## Number of crocodiles to spawn per chunk
## Higher values = more dangerous terrain!
##
## 10 -> 4 -> 3 (owner pacing adjustment).
## This is a DESIGN change, not an optimization — the one sanctioned way croc
## counts move. The arithmetic behind the count: a chunk is 50 m square and the
## crocodile's detection radius is 15 m, so ten bodies tiled the 2500 m^2 with
## overlapping detection discs and left nowhere to stand. Three leaves gaps you
## can rest in while a chunk you cross still holds a threat.
##
## NOT THE FINAL COUNT since bead godot-test1-7ed: spawn_crocodiles_in_chunk adds
## the distance gradient to this and then HALVES the sum (owner, 2026-09-02). Read
## this as the gradient's base; the real per-chunk count is the target there.
@export var crocodiles_per_chunk: int = 3

## Minimum distance between crocodiles (in meters)
@export var min_crocodile_spacing: float = 7.0

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
# HUNTER ROBOTS (epic godot-test1-9rm — the corporation's retrieval units)
# ----------------------------------------------------------------------------
##
## THE ONE PREDATOR THAT IS NOT DISPATCHED ON A BIOME. Every other species in
## piglet_crocodile_ai.SPECIES reaches the world through BIOME_SPECIES: the band
## picks the animal, and that lookup is deliberately draw-free because the chunk's
## crocodile RNG is one shared stream. A hunter is not a band's animal — the
## corporation hunts EVERYWHERE — so it gets its own spawner instead, and being
## biome-blind is what makes that spawner free of any dispatch at all.
##
## THE HARD RULE THIS SECTION EXISTS TO HONOUR (CLAUDE.md, determinism): the
## hunter takes its OWN hash stream, with its own salt and its own coordinate
## primes, and the crocodile stream is left BYTE-IDENTICAL. One extra draw from
## the chunk RNG would slide every crocodile in the world to a new spot — the same
## reason BIOME_SPECIES, CITY_CROC_DIVISOR and DESERT_BLOCK_KEEP_EVERY are all
## branch-on-a-pure-function rather than a roll. enemy_spawn_selfcheck's check 12
## is the A/B that proves it rather than asserting it: the same field generated
## with hunters on and off, crocodile positions digested from both.
##
## Structurally this is the artifact / camp / chest / landmark recipe, one feature
## over: an independent-stream rarity roll, then a candidate loop judged against
## the finished `obstacles` list, with every rejection a POST-DRAW skip.

## Enable/disable hunter spawning. Its own flag rather than a branch inside
## `spawn_crocodiles`, because it is also the A/B switch check 12 flips: with it
## false the hunter stream is never touched at all and every crocodile must come
## out where it already was.
@export var spawn_hunters: bool = true

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
## the number).
##
## 30 -> 65 IN PHASE 13, because the HQ became the ten-storey building the owner
## asked for: `TowerShell.OUTER_HALF` is 40, so the keep's own corners reach
## 40 * sqrt2 = 56.6 m, and the yard slab around it reaches 63.6 m. 65 is that plus
## a metre of margin — it is ~2.6 chunks across and costs the field ~5.3 chunks of
## content, once, in a whole world.
##
## IT IS ALSO THE DRY DISC AND THE SHADER'S RIVER MASK (see below and
## `_apply_biome_shader_params`), so growing it grows the tinted band that gets
## suppressed under the compound. That is wanted: the yard grew with the building.
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
const TOWER_RADIUS: float = 65.0

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

## THE DRY DISC — rivers do not run under the tower.
##
## The site is a CONSTANT (owner ruling 2026-08-29: "Gastro HQ shouldn't be seed
## randomized, we can plan it once and forever"), so the building can no longer be
## nudged out of the water — the water has to get out of its way instead.
## is_river_at() therefore answers false everywhere inside TOWER_RADIUS of the
## site, and the ground shader masks the blue band over the same disc.
##
## WHY MASK RATHER THAN MOVE: is_river_at() ignores Y by contract (the world is
## flat and a river is a tint), and the player's wade test is XZ-only, so a tower
## standing on a river band wades on every floor. One boolean disc costs a length()
## per call and buys a fixed, hand-plannable address.
##
## CPU/GPU PARITY (CLAUDE.md): the mask is ONE extra step in both languages —
## is_river_at() below and ground.gdshader's fragment(), fed the same centre and
## radius by _apply_biome_shader_params. Edit the two together, and keep the CPU
## side's distance going through Vector2 (fp32) like the rest of the noise port.
## The seam at the rim is a hard circle in both, which is what makes them agree;
## it sits under the shell and its yard, where nothing looks at the ground.

## How near the player must come to tower_site() before the shell is INSTANCED
## (metres). Phase 2's lazy-load radius.
##
## Generous on purpose, and the generosity is the whole design. The shell is one
## scene of fifteen boxes — a rounding error next to a chunk — so the cost of
## building it early is nothing, while the cost of building it LATE is a building
## popping into existence in front of the player.
##
## 320 -> 360 IN PHASE 13, and the arithmetic is why. This is checked only when the
## player crosses a CHUNK boundary (50 m), so the worst case instances the tower a
## whole chunk INSIDE the radius: 360 - 50 = 310 m from its centre. The FACADE is
## nearer than the centre by `TowerShell.OUTER_HALF`, which phase 13 took from 10 m
## to 40 m — so the nearest stone appears 270 m out, still clear of the desktop
## render distance (250 m) and of both fog ranges. At the old 320 that same worst
## case put the new facade at 230 m: inside render distance, i.e. the impostor
## swapping for the lit shell in plain view. (Found by codex review, 2026-08-29.)
##
## AND IT IS THE OUTER EDGE OF THE CROSS-FADE. There is no swap any more (bead
## godot-test1-rgt): the horizon impostor dissolves across
## TowerShell.IMPOSTOR_FADE_FAR -> _NEAR, and that band has to sit INSIDE the worst
## case, or a player crosses into it with a half-faded silhouette and no building
## behind it yet. The worst case is THREE terms, not one: 360, minus the chunk
## DIAGONAL (a boundary crossing can be corner-to-corner, so sqrt(2) * 50 = 70.7,
## not 50), minus the shell's own footprint radius (63.6 — the fade is per PIXEL and
## opens on the nearest corner, not on the centre this radius measures). That is
## 225.6 m against a fade that starts at 220. tower_shell_selfcheck check 9 computes
## all three off the live constants, so shrinking any of them fails the build rather
## than the view.
const TOWER_LOAD_RADIUS: float = 360.0

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
##
## 0.4 -> 0.2 with the ground density (owner pacing ruling, 2026-08-29): a
## climbable top is where you go to get OFF the ground, so a guard on two in five
## of them made the rest spots themselves populated. One in five still means the
## high ground has to be read before it is trusted.
@export var platform_crocodile_chance: float = 0.2

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
## slice = road_coin_slots * road_coin_chance * 0.7 — the 0.7 is the deterministic 30%
## THINNING at the bottom of _road_coins_at (bead godot-test1-7ed), which is a post-draw
## skip and therefore not expressible as a lower chance here: lowering the chance would
## re-scatter every surviving coin, and the point of the thinning is that it does not.
## Lower the chance for a sparser, less obvious trail; raise it (or the slots) for a denser swath. Keeping the average near ~1 makes the
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
## THE ROAD'S CONSTANTS MOVED TO `CoinRoad` (bd godot-test1-ftn.7), and exactly
## ONE of them is aliased back — the `species_table.gd` / `terrain_props.gd`
## precedent of re-exporting only what is really read from outside.
##
## `ROAD_TERMINAL_X` is read four ways by five other files: through
## `get_script_constant_map()` (budapest_selfcheck, landmark_sites_selfcheck),
## as `TERRAIN_SCRIPT.ROAD_TERMINAL_X` (field_bridge_selfcheck, six sites), as
## `StubTerrain.TERRAIN.ROAD_TERMINAL_X` (wade_selfcheck) and by name in
## enemy_spawn_selfcheck's own banner. A `const` alias keeps every one of those
## answering, `get_script_constant_map()` included.
##
## The other eight — ROAD_RESTORE, ROAD_WORLD_SEED, ROAD_COIN_SEED,
## ROAD_GEM_CHANCE, ROAD_WIDTH_FREQ, ROAD_NARROW_STATIONS,
## ROAD_NARROW_FLOOR_FACTOR, ROAD_COIN_LONG_JITTER — were measured, not assumed:
## they appear outside `coin_road.gd` only in PROSE (two comments in
## `terrain_features.gd`, one in `terrain_predators.gd`, one in `coin.gd`), so
## they are family-internal and stay there alone.
const ROAD_TERMINAL_X := CoinRoad.ROAD_TERMINAL_X

# ----------------------------------------------------------------------------
# FIELD BRIDGES — nine measured const aliases into `FieldBridges` (bd godot-test1-ftn.28)
# ----------------------------------------------------------------------------
const FIELD_BRIDGE_TOP := FieldBridges.FIELD_BRIDGE_TOP
const FIELD_BRIDGE_THICKNESS := FieldBridges.FIELD_BRIDGE_THICKNESS
const FIELD_BRIDGE_HALF_WIDTH := FieldBridges.FIELD_BRIDGE_HALF_WIDTH
const FIELD_BRIDGE_MAX_SPAN := FieldBridges.FIELD_BRIDGE_MAX_SPAN
const FIELD_BRIDGE_PROBE_STEP := FieldBridges.FIELD_BRIDGE_PROBE_STEP
const FIELD_BRIDGE_FOOT_PUSH_MAX := FieldBridges.FIELD_BRIDGE_FOOT_PUSH_MAX
const FIELD_BRIDGE_PARAPET_HEIGHT := FieldBridges.FIELD_BRIDGE_PARAPET_HEIGHT
const FIELD_BRIDGE_PYLON_WIDTH := FieldBridges.FIELD_BRIDGE_PYLON_WIDTH
const FIELD_BRIDGE_PYLON_RISE := FieldBridges.FIELD_BRIDGE_PYLON_RISE

## Feature flag, `spawn_hunters`' precedent: it exists so field_bridge_selfcheck
## can generate the same chunk with the bridges OFF and prove that nothing else
## in the world moved by a single box (check 6's A/B).
@export var spawn_field_bridges: bool = true


# ----------------------------------------------------------------------------
# THE PRIVATE-STREAM FEATURES — the three feature flags
# ----------------------------------------------------------------------------
# These three stayed when the families moved (bead godot-test1-ftn.4): an
# `@export` is inspector-facing world-engine configuration and a static library
# has no inspector, so they sit with `spawn_crocodiles` and the rest of the
# flags. `TerrainFeatures` reads them off the terrain it is handed.
@export var spawn_artifacts: bool = true
@export var spawn_camps: bool = true
@export var spawn_chests: bool = true

# ----------------------------------------------------------------------------
# THE PRIVATE-STREAM FEATURES — what anything outside the family still reads
# ----------------------------------------------------------------------------
# The artifacts, the nomad camps and the treasure chests moved to
# `scripts/terrain_features.gd` in bead godot-test1-ftn.4, salts and coordinate
# primes with them. These seventeen names are aliased back because each is read
# from OUTSIDE that family — the three SALTs by landmark_builders.gd and
# landmark_toast.gd, the three CHEST_* by treasure_chest.gd and mp_manager.gd,
# and the rest by spawners still here. Measured, not assumed: the other
# fifty-nine constants are read nowhere but the builders that moved with them,
# so they are not re-exported. `species_table.gd`'s precedent.
const ARTIFACT_SALT := TerrainFeatures.ARTIFACT_SALT
const ARTIFACT_RADIUS := TerrainFeatures.ARTIFACT_RADIUS
const ARTIFACT_ROAD_CLEARANCE := TerrainFeatures.ARTIFACT_ROAD_CLEARANCE
const ARTIFACT_EDGE_MARGIN := TerrainFeatures.ARTIFACT_EDGE_MARGIN
const ARTIFACT_GLOW_COLOR := TerrainFeatures.ARTIFACT_GLOW_COLOR
const ARTIFACT_GLOW_ENERGY := TerrainFeatures.ARTIFACT_GLOW_ENERGY
const ARTIFACT_MAX_ACCENTS := TerrainFeatures.ARTIFACT_MAX_ACCENTS
const CAMP_SALT := TerrainFeatures.CAMP_SALT
const CAMP_ROAD_CLEARANCE := TerrainFeatures.CAMP_ROAD_CLEARANCE
const CAMP_EDGE_MARGIN := TerrainFeatures.CAMP_EDGE_MARGIN
const CAMP_EMBER_COLOR := TerrainFeatures.CAMP_EMBER_COLOR
const CAMP_EMBER_ENERGY := TerrainFeatures.CAMP_EMBER_ENERGY
const CHEST_SALT := TerrainFeatures.CHEST_SALT
const CHEST_ROAD_CLEARANCE := TerrainFeatures.CHEST_ROAD_CLEARANCE
const CHEST_COINS_MIN := TerrainFeatures.CHEST_COINS_MIN
const CHEST_COINS_MAX := TerrainFeatures.CHEST_COINS_MAX
const CHEST_BURST_DURATION := TerrainFeatures.CHEST_BURST_DURATION

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
##   chest     ~1 chunk in 13   a 1.3 m box, 6-11 coins in a burst, NO GEM
##   artifact  ~1 chunk in 23   huge ruin, 2-4 coins AND the one guaranteed GEM
##   camp      ~1 chunk in 31   a whole village, 1-3 coins, no gem
##   landmark  48 IN THE WORLD   a famous place, 2-4 coins, NO GEM, plus a fact
##
## The landmark row is the odd one out and has been since bead godot-test1-bcf:
## the other three are RATES and it is a CENSUS. There are as many landmarks as
## there are registry rows, ever, and where each stands is THE MUSEUM MILE below.
## It still sits at the bottom of the hierarchy — 41 of 48 built over a whole
## world against a chest every 13 chunks — and it is the only one of the four you
## can set out to find.
##
## The four pairs were 8-15 / 3-5 / 2-4 / 3-5 until bead godot-test1-7ed trimmed
## every one of them by ~30% (owner, 2026-09-02). The HIERARCHY is what matters
## here and it is unchanged — they were scaled together, not re-ranked.
##
## REWARD DECISION — a small coin ring (LANDMARK_COIN_MIN..MAX, 2-4 ordinary
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
## Structurally this is the chest/camp/artifact recipe with ONE thing changed —
## the roll (bead godot-test1-bcf; see THE MUSEUM MILE further down):
##   - landmark_sites()           ONE SITE PER KIND for the whole run, a pure
##                                function of run_seed built once and memoized.
##   - _landmark_at()             the REVERSE LOOKUP alone — one Dictionary
##                                lookup in that table, so it consumes ZERO draws
##                                from the shared chunk RNG and, unlike the roll
##                                it replaced, evaluates no hash per chunk either.
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
## place; this file holds the POLICY that places them: WHERE each one stands,
## which hash stream decides it, how far off the road they sit, how the reward
## ring and the crocodile-exclusion footprint are sized. Adding a famous place is ONE
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

## Kill switch for the WAYPOINT circles (epic godot-test1-sc6), the same shape as
## the one above and for the same reason: `waypoint_selfcheck` check 2 builds a
## site-free chunk with it on and off and demands the two be byte-identical down
## to the crocodile positions, which is the half of the no-draw proof a text scan
## cannot give. Read by `TerrainWaypoints.spawn_waypoint_in_chunk`.
@export var spawn_waypoints: bool = true

## THE RARITY ROLL IS RETIRED, and `LANDMARK_CHANCE` with it (bead
## godot-test1-bcf). Until 2026-09-04 a chunk rolled 0.21 * scarcity against its
## own LANDMARK_SALT stream and then drew a kind uniformly from the registry;
## five waves of measurement across 38 seeds and 22,000 chunks tuned that number
## from 0.15 to 0.21 to hold the built rate in a "1 landmark per 40-60 chunks"
## band. The owner's ruling ("each type exists once in our world") makes a RATE
## the wrong shape of answer entirely: there is no population to be rare within
## any more, so the number, its band and its sweeps all went with it. See THE
## MUSEUM MILE below for what replaced them.
##
## ONE FINDING FROM THOSE SWEEPS OUTLIVED THE CONSTANT and is worth keeping,
## because it is the property that makes appending places to the registry free:
## `randi_range` consumes exactly ONE draw whatever its range, MEASURED rather
## than argued — the same 17x17 field x 60 seeds run twice against the same code,
## once with all 48 registry entries and once with landmark_builders.gd checked
## back out at 38, produced BIT-IDENTICAL worlds (3286 rolled, 359 built, digest
## 403935944 both times). The site table below keys on the kind index directly, so
## the property it protects — appending a place moves nothing else — now holds by
## construction rather than by measurement.

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

## ============================================================================
## THE MUSEUM MILE — ONE SITE PER KIND, AND THE CHUNK DOES A REVERSE LOOKUP
## ============================================================================
##
## Owner, 2026-09-04 (bead godot-test1-bcf): *"for landmarks they should be
## unique, each type exists once in our world"*. Budapest's CITY_LANDMARKS were
## always unique — they are 22 authored slots — and the FIELD registry was not:
## the old `_landmark_at` rolled a rarity chance per chunk and then drew a kind
## uniformly from the same chunk-local stream, so an infinite field repeated
## every kind forever and two Eiffel Towers 300 m apart was luck rather than a
## bug anybody could point at.
##
## SO THE PLACEMENT IS INVERTED. Instead of "does this chunk have a landmark, and
## if so which", the question is "where does kind K stand this run" — asked once
## per run for all 48 kinds, cached, and READ BACK BY CHUNK COORDINATE
## (`landmark_sites()` is chunk -> kind; `_landmark_at` is one Dictionary lookup
## in it). Three properties fall out of that shape and all three are load-bearing:
##
##   * UNIQUENESS IS STRUCTURAL. A kind has one site or none. It is not a rate
##     that happens to be low, so no seed, no walk and no field size can produce
##     a second Colosseum.
##   * IT COSTS THE CHUNK STREAM NOTHING. Not one RNG draw is taken from any
##     shared stream, and not one hash is even evaluated per chunk — the table is
##     built ONCE per run from `run_seed` alone. Crocodiles, hunters, bosses,
##     coins, props, camps, chests and artifacts are byte-identical to a build
##     with `spawn_landmarks = false`, which is what the A/B measures.
##   * A SITE IS COMPUTABLE WITHOUT ITS CHUNK. `landmark_site(kind)` answers for a
##     chunk that has never streamed in, which is what a future "unexplored
##     landmark" minimap mark would need. Not this bead.
##
## WHERE THE SITES GO. The road is the run's spine — it starts at the HQ
## (`tower_site().x`, -400) and every road consumer stops at the terminal station
## `T` (ROAD_TERMINAL_X, 1450), so ~1850 m of centreline is the corridor a run
## actually walks. That is the MUSEUM MILE: as many kinds as `LANDMARK_MILE_SPACING`
## fits get a slot on it, spread evenly by METRES OF X and looked up as stations
## (the road bosses' idiom — X is strictly increasing in `k`, so a station is a
## place), offset 60-120 m to one side and alternating sides by kind parity so the
## walk is never all-left. Everything that does not fit the mile goes into an ANNULUS
## 0.5-2.5 km off the same centreline, on the same hash — a wanderer finds those,
## and nothing is unreachable.
##
## SCARCITY DOES NOT APPLY HERE ANY MORE, and that is a decision rather than an
## omission. `scarcity_at` thins a POPULATION: it answers "how much of what would
## be here is still here" and the three shipped forms (chance * k, roundi(n * k),
## the per-object `_scarcity_keep` skip) all remove one of many. A thing that
## exists exactly ONCE IN THE WORLD is neither thinned nor unthinned — multiplying
## its single existence by k is a coin flip on whether the Eiffel Tower is in this
## run at all, which is not a gradient, it is a lottery. The gradient's own
## purpose (owner ruling, bead godot-test1-bn8: demotivate walking away from
## Budapest) is served by the mile instead: the sites are ON the corridor and in a
## 2.5 km annulus around it, i.e. all of them are inside the k > 0 field anyway,
## and the far field beyond SCARCITY_PLAIN_DISTANCE (4 km) holds no site at all.
## `scarcity_selfcheck` keeps `_landmark_at` in its per-biome sweep unchanged and
## still measures 0 out there — see the note in its `_check_every_biome`.
##
## The rest of the pipeline is untouched: `spawn_landmark_in_chunk` still runs the
## LANDMARK_PLACE_TRIES candidate loop against `_biome_spot_ok` where `obstacles`
## exists, still batches into the chunk's one MultiMesh, still perches its coin
## ring and still appends one non-climbable footprint.

## Fixed salt for the SITE stream, distinct from LANDMARK_SALT so the site table
## and anything else keyed on a landmark cannot share a lattice.
const LANDMARK_SITE_SALT: int = 0x51_7E5  # "SITES"-ish; arbitrary fixed constant

## `landmark_site()`'s "this kind has no site this run" answer. A real chunk
## coordinate is bounded by the world's float range divided by chunk_size, so this
## is unreachable; callers must test rather than compare distances to it.
const LANDMARK_SITE_NONE: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)

## Metres of ROAD X per museum-mile slot.
##
## THE BEAD GUESSED 250-400 m AND THAT WAS ARITHMETIC, NOT DESIGN: it assumed the
## road terminal sat at x = +1600..+3800, i.e. a 2.0-4.2 km corridor, and derived
## "5-17 slots" from it — then asked its acceptance for TWELVE kinds STANDING in
## the corridor of a run. ROAD_TERMINAL_X is really 1450 and the corridor runs
## from station 0, so it is 1450 m — a third of what the bead assumed at the top
## end. The COUNT is the half of that pair that was actually specified, so the
## count is what this follows.
##
## 75 m fits 19 slots in 1450 m, and it takes nineteen SITES to stand twelve
## LANDMARKS: a site whose chunk has no room for the shape builds nothing (the
## whole of LANDMARK_PLACE_TRIES' note). Measured 13 / 15 / 14 corridor landmarks
## built over `landmark_sites_selfcheck`'s three seeds, against its floor of 12.
##
## Consecutive mile landmarks alternate sides at 60-120 m out, so the real
## walk-to-walk distance is 120-190 m — a monument every minute or two on the
## trail, which is the "museum mile" the bead names, and still an OFF-ROAD detour
## (LANDMARK_ROAD_CLEARANCE is 22 m and the nearest site is 60).
const LANDMARK_MILE_SPACING: float = 75.0

## Lateral offset band for a MILE site: far enough off the trail to be a detour,
## near enough to be seen from it. Both are >> LANDMARK_ROAD_CLEARANCE (22).
const LANDMARK_MILE_LATERAL_MIN: float = 60.0
const LANDMARK_MILE_LATERAL_MAX: float = 120.0

## Lateral offset band for a FIELD site — the annulus the kinds that do not fit
## the mile go into, the bead's "0.5-2.5 km off the road". Inside
## SCARCITY_PLAIN_DISTANCE (4 km) by construction, so every kind stands in ground
## the gradient still furnishes.
const LANDMARK_FIELD_LATERAL_MIN: float = 500.0
const LANDMARK_FIELD_LATERAL_MAX: float = 2500.0

## Deterministic re-hash attempts before a kind gives up and simply has no site
## this run. A site is rejected for standing in the HQ disc, the Budapest rect,
## the spawn bubble, a river band or a chunk another kind already took; each
## retry is a new hash on (kind, attempt, run_seed), never a draw. 32 is far more
## than it takes: `landmark_sites_selfcheck` reports 144 sites over three seeds,
## i.e. all 48 kinds sited in all three worlds, with none of the four rules
## running a kind out of attempts.
const LANDMARK_SITE_TRIES: int = 32

## Candidate spots tried inside a chunk before giving up. Every try failing means
## NO LANDMARK — the same call artifacts and camps both make, and the right one:
## the Eiffel Tower sticking out of a mountain massif reads far worse than a
## chunk without one.
##
## RAISED 4 -> 200 BY THE MUSEUM MILE, and the reason is that the MEANING OF A
## FAILURE CHANGED. While every chunk rolled, a 10.7% survival rate was a RATE:
## the failures were absorbed by LANDMARK_CHANCE and the built density was tuned
## against the survivors. With one site per kind a failed candidate loop means
## that kind is ABSENT FROM THE WORLD, so the tries stopped being a tuning knob
## and became a completeness budget.
##
## MEASURED over the 48 sites of three seeds (20260904 / 777 / 4242), kinds built
## out of 48 (and of those, kinds standing in the road corridor), at the
## row-radius test below and at an earlier, slightly wider mile spacing:
##     4 tries:   22 / 19 / 26   (corridor 6 / 4 / 5)  — the old constant
##    40 tries:   40 / 39 / 39   (corridor 14 / 13 / 12)
##   200 tries:   43 / 41 / 41   (corridor 15 / 14 / 13)
## That sweep predates the mile's final spacing AND ran on the check's own
## hand-rolled chunk order rather than `create_chunk`, so it is the SHAPE of the
## curve that it measures, not the row; the shipped numbers are 37 / 43 / 43
## built, corridor 13 / 15 / 14 — `landmark_sites_selfcheck` prints them.
## and it plateaus there — the remainder are chunks where a 4-9 m circle genuinely
## does not fit (field CITY band chunks are two thirds of them). 200 tries is FREE
## because only ~48 chunks in a whole world ever run this loop, and each try is a
## `randf_range` pair plus one `_biome_spot_ok` over ~25 footprints. No other
## stream can see them either: the loop draws from the landmark's OWN private RNG.
const LANDMARK_PLACE_TRIES: int = 200

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
## up to BOSS_LATERAL_MAX (9.0 m) across it, so BOTH legs belong in the bound:
##     LANDMARK_ROAD_CLEARANCE > LANDMARK_RADIUS + sqrt(BOSS_FORWARD_OFFSET^2 + BOSS_LATERAL_MAX^2)
##     22.0                    > 9.5             + sqrt(8.0^2 + 9.0^2) = 9.5 + 12.04 = 21.54  ✓
## i.e. 0.46 m of slack — it was 3.56 before bead godot-test1-9k7 widened the
## lateral band from 4.0 to 9.0 so a 9x boss could find a clear spot, and this is
## the TIGHTEST of the two boss exclusions (the camp's has 0.56). That single
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
## 3-5 -> 2-4, the 30% reward trim of bead godot-test1-7ed.
const LANDMARK_COIN_MIN: int = 2
const LANDMARK_COIN_MAX: int = 4
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

## Noise-space half-width of the soft colour transition between biomes, used as
## a smoothstep radius in the ground shader. Purely cosmetic: gameplay reads the
## hard thresholds above, the eye reads this blend.
const BIOME_BLEND: float = 0.05

# ----------------------------------------------------------------------------
# FIELD ALTITUDE — THE SPIKE FLAG (bead godot-test1-ope.1)
# ----------------------------------------------------------------------------
#
# THE WORLD IS STILL FLAT. The implementation and 20 ALT_* constants live in
# scripts/terrain_altitude.gd. With FIELD_ALTITUDE false the world is byte for
# byte today's flat world: height_at() early-returns 0.0 before touching any
# noise, _ensure_chunk_ground builds the same BoxShape3D it always did, and
# _apply_biome_shader_params() pushes alt_enabled = 0.0 so the shader displaces
# nothing. THAT IS THE MERGE CONDITION — the flag ships false and every
# self-check is green with it false.
#
# Flipping it true is how the spike's numbers are taken (see
# docs/field-altitude-spike.md): the red-check list, the per-chunk collision
# build cost and the web F3 readings all come from a local flip that is never
# committed.
const FIELD_ALTITUDE: bool = TerrainAltitude.FIELD_ALTITUDE

## THE SELF-CHECK SEAM for the flag above. `altitude_selfcheck.gd` drives both
## the flag-off and the flag-on paths in ONE process, which a `const` alone
## cannot express — so alt_enabled() is the single gate every altitude path
## reads and this var is the only other thing it looks at. THE GAME NEVER WRITES
## IT: nothing outside a self-check may set it, which is what keeps "the flag is
## a const" true in every shipped build.
var alt_force: bool = false

## The sizes of ground.gdshader's two Budapest array uniforms, restated here for
## the ONE thing GDScript can do that GLSL cannot: fail loudly. A GLSL array is a
## fixed size, so the plan's Danube and its dry rects have to be padded to it —
## and if a future author adds a sixth polyline point or a ninth dry rect, the
## asserts in _city_river_segments() / _city_dry_rects() say so instead of the
## river quietly losing its last bend. Keep both in step with CITY_SEG_MAX /
## CITY_DRY_MAX in the shader; they are the same two-language contract as
## everything else in this pair of files.
const CITY_SHADER_SEG_MAX: int = 8
const CITY_SHADER_DRY_MAX: int = 8

## THE CITY'S CONSTANTS MOVED TO `BudapestStreamer` (bd godot-test1-ftn.8), and
## EIGHT of the forty are aliased back — the `species_table.gd` /
## `terrain_props.gd` precedent of re-exporting only what is really read from
## outside, measured with a grep rather than assumed.
##
## All eight are read through `get_script_constant_map()` on the TERRAIN script
## (`budapest_selfcheck`'s `consts[...]`, `budapest_city_selfcheck`'s, and
## `field_bridge_selfcheck`'s `TERRAIN_SCRIPT.get_script_constant_map()`), and a
## `const` alias keeps every one of those answering. The other thirty-two are
## read nowhere but the builders that moved with them.
const CITY_STREAM_SEED := BudapestStreamer.CITY_STREAM_SEED
const CITY_RAMP_THICKNESS := BudapestStreamer.CITY_RAMP_THICKNESS
const CITY_SHOPFRONT_PROUD := BudapestStreamer.CITY_SHOPFRONT_PROUD
const CITY_AWNING_PROUD := BudapestStreamer.CITY_AWNING_PROUD
const CITY_BALCONY_PROUD := BudapestStreamer.CITY_BALCONY_PROUD
const CITY_CORNICE_PROUD := BudapestStreamer.CITY_CORNICE_PROUD
const CITY_CHUNK_BOX_BUDGET := BudapestStreamer.CITY_CHUNK_BOX_BUDGET
const CITY_CHUNK_SHAPE_BUDGET := BudapestStreamer.CITY_CHUNK_SHAPE_BUDGET
const CITY_CHUNK_MS_BUDGET := BudapestStreamer.CITY_CHUNK_MS_BUDGET

# ----------------------------------------------------------------------------
# SCARCITY GRADIENT — objects thin out logarithmically with distance
# ----------------------------------------------------------------------------
##
## Plain terrain at SCARCITY_PLAIN_DISTANCE = 4000 m. Inside the union of the
## Budapest rect and the HQ-to-gate corridor k=1, at 4000 m from that union k=0,
## logarithmically: k = 1 - log(1+d/d0)/log(1+4000/d0) with d0=400 m. d is distance
## from pos to the nearest edge of the UNION (BudapestPlan.rect() plus the corridor
## box from the HQ disc to the gate). Measured k at HQ (~2 km) is ~0.25 when measured
## off the rect alone; off the union the whole corridor stays at 1.0 (see review).
##
## ONE RULE FOR EVERY BIOME (bead `godot-test1-bn8`, owner 2026-09-04: *"i see that
## object in plains rare and rare when we farther away from center hq+budapest, but
## I don't see this happening with desert and probably other biomes, it should be one
## rule for all, we should demotivate players go far away from center"*). The gradient
## used to be applied per FAMILY and several families never read k, so a desert kept
## every oasis, every dune and every mammoth on the way out while the plains emptied.
## The rule now, and the whole of it:
##
##   * EVERY CONTENT BUILDER READS k. Scattered props, feature structures,
##     artifacts, camps, chests, geo landmarks, cacti, oases, dunes, forest trees,
##     city houses / stalls / lights, snow trees and mammoth skeletons — all of
##     them, in the three forms below and no fourth one.
##   * MASSIFS ARE EXEMPT (owner ruling, same date). They are the impassable walls
##     the flat-world invariant rests on, not decoration: a far mountain band with
##     no massifs is a plains band painted grey. `_spawn_mountain_content` is
##     therefore the one biome builder with no k in it at all.
##   * PREDATORS, HUNTERS, BOSSES AND ROAD COINS ARE NEVER THINNED. Entity counts
##     are design-only, and fewer predators far out would REWARD leaving — the
##     opposite of the ruling; the road is the guide to Budapest. There are no
##     off-road CHUNK coins to thin either: every non-road coin in the world is a
##     reward inside an artifact, camp, chest or landmark, so it already vanishes
##     with the feature that carries it.
##
## THE THREE FORMS, and never a fourth:
##
##   * A COUNT TARGET becomes `roundi(target * k)` (the scattered-prop scatter).
##   * A RARITY ROLL is compared against `chance * k` — the same roll, no new draw
##     (structures, artifacts, camps, chests, oases, dunes). GEO LANDMARKS USED TO
##     BE ON THIS LINE AND ARE DELIBERATELY NOT ANY MORE: since bead
##     godot-test1-bcf each kind exists exactly ONCE IN THE WORLD, so there is no
##     population for a gradient to thin and multiplying a single existence by k
##     would be a lottery rather than a thinning. Every site is on the road
##     corridor or in a 2.5 km annulus round it, i.e. inside the k > 0 field
##     anyway; see the MUSEUM MILE banner and `scarcity_selfcheck`'s
##     `_check_every_biome`, which still measures the far field's zero.
##   * A PER-OBJECT removal inside a loop is a post-draw `continue` on
##     `_scarcity_keep()`'s own SCARCITY_SALT hash stream (cacti, forest trees,
##     city furniture, snow trees, mammoths).
##
## In all three the shared chunk / biome RNG takes exactly the draws it took
## before, which is why k = 1 near the centre regenerates byte-identically.
##
## AND THERE IS NO `if k <= 0.0: return` SHORTCUT ANY MORE, deliberately. Four
## biome builders carried one; it emitted the same nothing the per-object rolls do,
## but it emitted it for the WHOLE FUNCTION — so a builder further down that forgot
## k (the oasis, which is called from the bottom of `_spawn_desert_content`) looked
## correct at 4 km and the acceptance check could not tell the difference. The far
## field is now empty because every builder's own k says so, which is the only
## version of that measurement a mutation test can fail.
## `scripts/scarcity_selfcheck.gd` iterates the Biome enum and fails the build for
## a builder that forgets k.
const SCARCITY_PLAIN_DISTANCE: float = 4000.0
const SCARCITY_D0: float = 400.0
const SCARCITY_SALT: int = 0x5C4177 # own stream for per-object scarcity rolls
const _SCARCITY_DENOM: float = 2.3978952727983707 # log(1+4000/400) = log(11) — keep in sync with the two consts above
## HQ-to-gate corridor that keeps the tutorial road furnished: the union of this box
## and the Budapest rect is where k=1. Z half-width 200 m contains the coin road's
## real Z envelope between station 0 and ROAD_TERMINAL_X — measured max |z| 129 m
## across 200 run_seeds plus half band 10 m = 139 m, rounded to 200 m for margin.
## X runs from the HQ disc's east edge (tower_site.x - TOWER_RADIUS = -400-65=-465)
## to the rect's west edge (BUDAPEST_MIN.x=1600). Const Rect2s, no per-call alloc.
const SCARCITY_CORRIDOR_HALF_WIDTH: float = 200.0
const SCARCITY_CORRIDOR_RECT: Rect2 = Rect2(-465.0, -200.0, 2065.0, 400.0)


func scarcity_at(pos: Vector3) -> float:
	"""Pure function in [0,1]: 1 inside/near Budapest or the HQ corridor, 0 at 4 km."""
	var rect: Rect2 = BudapestPlan.rect()
	var dx := 0.0
	if pos.x < rect.position.x:
		dx = rect.position.x - pos.x
	elif pos.x > rect.position.x + rect.size.x:
		dx = pos.x - (rect.position.x + rect.size.x)
	var dz := 0.0
	if pos.z < rect.position.y:
		dz = rect.position.y - pos.z
	elif pos.z > rect.position.y + rect.size.y:
		dz = pos.z - (rect.position.y + rect.size.y)
	var d_rect := sqrt(dx * dx + dz * dz)
	# Distance to the HQ-to-gate corridor box (union half of the distance).
	var cdx := 0.0
	if pos.x < SCARCITY_CORRIDOR_RECT.position.x:
		cdx = SCARCITY_CORRIDOR_RECT.position.x - pos.x
	elif pos.x > SCARCITY_CORRIDOR_RECT.position.x + SCARCITY_CORRIDOR_RECT.size.x:
		cdx = pos.x - (SCARCITY_CORRIDOR_RECT.position.x + SCARCITY_CORRIDOR_RECT.size.x)
	var cdz := 0.0
	if pos.z < SCARCITY_CORRIDOR_RECT.position.y:
		cdz = SCARCITY_CORRIDOR_RECT.position.y - pos.z
	elif pos.z > SCARCITY_CORRIDOR_RECT.position.y + SCARCITY_CORRIDOR_RECT.size.y:
		cdz = pos.z - (SCARCITY_CORRIDOR_RECT.position.y + SCARCITY_CORRIDOR_RECT.size.y)
	var d_corridor := sqrt(cdx * cdx + cdz * cdz)
	var d := minf(d_rect, d_corridor)
	if d <= 0.0:
		return 1.0
	if d >= SCARCITY_PLAIN_DISTANCE:
		return 0.0
	return clampf(1.0 - log(1.0 + d / SCARCITY_D0) / _SCARCITY_DENOM, 0.0, 1.0)


func _scarcity_keep(chunk_pos: Vector2i, index: int, k: float) -> bool:
	"""
	The ONE home of the per-object scarcity roll — the third of the three forms in
	the banner above, and the only one that needs a hash stream of its own.

	@param chunk_pos: The chunk the object stands in. NOT the world position: a
	                  builder is sliced by nothing, and a chunk-keyed roll is what
	                  makes a revisited chunk regenerate identically.
	@param index: The object's index within its own loop, plus a per-family offset
	              where one loop's objects would otherwise share rolls with
	              another's (the city's stalls take `_i + 1000`, its lights
	              `_i + 2000`, snow's mammoths `_i + 1000`). THE OFFSETS ARE PART OF
	              THE WORLD — changing one moves every object of that family.
	@param k: scarcity_at() at the chunk's centre, read once by the caller.
	@return: true to build this object, false to thin it away.

	IT COSTS NO DRAW. The roll is a hash of (chunk, run_seed ^ SCARCITY_SALT ^
	index), not a draw from the caller's RandomNumberGenerator, so the shared
	biome / chunk stream is exactly the sequence it was before scarcity existed.

	THE CALL MUST BE A POST-DRAW `continue`, the discipline every removal in this
	file follows: put it after whatever unconditional draws the object takes and
	immediately before the first create_box. At k = 1 it never skips and the world
	is byte-identical; below 1 a thinned object's emit-time draws are skipped,
	which shifts the rest of THAT chunk — deterministic (k is pure in position)
	and intended.
	"""
	var roll := float(hash(Vector3i(
		chunk_pos.x * 96174811, chunk_pos.y * 18266587, run_seed ^ SCARCITY_SALT ^ index
	)) % 1000000) / 1000000.0
	return roll < k


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
	## croc_steering.pack_steer_point) has each animal swing to its own slot
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
	## charge (see croc_steering.charge_steer_point) is only fair if you can
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
	## predator belongs. The cougar's pounce (see croc_steering's
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
## THIS TABLE SHIPPED EMPTY, AND THAT WAS THE POINT — the seam landed with every
## boss still a crocodile and a byte-identical world, and the snow titan below was
## the first row to change an answer. It is now TOTAL over the `Biome` enum (a
## gate enemy_spawn_selfcheck asserts against the enum, so a seventh band would
## have to bring its own boss), which leaves the crocodile fallback reachable on
## exactly two paths: a station standing in a RIVER, and the degrade path for a
## row that fails to resolve. Adding a row changed no PLACEMENT anywhere:
## the dispatch is pure function calls (biome_at / is_river_at — the
## allocation-free public API, no RNG anywhere under either) inserted at a spot
## where no draw is made, so the BOSS_SEED stream consumes the same draws in the
## same order it always did. A single extra draw would slide every boss in the
## world, which is the same rule CLAUDE.md states for BIOME_SPECIES and
## CITY_CROC_DIVISOR. All six kinds land as ONE ROW here each, exactly as a
## predator lands as one row in BIOME_SPECIES.
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
	## The forest band's guardian: the GREEN DRAGON, a melee territorial boss —
	## no projectile, no behaviour arm, no speed opt-out. The second row, and the
	## cheap one: everything it needed already existed, so it is this line, a
	## SPECIES entry and a .tscn. (Forest is the densest tree cover in the world
	## and a 9x dragon is a ~6.3 m-radius body, so some forest stations will legitimately
	## find no clear candidate and place no boss at all — that is the designed
	## outcome of spawn_bosses_in_chunk's clearance walk, not a reason to loosen
	## it.)
	Biome.FOREST: {
		"species": "green_dragon",
		"scene": "res://scenes/characters/green_dragon.tscn",
	},
	## The four that make this map TOTAL over the Biome enum. From here the
	## crocodile is still the boss of a road station, but only on the two paths
	## that are not a band lookup at all: a station standing in a RIVER (the
	## is_river_at overlay above the table, the owner's "river - crocodile", which
	## overrides whatever band the noise field puts it in) and the DEGRADE path
	## for a row whose species name or scene fails to resolve. Both are still
	## measured — enemy_spawn_selfcheck check 11 fails if no station in its
	## eighty-boss walk stands in water, and boss_selfcheck drives the crocodile
	## as a subject in its own right beside every BIOME_BOSS kind — so the
	## fallback does not rot now that no biome reaches it.
	##
	## They cost what the dragon cost: one line each here, one SPECIES row each,
	## one .tscn each, and no new code anywhere. Adding them consumes no RNG draw
	## (this dispatch is pure biome_at / is_river_at calls at a point where no
	## draw is made), so every boss in the world stands exactly where it stood.
	##
	## The plains hydra, the desert naga and the mountain roc are melee and take
	## the default BOSS_CHASE_SPEED; the city clown opts into the titan's ranged
	## capability with its own ice cream. See their SPECIES rows for all of it.
	Biome.PLAINS: {
		"species": "hydra",
		"scene": "res://scenes/characters/hydra.tscn",
	},
	Biome.DESERT: {
		"species": "naga",
		"scene": "res://scenes/characters/naga.tscn",
	},
	## MOUNTAIN is the band of impassable massifs, so more of its stations than
	## any other's will find no clear candidate and place no boss — the designed
	## outcome of spawn_bosses_in_chunk's per-scale clearance walk, not a reason
	## to loosen it.
	Biome.MOUNTAIN: {
		"species": "roc",
		"scene": "res://scenes/characters/roc.tscn",
	},
	Biome.CITY: {
		"species": "clown",
		"scene": "res://scenes/characters/clown.tscn",
	},
}


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

## Memoized result of _road_terminal_k() — the last station at or west of
## ROAD_TERMINAL_X. It is a pure function of run_seed and the road config (both
## constant within a run) and EVERY road consumer asks for it, so it is computed
## once and dropped by `_drop_seeded_memos()` beside the station cache it is
## derived from — see there for why that lives under the SEED WRITE.
##
## The sentinel is a station index nothing can legitimately be: the cache grows
## contiguously outward from station 0 and a run would have to walk ~10^9
## stations west to reach it.
const ROAD_TERMINAL_K_UNSET: int = -0x7FFFFFFF
var _road_terminal_k_cache: int = ROAD_TERMINAL_K_UNSET

## Memoized field bridges, keyed by ANCHOR STATION index — `{}` for a station
## that anchors none, which is most of them (see field_bridge_at). It rides the
## station cache: derived from it plus the river field, so `_drop_seeded_memos()`
## clears the two together. Every chunk within a bridge's reach asks the same question, and
## the answer costs a walk across the water each time it is not remembered.
var _field_bridge_cache: Dictionary = {}

## The APPROACH CORRIDOR's bridges (see approach_bridges) — one small array for
## the run, not a per-station memo, because the corridor is ~150 m of authored
## line and is scanned in one pass. `_scanned` is separate from "empty", since a
## corridor that crosses no water is an honest empty answer.
var _approach_bridge_cache: Array = []
var _approach_bridge_scanned: bool = false

## Memoized "how much water does station k own", the hot read of the whole
## feature — see _field_bridge_wet_metres. Same lifetime as the bridges it feeds.
var _field_bridge_wet_cache: Dictionary = {}

## THE COARSE ROAD POLYLINE for the currently loaded window, as (x1, z1, x2, z2)
## segments — the one cache _alt_flat_mask's clause 4 reads on this side and
## ground.gdshader's `alt_road_seg` array uniform is fed from on the other.
##
## Empty until the first refresh, and empty forever while the spike flag is off.
## An empty cache means _alt_road_distance() answers INF, which the mask already
## reads as "nowhere near the road" — the same degrade _road_lateral_distance has
## always given a point far off-road in X, so there is no uninitialised state to
## trip over.
##
## Refreshed on a CHUNK-BOUNDARY CROSSING only (update_chunks, the seam that
## already runs there) — never per frame, and above all never from height_at(),
## which is called once per ground vertex.
var _alt_road_segs: PackedVector4Array = PackedVector4Array()

## Memoized result of _approach_coin_east_end() — where the approach coin line
## meets the Danube. Unlike the terminal station above this carries NO run seed
## (the avenue is authored at z = 0 and so is the river), so new_run() leaves it
## alone. INF is the "not resolved yet" sentinel.
var _approach_coin_east_end_cache: float = INF

## Memoized result of _approach_coin_line() — the whole approach + avenue coin
## line, resampled by arc length. It rides the TERMINAL STATION, so unlike the
## east end above it IS seeded, and `_drop_seeded_memos()` drops it beside the
## terminal cache.
var _approach_coin_line_cache: PackedVector2Array = PackedVector2Array()

## Memoized result of _build_landmark_sites() — chunk Vector2i -> LANDMARKS kind,
## the whole field landmark placement for this run (see the MUSEUM MILE banner).
## It rides the road centreline, so like the two caches above it IS seeded and
## `_drop_seeded_memos()` drops it beside them. The `_built` flag is separate because an empty
## table is a legitimate answer (spawn_landmarks off, or a degenerate road) and
## `is_empty()` alone would rebuild it on every chunk.
var _landmark_sites_cache: Dictionary = {}
var _landmark_sites_built: bool = false

## Reference to the player node to track their position
var player: Node3D

## Dictionary to store active chunks
## Key: Vector2i (chunk coordinates), Value: MeshInstance3D (the chunk)
var active_chunks: Dictionary = {}

## Spawn SLOTS whose body has walked out of the chunk that made it, as
## { node name (the slot id) : the node }. Written only by `adopt_wanderer`, read
## only by `spawn_hunters_in_chunk`, cleared by `set_run_seed`.
##
## THE ONE THING IT PREVENTS, and the only reason it exists: a scent-tracking
## hunter re-parents to whatever chunk it is standing on, so its birth chunk can
## unload and later regenerate while the unit is still alive somewhere else — and
## that regeneration would deterministically build a SECOND body with the same
## name, which is the room-wide crocodile id. One slot, one body.
##
## Entries are reaped lazily where they are read (a freed node is erased on the
## next spawn attempt for its slot), so nothing has to watch for deletions.
var _migrated_units: Dictionary = {}

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

## FIELD ALTITUDE (the spike, bead godot-test1-ope.1): lifetime microseconds spent
## building per-chunk ground collision HEIGHTMAPS. Exactly 0 with the flag off,
## because the flag-off path builds the same BoxShape3D it always did and never
## enters the timed block.
##
## IT EXISTS BECAUSE THE BUILD LANDS INSIDE THE SYNCHRONOUS FLOOR PATH.
## update_chunks() grounds the safety ring in the frame the player crosses a
## boundary — the floor is the whole fall-through guarantee — so a heightmap that
## cost milliseconds would be a startup freeze wearing a chunk-streaming costume.
## Same convention as the two counters above and for the same reason: A SPIKE
## SOURCE EXPOSES A MONOTONE COUNTER, NEVER A SIGNAL, so `perf_overlay.gd` can
## poll it at its own rate and measuring can never perturb what it measures.
var ground_collision_usec_total: int = 0

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

## MEMO for tower_site(). The site is a pure function of tower_site_distance ALONE
## (the seed left the key with the dry-site nudge — see THE DRY DISC), and
## _biome_spot_ok asks for it at every candidate spot in the world, so it is
## derived once and re-derived only when a designer moves that knob. One scalar
## compare per call, no allocation. `_tower_site_dist` starts negative, a distance
## no caller can supply, so the first call always computes.
var _tower_site_cache: Vector3 = Vector3.ZERO
var _tower_site_dist: float = -1.0

## The tower's two bodies, both parented to THIS manager (never to a chunk) and
## both a pure function of the run seed, so multiplayer needs no packet for either.
##
##   * `_tower_shell` is the real building. Null until the player first comes within
##     TOWER_LOAD_RADIUS, then never freed for the rest of the run — a bounded,
##     known cost, and freeing it would only trade nine boxes for a pop-in.
##   * `_tower_impostor` is the fog-exempt horizon silhouette, built at _ready() and
##     alive for the whole session; it is not freed when the shell exists — the
##     cross-fade (bead godot-test1-rgt) keeps it visible alongside the shell and
##     fades it via the material, and it is hidden only while the local player
##     stands inside Budapest (bead godot-test1-8gw.14) — because new_run() needs it back.
var _tower_shell: Node3D = null
var _tower_impostor: Node3D = null

# ----------------------------------------------------------------------------
# SHARED RESOURCES (created once, reused forever)
# ----------------------------------------------------------------------------
##
## THE BLOCK BATCH'S TWO ARE GONE FROM HERE — the unit cube every block
## instances and the vertex-coloured material that paints it are
## `chunk_batch.gd`'s now (bead godot-test1-ftn.1), and the MultiMesh reasoning
## went with them, because what it explains is create_box and
## _build_block_multimesh and those live there too. What stays are the
## singletons THIS file's own geometry wants: the one ground PlaneMesh every
## chunk shares, and the two emissive materials the artifact accents and the
## camp embers share. Same lazy-singleton discipline either way — one resource
## per process, never one per chunk.

## The single ground PlaneMesh shared by every chunk (see _get_shared_ground_mesh).
var _shared_ground_mesh: PlaneMesh

## The ground plane's subdivision count, as Godot's PlaneMesh means it: `N` CUTS,
## so 17 x 17 quads and 18 x 18 vertices over a 50 m chunk — 2.941 m apart, which
## is the density the vertex-noise ground shader wants and (with FIELD_ALTITUDE
## on) plenty for a 260 m-wavelength height field. ALT_GROUND_SIDE below is that
## VERTEX count and is what the collision heightmap reads; do not spell either as
## GROUND_SUBDIVISIONS + 1.
##
## IT IS A CONSTANT BECAUSE TWO THINGS READ IT. The visual mesh below and the
## collision HeightMapShape3D in _ensure_chunk_ground are built on the same grid
## ON PURPOSE — the floor you stand on is then the floor you see, for free and by
## construction rather than by review. Written down twice, the two would drift and
## the ground would draw one surface while collision answered another.
const GROUND_SUBDIVISIONS: int = 16

## VERTICES per side of that mesh, which is the number the collision heightmap
## needs and is NOT GROUND_SUBDIVISIONS + 1. Godot's `subdivide_width = N` inserts
## N cuts into ONE quad, giving N + 1 quads and N + 2 vertices — measured, 18 x 18
## for 16. Getting this wrong does not fail anywhere: it silently makes the floor a
## different piecewise-linear interpolant of height_at() from the drawn surface.
const ALT_GROUND_SIDE: int = GROUND_SUBDIVISIONS + 2

## Thickness of the ground's collision box, in metres — the number _ensure_chunk_ground
## has always built its BoxShape3D with, now spelled once because the ALTITUDE path
## needs its HALF.
##
## THE SHIPPED FLOOR IS NOT THE DRAWN PLANE: the box is centred on the chunk node, so
## its walkable TOP FACE is half a thickness above the mesh (y = +0.05, not 0.0), and
## every body in this game has stood there since the first chunk. The heightmap the
## spike builds is a SURFACE, not a solid, so sampling height_at() into it raw would
## drop the floor 5 cm everywhere the flag is on — INCLUDING inside the four zones
## _alt_flat_mask forces flat, whose whole promise (clause 2: "may not move by so much
## as a millimetre") is that flipping the flag moves nothing there. That is why
## _alt_ground_heightmap adds GROUND_COLLISION_TOP to every sample: with the flag on
## the collider keeps exactly today's offset above the drawn ground, so a red check in
## a forced-flat zone means the MASK is wrong and never the shape swap.
const GROUND_COLLISION_THICK: float = 0.1
const GROUND_COLLISION_TOP: float = GROUND_COLLISION_THICK * 0.5

## Lazily-created shared material for artifact glow accents (rune strips, eyes,
## missing keystones — see the ARTIFACTS section). ONE material shared by every
## accent in the world, same lazy-singleton discipline as ChunkBatch's own two.
var _shared_artifact_glow_material: StandardMaterial3D

## Lazily-created shared material for the nomad camps' fire-pit embers (see the
## NOMAD CAMPS banner). Same lazy-singleton discipline as the artifact glow above:
## ONE material for every ember that will ever be spawned, never one per camp.
var _shared_camp_ember_material: StandardMaterial3D

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
		_shared_ground_mesh.subdivide_width = GROUND_SUBDIVISIONS
		_shared_ground_mesh.subdivide_depth = GROUND_SUBDIVISIONS
		_shared_ground_mesh.material = terrain_material
	return _shared_ground_mesh

func _get_artifact_glow_material() -> StandardMaterial3D:
	"""
	Returns the shared emissive material for artifact glow accents, creating it on
	first use (same lazy-singleton shape as ChunkBatch._get_shared_block_material,
	one file along). The emission energy (3.0) sits well above main.tscn's
	glow_hdr_threshold (0.85), so the already-paid glow post-process picks these
	up and they bloom for free —
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
	accent.mesh = ChunkBatch._get_shared_unit_box_mesh()  # shared cube; transform carries the size
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
	# A NEW WORLD REMEMBERS NOTHING. Two pieces of runtime state outlive a chunk
	# wipe and would otherwise leak across it: the migrated-slot registry (whose
	# bodies the wipe frees, leaving stale names that would suppress the new
	# world's hunters) and the LOD manager's scent trail — a sibling node the wipe
	# never touches, so the new run's hunters would spend up to TRAIL_TTL following
	# the paths of the run you just lost. Hung off the seed write for the same
	# reason `_tower_reset()` is: every path that starts a world comes through here.
	_migrated_units.clear()
	# ...and every memo that is a pure function of run_seed — the road centreline
	# and the whole family strung along it. See `_drop_seeded_memos()`.
	_drop_seeded_memos()
	var lod := get_tree().get_first_node_in_group("lod_manager") if is_inside_tree() else null
	if lod != null and lod.has_method("reset_trails"):
		lod.reset_trails()
	# Put the tower's two bodies back to a not-built-yet state. The site itself no
	# longer moves (it is a constant — see tower_site()), but the SHELL is the one
	# thing under this manager a chunk wipe does not free, so a new world still has
	# to drop the old world's building. THIS is why the reset hangs off the seed
	# write rather than off new_run(): every path that starts a world — _ready's
	# roll, a restart, a multiplayer peer being handed the room's seed — goes
	# through here, so none of them can forget.
	_tower_reset()


func _drop_seeded_memos() -> void:
	"""
	Drop every memo that is a PURE FUNCTION OF `run_seed`, so the next reader
	rebuilds it for the world we have just moved to.

	CALLED FROM `set_run_seed()` AND NOWHERE ELSE, which is the whole bead
	(godot-test1-bvq). These used to be reset in `new_run()` instead, one level
	up — and `new_run()` is not the only door. `set_run_seed()` is, by CLAUDE.md's
	rule: it is the ONLY place `run_seed` is written, so it is the only seam that
	sees `_ready()`'s roll, a restart AND a multiplayer joiner being handed the
	room's seed after it has already streamed chunks. A memo dropped one level up
	is a memo the third caller forgets, and this whole family is memoized off the
	seed exactly like the site table that was moved here first (PR #228). Nothing
	shipped could reach the bug — `_ready()`'s roll predates any road and the MP
	path is `new_run()` — which is precisely why it had to be closed before a
	fourth caller arrived rather than after.

	EVERYTHING HERE IS DERIVED FROM THE ROAD CENTRELINE, which is itself pure in
	the seed, so they are one family and are reset together — the reason this is
	one function and not eleven lines copied into every door.
	"""
	# The station cache, back to its declared empty state (min > max is the "no
	# stations" sentinel, so the next `_road_extend_to_x` re-seeds station 0).
	# Its entries were computed with the OLD seed and would poison the new road:
	# the cache is "correct forever" only while the seed is constant.
	road_stations = {}
	road_k_min = 1
	road_k_max = 0
	# The terminal station is derived from that centreline, so it is exactly as
	# stale: a new seed puts a different station at ROAD_TERMINAL_X. Reset it HERE,
	# beside what it is derived from, so the two can never be reset apart.
	_road_terminal_k_cache = ROAD_TERMINAL_K_UNSET
	# ...and the field bridges, for the same reason one step further out: a
	# crossing is a station index plus the river field, and both moved. The
	# corridor's are derived from the terminal station, so they go with them.
	_field_bridge_cache = {}
	_field_bridge_wet_cache = {}
	_approach_bridge_cache = []
	_approach_bridge_scanned = false
	# ...and the approach coin line with it: it is resampled off that station.
	_approach_coin_line_cache = PackedVector2Array()
	# `_approach_coin_east_end_cache` is DELIBERATELY NOT HERE, and bd
	# `godot-test1-2iu` is the bead that established it rather than the bead that
	# fixed it. It looks like the line cache's twin and it is not: east of the
	# gate the corridor IS the avenue at z = 0, so that function scans
	# `BudapestPlan`'s authored polyline from `GATE.x` and takes the western
	# abutment of whichever bridge stands on it — every term is a constant a
	# designer typed, with no `run_seed` and no road station in it anywhere (its
	# own docstring says so, and `landmark_sites_selfcheck` check 1b now asserts
	# it across two seeds with a mutation control). A reset here would imply a
	# dependency that does not exist, which is the one thing this list must not do.
	# ...and the MUSEUM MILE: every site is a station index on the centreline
	# above, so a table kept across a re-seed would string this run's landmarks
	# along the LAST run's road (see the MUSEUM MILE banner). This is the one that
	# was already here before the bead, and moving the road beside it is what
	# makes `landmark_sites_selfcheck` check 1b able to stop clearing the road by
	# hand and assert the centreline itself instead.
	_landmark_sites_cache = {}
	_landmark_sites_built = false
	# ...and the FIELD_ALTITUDE spike's coarse road polyline, which is a window
	# onto the same centreline. `update_chunks` rebuilds it for the new world.
	_alt_road_segs = PackedVector4Array()


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
	# THE DEEP CHANNEL's darker centre strip (bead godot-test1-06o.3). Parity in
	# the ordinary sense: the strip you cannot walk into has to be the strip you
	# can SEE, and both are readouts of the same normalised depth — the fraction
	# is pushed rather than restated in GLSL. It shades the NOISE river and the
	# Danube from the one number. The shader deliberately does NOT run the FORD
	# exemption (`_deep_channel_ford` — a road-width gap at one refused crossing
	# in thirty-nine, which would cost a station search per fragment): the tint
	# says "deep water", the CPU says who may walk it.
	mat.set_shader_parameter("river_deep_fraction", RIVER_DEEP_FRACTION)
	mat.set_shader_parameter("biome_blend", BIOME_BLEND)
	# THE DRY DISC, the GPU half of it: is_river_at() refuses to call the tower's
	# footprint water, so the shader must refuse to paint it blue. Parity-critical
	# in the strongest sense — this pair IS the disagreement it prevents. The
	# shader's own defaults leave the mask off (radius -1), so a material that
	# never met this function draws exactly the world it always drew.
	var site := tower_site()
	mat.set_shader_parameter("tower_dry_center", Vector2(site.x, site.z))
	mat.set_shader_parameter("tower_dry_radius", TOWER_RADIUS)
	# BUDAPEST, the GPU half of it: the forced CITY ground, the authored Danube
	# and the dry decks, straight off BudapestPlan — the same numbers biome_at()
	# and is_river_at() answer with, so the paint and the wading cannot disagree.
	# Parity-critical in the same strongest sense as the dry disc above. All of it
	# is CONSTANT (the city is authored, there is no seed in it), so this could in
	# principle be pushed once — it is pushed here anyway, beside its siblings,
	# because ONE function feeding the ground material is the thing that makes the
	# contract auditable. The shader's own defaults are inert, so a material that
	# never met this function draws exactly the world it always drew.
	mat.set_shader_parameter("city_rect", Vector4(
			BudapestPlan.BUDAPEST_MIN.x, BudapestPlan.BUDAPEST_MIN.y,
			BudapestPlan.BUDAPEST_MAX.x, BudapestPlan.BUDAPEST_MAX.y))
	mat.set_shader_parameter("city_river", BudapestStreamer._city_river_segments(self))
	# CLAMPED, like the arrays themselves: the asserts in the two builders below are
	# stripped in an exported build — which is the web build, the one target this
	# shader exists for — so a plan that outgrew CITY_SEG_MAX / CITY_DRY_MAX would
	# ship a count past the end of a GLSL array uniform. That read is undefined in
	# GLSL ES 3.00. Losing the last bend is a bug budapest_selfcheck catches; a
	# driver-dependent out-of-range fetch is not.
	mat.set_shader_parameter("city_river_count",
			mini(BudapestPlan.DANUBE.size() - 1, CITY_SHADER_SEG_MAX))
	mat.set_shader_parameter("city_river_half", BudapestPlan.DANUBE_HALF_WIDTH)
	mat.set_shader_parameter("city_dry", BudapestStreamer._city_dry_rects(self))
	mat.set_shader_parameter("city_dry_count",
			mini(BudapestPlan.DRY_RECTS.size(), CITY_SHADER_DRY_MAX))
	# FIELD ALTITUDE, the GPU half of it (the SPIKE — see FIELD_ALTITUDE). Every
	# uniform below is the twin of a constant height_at() reads, pushed here beside
	# its siblings because ONE function feeding the ground material is the thing
	# that makes the parity contract auditable — and because the DISPLACEMENT is
	# the strongest form of that contract there is: the ground the player sees
	# raised is the ground the collision heightmap is sampled off, so a uniform
	# left behind is a player standing in mid-air or buried in a hill.
	#
	# THE GATE READS alt_enabled(), not FIELD_ALTITUDE, so altitude_selfcheck can
	# drive a real push both ways in one process. In the game the two are the same
	# false and the shader's own 0.0 default already agrees with it.
	mat.set_shader_parameter("alt_enabled", 1.0 if alt_enabled() else 0.0)
	# ALT_OFFSET_SALT alone, NOT pre-summed with biome_offset: the shader adds the
	# two in the same order height_at() does, and fp32 addition is not associative,
	# so a pre-summed offset would round to a different domain shift.
	mat.set_shader_parameter("alt_offset", TerrainAltitude.ALT_OFFSET_SALT)
	mat.set_shader_parameter("alt_cell_size", TerrainAltitude.ALT_CELL_SIZE)
	mat.set_shader_parameter("alt_detail_scale", TerrainAltitude.ALT_DETAIL_SCALE)
	mat.set_shader_parameter("alt_detail_weight", TerrainAltitude.ALT_DETAIL_WEIGHT)
	mat.set_shader_parameter("alt_detail_shift", TerrainAltitude.ALT_DETAIL_SHIFT)
	mat.set_shader_parameter("alt_amp_desert", TerrainAltitude.ALT_AMP_DESERT)
	mat.set_shader_parameter("alt_amp_plains", TerrainAltitude.ALT_AMP_PLAINS)
	mat.set_shader_parameter("alt_amp_city", TerrainAltitude.ALT_AMP_CITY)
	mat.set_shader_parameter("alt_amp_forest", TerrainAltitude.ALT_AMP_FOREST)
	mat.set_shader_parameter("alt_amp_mountain", TerrainAltitude.ALT_AMP_MOUNTAIN)
	mat.set_shader_parameter("alt_amp_snow", TerrainAltitude.ALT_AMP_SNOW)
	mat.set_shader_parameter("alt_city_skirt", TerrainAltitude.ALT_CITY_SKIRT)
	mat.set_shader_parameter("alt_tower_skirt", TerrainAltitude.ALT_TOWER_SKIRT)
	mat.set_shader_parameter("alt_river_skirt_k", TerrainAltitude.ALT_RIVER_SKIRT_K)
	mat.set_shader_parameter("alt_road_flat_half", TerrainAltitude.ALT_ROAD_FLAT_HALF)
	mat.set_shader_parameter("alt_road_skirt", TerrainAltitude.ALT_ROAD_SKIRT)
	# THE ROAD POLYLINE THE CPU IS ALREADY USING — read straight back out of
	# _alt_road_segs rather than rebuilt, which is the whole reason that cache
	# exists: parity by construction, so the corridor the GPU flattens and the
	# corridor the collision heightmap flattens can never be two different windows.
	mat.set_shader_parameter("alt_road_seg", TerrainAltitude._alt_road_seg_uniform(self))
	# CLAMPED for the same reason city_river_count is: the assert in the padder
	# below is stripped in an exported build, and a count past the end of a GLSL
	# array uniform is an undefined read in GLSL ES 3.00.
	mat.set_shader_parameter("alt_road_seg_count",
			mini(_alt_road_segs.size(), TerrainAltitude.ALT_ROAD_SEG_MAX))


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

	# ...and retune the sun's SHADOW on web only, for the same reason the fog's
	# density is gated: the web build's shadow map is a quarter of desktop's in
	# each axis. Desktop keeps the scene file's values untouched. The `is_web`
	# argument rather than a read inside is what lets a capture tool ask for the
	# web look on a desktop binary (see the function's banner).
	apply_sun_shadow(OS.has_feature("web"))

	print("Endless Terrain System initialized!")
	# Log the platform and the EFFECTIVE render distance so it's obvious in the web
	# console which value the build is actually running with (3 on web, 5 on desktop).
	print("Platform: ", "WEB" if OS.has_feature("web") else "DESKTOP/EDITOR")
	print("Chunk size: ", chunk_size, "m")
	print("Render distance: ", render_distance, " chunks")
	print("Crocodiles per chunk: ", crocodiles_per_chunk if spawn_crocodiles else 0)

func apply_sun_shadow(is_web: bool) -> void:
	"""
	Retune the sun's shadow for the WEB build, and only for it (bead
	godot-test1-6n1). A no-op anywhere else, which is what leaves desktop and the
	editor rendering exactly what `scenes/main.tscn` says.

	@param is_web: whether to apply the web values. `_ready` passes
	               `OS.has_feature("web")`.

	IT TAKES THE PLATFORM AS AN ARGUMENT instead of asking `OS` itself, because
	`OS.has_feature("web")` cannot be forced: a desktop binary can run the web
	RENDERER (`--rendering-method gl_compatibility`) but never carries the web
	FEATURE TAG, so nothing on a desktop machine — `scenes/style_shots.tscn`
	included — could otherwise reproduce what the web build looks like. That trap
	is what produced this bead's first, invalid set of A/B frames; see
	`project.godot`'s `[rendering]` shadow comment.

	The two values and the whole argument for them live on
	`WEB_SHADOW_NORMAL_BIAS` / `WEB_SHADOW_SPLIT_1` up top. Everything else on the
	light — the transform, the colour, the energy, the 2-split mode, the 55 m max
	distance — is the scene's and is not touched on any platform.
	"""
	if not is_web:
		return
	# Sibling lookup through our parent, exactly as _setup_fog reaches the
	# WorldEnvironment: in main.tscn the light and the terrain manager are both
	# children of "Main", and EndlessTerrain holds no hard reference to either.
	# Every step is null-guarded so a scene without the light degrades to "no
	# retune" instead of crashing.
	var parent_node := get_parent()
	if parent_node == null:
		return
	var sun := parent_node.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		push_warning("Sun shadow: no sibling DirectionalLight3D; skipping web retune.")
		return
	sun.shadow_normal_bias = WEB_SHADOW_NORMAL_BIAS
	sun.directional_shadow_split_1 = WEB_SHADOW_SPLIT_1
	print("Sun shadow retuned for web (normal_bias ", WEB_SHADOW_NORMAL_BIAS,
			", split_1 ", WEB_SHADOW_SPLIT_1, ")")

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
		# The tower shell streams on a chunk-boundary crossing — the streamer
		# already pays for that test, so walking nowhere near the site costs one
		# distance test per 50 m. The impostor's Budapest gate below is the one
		# per-frame tower cost: BUDAPEST_MIN/MAX are chunk-aligned (1600, ±1100
		# vs chunk_size 50) so the gate could be folded into this `if`, but
		# `_tower_reset()` writes `visible = true` outside any crossing and the
		# gate must win the next frame. Per-frame is the robust form, and
		# `set_visible` early-outs when nothing changed so it costs nothing.
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

	# The horizon impostor is a distant picture of the HQ. When the local
	# player is standing inside Budapest the city itself is the destination —
	# the HQ behind it is irrelevant and its fog-exempt silhouette reads as a
	# second city on the horizon. Hide the picture while inside, show it again
	# the moment the player steps out. The distance fade (FADE_FAR -> NEAR)
	# still owns opacity outside the city; this only suppresses the picture
	# entirely while inside. Multiplayer: each peer decides for its own screen
	# — remote avatars are pictures, not another "player" to read. Per-frame is
	# the robust form (see the note on the boundary block above).
	if is_instance_valid(_tower_impostor):
		_tower_impostor.visible = not BudapestPlan.contains(player.global_position.x, player.global_position.z)

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
	the `focus_chunks` banner in SECTION 2. (The FIELD_ALTITUDE spike's road
	corridor is the one thing that would break that with the flag on — its window
	is centred on the LOCAL player, so a far-pinned chunk bakes a floor off a window
	that never covered it. Flag-off it is inert; see height_at().)

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

	# STEP 0: refresh the coarse ROAD POLYLINE the heightfield's flat corridor is
	# measured against (spike flag only — _alt_road_segments is empty with it off).
	#
	# A chunk-boundary crossing is exactly the seam it wants: it runs once per ~50 m
	# of walking rather than per frame, and it runs BEFORE STEP 3 lays the safety
	# ring's ground, so the floor built this crossing already sees this crossing's
	# corridor. See clause 4 of _alt_flat_mask for the window's known ceiling.
	if alt_enabled():
		TerrainAltitude._alt_road_refresh(self, float(player_chunk.x) * chunk_size + chunk_size / 2.0)

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

	if alt_enabled():
		# FIELD ALTITUDE (the spike, bead godot-test1-ope.1). The displaced ground
		# needs a floor that follows it, and it is built on the SAME vertex grid the
		# visual mesh is subdivided into (ALT_GROUND_SIDE^2, 18 x 18), so the surface
		# the player stands on is the surface the vertex shader drew rather than an
		# approximation of it.
		#
		# TIMED, because this lands inside update_chunks' synchronous safety-ring
		# path (see ground_collision_usec_total for why that matters).
		var started_usec := Time.get_ticks_usec()
		collision_shape.shape = TerrainAltitude._alt_ground_heightmap(self, chunk_pos)
		# THE UNIFORM SCALE, and why the heights were pre-divided by it upstream:
		# HeightMapShape3D cells are ONE unit wide and the grid is centred on the
		# node, so an 18-wide map spans -8.5..+8.5 units. The chunk is chunk_size
		# (50 m) across, so the shape is stretched by alt_ground_cell() (2.941) to
		# reach -25..+25 m. UNIFORM is the operative word — a non-uniformly scaled
		# shape is a Godot warning and an unsupported physics case — so the scale
		# hits Y as well, and _alt_ground_heightmap already divided every stored
		# height by the same factor to cancel it back out.
		collision_shape.scale = Vector3.ONE * TerrainAltitude.alt_ground_cell(self)
		ground_collision_usec_total += Time.get_ticks_usec() - started_usec
		# THE CULL VOLUME, because the displacement is a VERTEX SHADER and the
		# renderer cannot see it. The shared PlaneMesh's AABB is chunk_size x 0 x
		# chunk_size, so a chunk whose flat quad is just outside the frustum has
		# its 22 m hilltop culled with it and the hillside pops. PER-INSTANCE — the
		# shared mesh resource is untouched, and the flag-off branch below sets
		# nothing at all, so today's world keeps today's AABB exactly.
		var half_span := chunk_size / 2.0
		mesh_instance.custom_aabb = AABB(
				Vector3(-half_span, -TerrainAltitude.ALT_AMP_MAX, -half_span),
				Vector3(chunk_size, 2.0 * TerrainAltitude.ALT_AMP_MAX, chunk_size))
	else:
		# TODAY'S FLOOR, byte for byte: one box the width of the chunk, 0.1 m
		# thick. This is what ships (FIELD_ALTITUDE is false) and the branch above
		# is unreachable in every build the player ever runs.
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(chunk_size, GROUND_COLLISION_THICK, chunk_size)
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
	#      { "transform": Transform3D, "color": Color, "kind": int }
	#      entry here, and AFTER generation we build ONE MultiMeshInstance3D per
	#      mesh KIND present rendering all of them in a single draw call each
	#      (a chunk of nothing but cubes -- every chunk today -- is still one).
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
	TerrainBiomes.spawn_biome_content_in_chunk(self, chunk_pos, obstacles, block_batch, block_body)

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

	# A WAYPOINT CIRCLE, if one of the eight stands in this chunk (epic
	# godot-test1-sc6). Neither a roll nor a hash stream: the eight sites are pure
	# arithmetic over the road's station cache, tower_site() and three authored
	# rows in budapest_plan.gd, so this consumes NOTHING from anybody — it is the
	# landmark reverse lookup's shape, one family along.
	#
	# It shares the five spawners' ordering requirement only in its second half: it
	# must run before _build_block_multimesh / the block_body attach so the ring's
	# thirteen boxes join the chunk's ONE MultiMesh draw call. The FIRST half does
	# not apply and that is the interesting part — a waypoint neither reads
	# `obstacles` nor appends to it (the ring is flat, walkable and collision-free
	# on purpose; TerrainWaypoints' banner carries the "no footprint, and why"),
	# so nothing before it can move it and nothing after it can see it. Placing the
	# call here rather than anywhere else in the block is therefore a readability
	# choice, not a constraint — it sits with the family it looks most like.
	#
	# CITY CHUNKS TOO, unlike the chest above: five of the eleven sites are inside
	# the rect, they are ordinary chunk content, and a 5.2 m circle never straddles
	# a chunk seam so nothing here is sliced.
	TerrainWaypoints.spawn_waypoint_in_chunk(self, chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# BUDAPEST — this chunk's slice of the authored city (bead godot-test1-8gw.3).
	# NOT a hash stream and NOT a roll: the city is a table of constants in
	# budapest_plan.gd, so this consumes no draw from anybody and asks the plan
	# only whether its rect reaches this chunk. Outside the rect it costs one
	# rectangle intersection.
	#
	# SAME ORDERING REQUIREMENT as the five above, and it is why it runs LAST of
	# the six: after them so the plateau footprints join the finished obstacles
	# list (and so nothing procedural has to know the city is coming — the spawner
	# policy that keeps props out of Pest is each spawner's own early return), and
	# before _build_block_multimesh / the block_body attach so a hill, a ramp and a
	# pavement slab join the chunk's ONE MultiMesh draw call and ONE collision
	# body, exactly like a cactus. It also runs BEFORE the coin spawners below,
	# which is what lets the approach line perch or skip over city stone.
	spawn_city_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)

	# ...and the FIELD's bridges, wherever the coin road crosses a river band
	# (bead godot-test1-06o.2). Same ordering requirement as the six above and for
	# the same two reasons: after everything that fills `obstacles` (though it
	# appends nothing to it — a bridge is meant to be walked) and before
	# _build_block_multimesh, so a deck joins the chunk's ONE batch and ONE
	# collision body. Before the coin spawners too, which is what lets the road's
	# coins ride the deck instead of drowning under it.
	FieldBridges.spawn_field_bridges_in_chunk(self, chunk_pos, block_batch, block_body)

	# Build the chunk's batched block visuals. If any blocks were placed, collapse
	# them all into one MultiMeshInstance3D parented to this chunk (so it is freed
	# automatically when the chunk unloads, like every other per-chunk node).
	if not block_batch.is_empty():
		# THE CITY'S STREET WALLS CAST NO SHADOW, and this one boolean is the
		# whole of bead godot-test1-8gw.9's performance story (measured on a
		# Pest chunk at the web build's own render_distance 3, standing still,
		# best of three runs each):
		#
		#     before the blocks landed   47 FPS   22.6 ms process   126 draws
		#     blocks, shadows casting    25 FPS   42.1 ms process   150 draws
		#     blocks, shadows off        48 FPS   22.7 ms process   127 draws
		#
		# 19 ms a frame, all of it in the shadow pass and none of it in the draw
		# call count the box budgets guard — and with it gone, a Budapest with
		# every block filled costs what the empty one did, to the millisecond. A filled block is ~2,100 boxes in the
		# 49-chunk web view, most of them 8-25 m tall, so every one of them is a
		# long caster crossing several cascades of the directional light — the
		# exact cost TowerInterior's "one batched mesh per storey and casts no
		# shadow" already measured indoors, met again outdoors at city scale.
		#
		# THE BUILDINGS STILL LIGHT AND SELF-SHADE: they RECEIVE the directional
		# light, so a north wall is dark and a south wall is bright and the
		# roofline still reads. What is gone is the shadow a building throws onto
		# the flat ground beside it, which in a city that is a street wall on both
		# sides of every road is a dark band the fog eats anyway.
		#
		# IT IS THE WHOLE BUDAPEST CHUNK, so a landmark's stone loses its cast
		# shadow along with the blocks around it — the chunk has ONE batch, and
		# splitting it to give the sights their shadows back is a second draw
		# call per chunk, which is the invariant budapest_selfcheck check 4
		# exists to defend.
		#
		# THAT TRADE IS AN OWNER RULING AND NOT A GUESS (2026-09-02, bead
		# godot-test1-8gw.9, verbatim: "it's okay without shadow, performance is
		# more important"). Budapest chunk batches stay shadow RECEIVERS ONLY.
		# Do not split the batch to restore them; a future author who wants the
		# landmarks' shadows back needs a new ruling, because the cost is the
		# 19 ms measured above and the second draw call per chunk on top of it.
		#
		# ASKED OF THE CHUNK'S SQUARE, NEVER ITS CENTRE — `city_chunk()` is the
		# SAME predicate spawn_city_in_chunk rejects on, so "built a slice of
		# Budapest" and "casts no shadow" are one answer and cannot disagree. An
		# earlier cut asked `in_budapest()` about the centre and got both edge
		# cases wrong, all the way round a 2.2 km rect.
		_build_block_multimesh(mesh_instance, block_batch,
				not city_chunk(chunk_to_world(chunk_pos)))

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
		TerrainPredators.spawn_crocodiles_in_chunk(self, chunk_pos, mesh_instance, obstacles)
		# Rare crocodiles that patrol an elevated platform (mound summit / wall ridge)
		TerrainPredators.spawn_platform_crocodiles(self, chunk_pos, mesh_instance, platforms)
		# ...and the DANUBE's crocodiles, the one predator the authored city rect
		# keeps (bead godot-test1-8gw.3, DEC-9). Same flag as its siblings — a
		# check that turns predators off must turn off all of them — but its own
		# independent DANUBE_SALT hash stream, so the spawner above regenerates
		# every crocodile in the world exactly where it already was. Takes no
		# `obstacles` — a city landmark's footprint is one disc up to 156 m across,
		# which would empty the whole river — and clears stone with its own
		# danube_wet() re-test at each body plus a deck-rect margin for the pier
		# and cutwater stone that hangs off a deck (DANUBE_CROC_DECK_MARGIN).
		TerrainPredators.spawn_danube_crocodiles_in_chunk(self, chunk_pos, mesh_instance)
		# Rare BOSS crocodiles guarding the coin road (deterministic, station-
		# indexed — its own BOSS_SEED hash stream, no shared RNG draws consumed).
		# Gets `obstacles` like its siblings so a 3.75x-9x boss is never wedged
		# inside a wall/mound/tree/mountain right on the player's path.
		TerrainPredators.spawn_bosses_in_chunk(self, chunk_pos, mesh_instance, obstacles)

	# GD-SURVEY hunter robots — the corporation's retrieval units, gated on their
	# OWN flag rather than `spawn_crocodiles` because that flag is also check 12's
	# A/B switch. Its own independent HUNTER_SALT hash stream, so it consumes no
	# draw from the crocodile spawner above and every crocodile in the world stands
	# exactly where it stood before hunters existed. Gets `obstacles` like its
	# siblings so a 1.35 m chassis is never wedged inside a wall or a massif.
	TerrainPredators.spawn_hunters_in_chunk(self, chunk_pos, mesh_instance, obstacles)

	# Lay this chunk's slice of the coin road (deterministic station-indexed trail;
	# coins sit at ground height, perching on a climbable block where the road
	# crosses one — see spawn_coins_in_chunk).
	if spawn_coins:
		spawn_coins_in_chunk(chunk_pos, mesh_instance, obstacles)
		# ...and the APPROACH + AVENUE line that takes over where the road's coins
		# stop, from the terminal station through the gate to the Danube's west
		# bank (bead godot-test1-8gw.3). Same flag as its sibling: they are one
		# continuous trail as far as the player is concerned, and a check that
		# turns coins off must turn off all of them. Zero RNG, so it consumes no
		# draw from anybody's stream.
		spawn_approach_coins_in_chunk(chunk_pos, mesh_instance, obstacles)
		# ...and the CITY's own routes (bead godot-test1-8gw.9), which pick the
		# trail up at the west bank and carry it down every avenue of the street
		# grid and across every bridge. Same flag again, same zero-RNG rule: the
		# player should never be able to tell where one authored line ends and
		# the next begins.
		spawn_city_coins_in_chunk(chunk_pos, mesh_instance, obstacles)

	# TELEMETRY, counted HERE and not in _ensure_chunk_ground: the counter exists
	# to explain frame spikes (see its comment in SECTION 2), and after the
	# ground/content split it is the content that costs anything — ~97% of a
	# chunk. Counting the ground instead would credit the cheap frame and report
	# "+0 chunks" on the frame that actually did the work.
	chunks_created_total += 1

func spawn_objects_in_chunk(chunk_pos: Vector2i, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> Array:
	"""
	Spawns this chunk's ground clutter: themed scattered props (see TerrainProps.build_prop)
	and — sometimes — one themed feature structure (barrier wall / run-through
	lane / gate / terraced mound, dressed for the territory it stands in).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param platforms: Out-param; feature structures append walkable-top descriptors
	                  here for patrolling crocodiles.
	@param block_batch: Out-param; each block created appends its
	                  { "transform": Transform3D, "color": Color, "kind": int } here so the
	                  caller can render them all as one MultiMesh per kind present
	                  (visual batching).
	@param block_body: The chunk's single shared block-collision StaticBody3D; each
	                  block adds its CollisionShape3D child to this body (Task 5).
	@return Array of obstacle footprints ({ "pos": Vector3, "radius": float }) so
	        the crocodile spawner can keep its NPCs out of the blocks.

	EDUCATIONAL NOTE:
	- We use chunk coordinates as a seed for deterministic randomness
	- This means the same chunk always generates the same objects
	- Objects are parented to the chunk so they're removed when chunk is removed
	"""

	# BUDAPEST — props and feature structures are OFF inside the city rect (bead
	# godot-test1-8gw.3, DEC-9): the city is AUTHORED, and a barrier wall or a
	# terraced mound rolled into the middle of Pest is the one thing the plan
	# cannot design around. NOT tower_excludes(), which would turn everything off
	# with one answer — the rect wants a different answer per system, and the very
	# next spawner down (the Danube's crocodiles) is a yes. Keyed on the CHUNK
	# CENTRE, and taken BEFORE the RNG exists because there is nothing to advance:
	# this stream is never consulted for a city chunk at all.
	var city_probe := chunk_to_world(chunk_pos)
	if in_budapest(city_probe.x, city_probe.z):
		return []

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
	# Scarcity thins feature structures to plain at 4 km — compare the same
	# roll against chance * k, no new draw.
	var k_struct := scarcity_at(chunk_center)
	if rng.randf() < TerrainStructures._structure_chance_at(self, chunk_center) * k_struct:
		TerrainStructures.spawn_feature_structure(self, rng, half_chunk, chunk_center, obstacles, platforms, block_batch, block_body)

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
	# SCARCITY — plain terrain at 4 km. Multiply the TARGET, never add a draw
	# on the shared chunk RNG (same discipline as desert). Budapest itself is
	# exempt (early return above), so this only thins the wilderness.
	# Use roundi so the target reaches 0 only when k reaches 0 (int() would
	# truncate desert props at ~2 km and plains at ~3.86 km).
	var k := scarcity_at(chunk_center)
	object_target = roundi(object_target * k)
	if object_target == 0:
		return obstacles # footprints gathered so far (feature structure) stay

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

		# Everything below this line runs on the PRIVATE prop RNG. TerrainProps.build_prop is
		# handed no shared rng at all, which is what makes the rule above
		# structural rather than a discipline somebody has to remember.
		var prop := TerrainProps.build_prop(
			self, Vector3(random_x, 0.0, random_z), size, prop_seed, chunk_center, block_batch, block_body
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


func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0), collide: bool = true, kind: int = ChunkBatch.BoxKind.CUBE) -> void:
	"""
	THE ONE FORWARDER (bead godot-test1-ftn.1). The box seam itself is
	`chunk_batch.gd` — read ChunkBatch.create_box for what a box costs the
	caller's RNG, why the visual and the collision share one basis, why the
	colour is converted to linear here instead of by the material, and what
	`kind` may and may not be used for (ChunkBatch.BoxKind's banner).

	It stays a method on the terrain because `terrain.create_box(...)` IS the
	contract 600-odd call sites and every landmark builder are written against
	(landmark_builders.gd's header: a builder's whole job is appending boxes
	through the terrain's own create_box). Rewriting them all is the opposite of
	a mechanical move — and `kind` being the LAST optional is what keeps that
	true for the mesh-kind slot (bead godot-test1-y1o.1) too.
	"""
	ChunkBatch.create_box(center_pos, dimensions, yaw, rng, block_batch, block_body,
			tilt, color_override, collide, kind)

func _build_block_multimesh(parent_chunk: MeshInstance3D, block_batch: Array,
		cast_shadows: bool = true) -> void:
	"""
	Forwarder to ChunkBatch._build_block_multimesh (bead godot-test1-ftn.1),
	kept for create_box's reason one seam along: create_chunk calls it on itself
	and budapest_selfcheck calls it on the terrain node. The MultiMesh, and the
	note on why one draw call per chunk is the whole point, are over there.
	"""
	ChunkBatch._build_block_multimesh(parent_chunk, block_batch, cast_shadows)

# ----------------------------------------------------------------------------
# THE PREDATOR SPAWNERS — one-line forwarders, the code is in terrain_predators.gd
# ----------------------------------------------------------------------------
##
## Bead godot-test1-ftn.6. `create_chunk` below calls `TerrainPredators` DIRECTLY
## (it owns the call-order list and should say so); these six exist for
## `create_box`'s reason one seam along — ninety-odd call sites across
## `piglet_crocodile_ai.gd`, `tower_guards.gd`, `budapest_plan.gd` and a dozen
## self-checks are written against `terrain.spawn_x_in_chunk(...)`, and rewriting
## them all is the opposite of a mechanical move. The population rules, the
## salts and every comment are over there.

func spawn_crocodiles_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	TerrainPredators.spawn_crocodiles_in_chunk(self, chunk_pos, parent_chunk, obstacles)

func spawn_danube_crocodiles_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D) -> void:
	TerrainPredators.spawn_danube_crocodiles_in_chunk(self, chunk_pos, parent_chunk)

func spawn_hunters_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	TerrainPredators.spawn_hunters_in_chunk(self, chunk_pos, parent_chunk, obstacles)

func spawn_platform_crocodiles(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> void:
	TerrainPredators.spawn_platform_crocodiles(self, chunk_pos, parent_chunk, platforms)

func spawn_bosses_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	TerrainPredators.spawn_bosses_in_chunk(self, chunk_pos, parent_chunk, obstacles)

func adopt_wanderer(unit: Node3D) -> void:
	TerrainPredators.adopt_wanderer(self, unit)

## The two the self-checks reach for by name: `_boss_at` is how
## `enemy_spawn_selfcheck` walks the road's bosses and `_croc_roll_seed` is the
## per-instance roll `budapest_selfcheck` A/Bs. Same forwarder, same reason.

func _boss_at(i: int) -> Dictionary:
	return TerrainPredators._boss_at(self, i)

func _croc_roll_seed(chunk_pos: Vector2i, index: int) -> int:
	return TerrainPredators._croc_roll_seed(self, chunk_pos, index)

func _near_dry_rect(x: float, z: float, margin: float) -> bool:
	return TerrainPredators._near_dry_rect(self, x, z, margin)


# ============================================================================
# THE PRIVATE-STREAM FEATURES — three one-line forwarders (bead godot-test1-ftn.4)
# ============================================================================
# The bodies are `TerrainFeatures`'. These three stay as methods for
# `create_box`'s reason and no other: `terrain.spawn_artifact_in_chunk(...)` IS
# the contract `budapest_selfcheck` (twelve call sites), `landmark_sites_selfcheck`
# and `create_chunk`'s call-order list are written against, and rewriting them all
# is the opposite of a mechanical move. Nothing else of the family is forwarded.

func spawn_artifact_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainFeatures.spawn_artifact_in_chunk(self, chunk_pos, parent_chunk, obstacles, block_batch, block_body)

func spawn_camp_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainFeatures.spawn_camp_in_chunk(self, chunk_pos, parent_chunk, obstacles, block_batch, block_body)

func spawn_chest_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainFeatures.spawn_chest_in_chunk(self, chunk_pos, parent_chunk, obstacles, block_batch, block_body)

# ============================================================================
# GEO LANDMARKS — two forwarders into `TerrainLandmarks` (bd godot-test1-ftn.26)
# ============================================================================
#
# The section is `scripts/terrain_landmarks.gd` now; read that file's header for
# why the SITE MEMO above and the whole `LANDMARK_*` banner stayed here. The
# three below are the names reached from outside, measured rather than guessed:
#
#   * `_landmark_at` is reached BY STRING — `scarcity_selfcheck.gd:397` calls
#     `terrain.call("_landmark_at", chunk)`, which no rename-aware tool would
#     find — and by `style_shots`;
#   * `spawn_landmark_in_chunk` is `create_chunk`'s call-order list plus four
#     self-checks (budapest, enemy_spawn, field_bridge, landmark_sites);
#
# NEITHER PUBLIC SITE QUERY GETS ONE, and that is measured rather than assumed:
# `landmark_sites()` and `landmark_site(kind)` are the "a site is computable
# without its chunk" seam, and nothing in the project reaches either through the
# `terrain` group — `landmark_sites_selfcheck` names the class (it is the
# family's own check) and `style_shots` uses `_landmark_at`. They are spelled
# `TerrainLandmarks.landmark_sites(terrain)`; a forwarder for a name with no
# caller is dead weight, and this file has enough of those to carry already.
#
# `landmark_sites_selfcheck` — the FAMILY's own check — names the class directly
# instead, which is the epic's acceptance (d) and `scarcity_selfcheck`'s ftn.7
# lesson: a check that reads its subject through a forwarder measures the
# forwarder.

func _landmark_at(chunk_pos: Vector2i) -> Dictionary:
	return TerrainLandmarks._landmark_at(self, chunk_pos)


func spawn_landmark_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainLandmarks.spawn_landmark_in_chunk(self, chunk_pos, parent_chunk, obstacles, block_batch, block_body)
# ============================================================================
# BIOME CONTENT — forwarders; the builders are in terrain_biomes.gd
# ============================================================================
##
## Bead godot-test1-ftn.5 moved the eight `_spawn_*_content` builders, the oasis
## and dune site rolls, `_snow_mammoth`, `_city_snap` and `_biome_spot_ok` to
## `scripts/terrain_biomes.gd`. The BIOME FIELD did not go with them —
## `_biome_noise`, `biome_at`, `is_river_at` and the `Biome` enum are still
## below, because the noise is one half of the CPU/GPU parity contract and the
## enum cannot leave a file whose const Dictionaries are keyed by it.
##
## These two are forwarders for `create_box`'s reason (bead ftn.1):
## `spawn_biome_content_in_chunk` is called on the terrain by a dozen
## self-checks, and `_biome_spot_ok` is the single home of the placement rule —
## the artifact, camp, chest and landmark spawners still in this file all place
## through it, and so do six self-checks. The six builders below them are
## reached BY STRING (`terrain.call("_spawn_city_content", ...)`), which no
## rename-aware tool would have caught.

func spawn_biome_content_in_chunk(chunk_pos: Vector2i, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes.spawn_biome_content_in_chunk(self, chunk_pos, obstacles, block_batch, block_body)

func _biome_spot_ok(chunk_center: Vector3, local_x: float, local_z: float, radius: float, road_clearance: float, obstacles: Array) -> bool:
	return TerrainBiomes._biome_spot_ok(self, chunk_center, local_x, local_z, radius, road_clearance, obstacles)

func _spawn_desert_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_desert_content(self, chunk_center, rng, obstacles, block_batch, block_body)

func _spawn_desert_oasis(chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_desert_oasis(self, chunk_center, chunk_pos, rng, obstacles, block_batch, block_body)

func _spawn_desert_dunes(chunk_center: Vector3, chunk_pos: Vector2i, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_desert_dunes(self, chunk_center, chunk_pos, rng, obstacles, block_batch, block_body)

func _spawn_forest_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_forest_content(self, chunk_center, rng, obstacles, block_batch, block_body)

func _spawn_city_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_city_content(self, chunk_center, rng, obstacles, block_batch, block_body)

func _spawn_snow_content(chunk_center: Vector3, rng: RandomNumberGenerator, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	TerrainBiomes._spawn_snow_content(self, chunk_center, rng, obstacles, block_batch, block_body)

func _snow_mammoth(local: Vector3, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	return TerrainBiomes._snow_mammoth(self, local, rng, block_batch, block_body)

func _oasis_at(chunk_pos: Vector2i) -> Dictionary:
	return TerrainBiomes._oasis_at(self, chunk_pos)

func _dune_at(chunk_pos: Vector2i) -> Dictionary:
	return TerrainBiomes._dune_at(self, chunk_pos)

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

	...with ONE override, and it is BUDAPEST. Inside the authored city rect the
	answer is CITY whatever the noise field says: the city is hand-planned like
	the HQ's site, and a band that wandered under it between runs would put
	desert sand down Váci utca. This is one half of a two-language contract —
	the other half is the `in_city` clause in ground.gdshader's fragment(), fed
	`city_rect` by _apply_biome_shader_params(). EDIT BOTH TOGETHER.
	"""
	if BudapestPlan.contains(world_x, world_z):
		return Biome.CITY
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

	...with ONE exception, and it is the whole of THE DRY DISC: the tower stands at
	a fixed address now, so the river gets out of ITS way. Inside TOWER_RADIUS of
	tower_site() this answers false whatever the raw field says, and
	ground.gdshader masks the blue band over exactly the same disc — the CPU/GPU
	parity contract applies to the mask as much as to the noise. First, because it
	is the cheaper test (no noise evaluation) and tower_site() is a memo read.
	"""
	var site := tower_site()
	# Vector2, not scalar math: fp32, the same fp32 the shader's distance() runs
	# in, for the same reason the noise port routes everything through Vector2.
	if Vector2(world_pos.x - site.x, world_pos.z - site.z).length() <= TOWER_RADIUS:
		return false
	# ...and ONE MORE, which is BUDAPEST: inside the city rect the answer is the
	# AUTHORED Danube and nothing else. The early return is what suppresses the
	# noise river in there — the city has one river, it is drawn in
	# BudapestPlan.DANUBE, and a second one wandering through Pest would be a
	# river no map and no landmark slot knows about. One half of a two-language
	# contract: ground.gdshader computes the same predicate from the same numbers
	# (city_river / city_river_half / city_dry, pushed by
	# _apply_biome_shader_params), so the blue you SEE is the water you WADE.
	# EDIT BOTH TOGETHER. The polyline distance is routed through Vector2 inside
	# BudapestPlan for the same fp32 reason as the disc above.
	if BudapestPlan.contains(world_pos.x, world_pos.z):
		return BudapestPlan.danube_wet(world_pos.x, world_pos.z)
	return absf(_biome_noise(world_pos.x, world_pos.z) - RIVER_LEVEL) < RIVER_HALF_WIDTH


## How high above the flat world a body may stand and still be IN the river.
##
## THE Y-AWARE HALF OF WADING (bead godot-test1-06o.2). `is_river_at` is XZ-only
## and must stay that way — it is the band the ground shader paints, and the two
## are one function in two languages. But "am I in the water" is a question about
## a BODY, and a body standing on a bridge deck 1.6 m over the band is not.
##
## 0.6 m is chosen against the two things that can put a grounded body above y=0
## in this game: a bridge deck (FIELD_BRIDGE_TOP 1.6, Budapest's 12) is over it,
## and the wade sink plus a coin-height perch on a climbable prop top are under
## it. It is deliberately NOT read off FIELD_BRIDGE_TOP: the rule is "am I
## standing on something", not "am I standing on a bridge", and a future ford,
## stepping stone or barge gets it for free.
const WADE_SURFACE_MAX: float = 0.6


func is_wading_at(world_pos: Vector3) -> bool:
	"""
	Is a body at this position standing IN a river — the Y-AWARE question, and
	the one every wading consumer asks (bead godot-test1-06o.2).

	@param world_pos: The BODY's world position. Y matters here, unlike
	                  is_river_at.
	@return: true when the point is inside a river band AND low enough to be in
	         the water rather than on something over it.

	ONE HOME FOR THE RULE, which is the whole point of it being here rather than
	a clause repeated in the player, the remote avatar and the crocodile: those
	three used to each call is_river_at directly, and a fourth consumer would have
	been a fourth chance to forget the height.

	IT DOES NOT TOUCH THE SHADER, deliberately. The blue band is still painted
	under a bridge, because the water really is under the bridge — the CPU/GPU
	parity contract is about `is_river_at`, which is unchanged, and this is a
	strictly narrower question that only a body can ask.

	IT CLOSES BUDAPEST'S UNDER-DECK GAP (bead godot-test1-06o.3) by asking
	`river_depth_at`, which subtracts only the DRY_RECTS rows that are real LAND.
	`is_river_at` still subtracts every row — it is the band the shader paints and
	a deck must read dry to it — but a BODY at y = 0 under a deck 12 m up is
	standing in the Danube, and the height compare above is what makes that
	distinction safe: a body ON the deck never reaches this line. Margaret Island
	keeps its cutout because it is land, not a lid.

	Cheap in the order that matters: the height compare is free and rejects every
	body on a deck before the noise evaluation runs.
	"""
	if world_pos.y >= WADE_SURFACE_MAX:
		return false
	return river_depth_at(world_pos.x, world_pos.z) < 1.0


## ============================================================================
## THE DEEP CHANNEL — rivers are not walkable down the middle
## ============================================================================
##
## OWNER RULING 2026-09-04, re-asked with urgency 2026-09-05 ("why rivers, and
## danube are still walkable? fix this") — bead godot-test1-06o.3. The inner
## fraction of every river band is IMPASSABLE: a body that gets into it is pushed
## back out along the field's own gradient. The outer band still wades at exactly
## today's numbers (WADE_SPEED_FACTOR / WADE_RUN_MIN_SPEED are untouched), so the
## thing that made wading a decision rather than a trap survives on the banks.
##
## WHY A FRACTION AND NOT A WALL: a hard wall across an endless procedural field
## is a softlock generator. A centre channel leaves the banks walkable, keeps the
## river readable as water you can stand in, and puts the crossing where the
## bridges are — the road's (spawn_field_bridges_in_chunk), the corridor's
## (approach_bridges) and Budapest's four authored decks.
const RIVER_DEEP_FRACTION: float = 0.4

## Finite-difference step for the push direction, in metres. Small against a band
## (~10-20 m across) and large against fp32 noise, so the two extra evaluations
## give a direction and not rounding noise.
##
## IT IS DIFFERENCED ON THE SIGNED FIELD, NOT ON THE DEPTH, and that is a
## correctness fix rather than a preference. `river_depth_at` is an ABSOLUTE
## value, so it has a KINK on the centreline: a forward difference taken within
## RIVER_DEEP_PROBE of it lands on the far bank and reads the wrong side's slope,
## which points the push INTO the channel. Measured on the shipped field before
## the fix: 42 of 4,000 channel samples (1.05%), all at depth < 0.1 — a jitter
## rather than a trap, because the body drifts off the kink and the next frame is
## right, but the docstring claimed it could not happen and it could.
## `_river_signed_raw` has no kink, so the difference is honest everywhere.
const RIVER_DEEP_PROBE: float = 0.5

## THE FORD's half-width — how far off the road's CENTRELINE the one exemption
## reaches, in metres. The deck's own half-width plus a station, so the gap in the
## wall is the width of the road and a metre of slop, never a beach: off the road
## the same water is still walled.
const RIVER_DEEP_FORD_HALF: float = FIELD_BRIDGE_HALF_WIDTH + 4.0


func river_depth_at(world_x: float, world_z: float) -> float:
	"""
	How deep into a river this XZ is, NORMALISED: 0 on the centreline, 1 at the
	bank, > 1 on dry land.

	@param world_x, world_z: World-space point (metres). XZ-only, like the band.
	@return: |field| / half-width for the noise river, distance / half-width for
	         the authored Danube, and DRY_MARGIN for anything masked dry.

	ONE FIELD FOR TWO RIVERS, which is the whole point: the deep channel, the
	push gradient and the Y-aware wade test all read this, so the procedural river
	and the Danube get the same rule with no second implementation and no second
	set of constants. It is the same cost shape as `is_river_at` — the tower disc
	first (no noise evaluation), then Budapest, then one `_biome_noise`.

	IT IS NOT `is_river_at`, and the difference is exactly one clause: inside the
	city it subtracts only the dry LAND rows (`BudapestPlan.is_dry_land`), never
	the four bridge decks. See `is_wading_at` — a deck is dry to the shader and to
	every spawner, and is water to a body standing under it.
	"""
	# Far enough out that no caller can mistake it for a bank; a plain INF would
	# poison the finite difference in deep_channel_push().
	const DRY_MARGIN: float = 4.0
	var site := tower_site()
	# Vector2, not scalar math: fp32, the same fp32 is_river_at() runs in.
	if Vector2(world_x - site.x, world_z - site.z).length() <= TOWER_RADIUS:
		return DRY_MARGIN
	if BudapestPlan.contains(world_x, world_z):
		if BudapestPlan.is_dry_land(world_x, world_z):
			return DRY_MARGIN
		return BudapestPlan.danube_distance(world_x, world_z) \
				/ BudapestPlan.DANUBE_HALF_WIDTH
	return absf(_biome_noise(world_x, world_z) - RIVER_LEVEL) / RIVER_HALF_WIDTH


func _river_signed_raw(world_x: float, world_z: float) -> float:
	"""
	`river_depth_at` WITHOUT the absolute value and without the masks — the field
	the push gradient is differenced on.

	@return: The noise river's SIGNED normalised field (negative on one bank,
	         positive on the other, zero mid-channel), or the Danube's distance in
	         the same units, which is already non-negative.

	TWO DIFFERENCES FROM `river_depth_at`, and each buys the gradient something:

	  NO ABSOLUTE VALUE, so there is no kink on the centreline. `absf` is what
	  made a forward difference read the wrong bank's slope within one probe step
	  of the middle (see RIVER_DEEP_PROBE); the signed field is smooth through it,
	  and `deep_channel_push` restores the direction by multiplying by the sign it
	  already has. The Danube's distance has a kink of its own, but only ON the
	  polyline itself, where every direction is outward and the difference is
	  right by construction.

	  NO MASKS, which is `river_field_at`'s own rule one caller along: the tower
	  disc and Margaret Island are hard-edged READOUT policy, so a probe that
	  stepped onto one would read a 4.0 cliff and the gradient would point at the
	  mask instead of at the bank. Whether a body is IN a channel is
	  `river_depth_at`'s question, masks and all; which way is OUT is this one's.
	"""
	if BudapestPlan.contains(world_x, world_z):
		return BudapestPlan.danube_distance(world_x, world_z) \
				/ BudapestPlan.DANUBE_HALF_WIDTH
	return (_biome_noise(world_x, world_z) - RIVER_LEVEL) / RIVER_HALF_WIDTH


func deep_channel_push(world_pos: Vector3) -> Vector3:
	"""
	The way OUT of the impassable centre channel, or ZERO if this body is not in
	one.

	@param world_pos: The BODY's world position — Y matters, exactly as in
	                  is_wading_at.
	@return: A horizontal UNIT vector pointing at the nearest bank, or
	         Vector3.ZERO when the body is free to move.

	THE ONE HOME OF THE RULE, beside `is_wading_at` for the same reason that one
	exists: the player pushes with it, the self-check measures it, and a second
	consumer must not get a second idea of where the channel is.

	COST: the height compare and one `river_depth_at` reject every body that is
	not already mid-channel; only a body INSIDE the strip pays the two extra
	evaluations for the gradient. Zero allocation past the two Vector2s.

	IT DOES NOT REACH AN AIRBORNE BODY, and that is the design as far as the
	ruling goes: the push is the player's STEP 8.5, which is gated on `is_wading`,
	so flying over a channel is exactly as legal as flying over the band always
	was. KNOWN CEILING, measured and written down rather than discovered: the
	strip of a typical field river is ~4.8 m across (median over 178 centreline
	samples; p90 is 11 m) against a ~9.6 m wading jump, so an ordinary Space press
	clears the median river. Budapest's 96 m Danube channel and the wide bands are
	genuinely impassable. Closing that would mean pushing an airborne body, which
	is an invisible air wall and an owner call — bead godot-test1-06o.3's report
	raises it.

	NOT A COLLISION SHAPE, deliberately. The world is flat and the river is a
	shader tint — giving it a StaticBody would put thousands of bodies in the
	world, break the "no water mesh" invariant and still not follow a contour.
	"""
	if world_pos.y >= WADE_SURFACE_MAX:
		return Vector3.ZERO
	var depth := river_depth_at(world_pos.x, world_pos.z)
	if depth >= RIVER_DEEP_FRACTION:
		return Vector3.ZERO
	# THE ONE EXEMPTION, and it asks the AUTHORITY rather than a threshold: a road
	# crossing the field bridges REFUSED (a lake, past FIELD_BRIDGE_MAX_SPAN of
	# walked water) is left wadeable on purpose, and walling it would softlock the
	# road it stands on. Asked last because it is the only expensive line here and
	# only a body already inside a strip ever reaches it.
	if _deep_channel_ford(world_pos.x, world_pos.z):
		return Vector3.ZERO
	# THE GRADIENT OF THE SIGNED FIELD, TURNED OUTWARD BY ITS OWN SIGN — never a
	# difference of `river_depth_at`, which has a kink on the centreline that
	# points 1% of pushes back into the water (see RIVER_DEEP_PROBE).
	var e := RIVER_DEEP_PROBE
	var signed := _river_signed_raw(world_pos.x, world_pos.z)
	var grad := Vector2(
			_river_signed_raw(world_pos.x + e, world_pos.z) - signed,
			_river_signed_raw(world_pos.x, world_pos.z + e) - signed)
	# Exactly on the contour every direction is outward, so the sign is +1 there
	# rather than the 0 `signf` would hand back.
	if signed < 0.0:
		grad = -grad
	if grad.length_squared() <= 0.0:
		return Vector3.ZERO
	var out := grad.normalized()
	return Vector3(out.x, 0.0, out.y)


func _deep_channel_ford(world_x: float, world_z: float) -> bool:
	"""
	Is this point standing in the ONE thing the deep channel yields to — a road
	river crossing the field bridges REFUSED?

	@return: true when the road is wet at the nearest station, the point is on the
	         road, and NO STONE stands over that station.

	WHY THE AUTHORITY AND NOT A WIDTH THRESHOLD. The first version of this asked
	the field's own gradient — a band wider than FIELD_BRIDGE_MAX_SPAN
	perpendicular is a lake — which is cheap, pointwise and WRONG: the cap counts
	the water the road WALKS, and a road crossing a 100 m band at an angle walks
	124 m of it. Measured over 20 seeds, that left exactly one crossing (seed 10,
	x = 443) unbridged AND walled, which is the softlock this bead exists to
	avoid.

	AND THE AUTHORITY IS THE STONE, NOT THE ANCHOR ROW. This asked
	`field_bridge_at(k0).is_empty()` for one round, walking back to the crossing
	entry to find `k0` — and `field_bridge_at` answers `{}` for THREE reasons, only
	two of which mean "unbridged": the lake, the no-dry-abutment refusal, and "an
	earlier WESTERN anchor already owns this merged deck", where stone demonstrably
	exists. Measured over 40 seeds: 3 of 103 channel points on the road were both
	bridged and forded (seed 19 station 148, owned by anchor 131). Two of its
	returns are also un-memoized "the station cache is short right now", which
	would make the wall a function of where the player had walked — the exact class
	CLAUDE.md documents as "THE GROWTH MAY NOT READ THE STATION CACHE'S EDGE", and
	in a room two peers would disagree about a wall. `field_bridge_surface_y` is
	the query with none of those hazards: it extends the cache by
	`_field_bridge_reach()` itself, it sees merged decks and corridor decks alike,
	and it is the same question `wade_selfcheck` check 9 asks. Asking it also
	deleted the walk-back and its budget.

	IT IS THE ROAD'S WIDTH AND NOT THE RIVER'S. Off the centreline by more than
	RIVER_DEEP_FORD_HALF the same water is walled again, so a lake is a lake
	everywhere except at the ford the road drives through it.

	COST: only a body already INSIDE a deep strip ever calls this, and the two
	cheap rejects (the station's distance, and whether the road is even wet there)
	stand above the one expensive line. Warm it is 5-7 us; the first call of a run
	that lands a body in a channel near the road pays `field_bridge_at`'s cold scan
	(measured 2.3-2.7 ms), which ordinary chunk streaming has already warmed —
	a `\\fb` teleport straight into one is the case that would see it.
	"""
	var spacing := _road_spacing()
	_road_extend_to_x(world_x - spacing * 2.0, world_x + spacing * 2.0)
	var k := _road_first_k_at_or_after_x(world_x)
	if k <= road_k_min or k > road_k_max:
		return false
	# The nearer of the two stations bracketing this X — the road is a polyline
	# and the point may sit either side of the sample.
	var here: Vector2 = _road_station(k).center
	var back: Vector2 = _road_station(k - 1).center
	if absf(back.x - world_x) < absf(here.x - world_x):
		k -= 1
		here = back
	# CAP 5 again: east of the terminal station the road has no bridges of its own
	# (the corridor's are approach_bridges', and they cover every wet stretch), so
	# there is nothing here to exempt.
	if k > _road_terminal_k():
		return false
	if Vector2(world_x, world_z).distance_to(here) > RIVER_DEEP_FORD_HALF:
		return false
	if not FieldBridges._field_bridge_wet(self, k):
		return false
	return field_bridge_surface_y(Vector3(here.x, 0.0, here.y)) <= -INF


func river_field_at(world_x: float, world_z: float) -> float:
	"""
	The RAW signed river field: _biome_noise minus RIVER_LEVEL, so the river's
	centreline is the ZERO contour and the banks sit at +/- RIVER_HALF_WIDTH.

	@param world_x, world_z: World-space point (metres).
	@return: Signed distance-ish of the field from the river level. Negative on
	         one bank, positive on the other, zero mid-channel.

	Pure, allocation-free, one noise evaluation — the same cost shape as the two
	readouts beside it, for the minimap's contour tracer (bead godot-test1-06o.1):
	marching squares needs the FIELD, not the boolean, because a river is ~8 m
	wide against a ~12 px map cell and sampling the boolean only paints confetti
	along a line that is not the line. Deliberately the RAW field: no tower-disc
	and no Budapest override — those are readout policy in is_river_at(), while a
	tracer needs the unmasked number (it masks the disc itself, sample by sample).
	"""
	return _biome_noise(world_x, world_z) - RIVER_LEVEL


# ============================================================================
# FIELD ALTITUDE (the SPIKE — see FIELD_ALTITUDE at the top of the file)
# ============================================================================
# The implementation lives in scripts/terrain_altitude.gd (class_name TerrainAltitude).
# Only the two public/internal forwarders stay here.

func alt_enabled() -> bool:
	"""
	THE ONE GATE every altitude path reads.

	@return: true when the heightfield is live.

	FIELD_ALTITUDE is the shipped answer (false, always) and `alt_force` is the
	self-check's, so `altitude_selfcheck.gd` can drive both halves in one process
	without editing a const. Nothing in the game writes alt_force.
	"""
	return TerrainAltitude.alt_enabled(self)


func height_at(world_x: float, world_z: float) -> float:
	"""
	THE FIELD'S ALTITUDE at a world position — the GDScript twin of `field_height`
	in ground.gdshader, and the one function every altitude consumer reads.

	@param world_x, world_z: World-space point (metres).
	@return: Ground height in metres, signed around 0. Exactly 0.0 everywhere when
	         the spike flag is off, and exactly 0.0 inside every authored zone.
	"""
	return TerrainAltitude.height_at(self, world_x, world_z)


func in_budapest(world_x: float, world_z: float) -> bool:
	"""
	Is this world XZ inside the authored Budapest rect?

	@param world_x, world_z: The point, WORLD space (the `obstacles` list is
	                         chunk-local; convert before calling, exactly like
	                         tower_excludes below).
	@return: true when the city owns this ground.

	THE SINGLE HOME of the city's membership test on this side of the seam, the
	way tower_excludes() is the single home of the tower's. It delegates to
	BudapestPlan.contains() and adds nothing: the rect is the PLAN's number, and a
	second copy of it here is the one way the streamer and the shader could ever
	disagree about where the city is.

	IT IS DELIBERATELY NOT tower_excludes(). The tower's disc excludes everything
	procedural with one answer; the city wants a DIFFERENT answer per system —
	props off, hunters on, its own crocodiles in the river — so each spawner reads
	this predicate and decides for itself (bead godot-test1-8gw.3, DEC-9).

	Pure and allocation-free, safe to call from any spawner in any order.
	"""
	return BudapestPlan.contains(world_x, world_z)


func budapest_rect() -> Rect2:
	"""
	The city footprint as a `Rect2`, for a caller that has to intersect a SHAPE
	against it rather than ask about one point — fauna_manager tests its whole
	migration LINE (bead godot-test1-8gw.25).

	@return: The authored rect in world XZ (`position`/`size` are x/z, not x/y).

	Delegates to `BudapestPlan.rect()` and adds nothing, exactly the way
	in_budapest() delegates to contains(): the rect is the PLAN's number and a
	second copy of it on this side of the seam is how the two drift apart.
	"""
	return BudapestPlan.rect()


func tower_site() -> Vector3:
	"""
	Where the tower stands this run — the ONE position the whole tower epic
	parents to (shell, impostor, minimap marker, door, interior).

	@return: Ground-level world position (y = 0) of the tower's centre.

	FIXED, FOR EVERY RUN THAT WILL EVER BE PLAYED. Owner ruling 2026-08-29: the HQ
	is hand-planned once, so the site is (-tower_site_distance, 0, 0) and nothing
	else — not the seed, not the river field, not an RNG draw. Every peer in a
	multiplayer room agrees for free, a returning player finds it where they left
	it, and no spawner's stream is disturbed by asking. Never call an RNG from
	anywhere under here: a single draw from the shared chunk stream slides every
	crocodile in the world (see the determinism section of CLAUDE.md).

	The rivers that used to push the building around are masked under it instead —
	see THE DRY DISC and is_river_at().
	"""
	if _tower_site_dist == tower_site_distance:
		return _tower_site_cache
	_tower_site_cache = Vector3(-tower_site_distance, 0.0, 0.0)
	_tower_site_dist = tower_site_distance
	return _tower_site_cache


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
	#
	# `all_boxes()` AND NOT `boxes()`: since phase 14 the interior's plan is the keep
	# PLUS three hand-planned 80 m storeys, and the keep table alone no longer
	# describes the stone the road passes through. Run seed 309 lays a coin inside
	# the grand ramp at tower-local (-26.54, 0.9, -33.36) that `boxes()` cannot see.
	# (codex review, 2026-08-29.)
	var query := Vector3(dx, world_y, dz)
	for box: Dictionary in TowerShell.boxes() + TowerInterior.all_boxes():
		# Only the SOLID boxes. The yard slab is 3 cm of paint and the beacon is a
		# light 24 m up; a coin is welcome to sit on either.
		if not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		# A RAMP IS A TILTED SLAB and its axis-aligned box is not its stone: measured
		# untilted it claims a whole storey's height of air, which would swallow every
		# coin beside the ramp and none of the coins actually inside it. So the query
		# point moves into the box's own frame and the same three compares decide it.
		var here := query - pos
		if box.has("rot"):
			here = Basis.from_euler(box["rot"] as Vector3).inverse() * here
		if absf(here.x) < half.x + COIN_TOWER_CLEARANCE \
				and absf(here.y) < half.y + COIN_TOWER_CLEARANCE \
				and absf(here.z) < half.z + COIN_TOWER_CLEARANCE:
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
	# THE SILHOUETTE IS NOT HIDDEN HERE, and that is the point of bead
	# godot-test1-rgt. Switching it off the frame the shell arrives is a hard swap
	# between a fog-exempt cut-out and a building that is still 50-80% blended into
	# the fog at this range — the owner's "black, then it pops to white". The
	# impostor now dissolves across `TowerShell.IMPOSTOR_FADE_FAR -> _NEAR` (a
	# material property) and stops being submitted just below that (a mesh
	# property), so the handover costs this streamer nothing and has no frame in it.
	# It is transparent while it fades, so it writes no depth and cannot z-fight
	# with the shell standing inside it. TOWER_LOAD_RADIUS is what guarantees the
	# shell is here BEFORE the fade starts; tower_shell_selfcheck asserts that
	# inequality against chunk_size rather than trusting this comment.


func _tower_in_load_range(from: Vector3, site: Vector3) -> bool:
	"""Is this world point near enough the site to want the shell built? XZ only —
	the world is flat and the tower is not going anywhere vertically."""
	return Vector2(from.x - site.x, from.z - site.z).length() <= TOWER_LOAD_RADIUS


func _tower_reset() -> void:
	"""
	Put the tower back to "not built yet, and visible on the horizon".

	The SITE does not move any more (it is a constant — see tower_site()), so this
	is about the BUILDING: a shell carries the old world's opened gates, captives
	and guards, and a new run must not inherit them.

	Called from `set_run_seed()` — the seed write, every door — and so before any
	chunk is rebuilt.
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
# COIN ROAD — twelve one-line forwarders into `CoinRoad` (bd godot-test1-ftn.7)
# ============================================================================
#
# The math itself is `scripts/coin_road.gd` now; read that file's header for why
# the STATION CACHE above stayed here while the functions left.
#
# EVERY ONE OF THESE IS EARNED, and the list is grep-driven rather than guessed
# — `create_box`'s precedent (ftn.1) and `terrain_biomes`' eleven (ftn.5):
#
#   * TWO ARE REACHED BY STRING and no rename-aware tool would find them —
#     `minimap_hud` guards its road line with
#     `has_method("_road_first_k_at_or_after_x")` and `has_method("_road_terminal_k")`,
#     and `minimap_selfcheck` asserts the first of those by name.
#   * NINE SELF-CHECKS call them on the terrain (budapest, field_bridge,
#     landmark_sites, altitude, enemy_spawn, wade, minimap, tower_site,
#     tower_shell), as does `style_shots`.
#   * `terrain_predators` and `terrain_biomes` — two sibling families — call
#     `_road_station`, `_road_extend_to_x`, `_road_first_k_at_or_after_x`,
#     `_road_terminal_k` and `_road_lateral_distance` through the terrain
#     reference they are already handed. A family reaches a SIBLING family
#     through the terrain; only calls WITHIN a family go direct.
#
# Rewriting those call sites to `CoinRoad.x(terrain, ...)` buys this bead nothing
# and is the same clean follow-up ftn.5 left behind for its own eleven.

func _road_hash01(k: int) -> float:
	return CoinRoad._road_hash01(self, k)


func _road_turn(k: int) -> float:
	return CoinRoad._road_turn(self, k)


func _road_extend_to_x(x_min: float, x_max: float) -> void:
	CoinRoad._road_extend_to_x(self, x_min, x_max)


func _road_max_heading() -> float:
	return CoinRoad._road_max_heading(self)


func _road_spacing() -> float:
	return CoinRoad._road_spacing(self)


func _road_station(k: int) -> Dictionary:
	return CoinRoad._road_station(self, k)


func _road_first_k_at_or_after_x(x: float) -> int:
	return CoinRoad._road_first_k_at_or_after_x(self, x)


func _road_terminal_k() -> int:
	return CoinRoad._road_terminal_k(self)


func _road_width(k: int) -> float:
	return CoinRoad._road_width(self, k)


func _road_coins_at(k: int) -> Array:
	return CoinRoad._road_coins_at(self, k)


func _road_lateral_distance(world_x: float, world_z: float, clearance: float) -> float:
	return CoinRoad._road_lateral_distance(self, world_x, world_z, clearance)


func spawn_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	CoinRoad.spawn_coins_in_chunk(self, chunk_pos, parent_chunk, obstacles)

# ============================================================================
# FIELD BRIDGES — eight one-line forwarders into `FieldBridges` (bd godot-test1-ftn.28)
# ============================================================================
#
# The family itself is `scripts/terrain_bridges.gd` now; read that file's
# header for what stayed here and why. These eight are the names reached from
# OUTSIDE this file, measured rather than guessed (`create_box`'s precedent,
# ftn.1; `terrain_biomes`' eleven, ftn.5; `coin_road`'s twelve, ftn.7;
# `budapest_streamer`'s eight, ftn.8):
#
#   * `field_bridge_surface_y` (field_bridge_selfcheck, wade_selfcheck,
#     budapest_streamer, style_shots, _deep_channel_ford)
#   * `field_bridge_at` (field_bridge_selfcheck, style_shots)
#   * `approach_bridges` (field_bridge_selfcheck, budapest_selfcheck)
#   * `field_bridges_near` (coin_road, field_bridge_selfcheck)
#   * `field_bridge_stand_y` (terrain_predators)
#   * `_field_bridge_surface_on` (coin_road)
#   * `spawn_field_bridges_in_chunk` (field_bridge_selfcheck)
#   * `field_bridge_outer_reach` (field_bridge_selfcheck)
#
# `field_bridge_selfcheck` — the FAMILY's own check — was repointed to
# `FieldBridges._x(terrain, ...)` for the private helpers, while
# `create_chunk` calls `FieldBridges.spawn_field_bridges_in_chunk(self, ...)`
# directly.

static func field_bridge_outer_reach() -> float:
	return FieldBridges.field_bridge_outer_reach()


func field_bridge_surface_y(world_pos: Vector3) -> float:
	return FieldBridges.field_bridge_surface_y(self, world_pos)


func field_bridge_stand_y(world_x: float, world_z: float, ground_y: float) -> float:
	return FieldBridges.field_bridge_stand_y(self, world_x, world_z, ground_y)


func field_bridge_at(k0: int) -> Dictionary:
	return FieldBridges.field_bridge_at(self, k0)


func approach_bridges() -> Array:
	return FieldBridges.approach_bridges(self)


func field_bridges_near(x0: float, x1: float) -> Array:
	return FieldBridges.field_bridges_near(self, x0, x1)


func _field_bridge_surface_on(row: Dictionary, world_pos: Vector3) -> float:
	return FieldBridges._field_bridge_surface_on(self, row, world_pos)


func spawn_field_bridges_in_chunk(chunk_pos: Vector2i, block_batch: Array,
		block_body: StaticBody3D) -> void:
	FieldBridges.spawn_field_bridges_in_chunk(self, chunk_pos, block_batch, block_body)


# ============================================================================
# BUDAPEST — eight one-line forwarders into `BudapestStreamer` (bd godot-test1-ftn.8)
# ============================================================================
#
# The streamer itself is `scripts/budapest_streamer.gd` now; read that file's
# header for what stayed here and why. These eight are the names reached from
# OUTSIDE this file, measured rather than guessed (`create_box`'s precedent,
# ftn.1; `terrain_biomes`' eleven, ftn.5; `coin_road`'s twelve, ftn.7):
#
#   * `budapest_city_selfcheck` calls `spawn_city_in_chunk`,
#     `spawn_city_bridges_in_chunk`, `spawn_city_coins_in_chunk`,
#     `_approach_coin_line` and `_approach_coin_east_end` on the terrain;
#   * `field_bridge_selfcheck` calls `spawn_city_in_chunk`,
#     `spawn_approach_coins_in_chunk` and `_approach_coin_east_end`;
#   * `create_chunk` itself calls four of them in its call-order list, which is
#     the same reason `terrain_features` kept its three (bd ftn.4).
#
# `budapest_selfcheck` — the FAMILY's own check — was repointed to
# `BudapestStreamer.x(terrain, ...)` instead, which is the epic's acceptance (d)
# and the lesson `scarcity_selfcheck` taught at ftn.7: a check that reads its
# subject through a forwarder can pass for the wrong reason.
#
# The two array-uniform builders get NO forwarder: their only caller is
# `_apply_biome_shader_params` in this file, which calls the class directly.

func city_chunk(chunk_center: Vector3) -> bool:
	return BudapestStreamer.city_chunk(self, chunk_center)


func spawn_city_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	BudapestStreamer.spawn_city_in_chunk(self, chunk_pos, parent_chunk, obstacles, block_batch, block_body)


func spawn_city_bridges_in_chunk(chunk_center: Vector3, block_batch: Array,
		block_body: StaticBody3D) -> void:
	BudapestStreamer.spawn_city_bridges_in_chunk(self, chunk_center, block_batch, block_body)


func _spawn_city_landmarks_in_chunk(chunk_center: Vector3, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	BudapestStreamer._spawn_city_landmarks_in_chunk(self, chunk_center, parent_chunk, obstacles, block_batch, block_body)


func spawn_approach_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	BudapestStreamer.spawn_approach_coins_in_chunk(self, chunk_pos, parent_chunk, obstacles)


func spawn_city_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	BudapestStreamer.spawn_city_coins_in_chunk(self, chunk_pos, parent_chunk, obstacles)


func _approach_coin_line() -> PackedVector2Array:
	return BudapestStreamer._approach_coin_line(self)


func _approach_coin_east_end() -> float:
	return BudapestStreamer._approach_coin_east_end(self)

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
	2. Clear both pending queues — anything queued was computed for the old world.
	   The SEED-derived memos (the road station cache and everything strung along
	   it) are NOT cleared here: step 1's seed write drops them, in
	   `_drop_seeded_memos()`, because `set_run_seed()` is the only seam every
	   door goes through. These two queues are CHUNK state, so they stay.
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

	# 2. BOTH old-world pending queues emptied (update_chunks below rebuilds them
	# for the new world anyway; clearing here just makes the invariant explicit).
	# The removal queue in particular holds bare coordinates, and step 3 is about
	# to free everything they name — leaving stale ones around a rebuild that
	# re-uses the same coordinates is how a brand-new chunk would get freed a
	# frame later.
	#
	# THE ROAD MEMOS ARE NOT HERE ANY MORE (bead godot-test1-bvq). The station
	# cache and everything derived from it are SEED-derived, so they are dropped
	# by `_drop_seeded_memos()` inside `set_run_seed()`, which step 1 above has
	# already called down both branches. These two queues stay because they are
	# CHUNK state, not seed state: a bare re-seed does not free a chunk.
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

	FOR THE CALLERS THAT ARRIVE IN THE WORLD RATHER THAN WALKING INTO IT.
	Ground-first streaming is safe for anybody who arrives on foot: the floor is
	under them immediately and the scenery catches up around them. A mid-run
	multiplayer joiner is the exception — `MpManager._apply_join_placement()`
	rebuilds the world around the group and then has `join_at()` ask the physics
	space for a clear spot and sweep the crocodiles off it, and a question asked
	of a world whose blocks and crocodiles have not been built yet gets the
	answer "all clear" for every candidate. So that path buys the ring's content
	up front and pays the one-frame hitch it used to pay anyway.

	...AND THE TOWER WITH IT, on the same reasoning `new_run()` already applies:
	`_tower_stream()` is otherwise reached only from the next chunk-boundary
	crossing, one `_process` later, and the caller here teleports a body to the
	destination before that — a probe run against a missing building. The stream is
	still range-gated and still one-shot, so a ring nowhere near the site pays a
	single distance test.

	Cost is bounded by the ring, not the render distance: 9 chunks, the exact
	build `update_chunks` used to do synchronously on every new_run.

	Stale queue entries are deliberately left alone — `create_chunk` returns
	immediately for an already-populated chunk, so the drain reaching one later
	is a no-op.
	"""
	for x in range(around.x - SYNC_RING, around.x + SYNC_RING + 1):
		for z in range(around.y - SYNC_RING, around.y + SYNC_RING + 1):
			create_chunk(Vector2i(x, z))
	_tower_stream(chunk_to_world(around))

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


# ----------------------------------------------------------------------------
# THE PREDATOR CONSTANTS — aliases, the code is in terrain_predators.gd
# ----------------------------------------------------------------------------
##
## Bead godot-test1-ftn.6 moved every predator spawner and its constant banner
## to `scripts/terrain_predators.gd`. These names are aliased back because
## `enemy_spawn_selfcheck`, `boss_selfcheck`, `budapest_selfcheck` and
## `scarcity_selfcheck` read them off THIS script's
## `get_script_constant_map()`, and a mechanical move may not break a reader.
## The prose, the derivations and the measurements moved WITH the code — read
## them there, not here.
##
## `BIOME_SPECIES`, `BIOME_BOSS` and `SPAWN_SAFE_RADIUS` are NOT in this list:
## they stayed on this script for the reasons in TerrainPredators' header.

const HUNTER_SPECIES := TerrainPredators.HUNTER_SPECIES
const HUNTER_SCENE := TerrainPredators.HUNTER_SCENE
const HUNTER_CHANCE := TerrainPredators.HUNTER_CHANCE
const HUNTER_FIELD_CAP := TerrainPredators.HUNTER_FIELD_CAP
const HUNTER_SALT := TerrainPredators.HUNTER_SALT
const HUNTER_HASH_PRIME_X := TerrainPredators.HUNTER_HASH_PRIME_X
const HUNTER_HASH_PRIME_Y := TerrainPredators.HUNTER_HASH_PRIME_Y
const HUNTER_PLACE_TRIES := TerrainPredators.HUNTER_PLACE_TRIES
const HUNTER_EDGE_MARGIN := TerrainPredators.HUNTER_EDGE_MARGIN
const HUNTER_SPAWN_HEIGHT := TerrainPredators.HUNTER_SPAWN_HEIGHT
const HUNTER_ROLL_INDEX := TerrainPredators.HUNTER_ROLL_INDEX
const PLATFORM_SPAWN_HEIGHT := TerrainPredators.PLATFORM_SPAWN_HEIGHT
const PLATFORM_SPAWN_EDGE_INSET := TerrainPredators.PLATFORM_SPAWN_EDGE_INSET
const BOSS_INTERVAL_STATIONS := TerrainPredators.BOSS_INTERVAL_STATIONS
const BOSS_BASE_SCALE := TerrainPredators.BOSS_BASE_SCALE
const BOSS_GROWTH := TerrainPredators.BOSS_GROWTH
const BOSS_MAX_SCALE := TerrainPredators.BOSS_MAX_SCALE
const BOSS_LATERAL_MAX := TerrainPredators.BOSS_LATERAL_MAX
const BOSS_FORWARD_OFFSET := TerrainPredators.BOSS_FORWARD_OFFSET
const BOSS_FOOTPRINT_RADIUS_PER_SCALE := TerrainPredators.BOSS_FOOTPRINT_RADIUS_PER_SCALE
const BOSS_PLACE_TRIES := TerrainPredators.BOSS_PLACE_TRIES
const BOSS_SEED := TerrainPredators.BOSS_SEED
const CROC_ROLL_SALT := TerrainPredators.CROC_ROLL_SALT
const DANUBE_SALT := TerrainPredators.DANUBE_SALT
const DANUBE_HASH_PRIME_X := TerrainPredators.DANUBE_HASH_PRIME_X
const DANUBE_HASH_PRIME_Y := TerrainPredators.DANUBE_HASH_PRIME_Y
const DANUBE_CROC_CHANCE := TerrainPredators.DANUBE_CROC_CHANCE
const DANUBE_CROC_MAX := TerrainPredators.DANUBE_CROC_MAX
const DANUBE_CROC_DECK_MARGIN := TerrainPredators.DANUBE_CROC_DECK_MARGIN
const DANUBE_SLOT_BASE := TerrainPredators.DANUBE_SLOT_BASE
const CITY_CROC_DIVISOR := TerrainPredators.CITY_CROC_DIVISOR
