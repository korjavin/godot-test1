# Nomad camps (dome-hut villages) + herder caravans

## Overview

Two halves of one owner request ("rarely, a village of dome dwellings appears; its
people are caravan herders who ignore the player completely"):

1. **Nomad camps** — a rare, deterministic terrain feature in `scripts/endless_terrain.gd`:
   3–6 white/bone DOME huts (igloo look) in a loose circle around a fire pit
   (dark stone ring + one emissive ember), plus crates/bundles and tether posts.
   Rarer than artifacts (~1 per 30–50 chunks), off-road, never mid-river, all solid
   geometry batched into the chunk's existing MultiMesh + `BlockCollision` body.
   A couple of scattered coins, **no gem** (that stays the artifacts' distinction).
   Crocodile spawns inside the camp circle are skipped so a camp reads as a calm pocket.

2. **Herder caravans** — a third migration type in `scripts/fauna_manager.gd`:
   2–4 blocky herders leading 3–6 woolly pack beasts with bundles on their backs,
   walking a loose line, weighted rarer than elephants/giraffes, sharing the existing
   fauna event timer. Pure ambience: no collision, no groups, no reaction to anything.

Both halves are additive: they reuse the existing machinery (artifact/biome spawner
pattern for camps, the fauna record/animation loop for caravans) and must not shift
any existing RNG stream.

## Context (from discovery)

- **Files involved**: `scripts/endless_terrain.gd` (camps), `scripts/fauna_manager.gd`
  (caravans), `CLAUDE.md` (documentation).
- **Patterns to copy**:
  - `_artifact_at()` / `spawn_artifact_in_chunk()` — independent hash stream keyed
    `hash(Vector3i(cx * P1, cy * P2, run_seed ^ SALT))`, candidate-spot loop, footprint
    appended to `obstacles`, coins settled through `_settle_coin_y` **before** the
    footprint append.
  - `spawn_biome_content_in_chunk()` / `_biome_spot_ok()` — the existing
    "is this a legal spot?" helper (river + road clearance + obstacle overlap in one).
    **Reuse it; do not write a second copy of that rule.**
  - `create_box(..., tilt, color_override, collide)` — the batched-geometry entry point.
  - `_spawn_artifact_accent()` + `_get_artifact_glow_material()` — the emissive-accent path.
  - `fauna_manager.gd`: `_make_box_part` / `_make_leg` / the species-agnostic animal
    record (`root`/`body`/`legs`/`neck`/`neck_rest`/`trunk`), `static var` shared
    material getters, `_add_animal`, `_animate_animals`.
- **Dependencies already on master**: biomes (`is_river_at()`), migrating fauna,
  artifacts, bosses, weather.
- **Coordination**: a parallel executor is editing `spawn_bosses_in_chunk`.
  **Do not touch that function** — the boss/camp exclusion is achieved by geometry
  instead (see Task 2).

## Development Approach
- **Testing approach**: NO unit tests. This is a Godot project with no test suite,
  linter, or build script; the verification is `godot --headless --path . --import`
  plus a short headless run (`--quit-after 3`) with no errors.
- Complete each task fully before moving to the next.
- Make small, focused changes; keep teaching-density comments and explicit type hints
  (project convention — see CLAUDE.md "Conventions").
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility: the world outside a camp chunk must regenerate
  byte-identically.

## Testing Strategy
- **Unit tests**: none.
- **Integration tests**: none — the project has no test harness. The runnable check is
  the headless import + run, called out explicitly in the verify task.
- **E2E tests**: none exist in this project.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Keep plan in sync with actual work done

## Implementation Steps

### Task 1: Nomad camp constants + placement stream in endless_terrain.gd
- [x] add a `NOMAD CAMPS` constant banner near the ARTIFACTS section of
      `scripts/endless_terrain.gd`, in the same commented style: `@export var spawn_camps: bool = true`,
      `CAMP_CHANCE` (~0.025 → ~1 per 40 chunks before rejections, rarer than
      `ARTIFACT_CHANCE` 0.05), `CAMP_SALT` (a fresh arbitrary constant, distinct from
      `ARTIFACT_SALT` / `BIOME_SALT` / `BOSS_SEED`), `CAMP_PLACE_TRIES`,
      `CAMP_ROAD_CLEARANCE`, `CAMP_EDGE_MARGIN`, `CAMP_RADIUS` (the camp circle),
      hut/fire-pit/crate/post geometry constants, the weathered palette
      (`CAMP_HUT_A`/`CAMP_HUT_B` bone-white, `CAMP_STONE`, `CAMP_WOOD`,
      `CAMP_EMBER_COLOR`, `CAMP_EMBER_ENERGY`) and `CAMP_COIN_MIN`/`CAMP_COIN_MAX`
- [x] document in the banner: palette deliberately distinct from both the warm `RAMP_*`
      block ramps and the artifacts' grey-green; ember is warm orange vs the artifacts' cold cyan
- [x] `CAMP_ROAD_CLEARANCE` **must** exceed `CAMP_RADIUS + BOSS_LATERAL_MAX` — write the
      arithmetic into the comment. This is what makes "no boss inside a camp circle" true
      **by construction**, with zero edits to `spawn_bosses_in_chunk` (owned by a parallel
      executor this cycle)
- [x] `CAMP_EDGE_MARGIN` must exceed `CAMP_RADIUS` so a whole camp fits inside its own
      chunk and never straddles a seam (same rule as `ARTIFACT_EDGE_MARGIN`)
- [x] add `_camp_at(chunk_pos: Vector2i) -> Dictionary` modelled line-for-line on
      `_artifact_at`: its own RNG seeded `hash(Vector3i(chunk_pos.x * P1, chunk_pos.y * P2,
      run_seed ^ CAMP_SALT))` with **different coordinate primes** from the artifact and
      biome streams; rarity roll, then up to `CAMP_PLACE_TRIES` candidate spots accepted on
      the FIRST that clears the road (`_road_lateral_distance`) and is not
      `is_river_at()`; returns `{}` or `{ "local": Vector3, "seed": int }`
- [x] docstring the determinism contract exactly as `_artifact_at` does: zero draws from
      the shared chunk RNG, identical within a run, different across runs

### Task 2: Camp geometry builders (dome huts, fire pit, crates, tether posts)
- [x] add `_camp_hut(center, yaw, rng, block_batch, block_body)`: an igloo read from
      2–3 stacked shrinking box tiers (widest at the ground, each tier narrower and
      shorter, slight per-tier yaw jitter) + a small dark doorway box on one side,
      all through `create_box(..., color_override = <bone white from CAMP_HUT_A→B>)` so it
      joins the chunk's ONE MultiMesh and ONE `BlockCollision` body
      (returns `{ "radius", "top" }` like the artifact builders, so Task 3 gets the hut
      footprint for free; only the TOP tier is shortened — the dome cap — so a 3-tier hut
      stays 2.36 m and the doorway still reads)
- [x] add `_camp_fire_pit(center, rng, parent_chunk, block_batch, block_body)`: a ring of
      small dark stone boxes (`CAMP_STONE`) around the centre, plus **one** small emissive
      ember mesh
- [x] extend `_spawn_artifact_accent` with an OPTIONAL trailing
      `material: StandardMaterial3D = null` parameter (null keeps the artifact glow
      material — every existing call site is unchanged), and add
      `_get_camp_ember_material()` as a second lazily-created shared unshaded emissive
      material (warm orange, energy above `main.tscn`'s `glow_hdr_threshold` 0.85,
      `cast_shadow` OFF via the existing accent path). ONE material for every ember ever
      spawned — never per camp
- [x] add `_camp_props(center, rng, block_batch, block_body)`: a few crates/bundles (small
      `CAMP_WOOD` boxes at random yaw) and 2–3 tall thin tether posts, placed on a jittered
      ring between the fire and the huts
- [x] every builder takes the camp's PRIVATE rng (seeded from `_camp_at`'s `"seed"`), like
      the artifact shape builders, so they may draw freely

### Task 3: spawn_camp_in_chunk + wiring into create_chunk
- [x] add `spawn_camp_in_chunk(chunk_pos, parent_chunk, obstacles, block_batch, block_body)`:
      early-return on `not spawn_camps` / empty `_camp_at`; seed the private builder RNG;
      re-check the accepted spot against the chunk's finished `obstacles` (reuse
      `_biome_spot_ok(chunk_center, local_x, local_z, CAMP_RADIUS, CAMP_ROAD_CLEARANCE, obstacles)`
      — the existing single home of that rule; bail if it fails rather than shoving a camp
      through a mountain massif)
- [x] build the fire pit at the camp centre, then 3–6 huts on a jittered ring around it
      (`CAMP_HUT_RING_*`), each yawed to face the fire, then the props
- [x] spawn `CAMP_COIN_MIN..MAX` scattered coins around the fire through `_settle_coin_y`
      (the perch-or-skip rule) **before** the footprint append, exactly like the artifact
      reward ordering — and **no gem**; comment why (artifacts keep that distinction)
- [x] append ONE round obstacle footprint at the camp centre with `radius = CAMP_RADIUS`,
      `climbable = false`. **This single footprint IS the crocodile exclusion**: the existing
      `spawn_crocodiles_in_chunk` already rejects any candidate within
      `ob.radius + min_object_clearance` of a footprint, so no croc spawns inside the circle
      and `spawn_crocodiles_in_chunk` needs NO edit and NO shifted RNG draw. Also append the
      individual huts' own footprints so the crocodile/coin rules see real hut stone
- [x] call `spawn_camp_in_chunk` from `create_chunk` AFTER `spawn_biome_content_in_chunk`
      and BEFORE `_build_block_multimesh` / the `block_body` attach, with the same ordering
      comment the artifact and biome calls carry; **do not touch `spawn_bosses_in_chunk`**
- [x] confirm in comments that camp coins can't collide with the road-coin claim logic
      (a camp is ≥ `CAMP_ROAD_CLEARANCE` off the centerline, well outside the widest
      `road_width_max / 2` scatter band)

### Task 4: Herder + pack-beast model builders in fauna_manager.gd
- [ ] add a `CONSTANTS — caravan geometry` block in the existing commented style: herder
      torso/head/leg sizes, staff size, pack-beast body/leg/neck/head sizes, shag fringe box
      size and count, bundle box size, plus `CARAVAN_HERDERS_MIN/MAX` (2–4),
      `CARAVAN_BEASTS_MIN/MAX` (3–6) and the line-formation spacing
- [ ] add two shared `static var` materials with lazy getters in the existing style —
      `_get_cloak_material()` (muted cloak) and `_get_wool_material()` (light-brown/cream) —
      and reuse `_get_patch_material()` (dark brown) for staffs/bundles/hooves. Total feature
      material count stays a small constant; **never `duplicate()` per animal**
- [ ] add `_build_herder() -> Dictionary` returning the SAME record shape
      (`root`/`body`/`legs`/`neck`/`neck_rest`/`trunk`): torso box + head box + **two**
      hip-pivot legs via the existing `_make_leg` (the animation loop indexes
      `LEG_PHASE_OFFSETS` by leg index, so two legs get the 0/PI alternating stride for
      free), plus a staff box angled at the side; `neck = null`, `trunk = []`
- [ ] add `_build_pack_beast() -> Dictionary`: woolly body box + a row of shag fringe boxes
      along its lower flanks, four `_make_leg` legs in the FL/FR/RL/RR order the animation
      loop requires, a curved neck as a short chain of pivots (or a neck pivot with a second
      angled segment) ending in a small head, and 1–2 bundle boxes strapped on the back.
      Use the `neck` slot so the existing neck-bob animation drives it, and cache
      `neck_rest`
- [ ] follow the existing shadow discipline: `cast_shadow` ON for big silhouette parts
      (torso, legs, beast body/neck), OFF for small accents (staff, fringe, bundles, head nubs)
- [ ] feet rest at local y = 0 and local forward is -Z, like every other fauna builder

### Task 5: Caravan as the third migration type
- [ ] add `CARAVAN_CHANCE` (weighted clearly rarer than the two herds — e.g. 0.15) with a
      comment on why it shares the fauna event timer rather than owning one
- [ ] extend the species pick in `_spawn_herd()` so a caravan is rolled first and the
      existing `ELEPHANT_CHANCE` split stays the elephant/giraffe branch — one extra
      branch, not a restructure
- [ ] add `_spawn_caravan()`: herders at the FRONT of the line (small lateral jitter),
      pack beasts trailing behind them along the heading in a loose, jittered single file
      — reuse `_add_animal(record, offset)` so formation easing, facing, phase offsets and
      despawn all come for free
- [ ] verify no new state is needed in `_update_herd` / `_animate_animals`: a caravan is
      just N records, so movement/animation/despawn are untouched
- [ ] document the hard isolation contract in the caravan comments (no groups, no
      collision, ignores player/crocs/abilities/rain — same as the herds), and add a
      `ponytail:` note that a caravan does NOT path to nomad camps (out of scope; the
      upgrade path is a nearest-camp query from the terrain)
- [ ] the optional caravan bell one-shot is **skipped honestly** — record it as a
      `ponytail:` deferral in the same shape as the existing elephant-trumpet note
      (`sound_manager.gd` is shared and the spawn is ~140 m away, so a non-positional bell
      would misread)

### Task 6: Verify acceptance criteria
- [ ] `godot --headless --path . --import` runs clean (no errors/warnings from the two
      edited scripts)
- [ ] `godot --headless --path . scenes/main.tscn --quit-after 3` runs clean
- [ ] re-read both diffs for the project conventions: explicit type hints, constants at
      top, teaching-density comments
- [ ] confirm determinism by inspection: camps draw from their own salted stream only;
      no existing RNG call was inserted, removed, or reordered; every rejection is a
      `continue`/`return` after its draws
- [ ] confirm batching by inspection: all camp solid geometry goes through `create_box`
      (one MultiMesh, one collision body per chunk) and the ember is the only extra
      MeshInstance3D per camp

### Task 7: [Final] Update documentation
- [ ] add a "Nomad camps" paragraph to the terrain section of `CLAUDE.md` (rarity, salt
      stream, off-road/river rules, the boss-exclusion-by-clearance argument, the single
      camp footprint doing the crocodile exclusion, no gem)
- [ ] extend the "Ambient fauna" section of `CLAUDE.md` with the caravan migration type
      and its deferrals

## Technical Details

- **Camp record**: `_camp_at()` → `{ "local": Vector3 (chunk-local, y = 0), "seed": int }`.
- **Camp footprint**: `{ "pos": Vector3, "radius": CAMP_RADIUS, "top": <hut top>,
  "climbable": false }` — non-climbable so a stray road coin is skipped rather than perched
  on thin air (cannot happen given the road clearance, but the rule stays honest).
- **Boss exclusion invariant**: `CAMP_ROAD_CLEARANCE > CAMP_RADIUS + BOSS_LATERAL_MAX`.
  A boss sits at most `BOSS_LATERAL_MAX` from the road centerline; a camp centre is at
  least `CAMP_ROAD_CLEARANCE` from it; so the boss is always outside the camp circle. If
  either constant is ever retuned, this inequality is the thing to re-check.
- **Animal record shape** (unchanged, species-agnostic):
  `{ root, body, legs (FL/FR/RL/RR or L/R), neck, neck_rest, trunk, offset, phase }`.

## Post-Completion

**Manual verification**:
- Walk/fly a few thousand metres in the editor and confirm a camp reads instantly as
  "a small dome-hut village with a glowing fire pit", sits off-road, and holds no crocodiles.
- Watch the F3 perf overlay across a camp chunk: draw calls should rise by ~1 (the ember),
  not by dozens.
- Idle a few minutes to catch a caravan crossing and confirm herders + laden beasts walk
  their line and ignore everything.
