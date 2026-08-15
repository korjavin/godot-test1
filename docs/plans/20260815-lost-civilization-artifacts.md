# Lost-Civilization Artifacts (rare deterministic landmarks + gem reward)

## Overview

Add rare "lost civilization" artifacts to the endless field: weird, weathered
landmarks that break the monotony of the flat world and reward walking over to
look at them. Roughly **one artifact per ~20 chunks**, placed deterministically,
biased **off the coin road** (never on the road centerline), built entirely from
the existing terrain block primitives so they cost almost nothing to render.

Each artifact:
- is one of **5 distinct code-built shapes** (leaning half-buried monolith with
  glowing rune strips, broken arch of floating stones, circle of tilted standing
  stones around a glowing centre slab, half-buried colossus head with emissive
  eye blocks, spiral of steps to nowhere),
- uses a **weathered grey/mossy palette DISTINCT** from the curated block ramps
  (`RAMP_SANDSTONE_*` / `RAMP_SLATE_*` / `RAMP_MOSS_*`) so it reads as "from
  another age",
- routes **all solid geometry through the existing per-chunk MultiMesh batch +
  the consolidated `BlockCollision` body** (the `create_block`/`create_box` call
  chain) — so an artifact adds **zero** extra draw calls for its stone,
- adds **at most 4 small emissive accent `MeshInstance3D`s** (`cast_shadow` OFF)
  that feed the `glow_enabled` post-process already configured in `main.tscn`,
- scatters **3-5 coins** around its base and places **exactly one gem coin**
  (`coin.gd::make_gem`) at its centre — the incentive to detour off the road,
- is **parented to the chunk mesh**, so it unloads with the chunk (no leaks).

Non-goals (explicitly out of scope): lore UI, pickup systems, new HUD, per-
artifact scenes or asset files, biome logic.

## Context (from discovery)

Files/components involved:
- `scripts/endless_terrain.gd` (~2219 lines) — the ONLY script that changes.
  - `create_chunk()` — builds the chunk mesh, ground body, `block_batch` (visual)
    and `block_body` (`StaticBody3D` named `BlockCollision`), then calls
    `spawn_objects_in_chunk` → `_build_block_multimesh` → crocodiles → bosses →
    `spawn_coins_in_chunk`.
  - `spawn_objects_in_chunk()` / `spawn_feature_structure()` / `spawn_pyramid()` /
    `spawn_wall()` / `spawn_gate()` / `spawn_corridor()` — the existing per-chunk
    feature-structure spawners. They take
    `(rng, half_chunk, obstacles, platforms, block_batch, block_body)` and append
    footprint dicts `{ "pos": Vector3, "radius": float, "top": float,
    "climbable": bool }` to `obstacles`.
  - `create_block()` / `create_box()` — the single funnel every solid block goes
    through: appends `{ "transform": Transform3D, "color": Color }` to
    `block_batch` and hangs a `CollisionShape3D` (BoxShape3D) on `block_body`.
    Currently supports **yaw only** and always picks its colour from the curated
    ramps via 1-3 RNG draws + a discarded roughness draw.
  - `_boss_at(i)` / `spawn_bosses_in_chunk()` — the model for an **independent
    hash stream**: `rng.seed = hash(Vector3i(i, BOSS_SEED, run_seed))`, touching
    no shared RNG.
  - `_road_coins_at(k)` — the other independent-stream model
    (`hash(Vector3i(k, ROAD_COIN_SEED, run_seed))`).
  - `_road_extend_to_x()`, `_road_first_k_at_or_after_x()`, `_road_station(k)` —
    the station cache API used to locate the road near a chunk.
  - `spawn_coins_in_chunk()` — contains the coin **perch/skip rule**: if a coin's
    column overlaps block footprints, find the **tallest** overlapping block;
    perch at `top + COIN_BLOCK_OFFSET` if it is `climbable`, else **skip the
    coin**. Helpers `_block_overlaps()` / `_point_over_block()`.
  - `run_seed` + `new_run()` — per-run seed mixed into every hash stream.
- `scripts/coin.gd` — `make_gem()` must be called **before** the coin enters the
  tree (it uses `get_node("Mesh")`, not the `@onready` var).
- `scenes/main.tscn` — `glow_enabled = true`, `glow_hdr_threshold = 0.85`, so an
  emissive material brighter than that blooms for free.

Related patterns found:
- Per-chunk parenting rule: everything spawned per chunk is a child of the chunk
  `MeshInstance3D` so it is freed on unload.
- Determinism discipline: chunk layout comes from ONE `rng` seeded from
  `hash(Vector3i(chunk.x * 73856093, chunk.y * 19349663, run_seed))`; **its draw
  sequence is load-bearing and must not be disturbed**. Anything new uses its own
  independent hash stream (boss + road-coin pattern) — that is what we do here.
- Shared resource caching: `_get_shared_unit_box_mesh()`, `_get_shared_ground_mesh()`,
  `_get_shared_block_material()` (lazy singletons).
- Teaching-style comments, explicit type hints, tunables as consts/`@export` at
  the top of the script.

Dependencies identified: none new. No new files, no new assets, no scene edits.

## Development Approach
- **Testing approach**: NO unit tests. This is a Godot project with no test
  suite, linter, or build script. The one runnable check this plan leaves behind
  is a **temporary headless determinism script** (Task 8) that asserts the
  placement function is stable within a run and differs across runs; it is run
  once and deleted (no test infrastructure is stood up).
- Complete each task fully before moving to the next.
- Make small, focused changes; one function per task where possible.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility: on a chunk with **no** artifact (19 out of 20)
  the generated world must be **byte-identical** to today's.

## Testing Strategy
- **Unit tests**: none. Do not add unit tests.
- **Integration tests**: none — there is no suite to add to. The determinism
  check in Task 8 is a throwaway headless script, deleted after it passes.
- **E2E tests**: none (the project has no e2e suite).
- Verification is: `godot --headless --path . --import` then
  `godot --headless --path . --quit-after 3` with **no errors/warnings** in the
  output.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope
- Keep plan in sync with actual work done

## What Goes Where
- **Implementation Steps** (`[ ]` checkboxes): all code changes in
  `scripts/endless_terrain.gd` plus the headless verification runs.
- **Post-Completion** (no checkboxes): visual/manual checks that need a human at
  a screen (does it look like a lost civilization, F3 draw-call inspection on a
  real playthrough, web export smoke test).

## Implementation Steps

### Task 1: Add the ARTIFACTS configuration block (constants + palette + export)
- [x] in `scripts/endless_terrain.gd`, add a new **`# ARTIFACTS`** configuration
      section immediately AFTER the existing BOSS CROCODILES const block (keep
      the file's "constants at the top" convention), with a teaching-style
      section comment explaining what an artifact is and why it uses its own hash
      stream
- [x] add `@export var spawn_artifacts: bool = true` (kill switch, mirrors
      `spawn_coins` / `spawn_crocodiles`)
- [x] add rarity + placement consts:
      `ARTIFACT_CHANCE: float = 0.05` (≈1 per 20 chunks, inside the 15-25 target),
      `ARTIFACT_SALT: int = 0xA27_1FA` (arbitrary fixed salt, same spirit as
      `BOSS_SEED` / `ROAD_COIN_SEED`),
      `ARTIFACT_PLACE_TRIES: int = 4` (candidate spots tried before giving up),
      `ARTIFACT_ROAD_CLEARANCE: float = 14.0` (min lateral distance from the road
      centerline — comment that the widest coin band half-width is
      `road_width_max * 0.5 = 10`, so this keeps artifacts clear of the swath
      while still leaving them visible from the road),
      `ARTIFACT_EDGE_MARGIN: float = 12.0` (keeps the whole artifact inside its
      chunk so nothing straddles a seam)
- [x] add the **weathered palette** consts with a comment stating explicitly that
      these are deliberately DISTINCT from `RAMP_SANDSTONE_*` / `RAMP_SLATE_*` /
      `RAMP_MOSS_*` (neutral desaturated greys + a dead-moss green, no warm
      sandstone, no blue slate):
      `ARTIFACT_STONE_A := Color(0.40, 0.41, 0.39)`,
      `ARTIFACT_STONE_B := Color(0.60, 0.61, 0.58)`,
      `ARTIFACT_MOSS := Color(0.33, 0.40, 0.30)`,
      `ARTIFACT_MOSS_MAX: float = 0.35` (max lerp toward moss)
- [x] add the glow consts: `ARTIFACT_GLOW_COLOR := Color(0.45, 0.95, 1.0)`
      (cold cyan — nothing else in the world is this colour),
      `ARTIFACT_GLOW_ENERGY: float = 3.0` (comment: `main.tscn` glow threshold is
      0.85, so this blooms), `ARTIFACT_MAX_ACCENTS: int = 4` (hard cap on real
      `MeshInstance3D`s per artifact — the draw-call budget)
- [x] add the coin-reward consts: `ARTIFACT_COIN_MIN: int = 3`,
      `ARTIFACT_COIN_MAX: int = 5`, `ARTIFACT_COIN_RING_PAD_MIN: float = 1.5`,
      `ARTIFACT_COIN_RING_PAD_MAX: float = 4.0` (coin ring radius = artifact
      footprint radius + a pad in this range)

### Task 2: Extend create_box with optional tilt + colour override (backward compatible)
- [x] change `create_box()`'s signature to
      `create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void`
      — both new params are **optional with inert defaults**, so all 20-odd
      existing call sites are untouched and behave byte-identically
- [x] build the rotation once as
      `var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)` and use it
      for BOTH halves: visual `Transform3D(rot.scaled_local(dimensions), center_pos)`
      and collision `collision_shape.transform = Transform3D(rot, center_pos)`
      (replacing the current `position` + `rotation.y` assignment). Add a comment
      explaining that this keeps the `R * S` order the existing `scaled_local`
      note documents, so visual and collision stay in lockstep for a tilted box —
      and that with `tilt == 0.0` the extra `Basis` is the identity, so the
      transform is bit-for-bit what it was
- [x] apply the colour override AFTER the existing ramp `match`: if
      `color_override.a > 0.0`, use it instead of `chosen_color`. Comment WHY the
      ramp draws still happen (they belong to the caller's RNG stream; artifacts
      pass their own private RNG, so the discarded draws cost nothing and the
      shared-stream discipline in this function stays untouched)
- [x] verify by inspection that `create_block()` needs no change (it forwards
      positionally and the new params default)

### Task 3: Add the shared emissive accent material + accent spawner
- [x] add `var _shared_artifact_glow_material: StandardMaterial3D` near the other
      shared-resource vars, plus `_get_artifact_glow_material() -> StandardMaterial3D`
      following the exact lazy-singleton shape of `_get_shared_block_material()`:
      `albedo_color = ARTIFACT_GLOW_COLOR`, `emission_enabled = true`,
      `emission = ARTIFACT_GLOW_COLOR`,
      `emission_energy_multiplier = ARTIFACT_GLOW_ENERGY`,
      `shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED` (a rune should not go
      dark in shadow), with a teaching comment on how it feeds the `glow_enabled`
      post-process in `main.tscn`
- [x] add `_spawn_artifact_accent(parent_chunk: MeshInstance3D, local_pos: Vector3, dimensions: Vector3, yaw: float, tilt: float) -> void`:
      a `MeshInstance3D` using the **shared unit box mesh**
      (`_get_shared_unit_box_mesh()`), `transform = Transform3D((Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)).scaled_local(dimensions), local_pos)`,
      `material_override = _get_artifact_glow_material()`,
      `cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`, parented to
      `parent_chunk` (per-chunk parenting rule)
- [x] comment the draw-call budget explicitly: accents are real mesh instances
      (they cannot join the block MultiMesh, which has one shared non-emissive
      material), which is why there are at most `ARTIFACT_MAX_ACCENTS` of them
      and why artifacts are rare

### Task 4: Add the road-distance helper and the deterministic placement function
- [x] add `_road_lateral_distance(world_x: float, world_z: float) -> float`
      in the COIN ROAD MATH section: extend the station cache over
      `[world_x - pad, world_x + pad]` (pad = `ARTIFACT_ROAD_CLEARANCE + _road_spacing() * 2.0`),
      jump to `_road_first_k_at_or_after_x(world_x - pad)`, walk forward with a
      manual counter (NOT `range()` — same allocation gotcha the coin scan
      documents), `break` once `station.center.x > world_x + pad`, and return the
      minimum distance from `(world_x, world_z)` to any scanned station centre;
      return `INF` when no station is in range (treat as "far off road")
- [x] add `_artifact_at(chunk_pos: Vector2i) -> Dictionary` — the **pure**
      placement function, modelled on `_boss_at`: seed a private
      `RandomNumberGenerator` with
      `hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ ARTIFACT_SALT))`
      (an INDEPENDENT hash stream: it consumes NO draw from the chunk RNG, so
      every existing block/crocodile/coin is unmoved), then:
      1. `if rng.randf() >= ARTIFACT_CHANCE: return {}` (no artifact here),
      2. up to `ARTIFACT_PLACE_TRIES` candidate `(x, z)` inside the chunk minus
         `ARTIFACT_EDGE_MARGIN`, accepting the first whose world position is at
         least `ARTIFACT_ROAD_CLEARANCE` from the road centerline (this is what
         produces the off-road bias AND the "never on the centerline" rule);
         return `{}` if all tries are rejected,
      3. pick the shape with `rng.randi_range(0, 4)`,
      4. return `{ "local": Vector3, "kind": int, "seed": int }` where `seed` is
         a further `rng.randi()` used to seed the shape builder's own RNG
- [x] document in the docstring: within a run the same chunk yields the identical
      artifact (pure function of chunk coords + run_seed); across runs `run_seed`
      changes so artifacts land elsewhere; the chunk RNG stream is never touched

### Task 5: Build the five artifact shapes
- [x] add `_artifact_stone_color(rng: RandomNumberGenerator) -> Color`: lerp
      `ARTIFACT_STONE_A → ARTIFACT_STONE_B` by a random `t`, then lerp toward
      `ARTIFACT_MOSS` by `rng.randf() * ARTIFACT_MOSS_MAX`, so every stone is a
      slightly different weathered grey-green
- [x] add `_artifact_monolith(...)` — **leaning half-buried monolith**: one tall
      slab (≈`Vector3(1.8, 8.0, 1.1)`) with a random yaw and a `tilt` of
      ±(0.12..0.25) rad, its centre pushed BELOW y = 0 so the base is buried;
      3 thin emissive **rune strips** stacked up one face (accents, offset along
      the face normal so they sit proud of the stone)
- [x] add `_artifact_arch(...)` — **broken arch of floating stones**: 7-9 boxes
      placed along a half-circle arc (radius ≈ 5), each with a small random tilt
      and yaw, with 1-2 consecutive stones OMITTED so the arch reads as broken;
      one emissive accent floating in the gap (the "keystone that is missing")
- [x] add `_artifact_stone_circle(...)` — **circle of tilted standing stones**:
      6-9 slabs on a ring (radius 4-6), each leaning outward/inward by a random
      tilt, around a low central slab; one wide flat emissive accent lying on the
      centre slab's top face
- [x] add `_artifact_colossus_head(...)` — **half-buried colossus head**: a big
      half-buried jaw box, a narrower brow box on top, a slab nose, all sharing
      one yaw; two small emissive **eye** accents inset under the brow
- [x] add `_artifact_spiral_steps(...)` — **spiral of steps to nowhere**: 10-16
      step boxes on a spiral (angle increment ≈ 0.6 rad, rising ≈ 0.55 per step,
      radius 3-4), each yawed to face the centre; one emissive accent on the
      final, highest step (the destination that is not there)
- [x] give every builder the SAME signature —
      `(center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary` —
      returning `{ "radius": float, "top": float }` (footprint radius and top
      height for the obstacle entry). All solid geometry goes through
      `create_box(..., tilt, _artifact_stone_color(rng))`; all glow goes through
      `_spawn_artifact_accent`; nothing else is instanced
- [x] keep total accents per artifact `<= ARTIFACT_MAX_ACCENTS` (monolith 3,
      arch 1, circle 1, head 2, spiral 1)

### Task 6: Wire the artifact spawner into create_chunk (with coins + gem)
- [x] extract the coin perch/skip rule out of `spawn_coins_in_chunk` into
      `_settle_coin_y(local_x: float, local_z: float, ground_y: float, obstacles: Array) -> float`:
      returns the y to place the coin at, or `INF` to mean "skip this coin"
      (tallest overlapping block is non-climbable). Rewrite that stretch of
      `spawn_coins_in_chunk` to call it — **behaviour must be identical**
      (same tallest-overlap scan, same strict `>` tie-break, same
      `COIN_BLOCK_OFFSET`). One home for the rule so artifact coins and road
      coins can never drift apart
- [x] add `spawn_artifact_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void`:
      early-return unless `spawn_artifacts`; call `_artifact_at(chunk_pos)` and
      return on `{}`; seed a builder RNG from the returned `seed`; dispatch on
      `kind` to the five builders; append the returned footprint to `obstacles`
      as `{ "pos": ..., "radius": ..., "top": ..., "climbable": true }` (so
      crocodiles avoid the artifact and road coins perch on it rather than being
      buried in it — comment this consequence)
- [x] in the same function, spawn the reward (guarded by
      `spawn_coins and coin_scene != null`): `ARTIFACT_COIN_MIN..MAX` coins on a
      ring at `radius + randf_range(ARTIFACT_COIN_RING_PAD_MIN, ARTIFACT_COIN_RING_PAD_MAX)`
      at `COIN_GROUND_HEIGHT`, plus **exactly one** gem at the artifact centre
      (`coin.make_gem()` BEFORE `add_child`, per coin.gd's contract). Every coin
      runs through `_settle_coin_y` and is skipped when it returns `INF`. All
      coins are chunk-LOCAL and parented to `parent_chunk`. Do NOT touch the road
      station claim logic — these are ordinary chunk-local coins
- [x] call `spawn_artifact_in_chunk(chunk_pos, mesh_instance, obstacles, block_batch, block_body)`
      in `create_chunk` **after** the `spawn_objects_in_chunk` block and
      **before** `_build_block_multimesh` / the `block_body` attach, so artifact
      stone joins the chunk's single MultiMesh and single collision body. Comment
      the ordering requirement

### Task 7: Documentation comments in-file
- [x] extend the ARTIFACTS section comment with the determinism contract in the
      house teaching style: independent hash stream (no shared draws consumed),
      within-run revisits identical, cross-run different via `run_seed`, per-chunk
      parenting, and the "solid geometry → MultiMesh + BlockCollision, glow → at
      most 4 unshadowed MeshInstance3Ds" split
- [x] note honestly in a comment that the optional proximity shimmer loop was
      **skipped**: `sound_manager.get_loop_player()` returns a non-positional
      `AudioStreamPlayer`, so a per-artifact 3D hum would need a new positional
      audio path plus a per-frame proximity scan — out of proportion to "quiet
      polish"

### Task 8: Verify acceptance criteria
- [ ] `godot --headless --path . --import` — must complete without script errors
- [ ] `godot --headless --path . --quit-after 3` — must run and quit with no
      errors or warnings in stdout/stderr
- [ ] write a TEMPORARY headless GDScript check (e.g. `scripts/tmp_artifact_check.gd`
      run via `godot --headless --path . --script`) asserting: (a) `_artifact_at`
      returns the identical Dictionary for the same chunk called twice within a
      run; (b) over ~400 chunk coords the artifact hit-rate lands in the 1-per-15
      to 1-per-25 band; (c) changing `run_seed` changes the placement set; (d) no
      returned artifact sits within `ARTIFACT_ROAD_CLEARANCE` of the road
      centerline. Run it, confirm it passes, then **delete the file** (no test
      infrastructure is left behind)
- [ ] grep the diff to confirm ONLY `scripts/endless_terrain.gd` (plus this plan)
      changed — `player_controller.gd`, the crocodile AI, HUD scripts and the
      boss spawner must be untouched
- [ ] confirm by inspection that every existing `create_box`/`create_block` call
      site is unchanged and that no draw was inserted into the chunk RNG stream

### Task 9: [Final] Update documentation
- [ ] add a short subsection to `CLAUDE.md` under "Everything in the world is
      spawned procedurally from the terrain" describing artifacts: rarity, the
      independent `ARTIFACT_SALT` hash stream, the road-clearance rule, the
      MultiMesh/BlockCollision requirement, the ≤4 emissive accents, and the
      coin+gem reward — matching the density of the surrounding docs
- [ ] do NOT touch README.md / QUICKSTART.md (stale by project convention)

## Technical Details

**Determinism model (the load-bearing part).** Artifacts use an INDEPENDENT hash
stream, the preferred option in the bead:

```
rng.seed = hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed ^ ARTIFACT_SALT))
```

This is the `_boss_at` / `_road_coins_at` pattern. Consequences:
- the chunk RNG (`spawn_objects_in_chunk`) draw sequence is **completely
  untouched** — no draw inserted, moved or removed, so blocks/structures are
  where they always were;
- a revisited chunk regenerates the identical artifact within a run;
- two runs differ because `run_seed` is re-rolled by `new_run()`.

One deliberate, documented side effect: an artifact appends a footprint to the
chunk's `obstacles` list, which the crocodile spawner uses for rejection and the
coin road uses for perch/skip. So in the ~5% of chunks that HAVE an artifact,
crocodiles avoid spawning inside it and road coins perch on it instead of being
buried. That is the intended behaviour (it is what "artifact blocks count as
normal blocks" means) and it changes nothing in the 95% of chunks without one.

**Geometry routing.** `create_box` stays the single funnel. It gains two optional
inert-by-default parameters:
- `tilt: float = 0.0` — rotation about the local X axis applied AFTER yaw
  (`Basis(UP, yaw) * Basis(RIGHT, tilt)`), needed because a leaning monolith and
  tilted standing stones are the whole visual idea. Visual uses
  `rot.scaled_local(dimensions)`; collision sets the same `rot` on the
  `CollisionShape3D` transform — preserving the `R * S` lockstep the existing
  comment documents. With `tilt == 0.0` the extra basis is the identity, so every
  existing block is bit-identical.
- `color_override: Color = Color(0,0,0,0)` — used only when `a > 0`, so artifacts
  get the weathered palette while ordinary blocks keep the ramps.

**Draw-call budget.** Artifact stone lives in the chunk's existing MultiMesh (0
extra draws) and its existing `BlockCollision` body (0 extra bodies). Only the
emissive accents are real nodes: at most `ARTIFACT_MAX_ACCENTS = 4` per artifact,
in ~1 chunk out of 20, `cast_shadow` OFF. Worst case with 49 active web chunks:
~2-3 artifacts on screen, ≤12 extra unshadowed draws.

**Shape dispatch.** `kind` 0..4 → monolith, arch, stone circle, colossus head,
spiral steps. Each builder is self-contained, takes the same signature, returns
`{ radius, top }` for the obstacle entry, and draws only from the artifact RNG.

**Coins.** Chunk-local, parented to the chunk, ground height, standard perch/skip
rule via the extracted `_settle_coin_y`. Exactly one gem at the centre —
`make_gem()` is called before `add_child` as coin.gd requires. Road station claim
logic (`spawn_coins_in_chunk`'s `world_to_chunk` bucketing) is NOT touched.

**Skipped (honest deferral).** The optional proximity shimmer/hum loop:
`sound_manager.get_loop_player()` hands back a non-positional `AudioStreamPlayer`,
so a per-artifact ambience needs a positional audio path plus a per-frame
proximity scan against artifact centres. Out of proportion to the polish it buys;
noted in-file and in the PR.

## Post-Completion

*Items requiring manual intervention - no checkboxes, informational only*

**Manual verification:**
- Walk/fly the world and confirm artifacts read as "another age": weathered grey
  stone clearly distinct from the sandstone/slate/moss block ramps, cyan runes
  blooming through the glow pass.
- F3 perf overlay: confirm draw calls do NOT jump when an artifact chunk loads
  (only the handful of accent instances).
- Confirm the gem is reachable on each shape (perch rule may put it on top of the
  monolith/head rather than at ground level — that is intended, it rewards a
  climb) and retune `ARTIFACT_*` constants if a shape feels wrong at play scale.
- Web export smoke test after merge (CI builds it; play the Pages build on a
  phone to confirm no frame-time regression).
