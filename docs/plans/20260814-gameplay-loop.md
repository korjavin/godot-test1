# Gameplay Loop: Distance Score, Per-Run Seed, Difficulty Gradient

## Overview

The game currently has no difficulty gradient, no memory, and no fail pressure: every
metre is exactly as hard as metre zero, run 2 is byte-identical to run 1, and crocodiles
(BASE_CHASE_SPEED 3.5) are slower than the player (WALK_SPEED 5.0) so they can never
catch anyone. Score is a raw coin counter, never persisted, wiped on restart.

This plan implements a coherent gameplay loop (bead godot-test1-afc.1):

1. Distance-as-headline-score (world X is strictly increasing along the coin road by
   construction, so `max(int(global_position.x))` is the score — no path integration).
2. Best-run persistence via ConfigFile at `user://best_run.cfg` with a NEW BEST flash
   on the game-over screen.
3. Per-run world seed mixed into every chunk/road hash so consecutive runs differ,
   while within-run determinism and coin seam-claiming survive untouched.
4. Croc chase speed raised above walk speed, scaling up with distance from origin.
5. Croc density scaling with distance (pure function of chunk coords).
6. Road band narrowing with distance (pure function of station index k).
7. Rare gem coins worth 10 (purple, larger).
8. Coin streak multiplier (broken by bites).
9. Modest per-character movement speed stats (0.9–1.15x).
10. Extra life every 75 coins (cap 5) + fix lives_hud.gd's duplicated MAX_LIVES.
Bonus: Enter/Space bound to Play Again on the game-over screen.

## Context (from discovery)

Files involved and the exact anchors:

- `scripts/endless_terrain.gd` (1839 lines) — the world engine.
  - Chunk object seed: line ~700 `hash(Vector2i(chunk_pos.x * 73856093, chunk_pos.y * 19349663))` in `spawn_objects_in_chunk`.
  - Ground croc seed: line ~1257 `hash(Vector2i(chunk_pos.x * 83492791, chunk_pos.y * 28411639))` in `spawn_crocodiles_in_chunk`.
  - Platform croc seed: line ~1331 `hash(Vector2i(chunk_pos.x * 40499, chunk_pos.y * 86969))` in `spawn_platform_crocodiles`.
  - Road centerline hash: `_road_hash01(k)` → `hash(Vector2i(k, ROAD_WORLD_SEED))`.
  - Road coin scatter RNG: `_road_coins_at(k)` → `rng.seed = hash(Vector2i(k, ROAD_COIN_SEED))`.
  - Station cache: `road_stations: Dictionary` + `road_k_min`/`road_k_max` (empty sentinel: min > max; `_road_extend_to_x` seeds station 0 on first use).
  - Active chunks: `active_chunks: Dictionary`, `last_player_chunk`, `update_chunks()`, `remove_chunk()`.
  - Croc density loop: `while spawned_positions.size() < crocodiles_per_chunk and attempts < max_attempts` (~line 1272), `max_attempts := crocodiles_per_chunk * 5`.
  - Band width: `_road_width(k)` lerps `road_width_min`(10)…`road_width_max`(20) on a slow cosine.
  - Seam pad in `spawn_coins_in_chunk`: `pad := maxf(road_width_min, road_width_max) * 0.5 + ...` — narrowing only ever SHRINKS the band, so the pad invariant survives item 6 untouched.
  - Coins spawned in `spawn_coins_in_chunk` via `coin_scene.instantiate()`; each coin claimed by exactly one chunk via `world_to_chunk(cw) == chunk_pos`.
- `scripts/player_controller.gd` (1597 lines) — `WALK_SPEED=5.0` (line 19), `MAX_LIVES=3` (line 123), `coins_collected` (line 110), `collect_coin()` (line 1065), `hit_by_crocodile()` (1074), `_trigger_game_over()` (1131, calls `panel.show_game_over(coins_collected)`), `restart_game()` (1149), `reset_position()` (1201), `calculate_current_speed()` (490), `CHARACTERS` array (160), `ABILITY_COOLDOWN` dict (1284).
- `scripts/coin.gd` (82 lines) — Area3D; `_on_body_entered` calls `body.collect_coin()`.
- `scripts/coin_hud.gd` (17 lines) — Label, mirrors `player.coins_collected`.
- `scripts/lives_hud.gd` — re-declares `const MAX_LIVES: int = 3` (line 16) — the latent bug.
- `scripts/game_over_ui.gd` — `show_game_over(coins)` (line 85), `_on_restart_pressed()` (line 92).
- `scripts/piglet_crocodile_ai.gd` — `BASE_MOVE_SPEED=2.5` (25), `BASE_CHASE_SPEED=3.5` (26), per-instance speed roll in `_ready()` (~220).
- ConfigFile persistence pattern to copy: `scripts/mobile_input.gd` `_load_tuning`/`_save_tuning` (lines ~540-590) — `user://` is IndexedDB-backed on web, missing file on first run is NOT an error.

Related patterns: group-based discovery only (no hard refs) — `player`, `game_over_ui`, `crocodile` groups; heavily-commented teaching style with explicit type hints; tunable constants at the top of each script. A parallel audio PR may add one-line `play_*` hooks to `coin.gd`/`player_controller.gd` — keep edits to those files small and surgical so the merge is clean.

## Development Approach

- **Testing approach**: NO unit tests. There is no test suite in this project (pure Godot
  game). Verification is by targeted headless script checks where the logic is pure
  (seed mixing, road math determinism) and by the headless web export build.
- Complete each task fully before moving to the next.
- Make small, focused changes.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Match the repo's heavily-commented teaching style and explicit type hints; new
  tunables go in constants at the top of the owning script.
- Do NOT hand-edit `.gd.uid` files. Anything spawned per-chunk must be parented to the
  chunk mesh. Do NOT touch the LOD invariants (SIM_RADIUS >> DETECTION_RADIUS,
  sleep-never-remove).

## Testing Strategy

- **Unit tests**: none.
- **Integration tests**: none as persistent files. One-off determinism checks run via
  `godot --headless -s <temp script>` where feasible; otherwise reasoning + build check.
- **Build check**: `mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html`
  if the `godot` CLI and web templates are available (CI runs it regardless). If the CLI
  is unavailable, run at minimum a GDScript parse sanity pass (e.g. `godot --headless --check-only`
  equivalent) or note it in the plan as a ⚠️ deferral.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Per-run world seed in endless_terrain.gd (the delicate one)

The goal: two consecutive runs generate different worlds; within one run every chunk
regenerates byte-identically on revisit and coin seam-claiming still holds.

- [x] Add `var run_seed: int = 0` state to `scripts/endless_terrain.gd` (documented in the
      teaching style: why it exists, why it's mixed into every hash, why it must stay
      constant for a whole run). Roll it in `_ready()` before any chunk generates:
      use a `RandomNumberGenerator` with `randomize()` and take `rng.randi()` (do not
      disturb global RNG state used elsewhere).
- [x] Mix `run_seed` into ALL five deterministic hash sites, using `Vector3i` so the mix
      is a real third hash input (not arithmetic that could alias):
      - `spawn_objects_in_chunk`: `hash(Vector3i(chunk_pos.x * 73856093, chunk_pos.y * 19349663, run_seed))`
      - `spawn_crocodiles_in_chunk`: `hash(Vector3i(chunk_pos.x * 83492791, chunk_pos.y * 28411639, run_seed))`
      - `spawn_platform_crocodiles`: `hash(Vector3i(chunk_pos.x * 40499, chunk_pos.y * 86969, run_seed))`
      - `_road_hash01`: `hash(Vector3i(k, ROAD_WORLD_SEED, run_seed))`
      - `_road_coins_at`: `rng.seed = hash(Vector3i(k, ROAD_COIN_SEED, run_seed))`
      Update the surrounding educational comments (they currently say "fixed seed /
      identical run-to-run" — now it's "fixed for the duration of a run").
- [x] Add `func new_run() -> void` to `endless_terrain.gd`: re-roll `run_seed`, clear the
      road station cache (`road_stations = {}`, reset `road_k_min`/`road_k_max` to the
      empty sentinel exactly as declared at the top of the file), `queue_free()` every
      chunk in `active_chunks` and clear the dictionary, then force an immediate rebuild
      around the spawn chunk (call `update_chunks(Vector2i(0, 0))` and set
      `last_player_chunk = Vector2i(0, 0)`) so the player teleported to (0,2,0) by
      `reset_position()` lands on solid ground the same frame.
- [x] Add the terrain to a group in `_ready()` (`add_to_group("terrain")`) and call
      `new_run()` from `player_controller.restart_game()` via
      `get_tree().get_first_node_in_group("terrain")` with a `has_method` guard —
      matching the project's group-based wiring convention.
- [x] Verify determinism by reasoning AND a headless check if the CLI allows: within a
      run `run_seed` never changes, so every seed site is still a pure function of
      (chunk coords | k) — revisited chunks regenerate identically and the coin
      seam-claiming (`world_to_chunk(cw) == chunk_pos`) is untouched. Across
      `new_run()` calls the mixed hashes differ. Document this invariant in a comment
      block above `run_seed`.

### Task 2: Distance as headline score (player + HUD)

- [x] Add `var run_distance: int = 0` to `scripts/player_controller.gd` (documented:
      the coin road's X is strictly increasing by construction, so farthest-X *is*
      the distance travelled along the run — no path integration needed). Update it in
      `_physics_process`: `run_distance = maxi(run_distance, int(global_position.x))`.
      Reset to 0 in `restart_game()` (and in `reset_position()` alongside the coin wipe).
- [x] Show it live in `scripts/coin_hud.gd`: label becomes e.g.
      `"Distance: %dm   Coins: %d"` (streak multiplier suffix comes in Task 6).
- [x] Pass it to the game-over screen: `_trigger_game_over()` calls
      `panel.show_game_over(coins_collected, run_distance)`; update
      `game_over_ui.show_game_over` signature and add a distance label
      (distance is the HEADLINE — larger/above the coin tally).

### Task 3: Best-run persistence (ConfigFile at user://best_run.cfg)

- [ ] In `scripts/player_controller.gd`, add best-run state (`best_distance: int`,
      `best_coins: int`) loaded in `_ready()` from `user://best_run.cfg` via ConfigFile —
      copy the load/save pattern (and its comments about first-run missing file being
      fine and web IndexedDB persistence) from `scripts/mobile_input.gd`
      `_load_tuning`/`_save_tuning`. Constants at top: `BEST_RUN_CONFIG_PATH`, section name.
- [ ] In `_trigger_game_over()`: compute `is_new_best := run_distance > best_distance`;
      if the run beat either record, update `best_distance`/`best_coins`
      (track them independently: best_distance is the record distance, best_coins the
      record coin count — each updates on its own max) and save the ConfigFile.
      Pass everything to the UI: `show_game_over(coins, distance, best_distance, best_coins, is_new_best)`.
- [ ] In `scripts/game_over_ui.gd`: add a "Best: NNNm / NN coins" line, and a
      "NEW BEST!" flash label shown only when `is_new_best` (bright colour; a simple
      Tween scale/blink pulse built in code is enough — no assets).

### Task 4: Difficulty gradient (crocs faster + denser, road narrower with distance)

- [ ] `scripts/piglet_crocodile_ai.gd`: raise `BASE_CHASE_SPEED` from 3.5 to 5.5
      (now above WALK_SPEED 5.0 — a walking player gets caught; running/abilities escape).
      In `_ready()`, after the existing per-instance speed roll, multiply
      `chase_speed_instance` by a distance factor
      `1.0 + clampf(absf(global_position.x) / 3000.0, 0.0, 0.6)` — new constants at top
      (`DISTANCE_SPEED_SCALE_DENOM: float = 3000.0`, `DISTANCE_SPEED_SCALE_MAX: float = 0.6`)
      with a teaching comment (global_position is valid in _ready because the terrain
      parents the croc before _ready runs).
- [ ] `scripts/endless_terrain.gd` `spawn_crocodiles_in_chunk`: density scales with
      distance — compute `var chunk_croc_target := crocodiles_per_chunk + mini(8, absi(chunk_pos.x) / 6)`
      and use it in BOTH the while condition and `max_attempts` (`chunk_croc_target * 5`).
      Pure function of chunk coords → determinism within a run is preserved. Note in the
      comment that the LOD manager keeps the extra distant crocs cheap (slept, never removed).
- [ ] `scripts/endless_terrain.gd` `_road_width(k)`: narrow the band with distance —
      after computing the oscillating width, scale it toward a floor:
      `var narrow_t := clampf(float(absi(k)) / 2000.0, 0.0, 1.0)` and
      `return lerpf(width, road_width_min * 0.4, narrow_t)` (new constants at top:
      `ROAD_NARROW_STATIONS: int = 2000`, `ROAD_NARROW_FLOOR_FACTOR: float = 0.4`).
      Stays pure-in-k. Add a comment noting the seam `pad` in `spawn_coins_in_chunk`
      remains a safe upper bound because narrowing only ever SHRINKS the band below
      `maxf(road_width_min, road_width_max)`.

### Task 5: Gem coins worth 10

- [ ] `scripts/coin.gd`: add `var value: int = 1` and `var is_gem: bool = false`, plus a
      `func make_gem() -> void` that sets value 10, scales the coin up (~1.6x), and
      recolours the mesh purple with emission (duplicate the mesh material at runtime —
      never mutate the shared resource; follow the same defensive-duplicate pattern as
      `_setup_web_fog`). Collection passes the value: `body.collect_coin(value)`.
      Keep the diff surgical (a parallel audio PR touches this file).
- [ ] `scripts/endless_terrain.gd` `_road_coins_at(k)`: after a slot's position draws,
      roll one extra `rng.randf()` for the gem chance (`ROAD_GEM_CHANCE: float = 0.04`,
      constant at top). Return entries as `{ "pos": Vector3, "gem": bool }` dictionaries
      instead of bare Vector3s. The extra draw changes the per-station RNG sequence —
      that is deliberate and fine because the run_seed scheme (Task 1) already regenerated
      the world; determinism within a run holds because the draw ORDER is fixed.
- [ ] `spawn_coins_in_chunk`: consume the new entry shape (`cw.pos` for bucketing/height
      logic, call `coin.make_gem()` after instantiate when `cw.gem`). Every use of the
      old bare-Vector3 value must be updated — grep for `_road_coins_at` callers.

### Task 6: Coin streak multiplier + per-character speeds + extra lives

- [ ] `scripts/player_controller.gd`: streak state (`coin_streak: int`,
      `streak_timer: float`, `const STREAK_WINDOW: float = 2.5`,
      `const STREAK_MAX_BONUS: int = 4`, `const STREAK_COINS_PER_STEP: int = 10`).
      `collect_coin(value: int = 1)`: refresh `streak_timer`, increment `coin_streak`,
      score `value * (1 + mini(STREAK_MAX_BONUS, coin_streak / STREAK_COINS_PER_STEP))`
      into `coins_collected`. Tick `streak_timer` down in `_physics_process`; at zero
      reset `coin_streak`. Break the streak in `hit_by_crocodile()` (before the
      invulnerability early-return? NO — after it, so ignored bites don't break streaks).
      Expose `func get_streak_multiplier() -> int` for the HUD.
- [ ] `scripts/coin_hud.gd`: append ` (x%d)` when the multiplier is > 1, e.g.
      `Distance: 240m   Coins: 87 (x3)`.
- [ ] `scripts/player_controller.gd`: `const CHARACTER_SPEED := { "windman": 1.0,
      "primm": 1.15, "teibi": 0.9, "phoboman": 1.05 }` next to `ABILITY_COOLDOWN`;
      multiply into `calculate_current_speed()`'s duck/run/walk returns (NOT the
      windman air-rush return — the ability already defines its own speed). Keep the
      spread modest (0.9–1.15) so no character is unplayable.
- [ ] Extra life every 75 coins: `const EXTRA_LIFE_COINS: int = 75`,
      `const LIVES_CAP: int = 5`, `var next_extra_life_at: int = EXTRA_LIFE_COINS`.
      In `collect_coin()`, while `coins_collected >= next_extra_life_at`: advance the
      threshold and `lives = mini(lives + 1, LIVES_CAP)`. Reset `next_extra_life_at`
      in `restart_game()`/`reset_position()`. (While-loop, not if: a single gem+streak
      pickup can jump across a threshold — or even two.)
- [ ] Fix `scripts/lives_hud.gd`: DELETE its own `const MAX_LIVES` and read the pip
      count from the player via the existing group lookup —
      `maxi(player.MAX_LIVES, player.lives)` pips total, `lives` of them filled — so a
      4th/5th heart renders correctly and the duplication bug is gone. Track the drawn
      pip count in the repaint-on-change guard too (redraw when either lives or the
      total changes).

### Task 7: Enter/Space restart + verify acceptance criteria

- [ ] `scripts/game_over_ui.gd`: restart on `ui_accept` — in `_unhandled_input` (or
      `_input`), when `visible` and `event.is_action_pressed("ui_accept")`, call the
      same `_on_restart_pressed()` path and mark the event handled. `ui_accept` covers
      Enter AND Space out of the box; no project.godot change needed.
- [ ] Re-read the bead's acceptance criteria and verify each is implemented:
      live+game-over distance; best persists (ConfigFile written); two runs differ
      (run_seed mixed into all 5 hash sites); within-run chunk regen identical (no
      seed site depends on anything but coords/k + run_seed); crocs catch a walking
      player (5.5 > 5.0); density/speed/narrowing scale with distance; gems + streak
      in HUD; 4th heart renders; Enter/Space restarts.
- [ ] Run the headless web export if the godot CLI + templates are available:
      `mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html`.
      If unavailable, add a ⚠️ note that build verification is deferred to CI.

### Task 8: [Final] Update documentation

- [ ] Update CLAUDE.md: new "Gameplay loop" notes — run_seed mixing (and the
      new_run()/restart contract), distance score, best-run ConfigFile, difficulty
      gradient knobs, gem/streak/extra-life mechanics, lives_hud now reads the player.
      Amend the now-stale claims ("identical run-to-run", "coins... reset to 0 only on
      a full restart" stays true, `_road_coins_at` return shape).

## Technical Details

- **run_seed mixing**: `Vector3i(a, b, run_seed)` through Godot's `hash()` — same shape
  at all five sites so the pattern is obvious. `run_seed` is rolled once per run and
  only ever changed by `new_run()`; everything downstream stays a pure function of
  (coords|k, run_seed).
- **new_run() ordering**: re-roll seed → clear road cache → free+clear chunks →
  rebuild around (0,0). Called from `restart_game()` BEFORE `reset_position()` returns
  control (restart_game already teleports via reset_position; call new_run() first so
  the rebuilt chunks exist when the player lands — reset_position puts the player at
  (0,2,0) and terrain rebuild in the same frame is fine since chunks are built
  synchronously in update_chunks).
- **Croc speed vs escape hatches**: 5.5 chase > 5.0 walk but < RUN_SPEED and abilities;
  the distance scale (+60% at 3km) makes late-run walking lethal.
- **`_road_coins_at` return shape change**: Array of `{ pos, gem }` dicts — the only
  caller is `spawn_coins_in_chunk`.
- **best_run.cfg keys**: section `"best"`, keys `distance`, `coins`. Ints.

## Post-Completion

**Manual verification** (needs a real browser/editor session):
- Play two runs and eyeball that the block/croc layout differs between them.
- Walk ~1km+ and feel the croc pressure/narrowing (or temporarily lower the denominators).
- Reload the page after a game over and confirm the Best line survives (IndexedDB).
- Confirm gem coins are visually obvious and the streak counter feels right on mobile.

**External**:
- CI web build on push validates the export regardless of local CLI availability.
- Parallel audio PR (godot-test1-zxx) may merge while this is in flight — merge master
  keeping both sides; optionally add one-line sound hooks for gem pickup / extra life /
  new best if the sound manager exists by then.
