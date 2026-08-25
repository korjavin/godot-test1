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

## Radius (in metres) of the crocodile-free bubble around the world origin — the
## spawn point every run and every restart begins on.
##
## Without it the FIRST run of a session gets no spawn protection at all: the
## player's own clear_nearby_crocodiles() sweep only runs on respawn/restart, so a
## fresh boot drops the player into a chunk holding ~10 crocodiles with nothing
## keeping them off (0,0) — several sit inside DETECTION_RADIUS (15) and start
## chasing on frame one, and BASE_CHASE_SPEED (5.5) beats WALK_SPEED (5.0).
## Enforced here, in world generation, rather than as another sweep: it is a pure
## function of position, so it holds identically for new_run() and needs no
## ordering dance with the player's _ready(), which runs before any chunk exists.
## Matches the player's SPAWN_SAFE_RADIUS (the post-respawn sweep radius) — the two
## are the same rule enforced from the two ends; keep them in step if either moves.
const SPAWN_SAFE_RADIUS: float = 25.0

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
##     add are at most LANDMARK_MAX_ACCENTS emissive accents and one script-free
##     marker Node3D (which has no mesh and no physics either).
##
## THE REGISTRY IS THE EXTENSION POINT. LANDMARKS below is pure data — builder
## method NAME, English name, English fact, footprint radius — so a later wave of
## places is ONE builder function, ONE registry entry and TWO CSV rows. Nothing
## else in this file, in the toast, or in the self-check has to learn about it.
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
## eight kinds appearing. That lands in the intended 1-per-40-60 band —
## deliberately rarer than the artifacts' 1-in-23, because these are destinations
## rather than scenery — so 0.15 stands as measured. Survival is camp-like
## (14%) rather than chest-like (98.5%) for the same reason a camp's is: the
## overlap test rejects almost everything for a 9.5 m circle and almost nothing
## for a 1.5 m one.
## Re-measure this pair if the radius, the clearances or the biome mix change.
const LANDMARK_CHANCE: float = 0.15

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
## LANDMARKS[i].radius must be <= this; landmark_selfcheck.gd asserts both that
## and that each declared radius is a TRUE BOUND on the stone its builder emits.
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

## The emissive-accent budget per landmark, the same rule as ARTIFACT_MAX_ACCENTS:
## an accent is a real extra MeshInstance3D and therefore a real extra DRAW CALL,
## which is the one cost that does not batch. Builders use at most ONE each, and
## only where a real light belongs (a torch, a beacon, a gilded capstone).
const LANDMARK_MAX_ACCENTS: int = 4

## Coin reward: a small ring round the base. NO GEM — see the banner above.
const LANDMARK_COIN_MIN: int = 3
const LANDMARK_COIN_MAX: int = 5
## How far outside the shape's own radius the ring sits, so the coins are found
## by walking AROUND the landmark rather than by clipping into it.
const LANDMARK_COIN_RING_PAD_MIN: float = 1.5
const LANDMARK_COIN_RING_PAD_MAX: float = 4.0

## --- Palette. Deliberately distinct from the warm RAMP_* block ramps, the
## artifacts' grey-green weathered stone and the camps' bone white, because the
## whole point of a landmark is that it does not read as scenery. Each place gets
## the colour a person would actually name it by.
const LM_STONE_GREY := Color(0.62, 0.61, 0.57)   # Stonehenge sarsen
const LM_BASALT := Color(0.34, 0.32, 0.30)       # Moai volcanic tuff
const LM_SANDSTONE := Color(0.80, 0.68, 0.44)    # Giza limestone
const LM_GRANITE := Color(0.48, 0.46, 0.47)      # plinths, pedestals, ahu
const LM_ORANGE := Color(0.75, 0.24, 0.10)       # Golden Gate International Orange
const LM_COPPER := Color(0.42, 0.71, 0.60)       # Liberty's oxidised copper
const LM_OCHRE := Color(0.72, 0.44, 0.24)        # Plaza Mayor walls
const LM_ROOF := Color(0.36, 0.20, 0.15)         # Plaza Mayor slate/tile trim
const LM_IRON := Color(0.45, 0.36, 0.28)         # Eiffel "brun tour Eiffel"
const LM_MARBLE := Color(0.93, 0.91, 0.87)       # Taj Mahal marble

## THE REGISTRY. Pure data, so it can be a `const` — and it is const precisely to
## make "add a place" a data edit rather than a code edit.
##
## `builder` is a METHOD-NAME STRING, invoked as call(entry.builder, ...). It is a
## String and not a Callable because a `const` Array cannot hold a Callable (a
## Callable binds an object at runtime, so it is not a constant expression); a
## String keeps the whole registry pure data and const-able, at the cost of the
## method name being checked at call time rather than parse time — which
## landmark_selfcheck.gd covers by calling every builder in the table.
##
## `name` and `fact` are the ENGLISH SOURCE STRINGS, not identifiers, because in
## this project THE TRANSLATION KEY IS THE ENGLISH SOURCE STRING (CLAUDE.md
## Localization RULE 1). The toast assigns them straight to a Label.text and gets
## translation AND live locale-switching for free, with no tr() call anywhere. Do
## not "fix" that by inventing HUD_LANDMARK_* keys — it would break the fallback
## that makes a place with no CSV row render as readable English.
##
## `radius` is that shape's OWN footprint radius (metres), which is what the
## reward ring and the obstacle footprint are measured from. It must be
## <= LANDMARK_RADIUS, and it must be a true bound on the stone the builder
## actually emits; landmark_selfcheck.gd measures both.
##
## ORDER IS LOAD-BEARING ONLY IN THAT IT IS THE KIND ROLL — _landmark_at draws
## randi_range(0, LANDMARKS.size() - 1) into this array, so appending is safe and
## reordering re-rolls every landmark in every existing world (harmless: worlds
## are per-run anyway).
const LANDMARKS: Array = [
	{
		"builder": "_landmark_stonehenge",
		"name": "Stonehenge",
		"fact": "A Neolithic stone circle on Salisbury Plain, England, raised around 2500 BC.",
		"radius": 7.6,
	},
	{
		"builder": "_landmark_moai",
		"name": "Moai of Easter Island",
		"fact": "Nearly 900 stone figures carved by the Rapa Nui on Easter Island, Chile, between 1250 and 1500.",
		"radius": 6.6,
	},
	{
		"builder": "_landmark_giza",
		"name": "Pyramids of Giza",
		"fact": "Three royal tombs near Cairo, Egypt, built around 2560 BC — the last surviving Wonder of the Ancient World.",
		"radius": 9.4,
	},
	{
		"builder": "_landmark_golden_gate",
		"name": "Golden Gate Bridge",
		"fact": "A 2.7 km suspension bridge over San Francisco Bay, USA, opened in 1937 and painted International Orange.",
		"radius": 9.4,
	},
	{
		"builder": "_landmark_liberty",
		"name": "Statue of Liberty",
		"fact": "A 93 m copper statue in New York Harbor, USA — a gift from France, dedicated in 1886.",
		"radius": 5.4,
	},
	{
		"builder": "_landmark_plaza_mayor",
		"name": "Plaza Mayor",
		"fact": "The arcaded central square of Madrid, Spain, completed in 1619 and ringed by 237 balconies.",
		"radius": 8.6,
	},
	{
		"builder": "_landmark_eiffel",
		"name": "Eiffel Tower",
		"fact": "A 330 m iron tower in Paris, France, built for the 1889 World's Fair and meant to stand only 20 years.",
		"radius": 6.2,
	},
	{
		"builder": "_landmark_taj",
		"name": "Taj Mahal",
		"fact": "A white marble mausoleum in Agra, India, built by Shah Jahan for his wife Mumtaz Mahal in 1653.",
		"radius": 8.6,
	},
]

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
## _biome_noise below). Thresholding its 0..1 output gives the four bands; a thin
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
enum Biome { PLAINS, DESERT, FOREST, MOUNTAIN }

## Fixed salt XORed into run_seed for every biome hash stream — same spirit as
## ARTIFACT_SALT / BOSS_SEED / ROAD_COIN_SEED: an arbitrary constant that keeps
## this stream independent of every other deterministic spawn site.
const BIOME_SALT: int = 0xB10_11E

## Noise wavelength in metres. Chunks are 50 m, so a biome cell spans ~8 chunks:
## big enough that you walk through a region rather than past it, small enough
## that a ~1 km run crosses several.
const BIOME_CELL_SIZE: float = 400.0

## Thresholds splitting the 0..1 noise into the four bands:
##   n < DESERT_MAX          -> DESERT
##   n < PLAINS_MAX          -> PLAINS   (the widest band: the current look stays
##   n < FOREST_MAX          -> FOREST    the most common thing you see)
##   otherwise               -> MOUNTAIN (the rarest — massifs are the heaviest)
const BIOME_DESERT_MAX: float = 0.34
const BIOME_PLAINS_MAX: float = 0.62
const BIOME_FOREST_MAX: float = 0.82

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
## as "do not bury this" when siting a massif. Scattered blocks top out at
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

## MOUNTAIN — grey scree ramp for the rock itself. Cooler and flatter than both
## the warm RAMP_* block colours and the artifacts' grey-green, so a massif reads
## as bare rock rather than as a very large block or a ruin.
const MOUNTAIN_ROCK_A := Color(0.42, 0.42, 0.44)
const MOUNTAIN_ROCK_B := Color(0.58, 0.57, 0.55)

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
	mat.set_shader_parameter("biome_forest_max", BIOME_FOREST_MAX)
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
		# Rare crocodiles that patrol an elevated platform (pyramid top / wall ridge)
		spawn_platform_crocodiles(chunk_pos, mesh_instance, platforms)
		# Rare BOSS crocodiles guarding the coin road (deterministic, station-
		# indexed — its own BOSS_SEED hash stream, no shared RNG draws consumed).
		# Gets `obstacles` like its siblings so a 2.5x-6x boss is never wedged
		# inside a wall/pyramid/tree/mountain right on the player's path.
		spawn_bosses_in_chunk(chunk_pos, mesh_instance, obstacles)

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

	# World-space centre of this chunk. Block positions below are chunk-LOCAL, so
	# every biome/river question (which is asked in WORLD space, because the biome
	# field is one continuous world-space field) adds this first.
	var chunk_center := chunk_to_world(chunk_pos)

	# Footprints of every block we place, returned so crocodiles can avoid them.
	var obstacles: Array = []

	# Occasionally build one feature structure first (wall / corridor / pyramid),
	# so scattered blocks can be placed around it (the scatter loop below checks
	# against these footprints).
	if rng.randf() < structure_chance:
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

func spawn_feature_structure(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Pick and build one "feature" structure for variety: a wall, a corridor to run
	through, a gate, or a Mayan step-pyramid. Pyramids are the biggest/rarest
	landmark. Walls and pyramids also register a walkable top (platforms) that a
	patrolling crocodile can be placed on.

	@param rng: The chunk's seeded RNG (so the choice is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World-space centre of the chunk, so each builder can turn
	                  its chunk-LOCAL centre into a world position for the river
	                  test (structures never stand in the water).
	@param obstacles: Footprint list each piece is appended to (crocodiles + coins)
	@param platforms: Walkable-top descriptors for patrolling crocodiles
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body, threaded down to
	                  create_box so each block's shape hangs on it (Task 5)

	EDUCATIONAL NOTE — the river rule for structures: a structure is placed as ONE
	object, so it gets ONE test, on its chosen centre, taken right after the draws
	that produced that centre. A footprint-vs-band intersection test would be more
	precise and much fiddlier for a band that winds; a centre test is enough to keep
	walls and pyramids out of the water, which is all the rule is for.
	"""
	var pick := rng.randf()
	if pick < 0.3:
		spawn_wall(rng, half_chunk, chunk_center, obstacles, platforms, block_batch, block_body)
	elif pick < 0.55:
		spawn_corridor(rng, half_chunk, chunk_center, obstacles, block_batch, block_body)
	elif pick < 0.75:
		spawn_gate(rng, half_chunk, chunk_center, obstacles, block_batch, block_body)
	else:
		spawn_pyramid(rng, half_chunk, chunk_center, obstacles, platforms, block_batch, block_body)

func spawn_pyramid(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a Mayan step-pyramid: a few square slabs stacked smallest-on-top, like a
	ziggurat. Each layer is a single flat box (cheap), not a grid of cubes.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the apex
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

	# No pyramids in the water (centre test, taken right after the centre draws).
	if is_river_at(chunk_center + Vector3(cx, 0.0, cz)):
		return

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

func spawn_gate(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a monumental gate (Brandenburg-Tor style): two tall pillars with a thick
	lintel beam across the top, leaving an opening to walk through.

	The pillars are about as tall as a full jump, so reaching the coin that perches
	on the lintel is genuinely hard — you have to hop up onto a pillar and then up
	onto the lintel. That's intentional "hard to reach" gameplay.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the gate
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

	# No gates in the water (centre test, taken right after the centre draws).
	if is_river_at(chunk_center + Vector3(cx, 0.0, cz)):
		return

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

func spawn_corridor(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a corridor: two parallel two-block-high walls with a gap between them
	that the player can run down.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  corridor's midpoint
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

	# No corridors in the water. The corridor's centre is the midpoint of its run
	# along one axis and the centreline on the other (centre test, taken right
	# after the draws that fixed both).
	var mid_along := start + span * 0.5
	var corridor_center: Vector3 = Vector3(mid_along, 0.0, center_perp) if along_x else Vector3(center_perp, 0.0, mid_along)
	if is_river_at(chunk_center + corridor_center):
		return

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

func spawn_wall(rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a single wall — a straight line of touching blocks the player must run
	around — somewhere inside the chunk.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  wall's midpoint
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

	# Midpoint of the wall's run — used both for the river test here and for the
	# patrol-platform ridge at the bottom of this function.
	var mid_along := start + (length - 1) * step * 0.5

	# No walls in the water (centre test, taken right after the draws that placed
	# the wall).
	var wall_center: Vector3 = Vector3(mid_along, 0.0, fixed) if along_x else Vector3(fixed, 0.0, mid_along)
	if is_river_at(chunk_center + wall_center):
		return

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

func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0), collide: bool = true) -> void:
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

		if not valid_position:
			continue

		# Instantiate the crocodile
		var crocodile_instance = crocodile_scene.instantiate()
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
	boss wedged into a wall/pyramid/tree/mountain sits right on the player's path.
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
		if _road_station(k).center.x > x1 + pad:
			break

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
			if clear:
				local_pos = local
				placed = true
				break
		# Not ours, or every candidate of ours was buried in geometry: no boss here.
		if not placed:
			continue

		var croc = crocodile_scene.instantiate()
		croc.name = "BossCrocodile_%d" % cur_i
		# Chunk-LOCAL position (relative to the chunk center), like every other
		# chunk-parented node. Default rotation — the wander AI turns it within a
		# second anyway, and drawing a rotation would add an RNG draw for nothing.
		croc.position = local_pos
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
	var kind := rng.randi_range(0, LANDMARKS.size() - 1)

	return { "seed": rng.randi(), "kind": kind }

# ----------------------------------------------------------------------------
# THE EIGHT BUILDERS
# ----------------------------------------------------------------------------
##
## Every builder has the identical signature
##   _landmark_x(center, rng, parent_chunk, block_batch, block_body) -> Dictionary
## and returns { "radius": float, "top": float } — no `gem_offset`, because a
## landmark deliberately pays NO GEM (see the REWARD DECISION in the constant
## banner). `center` is CHUNK-LOCAL, exactly as the artifact builders take it.
##
## Shared rules, all four of them load-bearing:
##  1. EVERY solid box goes through create_box with a color_override, so it lands
##     in the chunk's ONE MultiMesh and ONE BlockCollision body. A landmark is
##     therefore free at the draw-call level however many boxes it is made of.
##  2. `collide = false` for pure trim that sits INSIDE another box's collision
##     volume (dark recesses, thin cornices, brows, cable strands overhead). The
##     chest's brass band and the camp's fire stones are the precedent.
##  3. The returned `radius` must BOUND every box actually emitted, measured as
##     horizontal centre offset + the rotated box's horizontal half-diagonal —
##     which is exactly what landmark_selfcheck.gd measures over 25 seeds per
##     builder. Each builder's comment carries its own worst-case arithmetic, so
##     a retune can be checked by reading rather than by running.
##  4. AT MOST ONE emissive accent, and only where a real light belongs (a
##     capstone, a torch, a beacon). An accent is a genuine extra draw call, and
##     it reuses _get_camp_ember_material() — the warm one. DO NOT add a third
##     glow material; two temperatures is the whole vocabulary.
##
## The RNG is the landmark's PRIVATE stream (seeded from _landmark_at's `seed`),
## so a builder may draw as freely as its shape needs — nothing else reads it.

func _lm_shade(base: Color, rng: RandomNumberGenerator, amount: float = 0.06) -> Color:
	"""
	One stone's colour: the landmark's base palette entry nudged by up to `amount`
	in each channel. Mortared ruins and quarried blocks are never one flat colour,
	and a per-box jitter is what stops a MultiMesh of identical greys reading as a
	single extruded blob. Deliberately SMALL — a landmark has to stay recognizable,
	which means its silhouette does the work and the colour stays quiet.
	"""
	var d := rng.randf_range(-amount, amount)
	return Color(clampf(base.r + d, 0.0, 1.0), clampf(base.g + d, 0.0, 1.0), clampf(base.b + d, 0.0, 1.0))

func _landmark_stonehenge(center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 0 — STONEHENGE: an outer ring of 5 trilithons (two uprights carrying a
	lintel laid across their tops) around an inner horseshoe of 4 shorter, drunkenly
	leaning standing stones. Salisbury Plain in cubes.

	RADIUS ARITHMETIC (declared 7.6). The widest thing is a lintel: its centre sits
	on the RING_R (5.6) ring and its horizontal half-diagonal is
	0.5*sqrt(3.4^2 + 1.0^2) = 1.77, so 5.6 + 1.77 = 7.37 <= 7.6. The uprights sit
	further out along the tangent (sqrt(5.6^2 + 1.2^2) = 5.73) but are much thinner
	(half-diagonal 0.71), so 6.44. RING_R is 5.6 rather than the 6.0 a real plan
	would suggest precisely because of that lintel term.
	NO ACCENT: Stonehenge is a sundial, not a lamp.
	"""
	const RING_R := 5.6
	const TRILITHONS := 5
	const UPRIGHT := Vector3(1.0, 4.2, 1.0)
	const LINTEL := Vector3(3.4, 0.8, 1.0)
	# One shared orientation for the whole monument, so the ring reads as built
	# rather than scattered.
	var base_a := rng.randf_range(0.0, TAU)

	for i in TRILITHONS:
		var a := base_a + TAU * float(i) / float(TRILITHONS)
		# yaw = PI/2 - a points the stone's local Z (its thin depth axis) along the
		# radius, i.e. the trilithon FACES the centre and its long X axis runs along
		# the tangent — the same face-the-centre trick the artifact stone circle uses.
		var yaw := PI / 2.0 - a
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var ring_pos := center + radial * RING_R
		# The two uprights, offset along the tangent so the lintel bridges them.
		for side in [-1.0, 1.0]:
			create_box(ring_pos + tangent * (side * 1.2) + Vector3(0.0, UPRIGHT.y / 2.0, 0.0),
					UPRIGHT, yaw + rng.randf_range(-0.05, 0.05), rng, block_batch, block_body,
					0.0, _lm_shade(LM_STONE_GREY, rng))
		# The lintel laid flat across both tops — the detail that makes a trilithon
		# read as Stonehenge and not as a stone circle.
		create_box(ring_pos + Vector3(0.0, UPRIGHT.y + LINTEL.y / 2.0, 0.0),
				LINTEL, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_STONE_GREY, rng))

	# Inner horseshoe: 4 shorter bluestones over a 3/4 arc (a horseshoe, not a
	# second ring), each leaning a little — a thousand years of frost heave.
	const INNER_R := 2.8
	for i in 4:
		var a := base_a + 0.35 + (TAU * 0.75) * float(i) / 3.0
		var dims := Vector3(1.0, rng.randf_range(2.2, 2.9), 0.7)
		var lean := rng.randf_range(-0.15, 0.15)
		create_box(center + Vector3(cos(a) * INNER_R, dims.y / 2.0 - 0.15, sin(a) * INNER_R),
				dims, PI / 2.0 - a, rng, block_batch, block_body, lean, _lm_shade(LM_STONE_GREY, rng))

	return { "radius": 7.6, "top": UPRIGHT.y + LINTEL.y }

func _landmark_moai(center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 1 — MOAI OF EASTER ISLAND: five heavy figures standing shoulder to
	shoulder on a low ahu platform, ALL FACING THE SAME WAY (inland, as the real
	ones do). The row plus the shared gaze is the whole recognition cue.

	RADIUS ARITHMETIC (declared 6.6). The ahu slab is the widest box:
	0.5*sqrt(11.0^2 + 3.0^2) = 5.70. The outermost statue body sits at x = 4.4 with
	half-diagonal 0.79 => 5.19. So 5.70 <= 6.6.
	NO ACCENT.
	"""
	const AHU := Vector3(11.0, 0.7, 3.0)
	const STATUES := 5
	const SPACING := 2.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_BASALT, rng, 0.03)  # one quarry, one colour family
	create_box(center + Vector3(0.0, AHU.y / 2.0, 0.0), AHU, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))

	var tallest := AHU.y
	for i in STATUES:
		var offset := (float(i) - float(STATUES - 1) / 2.0) * SPACING
		var base := center + rot * Vector3(offset, 0.0, 0.0)
		# Each figure is carved separately, so each leans a hair differently — but
		# the wobble stays tiny, because "all facing one way" is the recognition cue.
		var wobble := rng.randf_range(-0.09, 0.09)
		var body := Vector3(1.3, rng.randf_range(2.7, 3.2), 0.9)
		create_box(base + Vector3(0.0, AHU.y + body.y / 2.0, 0.0), body, yaw + wobble, rng, block_batch, block_body, 0.0, stone)
		var head := Vector3(1.15, 1.5, 1.0)
		var head_y := AHU.y + body.y + head.y / 2.0
		create_box(base + Vector3(0.0, head_y, 0.0), head, yaw + wobble, rng, block_batch, block_body, 0.0, stone)
		# The heavy brow ridge, proud of the face — visual trim only (it sits on the
		# head's own collision volume), so collide = false.
		create_box(base + Vector3(0.0, head_y + 0.25, 0.0) + Basis(Vector3.UP, yaw + wobble) * Vector3(0.0, 0.0, head.z / 2.0 + 0.06),
				Vector3(1.2, 0.35, 0.18), yaw + wobble, rng, block_batch, block_body, 0.0,
				_lm_shade(LM_BASALT, rng, 0.02).darkened(0.25), false)
		tallest = maxf(tallest, AHU.y + body.y + head.y)

	return { "radius": 6.6, "top": tallest }

func _landmark_giza(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 2 — PYRAMIDS OF GIZA: three stepped pyramids of descending size on the
	shallow diagonal the real ones stand on, plus ONE emissive capstone on the
	Great Pyramid (the pyramidion that is missing in Cairo and present here).

	RADIUS ARITHMETIC (declared 9.4). Worst case is the SMALLEST pyramid, because
	it is the one pushed furthest out: centre offset sqrt(5.0^2 + 3.0^2) = 5.83 plus
	its base half-diagonal 0.5*sqrt(2*4.0^2) = 2.83 => 8.66. The Great Pyramid is
	2.5 out with a 4.95 half-diagonal => 7.45. So 8.66 <= 9.4.
	Sizes and offsets are FIXED rather than rolled: three pyramids in descending
	size on a diagonal IS the recognition cue, and a roll that shuffled them would
	sometimes produce three equal lumps.
	"""
	# base width, layer count, offset from the group centre — largest first.
	var plan := [
		{ "base": 7.0, "layers": 9, "off": Vector2(-2.0, -1.5) },
		{ "base": 5.5, "layers": 7, "off": Vector2(2.2, 1.0) },
		{ "base": 4.0, "layers": 5, "off": Vector2(5.0, 3.0) },
	]
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var great_top := 0.0
	for p in plan:
		var base_w: float = p.base
		var layers: int = p.layers
		var spot: Vector3 = center + rot * Vector3(p.off.x, 0.0, p.off.y)
		# Same tapering-stack recipe as spawn_pyramid, so a stepped pyramid is
		# climbable the same way theirs is.
		var layer_h: float = base_w / float(layers) * 0.62
		var shrink: float = base_w / float(layers + 1)
		var y := 0.0
		for i in layers:
			var w: float = base_w - float(i) * shrink
			create_box(spot + Vector3(0.0, y + layer_h / 2.0, 0.0), Vector3(w, layer_h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng))
			y += layer_h
		if great_top == 0.0:
			great_top = y
			# THE one accent: a gilded capstone on the Great Pyramid.
			_spawn_artifact_accent(parent_chunk, spot + Vector3(0.0, y + 0.35, 0.0),
					Vector3(0.9, 0.7, 0.9), yaw, 0.0, _get_camp_ember_material())

	return { "radius": 9.4, "top": great_top + 0.7 }

func _landmark_golden_gate(center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 3 — GOLDEN GATE BRIDGE: two International Orange towers, a deck slab
	spanning and overhanging them, and the main cable as a chain of small boxes
	sagging from tower top to tower top in a shallow catenary.

	THE DECK IS SOLID AND CLIMBABLE-LOOKING ON PURPOSE. It goes through create_box
	like every other solid, so downstream it IS ordinary block stone: the player can
	stand on it, a road coin whose column crosses the landmark footprint perches on
	it, and crocodiles treat the footprint as an obstacle. A bridge you cannot walk
	across would be a strange thing to put in a game about walking.

	RADIUS ARITHMETIC (declared 9.4). The deck is the widest box:
	0.5*sqrt(17.0^2 + 3.0^2) = 8.63. A tower leg sits at sqrt(5.5^2 + 1.2^2) = 5.63
	with half-diagonal 0.64 => 6.27. So 8.63 <= 9.4.
	NO ACCENT: the towers already carry the loudest colour in the whole palette.
	"""
	const TOWER_X := 5.5          # half the tower spacing (towers 11 m apart)
	const LEG := Vector3(0.9, 11.0, 0.9)
	const LEG_Z := 1.2            # half the spacing between a tower's two legs
	const DECK := Vector3(17.0, 0.6, 3.0)
	const DECK_Y := 5.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var orange := _lm_shade(LM_ORANGE, rng, 0.04)

	for side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			create_box(center + rot * Vector3(side * TOWER_X, LEG.y / 2.0, z_side * LEG_Z),
					LEG, yaw, rng, block_batch, block_body, 0.0, orange)
		# Two crossbeams tying each tower's legs together — the ladder look that
		# says "suspension tower" rather than "two posts".
		for beam_y in [DECK_Y + 1.4, LEG.y - 1.0]:
			create_box(center + rot * Vector3(side * TOWER_X, beam_y, 0.0),
					Vector3(0.7, 0.6, LEG_Z * 2.0 + LEG.z), yaw, rng, block_batch, block_body, 0.0, orange)

	# The deck, overhanging both towers so the span reads as part of a longer road.
	create_box(center + rot * Vector3(0.0, DECK_Y, 0.0), DECK, yaw, rng, block_batch, block_body, 0.0,
			_lm_shade(LM_ORANGE, rng, 0.04).darkened(0.2))

	# The main cable: a chain of short boxes on a parabola from tower top, dipping
	# to just above the deck at mid-span, back up to the other tower top. Two of
	# them, one per side, hung off the same LEG_Z the legs use.
	# collide = false — a 30 cm strand of cable overhead is decoration, and giving
	# it a collision shape would let the player stand on thin air at mid-span.
	const CABLE_SEGMENTS := 11
	var top_y := LEG.y
	var sag_y := DECK_Y + 0.9
	for z_side in [-1.0, 1.0]:
		for i in CABLE_SEGMENTS:
			var t := float(i) / float(CABLE_SEGMENTS - 1)   # 0..1 across the span
			var u := t * 2.0 - 1.0                          # -1..1, 0 at mid-span
			var x := u * TOWER_X
			var y: float = sag_y + (top_y - sag_y) * u * u   # parabola == shallow catenary
			create_box(center + rot * Vector3(x, y, z_side * LEG_Z), Vector3(TOWER_X * 2.0 / float(CABLE_SEGMENTS - 1) + 0.15, 0.3, 0.3),
					yaw, rng, block_batch, block_body, 0.0, orange, false)

	return { "radius": 9.4, "top": LEG.y }

func _landmark_liberty(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 4 — STATUE OF LIBERTY: a stepped pedestal, a robe tapering upward, a head
	wearing a seven-point crown, and a raised right arm carrying ONE emissive torch.
	The crown and the raised torch are the whole silhouette; everything else is
	scaffolding for them.

	RADIUS ARITHMETIC (declared 5.4). The widest box is the bottom pedestal slab,
	0.5*sqrt(2*4.6^2) = 3.25, at the centre. The arm reaches out ~1.9 with a small
	half-diagonal => under 3.0. So 3.25 <= 5.4, with room to spare for the crown
	spikes' tilt.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var granite := _lm_shade(LM_GRANITE, rng)
	var copper := _lm_shade(LM_COPPER, rng, 0.03)

	# Pedestal: three shrinking slabs (Fort Wood's star fort, flattened to steps).
	var y := 0.0
	for i in 3:
		var w := 4.6 - float(i) * 0.7
		var h := 1.2
		create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, granite)
		y += h

	# Robe: four boxes narrowing as they rise — a cone, in the house's box vocabulary.
	for i in 4:
		var w: float = 2.6 - float(i) * 0.33
		var h := 1.6
		create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w * 0.85), yaw, rng, block_batch, block_body, 0.0, copper)
		y += h

	# Head.
	var head_h := 1.1
	create_box(center + Vector3(0.0, y + head_h / 2.0, 0.0), Vector3(1.0, head_h, 1.0), yaw, rng, block_batch, block_body, 0.0, copper)
	var crown_y := y + head_h

	# The seven-point crown: spikes radiating outward and up. Trim only (they hang
	# off the head's own volume), so collide = false.
	for i in 7:
		var a := yaw + PI * (float(i) / 6.0 - 0.5)   # a half-circle fan, facing forward
		create_box(center + Vector3(cos(a) * 0.85, crown_y + 0.15, sin(a) * 0.85), Vector3(0.22, 1.0, 0.22),
				PI / 2.0 - a, rng, block_batch, block_body, -0.45, copper, false)

	# The raised arm: upper arm angled out, forearm going straight up, torch on top.
	var shoulder := center + rot * Vector3(1.0, y - 0.6, 0.0)
	create_box(shoulder + rot * Vector3(0.35, 0.8, 0.0), Vector3(0.5, 2.0, 0.5), yaw, rng, block_batch, block_body, 0.0, copper)
	var hand := shoulder + rot * Vector3(0.7, 2.6, 0.0)
	create_box(hand, Vector3(0.6, 1.6, 0.6), yaw, rng, block_batch, block_body, 0.0, copper)
	# THE one accent: the torch flame, warm — the only thing on this statue that
	# should be visible from the coin road at night.
	_spawn_artifact_accent(parent_chunk, hand + Vector3(0.0, 1.2, 0.0), Vector3(0.55, 0.8, 0.55), yaw, 0.0, _get_camp_ember_material())

	return { "radius": 5.4, "top": maxf(crown_y + 0.9, hand.y + 1.6) }

func _landmark_plaza_mayor(center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 5 — PLAZA MAYOR: a square of three-storey ochre buildings enclosing an
	open courtyard, with an arcade of pillars along the inner faces, an arched
	entrance gap in one side, and a statue plinth in the middle. The one landmark
	you go INSIDE.

	WHY EACH SIDE IS THREE SEGMENTS AND NOT ONE LONG WALL. Purely the radius bound:
	a single 11.4 m wall has a horizontal half-diagonal of 5.79, which added to its
	4.7 offset is 10.5 — over the declared 8.6, even though its actual far corner is
	only at 8.4. The bound the self-check measures is offset + half-diagonal, so
	splitting each side into three bays (half-diagonal 2.14) brings the worst case
	to sqrt(3.75^2 + 4.7^2) + 2.14 = 6.01 + 2.14 = 8.15 <= 8.6. It also happens to
	read better: three bays per side is what an arcaded square looks like.
	NO ACCENT.
	"""
	const SIDE := 11.4        # outer side of the square
	const WALL_T := 2.0       # building depth
	const BAY := 3.8          # one segment's length
	const STOREY := 2.2
	const STOREYS := 3
	var yaw := rng.randf_range(0.0, TAU)
	var wall_line := SIDE / 2.0 - WALL_T / 2.0
	var ochre := _lm_shade(LM_OCHRE, rng, 0.05)

	# Four sides; side 0 is the entrance side and skips its middle bay.
	for side_i in 4:
		var side_yaw := yaw + PI / 2.0 * float(side_i)
		var side_rot := Basis(Vector3.UP, side_yaw)
		for bay in 3:
			if side_i == 0 and bay == 1:
				continue  # the archway: left open, spanned by a lintel below
			var along := (float(bay) - 1.0) * BAY
			var foot := center + side_rot * Vector3(along, 0.0, wall_line)
			for s in STOREYS:
				create_box(foot + Vector3(0.0, STOREY * float(s) + STOREY / 2.0, 0.0),
						Vector3(BAY, STOREY, WALL_T), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(ochre, rng, 0.03))
			# Slate cornice capping the bay — trim sitting on the wall's own volume.
			create_box(foot + Vector3(0.0, STOREY * float(STOREYS) + 0.18, 0.0),
					Vector3(BAY + 0.2, 0.36, WALL_T + 0.3), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
		# The arcade: three squat pillars along this side's inner face, standing
		# proud of the wall — the colonnade you walk behind.
		for p in 3:
			var px := (float(p) - 1.0) * BAY
			create_box(center + side_rot * Vector3(px, STOREY / 2.0, wall_line - WALL_T / 2.0 - 0.35),
					Vector3(0.5, STOREY, 0.5), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.05))

	# The entrance arch: two piers either side of the missing bay plus a lintel over
	# it, so the gap reads as a doorway rather than as a demolition.
	var arch_rot := Basis(Vector3.UP, yaw)
	for s in [-1.0, 1.0]:
		create_box(center + arch_rot * Vector3(s * (BAY / 2.0 - 0.35), STOREY, wall_line),
				Vector3(0.7, STOREY * 2.0, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)
	create_box(center + arch_rot * Vector3(0.0, STOREY * 2.0 + STOREY / 2.0, wall_line),
			Vector3(BAY, STOREY, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)

	# The courtyard's centrepiece: Felipe III on his plinth, abstracted to two boxes.
	create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(1.4, 0.8, 1.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	create_box(center + Vector3(0.0, 0.8 + 0.85, 0.0), Vector3(0.55, 1.7, 0.55), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.03))

	# ponytail: the roof is a cornice band, not a pitched roof — a real one needs
	# tilted slabs whose collision would then be a ramp the player slides off. Add
	# tilted eaves if the square ever reads too flat from a distance.
	return { "radius": 8.6, "top": STOREY * float(STOREYS) + 0.36 }

func _landmark_eiffel(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 6 — EIFFEL TOWER: four legs leaning inward in two segments each (the
	curve, in two straight pieces), a broad first platform, a smaller second one, a
	tapering shaft and an antenna, with ONE emissive beacon at the top.

	WHY THE LEGS ARE TWO SEGMENTS. Partly the curve — a single straight leg reads
	as a pylon — and partly the radius bound: a tilted box contributes
	sin(tilt) * height/2 of horizontal reach, so one 7 m leg tilted 0.3 rad reaches
	further than two 3.5 m ones that each restart closer to the axis.

	RADIUS ARITHMETIC (declared 6.2). Worst case is the FIRST PLATFORM,
	0.5*sqrt(2*6.0^2) = 4.24 at the centre. A lower leg segment sits at
	sqrt(2*2.2^2) = 3.11 with a tilted horizontal half-reach under 1.5 => 4.6.
	So 4.6 <= 6.2.
	"""
	const LEG_TILT := 0.30
	const SEG := Vector3(0.85, 3.6, 0.85)
	var yaw := rng.randf_range(0.0, TAU)
	var iron := _lm_shade(LM_IRON, rng, 0.04)

	# Four legs at the corners of a square, each leaning toward the axis. The tilt
	# is applied about the leg's own local X after a yaw that points that X along
	# the tangent, so every leg leans INWARD rather than all four leaning north.
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var lower := center + Vector3(cos(a) * 2.2, SEG.y / 2.0, sin(a) * 2.2)
		create_box(lower, SEG, PI / 2.0 - a, rng, block_batch, block_body, LEG_TILT, iron)
		var upper := center + Vector3(cos(a) * 1.2, SEG.y * 1.5 - 0.1, sin(a) * 1.2)
		create_box(upper, Vector3(SEG.x * 0.85, SEG.y, SEG.z * 0.85), PI / 2.0 - a, rng, block_batch, block_body, LEG_TILT * 0.55, iron)

	# First platform — the wide one you can see people standing on from the Champ
	# de Mars, and here a genuinely reachable roof if you climb the legs.
	var p1_y := SEG.y * 2.0 - 0.2
	create_box(center + Vector3(0.0, p1_y + 0.25, 0.0), Vector3(6.0, 0.5, 6.0), yaw, rng, block_batch, block_body, 0.0, iron)
	# Second platform.
	var p2_y := p1_y + 4.0
	create_box(center + Vector3(0.0, p2_y + 0.2, 0.0), Vector3(3.6, 0.4, 3.6), yaw, rng, block_batch, block_body, 0.0, iron)

	# The shaft between and above the platforms: three boxes narrowing upward.
	var y := p1_y + 0.5
	for i in 3:
		var w: float = 2.4 - float(i) * 0.55
		var h := 3.5
		create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, iron)
		y += h

	# Antenna, and THE one accent: the aircraft beacon at the very top.
	create_box(center + Vector3(0.0, y + 1.25, 0.0), Vector3(0.3, 2.5, 0.3), yaw, rng, block_batch, block_body, 0.0, iron)
	_spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 2.7, 0.0), Vector3(0.4, 0.4, 0.4), yaw, 0.0, _get_camp_ember_material())

	return { "radius": 6.2, "top": y + 2.5 }

func _landmark_taj(center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 7 — TAJ MAHAL: a white marble plinth carrying a cubic mausoleum under a
	stacked onion dome, four corner minarets, and a dark iwan arch recessed into
	the front face. Symmetry is the recognition cue, so nothing here is jittered
	except the colour.

	RADIUS ARITHMETIC (declared 8.6). The plinth is the widest box,
	0.5*sqrt(2*11.6^2) = 8.20. A minaret stands at sqrt(2*4.6^2) = 6.51 with a
	half-diagonal of 0.57 => 7.08. So 8.20 <= 8.6.
	NO ACCENT: the marble is the brightest albedo in the palette already.
	"""
	const PLINTH := Vector3(11.6, 0.9, 11.6)
	const HALL := Vector3(6.0, 5.0, 6.0)
	const MINARET_OFF := 4.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var marble := _lm_shade(LM_MARBLE, rng, 0.02)

	create_box(center + Vector3(0.0, PLINTH.y / 2.0, 0.0), PLINTH, yaw, rng, block_batch, block_body, 0.0, marble)
	var hall_y := PLINTH.y
	create_box(center + Vector3(0.0, hall_y + HALL.y / 2.0, 0.0), HALL, yaw, rng, block_batch, block_body, 0.0, marble)

	# The iwan: a tall dark recess in the front (+Z) face. Trim only — it sits on
	# the hall's own collision volume, so collide = false keeps the wall solid.
	create_box(center + rot * Vector3(0.0, hall_y + 1.9, HALL.z / 2.0 - 0.05), Vector3(2.4, 3.4, 0.5),
			yaw, rng, block_batch, block_body, 0.0, LM_MARBLE.darkened(0.72), false)

	# The dome: three shrinking boxes plus a finial. Crude, and unmistakable.
	var y := hall_y + HALL.y
	for dims in [Vector3(3.6, 1.6, 3.6), Vector3(2.6, 1.2, 2.6), Vector3(1.6, 0.9, 1.6)]:
		create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body, 0.0, marble)
		y += dims.y
	create_box(center + Vector3(0.0, y + 0.6, 0.0), Vector3(0.35, 1.2, 0.35), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))

	# Four minarets, one per plinth corner, each with a small cap.
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var spot := center + Vector3(cos(a) * MINARET_OFF * sqrt(2.0), 0.0, sin(a) * MINARET_OFF * sqrt(2.0))
		create_box(spot + Vector3(0.0, PLINTH.y + 4.0, 0.0), Vector3(0.8, 8.0, 0.8), yaw, rng, block_batch, block_body, 0.0, marble)
		create_box(spot + Vector3(0.0, PLINTH.y + 8.35, 0.0), Vector3(1.1, 0.7, 1.1), yaw, rng, block_batch, block_body, 0.0, marble)

	return { "radius": 8.6, "top": y + 1.2 }


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

	# --- Build it. The registry is pure data, so the dispatch is one call() on a
	# method-name String and adding a ninth famous place touches no code here at
	# all. `builder` being a String rather than a Callable is what lets LANDMARKS be
	# a `const`; the cost is that a typo'd method name is caught at call time, which
	# is why landmark_selfcheck.gd calls every builder in the table.
	var entry: Dictionary = LANDMARKS[lm.kind]
	var footprint: Dictionary = call(entry.builder, center, rng, parent_chunk, block_batch, block_body)

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
	# The three metas are the whole contract with the toast: the English name and
	# fact (which ARE the translation keys — CLAUDE.md Localization RULE 1) and the
	# shape's real radius, so the toast can measure "within ~15 m of the STONE"
	# rather than "within 15 m of a point" and a small statue and a wide plaza both
	# trigger where they look like they should.
	var marker := Node3D.new()
	marker.name = "LandmarkMarker"
	marker.position = center
	marker.add_to_group("landmark")
	marker.set_meta("name_key", entry.name)
	marker.set_meta("fact_key", entry.fact)
	marker.set_meta("radius", footprint.radius)
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
	@return: true when the spot is NOT in a river, is at least `road_clearance`
	         from the road centerline, and overlaps nothing already placed.

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
	var avoid: Array = []
	for ob in obstacles:
		if ob.radius >= MOUNTAIN_AVOID_RADIUS or ob.top >= MOUNTAIN_AVOID_TOP:
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

# ============================================================================
# BIOME FIELD (one noise field; four biomes + rivers read out of it)
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
	Classify a world position into one of the four biomes.

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
	if n < BIOME_FOREST_MAX:
		return Biome.FOREST
	return Biome.MOUNTAIN


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
	build in step 4 lands under ITS feet in the same frame — exactly the guarantee
	the spawn-chunk build gives a restart, just centred somewhere else.

	EDUCATIONAL NOTE — the order matters:
	1. Set run_seed — re-rolled at random, or taken from forced_seed. Every hash
	   site mixes it in, so all downstream content (blocks, crocodiles, road,
	   coins) comes out of that one number.
	2. Clear the road station cache — its entries were computed with the OLD seed
	   and would poison the new road (the cache is "correct forever" only while the
	   seed is constant). Reset the bounds to the empty sentinel (min > max) exactly
	   as declared, so the next _road_extend_to_x re-seeds station 0. Also clear the
	   pending-chunk queue — anything queued was computed for the old world.
	3. Free every active chunk and clear the dictionary — old-world geometry.
	4. Rebuild around chunk `around` (the spawn chunk (0,0) unless a caller says
	   otherwise) via update_chunks — which builds that chunk + SYNC_RING ring 1
	   SYNCHRONOUSLY and queues the rest for progressive fill. The respawned player
	   is teleported into that chunk this SAME frame, so that ring-1-sync build is
	   the load-bearing guarantee that they land on solid new-world ground instead
	   of falling through a hole. Setting last_player_chunk to `around` keeps
	   _process from redundantly rebuilding.
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

	# 4. Rebuild the ring around `around` synchronously (+ queue the rest) so the
	# player teleported into that chunk has ground under them this frame.
	update_chunks(around)
	last_player_chunk = around

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
