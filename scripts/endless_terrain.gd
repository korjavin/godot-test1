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

## Chance (0..1) that a chunk contains a wall — a line of blocks the player has
## to run around. Kept low so walls show up only "sometimes", not every chunk.
@export var wall_chance: float = 0.35

## How many blocks long a wall is (random between min and max).
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

# ============================================================================
# SECTION 2: INTERNAL STATE
# ============================================================================

## Preloaded crocodile scene for spawning
var crocodile_scene: PackedScene

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
	# block placed (walls included) so crocodiles can avoid spawning inside them.
	var obstacles: Array = []
	if spawn_objects:
		obstacles = spawn_objects_in_chunk(chunk_pos, mesh_instance)

	# Spawn crocodiles in this chunk if enabled
	if spawn_crocodiles:
		spawn_crocodiles_in_chunk(chunk_pos, mesh_instance, obstacles)

func spawn_objects_in_chunk(chunk_pos: Vector2i, parent_chunk: MeshInstance3D) -> Array:
	"""
	Spawns blocks within a terrain chunk: scattered cubes, the occasional little
	stack/tower, and — sometimes — a wall the player has to run around.

	@param chunk_pos: Chunk coordinates for seeded random generation
	@param parent_chunk: The chunk mesh to attach objects to
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

	# Occasionally lay down a wall first, so scattered blocks can be placed around
	# it (the scatter loop below checks against these footprints).
	if rng.randf() < wall_chance:
		spawn_wall(rng, parent_chunk, half_chunk, obstacles)

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
		obstacles.append({ "pos": Vector3(random_x, 0, random_z), "radius": size * 0.71 })

		# Sometimes stack a few smaller blocks on top to make a little tower.
		if rng.randf() < stack_chance:
			var stack_count := rng.randi_range(1, stack_max_extra)
			var top_y := size  # current height of the top surface of the stack
			for i in stack_count:
				# Each block up the stack is a bit smaller, so towers taper and
				# the random yaw doesn't make them overhang awkwardly.
				var stack_size := size * rng.randf_range(0.6, 0.85)
				create_block(parent_chunk, Vector3(random_x, top_y + stack_size / 2.0, random_z), stack_size, rng.randf_range(0, TAU), rng)
				top_y += stack_size

	return obstacles

func spawn_wall(rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, half_chunk: float, obstacles: Array) -> void:
	"""
	Build a single wall — a straight line of touching blocks the player must run
	around — somewhere inside the chunk.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param parent_chunk: The chunk mesh to attach the wall blocks to
	@param half_chunk: Half the chunk width, for bounds
	@param obstacles: Footprint list to append each wall block to (for crocodiles)
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
		obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71 })

		# Now and then double a section up so the wall isn't a uniform single row.
		if rng.randf() < 0.3:
			create_block(parent_chunk, Vector3(x, block_size + block_size / 2.0, z), block_size, 0.0, rng)

func create_block(parent_chunk: MeshInstance3D, center_pos: Vector3, size: float, yaw: float, rng: RandomNumberGenerator) -> void:
	"""
	Create one cube block (mesh + earthy material + box collision) and parent it
	to the chunk. Shared by the scattered blocks, the stacked towers and the walls.

	@param parent_chunk: The chunk mesh to attach the block to
	@param center_pos: Block centre position, local to the chunk (Y is the centre,
	                    so pass size/2 to sit a block on the ground)
	@param size: Cube edge length
	@param yaw: Y rotation in radians (0 for walls so they line up; random for scatter)
	@param rng: The chunk's seeded RNG, used for the random material colour
	"""
	var object_instance := MeshInstance3D.new()

	# Create a cube mesh at the requested size
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = Vector3(size, size, size)

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
	cube_mesh.material = object_material
	object_instance.mesh = cube_mesh

	# Position (local to the chunk) and orient the block.
	object_instance.position = center_pos
	object_instance.rotation.y = yaw

	# Add collision so the player (and crocodiles) can't walk through the block.
	var static_body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(size, size, size)
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
