class_name TowerShell
extends Node3D
## THE TOWER — GastroDefense HQ, the building itself (epic godot-test1-3iy, phase 2).
##
## Phase 1 decided WHERE the tower stands (`endless_terrain.tower_site()`) and kept
## that disc clear (`tower_excludes()`, radius `TOWER_RADIUS`). This file is what
## stands there: a sealed 80 x 80 x 52 m block, the 20 m keep phase 3's interior is
## authored inside (see `KEEP_HALF`), a yard slab, a door line through both, and the
## door trigger the interior hangs off. Phase 13 grew the envelope to the ten-storey
## HQ and, more importantly, put a LID on it — see `ROOF_THICK`.
##
## SELF-BUILDING, LIKE `ability_effect.gd`. The scene file
## `scenes/tower/tower_shell.tscn` is a bare Node3D carrying this script — every
## box comes out of `boxes()` below at `_ready()`. That is not laziness dressed as
## architecture, it buys three things a hand-authored .tscn cannot:
##
##   * ONE TABLE, TWO BUILDINGS. `build_impostor()` reads the SAME table, so the
##     far-away silhouette the player steers toward and the building they arrive at
##     are the same shape by construction rather than by somebody remembering to
##     edit both. (See the impostor block below for why there is one at all.)
##   * THE BUDGET IS CHECKABLE. `tower_shell_selfcheck.gd` counts and measures the
##     table without instancing anything, the discipline `landmark_selfcheck.gd`
##     applies to the procedural landmarks.
##   * THE DOORWAY CANNOT DRIFT SHUT. The two front jambs and the door trigger are
##     all derived from `DOOR_HALF_WIDTH` / `DOOR_HEIGHT`, so there is no second
##     number that has to agree with a first one.
##
## WHAT THIS IS NOT: chunk content. It never touches `create_box()` /
## `block_batch` / the per-chunk MultiMesh (CLAUDE.md's "everything in the world is
## spawned procedurally from the terrain" is about the streamed field; this is one
## authored building at one authored place). It is instanced ONCE and parented to
## the terrain MANAGER, never to a chunk — the fauna precedent — so chunk unloading
## can never free it out from under a player standing in the doorway.
##
## MULTIPLAYER: nothing to sync. `tower_site()` is a CONSTANT (the HQ is hand-
## planned once and forever), so every peer builds the same tower in the same place
## from local information only — it does not even need the seed. No spawn packet,
## no claim, no authority.
##
## COST: 15 `MeshInstance3D`s, ONE `StaticBody3D` holding 13 box shapes, one `Area3D`,
## and 4 materials shared process-wide by the static cache below. That is the whole
## bill, once, for the life of a run.

# ============================================================================
# SIGNALS
# ============================================================================

## Fired every time a body in the "player" group walks into the doorway volume.
##
## THE DOORWAY IS THE INTERACTION — no prompt, no menu, no key to press: walking
## through it IS entering, exactly like a coin is collected by touching it. Phase 3
## (the interior) is what consumes this; for now the signal plus `entered` is the
## whole contract, and the shell is deliberately inert without a listener.
signal player_entered(body: Node3D)

# ============================================================================
# GEOMETRY — the keep, in metres, local space, feet at y = 0
# ============================================================================

## Half the keep's OUTER footprint. The walls are a 2 * OUTER_HALF square; every
## other horizontal number below derives from this one.
##
## 10 -> 40 IN PHASE 13 (80 x 80 m). The owner's "100x size" ruling is read as
## usable FLOOR AREA (epic note, 2026-08-29): 16x the footprint times 5x the
## storeys is the 100x, and 80 m square is what ~100-150 hand-planned rooms per
## the epic's phase 14 need. It is ~1.6 chunks across, which is why
## `endless_terrain.TOWER_RADIUS` had to grow with it.
const OUTER_HALF: float = 40.0

## Wall thickness, and the storey grid the height is made of.
##
## PHASE 13 REPLACED A NUMBER WITH A PRODUCT. The height used to be an authored
## 11 m (phase 3 raised it from 7 for two interior storeys); it is now ten storeys
## of 5.0 m, because the owner asked for "a 10-storey building" and the storey
## count is the thing being asked for. 5.0 m clears `tower_interior.SLAB_Y`'s
## floor-to-floor minimum (a storey has to be at least 4.6 m: the jump apex is
## 3.6125 m and a floor you can jump onto is not a floor) with room for a slab.
const WALL_THICK: float = 1.2
const STOREY_HEIGHT: float = 5.0
const STOREYS: int = 10
const WALL_HEIGHT: float = STOREY_HEIGHT * STOREYS

## THE INNER KEEP: the phase-3 building, preserved inside the phase-13 envelope.
##
## IT IS HERE BECAUSE A FLOOR PLAN IS MADE OF WALLS, AND HALF OF THIS ONE'S WERE
## THE SHELL'S. `TowerInterior`'s rotor posts, vault, spine wall and cell
## partitions all run to the shell's inner faces and are closed by them; move those
## faces 30 m out and the plan stops being a plan — you stroll round the end of the
## spine wall and into a cell from behind, past every identity gate in the wing.
## (Found by codex review, 2026-08-29, on the first cut of this phase.)
##
## So the 20 m keep those rooms were authored against stays exactly where it was,
## now as a structure standing inside a much larger hall, and the interior derives
## its `INNER_HALF` from KEEP_HALF instead of from OUTER_HALF — one source of the
## number, as before. The 30 m annulus around it is what PHASE 14 plans; when its
## storeys are authored against the real envelope this ring is what they replace.
const KEEP_HALF: float = 10.0
const KEEP_HEIGHT: float = 11.0

## THE ROOF, which is the whole point of this phase.
##
## The building is sealed: a solid `collide: true` slab over the entire footprint,
## with NO door, NO hatch and no way through it, ever. Windman's Air Rush is the
## only thing in the game that gains real altitude, and the epic's ruling is that
## the tower is entered through the door or not at all — so the answer is not a
## height nobody can reach (see the chain-launch note in
## `tower_shell_selfcheck._check_roof_is_above_windmans_reach`) but a lid.
##
## THICK ENOUGH TO BE THE PARAPET TOO. The slab spans WALL_HEIGHT -> 52 m, so the
## roof surface a flier could stand on is at 52 m — above one fully-skilled Air
## Rush launched from a 20 m massif summit (26.25 + 20 = 46.25 m) with margin, and
## it is one box instead of a slab plus four parapet walls whose tops would each
## be another ledge to reason about.
const ROOF_THICK: float = 2.0

## THE DOORWAY, and the only place its size is written down. The two front jambs
## are what is LEFT of the front wall once this hole is taken out of it, and the
## door trigger spans exactly the hole — so a doorway that drifts shut is a
## contradiction rather than a bug you have to notice. 6 m wide and 4 m tall clears
## a giant Teibi (the character with the largest silhouette) with room to spare.
##
## THE HOLE IS IN THE +X WALL, i.e. it faces back toward the world origin. The tower
## sits on -X (phase 1's ruling) and the player spawns at the origin, so a player who
## walks to the tower walks straight at the doorway instead of round the back.
##
## BOTH RINGS ARE CUT WITH THE SAME TWO NUMBERS, so the outer envelope's hole and the
## inner keep's hole are on one line and you walk straight through both. The door
## TRIGGER is on the keep's, because "entered the tower" is a claim about the rooms:
## the outer hole is a gateway into a courtyard.
const DOOR_HALF_WIDTH: float = 3.0
const DOOR_HEIGHT: float = 4.0

## How far the door trigger reaches on either side of the wall plane. It only has
## to be thicker than the furthest a player travels in one physics tick — the
## fastest run in the game is 9 m/s, i.e. 0.15 m at 60 Hz — so 1 m each way is two
## orders of margin against tunnelling, and short enough that standing outside the
## wall does not count as being inside.
const DOOR_TRIGGER_DEPTH: float = 1.0

## THE BEACON: the amber light that says "that shape on the horizon is the one you
## are walking to". It sits on the -X/-Z corner OF THE ROOF.
##
## PHASE 13 DELETED THE SPIRE IT USED TO STAND ON. A 22 m corner tower with an
## overhanging cap was the silhouette when the keep was 11 m tall; against a 52 m
## slab it is a bump, and — fatally for this phase — its cap was a 8.6 m wide
## horizontal top 22 m up, i.e. a landing pad from which a Windman re-launches.
## Identity comes from mass now (the epic's ruling), and the facade below the roof
## carries nothing wide enough to stand on.
const BEACON_SIDE: float = 4.0

## The yard: a flat visual slab under the whole compound. VISUAL ONLY and 3 cm
## proud of the ground — no collision shape, no lip to step over. The flat-world
## invariant (CLAUDE.md) says the ground stays at y = 0 and everything assumes it;
## a slab you could stand on would be the first raised terrain in the game and
## would fight coin settling, crocodile gravity and the wade test. It is a change
## of colour, nothing more.
##
## 45 AND NOT 48, and the three metres are arithmetic rather than taste: the yard
## is a SQUARE and `TOWER_RADIUS` is a CIRCLE, so its corners reach 45 * sqrt2 =
## 63.6 m of the 65 m disc. At 48 they would reach 67.9 m and stand in scenery the
## site was never promised to be clear of — which check 2 of the self-check would
## (correctly) refuse.
const YARD_HALF: float = 45.0
const YARD_LIFT: float = 0.03

## Hard cap on how many boxes the shell may be made of, asserted headlessly by
## `tower_shell_selfcheck.gd`.
##
## The number that matters on web `gl_compatibility` is DRAW CALLS, and each box is
## a `MeshInstance3D` — this building is permanently on screen once you are near it,
## so the budget is what stops "one more buttress" from being free. 12 leaves room
## for the interior phase to add a step or a threshold without a new ruling, and
## bites immediately if somebody starts modelling crenellations. The check also
## measures the FOOTPRINT against endless_terrain's `TOWER_RADIUS`, which is the
## other half of the budget and is deliberately NOT restated here.
##
## 12 -> 16 IN PHASE 13: yard + roof + beacon + THE SAME SIX-BOX RING TWICE (3
## walls, 2 jambs, a lintel) — the 80 m envelope and the 20 m keep preserved inside
## it (see KEEP_HALF) — is 15, with one spare slot, the same courtesy phase 3 was
## left. The spire, its cap and its overhang all went away (see BEACON_SIDE), so
## the growth is the inner ring and nothing else. A tenth STOREY is not ten more
## boxes: storeys are interior (phase 14) and the shell stays an extrusion however
## the plans grow. Phase 14 is also what deletes the inner ring again.
const BOX_BUDGET: int = 16

## Palette. Four colours, four materials, shared process-wide (see `_material`).
##
## DARKER THAN THEY LOOK ON PAPER, and deliberately. `main.tscn` grades the scene
## with a bright key light, glow and a BCS pass, and the ground and sky at the
## tower's latitudes are pale — a "weathered pale stone" wall at 0.6 albedo comes
## out of that pipeline as a white monolith with no readable edges (measured in the
## editor, 2026-08-28). Judge these against a screenshot, never against the swatch.
const COLOR_WALL := Color(0.44, 0.42, 0.40)      # weathered grey stone
const COLOR_ROOF := Color(0.26, 0.22, 0.28)      # dark slate cap, reads as a roof
const COLOR_YARD := Color(0.33, 0.31, 0.29)      # packed earth, a shade under the wall
const COLOR_BEACON := Color(1.0, 0.72, 0.18)     # the amber light on the roof

## Silhouette colour of the horizon impostor, and of its beacon. Deliberately DARK
## and unshaded: at 400 m the tower is a shape against a bright sky, and a shape is
## what has to read.
const IMPOSTOR_COLOR := Color(0.17, 0.19, 0.25)
const IMPOSTOR_BEACON_COLOR := Color(1.0, 0.78, 0.32)

# ============================================================================
# STATE
# ============================================================================

## True once any player has walked through the doorway this run. A latch, not a
## presence flag: phase 3 wants "has this player found the way in", and a bool that
## flickers as somebody paces the threshold answers a different question.
var entered: bool = false

## Every gate, stop and stage inside this tower that has been opened this run, as a
## SET of string ids (`{id: true}` — GDScript has no Set, and a Dictionary's key
## lookup is the whole reason this is not an Array).
##
## THE STATE LIVES HERE AND NOWHERE ELSE, and that placement is the design:
##
##   * IT IS WORLD STATE, NOT PLAYER STATE. The interior's identity gate asks who
##     is standing on the pad and then writes the answer HERE — so what changed is
##     the building, not a permission the local player carries around. That is what
##     the epic's multiplayer landmine asks for: syncing it later is one broadcast
##     of `opened_ids()`, with no per-player bookkeeping to unpick, because there
##     never was any.
##   * IT SURVIVES THE WHOLE RUN. The tower is manager-parented and freed only by
##     `new_run()`, so "walk out of the tower and back in, gates still open" is a
##     property of where this variable lives rather than of anything remembering to
##     save it.
##   * IT SURVIVES THE PROCESS. `_enter_tree()` hydrates it from
##     `BestRunStore.tower_opened_ids()` and `mark_opened()` writes straight
##     through, so "quit, relaunch, the gate is still open" needs nobody to
##     remember to save either. That is phase 5, and it is four lines because the
##     set was already the right shape.
##   * IT IS MONOTONE. Ids are only ever added — never removed, never re-closed —
##     which is what lets two copies merge with a union and no conflict rule (see
##     `BestRunStore.merge_tower_opened_ids`), and what stops a met demand gate
##     from ever re-locking: earned progression must never become upkeep.
##
## Ids are declared as consts on `TowerGraph` (`GATE_*`) and re-exported by
## `TowerInterior`. THEY ARE PERSISTED VERBATIM, so adding one is free and
## renaming one is a save migration.
var opened: Dictionary = {}

## Albedo colour -> the one material of that colour, for the whole process.
##
## The same discipline (and the same reason) as `ToonShading._styled_cache`: never
## a material per instance. There is only ever one tower, so the saving here is
## small and the POINT is the contract — the impostor, a second shell built by a
## self-check, and a shell rebuilt after `new_run()` all share these four, and the
## renderer can batch what shares a material.
static var _materials: Dictionary = {}


static func boxes() -> Array[Dictionary]:
	"""
	The whole building, as boxes: `{name, pos, size, color, collide}` in local metres.

	@return: One entry per `MeshInstance3D` the shell builds, in build order.

	THE SINGLE SOURCE OF THE SHAPE. `_ready()` builds the real thing from it,
	`build_impostor()` builds the far-away silhouette from it, and
	`tower_shell_selfcheck.gd` measures the budget and the footprint from it
	without instancing anything at all.

	Every position is a CENTRE and every size is a full extent, so a box occupies
	`pos ± size/2` — which is what makes the footprint measurement in the self-check
	a two-line loop over corners.
	"""
	# Centre of a wall slab: the outer face sits at OUTER_HALF, so the slab's middle
	# is half a thickness inside that.
	var wall_mid := OUTER_HALF - WALL_THICK * 0.5
	# The side walls run BETWEEN the two they meet, so the corners are not doubled.
	var side_len := 2.0 * (OUTER_HALF - WALL_THICK)
	# What is left of the front wall either side of the doorway.
	var jamb_len := OUTER_HALF - DOOR_HALF_WIDTH
	var jamb_mid := (OUTER_HALF + DOOR_HALF_WIDTH) * 0.5
	# The lintel bridges the hole, from the top of the doorway to the wall top.
	var lintel_height := WALL_HEIGHT - DOOR_HEIGHT
	# The beacon sits on the roof, over the -X/-Z corner.
	var beacon_mid := -(OUTER_HALF - BEACON_SIDE)

	var out: Array[Dictionary] = []
	# 1. The yard, first so everything else draws over it. No collision — see YARD_LIFT.
	out.append({"name": "Yard", "pos": Vector3(0.0, YARD_LIFT * 0.5, 0.0),
		"size": Vector3(2.0 * YARD_HALF, YARD_LIFT, 2.0 * YARD_HALF),
		"color": COLOR_YARD, "collide": false})
	# 2. The three solid walls. -X is the back (the door faces +X).
	out.append({"name": "WallBack", "pos": Vector3(-wall_mid, WALL_HEIGHT * 0.5, 0.0),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, 2.0 * OUTER_HALF),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "WallSideNegZ", "pos": Vector3(0.0, WALL_HEIGHT * 0.5, -wall_mid),
		"size": Vector3(side_len, WALL_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "WallSidePosZ", "pos": Vector3(0.0, WALL_HEIGHT * 0.5, wall_mid),
		"size": Vector3(side_len, WALL_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	# 3. The front wall, as two jambs and a lintel — i.e. a wall with a hole in it.
	out.append({"name": "DoorJambNegZ", "pos": Vector3(wall_mid, WALL_HEIGHT * 0.5, -jamb_mid),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "DoorJambPosZ", "pos": Vector3(wall_mid, WALL_HEIGHT * 0.5, jamb_mid),
		"size": Vector3(WALL_THICK, WALL_HEIGHT, jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "DoorLintel", "pos": Vector3(wall_mid, DOOR_HEIGHT + lintel_height * 0.5, 0.0),
		"size": Vector3(WALL_THICK, lintel_height, 2.0 * DOOR_HALF_WIDTH),
		"color": COLOR_WALL, "collide": true})
	# 4. THE INNER KEEP: the phase-3 ring, same six boxes, same door line, still
	#    open-topped exactly as it was — the interior is authored against these
	#    faces (see KEEP_HALF).
	var keep_mid := KEEP_HALF - WALL_THICK * 0.5
	var keep_side_len := 2.0 * (KEEP_HALF - WALL_THICK)
	var keep_jamb_len := KEEP_HALF - DOOR_HALF_WIDTH
	var keep_jamb_mid := (KEEP_HALF + DOOR_HALF_WIDTH) * 0.5
	out.append({"name": "KeepWallBack", "pos": Vector3(-keep_mid, KEEP_HEIGHT * 0.5, 0.0),
		"size": Vector3(WALL_THICK, KEEP_HEIGHT, 2.0 * KEEP_HALF),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "KeepWallSideNegZ", "pos": Vector3(0.0, KEEP_HEIGHT * 0.5, -keep_mid),
		"size": Vector3(keep_side_len, KEEP_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "KeepWallSidePosZ", "pos": Vector3(0.0, KEEP_HEIGHT * 0.5, keep_mid),
		"size": Vector3(keep_side_len, KEEP_HEIGHT, WALL_THICK),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "KeepJambNegZ", "pos": Vector3(keep_mid, KEEP_HEIGHT * 0.5, -keep_jamb_mid),
		"size": Vector3(WALL_THICK, KEEP_HEIGHT, keep_jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "KeepJambPosZ", "pos": Vector3(keep_mid, KEEP_HEIGHT * 0.5, keep_jamb_mid),
		"size": Vector3(WALL_THICK, KEEP_HEIGHT, keep_jamb_len),
		"color": COLOR_WALL, "collide": true})
	out.append({"name": "KeepLintel", "pos": Vector3(keep_mid,
			DOOR_HEIGHT + (KEEP_HEIGHT - DOOR_HEIGHT) * 0.5, 0.0),
		"size": Vector3(WALL_THICK, KEEP_HEIGHT - DOOR_HEIGHT, 2.0 * DOOR_HALF_WIDTH),
		"color": COLOR_WALL, "collide": true})
	# 5. THE LID. One slab over the whole footprint, so every wall top underneath it
	#    is covered rather than exposed — that is what makes the facade smooth: the
	#    only horizontal surface a flier can put his feet on is the top of this box.
	#    It spans the full 2 * OUTER_HALF square, not the inner hole, so it also is
	#    its own parapet (see ROOF_THICK).
	out.append({"name": "Roof", "pos": Vector3(0.0, WALL_HEIGHT + ROOF_THICK * 0.5, 0.0),
		"size": Vector3(2.0 * OUTER_HALF, ROOF_THICK, 2.0 * OUTER_HALF),
		"color": COLOR_ROOF, "collide": true})
	# 6. The beacon, standing on the roof. No collision: it is a light, and a
	#    1-box plinth is not a place to stand.
	out.append({"name": "Beacon", "pos": Vector3(beacon_mid,
			WALL_HEIGHT + ROOF_THICK + BEACON_SIDE * 0.5, beacon_mid),
		"size": Vector3(BEACON_SIDE, BEACON_SIDE, BEACON_SIDE),
		"color": COLOR_BEACON, "collide": false})
	return out


static func door_trigger_box() -> Dictionary:
	"""
	The doorway volume, as the same `{pos, size}` shape `boxes()` speaks.

	@return: Centre and full extent of the `Area3D`'s box, local metres.

	Derived from the SAME `DOOR_*` constants the jambs are cut around, which is the
	whole reason it is a function and not a literal in `_ready()`: the trigger is
	the hole, so it cannot end up somewhere the hole is not. It is on the INNER
	KEEP's door line — walking through the outer envelope's hole puts you in a
	courtyard, and "entered the tower" means the rooms (see DOOR_HALF_WIDTH). `tower_shell_selfcheck`
	asserts exactly that — no wall box may overlap this volume.
	"""
	var wall_mid := KEEP_HALF - WALL_THICK * 0.5
	return {
		"pos": Vector3(wall_mid, DOOR_HEIGHT * 0.5, 0.0),
		"size": Vector3(WALL_THICK + 2.0 * DOOR_TRIGGER_DEPTH,
			DOOR_HEIGHT, 2.0 * DOOR_HALF_WIDTH),
	}


static func footprint_radius() -> float:
	"""
	How far the shell reaches from its own centre, horizontally.

	@return: Metres, measured to the furthest CORNER of the furthest box.

	This is the number that has to fit inside phase 1's exclusion disc, and it is
	measured rather than declared so it can never quietly disagree with the geometry
	above. The comparison against `endless_terrain.TOWER_RADIUS` lives in the
	self-check, where the constant can be read from its owner instead of restated
	here (the bead's landmine: share the constant, never copy the number).
	"""
	var worst := 0.0
	for box: Dictionary in boxes():
		var pos: Vector3 = box["pos"]
		var half: Vector3 = box["size"] * 0.5
		# Furthest corner of an axis-aligned box from the origin, in XZ.
		worst = maxf(worst, Vector2(absf(pos.x) + half.x, absf(pos.z) + half.z).length())
	return worst


static func build_impostor() -> Node3D:
	"""
	THE HORIZON IMPOSTOR: the tower as it looks from 400 m away, which is to say
	as a shape.

	@return: A fresh, unparented Node3D holding the silhouette. The caller places it
	        at `tower_site()` and hides it once the real shell exists.

	WHY IT EXISTS (owner ruling, 2026-08-27: wayfinding, and it ships with this
	phase). The real shell is not instanced until the player is within
	`TOWER_LOAD_RADIUS`, and even if it were, the web build draws nothing past
	`render_distance` (150 m) and drowns what is left in fog at density 0.005 — so
	at 400 m the actual building is not merely dim, it is absent. Without a stand-in
	the tower is a place the minimap knows about and the world does not, and the
	walk out there is 400 m of featureless field.

	FOG-EXEMPT AND UNSHADED, which is the entire trick: `disable_fog` opts the
	material out of the depth fog that would otherwise erase it, and unshaded means
	its colour does not wash out with the light angle. It is the same boxes as the
	real shell at the same true scale — NOT scaled up — so walking toward it makes
	it grow the way a building does, and the swap to the real shell (which happens
	well outside fog range) changes nothing you can see.

	NO COLLISION, NO GROUP, NO SCRIPT: it is a picture, and the only thing that can
	ever be done to it is `visible = false`.
	"""
	var root := Node3D.new()
	root.name = "TowerImpostor"
	for box: Dictionary in boxes():
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _box_mesh(box["size"])
		mesh.position = box["pos"]
		var beacon: bool = box["color"] == COLOR_BEACON
		mesh.material_override = _impostor_material(
			IMPOSTOR_BEACON_COLOR if beacon else IMPOSTOR_COLOR)
		# The silhouette must never be the reason something else does not draw.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	return root


func _ready() -> void:
	"""Build the keep, its one collision body, and the door trigger."""
	# Group registration so phase 3's interior, a self-check or the HUD can find the
	# tower the project's way — no hard references anywhere (CLAUDE.md).
	add_to_group("tower")

	# ONE StaticBody3D for the whole building, the same rule chunks follow (one
	# collision body per chunk): a body per wall would be eight physics islands
	# where one does.
	var body := StaticBody3D.new()
	body.name = "TowerCollision"
	add_child(body)

	for box: Dictionary in boxes():
		var mesh := MeshInstance3D.new()
		mesh.name = box["name"]
		mesh.mesh = _box_mesh(box["size"])
		mesh.position = box["pos"]
		mesh.material_override = _material(box["color"])
		add_child(mesh)
		if not box["collide"]:
			continue
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = box["size"]
		shape.shape = box_shape
		shape.position = box["pos"]
		shape.name = "%sShape" % box["name"]
		body.add_child(shape)

	# The door trigger — an Area3D on the coin's idiom (coin.gd extends Area3D and
	# reacts to `body_entered` from the "player" group). Monitorable is off: nothing
	# ever asks whether the doorway is inside something else, and leaving it on
	# costs a broadphase entry for no reader.
	var door := Area3D.new()
	door.name = "DoorTrigger"
	door.monitorable = false
	var trigger: Dictionary = door_trigger_box()
	var door_shape := CollisionShape3D.new()
	var door_box := BoxShape3D.new()
	door_box.size = trigger["size"]
	door_shape.shape = door_box
	door.add_child(door_shape)
	door.position = trigger["pos"]
	door.body_entered.connect(_on_door_body_entered)
	add_child(door)


func _enter_tree() -> void:
	"""
	Hydrate the opened set from the local save before anything can read it.

	`_enter_tree` and not `_ready`, and that is the whole subtlety: ready
	propagates CHILDREN FIRST, so `TowerInterior._ready()` — which calls
	`_apply_opened()` to snap the gates to the set with no animation — runs before
	this node's own `_ready()` would. `_enter_tree` propagates parent first, so the
	set is loaded before the interior is built from it and a restored gate comes up
	open on its first frame, exactly as check 8 of `tower_interior_selfcheck.gd`
	asserts for a hand-seeded set.

	The merge is a union into whatever is already here, so re-entering the tree
	cannot lose an id opened while detached.
	"""
	for id: String in BestRunStore.tower_opened_ids():
		opened[id] = true


func mark_opened(id: String) -> void:
	"""
	Record a gate as open. Idempotent, and the only writer of `opened`.

	@param id: One of `TowerGraph`'s `GATE_*` constants.

	WRITES THROUGH IMMEDIATELY, on the opening only. A gate opening is rare and
	precious — a handful of times in a whole campaign — so there is nothing to
	batch and everything to lose by deferring it to a flush a crash can eat. The
	early return is what keeps it off any repeated path: re-marking an open gate,
	including every id this shell just hydrated, touches no disk at all.
	"""
	if opened.has(id):
		return
	opened[id] = true
	BestRunStore.merge_tower_opened_ids([id])


func is_opened(id: String) -> bool:
	"""
	Has this gate been opened this run?

	@param id: One of `TowerInterior`'s `GATE_*` constants.
	@return: true once `mark_opened` has been called for it.
	"""
	return opened.has(id)


func opened_ids() -> Array:
	"""
	Every opened id, sorted.

	@return: A fresh sorted Array of String — the caller may keep or mutate it.

	SORTED SO IT IS COMPARABLE. Dictionary key order is insertion order, which
	means two players who opened the same three gates in different orders would
	produce two different arrays; phase 5 merges these and a self-check compares
	them, and both want the set rather than the history.
	"""
	var out: Array = opened.keys()
	out.sort()
	return out


func sheltered(pos: Vector3) -> bool:
	"""
	Is this world point under the roof?

	@param pos: A world-space position.
	@return: true anywhere inside the roofed footprint, below the roof slab.

	THE BUILDING OWNS THIS QUESTION, because the building owns the numbers. Phase
	13 put a lid on the shell (`ROOF_THICK`) and the weather did not notice: a
	storm cloud drifting over the HQ drew rain through the slab and grounded
	Windman indoors (bug godot-test1-li2). `TowerInterior.inside_walls()` is the
	wrong boundary to ask — it is the 20 m phase-3 keep, not the 80 m footprint the
	roof actually covers — and restating OUTER_HALF anywhere else is how the two
	drift apart the next time the envelope grows.

	`to_local` rather than subtracting `global_position`: the shell is parked
	unrotated today (`endless_terrain._tower_build_shell`), and this stays correct
	on the day somebody turns it.

	Half-open at the top: the roof's UNDERSIDE is the ceiling, so a player standing
	ON the roof (y >= WALL_HEIGHT) is outdoors and gets rained on, which is the
	answer that makes the gate read as a roof rather than as a column of immunity
	reaching to the sky. Below y = 0 is the yard slab's underside — nothing stands
	there, but answering true costs nothing and keeps the test a simple range.

	Cheap enough for the per-tick weather query that consumes it: one transform
	multiply and three compares, no allocation.
	"""
	var local: Vector3 = to_local(pos)
	if local.y < 0.0 or local.y >= WALL_HEIGHT:
		return false
	return absf(local.x) <= OUTER_HALF and absf(local.z) <= OUTER_HALF


func _on_door_body_entered(body: Node3D) -> void:
	"""
	Somebody touched the doorway volume. Only the LOCAL player counts.

	"player" means the local player and nothing else (CLAUDE.md) — a remote
	teammate is a `RemoteAvatar`, which joins no group and carries no physics body,
	so it cannot reach here at all and this guard is not what excludes it. What the
	guard does exclude is every crocodile in the world: they are `CharacterBody3D`s
	that will happily wander into the doorway, and a tower that reports itself
	entered because a croc walked past would hand phase 3 a lie.
	"""
	if not body.is_in_group("player"):
		return
	entered = true
	player_entered.emit(body)


static func _box_mesh(size: Vector3) -> BoxMesh:
	"""A BoxMesh of exactly this size. One per box — nine meshes for the building,
	which is not worth a cache the way the materials are (a `BoxMesh` carries its
	size, so sharing one would mean scaling nine `MeshInstance3D`s instead, and
	scaled instances are the thing that breaks batching)."""
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	"""
	The one material of this colour, for the life of the process.

	ALREADY TOON, on purpose. `ToonShading.apply_to_mesh()` skips a material whose
	`diffuse_mode` is already `DIFFUSE_TOON`, so authoring these the way that helper
	would have left them means the tower matches the cast's cel-shaded look AND can
	never be handed to the styler for a per-instance `duplicate()`. The rim numbers
	are copied from `ToonShading` deliberately — same look, one source of truth for
	what that look is, and `tower_shell_selfcheck` asserts they still agree.
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
	if color == COLOR_BEACON:
		# The beacon is a light, not a stone: unshaded and emissive so it holds its
		# colour at any hour and at any angle. It is the one part of the real shell
		# that reads the same as its impostor counterpart.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = color
	_materials[color] = mat
	return mat


static func _impostor_material(color: Color) -> StandardMaterial3D:
	"""
	The impostor's flat, fog-exempt material — keyed into the SAME static cache as
	the shell's, so the whole tower feature owns a fixed handful of materials no
	matter how many times anything is built.

	`disable_fog` is the load-bearing flag: without it the silhouette is erased by
	the same depth fog that erases the real building, and the impostor answers
	nothing. Unshaded keeps it a flat colour at 400 m, where a lit surface would
	just be a slightly different grey than the sky.
	"""
	var hit: StandardMaterial3D = _materials.get(color)
	if hit != null:
		return hit
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_fog = true
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON  # so ToonShading never duplicates it
	_materials[color] = mat
	return mat
