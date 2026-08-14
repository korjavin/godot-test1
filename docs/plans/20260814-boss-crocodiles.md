# Boss Crocodiles Along the Coin Road

## Overview
- Add rare "boss" crocodiles placed deterministically along the coin road: one every
  ~50 stations (~300 m of road at 6 m/station), each boss bigger than the last on a
  fixed size schedule (2.5x up to a 6x cap).
- Bosses reuse the existing piglet crocodile scene + AI wholesale — no new AI system.
  A boss differs only in flags: immune to Phoboman's Stink Wave (`flee_from` no-op),
  faster chase (~7.0, still capped so a RUNNING player escapes but a walking one is
  caught), wider detection radius (25.0, still well under the LOD `SIM_RADIUS` 45),
  NOT crushable by giant Teibi, and NO per-instance random speed/size rolls.
- Placement is a pure function of the boss index `i` + `run_seed` via an INDEPENDENT
  hash stream (a new `BOSS_SEED`, like `ROAD_COIN_SEED`) — it must never consume a
  draw from any existing chunk/coin/croc RNG sequence, so the whole procedural world
  regenerates byte-for-byte identically.
- Chunk-claim spawning exactly like road coins: the chunk whose `world_to_chunk(pos)`
  matches spawns the boss, parented to the chunk mesh — so outrunning far enough
  despawns the boss with its chunk, which reads as "you escaped it".
- Visuals: the same croc scene scaled up, with ONE statically-cached darker/red-shifted
  toon material variant via a new helper on `scripts/toon_shading.gd`, and the per-mesh
  `visibility_range_end` cull distance scaled by the boss's size (a 6x boss must not
  pop in at 60 m).
- Optional growl one-shot via the synthesized `sound_manager` when a boss first
  acquires the player.

## Context (from discovery)
- **`scripts/endless_terrain.gd`** — world engine. Key pieces to reuse:
  - Road station cache: `_road_extend_to_x(x_min, x_max)` grows `road_stations`
    (Dictionary keyed by station index `k`, contiguous `[road_k_min, road_k_max]`);
    `_road_station(k)` returns `{ "center": Vector2, "heading": float }`;
    `_road_first_k_at_or_after_x(x)` binary-searches the window start. Centerline X
    is strictly increasing in `k` (heading cap < 90°), so a chunk's X-range maps to
    a contiguous station window.
  - Claim pattern (from `spawn_coins_in_chunk`, line ~1831): compute a padded chunk
    X-window, `_road_extend_to_x`, jump to `k_start`, walk stations with a manual
    `while` cursor, `break` past the window, and spawn only what
    `world_to_chunk(world_pos) == chunk_pos` claims. Positions stored chunk-LOCAL
    (relative to `chunk_to_world(chunk_pos)`).
  - Seed shape convention: `hash(Vector3i(a, b, run_seed))` — see `_road_coins_at`
    (`hash(Vector3i(k, ROAD_COIN_SEED, run_seed))`). `run_seed` is re-rolled by
    `new_run()` only.
  - `create_chunk` (line ~738) calls `spawn_crocodiles_in_chunk(chunk_pos,
    mesh_instance, obstacles)` then `spawn_coins_in_chunk(chunk_pos, mesh_instance,
    obstacles)` — the boss spawner slots in beside these, using `crocodile_scene`
    (already preloaded) and the same chunk parenting.
- **`scripts/piglet_crocodile_ai.gd`** — the live croc AI:
  - `_ready()` (line ~239) rolls per-instance speed (`SPEED_RANDOM_FACTOR`) and size
    (`SIZE_RANDOM_FACTOR`) from a `randomize()`d per-instance `rng`, applies the
    distance-scaled chase factor (`DISTANCE_SPEED_SCALE_*`, capped at
    `MAX_CHASE_SPEED` 8.5), sets `scale`, then styles the model via
    `_style_model_meshes` (visibility cull 60 m + `ToonShading.apply_to_mesh`).
  - `_update_chase_state()` (line ~431) compares against the `DETECTION_RADIUS`
    const (15.0).
  - `flee_from(source, duration)` (line ~492) is the Stink Wave hook (group
    `"crocodile"`).
  - `_on_player_collision(player)` (line ~850): crush check first
    (`player.crushes_crocodiles()` → `queue_free()`), then flee check, then bite.
    **A parallel executor is adding "crush juice" inside that crush block — the boss
    branch must be an early check ABOVE it, leaving the crush block textually
    untouched.**
  - Terrain parents the croc BEFORE `_ready` runs, so `global_position` is valid in
    `_ready` (the distance factor relies on this) — and so does the boss setup:
    `setup_as_boss(...)` is called on the instance BEFORE `add_child`, setting flags
    that `_ready` then branches on.
- **`scripts/toon_shading.gd`** — `ToonShading.apply_to_mesh(mesh)` with a static
  `_styled_cache` keyed by source-material instance id. The boss variant follows the
  same pattern with its own static cache.
- **`scripts/sound_manager.gd`** — synthesized `AudioStreamWAV` one-shots; consts at
  top, `_synth_*()` builders registered in `_ready()`, public `play_*()` methods
  behind the web unlock gate. Callers use null-safe
  `get_first_node_in_group("sound_manager")` + `has_method` guards.
- **Do NOT touch:** `scripts/crocodile_lod_manager.gd`, `scripts/player_controller.gd`,
  any HUD script — a parallel game-feel executor owns those. Bosses participate in
  LOD sleep like any croc (they keep group `"crocodile"` and `set_lod_active`), and
  `SIM_RADIUS` stays untouched.

## Development Approach
- **Testing approach**: NO unit tests (project has no test suite). Verification is
  `godot --headless --path . --import` + a short `--quit-after` run, plus a
  determinism sanity script if cheap.
- Complete each task fully before moving to the next.
- Make small, focused changes; match the codebase's teaching-style comment density
  and explicit type hints; tunables as constants at the top of each script.
- **CRITICAL: update this plan file when scope changes during implementation**
- **HARD determinism rule:** boss placement is a pure function of (boss index,
  `run_seed`) via its own hash stream. Never draw from the chunk RNG, the road
  coin RNG, or any existing sequence; never reorder or add draws to those sequences.
  Within a run, revisiting a chunk regenerates the identical boss; two runs differ.

## Testing Strategy
- **Unit tests**: none.
- **Integration tests**: none — no boundary here that the headless run doesn't cover.
- Verification: headless import + timed run must exit clean (see Verify task).

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Boss flags and behavior in piglet_crocodile_ai.gd
- [x] Add boss constants at the top of `scripts/piglet_crocodile_ai.gd` (with the
      existing teaching-comment style): `BOSS_CHASE_SPEED: float = 7.0` (above
      WALK 5.0, below the slowest RUN 9.0 — walking loses, running escapes),
      `BOSS_DETECTION_RADIUS: float = 25.0` (with a comment citing the invariant:
      must stay well below the LOD manager's `SIM_RADIUS` 45 so any boss that can
      detect the player is always awake).
- [x] Add state vars near the other flags: `var is_boss: bool = false` and
      `var boss_scale: float = 1.0`.
- [x] Add `func setup_as_boss(body_scale: float) -> void` — a public hook the
      terrain calls on the instance BEFORE `add_child` (so `_ready` sees the flags):
      sets `is_boss = true` and `boss_scale = body_scale`. Document the call-order
      contract in its docstring.
- [x] Branch `_ready()`: when `is_boss`, SKIP the random speed roll and the random
      size roll entirely (no per-instance randomization for bosses — size comes from
      the deterministic schedule) — instead set
      `move_speed_instance = BASE_MOVE_SPEED`,
      `chase_speed_instance = minf(BOSS_CHASE_SPEED * distance_factor, MAX_CHASE_SPEED)`
      (keep the existing distance-factor computation shared between both branches so
      the difficulty gradient still applies, and keep the `MAX_CHASE_SPEED` cap so
      the running-escape hatch survives at any distance), and
      `scale = Vector3.ONE * boss_scale`. The cosmetic animation-phase rolls
      (`instance_phase` etc.) stay for both (they only desync animations).
- [x] Stink-wave immunity: `flee_from()` early-returns when `is_boss` (with a
      comment: the group `"crocodile"` membership is KEPT — the wave finds bosses,
      they just shrug it off; immunity lives here, not in group tricks).
- [x] Detection radius: in `_update_chase_state()`, compare against a local
      `var radius: float = BOSS_DETECTION_RADIUS if is_boss else DETECTION_RADIUS`.
- [x] Not crushable: in `_on_player_collision()`, add the boss branch as an EARLY
      check ABOVE the existing giant-Teibi crush block (leave that block textually
      untouched — a parallel executor edits inside it): when `is_boss`, go straight
      to the bite path (print, `_start_bite()`, `hit_by_crocodile()` /
      `reset_position()` fallback, `_pause_and_change_direction()`) and `return`.
      Comment the assumption for the owner: a boss is bigger than giant Teibi, so
      giant form is bitten, not a crusher. The few duplicated bite lines are a
      deliberate minimal-merge-conflict choice — mark with a `ponytail:` comment.

### Task 2: Boss visual styling (toon variant + scaled cull range)
- [x] Add a boss material variant to `scripts/toon_shading.gd`: a second static
      cache (`_boss_styled_cache: Dictionary`) and
      `static func apply_boss_to_mesh(mesh: MeshInstance3D) -> void` that mirrors
      `apply_to_mesh` but additionally darkens/red-shifts the duplicate's
      `albedo_color` (e.g. multiply by `Color(0.85, 0.4, 0.4)`) so bosses read
      menacing. ONE cached variant per distinct source material, shared by every
      boss — never a per-boss duplicate (comment why, same as the existing cache).
      Note: unlike `apply_to_mesh`, do NOT skip materials that are already
      `DIFFUSE_TOON` from the regular cache — key the boss cache off the SOURCE
      material seen on the mesh and always install the boss duplicate.
- [x] In `piglet_crocodile_ai.gd` `_style_model_meshes()`, branch on `is_boss`:
      bosses call `ToonShading.apply_boss_to_mesh(node)` instead of
      `apply_to_mesh(node)`, and set
      `visibility_range_end = VISUAL_CULL_DISTANCE * boss_scale` (margin scaled
      too) so a 6x boss doesn't pop in at 60 m. Regular crocs are byte-identical
      to before.

### Task 3: Deterministic boss spawner in endless_terrain.gd
- [x] Add boss constants near the road config section of
      `scripts/endless_terrain.gd`, teaching-style comments included:
      `BOSS_INTERVAL_STATIONS: int = 50` (at 6 m/station ≈ every 300 m of road,
      inside the requested 250–400 m), `BOSS_BASE_SCALE: float = 2.5` (clearly
      bigger than the biggest regular croc's +25% roll), `BOSS_GROWTH: float = 0.35`
      (each boss ~35% of base bigger than the last), `BOSS_MAX_SCALE: float = 6.0`,
      `BOSS_LATERAL_MAX: float = 4.0` (small deterministic lateral offset off the
      centerline), `BOSS_FORWARD_OFFSET: float = 8.0` (spawn a bit ahead of the
      station along the road so the player sees it looming ahead), and
      `BOSS_SEED: int = 0xB0_55` (its OWN independent hash stream, like
      `ROAD_COIN_SEED` — never consumes existing RNG draws).
- [x] Add `func _boss_at(i: int) -> Dictionary` returning
      `{ "pos": Vector3, "scale": float }` for boss index `i >= 1` (station
      `k = i * BOSS_INTERVAL_STATIONS`; only forward stations get bosses — the
      player spawns at station 0 and the road trends +X; no boss at spawn).
      Pure function of `i` + `run_seed`: an RNG seeded
      `hash(Vector3i(i, BOSS_SEED, run_seed))` draws ONLY the lateral offset
      (`randf_range(-1, 1) * BOSS_LATERAL_MAX`); position =
      station center + tangent * BOSS_FORWARD_OFFSET + perp * lateral (same
      tangent/perp construction as `_road_coins_at`), Y a little above ground
      (gravity settles the body). Scale =
      `minf(BOSS_BASE_SCALE * (1.0 + float(i - 1) * BOSS_GROWTH), BOSS_MAX_SCALE)`
      so boss 1 is exactly `BOSS_BASE_SCALE` and each successive boss is visibly
      bigger until the cap. Requires the station cache to already cover `k`
      (documented; the caller extends first, like `_road_coins_at`).
- [x] Add `func spawn_bosses_in_chunk(chunk_pos: Vector2i, parent_chunk:
      MeshInstance3D) -> void` following `spawn_coins_in_chunk`'s claim pattern:
      pad = `BOSS_LATERAL_MAX + BOSS_FORWARD_OFFSET + 2.0`; `_road_extend_to_x`
      over the padded chunk X-window; find the smallest boss index `i` whose
      station falls at/after the window start (derive from
      `_road_first_k_at_or_after_x` rounded up to the next interval multiple,
      minimum 1); walk boss indices while their station `k <= road_k_max` and the
      station X is inside the padded window; for each, spawn ONLY if
      `world_to_chunk(boss_pos) == chunk_pos` (exactly-one-chunk claim → no seam
      gaps/duplicates). Instantiate `crocodile_scene`, set chunk-LOCAL position,
      deterministic name (`"BossCrocodile_%d" % i`), call
      `setup_as_boss(scale)` BEFORE `parent_chunk.add_child(...)`. Parenting to
      the chunk mesh = despawns with the chunk = "you escaped it" (comment this).
      No rotation draw needed — face along the road heading
      (`rotation.y = atan2(...)` from the station heading) or leave default;
      whatever is chosen must not consume any shared RNG.
- [x] Call `spawn_bosses_in_chunk(chunk_pos, mesh_instance)` from `create_chunk`,
      gated on `spawn_crocodiles`, right after the existing crocodile spawns.
      Confirm by reading the diff that NO existing RNG stream (chunk object rng,
      croc rng, platform rng, road coin rng) gained/lost/reordered a single draw.

### Task 4: Optional boss growl one-shot (skip honestly if fiddly)
- [ ] Add to `scripts/sound_manager.gd` following the existing recipe: `GROWL_*`
      consts (low fundamental ~70 Hz, ~0.5 s, saw/noise blend, −8 dB),
      `_synth_growl()` builder, bake in `_ready()`, public `play_boss_growl()`
      behind the same unlock gate.
- [ ] In `piglet_crocodile_ai.gd` `_update_chase_state()`, on the
      not-chasing → chasing transition, when `is_boss`, fire the growl via the
      null-safe group lookup pattern
      (`get_tree().get_first_node_in_group("sound_manager")` + `has_method`
      guard) — one line each side, no hard refs. If this turns out fiddly, drop
      the whole task and note it in the plan with ⚠️.

### Task 5: Verify acceptance criteria
- [ ] Re-read the diff against the determinism rules: boss stream independent
      (only `hash(Vector3i(i, BOSS_SEED, run_seed))`), no changes to any existing
      RNG draw sequence, `SIM_RADIUS`/`crocodile_lod_manager.gd`/
      `player_controller.gd`/HUD scripts untouched, bosses keep group
      `"crocodile"` (LOD sleep + stink-wave targeting + danger telegraph all
      keep working; a slept boss is fine — sleep-never-remove holds).
- [ ] `godot --headless --path . --import` exits clean (no script errors).
- [ ] `godot --headless --path . --quit-after 3` (main scene) exits clean —
      terrain generates, bosses spawn without runtime errors.
- [ ] Sanity-check the size schedule numerically (a quick throwaway calc is fine):
      boss 1 = 2.5x, monotonically growing, capped at 6.0x.

### Task 6: [Final] Update documentation
- [ ] Add a short "Boss crocodiles" subsection to `CLAUDE.md` under the enemy/AI
      architecture notes: deterministic station-indexed placement (own
      `BOSS_SEED` stream), size schedule, `setup_as_boss` call-order contract
      (before `add_child`), flee immunity keeps group membership, boss detection
      25 << SIM_RADIUS 45 invariant, not crushable (bigger-than-giant-Teibi
      assumption), chunk parenting = escape-by-outrunning.

## Technical Details
- **Size schedule**: `scale(i) = minf(BOSS_BASE_SCALE * (1 + (i-1) * BOSS_GROWTH),
  BOSS_MAX_SCALE)` → 2.5, 3.375, 4.25, 5.125, 6.0, 6.0, … Uniform body `scale` on
  the `CharacterBody3D`, same mechanism as the regular size roll (model local scale
  stays 1 so the procedural animation composes; gravity settles any size onto the
  ground).
- **Speed model**: boss chase = `minf(7.0 * distance_factor, MAX_CHASE_SPEED 8.5)`.
  WALK 5.0 < 7.0 (walking player is run down) and 8.5 < slowest RUN 9.0 (running
  always escapes). Wander speed = plain `BASE_MOVE_SPEED` (no roll).
- **Determinism contract**: bosses introduce exactly one new hash stream
  (`hash(Vector3i(i, BOSS_SEED, run_seed))`) and read the existing pure-in-k station
  cache. Same run → same bosses at the same spots (chunk revisit regenerates the
  identical boss, since index, seed, and station are all position-derived).
  Different `run_seed` → different lateral offsets AND a different road, so bosses
  land elsewhere.
- **Block overlap**: bosses do NOT reroll against chunk obstacles (deterministic
  placement can't retry without extra draws). A boss spawning against a block is
  rare (near-centerline, structures sparse) and `move_and_slide` depenetration
  settles it — accepted simplification, noted with a `ponytail:` comment.

## Post-Completion
**Manual verification** (needs a windowed editor run — not possible headless):
- Walk the road ~300 m: first boss visible ahead on the road, clearly bigger and
  darker/redder than any regular croc; next boss bigger still.
- Let it catch a walking player (bite → lives flow); outrun it with Shift (escapes);
  outrun far enough that its chunk unloads (boss despawns = escaped).
- Phoboman stink wave: regular crocs flee, boss keeps coming.
- Giant Teibi: crushes regular crocs, is bitten by the boss.
- Restart (Play Again → `new_run()`): bosses relocate with the new road.

**Owner note for the PR**: the "giant Teibi cannot crush a boss" rule assumes a boss
(2.5x+) always out-sizes giant Teibi; flagged for the owner in the PR description.
