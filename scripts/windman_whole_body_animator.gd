extends Node3D
## Windman Whole Body Animator
##
## Since the Windman GLB model is static (no skeleton), this script
## animates the entire model as a unit with tilting, bobbing, and rotation.
## This provides visual feedback for movement without requiring limb articulation.

@onready var body: Node3D = $Body if has_node("Body") else null
@onready var model: Node3D = $Body/WindmanModel if has_node("Body/WindmanModel") else null

## Animation state variables
var animation_time: float = 0.0
var last_velocity: Vector3 = Vector3.ZERO
var is_moving: bool = false
var is_in_air: bool = false

## Parent character body reference (set automatically)
var character_body: CharacterBody3D = null

func _ready() -> void:
	"""
	Initialize the animator and find parent CharacterBody3D.
	"""
	# Walk up the tree to find the CharacterBody3D
	var parent = get_parent()
	while parent:
		if parent is CharacterBody3D:
			character_body = parent
			break
		parent = parent.get_parent()

	if character_body:
		print("Windman whole-body animator initialized for CharacterBody3D")
	else:
		print("Warning: Windman animator couldn't find CharacterBody3D parent")

	if not body or not model:
		print("Warning: Windman animator couldn't find Body or Model nodes")

func _process(delta: float) -> void:
	"""
	Animate the whole Windman model based on movement state.
	"""
	if not body or not model or not character_body:
		return

	# Update animation time
	animation_time += delta

	# Get movement state from character body
	var velocity = character_body.velocity
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	is_moving = horizontal_speed > 0.5
	is_in_air = not character_body.is_on_floor()

	# Apply animations based on state
	if is_in_air:
		animate_jumping()
	elif is_moving:
		var is_running = horizontal_speed > 7.0  # Running threshold
		animate_moving(delta, is_running)
	else:
		animate_idle(delta)

	# Store velocity for next frame
	last_velocity = velocity

func animate_moving(delta: float, is_running: bool) -> void:
	"""
	Animate the model while walking or running.
	Creates bobbing and tilting motion.
	"""
	var speed_multiplier = 1.5 if is_running else 1.0
	var bob_speed = 8.0 * speed_multiplier
	var tilt_speed = 8.0 * speed_multiplier

	# Vertical bobbing
	var bob_amount = 0.06 if is_running else 0.04
	var bob = sin(animation_time * bob_speed * 2.0) * bob_amount
	body.position.y = lerp(body.position.y, bob, 0.3)

	# Side-to-side tilt (like a walking pendulum)
	var tilt_amount = deg_to_rad(3.0 if is_running else 2.0)
	var tilt = sin(animation_time * tilt_speed) * tilt_amount
	body.rotation.z = lerp(body.rotation.z, tilt, 0.2)

	# Slight forward lean when running
	if is_running:
		body.rotation.x = lerp(body.rotation.x, deg_to_rad(5.0), 0.1)
	else:
		body.rotation.x = lerp(body.rotation.x, 0.0, 0.1)

func animate_jumping() -> void:
	"""
	Animate the model while in the air.
	Slight forward tilt and reduced bobbing.
	"""
	# Tilt forward slightly when jumping
	body.rotation.x = lerp(body.rotation.x, deg_to_rad(10.0), 0.1)

	# Reduce side tilt in air
	body.rotation.z = lerp(body.rotation.z, 0.0, 0.15)

	# Return to neutral position
	body.position.y = lerp(body.position.y, 0.0, 0.1)

func animate_idle(delta: float) -> void:
	"""
	Animate the model while standing still.
	Subtle breathing motion.
	"""
	# Return rotations to neutral
	body.rotation.x = lerp(body.rotation.x, 0.0, 0.1)
	body.rotation.z = lerp(body.rotation.z, 0.0, 0.1)

	# Gentle breathing bob
	var breathe_speed = 1.5
	var breathe_amount = 0.01
	var breathe = sin(animation_time * breathe_speed) * breathe_amount
	body.position.y = lerp(body.position.y, breathe, 0.05)
