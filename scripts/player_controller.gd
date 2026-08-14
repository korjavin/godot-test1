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

## How many golden coins the player has collected. The HUD reads this. Coins now
## survive a crocodile bite (we only lose a life); they are reset to 0 only on a
## full restart from the Game Over screen (see restart_game / reset_position).
var coins_collected: int = 0

## "Caught" sequence: when a crocodile bites the player we freeze briefly (so the
## bite is actually visible), flash the screen red and shake the camera, then
## respawn. These track that short window.
var is_caught: bool = false
var caught_timer: float = 0.0
const CAUGHT_DURATION: float = 0.55

## Lives / game-over state. The player starts each run with MAX_LIVES; every
## crocodile bite costs one. While lives remain we respawn *in place* (keeping all
## coins) after a short grace window; when they run out we show the Game Over
## screen and freeze until the player restarts. The hearts HUD reads `lives`.
const MAX_LIVES: int = 3
var lives: int = MAX_LIVES
var is_game_over: bool = false

## Post-respawn grace: after losing a life we stand frozen and invulnerable for
## RESPAWN_GRACE_DURATION seconds (with crocodiles swept out of the area) before
## control returns, so a wandering crocodile can't bite us the instant we recover.
var is_respawning: bool = false
var respawn_timer: float = 0.0
const RESPAWN_GRACE_DURATION: float = 5.0

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

## Player collision capsule. Teibi's resize ability scales this (and the visible
## model) up and down; we cache its rest position and half-height so the capsule's
## BOTTOM can be pinned to the ground at any size — the player never sinks into the
## floor or gets launched when growing or shrinking.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var collision_base_y: float = 1.0
var collision_half_height: float = 1.0

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
	# Capture the mouse so it doesn't leave the game window — but ONLY when this is NOT
	# a touch session. On a phone/tablet the mobile controls are active and there is no
	# mouse to capture; requesting pointer-lock there would pop a useless permission
	# prompt and can leave the page in a weird captured state. So we skip the capture
	# on a touch session, leaving the cursor visible for the on-screen touch buttons.
	#
	# CANONICAL DETECTION (the fix): we ask `MobileSensors.is_touch_session()` — the
	# SAME static rule the touch UI (`touch_controls._is_touch_device()`) uses — instead
	# of the narrower `DisplayServer.is_touchscreen_available()`. Previously the UI could
	# decide "mobile" (via the web coarse-pointer check) while this guard still captured
	# the mouse, an inconsistency on web phones that report no Godot touchscreen.
	#
	# DESKTOP SAFETY: on a native desktop build (no touchscreen, not web) the static func
	# returns false WITHOUT touching JavaScriptBridge, so mouse capture happens exactly as
	# before — desktop keyboard+mouse play is byte-for-byte unchanged. (Mobile-motion plan.)
	if not MobileSensors.is_touch_session():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Store the original character height for ducking calculations
	if mesh_instance:
		original_scale_y = mesh_instance.scale.y

	# Cache the collision capsule's rest pose so Teibi's resize ability can keep the
	# capsule grounded at any scale, and give every character its own cooldown slot.
	if collision_shape:
		collision_base_y = collision_shape.position.y
		if collision_shape.shape is CapsuleShape3D:
			collision_half_height = (collision_shape.shape as CapsuleShape3D).height * 0.5
	ability_cooldowns.resize(CHARACTERS.size())
	ability_cooldowns.fill(0.0)

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
	print("  F - Special ability (unique per character)")
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

	# Allow player to release mouse with ESC.
	# TOUCH-SESSION GUARD: on a phone/tablet we deliberately keep the mouse VISIBLE so
	# the on-screen touch buttons are usable and no pointer-lock prompt appears (matching
	# the same `MobileSensors.is_touch_session()` gate used by the mouse-capture sites in
	# `_ready()`/`restart_game()`). Without this guard, ESC's unconditional toggle could
	# re-capture the mouse in a touch session, bypassing that single source of truth. So
	# on a touch session ESC only ever moves TOWARD visible (never into captured); on
	# desktop (non-touch) the original capture<->visible toggle is byte-for-byte unchanged.
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif not MobileSensors.is_touch_session():
			# Desktop only: re-capture on a second ESC. A touch session never re-captures.
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

	# STEP 0a: Game over — out of lives. Stand frozen (the Game Over screen is up
	# and the cursor is free) until the player hits "Play Again", which calls
	# restart_game(). We still settle under gravity so we don't hang in the air.
	if is_game_over:
		_freeze_with_gravity(delta)
		update_character_animation(delta, Vector2.ZERO)
		return

	# STEP 0b: If a crocodile just caught us, freeze in place and let the bite +
	# red flash play out for a moment. When the window ends we lose a life and
	# either respawn in place or, if that was our last life, trigger game over.
	if is_caught:
		velocity = Vector3.ZERO
		move_and_slide()
		update_character_animation(delta, Vector2.ZERO)
		caught_timer -= delta
		if caught_timer <= 0.0:
			is_caught = false
			_on_caught_finished()
		return

	# STEP 0c: Post-respawn grace. We keep standing still and invulnerable (see
	# hit_by_crocodile) while a short countdown runs, then hand control back. A
	# final crocodile sweep on the last frame keeps the resume spot clear.
	if is_respawning:
		_freeze_with_gravity(delta)
		update_character_animation(delta, Vector2.ZERO)
		respawn_timer -= delta
		_show_respawn_countdown()
		if respawn_timer <= 0.0:
			is_respawning = false
			_hide_respawn_message()
			clear_nearby_crocodiles(global_position)
		return

	# STEP 0.5: Tick ability cooldowns / the Windman air boost, then read the F key.
	# Done before gravity so an active boost can soften this frame's fall.
	_update_ability_timers(delta)
	if Input.is_action_just_pressed("special_ability"):
		try_activate_ability()

	# STEP 1: Handle Gravity
	# If the character is not on the ground, apply gravity. While Windman's Air Rush
	# is active we soften gravity so he glides and soars on the wind instead of
	# dropping like a stone.
	if not is_on_floor():
		var frame_gravity := gravity
		if windman_boost_timer > 0.0:
			frame_gravity *= WINDMAN_GRAVITY_FACTOR
		# Note: We multiply by delta to make it frame-rate independent
		velocity.y -= frame_gravity * delta

	# STEP 2: Handle Jumping
	# Check if jump button is pressed AND character is on the ground. Giant Teibi
	# is too heavy to leave the ground, so he can't jump while transformed.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_giant:
		# Set upward velocity for jump
		velocity.y = JUMP_VELOCITY
		# Jump sound (null-safe group lookup, like the hit_flash pattern).
		var sm := get_tree().get_first_node_in_group("sound_manager")
		if sm and sm.has_method("play_jump"):
			sm.play_jump()

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
	- We check states in priority order: air-rush > duck > run > walk
	- Only one state can be active at a time
	"""
	# Windman's Air Rush overrides everything while he is airborne — a wind-fast
	# flight through the sky (~5× walk speed, "Shift pressed five times over").
	if windman_boost_timer > 0.0 and not is_on_floor():
		return WINDMAN_AIR_SPEED

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
	# Block switching while a prolonged ability (flying/resize) is active
	if windman_boost_timer > 0.0 or teibi_size_state != 0:
		return

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

	# A freshly selected character always starts at normal size with no giant
	# crush — Teibi's resize state must not carry across a switch (otherwise a
	# different character could inherit Teibi's giant body or shrunken capsule).
	_revert_teibi_to_normal()

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
		# Landing thud (null-safe group lookup).
		var sm := get_tree().get_first_node_in_group("sound_manager")
		if sm and sm.has_method("play_land"):
			sm.play_land()
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
	screen flash, a camera shake, and a brief freeze (handled in _physics_process).
	When that window ends _on_caught_finished() spends a life and either respawns
	us in place or ends the run.

	Bites are ignored while we are already caught, inside the post-respawn grace
	window, or on the game-over screen — those three states make us invulnerable.
	"""
	if is_caught or is_respawning or is_game_over:
		return
	is_caught = true
	caught_timer = CAUGHT_DURATION

	# Bite sting (null-safe group lookup, like the hit_flash below).
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_bite"):
		sm.play_bite()

	# Pop the red full-screen flash (found via group, so the HUD isn't hard-wired).
	var flash := get_tree().get_first_node_in_group("hit_flash")
	if flash and flash.has_method("flash"):
		flash.flash()

	# Kick off the camera shake.
	shake_amount = SHAKE_MAX


func _on_caught_finished() -> void:
	"""
	Called once the "caught" freeze ends. One bite costs one life; from there we
	either respawn in place (lives left) or end the run (no lives left).
	"""
	lives -= 1
	print("Caught! Lives remaining: %d" % lives)
	if lives <= 0:
		lives = 0
		_trigger_game_over()
	else:
		_respawn_in_place()


func _respawn_in_place() -> void:
	"""
	Soft respawn after a bite: stay exactly where we fell and keep every coin —
	the only penalty is the lost life. We sweep crocodiles out of the immediate
	area and start a short, frozen grace window (see the is_respawning branch in
	_physics_process) so we can't be re-bitten the moment we recover. Any active
	ability state (air boost, giant/small form) is also cleared.
	"""
	_reset_ability_states()
	clear_nearby_crocodiles(global_position)
	velocity = Vector3.ZERO
	is_ducking = false
	is_running = false
	is_respawning = true
	respawn_timer = RESPAWN_GRACE_DURATION


func _trigger_game_over() -> void:
	"""
	Out of lives: freeze the player, free the mouse cursor so the player can click
	the button, and raise the Game Over screen (found via group) with the final
	coin tally.
	"""
	is_game_over = true
	velocity = Vector3.ZERO
	_reset_ability_states()
	_hide_respawn_message()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Game-over sting (null-safe group lookup).
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("play_game_over"):
		sm.play_game_over()

	var panel := get_tree().get_first_node_in_group("game_over_ui")
	if panel and panel.has_method("show_game_over"):
		panel.show_game_over(coins_collected)
	print("Game over! Final coins: %d" % coins_collected)


func restart_game() -> void:
	"""
	Start a brand-new run. Called by the Game Over screen's "Play Again" button.
	Everything resets: coins to 0, lives back to full, and the player is sent to
	the origin spawn with the mouse recaptured.
	"""
	coins_collected = 0
	lives = MAX_LIVES
	is_game_over = false
	is_caught = false
	is_respawning = false
	_hide_respawn_message()
	reset_position()
	# Recapture the mouse — but ONLY when this is NOT a touch session, mirroring the
	# `_ready()` guard via the SAME canonical `MobileSensors.is_touch_session()` rule.
	# "Play Again" on a phone must not re-grab the mouse (pointer-lock), which would
	# undo the touch mouse-capture guard. On native desktop the static func returns
	# false (no JavaScriptBridge touched), so the mouse is recaptured exactly as before.
	if not MobileSensors.is_touch_session():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _freeze_with_gravity(delta: float) -> void:
	"""
	Hold the player still (no horizontal movement) while still settling under
	gravity, so a frozen state never leaves the character hovering. Used by the
	game-over and post-respawn-grace branches of _physics_process.
	"""
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _show_respawn_countdown() -> void:
	"""Show the centred respawn countdown (a plain Label found via group)."""
	var label := get_tree().get_first_node_in_group("respawn_label")
	if label:
		label.visible = true
		label.text = "Caught! Back in %d..." % int(ceil(respawn_timer))


func _hide_respawn_message() -> void:
	"""Hide the respawn countdown label."""
	var label := get_tree().get_first_node_in_group("respawn_label")
	if label:
		label.visible = false


func reset_position() -> void:
	"""
	Hard reset to the origin spawn point. This is the "start over" teleport used by
	restart_game() (and kept as the crocodile's legacy fallback). It wipes the coin
	count — a normal bite no longer does this; it only costs a life and respawns in
	place (see _respawn_in_place).
	"""
	# Define spawn point
	var spawn_point = Vector3(0, 2, 0)

	# A full restart wipes the coin count.
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

	# Drop any active ability state (air boost, giant form, odd size) on respawn.
	_reset_ability_states()

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


# ============================================================================
# SECTION 8: SPECIAL ABILITIES (F KEY)
# ============================================================================
## Every character has ONE signature power, fired with F (the "special_ability"
## input action). They all share a per-character cooldown and a HUD dial:
##
##   * windman  — Air Rush:   launches into the sky and flies at ~5× walk speed
##                            with softened gravity for a few seconds.
##   * primm    — Phase Step: blinks straight forward THROUGH a block, never
##                            stopping inside it (an instant short teleport).
##   * teibi    — Resize:     cycles normal → small → giant → normal. Giant Teibi
##                            is fearless and CRUSHES any crocodile it touches.
##   * phoboman — Stink Wave: belches expanding waves of stench; every crocodile
##                            turns tail and flees for several seconds.
##
## Cooldowns are tracked PER CHARACTER (one timer each), so switching characters
## shows that character's own readiness on the HUD. Discovery stays group-based
## (crocodiles via the "crocodile" group), matching the rest of the project.

## One-shot expanding "wave" visual, reused by several abilities. We spawn it into
## the world (parented to our parent) so it lives on its own and frees itself.
const ABILITY_EFFECT := preload("res://scripts/ability_effect.gd")

## Per-character cooldown length, in seconds. Tunable — longer for stronger powers.
const ABILITY_COOLDOWN := {
	"windman": 8.0,
	"primm": 6.0,
	"teibi": 4.0,
	"phoboman": 12.0,
}

## Friendly ability names shown on the cooldown HUD.
const ABILITY_NAME := {
	"windman": "Air Rush",
	"primm": "Phase Step",
	"teibi": "Resize",
	"phoboman": "Stink Wave",
}

# --- Windman: Air Rush ---
## Top air speed during the boost (5× walk speed — "like Shift pressed five times").
const WINDMAN_AIR_SPEED: float = WALK_SPEED * 5.0
## How long the boost lasts, in seconds.
const WINDMAN_BOOST_DURATION: float = 4.0
## Gravity multiplier while boosting, so Windman glides instead of dropping.
const WINDMAN_GRAVITY_FACTOR: float = 0.45
## Upward launch applied on activation so he gets airborne to use the speed.
const WINDMAN_LIFT: float = 6.0

# --- Primm: Phase Step ---
## Desired blink distance — far enough to clear a single block in open ground.
const PRIMM_BLINK_DISTANCE: float = 6.0
## If the desired landing spot is inside a block, keep scanning outward in steps
## of this size until a clear spot is found (so Primm always exits the far side).
const PRIMM_BLINK_STEP: float = 0.5
## How far out the scan looks before giving up (covers any structure in-game).
const PRIMM_BLINK_MAX_DISTANCE: float = 40.0

# --- Teibi: Resize ---
## Scale factors for the small and giant forms (1.0 is the normal size).
const TEIBI_SCALE_SMALL: float = 0.45
const TEIBI_SCALE_BIG: float = 2.2
## How long Teibi may stay in an altered form (small OR giant) before he snaps
## back to normal on his own — no extra press needed. This is a TOTAL budget for
## the whole small/giant excursion: switching small↔giant does not refill it.
const TEIBI_FORM_DURATION: float = 10.0

# --- Phoboman: Stink Wave ---
## How long crocodiles flee after one whiff, in seconds.
const PHOBOMAN_FLEE_DURATION: float = 10.0
## Visual reach of the stink waves, in metres.
const PHOBOMAN_STINK_RADIUS: float = 9.0

## Per-character cooldown timers (seconds remaining; 0 = ready). Sized in _ready().
var ability_cooldowns: Array[float] = []

## Windman boost time remaining (seconds; > 0 means the Air Rush is active).
var windman_boost_timer: float = 0.0

## Teibi's size cycle: 0 = normal, 1 = small, 2 = giant.
var teibi_size_state: int = 0

## Seconds left in Teibi's current altered form before it auto-reverts to normal
## (0 while he is normal). See TEIBI_FORM_DURATION.
var teibi_form_timer: float = 0.0

## True only while Teibi is giant — makes him crush crocodiles on contact.
var is_giant: bool = false


func _update_ability_timers(delta: float) -> void:
	"""Count down cooldowns, the Windman air boost, and Teibi's form timer."""
	for i in ability_cooldowns.size():
		if ability_cooldowns[i] > 0.0:
			ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
	if windman_boost_timer > 0.0:
		windman_boost_timer = maxf(0.0, windman_boost_timer - delta)
	# Teibi's small/giant form expires on its own after a while, snapping him back
	# to normal size with no extra press — so he can never get stuck transformed.
	if teibi_size_state != 0 and teibi_form_timer > 0.0:
		teibi_form_timer = maxf(0.0, teibi_form_timer - delta)
		if teibi_form_timer <= 0.0:
			_revert_teibi_to_normal()


func try_activate_ability() -> void:
	"""
	Fire the current character's special ability if it isn't on cooldown. Each
	ability function returns true when it actually triggered, which is what starts
	the cooldown — so a no-op never locks the power.
	"""
	var char_name: String = CHARACTERS[current_character_index]["name"]

	# Still cooling down? Ignore the press.
	if ability_cooldowns[current_character_index] > 0.0:
		return

	var used := false
	match char_name:
		"windman":
			used = _ability_windman()
		"primm":
			used = _ability_primm()
		"teibi":
			used = _ability_teibi()
		"phoboman":
			used = _ability_phoboman()

	if used:
		ability_cooldowns[current_character_index] = float(ABILITY_COOLDOWN.get(char_name, 10.0))
		# Whoosh only when the ability actually fired — a failed Primm blink that
		# costs no cooldown stays silent too (null-safe group lookup).
		var sm := get_tree().get_first_node_in_group("sound_manager")
		if sm and sm.has_method("play_ability"):
			sm.play_ability(char_name)


func _ability_windman() -> bool:
	"""Air Rush: launch up and forward, then soar fast with softened gravity."""
	var forward := -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	windman_boost_timer = WINDMAN_BOOST_DURATION
	# Launch: up so he is airborne, plus an immediate forward shove so even a
	# standing press blasts off into the wind right away.
	velocity.y = WINDMAN_LIFT
	velocity.x = forward.x * WINDMAN_AIR_SPEED
	velocity.z = forward.z * WINDMAN_AIR_SPEED

	# An airy cyan swirl around him to sell the gust.
	_spawn_ability_effect(global_position, Color(0.7, 0.92, 1.0, 0.4), 5.0, 0.6)
	return true


func _ability_primm() -> bool:
	"""
	Phase Step: instantly blink straight forward, passing THROUGH any block. Primm
	must never end up stuck inside geometry, so instead of a blind fixed hop we
	scan forward from the desired distance and land at the first spot where his
	body actually fits — which is always on the far side of whatever he phased
	through (a single block, a wall, or a whole pyramid). If there's no clear spot
	within reach (facing into an enormous solid), the blink simply doesn't fire and
	costs no cooldown.
	"""
	var forward := -transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	forward = forward.normalized()

	# March outward for the first position where Primm's body is NOT inside a block.
	var target := global_position
	var found := false
	var d := PRIMM_BLINK_DISTANCE
	while d <= PRIMM_BLINK_MAX_DISTANCE:
		var candidate := global_position + forward * d
		if not _is_body_blocked_at(candidate):
			target = candidate
			found = true
			break
		d += PRIMM_BLINK_STEP

	if not found:
		return false

	# A quick flash where he leaves and where he arrives, to sell the teleport.
	_spawn_ability_effect(global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	global_position = target
	velocity = Vector3.ZERO  # land cleanly on the far side, no carried momentum
	_spawn_ability_effect(global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	return true


func _is_body_blocked_at(pos: Vector3) -> bool:
	"""
	True if solid geometry occupies Primm's body space at world position `pos`.
	We probe with a small sphere at capsule-CENTRE height (not at the feet) so the
	flat ground — which the capsule always rests on — never counts as "blocked";
	only blocks and structures that rise above the ground do.
	"""
	var space := get_world_3d().direct_space_state
	if not space:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.5
	query.shape = probe
	# Lift the probe to the capsule's centre height so it clears the ground plane.
	query.transform = Transform3D(Basis(), pos + Vector3(0.0, collision_base_y, 0.0))
	query.exclude = [get_rid()]  # never sense our own collider
	query.collision_mask = collision_mask
	return not space.intersect_shape(query, 1).is_empty()


func _ability_teibi() -> bool:
	"""
	Resize: cycle normal → small → giant → normal. Giant form crushes crocodiles
	(see crushes_crocodiles) but is too heavy to jump (see the jump step). Any
	altered form auto-reverts to normal after TEIBI_FORM_DURATION, so Teibi can
	never get stuck giant or tiny.
	"""
	var prev_state := teibi_size_state
	teibi_size_state = (teibi_size_state + 1) % 3
	var s := 1.0
	match teibi_size_state:
		1:
			s = TEIBI_SCALE_SMALL
		2:
			s = TEIBI_SCALE_BIG
		_:
			s = 1.0
	_apply_teibi_scale(s)
	is_giant = (teibi_size_state == 2)

	# Manage the auto-revert budget: start it the moment he first leaves normal,
	# clear it when he's back to normal, and KEEP it running across a small↔giant
	# switch (it's a total time-in-altered-form budget, not per-form).
	if teibi_size_state == 0:
		teibi_form_timer = 0.0
	elif prev_state == 0:
		teibi_form_timer = TEIBI_FORM_DURATION
	return true


func _ability_phoboman() -> bool:
	"""Stink Wave: send out smelly waves; every crocodile flees for a while."""
	# A few staggered green waves so it reads as rolling stench, not one pop.
	_spawn_ability_effect(global_position, Color(0.55, 0.85, 0.2, 0.55), PHOBOMAN_STINK_RADIUS, 0.9, 0.0)
	_spawn_ability_effect(global_position, Color(0.5, 0.8, 0.25, 0.45), PHOBOMAN_STINK_RADIUS, 0.9, 0.18)
	_spawn_ability_effect(global_position, Color(0.45, 0.75, 0.3, 0.4), PHOBOMAN_STINK_RADIUS, 0.9, 0.36)

	# Repel every crocodile via the group (no hard references), matching the
	# project's group-based discovery convention.
	for croc in get_tree().get_nodes_in_group("crocodile"):
		if croc.has_method("flee_from"):
			croc.flee_from(global_position, PHOBOMAN_FLEE_DURATION)
	return true


func _apply_teibi_scale(s: float) -> void:
	"""
	Resize the visible model AND the collision capsule to scale `s`, keeping the
	capsule's bottom pinned to the ground so the player never sinks into the floor
	or gets launched when growing or shrinking.

	Why the position tweak: scaling the CollisionShape3D node scales the capsule
	about the node's origin, which would move the capsule's bottom up/down. We move
	the node so the bottom stays exactly where it was at normal size.
	"""
	if character_container:
		character_container.scale = Vector3(s, s, s)
	if collision_shape:
		collision_shape.scale = Vector3(s, s, s)
		var bottom := collision_base_y - collision_half_height
		collision_shape.position.y = bottom + s * collision_half_height


func _spawn_ability_effect(pos: Vector3, color: Color, max_radius: float, lifetime: float, delay: float = 0.0) -> void:
	"""
	Spawn a one-shot expanding/fading wave at a world position. Parented to our
	parent (the main scene) so it lives independently of the player and frees
	itself when finished — no manual cleanup, no leak.
	"""
	var parent := get_parent()
	if not parent:
		return
	var fx := MeshInstance3D.new()
	fx.set_script(ABILITY_EFFECT)
	parent.add_child(fx)
	fx.global_position = pos
	fx.setup(color, max_radius, lifetime, delay)


func _reset_ability_states() -> void:
	"""Clear transient ability state on respawn (air boost, giant/small form)."""
	windman_boost_timer = 0.0
	_revert_teibi_to_normal()


func _revert_teibi_to_normal() -> void:
	"""Snap Teibi back to normal size — used by the form timeout, character switch,
	and respawn. Safe to call for any character (a normal-size body is the default)."""
	teibi_size_state = 0
	is_giant = false
	teibi_form_timer = 0.0
	_apply_teibi_scale(1.0)


# --- Ability HUD contract (read by ability_hud.gd) ---------------------------

func get_ability_name() -> String:
	"""Friendly name of the current character's ability (for the HUD)."""
	var char_name: String = CHARACTERS[current_character_index]["name"]
	return ABILITY_NAME.get(char_name, "Ability")


func get_ability_cooldown_ratio() -> float:
	"""Cooldown progress for the HUD dial: 1.0 just-used → 0.0 fully ready."""
	var char_name: String = CHARACTERS[current_character_index]["name"]
	var duration: float = float(ABILITY_COOLDOWN.get(char_name, 10.0))
	if duration <= 0.0:
		return 0.0
	return clampf(ability_cooldowns[current_character_index] / duration, 0.0, 1.0)


func get_ability_remaining() -> float:
	"""Seconds of cooldown left on the current character's ability."""
	return maxf(0.0, ability_cooldowns[current_character_index])


func is_ability_ready() -> bool:
	"""True when the current character can fire its ability right now."""
	return ability_cooldowns[current_character_index] <= 0.0


func crushes_crocodiles() -> bool:
	"""
	Crocodile contract: when true, a crocodile that touches the player is crushed
	instead of biting. Only giant-form Teibi qualifies. (See piglet_crocodile_ai
	._on_player_collision.)
	"""
	return is_giant
