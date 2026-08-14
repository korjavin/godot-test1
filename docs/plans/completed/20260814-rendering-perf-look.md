# Rendering Layer: Perf Wins + Art-Directed Look (web-first)

## Overview

Bead **godot-test1-afc.3**. Two audits (perf + visual) converge on one rendering-layer
change set, executed in two phases:

- **Phase A (perf)**: the web build is draw-call bound (~490 unbatched crocodiles rendered
  up to 5x each in main pass + 4 default PSSM shadow splits at 100 m), chunk generation is
  synchronous on the main thread (all 49 chunks in one frame at startup = multi-second
  phone freeze; 7–13 chunks on boundary crossings), and glow burns a fullscreen blur every
  frame while nothing exceeds its threshold. Fix the draw-call and hitch sources WITHOUT
  reducing any entity counts (repo law).
- **Phase B (look)**: warm ~35° key light with a real sun disc, finished sky gradient,
  UNIVERSAL fog (desktop too — an owner-sanctioned exception to the web-gate rule),
  glow that earns its pass (blooming coins), BCS color grade, a vertex-noise ground
  shader, curated block color ramps, toon+rim crocodiles, and a 15° coin rest tilt.

Everything in Phase B is verified shippable in `gl_compatibility` (SSAO/DOF/volumetric do
NOT exist there — do not attempt them). Visual changes here are cross-platform BY DESIGN.

## Context (from discovery)

Files involved:
- `scripts/endless_terrain.gd` (1964 lines) — chunk engine. Per-chunk `print()` at :1382
  and :1431; O(n²) membership scan in `update_chunks` (`chunk_pos not in chunks_to_load`
  over an Array); a NEW `PlaneMesh` allocated per chunk in `create_chunk` (:631–635,
  subdivide 10×10); web-only fog in `_setup_web_fog` (:466); `new_run()` (:1908) rebuilds
  the world SYNCHRONOUSLY via `update_chunks(Vector2i(0,0))` so the respawned player lands
  on solid ground the same frame — that safety must survive time-slicing; block colors
  rolled in `create_box` (:1152–1178) with a **load-bearing RNG draw sequence** (the file
  documents this: same count + order per chunk or the whole world layout shifts).
- `scenes/main.tscn` — `DirectionalLight3D` has ONLY `shadow_enabled = true` (default 4
  PSSM splits @ 100 m); Environment has `glow_enabled = true` with default threshold
  (nothing blooms → wasted pass); half-edited ProceduralSky (only horizon colors set).
- `scenes/characters/piglet_crocodile.tscn` — dead `HitBox` Area3D (:25–31); the AI script
  itself documents (piglet_crocodile_ai.gd :600–604) that nothing connects to it.
- `scripts/piglet_crocodile_ai.gd` — `set_lod_active` (:587) toggles the dead HitBox via
  `set_deferred`; `_physics_process` early-returns at :304 while `!lod_active` but the
  script dispatch itself still happens ~460×/tick.
- `scripts/crocodile_lod_manager.gd` — the existing throttled (~9 Hz) distance scan;
  the natural home for a coin `set_process` gate (same pattern, same tick).
- `scenes/collectibles/coin.tscn` + `scripts/coin.gd` — ~250 coins each running `_process`
  spin+bob every frame; coin `emission_energy_multiplier = 0.6` (too dim to bloom);
  coin mesh casts shadows; rest pose is dead vertical.
- `scripts/ability_hud.gd` — unconditional `queue_redraw()` every frame (:38–42).
- `scripts/player_controller.gd` — `apply_toon_shading` (:903–922) is the toon+rim
  treatment to LIFT into a shared helper. **Touch this file surgically — a game-feel bead
  owns it next.** Only the lift + delegation call may change.
- `assets/shaders/` — has `outline.gdshader`; ground shader goes here.

Patterns found:
- Group-based discovery everywhere (`player`, `crocodile`, `coin`, `terrain` groups).
- Shared-resource lazy getters: `_get_shared_unit_box_mesh()` / `_get_shared_block_material()`
  (endless_terrain.gd :358–382) — the exact pattern for the shared ground PlaneMesh.
- Defensive `duplicate()` of the shared Environment before mutating (`_setup_web_fog`).
- Teaching-style comments + explicit type hints + constants at top of each script.

Hard invariants (repo law — violating any is a blocker):
1. **Determinism**: within a run, chunk regeneration must stay byte-identical. Every
   chunk-seeded RNG must consume EXACTLY the same number of draws in the same order.
   `run_seed` semantics (rolled in `_ready`/`new_run`, mixed into all five hash sites)
   are preserved untouched.
2. **Entity counts are never reduced**: same crocodiles/blocks/coins as before. Crocs are
   slept or visually culled, never removed.
3. **SIM_RADIUS (45) >> DETECTION_RADIUS (15)** stays; LOD sleep semantics unchanged.
4. Croc damage path: do NOT touch collision layers/masks (croc mask 3 detects player on
   layer 1).
5. No GPUParticles3D dependencies.

## Development Approach

- **Testing approach**: NO unit tests (project has no test suite). Verification is:
  `godot --headless --path . --quit-after 2` runs clean (no script errors) and the
  headless web export builds.
- Complete each task fully before moving to the next; small focused commits.
- Phase A tasks first — they fund Phase B.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Match the codebase's teaching-comment density when editing existing files.

## Testing Strategy

- **Unit tests**: none.
- **Integration tests**: none — no test infrastructure exists; the headless run + web
  export are the automated guarantees.
- **E2E tests**: none.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope

## Implementation Steps

### Task 1: Terrain quick wins — prints, Dictionary membership, shared ground mesh

- [x] `scripts/endless_terrain.gd`: delete the two PER-CHUNK `print()` calls — the
      "Spawned %d crocodiles…" (:1382, with its `if spawned_positions.size() > 0` guard)
      and "Spawned %d patrolling crocodile(s)…" (:1431, with its `if count > 0` guard).
      Keep the one-time `_ready()` and `new_run()` prints — they fire once, not per chunk.
- [x] `scripts/endless_terrain.gd` `update_chunks`: replace the O(n²) Array membership
      (`chunk_pos not in chunks_to_load` — a linear scan per active chunk, and again per
      candidate) with a Dictionary keyed by `Vector2i` (value `true`); membership becomes
      O(1) hash lookups. Keep the same load/remove/create semantics. Add a short teaching
      comment about why Dictionary membership beats Array `in` here.
- [x] `scripts/endless_terrain.gd`: add a `_get_shared_ground_mesh()` lazy getter (same
      pattern and placement as `_get_shared_unit_box_mesh`, :358) returning ONE
      `PlaneMesh` shared by all chunks: `size = Vector2(chunk_size, chunk_size)`,
      `subdivide_width = 16`, `subdivide_depth = 16` (16×16 — enough vertices for the
      Task 8 vertex-noise ground shader), `material = terrain_material`. In
      `create_chunk`, use it instead of allocating a new `PlaneMesh` per chunk (:631–635).
      Note: all chunks are the same size, so one mesh serves every chunk; the material
      hookup must happen AFTER `terrain_material` exists (getter runs post-`_ready`, so
      reading `terrain_material` inside the getter is safe — but guard the order anyway
      by assigning the material inside the getter from the current `terrain_material`).
- [x] `scripts/endless_terrain.gd` `create_chunk`: set
      `mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF` on the
      ground plane — a flat ground plane can only ever shadow itself; skipping it cuts
      every chunk out of the shadow passes for free.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Env note: this worktree has no `.godot` import cache, so the headless run
      shows 20 PRE-EXISTING errors (unimported piglet_crocodile.glb, MobileSensors
      class-cache misses) — verified identical on the unmodified baseline via
      `git stash`. Zero errors originate from the edited endless_terrain.gd.
      "Clean" here = no NEW errors vs baseline.

### Task 2: Crocodile perf — dead HitBox removal, physics-process sleep, draw-range cull

- [x] `scenes/characters/piglet_crocodile.tscn`: delete the `HitBox` Area3D node and its
      `HitBoxShape` child (:25–31) and the now-unused `SphereShape3D_1` sub-resource
      (and drop `load_steps` accordingly). The AI script itself documents nothing connects
      to it — it is ~2 dead nodes + 1 physics area × ~490 crocs.
- [x] `scripts/piglet_crocodile_ai.gd` `set_lod_active`: remove the HitBox
      `set_deferred("monitoring", …)` block (:617–622-ish) and rewrite the surrounding
      doc/comments (:600–609 reference the HitBox cleanup — they must go too, including
      the stale mention at :207–210 near the `lod_active` var).
      ➕ Also scrubbed the HitBox mention from crocodile_lod_manager.gd's header.
- [x] `scripts/piglet_crocodile_ai.gd` `set_lod_active`: add
      `set_physics_process(active)` on the state change — a slept croc's script is no
      longer dispatched at all (~460 saved dispatches per physics tick). KEEP the
      `if not lod_active: velocity = Vector3.ZERO; return` early-return at the top of
      `_physics_process` as a backstop (comment it as such), and keep zeroing `velocity`
      inside `set_lod_active(false)` so the freeze stays immediate.
- [x] `scripts/piglet_crocodile_ai.gd` `_ready`: after caching `model`, walk the model
      subtree and on every `GeometryInstance3D` (equivalently `MeshInstance3D`) found set
      `visibility_range_end = 60.0` and `visibility_range_end_margin = 8.0` (both as new
      named constants at the top, e.g. `VISUAL_CULL_DISTANCE` / `VISUAL_CULL_MARGIN`).
      This is a pure DRAW cull (works in gl_compatibility; the universal fog from Task 6
      hides the pop) — the croc entity itself stays alive, slept by the LOD manager as
      before. Counts unchanged: comment must say so explicitly. This same walk is reused
      in Task 9 for toon shading — structure it as one helper method
      (`_style_model_meshes()` or similar) so the subtree is walked once.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Same env note as Task 1: pre-existing unimported-glb errors only; verified
      the error set is IDENTICAL to the stashed baseline (sole diff: the .tscn parse
      error's line number shifted 18→15 because the scene file got shorter).

### Task 3: Shadow tuning + art-directed key light (main.tscn)

- [x] `scenes/main.tscn` `DirectionalLight3D`: add shadow tuning —
      `directional_shadow_mode = 1` (2 splits instead of 4),
      `directional_shadow_max_distance = 55.0`,
      `directional_shadow_blur = 1.2`,
      `shadow_normal_bias = 0.8`.
      ➕ Property-name fix: the plan said `directional_shadow_normal_bias`, but the
      real Godot 4 Light3D property is `shadow_normal_bias` — used the real name so
      the value actually applies.
      1024 px (web) spread over 55 m / 2 splits ≈ crisper contact shadows AND a 2–4×
      cheaper shadow pass than 100 m / 4 splits.
- [x] `scenes/main.tscn` `DirectionalLight3D`: art-direct the key —
      `light_color = Color(1, 0.94, 0.82)` (warm), `light_energy = 1.15`,
      `light_angular_distance = 1.5` (also makes the ProceduralSky draw a real sun disc).
      Rotate the sun to ~35° elevation raking SIDEWAYS across the +X run direction
      (e.g. rotation ≈ (-35°, -125°, 0°) so light comes from high-left of the run axis);
      compute the `transform` basis for the .tscn from those Euler angles. Drop the
      irrelevant translation-Y=10 origin or keep it (directional lights ignore position).
      Basis computed from YXZ Euler (-35°, -125°, 0°), verified 35.0° elevation;
      origin kept (harmless).
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Same env note as Tasks 1–2: pre-existing unimported-glb warnings only;
      warning/error line set identical to the stashed baseline (only the occurrence
      count of the per-croc './Model' warning varies run-to-run with the run seed).

### Task 4: Time-sliced chunk generation (one chunk per frame, nearest-first)

- [x] `scripts/endless_terrain.gd`: add state at the top of SECTION 2 (with teaching
      comments): `var pending_chunks: Array[Vector2i] = []` plus a companion
      `var pending_lookup: Dictionary = {}` for O(1) dedupe, and a constant
      `const SYNC_RING: int = 1` (chunks within Chebyshev distance ≤ 1 of the player's
      chunk are built synchronously — the safety ring the player can reach this frame).
- [x] Rework `update_chunks(player_chunk)`: still computes needed set + removes far
      chunks immediately (unchanged), but instead of creating ALL missing chunks in one
      frame it (a) creates missing chunks with `max(|dx|,|dz|) <= SYNC_RING`
      IMMEDIATELY (player + ring 1 — at startup and after `new_run()` that is 9 chunks,
      on a normal boundary crossing at most 3, so the player NEVER stands over an unbuilt
      chunk), and (b) queues the rest into `pending_chunks` sorted nearest-first by
      squared distance to `player_chunk`, dropping any previously-pending chunk that
      fell out of range (rebuild the queue from scratch each call — it only runs on
      boundary crossings, so a full rebuild is cheap and simpler than incremental
      surgery).
- [x] `_process`: after the existing boundary-crossing check, dequeue and `create_chunk`
      exactly ONE pending chunk per frame (skip entries already created). 40 pending
      chunks = 40 frames (~0.7 s) of progressive fill hidden behind the fog, instead of
      one multi-second freeze.
- [x] `new_run()`: clear `pending_chunks`/`pending_lookup` in step 2–3 (they were
      computed for the old world), then keep calling `update_chunks(Vector2i(0,0))` —
      with the rework that synchronously builds the spawn chunk + ring 1 (the landing
      safety the current synchronous rebuild provides — comment MUST say the respawned
      player teleports to (0,2,0) the same frame, so ring-1-sync is the load-bearing
      guarantee), queueing the remaining ~40 for progressive fill.
- [x] Determinism note in comments: generation ORDER does not affect content — every
      chunk's RNG is seeded purely from its own coords + `run_seed`, and the road
      station cache is pure in `k` — so time-slicing cannot change the world. Verify the
      claim holds by reading `spawn_coins_in_chunk`'s station-cache extension (it is
      monotonic and order-independent) before writing the comment.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean (the player must
      not fall through: watch for "fell off" resets in output).
      ⚠️ Same env note as Tasks 1–3: ran with --quit-after 300 for a longer soak;
      error set verified byte-identical to the stashed baseline (pre-existing
      unimported-glb + MobileSensors class-cache errors only). Zero "fell off"
      resets — the SYNC_RING landing safety holds. Backtraces confirm both paths
      exercise: sync ring via update_chunks, progressive fill via _process.
      Verified before writing the determinism comment: _road_extend_to_x grows the
      station cache contiguously from station 0 via a recurrence pure in k, so
      chunk generation order cannot change road/coin content.

### Task 5: Coin cost + presentation — process gating, no shadow, brighter emission, rest tilt

- [x] `scripts/crocodile_lod_manager.gd`: extend the existing ~9 Hz throttled scan to
      ALSO gate coins: for every node in the `"coin"` group, `set_process(false)` when
      beyond `COIN_ANIM_RADIUS = 30.0` from the player and `set_process(true)` within,
      with the same hysteresis-margin pattern (`COIN_HYSTERESIS = 5.0`) and
      only-on-state-change discipline as the croc scan (track state per coin via a small
      `Dictionary` keyed by instance id, or read `coin.is_processing()` directly —
      whichever is cleaner). Distant coins simply stop spinning/bobbing (invisible at
      30 m+); collection is Area3D-signal driven and does NOT depend on `_process`, so a
      frozen coin still collects normally. Do NOT touch collision layers/masks. Update
      the script's header comment: it is now the small "animation/simulation LOD"
      manager for crocs + coins (name kept for history).
- [x] `scenes/collectibles/coin.tscn`: on the `Mesh` MeshInstance3D set `cast_shadow = 0`
      (a 0.35 m coin's shadow is invisible noise; ~250 casters removed from the shadow
      pass) and raise the gold material's `emission_energy_multiplier` from 0.6 to 1.6
      so coins genuinely exceed the Task 6 glow threshold and bloom.
- [x] Coin rest tilt (~15° off vertical so the spin shows face AND edge):
      in `scripts/coin.gd`, keep the spin in `_process` but compose the mesh basis as
      `Basis(Vector3.UP, spin_angle) * TILT_BASIS * mesh_base_basis` where
      `TILT_BASIS = Basis(Vector3.RIGHT, deg_to_rad(15.0))` and `mesh_base_basis` is the
      scene-authored basis cached in `_ready` — i.e. the coin spins around the world-up
      axis while permanently leaning 15°. (`rotate_y` alone cannot express this once the
      mesh is tilted; the explicit compose is the simple correct form.) `make_gem()`
      needs no change (it scales the whole Area3D). NO pickup tween/pop — the game-feel
      bead owns that.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Same env note as Tasks 1–4: pre-existing unimported-glb + MobileSensors
      class-cache errors only; unique-error set verified byte-identical to the
      stashed baseline (coin.gd / crocodile_lod_manager.gd load with zero errors).

### Task 6: Finished sky, UNIVERSAL fog, glow that earns its pass, BCS grade

- [x] `scenes/main.tscn` `ProceduralSkyMaterial_1`: finish the sky —
      `sky_top_color = Color(0.25, 0.45, 0.75)`,
      `sky_horizon_color = Color(0.85, 0.86, 0.80)` (warm pale),
      `ground_horizon_color = Color(0.85, 0.86, 0.80)` (match, seamless horizon band),
      `ground_bottom_color` = a desaturated terrain green (e.g. `Color(0.28, 0.33, 0.25)`),
      `sun_curve = 0.08` (visible sun halo; pairs with Task 3's angular_distance disc).
- [x] `scenes/main.tscn` `Environment_1`: make glow earn its already-paid pass —
      `glow_hdr_threshold = 0.85`, `glow_intensity = 0.6`, `glow_bloom = 0.05`. The
      compatibility renderer hardcodes screen-blend for glow — if it blooms hot, tune
      `glow_intensity` DOWN rather than the threshold up (leave a comment in the plan /
      commit message, the .tscn can't carry comments). Add the BCS grade:
      `adjustment_enabled = true`, `adjustment_contrast = 1.08`,
      `adjustment_saturation = 1.18`, and `tonemap_white = 1.2`,
      `tonemap_exposure = 1.05` (tonemap_mode stays 2/Filmic).
      NOTE for future tuners (the .tscn can't carry comments): if glow blooms hot in
      the compatibility renderer's hardcoded screen-blend, tune `glow_intensity`
      DOWN — do not raise the threshold.
- [x] `scripts/endless_terrain.gd`: make fog UNIVERSAL — this is an intentional,
      owner-sanctioned desktop visual change (the one deliberate exception to the
      "visual changes are web-gated" rule; say exactly that in the comments and update
      the stale web-only rationale at :24–62). Concretely: rename `_setup_web_fog` →
      `_setup_fog` and drop its `OS.has_feature("web")` early-return; rename
      `WEB_FOG_COLOR` → `FOG_COLOR` and set it to the NEW sky horizon color
      `Color(0.85, 0.86, 0.80)` (the :50–53 comment documents the fog-tracks-horizon
      contract — keep that contract, update the value + comment); split density into
      `FOG_DENSITY_WEB = 0.005` (short view, thick mask) and
      `FOG_DENSITY_DESKTOP = 0.0022` (long view, soft depth haze) chosen by
      `OS.has_feature("web")` — a DENSITY difference is a perf/view-distance concern and
      stays platform-gated even though the fog itself is universal; set
      `fog_sun_scatter = 0.15` (was 0.0 — a gentle bright streak toward the new warm
      sun). Keep the defensive `duplicate()` and the one-time print (update its text).
      ➕ Also updated the stale `_setup_web_fog` cross-reference in coin.gd's
      make_gem() docstring to the new `_setup_fog` name.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Same env note as Tasks 1–5: pre-existing unimported-glb + MobileSensors
      class-cache errors only; unique-error set diffed against the stashed baseline —
      sole difference is backtrace line numbers shifting (endless_terrain.gd grew by
      ~15 comment lines). Headless run confirms the desktop fog path fires:
      "Fog enabled (density 0.0022, colour (0.85, 0.86, 0.8, 1.0))".

### Task 7: Ground vertex-noise shader

- [x] Create `assets/shaders/ground.gdshader` (`shader_type spatial`): in `vertex()`,
      compute a large-scale 2-octave value-noise float from the WORLD-space XZ of the
      vertex (`(MODEL_MATRIX * vec4(VERTEX, 1.0)).xz`; sin/hash-based, e.g.
      `fract(sin(dot(p, vec2(...))) * ...)` smoothed with a `sin`-blend octave at ~1/40 m
      and ~1/13 m scales) and pass it as a `varying float`. In `fragment()`, `ALBEDO =
      mix(GREEN_A, GREEN_B, n)` with uniforms defaulting to `vec3(0.42, 0.55, 0.24)` and
      `vec3(0.20, 0.44, 0.26)`; `ROUGHNESS = 0.8` (match the old StandardMaterial3D).
      FILL RATE UNTOUCHED: the fragment stage does only the varying lerp — all noise math
      is per-VERTEX (the 16×16 subdivided plane from Task 1 provides the vertices).
      World-space input means the pattern is continuous across chunk seams with zero
      per-chunk work. Teaching comments in the shader.
- [x] `scripts/endless_terrain.gd` `_ready`: build the ground material as a
      `ShaderMaterial` loading `ground.gdshader` instead of the default green
      `StandardMaterial3D` (keep the `@export var terrain_material` escape hatch: if a
      material IS provided in the editor, honor it; only the built-in default switches
      to the shader). Type of `terrain_material` export must widen from
      `StandardMaterial3D` to `Material` for this — update the export and its comment.
- [x] Run `godot --headless --path . --quit-after 2` — must be clean (shader compile
      errors surface here).
      ⚠️ Same env note as Tasks 1–6: pre-existing unimported-glb + MobileSensors
      class-cache errors only; unique-line diff vs the stashed baseline shows ONLY
      backtrace line numbers shifting (endless_terrain.gd grew ~7 comment lines)
      plus the usual seed-dependent './Model' warning backtrace variance. Zero
      shader compile errors; main.tscn assigns no terrain_material override, so
      the ShaderMaterial default is live.

### Task 8: Curated block color ramps (RNG-sequence-preserving)

- [x] `scripts/endless_terrain.gd` `create_box` (:1152–1178): replace the three
      per-channel-random color branches with three hand-picked RAMPS sharing a warm
      undertone, each sampled by ONE lerp: 0 = warm sandstone→terracotta
      (`Color(0.72, 0.58, 0.42)` → `Color(0.65, 0.38, 0.28)`), 1 = slate→blue-grey
      (`Color(0.38, 0.40, 0.45)` → `Color(0.55, 0.58, 0.63)`), 2 = olive→moss
      (`Color(0.42, 0.45, 0.26)` → `Color(0.30, 0.42, 0.28)`). Declare the six Color
      endpoints as consts at the top of the file near `SHARED_BLOCK_ROUGHNESS`.
- [x] **HARD CONSTRAINT — consume EXACTLY the same RNG draws in the same order** (the
      existing :1146–1151 comment documents why; extend it): keep `rng.randi_range(0, 2)`
      as the ramp selector, then per branch consume the SAME number of `randf_range`
      calls as today — branch 0 (was 3 draws): first draw is the ramp `t`, the next two
      are drawn and DISCARDED; branch 1 (was 1 draw): the single draw is `t`; branch 2
      (was 3 draws): first is `t`, two discarded. Keep the discarded roughness draw
      (:1178) untouched. Use the same `randf_range` ARGUMENT ranges as before for the
      draws (the values are remapped/discarded, but keeping the calls textually parallel
      makes the preservation auditable) — then normalize the used draw to 0..1 for the
      lerp `t`. Comment each discard exactly like the existing roughness-discard note.
- [x] Keep the `.srgb_to_linear()` conversion on the final color (the :1203–1214 comment
      explains why; ramps don't change that logic). (Untouched — sits after the match.)
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ⚠️ Same env note as Tasks 1–7: pre-existing unimported-glb + MobileSensors
      class-cache errors only; unique-error set verified byte-identical to the
      stashed baseline. Draw audit: branch 0 = 3 randf_range, branch 1 = 1,
      branch 2 = 3, plus the roughness discard — 5/3/5 total, unchanged.

### Task 9: Croc toon+rim via shared helper (ONE static cached material set)

- [x] Create `scripts/toon_shading.gd` (`class_name ToonShading extends RefCounted`) with
      one static method `apply_to_mesh(mesh: MeshInstance3D) -> void` containing the
      EXACT logic of `player_controller.apply_toon_shading` (:903–922: per-surface, skip
      already-toon, duplicate → `diffuse_mode = DIFFUSE_TOON`, `rim_enabled`, `rim 0.4`,
      `rim_tint 0.25`), PLUS a `static var _styled_cache: Dictionary = {}` keyed by the
      source material's `get_instance_id()` mapping to its styled duplicate — so ~490
      crocodiles sharing the same GLB materials get ONE styled duplicate per source
      material, never per-croc duplicates. Teaching comment: the cache is the whole
      point — per-croc duplicates would be ~490 extra materials AND break batching.
- [x] `scripts/player_controller.gd`: SURGICAL edit only — replace the BODY of
      `apply_toon_shading` with a delegation to `ToonShading.apply_to_mesh(mesh)` (keep
      the method + docstring so call sites and teaching flow are untouched). The shared
      cache is correct for the player too (same source material → same styled result).
      Touch NOTHING else in this file.
- [x] `scripts/piglet_crocodile_ai.gd` `_ready`: in the Task 2 model-subtree walk, call
      `ToonShading.apply_to_mesh(mesh)` on each MeshInstance3D — crocs get the same
      toon+rim cohesion as the hero. Do NOT add the inverted-hull outline overlay to
      crocs (a second draw call × 490 — unaffordable; comment says so).
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      ➕ Env upgrade: ran `godot --headless --import` once to build the missing
      `.godot` class-name cache (ToonShading is a `class_name` and needs it).
      Result: the run is now FULLY clean — zero errors — and the pre-existing
      unimported-glb/MobileSensors baseline errors from Tasks 1–8 are gone too.
      Error diff vs stashed baseline: empty both ways. The import also
      generated `toon_shading.gd.uid` and the previously-missing
      `ground.gdshader.uid` (committed — Godot manages these).

### Task 10: Ability HUD redraw gating

- [x] `scripts/ability_hud.gd` `_process`: gate `queue_redraw()` on the DISPLAYED state
      actually changing. Cache the last-drawn tuple — ready flag, ability name, the
      cooldown ratio quantized to arc-visible steps (e.g. `roundi(ratio * 128.0)`), and
      the remaining-seconds string (`"%.1f"`) — and redraw only when any differ (or when
      the player reference was just [re]acquired). While the ability is READY and
      nothing changes (the common case), the HUD costs zero redraws. Update the
      "redrawing each frame … is cheap" comment (:41) to explain the new gate.
      (Implemented as one composed string key `ready|name|quantized|secs` — a single
      compare, no tuple plumbing; empty string = force-redraw sentinel on [re]acquire.)
- [x] Run `godot --headless --path . --quit-after 2` — must be clean.
      Fully clean run (post-Task-9 import cache), exit 0, zero errors.

### Task 11: Verify acceptance criteria + docs

- [x] Re-read the plan Overview + all hard invariants; verify each is honored (grep for
      leftover `WEB_FOG`, dead HitBox references, per-chunk prints; re-check the RNG
      draw count in `create_box` by counting calls per branch old vs new).
      Audit results: zero `WEB_FOG` hits, zero HitBox hits (scripts/ + scenes/);
      only one-time prints remain in endless_terrain.gd (_ready ×5, fog ×1,
      new_run ×1); create_box draws = selector + 3/1/3 per branch + roughness
      discard = 5/3/5, matching the audit table. Collision layers untouched,
      SIM_RADIUS/DETECTION_RADIUS untouched, no GPUParticles3D anywhere.
- [x] `godot --headless --path . --quit-after 2` runs clean.
      Fully clean (post-Task-9 import cache), exit 0, zero errors; desktop fog
      line prints (density 0.0022).
- [x] Headless web export builds: `mkdir -p build/web && godot --headless
      --export-release "Web" build/web/index.html` (exit 0, index.html + wasm produced).
      Exit 0; index.html, index.wasm, index.js, index.pck all produced.
- [x] Update `CLAUDE.md`: (a) fog is now UNIVERSAL (desktop too) — document it as the
      sanctioned exception to the web-gate rule, with density still platform-gated;
      (b) time-sliced chunk generation (one/frame nearest-first, SYNC_RING safety for
      spawn/new_run); (c) HitBox is gone from the croc scene (update the LOD-contract
      paragraph that mentions `$HitBox` monitoring); (d) `ToonShading` shared helper +
      croc styling + visual cull range; (e) LOD manager now also gates coin `_process`;
      (f) shared ground mesh + ground shader + curated block ramps (with the RNG-
      preservation note); (g) main.tscn light/sky/glow/grade values.
      All seven items landed: new time-slicing + shared-ground paragraphs in the
      terrain section, LOD section rewritten (HitBox gone, set_physics_process,
      draw cull, coin gating), new "Art-directed look" section for (d)+(g), fog
      bullet + conventions exception rewritten for (a), block-MultiMesh paragraph
      updated for the ramps, new_run description updated for the sliced rebuild.
- [x] ➕ NOTE (honest deferral, decided at planning time): **B10 near-ring grass is
      SKIPPED.** (Acknowledged — not implemented, per its own verify-first gate.) Its own acceptance gate — "only if A-phase wins are verified via the F3
      overlay" — cannot be met in this environment (headless, no display, no real web
      device to read F3 on). Shipping unverifiable extra geometry against an explicit
      verify-first gate would be dishonest; it remains a clean follow-up once someone
      can measure. Do not implement it.

## Technical Details

- **Draw-cull vs sleep**: two independent radii — LOD sleep at 45/50 m (simulation,
  existing) and `visibility_range_end` 60/8 m (rendering, new). Rendering cull is wider
  than the sleep radius, so a visible croc is never a frozen-mid-stride sleeper close up.
- **Time-slicing math**: startup on web = 49 chunks → 9 sync + 40 progressive frames;
  desktop = 121 → 9 sync + 112 frames (~2 s of background fill, invisible beyond fog).
  Boundary crossing worst case: 2·(2r+1) new chunks, of which ≤ 3 are in the sync ring.
- **RNG audit table for `create_box`** (old = new, per branch, after the selector draw):
  branch 0: 3 randf_range; branch 1: 1 randf_range; branch 2: 3 randf_range; then always
  1 roughness randf_range (discarded). Total draws per block unchanged: 5/3/5.
- **Fog contract**: `FOG_COLOR` == `sky_horizon_color` == `ground_horizon_color`
  (0.85, 0.86, 0.80). If the sky changes again, all three move together.
- Compatibility renderer notes: `visibility_range_*` works; glow works (screen-blend
  hardcoded); `light_angular_distance` sun disc works with ProceduralSky; NO SSAO/DOF/
  volumetric — never referenced.

## Post-Completion

**Manual verification** (requires a real browser/phone — not possible in this env):
- F3 overlay on a web build: draw calls should be roughly halved; `Crocs (active/total)`
  total unchanged (proves no entity reduction).
- Walk across several chunk boundaries: no visible hitch; progressive fill hidden by fog.
- Desktop run: fog present but subtle (0.0022), horizon dissolves instead of hard edge.
- Coins visibly bloom; sun disc visible in sky; block palette reads curated, layout
  unchanged within a run (restart from game-over gives a NEW world — per-run seed).
- If someone later verifies headroom on-device via F3, B10 grass is the ready follow-up
  (per-chunk MultiMesh ~250 crossed quads, visibility_range_end ~45, buffer-filled,
  scatter RNG drawn AFTER all existing consumers).
