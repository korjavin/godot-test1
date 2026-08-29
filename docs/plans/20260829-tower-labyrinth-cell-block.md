# Tower phase 16 — the labyrinth (storeys 8–9) and the cell block moved to storey 10

## Overview

Bead `godot-test1-3iy.16` (epic `godot-test1-3iy`, phase 16, size **huge**). Owner
ruling item 3 (2026-08-29): *"a labyrinth to jail where captured heroes are"*.

Phase 14 built the machinery that makes a hand-planned storey cheap and shipped
storeys 3–5. Phase 15 added the riddle gate class. **This phase fills the building to
its sealed roof and moves the prison to the top of it:**

1. **Storeys 6 and 7** — the last two office storeys, authored as `TowerPlans.STOREYS`
   rows in the phase-14 format.
2. **Storeys 8 and 9 — THE LABYRINTH.** A hand-drawn maze of one-cell (1.94 m)
   corridors, two riddle gates, and dead-end chambers carrying the riddles' clues.
3. **Storey 10 — THE CELL BLOCK**, rebuilt from the phase-8 wing's layout onto the
   plan grid. **The graph room ids and every gate id are unchanged** — moving
   geometry is not a save migration, renaming an id is.
4. **The ground-floor cell wing is demolished**; its floor area is absorbed into the
   entry hall.
5. **The four rescue spines are re-expressed** as front door → ramps → maze → the
   hero's own identity door on storey 10, and **the custody scar is re-expressed** on
   the new geometry.
6. **The storey-8 landing becomes an unlockable lift stop** — the entry row, its
   quest and its trigger ship now; the menu is bead `godot-test1-3iy.7`.

**`tower_selfcheck`'s 15-subset audit is LOAD-BEARING and must be green at the end of
every task below, with the cell block on storey 10.** So is
`tower_interior_selfcheck`, `capture_selfcheck`, `tower_shell_selfcheck`,
`chunk_stream_selfcheck` and `perf_selfcheck`.

## Context — READ THIS BEFORE WRITING CODE

Read, in this order, and do not skip them: `CLAUDE.md`'s tower notes, the header of
`scripts/tower_plans.gd` (the grid, the character table, the extension rule), the
header of `scripts/tower_graph.gd` (the three design laws), the legibility-language
block at the top of `scripts/tower_interior.gd`, and
`docs/plans/20260829-tower-storey-plans.md` (phase 14's plan — this one is its
sequel and reuses its vocabulary).

### Measured baseline on this branch (2026-08-29, after `godot --headless --path . --import`)

```
tower_selfcheck             0.40 s   "44 rooms, 48 edges, 10 gates, 2 entries, 2 scars — 15 subset walks clean"
                                     "3 storeys, 28 rooms, 3220 cells walkable, ramps 29.6, 27.3, 27.3 deg"
tower_interior_selfcheck   12.4 s    "56 keep boxes (budget 60)"
                                     "storey 2: 52 boxes / storey 3: 43 / storey 4: 52  (PLAN_BOX_BUDGET 90)"
                                     "28 meshes drawn (budget 28) for 203 boxes"
                                     "camera needs 3.95 m clear"
capture_selfcheck           9.1 s
tower_shell_selfcheck       0.7 s
```

Record the post-change numbers in the same shape in the final task.

### Hard invariants this work must not break

- **No `run_seed`, no `hash()`, no RNG anywhere in the tower.** The maze is
  hand-drawn and fixed forever. `grep -n 'run_seed\|randf\|randi\|hash(' scripts/tower_*.gd`
  must gain no hits.
- **One `StaticBody3D` for the whole interior**, one `CollisionShape3D` per solid box.
- **One `MeshInstance3D` per storey** for static geometry; only parts that move or
  recolour get their own node, and every one spends a `DRAW_BUDGET` slot.
- **No jump-gated traversal.** Apex 3.6125 m. Stairs are ramps; a tread of any height
  is a wall to a `CharacterBody3D`.
- **Design law 3 (edge-additive)** holds; the custody scar is its one sanctioned
  exception and stays enumerated in `scars`.
- **Gate ids and scar ids are persisted verbatim** — add, never rename.
  `updraft_shaft`, `phase_grate`, `collapsed_slab`, `hound_den`,
  `maintenance_crawl`, `riddle_stair`, `riddle_strongroom`, `tower_vault`,
  `tower_secure_door`, `tower_checkpoint`, `rotor_gate`, `custody_stair_collapse`,
  `tower_rescue_primm` — **all keep their spelling.**
  **Graph ROOM ids `service_stair`, `cell_gallery`, `cell_windman`, `cell_primm`,
  `cell_teibi`, `cell_phoboman` keep their spelling too** (the bead is explicit).
  **EDGE ids and BOX names are NOT persisted** and may be renamed freely.
- The flat-world invariant is untouched — all of this is interior, above y = 0.

### Files this phase touches

- `scripts/tower_plans.gd` — five new `STOREYS` rows, and only that.
- `scripts/tower_interior.gd` — floor table, neighbours, budgets, the gate builder,
  the relocated block, the stand points, the lift-stop trigger.
- `scripts/tower_graph.gd` — rooms, edges, gates, spines, scars, entries, quests,
  mutations. Data only.
- `scripts/tower_selfcheck.gd` — check 8's box source, and new assertions.
- `scripts/tower_interior_selfcheck.gd` — every `boxes()` site that means "the cell
  block", the storey-10 floor path, the budgets, the visibility assertion.
- `scripts/player_controller.gd` — **one line**: `CUSTODY_STAND` becomes a call.
- `CLAUDE.md` — the tower subsection.

## The design, decided — these are rulings for this plan, do not re-derive them

### D1. Where the new storeys go

`FLOOR_Y` grows from 5 entries to 10. Nothing is written twice: the storeys count off
the shell's own grid exactly as phase 14's do.

| floor index | storey | walking surface y | clear height |
|---|---|---|---|
| 4 | 5 (executive, phase 14) | 21.0 | 4.6 (was 29.0 — storey 6's slab is now above it) |
| 5 | **6 — operations** | 26.0 | 4.6 |
| 6 | **7 — security** | 31.0 | 4.6 |
| 7 | **8 — labyrinth, lower** | 36.0 | 4.6 |
| 8 | **9 — labyrinth, upper** | 41.0 | 4.6 |
| 9 | **10 — the cell block** | 46.0 | **4.0** |

```gdscript
const FLOOR_Y: Array[float] = [
	0.0,
	SLAB_Y,
	TowerShell.KEEP_HEIGHT,
	TowerShell.KEEP_HEIGHT + TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 2.0 * TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 3.0 * TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 4.0 * TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 5.0 * TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 6.0 * TowerShell.STOREY_HEIGHT,
	TowerShell.KEEP_HEIGHT + 7.0 * TowerShell.STOREY_HEIGHT,
]
```

`FLOOR_NEIGHBOURS` gains five rows AND **index 4 changes from `[3]` to `[3, 5]`** —
storey 5 is no longer the top of the building:

```gdscript
	[3, 5],     # 4 storey 5 — storey 6's slab is now its ceiling
	[4, 6],     # 5 storey 6
	[5, 7],     # 6 storey 7
	[6, 8],     # 7 storey 8 — the labyrinth's lower half
	[7, 9],     # 8 storey 9 — its upper half
	[8],        # 9 storey 10, the cell block, under the sealed roof
```

**THE TOP STOREY'S 4.0 m OF CLEAR HEIGHT IS THE TIGHTEST NUMBER IN THIS PHASE.**
The roof's underside is `TowerShell.WALL_HEIGHT` = 50.0 and floor 9 walks at 46.0.
`tower_interior_selfcheck` check 4 requires 3.95 m for the indoor camera boom, so
storey 10 clears it by 5 cm. That is fine and it is also fragile: **assert it, and
say in the comment that raising `SLAB_THICK` or lowering `ROOF_THICK`'s reach is what
would break it.**

### D2. A NEW BUILDER RULE: a storey's walls are as tall as its clear height

Today `_merge_walls` and the riddle mass use `TowerShell.STOREY_HEIGHT - SLAB_THICK`
(4.6) for every storey. On floor 9 that would put wall tops at 50.6 m — **through the
sealed roof**, which check 1 refuses. So:

```gdscript
static func plan_clear_height(floor_index: int) -> float:
	"""
	The clear air over one planned storey's walking surface: floor to the underside
	of whatever is above it — the next storey's slab, or the shell's roof for the
	top one. Walls, gate masses and light panels are all sized off this, so a storey
	under the roof is not built to the same height as one under a slab.
	"""
```

Its ceiling for the TOP planned floor is `TowerShell.WALL_HEIGHT`; for any other it is
`FLOOR_Y[next] - SLAB_THICK`. `tower_interior_selfcheck` already has a private
`_plan_clear_height`; **delete that copy and read this one**, so the builder and the
check cannot disagree.

Every place that used `STOREY_HEIGHT - SLAB_THICK` becomes `plan_clear_height(floor)`:
`_merge_walls`, the gate masses in `_plan_gates`, and the block's light panels.

### D3. `riddle_stair` moves off the main stair and onto the boardroom door

**This is forced, and here is the derivation — put it in the code comment.**

The bead requires a lift stop at the storey-8 landing, and `tower_selfcheck` check 10
requires that *from every legal entry*, with a riddle treated as a wall, the full
roster can still reach that riddle's clue room. `riddle_stair` sits across the ONLY
passage between `s5_stairhead` and `s5_landing`, and its clue is on storey 3 — below
it. Enter at storey 8 and the descent to the clue crosses the gate the clue explains.
**Any riddle across the main vertical spine below the lift stop is unauditable once
that stop exists**, and the audit is right to say so: a player lifted to storey 8 on a
fresh profile really would be locked out of the clue.

So `riddle_stair` becomes **optional side content in the mould of
`riddle_strongroom`**: its mass moves off the stairhead's east end and onto the
**boardroom's doorway** on storey 5, and its four pads move to the ring corridor in
front of it (same "the thing you are opening is in your eye line" rule the strongroom
follows). Its clue room stays `s3_records_east` and its answer stays `[3, 1, 4, 2]`.

Graph consequences, all in `tower_graph.gd`:

- `s5_stairhead_landing` (`s5_stairhead` ↔ `s5_landing`) loses its gate — `""`.
- `s5_landing_boardroom` gains `"gate": "riddle_stair"`.
- `s5_stairhead`'s note is rewritten: it is now just the head of the ramp.

`tower_plans.gd` consequence: storey 5's `gates` dict re-keys to the boardroom's
doorway cells and the new pad cells, and the `1234`/`D` characters move in its `rows`.
**Nothing else about storey 5 changes** and its ramp is untouched.

### D4. The two maze routes, and which one the spines walk

**`_check_spines_at_the_readiness_floor` calls `_passable(gid, free, FLOOR)` with an
EMPTY solved set, so a riddle gate on a spine's edge list FAILS THE BUILD.** That is
correct behaviour — a spine is the promise that one hero alone can walk it with no
prior knowledge — and it decides the maze's topology:

- **ROUTE A — "the long way", UNGATED end to end.** This is what the four spines walk.
  It is the longer of the two through the maze: up the storey-8 landing, round the
  outer circuit, across the storey-9 ramp at the far corner, round again to the
  storey-10 ramp.
- **ROUTE B — "the short way", behind the two riddles.** `riddle_maze_lower` on
  storey 8 and `riddle_maze_upper` on storey 9, in series. It cuts most of both
  circuits.

Both are base-kit (a riddle asks nothing of who you are and nothing of rank), which is
the bead's "at least two maze routes from the storey-8 landing to the storey-10 stair,
both base-kit". Because route A exists, **`needed_during_captivity` is `false` for both
maze riddles** — check 6 recomputes this and will fail on any disagreement, so author
the flag as `false` and let the check confirm it.

The two riddles' clue rooms are **dead-end chambers off route A on storey 8**, so they
are reachable both from the front door (walking up) and from the lift stop (walking
along) with either riddle shut. Each clue chamber must be **at least 4 cells wide in a
single row** — `TowerInterior.clue_strip` paints four marks in a row and check 10
fails a room too narrow for them.

### D5. The cell block on storey 10 — the plan owns the walls, the masses and the pads

The phase-8 wing's LAYOUT is preserved exactly — a corridor, four identity doorways in
one wall, a gallery, four uniform open-fronted recesses — and re-drawn on the plan
grid, where a doorway is one cell (1.94 m, comfortably over the 1.5 m that clears a
giant Teibi) and a pier is one cell.

**`_wing_boxes()` is deleted. `_plan_riddles()` is generalized into `_plan_gates()`**,
which dispatches on `TowerGraph.gate(id)["class"]`:

| class | what the `D` run emits | what else |
|---|---|---|
| `riddle` | the mass, `COLOR_RIDDLE`, `dynamic`, rises | its `1234` pads from the `gates` dict, plus any clue strip this storey carries — **unchanged behaviour** |
| `identity` | the mass, `COLOR_IDENTITY`, `dynamic`, **sinks** | one `COLOR_IDENTITY_PAD` plate, auto-placed |
| `challenge` | a **lintel**: a partial-height wall over the run, `COLOR_STONE`, batched | nothing — the hazard that sweeps under it is a hand-built box positioned from the same run |

**The identity mass sinks and does not rise, and the reason is the phase-8 reason
verbatim: it fills its doorway floor-to-ceiling, and a mass as tall as the room has
nowhere to go but down.** Do not re-argue it; cite the existing comment.

**Where the identity pad goes is DERIVED, never authored:** of the two cells 4-adjacent
to the run's midpoint across the run's short axis, the pad goes on the one that is
`FLOOR_CHAR` (the corridor side). If both sides are floor, or neither is, that is an
authoring error and the self-check must name it — a pad on the wrong side of a door is
a gate you open from inside the room it guards.

**Box names.** Unify on `"%sGateMass_%s" % [prefix, gate_id]` and
`"%sGatePad_%s" % [prefix, gate_id]` for every class, replacing phase 15's
`%sRiddleMass_%s`. Update the two riddle rows' `parts` in `tower_graph.gd` and the
four `SPINE_DOORS` rows' `mass`/`pad` fields to the generated names. `MOVING_PARTS`
reads the names out of `SPINE_DOORS`, so it follows; add the two maze riddle masses to
it the way phase 15 added its two. Box names are not persisted — this is free.

**What stays hand-built**, because the plan format cannot express it, and every one of
them takes its position from a plan lookup rather than from a fresh constant:

| box | positioned from |
|---|---|
| `CrawlLintel` (if not emitted by the challenge arm) and `CrawlPress` | the `maintenance_crawl` `D` run on storey 10 |
| `CellFrame<Hero>` ×4 | the `cell_<hero>` room's cell rect |
| `PrimmContainment` | the `cell_primm` room's cell rect |
| `PurgePad` | the `cell_gallery` room's cell rect, at its +X end |
| `PanelCorridor`, `PanelGallery` | the `service_stair` / `cell_gallery` rects |
| `StairCollapse` (the scar) | the `block_main_door` doorway's cells |

Add the helper these all use:

```gdscript
static func plan_room_rect(floor_index: int, room_id: String) -> Rect2i:
	"""The cell bounding box of one graph room on one storey, `Rect2i()` if absent."""

static func plan_gate_rect(floor_index: int, gate_id: String) -> Rect2i:
	"""The cell bounding box of one gate's `D` run on one storey."""
```

`plan_gate_rect` is `riddle_slots(plan)["masses"]` looked up by id — reuse it, do not
write a second walker.

**These boxes go into `plan_boxes(9)`, NOT into `boxes()`.** Check 1 fits `boxes()`
against the keep's `INNER_HALF` (8.8 m) and plan boxes against `PLAN_HALF` (38.8 m);
the block now spans the wide grid, so it belongs to the plan population. Keep it in
its own `_block_boxes(plan)` function appended by `plan_boxes()` for the floor that
draws the block — one `if` in `plan_boxes`, keyed on the storey drawing a
`cell_gallery` room, not on the literal 9.

**Derived stand points.** `CUSTODY_STAND` and `cell_stand()` and `block_min()` /
`block_max()` are re-derived from the plan rects and the storey-10 `FLOOR_Y`.
`CUSTODY_STAND` becomes `static func custody_stand() -> Vector3` (the corridor's
centre, clear of all four doorways, `+0.2` lift as today); update its two callers,
`player_controller.gd:2880` and `tower_interior_selfcheck.gd`.
`_spine_door_x` / `_spine_pier_x` / `_cell_x` / `_cell_width` / `wing_span` are
**deleted** — the grid answers all of those now — along with the constants they were
built from (`WING_Z`, `WING_JOG_X`, `WING_JOG_Z`, `SPINE_Z`, `SPINE_DOOR_W`,
`SPINE_PIER_W`, `CELL_Z0`, `CELL_DIVIDER`, `PAD_Z`, `PAD_DEPTH`, `PURGE_PAD_X`,
`PURGE_PAD_Z`, `CRAWL_X0`, `CRAWL_X1`). Keep `SPINE_TRAVEL`, `PAD_TRIGGER_DEPTH`,
`CRAWL_LINTEL_Y`, `PRESS_TOP`, `PRESS_BOTTOM`, `PRESS_PERIOD`, `PURGE_*` timings —
those are behaviour, not placement. Every self-check that drove the deleted helpers
gets re-pointed at the plan rects.

### D6. The ground floor loses the wing

`_wing_boxes()`'s output is gone from floor 0. The strip north of the old `WING_Z`
becomes **part of the entry hall** — same slab over it, same 4.2 m of headroom, and
one light panel kept so it is not a dark void.

**No new graph room.** The bead says "its boxes go; its graph rooms are re-pointed to
storey 10 plan letters", and the re-pointing is exactly D5. Adding a `keep_offices`
row would be a room with no gate, no cell and no quest — a row the audit cannot use.
Update `entry_hall`'s note to say the hall now runs the keep's full depth, and update
the route narrative at the top of `tower_interior.gd` (the "…and, off the hall to the
NORTH (phase 8), THE CELL BLOCK WING" block moves to storey 10).

### D7. The scar, re-expressed

The scar id `custody_stair_collapse` is **persisted and does not change**. What changes
is the edge it severs, because the corridor it severed is now 46 m higher.

On storey 10 the block is entered from `s10_landing` two ways, which is the same
redundancy the phase-8 wing had and for the same reason:

| edge id | from → to | gate | note |
|---|---|---|---|
| `block_main_door` | `s10_landing` ↔ `service_stair` | `""` | the wide doorway. **The scar drops this one.** |
| `block_crawl` | `s10_landing` ↔ `service_stair` | `maintenance_crawl` | the duct with the stamping press. Base kit, so no subset can be stopped by it. **This is what makes the scar survivable.** |

`courtyard_stair` and `hall_stair` are **renamed** to these (edge ids are not
persisted; the note in `tower_graph.gd`'s gate-id header says only `gates` keys are).
Update `scars[custody_stair_collapse].removes` to `["block_main_door"]` and the
`StairCollapse` box's `"severs"` to the same.

**`tower_selfcheck` check 8 (`_check_scars_are_built`, `:1221`) reads
`TowerInterior.boxes()` and must read `TowerInterior.all_boxes()`** — the scar box now
lives in `plan_boxes(9)`. The bead names this landmine explicitly; it is the check that
stops the scar shipping inert.

### D8. The spines

```gdscript
	"spines": {
		"windman": {"entry": "front_door", "edges": [
			"hall_outer", "outer_s3", "s3_s4", "s4_s5", "s5_stairhead_landing",
			"s5_s6", "s6_s7", "s7_s8",
			<route A's ungated maze edges, storey 8>,
			"s8_s9",
			<route A's ungated maze edges, storey 9>,
			"s9_s10", "block_main_door", "stair_gallery_windman"]},
		… the same list for primm / teibi / phoboman, differing only in the last edge
	},
```

Every edge on it must be ungated or challenge-gated. **`rotor_gate` is no longer on any
spine** — the route now leaves the entry hall through `hall_outer` into the annulus.
Its `needed_during_captivity` is still expected to be `true` (from `lift_stop_upper`
with the scar taken, the rotor doorway is the only way back down out of the keep), but
**do not hand-tune any `needed_during_captivity` flag: author your best answer and let
check 6 correct you.** It recomputes every one over every story × scar × entry × subset
and fails on disagreement.

### D9. The lift stop

Four data rows and one small trigger:

```gdscript
# rooms
"s8_landing": {"built": true, "quest": "maze_landing", "cell": "", "parts": [], "note": …},
# edges
{"id": "lift_shaft_maze", "a": "entry_hall", "b": "s8_landing", "gate": "", "built": false},
# entries
{"id": "lift_stop_maze", "room": "s8_landing", "built": false, "note": …},
# quests
{"id": "maze_landing", "room": "s8_landing", "requires_quest": "", "note": …},
# mutations
{"id": "lift_stop_maze_unlocked", "trigger": "maze_landing",
 "adds": ["lift_shaft_maze"], "adds_entries": ["lift_stop_maze"], "note": …},
```

The audit walks the BASE graph from every entry any mutation can grant, so **the
15-subset property is re-asked starting at the storey-8 landing** — that is what makes
this an audited entry rather than a promise, and it is where D3 and D4 come from.

In the building: one `Area3D` `LiftStopTrigger` over the storey-8 landing cells that
calls `_open("lift_stop_maze")` on the local player's first entry. Same shape as
`CheckpointTrigger` — reuse it, do not invent a second pattern. The stop id rides the
monotone opened set and is **persisted verbatim**. The menu that offers the stop is
bead `godot-test1-3iy.7`; **do not build a menu here.**

### D10. The plan text IS the design record

Each maze storey's `note` and the comment block above its row carry:

- what the floor is,
- **the solution path, written out as a cell-by-cell route** ("from the landing at
  (c, r): east 6, north 4, …"), for BOTH route A and route B, per the bead;
- which dead ends carry which riddle's clue.

There is no seed and there may never be one. A future author edits the text.

## Budgets and the web frame budget

- **`PLAN_BOX_BUDGET` rises.** A one-cell maze legitimately produces many merged
  rects — that is the maze, not a merging bug. Measure the real per-storey counts,
  set the constant to the largest **rounded up with a stated margin**, and REWRITE its
  comment to say what it now guards: it is still "this floor's walls stopped merging",
  but the yardstick is now a maze floor's measured rect count rather than an office
  floor's.
- **`DRAW_BUDGET` rises by exactly the new nodes**: five storey batches and the two
  maze riddle masses. The block's four masses, four cell frames, press, containment
  and scar box are *moved*, not added, so they spend nothing new. Recount and state
  the arithmetic in the comment, phase-14 style. **If the count is higher than that,
  something left the batch — find it, do not raise the number.**
- **`BOX_BUDGET` (the keep's own population) FALLS** as the wing leaves `boxes()`.
  Lower it to the measured count plus a small stated margin and rewrite the comment,
  which currently explains 60 in terms of the wing.
- **Collision shapes.** One `CollisionShape3D` per solid box on one `StaticBody3D`; two
  maze storeys add a few hundred. Print the total in check 5's line and add a stated
  ceiling for it. They are static box shapes on one body, which is the cheapest thing
  Godot's broadphase holds, but the number should be visible rather than discovered.
- **Visibility.** `_update_visibility` is one boolean write per floor and
  `FLOOR_NEIGHBOURS` is a ±1 window, so **standing on storey 9 draws 8, 9 and 10 and
  nothing else** — the maze must not show the cell block through the floor, and the
  slabs are solid. Extend `tower_interior_selfcheck` check 9 to assert, **for every
  floor index**, that at most three storey batches are visible and that floor 9's batch
  is hidden from every floor below 8. The **8 → 9 transition rebuilds nothing** — it
  toggles `visible` — and check 9 is where that claim is made.
- Run `perf_selfcheck` and `chunk_stream_selfcheck` unchanged; they must stay green.

## Tasks

Each task ends with **every named self-check printing `SELFCHECK OK`**, a commit, and
a push. A fresh worktree needs `godot --headless --path . --import` once before any
self-check, and again after touching `assets/`.

Self-check command shape:

```bash
godot --headless --path . --script res://scripts/<name>.gd
```

---

### Task 1: the floor table, the clear-height rule, and storeys 6 and 7

**Scope:** `tower_interior.gd`, `tower_plans.gd`, `tower_graph.gd`,
`tower_interior_selfcheck.gd`. **Not** the maze, **not** the cell block.

- [x] `FLOOR_Y` and `FLOOR_NEIGHBOURS` per **D1**, including the change to index 4.
- [x] `plan_clear_height()` per **D2**, used by `_merge_walls` and the gate masses;
   delete `tower_interior_selfcheck`'s private copy and read the new one.
- [x] Author **storey 6 (floor 5)** and **storey 7 (floor 6)** as `STOREYS` rows in the
   phase-14 idiom. They are office floors: a ring-and-cross skeleton like storey 3's,
   but a *different plan* — do not ship storey 3 with the letters changed. Storey 7 is
   "security": its rooms are where the maze's fiction starts (a control room, a
   records vault, a briefing room).
   Each needs: the outer ring of `#`; an `S` lane of **at least 5 cells** on X with its
   `s` landing against one short end (5 cells is 9.7 m for a 5.0 m rise, slope 0.5155,
   under the proven 0.575 ceiling); **exactly two `P` pads**, each 4-adjacent to a room
   letter; every lane cell standing over a walkable cell of the storey below (not `#`,
   not `S`); and every lettered cell reachable by 4-connected flood fill from the
   landing.
   **Walk the two ramps apart** — do not stack every stairwell in one shaft.
- [x] `TOWER_GRAPH` rooms and edges for both storeys, all ungated, in the phase-14 style
   (`s6_landing` + its rooms, `s7_landing` + its rooms, `s5_s6`, `s6_s7`, and one
   `s<n>_landing_<room>` edge per room).
- [x] Apply **D3**: `riddle_stair` moves to the boardroom doorway on storey 5. Edit
   storey 5's `rows` and `gates`, and the two `tower_graph.gd` edges. Write the
   derivation from D3 into the comment above the gate row — a future author WILL try
   to put a riddle back across the stair.
- [x] Raise `PLAN_BOX_BUDGET` / `DRAW_BUDGET` only as far as the measured counts require.

**Verify:** `tower_selfcheck`, `tower_interior_selfcheck`, `tower_shell_selfcheck`.

---

### Task 2: the labyrinth, storeys 8 and 9

**Scope:** `tower_plans.gd`, `tower_graph.gd`, and budget constants.

- [x] Author **storey 8 (floor 7)** and **storey 9 (floor 8)** as `STOREYS` rows: a
   hand-drawn maze of **one-cell (1.94 m) corridors** with `#` walls, per **D4** and
   **D10**.
- [x] **Route A**, ungated, from the storey-8 landing to the storey-9 ramp and on to the
   storey-10 ramp. **Route B**, shorter, through `riddle_maze_lower` (storey 8) and
   `riddle_maze_upper` (storey 9) in series. Both reach the storey-10 stair.
- [x] **Dead ends with clue chambers.** Each maze riddle's clue room is a dead-end chamber
   **at least 4 cells wide in one row**, off route A on storey 8, reachable from the
   landing with either riddle shut. Author several *decoy* dead ends too — a maze with
   no wrong turns is a corridor.
- [x] The two riddle gate rows in `TOWER_GRAPH`: `class: CLASS_RIDDLE`, `identity: ""`,
   `clue_room` naming its chamber, `answer` a 4-step **permutation** of `1234`,
   `needed_during_captivity: false`, `parts` naming the generated mass box.
   `1`–`4` pad cells in front of each mass, bound through the storey's `gates` dict.
- [x] Graph rooms and edges for both storeys, wired so route A is ungated and route B
   carries the riddles. Wire `s7_s8` and `s8_s9`.
- [x] **Solid slabs.** Nothing about the maze may let storey 10 be seen from storey 9 —
   the slab is the full footprint minus the derived stairwell hole, which is already
   how `_plan_slab` works. Do not add a hole.
- [x] Re-measure the budgets; `PLAN_BOX_BUDGET` is expected to move most here.

**Verify:** `tower_selfcheck` (the flood fill is what proves the maze is connected),
`tower_interior_selfcheck`, `tower_shell_selfcheck`.

---

### Task 3: the cell block moves to storey 10

The big one. **Scope:** everything in the file list.

- [ ] `_plan_riddles` → `_plan_gates` with the three class arms and the derived identity
   pad, per **D5**. Unify the box names; update the two riddle `parts` rows.
- [ ] Author **storey 10 (floor 9)**: the landing, the two ways into the corridor
   (`D` run for `maintenance_crawl`, an open doorway for the main door), the corridor
   (`service_stair`), four `D` runs for `updraft_shaft` / `phase_grate` /
   `collapsed_slab` / `hound_den` in one wall with a pier between each, the gallery
   (`cell_gallery`), and four uniform open-fronted recesses lettered to
   `cell_windman` / `cell_primm` / `cell_teibi` / `cell_phoboman`.
   **The room ids are the phase-8 ids, verbatim.**
- [ ] `_wing_boxes()` → `_block_boxes(plan)`, appended by `plan_boxes()` for the storey
   that draws `cell_gallery`. Every position from `plan_room_rect` / `plan_gate_rect`.
   Delete the placement constants and helpers listed in **D5**.
- [ ] **D6:** the ground floor loses the wing; the strip is absorbed into the entry hall,
   one light panel kept. Update the file header's route narrative.
- [ ] **D7:** rename the two edges, re-point the scar's `removes` and the box's `severs`,
   and change check 8 to `all_boxes()`.
- [ ] **D8:** the four spines.
- [ ] Re-derive `custody_stand()`, `cell_stand()`, `block_min()`, `block_max()`; update
   `player_controller.gd`'s one call site.
- [ ] Re-point every `tower_interior_selfcheck` assertion that named the wing: the
   `"Floor0/CellTrigger%s"` node path becomes `Floor9/…` (derive the index from the
   storey that draws the block, do not hardcode 9 twice), the spine-door spacing
   checks become plan-rect checks, and checks 16/17 (the full-custody protocol scene)
   follow the stand to storey 10.
- [ ] Budgets: `BOX_BUDGET` falls, `DRAW_BUDGET` recounted per the arithmetic in
   **Budgets**.

**Verify:** `tower_selfcheck`, `tower_interior_selfcheck`, `capture_selfcheck`,
`tower_shell_selfcheck`.

---

### Task 4: the lift stop, the visibility and budget assertions, the docs

- [ ] **D9:** the entry, edge, quest and mutation rows, plus the `LiftStopTrigger`
   `Area3D` and its `_open("lift_stop_maze")`. No menu.
- [ ] Extend `tower_interior_selfcheck` check 9 per **Budgets → Visibility**: for every
   floor index, at most three storey batches visible, and floor 9's batch hidden from
   every floor below 8.
- [ ] Print the collision-shape total in check 5 and assert a stated ceiling.
- [ ] `CLAUDE.md`: the tower subsection gains the storey table, the "walls are as tall as
   their clear height" rule, the two-route maze rule and the "the plan text is the
   design record, there is no seed" line. **Keep it a map, not the territory** — the
   reasoning belongs beside the code.
- [ ] Run **every** self-check and record the numbers in the shape of the baseline block
   above: `tower_selfcheck`, `tower_interior_selfcheck`, `capture_selfcheck`,
   `tower_shell_selfcheck`, `chunk_stream_selfcheck`, `perf_selfcheck`.

**Verify:** all six.

## Definition of done

- Every self-check above prints `SELFCHECK OK`.
- `tower_selfcheck` reports the 15 subset walks clean **in both scar states and from
  both the front door and the storey-8 lift stop**, with the cell block on storey 10.
- The maze flood-fills connected on both storeys and has **two base-kit routes** from
  the storey-8 landing to the storey-10 stair.
- No new `run_seed` / `hash()` / RNG hit in `scripts/tower_*.gd`.
- Every persisted id (gates, scars, cell block rooms) is spelled exactly as it was.
- Budget constants are the measured numbers with comments that explain them.
