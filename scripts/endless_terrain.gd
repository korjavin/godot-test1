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

## Chance (0..1) that a chunk gets one "feature" structure — a wall, a corridor,
## or a Mayan step-pyramid — for variety. Kept moderate so structures show up
## often enough to be interesting but the field doesn't feel crowded.
@export var structure_chance: float = 0.5

## How many blocks long a wall / corridor is (random between min and max).
@export var wall_min_length: int = 4
@export var wall_max_length: int = 7

## Chance (0..1) that a scattered block gets extra blocks stacked on top of it,
## so the terrain occasionally has little towers instead of only single cubes.
@export var stack_chance: float = 0.25

## Maximum number of extra blocks stacked on top of a stacked block.
@export var stack_max_extra: int = 2

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

## Chance (0..1) that a given walkable structure top (pyramid apex / wall ridge)
## gets a rare crocodile patrolling it. Kept moderate so they're an occasional
## surprise, not on every structure.
@export var platform_crocodile_chance: float = 0.4

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

## Fixed seed for the boss placement RNG — its OWN independent hash stream (like
## ROAD_COIN_SEED), mixed with the boss index and run_seed as
## hash(Vector3i(i, BOSS_SEED, run_seed)). It never consumes a draw from any
## existing chunk/coin/croc RNG sequence, so adding bosses regenerates the rest
## of the procedural world byte-for-byte identically.
const BOSS_SEED: int = 0xB0_55  # "BOSS"-ish; arbitrary fixed constant

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

## Kill switch, mirrors spawn_coins / spawn_crocodiles.
@export var spawn_artifacts: bool = true

## Per-chunk chance of hosting an artifact: 0.05 ≈ one per 20 chunks, inside the
## one-per-15-to-25 target band. Rarity is also the draw-call budget (see
## ARTIFACT_MAX_ACCENTS below).
const ARTIFACT_CHANCE: float = 0.05

## Fixed salt XORed into run_seed for the artifact hash stream — same spirit as
## BOSS_SEED / ROAD_COIN_SEED: an arbitrary constant that keeps this stream
## independent of every other deterministic spawn site.
const ARTIFACT_SALT: int = 0xA27_1FA

## Candidate spots tried inside a chunk before giving up (a try is rejected when
## it lands too close to the coin road — see ARTIFACT_ROAD_CLEARANCE).
const ARTIFACT_PLACE_TRIES: int = 4

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

# ============================================================================
# SECTION 2: INTERNAL STATE
# ============================================================================

## Preloaded crocodile scene for spawning
var crocodile_scene: PackedScene

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

## Chunks within Chebyshev distance <= SYNC_RING of the player's chunk are built
## SYNCHRONOUSLY in update_chunks. This is the load-bearing safety guarantee:
## the player (walking, or teleported to spawn by new_run/restart) can only ever
## reach an adjacent chunk this frame, so ring 1 being solid means they can
## never stand over — or fall through — an unbuilt chunk while the rest of the
## world fills in progressively. 9 chunks at startup/new_run, at most 3 new
## ring chunks on a normal boundary crossing.
const SYNC_RING: int = 1

## Missing chunks awaiting progressive creation, sorted nearest-first (squared
## distance to the player's chunk). Rebuilt from scratch on every update_chunks
## call — it only runs on boundary crossings, so a full rebuild is cheap and
## simpler than incremental surgery: it dedupes for free (each position comes
## from iterating the unique-keyed chunks_to_load Dictionary once) and
## naturally drops queued chunks that fell back out of range.
var pending_chunks: Array[Vector2i] = []

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

func _spawn_artifact_accent(parent_chunk: MeshInstance3D, local_pos: Vector3, dimensions: Vector3, yaw: float, tilt: float) -> void:
	"""
	Spawns one emissive accent box (a rune strip, an eye, a missing keystone) as a
	REAL MeshInstance3D parented to the chunk (per-chunk parenting rule: it unloads
	with the chunk). Accents cannot join the block MultiMesh — that batch has one
	shared NON-emissive material — so each accent is a genuine extra draw call.
	That is exactly why artifacts are rare and capped at ARTIFACT_MAX_ACCENTS
	accents each: worst case on screen is a handful of extra unshadowed draws.
	Same Basis(UP, yaw) * Basis(RIGHT, tilt) rotation order as create_box, so an
	accent can sit flush on a tilted stone.
	"""
	var accent := MeshInstance3D.new()
	accent.mesh = _get_shared_unit_box_mesh()  # shared cube; transform carries the size
	accent.transform = Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)).scaled_local(dimensions), local_pos)
	accent.material_override = _get_artifact_glow_material()
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
	run_seed = seed_rng.randi()


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

	# Only update if player moved to a different chunk
	if player_chunk != last_player_chunk:
		update_chunks(player_chunk)
		last_player_chunk = player_chunk

	# TIME-SLICED FILL: build exactly ONE queued chunk per frame (see the
	# pending_chunks comment in SECTION 2). The queue is sorted nearest-first,
	# so the chunks the player is most likely to see next appear first, and the
	# per-frame cost is bounded by one chunk's generation instead of dozens.
	# (No already-created check needed: the queue is rebuilt from scratch on
	# every boundary crossing, and between crossings only this line creates
	# chunks, so a queued position can never already be active.)
	if not pending_chunks.is_empty():
		create_chunk(pending_chunks.pop_front())

# ============================================================================
# CHUNK MANAGEMENT FUNCTIONS
# ============================================================================

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

	# STEP 2: Remove chunks that are too far away
	var chunks_to_remove: Array[Vector2i] = []

	for chunk_pos in active_chunks.keys():
		if chunk_pos not in chunks_to_load:
			chunks_to_remove.append(chunk_pos)

	for chunk_pos in chunks_to_remove:
		remove_chunk(chunk_pos)

	# STEP 3: Create new chunks that don't exist yet — TIME-SLICED.
	#
	# Only the SAFETY RING (Chebyshev distance <= SYNC_RING around the player —
	# the chunks the player could physically reach this frame) is built right
	# now. Everything further out goes into pending_chunks, which _process
	# drains at one chunk per frame. Rebuilding the queue from scratch here is
	# deliberate: this only runs on boundary crossings, and a fresh build both
	# dedupes for free and drops any previously-queued chunk that fell out of
	# range. Generation ORDER doesn't matter for content — see the determinism
	# note above pending_chunks in SECTION 2.
	pending_chunks.clear()

	for chunk_pos in chunks_to_load:
		if chunk_pos in active_chunks:
			continue
		var cheb := maxi(absi(chunk_pos.x - player_chunk.x), absi(chunk_pos.y - player_chunk.y))
		if cheb <= SYNC_RING:
			create_chunk(chunk_pos)
		else:
			pending_chunks.append(chunk_pos)

	# Nearest-first: sort by squared distance to the player's chunk so the fill
	# grows outward from the player (the far edge, hidden by fog, comes last).
	pending_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - player_chunk).length_squared() < (b - player_chunk).length_squared())

func create_chunk(chunk_pos: Vector2i) -> void:
	"""
	Creates a new terrain chunk at the specified chunk coordinates.

	@param chunk_pos: Chunk coordinates where to create the terrain

	EDUCATIONAL NOTE:
	- We create a simple flat plane mesh procedurally
	- Each chunk is a MeshInstance3D with collision
	- In advanced games, you could add noise/procedural generation here!
	"""

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
	# in its OWN StaticBody3D, SEPARATE from the per-chunk *block* body created below.
	# The ground is a single shape created once per chunk, so folding it into the
	# block body would save exactly one node and only muddle the code — there is no
	# meaningful win. The real win is collapsing the MANY per-block bodies (one per
	# decorative cube/slab — dozens per chunk) into a single body; that's what the
	# block_body below does. Ground and blocks share the same default collision
	# layer/mask, so keeping them in two bodies is purely cosmetic, not behavioural.
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()

	box_shape.size = Vector3(chunk_size, 0.1, chunk_size)
	collision_shape.shape = box_shape

	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)

	# Add to scene and register in our dictionary
	add_child(mesh_instance)
	active_chunks[chunk_pos] = mesh_instance

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
		# Rare crocodiles that patrol an elevated platform (pyramid top / wall ridge)
		spawn_platform_crocodiles(chunk_pos, mesh_instance, platforms)
		# Rare BOSS crocodiles guarding the coin road (deterministic, station-
		# indexed — its own BOSS_SEED hash stream, no shared RNG draws consumed)
		spawn_bosses_in_chunk(chunk_pos, mesh_instance)

	# Lay this chunk's slice of the coin road (deterministic station-indexed trail;
	# coins sit at ground height, perching on a climbable block where the road
	# crosses one — see spawn_coins_in_chunk).
	if spawn_coins:
		spawn_coins_in_chunk(chunk_pos, mesh_instance, obstacles)

func spawn_objects_in_chunk(chunk_pos: Vector2i, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> Array:
	"""
	Spawns blocks within a terrain chunk: scattered cubes, the occasional little
	stack/tower, and — sometimes — a feature structure (wall / corridor / gate /
	pyramid).

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

	# Footprints of every block we place, returned so crocodiles can avoid them.
	var obstacles: Array = []

	# Occasionally build one feature structure first (wall / corridor / pyramid),
	# so scattered blocks can be placed around it (the scatter loop below checks
	# against these footprints).
	if rng.randf() < structure_chance:
		spawn_feature_structure(rng, half_chunk, obstacles, platforms, block_batch, block_body)

	# Store positions of scattered objects to check spacing between them
	var spawned_positions: Array[Vector3] = []

	# Try to spawn objects with proper spacing
	var attempts := 0
	var max_attempts := objects_per_chunk * 3  # Allow multiple attempts per object

	while spawned_positions.size() < objects_per_chunk and attempts < max_attempts:
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

		if not valid_position:
			continue

		# Base block sits on the ground.
		var size := rng.randf_range(object_size_min, object_size_max)
		create_block(Vector3(random_x, size / 2.0, random_z), size, rng.randf_range(0, TAU), rng, block_batch, block_body)
		spawned_positions.append(object_pos)

		# Track the height of the top surface (grows if we stack a tower on top).
		var top_y := size

		# Sometimes stack a few smaller blocks on top to make a little tower.
		if rng.randf() < stack_chance:
			var stack_count := rng.randi_range(1, stack_max_extra)
			for i in stack_count:
				# Each block up the stack is a bit smaller, so towers taper and
				# the random yaw doesn't make them overhang awkwardly.
				var stack_size := size * rng.randf_range(0.6, 0.85)
				create_block(Vector3(random_x, top_y + stack_size / 2.0, random_z), stack_size, rng.randf_range(0, TAU), rng, block_batch, block_body)
				top_y += stack_size

		# Record the footprint and final top height — used to keep crocodiles out
		# of the block and to perch coins on top of it. Single blocks/towers are
		# climbable (their steps are <= one jump), so coins may sit on top.
		obstacles.append({ "pos": Vector3(random_x, 0, random_z), "radius": size * 0.71, "top": top_y, "climbable": true })

	return obstacles

func spawn_feature_structure(rng: RandomNumberGenerator, half_chunk: float, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Pick and build one "feature" structure for variety: a wall, a corridor to run
	through, a gate, or a Mayan step-pyramid. Pyramids are the biggest/rarest
	landmark. Walls and pyramids also register a walkable top (platforms) that a
	patrolling crocodile can be placed on.

	@param rng: The chunk's seeded RNG (so the choice is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list each piece is appended to (crocodiles + coins)
	@param platforms: Walkable-top descriptors for patrolling crocodiles
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body, threaded down to
	                  create_box so each block's shape hangs on it (Task 5)
	"""
	var pick := rng.randf()
	if pick < 0.3:
		spawn_wall(rng, half_chunk, obstacles, platforms, block_batch, block_body)
	elif pick < 0.55:
		spawn_corridor(rng, half_chunk, obstacles, block_batch, block_body)
	elif pick < 0.75:
		spawn_gate(rng, half_chunk, obstacles, block_batch, block_body)
	else:
		spawn_pyramid(rng, half_chunk, obstacles, platforms, block_batch, block_body)

func spawn_pyramid(rng: RandomNumberGenerator, half_chunk: float, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a Mayan step-pyramid: a few square slabs stacked smallest-on-top, like a
	ziggurat. Each layer is a single flat box (cheap), not a grid of cubes.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list (one entry for the whole base, with the apex
	                  height as its top so a coin can perch on top)
	@param platforms: Gets the flat apex registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	# Pyramids vary a lot in size. Most are modest; now and then a giant one with
	# 10-15 levels towers over the field as a landmark you can climb.
	var layers: int
	var base_size: float
	if rng.randf() < 0.25:
		layers = rng.randi_range(10, 15)
		base_size = rng.randf_range(16.0, 24.0)
	else:
		layers = rng.randi_range(3, 6)
		base_size = rng.randf_range(6.0, 11.0)

	var layer_height := rng.randf_range(1.0, 1.5)
	# How much narrower each layer is than the one below it.
	var shrink := base_size / float(layers + 1)

	# Keep the whole base inside the chunk.
	var limit := half_chunk - (base_size * 0.5 + 1.0)
	if limit <= 0.0:
		return  # chunk too small for this pyramid; skip it
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	var y := 0.0
	for i in layers:
		var w := base_size - i * shrink
		create_box(Vector3(cx, y + layer_height / 2.0, cz), Vector3(w, layer_height, w), 0.0, rng, block_batch, block_body)
		y += layer_height

	# One footprint for the whole base; top = apex height. Pyramids are climbable
	# via their steps, so a coin on the apex is reachable (just a long climb).
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": base_size * 0.71, "top": y, "climbable": true })

	# Register the flat apex as a patrol platform (if it's big enough to stand on).
	var apex_w := base_size - (layers - 1) * shrink
	var apex_half := apex_w * 0.5 - 0.3
	if apex_half > 0.4:
		platforms.append({ "center": Vector3(cx, y, cz), "half": Vector2(apex_half, apex_half) })

func spawn_gate(rng: RandomNumberGenerator, half_chunk: float, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a monumental gate (Brandenburg-Tor style): two tall pillars with a thick
	lintel beam across the top, leaving an opening to walk through.

	The pillars are about as tall as a full jump, so reaching the coin that perches
	on the lintel is genuinely hard — you have to hop up onto a pillar and then up
	onto the lintel. That's intentional "hard to reach" gameplay.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list (pillars, plus a coin-perch on the lintel)
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var pillar_w := rng.randf_range(1.3, 1.8)
	# Pillars stay just under jump height (~3.6 m) so you can still hop onto one to
	# reach the lintel coin — hard, but possible.
	var pillar_h := rng.randf_range(2.7, 3.1)
	var depth := rng.randf_range(1.3, 2.0)
	var opening := rng.randf_range(3.0, 4.5)
	var lintel_h := rng.randf_range(0.9, 1.3)
	var total_w := opening + 2.0 * pillar_w  # full span across both pillars

	# Pillars are separated along X (and you walk through along Z) or vice-versa.
	var along_x := rng.randf() < 0.5

	# Conservative bound that fits the gate whichever way it's turned.
	var limit := half_chunk - (total_w * 0.5 + 1.0)
	if limit <= 0.0:
		return
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# Distance from the gate centre to each pillar's centre.
	var half_span := opening * 0.5 + pillar_w * 0.5

	for pillar_sign in 2:
		var s := -1.0 if pillar_sign == 0 else 1.0
		var px: float = cx + (s * half_span if along_x else 0.0)
		var pz: float = cz + (0.0 if along_x else s * half_span)
		# Pillar is pillar_w across the span axis and `depth` across the other.
		var pillar_dims: Vector3 = Vector3(pillar_w, pillar_h, depth) if along_x else Vector3(depth, pillar_h, pillar_w)
		create_box(Vector3(px, pillar_h * 0.5, pz), pillar_dims, 0.0, rng, block_batch, block_body)
		# Each pillar is its own footprint, so crocodiles can still pass through
		# the opening between them.
		obstacles.append({ "pos": Vector3(px, 0, pz), "radius": maxf(pillar_w, depth) * 0.71, "top": pillar_h, "climbable": true })

	# Lintel beam spanning the full width, resting on top of both pillars.
	var lintel_dims: Vector3 = Vector3(total_w, lintel_h, depth) if along_x else Vector3(depth, lintel_h, total_w)
	create_box(Vector3(cx, pillar_h + lintel_h * 0.5, cz), lintel_dims, 0.0, rng, block_batch, block_body)

	# Register the lintel centre as a (hard-to-reach but climbable) coin perch.
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": 1.0, "top": pillar_h + lintel_h, "climbable": true })

func spawn_corridor(rng: RandomNumberGenerator, half_chunk: float, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a corridor: two parallel two-block-high walls with a gap between them
	that the player can run down.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list each block is appended to
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var block_size := rng.randf_range(1.8, 2.4)
	var step := block_size * 0.98
	var length := rng.randi_range(wall_min_length + 1, wall_max_length + 1)
	# Width of the walkable gap between the two walls.
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

	# Two parallel walls, offset to either side of the centreline.
	for side_sign in 2:
		var side := -1.0 if side_sign == 0 else 1.0
		var perp := center_perp + side * gap * 0.5
		for i in length:
			var along := start + i * step
			var x := along if along_x else perp
			var z := perp if along_x else along
			# Two blocks tall so it reads as an enclosed passage. Sheer and taller
			# than a jump, so it's not climbable (no coins perch on the roof).
			create_block(Vector3(x, block_size / 2.0, z), block_size, 0.0, rng, block_batch, block_body)
			create_block(Vector3(x, block_size + block_size / 2.0, z), block_size, 0.0, rng, block_batch, block_body)
			obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": 2.0 * block_size, "climbable": false })

func spawn_wall(rng: RandomNumberGenerator, half_chunk: float, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a single wall — a straight line of touching blocks the player must run
	around — somewhere inside the chunk.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list to append each wall block to (for crocodiles)
	@param platforms: Gets the wall ridge registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
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

	for i in length:
		var along := start + i * step
		var x := along if along_x else fixed
		var z := fixed if along_x else along

		# Wall blocks are axis-aligned (yaw 0) so they sit flush against each other.
		create_block(Vector3(x, block_size / 2.0, z), block_size, 0.0, rng, block_batch, block_body)
		var top := block_size
		# A single-block section is low enough to hop onto; a doubled one is not.
		var climbable := true

		# Now and then double a section up so the wall isn't a uniform single row.
		if rng.randf() < 0.3:
			create_block(Vector3(x, block_size + block_size / 2.0, z), block_size, 0.0, rng, block_batch, block_body)
			top = 2.0 * block_size
			climbable = false

		obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": top, "climbable": climbable })

	# Register the wall ridge as a thin patrol platform (a crocodile can pace it
	# end to end). Surface is the single-block height; doubled humps just become
	# obstacles its feelers turn it back at.
	var mid_along := start + (length - 1) * step * 0.5
	var ridge_center: Vector3 = Vector3(mid_along, block_size, fixed) if along_x else Vector3(fixed, block_size, mid_along)
	var half_along := (length - 1) * step * 0.5 + block_size * 0.5 - 0.4
	var half_across := block_size * 0.5 - 0.3
	var ridge_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
	if half_along > 1.0 and half_across > 0.2:
		platforms.append({ "center": ridge_center, "half": ridge_half })

func create_block(center_pos: Vector3, size: float, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Create one cube block. Thin wrapper over create_box for the common case where
	all three dimensions are equal (scattered blocks, towers, walls, corridors).

	@param block_batch: Out-param forwarded to create_box for MultiMesh batching.
	@param block_body: The chunk's shared block-collision body, forwarded to
	                  create_box so this block's shape hangs on it (Task 5).
	"""
	create_box(center_pos, Vector3(size, size, size), yaw, rng, block_batch, block_body)

func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	"""
	Register one box for rendering AND register its physics collision shape. Used for
	cube blocks and for the flat slabs that make up pyramids.

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

		if not valid_position:
			continue

		# Instantiate the crocodile
		var crocodile_instance = crocodile_scene.instantiate()
		crocodile_instance.name = "Crocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, spawned_positions.size()]

		# Position relative to chunk
		crocodile_instance.position = crocodile_pos

		# Random initial rotation for variety
		crocodile_instance.rotation.y = rng.randf_range(0, TAU)

		# Add to chunk (so it gets removed when chunk is removed)
		parent_chunk.add_child(crocodile_instance)
		spawned_positions.append(crocodile_pos)

func spawn_platform_crocodiles(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> void:
	"""
	Place rare crocodiles that patrol an elevated structure top (a pyramid apex or
	a wall ridge). They can't jump or climb, so each is confined to its platform —
	it paces around but never walks off the edge (see set_confinement in the AI).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach the crocodiles to
	@param platforms: Walkable-top descriptors ({ "center": Vector3, "half": Vector2 })
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
		var sx := maxf(0.0, half.x - 1.0) * cos(ang)
		var sz := maxf(0.0, half.y - 1.0) * sin(ang)

		var crocodile := crocodile_scene.instantiate()
		crocodile.name = "PatrolCrocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, count]
		# Spawn just above the surface so gravity settles it onto the platform.
		crocodile.position = Vector3(center.x + sx, center.y + 0.6, center.z + sz)
		crocodile.rotation.y = rng.randf_range(0.0, TAU)
		parent_chunk.add_child(crocodile)

		# Confine it to this platform (in world space) so it can never wander off.
		if crocodile.has_method("set_confinement"):
			var center_global: Vector3 = parent_chunk.global_position + center
			crocodile.set_confinement(center_global, half)

		count += 1

func _boss_at(i: int) -> Dictionary:
	"""
	Deterministic placement + size for boss index `i` (>= 1). Pure function of
	`i` + run_seed via the independent BOSS_SEED hash stream — no shared RNG is
	touched, so the rest of the world regenerates byte-identically.

	@param i: Boss index (1-based). Owns station k = i * BOSS_INTERVAL_STATIONS.
	          ASSUMES the station cache already covers `k` (callers
	          _road_extend_to_x first, like _road_coins_at).
	@return: { "pos": Vector3 (world-space), "scale": float (body scale) }.

	EDUCATIONAL NOTE:
	- The RNG draws ONLY the lateral offset (one draw, fixed order), so boss
	  placement is stable within a run: revisiting a chunk regenerates the
	  identical boss. Across runs, run_seed changes BOTH the road and this
	  stream, so bosses land elsewhere.
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
	var lateral := rng.randf_range(-1.0, 1.0) * BOSS_LATERAL_MAX

	var p: Vector2 = st.center + tangent * BOSS_FORWARD_OFFSET + perp * lateral
	# Size schedule: boss 1 is exactly BOSS_BASE_SCALE, each successive boss is
	# BOSS_GROWTH of base bigger, capped at BOSS_MAX_SCALE (see the consts above).
	var body_scale := minf(BOSS_BASE_SCALE * (1.0 + float(i - 1) * BOSS_GROWTH), BOSS_MAX_SCALE)
	return { "pos": Vector3(p.x, 0.6, p.y), "scale": body_scale }

func spawn_bosses_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D) -> void:
	"""
	Spawn this chunk's boss crocodiles — the rare road-guarding giants placed every
	BOSS_INTERVAL_STATIONS stations along the coin road (see the BOSS CROCODILES
	config section near the top).

	Follows spawn_coins_in_chunk's seam-claim pattern exactly: extend the shared
	station cache over this chunk's padded X-window, walk the boss indices whose
	stations fall inside it, and spawn ONLY the bosses whose FINAL world position
	lands in THIS chunk (world_to_chunk(pos) == chunk_pos) — each boss is claimed
	by exactly one chunk, so there are no seam gaps or duplicates.

	@param chunk_pos: Chunk coordinates this call is generating bosses for.
	@param parent_chunk: The chunk mesh to attach bosses to. Chunk parenting is a
	                     FEATURE here: outrunning a boss far enough unloads its
	                     chunk and frees the boss with it — which reads to the
	                     player as "you escaped it".
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
		if _road_station(k).center.x > x1 + pad:
			break

		var boss: Dictionary = _boss_at(cur_i)
		var boss_pos: Vector3 = boss.pos
		# Exactly-one-chunk claim (see the docstring): only the chunk the boss
		# actually lands in spawns it.
		if world_to_chunk(boss_pos) != chunk_pos:
			continue

		var croc = crocodile_scene.instantiate()
		croc.name = "BossCrocodile_%d" % cur_i
		# Chunk-LOCAL position (relative to the chunk center), like every other
		# chunk-parented node. Default rotation — the wander AI turns it within a
		# second anyway, and drawing a rotation would add an RNG draw for nothing.
		croc.position = Vector3(boss_pos.x - center.x, boss_pos.y, boss_pos.z - center.z)
		# CALL-ORDER CONTRACT: setup_as_boss BEFORE add_child, so the croc's
		# _ready (which runs on add_child, terrain-parented) sees the boss flags
		# and skips its random speed/size rolls in favor of the schedule.
		croc.setup_as_boss(boss.scale)
		parent_chunk.add_child(croc)

func _artifact_at(chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic artifact placement for one chunk — the _boss_at of artifacts.
	Pure function of chunk coords + run_seed via the independent ARTIFACT_SALT
	hash stream: it consumes NO draw from the shared chunk RNG, so every existing
	block/crocodile/coin is exactly where it was before artifacts existed.

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when this chunk has no artifact (the ~19-in-20 case, or when every
	         candidate spot fell too close to the coin road); otherwise
	         { "local": Vector3 (chunk-LOCAL position, y = 0),
	           "kind": int (0..4, which of the five shapes),
	           "seed": int (seeds the shape builder's own private RNG) }.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL artifact (same spot, same
	  shape, same builder seed) no matter how often it unloads and regenerates —
	  the RNG is seeded purely from chunk coords + run_seed, and its draw order
	  below is fixed (chance roll, then 2 draws per placement try, then kind,
	  then builder seed).
	- Across runs, new_run() re-rolls run_seed, so artifacts land elsewhere.
	- The road-clearance test reads the station cache (pure in `k`), so it too is
	  load-order independent: rejection is a property of the POSITION, not of
	  when the chunk happened to generate.
	"""
	var rng := RandomNumberGenerator.new()
	# Same coordinate mixing as the chunk object seed, but salted so this stream
	# never collides with (or perturbs) any other deterministic spawn site.
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ ARTIFACT_SALT))

	# 1. Rarity roll — most chunks bail here.
	if rng.randf() >= ARTIFACT_CHANCE:
		return {}

	var center := chunk_to_world(chunk_pos)
	# Candidates stay ARTIFACT_EDGE_MARGIN inside the chunk so the whole artifact
	# (widest footprint < the margin) never straddles a seam.
	var half := chunk_size / 2.0 - ARTIFACT_EDGE_MARGIN

	# 2. Try a few candidate spots; accept the FIRST one far enough from the road
	# centerline. This is what produces the off-road bias AND the hard "never on
	# the centerline" rule. Acceptance stops the loop, so the draw sequence is
	# still fixed for a given outcome (2 draws per try until the accepted try),
	# and the kind/seed draws always follow in the same order.
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < ARTIFACT_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if _road_lateral_distance(center.x + local_x, center.z + local_z) >= ARTIFACT_ROAD_CLEARANCE:
			placed = true
	if not placed:
		return {}

	# 3. Which of the five shapes, and 4. a further seed for the shape builder's
	# own RNG (so builders can draw freely without this function caring how many
	# draws each shape needs).
	var kind := rng.randi_range(0, 4)
	var builder_seed := rng.randi()
	return { "local": Vector3(local_x, 0.0, local_z), "kind": kind, "seed": builder_seed }

# ============================================================================
# ARTIFACT SHAPE BUILDERS (the five code-built "lost civilization" landmarks)
# ============================================================================
#
# Every builder shares ONE signature and ONE contract:
#   _artifact_<shape>(center, rng, parent_chunk, block_batch, block_body)
#     -> { "radius": float, "top": float }
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
	return { "radius": 2.5, "top": slab_center.y + (dims.y / 2.0) * cos(tilt) }

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
	return { "radius": radius + 1.0, "top": radius + 1.0 }

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
	return { "radius": ring_r + 1.0, "top": tallest_top }

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
	return { "radius": 3.2, "top": brow_center.y + brow.y / 2.0 }

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
	return { "radius": spiral_r + 1.2, "top": rise * float(count - 1) + step_dims.y }

func spawn_artifact_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's artifact, if _artifact_at says it has one (~1 in 20), plus
	its coin reward. Called from create_chunk AFTER spawn_objects_in_chunk and
	BEFORE _build_block_multimesh / the block_body attach, so the artifact's stone
	joins the chunk's single MultiMesh and single BlockCollision body.

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — accents and reward coins parent here
	                     (per-chunk parenting rule: they unload with the chunk).
	@param obstacles: The chunk's block-footprint list; the artifact appends its
	                  own footprint so later spawners react to it (see below).
	@param block_batch / block_body: The chunk's visual batch + collision body,
	                                 threaded through to create_box.
	"""
	if not spawn_artifacts:
		return
	var art := _artifact_at(chunk_pos)
	if art.is_empty():
		return

	# The shape builder draws from its OWN RNG, seeded by _artifact_at's "seed"
	# draw — so each builder can consume as many draws as its shape needs without
	# the placement function (or anything else) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = art.seed
	var center: Vector3 = art.local

	var footprint: Dictionary
	match int(art.kind):
		0: footprint = _artifact_monolith(center, rng, parent_chunk, block_batch, block_body)
		1: footprint = _artifact_arch(center, rng, parent_chunk, block_batch, block_body)
		2: footprint = _artifact_stone_circle(center, rng, parent_chunk, block_batch, block_body)
		3: footprint = _artifact_colossus_head(center, rng, parent_chunk, block_batch, block_body)
		_: footprint = _artifact_spiral_steps(center, rng, parent_chunk, block_batch, block_body)

	# Register the artifact as one round obstacle footprint, exactly like a normal
	# block. CONSEQUENCE (deliberate): crocodiles reject spawn points inside it,
	# and any road coin whose column crosses it PERCHES on its top (climbable =
	# true) instead of being buried in the stone — artifact stone behaves like
	# ordinary block stone everywhere downstream.
	obstacles.append({ "pos": center, "radius": footprint.radius, "top": footprint.top, "climbable": true })

	# --- The reward: a ring of ordinary coins around the base + ONE gem at the
	# centre (the incentive to detour off the coin road). Guarded like every other
	# coin spawn; these are ordinary chunk-local coins parented to the chunk — the
	# road's station-claim logic is not involved in any way.
	if not spawn_coins or coin_scene == null:
		return
	var coin_count := rng.randi_range(ARTIFACT_COIN_MIN, ARTIFACT_COIN_MAX)
	var ring_radius: float = footprint.radius + rng.randf_range(ARTIFACT_COIN_RING_PAD_MIN, ARTIFACT_COIN_RING_PAD_MAX)
	var i := 0
	while i < coin_count:
		i += 1
		var a := rng.randf_range(0.0, TAU)
		var cx := center.x + cos(a) * ring_radius
		var cz := center.z + sin(a) * ring_radius
		# Same perch-or-skip rule as road coins (one home: _settle_coin_y). The
		# ring can graze the artifact's own footprint or a neighbouring block —
		# the coin perches on a climbable top, or is dropped under a sheer wall.
		var cy := _settle_coin_y(cx, cz, COIN_GROUND_HEIGHT, obstacles)
		if is_inf(cy):
			continue
		var coin := coin_scene.instantiate()
		coin.position = Vector3(cx, cy, cz)
		parent_chunk.add_child(coin)

	# Exactly one gem at the artifact centre. The artifact's own footprint is in
	# `obstacles` (climbable), so _settle_coin_y perches the gem ON TOP of the
	# shape — intended: the prize rewards a climb. make_gem() BEFORE add_child,
	# per coin.gd's contract (it fetches nodes with get_node, not @onready).
	var gem_y := _settle_coin_y(center.x, center.z, COIN_GROUND_HEIGHT, obstacles)
	if not is_inf(gem_y):
		var gem := coin_scene.instantiate()
		gem.position = Vector3(center.x, gem_y, center.z)
		gem.make_gem()
		parent_chunk.add_child(gem)

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

func _road_lateral_distance(world_x: float, world_z: float) -> float:
	"""
	Minimum distance (world metres, XZ plane) from the point (world_x, world_z)
	to any road centerline station near it. Used by artifact placement to keep
	landmarks off the coin road (see ARTIFACT_ROAD_CLEARANCE).

	@param world_x, world_z: World-space point to test.
	@return: Distance to the nearest scanned station centre, or INF when no
	         station falls in the scan window (the point is far off-road in X —
	         "very far from the road" and "no road here" both mean "clear").

	EDUCATIONAL NOTE:
	- We only need to know whether the point is WITHIN ARTIFACT_ROAD_CLEARANCE of
	  the centerline, so scanning the stations inside a padded X-window around the
	  point suffices: any station outside that window is already further away in X
	  alone than the clearance we test against. The pad adds two station spacings
	  so the sampled polyline can't cut a corner past the window edge.
	- Same manual-counter scan as spawn_coins_in_chunk — NOT `for k in range(...)`,
	  which would eagerly materialise an O(total cached suffix) int Array per call
	  just to visit a handful of stations (see the allocation note there).
	- Reads only the station cache (pure in `k`), so the answer for a given point
	  is deterministic and load-order independent.
	"""
	var pad := ARTIFACT_ROAD_CLEARANCE + _road_spacing() * 2.0
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

func new_run() -> void:
	"""
	Reset the world for a brand-new run: re-roll the per-run seed and rebuild
	everything derived from it. Called by player_controller.restart_game() (via the
	"terrain" group) BEFORE the player is teleported back to the (0,2,0) spawn.

	EDUCATIONAL NOTE — the order matters:
	1. Re-roll run_seed — every hash site mixes it in, so all downstream content
	   (blocks, crocodiles, road, coins) will come out different.
	2. Clear the road station cache — its entries were computed with the OLD seed
	   and would poison the new road (the cache is "correct forever" only while the
	   seed is constant). Reset the bounds to the empty sentinel (min > max) exactly
	   as declared, so the next _road_extend_to_x re-seeds station 0. Also clear the
	   pending-chunk queue — anything queued was computed for the old world.
	3. Free every active chunk and clear the dictionary — old-world geometry.
	4. Rebuild around the spawn chunk (0,0) via update_chunks — which builds the
	   spawn chunk + SYNC_RING ring 1 SYNCHRONOUSLY and queues the rest for
	   progressive fill. The respawned player is teleported to (0,2,0) this SAME
	   frame, so that ring-1-sync build is the load-bearing guarantee that they
	   land on solid new-world ground instead of falling through a hole. Setting
	   last_player_chunk to (0,0) keeps _process from redundantly rebuilding.
	"""
	# 1. New seed (same roll as _ready()).
	_roll_run_seed()

	# 2. Road cache back to its declared empty state, and the old-world pending
	# queue emptied (update_chunks below rebuilds it for the new world anyway;
	# clearing here just makes the invariant explicit).
	road_stations = {}
	road_k_min = 1
	road_k_max = 0
	pending_chunks.clear()

	# 3. Drop every old-world chunk (queue_free is the safe removal, as in remove_chunk).
	for chunk_pos in active_chunks.keys():
		active_chunks[chunk_pos].queue_free()
	active_chunks.clear()

	# 4. Rebuild the spawn ring synchronously (+ queue the rest) so the
	# respawning player has ground under (0,2,0) this frame.
	update_chunks(Vector2i(0, 0))
	last_player_chunk = Vector2i(0, 0)

	print("New run started (run_seed = %d)" % run_seed)

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
