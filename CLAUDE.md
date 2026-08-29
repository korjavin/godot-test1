# CLAUDE.md

Guidance for Claude Code when working in this repository.

**This file is a map, not the territory.** It records where things live and the rules
you would break without knowing. The reasoning, the measured numbers and the tuning
history live in the code — scripts are heavily commented on purpose, so read the file
you are changing. Do not grow this file with details that belong next to the code.

## Project

A Godot 3rd-person endless-runner adventure game ("CrimeKickers"). The player walks an
infinite procedurally generated field, switches between four characters, and is chased
by hostile NPC crocodiles. 2–4 players can share a world over WebRTC.

**Engine: Godot 4.5.** README.md and QUICKSTART.md say 4.3 — they are stale.

## Commands

The game has **no test suite, linter, or build script** — it is a pure Godot project
driven from the editor and CI. Correctness is guarded by **headless self-checks**: each
prints `SELFCHECK OK` and exits 0. Run the ones covering what you touched; read the
script's own header for what it asserts.

```bash
godot --path . scenes/main.tscn                    # run the game
godot --path . scenes/characters/primm.tscn        # run one scene in isolation
mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html
./serve.sh                                          # serve a web build (WASM needs http://)

# Self-checks — godot --headless --path . --script res://scripts/<name>.gd
#   fauna_selfcheck          herd steering + rider carry
#   mp_selfcheck             multiplayer pure logic (decoders, ids, arithmetic)
#   locale_selfcheck         en/de table + German fits its controls
#   view_selfcheck           the three camera views C cycles
#   progression_selfcheck    level curve, skill trees, effects on a live player
#   wade_selfcheck           river wading (player, croc, boss)
#   minimap_selfcheck        the map actually read the world
#   help_selfcheck           keymap card vs the real input map
#   hero_hud_selfcheck       the portrait row: one colour row and one loadable
#                            portrait per CHARACTERS hero at the single asset
#                            path, the four tile states (captive OUTRANKS
#                            active), the no-player degrade, and the row's
#                            fit in main.tscn against the hearts and F3
#   landmark_selfcheck       every builder fits its declared radius
#   prop_selfcheck           prop/structure footprints, budgets, palettes
#   enemy_spawn_selfcheck    every species: no spawn in stone, deterministic
#                            placement, biome dispatch, behaviour, MP identity
#   boss_selfcheck           EVERY BIOME_BOSS kind: the territory leash (hunts
#                            inside, never leaves), crush immunity is an
#                            ORDERING, the row's boss speed is the one resolved,
#                            and a ranged boss really fires — only in its band,
#                            on its cooldown, inside its area, while chasing.
#                            Plus check 8: EVERY SPECIES row through the
#                            stink_immune / crush_immune guards, animals as the
#                            negative control
#   projectile_selfcheck     boss projectiles: the per-style FAIRNESS contract
#                            (a walking player always clears it; nothing outruns
#                            a fleeing one), straight + lob flight, both dodge
#                            sims with their stationary controls, the per-shooter
#                            cap and its chunk-unload release
#   hunt_director_selfcheck  the hunter encounter director: the pursuer cap, the
#                            post-grab / hard-chase lull and the escape-sector
#                            guarantee (driven on the shipped pure functions,
#                            against an independent oracle), per-quarry
#                            bucketing, and the absent-director degrade measured
#                            through the arm's real seam
#   perf_selfcheck           frame-spike telemetry (thresholds, correlation, reset)
#   chunk_stream_selfcheck   ground-first chunk streaming (floor, debt, determinism)
#   intro_selfcheck          intro film: web gate, desktop PLAY SOLO path, JS shape
#   build_version_selfcheck  auto-reload onto a new build: the CI bake contract,
#                            the web gate, and never mid-run / never in a room
#   pause_selfcheck          the pause refcount: overlapping holders, the
#                            P / ? / P repro, and nothing writing tree.paused
#   tower_site_selfcheck     the tower's site: deterministic, dry, and clear of
#                            every spawner (plus the A/B that the rest of the world
#                            is byte-identical with the exclusion on and off)
#   tower_shell_selfcheck    the tower's building: box budget, fit inside
#                            TOWER_RADIUS, shared materials, the doorway is a hole,
#                            the door fires for a player only, lazy manager-parented
#                            instancing, the fog-exempt impostor, the minimap mark
#   tower_interior_selfcheck the tower's interior: the plan fits the shell, NO
#                            jump-gated climb (apex read from player_controller),
#                            the ramp deck is flush at both ends, the hall clears
#                            a live camera rig, the batch/draw budget, the gate
#                            lifecycle under real physics, opened state re-applied,
#                            per-floor visibility, and — phase 8 — the CELL BLOCK:
#                            the spine line SAMPLED for holes (a gap there makes
#                            every identity gate in the wing decorative), the
#                            acceptance walk for a spine door plus liberation, and
#                            the custody scene DRIVEN (containment re-shuts earned
#                            doors and stays shut, the right hero's pad releases it,
#                            the scar's rubble is drawn AND solid AND permanent).
#                            Every geometry check LOOPS OVER STOREYS off FLOOR_Y
#                            and TowerPlans.floors(), so a new plan row is
#                            covered the day it lands: per-storey box budget,
#                            headroom, and the ramp flush at both ends
#   capture_selfcheck        SYSTEMIC CAPTURE and the tower guard's setback: the
#                            arming gate (pre/post the
#                            authored beat), attribution (only a "hunt" row takes
#                            a hero), invulnerability covering the hero too, the
#                            clean auto-switch, liberation, the empty-roster game
#                            over with hearts in hand, that the set never touches
#                            the monotone store, the cell-block mirror in both
#                            directions, and THE FULL-CUSTODY PROTOCOL: the scene
#                            opens instead of a screen and is playable, surviving
#                            it takes exactly one AUTHORED scar, losing it archives
#                            the world (Continue reopens the ending, New Game
#                            clears it), and the roster override does not leak
#   tower_selfcheck          THE SOFTLOCK AUDIT: TOWER_GRAPH bound to the boxes
#                            the interior really builds, the three design laws
#                            (spines at floor rank, no item custody, mutations
#                            edge-additive + the sanctioned scar), all 15
#                            free-hero subsets reaching a cell from every entry,
#                            in every story-flag and scar state, that every
#                            authored scar is one the BUILDING can inflict, and
#                            — phase 14 — the two things the graph walk CANNOT
#                            see: the per-storey GRID FLOOD-FILL (a doorway
#                            typed as a wall passes every subset walk) and the
#                            plan-room / gate-slot binding to TOWER_GRAPH rows,
#                            both ways, each with a negative control

bash scripts/mp_e2e.sh    # two-instance multiplayer e2e; needs go + godot on PATH
```

**After editing `assets/translations/ui.csv`, re-run `godot --headless --path . --import`
before `locale_selfcheck`** — otherwise it reports the stale imported table.

The lobby in `server/` is a separate Go service with its own `go test` suite.

3D character models are **generated by Python** (`python3 scripts/generate_*.py`, needs
the PINNED `trimesh` + `numpy` of `scripts/requirements.txt` — CI compares the rebuilt
`.glb` bytes against the committed ones, so an unpinned install is a red build, not a
convenience), output to `assets/models/characters/`. The live Windman is the
separate parts in `windman_parts/`, assembled by `scenes/characters/windman_updated.tscn`
— not the monolithic `windman.glb`.

The biome-predator models — five animals, the GD-SURVEY hunter robot and the naga,
hydra, green dragon and roc bosses — share one
toolkit, `scripts/predator_parts.py`, which carries the orientation / feet-at-y=0 /
one-vertex-coloured-mesh contract an enemy model must honour and asserts it on every
build. Running it directly rebuilds and checks all ten:
`python3 scripts/predator_parts.py` -> `SELFCHECK OK`. Two of its primitives are
composed INTO models rather than being models — `wings()` (the winged bosses' folded
silhouette; they hop, nothing in this game flies) and `necks()` (a fan of necks and
heads off ONE point on the spine, the multi-head capability the hydra spends) — so each
carries a `_selfcheck_*` stand-in beside the model loop; `verify()` only ever sees the
finished welded animal, in which neither is a separable thing any more.

**Every check above runs on the REBUILD, so none of them can see a stale committed
`.glb`.** That is a separate CI step (`model-selfcheck`'s second one): rebuild, then fail
if the tree is dirty. **A generator change and its regenerated `.glb` belong in the same
commit** — a hand-committed artifact the code never produced is what this catches.

Each `.gd` has a sibling `.gd.uid` managed by Godot; don't hand-edit them.

## Architecture

### Node discovery is group-based, not reference-based
Systems never hold hard references to each other. Use
`get_tree().get_first_node_in_group(...)`, not `$`-paths or exported references, and
guard with `has_method` so a scene run standalone degrades instead of erroring. Groups:
`player`, `crocodile`, `enemy`, `coin`, `landmark`, `terrain`, `weather`, `fauna`,
`sound_manager`, `progression`, `mp`, `lod_manager`, plus one per HUD widget.

**`"player"` means the LOCAL player and nothing else.** Terrain streaming, crocodile
chase, the LOD manager, the danger vignette, fauna and weather all resolve "the player"
through that group — a remote multiplayer peer joins no group precisely so they cannot
silently follow a hologram.

### Everything in the world is spawned procedurally from the terrain
`scripts/endless_terrain.gd` is the world engine: a dictionary of chunks keyed by
`Vector2i`, rebuilt when the player crosses a chunk boundary. Generation is time-sliced
— the safety ring around the player gets its GROUND synchronously (the floor is the
whole fall-through guarantee and ~3% of a chunk's cost), and every chunk's contents,
ring included, are built one chunk per frame.

Load-bearing rules:

- **Determinism.** Every spawn site is a pure function of (chunk coords or station index)
  plus `run_seed`, hashed as `hash(Vector3i(a, b, run_seed))`. Within a run a revisited
  chunk regenerates byte-identically; across runs the world differs. A new spawn site
  mixes `run_seed` the same way. Independent features take their **own hash stream** with
  their own salt and their own coordinate primes, so they consume no draw from the shared
  chunk RNG and cannot correlate with it.
- **Post-draw skips.** Where a feature *removes* a placement, `continue` **after** the RNG
  draws that produced the candidate — the draws must still advance the stream.
- **One MultiMesh + one collision body per chunk.** All decorative geometry goes through
  `create_box()`, which appends to the chunk's `block_batch` and (unless `collide=false`)
  adds a `CollisionShape3D` to the chunk's single `BlockCollision` `StaticBody3D`. Never
  instance a MeshInstance3D or a physics body per object.
- **Chunk-parented, so unloading frees it.** Anything spawned per-chunk parents to the
  chunk MeshInstance3D or it leaks.
- **Footprints are the shared currency.** Each thing built appends
  `{pos, radius, top, climbable}` to `obstacles`; later spawners (crocodiles, coins) read
  it. `_settle_coin_y` perches a coin on a **climbable** top and **skips** it over a
  non-climbable one. Settle reward coins *before* appending the feature's own footprint.
- **Placement is split in two.** A rarity roll on its own hash stream, then a candidate
  loop in the spawner where `obstacles` exists, judged by `_biome_spot_ok(...)` — the
  single home of the river / road-clearance / overlap rule. The loop must not live in the
  rarity function: there is no geometry to test against there.
- **Ground is one shared `PlaneMesh` at y = 0**, shaded by `assets/shaders/ground.gdshader`.

Features built this way: the coin road (a parametric station-indexed path whose X strictly
increases, so distance = `global_position.x`), boss crocodiles on road stations, lost-
civilization artifacts, nomad camps, geo landmarks, biome content, themed props.

**The tower (GastroDefense HQ) is the one exception and must stay one.** It is ONE
authored building at ONE site — `tower_site()`, a CONSTANT at `(-400, 0, 0)` (owner
ruling: the HQ is hand-planned once and forever, so no seed and no RNG draw moves
it) — that every spawner keeps clear of via `tower_excludes()`. The rivers that
used to nudge it are **masked under it instead**: `is_river_at()` answers false
inside `TOWER_RADIUS` and `ground.gdshader` paints no band over the same disc —
one more clause of the CPU/GPU parity contract, edited in both languages together. Its geometry is
`scripts/tower_shell.gd`'s box table, **not** `create_box()`/`block_batch`, and both it
and its fog-exempt horizon impostor are parented to the terrain **manager** (the fauna
precedent) so chunk unloading can never free the building you are standing in. The
shell is instanced lazily on a chunk-boundary crossing and **shares `TOWER_RADIUS`**
rather than restating any distance of its own. `tower_shell_selfcheck` pins all of it.

`scripts/tower_interior.gd` is the same idea one floor in: a second box table for the
two-storey keep, plus eight hand-planned storeys over it (see below) rising to the CELL
BLOCK under the sealed roof, assembled onto the
shell by
`endless_terrain` (one direction only — the interior reads the shell's constants, so a
shell that knew about the interior would be a cyclic `class_name`). Four rules of its
own, all pinned by `tower_interior_selfcheck`:

- **No interior traversal may demand a jump-height.** The base apex (3.6125 m) is what
  mountain impassability rests on, so a storey you can jump onto is a bug the day
  somebody retunes the jump. Vertical movement is ramps and gates — never steps, which
  `CharacterBody3D` cannot climb at all.
- **Opened gates are a monotone SET on the shell node** (`mark_opened` / `is_opened` /
  `opened_ids`), not per-player state, because the transformation is world state every
  peer would see. `_apply_opened()` is the one place state becomes geometry, and the
  seam phase 5 will load a save through.
- **Static interior geometry is ONE batched mesh per storey and casts no shadow.** Both
  were measured, both are invisible, and together they are the difference between the
  interior costing 4 ms a frame and costing nothing measurable.
- **The cell block is the tower's destination, and since phase 16 it is on STOREY 10** —
  drawn on the plan grid like every other storey, not on a box table of its own, with
  only its hand-built parts (the press, the frames, the scar's rubble) placed from
  `plan_room_rect()`. A service corridor with two ways in (an ungated door off the muster
  floor, a press-guarded crawl), FOUR identity
  doors in one wall — one rescue spine per hero, the hero read from `TowerGraph` and never
  restated — and four UNIFORM cells off a gallery. Liberation is walking into an occupied
  cell and asks nobody's name; the captive set lives on the interior and is per-run, while
  the single authored first rescue joins the persisted opened set (so the staging in
  Primm's cell is gone for good and nothing else is). `set_captive()` is the seam
  systemic capture drives. **A room under a slab has nowhere for a mass to rise**, so
  these four sink — the one axis of the gate language the geometry took away. **Its graph
  room ids and every gate and scar id are phase 8's, spelled exactly as phase 8 spelled
  them** — moving geometry is not a save migration, renaming an id is.
- **THREE KINDS OF TOWER STATE, THREE HOMES — and the guards' home is nowhere.** Opened
  gates are a monotone union set on the shell; the captive set is per-run and
  deliberately outside it (non-monotone); the GUARDS are never persisted by anybody, and
  that absence plus `reset_guards()` on the shell's `player_entered` signal IS the
  owner's "structure persists; population resets". Guards are parented to the building
  (a storey is flat within itself, so the gravity settle a `SPECIES` row expects holds),
  never chunk-spawned. **Losing to one is the THIRD STAKE**: `coin_setback` (7%) off this
  peer's own coins plus a knockback to `setback_point()` — the last checkpoint in the
  opened set, or the doorway — and **no life and no game over**, so the building can
  never end a run mid-rescue. It rides the one damage verb: `hit_by_crocodile(attacker)`
  reads the row key, exactly as `_is_hunter_grab` reads `behavior`. Guards stay in group
  `"crocodile"` (LOD sleep and the MP relay still want them) and refuse the Stink Wave
  and the giant's crush through `stink_immune` / `crush_immune`, never through group
  tricks; `clear_nearby_crocodiles()` exempts them the way it exempts a boss, or any
  death inside the building would clear the floor.
- **THE FULL-CUSTODY PROTOCOL is what an empty roster opens instead of a screen.**
  When the corporation holds every hero, `player_controller` marches the party to
  the cell block's service corridor, RAISES CONTAINMENT (`begin_lockdown()`
  re-shuts every spine door a hundred earlier rescues opened) and runs a recall
  clock. One liberation is success; the clock, or the last heart, is failure. The
  scene's verbs are the game's — switch, move, stand on a pad — and its
  scene-scoped roster grant lives at `available_character_indices()` and nowhere
  else, so it composes with the lobby's hand and `free_hero_count()` stays honest
  (0 until somebody is actually freed, which is how the outcome is decided).
  **The exit set is `entry INTERSECT still-held`** — the scene marks all four
  captive, so anything less leaks a teammate's hero into this peer's filter.
- **A FOURTH HOME, and it is a fourth for one reason.** The SCAR rides the monotone
  opened set like a gate (earned, permanent, no verb heals it — it is only design
  law 3's exception in what the *building* does with the id, never in how it is
  stored). The WORLD ARCHIVE cannot: New Game has to clear it and a union has no
  removal verb, so it is its own `[world] archived` latch in `best_run_store.gd`,
  read at boot (Continue reopens the ending) and cleared by `restart_game()`. The
  scene's own clock, grant and entry set are stored **nowhere**, like the guards.
  Every scar is authored in `TowerGraph.scars` and picked by `next_scar()`; nothing
  computes a scar id, and `tower_selfcheck` fails a scar row no box implements.

#### Hand-planned storeys — the ASCII plans are the level editor
`scripts/tower_plans.gd` is a third const dict of plain dicts, and it is what a
DESIGNER edits: one character per cell, `rows[r][c]` reading north to south the way you
read a floor plan. **Nothing about a storey is generated, seeded or hashed** — the
owner's "plan it once and forever" applies to the inside of the building as much as to
its site, and a tower that moved between runs would mean the softlock audit certified a
layout no player ever sees. Grep the file for `run_seed` / `randf` / `hash(` and there is
nothing to find; keep it that way. **The plan text IS the design record** — each storey's
comment block and `note` carry what the floor is and, for the labyrinth, the solution
path written out cell by cell. A future author edits the text, because there is no seed
to reroll.

The building is full to its sealed roof — ten floor indices, `FLOOR_Y[0..9]`:

| floor | storey | what it is |
|---|---|---|
| 0–1 | keep | entry hall + courtyard + the 80 m annulus; the mezzanine landing |
| 2–4 | 3–5 | the phase-14 office storeys (vault, secure door, executive) |
| 5–6 | 6–7 | operations and security |
| 7–8 | 8–9 | **the labyrinth** |
| 9 | 10 | **the cell block**, under the sealed roof |

- **The grid is 40 x 40 and `PLAN_CELL` is DERIVED** — `2 * PLAN_HALF / PLAN_GRID`, 1.94 m
  — because 40 cells have to span exactly the shell's clear inner width. Round it to a
  nice 2.0 and the plan's outer ring stops meeting the wall it is drawn against and every
  storey grows a 0.8 m ledge nobody planned, on all four sides, forever. A corridor is two
  cells (3.88 m); a small office is 4 x 5.
- **THE EXTENSION RULE, which is what this phase is measured on: a new storey is one
  `STOREYS` row plus its `TOWER_GRAPH` rows, and NO BUILDER LOGIC.** `tower_interior.gd`
  walks whatever is in `STOREYS` — it knows about storeys, not about storey 3. The day
  adding a floor needs a line of *code* in the builder, the format has failed and the
  format is what should change. Measured on a throwaway sixth storey: those two rows plus
  exactly two declared numbers moving — one more `FLOOR_Y` element and `DRAW_BUDGET`
  26 → 27, one more storey mesh — and the self-check named the budget rather than leaving
  it to be noticed.
- **TWO audits, because neither can see what the other does.** `tower_selfcheck`'s graph
  walk does not know a corridor exists — the graph says two rooms are joined, and only the
  grid says the doorway between them was drawn, so one `.` typed as a `#` passes check 1
  and all 15 subset walks while the floor is two sealed halves. Its **grid flood-fill**
  (4-connected from the `s` landing, must reach every room cell, pad, post and gate slot)
  is that half; it in turn does not know a `D` is passable, which is the graph's half. The
  plan ↔ graph binding is checked **both ways** — every letter is a built room row, every
  room id is claimed by exactly one storey — and every assertion has a negative control
  driven on a deliberately broken *copy* of a shipped storey.
- **A storey's walls are as tall as ITS OWN clear height** (`plan_clear_height()`), not a
  constant: the top storey is short because the sealed roof is where it is, and a wall
  built to somebody else's height would either poke through that roof or leave a gap you
  can see the next floor through. The gate masses read the same function, so a mass on a
  short storey is a short mass.
- **Walls are 2-D run-length merged**, so a 40-cell wall is one box and not forty — which
  matters because each box is also a `CollisionShape3D`, and the collision body is the one
  thing in this building that is not batched. Measured over the eight planned storeys:
  **52 / 43 / 52 / 29 / 29 / 81 / 62 / 46** boxes against `PLAN_BOX_BUDGET` 120 (the two
  maze floors are the 81 and the 62 — a one-cell maze legitimately produces many rects,
  which is what that budget now guards). Mesh NODES are **35 (`DRAW_BUDGET` 35) for 421
  boxes** — one `FloorNBatch` per storey plus the parts that move — and the whole interior
  is **348 collision shapes on one `StaticBody3D`** (ceiling 420, printed by check 5). A
  plan whose walls stopped merging blows the box budget on its first row. **`DRAW_BUDGET`
  counts nodes, not draws**: emissive is a material property, so a storey carrying a
  `GLOW_COLORS` box commits a second SURFACE in the same `ArrayMesh` and the engine
  submits one draw per surface. Floors 0, 1 and 9 glow (the keep and the cell block),
  so the interior is 13 batch
  surfaces + 25 own-node meshes = **38 real draws**. Read the number as "nothing left the
  batch", not as a draw count.
- **The labyrinth's rule is TWO ROUTES, and the spines walk the ungated one.** Each maze
  storey has an outer circuit that asks nothing of anybody (route A) and a short way
  through the core behind a riddle gate (route B). Check 3 walks every spine with an EMPTY
  solved set, so a riddle on a spine fails the build — that is what forces the second
  route to exist, and why both riddles' clue chambers are dead ends off storey 8's
  circuit.
- **The ramp is derived, never authored.** `S` cells ARE the ramp (one solid rectangle,
  long axis on X, `s` landing against one short end — which end is how the builder knows
  which way it rises), and the stairwell hole in the slab above is computed from
  `SLAB_THICK + PLAN_HEADROOM`, so "adjacent storeys' stair cells coincide" is true by
  construction rather than by review. `PLAN_RAMP_MAX_SLOPE` is the phase-3 ramp's own
  slope, so retuning the one ramp anyone has actually walked retunes the ceiling with it.
  **X-axis only**: a ramp that turned a corner would need a second rectangle, and the
  single rect is what buys the simple slab.
- **`FLOOR_Y` is the one storey table**, and the upper entries are `KEEP_HEIGHT` plus a
  count of the shell's `STOREY_HEIGHT` — a storey is never a number written down twice.
  `_update_visibility`'s window finally bites at five storeys — it hid nothing with two —
  but **the ±1 arithmetic did not survive contact with them and `FLOOR_NEIGHBOURS`
  replaced it**: floor 1 is a MEZZANINE over the 20 m core, so the 80 m annulus at floor 0
  runs straight past it to floor 2's slab, which is its ceiling two indices away. Index
  distance hid that ceiling while it was solid, and hid the grand ramp from the head of
  the grand ramp. Adjacency is now the table, `_floor_visible` reads it, and the check
  asserts the relation's properties (symmetric, reflexive, at most three storeys drawn —
  floor 2, whose slab caps both the annulus and the keep, is the one four) plus this
  building's own touching/not-touching pairs — never the table read back to itself. **The
  cell block is hidden from every storey more than one below it**, and walking up the
  building rebuilds nothing: the window is one boolean write per floor, driven storey by
  storey in check 9.
- **What is deliberately not here yet, all carrying `ponytail:` comments**: `P` pads are
  geometry with no guards to scare (phase 17 owns population); `G` posts spawn nothing;
  and the storey-8 **lift stop** ships its trigger and its graph rows but no menu to
  choose it from — that is bead `godot-test1-3iy.7`. The entry is audited from anyway, so
  the 15-subset property already holds starting at the labyrinth's foot.

`scripts/tower_graph.gd` is the tower's TOPOLOGY as one const dict of plain dicts —
rooms, gated passages, entries, the mutation table, the enumerated scar states, the four
rescue spines. Pure data, depended on by nobody (so no cycle): the interior takes its
gate ids and its identity gate's hero from it, and `tower_selfcheck` walks it to prove
the campaign cannot softlock. Its three design laws are what make that audit tractable —
**spines at floor rank, no item custody, mutations may only ADD edges** (the full-custody
scar being the one owner-sanctioned exception) — and the check asserts all three
structurally, so a row that breaks one fails the build. **A gate added to the building
must appear there**: the correspondence is bound through the interior's legibility
colours, in both directions.

### Biomes are decoration over a flat world — do not break the flat-world invariant
The ground stays flat at y = 0. Coin heights, road placement, crocodile gravity settle,
the spawn point and block bases all assume it. So **mountains are impassable block massifs
you walk around, not raised terrain**, and **rivers are flat tinted wading bands** — a
shader tint plus a speed penalty, no water mesh, depth or transparency. Only the ground
*shader* knows about biomes.

**CPU/GPU parity contract:** `_biome_noise` in `endless_terrain.gd` and `biome_noise` in
`ground.gdshader` are the same function in two languages and **must be edited together** —
the blue band you see and the wading zone you feel have to be the same band. The GDScript
port routes every step through `Vector2` to force fp32, because GDScript floats are f64
and the hash amplifies: a float64 port gives a *different field*, not a more precise one.
Don't simplify any line of it back to scalar arithmetic.

`biome_at()` / `is_river_at()` are the public API — pure, allocation-free, safe per tick.

### Player
`scripts/player_controller.gd` (a `CharacterBody3D`). Character switching on E cycles
`CHARACTERS`, freeing and re-instancing under `$CharacterModel`.

**There is no `AnimationPlayer`.** Limb animation is sine waves driven onto child nodes
looked up **by exact name**: `Body`, and under it `LeftArm` / `RightArm` / `LeftLeg` /
`RightLeg`. A new playable character scene must use these names or it loads and stays
frozen.

**Camera rig is `$CameraPivot/CameraArm/Camera3D`, and `CameraArm` is a `SpringArm3D`,
which overwrites its children's local position every physics frame.** Nothing may write
`camera.position` — it is silently fought and undone. Camera motion uses `h_offset` /
`v_offset`, or moves the arm/pivot. C cycles third-person → first-person → front.

Transient ability state is cleared on respawn and on character switch, so a power never
bleeds across a death or a swap.

### Per-character special abilities (F)
All in `player_controller.gd`; `try_activate_ability()` dispatches on character name and
every ability is gated by a per-character cooldown. windman → Air Rush (fly fast, softened
gravity); primm → Phase Step (blink that scans outward for a spot the body fits, so it can
never land inside geometry); teibi → Resize (small/giant, auto-reverts on a timer, giant
crushes crocodiles and cannot jump); phoboman → Stink Wave (crocodiles flee).

`scripts/ability_effect.gd` is the self-building, self-freeing expanding sphere.
`scripts/ability_hud.gd` reads the player's contract methods for the cooldown dial.

### Crocodiles
`scripts/piglet_crocodile_ai.gd` + `scenes/characters/piglet_crocodile.tscn` is the enemy
the terrain spawns. It wanders, chases within its detection radius, and calls
`player.hit_by_crocodile()`. Crocodiles are solid to one another (`collision_mask = 3`);
the player stays mask 1 and passes through, so damage is decided entirely by the
crocodile's own collision handling.

**Species are data, not subclasses.** Every trait that makes one predator feel different —
speeds, detection, wander rhythm, obstacle feelers, waddle/bite geometry, river sink — is a
row of the `SPECIES` const dict of plain dicts at the top of `piglet_crocodile_ai.gd`, the
same shape as `Progression.SKILL_TREES`. An instance's `species` field is a plain public
var assigned **before `add_child`** (same call-order contract as `setup_as_boss()`), and
`_ready()` resolves it once into `spec`, which the per-frame paths read. A new predator is
a new entry there plus at most one new arm in a `match` — never a new script and never a
subclass. Game-wide contracts stay top-level consts and no species may opt out of them.

**Which species a chunk spawns is PURE DISPATCH on `biome_at(chunk_centre)`** —
`BIOME_SPECIES` in `endless_terrain.gd`, a biome with no entry getting the crocodile.
It must never cost an RNG draw: the chunk's crocodile RNG is one shared stream, so a
single extra draw slides every crocodile in the world to a new spot. Same rule, same
reason, as `CITY_CROC_DIVISOR` and `DESERT_BLOCK_KEEP_EVERY`. Adding a predator is a
`SPECIES` row, a `.tscn` beside `sand_viper.tscn`, and one line in that map;
`enemy_spawn_selfcheck` fails if the row is incomplete, breaks the speed lattice, is
assigned after `add_child`, is reachable from no biome, or carries a `behavior` string
no probe in that file measures. **It iterates `SPECIES`, `BIOME_SPECIES` and the `Biome`
enum, never a list of its own** — so a new predator is covered the day its row lands, and
a new behaviour arm has to bring a probe with it. Keep it that way.

**Behaviour is one `match` on `spec["behavior"]` at the end of `_update_chase_state()`,
and every arm is one call to its own `_behave_*()`** — no logic in the arm, no state
shared between arms, `"solo"` deliberately having no arm at all (it is the code above it,
so an unknown behaviour string degrades to solo). An arm may bend `chase_target`, which is
where a predator *steers*, never how far it can smell — the detection decision is made
above the dispatch. The timber wolf is the first: each one steers to its own slot on a
ring around the quarry, derived from its own deterministic id, so the pack surrounds with
no coordinator, no registry and no group scan — which is also what makes it LOD-safe (a
slept wolf corrupts nothing, a waking one recomputes with no lurch).

Per-instance speed and size rolls are **not** deterministic (they use a `randomize()`d
RNG); only *positions* are. Bosses skip both rolls — `setup_as_boss()` must be called
**before** `add_child`, because `_ready()` is where the rolls happen.

**A boss is a MODIFIER on a species, so anything true of "boss" is written once in the
`is_boss` layer and every boss kind inherits it.** Two rules live there today and neither
may be reimplemented per-kind: the **territory leash** — a boss hunts normally inside
`home_position` + `territory_radius()` and can never leave it, which is the only
counterplay because bosses cannot be killed — and **crush immunity**, which is an
ORDERING (the `is_boss` early return in `_on_player_collision` sits above the giant-Teibi
crush block; swap them and Teibi one-shots the boss with no error anywhere). The territory
is deliberately ONE queryable seam — `home_position` + `territory_radius()` +
`in_territory()` — because the owner intends the zone to grow gameplay later; `is_boss` is
never a bare radius comparison. `boss_selfcheck` pins both.

**Which boss kind a road station gets is its own dispatch, `BIOME_BOSS`** — same shape and
same no-RNG-draw rule as `BIOME_SPECIES`, but keyed on the **owning station's centre**
(`is_river_at` first, the owner's "river → crocodile"), because a boss is station-indexed
and has no chunk centre. It is now **TOTAL over the `Biome` enum** — SNOW → titan,
FOREST → green dragon, PLAINS → hydra, DESERT → naga, MOUNTAIN → roc, CITY → ice cream
clown — which leaves the crocodile as a boss on exactly two paths: a station standing in
a **river**, and the degrade path for a row that fails to resolve. Both stay measured
(`enemy_spawn_selfcheck` fails if its road walk never crosses water; `boss_selfcheck`
drives the crocodile as a subject beside every `BIOME_BOSS` kind). The
row is resolved *above* the candidate walk so the kind stays a pure function of the boss
index. Adding a boss is a `SPECIES` row, a `.tscn`, and one line there —
`enemy_spawn_selfcheck` check 11 walks the road, asks the rule at every station, fails a
row it never actually placed, and compares the body's **whole resolved row** (not one
speed) against the table, because a boss row that shares the crocodile's numbers would
otherwise hide a `species`-after-`add_child` violation.

The dragon is what the seam is supposed to cost: `behavior: "solo"` (no arm — that string
deliberately has no `match` case), no `boss_chase_speed` opt-out, so it takes the default
`BOSS_CHASE_SPEED` (7.0) and is thirty numbers, one `.tscn` and one dispatch line with no
new logic anywhere. The hydra, naga and roc are the same row three more times; the clown
adds only a `"ranged"` dict and reuses the titan's arm unchanged. Every one of their
models is a re-skinned, rescaled existing mesh per the epic's placeholder-first art
convention — the real ones are their own art beads — and a placeholder's collision
capsule may not reach past `BOSS_FOOTPRINT_RADIUS_PER_SCALE` (0.7 m at body scale 1),
which is why several of them are squashed horizontally as well as stretched up.

**A boss-only row may go BELOW `WALK_SPEED`, and the titan does.** The lattice's lower
bound ("walking is caught") is asked of ordinary predators; a boss ignores its row's chase
speed entirely and takes `BOSS_CHASE_SPEED` unless the row opts out with
`boss_chase_speed`, which exists for a species whose threat is its **shot** and not its
feet — the titan and the ice cream clown, both of them archers a walking player must be
able to stroll away from. The exemption is paid for, not free: `enemy_spawn_selfcheck`'s ranged probe
*asserts* every `"ranged"` row's speeds are sub-walk, and `boss_selfcheck` — which runs
every check over every `BIOME_BOSS` kind, not just the crocodile — asserts the body really
resolved the speed its row asked for.

**The GD-SURVEY hunter robot is dispatched on nothing.** The
corporation hunts every band, so it reaches the world through its own
`spawn_hunters_in_chunk` on its own `HUNTER_SALT` hash stream (own salt, own coordinate
primes, own `spawn_hunters` flag) instead of through `BIOME_SPECIES` — which is
dispatch-free and costs the chunk RNG zero draws. That is a **third door** into the
world and check 4's reachability gate reads `HUNTER_SPECIES` to know about it; check 12
is the A/B that *proves* the crocodile stream is untouched rather than asserting it.

**It is also the row that proved player abilities can be opted out of as DATA.** A
machine has no nose and is not flesh, so its row carries `stink_immune` (`flee_from()`
early-returns) and `crush_immune` (giant Teibi's squash block is skipped and the body
takes the ordinary bite path). Both are `spec.get(key, false)` reads placed beside the
existing `is_boss` guards — never a species-name test — so the next armoured or airtight
predator opts in with a row edit and no code change. `boss_selfcheck` check 8 drives
**every** row through both real paths, which makes the seven animal rows the negative
control and anchors the crocodile by name against a stray key.

**The tower guard is the FOURTH door, and it is not in `endless_terrain` at all.** It is
placed on an authored post by `TowerInterior` (`GUARD_SPECIES` / `GUARD_SCENE` /
`GUARD_POSTS`), so check 4's reachability gate reads those consts too — a union over the
dispatch maps and the hunter spawner alone reports a shipped predator as unspawnable.
**It adds no behaviour arm**: "patrols its floor and never leaves it" is the existing
`set_confinement()` leash the elevated-platform guards already use, so the row is
`behavior: "solo"` and the patrol is geometry. Its `coin_setback` key is the third
stake, and it reuses BOTH of the hunter's immunity keys — see the tower section above
for why that is a design decision and not an inheritance.

**Hunter mercy is tuned BEFORE contact and never by a hunter pulling its punch.**
`scripts/hunt_director.gd` (one node in `main.tscn`, group `"hunt_director"`, modelled on
the LOD manager: group discovery, a 2 Hz tick, a pure decision core) answers the hunt arm's
`_hunt_close_granted()` seam with three pre-contact rules — a pursuer cap, a post-grab /
hard-chase lull, and a guaranteed open escape sector. Its entire output is that bool: it
touches no grab range, collision, speed or detection, and a denied hunter keeps SHADOWING
visibly. Rules are bucketed **per quarry by proximity**, never globally — group `"player"`
is the local player, so a global cap would starve a room. **Absent director = granted**,
which is what keeps the standalone `hunter_robot.tscn` and every headless harness working;
that degrade is debug-only, because hunters are Stink-Wave-exempt and uncrushable and the
open sector is their whole fairness budget. `grant_engagement` / `escape_sector_open` are
static and pure so `hunt_director_selfcheck` drives the shipped geometry. Its numbers (cap
2, 20 s chase, 15 s lull, 90°) are **provisional, held for the predator-density epic**.

The species `chase_speed` (5.5 for the crocodile) is deliberately above `WALK_SPEED` (5.0)
so walking gets you caught, and `MAX_CHASE_SPEED` (8.5) — a top-level const clamping every
species' **sustained** speed — is deliberately below the slowest character's run, so
**running always escapes**. Keep that chain intact when retuning anything in it — the
river wade factor is floored for the same reason.

**The `"burst"` arm is the one exception, and the only way anything in this game goes above
8.5.** The mountain cougar and city alley hound multiply that already-clamped speed by a
`burst_factor` for a bounded pounce (11.05 and 11.48 m/s — over the ceiling *and* over the
9.0 run), then pay it back in a mandatory recovery leg. So the promise is not "nothing is
ever faster than 8.5" but **running escapes across the whole pounce-and-recovery cycle** —
a claim about a gap over time, and measured at both ends (a walking player must still be
caught) by `enemy_spawn_selfcheck` check 8, which probes *every* row carrying the
behaviour — a second burst species needs no edit there.

**Ranged attacks are `scripts/boss_projectile.gd`, and it is a CAPABILITY, not a boss.**
One static `BossProjectile.fire(from, at, parent, params, shooter)` taking a params dict
that lives in the firing row's `"ranged"` key, so a new ranged boss is row data plus one
line in its behaviour arm. That file owns flight, visuals, lethality and lifetime only —
cooldown/when/at-whom stays in the arm. Two trajectories exist (`"straight"`, `"lob"`) and
**both freeze their aim at fire time: no homing, ever** — side-stepping is the whole
counterplay against a boss that cannot be killed. Projectiles are transient combat effects
and sit **outside the world-determinism contract** (no RNG, no hash stream, no footprint),
like weather and fauna. The **fairness contract** is the load-bearing part and is measured
per style by `projectile_selfcheck`: from its `min_fire_range` the flight must last long
enough for a merely *walking* player to clear 3x the hit radius, and its horizontal speed
must stay under `RUN_SPEED`. "Make the bolt snappier" is the retune that breaks the game.

The spawn point is a crocodile-free bubble enforced in generation
(`SPAWN_SAFE_RADIUS`, mirrored in `player_controller`; keep the two in step).

### Crocodile / coin simulation LOD
`scripts/crocodile_lod_manager.gd` sleeps distant crocodiles on a ~9 Hz tick by calling
`set_lod_active(false)` (which zeroes velocity and stops `_physics_process`), and freezes
coin animation beyond its own radius. Two invariants:

- **`SIM_RADIUS` (45) must stay well above every species' `detection_radius` (5–18 across
  the table — the ambushing viper's 5 is the floor, the wolf's 18 the ceiling; 25 for a
  boss).** Anything that could
  chase or touch the player is always fully awake, so near-player behaviour is unchanged.
  A boss widens that chain by one link — `BOSS_DETECTION_RADIUS` (25) <=
  `BOSS_TERRITORY_RADIUS` (32) < `SIM_RADIUS` (45) — because it is leashed to the area it
  spawned in and the whole ZONE, not just the smell, has to fit inside the sleep radius.
- **Crocodiles are slept, never removed.** Entity counts stay the same.

The same scan publishes the nearest chaser's distance to the danger vignette — **two
channels off one scan**, split on the chaser's `behavior`: animals drive the red edge glow
and the heartbeat loop, a GD-SURVEY hunter drives its own cold scanning rim (and no
heartbeat — its audio channel is the lock-on ping). Both are normalised by the chaser's
OWN `detection_radius`, both are published every scan, and the vignette's shader ADDS them
in different radial bands so neither can suppress the other. A second retrieval unit joins
the machine channel with its `SPECIES` row and no edit anywhere.

Hunters are in group `"crocodile"`, so **the F3 overlay's "Crocs (active/total)" counter
means predators + hunters** — which is exactly what the LOD manager manages.

### Systemic capture — a hunter takes the HERO
A post-beat grab by a predator on the `"hunt"` arm puts the ACTIVE hero in `player_controller`'s
`captive_heroes` and steps into the next free one. Four rules:

- **Availability is `hand INTERSECT free`, at ONE site.** `switch_to_next_character()` already
  cycles inside an allowed-index array (the lobby's, in a room); captivity is one more
  intersection there. There is no second roster system, and there may not be one.
- **The auto-switch goes through `set_active_character()`**, never the E-cycle: that is where
  `_reset_ability_states()` lives, and the cycle refuses a press mid-Air-Rush anyway.
- **It arms only after the authored Primm rescue** (`TowerInterior.RESCUE_DONE` in the stored
  tower set) — the beat is where the rule is taught. Before it, a grab is an ordinary bite.
- **The set is NON-MONOTONE** (captures add, liberations remove), so it stays out of
  `best_run_store`'s union/max merge, which the tower's opened-gate ids *do* ride. A captive
  folded into a union could never be freed.

The player owns the set; `TowerInterior` mirrors it (pushed on a grab, re-seeded on build)
because the tower is usually not streamed in when a field grab lands. An empty free set
opens the FULL-CUSTODY PROTOCOL (see the tower section), decided beside the out-of-hearts
branch in `_on_caught_finished()` — which stays the one place a heart-death is decided,
inside the scene as well as outside it.
`free_hero_count()` is the hunt director's roster seam — death-spiral mitigation belongs
there, before contact, never in the capture path.

**IN A ROOM THE CAPTIVE SET IS ROOM-WIDE, and the rule is REASSIGN FIRST, IMPRISON
LAST.** A capture broadcasts the `cap` verb; every peer mirrors it into its own
`captive_heroes`, so the picker, the E-cycle and the ending all become world-level with
no second roster. The reassignment is the LOBBY's `SetHero` and needs no server change —
two peers benched in one frame serialize on the room lock, first wins, second retries on
the next `_tick_prison()`, which is the ONE site that sends it. Only a room with nothing
free benches anybody, and a benched peer plays as their captive inside the cell block:
confined to the gallery and its cells (`TowerInterior.block_min/max`), with **no ability**
(`get_ability_block_reason()` answers `"CELL"`), able to free a CELLMATE but never
themselves, and able to operate the VENT PURGE — theirs alone, and it scatters the pack
around every teammate through the shipped `flee` verb. `_tick_prison()` stands aside
while `is_caught`, so the grab that empties the roster still pays its heart in
`_on_caught_finished()`. **Game over is world-level** — the room's free set empty, not
this peer's hand — which is an adopted reading of the owner's phrasing.

### Death, lives, respawn
Three lives (up to five from coins), drawn by `scripts/lives_hud.gd`, which reads the pip
total from the player rather than keeping its own constant. `hit_by_crocodile()` →
freeze/flash → spend a life → either **soft respawn in place** (keep coins, frozen grace
then invulnerable blinking) or **game over**. Invulnerability is enforced in one place: the
early-return at the top of `hit_by_crocodile()`. `reset_position()` is now only the hard
reset to spawn used by `restart_game()`.

### Gameplay loop
`run_seed` is rolled in `_ready()` from a private RNG and re-rolled by `new_run()`, which
is the only place it changes; `set_run_seed()` is the only place it is written, because the
biome domain offset derives from it. Distance is the headline score. Coins have a streak
multiplier and grant extra lives at thresholds; gems are worth 10. Difficulty scales with
`absf(global_position.x)` — all pure functions of position.

### Meta-progression and skill trees
`scripts/progression.gd` (group `"progression"`) owns lifetime coins → levels → skill
points, and is **run-independent** — nothing in restart/new-run/reset touches it. Levels
derive from the raw count, so there is no second number to drift; coins are never deducted,
which is what lets every persistence layer merge with a plain monotone `max`.

`Progression.SKILL_TREES` is one const dict of plain dicts — no class hierarchy, no custom
`Resource`. **Hard caps live in the getters, not in the tree data**, so retuning ranks or a
hand-edited profile cannot exceed them. Effects reach gameplay through one null-safe helper
pair in `player_controller`, so the consts stay consts.

**There is no walk-speed effect and there may never be one** — the catchable-walk contract
above is the tightest margin in the game.

Panels open on raw keycodes outside the input map (K, M, P, +/−, F3–F7): named actions are
for rebindable *gameplay* input, and a key that only opens a panel has nothing to rebind
against. Every overlay pauses the tree, because the player reads gameplay through global
polled `Input`, which a focused `Control` does not suppress.

### The pause is refcounted — `scripts/pause_hub.gd` is the only writer
Seven scripts freeze the world (`pause_controller`, `help_overlay`, `skill_tree_ui`,
`mp_ui`, `start_overlay`, `mobile_input`, `landmark_toast`). They used to own it
first-taker-wins, and the bug was **emergent**: an overlay opening over an already-paused
tree claimed nothing, so whichever owner released first started the world under every
overlay still on screen (P, `?`, P — help card over live crocodiles).

`PauseHub.take(who)` / `PauseHub.release(who)` refcount holders **by identity**; the tree
is paused while the set is non-empty. **No other script may assign `.paused`** —
`pause_selfcheck` scans `scripts/*.gd` and fails if one does. A new pauser is a
take/release pair plus its own "did I claim" bit; it needs no edit anywhere else.

What stays with the feature and NOT in the hub: the refusals (`pause_controller` and
`mobile_input` won't pause over game-over, `landmark_toast` won't in a room,
`skill_tree_ui` won't open under a foreign pause), and reads of `get_tree().paused` as a
**condition** — "is the world stopped" — which several places want and which are
deliberately not routed through the refcount.

### Persistence
`scripts/best_run_store.gd` owns best distance/coins plus lifetime coins, spent points and
skill ranks. Three layers: `user://best_run.cfg`, `localStorage` on web, and
`GET`/`POST <lobby>/best?id=<player id>` on the Go lobby. Every field is monotone and every
write is a read-modify-write merge, so a late reply can never lower a record and a retry is
free. Server failures are silent and non-fatal. Skill ranks are local-only.

**Ceiling:** the id is per browser profile and per install, so "follows you between devices"
means devices sharing the id, and nothing transfers one.

### Synthesized audio — no asset files
`scripts/sound_manager.gd` generates every sound in code as an `AudioStreamWAV`. **There
are no audio asset files**; keep it that way. One-shots ride a round-robin player pool;
named ambient beds come from `get_loop_player(name)`.

**Browsers block audio until a user gesture**, so every `play_*` early-returns until
`unlock_audio()` fires. Don't add a path that bypasses that gate; a `get_loop_player` voice
must check `is_unlocked()` itself.

**An acquisition cue belongs on the `is_chasing` edge, and that edge exists TWICE.**
`_announce_acquisition()` in `piglet_crocodile_ai.gd` is the one home of the boss growl,
the viper hiss and the hunter's lock-on ping, and it is called from `_update_chase_state()`
AND from `set_remote_state()`, which re-detects the same edge off `CROC_FLAG_CHASING`. A
cue fired from a behaviour arm — or from anywhere else below `_tick_remote()`'s early
return — is **silent for every player in the room but the one simulating that body**.

### Weather and fauna — ambience, deliberately outside the determinism contract
`scripts/weather_manager.gd` (clouds, storm rain zones, birds) and
`scripts/fauna_manager.gd` (elephant/giraffe herds, herder caravans) both use their own
`randomize()`d RNG and never touch `run_seed`. Don't wire them in.

Weather exposes `is_raining_at(pos)`; the player uses it through one null-safe helper —
Windman can't launch in rain and loses an active boost on entering one.

Fauna: **one herd at a time, ever** — that is the whole perf story. Animals join **no
group** and have **no collision** (a fauna node in `"crocodile"` would be grabbed by the
Stink Wave and the LOD manager), are parented to the manager rather than a chunk, and are
animated by one `_process` on the manager. Feet rest at y = 0 by construction. Species share
one `BoxMesh` and one material each via static lazy getters — never `duplicate()` a material
per animal.

### Art direction
Authored in `main.tscn` (key light, ProceduralSky, glow, BCS grade) plus
`scripts/toon_shading.gd`, whose **static cache keyed by source material id** is the point:
hundreds of crocodiles get one styled duplicate per source material, never one per instance.
Fog colour must equal the sky horizon colours — if the sky changes, all three move together.
Verified against the web `gl_compatibility` renderer; SSAO/DOF/volumetrics don't exist there.

### Mobile / touch controls
`scripts/mobile_sensors.gd` (native `Input` sensors or a `JavaScriptBridge` DOM shim),
`scripts/mobile_input.gd` (step detection → walk, tilt/twist → steer),
`scenes/ui/touch_controls.tscn`, and a live tuning panel persisting to
`user://mobile_tuning.cfg`.

**The design rule: synthesize the EXISTING input actions, don't add controller code paths.**
Analog held actions via `Input.action_press(action, strength)`; discrete buttons via
`Input.parse_input_event(InputEventAction)`.

**`switch_character` is handled in `player_controller._input()`, not polled** — so
`action_press` would silently never fire it. It must go through `parse_input_event`.

Everything is gated on `DisplayServer.is_touchscreen_available()`; on desktop the UI is
hidden, the driver writes no `Input`, and keyboard play is byte-for-byte unchanged.

### Localization (en / de)
Almost none of this is our code — it is Godot's built-in `Control` auto-translation.

- **Rule 1: the translation key IS the English source string.** A plain literal assigned to
  `.text` needs no `tr()` call. `assets/translations/ui.csv` is a `keys,en,de` table.
- **Rule 2: `tr()` explicitly on the FORMAT STRING** wherever text is composed at runtime —
  auto-translation would only see the formatted result, which is a key in no table.

German is ~30% longer and this UI has hard-sized controls, so fit is **measured** by
`locale_selfcheck.gd`, not eyeballed. Debug surfaces (F3/F4, ⚙ telemetry, selfcheck output)
are deliberately not localized.

**CI gotcha:** `*.translation` and `*.import` are gitignored, so CI must run an explicit
`--import` step before the export.

## Multiplayer

### Lobby service (`server/`)
A small Go service — **the only server** — doing signalling, membership and master naming,
and deliberately no game logic and no game state. Rooms live in memory. `room.go` is the
state machine and imports no network types, so tests drive it directly.

- **The lobby never inspects `payload`.** Offers, answers and ICE all ride one opaque
  `signal` relay; that opacity is what keeps game logic off the server.
- The master is the oldest surviving member, re-elected on disconnect or by a stall vote.
- Trust-boundary guards that must stay: the read limit and the relayed-payload cap.
- `GET /ice` serves STUN/TURN config from the environment, so credentials are never baked
  into the build.
- **A new route must also be added to the Traefik path list in `server/docker-compose.yml`**
  — the game client owns `/`, so a missing rule silently serves `index.html`.

### Mesh (`scripts/mp_manager.gd` and friends)
`lobby_client.gd` (socket + `/ice`), `mp_manager.gd` (mesh, seed, presence, heroes, shared
totals, crocodile sync, claims), `remote_avatar.gd` (visual only), `mp_ui.gd`,
`teammate_locator.gd`.

The sharpest rules, in rough order of how badly they bite:

- **`_rtc` is NEVER assigned to `multiplayer.multiplayer_peer`.** The `WebRTCMultiplayerPeer`
  is used as a plain `PacketPeer`. This is the single most important line in the file.
- **The isolation contract — a `RemoteAvatar` is a picture of a player, not a player.** It
  joins no group (above all not `"player"`), adds no `CollisionObject3D` / `Area3D` /
  `CharacterBody3D`, and parents to the MP manager.
- **`bytes_to_var`, never `bytes_to_var_with_objects`.**
- **The feature is inert until a room is joined** — `_process` early-returns while OFFLINE,
  so solo play is byte-for-byte unchanged.
- Peer ids are a pure function of the lobby id, so the mesh needs no numbering protocol.
  The lexicographically lower id offers, which kills glare with no round trip.
- **The seed travels over the lobby relay, not the mesh**, because it must arrive before any
  data channel opens.
- **The lobby is the source of truth for hero assignment**; nothing is decided locally.
- Coin identity derives from quantized position, crocodile identity from the deterministic
  node name — so no spawner needed editing.
- **Everything relayed is unvalidated peer input.** Type-check every field, drop anything
  malformed, and rate-limit the state-mutating verbs per peer.
- Crocodiles are **master-simulated but never network-spawned** — lifetime stays local,
  deterministic and chunk-parented. A crocodile's quarry is the nearest *room member*, not
  the nearest node in group `"player"`.
- Shared bank/lives/distance are a sum of per-peer absolute broadcasts — no authority, no
  round trips.
- The join snapshot is a trust boundary and carries absolute values, never deltas.
- **The captive set is GAME state, so it rides the mesh and not the lobby.** One verb
  (`cap`), and a capture is authorized by **`_last_holder`, not `_heroes`** — the lobby's
  last named holder of that hero, a map that only ever learns. `SetHero` releases the
  captured hero as it grants the replacement, so the live map stops naming the captor at
  an unpredictable moment relative to the packet, and the two travel different transports.
  Release is open to any member, because liberation is performed by whoever walked into
  the cell. **It goes over the mesh AND the lobby relay** — the relay reaching exactly the
  peers whose ICE is not finished, the seed's own reasoning one verb along. The join
  snapshot carries the whole set and is honoured **from the master alone**, like `dead`.
  Entering a room resets the local mirror: a room's roster is the room's.
- **The master publishes the two values a room may never disagree about** — the captive
  set and the break-out's clock and verdict — on one verb (`room`, 2 Hz, mesh + relay,
  master-only, applied wholesale). It is a REPAIR channel, not the source: it closes the
  join gap the per-hero verb cannot reach (a capture landing between the master
  snapshotting a joiner and the captor learning that joiner exists), and it converges in
  BOTH directions while leaving any assertion younger than `RELEASE_GRACE_MSEC` alone —
  without that the master's older picture undoes a fresh local capture and puts it back
  next tick, a flap at the publish rate. **A non-master runs the recall clock for
  presentation and decides nothing**; the master's verdict is what ends the scene, and it
  survives re-election because the clock is published as SECONDS LEFT, so the new master
  carries on from the number it was already showing. `_auto_claim_hero()` waits for
  `_join_settled()` — on the `welcome` frame the captive set is still empty, and claiming
  there means claiming a hero who is in a cell.
- The stall heartbeat rides the lobby relay, not the mesh, because a throttled tab stops
  polling both.

Desktop needs the `webrtc-native` addon (fetched by `./fetch_webrtc_addon.sh`, never
vendored); the web build needs nothing.

## Performance & web build

The web (WebGL) build is the performance-sensitive target.

- `scripts/perf_overlay.gd` — **F3**. FPS, draw calls, node count, active/total crocs. This
  is the measurement tool; use it to prove a change and catch regressions.
- The same script samples **every frame, hidden or not**, and logs any frame over 33 / 50 ms
  with what the engine did on it (chunks built/freed, whether the LOD scan ticked, node
  count) — to the console as `[SPIKE] …` and to `get_spike_log()` / `get_spike_summary()`.
  Averages hide freezes; that log is what optimization work is measured against. It reads
  `chunks_created_total` / `chunks_removed_total` on the terrain and `lod_scans_total` on
  the LOD manager by **polling** — a spike source that wants to be visible exposes a
  monotone counter, never a signal, so measuring can't perturb what it measures.
- Web-only tuning in `project.godot` `[rendering]` via the `.web` suffix, plus a lower
  `render_distance` at runtime behind `OS.has_feature("web")`.
- Fog is the one **universal** visual change (owner-approved); only its density is
  platform-gated.

### Performance conventions
- **Visual-affecting changes are web-gated.** Desktop and editor stay at full quality.
- **Purely invisible optimizations are global** (batching, LOD, consolidated collision).
- **Entity counts are never reduced as an optimization.** Croc counts change only by
  *design*. Distant crocodiles are slept, never removed.

## CI/CD

`.github/workflows/build.yml` builds the web export on every push, and runs the two
self-check jobs beside it: `selfchecks` globs **every** `scripts/*_selfcheck.gd` (so a new
one is gated the day it lands) and `model-selfcheck` runs `scripts/predator_parts.py`.
A check counts as passed only if it exits 0 **and** printed `SELFCHECK OK` — a GDScript
parse error exits 0, so the exit code alone is not a verdict. Both deploy jobs `needs:`
them. **Deploy happens only on push to `master`** — merging is what publishes.

The same master push runs `deploy-stack`, the **single owner of the `deploy` branch** that
Portainer reads: it builds both production images, pins them by commit SHA (**never
`:latest`**), rewrites `server/docker-compose.yml` and force-pushes. **Both images must stay
in that one job** — the branch is maintained by force-push, so a second workflow writing it
would clobber the other's pin.

## Conventions

- GDScript with explicit type hints; tunable constants declared at the top of each script.
- Gravity is per-script and intentionally non-physical (arcade-snappy, not realistic).
  Jumps get coyote time and input buffering; horizontal velocity uses `move_toward`, not a
  snap.
- Gameplay input goes through the named actions in `project.godot`; don't hardcode keycodes.
  Meta/UI keys that only toggle a panel stay outside the input map (see the skill-tree note).
- Match the surrounding comment density. This codebase is written to be read.

## Issue tracking

This project uses **bd** (beads). Run `bd prime` for the workflow, commands, and
session-close protocol — it is injected at session start by the `.claude/settings.json`
SessionStart hook, so it is always current. Don't restate it here; this file rots, `bd prime` doesn't.
