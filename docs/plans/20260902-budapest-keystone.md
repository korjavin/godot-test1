# Budapest .3 — THE KEYSTONE: the authored city, streamed through ordinary chunks

## Overview

Bead `godot-test1-8gw.3`, the keystone of epic `godot-test1-8gw` ("Escape to Budapest").
Ship the city's **skeleton** and the **gate district**. Landmark *builders* already
exist (beads .6a/.6b shipped 15 of them into `CITY_LANDMARKS`); what does not exist is
anywhere to put them, a river to put them beside, a road that arrives, or a rule that
stops the procedural world spawning cacti in the middle of Pest.

This bead delivers, in one branch:

1. `scripts/budapest_plan.gd` — a `const` plan in the `tower_plans.gd` idiom: the site
   rect, the gate, the Danube polyline, the dry rects (bridge decks + Margaret Island),
   two ramped plateaus, the street grid parameters, the gate district, and **22 named
   landmark slots**.
2. City cells streamed from that plan through `create_chunk`, chunk-parented, through
   `create_box()` / `block_batch` / the chunk's single `BlockCollision`.
3. CPU/GPU parity: forced CITY ground, the authored Danube band, the dry cutouts — in
   both languages, together.
4. Per-system spawner policy inside the rect (NOT `tower_excludes()`).
5. The road's final approach: a terminal station `T`, consumers capped there, a
   deterministic corridor from `T` to the gate.
6. The difficulty input clamped at the gate's X.
7. The gate district built for real.
8. `scripts/budapest_selfcheck.gd`.
9. `CLAUDE.md`: the city's lifetime model beside the tower's "must stay one".

---

## Files this bead touches — and the ones it MUST NOT

**Touches:**

| File | What |
|---|---|
| `scripts/budapest_plan.gd` | NEW. Pure const data + pure helpers. `class_name BudapestPlan extends RefCounted`. |
| `scripts/budapest_selfcheck.gd` | NEW. `extends SceneTree`, the `tower_shell_selfcheck` idiom. |
| `scripts/endless_terrain.gd` | The streamer, the parity clauses, the spawner policy, the road cap + approach. |
| `assets/shaders/ground.gdshader` | The GPU half of the three new parity clauses. |
| `scripts/piglet_crocodile_ai.gd` | ONE line: the difficulty clamp at L3695. |
| `scripts/minimap_hud.gd` | ONE clause in `_gather_road()`: stop at `T`. |
| `CLAUDE.md` | The city's lifetime model. |

**MUST NOT touch — another track owns them, a merge conflict here costs more than any
feature this bead could add:**

- `scripts/landmark_builders.gd` and `scripts/landmark_selfcheck.gd` — bead .6c (wave C)
  is landing six or seven more builders in that file **in parallel**. This bead REFERENCES
  `CITY_LANDMARKS` by builder-method-name string and never edits the registry. A slot whose
  builder does not exist yet carries `"builder": ""` and is skipped by the streamer.
- `scripts/player_controller.gd`, `scripts/best_run_store.gd`, `scripts/game_over_ui.gd`,
  the intro/start overlay — bead .2 (run OUTCOME) owns them. **The difficulty clamp is NOT
  in `player_controller.gd`** — it is in `piglet_crocodile_ai.gd:3695`; grep confirmed
  `player_controller.gd` only *mentions* the difficulty contract in comments.
- `scripts/fauna_manager.gd` — see the deferral list.

---

## Decisions already made — do NOT re-open these

### DEC-1. THE KEYSTONE DECISION the bead demands an answer to: **(a) per-chunk slicing**

The note on the bead (from PR #172) says: a city landmark builder emits into ONE chunk's
`block_batch`, but Parliament is 268 m long and Buda Castle's disc is 156 m in radius,
while a chunk is 50 m and the web build's `render_distance` is 3. Stand at the far end of
the Parliament and the chunk holding its slot has unloaded — the building vanishes.

**The answer is (a): the builder's output is SLICED per chunk.** Every chunk whose square
intersects a slot's disc runs that slot's builder into a SCRATCH batch and a SCRATCH body,
and keeps only the boxes whose **centre** falls inside its own square. Rejected:

- **(b) manager-parenting the giants** — a second lifetime model for a handful of
  buildings, and the one thing CLAUDE.md says must stay exactly one exception.
- **(c) a wider residency radius for city cells** — the 49-chunk web residency ceiling is
  the whole reason the city is chunk-streamed at all.

Why (a) is nearly free: the builders are **pure functions of (center, rng)** — the city
banner in `landmark_builders.gd` states the RNG touches COLOUR ONLY, no dimension, offset
or count is drawn. So running the same builder from the same seed in a neighbouring chunk
produces the *same boxes at the same world positions*, and clipping is a filter on the
output. It needs no edit to `landmark_builders.gd`, which this bead may not touch anyway.

**The rules that make it correct, all four asserted by `budapest_selfcheck` check 5:**

- **The slot's RNG seed is a pure function of the SLOT INDEX and nothing else** —
  `hash(Vector3i(slot_index, CITY_LANDMARK_SALT, 0))`. **No `run_seed`** (the city is
  authored, `tower_site()`'s precedent) and **no chunk coordinate** (or the same box
  would get a different `_lm_shade` colour in each slice and the building would be
  tie-dyed along its chunk seams).
- **The clip test is half-open**: keep a box when
  `local.x >= -half and local.x < half and local.z >= -half and local.z < half`, `half =
  chunk_size / 2`. Half-open means a box centred exactly on a boundary lands in exactly
  one chunk — never both, never neither.
- **The clip applies to BOTH halves.** Batch entries are filtered by
  `entry["transform"].origin`; collision shapes are filtered by the scratch body's
  `CollisionShape3D.transform.origin` and **reparented** (`remove_child` then
  `block_body.add_child`) rather than rebuilt. Do not try to correlate a shape with a
  batch entry by index — `collide = false` boxes make the two lists different lengths.
- **`parent_chunk` gets a scratch too.** Ten builders (`_city_parliament`,
  `_city_basilica`, `_city_synagogue`, …) parent a glowing ACCENT node to `parent_chunk`.
  Under slicing that would give the Parliament one beacon per overlapping chunk. So pass a
  scratch `MeshInstance3D`, and afterwards: if the slot's CENTRE is in this chunk, reparent
  the scratch's children onto the real chunk; otherwise free the scratch and its children.
  One rule, no builder edit, and the accent exists exactly once.

Cost, measured against the shipped numbers: Parliament is 122 boxes and its disc touches
~7 x 7 = 49 chunks, so the whole building costs ~6,000 `create_box` calls spread across 49
different frames (one chunk per frame — `_process` L3024) — ~122 per frame, which is what
one ordinary prop chunk already pays. Accepted.

### DEC-2. Orientation and the site

**+X is EAST, +Z is SOUTH, +Y is up.** Written in the file header of `budapest_plan.gd` in
those words, because every coordinate in the table below is meaningless without it and a
reader coming from a map will otherwise assume +Z is north.

```
BUDAPEST_MIN := Vector2(1600.0, -1100.0)    # x, z
BUDAPEST_MAX := Vector2(3800.0,  1100.0)
GATE         := Vector3(1600.0, 0.0, 0.0)   # on the west edge, z = 0
```

A `Rect2`, a CONSTANT, no seed, no hash, no `randf` — `tower_site()`'s ruling one scale up.
The HQ is at x = -400, so the gate is 2 km east of it, which is the owner's number.

### DEC-3. The Danube

A 5-point polyline in (x, z), north to south, with a real bend, and a half-width:

```
DANUBE := [ Vector2(2560, -1100), Vector2(2530, -560), Vector2(2470, -40),
            Vector2(2500,  520), Vector2(2570,  1100) ]
DANUBE_HALF_WIDTH := 120.0
```

240 m wide against the real ~350 m: narrowed, not because of gameplay but because Castle
Hill and Gellért Hill have to fit on the west bank at roughly real scale inside a 2.2 km
rect. Document that trade in the plan header.

The band is **paint plus a wade penalty and nothing else** — the flat-world invariant is
untouched: no water mesh, no depth, no transparency, ground stays at y = 0. Banks, the
island's parkland and the Danube crocodile *density* schedule are bead .4's.

### DEC-4. Dry rects — ONE mechanism, three users

`is_river_at()` is XZ-only and the wade test ignores Y, so a bridge deck 12 m above the
water still wades. The answer is a small table of axis-aligned **dry rects** that the band
is punched out by, in both languages:

```
DRY_RECTS := [                                  # Rect2(x, z, w, h)
  Rect2(2380, -716, 320, 32),   # Margaret Bridge deck
  Rect2(2330,  -16, 290, 32),   # Chain Bridge deck
  Rect2(2350,  404, 290, 32),   # Elisabeth Bridge deck
  Rect2(2360,  684, 300, 32),   # Liberty Bridge deck
  Rect2(2470, -950, 130, 310),  # Margaret Island — dry land in the river
]
```

Margaret Island rides the SAME table as the decks, because "an island" and "a bridge deck"
are the same question asked of `is_river_at`: *this XZ is inside the band and is not water*.
That is why bead .4 needs no new machinery for the island — it adds a row and builds
parkland.

### DEC-5. The plateaus — ramped massifs, and the ramp is ONE tilted box per chunk

```
CASTLE_HILL := { rect: Rect2(1970, -860, 400, 800), top: 30.0,
                 ramp: Rect2(1830, -466, 140, 12), ramp_dir: +X }
GELLERT     := { rect: Rect2(2090,  570, 280, 380), top: 46.0,
                 ramp: Rect2(1880,  734, 210, 12), ramp_dir: +X }
```

- **The plateau is chunk-sliced for free**: a chunk inside the rect emits **one** box —
  the chunk-square ∩ plateau-rect, from y = 0 to `top`. One box, one collision shape, one
  `obstacles` footprint (`climbable: false`, `top: top`, the mountain-massif convention).
  Cliffs on every side; the only way up is the ramp. Mountains are impassable massifs you
  walk around, and a plateau is a mountain with a walkable lid.
- **The ramp is a TILTED box, never steps.** `CharacterBody3D` cannot climb steps at all,
  and CLAUDE.md's tower rule — *no interior traversal may demand a jump-height* — is the
  same rule outdoors. `create_box` already composes `Basis(UP, yaw) * Basis(RIGHT, tilt)`;
  a ramp on +X is `yaw = PI/2`, `tilt = -atan2(rise, run)` (the `_city_cable` derivation,
  read it before you write this). It slices per chunk exactly like the plateau: the sub-rect
  is on the same plane, so neighbouring slices meet flush by construction.
- **The slope is measured, not asserted.** Castle Hill: 30 / 140 = 0.214. Gellért:
  46 / 210 = 0.219. `budapest_selfcheck` reads `TowerInterior.PLAN_RAMP_MAX_SLOPE` —
  the slope of the one ramp in this game anybody has actually walked — and fails a plateau
  ramp steeper than it. **Read it, never restate it**: retuning the proven ramp must retune
  this ceiling with it.

### DEC-6. The 22 landmark slots

A slot is `{ id, builder, pos: Vector3, radius: float }` — **position and radius only**;
the geometry is .6a/.6b/.6c's. `builder` is the METHOD-NAME STRING from `CITY_LANDMARKS`
(`landmark_builders.gd` dispatches that way already, via `_landmark_builders.call(...)`),
or `""` for a slot whose wave-C builder has not landed yet.

Slot `pos.y` is the base height the builder is placed at — 0 everywhere except the four
slots on a plateau, which carry the plateau's `top`.

| # | id | builder | pos (x, y, z) | radius | notes |
|---|---|---|---|---|---|
| 0 | `parliament` | `_city_parliament` | 2760, 0, -480 | 151 | Pest bank, faces the river |
| 1 | `buda_castle` | `_city_buda_castle` | 2170, 30, -240 | 156 | on Castle Hill |
| 2 | `matthias` | `_city_matthias_bastion` | 2170, 30, -640 | 80 | on Castle Hill, north end |
| 3 | `citadella` | `_city_citadella` | 2230, 46, 760 | 120 | on Gellért Hill |
| 4 | `margaret_island` | `_city_margaret_island` | 2535, 0, -880 | 56 | on the island dry rect |
| 5 | `chain_bridge` | `_city_chain_bridge` | 2475, 0, 0 | 124 | on the Chain deck |
| 6 | `liberty_bridge` | `_city_liberty_bridge` | 2510, 0, 700 | 104 | on the Liberty deck |
| 7 | `elisabeth_bridge` | `_city_elisabeth_bridge` | 2495, 0, 420 | 122 | on the Elisabeth deck |
| 8 | `margaret_bridge` | `_city_margaret_bridge` | 2540, 0, -700 | 114 | on the Margaret deck |
| 9 | `basilica` | `_city_basilica` | 2920, 0, -280 | 58 | |
| 10 | `market_hall` | `_city_market_hall` | 2820, 0, 620 | 82 | |
| 11 | `synagogue` | `_city_synagogue` | 2960, 0, 200 | 49 | |
| 12 | `vaci_utca` | `_city_vaci_utca` | 2760, 0, 300 | 78 | |
| 13 | `national_museum` | `_city_national_museum` | 2920, 0, 440 | 62 | |
| 14 | `opera` | `_city_opera` | 3000, 0, -180 | 49 | |
| 15 | `heroes_square` | `""` | 3520, 0, -520 | 110 | wave C |
| 16 | `vajdahunyad` | `""` | 3680, 0, -340 | 100 | wave C |
| 17 | `szechenyi_bath` | `""` | 3620, 0, -760 | 90 | wave C |
| 18 | `gellert_bath` | `""` | 2420, 0, 1000 | 70 | wave C |
| 19 | `rudas_bath` | `""` | 2370, 0, 560 | 50 | wave C |
| 20 | `shoes_on_the_danube` | `""` | 2640, 0, -300 | 40 | wave C |
| 21 | `budapest_eye` | `""` | 2870, 0, -60 | 40 | wave C |

Rows 0–14 are the fifteen shipped builders, in `CITY_LANDMARKS` order, with the registry's
own declared radius copied into the slot — and check 2 asserts the two agree, so a wave-C
edit to a shipped radius fails this build instead of silently overhanging.

Rows 15–21 are the seven wave-C slots. Their radii are RESERVATIONS: generous, authored
here so `.5`'s catalogue and `.10`'s reachability audit have 22 slots to work with from
day one, and so wave C's builders have a declared bound to hit. **A slot with an empty
builder is skipped by the streamer and exempt from the registry check** — that is the
whole of "leave the slot empty".

These coordinates are a **real-map relative layout at roughly real scale**, with the
Andrássy end (15–17) folded ~800 m closer than the real 2.5 km, exactly as the epic asked.
The header comment must say which liberties were taken and why, because the numbers ARE
the design record — there is no seed to reroll, the `tower_plans.gd` ruling.

### DEC-7. THE ROAD'S FINAL APPROACH — cap the consumers, never the cache

The centreline's Z is a function of `run_seed` (only station 0 is fixed), so a FIXED city
cannot wait at the end of a wandering road. Two halves:

**(i) A terminal station T.**

```
ROAD_TERMINAL_X := 1450.0      # a const in endless_terrain, beside the road config
func _road_terminal_k() -> int  # cached per run; the last station with center.x <= T
```

Implemented off the machinery that already exists: `_road_extend_to_x(T, T)` then
`_road_first_k_at_or_after_x(T) - 1`. Memoize it in a `var _road_terminal_k_cache: int`
reset in `new_run()` beside the road cache reset (L9261–9263) — it is a pure function of
`run_seed` and the road config, and every consumer asks for it.

**DO NOT cap `_road_extend_to_x()` itself.** Its loops and all three binary-search callers
assume the cache spans any X; capping it there hangs the forward loop. Cap the CONSUMERS,
all four:

| Consumer | Site | Cap |
|---|---|---|
| road coins | `_road_coins_at(k)` L8886 | `if k > _road_terminal_k(): return []` — first line. Each station's coin RNG is seeded from `k` alone, so skipping a station perturbs no other station. |
| road clearance | `_road_lateral_distance` L8978 | clamp the `while k <= road_k_max` bound to `mini(road_k_max, _road_terminal_k())`. Returns INF past T, which every caller already reads as "nowhere near the road". |
| road bosses | `spawn_bosses_in_chunk` L5900–5924 | skip a boss index whose station `k > _road_terminal_k()`, **before** `_boss_row_at()` — so the `BIOME_BOSS` dispatch never fires past T. |
| the minimap line | `minimap_hud.gd` `_gather_road()` L815–866 | clamp `x_limit`'s station window's upper end to `_road_terminal_k()`. It is a `_terrain.` call like the two already there. |

**(ii) The corridor, from T to the gate.**

```
func road_approach_point(terminal: Vector2, x: float) -> Vector2
```
Pure, on `BudapestPlan`: for `x <= terminal.x` return `terminal`; for
`x >= GATE.x` return `Vector2(x, GATE.z)`; between, lerp Z from `terminal.y` to `GATE.z`
over a `smoothstep` in `x`, so the join at T has no kink. Deterministic in
(`terminal`, `x`) and therefore in `run_seed`, which is what check 7 measures over 50 seeds.

Past the gate the corridor IS the avenue, at z = 0 — one line, not two.

**(iii) The approach + avenue coin line**, `spawn_approach_coins_in_chunk`, because
capping road coins at T would otherwise leave 900 m with nothing to pick up and the
headline score (coins, since .1 retired distance) frozen from T to the Danube:

- Covers `x` in `[ROAD_TERMINAL_X, DANUBE west bank at z = 0]`.
- **Zero RNG.** Coins at a fixed `CITY_COIN_SPACING` (8 m) on the corridor centreline —
  authored, like everything else in this city, so there is no stream to keep independent
  and nothing to A/B. Height through the existing `_settle_coin_y`; `is_inf` skips as usual.
- Bucket by `world_to_chunk(pos) == chunk_pos` exactly as `spawn_coins_in_chunk` does
  (L9086), so a coin belongs to exactly one chunk and unloads with it.
- Coin identity is `Coin.id_at(world)` — quantized position — so multiplayer claims work
  with **no `mp_manager.gd` edit at all**, the dossier-rack precedent.

### DEC-8. Parity — three clauses, in both languages, edited together

`_biome_noise` / `biome_noise` themselves are **NOT touched**. What changes is what is
read off them inside the rect.

**CPU, `endless_terrain.gd`:**

- `biome_at(x, z)` — first line: `if BudapestPlan.contains(x, z): return Biome.CITY`.
- `is_river_at(pos)` — after the tower disc clause (L8413–8417), before the noise band:
  ```
  if BudapestPlan.contains(pos.x, pos.z):
      return BudapestPlan.danube_wet(pos.x, pos.z)
  ```
  `danube_wet` = distance to the polyline `< DANUBE_HALF_WIDTH` **and** not inside any
  `DRY_RECTS` row. The early `return` is what suppresses the noise river inside the rect:
  the city has ONE river and it is authored.
- Route the polyline distance through `Vector2`, never scalar arithmetic — same fp32
  discipline as the noise port and the tower disc, for the same reason.

**GPU, `ground.gdshader`** — new uniforms, all with INERT defaults so a material nobody
feeds still looks right (the `tower_dry_radius = -1.0` pattern):

```glsl
const int CITY_SEG_MAX = 8;
const int CITY_DRY_MAX = 8;
uniform vec4  city_rect = vec4(0.0, 0.0, -1.0, -1.0);   // xmin, zmin, xmax, zmax; inert when max < min
uniform vec4  city_river[CITY_SEG_MAX];                  // x1,z1,x2,z2 per segment
uniform int   city_river_count = 0;
uniform float city_river_half = 0.0;
uniform vec4  city_dry[CITY_DRY_MAX];                    // xmin,zmin,xmax,zmax
uniform int   city_dry_count = 0;
```

**Where each half is computed, and why they are not in the same stage:**

- The **band factor goes in `vertex()`** as a new varying. The existing river band is
  per-fragment because it is ~8 m wide against ~3 m vertex spacing (2.6x — undersampled).
  The Danube is 240 m wide against the same 3 m spacing (**40x oversampled**), so
  interpolating it costs no visible accuracy and keeps a 8-segment distance loop off a
  fill-rate-bound web target. Write that arithmetic into the comment; it is the reason the
  two rivers are computed in different stages and the next reader will otherwise "fix" it.
- The **dry-rect mask goes in `fragment()`**, inside the city branch: a deck is 32 m wide
  and its edge is HARD, and a 3 m interpolated fade on a rect the CPU answers exactly would
  put the blue you see and the wading you feel a metre and a half apart on every deck. Up
  to 8 rect tests, four compares each, only for pixels inside the city.
- **The forced CITY ground** replaces the biome chain's result inside the rect
  (`albedo = city_color * mottle;`), and the **tower disc mask does not apply inside the
  city** — one river or the other, never both.

**`_apply_biome_shader_params()` (L2803)** pushes every new uniform beside the tower's
two, from the plan, in one place. It is guarded by `if not (terrain_material is
ShaderMaterial): return` — leave that guard alone.

### DEC-9. Spawner policy INSIDE the rect — per system, NOT `tower_excludes()`

`tower_excludes()` excludes *everything procedural*; the city wants five different answers.
Add one predicate on the terrain — `func in_budapest(world_x: float, world_z: float) ->
bool` delegating to `BudapestPlan.contains` — and one early return per spawner, keyed on
the CHUNK CENTRE:

| System | Policy | How |
|---|---|---|
| props + feature structures | **OFF** | `spawn_objects_in_chunk` returns `[]` before its RNG is even constructed |
| artifacts, biome content, camps, geo landmarks, chests | **OFF** | early return at the top of each |
| biome predators | **OFF** | early return at the top of `spawn_crocodiles_in_chunk` |
| **Danube crocodiles** | **ON** | `spawn_danube_crocodiles_in_chunk`, its OWN salt and primes (below) |
| platform crocodiles | off by construction | `platforms` is empty inside the rect; add nothing |
| road bosses | **OFF** | already true: T (x = 1450) is west of the gate (x = 1600). Asserted, not re-guarded. |
| **hunters** | **ON, unchanged** | `spawn_hunters_in_chunk` is not edited at all — the pursuit is the story |
| road coins | **OFF** | already true via the T cap |
| **avenue coins** | **ON** | `spawn_approach_coins_in_chunk`, zero RNG |
| **the city itself** | **ON** | `spawn_city_in_chunk` |

**The Danube crocodile policy.** Its own hash stream, its own salt, its own coordinate
primes — CLAUDE.md's rule, and the thing check 10's A/B measures:

```
const DANUBE_SALT: int = 0xDA_11BE
const DANUBE_HASH_PRIME_X: int = 141650939
const DANUBE_HASH_PRIME_Y: int = 175961107
const DANUBE_CROC_CHANCE: float = 0.55
const DANUBE_CROC_MAX: int = 2
```
Only for a chunk whose centre `danube_wet()` answers true for. Species is `"crocodile"` —
the owner's "river → crocodile", the same rule `_boss_row_at` already applies. Assign
`croc.species` **before** `add_child`, the `SPECIES` row contract. Candidate positions are
re-tested with `danube_wet()` so nothing stands on a deck or the island.

### DEC-10. `spawn_city_in_chunk` — where it goes and what it emits

**Insertion point: between L3405 (`spawn_chest_in_chunk`) and L3410
(`_build_block_multimesh`)** — after everything that fills `obstacles`, before the batch
and body are committed, so every box joins the chunk's ONE MultiMesh draw call and ONE
collision body. That is the ordering requirement stated five times in `create_chunk`'s
comments; obey it.

It emits, in this order (later things read the earlier ones' footprints):

1. **plateau slice** — one box per plateau whose rect meets this chunk, plus its footprint;
2. **ramp slice** — one tilted box per ramp rect that meets this chunk;
3. **landmark slices** — DEC-1, per slot whose disc meets this chunk, plus ONE round
   footprint per slot in every chunk it touches (`climbable: false`);
4. **the gate district** — DEC-11 — only in the chunks that meet its rect;
5. **the avenue** — a thin pavement slab (`collide = false`, 0.15 m) along z = 0 from the
   gate to the Danube's west bank, sliced per chunk. Nothing else of the street grid is
   drawn: bead .7 owns the streets, this bead owns the grid PARAMETERS only.

Everything is `create_box()` into the passed `block_batch` / `block_body`, everything is
chunk-parented through them, and nothing here allocates a `MeshInstance3D` or a physics
body of its own. **All of it uses a private `RandomNumberGenerator`, never the chunk
stream** — `create_box` draws four numbers per box and one extra draw slides every
crocodile in the world.

### DEC-11. The gate district — the smallest slice that exercises every dangerous seam

`DISTRICT := Rect2(1620, -130, 200, 260)`, ~200 x 260 m at the gate. In it:

- **The avenue**, 16 m wide, on z = 0, running east out of the gate.
- **A block of authored houses**: a small `const DISTRICT_HOUSES` table in
  `budapest_plan.gd` — 16 rows of `{ pos, size, wall_shade, roof_shade }`, eight either
  side of the avenue at z = ±26, every 25 m. Hull + eaves roof + door + windows, the
  `_spawn_city_content` house recipe, but with the dimensions AUTHORED rather than drawn.
  **Do not refactor `_spawn_city_content` to share the recipe** — it is a hot deterministic
  path whose draw ORDER is load-bearing, and ten lines of `create_box` here is a smaller
  and much safer diff than proving a code motion changed no draw. Roof height stays under
  `PROP_MAX_STEP` (2.6) so a hull top is one jump from the pavement, the city biome's own
  contract, and the footprint is `climbable: true` like a city house.
- **Street dressing from the jb7 city prop builders**, called directly:
  `_prop_crate_stack`, `_prop_garden_wall`, `_prop_paving_stack` (the CITY arm of
  `_build_prop`, L4377–4384). A handful, on authored spots, off the private RNG.
- **One plateau ramp** — Castle Hill's, at x 1830–1970, is a chunk away from the district
  and is the proof that "ramps, never steps" holds outdoors.
- **One bridge, dry** — the Chain Bridge's deck rect and its builder, proving the dry-deck
  semantics for real. It is 900 m east of the district and streams in when you walk there;
  it needs no special case because it is plan data like everything else.

### DEC-12. The difficulty clamp

`piglet_crocodile_ai.gd:3695`:
```gdscript
var distance_factor := 1.0 + clampf(
    absf(minf(global_position.x, BudapestPlan.GATE.x)) / DISTANCE_SPEED_SCALE_DENOM, ...
```
`minf` on the SIGNED x, `absf` outside it: exploring **east** past the gate stops ramping
the chase, and travelling west (the tower is at x = -400, and the world runs on) is
untouched. `BudapestPlan` is a `class_name` on a `RefCounted` that depends on nothing, so
this is a constant read and not a cycle. One line, one comment naming the bead.

---

## Invariants this work must not break — read CLAUDE.md before you start

- **Determinism.** Every new site is a pure function of authored data (no seed at all) or
  of `hash(Vector3i(...))` with its OWN salt and OWN coordinate primes. **Every rejection
  is a post-draw `continue`.** One extra draw from a shared stream slides every crocodile
  in the world and nothing on screen ever tells you.
- **One MultiMesh + one collision body per chunk.** Nothing here instances a
  `MeshInstance3D` or a physics body per object.
- **Chunk-parented or it leaks.** Everything the city builds goes through the passed
  `block_batch` / `block_body`, which `create_chunk` parents to the chunk.
- **The flat-world invariant.** Ground stays at y = 0. Plateaus are block massifs, rivers
  are tinted wading bands — no heightfield, no water mesh, no transparency.
- **The tower's masking stays untouched.** Its disc clause in `is_river_at` and its two
  shader uniforms are not edited; the city's clause sits below the tower's and returns
  before the noise band.
- **`"player"` means the LOCAL player.** No new group lookups.
- **The speed lattice.** No `SPECIES` speed is touched. The difficulty clamp lowers a
  multiplier's input; it cannot raise anything.
- **`minimap_hud` allocates ONE tower buffer** (`_tower_points.resize(4)`, L524) — it is
  not generic, do not try to reuse it for the city. The city map is bead .9.
- **`_road_points` is the only minimap buffer that resizes on the tick** — the T cap makes
  the window SHORTER, never longer, so it cannot make that worse.
- GDScript with explicit type hints; tunable constants at the top of each script. **Match
  the surrounding comment density** — `endless_terrain.gd` and `tower_plans.gd` are the
  two most heavily commented files in this repo and the new file joins that family.

---

## Development Approach

Build in the task order below. After each task run the self-checks the task names; after
Task 8 run the whole family. `godot --headless --path . --import` before `locale_selfcheck`
and before the first run of any new selfcheck (`.uid` caches).

Run one check with:
```
godot --headless --path . --script res://scripts/<name>_selfcheck.gd
```
A check passes only when it exits 0 **and** printed `SELFCHECK OK` — a GDScript parse
error exits 0, so the exit code alone is not a verdict.

## Testing Strategy

There is no test suite. The gate is the headless self-check family, and CI globs
`scripts/*_selfcheck.gd`, so `budapest_selfcheck.gd` is gated the day it lands.

Regression risk is concentrated in three files that other checks already measure:
`enemy_spawn_selfcheck` (determinism, spawn streams, the boss road walk),
`chunk_stream_selfcheck` (ground-first streaming), `minimap_selfcheck` (the road line),
`wade_selfcheck` (the river), `tower_site_selfcheck` / `tower_shell_selfcheck` (the disc
and its coin exclusion), `landmark_selfcheck` (untouched, must stay green). **Run all of
them.**

## Progress Tracking

Tick each `- [ ]` as it lands. Commit per task with a descriptive message. No attribution
or co-author trailers anywhere.

---

## Implementation Steps

### Task 1: `scripts/budapest_plan.gd` — the plan, and nothing but the plan

- [x] Create `scripts/budapest_plan.gd`: `class_name BudapestPlan extends RefCounted`.
- [x] Header in the `tower_plans.gd` idiom (`##` doc comments, ALL-CAPS fenced sections):
      WHY IT IS AUTHORED (the owner's "plan it once and forever", `tower_site()`'s ruling
      one scale up), **THE ORIENTATION** (+X east, +Z south) in its own paragraph, the
      real-map liberties taken (the Andrássy fold, the narrowed Danube) and the rule that
      **the numbers ARE the design record because there is no seed to reroll**.
- [x] Constants per DEC-2, DEC-3, DEC-4, DEC-5: `BUDAPEST_MIN` / `BUDAPEST_MAX` / `GATE`,
      `DANUBE` / `DANUBE_HALF_WIDTH`, `DRY_RECTS`, `PLATEAUS`, `STREET_PITCH`,
      `AVENUE_HALF_WIDTH`, `DISTRICT`, `DISTRICT_HOUSES`, `CITY_COIN_SPACING`,
      `CITY_LANDMARK_SALT`.
- [x] `const SLOTS: Array` per DEC-6, all 22 rows, five keys, in the table's order.
- [x] Pure static helpers, ALL allocation-light and safe per tick (`is_river_at` calls two
      of them every physics frame):
      `contains(x, z) -> bool`, `rect() -> Rect2`, `gate_point() -> Vector3`,
      `danube_distance(x, z) -> float`, `is_dry(x, z) -> bool`,
      `danube_wet(x, z) -> bool`, `plateau_top_at(x, z) -> float`,
      `road_approach_point(terminal: Vector2, x: float) -> Vector2`,
      `slot(index) -> Dictionary`.
      Route the segment-distance math through `Vector2`, never scalar — the fp32 rule.
- [x] A `ponytail:` comment recording the two deliberate deferrals: **no horizon
      impostors** (the bead says "may"; the tower's manager-parented lifetime is the one
      exception and this bead does not open a second), and **fauna is not excluded from
      the rect** (`fauna_manager.gd` reads `tower_site()` only; a herd crossing the city
      has no collision and joins no group, so it is ambience in the wrong place and not a
      bug — name the bead that should fix it).
- [x] Sanity: `grep -nE 'run_seed|randf|randi|hash\(' scripts/budapest_plan.gd` is EMPTY.

### Task 2: parity — CPU and GPU, in the same commit

- [x] `endless_terrain.gd`: the `biome_at` and `is_river_at` clauses of DEC-8, each with a
      comment saying it is one half of a two-language contract and naming the other half.
- [x] `ground.gdshader`: the uniforms, the vertex-stage band varying, the fragment-stage
      dry mask, the forced CITY albedo, and the "tower disc does not apply inside the
      city" clause. Carry the 240 m / 3 m oversampling arithmetic in the comment.
- [x] `_apply_biome_shader_params()`: push every new uniform, from `BudapestPlan`, beside
      the tower's two.
- [x] Run `wade_selfcheck` — it drives `is_river_at` through a stub and through the real
      thing; it must stay green.

### Task 3: the road — the terminal station, the four caps, the corridor

- [x] `ROAD_TERMINAL_X` const + `_road_terminal_k()` + its per-run cache, reset in
      `new_run()` beside the road cache reset.
- [x] The four consumer caps of DEC-7(i), each with a comment saying **why the cap is on
      the consumer and not on `_road_extend_to_x`** (its loops and all three binary-search
      callers assume the cache spans any X — capping it there hangs the forward loop).
- [x] `BudapestPlan.road_approach_point()` and `spawn_approach_coins_in_chunk`, called from
      `create_chunk` beside `spawn_coins_in_chunk` under the same `spawn_coins` flag.
      The line's EAST END is the Danube's BAND edge at z = 0, not `danube_wet()`: the
      avenue's river crossing is the Chain Bridge, whose deck is a `DRY_RECTS` row, so a
      wet test never fires and the trail would pave all of Pest.
- [x] Run `minimap_selfcheck` and `enemy_spawn_selfcheck` (its road walk crosses water and
      would notice a road that stopped existing). `enemy_spawn_selfcheck`'s boss-dispatch
      walk needed the cap: forty bosses is twelve kilometres of road and the road now ends
      at 1450 m, so it clamps per seed to `_road_terminal_k()` and buys its reach from a
      longer seed list (`BOSS_DISPATCH_SEEDS`) instead of from distance — 58 of 70 bosses
      placed, all six `BIOME_BOSS` bands and three river stations.

### Task 4: the streamer — `spawn_city_in_chunk`, plateaus, ramps, the avenue

- [x] `in_budapest(x, z)` on the terrain.
- [x] `spawn_city_in_chunk(chunk_pos, parent_chunk, obstacles, block_batch, block_body)`,
      inserted at DEC-10's exact point, emitting items 1, 2 and 5 (plateau, ramp, avenue)
      for now. Private RNG, never the chunk stream.
- [x] Slicing helper: a chunk-square ∩ Rect2 intersection returning the box centre and
      size, used by both the plateau and the ramp so "the slices meet flush" is true by
      construction rather than by review.
- [x] Footprints appended to `obstacles` per DEC-10.
- [x] Run `chunk_stream_selfcheck`.

### Task 5: the landmark slices — the keystone decision, built

- [x] `_spawn_city_landmarks_in_chunk`, DEC-1 in full: the per-slot seed, the scratch
      batch / body / chunk, the half-open clip on both halves, the accent reparent-or-free,
      the per-chunk footprint, the empty-builder skip.
- [x] The docstring states the DECISION and why (b) and (c) were rejected — this is the
      thing a future reader will want to re-litigate, and the bead note is the record.
- [x] Run `landmark_selfcheck` — it must be **byte-for-byte green**, because this task must
      not have touched `landmark_builders.gd`. Green, plus `chunk_stream_selfcheck`,
      `enemy_spawn_selfcheck` and `prop_selfcheck` as the regression. Measured on an
      ad-hoc driver over all 15 shipped slots: every box the unsliced builder emits is
      recovered exactly once across the slices, none twice, and each slot's accent
      exists exactly once.

### Task 6: spawner policy + the Danube crocodiles

- [x] The early returns of DEC-9, one per spawner, each with a one-line comment saying
      which of the city's five answers it is implementing and why this is NOT
      `tower_excludes()`.
- [x] `spawn_danube_crocodiles_in_chunk` with its own salt and primes; called from
      `create_chunk` inside the `spawn_crocodiles` branch.
- [x] Run `enemy_spawn_selfcheck` (checks 4 and 12 in particular) and `boss_selfcheck`.

### Task 7: the gate district + the difficulty clamp

- [x] `DISTRICT_HOUSES` built per DEC-11, sliced by chunk like everything else —
      by OWNERSHIP (the half-open test on the house centre), because a 4 m house
      needs no clipping the way a 268 m Parliament does.
- [x] The three jb7 CITY prop builders called for street dressing: seven pieces on
      spots DERIVED from the house table (one per gap, alternating sides, cycling
      the three), each off its own index-seeded RNG so a prop's shape does not
      depend on how many boxes its chunk happened to build first.
- [x] The one-line difficulty clamp of DEC-12, with its comment.
- [x] Run `enemy_spawn_selfcheck` and `hunt_director_selfcheck`. Both green, plus
      `chunk_stream_selfcheck`, `boss_selfcheck`, `landmark_selfcheck` and
      `prop_selfcheck` as the regression. Measured on an ad-hoc driver over the
      district's chunks: 16 house footprints + 7 prop footprints, 107 boxes and
      32 collision shapes in total, worst chunk 15 boxes.

### Task 8: `scripts/budapest_selfcheck.gd`

`extends SceneTree`, no `class_name`, `_initialize()` → `_run()` coroutine → `_report()`;
`_fail()` collects, `SELFCHECK OK` + `quit(0)` or `printerr("FAIL: ", …)` + `quit(1)`.
Constants read via `get_script_constant_map()`, **never** `node.get("CONST")` (which
answers null and passes vacuously). A terrain is `Node3D.new()` + `set_script(...)`; keep
it detached unless a check needs the tree. A section banner per check, numbered in the
banner and not in the function name, and a class header enumerating them as "WHAT IT
GUARDS" with a sentence each on how that failure is INVISIBLE in play.

- [ ] **1 — plan purity.** Read `scripts/budapest_plan.gd` as TEXT and fail on
      `run_seed`, `randf`, `randi` or `hash(`. Negative control: the same scan over a
      string that does contain one.
- [ ] **2 — the plan is well formed.** 22 slots; every slot disc inside the rect; no two
      slot discs overlap; every non-empty `builder` is a row of `CITY_LANDMARKS` and its
      `radius` equals the registry's; every empty-builder slot is exempt; every non-bridge,
      non-island slot centre is at least `DANUBE_HALF_WIDTH` from the polyline (nothing
      stands in the river); every bridge/island slot centre is inside its dry rect; the
      four plateau slots' `pos.y` equals their plateau's `top`.
- [ ] **3 — two identical regenerations.** Build the same city chunk twice, from two fresh
      terrains on two different `run_seed`s, and compare `var_to_bytes` of the whole batch
      (transforms and colours) and of every collision shape's transform. Two seeds, because
      an authored city must be **identical across runs**, not merely within one — which is
      a stronger statement than any other spawner in this game makes.
- [ ] **4 — per-chunk budgets, printed with their ceilings.** Over the whole rect: boxes
      per chunk (`CITY_CHUNK_BOX_BUDGET`), collision shapes per chunk
      (`CITY_CHUNK_SHAPE_BUDGET`), **exactly one `BlockMultiMesh` node** per city chunk
      (the one-draw-call invariant), and build milliseconds (`CITY_CHUNK_MS_BUDGET`).
      Print the measured worst chunk and its coordinates beside each ceiling; name the
      budget in the failure message the way `tower_interior_selfcheck` does. Start at
      boxes 240 / shapes 140 / 12 ms and **move the constant to the measured number plus
      headroom**, with the measurement in its comment.
- [ ] **5 — the slicing decision, asserted.** For `parliament` and `buda_castle`: build the
      builder ONCE unclipped, then build every overlapping chunk's slice, and assert the
      multiset union of slice boxes equals the unclipped set EXACTLY — every box present
      once, none twice, none lost. Then assert the same for colours (the per-slot seed
      rule), and that exactly one chunk received the accent node.
- [ ] **6 — CPU/GPU parity.** CPU: `biome_at` is CITY at 200 sampled points in the rect and
      is NOT forced one metre outside it; `is_river_at` is true mid-channel at each polyline
      vertex and each midpoint, false at the centre and all four corners of every dry rect,
      false 200 m either side of the band, and **the tower's disc still answers dry** (the
      city clause must not have moved above it). GPU: read `assets/shaders/ground.gdshader`
      as text and assert every new uniform is declared, that `CITY_SEG_MAX >= DANUBE.size()
      - 1` and `CITY_DRY_MAX >= DRY_RECTS.size()` (a ninth segment would silently truncate),
      and that `endless_terrain.gd`'s text pushes each new uniform through
      `set_shader_parameter`.
- [ ] **7 — the approach corridor reaches the gate, for 50 seeds.** Per seed: T exists and
      its X is within one station spacing of `ROAD_TERMINAL_X`; `road_approach_point` at
      `GATE.x` equals the gate within epsilon; the corridor is continuous (|Δz| per metre
      bounded) and has no kink at T (the first step off T is smaller than the last step
      before it, which is what the `smoothstep` join buys).
- [ ] **8 — the consumers stop at T.** Walk stations past T: `_road_coins_at` returns empty
      for every one; `_road_lateral_distance` answers INF well past T; no boss index
      dispatches past T (and `_boss_row_at` is never reached — assert by station index, and
      keep a positive control that bosses DO still spawn before T, or this measures an
      inert road); the minimap's gathered road count stops at T's screen position.
- [ ] **9 — the spawner policy.** Build ~60 chunks spread over the rect: zero props, zero
      structures, zero artifacts, zero camps, zero geo landmarks, zero chests, zero biome
      content; **at least one hunter** across the sweep (a positive control — a policy that
      silently killed hunters would pass every negative); crocodiles only in chunks whose
      centre is `danube_wet`, and every crocodile found is `species == "crocodile"` and
      stands on wet XZ; **no other species anywhere inside**.
- [ ] **10 — the crocodile stream A/B, `enemy_spawn_selfcheck` check 12's methodology.**
      Build a field of chunks OUTSIDE the rect twice — once with the Danube spawner and the
      city streamer live, once with them off — and compare the crocodile signature
      (`name`, `species`, `position`, `rotation.y`) through `var_to_bytes`. Both halves,
      like check 12: the field must be byte-identical **and** must have contained
      crocodiles, or the check compared two empty signatures and proved nothing.
- [ ] **11 — the plateau ramps.** Slope ≤ `TowerInterior.PLAN_RAMP_MAX_SLOPE` **read from
      that script**, never restated; the ramp's low end is at y = 0 and its high end is
      flush with its plateau's `top` (both within a centimetre); the ramp rect touches its
      plateau's rect edge; a chunk-sliced ramp's top surface agrees with the unsliced
      plane at both slice ends.
- [ ] **12 — the difficulty clamp.** Drive the arithmetic at both ends: at x = 3800 the
      factor equals the factor at x = 1600, and at x = -3800 it does not.
- [ ] **13 — the avenue is walkable.** The avenue's 16 m corridor from the gate to the
      Danube's west bank crosses no plateau rect and no landmark footprint disc, and no
      chunk emits a colliding box inside it. (The full one-hero reachability audit over
      all 22 slots is bead .10; this is the one corridor .3 promises.)

### Task 9: `CLAUDE.md`

- [ ] In the "**The tower (GastroDefense HQ) is the one exception and must stay one**"
      paragraph, add the city's DIFFERENT lifetime model so the rule stays true: Budapest
      is **authored data streamed through ordinary chunks** — one const plan
      (`budapest_plan.gd`, the `tower_plans.gd` idiom: no seed, no hash, no `randf`), read
      by `create_chunk`, built through `create_box()` / `block_batch` / the chunk's single
      `BlockCollision`, chunk-parented and therefore freed by chunk unloading. A 2 x 2 km
      city is 1,936 cells against the web build's 49-chunk residency, so it CANNOT be a
      second manager-parented shell — the tower stays the one exception precisely because
      the city is not one.
- [ ] Record, in the same place or beside the determinism rules: the **slicing decision**
      (a big landmark's builder is re-run per overlapping chunk and clipped by box centre,
      off a seed that is a function of the SLOT and nothing else), the **four road
      consumers capped at T** and why `_road_extend_to_x` is not, and the **per-system
      spawner policy** (hunters ON, Danube crocodiles ON on their own stream, everything
      else procedural OFF, coins authored) as explicitly NOT `tower_excludes()`.
- [ ] Add `budapest_selfcheck` to the self-check list in the Commands block, with a
      one-line description of what it asserts in the style of its neighbours.

### Task 10: the full sweep

- [ ] `godot --headless --path . --import`
- [ ] Run **every** `scripts/*_selfcheck.gd`. All must print `SELFCHECK OK` and exit 0.
- [ ] `mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html`
      — the web export is the performance target and a shader that fails to compile under
      `gl_compatibility` fails HERE and nowhere else.
- [ ] `git status` clean apart from the intended files. **Never** commit `.beads/` churn to
      this branch.
