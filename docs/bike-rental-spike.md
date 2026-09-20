# Rental-bike spike — the report

Bead `godot-test1-z2yv.4`, epic `godot-test1-z2yv`. This file is the SPIKE's report and
its acceptance artifact: the six questions the bead asked, answered with numbers read
out of the code at `a3aae26`, each carrying its `file:line`. No mechanics ship here —
no code, no scene, no self-check, no `.glb`. The follow-up beads at the end are filed
(`godot-test1-z2yv.5`–`.9`); this document files nothing itself.

## 1. The speed lattice

The lattice (`scripts/player_controller.gd:19`, `:23`, `scripts/piglet_crocodile_ai.gd:51`):

| what | value | where |
|---|---|---|
| `WALK_SPEED` | 5.0 | `scripts/player_controller.gd:19` |
| `RUN_SPEED` | 10.0 | `scripts/player_controller.gd:23` |
| `DUCK_SPEED` | 2.5 | `scripts/player_controller.gd:27` |
| `WADE_RUN_MIN_SPEED` (run floor in a river) | 9.0 | `scripts/player_controller.gd:50` |
| `CHARACTER_SPEED` windman / primm / teibi / phoboman | 1.0 / 1.15 / 0.9 / 1.05 | `scripts/player_controller.gd:4299-4304` |
| → runs | 10.0 / 11.5 / **9.0 (slowest, Teibi)** / 10.5 | derived |
| → walks (no `gait_mult` on the walk branch, `:1819`) | 5.0 / 5.75 / 4.5 / 5.25 | derived |
| `RUN_SPEED_MULT_MAX` (all passives) | 1.20 → fastest passive run 13.8 | `scripts/progression.gd:110` |
| Speed Burst (outside the cap) | ×1.30 → ×1.56 composite, 17.9 m/s | `scripts/progression.gd:137-145` |
| `WINDMAN_AIR_SPEED` | 25 (`WALK_SPEED * 5.0`) | `scripts/player_controller.gd:4315` |
| `MAX_CHASE_SPEED` | 8.5 | `scripts/piglet_crocodile_ai.gd:51` |
| `SIM_RADIUS` | 45.0 | `scripts/crocodile_lod_manager.gd:63` (cited at `scripts/piglet_crocodile_ai.gd:91`) |

`chase_speed` per row, `scripts/species_table.gd`: crocodile 5.5 (`:82`), sand_viper 5.5
(`:366`), timber_wolf 6.8 (`:609`), frost_bear 6.0 (`:827`), mountain_cougar 7.8
(`:1091`), alley_hound 6.8 (`:1324`), titan 3.0 (`:1504`), green_dragon 5.5 (`:1763`),
hydra 5.5 (`:1997`), naga 5.5 (`:2103`), roc 5.5 (`:2216`), clown 3.5 (`:2352`),
hunter_robot 6.5 (`:2549`), tower_guard 5.6 (`:2830`). Every one is below 8.5, and 8.5
is below the slowest run (9.0) — the lattice holds with 0.5 m/s to spare at the tight
end.

The burst arm (`_behave_burst`, `scripts/piglet_crocodile_ai.gd:1663`) multiplies
`burst_factor` AFTER the 8.5 clamp (`:874-876`, then `:1172-1173`; the cycle math lives
in `CrocSteering.burst_cycle_factor`, `scripts/croc_steering.gd:261`):

- mountain_cougar: `burst_distance` 4.0 (`:1213`), `recover_distance` 3.0 (`:1220`),
  `burst_factor` 1.3 (`:1226`), `recover_factor` 0.55 (`:1234`) → cycle average
  V × 7.0 / (4.0/1.3 + 3.0/0.55) = V × 0.8205 = **6.97 m/s** at V = 8.5; instantaneous
  peak 8.5 × 1.3 = **11.05**.
- alley_hound: 2.5 / 2.0 / 1.35 / 0.6 (`:1440-1460`) → average 0.868 × 8.5 =
  **7.38 m/s**, peak 8.5 × 1.35 = **11.48** (9.18 at the nominal 6.8).
- leap arms (`_behave_leap`, `:2314`) peak at clamp × `leap_speed_factor`
  (`scripts/species_table.gd:1887`, `:2295`): 8.5 × 1.2 = **10.2**.

Proposal: **`BIKE_SPEED = 14.0`**, one absolute const beside `WINDMAN_AIR_SPEED`, on
its own branch of `calculate_current_speed()` (`scripts/player_controller.gd:1758`)
ABOVE the walk `else` — it never multiplies `WALK_SPEED` and takes no `gait_mult`
(the bike is a leveller, not a passive). Margins: +5.0 (56 %) over the slowest run
9.0; +2.5 over Primm's 11.5; +0.2 over a maxed-passive Primm 13.8; under the burst
run 17.9 and Air Rush 25 (the ability stays the fastest thing in the game). 14.0 is
above BOTH burst peaks (11.05 / 11.48), so the burst-arm question dissolves: not even
the instant can close a gap, and the cycle averages (6.97 / 7.38) lose ~7 m/s every
second. A stationary rider is simply caught, like a stationary walker. The FOV ramp
(`:1722-1728`, WALK → `WINDMAN_AIR_SPEED`) picks the bike up for free. The lattice
guard (`scripts/enemy_spawn_selfcheck.gd:256-263`, `:349-351`) reads `WALK_SPEED`/runs
off `player_controller.gd`; it must gain `BIKE_SPEED > slowest run` and
`BIKE_SPEED > every burst peak`.

THE RULING: `BIKE_SPEED` 14 m/s — ok.

## 2. The price

- `TELEPORT_COIN_COST` 15 (`scripts/player_controller.gd:4044`), charged `:4162-4163`,
  refunded on a failed jump `:4171-4173`, refusal toast "Not enough coins" /
  "Travel costs %d coins." (`:4199-4200`, through `landmark_toast.announce`).
- A hop is `WAYPOINT_SPACING` 450 m (`scripts/terrain_waypoints.gd:135`).
- Road income: `road_coin_spacing` 6.0 m (`scripts/endless_terrain.gd:612`),
  `road_coin_slots` 3 (`:630`), `road_coin_chance` 0.4 (`:631`), average per slice
  3 × 0.4 × 0.7 = 0.84 (`:623`) → **0.14 coin/m = 140 coins/km**; gems 4 %
  (`scripts/coin_road.gd:159`) worth 10 (`scripts/coin.gd:29`) → EV 1.36 per coin →
  **~190 coins/km** on the road. The road ends at `ROAD_TERMINAL_X` 1450 m
  (`scripts/coin_road.gd:192`).
- Bike strips sit `BIKE_ROAD_CLEARANCE` 14 m off the road
  (`scripts/terrain_bike_paths.gd:410`), so **riding earns nothing** — a 450 m leg
  forgoes ~85 coins of pick-ups; that opportunity cost is the real fare. Strip:
  `BIKE_PATH_WIDTH` 2.4 (`:538`), station 5 m (`BIKE_STATION_SPACING`, `:363`), spur
  reach 24 stations × 5 m = 120 m (`:380-389`); trunks run anchor-to-anchor (HQ,
  waypoints, Budapest gate, corridor landmarks — `scripts/bike_network.gd:101-102`);
  racks only at anchors a trunk touches.
- Time on a 450 m leg: 32 s on the bike vs 50 s running (Teibi) vs 90 s walking; the
  teleport is instant for 15.
- 2 coins = 10 m of road income: the rental is a "why not" and the strip is what
  sells it.

THE RULING: price 2 COINS at mount, no refund; no coins → refuse with the "Not enough
coins" toast.

## 3. The dismount — transient ability state, not a world object

`_reset_ability_states()` (`scripts/player_abilities.gd:1127`, forwarded
`scripts/player_controller.gd:4713`) is reached from: `_pay_coin_setback`
(coin-tax contact) `:2462`, `set_active_character` `:2569`, `_respawn_in_place`
`:2921`, `_enter_prison` `:3039`, `_exit_prison` `:3069`, `_end_run` `:3111`,
`reset_position` `:3662`, `join_at` `:3818`, `_jump_to` (waypoint hop and debug
teleport) `:4027`, and the HQ knockback `:2451-2462` (gated on
`TowerInterior.inside_walls()`). `_sheltered()` is `:4461`. Windman's dance breaks on a
step or a hop (`:1631-1639`) — the precedent for "jump = dismount".

The fauna giraffe (`scripts/fauna_manager.gd:12-16`, `:24-46`) is the "world object you
stand on" precedent: no mount state, walking off is the dismount — it works only
because the animal moves itself. A bike does not, so a world object would need a body,
a seat, MP ownership and chunk-unload survival for nothing.

Decision: transient state on the player — `is_riding` + `bike_range_left` (metres,
distance budget ~5 km, decremented by horizontal distance ridden, NOT a timer) cleared
inside `_reset_ability_states()`; plus two edges: a jump press dismounts,
`_sheltered()` flipping true dismounts (no bike on the HQ ramps). Riding off the
strip: nothing happens — no strip detection; the flat world (y = 0), the massifs and
the deep channel already bound it.

THE RULING: transient state, cleared on every ending above — EXCEPT `set_active_character`
KEEPS the bike: the reset there (`:2569`) must not clear the two bike fields; the new
hero mounts the same bike with the same `bike_range_left`.

## 4. Multiplayer — purely local, one presence bit, teammates see the bike

Presence packet (`scripts/mp_manager.gd:4082-4095`): `p y c s g cc dd` + optional `ab`
(= `ability_visual_state()` `scripts/player_controller.gd:5025`; bits
`ABILITY_BIT_FLYING..DANCE` = 1<<0..1<<4 `:5012-5022`). `PRESENCE_HZ` 15
(`scripts/mp_manager.gd:61`), `MAX_PRESENCE_PACKETS_PER_PEER` 8 (`:66`). The codec
clamps `ab` to 0..255 and treats a missing field as 0 (`scripts/mp_codec.gd:425-432`).
`RemoteAvatar` (`scripts/remote_avatar.gd:3-40`) joins no group, has no body, is
parented to the MP manager and drives the same rig; the FLYING bit already selects
`_rig.air()` (`:525-531`); per-hero gait via `PlayerAnimation.gait_for` (`:332`).

Decision: `ABILITY_BIT_BIKE = 1 << 5` in `ab` — no verb, no parser, no handler, no
codec change (32 is inside the 0..255 clamp). Remote: a branch beside FLYING →
`_rig.pedal()` and the bike mesh shown under the avatar. Ceiling: the presence budget
above (15 Hz, 8/peer/frame); at 14 m/s that is 0.93 m per packet, inside the avatar's
smoothing. Coins are already per-peer (`cc`). Nothing gates the herd, so not
master-simulated; never seeded.

THE RULING: teammates MUST see the bike — the presence bit + bike mesh under the remote
avatar satisfies that (same-build peers all run the deployed web build; the "old build
sees a runner" degrade is moot but must never apply to a same-build peer).

## 5. The pose — one `pedal()` for all four heroes

`update_character_animation` (`scripts/player_animation.gd:478-560`) has 5 branches
(jumping / sidestep / landing / walking / idle) plus ability overlays
(`_apply_stink_pose` and siblings `:692-762`). `GAITS` is per hero (DEFAULT, windman,
primm, teibi, phoboman `:95-175`) but holds amplitudes and cadence only.
`scripts/hero_rig_skeleton.gd` has ONE `GAIT_SKIN` table (`:172`), bones by name
(`:146-156`, the 23-bone MakeHuman rig), and every pose is one function for all
heroes: `air` `:538`, `slump` `:525`, `dance` `:614`, `sidestep` `:644`; `measure()`
`:677` is how self-checks read it. Decision: one rig function `pedal(phase, amount)` —
thighs at seat angle ± a pedal sine, knees folded, forearms to the bars, torso leaning
— one dispatch branch locally, one in `remote_avatar.gd`; per-hero flavour comes free
from `GAITS.stride_rate` as cadence. ≈ 80 lines rig + 15 animation + 10 remote + a
`gait_selfcheck` probe over all four heroes.

THE RULING: one `pedal()` pose for all four heroes.

## 6. Geometry — ridden = generated .glb, parked = CUBEs in the rack

`export_faceted()` `scripts/predator_parts.py:500` (flat normals, hand-rolled maths for
CI byte-compare `:527-539`); `build.yml`'s rebuild loop names two hero-prop generators
(`.github/workflows/build.yml:524`: `generate_windman_fan generate_primm_swords`),
output under `assets/models/characters/<hero>_parts/`
(`scripts/generate_windman_fan.py:127`), rows in
`assets/models/characters/PROVENANCE.md`. `ChunkBatch.BoxKind {CUBE, SPHERE, CONE,
CYLINDER, ROCK, WEDGE}` `scripts/chunk_batch.gd:127`. Primm's swords are named
MeshInstance nodes in the hero scene toggled by `_set_primm_swords_drawn`
(`scripts/player_abilities.gd:683`) — the precedent for a mesh that travels with the hero.

A ridden bike moves with the player, so it can never be chunk-batch content (a chunk
frees its children on unload and a MultiMesh instance has no owner). Decision: ridden
= `generate_bike.py` → `bike.glb` through `export_faceted`, ≤ 300 faces, third name in
the loop, a MeshInstance3D child under `CharacterModel` toggled like the swords;
parked = 2-3 CUBE silhouettes per rack through `create_box`, inside the bike family's
batch slice, world-tied to the rack, no footprint of their own (they sit inside the
rack's r = 1.4).

The rack: rail 2.2 × 0.08 × 0.12 m at 0.5 m
(`scripts/terrain_bike_paths.gd:714-717`) + 3 uprights 0.09 × 1.0 × 0.09 (`:718-721`),
all CUBE; one footprint `{radius 1.4, top 1.0, climbable false}` (`:726-727`); one bare
`Node3D` per rack in group `bike_stand` (`:709`), metas `anchor: int` (index into
`BikeNetwork.anchors()`) and `pos: Vector3` (`:707-708`), named `BikeStand<anchor>`
(`:710`, `:2508`), parented to the owning chunk.

THE RULING: 2-3 CUBE bike silhouettes at every rack AND the ridden bike is a generated
.glb.

## Rulings 2026-09-20

1. `BIKE_SPEED` 14 m/s — ok.
2. Price 2 COINS at mount, no refund.
3. No coins → refuse with the "Not enough coins" toast.
4. The ride is bounded by DISTANCE, ~5 km "or similar", not by time (a
   `bike_range_left` metres budget decremented by distance ridden, not a timer).
5. Hero switch KEEPS the bike — `set_active_character` must NOT clear it (a deliberate
   exception to "transient state clears on switch"); every other ending still
   dismounts: respawn / capture / tax contact / prison in-out / run end / hop / join /
   HQ knockback, plus jump and `sheltered()`.
6. TEAMMATES MUST SEE THE BIKE — presence bit + bike mesh under the remote avatar
   satisfies that (same-build peers all run the deployed web build; the "old build
   sees a runner" degrade is moot but must never apply to a same-build peer).
7. One `pedal()` pose for all four heroes.
8. 2-3 CUBE bike silhouettes at every rack (chunk content, inside the family's batch
   slice, no footprint of their own — inside the rack's) AND the ridden bike is a
   generated .glb.

## Follow-up beads

- **godot-test1-z2yv.5** — `generate_bike.py` + `bike.glb` (export_faceted, third name
  in build.yml's loop, PROVENANCE row, ≤ 300 faces, no gameplay).
- **godot-test1-z2yv.6** — rig `pedal()` + animation branch + `gait_selfcheck` probe via
  `rig.measure()` on all four heroes.
- **godot-test1-z2yv.7** — the rental: mount at a `bike_stand` marker, 2 coins with the
  toast, `BIKE_SPEED` in the lattice + `enemy_spawn_selfcheck` extended, 5 km distance
  budget, dismount edges, hero switch keeps it, the glb child. Depends on .5 and .6.
- **godot-test1-z2yv.8** — MP mirror: `ABILITY_BIT_BIKE` in `ab`, `remote_avatar.gd`
  branch + bike mesh, `mp_selfcheck` round-trip, no codec change. Depends on .7.
- **godot-test1-z2yv.9** — parked CUBE silhouettes at racks, 2-3 per rack, inside the
  bike family's batch slice, world-tied. Independent.

## Open questions

1. **Exact `BIKE_RANGE_METRES`: 5000 or similar?** The ruling says ~5 km "or similar".
   Recommendation: 5000 m flat — one 450 m hop is 9 % of a budget, a full budget is 11
   hops, trivially memorable. Default the developer takes: 5000.
2. **Mount reach: how close to the `bike_stand` marker may the player mount?**
   Recommendation: reuse the waypoint circle idiom (enter edge on proximity, no key) at
   ~2.5 m — inside the rack's 1.4 m footprint plus arm's reach, outside accidental
   brush-past. Default: 2.5 m proximity, no key.
3. **May a rider enter water?** The deep channel pushes the player out and
   `WADE_RUN_MIN_SPEED` (`scripts/player_controller.gd:50`) floors wading at 9.0.
   Recommendation: the bike keeps its 14.0 on the wading band (it is wheels, not legs)
   but the deep channel still ejects — i.e. the channel is a dismount-and-swim edge,
   not a ride-through. Default: eject at the deep channel.
