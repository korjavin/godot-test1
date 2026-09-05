class_name TowerPlanBoxes
extends RefCounted
## THE TOWER'S PLAN WALKER — ASCII into boxes, and the geometry banner it reads.
##
## Lifted whole out of `tower_interior.gd` by bead `godot-test1-ftn.19`, the first
## of the epic's three tower extractions. It is a MECHANICAL move: not one box,
## colour, name, budget or route step changed, and the acceptance is an A/B of
## `all_boxes()` byte-for-byte against master.
##
## WHY THIS IS THE CUT. Everything here answers a question about `TowerPlans`'
## text and `TowerShell`'s envelope — where a storey's walking surface is, which
## cells are stone, where the ramp rises, which way a guard walks. None of it
## needs the interior INSTANCE: every function was already `static`, which is what
## made the seam obvious rather than invented. `tower_interior.gd` keeps the
## SCENE — the built nodes, the gates, the guards, the captives, the dressing
## seam — and the plan arithmetic they all stand on lives here.
##
## THE DEPENDENCY DIRECTION, and it is the one thing to keep straight:
##
##   TowerInterior --const--> TowerPlanBoxes      (the aliases: FLOOR_Y, SLAB_Y,
##                                                 PLAN_RAMP_MAX_SLOPE, ...)
##   TowerPlanBoxes --runtime--> TowerInterior    (the palette, `_plan_prefix`,
##                                                 `_deck_box`, and the set-piece
##                                                 builders `plan_boxes` calls)
##
## The const direction is ONE WAY. The reach back is only ever inside a function
## body, which is exactly the shape `TowerInterior` and `TowerDressing` have had
## since bd `godot-test1-ftn.12` and which Godot resolves without complaint; a
## top-level `const` pointing the other way would make it a parse-time cycle and
## must not be added.
##
## `plan_boxes()` STAYS THE ONE SEAM THE DRESSING ENTERS THROUGH (CLAUDE.md). It
## moved house; it did not change shape, and `TowerDressing.plan_dressing()` is
## still its last call, still handed everything the storey drew before it.
##
## EVERY NAME IS ALIASED BACK on `TowerInterior` — eleven consts and seventeen
## one-line static forwarders — so the forty-four readers of `FLOOR_Y`, the
## thirty-seven of `_grid_x`/`_grid_z` and the twenty-two of
## `PLAN_RAMP_MAX_SLOPE` across the terrain, the minimap, the guard AI, the city
## plan and eight self-checks are untouched by this bead. Only the tower's own
## self-checks name this script directly.
##
## `TowerDressing`'s idiom: `class_name`, all `static`, holds no scene state.

# ============================================================================
# GEOMETRY — metres, LOCAL to the shell's origin, feet at y = 0
# ============================================================================
#
# THERE ARE NO AUTHORED WIDTHS IN HERE ANY MORE. Every horizontal number the
# interior used to carry — the keep's inner faces, the slab's west edge, the jambs,
# the ramp's lane, the secure partition — described the phase-3 KEEP, a windowless
# 20 m box standing in the middle of the 80 m hall. Bead `godot-test1-dn8`
# demolished it and drew floors 0 and 1 on `TowerPlans`' grid like every other
# storey, so what is left below is HEIGHTS and RHYTHMS: how tall a storey is, how
# far a mass travels, how fast a bar sweeps. Where something stands is read out of
# the plan (`plan_room_rect`, `plan_gate_rect`), which is the same rule the cell
# block has followed since phase 16 and the reason it could change floors without
# a number following it.

## The upper storey. `SLAB_Y` is its WALKING SURFACE; the slab hangs below it, so
## the ground floor's headroom is `SLAB_Y - SLAB_THICK`.
##
## 4.6 is the smallest number that satisfies both rules at once: it must exceed
## the jump apex (3.6125) plus the tallest thing standing under it (0.7) with
## margin, and `SLAB_Y - SLAB_THICK` must exceed the camera's 3.5 m float. Raising
## it costs shell wall height; lowering it breaks one of the two.
const SLAB_Y: float = 4.6
const SLAB_THICK: float = 0.4

## How thick a ramp deck is. The only survivor of the phase-3 ramp's own constants:
## `_deck_box()` still places every ramp in the building by its TOP face and derives
## the centre half a thickness along the deck's normal, and this is that thickness.
const RAMP_THICK: float = 0.4

# ============================================================================
# THE HAND-PLANNED STOREYS (phase 14) — where they sit and what they may be
# ============================================================================
#
# The plan itself is TEXT and lives in `tower_plans.gd`; everything here is the
# arithmetic that turns a storey row into boxes. Read that file's header first —
# it carries the grid, the character table and the extension rule ("a new storey
# is one STOREYS row plus its TOWER_GRAPH rows, and NO builder edit").

## The first office storey's walking surface, and the one number in this table that
## is HISTORY rather than arithmetic: 11.0 m was the phase-3 keep's parapet, and the
## seven storeys above it plus the sealed roof were sized off it. The keep is gone
## (bd godot-test1-dn8); the height stays, because moving it would move storeys 3-10
## and the roof, and this bead demolishes a building, not the tower.
##
## It lived on `TowerShell.KEEP_HEIGHT` until that bead deleted the ring it measured.
## Here rather than there because nothing outside this file needs it any more: the
## shell is one envelope now, and the only thing 11.0 m still means is "where the
## podium's storeys start".
const PODIUM_Y: float = 11.0

## The walking surface of every storey, in interior-local metres. The index is the
## `floor` a box declares and the container `_update_visibility` toggles.
##
## The first two used to be the phase-3 keep — the hall at 0 and the mezzanine on
## its slab — and every value here is unchanged by the demolition that drew them on
## the plan grid instead. The rest sit on `PODIUM_Y` and rise on the SHELL's own
## storey grid, so a storey is never a number written down twice here — it is
## `STOREY_HEIGHT` counted off the podium. Retune the shell constant and these move
## with it.
const FLOOR_Y: Array[float] = [
	0.0,
	SLAB_Y,
	PODIUM_Y,
	PODIUM_Y + TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 2.0 * TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 3.0 * TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 4.0 * TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 5.0 * TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 6.0 * TowerShell.STOREY_HEIGHT,
	PODIUM_Y + 7.0 * TowerShell.STOREY_HEIGHT,
]

## Which storeys physically TOUCH each one. THE VISIBILITY WINDOW'S ADJACENCY.
##
## IT IS PLAIN ADJACENCY AGAIN, AND THAT IS A DEMOLITION AND NOT A SIMPLIFICATION.
## It was `[1, 2]` / `[0, 2]` / `[0, 1, 3]` at the bottom while floor 1 was the
## KEEP'S MEZZANINE — a 20 m square of slab over the courtyard and nothing else, so
## the 80 m annulus at floor 0 ran straight past it to floor 2's slab, which was its
## ceiling two indices away. Index arithmetic hid that ceiling while it was solid and
## hid the grand ramp from the head of the grand ramp: invisible collision, on
## exactly the walk phase 14 was judged on (codex review, 2026-08-29). Bead
## `godot-test1-dn8` demolished the keep and drew floor 1 as a full 80 m plate, so
## floor 1's slab now roofs floor 0 everywhere and there is no storey with two rooms
## under it.
##
## IT STAYS A TABLE. `_floor_visible` reads it and `tower_interior_selfcheck` check 9
## asserts the RELATION's properties — symmetric, reflexive, at most three storeys
## drawn — never the table read back to itself, so the day a mezzanine is authored
## again the window is one row here and no arithmetic anywhere. A new plan storey
## appends `[previous, next]`, the same one-line edit `FLOOR_Y` takes.
const FLOOR_NEIGHBOURS: Array[Array] = [
	[1],        # 0 storey 1, the entry hall — floor 1's slab is its whole ceiling
	[0, 2],     # 1 storey 2, the muster floor
	[1, 3],     # 2 storey 3, records
	[2, 4],     # 3 storey 4, accounts
	[3, 5],     # 4 storey 5, executive — storey 6's slab is its ceiling since phase
	            #   16; it was `[3]` only while it was the top of the building
	[4, 6],     # 5 storey 6, operations
	[5, 7],     # 6 storey 7, security
	[6, 8],     # 7 storey 8 — the labyrinth's lower half
	[7, 9],     # 8 storey 9 — its upper half
	[8],        # 9 storey 10, the cell block, under the sealed roof
]

## How much clear air a plan ramp keeps under the slab it climbs towards.
##
## The player's capsule is 2.0 m; 2.2 is that plus a margin. It is what sizes the
## STAIRWELL HOLE: the slab is cut from the point on the deck where the ceiling
## would be `SLAB_THICK + PLAN_HEADROOM` overhead, so walking up a ramp never ends
## with your head in the floor you are about to stand on.
const PLAN_HEADROOM: float = 2.2

## How proud of the floor a plan pad's plate stands. Low enough that walking onto
## one is not a step (`CharacterBody3D` has no step-up, so anything you can trip on
## is a wall), high enough to read as a plate and not as paint.
const PLAN_PAD_THICK: float = 0.1

## THE STEEPEST A PLAN RAMP MAY BE, and the number carries its own provenance.
##
## It USED to be derived — `SLAB_Y / (SLAB_X0 - RAMP_X0)`, the phase-3 keep ramp's
## own slope — precisely so that retuning the proven ramp retuned the ceiling with
## it. Bead `godot-test1-dn8` deleted that ramp along with the keep it climbed, so
## the derivation would now read off constants that no longer exist. The VALUE is
## unchanged and it is not a fresh one: 4.6 m of rise over 8.0 m of run, 29.9
## degrees, the ramp this game has shipped and been walked on since phase 3 without
## anybody sliding back down it.
##
## It is a CEILING and not a target. Every ramp drawn since is gentler (storey 3's
## grand ramp is 0.330 and floor 1's is 0.395); what this stops is a plan author
## saving cells by drawing a lane nobody has ever walked. `tower_selfcheck` and
## `tower_interior_selfcheck` both assert against it.
const PLAN_RAMP_MAX_SLOPE: float = 0.575


## A STOREY'S WALLS ARE AS TALL AS ITS CLEAR HEIGHT, AND THAT IS NOT ALWAYS
## `STOREY_HEIGHT - SLAB_THICK`.
##
## Phase 16 fills the shell to its sealed roof, and the top storey has no slab over
## it — its ceiling is `TowerShell.WALL_HEIGHT`. Build that floor to the ordinary
## 4.6 m and its walls, its gate masses and its light panels all end up THROUGH the
## roof, which check 1 refuses; leave the roof-height number written down anywhere
## but here and it stops agreeing with `FLOOR_Y` the day a storey is added.
##
## So it is one function, read by `_merge_walls`, by the gate masses and by
## `tower_interior_selfcheck` — which HAD a private copy and no longer does, because
## the builder and the check disagreeing about a storey's ceiling is precisely the
## failure this is here to make impossible.
static func plan_clear_height(floor_index: int) -> float:
	"""
	The clear air over one planned storey's walking surface.

	@param floor_index: An index into `FLOOR_Y`.
	@return: Floor to the underside of whatever is above — the next storey's slab,
	        or the shell's roof for the top one.
	"""
	if not TowerPlans.storey(floor_index + 1).is_empty():
		return FLOOR_Y[floor_index + 1] - SLAB_THICK - FLOOR_Y[floor_index]
	return TowerShell.WALL_HEIGHT - FLOOR_Y[floor_index]

## Hard cap on the boxes ONE plan storey may emit, asserted per storey by
## `tower_interior_selfcheck`. It is the shell's `BOX_BUDGET` discipline applied to
## the machine; the interior's own hand-placed budget went with the keep it counted
## (bd godot-test1-dn8), because every box in this building is a plan box now.
##
## A 40 x 40 grid is 1600 cells and could in principle be 1600 boxes; the whole
## reason `_merge_walls` exists is that it is not. What this number stops is a plan
## whose walls stopped merging — a chequerboard, a wall drawn one cell out of
## line with the one beside it, a partition every other cell — because each of
## those is a collision shape as well as a box, and the collision body is the one
## thing in this building that is not batched.
##
## MEASURED, not guessed, AND THE YARDSTICK IS NOW A MAZE FLOOR. The office
## storeys emit 29 to 52 boxes for around a thousand walkable cells apiece — one
## box per 20-odd cells, which is what a merge that is working looks like on a
## floor made of rooms. THE LABYRINTH IS THE HONEST WORST CASE: storey 8 emits 81
## and storey 9 emits 61, for 450 and 431 walkable cells, because a one-cell maze
## legitimately chops the solid stone it is cut into up into many rectangles. That
## is the maze and not a merging bug — and it is still one box per five or six
## cells, an order off the chequerboard this number exists to catch.
##
## 120 IS THE WORST FLOOR PLUS A HALF, and what it still stops is unchanged: a
## plan whose walls stopped merging blows through it on the first row (an unmerged
## 40-cell wall is 40 boxes on its own), because each box is a collision shape as
## well, and the collision body is the one thing here that is not batched.
const PLAN_BOX_BUDGET: int = 120

## ...and the same discipline for the FURNITURE, counted SEPARATELY and on purpose.
##
## Folding the dressing into `PLAN_BOX_BUDGET` would have meant tripling that
## number, and tripling it destroys the only thing it does: an unmerged 40-cell
## wall is 40 boxes, which is loud against 120 and invisible against 400. So the
## structure keeps its budget unchanged and the office keeps its own, and a
## regression in either one is still legible.
##
## MEASURED, per storey: 64 / 28 / 143 / 216 / 146 / 143 / 110 / 19 / 14 / 0. The
## office floors are the big ones (216 is the accounts floor's twelve rooms), the
## labyrinth floors are nearly all corridor and the cell block is all set piece.
## 300 is the worst floor plus about a third.
##
## IT WENT UP WITH THE WAYFINDING PLAQUES (bd godot-test1-kox): four more boxes per
## dressed office room, which is +48 on the accounts floor and nothing at all on the
## labyrinth or the block, neither of which is signed.
##
## ...AND AGAIN WITH THE SECOND DRESSING PASS (bd godot-test1-st9), which is where
## the bulk of it now is. Re-MEASURED, per storey: 127 / 94 / 346 / 440 / 345 / 324
## / 242 / 36 / 16 / 0. Three things moved it: `DRESS_SPACING` halved and the piece
## cap raised (a room goes from 7 dressed cells to 11-16), four new furniture kinds
## and two new art kinds (which are boxes per piece, not pieces), and the corridor
## benches and planters, up to fourteen a storey. 580 is the accounts floor's 440
## plus a third, the same headroom the number has always carried.
##
## What it catches is the dresser's OWN failure mode, which is not "the walls
## stopped merging" but "a rule stopped excluding": drop the threshold guard or the
## footprint test and every wall-adjacent cell in the building is a candidate, which
## is many thousands per storey rather than hundreds. That failure is an order of
## magnitude over this, which is why raising it stays honest.
const PLAN_DRESS_BUDGET: int = 580

# ============================================================================
# THE PLAN CACHE
# ============================================================================

## Floor index -> that storey's built boxes. `plan_boxes()` walks 1600 cells and is
## called many times per self-check run (`all_boxes()` is the plan's single source
## the way `boxes()` is, so every check asks for it); the plan is a `const` and can
## never change at runtime, so building it once is free correctness.
static var _plan_cache: Dictionary = {}

# ============================================================================
# THE PLAN BUILDER — text into boxes
# ============================================================================
#
# Everything below reads `TowerPlans.STOREYS` and knows about STOREYS, never about
# storey 3. That is the bead's acceptance criterion and it is a property of these
# functions: none of them names a floor, a room or a letter.

static func floor_y(index: int) -> float:
	"""The walking surface of a storey, in interior-local metres."""
	return FLOOR_Y[index]


static func plan_boxes(floor_index: int) -> Array[Dictionary]:
	"""
	One hand-planned storey, as boxes: its slab, its merged walls, its ramp and its
	pads.

	@param floor_index: An index into `FLOOR_Y`.
	@return: `boxes()`-shaped entries, or `[]` for a floor with no plan.

	THIS IS THE ONLY WAY BOXES ENTER THE BUILDING SINCE bd `godot-test1-dn8`. There
	used to be a hand-authored `boxes()` beside it holding the phase-3 keep; the keep
	is demolished, so `all_boxes()` is this function over `TowerPlans.floors()` and
	nothing else. Names are prefixed `S<floor>Plan`, which is what makes them unique
	across storeys without any of the four builders below knowing the others exist.
	"""
	if _plan_cache.has(floor_index):
		return _plan_cache[floor_index]
	var out: Array[Dictionary] = []
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		_plan_cache[floor_index] = out
		return out
	# THE SLAB IS COUNTED OFF SEPARATELY and never re-read below. It is the one
	# thing on a storey that covers every cell of it, so a dresser asking "is this
	# cell free?" against the whole list would find every cell taken; everything
	# after this line is something a piece of furniture must genuinely stand clear
	# of. (Same reason the ground floor's non-solid carpet is in that first group.)
	var floor_boxes := _plan_slab(plan)
	out.append_array(floor_boxes)
	out.append_array(_merge_walls(plan))
	var ramp := _plan_ramp(plan)
	if not ramp.is_empty():
		out.append(ramp)
	out.append_array(_plan_pads(plan))
	out.append_array(TowerInterior._plan_gates(plan))
	# ...and the hand-built parts, each guarded by a ROOM OR GATE LOOKUP and never by
	# a floor number. That is the rule the cell block has followed since phase 16 and
	# the reason it could change storeys without a number following it; bead
	# `godot-test1-dn8` brought the phase-3 keep's three set pieces under it when the
	# ground floor and the mezzanine became plan rows like every other. Move the `D`
	# run or the room's letters in the ASCII and the mechanism follows.
	if TowerInterior.plan_gate_rect(floor_index, TowerInterior.GATE_DEMAND).size != Vector2i.ZERO:
		out.append_array(TowerInterior._demand_boxes(plan))
	if TowerInterior.plan_room_rect(floor_index, TowerInterior.CHECKPOINT_ROOM).size != Vector2i.ZERO:
		out.append_array(TowerInterior._checkpoint_boxes(plan))
	if TowerInterior.plan_room_rect(floor_index, TowerInterior.BLOCK_ROOM).size != Vector2i.ZERO:
		out.append_array(TowerInterior._block_boxes(plan))
	# THE DRESSING GOES LAST, AND THAT ORDER IS THE WHOLE OF ITS SAFETY. Every
	# candidate cell is tested against everything above — the walls, the ramp, the
	# pads, the lock plates, the gate masses and each hand-built set piece — so a
	# desk can never land in a mechanism, and a set piece added tomorrow keeps it
	# out on the day it is drawn without a name being written down anywhere.
	out.append_array(TowerDossiers.alcove_boxes(plan))
	out.append_array(TowerInterior._egg_boxes(plan))
	# ...and the dossiers RESERVE their cells without drawing anything here. The
	# folders themselves are one `MultiMesh` (see `TowerDossiers.build`), so they are in
	# no box list at all — but the dresser decides where a desk goes by asking what
	# else this storey drew, and a desk on top of a pickup is the bug that costs
	# nothing to prevent and cannot be seen in a screenshot. Same seam every
	# hand-built set piece uses, one footprint per dossier and no geometry.
	var reserved := out.slice(floor_boxes.size())
	reserved.append_array(TowerDossiers.marks(floor_index))
	out.append_array(TowerDressing.plan_dressing(plan, reserved))
	_plan_cache[floor_index] = out
	return out


static func all_boxes() -> Array[Dictionary]:
	"""
	The WHOLE building's static plan: every planned storey, in plan order.

	@return: `plan_boxes()` for each `TowerPlans.floors()` index, concatenated.

	IT IS THE PLAN LOOP AND NOTHING ELSE SINCE BEAD `godot-test1-dn8`. There used to
	be a hand-authored `boxes()` table in front of it holding the phase-3 keep — 27
	boxes of walls, jambs, ceiling panels, a carpet, a slab and a ramp, all placed
	against the inner faces of a 20 m building standing in the middle of an 80 m
	hall. The keep is demolished; floors 0 and 1 are `TowerPlans` rows like every
	other storey, and there is no floor of this building that is not drawn as text.

	This is what `_ready()` builds from and what the self-checks measure.
	"""
	var out: Array[Dictionary] = []
	for floor_index: int in TowerPlans.floors():
		out.append_array(plan_boxes(floor_index))
	return out


static func _grid_x(edge: float) -> float:
	"""Column EDGE coordinate (0 is the west face of column 0) -> interior x."""
	return -TowerPlans.PLAN_HALF + edge * TowerPlans.PLAN_CELL


static func _grid_z(edge: float) -> float:
	"""Row EDGE coordinate (0 is the north face of row 0) -> interior z."""
	return -TowerPlans.PLAN_HALF + edge * TowerPlans.PLAN_CELL


static func _plan_stair(plan: Dictionary) -> Dictionary:
	"""
	Where the `S` lane and its `s` landing are, in cells.

	@return: `{c0, c1, r0, r1, rises_east}`, or `{}` when the storey has no `S`
	        cells at all.

	The lane is one solid rectangle with its long axis on X (`tower_selfcheck`'s
	flood-fill is what asserts that; here it is simply the bounding box of the `S`
	cells). WHICH WAY THE RAMP RISES IS DERIVED and never authored: the landing sits
	against one short end, so the end it is on IS the head. That is the whole reason
	`s` is a character rather than a `rise: "east"` key nobody would keep in step
	with the drawing.
	"""
	var rows: Array = plan["rows"]
	var c0 := TowerPlans.PLAN_GRID
	var c1 := -1
	var r0 := TowerPlans.PLAN_GRID
	var r1 := -1
	var landing_c_sum := 0.0
	var landing_n := 0
	for r: int in rows.size():
		var line: String = rows[r]
		for c: int in line.length():
			var ch := line[c]
			if ch == TowerPlans.STAIR_UP_CHAR:
				c0 = mini(c0, c)
				c1 = maxi(c1, c)
				r0 = mini(r0, r)
				r1 = maxi(r1, r)
			elif ch == TowerPlans.LANDING_CHAR:
				landing_c_sum += float(c)
				landing_n += 1
	if c1 < 0 or landing_n == 0:
		return {}
	return {
		"c0": c0, "c1": c1, "r0": r0, "r1": r1,
		"rises_east": landing_c_sum / float(landing_n) > float(c1),
	}


static func _plan_ramp(plan: Dictionary) -> Dictionary:
	"""
	The up-ramp arriving on this storey, as one rotated deck.

	@return: A `boxes()` entry carrying `rot`, or `{}` when the storey has no `S`.

	Its `floor` is the LOWER of the two storeys it joins, which is the existing
	convention and not a new one: a box you stand on belongs to the floor it
	carries, which is why the phase-3 ramp is floor 0 and not floor 1.
	"""
	var stair := _plan_stair(plan)
	if stair.is_empty():
		return {}
	var floor_index := int(plan["floor"])
	var from_index := int(plan["from"])
	var y_foot: float = FLOOR_Y[from_index]
	var y_head: float = FLOOR_Y[floor_index]
	# The lane's two short ends, as metres. The deck's foot is at the FAR edge of
	# the far `S` cell and its head at the near edge of the `s` cell — i.e. the
	# lane's full length, so the deck meets both floors flush with no lip.
	var x_west := _grid_x(float(stair["c0"]))
	var x_east := _grid_x(float(int(stair["c1"]) + 1))
	var foot := Vector2(x_west, y_foot)
	var head := Vector2(x_east, y_head)
	if not bool(stair["rises_east"]):
		foot = Vector2(x_east, y_foot)
		head = Vector2(x_west, y_head)
	var z := _grid_z((float(int(stair["r0"]) + int(stair["r1"])) + 1.0) * 0.5)
	var width := float(int(stair["r1"]) - int(stair["r0"]) + 1) * TowerPlans.PLAN_CELL
	return TowerInterior._deck_box("%sRamp" % TowerInterior._plan_prefix(floor_index), foot, head, z, width,
			mini(floor_index, from_index))


static func _plan_hole(plan: Dictionary) -> Dictionary:
	"""
	The stairwell hole in this storey's slab, in cells.

	@return: `{c0, c1, r0, r1}`, or `{}` when the storey has no ramp to clear.

	DERIVED, NEVER AUTHORED, and that is what makes "adjacent storeys' stair cells
	coincide" true by construction rather than by review. The hole starts at the
	point on the deck where this storey's slab would be `SLAB_THICK +
	PLAN_HEADROOM` overhead and runs to the head; anything shorter and a player
	walking up meets the floor they are about to stand on with their face. It is
	rounded OUTWARD to whole cells, because a slab edge halfway through a cell is a
	lip in a grid where every other edge is on a cell line.

	# ponytail: one axis-aligned rectangle. A ramp that turned a corner would need a
	# second rect and a slab that is up to 8 boxes rather than 4; X-axis-only ramps
	# (see `_deck_box`) are exactly what buys the simple version.
	"""
	var stair := _plan_stair(plan)
	if stair.is_empty():
		return {}
	var floor_index := int(plan["floor"])
	var from_index := int(plan["from"])
	var y_foot: float = FLOOR_Y[from_index]
	var y_head: float = FLOOR_Y[floor_index]
	var rise := y_head - y_foot
	# How far along the deck the ceiling stops being high enough, as a fraction.
	var span := SLAB_THICK + PLAN_HEADROOM
	var along := 1.0 if rise <= 0.0 else clampf((rise - span) / rise, 0.0, 1.0)
	var c0 := int(stair["c0"])
	var c1 := int(stair["c1"])
	var cells := float(c1 - c0 + 1)
	if bool(stair["rises_east"]):
		# Rounded outward: the cell CONTAINING the threshold is part of the hole.
		var first := c0 + int(floorf(along * cells))
		return {"c0": mini(first, c1), "c1": c1, "r0": stair["r0"], "r1": stair["r1"]}
	var last := c1 - int(floorf(along * cells))
	return {"c0": c0, "c1": maxi(last, c0), "r0": stair["r0"], "r1": stair["r1"]}


static func _plan_slab(plan: Dictionary) -> Array[Dictionary]:
	"""
	The storey's floor: the whole inner footprint MINUS the stairwell hole.

	@return: At most four boxes — the bands north and south of the hole, then the
	        strips east and west of it. Any that comes out zero-wide is skipped.

	Four boxes for 6000 m2 of floor, and the alternative is 1600 cell-sized ones.
	The slab hangs BELOW the walking surface (`SLAB_THICK` under `FLOOR_Y`), the
	same construction as the keep's, so `FLOOR_Y` is the number you stand on and
	not the number you have to subtract from.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var last := TowerPlans.PLAN_GRID - 1
	var hole := _plan_hole(plan)
	var bands: Array[Array] = []
	if hole.is_empty():
		bands.append([0, last, 0, last])
	else:
		var hc0 := int(hole["c0"])
		var hc1 := int(hole["c1"])
		var hr0 := int(hole["r0"])
		var hr1 := int(hole["r1"])
		if hr0 > 0:
			bands.append([0, last, 0, hr0 - 1])
		if hr1 < last:
			bands.append([0, last, hr1 + 1, last])
		if hc0 > 0:
			bands.append([0, hc0 - 1, hr0, hr1])
		if hc1 < last:
			bands.append([hc1 + 1, last, hr0, hr1])
	for i: int in bands.size():
		var band: Array = bands[i]
		var x0 := _grid_x(float(band[0]))
		var x1 := _grid_x(float(int(band[1]) + 1))
		var z0 := _grid_z(float(band[2]))
		var z1 := _grid_z(float(int(band[3]) + 1))
		out.append({
			"name": "%sSlab%d" % [TowerInterior._plan_prefix(floor_index), i],
			"pos": Vector3((x0 + x1) * 0.5, top - SLAB_THICK * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, SLAB_THICK, z1 - z0),
			"color": TowerInterior.COLOR_STONE, "collide": true, "floor": floor_index,
			# The face you walk on is carpet; the underside is the ceiling of the
			# storey below and stays off-white with the walls. One box, two colours —
			# see `_emit_box`.
			"top_color": TowerInterior.COLOR_CARPET,
		})
	# THE GROUND STOREY IS THE ONE WHOSE FLOOR YOU NEVER SEE. Its slab's top face is
	# at y = 0 — under the shell's `Yard`, a non-solid packed-earth apron lifted
	# `YARD_LIFT` (3 cm) over the whole footprint — so the mint above renders as
	# packed earth and the roofed ground floor stops matching every storey over it.
	# (codex review, 2026-08-30.)
	#
	# The slab itself may NOT be lifted to clear the apron: it is `collide: true`,
	# and 3 cm of collision is a lip at the foot of the ramp climbing out of here —
	# `CharacterBody3D` has no step-up, so anything you can trip on is a wall. So the
	# colour goes on separately, as the `HallCarpet` this bead deleted always did it:
	# one NON-SOLID 2 cm layer over the apron. You stand on the slab; this is pile.
	#
	# IT STOPS SHORT OF THE DOORWAY, by the shell's own `DOOR_TRIGGER_DEPTH`: the door
	# volume is a hole and nothing the interior builds may stand in it (check 1 asks
	# that of every box, and a carpet is a box). The threshold strip that leaves is the
	# doormat line — the slab underneath still runs to the wall.
	if top <= TowerShell.YARD_LIFT:
		var carpet_x1 := TowerPlans.PLAN_HALF - TowerShell.DOOR_TRIGGER_DEPTH
		out.append({
			"name": "%sCarpet" % TowerInterior._plan_prefix(floor_index),
			"pos": Vector3((carpet_x1 - TowerPlans.PLAN_HALF) * 0.5,
					TowerShell.YARD_LIFT + TowerInterior.CARPET_THICK * 0.5, 0.0),
			"size": Vector3(carpet_x1 + TowerPlans.PLAN_HALF, TowerInterior.CARPET_THICK,
					2.0 * TowerPlans.PLAN_HALF),
			"color": TowerInterior.COLOR_CARPET, "collide": false, "floor": floor_index,
		})
	return out


static func _merge_walls(plan: Dictionary) -> Array[Dictionary]:
	"""
	Every `#` cell on this storey, run-length merged in TWO dimensions.

	@return: One box per maximal rectangle of wall, floor slab to ceiling.

	THIS FUNCTION IS THE WHOLE REASON A 40 x 40 GRID IS AFFORDABLE. A corridor wall
	across a floor is 40 cells; emitted one box per cell that is 40 boxes, 40
	collision shapes and a budget nobody can hold — and the collision body is the
	one part of this building that is not batched, so those 40 shapes are real cost
	on every physics tick.

	Rows alone are not enough, and that is the second pass: horizontal run-length
	leaves a VERTICAL 40-cell wall as 40 one-wide runs, i.e. exactly the case it was
	supposed to fix. Merging adjacent rows whose runs have IDENTICAL extents makes a
	vertical wall one box for the same reason a horizontal one is. Runs that merely
	overlap are deliberately not merged: that is a rectangle-cover problem, and the
	greedy answer to it is worse than the boxes it saves.

	Walls run from the slab's top face to the storey's ceiling, so a wall top is
	never a ledge — which is what lets `tower_interior_selfcheck`'s check 2 assert
	the no-jump-gated-climb rule structurally instead of sweeping the whole floor.
	"""
	var floor_index := int(plan["floor"])
	var bottom: float = FLOOR_Y[floor_index]
	# ...as tall as THIS storey's clear height, not as tall as a storey: the floor
	# under the sealed roof has no slab over it (see `plan_clear_height`).
	var height := plan_clear_height(floor_index)
	var rows: Array = plan["rows"]
	# Pass 1 and 2 at once: each row's maximal runs, extending the run directly
	# above when its extent is identical.
	var rects: Array[Dictionary] = []
	var above: Dictionary = {}
	for r: int in rows.size():
		var line: String = rows[r]
		var here: Dictionary = {}
		var c := 0
		while c < line.length():
			if line[c] != TowerPlans.WALL_CHAR:
				c += 1
				continue
			var start := c
			while c < line.length() and line[c] == TowerPlans.WALL_CHAR:
				c += 1
			var key := "%d,%d" % [start, c - 1]
			if above.has(key):
				var grown: Dictionary = rects[above[key]]
				grown["r1"] = r
				here[key] = above[key]
			else:
				rects.append({"c0": start, "c1": c - 1, "r0": r, "r1": r})
				here[key] = rects.size() - 1
		above = here
	var out: Array[Dictionary] = []
	for i: int in rects.size():
		var rect: Dictionary = rects[i]
		var x0 := _grid_x(float(rect["c0"]))
		var x1 := _grid_x(float(int(rect["c1"]) + 1))
		var z0 := _grid_z(float(rect["r0"]))
		var z1 := _grid_z(float(int(rect["r1"]) + 1))
		out.append({
			"name": "%sWall%d" % [TowerInterior._plan_prefix(floor_index), i],
			"pos": Vector3((x0 + x1) * 0.5, bottom + height * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, height, z1 - z0),
			"color": TowerInterior.COLOR_STONE, "collide": true, "floor": floor_index,
			# ...and a pale-wood skirting, which `_emit_box` splits off the bottom of
			# this same prism. It is what gives a white corridor a horizontal line to
			# read its corners against.
			"wainscot": true,
		})
	return out


static func _plan_pads(plan: Dictionary) -> Array[Dictionary]:
	"""
	One plate per `P` cell, in the operable-system cyan.

	@return: A `COLOR_SYSTEM` plate per pad, non-solid (you stand ON the slab).

	THE PLATE IS THE PAINT AND `_build_lure_pads()` IS THE LOCK, exactly as the
	riddle pads are drawn here and triggered there: what makes a plate a lure is an
	`Area3D` standing on it, and only what MOVES ever leaves the storey's batch.
	Both read the same `pad_cells()` scan, so the volume you step into and the
	square you see it painted on cannot drift apart.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	for cell: Vector2i in pad_cells(plan):
		out.append({
			"name": "%sPad%d_%d" % [TowerInterior._plan_prefix(floor_index), cell.x, cell.y],
			"pos": Vector3(_grid_x(float(cell.x) + 0.5), top + PLAN_PAD_THICK * 0.5,
					_grid_z(float(cell.y) + 0.5)),
			"size": Vector3(TowerPlans.PLAN_CELL, PLAN_PAD_THICK,
					TowerPlans.PLAN_CELL),
			"color": TowerInterior.COLOR_SYSTEM, "collide": false, "floor": floor_index,
		})
	return out


static func pad_cells(plan: Dictionary) -> Array[Vector2i]:
	"""
	One storey's `P` cells, row-major.

	@param plan: A `TowerPlans.STOREYS` row.
	@return: the pad cells in reading order — and that ORDER IS AN INDEX every
	    peer in a room agrees on, because `TowerPlans` is a const and nothing about
	    a storey is seeded. It is what the `pad` verb carries instead of a
	    position, so a modified client cannot name a plate that is not on a plan.
	"""
	var out: Array[Vector2i] = []
	var rows: Array = plan["rows"]
	for r: int in rows.size():
		var line: String = rows[r]
		for c: int in line.length():
			if line[c] == TowerPlans.PAD_CHAR:
				out.append(Vector2i(c, r))
	return out


static func pad_point(floor_index: int, pad_index: int) -> Vector3:
	"""
	Where pad `pad_index` of storey `floor_index` is, in interior-local metres.

	@return: the plate's centre at the storey's walking surface, or
	    `Vector3.INF` when that storey draws no such pad — a refusal a caller can
	    test, rather than the origin, which is a real place inside this building.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return Vector3.INF
	var cells := pad_cells(plan)
	if pad_index < 0 or pad_index >= cells.size():
		return Vector3.INF
	var cell: Vector2i = cells[pad_index]
	return Vector3(_grid_x(float(cell.x) + 0.5), FLOOR_Y[floor_index],
			_grid_z(float(cell.y) + 0.5))


static func _plan_cell_of(local: Vector3) -> Vector2i:
	"""Interior-local metres -> the plan cell they stand in. `_grid_x` inverted."""
	return Vector2i(
			int(floor((local.x + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL)),
			int(floor((local.z + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL)))


static func _route_open(ch: String) -> bool:
	"""
	May a walking body cross this plan cell on its way somewhere?

	STONE AND THE RAMP ARE OUT for opposite reasons — one is a wall, the other is a
	DECK that descends a whole storey along its lane, so a body crossing it
	sideways is walking off a cliff (the `s` landing at its head is flush, and is
	in). A `D` IS OUT TOO, and that is the interesting one: every doorway on this
	grid is a gate slot, the mass in it may be down, and a router that took the
	short way through a shut door would send a guard to stand against it until its
	patience ran out. Every storey's ungated circuit is what makes routing round
	them possible — the labyrinth's route A is that rule written on a floor plan.
	"""
	return ch != TowerPlans.WALL_CHAR and ch != TowerPlans.STAIR_UP_CHAR \
			and ch != TowerPlans.GATE_CHAR


static func plan_route(floor_index: int, from_local: Vector3,
		to_local: Vector3) -> PackedVector3Array:
	"""
	A walkable way across one storey, as corner waypoints in interior-local metres.

	@return: the corners to walk, ending at the destination cell's centre, or an
	    EMPTY array when the plan offers no way — which the lure reads as "that
	    plate cannot call this guard" and refuses.

	A BREADTH-FIRST WALK OF THE FLOOR PLAN, four-connected, on a 40 x 40 grid of
	characters that is a `const` — so this is a few hundred microseconds on a press
	and there is nothing to cache, invalidate or keep in step. The alternative was
	the obstacle feelers alone, which have a 1.8 m reach and no memory: measured
	against the shipped plans, exactly ONE of the seventeen (post, plate) pairs in
	this building has a clear straight line, so a lure that steered by bearing was a
	lure that walked fifteen guards into a wall.

	THE CORNERS ARE THE OUTPUT, not the cells. A body that steered at every cell
	centre would stutter down a straight corridor; keeping only the cells where the
	direction changes leaves the follower one heading per leg, which is exactly what
	`_investigate_move()` wants and what the wander already does.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return PackedVector3Array()
	var rows: Array = plan["rows"]
	var height: int = rows.size()
	var width: int = String(rows[0]).length()
	var start := _plan_cell_of(from_local)
	var goal := _plan_cell_of(to_local)
	if start.x < 0 or start.y < 0 or start.x >= width or start.y >= height \
			or goal.x < 0 or goal.y < 0 or goal.x >= width or goal.y >= height:
		return PackedVector3Array()
	if start == goal:
		return PackedVector3Array([to_local])
	var came: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	var found := false
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == goal:
			found = true
			break
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0),
				Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cur + step
			if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
				continue
			if came.has(next):
				continue
			if not _route_open(String(rows[next.y])[next.x]):
				continue
			came[next] = cur
			queue.append(next)
	if not found:
		return PackedVector3Array()
	var cells: Array[Vector2i] = []
	var walk := goal
	while walk != start:
		cells.push_front(walk)
		walk = came[walk]
	cells.push_front(start)
	# ---- EVERY CELL CENTRE, and that is a measurement rather than laziness. The
	# first cut emitted corners only, which is what a follower with no drift would
	# want; the shipped follower has the obstacle feelers, and nineteen cells of
	# corridor is enough of them to nudge a body a whole cell off the lane — so it
	# arrived at the cell block's doorway at an angle and wedged on the jamb. A
	# waypoint per cell is the lane, so the walk stays in the middle of it.
	var out := PackedVector3Array()
	var top: float = FLOOR_Y[floor_index]
	for i in range(1, cells.size() - 1):
		out.append(Vector3(_grid_x(float(cells[i].x) + 0.5), top,
				_grid_z(float(cells[i].y) + 0.5)))
	out.append(to_local)
	return out
