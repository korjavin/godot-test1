extends SceneTree
## Headless self-check: NO CROCODILE MAY SPAWN INSIDE SOLID STONE — and, since
## the biome-predator epic, EVERY PREDATOR IS THE SPECIES ITS BIOME ASKED FOR.
##
## The second subject lives here rather than in a file of its own because it is
## the same measurement on the same sweep: the spawner that must not put a body
## in stone is the spawner that decides what that body IS, and the failure has
## the same shape — nothing errors, nothing logs, you just get the wrong animal.
##
##   godot --headless --path . --script res://scripts/croc_spawn_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as prop_selfcheck.gd / landmark_selfcheck.gd, and it exists for the
## same reason those do: every way of breaking this looks like ordinary scenery
## from the outside. A crocodile wedged in a block is not an error anywhere — it
## is a body the physics server shoves out sideways, or one that stands in a wall
## biting a player who cannot reach it, in a world where nothing logs anything.
##
## THE THREE SPAWNERS AND WHAT EACH RELIES ON, because they are not alike:
##
##   * spawn_crocodiles_in_chunk (ground) rejects candidates within
##     `ob.radius + min_object_clearance` of every footprint in `obstacles`.
##   * spawn_bosses_in_chunk walks BOSS_PLACE_TRIES candidates against the same
##     list with a per-scale clearance, because a 6x boss needs ~4.2 m.
##   * spawn_platform_crocodiles gets NO obstacles at all. It is handed walkable
##     tops and trusts their declared geometry — which is exactly where this
##     check earns its keep, and where the bug it was written for lived: a wall
##     ridge declared its surface at the SINGLE-block height while 30% of its
##     sections are DOUBLED, so a guard dropped in at surface + spawn height
##     landed inside a hump whenever the random angle picked one.
##
## HOUSE RULE, followed throughout: every check is an EFFECT measurement against
## the chunk's REAL collision shapes — the CollisionShape3D children of its
## BlockCollision body — never a read-back of the declared footprints, because
## the declared footprints are precisely what a bug here gets wrong. Every check
## has a negative control beside it, since "no crocodile was in stone" is also
## true of a sweep that generated no crocodiles, no stone, or no doubled wall.
##
## Cost: the whole file is ~1.3 s for 2 seeds x 289 chunks. Don't grow it into a
## suite; if a fourth spawner appears, it belongs in check 1's sweep, not in a
## new file.
##
## THE ONE THING IT PRINTS THAT IS NOT ITS OWN: a handful of "RID allocations …
## were leaked at exit" / "resources still in use at exit" lines AFTER the
## verdict. Those are the engine reporting the STATIC shared caches this project
## deliberately keeps — endless_terrain's shared unit box and ground meshes, the
## artifact glow and camp ember materials, ToonShading's styled-material cache,
## and the two PackedScenes loaded below — none of which is owned by, or
## releasable from, a check. They are the same lines any harness that loads the
## crocodile scene prints, they appear after the exit code is decided, and they
## are NOT a failure. Everything else must stay silent: a run that prints a
## SCRIPT ERROR beside SELFCHECK OK is measuring a world it did not build (see
## _make_chunk_parent and _boot for the two traps that caused exactly that).

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const CROC_AI_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

## Field side in chunks. 17 x 17 = 289, the size every measurement in CLAUDE.md's
## terrain sections is quoted at, so a number printed here is comparable to them.
const FIELD: int = 17

## Two run seeds, not one. The biome offset is derived from run_seed, so a single
## seed can land most of a field in desert (few structures) and miss the walls
## entirely — check 3 is the control that says so out loud if it happens.
const RUN_SEEDS: Array[int] = [12345, 20260826]

## Angles walked around each platform's spawn ellipse in check 2. The spawner
## draws ONE angle per platform, so the live sweep in check 1 samples a single
## point per structure; 16 covers the arc a different run_seed would have picked.
const PLATFORM_ANGLE_SAMPLES: int = 16

## Float slack. A body resting exactly on a face is correct, not a failure.
const EPSILON: float = 0.001

var _failures: Array[String] = []

## piglet_crocodile_ai.gd's SPECIES table and endless_terrain.gd's BIOME_SPECIES
## map, read once in _run() through get_script_constant_map() — see the note there
## on why a `const` cannot be read as a property.
var _species_table: Dictionary = {}
var _biome_species: Dictionary = {}

## The two ends of the speed lattice, read off player_controller.gd and
## piglet_crocodile_ai.gd rather than restated — see the note in _run().
var _walk_speed: float = 0.0
var _max_chase_speed: float = 0.0


func _initialize() -> void:
	_boot()


func _boot() -> void:
	"""
	Wait ONE frame before generating anything.

	A node added to `root` from inside _initialize() is not `is_inside_tree()`
	until the first frame — the same trap best_run_e2e.gd is written around (there
	it makes HTTPRequest.request() answer ERR_UNCONFIGURED). Here it would make
	every chunk parent _make_chunk_parent() creates a detached node in disguise,
	so `treasure_chest.setup()` would still get a null tree and a zero global
	transform, and the check would go on printing engine errors beside its own OK.
	"""
	await process_frame
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	# get_script_constant_map() is how a `const` is read from outside: constants
	# are not properties, so terrain.get("PLATFORM_SPAWN_HEIGHT") answers null and
	# a check written that way would measure against 0.0 and pass vacuously.
	var consts: Dictionary = terrain_script.get_script_constant_map()
	if not consts.has("PLATFORM_SPAWN_HEIGHT") or not consts.has("PLATFORM_SPAWN_EDGE_INSET"):
		_fail("endless_terrain.gd has no PLATFORM_SPAWN_HEIGHT / PLATFORM_SPAWN_EDGE_INSET —"
				+ " the patrol drop-in constants this check measures against are gone")
		_report()
		return

	var spawn_height: float = float(consts["PLATFORM_SPAWN_HEIGHT"])
	var edge_inset: float = float(consts["PLATFORM_SPAWN_EDGE_INSET"])

	# The lattice's two ends are READ, never restated here: WALK_SPEED off the
	# player and MAX_CHASE_SPEED off the AI, so retuning either moves this check
	# with it instead of leaving it asserting a number nothing uses any more.
	var croc_consts: Dictionary = load(CROC_AI_SCRIPT).get_script_constant_map()
	_species_table = croc_consts.get("SPECIES", {})
	_max_chase_speed = float(croc_consts.get("MAX_CHASE_SPEED", 0.0))
	_walk_speed = float(load(PLAYER_SCRIPT).get_script_constant_map().get("WALK_SPEED", 0.0))
	_biome_species = consts.get("BIOME_SPECIES", {})
	_check_species_table()

	for run_seed: int in RUN_SEEDS:
		_sweep(terrain_script, run_seed, spawn_height, edge_inset)

	_report()


# ============================================================================
# CHECK 4 (table half) — every SPECIES row is complete, legal and reachable
# ============================================================================

func _check_species_table() -> void:
	"""
	Read the two tables and prove a NEW ROW cannot ship broken.

	This is the cheap half of check 4 — no world, no chunks, pure data — and it
	exists because the biome-predator epic adds one species per bead, each of
	them a hand-copied dictionary of ~30 keys. The three ways that goes wrong are
	all silent from the outside, which is this file's whole subject:

	  * A MISSING KEY is a crash in a per-frame path (`spec["sway_yaw"]` in
	    _animate_body), on the first frame the first one of them is visible, and
	    only in the biome that species lives in.
	  * A chase_speed OVER the lattice quietly breaks the promise the whole game
	    is balanced on — walking is caught, RUNNING ESCAPES. MAX_CHASE_SPEED
	    clamps it at runtime so nothing ever looks wrong; the row is just a lie.
	  * A dispatch entry naming a species that isn't in the table, or pointing at
	    a scene that doesn't load, degrades to a crocodile — which reads as "the
	    new predator isn't finished yet" rather than as a bug.

	The key set is taken from the crocodile row rather than hardcoded here, so it
	tracks the AI: add a key to the table and every row must grow it, delete one
	and this stops demanding it. That is deliberately stricter than the engine —
	an unused key on one row is not a crash — and it is the point: 'the crocodile
	has it and you don't' is exactly the state that crashes later.
	"""
	if _species_table.is_empty():
		_fail("piglet_crocodile_ai.gd exposes no SPECIES table — the species dispatch"
				+ " this check measures has nothing to dispatch over")
		return
	if not _species_table.has("crocodile"):
		_fail("SPECIES has no 'crocodile' row — it is the fallback every unknown"
				+ " species name and every scene-less biome resolves to")
		return

	var required: Array = _species_table["crocodile"].keys()
	for name_v: Variant in _species_table:
		var species_name: String = String(name_v)
		var row: Dictionary = _species_table[species_name]
		for key_v: Variant in required:
			if not row.has(key_v):
				_fail("SPECIES['%s'] is missing '%s', which the crocodile row has —"
						% [species_name, key_v]
						+ " a per-frame path reads it and will crash on the first"
						+ " frame one of these is on screen")
		# The lattice, stated in CLAUDE.md and in the SPECIES doc block: walking
		# (5.0) must be caught, and the slowest run (9.0) must escape. Every row
		# owes both ends; MAX_CHASE_SPEED is the ceiling and no row may raise it.
		if row.has("chase_speed"):
			var chase: float = float(row["chase_speed"])
			if chase <= _walk_speed:
				_fail("SPECIES['%s'].chase_speed %.2f is at or below %.2f —"
						% [species_name, chase, _walk_speed]
						+ " a player could stroll away from it")
			if chase > _max_chase_speed:
				_fail("SPECIES['%s'].chase_speed %.2f exceeds %.2f —"
						% [species_name, chase, _max_chase_speed]
						+ " the clamp hides it at runtime, so the row is simply wrong")

	# The dispatch map: names must resolve, scenes must load.
	for biome_v: Variant in _biome_species:
		var entry: Dictionary = _biome_species[biome_v]
		var species_name: String = String(entry.get("species", ""))
		if not _species_table.has(species_name):
			_fail("BIOME_SPECIES[%s] dispatches to '%s', which is not a SPECIES row —"
					% [biome_v, species_name]
					+ " every crocodile in that biome would silently fall back")
		var scene_path: String = String(entry.get("scene", ""))
		if not ResourceLoader.exists(scene_path) or load(scene_path) == null:
			_fail("BIOME_SPECIES[%s] points at '%s', which does not load"
					% [biome_v, scene_path])

	# The negative control for this half: a table with one row and an empty
	# dispatch map passes every loop above without measuring anything.
	if _species_table.size() < 2 or _biome_species.is_empty():
		_fail("only %d SPECIES row(s) and %d dispatch entries — checks over the"
				% [_species_table.size(), _biome_species.size()]
				+ " species table ran against a world with one predator in it")


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


# ============================================================================
# THE SWEEP — one whole field, generated exactly the way create_chunk does
# ============================================================================

func _sweep(terrain_script: GDScript, run_seed: int, spawn_height: float, edge_inset: float) -> void:
	"""
	Generate a FIELD x FIELD chunk field and measure every crocodile against the
	solid geometry around it.

	The terrain node is DETACHED (never added to the tree), the same way
	prop_selfcheck.gd and landmark_selfcheck.gd drive it: _ready() rolls a random
	run seed, awaits a frame and starts streaming chunks around the player, none
	of which this check wants. set_run_seed() is the public seam that makes the
	field reproducible (it is also what new_run() and the multiplayer forced seed
	go through, so it cannot rot), and the two scenes are assigned by hand because
	_ready() is what normally loads them.

	TWO PASSES, and the split is load-bearing: a block near a chunk edge reaches
	into the NEIGHBOURING chunk, while `obstacles` only ever describes the chunk
	being generated. So every chunk's geometry is built first and each crocodile
	is then measured against its own chunk AND its eight neighbours, in world
	space. A single-pass version passes while a crocodile stands in the corner of
	the wall next door.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)

	var chunk_solids := {}      # Vector2i -> Array of { inv, half } in WORLD space
	var chunk_obstacles := {}   # Vector2i -> the chunk's footprint list
	var chunk_platforms := {}   # Vector2i -> the chunk's walkable tops
	var solid_count := 0
	var half_field := FIELD / 2

	# ---- pass 1: build the geometry -----------------------------------------
	for cx in range(-half_field, half_field + 1):
		for cz in range(-half_field, half_field + 1):
			var chunk_pos := Vector2i(cx, cz)
			var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
			var parent := _make_chunk_parent(origin)
			var obstacles: Array = []
			var platforms: Array = []
			var batch: Array = []
			var body := StaticBody3D.new()

			# Same call ORDER as create_chunk, because the later spawners judge
			# their candidates against the footprints the earlier ones appended.
			obstacles = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
			terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
			terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)

			var solids: Array = []
			for child in body.get_children():
				var shape_node := child as CollisionShape3D
				var box := shape_node.shape as BoxShape3D
				# The shape carries the block's chunk-local transform (create_box
				# assigns it whole); lift it to world so neighbours are comparable.
				var world := Transform3D(shape_node.transform.basis,
						shape_node.transform.origin + origin)
				solids.append({ "inv": world.affine_inverse(), "half": box.size * 0.5 })
			solid_count += solids.size()

			chunk_solids[chunk_pos] = solids
			chunk_obstacles[chunk_pos] = obstacles
			chunk_platforms[chunk_pos] = platforms
			parent.free()
			body.free()

	# ---- pass 2: spawn the crocodiles and measure ---------------------------
	var counts := { "ground": 0, "platform": 0, "boss": 0 }
	var worst_depth := 0.0
	var worst_desc := ""
	var in_stone := 0
	# Check 4's live half — see the block inside the loop below.
	var species_mismatches := 0
	var species_worst := ""
	var species_seen := {}

	for cx in range(-half_field, half_field + 1):
		for cz in range(-half_field, half_field + 1):
			var chunk_pos := Vector2i(cx, cz)
			var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
			var parent := _make_chunk_parent(origin)
			var obstacles: Array = chunk_obstacles[chunk_pos]

			terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
			terrain.spawn_platform_crocodiles(chunk_pos, parent, chunk_platforms[chunk_pos])
			terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)

			for child in parent.get_children():
				var node_name := String(child.name)
				var kind := ""
				if node_name.begins_with("Crocodile_"):
					kind = "ground"
				elif node_name.begins_with("PatrolCrocodile_"):
					kind = "platform"
				elif node_name.begins_with("BossCrocodile_"):
					kind = "boss"
				else:
					continue
				counts[kind] = int(counts[kind]) + 1

				# CHECK 4 (live half): the biome dispatch actually reached the
				# body. The table itself is checked once, off-world, in
				# _check_species_table; what can only be seen HERE is whether
				# spawn_crocodiles_in_chunk assigned `species` at all, whether it
				# assigned it BEFORE add_child (an assignment after it leaves
				# `spec` resolved to the crocodile row, so the field and the row
				# disagree), and whether it picked the entry the chunk's biome
				# calls for. A boss or a platform guard is deliberately exempt —
				# neither is dispatched on a chunk centre.
				if kind == "ground":
					var want: String = _expected_species(terrain, origin)
					var got: String = String(child.get("species"))
					# `spec` is what the per-frame paths actually read, and it is
					# resolved in _ready(). Comparing ONE number off it against
					# the table is what catches the call-order break: assign
					# `species` after add_child() and the field says "sand_viper"
					# while every speed, feeler and animation stays a crocodile's.
					var spec: Variant = child.get("spec")
					var want_speed: float = float(_species_table[want]["chase_speed"])
					var got_speed: float = (float(spec["chase_speed"])
							if spec is Dictionary and spec.has("chase_speed") else NAN)
					if got != want:
						species_mismatches += 1
						if species_worst == "":
							species_worst = "%s (%s biome) is species '%s', expected '%s'" % [
									node_name, _biome_name(origin, terrain), got, want]
					elif not is_equal_approx(got_speed, want_speed):
						species_mismatches += 1
						if species_worst == "":
							species_worst = ("%s says species '%s' but resolved a spec with"
									+ " chase_speed %s, not the table's %s — `species` was"
									+ " assigned AFTER add_child()") % [
									node_name, got, got_speed, want_speed]
					species_seen[want] = int(species_seen.get(want, 0)) + 1

				var world_pos: Vector3 = (child as Node3D).global_position
				var depth := _depth_in_stone(chunk_solids, chunk_pos, world_pos)
				if depth > EPSILON:
					in_stone += 1
					if depth > worst_depth:
						worst_depth = depth
						worst_desc = "%s crocodile %s at %v" % [kind, node_name, world_pos]

			parent.free()

	if in_stone > 0:
		_fail("seed %d: %d of %d crocodiles spawned INSIDE solid stone (worst %.2f m deep: %s)"
				% [run_seed, in_stone, counts["ground"] + counts["platform"] + counts["boss"],
				   worst_depth, worst_desc])

	if species_mismatches > 0:
		_fail("seed %d: %d of %d ground predators are not the species their chunk's biome"
				% [run_seed, species_mismatches, counts["ground"]]
				+ " dispatches to (first: %s)" % species_worst)
	# The negative control for the live half: a field that is all one biome, or a
	# dispatch that never fired, agrees with itself perfectly and proves nothing.
	if species_seen.size() < 2:
		_fail("seed %d: every ground predator in the field was the same species (%s) —"
				% [run_seed, species_seen.keys()]
				+ " the biome dispatch was never actually exercised")

	# ---- CHECK 2: every angle of every platform, not just the drawn one ------
	# A guard's angle is one RNG draw, so check 1 samples ONE point per structure
	# and a producer that under-declares its `top` over half its length passes on
	# most seeds by luck. This walks the whole spawn ellipse.
	var platforms_seen := 0
	var humped_platforms := 0
	var bad_angles := 0
	var worst_angle_depth := 0.0
	var worst_angle_desc := ""

	for chunk_pos_v: Variant in chunk_platforms:
		var chunk_pos: Vector2i = chunk_pos_v
		var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
		for platform_v: Variant in chunk_platforms[chunk_pos]:
			var platform: Dictionary = platform_v
			if not platform.has("top"):
				_fail("seed %d: a platform in chunk %s declares no `top` — spawn_platform_crocodiles"
						% [run_seed, chunk_pos]
						+ " drops its guard in from that field, so a producer without one"
						+ " cannot say where its tallest stone is")
				continue
			platforms_seen += 1
			var center: Vector3 = platform.center
			var half: Vector2 = platform.half
			var top: float = float(platform.top)
			# The control for the bug this file was written for: a wall whose
			# ridge carries a doubled hump declares a `top` ABOVE the surface it
			# paces. If no platform in the whole field does, checks 1 and 2 never
			# exercised the case at all (see check 3).
			if top > center.y + EPSILON:
				humped_platforms += 1

			for i in PLATFORM_ANGLE_SAMPLES:
				var ang := TAU * float(i) / float(PLATFORM_ANGLE_SAMPLES)
				var probe := origin + Vector3(
						center.x + maxf(0.0, half.x - edge_inset) * cos(ang),
						top + spawn_height,
						center.z + maxf(0.0, half.y - edge_inset) * sin(ang))
				var depth := _depth_in_stone(chunk_solids, chunk_pos, probe)
				if depth > EPSILON:
					bad_angles += 1
					if depth > worst_angle_depth:
						worst_angle_depth = depth
						worst_angle_desc = "chunk %s, angle %.2f rad, probe %v" % [chunk_pos, ang, probe]

	if bad_angles > 0:
		_fail("seed %d: %d platform spawn points (over %d platforms) fall inside solid stone"
				% [run_seed, bad_angles, platforms_seen]
				+ " (worst %.2f m deep: %s) — a platform's `top` is not a true bound"
				% [worst_angle_depth, worst_angle_desc]
				+ " on the stone standing in its own footprint")

	# ---- CHECK 3: the negative controls -------------------------------------
	# Everything above is trivially true of a sweep that produced nothing. Each of
	# these is a thing that must have EXISTED for the measurements to mean anything.
	if counts["ground"] < 1:
		_fail("seed %d: the sweep spawned no ground crocodiles at all — checks 1-2 measured nothing" % run_seed)
	if counts["platform"] < 1:
		_fail("seed %d: the sweep spawned no platform guards — the one spawner with no obstacle"
				% run_seed + " test is exactly what this file exists to measure")
	if solid_count < 1:
		_fail("seed %d: the sweep built no collision shapes — there was no stone to be inside of" % run_seed)
	if humped_platforms < 1:
		_fail("seed %d: no platform in the field declared a `top` above its paced surface, so the"
				% run_seed + " doubled-wall-hump case this check was written for was never exercised")

	# Counts only — the verdict is SELFCHECK OK / the FAIL lines, and a summary
	# that asserted "all clear" here would print it beside its own failures.
	print("seed %d: measured %d ground / %d platform / %d boss crocodiles against %d collision shapes, plus %d angle probes over %d platforms (%d humped)"
			% [run_seed, counts["ground"], counts["platform"], counts["boss"], solid_count,
			   platforms_seen * PLATFORM_ANGLE_SAMPLES, platforms_seen, humped_platforms])
	print("seed %d: ground predators by species %s" % [run_seed, species_seen])


func _expected_species(terrain: Node, chunk_centre: Vector3) -> String:
	"""
	What BIOME_SPECIES says a chunk should spawn — recomputed from the PUBLIC
	biome API, not read back off the spawner.

	@param terrain: The detached terrain node driving this sweep.
	@param chunk_centre: chunk_to_world(chunk_pos) — the exact point the spawner
	                     dispatches on, which is the whole reason this is a
	                     one-liner and not a reimplementation.
	@return: A key of SPECIES; "crocodile" for any biome with no entry.
	"""
	var biome: int = terrain.biome_at(chunk_centre.x, chunk_centre.z)
	if _biome_species.has(biome):
		return String(_biome_species[biome]["species"])
	return "crocodile"


func _biome_name(chunk_centre: Vector3, terrain: Node) -> String:
	"""The chunk's biome as a readable name, for failure messages only."""
	var names: Array = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN", "CITY", "SNOW"]
	var biome: int = terrain.biome_at(chunk_centre.x, chunk_centre.z)
	return names[biome] if biome >= 0 and biome < names.size() else str(biome)


func _make_chunk_parent(origin: Vector3) -> MeshInstance3D:
	"""
	A stand-in for the chunk MeshInstance3D, IN THE TREE at its world origin.

	@param origin: The chunk's world position (chunk_to_world).
	@return The parent node the spawners are handed. Freed with queue_free().

	IT HAS TO BE IN THE TREE, unlike prop_selfcheck.gd's terrain node, and the
	difference is which functions are being driven. A prop builder reaches only
	create_box; the chunk spawners reach node code that asks the tree about
	itself — `treasure_chest.setup()` calls `get_global_transform()` and
	`get_tree().get_first_node_in_group(...)`, and `spawn_platform_crocodiles`
	hands `set_confinement` a `parent_chunk.global_position`. Detached, all three
	answer with an engine error and a zero: a run printed 195 error lines and
	still exited 0 with SELFCHECK OK, which is the exact "green lie" this
	project's checks exist to avoid (its two siblings print none). In the tree at
	the real origin they are all simply correct, and `global_position` can then be
	read straight off a crocodile rather than reconstructed.

	The terrain node itself stays DETACHED — its _ready() would roll a random run
	seed over the one this sweep set and start streaming chunks of its own.
	"""
	var parent := MeshInstance3D.new()
	parent.position = origin
	root.add_child(parent)
	return parent


func _depth_in_stone(chunk_solids: Dictionary, chunk_pos: Vector2i, world_pos: Vector3) -> float:
	"""
	How deep `world_pos` sits inside the nearest solid box of the 3x3 chunk block
	around `chunk_pos`. 0.0 when it is outside every one of them.

	@param chunk_solids: Vector2i -> Array of { inv: Transform3D, half: Vector3 }
	@param chunk_pos: The chunk to search around (its 8 neighbours included)
	@param world_pos: The point to test, in world space
	@return Penetration depth in metres; 0.0 means clear.

	The neighbours are what make this honest — see the two-pass note in _sweep.
	The point is transformed into each box's own frame rather than compared
	against an axis-aligned bound, because create_box gives a block a yaw (and an
	artifact stone a tilt as well), so a bounding box would report a corner region
	as solid and fail on crocodiles standing in clear air beside a rotated block.
	"""
	var deepest := 0.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var neighbour := chunk_pos + Vector2i(dx, dz)
			if not chunk_solids.has(neighbour):
				continue
			for solid_v: Variant in chunk_solids[neighbour]:
				var solid: Dictionary = solid_v
				var local: Vector3 = solid.inv * world_pos
				var half: Vector3 = solid.half
				# Distance to the nearest face, from the inside. Any axis already
				# outside the box means the point is outside it entirely.
				var gap := minf(half.x - absf(local.x),
						minf(half.y - absf(local.y), half.z - absf(local.z)))
				if gap > deepest:
					deepest = gap
	return deepest
