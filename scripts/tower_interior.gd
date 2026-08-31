class_name TowerInterior
extends Node3D
## THE TOWER, INSIDE — GastroDefense HQ's first playable interior (epic
## godot-test1-3iy, phase 3, the keystone).
##
## Phase 1 decided WHERE the tower stands, phase 2 built the SHELL and gave it a
## doorway you can walk through. This is what is behind that doorway: ten storeys,
## ramps between them, and one instance of each of the room verbs the rest of the
## epic is built out of.
##
## THE KEEP IS GONE. Phase 3 built the first two of those storeys as a windowless
## 20 m box standing inside the 80 m envelope, hand-authored against its own inner
## faces; bead `godot-test1-dn8` demolished it and redrew both floors on
## `TowerPlans`' grid like every storey above them. The route below is phase 3's
## route, walked through the building that replaced it — same rooms, same gates,
## same persisted ids, four times the floor.
##
## ============================================================================
## THE ROUTE, which is the design (walk it in this order):
## ============================================================================
##
##   doorway (+X wall)  →  ENTRY HALL, the east half of the ground plate, 4.2 m
##                         of headroom under storey 2's slab
##                      →  THE ANNULUS (`outer_hall`), off the hall north and
##                         south, ungated — and the way up the building
##                      →  THE ROTOR GATE (the CHALLENGE SPACE): the only opening
##                         west, with two counter-rotating bars sweeping it
##                      →  COURTYARD, the whole west half of the plate. Storey 2
##                         roofs it now, which the persisted room id does not mind
##                      →  THE RAMP, up the courtyard's south-west corner
##                      →  MUSTER FLOOR (storey 2), an 80 m plate with the
##                         checkpoint walled off east behind the SECURE DOOR
##                      →  THE BASE-KIT MASS: any hero can lift it
##                      →  THE CHECKPOINT, lit green once you stand on it
##
##   and, off the hall to the south, the DEMAND GATE sealing a vault. Optional,
##   skippable, and the whole point of it is that you can SEE what it wants.
##
## ...and, from the muster floor's north-west corner, up the GRAND RAMP and on up
## the building (phases 14-16): seven hand-planned storeys of offices, the
## two-floor LABYRINTH, and at the top of them, on storey 10 under the sealed
## roof, THE CELL BLOCK:
##
##   muster floor →  THE MAINTENANCE CRAWL: a low duct with a stamping press
##                   across it. A challenge, so anybody gets through it.
##               →  the same corridor by its WIDE DOORWAY, which asks nothing.
##                  Two ways in, on purpose: the custody scar drops one.
##               →  THE SERVICE CORRIDOR, with FOUR DOORS along its north side
##                  and a violet pad in front of each. One door per hero, and
##                  each is that hero's rescue spine (`TowerGraph.spines`).
##               →  THE CELL GALLERY, and off it FOUR UNIFORM CELLS. Whoever
##                  reached the gallery can open any of them: liberation asks
##                  nobody's name, which is what "uniform cells" means.
##
## THE BLOCK IS THE TUTORIAL FOR ITSELF. Ordinary rescues walk it over and over,
## and the one scene where it matters most is the last one — so the geography is
## deliberately a straight line with a single fork: corridor, four doors, one
## gallery, four cells in a row. Nothing branches, nothing doubles back, and the
## cell you want is always the nth recess from the end. PHASE 16 MOVED IT AND
## CHANGED NONE OF THAT: the layout is now drawn on `TowerPlans`' storey-10 grid
## instead of hand-placed north of the entry hall, and every graph room id it
## carries is spelled exactly as phase 8 spelled it.
##
## ============================================================================
## THE LEGIBILITY LANGUAGE — READ THIS BEFORE ADDING A ROOM
## ============================================================================
##
## The epic's session-03 ruling is that a player must be able to tell, AT A GLANCE
## and from across the room, which of three things they are looking at. That is a
## promise about silhouette, material and light — not about text — because text is
## read after you have already decided whether to walk over. So:
##
##   ORDINARY GEOMETRY — walls, floors, the ramp, the jambs.
##     Silhouette: flat slabs, axis-aligned, no overhang, nothing pointing at you.
##     Material:   COLOR_STONE. Matte, unlit, the same family as the shell.
##     Light:      none of its own. It is lit by the panels or by the sky.
##     Reads as:   "this is the building".
##
##   CHALLENGE SPACE — a hazard you beat with the base kit (run, jump, duck).
##     Silhouette: THINGS THAT MOVE, and nothing else in the game moves like this.
##     Material:   COLOR_HAZARD, high-chroma orange, the one warm accent down here.
##     Light:      none. It is dangerous, not powered.
##     Reads as:   "time this".
##     Rule for later rooms: a challenge NEVER carries a calibration band and
##     NEVER carries a hero colour. If a player has to ask "can I even attempt
##     this?" it has been built wrong — the answer is always yes.
##     The secure checkpoint is the one authored challenge exception to the
##     usual lintel silhouette: its rising mass and floor pad stay hazard orange
##     while its access remains base kit. It never uses the violet identity style.
##
##   DEMAND GATE — a corporate mechanism that measures you and finds you short.
##     Silhouette: a SEALED SLAB flush in a wall, plus a free-standing RECEPTACLE
##                 pillar in front of it. The pillar is the tell: nothing else in
##                 the building is a waist-high box you walk up to.
##     Material:   COLOR_MECHANISM, cold blue-grey steel, deliberately NOT stone.
##     Light:      COLOR_BAND_LIT — a vertical ladder of calibration bands on the
##                 pillar's face. LIT BANDS ARE YOUR READING, DARK BANDS ARE THE
##                 SHORTFALL, and the count is the scale. This is the whole
##                 diagnosis: you can see how short you are before you try.
##     Motion:     it SINKS into the floor. Down = "the building let you in".
##     Reads as:   "come back stronger".
##
##   BLOCK SYSTEM — a thing you OPERATE, whose effect happens somewhere else.
##     Silhouette: a pad, flush with the floor, exactly like an identity pad.
##     Material:   COLOR_SYSTEM, cold cyan — in neither gate family on purpose.
##     Light:      the pad glows; there is no mass beside it, and that absence is
##                 the tell. A gate always has something in the doorway.
##     Reads as:   "stand here and something opens, elsewhere".
##     ONE IS WIRED TODAY: the cell block's VENT PURGE, which a benched multiplayer
##     player operates for the team outside (bead godot-test1-3iy.10). The other
##     cyan plates are the `P` cells every storey plan carries — drawn as geometry,
##     wired to nothing until phase 17 brings the guards they scare (see
##     `_plan_pads`). Two of them stand inside the block itself since the block
##     moved to storey 10, so the purge pad is NOT the only cyan plate a prisoner
##     can see; that ambiguity is phase 17's to resolve, and the resolution is
##     wiring them, not recolouring them.
##
##   RIDDLE GATE — a lock that asks where you have been (phase 15).
##     Silhouette: a MASS in a doorway, with FOUR COLOURED PLATES on the floor in
##                 front of it. Four plates is the tell — every other pad in this
##                 building is one plate, alone.
##     Material:   COLOR_RIDDLE, a cold indigo in neither gate family, plus the four
##                 pad colours, which are the alphabet its clue is written in.
##     Light:      none. The mass is the readout: it RISES ONE NOTCH per correct
##                 step and clunks back down on a wrong one.
##     Motion:     it rises, and stays risen forever.
##     Reads as:   "the answer is painted somewhere else in this building".
##     Rule for later riddles: a riddle NEVER carries a hero colour and never asks
##     for a rank. Knowledge is party-level, so anybody who has walked to the clue
##     room can open it — which is exactly why it can be on a rescue route and an
##     identity gate has to be justified.
##
##   IDENTITY GATE — a lock that asks who you are, and can never be out-levelled.
##     Silhouette: a MASS. Tall, heavy, filling its doorway, one solid piece.
##     Material:   COLOR_IDENTITY, the hero's violet, plus a floor pad in the same
##                 violet directly in front of it — the pad is where you stand.
##     Light:      the pad glows. The mass does not; it is dead weight.
##     Motion:     it RISES, and stays risen forever. Up = "the world changed".
##     Reads as:   "bring the right hero".
##
## THE TWO GATES ARE DELIBERATELY OPPOSITES ON EVERY AXIS — steel vs violet,
## banded vs blank, sinks vs rises, a number vs a name. A player who has met one
## can classify the other without being told. Keep that up.
##
## ============================================================================
## WHAT THIS FILE IS, structurally
## ============================================================================
##
## SELF-BUILDING FROM A TABLE, exactly like `tower_shell.gd` (and for the same
## three reasons — see its header); `_ready()` is a loop over it. Nothing here is
## authored in a .tscn, so `tower_interior_selfcheck.gd` can measure the plan
## without instancing anything, and the jump-height and headroom rules below are
## ASSERTED rather than eyeballed.
##
## THE TABLE IS NOT IN THIS FILE ANY MORE. `boxes()` — the hand-authored box list
## that WAS the phase-3 keep's two floors — is gone (bd `godot-test1-dn8`), and
## EVERY storey in the building now comes from `TowerPlans.STOREYS`: `all_boxes()`
## is the plan builder over `TowerPlans.floors()` plus the hand-built PARTS, which
## are the things a grid of characters cannot say. A part is a thing that MOVES
## (the rotor's bars, a gate mass), a thing that MEASURES you (the demand
## receptacle and its calibration ladder) or a thing that LIGHTS UP (a checkpoint
## plate, a pad), and each is placed from a plan lookup — `plan_room_rect()` /
## `plan_gate_rect()` — never from an authored X or Z. That is why floors 0 and 1
## could change shape without a single number following them, and it is the same
## rule the cell block has followed since phase 16.
##
## It is a child of the shell, assembled onto it by `endless_terrain._tower_stream`
## (one arrow, one direction: this file reads the shell's constants, so a shell that
## also knew about the interior would be a cyclic `class_name` Godot refuses to
## load). So it exists exactly
## when and where the shell does — including on a multiplayer master simulating a
## teammate at the tower. It is never chunk-parented and never freed except by
## `new_run()` freeing the whole shell.
##
## ============================================================================
## THE JUMP RULE — the tightest constraint in this file
## ============================================================================
##
## The base jump apex is 3.6125 m (`player_controller.JUMP_VELOCITY` 10.2 squared
## over 2 x gravity 14.4) and mountain impassability rests on it staying under
## `MOUNTAIN_MIN_LAYER_HEIGHT` 4.0. Interiors inherit that: **no traversal in this
## building may ever demand a jump-height**, because the day somebody adds a skill
## that raises the apex, every such demand silently becomes free.
##
## So every vertical move is a ramp or a gate, and every horizontal barrier is
## taller than an apex plus whatever you can stand on beneath it:
##
##   THE GROUND FLOOR IS ROOFED, ALL OF IT. While the keep stood, the courtyard
##   was open to the sky and this paragraph was a sweep: every box top between the
##   floor and 4.6 - 3.6125 = 0.9875 m was a step onto the storey above, which is
##   what turned the rotor post into a full-height column instead of the waist-high
##   hub it wants to be. Storey 2 is a full 80 m plate now, so there is no open sky
##   below the roof and the sweep is gone with the table it read — a jump anywhere
##   on floor 0 ends at that slab's underside, exactly as it always did in the
##   entry hall. The receptacle's 2.6 m and the rotor column are harmless for the
##   same reason.
##
##   WHAT REPLACED IT IS STRUCTURAL, not a measurement: a plan storey has exactly
##   two kinds of solid — a wall as tall as its own storey's ceiling, and a gate
##   mass filling its doorway floor to ceiling — and neither can be a ledge at all.
##   So the rule holds for ten storeys by construction, and check 2 asserts THAT
##   rather than sweeping thousands of box pairs. The one thing a plan cannot say
##   is the shell's own wall: top 11.0 m vs slab 4.6 + apex = 8.21. Unjumpable, so
##   storey 2 is a room and not a balcony you can leave over the side.
##
## The shell's WALL_HEIGHT was raised from 7 to 11 for exactly this: two storeys
## of 4.6 m each need 9.2 m of wall before the parapet is even a parapet.
##
## ============================================================================
## CAMERA (the bead's landmine)
## ============================================================================
##
## `CameraArm` is a `SpringArm3D` 8.25 m long, tilted 14 degrees up from a pivot
## 1.5 m over the player's feet — so in the open the camera floats about 3.5 m up.
## Nothing may write `camera.position` (CLAUDE.md), which means the ONLY way to
## make a room comfortable is to build it tall enough. 4.2 m of headroom under the
## ground floor's slab clears that 3.5 m with room for the arm's 0.25 m margin, so
## the arm never slams in on flat ground, and every planned storey above it is
## 4.6 m for the same reason. That is why the ground floor is 4.2 m and not 3.
## Check 4 measures it off a LIVE rig and asks it of every storey, so the day
## somebody retunes `STOREY_HEIGHT` this fails instead of the building quietly
## becoming 6000 m2 of the-back-of-a-head.
##
## HEIGHT IS ONLY HALF OF IT — THE OTHER HALF IS WIDTH, and the outdoor arm is
## 8.25 m long. A corridor is two cells (3.88 m) and the ground floor's rooms are
## walled off from each other, so facing a near wall used to collapse the arm into
## a shot of the back of the hero's head. RESOLVED (bd godot-test1-0nu) by an
## INDOOR BOOM: `_update_visibility` below asks `inside_walls()` — which reads the
## ENVELOPE, not the demolished keep — and hands the answer to
## `PlayerController.set_indoor_camera()`, which swaps the arm to
## `INDOOR_ARM_LENGTH` (3.85; the derivation lives on that constant). This file
## does not touch the camera and could not: nothing may write `camera.position`,
## and the arm belongs to the player. It only answers "are you inside my walls?".
##
## ============================================================================
## COST
## ============================================================================
##
## TWENTY-ODD `MeshInstance3D`s for the parts that move (plus one batch per storey)
## and everything else welded into those batches (see THE BATCH below), ONE
## `StaticBody3D`, twenty-odd `Area3D`s (three pads, two rotor hazards, from
## phase 8 one press hazard, four spine pads and four cell volumes, from phase
## 15 one per riddle lock pad and from phase 16 the labyrinth's lift stop —
## check 5 counts them and is the number that is actually true), two rotor pivots,
## a `Label3D` per sign — three fixed (the demand gate, the spine, the cell) plus a
## lock sign and a clue sign per riddle, so eleven at four riddles and two more per
## riddle after that — and one gem —
## built once, for the life of a run. Per-floor visibility
## gating (`_update_visibility`) is what keeps that off the web frame budget when
## the player is anywhere else in the world.

# ============================================================================
# GEOMETRY — metres, LOCAL to the shell's origin, feet at y = 0
# ============================================================================
#
# THERE ARE NO AUTHORED WIDTHS IN HERE ANY MORE. Every horizontal number this file
# used to carry — the keep's inner faces, the slab's west edge, the vault's jambs,
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

## The rotor doorway: the one gap in the wall between the entry hall and the
## courtyard, and therefore the only land route to the climb. `ROTOR_ARM` must stay
## under `ROTOR_DOOR_HALF` so the sweeping bars clear the jambs, and over
## `ROTOR_DOOR_HALF * 0.5` so a bar lying across the doorway actually blocks a gap
## instead of leaving one open.
##
## WHERE the doorway is, is the PLAN's to say — the `D` run bound to `rotor_gate` on
## whichever storey draws it. What stays here is the pair of numbers the BARS are
## made of, and `tower_interior_selfcheck` asserts the run the plan draws is wide
## enough to hold them.
const ROTOR_DOOR_HALF: float = 1.9
const ROTOR_ARM: float = 1.7

## The two bars: height off the floor, and angular velocity (rad/s). OPPOSITE
## SIGNS and INCOMMENSURATE RATES on purpose — same-signed bars would lock into a
## fixed pattern you learn once, and a rational ratio would make the doorway
## periodic. Both are low enough to hop (the apex is 3.6 m) because DUCKING DOES
## NOT SHRINK THE PLAYER'S CAPSULE in this game — the duck is a model-scale, so a
## "duck under it" bar would be an unwinnable one.
const ROTOR_LOW_Y: float = 0.55
const ROTOR_HIGH_Y: float = 1.05
const ROTOR_LOW_SPEED: float = 1.15
const ROTOR_HIGH_SPEED: float = -0.77

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
# THE RIDDLE LOCK (phase 15) — the fourth gate verb
# ============================================================================
#
# A riddle is a COMBINATION LOCK: four coloured pads in front of a sealed mass,
# pressed in an order painted on a floor somewhere else in the building. It asks
# nothing of who you are and nothing of your ranks — only that you have been to the
# clue room — which is why `tower_graph.gd` calls knowledge party-level and why the
# audit's rule for it is a reachability question and not a capability one.
#
#   Silhouette: a MASS in a doorway, exactly like an identity gate's, with four
#               floor plates in front of it instead of one.
#   Material:   COLOR_RIDDLE, a cold indigo in neither gate family, plus the four
#               pad colours — which are the alphabet the clue is written in.
#   Motion:     it RISES, and one NOTCH per correct step on the way. Up = "the
#               world changed", the identity gate's own sentence.
#   Reads as:   "the answer is somewhere else in this building".

## How far the mass lifts per correct step, at four steps to a lock — the progress
## display, and the demand gate's calibration ladder laid on its side.
##
## THE NUMBER IS CAPPED BY THE PLAYER'S CAPSULE AND NOT CHOSEN FOR LOOKS. A gap a
## `CharacterBody3D` fits through is an open gate, so the whole partial rise has to
## stay well under the 2.0 m capsule; 1.2 m is that with a wide margin, and the
## three-quarters of it a player can actually be looking at is 0.9 m.
##
## ponytail: the mass IS the ladder. A separate stack of four lit bands beside each
## lock would be four more unbatched meshes per riddle for the same four bits, and
## the pads are drawn in front of the mass precisely so the thing you are opening is
## in your eye line. If a later riddle puts its lock out of sight of its gate, that
## is when the bands earn their nodes.
const RIDDLE_NOTCH: float = 1.2

## How hard the mass clunks on a wrong step, scaled by how far in you were — the
## demand gate's `_nudge_ratio` reaction, in the one direction a mass can move.
const RIDDLE_RATTLE: float = 0.22

## How far it travels once solved: ITS OWN HEIGHT, so the doorway is fully clear.
##
## Read off the mass rather than declared, because since phase 16 a mass is as tall
## as the storey it stands on (`plan_clear_height`) and a storey is not always 4.6 m.
## A travel written down separately would leave a lock on a taller floor three
## quarters open — solved, and still a wall.
static func riddle_travel(mass: MeshInstance3D) -> float:
	"""How far one riddle's mass lifts when solved: the height of the mass itself."""
	var box := mass.mesh as BoxMesh
	return 0.0 if box == null else box.size.y

## The receptacle pillar's calibration ladder. `DEMAND_BANDS` is the SCALE the
## player reads: lit bands are their current capability, the full stack is what the
## gate wants. Four is enough to see a shortfall at a glance and few enough to count
## without counting.
##
## WHERE the vault, its shutter and its pillar stand is the PLAN's to say since bead
## `godot-test1-dn8` — the `D` run bound to `GATE_DEMAND` and the plain-floor cell
## `gate_pad_cell()` picks out in front of it. `VAULT_X0`, `VAULT_Z`, `SHUTTER_X0`,
## `SHUTTER_X1`, `RECEPTACLE_X` and `RECEPTACLE_Z` were the keep's authored widths
## and went with the keep; `_demand_boxes()` reads the drawing instead.
const DEMAND_BANDS: int = 4

## WHAT THE DEMAND GATE DEMANDS, and why this number.
##
## Primm's Phase Step reaches `PRIMM_BLINK_DISTANCE` (6.0 m) unskilled and 20% more
## per rank of Long Step. 7.2 m is therefore EXACTLY one rank — the gate is a
## single skill point away for a player who has already found Primm, which makes it
## forecastable ("I know what fixes this") rather than merely refusing. A gate
## calibrated to the maxed 8.4 would be a wall wearing a number.
##
## Read through `player.phase_reach()`, which is the same expression `_ability_primm`
## blinks with — so the gate can never demand a distance the ability does not have.
const DEMAND_TARGET: float = 7.2

## Slack on the calibration comparison, in metres. NOT A FUDGE — a bug fix with a
## constant attached, and the reason it exists is worth the paragraph:
##
##   PRIMM_BLINK_DISTANCE * (1.0 + 0.20) == 7.199999999999999
##
## in IEEE 754, so a gate calibrated to "exactly one rank of Long Step" refused
## exactly one rank of Long Step, while printing "needs 7.2 m, reads 7.2 m" at
## `%.1f` — the single most confusing failure this feature could have. Caught by
## eye in the real game (2026-08-28), not by any structural assertion, which is why
## `tower_interior_selfcheck` now derives the one-rank reading from
## `Progression.SKILL_TREES` and asserts the gate opens for it.
##
## 1 cm is far below any rank step (each is 1.2 m) so it can never let a genuinely
## short reading through; it only makes the comparison mean what the number says.
const DEMAND_TOLERANCE: float = 0.01

## How far the secure mass rises when it opens, and how far the demand shutter
## sinks. Both are a full body-height of travel so the opening is unambiguous, and
## the mass's is enough to carry its foot clear of the shell parapet — the risen
## counterweight is visible from the yard, which is what makes it WORLD state
## rather than a door that quietly stopped being there.
const MASS_TRAVEL: float = 4.4
const SHUTTER_TRAVEL: float = 4.4

## Seconds a gate takes to finish moving. Long enough to watch, short enough that
## nobody waits on it.
const GATE_TIME: float = 1.6

## The partway reaction: how much of its travel the shutter gives an under-strength
## reading, as a fraction, scaled by how close that reading was. A player at 83% of
## the demand sees the slab drop 0.83 * 0.3 of the way and grind back — the shutter
## itself is a second, redundant readout of the same number the bands show.
const NUDGE_FRACTION: float = 0.3
const NUDGE_TIME: float = 1.4

# ============================================================================
# THE CELL BLOCK — phase 8's rooms, phase 16's storey
# ============================================================================
#
# THE BLOCK IS ROOFED, AND THAT IS THE CONSTRAINT EVERYTHING BELOW BENDS TO. It
# used to sit north of the entry hall under the keep's 4.2 m slab; it now sits on
# storey 10 under the shell's SEALED ROOF, with 4.0 m of clear air over it. The
# ceiling got 20 cm lower and the argument did not change at all:
#
#   FREE: the jump rule stops applying (a jump under a ceiling ends at the
#         ceiling), so walls here are sized for sightlines instead of for an apex.
#   FREE: it is dark, so the two light panels below are the whole art direction.
#   PAID: A ROOM-HEIGHT MASS CANNOT RISE IN A ROOM ITS OWN HEIGHT. The secure
#         door's counterweight rises and stays risen because it stands under open
#         sky; these four have nowhere to go but DOWN, so they sink and stay sunk.
#
# That is a real, deliberate weakening of the legibility language's "identity gates
# rise, demand gates sink" opposition, taken with eyes open because the geometry
# left no other move that is not a jump-gated ledge. The other three axes are
# untouched and they are the ones a player reads FIRST: violet against steel, a
# blank mass against a banded pillar, a pad you stand on against a receptacle you
# walk up to. Motion is the axis you only see once you have already been told the
# answer. The roof is sealed, so there will never be sky over this room.
#
# WHERE ITS GEOMETRY COMES FROM, and this is the phase-16 change: the walls, the
# four gate masses, their four pads and the crawl's lintel are all DRAWN, on
# `TowerPlans`' storey-10 grid, and built by the ordinary plan builder. What is
# left here is the handful of parts the plan format cannot express — a press that
# sweeps, four containment fields that recolour, one piece of authored staging, an
# operable pad and the scar's rubble — and every one of them takes its position
# from a plan lookup (`plan_room_rect` / `plan_gate_rect` / `plan_doorway_rect`)
# rather than from a constant of its own. `_spine_door_x`, `_cell_x` and the dozen
# hand-tuned spacings they were built from are GONE: the grid answers all of them.
#
# THE CAMERA, honestly: `CameraArm` is an 8.25 m `SpringArm3D` and nothing may
# write `camera.position`, so a room narrower than the arm collapses it — the
# courtyard's documented 8 m deferral. The move to the plan grid quietly fixed
# most of it: the corridor is 19 cells (36.9 m) long and the gallery the same, so
# the arm extends fully along either run. Facing into a 4-cell recess it still
# does not, and that is the same deferral, not a new one.

## The crawl press's lintel height, its stroke and its rhythm. The press is an
## `Area3D` hazard on a mesh that never becomes solid — a solid block driven by
## script shoves a `CharacterBody3D` through whatever is behind it, which is the
## same reason the rotor bars are hazards (see `_make_rotor`).
##
## IT IS A CHALLENGE AND MUST STAY ONE. `maintenance_crawl` is the route the
## custody scar leaves standing when it drops the block's wide doorway, so the
## softlock audit needs it passable by every hero with no rank at all. A press you
## time is; anything keyed on a name or a number is not.
##
## WHERE the duct is is no longer written here — it is the `D` run the plan draws
## for `maintenance_crawl`, and both the lintel over it and the press under it are
## derived from that run. The numbers below are the STROKE, which is behaviour.
##
## The lintel and the stroke are one pair of numbers, not two: the press's box is
## 0.7 m deep, so its top at rest is exactly the lintel's underside and its bottom
## at the end of the stroke is exactly the floor. Between them the gap has to clear
## a 2 m capsule or the crawl is impassable at every phase of its cycle — which is
## a challenge gate that is really a wall, and check 11 measures it. All three are
## measured from the storey's own walking surface, never from y = 0.
const CRAWL_LINTEL_Y: float = 2.8
const PRESS_TOP: float = 2.45
const PRESS_BOTTOM: float = 0.35
## Long enough to walk under without sprinting, short enough that waiting is dull.
const PRESS_PERIOD: float = 2.6

## How far a spine mass sinks: its own height and a little more, so its top ends up
## under the floor and there is no lip left in the doorway. A lip of ANY height is a
## wall in this engine, so "nearly flush" is not a finish, it is a bug.
const SPINE_TRAVEL: float = 4.6

## How deep a spine pad's TRIGGER is, in metres. The plate itself is one plan cell
## (1.94 m); the volume you step into is deeper than the paint, because you walk
## onto a pad from the corridor and the step that matters happens before your feet
## are centred on it.
const PAD_TRIGGER_DEPTH: float = 2.4

## THE VENT PURGE - the cell block's operable system, and the prison role's one
## outward-facing verb (bead godot-test1-3iy.10). A benched player stands on this
## pad and the pack around every TEAMMATE scatters: an immediate opening for the
## team outside, bought by somebody who cannot use it themselves.
##
## IT RIDES THE SHIPPED `flee` VERB AND ADDS NO PROTOCOL. `MpManager.request_croc_flee()`
## already relays to the master, the master already simulates the crocodiles around
## every member (its terrain keeps focus chunks there), and `is_fleeing` is already
## a bit in the crocodile sync's flag byte - so the effect reaches the teammate's
## screen through machinery that exists, one sync packet later. A new verb here
## would have been a fifth trust boundary for a thing four already do.
##
## IN THE GALLERY, at its +X end: the prisoner has to leave their own cell to reach
## it, which is the small act that makes operating it a decision. WHERE that is is
## read off the gallery's own plan cells (`purge_pad()`), never written down.
const PURGE_PAD_SIDE: float = 1.1

## How long the scattered pack stays scattered, and how far from each teammate the
## purge reaches. The duration is under Phoboman's own PHOBOMAN_FLEE_DURATION (10 s)
## because this is an assist and not an ability; the radius is the crocodile sync's
## own CROC_SYNC_RADIUS class, so it cannot ask the master to scare a crocodile the
## master would not be sending that peer anyway.
const PURGE_FLEE_SECONDS: float = 6.0
const PURGE_FLEE_RADIUS: float = 40.0

## Seconds between purges. Long enough that the system is a lever and not a
## hold-to-win button, and comfortably inside `MpManager`'s 4-per-second `flee`
## budget even with three teammates taking one packet each.
const PURGE_COOLDOWN: float = 20.0

# ============================================================================
# VISIBILITY GATING — the web frame budget's half of this bead
# ============================================================================

## Beyond this distance from the tower the whole interior stops drawing.
##
## The interior is INSTANCED once the player is within `TOWER_LOAD_RADIUS` (320 m)
## and never freed, so without this it would be 35 permanently-submitted meshes for
## the entire rest of the run. Godot's frustum culling does not help when you are
## looking AT the tower and there is no occlusion culling on the web renderer's
## `gl_compatibility` path — the walls do not hide what is behind them, they just
## draw first. 60 m is comfortably past the shell's own footprint (~19 m) and well
## inside the web build's 150 m render distance, so the transition is never on
## screen. COLLISION IS UNAFFECTED: `visible` is a draw flag, so nothing can fall
## through a hidden floor.
const DRAW_RADIUS: float = 60.0

## How far below `SLAB_Y` the player still counts as being on the lower floor. The
## slab's own thickness plus a margin, so standing on the ramp near the top does
## not flicker between storeys.
const FLOOR_HYSTERESIS: float = 0.8

## Hard cap on how many `MeshInstance3D`s the interior may actually BUILD — which,
## unlike the box budget, is the number the renderer charges for.
##
## THE TWO BUDGETS ARE NOT THE SAME NUMBER AND MUST NOT BE. Boxes are free once
## they are in a batch (see THE BATCH above): the plan may grow to 60 of them and
## still cost twelve draws. What this cap stops is boxes leaving the batch — every
## name added to `MOVING_PARTS` spends one, and sixty unbatched boxes is the
## 190-spike walk that made the batch necessary in the first place.
##
## RAISED FROM 14 TO 22 BY PHASE 8, and every one of the ten new nodes is a box
## that CANNOT be batched: four spine masses that travel, one press that sweeps,
## four cell frames that relight on liberation and one staging unit that
## disappears. The four spine pads, three piers, four dividers, five walls and two
## light panels are batched and therefore cost nothing.
##
## 22 IS THE EXACT COUNT, with no slack left, on purpose: the next part that wants
## its own node has to justify itself against this comment rather than fit under a
## rounding. (12 of it is the pre-phase-8 building, two of THOSE being the per-storey
## batches.)
##
## 23 SINCE PHASE 11, and here is that justification. The scar's rubble (`SCAR_BOX`)
## is invisible and non-solid in every world that has not survived the full-custody
## protocol and stone in every world that has, so it is the one box in the plan
## whose DRAW STATE is decided per save — which a merged batch cannot express
## without being rebuilt. One node, once, for the life of a run.
##
## 26 SINCE PHASE 14, and the three are the whole cost of the hand-planned storeys:
## one `Floor%dBatch` `MeshInstance3D` each, and nothing else. Not one plan box is
## in `MOVING_PARTS`, not one carries `spin`, and — deliberately — not one is
## painted a `GLOW_COLORS` colour, so a plan storey commits ONE surface and not two.
## THREE STOREYS OF 80 x 80 m COST THREE DRAWS: that is the claim this number is,
## and `_check_node_shape` is what stops the next author quietly spending it.
##
## 28 SINCE PHASE 15, and the two are the two riddle masses — the only riddle boxes
## that leave the batch, because they are the only ones that move. A lock's four
## coloured pads and its clue's four coloured marks are static plates and cost
## nothing at all, which is the whole reason the mass doubles as the progress
## display (see `RIDDLE_NOTCH`): the alternative, a lit band ladder beside every
## lock, would have been four more nodes per riddle for the same four bits.
## ONE DRAW PER RIDDLE is the claim, and it is what makes a floor of them
## affordable.
##
## 30 SINCE PHASE 16's FIRST TASK, and the two are storeys 6 and 7: one
## `Floor%dBatch` apiece and nothing else, exactly the phase-14 arithmetic. Neither
## floor puts a box in `MOVING_PARTS`, so the whole 6000 m2 of each is one draw.
##
## 34 SINCE THE LABYRINTH, and the four are exactly what the two maze storeys
## cost: one `Floor%dBatch` apiece, plus one mass per maze riddle — the same
## ONE DRAW PER RIDDLE the phase-15 arithmetic above claims, asked of a floor
## whose walls are a maze. The 450 and 431 walkable cells of those two storeys,
## and every wrong turn in them, are in the two batches and cost nothing more.
##
## 35 SINCE THE CELL BLOCK MOVED (phase 16), AND THE ONE IS THE STOREY, not the
## block. Every unbatched part of the block — four masses, the press, four
## containment fields, the staging unit and the scar's rubble — was already
## spending a slot on the ground floor and simply changed parent; what is new is
## `Floor9Batch`, storey 10's own merged mesh, holding its walls, its four gate
## pads, its lintel and its two light panels. Moving eleven nodes 46 m upwards
## costs nothing, which is the whole claim this number is making.
##
## Storey 10's batch is the FIRST plan storey to carry two surfaces rather than
## one: its gate pads and its light panels are `GLOW_COLORS`, so the matte and the
## emissive halves are both there — which retires the phase-14 claim above ("a plan
## storey commits ONE surface").
##
## THIS NUMBER COUNTS NODES, NOT DRAWS, and the two stopped being the same thing
## here. `merged_mesh` puts both halves in one `ArrayMesh` on one `MeshInstance3D`,
## so the node count is unchanged — but emissive is a MATERIAL property, so the two
## halves are two surfaces, and the engine submits one draw per surface (that is
## `merged_mesh`'s own "a storey costs two draw calls whether it is four boxes or
## forty"). Floors 0, 1 and 9 carry glow, so the interior's real draw count is
## nearer 38 than 35. The budget is still the useful guard — a storey that stopped
## batching costs a node per box, not a surface — but do not read it as a draw
## count. If draws are what you want to bound, that is `SURFACE_BUDGET` below —
## check 5 asserts both.
##
## 39 SINCE THE OFFICE DRESSING (bead godot-test1-0a5), AND ALL FOUR ARE THE JOKE.
## Every desk, chair, cabinet, plant, diploma and framed photograph in this
## building went into the storeys' EXISTING batch surfaces, so furnishing ten
## floors moved this number by exactly ZERO. That is the chunks' "one MultiMesh
## per chunk" applied to an office fit-out, and it is the reason the dressing is
## vertex-coloured boxes rather than the textured quads the bead offered.
##
## The four are the four hero portraits on the employee-of-the-month wall, which
## are the one thing in this building a vertex colour cannot say. A photograph
## needs a texture, a texture needs a material of its own, and a material is a
## draw — so they are four `QuadMesh` nodes on one storey wearing the hero HUD's
## own `Texture2D`. They are the WHOLE of the easter egg's cost: the frames round
## them and the brass plaques under them are batched boxes like everything else.
const DRAW_BUDGET: int = 39

# ============================================================================
# PALETTE — one material per colour, shared process-wide (see `_material`)
# ============================================================================
#
# Read the legibility block at the top of the file before changing any of these:
# the colours ARE the language, and a room that borrows the wrong one lies to the
# player about what it is.

## ORDINARY GEOMETRY, AND IT IS A BRIGHT OFF-WHITE ON PURPOSE (bead 99j). The
## sealed roof (shell phase 13) put the key light and the sky outside, so an
## interior painted the shell's grey stone rendered as black rooms — the owner's
## playtest note was "hq inside shouldn't be that black". The target is the Lumon
## severed floor: white walls and ceilings, evenly lit, no dark corners, uncanny
## because it is TOO clean. Every slab's UNDERSIDE is the ceiling of the storey
## below, so this one colour is walls AND ceilings; the floor is `COLOR_CARPET`
## via `top_color`, and the pale-wood skirting is `COLOR_WAINSCOT`.
const COLOR_STONE := Color(0.93, 0.93, 0.90)        # walls and ceilings
const COLOR_HAZARD := Color(0.86, 0.36, 0.12)       # anything that moves to hurt you
const COLOR_MECHANISM := Color(0.24, 0.27, 0.33)    # demand gate: cold steel
const COLOR_BAND_DARK := Color(0.13, 0.14, 0.16)    # an unlit calibration band
const COLOR_BAND_LIT := Color(1.00, 0.62, 0.12)     # a lit one — your reading
const COLOR_IDENTITY := Color(0.42, 0.20, 0.58)     # identity gate: the mass
const COLOR_IDENTITY_PAD := Color(0.72, 0.36, 1.00) # ...and the pad you stand on
const COLOR_CHECKPOINT := Color(0.16, 0.38, 0.30)   # checkpoint, not yet reached
const COLOR_CHECKPOINT_LIT := Color(0.32, 1.00, 0.58)
const COLOR_PANEL := Color(1.00, 0.95, 0.86)        # ceiling light panels

## THE FLOOR, and the only surface in the building that is not off-white: a
## desaturated mint that reads as carpet against the walls. Applied through a box's
## optional `top_color`, so a slab is ONE box whose top face is carpet and whose
## underside is still the ceiling of the storey below — the alternative was a
## second box per slab, i.e. more geometry and more `PLAN_BOX_BUDGET` for a colour.
const COLOR_CARPET := Color(0.44, 0.62, 0.52)
## The wainscot: pale wood, `WAINSCOT_HEIGHT` up every planned wall. It is what
## keeps a corridor of white walls readable at a glance — an all-white room under
## flat light has no horizontal line in it, so the corners disappear. Emitted by
## splitting the wall's prism in `_emit_box`, NOT as a second box: same vertex
## count either way, but no extra box, no extra collision shape and no budget.
const COLOR_WAINSCOT := Color(0.80, 0.71, 0.55)
## A SYSTEM YOU OPERATE — the fifth thing in the legibility language, and the only
## one whose effect is somewhere ELSE. Cold cyan, deliberately in neither family:
## it is not violet (a gate reads "bring the right hero" and this asks nobody's
## name) and it is not steel (a demand gate reads "come back stronger" and this
## measures nothing). `tower_selfcheck` is what enforces the distinction — a box
## painted a GATE colour must be claimed by a `TOWER_GRAPH` row, and a system that
## borrowed one would quietly enter the softlock audit as a passage.
const COLOR_SYSTEM := Color(0.20, 0.72, 0.78)       # an operable block system
## THE FIFTH WORD IN THE LANGUAGE, and it is a ROOM MARKER and not a gate: a cell's
## containment field, held red while somebody is in there and dead grey once they
## are not. Red is free — nothing else in this building is warm except the hazard
## orange, and a hazard is a moving bar. So "there is a person in that recess" is
## answerable from the far end of the gallery, which is the whole design of the
## wing (see THE ROUTE). `tower_selfcheck` claims every box wearing it for exactly
## one cell room, the way it claims the checkpoint's green.
const COLOR_CELL := Color(0.95, 0.24, 0.30)         # an OCCUPIED cell
const COLOR_CELL_FREED := Color(0.19, 0.21, 0.23)   # ...and the same field, shut down

## A SCAR: stone that was not there yesterday. Dark, brown-grey rubble — the same
## family as `COLOR_STONE` ("this is the building") but visibly dirtier, because a
## scar has to read as a CHANGE to a player who walked this doorway ten minutes
## ago and not as a wall that was always here. Deliberately not one of the three
## verb colours: a collapse is not a gate, asks nothing and can never be opened.
const COLOR_SCAR := Color(0.34, 0.30, 0.28)

## The riddle gate's mass, and the four colours its lock is spelled in. The mass is
## a cold indigo in NEITHER gate family on purpose — a player who has met the steel
## demand gate and the violet identity gate must not read this as either.
##
## The pad colours are the clue's alphabet: the same four, in the same order, are
## painted on the clue room's floor. They are deliberately outside `GLOW_COLORS`,
## like every other plan box, so a storey batch stays one surface.
const COLOR_RIDDLE := Color(0.16, 0.20, 0.44)
const COLOR_RIDDLE_PADS: Array[Color] = [
	Color(0.98, 0.72, 0.16),   # 1 — amber
	Color(0.24, 0.46, 0.92),   # 2 — blue
	Color(0.86, 0.24, 0.62),   # 3 — magenta
	Color(0.56, 0.82, 0.20),   # 4 — lime
]

## Which colours are EMISSIVE AND UNSHADED. There are no `Light3D`s anywhere in
## this building: a real light under the slab would cost a shadow pass on a
## renderer (`gl_compatibility`) that is the whole reason for the visibility gating
## above. A glowing box is a draw call that was happening anyway.
const GLOW_COLORS: Array[Color] = [
	COLOR_BAND_LIT, COLOR_IDENTITY_PAD, COLOR_CHECKPOINT_LIT, COLOR_PANEL,
	COLOR_CELL,
]

## HOW HARD EVERY INTERIOR SURFACE SELF-LIGHTS, and the whole of bead 99j's fix.
## The interior materials are `EMISSION_OP_MULTIPLY`, so a surface's emission is
## its OWN albedo times this — an off-white wall glows off-white, the carpet glows
## mint, and nothing needs a `Light3D` under a sealed roof. That is the same "a
## glowing box is a draw call that was happening anyway" trade `GLOW_COLORS` makes,
## applied to the matte surface as well, and it costs no draw call, no node and no
## shadow pass: it is one flag on two cached materials.
##
## A CALIBRATION KNOB, and the one number to turn if the look is wrong. Too high
## and the two open storeys blow out under the key light and bloom (the
## Environment's `glow_hdr_threshold` is 0.85); too low and the sealed storeys go
## back to reading black. 0.45 sits a sunlit off-white wall just under the bloom
## knee and a roofed one at a flat, even mid-bright — measured against nothing but
## the arithmetic, because a headless `gl_compatibility` process cannot screenshot.
##
## THE FOG IS NOT PART OF THE PROBLEM AND WAS CHECKED BEFORE ANY OF THIS WAS WRITTEN.
## `endless_terrain`'s fog is exponential at 0.005 (web) toward `FOG_COLOR`, a PALE
## warm grey — so the far end of an 80 m storey blends about a quarter of the way
## toward something brighter than the wall, not darker. It lightens the long
## corridors it reaches and there is nothing here to gate it out of. Nor does the
## per-floor draw gate (`_update_visibility`) darken anything: it hides whole
## storeys you are not on, and a hidden storey is not a dark one.
const INTERIOR_EMISSION: float = 0.45

## The wainscot band's height off the walking surface. Pure look; never collided
## with, never stood on.
const WAINSCOT_HEIGHT: float = 1.05

## AIR SIGHT (bead godot-test1-oht) — how opaque a wall is left while Windman's
## indoor ability is running. Not zero: the point is to READ the layout and spot a
## patrol through it, and a wall you cannot see at all is a room with no corners.
const XRAY_ALPHA: float = 0.30

## SURFACES, WHICH ARE DRAWS — the bound `DRAW_BUDGET` explicitly declines to be
## (read its last paragraphs: it counts NODES). `merged_mesh` welds a storey into at
## most three of them and the engine submits one draw per surface, so this is the
## number that moves when a batch stops merging or a fourth material sneaks into the
## building. Air Sight is what made it worth stating: pulling the walls onto their
## own surface so they can be swapped costs ONE surface per planned storey and
## nothing else — no node, no material per box, and no work at all while it is off.
##
## MEASURED AT 51 with ten storeys authored, of which the ten wall surfaces are the
## whole of what this bead added (it was 41). The slack over it is the same slack
## `DRAW_BUDGET` carries, and for the same reason: a moving part earns a mesh, and a
## mesh is at least one more draw.
const SURFACE_BUDGET: int = 54

## The ground storey's carpet layer. 2 cm of pure colour, non-solid, laid OVER the
## shell's `Yard` apron — see `_plan_slab` for why the ground floor is the one storey
## whose slab top face is not the surface you look at. Thin enough that it is a change
## of colour under your feet and never a lip: `CharacterBody3D` has no step-up, so
## anything solid you could trip on is a wall, and this is not solid at all.
const CARPET_THICK: float = 0.02

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
#     pad, a lock plate, a clue strip, a containment frame, the rotor's mechanism
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

## The two rooms that ARE their set piece end to end, and so are never dressed.
## Named as graph rooms and never as floor numbers — the same rule `plan_boxes`
## follows when it decides which storey draws the block. Everything else is kept
## out cell by cell by the footprint test, which needs no name.
const DRESS_SKIP_ROOMS: Array[String] = [BLOCK_ROOM, CHECKPOINT_ROOM]

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
				"color": COLOR_WAINSCOT, "solid": true},
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
				"color": COLOR_WAINSCOT, "solid": true},
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
				"color": COLOR_WAINSCOT, "solid": true},
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
				"color": COLOR_WAINSCOT},
			{"size": Vector3(0.56, 0.07, 0.07), "off": Vector3(0.0, 1.59, 0.40),
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
			{"size": Vector3(1.40, 0.44, 0.08), "off": Vector3(0.0, 0.44, 0.04),
				"color": COLOR_WAINSCOT},
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
# NOT IN THE LABYRINTH AND NOT IN THE BLOCK. `is_maze_floor()` keeps the signs off
# storeys 8 and 9 — the maze is meant to be crossed by its landmarks, and a corridor
# sign in there is the pathfinding the whole design note refused.

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
				"color": COLOR_WAINSCOT},
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
				"color": COLOR_WAINSCOT},
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
# THE EMPLOYEE-OF-THE-MONTH WALL — the joke
# ============================================================================
#
# Four framed hero portraits on one office wall, captioned. It is the ONLY
# textured thing in this building, and the textures are the very files the hero
# HUD draws (`res://assets/portraits/<hero>.png`, bead #134): `load()` on a
# `res://` path hands back the process-wide cached `Texture2D`, so hanging them
# here is a REFERENCE and never a second copy of the art.
#
# Four quads, four cached materials, four draw calls, on one storey — and that is
# the whole of what `DRAW_BUDGET` moved for. The frames and the plaques under
# them are ordinary batched boxes and cost nothing.

## Which room the wall is in — a graph room, looked up like everything else here,
## so moving `outer_hall` in the ASCII moves the portraits with it. The outer hall
## is the first room a player walks into off the entry hall, which is the point of
## a joke nobody is meant to have to hunt for.
const EGG_ROOM: String = "outer_hall"

## How high off the walking surface the bottom of a portrait frame sits.
const EGG_FRAME_Y: float = 1.30
const EGG_FRAME_SIZE := Vector2(0.92, 1.12)   # the wooden frame, along-wall x up

## ...and the picture inside it, WHICH IS SQUARE BECAUSE THE SOURCE IS. The four
## portraits ship at 130 x 130 and a `QuadMesh` maps the whole texture across
## whatever surface it is given, so a 0.76 x 0.96 quad stretches every hero 26%
## taller — no error, no warning, just four subtly wrong faces (codex review,
## 2026-08-31). The frame stays TALL and the difference is the mount the picture is
## hung on, which is what a framed photograph actually looks like.
const EGG_PORTRAIT_SIZE := Vector2(0.78, 0.78)

## How far under the frame's top edge the picture hangs. The rest of the frame's
## height falls below it as mount, over the plaque.
const EGG_PORTRAIT_INSET: float = 0.07

# ============================================================================
# GATE IDS — the strings that go in the opened set
# ============================================================================
#
# Stable, lowercase, prefixed by the tower. They are persisted verbatim by phase 5,
# so RENAMING ONE IS A SAVE MIGRATION. Add, never rename.
#
# TAKEN FROM `tower_graph.gd`, NOT RESTATED. That file is the tower's topology as
# data and the thing `tower_selfcheck.gd` walks to prove the campaign cannot
# softlock; an audit of a graph whose gate ids had drifted from the building's
# would certify the wrong tower. One arrow, one direction — the graph is pure data
# and knows nothing about this file.

const GATE_DEMAND: String = TowerGraph.GATE_DEMAND
const GATE_IDENTITY: String = TowerGraph.GATE_IDENTITY
const GATE_CHECKPOINT: String = TowerGraph.GATE_CHECKPOINT

## THE FOUR RESCUE SPINES, in door order west to east — the gate id is the graph's
## own key and the box names it claims in `parts`.
##
## THE HERO IS NOT HERE, deliberately: `TowerGraph.identity_of()` answers who each
## door opens for, so the four names are written down once in this repository and a
## door cannot ask for a hero the softlock audit thinks it asks for somebody else.
## The gate id doubles as the string that goes in the opened set, exactly as the
## three constants above do.
##
## THE BOX NAMES ARE THE PLAN BUILDER'S SINCE PHASE 16 — `S<floor>PlanGateMass_<id>`
## and `...GatePad_<id>`, the same names every other gate in the building carries,
## because the four doors are `D` runs on storey 10's grid now and not hand-placed
## boxes. Box names are NOT persisted (only gate ids are), so the rename was free;
## the floor number in them is, and `tower_selfcheck` binds every one of these
## strings back to a box `all_boxes()` really builds.
const SPINE_DOORS: Array[Dictionary] = [
	{"gate": "updraft_shaft", "mass": "S9PlanGateMass_updraft_shaft",
		"pad": "S9PlanGatePad_updraft_shaft"},
	{"gate": "phase_grate", "mass": "S9PlanGateMass_phase_grate",
		"pad": "S9PlanGatePad_phase_grate"},
	{"gate": "collapsed_slab", "mass": "S9PlanGateMass_collapsed_slab",
		"pad": "S9PlanGatePad_collapsed_slab"},
	{"gate": "hound_den", "mass": "S9PlanGateMass_hound_den",
		"pad": "S9PlanGatePad_hound_den"},
]

## What the AUTHORED FIRST RESCUE writes into the tower's opened set once it has
## happened. Not a passage — the cell doors are ungated, which is the point — but
## story progress, and it belongs in the same monotone set for the same reason a
## checkpoint does: it is a thing the building remembers about you.
##
## IT IS THE ONLY LIBERATION STATE THAT PERSISTS, and that is a deliberate split.
## Systemic captivity (phase 9) is per-run: heroes are taken and freed over and
## over inside one run, and a saved "primm is free" would be a lie the moment he
## was taken again. What survives a relaunch is the single fact the staging depends
## on — the first rescue happened, so the containment unit is gone for good.
## The one box the full-custody scar builds: the rubble that fills the service
## doorway when `TowerGraph.SCAR_CUSTODY` is in the opened set. Named here because
## three places need the same string — the box table, `_remember()` and the build
## loop's shape capture.
const SCAR_BOX: String = "BlockDoorCollapse"

const RESCUE_DONE: String = "tower_rescue_primm"

## Who the authored first rescue is about. Read from the graph's cell rooms rather
## than trusted: `AUTHORED_CAPTIVE` must be a hero with a cell, which check 1
## already guarantees for all four.
const AUTHORED_CAPTIVE: String = "primm"

# ============================================================================
# THE BATCH — why most of this building is two meshes
# ============================================================================
#
# MEASURED, and it is the whole reason this section exists. Built as one
# `MeshInstance3D` per box, the interior added 67 draw calls over the bare shell
# and took a walk through the entry hall from 26 frame-spikes per 600 to 190
# (perf_overlay's own SPIKE log, desktop, 1280x720, 2026-08-28). Draw calls are
# what the web `gl_compatibility` target counts, so that is a regression the bead's
# acceptance forbids — and it is the same lesson `create_box()` learned for chunk
# content, arriving one building later.
#
# So the STATIC geometry of each storey is merged into ONE `ArrayMesh` carrying at
# most two surfaces: the matte one and the emissive one. Colour rides in the
# VERTEX COLOURS (`vertex_color_use_as_albedo`), which is what lets a dozen boxes
# of a dozen different colours share a surface at all. It is the same trick
# `predator_parts.py` uses for the enemy models and the same trick a chunk's
# MultiMesh uses, minus the MultiMesh — this is authored geometry and must not go
# near `block_batch` (CLAUDE.md).
#
# WHAT IS DELIBERATELY NOT BATCHED, because a merged mesh cannot move or recolour
# one of its own boxes without being rebuilt:
#
#   * the two gates, which travel;
#   * the four calibration bands, which relight as often as a hero switches;
#   * the checkpoint's plate and post, which relight once;
#   * the two rotor bars, which hang off spinning pivots of their own.
#
# Ten nodes, and every one of them earns it. Anything you add that just SITS there
# belongs in the batch — leave it out of this set and it is batched for free.
const MOVING_PARTS: Array[String] = [
	"DemandShutter",
	"Band1", "Band2", "Band3", "Band4",
	"CheckpointPlate", "CheckpointPost",
	# THE CELL BLOCK IS NOT IN THIS LIST, and that is phase 16's doing rather than an
	# omission: every part of it is a PLAN box now, and a plan box declares itself
	# with `dynamic` because it is named by a builder and cannot be in a const list.
	# The count is unchanged — four masses that travel, one press that sweeps, four
	# cell frames that relight the moment a captive walks out, the staging unit that
	# is never seen again after the first rescue, and phase 11's scar — they simply
	# say so themselves. `is_own_node()` is the one place the two spellings meet.
]

# ============================================================================
# THE GUARDS — the population half of "structure persists, population resets"
# ============================================================================
#
# THREE KINDS OF TOWER STATE, THREE HOMES, AND THIS IS THE THIRD:
#
#   OPENED GATES (phase 5, `TowerShell.opened`)   — monotone union set, written
#     through to `BestRunStore` on the opening. A gate you opened stays open
#     across a relaunch, because opening it was earned.
#   THE CAPTIVE SET (phase 9, `player_controller.captive_heroes`)  — deliberately
#     NOT in that set, because it is non-monotone: heroes are taken and freed over
#     and over inside one run, so a union merge would be a lie. Per-run world
#     state, mirrored into `_captives` here.
#   THE GUARDS (this phase)  — NO HOME AT ALL. They are never written anywhere,
#     by anybody, and the whole "population resets on re-entry" ruling is
#     implemented by that absence plus `reset_guards()` below. There is no guard
#     field to forget to clear, no id to leak into the opened set, and nothing for
#     a save to disagree with: cross the doorway and every guard is a fresh body
#     standing on its authored post.
#
# WHY THEY ARE PARENTED HERE AND NOT CHUNK-SPAWNED: a storey is flat within
# itself, so the gravity settle a SPECIES row expects holds locally on the slab
# exactly as it does on the ground floor — but only if the guard belongs to the
# building rather than to a chunk that unloads out from under it. Same reason the
# shell is parented to the terrain manager and a herd to the fauna manager.

## The guard scene and the SPECIES row it must resolve to. Read by
## `enemy_spawn_selfcheck` as the FOURTH door into the world (after BIOME_SPECIES,
## BIOME_BOSS and endless_terrain's hunter spawner) — a guard belongs to no biome
## and no road station, so a reachability check over the dispatch maps alone would
## report a shipped, working predator as one nothing can spawn.
##
## A PATH AND A LAZY `load()`, NOT A `preload()` CONST, and that is a cold-cache
## bug rather than a preference. `endless_terrain.gd` preloads BOTH the crocodile
## scene and `tower_interior.tscn`, so a `preload` here closes a diamond onto
## `piglet_crocodile_ai.gd`: on a cold `.godot/` the AI script is still mid-load
## when this scene's `[ext_resource]` is resolved, and the engine answers
## "referenced non-existent resource" — a parse error that leaves every guard scene
## in the process unloadable while a warm cache passes. It cost CI run 33231844780
## to find, which is exactly the kind of thing a warm working copy cannot show you.
## Resolved once per process by `guard_scene()` below; `ResourceLoader` caches the
## rest.
const GUARD_SCENE_PATH: String = "res://scenes/characters/tower_guard.tscn"
const GUARD_SPECIES: String = "tower_guard"

## The resolved scene, once per process. `static` rather than per-instance for the
## same reason `_materials` is: there is one tower, but a self-check builds a dozen.
static var _guard_scene: PackedScene = null

static func guard_scene() -> PackedScene:
	"""The guard scene, loaded on first use. Null only if the file is missing."""
	if _guard_scene == null:
		_guard_scene = load(GUARD_SCENE_PATH) as PackedScene
	return _guard_scene

## How far above its post a guard is dropped in. Small on purpose: every storey is
## flat, so there is nothing to clear — this is only enough that the body starts
## the frame above the floor and settles onto it rather than starting inside it.
const GUARD_SPAWN_LIFT: float = 0.4

## ============================================================================
## THE DENSITY RULE — one guard per storey, and it is an owner ruling
## ============================================================================
##
## OWNER, 2026-08-30: "hunters can be one per storey in the HQ." That supersedes
## the earlier "one per three rooms" band and it is the whole population policy of
## this building: AT MOST ONE body per storey, zero on a storey whose plan draws
## no post. Ten storeys, nine posts (the labyrinth on floor 8 has no corridor long
## enough to patrol and so has none), of which the LOD manager has at most the
## player's own storey and its neighbours awake at any moment.
##
## WHY SO FEW, stated once so the next retune does not quietly walk it back: this
## building is a STEALTH problem, not a chase. Two guards on one floor means one
## of them sees you while you are backing out of the other's cone, and the answer
## to a room stops being "watch it, time it, walk past it" and becomes "run". The
## rescue on storey 10 is the sharpest case and the reason the ruling exists.
##
## ASSERTED FROM THE BUILT POPULATION, never from this table: check 12 of
## `tower_interior_selfcheck` counts the BODIES under `Guards` per storey. A
## derived table that started emitting two posts for one floor, or a plan that
## grew a second `G`, is a bug this const cannot see and that count can.
const GUARDS_PER_STOREY_MAX: int = 1

## EVERY POST IN THIS BUILDING IS A `G` ON A FLOOR PLAN, and since bead
## `godot-test1-dn8` there is no exception. The keep's two hand-authored rows —
## `Courtyard` and `Upper`, the ground floor's one junction and the approach to the
## identity gate — are two characters on storeys 1 and 2 now, because those two
## floors are `TowerPlans` rows like every other. `guard_posts_table()` is the whole
## population.
##
## NONE OF THEM CAN BLOCK A ROUTE, which is what keeps the softlock audit
## (`tower_selfcheck`) true with guards in the building: the player is collision
## mask 1 and walks THROUGH a predator (CLAUDE.md), so a guard standing in a
## doorway is a threat and never a wall. That is also why a guard needs no entry in
## `TowerGraph` — it gates nothing.
##
## `patrol_center` / `patrol_half` is the box `set_confinement()` pins the guard
## inside — the leash that has existed since the elevated-platform guards and that
## is the whole of "patrols, spots and chases WITHIN ITS FLOOR". The checkpoint's
## safe haven used to be `Upper`'s hand-tuned `patrol_half` promising to stop short
## of the partition; it is GEOMETRY now, because `_plan_guard_post` measures a beat
## as the run of plain `.` cells and a `D` cell is not one. A guard that has seen
## you standing on the plate still cannot follow you through the door, and the
## knockback below therefore cannot drop you into a re-bite loop.

## How far, in whole plan cells, a derived patrol may run from its post along the
## corridor. Three cells is 5.82 m — a beat you can watch a guard walk out and
## back, and short enough that its 9 m cone sweeps one length of corridor rather
## than a whole ring. The corridor is usually longer than this; the cap is what
## stops a ring-corridor post becoming a 35 m march nobody can time.
const GUARD_PATROL_MAX_CELLS: int = 3

## Half the patrol box ACROSS the corridor. Three quarters of a cell: wide enough
## to clear `piglet_crocodile_ai`'s CONFINE_MARGIN (0.9 m) with room to steer in,
## narrow enough that the box stays in the lane its post stands in and the guard
## paces the corridor rather than wandering the floor.
const GUARD_PATROL_LANE_HALF: float = TowerPlans.PLAN_CELL * 0.75

## The derived table, built once per process. `TowerPlans.STOREYS` is a const, so
## the answer cannot change within a run.
static var _guard_table_cache: Array[Dictionary] = []


static func guard_posts_table() -> Array[Dictionary]:
	"""
	Every post in the building: one per storey that draws a `G`, and nothing else.

	@return: rows shaped `{name, post, patrol_center, patrol_half}` — what
	        `reset_guards()` stands a body up from and what `set_confinement()`
	        leashes it inside.

	THE PLAN IS THE MAP, AND SINCE BEAD `godot-test1-dn8` IT IS THE WHOLE MAP.
	Phase 14 parsed and validated `G` and built nothing from it, precisely so
	phase 17 would be a reader and not a format change; that phase still had to
	`append_array` two hand-authored rows in front of this loop, because the keep's
	two storeys had no grid to read a `G` out of. They have one now, so the loop is
	the function.

	DERIVED, NEVER PERSISTED. Structure persists (the opened set); population does
	not — `reset_guards()` rebuilds from this table on every crossing of the
	doorway, exactly as it did from the const.
	"""
	if not _guard_table_cache.is_empty():
		return _guard_table_cache
	var out: Array[Dictionary] = []
	for floor_index: int in TowerPlans.floors():
		var derived := _plan_guard_post(floor_index)
		if not derived.is_empty():
			out.append(derived)
	_guard_table_cache = out
	return out


static func _plan_guard_post(floor_index: int) -> Dictionary:
	"""
	One storey's post, read off its `G` cell, or `{}` when it draws none.

	@param floor_index: An index into `FLOOR_Y`.

	The post is the cell; the PATROL is the run of corridor floor around it. Both
	axes are measured symmetrically — the shorter side of each wins, so the box is
	centred on the post and a guard never walks further one way than the other —
	and the longer of the two becomes the patrol axis. That is the whole of "a
	patrol along the corridor": the corridor IS the long run of `.` cells, so
	nothing has to say which way it goes.

	THE FIRST `G` WINS if a storey somehow draws two. The one-per-storey ruling is
	enforced where it can actually be seen — on the built population, in check 12 —
	rather than by this function silently picking one and hiding the second.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return {}
	var rows: Array = plan["rows"]
	var cell := Vector2i(-1, -1)
	for r: int in rows.size():
		var line := String(rows[r])
		var c := line.find(TowerPlans.POST_CHAR)
		if c >= 0:
			cell = Vector2i(c, r)
			break
	if cell.x < 0:
		return {}
	var along_x: int = mini(_floor_run(rows, cell, Vector2i(1, 0)),
			_floor_run(rows, cell, Vector2i(-1, 0)))
	var along_z: int = mini(_floor_run(rows, cell, Vector2i(0, 1)),
			_floor_run(rows, cell, Vector2i(0, -1)))
	var run: int = mini(maxi(along_x, along_z), GUARD_PATROL_MAX_CELLS)
	var reach: float = float(run) * TowerPlans.PLAN_CELL
	var half := (Vector2(reach, GUARD_PATROL_LANE_HALF) if along_x >= along_z
			else Vector2(GUARD_PATROL_LANE_HALF, reach))
	var at := Vector3(_grid_x(float(cell.x) + 0.5), FLOOR_Y[floor_index],
			_grid_z(float(cell.y) + 0.5))
	return {
		"name": "Floor%d" % floor_index,
		"post": at,
		"patrol_center": at,
		"patrol_half": half,
	}


static func _floor_run(rows: Array, from: Vector2i, step: Vector2i) -> int:
	"""How many unbroken `.` cells lie beyond `from` in direction `step`."""
	var n := 0
	var at := from + step
	while at.y >= 0 and at.y < rows.size():
		var line := String(rows[at.y])
		if at.x < 0 or at.x >= line.length() or line[at.x] != TowerPlans.FLOOR_CHAR:
			break
		n += 1
		at += step
	return n


# ============================================================================
# STATE
# ============================================================================

## The moving parts, held by reference because they are the only nodes in the
## building whose transform ever changes after `_ready()`. Mesh and collision shape
## are moved TOGETHER — a gate that opened visually and stayed solid is the worst
## bug this file could have.
var _shutter_mesh: MeshInstance3D = null
var _shutter_shape: CollisionShape3D = null
var _mass_mesh: MeshInstance3D = null
var _mass_shape: CollisionShape3D = null
var _band_meshes: Array[MeshInstance3D] = []
var _checkpoint_meshes: Array[MeshInstance3D] = []
var _label: Label3D = null
var _spine_label: Label3D = null
var _cell_label: Label3D = null

## The two rotor pivots. The bars and their hazard volumes are children, so one
## `rotation.y` per pivot animates both.
var _rotors: Array[Node3D] = []

## Per-floor mesh containers, index 0 = ground. `_update_visibility` shows floor
## `n` +/- 1 and hides the rest.
var _floors: Array[Node3D] = []

## AIR SIGHT'S SWAP LIST (bead godot-test1-oht): `[batch mesh, surface index]` for
## every WALL surface in the building, resolved once in `_ready()` by material
## identity. Walls and nothing else — the floor slabs, the ceilings and the gate set
## pieces live on other surfaces or on nodes of their own, so they cannot be reached
## from here however the ability is driven. `set_xray()` writes a surface override
## down this list and clears it again; while the ability is off the list is not read
## at all and the building renders exactly as it did before this bead.
var _wall_surfaces: Array[Array] = []

## Whether the walls are currently rendering translucent. Read by the self-check and
## by nothing in the game — the player's ability owns the timer.
var _xray_on: bool = false

## Progress of each gate's open animation, 0 = shut, 1 = fully open. Persisted only
## as the boolean "is this id in the opened set"; this is the tween.
var _shutter_open: float = 0.0
var _mass_open: float = 0.0

## The block's four spine doors, keyed by gate id: the mass, its collision shape,
## how far it has sunk (0 = shut, 1 = fully open) and whether the local player is
## standing on its pad. FOUR PARALLEL DICTIONARIES AND NOT FOUR FIELDS EACH,
## because every one of them is read in a loop over `SPINE_DOORS` and never by
## name — a fifth spine would be a row in that table and nothing else.
var _spine_meshes: Dictionary = {}
var _spine_shapes: Dictionary = {}
var _spine_open: Dictionary = {}
var _on_spine_pad: Dictionary = {}

## The crawl press and its clock. The clock is the animation's only state — the
## press has no open/shut, it just runs, which is what makes it a challenge.
## The riddles, keyed by gate id (phase 15). `_riddle_step` is how far into the
## sequence the player is and is the ONLY per-lock state that is not derived; it is
## deliberately not persisted, because a half-entered combination is not a thing the
## building remembers about you — the SOLVE is, and that rides the opened set.
var _riddle_meshes: Dictionary = {}
var _riddle_shapes: Dictionary = {}
var _riddle_open: Dictionary = {}     # gate id -> 0..1 tween of the full travel
var _riddle_step: Dictionary = {}     # gate id -> steps entered correctly
var _riddle_on_pad: Dictionary = {}   # gate id -> the digit under the player, 0 none
var _riddle_last: Dictionary = {}     # gate id -> the digit already acted on
var _riddle_nudge: Dictionary = {}    # gate id -> 1..0 clunk, on a wrong step
var _riddle_ratio: Dictionary = {}    # gate id -> how far in that wrong step was
var _gate_rest: Dictionary = {}       # gate id -> its mass's y with nothing entered

var _press: MeshInstance3D = null
var _press_clock: float = 0.0
## The storey the press stands on, so `press_y()` stays a stroke and not a height.
var _press_base: float = 0.0

## The four containment frames, keyed by HERO, plus the authored staging unit.
var _cell_frames: Dictionary = {}

## The visual-only hero bodies in occupied cells, keyed by hero name. These are
## deliberately separate from the containment frames: a captive is per-run
## population, so its model is created by the same `_refresh_cells()` seam that
## recolours the frame and is freed when the captive leaves. A body lives under
## its storey's floor container, which keeps it inside the interior lifecycle.
var _cell_bodies: Dictionary = {}

## Character scenes are the player's authored roster, but these instances are
## pictures rather than players. The remote-avatar precedent is the contract:
## no group, no CollisionObject3D and no per-frame animation.
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")
const CAPTIVE_BODY_PREFIX: String = "CaptiveBody_"

## THE BODY STANDING ON THE VENT-PURGE PAD, and how long until it can fire again.
##
## The BODY and not a boolean, because eligibility has to be re-asked every frame:
## the prison role ends where the player is standing (a teammate frees your hero, a
## lobby grant lands), and a latch taken on entry would leave a now-free player
## working the prisoners' system until they happened to step off. Polled like the
## spine pads - see `_tick_spine_pads()`.
var _purge_body: Node3D = null
var _purge_cooldown: float = 0.0
var _containment: MeshInstance3D = null

## The scar's rubble and its collision shape. Hidden and non-solid until the world
## has taken the scar; both move together, for the same reason a gate's mesh and
## shape do — rubble you can see and walk through is worse than no rubble.
var _scar_slab: MeshInstance3D = null
var _scar_shape: CollisionShape3D = null

## THE SCENE'S ONE AUTHORED CHANGE (phase 11): spine gate ids whose door has been
## re-shut for the full-custody break-out, whatever the opened set says.
##
## A SET AND NOT A BOOLEAN, because the scene is won one door at a time: standing
## on a pad as the right hero erases that id and the ordinary tween takes over, so
## the break-out is exactly the block's own lesson replayed under a clock. Empty
## whenever the protocol is not running, and NEVER PERSISTED — the guards' home
## (see the block above `GUARD_SCENE_PATH`): raised containment is population, not
## structure, and "it lifts when the scene ends" is implemented by not saving it.
var _lockdown: Dictionary = {}

## WHO IS IN THE CELLS RIGHT NOW, as a set of hero names.
##
## PER-RUN AND DELIBERATELY NOT PERSISTED: phase 9 takes and frees heroes over and
## over inside one run, so a saved captive set would be stale the moment it was
## written. The single fact that DOES survive a relaunch is `RESCUE_DONE` — the
## authored first rescue happened — and it is what seeds this set on build.
##
## A MIRROR, NOT THE RECORD (phase 9). Systemic capture happens out in the field,
## where this building is usually not streamed in at all, so the PLAYER owns the
## set and this node tracks it from both ends: `set_captive()` when a grab lands
## while the tower is loaded, and `_apply_opened()`'s re-seed when a tower is built
## after one. Those two plus `_liberate()` are the only writers.
var _captives: Dictionary = {}

## The partway reaction's clock, counting 0 -> 1 over NUDGE_TIME. Zero when idle.
var _nudge: float = 0.0
var _nudge_ratio: float = 0.0

## True once the demand gate has explained itself. ONE TIME, EVER, per run: the
## explanation is what turns a refusal into a diagnosis, and a line that reappears
## every time you walk past stops being read.
var _explained: bool = false

## How many calibration bands are currently lit. -1 means "not decided yet", so the
## first `_update_bands()` always writes even when the answer is zero.
var _lit_bands: int = -1

## Which pads currently have the local player standing on them. Tracked by
## `Area3D` signals rather than polled overlaps, and re-read every frame against
## the CURRENT hero — which is the whole identity-gate contract: it keys on who is
## standing there, not on who walked in.
var _on_demand_pad: bool = false
var _on_identity_pad: bool = false

## Cached local player. Revalidated every frame — a respawn does not free it, but a
## self-check running without one must not crash.
var _player: Node3D = null

## The container every guard is parented to. One node, so "reset the population"
## is one `queue_free()` and one fresh `Node3D` — there is no per-guard
## bookkeeping to keep in step and nothing to leak if a reset lands mid-chase.
## Held rather than looked up by name because a queued-free node keeps its name
## until the frame ends, and a rebuild in the same frame would otherwise collide
## with the corpse and be silently renamed by the engine.
var _guards: Node3D = null

## Albedo colour -> the one material of that colour, process-wide. Same contract
## and same reason as `TowerShell._materials`: never a material per instance.
static var _materials: Dictionary = {}

## Floor index -> that storey's built boxes. `plan_boxes()` walks 1600 cells and is
## called many times per self-check run (`all_boxes()` is the plan's single source
## the way `boxes()` is, so every check asks for it); the plan is a `const` and can
## never change at runtime, so building it once is free correctness.
static var _plan_cache: Dictionary = {}

## Hero name -> the one material carrying that hero's portrait. Its own cache
## rather than `_materials` because that one is keyed by COLOUR, and a portrait
## has no colour — see `portrait_material()`.
static var _portrait_materials: Dictionary = {}

## The same trick one storey down, and here it is not an optimization but a fix:
## `block_min()` / `block_max()` are read from `player_controller._physics_process`
## every frame a benched player is confined, and each one used to re-scan the whole
## 40 x 40 grid eight times over (`block_floor()`) plus five room lookups. They were
## literals before the block moved to storey 10; deriving them from the plan is the
## right call, recomputing them 60 times a second is not. Both are pure functions of
## `const` data, so one lazy fill is the whole of it.
static var _block_floor_cache: int = -2       # -2 = not asked yet; -1 = no block
static var _block_bounds_cache: Variant = null
## ...and the labyrinth's storeys, filled once by `is_maze_floor()`. null = not
## asked yet; the filled value is an `Array[int]` of floor indices.
static var _maze_floors_cache: Variant = null


static func _deck_box(deck_name: String, foot: Vector2, head: Vector2, z: float,
		width: float, floor_index: int) -> Dictionary:
	"""
	A ramp deck as a rotated box whose TOP FACE passes exactly through both of its
	two end points.

	@param foot: The low end, in the XY plane (x metres, y metres).
	@param head: The high end, same plane.
	@param z: The lane's centre line.
	@param width: The lane's width.
	@param floor_index: The storey the deck belongs to for visibility gating.
	@return: One `boxes()` entry, carrying a `rot`.

	ONE COPY OF THE ARITHMETIC, shared by the phase-3 keep ramp and every
	hand-planned storey's ramp, because the flushness is the whole point and a
	second copy is a second chance to get it wrong: the box is placed by its top
	face and its centre derived — offset half a thickness along the deck's own
	NORMAL, not straight down, which is the mistake that leaves a 12 cm step at the
	top. A step of ANY height is a wall in this engine.

	EVERY RAMP IN THIS BUILDING RUNS ALONG X, and the endpoints are ordered so that
	the run is positive. That is not tidiness: `rot.z` beyond a quarter turn puts
	the box's local +Y (the face we just placed) pointing DOWNWARDS, and the offset
	silently lands the walkable surface a thickness too high. Everything that
	reasons about these decks — `_ramp_underside_at`, check 1 and check 3 — reasons
	in the XY plane about `rot.z` for the same reason.
	"""
	var low := foot
	var high := head
	if high.x < low.x:
		var swap := low
		low = high
		high = swap
	var run := high.x - low.x
	var rise := high.y - low.y
	var length := Vector2(run, rise).length()
	var theta := atan2(rise, run)
	# Midpoint of the deck, and the deck's own normal.
	var deck_mid := (low + high) * 0.5
	var normal := Vector2(-sin(theta), cos(theta))
	var centre := deck_mid - normal * (RAMP_THICK * 0.5)
	return {
		"name": deck_name,
		"pos": Vector3(centre.x, centre.y, z),
		"size": Vector3(length, RAMP_THICK, width),
		"rot": Vector3(0.0, 0.0, theta),
		"color": COLOR_STONE, "collide": true, "floor": floor_index,
	}


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
	out.append_array(_plan_gates(plan))
	# ...and the hand-built parts, each guarded by a ROOM OR GATE LOOKUP and never by
	# a floor number. That is the rule the cell block has followed since phase 16 and
	# the reason it could change storeys without a number following it; bead
	# `godot-test1-dn8` brought the phase-3 keep's three set pieces under it when the
	# ground floor and the mezzanine became plan rows like every other. Move the `D`
	# run or the room's letters in the ASCII and the mechanism follows.
	if plan_gate_rect(floor_index, "rotor_gate").size != Vector2i.ZERO:
		out.append_array(_rotor_boxes(plan))
	if plan_gate_rect(floor_index, GATE_DEMAND).size != Vector2i.ZERO:
		out.append_array(_demand_boxes(plan))
	if plan_room_rect(floor_index, CHECKPOINT_ROOM).size != Vector2i.ZERO:
		out.append_array(_checkpoint_boxes(plan))
	if plan_room_rect(floor_index, BLOCK_ROOM).size != Vector2i.ZERO:
		out.append_array(_block_boxes(plan))
	# THE DRESSING GOES LAST, AND THAT ORDER IS THE WHOLE OF ITS SAFETY. Every
	# candidate cell is tested against everything above — the walls, the ramp, the
	# pads, the lock plates, the gate masses and each hand-built set piece — so a
	# desk can never land in a mechanism, and a set piece added tomorrow keeps it
	# out on the day it is drawn without a name being written down anywhere.
	out.append_array(_egg_boxes(plan))
	out.append_array(_plan_dressing(plan, out.slice(floor_boxes.size())))
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
	return _deck_box("%sRamp" % _plan_prefix(floor_index), foot, head, z, width,
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
			"name": "%sSlab%d" % [_plan_prefix(floor_index), i],
			"pos": Vector3((x0 + x1) * 0.5, top - SLAB_THICK * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, SLAB_THICK, z1 - z0),
			"color": COLOR_STONE, "collide": true, "floor": floor_index,
			# The face you walk on is carpet; the underside is the ceiling of the
			# storey below and stays off-white with the walls. One box, two colours —
			# see `_emit_box`.
			"top_color": COLOR_CARPET,
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
			"name": "%sCarpet" % _plan_prefix(floor_index),
			"pos": Vector3((carpet_x1 - TowerPlans.PLAN_HALF) * 0.5,
					TowerShell.YARD_LIFT + CARPET_THICK * 0.5, 0.0),
			"size": Vector3(carpet_x1 + TowerPlans.PLAN_HALF, CARPET_THICK,
					2.0 * TowerPlans.PLAN_HALF),
			"color": COLOR_CARPET, "collide": false, "floor": floor_index,
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
			"name": "%sWall%d" % [_plan_prefix(floor_index), i],
			"pos": Vector3((x0 + x1) * 0.5, bottom + height * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, height, z1 - z0),
			"color": COLOR_STONE, "collide": true, "floor": floor_index,
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

	# ponytail: geometry only, and still is. Phase 17 brought the guards these were
	# waiting for, but a plate's trigger and its flee wiring are their own bead —
	# the population pass changed WHO is on a storey, not what a pad does. Until
	# then the plate is the author's map of where a purge will go.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var rows: Array = plan["rows"]
	for r: int in rows.size():
		var line: String = rows[r]
		for c: int in line.length():
			if line[c] != TowerPlans.PAD_CHAR:
				continue
			out.append({
				"name": "%sPad%d_%d" % [_plan_prefix(floor_index), c, r],
				"pos": Vector3(_grid_x(float(c) + 0.5), top + PLAN_PAD_THICK * 0.5,
						_grid_z(float(r) + 0.5)),
				"size": Vector3(TowerPlans.PLAN_CELL, PLAN_PAD_THICK,
						TowerPlans.PLAN_CELL),
				"color": COLOR_SYSTEM, "collide": false, "floor": floor_index,
			})
	return out


# ============================================================================
# THE DRESSER — an office in every room, derived (bead godot-test1-0a5)
# ============================================================================
#
# Read the block beside `DRESS_PIECES` first: it says why this is derived rather
# than drawn, and what the three safety rules are. Everything below is those rules
# and nothing else, and none of it names a floor, a room or a letter.

static func _plan_dressing(plan: Dictionary, taken: Array[Dictionary]) -> Array[Dictionary]:
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
	var hole := {} if above.is_empty() else _plan_hole(above)
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
	@param taken: As `_plan_dressing` — everything but the floor slab.
	@param hole: The storey above's stairwell hole, or `{}`.
	@return: `boxes()` entries carrying `"dress": true`, or `[]`.
	"""
	if is_maze_floor(floor_index) or floor_index == block_floor():
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
				var ch := _plan_char(rows, cell + step)
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
					_plan_char(rows, cell + Vector2i(int(normal.x), int(normal.z)))):
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
	"""One room's furniture and wall art. See `_plan_dressing` for the parameters."""
	var cells := _room_cells(rows, letter)
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
			var ch := _plan_char(rows, cell + step)
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
			if _plan_char(rows, cell + step) == TowerPlans.WALL_CHAR:
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
	if is_maze_floor(floor_index) or floor_index == block_floor():
		return []
	# The way up is what the sign points at. A storey with no `S` lane has nothing
	# honest to say, so it says nothing.
	var stair := _plan_stair(plan)
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
	var here := Vector3(_grid_x(float(best.x) + 0.5), 0.0, _grid_z(float(best.y) + 0.5))
	var target := Vector3(_grid_x((float(int(stair["c0"]) + int(stair["c1"])) + 1.0) * 0.5),
			0.0, _grid_z((float(int(stair["r0"]) + int(stair["r1"])) + 1.0) * 0.5))
	var side := SIGN_RIGHT if (target - here).dot(tangent) >= 0.0 else SIGN_LEFT
	return _dress_boxes(rows, floor_index, letter, best, SIGN_PIECES[side])


## The four 4-neighbours, named once. Every rule in the dresser is a claim about
## 4-adjacency (a diagonal neighbour is not a way past a box), so they share one.
const _STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func _plan_char(rows: Array, cell: Vector2i) -> String:
	"""One cell's character, `#` off the edge of the grid — a wall, which is what
	the shell actually is out there."""
	if cell.y < 0 or cell.y >= rows.size():
		return TowerPlans.WALL_CHAR
	var line := String(rows[cell.y])
	if cell.x < 0 or cell.x >= line.length():
		return TowerPlans.WALL_CHAR
	return line[cell.x]


static func _room_cells(rows: Array, letter: String) -> Array[Vector2i]:
	"""Every cell of one room, in row-major order."""
	var out: Array[Vector2i] = []
	for r: int in rows.size():
		var line := String(rows[r])
		for c: int in line.length():
			if line[c] == letter:
				out.append(Vector2i(c, r))
	return out


static func _under_hole(cell: Vector2i, hole: Dictionary) -> bool:
	"""Is this cell under the storey above's stairwell hole? See `_plan_dressing`."""
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
	var x0 := _grid_x(float(cell.x)) + DRESS_EPS
	var x1 := _grid_x(float(cell.x) + 1.0) - DRESS_EPS
	var z0 := _grid_z(float(cell.y)) + DRESS_EPS
	var z1 := _grid_z(float(cell.y) + 1.0) - DRESS_EPS
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
		if _plan_char(rows, cell + step) == TowerPlans.WALL_CHAR:
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
	var centre := Vector3(_grid_x(float(cell.x) + 0.5), 0.0, _grid_z(float(cell.y) + 0.5))
	var face := centre - normal * (TowerPlans.PLAN_CELL * 0.5)
	var top: float = FLOOR_Y[floor_index]
	for i: int in piece["parts"].size():
		var part: Dictionary = piece["parts"][i]
		var size: Vector3 = part["size"]
		var off: Vector3 = part["off"]
		var world := tangent * size.x + Vector3(0.0, size.y, 0.0) + normal.abs() * size.z
		var at := face + tangent * off.x + normal * (off.z + size.z * 0.5)
		at.y = top + off.y + size.y * 0.5
		out.append({
			"name": "%sDress%s_%d_%d_%s%d" % [_plan_prefix(floor_index), letter,
					cell.x, cell.y, piece["kind"], i],
			"pos": at, "size": world, "color": part["color"],
			"collide": bool(part.get("solid", false)), "floor": floor_index,
			"dress": true,
		})
	return out


static func egg_frames() -> Array[Dictionary]:
	"""
	Where the four employee-of-the-month portraits hang, or `[]` if nowhere.

	@return: One `{"hero", "floor", "pos"}` per `TowerGraph.HEROES`, `pos` being
	        the point on the wall face at the walking surface, directly under the
	        frame's centre line. They face +Z by construction — see below.

	ONE FUNCTION, TWO CALLERS, so the batched frames and the textured pictures
	inside them cannot drift apart by a centimetre: `_egg_boxes` builds the wood
	and the plaques off this, and `_build_portraits` hangs the quads off the same
	answer.

	IT IS THE ROOM'S NORTHERNMOST ROW, and that is what makes the +Z facing a fact
	rather than a hope: the cells above it are asserted to be `#` before anything is
	returned, so the wall really is behind the frames and the pictures really do
	look south into the room. Redraw `outer_hall` so that row is no longer against
	stone and this answers `[]` — no portraits, rather than four floating in air.
	"""
	var out: Array[Dictionary] = []
	var floor_index := room_floor(EGG_ROOM)
	if floor_index < 0:
		return out
	var plan := TowerPlans.storey(floor_index)
	var rect := plan_room_rect(floor_index, EGG_ROOM)
	if rect.size == Vector2i.ZERO:
		return out
	var letter := ""
	for key: String in plan["rooms"]:
		if String(plan["rooms"][key]) == EGG_ROOM:
			letter = key
			break
	var rows: Array = plan["rows"]
	var count := TowerGraph.HEROES.size()
	var r := rect.position.y
	var c0 := rect.position.x + (rect.size.x - count) / 2
	for i: int in count:
		if _plan_char(rows, Vector2i(c0 + i, r)) != letter \
				or _plan_char(rows, Vector2i(c0 + i, r - 1)) != TowerPlans.WALL_CHAR:
			return []
	for i: int in count:
		out.append({
			"hero": String(TowerGraph.HEROES[i]),
			"floor": floor_index,
			"pos": Vector3(_grid_x(float(c0 + i) + 0.5), FLOOR_Y[floor_index],
					_grid_z(float(r))),
		})
	return out


static func _egg_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The wooden frame and the brass plaque under each hero portrait.

	Batched boxes like any other dressing, so the joke costs four draw calls for
	the four pictures and nothing at all for the carpentry round them.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	for frame: Dictionary in egg_frames():
		if int(frame["floor"]) != floor_index:
			continue
		var hero: String = frame["hero"]
		var at: Vector3 = frame["pos"]
		out.append({
			"name": "%sEggFrame_%s" % [_plan_prefix(floor_index), hero],
			"pos": Vector3(at.x, at.y + EGG_FRAME_Y + EGG_FRAME_SIZE.y * 0.5, at.z + 0.03),
			"size": Vector3(EGG_FRAME_SIZE.x, EGG_FRAME_SIZE.y, 0.06),
			"color": COLOR_WAINSCOT, "collide": false, "floor": floor_index,
			"dress": true,
		})
		out.append({
			"name": "%sEggPlaque_%s" % [_plan_prefix(floor_index), hero],
			"pos": Vector3(at.x, at.y + EGG_FRAME_Y - 0.16, at.z + 0.025),
			"size": Vector3(0.72, 0.16, 0.05),
			"color": COLOR_SEAL, "collide": false, "floor": floor_index,
			"dress": true,
		})
	return out


static func portrait_material(hero: String) -> StandardMaterial3D:
	"""
	The one material carrying one hero's portrait, for the life of the process.

	@param hero: A `TowerGraph.HEROES` name.
	@return: The cached material, or null when that hero has no portrait shipped.

	THE TEXTURE IS THE HUD'S OWN. `load()` on a `res://` path returns the
	process-wide cached resource, so this is a second reference to the very
	`Texture2D` `hero_hud.gd` draws and never a second copy of the image.
	`ResourceLoader.exists` first, for the same reason the HUD does it: a bare
	`load()` on a hero who ships before his art is a red console error per frame.

	UNSHADED, like everything else under this sealed roof, and `DIFFUSE_TOON` so
	`ToonShading.apply_to_mesh()` declines to duplicate it — the same two lines
	`_batch_material` sets, for the same two reasons.
	"""
	var hit: StandardMaterial3D = _portrait_materials.get(hero)
	if hit != null:
		return hit
	var path := "res://assets/portraits/%s.png" % hero
	if not ResourceLoader.exists(path):
		return null
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(path) as Texture2D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	_portrait_materials[hero] = mat
	return mat


static func riddle_ids() -> Array[String]:
	"""
	Every riddle gate in the graph, in `gates` order.

	Read out of `TowerGraph` rather than listed here, exactly as the identity gate's
	hero is: the building must not be able to hold a riddle the audit has never
	heard of, or miss one it has.
	"""
	var out: Array[String] = []
	for gid: String in TowerGraph.TOWER_GRAPH["gates"]:
		if String(TowerGraph.gate(gid).get("class", "")) == TowerGraph.CLASS_RIDDLE:
			out.append(gid)
	return out


static func gate_slots(plan: Dictionary) -> Dictionary:
	"""
	One storey's gate cells, resolved against the grid it is drawn on.

	@return: `{"masses": {gate id: Rect2i in cells}, "pads": [{gate, digit, c, r}]}`

	The storey's `gates` dict is the ONE binding, for both characters: a `"c,r"` key
	whose cell is a `D` is part of that gate's run, and one whose cell is a lock
	digit is one of its pads. That is what lets a lock and the mass it lifts sit on
	different floors — and `tower_selfcheck` walks the same dict from both ends, so
	neither a cell nobody named nor a name nobody drew can survive a build.

	`"masses"` is EVERY class's `D` run, not just a riddle's: phase 16 gave the
	identity gates and the maintenance crawl `D` cells too, and `_plan_gates` is
	what decides what each run becomes. `"pads"` is only ever a riddle's lock,
	because an identity pad is DERIVED from its own doorway and never drawn.
	"""
	var masses: Dictionary = {}
	var pads: Array[Dictionary] = []
	var rows: Array = plan["rows"]
	var slots: Dictionary = plan["gates"]
	for key: String in slots:
		var parts := key.split(",")
		if parts.size() != 2:
			continue
		var c := int(parts[0])
		var r := int(parts[1])
		if r < 0 or r >= rows.size():
			continue
		var line := String(rows[r])
		if c < 0 or c >= line.length():
			continue
		var gid := String(slots[key])
		var ch := line[c]
		if ch == TowerPlans.GATE_CHAR:
			var span: Rect2i = masses.get(gid, Rect2i(c, r, 1, 1))
			masses[gid] = span.merge(Rect2i(c, r, 1, 1))
		elif TowerPlans.pad_digit(ch) > 0:
			pads.append({"gate": gid, "digit": TowerPlans.pad_digit(ch), "c": c, "r": r})
	return {"masses": masses, "pads": pads}


static func _plan_gates(plan: Dictionary) -> Array[Dictionary]:
	"""
	One storey's gate geometry: what each `D` run becomes, its pads, and any clue
	strip this floor happens to carry.

	@return: `boxes()`-shaped entries. Empty for a storey that draws no gate cell
	        and holds no riddle's clue room.

	ONE ARM PER GATE CLASS, dispatched on `TowerGraph.gate(id)["class"]` — the same
	binding `tower_interior` uses for every other thing it takes from the graph, so
	a gate cannot be drawn in a colour its own row disagrees with:

	  RIDDLE    the MASS, indigo, floor slab to ceiling so it can be neither jumped
	            nor crawled. It travels, so it carries `dynamic` and stays out of
	            the batch. Its four lock pads are DRAWN (`1`-`4` cells) and coloured
	            from `COLOR_RIDDLE_PADS`.
	  IDENTITY  the same mass in the hero's violet, plus ONE pad, which is not drawn
	            at all — see `gate_pad_cell()` for why it is derived.
	  CHALLENGE a LINTEL: a partial-height wall over the run, in ordinary stone and
	            batched, so the opening reads as a duct. The hazard that sweeps
	            under it is hand-built from the same run (`_block_boxes` for the
	            crawl's press, `_rotor_boxes` for the rotor doorway's bars), because
	            a thing that moves is not a plan character. The secure checkpoint is
	            the one authored exception: its graph row declares `GEOMETRY_MASS`
	            so the rising mass and derived pad remain while access stays base kit.
	  DEMAND    nothing at all. Its shutter SINKS rather than rising and its
	            receptacle is not a character either, so `_demand_boxes` builds the
	            whole gate off the same run — see the arm for the argument.

	The CLUE is four plates in a row on the clue room's floor, in the answer's order
	and the answer's colours. DERIVED FROM THE ANSWER ARRAY, so the clue cannot
	drift from the lock it explains — the failure a hand-painted clue would
	eventually have, and one no self-check could see.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var prefix := _plan_prefix(floor_index)
	var top: float = FLOOR_Y[floor_index]
	var slots := gate_slots(plan)

	# Slab to ceiling, so a mass can be neither jumped nor crawled — and the ceiling
	# is this storey's, which is not every storey's (`plan_clear_height`).
	var clear := plan_clear_height(floor_index)
	var masses: Dictionary = slots["masses"]
	for gid: String in masses:
		var span: Rect2i = masses[gid]
		var x0 := _grid_x(float(span.position.x))
		var x1 := _grid_x(float(span.end.x))
		var z0 := _grid_z(float(span.position.y))
		var z1 := _grid_z(float(span.end.y))
		var gate := TowerGraph.gate(gid)
		var cls := String(gate.get("class", ""))
		if cls == TowerGraph.CLASS_DEMAND:
			# NOTHING, on purpose. A demand gate's mass SINKS — it is the one gate in
			# the building that opens downwards — so the generic mass above, which is
			# drawn to be lifted and retired, would be the wrong body in the right
			# hole. And a demand gate is not just a mass: its RECEPTACLE and its four
			# calibration bands are the whole of its legibility, and a pillar standing
			# in front of a door is not a plan character. `_demand_boxes()` reads this
			# same run and builds all six.
			continue
		# Access class and authored silhouette are separate. The secure checkpoint
		# is base kit (challenge semantics), but its existing rising mass and derived
		# pad are part of the shipped floor plan and must remain in the doorway.
		var geometry := String(gate.get("geometry", ""))
		if cls == TowerGraph.CLASS_CHALLENGE and geometry != TowerGraph.GEOMETRY_MASS:
			var lintel_h := clear - CRAWL_LINTEL_Y
			out.append({
				"name": "%sGateLintel_%s" % [prefix, gid],
				"pos": Vector3((x0 + x1) * 0.5, top + CRAWL_LINTEL_Y + lintel_h * 0.5,
						(z0 + z1) * 0.5),
				"size": Vector3(x1 - x0, lintel_h, z1 - z0),
				"color": COLOR_STONE, "collide": true, "floor": floor_index,
			})
			continue
		var identity := cls == TowerGraph.CLASS_IDENTITY
		var mass_style := geometry == TowerGraph.GEOMETRY_MASS
		out.append({
			"name": "%sGateMass_%s" % [prefix, gid],
			"pos": Vector3((x0 + x1) * 0.5, top + clear * 0.5, (z0 + z1) * 0.5),
			"size": Vector3(x1 - x0, clear, z1 - z0),
			# A mass override does not turn a base-kit challenge into an identity
			# gate visually. Violet is reserved for doors that name a hero; this
			# checkpoint remains hazard orange like the other challenge geometry.
			"color": COLOR_IDENTITY if identity else COLOR_HAZARD if mass_style else COLOR_RIDDLE,
			"collide": true, "floor": floor_index,
			"dynamic": true,
		})
		if not identity and not mass_style:
			continue
		# ...and the one pad you stand on, on the side of the doorway you approach
		# it from. An unresolvable side is an AUTHORING ERROR and is left unbuilt
		# rather than guessed at: `tower_selfcheck` fails a gate with no pad, which
		# is the report the author needs. A pad on the wrong side of a door would be
		# a gate you open from inside the room it guards.
		var cell := gate_pad_cell(plan, span)
		if cell.x < 0:
			continue
		out.append({
			"name": "%sGatePad_%s" % [prefix, gid],
			"pos": Vector3(_grid_x(float(cell.x) + 0.5), top + PLAN_PAD_THICK * 0.5,
					_grid_z(float(cell.y) + 0.5)),
			"size": Vector3(TowerPlans.PLAN_CELL, PLAN_PAD_THICK, TowerPlans.PLAN_CELL),
			"color": COLOR_IDENTITY_PAD if identity else COLOR_HAZARD,
			"collide": false, "floor": floor_index,
		})

	for pad: Dictionary in slots["pads"]:
		out.append(_riddle_plate("%sRiddlePad_%s_%d" % [prefix, String(pad["gate"]),
				int(pad["digit"])], int(pad["c"]), int(pad["r"]), int(pad["digit"]),
				floor_index, TowerPlans.PLAN_CELL))

	# ...and any clue this storey happens to carry. A riddle's clue room is named in
	# the GRAPH, so the storey that draws that room paints the strip whether or not
	# it draws any of the riddle's own cells — which is the whole point of a clue.
	for gid2: String in riddle_ids():
		var strip := clue_strip(gid2)
		if strip.is_empty() or int(strip["floor"]) != floor_index:
			continue
		var answer: Array = TowerGraph.gate(gid2)["answer"]
		for i: int in answer.size():
			out.append(_riddle_plate("%sRiddleClue_%s_%d" % [prefix, gid2, i],
					int(strip["c"]) + i, int(strip["r"]), int(answer[i]), floor_index,
					TowerPlans.PLAN_CELL * 0.7))
	return out


static func gate_pad_cell(plan: Dictionary, span: Rect2i) -> Vector2i:
	"""
	Which cell a rising mass's pad stands on, `Vector2i(-1, -1)` when the plan
	cannot say. This serves named identity gates and the base-kit secure mass.

	@param span: The gate's `D` run, in cells.

	DERIVED, NEVER AUTHORED. Of the four cells 4-adjacent to the run's midpoint,
	exactly ONE must be plain floor, and that is the corridor side — the side you
	walk up to the door from. The run's own cells are `D`, the wall it is cut into
	is `#` and the room it guards is a lettered room, so in a well-drawn plan
	exactly one neighbour is ever `.`; the two-sided and no-sided cases are
	authoring errors, and `tower_selfcheck` names them rather than this file
	guessing. A pad on the wrong side of a door is a gate you open from inside the
	room it guards.
	"""
	var rows: Array = plan["rows"]
	var mid := span.position + span.size / 2
	var found := Vector2i(-1, -1)
	var seen := 0
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cell := mid + step
		if cell.x < 0 or cell.y < 0 or cell.y >= rows.size():
			continue
		var line := String(rows[cell.y])
		if cell.x >= line.length() or line[cell.x] != TowerPlans.FLOOR_CHAR:
			continue
		found = cell
		seen += 1
	return found if seen == 1 else Vector2i(-1, -1)


static func _riddle_plate(plate_name: String, c: int, r: int, digit: int,
		floor_index: int, side: float) -> Dictionary:
	"""One coloured plate on a storey's floor — a lock pad or a clue mark."""
	return {
		"name": plate_name,
		"pos": Vector3(_grid_x(float(c) + 0.5), FLOOR_Y[floor_index] + PLAN_PAD_THICK * 0.5,
				_grid_z(float(r) + 0.5)),
		"size": Vector3(side, PLAN_PAD_THICK, side),
		"color": COLOR_RIDDLE_PADS[clampi(digit - 1, 0, COLOR_RIDDLE_PADS.size() - 1)],
		"collide": false, "floor": floor_index,
	}


static func clue_strip(gate_id: String) -> Dictionary:
	"""
	Where one riddle's clue is painted: `{floor, c, r}`, the WEST end of the strip.

	@return: `{}` when the gate is not a riddle, or when no storey draws its clue
	        room — which `tower_selfcheck` fails on rather than shrugging at.

	DERIVED FROM THE CLUE ROOM'S OWN CELLS, centred on their bounding box, because
	an authored xz would be a third place the plan has to agree with itself. The
	self-check asserts every plate lands on a plain cell of that room, so a strip
	that ran into a wall or over a system pad fails the build.
	"""
	var room_id := String(TowerGraph.gate(gate_id).get("clue_room", ""))
	var answer: Array = TowerGraph.gate(gate_id).get("answer", [])
	if room_id == "" or answer.is_empty():
		return {}
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		var letter := ""
		for key: String in plan["rooms"]:
			if String(plan["rooms"][key]) == room_id:
				letter = key
				break
		if letter == "":
			continue
		var span := Rect2i()
		var first := true
		for r: int in plan["rows"].size():
			var line := String(plan["rows"][r])
			for c: int in line.length():
				if line[c] != letter:
					continue
				var cell := Rect2i(c, r, 1, 1)
				span = cell if first else span.merge(cell)
				first = false
		if first:
			continue
		var start := span.position.x + int(floorf(float(span.size.x - answer.size()) * 0.5))
		return {
			"floor": floor_index,
			"c": start,
			"r": span.position.y + span.size.y / 2,
		}
	return {}


static func _plan_prefix(floor_index: int) -> String:
	"""
	The name every box of one planned storey carries.

	The number is the FLOOR INDEX and not the storey's colloquial name — floor 2 is
	"storey 3" in the design notes and `S2Plan...` here, because the index is what
	`FLOOR_Y`, the `floor` key and the `Floor%d` container all agree on, and a name
	that meant a third thing would be one more mapping to keep in step.
	"""
	return "S%dPlan" % floor_index


static func plan_room_rect(floor_index: int, room_id: String) -> Rect2i:
	"""
	The cell bounding box of one graph room on one storey, `Rect2i()` if absent.

	@param room_id: A `TOWER_GRAPH` room id, as it appears in a storey's `rooms`.

	THE LOOKUP EVERY HAND-BUILT PART OF THE CELL BLOCK IS PLACED FROM. The plan
	already says where the gallery is and how wide a cell is; a second copy of those
	numbers as constants is exactly how a containment frame ends up 40 cm outside
	the recess it belongs to (which is what `_spine_door_x` and `_cell_x` were, and
	why they are gone).
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return Rect2i()
	var letter := ""
	for key: String in plan["rooms"]:
		if String(plan["rooms"][key]) == room_id:
			letter = key
			break
	if letter == "":
		return Rect2i()
	var span := Rect2i()
	var first := true
	for r: int in plan["rows"].size():
		var line := String(plan["rows"][r])
		for c: int in line.length():
			if line[c] != letter:
				continue
			var cell := Rect2i(c, r, 1, 1)
			span = cell if first else span.merge(cell)
			first = false
	return Rect2i() if first else span


static func plan_gate_rect(floor_index: int, gate_id: String) -> Rect2i:
	"""
	The cell bounding box of one gate's `D` run on one storey, `Rect2i()` if absent.

	`gate_slots()` already walks the storey's `gates` dict from both ends; this is
	that walk looked up by id, and deliberately not a second walker.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return Rect2i()
	return gate_slots(plan)["masses"].get(gate_id, Rect2i())


static func plan_doorway_rect(floor_index: int, room_id: String) -> Rect2i:
	"""
	The plain-floor gap in the wall row on the +Z side of one room's cells.

	@return: The doorway's cells, or `Rect2i()` when that row has no gap.

	THE ONE DOORWAY IN THIS BUILDING WITH NOTHING DRAWN IN IT. `block_main_door` is
	ungated, so it has no `D` and no `gates` entry to look up — and the custody
	scar's rubble has to stand exactly in it. Rather than write its cells down a
	second time, this reads the wall the corridor's south side is closed by and
	returns the run somebody can walk through. A wall with two gaps in it would be
	two doorways and is not what this answers; the run it returns is the first.
	"""
	var rect := plan_room_rect(floor_index, room_id)
	if rect.size == Vector2i.ZERO:
		return Rect2i()
	var plan := TowerPlans.storey(floor_index)
	var r := rect.end.y
	if r >= plan["rows"].size():
		return Rect2i()
	var line := String(plan["rows"][r])
	var span := Rect2i()
	var first := true
	for c: int in range(rect.position.x, mini(rect.end.x, line.length())):
		if line[c] != TowerPlans.FLOOR_CHAR:
			if not first:
				break
			continue
		var cell := Rect2i(c, r, 1, 1)
		span = cell if first else span.merge(cell)
		first = false
	return Rect2i() if first else span


## The room whose presence says "this storey draws the cell block". Keyed on a
## graph room and never on a floor number, so the block is wherever it is drawn.
const BLOCK_ROOM: String = "cell_gallery"

## ...and the same trick for the checkpoint, which bead `godot-test1-dn8` moved off
## a hand-authored `Vector3` and onto storey 2's grid. The plate, the post, the
## trigger volume and `setback_point()`'s far end are all read out of this room's
## cells, so re-drawing the checkpoint anywhere in the building moves all four.
const CHECKPOINT_ROOM: String = "checkpoint_room"

## How far clear of `CheckpointPost` a player is set back to. The post stands on the
## plate, in the middle of the room, and "the checkpoint" is the space BESIDE it —
## put the player on the room's centre and they are inside the pillar.
const CHECKPOINT_CLEAR: float = 1.0

## ...and the same trick again for THE LABYRINTH, which is a place and not a floor
## number: the two maze storeys are wherever their cores are drawn. Two consumers
## read this — the wayfinding plaques below (which stay out of the maze, because the
## maze is the one part of the building that is meant to be hard to cross) and the
## minimap's jail line (which degrades to "NO LOCK" up here). Neither may spell
## "storey 8 and 9" in a constant of its own.
const MAZE_ROOMS: Array[String] = ["s8_maze_core", "s9_maze_core"]


static func is_maze_floor(floor_index: int) -> bool:
	"""
	Is this storey part of the labyrinth?

	Derived from `MAZE_ROOMS` through `room_floor()` and memoized on first ask, for
	the reason `block_floor()` is: the minimap asks this on its 5 Hz tick and
	`room_floor()` scans every storey's whole grid.
	"""
	if _maze_floors_cache == null:
		var found: Array[int] = []
		for room_id: String in MAZE_ROOMS:
			var at := room_floor(room_id)
			if at >= 0:
				found.append(at)
		_maze_floors_cache = found
	return (_maze_floors_cache as Array[int]).has(floor_index)


static func room_floor(room_id: String) -> int:
	"""
	Which `FLOOR_Y` index draws one graph room, -1 when no storey does.

	Check 1 of `tower_selfcheck` already guarantees a room is claimed by at most one
	storey, so the first hit is the only hit.
	"""
	for floor_index: int in TowerPlans.floors():
		if plan_room_rect(floor_index, room_id).size != Vector2i.ZERO:
			return floor_index
	return -1


static func block_floor() -> int:
	"""Which `FLOOR_Y` index the cell block is drawn on, -1 when no storey draws it."""
	if _block_floor_cache != -2:
		return _block_floor_cache
	_block_floor_cache = room_floor(BLOCK_ROOM)
	return _block_floor_cache


static func gate_stand(gate_id: String, steps: int) -> Vector3:
	"""
	Where a player stands to work one gate: the centre of the cell `steps` out from
	its `D` run, on the side `gate_pad_cell()` picked.

	@param steps: 1 is the pad cell itself (an identity gate's plate); 2 is one cell
	        further back, which is where you end up when something SOLID stands on
	        the pad — the demand gate's receptacle pillar.
	@return: interior-local metres at the storey's walking surface, `Vector3.ZERO`
	        when no storey draws the gate or the drawing cannot say which side.

	DERIVED, LIKE THE PAD ITSELF. Every trigger volume in the phase-3 keep used to
	be an authored `Vector3` beside an authored mass; bead `godot-test1-dn8` drew
	both gates on the grid, and a trigger that did not follow the drawing would be
	a plate you stand on and a volume three metres away.
	"""
	for floor_index: int in TowerPlans.floors():
		var run := plan_gate_rect(floor_index, gate_id)
		if run.size == Vector2i.ZERO:
			continue
		var pad := gate_pad_cell(TowerPlans.storey(floor_index), run)
		if pad.x < 0:
			return Vector3.ZERO
		var cell := pad + (pad - (run.position + run.size / 2)) * (steps - 1)
		return Vector3(_grid_x(float(cell.x) + 0.5), FLOOR_Y[floor_index],
				_grid_z(float(cell.y) + 0.5))
	return Vector3.ZERO


static func checkpoint_stand() -> Vector3:
	"""
	Where a guard's setback drops a player who HAS lit the checkpoint.

	Inside `CheckpointTrigger`'s volume and clear of `CheckpointPost` by
	`CHECKPOINT_CLEAR` — "the checkpoint" is the space beside the post, not the
	post's own footprint. It was a `const Vector3` authored against the keep's upper
	floor until bead `godot-test1-dn8`; it is now the room's own cells, so moving
	the checkpoint in the ASCII moves the respawn with it.
	"""
	var floor_index := room_floor(CHECKPOINT_ROOM)
	if floor_index < 0:
		return entry_stand()
	var room := _cell_span(plan_room_rect(floor_index, CHECKPOINT_ROOM))
	return Vector3((room["x0"] + room["x1"]) * 0.5 - CHECKPOINT_CLEAR,
			FLOOR_Y[floor_index] + 0.2, (room["z0"] + room["z1"]) * 0.5)


static func entry_stand() -> Vector3:
	"""
	...and where it drops a player who has not: just inside the front door.

	Derived from the SHELL's own door constants and clear of the trigger volume by a
	metre, so a setback never lands you in the doorway you are about to re-enter.
	The x moved outward with bead `godot-test1-dn8`: the keep's own door — the one
	this used to stand behind — no longer exists, and there is one ring now.
	"""
	return Vector3(TowerPlans.PLAN_HALF - TowerShell.DOOR_TRIGGER_DEPTH - 1.0, 0.2, 0.0)


static func _rotor_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The challenge space's mechanism: the post in the rotor doorway and its two
	counter-rotating bars.

	@return: `RotorPost` (solid, full storey height) and `RotorBarLow` /
	        `RotorBarHigh` (never solid — a script-moved solid body shoves a
	        `CharacterBody3D` through whatever is behind it, and behind this one is
	        the outside world).

	The DOORWAY is a `D` run drawn on the plan and `_plan_gates`' challenge arm
	builds its lintel; what cannot be a plan character is a thing that MOVES, so the
	post and the bars are placed from the same run here. Same division of labour as
	the maintenance crawl's press, one gate class along.
	"""
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var clear := plan_clear_height(floor_index)
	var run := _cell_span(plan_gate_rect(floor_index, "rotor_gate"))
	var at_x: float = (run["x0"] + run["x1"]) * 0.5
	var at_z: float = (run["z0"] + run["z1"]) * 0.5
	var out: Array[Dictionary] = [{
		"name": "RotorPost",
		"pos": Vector3(at_x, top + clear * 0.5, at_z),
		"size": Vector3(0.4, clear, 0.4),
		"color": COLOR_HAZARD, "collide": true, "floor": floor_index,
	}]
	for bar: Array in [["RotorBarLow", ROTOR_LOW_Y, ROTOR_LOW_SPEED],
			["RotorBarHigh", ROTOR_HIGH_Y, ROTOR_HIGH_SPEED]]:
		out.append({
			"name": String(bar[0]),
			"pos": Vector3(at_x, top + float(bar[1]), at_z),
			"size": Vector3(2.0 * ROTOR_ARM, 0.3, 0.3),
			"color": COLOR_HAZARD, "collide": false, "floor": floor_index,
			"spin": float(bar[2]),
		})
	return out


static func _demand_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The demand gate: the shutter that sinks, the receptacle pillar you read it from,
	and the four calibration bands up its face.

	@return: `DemandShutter`, `Receptacle`, `Band1`..`Band4`. Every name is kept
	        exactly — they are claimed by `TOWER_GRAPH`, held in `MOVING_PARTS` and
	        looked up by `_remember()`, and keeping them is what makes this a
	        geometry move rather than a rename.

	`_plan_gates` deliberately builds NOTHING for a demand gate (see its
	`CLASS_DEMAND` arm): a shutter sinks where every other mass in the building
	rises, and a receptacle is not a plan character at all. So the run is read here
	and the pillar stands on the cell `gate_pad_cell()` picked — the side of the
	doorway you walk up from, drawn rather than authored — with the bands on the
	face that looks back at you. `bottom band first`, because `_update_bands()`
	lights them by index.
	"""
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var clear := plan_clear_height(floor_index)
	var slot := plan_gate_rect(floor_index, GATE_DEMAND)
	var run := _cell_span(slot)
	var out: Array[Dictionary] = [{
		"name": "DemandShutter",
		"pos": Vector3((run["x0"] + run["x1"]) * 0.5, top + clear * 0.5,
				(run["z0"] + run["z1"]) * 0.5),
		"size": Vector3(run["x1"] - run["x0"], clear, run["z1"] - run["z0"]),
		"color": COLOR_MECHANISM, "collide": true, "floor": floor_index,
		"dynamic": true,
	}]
	var pad := gate_pad_cell(plan, slot)
	if pad.x < 0:
		return out   # an authoring error `tower_selfcheck` names; never guessed at.
	var step := pad - (slot.position + slot.size / 2)
	var face := Vector3(float(step.x), 0.0, float(step.y))
	var at_x := _grid_x(float(pad.x) + 0.5)
	var at_z := _grid_z(float(pad.y) + 0.5)
	# The pillar is THIN ACROSS THE APPROACH and wide along it, whichever axis the
	# drawing put the doorway on, so its face is the one you are looking at.
	var along_x := absf(face.x) > absf(face.z)
	out.append({
		"name": "Receptacle",
		"pos": Vector3(at_x, top + 1.3, at_z),
		"size": Vector3(0.6, 2.6, 1.0) if along_x else Vector3(1.0, 2.6, 0.6),
		"color": COLOR_MECHANISM, "collide": true, "floor": floor_index,
	})
	for i in DEMAND_BANDS:
		out.append({
			"name": "Band%d" % (i + 1),
			"pos": Vector3(at_x + face.x * 0.35, top + 0.75 + 0.45 * float(i),
					at_z + face.z * 0.35),
			"size": Vector3(0.1, 0.18, 0.7) if along_x else Vector3(0.7, 0.18, 0.1),
			"color": COLOR_BAND_DARK, "collide": false, "floor": floor_index,
		})
	return out


static func _checkpoint_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The checkpoint: a plate you cross and the post standing on it, both relit once.

	@return: `CheckpointPlate` (0.1 m proud and never solid — a lip of any height is
	        a wall in this engine) and `CheckpointPost`, centred in the room the plan
	        letters `checkpoint_room`.

	It is a MARKER and not a passage — `GATE_CHECKPOINT` gates no edge, and check 1
	of `tower_selfcheck` refuses it as one — so the room's own `parts` claim these
	two boxes rather than a gate row.
	"""
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var room := _cell_span(plan_room_rect(floor_index, CHECKPOINT_ROOM))
	var at_x: float = (room["x0"] + room["x1"]) * 0.5
	var at_z: float = (room["z0"] + room["z1"]) * 0.5
	return [
		{
			"name": "CheckpointPlate",
			"pos": Vector3(at_x, top + 0.05, at_z),
			"size": Vector3(3.0, 0.1, 3.0),
			"color": COLOR_CHECKPOINT, "collide": false, "floor": floor_index,
		},
		{
			"name": "CheckpointPost",
			"pos": Vector3(at_x, top + 1.3, at_z),
			"size": Vector3(0.7, 2.6, 0.7),
			"color": COLOR_CHECKPOINT, "collide": true, "floor": floor_index,
		},
	]


static func _cell_span(rect: Rect2i) -> Dictionary:
	"""One plan rect as metres: `{x0, x1, z0, z1}` on the interior's own axes."""
	return {
		"x0": _grid_x(float(rect.position.x)), "x1": _grid_x(float(rect.end.x)),
		"z0": _grid_z(float(rect.position.y)), "z1": _grid_z(float(rect.end.y)),
	}


static func _block_boxes(plan: Dictionary) -> Array[Dictionary]:
	"""
	The cell block's hand-built parts, as `boxes()` entries on the storey that draws
	the block.

	@return: The press, four containment frames, the authored staging, the purge
	        pad, two light panels and the custody scar's rubble — in build order.

	EVERYTHING THE PLAN CAN DRAW IS DRAWN: the corridor's walls, the gallery's, the
	four recesses' dividers, the four gate masses, their pads and the crawl's lintel
	are all `#` / `D` cells built by `_merge_walls` and `_plan_gates`. What is left
	here is the six things a grid of characters cannot say — a press that sweeps,
	four fields that recolour on liberation, one piece of staging that disappears,
	an operable pad, the light, and rubble that appears the day the protocol is
	survived — and every one of them is POSITIONED FROM A PLAN LOOKUP, so the day
	somebody moves a wall in the ASCII these move with it.

	They go in `plan_boxes()`, which since bead `godot-test1-dn8` is the only
	population there is: the hand-authored `boxes()` table went with the keep, and
	every box in this building is now measured against `PLAN_HALF` (38.8 m) on the
	storey that drew it.
	"""
	var out: Array[Dictionary] = []
	var floor_index := int(plan["floor"])
	var top: float = FLOOR_Y[floor_index]
	var clear := plan_clear_height(floor_index)

	# ---- The maintenance crawl's press, in the duct the plan drew for it ----
	# `sweep` marks a part that is MOVING on any frame you look at it, the way
	# `spin` marks a rotor bar. Its y here is the TOP of the stroke, which is where
	# `press_y(0)` puts it — see that function.
	var crawl := plan_gate_rect(floor_index, "maintenance_crawl")
	if crawl.size != Vector2i.ZERO:
		var duct := _cell_span(crawl)
		out.append({
			"name": "CrawlPress",
			"pos": Vector3((duct["x0"] + duct["x1"]) * 0.5, top + PRESS_TOP,
					(duct["z0"] + duct["z1"]) * 0.5),
			"size": Vector3(duct["x1"] - duct["x0"] - 0.1, 0.7, 0.6),
			"color": COLOR_HAZARD, "collide": false, "floor": floor_index,
			"sweep": true, "dynamic": true,
		})

	# ---- The four containment fields, across the back of each recess -------
	for hero: String in TowerGraph.HEROES:
		var cell := plan_room_rect(floor_index, "cell_%s" % hero)
		if cell.size == Vector2i.ZERO:
			continue
		var box := _cell_span(cell)
		out.append({
			"name": "CellFrame%s" % hero.capitalize(),
			"pos": Vector3((box["x0"] + box["x1"]) * 0.5, top + 1.25, box["z0"] + 0.3),
			"size": Vector3(box["x1"] - box["x0"] - 0.6, 2.5, 0.12),
			"color": COLOR_CELL, "collide": false, "floor": floor_index,
			"dynamic": true,
		})

	# THE ONE PIECE OF AUTHORED STAGING IN THE BUILDING. A standard cell plus a
	# steel containment screen across its mouth: the first rescue's identity comes
	# from what is IN the cell, never from the cell, because any hero can land in
	# any of them. Non-solid — it smothers a field, it is not a door — and gone for
	# good the moment `RESCUE_DONE` is in the opened set.
	# WAIST HIGH, and that was found by walking it rather than reasoned: built full
	# height it stood in front of the containment frame and hid it, so Primm's cell
	# read exactly like the three empty ones — the staging swallowed the one thing
	# this block has to say from across the gallery.
	var staged := plan_room_rect(floor_index, "cell_%s" % AUTHORED_CAPTIVE)
	if staged.size != Vector2i.ZERO:
		var stage := _cell_span(staged)
		out.append({
			"name": "PrimmContainment",
			"pos": Vector3((stage["x0"] + stage["x1"]) * 0.5, top + 0.6, stage["z1"] - 0.5),
			"size": Vector3(stage["x1"] - stage["x0"] - 0.2, 1.2, 0.5),
			"color": COLOR_MECHANISM, "collide": false, "floor": floor_index,
			"dynamic": true,
		})

	# The vent-purge pad. Same plate shape as the four gate pads, in the gallery
	# rather than the corridor - it is operated from the wrong side of the doors, by
	# somebody the doors are keeping in.
	var pad := purge_pad()
	out.append({
		"name": "PurgePad",
		"pos": Vector3(pad.x, top + 0.05, pad.z),
		"size": Vector3(PURGE_PAD_SIDE, 0.1, PURGE_PAD_SIDE),
		"color": COLOR_SYSTEM, "collide": false, "floor": floor_index,
	})

	# ---- Light. The block is under the sealed roof and the sun never reaches it.
	for pair: Array in [["PanelCorridor", "service_stair"], ["PanelGallery", BLOCK_ROOM]]:
		var room := plan_room_rect(floor_index, String(pair[1]))
		if room.size == Vector2i.ZERO:
			continue
		var lit := _cell_span(room)
		out.append({
			"name": String(pair[0]),
			"pos": Vector3((lit["x0"] + lit["x1"]) * 0.5, top + clear - 0.05,
					(lit["z0"] + lit["z1"]) * 0.5),
			"size": Vector3(lit["x1"] - lit["x0"] - 2.0, 0.1, lit["z1"] - lit["z0"] - 1.0),
			"color": COLOR_PANEL, "collide": false, "floor": floor_index,
		})

	# ---- THE SCAR (phase 11), in the doorway phase 16 moved it to -----------
	# The block's wide doorway, filled with rubble — built ALWAYS, drawn and made
	# solid only once `TowerGraph.SCAR_CUSTODY` is in the opened set
	# (`_refresh_scar`). In the table so it is budgeted, footprint-checked and fits
	# the shell like every other box; `scar` is what keeps it out of the BASE plan
	# the self-checks sample, and `severs` names the graph edge it takes away, so
	# `tower_selfcheck` can bind the two rather than trust this comment.
	var gap := plan_doorway_rect(floor_index, "service_stair")
	if gap.size != Vector2i.ZERO:
		var rubble := _cell_span(gap)
		out.append({
			"name": SCAR_BOX,
			"pos": Vector3((rubble["x0"] + rubble["x1"]) * 0.5, top + clear * 0.5,
					(rubble["z0"] + rubble["z1"]) * 0.5),
			"size": Vector3(rubble["x1"] - rubble["x0"], clear,
					rubble["z1"] - rubble["z0"]),
			"color": COLOR_SCAR, "collide": true, "floor": floor_index,
			"scar": TowerGraph.SCAR_CUSTODY, "severs": "block_main_door",
			"dynamic": true,
		})
	return out


static func purge_pad() -> Vector3:
	"""
	The vent-purge pad's centre, in interior-local metres — the gallery's +X end.

	`y` is the storey's walking surface; the plate itself stands `0.05` over it.
	"""
	var floor_index := block_floor()
	if floor_index < 0:
		return Vector3.ZERO
	var box := _cell_span(plan_room_rect(floor_index, BLOCK_ROOM))
	return Vector3(box["x1"] - 1.5, FLOOR_Y[floor_index], (box["z0"] + box["z1"]) * 0.5)


static func cell_stand(hero: String) -> Vector3:
	"""
	Where the prison role stands a benched player up, in interior-local metres.

	@param hero: the captive - one of `TowerGraph.HEROES`. An unknown name lands in
	    the gallery, which is inside the block and therefore still legal.

	ONE PLAYER PER CELL comes free from the geometry: the cells are indexed by hero
	and a peer is benched holding exactly one, so two benched peers are two
	different recesses with no allocator, no registry and nothing to keep in step.

	`y` is the same 0.2 m lift `custody_stand()` uses - a body dropped exactly on
	the floor plane can start the frame a hair inside it.
	"""
	var floor_index := block_floor()
	if floor_index < 0:
		return Vector3.ZERO
	var cell := plan_room_rect(floor_index, "cell_%s" % hero)
	if cell.size == Vector2i.ZERO:
		return purge_pad() + Vector3(0.0, 0.2, 0.0)
	var box := _cell_span(cell)
	return Vector3((box["x0"] + box["x1"]) * 0.5, FLOOR_Y[floor_index] + 0.2,
			(box["z0"] + box["z1"]) * 0.5)


static func _block_bounds() -> Dictionary:
	"""
	The gallery and its four cells as one rect in metres, `{}` when unbuilt.

	EVERYTHING ON THE GALLERY SIDE OF THE SPINE WALL AND NOTHING ELSE — the union
	of the rooms a prisoner may walk, read off the plan rather than written down.
	"""
	if _block_bounds_cache != null:
		return _block_bounds_cache
	var floor_index := block_floor()
	if floor_index < 0:
		_block_bounds_cache = {}
		return _block_bounds_cache
	var span := plan_room_rect(floor_index, BLOCK_ROOM)
	for hero: String in TowerGraph.HEROES:
		var cell := plan_room_rect(floor_index, "cell_%s" % hero)
		if cell.size != Vector2i.ZERO:
			span = span.merge(cell)
	_block_bounds_cache = _cell_span(span)
	return _block_bounds_cache


## How far inside the block's own walls the prisoner's clamp stops. Keeps it off
## the wall faces, so a body pushed into the box is not pushed into geometry.
const BLOCK_INSET: float = 0.4


static func block_min() -> Vector3:
	"""
	The prison role's confinement box, low corner, in interior-local metres.

	THE GALLERY AND ITS FOUR CELLS AND NOTHING ELSE - everything on the far side of
	the spine wall, which is where the four identity doors stand: a prisoner may
	walk the gallery and every cell (that is what makes freeing a CELLMATE possible,
	and it is the block's second system) but may never step through a spine door,
	which is the whole of "no solo escape". `tower_interior_selfcheck` re-derives
	both corners rather than trusting them.
	"""
	var box := _block_bounds()
	if box.is_empty():
		return Vector3.ZERO
	return Vector3(float(box["x0"]) + BLOCK_INSET, FLOOR_Y[block_floor()],
			float(box["z0"]) + BLOCK_INSET)


static func block_max() -> Vector3:
	"""The confinement box's high corner - see `block_min()`."""
	var box := _block_bounds()
	if box.is_empty():
		return Vector3.ZERO
	return Vector3(float(box["x1"]) - BLOCK_INSET, FLOOR_Y[block_floor()],
			float(box["z1"]) - BLOCK_INSET)


static func press_y(clock: float) -> float:
	"""
	Where the crawl press sits at `clock` seconds into its cycle.

	@param clock: 0 .. `PRESS_PERIOD`.
	@return: The mesh's y, in interior-local metres.

	A raised cosine, so it DWELLS at both ends: the gap under it is open long
	enough to walk through at a walk, which is the difference between a challenge
	and a coin flip. `press_y(0)` is the top of the stroke, which is where
	`_block_boxes()` puts the box — so the table and the animation agree at t = 0
	and the self-check can assert the stroke's bounds from these two constants.

	IT IS A STROKE AND NOT A HEIGHT: the block stands on storey 10, so the caller
	adds the storey's walking surface. Keeping this relative is what lets the three
	constants above stay the same three numbers they were on the ground floor.
	"""
	var phase := TAU * clock / PRESS_PERIOD
	return PRESS_BOTTOM + (PRESS_TOP - PRESS_BOTTOM) * (0.5 + 0.5 * cos(phase))


static func demand_met(reach: float) -> bool:
	"""
	Does this reading satisfy the demand gate? The ONE comparison — see
	`DEMAND_TOLERANCE` for why it is not a bare `>=`.

	@param reach: The standing hero's Phase Step reach, in metres.
	"""
	return reach + DEMAND_TOLERANCE >= DEMAND_TARGET


static func demand_ratio(reach: float) -> float:
	"""
	How far along the calibration ladder this reading gets, 0 .. 1.

	@param reach: The standing hero's Phase Step reach, in metres.

	Carries the SAME tolerance the comparison does, so the ladder fills exactly when
	the gate opens. Without that the top band stays dark on the reading that passes,
	which reads as "you are one short" beside a door that just opened.
	"""
	return clampf((reach + DEMAND_TOLERANCE) / DEMAND_TARGET, 0.0, 1.0)


static func headroom() -> float:
	"""Clear height of the enclosed entry hall, floor to slab underside."""
	return SLAB_Y - SLAB_THICK


static func is_own_node(box: Dictionary) -> bool:
	"""
	Does this box need a `MeshInstance3D` of its own, rather than the batch?

	THE ONE ANSWER, asked by `_ready()` when it builds and by
	`tower_interior_selfcheck` when it counts the draws and the materials — the two
	must not be able to disagree about which boxes left the batch.

	Three ways in: the `MOVING_PARTS` name list (the hand-built parts — the gate
	masses, the press, the rotor bars — whose names a const can hold), a rotor's
	`spin`, and a plan box that declared itself `dynamic` (phase 15's riddle masses,
	which are named by a builder and so cannot be in a const list).
	"""
	return MOVING_PARTS.has(String(box["name"])) \
		or not is_zero_approx(float(box.get("spin", 0.0))) \
		or bool(box.get("dynamic", false))


func _ready() -> void:
	"""Build the interior, its one collision body, its pads and its label."""
	add_to_group("tower_interior")

	# ONE StaticBody3D for the whole interior — the shell's rule, and the chunks'.
	var body := StaticBody3D.new()
	body.name = "InteriorCollision"
	add_child(body)

	# One container per storey. Visibility is toggled on THESE, never on individual
	# meshes, so `_update_visibility` is one boolean write per floor however big a
	# floor gets — and the count comes off `FLOOR_Y`, so a storey added to
	# `TowerPlans` gets its container with no edit here.
	for i in FLOOR_Y.size():
		var floor_node := Node3D.new()
		floor_node.name = "Floor%d" % i
		add_child(floor_node)
		_floors.append(floor_node)

	# THE STATIC GEOMETRY IS ONE MESH PER STOREY, batched below. Only the parts that
	# move or change colour get a node of their own.
	var batched: Array[Array] = []
	for i in FLOOR_Y.size():
		batched.append([])

	for box: Dictionary in all_boxes():
		var parent: Node3D = _floors[int(box["floor"])]
		var spin: float = float(box.get("spin", 0.0))
		if not is_zero_approx(spin):
			parent = _make_rotor(box, parent)
		elif not is_own_node(box):
			batched[int(box["floor"])].append(box)
			if box["collide"]:
				_add_shape(body, box)
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _box_mesh(box["size"])
		# A rotor bar hangs off a pivot that is already at the post, so only its
		# HEIGHT is local; everything else is placed in interior space.
		mesh.position = Vector3(0.0, box["pos"].y, 0.0) if not is_zero_approx(spin) else box["pos"]
		if box.has("rot"):
			mesh.rotation = box["rot"]
		mesh.material_override = _material(box["color"])
		_no_shadow(mesh)
		parent.add_child(mesh)
		# The press's hazard volume rides the mesh itself, so one `position.y` write
		# moves what you see and what hurts you together. Never a solid body: a
		# script-driven solid shoves a `CharacterBody3D` through the wall behind it.
		if box.has("sweep"):
			_add_hazard_child(mesh, box["size"])
		_remember(box["name"], mesh)
		if not box["collide"]:
			continue
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box["size"]
		shape.shape = box_shape
		shape.position = box["pos"]
		if box.has("rot"):
			shape.rotation = box["rot"]
		shape.name = "%sShape" % box["name"]
		body.add_child(shape)
		if box["name"] == "DemandShutter":
			_shutter_shape = shape
		elif box["name"] == SCAR_BOX:
			_scar_shape = shape
		elif gate_of(String(box["name"])) != "":
			var gid := gate_of(String(box["name"]))
			# The same three-way split `_remember()` makes above, and it has to be
			# the same one: a mesh in `_spine_meshes` whose shape landed in
			# `_mass_shape` is a gate that opens visually and stays solid.
			if gid == GATE_IDENTITY:
				_mass_shape = shape
			elif String(TowerGraph.gate(gid).get("class", "")) == TowerGraph.CLASS_IDENTITY:
				_spine_shapes[gid] = shape
			else:
				_riddle_shapes[gid] = shape

	for i in _floors.size():
		# A floor index with nothing static on it — `FLOOR_Y` names all ten storeys
		# from phase 16's first task, and the upper ones are authored task by task —
		# gets its container and no mesh. An empty batch is a node and a
		# `DRAW_BUDGET` slot for zero triangles.
		if batched[i].is_empty():
			continue
		var batch := MeshInstance3D.new()
		batch.name = "Floor%dBatch" % i
		batch.mesh = merged_mesh(batched[i])
		_no_shadow(batch)
		_floors[i].add_child(batch)
		# AIR SIGHT'S SWAP LIST, resolved once and by MATERIAL IDENTITY rather than
		# by a surface index: `merged_mesh` omits any surface a storey has nothing
		# for, so "walls are surface 0" is true of a planned storey and meaningless
		# on one with none. Asking which surface wears the wall material is the same
		# question with no arithmetic to get wrong.
		for surface: int in batch.mesh.get_surface_count():
			if batch.mesh.surface_get_material(surface) == _batch_material(false, true):
				_wall_surfaces.append([batch, surface])

	_build_pads()
	_build_lift_stop()
	_build_block()
	_build_riddles()
	_build_label()
	_build_vault_prize()
	_build_portraits()
	# Whatever the tower already knows is open, apply it NOW — before the first
	# frame, with no animation. This is the seam phase 5 loads a save through, and
	# the reason the acceptance walk ("out and back in, gates still open") is a
	# property of the code rather than of nothing ever being freed.
	_apply_opened()
	_update_bands()

	# THE POPULATION. Deferred, and the deferral is load-bearing rather than
	# tidiness: `endless_terrain._tower_stream()` parks the shell on the tower site
	# on the line AFTER `add_child()`, so at this point in `_ready()` the whole
	# building is still standing at the terrain's origin and our `global_position`
	# is a lie. Guards are placed in LOCAL space (which is correct either way), but
	# `set_confinement()` takes WORLD coordinates — computed here it would leash
	# every guard to a box 400 m away and `_clamp_to_platform` would fire on the
	# first frame. One idle frame later the shell is where it belongs.
	reset_guards.call_deferred()

	# ...and re-place them whenever the local player crosses the doorway. The shell
	# owns the door trigger and already emits on it; connecting here rather than
	# there keeps the arrow pointing one way (this file reads the shell, never the
	# reverse — see the header). Guarded, so an interior built standalone by a
	# self-check simply never gets the signal and keeps its build-time population.
	var tower := _tower()
	if tower != null and tower.has_signal("player_entered") \
			and not tower.is_connected("player_entered", _on_tower_doorway):
		tower.connect("player_entered", _on_tower_doorway)
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_signal("heroes_changed") \
			and not mp.is_connected("heroes_changed", _on_hero_holders_changed):
		mp.connect("heroes_changed", _on_hero_holders_changed)


func _on_hero_holders_changed(_heroes: Dictionary, _pool: Array) -> void:
	"""Reconcile cell pictures when the synchronized live-holder map changes."""
	_refresh_cells()


func _exit_tree() -> void:
	"""
	Hand the outdoor camera back on the way out.

	THE ROOM IS THE ONLY THING THAT CLEARS THE INDOOR BOOM, so a room that is FREED
	while the player stands in it would leave the short arm on forever. That is not
	hypothetical: joining a multiplayer room mid-run calls `new_run()`, which
	`_tower_reset()`s the shell out from under this node before teleporting the
	player to the group — no respawn, no `reset_position()`, nobody left to ask.

	Here rather than at that call site because it covers every way the building can
	go away, present and future, with one guard. Cheap and null-safe: on shutdown
	the player may be gone or going, which reads as "nothing to hand back".
	"""
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player != null and player.has_method("set_indoor_camera"):
		player.call("set_indoor_camera", false)


func _process(delta: float) -> void:
	"""
	Everything that moves, plus the visibility gating.

	ONE `_process` FOR THE WHOLE BUILDING — the fauna manager's rule. Two rotor
	pivots, two gate tweens, one distance test and two boolean writes; the rotors
	are skipped outright while the interior is not drawn, which is most of a run.
	"""
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var near := _update_visibility()
	if not near:
		return
	for i in _rotors.size():
		var speed: float = ROTOR_LOW_SPEED if i == 0 else ROTOR_HIGH_SPEED
		_rotors[i].rotation.y = wrapf(_rotors[i].rotation.y + speed * delta, 0.0, TAU)
	_tick_press(delta)
	_tick_gates(delta)
	_tick_pads()
	_tick_purge(delta)


# ============================================================================
# THE OPENED SET — in-session persistence, and phase 5's seam
# ============================================================================

func _tower() -> Node:
	"""The shell this interior lives in, or null when built standalone in a check."""
	return get_parent() if get_parent() != null and get_parent().has_method("mark_opened") else null


func _is_open(id: String) -> bool:
	"""Has this gate id been opened this run? False when there is no tower above us."""
	var tower := _tower()
	return tower != null and bool(tower.call("is_opened", id))


func _open(id: String) -> void:
	"""
	Record a gate as open ON THE TOWER, not here.

	THE STATE DOES NOT LIVE IN THIS NODE, deliberately. It lives on the shell,
	which is the node the world knows about (group "tower"), the node phase 5 will
	serialize, and — the multiplayer landmine — the node a broadcast would carry.
	Nothing here is a permission check against the local player: the pad asks WHO
	IS STANDING THERE, and the answer is written into world state that every peer
	would see. Syncing it is one `opened_ids()` broadcast whenever that phase lands,
	with no rework, because there is no per-player state to untangle.
	"""
	var tower := _tower()
	if tower != null:
		tower.call("mark_opened", id)


func _apply_opened() -> void:
	"""
	Snap every gate to whatever the opened set says, with no animation.

	The one place state becomes geometry. Called at build time (so a tower that was
	already opened comes back open) and never again — the live tweens in
	`_tick_gates` take over from here.
	"""
	if _is_open(GATE_DEMAND):
		_shutter_open = 1.0
	if _is_open(GATE_IDENTITY):
		_mass_open = 1.0
	if _is_open(GATE_CHECKPOINT):
		_light_checkpoint()
	for door: Dictionary in SPINE_DOORS:
		var gid := String(door["gate"])
		_spine_open[gid] = 1.0 if _is_open(gid) else 0.0
		_place_spine(gid)
	# A solved riddle is a solved riddle for good — it is in the same monotone set,
	# so a tower rebuilt (or a save reloaded) comes back with the mass already up
	# and the sequence never asked for again.
	for gid2: String in _riddle_meshes:
		_riddle_open[gid2] = 1.0 if _is_open(gid2) else 0.0
		_riddle_step[gid2] = 0
		_riddle_nudge[gid2] = 0.0
		_place_riddle(gid2)
	_place_shutter()
	_place_mass()
	# The captive set is seeded from the same snapshot, so a tower rebuilt after the
	# authored rescue comes up with an empty cell block and no staging in it.
	_captives.clear()
	if not _is_open(RESCUE_DONE):
		_captives[AUTHORED_CAPTIVE] = true
	# ...and then from the FIELD. Systemic capture (bead godot-test1-3iy.9) happens
	# out on the map, where this building is a streamed landmark that is usually not
	# in the tree at all — so the player owns the set and this node mirrors it. The
	# capture pushes through `set_captive()` when the tower happens to be loaded,
	# and a tower streamed in afterwards catches up HERE, which is the half that
	# makes the cell real: `_liberate()` early-returns on a hero it has no record
	# of, so without this line a hero taken in the field would have a red frame and
	# no way out of it.
	var owner_of_the_set := get_tree().get_first_node_in_group("player")
	if owner_of_the_set != null and owner_of_the_set.has_method("is_hero_captive"):
		for hero: String in TowerGraph.HEROES:
			if bool(owner_of_the_set.call("is_hero_captive", hero)):
				_captives[hero] = true
	_refresh_cells()
	_refresh_scar()
	# ...and the same mirror for the full-custody scene. A protocol begins out in
	# the field and TELEPORTS the party here, so on most runs this building is
	# streamed in a frame AFTER the scene started and the player's own
	# `begin_lockdown()` call found no interior to make. Both ends, exactly as the
	# captive set above: the player pushes when the tower is loaded, a tower built
	# afterwards catches up here. Without it the doors stand open and the break-out
	# is three metres of walking.
	if owner_of_the_set != null and owner_of_the_set.has_method("in_custody_protocol") \
			and bool(owner_of_the_set.call("in_custody_protocol")):
		begin_lockdown()


# ============================================================================
# THE GATES
# ============================================================================

func _tick_gates(delta: float) -> void:
	"""Advance the two gate tweens and the demand gate's partway nudge."""
	var step := delta / GATE_TIME
	if _is_open(GATE_DEMAND) and _shutter_open < 1.0:
		_shutter_open = minf(1.0, _shutter_open + step)
		_place_shutter()
	if _is_open(GATE_IDENTITY) and _mass_open < 1.0:
		_mass_open = minf(1.0, _mass_open + step)
		_place_mass()
	for door: Dictionary in SPINE_DOORS:
		var gid := String(door["gate"])
		# `_lockdown` beats the opened set, and only while the scene runs: an id in
		# it is a door the protocol shut again, and it re-opens on the pad press
		# that erases it — never on its own.
		if _is_open(gid) and not _lockdown.has(gid) \
				and float(_spine_open.get(gid, 0.0)) < 1.0:
			_spine_open[gid] = minf(1.0, float(_spine_open.get(gid, 0.0)) + step)
			_place_spine(gid)
	if _nudge > 0.0:
		_nudge = maxf(0.0, _nudge - delta / NUDGE_TIME)
		_place_shutter()
	# The riddles: the same open tween, plus the clunk decaying on the same clock as
	# the demand gate's nudge — one reaction, two gates, one constant.
	for gid: String in _riddle_meshes:
		var moved := false
		if _is_open(gid) and float(_riddle_open.get(gid, 0.0)) < 1.0:
			_riddle_open[gid] = minf(1.0, float(_riddle_open.get(gid, 0.0)) + step)
			moved = true
		if float(_riddle_nudge.get(gid, 0.0)) > 0.0:
			_riddle_nudge[gid] = maxf(0.0, float(_riddle_nudge[gid]) - delta / NUDGE_TIME)
			moved = true
		if moved:
			_place_riddle(gid)


func _place_shutter() -> void:
	"""
	Put the shutter where its open fraction and its nudge say.

	The nudge is a half-sine: down and back up over NUDGE_TIME, scaled by how close
	the reading was. It is the SECOND readout of the same number the bands show —
	a player who did not look at the ladder still sees the slab move a little for a
	small shortfall and a lot for a near miss.
	"""
	if _shutter_mesh == null:
		return
	var drop := SHUTTER_TRAVEL * _shutter_open
	if _shutter_open < 1.0 and _nudge > 0.0:
		drop += SHUTTER_TRAVEL * NUDGE_FRACTION * _nudge_ratio * sin(PI * (1.0 - _nudge))
	# Rest height off the box the table placed, like every other mass in the
	# building — the shutter fills its storey's doorway, and a storey is not always
	# 4.6 m tall (`plan_clear_height`).
	_shutter_mesh.position.y = float(_gate_rest.get(GATE_DEMAND, 0.0)) - drop
	if _shutter_shape != null:
		_shutter_shape.position.y = _shutter_mesh.position.y


func _place_mass() -> void:
	"""
	Put the secure mass where its open fraction says. It only ever rises.

	AND IT RISES INTO STOREY 3, which is why `_retire` is here — the same call
	`_place_spine` makes, for the same reason: fully open, half the mass stands
	proud of the floor above, in whatever room happens to be drawn over the doorway.
	That was invisible while the keep was the top of the building; phase 16 built
	ten storeys over it.

	THE REST HEIGHT IS READ OFF THE BOX, never recomputed. It used to be
	`SLAB_Y + UPPER_WALL_HEIGHT * 0.5`, two authored constants that went with the
	keep (bd godot-test1-dn8); the mass is a plan `D` run now and as tall as its own
	storey, so `_gate_rest` — filled by `_remember()` from the mesh the table placed
	— is the one source, exactly as it already was for the spines and the riddles.
	"""
	if _mass_mesh == null:
		return
	var lift := MASS_TRAVEL * _mass_open
	_mass_mesh.position.y = float(_gate_rest.get(GATE_IDENTITY, 0.0)) + lift
	if _mass_shape != null:
		_mass_shape.position.y = _mass_mesh.position.y
	_retire(_mass_mesh, _mass_shape, _mass_open >= 1.0)


func _tick_pads() -> void:
	"""
	Re-decide the secure-door and demand pads against the CURRENT hero, every frame.

	The secure door is polled rather than answered in `body_entered`: E switches
	character while you stand there, and ability state is cleared on a switch
	(player_controller's existing rule), so the gate re-evaluates the hero standing
	there every frame. It is base kit, so every hero passes; identity spine doors
	below still compare their named hero. Nothing is buffered, held, or counted down.

	THE DEMAND GATE GETS THE SAME TREATMENT, and for a reason that is legibility
	rather than symmetry: its calibration ladder relights live as you cycle heroes on
	the plate, so a player who rotates to Primm and watches the bands fill would
	otherwise be looking at a full ladder on a shut door until they stepped off and
	back on. This is also the ONLY place the vault opens — `_attempt_demand` refuses
	and never opens — so there is one answer to "is the reading good enough" and one
	place that gives it.
	"""
	if _player == null:
		return
	# The gate's access class is the graph's to say. The secure checkpoint is a
	# base-kit challenge, so its mass opens for whoever is standing on its pad;
	# identity gates elsewhere still compare the graph's named hero here.
	var identity_gate := TowerGraph.gate(GATE_IDENTITY)
	var named_identity := String(identity_gate.get("class", "")) == TowerGraph.CLASS_IDENTITY
	var hero_matches := not named_identity or _hero_name() == TowerGraph.identity_of(GATE_IDENTITY)
	if (_on_identity_pad and hero_matches and not _is_open(GATE_IDENTITY)):
		_open(GATE_IDENTITY)
		_say(tr("The mass lifts. The way through stays open."))
		_sfx("play_level_up")
	_tick_spine_pads()
	_tick_riddle_pads()
	if not _on_demand_pad:
		return
	_update_bands()
	if not _is_open(GATE_DEMAND) and demand_met(_phase_reach()):
		_open(GATE_DEMAND)
		_say(tr("Calibration met. The vault opens."))
		_sfx("play_level_up")


func _tick_riddle_pads() -> void:
	"""
	Read every riddle lock against the pad the player is standing on RIGHT NOW.

	POLLED, and for a reason `body_entered` cannot cover: the pads of one lock touch
	each other, so walking from pad 2 onto pad 3 fires an enter and an exit in an
	order Godot does not promise. Holding "which pad is under the player" and acting
	on the CHANGE makes the step depend on where you are and not on which signal won
	the frame — the same reasoning that makes the secure door a poll, one gate verb
	later. Standing still presses nothing, which is what makes a four-step sequence
	enterable at a walk.
	"""
	for gid: String in _riddle_meshes:
		var now := int(_riddle_on_pad.get(gid, 0))
		if now == int(_riddle_last.get(gid, 0)):
			continue
		_riddle_last[gid] = now
		if now > 0 and not _is_open(gid):
			_press_riddle(gid, now)


func _press_riddle(gate_id: String, digit: int) -> void:
	"""
	One step of a combination.

	Right: the mass lifts a notch and the sequence advances. Wrong: it drops back and
	CLUNKS — the demand gate's partway reaction, scaled by how far in you were, so a
	miss on the last step is louder than a miss on the first. No penalty, no lockout,
	no cooldown: a riddle costs time and attention and nothing else.

	A wrong step that HAPPENS TO BE the first digit restarts the sequence at one
	rather than at zero, because a lock that made you step off and back on to try
	again would be a puzzle about its own interface.
	"""
	var answer: Array = TowerGraph.gate(gate_id).get("answer", [])
	if answer.is_empty():
		return
	# A COMPLETED SEQUENCE THAT NEVER GOT RECORDED starts again from the top rather
	# than indexing past the end. `_tick_riddle_pads` skips an OPEN gate, and the
	# open state lives on the shell (`_open` / `_is_open`) — so an interior built
	# with no tower above it, which is exactly what a self-check does, finishes the
	# answer, records nothing, and comes back here with `step` at `answer.size()`.
	var step := int(_riddle_step.get(gate_id, 0))
	if step >= answer.size():
		step = 0
	if digit == int(answer[step]):
		step += 1
	else:
		_riddle_ratio[gate_id] = float(step) / float(answer.size())
		_riddle_nudge[gate_id] = 1.0
		_sfx("play_buzz")
		step = 1 if digit == int(answer[0]) else 0
	_riddle_step[gate_id] = step
	_place_riddle(gate_id)
	if step < answer.size():
		return
	_open(gate_id)
	_sfx("play_level_up")


func _place_riddle(gate_id: String) -> void:
	"""
	Put one riddle's mass where its progress, its tween and its clunk say.

	Three terms, and the partial one is bounded by `RIDDLE_NOTCH` for a reason that
	is not cosmetic: the gap under a part-risen mass must stay under the player's
	capsule, or a lock three quarters entered is a lock you walk under.
	"""
	var mesh: MeshInstance3D = _riddle_meshes.get(gate_id)
	if mesh == null:
		return
	var answer: Array = TowerGraph.gate(gate_id).get("answer", [])
	var opened := float(_riddle_open.get(gate_id, 0.0))
	var steps := maxi(answer.size(), 1)
	var lift := riddle_travel(mesh) * opened
	if opened < 1.0:
		lift += RIDDLE_NOTCH * float(int(_riddle_step.get(gate_id, 0))) / float(steps)
		var clunk := float(_riddle_nudge.get(gate_id, 0.0))
		if clunk > 0.0:
			lift += RIDDLE_RATTLE * maxf(float(_riddle_ratio.get(gate_id, 0.0)), 0.25) \
				* sin(PI * (1.0 - clunk))
	mesh.position.y = float(_gate_rest.get(gate_id, 0.0)) + lift
	var shape: CollisionShape3D = _riddle_shapes.get(gate_id)
	if shape != null:
		shape.position.y = mesh.position.y
	_retire(mesh, shape, opened >= 1.0)


func _attempt_demand() -> void:
	"""
	The player stepped onto the receptacle's plate — a deliberate attempt.

	THIS FUNCTION ONLY REFUSES. Opening lives in `_tick_pads`'s poll and nowhere
	else, so there is exactly one place the vault can come open and it is the same
	place that answers "who is standing here now"; a good reading returns from here
	untouched and is opened on the same frame. Splitting it the other way — open
	here, poll there — is how you get a gate that buzzes at you and then opens.

	What is left is the two things the epic's legibility rules ask of a refusal: a
	PARTWAY REACTION (the shutter moves as far as you are strong) and, the first
	time only, an EXPLANATION naming the capability, the number, and the fact that
	ranks fix it. Diagnosable, then forecastable.
	"""
	var reach := _phase_reach()
	_nudge_ratio = demand_ratio(reach)
	_update_bands()
	if _is_open(GATE_DEMAND) or demand_met(reach):
		return
	_nudge = 1.0
	_sfx("play_buzz")
	if _explained:
		return
	_explained = true
	# Two lines: what it measured and what it wanted, then what to do about it.
	# The hero name is in the message because a Windman standing here reads 0.0 and
	# would otherwise have no idea the number is even reachable.
	_say("%s\n%s" % [
		tr("PHASE RECEPTACLE — needs PHASE STEP REACH %.1f m, reads %.1f m.") % [
			DEMAND_TARGET, reach],
		tr("Primm carries phase. Rank up Long Step — farm coins for the points."),
	])


func _update_bands() -> void:
	"""
	Light the calibration ladder from the bottom up: lit bands are the standing
	hero's reading, dark bands are the shortfall, the whole stack is the demand.

	Called whenever the player is on the plate, so switching hero on the spot
	re-reads the ladder live — which is how a player discovers the category belongs
	to one hero without being told.
	"""
	var ratio := demand_ratio(_phase_reach())
	var lit := DEMAND_BANDS if _is_open(GATE_DEMAND) else int(floor(ratio * float(DEMAND_BANDS)))
	# Called every frame the player stands on the plate, so it earns a latch: four
	# `material_override` writes a frame is churn for a reading that changes only
	# when somebody presses E.
	if lit == _lit_bands:
		return
	_lit_bands = lit
	for i in _band_meshes.size():
		_band_meshes[i].material_override = _material(
			COLOR_BAND_LIT if i < lit else COLOR_BAND_DARK)


func _light_checkpoint() -> void:
	"""Swap the checkpoint's plate and post to the lit material. Idempotent."""
	for mesh: MeshInstance3D in _checkpoint_meshes:
		mesh.material_override = _material(COLOR_CHECKPOINT_LIT)


# ============================================================================
# BUILD HELPERS
# ============================================================================

func _make_rotor(box: Dictionary, parent: Node3D) -> Node3D:
	"""
	A rotor bar's pivot: a Node3D at the post, carrying the bar mesh and the bar's
	hazard volume, so ONE `rotation.y` sweeps both.

	The hazard is an `Area3D`, never a solid body — a solid bar moved by script
	shoves a `CharacterBody3D` through whatever is behind it, and behind this one is
	the outside world.
	"""
	var pivot := Node3D.new()
	pivot.name = "%sPivot" % box["name"]
	pivot.position = Vector3(box["pos"].x, 0.0, box["pos"].z)
	parent.add_child(pivot)
	_rotors.append(pivot)

	var hazard := Area3D.new()
	hazard.name = "%sHazard" % box["name"]
	hazard.monitorable = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box["size"]
	shape.shape = box_shape
	hazard.add_child(shape)
	hazard.position = Vector3(0.0, box["pos"].y, 0.0)
	hazard.body_entered.connect(_on_hazard_touched)
	pivot.add_child(hazard)
	return pivot


func _build_pads() -> void:
	"""
	The three trigger volumes: demand plate, identity plate, checkpoint.

	ALL THREE ARE READ OFF THE DRAWING since bead `godot-test1-dn8`. They were
	authored `Vector3`s beside authored masses while floors 0 and 1 were the keep's
	box table; both gates are `D` runs on the plan grid now, so each volume is the
	cell `gate_pad_cell()` picked (the demand gate one further back, because its
	receptacle pillar is standing ON its pad cell) and the checkpoint is its room's
	own centre. A trigger that did not follow the drawing would be a plate you stand
	on and a volume three metres away.
	"""
	# NAMED `*Trigger`, NOT `*Pad`: the visible plates are meshes already carrying
	# those names, and two siblings with one name is a rename by the engine — which
	# turns every `get_node("Floor1/IdentityPad")` into a null.
	var cell := Vector3(TowerPlans.PLAN_CELL, 2.0, TowerPlans.PLAN_CELL)
	var demand := gate_stand(GATE_DEMAND, 2)
	var demand_floor := room_floor("vault")
	if demand_floor >= 0:
		_add_area("DemandTrigger", demand + Vector3(0.0, 1.0, 0.0), cell,
			_on_demand_enter, _on_demand_exit, demand_floor)
	var identity := gate_stand(GATE_IDENTITY, 1)
	var identity_floor := room_floor(CHECKPOINT_ROOM)
	if identity_floor >= 0:
		_add_area("IdentityTrigger", identity + Vector3(0.0, 1.0, 0.0), cell,
			_on_identity_enter, _on_identity_exit, identity_floor)
		var plate := checkpoint_stand()
		_add_area("CheckpointTrigger",
			Vector3(plate.x + CHECKPOINT_CLEAR, FLOOR_Y[identity_floor] + 1.0, plate.z),
			Vector3(3.0, 2.0, 3.0), _on_checkpoint_enter, Callable(), identity_floor)


func _build_lift_stop() -> void:
	"""
	The labyrinth's lift stop: one `Area3D` over the storey-8 ramp head.

	NO GEOMETRY AND NO SECOND PATTERN. This is `CheckpointTrigger` one storey
	vocabulary along — walk in, an id joins the monotone opened set, nothing moves —
	because "a stop the tower remembers you reached" is exactly what both are. The
	only difference is which set member the id names: the checkpoint is a gate id,
	this is `TowerGraph.ENTRY_LIFT_MAZE`, the graph entry the lift will offer.

	# ponytail: the trigger and no menu. Choosing a stop is bead godot-test1-3iy.7,
	# and the entry's `built` flag in the graph says so; earning it has to ship
	# first or that bead has nothing to offer.
	"""
	var floor_index := lift_stop_floor()
	if floor_index < 0:
		return  # no storey carries the stop's landing — nothing to trigger on.
	var rect := landing_rect(floor_index)
	if rect.size == Vector2i.ZERO:
		return
	var span := _cell_span(rect)
	_add_area("LiftStopTrigger",
		Vector3((span["x0"] + span["x1"]) * 0.5, FLOOR_Y[floor_index] + 1.0,
				(span["z0"] + span["z1"]) * 0.5),
		Vector3(span["x1"] - span["x0"], 2.0, span["z1"] - span["z0"]),
		_on_lift_stop_enter, Callable(), floor_index)


static func lift_stop_floor() -> int:
	"""
	Which `FLOOR_Y` index carries the maze lift stop, -1 when no storey does.

	DERIVED FROM THE GRAPH AND THE PLANS, never written down: the entry row names
	its room, and the storey whose `landing` key is that room is the storey whose
	`s` cells you arrive on. Re-plan the labyrinth onto a different floor and the
	trigger follows it, the way `block_floor()` follows the cell block.
	"""
	var room := String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_MAZE).get("room", ""))
	if room == "":
		return -1
	for floor_index: int in TowerPlans.floors():
		if String(TowerPlans.storey(floor_index).get("landing", "")) == room:
			return floor_index
	return -1


static func landing_rect(floor_index: int) -> Rect2i:
	"""The `s` landing cells of one storey as a cell rect, `Rect2i()` if it has none."""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return Rect2i()
	var span := Rect2i()
	var first := true
	for r: int in plan["rows"].size():
		var line := String(plan["rows"][r])
		for c: int in line.length():
			if line[c] != TowerPlans.LANDING_CHAR:
				continue
			var cell := Rect2i(c, r, 1, 1)
			span = cell if first else span.merge(cell)
			first = false
	return Rect2i() if first else span


func _add_area(area_name: String, pos: Vector3, size: Vector3,
		on_enter: Callable, on_exit: Callable, floor_index: int) -> void:
	"""One trigger volume, parented to its floor so it hides with it."""
	var area := Area3D.new()
	area.name = area_name
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	area.add_child(shape)
	area.position = pos
	area.body_entered.connect(on_enter)
	if not on_exit.is_null():
		area.body_exited.connect(on_exit)
	_floors[floor_index].add_child(area)


func _build_riddles() -> void:
	"""
	Every riddle's lock: one trigger volume per pad, and two signs.

	THE PADS ARE BATCHED PLATES WITH NO NODE OF THEIR OWN — the plate you see is
	part of the storey's merged mesh, and what makes it a lock is this `Area3D`
	standing on it. Only the mass leaves the batch, because only the mass moves.

	The two signs are the whole of this feature's TEXT, and they are two words: the
	sequence itself is spelled in colour, at both ends, so the puzzle needs no
	sentence to state and no sentence to translate.
	"""
	for floor_index: int in TowerPlans.floors():
		var plan := TowerPlans.storey(floor_index)
		var slots := gate_slots(plan)
		var lock_sum: Dictionary = {}
		var lock_n: Dictionary = {}
		for pad: Dictionary in slots["pads"]:
			var gid := String(pad["gate"])
			var digit := int(pad["digit"])
			var here := Vector3(_grid_x(float(int(pad["c"])) + 0.5),
					FLOOR_Y[floor_index] + 1.0, _grid_z(float(int(pad["r"])) + 0.5))
			_add_area("RiddleTrigger_%s_%d" % [gid, digit], here,
					Vector3(TowerPlans.PLAN_CELL * 0.9, 2.0, TowerPlans.PLAN_CELL * 0.9),
					_on_riddle_enter.bind(gid, digit), _on_riddle_exit.bind(gid, digit),
					floor_index)
			# The sign hangs over the middle of the pad block, which is the mean of
			# the pads themselves — so a lock of any shape signs itself.
			lock_sum[gid] = (lock_sum.get(gid, Vector3.ZERO) as Vector3) + here
			lock_n[gid] = int(lock_n.get(gid, 0)) + 1
		for gid2: String in lock_sum:
			var centre: Vector3 = (lock_sum[gid2] as Vector3) / float(int(lock_n[gid2]))
			_make_label("RiddleLockLabel_%s" % gid2,
					centre + Vector3(0.0, 1.6, 0.0), tr("SEQUENCE LOCK"), floor_index)

	for gid3: String in riddle_ids():
		var strip := clue_strip(gid3)
		if strip.is_empty():
			continue
		var answer: Array = TowerGraph.gate(gid3)["answer"]
		var mid := float(int(strip["c"])) + float(answer.size()) * 0.5
		_make_label("RiddleClueLabel_%s" % gid3,
				Vector3(_grid_x(mid), FLOOR_Y[int(strip["floor"])] + 2.0,
					_grid_z(float(int(strip["r"])) + 0.5)),
				tr("SEQUENCE"), int(strip["floor"]))


func _make_label(label_name: String, pos: Vector3, text: String,
		floor_index: int = 0) -> Label3D:
	"""
	One world label: billboarded, wrapped narrow, shadow-free, parented to storey 0.

	Shared by every sign in the building — the demand gate's, the spine's, the cell's
	and a lock/clue pair per riddle — because they are the same object at a different
	position. See `_build_label()` for why these are world labels and not HUD toasts.

	WRAPPED, AND NARROW ON PURPOSE. A `Label3D` is geometry: an unwrapped
	explanation is a 5.7 m banner that runs straight into the walls either side of
	the receptacle's alcove and gets depth-culled mid-sentence, which is how the
	first build shipped a gate that said "...farm coins for the point". 700 px at
	this pixel size is 2.45 m — narrower than the niche it stands in, from both
	sides. (The block's two signs then shrink themselves further; the corridor they
	hang in is narrower still, and `_build_block()` says why.)
	"""
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.font_size = 40
	label.outline_size = 12
	label.pixel_size = 0.0035
	label.width = 700.0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = COLOR_BAND_LIT
	label.position = pos
	_no_shadow(label)
	# ITS OWN STOREY, not floor 0: a label is geometry and hides with the container
	# it hangs in, so a sign parented to the ground floor would be drawn whenever
	# the ground floor is — from 46 m up, through five slabs.
	_floors[clampi(floor_index, 0, _floors.size() - 1)].add_child(label)
	return label


func _build_label() -> void:
	"""
	The gate's voice: one `Label3D` over the receptacle, reused by every message.

	A WORLD LABEL AND NOT A HUD TOAST, on purpose. The explanation is about the
	thing in front of you, so it belongs on the thing in front of you — it stays
	legible in first person (C cycles the view), it needs no HUD node to exist for
	the tower to work, and it cannot collide with the landmark quiz card. It starts
	holding the receptacle's own name, which is what makes the mechanism
	self-identifying from across the hall.
	"""
	# Over the pillar, on the side you read it from — one cell back and 3.2 m up, off
	# the same derived stand the trigger volume uses.
	var at := gate_stand(GATE_DEMAND, 2)
	_label = _make_label("DemandLabel", at + Vector3(0.0, 3.2, 0.0),
		tr("PHASE RECEPTACLE"))


func _build_portraits() -> void:
	"""
	The four hero portraits, and the caption that makes them a joke.

	ONE QUAD PER HERO, and they are the only textured surfaces in this building —
	which is exactly why they cannot be batched: `merged_mesh` welds boxes into two
	VERTEX-COLOURED surfaces, and a photograph is not a vertex colour. Four draw
	calls, on one storey, and `DRAW_BUDGET` moved by four and says so.

	PARENTED TO THEIR OWN STOREY, like every other mesh here, so they hide with it:
	the visibility gate is a boolean write on `Floor%d` and the joke is inside it,
	not drawn from six floors up. The caption rides `_make_label`, which parents to
	the same container for the same reason — and a `Label3D` is not a
	`MeshInstance3D`, so it costs the mesh budget nothing.
	"""
	var frames := egg_frames()
	if frames.is_empty():
		return
	for frame: Dictionary in frames:
		var hero: String = frame["hero"]
		var mat := portrait_material(hero)
		if mat == null:
			continue
		var at: Vector3 = frame["pos"]
		var quad := MeshInstance3D.new()
		quad.name = "EggPortrait_%s" % hero
		var plane := QuadMesh.new()
		plane.size = EGG_PORTRAIT_SIZE
		quad.mesh = plane
		# 7 cm proud of the wall: 6 cm of frame, then the picture sitting in it, hung
		# from the frame's TOP edge so the mount falls below it over the plaque.
		quad.position = Vector3(at.x,
				at.y + EGG_FRAME_Y + EGG_FRAME_SIZE.y - EGG_PORTRAIT_INSET
						- EGG_PORTRAIT_SIZE.y * 0.5,
				at.z + 0.07)
		quad.material_override = mat
		_no_shadow(quad)
		_floors[int(frame["floor"])].add_child(quad)
	# One caption for the row rather than four, because the joke is that all four
	# of them won it at once and four separate plaques would be four setups for it.
	var first: Vector3 = frames[0]["pos"]
	var last: Vector3 = frames[frames.size() - 1]["pos"]
	_make_label("EggLabel", Vector3((first.x + last.x) * 0.5,
			first.y + EGG_FRAME_Y + EGG_FRAME_SIZE.y + 0.55, first.z + 0.2),
			tr("EMPLOYEE OF THE MONTH (ALL FOUR, EVERY MONTH)"),
			int(frames[0]["floor"]))


func _build_vault_prize() -> void:
	"""
	A single gem behind the demand gate — the reason to want in.

	One node, worth ten coins, and it is the EXISTING collectible rather than a
	tower-specific reward: the pickup, the sound, the streak and the level maths all
	already work. An empty vault would make the gate a puzzle about nothing.
	"""
	var floor_index := room_floor("vault")
	if floor_index < 0:
		return   # no storey draws the vault — nothing to put a prize in.
	var room := _cell_span(plan_room_rect(floor_index, "vault"))
	var gem := load("res://scenes/collectibles/coin.tscn").instantiate() as Node3D
	gem.name = "VaultGem"
	# Centred in the room the plan draws, at pickup height. It was an authored
	# `Vector3` inside the keep's vault until bead `godot-test1-dn8`; the room is a
	# `V` on a floor plan now, so the prize follows the walls.
	gem.position = Vector3((room["x0"] + room["x1"]) * 0.5,
			FLOOR_Y[floor_index] + 1.1, (room["z0"] + room["z1"]) * 0.5)
	_floors[floor_index].add_child(gem)
	if gem.has_method("make_gem"):
		gem.call("make_gem")


func _remember(box_name: String, mesh: MeshInstance3D) -> void:
	"""Keep the handful of meshes whose material or transform changes later."""
	match box_name:
		"DemandShutter":
			_shutter_mesh = mesh
			# Its own rest height, off the box the table just placed — the same one
			# source `_gate_rest` is for every other mass. It sinks from here.
			_gate_rest[GATE_DEMAND] = mesh.position.y
		"CheckpointPlate", "CheckpointPost":
			_checkpoint_meshes.append(mesh)
		"CrawlPress":
			_press = mesh
			# The stroke is relative to the storey the duct is drawn on — read off
			# the mesh the table just placed, never a second copy of `FLOOR_Y[9]`.
			_press_base = mesh.position.y - PRESS_TOP
		"PrimmContainment":
			_containment = mesh
		SCAR_BOX:
			_scar_slab = mesh
		_:
			if box_name.begins_with("Band"):
				_band_meshes.append(mesh)
				return
			if box_name.begins_with("CellFrame"):
				# "CellFrameWindman" -> "windman". Derived, so a fifth hero needs no
				# second table: the box was named from `TowerGraph.HEROES` and this
				# reads the name straight back.
				_cell_frames[box_name.trim_prefix("CellFrame").to_lower()] = mesh
				return
			var gid := gate_of(box_name)
			if gid == "":
				return
			# The rest height, taken off the mesh the table just placed rather than
			# recomputed — one number, one source, no chance of a mass that animates
			# from a y its own box never had. Both gate families want it now that
			# the spine doors stand on a storey and not on y = 0.
			_gate_rest[gid] = mesh.position.y
			if gid == GATE_IDENTITY:
				# THE SECURE CHECKPOINT MASS THAT IS NOT A RESCUE SPINE. It is drawn by
				# the same builder and carries the same name shape since bead
				# `godot-test1-dn8` (`S1PlanGateMass_tower_secure_door`), but it is
				# the phase-3 secure door with its own tween, its own trigger and its
				# own opened-set id — so it is held where phase 3 held it and the
				# spine dictionaries never hear about it.
				_mass_mesh = mesh
			elif String(TowerGraph.gate(gid).get("class", "")) == TowerGraph.CLASS_IDENTITY:
				_spine_meshes[gid] = mesh
			else:
				_riddle_meshes[gid] = mesh


static func gate_of(box_name: String) -> String:
	"""
	Which gate a box is the mass of, "" for a box that is no gate's mass.

	Derived from the name the plan builder gave it — `S<floor>PlanGateMass_<id>` —
	rather than from a second table, exactly as `CellFrame<Hero>` is read back. The
	CLASS then says which family the mass belongs to, which is why one name serves
	the riddles and the four rescue spines alike.
	"""
	var cut := box_name.find("GateMass_")
	return "" if cut < 0 else box_name.substr(cut + "GateMass_".length())


# ============================================================================
# THE CELL BLOCK — phase 8's rooms, on phase 16's storey
# ============================================================================

func _build_block() -> void:
	"""
	The cell block's trigger volumes and its two labels.

	Four spine pads (polled, like every identity pad in this building) and four cell
	volumes (one-shot, because liberation is a thing you do and not a thing you
	stand in). Every position is read off the plan, and all of them are parented to
	the storey that draws the block, so they hide with it.
	"""
	var floor_index := block_floor()
	if floor_index < 0:
		return
	var plan := TowerPlans.storey(floor_index)
	var top: float = FLOOR_Y[floor_index]
	var slots := gate_slots(plan)
	for i in SPINE_DOORS.size():
		var gid := String(SPINE_DOORS[i]["gate"])
		var span: Rect2i = slots["masses"].get(gid, Rect2i())
		if span.size == Vector2i.ZERO:
			continue
		var cell := gate_pad_cell(plan, span)
		if cell.x < 0:
			continue
		_add_area("SpineTrigger%d" % (i + 1),
			Vector3(_grid_x(float(cell.x) + 0.5), top + 1.0, _grid_z(float(cell.y) + 0.5)),
			Vector3(TowerPlans.PLAN_CELL, 2.0, PAD_TRIGGER_DEPTH),
			_on_spine_enter.bind(gid), _on_spine_exit.bind(gid), floor_index)
	var pad := purge_pad()
	_add_area("PurgeTrigger",
		Vector3(pad.x, top + 1.0, pad.z),
		Vector3(PURGE_PAD_SIDE, 2.0, PURGE_PAD_SIDE),
		_on_purge_enter, _on_purge_exit, floor_index)
	for hero: String in TowerGraph.HEROES:
		var rect := plan_room_rect(floor_index, "cell_%s" % hero)
		if rect.size == Vector2i.ZERO:
			continue
		var box := _cell_span(rect)
		_add_area("CellTrigger%s" % hero.capitalize(),
			Vector3((box["x0"] + box["x1"]) * 0.5, top + 1.0,
				(box["z0"] + box["z1"]) * 0.5),
			Vector3(box["x1"] - box["x0"] - 0.4, 2.0, box["z1"] - box["z0"] - 0.4),
			_on_cell_enter.bind(hero), Callable(), floor_index)

	# TWO LABELS AND NOT ONE, because a wall stands between the two rooms they speak
	# in and a `Label3D` is geometry: the corridor's line would be depth-culled from
	# the gallery and vice versa. Same construction as the receptacle's — see
	# `_build_label()` for why this is a world label and not a HUD toast.
	#
	# SMALLER AND HIGHER THAN THE RECEPTACLE'S, and that was found by looking rather
	# than reasoned: the receptacle stands at the end of a deep alcove you approach
	# from across the hall, so its 2.45 m banner is read at four metres. These two
	# live in a corridor where the spring arm puts the camera a metre from them, and
	# at the receptacle's size the first walkthrough was a screen full of the word
	# "open". Up near the ceiling and half the scale, they read as signage on a wall
	# instead of as a wall.
	var corridor := _cell_span(plan_room_rect(floor_index, "service_stair"))
	var gallery := _cell_span(plan_room_rect(floor_index, BLOCK_ROOM))
	_spine_label = _make_label("SpineLabel",
		Vector3((corridor["x0"] + corridor["x1"]) * 0.5, top + 3.6,
			float(corridor["z0"]) + 0.4),
		tr("THE FOUR SPINES — one door each"), floor_index)
	_cell_label = _make_label("CellLabel",
		Vector3((gallery["x0"] + gallery["x1"]) * 0.5, top + 3.6,
			float(gallery["z1"]) - 0.4),
		tr("CELL BLOCK"), floor_index)
	for sign: Label3D in [_spine_label, _cell_label]:
		sign.font_size = 30
		sign.outline_size = 9
		sign.pixel_size = 0.0022
		sign.width = 520.0


func _tick_press(delta: float) -> void:
	"""Run the crawl press. No state but its clock — it never opens and never shuts."""
	if _press == null:
		return
	_press_clock = wrapf(_press_clock + delta, 0.0, PRESS_PERIOD)
	_press.position.y = _press_base + press_y(_press_clock)


func _tick_spine_pads() -> void:
	"""
	Re-decide all four spine doors against the CURRENT hero, every frame.

	THE SAME CONTRACT THE SECURE DOOR HOLDS and for the same reason: E switches
	character where you stand and clears ability state, so the only honest question
	is who is standing here NOW. Nothing is buffered and nothing counts down —
	walking onto a pad as the wrong hero and pressing E is the intended solution.

	The label is written on every frame a pad is occupied, which is what makes a
	wrong hero DIAGNOSABLE ("this one wants Teibi") instead of merely refused.
	"""
	var here := _hero_name()
	for door: Dictionary in SPINE_DOORS:
		var gid := String(door["gate"])
		if not bool(_on_spine_pad.get(gid, false)):
			continue
		var wants := TowerGraph.identity_of(gid)
		# THE OPEN TEST NOW ASKS THE LOCKDOWN FIRST, and the order is the whole
		# scene: a door the protocol re-shut must refuse a wrong hero exactly as an
		# unopened one does, or the break-out is walked through by whoever happens
		# to be standing there.
		var locked := _lockdown.has(gid)
		if _is_open(gid) and not locked:
			_say_spine(tr("This way is open."))
			continue
		if here != wants:
			_say_spine(tr("%s ANSWERS TO %s.") % [
				gid.replace("_", " ").to_upper(), wants.to_upper()])
			continue
		# The right hero is standing here: lift containment on this one door, and
		# earn the gate itself if this is the first time through. Both are
		# idempotent, and doing them in this order is what lets a door that was
		# already in the opened set still cost a pad press during the protocol.
		_lockdown.erase(gid)
		if not _is_open(gid):
			_open(gid)
		_say_spine(tr("%s clears the way. It stays clear.") % wants.capitalize())
		_sfx("play_level_up")


func _place_spine(gate_id: String) -> void:
	"""
	Put one spine mass where its open fraction says. It only ever SINKS.

	Down, and not up, purely because the block is roofed — see THE CELL BLOCK above.
	Mesh and collision shape move together: a gate that opened only visually is the
	worst bug this file can have.

	Its shut height is `_gate_rest`, taken off the mesh the plan builder placed, so
	the mass animates from the y its own box actually had — on whatever storey the
	block is drawn on.
	"""
	var mesh: MeshInstance3D = _spine_meshes.get(gate_id)
	if mesh == null:
		return
	var open := float(_spine_open.get(gate_id, 0.0))
	mesh.position.y = float(_gate_rest.get(gate_id, 0.0)) - SPINE_TRAVEL * open
	var shape: CollisionShape3D = _spine_shapes.get(gate_id)
	if shape != null:
		shape.position.y = mesh.position.y
	_retire(mesh, shape, open >= 1.0)


func _retire(mesh: MeshInstance3D, shape: CollisionShape3D, done: bool) -> void:
	"""
	Hide and de-solidify a gate mass that has finished travelling.

	A MASS IS AS TALL AS ITS ROOM, so it has nowhere to go that is not somebody
	else's room. It fills its doorway floor to ceiling — that is what makes it a
	gate and not a hurdle — and the slab between two storeys is 0.4 m, so a fully
	sunk one ends up a four-metre block standing in the storey BELOW and a fully
	risen one a block standing in the storey ABOVE. That was invisible while the
	only gates that moved stood on the ground floor and under the open sky; phase 16
	filled the building to its roof, and every gate in it now has a room on the
	other side of the floor it disappears into.

	Nothing is lost by not drawing it: an opened gate's mass has already left the
	room it was in (its bottom is the ceiling, or its top is the floor), so from
	anywhere a player can stand it is gone either way. What this removes is only
	the leak into the neighbouring storey — and the collision that came with it.

	It is applied at the END of the travel and not at the start, because the tween
	IS the sentence the legibility language is making ("up = the world changed"),
	and `_apply_opened()` snaps a loaded save straight to 1.0, which is the case
	that matters.
	"""
	mesh.visible = not done
	if shape != null:
		shape.disabled = done


func _refresh_cells() -> void:
	"""
	Repaint every containment frame from the captive set, place a visual body in each
	occupied cell, and hide the staging unit once the authored rescue is done.

	THE ONE PLACE CAPTIVITY BECOMES GEOMETRY, the way `_apply_opened` is the one
	place an opened gate does. Idempotent, so `set_captive()` can just call it. The
	body is intentionally not part of the static box table: it is per-run
	population, and its lifecycle must follow this non-monotone set.
	"""
	for hero: String in _cell_frames:
		var frame: MeshInstance3D = _cell_frames[hero]
		frame.material_override = _material(
			COLOR_CELL if _captives.has(hero) else COLOR_CELL_FREED)
		_refresh_cell_body(hero)
	if _containment != null:
		_containment.visible = not _is_open(RESCUE_DONE)


func _refresh_cell_body(hero: String) -> void:
	"""Create or free the one visual-only model held in `hero`'s cell."""
	# Build-time geometry checks instantiate this scene without a shell parent. That
	# detached form has no room-wide captive source, so keep it the static interior
	# those checks measure; the live tower path always has the shell lifecycle.
	if _tower() == null:
		return
	var existing := _cell_bodies.get(hero) as Node3D
	if not _captives.has(hero) or _hero_has_live_holder(hero):
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		_cell_bodies.erase(hero)
		return
	if existing != null and is_instance_valid(existing):
		return
	_cell_bodies.erase(hero)

	var character_index := -1
	for index: int in PLAYER_SCRIPT.CHARACTERS.size():
		if String(PLAYER_SCRIPT.CHARACTERS[index]["name"]) == hero:
			character_index = index
			break
	if character_index < 0:
		return
	var scene_path := String(PLAYER_SCRIPT.CHARACTERS[character_index]["scene_path"])
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("TowerInterior: could not load captive model %s" % scene_path)
		return
	var floor_index := block_floor()
	if floor_index < 0 or floor_index >= _floors.size():
		return

	var body := scene.instantiate() as Node3D
	if body == null:
		return
	body.name = "%s%s" % [CAPTIVE_BODY_PREFIX, hero.capitalize()]
	# A jailed model is scenery. Disable any future scene-side processing so this
	# body can never acquire the player's walk/breathe animation by accident.
	body.process_mode = Node.PROCESS_MODE_DISABLED
	var stand := cell_stand(hero)
	stand.y = FLOOR_Y[floor_index]
	body.position = stand
	# Character scenes face -Z at their authored neutral rotation. The gallery is
	# on the +Z side of the cell row, so a half turn makes every captive face it.
	body.rotation.y = PI
	_floors[floor_index].add_child(body)
	_style_captive_model(body)
	_pose_captive_model(body)
	_cell_bodies[hero] = body


func _style_captive_model(node: Node) -> void:
	"""Match the shared character shading without adding player-only outlines."""
	if node is MeshInstance3D:
		ToonShading.apply_to_mesh(node)
		_no_shadow(node)
	for child: Node in node.get_children():
		_style_captive_model(child)


func _pose_captive_model(node: Node3D) -> void:
	"""Apply one authored, slumped idle pose; nothing here is animated later."""
	var model_body := node.get_node_or_null("Body") as Node3D
	if model_body == null:
		return
	model_body.rotation.x += deg_to_rad(-8.0)
	var limb_offsets := {
		"LeftArm": deg_to_rad(20.0), "RightArm": deg_to_rad(20.0),
		"LeftLeg": deg_to_rad(-8.0), "RightLeg": deg_to_rad(-8.0),
	}
	for limb_name: String in limb_offsets:
		var limb := model_body.get_node_or_null(limb_name) as Node3D
		if limb != null:
			limb.rotation.x += float(limb_offsets[limb_name])


func _hero_has_live_holder(hero: String) -> bool:
	"""Whether the synchronized room assignment still has a body for `hero`.

	The holder map is authoritative across peers. A holder's RemoteAvatar can be
	temporarily hidden while WebRTC negotiates (or until the lobby removes a failed
	member); that brief gap is benign because the containment field still marks the
	cell and the next heroes broadcast restores the static model. Do not key this on
	this peer's transport visibility, or cells would flicker and peers would disagree.
	"""
	var mp := get_tree().get_first_node_in_group("mp")
	return mp != null and mp.has_method("hero_holder") \
			and not String(mp.call("hero_holder", hero)).is_empty()


func _liberate(hero: String) -> void:
	"""
	Free whoever is in this cell. Performable by ANY hero — nothing here reads
	`hero_name()`, which is what "uniform cells" means in code.

	@param hero: The captive this cell holds.

	The freed hero rejoins the roster IMMEDIATELY, through one null-safe call: a
	player that has grown a captive set (phase 9) is told; today's player has not,
	so the call is skipped and nobody was ever locked out. That is the whole seam
	between this bead and the next, and it is deliberately one `has_method`.
	"""
	if not _captives.has(hero):
		return
	_captives.erase(hero)
	# The authored first rescue is the one liberation the tower remembers: the
	# staging goes, and it goes for good, across a relaunch.
	if hero == AUTHORED_CAPTIVE and not _is_open(RESCUE_DONE):
		_open(RESCUE_DONE)
	_refresh_cells()
	_say_cells(tr("%s IS FREE.") % hero.to_upper())
	_sfx("play_level_up")
	if _player != null and _player.has_method("hero_freed"):
		_player.call("hero_freed", hero)


# ---------------------------------------------------------------------------
# THE FULL-CUSTODY PROTOCOL — phase 11's half of the scene
# ---------------------------------------------------------------------------
#
# The scene itself is `player_controller`'s: it decides that the corporation has
# everybody, marches the party here and runs the recall clock. This file owns the
# two things the BUILDING does about it, and nothing else:
#
#   * RAISED CONTAINMENT while the scene runs (`begin_lockdown` / `end_lockdown`).
#     Every spine door is shut again, whatever a hundred earlier rescues opened, so
#     the break-out is the block's own lesson under a clock: read the door, switch to
#     the hero it names, stand on the pad. That is deliberately the game's verbs and
#     not a minigame — there is no new input and no new rule, only the old ones with
#     nothing already unlocked.
#   * THE SCAR (`apply_scar`), which is the one sanctioned exception to the graph's
#     edge-additive law: a survived protocol brings the block's wide doorway down
#     for good.
#
# WHERE THE STAND IS AND WHY IT IS NOT A CELL. The party wakes in the SERVICE
# CORRIDOR, on the wrong side of the spine wall — because a cell hangs off the
# gallery on an ungated edge (that is what "uniform cells" means), so a break-out
# that started in one would be three metres of walking and no scene at all. From the
# corridor the only way to a cell is through a door that asks for a name.

static func custody_stand() -> Vector3:
	"""
	Where the protocol stands the party up, in interior-local metres.

	THE MIDDLE OF THE SERVICE CORRIDOR, and it is DERIVED and no longer a literal:
	it was a bare `Vector3` in a file full of derived spacings, which is exactly the
	shape of constant that ends up 40 cm inside a wall the day a doorway moves — and
	phase 16 moved every doorway in this room 46 m upwards.

	The middle is the camera's doing rather than the drama's: facing +X
	(`SPAWN_FACING_Y`) the spring arm needs corridor behind it, and from either end
	it collapses into the back of the hero's head. The middle is also the furthest
	any point in the room can be from the four gate pads, so the scene does not open
	on a door's refusal line.

	Every clearance is re-derived and ASSERTED by `tower_interior_selfcheck` rather
	than trusted here — a stand inside a wall is a body shoved through it on the
	first frame. `y` is the storey's walking surface plus the same 0.2 m lift
	`cell_stand()` uses.
	"""
	var floor_index := block_floor()
	if floor_index < 0:
		return Vector3.ZERO
	var box := _cell_span(plan_room_rect(floor_index, "service_stair"))
	return Vector3((box["x0"] + box["x1"]) * 0.5, FLOOR_Y[floor_index] + 0.2,
			(box["z0"] + box["z1"]) * 0.5)


func begin_lockdown() -> void:
	"""
	Shut every spine door for the break-out scene. Idempotent.

	Slams rather than tweens: the doors coming down IS the protocol arriving, and a
	1.6 s close on a 35 s clock reads as the building being slow rather than as the
	corporation being fast.
	"""
	for door: Dictionary in SPINE_DOORS:
		var gid := String(door["gate"])
		_lockdown[gid] = true
		_spine_open[gid] = 0.0
		_place_spine(gid)
	_say_spine(tr("CONTAINMENT RAISED."))
	_say_cells(tr("FULL CUSTODY."))


func end_lockdown() -> void:
	"""
	Drop raised containment. The ordinary `_tick_gates` tween re-opens whatever the
	opened set actually earned, so nothing the player owned is lost by the scene.

	CALLED ON BOTH OUTCOMES, which is the landmine: a scene that ended in failure
	still has to leave the building in the state the opened set describes, because
	the Game Over screen's Play Again keeps the same profile.
	"""
	_lockdown.clear()
	_say_spine(tr("Containment released."))


func is_locked_down(gate_id: String) -> bool:
	"""Is this spine door re-shut by a running protocol? The check's window in."""
	return _lockdown.has(gate_id)


func apply_scar(scar_id: String) -> bool:
	"""
	Take an authored scar, permanently. The ONE place a scar becomes world state.

	@param scar_id: one of `TowerGraph.scar_ids()` — never a computed string.
	@return: true when the id was authored and is now recorded.

	IT RIDES THE MONOTONE OPENED SET, through `_open()` like every gate, and that is
	the deliberate storage choice: a scar is EARNED and PERMANENT, there is no verb
	that heals one, and the union's read-modify-write merge is exactly the write a
	crash between two frames must survive. (The captive set is the opposite kind of
	fact and stays out — see `_captives`. The guards are neither and are stored
	nowhere at all.)

	The geometry follows in the same call, so there is no window in which the world
	has taken a scar the building is not showing.
	"""
	if not TowerGraph.scar_ids().has(scar_id):
		return false
	_open(scar_id)
	_refresh_scar()
	_say_spine(tr("THE DOORWAY IS GONE."))
	return true


func _refresh_scar() -> void:
	"""
	Show and solidify the rubble iff the world has taken the scar it belongs to.

	The one place a scar becomes geometry, exactly as `_apply_opened` is for a gate
	and `_refresh_cells` is for a captive. Idempotent, and null-safe so an interior
	built without its scar box (there is none today) simply does nothing.
	"""
	if _scar_slab == null:
		return
	var taken := _is_open(TowerGraph.SCAR_CUSTODY)
	_scar_slab.visible = taken
	if _scar_shape != null:
		_scar_shape.disabled = not taken


# ---------------------------------------------------------------------------
# THE CAPTIVE SET — phase 9's seam, and the whole of it
# ---------------------------------------------------------------------------

func set_captive(hero: String, held: bool) -> void:
	"""
	Put a hero in his cell, or take him out of it.

	@param hero: One of `TowerGraph.HEROES`.
	@param held: true to hold him, false to release without the liberation beat.

	The verb systemic capture will call. Liberation itself is `_liberate`, which the
	cell volume fires — a capture puts somebody in, walking into the cell takes them
	out, and there is exactly one of each.
	"""
	if not TowerGraph.HEROES.has(hero):
		return
	if held:
		_captives[hero] = true
	else:
		_captives.erase(hero)
	_refresh_cells()


func is_captive(hero: String) -> bool:
	"""Is this hero in a cell right now?"""
	return _captives.has(hero)


func captives() -> Array:
	"""Every held hero, in `TowerGraph.HEROES` order — a fresh array, sorted stably."""
	var out: Array = []
	for hero: String in TowerGraph.HEROES:
		if _captives.has(hero):
			out.append(hero)
	return out


# ============================================================================
# SIGNAL HANDLERS — every one of them guards on the "player" group
# ============================================================================
#
# "player" means the LOCAL player and nothing else (CLAUDE.md). A remote teammate
# is a RemoteAvatar with no physics body and cannot reach here at all; what these
# guards actually exclude is the crocodile population, which will happily wander
# in through the front door and would otherwise trip every pad in the building.

func _on_hazard_touched(body: Node3D) -> void:
	"""A rotor bar swept through the player. Costs coins, via the ONE damage verb."""
	if not body.is_in_group("player") or not body.has_method("hit_by_crocodile"):
		return
	body.call("hit_by_crocodile")


func _on_demand_enter(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_on_demand_pad = true
	_attempt_demand()


func _on_demand_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_on_demand_pad = false


func _on_identity_enter(body: Node3D) -> void:
	if body.is_in_group("player"):
		_on_identity_pad = true


func _on_identity_exit(body: Node3D) -> void:
	if body.is_in_group("player"):
		_on_identity_pad = false


func _on_riddle_enter(body: Node3D, gate_id: String, digit: int) -> void:
	"""Remember which lock pad the player is on; `_tick_pads` decides what it means."""
	if body.is_in_group("player"):
		_riddle_on_pad[gate_id] = digit


func _on_riddle_exit(body: Node3D, gate_id: String, digit: int) -> void:
	"""...and forget it, unless another pad has already claimed the player."""
	if body.is_in_group("player") and int(_riddle_on_pad.get(gate_id, 0)) == digit:
		_riddle_on_pad[gate_id] = 0


func _on_spine_enter(body: Node3D, gate_id: String) -> void:
	if body.is_in_group("player"):
		_on_spine_pad[gate_id] = true


func _on_spine_exit(body: Node3D, gate_id: String) -> void:
	if body.is_in_group("player"):
		_on_spine_pad[gate_id] = false


func _on_cell_enter(body: Node3D, hero: String) -> void:
	"""
	Somebody walked into a cell. If it holds a captive, that is the rescue.

	No pad, no prompt and no hero test: reaching the cell IS the action, which is
	the only shape `tower_selfcheck`'s liberation clause admits — a cell hangs off
	its gallery on an ungated edge precisely so that whoever got there can do this.

	...WITH ONE EXCEPTION, AND IT IS "NO SOLO ESCAPE" (bead godot-test1-3iy.10). A
	benched multiplayer player plays as their OWN captive inside this block, so
	walking back into their own recess would be a rescue performed on themselves —
	the one liberation the owner's ruling forbids. Narrow on purpose: it asks the
	body whether it is serving the prison role AND whether this is its own cell, so
	a prisoner still frees every CELLMATE (that is the block's second system) and no
	ordinary rescue anywhere in the game changes by a frame.
	"""
	if not body.is_in_group("player"):
		return
	# `"x" in body`, never `bool(body.get("x"))`: `get()` answers null for a body that
	# has no such property (every probe player in the self-checks, and the real one
	# before this bead), and `bool(null)` is not a constructor GDScript has - it
	# throws, and a throw inside an `Area3D` callback swallows the liberation.
	# ASKED OF THE ENTERING BODY, not of `_hero_name()`. That helper answers off the
	# interior's cached `_player`, which is written in `_process` — so on the first
	# frame after a build (and in every harness that drives this callback directly)
	# it is still empty, and the refusal would silently not refuse. The body that
	# walked in is the body whose identity this rule is about.
	if "prisoner_active" in body and bool(body.prisoner_active) \
			and body.has_method("hero_name") and String(body.call("hero_name")) == hero:
		return
	_liberate(hero)


func _on_purge_enter(body: Node3D) -> void:
	# PLAIN OVERLAP, like every other pad in this building. WHO may work it is
	# `_tick_purge()`'s question — see `_purge_body`.
	if body.is_in_group("player"):
		_purge_body = body


func _on_purge_exit(body: Node3D) -> void:
	if body == _purge_body:
		_purge_body = null


func _tick_purge(delta: float) -> void:
	"""
	The vent purge: scatter the pack around every teammate. See `purge_pad()`.

	Polled like every other pad in this building, and it fires the moment the
	cooldown allows rather than on a press — the block has no new input, which is the
	same rule the break-out scene is built on.

	NULL-SAFE AND ROOM-ONLY. Solo, `peer_markers()` answers `null` and this is one
	group lookup and a return: there is no team outside to open anything for, and
	firing it on the player's own pack would turn a cell into a panic button.

	IT ASKS `peer_markers()` AND NOT `peer_positions()`, which looks like the same
	query and is not: that one is deliberately MASTER-ONLY and answers `null` to
	everybody else, so a purge built on it would have been dead for three prisoners
	out of four - the silent kind of dead, with a pad that lights up and does
	nothing. `peer_markers()` answers for every member of the room. It allocates and
	is documented for HUD tick rates; this asks it once per PURGE_COOLDOWN.
	"""
	_purge_cooldown = maxf(0.0, _purge_cooldown - delta)
	if _purge_body == null or not is_instance_valid(_purge_body) or _purge_cooldown > 0.0:
		return
	# THE PAD IS THE PRISONER'S. A rescuer crosses this gallery on every ordinary
	# liberation in the game, and the purge is the bench's compensation for having no
	# field play at all — a party that could stand on it in passing would be handed
	# the same opening for free. Asked of the standing body every frame, so leaving
	# the role while standing here stops the pad on the spot.
	if not ("prisoner_active" in _purge_body) or not bool(_purge_body.prisoner_active):
		return
	var mp := get_tree().get_first_node_in_group("mp")
	if mp == null or not mp.has_method("peer_markers") or not mp.has_method("request_croc_flee"):
		return
	var markers: Variant = mp.call("peer_markers")
	if markers == null or not (markers is Array):
		return
	var fired: int = 0
	for entry: Variant in (markers as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var where: Variant = (entry as Dictionary).get("pos", null)
		if typeof(where) != TYPE_VECTOR3:
			continue
		# `tracks_player` FALSE: the position named is a TEAMMATE's, not this body's.
		# Left true, a purge fired by a prisoner who happens to be the room master
		# would apply locally with the caster set to the player in the cell — the
		# pack would run from the tower, which is roughly towards the teammate it was
		# bought to help.
		if bool(mp.call("request_croc_flee", where as Vector3, PURGE_FLEE_SECONDS,
				PURGE_FLEE_RADIUS, false)):
			fired += 1
	if fired == 0:
		return
	# ponytail: `request_croc_flee()` answers true once the LOCAL pass has run, so a
	# non-master whose channel to the master is still negotiating spends a cooldown
	# on a wave that reached nobody's crocodiles. The ceiling is one wasted press
	# per mesh hiccup and the pad re-arms in PURGE_COOLDOWN; the upgrade path is a
	# send-status return from that function, which every existing caller would have
	# to be re-read against (it deliberately answers "the room has taken this over",
	# not "the packet left").
	_purge_cooldown = PURGE_COOLDOWN
	_say_cells(tr("VENT PURGE — THE PACK SCATTERS."))
	_sfx("play_level_up")


func _on_checkpoint_enter(body: Node3D) -> void:
	"""
	The checkpoint. Reaching it is the whole interaction — no plate to press.

	It goes in the SAME opened set as the two gates, because that is what a
	checkpoint is: a stop the tower remembers you reached. Phase 5 persists all
	three through one union merge precisely because they are one kind of thing.
	"""
	if not body.is_in_group("player") or _is_open(GATE_CHECKPOINT):
		return
	_open(GATE_CHECKPOINT)
	_light_checkpoint()
	_say(tr("CHECKPOINT"))
	_sfx("play_level_up")


func _on_lift_stop_enter(body: Node3D) -> void:
	"""
	The labyrinth's lift stop is earned by standing on it. Idempotent, local player.

	A CUE AND NO TEXT. Every label in this building belongs to a room that has one
	(the receptacle's, the corridor's, the gallery's) and the maze has none — a line
	written to the ground floor's label 32 m below is a line nobody reads, and a
	Label3D on a landing is a draw call plus a translation row for a message the
	phase-7 menu will state properly anyway.
	"""
	if not body.is_in_group("player") or _is_open(TowerGraph.ENTRY_LIFT_MAZE):
		return
	_open(TowerGraph.ENTRY_LIFT_MAZE)
	_sfx("play_level_up")


# ============================================================================
# GUARDS
# ============================================================================

func _on_tower_doorway(_body: Node3D) -> void:
	"""
	The local player crossed the doorway. Put the population back.

	@param _body: the entering body, already filtered to group "player" by the
	              shell — a crocodile in the doorway must not reset anything.

	FIRES IN BOTH DIRECTIONS, because an `Area3D` cannot tell walking in from
	walking out and does not need to: "leave and come back and the guards are at
	their posts" is the acceptance, and re-placing them on the way out costs one
	free-and-rebuild of the whole population at the one moment nothing is looking
	at it.
	"""
	reset_guards()


func reset_guards() -> void:
	"""
	Free every guard and stand a fresh one on each post in `guard_posts_table()`.

	THE WHOLE PERSISTENCE CONTRACT FOR THE POPULATION, and it is implemented by
	what is NOT here: nothing reads a save, nothing writes one, and no guard state
	survives this call. "Structure persists; population resets" is one monotone
	union set (the opened gates, on the shell) plus this function.

	IDEMPOTENT AND SAFE MID-CHASE. A guard that is chasing, biting, paused, slept
	by the LOD manager or being remote-driven is simply freed with everything it
	was holding; the replacement is a new body with a new `_ready()`, so there is
	no state to reconcile and no half-reset to get wrong.

	Public because `_ready()` defers it (see the note there) and because the
	self-check drives it directly rather than waiting on an idle frame.
	"""
	# WORLD SPACE IS THE POINT OF BEING IN THE TREE: `set_confinement()` below takes
	# a world centre, so a detached interior would leash every guard to a box around
	# the origin. Nothing in the shipped game can reach here detached (the deferral
	# in `_ready()` and the door signal both run in-tree); this is the standalone
	# degrade the project asks for rather than an error nobody can act on.
	if not is_inside_tree():
		return
	if is_instance_valid(_guards):
		# `remove_child` BEFORE `queue_free`, and it is not tidiness: a queued node
		# keeps its name until the frame ends, so adding the replacement first would
		# hit a duplicate "Guards" and the engine would silently rename the NEW
		# container. Every `get_node("Guards")` in the building — and in the check —
		# would then keep answering with the corpse.
		var retired := _guards
		remove_child(retired)
		retired.queue_free()
	_guards = Node3D.new()
	_guards.name = "Guards"
	add_child(_guards)

	var scene := guard_scene()
	if scene == null:
		return
	for authored: Dictionary in guard_posts_table():
		var guard := scene.instantiate() as Node3D
		# Deterministic, and stable across a reset: `croc_id_for()` hashes the node
		# name, so the same post is the same id every time the population is rebuilt
		# — which is what a multiplayer relay needs from a body it did not spawn.
		guard.name = "TowerGuard%s" % String(authored["name"])
		var post: Vector3 = authored["post"]
		guard.position = post + Vector3(0.0, GUARD_SPAWN_LIFT, 0.0)
		# THE CALL-ORDER CONTRACT (`setup_as_boss` / the hunter spawner / the
		# platform spawner, all the same shape): `species` goes in BEFORE
		# `add_child`, because `_ready()` is where it is resolved into `spec` and
		# where the size/speed rolls that READ that spec happen. Assigned after, a
		# guard would roll a crocodile's numbers onto its body and every per-frame
		# path would read the wrong row.
		guard.set("species", GUARD_SPECIES)
		_guards.add_child(guard)
		# ...and the leash AFTER, exactly as `spawn_platform_crocodiles` does:
		# `set_confinement` is a plain setter no per-frame path reads until the
		# body's first physics tick, and it wants WORLD coordinates, which only
		# exist once the node is in the tree.
		if guard.has_method("set_confinement"):
			var centre: Vector3 = authored["patrol_center"]
			guard.call("set_confinement", global_position + centre,
					authored["patrol_half"])


func guard_posts() -> Array:
	"""
	Every live guard's authored post name and current global position.

	@return: a fresh Array of { "name": String, "position": Vector3 }.

	The seam the self-check measures the population through, so it counts BODIES
	IN THE TREE rather than rows in `guard_posts_table()` — a spawner that silently
	stopped instancing would otherwise be reported by the table it was meant to be
	standing up.
	"""
	var out: Array = []
	if not is_instance_valid(_guards):
		return out
	for child in _guards.get_children():
		if child is Node3D:
			out.append({
				"name": String(child.name),
				"position": (child as Node3D).global_position,
			})
	return out


func setback_point() -> Vector3:
	"""
	Where a guard's setback drops the player: the last checkpoint they activated
	inside this tower, or the doorway if they have not activated one yet.

	@return: a WORLD position, standable, on the storey the checkpoint is on.

	"THE LAST ACTIVATED CHECKPOINT" IS THE OPENED SET, not a second field. There is
	one checkpoint in the v1 interior and it is `GATE_CHECKPOINT` in the same
	monotone union set the two gates live in, so this asks the set the same way
	`_apply_opened()` does — and phase 7's extra stops become extra entries there
	plus one more branch here, with nothing new to persist.

	Called by `player_controller` through a null-safe group lookup, so a run with
	no tower in the tree at all never reaches this.
	"""
	return global_position + (checkpoint_stand() if _is_open(GATE_CHECKPOINT)
			else entry_stand())


# ============================================================================
# VISIBILITY
# ============================================================================

func _update_visibility() -> bool:
	"""
	Draw only what is worth drawing: nothing at all when the player is far, and
	the current storey +/- 1 when they are near.

	@return: true when the interior is being drawn (and therefore worth animating).

	THE +/-1 WINDOW FINALLY BITES SINCE PHASE 14. With two storeys it hid nothing and
	was written anyway, because `_floor_visible` is a pure function of two integers
	and a check can drive it at any storey count; with five it is the difference
	between three storey meshes on screen and five. Neither the policy nor this
	function changed to get there — the storeys did.
	"""
	if _player == null:
		return visible
	var here := global_position
	var there := _player.global_position
	var local := there - here
	var near := Vector2(local.x, local.z).length() <= DRAW_RADIUS
	visible = near
	# THE INDOOR CAMERA, off the offset this function already had in hand. The
	# player owns the knob (`spring_length` — nothing may write `camera.position`);
	# the building only answers "are you inside my walls?", which is the one
	# question it is qualified to answer. Null-safe like every other seam here, and
	# idempotent on the player's side, so driving it unconditionally is free.
	if _player.has_method("set_indoor_camera"):
		_player.call("set_indoor_camera", near and inside_walls(local))
	if not near:
		return false
	var current := current_floor(local.y)
	for i in _floors.size():
		_floors[i].visible = _floor_visible(i, current)
	return true


static func inside_walls(local: Vector3) -> bool:
	"""
	Is this interior-local point within the building's walls — i.e. in a ROOM?

	The footprint is the ENVELOPE's inner faces (`TowerPlans.PLAN_HALF` on both
	axes) and the ceiling is the top of its wall: everything the interior builds —
	the keep, and since phase 14 the hand-planned storeys and the annulus they
	roofed — lives inside that box, so there is nothing to enumerate and a new room
	joins for free. The height term is what keeps Windman's Air Rush from reporting
	"indoors" while he is sightseeing over the parapet.

	IT WAS THE 20 m KEEP UNTIL PHASE 14, and left that way it would have answered
	"outdoors" in every one of the twenty-eight new offices: the indoor boom never
	shortens, and the spring arm collapses into the back of a head in a 4.6 m room.
	(codex review, 2026-08-29.) There is no keep to be the narrowest indoor space
	any more (bd godot-test1-dn8) — the tightest room in the building is whichever
	planned storey draws it, which is why check 4 sizes the boom against the PLANS
	and not against a constant.

	Pure, allocation-free and three compares — `biome_at()`'s idiom, and safe to
	call every tick.
	"""
	return absf(local.x) <= TowerPlans.PLAN_HALF and absf(local.z) <= TowerPlans.PLAN_HALF \
			and local.y <= TowerShell.WALL_HEIGHT


static func current_floor(local_y: float) -> int:
	"""
	Which storey a height belongs to, in interior-local metres.

	The HIGHEST `FLOOR_Y` whose walking surface, less the hysteresis, is at or below
	this height — so standing on a slab answers that slab's storey, and standing on
	the ramp just under its lip answers the storey below rather than flickering
	between the two. Floor 0 is the floor of last resort, so a height below the
	ground (a player falling past the building) still names a real container.

	Pure, allocation-free and a walk of ten compares: it runs every `_process`.
	"""
	var out := 0
	for i: int in FLOOR_Y.size():
		if local_y >= FLOOR_Y[i] - FLOOR_HYSTERESIS:
			out = i
	return out


static func zone_at(local: Vector3) -> String:
	"""
	Which ROOM or MAZE CELL an interior-local point stands in — "" for none.

	@param local: A point in the interior's own frame.
	@return: `"<floor>:<room letter>"` inside a planned room, `"<floor>:<col>,<row>"`
	        on a corridor or maze cell, and `""` in a wall or off the grid.

	THE ANTI-STALL TIMER'S PROGRESS SIGNAL, and the shape of the key is the whole of
	it (bd godot-test1-kox, codex refinement 2). A ROOM COLLAPSES TO ONE KEY because
	a player pacing a room they have already searched is stuck and must still get
	help — key it by cell and every step across the carpet would read as progress and
	reset the timer forever. A CORRIDOR OR MAZE CELL IS ITS OWN KEY because that is
	the grain the labyrinth is drawn at: there are no rooms up there, and a new cell
	really is somewhere new.

	Pure and allocation-light (one small String), which is what lets the minimap ask
	it on its 5 Hz tick.
	"""
	var floor_index := current_floor(local.y)
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return ""
	# The inverse of `_grid_x` / `_grid_z`: which cell of the 40 x 40 plan this is.
	var col := floori((local.x + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL)
	var row := floori((local.z + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL)
	if col < 0 or col >= TowerPlans.PLAN_GRID or row < 0 or row >= TowerPlans.PLAN_GRID:
		return ""
	var ch := _plan_char(plan["rows"], Vector2i(col, row))
	if ch == TowerPlans.WALL_CHAR:
		return ""
	if plan["rooms"].has(ch):
		return "%d:%s" % [floor_index, ch]
	return "%d:%d,%d" % [floor_index, col, row]


static func _floor_visible(index: int, current: int) -> bool:
	"""
	The gating policy itself: the current storey and every storey it TOUCHES.

	Adjacency is read out of `FLOOR_NEIGHBOURS` rather than computed as
	`absi(index - current) <= 1`. That table exists because of the keep's MEZZANINE,
	which hung two indices under floor 2's slab and made index distance lie; bead
	`godot-test1-dn8` demolished the keep, so the table is plain adjacency today and
	the arithmetic would give the same answers. It stays a table anyway: the next
	irregular storey should be one row of data and not a rewrite of this function.

	At most THREE storey meshes are drawn — yourself, the one under you and the one
	over you. It was four from storey 3 while the mezzanine existed. `DRAW_BUDGET`
	counts meshes BUILT, not drawn, so that number is unaffected either way.
	"""
	if index == current:
		return true
	return FLOOR_NEIGHBOURS[current].has(index)


# ============================================================================
# SMALL HELPERS
# ============================================================================

func _hero_name() -> String:
	"""The standing hero's name, or "" when there is no player to ask."""
	if _player == null or not _player.has_method("hero_name"):
		return ""
	return String(_player.call("hero_name"))


func _phase_reach() -> float:
	"""
	The standing hero's Phase Step reach, in metres — 0 for anyone but Primm.

	Asked of the PLAYER rather than recomputed here, because the same expression is
	what `_ability_primm` actually blinks with. A gate that recomputed the balance
	formula would be a second copy of it, and the two would drift the first time
	Long Step is retuned.
	"""
	if _player == null or not _player.has_method("phase_reach"):
		return 0.0
	return float(_player.call("phase_reach"))


func _say(text: String) -> void:
	"""Put a line on the receptacle's label."""
	if _label != null:
		_label.text = text


func _say_spine(text: String) -> void:
	"""Put a line on the service corridor's label, over the four spine doors."""
	if _spine_label != null and _spine_label.text != text:
		_spine_label.text = text


func _say_cells(text: String) -> void:
	"""Put a line on the cell gallery's label."""
	if _cell_label != null:
		_cell_label.text = text


func _sfx(method: String) -> void:
	"""Fire a synthesized sound, if there is a sound manager and it knows this one."""
	var sound := get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method(method):
		sound.call(method)


static func merged_mesh(group: Array) -> ArrayMesh:
	"""
	Every box in `group`, welded into one `ArrayMesh` of at most three surfaces.

	@param group: `boxes()` entries, all of one storey.
	@return: A fresh ArrayMesh — WALLS first, then matte, then emissive, each
	        omitted when that storey has none of that kind.

	THREE SURFACES AND NOT ONE, because a material property is not a vertex one and
	these boxes disagree about two of them. Emissive is the older split: a light
	panel and a stone wall cannot share a surface however similar their vertices are.
	TRANSPARENCY is the second (bead godot-test1-oht): Air Sight makes the walls of
	your storey translucent and leaves its floor, its ceiling and its gates solid, so
	the walls need a surface of their own to swap a material onto.

	WALLS ARE FIRST ON PURPOSE, and it is the contract `set_xray()` and the
	self-check both read: a storey that has any wall carries it as surface 0.

	Three is still the floor and not a per-box cost — every other difference between
	these boxes (colour, size, the ramp's tilt) is baked into the vertices, so a
	storey costs three draw calls whether it is four boxes or forty, and the third is
	the WHOLE price of the ability (see `SURFACE_BUDGET`).
	"""
	var out := ArrayMesh.new()
	for kind: int in [SURFACE_WALL, SURFACE_MATTE, SURFACE_GLOW]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for box: Dictionary in group:
			if surface_kind(box) != kind:
				continue
			any = true
			_emit_box(tool, box)
		if not any:
			continue
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1,
				_batch_material(kind == SURFACE_GLOW, kind == SURFACE_WALL))
	return out


## The three batch surfaces, in the order `merged_mesh` emits them.
enum { SURFACE_WALL, SURFACE_MATTE, SURFACE_GLOW }


static func surface_kind(box: Dictionary) -> int:
	"""
	Which of a storey's three surfaces one box belongs on.

	@param box: A `boxes()` entry.
	@return: `SURFACE_WALL`, `SURFACE_MATTE` or `SURFACE_GLOW`.

	`wainscot` IS THE WALL TAG and no second one was invented: the flag already means
	"this prism is a planned wall run" — it is what `_emit_box` splits a skirting
	board off the bottom of, and `_plan_walls` is the only thing in the building that
	sets it. A slab, a pad, a lintel and a ramp deck do not carry it and so cannot go
	translucent. Public because the self-check derives the same answer independently
	rather than reading `_wall_surfaces` back.
	"""
	if GLOW_COLORS.has(box["color"]):
		return SURFACE_GLOW
	return SURFACE_WALL if bool(box.get("wainscot", false)) else SURFACE_MATTE


static func _emit_box(tool: SurfaceTool, box: Dictionary) -> void:
	"""
	Append one box's triangles to a surface, in interior space and carrying its own
	colour — split into a wainscot band and the wall above it when it asks for one.

	THE SPLIT IS HERE AND NOT IN THE BOX TABLES, and that is bead 99j's whole
	economy. A skirting board is two prisms of one wall, not two walls: emitted here
	it costs the vertices it draws and NOTHING else — no second entry in
	`plan_boxes()` (so `PLAN_BOX_BUDGET`, which exists to catch walls that stopped
	merging, keeps measuring exactly that), no second `CollisionShape3D` on the
	storey's one body, and no second name for `tower_selfcheck` to reconcile. Split
	along the flat top of the band, so the two prisms share a face and there is
	nothing to z-fight; a rotated or too-short box declines the split and is emitted
	whole, because a band taller than the wall it skirts is just a repaint.
	"""
	if bool(box.get("wainscot", false)) and not box.has("rot") \
			and box["size"].y > WAINSCOT_HEIGHT * 2.0:
		var size: Vector3 = box["size"]
		var pos: Vector3 = box["pos"]
		var foot := pos.y - size.y * 0.5
		var band := box.duplicate()
		band.erase("wainscot")
		band["size"] = Vector3(size.x, WAINSCOT_HEIGHT, size.z)
		band["pos"] = Vector3(pos.x, foot + WAINSCOT_HEIGHT * 0.5, pos.z)
		band["color"] = COLOR_WAINSCOT
		_emit_box(tool, band)
		var upper := box.duplicate()
		upper.erase("wainscot")
		upper["size"] = Vector3(size.x, size.y - WAINSCOT_HEIGHT, size.z)
		upper["pos"] = Vector3(pos.x, pos.y + WAINSCOT_HEIGHT * 0.5, pos.z)
		_emit_box(tool, upper)
		return
	var arrays: Array = _box_mesh(box["size"]).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(box["rot"]) if box.has("rot") else Basis.IDENTITY
	var placed := Transform3D(basis, box["pos"])
	var color: Color = box["color"]
	# THE FLOOR IS THE ONE FACE THAT DIFFERS FROM ITS BOX. A slab's underside is the
	# ceiling of the storey below and must stay off-white, while the face you walk on
	# is carpet — so a slab declares `top_color` and its UP-facing vertices take it.
	# The alternative was a carpet box per slab: same colour, one more box, one more
	# name, and a hairline of z-fight to tune. Read off the untransformed normal
	# because a box carrying `top_color` is never tilted.
	var top_color: Color = box.get("top_color", color)
	for i: int in indices:
		# CONVERTED, and it is not a nicety. `albedo_color` is authored in sRGB and
		# the engine converts it; a VERTEX colour is taken as linear and is not. Feed
		# the palette straight in and a batched box comes out visibly paler than the
		# same colour on an unbatched one — the hazard orange washed out to a custard
		# yellow, which is the sort of drift that makes a colour language stop
		# meaning anything.
		var n := normals[i]
		var face: Color = top_color if n.y > 0.5 else color
		var shade := _face_shade(n)
		tool.set_color(Color(face.r * shade, face.g * shade,
				face.b * shade).srgb_to_linear())
		tool.set_normal(basis * n)
		tool.add_vertex(placed * verts[i])


static func _face_shade(normal: Vector3) -> float:
	"""
	How bright one face of a box is, baked into its vertices.

	@param normal: The box-local face normal — axis-aligned, because the only tilted
	        thing in this building is the ramp and a ramp's deck is its top either way.
	@return: A multiplier for the face's colour.

	THE BATCH IS UNSHADED (see `_batch_material`), so without this every box would be
	one flat silhouette of its own colour and a white corridor would have no corners
	in it at all. Baking one tone per face into the vertex colours is how a cel-shaded
	model gets its form and it is what the interior does now: an even, shadowless,
	always-identical light that owes nothing to where the sun is or whether there is a
	roof overhead. It is also free — the vertices were being written anyway.

	SHALLOW ON PURPOSE. These are the gentlest ratios that still separate two white
	walls meeting at a corner; a dramatic ramp would put the dark corners back, which
	is the exact thing bead 99j exists to remove. `INTERIOR_MIN_LUMINANCE` in the
	self-check is the palette's darkest colour times the darkest factor here, so
	deepening these is a change that file will notice.
	"""
	if normal.y > 0.5:
		return 1.0
	if normal.y < -0.5:
		return 0.78
	return 0.90 if absf(normal.x) > 0.5 else 0.84


static func _batch_material(glow: bool, wall: bool = false) -> StandardMaterial3D:
	"""
	The batch's three materials, cached beside the per-box ones.

	Keyed by a colour that is not in the palette above (so the two caches cannot
	collide) — the material's own albedo is white and unused, because
	`vertex_color_use_as_albedo` is what actually colours these surfaces.

	THE WALL ONE IS A THIRD OBJECT WITH IDENTICAL SETTINGS, which is the only reason
	it exists: it renders exactly like the matte one, and having its own identity is
	what lets `_ready()` find the wall surfaces to swap without counting indices, and
	what lets `ToonShading`'s cache and the self-check's material cap keep saying
	something true. Sharing the matte object instead would have made Air Sight
	dissolve the floor slabs with it.
	"""
	var key := Color(0.0, 1.0, 0.0) if wall \
			else (Color(0.0, 0.0, 1.0) if glow else Color(0.0, 0.0, 0.0))
	var hit: StandardMaterial3D = _materials.get(key)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	# BOTH HALVES ARE UNSHADED, and since bead 99j that is the interior's whole
	# lighting model rather than a light-panel special case.
	#
	# The emissive half never had a choice: emission is a material property and cannot
	# come from a vertex colour, so the albedo has to BE what you see. The matte half
	# joined it because nothing else can light a vertex-coloured surface in its own
	# colour — additive emission is one constant for the whole surface and washes the
	# off-white, the mint and the wainscot toward the same white, and multiplicative
	# emission multiplies by the emission TEXTURE (black when unset), not the albedo.
	#
	# So the batch is lit the way a cel-shaded model is: the shading is BAKED INTO THE
	# VERTEX COLOURS, one flat tone per face (`_emit_box`). That is the Severance floor
	# exactly — even, shadowless, no dark corners, the same at every hour and under
	# every roof — and it costs no light, no shadow pass, no second surface and no draw
	# call. `diffuse_mode` and the rim stay set so `ToonShading` still declines to
	# duplicate this material; an unshaded material ignores both.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = mat
	return mat


static func xray_material() -> StandardMaterial3D:
	"""
	The wall material's see-through twin, cached process-wide like every other
	material in here.

	ALPHA RIDES `albedo_color`, NOT THE VERTEX COLOURS. `vertex_color_use_as_albedo`
	multiplies the two, and `_emit_box` writes fully opaque vertices; putting the
	alpha here means one duplicated material carries the whole effect and not one
	re-emitted vertex anywhere. The rest of the material is inherited by `duplicate()`
	from the wall batch's own — unshaded, vertex-coloured, toon-compatible — so a wall
	going translucent changes exactly one thing about how it renders.

	`ponytail:` fill-rate is the known ceiling. Transparency is not free on web
	`gl_compatibility` and this makes every wall of one storey an overlapping
	transparent surface for the duration; it is a short timed window on ONE storey
	(the others are hidden by the visibility gate), which is why it is affordable.
	If F3 ever shows it, the upgrade path is a depth-tested cutout rather than blend.
	"""
	var hit: StandardMaterial3D = _materials.get(XRAY_KEY)
	if hit != null:
		return hit
	var mat: StandardMaterial3D = _batch_material(false, true).duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_color = Color(1.0, 1.0, 1.0, XRAY_ALPHA)
	_materials[XRAY_KEY] = mat
	return mat


## The x-ray material's cache key — a fourth colour outside the palette, for the
## same reason as `_batch_material`'s three.
const XRAY_KEY := Color(1.0, 0.0, 0.0, 0.5)


func set_xray(on: bool) -> void:
	"""
	Make this building's WALLS translucent, or put them back.

	@param on: true to see through them, false to restore.

	WINDMAN'S AIR SIGHT (bead godot-test1-oht), and the whole of it on this side. The
	swap is two material references per storey down `_wall_surfaces` — no per-box
	work, no rebuild, no node created or freed, and nothing at all touched while the
	ability is off.

	WALLS ONLY, BY CONSTRUCTION rather than by a filter here: `_wall_surfaces` was
	resolved in `_ready()` from the wall batch material's own identity, so the floor
	slabs (whose undersides are the ceiling below you), the ramp decks and every gate
	set piece are not in the list and cannot be reached from this function. You look
	through the walls of your storey; the building keeps its floors and its gates.

	`ponytail:` EVERY storey's walls are swapped, not just the one you are on (codex
	review). Deliberate, and the answer is what stays opaque: the slabs do, so a
	neighbouring floor's translucent walls are behind a solid ceiling and you cannot
	see them — "your storey" is delivered by the floors, never by this list. It also
	means walking up a ramp mid-ability needs no re-swap and no per-frame floor
	tracking, and `_update_visibility` has already culled all but three or four
	storeys, so the fill rate this could save is a fraction of a cost that is already
	the ability's known ceiling (see `xray_material`). Filter by `current_floor()`
	here if that ever measures.

	Idempotent, and safe to call on an interior that is being torn down — the
	`is_instance_valid` guard is there because the tower streams out with the terrain
	and a running ability outlives it by up to its own duration.
	"""
	_xray_on = on
	var swap: Material = xray_material() if on else null
	for pair: Array in _wall_surfaces:
		var mesh: MeshInstance3D = pair[0]
		if not is_instance_valid(mesh):
			continue
		mesh.set_surface_override_material(int(pair[1]), swap)


func xray_active() -> bool:
	"""Whether Air Sight is currently showing through this building's walls."""
	return _xray_on


static func _no_shadow(node: GeometryInstance3D) -> void:
	"""
	Take one interior mesh out of the directional shadow pass.

	MEASURED, and the single biggest thing this file does for the frame budget: a
	walk through the entry hall costs 33.7 ms a frame with the interior casting
	shadows and 31.4 ms without, on a 29.7 ms bare-shell baseline (perf_overlay,
	desktop, 1280x720, 2026-08-28) — i.e. shadow casting was more than half of the
	interior's entire cost. It is 28 extra draws in the shadow pass for a building
	whose every room is already in shadow: the enclosed hall has the upper slab over
	it, and the two open storeys sit at the bottom of an 11 m parapet. THE SHELL
	STILL CASTS, so the tower's own shadow on the field is unchanged; what is gone
	is furniture shadowing furniture inside a dark room.

	A purely invisible optimization, so it is global rather than web-gated
	(CLAUDE.md's performance conventions).
	"""
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_hazard_child(mesh: MeshInstance3D, size: Vector3) -> void:
	"""
	Hang a swept part's hazard volume off the mesh itself, so the two move as one.

	The rotor bars get theirs from `_make_rotor` (they hang off a pivot instead,
	because a rotation has to sweep both); a linear part has no pivot to share, and
	parenting the `Area3D` to the mesh is the smaller of the two ways to keep what
	you see and what hurts you in the same place.
	"""
	var hazard := Area3D.new()
	hazard.name = "%sHazard" % mesh.name
	hazard.monitorable = false
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	hazard.add_child(shape)
	hazard.body_entered.connect(_on_hazard_touched)
	mesh.add_child(hazard)


static func _add_shape(body: StaticBody3D, box: Dictionary) -> void:
	"""One collision shape for a batched box — the mesh merged, the collider did not."""
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box["size"]
	shape.shape = box_shape
	shape.position = box["pos"]
	if box.has("rot"):
		shape.rotation = box["rot"]
	shape.name = "%sShape" % box["name"]
	body.add_child(shape)


static func _box_mesh(size: Vector3) -> BoxMesh:
	"""A BoxMesh of exactly this size — `TowerShell._box_mesh`'s reasoning."""
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _self_light(mat: StandardMaterial3D, tint: Color) -> void:
	"""
	Make one PER-COLOUR interior material light itself, so nothing here is dark.

	@param mat: The material to light.
	@param tint: The colour it is painted, which is also the colour it glows.

	BEAD 99j. The shell was sealed in phase 13, which took the key light and the sky
	out of every room; what was left was ambient, and the interior read as black. The
	bead's direction was "no per-room OmniLights" — a real light under the slab is a
	shadow pass on `gl_compatibility`, which is the renderer this building already
	gates its geometry for — so the surfaces light THEMSELVES instead.

	A material that knows its own colour can do that with plain ADDITIVE emission in
	that colour: it keeps its diffuse shading and gains a floor under it, so a gate
	mass still reads as a shaped solid and never as a silhouette. `EMISSION_OP_MULTIPLY`
	is NOT the way to spend a vertex colour here and was the first thing tried:
	`emission_operator` combines the emission colour with the emission TEXTURE, not
	with the albedo, and an unset emission texture samples BLACK — so a multiply
	material emits nothing at all. The batch's vertex-coloured surface therefore takes
	a different route entirely; see `_batch_material`.
	"""
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = INTERIOR_EMISSION


static func _material(color: Color) -> StandardMaterial3D:
	"""
	The one material of this colour, for the life of the process.

	Its own cache rather than the shell's so a colour can never mean two different
	materials, but the same contract: never a duplicate per instance, and ALREADY
	`DIFFUSE_TOON` so `ToonShading.apply_to_mesh()` skips it instead of making one.
	`GLOW_COLORS` decides emissive; there are no `Light3D`s in this building.
	"""
	var hit: StandardMaterial3D = _materials.get(color)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	if GLOW_COLORS.has(color):
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = color
	else:
		_self_light(mat, color)
	_materials[color] = mat
	return mat
