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

# ----------------------------------------------------------------------------
# FIELD BRIDGES — the road crosses a river ON something (bead godot-test1-06o.2)
# ----------------------------------------------------------------------------
#
# The coin road is a parametric centreline that has never asked where the water
# is, and the only bridge builder in the project is Budapest's — four authored
# decks over an authored Danube, placed off `BudapestPlan.DRY_RECTS`. Out in the
# field a river crossing is simply a wade, which is fine today and is a SOFTLOCK
# the day the rivers epic makes a channel not walkable. So every station where
# the centreline enters the water gets ONE low stone footbridge.
#
# THREE THINGS IT DELIBERATELY IS NOT:
#   * NOT a dry rect. `DRY_RECTS` punches the river out in XZ, which is why
#     Budapest's own deck note (spawn_city_bridges_in_chunk) admits you can walk
#     the river bed underneath one. Here the deck is opaque stone and the WADE
#     TEST became Y-AWARE instead (see WADE_SURFACE_MAX / is_wading_at) — the
#     water is still painted under the deck, which is correct, and standing on
#     the deck is dry because you are 1.6 m above it, and it costs the shader
#     nothing. It does NOT close Budapest's own gap: inside the rect
#     `is_river_at` delegates to `BudapestPlan.danube_wet()`, which subtracts
#     every DRY_RECTS row, so the bed under an authored deck answers DRY before
#     the height rule is asked. The cutout is shared with Margaret Island, which
#     is dry LAND at y = 0 — so closing it is a bridge-rects-only exception and
#     bead godot-test1-06o.3's call, not this one's.
#   * NOT an `obstacles` footprint. A bridge is MEANT to be walked, and a
#     footprint is a keep-out claim that would push crocodiles off the road and
#     make `_settle_coin_y` skip the coins ON the deck — the city ramp's rule.
#   * NOT one RNG draw. The site is (station index, run_seed) through the road's
#     own centreline plus `is_river_at`, both pure — so no shared stream moves
#     and every other spawner in the world is byte-identical with this feature
#     on or off (the `spawn_field_bridges` A/B, field_bridge_selfcheck check 6).

## Walking height of a field deck, metres. LOW on purpose: the ramps are
## FIELD_BRIDGE_TOP / TowerInterior.PLAN_RAMP_MAX_SLOPE long, so 1.6 m buys a
## 2.8 m approach at the shipped ceiling and the whole bridge stays inside the
## few stations either side of the water. A Budapest deck is at 12 m because
## ships pass under it; nothing passes under this one.
const FIELD_BRIDGE_TOP: float = 1.6

## Deck slab thickness (the box hangs UNDER the walking surface, the city's
## convention, so the ramp tops meet it flush).
const FIELD_BRIDGE_THICKNESS: float = 0.5

## HALF the deck's width. 8 m is wider than it needs to be to walk and narrower
## than every road clearance in play — the smallest is CHEST_ROAD_CLEARANCE
## (10.0, = road_width_max * 0.5), so no prop, chest, camp or landmark can ever
## be standing where a deck lands. field_bridge_selfcheck check 5 asserts that
## inequality against every *_ROAD_CLEARANCE const in this file rather than
## against a number typed here twice.
const FIELD_BRIDGE_HALF_WIDTH: float = 8.0

## The widest crossing that gets a bridge, in metres of centreline walked
## through the water. Past this it is not a river the road crosses, it is a LAKE
## the road runs into — a 300 m causeway would be a landmark nobody authored, so
## the road wades it, and the rivers epic's not-walkable bead owes that case an
## answer of its own (a ford, a detour, or a real crossing).
##
## 120, NOT THE 40 THE BEAD SKETCHED, and the difference is the GRAZING CROSSING.
## A band is ~8-25 m wide, so even a perpendicular crossing is only ~25 m of
## centreline — but the road's heading cap is 78 degrees, and a road running
## nearly ALONG a river walks 8 / cos(78 deg) = 38 m through the same 8 m of
## water, and the span is measured across the deck's whole WIDTH, which finds the
## water a station or two earlier at each bank. Those are the crossings a short
## cap throws away, and they are not lakes. Measured over
## field_bridge_selfcheck's sixteen seeds: at 80 m, 4 of 40 crossings went
## unbridged; at 120 m, one does — and that one is standing water.
const FIELD_BRIDGE_MAX_SPAN: float = 120.0

## How far past the last WET station the deck reaches, in stations. One station
## either side puts both abutments on dry ground with a whole station of margin,
## which is what makes "the ramp foot is dry" a property of the geometry rather
## than of the noise field's exact gradient at one point.
const FIELD_BRIDGE_DRY_STATIONS: int = 1

## Step used when probing the river band for the deck's width, metres. The probe
## is three lanes wide (the centreline and both parapets) so the deck covers the
## water at its EDGES too, not just under the walking line.
const FIELD_BRIDGE_PROBE_STEP: float = 1.0

## How far a ramp foot may be pushed back to get its whole WIDTH onto dry land
## (see _field_bridge_foot). Pushing lengthens the run at a fixed rise, so it can
## only make the ramp gentler; 30 m is far more bank than any measured crossing
## has needed, and check 4 prints the worst push it found.
const FIELD_BRIDGE_FOOT_PUSH_MAX: float = 30.0

## How far a deck may carry on PAST the water at deck height, at each end, to
## reach ground where its abutment's whole 16 m section is dry.
##
## It is not the span cap and it is not the push budget: a river that runs
## ALONGSIDE the road (seed 218 grazes one within 8 m for 186 m, seed 777001 for
## 150 m) leaves no dry section for a foot anywhere near the crossing, and the
## alternative to carrying on at 1.6 m is dragging a RAMP along the water — which
## is under WADE_SURFACE_MAX for its first 2.4 m, i.e. a hero wading on a bridge.
## 300 m covers every grazing stretch field_bridge_selfcheck has measured (the
## longest bank actually walked is ~110 m); past it the crossing is refused and
## the lake rule takes it. It is also the term that dominates
## _field_bridge_reach(), i.e. how many stations a cold window scan walks — 600
## here cost the first query of a run 33 ms, one whole frame-spike budget.
const FIELD_BRIDGE_BANK_WALK_MAX: float = 300.0

## Slop on a slab's own faces when asking whether a point stands on it. A
## millimetre: big enough that the exact edge of a slab answers "yes" whichever
## way the last bit of a dot product falls, small enough to be no geometry.
const EDGE_EPS: float = 0.001

## Slop added to the DERIVED slab stretch at a deck-to-deck joint (see
## _field_bridge_joint_ext, which computes half * tan(turn / 2) — the exact depth
## of the wedge a turn opens at the outer parapet).
##
## THE STRETCH IS ONLY EVER AT A DECK-TO-DECK JOINT, never where a slab meets a
## RAMP. A slab overhanging the head of a ramp is a step down onto it — and a
## step is the one thing CharacterBody3D cannot climb at all, so walking back up
## would be a jump gate outdoors, which is exactly what this bead exists to
## prevent. The ramp and the slab it meets are made COLINEAR instead, so that
## joint opens no wedge at all. field_bridge_selfcheck check 2 samples the wedge
## arc at every joint rather than trusting either half of this argument.
const FIELD_BRIDGE_SLAB_MARGIN: float = 0.05

## The private colour stream, CITY_STREAM_SEED's reason one feature along:
## create_box spends four draws per box on a colour ramp this builder overrides
## anyway, and a draw taken from a stream somebody else reads slides every
## crocodile in the world.
const FIELD_BRIDGE_STREAM_SEED: int = 0x0_6021

## Field decks are the same slate the city's ramps and pavements are cut from —
## one stone vocabulary outdoors, and a colour is not worth a hash stream.
const FIELD_BRIDGE_STONE := Color(0.58, 0.58, 0.60)

## THE TRIM (bead godot-test1-06o.4). Owner on the .2 screenshot, a flat grey
## deck angled across the water: "parapets/pylons" — a bare slab reads as a
## floating plate. So every field bridge is dressed in the CITY'S bridge
## vocabulary (_city_chain_bridge / _city_margaret_bridge are the reference:
## stone edge walls and a portal pair at the bank), scaled from a 12 m Danube
## deck to a 1.6 m field one, through the SAME create_box batch, the SAME centre
## rule and the SAME zero-RNG rule as the deck itself.
##
## THE PARAPET'S INNER FACE IS EXACTLY FIELD_BRIDGE_HALF_WIDTH, which is the
## whole of "it must not narrow the lane": the wall is CANTILEVERED off the deck
## edge rather than standing on it, so the walkable width, `field_bridge_surface_y`,
## every wet probe and every span measurement are byte-for-byte what they were
## and only boxes were added. It reaches DOWN past the deck's own underside too
## (hence the + FIELD_BRIDGE_THICKNESS on its height), which is what gives the
## slab a visible edge beam instead of a paper edge.
##
## It is the ONE colliding piece of trim — a rail you can walk through is not a
## rail — and 1.0 m is chest-high on a hero and far under the jump apex, so it
## fences the drop without fencing anybody in.
##
## KNOWN CEILING, measured (16 seeds, 458 bridge chunks): every spawner that
## drops something near a deck reads `field_bridge_surface_y`, which knows the
## 8 m walking rect and can never see trim — so at a RAMP FOOT, where the rail
## descends through coin and animal height, 3 road coins in 517 stood inside a
## parapet and 1 crocodile in ~450 spawned in one. Both are thin-wall cases that
## depenetration and a 0.6 m pickup sphere resolve, and the alternative is an
## `obstacles` footprint, which this feature is forbidden (it would push
## crocodiles off the road and make _settle_coin_y skip the deck's own coins).
const FIELD_BRIDGE_PARAPET_WIDTH: float = 0.5
const FIELD_BRIDGE_PARAPET_HEIGHT: float = 1.0

## The pylon pair at each bank — the portal the Chain Bridge puts at each end of
## its span, four boxes instead of ninety-two. They stand from the GROUND to
## FIELD_BRIDGE_TOP + rise, so a deck that used to hang in the air is visibly
## carried at both ends, and they straddle the parapet OUTBOARD of its centre
## line (see the builder) so nothing of them is ever over the lane.
##
## NOT FLUSH WITH THE PARAPET, and that is the whole of the offset: a pylon
## whose inner face shares the parapet's plane is two coincident opaque faces at
## every bank of every bridge, i.e. z-fighting on the one thing this bead exists
## to make look right. It is pushed out half a parapet so the two solids
## interpenetrate instead of touching.
##
## NON-COLLIDING, like every other piece of ornament in this game that nobody
## needs to climb: they cost the chunk body no shape, and a post at the very
## edge of a 16 m deck is scenery, not geometry.
##
## The width's real ceiling is `field_bridge_outer_reach()` against the tightest
## *_ROAD_CLEARANCE (check 5) — 2.0 m of headroom over the deck's half-width,
## not check 2's "a metre outside the parapet" control, which reads a box list
## FILTERED to the deck rect and can see no trim at all.
## SQUARE IN PLAN, and it was judged by eye: 0.9 x 1.6 read as a dark FIN
## standing on the deck rather than as a post.
const FIELD_BRIDGE_PYLON_WIDTH: float = 0.9
const FIELD_BRIDGE_PYLON_DEPTH: float = 0.9
const FIELD_BRIDGE_PYLON_RISE: float = 3.2

## Trim tones, FIELD_BRIDGE_STONE's neighbours and consts for its reason: a
## colour is not worth a hash stream, and three flat greys is what tells a
## parapet from a deck from a pylon at 100 m.
const FIELD_BRIDGE_PARAPET_STONE := Color(0.66, 0.65, 0.64)
const FIELD_BRIDGE_PYLON_STONE := Color(0.50, 0.50, 0.53)

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

## Noise-space half-width of the soft colour transition between biomes, used as
## a smoothstep radius in the ground shader. Purely cosmetic: gameplay reads the
## hard thresholds above, the eye reads this blend.
const BIOME_BLEND: float = 0.05

# ----------------------------------------------------------------------------
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

## THE SELF-CHECK SEAM for the flag above. `altitude_selfcheck.gd` drives both
## the flag-off and the flag-on paths in ONE process, which a `const` alone
## cannot express — so alt_enabled() is the single gate every altitude path
## reads and this var is the only other thing it looks at. THE GAME NEVER WRITES
## IT: nothing outside a self-check may set it, which is what keeps "the flag is
## a const" true in every shipped build.
var alt_force: bool = false

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

# ----------------------------------------------------------------------------
# BUDAPEST — THE CITY STREAMER (bead godot-test1-8gw.3)
# ----------------------------------------------------------------------------
##
## What spawn_city_in_chunk needs that BudapestPlan does not carry. The plan is
## the DESIGN — where the hills are, how wide the avenue is, which liberties were
## taken with the map — and a designer edits it. These are the MATERIALS: how
## thick a slab is and what colour the stone is, which is this file's business,
## beside CITY_PLASTER_* and every other palette and thickness in it.

## The seed of the city streamer's PRIVATE RandomNumberGenerator, and it is a
## CONSTANT for two reasons that both matter.
##
## PRIVATE, because create_box draws four numbers per box for its colour ramp and
## one extra draw taken from the chunk's shared stream slides every crocodile in
## the world (see the determinism block in SECTION 1). The city is authored, so
## it has nothing to seed from anyway — this stream exists only to feed those
## discarded draws.
##
## CONSTANT rather than per-chunk, because every box the streamer places passes
## an explicit color_override and a plateau whose slices each drew their own
## colour would be a different grey on either side of every chunk seam. One seed,
## one hill.
const CITY_STREAM_SEED: int = 0x8_6D4_9E51

## The plateau massifs' stone, and their ramps' — ONE colour for both, because
## they are the same hill. Deliberately duller and greyer than CITY_PLASTER_*:
## Castle Hill has to read as the rock the city stands ON rather than as another
## building on it.
const CITY_HILL_STONE := Color(0.47, 0.45, 0.41)

## A plateau ramp's slab thickness, metres. Thick enough to read as a viaduct
## from the side, thin enough that the head of the ramp never pokes up through
## the plateau's lid.
const CITY_RAMP_THICKNESS: float = 1.0

## A BRIDGE DECK's slab thickness, metres. Thicker than a ramp because it is read
## from BELOW as well — you wade under it — and because the Margaret Bridge's
## piers top out at y = 11 and its arches spring from there, so a 1.2 m slab hung
## off BudapestPlan.BRIDGE_DECK_TOP lands its underside exactly on them. The
## approach ramps stay CITY_RAMP_THICKNESS: they meet the deck at its TOP surface,
## which is the only place a step could appear.
const CITY_BRIDGE_DECK_THICKNESS: float = 1.2

## The avenue's pavement slab: 4 cm, straddling y = 0, and collide = FALSE.
##
## The avenue is a READ — the thing that says "this way into the city" — and not
## a corridor. The ground under it is already flat and walkable, so a COLLIDING
## lip would buy nothing and cost 900 m of kerb for a CharacterBody3D to catch its
## toe on. Same reasoning as the forest canopies' collide = false: pure decoration
## pays for its pixels and not for a collision shape.
##
## WHICH IS EXACTLY WHY IT MUST BE THIN AND CENTRED ON THE GROUND. Nothing stands
## ON this slab — the player walks the y = 0 plane straight through it, capsule
## bottom at y = 0 and the model's feet with it — so every centimetre of pavement
## above y = 0 is a centimetre of shin rendered inside opaque stone, for the whole
## 750 m of the one authored route out of the gate. A kerb-height 15 cm slab sunk
## its feet; 4 cm straddling zero leaves 2 cm proud (enough to read as pavement
## and to stay off the ground plane's own depth) and 2 cm buried out of sight.
const CITY_AVENUE_THICKNESS: float = 0.04
const CITY_AVENUE_STONE := Color(0.62, 0.60, 0.56)

## THE GATE DISTRICT'S STREET DRESSING (DEC-11) — where the jb7 city prop
## builders are called, and how big.
##
## The spots are DERIVED from DISTRICT_HOUSES rather than typed into a second
## table: one prop in each gap between neighbouring houses, alternating sides,
## cycling _prop_crate_stack / _prop_garden_wall / _prop_paving_stack. Seven
## props, no new plan data, and the dressing follows the houses if a designer
## moves them.
##
## Z IS THE LOAD-BEARING NUMBER. 14 m off the centreline puts the widest prop's
## own footprint (2.0 * PROP_RADIUS_FACTOR = 1.42) at 12.6 m, comfortably clear
## of the avenue's 8 m half-width — the corridor out of the gate has to stay
## walkable, and a crate stack standing in it is exactly the failure the .3
## acceptance walk looks for.
const CITY_DISTRICT_PROP_Z: float = 14.0
const CITY_DISTRICT_PROP_SIZE: float = 2.0

## ---------------------------------------------------------------------------
## THE CITY BLOCKS (bead godot-test1-8gw.9) — how a street wall is DRAWN
## ---------------------------------------------------------------------------
##
## The LAYOUT is BudapestPlan's (which cell, which wing, how deep, how many
## storeys); everything below is the PALETTE AND THE THICKNESSES, which is the
## same division of labour DISTRICT_HOUSES already runs under — the plan carries
## shade FACTORS and this file carries the colours they lerp between.
##
## ONE FACADE BOX PER BUILDING, NEVER ONE BOX PER WINDOW. A 46 m block side is
## two segments, each ONE colliding hull, and the articulation that makes it read
## as a street is VERTEX-COLOURED BANDS lying against it: a ground-floor
## shopfront, a balcony course, a roof cornice and one doorway. Seven boxes buy a
## whole side of a Budapest block; a window grid would buy a tenth of one and
## blow CITY_CHUNK_BOX_BUDGET on the first cell.
##
## THE STREAM IS PER-CELL AND FIXED-SALT — the tower furniture precedent
## (`TowerDressing.plan_dressing`'s FIXED salt, never run_seed). Budapest is authored, so the
## facade a player photographs has to be the same facade every run and for every
## peer; and a cell's stream must not depend on which chunk is asking, because a
## block straddles up to four of them. Both fall out of seeding one RNG off
## (cell.x, cell.y, CITY_BLOCK_SALT) and drawing every parameter ANYTHING READS
## before emitting anything — see _build_city_block for why that qualifier is
## exact, and why create_box's own ramp draws after it are padding that may
## legitimately differ between two chunks slicing one cell.
const CITY_BLOCK_SALT: int = 0x8_DA9E_571

## A storey, in metres. 4.2 is a tall Pest piano-nobile floor rather than a
## modern 3 m one, which is what makes a 5-storey block read as 21 m of eclectic
## facade instead of a suburban office.
const CITY_STOREY_HEIGHT: float = 4.2

## The bands. Each is a thin, NON-COLLIDING box lying against the hull and
## standing `*_PROUD` metres off its faces on the cross axis — the hull is the
## only thing with a collision shape, so a band can never be something to snag on.
## EVERY PROUD IS POSITIVE, and it has to be: the batch is opaque boxes with no
## cutouts, so a band set back INSIDE the hull is a band nobody can see — see
## CITY_WINDOW_PROUD, which is where that was learned the expensive way.
const CITY_SHOPFRONT_HEIGHT: float = 2.9    # ground floor, one storey of glass
const CITY_SHOPFRONT_PROUD: float = 0.16
const CITY_AWNING_THICKNESS: float = 0.22
const CITY_AWNING_PROUD: float = 0.62       # oversails the shopfront it shades
const CITY_BALCONY_THICKNESS: float = 0.26
const CITY_BALCONY_PROUD: float = 0.52
const CITY_CORNICE_THICKNESS: float = 0.55
const CITY_CORNICE_PROUD: float = 0.46
const CITY_DOOR_WIDTH: float = 1.5
const CITY_DOOR_HEIGHT: float = 2.4
const CITY_DOOR_PROUD: float = 0.10

## ONE WINDOW ROW PER STOREY, and it is a ROW and not a window.
##
## The owner asked for Google-Street-View Budapest and the first cut shipped
## blank slabs: a 21 m facade with a single cornice line on it reads as a wall,
## not as a building. What makes a real facade legible at 30 m is the HORIZONTAL
## RHYTHM of its window courses, so each storey above the shopfront gets one
## recessed dark band the full width of the facade. That is ONE box per storey
## against the ~30 a window grid would cost, and it is the same trade the
## shopfront and cornice already make.
##
## THE TWO-TONE IS FREE: the band's glass colour alternates by storey parity
## (CITY_WINDOW_DARK / CITY_WINDOW_LIT), so a five-storey facade reads as five
## distinct courses rather than one striped texture, and it costs no extra box.
##
## IT STANDS PROUD, AND IT HAS TO. The first cut RECESSED these bands into the
## wall, which is what a real window reveal does and which is invisible here: the
## batch is opaque boxes with no cutouts, so a band inside the hull is a band you
## cannot see, and all it actually produced was z-fighting where the two surfaces
## nearly met. 6 cm proud is flush to the eye at street distance and is the only
## thing that makes the course exist at all.
const CITY_WINDOW_HEIGHT: float = 1.60
const CITY_WINDOW_PROUD: float = 0.06
const CITY_WINDOW_SILL: float = 1.15        # sill height above the storey floor

## ...AND IT IS PULLED IN AT ITS ENDS, which is the OTHER half of the same lesson
## (bead godot-test1-8gw.19). A proud band was still drawn to the hull's exact
## length, so while its street face stood 6 cm clear its two END faces landed on
## the hull's end planes at a separation of EXACTLY zero — measured, 20.8 m² of
## shared face per pair, 37 hull/window pairs in a single chunk. Zero fights at
## any depth precision on any renderer, which is why raising the camera's near
## plane (bead 8gw.17) did nothing for it; and coplanar QUADS fight along their
## shared diagonal, which is why the owner saw "instead of rectangular i see
## triangle for a moment" rather than two colours swapping.
##
## It was visible on most of every other street wall, not in a corner: block_wing
## spans the north/south wings the full width of the ring and insets the side
## wings by BLOCK_WING_DEPTH, so a ±X street wall is end face, front face, end
## face — 26 of 43.6 m fighting — while the ±Z walls of the same block are clean,
## and vice versa.
##
## 4 cm, applied to the WHOLE building rect before _city_chunk_slice so that
## neighbouring chunks still cut one rect and still meet flush. It changes no box
## count, costs no RNG draw, and is invisible at street scale.
const CITY_BAND_END_INSET: float = 0.04

## The block palette. Walls reuse the CITY_PLASTER_A/B pair the gate district's
## houses lerp between, so Budapest is ONE city and not two; the rest is new
## because a 5-storey facade has parts a 2.5 m cottage does not.
const CITY_SHOPFRONT_GLASS := Color(0.20, 0.22, 0.25)   # dark glazing + signage
const CITY_BALCONY_IRON := Color(0.24, 0.24, 0.26)      # wrought-iron course
const CITY_DOOR_WOOD := Color(0.30, 0.20, 0.14)         # the carriage gateway
const CITY_WINDOW_DARK := Color(0.20, 0.23, 0.27)       # a shaded course
const CITY_WINDOW_LIT := Color(0.29, 0.33, 0.38)        # ...and a sunlit one
const CITY_AWNING_A := Color(0.60, 0.25, 0.22)          # shop canvas, red
const CITY_AWNING_B := Color(0.26, 0.42, 0.33)          # ...and green

## THE FACADE HUES, one array per bank of the river, and a building picks ONE.
##
## A block whose eight buildings are eight lerps along a single cream-to-grey
## ramp is a block of one building repeated. Pest is ECLECTIC — the real thing is
## cream beside ochre beside grey-green beside rose — and Buda under the castle
## is whitewash, ochre and brick red. The per-building tint below still runs, but
## it now varies a chosen hue instead of choosing the hue.
const CITY_FACADE_PEST: Array[Color] = [
	Color(0.90, 0.86, 0.75),   # cream
	Color(0.84, 0.70, 0.44),   # ochre
	Color(0.69, 0.73, 0.65),   # grey-green
	Color(0.84, 0.69, 0.67),   # rose
	Color(0.77, 0.75, 0.71),   # stone grey
]
const CITY_FACADE_BUDA: Array[Color] = [
	Color(0.93, 0.92, 0.87),   # whitewash
	Color(0.86, 0.73, 0.49),   # ochre
	Color(0.73, 0.44, 0.35),   # brick red
]

## How far a building's own draw may shade its chosen hue toward the weathered
## render, 0..1. Small: this is grime and sun, not a second colour choice.
const CITY_FACADE_TINT_MAX: float = 0.30

## The share of PEST buildings that carry a balcony course. Balconies everywhere
## are a texture; balconies on two facades of a block are a detail the eye
## lands on. Buda's 2-3 storey houses get none at all.
const CITY_BALCONY_CHANCE: float = 0.42

## How far a block's own facade stream may push a segment off the cell's base
## storey count, in storeys. +-1 is a stepped roofline; more and the block stops
## reading as one period.
const CITY_BLOCK_STOREY_JITTER: int = 1

## THE CITY'S PER-CHUNK CEILINGS — what a Budapest chunk is allowed to cost.
##
## A chunk in Pest is an ordinary chunk: ONE MultiMesh, ONE collision body, built
## in the same one-chunk-per-frame drain as a chunk of cactus. These three numbers
## are what says so, and `budapest_selfcheck` check 4 measures every chunk in the
## 2.2 km rect against them and prints the worst one it found beside each ceiling.
##
## MEASURED over the whole rect (2025 chunks, 2026-09-02, with ALL 22 landmark
## builders placed, the four bridge decks built and — since bead
## godot-test1-8gw.9 — every block of the street grid FILLED): worst 145 boxes,
## worst 15 collision shapes, worst 1.1 ms, over 96,770 boxes and 1,631 chunks
## with stone. The ms budget is deliberately loose because it is wall-clock on
## whatever machine CI happens to be — it is a runaway detector, not a benchmark.
##
## THE BOX BUDGET MOVED 120 -> 200 WHEN THE BLOCKS LANDED, and that is the one
## raise this file has taken. The history is worth keeping because it says what
## each number measures:
##
##   wave B, seven slots still reservations    69 boxes   15 shapes   7.4 ms
##   all 22 landmarks + the four decks         92 boxes   15 shapes   3.0 ms
##   ...and every block filled (bead .9)      145 boxes   15 shapes   1.1 ms
##
## The worst chunk is STILL a Parliament slice; the densest all-block chunk is
## 119. Collision is unmoved at 15 because a building's only colliding box is its
## hull — every band is decoration. Bead .9's own note said to raise this budget
## and the web residency proof TOGETHER if a dense chunk needed it, and this is
## that raise: see CITY_RESIDENCY_BOX_BUDGET in budapest_selfcheck.gd, which went
## 3000 -> 6000 against a measured 4,510 in the same pass.
##
## The box number is still the one to watch: a landmark builder that stopped
## being a pure function of (centre, rng) would emit its whole self into every
## chunk its disc touches instead of its own slice, and THAT is what this catches
## — 268 boxes of Parliament in one 50 m square instead of the dozen that stand
## in it.
const CITY_CHUNK_BOX_BUDGET: int = 200
const CITY_CHUNK_SHAPE_BUDGET: int = 40
const CITY_CHUNK_MS_BUDGET: float = 12.0

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
	mat.set_shader_parameter("city_river", _city_river_segments())
	# CLAMPED, like the arrays themselves: the asserts in the two builders below are
	# stripped in an exported build — which is the web build, the one target this
	# shader exists for — so a plan that outgrew CITY_SEG_MAX / CITY_DRY_MAX would
	# ship a count past the end of a GLSL array uniform. That read is undefined in
	# GLSL ES 3.00. Losing the last bend is a bug budapest_selfcheck catches; a
	# driver-dependent out-of-range fetch is not.
	mat.set_shader_parameter("city_river_count",
			mini(BudapestPlan.DANUBE.size() - 1, CITY_SHADER_SEG_MAX))
	mat.set_shader_parameter("city_river_half", BudapestPlan.DANUBE_HALF_WIDTH)
	mat.set_shader_parameter("city_dry", _city_dry_rects())
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
	mat.set_shader_parameter("alt_offset", ALT_OFFSET_SALT)
	mat.set_shader_parameter("alt_cell_size", ALT_CELL_SIZE)
	mat.set_shader_parameter("alt_detail_scale", ALT_DETAIL_SCALE)
	mat.set_shader_parameter("alt_detail_weight", ALT_DETAIL_WEIGHT)
	mat.set_shader_parameter("alt_detail_shift", ALT_DETAIL_SHIFT)
	mat.set_shader_parameter("alt_amp_desert", ALT_AMP_DESERT)
	mat.set_shader_parameter("alt_amp_plains", ALT_AMP_PLAINS)
	mat.set_shader_parameter("alt_amp_city", ALT_AMP_CITY)
	mat.set_shader_parameter("alt_amp_forest", ALT_AMP_FOREST)
	mat.set_shader_parameter("alt_amp_mountain", ALT_AMP_MOUNTAIN)
	mat.set_shader_parameter("alt_amp_snow", ALT_AMP_SNOW)
	mat.set_shader_parameter("alt_city_skirt", ALT_CITY_SKIRT)
	mat.set_shader_parameter("alt_tower_skirt", ALT_TOWER_SKIRT)
	mat.set_shader_parameter("alt_river_skirt_k", ALT_RIVER_SKIRT_K)
	mat.set_shader_parameter("alt_road_flat_half", ALT_ROAD_FLAT_HALF)
	mat.set_shader_parameter("alt_road_skirt", ALT_ROAD_SKIRT)
	# THE ROAD POLYLINE THE CPU IS ALREADY USING — read straight back out of
	# _alt_road_segs rather than rebuilt, which is the whole reason that cache
	# exists: parity by construction, so the corridor the GPU flattens and the
	# corridor the collision heightmap flattens can never be two different windows.
	mat.set_shader_parameter("alt_road_seg", _alt_road_seg_uniform())
	# CLAMPED for the same reason city_river_count is: the assert in the padder
	# below is stripped in an exported build, and a count past the end of a GLSL
	# array uniform is an undefined read in GLSL ES 3.00.
	mat.set_shader_parameter("alt_road_seg_count",
			mini(_alt_road_segs.size(), ALT_ROAD_SEG_MAX))


func _alt_road_seg_uniform() -> PackedVector4Array:
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
	assert(_alt_road_segs.size() <= ALT_ROAD_SEG_MAX,
			"_alt_road_segs holds more segments than the GLSL array can carry — the push clamps and the GPU flattens a shorter corridor than the collision heightmap does")
	for i in mini(_alt_road_segs.size(), ALT_ROAD_SEG_MAX):
		segs[i] = _alt_road_segs[i]
	return segs


func _city_river_segments() -> PackedVector4Array:
	"""
	The Danube polyline as (x1, z1, x2, z2) segments, for ground.gdshader's
	`city_river` array uniform.

	Padded to CITY_SEG_MAX (8) because a GLSL array uniform is that size whatever
	the polyline's length is; the shader reads `city_river_count` of them and the
	padding is never touched. If a future author adds a sixth point to DANUBE, the
	assert below is what tells them the shader's array has to grow with it.
	"""
	var segs := PackedVector4Array()
	segs.resize(CITY_SHADER_SEG_MAX)
	assert(BudapestPlan.DANUBE.size() - 1 <= CITY_SHADER_SEG_MAX,
			"BudapestPlan.DANUBE has more segments than ground.gdshader's CITY_SEG_MAX")
	for i in range(mini(BudapestPlan.DANUBE.size() - 1, CITY_SHADER_SEG_MAX)):
		var a: Vector2 = BudapestPlan.DANUBE[i]
		var b: Vector2 = BudapestPlan.DANUBE[i + 1]
		segs[i] = Vector4(a.x, a.y, b.x, b.y)
	return segs


func _city_dry_rects() -> PackedVector4Array:
	"""
	The dry rects — bridge decks and Margaret Island — as (xmin, zmin, xmax, zmax)
	for ground.gdshader's `city_dry`, padded to CITY_DRY_MAX exactly like the
	segments above and read `city_dry_count` deep.
	"""
	var rects := PackedVector4Array()
	rects.resize(CITY_SHADER_DRY_MAX)
	assert(BudapestPlan.DRY_RECTS.size() <= CITY_SHADER_DRY_MAX,
			"BudapestPlan.DRY_RECTS has more rows than ground.gdshader's CITY_DRY_MAX")
	for i in range(mini(BudapestPlan.DRY_RECTS.size(), CITY_SHADER_DRY_MAX)):
		var r: Rect2 = BudapestPlan.DRY_RECTS[i]
		rects[i] = Vector4(r.position.x, r.position.y,
				r.position.x + r.size.x, r.position.y + r.size.y)
	return rects


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
		_alt_road_refresh(float(player_chunk.x) * chunk_size + chunk_size / 2.0)

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
		collision_shape.shape = _alt_ground_heightmap(chunk_pos)
		# THE UNIFORM SCALE, and why the heights were pre-divided by it upstream:
		# HeightMapShape3D cells are ONE unit wide and the grid is centred on the
		# node, so an 18-wide map spans -8.5..+8.5 units. The chunk is chunk_size
		# (50 m) across, so the shape is stretched by alt_ground_cell() (2.941) to
		# reach -25..+25 m. UNIFORM is the operative word — a non-uniformly scaled
		# shape is a Godot warning and an unsupported physics case — so the scale
		# hits Y as well, and _alt_ground_heightmap already divided every stored
		# height by the same factor to cancel it back out.
		collision_shape.scale = Vector3.ONE * alt_ground_cell()
		ground_collision_usec_total += Time.get_ticks_usec() - started_usec
		# THE CULL VOLUME, because the displacement is a VERTEX SHADER and the
		# renderer cannot see it. The shared PlaneMesh's AABB is chunk_size x 0 x
		# chunk_size, so a chunk whose flat quad is just outside the frustum has
		# its 22 m hilltop culled with it and the hillside pops. PER-INSTANCE — the
		# shared mesh resource is untouched, and the flag-off branch below sets
		# nothing at all, so today's world keeps today's AABB exactly.
		var half_span := chunk_size / 2.0
		mesh_instance.custom_aabb = AABB(
				Vector3(-half_span, -ALT_AMP_MAX, -half_span),
				Vector3(chunk_size, 2.0 * ALT_AMP_MAX, chunk_size))
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
	spawn_field_bridges_in_chunk(chunk_pos, block_batch, block_body)

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
# GEO LANDMARKS (see the GEO LANDMARKS constant banner)
# ============================================================================

func landmark_sites() -> Dictionary:
	"""
	THE WHOLE FIELD LANDMARK PLACEMENT FOR THIS RUN: chunk Vector2i -> kind index.

	@return: The memoized site table. At most one entry per LANDMARKS kind, at most
	         one kind per chunk. Read-only to callers — it is the cache itself, not
	         a copy, because it is asked once per chunk generated.

	Pure in `run_seed` (and in the road centreline, which is itself pure in
	run_seed), so every peer in a room and every regeneration of the same run agree
	for free — the same argument the old per-chunk roll made, one level up. Built
	lazily on the first ask and dropped by `set_run_seed()` (through
	`_drop_seeded_memos()`) beside the station cache it is derived from; see the
	MUSEUM MILE banner for the design.
	"""
	if _landmark_sites_built:
		return _landmark_sites_cache
	_landmark_sites_cache = _build_landmark_sites()
	_landmark_sites_built = true
	return _landmark_sites_cache


func landmark_site(kind: int) -> Vector2i:
	"""
	Where kind `kind` stands this run, as CHUNK coordinates.

	@param kind: Index into LandmarkBuilders.LANDMARKS.
	@return: The kind's chunk, or LANDMARK_SITE_NONE when every attempt was
	         rejected and this run simply has no such place. Callers must test.

	The forward direction of `landmark_sites()`, and the one a future minimap mark
	for an UNVISITED landmark would read: it answers for a chunk that has never
	streamed in. Linear in the table (48 entries), which is fine for a UI ask and
	is why the SPAWNER uses the reverse lookup instead.
	"""
	var sites: Dictionary = landmark_sites()
	for chunk: Vector2i in sites:
		if int(sites[chunk]) == kind:
			return chunk
	return LANDMARK_SITE_NONE


func _build_landmark_sites() -> Dictionary:
	"""
	Choose one site per LANDMARKS kind. Called once per run by landmark_sites().

	@return: chunk Vector2i -> kind index.

	THE MILE AND THE ANNULUS. The corridor is the road centreline from STATION 0
	(the spawn, where the road is defined to begin) to the terminal station T,
	which is every metre of road a run's consumers acknowledge. It is divided into
	slots LANDMARK_MILE_SPACING
	apart; kinds 0..slots-1 take one slot each, and every remaining kind takes a
	station drawn uniformly from the same span with a 0.5-2.5 km lateral offset
	instead of a 60-120 m one. There is no third case: the mile and the annulus
	differ ONLY in the offset band and in how the station is picked.

	A SLOT IS METRES OF X, NOT A COUNT OF STATIONS, and that is not a nicety. The
	road CURVES, so a station advances `_road_spacing() * cos(heading)` of X and
	not the full 6 m — measured 4.0 m over the shipped corridor. Counting stations
	per slot therefore packs the mile ~1.5x denser than LANDMARK_MILE_SPACING says,
	and does it differently on every seed (the same 1450 m spans a different number
	of stations in every world). So a slot's target X is arithmetic and the STATION
	is looked up from it, through the same binary search every other road consumer
	uses.

	ONE HASH PER ATTEMPT, and it carries everything. `hash(Vector3i(...))` is folded
	into three independent fields — 12 bits of along-slot jitter, 12 bits of
	lateral offset, one bit of side — so a rejected attempt re-hashes with a new
	`attempt` and moves the whole site rather than nudging one axis. That is the
	bead's "deterministic re-hash with a bounded attempt count, never a chunk draw".

	SIDES ALTERNATE BY KIND PARITY on the mile (walking the trail should not be
	48 detours to the left) and are hashed in the annulus, where there is no walk
	order to alternate along.

	A kind whose LANDMARK_SITE_TRIES attempts are all rejected has NO SITE this
	run. That is the honest degrade: the alternative is relaxing a rule that exists
	because the HQ, the city, the spawn bubble and the river are places a monument
	must not stand in.

	AND THE CORRIDOR STOPS AT THE SPAWN RATHER THAN REACHING BACK TO THE HQ, which
	is a CONSTRAINT and not a preference. This table is global and pre-computed, so
	anything it reads is read for the WHOLE world — it cannot take the post-draw
	skip every per-chunk rejection in this file takes. `tower_site_selfcheck`
	check 5 is what says so out loud: it moves the tower and demands that a chunk
	the disc does not reach be byte-identical, and a corridor whose west end was
	`tower_site().x` moved all 48 sites when the tower moved. Station 0 is the
	road's own origin and depends on nothing. The 400 m of road west of the spawn
	is the HQ's approach and belongs to the building, not to the museum.
	"""
	var sites: Dictionary = {}
	var kinds: int = LandmarkBuilders.LANDMARKS.size()

	# The corridor, in station indices: station 0 (the spawn, where the road is
	# DEFINED to begin) to the terminal station T. _road_extend_to_x is the uncapped
	# station cache (see _road_terminal_k's docstring for why the CONSUMERS cap and
	# it does not); T is the consumer cap and this is consumer number five.
	var mile_x_min: float = 0.0
	_road_extend_to_x(mile_x_min, ROAD_TERMINAL_X)
	var k_first: int = _road_first_k_at_or_after_x(mile_x_min)
	var k_last: int = _road_terminal_k()
	var span: int = maxi(1, k_last - k_first)
	# The corridor in METRES of X (see the docstring for why not in stations), and
	# how many LANDMARK_MILE_SPACING slots fit in it.
	var corridor: float = maxf(1.0, _road_station(k_last).center.x - mile_x_min)
	var mile_slots: int = clampi(int(corridor / LANDMARK_MILE_SPACING), 0, kinds)

	for kind in kinds:
		for attempt in LANDMARK_SITE_TRIES:
			var h: int = hash(Vector3i(
				kind * LANDMARK_HASH_PRIME_X,
				attempt * LANDMARK_HASH_PRIME_Y,
				run_seed ^ LANDMARK_SITE_SALT))
			# Three independent fields off one hash. Mask AFTER the shift: hash()
			# may return a negative and `>>` on one is arithmetic.
			var u_along: float = float(h & 0xFFF) / 4096.0
			var u_lateral: float = float((h >> 12) & 0xFFF) / 4096.0
			var station: int
			var lateral: float
			var side: float
			if kind < mile_slots:
				# MILE — an evenly spaced slot, jittered inside its own slot so two
				# runs do not stand their monuments on the same metre marks.
				var target_x: float = mile_x_min + (float(kind) + u_along) * LANDMARK_MILE_SPACING
				station = _road_first_k_at_or_after_x(target_x)
				lateral = lerpf(LANDMARK_MILE_LATERAL_MIN, LANDMARK_MILE_LATERAL_MAX, u_lateral)
				side = 1.0 if kind % 2 == 0 else -1.0
			else:
				# ANNULUS — anywhere along the same corridor, far off it.
				station = k_first + int(u_along * float(span))
				lateral = lerpf(LANDMARK_FIELD_LATERAL_MIN, LANDMARK_FIELD_LATERAL_MAX, u_lateral)
				side = 1.0 if ((h >> 24) & 1) == 0 else -1.0
			station = clampi(station, k_first, k_last)
			var st: Dictionary = _road_station(station)
			var heading: float = st.heading
			# Same perp construction as _road_coins_at / _boss_at (XZ plane;
			# Vector2.x is world X, Vector2.y is world Z).
			var perp := Vector2(-sin(heading), cos(heading))
			var spot: Vector2 = st.center + perp * (side * lateral)
			var chunk: Vector2i = world_to_chunk(Vector3(spot.x, 0.0, spot.y))
			if _landmark_site_ok(chunk, sites):
				sites[chunk] = kind
				break

	return sites


func _landmark_site_ok(chunk: Vector2i, taken: Dictionary) -> bool:
	"""
	May kind K stand in this chunk? Asked of a CHUNK, not of a spot, because the
	site table is chunk-keyed and the exact metre inside it is still chosen by
	spawn_landmark_in_chunk's candidate loop against the finished `obstacles`.

	@param chunk: Candidate chunk coordinates.
	@param taken: Sites accepted so far this build.
	@return: false when the chunk is somebody else's, the HQ's, the city's, the
	         spawn bubble's or a river's.

	THE PAIRWISE SPACING RULE IS "DISTINCT CHUNKS", AND THAT IS ARITHMETIC.
	The bead asks for >= 2x the largest declared radius (2 * LANDMARK_RADIUS = 19 m)
	between two sites. A candidate stays LANDMARK_EDGE_MARGIN (12) inside its own
	chunk, so its centre is at most chunk_size/2 - 12 = 13 m from the chunk centre.
	Two landmarks in edge-adjacent chunks are therefore at least 50 - 13 - 13 = 24 m
	apart, and diagonally at least 70.7 - 2*13*sqrt(2) = 33.9 m. Both clear 19, so
	one Dictionary lookup buys the whole rule and there is no distance loop here.
	`landmark_sites_selfcheck` asserts the CONSEQUENCE (>= 19 m, measured on real
	built centres) rather than this argument.

	THE WHOLE CHUNK IS TESTED against the HQ and the spawn bubble, not its centre:
	a chunk half inside the disc would put its candidate loop to work looking for
	the one corner that clears it, and a monument crowding the HQ gate is the thing
	tower_excludes() exists to prevent. `chunk_size` as the radius is the diagonal
	half-width rounded up, i.e. deliberately generous.

	THE HQ CLAUSE CANNOT FIRE TODAY and it stays anyway. No station of the museum
	mile's corridor is west of the spawn and no annulus site is within 500 m of the
	centreline, so nothing this table proposes reaches a disc 400 m west on the road
	— which is exactly what keeps the table's global pre-computation compatible with
	`tower_site_selfcheck` check 5 (see `_build_landmark_sites`). It is one line and
	it is the project's single home for tower clearance, which every sibling spawner
	also calls; if a future corridor DOES reach the HQ, this is where the rejection
	belongs, and that check is where the consequence will be argued out.

	THE RIVER TEST is at the chunk CENTRE only, and it is a cheap pre-reject rather
	than the rule: `_biome_spot_ok` still refuses a wet candidate metre by metre in
	the spawner. Rejecting the chunk here is what stops a kind spending every one of
	its LANDMARK_PLACE_TRIES in a band it can never clear and vanishing from the run.
	"""
	if taken.has(chunk):
		return false
	var world: Vector3 = chunk_to_world(chunk)
	# Budapest owns its ground: the city's landmarks are the plan's 22 authored
	# slots, and a rolled Eiffel beside the authored one is the bug DEC-9 named.
	if in_budapest(world.x, world.z):
		return false
	if tower_excludes(world.x, world.z, chunk_size):
		return false
	if Vector2(world.x, world.z).length() < SPAWN_SAFE_RADIUS + chunk_size:
		return false
	if is_river_at(world):
		return false
	return true


func _landmark_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	THE REVERSE LOOKUP: does any kind's site land in this chunk?

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when no kind stands here (all but ~48 chunks in the world);
	         otherwise { "seed": int, "kind": int } — the seed for the landmark's
	         private RNG (spawn_landmark_in_chunk uses it for placement, geometry
	         and the coin ring) and the index into LANDMARKS of WHICH famous place
	         this is.

	Same signature and same contract as `_chest_at` / `_camp_at` / `_artifact_at`,
	and still consumes NO draw from the shared chunk RNG — but it is no longer a
	rarity roll at all. It is one Dictionary lookup in `landmark_sites()`, which is
	pure in run_seed and built once per run. See the MUSEUM MILE banner for why the
	question was inverted and why `scarcity_at` is no longer asked here.

	THE PRIVATE SEED IS KEYED ON THE KIND, not on the chunk. The kind is unique now,
	so (kind, run_seed) identifies the landmark exactly as (chunk, run_seed) used
	to — and the builders' stream touches COLOUR ONLY plus the in-chunk candidate
	spot, so this is the same "a private stream per landmark" contract it always
	was. Keying it on the chunk instead would work too and would be strictly worse:
	the palette would then depend on where the site happened to land.

	WHY THERE IS STILL NO CANDIDATE LOOP HERE. This is the landmine that BOTH
	artifacts and camps had to be dug out of, and it is worth restating rather than
	cross-referencing, because the next person to add a landmark family member will
	reach for it again: when this function runs, THE CHUNK HAS NO GEOMETRY YET. The
	only tests available are river and road, and neither rejects the thing that
	actually matters — overlap with the chunk's ~12 scattered blocks, its feature
	structure, its biome trees and massifs, its artifact and its camp. So the
	LANDMARK_PLACE_TRIES loop lives in spawn_landmark_in_chunk, where `obstacles`
	exists, and this function does exactly one thing: answer whether.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL landmark (same place, same
	  spot, same stone jitter, same coin ring) however often it unloads and
	  regenerates: the site table is pure in run_seed, and every draw downstream
	  comes off one stream seeded from the kind in a fixed order.
	- Across runs, new_run() re-rolls run_seed, so a new world puts the same 48
	  places somewhere else entirely (and the road they are strung along moves too).
	- MULTIPLAYER NEEDS ZERO WORK because of exactly that: run_seed is already
	  shared by every peer in a room, so every peer generates the same landmark in
	  the same chunk by construction. No packet, no claim, no sync.
	- Whether a candidate is ACCEPTED is likewise load-order independent: the road
	  test reads the station cache (pure in `k`), the river test reads the biome
	  field (pure in world position + run_seed) and the overlap test reads the
	  chunk's own obstacle list (pure in chunk coords + run_seed).
	"""
	var sites: Dictionary = landmark_sites()
	if not sites.has(chunk_pos):
		return {}
	var kind: int = int(sites[chunk_pos])
	return {
		"seed": hash(Vector3i(kind, LANDMARK_SALT, run_seed)),
		"kind": kind,
	}



func spawn_landmark_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's geo landmark, if a kind's site lands here, plus its coin
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
	# BUDAPEST — no FIELD geo landmarks in the city (DEC-9). The builders are the
	# same ones the rect uses, but WHERE they stand is the plan's 22 authored slots
	# and not the museum mile — two Eiffel Towers, one authored and one sited, in
	# the same district. NOT tower_excludes(): per-system answers.
	#
	# BELT AND BRACES SINCE THE MUSEUM MILE: `_landmark_site_ok` already refuses a
	# chunk in the rect, so no site is ever here. It stays because this is the
	# spawner's own statement of the city policy every sibling spawner also makes,
	# and it costs one rectangle test on a path that already reads chunk_to_world.
	var lm_center := chunk_to_world(chunk_pos)
	if in_budapest(lm_center.x, lm_center.z):
		return
	if not spawn_landmarks:
		return
	var lm := _landmark_at(chunk_pos)
	if lm.is_empty():
		return

	# The landmark's OWN private RNG, seeded off (kind, run_seed) by _landmark_at:
	# it picks the spot AND feeds the builder AND draws the coin ring, so each
	# consumes as many draws as it needs without any other stream caring.
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
	# EVERY TRY FAILING MEANS NO LANDMARK, and since the museum mile that means NO
	# SUCH PLACE IN THIS WORLD rather than "one chunk in fifty went without" — the
	# whole reason LANDMARK_PLACE_TRIES is 200 and not 4. It is still the right
	# call: the Eiffel Tower sticking out of a mountain massif reads far worse than
	# a world without an Eiffel Tower.
	#
	# THE RADIUS ASKED FOR IS THE ROW'S OWN, NOT LANDMARK_RADIUS, and that changed
	# with the museum mile (bead godot-test1-bcf). The sibling spawners hand over
	# "the widest this could be" because their shape is drawn from the same stream
	# AFTER the spot is chosen, so its real width is genuinely unknown here — but a
	# landmark's is DECLARED in its registry row, `landmark_selfcheck` asserts every
	# builder fits inside it, and the kind is known before the loop starts. Asking
	# for 9.5 m when the row says 4.2 was pure conservatism, and it stopped being
	# free the moment a rejected chunk meant the Sagrada Familia is not in this
	# world at all rather than "one chunk in fifty went without". LANDMARK_RADIUS
	# stays the GLOBAL BOUND every inequality in the banner is derived from
	# (the edge margin, the road clearance, the coin-ring pad) — this is the one
	# place that wanted the specific number instead of the bound.
	var entry: Dictionary = LandmarkBuilders.LANDMARKS[lm.kind]
	var want_radius: float = minf(float(entry.radius), LANDMARK_RADIUS)
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < LANDMARK_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if _biome_spot_ok(chunk_center, local_x, local_z, want_radius, LANDMARK_ROAD_CLEARANCE, obstacles):
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
	if not _field_bridge_wet(k):
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
#
# The same shape as the biome field above and for the same reasons: a function of
# (world x, world z, run_seed) with no RNG draw and no hash stream, so a revisited
# chunk regenerates byte-identically — with ONE named exception, the road
# corridor's sliding window, which height_at()'s docstring states and bounds; and a
# two-language
# twin in ground.gdshader that is EDITED TOGETHER with this one, because the
# ground you see displaced and the ground you stand on have to be the same
# surface. It reuses _biome_value_noise / _biome_hash2 rather than bringing its
# own lattice hash — one hash in the whole project is what keeps the fp32 port
# honest, and it means the height field inherits the mod(289) wrap that stops
# the noise collapsing out at kilometre X.

func alt_enabled() -> bool:
	"""
	THE ONE GATE every altitude path reads.

	@return: true when the heightfield is live.

	FIELD_ALTITUDE is the shipped answer (false, always) and `alt_force` is the
	self-check's, so `altitude_selfcheck.gd` can drive both halves in one process
	without editing a const. Nothing in the game writes alt_force.
	"""
	return FIELD_ALTITUDE or alt_force


func _alt_value_noise_pair(p: Vector2) -> float:
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
	var broad := Vector2(_biome_value_noise(p) * w.x, 0.0).x
	var detail := Vector2(_biome_value_noise(p * ALT_DETAIL_SCALE + ALT_DETAIL_SHIFT) * w.y, 0.0).x
	return Vector2(broad + detail, 0.0).x


func _alt_amplitude(biome_value: float) -> float:
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
			smoothstep(BIOME_DESERT_MAX - BIOME_BLEND, BIOME_DESERT_MAX + BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_CITY,
			smoothstep(BIOME_PLAINS_MAX - BIOME_BLEND, BIOME_PLAINS_MAX + BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_FOREST,
			smoothstep(BIOME_CITY_MAX - BIOME_BLEND, BIOME_CITY_MAX + BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_MOUNTAIN,
			smoothstep(BIOME_FOREST_MAX - BIOME_BLEND, BIOME_FOREST_MAX + BIOME_BLEND, biome_value))
	amp = lerpf(amp, ALT_AMP_SNOW,
			smoothstep(BIOME_MOUNTAIN_MAX - BIOME_BLEND, BIOME_MOUNTAIN_MAX + BIOME_BLEND, biome_value))
	return amp


func _alt_road_window() -> float:
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
			* _road_spacing()


func _alt_road_segments(center_x: float) -> PackedVector4Array:
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
	if not alt_enabled():
		return segs
	# Grown in X, because that is the only thing _road_extend_to_x speaks — but the
	# window is then taken in STATIONS around the player's own station, NOT as the
	# X range itself. The road's heading cap is 78 degrees, so a curving stretch
	# advances as little as 1.25 m of X per 6 m station: an X-ordered walk starting
	# at center_x - _alt_road_window() spends its whole segment budget hundreds of
	# metres WEST of the player and leaves the ground under their feet uncorridored.
	# Centring on the station is what makes the window a window around the player.
	var reach := _alt_road_window()
	_road_extend_to_x(center_x - reach, center_x + reach)
	var k_last := mini(road_k_max, _road_terminal_k())
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
	var k_center: int = _road_first_k_at_or_after_x(center_x)
	k_center -= posmod(k_center, ALT_ROAD_SEG_STRIDE)
	var k := k_center - half * ALT_ROAD_SEG_STRIDE
	# Clamped ON THE LATTICE — a bare maxi(road_k_min, ...) would put the western
	# end back on an arbitrary station and reintroduce exactly what the snap fixed.
	while k < road_k_min:
		k += ALT_ROAD_SEG_STRIDE
	var k_end := mini(k_last, k_center + half * ALT_ROAD_SEG_STRIDE)
	var prev := Vector2.ZERO
	var have_prev := false
	while k <= k_end and segs.size() < ALT_ROAD_SEG_MAX:
		var c: Vector2 = _road_station(k).center
		if have_prev:
			segs.append(Vector4(prev.x, prev.y, c.x, c.y))
		prev = c
		have_prev = true
		k += ALT_ROAD_SEG_STRIDE
	return segs


func _alt_road_refresh(center_x: float) -> void:
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
	_alt_road_segs = _alt_road_segments(center_x)
	_apply_biome_shader_params()


func _alt_road_distance(world_x: float, world_z: float) -> float:
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
	for seg: Vector4 in _alt_road_segs:
		var d := BudapestPlan.segment_distance(p, Vector2(seg.x, seg.y), Vector2(seg.z, seg.w))
		if d < best:
			best = d
	return best


func _alt_flat_mask(world_x: float, world_z: float, biome_value: float) -> float:
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
	var site := tower_site()
	var tower_d := p.distance_to(Vector2(site.x, site.z))
	mask *= smoothstep(TOWER_RADIUS, TOWER_RADIUS + ALT_TOWER_SKIRT, tower_d)

	# CLAUSE 3 — EVERY RIVER BAND, in FIELD units. This is the same
	# |_biome_noise - RIVER_LEVEL| < RIVER_HALF_WIDTH test is_river_at() makes, so
	# the water's edge and the flat edge are one number: rivers stay at y = 0 and
	# wading stays XZ-only with no edit. Deliberately the RAW field, exactly as the
	# shader has it in `b` — the tower and city overrides is_river_at() applies are
	# readout policy, and both of those zones are already flattened above.
	mask *= smoothstep(RIVER_HALF_WIDTH, RIVER_HALF_WIDTH * ALT_RIVER_SKIRT_K,
			absf(biome_value - RIVER_LEVEL))

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
			_alt_road_distance(world_x, world_z))

	return mask


func height_at(world_x: float, world_z: float) -> float:
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
	if not alt_enabled():
		return 0.0
	var p := Vector2(world_x, world_z) / ALT_CELL_SIZE + biome_offset + ALT_OFFSET_SALT
	var n := _alt_value_noise_pair(p)
	# 0..1 -> -1..1, so the field cuts valleys as well as raising hills and its
	# mean stays at the y = 0 the whole game is written against.
	var signed_unit := Vector2((n - 0.5) * 2.0, 0.0).x
	# ONE _biome_noise() evaluation, spent twice: the amplitude ladder and the flat
	# mask's river clause are both readouts of the same number, and the shader twin
	# passes it to both for the same reason.
	var b := _biome_noise(world_x, world_z)
	var h := Vector2(signed_unit * _alt_amplitude(b), 0.0).x
	return Vector2(h * _alt_flat_mask(world_x, world_z, b), 0.0).x


func alt_ground_cell() -> float:
	"""
	Metres between two adjacent ground vertices — the heightmap's cell size and the
	CollisionShape3D's uniform scale, which are the same number by construction.

	@return: chunk_size spread over ALT_GROUND_SIDE - 1 spans (2.941 m at 50 m).

	PUBLIC because altitude_selfcheck reads it back; there is nowhere else the two
	call sites could agree except one function.
	"""
	return chunk_size / float(ALT_GROUND_SIDE - 1)


func _alt_ground_heightmap(chunk_pos: Vector2i) -> HeightMapShape3D:
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
	var side := ALT_GROUND_SIDE
	var shape := HeightMapShape3D.new()
	shape.map_width = side
	shape.map_depth = side

	# The metres-per-cell the CollisionShape3D's uniform scale will apply. Heights
	# are DIVIDED by it here so that scale multiplies them back to the metres
	# height_at() returned — the alternative, a non-uniform scale of (cell, 1,
	# cell), is a Godot warning and unsupported by the physics server.
	var cell := alt_ground_cell()
	var origin := chunk_to_world(chunk_pos)
	var half := chunk_size / 2.0

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
			data[iz * side + ix] = (height_at(world_x, world_z) + GROUND_COLLISION_TOP) / cell
	shape.map_data = data
	return shape



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

func _road_terminal_k() -> int:
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
	if _road_terminal_k_cache != ROAD_TERMINAL_K_UNSET:
		return _road_terminal_k_cache
	_road_extend_to_x(ROAD_TERMINAL_X, ROAD_TERMINAL_X)
	_road_terminal_k_cache = _road_first_k_at_or_after_x(ROAD_TERMINAL_X) - 1
	return _road_terminal_k_cache

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
	if k > _road_terminal_k():
		return []

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
	for slot in road_coin_slots:
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
		if posmod(k * road_coin_slots + slot, 10) < 3:
			continue
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
	var k_last := mini(road_k_max, _road_terminal_k())
	while k <= k_last:
		var st: Dictionary = _road_station(k)
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
		var terminal: Vector2 = _road_station(_road_terminal_k()).center
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

# ============================================================================
# SECTION — FIELD BRIDGES (bead godot-test1-06o.2)
# ============================================================================
#
# See the FIELD BRIDGES const block near the top for what this is and the three
# things it deliberately is not. The shape of the feature, in four functions:
#
#   _field_bridge_wet(k)      is the road in the water at station k (3 lanes)
#   field_bridge_at(k0)       the whole bridge anchored at station k0, memoized
#   field_bridges_near(x0,x1) every bridge whose stone can reach an X window
#   field_bridge_surface_y(p) how high the walking surface is over an XZ, or -INF
#
# The last two are PUBLIC for spawn_city_bridges_in_chunk's reason: the coin
# spawner reads the surface to stand a coin on a deck, and field_bridge_selfcheck
# walks the plan and measures the stone against it.

func _field_bridge_run() -> float:
	"""
	The horizontal RUN of one approach ramp, metres.

	Derived from the rise and the slope BUDAPEST'S OWN BRIDGES climb at, read out
	of BudapestPlan rather than restated: the city and the field have one ramp
	feel, and retuning the city's retunes this. The ceiling it must stay under is
	TowerInterior.PLAN_RAMP_MAX_SLOPE — "no traversal outdoors may demand a
	jump-height" is the tower's rule and the same one here — which
	field_bridge_selfcheck check 3 asserts off the built stone, so this derivation
	cannot quietly drift past it.
	"""
	return FIELD_BRIDGE_TOP * BudapestPlan.BRIDGE_RAMP_RUN / BudapestPlan.BRIDGE_DECK_TOP


static func field_bridge_outer_reach() -> float:
	"""
	How far from the walking line ANY of a bridge's stone reaches — the deck's
	half-width plus the widest piece of trim standing outboard of it.

	The number check 5 measures against every *_ROAD_CLEARANCE in this file, and
	it is a DERIVATION rather than FIELD_BRIDGE_HALF_WIDTH read a second time:
	the parapet and the pylons are cantilevered off the deck edge (see the trim
	const block), so the stone now reaches further than the lane does and the
	"no prop can ever stand on a deck" contract is about the stone.
	"""
	return FIELD_BRIDGE_HALF_WIDTH + maxf(FIELD_BRIDGE_PARAPET_WIDTH,
			FIELD_BRIDGE_PARAPET_WIDTH * 0.5 + FIELD_BRIDGE_PYLON_WIDTH)


func _field_bridge_reach() -> float:
	"""
	How far in X a bridge's stone can reach from its anchor station — the pad
	every X-window scan in this section widens by, spawn_coins_in_chunk's `pad`
	one feature along.

	The span is capped at FIELD_BRIDGE_MAX_SPAN of CENTRELINE (and X advances no
	faster than the centreline does), plus the dry stations either end, plus a
	ramp at each end, plus the slab stretch. Deliberately a loose upper bound: it
	costs a few stations of scanning and it is what makes "no chunk misses a piece
	of a bridge that reaches into it" true by arithmetic.
	"""
	# ONE bank walk and ONE ramp, not two of each: this is how far the stone
	# reaches from its anchor IN ONE DIRECTION, and the scan pads BOTH sides by
	# it. Doubling them made the window 2.9 km wide and the first cold query of a
	# run 33 ms — one frame's whole spike budget, spent walking stations whose
	# decks could never touch the chunk being built.
	return FIELD_BRIDGE_MAX_SPAN \
			+ float(2 * FIELD_BRIDGE_DRY_STATIONS + 2) * _road_spacing() \
			+ _field_bridge_run() + FIELD_BRIDGE_FOOT_PUSH_MAX \
			+ 2.0 * FIELD_BRIDGE_HALF_WIDTH \
			+ FIELD_BRIDGE_BANK_WALK_MAX


func _field_bridge_dry_across(centre: Vector2, dir: Vector2) -> bool:
	"""
	Is a deck-wide cross-section at `centre` DRY ALL THE WAY ACROSS?

	@param centre: The centreline point, world XZ.
	@param dir: The direction the deck runs in (unit); the section is measured
	            perpendicular to it.
	@return: false the moment any sample of the section stands in a river band.

	THE WHOLE WIDTH, NOT THREE LANES. A river is a contour crossed at an angle, so
	its edge is at a different place on the deck's north side than on its south —
	and a section is 16 m wide. Sampling the centre and the two parapets passed a
	foot with a wet patch 0.5 m inside one edge (seed 12, anchor 122), which is a
	flank a player wades up: the band under a foot slab has no deck over it, so
	the Y-aware wade never sees stone. FIELD_BRIDGE_PROBE_STEP samples, both edges
	included.

	ONE PRIMITIVE, TWO CALLERS — the span walk (is the road in the water here) and
	the abutment probe (is this foot on the bank) are the same question about the
	same rectangle, and they disagreed once. No allocation and no RNG draw: this
	decides WHERE a bridge is, and a single draw would slide every crocodile in
	the world.
	"""
	var perp := Vector2(-dir.y, dir.x)
	var lane := -FIELD_BRIDGE_HALF_WIDTH
	while lane < FIELD_BRIDGE_HALF_WIDTH + FIELD_BRIDGE_PROBE_STEP * 0.5:
		var at := centre + perp * minf(lane, FIELD_BRIDGE_HALF_WIDTH)
		if is_river_at(Vector3(at.x, 0.0, at.y)):
			return false
		lane += FIELD_BRIDGE_PROBE_STEP
	return true


func _field_bridge_wet(k: int) -> bool:
	"""
	Is the road IN THE WATER at station `k` — on the CENTRELINE, over the stretch
	of it this station owns?

	@param k: Station index; the cache must already cover it (k-1 and k+1 too).
	@return: true when any centreline sample between the midpoints either side of
	         station `k` stands in a river band.

	THE CENTRELINE, NOT THE WIDTH, AND THAT IS THE WHOLE SPAN RULE. Wading is
	decided where the HERO is, which is the centreline; the 16 m section is about
	where the deck's FEET may stand and belongs to `_field_bridge_foot` alone. A
	span measured on the section counts a road that merely runs ALONGSIDE a river
	as being in it: on seed 218 the road grazes one within 8 m for 186 m, which
	turned an ordinary 18 m crossing into a "lake" and left it unbridged, and on
	seed 777001 a 150 m section-run swallowed two real crossings of 17.5 m and
	65 m. Both are the deep strip bead godot-test1-06o.3 makes impassable.

	IT SAMPLES THE STRETCH, NOT THE POINT, for the corridor scan's reason one
	table along: a station is ~6 m of road and a river band can be narrower, so
	asking only at the station centre steps over one. The window is half a
	station either side, so consecutive stations tile the centreline with no gap
	and no overlap.

	No allocation and no RNG draw: this decides WHERE a bridge is, and a single
	draw would slide every crocodile in the world.
	"""
	return _field_bridge_wet_metres(k) > 0.0


func _field_bridge_wet_metres(k: int) -> float:
	"""
	How many metres of the CENTRELINE this station owns are in the water.

	@param k: Station index; the cache must already cover k-1 and k+1.
	@return: The wet length inside the window between the midpoints either side
	         of station `k`, sampled at FIELD_BRIDGE_PROBE_STEP.

	IT IS A LENGTH, NOT A FLAG, because the span cap is a length: adding up
	distances between wet station CENTRES omits the entry station's own share and
	both partial intervals at the banks, which on seed 296 totalled 120.0 m for a
	124.5 m crossing and bridged past the cap. The flag above is this answer
	compared to zero, so the two can never disagree about where the water is.

	MEMOIZED per station, and it is the hot path of the whole feature: every
	station in a scan window is asked as `k` and again as `k - 1`, and the growth
	loops ask it again. `_drop_seeded_memos()` drops it with the bridges it feeds.
	"""
	if _field_bridge_wet_cache.has(k):
		return _field_bridge_wet_cache[k]
	var centre: Vector2 = _road_station(k).center
	var back: Vector2 = (_road_station(k - 1).center + centre) * 0.5 \
			if k - 1 >= road_k_min else centre
	var fwd: Vector2 = (_road_station(k + 1).center + centre) * 0.5 \
			if k + 1 <= road_k_max else centre
	var wet := _centreline_wet_metres(back, fwd)
	_field_bridge_wet_cache[k] = wet
	return wet


func _field_bridge_out_dir(k: int, sign: int) -> Vector2:
	"""
	The unit direction a ramp at deck end `k` runs AWAY from the deck in —
	westward for `sign` -1, eastward for +1.

	IT IS THE CONTINUATION OF THE LAST DECK SEGMENT, not the next station's
	bearing, because that is the direction `_field_bridge_row_from` gives the
	foot: a ramp colinear with the slab it meets leaves no wedge at the parapet.
	Testing the growth along the road's NEXT segment instead measures a ramp
	nobody builds, and where the road turns the two disagree enough to refuse a
	crossing that would have been fine (seed 777001, station 71).
	"""
	var here: Vector2 = _road_station(k).center
	var inward: Vector2 = _road_station(k - sign).center
	return (here - inward).normalized()


func _field_bridge_ramp_dry(head: Vector2, foot: Vector2) -> bool:
	"""
	Is the whole RAMP RECTANGLE — every deck-wide section from the deck's end
	`head` down to `foot` — clear of the water?

	The abutment's real question, and the growth loop's too: a ramp that lands on
	a dry section but crosses a shallow on the way is a stretch of bridge under
	WADE_SURFACE_MAX with water beside it, which a hero on the parapet wades.
	"""
	var run := head.distance_to(foot)
	if run <= 0.0:
		return _field_bridge_dry_across(head, Vector2.RIGHT)
	var dir := (foot - head) / run
	var steps := int(run / FIELD_BRIDGE_PROBE_STEP)
	for i in range(steps + 1):
		if not _field_bridge_dry_across(head + dir * minf(
				float(i) * FIELD_BRIDGE_PROBE_STEP, run), dir):
			return false
	return _field_bridge_dry_across(foot, dir)


func _field_bridge_section_dry(k: int) -> bool:
	"""Is a deck-wide section across station `k` dry all the way across? The
	abutment's question (see _field_bridge_dry_across), asked of a station."""
	var st: Dictionary = _road_station(k)
	var heading: float = st.heading
	return _field_bridge_dry_across(st.center, Vector2(cos(heading), sin(heading)))


func _centreline_wet_metres(from: Vector2, to: Vector2) -> float:
	"""
	How many metres of this centreline segment are in a river band, sampled at
	FIELD_BRIDGE_PROBE_STEP.

	EACH SAMPLE OWNS THE INTERVAL AHEAD OF IT, never the interval AND the
	end-point: charging `steps + 1` samples a full step each reports `span +
	step` for a fully wet segment, and summed over a crossing's stations that
	overcounted seed 19's 115.8 m of water as 139.7 m and refused the bridge as a
	lake under a 120 m cap. So a fully wet segment contributes exactly `span`.

	The far end-point belongs to the NEXT segment's first sample — consecutive
	station windows tile the centreline (see _field_bridge_wet_metres), so no
	metre is counted twice and none is missed.

	The one home of "the road is in the water HERE", shared by the station walk,
	the approach corridor's and the span cap.
	"""
	var span := from.distance_to(to)
	var steps := int(span / FIELD_BRIDGE_PROBE_STEP)
	if steps < 1:
		# Shorter than one probe step: one sample, and it owns what there is.
		return span if is_river_at(Vector3(from.x, 0.0, from.y)) else 0.0
	var step_len: float = span / float(steps)
	var wet := 0.0
	for i in range(steps):
		var at: Vector2 = from.lerp(to, float(i) / float(steps))
		if is_river_at(Vector3(at.x, 0.0, at.y)):
			wet += step_len
	return wet


func _field_bridge_foot(head: Vector2, out_dir: Vector2) -> Vector2:
	"""
	Where one ramp's FOOT stands: back along `out_dir` from the deck's end, far
	enough that the whole width of the abutment is on dry land.

	@param head: The deck end this ramp climbs to (a station centre).
	@param out_dir: Unit vector pointing AWAY from the deck, along the ramp.
	@return: The foot point, world XZ — or `Vector2.INF` when no dry foot exists
	         inside the push budget, which REFUSES the whole bridge.

	THE CENTRELINE IS NOT THE ABUTMENT. The foot is a 16 m wide slab at y = 0, so
	a corner of it can stand in the river while its centre is dry — and a player
	walking up that side keeps wading until the ramp has risen past
	WADE_SURFACE_MAX, which is the whole bridge undone on one flank (measured:
	seed 12, station 116, the east foot's north corner). So both corners are
	PROBED, and the foot is pushed further out until they are dry.

	PUSHING IS FREE AND CANNOT BREAK THE SLOPE: the rise is fixed at
	FIELD_BRIDGE_TOP, so a longer run is a GENTLER ramp, always further under
	TowerInterior.PLAN_RAMP_MAX_SLOPE than the base run already is.

	# ponytail: a bank still wet 30 m back is refused rather than merged with the
	# crossing next door. Merging is the richer answer (two spans and one long
	# deck between them) and it is a bead of its own; refusing keeps the promise
	# this file makes — every bridge it builds is standing on dry ground at both
	# ends — and field_bridge_selfcheck counts the refusals.
	"""
	var run := _field_bridge_run()
	var pushed := 0.0
	while pushed <= FIELD_BRIDGE_FOOT_PUSH_MAX:
		var foot := head + out_dir * (run + pushed)
		# THE WHOLE RAMP RECTANGLE, not the foot's section and the centreline. A
		# ramp is under WADE_SURFACE_MAX for its first 2.4 m and it is 16 m wide,
		# so a hero hugging its parapet over a bank shallow wades on a bridge —
		# measured on six seeds, ~1-3 m of one edge each. The rectangle is every
		# section from the deck's end down to the foot.
		if _field_bridge_ramp_dry(head, foot):
			return foot
		pushed += FIELD_BRIDGE_PROBE_STEP
	# NEVER A KNOWN-WET FOOT. Out of budget the honest answer is that this bank
	# cannot carry an abutment, so the CROSSING is refused and the lake rule takes
	# it (the road wades, and bead godot-test1-06o.3 owes the case an answer) —
	# returning the last point tried would plant a 16 m slab in the river and call
	# it a bridge, which is worse than no bridge because it looks like one.
	return Vector2.INF


func _field_bridge_joint_ext(dir_a: Vector2, dir_b: Vector2, half: float) -> float:
	"""
	How far each slab must be stretched past a deck-to-deck joint to close the
	wedge of open air the turn opens at the outer parapet.

	@param dir_a, dir_b: The two slabs' unit directions, in order.
	@param half: Half the deck's width.
	@return: The stretch, metres — zero for a straight joint.

	DERIVED, NEVER A CONSTANT, and the constant is why: two rectangles meeting at
	an angle `d` leave a triangle at the outer edge whose depth is
	half * tan(d / 2), and the road's per-station turn is NOT bounded by
	`road_turn_rate_deg` — the recurrence also restores the heading toward +X by
	ROAD_RESTORE, so a station leaving the heading cap can turn further than the
	noise alone allows (measured: a 22.4 degree joint wanting 1.585 m against a
	fixed 1.5). A shipped fixed stretch is one retune of the turn rate away from
	being wrong again, so this is the arithmetic and not a number.

	The margin is EDGE_EPS's cousin: a hair over the exact depth, because the two
	rectangles meet the wedge along its own edges and floating point decides which
	side of them a sample lands on.
	"""
	var dot := clampf(dir_a.dot(dir_b), -1.0, 1.0)
	var turn := acos(dot)
	if turn <= 0.0:
		return 0.0
	return half * tan(turn * 0.5) + FIELD_BRIDGE_SLAB_MARGIN


func _field_bridge_slabs(row: Dictionary) -> Array:
	"""
	THE SLABS OF ONE BRIDGE — the single description of what the stone is, read
	by the builder that emits it AND by the surface query that answers where you
	can stand.

	@param row: A field_bridge_at() row.
	@return: One entry per slab, in order:
	           "start" / "dir" / "len"   the slab's axis in world XZ (its own
	                                     length, the stretch included)
	           "y_a" / "y_b"             the walking height at each end
	           "half"                    half its width

	ONE TABLE, TWO READERS, and it exists because the two disagreed. The query
	used to be a point-to-POLYLINE distance, which describes a CAPSULE: at a
	joint on the outside of a turn, a point can be within half a deck of the line
	and outside every rectangle the builder actually emitted. `spawn_coins_in_chunk`
	then stood a coin at deck height over open air (seed 26, station 34). A
	rectangle is what is built, so a rectangle is what is asked.

	The heights are the INDEX, not a re-derivation from the profile: the polyline
	is (west ramp foot, every deck station, east ramp foot) by construction, so
	the two end points are at 0 and everything between them is at deck height —
	which also lets the two ramps have DIFFERENT runs (see _field_bridge_foot)
	with no second profile to keep in step.
	"""
	if row.has("slabs"):
		return row["slabs"]   # the row is memoized, so this is once per bridge
	var poly: PackedVector2Array = row["poly"]
	var half: float = row["half"]
	var last := poly.size() - 2   # index of the LAST segment
	var out: Array = []
	for i in range(poly.size() - 1):
		var y_a := 0.0 if i == 0 else FIELD_BRIDGE_TOP
		var y_b := 0.0 if i == last else FIELD_BRIDGE_TOP
		var a: Vector2 = poly[i]
		var seg: Vector2 = poly[i + 1] - a
		# The slab stretch, at deck-to-deck joints ONLY — BOTH ends of it have to
		# be deck. A slab overhanging the head of a ramp is a step you cannot walk
		# back up (see _field_bridge_joint_ext), and stretching the RAMP itself
		# is worse: its top surface is a plane through its two ends, so a longer
		# box at the same heights lifts the whole surface off the profile.
		var deck := i >= 1 and i <= last - 1
		var dir := seg.normalized()
		var ext_a := 0.0
		var ext_b := 0.0
		if deck and i >= 2:
			ext_a = _field_bridge_joint_ext(
					(poly[i] - poly[i - 1]).normalized(), dir, half)
		if deck and i <= last - 2:
			ext_b = _field_bridge_joint_ext(
					dir, (poly[i + 2] - poly[i + 1]).normalized(), half)
		out.append({
			"start": a - dir * ext_a, "dir": dir,
			"len": seg.length() + ext_a + ext_b,
			"y_a": y_a, "y_b": y_b, "half": half,
		})
	row["slabs"] = out
	return out


func _field_bridge_rail_line(poly: PackedVector2Array, offset: float) -> PackedVector2Array:
	"""
	The walking line offset sideways by `offset` metres, MITRED at every joint —
	the line a parapet's boxes are centred on.

	@param offset: SIGNED lateral offset. The normal is (dir.y, -dir.x), which is
	               the box's own local +X (see spawn_field_bridges_in_chunk).
	@return: One point per point of `poly`, so segment `i` of the result is the
	         rail beside slab `i`.

	A MITRE, NOT ONE OFFSET RECTANGLE PER SLAB, and the difference is the lane.
	A rectangle offset from its own segment stops at the joint's projection, and
	on the INSIDE of a turn that corner lands `offset * cos(turn)` from the NEXT
	segment's line — 7.63 m from a line whose deck reaches 8.0 at the road's
	measured 22.4 degree worst joint, i.e. a rail poking a third of a metre into
	the lane the deck promises (field_bridge_selfcheck check 11 catches exactly
	that). The mitre point lies on BOTH offset lines by construction, so no part
	of the rail is ever nearer the walking line than `offset` — and the OUTER
	corner closes with no wedge for free, which is why the parapet needs no slab
	stretch of its own (_field_bridge_joint_ext stays the deck's).
	"""
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var d_in: Vector2 = (poly[i] - poly[i - 1]).normalized() if i > 0 \
				else (poly[1] - poly[0]).normalized()
		var d_out: Vector2 = (poly[i + 1] - poly[i]).normalized() if i < n - 1 \
				else d_in
		var bis := (Vector2(d_in.y, -d_in.x) + Vector2(d_out.y, -d_out.x)).normalized()
		# Scale the bisector so its projection on either normal is exactly
		# `offset`. Floored because a hairpin sends the mitre to infinity, and
		# the floor is NOT a graceful cap: under it the rail lands at
		# 2 * offset * proj, i.e. INSIDE the lane, which is the very thing this
		# function exists to prevent. It is unreachable on this road — proj is
		# cos(turn / 2) and needs a 120 degree joint against a measured worst of
		# 22.41 (minimum proj over 45 bridges: 0.9809) — so it is a guard against
		# a division, not a supported case. Widen the turn cap and this needs a
		# real answer.
		var proj := maxf(bis.dot(Vector2(d_out.y, -d_out.x)), 0.5)
		out.append(poly[i] + bis * (offset / proj))
	return out


func field_bridge_at(k0: int) -> Dictionary:
	"""
	THE BRIDGE ANCHORED AT STATION `k0`, or {} when there is none.

	@param k0: Station index. A bridge exists here only when `k0` is a CROSSING
	           ENTRY — wet at `k0`, dry at `k0 - 1` — which is what makes "one
	           bridge per crossing" a definition rather than a de-duplication
	           pass over overlapping candidates.
	@return: {} or a row:
	           "k0" / "k1"   first and last wet station
	           "poly"        the walking line as world XZ points: the west ramp
	                         foot, every deck station, the east ramp foot
	           "along"       cumulative distance along `poly`, same length
	           "half"        half the deck width
	           "run"         the ramp run, so a reader need not re-derive it

	MEMOIZED, because every chunk within a bridge's reach re-asks this and the
	answer is a pure function of (k0, run_seed) through the road cache and the
	river field. `_drop_seeded_memos()` clears it beside the station cache it is
	derived from.

	THE CAP IS A LAKE, NOT A LONGER BRIDGE. Past FIELD_BRIDGE_MAX_SPAN of wet
	centreline the road is not crossing a river, it is running into standing
	water, and a 200 m slab there would be a landmark nobody authored. It wades —
	and the rivers epic's not-walkable bead owes that case an answer of its own.
	"""
	if _field_bridge_cache.has(k0):
		return _field_bridge_cache[k0]

	var empty: Dictionary = {}
	var terminal := _road_terminal_k()
	# CAP 5 — the road's consumers stop at the terminal station (bead
	# godot-test1-8gw.3). East of T the route is the city's authored approach
	# corridor and then Budapest itself, whose four bridges are authored over an
	# authored Danube; a seeded field deck in there would be a fifth bridge across
	# the Danube that no plan, no landmark slot and no map knows about.
	if k0 > terminal:
		_field_bridge_cache[k0] = empty
		return empty
	# NOT MEMOIZED, and that distinction is the whole determinism of this table.
	# "The station cache does not reach far enough to answer yet" is a fact about
	# THIS MOMENT, not about the world: remember it and the first chunk to ask
	# early would delete a bridge for the rest of the run, and which chunk asks
	# first is the order the player walked in. Every answer below IS about the
	# world (the road's centreline and the river field, both pure in the seed),
	# so every answer below is remembered.
	if k0 - FIELD_BRIDGE_DRY_STATIONS - 1 < road_k_min:
		return empty
	# The crossing ENTRY test. Dry behind, wet here.
	if _field_bridge_wet(k0 - 1) or not _field_bridge_wet(k0):
		_field_bridge_cache[k0] = empty
		return empty

	# Walk forward to the far bank, ACCUMULATING THE METRES WALKED — never the
	# chord back to the first wet station, which a curved wet run makes shorter
	# than the road really is (measured on seed 72: 84 m walked reading as a
	# 79.2 m chord, so a crossing over the cap was bridged anyway). The cap is
	# metres of water, and a station budget would be one `road_coin_spacing`
	# retune away from meaning something else.
	var k1 := k0
	# THE ENTRY STATION'S OWN WATER COUNTS. `walked` used to start at zero and add
	# only the distances between subsequent wet station CENTRES, which drops the
	# entry's share and both partial intervals at the banks — seed 296's 124.5 m
	# crossing totalled 119.99996 and was bridged as if it were inside the 120 m
	# cap. Every station contributes the wet METRES of the stretch it owns, and
	# consecutive stations tile the centreline, so the sum is the crossing.
	var walked := _field_bridge_wet_metres(k0)
	while true:
		var next := k1 + 1
		if next + FIELD_BRIDGE_DRY_STATIONS > terminal:
			# The far bank is past the road's last station: no bridge, and that
			# IS about the world, so it is remembered.
			_field_bridge_cache[k0] = empty
			return empty
		if next + FIELD_BRIDGE_DRY_STATIONS > road_k_max:
			# ...whereas a cache that has not grown that far yet is a fact about
			# this moment — see the un-memoized return above.
			return empty
		if not _field_bridge_wet(next):
			break
		walked += _field_bridge_wet_metres(next)
		if walked > FIELD_BRIDGE_MAX_SPAN:
			_field_bridge_cache[k0] = empty   # a lake, see above
			return empty
		k1 = next

	# The deck's stations: every wet one plus FIELD_BRIDGE_DRY_STATIONS of dry
	# ground at each end, so both abutments stand on land with a whole station of
	# margin rather than on the noise field's exact zero crossing...
	var west_k := k0 - FIELD_BRIDGE_DRY_STATIONS
	var east_k := k1 + FIELD_BRIDGE_DRY_STATIONS
	# ...and then further out, at DECK HEIGHT, until the SECTION at each end is
	# dry across its width. THE DECK GROWS, THE RAMP DOES NOT: a river that runs
	# alongside the road for a while (seed 777001 grazes one within 8 m for 150 m)
	# leaves no dry 16 m section for an abutment anywhere near the crossing, and
	# pushing the FOOT out there only drags a ramp — which is under
	# WADE_SURFACE_MAX for its first 2.4 m — along the water. Carrying on at 1.6 m
	# and coming down where the bank is dry is the same stone in the right order.
	# Bounded by FIELD_BRIDGE_MAX_SPAN at each end — the same ceiling the water
	# itself gets, because this growth is the deck following a river bank and a
	# bank is exactly as long as the crossing next to it.
	#
	# THE CACHE IS EXTENDED FIRST, AND THE LOOPS DO NOT READ ITS EDGE. This
	# answer is memoized for the run, so a loop that stopped at whatever the
	# station cache happened to hold would make the BRIDGE SET a function of the
	# order the player walked the chunks in — measured: seed 409 built six
	# bridges ascending and five descending, and in a room two peers would lay
	# different decks over the same water. The k1 walk above returns UN-memoized
	# when the cache is short for exactly this reason; the growth cannot, because
	# it may legitimately want stations 260 m out, so it makes sure they exist.
	var reach_x := FIELD_BRIDGE_BANK_WALK_MAX + FIELD_BRIDGE_FOOT_PUSH_MAX \
			+ 2.0 * _field_bridge_run()
	_road_extend_to_x(_road_station(west_k).center.x - reach_x,
			_road_station(east_k).center.x + reach_x)
	var grown := 0.0
	while grown < FIELD_BRIDGE_BANK_WALK_MAX and not _field_bridge_ramp_dry(
			_road_station(west_k).center,
			_road_station(west_k).center + _field_bridge_out_dir(west_k, -1)
					* _field_bridge_run()):
		grown += _road_station(west_k).center.distance_to(
				_road_station(west_k - 1).center)
		west_k -= 1
	grown = 0.0
	while east_k + 1 < terminal and grown < FIELD_BRIDGE_BANK_WALK_MAX \
			and not _field_bridge_ramp_dry(
					_road_station(east_k).center,
					_road_station(east_k).center
							+ _field_bridge_out_dir(east_k, 1) * _field_bridge_run()):
		grown += _road_station(east_k).center.distance_to(
				_road_station(east_k + 1).center)
		east_k += 1
	var pts := PackedVector2Array()
	for k in range(west_k, east_k + 1):
		pts.append(_road_station(k).center)

	# ONE ANCHOR OWNS A DECK. Two crossings on the same bank both grow outward to
	# the same dry ground and produce the SAME row under two anchors — and then
	# every chunk emits every slab twice: double the boxes, double the collision
	# shapes, and a full-length z-fight (7 of 78 seeds, one of them three times
	# over). The WESTERN entry wins, so the rule is: if an earlier entry's deck
	# already covers this crossing, this anchor has nothing to build.
	#
	# It terminates because it only ever looks WEST, and it is cheap because
	# field_bridge_at is memoized — the neighbour it asks was built by the same
	# window scan a moment ago.
	var look := west_k
	while look < k0:
		var earlier: Dictionary = field_bridge_at(look)
		look += 1
		if earlier.is_empty():
			continue
		if _field_bridge_surface_on(earlier,
				Vector3(_road_station(k0).center.x, 0.0,
						_road_station(k0).center.y)) > -INF:
			_field_bridge_cache[k0] = empty
			return empty

	var row := _field_bridge_row_from(pts)
	if not row.is_empty():
		row["k0"] = k0
		row["k1"] = k1
	_field_bridge_cache[k0] = row
	return row


func _field_bridge_row_from(pts: PackedVector2Array) -> Dictionary:
	"""
	One bridge's geometry from the centreline points its deck stands on.

	@param pts: The deck's own centre points, west to east, the DRY margin point
	            at each end included. At least three.
	@return: The row (see field_bridge_at), or {} when either abutment cannot be
	         put on dry ground — which refuses the whole crossing.

	SHARED BY THE TWO SOURCES OF A CENTRELINE: the seeded road's stations, and the
	AUTHORED approach corridor from the terminal station to Budapest's gate. The
	corridor is not station-indexed and has no `k`, but it is the same walk over
	the same water, and a second copy of the feet-and-profile arithmetic is how
	the two would drift apart.

	The two ramp feet are measured back along the FIRST and forward along the LAST
	deck segment's own direction — colinear rather than tangent-derived, so the
	ramp and the slab it meets share a heading and there is no wedge of open air
	at that joint (which is the one joint the slab stretch is forbidden to cover;
	see _field_bridge_joint_ext).
	"""
	if pts.size() < 3:
		return {}
	var head := (pts[1] - pts[0]).normalized()
	var tail := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var west := _field_bridge_foot(pts[0], -head)
	var east := _field_bridge_foot(pts[pts.size() - 1], tail)
	if west == Vector2.INF or east == Vector2.INF:
		return {}   # no dry bank for an abutment — see _field_bridge_foot

	var poly := PackedVector2Array()
	poly.append(west)
	poly.append_array(pts)
	poly.append(east)

	var along := PackedFloat32Array()
	along.append(0.0)
	for i in range(1, poly.size()):
		along.append(along[i - 1] + poly[i].distance_to(poly[i - 1]))

	return { "poly": poly, "along": along, "half": FIELD_BRIDGE_HALF_WIDTH }


func approach_bridges() -> Array:
	"""
	The bridges on the APPROACH CORRIDOR — the authored line from the road's
	terminal station `T` through Budapest's gate (bead godot-test1-06o.2, round 3).

	@return: Rows in the shape field_bridge_at() returns, west to east. Memoized
	         for the run beside the road's own bridges.

	WHY THE CORRIDOR NEEDS ITS OWN SCAN AND IS NOT AN OVERSIGHT TWICE. The road's
	crossings are found by walking STATIONS, and the road's consumers stop at `T`
	(cap 5) — but the player does not: from `T` the route is
	BudapestPlan.road_approach_point(), ~150 m of authored corridor that
	`spawn_approach_coins_in_chunk` lays a coin line along. That corridor has no
	stations, and the city's river override only starts at the rect's west edge
	(x = 1600), so the PROCEDURAL river is alive underneath it — and on seed 4 it
	crosses one at about x = 1495 with no bridge over it. That is the same softlock
	as any unbridged crossing, on the one stretch of the walk a player cannot go
	around.

	So the corridor is sampled at the road's own station pitch and walked with the
	same crossing rule, and the deck is built by the same
	_field_bridge_row_from() the stations use. It stops at the city rect: inside
	it, the Danube is authored and so are its four bridges.

	ZERO RNG, like the coin line it shadows: the corridor is a pure function of
	the terminal station, which is where the run's seed enters.
	"""
	if not _approach_bridge_cache.is_empty():
		return _approach_bridge_cache
	if _approach_bridge_scanned:
		return _approach_bridge_cache
	_approach_bridge_scanned = true

	var terminal: Vector2 = _road_station(_road_terminal_k()).center
	# East end: the coin line's own — the Danube's west bank. NOT clamped to the
	# city rect, and that is a fix rather than an oversight: a crossing can END on
	# the rect boundary (seed 606060 wades from x = 1589 to the edge at 1600), and
	# a scan that stops at 1600 finds no far bank and builds nothing. Inside the
	# rect `is_river_at` is the AUTHORED Danube and the corridor is the gate avenue
	# — dry — so the walk simply runs out of water there, and the Danube's own
	# crossings stay the four authored bridges: the coin line stops at its west
	# bank, so this scan never reaches midstream to call it a crossing.
	# A FEW METRES PAST THE RECT EDGE, NOT ALL THE WAY TO THE RIVER. Inside
	# Budapest `is_river_at` is the AUTHORED Danube and the corridor is the dry
	# gate avenue, so of the 880 samples this used to take, 730 asked a question
	# with a known answer — 36.7 ms on the first chunk build of a run, which lands
	# in the synchronous spawn ring. What round 3 actually needed past the
	# boundary was the DRY MARGIN of a crossing that ends ON it (seed 606060), and
	# that is one deck-width, not 730 m.
	# The east end is set so the RAMP FOOT — one run past the last deck point —
	# still lands inside that same bound, which is what keeps the corridor's stone
	# out of the gate district (authored from x = 1620) while leaving room for the
	# dry margin of a crossing that ends ON the rect edge.
	var east_x := minf(_approach_coin_east_end(),
			BudapestPlan.BUDAPEST_MIN.x + 2.0 * FIELD_BRIDGE_HALF_WIDTH
					- _field_bridge_run())
	if east_x <= ROAD_TERMINAL_X:
		return _approach_bridge_cache

	# SAMPLED AT THE PROBE STEP, NOT AT THE ROAD'S PITCH. A station is ~6 m of X
	# and a river band can be narrower than that, so a corridor walked station by
	# station steps straight over one and reports dry ground on both sides of
	# water it never asked about (run seed 63: the band at x = 1530-1532 fell
	# between two samples and the corridor got no bridge at all). Detection is
	# cheap and metre-fine; the DECK is decimated back to the road's pitch below,
	# so the stone is the same shape either way.
	var pts := PackedVector2Array()
	# FROM THE TERMINAL STATION, NOT FROM ROAD_TERMINAL_X. `T` is the last station
	# AT OR WEST of that X, so the two are up to a station apart — and the west
	# extension below stops at the terminal station, which left that gap
	# unsampled. On seed 115 the handoff water sits inside it, so the corridor
	# walked straight over the crossing it exists to find.
	# `road_approach_point` answers the terminal itself west of it, so starting
	# here is continuous with the extension and adds no kink.
	var x := minf(ROAD_TERMINAL_X, terminal.x)
	while x <= east_x:
		pts.append(BudapestPlan.road_approach_point(terminal, x))
		x += FIELD_BRIDGE_PROBE_STEP

	# ...and the WEST EXTENSION, which is THE HANDOFF AND HAS EXACTLY ONE OWNER.
	# The road-side builder refuses any crossing whose far bank lies past the last
	# station a road consumer may touch (`k1 + DRY > terminal`), so every crossing
	# still under way within a dry margin of `T` is the corridor's — and the
	# TRIGGER here has to be that same condition, not a probe of the corridor's
	# own first sample. `road_approach_point` answers the terminal itself for
	# every x west of it, so the corridor's line there is a POINT: on seed 203 it
	# reported dry across an axis the road never travels while the road's own
	# section was wet, and on seed 224 the crossing ended at `T - 1` with the
	# terminal dry, so neither side saw it at all.
	var terminal_k := _road_terminal_k()
	# THE WEST EXTENSION IS UNCONDITIONAL, and that is the handoff's whole
	# ownership rule. The road side refuses any crossing whose far bank or whose
	# grown deck runs past the last station a road consumer may touch, and west of
	# `T` the corridor is a POINT whose perpendicular is not the road's — so every
	# TRIGGER tried here (the corridor's own first sample, then the road's wet
	# stations near T) missed one shape of the same case. Starting the corridor's
	# line on dry ROAD, always, means the scan below simply sees the crossing;
	# anything the road side really did deck is skipped by the ownership test in
	# the loop, so nothing is built twice.
	if true:
		# Walk back to the last DRY station, then lay the road's own centreline
		# out at the SAME pitch as the corridor's samples — mixing 6 m stations
		# with 1 m samples makes the decimation below skip 36 m of the western
		# half and turn the last deck segment into a chord.
		_road_extend_to_x(_road_station(terminal_k).center.x
				- FIELD_BRIDGE_BANK_WALK_MAX - FIELD_BRIDGE_MAX_SPAN,
				ROAD_TERMINAL_X)
		var k := terminal_k
		var walked_west := 0.0
		while walked_west <= FIELD_BRIDGE_BANK_WALK_MAX:
			k -= 1
			walked_west += _road_station(k).center.distance_to(
					_road_station(k + 1).center)
			# Far enough back that a RAMP fits on dry ground — the same rule the
			# road's own growth stops on, so the corridor's deck can end here.
			if _field_bridge_ramp_dry(_road_station(k).center,
					_road_station(k).center + _field_bridge_out_dir(k, -1)
							* _field_bridge_run()):
				break
		var west := PackedVector2Array()
		for j in range(k, terminal_k):
			var from: Vector2 = _road_station(j).center
			var to: Vector2 = _road_station(j + 1).center
			var steps := maxi(1, int(from.distance_to(to) / FIELD_BRIDGE_PROBE_STEP))
			for i in range(steps):
				west.append(from.lerp(to, float(i) / float(steps)))
		west.append_array(pts)
		pts = west

	var i := 0
	while i < pts.size() - 1:
		if _approach_wet(pts, i) or not _approach_wet(pts, i + 1):
			i += 1
			continue
		# i is the last DRY sample before the water: walk to the far bank,
		# accumulating metres walked (never the chord — see field_bridge_at).
		var j := i + 1
		var walked := 0.0
		var lake := false
		while j < pts.size() - 1 and _approach_wet(pts, j):
			walked += pts[j].distance_to(pts[j - 1])
			if walked > FIELD_BRIDGE_MAX_SPAN:
				lake = true
				break
			j += 1
		if lake or j >= pts.size() - 1:
			i = j + 1
			continue
		# ...and the same growth outward until the SECTION at each end is dry
		# across its width (see field_bridge_at): the deck carries on at 1.6 m
		# rather than dragging a ramp along the water.
		# ...growing on the RAMP RECTANGLE, exactly as the road's does: the foot
		# this deck will ask for demands the whole rectangle dry, so a growth that
		# stopped on a dry SECTION would hand it a bank it must refuse.
		# ...growing on the RAMP RECTANGLE, exactly as the road's does — and along
		# the direction the DECIMATED deck will hand its foot, not the 1 m local
		# one. The two differ wherever the corridor bends, and a growth that
		# cleared a ramp nobody builds hands the row a bank it must refuse.
		var stride: int = maxi(1, roundi(_road_spacing() / FIELD_BRIDGE_PROBE_STEP))
		var run := _field_bridge_run()
		var grown := 0.0
		while i > 0 and grown < FIELD_BRIDGE_BANK_WALK_MAX and not \
				_field_bridge_ramp_dry(pts[i], pts[i] - (pts[
						mini(i + stride, pts.size() - 1)] - pts[i]).normalized() * run):
			grown += pts[i].distance_to(pts[i - 1])
			i -= 1
		grown = 0.0
		while j < pts.size() - 2 and grown < FIELD_BRIDGE_BANK_WALK_MAX and not \
				_field_bridge_ramp_dry(pts[j], pts[j] + (pts[j] - pts[
						maxi(j - stride, 0)]).normalized() * run):
			grown += pts[j].distance_to(pts[j + 1])
			j += 1

		# THE DECK IS DECIMATED BACK TO THE ROAD'S PITCH (`stride`, above):
		# detection wants metres, but a slab per metre is a hundred boxes and a
		# hundred collision shapes for one crossing. Both ends are kept whatever
		# the stride lands on, so the deck still starts and finishes on the dry
		# samples the walk found.
		var deck := PackedVector2Array()
		var m := i
		while m < j:
			deck.append(pts[m])
			m += stride
		deck.append(pts[j])
		if deck.size() < 3:
			# A crossing narrower than one stride decimates to its two ends, and
			# a deck needs a middle: the row is (dry margin, deck..., dry margin),
			# so two points describe no deck at all. This is exactly the narrow
			# band the fine sampling exists to catch (seed 63's is 5 m wide), so
			# it is the common case here rather than a corner of one.
			deck = PackedVector2Array([pts[i], pts[(i + j) / 2], pts[j]])
		# ...and the ROAD may already have decked this water from its own side of
		# the handoff (its east growth can run to T). One deck, one owner.
		var mid: Vector2 = pts[(i + j) / 2]
		if _field_bridge_decked(mid, _road_bridges_near(mid.x, mid.x)):
			i = j + 1
			continue
		var row := _field_bridge_row_from(deck)
		if not row.is_empty():
			row["k0"] = -1   # the corridor has no station index
			row["k1"] = -1
			_approach_bridge_cache.append(row)
		i = j + 1
	return _approach_bridge_cache


func _approach_wet(pts: PackedVector2Array, i: int) -> bool:
	"""Is the corridor in the water at sample `i`? THE CENTRELINE, for
	_field_bridge_wet's reason — the samples are already a metre apart, so one
	point each is the whole stretch."""
	return is_river_at(Vector3(pts[i].x, 0.0, pts[i].y))


func field_bridges_near(x0: float, x1: float) -> Array:
	"""
	Every field bridge whose stone can reach the world-X window [x0, x1].

	@param x0, x1: The window, world metres. Widened by _field_bridge_reach()
	               before the scan, so a bridge anchored outside it whose deck
	               reaches in is still found.
	@return: Array of rows from field_bridge_at(), west to east.

	Same shape as every other road consumer: extend the station cache over the
	padded window, binary-search its start, walk forward until the centreline
	passes the end. The cache stays uncapped (see _road_terminal_k) — it is this
	CONSUMER that stops at T, inside field_bridge_at.
	"""
	var reach := _field_bridge_reach()
	# One extra station of cache each way so field_bridge_at can ask about
	# (k0 - 1) at the window's western edge and about the dry station past k1 at
	# its eastern one.
	_road_extend_to_x(x0 - reach - _road_spacing() * 2.0,
			x1 + reach + _road_spacing() * 2.0)
	var rows: Array = _road_bridges_near(x0, x1)
	# ...and the APPROACH CORRIDOR's own, which are not station-indexed and so are
	# not on the walk above. Cheap: the scan is memoized for the run and its rows
	# are rejected on X like any other.
	for row_v: Variant in approach_bridges():
		var row: Dictionary = row_v
		var poly: PackedVector2Array = row["poly"]
		if poly[poly.size() - 1].x < x0 - reach or poly[0].x > x1 + reach:
			continue
		rows.append(row)
	return rows


func _road_bridges_near(x0: float, x1: float) -> Array:
	"""
	The STATION-INDEXED half of field_bridges_near — every road bridge whose stone
	can reach the world-X window.

	Its own function because the corridor scan has to ask it: a crossing the road
	side already decks must not be decked a second time from the other side of the
	handoff (see approach_bridges). Splitting it is also what keeps that question
	free of recursion — the corridor asks about ROAD rows, and road rows never ask
	about the corridor.
	"""
	var reach := _field_bridge_reach()
	_road_extend_to_x(x0 - reach - _road_spacing() * 2.0,
			x1 + reach + _road_spacing() * 2.0)
	var rows: Array = []
	var k := _road_first_k_at_or_after_x(x0 - reach)
	while k <= road_k_max:
		var cur_k := k
		k += 1
		if _road_station(cur_k).center.x > x1 + reach:
			break
		var row: Dictionary = field_bridge_at(cur_k)
		if not row.is_empty():
			rows.append(row)
	return rows


func _field_bridge_decked(at: Vector2, rows: Array) -> bool:
	"""Is this world XZ already on one of these decks?"""
	for row_v: Variant in rows:
		if _field_bridge_surface_on(row_v, Vector3(at.x, 0.0, at.y)) > -INF:
			return true
	return false


func field_bridge_surface_y(world_pos: Vector3) -> float:
	"""
	The height of the field-bridge walking surface over this XZ, or -INF when
	there is no bridge here.

	@param world_pos: World position; only X and Z are read.
	@return: The surface Y (FIELD_BRIDGE_TOP across the deck, sloping linearly
	         down each ramp to 0 at its foot), or -INF off the bridge.

	BudapestPlan.bridge_surface_y's field cousin, one dimension curvier: the city
	measures from the ends of an axis-aligned rect, and here the walking line is a
	polyline the road bent, so the parameter is distance ALONG it. Same profile,
	same flush-at-both-ends guarantee.

	It is what stands a road coin on a deck (spawn_coins_in_chunk) and what
	field_bridge_selfcheck measures the built stone against, so the surface the
	coins ride and the surface the boxes draw cannot drift apart.
	"""
	for row_v: Variant in field_bridges_near(world_pos.x, world_pos.x):
		var y := _field_bridge_surface_on(row_v, world_pos)
		if y > -INF:
			return y
	return -INF


func field_bridge_stand_y(world_x: float, world_z: float, ground_y: float) -> float:
	"""
	The height a BODY spawns at over this world XZ: its usual ground height, or
	that height above the deck when a field bridge is here.

	@param ground_y: The spawner's own drop height (0.6 for a boss, the
	                 crocodile's settle height, and so on) — kept, not replaced,
	                 so the gravity settle each spawner relies on is unchanged.

	A BODY IS DROPPED AT A GROUND HEIGHT AND SETTLED BY GRAVITY, so one placed at
	0.6 under a deck whose walking surface is 1.6 m up can neither fall onto it
	nor climb out: it clips through the stone or wanders about underneath (seed
	19's third road boss stood in exactly that, and all eight of its candidate
	spots were on the deck).

	A LIFT, NOT A REFUSAL, and the difference is a population. Rejecting the spot
	is the tidier-looking rule and it is what this shipped for one round — but a
	boss on a RIVER station is the one path that dispatches the crocodile, its
	spots are inside the 16 m deck almost by construction, and refusing them
	deleted every river boss in the world (`enemy_spawn_selfcheck` check 11's
	non-vacuity assertion caught it). Standing the animal ON the bridge keeps the
	encounter the road promised.

	Deliberately NOT an `obstacles` footprint: that list is the coin perch rule's
	too, and a footprint here would make `_settle_coin_y` skip the very coins the
	deck is supposed to carry. It costs no RNG draw either, so it can move no
	spawn.
	"""
	var surface := field_bridge_surface_y(Vector3(world_x, 0.0, world_z))
	return ground_y if surface <= -INF else ground_y + surface


func _field_bridge_surface_on(row: Dictionary, world_pos: Vector3) -> float:
	"""
	field_bridge_surface_y for ONE bridge row (the split exists so the coin
	spawner and the self-check can hold a row they already looked up).

	@return: The surface Y, or -INF when the point is off this bridge's deck.

	Point-to-polyline, the standard projection BudapestPlan.segment_distance
	makes for the Danube, kept here because this one also needs the PARAMETER
	(how far along) and not just the distance.
	"""
	var p := Vector2(world_pos.x, world_pos.z)
	for slab_v: Variant in _field_bridge_slabs(row):
		var slab: Dictionary = slab_v
		var d: Vector2 = p - Vector2(slab["start"])
		var dir: Vector2 = slab["dir"]
		# The slab's own frame: how far along it, and how far off its axis.
		var along: float = d.dot(dir)
		var length: float = slab["len"]
		# A millimetre of tolerance on every face, because the ends and the
		# parapets are exactly where a caller asks: the ramp foot projects to
		# `along` = 0 and a dot product of two normalised vectors lands either
		# side of it, which would answer "no bridge" on the first sample of a
		# metre-by-metre walk of its own deck.
		if along < -EDGE_EPS or along > length + EDGE_EPS:
			continue
		if absf(d.dot(Vector2(-dir.y, dir.x))) > float(slab["half"]) + EDGE_EPS:
			continue
		# The top surface is the plane through the slab's two ends, so the height
		# is one lerp — and a ramp and a deck slab are the same arithmetic.
		return lerpf(float(slab["y_a"]), float(slab["y_b"]),
				clampf(along / length, 0.0, 1.0))
	return -INF


func spawn_field_bridges_in_chunk(chunk_pos: Vector2i, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Build this chunk's share of every field bridge that reaches into it.

	@param chunk_pos: Chunk coordinates being built.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	SLICED BY THE CENTRE RULE, not by rect intersection, and that is the city's
	own decision read the other way round. A field deck is a chain of ROTATED
	slabs (the road curves; an axis-aligned deck would have to be widened by the
	lateral drift, which at the road's 78 deg heading cap is a 190 m slab for a
	40 m crossing), and CLAUDE.md's rule is that a rotated box cannot be cut into
	boxes and keeps the centre rule. That is safe here for the reason it is not
	safe for the Parliament: every piece is at most a couple of stations long and
	one deck wide, i.e. far smaller than a chunk, so the chunk that owns a piece
	is always within half a chunk of all of it. field_bridge_selfcheck check 2
	asserts that size bound, the budapest_selfcheck check 5 idiom.

	ORDERING: with the city's builders, after everything that fills `obstacles`
	and before _build_block_multimesh — a deck is one draw call's worth of the
	chunk's batch like any cactus. It appends NO footprint (see the const block).

	THE TRIM RIDES THE SAME LOOP (bead godot-test1-06o.4): a parapet per slab
	edge and a pylon pair at each bank, cantilevered OUTBOARD of the deck so the
	walkable lane, the surface query and every wet probe are untouched and only
	boxes were added — see the trim const block for the whole argument. Each
	piece takes the centre rule for ITSELF, because its midpoint is not its
	slab's.

	NO RNG DRAW from anybody's stream: its own private generator at a fixed seed,
	whose colour picks are overridden anyway.
	"""
	if not spawn_field_bridges:
		return
	var centre := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0
	var rows := field_bridges_near(centre.x - half_chunk, centre.x + half_chunk)
	if rows.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = FIELD_BRIDGE_STREAM_SEED
	for row_v: Variant in rows:
		var row: Dictionary = row_v
		var poly: PackedVector2Array = row["poly"]
		# The two parapet lines, mitred, one per deck edge — segment `i` of each
		# belongs to slab `i`. Once per row per CHUNK, not once per slab: it is
		# pure in the row (so it is cached nowhere and can leak across no
		# re-seed) and it is a couple of dozen normalises against a window scan
		# this feature already budgets in milliseconds.
		var rail_off: float = float(row["half"]) + FIELD_BRIDGE_PARAPET_WIDTH * 0.5
		var rails: Array[PackedVector2Array] = [
			_field_bridge_rail_line(poly, rail_off),
			_field_bridge_rail_line(poly, -rail_off),
		]
		var slabs := _field_bridge_slabs(row)
		for i in slabs.size():
			var slab: Dictionary = slabs[i]
			var dir: Vector2 = slab["dir"]
			var run_h: float = slab["len"]
			var y_a: float = slab["y_a"]
			var y_b: float = slab["y_b"]
			var half: float = slab["half"]
			var mid: Vector2 = Vector2(slab["start"]) + dir * run_h * 0.5
			var rise := y_b - y_a
			var length := sqrt(run_h * run_h + rise * rise)
			# create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), so a box
			# long in LOCAL Z is tipped by `tilt` and swung to its heading by
			# `yaw` — the derivation _city_ramp_slice spells out. Local +Z lands
			# on (cos(tilt) * sin(yaw), -sin(tilt), cos(tilt) * cos(yaw)), so
			# yaw = atan2(dir.x, dir.y) points it along this segment and
			# tilt = -atan2(rise, run) tips it up that segment's climb.
			var yaw := atan2(dir.x, dir.y)
			var tilt := -atan2(rise, run_h)
			var surface := (y_a + y_b) * 0.5
			if world_to_chunk(Vector3(mid.x, 0.0, mid.y)) == chunk_pos:
				create_box(
						Vector3(mid.x - centre.x,
								surface - FIELD_BRIDGE_THICKNESS * 0.5,
								mid.y - centre.z),
						Vector3(half * 2.0, FIELD_BRIDGE_THICKNESS, length),
						yaw, rng, block_batch, block_body, tilt,
						FIELD_BRIDGE_STONE)

			# THE PARAPETS — one per edge of this slab, ramps included, because a
			# rail that stops where the deck does is a rail you walk off the side
			# of the approach. A rail segment is parallel to its slab (offset
			# lines are), so it takes the slab's own `yaw`; only its LENGTH moves,
			# which is what a mitre does at a turn.
			#
			# EACH ONE TAKES THE CENTRE RULE FOR ITSELF: a parapet's midpoint is
			# 8.25 m off its slab's, so the chunk that owns the slab is routinely
			# not the chunk that owns the wall — the rule slices a BOX.
			for rail_v: Variant in rails:
				var rail: PackedVector2Array = rail_v
				var r_mid: Vector2 = (rail[i] + rail[i + 1]) * 0.5
				var r_run: float = rail[i].distance_to(rail[i + 1])
				if r_run <= EDGE_EPS:
					continue
				if world_to_chunk(Vector3(r_mid.x, 0.0, r_mid.y)) != chunk_pos:
					continue
				create_box(
						Vector3(r_mid.x - centre.x,
								surface + (FIELD_BRIDGE_PARAPET_HEIGHT
										- FIELD_BRIDGE_THICKNESS) * 0.5,
								r_mid.y - centre.z),
						Vector3(FIELD_BRIDGE_PARAPET_WIDTH,
								FIELD_BRIDGE_PARAPET_HEIGHT + FIELD_BRIDGE_THICKNESS,
								sqrt(r_run * r_run + rise * rise)),
						yaw, rng, block_batch, block_body,
						-atan2(rise, r_run), FIELD_BRIDGE_PARAPET_STONE)

		# THE PYLON PAIR AT EACH BANK. The deck's two ends are poly[1] and
		# poly[-2] by construction (_field_bridge_row_from appends a ramp foot
		# outside each of them), and the slab meeting each is COLINEAR with the
		# deck segment beyond it — so the heading is that segment's and there is
		# no fourth description of the bridge's shape to keep in step.
		var last := poly.size() - 1
		for bank in [
			{ "at": poly[1], "dir": (poly[2] - poly[1]).normalized() },
			{ "at": poly[last - 1], "dir": (poly[last - 1] - poly[last - 2]).normalized() },
		]:
			var b_dir: Vector2 = bank["dir"]
			var b_perp := Vector2(b_dir.y, -b_dir.x)
			var b_top := FIELD_BRIDGE_TOP + FIELD_BRIDGE_PYLON_RISE
			for side in [-1.0, 1.0]:
				# OUTBOARD OF THE PARAPET'S CENTRE LINE by half a pylon, so the
				# two solids interpenetrate rather than share a face — see the
				# const block for why flush is z-fighting and not tidiness.
				var at: Vector2 = Vector2(bank["at"]) + b_perp * (side
						* (float(row["half"]) + FIELD_BRIDGE_PARAPET_WIDTH * 0.5
								+ FIELD_BRIDGE_PYLON_WIDTH * 0.5))
				if world_to_chunk(Vector3(at.x, 0.0, at.y)) != chunk_pos:
					continue
				create_box(
						Vector3(at.x - centre.x, b_top * 0.5, at.y - centre.z),
						Vector3(FIELD_BRIDGE_PYLON_WIDTH, b_top,
								FIELD_BRIDGE_PYLON_DEPTH),
						atan2(b_dir.x, b_dir.y), rng, block_batch, block_body,
						0.0, FIELD_BRIDGE_PYLON_STONE, false)


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
	# THIS CHUNK'S FIELD BRIDGES, looked up ONCE for the whole coin scan rather
	# than per coin (bead godot-test1-06o.2). A coin that lands on a deck rides
	# the deck; every other coin takes the ground rule below, untouched.
	var bridges: Array = field_bridges_near(x0 - pad, x1 + pad) if spawn_field_bridges else []

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
				var deck_y := _field_bridge_surface_on(row_v, cw_pos)
				if deck_y > -INF:
					local.y = deck_y + COIN_GROUND_HEIGHT
					break

			# Spawn the coin (position is local to the chunk, like blocks/crocodiles).
			# A gem entry is upgraded BEFORE entering the tree (make_gem recolours a
			# duplicated material and scales the whole pickup — see coin.gd).
			var coin := coin_scene.instantiate()
			coin.position = local
			if cw.gem:
				coin.make_gem()
			parent_chunk.add_child(coin)

# ============================================================================
# SECTION — BUDAPEST, STREAMED THROUGH ORDINARY CHUNKS
# ============================================================================
#
# The city is AUTHORED (scripts/budapest_plan.gd) and STREAMED (here). Those two
# words are the whole design: every coordinate is a constant a designer typed,
# and every box those constants describe is emitted by the same create_chunk pass
# that emits a cactus — chunk-parented, into the chunk's ONE MultiMesh batch and
# ONE collision body, freed when the chunk unloads.
#
# THAT IS WHY THE CITY IS NOT A SECOND TOWER. The HQ is manager-parented and
# CLAUDE.md says it is the ONE exception and must stay one; a 2.2 km city held
# outside the chunk dictionary would be an exception 4,000 times its size, and
# the 49-chunk web residency ceiling is exactly what chunk streaming buys. So a
# thing 800 m long is not built by one chunk — it is SLICED, and every chunk
# builds the part of it that stands in its own square.
#
# NOTHING HERE DRAWS FROM THE SHARED CHUNK STREAM. create_box spends four random
# numbers per box on its colour ramp, and one extra draw taken from the chunk's
# RNG moves every block, crocodile and coin downstream of it. The streamer
# carries its own RandomNumberGenerator at a fixed seed (CITY_STREAM_SEED) whose
# draws are discarded padding, because every box passes a colour override.


func city_chunk(chunk_center: Vector3) -> bool:
	"""
	Does this chunk's SQUARE meet Budapest — i.e. is it a chunk that can build
	city stone?

	@param chunk_center: This chunk's centre, from chunk_to_world().

	ONE PREDICATE, TWO READERS, AND THAT IS THE WHOLE REASON IT EXISTS.
	spawn_city_in_chunk's cheap reject asks it to decide whether to build, and
	create_chunk asks it to decide whether the chunk's batch casts a shadow. Those
	two answers MUST be the same answer: the owner's no-shadow ruling is about the
	city, so a chunk that builds a slice of Budapest must not cast, and a chunk
	that builds none of it must.

	IT IS THE SQUARE, NOT THE CENTRE, and that distinction is a real bug that was
	shipped once. A chunk on the rect's edge can straddle the boundary — its
	square meets the city and it builds a sliced facade, while its CENTRE sits
	outside. Asked about its centre it kept its shadows and cast them off city
	stone; the mirror case (centre inside, a sliver of ordinary world outside)
	silently stripped shadows from that sliver's cactus. Both are one ring of
	chunks all the way round a 2.2 km rect. budapest_selfcheck check 4 now asserts
	the two readers agree, and names the edge chunks it found.
	"""
	return _city_chunk_slice(chunk_center, BudapestPlan.rect()).has_area()


func _city_chunk_slice(chunk_center: Vector3, area: Rect2) -> Rect2:
	"""
	This chunk's share of an authored city rect, in WORLD XZ.

	@param chunk_center: This chunk's centre, from chunk_to_world().
	@param area: The authored rect (a plateau, a ramp, the avenue), world XZ.
	@return: The intersection, or a zero-area Rect2 when the two do not meet —
	         test it with has_area() before building anything from it.

	ONE HELPER FOR EVERY SLICED RECT, and that is the point rather than a
	convenience. "Neighbouring chunks' slices meet flush" is the claim a plateau
	and a ramp both rest on, and routing both through the same intersection makes
	it true BY CONSTRUCTION instead of by review: adjacent chunk squares share an
	edge exactly, so their intersections with one rect share that edge exactly and
	the two boxes touch with no gap and no overlap.

	A slice that is exactly a line (a rect whose edge lies on a chunk seam) has no
	area, so has_area() drops it — the degenerate box is never built, and the
	chunk on the other side of the seam owns the whole thing.
	"""
	var half := chunk_size / 2.0
	var square := Rect2(chunk_center.x - half, chunk_center.z - half, chunk_size, chunk_size)
	return square.intersection(area)


func _city_ramp_slice(chunk_center: Vector3, ramp: Rect2, rise: float, dir: float,
		thickness: float, rng: RandomNumberGenerator, block_batch: Array,
		block_body: StaticBody3D, stone: Color) -> void:
	"""
	This chunk's slice of ONE tilted ramp, on the X axis. The city has two kinds
	and they are the same slab: a plateau's climb onto its lid, and a bridge's
	approach onto its deck.

	@param chunk_center: This chunk's centre, from chunk_to_world().
	@param ramp: The ramp's footprint in world XZ — `size.x` is the RUN, `size.y`
	             the width.
	@param rise: How far it climbs, in metres. The foot is at y = 0.
	@param dir: +1 if it climbs eastward (foot on the west end), -1 if westward.
	@param thickness: The slab's own thickness.

	A TILTED BOX, NEVER STEPS. CharacterBody3D cannot climb a step at all, and the
	HQ's rule — no traversal may demand a jump-height — is the same rule outdoors.
	The derivation is _city_cable's, read it there: create_box composes
	Basis(UP, yaw) * Basis(RIGHT, tilt), so a box long in LOCAL Z is tipped by
	`tilt` and then swung to its heading by `yaw`, and local +Z lands on
	(cos(tilt)*sin(yaw), -sin(tilt), cos(tilt)*cos(yaw)). A ramp on +X is therefore
	yaw = +PI/2 with tilt = -atan2(rise, run); a box long in local X could not be
	sloped at all, and yaw = -PI/2 mirrors the whole thing for a -X climb.

	NO FOOTPRINT, deliberately: a ramp is the one piece of city geometry you are
	MEANT to walk up, and an `obstacles` entry is a keep-out claim that would push
	crocodiles off it and drop every coin that crossed it.
	"""
	var slice := _city_chunk_slice(chunk_center, ramp)
	if not slice.has_area():
		return
	var run: float = ramp.size.x
	var mid := slice.get_center()
	# How far up the climb this slice's centre sits, 0 at the foot to 1 at the
	# head — measured from the rect's west edge and flipped for a -X ramp, so
	# `dir` is honoured rather than assumed.
	var climbed := clampf((mid.x - ramp.position.x) / run, 0.0, 1.0)
	if dir < 0.0:
		climbed = 1.0 - climbed
	# The slice is longer than its X width by exactly the slope's hypotenuse
	# ratio, which is what makes two neighbouring slices meet flush on the same
	# plane rather than leaving a lip at the seam.
	var slope_len := slice.size.x * sqrt(run * run + rise * rise) / run
	create_box(
			Vector3(mid.x - chunk_center.x,
					climbed * rise - thickness * 0.5,
					mid.y - chunk_center.z),
			Vector3(slice.size.y, thickness, slope_len),
			PI * 0.5 * dir, rng, block_batch, block_body, -atan2(rise, run), stone)


func spawn_city_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's slice of Budapest (bead godot-test1-8gw.3).

	@param chunk_pos: Chunk coordinates being built.
	@param parent_chunk: The chunk mesh, for the parts of the city that are nodes
	                     rather than boxes (the landmark accents; nothing here
	                     needs it yet).
	@param obstacles: Out-param; the plateau massifs append their footprints here,
	                  so the crocodile spawner and the coin perch rule see them.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	ORDERING REQUIREMENT, the same one the artifact / camp / landmark / chest
	family carries: this runs AFTER every spawner that fills `obstacles` and
	BEFORE _build_block_multimesh and the block_body attach, so the city's stone
	joins the chunk's one draw call and its one collision body — and BEFORE the
	coin spawners, so the approach line's perch-or-skip rule can see a plateau.

	WHAT IT BUILDS, in this order:
	  1. the PLATEAU slice — one box, the chunk square meeting the hill's rect,
	     y = 0 to `top`, plus one footprint at climbable: false;
	  2. the RAMP slice — one TILTED box, the only way onto that lid;
	  3. the LANDMARK slices — _spawn_city_landmarks_in_chunk, this chunk's share
	     of every authored slot whose disc reaches into its square;
	  5. the AVENUE slice — a thin, non-colliding pavement slab out of the gate;
	  6. the four BRIDGE DECKS and their ramped approaches — bead .4's, and the
	     one step with a public entry point of its own so the self-check can walk
	     a deck without twenty landmark builders in the way.
	4 is the gate district and is its own task; the Danube's crocodiles are a
	spawner of their own, not city stone. The numbering is DEC-10's, kept as it
	is so the gap is visibly a slot rather than an omission.
	"""
	var chunk_center := chunk_to_world(chunk_pos)
	# Cheap rect reject: every chunk in the world that is not in the city pays one
	# intersection and nothing else.
	if not city_chunk(chunk_center):
		return

	# The private stream — see CITY_STREAM_SEED for why it is private and why it
	# is constant. Its draws are colour-ramp padding; every box below overrides.
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for i in range(BudapestPlan.PLATEAUS.size()):
		var row: Dictionary = BudapestPlan.PLATEAUS[i]
		var top: float = row["top"]

		# ---- 1. THE PLATEAU -------------------------------------------------
		# A hill in this game is a MASSIF WITH A WALKABLE LID, not raised terrain:
		# the ground is one flat plane at y = 0 and every coin height, gravity
		# settle and block base in the world depends on that. So the hill is one
		# box per chunk with cliffs on every side, and the footprint is
		# climbable: false — the mountain-massif convention, which is what tells
		# the coin road to SKIP a coin over it rather than perch one on a cliff.
		var slice := _city_chunk_slice(chunk_center, row["rect"])
		if slice.has_area():
			var mid := slice.get_center()
			var local := Vector3(mid.x - chunk_center.x, top * 0.5, mid.y - chunk_center.z)
			create_box(local, Vector3(slice.size.x, top, slice.size.y), 0.0,
					rng, block_batch, block_body, 0.0, CITY_HILL_STONE)
			obstacles.append({
				"pos": Vector3(local.x, 0.0, local.z),
				"radius": slice.size.length() * 0.5,   # the slice's circumscribing disc
				"top": top,
				"climbable": false,
			})

		# ---- 2. THE RAMP ----------------------------------------------------
		# One tilted slab, the only way onto the lid — see _city_ramp_slice, which
		# the bridges' approaches share.
		_city_ramp_slice(chunk_center, row["ramp"], top,
				signf(float(row["ramp_dir"])), CITY_RAMP_THICKNESS,
				rng, block_batch, block_body, CITY_HILL_STONE)

	# ---- 3. THE LANDMARK SLICES ---------------------------------------------
	# Its own function because it is the bead's keystone decision and wants the
	# whole docstring to itself. It gets the chunk centre rather than recomputing
	# it, and its own per-slot RNG rather than this one.
	_spawn_city_landmarks_in_chunk(chunk_center, parent_chunk, obstacles, block_batch, block_body)

	# ---- 4. THE GATE DISTRICT ------------------------------------------------
	_spawn_gate_district_in_chunk(chunk_center, obstacles, block_batch, block_body)

	# ---- 4b. THE CITY BLOCKS (bead godot-test1-8gw.9) ------------------------
	# Every block of the street grid the plan lays down, filled with a continuous
	# street wall around a hollow courtyard. It runs AFTER the landmarks and the
	# gate district for the same reason those run after the props: `obstacles` is
	# read to decide nothing here (a block is authored, not rolled), but the
	# ORDER the footprints land in is what every later spawner's candidate loop
	# sees, and the authored city has first claim on its own ground.
	_spawn_city_blocks_in_chunk(chunk_center, obstacles, block_batch, block_body)

	# ---- 5. THE AVENUE ------------------------------------------------------
	# The one street this bead draws: 16 m of pavement running east out of the
	# gate along z = 0, to the Danube's west bank. Bead godot-test1-8gw.9 owns the
	# rest of the grid; this file owns STREET_PITCH as a parameter and nothing more.
	#
	# The east end is _approach_coin_east_end() — the SAME west bank the approach
	# coin line stops at, asked once and answered from the river's own polyline, so
	# the pavement and the coins on it cannot end in different places.
	var avenue := Rect2(
			BudapestPlan.GATE.x,
			BudapestPlan.GATE.z - BudapestPlan.AVENUE_HALF_WIDTH,
			_approach_coin_east_end() - BudapestPlan.GATE.x,
			BudapestPlan.AVENUE_HALF_WIDTH * 2.0)
	var av := _city_chunk_slice(chunk_center, avenue)
	if av.has_area():
		var mid_a := av.get_center()
		create_box(
				Vector3(mid_a.x - chunk_center.x, 0.0, mid_a.y - chunk_center.z),
				Vector3(av.size.x, CITY_AVENUE_THICKNESS, av.size.y), 0.0,
				rng, block_batch, block_body, 0.0, CITY_AVENUE_STONE, false)

	# ---- 6. THE FOUR BRIDGE DECKS -------------------------------------------
	spawn_city_bridges_in_chunk(chunk_center, block_batch, block_body)


func spawn_city_bridges_in_chunk(chunk_center: Vector3, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Build this chunk's slice of the four Danube bridges' DECKS (bead
	godot-test1-8gw.4).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	PUBLIC, for the same reason ChunkBatch.split_city_boxes_on_chunk_grid is:
	budapest_selfcheck check 14 walks a bridge's chunks and measures the surface
	it can actually stand on, and it can only do that if the deck's boxes arrive
	on their own instead of mixed in with twenty landmark builders' piers and
	towers.

	WHAT IT BUILDS, per bridge, all of it sliced by _city_chunk_slice so
	neighbouring chunks meet flush: a flat colliding slab hung under
	BudapestPlan.BRIDGE_DECK_TOP across the middle, and one tilted ramp at each end
	climbing to it from y = 0. The ramp shares the plateaus' _city_ramp_slice, so
	"no traversal may demand a jump-height" is one piece of arithmetic in this file
	and not two.

	WHAT IT DOES NOT BUILD is the bridge: the towers, chains, trusses, cutwaters and
	lions belong to landmark_builders.gd's `_city_*_bridge` rows, which stand on the
	SLOTS entry of the same id. The deck is placed off the DRY_RECTS row the band is
	already punched out by, and check 14 asserts the two agree on where the bridge
	is — the ornament hangs its chains at exactly BRIDGE_DECK_TOP.

	ITS OWN PRIVATE STREAM, the gate district's precedent: create_box draws four
	numbers per box for a colour ramp this feature overrides anyway, and a draw
	taken from a stream somebody else reads slides every crocodile in the world.

	NO `obstacles` FOOTPRINT, deliberately, and for the ramp's reason one span
	along: a deck is MEANT to be walked. Nothing downstream wants one either —
	inside the rect the coin line stops at the west bank and the only predator is
	spawn_danube_crocodiles_in_chunk, which keeps clear of a deck through
	DANUBE_CROC_DECK_MARGIN off the same rect rather than through this list.

	# ponytail: THE STRIP UNDER A DECK IS DRY TOO, and that is DRY_RECTS being
	# XZ-only rather than an oversight — the same trade the plan's SECTION 3 makes
	# for Margaret Island. A player who ignores the ramps can walk the river bed
	# beneath a bridge without wading. Closing it means a Y-aware is_river_at(),
	# which every predator and the ground shader read per frame; the cheap half-fix
	# (a solid abutment wedge at each end) is worth doing the day somebody notices.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for row_v: Variant in BudapestPlan.BRIDGES:
		var row: Dictionary = row_v
		var deck: Rect2 = BudapestPlan.bridge_deck(row)
		# Cheap reject: a chunk nowhere near this bridge pays one intersection.
		if not _city_chunk_slice(chunk_center, deck).has_area():
			continue

		# The level span, hung UNDER its walking height so the ramps meet its top.
		var flat := _city_chunk_slice(chunk_center, BudapestPlan.bridge_flat(row))
		if flat.has_area():
			var mid := flat.get_center()
			create_box(
					Vector3(mid.x - chunk_center.x,
							BudapestPlan.BRIDGE_DECK_TOP - CITY_BRIDGE_DECK_THICKNESS * 0.5,
							mid.y - chunk_center.z),
					Vector3(flat.size.x, CITY_BRIDGE_DECK_THICKNESS, flat.size.y),
					0.0, rng, block_batch, block_body, 0.0, CITY_AVENUE_STONE)

		# ...and the two approaches. The east one climbs WESTWARD (dir -1), so its
		# foot is on the east bank — the same slab mirrored, not a second case.
		for east in [false, true]:
			_city_ramp_slice(chunk_center, BudapestPlan.bridge_ramp(row, east),
					BudapestPlan.BRIDGE_DECK_TOP, -1.0 if east else 1.0,
					CITY_RAMP_THICKNESS, rng, block_batch, block_body,
					CITY_AVENUE_STONE)


func _spawn_city_landmarks_in_chunk(chunk_center: Vector3, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's SHARE of every authored Budapest landmark whose disc reaches
	into its square (bead godot-test1-8gw.3).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param parent_chunk: The real chunk mesh — the accent nodes' final home, but
	                     only for the chunk holding a slot's CENTRE (see below).
	@param obstacles: Out-param; one round footprint per overlapping slot.
	@param block_batch: Out-param; the kept boxes join the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	================= THE DECISION, AND THE TWO IT BEAT =================

	The Parliament is 268 m long and Buda Castle's disc is 156 m across, while a
	chunk is 50 m and the web build keeps 49 of them resident. So a landmark
	CANNOT be emitted by "its own" chunk: walk to the far end of the Parliament and
	the chunk that would have built it has unloaded, and the building disappears
	while you are standing on it.

	THE ANSWER IS (a) PER-CHUNK SLICING. Every chunk whose square meets a slot's
	disc runs that slot's builder into a SCRATCH batch, a SCRATCH body and a
	SCRATCH chunk node, and keeps only the pieces whose CENTRE falls inside its own
	square. The two rejected answers, recorded here because this is exactly what a
	future reader will want to re-open:

	  (b) MANAGER-PARENT THE GIANTS, the way the HQ's shell is parented. Rejected
	      because CLAUDE.md says the tower is the ONE lifetime exception and must
	      stay one, and this would make a second one out of a dozen buildings —
	      each with its own "when does it get freed" question and no chunk to
	      answer it.
	  (c) A WIDER RESIDENCY RADIUS for city chunks. Rejected because the 49-chunk
	      web residency ceiling is the entire reason the city is chunk-streamed
	      instead of authored into the scene; widening it for the city spends the
	      budget the decision was made to protect.

	WHY (a) IS NEARLY FREE: the city builders are PURE FUNCTIONS OF (centre, rng)
	whose random stream touches COLOUR ONLY — landmark_builders.gd's own banner
	says so, and not one dimension, offset or count is drawn. Run the same builder
	from the same seed in a neighbouring chunk and it emits the SAME boxes at the
	SAME world positions, so clipping is a filter on the output and needs no edit
	to that file at all. The cost is measured: the Parliament is 122 boxes over
	~49 chunks, i.e. ~6,000 create_box calls spread one chunk per frame — about
	122 a frame, which is what one ordinary prop chunk already pays.

	================= THE FOUR RULES THAT MAKE IT CORRECT =================

	1. THE SEED IS THE SLOT INDEX AND NOTHING ELSE. No run_seed (the city is
	   authored — tower_site()'s ruling) and, far more sharply, NO CHUNK
	   COORDINATE: mix one in and every slice draws its own colours, and the
	   Parliament comes out tie-dyed along its chunk seams. The salt is wider than
	   an int32 and wraps into Vector3i's component; the wrap is silent but it is
	   deterministic and identical in every chunk, which is the only property this
	   seed needs.
	2. THE CLIP IS HALF-OPEN — `>= -half` and `< half` on both axes. A box centred
	   exactly on a chunk boundary then lands in exactly ONE chunk: never in both
	   (a doubled, z-fighting wall) and never in neither (a hole).
	   THE CENTRE RULE ONLY SLICES A LANDMARK; IT DOES NOT SLICE A BOX, and these
	   builders emit single boxes far bigger than a chunk (Buda Castle's terrace is
	   70 x 300, the Parliament's plinth 125 x 272, against a 50 m chunk). Handed
	   whole to the chunk holding its centre, such a box unloads with that chunk —
	   on the web build that is 150 m of Chebyshev residency against a 300 m
	   palace, i.e. the building vanishing while you walk its far end, which is the
	   exact failure this whole function exists to prevent. So
	   ChunkBatch.split_city_boxes_on_chunk_grid() cuts every oversized
	   AXIS-ALIGNED box on the world chunk grid FIRST; the centre rule then sees
	   only pieces that fit inside one cell and is correct again. Rotated boxes
	   cannot be cut into boxes and keep the centre rule — budapest_selfcheck
	   check 5 fails a rotated box
	   whose footprint exceeds a chunk, which is what keeps that safe.
	   ponytail: the test is on the CHUNK-LOCAL centre, and a local coordinate is
	   an f32 with the chunk's own origin already subtracted, so two neighbours
	   disagree about a seam-straddling box only if their f32 rounding disagrees —
	   sub-micron, and measured as zero over all 15 shipped buildings. If a box
	   ever does double, nudge the slot, not this test: an epsilon here reopens
	   the hole case on the other side.
	3. THE CLIP APPLIES TO BOTH HALVES. Batch entries are filtered on their
	   transform origin; collision shapes are filtered on the scratch body's own
	   CollisionShape3D transforms and REPARENTED rather than rebuilt. Do NOT try
	   to pair a shape with a batch entry by index — every `collide = false` box
	   (and these builders are full of them: domes, spires, cornices) makes the
	   two lists different lengths.
	4. THE ACCENT EXISTS EXACTLY ONCE. Ten of these builders hang a glowing
	   MeshInstance3D on parent_chunk, and under slicing that would give the
	   Parliament one beacon per overlapping chunk. So they are handed a scratch
	   node, and afterwards: if the slot's CENTRE is in this chunk the scratch's
	   children are reparented onto the real one, otherwise the scratch is freed
	   and takes them with it. One rule, no builder edit.

	THE FOOTPRINT is one disc per slot in EVERY chunk the slot touches, at
	climbable: false — the massif convention, so the coin rule skips a coin over a
	cathedral rather than perching it on the silhouette top of a hollow nave, and
	the crocodile spawner keeps out. It is per-chunk because `obstacles` is
	per-chunk, and it is the whole slot rather than this slice because a spawner
	200 m away in another chunk cannot see a neighbour's list anyway.

	AN EMPTY BUILDER IS SKIPPED — that is the whole of "leave the slot empty" for
	the seven wave-C reservations.
	"""
	var half := chunk_size / 2.0

	for i in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[i]
		var builder: String = slot["builder"]
		if builder.is_empty():
			continue   # a wave-C reservation: a position and a radius, no stone yet

		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]

		# Exact disc-meets-square reject, via the square's closest point to the
		# centre. Every chunk in the city pays 22 of these and nothing else; the
		# rest of the world never gets here at all (spawn_city_in_chunk's own rect
		# reject returned first).
		var near := Vector2(
				clampf(pos.x, chunk_center.x - half, chunk_center.x + half),
				clampf(pos.z, chunk_center.z - half, chunk_center.z + half))
		if Vector2(pos.x - near.x, pos.z - near.y).length_squared() > radius * radius:
			continue

		# Rule 1. The seed carries the slot index and the salt; the chunk is
		# deliberately absent.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(i, BudapestPlan.CITY_LANDMARK_SALT, 0))

		# The scratch trio. None of the three is ever added to the scene tree:
		# the body and the chunk node are pure receptacles that get emptied and
		# freed below, and the batch is a plain Array.
		var scratch_batch: Array = []
		var scratch_body := StaticBody3D.new()
		var scratch_chunk := MeshInstance3D.new()

		# Builders take a CHUNK-LOCAL centre (the field landmarks' convention), so
		# the slot's world position is rebased here — and its authored y is passed
		# through unchanged, which is how the three slots on a plateau stand on the
		# lid instead of inside the hill.
		var center := Vector3(pos.x - chunk_center.x, pos.y, pos.z - chunk_center.z)
		var footprint: Dictionary = _landmark_builders.call(
				builder, self, center, rng, scratch_chunk, scratch_batch, scratch_body)

		# Rule 2a: a box WIDER THAN A CHUNK is cut on the grid first (see the
		# helper). Without this the centre rule below hands a 300 m box to one
		# chunk whole, and that chunk unloads while you stand on the far end.
		ChunkBatch.split_city_boxes_on_chunk_grid(self, chunk_center, scratch_batch, scratch_body)

		# Rule 2 + 3a: the visual half, half-open on both axes.
		for entry in scratch_batch:
			var o: Vector3 = entry["transform"].origin
			if o.x >= -half and o.x < half and o.z >= -half and o.z < half:
				block_batch.append(entry)

		# Rule 3b: the collision half. get_children() hands back a copy, so
		# removing while iterating it is safe.
		for shape in scratch_body.get_children():
			var o: Vector3 = shape.transform.origin
			if o.x >= -half and o.x < half and o.z >= -half and o.z < half:
				scratch_body.remove_child(shape)
				block_body.add_child(shape)
		scratch_body.free()   # takes every shape this chunk did not claim with it

		# Rule 4: the accent, on the centre chunk only.
		if center.x >= -half and center.x < half and center.z >= -half and center.z < half:
			for accent in scratch_chunk.get_children():
				scratch_chunk.remove_child(accent)
				parent_chunk.add_child(accent)
		scratch_chunk.free()

		# `top` IS RELATIVE TO THE BUILDER'S CENTRE, and here that centre is not on
		# the ground: a builder accumulates its height from 0 and the field spawners
		# hand it center.y = 0, so there the two frames coincide and `footprint.top`
		# is read straight through. The three slots standing on a plateau lid get
		# center.y = pos.y (30, 30, 46), so the lid has to be added back or the
		# entry understates Buda Castle's roofline by the whole hill — and `top` is
		# the shared footprint currency every later spawner reads.
		obstacles.append({
			"pos": Vector3(center.x, 0.0, center.z),
			"radius": radius,
			"top": pos.y + float(footprint.get("top", 0.0)),
			"climbable": false,
		})


func _spawn_gate_district_in_chunk(chunk_center: Vector3, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's share of the GATE DISTRICT (DEC-11, bead godot-test1-8gw.3).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param obstacles: Out-param; one CLIMBABLE disc per house, one prop footprint
	                  per dressing piece.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	WHY THIS DISTRICT AND ONLY THIS DISTRICT. It is ~200 x 260 m immediately east
	of the gate — the SMALLEST slice that exercises every dangerous seam at once:
	authored buildings streamed through ordinary chunks, the city prop builders
	called on authored spots, the avenue running between them, a plateau ramp one
	chunk west and a dry bridge deck 900 m east. Bead godot-test1-8gw.7 owns the
	rest of the street grid; this file owns STREET_PITCH as a parameter and this
	one block as the proof.

	SLICED BY OWNERSHIP, NOT BY CLIPPING, and that is the difference between a
	house and the Parliament. A landmark is 268 m long and has to be cut across
	the chunks it stands on (see _spawn_city_landmarks_in_chunk); a house is 4 m,
	so the chunk containing its CENTRE builds the whole thing. The test is the
	same HALF-OPEN comparison for the same reason — a house centred exactly on a
	seam lands in exactly one chunk, never both and never neither. The couple of
	metres a house may overhang its own chunk are freed with it, 150 m away and
	three chunks behind the camera.

	THE RECIPE IS _spawn_city_content'S, COPIED AND NOT SHARED. Hull + eaves roof
	+ door + windows, with the dimensions AUTHORED (DISTRICT_HOUSES) instead of
	drawn. Refactoring the two to share would move code inside a hot deterministic
	path whose draw ORDER is load-bearing for every crocodile downstream of it;
	ten lines of create_box here is a smaller and far safer diff than proving a
	code motion changed no draw.

	EVERY HOUSE ROOF IS STILL A REST SPOT. The plan caps every authored `height`
	at PROP_MAX_STEP (2.6) and the footprint is climbable: true at the HULL top,
	exactly as the procedural city's is — a gate district whose roofs you could
	not reach would quietly be the one city block that is not a city block.
	"""
	var half := chunk_size / 2.0
	if not _city_chunk_slice(chunk_center, BudapestPlan.DISTRICT).has_area():
		return

	# The private stream. Its draws are create_box's colour-ramp padding: every
	# box below passes an explicit override off the plan's authored shades, so the
	# seed only has to be a constant, not a good one.
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for row in BudapestPlan.DISTRICT_HOUSES:
		var pos: Vector3 = row["pos"]
		var local := Vector3(pos.x - chunk_center.x, 0.0, pos.z - chunk_center.z)
		if not (local.x >= -half and local.x < half and local.z >= -half and local.z < half):
			continue

		var size: Vector3 = row["size"]
		var width := size.x
		var height := size.y
		var depth := size.z
		# Both rows FACE THE AVENUE: yaw 0 puts `front` on +Z for the north side,
		# yaw PI turns the south side round. The plan carries no yaw column because
		# there is nothing to choose — a street is two facades looking at each other.
		var yaw := 0.0 if pos.z < 0.0 else PI
		var front := Vector3(-sin(yaw), 0.0, cos(yaw))
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		# The plan's shades are FACTORS between this file's palette entries, which
		# is what keeps budapest_plan.gd free of any dependency on it.
		var wall := CITY_PLASTER_A.lerp(CITY_PLASTER_B, float(row["wall_shade"]))
		var roof := CITY_ROOF_TILE.lerp(CITY_ROOF_SLATE, float(row["roof_shade"]))

		# Hull — the ONLY colliding box, and the one whose top face the footprint
		# names.
		create_box(
			local + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth),
			yaw, rng, block_batch, block_body, 0.0, wall
		)
		# Roof — a thin film over the hull top, collide = false, oversailing as
		# eaves. The player stands on the HULL, inside this film.
		create_box(
			local + Vector3(0.0, height + CITY_ROOF_THICKNESS * 0.5, 0.0),
			Vector3(width + CITY_ROOF_EAVES * 2.0, CITY_ROOF_THICKNESS, depth + CITY_ROOF_EAVES * 2.0),
			yaw, rng, block_batch, block_body, 0.0, roof, false
		)
		# Door and windows — trim, never solid: they sit inside the hull's own
		# collision box, so making them collide would buy nothing but a snag.
		var door_h := height * 0.62
		create_box(
			local + front * (depth * 0.5) + Vector3(0.0, door_h * 0.5, 0.0),
			Vector3(width * 0.24, door_h, 0.10), yaw,
			rng, block_batch, block_body, 0.0, PROP_CRATE, false
		)
		# Two windows, SYMMETRIC about the door and above its head — the same
		# arrangement (and the same two fixes) as `_spawn_city_content`'s houses,
		# which this recipe is copied from: no one-sided bias, and clear of the
		# door's box so the two never end up coplanar and z-fighting.
		for w in 2:
			var offset := (float(w) - 0.5) * width * 0.32
			create_box(
				local + front * (depth * 0.5) + right * offset
						+ Vector3(0.0, height * 0.78, 0.0),
				Vector3(width * 0.16, height * 0.22, 0.10), yaw,
				rng, block_batch, block_body, 0.0, CITY_ROOF_SLATE, false
			)

		obstacles.append({
			"pos": local,
			"radius": 0.5 * sqrt(pow(width + CITY_ROOF_EAVES * 2.0, 2.0) + pow(depth + CITY_ROOF_EAVES * 2.0, 2.0)),
			"top": height,
			"climbable": true,
		})

	# ---- STREET DRESSING ----------------------------------------------------
	# The three jb7 CITY prop builders, called DIRECTLY rather than through
	# TerrainProps.build_prop: that function's job is to pick a theme from biome_at, and here
	# the theme is not in question — this is Budapest, so it is the city arm or
	# nothing. One piece in each gap between neighbouring houses on the north row
	# (seven today), alternating sides and cycling the three builders. The row is
	# FILTERED out of the table rather than counted off the front of it: the south
	# houses share the table, so a ninth north house typed in would otherwise pair
	# a north house with a south one and drop the prop at a meaningless midpoint.
	#
	# The spots are DERIVED from the house table rather than typed into a second
	# one, so moving a house moves the crate stack beside it and there is no
	# second table to fall out of step. Each piece takes its OWN RNG seeded off
	# its index alone — the builders draw real dimensions, and one seeded off the
	# shared stream would make a prop's shape depend on how many boxes the chunk
	# happened to build before it.
	var north: Array = BudapestPlan.DISTRICT_HOUSES.filter(
			func(h: Dictionary) -> bool: return h["pos"].z < 0.0)
	for i in range(north.size() - 1):
		var a: Vector3 = north[i]["pos"]
		var b: Vector3 = north[i + 1]["pos"]
		var wx := (a.x + b.x) * 0.5
		var wz := -CITY_DISTRICT_PROP_Z if i % 2 == 0 else CITY_DISTRICT_PROP_Z
		var p_local := Vector3(wx - chunk_center.x, 0.0, wz - chunk_center.z)
		if not (p_local.x >= -half and p_local.x < half and p_local.z >= -half and p_local.z < half):
			continue

		var prng := RandomNumberGenerator.new()
		prng.seed = CITY_STREAM_SEED + i
		var foot: Dictionary
		match i % 3:
			0:
				foot = TerrainProps._prop_crate_stack(self, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
			1:
				foot = TerrainProps._prop_garden_wall(self, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
			_:
				foot = TerrainProps._prop_paving_stack(self, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
		obstacles.append({
			"pos": p_local,
			"radius": foot["radius"],
			"top": foot["top"],
			"climbable": foot["climbable"],
		})


func _spawn_city_blocks_in_chunk(chunk_center: Vector3, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Fill this chunk's share of every CITY BLOCK the plan's street grid bounds
	(bead godot-test1-8gw.9).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param obstacles: Out-param; one keep-out disc per few metres of street wall,
	                  so the hunters that DO spawn in the city are not wedged
	                  inside a facade and a coin over one is skipped, not buried.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	WHAT THE OWNER ASKED FOR, verbatim: "budapest seems really empty, but it is
	full of multi story buildings in fact, make it so, make it like what we can see
	on google map walking mode". A street-view city is a CONTINUOUS STREET WALL,
	so every block of the grid that the city has not reserved for something else
	(BudapestPlan.block_buildable) gets four wings of contiguous facade around a
	hollow courtyard: 4-6 storeys of eclectic Pest, 2-3 of Buda hillside.

	AT MOST FOUR CELLS ARE EVER ASKED. A block is 62 m on the grid and a chunk is
	50 m, so a chunk square can straddle one grid line per axis and no more. The
	cheap rect reject in spawn_city_in_chunk has already turned away every chunk
	outside the rect, so the cost of this function for the whole rest of the world
	is zero.

	A BLOCK IS BUILT WHOLE BY EVERY CHUNK THAT TOUCHES IT, AND SLICED ON THE WAY
	OUT. That is the landmark builders' rule one scale down: the facade stream is
	seeded off the CELL, every parameter anything READS is drawn before anything
	is emitted, and only then is each rect intersected with this chunk's
	square. So two chunks slicing one block agree bit for bit on its heights and
	its colours, and the wall meets flush at the seam because _city_chunk_slice
	cuts both halves out of the same rect.
	"""
	var half := chunk_size / 2.0
	var square := Rect2(chunk_center.x - half, chunk_center.z - half, chunk_size, chunk_size)
	var lo: Vector2i = BudapestPlan.block_cell(square.position.x, square.position.y)
	var hi: Vector2i = BudapestPlan.block_cell(square.end.x, square.end.y)
	for k in range(lo.x, hi.x + 1):
		for m in range(lo.y, hi.y + 1):
			var cell := Vector2i(k, m)
			if BudapestPlan.block_buildable(cell):
				_build_city_block(cell, chunk_center, obstacles, block_batch, block_body)


func _build_city_block(cell: Vector2i, chunk_center: Vector3, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	One block of the city: eight buildings in a ring, and this chunk's slice of
	each of them.

	@param cell: The block's integer grid coordinates.

	THE STREAM IS THE WHOLE CORRECTNESS ARGUMENT. `rng` is seeded off (cell,
	CITY_BLOCK_SALT) and NOTHING ELSE — no run_seed (Budapest is authored, the
	tower-furniture precedent), no chunk coordinate (a block is built by up to
	four of them and they have to agree), no draw from anybody else's stream.

	AND EVERY DRAW ANYTHING READS IS TAKEN UP FRONT, before the first box is
	emitted. That is the exact claim, and the qualifier is load-bearing: create_box
	spends four more numbers per box on its curated colour ramp and its roughness,
	AFTER these, and a chunk that skips a box (its piece is in the chunk next door)
	does not spend them. So the streams of two chunks slicing one cell DO diverge —
	in create_box's ramp draws, and only there.

	That divergence is unobservable by construction, for the reason CITY_STREAM_SEED
	states one feature along: every box here passes an explicit `color_override`, so
	the ramp's output is discarded and its draws are pure padding. Nothing downstream
	reads this rng either — it is per-cell and dies with the call. What the two
	chunks must agree on is `storeys`, `walls`, `awnings`, `balconies` and `roof`,
	and those are all drawn above, in one fixed order, for all eight buildings,
	before any geometry exists to skip. budapest_selfcheck check 3 measures the
	result rather than the argument: a dense Pest block, byte-identical across two
	different run seeds.

	~TEN BOXES BUY A BUILDING: one colliding hull, a window course per storey, two
	shopfronts around a doorway gap, an awning, an optional balcony and the cornice.
	See _city_block_boxes and the CITY BLOCKS constants.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, CITY_BLOCK_SALT))

	var interior := BudapestPlan.block_rect(cell)
	var centre := interior.get_center()
	var band: Vector2i = BudapestPlan.BLOCK_STOREYS_BUDA \
			if BudapestPlan.is_buda(centre.x, centre.y) \
			else BudapestPlan.BLOCK_STOREYS_PEST

	# ---- EVERY DRAW, BEFORE ANY EMIT ---------------------------------------
	# A building's whole description is drawn here, in one fixed order, for all
	# eight of them — see the docstring. `hues` is the bank's own palette, so a
	# Pest block is cream beside ochre beside grey-green and not eight samples of
	# one ramp.
	var buda := BudapestPlan.is_buda(centre.x, centre.y)
	var hues: Array[Color] = CITY_FACADE_BUDA if buda else CITY_FACADE_PEST
	var base := rng.randi_range(band.x, band.y)
	var roof := CITY_ROOF_TILE.lerp(CITY_ROOF_SLATE, rng.randf())
	var storeys: Array[int] = []
	var walls: Array[Color] = []
	var awnings: Array[Color] = []
	var balconies: Array[bool] = []
	for _i in range(4 * BudapestPlan.BLOCK_SEGMENTS):
		storeys.append(clampi(
				base + rng.randi_range(-CITY_BLOCK_STOREY_JITTER, CITY_BLOCK_STOREY_JITTER),
				band.x, band.y))
		walls.append((hues[rng.randi_range(0, hues.size() - 1)] as Color)
				.lerp(CITY_PLASTER_B, rng.randf() * CITY_FACADE_TINT_MAX))
		awnings.append(CITY_AWNING_A.lerp(CITY_AWNING_B, rng.randf()))
		# Buda's houses get no balcony at all, but the draw is taken either way:
		# a stream whose length depended on which bank it was on would be a
		# second thing to keep in step for nothing.
		balconies.append(rng.randf() < CITY_BALCONY_CHANCE and not buda)

	# ---- ...AND ONLY THEN, THIS CHUNK'S SLICE OF EACH ------------------------
	for side in 4:
		var wing: Rect2 = BudapestPlan.block_wing(cell, side)
		var outward: Vector2 = BudapestPlan.block_wing_outward(side)
		# A wing is long on X for the north/south walls and long on Z for the two
		# side walls; `along_x` is which axis it runs down, and the bands stand
		# proud on the other one.
		var along_x := absf(outward.y) > 0.5
		for seg in range(BudapestPlan.BLOCK_SEGMENTS):
			var idx := side * BudapestPlan.BLOCK_SEGMENTS + seg
			var height := float(storeys[idx]) * CITY_STOREY_HEIGHT
			var piece := _city_block_segment(wing, along_x, seg)
			_city_block_boxes(piece, along_x, storeys[idx], walls[idx], roof,
					awnings[idx], balconies[idx], chunk_center, rng,
					block_batch, block_body)
			_city_block_footprints(piece, height, chunk_center, obstacles)
			_city_block_door(piece, outward, chunk_center, rng, block_batch, block_body)


func _city_block_segment(wing: Rect2, along_x: bool, seg: int) -> Rect2:
	"""One building's footprint: the `seg`'th equal slice of a wing along its long
	axis. Equal slices and not jittered ones, because the ROOFLINE is where the
	variety lives — two neighbours of different heights read as two houses, and a
	jittered party wall would only cost a constant nobody can see."""
	var n := float(BudapestPlan.BLOCK_SEGMENTS)
	if along_x:
		var w := wing.size.x / n
		return Rect2(wing.position.x + float(seg) * w, wing.position.y, w, wing.size.y)
	var d := wing.size.y / n
	return Rect2(wing.position.x, wing.position.y + float(seg) * d, wing.size.x, d)


func _city_block_boxes(piece: Rect2, along_x: bool, storeys: int, wall: Color,
		roof: Color, awning: Color, balcony: bool, chunk_center: Vector3,
		rng: RandomNumberGenerator, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Every SLICEABLE box of one building: the hull, a window course per storey, the
	two halves of its shopfront with the doorway gap between them, the awning over
	them, an optional balcony course and the roofline cornice.

	WHY A BAND AND NOT A WINDOW. A 21 m facade drawn as one plaster box with a
	cornice on top reads as a WALL — which is what the first cut of this bead
	shipped and what the owner's "like google map walking mode" is not. What makes
	a real street legible from across it is the HORIZONTAL RHYTHM of the window
	courses, and a band gets that for ONE box per storey where a window grid would
	cost thirty. `_city_band` is the whole vocabulary; everything here is a call
	to it with a height, a thickness, a proud distance and a colour.

	THE BANDS ARE GROWN BEFORE THEY ARE SLICED, never after, and that ordering is
	load-bearing at a chunk seam. Growing a slice would push a band across the
	seam and into the identical band its neighbour chunk grew the other way, so
	the two would overlap by twice the proud distance and z-fight for the length
	of the wall. Growing the WHOLE rect and then cutting it gives two pieces that
	meet exactly, which is the same argument _city_chunk_slice already makes for
	the hull.

	Only the HULL collides. A cornice you could stand on would be a 20 m ledge the
	whole way round every block in the city; a shopfront you could snag on would
	be 46 m of kerb per block face. Both are decoration, and decoration in this
	codebase pays for its pixels and not for a collision shape.
	"""
	var height := float(storeys) * CITY_STOREY_HEIGHT

	# The hull: the one box with a collision shape, floor to roofline.
	var hull := _city_chunk_slice(chunk_center, piece)
	if hull.has_area():
		var c := hull.get_center()
		create_box(Vector3(c.x - chunk_center.x, height * 0.5, c.y - chunk_center.z),
				Vector3(hull.size.x, height, hull.size.y), 0.0,
				rng, block_batch, block_body, 0.0, wall)

	# ---- THE WINDOW COURSES, one per storey above the shopfront -------------
	# 6 cm PROUD, which reads as flush at street distance and is the only way the
	# course exists at all — see CITY_WINDOW_PROUD for the recessed version that
	# did not. The glass tone alternates by storey parity, so five storeys read as
	# five courses and not as one striped texture.
	for s in range(1, storeys):
		_city_band(piece, along_x, CITY_WINDOW_PROUD,
				float(s) * CITY_STOREY_HEIGHT + CITY_WINDOW_SILL + CITY_WINDOW_HEIGHT * 0.5,
				CITY_WINDOW_HEIGHT,
				CITY_WINDOW_DARK if s % 2 == 0 else CITY_WINDOW_LIT,
				chunk_center, rng, block_batch, block_body)

	# ---- THE GROUND FLOOR: two shopfronts with the doorway between them ------
	# One band split around the door's own width is what turns a continuous dark
	# stripe into a row of SHOPS with an entrance, and it costs one extra box.
	# The door itself is _city_block_door's, placed by the chunk that owns it.
	var span := piece.size.x if along_x else piece.size.y
	var gap := (CITY_DOOR_WIDTH + 0.9) / span * 0.5   # half the gap, as a fraction
	for half in [Vector2(0.0, 0.5 - gap), Vector2(0.5 + gap, 1.0)]:
		_city_band(_city_sub_rect(piece, along_x, half.x, half.y), along_x,
				CITY_SHOPFRONT_PROUD, CITY_SHOPFRONT_HEIGHT * 0.5,
				CITY_SHOPFRONT_HEIGHT, CITY_SHOPFRONT_GLASS,
				chunk_center, rng, block_batch, block_body)
	# ...and the canvas awning over them, oversailing the pavement.
	_city_band(piece, along_x, CITY_AWNING_PROUD,
			CITY_SHOPFRONT_HEIGHT + CITY_AWNING_THICKNESS * 0.5,
			CITY_AWNING_THICKNESS, awning, chunk_center, rng, block_batch, block_body)

	# ---- THE BALCONY COURSE, on the Pest buildings that drew one ------------
	if balcony:
		_city_band(piece, along_x, CITY_BALCONY_PROUD, _city_balcony_y(height),
				CITY_BALCONY_THICKNESS, CITY_BALCONY_IRON,
				chunk_center, rng, block_batch, block_body)

	# ---- ...AND THE ROOFLINE ------------------------------------------------
	_city_band(piece, along_x, CITY_CORNICE_PROUD,
			height + CITY_CORNICE_THICKNESS * 0.25, CITY_CORNICE_THICKNESS, roof,
			chunk_center, rng, block_batch, block_body)


func _city_band(piece: Rect2, along_x: bool, proud: float, y: float, thickness: float,
		tone: Color, chunk_center: Vector3, rng: RandomNumberGenerator,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	ONE horizontal band lying against a building's facade — the single vocabulary
	every piece of articulation in this city is spelled in.

	@param proud: how far it stands off the wall on the CROSS axis. NEGATIVE
	              recesses it INTO the wall, which is what a window course is.
	@param y: the band's centre height. @param thickness: its full height.

	Grown on the cross axis only, so it never lengthens into the building next
	door, and grown before it is sliced — see the caller for why that ordering is
	the difference between a flush seam and a z-fighting one. Never collides.
	"""
	# Cross axis stands PROUD; the long axis is pulled IN by CITY_BAND_END_INSET so
	# the band's end faces never land on the hull's own end planes — see that const.
	var grown: Rect2 = piece.grow_individual(-CITY_BAND_END_INSET, proud, -CITY_BAND_END_INSET, proud) if along_x \
			else piece.grow_individual(proud, -CITY_BAND_END_INSET, proud, -CITY_BAND_END_INSET)
	var slice := _city_chunk_slice(chunk_center, grown)
	if not slice.has_area():
		return
	var mid := slice.get_center()
	create_box(Vector3(mid.x - chunk_center.x, y, mid.y - chunk_center.z),
			Vector3(slice.size.x, thickness, slice.size.y), 0.0,
			rng, block_batch, block_body, 0.0, tone, false)


func _city_sub_rect(piece: Rect2, along_x: bool, from: float, to: float) -> Rect2:
	"""The `from`..`to` fraction of a building's rect along its LONG axis — how the
	shopfront is split around its doorway."""
	if along_x:
		return Rect2(piece.position.x + piece.size.x * from, piece.position.y,
				piece.size.x * (to - from), piece.size.y)
	return Rect2(piece.position.x, piece.position.y + piece.size.y * from,
			piece.size.x, piece.size.y * (to - from))


func _city_balcony_y(height: float) -> float:
	"""The height of a building's balcony course: the top of its SECOND storey, or
	of its first when it only has two. A course drawn above the roofline is a rail
	hanging in the sky, which is what a fixed 8.4 m would give every Buda house."""
	return minf(2.0 * CITY_STOREY_HEIGHT, height - CITY_STOREY_HEIGHT * 0.5)


func _city_block_door(piece: Rect2, outward: Vector2, chunk_center: Vector3,
		rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	One carriage gateway on a building's street face — the piece of a Pest block
	that tells you the courtyard behind it is hollow.

	OWNER-CHUNK PLACED, NOT SLICED, and that is the difference between a POINT
	feature and a RECT one. A door is 1.5 m wide; slicing it would be pointless,
	and centring it on the SLICE rather than on the building would move it every
	time the chunk grid moved and would draw it twice on a building that straddles
	a seam. So the chunk containing the door's own anchor builds the whole thing,
	on the same half-open comparison the gate district's houses use.
	"""
	var c := piece.get_center()
	var face := c + outward * (0.5 * (absf(outward.x) * piece.size.x
			+ absf(outward.y) * piece.size.y) + CITY_DOOR_PROUD * 0.5)
	var half := chunk_size / 2.0
	var local := Vector3(face.x - chunk_center.x, 0.0, face.y - chunk_center.z)
	if not (local.x >= -half and local.x < half and local.z >= -half and local.z < half):
		return
	# Thin on the outward axis, CITY_DOOR_WIDTH across it.
	var size := Vector3(CITY_DOOR_PROUD, CITY_DOOR_HEIGHT, CITY_DOOR_WIDTH) \
			if absf(outward.x) > 0.5 \
			else Vector3(CITY_DOOR_WIDTH, CITY_DOOR_HEIGHT, CITY_DOOR_PROUD)
	create_box(local + Vector3(0.0, CITY_DOOR_HEIGHT * 0.5, 0.0), size, 0.0,
			rng, block_batch, block_body, 0.0, CITY_DOOR_WOOD, false)


func _city_block_footprints(piece: Rect2, height: float, chunk_center: Vector3,
		obstacles: Array) -> void:
	"""
	Claim one building's ground as `obstacles`, as a CHAIN OF DISCS rather than as
	one circumscribing circle.

	@param piece: the building's own rect, world XZ. The claim is made in this
	              chunk's local frame; a disc that falls outside the chunk is
	              simply never asked about.

	WHY NOT ONE DISC. `obstacles` is a list of circles, and the circle round a
	23 x 13 m building has a 13 m radius centred 6.5 m behind the facade — it
	would reach 6.5 m past the kerb into a 16 m street, and every coin on that
	avenue would be dropped by _settle_coin_y as "buried". A chain of discs one
	wing-depth apart covers the same rect and reaches only ~2.7 m into the street,
	which is inside the pavement the buildings stand on.

	climbable: FALSE, because these are 8 to 25 m tall. That is what makes a coin
	that lands on one SKIPPED rather than perched on a roof no one can reach, and
	it is the same mountain-massif convention the plateaus use.
	"""
	var r := BudapestPlan.BLOCK_WING_DEPTH * 0.5
	var along_x := piece.size.x >= piece.size.y
	var span := piece.size.x if along_x else piece.size.y
	var n := maxi(1, ceili(span / BudapestPlan.BLOCK_WING_DEPTH))
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var p := piece.position + Vector2(
				piece.size.x * (t if along_x else 0.5),
				piece.size.y * (0.5 if along_x else t))
		obstacles.append({
			"pos": Vector3(p.x - chunk_center.x, 0.0, p.y - chunk_center.z),
			# The disc that covers a wing-depth square of the wall, so the chain
			# leaves no gap between its links.
			"radius": r * sqrt(2.0),
			"top": height,
			"climbable": false,
		})


func spawn_approach_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Lay this chunk's slice of the APPROACH + AVENUE coin line: the trail that
	carries the player from the road's terminal station, through Budapest's gate,
	up the avenue to the Danube's west bank (bead godot-test1-8gw.3).

	@param chunk_pos: Chunk coordinates this body is laying coins for.
	@param parent_chunk: The chunk mesh the coins attach to (positions are stored
	                     chunk-LOCAL, exactly like the road's).
	@param obstacles: This chunk's block footprints, for the shared perch-or-skip
	                  rule in _settle_coin_y.

	WHY IT EXISTS AT ALL. _road_coins_at stops at the terminal station, and the
	terminal is ~900 m west of the Danube. Coins are the headline score since bead
	.1 retired distance, so without this line the score would sit frozen for the
	whole walk into the city — the road would read as "you have arrived nowhere".

	ZERO RNG, and that is the design and not an omission. Every coin is at a fixed
	CITY_COIN_SPACING pitch ALONG BudapestPlan.road_approach_point()'s centreline
	(BudapestPlan.approach_coin_line resamples it by arc length — a pitch stepped in
	X would open to 8 * sqrt(1 + slope^2) on a steep seed), so this line is AUTHORED
	like the rest of the city (the tower_site() ruling one scale up). There is no
	hash stream here to keep independent of the chunk's, no salt to pick and nothing
	for a determinism A/B to measure — the only run-varying input is the terminal
	station itself, which is where the road's own seed enters.

	SEAM-CORRECTNESS, the road's rule unchanged: a coin's position is fixed by its
	index in that one shared line, but it rides the corridor in BOTH axes, so a coin
	whose X is in this chunk's column can still belong to the chunk one row over.
	Every coin is therefore BUCKETED by `world_to_chunk(pos) == chunk_pos` — the
	chunk that owns it scans the same X window and picks it up, so there are no gaps
	and no duplicates. Coin identity is Coin.id_at(world) (quantized position), so
	multiplayer claims work with no mp_manager edit at all.

	Nothing here is a MeshInstance3D or a body of its own: coins are ordinary
	chunk-parented pickups that unload with the chunk, like every road coin.
	"""
	if not spawn_coins or coin_scene == null:
		return

	var line := _approach_coin_line()
	if line.is_empty():
		return

	var center := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0
	var x0 := center.x - half_chunk
	var x1 := center.x + half_chunk
	# The line is in increasing X, so a chunk column outside its span has nothing
	# to do at all — which is every chunk in the world bar the corridor's own few.
	if x1 < line[0].x or x0 > line[line.size() - 1].x:
		return

	for i in range(line.size()):
		var p: Vector2 = line[i]
		# Past this chunk's column — X only grows from here, so this is the end of
		# this chunk's work. (The west bank is where the LINE stops, not a per-coin
		# test: a chunk east of the river would answer "not wet" for every coin in
		# turn and pave the whole Pest side.)
		if p.x > x1:
			break
		if p.x < x0:
			continue

		var world := Vector3(p.x, COIN_GROUND_HEIGHT, p.y)
		# Bucket by final chunk — the seam rule, identical to the road's.
		if world_to_chunk(world) != chunk_pos:
			continue

		var local := Vector3(world.x - center.x, world.y, world.z - center.z)
		# The shared perch-or-skip rule: perch on a climbable top, drop the coin
		# where the corridor runs under something sheer (INF). The city's own
		# geometry is already in `obstacles` — spawn_city_in_chunk runs before the
		# coin spawners, like every other footprint producer.
		local.y = _settle_coin_y(local.x, local.z, local.y, obstacles)
		if is_inf(local.y):
			continue
		# ...and the corridor's own bridges, the road line's rule one spawner
		# along (bead godot-test1-06o.2): a coin standing over a deck rides it,
		# instead of being buried in the slab that crosses the water here.
		#
		# BEHIND THE SAME FLAG as the road line's lift, and for a reason the road
		# line found first: `field_bridge_surface_y` answers off the PLAN, which
		# exists whether or not the builder was allowed to run, so an ungated lift
		# stands a coin 1.6 m over open water in every configuration that turns
		# the bridges off — the A/B in field_bridge_selfcheck check 6 among them.
		if spawn_field_bridges:
			var deck_y := field_bridge_surface_y(world)
			if deck_y > -INF:
				local.y = deck_y + COIN_GROUND_HEIGHT

		var coin := coin_scene.instantiate()
		coin.position = local
		parent_chunk.add_child(coin)

func _approach_coin_line() -> PackedVector2Array:
	"""
	The approach + avenue coin line for this run: every coin centre, in increasing
	X, at a uniform CITY_COIN_SPACING pitch ALONG the corridor.

	@return: The shared, memoized line. Callers must not mutate it.

	Memoized because every chunk in the world asks for it and it is a pure function
	of the terminal station — which is fixed for the run. `_drop_seeded_memos()`
	drops it beside _road_terminal_k_cache, the one seeded input it has.

	The resampling itself lives in BudapestPlan.approach_coin_line(), with the rest
	of the corridor's arithmetic, so the coins and the clearance swath keep reading
	one geometry.
	"""
	if _approach_coin_line_cache.is_empty():
		# _road_terminal_k() has already extended the cache far enough to cover the
		# terminal — the ONE place the run's seed reaches this line.
		var terminal: Vector2 = _road_station(_road_terminal_k()).center
		_approach_coin_line_cache = BudapestPlan.approach_coin_line(
				terminal, ROAD_TERMINAL_X, _approach_coin_east_end())
	return _approach_coin_line_cache

func spawn_city_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Lay this chunk's slice of the CITY's own coin routes (bead godot-test1-8gw.9):
	the avenues of the street grid, and every bridge across the Danube.

	@param chunk_pos: Chunk coordinates this body is laying coins for.
	@param parent_chunk: The chunk mesh the coins attach to (positions are stored
	                     chunk-LOCAL, exactly like the road's).
	@param obstacles: This chunk's block footprints, for the shared perch-or-skip
	                  rule in _settle_coin_y.

	WHY IT EXISTS. Coins are the headline score since bead .1 retired distance,
	and bead .3's approach line deliberately stops at the Danube's west bank — its
	own docstring says so and calls the 1.4 km of Pest east of it "no coin source
	at all". This is that source. `in_budapest()` turns every PROCEDURAL coin off
	inside the rect, so an authored city needs an authored reward line.

	ZERO RNG, exactly like its sibling above: a fixed pitch along authored lines,
	so there is no stream here to keep independent of the chunk's, nothing for a
	determinism A/B to measure, and the same coin stands in the same metre of
	Budapest in every run and for every peer. Coin identity is Coin.id_at(world)
	(quantized position), so multiplayer claims work with NO mp_manager edit.

	THREE RULES, and each one is a thing that would otherwise be a bug:
	  1. NOT ON THE APPROACH LINE. Street row 0 IS the avenue out of the gate, and
	     bead .3's corridor already paves it as far as the west bank. Coins west
	     of `_approach_coin_east_end()` inside the carriageway are therefore
	     skipped — the two lines are one trail and must not double up.
	  2. NOT UNDER A BRIDGE. A deck rect crosses the grid at 12 m, and an avenue
	     coin under one would sit at COIN_GROUND_HEIGHT with a colliding slab over
	     it (a deck takes no `obstacles` footprint, deliberately, so _settle_coin_y
	     cannot see it — the same reasoning `_approach_coin_east_end` is built on).
	     The bridge's OWN line, at deck height, replaces it.
	  3. GEMS AT THE SQUARES. Where two GEM avenues cross is a square, and a square
	     is worth stopping at — a gem is 10 coins, so the streak the player is
	     building has somewhere to pay off.

	AND THE PITCH IS THE CITY'S OWN, NOT THE CORRIDOR'S (bead godot-test1-1qm,
	owner: "coins should be really rare in Budapest"). Both loops below step
	CITY_STREET_COIN_SPACING (64 m) where they used to step CITY_COIN_SPACING
	(8 m) — one coin per city block along an avenue, and gems on a quarter of the
	squares. The APPROACH corridor above keeps the 8 m pitch untouched: it is the
	guide out of the field and has to read as a continuous trail, which is the
	whole reason the two pitches are two constants. Entity counts moved BY DESIGN
	here, which is the one reason the performance conventions allow them to move.
	"""
	if not spawn_coins or coin_scene == null:
		return
	var centre := chunk_to_world(chunk_pos)
	var half := chunk_size / 2.0
	var square := Rect2(centre.x - half, centre.z - half, chunk_size, chunk_size)
	if not square.intersects(BudapestPlan.rect()):
		return

	# ---- THE AVENUES --------------------------------------------------------
	# Both axes, one loop each: a NORTH-SOUTH avenue is a fixed X with coins
	# stepped in Z, and an EAST-WEST one is the transpose. The step is anchored on
	# the city rect's own corner rather than on the chunk, so a coin's position is
	# a function of the CITY and every chunk that could own it agrees on where it
	# is — the road's seam rule, one authored line along.
	for axis_x in [true, false]:
		var line_lo: int = ceili((square.position.x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH) \
				if axis_x else ceili((square.position.y - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
		var line_hi: int = floori((square.end.x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH) \
				if axis_x else floori((square.end.y - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
		for i in range(line_lo, line_hi + 1):
			if not BudapestPlan.is_avenue(i):
				continue
			var fixed: float = BudapestPlan.street_x(i) if axis_x else BudapestPlan.street_z(i)
			var run_min: float = BudapestPlan.BUDAPEST_MIN.y if axis_x else BudapestPlan.BUDAPEST_MIN.x
			var lo := maxf(square.position.y if axis_x else square.position.x, run_min)
			var hi := minf(square.end.y if axis_x else square.end.x,
					BudapestPlan.BUDAPEST_MAX.y if axis_x else BudapestPlan.BUDAPEST_MAX.x)
			var j := ceili((lo - run_min) / BudapestPlan.CITY_STREET_COIN_SPACING)
			var along := run_min + float(j) * BudapestPlan.CITY_STREET_COIN_SPACING
			while along <= hi:
				var world := Vector3(fixed if axis_x else along, COIN_GROUND_HEIGHT,
						along if axis_x else fixed)
				along += BudapestPlan.CITY_STREET_COIN_SPACING
				_place_city_coin(world, chunk_pos, centre, parent_chunk, obstacles,
						_city_square_here(world.x, world.z))

	# ---- AND EVERY BRIDGE ---------------------------------------------------
	# Down the middle of each deck, at the height the deck's own profile gives —
	# BudapestPlan.bridge_surface_y, the same expression the slabs are built from,
	# so the trail climbs each ramp with the stone instead of through it.
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if not square.intersects(deck):
			continue
		var z := deck.get_center().y
		var b := ceili((maxf(square.position.x, deck.position.x) - deck.position.x)
				/ BudapestPlan.CITY_STREET_COIN_SPACING)
		var x := deck.position.x + float(b) * BudapestPlan.CITY_STREET_COIN_SPACING
		while x <= minf(square.end.x, deck.end.x):
			var world := Vector3(x, BudapestPlan.bridge_surface_y(row_v, x) + COIN_GROUND_HEIGHT, z)
			x += BudapestPlan.CITY_STREET_COIN_SPACING
			if world_to_chunk(world) != chunk_pos:
				continue
			# NO _settle_coin_y HERE, and that is deliberate: a deck coin is 12 m
			# up, and the perch rule is about what stands on the GROUND under a
			# column. Asking it would drop every coin on the Chain Bridge for the
			# pier stone at its foot.
			var gem := coin_scene.instantiate()
			gem.position = Vector3(world.x - centre.x, world.y, world.z - centre.z)
			parent_chunk.add_child(gem)


func _place_city_coin(world: Vector3, chunk_pos: Vector2i, centre: Vector3,
		parent_chunk: MeshInstance3D, obstacles: Array, gem: bool) -> void:
	"""One avenue coin, through every rule the routes' docstring lists. Bucketed
	by `world_to_chunk` like the road's, so seams are gap-free and duplicate-free."""
	if world_to_chunk(world) != chunk_pos:
		return
	# Rule 1 — the gate avenue is already paved as far as the west bank.
	if absf(world.z - BudapestPlan.GATE.z) < BudapestPlan.AVENUE_HALF_WIDTH \
			and world.x < _approach_coin_east_end():
		return
	# Rule 2 — a bridge's own line owns the crossing, at deck height.
	for row_v: Variant in BudapestPlan.BRIDGES:
		if (BudapestPlan.bridge_deck(row_v) as Rect2).has_point(Vector2(world.x, world.z)):
			return
	var local := Vector3(world.x - centre.x, world.y, world.z - centre.z)
	local.y = _settle_coin_y(local.x, local.z, local.y, obstacles)
	if is_inf(local.y):
		return
	var coin := coin_scene.instantiate()
	coin.position = local
	if gem:
		coin.make_gem()
	parent_chunk.add_child(coin)


func _city_square_here(x: float, z: float) -> bool:
	"""
	Is this coin standing at a SQUARE — the crossing of two GEM avenues? That is
	where the gems go, and it is the one place the grid's two axes have anything
	to say to each other.

	PURE GRID PARITY, and the distance test that used to be here is GONE rather
	than retuned (bead godot-test1-1qm). It asked whether the coin lay within half
	a COIN pitch of the crossing, which discriminated while that pitch was 8 m; at
	CITY_STREET_COIN_SPACING (64 m) it is wider than STREET_PITCH (62 m), so every
	coin is within half a pitch of its nearest crossing and the test answers true
	for all of them — a clause that cannot say no is worse than no clause, because
	it reads like one that can. What is left is the parity of the two NEAREST
	street lines, which is the rule the owner's "really rare" asked for: a gem at
	every fourth square instead of at every one.
	"""
	var k := roundi((x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH)
	var m := roundi((z - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
	return BudapestPlan.is_gem_avenue(k) and BudapestPlan.is_gem_avenue(m)


func _approach_coin_east_end() -> float:
	"""
	The world X the approach + avenue coin line stops at: the Danube's WEST BANK on
	the avenue's own line at z = 0, or the western abutment of the bridge standing
	on that line, whichever comes first.

	@return: The first X at or east of the gate where the avenue is in the water or
	         is climbing a bridge.

	Asked of the river's own polyline rather than written down, so bead .4 can
	reshape the Danube and this line follows with no edit here — the same "one home
	for the rule" discipline _settle_coin_y gives the coin perch.

	IT IS THE BAND, NOT danube_wet(), AND THAT DISTINCTION IS THE WHOLE FUNCTION.
	The avenue runs east along z = 0, and the Danube's z = 0 crossing is exactly
	where the CHAIN BRIDGE stands — so its deck is a DRY_RECTS row and danube_wet()
	answers false for every metre of the crossing. A line that stopped at the first
	wet metre would therefore not stop at all: it would run the full 2.2 km of the
	rect and out the other side of the city, paving the bridge and all of Pest with
	the gate's coin trail. A BANK is where the water's edge is; a dry rect is a
	thing built ON the water and has nothing to say about where the river runs.

	ponytail: the line stops at the west bank, so the 1.4 km of Pest east of the
	Danube ships with no coin source at all (in_budapest() turns every procedural
	one off inside the rect). That is this bead's authored scope — the city's own
	reward line is bead .5's — not an oversight, and it is written down here
	because a corridor that simply ends reads like one.

	Memoized for the process, and it may be: east of the gate the corridor IS the
	avenue at z = 0, so this is a pure function of BudapestPlan's authored polyline
	with no run_seed in it anywhere. new_run() has nothing to reset. The scan is
	bounded by the city rect's east edge, so a plan whose river missed z = 0
	entirely would terminate with the line simply running the width of the city
	rather than looping.
	"""
	if not is_inf(_approach_coin_east_end_cache):
		return _approach_coin_east_end_cache
	var east := BudapestPlan.BUDAPEST_MAX.x
	var x := BudapestPlan.GATE.x
	while x < east:
		if BudapestPlan.danube_distance(x, BudapestPlan.GATE.z) < BudapestPlan.DANUBE_HALF_WIDTH:
			east = x
			break
		x += BudapestPlan.CITY_COIN_SPACING

	# ...OR AT THE BRIDGE'S ABUTMENT, WHICHEVER COMES FIRST (bead .4), which is the
	# reshaping this function's third paragraph was written to absorb.
	#
	# A deck rect deliberately OVERHANGS the band so its ramps' feet land on dry
	# ground, so the Chain Bridge's western approach begins ~22 m short of the bank
	# and climbs to 12 m across those metres. Everything the corridor puts on that
	# stretch is put UNDER a colliding ramp slab: the last coins would sit at
	# COIN_GROUND_HEIGHT with several metres of stone over them (a ramp takes no
	# `obstacles` footprint, deliberately, so _settle_coin_y cannot see it), and the
	# pavement would be buried with them. The corridor the city actually offers is
	# the gate to the bridge, and then up — so both stop where the bridge starts.
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if deck.position.y <= BudapestPlan.GATE.z and deck.end.y >= BudapestPlan.GATE.z:
			east = minf(east, deck.position.x)

	_approach_coin_east_end_cache = east
	return east

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
