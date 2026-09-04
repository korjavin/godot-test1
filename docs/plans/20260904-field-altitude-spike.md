# Field altitude SPIKE — a vertex-displaced heightfield behind `FIELD_ALTITUDE`

## Overview

Bead `godot-test1-ope.1` (huge, P3), first child of epic `godot-test1-ope`. Owner
2026-09-04: *"we might consider to migrate from flat map to some not-flat with
mountains"*. This ACTIVATES the epic **as a SPIKE, not the migration**.

The deliverable is a **measurement**, not a shipped feature:

1. a working vertex-displaced heightfield with CPU/GPU parity,
2. the four authored zones (Budapest, the HQ disc, every river band, the coin road
   corridor) held at y = 0 so nothing authored migrates,
3. **the RED-CHECK LIST** — every `scripts/*_selfcheck.gd` run with the flag ON,
   named, with the flat-world consumer each one guards,
4. **the web numbers** — F3 frame time / draw calls, flag off vs on,
5. **the written migration order** of the epic's consumer list with a size per
   consumer and which self-check proves each.

**The whole diff lives behind `const FIELD_ALTITUDE: bool = false`.** With the flag
false the world is byte-for-byte today's flat world and every self-check is green;
that is the merge condition and it is a hard requirement of every task below.

## Context (from discovery)

Files involved:

- `scripts/endless_terrain.gd` (11,807 lines) — `_biome_hash2` / `_biome_value_noise`
  / `_biome_noise` (the fp32 parity port, ~line 9230), `biome_at` (9306),
  `is_river_at` (9340), `in_budapest` (9406), `tower_site` (9431), `tower_excludes`
  (9456), `_apply_biome_shader_params` (3337), `_get_shared_ground_mesh` (3178),
  `_ensure_chunk_ground` (3838, the ground plane + its **BoxShape3D**),
  `create_chunk` (3904), `_road_lateral_distance` (10021), `_road_station` (9835),
  `_road_first_k_at_or_after_x` (9843), `_road_terminal_k` (9872), `_road_spacing`
  (9815).
- `assets/shaders/ground.gdshader` (343 lines) — `hash2`, `value_noise`,
  `biome_noise`, `city_river_distance`, `vertex()`, `fragment()`.
- NEW `scripts/altitude_selfcheck.gd`.
- NEW `docs/field-altitude-spike.md` (the report — the actual acceptance artifact).

Patterns to reuse (rung 2 of the ladder — do NOT reinvent any of these):

- **The fp32 routing.** `_biome_hash2` routes every step through `Vector2` because
  `Vector2` stores `real_t` = float32 and that is the only fp32 cast GDScript has.
  The height function's CPU half MUST do the same. **Do not "simplify" any line back
  to scalar arithmetic** — the docstring records that the naive fp64 version moved the
  waterline by metres.
- **The inert-default idiom.** `tower_dry_radius = -1.0` and
  `city_rect = vec4(0,0,-1,-1)` leave their masks OFF for a material nobody fed.
  Every new uniform here follows it: default = "no altitude".
- **The point-to-segment loop.** `city_river_distance()` in the shader and
  `BudapestPlan.danube_distance()` on the CPU are the same clamped projection. The
  road corridor is that shape again — copy it, do not invent a second spelling.
- **The uniform-push seam.** `_apply_biome_shader_params()` is the ONE function
  feeding the ground material, and `budapest_selfcheck`'s `_check_parity` /
  `_check_parity_packing` read the shader as TEXT plus drive that one function. The
  new parity check copies that shape.
- **The self-check chassis.** `_initialize()` starts with
  `Sentinel.isolate_user_state()`, every check ends with `Sentinel.done("<name>")`
  (and before every early exit), and the report site calls `Sentinel.finish(self)`
  instead of printing `SELFCHECK OK` + `quit(0)`. See `scripts/tower_site_selfcheck.gd`
  for the smallest complete example.

## Decisions already made — do NOT re-open these

These are settled by the bead and by this plan. An agent that re-litigates them is
burning the budget the measurement needs.

- **The flag is a compile-time-ish `const`, not an `@export`.** `const FIELD_ALTITUDE:
  bool = false` at the top of `endless_terrain.gd`, beside the other tunables. Every
  altitude code path is gated on it; with it false, `height_at()` early-returns `0.0`
  before touching any noise, `_ensure_chunk_ground` builds today's `BoxShape3D`, and
  `_apply_biome_shader_params` pushes `alt_enabled = 0.0`.
- **The GPU gate is a uniform, not an `#ifdef`.** `uniform float alt_enabled = 0.0;`
  multiplies the whole displacement. Default 0 = inert, the `tower_dry_radius = -1`
  precedent, so a material nobody fed draws exactly the world it always drew.
- **The road corridor IS flattened, via a shared coarse polyline pushed as a uniform
  array.** The bead offers two answers ("a small uniform array for the loaded window"
  or "accept the road on hills"). **Take the array.** Reason: the coin road is where
  the player walks, so a hilly road makes coin settling, road bosses and road
  clearance all go red at once and you cannot tell which breakage is the heightfield
  and which is the road. The array keeps the road as the CONTROL. Say so in the report.
- **The CPU and the GPU read the SAME road array**, built once by
  `_alt_road_segments()` and cached on the terrain. Parity by construction beats
  parity by re-derivation.
- **Normals are recomputed** by two finite differences in `vertex()` (3 height evals
  per vertex). A displaced plane with flat normals reads as a bug, and the cost of
  the extra two evals is exactly one of the numbers this spike exists to measure.
- **The ground mesh stays 16x16.** 17x17 vertices over a 50 m chunk is 3.125 m
  spacing, which is plenty for a 260 m-wavelength field, and it makes the collision
  heightmap grid IDENTICAL to the visual grid for free. Do not raise the subdivision.
- **Props, blocks, coins, crocodiles and the spawn point are NOT fixed.** The bead
  says so explicitly: *"the spike may leave props floating (measure, do not fix)"*.
  Every one of those is a MIGRATION bead filed from this report. Touch none of them.
- **No entity count changes. No behaviour changes with the flag off.**

## Invariants that MUST survive (read CLAUDE.md before you start)

- **The CPU/GPU parity contract, one clause wider.** `_biome_noise` /`biome_noise`
  are the same function in two languages, edited together. The height function joins
  them under exactly the same rule: same constants, same fp32, edited together,
  measured by a check.
- **Determinism.** `height_at` is a pure function of `(x, z, run_seed)` — no RNG
  draw, no hash-stream consumption, no state. A revisited chunk regenerates
  byte-identically.
- **The authored zones do not move.** Budapest and the tower interior must be
  byte-identical with the flag ON — their zones are forced flat, and
  `budapest_selfcheck` / `tower_*_selfcheck` are the assertion. If they go red with
  the flag on, the flat mask is wrong; **fix the mask, never the check**.
- **The ground-first floor guarantee.** `update_chunks` gives the safety ring its
  GROUND synchronously because the floor is the whole fall-through promise. The
  heightmap build lands inside that synchronous path — so it must be MEASURED
  (a monotone `usec` counter, the `chunks_created_total` convention: a spike source
  exposes a counter, never a signal).
- **`is_river_at` stays XZ-only** and rivers stay at y = 0. Wading is untouched
  because the river band is a forced-flat zone.
- **Mountain impassability.** Jump apex is 3.6125 m under `MOUNTAIN_MIN_LAYER_HEIGHT`
  4.0. The heightfield must not hand a player a ramp over a massif wall — the field's
  max slope is measured and asserted walkable, and any residual risk is a REPORT item.

## Development Approach

- **Testing approach: Regular** (code, then the check that proves it). This project
  has no test framework — correctness is **headless self-checks**. "Write tests" below
  always means "add checks to `scripts/altitude_selfcheck.gd`", never a new framework.
- Run `godot --headless --path . --script res://scripts/altitude_selfcheck.gd` after
  each task. A check passes only if it exits 0 **and** prints `SELFCHECK OK` **and**
  logs no `SCRIPT ERROR` — Godot exits 0 on a runtime error, so the exit code alone is
  not a verdict.
- Match the surrounding comment density. This codebase is written to be read: every
  new constant gets the note that says why it is that number.
- Complete each task fully before the next. Update this plan file when scope changes.

## Progress Tracking

- Mark completed items `[x]` immediately.
- New tasks get a ➕ prefix; blockers get ⚠️.

## Implementation Steps

### Task 1: The height function, CPU half, behind the flag

- [x] add `const FIELD_ALTITUDE: bool = false` to `scripts/endless_terrain.gd` beside
      the biome constants, with a docstring saying it is a SPIKE flag: false = today's
      flat world, byte for byte, and that is the merge condition
- [x] add the altitude constants next to it, each with its reason:
      `ALT_CELL_SIZE = 260.0` (wavelength, deliberately not `BIOME_CELL_SIZE` so hills
      do not line up with biome edges), `ALT_OFFSET_SALT = Vector2(37.0, 71.0)` (its
      own domain shift on top of `biome_offset`, so altitude never correlates with the
      biome field — the "own salt" rule one feature along), `ALT_DETAIL_SCALE = 3.1`,
      `ALT_DETAIL_WEIGHT = 0.3`, and the six per-biome amplitudes in metres:
      `ALT_AMP_DESERT = 2.5` (dunes, low), `ALT_AMP_PLAINS = 3.5` (gentle),
      `ALT_AMP_CITY = 1.0` (the NOISE city band — near flat, it is meant to be paved),
      `ALT_AMP_FOREST = 6.0`, `ALT_AMP_MOUNTAIN = 22.0`, `ALT_AMP_SNOW = 16.0`
- [x] add `_alt_value_noise_pair(p: Vector2) -> float` — two octaves,
      `_biome_value_noise(p) * (1 - ALT_DETAIL_WEIGHT) + _biome_value_noise(p *
      ALT_DETAIL_SCALE + Vector2(17.0, 31.0)) * ALT_DETAIL_WEIGHT`, **reusing the
      existing `_biome_value_noise` / `_biome_hash2`** — one lattice hash in the whole
      project, which is what keeps the port honest
- [x] add `alt_amplitude_at(world_x, world_z) -> float`: the SAME chained-smoothstep
      ladder `fragment()` already uses on `v_biome`, over the six amplitudes instead of
      six colours, on the same `_biome_noise` value with the same
      `BIOME_*_MAX` thresholds and the same `BIOME_BLEND`. Chained low-to-high, exactly
      the shader's order; a copy of the chain shape, never a new classification
- [x] add `height_at(world_x, world_z) -> float`: `if not FIELD_ALTITUDE: return 0.0`
      first line; then `p = Vector2(world_x, world_z) / ALT_CELL_SIZE + biome_offset +
      ALT_OFFSET_SALT`, `n = _alt_value_noise_pair(p)`, signed height
      `(n - 0.5) * 2.0 * alt_amplitude_at(...)`, times `_alt_flat_mask(...)` (Task 2).
      **Every step routed through `Vector2` for fp32**, the `_biome_hash2` rule
- [x] add the check file `scripts/altitude_selfcheck.gd` with the Sentinel chassis
      (`Sentinel.isolate_user_state()` first line of `_initialize()`, `Sentinel.done()`
      per check and before every early exit, `Sentinel.finish(self)` at the report site)
      and **check 1 — THE FLAG IS OFF**: with `FIELD_ALTITUDE` false, `height_at`
      returns exactly `0.0` at 10,000 points spread over ±5 km on three seeds
- [x] add **check 2 — fp32 PARITY**: an INDEPENDENT strict-fp32 oracle written inside
      the check straight off the GLSL text (`hash2`/`value_noise` re-derived,
      Vector2-routed), compared against the shipped `_alt_value_noise_pair` at 10,000
      points — bit-exact on the noise, `<= 1e-4 m` on the composed height. Plus a
      **negative control**: an fp64 oracle (bare scalars) must DISAGREE at >1% of
      points, or the check has no teeth. This is the assertion the bead calls "the
      acceptance"
- [x] run `godot --headless --path . --script res://scripts/altitude_selfcheck.gd` —
      must print `SELFCHECK OK`, exit 0, no `SCRIPT ERROR`

### Task 2: The four forced-flat zones (CPU half)

- [x] add `_alt_flat_mask(world_x, world_z, biome_value) -> float` — the PRODUCT of four 0..1
      factors, each a smoothstep skirt so the ground never steps. Returns 1.0 (no
      flattening) in open field. One function, four clauses, each commented with the
      thing it protects
- [x] clause 1 — **BUDAPEST**: 0 inside `BudapestPlan.rect()`, rising to 1 at
      `ALT_CITY_SKIRT = 120.0` m outside it. Use the standard axis-aligned box
      distance (`d = max(rect_min - p, p - rect_max)`, outside distance
      `length(max(d, 0))`). Delegate the rect to `BudapestPlan`, never restate it —
      `in_budapest()`'s rule. NOTE in the comment: the authored Danube and every
      `DRY_RECTS` row live INSIDE the rect, so they need no clause of their own
- [x] clause 2 — **THE HQ DISC**: 0 within `TOWER_RADIUS` of `tower_site()`, rising to
      1 at `+ ALT_TOWER_SKIRT = 60.0` m. Shares `TOWER_RADIUS`; states no distance of
      its own — the shell's rule
- [x] clause 3 — **EVERY RIVER BAND**: 0 where `absf(_biome_noise(x,z) - RIVER_LEVEL)
      < RIVER_HALF_WIDTH`, rising to 1 at `RIVER_HALF_WIDTH * ALT_RIVER_SKIRT_K`
      (`= 3.5`). **The skirt is in FIELD units, not metres**, and that is the point:
      the flat edge and the wading edge are then readouts of the same number, so
      `is_river_at`'s XZ-only contract survives and water stays at y = 0
- [x] clause 4 — **THE COIN ROAD CORRIDOR**: 0 within `ALT_ROAD_FLAT_HALF = 22.0` m of
      the coarse road polyline (Task 3), rising to 1 at `+ ALT_ROAD_SKIRT = 40.0` m.
      22 m clears `road_width_max/2` and every road-clearance constant
      (`MOUNTAIN_ROAD_CLEARANCE` 24 is the widest, so the corridor sits just inside it)
- [x] add **check 3 — THE FLAT ZONES HOLD**: with the flag forced ON in the check,
      2,000 points sampled inside Budapest's rect, inside the HQ disc, inside sampled
      river bands and inside the road corridor must return exactly `0.0`; plus the
      **negative control** — points one full skirt outside each zone must be non-zero
      somewhere, or "flat everywhere" would pass
- [x] run the check — `SELFCHECK OK`, exit 0, no `SCRIPT ERROR`

  NOTE (deviation, deliberate): the mask takes the `_biome_noise` value as a third
  argument rather than re-deriving it, matching the shader twin's
  `alt_flat_mask(vec2 w, float b)` signature exactly — `height_at` already has the
  value in hand for the amplitude ladder, and the vertex shader spends it three
  times over for the finite-difference normals.

  NOTE (deviation, deliberate): clause 4 currently reads the shipped
  `_road_lateral_distance` (station centres 6 m apart — a polyline in all but
  name) instead of a corridor of its own. Task 3 replaces it with the coarse
  cached polyline the GPU can also read; a `ponytail:` comment on the clause
  records the ceiling. Check 3's road leg walks the real station cache either
  side of the origin, so it will keep asserting the same thing after the swap.

### Task 3: The road corridor as a shared coarse polyline

- [x] add `ALT_ROAD_SEG_MAX = 24`, `ALT_ROAD_SEG_STRIDE = 8` (every 8th station ~48 m
      apart; the road's heading cap makes the chord deviation far under the 18 m
      between `ALT_ROAD_FLAT_HALF` and `ALT_ROAD_SKIRT`, so a coarse polyline flattens
      the same corridor a fine one would) and `ALT_ROAD_WINDOW = 560.0` m (just over
      the desktop residency half-width, `render_distance` 5 × `chunk_size` 50)
      — plus `ALT_ROAD_SEG_DEV_MAX = 12.0`, the deviation bound the stride buys
- [x] add `_alt_road_segments(center_x: float) -> PackedVector4Array` — walks the
      station cache from `center_x - ALT_ROAD_WINDOW` to `+ ALT_ROAD_WINDOW` by
      `ALT_ROAD_SEG_STRIDE`, packing consecutive centres as `(x1, z1, x2, z2)`, capped
      at `ALT_ROAD_SEG_MAX`. Stops at `_road_terminal_k()` — **cap 5 of the road's
      consumers**; east of T there is no road to flatten around, and
      `spawn_approach_coins_in_chunk`'s corridor is inside Budapest's rect anyway
- [x] cache it on the terrain (`_alt_road_segs`) and refresh it **on a chunk-boundary
      crossing only** (the same seam `update_chunks` already runs on), never per frame
- [x] add `_alt_road_distance(world_x, world_z) -> float` — the clamped
      point-to-segment loop over that cache, the SAME projection as
      `BudapestPlan.danube_distance()` / the shader's `city_river_distance`
- [x] wire clause 4 of `_alt_flat_mask` to it
- [x] document the **known spike ceiling** in a `ponytail:` comment: outside the
      window the corridor is not flattened, so a teleport far ahead sees a hilly road
      for one chunk-crossing until the window refreshes. Upgrade path: a distance
      texture, or widening the window
- [x] extend check 3's road leg to sample the corridor at 40 stations either side of
      the player and assert exactly `0.0`
- [x] run the check


  NOTE (deviation, deliberate): the plan's stride claim was MEASURED rather than
  assumed. Worst fine-station offset from the chord over 5 seeds and ±560 m:
  stride 4 → 3.6 m, stride 8 → 9.3 m, stride 16 → 25.2 m. Stride 8 keeps the
  centreline the player walks well inside `ALT_ROAD_FLAT_HALF` (22 m); stride 16
  does not. `ALT_ROAD_SEG_DEV_MAX = 12.0` records the bound and check 3 asserts
  it (mutation-tested at stride 24: it fails, naming the stride).

  NOTE (deviation, deliberate): the window is taken in STATIONS around the
  player's own station, not as the X range `ALT_ROAD_WINDOW` names. The road's
  heading cap is 78°, so a curving stretch advances as little as 1.25 m of X per
  6 m station — an X-ordered walk from `center_x - ALT_ROAD_WINDOW` spent its
  whole 24-segment budget hundreds of metres west of the player and left the
  ground under their feet uncorridored (measured: 651 m off, check 3 red).
  `ALT_ROAD_WINDOW` is now 600.0 and is the `_road_extend_to_x` hint, sized so
  the station 96 west of the player is already cached on a straight road. The
  ceiling this leaves — a hard-curving stretch shortens the corridor in X to
  ~120 m, inside the 250 m desktop residency — is in the `ponytail:` comment.

  NOTE: check 3's road leg already walked 40 stations either side, so the last
  checkbox was extended rather than added: it now drives the shipped
  `_alt_road_refresh()` seam (without it the check would sample an empty window
  and pass for the wrong reason), asserts the chord deviation, prints it as a
  report number, and shrinks its lateral offset to
  `ALT_ROAD_FLAT_HALF - ALT_ROAD_SEG_DEV_MAX` so it can keep demanding exactly
  `0.0` instead of a tolerance.
### Task 4: The GPU twin — vertex displacement in `ground.gdshader`

- [x] add the uniforms, all with INERT defaults: `alt_enabled = 0.0`,
      `alt_offset = vec2(0.0)`, `alt_cell_size = 260.0`, `alt_detail_scale`,
      `alt_detail_weight`, the six `alt_amp_*`, `alt_city_skirt`, `alt_tower_skirt`,
      `alt_river_skirt_k`, `alt_road_flat_half`, `alt_road_skirt`, plus
      `uniform vec4 alt_road_seg[ALT_ROAD_SEG_MAX]` and `alt_road_seg_count = 0`
      (`const int ALT_ROAD_SEG_MAX = 24;` — the `CITY_SEG_MAX` precedent)
- [x] add `float alt_road_distance(vec2 p)` — the copy of `city_river_distance`'s loop
      over `alt_road_seg`
- [x] add `float alt_amplitude(float b)` — the six-amplitude chained smoothstep, the
      exact twin of `alt_amplitude_at`, ladder in the same order with the same
      `biome_blend`
- [x] add `float alt_flat_mask(vec2 w, float b)` — the four clauses' twin. Budapest's
      rect comes from the EXISTING `city_rect` uniform (already pushed — do not add a
      second one); the HQ disc from the EXISTING `tower_dry_center` /
      `tower_dry_radius`; the river from `b` and the existing `river_level` /
      `river_half_width`; the road from `alt_road_distance`
- [x] add `float field_height(vec2 w)` — the twin of `height_at`, gated by
      `alt_enabled`
- [x] in `vertex()`: after `v_biome` is computed, `VERTEX.y += field_height(world_xz)`,
      and recompute `NORMAL` from two finite differences of `field_height` at
      `± ALT_NORMAL_EPS` (1.0 m) — 3 evals total per vertex. Guard the whole block
      with `if (alt_enabled > 0.0)` so the flag-off path costs one compare
- [x] **update the shader's header comment**: the "THE GROUND IS ALWAYS FLAT (y = 0)"
      paragraph is now conditional. Say the parity contract covers `field_height` too,
      and that with `alt_enabled = 0` the file draws exactly the world it always drew
- [x] extend `_apply_biome_shader_params()` to push every `alt_*` uniform — one
      function feeding the ground material stays the rule — with `alt_enabled` reading
      `FIELD_ALTITUDE`
- [x] add **check 4 — TEXT PARITY, BOTH WAYS**: the `budapest_selfcheck._check_parity`
      idiom. Every `alt_*` uniform declared in `ground.gdshader` must be pushed by
      `endless_terrain.gd` (matched as a DECLARATION regex, not a substring), and every
      `alt_*` uniform pushed must be declared. `ALT_ROAD_SEG_MAX` in the shader must be
      `>=` the GDScript's. Plus the **packing check** (`_check_parity_packing`'s idiom):
      drive the shipped `_apply_biome_shader_params()` and read the array back, asserting
      `alt_road_seg[i]` unpacks as `(x1, z1, x2, z2)`
- [x] run the check

  NOTE (deviation, deliberate): two uniforms the plan's list does not name were
  added, both to keep a number from being written down twice in two languages —
  `alt_detail_shift` (ALT_DETAIL_SHIFT, the detail octave's own domain shift; a
  GLSL literal here would be the one constant of the pair the parity check could
  not see) and `alt_offset` carrying ALT_OFFSET_SALT ALONE rather than
  `biome_offset + salt` pre-summed, because fp32 addition is not associative and
  the shader must add the two terms in height_at()'s order.

  NOTE: the normal is TWO FORWARD differences reusing the vertex's own height —
  3 field_height() evaluations per vertex, which is the number the plan asks for.
  A centred +/- pair would be 4 and buys nothing at a 260 m wavelength.

  NOTE: `_alt_road_refresh()` now re-pushes the material (through
  `_apply_biome_shader_params`, so ONE function still feeds the ground material).
  Without it the CPU's corridor window moves on a chunk-boundary crossing while
  the GPU keeps the previous one — ground drawn flat where the collision
  heightmap is not.

  NOTE: check 4's value leg is DERIVED, not listed: a pushed `alt_foo` whose
  upper-cased name is an endless_terrain.gd constant must equal it, so the naming
  convention is the contract and a uniform added tomorrow is covered the day it
  lands. The three that cannot follow it are named in the code with reasons.
  Mutation-tested: dropping one push and re-packing the road array as
  (x, z, dx, dz) both go red (3 failures).

### Task 5: Ground collision — `HeightMapShape3D` per chunk, measured

- [x] in `_ensure_chunk_ground`, keep TODAY'S `BoxShape3D` path unchanged when
      `FIELD_ALTITUDE` is false (byte for byte — this is the merge condition)
- [x] when true, build a `HeightMapShape3D`: `map_width = map_depth = 17` (identical to
      the visual mesh's 16x16 subdivisions, so the floor you stand on is the floor you
      see), `map_data` a `PackedFloat32Array` of `height_at` over the chunk grid.
      `HeightMapShape3D` cells are 1 unit, so scale the `CollisionShape3D` uniformly by
      `chunk_size / 16.0` and pre-divide the stored heights by the same factor —
      uniform scale, no non-uniform-shape warning. Comment the arithmetic
- [x] add a monotone `ground_collision_usec_total: int` counter on the terrain,
      accumulated around the heightmap build. **A spike source exposes a counter, never
      a signal** — `perf_overlay.gd` polls `chunks_created_total` the same way
- [x] surface it in `scripts/perf_overlay.gd` beside the existing counters, but ONLY
      as one extra line and only when the counter is non-zero (flag off ⇒ invisible)
- [x] add **check 5 — THE FLOOR IS THE FIELD**: with the flag ON, a built chunk's
      ground body carries a `HeightMapShape3D`; its sampled grid values, un-scaled,
      equal `height_at` at the corresponding world points to `<= 1e-3`; and with the
      flag OFF the shape is still a `BoxShape3D` of `Vector3(chunk_size, 0.1,
      chunk_size)`. Print the measured per-chunk build cost in µs — that number is a
      report deliverable, not an assertion
- [x] add **check 6 — THE FIELD IS WALKABLE**: sample the max height delta per metre
      over 20,000 points on three seeds; assert it stays under 1.0 (45°), and PRINT the
      max, the mountain-band max and the jump apex (3.6125 m) beside it so the
      mountain-impassability consumer has a number in the report
- [x] run the check

  NOTE (measurement, a Task 7 report number): the heightmap costs **2,610 us per
  chunk** (9 chunks, 23,492 us) — 289 `height_at()` calls at ~9 us each, and the
  9-chunk synchronous safety ring a boundary crossing floors is therefore ~23 ms
  in ONE frame. That is a spike, it is exactly what the counter exists to show,
  and it is a MIGRATION finding, not something the spike fixes.

  NOTE: max slope measured **0.591 / 0.557 / 0.644 m per metre** over three seeds
  (mountain band 0.502 / 0.457 / 0.361) against the 1.0 bound — the field is
  walkable everywhere with ~35% headroom, so the residual mountain-impassability
  risk is a gentle rise against a massif wall and not a ramp over it.

  NOTE (deviation, deliberate): `GROUND_SUBDIVISIONS` was added as a const and
  `_get_shared_ground_mesh` now reads it. The plan says the collision grid is
  "identical to the visual mesh's 16x16 subdivisions"; that identity was a 16
  typed in two places, which is the one way the floor and the drawn surface drift.

### Task 6: The RED-CHECK LIST — run the whole suite both ways

- [x] with `FIELD_ALTITUDE = false`, run **every** `scripts/*_selfcheck.gd` as CI does,
      one at a time, capturing rc, whether `SELFCHECK OK` was printed and whether any
      `SCRIPT ERROR` appeared. **All 36 must be green.** Any red one is a bug in this
      branch — fix it, the flag-off path is meant to be inert
- [x] flip `FIELD_ALTITUDE = true` **locally, without committing the flip**, and run
      the whole suite again the same way. Record for EACH check: green/red, the first
      failure line, and **which flat-world consumer from the epic's list it guards**
- [x] flip it back to `false` and re-run the suite once to prove the flip is clean
- [x] write the red list into `docs/field-altitude-spike.md` as a table:
      check | verdict | first failure | consumer it guards | migration size
- [x] expected reds, to be confirmed or refuted by measurement, NOT assumed:
      `chunk_stream_selfcheck` (the ground box at :161), coin settling
      (`_settle_coin_y` and `COIN_GROUND_HEIGHT` in `prop_selfcheck` /
      `enemy_spawn_selfcheck` check 14), road stations at y = 0
      (`enemy_spawn_selfcheck` check 11), crocodile gravity settle
      (`enemy_spawn_selfcheck`, `boss_selfcheck`), block bases
      (`prop_selfcheck`, `landmark_selfcheck`), the spawn point, `wade_selfcheck`
      (`is_on_floor()` AND river-at-XZ), `minimap_selfcheck`. **`budapest_selfcheck`,
      `tower_*_selfcheck` and `capture_selfcheck` MUST STAY GREEN** — their zones are
      forced flat and that is the whole point of Task 2; a red one there is a mask bug


  NOTE (measurement, Task 6): 36/36 green with the flag off, **34/36 with it on**,
  36/36 again after the flip back. The only reds are `altitude_selfcheck` (red BY
  DESIGN with the flag on — it asserts the spike ships false) and
  `chunk_stream_selfcheck` (`_has_ground_collision` measures a chunk-spanning
  `BoxShape3D`, which a `HeightMapShape3D` is not). **Every other expected red came
  back GREEN**, because `height_at()` has exactly one production consumer — the
  chunk ground shape — so every other flat-world system still writes y = 0 and its
  check still asserts y = 0. The red list is therefore NOT a migration to-do list;
  see `docs/field-altitude-spike.md`.

### Task 7: The report — web numbers and the migration order

- [x] write `docs/field-altitude-spike.md`. Sections: what was built; the road-corridor
      answer taken and why; the parity argument; the RED-CHECK LIST table from Task 6;
      the web numbers; the migration order
- [x] **the migration order**, the epic's consumer list, each with a size
      (small/medium/huge), the self-check that proves it, and the ORDER, dependencies
      first. Suggested spine, to be revised by what the reds actually say:
      1. ground mesh + collision (the scheme itself) — **huge** — `chunk_stream_selfcheck`
      2. `height_at` parity + flat zones (this spike, promoted) — **medium** — `altitude_selfcheck`
      3. block bases and every `create_box` caller — **huge** — `prop_selfcheck`, `landmark_selfcheck`
      4. coin settling (`_settle_coin_y`, `COIN_GROUND_HEIGHT`) — **medium** — `prop_selfcheck`, `enemy_spawn_selfcheck` 14
      5. crocodile / boss gravity settle — **medium** — `enemy_spawn_selfcheck`, `boss_selfcheck`
      6. road stations and the coin road — **medium** — `enemy_spawn_selfcheck` 11
      7. the spawn point + `SPAWN_SAFE_RADIUS` mirror — **small** — `chunk_stream_selfcheck`
      8. wading (`is_on_floor()` + XZ) — **small** — `wade_selfcheck`
      9. mountain impassability — **medium** — `enemy_spawn_selfcheck`, a new check
      10. the minimap's flat assumptions — **small** — `minimap_selfcheck`
- [x] record the deliberate NON-consumers and why: Budapest, the tower shell and
      interior, the crowd, the traffic and fauna — all inside forced-flat zones or
      manager-parented, so they migrate by NOT migrating
- [x] add a `CLAUDE.md` note — ONE short paragraph under "Biomes are decoration over a
      flat world" saying the flag exists, defaults false, and points at the report.
      Do not rewrite the section: the flat world is still what ships

  NOTE (Task 7): the report is written in the plan's order — what was built, the
  road-corridor answer, the parity argument, the red-check list (Task 6's table,
  unchanged), the numbers, the migration order, the deliberate non-consumers. The
  migration spine was REVISED against what the reds actually said: the suggested
  order's items 1 and 2 stand, but `create_box` block bases move UP to 3 (four of
  the consumers below settle onto a block, so a floating block poisons their
  measurements), and consumer 9 gains "a NEW check, there is none today". Sizes are
  otherwise the plan's.

  NOTE (Task 7, web numbers): the F3 pair is PENDING and is written into the report
  as an empty table plus the exact reproducible procedure. F3 is an on-screen
  overlay in a browser and there is no headless path to it — the plan files it
  under Post-Completion for that reason. What IS in the report is the
  headless-measurable half (the 2,610 us/chunk heightmap, the ~23 ms synchronous
  ring, the slope bounds) and the structurally-known half (draw calls, node count
  and vertex count all unchanged; three `field_height()` evaluations per vertex,
  ~42,483 per frame at the web build's 49-chunk residency). Budapest (F2) and the
  HQ (F8) rows are named as CONTROLS: both are forced-flat, so a frame-time
  difference there that the open field does not show is a mask bug.

### Task 8: Verify acceptance

- [ ] `git diff origin/master --stat` — confirm the diff touches only
      `scripts/endless_terrain.gd`, `assets/shaders/ground.gdshader`,
      `scripts/altitude_selfcheck.gd`, `scripts/perf_overlay.gd`, `CLAUDE.md`,
      `docs/field-altitude-spike.md` and this plan
- [ ] confirm `FIELD_ALTITUDE` is `false` in the committed tree
- [ ] confirm `alt_enabled`'s shader default is `0.0`
- [ ] re-run the full `scripts/*_selfcheck.gd` glob one final time — all green
- [ ] `godot --headless --path . --import` runs clean

## Technical Details

**The height function, both languages (the twin — edit together):**

```
p    = world_xz / ALT_CELL_SIZE + biome_offset + ALT_OFFSET_SALT
n    = value_noise(p) * 0.7 + value_noise(p * 3.1 + (17, 31)) * 0.3   // 0..1
amp  = chained smoothstep over (biome field) -> six per-biome metres
h    = (n - 0.5) * 2.0 * amp                                          // signed
out  = h * flat_mask(world_xz)                                        // 0 in authored zones
```

**The flat mask** is a product of four independent 0..1 factors — a point in two zones
is flat, never twice flat. Each factor is `smoothstep(inner, outer, distance)` with the
zone's own inner radius and skirt.

**Uniform push:** `_apply_biome_shader_params()` gains the `alt_*` block. It runs from
`_ready()` and `new_run()`; the road array additionally refreshes on chunk-boundary
crossings from `update_chunks`.

**Collision:** `HeightMapShape3D`, 17x17, `CollisionShape3D.scale = Vector3.ONE *
(chunk_size / 16.0)`, `map_data[i] = height_at(...) / (chunk_size / 16.0)`.

## Post-Completion

These need a human at a keyboard and are NOT agent checkboxes. The developer agent
supervising this run does them.

- **Web numbers.** `mkdir -p build/web && godot --headless --export-debug "Web"
  build/web/index.html`, then `./serve.sh`, open it, press **F3**, and record FPS,
  frame time, draw calls and node count at three places — the open field, Budapest
  (F2 teleports there in a debug build) and the HQ (F8) — with `FIELD_ALTITUDE` false
  and again with it true. Both sets go in the report.
- **Screenshots** of each biome with altitude on.
- The consumer beads are filed by the ARCHITECT from this report. Do not file them.
- Do not merge and do not close the bead.
