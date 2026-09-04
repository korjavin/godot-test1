# Field altitude spike — the report

Bead `godot-test1-ope.1`, epic `godot-test1-ope`. This file is the SPIKE's report and
its acceptance artifact: what was built, the answers taken, the red-check list, the
numbers, and the migration order the epic's consumer beads are filed from.

**The flag ships `false`.** `FIELD_ALTITUDE` in `scripts/endless_terrain.gd` and
`alt_enabled` in `assets/shaders/ground.gdshader` are both inert in the committed
tree, and `altitude_selfcheck` asserts that in the merged branch. Nothing below is a
shipped feature. **This is a measurement.**

## What was built

A vertex-displaced heightfield with a CPU twin, four forced-flat authored zones, a
matching ground collision shape, and one self-check that pins all of it.

- **`height_at(x, z)`** in `endless_terrain.gd` — a pure function of `(x, z, run_seed)`
  with `if not FIELD_ALTITUDE: return 0.0` as its first line. Two octaves of the
  project's ONE lattice hash (`_biome_hash2` / `_biome_value_noise`, reused, not
  re-spelled) on altitude's own domain (`ALT_CELL_SIZE` 260 m, `ALT_OFFSET_SALT`, so
  hills never line up with biome edges), scaled by a per-biome amplitude ladder
  (`_alt_amplitude`) that is `fragment()`'s colour chain with six metres instead of
  six colours: desert 2.5, plains 3.5, the noise city band 1.0, forest 6.0, mountain
  22.0, snow 16.0. No RNG draw and no hash-stream consumption. It is pure in
  (x, z, `run_seed`) **except clause 4 of the flat mask**, which reads the cached
  coarse road polyline: the chord nodes are snapped to a stride lattice so the
  corridor is bit-identical from every window centre, but a point that falls off the
  window's end answers differently. The window out-reaches the desktop residency, so
  no loaded chunk ever sees it move — which is what makes baking the collision
  heightmap once per chunk safe. **Promoting the spike means either making the
  corridor position-derived (a distance function of X, or a texture) or re-baking a
  loaded chunk's floor on refresh.**
- **`_alt_flat_mask(x, z, biome)`** — the product of four independent 0..1 smoothstep
  factors, so a point in two zones is flat and never twice flat: Budapest's rect
  (delegated to `BudapestPlan`, +120 m skirt), the HQ disc (`TOWER_RADIUS`, +60 m),
  **every** river band (skirt in FIELD units, `RIVER_HALF_WIDTH * 3.5`, so the flat
  edge and the wading edge are readouts of the same number) and the coin road corridor
  (22 m half-width, 40 m skirt).
- **The GPU twin** in `ground.gdshader` — `field_height()`, `alt_amplitude()`,
  `alt_flat_mask()`, `alt_road_distance()`, gated by `uniform float alt_enabled = 0.0`
  (the `tower_dry_radius = -1.0` inert-default idiom, not an `#ifdef`). `vertex()`
  displaces `VERTEX.y` and recomputes `NORMAL` from two forward differences — three
  `field_height()` evaluations per vertex, the number this spike exists to measure —
  inside `if (alt_enabled > 0.0)`, so the flag-off path costs one compare per vertex.
- **`HeightMapShape3D` ground collision** — 18x18 samples on the visual mesh's own
  grid (`ALT_GROUND_SIDE`, which is `GROUND_SUBDIVISIONS + 2`: Godot's
  `subdivide_width = N` gives N+1 quads and N+2 vertices per side), the
  `CollisionShape3D` uniformly scaled by `alt_ground_cell()` (2.941 m) with the
  stored heights pre-divided by the same factor. Check 5 reads that grid off the
  shipped `PlaneMesh`'s vertex array rather than re-deriving it — the first version
  of this file re-derived it with the builder's own (wrong) formula and certified a
  floor that was a different interpolant of `height_at()`, 5.2 cm off the drawn
  surface at worst. With the flag off it is byte for byte today's chunk-spanning `BoxShape3D`.
- **`scripts/altitude_selfcheck.gd`** (six checks): `flag_is_off`,
  `fp32_parity`, `flat_zones`, `shader_parity`, `ground_collision`,
  `field_is_walkable`.
- **`ground_collision_usec_total`**, a monotone counter on the terrain, surfaced by
  `perf_overlay.gd` (F3) only when non-zero. A spike source exposes a counter, never a
  signal — `chunks_created_total`'s convention.

## The road-corridor answer taken, and why

The bead offered two: flatten the coin road via a small uniform array for the loaded
window, or accept the road on hills. **The array was taken.**

The reason is the measurement, not the aesthetics. The coin road is where the player
walks, so a hilly road puts coin settling, road bosses and road clearance red in the
same run and you cannot tell which breakage is the heightfield and which is the road.
Flat, the road stays the CONTROL — and the red list below is worth reading precisely
because nothing on it is a road artifact.

**The CPU and the GPU read the SAME array.** `_alt_road_segments()` walks the station
cache around the player's own station, packs consecutive centres as `(x1, z1, x2, z2)`
into a `PackedVector4Array` capped at `ALT_ROAD_SEG_MAX` (24), and
`_apply_biome_shader_params()` pushes exactly that array into
`uniform vec4 alt_road_seg[24]`. Parity by construction, not parity by re-derivation.
It refreshes on a chunk-boundary crossing (`_alt_road_refresh()`, the seam
`update_chunks` already runs on), and that refresh re-pushes the material — without
it the CPU's corridor moves while the GPU keeps the previous one, which is ground
drawn flat where the collision heightmap is not.

Three things about it were measured rather than assumed:

- **The stride.** Worst fine-station offset from the coarse chord over 5 seeds and
  ±560 m: stride 4 → 3.6 m, stride 8 → **9.3 m**, stride 16 → 25.2 m. Stride 8 keeps
  the centreline the player walks well inside the 22 m half-width; stride 16 does not.
  `ALT_ROAD_SEG_DEV_MAX = 12.0` records the bound, check 3 asserts it, and the
  assertion was mutation-tested at stride 24 (it fails, naming the stride).
- **The window is in STATIONS, not in X.** The road's heading cap is 78°, so a curving
  stretch advances as little as 1.25 m of X per 6 m station. An X-ordered walk spent
  its whole 24-segment budget 651 m west of the player and left the ground under their
  feet uncorridored (measured; check 3 went red on it).
- **The ceiling, in a `ponytail:` comment.** A hard-curving stretch shortens the
  corridor in X to ~120 m, inside the 250 m desktop residency; and outside the window
  the road is not flattened at all, so a teleport far ahead sees a hilly road for one
  chunk-crossing. Upgrade path: a distance texture, or a wider window.

## The parity argument

The CPU/GPU parity contract (`_biome_noise` / `biome_noise`, the same function in two
languages, edited together) now has one clause more: `height_at()` / `field_height()`.
Four things hold it, and each is an assertion rather than a convention.

1. **One lattice hash.** The altitude field reuses `_biome_value_noise` /
   `_biome_hash2` — the fp32-routed port whose docstring records that the naive fp64
   version moved the waterline by metres. Every new step is `Vector2`-routed for the
   same reason. `ALT_OFFSET_SALT` is pushed to the shader **alone**, not pre-summed
   with `biome_offset`, because fp32 addition is not associative and the shader must
   add the two terms in `height_at()`'s order.
2. **An independent oracle.** `altitude_selfcheck`'s `fp32_parity` re-derives
   `hash2` / `value_noise` as a SECOND implementation, `Vector2`-routed, and compares
   it against the shipped `_alt_value_noise_pair` at 10,000 points: bit-exact on the
   noise, ≤ 1e-4 m on the composed height. Its **negative control** is an fp64 oracle
   in bare scalars, which must DISAGREE at > 1% of points — without that leg the check
   has no teeth.

   **Its ceiling, stated because a reader will otherwise over-read it.** The oracle is
   a hand transcription held current by the same edited-together rule the parity
   contract already runs on — nothing in the suite *parses* a GLSL function body, so an
   edit to `hash2`, `value_noise`, `alt_amplitude` or `field_height` inside the shader
   is invisible to it (`shader_parity` covers uniform names, pushed values, declared
   defaults and the array packing only). And the routing is strict fp32 inside `hash2`;
   `value_noise`'s smootherstep and its three blends, and the amplitude ladder's
   `lerpf`/`smoothstep` rungs, are f64 on both sides of the comparison, so those share
   a rounding rather than eliminating it. Measured residual against a true fp32 model:
   ~2–5 µm at the 22 m mountain amplitude, three orders under the 1 mm the collision
   heightmap is asserted to. It is a bound, not a proof — and it is a bound a consumer
   bead that tightens a skirt should re-measure rather than inherit.
3. **Text parity both ways.** `shader_parity` is `budapest_selfcheck._check_parity`'s
   idiom: every `alt_*` uniform DECLARED in the shader must be pushed by
   `endless_terrain.gd`, and every one pushed must be declared, matched as a
   declaration regex rather than a substring. `ALT_ROAD_SEG_MAX` in the shader must be
   ≥ the GDScript's. Its value leg is **derived, not listed** — a pushed `alt_foo`
   whose upper-cased name is an `endless_terrain.gd` constant must equal it — so a
   uniform added tomorrow is covered the day it lands, and the three that cannot
   follow the convention are named in the code with reasons. Mutation-tested: dropping
   one push and re-packing the road array as `(x, z, dx, dz)` both go red.
4. **The floor is the drawn surface.** `GROUND_SUBDIVISIONS` became a const because
   "16" typed in two places is the one way the collision grid and the visual grid
   drift; `ground_collision` asserts the heightmap's un-scaled samples equal
   `height_at` at the corresponding world points to ≤ 1e-3.

## The red-check list

### How the suite was run

Every `scripts/*_selfcheck.gd` in the glob (36 files), one process each, exactly as
CI judges them: a check is GREEN only when it exits 0 **and** printed `SELFCHECK OK`
**and** logged no `SCRIPT ERROR`. Godot exits 0 on a runtime error, so the exit code
alone is not a verdict.

Three runs: flag off, flag on (flipped locally, never committed), flag off again.

| run | green | red |
|---|---|---|
| `FIELD_ALTITUDE = false` | 36 / 36 | — |
| `FIELD_ALTITUDE = true` | 34 / 36 | `altitude_selfcheck`, `chunk_stream_selfcheck` |
| `FIELD_ALTITUDE = false` (after the flip back) | 36 / 36 | — |

The flag-off runs bracket the flip and agree, so the flip is clean and the flag-off
path is inert — which is the branch's merge condition.

### The red list

| check | verdict | first failure | consumer it guards | migration size |
|---|---|---|---|---|
| `altitude_selfcheck` | RED **by design** | `FIELD_ALTITUDE is true in the committed tree — the spike ships false (see the flag's docstring)` | the spike's own merge condition: the flag ships false, `alt_enabled` is pushed as 0.0, the ground shape is a `BoxShape3D` and the timed heightmap block is never entered | none — this check is written to be red exactly while the flag is on locally. Its six checks report failures ONLY where they assert the flag itself: `flag_is_off` entirely, `shader_parity`'s off-leg (which re-pushes with `alt_force = false` and demands `alt_enabled == 0.0`) and `ground_collision`'s flag-off leg (which demands a `BoxShape3D` and a zero timer). Every flag-ON leg of all six passed |
| `chunk_stream_selfcheck` | RED | `safety-ring chunk (-1, -1) is in active_chunks but has no ground collision box` (all 9 ring chunks) | **the ground floor is a chunk-spanning `BoxShape3D`** — `_has_ground_collision` at `scripts/chunk_stream_selfcheck.gd:312` measures the real shape, and a `HeightMapShape3D` is not one | **small** — the helper becomes "a `BoxShape3D` spanning the chunk, or a `HeightMapShape3D` of `ALT_GROUND_SIDE` × `ALT_GROUND_SIDE` samples covering it"; one helper, both branches, no other assertion in that file moves. **Spell it `ALT_GROUND_SIDE`, never `GROUND_SUBDIVISIONS + 1`** — that is the exact off-by-one recorded above, and re-typing it here would certify a floor 5.2 cm off the drawn surface a second time |

### The finding that matters more than the red list

**Only the two checks that read the GROUND SHAPE ITSELF went red.** Every flat-world
consumer the plan expected to fail stayed green — coin settling (`prop_selfcheck`,
`enemy_spawn_selfcheck` check 14), road stations at y = 0 (`enemy_spawn_selfcheck`
check 11), crocodile gravity settle (`enemy_spawn_selfcheck`, `boss_selfcheck`),
block bases (`prop_selfcheck`, `landmark_selfcheck`), the spawn point,
`wade_selfcheck` and `minimap_selfcheck`.

That is not the mask saving them; it is the spike's scope. `height_at()` has
**exactly one production consumer** — the per-chunk `HeightMapShape3D` in
`_ensure_chunk_ground` — so every other system still computes its y the way it did
yesterday. Those checks assert today's y = 0 behaviour against code that still
produces y = 0, and the mismatch between a coin at y = 1.0 and a floor now 2 m below
it is **invisible to all of them**.

Two consequences for the migration, and both are load-bearing:

- **The red list is not a to-do list.** It names two files. The epic's consumer list
  is a dozen systems, and the suite does not currently protect eleven of them.
- **Every consumer migrated needs its check TAUGHT about height first**, or it will
  certify the migration silently. The order in Task 7 is written against the consumer
  list, never against this table.

`budapest_selfcheck`, `tower_site_selfcheck`, `tower_shell_selfcheck`,
`tower_interior_selfcheck`, `tower_lift_selfcheck`, `tower_selfcheck` and
`capture_selfcheck` staying green **is** a real result: those zones are forced flat by
`_alt_flat_mask` and a red one there would have been a mask bug. So is
`wade_selfcheck` — the river bands are clause 3 of the same mask.


## The numbers

### Measured headless

| number | value | how |
|---|---|---|
| `HeightMapShape3D` build, per chunk | **2,741 µs** (9 chunks, 24,672 µs total) | `altitude_selfcheck` check 5, `ground_collision_usec_total` |
| `height_at()` per call | **~8.5 µs** (324 calls per chunk — `ALT_GROUND_SIDE`² = 18², the mesh's real vertex grid) | the same, divided out |
| the synchronous safety ring, one WORLD (RE)BUILD | **~25 ms in ONE frame** | 9 ring chunks × 2,741 µs |
| the same, per ordinary walking boundary crossing | **0 µs** | `update_chunks` STEP 3 skips a chunk already in `active_chunks`, and `_ensure_chunk_ground` early-returns for one anyway — at `render_distance = 5` the whole `SYNC_RING` 3×3 is already inside the previous 11×11 |
| what walking DOES pay | **~2.7 ms on each of 11 frames** per crossing (7 on web) | the newly-in-range chunks are grounded inside `create_chunk`, which `_process` drains one per frame |
| max height delta per metre, ±5 km box | **0.591 / 0.557 / 0.644** over three seeds | check 6, against a 1.0 (45°) bound |
| the same, mountain band only | **0.502 / 0.457 / 0.361** | check 6 |
| the same, on the road corridor's SKIRT | **0.385 / 0.197 / 0.167** | check 6 — walked as a curve, because the ±5 km box essentially never lands on a 40 m ramp |
| **the same, on a RIVER BANK — the field's real worst** | **0.789 / 0.705 / 0.824** | check 6, rejection-sampled to 10,000 hits per seed |
| jump apex, for comparison | 3.6125 m | `player_controller`, printed beside it |

Two of those are findings and not just numbers:

- **The 25 ms frame is the spike's headline cost — but it is paid on a world
  (RE)BUILD, not on walking.** `update_chunks` gives the safety ring its GROUND
  synchronously because the floor is the whole fall-through guarantee, and the
  heightmap build lands inside that synchronous path. Nine chunks land in one frame
  only when the ring is built from nothing: startup, `new_run()`, and
  `build_ring_now()` from a join or an F2/F8 teleport — or when the drain is already
  backlogged. An ordinary one-chunk walking crossing grounds **zero** chunks
  synchronously (the 3×3 ring is already inside the previous 11×11 and
  `_ensure_chunk_ground` is idempotent); what it pays instead is **2.7 ms added to
  each of the 11 one-chunk-per-frame drain steps**, which is the number consumer 1
  actually has to budget against and the one that decides whether this is a hitch or
  a sustained frame-time floor. Both are **a migration finding, not something the
  spike fixes** — the counter exists to make them visible. The obvious answers (fewer
  samples than the visual grid, a cached noise row, building the shape off the frame)
  are all consumer-1 work below.
- **The field is walkable, but the headroom is ~18% and it is a RIVER BANK that
  spends it — not the mountains and not the road.** The skirts are the steepest
  ground in the field by construction (a mask ramping a band's whole amplitude to
  zero across itself), and the four are not comparable: three ramp over an authored
  40-120 m, while the river's `ALT_RIVER_SKIRT_K` ramps over **0.0175 of biome
  field**, whose width in metres is that divided by the local
  `|grad _biome_noise|` — about 5-10 m carrying the full 3.5 m plains amplitude.
  That is the tightest skirt in the game and the number the 1.0 bound is really
  measured against (0.824 worst of three seeds). It is also the one figure a
  consumer bead cannot read off a constant in the source, because it has no metre
  value: **widening the bank means raising `ALT_RIVER_SKIRT_K`**. The mountain band
  is mild by comparison (0.502 worst) — so the residual mountain-impassability risk
  is still a gentle rise against a massif wall and **not** a ramp over it. That is a
  bound, not a proof: a rise that lifts the ground beside a 4.0 m
  `MOUNTAIN_MIN_LAYER_HEIGHT` block by 2 m halves the wall, and blocks still sit at
  y = 0. Consumer 9 below owns it.

### Structurally known, flag on vs flag off

- **Draw calls: unchanged.** No node is added and no material is added — the ground
  is the same one shared `PlaneMesh` and the same material it always was, and the
  displacement is a vertex-stage edit. The per-chunk collision shape is a different
  `Shape3D` on the same `StaticBody3D`.
- **Node count: unchanged.** Same reason.
- **Vertex count: unchanged** (324 per chunk). What changes is the work per vertex:
  **three `field_height()` evaluations** (the displacement plus two forward
  differences for the normal), in `vertex()` only — ~15,876 evaluated vertices per
  frame at the web build's 49-chunk residency, ~47,628 `field_height()` calls. **One
  such call is three terms, and the noise is not the big one:**
  - `alt_value_noise_pair()` — 2 octaves, 8 `hash2`;
  - `biome_noise()` — a third octave, 4 more `hash2` (and `vertex()` has already
    computed this exact value into `v_biome` one line above, so one of the four per
    vertex is redundant — see the migration list);
  - `alt_flat_mask()` → **`alt_road_distance()`, a loop of up to
    `ALT_ROAD_SEG_MAX` = 24 clamped point-to-segment projections**, run at every
    vertex in the world including the kilometres of field where the window holds no
    road at all.

  So the per-vertex bill is ~36 `hash2` **and up to 72 segment projections**, and
  the corridor loop is of the same order as all the noise put together. That is the
  one number the web reading is needed for and the reason it is needed: a headless
  run cannot see the vertex stage at all, so nothing in this document bounds it.
- **Flag off: one compare per vertex** and nothing else, because the block is guarded
  rather than multiplied by zero.

### Web F3 readings — PENDING, and they need a human

**Not filled in by this agent.** F3 is an on-screen overlay in a browser; there is no
headless path to it, and the plan files these under Post-Completion for exactly that
reason. The procedure, so the reading is reproducible and the pair is comparable:

```bash
mkdir -p build/web && godot --headless --export-debug "Web" build/web/index.html
./serve.sh          # WASM needs http://
```

Then press **F3** and record FPS, frame time, draw calls and node count at three
places — the open field, **Budapest (F2)** and **the HQ (F8)** — first with
`FIELD_ALTITUDE = false`, then with it `true`. Both F2 and F8 are `OS.is_debug_build()`
only, which is why the reading is taken on `--export-debug`: CI and the deployed build
export `--export-release`, where the teleports are dead by design. The before/after
PAIR is comparable on the debug template; the absolute numbers are not the deployed
build's.

| place | flag | FPS | frame ms | draw calls | nodes |
|---|---|---|---|---|---|
| open field | off | | | | |
| open field | on | | | | |
| Budapest (F2) | off | | | | |
| Budapest (F2) | on | | | | |
| HQ (F8) | off | | | | |
| HQ (F8) | on | | | | |

Budapest and the HQ are in the report **as controls**: both are forced-flat zones, so
their rows should show the vertex cost of a guarded-but-taken branch and nothing else.
A frame-time difference there that the open field does not show is a mask bug.

Screenshots of each biome with altitude on are the same Post-Completion step.

## The migration order

The epic's consumer list, dependencies first. **Size is the migration's, not the
spike's.** The self-check column is the check that must be TAUGHT ABOUT HEIGHT first
and then proves the consumer — see the finding above: eleven of these are green today
against code that still writes y = 0, so migrating one without teaching its check
means the suite certifies the migration silently.

| # | consumer | size | proved by | why here in the order |
|---|---|---|---|---|
| 1 | **The ground scheme itself** — the shared `PlaneMesh` + per-chunk collision, and the **25 ms synchronous ring** | **huge** | `chunk_stream_selfcheck` (its `_has_ground_collision` helper first — the one real red) | everything below stands on the floor this bead defines; the frame cost is the gate on the whole epic |
| 2 | **`height_at` parity + the flat zones** — this spike, promoted | **medium** | `altitude_selfcheck` | already built and pinned; promoting it is deleting the flag, and it is what every consumer below calls |
| 3 | **Block bases and every `create_box` caller** | **huge** | `prop_selfcheck`, `landmark_selfcheck`, `batch_selfcheck` | ~600 call sites plus `landmark_builders`' contract; every consumer below settles onto or beside a block, so a floating block poisons their measurements |
| 4 | **Coin settling** — `_settle_coin_y`, `COIN_GROUND_HEIGHT` | **medium** | `prop_selfcheck`, `enemy_spawn_selfcheck` check 14 | perches on a climbable top, which is 3's output; coins are the headline score, so this is the first one a player feels |
| 5 | **Crocodile / boss gravity settle** | **medium** | `enemy_spawn_selfcheck`, `boss_selfcheck` | species settle to flat ground; the boss territory leash and the LOD radii are XZ and stay XZ |
| 6 | **Road stations and the coin road** | **medium** | `enemy_spawn_selfcheck` check 11 | the spike keeps the road flat as a control; migrating it is choosing to give it up, and it must come after 4 and 5 because road coins and road bosses ride it |
| 7 | **The spawn point + the `SPAWN_SAFE_RADIUS` mirror** | **small** | `chunk_stream_selfcheck` | one y, two files (`endless_terrain` and `player_controller`) kept in step |
| 8 | **Wading** — `is_on_floor()` AND river-at-XZ | **small** | `wade_selfcheck` | `is_river_at` is XZ-only by documented contract; elevated ground over a river band would wade. Cheap **only** while rivers stay a forced-flat zone — the moment they do not, this is medium |
| 9 | **Mountain impassability** | **medium** | `enemy_spawn_selfcheck` + a NEW check (there is none today) | jump apex 3.6125 m under `MOUNTAIN_MIN_LAYER_HEIGHT` 4.0, and no skill touches `JUMP_VELOCITY`; a massif's blocks sit at y = 0 while the ground beside them rises. Needs 3 first, because "the wall's base" is a block base |
| 10 | **The minimap's flat assumptions** | **small** | `minimap_selfcheck` | it reads the world in XZ; last because nothing depends on it |
| 11 | **The ground plane's shadow flag** | **small** | nothing today | `_ensure_chunk_ground` sets `SHADOW_CASTING_SETTING_OFF` on the comment "a flat ground plane can only ever shadow itself", which stops being true the moment it is displaced — hills would need to shade valleys and today they cannot. **Not a free flip**: it is a shadow-pass cost, which is exactly the cost that produced Budapest's no-shadow ruling (`godot-test1-8gw.9`, 19 ms/frame), so it must be MEASURED on web and not assumed. Visual only, so it can come last |
| 12 | **The ground plane's CULL VOLUME** | **done in the spike** | `altitude_selfcheck` check 5 | Item 11's neighbour, on the same reasoning one step further: the displacement is a VERTEX SHADER and the renderer culls on the MESH's AABB, which for the shared flat `PlaneMesh` is `chunk_size × 0 × chunk_size`. Without a per-instance `custom_aabb` a chunk whose flat quad falls outside the frustum takes its 22 m hilltop with it and the hillside pops at the screen edge — and it would have quietly understated the draw-call column of every reading in this report. `_ensure_chunk_ground` now sets one from `ALT_AMP_MAX` in the flag-on branch only; check 5 asserts the box CONTAINS each chunk's real height range, which is what keeps `ALT_AMP_MAX` bound to the amplitude ladder rather than hand-picked |

| 13 | **The vertex stage's own cost** | **medium** | nothing — it is a shader-internal edit and every parity assertion is on the VALUE, which does not move | Two waste terms, both named in the per-vertex bill above and both left alone here because the spike's job was to measure, not to tune. (a) `field_height()` recomputes `biome_noise(w)`, which `vertex()` already has in `v_biome` — split it into a `field_height_b(vec2 w, float b)` worker plus a one-line wrapper, pass `v_biome` for the centre sample and keep the wrapper for the two offset samples; the GDScript twin needs **no** edit, so note the asymmetry beside `height_at`. (b) `alt_flat_mask()`'s 24-iteration `alt_road_distance()` loop runs three times per vertex — evaluate the mask ONCE per vertex and reuse it for both finite differences, which costs a slightly less exact normal on a skirt and nothing anywhere else. Both are worth roughly half the vertex-stage bill between them; **do neither until the web F3 pair below says the vertex stage is what hurts** |

Two rules the order encodes:

- **1 → 2 → 3 is a spine, not a preference.** The floor, then the function, then what
  stands on it. 4–10 can be scheduled in any order that respects their own notes.
- **Every bead in this list carries its check edit in the same commit.** The finding
  above is the argument: a consumer migrated against a check that still asserts y = 0
  is a green build and a broken game.

## The deliberate NON-consumers

These migrate by **not** migrating, and each for a reason already in the codebase.

- **Budapest.** Clause 1 of the flat mask holds the whole rect at y = 0, and the
  authored Danube and every `DRY_RECTS` row live inside it, so they need no clause of
  their own. The city is authored, streamed and sliced on the chunk grid; a heightfield
  under it would put a 268 m Parliament on a slope. `budapest_selfcheck` stayed green
  with the flag on and that is the assertion.
- **The tower shell and interior.** Clause 2 holds the HQ disc, sharing `TOWER_RADIUS`
  rather than restating a distance — the same disc `is_river_at` is already masked
  under. The building is manager-parented, hand-planned once and forever, and its
  verticality is interior-only by the tower epic's own ruling. All six `tower_*` checks
  plus `capture_selfcheck` stayed green.
- **The crowd and the traffic.** Ambience, outside the determinism contract, drawn as
  MultiMeshes with feet at y = 0 — and they only ever walk **Budapest's street grid**,
  which is inside clause 1. They never see field altitude.
- **Fauna.** One herd at a time, manager-parented, no collision, feet at y = 0 by
  construction, and it already **plans** around the one obstacle it cannot probe. If
  the field ever rises under a herd this becomes a small bead; it is not one now.
- **Rivers.** Clause 3, with the skirt in FIELD units so the flat edge and the wading
  edge are the same number. `is_river_at` stays XZ-only and water stays at y = 0 —
  which is what makes consumer 8 small.
- **Projectiles, weather, the LOD manager, the hunt director.** All XZ or transient;
  none reads ground height.
