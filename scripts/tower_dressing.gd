class_name TowerDressing
extends RefCounted
## THE HQ'S FURNITURE — the office, corridor and wayfinding dressers, lifted whole
## out of `tower_interior.gd` (bd godot-test1-ftn.12).
##
## THE SPLIT, and why it falls exactly here. `TowerInterior` keeps the BUILDING:
## the plan walker, the slab, the merged walls, the ramp, the pads, the gates, the
## set pieces, the captivity and Air Sight. This file keeps what STANDS IN IT, and
## the seam is one call — `plan_boxes()` hands the storey and everything it has
## already drawn to `plan_dressing()` and appends what comes back. Nothing else in
## the project calls in here except `tower_interior_selfcheck`'s check 18, which
## reads these constants directly rather than through a forwarder.
##
## IT IS A MOVE AND NOTHING ELSE. Every rule, every measured number and every
## comment below arrived unchanged from `tower_interior.gd`, and the acceptance was
## that the storey box counts, the dressing counts and `PLAN_DRESS_BUDGET` do not
## move by one. Read the `DRESS_PIECES` banner first: it says why the furniture is
## DERIVED from the plan rather than drawn in it, and what the three safety rules
## are that make a derived desk unable to softlock a floor.
##
## WHY STATIC FUNCTIONS AND NO STATE. `plan_boxes()` is static and cached, so there
## is no interior instance to hand over and nothing here to hold: a dresser is a
## pure function of (plan, what the storey already drew). It reaches back into
## `TowerInterior` for the plan-grid readers and the palette it shares with the
## walls — `_grid_x` / `_grid_z` / `_plan_char` / `_room_cells` / `_plan_prefix` /
## `_plan_hole` / `_plan_stair` / `FLOOR_Y` / `COLOR_WAINSCOT` — which is one
## direction only, and the direction `landmark_builders.gd` already established.


# ============================================================================
# OFFICE DRESSING (bead godot-test1-0a5) — furniture and wall art, DERIVED
# ============================================================================
#
# The storeys were correct plans in the right paint with nothing in them. This is
# the furniture, and the whole of it is DERIVED FROM THE PLAN rather than drawn
# in it.
#
# WHY NOT NEW GLYPHS. The obvious reading of "furniture from the plan" is a `d`
# for desk and a `c` for chair in `TowerPlans`, and it was rejected for two
# reasons, both of them about the extension rule that file's header is built on.
# First it is ten storeys x 1600 cells of hand-editing for a change nobody could
# review. Second, and worse, it makes furniture A THING A NEW STOREY MUST
# REMEMBER: every floor authored after today would arrive empty until somebody
# sprinkled glyphs through it. Derived, a storey drawn tomorrow is furnished the
# moment its ASCII lands — and the plan alphabet is untouched, so
# `tower_selfcheck`'s flood fill and its fifteen-subset audit are the same audits
# over the same grid, with no new character to teach them.
#
# WHAT MAKES IT SAFE. A solid desk across a doorway is a softlock, and the flood
# fill that would have caught it reads the ASCII, which knows nothing about any of
# this. So the safety is built in rather than audited in afterwards:
#
#   * dressing only ever lands on a cell that TOUCHES A WALL and is neither a
#     THRESHOLD (a room cell with a walkable non-room neighbour — i.e. a doorway)
#     nor 4-adjacent to one. The way in, and the middle of the room, are never
#     candidates at all;
#   * a piece with a SOLID part is committed only if the room's remaining free
#     cells are still ONE connected component afterwards. A piece that would wall
#     anything off is dropped on the spot, not warned about;
#   * a candidate cell that already carries anything else this storey draws — a
#     pad, a lock plate, a clue strip, a containment frame, the crawl's press
#     — is refused BY FOOTPRINT, so no set piece is ever dressed and the stealth
#     pacing is untouched. That test is geometry, not a list of names, so a set
#     piece added later is excluded the day it is drawn.
#
# `tower_interior_selfcheck`'s check 18 asserts all three from the outside, plus
# the floor on how much a real office room gets.

## Waist height: the line between a piece you walk into and one you walk over.
## Every part that declares `solid` must clear it (check 18), so a room reads
## solid without the player ever snagging on a chair leg or a plant pot.
const DRESS_WAIST: float = 0.70

## How sparse the furniture is — one piece per this many candidate cells, then
## clamped. A 3 x 15 cell office lands on three or four pieces; an 80 m hall gets
## the cap and reads as a lobby rather than a warehouse of desks.
##
## HALVED, AND THE CAP NEARLY DOUBLED, BY bd `godot-test1-st9` — the owner played
## #147's fit-out and read the rooms as empty. 7 and a cap of 6 put one piece per
## 13 m of wall in a room that has 40 m of it. The floor (`DRESS_MIN_PIECES`) is
## deliberately UNMOVED: it is what check 18 asserts an office owes, and a cupboard
## that scrapes `DRESS_MIN_CANDIDATES` still only has room for two things.
##
## THE KIND ROTATION IS WHAT MAKES THE EXTRA PIECES READ AS AN OFFICE rather than a
## showroom: `_dress_room` walks `DRESS_PIECES` from a per-room start, so a room
## that gets ten pieces gets ten DIFFERENT ones. That is why this number could only
## go up once the table below was widened past six.
const DRESS_SPACING: int = 4
const DRESS_MIN_PIECES: int = 2
const DRESS_MAX_PIECES: int = 10

## Wall art, counted the same way off the cells the furniture did not take.
const DRESS_ART_SPACING: int = 7
const DRESS_MAX_ART: int = 5

## A room with fewer candidate cells than this is a cupboard and stays empty. It
## is also the line check 18 uses to decide which rooms owe `DRESS_MIN_PIECES`.
const DRESS_MIN_CANDIDATES: int = 6

## THE FIXED SEED, and it is fixed BECAUSE THE TOWER IS AUTHORED. `run_seed` is
## the one thing that may never reach this building (see `tower_plans.gd`'s
## header): a desk that moved between runs would make every screenshot of this
## floor a screenshot of a different floor, and the softlock audits would be
## certifying a layout nobody plays. This salt, the storey and the room's letter
## are the whole of the entropy, so the offices are laid out identically forever.
const DRESS_SALT: int = 0x0FF1CE

## The three rooms that ARE their set piece end to end, and so are never dressed.
## Named as graph rooms and never as floor numbers — the same rule `plan_boxes`
## follows when it decides which storey draws the block. Everything else is kept
## out cell by cell by the footprint test, which needs no name.
##
## THE MUSTER FLOOR IS THE THIRD (bead `godot-test1-3iy.24`) and it joined the list
## the day it stopped being anonymous `.` and became a lettered room. It is the
## block's approach — an empty plate you cross in sight of a sentry, which is the
## stealth beat the whole storey is — and it is also the largest room in the
## building, so the dresser would have put a couple of hundred desks on it.
const DRESS_SKIP_ROOMS: Array[String] = [
	TowerInterior.BLOCK_ROOM, TowerInterior.CHECKPOINT_ROOM, "s10_landing",
]

## THE OFFICE PALETTE. Every colour here clears `INTERIOR_MIN_LUMINANCE` on its
## DARKEST face (`_face_shade`'s 0.78 underside), because a genuinely black
## monitor would be the one dark region in a building whose entire look is that it
## has none. So the screen is a cold grey that reads as "off" in a bright room,
## which is what an unlit LCD looks like anyway.
const COLOR_STEEL := Color(0.62, 0.64, 0.66)    # filing cabinets, pots, coolers
const COLOR_SCREEN := Color(0.30, 0.36, 0.40)   # a monitor, off
const COLOR_PLANT := Color(0.24, 0.50, 0.30)    # the one living thing in here
const COLOR_PAPER := Color(0.97, 0.95, 0.88)    # a diploma's mount
const COLOR_SEAL := Color(0.86, 0.68, 0.24)     # its foil seal, and every plaque
const COLOR_PHOTO := Color(0.55, 0.60, 0.68)    # a photo's grey studio backdrop
const COLOR_TERRACOTTA := Color(0.72, 0.44, 0.30)  # jars, planters, a cork board
const COLOR_BLOOM := Color(0.90, 0.52, 0.58)    # the one flower on the one cactus
# ...and pale wood is `COLOR_WAINSCOT`, borrowed rather than restated: the desks,
# the shelves and every frame are the same timber as the skirting, which is what
# makes a room read as one fitted-out space instead of a props box.

## THE FURNITURE, in WALL-LOCAL metres. A piece stands in ONE cell against ONE
## wall, and its parts are measured in that wall's own frame:
##
##   size  (along the wall, up, out of the wall)
##   off   (centre offset along the wall, BOTTOM above the walking surface,
##          NEAR FACE out from the wall's face)
##
## which is how a human measures furniture against a wall, and is what lets one
## table serve all four wall directions — `_dress_boxes` maps the frame onto the
## cell's actual normal, so a desk against an east wall is the same three numbers.
##
## `solid` IS PER PART, not per piece, and that is the bead's rule stated where it
## can be checked: the desk collides, the monitor and the chair tucked under it do
## not. Nothing under `DRESS_WAIST` is ever solid.
##
## TEN KINDS SINCE bd `godot-test1-st9`, AND THE ORDER IS INTERLEAVED ON PURPOSE.
## `_dress_room` walks this table from a per-room start and takes the next kind for
## every piece, so the table's order IS what a wall of a busy room looks like:
## solid and light alternate down it, and a room that now gets ten pieces gets a
## desk, a cabinet, a cactus, a shelf, a bin, a table, a fern, a cooler, a coat
## stand and a plant rather than ten desks.
const DRESS_PIECES: Array[Dictionary] = [
	{
		# THE DESK CARRIES THE CLUTTER (bd godot-test1-st9): a papers stack, a mug
		# and a phone, three flat boxes on a surface that already exists. Clutter as
		# its OWN placement would have wanted a cell and a table to stand on; on the
		# desk it costs no candidate and is exactly what the owner asked for.
		"kind": "desk",
		"parts": [
			{"size": Vector3(1.50, 0.74, 0.75), "off": Vector3(0.0, 0.0, 0.12),
				"color": TowerInterior.COLOR_WAINSCOT, "solid": true},
			{"size": Vector3(0.52, 0.34, 0.06), "off": Vector3(0.0, 0.74, 0.42),
				"color": COLOR_SCREEN},
			{"size": Vector3(0.50, 0.42, 0.50), "off": Vector3(0.0, 0.0, 1.02),
				"color": COLOR_STEEL},
			{"size": Vector3(0.50, 0.46, 0.08), "off": Vector3(0.0, 0.42, 1.44),
				"color": COLOR_STEEL},
			{"size": Vector3(0.26, 0.07, 0.20), "off": Vector3(-0.52, 0.74, 0.20),
				"color": COLOR_PAPER},
			{"size": Vector3(0.10, 0.11, 0.10), "off": Vector3(-0.24, 0.74, 0.16),
				"color": COLOR_PAPER},
			{"size": Vector3(0.22, 0.06, 0.16), "off": Vector3(0.52, 0.74, 0.22),
				"color": COLOR_SCREEN},
		],
	},
	{
		"kind": "cabinet",
		"parts": [
			{"size": Vector3(0.90, 1.35, 0.55), "off": Vector3(0.0, 0.0, 0.06),
				"color": COLOR_STEEL, "solid": true},
		],
	},
	{
		# The cactus in its terracotta jar, one bloom on top. Never solid: it is
		# knee-high and the whole point of the waist rule is that you do not snag.
		"kind": "cactus",
		"parts": [
			{"size": Vector3(0.34, 0.30, 0.34), "off": Vector3(0.0, 0.0, 0.28),
				"color": COLOR_TERRACOTTA},
			{"size": Vector3(0.16, 0.62, 0.16), "off": Vector3(0.0, 0.30, 0.37),
				"color": COLOR_PLANT},
			{"size": Vector3(0.26, 0.10, 0.10), "off": Vector3(0.16, 0.62, 0.40),
				"color": COLOR_PLANT},
			{"size": Vector3(0.10, 0.10, 0.10), "off": Vector3(0.0, 0.92, 0.40),
				"color": COLOR_BLOOM},
		],
	},
	{
		"kind": "shelf",
		"parts": [
			{"size": Vector3(1.30, 1.85, 0.42), "off": Vector3(0.0, 0.0, 0.06),
				"color": TowerInterior.COLOR_WAINSCOT, "solid": true},
			{"size": Vector3(1.10, 0.30, 0.06), "off": Vector3(0.0, 1.10, 0.44),
				"color": COLOR_SEAL},
		],
	},
	{
		"kind": "bin",
		"parts": [
			{"size": Vector3(0.32, 0.52, 0.32), "off": Vector3(0.0, 0.0, 0.24),
				"color": COLOR_STEEL},
			{"size": Vector3(0.36, 0.05, 0.36), "off": Vector3(0.0, 0.52, 0.22),
				"color": COLOR_SCREEN},
		],
	},
	{
		"kind": "table",
		"parts": [
			{"size": Vector3(1.55, 0.72, 1.00), "off": Vector3(0.0, 0.0, 0.30),
				"color": TowerInterior.COLOR_WAINSCOT, "solid": true},
			{"size": Vector3(0.44, 0.44, 0.44), "off": Vector3(-0.40, 0.0, 1.36),
				"color": COLOR_STEEL},
			{"size": Vector3(0.44, 0.44, 0.44), "off": Vector3(0.40, 0.0, 1.36),
				"color": COLOR_STEEL},
		],
	},
	{
		# The tall floor plant — head height, and still not solid, because a fern
		# you cannot walk past in a corner is furniture pretending to be a wall.
		"kind": "fern",
		"parts": [
			{"size": Vector3(0.40, 0.42, 0.40), "off": Vector3(0.0, 0.0, 0.28),
				"color": COLOR_TERRACOTTA},
			{"size": Vector3(0.10, 0.62, 0.10), "off": Vector3(0.0, 0.42, 0.43),
				"color": COLOR_PLANT},
			{"size": Vector3(0.86, 0.54, 0.62), "off": Vector3(0.0, 1.04, 0.17),
				"color": COLOR_PLANT},
		],
	},
	{
		"kind": "cooler",
		"parts": [
			{"size": Vector3(0.42, 0.98, 0.42), "off": Vector3(0.0, 0.0, 0.20),
				"color": COLOR_STEEL, "solid": true},
			{"size": Vector3(0.34, 0.44, 0.34), "off": Vector3(0.0, 0.98, 0.24),
				"color": COLOR_PHOTO},
		],
	},
	{
		"kind": "coatstand",
		"parts": [
			{"size": Vector3(0.36, 0.06, 0.36), "off": Vector3(0.0, 0.0, 0.26),
				"color": COLOR_STEEL},
			{"size": Vector3(0.09, 1.60, 0.09), "off": Vector3(0.0, 0.06, 0.39),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.56, 0.07, 0.07), "off": Vector3(0.0, 1.59, 0.40),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.28, 0.60, 0.20), "off": Vector3(0.18, 0.94, 0.34),
				"color": COLOR_PHOTO},
		],
	},
	{
		"kind": "plant",
		"parts": [
			{"size": Vector3(0.44, 0.34, 0.44), "off": Vector3(0.0, 0.0, 0.30),
				"color": COLOR_STEEL},
			{"size": Vector3(0.74, 0.90, 0.74), "off": Vector3(0.0, 0.34, 0.15),
				"color": COLOR_PLANT},
		],
	},
]

## THE WALL ART, in the same wall-local frame and never solid — a diploma you can
## walk into is a shelf. Both hang clear of the `WAINSCOT_HEIGHT` band, so the
## skirting still draws its unbroken line round the room under them.
##
## A DIPLOMA IS THREE BOXES AND A PHOTO IS TWO, all vertex-coloured, which is what
## keeps this free: they go into the storey's existing batch surface, so the whole
## of the wall art on a floor costs ZERO extra draw calls and zero materials. The
## alternative on the table was a generated atlas texture and a third surface —
## one more draw per storey, a new asset and a new material — to say "framed
## rectangle with a seal on it" at four metres' viewing distance.
const DRESS_ART: Array[Dictionary] = [
	{
		"kind": "diploma",
		"parts": [
			{"size": Vector3(0.62, 0.46, 0.05), "off": Vector3(0.0, 1.52, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.48, 0.32, 0.03), "off": Vector3(0.0, 1.59, 0.05),
				"color": COLOR_PAPER},
			{"size": Vector3(0.10, 0.10, 0.02), "off": Vector3(-0.14, 1.62, 0.08),
				"color": COLOR_SEAL},
		],
	},
	{
		"kind": "clock",
		"parts": [
			{"size": Vector3(0.36, 0.36, 0.05), "off": Vector3(0.0, 1.50, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.28, 0.28, 0.03), "off": Vector3(0.0, 1.54, 0.05),
				"color": COLOR_PAPER},
			{"size": Vector3(0.03, 0.13, 0.02), "off": Vector3(0.0, 1.62, 0.07),
				"color": COLOR_SCREEN},
		],
	},
	{
		"kind": "photo",
		"parts": [
			{"size": Vector3(0.40, 0.50, 0.05), "off": Vector3(0.0, 1.46, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.30, 0.38, 0.03), "off": Vector3(0.0, 1.52, 0.05),
				"color": COLOR_PHOTO},
		],
	},
	{
		# The notice board — cork, three pinned sheets, and the only thing on these
		# walls that is wider than it is tall. Its top is 1.90 m, which keeps it
		# clear of the 1.98 m the wayfinding plaques hang at.
		"kind": "notice",
		"parts": [
			{"size": Vector3(1.02, 0.66, 0.05), "off": Vector3(0.0, 1.24, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.92, 0.56, 0.03), "off": Vector3(0.0, 1.29, 0.05),
				"color": COLOR_TERRACOTTA},
			{"size": Vector3(0.16, 0.20, 0.02), "off": Vector3(-0.28, 1.42, 0.07),
				"color": COLOR_PAPER},
			{"size": Vector3(0.14, 0.18, 0.02), "off": Vector3(0.06, 1.36, 0.07),
				"color": COLOR_PAPER},
			{"size": Vector3(0.12, 0.16, 0.02), "off": Vector3(0.30, 1.48, 0.07),
				"color": COLOR_SEAL},
		],
	},
]

# ============================================================================
# CORRIDOR DRESSING (bead godot-test1-st9) — benches and planters in the halls
# ============================================================================
#
# The rooms were furnished and the corridors between them were still bare stone,
# which is what the owner's "it doesn't read as an office building" was mostly
# about: you spend more of a storey in the halls than in any one room.
#
# IT IS THE SAME DRESSER, one function further down, and it takes NOTHING new:
# the same `_dress_boxes` wall-local frame, the same batch surface, the same
# `_cell_is_taken` footprint refusal and the same stairwell-hole rule.
#
# NOTHING HERE IS EVER SOLID, and that is the whole safety argument. A room's
# furniture gets a flood fill before it commits because a desk is a wall; a bench
# you walk through cannot disconnect anything, on any floor shape, ever — so the
# corridors need no fill of their own and `tower_selfcheck`'s check 9 is as true
# after this as before it. The pieces stay low for the same reason the room's
# plants do: nothing under `DRESS_WAIST` may collide.
#
# WHERE. A corridor cell qualifies only if EVERY 4-neighbour is stone or more
# corridor — so a cell beside a doorway, a pad, a `D` run, a stair lane or any
# other lettered thing is refused outright, which is the room dresser's traffic
# rule stated in the one form a corridor can state it — AND the cell opposite its
# wall is corridor too, i.e. the hall is at least two cells wide there. A
# one-cell-wide corridor is a passage, and you do not put a bench in a passage.
#
# "CORRIDOR" IS `.` AND `s` BOTH, and the second one is the whole ground floor
# (codex review, 2026-08-31). The entry hall — the largest single space in the
# building and the first thing anybody sees — is drawn as an 18 x 18 block of
# LANDING, not of FLOOR, so a rule written against `.` alone left it bare while
# every storey above it got benches. A landing is walkable open floor by every
# other measure in this file; the RAMP that lands on it is a drawn box and is
# refused by `_cell_is_taken` like any other mechanism, and a cell touching the
# `S` lane is refused by the neighbour rule above. Everywhere else the two
# characters differ by at most a couple of cells.
#
# NOT IN THE LABYRINTH AND NOT IN THE BLOCK, the same two exclusions the
# wayfinding plaques take and for the same reason: the maze is meant to read as
# bare cut stone, and the block is a set piece end to end.

## The walkable-open-floor alphabet — see above for why the landing is in it.
const HALL_CHARS: String = TowerPlans.FLOOR_CHAR + TowerPlans.LANDING_CHAR

## One piece per this many qualifying corridor cells, capped per storey. The office
## storeys' halls run to a few hundred qualifying cells and take the cap; the entry
## hall has 56 and takes four, which is a lobby with seating rather than a waiting
## room. 12 and 14 are what put something in view down a corridor without lining it.
const HALL_SPACING: int = 12
const HALL_MAX: int = 14

## Its own salt, so a change to the corridors cannot slide a single desk.
const HALL_SALT: int = 0x8A11

## The name the corridor pieces are filed under, standing where a room's letter
## does in `_dress_boxes`. Deliberately NOT a single character: `_dress_cells` in
## the selfcheck reads placements back by the prefix `Dress<letter>_`, and a
## multi-character token can never be mistaken for a room's.
const HALL_LETTER: String = "Hall"

## Benches and planters, in `DRESS_PIECES`' wall-local frame. Never solid.
const HALL_PIECES: Array[Dictionary] = [
	{
		"kind": "bench",
		"parts": [
			{"size": Vector3(1.40, 0.09, 0.46), "off": Vector3(0.0, 0.40, 0.10),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(1.40, 0.44, 0.08), "off": Vector3(0.0, 0.44, 0.04),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.10, 0.40, 0.42), "off": Vector3(-0.60, 0.0, 0.12),
				"color": COLOR_STEEL},
			{"size": Vector3(0.10, 0.40, 0.42), "off": Vector3(0.60, 0.0, 0.12),
				"color": COLOR_STEEL},
		],
	},
	{
		"kind": "planter",
		"parts": [
			{"size": Vector3(1.10, 0.42, 0.42), "off": Vector3(0.0, 0.0, 0.14),
				"color": COLOR_TERRACOTTA},
			{"size": Vector3(1.00, 0.50, 0.36), "off": Vector3(0.0, 0.42, 0.17),
				"color": COLOR_PLANT},
		],
	},
]

# ============================================================================
# WAYFINDING PLAQUES (bead godot-test1-kox) — the horizontal half of the hint
# ============================================================================
#
# The minimap tells you the JAIL IS ON STOREY 10 AND YOU ARE FOUR BELOW IT. That is
# the whole of the guidance it gives, on purpose: a live bearing arrow would rank
# the corridors at every junction for you and quietly solve the building (the design
# note on this bead, after a codex peer-chat). So the horizontal help is AUTHORED
# INSTEAD — GastroDefense's own corridor signage, one plaque per office room, hung by
# the way out and pointing along its wall toward this storey's STAIR LANE, which is
# the way up and therefore the way to the block.
#
# It is coarse and it is intermittent and both are the point: a sign tells you which
# end of the floor the stairs are at, it does not tell you which of the two doors in
# front of you to take.
#
# IT IS A `DRESS_ART` ENTRY IN EVERYTHING BUT NAME — it goes through `_dress_boxes`
# onto a cell the dresser already vetted, into the storey's existing batch surface,
# vertex-coloured and never solid. So it costs ZERO new draw calls and ZERO new
# materials, and every safety rule check 18 asserts about the furniture (no doorway,
# no gate run, no set-piece room, never walls a room off) covers it unchanged.
#
# NOT IN THE LABYRINTH AND NOT IN THE BLOCK. `TowerInterior.is_maze_floor()` keeps
# the signs off storeys 8 and 9 — the maze is meant to be crossed by its landmarks,
# and a corridor sign in there is the pathfinding the whole design note refused.

## Which way along the wall the arrow points, as an index into `SIGN_PIECES`.
enum { SIGN_RIGHT, SIGN_LEFT }

## THE PLAQUE, in `DRESS_PIECES`' wall-local frame (along the wall, up, out of the
## wall) and never solid — a sign you can walk into is a shelf.
##
## It hangs at 1.98 m, ABOVE the wall art's band and above the tallest piece of
## furniture (the 1.85 m shelf), which is both where real corridor signage lives and
## what keeps it from ever sharing a wall face with anything else the dresser hung.
##
## The two rows are ONE SIGN MIRRORED: same board, same plate, and the shaft and the
## head of the arrow with their along-wall offsets negated. Written out as data
## rather than mirrored in code for `DRESS_ART`'s reason — a table you can read is
## worth more here than four saved lines.
const SIGN_PIECES: Array[Dictionary] = [
	{
		"kind": "signR",
		"parts": [
			{"size": Vector3(0.86, 0.34, 0.04), "off": Vector3(0.0, 1.98, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.76, 0.26, 0.03), "off": Vector3(0.0, 2.02, 0.04),
				"color": COLOR_SEAL},
			{"size": Vector3(0.34, 0.05, 0.02), "off": Vector3(0.10, 2.13, 0.07),
				"color": COLOR_PAPER},
			{"size": Vector3(0.14, 0.13, 0.02), "off": Vector3(0.31, 2.09, 0.07),
				"color": COLOR_PAPER},
		],
	},
	{
		"kind": "signL",
		"parts": [
			{"size": Vector3(0.86, 0.34, 0.04), "off": Vector3(0.0, 1.98, 0.0),
				"color": TowerInterior.COLOR_WAINSCOT},
			{"size": Vector3(0.76, 0.26, 0.03), "off": Vector3(0.0, 2.02, 0.04),
				"color": COLOR_SEAL},
			{"size": Vector3(0.34, 0.05, 0.02), "off": Vector3(-0.10, 2.13, 0.07),
				"color": COLOR_PAPER},
			{"size": Vector3(0.14, 0.13, 0.02), "off": Vector3(-0.31, 2.09, 0.07),
				"color": COLOR_PAPER},
		],
	},
]

# ============================================================================
# THE DRESSER — an office in every room, derived (bead godot-test1-0a5)
# ============================================================================
#
# Read the block beside `DRESS_PIECES` first: it says why this is derived rather
# than drawn, and what the three safety rules are. Everything below is those rules
# and nothing else, and none of it names a floor, a room or a letter.

static func plan_dressing(plan: Dictionary, taken: Array[Dictionary]) -> Array[Dictionary]:
	"""
	Every room on one storey, furnished and hung.

	@param plan: A `TowerPlans.STOREYS` row.
	@param taken: Everything this storey has already drawn EXCEPT its floor slab —
	        the walls, the ramp, the pads, the gate masses and every hand-built set
	        piece. A candidate cell overlapping any of them is refused.
	@return: `boxes()` entries, each carrying `"dress": true` so check 1 can budget
	        the furniture apart from the structure it stands in.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var rows: Array = plan["rows"]
	# NOTHING SOLID MAY STAND UNDER THE STAIRWELL HOLE, and this is the one rule the
	# footprint test above cannot express: the hole is a thing the storey ABOVE cuts
	# out of its own slab, so it is absent from everything this storey draws.
	#
	# It is the no-jump-gated-climb rule, and check 2 found it rather than a
	# playtest: a 1.85 m bookshelf on storey 9 stood under storey 10's hole, and
	# 1.85 + a 3.61 m jump apex is 5.46 m of reach against a 5.00 m storey — an
	# unaided hop straight onto the labyrinth's upper half, past the ramp, past the
	# riddle and past the guard. Everywhere else the ceiling is a slab and the jump
	# ends against it, which is why the rest of the furniture is free to be
	# furniture-shaped. Keeping the hole clear also just reads right: it is where the
	# ramp comes down.
	var above := TowerPlans.storey(floor_index + 1)
	var hole := {} if above.is_empty() else TowerInterior._plan_hole(above)
	var letters: Array = plan["rooms"].keys()
	letters.sort()
	for letter: String in letters:
		if DRESS_SKIP_ROOMS.has(String(plan["rooms"][letter])):
			continue
		out.append_array(_dress_room(plan, rows, floor_index, letter, taken, hole))
	out.append_array(_hall_dressing(rows, floor_index, taken, hole))
	return out


static func _hall_dressing(rows: Array, floor_index: int,
		taken: Array[Dictionary], hole: Dictionary) -> Array[Dictionary]:
	"""
	One storey's corridors, dressed. See the `HALL_PIECES` banner for the rules —
	all of them are in the candidate loop below and none of them is new machinery.

	@param rows: The storey's ASCII.
	@param taken: As `plan_dressing` — everything but the floor slab.
	@param hole: The storey above's stairwell hole, or `{}`.
	@return: `boxes()` entries carrying `"dress": true`, or `[]`.
	"""
	if TowerInterior.is_maze_floor(floor_index) \
			or floor_index == TowerInterior.block_floor():
		return []
	var cands: Array[Vector2i] = []
	for r: int in rows.size():
		var line := String(rows[r])
		for c: int in line.length():
			if not HALL_CHARS.contains(line[c]):
				continue
			var cell := Vector2i(c, r)
			# EVERY NEIGHBOUR STONE OR CORRIDOR. A doorway, a pad, a gate run, a
			# stair lane and every room letter are all "something other than `#`
			# or `HALL_CHARS`", so this one test is the whole traffic rule — and a
			# set piece drawn tomorrow is excluded by it on the day it is drawn.
			var normal := Vector3.ZERO
			for step: Vector2i in _STEPS:
				var ch := TowerInterior._plan_char(rows, cell + step)
				if ch == TowerPlans.WALL_CHAR:
					if normal == Vector3.ZERO:
						normal = Vector3(-float(step.x), 0.0, -float(step.y))
				elif not HALL_CHARS.contains(ch):
					normal = Vector3.ZERO
					break
			if normal == Vector3.ZERO:
				continue
			# ...and the hall is two cells wide here, so the bench leaves a lane.
			if not HALL_CHARS.contains(
					TowerInterior._plan_char(rows, cell + Vector2i(int(normal.x), int(normal.z)))):
				continue
			if _cell_is_taken(cell, taken) or _under_hole(cell, hole):
				continue
			cands.append(cell)
	if cands.size() < HALL_SPACING:
		return []
	# Strided over row-major candidates, exactly as `_dress_room` does it and for
	# the same reason: a shuffle puts three benches in one corner of the lobby.
	var want := mini(cands.size() / HALL_SPACING, HALL_MAX)
	var stride := maxi(1, cands.size() / want)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(floor_index, HALL_SALT, DRESS_SALT))
	var offset := rng.randi_range(0, stride - 1)
	var kind := rng.randi_range(0, HALL_PIECES.size() - 1)
	var out: Array[Dictionary] = []
	for i: int in want:
		var index := offset + i * stride
		if index >= cands.size():
			break
		out.append_array(_dress_boxes(rows, floor_index, HALL_LETTER, cands[index],
				HALL_PIECES[(kind + i) % HALL_PIECES.size()]))
	return out


static func _dress_room(plan: Dictionary, rows: Array, floor_index: int,
		letter: String, taken: Array[Dictionary], hole: Dictionary) -> Array[Dictionary]:
	"""One room's furniture and wall art. See `plan_dressing` for the parameters."""
	var cells := TowerInterior._room_cells(rows, letter)
	if cells.is_empty():
		return []
	# The doorways, and the cells beside them: a room's whole traffic is through
	# these and nothing may stand in any of them. Computing it here rather than
	# trusting `plan_doorway_rect` is deliberate — that one answers "the gap in the
	# wall row on the +Z side", which is one doorway of one shape, and a room with
	# its door on the north or west side would come back empty and undefended.
	var room := {}
	for cell: Vector2i in cells:
		room[cell] = true
	var thresholds: Array[Vector2i] = []
	for cell: Vector2i in cells:
		for step: Vector2i in _STEPS:
			var ch := TowerInterior._plan_char(rows, cell + step)
			if ch != TowerPlans.WALL_CHAR and ch != letter:
				thresholds.append(cell)
				break
	if thresholds.is_empty():
		# A room with no way in is a drafting error, not a room to furnish. The
		# flood fill below has no start cell either, so there is nothing honest to
		# say about it here; `tower_selfcheck`'s check 9 is what refuses it.
		return []
	var barred := {}
	for cell: Vector2i in thresholds:
		barred[cell] = true
		for step: Vector2i in _STEPS:
			barred[cell + step] = true

	var cands: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if barred.has(cell):
			continue
		var touches_wall := false
		for step: Vector2i in _STEPS:
			if TowerInterior._plan_char(rows, cell + step) == TowerPlans.WALL_CHAR:
				touches_wall = true
				break
		if not touches_wall or _cell_is_taken(cell, taken) or _under_hole(cell, hole):
			continue
		cands.append(cell)
	if cands.size() < DRESS_MIN_CANDIDATES:
		return []

	# The one draw of entropy this building takes, and it is not a run's. Seeded
	# from the storey and the room's own letter, so two rooms on a floor are laid
	# out differently and the same room is laid out identically forever.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(floor_index, letter.unicode_at(0), DRESS_SALT))

	var out: Array[Dictionary] = []
	var blocked := {}
	var used := {}
	var want := clampi(cands.size() / DRESS_SPACING, DRESS_MIN_PIECES, DRESS_MAX_PIECES)
	want = mini(want, cands.size())
	# STRIDED AND NOT SHUFFLED. `cands` is in row-major order, so walking it with a
	# stride spreads the pieces round the room's walls; a shuffle bunches three
	# desks in one corner about as often as it does not.
	var stride := maxi(1, cands.size() / want)
	var offset := rng.randi_range(0, stride - 1)
	var kind := rng.randi_range(0, DRESS_PIECES.size() - 1)
	for i: int in want:
		var index := offset + i * stride
		if index >= cands.size():
			break
		var cell: Vector2i = cands[index]
		var piece: Dictionary = DRESS_PIECES[(kind + i) % DRESS_PIECES.size()]
		if _piece_is_solid(piece) and not _still_connected(room, blocked, cell):
			# It would have walled something off. Dropped, and the room is simply
			# emptier — never "placed anyway with a warning", because the warning
			# nobody reads is how a softlock ships.
			continue
		if _piece_is_solid(piece):
			blocked[cell] = true
		used[cell] = true
		out.append_array(_dress_boxes(rows, floor_index, letter, cell, piece))

	# ...then the art, on the walls the furniture left bare.
	var free: Array[Vector2i] = []
	for cell: Vector2i in cands:
		if not used.has(cell):
			free.append(cell)
	if not free.is_empty():
		var art_want := mini(maxi(1, free.size() / DRESS_ART_SPACING), DRESS_MAX_ART)
		var art_stride := maxi(1, free.size() / art_want)
		var art_offset := rng.randi_range(0, art_stride - 1)
		var art_kind := rng.randi_range(0, DRESS_ART.size() - 1)
		for i: int in art_want:
			var index := art_offset + i * art_stride
			if index >= free.size():
				break
			used[free[index]] = true
			out.append_array(_dress_boxes(rows, floor_index, letter, free[index],
					DRESS_ART[(art_kind + i) % DRESS_ART.size()]))

	# ...and last, ONE wayfinding plaque, on the bare wall nearest the way out.
	out.append_array(_sign_boxes(plan, rows, floor_index, letter, cands, used, thresholds))
	return out


static func _sign_boxes(plan: Dictionary, rows: Array, floor_index: int, letter: String,
		cands: Array[Vector2i], used: Dictionary, thresholds: Array[Vector2i]) -> Array[Dictionary]:
	"""
	One room's wayfinding plaque — see the `SIGN_PIECES` banner.

	@param cands: The cells the dresser vetted, in row-major order.
	@param used: Which of them already carry furniture or art.
	@param thresholds: The room's doorway cells.
	@return: `boxes()` entries, or `[]` when this storey or this room gets no sign.

	NEAREST THE DOORWAY IS "AT THE JUNCTION". A candidate is never a threshold and
	never 4-adjacent to one (that is the dresser's traffic rule), so the nearest one
	is two cells from the door — beside the way out, which is where a sign is read.
	Manhattan distance, ties going to the first in row-major order, so the placement
	is as fixed as everything else in this building.
	"""
	if TowerInterior.is_maze_floor(floor_index) \
			or floor_index == TowerInterior.block_floor():
		return []
	# The way up is what the sign points at. A storey with no `S` lane has nothing
	# honest to say, so it says nothing.
	var stair := TowerInterior._plan_stair(plan)
	if stair.is_empty():
		return []
	var best := Vector2i(-1, -1)
	var best_reach := 1 << 30
	for cell: Vector2i in cands:
		if used.has(cell):
			continue
		var reach := 1 << 30
		for door: Vector2i in thresholds:
			reach = mini(reach, absi(cell.x - door.x) + absi(cell.y - door.y))
		if reach < best_reach:
			best_reach = reach
			best = cell
	if best.x < 0:
		return []
	# WHICH WAY ALONG THE WALL. The sign is flat on a wall, so the only direction it
	# can express is its tangent; the arrow takes the sign of the stair lane's offset
	# along it. A stair dead ahead of the sign (zero offset along the wall) points
	# right — a coin flip nobody can see, because there is no wrong answer to show.
	var normal := _wall_normal(rows, best)
	var tangent := Vector3(absf(normal.z), 0.0, absf(normal.x))
	var here := Vector3(TowerInterior._grid_x(float(best.x) + 0.5), 0.0,
			TowerInterior._grid_z(float(best.y) + 0.5))
	var target := Vector3(
			TowerInterior._grid_x((float(int(stair["c0"]) + int(stair["c1"])) + 1.0) * 0.5),
			0.0,
			TowerInterior._grid_z((float(int(stair["r0"]) + int(stair["r1"])) + 1.0) * 0.5))
	var side := SIGN_RIGHT if (target - here).dot(tangent) >= 0.0 else SIGN_LEFT
	return _dress_boxes(rows, floor_index, letter, best, SIGN_PIECES[side])


## The four 4-neighbours, named once. Every rule in the dresser is a claim about
## 4-adjacency (a diagonal neighbour is not a way past a box), so they share one.
const _STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func _under_hole(cell: Vector2i, hole: Dictionary) -> bool:
	"""Is this cell under the storey above's stairwell hole? See `plan_dressing`."""
	if hole.is_empty():
		return false
	return cell.x >= int(hole["c0"]) and cell.x <= int(hole["c1"]) \
		and cell.y >= int(hole["r0"]) and cell.y <= int(hole["r1"])


static func _piece_is_solid(piece: Dictionary) -> bool:
	"""Does any part of this piece collide? Then its cell is a wall to the fill."""
	for part: Dictionary in piece["parts"]:
		if bool(part.get("solid", false)):
			return true
	return false


static func _still_connected(room: Dictionary, blocked: Dictionary,
		adding: Vector2i) -> bool:
	"""
	Would blocking one more cell split anything the player can walk on?

	@param room: Every cell of the room, as a set.
	@param blocked: The cells already made solid by furniture.
	@param adding: The cell about to be made solid.
	@return: True when nothing gets cut off.

	THE TEST IS LOCAL, AND THAT IS EXACTLY AS STRONG AS THE GLOBAL ONE. Taking one
	cell out of a graph can only separate cells that were reaching each other
	THROUGH it, and every such path ran between two of its own neighbours. So: if
	the free neighbours of the cell all still reach one another without it, no
	component was split — anywhere, for any room shape.

	THE ROOM SHAPE IS WHY IT IS LOCAL RATHER THAN "the room stays in one piece",
	which is what this said first and which was wrong on real geometry. A `rooms`
	letter is a NAME, not a region: the ground floor's `outer_hall` is four separate
	blocks of `O` joined only through the corridors between them, so its cells were
	never one component and the strong claim refused to place a single solid thing
	in the biggest room in the building. This asks the question that was actually
	meant — did the furniture change the connectivity — and it is the same question
	`tower_interior_selfcheck` check 18 asks from the outside, phrased there as the
	doorways rather than the cells because that is the property that softlocks.
	"""
	var here: Array[Vector2i] = []
	for step: Vector2i in _STEPS:
		var next: Vector2i = adding + step
		if room.has(next) and not blocked.has(next):
			here.append(next)
	if here.size() < 2:
		return true
	var seen := {here[0]: true}
	var queue: Array[Vector2i] = [here[0]]
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in _STEPS:
			var next: Vector2i = at + step
			if seen.has(next) or next == adding or blocked.has(next) or not room.has(next):
				continue
			seen[next] = true
			queue.append(next)
	for cell: Vector2i in here:
		if not seen.has(cell):
			return false
	return true


## How much of a cell's edge the footprint test gives away, and it is FLOAT NOISE
## and not clearance. A merged wall is stored as a centre and a size, so the edge it
## reports (`pos.x - size.x * 0.5`) reproduces the grid line it was built from only
## to rounding — and a wall that appears to reach 1e-16 m into the cell beside it
## rejects that cell, which is how half the offices in the building came out empty
## with no error anywhere. A centimetre is orders of magnitude over the noise and
## orders under anything a piece of furniture would want to know about.
const DRESS_EPS: float = 0.01


static func _cell_is_taken(cell: Vector2i, taken: Array[Dictionary]) -> bool:
	"""Does anything else this storey drew stand in this cell's footprint?"""
	var x0 := TowerInterior._grid_x(float(cell.x)) + DRESS_EPS
	var x1 := TowerInterior._grid_x(float(cell.x) + 1.0) - DRESS_EPS
	var z0 := TowerInterior._grid_z(float(cell.y)) + DRESS_EPS
	var z1 := TowerInterior._grid_z(float(cell.y) + 1.0) - DRESS_EPS
	for box: Dictionary in taken:
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		if pos.x - half.x < x1 and pos.x + half.x > x0 \
				and pos.z - half.z < z1 and pos.z + half.z > z0:
			return true
	return false


static func _wall_normal(rows: Array, cell: Vector2i) -> Vector3:
	"""
	Out of the wall this cell touches, into the room — `Vector3.ZERO` if it touches
	none. The first wall in `_STEPS` order wins, so a corner cell is dressed against
	one of its two walls and never against both.
	"""
	for step: Vector2i in _STEPS:
		if TowerInterior._plan_char(rows, cell + step) == TowerPlans.WALL_CHAR:
			return Vector3(-float(step.x), 0.0, -float(step.y))
	return Vector3.ZERO


static func _dress_boxes(rows: Array, floor_index: int, letter: String,
		cell: Vector2i, piece: Dictionary) -> Array[Dictionary]:
	"""
	One piece, in one cell, against the wall that cell touches.

	THE WALL-LOCAL FRAME IS RESOLVED HERE and nowhere else, which is what lets one
	table serve all four directions: `normal` points out of the wall into the room,
	`tangent` runs along it, and a part's authored (along, up, out) is mapped onto
	them. Both are axis-aligned unit vectors, so the size mapping is a swap and not
	a rotation — the boxes stay axis-aligned and the batch stays cheap.
	"""
	var out: Array[Dictionary] = []
	var normal := _wall_normal(rows, cell)
	if normal == Vector3.ZERO:
		return out
	var tangent := Vector3(absf(normal.z), 0.0, absf(normal.x))
	var centre := Vector3(TowerInterior._grid_x(float(cell.x) + 0.5), 0.0,
			TowerInterior._grid_z(float(cell.y) + 0.5))
	var face := centre - normal * (TowerPlans.PLAN_CELL * 0.5)
	var top: float = TowerInterior.FLOOR_Y[floor_index]
	for i: int in piece["parts"].size():
		var part: Dictionary = piece["parts"][i]
		var size: Vector3 = part["size"]
		var off: Vector3 = part["off"]
		var world := tangent * size.x + Vector3(0.0, size.y, 0.0) + normal.abs() * size.z
		var at := face + tangent * off.x + normal * (off.z + size.z * 0.5)
		at.y = top + off.y + size.y * 0.5
		out.append({
			"name": "%sDress%s_%d_%d_%s%d" % [TowerInterior._plan_prefix(floor_index), letter,
					cell.x, cell.y, piece["kind"], i],
			"pos": at, "size": world, "color": part["color"],
			"collide": bool(part.get("solid", false)), "floor": floor_index,
			"dress": true,
		})
	return out
