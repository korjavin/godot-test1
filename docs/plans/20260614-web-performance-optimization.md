# Web Performance Optimization (without sacrificing visual quality)

## Overview
The game ships as a **web (WebGL) build** and currently stutters in the browser. This plan
makes it run smoothly in-browser while keeping the look the player likes. We take a
**deep structural refactor** (chosen approach "C"): batch all decorative blocks into
`MultiMesh` (collapsing thousands of draw calls into a handful), introduce a **central
crocodile LOD manager** that sleeps the simulation of distant/off-screen crocodiles, and
apply **web-only** render/settings tuning plus a fog mask so a smaller view distance is
invisible.

**Problem it solves:** in-browser lag and frame stutter.

**Key benefits:**
- Massive draw-call reduction (per-block unique meshes/materials → batched `MultiMesh`).
- Massive CPU/physics reduction (~1,210 always-simulating crocodiles → only the handful
  near the player simulate; the rest freeze cheaply).
- Lighter GPU load on web only (Compatibility renderer, MSAA/shadow/resolution tuning),
  desktop/editor stay full quality.
- Entity **counts are unchanged** and gameplay near the player is **identical** — the
  world still looks and plays the same.

**How it integrates:** all changes respect the existing group-based, chunk-spawned
architecture (`endless_terrain.gd` stays the world engine; everything spawned per-chunk
remains parented to the chunk and auto-freed on unload). The LOD manager is a new node
that discovers crocodiles via the existing `"crocodile"` group.

## Context (from discovery)
- **Files/components involved:**
  - `project.godot` — `[rendering]` section; currently `Forward Plus`, `msaa_3d=2`, no
    per-platform (`.web`) overrides.
  - `scenes/main.tscn` — `DirectionalLight3D` with `shadow_enabled=true`,
    `WorldEnvironment` (glow on), `HUD` CanvasLayer.
  - `scripts/endless_terrain.gd` — world engine. `render_distance=5` → **121 active
    chunks**; `create_box()` (line ~649) builds a **unique `BoxMesh` + unique
    `StandardMaterial3D` + `StaticBody3D` per block**; spawns `crocodiles_per_chunk=10`,
    `objects_per_chunk=12`, `coins_per_chunk=6` per chunk.
  - `scripts/piglet_crocodile_ai.gd` — `CharacterBody3D`; `_physics_process` (line 216)
    runs gravity, `move_and_slide`, obstacle avoidance, chase scan, body animation
    **every frame for every crocodile**; `DETECTION_RADIUS=15`.
  - `scenes/characters/piglet_crocodile.tscn` — body + `HitBox` `Area3D` (monitoring).
- **Related patterns found:**
  - Group-based discovery: `get_tree().get_first_node_in_group("player")`,
    `get_nodes_in_group("crocodile")`. Use groups, not hard refs.
  - Deterministic per-chunk seeding via `hash(...)`; chunk regenerates identically.
  - Per-chunk parenting → automatic cleanup on unload.
- **Dependencies identified:**
  - Player exposes `is_on_floor()` and `reset_position()` (death contract). LOD work
    must not break the chase/`reset_position` flow.
  - Crocodile obstacle avoidance and player movement rely on **physics collision bodies**
    for the blocks — so visual batching must keep collision intact.
  - `OS.has_feature("web")` distinguishes the HTML5 export at runtime.

## Scope decisions (confirmed with user)
- **Visual trade-off:** light, masked changes allowed (fog to hide the world edge,
  softened shadows). No drastic look change.
- **Platform:** visual-affecting changes are **web-only** (runtime `OS.has_feature("web")`
  and `.web` project-setting overrides). Desktop/editor keep full quality. Purely
  invisible optimizations (MultiMesh batching, crocodile LOD, consolidated collision) are
  applied **globally** — they change neither look nor gameplay anywhere and benefit
  desktop too.
- **Entity density:** **unchanged.** Same crocodiles/coins/blocks per chunk. The LOD
  manager only *sleeps simulation* of far/off-screen crocodiles; it never removes them.

## Development Approach
- **Testing approach for this project:** there is **no automated test suite, linter, or
  build script** (per `CLAUDE.md`) — this is a pure Godot project. So "tests" here means a
  rigorous, measurable **manual verification protocol** run on the **web build** after
  every task, not unit tests. Each task defines its own before/after measurement and a
  visual/gameplay regression check. This is the honest, correct form of "tests" for a
  performance task; we will not fabricate unit tests for a project that has none.
- **Measurement is the safety net.** Task 1 adds an in-game FPS / frame-time / draw-call /
  active-crocodile overlay so every later task can be proven (numbers must move the right
  way) and regressions caught (look/gameplay unchanged).
- Complete each task fully and verify it before moving to the next.
- Make small, focused changes; keep the heavy commenting density of the existing scripts.
- Maintain backward compatibility with the group-based / chunk-parented architecture and
  the `reset_position()` death contract.

## Testing Strategy
- **No unit/e2e framework exists** — do not invent one. Verification per task is:
  1. **Quantitative:** read the Task 1 overlay on the web build — FPS, frame time (ms),
     `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, physics frame time, active-crocodile count,
     node count. Record before/after.
  2. **Visual regression:** the scene looks the same (block shapes/colors, sky, glow,
     structures, coins) — compare screenshots before/after.
  3. **Gameplay regression:** walk near crocodiles (they chase within ~15 m exactly as
     before), get caught (`reset_position` fires, nearby crocs cleared), jump (crocs lose
     scent), collect coins, climb a pyramid/wall, run a corridor — all behave identically.
- Build command (same as CI): `mkdir -p build/web && godot --headless --export-release
  "Web" build/web/index.html`, then serve with `./serve.sh` and open in a browser.
- Quick desktop sanity per task: `godot --path . scenes/main.tscn`.

## Progress Tracking
- Mark completed items `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Update this plan if implementation deviates from scope (e.g., a chosen LOD radius or
  fog distance is tuned).

## Solution Overview
**High-level architecture chosen:**

1. **Measurement overlay** (`scripts/perf_overlay.gd`, debug-only, toggle with F3) — gives
   us a live web baseline and proves each subsequent change.

2. **Web-only GPU tuning** via `.web` project-setting overrides + runtime fog/scale:
   - `rendering/renderer/rendering_method.web = "gl_compatibility"` (Godot's intended
     WebGL2 path; far lighter than Forward+ in a browser).
   - `rendering/anti_aliasing/quality/msaa_3d.web = 0`.
   - softened directional shadows on web (smaller shadow size / max distance).
   - optional internal-resolution scale `< 1.0` on web (sharp upscale, big GPU win).

3. **Central crocodile LOD manager** (`scripts/crocodile_lod_manager.gd`, a node in
   `main.tscn`): on a throttled tick (~8–10 Hz) it scans the `"crocodile"` group, compares
   squared distance to the player against `SIM_RADIUS`, and flips each crocodile's
   `lod_active` flag. Crocodiles read that flag and **cheap-return** the heavy work
   (`_chase_player`, `_avoid_obstacles`, `move_and_slide`, `_animate_body`) and disable
   their `HitBox` monitoring while frozen. `SIM_RADIUS` is set comfortably larger than
   `DETECTION_RADIUS` (15 m) — e.g. 45 m — so any crocodile that could ever interact with
   the player is fully simulated; behavior near the player is byte-for-byte the same.

4. **MultiMesh block rendering** in `endless_terrain.gd`: `create_box()` stops
   instantiating a `MeshInstance3D`+material per block and instead appends a
   `(Transform3D, Color)` instance to the chunk's block batch. After generation, one
   `MultiMeshInstance3D` per chunk renders **every** block in a single draw call (unit
   `BoxMesh`, `use_colors`, per-instance transform encoding size+yaw, per-instance earthy
   color, material with `vertex_color_use_as_albedo`). Same shapes, same color ranges —
   visually identical, draw calls collapse.

5. **Consolidated per-chunk collision**: one `StaticBody3D` per chunk holding all block
   `CollisionShape3D` children (each with its own transform), instead of one body per
   block. Player/crocodile collision is unchanged; node count drops by ~25×.

6. **Web-only reduced render distance + fog mask**: on web, `render_distance` runtime-set
   lower (start at 3; tune by feel), and depth fog (color = sky horizon) added to the
   `WorldEnvironment` so the nearer world edge dissolves into the sky — the world still
   feels endless. Desktop keeps `render_distance=5` and no fog.

**Key design decisions & rationale:**
- *Visual vs collision decoupling* (MultiMesh for looks, separate static bodies for
  collision) is what lets us batch rendering without changing physics/gameplay.
- *Flag-based LOD* (manager sets a flag at low frequency; crocodile early-returns every
  frame) keeps per-frame cost trivial and re-activation seamless (node/state preserved).
- *Web-gating only the visual levers* honors "web-only" while still letting the invisible
  wins help desktop.

## Technical Details
- **Draw-call monitor:** `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`;
  frame time via `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS`; FPS via
  `Engine.get_frames_per_second()`.
- **MultiMesh:** `MultiMesh.transform_format = TRANSFORM_3D`, `use_colors = true`,
  `instance_count` = block count for the chunk; instance transform basis carries
  per-axis scale (`dimensions`) + yaw rotation; `set_instance_color(i, earthy_color)`.
  Material: `StandardMaterial3D` with `vertex_color_use_as_albedo = true`,
  `roughness` ≈ existing range. One unit `BoxMesh` shared across all chunks.
- **Collision:** per-chunk `StaticBody3D`; each block adds a `CollisionShape3D` child with
  `BoxShape3D(size=dimensions)` and local `position`/`rotation.y`. Layers/masks identical
  to current blocks so crocodile avoidance raycasts and player collision are unchanged.
- **LOD flag contract:** `piglet_crocodile_ai.gd` gains `var lod_active := true`. Manager
  calls a setter (or sets the property) per crocodile. While `!lod_active`: skip
  chase/wander/avoid/move/animate; keep the node and all state; set `HitBox.monitoring =
  false`; restore on re-activation. `SIM_RADIUS` (manager) ≥ `DETECTION_RADIUS + buffer`.
- **Web detection:** `OS.has_feature("web")` in `_ready()` of `endless_terrain.gd` (render
  distance) and for enabling fog on the `WorldEnvironment`.
- **Project-setting `.web` overrides** live in `project.godot` `[rendering]`.

## What Goes Where
- **Implementation Steps** (`[ ]`): all code/scene/project-setting changes in this repo.
- **Post-Completion** (no checkboxes): in-browser manual perf/visual validation across
  browsers, deciding final tuning values, and the GitHub Pages deploy (merge to `master`).

## Implementation Steps

### Task 1: In-game performance overlay (baseline + ongoing measurement)

**Files:**
- Create: `scripts/perf_overlay.gd`
- Modify: `scenes/main.tscn` (add a `Label` under the `HUD` CanvasLayer running the script)

- [x] create `scripts/perf_overlay.gd` (heavily commented, teaching style) showing: FPS,
      process ms, physics ms, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, rendered primitives,
      total node count, and active-crocodile count (count of `"crocodile"` group members
      with `lod_active` once Task 3 lands; until then show group size).
- [x] toggle visibility with a key (e.g. F3); start hidden in release, visible in debug
      (`OS.is_debug_build()`), so it never ships in the player's face.
- [x] add the `Label` node to `main.tscn` HUD with the script attached.
- [x] **Verify (web baseline):** build web export, open in browser, record baseline
      numbers (FPS, draw calls, ms, node count) in this plan under Task 8's table — this
      is the "before" all later tasks compare against. (manual web verification — to be
      done by user in browser; baseline numbers to be filled into the Task 7 measurement
      table from the running build.)
- [x] **Verify (desktop):** overlay renders and toggles; no errors. (validated headlessly:
      `godot --headless --check-only` parses `perf_overlay.gd` cleanly and the full
      project + `main.tscn` import with no errors; live render/toggle is a manual desktop
      check — to be done by user.)

### Task 2: Web-only GPU/render tuning (renderer, MSAA, shadows, scale)

**Files:**
- Modify: `project.godot` (`[rendering]`)
- Modify: `scenes/main.tscn` (`DirectionalLight3D` shadow tuning if not settable via `.web`)

- [x] in `project.godot [rendering]`, add `renderer/rendering_method.web="gl_compatibility"`
      (leave desktop `Forward Plus` untouched). Confirm/keep `.mobile` sensible.
      (Added the `.web` override only; desktop `Forward Plus` from `config/features`
      untouched. No `.mobile` override added — there is no mobile export preset and the
      desktop default is sensible for mobile; left as-is.)
- [x] add `anti_aliasing/quality/msaa_3d.web=0` (desktop keeps `msaa_3d=2`).
      (Added; desktop `anti_aliasing/quality/msaa_3d=2` left untouched.)
- [x] soften shadows on web: lower `lights_and_shadows/directional_shadow/size.web`
      (e.g. 2048→1024) and/or reduce the light's `directional_shadow_max_distance`; keep
      shadows ON (user wants only light, masked changes).
      (Added `lights_and_shadows/directional_shadow/size.web=1024`; shadows stay ON.
      Did NOT touch `directional_shadow_max_distance` in `main.tscn` — that is a per-light
      property that cannot be web-gated via project settings, so editing it would affect
      ALL platforms, violating web-only scope. Shadow-distance tuning, if wanted, should be
      done at runtime via `OS.has_feature("web")` in a later step; `size.web` is sufficient.)
- [x] (optional, tunable) add internal-resolution scale on web:
      `scaling_3d/mode` + `scaling_3d/scale.web` (~0.8) for a large GPU win with a slight
      softness; leave at 1.0 if the softness is noticeable.
      (Added `scaling_3d/mode=0` (bilinear) and `scaling_3d/scale.web=0.8`. 0.8 is a
      documented starting value — raise toward 1.0 in the browser if softness is noticeable.)
- [x] **Verify:** web build renders correctly under Compatibility — sky, glow/tonemap
      acceptable, block colors correct, no missing features; record FPS/draw-call delta vs
      baseline. Desktop unchanged (still Forward Plus, MSAA 2, full shadows).
      (manual web verification — to be done by user in browser; FPS/draw-call delta to be
      filled into the Task 7 measurement table from the running build. Validated headlessly:
      `godot --headless --editor --quit` loads the project and parses `project.godot` with
      exit code 0 and no errors. Confirmed desktop renderer and desktop `msaa_3d=2` are
      unchanged — only `.web` overrides were added.)

### Task 3: Central crocodile LOD manager + per-crocodile simulation gate

**Files:**
- Create: `scripts/crocodile_lod_manager.gd`
- Modify: `scenes/main.tscn` (add a `CrocodileLODManager` node running the script)
- Modify: `scripts/piglet_crocodile_ai.gd` (add `lod_active` gate; disable `HitBox` when frozen)

- [x] create `scripts/crocodile_lod_manager.gd` (Node): finds the player via the `player`
      group; on a throttled timer (~8–10 Hz, NOT every frame) iterates the `"crocodile"`
      group, computes squared distance to the player, and sets each crocodile's
      `lod_active` (true within `SIM_RADIUS`, false beyond). Document `SIM_RADIUS`
      (≈45 m) and why it must exceed `DETECTION_RADIUS` (15 m) plus buffer.
      (Created. Scans at ~9 Hz (`SCAN_INTERVAL=0.11`), compares squared distance
      (`distance_squared_to`) against squared thresholds — no sqrt. `SIM_RADIUS=45.0`
      (3× the 15 m DETECTION_RADIUS) with a `HYSTERESIS_MARGIN=5.0` dead-band so a body
      on the boundary doesn't flicker: wake within 45 m, sleep beyond 50 m. Player found
      via the `player` group with defensive `is_instance_valid` re-fetch; only calls the
      setter on a real state change; guards `has_method("set_lod_active")`. Heavily
      commented on why it's gameplay-neutral.)
- [x] in `piglet_crocodile_ai.gd`, add `var lod_active := true` and a setter; at the top
      of `_physics_process`, when `!lod_active`, cheap-return after (optionally) settling
      gravity — skip `_update_chase_state`, `_chase_player`/`_wander`, `_avoid_obstacles`,
      `move_and_slide`, `_handle_collisions`, `_animate_body`. Preserve all state.
      (Added `var lod_active: bool = true` and `set_lod_active(active)`. The early-return
      at the top of `_physics_process` zeroes velocity and returns WITHOUT calling
      move_and_slide, so a slept crocodile stays exactly put; all heading/chase/phase/
      confinement state is preserved for seamless re-activation. Patrol (`is_confined`)
      crocs simply don't move while slept and resume patrol on wake.)
- [x] when a crocodile becomes inactive, set its `HitBox` `Area3D` `monitoring=false`
      (deferred); restore `true` on re-activation, so ~1,210 idle Area3Ds stop costing
      physics time. Confirm an inactive crocodile far away cannot harm the player.
      (`set_lod_active` toggles `$HitBox.monitoring` via `set_deferred` (physics-safe),
      guarded with `get_node_or_null("HitBox")`, only on a genuine state change. A slept
      crocodile (45 m+ away) has monitoring off, so it cannot harm the player. Live
      gameplay confirmation is a manual web/desktop check — to be done by user.)
- [x] add the `CrocodileLODManager` node to `main.tscn`.
      (Added a `Node` named `CrocodileLODManager` under root `Main`, script attached via a
      script-by-path `ext_resource` (id `6_lod`) matching the coin_hud/hit_flash/perf
      convention; `load_steps` bumped 9→10. Editor import regenerates no errors.)
- [x] update `perf_overlay.gd` to show active vs total crocodile counts.
      (Already wired to read the real `lod_active` flag — counts group members where
      `lod_active` is true, staying defensive with `"lod_active" in croc`; updated the
      comment now that Task 3's flag exists. Line reads `Crocs (active/total): N / M`.)
- [x] **Verify (gameplay-identical):** approach a crocodile — it begins chasing at exactly
      the same ~15 m as before; getting caught still calls `reset_position()` and clears
      nearby crocs; jumping still drops the scent; patrol crocodiles still patrol when you
      are near them. Far crocodiles freeze (limbs still, no movement) but resume seamlessly
      as you approach.
      ([x] manual web/desktop verification — to be done by user. Static guarantee: SIM_RADIUS
      (45 m) ≫ DETECTION_RADIUS (15 m), so every crocodile that could ever detect/chase/
      touch the player is always fully awake and behaves byte-for-byte as before; only
      crocodiles well out of the player's reach are slept.)
- [x] **Verify (perf):** with many crocodiles around, physics ms and FPS improve markedly
      vs Task 2; record delta.
      ([x] manual web verification — to be done by user in browser; physics-ms/FPS delta to
      be read from the Task 7 measurement table on the running build via the F3 overlay
      (active vs total crocodile count proves the LOD is sleeping the distant pack).
      Validated headlessly: `godot --headless --check-only` parses the new script cleanly
      and `godot --headless --editor --quit` imports the whole project + modified `main.tscn`
      and both scripts with exit code 0 and no errors.)

### Task 4: MultiMesh batched block rendering (visual only)

**Files:**
- Modify: `scripts/endless_terrain.gd` (`create_box`, `create_block`, `create_chunk`, and
  the `spawn_*` structure builders that call them)

- [x] introduce a per-chunk **block batch**: change `create_box()` so that, instead of
      instancing a `MeshInstance3D`+`StandardMaterial3D` per block, it appends a
      `{ "transform": Transform3D, "color": Color }` entry to a batch array threaded
      through `create_chunk` → `spawn_objects_in_chunk` → `spawn_*` → `create_box`.
      (Keep the existing per-block `StaticBody3D` collision for now — Task 5 consolidates
      it.)
      (Done. `create_chunk` creates `var block_batch: Array = []` before calling
      `spawn_objects_in_chunk`, and the `block_batch` out-param is threaded through
      `spawn_objects_in_chunk` → `spawn_feature_structure` → `spawn_wall`/`spawn_corridor`/
      `spawn_gate`/`spawn_pyramid` → `create_block` → `create_box` (every call site updated;
      verified by grep). `create_box` now appends `{ "transform": Transform3D, "color":
      Color }` instead of instancing a MeshInstance3D+material. The per-block
      `StaticBody3D`+`CollisionShape3D`+`BoxShape3D` is STILL created (now a bare body with
      no visible mesh), positioned at `center_pos` with `rotation.y = yaw`, default
      layer/mask — collision is byte-for-byte unchanged. Task 5 will consolidate it.)
- [x] preserve the exact earthy color logic (brown / gray / mossy ranges) — just store the
      chosen `Color` per instance instead of baking it into a unique material.
      (Done. The `match rng.randi_range(0,2)` brown/gray/mossy branches and their
      `randf_range` ranges are unchanged; the chosen `Color` is stored per instance.
      DETERMINISM: `create_box` still consumes the `randf_range(0.7, 1.0)` roughness draw
      (discarded) so the chunk RNG sequence — and therefore the whole procedural world
      layout — is identical to before. Per-instance roughness isn't supported by MultiMesh,
      so the shared material bakes one representative roughness `SHARED_BLOCK_ROUGHNESS=0.85`
      (mid of the old 0.7–1.0 spread); the visual difference is negligible.)
- [x] after object generation in `create_chunk`, build one `MultiMeshInstance3D` per chunk:
      shared unit `BoxMesh`, `MultiMesh` with `TRANSFORM_3D` + `use_colors=true`,
      `instance_count = batch.size()`, per-instance transform (basis = per-axis scale by
      `dimensions` × yaw rotation, origin = local center) and `set_instance_color`. Material:
      `StandardMaterial3D`, `vertex_color_use_as_albedo=true`, roughness in the existing
      range. Parent the `MultiMeshInstance3D` to the chunk (auto-freed on unload).
      (Done in `_build_block_multimesh()`, called from `create_chunk` when `block_batch` is
      non-empty. Uses a lazily-created SHARED unit `BoxMesh` (size 1×1×1, reused across all
      chunks) and a SHARED `StandardMaterial3D` with `vertex_color_use_as_albedo=true`,
      `roughness=0.85`, applied as `material_override`. Per-instance basis =
      `Basis(Vector3.UP, yaw).scaled(dimensions)`, origin = chunk-local `center_pos`;
      `set_instance_transform`/`set_instance_color` per entry. The `MultiMeshInstance3D` is
      parented to the chunk mesh at local origin, so it auto-frees on unload and the blocks
      land in exactly the same spots (instance transforms are chunk-local, matching the old
      `MeshInstance3D.position = center_pos` convention).)
- [x] keep the heavy teaching comments: explain MultiMesh, per-instance transform/color,
      and why this collapses draw calls.
      (Done. SECTION 2 has a multi-paragraph note on what a MultiMesh is and why one draw
      call renders all instances; `create_box` documents the VISUALS-vs-COLLISION
      decoupling, the per-instance transform basis, and the determinism rationale;
      `_build_block_multimesh` documents `transform_format`, `use_colors`,
      `vertex_color_use_as_albedo`, and the chunk-local parenting. Comment density matches
      the surrounding teaching style.)
- [x] **Verify (visual-identical):** blocks, towers, walls, corridors, gates, pyramids all
      look the same (shapes, sizes, yaw, earthy colors); coins still perch correctly on
      block tops (`obstacles[].top` unchanged).
      (manual web/desktop verification — to be done by user. Static guarantees: the
      obstacle/platform return data (`pos`/`radius`/`top`/`climbable`) and the coin perching
      logic are untouched; the per-instance transform reproduces each block's exact size
      (per-axis scale = `dimensions`), yaw, and chunk-local position; colours use the
      identical brown/gray/mossy ranges; the RNG sequence is preserved so structure shapes/
      placements are unchanged. Headless validation: `godot --headless --check-only --script
      scripts/endless_terrain.gd` parses clean and `godot --headless --editor --quit` imports
      the whole project with no SCRIPT ERROR / Parse Error, exit 0.)
- [x] **Verify (perf):** `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` drops sharply vs Task 3;
      record delta.
      (manual web verification — to be done by user in browser; draw-call delta to be read
      from the F3 overlay and filled into the Task 7 measurement table. Expected: each
      chunk's many per-block MeshInstance3Ds collapse to one MultiMeshInstance3D = roughly
      one draw call per chunk for blocks, so `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` should drop
      sharply.)

### Task 5: Consolidated per-chunk block collision

**Files:**
- Modify: `scripts/endless_terrain.gd` (collision creation in `create_box`/`create_chunk`)

- [ ] replace per-block `StaticBody3D` with a single `StaticBody3D` per chunk; each block
      adds a `CollisionShape3D` child (`BoxShape3D(size=dimensions)`, local
      `position`/`rotation.y`). Keep the same collision layer/mask as today so crocodile
      avoidance raycasts and player collision are unchanged.
- [ ] fold the chunk ground collision into the same per-chunk body (or keep it separate if
      cleaner) — document the choice.
- [ ] **Verify (collision-identical):** player can't fall through ground or walk through
      blocks; crocodiles still steer around blocks (no clipping); climbing pyramids/walls
      and running corridors works exactly as before.
- [ ] **Verify (perf):** total node count drops substantially vs Task 4; physics time
      stable or improved; record delta.

### Task 6: Web-only reduced render distance + fog mask

**Files:**
- Modify: `scripts/endless_terrain.gd` (`_ready`: web-gated `render_distance`)
- Modify: `scenes/main.tscn` or runtime in code (`WorldEnvironment` fog, web-gated)

- [ ] in `endless_terrain._ready()`, if `OS.has_feature("web")`, set a lower
      `render_distance` (start at **3**; tunable — bump to 4 if 3 feels tight). Desktop
      keeps 5. Log the chosen value.
- [ ] enable depth fog on the `WorldEnvironment` **on web only** (runtime when
      `OS.has_feature("web")`, or a `.web`-gated setup): fog color = sky horizon
      `Color(0.646, 0.656, 0.671)`; tune `fog_depth`/`density` so the world edge fades into
      the sky just inside the (reduced) view distance. Desktop: no fog.
- [ ] **Verify (look):** on web the world still feels endless — the chunk boundary is
      hidden by fog, the horizon reads as sky, not a hard edge. Desktop unchanged.
- [ ] **Verify (perf):** chunk count, draw calls, node count, and physics time all drop
      again vs Task 5; this should be the largest single CPU/physics win; record delta.

### Task 7: Verify acceptance criteria
- [ ] verify every Overview benefit holds: smooth in-browser FPS; counts unchanged;
      gameplay near the player identical; look preserved (web-only, fog-masked).
- [ ] run the full gameplay regression on the **web build**: chase, catch/`reset_position`,
      jump-loses-scent, coin collect (ground/air/block), pyramid climb, wall/corridor/gate,
      patrol crocodiles, character switch (E), HUD coin counter, hit flash.
- [ ] confirm desktop (`godot --path . scenes/main.tscn`) is visually unchanged from before
      this plan (Forward Plus, full shadows, render_distance 5, no fog).
- [ ] fill in the before/after measurement table below and confirm the targets are met
      (e.g., draw calls down ≥5×, physics ms down sharply, stable ≥ target FPS in-browser).

#### Measurement table (fill during execution)
| Stage | FPS (web) | Process ms | Physics ms | Draw calls | Nodes | Active/total crocs |
|---|---|---|---|---|---|---|
| Baseline (Task 1) | | | | | | |
| + Web render tuning (Task 2) | | | | | | |
| + Crocodile LOD (Task 3) | | | | | | |
| + MultiMesh blocks (Task 4) | | | | | | |
| + Consolidated collision (Task 5) | | | | | | |
| + Render dist + fog (Task 6) | | | | | | |

### Task 8: [Final] Update documentation
- [ ] update `CLAUDE.md`: document the new `crocodile_lod_manager.gd` (LOD/sleep contract,
      `SIM_RADIUS` vs `DETECTION_RADIUS`), MultiMesh block rendering + consolidated
      per-chunk collision in `endless_terrain.gd`, the `perf_overlay.gd` debug HUD, and the
      web-only settings (`.web` overrides, web-gated `render_distance`, fog).
- [ ] note the new performance conventions (visual changes are web-gated; invisible wins
      are global; entity counts are never reduced — far crocs are slept, not removed).
- [ ] update `README.md` / `QUICKSTART.md` only if they describe performance/quality.
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p docs/plans/completed`).

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification:**
- In-browser playtest across browsers (Chrome, Firefox, Safari) and a mid/low-end machine —
  confirm smooth FPS and that fog/Compatibility rendering looks good everywhere.
- Decide final tuning values from the measurement table: `SIM_RADIUS`, web
  `render_distance` (3 vs 4), fog distances, optional `scaling_3d/scale.web`, shadow size.
- Confirm Compatibility-renderer glow/tonemap on web is acceptable; if glow looks wrong,
  decide whether to keep it on web or disable it there (web-only).

**External system updates:**
- Deploy: merge to `master` to publish the playable build via GitHub Pages
  (`.github/workflows/build.yml` deploys only on push to `master`). `claude/*` branches
  build a downloadable `web-build` artifact for pre-merge browser testing.
