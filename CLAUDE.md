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

**EVERY CHECK STAMPS ITS OWN EXIT, through `scripts/selfcheck_sentinel.gd`.** A GDScript
runtime error does not stop a script — it aborts the FUNCTION it lands in (returning that
function's declared default, `""` for a `-> String` check, which reads as "no failure")
and execution carries on, so a check that dies halfway simply stops asserting and the file
prints `SELFCHECK OK`. So a check calls `Sentinel.done("name")` as its last statement and
before every early exit, and the report site calls `Sentinel.finish(self)` in place of
`print("SELFCHECK OK")` + `quit(0)`; the expected set is READ OUT OF THE FILE'S OWN SOURCE
rather than listed in a const, so a check added or renamed is covered without a second edit.
It is consulted only on the PASSING path — a run that already failed fails anyway, and
`mp_selfcheck`'s fail-fast runner would otherwise bury one honest message under
twenty-seven unreached checks. A new self-check needs the preload, the stamps and that one
report line.

**EVERY CHECK ALSO OWNS ITS `user://` STATE, and the seam is the same file.**
`Sentinel.isolate_user_state()` is the FIRST statement of every check's
`_initialize()`: it points `BestRunStore.config_path` and
`StartOverlay.locale_config_path` at a freshly created directory keyed by this
PROCESS's pid, so a check can neither read the developer's real profile nor be
trampled by the same check running in another worktree (`user://` is per PROJECT
NAME, so every checkout on a machine shares one directory) nor inherit the state a
SIGTERM'd predecessor left behind — bead `godot-test1-3y3`, generalising `t8z`'s
per-file redirect in `progression_selfcheck`, which was hermetic against the player
and not against itself. `progression_selfcheck`'s `hermetic_stores` check audits the
glob for that call, for any other assignment of either seam, and for the real paths
as literals. **The shipped game is untouched** and still persists to
`user://best_run.cfg`.

```bash
godot --path . scenes/main.tscn                    # run the game
godot --path . scenes/characters/primm.tscn        # run one scene in isolation
mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html
./serve.sh                                          # serve a web build (WASM needs http://)

# Self-checks — godot --headless --path . --script res://scripts/<name>.gd
#   batch_selfcheck          the chunk batch's MESH-KIND slot: every BoxKind's
#                            unit mesh inscribed in the unit cube (and spanning
#                            its full height, or the shader gradient never
#                            reaches full colour), one MultiMeshInstance3D per
#                            kind PRESENT sharing one material and one shadow
#                            flag (a cube-only batch still exactly one node
#                            named BlockMultiMesh, measured over 225 real field
#                            chunks), the city splitter carrying kind and
#                            leaving a non-cube WHOLE on BOTH halves (the mesh on
#                            kind, the body on its BoxShape3D cast) with the wide
#                            CUBE cut into equal piece counts either side, and
#                            check 4 the PER-KIND COLLISION SHAPE: the type per
#                            kind, the radius/height, the collider INSCRIBED in
#                            dimensions, one shape per colliding entry and none
#                            without, and the aspect fallback driven at BOTH ends
#                            of ROUND_COLLIDER_MAX_ASPECT. Check 5 is
#                            the PER-BIOME DRAW-CALL BILL, iterating the Biome
#                            enum over both shipped field spawners: a forest
#                            chunk builds exactly TWO nodes (BlockMultiMesh +
#                            BlockMultiMesh_SPHERE, the canopies) and every
#                            other biome exactly one
#   fauna_selfcheck          herd steering + rider carry
#   mp_selfcheck             multiplayer pure logic (decoders, ids, arithmetic)
#   locale_selfcheck         en/de table + German fits its controls
#   view_selfcheck           the three camera views C cycles
#   progression_selfcheck    level curve, skill trees, effects on a live player,
#                            plus `hermetic_stores`: every `*_selfcheck.gd` in the
#                            glob opens `Sentinel.isolate_user_state()` and names
#                            no real `user://` path
#   wade_selfcheck           river wading (player, croc, boss)
#   field_bridge_selfcheck   FIELD BRIDGES where the road crosses a river: every
#                            crossing under the span cap bridged exactly once
#                            over 12 seeds (with the lake case counted), the
#                            stone the CHUNKS build walked metre by metre in
#                            three lanes for holes / seam gaps / duplicates,
#                            the slope against TowerInterior.PLAN_RAMP_MAX_SLOPE
#                            with a STEP as its control, both abutments dry with
#                            mid-span as the wet control, the deck narrower than
#                            every *_ROAD_CLEARANCE, the A/B (feature off: same
#                            footprints, bodies and boxes byte for byte; coins
#                            move in Y only) — and check 7, a REAL player.tscn
#                            walked across a REAL deck: dry every metre, wet a
#                            metre off the parapet, wet again with the deck gone.
#                            Check 9 walks the AUTHORED APPROACH CORRIDOR (T to
#                            the gate) metre by metre and asserts every wet
#                            stretch is bridged; check 10 samples the wedge arc
#                            at all 203 turning joints of all 39 bridges
#   altitude_selfcheck       the FIELD ALTITUDE spike (flag off): 0.0 everywhere
#                            with the flag off, the fp32 CPU/GPU port bit-exact
#                            against a GLSL-derived oracle (with an f64 negative
#                            control), the four forced-flat zones each with a
#                            control outside its skirt PLUS the road window's
#                            slide (the corridor may not move when the window
#                            does — a chunk's floor is baked once), every alt_*
#                            uniform declared, pushed, valued AND defaulted, the
#                            collision heightmap on the mesh's REAL vertex grid,
#                            and the field's walkable slope
#   minimap_selfcheck        the map actually read the world
#   city_map_selfcheck       the Budapest map panel (B): the key is free against
#                            the input map AND every other panel's constant, the
#                            plan is BAKED ONCE and is really the plan, the mask
#                            lights the right slots, and the pause is taken solo
#                            but never in a room nor over game over
#   help_selfcheck           keymap card vs the real input map
#   hero_hud_selfcheck       the portrait row: one colour row and one loadable
#                            portrait per CHARACTERS hero at the single asset
#                            path, the four tile states (captive OUTRANKS
#                            active), the no-player degrade, and the row's
#                            fit in main.tscn against every other widget
#                            pinned to that corner, \fo included
#   landmark_selfcheck       every builder fits its declared radius AND its
#                            declared top
#   landmark_sites_selfcheck THE MUSEUM MILE: every field kind sited AT MOST ONCE
#                            (a 31x31 window through the shipped reverse lookup,
#                            and the whole site table), no site in the HQ disc /
#                            Budapest rect / spawn bubble / river with four
#                            mutation controls, >= 2 x LANDMARK_RADIUS between
#                            real built centres, a site-free chunk byte-identical
#                            with landmarks on and off (crocodiles included) plus
#                            `_landmark_at` read as TEXT for a draw or a k, the
#                            built/on-the-mile floors (measured through the shipped
#                            `create_chunk`, with the harness read as TEXT so it
#                            can never drift back to a hand-rolled spawner order
#                            that skips the artifact and the camp), a REALLY BUILT
#                            marker walked up to through the shipped toast, and
#                            check 1b: `set_run_seed()` drops the memo
#   prop_selfcheck           prop/structure footprints, budgets, palettes
#   scarcity_selfcheck       the distance gradient, ONE RULE FOR EVERY BIOME: the
#                            k curve itself, then a near and a far field per
#                            `Biome` value built through the shipped spawners —
#                            far builds nothing, near does (the control), and the
#                            mountain MASSIF exemption is asserted POSITIVELY;
#                            plus the spawners that must never read k (predators,
#                            hunters, bosses, road coins) read as TEXT, with a
#                            near/far predator count beside it
#   enemy_spawn_selfcheck    every species PLACED: no spawn in stone,
#                            deterministic placement, the SPECIES table and both
#                            dispatch maps, MP identity, and the coverage
#                            verdict; plus check 13 the HUNTER FIELD CAP (the
#                            expected desktop residency under HUNTER_FIELD_CAP
#                            off the consts, and the live cap firing, reading the
#                            COUNT, excluding the HQ by PARENT, off in a room,
#                            and moving nothing else) and check 14 a ROAD BOSS'S
#                            FOOTPRINT (its own column refused by the shipped
#                            _settle_coin_y, and no coin inside one over 25 roads)
#   enemy_behavior_selfcheck what a predator DOES once it has seen you — one
#                            probe per arm on a live body against a live stub:
#                            pack surround, the ambush trip-wire, the charge
#                            sidestep, the burst and leap races (both ends: a
#                            run escapes, a walk is caught), the ranged cadence,
#                            the hunt ring and its scent nose, the tracker's
#                            chunk-to-chunk adoption, the view cone's telegraph
#                            and the Budapest crowd false-arrest. Split from
#                            enemy_spawn by bd godot-test1-ftn.13 (CI shards the
#                            glob BY FILE); the two stay bound through
#                            enemy_spawn's PROBED_BEHAVIORS, which fails BY NAME
#                            a `behavior` string with no probe here
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
#   budapest_selfcheck       the authored city: the plan's PURITY read as text (no
#                            seed, no draw, no hash) and its 22 slots well formed,
#                            two byte-identical regenerations across DIFFERENT run
#                            seeds (and every city chunk byte-identical across the
#                            same pair), the per-chunk box/shape budgets, the SLICING
#                            decision (every box AND every collision shape of a
#                            giant kept exactly once across its chunks, off the
#                            slot's seed alone, neither outgrowing a chunk),
#                            CPU/GPU parity over the forced CITY ground and the
#                            authored Danube, the approach corridor reaching the
#                            gate for 50 seeds, all four road consumers stopping
#                            at T, the five per-system spawner answers (with the
#                            hunters as the positive control), the Danube
#                            crocodiles' own stream A/B'd against the shared one,
#                            the difficulty clamp at both ends, and check 4's WEB
#                            RESIDENCY window — the only thing that can see a
#                            cost that moved out of one chunk and into 1,631,
#                            which also names the Parliament and Chain Bridge
#                            7x7 windows as info beside the densest one it
#                            asserts, with city coins inside the timed window.
#                            Check 18 DETERMINISM: every city chunk
#                            byte-identical across the two seeds and the
#                            crocodile stream outside the rect plus the hunter
#                            stream on the north field outside, both A/B'd
#                            against city-disabled builds with non-empty body
#                            counts
#   budapest_city_selfcheck  the city the CHUNKS BUILD, split from
#                            budapest_selfcheck by bd godot-test1-ftn.13 (CI
#                            shards the glob BY FILE) with the check NUMBERS
#                            unchanged: 11 the plateau ramps' slope, 13 the
#                            gate-to-river avenue walkable, and 14 THE FOUR
#                            BRIDGES — each deck rect bound to the SLOTS row its
#                            pylons stand on, both abutments on the bank, the
#                            crossing DRY metre by metre with a wet control off
#                            the parapet, and the surface the chunks really build
#                            measured against the plan's profile (flush, no step,
#                            no seam gap on either axis); plus Margaret Island
#                            dry and inside the band, the Danube's crocodiles
#                            bucketed north/middle/south so the policy is proved
#                            along the WHOLE river, and NOTHING STANDS IN THE
#                            RIVER OR IN A MASSIF — every landmark's COLLIDING
#                            STONE measured against the band (never its disc,
#                            which for a 268 m Parliament is a bound 33 m into
#                            the water while not one stone of it is) and every
#                            disc against every plateau, exempting only slots on
#                            a DRY_RECTS row or a plateau lid plus the one named
#                            `shoes_on_the_danube`; with a mutation control that
#                            runs a shipped builder mid-channel. Check 15 is THE
#                            CITY IS FULL: every grid cell the plan does not
#                            reserve filled with a ring of street walls, no
#                            solid box in any carriageway (the authored city's
#                            own cells, the plateaus and the decks exempted and
#                            counted), every courtyard hollow, and the coin
#                            routes on the avenues with a gem at a square and a
#                            line across every bridge. Check 16 REACHABILITY:
#                            one hero, no ability — every slot flood-reachable
#                            from the gate over streets/decks/ramps/plateau
#                            tops, every .7 block and .6a-c footprint as stone,
#                            the flood height-gated at 2.6 m or a ramp; two
#                            negative controls (a wall on Margaret Bridge,
#                            Castle Hill's ramp removed)
#   landmark_progress_selfcheck
#                            BUDAPEST'S WIN: the catalogue (every slot resolves a
#                            CITY_LANDMARKS row by BUILDER NAME, a wave-C
#                            reservation gracefully resolves none), the 22-bit
#                            explored mask on a real player.tscn (idempotent,
#                            range-checked, the mirror ORs and never assigns),
#                            the 18-of-22 threshold WITH its negative control,
#                            both wire formats DECODED WITH THE FIELD ABSENT
#                            (`room`'s `m`, the join snapshot's `lm` — an old
#                            master's packet must repair the cells, not be
#                            dropped), the `lmk` parser over ints AND relay
#                            floats, the master's proximity rule, and the
#                            approach trigger driven through the shipped toast
#   intro_selfcheck          intro film: web gate, desktop PLAY path, JS shape,
#                            and the ONE-PRESS start card — no mode fork, and it
#                            still names the MP button (bead godot-test1-6pa)
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
#                            the DORMANT SCAR still drawn (its rubble is a doorway
#                            the unscarred plan leaves open, and once taken it is
#                            drawn AND solid AND survives a relaunch).
#                            Every geometry check LOOPS OVER STOREYS off FLOOR_Y
#                            and TowerPlans.floors(), so a new plan row is
#                            covered the day it lands: per-storey box budget,
#                            headroom, and the ramp flush at both ends.
#                            Check 20 is the EVIDENCE DOSSIERS: every authored
#                            cell open, flood-fill-reachable, on an office or
#                            ops storey, distinct, and clear of everything else
#                            that storey draws; the crawl alcove measured
#                            against the real capsule and TEIBI_SCALE_SMALL and
#                            asserted to be a dead end; and one dossier taken
#                            for real coins, hidden, and refusing to pay twice
#   capture_selfcheck        SYSTEMIC CAPTURE and the tower guard's stake: the
#                            arming gate (pre/post the
#                            authored beat), attribution (every `captures_hero`
#                            row takes one, animals and row-less hazards none),
#                            the guard's arrest in place vs its PRE-BEAT
#                            setback+knockback, invulnerability covering the hero too, the
#                            clean auto-switch, liberation, the empty-roster game
#                            over as the ONLY game over there is, that the set
#                            never touches
#                            the monotone store, the cell-block mirror in both
#                            directions, and THE ENDING: the fourth capture ends
#                            the run in the same frame chain and archives the world
#                            without touching the building (Continue reopens the
#                            ending, New Game clears it), plus the vocabulary of
#                            both retired models — hearts and the vetoed break-out
#   tower_lift_selfcheck     the HQ's service lift (L): the key is free against the
#                            input map AND every other panel's constant, every stop
#                            is a built `entries` row with an `unlock` id landing on
#                            a real `s` cell, and the menu driven on a REAL shell —
#                            nothing offered before it is opened, the opened stop
#                            listed, the ride landing on that storey's landing, an
#                            unoffered floor refused, and the four refusals (room,
#                            game over, mid-bite, away from the call point) each
#                            with the refusal removed as its control
#   tower_selfcheck          THE SOFTLOCK AUDIT: TOWER_GRAPH bound to the boxes
#                            the interior really builds, the three design laws
#                            (spines at floor rank, no item custody, mutations
#                            edge-additive + the sanctioned scar), all 15
#                            free-hero subsets reaching a cell from every entry,
#                            in every story-flag and scar state, that every
#                            authored scar is one the BUILDING can inflict, and
#                            — phase 14 — the two things the graph walk CANNOT
#                            see: the per-storey GRID FLOOD-FILL (a doorway
#                            typed as a wall passes every subset walk) — run
#                            TWICE, the second time with every gate cell
#                            treated as stone, which is the only thing that
#                            binds an ungated graph row to the drawing — the
#                            plan-room / gate-slot binding to TOWER_GRAPH rows,
#                            both ways, and that a RISING gate is drawn under a
#                            wall and not over somebody's floor; each with a
#                            negative control

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
build. Running it directly rebuilds and checks all TWELVE models:
`python3 scripts/predator_parts.py` -> `SELFCHECK OK`. The two HUMANOID bosses (titan,
clown) are rebuilt by that loop but carry their own `verify_*`, because the shared one
demands a quadruped's longer-than-wide silhouette — see the note over the loop. Two of its primitives are
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
`player`, `crocodile`, `enemy`, `coin`, `landmark`, `terrain`, `weather`, `fauna`, `crowd`,
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
  instance a MeshInstance3D or a physics body per object. **That seam is its own file** —
  `scripts/chunk_batch.gd` (`class_name ChunkBatch`, all static, bead `godot-test1-ftn.1`):
  `create_box` / `_build_block_multimesh`, the two process-wide shared
  resources (`_get_shared_unit_box_mesh` / `_get_shared_block_material` — the latter
  the `world_block.gdshader` material, with `WORLD_BLOCK_SHADER`,
  `BLOCK_BOTTOM_SHADE`, `SHARED_BLOCK_ROUGHNESS` and the `RAMP_*` banner beside
  it), and the city splitter
  (`split_city_boxes_on_chunk_grid` / `_is_axis_aligned_basis` / `_chunk_grid_spans`).
  `endless_terrain.gd` keeps a one-line forwarder for `create_box` and
  `_build_block_multimesh` and nothing else — the 600-odd `terrain.create_box(` call sites
  and `landmark_builders`' contract are what those two buy; every other caller (the city
  streamer, `budapest_selfcheck`) reaches `ChunkBatch` directly. **New batch machinery
  lands there, not in the world engine.**
- **A BOX HAS A MESH KIND, AND EVERY UNIT MESH FITS THE UNIT CUBE** (bead
  `godot-test1-y1o.1`, epic `y1o` "get rid of blocks"). The batch entry is
  `{transform, color, kind}` — `ChunkBatch.BoxKind` (CUBE / SPHERE / CONE / CYLINDER), a
  trailing optional on `create_box` defaulting to CUBE, **always written** so the entry
  shape stays uniform (the whole-dict `var_to_bytes` signatures both `prop_selfcheck` and
  `budapest_selfcheck` compare would otherwise differ between two runs that agree about
  every box). Three rules, all pinned by `batch_selfcheck`:
  **every unit mesh is inscribed in the unit cube** (`ChunkBatch.unit_mesh`, radius 0.5 /
  height 1.0, lazy and shared like the cube), which is what keeps `dimensions` meaning the
  entry's BOUNDING BOX for every kind — and therefore keeps `prop_selfcheck`'s cube-corner
  reach helpers and `landmark_selfcheck`'s extent helpers valid upper bounds with no edit,
  and `world_block.gdshader`'s model-space -0.5..+0.5 gradient meaningful;
  **collision FOLLOWS the kind** (bead `godot-test1-y1o.10`) — `ChunkBatch.collision_shape_for`
  is the one home of the mapping: a near-round SPHERE hangs a `SphereShape3D`, a near-round
  CYLINDER a `CylinderShape3D` (radius = the smallest half-extent, so the collider is
  INSCRIBED in `dimensions` exactly like the mesh; the cylinder's axis is local Y, where
  `CylinderMesh` puts it, never "the long axis"), and a CONE plus anything squashed past
  `ROUND_COLLIDER_MAX_ASPECT` (1.6 — no `SphereShape3D` is an ellipsoid) keeps the bounding
  box. The shape COUNT is untouched, which every collision budget in the suite rests on.
  **The CONE is the one kind still wrong on purpose** (Godot has no cone primitive), so
  nothing a player can reach may be a colliding cone — `landmark_selfcheck` check 9c; and
  **`_build_block_multimesh` emits one `MultiMeshInstance3D` per kind PRESENT** — a
  cube-only chunk builds exactly the one node it always
  did, still named `BlockMultiMesh`, and every bucket shares the one
  `_get_shared_block_material` and the chunk's `cast_shadows` flag. That per-kind split is
  the ONLY sanctioned multiplication of a chunk's MultiMeshInstance3Ds. **Budapest stays
  pure cube** — no city builder passes a kind, and `budapest_selfcheck` asserts a built
  city chunk has exactly one MultiMeshInstance3D, which is the after-the-fact half its
  pre-build sweep cannot see. The city splitter **carries `kind` and leaves a non-CUBE
  entry whole**: a cut cone is not two cones. Choosing a kind costs **no RNG draw**, so it
  can never move a spawn.
  **THE FOREST IS THE FIRST CONSUMER AND SO FAR THE ONLY ONE** (bead
  `godot-test1-y1o.2`): every tree's 2-3 canopy layers are `BoxKind.SPHERE` blobs
  (`TREE_CANOPY_BLOB_HEIGHT` / `_OVERLAP`, both DERIVED from the width the layer
  already drew — so not one RNG draw moved and the biome stream is byte-identical),
  the trunk stays a `CUBE` because it is the one COLLIDING box in a tree, and a
  forest chunk therefore costs **+1 draw call and nothing else in the world costs
  anything**. `batch_selfcheck` check 5 bills that per biome off the `Biome` enum;
  `prop_selfcheck` check 10 asserts the two kinds tree by tree. **A new consumer is a
  named bead judged BY EYE by the owner** — the epic's rule — plus whatever that
  check-5 bill has to become.
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
- **Scarcity, and it is ONE RULE FOR EVERY BIOME.** Outside the union of Budapest rect and
  HQ-to-gate corridor, objects thin logarithmically to plain terrain at 4 km in three forms
  and no fourth: a rarity roll compared against `chance * scarcity_at(centre)`, a count
  target multiplied by `roundi(target * k)`, and a per-object post-draw `continue` on
  `_scarcity_keep()` — the one home of the `SCARCITY_SALT` hash stream, whose per-family
  index offsets are part of the world. Never a new draw. **EVERY content builder reads k**
  (bead `godot-test1-bn8` — it shipped as a per-family edit and oases, dunes, cacti and
  mammoths never got theirs); the mountain MASSIF is the single exemption (owner ruling
  2026-09-04: it is the impassable wall, not decoration); predators, hunters, bosses
  and road coins are **never** thinned, because fewer predators far out would reward
  leaving; and GEO LANDMARKS are outside the gradient entirely since bead
  `godot-test1-bcf` — one site per kind in the whole world is not a population, so
  there is nothing to thin (see the next bullet). There are no off-road chunk coins —
  every non-road coin rides an artifact, camp, chest or landmark and vanishes with it. `scarcity_selfcheck` iterates the `Biome` enum
  over a near and a far field, so a builder that forgets k fails the build.
- **A GEO LANDMARK KIND EXISTS EXACTLY ONCE IN A WORLD, and the placement is INVERTED**
  (owner ruling 2026-09-04, bead `godot-test1-bcf`: *"for landmarks they should be
  unique, each type exists once in our world"*). There is no rarity roll and no
  `LANDMARK_CHANCE` any more: `landmark_sites()` gives every `LandmarkBuilders.LANDMARKS`
  row ONE site — a chunk coordinate, pure in `run_seed`, built once per run and **dropped in
  `set_run_seed()`, the one place the seed is written** (a memo that outlived a re-seed would
  hand a multiplayer joiner the master's road with the LAST run's landmarks on it;
  `new_run()` clears it again beside the road station cache it is derived from) — and
  `_landmark_at` is a reverse lookup in that table. So the chunk stream sees **not one draw and not one hash**,
  and a site is answerable for a chunk that has never streamed in. Sites are strung along
  the MUSEUM MILE (the road from the HQ to the terminal station `T`, one kind per
  `LANDMARK_MILE_SPACING` of X, 60-120 m off alternating sides) with the overflow in a
  0.5-2.5 km annulus off the same centreline; illegal sites (HQ disc, Budapest rect, spawn
  bubble, river, a chunk already taken) are resolved by deterministic re-hash, never a
  draw. **Budapest's `CITY_LANDMARKS` are untouched** — 22 authored slots, a separate table
  the field placement cannot reach. `landmark_sites_selfcheck` pins all of it.
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

**BUDAPEST IS AUTHORED TOO, AND THAT IS WHY IT IS NOT A SECOND EXCEPTION.** The city
(`scripts/budapest_plan.gd`, epic `godot-test1-8gw`) is the tower's *authorship* model
with the tower's *lifetime* model deliberately refused: one `const` plan in the
`tower_plans.gd` idiom — no `run_seed`, no `randf`, no `hash(` anywhere in the file, and
`budapest_selfcheck` check 1 reads it as TEXT to keep it that way — but every cell of it
is streamed by `create_chunk` through `create_box()` / `block_batch` / the chunk's single
`BlockCollision`, **chunk-parented and therefore freed by chunk unloading like any prop**.
The arithmetic is the whole argument: the 2.2 x 2.2 km city is 2,025 chunk cells against the web
build's 49-chunk residency, so a manager-parented shell would hold the entire city in
memory forever. The tower stays the one lifetime exception precisely *because* the city is
not one. `in_budapest()` is the single home of the membership test on this side, the way
`tower_excludes()` is the tower's, and it delegates to `BudapestPlan.contains()` so the
rect is never written down twice. Parity is the same contract one clause wider — forced
CITY ground, the authored Danube band and the dry cutouts (bridge decks, Margaret Island)
live in `biome_at`/`is_river_at` **and** `ground.gdshader`, edited together (`_biome_noise`
itself is untouched — the city is an OVERRIDE above the field, not a change to it).

Three rules of the city's own, all pinned by `budapest_selfcheck` (the plan and the
streaming contract) and `budapest_city_selfcheck` (the city the chunks build) —
one 4,100-line file until bd `godot-test1-ftn.13` split it by check family:

- **A landmark bigger than a chunk is SLICED, not re-homed.** The Parliament is 268 m
  long; the chunk that "owns" it has unloaded by the time you reach its far end. So every
  chunk whose square meets a slot's disc runs that slot's builder into a scratch batch /
  body / node and keeps only the boxes whose CENTRE lands in its own square (half-open on
  both axes, so a seam-straddling box lands in exactly one chunk — never doubled, never
  missing). **The centre rule slices a LANDMARK, not a BOX**, and these builders emit
  single boxes far bigger than a chunk (Buda Castle's terrace is 70 x 300 m), so every
  oversized axis-aligned box is first cut on the world chunk grid by
  `ChunkBatch.split_city_boxes_on_chunk_grid()` — without it a 300 m palace lives in one 50 m chunk
  and vanishes at the web build's 150 m residency edge while you walk its far end. A
  ROTATED box cannot be cut into boxes and keeps the centre rule; `budapest_selfcheck`
  check 5 fails any box, turned or not, bigger than a chunk. **The splitter cuts the MESH
  and the COLLISION BODY on ONE shared predicate** (`ChunkBatch._is_axis_aligned_basis`): `create_box`
  hands the two halves different bases for the same box — the batch entry carries the
  dimensions, the shape node only the rotation — so a second spelling of "axis-aligned"
  is how they drift into a drawn wall whose collision lives in another chunk. Check 5
  tallies both halves. It is nearly free because `landmark_builders.gd`'s builders are pure functions
  of (centre, rng) whose stream touches **colour only**. **The seed is the SLOT INDEX and
  nothing else** — no `run_seed` (the city is authored) and above all no chunk coordinate,
  or the building comes out tie-dyed along its seams. The two rejected answers are recorded
  in `_spawn_city_landmarks_in_chunk`'s docstring: manager-parenting the giants (a dozen
  more lifetime exceptions) and a wider residency radius for city chunks (spending the
  exact budget the decision protects).
- **A BRIDGE IS TWO FILES, and `BudapestPlan.BRIDGES` is the joint.** The pylons, towers,
  chains, trusses and lions are `landmark_builders.gd`'s, on the `SLOTS` row of the id;
  the DECK — a level slab at `BRIDGE_DECK_TOP` (12 m, where every builder's ornament
  stops) plus one ramped approach at each end — is `endless_terrain.gd`'s
  `spawn_city_bridges_in_chunk`, built off the row's `DRY_RECTS` entry so **the rect the
  band is punched out by and the rect the stone stands on are one number**. Both ramps
  live INSIDE that rect, which is why the approach needed no new dry row and **no shader
  edit**: a deck rect overhangs the 240 m band by 21–41 m, so a ramp's foot is on the bank
  and its head reaches out over the water. No jump gates outdoors either — the approach
  shares the plateaus' `_city_ramp_slice` and is held to `TowerInterior.PLAN_RAMP_MAX_SLOPE`.
  **Margaret Island is the same mechanism**, one `DRY_RECTS` row, no machinery of its own.
  Known and documented: `DRY_RECTS` is XZ-only, so the river bed *under* a deck is dry too.
- **The road's CONSUMERS stop at the terminal station `T`; the road itself does not.**
  `_road_terminal_k()` is the last station at or west of `ROAD_TERMINAL_X`, and the caps
  are numbered in the code: road coins, road clearance, road bosses
  (`endless_terrain.gd`) and the minimap's drawn line (`minimap_hud.gd`) are 1–4;
  CAP 5 is FIELD BRIDGES and CAP 6 is `_alt_road_segments`, the `FIELD_ALTITUDE` spike's
  flat corridor, which is inert while the flag is false.
  **`_road_extend_to_x` is deliberately NOT capped** — it is the station cache, and a cache
  that stops growing hangs every forward loop that walks it until it passes an X. From `T`
  the player is carried on by `spawn_approach_coins_in_chunk`, a deterministic corridor
  (`BudapestPlan.road_approach_point()`) from `T` through the gate to the Danube's west
  bank: the one seam where the seeded road meets the authored city.
- **EVERY BLOCK OF THE GRID IS FILLED, and the grid is arithmetic rather than a table.**
  Owner, verbatim: *"budapest seems really empty, but it is full of multi story
  buildings in fact, make it so, make it like what we can see on google map walking
  mode"*. So `STREET_PITCH` (62 m) stopped being a parameter and became the city:
  cell `(k, m)` is the square between four street lines, `block_rect()` insets it by
  `AVENUE_HALF_WIDTH` **plus `BLOCK_PAVEMENT`**, and `block_buildable()` is the one
  predicate that refuses a cell meeting a landmark disc, a plateau or its ramp, the
  gate district, a `DRY_RECTS` row or the Danube's band. 805 of 1,296 cells fill.
  Each is a RING of four wings around a HOLLOW COURTYARD — never a solid cube — with
  Pest 4-6 storeys and Buda 2-3, picked off `is_buda()` against the river's own
  polyline. **The streets are clear BY CONSTRUCTION**: nothing is ever drawn outside
  `block_rect`, which is the whole of "a solid piece must never sever a street", and
  `budapest_city_selfcheck` check 15 sweeps the collision shapes anyway because a
  construction argument fails silently.
- **A FACADE IS BANDS, NEVER A BOX PER WINDOW, and `_city_band` is the whole
  vocabulary.** One colliding hull, then ONE window course per storey (proud, glass
  tone alternating by storey parity), two shopfronts with the doorway gap between
  them, an awning, an optional balcony and the roofline cornice — ~10 boxes for a
  5-storey building against the ~30 a window grid would cost. **Every proud is
  POSITIVE**: the batch is opaque boxes with no cutouts, so a band recessed into the
  hull is invisible and produces nothing but z-fighting — that was measured the
  expensive way and `CITY_WINDOW_PROUD` carries the note. Hues are per-BUILDING off
  the bank's own palette (`CITY_FACADE_PEST` cream/ochre/grey-green/rose/stone,
  `CITY_FACADE_BUDA` whitewash/ochre/brick red), tinted but never re-chosen, because
  eight lerps along one ramp is one building repeated eight times. All of it comes off
  a per-cell `CITY_BLOCK_SALT` stream (the tower-furniture precedent: a fixed salt,
  never `run_seed`, and never the chunk, because a block is sliced by up to four of
  them and they must agree), and **every parameter for the whole block is drawn BEFORE
  the first box is emitted**, which is what makes that agreement bit-exact.
- **The bands are what raised the budgets, and the two were raised TOGETHER** —
  `CITY_CHUNK_BOX_BUDGET` 120 → 200 against a measured worst 145, and check 4's
  `CITY_RESIDENCY_BOX_BUDGET` 3000 → 6000 against a measured 4,510 in the worst
  49-chunk web window. Collision did not move (15 shapes worst) because a building's
  only colliding box is its hull. That pairing is the bead's own instruction: a
  per-chunk ceiling raised alone would hide a cost that had moved into the number of
  chunks, which is exactly what the **web residency** window exists to see —
  Budapest went from 378 chunks with stone to 1,631.
- **BUDAPEST CHUNKS CAST NO SHADOW, and that is an OWNER RULING** (2026-09-02, bead
  `godot-test1-8gw.9`, verbatim: *"it's okay without shadow, performance is more
  important"*). 2,100+ tall casters in the 49-chunk web view cost **19 ms a frame in
  the shadow pass alone** — none of it visible in the draw-call count the box budgets
  guard — so `ChunkBatch._build_block_multimesh`'s `cast_shadows` flag makes a city chunk's batch
  a shadow RECEIVER only, the tower interior's measured rule met outdoors. It is the
  WHOLE chunk, so a landmark loses its cast shadow with the blocks around it; the
  chunk has ONE batch and splitting it is a second draw call per chunk, which is the
  invariant check 4 defends. **Do not split the batch to restore them** — that needs a
  new ruling.
- **THE CITY'S COINS RIDE THE AVENUES AND EVERY BRIDGE, AND THEY ARE RARE.**
  `spawn_city_coins_in_chunk`, zero RNG like its `spawn_approach_coins_in_chunk`
  sibling: every fourth grid line is an avenue (`CITY_AVENUE_EVERY`), coins step
  along it at `CITY_STREET_COIN_SPACING`, gems stand where two GEM avenues cross
  (`CITY_GEM_AVENUE_EVERY`, every eighth line — pure grid parity, no hash), and each
  bridge carries its own line at `bridge_surface_y`. **The street pitch is 64 m and is
  NOT the corridor's 8 m** (owner ruling 2026-09-04, bead `godot-test1-1qm`: *"coins
  should be really rare in Budapest"* — 4,133 coins in the rect became 527, a DESIGN
  change to entity counts, which is the one reason the performance conventions allow
  them to move). The two pitches are two constants because the approach corridor is a
  GUIDE and has to read as a continuous trail; it is untouched. Check 15 holds the
  walked avenue and every deck to a floor AND a **ceiling** derived from the constant
  (it is `budapest_city_selfcheck`'s since bd `godot-test1-ftn.13`),
  and asserts the constant itself against `CITY_STREET_COIN_MIN_PITCH` — a derived
  expectation would otherwise follow a one-character revert back down in silence.
  Three rules and each is a bug avoided: no coin west of
  `_approach_coin_east_end()` on the gate avenue (bead .3's corridor owns that), none
  on a deck rect at ground level (the bridge's own line owns the crossing, 12 m up),
  and the deck line skips `_settle_coin_y` because the perch rule is about the ground
  under a column. Coin identity is still `Coin.id_at(world)`, so **`mp_manager.gd`
  needed no edit**.
- **The spawner policy inside the rect is PER SYSTEM, and it is emphatically not
  `tower_excludes()`.** The tower's disc has one answer for everybody; the city wants a
  different answer per spawner, so each one reads `in_budapest()` and decides for itself:
  procedural props, structures, artifacts, camps, chests, geo landmarks and biome content
  **off**; ordinary chunk crocodiles **off** (the early return sits *above* the seed mix,
  so a city chunk never draws from that stream at all and nothing outside the rect shifts);
  **hunters ON** (GD-SURVEY hunts every band — check 9 carries them as a positive control);
  **Danube crocodiles ON**, on their own salt and their own coordinate primes inside the
  authored band; and coins **authored**, via the approach corridor.
- **THE WIN IS A 22-BIT MASK, AND EIGHTEEN BITS ENDS THE RUN.** Walking within
  `radius + landmark_toast.APPROACH_PAD` of a `BudapestPlan.SLOTS` row sets its bit in
  `player_controller.explored_mask`; `_check_budapest_win()` raises
  `end_run(Outcome.WON)` at `BUDAPEST_WIN_LANDMARKS` (18). Four rules, all pinned by
  `landmark_progress_selfcheck`:
  **it is PER-RUN and add-only** (`restart_game()` empties it beside `captive_heroes`; the
  monotone store gets the COUNT through `submit_landmarks()`, never the set — a walk is
  not earned); **the trigger reads the PLAN, not a group**, because a slot is authored and
  exists whether or not its chunk, its stone or even its builder does — an empty `builder`
  still counts and simply shows no card (`minimap_hud._gather_tower`'s precedent, one
  table along); **the card and the coins are a SECOND, PERSONAL latch** (`landmark_toast`'s
  own `_visited`), so a landmark a teammate explored still pays you when you walk it; and
  **in a room the set is the ROOM's** — the `lmk` claim carries a slot INDEX and nothing
  else, the master range-checks it and asks its own presence table whether the sender was
  within `MAX_LANDMARK_CLAIM_PAD` of that slot, and publishes the union as an **optional**
  `m` on the `room` packet plus an absolute `lm` in the join snapshot. Both are optional
  because `decode_room` may not drop an old master's packet — it is also the captive set's
  repair channel. **The mixed-room ceiling is documented and real**: a pre-.5 master
  advances no union, so eighteen alone still wins and eighteen between two people does not.
  Victory is never evaluated before `_join_settled()`.

`scripts/tower_interior.gd` is the same idea one floor in: a second box table for the
two-storey keep, plus eight hand-planned storeys over it (see below) rising to the CELL
BLOCK under the sealed roof, assembled onto the
shell by
`endless_terrain` (one direction only — the interior reads the shell's constants, so a
shell that knew about the interior would be a cyclic `class_name`). **Two families were
lifted out of it whole** by bd `godot-test1-ftn.12` and neither may drift back:
`scripts/tower_dressing.gd` (`TowerDressing` — the office, corridor and wayfinding
dressers) and `scripts/tower_dossiers.gd` (`TowerDossiers` — the evidence dossiers).
Both are static libraries in `landmark_builders.gd`'s idiom, reaching back into
`TowerInterior` for the plan-grid readers and the palette; that direction is one-way and
`plan_boxes()` is the single seam the dressing enters through. Four rules of its
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
  never chunk-spawned. **AT MOST ONE PER STOREY** (owner ruling 2026-08-30,
  `GUARDS_PER_STOREY_MAX`), because the building is a stealth problem and two on a floor
  turns a room you were meant to time and walk past into a chase; the count is asserted
  off the BODIES in the tree, never off the table. **Losing to one is an ARREST** (owner ruling 2026-09-01, bead
  `godot-test1-3iy.19`, superseding the third stake): to the player the thing that
  grabbed them in the HQ is a hunter — it is the same chassis — so a post-beat
  guard grab imprisons the hero exactly like a field grab, through the `captures_hero`
  ROW KEY the two GD-SURVEY rows share (`behavior` stays `"solo"`: behaviour is
  STEERING, and a sentry must not have the hunt arm's nose or its director seams).
  The `coin_setback` (7%, the lowest in the table) is billed on top —
  one arithmetic everywhere. **The checkpoint knockback is SKIPPED on exactly the
  contacts that arrest**, latched in `hit_by_crocodile()` (`caught_captured`) and
  read in `_pay_coin_setback()`, because the ruling's second half is that the
  surviving heroes carry on from where the party fell. It still catches every other
  way to lose indoors — a PRE-BEAT guard, the press, an animal that
  followed you in — and it is the building's, not the row's
  (`_pay_coin_setback()` relocates whoever bit you, gated on
  `TowerInterior.inside_walls()` — the group ANSWERING is not the test, because the
  shell streams in at 360 m and is never freed again). The arming gate is
  unchanged and is REQUIRED here: the authored Primm rescue is a room in this
  building, so pre-beat a guard is byte-for-byte today's setback-plus-knockback or a
  tutorial visit could strip the roster. An arrest ends a run only by being the
  FOURTH one — the empty free set is the game's one ending, raised where it lands.
  Guards stay in group
  `"crocodile"` (LOD sleep and the MP relay still want them) and refuse the Stink Wave
  and the giant's crush through `stink_immune` / `crush_immune`, never through group
  tricks; `clear_nearby_crocodiles()` exempts them the way it exempts a boss, or any
  death inside the building would clear the floor.
- **AN EMPTY ROSTER IS THE ENDING, IMMEDIATELY — and there is no scene between**
  (owner veto 2026-09-01, bead `godot-test1-ueg`, verbatim: *"i still see this
  recall in 33 after all caught, why? I never asked for this"*). There used to be a
  FULL-CUSTODY BREAK-OUT here — a march to the cell block, raised containment, a
  35 s recall clock, a scene-scoped roster grant. It was an ADOPTED READING layered
  by a planning pass onto the owner's actual ruling (`godot-test1-0bc`, "game over
  ONLY when all four heroes are jailed"); beads `3iy.11` built it and `3iy.21`
  hardened the web build to present it reliably, when the owner wanted the film.
  The fourth capture now calls `BestRunStore.archive_world()` and
  `_trigger_game_over()` on the same frame, in `_on_caught_finished()`'s roster
  clause and in `_tick_prison()`'s first clause. **Do not re-adopt the scene**;
  `capture_selfcheck` check 17 asserts its vocabulary is gone. The PARTIAL-capture
  rescue play is untouched — spine doors, liberation, the benched-peer prison role,
  the vent purge and the block confinement are all the same code they were.
- **A FOURTH HOME, and it is a fourth for one reason.** The SCAR rides the monotone
  opened set like a gate (earned, permanent, no verb heals it — it is only design
  law 3's exception in what the *building* does with the id, never in how it is
  stored). The WORLD ARCHIVE cannot: New Game has to clear it and a union has no
  removal verb, so it is its own `[world] archived` latch in `best_run_store.gd`,
  written by the roster clause directly, read at boot (Continue reopens the ending)
  and cleared by `restart_game()`. **The SCAR IS DORMANT and the row stays anyway**:
  the break-out was its only inflictor, but `custody_stair_collapse` is a PERSISTED
  id in the opened set of every profile that survived one, and retiring a persisted
  id is a save migration nobody ordered — deleting the row would un-draw rubble a
  world earned. `TowerGraph.next_scar()` therefore has no caller today; the row, its
  boxes and both audits stay, and wiring a new inflictor needs an owner ruling.

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
| 2–4 | 3–5 | the phase-14 office storeys (records, accounts, executive) |
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
  is that half; it in turn does not know a `D` is passable, which is the graph's half. Both
  fills refuse to step **sideways off an `S` lane**, which is the one piece of height in a
  flat grid — the deck descends a whole storey along the lane, so only the `s` landing at
  its head is flush with the floor. The
  plan ↔ graph binding is checked **both ways** — every letter is a built room row, every
  room id is claimed by exactly one storey, and every built room is drawn by SOME storey
  bar the keep's own (a room no plan draws has no cells, so the gates-shut pass silently
  skips every edge it carries) — and every assertion has a negative control
  driven on a deliberately broken *copy* of a shipped storey.
  **The floor is then filled a SECOND time with every gate cell treated as stone**, which
  is the only thing that binds a `gate: ""` row to the drawing: an ungated edge between two
  of a storey's rooms must land them in one component (the labyrinth's route A, and what
  makes "the spines walk the ungated circuit" a measurement rather than a claim), and a
  GATED edge whose rooms are in one component anyway must be joined by an ungated path in
  the graph, or the drawing offers a way *round* a door the audit models — which is what a
  hole in the cell block's outer wall is, and neither of check 11's two sampled lines
  crosses that wall since the block became an island in the muster floor.
- **A storey's walls are as tall as ITS OWN clear height** (`plan_clear_height()`), not a
  constant: the top storey is short because the sealed roof is where it is, and a wall
  built to somebody else's height would either poke through that roof or leave a gap you
  can see the next floor through. The gate masses read the same function, so a mass on a
  short storey is a short mass.
- **A gate mass has to have somewhere to GO, and the storey next door is not it.** A mass
  fills its doorway floor to ceiling — that is what makes it a gate and not a hurdle — so
  it leaves its own room the moment it moves. `_retire()` covers the OPEN end of the
  travel; what it cannot cover is a riddle's per-step notch, which is only 0.9 m but
  **stays** (nothing resets `_riddle_step` when you walk away) and the slab is 0.4 m. So a
  RISING gate is drawn under a wall on the storey above, checked by `tower_selfcheck`
  rather than left to luck — three of the four riddles satisfied it by accident and the
  fourth stood in the middle of Teibi's cell.
- **Walls are 2-D run-length merged**, so a 40-cell wall is one box and not forty — which
  matters because each box is also a `CollisionShape3D`, and the collision body is the one
  thing in this building that is not batched. Measured over the eight planned storeys:
  **55 / 43 / 52 / 29 / 29 / 81 / 61 / 46** boxes against `PLAN_BOX_BUDGET` 120 (the two
  maze floors are the 81 and the 61 — a one-cell maze legitimately produces many rects,
  which is what that budget now guards). Mesh NODES are **38 (`DRAW_BUDGET` 38) for 2420
  boxes** — one `FloorNBatch` per storey, the parts that move, the four hero
  portraits and the dossier rack — and the whole interior is **562 collision shapes on
  one `StaticBody3D`** (ceiling 640, printed by check 5). A
  plan whose walls stopped merging blows the box budget on its first row. **`DRAW_BUDGET`
  counts nodes, not draws**: emissive is a material property, so a storey carrying a
  `GLOW_COLORS` box commits a second SURFACE in the same `ArrayMesh` and the engine
  submits one draw per surface. Since Air Sight (bead `godot-test1-oht`) a storey
  batches up to THREE — walls, other matte, emissive — because the walls must be
  swappable on their own, and **`SURFACE_BUDGET` (54, measured at 49) is the bound
  that counts draws**; check 5 asserts both. Read `DRAW_BUDGET` as "nothing left the
  batch", not as a draw count.
- **The EVIDENCE DOSSIERS are the one MultiMesh in the building, and one is the cap.**
  They live in `scripts/tower_dossiers.gd` (`class_name TowerDossiers`, bd
  `godot-test1-ftn.12`), a static library the interior hands itself to; the four state
  vars and the `body_entered` handler stay on the node, and the seams are four lines in
  `tower_interior.gd`.
  Six authored folders (`TowerDossiers.DOSSIERS`, a const table of `{floor, cell, lore}` — floors 2-6
  only, never the labyrinth or the block) pay `DOSSIER_VALUE` coins and a localized line
  on the `landmark_toast` card when you walk into one. A pickup has to vanish on its own,
  which a merged storey batch cannot do, and six meshes would be six SURFACES — so they
  are one `MultiMeshInstance3D` (`DRAW_BUDGET` 37 -> 38, surfaces 48 -> 49, no emissive
  surface), and a taken one is a zero-scaled instance. **Write the rack through
  `multimesh.buffer`, never `set_instance_transform`**: the per-instance setter round-trips
  through the RenderingServer, which is the dummy driver under `--headless`, so every
  self-check reads identity back. State is per-run on the interior (the coin's rule, never
  the monotone opened set); in a room it is `claim_pickup(Coin.id_at(world), 1, value)` and
  the join replay, so `mp_manager.gd` needed **no edit at all**. Two finds are gated and
  neither is new machinery: a one-cell CRAWL ALCOVE off storey 3's west stack under a
  `DOSSIER_CRAWL_CLEAR` lintel (small Teibi only — the alcove's cells stay ordinary floor,
  because a height gate is exactly what the 2-D audits cannot see, and check 20 asserts the
  cell is a DEAD END so the invisible gate closes no route), and one standing in a guard's
  watched stretch, which is pure cell choice and must stay takeable by timing the patrol
  alone.
- **The offices are FURNISHED, and the furniture is derived rather than drawn.** No
  glyph was added to `TowerPlans` for it: `TowerDressing.plan_dressing` walks each storey's rooms
  and puts desks, chairs, cabinets, bookshelves, meeting tables, coolers, plants and
  framed diplomas/photos on the cells that touch a wall, off a FIXED salt (never
  `run_seed` — the tower is authored). It is all vertex-coloured boxes in the storey's
  existing batch, so ten furnished floors cost **zero** extra draw calls; only the four
  hero portraits hanging in the outer hall as "employee of the month" need textures, and
  they are the whole of `DRAW_BUDGET`'s move from 35 to 39 (37 since the rotor
  turnstile came out). Furniture has its own
  per-storey budget (`PLAN_DRESS_BUDGET` 580) so `PLAN_BOX_BUDGET` keeps measuring
  exactly what it always did. **The CORRIDORS are dressed too** (benches and planters,
  `TowerDressing._hall_dressing`), on cells whose four neighbours are all stone or open floor and whose
  hall is two cells wide — never in the labyrinth or the block, and **never solid**, which
  is why the halls need no connectivity fill of their own. **The WAYFINDING PLAQUES ride the same dresser** — one
  per office room, on the bare wall nearest the way out, its arrow pointing along that
  wall at the storey's stair lane, and never in the labyrinth or the block. They are the
  HORIZONTAL half of the jail hint (the minimap's indoor line is the vertical half): a
  live bearing arrow would rank the corridors at every junction and quietly solve the
  maze, so the horizontal help is authored, coarse and in the world. **Three rules keep it safe and check 18 asserts all
  three**: nothing lands on a doorway cell or beside one; a solid piece is committed only
  if the room's connectivity is unchanged (`TowerDressing._still_connected`); and a cell carrying
  anything else the storey draws — a pad, a lock plate, a set piece — or standing under
  the storey above's stairwell hole is refused. Only waist-high-or-taller pieces collide.
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
- **`G` posts ARE the population** — one per storey, read by `TowerInterior`'s
  `guard_posts_table()`, so where a guard stands is a character in a grid and not a
  Vector3 in a table. **`P` pads are the LURE** (bead `godot-test1-3iy.22`): step on one
  and that storey's guard walks over at patrol pace, faces it for `LURE_HOLD_SECONDS`,
  then walks back — a flag state (`investigate_point()`) beside `is_tracking` and **no
  behaviour arm**, so the row stays `"solo"`. Every anti-puppet rule (busy refuses,
  acquisition cancels, the plate's own cooldown) lives in that one shared function
  because a master-routed `pad` verb is the second way in. **The guard walks CORNERS
  the interior hands it** (`TowerInterior.plan_route()`, a BFS of the floor plan that
  refuses stone, the ramp deck and every `D`): exactly one of the building's eighteen
  (post, plate) pairs has a clear straight line, so a lure that steered by bearing
  walked seventeen guards into a wall. The AI is handed points and knows nothing about
  `TowerPlans`. The leash is GROWN toward the waypoint being walked and handed back at
  the post; an acquisition takes the growth back around the body on the spot, so a
  chase is still fought over a beat-sized patch.
- **THE SERVICE LIFT IS A MENU AND NO GEOMETRY, and a stop is a GRAPH ROW**
  (`scripts/tower_lift_menu.gd`, bead `godot-test1-3iy.7`). `L` at the ground
  floor's `s` landing lists the stops you have earned and a digit rides you to
  that storey's landing. Nothing about it is authored here: a stop is an entry
  some MUTATION grants (`TowerGraph.lift_stops()`), it is unlocked when its
  row's `unlock` id is in the shell's monotone opened set — the maze stop's own
  id, written by `LiftStopTrigger`; the checkpoint's, for the upper one — and it
  lands on the storey whose plan claims its room as the `landing`. So a third
  stop is a `TOWER_GRAPH` row and no code, and the ride needs no reachability
  argument of its own: `tower_selfcheck` already walks all fifteen subsets FROM
  every entry a mutation can grant. **It is ONE WAY (up, from the ground floor)
  and draws no car**, both `ponytail:` in that file. The refusals are
  `city_map_panel`'s — in a room, over game over, and mid-bite — and the pause
  is `PauseHub`'s; `tower_lift_selfcheck` drives all of them on a real shell.

`scripts/tower_graph.gd` is the tower's TOPOLOGY as one const dict of plain dicts —
rooms, gated passages, entries, the mutation table, the enumerated scar states, the four
rescue spines. Pure data, depended on by nobody (so no cycle): the interior takes its
gate ids and its identity-gate heroes from it, and `tower_selfcheck` walks it to prove
the campaign cannot softlock. Its three design laws are what make that audit tractable —
**spines at floor rank, no item custody, mutations may only ADD edges** (the authored
scar being the one owner-sanctioned exception, dormant since the break-out's veto) — and the check asserts all three
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

**WADING IS Y-AWARE; THE BAND IS NOT** (bead `godot-test1-06o.2`). `is_river_at()` stays
XZ-only — it is the band the shader paints, and the parity contract above is about it.
Whether a *body* is in the water is the narrower question `is_wading_at(pos)` answers:
`pos.y < WADE_SURFACE_MAX` (0.6 m) **and** `is_river_at`. That rule has ONE home and
three callers — the player's `is_wading`, the remote avatar's sink, the crocodile's
`_tick_river_sink` (plus the minimap's "in a river" readout) — because a fourth caller
would be a fourth chance to forget the height. It needs **no shader edit**: the water is
still painted under a bridge, which is correct.

**It does NOT close Budapest's "walk the river bed under a deck" gap, and the reason is one
layer down**: inside the rect `is_river_at` delegates to `BudapestPlan.danube_wet()`, which
already subtracts every `DRY_RECTS` row — so the bed under the four authored decks answers
DRY before the height rule is ever asked, for players, avatars, crocodiles and the map
alike. Closing it means asking the band WITHOUT the cutout on the low-Y path, and the
cutout is shared with MARGARET ISLAND, which is dry LAND at y = 0 and must stay dry — so it
is a bridge-rects-only exception, a Budapest behaviour change, and bead
`godot-test1-06o.3`'s to make with the not-walkable ruling in hand.

**THE ROAD CROSSES A RIVER ON A BRIDGE, and that is what keeps a run crossable** when
bead `godot-test1-06o.3` makes a channel not walkable. `spawn_field_bridges_in_chunk`
builds one low stone footbridge per road river crossing — the anchor is the station that
ENTERS the water (wet here, dry behind), so "one bridge per crossing" is a definition and
not a de-duplication pass; the span walks forward to the far bank and refuses past
`FIELD_BRIDGE_MAX_SPAN` (a lake, which wades and is 06o.3's problem). Five rules:
**zero RNG** (the site is the road's centreline plus the river field, both pure; the boxes
come off a private fixed-seed stream), so the A/B proves every other spawner is
byte-identical; **no `obstacles` footprint** — a bridge is meant to be walked, and a
footprint would push crocodiles off the road and make `_settle_coin_y` skip the deck's
coins; **the CENTRE rule, not rect slicing**, because the deck is a chain of ROTATED slabs
following the curving road (an axis-aligned deck would have to be widened by the lateral
drift, which at the 78° heading cap is a 190 m slab) — safe here only because every piece
is far smaller than a chunk, which the check asserts; **the ramps read
`BudapestPlan`'s own deck slope and are held to `TowerInterior.PLAN_RAMP_MAX_SLOPE`**, and
a slab may only be stretched at a deck-to-deck joint — stretching one over a ramp head
makes a STEP, which `CharacterBody3D` cannot climb at all; and **road coins on a deck ride
it** (`_settle_coin_y` still runs first, unlike the city's deck line, because a road boss
stands on a river crossing and its footprint must still refuse a coin outright).

**A DECK IS A FLOOR FOR BODIES TOO** — `field_bridge_stand_y()`. Every spawner drops a body
at a ground height and lets gravity settle it, so one placed at 0.6 m under a 1.6 m deck
can neither fall onto it nor climb out; a boss whose station is a river station has almost
all its candidate spots inside the deck by construction. It is a LIFT, not a refusal:
refusing the spot deleted every RIVER boss in the world, which is the one path that
dispatches the crocodile — `enemy_spawn_selfcheck` check 11's non-vacuity assertion is what
caught that, one round after the refusal shipped.

**AND THE CORRIDOR IS BRIDGED TOO.** The road's consumers stop at `T`; the player does
not. `approach_bridges()` samples `BudapestPlan.road_approach_point()` from `T` to the
Danube's west bank **at `FIELD_BRIDGE_PROBE_STEP`, not at the road's pitch** (a station is
~6 m of X and a band can be narrower — seed 63's fell between two samples), decimates the
deck back to that pitch so the stone is the same shape, and continues the line WEST along
the road's stations (resampled to the same metre pitch) whenever the ROAD SIDE REFUSES —
that refusal, `k1 + DRY > T`, is the trigger, not a probe of the corridor's own first
sample, because west of `T` the corridor is a POINT and its perpendicular is not the road's
(seeds 115, 203, 224 are three shapes of the same handoff). One owner, one deck. It walks the same crossing rule as the stations,
because the city's river override only starts at the rect's west edge — so the procedural
river is alive under the authored corridor, and on seed 4 it crosses one at x ≈ 1495 with
nothing over it. Same decks, same `_field_bridge_row_from()`, and the approach coin line
rides them like the road's — **behind the same `spawn_field_bridges` flag**, because
`field_bridge_surface_y` answers off the plan, which exists whether or not the builder ran.

Four of those rules were WRONG ONCE, and the corrections are the interesting part.
**`_field_bridge_slabs()` is the single description of the stone** — the builder that emits
it and the surface query that answers "can I stand here" both read it, because they
disagreed: the query was a point-to-POLYLINE distance, i.e. a CAPSULE, and at a joint on
the outside of a turn it accepted points no rectangle covered, so a road coin stood at deck
height over open air. **The span cap counts metres WALKED**, never the chord back to the
entry station, which a curved wet run makes shorter than the road really is — **and it
counts them on the CENTRELINE**, which is where the hero is. Measuring the span on the
16 m section instead made a road that merely runs ALONGSIDE a river (seed 218 grazes one
within 8 m for 186 m) into a "lake" and left two real crossings unbridged. The section
keeps exactly one job: **where a RAMP may stand**. `_field_bridge_dry_across()` is its one
home and `_field_bridge_ramp_dry()` is the shape it is asked in — the whole rectangle from
the deck's end to the foot, because three lanes passed a foot with a wet patch half a metre
inside one edge and the ramp's SIDES were wet on six seeds while its centre was dry, and a
ramp is under `WADE_SURFACE_MAX` for its first 2.4 m. When no dry ramp is reachable the
DECK CARRIES ON at deck height along the bank (`FIELD_BRIDGE_BANK_WALK_MAX`) rather than
dragging one through the water, and only when even that fails is the crossing refused (the
lake rule), never given a known-wet foot.

**THE SPAN CAP IS WET METRES, AND THE WINDOW SCAN IS THE FEATURE'S PERF BUDGET.** The cap
adds up the water each station OWNS (`_field_bridge_wet_metres`, memoized — the hot read of
the whole feature), never the distances between wet station centres, which drops the entry
station's share and both partial intervals at the banks and bridged a 124.5 m crossing as
if it were 120.0. And `_field_bridge_reach()` pads a scan by how far stone reaches from its
anchor IN ONE DIRECTION: doubling the bank walk and the ramp in it made the window 2.9 km
wide and the first cold query of a run **33 ms**, one whole frame-spike budget, walking
1,200 stations whose decks could never touch the chunk being built. One-sided, plus the
memo and a 300 m bank walk, it is **8-10 ms cold and 0.1 ms warm**.

**THE GROWTH MAY NOT READ THE STATION CACHE'S EDGE, and ONE ANCHOR OWNS A DECK.** Both are
determinism, and both were wrong once. The growth is memoized, so a loop that stopped at
whatever the cache happened to hold made the bridge SET a function of the order chunks were
visited — six decks walking east, five walking west, and two peers in a room laying
different stone over the same water; it extends the cache to its own budget first now, and
`field_bridge_selfcheck` check 6b drives every subject seed both ways. And two crossings
that grow onto the same bank produce the same deck under two anchors, which every chunk
then emits TWICE: the WESTERN entry owns a merged deck and the later anchor builds nothing,
with the corridor skipping any crossing the road already decked (`_road_bridges_near` is
split out for exactly that question, so the ownership test can never recurse).
Finally **the slab stretch at a joint is DERIVED, `half * tan(turn / 2)`**: the road's
recurrence restores the heading toward +X as well as turning it, so a station can turn
further than `road_turn_rate_deg` alone allows (22.4° measured), and a fixed stretch left a
wedge of open air at the outer parapet.
**There is a SPIKE behind `FIELD_ALTITUDE` (`endless_terrain.gd`) and it ships `false`.**
Bead `godot-test1-ope.1` built a vertex-displaced heightfield with the parity contract one
clause wider (`height_at()` / `field_height()`), Budapest, the HQ disc, every river band
and the coin road corridor held at y = 0, and a `HeightMapShape3D` ground shape — all of it
inert with the flag false and `alt_enabled = 0.0`, which is byte for byte the flat world
above. **The flat world is still what ships**; the measurement, the red-check list and the
migration order of the consumer list live in `docs/field-altitude-spike.md`, and the epic's
consumer beads are filed from that report.

### Player
`scripts/player_controller.gd` (a `CharacterBody3D`). Character switching on R (`switch_character`) cycles
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

**INSIDE THE HQ TWO OF THEM CHANGE, and both read the shell's own `sheltered()`** — the
predicate that already keeps the rain off, never a restated envelope. Windman's F becomes
**Air Sight** (`TowerInterior.set_xray()`: the storey's WALLS go translucent for 7 s so a
patrol can be watched through them — floors, ceilings and gate set pieces stay opaque),
because Air Rush under a 4.6 m ceiling was a press that did nothing; the take-off gates
(`RAIN` / `LAND`) do not apply to it. Teibi's growth is **refused everywhere sheltered**
(reason `INDOOR`, above `TIGHT`, owner ruling `godot-test1-xdf`) and a giant walking
through the door **auto-reverts at the threshold**, so the state cannot exist inside; SMALL
stays allowed. **The FORM TIMER's revert waits for room** (`_teibi_fit_blocked(1.0)`,
retried at `TEIBI_REVERT_RETRY`) — inflating a 2 m capsule inside stone is
`_teibi_grow_blocked`'s bug in reverse, and the HQ's 1.2 m crawl alcove is the first space
in this game a normal body does not fit in. The FORCED reverts (character switch, respawn,
the no-giant-indoors threshold) stay unconditional: those are not the body's call. Air Sight is the one transient ability state that lives in another node's
MATERIALS rather than in a float here, so it is cleared on the switch, on the respawn AND
on the way out of the door — `capture_selfcheck` drives all three exits.

`scripts/ability_effect.gd` is the self-building, self-freeing expanding sphere.
`scripts/ability_hud.gd` reads the player's contract methods for the cooldown dial.

### Crocodiles
`scripts/piglet_crocodile_ai.gd` + `scenes/characters/piglet_crocodile.tscn` is the enemy
the terrain spawns. It wanders, chases within its detection radius, and calls
`player.hit_by_crocodile()`. Crocodiles are solid to one another (`collision_mask = 3`);
the player stays mask 1 and passes through, so damage is decided entirely by the
crocodile's own collision handling.

**Species are data, not subclasses.** Every trait that makes one predator feel different —
speeds, detection, wander rhythm, obstacle feelers, waddle/bite geometry, river sink, and
the `coin_setback` bill losing to it costs — is a
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
no probe in **`enemy_behavior_selfcheck`** measures. **It iterates `SPECIES`,
`BIOME_SPECIES` and the `Biome` enum, never a list of its own** — so a new predator is
covered the day its row lands, and a new behaviour arm has to bring a probe with it.
Keep it that way.

**A cone is DETECTION, so it is data and it lives above the dispatch.** `view_cone_deg`
is an optional row field defaulting to 360 — the tower guard's 120 is the only one — read
once in `_ready()` into a cosine and applied in `_update_chase_state()` on the
**acquisition edge only** (a predator that has you keeps you until distance drops it),
after a game-wide `SPOT_TELEGRAPH_TIME` beat that shows a `?` and pings. **The beat is a
STANDSTILL** — the heading is zeroed last in `_physics_process`, over the wander, the
feelers and both leashes, because a body that walks through its own warning turns as it
goes and rolls the quarry back out of its own cone. And a bearing test is blind to height,
so a cone also carries `VIEW_CONE_HEIGHT_BAND`: without it a guard smells the player
through the floor slab above it. It costs no RNG draw, so adding it to a row moves no
spawn. `enemy_behavior_selfcheck` check 8e probes every
row that carries the field, from behind and ahead, with the crocodile as the no-cone
control.

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
able to stroll away from. The exemption is paid for, not free: `enemy_behavior_selfcheck`'s ranged probe
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

**THE FIELD IS CAPPED AT TEN, AND THE CAP IS TWO HALVES** (owner ruling 2026-09-02, bead
`godot-test1-fhu`: *"limit hunters on field with total number 10 (inside HQ doesn't
count)"*). The half that does the work is `HUNTER_CHANCE` (0.08), tuned so the EXPECTED
desktop residency — `(2 * render_distance + 1)^2` = 121 chunks — is 9.68 bodies; that half
is a pure function of (chunk, `run_seed`), so it holds in a room and on every peer.
`HUNTER_FIELD_CAP` (10) is the backstop for the lucky walk, and it is deliberately *not*
deterministic: it is a **post-draw skip** at the bottom of `spawn_hunters_in_chunk`,
counting live bodies of the row that are **not descendants of `tower_shell()`** (the HQ's
guards are excluded BY PARENT, never by group), and it is **off in a room** — a body count
differs per peer by where they walked, and crocodiles are master-simulated but never
network-spawned, so a hunter one peer capped away and the master did not is a local ghost
that can still bite. **In a room the retuned chance IS the whole cap**; that ceiling is
documented, not a bug. `enemy_spawn_selfcheck` check 13 pins all five clauses.

**It is also the row that proved player abilities can be opted out of as DATA.** By
owner ruling 2026-09-04 (bead `godot-test1-bvh`), the hunter's stink exemption is
reversed — gameplay beats fiction, so Phoboman's Stink Wave scares hunter robots away
like any ordinary predator. Its row retains `crush_immune` (a machine is not flesh, so
giant Teibi's squash block is skipped and the body takes the ordinary bite path), and
adds `fears_giant_radius` (14 m; owner ruling 2026-09-04, bead `godot-test1-upu`: giant Teibi
scares hunters away instead of crushing them). These are `spec.get(key, default)` reads
placed beside the existing `is_boss` guards — never a species-name test — so the next
armoured or airtight predator opts in with a row edit and no code change. `boss_selfcheck`
check 8 drives **every** row through both real paths and giant fear, which makes the animal
rows the negative control and anchors the crocodile by name against a stray key.

**The tower guard is the FOURTH door, and it is not in `endless_terrain` at all.** It is
placed on a post by `TowerInterior` (`GUARD_SPECIES` / `GUARD_SCENE` /
`GUARD_POSTS`, the keep's two hand rows, plus one derived per plan storey — see
`guard_posts_table()`), so check 4's reachability gate reads those consts too — a union over the
dispatch maps and the hunter spawner alone reports a shipped predator as unspawnable.
**It adds no behaviour arm**: "patrols its floor and never leaves it" is the existing
`set_confinement()` leash the elevated-platform guards already use, so the row is
`behavior: "solo"` and the patrol is geometry. Its `coin_setback` key is the same
required row key every predator carries, and it keeps BOTH `stink_immune` and `crush_immune`
(with no `fears_giant_radius`) AND its `captures_hero` — see the tower section above for
why each is a design decision and not an inheritance.

**The hunt arm has a SECOND LEG: scent tracking, and it is steering, not detection.**
Out of detection a row carrying `scent_radius` (150 m, the hunter alone) asks the LOD
manager for the freshest crumb of the nearest quarry's trail within that radius and walks
it — `is_tracking` / `track_target`, a third branch beside chase and wander in
`_physics_process`. It sets `is_chasing` for nobody, touches `detection_radius` for
nobody, and travels at the row's OWN `chase_speed`, which `_ready()` has already clamped
to `MAX_CHASE_SPEED` — so walking (5.0) lets a tracker arrive, which IS the pressure the
owner asked for, and running (9.0) still leaves it behind, and no retune of a row can
reach around either. Mercy is still decided at ENGAGEMENT by the director: the nose
brings hunters near you, it does not grant anybody a grab. `enemy_behavior_selfcheck`
check 8f is the acceptance — a walk that must be caught up with and a run that must not,
iterating every row that declares a nose.

**Hunter mercy is tuned BEFORE contact and never by a hunter pulling its punch.**
`scripts/hunt_director.gd` (one node in `main.tscn`, group `"hunt_director"`, modelled on
the LOD manager: group discovery, a 2 Hz tick, a pure decision core) answers the hunt arm's
`_hunt_close_granted()` seam with three pre-contact rules — a pursuer cap, a post-grab /
hard-chase lull, and a guaranteed open escape sector. Its entire output is that bool: it
touches no grab range, collision, speed or detection, and a denied hunter keeps SHADOWING
visibly. Rules are bucketed **per quarry by proximity**, never globally — group `"player"`
is the local player, so a global cap would starve a room. **Absent director = granted**,
which is what keeps the standalone `hunter_robot.tscn` and every headless harness working;
that degrade is debug-only, because hunters are uncrushable and the
open sector (alongside Phoboman's Stink Wave and giant Teibi) is their fairness budget. `grant_engagement` / `escape_sector_open` are
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
caught) by `enemy_behavior_selfcheck` check 8, which probes *every* row carrying the
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

**The scent trail lives here too, and it is why a slept body can now MOVE.** The same
scan that decides who sleeps records a breadcrumb ring buffer for every focus point
(`TRAIL_STEP` 2.5 m, `TRAIL_TTL` 3 min, matched to a quarry by proximity like
`hunt_director`'s buckets), publishes it as `scent_point(from, radius)`, and walks a
SLEEPING hunter one kinematic step along it per tick (`advance_tracking`). Three things
that rule keeps: it is **runtime state outside the determinism contract** — no RNG, no
hash stream, the weather/fauna precedent; the master's `focus_points` already contains
every room member, so "a hunter tracks the nearest room member" costs **zero netcode**;
and the step is kinematic (no physics, no `_physics_process`, no collision), so entity
counts and near-player behaviour are untouched. Only a `SPECIES` row carrying
`scent_radius` is ever asked. **`mp_manager._send_croc_sync` publishes a slept-but-
stalking hunter** — it is the one body that leaves its deterministic spawn state without
waking, so the usual "sleepers cost zero network" skip would pop it into place on wake.

The same scan publishes the nearest chaser's distance to the danger vignette — **two
channels off one scan**, split on the chaser's `behavior`: animals drive the red edge glow
and the heartbeat loop, a GD-SURVEY hunter drives its own cold scanning rim (and no
heartbeat — its audio channel is the lock-on ping). Both are normalised by the chaser's
OWN `detection_radius`, both are published every scan, and the vignette's shader ADDS them
in different radial bands so neither can suppress the other. A second retrieval unit joins
the machine channel with its `SPECIES` row and no edit anywhere.

Hunters are in group `"crocodile"`, so **the \fo overlay's "Crocs (active/total)" counter
means predators + hunters** — which is exactly what the LOD manager manages.

### Systemic capture — a GD-SURVEY machine takes the HERO
A post-beat grab by a predator whose `SPECIES` row carries `captures_hero` puts the
ACTIVE hero in `player_controller`'s `captive_heroes` and steps into the next free
one. **It is a ROW KEY, not the `"hunt"` behaviour** (bead `godot-test1-3iy.19`):
the field's retrieval unit and the HQ's sentry both arrest, and only the first is on
that arm — behaviour is steering, and the guard's patrol is `set_confinement()`.
Four rules:

- **Availability is `hand INTERSECT free`, at ONE site.** `switch_to_next_character()` already
  cycles inside an allowed-index array (the lobby's, in a room); captivity is one more
  intersection there. There is no second roster system, and there may not be one.
- **The auto-switch goes through `set_active_character()`**, never the R-cycle: that is where
  `_reset_ability_states()` lives, and the cycle refuses a press mid-Air-Rush anyway.
- **It arms only after the authored Primm rescue** (`TowerInterior.RESCUE_DONE` in the stored
  tower set) — the beat is where the rule is taught. Before it, a grab is an ordinary bite.
  That gate is load-bearing for the guard, not incidental: the beat happens INSIDE the HQ.
- **The set is NON-MONOTONE** (captures add, liberations remove), so it stays out of
  `best_run_store`'s union/max merge, which the tower's opened-gate ids *do* ride. A captive
  folded into a union could never be freed.

The player owns the set; `TowerInterior` mirrors it (pushed on a grab, re-seeded on build)
because the tower is usually not streamed in when a field grab lands. An empty free set
ENDS THE RUN ON THE SPOT — `archive_world()` plus `_trigger_game_over()` (owner veto
2026-09-01, bead `godot-test1-ueg`; see the tower section) — decided in
`_on_caught_finished()`, which stays the one place a run's end is decided, with
`_tick_prison()`'s 0.5 s poll as the door for every peer nothing bit.
`free_hero_count()` is the hunt director's roster seam — death-spiral mitigation belongs
there, before contact, never in the capture path.

**IN A ROOM THE CAPTIVE SET IS ROOM-WIDE, and the rule is REASSIGN FIRST, IMPRISON
LAST.** A capture broadcasts the `cap` verb; every peer mirrors it into its own
`captive_heroes`, so the picker, the R-cycle and the ending all become world-level with
no second roster. The reassignment is the LOBBY's `SetHero` and needs no server change —
two peers benched in one frame serialize on the room lock, first wins, second retries on
the next `_tick_prison()`, which is the ONE site that sends it. Only a room with nothing
free benches anybody, and a benched peer plays as their captive inside the cell block:
confined to the gallery and its cells (`TowerInterior.block_min/max`), with **no ability**
(`get_ability_block_reason()` answers `"CELL"`), able to free a CELLMATE but never
themselves, and able to operate the VENT PURGE — theirs alone, and it scatters the pack
around every teammate through the shipped `flee` verb. `_tick_prison()` stands aside
while `is_caught`, so the grab that empties the roster still pays its coin bill in
`_on_caught_finished()`. **Game over is world-level** — the room's free set empty, not
this peer's hand — which is an adopted reading of the owner's phrasing.

### Death and respawn — THE HEROES ARE THE LIVES
There are no hearts and there is no life counter (owner ruling 2026-08-31, bead
`godot-test1-0bc`): **the only game over is the free-hero set going empty**, and since
the owner's veto of the break-out scene (2026-09-01, bead `godot-test1-ueg`) the FOURTH
CAPTURE raises the ending immediately — the film on web, the panel on desktop. The roster
is drawn by `scripts/hero_hud.gd`, which is the death display from here on.

Every other contact is a TAX, never an ending: `hit_by_crocodile()` → freeze/flash →
`_on_caught_finished()` → `_pay_coin_setback()` bills the attacker's own
`SPECIES["coin_setback"]` fraction off the RUN's coins (a spec-less attacker — the
tower press, a boss projectile — pays `DEFAULT_COIN_SETBACK`) → **soft respawn in place** (frozen
grace, then invulnerable blinking). **Lifetime coins are never deducted** — the bill comes
off the RUN's coins alone.

**A BITE IS WHERE A LEG IS BANKED**, though, so a death is not store-free:
`_on_caught_finished()` calls `_bank_records()`. With no hearts most runs never reach an
ending, and banking only at `_trigger_game_over()` would leave a whole session unwritten.
It is idempotent and every field is monotone, so repeating it is free — and both writers
below it are CHANGE-GATED, because a bite is a per-contact path and the stores are a disk
write plus a lobby POST: `best_run_store.submit()` only when a record moved,
`Progression.save()` dropping a save whose counters have not. The "NEW BEST!" flash
therefore reads the `run_beat_record` LATCH and never a fresh
`own_distance > best_distance` — the bite already raised the record it would compare
against.

`_pay_coin_setback()` also RELOCATES you, but only while you are STANDING INSIDE the
tower's walls: it asks the `tower_interior` group for `setback_point()` behind
`TowerInterior.inside_walls()`, so inside the HQ a death knocks you back to the last
checkpoint and a field death stays put. **The group answering is not the test** — the
shell is streamed in at `TOWER_LOAD_RADIUS` (360 m) and never freed for the rest of the
run, so once anybody has walked near the HQ the node is in the tree everywhere; gating on
its existence alone teleports every death in the world to the doorway. It is refused for
an ARREST (the surviving heroes carry on from where the party fell) and for a BENCHED
peer (whose clamp would drag the body under the block), and it is the building's, not the
row's: a checkpointed level, not a property of the guard.

Invulnerability is enforced in one place: the early-return at the top of
`hit_by_crocodile()`. `reset_position()` is only the hard reset to spawn used by
`restart_game()`.

### Gameplay loop
`run_seed` is rolled in `_ready()` from a private RNG and re-rolled by `new_run()`, which
is the only place it changes; `set_run_seed()` is the only place it is written, because the
biome domain offset derives from it. Coins are the headline score (distance is
retired from scoring everywhere the player sees it; world X coordinate remains internal
plumbing for chunk streaming and difficulty scaling). Coins have a streak
multiplier; gems are worth 10. Difficulty scales with
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

Panels open on raw keycodes outside the input map (K, M, P, B, L, +/−, \ arming key, F4–F7): named actions are
for rebindable *gameplay* input, and a key that only opens a panel has nothing to rebind
against. Every overlay pauses the tree, because the player reads gameplay through global
polled `Input`, which a focused `Control` does not suppress.

### The pause is refcounted — `scripts/pause_hub.gd` is the only writer
Nine scripts freeze the world (`pause_controller`, `help_overlay`, `skill_tree_ui`,
`mp_ui`, `start_overlay`, `mobile_input`, `landmark_toast`, `city_map_panel`,
`tower_lift_menu`). They used to own it
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
there is no ambient bed running continuously — beds and looping cues are event-driven
(e.g. heartbeat under danger, rain in storm zones) and fetched via `get_loop_player(name)`.

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

**The HQ is the one obstacle fauna PLANS around instead of probing.** The swept-box
lookahead is a 45 m reflex capped at a 30 m berth — right for scenery of unknown shape,
useless against an 80 m shell on a 65 m disc, which it meets by parking against the
facade. So `_plan_tower_detour` reads `tower_site()` / `TOWER_RADIUS` off the terrain
group once per herd, computes the lateral offset that clears the disc, and writes it into
the **existing** `_avoid_target` — no fourth steering term, no per-animal work, and the
probe keeps everything else. Spawn origins inside the disc re-roll the whole line.

### Budapest citizen crowds — hero look-alikes walking the streets
`scripts/crowd_manager.gd` (`group "crowd"`) implements the owner's story vision: heroes
blend into Budapest because masses of citizens look remarkably like them. Following the
fauna precedent, this is pure ambience outside the determinism contract (`randomize()`d RNG).

Citizens join **no group** and have **no collision** bodies or Area3Ds (zero interference with
hunters, crocodiles, or Stink Wave). The whole crowd is drawn in **exactly 4 draw calls** via
four `MultiMeshInstance3D` nodes (one per hero archetype: Windman, Primm, Teibi, Phoboman),
sharing one `StandardMaterial3D` with vertex colors across the process. Budget is capped at
`CROWD_MAX` (60 on web, 120 on desktop). Walkers navigate the 62 m street grid of Budapest,
pausing at crossings, strictly avoiding the wet Danube and plateau cliffs, with feet at y = 0.
Ambient spawns bubble around the local player inside `BudapestPlan.rect()`, recycling when out
of range and sleeping when outside the city. Pinned by `crowd_selfcheck`.

**THE AMBIENCE BUDGET IS A COARSE TICK, NEVER A FREEZE, and `scripts/ambience_lod.gd` is
its one home** (owner, bead `godot-test1-8gw.22`: *"we may use the same trick - only those
moving who we can see"*, in the same sentence as *"I want this natural"*). The crowd and
`scripts/traffic_manager.gd` (the cars, group `"traffic"`, one MultiMesh) share that file
because the rule and its rate must be ONE number. An instance the CAMERA cannot see is
ticked ~4 Hz instead of 60 and advances by the **real elapsed time** when its turn comes,
so nothing is ever static and turning round shows a street that plausibly kept walking; a
binary freeze is the bug this is written against. Four rules, all pinned:

- **The camera, not the player** — `get_viewport().get_camera_3d()`, frustum plus a 12 m
  margin. `C` cycles third-person / first-person / FRONT, and FRONT looks BACKWARD along
  the hero, so "in front of the player" is wrong in one of the three shipped views;
  `crowd_selfcheck` drives all three with probe walkers either side of the hero.
- **A null camera degrades to EVERYTHING VISIBLE** — full rate, today's behaviour — never
  to "nothing updates". Every headless check and every standalone scene runs that path.
- **ONE decision per instance per frame** (`lod_step`, taken in the spawn/recycle pass and
  spent by the movement pass), which is what keeps `is_walkable` / `is_traffic_walkable`
  the FIRST branch of every tick an instance actually takes. Nothing is ever deleted and no
  cap moved: this changes how OFTEN, never whether — the LOD manager's rule one step on.
- **The queue scan is no longer all-pairs.** `_distance_to_block_ahead` rejects a pair on a
  per-axis box (`QUEUE_SCAN_RANGE`) before computing anything and takes its own index from
  the caller instead of a `find`. It is a strictly conservative reject, and
  `traffic_selfcheck` check 8 holds it to an independent all-pairs oracle over a live
  bubble rather than trusting the argument.

**THEY ARE SOLID, AND STILL NOT NODES — `scripts/ambience_proxies.gd` is the one home**
(owner, bead `godot-test1-8gw.21`: *"our hero can run through crowd and cars, shouldn't be
so"*). No citizen and no car gets a body; each MANAGER owns a small POOL of `StaticBody3D`
proxies (6 citizens, 4 cars — measured maxima 4 and 3 within reach, and both are CONSTANTS
that do not grow with the caps) that is moved onto the nearest few instances every frame.
The locality is 8gw.22's: `offer()` is called from inside the loop that already writes the
MultiMesh buffer, so there is no second nearest-N pass. Four rules:

- **The isolation is the PHYSICS LAYER, and it is `fauna_manager.gd`'s verbatim** —
  layer 3 (`PROXY_LAYER` 4), which only the player's `collision_mask = 5` reads.
  Every predator is layer 2 / mask 3, so a proxy is invisible to a chase, to the LOD
  sweep, to the hunt director and to the Stink Wave. Nothing joins a group; a proxy
  carries no mesh, so 4 crowd + 1 traffic draw calls are untouched.
- **The player can never be trapped, and that is the CROWD's rule** (`yields`).
  Citizens walk their waypoints and do not look where they are going, so a pool-wide
  contact WINDOW yields the whole pool for a second when the hero makes less than
  `STUCK_TRAVEL` of headway across `STUCK_SECONDS`. It is a distance over a window and
  deliberately not an instantaneous speed — a pinned hero's per-frame speed swings on
  the frames depenetration nudges him. **Cars declare it off**: one brakes 18 m out and
  stops 6.7 m short on an 8 m half-width avenue, so it can pin nobody, and a car you
  could walk through after a beat is not a car.
- **Nothing may push the hero, AND THE TEST IS 3-D.** A proxy whose VOLUME contains
  him is not solid that frame (it can only fire on a pose that landed on him). The
  vertical half is bead `godot-test1-d5f`: the rule used to be the FOOTPRINT alone, and
  a hero standing on a car roof has his centre inside the footprint by definition — so
  the box switched itself off under his feet and he fell through to the road, and the
  same rule met him mid-jump so he passed clean through the car instead of landing on
  it. Feet at or above the roof less `ROOF_GRACE` are STANDING on it and keep it solid;
  only feet genuinely below the roof turn it off. For cars the
  stronger promise is arithmetic: `CAR_WIDTH/2 + 0.5` is far inside `LATERAL_TOLERANCE`,
  so every car that could touch a hero has already yielded to him.
- **The two self-checks were TIGHTENED, not loosened.** They no longer say "no
  `CollisionObject3D` under the manager" but "the only ones are exactly N numbered pool
  slots, `StaticBody3D`, on `PROXY_LAYER`, masking nothing, in no group, carrying no
  mesh" — plus a real `player.tscn` driven by the shipped movement into a planted
  instance, mutation-tested against an emptied pool, and since `d5f` a hero who
  STANDS on a parked car for a second and a citizen planted on him who moves him
  nowhere, each mutation-tested against the pool forgetting how tall it is.

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
`locale_selfcheck.gd`, not eyeballed. Debug surfaces (\fo, F4, ⚙ telemetry, selfcheck output)
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
totals, crocodile sync, claims), **`mp_codec.gd` (the pure codec)**, `remote_avatar.gd`
(visual only), `mp_ui.gd`, `teammate_locator.gd`.

**THE PARSERS ARE `MpCodec`, THE HANDLERS ARE `MpManager`, and that seam is the file
boundary.** `scripts/mp_codec.gd` (`class_name MpCodec`, all `static`) holds every
`decode_*` — `decode_presence`, `decode_state`, `decode_croc_sync`, `decode_captive`,
`decode_room`, `decode_pad`, `decode_lmk` — plus `packet_kind`, the `_croc_flags` byte
packing and the `CROC_FLAG_*` constants both ends of it read, the two `*_in_reach`
proximity tests, `peer_int_id`, and the wire-format bounds (`MAX_STATE_IDS`,
`MAX_HERO_NAME`, `MAX_CROC_SYNC`, `MAX_LANDMARK_CLAIM_PAD`, …) they are written against.
It reads no instance state and knows about no room. Everything with a socket or state —
the mesh, presence, the verbs, authority, rate limits, the hero pool — stays in
`mp_manager.gd`. **A new verb is a parser in `mp_codec.gd` beside its siblings and a
handler in `mp_manager.gd`**; a bound belongs with the parser that enforces it, so the
encoder reads it back as `MpCodec.X` rather than re-typing the number.

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
- Shared bank/distance are a sum of per-peer absolute broadcasts — no authority, no
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
- **The master publishes the one value a room may never disagree about** — the captive
  set — on the `room` verb (2 Hz, mesh + relay, master-only, applied wholesale). It is a
  REPAIR channel, not the source: it closes the
  join gap the per-hero verb cannot reach (a capture landing between the master
  snapshotting a joiner and the captor learning that joiner exists), and it converges in
  BOTH directions while leaving any assertion younger than `RELEASE_GRACE_MSEC` alone —
  without that the master's older picture undoes a fresh local capture and puts it back
  next tick, a flap at the publish rate. **The packet still carries `cd`/`co`, as ZEROS
  and as a SHAPE ONLY**: they were the vetoed break-out's clock and verdict, nothing
  reads them, but `decode_room()` drops a packet missing either and `build_version`
  refuses to reload a peer that is in a room — so mixed-build rooms are real and an older
  master's real values must still decode, or the room stops repairing its cells over a
  field nobody uses. There is no authority left to hold: **game over is decided per peer
  off the mirrored set**, so every peer reaches the same empty free set on its own.
  `_auto_claim_hero()` waits for
  `_join_settled()` — on the `welcome` frame the captive set is still empty, and claiming
  there means claiming a hero who is in a cell.
- The stall heartbeat rides the lobby relay, not the mesh, because a throttled tab stops
  polling both.

Desktop needs the `webrtc-native` addon (fetched by `./fetch_webrtc_addon.sh`, never
vendored); the web build needs nothing.

## Performance & web build

The web (WebGL) build is the performance-sensitive target.

- `scripts/perf_overlay.gd` — **\fo** (cheat code). FPS, draw calls, node count, active/total crocs. This
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
- **\fb / \fh TELEPORT TO BUDAPEST AND TO THE HQ, so "no web reading" is no longer an
  excuse** (bead `godot-test1-xtl`). Two perf beads in a row shipped headless CPU numbers
  because the city is 1.7 km from spawn and nobody walks a browser build there twice for a
  before/after pair. **A perf bead that touches the city, the crowd, the traffic or the
  tower is now expected to carry a WEB \fo reading**: teleport, then \fo. It is
  `player_controller.debug_teleport_to()` behind `debug_teleport_allowed()` —
  `OS.is_debug_build()` AND not in a room, so an exported release build cannot reach it
  and a peer can never publish a teleported position — on typed cheat codes outside the input
  map (the \fo / \fb / \fh and F4–F7 precedent), and it re-seats the world through
  `MpManager._apply_join_placement()`'s own sequence (`new_run` with the CURRENT seed →
  `build_ring_now` → wait a physics frame → `_place_near`) so the body lands on built
  ground with the ring's blocks and crocodiles already there. **TAKE THE READING ON
  `godot --headless --export-debug "Web" build/web/index.html` + `./serve.sh`** — CI and the
  deployed build export `--export-release`, where `is_debug_build()` is false and \fb/\fh are
  dead by design, so a before/after PAIR is comparable on the debug template but the absolute
  numbers are not the deployed build's. It preserves the run —
  coins, streak, mask, heroes — and shifts `own_distance_origin` by the jump so the
  personal record is not banked from a place nobody walked to. `debug_teleport_selfcheck`
  pins all of it.

### Performance conventions
- **Visual-affecting changes are web-gated.** Desktop and editor stay at full quality.
- **Purely invisible optimizations are global** (batching, LOD, consolidated collision).
- **Entity counts are never reduced as an optimization.** Croc counts change only by
  *design*. Distant crocodiles are slept, never removed.

## CI/CD

`.github/workflows/build.yml` builds the web export on every push, and runs the two
self-check jobs beside it: `selfcheck-shard` globs **every** `scripts/*_selfcheck.gd` (so a
new one is gated the day it lands) and `model-selfcheck` runs `scripts/predator_parts.py`.
A check counts as passed only if it exits 0 **and** printed `SELFCHECK OK` **and** logged no
`SCRIPT ERROR` — Godot exits 0 on a parse error AND on a runtime error, so the exit code
alone is not a verdict, and a runtime error skips every assertion after it while the script
still prints its OK line.
The GDScript suite is **sharded across a matrix** (~8 min sequential → ~3 min); the
partition is computed from the glob at runtime by `scripts/selfcheck_shards.sh` off
`strategy.job-index` / `strategy.job-total`, **never a list of check names in the YAML** —
a list goes stale silently the day someone adds a check. It is COST-AWARE since bd
`godot-test1-ftn.14`: longest-first bin packing over `scripts/selfcheck_durations.json`
(seconds per check, refreshed from the `OK <name> (Ns)` lines the shard step prints), with
a name the table does not carry treated as the HEAVIEST check in the suite, so an
unmeasured newcomer can never be stacked on the slowest one. The glob remains the only
source of truth for *what* runs; the table only says how heavy each name is. The previous
positional "every Nth file" partition reshuffled on every added or renamed file, which is
how PR #233 put boss (3m01) and tower_interior (1m30) in one bin and took the gate from
4m30 to 6m00. `selfchecks` is the aggregating job both deploy jobs
`needs:`: it is green only when every shard is, it runs
`sh scripts/selfcheck_shards.sh --selftest` (the packing simulated over the glob plus a
dummy file; a weight naming a check that no longer exists is a red build), and it re-reads
the glob to prove the union of what the shards actually ran was exactly the suite. **Deploy happens only on push to
`master`** — merging is what publishes.

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
