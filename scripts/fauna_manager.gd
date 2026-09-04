extends Node
## Ambient migrating fauna: elephant families and giraffe flocks.
##
## From time to time a herd of migrating animals walks across the landscape in
## the distance — near enough to PURE SCENERY: the animals never react to the
## player, the crocodiles, or any special ability; they have no Area3Ds, no
## per-animal scripts, and they belong to NO gameplay group (see below for why
## that matters). They enter at the edge of a ~FIELD_RADIUS circle around the
## player, walk a straight-ish migration line at a calm 2–3 m/s, and are freed
## once past DESPAWN_RADIUS.
##
## RIDEABLE FAUNA — the ONE clause loosened in the isolation contract.
## The four-legged animals (elephant, giraffe, pack beast) each carry ONE box
## collider so the player can jump onto their back and be carried along like a
## moving platform: walking off IS the dismount, there is no mount state, no
## camera change and no input handling anywhere. Everything else about the
## isolation contract stands unchanged — fauna is still in no group, still
## invisible to the stink wave, the LOD manager and the danger vignette, and
## still reacts to nothing. The isolation is enforced by the PHYSICS LAYER, not
## by absence: see FAUNA_COLLISION_LAYER for why crocodiles still walk straight
## through a camel. HERDERS stay walk-through — there is nothing to stand on top
## of a person, and a walking human pillar that blocks the player adds nothing.
##
## Multiplayer note (cross-ref godot-test1-s86.3): a player standing on a camel
## is just a player transform, which peer presence already carries — no sync work
## here. But fauna is local and non-deterministic, so a remote peer does NOT see
## the camel and a ridden avatar appears to glide ~2 m above the ground on their
## screen. Known, accepted cosmetic artifact; do not design around it.
##
## This node (named FaunaManager, added once under Main in main.tscn, in group
## "fauna") is the ENTIRE feature — sibling in spirit to
## crocodile_lod_manager.gd and sound_manager.gd: a single self-contained
## manager that owns its own entities, builds their meshes fully in code (no
## asset files), and drives all of their movement and animation from one
## _physics_process (physics, not idle: the platform velocity a rider inherits
## is computed from the collider's per-PHYSICS-step transform delta, so moving
## the animals on the render frame would hand riders garbage — see
## _make_rideable_root). It holds no hard references to any other system; the player is
## found through the "player" group like everything else in this codebase.
##
## The perf story is deliberately boring:
## - At most ONE migration event is alive at a time: ≤ 8 animals for the two
##   herds, ≤ 10 members for a herder caravan (see CARAVAN_HERDERS_MAX).
## - Every animal is plain Node3D + MeshInstance3D boxes sharing ONE BoxMesh
##   and one material per species (see the static lazy getters below).
## - Between events the entire per-frame cost is a single float subtraction.
##
## WHY the animals join no group: the Phoboman stink wave iterates the
## "crocodile" group and the LOD manager iterates it too — a fauna node in any
## gameplay group would be grabbed by systems that were never written to
## handle it. The manager itself sits in "fauna" purely so future tools can
## find it; the animals themselves are in no group at all.
##
## Fauna is deliberately NON-deterministic ambience: its RNG is randomize()d
## per run and never touches the terrain's run_seed determinism contract —
## revisiting a chunk regenerates the world byte-identically, but which herd
## crosses when is fresh every time, like the crocodiles' per-instance rolls.

# ============================================================================
# CONSTANTS — event scheduling and migration field
# ============================================================================

## Radius (metres) of the field around the player where herds live: a herd
## spawns ON this circle and walks a line through the player's general area.
## Capped by the WEB build's terrain extent, not by taste: web drops
## render_distance to 3 chunks × 50 m, so the ground reaches only ~150 m from
## the player at worst (see endless_terrain.gd's fog comment). A herd spawned
## past that would stand over open sky with no ground plane under it, which
## the fog only partly hides for a 4 m-tall giraffe. 140 m keeps every spawn
## on solid ground on both platforms.
const FIELD_RADIUS: float = 140.0

## Longest formation offset (metres) any member can sit from its herd centre.
## _spawn_herd places the CENTRE and _add_animal then adds each member's offset on
## top, so the spawn circle has to be FIELD_RADIUS pulled in by this, or the
## outermost member lands past the terrain FIELD_RADIUS was sized for. Bounded by
## the giraffe echelon, the widest of the three formations:
##     lat = 3.5 * HERD_SPREAD_LATERAL * 0.6 + 1.5 = 14.1
##     lon = 3.5 * HERD_SPREAD_LONG    * 0.5 + 1.5 = 10.25   (step = (8-1)/2)
##     |offset| = 17.43   <= 17.5   ✓
## The caravan line is second at sqrt(9.9² + 1.6²) = 10.03. Retune GIRAFFE_FLOCK_MAX,
## HERD_SPREAD_*, or the caravan line and this moves with them.
const FORMATION_MAX_EXTENT: float = 17.5

## Distance (metres) from the live player position beyond which a herd is
## freed. Past FIELD_RADIUS so a herd is never culled mid-view — it always
## walks fully out of the visible field before despawning — but bounded by the
## SAME terrain-extent argument as FIELD_RADIUS: the web ground only reaches
## ~150 m, so a herd kept alive further than that would spend its last stretch
## walking over open sky. 150 m is the largest value that keeps every LIVE
## animal (not just every spawn) on solid ground.
const DESPAWN_RADIUS: float = 150.0

## Hard lifetime cap (seconds) for one herd, checked alongside DESPAWN_RADIUS.
## The distance test is RELATIVE to the live player, so a player travelling on
## the herd's heading at the herd's speed (2–3 m/s — squarely inside the duck
## gait's 2.25–2.875) pins the distance forever: the herd never despawns, the
## event timer never re-arms, and because _spawn_herd early-returns while
## _animals is non-empty NO fauna event ever happens again for the rest of the
## run, while _update_herd keeps writing ~90 node properties every frame. The
## cap is the escape hatch. A normal crossing with a STATIONARY player is the
## longest legitimate one — FIELD_RADIUS + DESPAWN_RADIUS = 290 m at the slowest
## 2 m/s ≈ 145 s — so 240 s never truncates a real crossing.
const MAX_HERD_LIFETIME: float = 240.0

## Physics layer the rideable quadruped bodies live on: layer 3 (bit value 4).
##
## THE LAYER CHOICE IS THE WHOLE ISOLATION MECHANISM, so it is not free to
## change. The player's CharacterBody3D masks layers 1 and 3 (scenes/player.tscn,
## collision_mask = 5), so it — and ONLY it — collides with fauna. Crocodiles are
## layer 2 / mask 3 (layers 1 and 2, see piglet_crocodile.tscn), so they never
## see layer 3: a croc still walks straight through a camel, its obstacle
## avoidance never fires on one, and its physics are byte-for-byte what they were
## before fauna had colliders. Putting fauna on layer 1 would silently undo all
## of that, because the croc mask includes layer 1.
const FAUNA_COLLISION_LAYER: int = 4

## Lateral offset (metres) of the migration line from the player, so a herd
## walks PAST them rather than THROUGH them. Without it the line is aimed
## exactly at the player's position at spawn time (the origin is placed on the
## ray from the player), and the miss distance comes only from the player
## having moved since — which is zero whenever they can't move: the 5 s
## respawn grace freeze, a pause, or the game-over screen. The floor covers
## MEANDER_AMPLITUDE (6) plus the widest formation spread, so a player standing
## still watches the herd pass several metres clear (measured: ~9 m at the
## closest draw). It does NOT make a crossing impossible — a player who runs
## across the migration line can still meet it, which is the accepted
## walk-through ceiling below, not a bug.
const MIGRATION_MISS_MIN: float = 25.0
const MIGRATION_MISS_MAX: float = 60.0

## The very first herd of a session comes sooner than the steady-state gap so
## a short play session still sees one (the acceptance criterion is "within a
## few minutes").
const FIRST_EVENT_DELAY_MIN: float = 40.0
const FIRST_EVENT_DELAY_MAX: float = 80.0

## Steady-state gap (seconds) between one herd despawning and the next
## spawning. Wide and random so migrations feel like events, not a schedule.
const FAUNA_INTERVAL_MIN: float = 120.0
const FAUNA_INTERVAL_MAX: float = 240.0

## Herd walking speed range (m/s) — a calm amble, well below every character's
## walk speed, so a herd reads as scenery drifting past rather than a chase.
const WALK_SPEED_MIN: float = 2.0
const WALK_SPEED_MAX: float = 3.0

## Probability that a given event is a herder caravan. Rolled FIRST, so it
## takes its share off the top and ELEPHANT_CHANCE below stays the plain
## elephant/giraffe split of whatever is left (0.15 caravan → 0.425 each herd).
## Clearly rarer than either species on purpose: a caravan is the nomad camps'
## people out on the move, and "rare" is the whole read — a wandering village
## that shows up every other event stops being a sighting.
##
## It shares the ONE fauna event timer rather than owning a second one, and
## that is the perf decision, not a stylistic one: a private timer would break
## the one-herd invariant in _spawn_herd (the early-return that caps this whole
## feature at a single live group), and two concurrent groups would double the
## worst case for a feature whose entire idle cost is one float subtraction.
const CARAVAN_CHANCE: float = 0.15

## Probability that a NON-caravan event is an elephant family; otherwise a
## giraffe flock. 50/50 — both species should feel equally common.
const ELEPHANT_CHANCE: float = 0.5

## Half-angle (radians) of the cone the migration heading is drawn from, taken
## AGAINST the player's run direction (+X). This is not decoration — it is what
## makes the event visible at all. The player runs down +X for the whole game
## (the coin road's X strictly increases) at 5–11 m/s, several times a herd's
## 2–3 m/s amble, so a uniformly random compass heading would waste most
## events: any herd walking roughly WITH the player is simply outrun and
## despawns far behind the camera, never seen. Spawning ahead down the road and
## walking back through the player's area is the only geometry that reliably
## produces a crossing. ~35° is wide enough that no two migrations arrive on
## the same line, narrow enough that the closing speed stays high.
const MIGRATION_HEADING_SPREAD: float = 0.6

# ============================================================================
# CONSTANTS — herd composition and formation
# ============================================================================

## Elephant family size: a small tight group — 1–2 adults leading, the rest
## calves trailing behind them (see _spawn_herd for the placement rule).
const ELEPHANT_HERD_MIN: int = 3
const ELEPHANT_HERD_MAX: int = 5
const ELEPHANT_ADULTS_MIN: int = 1
const ELEPHANT_ADULTS_MAX: int = 2

## Giraffe flock size: a looser, larger group in a diagonal spread.
const GIRAFFE_FLOCK_MIN: int = 4
const GIRAFFE_FLOCK_MAX: int = 8

## Formation spread (metres): how far members sit from the herd centre,
## sideways (perpendicular to travel) and along the travel direction.
const HERD_SPREAD_LATERAL: float = 6.0
const HERD_SPREAD_LONG: float = 5.0

## How far (metres) behind its parent adult an elephant calf walks.
const CALF_TRAIL_DISTANCE: float = 2.5

## Gentle shared meander: the herd centre swings MEANDER_AMPLITUDE metres
## sideways as sin(travelled * MEANDER_FREQUENCY) — frequency is per METRE
## travelled, not per second, so slower herds meander over the same ground.
## 0.03 gives a ~200 m wavelength: visibly "not a laser line", never a loop.
const MEANDER_AMPLITUDE: float = 6.0
const MEANDER_FREQUENCY: float = 0.03

## How quickly (1/s) each animal eases toward its formation slot. Low on
## purpose: the lag makes members drift in and out of formation like animals,
## not like a rigid parade float.
const FORMATION_LERP_SPEED: float = 1.5

## Hard cap (rad/s) on how fast an animal's facing yaw may CHANGE. This is a
## RIDER safety rule, not a look tweak, and it is the third trap in the same
## family as the two in _make_rideable_root.
##
## Each rideable root is an AnimatableBody3D, and Godot derives such a body's
## ANGULAR velocity from its basis delta across one physics step exactly as it
## derives the linear one from the origin delta. A CharacterBody3D standing on
## it inherits the platform velocity AT ITS OWN POINT — `linear + angular × r` —
## so a yaw that jumps in a single tick hands the rider a tangential impulse
## proportional to how far out on the barrel they are standing.
##
## The facing yaw is derived from the herd centre's velocity, whose lateral leg
## carries `_avoid_velocity` — and that is a STEP function: move_toward runs at
## exactly ±AVOID_EASE_SPEED while a swerve is easing and exactly 0 otherwise,
## so the yaw snapped ~0.77 rad (44°) in ONE tick on both the entry and the exit
## of every avoidance swerve. Measured by fauna_selfcheck.gd's row 4, with a
## rider parked at the deck's far corner (the longest lever arm) and driven
## through a meander plus a swerve out and back, that snap moved the player
## 1.26 m in a SINGLE tick on an elephant — 30x the herd's own 0.042 m step —
## against 0.88 on a giraffe and 0.74 on a pack beast. The barrel's half-diagonal
## IS the lever arm (1.53 / 1.07 / 0.95 m), which is exactly why the owner
## reported elephants and not the narrower camels. It threw the rider off: it
## slid 5.64 m across an elephant's deck and travelled only 81% of the animal's
## distance, i.e. it was flung off the back and left behind.
##
## 0.5 rad/s (~29°/s) is derived, not taste. The lever arm is the distance from
## the yaw axis (the root origin) to the rider, so the bound is the widest deck's
## half-DIAGONAL, not its half-width: the elephant's 1.6 x 2.6 m barrel gives
## hypot(0.8, 1.3) = 1.53 m (giraffe 1.07, pack beast 0.95). That bounds the
## tangential carry at ~0.77 m/s — under a third of the herd's own walking speed,
## i.e. a gentle carry-turn — while still completing a full 44° swerve turn in
## 1.5 s, inside the ~1.8 s the offset ease itself takes.
## Rate-limiting the OUTPUT rather than smoothing `_avoid_velocity` is deliberate:
## it bounds the angular velocity whatever feeds the yaw, so a future steering
## term cannot re-open this.
const FACING_YAW_RATE_MAX: float = 0.5

# ============================================================================
# CONSTANTS — obstacle lookahead (steer the CENTRE, never the individuals)
# ============================================================================
# A herd used to walk straight through mountains, camps and trees — the ceiling
# the old ponytail: note in _update_herd named. The fix steers the SHARED HERD
# CENTRE with one cheap swept-box probe and blends the result into the existing
# meander, so every member inherits the detour through its formation offset:
# zero per-animal work, no new state in _animate_animals, and nothing about the
# isolation contract moves (the query READS the world, it is not a contact —
# fauna keeps collision_mask 0 and still touches nothing but the player).
#
# WHY RAYS AND NOT THE TERRAIN'S FOOTPRINTS: endless_terrain builds an exact
# `obstacles` list per chunk (pos/radius/top), which sounds like the cheaper
# source — but it is a local inside create_chunk, handed down the spawner chain
# and dropped when the chunk finishes. Nothing retains it, so querying it means
# a new public API on the terrain. A layer-1 query needs no such API and sees
# strictly more: massif layers, camp huts, tree trunks, chest bodies, artifact
# stone and scattered blocks are all in the same per-chunk BlockCollision body.
#
# WHY A SWEPT BOX AND NOT THREE PARALLEL RAYS (the v1 shape): three rays are
# three infinitely thin samples of a ~30 m corridor, so everything between them
# is invisible — an owner playtest walked elephants straight through the 1–2 m
# scattered decorative blocks, which is exactly the ceiling the old ponytail:
# note predicted. One box the full width of the formation, swept along the
# heading with cast_motion, has NO gaps by construction: anything solid standing
# in the swath is hit whatever its width, so DETECTION and the measured distance
# both come from that ONE query now.
#
# The two EDGE RAYS survive, and only to choose a side: cast_motion answers how
# far the box got, never what it grazed, so it cannot say which way to go round
# (see _edge_clear for the measured failure of deriving that from a rest point).
# They are cast only on a tick that is already blocked, so open country — the
# 99% case — costs ONE query where v1 paid three, and a blocked tick costs the
# same three v1 always paid. Same throttled tick, same steering maths.

## How often (seconds) the lookahead is probed. Throttled like every other
## manager's scan (crocodile_lod_manager, weather_manager): a herd ambles 2–3
## m/s, so 0.25 s is 0.75 m of travel against a 26 m lookahead — the steering
## target cannot go visibly stale, and the whole feature costs 4 physics queries
## a second in open country (12 while actually swerving round something) while a
## herd is alive, and NOTHING at all between events.
const AVOID_PROBE_INTERVAL: float = 0.25

## Sweep length (metres). Sized from the worst case it has to solve, not by
## eye: a mountain massif is ~20 m across and the giraffe echelon is ~28 m wide,
## so the CENTRE has to end up ~25 m off the line before the last member clears
## stone. At AVOID_EASE_SPEED that takes ~13 s, i.e. ~32 m of walking at the
## mean amble — so the warning has to arrive further out than that.
const AVOID_LOOKAHEAD: float = 45.0

## Centre height (metres) of the swept box. Its bottom (centre − half of
## AVOID_PROBE_BOX_HEIGHT = 0.2) clears the chunk ground collision (a 0.1 m box
## straddling y = 0, so its top is 0.05) — without that margin the sweep would
## report the FLOOR as an obstacle and every herd everywhere would swerve.
const AVOID_PROBE_HEIGHT: float = 1.0

## Height (metres) of the swept box. Deliberately short: it only has to span
## from just above the ground slab to the top of the SHORTEST solid worth
## avoiding (a 1.3 m chest body), and a taller box would start catching the
## overhanging canopy slabs that carry no collision anyway.
const AVOID_PROBE_BOX_HEIGHT: float = 1.6

## Thickness (metres) of the swept box along the heading. Thin on purpose — the
## sweep is what covers the corridor's length; depth here only decides how far
## an obstacle level with the box's start still counts (see AVOID_PROBE_SETBACK).
const AVOID_PROBE_BOX_DEPTH: float = 0.4

## Extra clearance (metres) added outside the herd's widest formation slot when
## the swept box is sized, so the swath the herd tests is a little wider than
## the swath it fills and members clear stone rather than shave it.
const AVOID_EDGE_MARGIN: float = 2.0

## Widest lateral detour (metres) the centre will open up. Covers massif half
## width (10) + the widest formation slot (17.5) with a little to spare.
## Deliberately NOT bounded by a new terrain-extent constant: the despawn test
## already measures the FULLY offset centre (meander + detour) against
## DESPAWN_RADIUS, so a big detour simply ends the crossing a little sooner
## instead of walking members off the far edge of the streamed terrain.
const AVOID_MAX_OFFSET: float = 30.0

## How far BEHIND the formation the sweep starts, on top of the herd's own
## widest slot. This is what makes the berth hold until the herd is genuinely
## past what it stepped around, and it replaces a travel-distance latch that did
## the same job worse.
##
## The sweep points forward, so a herd that has opened enough berth stops
## hitting anything while the obstacle is still abeam — unwinding there sends the
## formation back into the flank it just walked around, and the rear members are
## the ones it catches (measured with forward-from-centre rays: 97.5% of aimed
## trials clipping, and with a 30 m travel latch bolted on, still 32-55%, every
## residual failure on the unwind). Starting the box behind the formation means
## an obstacle level with the swath is still IN the swept volume, so "clear"
## cannot become true until the whole herd is past it. No latch, no new state.
const AVOID_PROBE_SETBACK: float = 4.0

## How fast (m/s) the detour opens and closes. Under WALK_SPEED_MIN so the herd
## reads as *curving* around a massif rather than crab-walking sideways (the
## facing yaw follows the detour's rate, so it turns into its own swerve), and
## the same rate closing is what makes it visibly REFORM on the far side.
const AVOID_EASE_SPEED: float = 2.2

## Physics layer the sweep sees: layer 1, the world-geometry layer every chunk
## puts its ground and its single BlockCollision body on. Crocodiles (layer 2)
## and fauna itself (layer 3) are invisible to it by construction — the herd
## cannot react to a croc even by accident. The PLAYER is on layer 1, so it is
## excluded by RID instead (see _refresh_probe_exclude): swerving around the
## player would break the isolation contract just as loudly.
const AVOID_WORLD_MASK: int = 1

# ----------------------------------------------------------------------------
# THE TOWER — the one obstacle the reflex above cannot solve, so it is PLANNED
# ----------------------------------------------------------------------------
# The lookahead is a LOCAL REFLEX: it sees ~45 m and it can open at most
# AVOID_MAX_OFFSET (30 m) of berth. That is sized for what the terrain scatters
# — trees, camp huts, a ~20 m massif. The GastroDefense HQ is none of those: it
# is one sealed 80 m shell on a 65 m exclusion disc (endless_terrain.TOWER_RADIUS)
# standing at a FIXED address (endless_terrain.tower_site()). A herd aimed past
# it sees a wall filling the whole probe, swerves to the 30 m cap — which is not
# even half the disc — finds the wall still there, and parks against the facade
# or oscillates along it. Owner playtest, 2026-08-30: "our fauna guys like
# elephant and others can't go through HQ."
#
# A reflex cannot solve it because a reflex has no map, and this is the one
# obstacle in the game that IS a map: a known centre and a known radius, both
# public on the terrain. So it is answered at the PLANNING level instead — once
# per herd, at spawn, with arithmetic and no physics query at all:
#
#   * the spawn origin is rejected and the line re-rolled if it would stand in
#     the disc (_spawn_herd), and
#   * the lateral offset that clears the disc is computed once (_plan_tower_detour)
#     and then simply handed to the EXISTING `_avoid_target`, so the ease, the
#     facing derivative and the slew limit all work unchanged and nothing new
#     runs per animal or per frame.
#
# The swept box keeps everything else. It is still the right tool for scenery of
# unknown shape at unknown places; it was only ever the wrong tool for a building
# whose address we already know.

## How far ahead (metres, along the heading) the tower has to be before the herd
## starts bending around it. The bend can be ~90 m and `_avoid_target` is eased
## at AVOID_EASE_SPEED (2.2 m/s), so the full berth costs ~40 s, i.e. ~100 m of
## walking at the mean amble — 200 m is that with room to spare. It is also a
## GATE, not just a budget: without it a herd that will despawn long before it
## ever reaches the building would still walk its whole crossing on a visible
## diagonal, steering around a tower nobody can see yet.
const TOWER_PLAN_RANGE: float = 200.0

## Slack (metres) added on top of TOWER_RADIUS + this herd's own formation width
## + MEANDER_AMPLITUDE when planning the berth. The meander rides ON the detour
## (they share the lateral axis), so the berth has to cover the meander's full
## swing or the herd's outward wander eats the clearance it just bought.
const TOWER_CLEARANCE_MARGIN: float = 2.0

## How many times the migration line is re-rolled while its origin would stand
## inside the tower's keep-out disc, before the event is dropped for this cycle.
## Fauna rolls its OWN randomize()d RNG and touches no `run_seed` (see the header),
## so extra draws here shift nothing in the deterministic world. Dropping the
## event is the honest failure: _physics_process re-arms the timer either way, and
## the alternative — spawning anyway — puts elephants inside the lobby.
const TOWER_SPAWN_TRIES: int = 6

# ============================================================================
# CONSTANTS — elephant geometry
# ============================================================================
# All sizes in metres as Vector3(width, height, length). The animal's local
# forward is -Z (Godot's look-at convention, so the herd code can yaw it along
# its travel direction), and feet rest at local y = 0 by construction — the
# ground is a flat plane at world y = 0, so placing the root on the ground
# needs no raycast (see endless_terrain.gd).

## The barrel of the body. Sized so an adult reads clearly at FIELD_RADIUS
## through the fog: bigger than any crocodile, unmistakably "large animal".
const ELEPHANT_BODY_SIZE: Vector3 = Vector3(1.6, 1.5, 2.6)

## One leg column. Its y is the leg LENGTH and doubles as the hip height —
## the hip pivots sit at exactly this y so the foot bottoms out at y = 0.
const ELEPHANT_LEG_SIZE: Vector3 = Vector3(0.4, 1.1, 0.4)

## The head block, hung on the front of the body slightly above centre.
const ELEPHANT_HEAD_SIZE: Vector3 = Vector3(1.0, 1.0, 0.9)

## One big flat ear slab (thin on x so it reads as a flap, not a block).
const ELEPHANT_EAR_SIZE: Vector3 = Vector3(0.12, 0.8, 0.65)

## One trunk segment box; the trunk is ELEPHANT_TRUNK_SEGMENTS of these in a
## nested pivot chain so it can sway like a floppy chain, not a rigid bar.
const ELEPHANT_TRUNK_SEGMENT_SIZE: Vector3 = Vector3(0.28, 0.55, 0.28)

## How many chained trunk segments (2–3 reads fine; 3 sways best).
const ELEPHANT_TRUNK_SEGMENTS: int = 3

## One tusk box (adults only), tilted forward off the head's lower corners.
const ELEPHANT_TUSK_SIZE: Vector3 = Vector3(0.12, 0.55, 0.12)

## Whole-calf scale relative to an adult: applied as ONE scale write on the
## calf's root, never by rebuilding smaller boxes — same geometry, same code
## path, half-ish size.
const CALF_SCALE: float = 0.55

# ============================================================================
# CONSTANTS — giraffe geometry
# ============================================================================
# Same conventions as the elephant block: metres, Vector3(width, height,
# length), local forward -Z, feet at local y = 0.

## The torso block — smaller than an elephant's barrel; a giraffe's read is
## all in the legs and neck, not the body mass.
const GIRAFFE_BODY_SIZE: Vector3 = Vector3(1.0, 1.1, 1.9)

## One long thin leg column; its y doubles as hip height (same trick as the
## elephant), which is most of what makes the silhouette unmistakably giraffe.
const GIRAFFE_LEG_SIZE: Vector3 = Vector3(0.25, 1.9, 0.25)

## The neck box, hung from a shoulder pivot and tilted forward — its y is the
## neck LENGTH along the pivot's local up axis.
const GIRAFFE_NECK_SIZE: Vector3 = Vector3(0.35, 1.9, 0.35)

## Neck lean (degrees about the pivot's X): negative tips the top toward -Z
## (the animal's forward), giving the classic angled-forward giraffe neck.
const GIRAFFE_NECK_ANGLE_DEG: float = -28.0

## The small head block riding the far end of the neck.
const GIRAFFE_HEAD_SIZE: Vector3 = Vector3(0.42, 0.40, 0.75)

## One ossicone horn nub (two per head), tiny accent boxes on the crown.
const GIRAFFE_HORN_SIZE: Vector3 = Vector3(0.08, 0.22, 0.08)

## A FEW darker coat patches — thin slabs sitting just proud of the body's
## sides. Deliberately 2–3 and NOT a checker pattern: a real giraffe pattern
## would need a texture, and this feature ships zero asset files; a handful of
## darker slabs is enough to say "giraffe" at FIELD_RADIUS through the fog.
const GIRAFFE_PATCH_COUNT: int = 3
const GIRAFFE_PATCH_SIZE: Vector3 = Vector3(0.06, 0.45, 0.55)

# ============================================================================
# CONSTANTS — caravan geometry (herders + pack beasts)
# ============================================================================
# Same conventions as the two herd blocks: metres, Vector3(width, height,
# length), local forward -Z, feet at local y = 0. A caravan is the nomad
# camps' people out on the move — a couple of upright herders leading a short
# file of woolly, laden pack beasts.

## Caravan party size. Small on purpose: the read is "a few people walking
## their animals somewhere", not a second herd. Worst case 4 + 6 = 10 members,
## which is the largest event this manager can produce (the herds cap at 8) and
## still one event at a time, so the one-herd perf invariant is unchanged.
const CARAVAN_HERDERS_MIN: int = 2
const CARAVAN_HERDERS_MAX: int = 4
const CARAVAN_BEASTS_MIN: int = 3
const CARAVAN_BEASTS_MAX: int = 6

## Line formation: gap (metres) between consecutive members along the heading,
## and the lateral wobble each member gets so the file reads as a loose trail
## rather than a marching column.
##
## The spacing is BOUNDED by the field, not chosen by eye. The line is centred on
## the herd position, so the rear member sits half a line-length further out and
## must still land inside the ~150 m the web terrain actually reaches. That bound
## is now enforced structurally by FORMATION_MAX_EXTENT (the spawn circle is pulled
## in by it, and the despawn test subtracts the herd's real widest offset), so what
## this has to satisfy is the caravan's own contribution to that extent:
##     hypot((HERDERS_MAX + BEASTS_MAX - 1) / 2 * SPACING, JITTER)
##      <= FORMATION_MAX_EXTENT
##     hypot(4.5 * 2.2, 1.6) = hypot(9.9, 1.6) = 10.03 <= 17.5   ✓
## Note the JITTER leg: the rear member is offset laterally as well as back, so the
## plain 9.9 understates it.
## At 3.0 a full ten-member caravan reached 13.5 m, putting its tail 153.5 m out —
## standing over open sky on the web build. Retune the party size and this
## together.
const CARAVAN_LINE_SPACING: float = 2.2
const CARAVAN_LINE_JITTER: float = 1.6

## The herder: an upright blocky figure, deliberately human-scaled (~1.9 m to
## the crown) so a pack beast beside them reads as a big animal.
const HERDER_TORSO_SIZE: Vector3 = Vector3(0.52, 0.80, 0.34)
const HERDER_HEAD_SIZE: Vector3 = Vector3(0.32, 0.32, 0.32)

## One herder leg column; its y doubles as hip height, same trick as every
## other fauna limb (see _make_leg).
const HERDER_LEG_SIZE: Vector3 = Vector3(0.17, 0.80, 0.17)

## The walking staff, carried at one side and leaned forward a few degrees —
## the single silhouette cue that says "herder" rather than "person".
const HERDER_STAFF_SIZE: Vector3 = Vector3(0.07, 1.85, 0.07)
const HERDER_STAFF_LEAN_DEG: float = -8.0

## The pack beast: a heavy woolly barrel on short legs (a llama/yak read), so
## it never gets mistaken for the taller, leggier giraffe at FIELD_RADIUS.
const BEAST_BODY_SIZE: Vector3 = Vector3(0.85, 0.90, 1.70)
const BEAST_LEG_SIZE: Vector3 = Vector3(0.20, 0.80, 0.20)

## The neck is built as TWO segments so it curves: a lower segment leaning
## forward off the shoulders and an upper one bending back toward vertical,
## with the head on top. One pivot drives the whole chain (see _build_pack_beast).
const BEAST_NECK_SIZE: Vector3 = Vector3(0.28, 0.70, 0.28)
const BEAST_NECK_ANGLE_DEG: float = -34.0
const BEAST_NECK_UPPER_SIZE: Vector3 = Vector3(0.24, 0.55, 0.24)
const BEAST_NECK_UPPER_ANGLE_DEG: float = 30.0
const BEAST_HEAD_SIZE: Vector3 = Vector3(0.26, 0.28, 0.44)

## Shag fringe: thin slabs hung along the lower flanks, in the SAME spirit as
## the giraffe's coat patches — a handful of boxes standing in for fur this
## feature has no texture (and no asset files) to draw.
const BEAST_SHAG_PER_SIDE: int = 3
const BEAST_SHAG_SIZE: Vector3 = Vector3(0.07, 0.42, 0.42)

## The cargo: one or two strapped bundles riding the beast's back — the whole
## point of a pack animal, and what separates a caravan from a wild herd.
const BEAST_BUNDLE_SIZE: Vector3 = Vector3(0.72, 0.42, 0.52)

# ============================================================================
# CONSTANTS — procedural walk animation
# ============================================================================
# Same idiom as piglet_crocodile_ai._animate_body: no AnimationPlayer anywhere,
# just sine waves written onto limb pivots. The one twist here is that the
# stride phase is a pure function of METRES WALKED, not of accumulated time —
# see STRIDE_FREQUENCY.

## Radians of stride phase per METRE the herd travels. Tying the stride to
## distance instead of elapsed time does two things for free: feet keep pace
## with the ground at any walk speed (a faster herd steps faster, exactly like
## the crocodile's move_factor-scaled stride), and the phase is stateless — it
## is recomputed from _herd_travelled every frame, so it can never drift.
## 1.6 rad/m at ~2.5 m/s is a ~0.6 Hz gait: a heavy, unhurried big-animal walk.
const STRIDE_FREQUENCY: float = 1.6

## Peak leg swing (degrees about the hip pivot's X axis).
const LEG_SWING_DEG: float = 18.0

## Stride phase offset per leg, in the fixed FL/FR/RL/RR order every builder
## uses. Diagonal pairs move together (front-left with rear-right) and the two
## diagonals are half a cycle apart — a real quadruped trot, which is what a
## walking elephant or giraffe reads as at this distance.
const LEG_PHASE_OFFSETS: Array[float] = [0.0, PI, PI, 0.0]

## Vertical body bob (metres), oscillating at TWICE the stride rate — one dip
## per footfall rather than one per full cycle. Same bob-is-double-the-stride
## relationship as the crocodile's _animate_body.
const BODY_BOB_AMOUNT: float = 0.06

## Giraffe neck bob: a couple of degrees at HALF the stride rate (a long neck
## swings slowly), layered on top of the neck's rest lean — never overwriting
## it, the same compose-on-rest-pose discipline as the crocodile's
## model_base_scale / model_base_y. NECK_BOB_RATE is that "half" as a fraction
## of the stride rate, the neck's counterpart to TRUNK_SWAY_RATE below.
const NECK_BOB_DEG: float = 3.5
const NECK_BOB_RATE: float = 0.5

## Elephant trunk sway (degrees per segment, side to side about Z) and the
## phase LAG between consecutive segments. The lag is what makes the chain read
## as floppy: each segment starts its swing slightly after its parent, so the
## trunk trails in an S instead of swinging as one rigid bar.
const TRUNK_SWAY_DEG: float = 7.0
const TRUNK_SEGMENT_LAG: float = 0.6

## Trunk sway rate as a fraction of the stride rate — slower than the legs, so
## the trunk drifts rather than marching in time with the feet.
const TRUNK_SWAY_RATE: float = 0.7

# ============================================================================
# STATE
# ============================================================================

## Seconds until the next herd event. Counts down only while no herd is alive;
## re-armed from FAUNA_INTERVAL_* after each despawn.
var _event_timer: float = 0.0

## One record per live animal (see the per-animal record shape in the plan:
## root/body/legs plus species extras and animation phases). Empty array ==
## no herd alive — that emptiness IS the one-herd invariant's bookkeeping.
var _animals: Array[Dictionary] = []

## Private randomize()d RNG, like the crocodile's per-instance rng. Fauna is
## deliberately non-deterministic ambience — it must NOT draw from any seeded
## stream tied to the terrain's run_seed contract.
var _rng := RandomNumberGenerator.new()

## The live herd's shared movement state. Heading and lateral are fixed unit
## XZ vectors for the herd's whole life (the migration LINE); position is the
## herd centre (y = 0) including the meander; travelled is metres walked,
## which drives the meander phase. All meaningless while _animals is empty.
var _herd_heading: Vector3 = Vector3.ZERO
var _herd_lateral: Vector3 = Vector3.ZERO
var _herd_position: Vector3 = Vector3.ZERO
var _herd_speed: float = 0.0
var _herd_travelled: float = 0.0

## Seconds this herd has been alive, against MAX_HERD_LIFETIME (see there for
## why a purely relative despawn test can stall forever).
var _herd_age: float = 0.0

## Longest formation offset this herd actually built, filled in by _add_animal.
## The despawn test measures the herd CENTRE, so without subtracting this the
## members on the far side of the formation walk that much further than
## DESPAWN_RADIUS — over open sky on the web build. Bounded by
## FORMATION_MAX_EXTENT; using the herd's real value keeps a small elephant
## family on screen as long as it always was.
var _herd_offset_max: float = 0.0

## Lateral detour (metres, on the _herd_lateral axis) the lookahead is asking
## for, and the eased value actually applied. `_avoid_velocity` is the applied
## value's exact per-second rate, which the facing yaw needs so the herd LOOKS
## where it is swerving instead of walking sideways with its head straight on.
## All three are reset per herd in _spawn_herd; meaningless while _animals is
## empty, like every other field above.
var _avoid_target: float = 0.0
var _avoid_offset: float = 0.0
var _avoid_velocity: float = 0.0

## The facing yaw actually APPLIED to every animal this tick — the herd shares
## one, because every member shares one centre path (see _update_herd). It is
## the slew-limited follower of the centre velocity's raw angle, and it is state
## rather than a per-tick derivation precisely because the limit needs somewhere
## to start from. Seeded to the migration heading in _spawn_herd so the first
## tick does not slew in from zero. See FACING_YAW_RATE_MAX for why the limit
## exists at all — it is a rider contract, not a look tweak.
var _facing_yaw: float = 0.0

## Countdown to the next lookahead probe (see AVOID_PROBE_INTERVAL).
var _probe_timer: float = 0.0

## The tower plan for the LIVE herd, all three written once by _plan_tower_detour
## at spawn and read-only afterwards (see the TOWER block in the constants).
## `_tower_bend` is the signed lateral offset that clears the disc and is 0.0
## whenever there is no plan at all — no terrain, no tower, or a migration line
## that already misses the building — which is also the flag that keeps the whole
## feature out of _update_herd's hot path. `_tower_keep_out` is the planned
## clearance radius, reused as the "far enough past it to unwind" mark.
var _tower_site: Vector3 = Vector3.ZERO
var _tower_keep_out: float = 0.0
var _tower_bend: float = 0.0

## Metres-travelled mark before which the berth is HELD rather than unwound.
## Set from the distance the sweep actually measured, so it scales itself to
## what was seen instead of guessing (see _update_avoid_target).
var _avoid_hold_until: float = 0.0


## The ONE shape query object and the ONE box it carries, both built in _ready
## and MUTATED per probe — never re-created. The box is resized only when this
## herd's formation width actually differs from the last one (a size write
## notifies the physics server), and the transform/motion are rewritten per tick.
## ponytail: cast_motion returns a fresh PackedFloat32Array and get_rest_info a
## fresh Dictionary — the allocations left in the path, unavoidable through the
## public physics API, and they happen 8×/second only while a herd is alive.
var _probe_params: PhysicsShapeQueryParameters3D = null
var _probe_shape: BoxShape3D = null

## The ONE ray query object, likewise built in _ready and mutated per edge —
## PhysicsRayQueryParameters3D.create() (the crocodile's idiom) allocates a
## RefCounted per call. It is cast ONLY on a tick where the box found something,
## purely to choose a side (see _edge_clear).
var _ray_params: PhysicsRayQueryParameters3D = null

## Reusable exclude list holding just the player's collider RID (see
## AVOID_WORLD_MASK). Kept as a member so assigning it costs no allocation.
var _probe_exclude: Array[RID] = []

# ============================================================================
# SHARED RESOURCES (static — one per PROCESS, not one per manager/animal)
# ============================================================================
# Same discipline as ChunkBatch._get_shared_unit_box_mesh() and
# ToonShading's static material cache: every animal that will ever exist is
# built from ONE unit BoxMesh scaled per part, and the total material count
# for the whole feature is a small constant (2 species + 2 accents), no matter
# how many animals spawn over a session. Never duplicate() these per animal —
# that would defeat batching and grow memory with every herd.

static var _shared_box_mesh: BoxMesh = null
static var _elephant_material: StandardMaterial3D = null
static var _giraffe_material: StandardMaterial3D = null
static var _accent_material: StandardMaterial3D = null
static var _patch_material: StandardMaterial3D = null
static var _cloak_material: StandardMaterial3D = null
static var _wool_material: StandardMaterial3D = null


static func _get_shared_box_mesh() -> BoxMesh:
	## The ONE mesh every fauna body part uses: a unit cube, scaled per part
	## via each MeshInstance3D's own scale. Shared so the renderer sees one
	## mesh resource across every animal ever spawned (batching + memory).
	if _shared_box_mesh == null:
		_shared_box_mesh = BoxMesh.new()
		_shared_box_mesh.size = Vector3.ONE
	return _shared_box_mesh


static func _get_elephant_material() -> StandardMaterial3D:
	## The ONE elephant material (grey hide). Shared by every box of every
	## elephant ever spawned — N animals must never add N materials.
	if _elephant_material == null:
		_elephant_material = StandardMaterial3D.new()
		_elephant_material.albedo_color = Color(0.52, 0.52, 0.55)
		_elephant_material.roughness = 0.9
	return _elephant_material


static func _get_giraffe_material() -> StandardMaterial3D:
	## The ONE giraffe material (tan-orange coat). Same sharing rule as the
	## elephant material above.
	if _giraffe_material == null:
		_giraffe_material = StandardMaterial3D.new()
		_giraffe_material.albedo_color = Color(0.85, 0.62, 0.30)
		_giraffe_material.roughness = 0.9
	return _giraffe_material


static func _get_accent_material() -> StandardMaterial3D:
	## The ONE light accent material (off-white elephant tusks). Shared by
	## every tusk of every elephant ever spawned — accents follow the same
	## one-shared-material rule as the species hides.
	if _accent_material == null:
		_accent_material = StandardMaterial3D.new()
		_accent_material.albedo_color = Color(0.92, 0.90, 0.82)
		_accent_material.roughness = 0.7
	return _accent_material


static func _get_patch_material() -> StandardMaterial3D:
	## The ONE dark accent material (darker-brown giraffe coat patches and
	## horn nubs — both need a darker-than-coat read, so they share it). The
	## caravan reuses it as-is for staffs, straps and bundles rather than adding
	## a third brown, so the feature's total material count is a constant 6,
	## independent of how many animals ever spawn.
	if _patch_material == null:
		_patch_material = StandardMaterial3D.new()
		_patch_material.albedo_color = Color(0.48, 0.32, 0.16)
		_patch_material.roughness = 0.9
	return _patch_material


static func _get_cloak_material() -> StandardMaterial3D:
	## The ONE herder material (muted dusty mauve cloak). Picked to sit apart
	## from BOTH herd hides (elephant grey, giraffe tan) and from the nomad
	## camps' bone-white huts, so a caravan reads as "people" at a glance.
	## Same sharing rule as every material above — never duplicate() per herder.
	if _cloak_material == null:
		_cloak_material = StandardMaterial3D.new()
		_cloak_material.albedo_color = Color(0.43, 0.34, 0.40)
		_cloak_material.roughness = 0.95
	return _cloak_material


static func _get_wool_material() -> StandardMaterial3D:
	## The ONE pack-beast material (cream wool). Shared by every body, leg,
	## neck and shag slab of every beast ever spawned.
	if _wool_material == null:
		_wool_material = StandardMaterial3D.new()
		_wool_material.albedo_color = Color(0.86, 0.79, 0.63)
		_wool_material.roughness = 0.95
	return _wool_material


# ============================================================================
# MODEL BUILDERS (pure code, no scene files, no assets — ability_effect.gd
# precedent: build the visual tree in script, free it when done)
# ============================================================================

static func _make_box_part(part_name: String, size: Vector3, local_pos: Vector3,
		material: StandardMaterial3D, casts_shadow: bool) -> MeshInstance3D:
	## One box-shaped body part: the ONE shared unit BoxMesh scaled to `size`
	## via the node's own scale (never a new mesh resource), painted with a
	## shared species material. `casts_shadow` is a per-part choice: the big
	## silhouette parts keep the default ON (near-ground shadows sell an
	## animal's size), while small accents turn it OFF because they add
	## shadow-pass draws without contributing anything visible to the shadow.
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = _get_shared_box_mesh()
	part.material_override = material
	part.scale = size
	part.position = local_pos
	if not casts_shadow:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return part


static func _make_rideable_root(root_name: String, barrel_size: Vector3,
		bottom_y: float, top_y: float) -> AnimatableBody3D:
	## Build the ROOT node of a rideable quadruped: an AnimatableBody3D carrying
	## ONE box collider around the animal's barrel, so the player can jump on and
	## be carried like a moving platform (see the RIDEABLE FAUNA contract at the
	## head of this file).
	##
	## WHY THE ROOT ITSELF IS THE BODY, and not a body parented under a plain
	## Node3D root: an AnimatableBody3D only pushes a new transform to the
	## physics server when its OWN transform changes. _update_herd moves the
	## ROOT, so a body hanging underneath never sees a local transform change —
	## measured headlessly, its collider stays pinned at the spawn point while
	## the visual walks away, and a player "standing" on it is standing on a
	## phantom 12 m behind the animal with platform_velocity (0,0,0). With the
	## root as the body the same write reaches physics: measured 12.077 m of
	## beast travel against 12.077 m of player travel, platform velocity matching
	## the herd speed. Do NOT demote this back to a child body.
	##
	## The collider sits on the ROOT, never on "Body": Body bobs BODY_BOB_AMOUNT
	## every footfall (see _animate_animals), and a collider riding that would
	## shove the rider up and down a few centimetres at stride rate. The root
	## holds a still, flat deck at the animal's real back height.
	##
	## Layer 3 / mask 0 is the whole isolation story — see the contract at the
	## head of the file for why it must not be layer 1.
	var root := AnimatableBody3D.new()
	root.name = root_name
	# sync_to_physics MUST STAY OFF, and this is the second trap in a row.
	# It is the property every moving-platform tutorial turns ON, but it means
	# "physics drives this node": on every local-transform write the node is
	# immediately snapped BACK to the last transform the physics server
	# confirmed. _update_herd moves an animal with `root.position =
	# root.position.lerp(target, w)` — a read of its own position — so the snap
	# pins the read at the spawn transform and the animal never moves at all.
	# Measured with it on: 16.6 m of herd travel, 0.00 m of animal travel, and a
	# read-back immediately after writing position.x = -99 returned 0.0.
	# With it off the writes stick, and a rider is carried just the same:
	# Godot derives an AnimatableBody3D's platform velocity from its transform
	# delta across one PHYSICS step either way. Measured with it off: 12.077 m of
	# beast travel against 12.077 m of player travel, platform velocity
	# -2.4996 m/s against a herd speed of 2.5. Nothing is lost by teleporting
	# rather than sweeping at these speeds — 2–3 m/s is ~4 cm per step.
	root.sync_to_physics = false
	root.collision_layer = FAUNA_COLLISION_LAYER
	root.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(barrel_size.x, top_y - bottom_y, barrel_size.z)
	var collider := CollisionShape3D.new()
	collider.name = "PlatformShape"
	collider.shape = shape
	collider.position = Vector3(0.0, (bottom_y + top_y) * 0.5, 0.0)
	root.add_child(collider)
	return root


static func _make_leg(leg_name: String, hip_pos: Vector3, leg_size: Vector3,
		material: StandardMaterial3D, casts_shadow: bool) -> Node3D:
	## One leg = a bare pivot Node3D AT HIP HEIGHT with the visible box hung
	## half a leg-length BELOW it. That offset is the whole trick: rotating
	## the pivot about X swings the leg from the hip like a real limb, instead
	## of spinning the box around its own centre. The walk animation only ever
	## touches the pivot; the box never moves in its own frame.
	var pivot := Node3D.new()
	pivot.name = leg_name
	pivot.position = hip_pos
	pivot.add_child(_make_box_part("LegBox", leg_size,
			Vector3(0.0, -leg_size.y * 0.5, 0.0), material, casts_shadow))
	return pivot


func _build_elephant(is_adult: bool) -> Dictionary:
	## Assemble one elephant entirely from the shared unit BoxMesh + shared
	## materials. Blocky BY DESIGN: the whole world (decorative blocks, the
	## low-poly character cast) is boxes and flat colours, so a box elephant
	## matches the art direction — a smooth model would look pasted in, and a
	## real mesh would mean an asset file this feature deliberately avoids.
	##
	## Returns the animal RECORD, not just the root: the builder already holds
	## every pivot the animation loop will ever touch, so it hands them over
	## directly rather than making _add_animal rediscover them by node name.
	## The record shape is species-agnostic — root/body/legs (always four, in
	## FL/FR/RL/RR order) plus the extras slot, which for an elephant is the
	## trunk chain and a null neck.
	var mat := _get_elephant_material()
	# Calves cast no shadows AT ALL: at CALF_SCALE they are small accents in
	# the herd picture, and dropping them from the shadow passes is free
	# fidelity headroom for the adults (whose shadows sell the size contrast).
	var body_shadows := is_adult

	# Barrel: bottom rests on the leg tops, so its centre is hip + half height.
	var body_center_y := ELEPHANT_LEG_SIZE.y + ELEPHANT_BODY_SIZE.y * 0.5

	# The root is the ride platform (see _make_rideable_root): one box around
	# the barrel, from the leg tops to the elephant's back at 2.6 m — under the
	# player's 3.61 m jump apex, so the back is reachable from flat ground.
	var root := _make_rideable_root("Elephant", ELEPHANT_BODY_SIZE,
			ELEPHANT_LEG_SIZE.y, body_center_y + ELEPHANT_BODY_SIZE.y * 0.5)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	body.add_child(_make_box_part("BodyBox", ELEPHANT_BODY_SIZE,
			Vector3(0.0, body_center_y, 0.0), mat, body_shadows))

	# Head: hung on the front (-Z) face, slightly above body centre, tucked
	# 0.15 m back into the barrel so the joint never shows a gap.
	var head_pos := Vector3(0.0, body_center_y + 0.35,
			-(ELEPHANT_BODY_SIZE.z * 0.5 + ELEPHANT_HEAD_SIZE.z * 0.5 - 0.15))
	body.add_child(_make_box_part("Head", ELEPHANT_HEAD_SIZE, head_pos, mat, body_shadows))

	# Ears: thin slabs on the head's sides. Shadow OFF — a 12 cm slab adds a
	# shadow-pass draw and zero silhouette.
	var ear_x := ELEPHANT_HEAD_SIZE.x * 0.5 + ELEPHANT_EAR_SIZE.x * 0.5
	body.add_child(_make_box_part("EarL", ELEPHANT_EAR_SIZE,
			head_pos + Vector3(-ear_x, 0.05, 0.15), mat, false))
	body.add_child(_make_box_part("EarR", ELEPHANT_EAR_SIZE,
			head_pos + Vector3(ear_x, 0.05, 0.15), mat, false))

	# Tusks: adults only — the visual cue that separates parents from calves.
	# Accent material (off-white), tilted so the tops lean forward, shadow OFF.
	if is_adult:
		var tusk_y := head_pos.y - ELEPHANT_HEAD_SIZE.y * 0.5
		var tusk_z := head_pos.z - ELEPHANT_HEAD_SIZE.z * 0.5 + 0.1
		for side: float in [-1.0, 1.0]:
			var tusk := _make_box_part("TuskL" if side < 0.0 else "TuskR",
					ELEPHANT_TUSK_SIZE, Vector3(side * 0.25, tusk_y, tusk_z),
					_get_accent_material(), false)
			tusk.rotation_degrees.x = -35.0
			body.add_child(tusk)

	# Trunk: a chain of nested pivots hanging from the head's front-bottom
	# edge. Each pivot sits at the BOTTOM of its parent segment and its box
	# hangs half a segment below it, so rotating any pivot swings everything
	# downstream — the chain structure Task 5's per-segment sway lag needs.
	var seg_len := ELEPHANT_TRUNK_SEGMENT_SIZE.y
	var trunk: Array[Node3D] = []
	var trunk_parent: Node3D = body
	for i: int in ELEPHANT_TRUNK_SEGMENTS:
		var pivot := Node3D.new()
		pivot.name = "Trunk%d" % i
		if i == 0:
			pivot.position = Vector3(0.0, head_pos.y - ELEPHANT_HEAD_SIZE.y * 0.5,
					head_pos.z - ELEPHANT_HEAD_SIZE.z * 0.5)
		else:
			pivot.position = Vector3(0.0, -seg_len, 0.0)
		pivot.add_child(_make_box_part("TrunkBox", ELEPHANT_TRUNK_SEGMENT_SIZE,
				Vector3(0.0, -seg_len * 0.5, 0.0), mat, false))
		trunk_parent.add_child(pivot)
		trunk_parent = pivot
		trunk.append(pivot)

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := ELEPHANT_BODY_SIZE.x * 0.5 - ELEPHANT_LEG_SIZE.x * 0.5
	var hip_z := ELEPHANT_BODY_SIZE.z * 0.5 - ELEPHANT_LEG_SIZE.z * 0.5
	var hip_y := ELEPHANT_LEG_SIZE.y
	var legs: Array[Node3D] = [
		_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
		_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z), ELEPHANT_LEG_SIZE, mat, body_shadows),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	# A calf is the SAME build scaled once at the root — one scale write, no
	# smaller boxes, no second code path to keep in sync.
	if not is_adult:
		root.scale = Vector3.ONE * CALF_SCALE

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": null,        # elephants have no neck pivot — the trunk is their extra
		"neck_rest": 0.0,    # unused while neck is null; keeps the record one shape
		"trunk": trunk,
	}


func _build_giraffe() -> Dictionary:
	## Assemble one giraffe from the same shared unit BoxMesh + shared
	## materials, and return the SAME record shape as _build_elephant so the
	## animation loop reading it stays species-agnostic: root Node3D (feet at
	## y = 0, faces -Z) -> "Body" Node3D -> four hip-pivot legs in FL/FR/RL/RR
	## order. The only species difference is the extras slot: a giraffe has a
	## neck pivot (elephants: null) and no trunk chain (elephants: 3 segments)
	## — the record simply carries null/empty for the other species' extra.
	var mat := _get_giraffe_material()

	# Torso: rests on the long leg columns, so its centre is hip + half height.
	var body_center_y := GIRAFFE_LEG_SIZE.y + GIRAFFE_BODY_SIZE.y * 0.5

	# Ride platform on the root (see _make_rideable_root): the TORSO only — the
	# neck is animated and is not somewhere to stand. Its back is the tallest
	# rideable surface in the feature at 3.0 m, still under the player's 3.61 m
	# jump apex, so a giraffe stays mountable from flat ground.
	var root := _make_rideable_root("Giraffe", GIRAFFE_BODY_SIZE,
			GIRAFFE_LEG_SIZE.y, body_center_y + GIRAFFE_BODY_SIZE.y * 0.5)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	body.add_child(_make_box_part("BodyBox", GIRAFFE_BODY_SIZE,
			Vector3(0.0, body_center_y, 0.0), mat, true))

	# Coat patches: a few darker slabs just proud of the torso's flanks, at
	# fixed hand-picked spots (alternating sides, staggered along the body) —
	# see GIRAFFE_PATCH_COUNT for why this is NOT a checker pattern. Shadow
	# OFF: a 6 cm slab flush against the body adds a shadow-pass draw and
	# nothing to the silhouette.
	var patch_x := GIRAFFE_BODY_SIZE.x * 0.5 + GIRAFFE_PATCH_SIZE.x * 0.5 - 0.02
	var patch_sides: Array[float] = [-1.0, 1.0, -1.0]
	var patch_offsets: Array[Vector3] = [
		Vector3(0.0, 0.12, -0.55), Vector3(0.0, -0.10, 0.10), Vector3(0.0, 0.18, 0.60),
	]
	# Clamped to the hand-picked spot list: the placements are authored, not
	# generated, so raising GIRAFFE_PATCH_COUNT past them must cap out rather
	# than run off the end of the arrays.
	for i: int in mini(GIRAFFE_PATCH_COUNT, patch_offsets.size()):
		body.add_child(_make_box_part("Patch%d" % i, GIRAFFE_PATCH_SIZE,
				Vector3(patch_sides[i] * patch_x, body_center_y, 0.0) + patch_offsets[i],
				_get_patch_material(), false))

	# Neck: a pivot Node3D at the shoulders (front-top of the torso) with the
	# neck box hung half a length ABOVE it along the pivot's local up — the
	# same offset-from-pivot trick as the legs, so the neck-bob animation can
	# swing the whole neck (head and horns included) from the shoulders. The
	# forward lean is the pivot's REST rotation; Task 5 caches it and layers
	# the bob on top instead of overwriting it.
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, body_center_y + GIRAFFE_BODY_SIZE.y * 0.35,
			-(GIRAFFE_BODY_SIZE.z * 0.5 - GIRAFFE_NECK_SIZE.z * 0.5))
	neck.rotation_degrees.x = GIRAFFE_NECK_ANGLE_DEG
	body.add_child(neck)
	neck.add_child(_make_box_part("NeckBox", GIRAFFE_NECK_SIZE,
			Vector3(0.0, GIRAFFE_NECK_SIZE.y * 0.5, 0.0), mat, true))

	# Head + horn nubs live in NECK-local space at the neck's far end, so they
	# ride every neck swing for free. The head is a silhouette part (shadow
	# stays ON like body/legs/neck); the horn nubs are accents (shadow OFF).
	var head_pos := Vector3(0.0, GIRAFFE_NECK_SIZE.y + GIRAFFE_HEAD_SIZE.y * 0.5 - 0.08,
			-(GIRAFFE_HEAD_SIZE.z * 0.5 - GIRAFFE_NECK_SIZE.z * 0.5))
	neck.add_child(_make_box_part("Head", GIRAFFE_HEAD_SIZE, head_pos, mat, true))
	for side: float in [-1.0, 1.0]:
		neck.add_child(_make_box_part("HornL" if side < 0.0 else "HornR",
				GIRAFFE_HORN_SIZE,
				head_pos + Vector3(side * 0.12,
						GIRAFFE_HEAD_SIZE.y * 0.5 + GIRAFFE_HORN_SIZE.y * 0.5, 0.1),
				_get_patch_material(), false))

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := GIRAFFE_BODY_SIZE.x * 0.5 - GIRAFFE_LEG_SIZE.x * 0.5
	var hip_z := GIRAFFE_BODY_SIZE.z * 0.5 - GIRAFFE_LEG_SIZE.z * 0.5
	var hip_y := GIRAFFE_LEG_SIZE.y
	var legs: Array[Node3D] = [
		_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z), GIRAFFE_LEG_SIZE, mat, true),
		_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z), GIRAFFE_LEG_SIZE, mat, true),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": neck,
		# The neck's forward lean is its REST pose: the bob is layered on top of
		# this value, never overwriting it (same discipline as the crocodile's
		# cached model_base_scale / model_base_y).
		"neck_rest": neck.rotation.x,
		"trunk": [] as Array[Node3D],   # giraffes have no trunk chain
	}


func _build_herder() -> Dictionary:
	## Assemble one caravan herder — a two-legged blocky figure with a staff —
	## and return the SAME species-agnostic record shape as the two herd
	## builders, so nothing downstream learns a new case.
	##
	## The legs slot carries TWO pivots instead of four, and that costs no code
	## at all: _animate_animals indexes LEG_PHASE_OFFSETS by leg index, and its
	## first two entries are 0 and PI — exactly the alternating left/right
	## stride a biped wants. (The quadruped order is FL/FR/RL/RR, so index 0/1
	## being the left/right pair is not a coincidence to preserve here, it is
	## the same convention: even index = left, odd = right.)
	##
	## A herder is the ONE member that stays fully walk-through: a plain Node3D
	## root with no collider, unlike the three rideable quadrupeds (see
	## _make_rideable_root). There is nothing to stand on atop a person, and a
	## solid walking human that blocks or shoves the player buys nothing. Adding
	## one later is a single _make_rideable_root call if that ever changes.
	var mat := _get_cloak_material()

	var root := Node3D.new()
	root.name = "Herder"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	# Torso: rests on the leg tops, so its centre is hip + half height.
	var torso_center_y := HERDER_LEG_SIZE.y + HERDER_TORSO_SIZE.y * 0.5
	body.add_child(_make_box_part("TorsoBox", HERDER_TORSO_SIZE,
			Vector3(0.0, torso_center_y, 0.0), mat, true))

	# Head, sitting straight on the shoulders. Small, but it is the part that
	# makes the silhouette read as a person, so it keeps its shadow.
	body.add_child(_make_box_part("Head", HERDER_HEAD_SIZE,
			Vector3(0.0, torso_center_y + HERDER_TORSO_SIZE.y * 0.5 + HERDER_HEAD_SIZE.y * 0.5,
					0.0), mat, true))

	# Staff: a thin pole carried at the right side, leaned forward a few
	# degrees. Shadow OFF — a 7 cm pole is a pure accent (same rule as tusks).
	var staff := _make_box_part("Staff", HERDER_STAFF_SIZE,
			Vector3(HERDER_TORSO_SIZE.x * 0.5 + 0.10, HERDER_STAFF_SIZE.y * 0.5, -0.05),
			_get_patch_material(), false)
	staff.rotation_degrees.x = HERDER_STAFF_LEAN_DEG
	body.add_child(staff)

	# Two hip pivots, left then right (see the leg-order note above).
	var hip_x := HERDER_TORSO_SIZE.x * 0.5 - HERDER_LEG_SIZE.x * 0.5
	var legs: Array[Node3D] = [
		_make_leg("LegL", Vector3(-hip_x, HERDER_LEG_SIZE.y, 0.0), HERDER_LEG_SIZE, mat, true),
		_make_leg("LegR", Vector3(hip_x, HERDER_LEG_SIZE.y, 0.0), HERDER_LEG_SIZE, mat, true),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": null,                   # a herder's head rides the torso directly
		"neck_rest": 0.0,               # unused while neck is null
		"trunk": [] as Array[Node3D],   # no trunk chain
	}


func _build_pack_beast() -> Dictionary:
	## Assemble one laden pack beast: a woolly barrel on four short legs with a
	## curved neck, a small head and one or two bundles strapped to its back.
	## Same record shape as every other builder — the neck slot is filled, so
	## the existing neck-bob animation drives it with no new code.
	##
	## The neck CURVES using one pivot, not two animated ones: the lower
	## segment leans forward off the shoulders and carries a nested upper
	## segment bent back toward vertical, with the head on top of that. Only
	## the outer pivot is ever animated, and everything downstream rides it —
	## the same parent-swings-the-chain structure as the elephant's trunk.
	var mat := _get_wool_material()

	# Barrel: bottom rests on the leg tops, so its centre is hip + half height.
	var body_center_y := BEAST_LEG_SIZE.y + BEAST_BODY_SIZE.y * 0.5

	# Ride platform on the root (see _make_rideable_root). The deck reaches the
	# BUNDLE tops, not the barrel's: the cargo is what a rider actually stands
	# on, and a collider stopping at the barrel would leave the player floating
	# inside the bundles. The height is independent of how many bundles get
	# rolled below — they share one top face (see bundle_y).
	var root := _make_rideable_root("PackBeast", BEAST_BODY_SIZE, BEAST_LEG_SIZE.y,
			body_center_y + BEAST_BODY_SIZE.y * 0.5 + BEAST_BUNDLE_SIZE.y - 0.05)
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	body.add_child(_make_box_part("BodyBox", BEAST_BODY_SIZE,
			Vector3(0.0, body_center_y, 0.0), mat, true))

	# Shag fringe: slabs hung along the lower flanks, spaced down the length.
	# Shadow OFF (accents), like the giraffe's coat patches.
	var shag_x := BEAST_BODY_SIZE.x * 0.5 + BEAST_SHAG_SIZE.x * 0.5 - 0.02
	var shag_y := body_center_y - BEAST_BODY_SIZE.y * 0.5 + BEAST_SHAG_SIZE.y * 0.35
	for i: int in BEAST_SHAG_PER_SIDE:
		# Evenly spaced along the barrel: i / (n-1) mapped onto -0.35..0.35 of
		# the body length.
		var t := float(i) / float(BEAST_SHAG_PER_SIDE - 1) - 0.5
		var shag_z := t * BEAST_BODY_SIZE.z * 0.7
		for side: float in [-1.0, 1.0]:
			body.add_child(_make_box_part("Shag%d%s" % [i, "L" if side < 0.0 else "R"],
					BEAST_SHAG_SIZE, Vector3(side * shag_x, shag_y, shag_z), mat, false))

	# Bundles: the cargo, sitting on top of the barrel in dark strap-brown.
	# Shadow OFF — they are small and already inside the body's own shadow.
	var bundle_count := _rng.randi_range(1, 2)
	var bundle_y := body_center_y + BEAST_BODY_SIZE.y * 0.5 + BEAST_BUNDLE_SIZE.y * 0.5 - 0.05
	for i: int in bundle_count:
		var bundle_z := (float(i) - float(bundle_count - 1) * 0.5) * (BEAST_BUNDLE_SIZE.z + 0.08)
		body.add_child(_make_box_part("Bundle%d" % i, BEAST_BUNDLE_SIZE,
				Vector3(0.0, bundle_y, bundle_z), _get_patch_material(), false))

	# Neck: pivot at the shoulders, leaning forward; box hung half a length
	# ABOVE it along the pivot's local up (the same offset trick as the legs
	# and the giraffe neck), so the bob swings neck, head and all.
	var neck := Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0.0, body_center_y + BEAST_BODY_SIZE.y * 0.35,
			-(BEAST_BODY_SIZE.z * 0.5 - BEAST_NECK_SIZE.z * 0.5))
	neck.rotation_degrees.x = BEAST_NECK_ANGLE_DEG
	body.add_child(neck)
	neck.add_child(_make_box_part("NeckBox", BEAST_NECK_SIZE,
			Vector3(0.0, BEAST_NECK_SIZE.y * 0.5, 0.0), mat, true))

	# Upper neck: a child pivot at the lower segment's top, bent BACK so the
	# pair reads as a curve rather than one straight bar. Not animated — it is
	# rest geometry that rides the parent pivot.
	var neck_upper := Node3D.new()
	neck_upper.name = "NeckUpper"
	neck_upper.position = Vector3(0.0, BEAST_NECK_SIZE.y, 0.0)
	neck_upper.rotation_degrees.x = BEAST_NECK_UPPER_ANGLE_DEG
	neck.add_child(neck_upper)
	neck_upper.add_child(_make_box_part("NeckUpperBox", BEAST_NECK_UPPER_SIZE,
			Vector3(0.0, BEAST_NECK_UPPER_SIZE.y * 0.5, 0.0), mat, true))

	# Head, in UPPER-NECK-local space at the far end, so it rides the whole
	# chain for free. Shadow OFF — a 26 cm nub adds nothing to the silhouette.
	neck_upper.add_child(_make_box_part("Head", BEAST_HEAD_SIZE,
			Vector3(0.0, BEAST_NECK_UPPER_SIZE.y + BEAST_HEAD_SIZE.y * 0.5 - 0.05,
					-(BEAST_HEAD_SIZE.z * 0.5 - BEAST_NECK_UPPER_SIZE.z * 0.5)), mat, false))

	# Legs, always in FL/FR/RL/RR order — the species-agnostic contract the
	# animation loop relies on (diagonal trot pairs are picked by index).
	var hip_x := BEAST_BODY_SIZE.x * 0.5 - BEAST_LEG_SIZE.x * 0.5
	var hip_z := BEAST_BODY_SIZE.z * 0.5 - BEAST_LEG_SIZE.z * 0.5
	var hip_y := BEAST_LEG_SIZE.y
	var legs: Array[Node3D] = [
		_make_leg("LegFL", Vector3(-hip_x, hip_y, -hip_z), BEAST_LEG_SIZE, mat, true),
		_make_leg("LegFR", Vector3(hip_x, hip_y, -hip_z), BEAST_LEG_SIZE, mat, true),
		_make_leg("LegRL", Vector3(-hip_x, hip_y, hip_z), BEAST_LEG_SIZE, mat, true),
		_make_leg("LegRR", Vector3(hip_x, hip_y, hip_z), BEAST_LEG_SIZE, mat, true),
	]
	for leg: Node3D in legs:
		body.add_child(leg)

	return {
		"root": root,
		"body": body,
		"legs": legs,
		"neck": neck,
		# The forward lean is the neck's REST pose: the bob is layered on top of
		# it, never overwriting it (same discipline as the giraffe's neck).
		"neck_rest": neck.rotation.x,
		"trunk": [] as Array[Node3D],   # no trunk chain
	}


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	## Join the "fauna" group (discovery hook for future tools — the ANIMALS
	## join no group, only the manager), seed the private RNG, and arm the
	## first-event timer with the shorter first-session delay.
	add_to_group("fauna")
	_rng.randomize()
	_event_timer = _rng.randf_range(FIRST_EVENT_DELAY_MIN, FIRST_EVENT_DELAY_MAX)

	# The one shape query object for the obstacle lookahead — built once here,
	# mutated per probe (see _swath_clear), never re-created.
	_probe_shape = BoxShape3D.new()
	_probe_params = PhysicsShapeQueryParameters3D.new()
	_probe_params.shape = _probe_shape
	_probe_params.collision_mask = AVOID_WORLD_MASK
	_probe_params.collide_with_areas = false
	_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.collision_mask = AVOID_WORLD_MASK
	_ray_params.collide_with_areas = false


func _physics_process(delta: float) -> void:
	## The whole per-frame driver. With a herd alive it advances and animates
	## it; with none alive the ENTIRE cost of this feature is the one float
	## subtraction and compare below — that's the idle perf story.
	##
	## PHYSICS frame, not idle, and that is load-bearing: the animals' roots are
	## AnimatableBody3Ds (see _make_rideable_root), and Godot derives the platform
	## velocity a rider inherits from the body's transform delta ACROSS ONE
	## PHYSICS STEP. Driving them from _process would mean several render frames
	## per physics step (or none), so the delta the rider inherits would be a
	## render-clock artifact rather than the herd's speed. 60 Hz costs nothing
	## here either — a stride is ~0.6 Hz, so the weather manager's birds-alias
	## argument (which justified per-frame updates there) simply does not apply.
	if not _animals.is_empty():
		_update_herd(delta)
		return

	_event_timer -= delta
	if _event_timer <= 0.0:
		_spawn_herd()
		# Re-arm now so a failed spawn (no player yet) just retries later
		# instead of hammering every frame.
		_event_timer = _rng.randf_range(FAUNA_INTERVAL_MIN, FAUNA_INTERVAL_MAX)


# ============================================================================
# CORE (herd spawning, migration movement, animation)
# ============================================================================

func _find_player() -> Node3D:
	## Locate the player through the "player" group — group-based discovery,
	## never a hard $-path (matches crocodile_lod_manager.gd). Null-safe: in a
	## scene run without a player (a character scene tested standalone) this
	## returns null and the manager simply does nothing, same defensive style
	## as the sound-manager group lookups.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		return player
	return null


func _spawn_herd() -> void:
	## Build and place one herd on the edge of the field, aimed to walk
	## through the player's general area and out the far side.
	##
	## Placement: pick a heading from the rearward cone (see
	## MIGRATION_HEADING_SPREAD), put the herd origin on the field circle
	## FIELD_RADIUS away — ahead of the player down the road, offset sideways by
	## MIGRATION_MISS so the line passes BESIDE them, not through them — and walk
	## along +heading, so the migration line crosses TOWARD and PAST the player
	## even while they run.
	##
	## The animals are parented to THIS manager, never to a terrain chunk:
	## chunk unloading frees everything under a chunk mesh, and a herd must
	## survive its whole crossing regardless of which chunks come and go.
	##
	## ponytail: the bead's optional elephant trumpet is skipped this cycle —
	## sound_manager.gd is owned by a parallel executor; the upgrade path is a
	## play_*-style one-shot there plus a null-safe "sound_manager" group
	## lookup right here at spawn time.
	if not _animals.is_empty():
		# The ONE-HERD INVARIANT — this early-return IS the perf story: the
		# feature's worst case is a single event, ever — ≤ 8 animals for a herd,
		# ≤ 10 members for a caravan (CARAVAN_HERDERS_MAX + CARAVAN_BEASTS_MAX).
		return
	var player := _find_player()
	if player == null:
		return

	var player_ground := Vector3(player.global_position.x, 0.0, player.global_position.z)
	# The along-heading setback shrinks to keep the origin ON the spawn circle
	# (Pythagoras), not past it — otherwise the lateral offset would push the spawn
	# beyond DESPAWN_RADIUS and the herd would be freed on its first update frame.
	# The circle is FIELD_RADIUS pulled in by FORMATION_MAX_EXTENT, because
	# _add_animal places each member at `centre + offset` and never subtracts: with
	# the centre ON the 140 m circle the outermost giraffe stood at ~157 m, over the
	# open sky past the web build's ~150 m of terrain — the exact failure
	# FIELD_RADIUS exists to prevent. |miss| < spawn_radius always, so the root is real.
	var spawn_radius := FIELD_RADIUS - FORMATION_MAX_EXTENT
	# Roll the whole migration line, and re-roll it while its ORIGIN would stand
	# inside the tower's keep-out disc — a herd built there is a herd built in the
	# HQ's lobby, and no amount of steering afterwards gets it out (see the TOWER
	# block in the constants, and TOWER_SPAWN_TRIES for why giving up is right).
	# In open country the first attempt always passes, so the draw sequence — and
	# with it every migration line the field has ever laid out — is unchanged.
	var placed := false
	for _attempt: int in TOWER_SPAWN_TRIES:
		# Heading is drawn from a cone facing back down the road (PI = straight
		# against the player's +X run direction) — see MIGRATION_HEADING_SPREAD for
		# why a uniform compass heading would leave most migrations unseen.
		var angle := PI + _rng.randf_range(-MIGRATION_HEADING_SPREAD, MIGRATION_HEADING_SPREAD)
		_herd_heading = Vector3(cos(angle), 0.0, sin(angle))
		# Lateral = heading rotated 90° in the ground plane; with heading, it is
		# the herd-local frame every formation offset is expressed in.
		_herd_lateral = Vector3(-_herd_heading.z, 0.0, _herd_heading.x)
		# Offset the whole migration line sideways so the herd passes BESIDE the
		# player instead of straight through them (see MIGRATION_MISS_MIN).
		var miss := _rng.randf_range(MIGRATION_MISS_MIN, MIGRATION_MISS_MAX)
		if _rng.randf() < 0.5:
			miss = -miss
		var setback := sqrt(spawn_radius * spawn_radius - miss * miss)
		_herd_position = player_ground - _herd_heading * setback + _herd_lateral * miss
		if not _tower_excludes_spawn(_herd_position):
			placed = true
			break
	if not placed:
		return
	_herd_speed = _rng.randf_range(WALK_SPEED_MIN, WALK_SPEED_MAX)
	_herd_travelled = 0.0
	_herd_age = 0.0
	_herd_offset_max = 0.0
	# Fresh herd, fresh detour state — a herd that despawned mid-swerve must not
	# hand its offset to the next one, which walks a completely different line.
	_avoid_target = 0.0
	_avoid_offset = 0.0
	_avoid_velocity = 0.0
	_probe_timer = 0.0
	_avoid_hold_until = 0.0
	# Seed the slew-limited facing at the migration heading — the same expression
	# _add_animal places each member with — so the first tick has nothing to slew
	# toward and the herd does not spin up from world north (see FACING_YAW_RATE_MAX).
	_facing_yaw = atan2(-_herd_heading.x, -_herd_heading.z)
	_refresh_probe_exclude(player)

	# Build the members with their formation offsets (herd-local lateral/long
	# pairs turned into world-space vectors — heading never changes, so the
	# world-space offset is valid for the herd's whole life).
	# The caravan is rolled FIRST and takes its slice off the top, so the
	# elephant/giraffe split below is untouched (see CARAVAN_CHANCE).
	if _rng.randf() < CARAVAN_CHANCE:
		_spawn_caravan()
	elif _rng.randf() < ELEPHANT_CHANCE:
		_spawn_elephant_family()
	else:
		_spawn_giraffe_flock()

	# LAST, because the plan needs `_herd_offset_max` — which is this herd's own
	# formation width and is only known once every member has been placed.
	_plan_tower_detour()


func _spawn_elephant_family() -> void:
	## An elephant family: 1–2 adults spread abreast at the front, the calves
	## each trailing CALF_TRAIL_DISTANCE behind a randomly chosen adult with a
	## small lateral jitter — the classic "calf shadows its parent" read.
	var herd_size := _rng.randi_range(ELEPHANT_HERD_MIN, ELEPHANT_HERD_MAX)
	var adult_count := mini(_rng.randi_range(ELEPHANT_ADULTS_MIN, ELEPHANT_ADULTS_MAX), herd_size)

	var adult_offsets: Array[Vector3] = []
	for i: int in adult_count:
		# Adults abreast: centred lateral slots at the formation's front.
		var lat := (float(i) - float(adult_count - 1) * 0.5) * HERD_SPREAD_LATERAL
		var offset := _herd_lateral * lat + _herd_heading * _rng.randf_range(0.0, HERD_SPREAD_LONG * 0.4)
		adult_offsets.append(offset)
		_add_animal(_build_elephant(true), offset)
	for i: int in herd_size - adult_count:
		var parent_offset: Vector3 = adult_offsets[_rng.randi_range(0, adult_count - 1)]
		var jitter := _rng.randf_range(-HERD_SPREAD_LATERAL * 0.3, HERD_SPREAD_LATERAL * 0.3)
		var offset := parent_offset - _herd_heading * CALF_TRAIL_DISTANCE + _herd_lateral * jitter
		_add_animal(_build_elephant(false), offset)


func _spawn_giraffe_flock() -> void:
	## A giraffe flock: a loose DIAGONAL spread — each member steps a slot
	## along BOTH the heading and the lateral axis (plus jitter), so the line
	## reads as a staggered echelon rather than a row or a queue.
	var flock_size := _rng.randi_range(GIRAFFE_FLOCK_MIN, GIRAFFE_FLOCK_MAX)
	for i: int in flock_size:
		var step := float(i) - float(flock_size - 1) * 0.5
		var lat := step * HERD_SPREAD_LATERAL * 0.6 + _rng.randf_range(-1.5, 1.5)
		var lon := step * HERD_SPREAD_LONG * 0.5 + _rng.randf_range(-1.5, 1.5)
		_add_animal(_build_giraffe(), _herd_lateral * lat + _herd_heading * lon)


func _spawn_caravan() -> void:
	## A herder caravan: the herders walk at the FRONT of the line and the laden
	## pack beasts trail behind them in a loose, jittered single file — the
	## "people leading their animals somewhere" read the owner asked for.
	##
	## Formation is one slot per member stepping CARAVAN_LINE_SPACING backwards
	## along the heading, with a lateral wobble so the file bends like a trail
	## rather than a marching column. Everything else — easing into the slot,
	## facing along the heading, per-animal stride phase, movement, animation and
	## despawn — comes free from _add_animal / _update_herd / _animate_animals:
	## a caravan is just N records of the same species-agnostic shape.
	##
	## ISOLATION CONTRACT (identical to the two herds, and non-negotiable):
	## caravan members join NO group. Phoboman's Stink Wave iterates "crocodile"
	## and crocodile_lod_manager.gd iterates it too, so a fauna node in any enemy
	## group would be grabbed by both. They ignore the player, crocodiles,
	## abilities and rain completely — they are scenery that happens to walk.
	## The pack beasts DO carry a rideable collider on layer 3 (see
	## _make_rideable_root), which is the single loosened clause: the player can
	## stand on one, and nothing else in the game can touch them. The herders
	## carry no collider at all.
	##
	## ponytail: a caravan does NOT path to or from a nomad camp — the two
	## halves of the feature are thematically linked and mechanically
	## independent. Wiring them up needs a nearest-camp query on the terrain
	## (camps are chunk-local and unload with their chunk, so it would also need
	## to survive the camp despawning mid-walk); the upgrade path is a
	## `get_camp_near(pos)` on endless_terrain.gd plus a heading override here.
	##
	## ponytail: the optional caravan bell one-shot is skipped, same shape as
	## the elephant trumpet noted in _spawn_herd — sound_manager.gd's players are
	## non-positional, and a caravan spawns ~FIELD_RADIUS (140 m) away, so a bell
	## at full volume in both ears would read as "inside the player's head"
	## rather than "in the distance". The upgrade path is a positional audio path
	## (an AudioStreamPlayer3D on the lead herder) plus a play_* in the manager's
	## synth style.
	var herder_count := _rng.randi_range(CARAVAN_HERDERS_MIN, CARAVAN_HERDERS_MAX)
	var beast_count := _rng.randi_range(CARAVAN_BEASTS_MIN, CARAVAN_BEASTS_MAX)

	# Slot 0 is the front of the line; each later slot steps one spacing back
	# along the heading. Centred on the herd position so the line straddles the
	# migration centre instead of trailing entirely behind it.
	var total := herder_count + beast_count
	for i: int in total:
		var step := float(i) - float(total - 1) * 0.5
		var lon := -step * CARAVAN_LINE_SPACING
		var lat := _rng.randf_range(-CARAVAN_LINE_JITTER, CARAVAN_LINE_JITTER)
		var offset := _herd_heading * lon + _herd_lateral * lat
		var record := _build_herder() if i < herder_count else _build_pack_beast()
		_add_animal(record, offset)


func _add_animal(record: Dictionary, offset: Vector3) -> void:
	## Parent one built animal, place it at its formation slot, face it along
	## the herd heading, and finish its record. The builder already cached every
	## node reference the movement/animation code will ever touch (limb pivots,
	## neck, trunk chain, rest pose), so the per-frame loops never call get_node
	## — and neither does this, there is no lookup anywhere at spawn either.
	##
	## `position`, not `global_position`: the animals hang off this manager, a
	## plain Node with no transform of its own, under Main at identity.
	var root: Node3D = record["root"]
	add_child(root)
	root.position = _herd_position + offset
	# The herd's one shared facing, seeded from the heading in _spawn_herd — not
	# recomputed here, so spawn and every later tick cannot drift apart.
	root.rotation.y = _facing_yaw

	record["offset"] = offset                       # formation slot, world-space
	record["phase"] = _rng.randf_range(0.0, TAU)    # stride offset — no lockstep
	_animals.append(record)
	# Widest slot in this formation — the despawn test subtracts it (see the var).
	_herd_offset_max = maxf(_herd_offset_max, offset.length())


func _player_is_riding(player: Node3D) -> bool:
	## True while the player is in contact with one of THIS herd's animals —
	## the guard that stops MAX_HERD_LIFETIME dropping a rider (see _update_herd).
	##
	## The test is the player's own slide collisions from its last
	## move_and_slide, matched against the animal roots (which ARE the collision
	## bodies — see _make_rideable_root), so the manager needs no reference to
	## the player's internals and no second bookkeeping list. Standing on a beast
	## is a floor contact, so it always shows up here.
	##
	## Called only on the tick the cap would otherwise fire, so its cost is a
	## handful of comparisons once per frame after four minutes, not per frame.
	## has_method keeps it null-safe for a non-CharacterBody3D player (a bare
	## scene run standalone), matching the defensive style of _find_player.
	if not player.has_method("get_slide_collision_count"):
		return false
	for i: int in player.get_slide_collision_count():
		var collider: Object = player.get_slide_collision(i).get_collider()
		for animal: Dictionary in _animals:
			if animal["root"] == collider:
				return true
	return false


func _update_herd(delta: float) -> void:
	## Advance the shared herd centre along the migration line, ease every
	## member toward its formation slot, and despawn once the crossing is
	## done. Feet stay at y = 0 by construction: the ground is one flat plane
	## at world y = 0 (see endless_terrain.gd), so there is no raycast and no
	## terrain query anywhere in fauna.
	##
	## Scenery is steered around, not collided with: the animals' bodies still
	## mask nothing (see FAUNA_COLLISION_LAYER) — the detour comes entirely from
	## the lookahead sweep below, which READS the world and never touches it.
	## Giving fauna a collision mask instead would make herds shove each other
	## and stall against terrain, which is why that is still not done.
	var player := _find_player()
	# Despawn when the crossing is over: the herd centre is measured against
	# the LIVE player position each tick, so "the herd walked past" and "the
	# player ran away from the herd" are the same check. No player at all
	# (scene torn down mid-walk) also ends the event.
	# The lifetime cap is the second half of that test: the distance is measured
	# against a MOVING player, so a player travelling with the herd at the herd's
	# own speed keeps it in range forever and the feature stalls for good (see
	# MAX_HERD_LIFETIME).
	# The lifetime cap is DEFERRED, never skipped, while the player is standing
	# on one of this herd's animals. Riding is precisely the "player pins the
	# herd alive" case the cap was written for, so it is exactly the case that
	# trips it — and firing it would free the whole herd out from under the
	# player's feet mid-stride, dropping them ~2 m. Re-tested every tick, so the
	# cap resumes the instant they step off and the herd despawns normally.
	if player == null or (_herd_age + delta > MAX_HERD_LIFETIME and not _player_is_riding(player)):
		_despawn_herd()
		return

	_herd_age += delta
	_herd_travelled += _herd_speed * delta
	# Centre = straight line along the heading + the gentle shared meander on
	# the lateral axis, phased by distance walked (see MEANDER_FREQUENCY), plus
	# the obstacle detour below — all three ride the SAME lateral axis, which is
	# why steering needed no new geometry: it is one more term in the sum every
	# member is already placed against.
	_herd_position += _herd_heading * (_herd_speed * delta)
	var meander := sin(_herd_travelled * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE

	# Obstacle lookahead, on its own throttled tick. Probed from where the herd
	# centre actually IS (detour included), so the sweep describes the corridor
	# the herd is currently committed to rather than the undeflected line.
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = AVOID_PROBE_INTERVAL
		_update_avoid_target(_herd_position + _herd_lateral * (meander + _avoid_offset))
	# THE TOWER OVERRIDES THE PROBE, and it has to be in that order: the shell is
	# a wall filling the whole swath, so the reflex above is guaranteed to be
	# asking for its ±AVOID_MAX_OFFSET cap — which is less than half the disc and
	# is exactly the flailing this replaces. The plan is a straight write into the
	# SAME `_avoid_target` rather than a fourth lateral term, so the ease below,
	# `_avoid_velocity`, the facing derivative and the slew limit all keep working
	# untouched and nothing new happens per animal.
	#
	# Gated at both ends: TOWER_PLAN_RANGE ahead (a building the herd will despawn
	# before reaching must not bend it now), and released once the herd is a full
	# clearance radius PAST the site, which is the point the rear of the formation
	# has cleared the far corner — the probe and the unwind take it from there.
	if _tower_bend != 0.0:
		var along := (_tower_site.x - _herd_position.x) * _herd_heading.x \
				+ (_tower_site.z - _herd_position.z) * _herd_heading.z
		if along < TOWER_PLAN_RANGE and along > -_tower_keep_out:
			_avoid_target = _tower_bend
	# Ease toward the target and record the EXACT rate applied — the facing yaw
	# below reads it, so a swerving herd turns into its swerve.
	var avoid_before := _avoid_offset
	_avoid_offset = move_toward(_avoid_offset, _avoid_target, AVOID_EASE_SPEED * delta)
	_avoid_velocity = (_avoid_offset - avoid_before) / delta

	var centre := _herd_position + _herd_lateral * (meander + _avoid_offset)

	# The distance test measures `centre` — the point every member is actually
	# placed relative to, meander included — reduced by this herd's widest
	# formation offset. Measuring _herd_position instead (no meander) and not
	# subtracting the offset let the far side of the line walk ~14 m past the
	# radius, which is exactly the terrain extent DESPAWN_RADIUS is bounded by
	# (see _herd_offset_max). It runs AFTER the advance so the point tested is the
	# one the members are about to be eased toward, not last tick's.
	if centre.distance_to(player.global_position) > DESPAWN_RADIUS - _herd_offset_max:
		_despawn_herd()
		return

	# Facing: the centre's own velocity — the heading plus the meander's
	# derivative, which is exact and needs no previous-frame state. Computed
	# ONCE per frame, not once per animal: every member shares the same centre
	# path, the same formation offset arithmetic and the same ease weight, so
	# every member's motion vector is provably identical and N atan2 calls
	# would all return the same number. Local forward is -Z, hence the negated
	# atan2 arguments.
	# The detour's rate is added in metres per SECOND while the meander's term is
	# per metre travelled, hence the _herd_speed divide — both legs have to be in
	# the same units before they can share one atan2.
	var centre_velocity := _herd_heading + _herd_lateral \
			* (cos(_herd_travelled * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE * MEANDER_FREQUENCY
					+ _avoid_velocity / maxf(_herd_speed, 0.001))
	# ...and then SLEW-LIMITED before it reaches a node. The raw angle is a step
	# function (the lateral leg carries _avoid_velocity, which move_toward pins at
	# exactly ±AVOID_EASE_SPEED or exactly 0), and these roots are AnimatableBody3Ds
	# whose angular velocity Godot derives from the basis delta — so writing the
	# raw angle handed a rider `angular × r` and flung them off the barrel. See
	# FACING_YAW_RATE_MAX; this one line is the whole fix and it bounds every
	# future steering term for free.
	var yaw := rotate_toward(_facing_yaw, atan2(-centre_velocity.x, -centre_velocity.z),
			FACING_YAW_RATE_MAX * delta)
	_facing_yaw = yaw

	# The ease is a soft, uniform lag on the whole formation (members start
	# exactly on their slots, so nothing here spreads them apart): it takes the
	# edge off the meander's direction changes so the herd swings into a turn
	# instead of snapping onto the new line.
	var ease_weight := minf(1.0, FORMATION_LERP_SPEED * delta)
	for animal: Dictionary in _animals:
		var root: Node3D = animal["root"]
		var target: Vector3 = centre + animal["offset"]
		root.position = root.position.lerp(target, ease_weight)
		root.rotation.y = yaw

	_animate_animals()


func _refresh_probe_exclude(player: Node3D) -> void:
	## Point the sweep's exclude list at the player's collider, once per herd.
	##
	## The player is a CharacterBody3D on layer 1 (scenes/player.tscn leaves
	## collision_layer at the default), i.e. on the very layer the sweep watches,
	## so without this a herd would swerve around the PLAYER — the loudest
	## possible breach of the isolation contract, and one that would only show up
	## when somebody happened to stand in front of a passing herd. Excluding by
	## RID (not by an is_in_group check on the hit, the crocodile's idiom) is what
	## lets the box sweep on THROUGH the player to the massif behind them.
	##
	## PhysicsShapeQueryParameters3D carries `exclude` with exactly the same
	## meaning PhysicsRayQueryParameters3D did, so the shape-cast upgrade left
	## this rule untouched — and the layer-1-only mask still hides crocodiles
	## (layer 2) and fauna's own rideable bodies (layer 3) by construction.
	_probe_exclude.clear()
	if player.has_method("get_rid"):
		_probe_exclude.append(player.get_rid())
	_probe_params.exclude = _probe_exclude
	_ray_params.exclude = _probe_exclude


func _swath_clear(space: PhysicsDirectSpaceState3D, length: float) -> float:
	## Sweep the box (already sized, oriented and positioned by the caller) and
	## return how far it got: the distance to the first contact, or the full
	## `length` when the corridor is empty. Distance rather than a bool because
	## the caller grades the hold by how far off the blockage was.
	_probe_params.motion = _herd_heading * length
	var fractions := space.cast_motion(_probe_params)
	if fractions.size() < 2:
		# The engine could not answer (documented for a shape that cannot move).
		# Read that as open country, NEVER as blocked: a herd that reads an
		# unusable answer as "obstacle at zero metres" pins itself at the full
		# AVOID_MAX_OFFSET berth for the rest of the crossing, in open field.
		return length
	return fractions[0] * length


func _edge_clear(space: PhysicsDirectSpaceState3D, origin: Vector3,
		length: float) -> float:
	## Cast ONE edge ray and return how far it got: the hit distance, or the full
	## `length` when nothing is on that line. Distance rather than a bool (the
	## crocodile's _feeler_blocked) because the caller steers by comparing the
	## two edges' room.
	##
	## THESE TWO RAYS ARE NOT DETECTION and must not be folded into `tightest` —
	## the swept box already covers everything between and including them. They
	## survive from v1 for the one job a swept box cannot do: a cast_motion
	## answers HOW FAR it got, never WHAT it grazed, so it cannot say which way
	## to go round. "Is the extreme edge of the swath free?" is exactly the
	## question that answers it, and a thin sample of a line the obstacle
	## probably is not on is the right shape for that question — a rest point
	## from the box was tried and is the version that FAILS (12.5% of aimed
	## massif trials clipped, worst −2.44 m): the contact it reports can sit
	## anywhere on the manifold, so a massif lying mostly to the left reports a
	## contact on its right edge and sends the herd left into the bulk of it.
	_ray_params.from = origin
	_ray_params.to = origin + _herd_heading * length
	var hit := space.intersect_ray(_ray_params)
	if hit.is_empty():
		return length
	return origin.distance_to(hit["position"])


func _tower_excludes_spawn(spot: Vector3) -> bool:
	## Would a herd centre here stand inside the tower's keep-out disc?
	##
	## `tower_excludes()` on the terrain is THE SINGLE HOME of that rule (it adds
	## TOWER_DECOR_OVERHANG itself), so this asks it rather than re-deriving the
	## test — the same reason every spawner in endless_terrain.gd calls it. The
	## herd's own radius is FORMATION_MAX_EXTENT: the centre is what is being
	## placed, but _add_animal then hangs members up to that far off it.
	##
	## Group lookup with a has_method guard, like every other cross-system read in
	## this file: fauna run in a scene with no terrain (a character scene tested
	## standalone) answers "nothing in the way" and behaves exactly as before.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null or not terrain.has_method("tower_excludes"):
		return false
	return bool(terrain.call("tower_excludes", spot.x, spot.z, FORMATION_MAX_EXTENT))


func _plan_tower_detour() -> void:
	## Work out, ONCE for this herd, the lateral offset that walks it around the
	## tower — or leave the plan empty when there is nothing to walk around.
	##
	## The geometry is a two-liner because the herd's path is a straight line with
	## a FIXED heading (see _add_animal: the world-space formation offsets are only
	## valid because the heading never changes). `_herd_position` only ever advances
	## along that heading, so the tower's LATERAL coordinate relative to the line —
	## `s` below — is invariant for the herd's whole life and can be computed at
	## spawn and never again. The line misses the disc exactly when |s| is at least
	## the clearance radius, and when it does not, the offset that makes it miss is
	## `s ± keep_out`; the near side (the one that costs less than a full keep_out
	## of berth) is the smaller of the two, and it is also the side the herd is
	## already on, so it is both the cheapest bend and the one that reads as the
	## herd leaning away rather than crossing in front of the building.
	##
	## The clearance covers the CENTRE plus everything that rides on it: this
	## herd's own widest member (`_herd_offset_max`) and the meander, which shares
	## the lateral axis with the detour and would otherwise spend the berth.
	##
	## No physics query, no per-frame work, and nothing here that a missing terrain
	## can trip over — the guards leave the plan empty and the swept-box reflex is
	## then the only steering, exactly as before this existed.
	_tower_bend = 0.0
	_tower_keep_out = 0.0
	_tower_site = Vector3.ZERO
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null or not terrain.has_method("tower_site"):
		return
	var radius: Variant = terrain.get("TOWER_RADIUS")
	if typeof(radius) != TYPE_FLOAT:
		return
	_tower_site = terrain.call("tower_site") as Vector3
	_tower_keep_out = float(radius) + _herd_offset_max + MEANDER_AMPLITUDE \
			+ TOWER_CLEARANCE_MARGIN
	var to_site := _tower_site - _herd_position
	# THE TOWER HAS TO BE AHEAD. A herd that spawns just past the building and
	# walks away from it is already clear of everything it will ever meet: its
	# closest approach to the site is behind it, at spawn. Without this test the
	# lateral check below still fires for it (the spawn rejection only asks about
	# radial distance, so `along` between -keep_out and 0 is a legal spawn), and
	# the herd opens a full berth against a building it is receding from — a
	# visible swerve for nothing, and one that can push it out to the despawn
	# radius early. Found by codex review, 2026-08-30.
	if to_site.x * _herd_heading.x + to_site.z * _herd_heading.z <= 0.0:
		return
	var s := to_site.x * _herd_lateral.x + to_site.z * _herd_lateral.z
	if absf(s) >= _tower_keep_out:
		return                           # the line already walks clear of it
	_tower_bend = s - _tower_keep_out if s >= 0.0 else s + _tower_keep_out


func _update_avoid_target(centre: Vector3) -> void:
	## ONE box the full width of the formation, swept along the heading, turned
	## into ONE signed lateral target the caller eases toward.
	##
	## The box is the width of the MEMBERS, not of the centre's line, and that is
	## the whole reason this works on the case that matters. The first acceptance
	## case is a mountain massif, ~20 m across; the giraffe echelon is ~28 m wide.
	## Angled whiskers off the centre report where the CENTRE can walk, so a herd
	## steers until its middle is clear and drags its outermost giraffe straight
	## through the rock (measured: 100% of aimed trials still clipped, mean
	## penetration 6.0 m).
	##
	## The v1 of this used three PARALLEL rays — centre plus both edges — which
	## fixed the massif but left three thin samples of a 30 m corridor, so an
	## owner playtest walked elephants through the 1–2 m scattered blocks the
	## rays passed between. A swept box has no gaps: anything solid standing in
	## the swath is hit whatever its width. Everything downstream of `tightest`
	## and `side` is unchanged from v1, because the failure modes those two lines
	## were tuned against have not moved.
	##
	## Side choice is still the two edge rays' comparison, unchanged — see
	## _edge_clear for why a swept box cannot answer that question and for the
	## measurement of what happens when you make it try.
	##
	## ponytail: the remaining ceiling is warning DISTANCE, not width — a herd
	## that meets a massif with less than ~35 m of notice (a chunk streaming in
	## late, or a mountain range with no gap) still runs out of room to open the
	## full berth and grazes stone. The upgrade path is a longer AVOID_LOOKAHEAD
	## plus a faster AVOID_EASE_SPEED, both of which cost readability of the
	## swerve; not worth it until somebody sees it happen.
	if _probe_params == null or _probe_shape == null or _ray_params == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var space := viewport.world_3d.direct_space_state
	if space == null:
		return

	# The box brackets the whole formation: as wide as this herd's own widest
	# slot either side of the centre, and started behind it, so the sweep covers
	# the corridor the MEMBERS occupy rather than the line the centre walks.
	var reach := _herd_offset_max + AVOID_EDGE_MARGIN
	var origin := Vector3(centre.x, AVOID_PROBE_HEIGHT, centre.z) \
			- _herd_heading * (reach + AVOID_PROBE_SETBACK)
	var length := AVOID_LOOKAHEAD + reach + AVOID_PROBE_SETBACK
	var want_size := Vector3(reach * 2.0, AVOID_PROBE_BOX_HEIGHT, AVOID_PROBE_BOX_DEPTH)
	if _probe_shape.size != want_size:
		_probe_shape.size = want_size
	# Local X is the lateral axis and local Z the heading, so the box's width
	# spans the formation. lateral × UP == -heading (lateral is the heading
	# yawed 90°), which is what makes this basis right-handed.
	_probe_params.transform = Transform3D(
			Basis(_herd_lateral, Vector3.UP, -_herd_heading), origin)

	var tightest := _swath_clear(space, length)
	if tightest >= length:
		# Open country — the 99% case, and the one that costs the least: the
		# detour unwinds and the herd is back on its migration line, but ONLY
		# once it has walked past what it stepped around (see _avoid_hold_until).
		if _herd_travelled >= _avoid_hold_until:
			_avoid_target = 0.0
		return

	# Only now, with something actually in the way, are the two edge rays cast —
	# so open country (the 99% case) costs ONE query a tick where v1 paid three,
	# and a blocked tick costs the same three it always did.
	#
	# Side choice is v1's rule unchanged, because v1's rule measured 0% clipped
	# and nothing about it was the bug: the clearer edge wins, and ties go to the
	# side already committed to — a herd mid-swerve must never change its mind
	# halfway, and a symmetric massif dead ahead (both edges clear, middle
	# blocked) is exactly a tie.
	var edge := _herd_lateral * reach
	var plus_clear := _edge_clear(space, origin + edge, length)
	var minus_clear := _edge_clear(space, origin - edge, length)
	var side := 1.0 if plus_clear > minus_clear else -1.0
	if absf(plus_clear - minus_clear) < 0.01:
		side = 1.0 if _avoid_target >= 0.0 else -1.0
	# Blocked: walk toward the cap on the clear side. The target is only ever a
	# DIRECTION — AVOID_EASE_SPEED is the rate limiter, and the moment the
	# corridor clears the branch above pulls the target back to zero, so the herd
	# stops exactly as far out as it needed to be rather than at the cap.
	#
	# Grading the push by distance (target = offset + step × how-near-it-is) was
	# tried first and is the version that FAILS: it barely pushes at range, so a
	# herd that needs ~28 m of berth around a massif only starts moving at ~20 m
	# out and arrives half-swerved (measured 92.5% of aimed trials still clipping,
	# 5.1 m mean penetration). Starting the swerve the instant anything enters the
	# corridor is what buys the room.
	_avoid_target = side * AVOID_MAX_OFFSET
	# Hold this berth until the herd has walked past the thing that caused it.
	# THE SWEEP CANNOT TELL US WHEN THAT IS: it points forward, and a herd that
	# has swerved WIDER than the obstacle no longer has the rock inside its box
	# at all. So "all clear" arrives while the obstacle is still abeam, and
	# unwinding there walks the rear of the formation straight back into it
	# (measured: 45% of aimed trials still clipping, every failure on the unwind,
	# with the offset already decayed to 3-7 m at closest approach).
	#
	# The mark is derived from what the sweep actually measured rather than from
	# a guessed constant, so it scales with how far off the obstacle was: travel
	# past where it was seen, plus the formation's own depth so the REAR members
	# clear it too.
	_avoid_hold_until = _herd_travelled + tightest + reach


func _animate_animals() -> void:
	## The ONE animation loop for every live animal — there are no per-animal
	## scripts and no AnimationPlayer anywhere in this feature, exactly like the
	## player's limb sines and the crocodile's _animate_body.
	##
	## Everything here is a pure function of _herd_travelled (metres walked) plus
	## the animal's own random phase offset, so nothing accumulates and nothing
	## drifts: the herd's stride is literally "where its feet are on the ground".
	## The loop allocates nothing per frame — every node reference was cached by
	## the builder that created it, so there is not one get_node() call in here.
	var leg_swing := deg_to_rad(LEG_SWING_DEG)
	var neck_bob := deg_to_rad(NECK_BOB_DEG)
	var trunk_sway := deg_to_rad(TRUNK_SWAY_DEG)

	for animal: Dictionary in _animals:
		# Per-animal phase offset — the herd is never in lockstep, same reason
		# the crocodiles carry an instance_phase.
		var stride: float = _herd_travelled * STRIDE_FREQUENCY + float(animal["phase"])

		# Legs: swing from the hip, diagonal pairs in trot phase (see
		# LEG_PHASE_OFFSETS). The pivot is at hip height with the box hung
		# below it, so this rotation reads as a real limb swing.
		var legs: Array[Node3D] = animal["legs"]
		for i: int in legs.size():
			legs[i].rotation.x = sin(stride + LEG_PHASE_OFFSETS[i]) * leg_swing

		# Body: one shallow dip per footfall, i.e. twice the stride rate. The
		# curve is offset to sit entirely at or ABOVE the Body node's rest
		# height (0 by construction — neither builder moves it), because the
		# legs hang off Body: a bob that dipped below rest would push every
		# foot through the flat ground plane at y = 0.
		var body: Node3D = animal["body"]
		body.position.y = (sin(stride * 2.0) * 0.5 + 0.5) * BODY_BOB_AMOUNT

		# Giraffe neck: a slow bob layered ON TOP of the rest lean (null for
		# elephants — the record simply carries no neck for that species).
		var neck: Node3D = animal["neck"]
		if neck != null:
			neck.rotation.x = float(animal["neck_rest"]) + sin(stride * NECK_BOB_RATE) * neck_bob

		# Elephant trunk: each chained segment sways side to side one
		# TRUNK_SEGMENT_LAG behind its parent, so the chain trails in a soft S.
		# (Empty for giraffes.)
		var trunk: Array[Node3D] = animal["trunk"]
		for i: int in trunk.size():
			trunk[i].rotation.z = sin(stride * TRUNK_SWAY_RATE - float(i) * TRUNK_SEGMENT_LAG) * trunk_sway


func _despawn_herd() -> void:
	## Free every animal, forget the herd, and re-arm the event timer with the
	## steady-state gap — the field goes back to costing one subtraction per
	## frame until the next migration.
	for animal: Dictionary in _animals:
		(animal["root"] as Node3D).queue_free()
	_animals.clear()
	# Forget the tower plan with the herd it was made for. `_spawn_herd` rewrites
	# it anyway, but a stale bend left lying around is a live steering command for
	# anything that drives the herd state directly (fauna_selfcheck's rider row
	# does exactly that), and it would apply a berth for a building that is
	# nowhere near the line it was handed.
	_tower_bend = 0.0
	_event_timer = _rng.randf_range(FAUNA_INTERVAL_MIN, FAUNA_INTERVAL_MAX)
