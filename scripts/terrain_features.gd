class_name TerrainFeatures
extends RefCounted
## THE PRIVATE-STREAM FEATURES — lost-civilization ARTIFACTS, nomad CAMPS and
## treasure CHESTS, lifted whole out of endless_terrain.gd by bead
## godot-test1-ftn.4. `terrain_props.gd` and `terrain_structures.gd`'s sibling.
##
## WHAT MAKES THESE ONE FAMILY, and it is the thing the epic named them for:
## each is placed on its OWN hash stream — its own salt, its own coordinate
## primes, its own `_x_at(chunk_pos)` rarity function — so none of them draws
## from the shared chunk object RNG at all. That is why all three could move
## together and why the A/B is a stronger statement here than usual: a family
## that consumes no shared draw cannot move anything else even if it tried.
## Each salt and each prime pair moved WITH the code that uses it, per the epic.
##
## MECHANICAL MOVE. Every function below is byte-identical to the one it replaced
## apart from the rewrites the move forces — a leading `terrain: Node3D`, the
## terrain's own calls and fields reached through it, and the sibling `_x_at` /
## builder calls passing `terrain` on.
##
## STATIC, and `terrain` is typed `Node3D`, for landmark_builders.gd's reason:
## endless_terrain.gd declares no `class_name`.
##
## WHAT STAYED, and why: `_spawn_artifact_accent` and `_get_camp_ember_material`
## are on the terrain still. They are NODE work (a MeshInstance3D parented to the
## chunk; a process-wide lazy material singleton), not placement, and
## `landmark_builders.gd` already calls both through the terrain reference — so
## moving them would have broken a documented contract to buy nothing.

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
## (The `spawn_artifacts` @export stays on endless_terrain.gd — an `@export` is
## inspector-facing world-engine config, and a static library has no inspector.)

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
## (ChunkBatch's RAMP_SANDSTONE_* / RAMP_SLATE_* / RAMP_MOSS_*): neutral greys
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

## Coin reward: 2-4 ordinary coins ring the artifact's base (ring radius =
## footprint radius + a pad in [PAD_MIN, PAD_MAX]) plus exactly one gem at the
## centre — the incentive to detour off the coin road.
##
## 3-5 -> 2-4 with every other reward pair, bead godot-test1-7ed (owner, 2026-09-02:
## "scale down amount of coins, 30% less"). The GEM is untouched: it is the
## artifact's whole distinction, and one is already the minimum a thing can pay.
const ARTIFACT_COIN_MIN: int = 2
const ARTIFACT_COIN_MAX: int = 4
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
## (The `spawn_camps` @export stays on endless_terrain.gd — an `@export` is
## inspector-facing world-engine config, and a static library has no inspector.)

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
## (9.0 m) across it. Both legs must appear in the bound, or the invariant is
## checked against a number 8 m smaller than the real one:
##     CAMP_ROAD_CLEARANCE > CAMP_RADIUS + sqrt(BOSS_FORWARD_OFFSET^2 + BOSS_LATERAL_MAX^2)
##     22.0                > 9.4         + sqrt(8.0^2 + 9.0^2) = 9.4 + 12.04 = 21.44  ✓
## i.e. 0.56 m of slack — it was 3.66 before bead godot-test1-9k7 widened the
## lateral band from 4.0 to 9.0 to find spots for a 9x boss. (The landmark's
## copy of this inequality is tighter still, 0.46 m, and is the one that binds.)
## (The real
## clearance is larger still — stations are only _road_spacing() 6 m apart, so
## the boss is in practice closer to its NEAREST station centre than the
## hypotenuse says — but the hypotenuse is the bound that holds without assuming anything
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

## How much taller than its tier a hut's DOME is drawn (bead godot-test1-y1o.5).
## A tier is a `BoxKind.SPHERE` whose TOP is pinned at the tier's own top, so the
## silhouette height, the stack arithmetic and the footprint's `top` are all
## exactly what the box stack recorded — the stretch only sinks the sphere's
## lower half INTO the tier below, which is what closes the waist two ellipsoids
## resting apex-to-nadir would otherwise show.
##
## 1.6 IS A CEILING AND NOT A TASTE KNOB: `ChunkBatch.collision_shape_for` turns a
## near-round SPHERE into a `SphereShape3D`, and the GROUND tier must keep its
## box or the hut becomes a 0.8 m bump you walk over. At the narrowest hut
## (CAMP_HUT_WIDTH_MIN 2.6 on a 0.9 tier) the stretched dims are (2.6, 1.44, 2.6)
## and 1.44 * ROUND_COLLIDER_MAX_ASPECT = 2.30 < 2.6, so the ground tier is a box
## for every hut in the world. The tiers ABOVE it are rounder than that and DO
## take sphere colliders — deliberately: they sit on a solid base, so what they
## change is the shape you brush past at head height, not whether a hut is solid.
const CAMP_HUT_DOME_STRETCH: float = 1.6
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
## 2-4 -> 1-3, the 30% reward trim of bead godot-test1-7ed.
const CAMP_COIN_MIN: int = 1
const CAMP_COIN_MAX: int = 3

# ----------------------------------------------------------------------------
# TREASURE CHESTS (small, common, opened on touch for a coin shower)
# ----------------------------------------------------------------------------
##
## The third landmark in the artifact / camp family, and deliberately the SMALLEST
## and COMMONEST of the three — a snack, not a monument. The reward hierarchy is
## the whole reason each exists at its own rarity:
##
##   artifact  ~1 chunk in 23  huge ruin, 2-4 coins AND the one guaranteed GEM
##   camp      ~1 chunk in 31  a whole village, 1-3 coins, no gem
##   chest     ~1 chunk in 13  a 1.3 m box, 6-11 coins in a burst, NO GEM
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
## (The `spawn_chests` @export stays on endless_terrain.gd — an `@export` is
## inspector-facing world-engine config, and a static library has no inspector.)

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
## 8-15 -> 6-11, the 30% reward trim of bead godot-test1-7ed.
const CHEST_COINS_MIN: int = 6
const CHEST_COINS_MAX: int = 11
## Comfortably inside the player's STREAK_WINDOW (2.5 s), so the whole burst is
## one unbroken streak chain.
const CHEST_BURST_DURATION: float = 0.8

## The chest's one non-batched node.
const TREASURE_CHEST_SCRIPT := preload("res://scripts/treasure_chest.gd")

static func _artifact_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic artifact placement for one chunk — the _boss_at of artifacts.
	Pure function of chunk coords + terrain.run_seed via the independent ARTIFACT_SALT
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
	  is seeded purely from chunk coords + terrain.run_seed, and every draw downstream
	  comes off that one seeded stream in a fixed order.
	- Across runs, new_run() re-rolls terrain.run_seed, so artifacts land elsewhere.
	- The road-clearance test reads the station cache (pure in `k`), the river test
	  reads the biome field (pure in world position + terrain.run_seed), and the overlap
	  test reads the chunk's own obstacle list (pure in chunk coords + terrain.run_seed) —
	  so all three are load-order independent: rejection is a property of the
	  POSITION, not of when the chunk happened to generate.
	"""
	var rng := RandomNumberGenerator.new()
	# Same coordinate mixing as the chunk object seed, but salted so this stream
	# never collides with (or perturbs) any other deterministic spawn site.
	rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, terrain.run_seed ^ ARTIFACT_SALT))

	# Rarity roll — most chunks bail here. This is the ONLY draw taken from the
	# stream at this point; the rest happen in spawn_artifact_in_chunk off an RNG
	# re-seeded from `seed`, so the two stay a single fixed sequence per chunk.
	# Scarcity thins to plain terrain at 4 km: compare against chance * k (post-draw, no new draw).
	var k_art: float = terrain.scarcity_at(terrain.chunk_to_world(chunk_pos))
	if rng.randf() >= ARTIFACT_CHANCE * k_art:
		return {}

	return { "seed": rng.randi() }

# ============================================================================
# ARTIFACT SHAPE BUILDERS (the five code-built "lost civilization" landmarks)
# ============================================================================
#
# Every builder shares ONE signature and ONE contract:
#   _artifact_<shape>(center, rng, parent_chunk, block_batch, block_body)
#     -> { "radius": float, "top": float, "gem_offset": Vector3 }
# - ALL solid stone goes through create_box(..., tilt, _artifact_stone_color(terrain, rng)),
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

static func _artifact_stone_color(terrain: Node3D, rng: RandomNumberGenerator) -> Color:
	"""
	One weathered stone colour: a random spot on the ARTIFACT_STONE_A → B grey
	ramp, then pushed a random amount (up to ARTIFACT_MOSS_MAX) toward dead-moss
	green. Every stone comes out a slightly different grey-green — deliberately
	DISTINCT from the warm/blue curated RAMP_* block colours, so an artifact reads
	as "from another age" at a glance.
	"""
	var grey := ARTIFACT_STONE_A.lerp(ARTIFACT_STONE_B, rng.randf())
	return grey.lerp(ARTIFACT_MOSS, rng.randf() * ARTIFACT_MOSS_MAX)

static func _artifact_monolith(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
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
	terrain.create_box(slab_center, dims, yaw, rng, block_batch, block_body, tilt, _artifact_stone_color(terrain, rng))
	# Three rune strips up the slab's front (+Z) face. Positions are rotated by
	# the SAME yaw*tilt basis as the slab, then pushed just past the face along
	# its normal so each strip sits proud of the stone instead of z-fighting it.
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	for i in 3:
		var local_offset := Vector3(0.0, 0.6 + 1.5 * float(i), dims.z / 2.0 + 0.06)
		terrain._spawn_artifact_accent(parent_chunk, slab_center + rot * local_offset, Vector3(1.1, 0.35, 0.08), yaw, tilt)
	# Horizontal reach ≈ half width + the lean's horizontal throw; 2.5 covers it.
	# gem_offset: the centre column is solid slab, so the prize sits just off the
	# runed face where the player can actually reach it (rotated by the slab yaw).
	return {
		"radius": 2.5,
		"top": slab_center.y + (dims.y / 2.0) * cos(tilt),
		"gem_offset": Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, dims.z / 2.0 + 1.2),
	}

static func _artifact_arch(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
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
		terrain.create_box(pos, dims, yaw + rng.randf_range(-0.15, 0.15), rng, block_batch, block_body, rng.randf_range(-0.2, 0.2), _artifact_stone_color(terrain, rng))
		i += 1
	# The missing keystone: one accent floating at the gap's mid-angle.
	var a_mid := PI * (float(gap_start) + float(gap_len - 1) / 2.0) / float(count - 1)
	terrain._spawn_artifact_accent(parent_chunk, center + rot_arch * Vector3(cos(a_mid) * radius, sin(a_mid) * radius, 0.0), Vector3(0.7, 0.7, 0.7), yaw, 0.0)
	# Hollow centre — the gem sits on the ground under the arch (offset ZERO).
	return { "radius": radius + 1.0, "top": radius + 1.0, "gem_offset": Vector3.ZERO }

static func _artifact_stone_circle(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
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
	terrain.create_box(center + Vector3(0.0, slab_dims.y / 2.0, 0.0), slab_dims, base_yaw, rng, block_batch, block_body, 0.0, _artifact_stone_color(terrain, rng))
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
		terrain.create_box(pos, stone_dims, stone_yaw, rng, block_batch, block_body, lean, _artifact_stone_color(terrain, rng))
		tallest_top = maxf(tallest_top, pos.y + (stone_dims.y / 2.0) * cos(lean))
		i += 1
	# One wide, nearly-flat glow panel on the centre slab's top face.
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, slab_dims.y + 0.05, 0.0), Vector3(2.0, 0.08, 2.0), base_yaw, 0.0)
	# Offset ZERO: the gem sits dead centre, hovering just over the glowing altar
	# slab (COIN_GROUND_HEIGHT 0.9 clears its 0.6 top) — the obvious prize spot.
	return { "radius": ring_r + 1.0, "top": tallest_top, "gem_offset": Vector3.ZERO }

static func _artifact_colossus_head(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Shape 3 — HALF-BURIED COLOSSUS HEAD: a huge jaw box sunk into the ground, a
	narrower brow box stacked on top, a slab nose on the front face, all sharing
	one yaw so they read as a single fallen statue; two glowing eyes inset under
	the brow. Ozymandias, in cubes.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _artifact_stone_color(terrain, rng)  # ONE colour for the whole head — it is one statue, not a pile
	var jaw := Vector3(3.6, 2.4, 3.0)
	var jaw_center := center + Vector3(0.0, jaw.y / 2.0 - rng.randf_range(0.8, 1.4), 0.0)
	terrain.create_box(jaw_center, jaw, yaw, rng, block_batch, block_body, 0.0, stone)
	# Brow: narrower, pushed slightly back so the face has a step.
	var brow := Vector3(3.2, 1.4, 2.4)
	var brow_center := jaw_center + rot * Vector3(0.0, jaw.y / 2.0 + brow.y / 2.0, -0.3)
	terrain.create_box(brow_center, brow, yaw, rng, block_batch, block_body, 0.0, stone)
	# Nose: a thin slab proud of the jaw's front (+Z) face, reaching up to the brow.
	var nose := Vector3(0.8, 1.7, 0.6)
	terrain.create_box(jaw_center + rot * Vector3(0.0, jaw.y / 2.0 + 0.2, jaw.z / 2.0 - 0.1), nose, yaw, rng, block_batch, block_body, 0.0, stone)
	# Two eyes, inset just under the brow's front face, either side of the nose.
	for side in [-1.0, 1.0]:
		var eye_pos := brow_center + rot * Vector3(side * 0.9, -brow.y / 2.0 - 0.15, brow.z / 2.0 + 0.05)
		terrain._spawn_artifact_accent(parent_chunk, eye_pos, Vector3(0.5, 0.3, 0.12), yaw, 0.0)
	# gem_offset: the centre column is solid head, so the prize lies on the ground
	# in front of the face — under its gaze, and reachable.
	return {
		"radius": 3.2,
		"top": brow_center.y + brow.y / 2.0,
		"gem_offset": rot * Vector3(0.0, 0.0, jaw.z / 2.0 + 1.2),
	}

static func _artifact_spiral_steps(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
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
		terrain.create_box(pos, step_dims, last_yaw, rng, block_batch, block_body, 0.0, _artifact_stone_color(terrain, rng))
		last_pos = pos
		i += 1
	# The non-destination: one small glow hovering above the top step.
	terrain._spawn_artifact_accent(parent_chunk, last_pos + Vector3(0.0, 0.6, 0.0), Vector3(0.5, 0.5, 0.5), last_yaw, 0.0)
	# The helix winds AROUND an empty core, so the gem sits on the ground at the
	# centre of the spiral (offset ZERO) — you walk into the eye of the staircase.
	return { "radius": spiral_r + 1.2, "top": rise * float(count - 1) + step_dims.y, "gem_offset": Vector3.ZERO }

static func spawn_artifact_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	# BUDAPEST — no lost-civilization artifacts in the city (DEC-9): the rect's
	# monuments are its 22 authored landmark slots, and a procedural monolith
	# beside the Parliament reads as a bug. NOT tower_excludes(): that disc is one
	# answer for everything, and the city's answer differs per system.
	var art_center = terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(art_center.x, art_center.z):
		return
	if not terrain.spawn_artifacts:
		return
	var art := _artifact_at(terrain, chunk_pos)
	if art.is_empty():
		return

	# Everything below draws from ONE private RNG seeded by _artifact_at's roll, so
	# each builder can consume as many draws as its shape needs without any other
	# stream caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = art.seed

	var chunk_center = terrain.chunk_to_world(chunk_pos)
	# Candidates stay ARTIFACT_EDGE_MARGIN (12) inside the chunk so the whole
	# artifact (widest footprint ARTIFACT_RADIUS 7.0 < the margin) never straddles
	# a seam.
	var half = terrain.chunk_size / 2.0 - ARTIFACT_EDGE_MARGIN

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
		if terrain._biome_spot_ok(chunk_center, local_x, local_z, ARTIFACT_RADIUS, ARTIFACT_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	# Which of the five shapes.
	var kind := rng.randi_range(0, 4)
	var center := Vector3(local_x, 0.0, local_z)

	var footprint: Dictionary
	match kind:
		0: footprint = _artifact_monolith(terrain, center, rng, parent_chunk, block_batch, block_body)
		1: footprint = _artifact_arch(terrain, center, rng, parent_chunk, block_batch, block_body)
		2: footprint = _artifact_stone_circle(terrain, center, rng, parent_chunk, block_batch, block_body)
		3: footprint = _artifact_colossus_head(terrain, center, rng, parent_chunk, block_batch, block_body)
		_: footprint = _artifact_spiral_steps(terrain, center, rng, parent_chunk, block_batch, block_body)

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
	if terrain.spawn_coins and terrain.coin_scene != null:
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
			var cy = terrain._settle_coin_y(cx, cz, terrain.COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin = terrain.coin_scene.instantiate()
			coin.position = Vector3(cx, cy, cz)
			parent_chunk.add_child(coin)

		# Exactly ONE gem, at the artifact's centre — offset by the shape's own
		# `gem_offset` for the two shapes whose centre is solid stone (monolith,
		# colossus head), so the prize sits at the foot of the landmark instead of
		# inside it. Hollow shapes return ZERO and keep the gem dead centre.
		# make_gem() BEFORE add_child, per coin.gd's contract (it fetches nodes
		# with get_node, not @onready).
		var gem_pos: Vector3 = center + footprint.gem_offset
		var gem_y = terrain._settle_coin_y(gem_pos.x, gem_pos.z, terrain.COIN_GROUND_HEIGHT, obstacles)
		if not is_inf(gem_y):
			var gem = terrain.coin_scene.instantiate()
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

static func _camp_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic nomad-camp placement for one chunk — _artifact_at for camps,
	line for line. Pure function of chunk coords + terrain.run_seed via the independent
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
	  and regenerates — the RNG is seeded purely from chunk coords + terrain.run_seed, and
	  its draw order is fixed (chance roll, then the builder seed).
	- ACROSS RUNS new_run() re-rolls terrain.run_seed, so camps land elsewhere.
	- The placement tests downstream read the station cache (pure in `k`), the
	  biome field (pure in world position + terrain.run_seed) and the chunk's own
	  obstacles (rebuilt identically from the chunk RNG), so all three are
	  load-order independent: a rejection is a property of the POSITION and the
	  CHUNK, not of when the chunk happened to generate.
	"""
	var rng := RandomNumberGenerator.new()
	# DIFFERENT coordinate primes from the artifact stream (73856093 / 19349663)
	# and the biome stream (83492791 / 15485863), so camp placement can never
	# correlate with either — a chunk that hosts an artifact is not thereby more
	# (or less) likely to host a camp.
	rng.seed = hash(Vector3i(chunk_pos.x * 40960001, chunk_pos.y * 26463089, terrain.run_seed ^ CAMP_SALT))

	# 1. Rarity roll — the overwhelming majority of chunks bail here.
	# Scarcity thins camps logarithmically to plain terrain at 4 km.
	var k = terrain.scarcity_at(terrain.chunk_to_world(chunk_pos))
	if rng.randf() >= CAMP_CHANCE * k:
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

static func _camp_hut(terrain: Node3D, center: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Build ONE dome hut: 2-3 stacked DOME tiers, widest on the ground and each one
	narrower than the tier below. The top tier is also SHORTER (its height takes
	the same CAMP_HUT_TIER_SHRINK factor), so the silhouette caps off rather than
	ending in a flat chimney. Each tier gets its own small yaw wobble, so no two
	huts look stamped from the same mould.

	SINCE BEAD godot-test1-y1o.5 A TIER IS A `BoxKind.SPHERE`, not a box, and the
	hut is finally the dome its own docstring always claimed — a stack of narrowing
	cubes was the thing this epic exists to remove. Each sphere's TOP is pinned at
	the tier's own top and its lower half is sunk into the tier below by
	CAMP_HUT_DOME_STRETCH (see that constant for the sink, the waist it closes and
	the collider ceiling it is set by), so `y`, the stack arithmetic and the
	returned `top` are all byte-for-byte what the box stack recorded. The DOORWAY
	stays a CUBE: it is a rectangular opening, and rounding it would only make it
	stop reading as a door.

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
		# The dome: as tall as CAMP_HUT_DOME_STRETCH says, with its TOP on the
		# tier's own top (hence the half-height subtracted from `y + tier_height`
		# rather than added to `y`), so only the sunk half moves.
		var dome_h := tier_height * CAMP_HUT_DOME_STRETCH
		terrain.create_box(center + Vector3(0.0, y + tier_height - dome_h * 0.5, 0.0), Vector3(width, dome_h, width), tier_yaw, rng, block_batch, block_body, 0.0, shell, true, ChunkBatch.BoxKind.SPHERE)
		y += tier_height
		width *= CAMP_HUT_TIER_SHRINK
		i += 1

	# The doorway: one small dark box set into the fire-facing (+Z) wall. Half of it
	# sits inside the shell, so it reads as an opening rather than a porch.
	# collide = false — it is a 0.5 m thick decoration flush with a wall that
	# already collides, so a shape here would only add cost.
	var door_offset := Basis(Vector3.UP, yaw) * Vector3(0.0, CAMP_HUT_DOOR_SIZE.y / 2.0, base_width / 2.0)
	terrain.create_box(center + door_offset, CAMP_HUT_DOOR_SIZE, yaw, rng, block_batch, block_body, 0.0, CAMP_STONE, false)

	# Radius is the half-DIAGONAL of the widest tier (tiers are yawed, so the
	# half-width would under-cover a corner), plus a little for the doorway.
	return { "radius": base_width * 0.71 + 0.3, "top": y }

static func _camp_fire_pit(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> void:
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
		terrain.create_box(pos, CAMP_FIRE_STONE_SIZE, rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_STONE, false)
		i += 1

	# The one ember. Sits just clear of the ground so it never z-fights the plane.
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, CAMP_EMBER_SIZE.y / 2.0 + 0.05, 0.0), CAMP_EMBER_SIZE, rng.randf_range(0.0, TAU), 0.0, terrain._get_camp_ember_material())

static func _camp_props(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, huts: Array) -> void:
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
	it was a merged blob the terrain.player walked into.

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
		if not _camp_spot_clear(terrain, pos, crate_radius, solids):
			continue
		terrain.create_box(pos, Vector3(s, s, s), rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_WOOD)
		solids.append({ "pos": pos, "radius": crate_radius })

	var posts := rng.randi_range(CAMP_POST_MIN, CAMP_POST_MAX)
	i = 0
	while i < posts:
		i += 1
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(CAMP_PROP_RING_MIN, CAMP_PROP_RING_MAX)
		var pos := center + Vector3(cos(a) * r, CAMP_POST_SIZE.y / 2.0, sin(a) * r)
		var post_radius := CAMP_POST_SIZE.x * 0.71
		if not _camp_spot_clear(terrain, pos, post_radius, solids):
			continue
		terrain.create_box(pos, CAMP_POST_SIZE, rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, CAMP_WOOD)
		solids.append({ "pos": pos, "radius": post_radius })

static func _camp_spot_clear(terrain: Node3D, pos: Vector3, radius: float, solids: Array) -> bool:
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
	  wall, and props collide, so the terrain.player bumped geometry they could not see.
	- HUTS vs each other: the ring radius is drawn PER HUT over a 2.5 m range and
	  the angle is jittered, so evenly-spaced slots are no guarantee. At
	  CAMP_HUT_MAX (6) the nominal step is TAU/6 = 1.047 rad and the ±0.25 jitter
	  can shrink an adjacent gap to 0.547 rad; two huts both at CAMP_HUT_RING_MIN
	  are then 2 * 4.0 * sin(0.547/2) = 2.16 m apart while their radii sum to at
	  least 4.29 m. Measured over 163 camps with the roll forced to 1.0 BEFORE this
	  test existed: 38% of camps had a pair of fused, interpenetrating domes — 35 of
	  36 six-hut camps and half of the five-hut ones. Both huts collide, so that was
	  a merged, unreadable blob the terrain.player walked into. After: 0 of 175.
	"""
	for other in solids:
		if Vector2(pos.x - other.pos.x, pos.z - other.pos.z).length() < other.radius + radius:
			return false
	return true

static func spawn_camp_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	# BUDAPEST — no nomad camps in the city (DEC-9): a dome-hut village pitched on
	# Andrassy Avenue is the clearest case of the procedural world contradicting
	# the plan. NOT tower_excludes(); see in_budapest for why the city takes one
	# answer per system.
	var camp_center = terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(camp_center.x, camp_center.z):
		return
	if not terrain.spawn_camps:
		return
	var camp := _camp_at(terrain, chunk_pos)
	if camp.is_empty():
		return

	# The camp's OWN RNG, seeded by _camp_at's "seed" draw: it picks the spot AND
	# feeds every builder, so each consumes as many draws as it needs without the
	# placement roll (or any other stream) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = camp.seed

	var chunk_center = terrain.chunk_to_world(chunk_pos)
	# Candidates stay CAMP_EDGE_MARGIN (> CAMP_RADIUS) inside the chunk so the
	# whole village fits in one chunk and never straddles a seam.
	var half = terrain.chunk_size / 2.0 - CAMP_EDGE_MARGIN

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
		placed = terrain._biome_spot_ok(chunk_center, center.x, center.z, CAMP_RADIUS, CAMP_ROAD_CLEARANCE, obstacles)
	if not placed:
		return

	# 1. The fire pit at the camp's heart — built first because everything else is
	# arranged around it (the huts face it, the props ring it).
	_camp_fire_pit(terrain, center, rng, parent_chunk, block_batch, block_body)

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
		if not _camp_spot_clear(terrain, hut_center, CAMP_HUT_WIDTH_MAX * 0.71 + 0.3, hut_footprints):
			continue
		# Point the hut's local +Z back at the fire: Basis(UP, yaw) * (0,0,1) is
		# (sin yaw, 0, cos yaw), and we want that to equal -(cos a, sin a).
		var yaw := atan2(-cos(a), -sin(a))
		var footprint := _camp_hut(terrain, hut_center, yaw, rng, block_batch, block_body)
		# Only "pos"/"radius" — this list never reaches `obstacles` (see step 5), so
		# the "top"/"climbable" an obstacle record carries would be read by nothing.
		hut_footprints.append({ "pos": hut_center, "radius": footprint.radius })
		camp_top = maxf(camp_top, footprint.top)

	# 3. The lived-in clutter, on its own tighter ring between fire and huts. The
	# huts go in FIRST so the props can be tested against them: the two rings
	# touch, and a hut is nearly 3 m of radius around its ring position.
	_camp_props(terrain, center, rng, block_batch, block_body, hut_footprints)

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
	if terrain.spawn_coins and terrain.coin_scene != null:
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
			var cy = terrain._settle_coin_y(cx, cz, terrain.COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin = terrain.coin_scene.instantiate()
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

static func _chest_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Deterministic treasure-chest placement for one chunk — _artifact_at / _camp_at
	for chests, same shape, same guarantees. Pure function of chunk coords +
	terrain.run_seed via the independent CHEST_SALT hash stream, so it consumes NO draw
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
	  seeded purely from chunk coords + terrain.run_seed, and every draw downstream comes
	  off that one stream in a fixed order.
	- Across runs, new_run() re-rolls terrain.run_seed, so chests land elsewhere.
	- Whether a candidate is ACCEPTED is likewise load-order independent: the road
	  test reads the station cache (pure in `k`), the river test reads the biome
	  field (pure in world position + terrain.run_seed) and the overlap test reads the
	  chunk's own obstacle list (pure in chunk coords + terrain.run_seed).
	"""
	var rng := RandomNumberGenerator.new()
	# Own coordinate primes AND own salt — see the CHEST_HASH_PRIME_* constants for
	# why they differ from every other stream in this file.
	rng.seed = hash(Vector3i(chunk_pos.x * CHEST_HASH_PRIME_X, chunk_pos.y * CHEST_HASH_PRIME_Y, terrain.run_seed ^ CHEST_SALT))

	# The rarity roll — most chunks bail here, and this is the ONLY draw taken from
	# the stream at this point. The rest happen in spawn_chest_in_chunk off an RNG
	# re-seeded from `seed`, so the two together stay one fixed sequence per chunk.
	# Scarcity thins to plain terrain at 4 km: compare against chance * k (post-draw, no new draw).
	var k_chest: float = terrain.scarcity_at(terrain.chunk_to_world(chunk_pos))
	if rng.randf() >= CHEST_CHANCE * k_chest:
		return {}

	return { "seed": rng.randi() }


static func spawn_chest_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
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
	# BUDAPEST — no treasure chests in the city (DEC-9): the rect's reward line is
	# the authored avenue coins, so a chest here would be loot the plan never
	# placed. NOT tower_excludes(); the city answers per system.
	var chest_center = terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(chest_center.x, chest_center.z):
		return
	if not terrain.spawn_chests:
		return
	var chest := _chest_at(terrain, chunk_pos)
	if chest.is_empty():
		return

	# The chest's OWN RNG, seeded by _chest_at's roll: it picks the spot AND feeds
	# the geometry AND draws the payout, so each consumes as many draws as it needs
	# without the rarity roll (or any other stream) caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = chest.seed

	var chunk_center = terrain.chunk_to_world(chunk_pos)
	# Candidates stay CHEST_EDGE_MARGIN (> CHEST_RADIUS, and > the trigger radius)
	# inside the chunk, so neither the box nor its pickup sphere straddles a seam.
	var half = terrain.chunk_size / 2.0 - CHEST_EDGE_MARGIN

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
		if terrain._biome_spot_ok(chunk_center, local_x, local_z, CHEST_RADIUS, CHEST_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	var center := Vector3(local_x, 0.0, local_z)
	var yaw := rng.randf_range(0.0, TAU)

	# --- The box itself. All three parts go through create_box, so all three land
	# in the chunk's one MultiMesh; only the body carries collision.
	# The body sits ON the ground: centre at half its height.
	terrain.create_box(center + Vector3(0.0, CHEST_BODY_SIZE.y / 2.0, 0.0), CHEST_BODY_SIZE, yaw, rng, block_batch, block_body, 0.0, CHEST_WOOD)

	# The brass band across the waist — collide = false, exactly like a tree canopy
	# or a camp fire stone: it is 6 cm of trim sitting inside the body's own
	# collision box, so a shape for it would be pure cost.
	terrain.create_box(center + Vector3(0.0, CHEST_BODY_SIZE.y * 0.55, 0.0), CHEST_BAND_SIZE, yaw, rng, block_batch, block_body, 0.0, CHEST_BRASS, false)

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
	terrain.create_box(center + Basis(Vector3.UP, yaw) * lid_local, CHEST_LID_SIZE, yaw, rng, block_batch, block_body, -theta, CHEST_WOOD)

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
