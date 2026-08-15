# Weather: drifting clouds, storm-cloud rain zones, rare birds

## Overview

Add ambient weather to the endless field, owned by ONE new self-contained script
`scripts/weather_manager.gd` (a `Node` under `Main` in `scenes/main.tscn`, joining the
group `"weather"`, exactly like `CrocodileLODManager` / `SoundManager`):

- **Clouds** — a drifting field of blocky white cloud clusters at 45–70 m altitude in a
  ~250 m radius around the player, recycled to fresh positions ahead when they drift too
  far behind. Deliberately NOT part of `endless_terrain.gd`: clouds are ambience, not
  world content, so they need no per-chunk determinism (precedent: crocodile size/speed
  rolls are already `randomize()`d).
- **Storm clouds + rain** — ~1 in 7 clouds rolls dark and defines a moving circular ground
  rain zone. ONE `CPUParticles3D` emitter follows the player and only emits while the
  player is inside a zone. A synthesized rain loop fades in/out through the sound
  manager's `get_loop_player("rain")`, and the ambient wind bed ducks slightly under it.
- **Gameplay API** — `is_raining_at(world_pos: Vector3) -> bool`. Windman's Air Rush
  refuses to fire in the rain (blocked-press feedback, cooldown NOT consumed), and a
  Windman already flying who enters a rain zone drops out of the boost early (wet wings).
- **Birds** — every 60–120 s a small flock of 3–7 birds crosses the sky high up with
  sine-driven wing flaps, despawning past the field radius. No collision, no AI.

Benefits: the new sky gradient from the rendering PR finally has something in it, rain is
a rare event with real gameplay consequence for one character, and the whole thing is one
file plus a five-line scene node.

## Context (from discovery)

Files/components involved:
- `scripts/weather_manager.gd` — NEW, essentially all of the work.
- `scenes/main.tscn` — one `[node name="Weather" type="Node" parent="." groups=["weather"]]`
  block plus its `[ext_resource]` line. Keep this diff minimal: parallel executors are
  editing this file too.
- `scripts/player_controller.gd` — TWO small Windman hooks only (a parallel executor is
  heavily rewriting this file; do these LAST, right after a fresh
  `git fetch origin master && git merge origin/master`).

Related patterns found:
- **Group discovery, never hard references**: `get_tree().get_first_node_in_group("player")`
  (`crocodile_lod_manager.gd`), `_sfx()` in `player_controller.gd` (`sound_manager` group +
  `has_method` guard). Weather follows the same rule in both directions.
- **Throttled manager tick**: `crocodile_lod_manager.gd` uses `SCAN_INTERVAL = 0.11`
  (~9 Hz) rather than per-frame work. Clouds do the same.
- **MultiMesh batching**: `endless_terrain.gd`'s per-chunk block MultiMesh — shared unit
  `BoxMesh`, `transform_format = TRANSFORM_3D`, `use_colors = true`, one shared
  `StandardMaterial3D` with `vertex_color_use_as_albedo = true`. Clouds and birds copy
  this so each costs ONE draw call.
- **Synthesized audio**: `sound_manager.gd` builds every stream in code
  (`_synth_wind()` = one-pole low-passed noise + a crossfaded loop seam) and hands out
  named looping players via `get_loop_player(name)`, which lazily creates a player with a
  null stream for any new name. `is_unlocked()` guards playback until the browser's
  first-gesture audio unlock.
- **Ability structure**: `player_controller.gd` SECTION 8 —`try_activate_ability()`
  dispatches by character name after a cooldown check; `windman_boost_timer` is counted
  down in `_update_ability_timers()`.

Dependencies identified: none new. No assets, no GPUParticles3D (web runs
`gl_compatibility`), no new project settings.

## Development Approach
- **Testing approach**: NO unit tests. This is a Godot project with no test suite,
  linter, or build script — the checks are `godot --headless --path . --import` and
  `godot --headless --path . scenes/main.tscn --quit-after 3` running clean, plus the F3
  perf overlay for the draw-call budget.
- Complete each task fully before moving to the next.
- Make small, focused changes.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility: with the weather node absent (running
  `scenes/player.tscn` alone, or any other scene), the player must behave exactly as
  today — every weather lookup is null-safe + `has_method`-guarded.

## Testing Strategy
- **Unit tests**: none. Do not add unit tests.
- **Integration tests**: none add a real guarantee here (no test harness exists in this
  repo). Verification is the headless run below.
- **E2E tests**: none — the project has no e2e suite.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## What Goes Where
- **Implementation Steps**: code changes in this repo.
- **Post-Completion**: on-device/browser look-and-feel checks that need human eyes.

## Implementation Steps

### Task 1: Cloud field skeleton — `scripts/weather_manager.gd`
- [x] create `scripts/weather_manager.gd` (`extends Node`) with the project's
      teaching-density header comment: what it owns, why it is NOT in `endless_terrain.gd`
      (ambience, no per-chunk determinism), and how other scripts reach it (group
      `"weather"` + `has_method` guard)
- [x] declare ALL tunables as `const`s at the top with explicit type hints and a comment
      each: `FIELD_RADIUS: float = 250.0`, `CLOUD_COUNT: int = 26`,
      `CLOUD_ALTITUDE_MIN/MAX: float = 45.0/70.0`, `BOXES_PER_CLOUD_MIN/MAX: int = 4/9`,
      `CLOUD_BOX_SIZE_MIN/MAX`, `CLOUD_SPREAD` (how far boxes scatter from the cluster
      centre), `WIND_DIR: Vector3` (normalized, XZ only), `WIND_SPEED: float = 1.6`,
      `CLOUD_SPEED_VARIATION: float = 0.25`, `BOB_AMPLITUDE`, `BOB_SPEED`,
      `TICK_INTERVAL: float = 0.1`
- [x] `_ready()`: `add_to_group("weather")`, `randomize()`-style RNG init (a
      `RandomNumberGenerator` member, `randomize()`d — cosmetic randomness only, nowhere
      near the terrain's deterministic chunk RNG; say so in a comment)
- [x] build the cloud data model: an `Array` of per-cloud `Dictionary`s
      `{ "center": Vector3, "boxes": Array, "is_storm": bool, "radius": float,
      "speed": float, "bob_phase": float }`, where each box entry is
      `{ "offset": Vector3, "size": Vector3, "yaw": float }`. A `_make_cloud()` helper
      rolls one cloud; a `_place_cloud_around(cloud, player_pos, ahead_only)` helper
      positions it (initial fill = anywhere in the disc; recycling = upwind edge only)
- [x] find the player by group each tick (`_player` cached, re-fetched when invalid) —
      no hard references, and do nothing at all while no player exists

### Task 2: Cloud rendering — one MultiMesh, one draw call
- [x] in `_ready()`, build a single `MultiMeshInstance3D` child (`_cloud_mmi`) with a
      shared unit `BoxMesh`, `transform_format = TRANSFORM_3D`, `use_colors = true`, and
      `instance_count = CLOUD_COUNT * BOXES_PER_CLOUD_MAX` (fixed allocation; unused slots
      are parked with a zero-scale basis — cheaper and simpler than repacking, note it
      with a `ponytail:` comment)
- [x] give it ONE shared `StandardMaterial3D`: `vertex_color_use_as_albedo = true`,
      `roughness = 1.0`, `specular = 0.0` (soft matte white, NO transparency — alpha on
      big sky quads is mobile fill-rate poison, say so in the comment)
- [x] `cast_shadow = SHADOW_CASTING_SETTING_OFF` on the MultiMesh instance, with the
      comment explaining why: the tuned `directional_shadow_max_distance` is ~55 m, so
      clouds at 45–70 m are outside the shadow range anyway — do not fight it
- [x] per-instance colour: near-white for normal clouds (slight per-cloud brightness
      jitter), dark blue-grey for storm clouds (`STORM_COLOR`), both as `const`s
- [x] `_process(delta)`: accumulate into `_tick_accum` and only do cloud work every
      `TICK_INTERVAL` — drift each cloud centre by `WIND_DIR * cloud.speed * elapsed`, add
      the sine bob, recycle any cloud whose along-wind distance behind the player exceeds
      `FIELD_RADIUS`, then write every instance transform
      (`Basis(Vector3.UP, yaw).scaled(size)` + origin) and colour. 10 Hz is deliberate:
      at ~1.6 m/s the step is ~16 cm on a 50 m-distant object — invisible, and it keeps
      the manager off the per-frame budget

### Task 3: Storm clouds and the `is_raining_at()` API
- [x] `STORM_CHANCE: float = 1.0 / 7.0` — on `_make_cloud()`, roll storm; storm clouds get
      a bigger box count/size multiplier (`STORM_SIZE_FACTOR`) and the dark colour
- [x] compute and store each cloud's ground-zone `radius` from its actual box spread
      (`RAIN_ZONE_FACTOR` × cluster radius) so the rain zone matches what the player sees
      overhead
- [x] implement `func is_raining_at(world_pos: Vector3) -> bool` — a flat XZ distance test
      against every storm cloud's moving centre. Only a handful of storm clouds exist, so
      this is a few `distance_squared_to` calls; document that it is cheap enough to call
      per-frame from the player
- [x] maintain `_player_in_rain: bool`, recomputed on the throttled tick from
      `is_raining_at(player.global_position)`, so enter/exit transitions are detected once
      per tick rather than per frame

### Task 4: Rain particles — one CPUParticles3D, active only inside a zone
- [x] in `_ready()` build ONE `CPUParticles3D` child (`_rain`) — NOT `GPUParticles3D`
      (the web build runs `gl_compatibility`; comment this) — with `emitting = false`,
      `amount = RAIN_PARTICLE_COUNT` (120), `local_coords = false` (so the streaks stay in
      world space while the emitter follows the player), `lifetime`, `gravity` and
      `direction`/`initial_velocity` set for a fast vertical fall plus a slight wind lean
- [x] mesh: a thin elongated `BoxMesh` streak with a shared unshaded-ish grey material
      (`albedo_color` pale grey-blue, `shading_mode` unshaded, `cast_shadow` OFF)
- [x] emission: `EMISSION_SHAPE_BOX` with half-extents covering the play area around the
      player, the emitter parked `RAIN_SPAWN_HEIGHT` above the player's head; reposition
      it on the throttled tick only while raining
- [x] toggle `emitting` ONLY on the `_player_in_rain` transition, so the whole rain path
      costs literally nothing when it is not raining (beyond the manager's own tick)

### Task 5: Rain sound loop + wind ducking
- [x] synthesize the rain loop inside `weather_manager.gd` itself (`_synth_rain_stream()`,
      mirroring `sound_manager._synth_wind()`: one-pole low-passed noise, but brighter/
      hissier for rain, with the same crossfaded loop seam, converted to a 16-bit mono
      `AudioStreamWAV` and marked `LOOP_FORWARD`). Keeping the synthesis local keeps
      `sound_manager.gd` untouched — zero merge conflict with the parallel executors
- [x] fetch the dedicated player via the `"sound_manager"` group's `get_loop_player("rain")`
      (null-safe + `has_method` guard, same as `player_controller._sfx()`), assign the
      stream once, and only `play()` once `is_unlocked()` reports the browser gesture has
      landed
- [x] fade `volume_db` between `RAIN_SILENT_DB` (-60) and `RAIN_VOLUME_DB` over
      `RAIN_FADE_TIME` on zone enter/exit; stop the player once it has faded fully out so
      a silent voice is not left mixing
- [x] duck the existing ambient wind bed by `WIND_DUCK_DB` while rain is audible, using
      the same fade progress, and restore it exactly when the rain fades out (capture the
      wind player's original `volume_db` once rather than assuming a constant)

### Task 6: Rare bird flocks
- [x] constants: `BIRD_INTERVAL_MIN/MAX: float = 60.0/120.0`, `BIRD_FLOCK_MIN/MAX: int = 3/7`,
      `BIRD_ALTITUDE_MIN/MAX: float = 30.0/40.0`, `BIRD_SPEED`, `BIRD_FLAP_HZ`,
      `BIRD_WING_LENGTH`, `BIRD_BOB_*`, `BIRD_COLOR` (dark)
- [x] a second `MultiMeshInstance3D` (`_bird_mmi`) sized `BIRD_FLOCK_MAX * 3` instances
      (body + two wings per bird), sharing the same unit `BoxMesh` with its own dark
      material, `cast_shadow` OFF; instance count parked at zero scale while no flock is
      alive so it draws nothing
- [x] a countdown timer spawns a flock: pick a random crossing line through the player's
      neighbourhood, give each bird a small lateral/vertical offset from the flock leader
      and its own flap phase
- [x] update birds EVERY frame (not on the 10 Hz tick) while a flock is alive — a wing
      flap at a few Hz aliases badly at 10 Hz, and ≤21 instances updated only during the
      rare seconds a flock exists is free; wings rotate about their local forward axis by
      `sin(TAU * BIRD_FLAP_HZ * t + phase)` and the body bobs gently
- [x] despawn the flock (park instances, restart the countdown) once the leader is past
      `FIELD_RADIUS` from the player
- [x] no collision, no AI, no interaction, no caw sound — the bead marks the caw optional;
      skip it rather than growing `sound_manager.gd`, and note the skip in the comment

### Task 7: Wire the manager into `scenes/main.tscn` (minimal diff)
- [x] add exactly one `[ext_resource type="Script" path="res://scripts/weather_manager.gd" id="15_weather"]`
      line and one node block
      `[node name="Weather" type="Node" parent="." groups=["weather"]]` with its
      `script = ExtResource("15_weather")`, placed next to `SoundManager`
- [x] bump `load_steps` accordingly and change NOTHING else in the file — a parallel
      fauna executor is adding its own node line, so the merge must stay trivial

### Task 8: The TWO Windman hooks in `scripts/player_controller.gd` (do LAST)
- [x] FIRST run `git fetch origin master && git merge origin/master` — a parallel executor
      is heavily rewriting this file; do this task only after that merge is clean
- [x] add a small null-safe helper (`_weather_is_raining_here() -> bool`) that finds the
      `"weather"` group node and calls `is_raining_at(global_position)` behind a
      `has_method` guard, so scenes without the manager behave exactly as today
- [x] hook (a): in `try_activate_ability()`, when the current character is `windman` and
      `_weather_is_raining_here()`, bail out BEFORE firing — do NOT set the cooldown, do
      NOT play the whoosh — and surface the existing blocked-press feedback by calling
      `flash_blocked()` on the `"ability_hud"` group node behind a `has_method` guard
      (the parallel game-feel PR adds it; degrade silently if it is not there yet)
- [x] hook (b): in `_update_ability_timers()`, when `windman_boost_timer > 0.0` and
      `_weather_is_raining_here()`, zero the boost timer so wet wings drop him back into
      normal gravity mid-flight
- [x] keep the `player_controller.gd` diff to exactly these three additions — nothing else

### Task 9: Verify acceptance criteria
- [x] verify every Overview requirement is implemented (clouds drift + recycle, storm
      clouds define moving rain zones, rain particles + sound only inside a zone,
      `is_raining_at()` exists and is used by both Windman hooks, birds cross rarely)
- [x] verify edge cases: no player in the scene (manager idles), no sound manager (silent,
      no errors), audio not yet unlocked (no `play()`), no weather node (player
      unaffected), rain zone entered/exited repeatedly (fade never latches, `emitting`
      never left on)
- [x] `godot --headless --path . --import` runs clean (no script/parse errors)
- [x] `godot --headless --path . scenes/main.tscn --quit-after 3` runs clean (no runtime
      errors or warnings from the new script)
- [x] confirm the draw-call budget: clouds = 1 MultiMesh, birds = 1 MultiMesh, rain = 1
      particle system only while raining — a few extra draw calls, not a few hundred
      (the F3 perf overlay is the measure)

### Task 10: [Final] Update documentation
- [ ] add a short "Weather (clouds, rain zones, birds)" section to `CLAUDE.md` in the
      existing style: what the manager owns, why it is NOT in `endless_terrain.gd`,
      the `is_raining_at()` contract, the two Windman hooks, and the perf shape
      (2 MultiMeshes + 1 conditional CPUParticles3D, throttled 10 Hz tick)
- [ ] leave README/QUICKSTART alone (they are already stale about the engine version)

## Technical Details

**Cloud data flow (per throttled tick):**
`player pos` → drift centres by `WIND_DIR * cloud.speed * elapsed` → recycle clouds whose
along-wind offset behind the player exceeds `FIELD_RADIUS` (re-rolled upwind, at a fresh
altitude/size, so the field never depletes) → write `CLOUD_COUNT * BOXES_PER_CLOUD_MAX`
instance transforms + colours into the one MultiMesh.

**Rain zone test:** `is_raining_at(p)` = `any(storm)` where
`Vector2(p.x - c.x, p.z - c.z).length_squared() <= zone_radius²`. Storm clouds are a
handful (≈1 in 7 of 26), so this is ~4 squared-distance tests — safe to call per frame.

**Rain audio state machine:** `_rain_mix` is a 0..1 float lerped toward
`1.0 if _player_in_rain else 0.0` at `1.0 / RAIN_FADE_TIME` per second;
`rain.volume_db = lerp(RAIN_SILENT_DB, RAIN_VOLUME_DB, _rain_mix)` and
`wind.volume_db = wind_base_db + WIND_DUCK_DB * _rain_mix`. `play()` on the way up when
`_rain_mix` leaves 0, `stop()` when it reaches 0 again.

**Why no full-screen darkening ColorRect:** the bead lists it as optional. A full-screen
alpha-blended rect is exactly the mobile fill-rate cost the perf conventions warn about,
for a subtle effect the particles + sound already sell. Skipped deliberately (recorded as
a `ponytail:` note in the script, trivial to add later if the mood falls flat).

## Post-Completion

**Manual verification:**
- Play the desktop build and watch the sky: clouds should read as soft white blocky
  clusters against the new gradient, drifting slowly in one direction, never popping in
  view (recycling happens upwind, outside the field).
- Wait for / walk into a storm cloud's shadow footprint: rain particles should appear
  around the player, the rain loop fades in and the ambient wind ducks; leaving the zone
  fades both back.
- As Windman, press F inside rain: nothing fires, the dial flashes blocked (once the
  game-feel PR's `flash_blocked()` has landed), and the cooldown is still full. Air Rush
  out of clear sky INTO a rain zone: the boost should cut out mid-flight.
- Leave the game running a couple of minutes to catch a bird flock crossing high up.
- Check the web export in a browser (and ideally a phone) for frame rate: F3 draw calls
  should rise by only a few, not dozens.
