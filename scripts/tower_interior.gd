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
## It is a child of the shell, built by `TowerShell._ready()`, so it exists exactly
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
## slab clears that 3.5 m with room for the arm's 0.25 m margin, so the arm never
## slams in on flat ground; the courtyard and the upper floor are open to the sky
## and have no ceiling at all. That is why the entry hall is the only enclosed room
## in the building and why it is 4.2 m and not 3.
##
## ============================================================================
## COST
## ============================================================================
##
## 26 `MeshInstance3D`s, ONE `StaticBody3D`, five `Area3D`s (three pads and two
## rotor hazards), two rotor pivots, one `Label3D` and one gem — built once, for
## the life of a run. Per-floor visibility
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
## building. 32 leaves room for phase 8's cell block to add a few walls without a
## new ruling and bites the moment somebody starts furnishing.
const BOX_BUDGET: int = 32

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

## Which colours are EMISSIVE AND UNSHADED. There are no `Light3D`s anywhere in
## this building: a real light under the slab would cost a shadow pass on a
## renderer (`gl_compatibility`) that is the whole reason for the visibility gating
## above. A glowing box is a draw call that was happening anyway.
const GLOW_COLORS: Array[Color] = [
	COLOR_BAND_LIT, COLOR_IDENTITY_PAD, COLOR_CHECKPOINT_LIT, COLOR_PANEL,
]

# ============================================================================
# GATE IDS — the strings that go in the opened set
# ============================================================================
#
# Stable, lowercase, prefixed by the tower. They are persisted verbatim by phase 5,
# so RENAMING ONE IS A SAVE MIGRATION. Add, never rename.

const GATE_DEMAND: String = "tower_vault"
const GATE_IDENTITY: String = "tower_secure_door"
const GATE_CHECKPOINT: String = "tower_checkpoint"

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

## The partway reaction's clock, counting 0 -> 1 over NUDGE_TIME. Zero when idle.
var _nudge: float = 0.0
var _nudge_ratio: float = 0.0

## True once the demand gate has explained itself. ONE TIME, EVER, per run: the
## explanation is what turns a refusal into a diagnosis, and a line that reappears
## every time you walk past stops being read.
var _explained: bool = false

## Which pads currently have the local player standing on them. Tracked by
## `Area3D` signals rather than polled overlaps, and re-read every frame against
## the CURRENT hero — which is the whole identity-gate contract: it keys on who is
## standing there, not on who walked in.
var _on_demand_pad: bool = false
var _on_identity_pad: bool = false

## Cached local player. Revalidated every frame — a respawn does not free it, but a
## self-check running without one must not crash.
var _player: Node3D = null

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
	out.append({
		"name": "RotorJambPosZ",
		"pos": Vector3(ROTOR_POST_X, SLAB_Y * 0.5, (RAMP_UNDER_Z + ROTOR_DOOR_HALF) * 0.5),
		"size": Vector3(0.4, SLAB_Y, RAMP_UNDER_Z - ROTOR_DOOR_HALF),
		"color": COLOR_STONE, "collide": true, "floor": 0,
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
	out.append({
		"name": "PanelHallNorth",
		"pos": Vector3(5.4, hall_clear - 0.05, 3.4),
		"size": Vector3(4.0, 0.1, 4.0),
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

	for box: Dictionary in boxes():
		var parent: Node3D = _floors[int(box["floor"])]
		var spin: float = float(box.get("spin", 0.0))
		if not is_zero_approx(spin):
			parent = _make_rotor(box, parent)
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _box_mesh(box["size"])
		# A rotor bar hangs off a pivot that is already at the post, so only its
		# HEIGHT is local; everything else is placed in interior space.
		mesh.position = Vector3(0.0, box["pos"].y, 0.0) if not is_zero_approx(spin) else box["pos"]
		if box.has("rot"):
			mesh.rotation = box["rot"]
		mesh.material_override = _material(box["color"])
		parent.add_child(mesh)
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

	_build_pads()
	_build_label()
	_build_vault_prize()
	# Whatever the tower already knows is open, apply it NOW — before the first
	# frame, with no animation. This is the seam phase 5 loads a save through, and
	# the reason the acceptance walk ("out and back in, gates still open") is a
	# property of the code rather than of nothing ever being freed.
	_apply_opened()
	_update_bands()


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
	_tick_gates(delta)
	_tick_pads()


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
	_place_shutter()
	_place_mass()


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
	"""
	if _player == null:
		return
	var hero := _hero_name()
	if _on_identity_pad and hero == "teibi" and not _is_open(GATE_IDENTITY):
		_open(GATE_IDENTITY)
		_say(tr("The mass lifts. The way through stays open."))
		_sfx("play_level_up")
	if _on_demand_pad:
		_update_bands()


func _attempt_demand() -> void:
	"""
	The player stepped onto the receptacle's plate — a deliberate attempt.

	Either the reading meets the calibration and the vault opens for good, or it
	does not and the gate answers with the two things the epic's legibility rules
	require: a PARTWAY REACTION (the shutter moves as far as you are strong) and,
	the first time only, an EXPLANATION that names the capability, the number, and
	the fact that ranks fix it. Diagnosable, then forecastable.
	"""
	if _is_open(GATE_DEMAND):
		return
	var reach := _phase_reach()
	_nudge_ratio = clampf(reach / DEMAND_TARGET, 0.0, 1.0)
	_update_bands()
	if reach >= DEMAND_TARGET:
		_open(GATE_DEMAND)
		_say(tr("Calibration met. The vault opens."))
		_sfx("play_level_up")
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
	var ratio := clampf(_phase_reach() / DEMAND_TARGET, 0.0, 1.0)
	var lit := DEMAND_BANDS if _is_open(GATE_DEMAND) else int(floor(ratio * float(DEMAND_BANDS)))
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
	_label = Label3D.new()
	_label.name = "DemandLabel"
	_label.text = tr("PHASE RECEPTACLE")
	_label.font_size = 48
	_label.outline_size = 14
	_label.pixel_size = 0.004
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = COLOR_BAND_LIT
	_label.position = Vector3(RECEPTACLE_X, 3.2, RECEPTACLE_Z)
	_floors[0].add_child(_label)


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
		_:
			if box_name.begins_with("Band"):
				_band_meshes.append(mesh)


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
	var near := Vector2(there.x - here.x, there.z - here.z).length() <= DRAW_RADIUS
	visible = near
	if not near:
		return false
	var current := current_floor(there.y - here.y)
	for i in _floors.size():
		_floors[i].visible = _floor_visible(i, current)
	return true


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


func _sfx(method: String) -> void:
	"""Fire a synthesized sound, if there is a sound manager and it knows this one."""
	var sound := get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method(method):
		sound.call(method)


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
