# Tower — retire the legacy 20 m keep: plan storeys 1 and 2 on the grid

## Overview

Bead `godot-test1-dn8` (epic `godot-test1-3iy`), size **huge**.

**Owner playtest, 2026-08-30:** *"in the castle on the first floor there is a legacy
prison; we can remove it."* **Owner clarification, same day:** the "legacy prison" is
**the small building inside the new HQ** — the phase-3 **keep** (`TowerShell.KEEP_HALF`
10 m ring, `KEEP_HEIGHT` 11 m) that shell phase 13 preserved inside the 80 m envelope.
There is no prison geometry on the ground floor (a previous pass walked storey 0
headlessly and found 22 boxes, all phase-3 keystone); what the owner is looking at is
the **keep itself**, a windowless 20 m box standing in the middle of an 80 m hall.

**Remove the inner building.** Floors 0 and 1 are the only two floors in this tower not
drawn on `TowerPlans`' grid — they are hand-authored against the keep's inner faces.
Draw them as ASCII plans like storeys 3–10, let the plan builder build them, re-express
every room and gate the graph walks with **its existing id**, delete the keep ring and
the hand-authored `boxes()` table, and let the 30 m annulus become ordinary planned
floor.

**This is mostly deletion.** `tower_interior.boxes()` (the whole hand-authored table),
`TowerShell`'s six keep-ring boxes, `TowerInterior.GUARD_POSTS`, the `HallCarpet`, four
ceiling panels, `INNER_HALF` and a dozen authored X/Z constants all go away. What is
*added* is two `TowerPlans.STOREYS` rows, three small hand-built-part functions in the
`_block_boxes` idiom, and a handful of graph rows.

## Hard invariants (breaking any of these is a failed task)

1. **Every persisted id keeps its exact spelling.** The opened set, the checkpoint /
   lift stops, the scars and the cell rooms are **monotone persisted sets** (CLAUDE.md,
   `best_run_store.gd`). These may NOT be renamed, ever:
   - gates: `rotor_gate`, `tower_vault`, `tower_secure_door`, `tower_checkpoint`,
     `maintenance_crawl`, `updraft_shaft`, `phase_grate`, `collapsed_slab`,
     `hound_den`, `riddle_stair`, `riddle_strongroom`, `riddle_maze_lower`,
     `riddle_maze_upper`;
   - entries / stops: `front_door`, `lift_stop_upper`, `lift_stop_maze`;
   - scars: `custody_stair_collapse`; story flags: `lift_activated`,
     `lift_stop_maze_unlocked`; `TowerGraph.RESCUE_DONE`;
   - rooms the entries name or the rescue needs: `entry_hall`, `upper_landing`,
     `courtyard`, `checkpoint_room`, `vault`, `outer_hall`, `service_stair`,
     `cell_gallery`, `cell_windman`, `cell_primm`, `cell_teibi`, `cell_phoboman`.
   **Edge ids are NOT persisted** (`tower_graph.gd` says so at the `block_main_door`
   comment) — an edge may be renamed, and this plan renames exactly one.
2. **Storeys 3–10 do not move.** `FLOOR_Y[2..9]` stays `11, 16, 21, 26, 31, 36, 41, 46`
   and the sealed roof stays at 50/52. `tower_shell_selfcheck`'s roof-seal and
   castle checks must come back green with **no number changed but the box budget**.
3. **The 15-subset softlock audit is load-bearing** — `tower_selfcheck` must walk every
   entry × every story-flag state clean, exactly as today.
4. **The jump rule.** No traversal in this building may demand a jump height. Every
   vertical move stays a ramp or a gate.
5. **One guard per storey** (`GUARDS_PER_STOREY_MAX = 1`, owner ruling 2026-08-30).
   #144 landed one `G` post per storey plus two hand-authored rows for floors 0 and 1;
   after this change **both hand rows are gone and both floors carry a `G`**, so the
   built population is unchanged at nine bodies.
6. **No seed, no hash, no random** anywhere in `tower_plans.gd` (the owner's "plan it
   once and forever" ruling).

## Context — what the building is on `origin/master` today

Read these files before writing code. They are heavily commented on purpose.

- **`scripts/tower_shell.gd`** — `OUTER_HALF 40.0`, `WALL_THICK 1.2`,
  `STOREY_HEIGHT 5.0`, `STOREYS 10`, `WALL_HEIGHT 50.0`, `ROOF_THICK 2.0`,
  **`KEEP_HALF 10.0`, `KEEP_HEIGHT 11.0`**, `DOOR_HALF_WIDTH 3.0`, `DOOR_HEIGHT 4.0`,
  `YARD_HALF 45.0` (a non-colliding packed-earth apron at y 0…0.03 over the whole
  footprint), `BOX_BUDGET 28`.
  `boxes()` (`:444`) builds the envelope ring, **then the same six-box keep ring again**
  (`:470`–`:493`: `KeepWallBack`, `KeepWallSideNegZ`, `KeepWallSidePosZ`,
  `KeepJambNegZ`, `KeepJambPosZ`, `KeepLintel`), then the roof, the castle pass's
  dressing and the beacon. `door_trigger_box()` (`:548`) puts the "entered the tower"
  trigger on **the keep's** door line.
  The `BOX_BUDGET` comment already says: *"Phase 14 is also what deletes the inner ring
  again."* This bead is that deletion.
- **`scripts/tower_interior.gd`** (4651 lines) — `INNER_HALF = KEEP_HALF - WALL_THICK`
  (8.8), `SLAB_Y 4.6`, `SLAB_THICK 0.4`, `FLOOR_Y` (10 entries),
  `FLOOR_NEIGHBOURS`, `BOX_BUDGET 32`, `DRAW_BUDGET 35`, `PLAN_BOX_BUDGET 120`.
  - `boxes()` (`:1409`) — **the hand-authored keep**, 28 entries on floors 0 and 1:
    two rotor jambs, `RampUnderwall`, `RotorPost` + two spinning bars, the vault's
    wall/two jambs/`DemandShutter`, `Receptacle` + `Band1..4`, four `Panel*`,
    `_ramp_box()`, `HallCarpet`, `UpperSlab`, two `SecureJamb*`, `IdentityMass`,
    `IdentityPad`, `CheckpointPlate`, `CheckpointPost`.
  - `plan_boxes(i)` (`:1708`) — the machine: `_plan_slab` + `_merge_walls` +
    `_plan_ramp` + `_plan_pads` + `_plan_gates`, plus `_block_boxes(plan)` on the one
    storey that draws `cell_gallery`. **`all_boxes()` is `boxes()` then every plan.**
  - The plan-lookup idiom phase 16 established, and the one this bead copies:
    `plan_room_rect(floor, room_id)`, `plan_gate_rect(floor, gate_id)`,
    `plan_doorway_rect(floor, room_id)`, `_cell_span(rect)`, `gate_slots(plan)`,
    `gate_pad_cell(plan, span)`. **Every hand-built part of the cell block takes its
    position from those lookups instead of a constant** (`_block_boxes`, `:2411`).
    This bead does exactly the same for the rotor, the receptacle and the checkpoint.
  - `_plan_gates` (`:2099`) dispatches on `TowerGraph.gate(id)["class"]`:
    `CLASS_CHALLENGE` → a lintel; `CLASS_IDENTITY` → mass + derived pad;
    `CLASS_RIDDLE` → mass + drawn pads. **There is no `CLASS_DEMAND` arm.**
  - `GUARD_POSTS` (`:1113`) — the two hand-authored posts, `Courtyard` and `Upper`;
    `guard_posts_table()` (`:1148`) is those two plus one `_plan_guard_post` per
    planned storey.
  - `CHECKPOINT_STAND` / `ENTRY_STAND` (`:1246`) — the two `setback_point()` branches.
  - `inside_walls()` (`:4265`) **already derives from `TowerPlans.PLAN_HALF`**, i.e.
    the envelope. No change needed there; only its comment mentions the keep.
- **`scripts/tower_plans.gd`** (904 lines, pure data) — `PLAN_GRID 40`,
  `PLAN_HALF 38.8`, `PLAN_CELL 1.94`, the character table, `STOREYS` (floors **2…9**),
  `storey(floor_index)`, `floors()`. Read its header in full; it is the format spec.
- **`scripts/tower_graph.gd`** — `TOWER_GRAPH`. Floor 0/1 rooms are `entry_hall`,
  `vault`, `courtyard`, `upper_landing`, `checkpoint_room`, `outer_hall`; their edges
  are `hall_courtyard` (gate `rotor_gate`), `hall_vault` (gate `tower_vault`),
  `courtyard_landing` (ungated ramp), `landing_checkpoint` (gate `tower_secure_door`),
  `hall_outer` (ungated) and `outer_s3` (ungated).
- **The self-checks that must stay green** — `tower_selfcheck` (15-subset audit, plan
  ↔ graph binding, per-storey flood fill), `tower_interior_selfcheck` (18 checks,
  budgets, jump rule, node shape, guard posts), `tower_shell_selfcheck` (roof seal,
  doorway is a hole, castle), `capture_selfcheck` (rescue spines, custody protocol,
  scar, the guard-setback checkpoint positions), `chunk_stream_selfcheck`,
  `minimap_selfcheck`, `perf_selfcheck`, `enemy_spawn_selfcheck` (it asserts
  `TowerInterior.GUARD_POSTS` is non-empty — see Task 6).

### Baseline to record

Before Task 1, run every self-check in the Testing Strategy on the untouched branch and
paste the timings and the printed summary lines into this file under
"➕ Baseline (measured)". The bead's acceptance asks for **the storey-0 box count before
and after**, so capture the `tower interior: N keep boxes` and `storey 0: N boxes` lines
verbatim.

---

## The design, decided — these are rulings, do not re-derive them

### D1. The floors do not move, and `KEEP_HEIGHT` becomes an interior constant

`FLOOR_Y` keeps every value it has: `[0.0, 4.6, 11.0, 16.0, 21.0, 26.0, 31.0, 36.0,
41.0, 46.0]`. Only its *derivation* changes, because `TowerShell.KEEP_HEIGHT` is
deleted with the ring:

```gdscript
## The first office storey's walking surface, and the one number in this table that
## is HISTORY rather than arithmetic: 11.0 m was the phase-3 keep's parapet, and the
## seven storeys above it plus the sealed roof were sized off it. The keep is gone
## (bd godot-test1-dn8); the height stays, because moving it would move storeys 3-10
## and the roof, and this bead demolishes a building, not the tower.
const PODIUM_Y: float = 11.0
```

`FLOOR_Y` then reads `[0.0, SLAB_Y, PODIUM_Y, PODIUM_Y + TowerShell.STOREY_HEIGHT, …]`.

`SLAB_Y` (4.6) survives as floor 1's walking surface and keeps its derivation comment.
`SLAB_THICK` survives — every plan slab hangs off it.

**`FLOOR_NEIGHBOURS` collapses back to plain adjacency.** The mezzanine that broke the
index arithmetic is gone: floor 1 is now a full 80 m storey whose slab roofs floor 0
everywhere. The table becomes `[[1], [0,2], [1,3], …, [8]]`. Keep it a table (check 9
asserts it symmetric and the visibility policy reads it), but rewrite the comment: say
what it used to be, and that the mezzanine that needed it no longer exists.

### D2. Storey 1 (floor 0) and storey 2 (floor 1) become `TowerPlans.STOREYS` rows

Both are ordinary 40 × 40 rows in the existing format, prepended to `STOREYS` so
`TowerPlans.floors()` returns `0..9`. Naming: the colloquial storey number is the floor
index plus one, exactly as today (floor 2 is "storey 3"), so new graph rooms on floor 0
are `s1_*` and on floor 1 are `s2_*`.

**The ground storey has no ramp, and that is data, not a special case.** Its row carries
`"from": 0` — equal to its own `floor` — and draws **no `S` cells**. The rule to write
down once, in `tower_plans.gd`'s header and in `tower_selfcheck`:

> `from == floor` means **this storey is entered from outside the building**. It draws
> no `S` lane; its `s` cells are the doormat, and they are still the flood fill's start
> because that is where a player actually arrives.

`_plan_stair()` already returns `{}` when there are no `S` cells, so `_plan_ramp` and
`_plan_hole` need no edit at all. Only the *audit* needs the arm (Task 5).

**Floor 0 still emits its slab.** It is four boxes hanging in `-0.4 … 0.0`, under the
shell's yard apron and under the world's ground plane, so nothing shows and nothing
z-fights — and it is what makes the ground floor's collision the interior's own instead
of the streaming terrain's. **No builder edit**, which is the point.

### D3. Floor 0's plan — the route is phase 3's route, redrawn

Rooms and what they are:

| letter | room id | what it is |
|---|---|---|
| `s` | `entry_hall` (`"landing"`) | the hall behind the front door, on the +X side centred on z = 0. The flood fill starts here. |
| `C` | `courtyard` | west of the rotor doorway. No longer open to the sky — floor 1 roofs it — and that is fine: the id is persisted, the fiction is not. |
| `V` | `vault` | behind the demand shutter, off the hall's south side. |
| `O` | `outer_hall` | the ring corridor the phase-13 envelope opened up, off the hall, ungated. |
| `D` | — | one run for `tower_vault` only (see D5). |
| `P` | — | **exactly two**, each 4-adjacent to a room letter (check 9 requires it). |
| `G` | — | **exactly one**, in the courtyard between the rotor doorway and the foot of the ramp — the same junction #144's hand-authored `Courtyard` post stood on, and the ground floor's one choke point. |

The **`S` lane belongs to floor 1**, not here (D4).

**The rotor doorway is a plain two-cell gap in the `#` wall between `C` and the hall.**
It carries no `D`: `rotor_gate` is a challenge whose "mass" is two bars that sweep, and
`_plan_gates`' challenge arm draws a low **lintel** (right for the maintenance crawl,
wrong for a doorway you walk through). Its post and bars are hand-built from a plan
lookup instead (D6). Draw the gap **centred on the courtyard's z-midline** so the lookup
is one rect and no second number.

`2 * ROTOR_DOOR_HALF (3.8 m)` must fit a two-cell gap (3.88 m) — it does; check 1 gains
that assertion (Task 6).

### D4. Floor 1's plan — the landing, the identity gate, the checkpoint

| letter | room id | what it is |
|---|---|---|
| `s` | `upper_landing` (`"landing"`) | head of the floor-0 ramp, **and the foot of the grand ramp to storey 3**. |
| `A` | `checkpoint_room` | east of the identity gate. |
| `B` (+ `E` if the plan reads better) | `s2_muster` (new) | plain office floor filling the 80 m plate; exists so the storey's two `P` pads each have a room to stand beside. |
| `D` | `tower_secure_door` | the identity mass's run, cut into the partition that closes the checkpoint off. |
| `S` | — | the up-lane from floor 0, `"from": 0`, rise 4.6 m. |
| `G` | — | one post, **west of the `D` run**, i.e. on the approach to the identity gate — #144's `Upper` post, re-expressed. |

**The checkpoint stays a safe haven by construction.** `_plan_guard_post` measures the
patrol as the symmetric run of **`.` cells** around the post, so the run stops dead at
the `D` cell: a guard on floor 1 cannot follow you through the identity gate. That was a
hand-tuned `patrol_half` before and is now geometry. Say so in the plan row's `note`.

**Ramp geometry.** `PLAN_RAMP_MAX_SLOPE` is 0.575. Floor 0 → 1 rises 4.6 m, so the `S`
lane needs ≥ 8.0 m ≥ 4.13 cells: **draw 6 cells** (11.64 m, slope 0.395). Draw it two
cells deep, long axis on X, `s` against one short end — the format's rule.

**Storey 3's grand ramp now climbs from floor 1, not floor 0.** Change storey 3's row
from `"from": 0` to `"from": 1` and nothing else: its ten-cell lane now carries 6.4 m
instead of 11.0, slope 0.330, gentler than the 0.567 it has today. **This is required,
not cosmetic** — floor 1 is a full slab now, and a ramp from 0 to 2 would pass straight
through it (the plan format has no hole character, and `_plan_hole` only cuts the slab
of the storey the ramp *arrives* on).

So **floor 1's rows must be plain walkable floor under storey 3's lane cells**
(`tower_selfcheck` asserts that cell by cell) — that is rows 1–2, columns 5–14 of the
grid, and those cells must not be `#` and must not be floor 1's own `S`. Put floor 1's
own ramp on the south half of the plate.

### D5. The gates, re-expressed with their existing ids

| gate | class | how it is drawn now |
|---|---|---|
| `rotor_gate` | challenge | **no `D`** — a plain 2-cell gap; post + two bars hand-built (D6). |
| `tower_vault` | demand | a `D` run on floor 0 in the wall between `s`(hall) and `V`. `_plan_gates` gets **one new arm: `CLASS_DEMAND` → `continue`**, because a shutter *sinks* and its receptacle is not a plan character. The shutter, the pillar and the four bands are hand-built from `plan_gate_rect(0, TowerGraph.GATE_DEMAND)` (D6), keeping the names `DemandShutter`, `Receptacle`, `Band1`…`Band4`. |
| `tower_secure_door` | identity | a `D` run on floor 1. `_plan_gates`' existing identity arm draws it: mass `S1PlanGateMass_tower_secure_door` and derived pad `S1PlanGatePad_tower_secure_door`. `TOWER_GRAPH`'s `parts` for this gate change to those two names — **`parts` is not persisted**; phase 16 did exactly this for the four spine gates (`S9PlanGateMass_updraft_shaft`). Delete `IdentityMass`/`IdentityPad` and `UPPER_WALL_X` / `UPPER_WALL_HEIGHT` / `UPPER_DOOR_HALF`. |
| `tower_checkpoint` | — | not a doorway; `CheckpointPlate` + `CheckpointPost` hand-built from `plan_room_rect(1, "checkpoint_room")`. |

`_place_mass()` positions the identity mass off `SLAB_Y + UPPER_WALL_HEIGHT * 0.5`.
Re-derive its rest position from the built box (remember it when `_remember()` binds the
mesh, or read it back off `plan_boxes`) rather than from constants that no longer exist.
`gate_of()` already resolves `S<n>PlanGate…` names, so the plumbing is in place.

### D6. The hand-built parts, in the `_block_boxes` idiom

Three small functions in `tower_interior.gd`, each guarded in `plan_boxes()` by a
**room/gate lookup and never by a floor number** — the same rule that lets the cell
block live on whatever storey draws it:

```gdscript
if plan_room_rect(floor_index, "courtyard").size != Vector2i.ZERO:
    out.append_array(_rotor_boxes(plan))
if plan_gate_rect(floor_index, TowerGraph.GATE_DEMAND).size != Vector2i.ZERO:
    out.append_array(_demand_boxes(plan))
if plan_room_rect(floor_index, "checkpoint_room").size != Vector2i.ZERO:
    out.append_array(_checkpoint_boxes(plan))
```

- **`_rotor_boxes`** — `RotorPost` (full storey height, `COLOR_HAZARD`, solid) on the
  courtyard's east face at the doorway's z-midline, plus `RotorBarLow` / `RotorBarHigh`
  (`spin`, non-solid) at `ROTOR_LOW_Y` / `ROTOR_HIGH_Y`. Positions come from
  `_cell_span(plan_room_rect(floor, "courtyard"))`; keep `ROTOR_ARM`,
  `ROTOR_DOOR_HALF`, `ROTOR_LOW_Y`, `ROTOR_HIGH_Y`, `ROTOR_LOW_SPEED`,
  `ROTOR_HIGH_SPEED` — they are the bars' own geometry and rhythm.
- **`_demand_boxes`** — `DemandShutter` (`COLOR_MECHANISM`, `dynamic`, solid) filling
  the `D` run floor-slab to ceiling; `Receptacle` (1.0 × 2.6 × 0.6) standing one cell in
  front of it on the hall side (use `gate_pad_cell(plan, span)` — it answers exactly
  "which side do you walk up from"); `Band1`…`Band4` on the pillar's face in
  `COLOR_BAND_DARK`, bottom band first, because `_update_bands()` lights them by index.
  `SHUTTER_TRAVEL` stays (it is how far the thing sinks); `SHUTTER_X0/X1`,
  `VAULT_X0`, `VAULT_Z`, `RECEPTACLE_X`, `RECEPTACLE_Z` all go.
- **`_checkpoint_boxes`** — `CheckpointPlate` (0.1 m proud, non-solid) and
  `CheckpointPost` centred in `plan_room_rect(floor, "checkpoint_room")`.

**Every box name above is kept exactly** — they appear in `TOWER_GRAPH`'s `parts`, in
`MOVING_PARTS`, in `_remember()` / `gate_of()` and in the self-checks, and keeping them
is what makes this a geometry move and not a rename.

### D7. `CHECKPOINT_STAND` and `ENTRY_STAND` become derived

Both are `const Vector3`s authored against the keep. Replace with

```gdscript
static func checkpoint_stand() -> Vector3   # centre of plan_room_rect(f, "checkpoint_room"), y = FLOOR_Y[f] + 0.2
static func entry_stand() -> Vector3        # just inside the shell doorway, y = 0.2
```

`setback_point()` calls them; `capture_selfcheck` (`:910`) references the two constants
and must be updated to call the functions. **This is what the bead's "guard-setback
checkpoint positions" acceptance measures — check it explicitly.**

`entry_stand()`'s x moves from just inside the keep's door (7.6) to just inside the
**envelope's** door, because the keep's door no longer exists (D8).

### D8. The door trigger moves to the envelope

`TowerShell.door_trigger_box()` reads `KEEP_HALF`; change it to `OUTER_HALF`. Its
comment currently argues that "entered the tower" is a claim about the rooms and the
outer hole is a gateway into a courtyard — **rewrite it**: there is one ring now, so the
hole and the trigger are the same doorway again. `tower_shell_selfcheck`'s
`_check_doorway_is_a_hole` walks a list of wall rows including a `"keep wall"` entry
(`:690`) — that row goes with the ring.

### D9. What gets deleted

`tower_interior.gd`: `boxes()` in its entirety, `BOX_BUDGET`, `_ramp_box()`,
`INNER_HALF`, `SLAB_X0`, `ROTOR_POST_X`, `RAMP_X0`, `RAMP_WIDTH`, `RAMP_Z`,
`RAMP_THICK`, `RAMP_UNDER_Z`, `RAMP_UNDER_TOP`, `VAULT_Z`, `VAULT_X0`, `SHUTTER_X0`,
`SHUTTER_X1`, `RECEPTACLE_X`, `RECEPTACLE_Z`, `UPPER_WALL_X`, `UPPER_WALL_HEIGHT`,
`UPPER_DOOR_HALF`, `CARPET_THICK`, `GUARD_POSTS`, `CHECKPOINT_STAND`, `ENTRY_STAND`,
and the boxes `RotorJambNegZ`, `RotorJambPosZ`, `RampUnderwall`, `VaultWall`,
`VaultJambWest`, `VaultJambEast`, `PanelHallNorth`, `PanelHallFar`, `PanelHallSouth`,
`PanelVault`, `HallCarpet`, `UpperSlab`, `SecureJambNegZ`, `SecureJambPosZ`,
`IdentityMass`, `IdentityPad`.

**Keep `_deck_box()`** — `_plan_ramp` uses it. **Keep `COLOR_PANEL`** — the cell block's
two panels use it. `all_boxes()` becomes the plan loop alone.

`PLAN_RAMP_MAX_SLOPE` currently derives from the phase-3 ramp (`SLAB_Y / (SLAB_X0 -
RAMP_X0)` = 0.575). That ramp is being deleted, so write the number down as `0.575` and
carry its whole provenance in the comment: it is the slope the game has shipped since
phase 3, walked without sliding, and the reason it is a ceiling rather than a target.

`tower_shell.gd`: the six keep-ring boxes, `KEEP_HALF`, `KEEP_HEIGHT`; `BOX_BUDGET`
28 → 22 with a comment saying which six went and why.

`tower_selfcheck.gd`: the *"No plan below means floor 0"* branch in `_plan_problems`
(the keep-clearance and door-corridor rules for the grand ramp) — floor 0 has a plan
now, so the general branch covers it and the special case is dead code.

### D10. Graph edits (all in `TOWER_GRAPH`)

- **Unchanged rows**: `entry_hall`, `courtyard`, `vault`, `upper_landing`,
  `checkpoint_room`, `outer_hall`, and the edges `hall_courtyard`, `hall_vault`,
  `courtyard_landing`, `landing_checkpoint`, `hall_outer`. Update their `note`s to say
  where they are drawn now.
- **`outer_s3` → renamed `landing_s3`, `a` changes from `outer_hall` to
  `upper_landing`** — the grand ramp's foot moved up a floor (D4). Edge ids are not
  persisted; document the rename beside it the way `block_main_door` documents its own.
  `outer_hall` stays an ordinary ungated room off the entry hall.
- **New rooms**: `s2_muster` (and a second `s2_*` if floor 1's plan wants two), plus a
  `s1_*` row for any extra floor-0 room the drawing needs. Each needs an ungated edge to
  its floor's landing, exactly like every `s3_*` room.
- **`tower_secure_door`'s `parts`** → `["S1PlanGateMass_tower_secure_door",
  "S1PlanGatePad_tower_secure_door"]`.
  **`tower_vault`'s `parts`** stays `["DemandShutter", "Receptacle"]`.
  **`rotor_gate`'s `parts`** stays `["RotorPost", "RotorBarLow", "RotorBarHigh"]`.
- **Do not touch** `needed_during_captivity` on any gate. The audit recomputes it; if a
  flag now disagrees with the recomputation, that is a **finding to report**, not a flag
  to flip. (Making the whole climb sit behind `rotor_gate` is legal — a challenge is
  base-kit and can strand no subset — but if `tower_selfcheck` disagrees, see the
  fallback in Task 4.)

---

## Development Approach

- **No test framework exists.** Verification is `godot --headless --path . --import`
  plus the headless self-checks and a short headless boot of `scenes/main.tscn`.
- Complete each task fully before moving to the next, and **run the self-checks the task
  names before ticking it**.
- **Keep the teaching-density comments and explicit type hints.** These are the densest
  files in the repo; match `tower_graph.gd` and `tower_interior.gd`. Say *why*, carry
  the measured numbers, record deliberate simplifications as `ponytail:` comments naming
  their ceiling and upgrade path. When you delete a paragraph that argued for the keep,
  replace it with one that says the keep is gone and what took its place — do not leave
  a comment describing a building that no longer exists.
- **Do not invent scope.** No new gates, no new hazards, no lift, no furniture, no
  lighting rig. Plain planned floor, and the phase-3 set pieces re-expressed.
- **Push after every task lands.** The machine sleeps and kills agents; pushed work
  survives.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

A fresh worktree has no `.godot`, and the self-checks must run with an isolated HOME:

```bash
godot --headless --path . --import
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/tower_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/tower_interior_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/tower_shell_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/tower_site_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/capture_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/enemy_spawn_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/chunk_stream_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/minimap_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/perf_selfcheck.gd
HOME=$(mktemp -d) godot --headless --path . scenes/main.tscn --quit-after 120
```

Every one must print `SELFCHECK OK` and exit 0.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Keep plan in sync with actual work done

---

## Implementation Steps

### Task 1: Baseline, then teach the format about the ground storey

- [ ] Run every self-check listed above on the untouched branch. Record the timings and
      the printed summaries (`tower plans: …`, `tower interior: N keep boxes …`, the
      per-storey `storey N: M boxes` lines, `tower_selfcheck`'s room/edge/gate counts)
      under a new "➕ Baseline (measured)" heading in this file. Commit and push.
- [ ] `scripts/tower_plans.gd` header: document **the `from == floor` rule** (D2) in the
      "A STOREY ROW" section — a storey whose `from` is its own floor is entered from
      outside the building, draws no `S` lane, and its `s` cells are the doormat.
      Also update the file's opening line ("the hand-planned layout of every floor
      **above the phase-3 keep**") — there is no keep, and `STOREYS` now covers the
      whole building.
- [ ] Nothing else in this task. No plan rows yet.

### Task 2: Draw floor 1 (storey 2) and move the grand ramp onto it

Floor 1 first, because storey 3 already exists above it and its ramp is the thing that
has to keep working.

- [ ] Add the floor-1 `STOREYS` row per D4: `"floor": 1, "from": 0,
      "landing": "upper_landing"`, its `rooms` / `gates` maps, and 40 rows of 40 chars.
      Author the `note` as the design record: what the floor is, why the checkpoint is a
      safe haven by construction, and that the grand ramp to storey 3 starts here.
- [ ] Keep rows 1–2, columns 5–14 as plain walkable floor (storey 3's lane stands on
      them); put floor 1's own six-cell `S` lane and its `s` landing on the south half.
- [ ] Exactly two `P` cells, each 4-adjacent to a room letter; exactly one `G`, west of
      the `D` run.
- [ ] Change storey 3's row to `"from": 1`. Nothing else in that row moves.
- [ ] `FLOOR_NEIGHBOURS` → plain adjacency, with the rewritten comment (D1).
- [ ] Add `TOWER_GRAPH` rows for any new `s2_*` room plus their ungated edges from
      `upper_landing`; rename `outer_s3` → `landing_s3` with `a: "upper_landing"` (D10);
      re-point `tower_secure_door`'s `parts` (D5).
- [ ] `tower_selfcheck` and `tower_interior_selfcheck` will fail here (floor 1 now emits
      plan boxes *and* keep boxes on the same floor, duplicate names, budget). **That is
      expected** — Task 3 is what removes the keep. Note the failures; do not paper over
      them.

### Task 3: Draw floor 0 (storey 1) and delete `boxes()`

- [ ] Add the floor-0 `STOREYS` row per D3: `"floor": 0, "from": 0,
      "landing": "entry_hall"`, one `D` run for `tower_vault`, no `S`, exactly two `P`,
      exactly one `G` in the courtyard. Author its `note` as the design record.
- [ ] Add the `CLASS_DEMAND` arm to `_plan_gates` — one `continue` with the comment that
      says why (a shutter sinks, and a receptacle is not a plan character).
- [ ] Write `_rotor_boxes`, `_demand_boxes`, `_checkpoint_boxes` per D6, and wire the
      three room/gate-lookup guards into `plan_boxes()`.
- [ ] **Delete `boxes()`** and everything in D9's list. `all_boxes()` becomes the plan
      loop alone. Fix `_place_mass()` per D5.
- [ ] Replace `CHECKPOINT_STAND` / `ENTRY_STAND` with `checkpoint_stand()` /
      `entry_stand()` (D7); update `setback_point()`.
- [ ] Delete `GUARD_POSTS`; `guard_posts_table()` becomes the derived loop alone, with
      its comment rewritten (the keep's two hand rows are now two `G` characters).
- [ ] `PODIUM_Y` + the `FLOOR_Y` rewrite (D1); `PLAN_RAMP_MAX_SLOPE` becomes 0.575 with
      its provenance (D9).
- [ ] Update `inside_walls()`'s comment — it already reads the envelope; the paragraph
      about the keep being the narrowest indoor space is now false.

### Task 4: The shell — delete the ring, move the trigger

- [ ] Delete the six keep-ring boxes from `TowerShell.boxes()` and the constants
      `KEEP_HALF` / `KEEP_HEIGHT` (D9). Keep every castle-pass and beacon constant.
- [ ] `door_trigger_box()` → `OUTER_HALF`, with the rewritten comment (D8).
- [ ] `BOX_BUDGET` 28 → 22, comment naming the six that went.
- [ ] `tower_shell_selfcheck`: drop the `"keep wall"` row from `_check_doorway_is_a_hole`
      and any other keep assertion. **The roof-seal, Windman-reach, footprint, impostor,
      rain and cloud checks must pass with no number changed.**
- [ ] Run `tower_shell_selfcheck` and `tower_site_selfcheck`. Both `SELFCHECK OK`.
- [ ] ⚠️ If `tower_selfcheck` reports that `rotor_gate`'s `needed_during_captivity` or a
      subset walk is now wrong because the whole climb sits behind the rotor doorway,
      **do not flip the flag**. The fallback is to move floor 1's `S` lane so its foot
      stands in `outer_hall` instead of `courtyard` and re-point the
      `courtyard_landing` edge accordingly — record the change here and say why.

### Task 5: The audits — teach them the two new storeys

- [ ] `tower_selfcheck._plan_problems`: add the `from == floor` arm (skip every `S`-lane
      assertion — one solid lane, landing against a short end, lane stands on the floor
      below, slope — for a storey that draws no lane), and **delete the "No plan below
      means floor 0" branch** entirely (D9).
- [ ] Add a negative control for the new arm at the bottom of
      `_check_the_flood_fill_can_fail`, in the shape of the ones already there: a broken
      copy of the ground storey must still be caught.
- [ ] `tower_interior_selfcheck` check 1 `_check_plan_fits_the_shell`: drop the `keep`
      population, the `_fit_boxes(keep, INNER_HALF, [0,1], seen)` call and the
      `BOX_BUDGET` print; keep the per-storey `PLAN_BOX_BUDGET` loop and the name
      uniqueness `seen` dict. Add the rotor-doorway assertion: `2 * ROTOR_DOOR_HALF`
      must fit the gap the plan actually draws.
- [ ] Check 3 `_check_ramp_is_the_stair` and check 4 `_check_headroom_clears_the_camera`:
      re-point anything that measured the phase-3 ramp or sized the indoor boom against
      the keep at the plans instead. Keep the *intent* of each check — say in the
      docstring what it used to measure and what it measures now.
- [ ] Check 2 (jump rule) and check 9 (visibility gating) should need no logic change;
      if they do, the change is in the comment as well as the code.
- [ ] Move any budget that must move (`DRAW_BUDGET`, `PLAN_BOX_BUDGET`) **in the const,
      with a comment saying what pushed it** — never by loosening an assertion.

### Task 6: The rest of the callers

- [ ] `capture_selfcheck` (`:910`): `TowerInterior.CHECKPOINT_STAND` / `ENTRY_STAND` →
      the new functions. Confirm `_check_a_guard_takes_coins_and_ground_not_a_heart`
      still lands the player on the plate in both branches — this is the bead's
      "guard-setback checkpoint positions" acceptance.
- [ ] `enemy_spawn_selfcheck`: it asserts `TowerInterior.GUARD_POSTS` is non-empty.
      Re-point it at `guard_posts_table()`, which is the seam that actually matters.
- [ ] `grep -rn 'KEEP_HALF\|KEEP_HEIGHT\|INNER_HALF\|UpperSlab\|HallCarpet\|GUARD_POSTS\|CHECKPOINT_STAND\|ENTRY_STAND\|TowerInterior.boxes' scripts/ scenes/`
      must come back empty except for the historical notes you deliberately kept.
- [ ] `grep -rn 'keep' scripts/tower_*.gd` — read every hit and fix the comments that
      now describe a building that does not exist.

### Task 7: Verify, measure, document

- [ ] `godot --headless --path . --import`, then the **whole** Testing Strategy list.
      Every one `SELFCHECK OK`, exit 0.
- [ ] Record the post-change numbers next to the baseline: self-check timings, the
      per-storey box counts (**the bead asks for storey 0's box count before and
      after**), `tower_selfcheck`'s room/edge/gate/entry counts, and the guard body
      count per storey.
- [ ] Headless boot of `scenes/main.tscn --quit-after 120`, clean.
- [ ] Update `scripts/tower_interior.gd`'s file header: the route at the top still
      describes the keep's two storeys. Rewrite it as the route the player now walks,
      and add a line to the "WHAT THIS FILE IS, structurally" section saying the
      hand-authored table is gone and every storey comes from `TowerPlans`.
- [ ] Update `scripts/tower_plans.gd`'s header: it is now **every** floor, not "every
      floor above the phase-3 keep", and the extension rule is unchanged — say that
      absorbing two more storeys cost it no format change, because that is the evidence
      the format works.
- [ ] Move `docs/plans/20260829-tower-storey-plans.md` to `docs/plans/completed/` if it
      is complete, and move **this** plan there when every box above is ticked.
