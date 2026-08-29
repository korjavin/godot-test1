# Tower phase 14 — hand-planned ASCII storey plans, the builder, the flood-fill audit

## Overview

Bead `godot-test1-3iy.14` (epic `godot-test1-3iy`, phase 14, size **huge**). Owner
ruling item 3 (2026-08-29): *"100x size, multiple rooms"*, interpreted on the epic as
**100x usable FLOOR AREA** — 10 storeys of ~80 x 80 m, ~100–150 hand-planned rooms,
**no seed, ever**.

This phase builds **the machinery that makes a hand-planned storey cheap**, and ships
the first three new storeys with it:

1. **`scripts/tower_plans.gd`** (NEW, pure data) — ASCII floor plans, one character
   per cell, in the `SPECIES` / `TOWER_GRAPH` idiom: a `const` dict of plain dicts,
   no class hierarchy, no `Resource`, no logic. **A designer edits text.**
2. **A builder in `tower_interior.gd`** that walks a grid and emits boxes into the
   existing per-storey merged `ArrayMesh`, with **2-D run-length merged walls** so a
   40-cell wall is one box and not forty.
3. **Two new audit teeth in `tower_selfcheck.gd`** — a grid flood-fill per storey (the
   corridor-level guarantee the graph walk cannot give) and a bidirectional
   plan-room ↔ graph-row binding — plus an **adjacency index** in `_reach` so the
   15-subset audit stays fast as the graph grows past 40 rooms.
4. **Storeys 3, 4 and 5 authored** — office floors in the 30 m annulus the phase-13
   shell opened up, reached by a grand ramp from the annulus floor.

**The 15-subset reachability audit (`tower_selfcheck`) is LOAD-BEARING and must stay
green.** Every new room in this phase hangs off ungated edges, so the audit's *result*
does not change — only its size. That is deliberate: this phase adds space, phase 15
adds riddle gates, phase 16 moves the cell block.

## Context (from discovery — READ THIS BEFORE WRITING CODE)

### The building as it stands on `origin/master` (phases 12 + 13 are merged)

- `scripts/tower_shell.gd` — `OUTER_HALF 40.0`, `WALL_THICK 1.2`, `STOREY_HEIGHT 5.0`,
  `STOREYS 10`, `WALL_HEIGHT 50.0`, `ROOF_THICK 2.0` (sealed lid, top at 52 m),
  `KEEP_HALF 10.0`, `KEEP_HEIGHT 11.0`, `DOOR_HALF_WIDTH 3.0`, `DOOR_HEIGHT 4.0`,
  `YARD_HALF 45.0`, `BOX_BUDGET 16`.
  `boxes()` builds **the same six-box ring twice**: the 80 m envelope and the phase-3
  20 m keep preserved inside it, both **open-topped**, both with their doorway hole on
  the **same +X line** (`|z| <= 3`, `y 0..4`). Then one `Roof` slab over the whole
  footprint and a `Beacon` on it.
  **The annulus between the two rings — 28.8 m of clear floor on every side, open to
  the roof 50 m up — is empty. That is what this phase furnishes.**
- `scripts/tower_interior.gd` (2903 lines) — the phase-3/8/11 building **inside the
  keep**: `INNER_HALF = KEEP_HALF - WALL_THICK = 8.8`, `SLAB_Y 4.6`, `SLAB_THICK 0.4`,
  two storeys. `boxes()` (`:939`) is the single source of the plan;
  `_ramp_box()` (`:1149`) and `_wing_boxes()` (`:1180`) are its two helper tables.
  `_ready()` (`:1447`) builds two `Floor%d` containers, batches every box that is not
  in `MOVING_PARTS` and has no `spin` into one `merged_mesh()` per storey, and adds
  one `CollisionShape3D` per solid box to **one** `InteriorCollision` `StaticBody3D`.
  `BOX_BUDGET 60`, `DRAW_BUDGET 23`, `DRAW_RADIUS 60.0`, `FLOOR_HYSTERESIS 0.8`.
  `_update_visibility()` (`:2620`), `current_floor()` (`:2671`), `_floor_visible()`
  (`:2676`), `merged_mesh()` (`:2731`), `_emit_box()` (`:2762`).
- `scripts/tower_graph.gd` — `TOWER_GRAPH` (`:167`): **11 rooms, 15 edges, 8 gates,
  2 entries, 2 scars**. Rooms are `{built, quest, cell, parts, note}`; edges are
  `{id, a, b, gate, built}`, `gate: ""` for an open way through.
- `scripts/tower_selfcheck.gd` — the softlock audit. `_check_graph_matches_the_building`
  (`:165`) binds graph rows to `TowerInterior.boxes()` **by colour, in both
  directions**. `_reach` (`:762`) is BFS and today re-scans **every edge per pop**.
  `_edges_for` (`:714`) builds the edge set per (story, scar).
- `scripts/tower_interior_selfcheck.gd` — 15 checks. The four that this phase must
  keep honest: **check 1** `_check_plan_fits_the_shell` (`:217`, budget + fits inside
  `INNER_HALF` + floor index in `{0,1}` + doorway stays a hole), **check 2**
  `_check_no_jump_gated_climb` (`:303`, apex recomputed from `player_controller`),
  **check 3** `_check_ramp_is_the_stair` (`:504`, deck end points measured off the real
  transform), **check 4** `_check_headroom_clears_the_camera` (`:560`), **check 5**
  `_check_node_shape` (`:677`, `DRAW_BUDGET`, one `StaticBody3D`, one shape per solid
  box, batched boxes verified **corner by corner**), **check 9**
  `_check_visibility_gating` (`:1112`).

### Measured baseline on this branch (2026-08-29, after `--import`)

```
tower_selfcheck            0.37 s   "11 rooms, 15 edges, 8 gates, 2 entries, 2 scars — 15 subset walks clean"
tower_interior_selfcheck  10.96 s
tower_shell_selfcheck      0.66 s
```

Record the post-change numbers in the same shape; the bead's acceptance is
`tower_selfcheck` **under 30 s**.

### Hard invariants this work must not break

- **No `run_seed`, no `hash()`, no RNG anywhere in the tower.** Owner ruling 1:
  "plan it once and forever". `grep -n 'run_seed\|randf\|randi\|hash(' scripts/tower_*.gd`
  must stay empty of new hits.
- **One `StaticBody3D` for the whole interior**, one `CollisionShape3D` per solid box.
- **One `MeshInstance3D` per storey** for static geometry (`merged_mesh`); only parts
  that move or change colour get their own node, and every one of those spends a
  `DRAW_BUDGET` slot.
- **No jump-gated traversal.** Apex is 3.6125 m (`player_controller`, recomputed by
  check 2). Stairs are **ramps**; `CharacterBody3D` has no step-up, so a tread of any
  height is a wall.
- **No shadows** on interior geometry (`_no_shadow`), web `gl_compatibility` target.
- **The flat-world invariant is untouched** — this is all interior, above y = 0.
- **`tower_selfcheck` stays green over all 15 subsets.**

### Files this phase touches, and the two it must NOT

- `scripts/tower_plans.gd` — **NEW**.
- `scripts/tower_interior.gd` — the builder, the floor table, the budgets, `_ready()`.
- `scripts/tower_graph.gd` — new room and edge rows only.
- `scripts/tower_selfcheck.gd` — adjacency index, extended check 1, new flood-fill check.
- `scripts/tower_interior_selfcheck.gd` — generalize checks 1–5 and 9 over storeys.
- `CLAUDE.md` — one new subsection in the tower block (`:194-270`).

> ⛔ **DO NOT TOUCH `scripts/weather_manager.gd` or `scripts/player_controller.gd`.**
> Another developer is concurrently fixing rain-indoors (bead `godot-test1-...li2`) in
> those two files plus a small `sheltered()` query in `scripts/tower_shell.gd`.
> **Keep `tower_shell.gd` edits to zero if at all possible** — nothing in this plan
> needs to change it. Read constants from it; do not edit it.

## The design, decided (do not re-derive these — they are rulings for this plan)

### D1. Where the new storeys go, vertically

The keep is 11 m tall and open-topped. The new storeys sit **on top of it and across
the whole 80 m footprint**, so the annulus becomes an 11 m entrance hall and the keep
becomes a solid core standing in it.

| floor index | what it is | walking surface y |
|---|---|---|
| 0 | entry hall / courtyard / wing (keep, phase 3+8) + **the annulus** | 0.0 |
| 1 | upper landing / checkpoint room (keep, phase 3) | 4.6 (`SLAB_Y`) |
| 2 | **storey 3** (NEW) | 11.0 (`KEEP_HEIGHT`) |
| 3 | **storey 4** (NEW) | 16.0 |
| 4 | **storey 5** (NEW) | 21.0 |

Derived, never restated:

```gdscript
## The walking surface of every storey, in interior-local metres. Index is the
## `floor` a box declares and the container `_update_visibility` toggles.
##
## The first two are the phase-3 keep, unchanged. The rest sit ON the keep's open
## top (KEEP_HEIGHT) and rise on the shell's own storey grid, so a storey is not a
## number written here twice — it is the shell's STOREY_HEIGHT counted off the keep.
const FLOOR_Y: Array[float] = [0.0, SLAB_Y, TowerShell.KEEP_HEIGHT,
    TowerShell.KEEP_HEIGHT + TowerShell.STOREY_HEIGHT,
    TowerShell.KEEP_HEIGHT + 2.0 * TowerShell.STOREY_HEIGHT]
```

Each plan storey carries **its own floor slab** (`SLAB_THICK` 0.4 under the walking
surface), spanning the full inner footprint minus its stairwell hole. Clear height is
therefore `STOREY_HEIGHT - SLAB_THICK = 4.6 m` for storeys 3 and 4.

**Storey 5 has no ceiling.** It is open to the sealed roof 29 m above, and that is the
honest state of a building whose storeys 6–10 are phases 16+. Write it down as a
`ponytail:` note. It costs nothing: a 4.6 m wall top is 1 m above the jump apex, so
nothing up there is climbable, and check 4's headroom question passes trivially.

### D2. The grid

```gdscript
## The plan grid: 40 x 40 cells across the shell's INNER faces.
##
## The cell size is DERIVED and not authored — 40 cells have to span exactly the
## clear width, or the plan's outer ring stops meeting the wall it is drawn against
## and every storey gets a 0.8 m ledge nobody planned. 1.94 m is a corridor of two
## cells at 3.88 m and a small office at 4 x 5 cells; the bead asked for "~2 m".
const PLAN_GRID: int = 40
const PLAN_HALF: float = TowerShell.OUTER_HALF - TowerShell.WALL_THICK   # 38.8
const PLAN_CELL: float = 2.0 * PLAN_HALF / float(PLAN_GRID)              # 1.94
```

- `rows[r][c]`: `r` runs **-Z → +Z**, `c` runs **-X → +X**.
- centre of cell `(c, r)`: `x = -PLAN_HALF + (c + 0.5) * PLAN_CELL`,
  `z = -PLAN_HALF + (r + 0.5) * PLAN_CELL`.

### D3. The characters

| char | meaning | walkable | emits |
|---|---|---|---|
| `#` | wall — **full storey height**, floor slab to ceiling | no | one box (after merging) |
| `.` | floor, no room label (corridors, lobbies) | yes | nothing (the slab is under it) |
| letter | a room's cells; the letter maps to a `TOWER_GRAPH` room id via the storey's `rooms` dict. `A`–`Z` **except** `S`, `P`, `G`, `D` | yes | nothing |
| `S` | the up-ramp's lane, arriving on this storey from the storey named by `from` | yes (it *is* the ramp) | one ramp box + the slab hole |
| `s` | the landing at the head of that ramp — the flood-fill's start cell | yes | nothing |
| `P` | a pad. Must be 4-adjacent to at least one room-letter cell | yes | one 0.1 m plate box, `COLOR_SYSTEM` |
| `G` | a guard post. **Parsed and validated, spawns nothing this phase** — phase 17 owns population | yes | nothing |
| `D` | a gate slot; the cell key `"<c>,<r>"` must appear in the storey's `gates` dict and name a real `TOWER_GRAPH` gate row. **No storey authored in this phase has one** (phase 15 brings riddles) | yes | nothing this phase |

### D4. The storey row

```gdscript
const STOREYS: Array[Dictionary] = [
    {
        "floor": 2,                  # index into TowerInterior.FLOOR_Y
        "from": 0,                   # the floor its ramp climbs FROM
        "landing": "s3_landing",     # the TOWER_GRAPH room the `s` cells are
        "rooms": {"A": "s3_...", ...},   # room letter -> TOWER_GRAPH room id
        "gates": {},                 # "<c>,<r>" -> TOWER_GRAPH gate id
        "rows": [ ... 40 strings of 40 characters ... ],
        "note": "...",
    },
    ...
]
```

Plus two tiny accessors and nothing else — `tower_plans.gd` is **data**, the way
`tower_graph.gd` is:

```gdscript
static func storey(floor_index: int) -> Dictionary   # or {} 
static func floors() -> Array[int]                   # [2, 3, 4], in STOREYS order
```

### D5. The ramps

**Every ramp in this phase runs along X.** That is not taste: the interior's one
rotated body is X-running, and check 1, `_ramp_underside_at` and check 3 all reason in
the XY plane about `rot.z`. A Z-running ramp would need a second copy of all three.

- The `S` cells form **exactly one solid rectangle whose long axis is X**, 2 cells
  deep (3.88 m — the existing `RAMP_WIDTH` is 2.8, so this is generous).
- The `s` landing cells sit orthogonally against **one short end** of that rectangle.
  The ramp rises **toward** the `s` end; that is how the direction is derived.
- The deck's foot is at `FLOOR_Y[from]` at the far edge of the far `S` cell; its head
  is at `FLOOR_Y[floor]` at the near edge of the `s` cell. Build the box **by its top
  face, offset half a thickness along the deck's own normal** — reuse the arithmetic
  in `_ramp_box()` (`:1149`) verbatim; a straight-down offset leaves a 12 cm step at
  the top and the stair simply ends in a wall.
- **Slope ceiling.** The proven ramp is `SLAB_Y / (SLAB_X0 - RAMP_X0) = 4.6 / 8.0 =
  0.575` (29.9°). Every plan ramp must be **no steeper**. Cell counts that satisfy it:

  | storey | rise | min run | cells (`x 1.94`) | slope | angle |
  |---|---|---|---|---|---|
  | 3 (from floor 0) | 11.0 | 19.13 m | **10** = 19.40 m | 0.5670 | 29.55° |
  | 4 (from floor 2) | 5.0 | 8.70 m | **5** = 9.70 m | 0.5155 | 27.28° |
  | 5 (from floor 3) | 5.0 | 8.70 m | **5** = 9.70 m | 0.5155 | 27.28° |

  Declare `PLAN_RAMP_MAX_SLOPE: float = SLAB_Y / (SLAB_X0 - RAMP_X0)` — derived from
  the proven ramp, never a fresh 0.575 — and assert it in the self-check.
- **The stairwell hole is DERIVED, never authored.** The builder computes, in metres,
  the point on the deck where it is `SLAB_THICK + PLAN_HEADROOM` below the storey's
  walking surface, and the hole is the ramp's lane from there to the head, **rounded
  outward to whole cells**. `PLAN_HEADROOM: float = 2.2` (the 2.0 m capsule plus
  margin) — so a player walking up never hits the slab they are about to stand on.
  The slab is then **the inner footprint minus that one rectangle = at most 4 boxes.**
  Deriving it is what makes "adjacent storeys' stair cells coincide in XZ" true by
  construction instead of by review.
- **Storey 3's ramp is at ground level in the annulus.** Its lane must be entirely
  **outside the keep** (`max(|x|, |z|) > KEEP_HALF` at every corner, with a 1 m margin)
  and clear of the door corridor (`x in [KEEP_HALF, PLAN_HALF]`, `|z| <= DOOR_HALF_WIDTH + 1`),
  or you cannot walk from the outer door to the keep door. Assert both.
- **Storey 4's and 5's `S` lanes must be walkable cells on the storey below** (`.`,
  `s`, `P`, `G`, `D` or a room letter — never `#`). Assert it. That is the bead's
  "adjacent storeys' stair cells coincide in XZ", in the only form that can be wrong.

### D6. Where the annulus lives in the graph

The annulus is not a `TOWER_GRAPH` room today; the front door's entry row lands
straight in `entry_hall`. Storey 3's ramp starts in the annulus, so the annulus needs a
row.

- **New room `outer_hall`** — "the 80 m entrance hall the phase-13 envelope opened up;
  the keep stands in the middle of it".
- **New edge `hall_outer`** — `entry_hall <-> outer_hall`, `gate: ""` (the keep
  doorway; both rings' holes are on one line).
- **New edge `outer_s3`** — `outer_hall <-> s3_landing`, `gate: ""` (the grand ramp).
- **Leave `entries` alone.** They still land in `entry_hall`, which is strictly harsher
  than the truth and changes no audit result.

Every new room this phase adds is reachable by every subset through ungated edges, so
the 15-subset audit's verdict is unchanged. **That is the intent** — the bead says the
new storeys are optional space and the four rescue spines stay through the existing
cell block until phase 16.

### D7. Which function returns what

`boxes()` **stays exactly as authored** — the keep, floors 0 and 1, `BOX_BUDGET 60`.
The plan geometry is a sibling:

```gdscript
static func plan_boxes(floor_index: int) -> Array[Dictionary]   # one storey, built + cached
static func all_boxes() -> Array[Dictionary]                    # boxes() + every plan storey
```

`_ready()` changes by **one word** — iterate `all_boxes()` instead of `boxes()`. Plan
boxes are never in `MOVING_PARTS` and never carry `spin`, so they take the batch path
and the single-body collision path with no new branch. Size `batched` and the `Floor%d`
container loop off `FLOOR_Y.size()`.

Budgets:

- `BOX_BUDGET` — **unchanged at 60**, still the keep's, still biting on furniture.
- `PLAN_BOX_BUDGET` — **NEW, per storey**, set from the measured merged count with a
  comment carrying the number and what it stops (see Task 6).
- `DRAW_BUDGET` — **23 → 26**, and the comment says exactly why: three more storey
  batches, one `MeshInstance3D` each, no new `MOVING_PARTS` entry. A plan storey must
  cost exactly one mesh; **use no glow colours on plan storeys**, so `merged_mesh`
  emits one surface per storey rather than two.

## Development Approach

- **Testing approach**: no unit-test framework exists in this project. Verification is
  `godot --headless --path . --import`, the headless self-checks, and a short headless
  boot of `scenes/main.tscn`.
- Complete each task fully before moving to the next.
- **Keep the teaching-density comments and explicit type hints.** This codebase is
  written to be read (CLAUDE.md "Conventions"), and the tower files are the densest in
  it. Match `tower_graph.gd` and `tower_interior.gd`: say *why*, carry the measured
  numbers, and record every deliberate simplification as a `ponytail:` comment naming
  its ceiling and upgrade path.
- **Do not invent scope.** No guards on the new storeys, no gates, no lights, no
  furniture, no lift. Those are phases 15, 16 and 17.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- `godot --headless --path . --import` first (a fresh worktree has no `.godot`).
- `godot --headless --path . --script res://scripts/tower_selfcheck.gd` — must print
  `SELFCHECK OK`, exit 0, **in under 30 s**, with all 15 subsets, the new flood-fill
  check and the adjacency index.
- `godot --headless --path . --script res://scripts/tower_interior_selfcheck.gd`
- `godot --headless --path . --script res://scripts/tower_shell_selfcheck.gd`
- `godot --headless --path . --script res://scripts/tower_site_selfcheck.gd`
- `godot --headless --path . --script res://scripts/capture_selfcheck.gd`
- `godot --headless --path . --script res://scripts/chunk_stream_selfcheck.gd`
- `godot --headless --path . --script res://scripts/perf_selfcheck.gd`
- `godot --headless --path . scenes/main.tscn --quit-after 120` — clean boot.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Keep plan in sync with actual work done

---

## Implementation Steps

### Task 1: `scripts/tower_plans.gd` — the format, with one throwaway storey

- [x] Create `scripts/tower_plans.gd`: `class_name TowerPlans extends RefCounted`.
      Header block in `tower_graph.gd`'s voice, carrying:
      - **what this file is**: the hand-planned layout the owner ruled for
        ("plan it once and forever"), in the only level-editor a repo with no level
        editor has — text. A designer edits `rows`; nothing is generated, nothing is
        seeded, nothing is hashed.
      - **the grid contract** (D2) with the derivation of `PLAN_CELL` written out and
        the reason it is derived rather than authored.
      - **the character table** (D3), verbatim, as the reference a designer reads.
      - **the storey row's keys** (D4).
      - **the two things a new storey costs**: one `STOREYS` row plus its
        `TOWER_GRAPH` room and edge rows. **No builder edit, ever** — that is the
        bead's acceptance criterion and this comment is where it is promised.
- [x] Constants: `PLAN_GRID`, `PLAN_HALF`, `PLAN_CELL` (D2) — put them **here**, and
      have `tower_interior.gd` read them from here, so the grid has one home.
      `WALL_CHAR`, `FLOOR_CHAR`, `STAIR_UP_CHAR`, `LANDING_CHAR`, `PAD_CHAR`,
      `POST_CHAR`, `GATE_CHAR` as named consts — the self-check reads them rather
      than restating the characters.
- [x] `const STOREYS: Array[Dictionary]` with **one placeholder storey** for now
      (floor 2, a bare box with a ramp, a landing and two rooms) so Tasks 2–7 have
      something to build and check. The real content lands in Task 8.
- [x] `static func storey(floor_index: int) -> Dictionary` and
      `static func floors() -> Array[int]`. Nothing else. **No logic in this file.**
- [x] Sanity: `grep -n 'run_seed\|randf\|randi\|hash(' scripts/tower_plans.gd` is empty.

### Task 2: The builder in `tower_interior.gd`

- [x] Add the floor table `FLOOR_Y` (D1) with its comment, and
      `static func floor_y(index: int) -> float`. Replace the two hard-coded `2`s in
      `_ready()` (the container loop and `batched`) with `FLOOR_Y.size()`.
- [x] Generalize `current_floor(local_y: float) -> int`: the **highest** index whose
      `FLOOR_Y[i] - FLOOR_HYSTERESIS <= local_y`. It must still answer 0 at y = 0 and
      1 at `SLAB_Y` (check 9 asserts both, unchanged). Keep it pure and
      allocation-free — it runs every `_process`.
      Leave `_floor_visible` **exactly as it is**: `absi(index - current) <= 1` was
      written to be correct at any storey count and this is the phase that proves it.
- [x] `static func _plan_ramp(plan: Dictionary) -> Dictionary` — the ramp box for one
      storey, derived per D5 from the `S` rectangle and the `s` landing. Its `floor`
      is the **lower** of the two storeys it joins (the existing convention: a box you
      stand on belongs to the floor it carries, which is why the phase-3 ramp is floor
      0), so the ±1 window shows it from either end.
      **Reuse `_ramp_box()`'s deck arithmetic** — factor the shared part into
      `static func _deck_box(name, foot: Vector2, head: Vector2, z: float, width: float,
      floor_index: int) -> Dictionary` and have BOTH `_ramp_box()` and `_plan_ramp()`
      call it. One copy of "place the box by its top face along the deck's normal".
      Confirm `_ramp_box()`'s output is byte-identical afterwards (check 3 will say so).
- [x] `static func _plan_slab(plan: Dictionary) -> Array[Dictionary]` — the storey's
      floor slab as **the inner footprint minus the derived stairwell hole**, at most
      four boxes (skip any that comes out zero-width). `SLAB_THICK` thick, top at
      `FLOOR_Y[floor]`, `collide: true`, `COLOR_STONE`.
- [x] `static func _merge_walls(plan: Dictionary) -> Array[Dictionary]` — the 2-D
      run-length merge, and the whole reason a 40 x 40 grid is affordable:
      1. per row, maximal horizontal runs of `#`;
      2. then merge runs in adjacent rows that have **identical `[c0, c1]`** into one
         box.
      A horizontal wall is one box and **so is a vertical one** (a stack of 1-wide runs
      with the same extent). Walls run from the slab's top face to the storey's ceiling
      (`STOREY_HEIGHT - SLAB_THICK` tall), `collide: true`, `COLOR_STONE`.
      Comment the *why*: run-length on rows alone leaves a 40-cell vertical wall as 40
      boxes, and 40 boxes is 40 collision shapes and a budget nobody can hold.
- [x] `static func _plan_pads(plan: Dictionary) -> Array[Dictionary]` — one 0.1 m plate
      per `P` cell, `COLOR_SYSTEM`, `collide: false`.
      `# ponytail: geometry only. A purge pad with no guards to scare is a dead Area3D;
      the trigger and the flee wiring land in phase 17 with the guards they act on.`
- [x] `static func plan_boxes(floor_index: int) -> Array[Dictionary]` — slab + walls +
      ramp + pads, names prefixed `S%dPlan...` and **globally unique** (check 1
      asserts). Cache it in a `static var` dictionary; `boxes()` is called many times
      per self-check run and a 40 x 40 walk per call is waste.
- [x] `static func all_boxes() -> Array[Dictionary]` — `boxes()` then every
      `TowerPlans.floors()` storey in order. **`boxes()` itself is not touched.**
- [x] `_ready()`: iterate `all_boxes()`. One word. Verify nothing else needed a branch.
- [x] `PLAN_BOX_BUDGET` and `DRAW_BUDGET 23 -> 26` per D7, both with comments carrying
      the measured numbers (fill them in after Task 8 measures for real).


> Measured on the placeholder storey: keep 56 boxes, plan storey 21
> (4 slab + 14 merged walls + 2 pads + 1 ramp), ramp 29.55 deg / slope 0.5670
> against the proven 0.5750. `_ramp_box()` output is unchanged
> (`pos=(-4.400306, 2.126619, 7.4)`, `rot.z=0.521834`). `PLAN_BOX_BUDGET` is
> **provisional at 120** and gets its real number in Task 8, as planned.
> ⚠️ `tower_interior_selfcheck` is red until Task 6 generalizes it (shape count
> over `boxes()` not `all_boxes()`; empty `Floor3Batch`/`Floor4Batch` until Task 8
> authors those storeys). `tower_selfcheck`, `tower_shell_selfcheck` and
> `capture_selfcheck` are `SELFCHECK OK`.

### Task 3: The adjacency index in `tower_selfcheck._reach`

- [x] `_reach` currently re-scans **every** edge for every popped room. Replace the
      `edges: Array` parameter with an **index**: `Dictionary` of
      `room_id -> Array[Dictionary]` (the edges touching that room), built **once per
      (story, scar)** and memoized beside `_edges_for`'s result.
      - `_edges_for(story, scar)` gains a small cache keyed by `story.id + "|" + scar.id`.
      - New `_index_for(story, scar) -> Dictionary`, memoized the same way.
      - `_reach(index, start, free, mode, skip_gate)`; `_reaches_any` and every other
        caller updated.
- [x] Comment the *why* with the numbers: today's walk is O(rooms x edges) per pop; at
      the epic's 150 rooms / 200 edges that is 30 000 edge tests per pop and the file
      stops finishing. The index makes it O(degree).
- [x] Verify the audit's **verdict is unchanged**: `tower_selfcheck` still prints
      `SELFCHECK OK` with the same room/edge/gate counts before Task 5 adds any rows.

### Task 4: Extend check 1 — plan rooms and gates bound to graph rows, both ways

In `tower_selfcheck._check_graph_matches_the_building`:

- [x] **Plan → graph.** For every `TowerPlans.STOREYS` row: every value in its `rooms`
      dict, plus its `landing`, must be a `TOWER_GRAPH` room row with `built: true`;
      every value in its `gates` dict must be a `TOWER_GRAPH` gate row.
- [x] **Graph → plan.** Every room id claimed by any plan must be claimed by **exactly
      one** plan storey (no room on two floors), and every letter used in a storey's
      `rows` must appear in that storey's `rooms` dict — and vice versa, a `rooms`
      entry whose letter appears in no row is a row about nothing.
- [x] **Gate slots.** Every `D` cell's `"<c>,<r>"` key must be in the storey's `gates`
      dict, and every `gates` key must name a `D` cell. (No storey in this phase has
      one; the check is what makes phase 15 cheap and is what stops a `D` being drawn
      and forgotten.)
- [x] **The graph agrees the storey is walkable.** For each plan storey, one `_reach`
      from its `landing` with **all four heroes free** must reach every room the storey
      claims. This is the graph half of the flood-fill's geometry half; together they
      are what "the graph the selfcheck walks IS what the player walks" means.
- [x] Keep the existing colour binding untouched, but feed it `TowerInterior.boxes()`
      **and** the plan boxes — a plan box painted a gate or room colour must still be
      claimed by a row. (This phase paints none, which is the point: the check must be
      the reason that stays true.)

> Done. `tower_selfcheck` is `SELFCHECK OK` in 0.3 s: **15 rooms, 19 edges**, 8
> gates, 2 entries, 2 scars, 15 subset walks clean — the verdict is unchanged, only
> the size, exactly as D6 predicted.
> ➕ The placeholder storey's graph rows had to land here rather than in Task 8:
> check 1 now REFUSES a plan whose letters name no room, so `outer_hall`,
> `hall_outer`, `outer_s3`, `s3_landing`, `s3_office_a`/`_b` and their two ungated
> edges are in `tower_graph.gd` now (all `built: true`, all ungated — the D6 rows
> plus the placeholder's two offices). Task 8 authors the real storeys against them.
> Negative controls run by hand, each failing with the sentence a designer can act
> on: an unknown room id, a room on two floors, a `rooms` letter drawn nowhere, a
> `D` drawn and forgotten, a `gates` key naming no `D`, and an office the graph does
> not join to its landing.
> The colour binding now reads `TowerInterior.all_boxes()` and also fails a
> duplicate box name — the keep and every plan storey share one namespace.

### Task 5: New check — the grid flood-fill

New `_check_plans_are_walkable()` in `tower_selfcheck.gd`, registered alongside the
others, with a header block explaining **what the graph audit cannot see**: the graph
says two rooms are joined; only the grid says the corridor between them actually
exists and is not walled off by a typo.

- [x] **Well-formedness first**, per storey: exactly `PLAN_GRID` rows, each exactly
      `PLAN_GRID` characters, every character in the legal set (D3), exactly one solid
      rectangular `S` region with its long axis on X, `s` cells against one short end
      of it, exactly two `P` cells, every `P` 4-adjacent to a room-letter cell.
- [x] **Flood fill** 4-connected over every non-`#` cell from the `s` landing. Assert
      every room-letter cell, every `S` cell, every `P`, `G` and `D` cell is reached.
      Report the first unreachable cell as `(c, r)` **and** its world XZ, so a designer
      can find it.
- [x] **The stair coincides with the storey below** (D5): for a storey whose `from` has
      a plan, every `S` cell must be a walkable cell on that plan. For storey 3
      (`from: 0`, no plan), every `S` cell must be outside the keep by 1 m and clear of
      the door corridor.
- [x] **The ramp is not steeper than the proven one**: derive slope from the `S`
      rectangle's length and the two `FLOOR_Y` values, assert `<= PLAN_RAMP_MAX_SLOPE`
      and `< 40°`. Print the angle per storey.
- [x] **A negative control per assertion.** House style: mutate a copy of a plan (wall
      off a room, move the landing, shorten the ramp lane by a cell, drop a `rooms`
      entry) and assert the check *fails* — a flood-fill that passes on a broken plan
      is worse than no flood-fill. Do this by building the mutated dict in the check
      and calling the same helper, never by editing `tower_plans.gd`.
- [x] Print the summary line in the file's voice, e.g.
      `tower plans: 3 storeys, N rooms, M cells walkable, ramps 29.6/27.3/27.3 deg`.

### Task 6: Generalize `tower_interior_selfcheck` over storeys

- [x] **Check 1** `_check_plan_fits_the_shell`:
      - keep boxes (`boxes()`): bounded by `INNER_HALF`, `floor` in `{0, 1}`, budget
        `BOX_BUDGET` — **unchanged assertions**;
      - plan boxes (`plan_boxes(i)`): bounded by `TowerPlans.PLAN_HALF`, `floor` equal
        to the storey's own index, per-storey count `<= PLAN_BOX_BUDGET`;
      - **name uniqueness across `all_boxes()`**, and the doorway-stays-a-hole test
        over `all_boxes()`;
      - the `y <= TowerShell.WALL_HEIGHT` test over `all_boxes()`;
      - print one line per storey: boxes, budget, clear height.
- [x] **Check 2** `_check_no_jump_gated_climb`: keep the existing keep sweep untouched,
      then add the plan half. The plan half is **one assertion, not a sweep**, because
      the builder makes it structural: **every plan wall box runs from its storey's
      floor to its storey's ceiling** (`STOREY_HEIGHT - SLAB_THICK` tall, bottom at
      `FLOOR_Y[i]`), so no wall top is a ledge below the ceiling and nothing on storey
      *i* is a step onto storey *i+1*. Assert exactly that, and assert the wall height
      exceeds the recomputed jump apex, so a walled-off room can never be entered over
      the top. Write down *why* the structural assertion is stronger than a sweep.
- [x] **Check 3** `_check_ramp_is_the_stair`: loop over **every** box in `all_boxes()`
      carrying `rot`. For each, rebuild the deck's two end points from `pos`/`rot`/`size`
      exactly as today and assert foot and head land on their two `FLOOR_Y` values and
      at their expected X, that the angle is `< 40°`, and that the slope is
      `<= PLAN_RAMP_MAX_SLOPE`. The existing keep-ramp assertions must survive verbatim
      as the `from 0 -> 1` case. Print one line per ramp.
- [x] **Check 4** `_check_headroom_clears_the_camera`: leave the live-rig measurement
      alone; add — using the number it already measured — an assertion that **every
      plan storey's clear height** clears `camera_y + arm.margin + CAMERA_CLEARANCE`.
      Storey 5's "clear height" is the distance to the shell's roof; say so in the
      comment and in a `ponytail:` note (D1).
- [x] **Check 5** `_check_node_shape`: `want_shapes` and the batch-corner test over
      `all_boxes()` and `FLOOR_Y.size()` storeys; `DRAW_BUDGET` against the new 26;
      the `Area3D` count **unchanged** (plan pads add none — state it in the comment,
      because a future pad that does add one has to come and edit this number).
- [x] **Check 9** `_check_visibility_gating`: the `for i in 2` live-rig loop becomes
      `FLOOR_Y.size()`, and the "storey N is visible from the ground floor" assertion
      becomes the **policy's** answer (`_floor_visible(i, 0)`) rather than "all
      visible" — with five storeys the ±1 window finally bites, and a live test that
      still asserted "everything is visible" would now be asserting the bug. Add
      `current_floor` assertions at each `FLOOR_Y` value and just below each.
- [x] `_clearance_at` / `_ramp_underside_at`: today `_ramp_underside_at` hard-codes
      `TowerInterior._ramp_box()`. Generalize to take the ramp box as a parameter and
      have `_clearance_at` call it for **each** rotated box it meets. Without this,
      three new rotated slabs are invisible to check 2's headroom reasoning.

### Task 7: Wire it up and prove it builds

- [x] `godot --headless --path . --import`, then run **every** self-check in the
      Testing Strategy list. All `SELFCHECK OK`, exit 0.
      (2026-08-29: `tower_selfcheck`, `tower_interior_selfcheck`, `tower_shell_selfcheck`,
      `tower_site_selfcheck`, `capture_selfcheck`, `chunk_stream_selfcheck`,
      `perf_selfcheck` — 7/7 `SELFCHECK OK`, exit 0.)
- [x] `godot --headless --path . scenes/main.tscn --quit-after 120` — no errors or
      warnings from any edited script. (Clean: exit 0, no `ERROR`/`WARNING`/`SCRIPT ERR`
      line in the boot log.)
- [x] Record `tower_selfcheck`'s wall-clock time (acceptance: **< 30 s**) and its new
      counts line. **0.39 s** — two orders of magnitude under the budget, which is the
      adjacency index of task 3 doing its job on a graph that has not grown yet. Counts,
      on the task-1 placeholder storey:

      ```
      tower scars: 1 authored, 1 built into the interior
      tower plans: 1 storeys, 2 rooms, 1384 cells walkable, ramps 29.6 deg
      tower graph: 15 rooms, 19 edges, 8 gates, 2 entries, 2 scars — 15 subset walks clean
      ```

      Re-measure after task 8 replaces the placeholder with the three real storeys —
      that is where the 30 s acceptance actually gets tested.

### Task 8: Author storeys 3, 4 and 5

Only now, with the machinery green on the placeholder, write the real content.

- [ ] Replace the placeholder `STOREYS` row with three real ones. Per the bead:
      **office floors — corridors, 8–12 rooms each, one stair per storey, two neutral
      rooms with a pad, NO gates.** Concretely, per storey:
      - a perimeter of `#` on the outermost ring (the plan's own wall, standing just
        inside the shell's inner face);
      - a corridor spine of `.` cells that the flood-fill reaches everything through —
        a ring corridor around the core reads best on an 80 m floor and gives the
        route redundancy the epic asks for;
      - 8–12 lettered rooms off it, each entered through a **one- or two-cell gap in
        its `#` wall** (a doorway is a hole in a wall, the shell's own idiom);
      - the `S` lane and `s` landing per D5, with the cell counts from D5's table;
      - exactly two `P` cells, in two different rooms.
      **Storey 3 additionally must leave the door corridor clear** (D5) and should read
      as the lobby floor that wraps the keep.
- [ ] Add the `TOWER_GRAPH` rows: `outer_hall`, `hall_outer`, `outer_s3` (D6), then one
      room row per plan letter per storey and the ungated edges joining each to its
      storey's landing (directly or through a corridor room, as the plan actually
      reads). Every new row: `"built": true, "quest": "", "cell": "", "parts": []`, and
      a `note` that says what the room IS — the notes are the design record.
      Naming convention: `s3_*`, `s4_*`, `s5_*`, landings `s3_landing` etc.
- [ ] Re-run the full self-check list. **Iterate on the ASCII until the flood-fill and
      the 15-subset audit are both green** — that loop is the point of this phase.
- [ ] Measure and set `PLAN_BOX_BUDGET` from the real merged counts, with the numbers
      and the reasoning in its comment (the shell's and the interior's budget comments
      are the models: say what the number *stops*).
- [ ] Confirm `DRAW_BUDGET` 26 is exact — `_check_node_shape` prints the real mesh
      count; if a plan storey emitted two surfaces, find the glow colour and remove it.

### Task 9: Documentation and acceptance

- [ ] `CLAUDE.md`: a new **`Hand-planned storeys`** subsection inside the existing
      tower block (after the `tower_interior.gd` paragraph at `:207`), in the same
      density and voice, carrying:
      - ASCII plans are the level editor; a designer edits `rows` and **nothing is
        generated, seeded or hashed** (owner ruling 1);
      - the grid contract and why `PLAN_CELL` is derived;
      - **the extension rule the bead is measured on**: a new storey is one `STOREYS`
        row plus its `TOWER_GRAPH` rows — **no builder edit**;
      - the two audits and what each one *cannot* see (the graph does not know a
        corridor exists; the flood-fill does not know a gate is passable);
      - the run-length merge and the measured per-storey box and draw numbers;
      - the ramp rule: derived hole, slope never above the proven `RAMP_*` one, X-axis
        only and why;
      - `FLOOR_Y` and the ±1 visibility window finally biting at five storeys;
      - the `ponytail:` deferrals, honestly.
- [ ] Update the `tower_selfcheck` and `tower_interior_selfcheck` lines in the Commands
      block (`:70-105`) to mention the flood-fill and the per-storey loops.
- [ ] Verify the bead's acceptance, item by item, and write the evidence into the PR body:
      - storeys 3–5 walkable from the existing upper landing by ramp — state the route
        (upper landing → phase-3 ramp → courtyard → rotor doorway → entry hall → keep
        doorway → annulus → grand ramp → storey 3 → storey 4 → storey 5), and that
        every leg is a ramp or an ungated doorway;
      - `tower_selfcheck` all checks, 15 subsets, new flood-fill, adjacency index,
        **< 30 s**, `SELFCHECK OK` — quote the time;
      - `tower_interior_selfcheck` and `tower_shell_selfcheck` `SELFCHECK OK`;
      - the declared per-storey box and draw budgets, with the measured numbers;
      - **web spike measurement**: `get_spike_summary()` on entry cannot be driven from
        a headless CI box. State honestly what *was* asserted instead (draw count per
        storey, the ±1 gate meaning at most three storey meshes render, no shadows, one
        `StaticBody3D`) and flag the F3 walk-through as an owner-side check.
      - "a designer can add a storey with no builder edit" — demonstrate it: add a
        fourth throwaway storey row locally, watch the checks pass, then delete it and
        confirm `git status` is clean.
- [ ] Every deliberate simplification carries a `ponytail:` comment with its ceiling and
      upgrade path. The known ones:
      - storey 5 has no ceiling (open to the shell roof) until phase 16's storeys land;
      - `P` pads are geometry only until phase 17 brings the guards they would scare;
      - `G` posts are parsed and validated but spawn nothing (phase 17);
      - `D` gate slots are parsed and validated but no storey has one (phase 15);
      - the stairwell hole is one axis-aligned rectangle, so a ramp that turned a
        corner would need a second rect — X-axis-only ramps are what buys that;
      - the new storeys hang off ungated edges, so they add rooms to the 15-subset
        audit but no new route obligation; phase 15 is where that changes.
