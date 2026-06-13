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

## How fast A / D rotate the character, in radians per second.
## A and D no longer strafe — they turn the body (tank-style steering), so
## whatever way the character ends up facing is the way W will walk.
const TURN_SPEED: float = 2.6

## Sidestep ("step aside") tuning for Q / E.
## A step is a short, self-contained burst sideways: STEP_SPEED for STEP_DURATION
## seconds, so the character slides about STEP_SPEED * STEP_DURATION metres over.
const STEP_SPEED: float = 5.5
const STEP_DURATION: float = 0.28

# ============================================================================
# SECTION 2: JUMP AND PHYSICS CONSTANTS
# ============================================================================

## Jump velocity determines how high the character can jump
## Higher values = higher jumps
## Physics Note: This is the initial upward velocity when jumping.
## Apex height scales with the SQUARE of this. With gravity = 3.6 the apex is
## about JUMP_VELOCITY^2 / (2 * gravity): 5.1 -> ~3.6 m. Single blocks top out at
## 2.5 m and structures are climbed in <=3 m steps, so everything stays jumpable.
const JUMP_VELOCITY: float = 5.1

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

## Safe spawn radius - crocodiles within this distance will be removed on respawn
const SPAWN_SAFE_RADIUS: float = 25.0

# ============================================================================
# SECTION 4: STATE VARIABLES
# ============================================================================

## Tracks if the player is currently ducking
var is_ducking: bool = false

## Tracks if the player is currently running
var is_running: bool = false

## Sidestep state. While a "step aside" is playing we slide sideways for a short
## burst and run a matching leg animation; new step requests are ignored until it
## finishes so taps don't stack into a long slide.
var is_stepping: bool = false
## Seconds left in the current sidestep (counts down to 0).
var step_timer: float = 0.0
## Direction of the current sidestep in the character's local space:
## -1 = stepping left (Q), +1 = stepping right (E).
var step_direction: float = 0.0

## How many golden coins the player has collected. The HUD reads this, and it is
## reset to 0 whenever the player is caught by a crocodile (see reset_position).
var coins_collected: int = 0

## "Caught" sequence: when a crocodile bites the player we freeze briefly (so the
## bite is actually visible), flash the screen red and shake the camera, then
## respawn. These track that short window.
var is_caught: bool = false
var caught_timer: float = 0.0
const CAUGHT_DURATION: float = 0.55

## Camera shake, used by the crocodile-bite hit effect. Decays back to 0.
var shake_amount: float = 0.0
const SHAKE_MAX: float = 0.25
const SHAKE_DECAY: float = 1.0
## Resting local position of the camera, so shake can offset from it and restore.
var camera_rest_position: Vector3 = Vector3.ZERO

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

## All character models, instanced once up front and reused. Switching characters
## just toggles which one is visible, so there is no per-press load/instance cost
## (which is what used to cause the hitch when pressing E).
var character_instances: Array[Node3D] = []

## Cached neutral limb rotations for each character, captured at startup while the
## model is in its untouched rest pose. Restoring from this on activation means a
## character never resumes from a frozen mid-animation pose after being hidden.
var character_rest_poses: Array[Dictionary] = []

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

## Shared cel-shading outline, created once and reused for every character.
## Applied as a material overlay so it works on any mesh — both the primitive
## characters and the GLB-based windman — without touching their own materials.
const OUTLINE_SHADER: Shader = preload("res://assets/shaders/outline.gdshader")
var outline_material: ShaderMaterial = null

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

	# Instance every character once up front, then show the starting one (windman).
	# Pre-instancing here keeps later character switches instant.
	preload_all_characters()
	set_active_character(current_character_index)

	# Remember the camera's resting spot so the hit-shake can offset from it.
	if camera:
		camera_rest_position = camera.position

	print("Player Controller initialized!")
	print("Controls:")
	print("  W / S - Walk forward / back")
	print("  A / D - Turn left / right")
	print("  Q / E - Step aside left / right")
	print("  Space - Jump")
	print("  Shift - Run")
	print("  Ctrl - Duck")
	print("  R - Switch Character")
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

	# STEP 0: If a crocodile just caught us, freeze in place and let the bite +
	# red flash play out for a moment, then respawn. We skip all normal input and
	# movement while this short "caught" window runs.
	if is_caught:
		velocity = Vector3.ZERO
		move_and_slide()
		update_character_animation(delta, Vector2.ZERO)
		caught_timer -= delta
		if caught_timer <= 0.0:
			is_caught = false
			reset_position()
		return

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

	# STEP 5: Turn the character with A / D (changes which way it faces)
	handle_turning(delta)

	# STEP 6: Advance any in-progress sidestep, and start a new one on Q / E
	update_sidestep(delta)

	# STEP 7: Read forward/back input and the current movement speed
	var input_dir := get_input_direction()
	var current_speed := calculate_current_speed()

	# STEP 8: Build this frame's horizontal velocity from two sources:
	#   - forward/back walking in the direction the character faces (W/S), and
	#   - a quick lateral burst while a sidestep is active (Q/E).
	# Both are expressed in the character's local space, then rotated into the
	# world by transform.basis, so they always follow the current facing.
	var planar_velocity := Vector3.ZERO

	if absf(input_dir.y) > 0.01:
		var forward_dir := (transform.basis * Vector3(0.0, 0.0, input_dir.y)).normalized()
		planar_velocity += forward_dir * current_speed

	if is_stepping:
		var step_dir := (transform.basis * Vector3(step_direction, 0.0, 0.0)).normalized()
		planar_velocity += step_dir * STEP_SPEED

	if planar_velocity != Vector3.ZERO:
		# Set horizontal velocity (X and Z)
		velocity.x = planar_velocity.x
		velocity.z = planar_velocity.z
	else:
		# No input: gradually slow down (friction)
		velocity.x = move_toward(velocity.x, 0, current_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, current_speed * delta * 10.0)

	# STEP 9: Move the character using Godot's built-in physics
	# This handles collisions automatically
	move_and_slide()

	# STEP 10: Update character animations
	update_character_animation(delta, input_dir)

func _process(delta: float) -> void:
	"""
	Per-frame visual updates that don't belong in the physics step. Right now this
	is just the camera shake from being bitten — it offsets the camera by a small
	random amount that decays back to zero.
	"""
	if not camera:
		return

	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - SHAKE_DECAY * delta)
		camera.position = camera_rest_position + Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			0.0
		) * shake_amount
	elif camera.position != camera_rest_position:
		# Settle exactly back to rest once the shake is done.
		camera.position = camera_rest_position

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

func get_input_direction() -> Vector2:
	"""
	Reads forward/back keyboard input and returns it as a 2D direction vector.

	@return Vector2: x is always 0 (A/D now turn the body instead of strafing),
	                 y is the forward/back axis from W/S.

	EDUCATIONAL NOTE:
	- Input.get_axis() returns a value between -1 and 1.
	- Sideways movement is no longer continuous here: A/D rotate the character
	  (see handle_turning) and Q/E fire a one-off sidestep (see update_sidestep).
	"""
	var input_y := Input.get_axis("move_forward", "move_backward")

	return Vector2(0.0, input_y)

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

func handle_turning(delta: float) -> void:
	"""
	Rotate the whole character left/right with A and D.

	A and D no longer strafe — they change which way the character is *facing*,
	like the tank-style steering in classic adventure games. Whatever direction
	the body ends up pointing is the direction W will walk. (The mouse can still
	turn the body too; the two just add together.)

	@param delta: Time since last frame, so the turn rate is frame-rate independent
	"""
	# +1 when turning left (A), -1 when turning right (D).
	var turn_input := Input.get_axis("turn_right", "turn_left")
	if absf(turn_input) > 0.01:
		# A positive angle spins counter-clockwise around +Y, i.e. to the
		# character's left — which matches A producing a positive turn_input.
		rotate_y(turn_input * TURN_SPEED * delta)

func update_sidestep(delta: float) -> void:
	"""
	Manage the quick "step aside" triggered by Q (left) and E (right).

	A step is short and self-contained: press once and the character slides about
	one step sideways while the legs play a matching side-step animation. We
	ignore new requests until the current step finishes, so tapping doesn't stack
	into a long continuous slide.

	@param delta: Time since last frame
	"""
	# Tick down a step that's already in progress.
	if is_stepping:
		step_timer -= delta
		if step_timer <= 0.0:
			# Step done: clear the state and unwind the side-step pose so the
			# next idle/walk frame starts from a clean rest pose.
			is_stepping = false
			step_timer = 0.0
			reset_sidestep_pose()
		return

	# Only start a new step while grounded — no air-stepping.
	if not is_on_floor():
		return

	if Input.is_action_just_pressed("step_left"):
		start_sidestep(-1.0)
	elif Input.is_action_just_pressed("step_right"):
		start_sidestep(1.0)

func start_sidestep(direction: float) -> void:
	"""
	Begin a sidestep in the character's local space.

	@param direction: -1.0 = step left (Q), +1.0 = step right (E)
	"""
	is_stepping = true
	step_timer = STEP_DURATION
	step_direction = direction

func reset_sidestep_pose() -> void:
	"""
	Return the limb/body roll used by the sidestep back to their rest values.

	The sidestep is the only animation that touches the Z (roll) rotation, so the
	walk/idle animations never put it back on their own. We snap it here when a
	step ends so a finished step never leaves the legs slightly splayed.
	"""
	if left_arm and original_rotations.has("left_arm"):
		left_arm.rotation.z = original_rotations["left_arm"].z
	if right_arm and original_rotations.has("right_arm"):
		right_arm.rotation.z = original_rotations["right_arm"].z
	if left_leg and original_rotations.has("left_leg"):
		left_leg.rotation.z = original_rotations["left_leg"].z
	if right_leg and original_rotations.has("right_leg"):
		right_leg.rotation.z = original_rotations["right_leg"].z
	if character_body and original_rotations.has("body"):
		character_body.rotation.z = original_rotations["body"].z

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

	This is now just a visibility swap between already-instanced models, so it
	happens instantly with no loading hitch.
	"""
	# Increment the character index
	current_character_index = (current_character_index + 1) % CHARACTERS.size()

	# Show the newly selected character
	set_active_character(current_character_index)

	# Print confirmation
	print("Switched to character: %s" % CHARACTERS[current_character_index]["name"])

func preload_all_characters() -> void:
	"""
	Instance all characters a single time and park them (hidden) under the
	character container.

	Doing the expensive load + instance + outline work here, once at startup,
	means switching characters later (set_active_character) is just a visibility
	toggle. That removes the per-press hitch that used to come from re-loading
	and re-instancing a model — especially windman, which is 11 separate meshes.
	"""
	if not character_container:
		push_error("Character container node not found")
		return

	for index in CHARACTERS.size():
		var scene_path: String = CHARACTERS[index]["scene_path"]
		var character_scene := load(scene_path) as PackedScene
		if not character_scene:
			push_error("Failed to load character scene: %s" % scene_path)
			character_instances.append(null)
			character_rest_poses.append({})
			continue

		# Instance it, hide it, and add it to the container.
		var instance := character_scene.instantiate()
		character_container.add_child(instance)
		instance.visible = false

		# Give it the cel-shaded style (outline + toon/rim) and remember its rest
		# pose while limbs are still untouched (so re-activation never drifts it).
		apply_character_style(instance)
		character_instances.append(instance)
		character_rest_poses.append(capture_rest_pose(instance))

		print("Preloaded character: %s" % CHARACTERS[index]["name"])

func set_active_character(index: int) -> void:
	"""
	Make one preloaded character visible and route the animation system to it.
	Switching is instant because every character already exists in the tree.

	@param index: Index in the CHARACTERS array
	"""
	if index < 0 or index >= character_instances.size():
		push_error("Invalid character index: %d" % index)
		return

	current_character_index = index

	# Show only the chosen character; hide the rest.
	for i in character_instances.size():
		if character_instances[i]:
			character_instances[i].visible = (i == index)

	current_character_node = character_instances[index]
	if not current_character_node:
		return

	# Point the animation system at this character, then snap it back to its
	# cached rest pose so it never resumes from a frozen mid-animation pose.
	setup_animation_references()
	original_rotations = character_rest_poses[index].duplicate()
	restore_rest_pose(index)

func capture_rest_pose(instance: Node3D) -> Dictionary:
	"""
	Record a character's limb rotations while it sits in its untouched rest pose.
	Keys match those used by the animation functions (left_arm, right_leg, ...).

	@param instance: A freshly-instanced character model
	@return Dictionary of limb name -> rest rotation
	"""
	var pose: Dictionary = {}
	var body := instance.get_node_or_null("Body")
	if not body:
		return pose

	pose["body"] = body.rotation
	var limb_keys := {
		"left_arm": "LeftArm", "right_arm": "RightArm",
		"left_leg": "LeftLeg", "right_leg": "RightLeg",
	}
	for key in limb_keys:
		var limb := body.get_node_or_null(limb_keys[key])
		if limb:
			pose[key] = limb.rotation
	return pose

func restore_rest_pose(index: int) -> void:
	"""
	Snap the active character's limbs (and body) back to their cached rest pose.

	@param index: Index in the CHARACTERS array
	"""
	var pose: Dictionary = character_rest_poses[index]
	if left_arm and pose.has("left_arm"):
		left_arm.rotation = pose["left_arm"]
	if right_arm and pose.has("right_arm"):
		right_arm.rotation = pose["right_arm"]
	if left_leg and pose.has("left_leg"):
		left_leg.rotation = pose["left_leg"]
	if right_leg and pose.has("right_leg"):
		right_leg.rotation = pose["right_leg"]
	if character_body and pose.has("body"):
		character_body.rotation = pose["body"]
		character_body.position.y = 0.0

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

func apply_character_style(node: Node) -> void:
	"""
	Recursively give every mesh in the character its cel-shaded look:
	  - a shared inverted-hull outline as a material overlay, and
	  - soft toon diffuse + rim light on each surface material.

	Walking the tree covers both the primitive-built characters AND the nested
	meshes inside the GLB-based windman, in one place. The primitive characters
	already declare toon shading in their scene files, so apply_toon_shading only
	upgrades materials that aren't toon yet (windman's baked GLB materials) and
	leaves the others exactly as authored.

	@param node: Root of the character subtree to style
	"""
	# Build the shared outline material the first time we need it.
	if outline_material == null:
		outline_material = ShaderMaterial.new()
		outline_material.shader = OUTLINE_SHADER

	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.material_overlay = outline_material
		apply_toon_shading(mesh)

	for child in node.get_children():
		apply_character_style(child)

func apply_toon_shading(mesh: MeshInstance3D) -> void:
	"""
	Add soft toon diffuse + rim light to a mesh's materials, matching the look
	the primitive characters get from their scene files. We duplicate each
	material first so we only ADD shading and never lose the baked albedo or
	textures — important for windman, whose colours live in its GLB materials.

	Materials that are already toon (the primitive characters) are skipped.

	@param mesh: The mesh whose surface materials should be cel-shaded
	"""
	for surface in mesh.get_surface_override_material_count():
		var mat := mesh.get_active_material(surface)
		if mat is BaseMaterial3D and mat.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
			var styled := mat.duplicate() as BaseMaterial3D
			styled.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			styled.rim_enabled = true
			styled.rim = 0.4
			styled.rim_tint = 0.25
			mesh.set_surface_override_material(surface, styled)

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
	# Sidestep takes priority on the ground so the legs read the side motion
	elif is_stepping:
		animate_sidestep()
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

func animate_sidestep() -> void:
	"""
	Animate the legs (and arms) for a sideways "step aside".

	The step runs over STEP_DURATION. We turn the time remaining into a 0 -> 1
	progress value, then feed it through sin() to get a smooth arc that is 0 at
	the start, peaks mid-step, and returns to 0 as the foot plants. Driving the
	pose off that arc means the legs splay out toward the step direction and come
	back together on their own — and because the arc is 0 at the end, the pose
	lands exactly on the rest pose.

	Unlike walking (which swings the limbs forward/back on the X axis), the
	sidestep rolls them on the Z axis so the motion reads as sideways.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# 0.0 at the start of the step, 1.0 at the very end.
	var progress := 1.0 - clampf(step_timer / STEP_DURATION, 0.0, 1.0)
	# Smooth arc: 0 -> 1 (mid-step) -> 0 (foot plants).
	var arc := sin(progress * PI)

	# How far the legs splay sideways, and the extra lift on the leading leg.
	var leg_splay := step_direction * arc * deg_to_rad(28)
	var lead_lift := step_direction * arc * deg_to_rad(14)
	# Arms counter-swing for balance.
	var arm_balance := step_direction * arc * deg_to_rad(20)

	# Both legs lean toward the step; the leading leg (on the step side) lifts a
	# touch more so the step reads as one foot reaching out and the other following.
	left_leg.rotation.z = original_rotations["left_leg"].z + leg_splay
	right_leg.rotation.z = original_rotations["right_leg"].z + leg_splay
	if step_direction > 0.0:
		right_leg.rotation.z += lead_lift
	else:
		left_leg.rotation.z += lead_lift

	left_arm.rotation.z = original_rotations["left_arm"].z - arm_balance
	right_arm.rotation.z = original_rotations["right_arm"].z - arm_balance

	# Lean the body into the step direction for a bit of weight shift.
	if character_body:
		character_body.rotation.z = original_rotations["body"].z - step_direction * arc * deg_to_rad(8)
		character_body.position.y = 0.0

func animate_jumping() -> void:
	"""
	Animate the character in mid-air: they throw their arms out to the sides and
	FLAP them like wings, as if trying to take off, while the legs tuck together.

	Walking swings the limbs forward/back on the X axis; the wing flap rolls the
	arms on the Z axis instead, so it never fights the walk pose. We set the arm
	roll directly (rather than easing toward it) so the flap stays crisp, and
	mirror the two arms with opposite signs so they spread and beat together.
	animate_landing() drops the wings back down on touchdown.
	"""
	if not left_arm or not right_arm or not left_leg or not right_leg:
		return

	# Continuous wing beat while airborne.
	var flap_speed = 14.0
	var flap = sin(animation_time * flap_speed)

	# Base spread (arms out toward horizontal) with the flap added on top. The
	# right arm rolls toward +X and the left toward -X, so they mirror each other.
	var wing_spread = deg_to_rad(72)
	var flap_range = deg_to_rad(22)
	var wing_angle = wing_spread + flap * flap_range

	right_arm.rotation.z = original_rotations["right_arm"].z + wing_angle
	left_arm.rotation.z = original_rotations["left_arm"].z - wing_angle
	# Clear any leftover forward/back swing from walking so the wings sit level.
	right_arm.rotation.x = original_rotations["right_arm"].x
	left_arm.rotation.x = original_rotations["left_arm"].x

	# Tuck the legs slightly together underneath.
	var leg_together_angle = deg_to_rad(10)
	var lerp_speed = 0.2
	left_leg.rotation.x = lerp(left_leg.rotation.x, original_rotations["left_leg"].x + leg_together_angle, lerp_speed)
	right_leg.rotation.x = lerp(right_leg.rotation.x, original_rotations["right_leg"].x + leg_together_angle, lerp_speed)

	# Reset body position
	if character_body:
		character_body.position.y = lerp(character_body.position.y, 0.0, lerp_speed)

func animate_landing() -> void:
	"""
	Brief animation when the character lands on the ground.
	Creates a small impact pose and lowers the wings back to rest.
	"""
	if not character_body:
		return

	# Small crouch on landing
	character_body.position.y = -0.1

	# Drop the wings (arm roll) back to the sides now that we're grounded. The
	# walk/idle animations only drive the X axis, so without this the arms would
	# stay spread out after touchdown.
	if left_arm and original_rotations.has("left_arm"):
		left_arm.rotation.z = original_rotations["left_arm"].z
	if right_arm and original_rotations.has("right_arm"):
		right_arm.rotation.z = original_rotations["right_arm"].z

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

func collect_coin() -> void:
	"""
	Add one to the coin count. Called by a coin's Area3D when the player touches
	it (see coin.gd). The HUD picks up the new value on its next frame.
	"""
	coins_collected += 1
	print("Collected a coin! Total: %d" % coins_collected)


func hit_by_crocodile() -> void:
	"""
	Called by a crocodile when it bites the player (see piglet_crocodile_ai.gd).

	Rather than teleporting away instantly, we play a clear "caught" signal: a red
	screen flash, a camera shake, and a brief freeze (handled in _physics_process)
	so the bite is actually visible. reset_position() — which also clears the coin
	count — runs at the end of that short window.
	"""
	if is_caught:
		return
	is_caught = true
	caught_timer = CAUGHT_DURATION

	# Pop the red full-screen flash (found via group, so the HUD isn't hard-wired).
	var flash := get_tree().get_first_node_in_group("hit_flash")
	if flash and flash.has_method("flash"):
		flash.flash()

	# Kick off the camera shake.
	shake_amount = SHAKE_MAX


func reset_position() -> void:
	"""
	Reset the player to the spawn position.
	Called when the player dies (e.g., hit by a crocodile).
	"""
	# Define spawn point
	var spawn_point = Vector3(0, 2, 0)

	# Getting caught by a crocodile costs you all your coins.
	coins_collected = 0

	# Clear any crocodiles near the spawn point
	clear_nearby_crocodiles(spawn_point)

	# Reset position to spawn point
	global_position = spawn_point

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


func clear_nearby_crocodiles(spawn_point: Vector3) -> void:
	"""
	Remove all crocodiles within SPAWN_SAFE_RADIUS of the spawn point.
	Prevents instant death after respawning.

	@param spawn_point: The position to check distance from
	"""
	var crocodiles = get_tree().get_nodes_in_group("crocodile")
	var removed_count = 0

	for crocodile in crocodiles:
		if crocodile is Node3D:
			var distance = spawn_point.distance_to(crocodile.global_position)
			if distance <= SPAWN_SAFE_RADIUS:
				crocodile.queue_free()
				removed_count += 1

	if removed_count > 0:
		print("Cleared %d crocodile(s) near spawn point" % removed_count)
