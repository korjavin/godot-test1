extends CharacterBody3D
## Piglet Crocodile NPC AI
##
## This script controls the behavior of hostile piglet crocodiles.
## They wander randomly and are fatal to the player on collision.
##
## Behavior:
## - Random wandering with periodic direction changes
## - Slow to medium movement speed
## - Fatal collision with player (resets player position)

# ============================================================================
# CONSTANTS
# ============================================================================

## Movement speed in meters per second
const MOVE_SPEED: float = 2.5

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

	# Update direction change timer
	time_since_direction_change += delta
	if time_since_direction_change >= DIRECTION_CHANGE_INTERVAL:
		_pause_and_change_direction()

	# Apply movement
	velocity.x = movement_direction.x * MOVE_SPEED
	velocity.z = movement_direction.z * MOVE_SPEED

	# Rotate to face movement direction
	if movement_direction.length() > 0.1:
		var target_rotation = atan2(movement_direction.x, movement_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)

	# Move and handle collisions
	move_and_slide()

	# Check for player collision
	_check_player_collision()


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

func _check_player_collision() -> void:
	"""Check if we've collided with the player and handle it."""
	# Check all collisions from move_and_slide()
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		# Check if we hit the player
		if collider and collider.is_in_group("player"):
			_on_player_collision(collider)
			return


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
