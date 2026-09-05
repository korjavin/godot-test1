extends RefCounted
class_name BossProbe
## ============================================================================
## THE BOSS HARNESS — shared by every `scripts/boss_*_selfcheck.gd`
## ============================================================================
##
## This is not a check and is deliberately not named like one: CI globs
## `scripts/*_selfcheck.gd`, so a harness with that suffix would be RUN as a
## check and would print nothing. It is the static library the five boss checks
## share, in `landmark_builders.gd`'s idiom — the split of the 1,529-line
## `boss_selfcheck.gd` by bead `godot-test1-ftn.24`, the same treatment bead
## `godot-test1-ftn.13` gave `enemy_spawn_selfcheck`.
##
## WHY THE FILE WAS SPLIT AT ALL. `boss_selfcheck` was 181 s of a 505 s suite and
## CI shards BY FILE (`scripts/selfcheck_shards.sh`), so the gate could never be
## shorter than this one file however many shards ran. The measurement decided the
## cut: every phase here is WALL CLOCK, not CPU — `await physics_frame` is paced at
## the real 60 Hz, so a check's cost is exactly its physics-frame count over 60 —
## and the four 240-frame walking phases were 4.0 s each on every one of the seven
## boss kinds. See each check file's header for what it holds and what it measured.
##
## WHAT LIVES HERE is what every one of them needs and none of them owns: the
## constants that are read from the files that OWN them, the quarry stand-in, the
## subject table, and the driver — instantiate a kind, honour the three-deep
## call-order contract, settle it on a real floor, hand it to the check, free it.
##
## WHAT DOES NOT LIVE HERE: `_failures` / `_fail` / `_report`, which stay on each
## check with its own `Sentinel.finish(self)` — the sentinel reads the expected
## stamp set out of the CALLING script's own source, so a shared report site would
## audit the wrong file. `subject` is the exception and it is here because the
## DRIVER is: the loop is what knows which kind is under test, and every check's
## `_fail` reads it back for the message prefix.

const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const CROC_SCRIPT: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")
## The boss dispatch map, so EVERY boss kind the world can spawn is driven
## through the checks instead of the crocodile standing in for all of them.
## Read from the file that owns it for the same reason SIM_RADIUS is: a boss is a
## MODIFIER on a species, so "the leash and the crush immunity are inherited" is a
## claim about kinds nobody has written yet, and the only way to keep it true is
## to iterate the table rather than a list in here. A new row is covered the day
## it lands (see `subjects()`).
const TERRAIN_SCRIPT: GDScript = preload("res://scripts/endless_terrain.gd")
## Read from the file that OWNS it — the whole point of the constants check is
## that the crocodile's territory and the LOD manager's sleep radius must stay in
## step, and re-typing 45.0 here would make the check pass through a copy of the
## bug.
const LOD_SCRIPT: GDScript = preload("res://scripts/crocodile_lod_manager.gd")

const TERRITORY_RADIUS: float = CROC_SCRIPT.BOSS_TERRITORY_RADIUS
const DETECTION_RADIUS: float = CROC_SCRIPT.BOSS_DETECTION_RADIUS
const SIM_RADIUS: float = LOD_SCRIPT.SIM_RADIUS

## Body scale for the test boss. The terrain's schedule hands out 3.75x–9x; a
## middling one keeps the capsule from dominating the distances measured here.
## Deliberately NOT the cap: the footprint check already measures the footprint
## promise against BOSS_MAX_SCALE arithmetically, and a 9x capsule here would
## swamp the 25/32/45 m radii the territory checks are actually about.
const BOSS_SCALE: float = 3.0

## Any fixed seed: it makes the WANDER stream deterministic (a boss takes no
## size/speed roll, so that is all it does here), which is what keeps the fence
## walk in `boss_wander_selfcheck` from being a coin flip on rng.randomize().
const BOSS_ROLL_SEED: int = 20260828

## Frames to let a freshly added body fall onto the slab and run its deferred
## _ready()/_find_player(). Same number, same reason, as wade_selfcheck.
const SETTLE_FRAMES: int = 30

## Frames per simulated phase. 240 @ 60 Hz = 4 s — long enough for a boss at
## BOSS_CHASE_SPEED (7 m/s) to cross its whole territory twice over, which is
## what makes "it never got out" mean something.
const PHASE_FRAMES: int = 240

## Containment tolerance (metres). The clamp pulls the body back onto the circle
## with no epsilon at all, so this is pure float slop; anything the leash misses
## is metres out, not centimetres.
const CONTAIN_EPS: float = 0.05

## Which boss kind the current phase is measuring, for the failure messages. A
## suite that runs every check over N species has to say WHICH one broke, and
## prefixing in each check's `_fail()` is cheaper than threading a label through
## twenty calls. It lives here because `drive()` is what advances it; static
## because a self-check is one process running one file, the same reasoning
## `selfcheck_sentinel.gd`'s `_reached` is written on.
static var subject: String = ""


## The player stand-in. Deliberately a plain Node3D and NOT a CharacterBody3D:
## `_update_chase_state` asks the quarry `is_on_floor()` and a CharacterBody3D
## that never ran move_and_slide answers false, i.e. "jumped", i.e. unsmellable —
## every chase check would then pass vacuously. This answers the one question the
## AI asks, and carries the two methods `_on_player_collision` dispatches on so
## the crush ordering can be driven directly.
class StubPlayer:
	extends Node3D
	## Flipped by the crush checks only; the chase checks want an ordinary player.
	var giant: bool = false
	var bitten: int = 0

	func is_on_floor() -> bool:
		return true

	func crushes_crocodiles() -> bool:
		return giant

	func hit_by_crocodile(_attacker: Node = null) -> void:
		bitten += 1

	func is_giant() -> bool:
		return giant


static func frames(tree: SceneTree, n: int) -> void:
	for _i in n:
		await tree.physics_frame


static func flat_distance(a: Vector3, b: Vector3) -> float:
	"""XZ distance — the axes the territory is measured on (the world is flat)."""
	return Vector2(a.x - b.x, a.z - b.z).length()


static func assert_contained(fail: Callable, boss: CharacterBody3D, home: Vector3,
		phase: String) -> void:
	"""Containment is asserted in EVERY phase, not just the leash one — a boss
	that slips out while hunting a quarry inside its area is the same bug.

	@param fail: the calling check's own `_fail`, which prefixes with `subject`."""
	var out := flat_distance(boss.global_position, home)
	if out > TERRITORY_RADIUS + CONTAIN_EPS:
		fail.call("%s: boss is %.2f m from home, territory is %.1f m"
				% [phase, out, TERRITORY_RADIUS])


static func subjects() -> Array[Dictionary]:
	"""
	Every boss kind the world can spawn: the crocodile (the fallback every
	entry-less biome and every river station takes) plus one entry per BIOME_BOSS
	row, deduplicated by species.

	@return [{ "species": String, "scene": String }], crocodile first

	NOTHING HERE NAMES THE TITAN, and that is the point — the same rule
	enemy_spawn_selfcheck follows. The boss rules these files pin (the leash, the
	crush ordering) are properties of BOSS-NESS and are inherited by every kind,
	so a check that only ever drove the crocodile would keep passing while a new
	kind quietly broke them. A row added to BIOME_BOSS is measured on the commit
	that adds it, with no edit here and none in any of the five check files.
	"""
	var out: Array[Dictionary] = [{ "species": "crocodile", "scene": CROC_SCENE }]
	var seen: Dictionary = { "crocodile": true }
	for biome_v: Variant in TERRAIN_SCRIPT.BIOME_BOSS:
		var row: Dictionary = TERRAIN_SCRIPT.BIOME_BOSS[biome_v]
		var species_name: String = String(row.get("species", ""))
		if species_name.is_empty() or seen.has(species_name):
			continue
		seen[species_name] = true
		out.append({ "species": species_name, "scene": String(row.get("scene", "")) })
	return out


static func build_floor(root: Node) -> void:
	"""Something to stand on. The world is flat at y = 0 by invariant, so this is a
	slab whose TOP is the ground plane — wide enough that a boss roaming its whole
	territory never runs out of floor and starts falling."""
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)


static func build_player(root: Node) -> StubPlayer:
	"""The quarry goes in FIRST: a boss's `_find_player()` is call_deferred from
	`_ready()`, so a player added afterwards is simply never found and every chase
	assertion would pass for the wrong reason."""
	var player := StubPlayer.new()
	# `position`, not `global_position`: a node added from _initialize() is not yet
	# is_inside_tree() at this point and global_position errors out — the same trap
	# wade_selfcheck documents. Every later move happens after a frame, so those
	# use global_position normally.
	player.position = Vector3.ZERO
	root.add_child(player)
	player.add_to_group("player")
	return player


static func spawn_boss(tree: SceneTree, packed: PackedScene,
		species_name: String) -> CharacterBody3D:
	"""One boss kind, in the tree and settled on the floor.

	CALL-ORDER CONTRACT, and it is three deep: `species` BEFORE setup_as_boss
	BEFORE add_child. _ready() resolves `spec` from `species` exactly once and
	branches on is_boss in the same pass, so an assignment after add_child leaves a
	body with a crocodile's spec, or one that took the random speed and size rolls
	a boss must not have — with no error anywhere. This is the same order
	endless_terrain.spawn_bosses_in_chunk uses, on purpose."""
	var boss: CharacterBody3D = packed.instantiate()
	boss.species = species_name
	boss.setup_as_boss(BOSS_SCALE)
	# Same call-order contract. A boss takes no size/speed roll, so the seed goes
	# unused there (setup_roll_seed says so explicitly) — what it buys is a
	# deterministic wander stream, which is what stops the fence walk from being a
	# coin flip. Without it a boss falls back to rng.randomize().
	boss.setup_roll_seed(BOSS_ROLL_SEED)
	boss.position = Vector3(0.0, 1.0, 0.0)
	tree.root.add_child(boss)
	await frames(tree, SETTLE_FRAMES)
	return boss


static func ready_failure(boss: CharacterBody3D, species_name: String) -> String:
	"""Why this body cannot be measured, or "" if it can. Asked once per subject by
	`drive()`: all three are the harness failing rather than the game, and all three
	would make every assertion after them meaningless rather than false."""
	if not boss.has_method("in_territory"):
		return ("boss: no in_territory() on this scene — did the script fail to "
				+ "attach? (a fresh clone needs `godot --headless --path . --import` first)")
	if not boss.is_boss:
		return "boss: setup_as_boss() left is_boss false"
	if String(boss.species) != species_name:
		return ("boss: species is '%s' after _ready(), expected '%s' — an unknown "
				% [boss.species, species_name] + "name falls back to the crocodile, "
				+ "so this kind would be measured as one")
	return ""


static func drive(tree: SceneTree, fail: Callable, on_boss: Callable) -> void:
	"""
	THE DRIVER. A floor, a shared quarry, and every kind `subjects()` yields
	instantiated, settled, handed to the caller and freed.

	@param tree: the check itself (each is a `SceneTree`)
	@param fail: its `_fail` — the harness's own failures are reported through the
	             caller so they carry its subject prefix and land in its verdict
	@param on_boss: `func(boss: CharacterBody3D, player: StubPlayer,
	                home: Vector3) -> void`, awaited; may be a coroutine

	The player stub is SHARED across the kinds (it is already in the tree, which is
	what the deferred `_find_player()` needs); each subject gets its own body at its
	own spawn spot.
	"""
	build_floor(tree.root)
	var player: StubPlayer = build_player(tree.root)
	for entry: Dictionary in subjects():
		subject = String(entry["species"])
		var packed: PackedScene = load(String(entry["scene"]))
		if packed == null:
			fail.call("could not load %s" % entry["scene"])
			continue
		var boss: CharacterBody3D = await spawn_boss(tree, packed, subject)
		var bad: String = ready_failure(boss, subject)
		if not bad.is_empty():
			fail.call(bad)
			boss.queue_free()
			await frames(tree, 2)
			continue
		await on_boss.call(boss, player, boss.home_position)
		boss.queue_free()
		await frames(tree, 2)
	subject = ""
	player.queue_free()
	await frames(tree, 2)
