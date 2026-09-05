class_name TowerProbe
extends RefCounted
## THE TOWER SELF-CHECKS' SHARED RIG — the scene paths, the shell/interior
## instancing and the two-line teardown that every one of them needs.
##
## Lifted out of `tower_interior_selfcheck.gd` by bead `godot-test1-ftn.25`, which
## split that 5,250-line file into three by check family (the ftn.13 shape: check
## NUMBERS and names unchanged, each file its own Sentinel set read from its own
## source). It is a MECHANICAL extraction — not one assertion moved, and every
## function below is the original body with `root` taken as an argument, because a
## static helper has no `SceneTree` of its own.
##
## THE RULE FOR WHAT LANDS HERE: something MORE THAN ONE of the tower checks needs,
## and that touches no `_failures` array — a helper that fails on its caller's
## behalf belongs beside the assertion it is making, where the message can name the
## check. Everything here builds, frees or measures; nothing here judges.
##
## `ChunkBatch`'s idiom: `class_name`, all `static`, reads no instance state.

const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"

## The AI's SPECIES table, for the "which row did this body actually resolve" test
## in the guard checks. Read rather than restated, so a renamed row fails by name.
const CROC_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"

## Radians of slop allowed on "it is looking at the plate". A whole degree, which
## is far tighter than a 120-degree cone and far looser than float noise. Shared
## because BOTH lure checks — the ground floor's errand and the cell block's — hold
## the hold to the same standard.
const LURE_FACING_EPS: float = 0.02

## How far from the guard's post the probe player has to be parked while the walk
## is being measured: comfortably outside the row's 9 m detection, so the guard is
## not chasing anything the errand could be blamed on.
const LURE_PARK_MIN: float = 15.0

## How fast a guard may still be travelling during its telegraph, or standing on a
## plate, and be called still. Not zero: `move_and_slide` resolves a settling body
## against the slab and the reported velocity carries a little of that. Far under
## the row's 1.4 m/s walk, which is what the assertions are actually about.
const TELEGRAPH_STILL_SPEED: float = 0.05


static func make_interior(tree: SceneTree) -> Node3D:
	## A bare interior in the tree — no shell above it, so `_tower()` finds nothing
	## and every gate reads shut. That is what the node-shape and palette checks
	## want: the geometry, with no state.
	var interior := load(INTERIOR_SCENE).instantiate() as Node3D
	tree.root.add_child(interior)
	await tree.process_frame
	return interior


static func make_tower(tree: SceneTree) -> Node3D:
	## Shell plus interior, assembled the way endless_terrain assembles them — the
	## interior added BEFORE the shell enters the tree, so it can see its parent.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	tree.root.add_child(shell)
	await tree.process_frame
	return shell


static func clear(tree: SceneTree, hero: Node, shell: Node) -> void:
	"""
	Free a check's probe player and tower before bailing out.

	NOT TIDINESS. A check that `return`s on a failure and leaves its probe in the
	tree leaves a second node in group "player", and the next check's
	`get_first_node_in_group("player")` picks one of them at random — so one real
	failure grows a train of invented ones in checks that are fine. (Happened while
	this file was being written: a missing `IdentityTrigger` reported itself as "the
	interior still draws with the player 240 m away".)
	"""
	if hero != null:
		hero.queue_free()
	if shell != null:
		shell.queue_free()
	await tree.process_frame


static func settle_physics(tree: SceneTree) -> void:
	## Four physics frames — the number `tower_shell_selfcheck` MEASURED: a body added
	## and positioned in the same frame is reported by an area on the THIRD frame, so
	## two reads as "nothing fired" and passes every mutant.
	for _i in 4:
		await tree.physics_frame


static func overlaps(a_pos: Vector3, a_size: Vector3, b_pos: Vector3, b_size: Vector3) -> bool:
	## Axis-aligned three-interval overlap, with a tolerance so two boxes that merely
	## share a face do not read as intersecting.
	const TOUCH: float = 0.001
	var a := a_size * 0.5
	var b := b_size * 0.5
	return absf(a_pos.x - b_pos.x) < a.x + b.x - TOUCH \
			and absf(a_pos.y - b_pos.y) < a.y + b.y - TOUCH \
			and absf(a_pos.z - b_pos.z) < a.z + b.z - TOUCH


static func fresh_store() -> void:
	"""
	Delete the throwaway save, so the next assertion starts from a clean profile.

	Never the real one: `Sentinel.isolate_user_state()` pointed
	`BestRunStore.config_path` at this process's own scratch file before any shell
	could exist — and it reads that seam rather than naming a path, which is what
	makes the sentence true rather than hopeful.

	`ponytail:` THE CEILING IS THAT THIS `remove_absolute` NOW SITS OUTSIDE THE
	AUDIT. `progression_selfcheck`'s `hermetic_stores` globs `*_selfcheck.gd`, and
	this file is not one — so the one line in the tower checks that DELETES a store
	is the one line that audit no longer reads. It is safe today for the reason
	above (a seam, not a literal); it stops being safe the day somebody types
	`user://best_run.cfg` here, which is precisely the mistake the audit exists to
	catch. If a second non-check file ever needs a store verb, widen that glob to
	the whole of `scripts/` rather than trusting this comment.
	"""
	DirAccess.remove_absolute(BestRunStore.config_path)
