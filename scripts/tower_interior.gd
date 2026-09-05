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
##                      →  THE COURTYARD DOORWAY: the only opening west, and since
##                         bead `godot-test1-e7q` a plain one — it used to carry a
##                         rotor turnstile the owner had removed as confusing
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
##     TWO THINGS ARE WIRED TO IT. The cell block's VENT PURGE, which a benched
##     multiplayer player operates for the team outside (bead godot-test1-3iy.10),
##     and — since bead godot-test1-3iy.22 — every `P` cell on every storey plan,
##     which LURES that storey's guard over to stand and look at it (see
##     `LURE_HOLD_SECONDS` and `_build_lure_pads`). The sketch here used to say the
##     plates would SCARE the guards; the lure was adopted instead, because a pad
##     that empties the corridor hands you the floor for free and the scare verb is
##     already the purge's. Two `P` cells stand inside the block itself since the
##     block moved to storey 10, so the purge pad is not the only cyan plate a
##     prisoner can see: they wire as lures like every other plan pad, which is the
##     "wiring them, not recolouring them" this record promised.
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
## (the crawl's press, a gate mass), a thing that MEASURES you (the demand
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
##   floor and 4.6 - 3.6125 = 0.9875 m was a step onto the storey above. Storey 2
##   is a full 80 m plate now, so there is no open sky below the roof and the sweep
##   is gone with the table it read — a jump anywhere on floor 0 ends at that
##   slab's underside, exactly as it always did in the entry hall. The
##   receptacle's 2.6 m is harmless for the same reason.
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
## `StaticBody3D`, forty-odd `Area3D`s (three pads, from
## phase 8 one press hazard, four spine pads and four cell volumes, from phase
## 15 one per riddle lock pad, from phase 16 the labyrinth's lift stop and from
## bead godot-test1-3iy.22 one per `P` cell, which is two a storey —
## check 5 counts them and is the number that is actually true),
## a `Label3D` per sign — three fixed (the demand gate, the spine, the cell) plus a
## lock sign and a clue sign per riddle, so eleven at four riddles and two more per
## riddle after that — and one gem —
## built once, for the life of a run. Per-floor visibility
## gating (`_update_visibility`) is what keeps that off the web frame budget when
## the player is anywhere else in the world.

# ============================================================================
# THE PLAN'S GEOMETRY — ALIASED, not owned (bead `godot-test1-ftn.19`)
# ============================================================================
#
# The heights, rhythms and budgets that turn a `TowerPlans` storey into boxes now
# live in `scripts/tower_plan_boxes.gd` beside the walker that reads them. They are
# aliased back here because the READERSHIP IS THE POINT: forty-four sites name
# `TowerInterior.FLOOR_Y` and twenty-two name `TowerInterior.PLAN_RAMP_MAX_SLOPE`,
# across the terrain, the minimap, the guard AI, the city plan and eight
# self-checks. One line each keeps every one of them true, and keeps this file's
# own two hundred uses of them unedited — which is what makes the extraction
# provably mechanical rather than a rename with a diff nobody can read.
#
# ONE WAY, AND THAT IS LOAD-BEARING. These are the only `const`s in this project
# that point at `TowerPlanBoxes`; that file reaches back only from inside function
# bodies (the palette, `_plan_prefix`, `_deck_box`, the set-piece builders), which
# is the shape `TowerDressing` has had since bd `godot-test1-ftn.12`. A top-level
# `const` pointing the other way makes it a parse-time cycle.
#
# `PODIUM_Y` and `PLAN_HEADROOM` are NOT aliased: nothing outside the walker has
# ever read them, and an alias with no reader is a name to keep in step for free.

const SLAB_Y: float = TowerPlanBoxes.SLAB_Y
const SLAB_THICK: float = TowerPlanBoxes.SLAB_THICK
const RAMP_THICK: float = TowerPlanBoxes.RAMP_THICK
const FLOOR_Y: Array[float] = TowerPlanBoxes.FLOOR_Y
const FLOOR_NEIGHBOURS: Array[Array] = TowerPlanBoxes.FLOOR_NEIGHBOURS
const PLAN_PAD_THICK: float = TowerPlanBoxes.PLAN_PAD_THICK
const PLAN_RAMP_MAX_SLOPE: float = TowerPlanBoxes.PLAN_RAMP_MAX_SLOPE
const PLAN_BOX_BUDGET: int = TowerPlanBoxes.PLAN_BOX_BUDGET
const PLAN_DRESS_BUDGET: int = TowerPlanBoxes.PLAN_DRESS_BUDGET


# ============================================================================
# THE GATES AND RIDDLE LOCKS — ALIASED, not owned (bead `godot-test1-ftn.21`)
# ============================================================================
#
# Where a gate is, what it looks like and where you stand to work it now live in
# `scripts/tower_gates.gd`. What is still here is the RUNTIME — the per-gate
# dictionaries, `_tick_gates` and its `_place_*` writers, `_press_riddle`, and
# **`_apply_opened()`, the one place state becomes geometry** — because all of it
# writes instance state and none of it is a function of the plan alone.
#
# The names below are the ones this file and the four tower self-checks still call
# through `TowerInterior`; one line each, so no call site moved. ONE WAY, like
# `TowerPlanBoxes` and `TowerGuards`: these `const`s point at `TowerGates`, and
# nothing in that file names this class outside a function body.

const RIDDLE_NOTCH: float = TowerGates.RIDDLE_NOTCH
const RIDDLE_RATTLE: float = TowerGates.RIDDLE_RATTLE
const DEMAND_BANDS: int = TowerGates.DEMAND_BANDS
const DEMAND_TARGET: float = TowerGates.DEMAND_TARGET
const DEMAND_TOLERANCE: float = TowerGates.DEMAND_TOLERANCE
const MASS_TRAVEL: float = TowerGates.MASS_TRAVEL
const SHUTTER_TRAVEL: float = TowerGates.SHUTTER_TRAVEL
const GATE_TIME: float = TowerGates.GATE_TIME
const NUDGE_FRACTION: float = TowerGates.NUDGE_FRACTION
const NUDGE_TIME: float = TowerGates.NUDGE_TIME


static func riddle_travel(mass: MeshInstance3D) -> float:
	return TowerGates.riddle_travel(mass)


static func riddle_ids() -> Array[String]:
	return TowerGates.riddle_ids()


static func gate_slots(plan: Dictionary) -> Dictionary:
	return TowerGates.gate_slots(plan)


static func _plan_gates(plan: Dictionary) -> Array[Dictionary]:
	return TowerGates._plan_gates(plan)


static func gate_pad_cell(plan: Dictionary, span: Rect2i) -> Vector2i:
	return TowerGates.gate_pad_cell(plan, span)


static func clue_strip(gate_id: String) -> Dictionary:
	return TowerGates.clue_strip(gate_id)


static func plan_gate_rect(floor_index: int, gate_id: String) -> Rect2i:
	return TowerGates.plan_gate_rect(floor_index, gate_id)


static func plan_doorway_rect(floor_index: int, room_id: String) -> Rect2i:
	return TowerGates.plan_doorway_rect(floor_index, room_id)


static func gate_stand(gate_id: String, steps: int) -> Vector3:
	return TowerGates.gate_stand(gate_id, steps)


static func checkpoint_stand() -> Vector3:
	return TowerGates.checkpoint_stand()


static func entry_stand() -> Vector3:
	return TowerGates.entry_stand()


static func _demand_boxes(plan: Dictionary) -> Array[Dictionary]:
	return TowerGates._demand_boxes(plan)


static func _checkpoint_boxes(plan: Dictionary) -> Array[Dictionary]:
	return TowerGates._checkpoint_boxes(plan)


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
## script shoves a `CharacterBody3D` through whatever is behind it.
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

## THE LURE — what every OTHER cyan plate in the building does (bead
## godot-test1-3iy.22). Step on a `P` cell and the storey's one guard walks over
## at its patrol pace, stands facing the plate for `LURE_HOLD_SECONDS`, and then
## walks back to its post. Every plan carries exactly two, which
## `tower_selfcheck` has asserted since they were drawn: pull the 120-degree cone
## to one plate and walk past on the other side.
##
## THE DESIGN RECORD ABOVE USED TO SKETCH THESE AS A SCARE (a purge that makes
## guards flee) and this bead adopted a LURE instead, owner unreachable. A flee
## pad clears the corridor for free and deletes the challenge it was meant to be
## part of; a lure is the stealth verb the epic was ruled to — and the scare verb
## is already spoken for by the cell block's vent purge, which stays exactly as it
## is (the block's own hand-built pad keeps its own wiring; the two plan `P` cells
## that stand inside the block since it moved to storey 10 wire as lures like
## every other, which is the "wiring, not recolouring" the record promised).
##
## PROVISIONAL, both of them. Ten seconds is about two lengths of a corridor at a
## walk — long enough to use, short enough that it is a window and not a solution.
const LURE_HOLD_SECONDS: float = 10.0

## Seconds a pad stays dead after a press, counted from the press and therefore
## COVERING THE ERRAND ITSELF (a walk out, the hold, the walk home) plus a rest.
## The anti-puppet rule this half owns is "two players alternating the pair cannot
## walk a guard around the floor forever"; the other half is
## `piglet_crocodile_ai.investigate_point()` refusing a body that is already busy.
const LURE_COOLDOWN: float = 20.0


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
## is invisible and non-solid in every world that has not taken the custody scar
## and stone in every world that has, so it is the one box in the plan
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
##
## 37 SINCE BEAD `godot-test1-e7q` took the rotor turnstile out of the courtyard
## doorway: its two bars were the only spinning parts in the building and each was
## a mesh of its own. The post was batched, so it cost nothing here.
##
## 38 SINCE THE EVIDENCE DOSSIERS (bead godot-test1-3iy.23), AND THAT ONE NODE IS
## SIX PICKUPS. A dossier has to disappear on its own when it is taken, which is
## the one thing a storey's merged batch cannot do — and six `MeshInstance3D` would
## have been six nodes and six SURFACES, which is what `SURFACE_BUDGET` (48
## measured against 54) has no room for. One `MultiMeshInstance3D` is one node, one
## surface and one draw however many dossiers are authored, and a taken one is a
## zero-scaled instance. Check 5 counts it as a mesh node and as a surface, because
## it is both; the "no MultiMeshInstance3D here" rule it replaces meant "this is
## authored geometry, not chunk content", and one authored rack of pickups is not
## the chunk streamer coming indoors.
const DRAW_BUDGET: int = 38

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
## MEASURED AT 49 with ten storeys authored, of which the ten wall surfaces are the
## whole of what Air Sight added. The slack over it is the same slack `DRAW_BUDGET`
## carries, and for the same reason: a moving part earns a mesh, and a mesh is at
## least one more draw.
##
## 48 -> 49 IS THE EVIDENCE DOSSIERS (bead godot-test1-3iy.23) — one `MultiMesh` of
## matte folders, deliberately NOT a `GLOW_COLORS` colour, so the six pickups cost
## the building one surface between them and no emissive surface at all. That is
## the whole reason they are one rack and not six meshes: see `DRAW_BUDGET`.
const SURFACE_BUDGET: int = 54

## The ground storey's carpet layer. 2 cm of pure colour, non-solid, laid OVER the
## shell's `Yard` apron — see `_plan_slab` for why the ground floor is the one storey
## whose slab top face is not the surface you look at. Thin enough that it is a change
## of colour under your feet and never a lip: `CharacterBody3D` has no step-up, so
## anything solid you could trip on is a wall, and this is not solid at all.
const CARPET_THICK: float = 0.02


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
#   * the checkpoint's plate and post, which relight once.
#
# Every one of them earns it. Anything you add that just SITS there
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
# THE GUARDS — ALIASED, not owned (bead `godot-test1-ftn.20`)
# ============================================================================
#
# The population lives in `scripts/tower_guards.gd` now: where a post is, what a
# beat is, the scene, and the free-and-rebuild that IS the persistence contract,
# with the three owner rulings written where they are enforced. What stays here is
# what belongs to the NODE — the `player_entered` handler below, and the names
# other scripts still reach through `TowerInterior`.
#
# `enemy_spawn_selfcheck` reads `GUARD_SPECIES` and `guard_posts_table()` as the
# FOURTH DOOR into the world (after `BIOME_SPECIES`, `BIOME_BOSS` and the hunter
# spawner) — a guard belongs to no biome and no road station, so a reachability
# check over the dispatch maps alone would report a shipped, working predator as
# one nothing can spawn. That gate, and `capture_selfcheck`'s arrest, and every
# guard check, go on reading these names.
#
# ONE WAY, like `TowerPlanBoxes`: these `const`s point at `TowerGuards`, and
# `TowerGuards` names this class only as a parameter type and in function bodies.
#
# `GUARD_PATROL_MAX_CELLS` and `GUARD_PATROL_LANE_HALF` are NOT aliased — nothing
# outside the post finder has ever read them.

const GUARD_SCENE_PATH: String = TowerGuards.GUARD_SCENE_PATH
const GUARD_SPECIES: String = TowerGuards.GUARD_SPECIES
const GUARD_SPAWN_LIFT: float = TowerGuards.GUARD_SPAWN_LIFT
const GUARDS_PER_STOREY_MAX: int = TowerGuards.GUARDS_PER_STOREY_MAX


static func guard_scene() -> PackedScene:
	return TowerGuards.guard_scene()


static func guard_posts_table() -> Array[Dictionary]:
	return TowerGuards.guard_posts_table()


static func _plan_guard_post(floor_index: int) -> Dictionary:
	return TowerGuards._plan_guard_post(floor_index)


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

## Seconds each lure plate still has to sit dead, keyed `"floor:pad"`. Per-run and
## per-peer like the purge's own cooldown, and deliberately not shared over the
## mesh: it is an INPUT gate on this screen's plate, while the rule that stops a
## room walking a guard around is the guard's own refusal to take a second errand.
var _lure_cooldown: Dictionary = {}
var _containment: MeshInstance3D = null

## The scar's rubble and its collision shape. Hidden and non-solid until the world
## has taken the scar; both move together, for the same reason a gate's mesh and
## shape do — rubble you can see and walk through is worse than no rubble.
var _scar_slab: MeshInstance3D = null
var _scar_shape: CollisionShape3D = null

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

## THE EVIDENCE DOSSIERS' one node, and which of them have been taken this run.
##
## PER-RUN, LIKE A COIN AND NOT LIKE A GATE. The opened set on the shell is a
## MONOTONE UNION that survives the process (`_open()` explains why); a dossier
## refinds on the next run, so putting an id in there would mean a pickup nobody
## could ever pick up again. `_captives` is per-run for the mirror-image reason,
## and this is the same shelf.
##
## In a ROOM the dedupe is not this dict at all — it is `MpManager`'s
## `_collected_ids`, reached through the very same `claim_pickup` / join replay a
## coin uses (see `TowerDossiers.collect`). This one only stops the local trigger firing
## twice and remembers which instances to zero-scale.
var _dossier_rack: MultiMeshInstance3D = null
var _dossier_found: Dictionary = {}

## Seconds until the next "has a teammate taken one?" read — see
## `TowerDossiers.tick`.
var _dossier_poll: float = 0.0

## Lore lines the toast REFUSED (a pending landmark question owns the card — possible
## in a room, where the quiz does not pause movement), waiting to be retried on
## `TowerDossiers.tick`'s clock. Without this the false return was dropped after
## `_dossier_found` was already set, and a one-time line was gone for good.
var _dossier_lore_queue: Array[String] = []

## The storey `_update_visibility` last drew the window around, -1 before the first
## frame. The rack is ONE node for the whole building, so it cannot hide with a
## storey container; this is what tells `TowerDossiers.refresh()` when to re-decide,
## and it means the decision costs one integer compare a frame rather than six
## transform writes.
var _drawn_floor: int = -1

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
# THE PLAN BUILDER — ALIASED, not owned (bead `godot-test1-ftn.19`)
# ============================================================================
#
# The walker itself is `scripts/tower_plan_boxes.gd`. What follows is one line per
# name anything still calls through `TowerInterior`, for the reason the const
# banner above gives: the readers are the asset, and a forwarder is cheaper than
# editing thirty-seven `_grid_x` / `_grid_z` call sites across nine files to prove
# a point about where a function lives.
#
# `plan_boxes()` IS STILL THE ONE SEAM THE DRESSING ENTERS THROUGH (CLAUDE.md).
# It changed house, not shape.
#
# Only the names something actually calls are here. `floor_y`, `_plan_ramp`,
# `_merge_walls` and `_plan_pads` have no caller outside the walker and are
# therefore not forwarded — see the const banner's last paragraph.

static func plan_clear_height(floor_index: int) -> float:
	return TowerPlanBoxes.plan_clear_height(floor_index)


static func plan_boxes(floor_index: int) -> Array[Dictionary]:
	return TowerPlanBoxes.plan_boxes(floor_index)


static func all_boxes() -> Array[Dictionary]:
	return TowerPlanBoxes.all_boxes()


static func _grid_x(edge: float) -> float:
	return TowerPlanBoxes._grid_x(edge)


static func _grid_z(edge: float) -> float:
	return TowerPlanBoxes._grid_z(edge)


static func _plan_stair(plan: Dictionary) -> Dictionary:
	return TowerPlanBoxes._plan_stair(plan)


static func _plan_hole(plan: Dictionary) -> Dictionary:
	return TowerPlanBoxes._plan_hole(plan)


static func _plan_slab(plan: Dictionary) -> Array[Dictionary]:
	return TowerPlanBoxes._plan_slab(plan)


static func pad_cells(plan: Dictionary) -> Array[Vector2i]:
	return TowerPlanBoxes.pad_cells(plan)


static func pad_point(floor_index: int, pad_index: int) -> Vector3:
	return TowerPlanBoxes.pad_point(floor_index, pad_index)


static func _plan_cell_of(local: Vector3) -> Vector2i:
	return TowerPlanBoxes._plan_cell_of(local)


static func _route_open(ch: String) -> bool:
	return TowerPlanBoxes._route_open(ch)


static func plan_route(floor_index: int, from_local: Vector3,
		to_local: Vector3) -> PackedVector3Array:
	return TowerPlanBoxes.plan_route(floor_index, from_local, to_local)


func pad_world(floor_index: int, pad_index: int) -> Vector3:
	"""
	`pad_point()` in world space — what the master validates a `pad` verb against.

	@return: `Vector3.INF` for a pad no plan draws, which is a rejection.
	"""
	var local := pad_point(floor_index, pad_index)
	return local if not local.is_finite() else global_position + local


# ============================================================================
# PLAN GRID READERS — the two the storey builders and the dressers share
# ============================================================================
#
# Both answer a question about the ASCII and nothing else, which is why they
# stayed here when the dressers moved out to `tower_dressing.gd`: `zone_at` and
# `egg_frames` read `_plan_char`, `minimap_selfcheck` reads `_room_cells`, and a
# reader with callers on both sides of that seam belongs to the plan rather than
# to the furniture standing on it.

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
			"color": TowerDressing.COLOR_SEAL, "collide": false, "floor": floor_index,
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
	# `sweep` marks a part that is MOVING on any frame you look at it. Its y here is
	# the TOP of the stroke, which is where `press_y(0)` puts it — see that
	# function.
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

	`y` lifts the body 0.2 m - dropped exactly on the floor plane it can start the
	frame a hair inside it.
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

	Two ways in: the `MOVING_PARTS` name list (the hand-built parts — the gate
	masses, the press — whose names a const can hold), and a plan box that declared
	itself `dynamic` (phase 15's riddle masses, which are named by a builder and so
	cannot be in a const list).
	"""
	return MOVING_PARTS.has(String(box["name"])) \
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
		if not is_own_node(box):
			batched[int(box["floor"])].append(box)
			if box["collide"]:
				_add_shape(body, box)
			continue
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _box_mesh(box["size"])
		mesh.position = box["pos"]
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
	_build_lure_pads()
	TowerDossiers.build(self)
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

	# ...and the dossiers' JOIN REPLAY, deferred for the very same reason: a dossier
	# id is its world position, and right now this building is standing at the
	# terrain's origin. One idle frame later it is on the tower site and the id a
	# joiner's collected set was written with is the id we compute.
	TowerDossiers.latch.call_deferred(self)

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

	ONE `_process` FOR THE WHOLE BUILDING — the fauna manager's rule. The press,
	two gate tweens, one distance test and two boolean writes; all of it is skipped
	outright while the interior is not drawn, which is most of a run.
	"""
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var near := _update_visibility()
	if not near:
		return
	_tick_press(delta)
	_tick_gates(delta)
	_tick_pads()
	_tick_lure_pads(delta)
	_tick_purge(delta)
	TowerDossiers.tick(self, delta)


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
		if _is_open(gid) and float(_spine_open.get(gid, 0.0)) < 1.0:
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

	THE MENU THAT SPENDS IT is `scripts/tower_lift_menu.gd` (bead godot-test1-3iy.7),
	which lists the stops whose `unlock` id this trigger — or the checkpoint — put in
	that set and rides you to `lift_stand()`. Nothing here knows about it: the stop
	is earned by standing on it, and what the earning is worth is the menu's problem.
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
	return landing_floor(String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_MAZE).get("room", "")))


static func landing_floor(room_id: String) -> int:
	"""
	Which `FLOOR_Y` index has `room_id` for its `landing`, -1 when none does.

	The seam between a graph ENTRY (which names a room) and a storey (which is a
	number), and the only place that translation is written. `lift_stop_floor()`
	above and the lift menu both ask it, so re-planning a landing onto another
	floor moves the trigger and the ride together.
	"""
	if room_id == "":
		return -1
	for floor_index: int in TowerPlans.floors():
		if String(TowerPlans.storey(floor_index).get("landing", "")) == room_id:
			return floor_index
	return -1


static func lift_stand(floor_index: int) -> Vector3:
	"""
	Where the lift sets you down on a storey: an `s` LANDING CELL near the middle
	of that storey's landing.

	@return: an interior-LOCAL point, 0.2 m off the walking surface —
	        `entry_stand()`'s and `checkpoint_stand()`'s convention.

	THE NEAREST `s` CELL TO THE CENTROID, not the centre of `landing_rect()`. The
	rect is a bounding box over cells that need not fill it (the ground floor's
	landing is an 18 x 16 hall with a doorway bitten out of one row), so its centre
	is only accidentally standable; a cell that IS an `s` is standable by
	construction, because the flood fill in `tower_selfcheck` walks it. Deterministic
	for the same reason everything else in this building is: it reads authored text
	and draws nothing.

	INSURANCE RATHER THAN A FIX TODAY, and measured: all three landings this
	building has a lift stop at or calls from have a bbox centre that already IS an
	`s`, so the snap changes nothing this build draws. It is here so the EXTENSION
	RULE holds — a storey whose landing wraps a corner gets a working stop from its
	plan alone, instead of a `tower_lift_selfcheck` failure a designer has to
	hand-place around.
	"""
	var plan := TowerPlans.storey(floor_index)
	if plan.is_empty():
		return entry_stand()
	var cells: Array[Vector2i] = []
	var sum := Vector2.ZERO
	for r: int in plan["rows"].size():
		var line := String(plan["rows"][r])
		for c: int in line.length():
			if line[c] == TowerPlans.LANDING_CHAR:
				cells.append(Vector2i(c, r))
				sum += Vector2(float(c), float(r))
	if cells.is_empty():
		return entry_stand()
	var centroid := sum / float(cells.size())
	var best := cells[0]
	var best_d := INF
	for cell: Vector2i in cells:
		var d := (Vector2(float(cell.x), float(cell.y)) - centroid).length_squared()
		if d < best_d:
			best_d = d
			best = cell
	return Vector3(_grid_x(float(best.x) + 0.5), FLOOR_Y[floor_index] + 0.2,
			_grid_z(float(best.y) + 0.5))


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


func _build_lure_pads() -> void:
	"""
	One trigger volume per `P` cell in the building — the lure's whole geometry.

	NO PLATE IS BUILT HERE. `_plan_pads()` already draws them into the storey's
	batch, and both read `pad_cells()`, so the volume and the paint are one scan
	apart and cannot drift. The riddle locks are wired exactly this way for exactly
	this reason.

	NOTHING IS AUTHORED, and that is the extension rule holding: a storey that
	grows a `P` gets a working lure the day its plan row lands, and a storey with
	no `G` simply has plates nobody answers — `lure_guard()` finds no guard and
	says so, which is the same degrade as a standalone interior with no population.
	"""
	for floor_index: int in TowerPlans.floors():
		var cells := pad_cells(TowerPlans.storey(floor_index))
		for i: int in cells.size():
			var at := pad_point(floor_index, i)
			if not at.is_finite():
				continue
			_add_area("LurePad%d_%d" % [floor_index, i], at + Vector3(0.0, 1.0, 0.0),
					Vector3(TowerPlans.PLAN_CELL, 2.0, TowerPlans.PLAN_CELL),
					_on_lure_pad_enter.bind(floor_index, i), Callable(), floor_index)


func _on_lure_pad_enter(body: Node3D, floor_index: int, pad_index: int) -> void:
	"""A plate went off under the local player. Plain overlap, like every pad here."""
	if body.is_in_group("player"):
		_press_lure_pad(floor_index, pad_index)


func _press_lure_pad(floor_index: int, pad_index: int) -> void:
	"""
	Spend the plate: send the storey's guard to look at it, or route the intent.

	THE COOLDOWN IS SPENT ON THE PRESS, not on the acceptance, and it covers the
	whole errand (`LURE_HOLD_SECONDS + LURE_COOLDOWN`). A guard that refuses
	because it is chasing you has already given you the only answer that matters,
	and a pad that re-armed instantly on a refusal would be a button to hold down
	while a guard is busy.

	SOLO IS THE `not routed` PATH, and it is the absent-MP degrade every seam in
	this building has: no manager, or a manager that is not in a room, and the
	press applies right here with zero mesh. In a room `request_guard_lure()`
	applies locally AND relays to the master, the `flee` verb's shape one verb
	along — the master is the authority for these bodies and its walk reaches every
	screen through the ordinary crocodile sync, with no flag and no new protocol.
	"""
	var key := "%d:%d" % [floor_index, pad_index]
	if float(_lure_cooldown.get(key, 0.0)) > 0.0:
		return
	_lure_cooldown[key] = LURE_HOLD_SECONDS + LURE_COOLDOWN
	var mp := get_tree().get_first_node_in_group("mp")
	var routed := (mp != null and mp.has_method("request_guard_lure")
			and bool(mp.call("request_guard_lure", floor_index, pad_index)))
	if not routed:
		lure_guard(floor_index, pad_index)


func _tick_lure_pads(delta: float) -> void:
	"""Run every plate's cooldown down. At most two entries per storey, ever."""
	for key: String in _lure_cooldown:
		_lure_cooldown[key] = maxf(0.0, float(_lure_cooldown[key]) - delta)


func lure_guard(floor_index: int, pad_index: int) -> bool:
	"""
	Send storey `floor_index`'s guard to stand and look at pad `pad_index`.

	@return: whether a guard took the errand. False is ordinary: an unplanned pad,
	    a storey with no `G`, a population that has not been stood up yet, or a
	    guard that is busy (`investigate_point()` owns that last judgement and
	    every other anti-puppet rule with it — see it for why they live there).

	PUBLIC because there are two callers and they must not drift: this building's
	own plate, and `MpManager._apply_guard_lure()` applying a relayed press.

	THE ROUTE IS COMPUTED HERE AND NOT IN THE AI, which is the whole reason
	`investigate_point()` takes one: this file owns the floor plan, and a predator
	that knew about `TowerPlans` would be a hunting AI with a level editor in it.
	The guard walks corners; a plate the plan offers no way to is simply refused.
	"""
	var where := pad_world(floor_index, pad_index)
	if not where.is_finite():
		return false
	var guard := _guard_on(floor_index)
	if guard == null or not guard.has_method("investigate_point"):
		return false
	var route := plan_route(floor_index, guard.global_position - global_position,
			pad_point(floor_index, pad_index))
	if route.is_empty():
		return false
	var world := PackedVector3Array()
	for point: Vector3 in route:
		world.append(global_position + point)
	return bool(guard.call("investigate_point", where, LURE_HOLD_SECONDS, world))


func _guard_on(floor_index: int) -> Node3D:
	"""
	The one guard standing on storey `floor_index`, or null.

	MATCHED THROUGH THE AUTHORED TABLE rather than by rebuilding the node name:
	`reset_guards()` names a body after its post row, so asking the table which row
	stands at this storey's height is the same question without a second copy of
	the naming rule to keep in step.
	"""
	if not is_instance_valid(_guards):
		return null
	for authored: Dictionary in guard_posts_table():
		if absf((authored["post"] as Vector3).y - FLOOR_Y[floor_index]) > 0.01:
			continue
		return _guards.get_node_or_null("TowerGuard%s" % String(authored["name"])) as Node3D
	return null


func _on_dossier_enter(body: Node3D, index: int) -> void:
	"""A dossier's trigger fired. Plain overlap, like every pad in this building."""
	if body.is_in_group("player"):
		TowerDossiers.collect(self, index, body)


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
		if _is_open(gid):
			_say_spine(tr("This way is open."))
			continue
		if here != wants:
			_say_spine(tr("%s ANSWERS TO %s.") % [
				gid.replace("_", " ").to_upper(), wants.to_upper()])
			continue
		# The right hero is standing here: earn the gate. Idempotent.
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
# THE SCAR — the one sanctioned exception to the graph's edge-additive law
# ---------------------------------------------------------------------------
#
# There used to be a break-out scene above this line — raised containment, a
# recall clock, a stand in the service corridor — opened when the corporation
# held every hero. The owner vetoed it (2026-09-01, bead `godot-test1-ueg`): the
# fourth capture is the ending, immediately. What survives is the SCAR, because
# `custody_stair_collapse` is a PERSISTED id in the monotone opened set of every
# profile that once survived that scene, and retiring a persisted id is a save
# migration nobody ordered. Nothing INFLICTS it any more; the row, the box and
# both audits stay so the worlds that took it still draw their rubble.

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
	"""A swept hazard moved through the player. Costs coins, via the ONE damage verb."""
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
	lift menu states properly anyway — it lists this floor from the moment this
	line runs.
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
	"""Free every guard and stand a fresh one on each authored post.

	Stays an INSTANCE method: `_ready()` defers it, the door signal calls it and the
	self-checks drive it directly, all through the node. The work is
	`TowerGuards.reset()`."""
	TowerGuards.reset(self)


func guard_posts() -> Array:
	"""Every live guard's authored post name and current global position — the seam
	the self-check measures the population through. `TowerGuards.posts()`."""
	return TowerGuards.posts(self)


func setback_point() -> Vector3:
	"""
	Where a knockback taken inside this tower drops the player: the last checkpoint
	they activated in it, or the doorway if they have not activated one yet.

	NOT "A GUARD'S", since bead godot-test1-3iy.19: a post-beat guard ARRESTS, and
	an arrest is the one contact whose knockback is waived (the surviving heroes
	carry on from where the party fell). This is the plate for everything else the
	building can do to you — a pre-beat guard, the press, an animal that followed
	you through the door.

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
	# THE DOSSIER RACK IS ONE NODE FOR TEN STOREYS, so it cannot ride a storey
	# container the way everything else in this building does — a folder on floor 6
	# would hang in the air over a hidden floor 5. Its instances are zero-scaled
	# instead, and only when the window actually moves: one integer compare a frame
	# against six transform writes.
	if current != _drawn_floor:
		_drawn_floor = current
		TowerDossiers.refresh(self)
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

	Parenting the `Area3D` to the mesh is the smallest way to keep what you see and
	what hurts you in the same place.
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
