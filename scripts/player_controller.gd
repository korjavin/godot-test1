extends CharacterBody3D
## Player Controller Script
##
## This script controls the player character in a 3rd person perspective.
## It handles movement (walking, running), jumping, ducking, and camera control.
##
## EDUCATIONAL NOTES:
## - CharacterBody3D is Godot's built-in class for characters with physics
## - The velocity property is inherited from CharacterBody3D
## - We use Godot's physics engine to handle gravity and collisions

# ============================================================================
# SECTION 1: MOVEMENT SPEED CONSTANTS
# ============================================================================
# These constants define how fast the character moves in different states.
# Try adjusting these values to see how they affect gameplay!

## Normal walking speed in meters per second
const WALK_SPEED: float = 5.0

## Running speed when holding the run button (Shift)
## Note: This is 2x the walk speed for a noticeable difference
const RUN_SPEED: float = 10.0

## Speed when ducking (Ctrl)
## Note: Ducking is slower than walking for realism
const DUCK_SPEED: float = 2.5

# ============================================================================
# SECTION 2: JUMP AND PHYSICS CONSTANTS
# ============================================================================

## Jump velocity determines how high the character can jump
## Higher values = higher jumps
## Physics Note: This is the initial upward velocity when jumping
const JUMP_VELOCITY: float = 8.0

## Gravity value (meters per second squared)
## This matches Earth's gravity. The physics engine uses this to pull
## the character down when they're in the air.
## Try changing this to simulate different planets!
## - Moon: 1.6
## - Mars: 3.7
## - Earth: 9.8
## - Jupiter: 24.8
var gravity: float = 3.6

##  ProjectSettings.get_setting("physics/3d/default_gravity")

# ============================================================================
# SECTION 3: CAMERA AND ROTATION SETTINGS
# ============================================================================

## How fast the character rotates to face the movement direction
## Higher values = faster rotation (more responsive but less smooth)
## Lower values = slower rotation (smoother but less responsive)
const ROTATION_SPEED: float = 10.0

## Camera reference - we'll set this up in the scene
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

## Mouse sensitivity for camera rotation
const MOUSE_SENSITIVITY: float = 0.003

## Camera pitch limits (prevents camera from flipping over)
const CAMERA_PITCH_MIN: float = -60.0  # Looking down limit (degrees)
const CAMERA_PITCH_MAX: float = 60.0   # Looking up limit (degrees)

# ============================================================================
# SECTION 4: STATE VARIABLES
# ============================================================================

## Tracks if the player is currently ducking
var is_ducking: bool = false

## Tracks if the player is currently running
var is_running: bool = false

## Character's visual mesh (for ducking animation)
@onready var mesh_instance: Node3D = $MeshInstance3D

## Original height of the character (for ducking)
var original_scale_y: float = 1.0

# ============================================================================
# SECTION 5: CHARACTER SYSTEM
# ============================================================================

## Available characters in the game
const CHARACTERS: Array[Dictionary] = [
	{
		"name": "windman",
		"scene_path": "res://scenes/characters/windman_updated.tscn"
	},
	{
		"name": "primm",
		"scene_path": "res://scenes/characters/primm.tscn"
	},
	{
		"name": "teibi",
		"scene_path": "res://scenes/characters/teibi.tscn"
	},
	{
		"name": "phoboman",
		"scene_path": "res://scenes/characters/phoboman.tscn"
	}
]

## Current character index (starts with windman at index 0)
var current_character_index: int = 0

## Reference to the character model container
@onready var character_container: Node3D = $CharacterModel

## Currently loaded character instance
var current_character_node: Node3D = null

# ============================================================================
# SECTION 6: ANIMATION SYSTEM
# ============================================================================

## Animation timing variable (tracks time for procedural animations)
var animation_time: float = 0.0

## Animation speed multiplier for walking/running
var animation_speed: float = 1.0

## References to character limbs for animation
var left_arm: Node3D = null
var right_arm: Node3D = null
var left_leg: Node3D = null
var right_leg: Node3D = null
var character_body: Node3D = null

## Original rotations for resetting animations
var original_rotations: Dictionary = {}

## Track if character was on floor last frame (for landing detection)
var was_on_floor: bool = true

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	"""
	Called when the node enters the scene tree.
	This is where we do initial setup.
	"""
	# Capture the mouse so it doesn't leave the game window
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Store the original character height for ducking calculations
	if mesh_instance:
		original_scale_y = mesh_instance.scale.y

	# Initialize the starting character (windman)
	load_character(current_character_index)

	print("Player Controller initialized!")
	print("Controls:")
	print("  WASD - Move")
	print("  Space - Jump")
	print("  Shift - Run")
	print("  Ctrl - Duck")
	print("  E - Switch Character")
	print("  Mouse - Look around")
	print("  ESC - Release mouse")

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _input(event: InputEvent) -> void:
	"""
	Handles mouse input for camera rotation.
	This runs whenever an input event occurs.
	"""
	# Check if the mouse moved
	if event is InputEventMouseMotion:
		# Only rotate camera if mouse is captured
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			# Rotate the entire character body left/right (yaw)
			rotate_y(-event.relative.x * MOUSE_SENSITIVITY)

			# Rotate the camera pivot up/down (pitch)
			camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)

			# Clamp the camera pitch to prevent over-rotation
			var pitch = rad_to_deg(camera_pivot.rotation.x)
			pitch = clamp(pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
			camera_pivot.rotation.x = deg_to_rad(pitch)

	# Allow player to release mouse with ESC
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Handle character switching with E key
	if event.is_action_pressed("switch_character"):
		switch_to_next_character()

# ============================================================================
# PHYSICS PROCESSING (CALLED EVERY FRAME)
# ============================================================================

func _physics_process(delta: float) -> void:
	"""
	Called every physics frame (usually 60 times per second).
	This is where we handle movement and physics.

	@param delta: Time elapsed since last frame (in seconds)
	"""

	# STEP 1: Handle Gravity
	# If the character is not on the ground, apply gravity
	if not is_on_floor():
		# Add gravity to the vertical velocity
		# Note: We multiply by delta to make it frame-rate independent
		velocity.y -= gravity * delta

	# STEP 2: Handle Jumping
	# Check if jump button is pressed AND character is on the ground
	if Input.is_action_just_pressed("jump") and is_on_floor():
		# Set upward velocity for jump
		velocity.y = JUMP_VELOCITY

	# STEP 3: Handle Ducking
	handle_ducking()

	# STEP 4: Handle Running
	is_running = Input.is_action_pressed("run") and not is_ducking

	# STEP 5: Calculate Movement Direction
	var input_dir := get_input_direction()

	# STEP 6: Calculate Movement Speed
	var current_speed := calculate_current_speed()

	# STEP 7: Apply Movement
	if input_dir != Vector2.ZERO:
		# Convert 2D input to 3D direction based on character's rotation
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		# Set horizontal velocity (X and Z)
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		# No input: gradually slow down (friction)
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 10.0)

	# STEP 8: Move the character using Godot's built-in physics
	# This handles collisions automatically
	move_and_slide()

	# STEP 9: Update character animations
	update_character_animation(delta, input_dir)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func get_input_direction() -> Vector2:
	"""
	Reads keyboard input and returns a 2D movement direction vector.

	@return Vector2: Direction vector (normalized if moving diagonally)

	EDUCATIONAL NOTE:
	- Input.get_axis() returns a value between -1 and 1
	- This creates a 2D vector that we'll convert to 3D movement
	"""
	var input_x := Input.get_axis("move_left", "move_right")
	var input_y := Input.get_axis("move_forward", "move_backward")

	return Vector2(input_x, input_y)

func calculate_current_speed() -> float:
	"""
	Determines the current movement speed based on character state.

	@return float: Current speed in meters per second

	EDUCATIONAL NOTE:
	- We check states in priority order: duck > run > walk
	- Only one state can be active at a time
	"""
	if is_ducking:
		return DUCK_SPEED
	elif is_running:
		return RUN_SPEED
	else:
		return WALK_SPEED

func handle_ducking() -> void:
	"""
	Handles the ducking mechanic.

	EDUCATIONAL NOTE:
	- Ducking makes the character shorter by scaling the mesh
	- In a real game, you'd also shrink the collision shape
	- This is a visual-only implementation for learning purposes
	"""
	var target_scale_y: float = original_scale_y

	if Input.is_action_pressed("duck") and is_on_floor():
		is_ducking = true
		target_scale_y = original_scale_y * 0.5  # Duck to 50% height
	else:
		is_ducking = false
		target_scale_y = original_scale_y  # Return to normal height

	# Smoothly interpolate the scale for a nice ducking animation
	if mesh_instance:
		mesh_instance.scale.y = lerp(mesh_instance.scale.y, target_scale_y, 0.1)

# ============================================================================
# DEBUG AND UTILITY FUNCTIONS
# ============================================================================

func _to_string() -> String:
	"""
	Returns a string representation of the player's current state.
	Useful for debugging.
	"""
	return "Player[Speed: %s, OnFloor: %s, Velocity: %s]" % [
		calculate_current_speed(),
		is_on_floor(),
		velocity
	]

# ============================================================================
# CHARACTER SWITCHING FUNCTIONS
# ============================================================================

func switch_to_next_character() -> void:
	"""
	Switches to the next character in the cycle:
	windman -> primm -> teibi -> phoboman -> windman (loops)
	"""
	# Increment the character index
	current_character_index = (current_character_index + 1) % CHARACTERS.size()

	# Load the new character
	load_character(current_character_index)

	# Print confirmation
	var character_name = CHARACTERS[current_character_index]["name"]
	print("Switched to character: %s" % character_name)

func load_character(index: int) -> void:
	"""
	Loads a character's 3D model based on the index.

	@param index: Index in the CHARACTERS array
	"""
	if index < 0 or index >= CHARACTERS.size():
		push_error("Invalid character index: %d" % index)
		return

	var character_data = CHARACTERS[index]
	var scene_path = character_data["scene_path"]

	# Remove the old character if it exists
	if current_character_node != null:
		current_character_node.queue_free()
		current_character_node = null

	# Load the character scene
	var character_scene = load(scene_path) as PackedScene

	if character_scene and character_container:
		# Instance the new character
		current_character_node = character_scene.instantiate()
		character_container.add_child(current_character_node)

		# Setup animation references
		setup_animation_references()

		print("Loaded character: %s" % character_data["name"])
	else:
		push_error("Failed to load character scene or container node not found")

# ============================================================================
# ANIMATION FUNCTIONS
# ============================================================================

func setup_animation_references() -> void:
	"""
	Finds and stores references to character limbs for animation.
	Called when a new character is loaded.
	"""
	if not current_character_node:
		return

	# Find the Body node that contains all limbs
	character_body = current_character_node.get_node_or_null("Body")

	if not character_body:
		print("Warning: Character doesn't have a 'Body' node")
		return

	print("Body node found!")

	# Find limb nodes
	left_arm = character_body.get_node_or_null("LeftArm")
	right_arm = character_body.get_node_or_null("RightArm")
	left_leg = character_body.get_node_or_null("LeftLeg")
	right_leg = character_body.get_node_or_null("RightLeg")

	# Debug output
	print("  Limb nodes found:")
	print("    LeftArm: ", left_arm != null)
	print("    RightArm: ", right_arm != null)
	print("    LeftLeg: ", left_leg != null)
	print("    RightLeg: ", right_leg != null)

	# Store original rotations
	original_rotations.clear()
	if left_arm:
		original_rotations["left_arm"] = left_arm.rotation
	if right_arm:
		original_rotations["right_arm"] = right_arm.rotation
	if left_leg:
		original_rotations["left_leg"] = left_leg.rotation
	if right_leg:
		original_rotations["right_leg"] = right_leg.rotation
	if character_body:
		original_rotations["body"] = character_body.rotation

	print("Animation system initialized for character")

func update_character_animation(delta: float, input_dir: Vector2) -> void:
	"""
	Main animation update function. Determines which animation to play
	based on character state.

	@param delta: Time since last frame
	@param input_dir: Current input direction
	"""
	if not current_character_node or not character_body:
		return

	# Update animation time
	animation_time += delta

	# Determine animation state and animate accordingly
	var is_moving = input_dir.length() > 0.1
	var current_on_floor = is_on_floor()

	# Jump/Fall animation
	if not current_on_floor:
		animate_jumping()
	# Landing detected
	elif not was_on_floor and current_on_floor:
		animate_landing()
	# Walking/Running animation
	elif is_moving and current_on_floor:
		var speed_multiplier = 1.5 if is_running else 1.0
		animate_walking(delta, speed_multiplier)
	# Idle animation
	else:
		animate_idle(delta)

	# Update floor tracking
	was_on_floor = current_on_floor

func animate_walking(delta: float, speed_multiplier: float) -> void:
	"""
	Animates the character's limbs for walking/running.
	Arms and legs swing back and forth.

	@param delta: Time since last frame
	@param speed_multiplier: How fast to play the animation (1.0 = normal, 1.5 = running)
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Walking animation uses sine waves for smooth swinging motion
	var walk_speed = 8.0 * speed_multiplier
	var arm_swing_amount = deg_to_rad(30)  # 30 degrees swing
	var leg_swing_amount = deg_to_rad(40)  # 40 degrees swing

	# Calculate swing values using sine wave
	var time_factor = animation_time * walk_speed
	var arm_swing = sin(time_factor) * arm_swing_amount
	var leg_swing = sin(time_factor) * leg_swing_amount

	# Apply rotations (arms and legs swing opposite to each other)
	left_arm.rotation.x = original_rotations["left_arm"].x + arm_swing
	right_arm.rotation.x = original_rotations["right_arm"].x - arm_swing

	left_leg.rotation.x = original_rotations["left_leg"].x - leg_swing
	right_leg.rotation.x = original_rotations["right_leg"].x + leg_swing

	# Add slight body bob for realism
	if character_body:
		var bob_amount = 0.03
		var bob = sin(time_factor * 2.0) * bob_amount
		character_body.position.y = bob

func animate_jumping() -> void:
	"""
	Animates the character in mid-air (jumping or falling).
	Arms go up, legs come together.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Target pose for jumping
	var arm_up_angle = deg_to_rad(-45)  # Arms raised
	var leg_together_angle = deg_to_rad(10)  # Legs slightly bent

	# Smoothly interpolate to jump pose
	var lerp_speed = 0.15

	left_arm.rotation.x = lerp(left_arm.rotation.x, original_rotations["left_arm"].x + arm_up_angle, lerp_speed)
	right_arm.rotation.x = lerp(right_arm.rotation.x, original_rotations["right_arm"].x + arm_up_angle, lerp_speed)

	left_leg.rotation.x = lerp(left_leg.rotation.x, original_rotations["left_leg"].x + leg_together_angle, lerp_speed)
	right_leg.rotation.x = lerp(right_leg.rotation.x, original_rotations["right_leg"].x + leg_together_angle, lerp_speed)

	# Reset body position
	if character_body:
		character_body.position.y = lerp(character_body.position.y, 0.0, lerp_speed)

func animate_landing() -> void:
	"""
	Brief animation when the character lands on the ground.
	Creates a small impact pose.
	"""
	if not character_body:
		return

	# Small crouch on landing
	character_body.position.y = -0.1

func animate_idle(delta: float) -> void:
	"""
	Animates the character when standing still.
	Creates a subtle breathing/idle motion.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Smoothly return limbs to original positions
	var lerp_speed = 0.1

	left_arm.rotation.x = lerp(left_arm.rotation.x, original_rotations["left_arm"].x, lerp_speed)
	right_arm.rotation.x = lerp(right_arm.rotation.x, original_rotations["right_arm"].x, lerp_speed)

	left_leg.rotation.x = lerp(left_leg.rotation.x, original_rotations["left_leg"].x, lerp_speed)
	right_leg.rotation.x = lerp(right_leg.rotation.x, original_rotations["right_leg"].x, lerp_speed)

	# Subtle breathing animation
	if character_body:
		var breathe_speed = 2.0
		var breathe_amount = 0.01
		var breathe = sin(animation_time * breathe_speed) * breathe_amount
		character_body.position.y = lerp(character_body.position.y, breathe, 0.1)

# ============================================================================
# SECTION 7: GAME STATE METHODS
# ============================================================================

func reset_position() -> void:
	"""
	Reset the player to the spawn position.
	Called when the player dies (e.g., hit by a crocodile).
	"""
	# Reset position to spawn point
	global_position = Vector3(0, 2, 0)

	# Reset velocity to prevent carrying momentum
	velocity = Vector3.ZERO

	# Reset camera and character rotation to default
	rotation.y = 0.0  # Reset character horizontal rotation
	if camera_pivot:
		camera_pivot.rotation.x = 0.0  # Reset camera vertical rotation
		camera_pivot.rotation.y = 0.0  # Reset camera horizontal rotation

	# Reset character state
	is_ducking = false
	is_running = false

	print("Player position reset - respawned at spawn point")
