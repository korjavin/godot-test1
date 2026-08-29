class_name TowerInterior
extends Node3D
## THE TOWER, INSIDE — GastroDefense HQ's first playable interior (epic
## godot-test1-3iy, phase 3, the keystone).
##
## Phase 1 decided WHERE the tower stands, phase 2 built the SHELL and gave it a
## doorway you can walk through. This is what is behind that doorway: two storeys,
## a ramp between them, and one instance of each of the three room verbs the rest
## of the epic will be built out of.
##
## ============================================================================
## THE ROUTE, which is the design (walk it in this order):
## ============================================================================
##
##   doorway (+X wall)  →  ENTRY HALL, under the upper slab, 4.2 m of headroom
##                      →  THE ROTOR GATE (the CHALLENGE SPACE): the only opening
##                         west, with two counter-rotating bars sweeping it
##                      →  COURTYARD, open to the sky, 11 m of it
##                      →  THE RAMP, up the courtyard's north side to the slab
##                      →  UPPER FLOOR, walled across by the SECURE DOOR
##                      →  THE IDENTITY GATE: the mass only Teibi can lift
##                      →  THE CHECKPOINT, lit green once you stand on it
##
##   and, off the hall to the south, the DEMAND GATE sealing a vault. Optional,
##   skippable, and the whole point of it is that you can SEE what it wants.
##
## ...and, off the hall to the NORTH (phase 8), THE CELL BLOCK WING:
##
##   entry hall  →  THE MAINTENANCE CRAWL: a low duct with a stamping press
##                  across it. A challenge, so anybody gets through it.
##   courtyard   →  the same corridor by its other door, which asks nothing.
##                  Two ways in, on purpose: the custody scar drops one.
##               →  THE SERVICE CORRIDOR, with FOUR DOORS along its north side
##                  and a violet pad in front of each. One door per hero, and
##                  each is that hero's rescue spine (`TowerGraph.spines`).
##               →  THE CELL GALLERY, and off it FOUR UNIFORM CELLS. Whoever
##                  reached the gallery can open any of them: liberation asks
##                  nobody's name, which is what "uniform cells" means.
##
## THE WING IS THE TUTORIAL FOR ITSELF. Ordinary rescues walk it over and over,
## and the one scene where it matters most is the last one — so the geography is
## deliberately a straight line with a single fork: corridor, four doors, one
## gallery, four cells in a row. Nothing branches, nothing doubles back, and the
## cell you want is always the nth recess from the end.
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
##     There is exactly one today: the cell block's VENT PURGE, which a benched
##     multiplayer player operates for the team outside (bead godot-test1-3iy.10).
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
## SELF-BUILDING FROM ONE TABLE, exactly like `tower_shell.gd` (and for the same
## three reasons — see its header). `boxes()` is the whole floor plan; `_ready()`
## is a loop over it. Nothing here is authored in a .tscn, so
## `tower_interior_selfcheck.gd` can measure the plan without instancing anything,
## and the jump-height and headroom rules below are ASSERTED rather than eyeballed.
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
##   slab top 4.6 m. NOTHING standing under the OPEN SKY has a top between the
##   floor and 4.6 - 3.6125 = 0.9875 m, so the ramp is the only way up. That is
##   what turned the rotor post into a full-height column instead of the waist-high
##   hub it wants to be: a 1.6 m hub is a step, and a step under an open sky is a
##   ladder onto the upper floor that skips the challenge space entirely. Under a
##   CEILING the rule does not apply — the receptacle is 2.6 m tall and harmless,
##   because a jump off it ends at the slab's underside. `tower_interior_selfcheck`
##   is what makes this paragraph true rather than merely intended.
##
##   upper partition top 8.6 m vs slab 4.6 + apex = 8.21. Unjumpable.
##   shell wall top 11.0 m vs the same 8.21. Unjumpable, so the upper floor is a
##   room and not a balcony you can leave over the side.
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
## THE COURTYARD IS 8 m WIDE AND THE OUTDOOR ARM IS 8.25 m LONG, so facing east
## anywhere near its west wall — the foot of the ramp above all — used to collapse
## the arm into a shot of the back of the hero's head, and the same arm sweeping
## nearby static collision was ~9 ms of a ~46 ms frame in the cell gallery. RESOLVED
## (bd godot-test1-0nu) by an INDOOR BOOM: `_update_visibility` below asks
## `inside_walls()` and hands the answer to `PlayerController.set_indoor_camera()`,
## which swaps the arm to `INDOOR_ARM_LENGTH` (3.85 — sized against half this
## courtyard; the derivation lives on that constant). This file does not touch the
## camera and could not: nothing may write `camera.position`, and the arm belongs to
## the player. It only answers "are you inside my walls?".
##
## slab clears that 3.5 m with room for the arm's 0.25 m margin, so the arm never
## slams in on flat ground; the courtyard and the upper floor are open to the sky
## and have no ceiling at all. That is why the entry hall is the only enclosed room
## in the building and why it is 4.2 m and not 3.
##
## ============================================================================
## COST
## ============================================================================
##
## TWENTY `MeshInstance3D`s for the parts that move (plus the two batches) plus TWO batched ones for
## everything that does not (see THE BATCH below), ONE `StaticBody3D`, fourteen
## `Area3D`s (three pads, two rotor hazards and, from phase 8, one press hazard,
## four spine pads and four cell volumes), two rotor pivots, three `Label3D`s and
## one gem — built once, for the life of a run. Per-floor visibility
## gating (`_update_visibility`) is what keeps that off the web frame budget when
## the player is anywhere else in the world.

# ============================================================================
# GEOMETRY — metres, LOCAL to the shell's origin, feet at y = 0
# ============================================================================
#
# The shell's inner faces are at +/- INNER_HALF on both axes, and the corner spire
# is a solid 7 m cube of stone at the -X/-Z corner (x <= -3, z <= -3) — which is
# why nothing below reaches into that corner and why the upper slab starts where
# it does.

## Half the CLEAR interior span: the shell's outer half minus one wall thickness.
## Derived, never restated, so a thicker wall shrinks the interior automatically.
const INNER_HALF: float = TowerShell.OUTER_HALF - TowerShell.WALL_THICK

## The upper storey. `SLAB_Y` is its WALKING SURFACE; the slab hangs below it, so
## the hall's headroom is `SLAB_Y - SLAB_THICK`.
##
## 4.6 is the smallest number that satisfies both rules at once: it must exceed
## the jump apex (3.6125) plus the tallest thing standing under it (0.7) with
## margin, and `SLAB_Y - SLAB_THICK` must exceed the camera's 3.5 m float. Raising
## it costs shell wall height; lowering it breaks one of the two.
const SLAB_Y: float = 4.6
const SLAB_THICK: float = 0.4

## Where the upper slab's west edge is — i.e. the line that divides the enclosed
## entry hall (east, under the slab) from the open courtyard (west, under the sky).
const SLAB_X0: float = -0.5

## The rotor doorway: the ONLY way west out of the entry hall, and therefore the
## only route to the ramp. `ROTOR_ARM` must stay under `ROTOR_DOOR_HALF` so the
## sweeping bars clear the jambs, and over `ROTOR_DOOR_HALF * 0.5` so a bar lying
## across the doorway actually blocks a gap instead of leaving one open.
const ROTOR_DOOR_HALF: float = 1.9
const ROTOR_ARM: float = 1.7
const ROTOR_POST_X: float = SLAB_X0 - 0.2

## Where the north jamb stops and the low wall under the ramp begins.
##
## The ramp crosses the slab's edge line on its way up, so the wall standing on
## that line CANNOT be full height along the ramp's strip or it would be a fence
## across the stairs. `RAMP_UNDER_TOP` is picked against two numbers at once: it
## must clear the ramp's underside where they cross (3.91 m), and — the rule that
## actually matters — it must stay under a plain jump apex (3.6125 m) from the
## courtyard floor, so the low stretch is a wall and not a step onto the roof.
const RAMP_UNDER_Z: float = RAMP_Z - RAMP_WIDTH * 0.5
const RAMP_UNDER_TOP: float = 3.4

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

## The ramp, up the courtyard's north side. Rise is `SLAB_Y`, so the only knob is
## the run — and the run is what sets the angle. 8.0 m of run gives 29.9 degrees,
## comfortably under `CharacterBody3D`'s default 45-degree floor limit; steepen it
## much and the player slides.
##
## IT IS A RAMP AND NOT STEPS, and that is not a shortcut. Godot 4's
## `CharacterBody3D` has no step-up: a stair tread of ANY height is a wall you have
## to jump, which is precisely the jump-gated traversal this bead forbids. A ramp
## is the only stair this engine has.
##
## IT HUGS THE NORTH WALL, and that is load-bearing rather than tidy: the low
## stretch of wall it flies over (`RAMP_UNDER_Z`) is derived from the ramp's own
## strip, so the two are the same span by construction. Move the ramp inboard and
## you leave a length of 3.4 m wall standing under the open sky beside it — which
## is a step onto the upper floor and a way past the challenge space. The
## self-check found exactly that.
const RAMP_X0: float = -8.5
const RAMP_WIDTH: float = 2.8
const RAMP_Z: float = INNER_HALF - RAMP_WIDTH * 0.5
const RAMP_THICK: float = 0.4

## The demand gate's vault, off the hall's south end. The shutter fills the gap
## between the two jambs and sinks its own full height to open.
const VAULT_Z: float = -5.0
const VAULT_X0: float = 2.0
const SHUTTER_X0: float = 4.6
const SHUTTER_X1: float = 7.0

## The receptacle pillar and its calibration ladder. `DEMAND_BANDS` is the SCALE
## the player reads: lit bands are their current capability, the full stack is what
## the gate wants. Four is enough to see a shortfall at a glance and few enough to
## count without counting.
const DEMAND_BANDS: int = 4
const RECEPTACLE_X: float = 5.8
const RECEPTACLE_Z: float = -4.3

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

## The upper floor's secure door: a partition across the whole slab with one gap,
## filled by the identity mass. Height is chosen against the jump rule above.
const UPPER_WALL_X: float = 4.0
const UPPER_WALL_HEIGHT: float = 4.0
const UPPER_DOOR_HALF: float = 1.5

## How far the identity mass rises when it opens, and how far the demand shutter
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
# THE CELL BLOCK WING — phase 8, north of the entry hall and under the same slab
# ============================================================================
#
# THE WING IS ROOFED, AND THAT IS THE CONSTRAINT EVERYTHING BELOW BENDS TO. The
# slab spans the whole of x >= SLAB_X0, so the only unbuilt ground left inside this
# keep is the hall's north end: the courtyard is the ramp's, the south is the
# vault's, and the -X/-Z corner is seven metres of solid spire. A wing under a
# 4.2 m ceiling gets two things for free and pays for one:
#
#   FREE: the jump rule stops applying (`_roofed` — a jump under the slab ends at
#         the slab), so walls here are sized for sightlines instead of for an apex.
#   FREE: it is dark, so the two light panels below are the whole art direction.
#   PAID: A 4.2 m MASS CANNOT RISE UNDER A 4.2 m CEILING. The secure door's
#         counterweight rises and stays risen because it stands under open sky;
#         these four have nowhere to go but DOWN, so they sink and stay sunk.
#
# That is a real, deliberate weakening of the legibility language's "identity gates
# rise, demand gates sink" opposition, taken with eyes open because the geometry
# left no other move that is not a jump-gated ledge. The other three axes are
# untouched and they are the ones a player reads FIRST: violet against steel, a
# blank mass against a banded pillar, a pad you stand on against a receptacle you
# walk up to. Motion is the axis you only see once you have already been told the
# answer. If the tower ever grows a storey with sky over this wing, put the rise
# back.
#
# THE CAMERA, honestly: `CameraArm` is an 8.25 m `SpringArm3D` and nothing may
# write `camera.position`, so a room narrower than the arm collapses it — the
# courtyard's documented 8 m deferral, one storey down. This wing is laid out to
# lose as little as it can: the corridor and the gallery both run the building's
# LONG axis (9.3 m), the cells are open-fronted recesses rather than rooms with
# doors, and the ceiling is the hall's full 4.2 m. Facing along either run the arm
# nearly extends; facing into a cell it does not, and that is the same deferral,
# not a new one.

## The wing's south wall: the line that divides the entry hall from the service
## corridor. 2.2 m clears the rotor bars' 1.7 m sweep with 0.3 m to spare, which is
## what stops a bar chopping through the wall the moment the doorway moves.
const WING_Z: float = 2.2

## ...except at the east end, where it JOGS NORTH around the shell's doorway. The
## front door's trigger volume reaches x >= 7.8 and z <= 3.0 and must stay empty
## (`tower_shell.door_trigger_box`, asserted by check 1), so the straight run stops
## short of it and the last 1.4 m of boundary is 1.2 m further north. That jog is
## what buys the wing its depth: a straight wall clear of the doorway would start
## at z = 3.4 and leave 5.4 m for a corridor, a gallery AND four cells.
const WING_JOG_X: float = 7.4
const WING_JOG_Z: float = 3.4

## The maintenance crawl's doorway, and the press that sweeps it. The press is an
## `Area3D` hazard on a mesh that never becomes solid — a solid block driven by
## script shoves a `CharacterBody3D` through whatever is behind it, which is the
## same reason the rotor bars are hazards (see `_make_rotor`).
##
## IT IS A CHALLENGE AND MUST STAY ONE. `maintenance_crawl` is the route the
## custody scar leaves standing when it drops the courtyard stair, so the softlock
## audit needs it passable by every hero with no rank at all. A press you time is;
## anything keyed on a name or a number is not.
const CRAWL_X0: float = 4.3
const CRAWL_X1: float = 5.7
## The lintel and the stroke are one pair of numbers, not two: the press's box is
## 0.7 m deep, so its top at rest is exactly the lintel's underside and its bottom
## at the end of the stroke is exactly the floor. Between them the gap has to clear
## a 2 m capsule or the crawl is impassable at every phase of its cycle — which is
## a challenge gate that is really a wall, and check 11 measures it.
const CRAWL_LINTEL_Y: float = 2.8
const PRESS_TOP: float = 2.45
const PRESS_BOTTOM: float = 0.35
## Long enough to walk under without sprinting, short enough that waiting is dull.
const PRESS_PERIOD: float = 2.6

## The corridor's other door: a gap cut in the slab-edge wall, straight out to the
## courtyard and asking nothing (`courtyard_stair`). Two ways into one corridor is
## not redundancy for its own sake — it is the entire reason the custody scar is
## survivable, and `tower_selfcheck` check 6 recomputes that rather than trusting
## this comment.
const SERVICE_DOOR_Z0: float = 2.6
const SERVICE_DOOR_Z1: float = 4.0

## The spine wall: four doorways in one 9.3 m run, one per hero, each filled by its
## own mass. Four doors need a long wall, which is why the wing splits north/south
## and not east/west — 1.5 m of door and 1.1 m of pier is what fits, and a 1.5 m
## opening clears a giant Teibi.
const SPINE_Z: float = 4.4
const SPINE_DOOR_W: float = 1.5
const SPINE_PIER_W: float = 1.1
## How far a spine mass sinks: its own height and a little more, so its top ends up
## under the yard slab and there is no lip left in the doorway. A lip of ANY height
## is a wall in this engine, so "nearly flush" is not a finish, it is a bug.
const SPINE_TRAVEL: float = 4.6
## Where a spine pad sits: in the corridor, hard against its own door.
##
## PRESSED UP AGAINST THE SPINE WALL, and that is the doorway's fault rather than a
## style choice: the easternmost pad reaches x = 8.8, and at the other end of the
## corridor the wing wall's jog runs to z = 3.6, so a deeper pad would either sit
## inside that wall or inside the shell's door trigger volume (check 1 caught both).
## The TRIGGER is deeper than the plate — you step onto a pad from the corridor, so
## the volume may reach back past the paint.
const PAD_Z: float = 3.9
const PAD_DEPTH: float = 0.6
const PAD_TRIGGER_DEPTH: float = 1.0

## The cells: four uniform recesses off the gallery's north side, divided by piers
## and open-fronted. THEY HAVE NO DOORS, and that is the rule rather than a saving —
## `TowerGraph`'s `gallery_cell_*` edges are ungated, so whoever reached the gallery
## can free whoever is inside, whatever hero they happen to be holding.
const CELL_Z0: float = 6.6

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
## it, which is the small act that makes operating it a decision.
const PURGE_PAD_X: float = INNER_HALF - 1.0
const PURGE_PAD_Z: float = (SPINE_Z + CELL_Z0) * 0.5

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
const CELL_DIVIDER: float = 0.3

# ============================================================================
# VISIBILITY GATING — the web frame budget's half of this bead
# ============================================================================

## Beyond this distance from the tower the whole interior stops drawing.
##
## The interior is INSTANCED once the player is within `TOWER_LOAD_RADIUS` (320 m)
## and never freed, so without this it would be 25 permanently-submitted meshes for
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

## Hard cap on the interior's box count, asserted headlessly by
## `tower_interior_selfcheck.gd` — the shell's `BOX_BUDGET` discipline, with its
## own (larger) number because these meshes are only ever drawn from inside the
## building.
##
## RAISED FROM 32 TO 60 BY PHASE 8: the cell block wing is 28 boxes (four walls, a
## lintel, a press, a jamb, three piers, four masses, four pads, three dividers,
## four cell frames, the staging unit and two light panels) and 26 of them are
## batched, i.e. free. What this number still stops is furnishing — it leaves six
## spare and bites the moment somebody starts modelling bunks.
const BOX_BUDGET: int = 60

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
const DRAW_BUDGET: int = 23

# ============================================================================
# PALETTE — one material per colour, shared process-wide (see `_material`)
# ============================================================================
#
# Read the legibility block at the top of the file before changing any of these:
# the colours ARE the language, and a room that borrows the wrong one lies to the
# player about what it is.

const COLOR_STONE := Color(0.50, 0.48, 0.46)        # ordinary geometry
const COLOR_HAZARD := Color(0.86, 0.36, 0.12)       # anything that moves to hurt you
const COLOR_MECHANISM := Color(0.24, 0.27, 0.33)    # demand gate: cold steel
const COLOR_BAND_DARK := Color(0.13, 0.14, 0.16)    # an unlit calibration band
const COLOR_BAND_LIT := Color(1.00, 0.62, 0.12)     # a lit one — your reading
const COLOR_IDENTITY := Color(0.42, 0.20, 0.58)     # identity gate: the mass
const COLOR_IDENTITY_PAD := Color(0.72, 0.36, 1.00) # ...and the pad you stand on
const COLOR_CHECKPOINT := Color(0.16, 0.38, 0.30)   # checkpoint, not yet reached
const COLOR_CHECKPOINT_LIT := Color(0.32, 1.00, 0.58)
const COLOR_PANEL := Color(1.00, 0.95, 0.86)        # ceiling light panels
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

## Which colours are EMISSIVE AND UNSHADED. There are no `Light3D`s anywhere in
## this building: a real light under the slab would cost a shadow pass on a
## renderer (`gl_compatibility`) that is the whole reason for the visibility gating
## above. A glowing box is a draw call that was happening anyway.
const GLOW_COLORS: Array[Color] = [
	COLOR_BAND_LIT, COLOR_IDENTITY_PAD, COLOR_CHECKPOINT_LIT, COLOR_PANEL,
	COLOR_CELL,
]

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
const SPINE_DOORS: Array[Dictionary] = [
	{"gate": "updraft_shaft", "mass": "UpdraftMass", "pad": "UpdraftPad"},
	{"gate": "phase_grate", "mass": "GrateMass", "pad": "GratePad"},
	{"gate": "collapsed_slab", "mass": "SlabMass", "pad": "SlabPad"},
	{"gate": "hound_den", "mass": "DenMass", "pad": "DenPad"},
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
const SCAR_BOX: String = "StairCollapse"

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
	"DemandShutter", "IdentityMass",
	"Band1", "Band2", "Band3", "Band4",
	"CheckpointPlate", "CheckpointPost",
	# --- phase 8: the wing. Four masses that travel, one press that sweeps, four
	# cell frames that relight the moment a captive walks out, and the staging unit
	# that is never seen again after the first rescue. Everything else in the wing
	# — every wall, pier, divider, pad and panel — sits still and is batched.
	"UpdraftMass", "GrateMass", "SlabMass", "DenMass",
	"CrawlPress",
	"CellFrameWindman", "CellFramePrimm", "CellFrameTeibi", "CellFramePhoboman",
	"PrimmContainment",
	# ...and phase 11's scar, which appears and turns solid the day the protocol is
	# survived. A batched box cannot do either.
	SCAR_BOX,
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

## THE POSTS. Three of them, which is the top of the owner's "few guards" band,
## and each one is a beat the route already had:
##
##   HALL      — you are barely inside and something is already walking. The POST
##               is 6.8 m from the doorway, against a 6.5 m detection radius, so
##               the guard is not looking at you the instant you step through; its
##               patrol box does bring it closer, which is the intended tension
##               rather than an oversight — a hall guard you can never meet at the
##               door is scenery.
##   COURTYARD — the open middle, between the rotor gate and the foot of the ramp.
##   UPPER     — the approach to the identity gate, WEST of the secure partition.
##
## NONE OF THEM CAN BLOCK A ROUTE, which is what keeps the softlock audit
## (`tower_selfcheck`) true with guards in the building: the player is collision
## mask 1 and walks THROUGH a predator (CLAUDE.md), so a guard standing in a
## doorway is a threat and never a wall. That is also why a guard needs no entry in
## `TowerGraph` — it gates nothing.
##
## `patrol_center` / `patrol_half` is the box `set_confinement()` pins the guard
## inside — the leash that has existed since the elevated-platform guards and that
## is the whole of "patrols, spots and chases WITHIN ITS FLOOR". The upper guard's
## box stops at x = 3.5, short of the partition at x = 3.8, which is why the
## checkpoint beyond the identity gate is a safe haven BY CONSTRUCTION rather than
## by hoping: a guard that has seen you standing on it still cannot follow you in,
## and the knockback below therefore cannot drop you into a re-bite loop.
const GUARD_POSTS: Array[Dictionary] = [
	{
		"name": "Hall",
		"post": Vector3(2.8, 0.0, -3.2),
		"patrol_center": Vector3(4.0, 0.0, -2.0),
		"patrol_half": Vector2(3.6, 2.4),
	},
	{
		"name": "Courtyard",
		"post": Vector3(-5.0, 0.0, 1.5),
		"patrol_center": Vector3(-5.0, 0.0, 1.5),
		"patrol_half": Vector2(3.5, 4.0),
	},
	{
		"name": "Upper",
		"post": Vector3(1.6, SLAB_Y, 2.2),
		"patrol_center": Vector3(1.6, SLAB_Y, 0.0),
		"patrol_half": Vector2(1.9, 4.0),
	},
]

## WHERE A GUARD'S SETBACK PUTS YOU — the two ends of `setback_point()`.
##
## The checkpoint stand is inside `CheckpointTrigger`'s volume and clear of
## `CheckpointPost`, which stands on the plate: "the checkpoint" is the space
## beside the post, not the post's own footprint. The entry stand is the fallback
## for a run that has not lit the checkpoint yet — just inside the doorway, so a
## setback before the checkpoint costs you the whole building rather than nothing.
const CHECKPOINT_STAND: Vector3 = Vector3(5.8, SLAB_Y + 0.2, 0.0)
const ENTRY_STAND: Vector3 = Vector3(7.6, 0.2, 0.0)

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

## Progress of each gate's open animation, 0 = shut, 1 = fully open. Persisted only
## as the boolean "is this id in the opened set"; this is the tween.
var _shutter_open: float = 0.0
var _mass_open: float = 0.0

## The wing's four spine doors, keyed by gate id: the mass, its collision shape,
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
var _press: MeshInstance3D = null
var _press_clock: float = 0.0

## The four containment frames, keyed by HERO, plus the authored staging unit.
var _cell_frames: Dictionary = {}

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
## the break-out is exactly the wing's own lesson replayed under a clock. Empty
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


static func boxes() -> Array[Dictionary]:
	"""
	The whole interior, as boxes: `{name, pos, size, color, collide, floor}` plus an
	optional `rot` (Euler radians) and `spin` (rad/s, marks a rotor bar).

	@return: One entry per `MeshInstance3D`, in build order.

	THE SINGLE SOURCE OF THE PLAN, the same contract `TowerShell.boxes()` holds:
	`_ready()` builds from it and `tower_interior_selfcheck.gd` measures the jump
	rule, the headroom and the budget out of it without instancing a thing.

	`floor` is the storey a box belongs to for visibility gating — 0 is the ground
	floor, 1 the upper. A box you STAND ON belongs to the floor it carries, which is
	why the slab is floor 1 and the ramp (which starts on the ground) is floor 0.
	"""
	var out: Array[Dictionary] = []

	# ---- Ground floor -----------------------------------------------------
	# The rotor doorway's two jambs: a full-height wall on the slab's west edge with
	# one gap in it, so the courtyard has exactly one land entrance.
	var hall_clear := SLAB_Y - SLAB_THICK
	out.append({
		"name": "RotorJambNegZ",
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, -(INNER_HALF + ROTOR_DOOR_HALF) * 0.5),
		"size": Vector3(0.4, SLAB_Y, INNER_HALF - ROTOR_DOOR_HALF),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	# The +Z jamb is now in TWO pieces with the service doorway between them: the
	# courtyard's own way into the cell block wing (`courtyard_stair`), which asks
	# nothing of anybody. The short stub is the pier between the rotor doorway and
	# that one, so the two openings read as two doors and not one wide gap.
	out.append({
		"name": "RotorJambPosZ",
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, (SERVICE_DOOR_Z0 + ROTOR_DOOR_HALF) * 0.5),
		"size": Vector3(0.4, SLAB_Y, SERVICE_DOOR_Z0 - ROTOR_DOOR_HALF),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "ServiceJamb",
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, (RAMP_UNDER_Z + SERVICE_DOOR_Z1) * 0.5),
		"size": Vector3(0.4, SLAB_Y, RAMP_UNDER_Z - SERVICE_DOOR_Z1),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	# THE SCAR (phase 11). The service doorway, filled with rubble — built ALWAYS,
	# drawn and made solid only once `TowerGraph.SCAR_CUSTODY` is in the opened set
	# (`_refresh_scar`). In the table so it is budgeted, footprint-checked and fits
	# the shell like every other box; `scar` is what keeps it out of the BASE plan
	# the self-checks sample, and `severs` names the graph edge it takes away, so
	# `tower_selfcheck` can bind the two rather than trust this comment.
	out.append({
		"name": SCAR_BOX,
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, (SERVICE_DOOR_Z0 + SERVICE_DOOR_Z1) * 0.5),
		"size": Vector3(0.4, SLAB_Y, SERVICE_DOOR_Z1 - SERVICE_DOOR_Z0),
		"color": COLOR_SCAR, "collide": true, "floor": 0,
		"scar": TowerGraph.SCAR_CUSTODY, "severs": "courtyard_stair",
	})
	# The stretch the ramp flies over on its way to the slab — see RAMP_UNDER_TOP.
	out.append({
		"name": "RampUnderwall",
		"pos": Vector3(ROTOR_POST_X, RAMP_UNDER_TOP * 0.5, (RAMP_UNDER_Z + INNER_HALF) * 0.5),
		"size": Vector3(0.4, RAMP_UNDER_TOP, INNER_HALF - RAMP_UNDER_Z),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	# The rotor itself: a post in the middle of that doorway with two bars through
	# it. The post is SOLID (you walk round it), the bars are not (you time them) —
	# a solid bar would shove the player through a wall.
	out.append({
		"name": "RotorPost",
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, 0.0),
		"size": Vector3(0.4, SLAB_Y, 0.4),
		"color": COLOR_HAZARD, "collide": true, "floor": 0,
	})
	out.append({
		"name": "RotorBarLow",
		"pos": Vector3(ROTOR_POST_X, ROTOR_LOW_Y, 0.0),
		"size": Vector3(2.0 * ROTOR_ARM, 0.3, 0.3),
		"color": COLOR_HAZARD, "collide": false, "floor": 0,
		"spin": ROTOR_LOW_SPEED,
	})
	out.append({
		"name": "RotorBarHigh",
		"pos": Vector3(ROTOR_POST_X, ROTOR_HIGH_Y, 0.0),
		"size": Vector3(2.0 * ROTOR_ARM, 0.3, 0.3),
		"color": COLOR_HAZARD, "collide": false, "floor": 0,
		"spin": ROTOR_HIGH_SPEED,
	})

	# The vault, off the hall's south end: a west wall, two jambs and the shutter
	# between them. Same "a wall with a hole in it" construction as the shell's
	# doorway, so the shutter cannot drift out of its own gap.
	out.append({
		"name": "VaultWall",
		"pos": Vector3(VAULT_X0, hall_clear * 0.5, (-INNER_HALF + VAULT_Z) * 0.5),
		"size": Vector3(0.4, hall_clear, INNER_HALF + VAULT_Z),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "VaultJambWest",
		"pos": Vector3((VAULT_X0 + SHUTTER_X0) * 0.5, hall_clear * 0.5, VAULT_Z),
		"size": Vector3(SHUTTER_X0 - VAULT_X0, hall_clear, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "VaultJambEast",
		"pos": Vector3((SHUTTER_X1 + INNER_HALF) * 0.5, hall_clear * 0.5, VAULT_Z),
		"size": Vector3(INNER_HALF - SHUTTER_X1, hall_clear, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "DemandShutter",
		"pos": Vector3((SHUTTER_X0 + SHUTTER_X1) * 0.5, hall_clear * 0.5, VAULT_Z),
		"size": Vector3(SHUTTER_X1 - SHUTTER_X0, hall_clear, 0.4),
		"color": COLOR_MECHANISM, "collide": true, "floor": 0,
	})
	# The receptacle: the free-standing pillar that is the demand gate's face.
	out.append({
		"name": "Receptacle",
		"pos": Vector3(RECEPTACLE_X, 1.3, RECEPTACLE_Z),
		"size": Vector3(1.0, 2.6, 0.6),
		"color": COLOR_MECHANISM, "collide": true, "floor": 0,
	})
	# The calibration ladder, bottom band first — the order `_update_bands` lights
	# them in, so the array index IS the rung.
	for i in DEMAND_BANDS:
		out.append({
			"name": "Band%d" % (i + 1),
			"pos": Vector3(RECEPTACLE_X, 0.75 + 0.45 * float(i), RECEPTACLE_Z + 0.35),
			"size": Vector3(0.7, 0.18, 0.1),
			"color": COLOR_BAND_DARK, "collide": false, "floor": 0,
		})

	# Ceiling panels. The hall is the one enclosed room in the building and the
	# directional light does not reach under a slab; without these it is a cave.
	# Moved south by phase 8: z = 3.4 is now inside the service corridor, and the
	# hall's own north end is the stretch between the doorway and the wing wall.
	out.append({
		"name": "PanelHallNorth",
		"pos": Vector3(5.4, hall_clear - 0.05, 0.4),
		"size": Vector3(4.0, 0.1, 3.2),
		"color": COLOR_PANEL, "collide": false, "floor": 0,
	})
	out.append({
		"name": "PanelHallSouth",
		"pos": Vector3(4.2, hall_clear - 0.05, -2.0),
		"size": Vector3(4.0, 0.1, 3.0),
		"color": COLOR_PANEL, "collide": false, "floor": 0,
	})
	out.append({
		"name": "PanelVault",
		"pos": Vector3(5.4, hall_clear - 0.05, -6.9),
		"size": Vector3(2.6, 0.1, 2.6),
		"color": COLOR_PANEL, "collide": false, "floor": 0,
	})

	# ---- The cell block wing, north of the hall (phase 8) ------------------
	out.append_array(_wing_boxes())

	# The ramp. Derived entirely from the storey height and the run, so the deck
	# lands EXACTLY on the slab's lip at one end and on the ground at the other —
	# see `_ramp_box()` for the arithmetic and why a lip would be a bug.
	out.append(_ramp_box())

	# ---- Upper floor ------------------------------------------------------
	out.append({
		"name": "UpperSlab",
		"pos": Vector3((SLAB_X0 + INNER_HALF) * 0.5, SLAB_Y - SLAB_THICK * 0.5, 0.0),
		"size": Vector3(INNER_HALF - SLAB_X0, SLAB_THICK, 2.0 * INNER_HALF),
		"color": COLOR_STONE, "collide": true, "floor": 1,
	})
	# The secure door: a partition across the entire upper floor with one gap, so
	# there is no walking round it and (being 4 m tall on a 4.6 m floor) no jumping
	# over it either.
	var upper_len := INNER_HALF - UPPER_DOOR_HALF
	var upper_mid := (INNER_HALF + UPPER_DOOR_HALF) * 0.5
	for sign_z in [-1.0, 1.0]:
		out.append({
			"name": "SecureJamb%s" % ("NegZ" if sign_z < 0.0 else "PosZ"),
			"pos": Vector3(UPPER_WALL_X, SLAB_Y + UPPER_WALL_HEIGHT * 0.5, sign_z * upper_mid),
			"size": Vector3(0.4, UPPER_WALL_HEIGHT, upper_len),
			"color": COLOR_STONE, "collide": true, "floor": 1,
		})
	out.append({
		"name": "IdentityMass",
		"pos": Vector3(UPPER_WALL_X, SLAB_Y + UPPER_WALL_HEIGHT * 0.5, 0.0),
		"size": Vector3(1.2, UPPER_WALL_HEIGHT, 2.0 * UPPER_DOOR_HALF),
		"color": COLOR_IDENTITY, "collide": true, "floor": 1,
	})
	# The pad. Non-solid and 10 cm proud, the yard slab's trick: a change of colour
	# under your feet, never a lip to trip on.
	out.append({
		"name": "IdentityPad",
		"pos": Vector3(UPPER_WALL_X - 1.8, SLAB_Y + 0.05, 0.0),
		"size": Vector3(2.6, 0.1, 3.0),
		"color": COLOR_IDENTITY_PAD, "collide": false, "floor": 1,
	})
	out.append({
		"name": "CheckpointPlate",
		"pos": Vector3(6.8, SLAB_Y + 0.05, 0.0),
		"size": Vector3(3.0, 0.1, 3.0),
		"color": COLOR_CHECKPOINT, "collide": false, "floor": 1,
	})
	out.append({
		"name": "CheckpointPost",
		"pos": Vector3(6.8, SLAB_Y + 1.3, 0.0),
		"size": Vector3(0.7, 2.6, 0.7),
		"color": COLOR_CHECKPOINT, "collide": true, "floor": 1,
	})
	return out


static func _ramp_box() -> Dictionary:
	"""
	The ramp, as a rotated box whose TOP SURFACE passes exactly through the ground
	at its foot and the slab's lip at its head.

	@return: One `boxes()` entry, carrying a `rot`.

	The arithmetic is here rather than inline because the flushness is the whole
	point: a rotated slab positioned by eye leaves a lip at one end, and a lip of
	ANY height is a wall in this engine (`CharacterBody3D` has no step-up). So the
	box is placed by its top face and the centre is derived — offset half a
	thickness along the deck's NORMAL, not straight down, which is the mistake that
	puts a 12 cm step at the top.
	"""
	var run := SLAB_X0 - RAMP_X0
	var rise := SLAB_Y
	var length := Vector2(run, rise).length()
	var theta := atan2(rise, run)
	# Midpoint of the deck, and the deck's own normal.
	var deck_mid := Vector2((RAMP_X0 + SLAB_X0) * 0.5, rise * 0.5)
	var normal := Vector2(-sin(theta), cos(theta))
	var centre := deck_mid - normal * (RAMP_THICK * 0.5)
	return {
		"name": "Ramp",
		"pos": Vector3(centre.x, centre.y, RAMP_Z),
		"size": Vector3(length, RAMP_THICK, RAMP_WIDTH),
		"rot": Vector3(0.0, 0.0, theta),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	}


static func _wing_boxes() -> Array[Dictionary]:
	"""
	The cell block wing: the service corridor, the four spine doors and the four
	cells, as `boxes()` entries.

	@return: Every box north of `WING_Z`, in build order (walls, crawl, spine,
	        cells, light).

	Its own function rather than another 150 lines inside `boxes()` for the reason
	`_ramp_box()` is: the arithmetic here is a run of derived spacings — four doors
	and three piers across one span, four cells and three dividers across the same
	span — and a derived spacing written inline next to hand-placed furniture is how
	a doorway ends up 4 cm off its pad. Every x below comes out of `_spine_door_x`,
	`_spine_pier_x` or `_cell_x`, which the self-check drives directly.
	"""
	var out: Array[Dictionary] = []
	var clear := headroom()
	var mid_y := clear * 0.5

	# ---- The wing wall: the hall's north boundary, with the crawl in it ----
	out.append({
		"name": "WingWallWest",
		"pos": Vector3((SLAB_X0 + CRAWL_X0) * 0.5, mid_y, WING_Z),
		"size": Vector3(CRAWL_X0 - SLAB_X0, clear, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "WingWallEast",
		"pos": Vector3((CRAWL_X1 + WING_JOG_X) * 0.5, mid_y, WING_Z),
		"size": Vector3(WING_JOG_X - CRAWL_X1, clear, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	# The jog around the shell's doorway, and the short return that closes it.
	out.append({
		"name": "WingWallJog",
		"pos": Vector3(WING_JOG_X, mid_y, (WING_Z + WING_JOG_Z) * 0.5),
		"size": Vector3(0.4, clear, WING_JOG_Z - WING_Z + 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	out.append({
		"name": "WingWallNorthEast",
		"pos": Vector3((WING_JOG_X + INNER_HALF) * 0.5, mid_y, WING_JOG_Z),
		"size": Vector3(INNER_HALF - WING_JOG_X, clear, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})

	# ---- The maintenance crawl: a lintel low enough to read as a duct, and a
	# press sweeping the gap under it. -----------------------------------------
	out.append({
		"name": "CrawlLintel",
		"pos": Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, (CRAWL_LINTEL_Y + clear) * 0.5, WING_Z),
		"size": Vector3(CRAWL_X1 - CRAWL_X0, clear - CRAWL_LINTEL_Y, 0.4),
		"color": COLOR_STONE, "collide": true, "floor": 0,
	})
	# `sweep` marks a part that is MOVING on any frame you look at it, the way
	# `spin` marks a rotor bar. Its position here is the TOP of the stroke, which is
	# where `press_y(0)` puts it — see that function.
	out.append({
		"name": "CrawlPress",
		"pos": Vector3((CRAWL_X0 + CRAWL_X1) * 0.5, PRESS_TOP, WING_Z),
		"size": Vector3(CRAWL_X1 - CRAWL_X0 - 0.1, 0.7, 0.6),
		"color": COLOR_HAZARD, "collide": false, "floor": 0,
		"sweep": true,
	})

	# ---- The spine wall: three piers, four doorways, four masses, four pads ----
	for i in 3:
		out.append({
			"name": "SpinePier%d" % (i + 1),
			"pos": Vector3(_spine_pier_x(i), mid_y, SPINE_Z),
			"size": Vector3(SPINE_PIER_W, clear, 0.4),
			"color": COLOR_STONE, "collide": true, "floor": 0,
		})
	for i in SPINE_DOORS.size():
		var door: Dictionary = SPINE_DOORS[i]
		# The mass fills its doorway to the ceiling, so there is nothing to jump
		# over and nothing to walk round — the two ways a gate stops being one.
		out.append({
			"name": String(door["mass"]),
			"pos": Vector3(_spine_door_x(i), mid_y, SPINE_Z),
			"size": Vector3(SPINE_DOOR_W, clear, 0.6),
			"color": COLOR_IDENTITY, "collide": true, "floor": 0,
		})
		# ...and the pad in front of it, 10 cm proud and non-solid: a change of
		# colour under your feet, never a lip to trip on.
		out.append({
			"name": String(door["pad"]),
			"pos": Vector3(_spine_door_x(i), 0.05, PAD_Z),
			"size": Vector3(SPINE_DOOR_W, 0.1, PAD_DEPTH),
			"color": COLOR_IDENTITY_PAD, "collide": false, "floor": 0,
		})

	# ---- The cells: three dividers and four containment frames ----------------
	var cell_mid := (CELL_Z0 + INNER_HALF) * 0.5
	var cell_depth := INNER_HALF - CELL_Z0
	for i in 3:
		out.append({
			"name": "CellDivider%d" % (i + 1),
			"pos": Vector3(_cell_x(i) + (_cell_width() + CELL_DIVIDER) * 0.5, mid_y, cell_mid),
			"size": Vector3(CELL_DIVIDER, clear, cell_depth),
			"color": COLOR_STONE, "collide": true, "floor": 0,
		})
	for i in TowerGraph.HEROES.size():
		out.append({
			"name": "CellFrame%s" % String(TowerGraph.HEROES[i]).capitalize(),
			"pos": Vector3(_cell_x(i), 1.25, INNER_HALF - 0.3),
			"size": Vector3(_cell_width() - 0.6, 2.5, 0.12),
			"color": COLOR_CELL, "collide": false, "floor": 0,
		})
	# THE ONE PIECE OF AUTHORED STAGING IN THE BUILDING. A standard cell plus a
	# steel containment screen across its mouth: the first rescue's identity comes
	# from what is IN the cell, never from the cell, because any hero can land in
	# any of them. Non-solid — it smothers a field, it is not a door — and gone for
	# good the moment `RESCUE_DONE` is in the opened set.
	# WAIST HIGH, and that was found by walking it rather than reasoned: built full
	# height it stood in front of the containment frame and hid it, so Primm's cell
	# read exactly like the three empty ones — the staging swallowed the one thing
	# this wing has to say from across the gallery.
	# The vent-purge pad. Same violet-pad shape as the four spine pads, in the
	# gallery rather than the corridor - it is operated from the wrong side of the
	# doors, by somebody the doors are keeping in.
	out.append({
		"name": "PurgePad",
		"pos": Vector3(PURGE_PAD_X, 0.05, PURGE_PAD_Z),
		"size": Vector3(1.1, 0.1, 1.1),
		"color": COLOR_SYSTEM, "collide": false, "floor": 0,
	})
	out.append({
		"name": "PrimmContainment",
		"pos": Vector3(_cell_x(TowerGraph.HEROES.find(AUTHORED_CAPTIVE)), 0.6, CELL_Z0 + 0.5),
		"size": Vector3(_cell_width() - 0.2, 1.2, 0.5),
		"color": COLOR_MECHANISM, "collide": false, "floor": 0,
	})

	# ---- Light. The wing is under the slab and the sun does not reach it. ----
	out.append({
		"name": "PanelStair",
		"pos": Vector3(4.0, clear - 0.05, (WING_Z + SPINE_Z) * 0.5),
		"size": Vector3(7.5, 0.1, 1.6),
		"color": COLOR_PANEL, "collide": false, "floor": 0,
	})
	out.append({
		"name": "PanelGallery",
		"pos": Vector3(4.15, clear - 0.05, (SPINE_Z + CELL_Z0) * 0.5 + 0.5),
		"size": Vector3(8.0, 0.1, 1.8),
		"color": COLOR_PANEL, "collide": false, "floor": 0,
	})
	return out


static func wing_span() -> float:
	"""The wing's full east-west run: the slab's west edge to the shell's inner face."""
	return INNER_HALF - SLAB_X0


static func _spine_door_x(index: int) -> float:
	"""
	Centre of the `index`th spine doorway, west to east.

	Four doors and three piers laid end to end across `wing_span()`, so the run is
	exact by construction: `4 * SPINE_DOOR_W + 3 * SPINE_PIER_W` must equal the
	span, which `tower_interior_selfcheck` asserts rather than trusts.
	"""
	return SLAB_X0 + SPINE_DOOR_W * 0.5 + float(index) * (SPINE_DOOR_W + SPINE_PIER_W)


static func _spine_pier_x(index: int) -> float:
	"""Centre of the `index`th pier — between doors `index` and `index + 1`."""
	return _spine_door_x(index) + (SPINE_DOOR_W + SPINE_PIER_W) * 0.5


static func cell_stand(hero: String) -> Vector3:
	"""
	Where the prison role stands a benched player up, in interior-local metres.

	@param hero: the captive - one of `TowerGraph.HEROES`. An unknown name lands in
	    the gallery, which is inside the block and therefore still legal.

	ONE PLAYER PER CELL comes free from the geometry: the cells are indexed by hero
	and a peer is benched holding exactly one, so two benched peers are two
	different recesses with no allocator, no registry and nothing to keep in step.

	`y` is the same 0.2 m lift `CUSTODY_STAND` uses - a body dropped exactly on the
	floor plane can start the frame a hair inside it.
	"""
	var index: int = TowerGraph.HEROES.find(hero)
	if index < 0:
		return Vector3(PURGE_PAD_X, 0.2, PURGE_PAD_Z)
	return Vector3(_cell_x(index), 0.2, (CELL_Z0 + INNER_HALF) * 0.5)


static func block_min() -> Vector3:
	"""
	The prison role's confinement box, low corner, in interior-local metres.

	THE GALLERY AND ITS FOUR CELLS AND NOTHING ELSE - everything north of the spine
	wall. The south face is `SPINE_Z`, which is where the four identity doors stand:
	a prisoner may walk the gallery and every cell (that is what makes freeing a
	CELLMATE possible, and it is the block's second system) but may never step
	through a spine door, which is the whole of "no solo escape". The 0.4 m inset
	keeps the clamp off the wall faces so a body pushed into the box is not pushed
	into geometry; `tower_interior_selfcheck` re-derives both corners rather than
	trusting these numbers.
	"""
	return Vector3(SLAB_X0 + 0.4, 0.0, SPINE_Z + 0.4)


static func block_max() -> Vector3:
	"""The confinement box's high corner - see `block_min()`."""
	return Vector3(INNER_HALF - 0.4, 0.0, INNER_HALF - 0.4)


static func _cell_width() -> float:
	"""How wide one cell is: the span less three dividers, split four ways."""
	return (wing_span() - 3.0 * CELL_DIVIDER) * 0.25


static func _cell_x(index: int) -> float:
	"""Centre of the `index`th cell, west to east — the same run, differently cut."""
	return SLAB_X0 + _cell_width() * 0.5 + float(index) * (_cell_width() + CELL_DIVIDER)


static func press_y(clock: float) -> float:
	"""
	Where the crawl press sits at `clock` seconds into its cycle.

	@param clock: 0 .. `PRESS_PERIOD`.
	@return: The mesh's y, in interior-local metres.

	A raised cosine, so it DWELLS at both ends: the gap under it is open long
	enough to walk through at a walk, which is the difference between a challenge
	and a coin flip. `press_y(0)` is the top of the stroke, which is where
	`_wing_boxes()` puts the box — so the table and the animation agree at t = 0
	and the self-check can assert the stroke's bounds from these two constants.
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


func _ready() -> void:
	"""Build the interior, its one collision body, its pads and its label."""
	add_to_group("tower_interior")

	# ONE StaticBody3D for the whole interior — the shell's rule, and the chunks'.
	var body := StaticBody3D.new()
	body.name = "InteriorCollision"
	add_child(body)

	# Two floor containers. Visibility is toggled on THESE, never on individual
	# meshes, so `_update_visibility` is two boolean writes however big a floor gets.
	for i in 2:
		var floor_node := Node3D.new()
		floor_node.name = "Floor%d" % i
		add_child(floor_node)
		_floors.append(floor_node)

	# THE STATIC GEOMETRY IS ONE MESH PER STOREY, batched below. Only the parts that
	# move or change colour get a node of their own.
	var batched: Array[Array] = [[], []]

	for box: Dictionary in boxes():
		var parent: Node3D = _floors[int(box["floor"])]
		var spin: float = float(box.get("spin", 0.0))
		if not is_zero_approx(spin):
			parent = _make_rotor(box, parent)
		elif not MOVING_PARTS.has(String(box["name"])):
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
		elif box["name"] == "IdentityMass":
			_mass_shape = shape
		elif box["name"] == SCAR_BOX:
			_scar_shape = shape
		else:
			var spine := _spine_gate_of(String(box["name"]))
			if spine != "":
				_spine_shapes[spine] = shape

	for i in _floors.size():
		var batch := MeshInstance3D.new()
		batch.name = "Floor%dBatch" % i
		batch.mesh = merged_mesh(batched[i])
		_no_shadow(batch)
		_floors[i].add_child(batch)

	_build_pads()
	_build_wing()
	_build_label()
	_build_vault_prize()
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
	_shutter_mesh.position.y = headroom() * 0.5 - drop
	if _shutter_shape != null:
		_shutter_shape.position.y = _shutter_mesh.position.y


func _place_mass() -> void:
	"""Put the identity mass where its open fraction says. It only ever rises."""
	if _mass_mesh == null:
		return
	var lift := MASS_TRAVEL * _mass_open
	_mass_mesh.position.y = SLAB_Y + UPPER_WALL_HEIGHT * 0.5 + lift
	if _mass_shape != null:
		_mass_shape.position.y = _mass_mesh.position.y


func _tick_pads() -> void:
	"""
	Re-decide both pads against the CURRENT hero, every frame.

	THIS IS THE IDENTITY GATE'S WHOLE CONTRACT and the reason it is polled rather
	than answered in `body_entered`: E switches character while you stand there, and
	ability state is cleared on a switch (player_controller's existing rule), so the
	only honest question is "who is standing here NOW". Nothing is buffered, nothing
	is held, nothing counts down.

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
	# WHICH hero the mass answers to is the graph's to say, not this file's — see
	# the GATE IDS block. The name is written down once, in `tower_graph.gd`.
	if (_on_identity_pad and _hero_name() == TowerGraph.identity_of(GATE_IDENTITY)
			and not _is_open(GATE_IDENTITY)):
		_open(GATE_IDENTITY)
		_say(tr("The mass lifts. The way through stays open."))
		_sfx("play_level_up")
	_tick_spine_pads()
	if not _on_demand_pad:
		return
	_update_bands()
	if not _is_open(GATE_DEMAND) and demand_met(_phase_reach()):
		_open(GATE_DEMAND)
		_say(tr("Calibration met. The vault opens."))
		_sfx("play_level_up")


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
	"""The three trigger volumes: demand plate, identity plate, checkpoint."""
	# NAMED `*Trigger`, NOT `*Pad`: the visible plates are meshes already carrying
	# those names, and two siblings with one name is a rename by the engine — which
	# turns every `get_node("Floor1/IdentityPad")` into a null.
	_add_area("DemandTrigger", Vector3(RECEPTACLE_X, 1.0, RECEPTACLE_Z + 1.3),
		Vector3(2.6, 2.0, 2.0), _on_demand_enter, _on_demand_exit, 0)
	_add_area("IdentityTrigger", Vector3(UPPER_WALL_X - 1.8, SLAB_Y + 1.0, 0.0),
		Vector3(2.6, 2.0, 3.0), _on_identity_enter, _on_identity_exit, 1)
	_add_area("CheckpointTrigger", Vector3(6.8, SLAB_Y + 1.0, 0.0),
		Vector3(3.0, 2.0, 3.0), _on_checkpoint_enter, Callable(), 1)


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


func _make_label(label_name: String, pos: Vector3, text: String) -> Label3D:
	"""
	One world label: billboarded, wrapped narrow, shadow-free, parented to storey 0.

	Shared by all three because they are the same object at a different position —
	see `_build_label()` for why these are world labels and not HUD toasts.

	WRAPPED, AND NARROW ON PURPOSE. A `Label3D` is geometry: an unwrapped
	explanation is a 5.7 m banner that runs straight into the walls either side of
	the receptacle's alcove and gets depth-culled mid-sentence, which is how the
	first build shipped a gate that said "...farm coins for the point". 700 px at
	this pixel size is 2.45 m — narrower than the niche it stands in, from both
	sides. (The wing's two signs then shrink themselves further; the corridor they
	hang in is narrower still, and `_build_wing()` says why.)
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
	_floors[0].add_child(label)
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
	_label = _make_label("DemandLabel",
		Vector3(RECEPTACLE_X, 3.2, RECEPTACLE_Z + 0.9), tr("PHASE RECEPTACLE"))


func _build_vault_prize() -> void:
	"""
	A single gem behind the demand gate — the reason to want in.

	One node, worth ten coins, and it is the EXISTING collectible rather than a
	tower-specific reward: the pickup, the sound, the streak and the level maths all
	already work. An empty vault would make the gate a puzzle about nothing.
	"""
	var gem := load("res://scenes/collectibles/coin.tscn").instantiate() as Node3D
	gem.name = "VaultGem"
	gem.position = Vector3(5.4, 1.1, -6.9)
	_floors[0].add_child(gem)
	if gem.has_method("make_gem"):
		gem.call("make_gem")


func _remember(box_name: String, mesh: MeshInstance3D) -> void:
	"""Keep the handful of meshes whose material or transform changes later."""
	match box_name:
		"DemandShutter":
			_shutter_mesh = mesh
		"IdentityMass":
			_mass_mesh = mesh
		"CheckpointPlate", "CheckpointPost":
			_checkpoint_meshes.append(mesh)
		"CrawlPress":
			_press = mesh
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
			var spine := _spine_gate_of(box_name)
			if spine != "":
				_spine_meshes[spine] = mesh


# ============================================================================
# THE CELL BLOCK WING — phase 8
# ============================================================================

func _build_wing() -> void:
	"""
	The wing's trigger volumes and its two labels.

	Four spine pads (polled, like every identity pad in this building) and four cell
	volumes (one-shot, because liberation is a thing you do and not a thing you
	stand in). Both are parented to storey 0, so they hide with it.
	"""
	for i in SPINE_DOORS.size():
		var gid := String(SPINE_DOORS[i]["gate"])
		_add_area("SpineTrigger%d" % (i + 1),
			Vector3(_spine_door_x(i), 1.0, PAD_Z),
			Vector3(SPINE_DOOR_W, 2.0, PAD_TRIGGER_DEPTH),
			_on_spine_enter.bind(gid), _on_spine_exit.bind(gid), 0)
	_add_area("PurgeTrigger",
		Vector3(PURGE_PAD_X, 1.0, PURGE_PAD_Z),
		Vector3(1.1, 2.0, 1.1),
		_on_purge_enter, _on_purge_exit, 0)
	var cell_mid := (CELL_Z0 + INNER_HALF) * 0.5
	for i in TowerGraph.HEROES.size():
		var hero := String(TowerGraph.HEROES[i])
		_add_area("CellTrigger%s" % hero.capitalize(),
			Vector3(_cell_x(i), 1.0, cell_mid),
			Vector3(_cell_width() - 0.4, 2.0, INNER_HALF - CELL_Z0 - 0.4),
			_on_cell_enter.bind(hero), Callable(), 0)

	# TWO LABELS AND NOT ONE, because a wall stands between the two rooms they speak
	# in and a `Label3D` is geometry: the corridor's line would be depth-culled from
	# the gallery and vice versa. Same construction as the receptacle's — see
	# `_build_label()` for why this is a world label and not a HUD toast.
	#
	# SMALLER AND HIGHER THAN THE RECEPTACLE'S, and that was found by looking rather
	# than reasoned: the receptacle stands at the end of a deep alcove you approach
	# from across the hall, so its 2.45 m banner is read at four metres. These two
	# live in a two-metre corridor where the spring arm puts the camera a metre from
	# them, and at the receptacle's size the first walkthrough was a screen full of
	# the word "open". Up near the ceiling and half the scale, they read as signage
	# on a wall instead of as a wall.
	_spine_label = _make_label("SpineLabel",
		Vector3(_spine_door_x(1) + (SPINE_DOOR_W + SPINE_PIER_W) * 0.5, 3.8, SPINE_Z - 0.4),
		tr("THE FOUR SPINES — one door each"))
	_cell_label = _make_label("CellLabel",
		Vector3(_cell_x(1) + (_cell_width() + CELL_DIVIDER) * 0.5, 3.8, CELL_Z0 - 0.35),
		tr("CELL BLOCK"))
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
	_press.position.y = press_y(_press_clock)


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

	Down, and not up, purely because this wing is roofed — see the block comment at
	`WING_Z`. Mesh and collision shape move together: a gate that opened only
	visually is the worst bug this file can have.
	"""
	var mesh: MeshInstance3D = _spine_meshes.get(gate_id)
	if mesh == null:
		return
	mesh.position.y = headroom() * 0.5 - SPINE_TRAVEL * float(_spine_open.get(gate_id, 0.0))
	var shape: CollisionShape3D = _spine_shapes.get(gate_id)
	if shape != null:
		shape.position.y = mesh.position.y


func _refresh_cells() -> void:
	"""
	Repaint every containment frame from the captive set, and hide the staging unit
	once the authored rescue is done.

	THE ONE PLACE CAPTIVITY BECOMES GEOMETRY, the way `_apply_opened` is the one
	place an opened gate does. Idempotent, so `set_captive()` can just call it.
	"""
	for hero: String in _cell_frames:
		var frame: MeshInstance3D = _cell_frames[hero]
		frame.material_override = _material(
			COLOR_CELL if _captives.has(hero) else COLOR_CELL_FREED)
	if _containment != null:
		_containment.visible = not _is_open(RESCUE_DONE)


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
#     the break-out is the wing's own lesson under a clock: read the door, switch to
#     the hero it names, stand on the pad. That is deliberately the game's verbs and
#     not a minigame — there is no new input and no new rule, only the old ones with
#     nothing already unlocked.
#   * THE SCAR (`apply_scar`), which is the one sanctioned exception to the graph's
#     edge-additive law: a survived protocol takes the courtyard stair away for good.
#
# WHERE THE STAND IS AND WHY IT IS NOT A CELL. The party wakes in the SERVICE
# CORRIDOR, on the wrong side of the spine wall — because a cell hangs off the
# gallery on an ungated edge (that is what "uniform cells" means), so a break-out
# that started in one would be three metres of walking and no scene at all. From the
# corridor the only way to a cell is through a door that asks for a name.

## Where the protocol stands the party up, in interior-local metres.
##
## THE MIDDLE OF THE CORRIDOR, and that is the camera's doing rather than the
## drama's. The run is 9.3 m and the spring arm is 8.25 m, so standing at either
## end and facing along it collapses the arm into the back of the hero's head (the
## wing's documented deferral, one room over from the courtyard's). From the middle,
## facing +X, the arm has ~4.8 m of corridor behind it and the shot reads.
##
## Clearances, all of them re-derived and ASSERTED by `tower_interior_selfcheck`
## rather than trusted here — a stand inside a wall is a body shoved through it on
## the first frame: south of the pad line (`PAD_Z` 3.9), north of the wing wall's
## inner face (`WING_Z` 2.2 + half of 0.4), and clear of the four spine doorways.
const CUSTODY_STAND: Vector3 = Vector3(4.15, 0.2, 2.95)


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
	_say_spine(tr("THE STAIR IS GONE."))
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


static func _spine_gate_of(box_name: String) -> String:
	"""Which spine gate a mass or pad belongs to, "" for a box that is neither."""
	for door: Dictionary in SPINE_DOORS:
		if box_name == String(door["mass"]) or box_name == String(door["pad"]):
			return String(door["gate"])
	return ""


# ============================================================================
# SIGNAL HANDLERS — every one of them guards on the "player" group
# ============================================================================
#
# "player" means the LOCAL player and nothing else (CLAUDE.md). A remote teammate
# is a RemoteAvatar with no physics body and cannot reach here at all; what these
# guards actually exclude is the crocodile population, which will happily wander
# in through the front door and would otherwise trip every pad in the building.

func _on_hazard_touched(body: Node3D) -> void:
	"""A rotor bar swept through the player. Costs a life, via the ONE damage verb."""
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
	The vent purge: scatter the pack around every teammate. See `PURGE_PAD_X`.

	Polled like every other pad in this building, and it fires the moment the
	cooldown allows rather than on a press — the wing has no new input, which is the
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
	free-and-rebuild of three bodies at the one moment nothing is looking at them.
	"""
	reset_guards()


func reset_guards() -> void:
	"""
	Free every guard and stand a fresh one on each authored post.

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
	for i in GUARD_POSTS.size():
		var authored: Dictionary = GUARD_POSTS[i]
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
	IN THE TREE rather than rows in `GUARD_POSTS` — a spawner that silently
	stopped instancing would otherwise be reported as three guards.
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
	return global_position + (CHECKPOINT_STAND if _is_open(GATE_CHECKPOINT)
			else ENTRY_STAND)


# ============================================================================
# VISIBILITY
# ============================================================================

func _update_visibility() -> bool:
	"""
	Draw only what is worth drawing: nothing at all when the player is far, and
	the current storey +/- 1 when they are near.

	@return: true when the interior is being drawn (and therefore worth animating).

	WITH TWO STOREYS THE +/-1 WINDOW HIDES NOTHING, and that is fine — the policy is
	the deliverable, not this run of it. `_floor_visible` is a pure function of two
	integers so a check can drive it at any storey count, and phase 8's cell block
	inherits a gate that is already correct instead of discovering it needs one.
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
	Is this interior-local point within the keep's walls — i.e. in a ROOM?

	The footprint is the shell's inner faces (`INNER_HALF` on both axes) and the
	ceiling is the top of its wall: everything the interior builds, the cell-block
	wing included, lives inside that box, so there is nothing to enumerate and a
	new room joins for free. The height term is what keeps Windman's Air Rush from
	reporting "indoors" while he is sightseeing over the parapet.

	Pure, allocation-free and three compares — `biome_at()`'s idiom, and safe to
	call every tick.
	"""
	return absf(local.x) <= INNER_HALF and absf(local.z) <= INNER_HALF \
			and local.y <= TowerShell.WALL_HEIGHT


static func current_floor(local_y: float) -> int:
	"""Which storey a height belongs to, in interior-local metres."""
	return 1 if local_y >= SLAB_Y - FLOOR_HYSTERESIS else 0


static func _floor_visible(index: int, current: int) -> bool:
	"""The gating policy itself: the current storey and its two neighbours."""
	return absi(index - current) <= 1


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
	Every box in `group`, welded into one `ArrayMesh` of at most two surfaces.

	@param group: `boxes()` entries, all of one storey.
	@return: A fresh ArrayMesh — matte surface first, emissive second, either
	        omitted when that storey has none of that kind.

	TWO SURFACES AND NOT ONE, because emissive is a material property and not a
	vertex one: a light panel and a stone wall cannot share a surface however
	similar their vertices are. Two is also the floor — every other difference
	between these boxes (colour, size, the ramp's tilt) is baked into the vertices,
	so a storey costs two draw calls whether it is four boxes or forty.
	"""
	var out := ArrayMesh.new()
	for glow: bool in [false, true]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		for box: Dictionary in group:
			if GLOW_COLORS.has(box["color"]) != glow:
				continue
			any = true
			_emit_box(tool, box)
		if not any:
			continue
		tool.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, _batch_material(glow))
	return out


static func _emit_box(tool: SurfaceTool, box: Dictionary) -> void:
	"""
	Append one box's triangles to a surface, in interior space and carrying its own
	colour.

	The vertices come from a real `BoxMesh` rather than from a hand-written cube, so
	the winding, the normals and the UVs are the engine's and cannot be subtly wrong
	in a way that only shows up under one light angle. Walking the INDEX array and
	emitting unindexed vertices is what lets `SurfaceTool` weld boxes that have no
	vertices in common.
	"""
	var arrays: Array = _box_mesh(box["size"]).get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(box["rot"]) if box.has("rot") else Basis.IDENTITY
	var placed := Transform3D(basis, box["pos"])
	var color: Color = box["color"]
	for i: int in indices:
		# CONVERTED, and it is not a nicety. `albedo_color` is authored in sRGB and
		# the engine converts it; a VERTEX colour is taken as linear and is not. Feed
		# the palette straight in and a batched box comes out visibly paler than the
		# same colour on an unbatched one — the hazard orange washed out to a custard
		# yellow, which is the sort of drift that makes a colour language stop
		# meaning anything.
		tool.set_color(color.srgb_to_linear())
		tool.set_normal(basis * normals[i])
		tool.add_vertex(placed * verts[i])


static func _batch_material(glow: bool) -> StandardMaterial3D:
	"""
	The batch's two materials, cached beside the per-box ones.

	Keyed by a colour that is not in the palette above (so the two caches cannot
	collide) — the material's own albedo is white and unused, because
	`vertex_color_use_as_albedo` is what actually colours these surfaces.
	"""
	var key := Color(0.0, 0.0, 1.0) if glow else Color(0.0, 0.0, 0.0)
	var hit: StandardMaterial3D = _materials.get(key)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.rim_enabled = true
	mat.rim = 0.4
	mat.rim_tint = 0.25
	if glow:
		# The emissive half cannot take its emission from vertex colour, so it is
		# UNSHADED instead: the albedo IS what you see, at any hour and any angle,
		# which is what a light panel wants anyway.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = mat
	return mat


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
	_materials[color] = mat
	return mat
