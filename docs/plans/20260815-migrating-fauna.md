# Migrating fauna: elephant families and giraffe flocks (pure ambience)

## Overview

From time to time a family of migrating elephants or a flock of giraffes walks across the
landscape in the distance. They are **pure scenery**: they never react to the player, the
crocodiles, or any special ability, they have no collision bodies, and they belong to no
gameplay group. They enter at the edge of a ~180 m field around the player, walk a
straight-ish migration line with a gentle meander at a calm 2–3 m/s, and despawn once past
the far edge.

Everything lives in ONE new self-contained script, `scripts/fauna_manager.gd` (a `Node`
named `FaunaManager` under `Main` in `main.tscn`, in group `"fauna"`), sibling in spirit to
`crocodile_lod_manager.gd` and `sound_manager.gd`: a single throttled manager that owns its
own entities and drives all of their animation from one `_process`.

Key benefits:
- The world stops feeling empty between crocodile encounters — life crosses the horizon.
- Zero gameplay coupling: no new groups, no collision, no per-animal scripts, no asset files.
- Bounded cost: at most ONE herd (≤ 8 animals) alive at a time, shared meshes/materials,
  and literally zero work between events beyond one timer decrement.

**Bead:** `godot-test1-afc.10`.

## Context (from discovery)

Files/components involved:
- `scripts/fauna_manager.gd` — **new**, the entire feature.
- `scenes/main.tscn` — **minimal** edit only: one `[ext_resource]` line + one 2-line node
  block under `Main` (a parallel executor is adding its own node line to this same file, so
  the diff must stay a single small block to keep the merge trivial).

Related patterns found (study these, match their style):
- `scripts/crocodile_lod_manager.gd` — the "bare `Node` under `Main` that owns a throttled
  tick and finds the player through `get_tree().get_first_node_in_group("player")`" pattern.
  Copy its no-hard-references discipline.
- `scripts/piglet_crocodile_ai.gd` `_animate_body()` (~line 814) — the project's procedural
  animation idiom: a `stride_phase` advanced by `delta * STRIDE_FREQUENCY * move_factor`,
  sine-driven roll/bob/sway, per-instance `instance_phase` offset so the pack is not in
  lockstep, and the transform composed as `Basis` products layered on a cached rest scale.
  Fauna animation is the same idea applied to child limb pivots instead of a whole body.
- `scripts/toon_shading.gd` — `ToonShading.apply_to_mesh(mesh)`, whose **static material
  cache keyed by source-material instance id** is the precedent for "one shared material,
  never one per entity". Fauna materials follow the same rule but are simpler: the manager
  builds exactly one `StandardMaterial3D` per species in a `static var`, so N animals add
  2 materials total, ever.
- `scripts/endless_terrain.gd` `_get_shared_unit_box_mesh()` (~line 462) — the lazy shared
  mesh getter. Fauna uses the identical trick: ONE unit `BoxMesh`, scaled per part.
- `scripts/endless_terrain.gd` — the ground is flat at **y = 0** (a shared `PlaneMesh`
  per chunk at `position.y = 0`), so fauna needs **no raycasts and no terrain queries**:
  feet rest at y = 0 by construction.
- `scripts/ability_effect.gd` — precedent for "build a visual node fully in code, no scene
  file, and free it when done".

Dependencies identified: none new. No asset files, no Python pipeline, no autoloads.

## Development Approach

- **Testing approach**: NO unit tests. This project has **no test suite, linter, or build
  script** at all (see CLAUDE.md) — it is a pure Godot project. The only automatable checks
  are the headless engine runs in the verification task; that is the correct and complete
  test story here.
- Complete each task fully before moving to the next.
- Make small, focused changes; all feature code lands in the one new script.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility: not one line of existing gameplay script changes.

## Testing Strategy

- **Unit tests**: none. Do not add unit tests.
- **Integration tests**: none add a real guarantee here — there is no test harness, and the
  feature's whole surface is visual. The guarantee comes from the headless runs in Task 6
  (`godot --headless --path . --import` clean, then `--quit-after 3` with **zero** script
  errors/warnings in the output), which is exactly what CI can prove.
- **E2E tests**: the project has no e2e suite; do not stand one up.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Update plan if implementation deviates from original scope
- Keep plan in sync with actual work done

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): the new script, the minimal `main.tscn` node
  block, the headless verification runs, and the CLAUDE.md section.
- **Post-Completion** (no checkboxes): actually *watching* a herd cross in a running game
  and eyeballing the F3 draw-call delta — requires a human at a screen.

## Hard constraints (violating any of these fails the task)

1. **Do NOT touch** `scripts/endless_terrain.gd`, `scripts/player_controller.gd`,
   `scripts/piglet_crocodile_ai.gd`, `scripts/enemy_controller.gd`, or **any** HUD script
   (`coin_hud.gd`, `lives_hud.gd`, `ability_hud.gd`, `perf_overlay.gd`, `game_over_ui.gd`).
   Parallel executors own those files right now.
2. **Do NOT touch** `scripts/sound_manager.gd`. The bead's optional elephant trumpet is
   **deliberately skipped** — a parallel weather executor is likely adding sounds to that
   same file, and the bead explicitly allows skipping it ("skip honestly if fiddly").
   Record the skip in the final report and leave a `ponytail:` comment naming
   `sound_manager.play_*` as the upgrade path.
3. **Animals must NOT join the `"crocodile"`, `"enemy"`, or `"enemies"` groups** — the
   Phoboman stink wave iterates `"crocodile"` and the LOD manager iterates it too; a fauna
   node in there would be grabbed by both. The manager node itself is in group `"fauna"`;
   the animals are in **no group at all**.
4. **No collision bodies, no `Area3D`, no physics.** Animals are plain `Node3D` +
   `MeshInstance3D` trees. Walking through a block is accepted (`ponytail:` comment it).
5. **No per-animal scripts.** One `_process` on the manager animates every animal.
6. **ONE shared `BoxMesh` and ONE `StandardMaterial3D` per species**, both in `static var`s
   built lazily on first use. Never `duplicate()` a material per animal or per part. The
   two tusks/horn accents may share the species material or one extra shared accent
   material — but the total material count for the whole feature is a small constant,
   independent of how many animals ever spawn.
7. **`main.tscn` diff = one `[ext_resource]` line + one node block.** Nothing else.
8. Project conventions: **explicit type hints everywhere**, **all tunables as `const` at the
   top of the script**, and **teaching-density comments** (docstring on every function
   explaining *why*, matching `piglet_crocodile_ai.gd`).

## Implementation Steps

### Task 1: Manager skeleton — scheduling, shared resources, main.tscn wiring

- [x] create `scripts/fauna_manager.gd`: `extends Node`, with a file-level `##` doc comment
      explaining the whole system (pure ambience, no gameplay coupling, one herd at a time)
      in the teaching style used by `crocodile_lod_manager.gd`
- [x] declare the full **constants block at the top**, grouped with `# ----- ... -----`
      section comments and each documented: `FIELD_RADIUS := 180.0`,
      `DESPAWN_RADIUS := 230.0` (comfortably past the field edge so a herd is never culled
      mid-view), `FIRST_EVENT_DELAY_MIN := 40.0` / `FIRST_EVENT_DELAY_MAX := 80.0` (the very
      first herd comes sooner than the steady-state gap so a short play session still sees
      one — the acceptance criterion is "within a few minutes"),
      `FAUNA_INTERVAL_MIN := 120.0` / `FAUNA_INTERVAL_MAX := 240.0`,
      `WALK_SPEED_MIN := 2.0` / `WALK_SPEED_MAX := 3.0`, `ELEPHANT_CHANCE := 0.5`
- [x] add manager state: `var _event_timer: float`, `var _animals: Array[Dictionary]`
      (animal records — chosen over `Array[Node3D]`, matches Task 5's record shape),
      `var _rng := RandomNumberGenerator.new()` (`randomize()`d in `_ready`, like the
      crocodile's per-instance rng — fauna is deliberately **non-deterministic ambience**,
      it must NOT touch the terrain's `run_seed` determinism contract)
- [x] `_ready()`: `add_to_group("fauna")`, seed the rng, set `_event_timer` to a random
      first-event delay
- [x] add the lazy shared-resource getters as `static var` + getter functions, mirroring
      `endless_terrain._get_shared_unit_box_mesh()`: `_get_shared_box_mesh() -> BoxMesh`
      (one 1×1×1 cube, scaled per part), `_get_elephant_material() -> StandardMaterial3D`
      (grey), `_get_giraffe_material() -> StandardMaterial3D` (tan-orange), and one shared
      accent material (off-white tusks / darker-brown giraffe patches). Each documents *why*
      it is shared (batching + memory: N animals must never add N materials)
- [x] `_process(delta)`: if a herd is alive, drive it (stub for now — filled in Tasks 4/5);
      otherwise decrement `_event_timer` and call `_spawn_herd()` when it reaches 0, then
      re-arm it with `_rng.randf_range(FAUNA_INTERVAL_MIN, FAUNA_INTERVAL_MAX)`. Comment
      that between events the entire per-frame cost is this one subtraction
- [x] add a `_find_player() -> Node3D` helper using
      `get_tree().get_first_node_in_group("player")`, **null-safe** — if there is no player
      (a scene run standalone) the manager simply does nothing, same defensive style as the
      sound-manager group lookups
- [x] edit `scenes/main.tscn`: add exactly one
      `[ext_resource type="Script" path="res://scripts/fauna_manager.gd" id="15_fauna"]`
      line after the `14_sound` line, bump `load_steps`, and add the 2-line node block
      `[node name="FaunaManager" type="Node" parent="."]` / `script = ExtResource("15_fauna")`
      immediately after the `SoundManager` node block. **No other change to the file.**

### Task 2: Elephant model builder (code-built boxes, no assets)

- [ ] add elephant geometry constants at the top: body size, leg size, head size, ear size,
      trunk segment size/count (2–3), tusk size, and `CALF_SCALE := 0.55`
- [ ] add `_build_elephant(is_adult: bool) -> Node3D` that assembles the animal entirely from
      the shared unit `BoxMesh` + the shared elephant material, with a docstring explaining
      the blocky-by-design aesthetic (matches the game's decorative blocks and low-poly cast)
- [ ] structure the node tree so the animation in Task 5 has clean pivots:
      root `Node3D` (the animal, positioned at ground level) → a `Body` `Node3D` carrying the
      body/head/ear boxes → **four leg pivot `Node3D`s at hip height**, each with a
      `MeshInstance3D` child offset **down by half the leg length** so rotating the pivot
      about X swings the leg from the hip, not around its own centre → a **trunk chain** of
      2–3 nested pivot `Node3D`s hanging off the head, each with its box child offset down
      by half a segment so the chain sways from its root
- [ ] give adults the two white tusk boxes; calves get none, and the whole calf root is
      scaled by `CALF_SCALE` (one `scale` write on the root — do not rebuild smaller boxes)
- [ ] set `cast_shadow`: **ON** (default) for the adult body/legs/head — near-ground shadows
      sell their size; **`SHADOW_CASTING_SETTING_OFF`** for ears, trunk segments, tusks and
      every part of a calf, with a comment naming the reason (small accents contribute
      nothing to the silhouette but cost shadow-pass draws)

### Task 3: Giraffe model builder

- [ ] add giraffe geometry constants: body, long thin legs, neck length/angle, head, horn
      nubs, and the count of darker-brown accent patch boxes (a **few** — 2–3 — explicitly
      NOT a checker pattern; comment that a real pattern would need a texture and is not
      worth an asset file)
- [ ] add `_build_giraffe() -> Node3D` with the same node structure contract as the
      elephant: root → `Body` → four hip-pivoted leg `Node3D`s → a **`Neck` pivot** at the
      shoulders holding the angled neck box, with the small head + horn nubs parented to the
      neck's far end so they swing with it
- [ ] `cast_shadow` OFF on horn nubs and the accent patch boxes; ON for body/legs/neck
- [ ] keep both builders returning the same shape of animal record so Task 5's animation
      loop is species-agnostic: legs are always four pivots in a known order
      (front-left, front-right, rear-left, rear-right), and species-specific extras (`neck`,
      `trunk` segments) are simply empty/null for the other species

### Task 4: Herd spawning, migration line, and despawn

- [ ] add herd constants: `ELEPHANT_HERD_MIN := 3` / `ELEPHANT_HERD_MAX := 5`,
      `ELEPHANT_ADULTS_MIN := 1` / `ELEPHANT_ADULTS_MAX := 2`,
      `GIRAFFE_FLOCK_MIN := 4` / `GIRAFFE_FLOCK_MAX := 8`, `HERD_SPREAD_LATERAL`,
      `HERD_SPREAD_LONG`, `CALF_TRAIL_DISTANCE`, `MEANDER_AMPLITUDE`, `MEANDER_FREQUENCY`,
      `FORMATION_LERP_SPEED`
- [ ] `_spawn_herd()`: pick the species by `ELEPHANT_CHANCE`, pick a random compass heading,
      place the **herd origin** on the field circle at `player_pos - heading * FIELD_RADIUS`
      (so it walks *toward and past* the player's area), roll one shared
      `_herd_speed` in `[WALK_SPEED_MIN, WALK_SPEED_MAX]`, build the members, and parent them
      to the manager's own parent (or to the manager) — **not** to a terrain chunk, since
      chunk unloading must never free a herd mid-walk
- [ ] give each member a per-animal record holding its lateral/longitudinal **formation
      offset**, its `phase` (a random stride phase offset so the herd is not in lockstep —
      same idea as the crocodile's `instance_phase`), and its limb pivot references
- [ ] elephants: 1–2 adults lead, the rest are calves placed **behind** an adult
      (`CALF_TRAIL_DISTANCE` back plus a small lateral jitter); giraffes: a loose **diagonal**
      spread (offsets stepped along both the heading and the lateral axis)
- [ ] `_update_herd(delta)`: advance a single shared `_herd_position` along the heading at
      `_herd_speed`, add a gentle shared meander
      (`sin(_herd_travelled * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE` on the lateral axis),
      then for each animal lerp its position toward `herd_position + its offset` at
      `FORMATION_LERP_SPEED` and face it along its own travel direction. Feet stay at
      **y = 0** (flat ground — no raycast, comment why)
- [ ] despawn: when the herd centre is farther than `DESPAWN_RADIUS` from the player (or the
      player is gone), `queue_free()` every animal, clear `_animals`, and re-arm the event
      timer. Also handle "the player ran away from the herd" — the same distance check covers
      it, since it measures against the live player position each tick
- [ ] add the two required `ponytail:` comments: (a) **walk-through is the accepted ceiling**
      — no collision bodies and no obstacle avoidance, so a herd may clip a decorative block;
      capsule bodies + a cheap raycast nudge are the upgrade path if it ever reads badly;
      (b) **the elephant trumpet sound is skipped** — `sound_manager.gd` is owned by a
      parallel executor this cycle; a `play_*`-style one-shot is the upgrade path
- [ ] enforce the **one-herd invariant** explicitly: `_spawn_herd()` early-returns if
      `_animals` is non-empty, with a comment that this is the whole perf story

### Task 5: Procedural walk animation (single loop over all animals)

- [ ] add animation constants: `STRIDE_FREQUENCY`, `LEG_SWING_DEG`, `BODY_BOB_AMOUNT`,
      `NECK_BOB_DEG`, `NECK_BOB_FREQUENCY`, `TRUNK_SWAY_DEG`, `TRUNK_SWAY_FREQUENCY`
- [ ] in `_process`, after the herd movement, run ONE loop over `_animals` that advances a
      shared `_animation_time` and per-animal `stride_phase += delta * STRIDE_FREQUENCY`
      (scaled by the herd walk speed so faster herds step faster — same `move_factor` idea as
      `_animate_body`)
- [ ] legs: `pivot.rotation.x = sin(stride_phase + leg_phase_offset) * LEG_SWING_DEG` in
      radians, with the diagonal pairs a half-cycle apart (front-left/rear-right in phase,
      the other diagonal offset by `PI`) — a real quadruped trot, and comment it as such
- [ ] body: a small vertical bob at **twice** the stride rate (`sin(stride_phase * 2.0)`),
      exactly the crocodile's bob relationship, applied to the `Body` node's local y
- [ ] giraffe neck: a gentle bob — `neck.rotation.x` oscillating a couple of degrees at
      `NECK_BOB_FREQUENCY`, layered on the neck's **rest angle** (cache the rest rotation at
      build time so the animation composes on top instead of overwriting it — same
      `model_base_scale` / `model_base_y` discipline as the crocodile)
- [ ] elephant trunk: each chained segment sways on `rotation.z` (or x) with a small
      **per-segment phase lag**, so the trunk reads as a floppy chain rather than a rigid bar
- [ ] verify by reading the code that the loop does **zero allocations per frame** (no
      `Array`/`Dictionary`/`Basis` construction in the inner loop beyond cheap value types,
      no `get_node()` calls — all pivots are cached references from build time)

### Task 6: Verify acceptance criteria

- [ ] verify every requirement in the Overview and Hard constraints is implemented, in
      particular: no collision node of any kind exists in the animal trees, the animals join
      **no** group, no per-animal script is attached, and exactly one material per species is
      ever created (grep the script for `duplicate()` and for `.new()` on material types —
      the material `.new()`s must be inside the `static var` lazy getters only)
- [ ] verify `git diff scenes/main.tscn` is **only** the `load_steps` bump, the one
      `[ext_resource]` line, and the one 2-line node block
- [ ] verify `git status` shows **no** modification to `endless_terrain.gd`,
      `player_controller.gd`, `piglet_crocodile_ai.gd`, `sound_manager.gd`, or any HUD script
- [ ] run `godot --headless --path . --import` — must complete with no errors
- [ ] run `godot --headless --path . scenes/main.tscn --quit-after 3` — must run clean with
      **no** script errors, no "Invalid access", and no missing-node warnings from the new
      script (the fauna timer will not fire in 3 s; that is expected — the check is that the
      manager loads and idles cleanly)
- [ ] ➕ to actually exercise the spawn path in a headless run, temporarily set the first-event
      delay to ~1 s (or add a short-lived debug call), confirm a herd spawns and animates
      without errors, then **restore the real constants** and re-run the clean check
- [ ] the project has no test suite and no linter (see CLAUDE.md) — the headless runs above
      are the complete automatable check

### Task 7: [Final] Update documentation

- [ ] add a short **"Ambient fauna (migrating herds)"** subsection to `CLAUDE.md` under
      Architecture, in the established voice: what the manager is, the one-herd-at-a-time
      invariant, the shared-mesh/one-material-per-species rule, the "**no groups, no
      collision, no reaction to anything**" contract and *why* (stink wave + LOD manager
      iterate `"crocodile"`), the flat-ground y = 0 assumption, and the fact that fauna is
      deliberately non-deterministic ambience outside the terrain `run_seed` contract
- [ ] do **not** touch README.md / QUICKSTART.md (they are already stale on engine version;
      out of scope)

## Technical Details

**Node tree of one animal (elephant shown; giraffe is the same contract with `Neck` in place
of the trunk):**

```
Elephant (Node3D)            <- the animal root; position.y = 0, faces travel direction
└── Body (Node3D)            <- bobs vertically; carries the static boxes
    ├── BodyBox (MeshInstance3D)      shared BoxMesh, scaled to body size
    ├── Head   (MeshInstance3D)
    ├── EarL / EarR (MeshInstance3D)  cast_shadow OFF
    ├── TuskL / TuskR (MeshInstance3D) adults only, cast_shadow OFF
    ├── Trunk0 (Node3D pivot)          -> Trunk1 (Node3D pivot) -> Trunk2 ...
    │     └── TrunkBox (MeshInstance3D, offset down by half a segment)
    ├── LegFL (Node3D pivot at hip)   -> LegBox (MeshInstance3D, offset down by half leg)
    ├── LegFR (Node3D pivot)          -> LegBox
    ├── LegRL (Node3D pivot)          -> LegBox
    └── LegRR (Node3D pivot)          -> LegBox
```

**Per-animal record** (kept in `_animals`, one entry per animal — the animation loop reads
only cached references, never `get_node`):
`root: Node3D`, `body: Node3D`, `legs: Array[Node3D]` (always 4, FL/FR/RL/RR),
`neck: Node3D` (null for elephants), `trunk: Array[Node3D]` (empty for giraffes),
`offset: Vector3` (formation offset in herd-local space), `phase: float`,
`neck_rest: float` / `body_rest_y: float` (rest poses the animation composes on top of).

**Processing flow per frame:**
1. No herd alive → `_event_timer -= delta`; spawn when it hits 0. (Entire cost: one float
   subtraction and one compare.)
2. Herd alive → advance `_herd_position` along the heading, apply the shared meander, lerp
   each animal toward `herd_position + offset`, yaw each toward its own motion.
3. Animate: one loop advancing stride phases and writing limb-pivot rotations + body bob.
4. Distance check against the live player → despawn + re-arm the timer.

**Cost ceiling:** ≤ 8 animals × ~12 boxes ≈ 96 `MeshInstance3D`s at the absolute worst, all
sharing one `BoxMesh` and 2–3 materials, alive only during an event. Zero fauna cost at all
other times.

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification:**
- Play for a few minutes and watch a herd cross the landscape: elephants must read as a
  family (big adults + smaller trailing calves, trunks swaying), giraffes as a tall
  long-necked flock in a loose diagonal.
- Confirm they walk straight past the player, the crocodiles, and a Phoboman stink wave
  without any of them reacting.
- Toggle the F3 perf overlay during a migration: draw calls should rise only marginally, and
  the node count should return to its previous value after the herd despawns.
- Check the web export (`godot --headless --export-release "Web" build/web/index.html`) and
  confirm the herd still reads well through the thicker web fog at distance.

**Deferred by design (documented as `ponytail:` comments in the code):**
- Elephant trumpet one-shot — skipped this cycle because `scripts/sound_manager.gd` is owned
  by a parallel executor; upgrade path is one `play_elephant_trumpet()` in the manager's
  synth style plus a null-safe group lookup at spawn time.
- Obstacle avoidance — herds may clip a decorative block; capsule bodies or a cheap forward
  raycast nudge are the upgrade path if it ever reads badly.
