class_name TowerPlans
extends RefCounted
## THE TOWER'S STOREYS, DRAWN AS TEXT — the hand-planned layout of every floor
## in the building, ground storey included.
##
## It used to say "every floor above the phase-3 keep", because floors 0 and 1
## were hand-authored against the inner faces of a 20 m box standing in the middle
## of the 80 m hall. Bead `godot-test1-dn8` demolished that keep; those two floors
## are `STOREYS` rows like every other, and there is no floor of this tower that is
## not drawn here.
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
## TWO authored edits, and no third:
##
##   1. one `STOREYS` row here (the ASCII plus its `rooms` / `gates` maps);
##   2. its `TOWER_GRAPH` room and edge rows, so the graph audit knows the space
##      exists and how it is entered.
##
## **NO BUILDER LOGIC EDIT, EVER.** `tower_interior.gd` walks whatever is in
## `STOREYS`; it knows about storeys, not about storey 3. If adding a floor ever
## requires a line of CODE in the builder, the format has failed and the format is
## what should change.
##
## MEASURED, not asserted: a throwaway sixth storey was built during phase 14 and
## cost the two rows above plus exactly two DECLARED NUMBERS moving — one more
## `FLOOR_Y` element (the new walking surface, which is data and has to be said
## once somewhere) and `DRAW_BUDGET` 26 -> 27 (one more storey mesh). Zero lines of
## builder logic, and the self-check named the budget itself rather than leaving it
## to be noticed. That is the honest shape of the promise; both audits keep it.
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
##   1-4      one pad of a riddle's COMBINATION LOCK, and the digit IS which pad it
##            is: the gate row's `answer` is a sequence of these digits, and the
##            clue painted in its clue room is the same four colours in the same
##            order. Bound to its gate through the storey's `gates` dict exactly as
##            a `D` is, so a lock and the mass it opens may sit on different floors
##            and neither can be drawn and forgotten.
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
##            `gates` dict and name a real `TOWER_GRAPH` gate row. Emits the gate's
##            mass: one box filling the run, floor slab to ceiling, which rises out
##            of the way when the gate opens and never comes back.
##
## ============================================================================
## A STOREY ROW
## ============================================================================
##
##   floor    int    index into `TowerInterior.FLOOR_Y` — the walking surface, and
##                   the `floor` every box this storey emits declares.
##   from     int    the floor index this storey's ramp climbs FROM.
##
##                   **`from == floor` means this storey is entered from OUTSIDE
##                   the building.** It draws no `S` lane at all, and its `s` cells
##                   are the DOORMAT rather than the head of a ramp — still the
##                   flood fill's start, because that is where a player actually
##                   arrives. The ground storey is the only row shaped like this
##                   today, and it is data rather than a special case: the builder
##                   needs no arm for it (`_plan_stair()` already answers `{}` when
##                   there are no `S` cells, so `_plan_ramp` and `_plan_hole` emit
##                   nothing), and only the AUDIT knows, because every S-lane rule
##                   it enforces — one solid lane, landing against a short end, the
##                   lane standing on the floor below, the slope ceiling — is a
##                   claim about a lane that does not exist here.
##   landing  String the `TOWER_GRAPH` room id the `s` cells are.
##   rooms    Dict   room letter -> `TOWER_GRAPH` room id.
##   gates    Dict   "<c>,<r>" -> `TOWER_GRAPH` gate id, for every `D` cell AND
##                   every lock-pad digit. One dict for both, so a pad on floor 3
##                   and the mass it lifts on floor 4 name the same gate.
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
# ponytail: `G` is still PARSED AND VALIDATED and builds nothing — a post spawns no
# guard, because population is phase 17's, and it is bound to a real row by check 1
# today, which is what stops one being drawn on a plan and forgotten. Wiring is one
# arm in `plan_boxes()` / `_ready()` when that phase lands; the format did not
# change to wire `D`, which is the evidence that it will not have to.
const POST_CHAR: String = "G"
const GATE_CHAR: String = "D"

## The riddle lock's pads, in digit order. FOUR, and the count is not free: a gate's
## `answer` is a permutation of them, and the mass rises one notch per correct step,
## so four pads and four notches are the same number said once.
const PAD_DIGITS: String = "1234"


static func pad_digit(ch: String) -> int:
	"""Which lock pad this character is (1..4), or 0 when it is not one."""
	return PAD_DIGITS.find(ch) + 1


const STOREYS: Array[Dictionary] = [
	# ------------------------------------------------------------------------
	# STOREY 1 (floor 0) — THE GROUND FLOOR, and the last thing bead
	# `godot-test1-dn8` moved onto this grid. Until that bead it was the phase-3
	# KEEP: a windowless 20 m box standing in the middle of an 80 m hall, drawn
	# from a hand-authored table of boxes against its own inner faces. The keep is
	# demolished; the hall it stood in is this floor.
	#
	# IT IS THE ONE STOREY ENTERED FROM OUTSIDE, so `from` is its own floor and it
	# draws no `S` lane at all (see the header). Its `s` cells are the DOORMAT —
	# the hall behind the shell's doorway, which is where a player actually
	# arrives and therefore where both flood fills start. The four cells of `s`
	# out at column 39 are the threshold itself: the plan's own outer ring stops
	# there so the front door opens into a room and not into a wall.
	#
	# THE ROUTE IS PHASE 3'S ROUTE, REDRAWN AT FOUR TIMES THE SCALE. In through
	# the east door into the ENTRY HALL; the annulus (`O`) opens off it north and
	# south, ungated, and the grand climb leaves the far side of the ROTOR
	# DOORWAY — the one gap in the wall at column 20, and the only land entrance
	# to the COURTYARD. The courtyard's lane runs west and then south to the foot
	# of storey 2's ramp at columns 4-9, rows 30-31, which is why those cells are
	# plain floor and must stay that way: `tower_selfcheck` reads the cell under
	# every lane cell out of this grid. Off the hall's south wall, behind the
	# demand shutter, is the VAULT — optional, skippable, and the only room on the
	# floor you can be refused.
	#
	# THE ROTOR DOORWAY CARRIES A `D`, AND THAT IS A CORRECTION TO THE PLAN THIS
	# BEAD WAS WRITTEN FROM. Drawn as a plain gap the two rooms land in ONE piece
	# of floor with every gate shut, and `_gates_shut_problems` rightly calls that
	# "the drawing offers a way round a door the audit models" — the challenge
	# would be decorative in the only place the audit can see. So it is a gate
	# slot like `maintenance_crawl`'s, its lintel comes from `_plan_gates`'
	# challenge arm, and the post and its two sweeping bars are hand-built from
	# the same run (`TowerInterior._rotor_boxes`) because a thing that moves is
	# not a plan character.
	# ------------------------------------------------------------------------
	{
		"floor": 0,
		"from": 0,
		"landing": "entry_hall",
		"rooms": {
			"C": "courtyard",
			"O": "outer_hall",
			"V": "vault",
		},
		# Two gates, two classes, and neither draws its own mechanism: the rotor's
		# bars and the vault's shutter, receptacle and calibration ladder are all
		# hand-built off these runs.
		"gates": {
			"20,19": "rotor_gate", "20,20": "rotor_gate",
			"29,27": "tower_vault", "30,27": "tower_vault",
		},
		"rows": [
			"########################################",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOPOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#######..###########",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCCCCCCCCCCCC#sssssssssssssssssss",
			"#CCCCCCCCC..........Dsssssssssssssssssss",
			"#CCCCCCCCC..P.......Dsssssssssssssssssss",
			"#CCCCCCCCC..CCCCCCCC#sssssssssssssssssss",
			"#CCCCCCCCC..CCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCC..CCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCC..CCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCC.GCCCCCCCC#ssssssssssssssssss#",
			"#CCCCCCCCC..CCCCCCCC#sssssssss.ssssssss#",
			"#CCCCCCCCC..CCCCCCCC##..#####DD#########",
			"#CCCCCCCCC..CCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#CCCCCCCCC..CCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#C..........CCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#C..........CCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOO#VVVVVV#OOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOO########OOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"#CCCCCCCCCCCCCCCCCCC#OOOOOOOOOOOOOOOOOO#",
			"########################################",
		],
		"note": "Storey 1, the ground floor: the 80 m hall the phase-3 keep used to "
			+ "stand in. Front door east into the entry hall, the annulus off it "
			+ "north and south, the vault behind the demand shutter to the south, "
			+ "and west through the rotor doorway into the walled courtyard, where "
			+ "the climb to storey 2 begins.",
	},
	# ------------------------------------------------------------------------
	# STOREY 2 (floor 1) — THE MUSTER FLOOR, and the first of the two storeys bead
	# `godot-test1-dn8` moved onto this grid. It used to be the keep's MEZZANINE:
	# a 20 m square of slab over the courtyard, hand-authored against the inner
	# faces of a building that no longer exists. It is now an ordinary 80 m plate
	# like every floor above it.
	#
	# THE FLOOR IS TWO RAMPS AND THE WALK BETWEEN THEM. You arrive in the south
	# west at the head of the ground floor's ramp (`s`, the six-cell `S` lane
	# climbing 4.6 m at slope 0.395), cross the muster hall or the concourse round
	# it, and leave at the north-west corner where the grand ramp to storey 3
	# starts — which is why rows 1-2, columns 5-14 are PLAIN FLOOR and must stay
	# that way: storey 3's lane stands on them, and `tower_selfcheck` reads the
	# cell under every lane cell out of this grid.
	#
	# THE CHECKPOINT IS A SAFE HAVEN BY CONSTRUCTION, and that is geometry now
	# rather than a hand-tuned number. `_plan_guard_post` measures a patrol as the
	# symmetric run of PLAIN `.` cells around the post, and the `D` cell is not
	# one — so the post in the vestibule (two cells of beat, west of the secure
	# door) can never reach through the doorway it watches. A guard on this floor
	# cannot follow you into the checkpoint; before this bead that was
	# `GUARD_POSTS`' `patrol_half` promising the same thing by hand.
	# ------------------------------------------------------------------------
	{
		"floor": 1,
		"from": 0,
		"landing": "upper_landing",
		"rooms": {
			"A": "checkpoint_room",
			"B": "s2_muster",
		},
		# The identity mass fills the checkpoint's only doorway. Its pad is DERIVED
		# from the plain floor on the vestibule side (`gate_pad_cell`), so the side
		# you open it from is drawn rather than authored.
		"gates": {
			"29,13": "tower_secure_door", "29,14": "tower_secure_door",
		},
		"rows": [
			"########################################",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#..#########BB#########................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#......#########.#",
			"#..#BBBBPBBBBBBBBBBBBB#......#AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#......#AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#.######AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#......DAAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#...G..DAAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBBB.######AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBBB......#AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#......#AAAAAAA#.#",
			"#..#BBBBBBBBBBBBBBBBBB#......#########.#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBPBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..#BBBBBBBBBBBBBBBBBB#................#",
			"#..####################................#",
			"#......................................#",
			"#......................................#",
			"#...SSSSSSs............................#",
			"#...SSSSSSs............................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 2, the muster floor: the keep's mezzanine redrawn as a full "
			+ "80 m plate. The ground floor's ramp lands in the south-west, the "
			+ "grand ramp to storey 3 leaves from the north-west, and the "
			+ "checkpoint sits east behind the secure door, watched by a post "
			+ "whose beat stops at the doorway it guards.",
	},
	# ------------------------------------------------------------------------
	# STOREY 3 (floor 2) — THE RECORDS FLOOR, and the first of the office storeys.
	#
	# THE GRAND RAMP NOW CLIMBS FROM STOREY 2, NOT FROM THE GROUND. It used to
	# start on the annulus floor and carry the whole 11.0 m in ten cells of X
	# (19.40 m, slope 0.567); bead `godot-test1-dn8` drew floor 1 as a full 80 m
	# plate, and a ramp from 0 to 2 would pass straight THROUGH that slab — the
	# format has no hole character, and `_plan_hole` only cuts the slab of the
	# storey a ramp arrives on. So `from` is 1 and the same ten cells carry 6.4 m
	# instead: slope 0.330, the gentlest ramp in the building.
	#
	# The lane's cells stand on rows 1-2, columns 5-14 of storey 2, which that
	# storey's plan keeps as plain floor on purpose. `tower_selfcheck` reads the
	# cell under every lane cell out of the storey below's own grid, so moving
	# either drawing without the other fails the build.
	#
	# The floor is a two-cell RING CORRIDOR round the outside and a two-cell CROSS
	# down each axis, so every room has two ways back to the landing and no dead end
	# is longer than one room. Eight long stacks hang off it, two per quadrant, each
	# entered through a two-cell hole in the wall it shares with the cross corridor.
	# ------------------------------------------------------------------------
	{
		"floor": 2,
		"from": 1,
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
		# The strongroom's mass fills the west permits doorway; its four lock pads
		# are the two-by-two block in the corridor directly in front of it, so the
		# thing you are opening is in your eye line while you enter the sequence.
		"gates": {
			"24,18": "riddle_strongroom", "25,18": "riddle_strongroom",
			"24,19": "riddle_strongroom", "25,19": "riddle_strongroom",
			"24,20": "riddle_strongroom", "25,20": "riddle_strongroom",
		},
		"rows": [
			"########################################",
			"#....SSSSSSSSSSs.......................#",
			"#....SSSSSSSSSSs.......G...............#",
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
			"#..###AA######BB###..###DD######EE###..#",
			"#.......................12.............#",
			"#.......................34.............#",
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
			+ "quadrant. Two of them carry the clues both riddles are about; the "
			+ "west permits stack is the strongroom one of them opens.",
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
			"#........................SSSSSs...G....#",
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
	# PHASE 16 PUT A CEILING ON IT. Storey 6's slab is now 4.6 m over this floor,
	# which is why `FLOOR_NEIGHBOURS[4]` grew from `[3]` to `[3, 5]` — the ceiling a
	# player on this floor is looking at belongs to the storey above, and index
	# arithmetic would have hidden it.
	#
	# ITS RIDDLE MOVED, AND THE MOVE WAS FORCED. `riddle_stair` used to fill the east
	# end of the stairhead pocket, i.e. it sat across the ONLY passage on the main
	# vertical spine between the ramp and the floor. Phase 16 makes the storey-8
	# landing an unlockable lift stop, and `tower_selfcheck` check 10 requires that
	# from EVERY legal entry the full roster can reach a riddle's clue room with that
	# riddle treated as a wall. This riddle's clue is on storey 3, three floors BELOW
	# the new stop: enter at storey 8 and the descent to the clue crosses the gate the
	# clue explains. That is not a check being pedantic — a player lifted to storey 8
	# on a fresh profile really would be locked out of the clue.
	#
	# So any riddle across the main spine below the lift stop is unauditable, and this
	# one became optional side content in `riddle_strongroom`'s mould: its mass fills
	# the BOARDROOM's doorway and its four pads stand in the west ring corridor in
	# front of it, the same "the thing you are opening is in your eye line" rule. The
	# stairhead pocket is now just the head of the ramp, so `s5_stairhead` is GONE
	# and this floor names its corridor as its landing like every other storey —
	# a room no plan draws is a room check 14 cannot see. DO NOT PUT A RIDDLE BACK
	# ACROSS THE STAIR.
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
		# The stair riddle, on the boardroom's doorway since phase 16 (see above for
		# why it is no longer on the stair). The mass is the two-cell doorway; the
		# four pads are the block of ring corridor directly in front of it.
		"gates": {
			"3,6": "riddle_stair", "3,7": "riddle_stair",
			"1,6": "riddle_stair", "2,6": "riddle_stair",
			"1,7": "riddle_stair", "2,7": "riddle_stair",
		},
		"rows": [
			"########################################",
			"#......................................#",
			"#......................................#",
			"#..################..################..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#..#AAAAAAAAAAAAAA#..#CCCCCCCCCCCCCC#..#",
			"#12DAAAAPAAAAAAAAA#..#CCCCCCCCCCCCCCC..#",
			"#34DAAAAAAAAAAAAAA#..#CCCCCCCCCCCCCCC..#",
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
			"#........................SSSSSs......G.#",
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
			+ "ring corridor. The stair riddle's sequence lock now seals the "
			+ "boardroom rather than the floor, and storey 6 is its ceiling.",
	},
	# ------------------------------------------------------------------------
	# STOREY 6 (floor 5) — OPERATIONS. A SPINE, not a cross: one east-west corridor
	# straight across the middle of the floor, with three wide bands of room hung off
	# each side of it and a two-cell ring corridor round the outside. Storeys 3 and 4
	# are a ring AND a cross with stacks in the quadrants; this floor has no
	# north-south corridor at all, so crossing it is one long walk and the plan reads
	# as a different building rather than as storey 3 with the letters changed.
	#
	# The north and south bands are split on DIFFERENT columns (14/25 against 13/24),
	# so no room faces its opposite number across the spine.
	#
	# Its ramp rises out of storey 5's SOUTH ring corridor: five cells of X (9.70 m)
	# for the 5.0 m storey, slope 0.5155 against the proven 0.575. Storey 5's own ramp
	# is in its middle corridor, so the two stairwells do not stack — the same "walk
	# the ramps apart" rule storeys 3-5 follow.
	# ------------------------------------------------------------------------
	{
		"floor": 5,
		"from": 4,
		"landing": "s6_landing",
		"rooms": {
			"A": "s6_dispatch_hall",
			"B": "s6_control_centre",
			"C": "s6_comms",
			"E": "s6_fleet_bay",
			"F": "s6_logistics",
			"H": "s6_crew_room",
		},
		"gates": {},
		"rows": [
			"########################################",
			"#......................................#",
			"#......................................#",
			"#..##################################..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAPAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#AAAAAAAAAAA#BBBBBBBBBB#CCCCCCCCC#..#",
			"#..#####AA##########BB########CC#####..#",
			"#......................................#",
			"#......................................#",
			"#..####EE#########FF#########HH######..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHPHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..#EEEEEEEEE#FFFFFFFFFF#HHHHHHHHHHH#..#",
			"#..##################################..#",
			"#...................SSSSSs.............#",
			"#...................SSSSSs......G......#",
			"########################################",
		],
		"note": "Storey 6, operations: one east-west spine corridor with three wide "
			+ "bands of room to the north and three more to the south, and a ring "
			+ "corridor round the outside. Where the fleet is dispatched from.",
	},
	# ------------------------------------------------------------------------
	# STOREY 7 (floor 6) — SECURITY, and where the labyrinth's fiction starts. The
	# spine turns NORTH-SOUTH here and the four quarters it serves are split
	# off-centre — the control room is deep and the vault beside it is shallow, and
	# the same offset the other way to the south — so the floor pinwheels rather than
	# mirroring. Nothing on it is gated: the maze above is what security actually
	# relies on, which is the joke.
	#
	# Its ramp rises out of storey 6's NORTH ring corridor, at the far end of the
	# building from storey 6's own ramp in the south.
	# ------------------------------------------------------------------------
	{
		"floor": 6,
		"from": 5,
		"landing": "s7_landing",
		"rooms": {
			"I": "s7_control_room",
			"J": "s7_records_vault",
			"K": "s7_briefing_room",
			"L": "s7_muster_hall",
		},
		"gates": {},
		"rows": [
			"########################################",
			"#.......SSSSSs.........................#",
			"#.......SSSSSs.......G.................#",
			"#..################..################..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..JJJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..JJJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIIII..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIPIIIIIIIIII..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..#JJJJJJJJJJJJJJ#..#",
			"#..#IIIIIIIIIIIIII#..################..#",
			"#..#IIIIIIIIIIIIII#..#LLLLLLLLLLLLLL#..#",
			"#..#IIIIIIIIIIIIII#..#LLLLLLLLLLLLLL#..#",
			"#..#IIIIIIIIIIIIII#..#LLLLLLLLLLLLLL#..#",
			"#..################..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..LLLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..LLLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKKK..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKKK..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLPLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..#KKKKKKKKKKKKKK#..#LLLLLLLLLLLLLL#..#",
			"#..################..################..#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 7, security: a north-south spine between four off-centre "
			+ "quarters — the control room, the records vault the maze's plans are "
			+ "filed in, the briefing room and the muster hall.",
	},
	# ------------------------------------------------------------------------
	# STOREY 8 (floor 7) — THE LABYRINTH, LOWER HALF. The first floor of the maze
	# the bead asked for, and nothing about it is generated: it is drawn here, cell
	# by cell, and a future author edits the text. There is no seed and there may
	# never be one.
	#
	# TWO ROUTES from the ramp out of storey 7 to the ramp up to storey 9, both
	# base kit, exactly as the phase-16 plan rules:
	#
	#   ROUTE A — THE LONG WAY, UNGATED END TO END, and the one the four rescue
	#   spines walk. It is the OUTER CIRCUIT, the one-cell ring corridor just inside
	#   the shell: from the landing at (25, 38) EAST along the south ring to (38, 38),
	#   north up the east ring to (38, 1), west along the north ring to (15, 1) — the
	#   foot of storey 9's ramp. 73 cells of walking, and not one of them asks a
	#   question.
	#
	#   EAST AND NOT WEST, and the ring is a C rather than a loop because of it. The
	#   ramp lane occupies (20..24, 37..38) and its deck DESCENDS from 36.0 m at the
	#   landing to 31.0 m at column 20 — storey 7's floor. Walking west off the
	#   landing therefore walks you back DOWN the ramp and into a 5 m step up at
	#   (19, 38); row 38's west half is reached by carrying on round column 1, not by
	#   stepping off the landing. A future author redrawing this floor has to keep the
	#   circuit reachable in the direction AWAY from the ramp, whichever end the `s`
	#   lands on.
	#
	#   ROUTE B — THE SHORT WAY, behind `riddle_maze_lower`. From the same landing
	#   north into the arrival pocket, past the four lock pads at (26..27, 35..36)
	#   and through the mass at (27, 34); north up column 27 to row 27; west along
	#   row 27 to column 20; north up column 20 into the CORE at (20, 21); out of its
	#   north face at (20, 16); north up column 20 to row 9; west along row 8 to
	#   column 12; north up column 12 to row 3; east along row 3 to column 18; and
	#   north into the stair hall at (18, 2). About 55 cells — a third off the
	#   circuit, which is the whole of what the riddle buys.
	#
	# THE CLUE CHAMBERS ARE DEAD ENDS OFF ROUTE A, one per riddle and both on this
	# floor: the WEST chamber (rows 8-12, through the doorway at (2, 10)) carries
	# this floor's riddle, the EAST one (rows 27-31, through (37, 29)) carries the
	# riddle on storey 9. Off the ungated circuit is not decoration — `tower_selfcheck`
	# check 10 asks, from every legal entry and with the riddle treated as a wall,
	# whether the full roster can still read the clue, and a chamber behind its own
	# riddle fails that.
	#
	# Everything else that is not the two routes is a WRONG TURN: nine dead-end spurs
	# off the circuit and eight more off route B's legs. A maze with no wrong turns is
	# a corridor.
	#
	# Its ramp rises out of storey 7's SOUTH ring corridor (five cells of X for the
	# 5.0 m storey, slope 0.5155), and the stair hall at (14..21, 2) is where storey
	# 9's ramp comes down — both feet stand on floor somebody can walk on, asserted
	# cell by cell against the floor below.
	# ------------------------------------------------------------------------
	{
		"floor": 7,
		"from": 6,
		"landing": "s8_landing",
		"rooms": {
			"A": "s8_clue_chamber_west",
			"B": "s8_clue_chamber_east",
			"C": "s8_maze_core",
			"E": "s8_north_hall",
		},
		# The lower riddle: its mass is the single-cell doorway out of the arrival
		# pocket, and its four pads are the two-by-two block in the pocket directly
		# in front of it — the same "the thing you are opening is in your eye line"
		# rule the strongroom and the boardroom follow.
		"gates": {
			"27,34": "riddle_maze_lower",
			"26,35": "riddle_maze_lower", "27,35": "riddle_maze_lower",
			"26,36": "riddle_maze_lower", "27,36": "riddle_maze_lower",
		},
		"rows": [
			"########################################",
			"#......................................#",
			"#.############EEEEEEEE.#######.###.###.#",
			"#.##########.......###.#######.###.###.#",
			"#.##########.##.######.#######.###.###.#",
			"#.###........##.######.#######.###.###.#",
			"#.##########.##.######.#######.###.###.#",
			"#.##########.#########.#######.###.###.#",
			"#.#APAAAA###.........#############.###.#",
			"#.#AAAAAA#####.#####.#################.#",
			"#..AAAAAA#####.##....#################.#",
			"#.#AAAAAA#####.#####.#################.#",
			"#.#AAAAAA#####.#####........####.......#",
			"#.##################.#################.#",
			"#.##################.........#########.#",
			"#.##################.#################.#",
			"#........###########.#################.#",
			"#.##############CCCCCCCC##############.#",
			"#.##############CCCCCCCC##############.#",
			"#.##############CCCCCCCC##############.#",
			"#......#########CCCCCCCC########.......#",
			"#.##############CCCCCCCC########.#####.#",
			"#.##################.......#####.#####.#",
			"#.##################.###.#######.#####.#",
			"#.###########........###.#######.#####.#",
			"#.##################.###.#######.#####.#",
			"#.##################.###.#############.#",
			"#.##################........###BBBBBB#.#",
			"#.#########################.###BBBBBB#.#",
			"#.#########################...#BBBBBB..#",
			"#.####.####################.###BBBBBB#.#",
			"#.####.##############.......###BBBPBB#.#",
			"#.####.####################.##########.#",
			"#.####.###.################.......####.#",
			"#.####.###.################D##########.#",
			"#.####.###.##############.12..########.#",
			"#.####.###.##############.34..########.#",
			"#.####.###.#########SSSSSs....########.#",
			"#...................SSSSSs......G......#",
			"########################################",
		],
		"note": "Storey 8, the labyrinth's lower half: a one-cell maze cut into the "
			+ "slab. The outer circuit is the ungated long way round; the sequence "
			+ "lock on the arrival pocket opens the short way through the core. Both "
			+ "riddles' clue chambers are dead ends off the circuit.",
	},
	# ------------------------------------------------------------------------
	# STOREY 9 (floor 8) — THE LABYRINTH, UPPER HALF. The same two-route rule one
	# floor on, mirrored: the ramp arrives at the NORTH and the way out is at the
	# SOUTH-EAST, so the maze is walked corner to corner rather than round the same
	# side twice.
	#
	#   ROUTE A — THE OUTER CIRCUIT, ungated, and the spines' way through: from the
	#   landing at (20, 1) east along the north ring to (38, 1), south down the east
	#   ring to (38, 38), west along the south ring to (31, 38) and north through the
	#   doorway at (31, 37) into the UPPER HALL. About 64 cells.
	#
	#   ROUTE B — behind `riddle_maze_upper`. South out of the landing into the
	#   arrival pocket, past the pads at (21..22, 3..4) and through the mass at
	#   (20, 5); south down column 20 to row 8; east along row 8 to column 22; south
	#   down column 22 to row 14; into the CORE at (22, 15) and out of its south face
	#   at (22, 20); south down column 22 to row 27; east along row 27 to column 32;
	#   south down column 32 to row 33; and into the upper hall at (32, 34). About 45
	#   cells.
	#
	#   THE MASS IS AT COLUMN 20 AND NOT AT 22 BECAUSE OF THE FLOOR ABOVE IT. A
	#   riddle's mass is floor to ceiling and lifts a notch per correct step, and a
	#   part-entered lock stays lifted — so anything past the 0.4 m slab stands proud
	#   of storey 10's walking surface. Column 22 at row 5 is the middle of Teibi's
	#   cell; column 20 is the pier between two of them. `tower_selfcheck` check 9
	#   now refuses a riddle drawn under a room, so this is a rule and not a
	#   coincidence — the other three locks happened to satisfy it.
	#
	# NEITHER RIDDLE'S CLUE IS ON THIS FLOOR — both chambers are downstairs on storey
	# 8, off its ungated circuit, so a player who took the long way up can still read
	# the answer to the door they are standing at.
	#
	# THE UPPER HALL (rows 34-36, columns 28-35) IS WHERE STOREY 10's RAMP STANDS.
	# It is a room and not a corridor for exactly that reason: a ramp's foot has to
	# land on walkable floor of the storey below, and eight by three cells of hall is
	# what the cell block's stair is drawn onto in the next task.
	# ------------------------------------------------------------------------
	{
		"floor": 8,
		"from": 7,
		"landing": "s9_landing",
		"rooms": {
			"A": "s9_maze_core",
			"B": "s9_upper_hall",
			"C": "s9_dead_gallery",
		},
		"gates": {
			"20,5": "riddle_maze_upper",
			"21,3": "riddle_maze_upper", "22,3": "riddle_maze_upper",
			"21,4": "riddle_maze_upper", "22,4": "riddle_maze_upper",
		},
		"rows": [
			"########################################",
			"#..............SSSSSs..................#",
			"#.#############SSSSSs....#########.###.#",
			"#.##################.12..#########.###.#",
			"#.##################.34..#########.###.#",
			"#.##################D#############.###.#",
			"#.##################.#############.###.#",
			"#.##################.#################.#",
			"#......#####.................#CCCCCC##.#",
			"#.####.#####.#########.#######CCCCCC##.#",
			"#.####.#####.#########.#######CCCCCC...#",
			"#.####.#####.#########.#######CCCCCC##.#",
			"#.####.#####.#########.......#CCCCCC##.#",
			"#.####.#####.......###.#####.#########.#",
			"#.####.###############.#####.#########.#",
			"#.################AAAAAAAA##.#########.#",
			"#.################APAAAAAA##.#########.#",
			"#.################AAAAAAAA##.#########.#",
			"#.################AAAAAAAA############.#",
			"#.################AAAAAAAA############.#",
			"#.......##############.###........####.#",
			"#.##############.......###.###########.#",
			"#.##############.#####.###.###########.#",
			"#.##############.#####.###.###########.#",
			"#.##########...........###.#######.....#",
			"#.##########.###.#####.###.#######.###.#",
			"#.##########.###.#####.###.#######.###.#",
			"#.##########.#########...........#.###.#",
			"#.##########.###################.#.###.#",
			"#.##########.###################.#.###.#",
			"#.######.###.........###########.#.###.#",
			"#.######.#######################.#####.#",
			"#........#######################.#####.#",
			"#.######.#######################.#####.#",
			"#.######.###################BBBBBBBB##.#",
			"#.######.###################BBBBBBPB##.#",
			"#.######.###################BBBBBBBB##.#",
			"#.######.######################.######.#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 9, the labyrinth's upper half: the ramp arrives at the north "
			+ "and the way on is the upper hall at the south-east, reached either "
			+ "round the ungated circuit or through the second sequence lock and the "
			+ "core. Its dead gallery is the floor's one decoy chamber.",
	},
	# ------------------------------------------------------------------------
	# STOREY 10 (floor 9) — THE CELL BLOCK, under the sealed roof, and the top of
	# the building. The phase-8 wing's LAYOUT, re-drawn on the plan grid: one
	# service corridor, FOUR IDENTITY DOORWAYS IN ONE WALL, a gallery behind them
	# and four uniform open-fronted recesses off that. Nothing about the shape
	# changed and NONE of the graph's room ids changed — `service_stair`,
	# `cell_gallery` and the four `cell_<hero>` rows are spelled exactly as phase 8
	# spelled them, because moving geometry is not a save migration and renaming an
	# id is.
	#
	# THE ROUTE IS STILL A STRAIGHT LINE WITH ONE FORK, which is the whole of "the
	# wing is the tutorial for itself": in off the muster floor, along the corridor,
	# through the door that says your name, into the gallery, and the cell you want
	# is the nth recess from the end. Nothing branches and nothing doubles back.
	#
	# TWO WAYS IN, on purpose and for the phase-8 reason: the WIDE DOORWAY at
	# (13..14, 15) is `block_main_door` and asks nothing, and the DUCT at (27, 15)
	# is `maintenance_crawl` with its stamping press — a challenge, so anybody gets
	# through it. The custody scar drops the first; the second is what makes that
	# survivable, and `tower_selfcheck` check 6 recomputes that rather than trusting
	# this comment.
	#
	# THE FOUR DOORWAYS ARE ONE CELL EACH (1.94 m, comfortably over the 1.5 m that
	# clears a giant Teibi) and each stands under its own recess, so the door you
	# want and the cell behind it are the same column of the plan. Their pads are
	# NOT drawn: the builder derives each one from the plain-floor side of its own
	# doorway (see `_plan_gates`), which is why row 12 is `.` and not corridor.
	#
	# BOTH `P` PADS STAND IN THE CORRIDOR AND NEITHER IS IN THE GALLERY, which is
	# not a layout preference: the gallery already carries the VENT PURGE, a LIVE
	# `COLOR_SYSTEM` plate, and a plan pad is the same colour and inert until phase
	# 17 gives it something to do. Two identical cyan plates a metre apart, one of
	# which works, is the legibility language lying — a system pad promises "stand
	# here and something opens, elsewhere". Keep them out of this room.
	#
	# ITS CEILING IS THE SEALED ROOF, not a slab: 46.0 m of floor under 50.0 m of
	# wall is 4.0 m of clear air, the tightest number in this phase and 5 cm over
	# what the indoor camera boom needs. `plan_clear_height()` is what knows that,
	# and raising `SLAB_THICK` or dropping the roof is what would break it.
	#
	# Its ramp rises out of storey 9's UPPER HALL at the south-east — six cells of X
	# (11.64 m) for the 5.0 m storey, slope 0.4296, the shallowest in the building.
	# ------------------------------------------------------------------------
	{
		"floor": 9,
		"from": 8,
		"landing": "s10_landing",
		"rooms": {
			"A": "service_stair",
			"B": "cell_gallery",
			"C": "cell_windman",
			"E": "cell_primm",
			"F": "cell_teibi",
			"H": "cell_phoboman",
		},
		# The four rescue spines, west to east, in `TowerInterior.SPINE_DOORS`
		# order — and the hero each one answers to is read from `TowerGraph`, never
		# from this file. Plus the maintenance crawl's duct in the south wall.
		"gates": {
			"12,11": "updraft_shaft",
			"17,11": "phase_grate",
			"22,11": "collapsed_slab",
			"27,11": "hound_den",
			"27,15": "maintenance_crawl",
		},
		"rows": [
			"########################################",
			"#......................................#",
			"#......................................#",
			"#.........#####################........#",
			"#.........#CCCC#EEEE#FFFF#HHHH#........#",
			"#.........#CCCC#EEEE#FFFF#HHHH#........#",
			"#.........#CCCC#EEEE#FFFF#HHHH#........#",
			"#.........#CCCC#EEEE#FFFF#HHHH#........#",
			"#.........#BBBBBBBBBBBBBBBBBBB#........#",
			"#.........#BBBBBBBBBBBBBBBBBBB#........#",
			"#.........#BBBBBBBBBBBBBBBBBBB#........#",
			"#.........##D####D####D####D###........#",
			"#.........#...................#........#",
			"#.........#AAAAAAAAAAAAAAAAAAA#........#",
			"#.........#AAPAAAAAAAAAAAAPAAA#........#",
			"#.........###..############D###........#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"#...........................SSSSSSs..G.#",
			"#...........................SSSSSSs....#",
			"#......................................#",
			"#......................................#",
			"#......................................#",
			"########################################",
		],
		"note": "Storey 10, the cell block: the service corridor, the four identity "
			+ "doorways in its north wall, the gallery behind them and four uniform "
			+ "recesses off that. The muster floor around it is the landing the "
			+ "ramp from storey 9 arrives on.",
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
