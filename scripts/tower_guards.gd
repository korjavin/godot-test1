class_name TowerGuards
extends RefCounted
## THE HQ'S GUARDS — the population half of "structure persists, population resets".
##
## Lifted whole out of `tower_interior.gd` by bead `godot-test1-ftn.20`, the second
## of the epic's three tower extractions. A MECHANICAL move: not one post, yaw,
## leash, budget or ruling changed, and the acceptance is that every guard body's
## position after `reset()` is byte-identical against master.
##
## THE SPLIT. `TowerInterior` keeps the BUILDING; this file keeps the bodies
## standing in it — where a post is (read out of the `G` glyphs on the plan), what
## a beat is, the scene they instance from, and the free-and-rebuild that IS the
## persistence contract. `TowerDossiers`' idiom exactly: static functions handed
## the interior node, because there is no guard state that is not the interior
## NODE's (`_guards` is its child), so a library that is handed the node costs no
## object and leaves the state where the rest of the building can still see it.
##
## THREE THINGS STAYED BEHIND, each for a reason:
##
##   * `_on_tower_doorway` — a `player_entered` handler belongs to the node whose
##     signal it is (`TowerDossiers._on_dossier_enter`'s precedent, verbatim). Its
##     body is one call to `reset_guards()`, which forwards here.
##   * `setback_point()` — it sits under the interior's GUARDS banner by accident
##     of history and its own docstring says it is NOT a guard's: since bd
##     `godot-test1-3iy.19` an arrest waives the knockback, so that function is the
##     plate for the press, a pre-beat guard and an animal that followed you in. It
##     reads `_is_open(GATE_CHECKPOINT)`, `checkpoint_stand()` and `entry_stand()`
##     — the GATE family, which is bd `godot-test1-ftn.21`'s. Moving it here would
##     put a gate reader in a file about guards and hand ftn.21 a dependency it
##     would have to undo.
##   * `set_captive` and the captive mirror, and `investigate_point`'s plate side:
##     the lure's seam is the guard AI's (`piglet_crocodile_ai.gd`), not the
##     interior's, and captivity is per-run world state rather than population.
##
## THE OWNER RULINGS MOVED WITH THE CODE, UNCHANGED — at most one guard per storey
## and it is asserted off the BODIES (`GUARDS_PER_STOREY_MAX`), guards are never
## persisted by anybody, and the population resets on `player_entered`. Read them
## where they are written, below.
##
## DEPENDENCY DIRECTION: this file reads `TowerPlans` and `TowerPlanBoxes` (the
## plan grid, since bd `godot-test1-ftn.19`) and takes the interior as an argument.
## `TowerInterior` const-aliases four names back and forwards four calls; the const
## direction is ONE WAY, exactly as it is for `TowerPlanBoxes`, and a top-level
## const pointing the other way would make it a parse-time cycle.
##
## THAT IS WHY THE TWO `interior` PARAMETERS ARE UNTYPED — a type annotation is a
## parse-time reference just like a `const`, so annotating them closes exactly the
## cycle the aliases open. `TowerDressing` and `TowerDossiers` type theirs because
## nothing on the interior points back at them with a `const`; this file is the
## first that is both handed the node AND const-aliased from it. The intent lives
## in the docstrings instead.

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
## `tower_guard_selfcheck` counts the BODIES under `Guards` per storey. A
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
	enforced where it can actually be seen — on the built population, in
	`tower_guard_selfcheck`'s check 12 —
	rather than by this function silently picking one and hiding the second.

	AND THE PATROL AXIS IS ALSO THE SPAWN FACING (`yaw`), which is not decoration.
	The chassis is 2.025 m long (bead `godot-test1-6bj` scaled it 1.5x) and a plan
	cell is 1.94 m, so a guard is LONGER THAN THE CELL IT STANDS ON: stood across a
	one-cell corridor it is inside the wall before it has taken a step, and
	`move_and_slide` depenetrates it off the post nobody moved it from. Facing it
	along the beat it was just measured for is the fix and costs nothing — the run
	of `.` cells it paces is exactly the run its body needs to lie in.

	CEILING, AND IT IS THE SPAWN THAT MATTERS: a guard turns freely once it is
	walking, so in a one-cell corridor a heading broadside to the lane still puts
	the ends of the capsule in the walls. That is an ordinary moving contact
	`move_and_slide` slides out of, and the heading is transient because a patrol's
	facing follows its motion; a body that STARTS buried is the one that gets
	resolved somewhere nobody authored. If the chassis is ever scaled again, the
	fix is a wider lane (two cells) under the `G`, not a longer list of yaws.
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
	var along_the_x: bool = along_x >= along_z
	var half := (Vector2(reach, GUARD_PATROL_LANE_HALF) if along_the_x
			else Vector2(GUARD_PATROL_LANE_HALF, reach))
	var at := Vector3(TowerPlanBoxes._grid_x(float(cell.x) + 0.5), TowerPlanBoxes.FLOOR_Y[floor_index],
			TowerPlanBoxes._grid_z(float(cell.y) + 0.5))
	return {
		"name": "Floor%d" % floor_index,
		"post": at,
		"patrol_center": at,
		"patrol_half": half,
		# The body's long axis is its local +Z (that is where the capsule lies in
		# `tower_guard.tscn`), so a yaw of 0 faces +Z and PI/2 faces +X.
		"yaw": (PI * 0.5 if along_the_x else 0.0),
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
# THE POPULATION — free everything and stand it back up
# ============================================================================

static func reset(interior) -> void:
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

	`interior` IS DELIBERATELY UNTYPED, and it is the one concession this extraction
	makes. `TowerInterior` const-aliases four of the names above, which is a
	PARSE-TIME reference from there to here; annotating this parameter would make one
	from here to there and the pair becomes a cycle the parser refuses outright
	(measured — "Could not resolve class TowerInterior, because of a parser error",
	and every script that named the class went down with it). `TowerDressing` and
	`TowerDossiers` can type theirs because nothing on the interior points back at
	them with a `const`. So: this is a `TowerInterior`, it is only ever called with
	one, and the type is left off so the const direction can stay one-way.
	"""
	# WORLD SPACE IS THE POINT OF BEING IN THE TREE: `set_confinement()` below takes
	# a world centre, so a detached interior would leash every guard to a box around
	# the origin. Nothing in the shipped game can reach here detached (the deferral
	# in `_ready()` and the door signal both run in-tree); this is the standalone
	# degrade the project asks for rather than an error nobody can act on.
	if not interior.is_inside_tree():
		return
	if is_instance_valid(interior._guards):
		# `remove_child` BEFORE `queue_free`, and it is not tidiness: a queued node
		# keeps its name until the frame ends, so adding the replacement first would
		# hit a duplicate "Guards" and the engine would silently rename the NEW
		# container. Every `get_node("Guards")` in the building — and in the check —
		# would then keep answering with the corpse.
		# Spelled out rather than inferred: `interior` is untyped (see the note in this
		# function's docstring), so `:=` has nothing to infer from.
		var retired: Node3D = interior._guards
		interior.remove_child(retired)
		retired.queue_free()
	interior._guards = Node3D.new()
	interior._guards.name = "Guards"
	interior.add_child(interior._guards)

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
		# ALONG THE BEAT, NEVER ACROSS IT — see `_plan_guard_post`. The chassis is
		# longer than a plan cell, so this is what keeps a fresh body out of the
		# corridor wall it would otherwise be standing broadside to.
		guard.rotation.y = float(authored["yaw"])
		# THE CALL-ORDER CONTRACT (`setup_as_boss` / the hunter spawner / the
		# platform spawner, all the same shape): `species` goes in BEFORE
		# `add_child`, because `_ready()` is where it is resolved into `spec` and
		# where the size/speed rolls that READ that spec happen. Assigned after, a
		# guard would roll a crocodile's numbers onto its body and every per-frame
		# path would read the wrong row.
		guard.set("species", GUARD_SPECIES)
		interior._guards.add_child(guard)
		# ...and the leash AFTER, exactly as `spawn_platform_crocodiles` does:
		# `set_confinement` is a plain setter no per-frame path reads until the
		# body's first physics tick, and it wants WORLD coordinates, which only
		# exist once the node is in the tree.
		if guard.has_method("set_confinement"):
			var centre: Vector3 = authored["patrol_center"]
			guard.call("set_confinement", interior.global_position + centre,
					authored["patrol_half"])


static func posts(interior) -> Array:
	"""
	Every live guard's authored post name and current global position.

	@return: a fresh Array of { "name": String, "position": Vector3 }.

	The seam the self-check measures the population through, so it counts BODIES
	IN THE TREE rather than rows in `guard_posts_table()` — a spawner that silently
	stopped instancing would otherwise be reported by the table it was meant to be
	standing up.

	`interior` IS DELIBERATELY UNTYPED, and it is the one concession this extraction
	makes. `TowerInterior` const-aliases four of the names above, which is a
	PARSE-TIME reference from there to here; annotating this parameter would make one
	from here to there and the pair becomes a cycle the parser refuses outright
	(measured — "Could not resolve class TowerInterior, because of a parser error",
	and every script that named the class went down with it). `TowerDressing` and
	`TowerDossiers` can type theirs because nothing on the interior points back at
	them with a `const`. So: this is a `TowerInterior`, it is only ever called with
	one, and the type is left off so the const direction can stay one-way.
	"""
	var out: Array = []
	if not is_instance_valid(interior._guards):
		return out
	for child in interior._guards.get_children():
		if child is Node3D:
			out.append({
				"name": String(child.name),
				"position": (child as Node3D).global_position,
			})
	return out
