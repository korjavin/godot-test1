extends Node3D
## Endless Terrain Generator
##
## This script creates an "endless" field by generating terrain chunks
## around the player and removing chunks that are far away.
##
## EDUCATIONAL NOTES:
## - This uses a technique called "chunk-based terrain generation"
## - Chunks are created/destroyed dynamically based on player position
## - This is how games like Minecraft create infinite worlds!

# ============================================================================
# SECTION 1: TERRAIN CONFIGURATION
# ============================================================================

## Size of each terrain chunk (in meters)
## Larger chunks = fewer chunks needed, but more memory per chunk
@export var chunk_size: float = 50.0

## How many chunks to render around the player in each direction
## Higher values = you can see further, but more GPU/CPU usage
@export var render_distance: int = 5

## Terrain height variation (for future procedural generation)
## Currently we use a flat plane, but this allows for hills/valleys
@export var terrain_height: float = 0.0

## The material to apply to terrain chunks
## You can customize this in the Godot editor!
@export var terrain_material: StandardMaterial3D

## Enable/disable object spawning on terrain
@export var spawn_objects: bool = true

## Number of objects to spawn per chunk (approximately)
## Higher values = more cluttered terrain
@export var objects_per_chunk: int = 12

## Minimum distance between objects (in meters)
## Higher values = more space for player movement
@export var min_object_spacing: float = 5.0

## Object size range (random between min and max)
@export var object_size_min: float = 1.0
@export var object_size_max: float = 2.5

## Chance (0..1) that a chunk gets one "feature" structure — a wall, a corridor,
## or a Mayan step-pyramid — for variety. Kept moderate so structures show up
## often enough to be interesting but the field doesn't feel crowded.
@export var structure_chance: float = 0.5

## How many blocks long a wall / corridor is (random between min and max).
@export var wall_min_length: int = 4
@export var wall_max_length: int = 7

## Chance (0..1) that a scattered block gets extra blocks stacked on top of it,
## so the terrain occasionally has little towers instead of only single cubes.
@export var stack_chance: float = 0.25

## Maximum number of extra blocks stacked on top of a stacked block.
@export var stack_max_extra: int = 2

## Enable/disable crocodile spawning on terrain
@export var spawn_crocodiles: bool = true

## Number of crocodiles to spawn per chunk
## Higher values = more dangerous terrain!
@export var crocodiles_per_chunk: int = 10

## Minimum distance between crocodiles (in meters)
@export var min_crocodile_spacing: float = 3.0

## How much clear space (in meters) to keep between a crocodile and the nearest
## block. This stops crocodiles from spawning partially buried inside blocks.
@export var min_object_clearance: float = 1.5

## Chance (0..1) that a given walkable structure top (pyramid apex / wall ridge)
## gets a rare crocodile patrolling it. Kept moderate so they're an occasional
## surprise, not on every structure.
@export var platform_crocodile_chance: float = 0.4

## Enable/disable collectible coin spawning on terrain
@export var spawn_coins: bool = true

## Number of coins to spawn per chunk. Kept modest so they stay motivating
## rather than carpeting the ground.
@export var coins_per_chunk: int = 6

## Minimum distance between coins (in meters)
@export var min_coin_spacing: float = 4.0

## Coin placement heights (metres):
## - ground coins float just above the grass, grabbed by walking over them
## - air coins sit above standing reach, so you have to jump for them
## - block coins sit this far above a block's top surface
const COIN_GROUND_HEIGHT: float = 0.9
const COIN_AIR_HEIGHT: float = 3.0
const COIN_BLOCK_OFFSET: float = 0.6

# ============================================================================
# SECTION 2: INTERNAL STATE
# ============================================================================

## Preloaded crocodile scene for spawning
var crocodile_scene: PackedScene

## Preloaded coin scene for spawning
var coin_scene: PackedScene

## Reference to the player node to track their position
var player: Node3D

## Dictionary to store active chunks
## Key: Vector2i (chunk coordinates), Value: MeshInstance3D (the chunk)
var active_chunks: Dictionary = {}

## Last player chunk position (to detect when to update chunks)
var last_player_chunk: Vector2i = Vector2i(999999, 999999)

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	"""
	Initialize the terrain system.
	"""
	# Load the crocodile scene for spawning
	crocodile_scene = load("res://scenes/characters/piglet_crocodile.tscn")
	if not crocodile_scene:
		push_warning("Failed to load crocodile scene!")
		spawn_crocodiles = false

	# Load the coin scene for spawning
	coin_scene = load("res://scenes/collectibles/coin.tscn")
	if not coin_scene:
		push_warning("Failed to load coin scene!")
		spawn_coins = false

	# Find the player in the scene tree
	# We'll use this to track where to generate terrain
	await get_tree().process_frame  # Wait for scene to be fully ready
	player = get_tree().get_first_node_in_group("player")

	if not player:
		push_warning("No player found! Add the player to the 'player' group.")
		return

	# Create default material if none provided
	if not terrain_material:
		terrain_material = StandardMaterial3D.new()
		terrain_material.albedo_color = Color(0.2, 0.6, 0.2)  # Green grass color
		terrain_material.roughness = 0.8

	print("Endless Terrain System initialized!")
	print("Chunk size: ", chunk_size, "m")
	print("Render distance: ", render_distance, " chunks")
	print("Crocodiles per chunk: ", crocodiles_per_chunk if spawn_crocodiles else 0)

func _process(_delta: float) -> void:
	"""
	Update terrain chunks every frame based on player position.

	EDUCATIONAL NOTE:
	- We only update when the player moves to a new chunk
	- This prevents unnecessary updates every frame
	"""
	if not player:
		return

	# Calculate which chunk the player is currently in
	var player_chunk := world_to_chunk(player.global_position)

	# Only update if player moved to a different chunk
	if player_chunk != last_player_chunk:
		update_chunks(player_chunk)
		last_player_chunk = player_chunk

# ============================================================================
# CHUNK MANAGEMENT FUNCTIONS
# ============================================================================

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	"""
	Converts a world position to chunk coordinates.

	@param world_pos: Position in 3D world space
	@return Vector2i: Chunk coordinates (we only use X and Z, not Y)

	EDUCATIONAL NOTE:
	- We divide the world into a grid of chunks
	- Each chunk has integer coordinates
	- Example: Position (75, 0, -25) with chunk_size=50 -> Chunk (1, 0)
	"""
	return Vector2i(
		int(floor(world_pos.x / chunk_size)),
		int(floor(world_pos.z / chunk_size))
	)

func chunk_to_world(chunk_pos: Vector2i) -> Vector3:
	"""
	Converts chunk coordinates to world position (center of chunk).

	@param chunk_pos: Chunk coordinates
	@return Vector3: World position at the center of the chunk
	"""
	return Vector3(
		chunk_pos.x * chunk_size + chunk_size / 2.0,
		terrain_height,
		chunk_pos.y * chunk_size + chunk_size / 2.0
	)

func update_chunks(player_chunk: Vector2i) -> void:
	"""
	Updates which chunks are visible based on player position.
	Creates new chunks in range, removes chunks out of range.

	@param player_chunk: The chunk coordinates where the player is

	EDUCATIONAL NOTE:
	- This is the "magic" that makes the terrain endless
	- We maintain a square of chunks around the player
	- As the player moves, we add/remove chunks at the edges
	"""

	# STEP 1: Find all chunks that SHOULD be loaded
	var chunks_to_load: Array[Vector2i] = []

	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var chunk_pos := Vector2i(player_chunk.x + x, player_chunk.y + z)
			chunks_to_load.append(chunk_pos)

	# STEP 2: Remove chunks that are too far away
	var chunks_to_remove: Array[Vector2i] = []

	for chunk_pos in active_chunks.keys():
		if chunk_pos not in chunks_to_load:
			chunks_to_remove.append(chunk_pos)

	for chunk_pos in chunks_to_remove:
		remove_chunk(chunk_pos)

	# STEP 3: Create new chunks that don't exist yet
	for chunk_pos in chunks_to_load:
		if chunk_pos not in active_chunks:
			create_chunk(chunk_pos)

func create_chunk(chunk_pos: Vector2i) -> void:
	"""
	Creates a new terrain chunk at the specified chunk coordinates.

	@param chunk_pos: Chunk coordinates where to create the terrain

	EDUCATIONAL NOTE:
	- We create a simple flat plane mesh procedurally
	- Each chunk is a MeshInstance3D with collision
	- In advanced games, you could add noise/procedural generation here!
	"""

	# Create a new MeshInstance to hold the chunk's visual geometry
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Chunk_%d_%d" % [chunk_pos.x, chunk_pos.y]

	# Create the plane mesh
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(chunk_size, chunk_size)
	plane_mesh.subdivide_width = 10  # More subdivisions = smoother mesh
	plane_mesh.subdivide_depth = 10
	plane_mesh.material = terrain_material

	mesh_instance.mesh = plane_mesh

	# Position the chunk in the world
	mesh_instance.position = chunk_to_world(chunk_pos)

	# Add collision so the player doesn't fall through
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()

	box_shape.size = Vector3(chunk_size, 0.1, chunk_size)
	collision_shape.shape = box_shape

	static_body.add_child(collision_shape)
	mesh_instance.add_child(static_body)

	# Add to scene and register in our dictionary
	add_child(mesh_instance)
	active_chunks[chunk_pos] = mesh_instance

	# Spawn objects in this chunk if enabled. This returns the footprint of every
	# block placed (walls included) so crocodiles can avoid spawning inside them,
	# and fills `platforms` with walkable structure tops for patrolling crocodiles.
	var obstacles: Array = []
	var platforms: Array = []
	if spawn_objects:
		obstacles = spawn_objects_in_chunk(chunk_pos, mesh_instance, platforms)

	# Spawn crocodiles in this chunk if enabled
	if spawn_crocodiles:
		spawn_crocodiles_in_chunk(chunk_pos, mesh_instance, obstacles)
		# Rare crocodiles that patrol an elevated platform (pyramid top / wall ridge)
		spawn_platform_crocodiles(chunk_pos, mesh_instance, platforms)

	# Spawn collectible coins (on the ground, on blocks, and some up in the air)
	if spawn_coins:
		spawn_coins_in_chunk(chunk_pos, mesh_instance, obstacles)

func spawn_objects_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> Array:
	"""
	Spawns blocks within a terrain chunk: scattered cubes, the occasional little
	stack/tower, and — sometimes — a feature structure (wall / corridor / gate /
	pyramid).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach objects to
	@param platforms: Out-param; feature structures append walkable-top descriptors
	                  here for patrolling crocodiles.
	@return Array of obstacle footprints ({ "pos": Vector3, "radius": float }) so
	        the crocodile spawner can keep its NPCs out of the blocks.

	EDUCATIONAL NOTE:
	- We use chunk coordinates as a seed for deterministic randomness
	- This means the same chunk always generates the same objects
	- Objects are parented to the chunk so they're removed when chunk is removed
	"""

	# Use chunk coordinates to create a unique but consistent seed
	# This ensures the same chunk always generates the same objects
	var seed_value := hash(Vector2i(chunk_pos.x * 73856093, chunk_pos.y * 19349663))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Half the chunk width — handy for keeping things inside the chunk bounds.
	var half_chunk := chunk_size / 2.0

	# Footprints of every block we place, returned so crocodiles can avoid them.
	var obstacles: Array = []

	# Occasionally build one feature structure first (wall / corridor / pyramid),
	# so scattered blocks can be placed around it (the scatter loop below checks
	# against these footprints).
	if rng.randf() < structure_chance:
		spawn_feature_structure(rng, parent_chunk, half_chunk, obstacles, platforms)

	# Store positions of scattered objects to check spacing between them
	var spawned_positions: Array[Vector3] = []

	# Try to spawn objects with proper spacing
	var attempts := 0
	var max_attempts := objects_per_chunk * 3  # Allow multiple attempts per object

	while spawned_positions.size() < objects_per_chunk and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		# Leave some margin from edges for better appearance
		var margin := 2.0
		var random_x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var random_z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var object_pos := Vector3(random_x, 0, random_z)

		# Check if this position is far enough from other scattered objects...
		var valid_position := true
		for existing_pos in spawned_positions:
			if object_pos.distance_to(existing_pos) < min_object_spacing:
				valid_position = false
				break

		# ...and not sitting on top of a wall block we placed above.
		if valid_position:
			for ob in obstacles:
				if Vector2(random_x - ob.pos.x, random_z - ob.pos.z).length() < min_object_spacing:
					valid_position = false
					break

		if not valid_position:
			continue

		# Base block sits on the ground.
		var size := rng.randf_range(object_size_min, object_size_max)
		create_block(parent_chunk, Vector3(random_x, size / 2.0, random_z), size, rng.randf_range(0, TAU), rng)
		spawned_positions.append(object_pos)

		# Track the height of the top surface (grows if we stack a tower on top).
		var top_y := size

		# Sometimes stack a few smaller blocks on top to make a little tower.
		if rng.randf() < stack_chance:
			var stack_count := rng.randi_range(1, stack_max_extra)
			for i in stack_count:
				# Each block up the stack is a bit smaller, so towers taper and
				# the random yaw doesn't make them overhang awkwardly.
				var stack_size := size * rng.randf_range(0.6, 0.85)
				create_block(parent_chunk, Vector3(random_x, top_y + stack_size / 2.0, random_z), stack_size, rng.randf_range(0, TAU), rng)
				top_y += stack_size

		# Record the footprint and final top height — used to keep crocodiles out
		# of the block and to perch coins on top of it. Single blocks/towers are
		# climbable (their steps are <= one jump), so coins may sit on top.
		obstacles.append({ "pos": Vector3(random_x, 0, random_z), "radius": size * 0.71, "top": top_y, "climbable": true })

	return obstacles

func spawn_feature_structure(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array, platforms: Array) -> void:
	"""
	Pick and build one "feature" structure for variety: a wall, a corridor to run
	through, a gate, or a Mayan step-pyramid. Pyramids are the biggest/rarest
	landmark. Walls and pyramids also register a walkable top (platforms) that a
	patrolling crocodile can be placed on.

	@param rng: The chunk's seeded RNG (so the choice is deterministic)
	@param parent_chunk: The chunk mesh to attach the structure to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list each piece is appended to (crocodiles + coins)
	@param platforms: Walkable-top descriptors for patrolling crocodiles
	"""
	var pick := rng.randf()
	if pick < 0.3:
		spawn_wall(rng, parent_chunk, half_chunk, obstacles, platforms)
	elif pick < 0.55:
		spawn_corridor(rng, parent_chunk, half_chunk, obstacles)
	elif pick < 0.75:
		spawn_gate(rng, parent_chunk, half_chunk, obstacles)
	else:
		spawn_pyramid(rng, parent_chunk, half_chunk, obstacles, platforms)

func spawn_pyramid(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array, platforms: Array) -> void:
	"""
	Build a Mayan step-pyramid: a few square slabs stacked smallest-on-top, like a
	ziggurat. Each layer is a single flat box (cheap), not a grid of cubes.

	@param rng: The chunk's seeded RNG
	@param parent_chunk: The chunk mesh to attach the slabs to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list (one entry for the whole base, with the apex
	                  height as its top so a coin can perch on top)
	@param platforms: Gets the flat apex registered as a patrol platform
	"""
	# Pyramids vary a lot in size. Most are modest; now and then a giant one with
	# 10-15 levels towers over the field as a landmark you can climb.
	var layers: int
	var base_size: float
	if rng.randf() < 0.25:
		layers = rng.randi_range(10, 15)
		base_size = rng.randf_range(16.0, 24.0)
	else:
		layers = rng.randi_range(3, 6)
		base_size = rng.randf_range(6.0, 11.0)

	var layer_height := rng.randf_range(1.0, 1.5)
	# How much narrower each layer is than the one below it.
	var shrink := base_size / float(layers + 1)

	# Keep the whole base inside the chunk.
	var limit := half_chunk - (base_size * 0.5 + 1.0)
	if limit <= 0.0:
		return  # chunk too small for this pyramid; skip it
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	var y := 0.0
	for i in layers:
		var w := base_size - i * shrink
		create_box(parent_chunk, Vector3(cx, y + layer_height / 2.0, cz), Vector3(w, layer_height, w), 0.0, rng)
		y += layer_height

	# One footprint for the whole base; top = apex height. Pyramids are climbable
	# via their steps, so a coin on the apex is reachable (just a long climb).
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": base_size * 0.71, "top": y, "climbable": true })

	# Register the flat apex as a patrol platform (if it's big enough to stand on).
	var apex_w := base_size - (layers - 1) * shrink
	var apex_half := apex_w * 0.5 - 0.3
	if apex_half > 0.4:
		platforms.append({ "center": Vector3(cx, y, cz), "half": Vector2(apex_half, apex_half) })

func spawn_gate(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array) -> void:
	"""
	Build a monumental gate (Brandenburg-Tor style): two tall pillars with a thick
	lintel beam across the top, leaving an opening to walk through.

	The pillars are about as tall as a full jump, so reaching the coin that perches
	on the lintel is genuinely hard — you have to hop up onto a pillar and then up
	onto the lintel. That's intentional "hard to reach" gameplay.

	@param rng: The chunk's seeded RNG
	@param parent_chunk: The chunk mesh to attach the gate to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list (pillars, plus a coin-perch on the lintel)
	"""
	var pillar_w := rng.randf_range(1.3, 1.8)
	# Pillars stay just under jump height (~3.6 m) so you can still hop onto one to
	# reach the lintel coin — hard, but possible.
	var pillar_h := rng.randf_range(2.7, 3.1)
	var depth := rng.randf_range(1.3, 2.0)
	var opening := rng.randf_range(3.0, 4.5)
	var lintel_h := rng.randf_range(0.9, 1.3)
	var total_w := opening + 2.0 * pillar_w  # full span across both pillars

	# Pillars are separated along X (and you walk through along Z) or vice-versa.
	var along_x := rng.randf() < 0.5

	# Conservative bound that fits the gate whichever way it's turned.
	var limit := half_chunk - (total_w * 0.5 + 1.0)
	if limit <= 0.0:
		return
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# Distance from the gate centre to each pillar's centre.
	var half_span := opening * 0.5 + pillar_w * 0.5

	for pillar_sign in 2:
		var s := -1.0 if pillar_sign == 0 else 1.0
		var px: float = cx + (s * half_span if along_x else 0.0)
		var pz: float = cz + (0.0 if along_x else s * half_span)
		# Pillar is pillar_w across the span axis and `depth` across the other.
		var pillar_dims: Vector3 = Vector3(pillar_w, pillar_h, depth) if along_x else Vector3(depth, pillar_h, pillar_w)
		create_box(parent_chunk, Vector3(px, pillar_h * 0.5, pz), pillar_dims, 0.0, rng)
		# Each pillar is its own footprint, so crocodiles can still pass through
		# the opening between them.
		obstacles.append({ "pos": Vector3(px, 0, pz), "radius": maxf(pillar_w, depth) * 0.71, "top": pillar_h, "climbable": true })

	# Lintel beam spanning the full width, resting on top of both pillars.
	var lintel_dims: Vector3 = Vector3(total_w, lintel_h, depth) if along_x else Vector3(depth, lintel_h, total_w)
	create_box(parent_chunk, Vector3(cx, pillar_h + lintel_h * 0.5, cz), lintel_dims, 0.0, rng)

	# Register the lintel centre as a (hard-to-reach but climbable) coin perch.
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": 1.0, "top": pillar_h + lintel_h, "climbable": true })

func spawn_corridor(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array) -> void:
	"""
	Build a corridor: two parallel two-block-high walls with a gap between them
	that the player can run down.

	@param rng: The chunk's seeded RNG
	@param parent_chunk: The chunk mesh to attach the walls to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list each block is appended to
	"""
	var block_size := rng.randf_range(1.8, 2.4)
	var step := block_size * 0.98
	var length := rng.randi_range(wall_min_length + 1, wall_max_length + 1)
	# Width of the walkable gap between the two walls.
	var gap := rng.randf_range(2.5, 4.0)

	var along_x := rng.randf() < 0.5
	var limit := half_chunk - 2.0

	# Trim the corridor if it's longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Bail if the chunk can't fit the corridor's width.
	if limit - gap * 0.5 <= -limit + gap * 0.5:
		return
	var start := rng.randf_range(-limit, limit - span)
	# Centreline of the corridor on the perpendicular axis.
	var center_perp := rng.randf_range(-limit + gap * 0.5, limit - gap * 0.5)

	# Two parallel walls, offset to either side of the centreline.
	for side_sign in 2:
		var side := -1.0 if side_sign == 0 else 1.0
		var perp := center_perp + side * gap * 0.5
		for i in length:
			var along := start + i * step
			var x := along if along_x else perp
			var z := perp if along_x else along
			# Two blocks tall so it reads as an enclosed passage. Sheer and taller
			# than a jump, so it's not climbable (no coins perch on the roof).
			create_block(parent_chunk, Vector3(x, block_size / 2.0, z), block_size, 0.0, rng)
			create_block(parent_chunk, Vector3(x, block_size + block_size / 2.0, z), block_size, 0.0, rng)
			obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": 2.0 * block_size, "climbable": false })

func spawn_wall(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array, platforms: Array) -> void:
	"""
	Build a single wall — a straight line of touching blocks the player must run
	around — somewhere inside the chunk.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param parent_chunk: The chunk mesh to attach the wall blocks to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list to append each wall block to (for crocodiles)
	@param platforms: Gets the wall ridge registered as a patrol platform
	"""
	# Uniform block size so the wall reads as one solid line.
	var block_size := rng.randf_range(1.6, 2.4)
	# Step slightly less than the block size so neighbours overlap — no gaps.
	var step := block_size * 0.98
	var length := rng.randi_range(wall_min_length, wall_max_length)

	# Run the wall along X or along Z.
	var along_x := rng.randf() < 0.5
	var margin := 2.0
	var limit := half_chunk - margin

	# Distance from the first block centre to the last. Trim the wall if it would
	# be longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Pick where the wall starts along its axis, and its fixed perpendicular coord.
	var start := rng.randf_range(-limit, limit - span)
	var fixed := rng.randf_range(-limit, limit)

	for i in length:
		var along := start + i * step
		var x := along if along_x else fixed
		var z := fixed if along_x else along

		# Wall blocks are axis-aligned (yaw 0) so they sit flush against each other.
		create_block(parent_chunk, Vector3(x, block_size / 2.0, z), block_size, 0.0, rng)
		var top := block_size
		# A single-block section is low enough to hop onto; a doubled one is not.
		var climbable := true

		# Now and then double a section up so the wall isn't a uniform single row.
		if rng.randf() < 0.3:
			create_block(parent_chunk, Vector3(x, block_size + block_size / 2.0, z), block_size, 0.0, rng)
			top = 2.0 * block_size
			climbable = false

		obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": top, "climbable": climbable })

	# Register the wall ridge as a thin patrol platform (a crocodile can pace it
	# end to end). Surface is the single-block height; doubled humps just become
	# obstacles its feelers turn it back at.
	var mid_along := start + (length - 1) * step * 0.5
	var ridge_center: Vector3 = Vector3(mid_along, block_size, fixed) if along_x else Vector3(fixed, block_size, mid_along)
	var half_along := (length - 1) * step * 0.5 + block_size * 0.5 - 0.4
	var half_across := block_size * 0.5 - 0.3
	var ridge_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
	if half_along > 1.0 and half_across > 0.2:
		platforms.append({ "center": ridge_center, "half": ridge_half })

func create_block(parent_chunk: MeshInstance3D, center_pos: Vector3, size: float, yaw: float, rng: RandomNumberGenerator) -> void:
	"""
	Create one cube block. Thin wrapper over create_box for the common case where
	all three dimensions are equal (scattered blocks, towers, walls, corridors).
	"""
	create_box(parent_chunk, center_pos, Vector3(size, size, size), yaw, rng)

func create_box(parent_chunk: MeshInstance3D, center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	"""
	Create one box (mesh + earthy material + matching box collision) and parent it
	to the chunk. Used for cube blocks and for the flat slabs that make up pyramids.

	@param parent_chunk: The chunk mesh to attach the box to
	@param center_pos: Box centre position, local to the chunk (Y is the centre,
	                   so pass height/2 to sit a box on the ground)
	@param dimensions: Full box size on each axis (width, height, depth)
	@param yaw: Y rotation in radians (0 to keep faces axis-aligned)
	@param rng: The chunk's seeded RNG, used for the random material colour
	"""
	var object_instance := MeshInstance3D.new()

	# Create a box mesh at the requested dimensions
	var box_mesh := BoxMesh.new()
	box_mesh.size = dimensions

	# Create a material with random earthy/natural colours (browns, grays, mossy)
	var object_material := StandardMaterial3D.new()
	var color_choice := rng.randi_range(0, 2)
	match color_choice:
		0:  # Brown rocks
			object_material.albedo_color = Color(
				rng.randf_range(0.3, 0.5),
				rng.randf_range(0.2, 0.4),
				rng.randf_range(0.1, 0.3)
			)
		1:  # Gray stones
			var gray := rng.randf_range(0.3, 0.6)
			object_material.albedo_color = Color(gray, gray, gray)
		2:  # Dark green (mossy)
			object_material.albedo_color = Color(
				rng.randf_range(0.1, 0.3),
				rng.randf_range(0.3, 0.5),
				rng.randf_range(0.1, 0.3)
			)

	object_material.roughness = rng.randf_range(0.7, 1.0)
	box_mesh.material = object_material
	object_instance.mesh = box_mesh

	# Position (local to the chunk) and orient the box.
	object_instance.position = center_pos
	object_instance.rotation.y = yaw

	# Add collision so the player (and crocodiles) can't walk through the box.
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = dimensions
	collision_shape.shape = box_shape

	static_body.add_child(collision_shape)
	object_instance.add_child(static_body)

	# Add to chunk (so it gets removed when chunk is removed)
	parent_chunk.add_child(object_instance)

func spawn_crocodiles_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array = []) -> void:
	"""
	Spawns crocodile NPCs within a terrain chunk.

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach crocodiles to
	@param obstacles: Block footprints to keep crocodiles out of, so they don't
	                  spawn partially buried inside a block (see spawn_objects_in_chunk)

	EDUCATIONAL NOTE:
	- Crocodiles are spawned dynamically with the terrain
	- They are parented to the chunk so they're removed when chunk is removed
	- This creates an endless stream of enemies as you explore
	"""

	if not crocodile_scene:
		return

	# Use chunk coordinates to create a unique but consistent seed
	# Offset the hash value to get different positions than objects
	var seed_value := hash(Vector2i(chunk_pos.x * 83492791, chunk_pos.y * 28411639))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Calculate the world position of this chunk's corner
	var chunk_world_pos := chunk_to_world(chunk_pos)
	var half_chunk := chunk_size / 2.0

	# Store positions of spawned crocodiles to check spacing
	var spawned_positions: Array[Vector3] = []

	# Try to spawn crocodiles with proper spacing
	var attempts := 0
	var max_attempts := crocodiles_per_chunk * 5  # Allow multiple attempts per crocodile

	while spawned_positions.size() < crocodiles_per_chunk and attempts < max_attempts:
		attempts += 1

		# Generate random position within chunk bounds
		var margin := 3.0  # Keep away from edges
		var random_x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var random_z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
		var crocodile_pos := Vector3(random_x, 0.5, random_z)  # Y=0.5 to spawn above ground

		# Check if this position is far enough from existing crocodiles
		var valid_position := true
		for existing_pos in spawned_positions:
			if crocodile_pos.distance_to(existing_pos) < min_crocodile_spacing:
				valid_position = false
				break

		# Also reject positions that overlap a block, so crocodiles never spawn
		# partially inside one. We compare horizontal distance against the block's
		# footprint radius plus a clearance margin.
		if valid_position:
			for ob in obstacles:
				var horizontal := Vector2(crocodile_pos.x - ob.pos.x, crocodile_pos.z - ob.pos.z).length()
				if horizontal < ob.radius + min_object_clearance:
					valid_position = false
					break

		if not valid_position:
			continue

		# Instantiate the crocodile
		var crocodile_instance = crocodile_scene.instantiate()
		crocodile_instance.name = "Crocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, spawned_positions.size()]

		# Position relative to chunk
		crocodile_instance.position = crocodile_pos

		# Random initial rotation for variety
		crocodile_instance.rotation.y = rng.randf_range(0, TAU)

		# Add to chunk (so it gets removed when chunk is removed)
		parent_chunk.add_child(crocodile_instance)
		spawned_positions.append(crocodile_pos)

	if spawned_positions.size() > 0:
		print("Spawned %d crocodiles in chunk (%d, %d)" % [spawned_positions.size(), chunk_pos.x, chunk_pos.y])

func spawn_platform_crocodiles(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, platforms: Array) -> void:
	"""
	Place rare crocodiles that patrol an elevated structure top (a pyramid apex or
	a wall ridge). They can't jump or climb, so each is confined to its platform —
	it paces around but never walks off the edge (see set_confinement in the AI).

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach the crocodiles to
	@param platforms: Walkable-top descriptors ({ "center": Vector3, "half": Vector2 })
	"""
	if not crocodile_scene or platforms.is_empty():
		return

	var seed_value := hash(Vector2i(chunk_pos.x * 40499, chunk_pos.y * 86969))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var count := 0
	for platform in platforms:
		# Only some platforms get a guard, so they stay a rare surprise.
		if rng.randf() > platform_crocodile_chance:
			continue

		var center: Vector3 = platform.center
		var half: Vector2 = platform.half

		# Start a little in from the edges so it lands cleanly on the surface.
		var ang := rng.randf_range(0.0, TAU)
		var sx := maxf(0.0, half.x - 1.0) * cos(ang)
		var sz := maxf(0.0, half.y - 1.0) * sin(ang)

		var crocodile := crocodile_scene.instantiate()
		crocodile.name = "PatrolCrocodile_%d_%d_%d" % [chunk_pos.x, chunk_pos.y, count]
		# Spawn just above the surface so gravity settles it onto the platform.
		crocodile.position = Vector3(center.x + sx, center.y + 0.6, center.z + sz)
		crocodile.rotation.y = rng.randf_range(0.0, TAU)
		parent_chunk.add_child(crocodile)

		# Confine it to this platform (in world space) so it can never wander off.
		if crocodile.has_method("set_confinement"):
			var center_global: Vector3 = parent_chunk.global_position + center
			crocodile.set_confinement(center_global, half)

		count += 1

	if count > 0:
		print("Spawned %d patrolling crocodile(s) in chunk (%d, %d)" % [count, chunk_pos.x, chunk_pos.y])

func spawn_coins_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Scatter collectible coins through a chunk. A coin is one of three kinds:
	  - a ground coin floating just above the grass (walk over it),
	  - an air coin up at jump height (you have to jump for it), or
	  - a block coin perched on top of a block / tower.

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach coins to
	@param obstacles: Block footprints (with their top heights) from
	                  spawn_objects_in_chunk, used to place block coins and to keep
	                  low coins from spawning inside a block.

	EDUCATIONAL NOTE:
	- Seeded like everything else, so a chunk's coins are always the same.
	- Coins are parented to the chunk, so they unload when the chunk does.
	"""
	if not coin_scene:
		return

	# Seed offset so coins land in different spots than objects/crocodiles.
	var seed_value := hash(Vector2i(chunk_pos.x * 19783, chunk_pos.y * 51307))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var half_chunk := chunk_size / 2.0
	var margin := 3.0

	# Positions placed so far, to keep coins spaced out.
	var placed: Array[Vector3] = []

	var attempts := 0
	var max_attempts := coins_per_chunk * 6

	while placed.size() < coins_per_chunk and attempts < max_attempts:
		attempts += 1

		var coin_pos: Vector3
		var roll := rng.randf()

		if roll < 0.3:
			# Perch a coin on top of a *climbable* structure, so it can actually be
			# reached. Sheer tops taller than a jump (doubled walls, corridor roofs)
			# are skipped; pyramids/gates/blocks are fair game.
			var perches: Array = []
			for o in obstacles:
				if o.get("climbable", false):
					perches.append(o)
			if perches.is_empty():
				continue
			var ob = perches[rng.randi_range(0, perches.size() - 1)]
			coin_pos = Vector3(ob.pos.x, ob.top + COIN_BLOCK_OFFSET, ob.pos.z)
		else:
			# Out in the open: a ground-level coin, or a higher "jump for it" one.
			var x := rng.randf_range(-half_chunk + margin, half_chunk - margin)
			var z := rng.randf_range(-half_chunk + margin, half_chunk - margin)
			# Don't bury a low coin inside a block.
			if _point_over_block(x, z, obstacles):
				continue
			var y := COIN_GROUND_HEIGHT if roll < 0.7 else COIN_AIR_HEIGHT
			coin_pos = Vector3(x, y, z)

		# Keep coins spaced apart from each other.
		var valid := true
		for existing in placed:
			if coin_pos.distance_to(existing) < min_coin_spacing:
				valid = false
				break
		if not valid:
			continue

		# Spawn the coin (position is local to the chunk, like blocks/crocodiles).
		var coin := coin_scene.instantiate()
		coin.position = coin_pos
		parent_chunk.add_child(coin)
		placed.append(coin_pos)

func _point_over_block(x: float, z: float, obstacles: Array) -> bool:
	"""
	True if the (x, z) column is over (or hugging) a block footprint, so we don't
	drop a ground/air coin inside a block.
	"""
	for ob in obstacles:
		if Vector2(x - ob.pos.x, z - ob.pos.z).length() < ob.radius + 1.0:
			return true
	return false

func remove_chunk(chunk_pos: Vector2i) -> void:
	"""
	Removes a chunk from the scene to save memory.

	@param chunk_pos: Chunk coordinates to remove

	EDUCATIONAL NOTE:
	- We use queue_free() instead of free() for safety
	- This ensures the node is removed at a safe time
	- We also remove it from our dictionary to free memory
	"""
	if chunk_pos in active_chunks:
		var chunk = active_chunks[chunk_pos]
		chunk.queue_free()
		active_chunks.erase(chunk_pos)

# ============================================================================
# DEBUG FUNCTIONS
# ============================================================================

func get_chunk_count() -> int:
	"""
	Returns the number of currently active chunks.
	Useful for performance monitoring.
	"""
	return active_chunks.size()

func _to_string() -> String:
	"""
	Debug information about the terrain system.
	"""
	return "EndlessTerrain[Chunks: %d, Player Chunk: %s]" % [
		get_chunk_count(),
		last_player_chunk
	]
