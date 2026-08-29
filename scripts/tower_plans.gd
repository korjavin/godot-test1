class_name TowerPlans
extends RefCounted
## THE TOWER'S STOREYS, DRAWN AS TEXT — the hand-planned layout of every floor
## above the phase-3 keep.
##
## Epic godot-test1-3iy, phase 14. This file is DATA, the way `tower_graph.gd` is
## data: a `const` dict of plain dicts, no class hierarchy, no `Resource`, no
## logic. It is read by exactly two things — `tower_interior.gd`, which turns a
## storey's `rows` into boxes, and `tower_selfcheck.gd`, which flood-fills the same
## grid and refuses a floor a player could not walk.
##
## ============================================================================
## WHY TEXT
## ============================================================================
##
## The owner's ruling on this building is "plan it once and forever" — the HQ is
## hand-authored, and NOTHING about it is generated, seeded or hashed. There is no
## run seed here, no random draw, no hashing, and there may never be one: a tower
## that moved between runs is a different building, and the softlock audit in
## `tower_selfcheck.gd` would be certifying a layout no player ever sees.
##
## Hand-authoring 10 storeys of 80 x 80 m needs a level editor. This repo has no
## level editor, so it has the one every repo has: text. A designer edits `rows`,
## one character per cell, and the builder and both audits follow. That is the
## whole idea, and the measure of whether it worked is the extension rule below.
##
## ============================================================================
## THE EXTENSION RULE — what a new storey costs
## ============================================================================
##
## TWO edits, and no third:
##
##   1. one `STOREYS` row here (the ASCII plus its `rooms` / `gates` maps);
##   2. its `TOWER_GRAPH` room and edge rows, so the graph audit knows the space
##      exists and how it is entered.
##
## **NO BUILDER EDIT, EVER.** `tower_interior.gd` walks whatever is in `STOREYS`;
## it knows about storeys, not about storey 3. If adding a floor ever requires a
## line in the builder, the format has failed and the format is what should change.
## This paragraph is where that promise lives; `tower_interior_selfcheck` and
## `tower_selfcheck` are what keep it honest.
##
## ============================================================================
## THE GRID
## ============================================================================
##
## `PLAN_GRID` x `PLAN_GRID` cells stretched across the shell's INNER faces.
##
##   * `rows[r][c]` — `r` runs -Z -> +Z (row 0 is the far north edge), `c` runs
##     -X -> +X (column 0 is the far west edge). Reading the array top to bottom is
##     reading the floor plan north to south, which is what makes it editable.
##   * the centre of cell `(c, r)` is
##         x = -PLAN_HALF + (c + 0.5) * PLAN_CELL
##         z = -PLAN_HALF + (r + 0.5) * PLAN_CELL
##
## `PLAN_CELL` is DERIVED and deliberately not authored. Forty cells have to span
## exactly the clear width between the shell's inner faces; round the cell to a
## nice 2.0 m and the plan's outer ring stops meeting the wall it is drawn against,
## and every storey grows a 0.8 m ledge nobody planned, on all four sides, forever.
## 1.94 m is what 40 cells of 77.6 m clear width actually are, and it reads well:
## a corridor is two cells (3.88 m) and a small office is 4 x 5 cells.
##
## ============================================================================
## THE CHARACTERS
## ============================================================================
##
##   #        wall. Full storey height, floor slab to ceiling — never a ledge, so
##            nothing on a storey is a step onto the next one. Emits one box after
##            the run-length merge, not one per cell.
##   .        floor with no room label: corridors, lobbies, landings-at-large.
##            Emits nothing; the storey's slab is already under it.
##   letter   a room's cells. The letter maps to a `TOWER_GRAPH` room id through
##            the storey's `rooms` dict, and the binding is checked BOTH ways.
##            `A`-`Z` EXCEPT `S`, `P`, `G` and `D`, which are taken below.
##   S        the up-ramp's lane, arriving on this storey from the floor named by
##            `from`. It IS the ramp: one solid rectangle, long axis on X, two
##            cells deep. Emits the ramp box and derives the stairwell hole.
##   s        the landing at the head of that ramp, and the flood-fill's start
##            cell. It sits against ONE short end of the `S` rectangle, and which
##            end it is on is how the builder knows which way the ramp rises.
##   P        a pad. Must be 4-adjacent to at least one room-letter cell. Emits one
##            0.1 m plate in `COLOR_SYSTEM`.
##   G        a guard post. Parsed and validated, spawns nothing — population is
##            phase 17's, and a post drawn here is the phase-17 author's map.
##   D        a gate slot. The cell key `"<c>,<r>"` must appear in the storey's
##            `gates` dict and name a real `TOWER_GRAPH` gate row. No storey
##            authored in this phase has one; phase 15 brings the riddles.
##
## ============================================================================
## A STOREY ROW
## ============================================================================
##
##   floor    int    index into `TowerInterior.FLOOR_Y` — the walking surface, and
##                   the `floor` every box this storey emits declares.
##   from     int    the floor index this storey's ramp climbs FROM.
##   landing  String the `TOWER_GRAPH` room id the `s` cells are.
##   rooms    Dict   room letter -> `TOWER_GRAPH` room id.
##   gates    Dict   "<c>,<r>" -> `TOWER_GRAPH` gate id, for every `D` cell.
##   rows     Array  exactly `PLAN_GRID` strings of exactly `PLAN_GRID` characters.
##   note     String what this floor IS. The notes are the design record.


## The plan grid: 40 x 40 cells across the shell's INNER faces.
const PLAN_GRID: int = 40

## Half the clear interior width — the shell's outer half less one wall.
const PLAN_HALF: float = TowerShell.OUTER_HALF - TowerShell.WALL_THICK   # 38.8

## One cell, in metres. Derived from the two above and never written down: see the
## header for what a rounded-off cell costs.
const PLAN_CELL: float = 2.0 * PLAN_HALF / float(PLAN_GRID)              # 1.94

# The character table, named once. The builder and both self-checks read these
# rather than restating the literals, so a character can be re-spelled here and
# nowhere else.
const WALL_CHAR: String = "#"
const FLOOR_CHAR: String = "."
const STAIR_UP_CHAR: String = "S"
const LANDING_CHAR: String = "s"
const PAD_CHAR: String = "P"
const POST_CHAR: String = "G"
const GATE_CHAR: String = "D"


const STOREYS: Array[Dictionary] = [
	# ------------------------------------------------------------------------
	# STOREY 3 (floor 2) — THE RECORDS FLOOR, and the first floor above the keep.
	#
	# The grand ramp climbs the ANNULUS from the courtyard floor: ten cells of X
	# (19.40 m) for an 11.0 m rise, slope 0.567 against the phase-3 ramp's proven
	# 0.575. Its lane runs along the north ring corridor at z about -35 m, which is
	# 25 m clear of the keep and nowhere near the door corridor that runs east from
	# the keep's doorway — both asserted, because getting either wrong walls the
	# player out of the building they just walked into.
	#
	# The floor is a two-cell RING CORRIDOR round the outside and a two-cell CROSS
	# down each axis, so every room has two ways back to the landing and no dead end
	# is longer than one room. Eight long stacks hang off it, two per quadrant, each
	# entered through a two-cell hole in the wall it shares with the cross corridor.
	# ------------------------------------------------------------------------
	{
		"floor": 2,
		"from": 0,
		"landing": "s3_landing",
		"rooms": {
			"A": "s3_records_west",
			"B": "s3_records_east",
			"C": "s3_permits_west",
			"E": "s3_permits_east",
			"F": "s3_archive_west",
			"H": "s3_archive_east",
			"I": "s3_evidence_west",
			"J": "s3_evidence_east",
		},
		"gates": {},
		"rows": [
			"########################################",
			"#....SSSSSSSSSSs.......................#",
			"#....SSSSSSSSSSs.......................#",
			"#..################..################..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAPAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..#AAAAAA##BBBBBB#..#CCCCCC##EEEEEE#..#",
			"#..###AA######BB###..###CC######EE###..#",
			"#......................................#",
			"#......................................#",
			"#..###FF######HH###..###II######JJ###..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJPJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..#FFFFFF##HHHHHH#..#IIIIII##JJJJJJ#..#",
			"#..################..################..#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 3, the records floor: the grand ramp off the annulus, a "
			+ "ring and cross corridor, and eight long record stacks two to a "
			+ "quadrant.",
	},
	# ------------------------------------------------------------------------
	# STOREY 4 (floor 3) — THE ACCOUNTS FLOOR. Same skeleton, finer grain: twelve
	# small offices, three to a quadrant, which is what an admin floor of an 80 m
	# building looks like and what stresses `_merge_walls` hardest (every partition
	# is a separate run).
	#
	# Its ramp rises off storey 3's north ring corridor — five cells for the 5.0 m
	# storey (slope 0.516) — so the two stairwells are one above the other in the
	# same corridor and the lane below is floor somebody can stand on. That is
	# asserted, not eyeballed: `tower_selfcheck` reads the cell under every lane cell
	# out of the storey below's own grid.
	# ------------------------------------------------------------------------
	{
		"floor": 3,
		"from": 2,
		"landing": "s4_landing",
		"rooms": {
			"A": "s4_accounts_a",
			"B": "s4_accounts_b",
			"C": "s4_accounts_c",
			"E": "s4_payroll_a",
			"F": "s4_payroll_b",
			"H": "s4_payroll_c",
			"I": "s4_supply_a",
			"J": "s4_supply_b",
			"K": "s4_supply_c",
			"L": "s4_dispatch_a",
			"M": "s4_dispatch_b",
			"N": "s4_dispatch_c",
		},
		"gates": {},
		"rows": [
			"########################################",
			"#........................SSSSSs........#",
			"#........................SSSSSs........#",
			"#..################..################..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#APA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AAA##BBB##CCCC#..#EEE##FFF##HHHH#..#",
			"#..#AA###BB###CC###..#EE###FF###HH###..#",
			"#......................................#",
			"#......................................#",
			"#..#II###JJ###KK###..#LL###MM###NN###..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NPNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..#III##JJJ##KKKK#..#LLL##MMM##NNNN#..#",
			"#..################..################..#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 4, the accounts floor: twelve small offices, three to a "
			+ "quadrant, off the same ring-and-cross skeleton.",
	},
	# ------------------------------------------------------------------------
	# STOREY 5 (floor 4) — THE EXECUTIVE FLOOR, and the top of the building for now.
	# Eight deep suites split the other way (on Z, two to a quadrant) and open onto
	# the ring corridor rather than the cross, so the floor reads as a different
	# plan and not as storey 3 with the letters changed.
	#
	# Its ramp rises out of storey 4's SOUTH CROSS corridor, so the three stairs
	# walk the building rather than stacking in one shaft.
	#
	# ponytail: this storey has NO CEILING. It is open to the sealed roof 29 m
	# above, which is the honest state of a building whose storeys 6-10 are phase 16.
	# It costs nothing today: a 4.6 m wall top is a metre above the jump apex, so
	# there is nothing up there to climb onto. Storeys 6+ are what closes it.
	# ------------------------------------------------------------------------
	{
		"floor": 4,
		"from": 3,
		"landing": "s5_landing",
		"rooms": {
			"A": "s5_boardroom",
			"B": "s5_secretariat",
			"C": "s5_directors_north",
			"E": "s5_directors_south",
			"F": "s5_legal",
			"H": "s5_audit",
			"I": "s5_lounge",
			"J": "s5_press_room",
		},
		"gates": {},
		"rows": [
			"########################################",
			"#......................................#",
			"#......................................#",
			"#..################..################..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#..AAAAAPAAAAAAAAA#..#CCCCCCCCCCCCCCC..#",
			"#..AAAAAAAAAAAAAAA#..#CCCCCCCCCCCCCCC..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#..################..################..#",
			"#..################..################..#",
			"#..#BBBBBBBBBBBBBB#..#EEEEEEEEEEEEEE#..#",
			"#..#BBBBBBBBBBBBBB#..#EEEEEEEEEEEEEE#..#",
			"#..BBBBBBBBBBBBBBB#..#EEEEEEEEEEEEEEE..#",
			"#..BBBBBBBBBBBBBBB#..#EEEEEEEEEEEEEEE..#",
			"#..#BBBBBBBBBBBBBB#..#EEEEEEEEEEEEEE#..#",
			"#..#BBBBBBBBBBBBBB#..#EEEEEEEEEEEEEE#..#",
			"#..################..################..#",
			"#........................SSSSSs........#",
			"#........................SSSSSs........#",
			"#..################..################..#",
			"#..#FFFFFFFFFFFFFF#..#IIIIIIIIIIIIII#..#",
			"#..#FFFFFFFFFFFFFF#..#IIIIIIIIIIIIII#..#",
			"#..FFFFFFFFFFFFFFF#..#IIIIIIIIIIIIIII..#",
			"#..FFFFFFFFFFFFFFF#..#IIIIIIIIIIIIIII..#",
			"#..#FFFFFFFFFFFFFF#..#IIIIIIIIIIIIII#..#",
			"#..#FFFFFFFFFFFFFF#..#IIIIIIIIIIIIII#..#",
			"#..################..################..#",
			"#..################..################..#",
			"#..#HHHHHHHHHHHHHH#..#JJJJJJJJJJJJJJ#..#",
			"#..#HHHHHHHHHHHHHH#..#JJJJJJJJJJJJJJ#..#",
			"#..HHHHHHHHHHHHHHH#..#JJJJJJJJJJJJJJJ..#",
			"#..HHHHHHHHHHHHHHH#..#JJJJJJJJJPJJJJJ..#",
			"#..#HHHHHHHHHHHHHH#..#JJJJJJJJJJJJJJ#..#",
			"#..#HHHHHHHHHHHHHH#..#JJJJJJJJJJJJJJ#..#",
			"#..################..################..#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 5, the executive floor: eight deep suites opening onto the "
			+ "ring corridor. Open to the shell roof until storey 6 lands.",
	},
]


## The storey row for a `FLOOR_Y` index, or `{}` if that floor carries no plan
## (floors 0 and 1 are the phase-3 keep and are authored in `tower_interior.gd`).
static func storey(floor_index: int) -> Dictionary:
	for row in STOREYS:
		if int(row["floor"]) == floor_index:
			return row
	return {}


## Every planned floor index, in `STOREYS` order — the builder's and the audits'
## one iteration order, so nobody keeps a second list of which storeys exist.
static func floors() -> Array[int]:
	var out: Array[int] = []
	for row in STOREYS:
		out.append(int(row["floor"]))
	return out
