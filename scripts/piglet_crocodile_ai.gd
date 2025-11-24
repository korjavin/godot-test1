extends CharacterBody3D
## Piglet Crocodile NPC AI
##
## This script controls the behavior of hostile piglet crocodiles.
## They wander randomly but will chase the player when detected.
##
## Behavior:
## - Random wandering with periodic direction changes
## - Detection radius: can "smell" the player within range
## - Chase mode: pursues player at increased speed when detected
## - Returns to wandering when player escapes detection range
## - Fatal collision with player (resets player position)

# ============================================================================
# CONSTANTS
# ============================================================================

## Movement speed in meters per second (wandering)
const MOVE_SPEED: float = 2.5

## Chase speed when pursuing player (faster)
const CHASE_SPEED: float = 3.5

## Detection radius - distance at which crocodile can "smell" the player
const DETECTION_RADIUS: float = 15.0

## Time between direction changes (in seconds)
const DIRECTION_CHANGE_INTERVAL: float = 4.0

## Pause duration when changing direction (in seconds)
const PAUSE_DURATION: float = 0.5

## Gravity acceleration (matches project default)
const GRAVITY: float = 9.8

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Current movement direction (normalized Vector3)
var movement_direction: Vector3 = Vector3.ZERO

## Time accumulator for direction changes
var time_since_direction_change: float = 0.0

## Is the crocodile currently paused?
var is_paused: bool = false

## Pause time remaining
var pause_time_remaining: float = 0.0

## Is the crocodile currently chasing the player?
var is_chasing: bool = false

## Reference to the player node
var player_node: Node3D = null

## Random number generator for movement
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	"""Initialize the crocodile NPC."""
	# Randomize the RNG
	rng.randomize()

	# Set initial random direction
	_choose_new_direction()

	# Add to "crocodile" group for easy detection
	add_to_group("crocodile")
	add_to_group("enemy")

	# Start with a random offset to avoid all crocodiles changing direction at once
	time_since_direction_change = randf() * DIRECTION_CHANGE_INTERVAL

	# Find the player node (defer to allow scene to fully load)
	call_deferred("_find_player")


func _physics_process(delta: float) -> void:
	"""Update movement and handle collision every physics frame."""
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# Handle pause state
	if is_paused:
		pause_time_remaining -= delta
		if pause_time_remaining <= 0:
			is_paused = false
		# Don't move while paused
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	# Check if player is in detection range
	_update_chase_state()

	# Choose movement behavior based on state
	if is_chasing and player_node:
		# Chase the player
		_chase_player()
	else:
		# Wander randomly
		_wander(delta)

	# Rotate to face movement direction
	if movement_direction.length() > 0.1:
		var target_rotation = atan2(movement_direction.x, movement_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

		# Apply movement based on facing direction (prevents sliding sideways)
		var current_speed = CHASE_SPEED if is_chasing else MOVE_SPEED
		velocity.x = sin(rotation.y) * current_speed
		velocity.z = cos(rotation.y) * current_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	# Move and handle collisions
	move_and_slide()

	# Handle collisions with player and other crocodiles
	_handle_collisions()


# ============================================================================
# DETECTION AND CHASE METHODS
# ============================================================================

func _find_player() -> void:
	"""Find and store reference to the player node."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]


func _update_chase_state() -> void:
	"""Check distance to player and update chase state."""
	if not player_node:
		is_chasing = false
		return

	# Calculate distance to player
	var distance_to_player = global_position.distance_to(player_node.global_position)

	# Update chase state based on detection radius
	if distance_to_player <= DETECTION_RADIUS:
		if not is_chasing:
			# Just started chasing
			is_chasing = true
	else:
		if is_chasing:
			# Lost the player
			is_chasing = false
			# Choose new random direction
			_choose_new_direction()


func _chase_player() -> void:
	"""Set movement direction toward the player."""
	if not player_node:
		return

	# Calculate direction to player (on XZ plane)
	var direction_to_player = player_node.global_position - global_position
	direction_to_player.y = 0  # Keep movement on horizontal plane
	movement_direction = direction_to_player.normalized()


func _wander(delta: float) -> void:
	"""Handle random wandering behavior."""
	# Update direction change timer
	time_since_direction_change += delta
	if time_since_direction_change >= DIRECTION_CHANGE_INTERVAL:
		_pause_and_change_direction()


# ============================================================================
# AI BEHAVIOR METHODS
# ============================================================================

func _choose_new_direction() -> void:
	"""Choose a new random movement direction."""
	# Random angle in radians
	var angle: float = rng.randf_range(0, TAU)  # TAU = 2*PI = full circle

	# Convert to direction vector (on XZ plane, Y=0 for ground movement)
	movement_direction = Vector3(
		sin(angle),
		0,
		cos(angle)
	).normalized()

	# Reset timer
	time_since_direction_change = 0.0


func _pause_and_change_direction() -> void:
	"""Pause briefly, then choose a new direction."""
	is_paused = true
	pause_time_remaining = PAUSE_DURATION
	_choose_new_direction()


# ============================================================================
# COLLISION DETECTION
# ============================================================================

func _handle_collisions() -> void:
	"""Check collisions with player and other crocodiles."""
	# Check all collisions from move_and_slide()
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		if not collider:
			continue

		# Check if we hit the player
		if collider.is_in_group("player"):
			_on_player_collision(collider)
			return # Prioritize player collision
			
		# Check if we hit another crocodile
		if collider.is_in_group("crocodile") and collider != self:
			_resolve_crocodile_conflict(collider)
			if is_queued_for_deletion():
				return


func _resolve_crocodile_conflict(other_crocodile: Node) -> void:
	"""
	Handle collision with another crocodile.
	Randomly (but deterministically) decide which one survives.
	"""
	if is_queued_for_deletion() or other_crocodile.is_queued_for_deletion():
		return

	# Use instance IDs to deterministically decide a winner
	# This ensures consistency even if only one detects the collision
	var my_id = get_instance_id()
	var other_id = other_crocodile.get_instance_id()
	
	# Simple hash to pick a winner "randomly" but consistently for this pair
	var combined_hash = (my_id + other_id) * 12345
	var i_win = false
	
	if combined_hash % 2 == 0:
		# Even hash: Larger ID wins
		i_win = my_id > other_id
	else:
		# Odd hash: Smaller ID wins
		i_win = my_id < other_id
	
	if i_win:
		print("🐊 Crocodile %s ate %s!" % [name, other_crocodile.name])
		other_crocodile.queue_free()
	else:
		print("🐊 Crocodile %s was eaten by %s!" % [name, other_crocodile.name])
		queue_free()


func _on_player_collision(player: Node) -> void:
	"""Handle collision with the player (FATAL)."""
	print("💀 Piglet Crocodile collision! Player defeated!")

	# Reset player to spawn position
	if player.has_method("reset_position"):
		player.reset_position()
	else:
		# Fallback: move player up and away
		if player is Node3D:
			player.global_position = Vector3(0, 2, 0)

	# Optional: Add visual/audio feedback here
	# - Play death sound
	# - Show game over UI
	# - Spawn particle effect

	# Optional: Make the crocodile react (pause, animation, etc.)
	_pause_and_change_direction()


# ============================================================================
# UTILITY METHODS
# ============================================================================

func _to_string() -> String:
	"""Debug string representation."""
	return "PigletCrocodile(pos=%s, dir=%s, paused=%s)" % [
		global_position,
		movement_direction,
		is_paused
	]
