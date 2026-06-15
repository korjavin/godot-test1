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
var move_speed_instance: float = 0.0

## Chase speed when pursuing player (faster)
var chase_speed_instance: float = 0.0

## Base speeds for randomization
const BASE_MOVE_SPEED: float = 2.5
const BASE_CHASE_SPEED: float = 3.5

## Per-crocodile speed spread: each crocodile rolls ONE multiplier in
## [1-FACTOR, 1+FACTOR] and applies it to BOTH its wander and chase speed, so some
## crocodiles are clearly faster and some slower — yet a given crocodile's chase
## always still outpaces its own stroll (the two speeds never drift apart). ±50%.
const SPEED_RANDOM_FACTOR: float = 0.5

## Per-crocodile size spread: each crocodile rolls a uniform scale in
## [1-FACTOR, 1+FACTOR] applied to the whole body (visual model + physics capsule
## together), so the pack is a mix of smaller and larger crocodiles. ±25%.
const SIZE_RANDOM_FACTOR: float = 0.25

## Detection radius - distance at which crocodile can "smell" the player
const DETECTION_RADIUS: float = 15.0

## Time between direction changes (in seconds)
const DIRECTION_CHANGE_INTERVAL: float = 4.0

## Pause duration when changing direction (in seconds)
const PAUSE_DURATION: float = 0.5

## Gravity acceleration (matches project default)
const GRAVITY: float = 9.8

# ----- Organic wandering -----
## How sharply the heading drifts while wandering (radians/sec of random steer).
## Small continuous nudges produce smooth, curved meandering instead of
## straight lines with hard turns.
const WANDER_TURN_RATE: float = 1.2

## How smoothly the body turns to face its heading (higher = snappier)
const TURN_SMOOTHNESS: float = 5.0

## Slowest wander speed as a fraction of the instance's base speed
const MIN_WANDER_SPEED_FACTOR: float = 0.45

## How quickly wander speed ebbs and flows (radians/sec)
const SPEED_VARIATION_FREQ: float = 0.8

## Chance (per direction-change interval) of pausing to "sniff" around
const SNIFF_PAUSE_CHANCE: float = 0.3

# ----- Obstacle avoidance -----
## How far ahead (metres) the crocodile senses blocks. This is deliberately
## longer than the visual model so the crocodile turns away *before* its snout
## can reach a block — the snout poking into blocks is exactly what this fixes
## (the physics capsule is much shorter than the model, so move_and_slide alone
## stops the body but lets the longer nose overlap the block).
const AVOID_LOOK_AHEAD: float = 3.0

## Angle of the left/right "feeler" probes used to find a clear way around (rad).
const AVOID_FEELER_ANGLE: float = PI / 5.0  # 36°

## Height above the body origin to cast the feelers from, so they sample the
## block's side walls rather than the flat ground.
const AVOID_FEELER_HEIGHT: float = 0.3

## Speed multiplier while steering around a block, so the crocodile eases off and
## curves around instead of ramming the block nose-first.
const AVOID_SPEED_FACTOR: float = 0.5

# ----- Procedural body animation -----
## Yaw applied to the model so its snout points along the travel direction.
## The mesh is authored facing +X but the body travels +Z, so we rotate -90°.
## If the snout ends up pointing the wrong way in-editor, flip this sign.
const MODEL_FACING_OFFSET: float = -PI / 2.0

## Stride frequency at full speed (radians/sec) — drives the waddle/bob
const STRIDE_FREQUENCY: float = 9.0

## Side-to-side waddle roll amplitude (radians) — uses PI math so it stays a
## constant expression (deg_to_rad() can't be used in a const)
const WADDLE_ROLL: float = 9.0 * PI / 180.0

## Vertical bob amplitude (metres)
const BOB_AMOUNT: float = 0.025

## Slow body "snaking" yaw amplitude (radians)
const SWAY_YAW: float = 5.0 * PI / 180.0

## Forward lean while hunting the player (radians)
const CHASE_PITCH: float = 10.0 * PI / 180.0

## Idle breathing speed/amount when standing still
const BREATHE_SPEED: float = 2.0
const BREATHE_AMOUNT: float = 0.012

# ----- Bite -----
## How long the chomp animation plays when the crocodile catches the player (s).
const BITE_DURATION: float = 0.5

## How far the head snaps down/up during the chomp (radians).
const BITE_PITCH: float = 26.0 * PI / 180.0

## How far the body lunges forward during the bite (metres).
const BITE_LUNGE: float = 0.35

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

## Flee state. When Phoboman unleashes his Stink Wave, every crocodile turns tail
## and runs from the player for a while. Fleeing OVERRIDES both chase and wander,
## and a fleeing crocodile is harmless — it won't bite (see _on_player_collision).
var is_fleeing: bool = false
## Seconds of fleeing left (counts down to 0).
var flee_time_remaining: float = 0.0
## The smell's origin, used only as a fallback "run from here" point if the player
## reference is momentarily missing while fleeing.
var flee_source: Vector3 = Vector3.ZERO

## Reference to the player node
var player_node: Node3D = null

## Random number generator for movement
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Smoothly-drifting heading used while wandering (radians)
var wander_heading: float = 0.0

## Phase accumulator for wander-speed variation
var speed_phase: float = 0.0

## Per-instance phase offset so the whole pack doesn't move in lockstep
var instance_phase: float = 0.0

# --- Body animation state ---

## The model node we animate (single static mesh, no rigged limbs)
var model: Node3D = null

## Cached rest scale / height of the model so animation composes on top
var model_base_scale: Vector3 = Vector3.ONE
var model_base_y: float = 0.0

## Stride / idle phase accumulators
var stride_phase: float = 0.0
var animation_time: float = 0.0

## Current (eased) forward lean
var current_pitch: float = 0.0

## Bite/chomp animation state, played when the crocodile catches the player.
var is_biting: bool = false
var bite_timer: float = 0.0

## LOD (simulation level-of-detail) gate. When true, this crocodile runs its full
## per-frame AI/physics step exactly as before. When false, it is "asleep": the
## central CrocodileLODManager has decided it is too far from the player to
## possibly matter this frame, so _physics_process cheap-returns (which is also
## what makes a slept croc harmless — see set_lod_active) and the HitBox stops
## monitoring as a cheap cleanup. Defaults to TRUE so a crocodile spawned before the manager's
## first scan behaves normally for that brief window (the manager will sleep it on
## its next tick if it's far away). See crocodile_lod_manager.gd for the contract.
var lod_active: bool = true

## Confinement: elevated "patrol" crocodiles are pinned to a structure top (a
## pyramid apex or wall ridge) and can never wander off it, since they can't jump
## or climb back up. Set up by the terrain via set_confinement().
var is_confined: bool = false
var confine_center: Vector3 = Vector3.ZERO
## Half-extents of the platform box on world X (.x) and world Z (.y).
var confine_half: Vector2 = Vector2.ZERO
## Start steering back toward the centre once this close to the platform edge.
const CONFINE_MARGIN: float = 0.9

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	"""Initialize the crocodile NPC."""
	# Randomize the RNG
	rng.randomize()

	# Set instance-specific speeds. One shared multiplier drives both speeds, so a
	# "fast" crocodile is fast at everything (and its chase always still outpaces its
	# own wander) instead of the two speeds drifting apart independently.
	var speed_factor := rng.randf_range(1.0 - SPEED_RANDOM_FACTOR, 1.0 + SPEED_RANDOM_FACTOR)
	move_speed_instance = BASE_MOVE_SPEED * speed_factor
	chase_speed_instance = BASE_CHASE_SPEED * speed_factor

	# Give this crocodile a randomized overall size. We scale the whole body
	# uniformly so the visual model and the physics capsule grow/shrink together;
	# gravity then settles it onto the ground regardless of size. The model's OWN
	# local scale stays 1, so model_base_scale cached below is unaffected and the
	# procedural body animation composes correctly on top of this body scale.
	var size_scale := rng.randf_range(1.0 - SIZE_RANDOM_FACTOR, 1.0 + SIZE_RANDOM_FACTOR)
	scale = Vector3.ONE * size_scale

	# Set initial random direction
	_choose_new_direction()

	# Add to "crocodile" group for easy detection
	add_to_group("crocodile")
	add_to_group("enemy")

	# Start with a random offset to avoid all crocodiles changing direction at once
	time_since_direction_change = randf() * DIRECTION_CHANGE_INTERVAL

	# Per-instance phase offsets so a pack of crocodiles doesn't move in lockstep
	instance_phase = rng.randf_range(0.0, TAU)
	speed_phase = rng.randf_range(0.0, TAU)
	stride_phase = rng.randf_range(0.0, TAU)

	# Cache the visual model so we can animate its body procedurally
	model = get_node_or_null("Model")
	if model:
		model_base_scale = model.scale
		model_base_y = model.position.y

	# Find the player node (defer to allow scene to fully load)
	call_deferred("_find_player")


func _physics_process(delta: float) -> void:
	"""Update movement, body animation and collisions every physics frame."""
	# ------------------------------------------------------------------------
	# LOD SLEEP GATE (simulation level-of-detail)
	# ------------------------------------------------------------------------
	# If the CrocodileLODManager has slept this crocodile (it is far from the
	# player and can't matter this frame), do the absolute minimum and bail out
	# BEFORE any of the expensive work: chase scanning, wander steering, obstacle
	# raycasts, confinement steering, move_and_slide, collision handling, platform
	# clamping and body animation are ALL skipped while asleep.
	#
	# We freeze the body completely by zeroing velocity and NOT calling
	# move_and_slide — a slept crocodile simply stays exactly where it was. We do
	# not even apply gravity here: distant crocodiles were already standing on the
	# terrain when they fell asleep, and skipping gravity (rather than letting them
	# drift down without collision resolution) is what keeps them perfectly put.
	# Every other piece of state (heading, chase flags, phases, confinement) is
	# preserved untouched, so when the manager wakes this crocodile again it
	# resumes seamlessly — whether it's a wanderer or a confined patrol crocodile.
	if not lod_active:
		velocity = Vector3.ZERO
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if is_paused:
		# Stand still while paused (still breathes via _animate_body below).
		pause_time_remaining -= delta
		if pause_time_remaining <= 0:
			is_paused = false
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		# Decide what we want to do this frame. Fleeing (Phoboman's Stink Wave)
		# overrides everything; otherwise chase the player if in range, else wander.
		if is_fleeing:
			flee_time_remaining -= delta
			if flee_time_remaining <= 0.0:
				# The whiff wore off — go back to normal wandering.
				is_fleeing = false
				_choose_new_direction()

		if is_fleeing:
			# Run directly away from the player.
			_flee()
		else:
			_update_chase_state()
			if is_chasing and player_node:
				# Chase the player
				_chase_player()
			else:
				# Wander with smooth, organic steering
				_wander(delta)

		# Steer around any block ahead so we don't drive our snout into it. This
		# may override the chase/wander heading for this frame.
		var avoiding := _avoid_obstacles()

		# If this is a patrol crocodile, turn it back toward the platform centre
		# when it gets near an edge (overrides the heading above).
		if is_confined:
			_steer_within_platform()

		# Rotate smoothly toward the desired heading and move that way.
		# Driving velocity from facing (not the raw direction) prevents sliding
		# sideways and makes turns curve naturally.
		if movement_direction.length() > 0.1:
			var target_rotation := atan2(movement_direction.x, movement_direction.z)
			# Turn harder while avoiding so we actually clear the block in time.
			var turn_rate := TURN_SMOOTHNESS * (2.0 if avoiding else 1.0)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * turn_rate)

			# Flee and chase both move at the faster "chase" speed.
			var current_speed := chase_speed_instance if (is_chasing or is_fleeing) else _wander_speed(delta)
			if avoiding:
				current_speed *= AVOID_SPEED_FACTOR
			velocity.x = sin(rotation.y) * current_speed
			velocity.z = cos(rotation.y) * current_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0

	# Move and resolve collisions (collisions are ignored while paused, matching
	# the original "harmless while recovering" behaviour).
	move_and_slide()
	if not is_paused:
		_handle_collisions()

	# Hard backstop: pin a patrol crocodile inside its platform so it can never
	# slip off the edge, even if a collision or the bite-lunge nudged it.
	if is_confined:
		_clamp_to_platform()

	# Animate the body to match how fast we're actually moving.
	_animate_body(delta)


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

	# Check if player is grounded (can be smelled)
	# If player jumps (is not on floor), crocodiles lose the scent
	var player_is_grounded = true
	if player_node.has_method("is_on_floor"):
		player_is_grounded = player_node.is_on_floor()

	# Update chase state based on detection radius AND player grounded state
	if distance_to_player <= DETECTION_RADIUS and player_is_grounded:
		if not is_chasing:
			# Just started chasing
			is_chasing = true
	else:
		if is_chasing:
			# Lost the player (too far OR player jumped)
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


func _flee() -> void:
	"""
	Run directly AWAY from the player (Phoboman's stink). Falls back to the
	remembered smell origin if the player reference is momentarily missing, and to
	the current heading if we somehow sit right on top of the source.
	"""
	var away := Vector3.ZERO
	if player_node:
		away = global_position - player_node.global_position
	else:
		away = global_position - flee_source
	away.y = 0.0

	if away.length() < 0.01:
		away = Vector3(sin(wander_heading), 0.0, cos(wander_heading))

	movement_direction = away.normalized()
	# Keep the wander heading in sync so obstacle-avoidance steering composes
	# cleanly and the croc holds its escape course instead of curving back.
	wander_heading = atan2(movement_direction.x, movement_direction.z)


func flee_from(source: Vector3, duration: float) -> void:
	"""
	Public hook called by Phoboman's Stink Wave (via the "crocodile" group): make
	this crocodile turn tail and run from the player for `duration` seconds. Drops
	any current chase. `source` is the smell's origin, used only as a fallback
	direction if the player can't be located on a given frame.
	"""
	is_fleeing = true
	flee_time_remaining = duration
	flee_source = source
	is_chasing = false


func _wander(delta: float) -> void:
	"""
	Organic wandering: instead of snapping to a brand-new random direction and
	walking dead-straight, the heading drifts continuously by small random
	amounts (a bounded random walk), producing smooth, curved meandering. Every
	so often we apply a bigger course correction and occasionally pause to sniff.
	"""
	# Continuous gentle steering — this is what curves the path.
	wander_heading += rng.randf_range(-1.0, 1.0) * WANDER_TURN_RATE * delta

	# Periodic bigger nudges / occasional pauses to look around.
	time_since_direction_change += delta
	if time_since_direction_change >= DIRECTION_CHANGE_INTERVAL:
		time_since_direction_change = 0.0
		wander_heading += rng.randf_range(-PI / 2.0, PI / 2.0)
		if rng.randf() < SNIFF_PAUSE_CHANCE:
			is_paused = true
			pause_time_remaining = PAUSE_DURATION

	# Convert heading to a direction vector on the XZ plane.
	movement_direction = Vector3(sin(wander_heading), 0.0, cos(wander_heading))


func _wander_speed(delta: float) -> float:
	"""
	A gently varying wander speed so crocodiles ease between strolling and a
	brisker walk instead of gliding at one constant velocity.
	"""
	speed_phase += delta * SPEED_VARIATION_FREQ
	var t := 0.5 * (sin(speed_phase + instance_phase) + 1.0)  # 0..1
	return move_speed_instance * lerp(MIN_WANDER_SPEED_FACTOR, 1.0, t)


func _avoid_obstacles() -> bool:
	"""
	Steer around blocks so the crocodile never drives its snout into one.

	We cast a short feeler ray straight ahead; if it hits a block, we probe to the
	left and right and turn toward whichever side is open (or turn hard if both are
	blocked, e.g. facing into a wall). Because the look-ahead is longer than the
	model, the crocodile starts turning before its nose can reach the block.

	The player, other crocodiles and the flat ground are NOT treated as obstacles,
	so this never stops a crocodile from reaching the player.

	@return true if a block was sensed and we steered around it this frame.
	"""
	if movement_direction.length() < 0.1:
		return false

	var space := get_world_3d().direct_space_state
	if not space:
		return false

	var origin := global_position + Vector3(0.0, AVOID_FEELER_HEIGHT, 0.0)
	var forward := movement_direction.normalized()

	# Nothing straight ahead? Then there's nothing to steer around.
	if not _feeler_blocked(space, origin, forward):
		return false

	# Probe both sides and pick a clear way around.
	var left_dir := forward.rotated(Vector3.UP, AVOID_FEELER_ANGLE)
	var right_dir := forward.rotated(Vector3.UP, -AVOID_FEELER_ANGLE)
	var left_blocked := _feeler_blocked(space, origin, left_dir)
	var right_blocked := _feeler_blocked(space, origin, right_dir)

	var steer_dir: Vector3
	if left_blocked and right_blocked:
		# Boxed in (running into a wall) — turn hard to one side to escape.
		steer_dir = forward.rotated(Vector3.UP, PI / 2.0)
	elif right_blocked:
		steer_dir = left_dir
	elif left_blocked:
		steer_dir = right_dir
	else:
		# A single block dead ahead with both sides open — ease around it.
		steer_dir = left_dir

	movement_direction = steer_dir.normalized()
	# Keep the wander heading in sync so a wandering crocodile holds the new
	# course after it clears the block instead of curving straight back into it.
	wander_heading = atan2(movement_direction.x, movement_direction.z)
	return true


func _feeler_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3) -> bool:
	"""
	Cast one feeler ray and report whether a *block* sits within AVOID_LOOK_AHEAD.
	The player, other crocodiles and the (horizontal) ground are not blocks.

	@param space: The physics space to query
	@param origin: Ray start, already lifted to feeler height
	@param dir: Direction to probe (need not be normalized)
	@return true if the ray hits something we should steer around
	"""
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * AVOID_LOOK_AHEAD)
	query.exclude = [get_rid()]  # never sense our own collider
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider = hit.get("collider")
	if collider == null:
		return false
	# Ignore the things we don't want to swerve around.
	if collider.is_in_group("player") or collider.is_in_group("crocodile"):
		return false
	return true


# ============================================================================
# LOD (SIMULATION LEVEL-OF-DETAIL)
# ============================================================================

func set_lod_active(active: bool) -> void:
	"""
	Wake (active = true) or sleep (active = false) this crocodile's simulation.
	Called by the central CrocodileLODManager only when the awake/asleep decision
	actually changes, so the transition work below runs at most once per change.

	What actually keeps a sleeping crocodile from harming the player is storing the
	flag: _physics_process reads `lod_active` at the very top and cheap-returns while
	asleep, which means the crocodile never runs move_and_slide nor _handle_collisions
	— and _handle_collisions (reading get_slide_collision()) is the ONLY code path that
	calls player.reset_position(). So the early-return alone makes a slept crocodile
	harmless; no contact damage can occur.

	The HitBox Area3D's monitoring is toggled here too, but purely as a cheap cleanup:
	nothing connects to the HitBox's body_entered/area_entered signals (grep confirms
	no such connection in this script or piglet_crocodile.tscn), so the HitBox does not
	itself drive any damage. Turning monitoring off on a sleeping crocodile just saves
	the physics server from tracking ~1,200 idle Area3Ds; turning it back on when awake
	costs nothing. It's harmless to keep, but it is NOT the safety mechanism.

	We touch the HitBox with set_deferred() because monitoring can't be flipped
	mid-physics-step safely; deferring applies it at a safe point. We also only do
	the HitBox work on a genuine state change to avoid redundant deferred calls.
	"""
	# No-op if nothing actually changed (defensive; the manager already guards this).
	if active == lod_active:
		return

	lod_active = active

	# Toggle the hostile trigger to match the new state. Guard that the node exists
	# (every PigletCrocodile scene has $HitBox, but stay robust if a variant doesn't).
	var hitbox := get_node_or_null("HitBox")
	if hitbox:
		# Deferred so we never change monitoring in the middle of physics resolution.
		# Asleep → stop monitoring (frees the physics server from tracking an idle
		# Area3D). Awake → resume. This is a cheap cleanup, NOT the harm-prevention
		# safety: the _physics_process early-return is what stops a slept croc from
		# ever running the collision code that damages the player (see set_lod_active).
		hitbox.set_deferred("monitoring", active)


# ============================================================================
# PLATFORM CONFINEMENT (patrolling crocodiles)
# ============================================================================

func set_confinement(center: Vector3, half: Vector2) -> void:
	"""
	Pin this crocodile to a platform so it patrols but never walks off. Called by
	the terrain right after spawning an elevated "patrol" crocodile.

	@param center: World-space centre of the platform (its surface height in .y)
	@param half: Half-extents of the platform on world X (.x) and world Z (.y)
	"""
	is_confined = true
	confine_center = center
	confine_half = half


func _steer_within_platform() -> void:
	"""
	Turn a patrol crocodile back toward the platform centre as it nears an edge,
	so it paces the surface instead of strolling off it.
	"""
	var off := global_position - confine_center
	var steer := Vector3.ZERO

	if off.x > confine_half.x - CONFINE_MARGIN:
		steer.x = -1.0
	elif off.x < -confine_half.x + CONFINE_MARGIN:
		steer.x = 1.0

	if off.z > confine_half.y - CONFINE_MARGIN:
		steer.z = -1.0
	elif off.z < -confine_half.y + CONFINE_MARGIN:
		steer.z = 1.0

	if steer != Vector3.ZERO:
		movement_direction = steer.normalized()
		wander_heading = atan2(movement_direction.x, movement_direction.z)


func _clamp_to_platform() -> void:
	"""
	Hard backstop: keep the crocodile's position inside the platform box. If it
	somehow reached the edge, pull it back and kill the outward velocity.
	"""
	var off := global_position - confine_center
	var clamped_x := clampf(off.x, -confine_half.x, confine_half.x)
	var clamped_z := clampf(off.z, -confine_half.y, confine_half.y)

	if clamped_x != off.x or clamped_z != off.z:
		global_position.x = confine_center.x + clamped_x
		global_position.z = confine_center.z + clamped_z
		velocity.x = 0.0
		velocity.z = 0.0


# ============================================================================
# AI BEHAVIOR METHODS
# ============================================================================

func _choose_new_direction() -> void:
	"""Pick a fresh random heading to wander toward."""
	# Random angle in radians (TAU = 2*PI = full circle)
	wander_heading = rng.randf_range(0.0, TAU)

	# Convert to a direction vector on the XZ plane (Y=0 for ground movement)
	movement_direction = Vector3(sin(wander_heading), 0.0, cos(wander_heading))

	# Reset timer
	time_since_direction_change = 0.0


func _pause_and_change_direction() -> void:
	"""Pause briefly, then choose a new direction."""
	is_paused = true
	pause_time_remaining = PAUSE_DURATION
	_choose_new_direction()


# ============================================================================
# BODY ANIMATION
# ============================================================================

func _animate_body(delta: float) -> void:
	"""
	Procedural body animation. The crocodile model is a single static mesh with
	no rigged limbs, so — like the player animates its limbs with sine waves — we
	animate the whole `Model` node: a side-to-side waddle, a vertical bob, a slow
	body "snake", and a forward lean while hunting. The stride speeds up the
	faster the crocodile moves and freezes (to a gentle breath) when it stops.
	"""
	if not model:
		return

	animation_time += delta

	# A bite overrides the normal locomotion animation while it plays.
	if is_biting:
		_animate_bite(delta)
		return

	# How fast are we actually moving along the ground? (0 = standing still)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var move_factor := clampf(horizontal_speed / BASE_MOVE_SPEED, 0.0, 1.6)

	# Advance the stride phase faster the quicker we move.
	stride_phase += delta * STRIDE_FREQUENCY * move_factor

	# Waddle (roll about the forward axis) + vertical bob (twice the stride rate).
	var roll := sin(stride_phase) * WADDLE_ROLL * move_factor
	var bob := sin(stride_phase * 2.0) * BOB_AMOUNT * move_factor

	# Slow body "snaking" — a lazy yaw sway, offset per-instance.
	var yaw_sway := sin(stride_phase * 0.5 + instance_phase) * SWAY_YAW * move_factor

	# Lean forward while hunting; ease back to level otherwise.
	var target_pitch := CHASE_PITCH if is_chasing else 0.0
	current_pitch = lerp(current_pitch, target_pitch, delta * 6.0)

	# When basically still, replace the bob with a subtle breathing motion.
	if move_factor < 0.05:
		bob = sin(animation_time * BREATHE_SPEED) * BREATHE_AMOUNT

	# Compose the transform: first align the snout to the travel direction, then
	# layer the oscillations on top (re-applying the model's rest scale).
	var facing := Basis(Vector3.UP, MODEL_FACING_OFFSET)
	var oscillation := Basis.from_euler(Vector3(current_pitch, yaw_sway, roll))
	model.transform.basis = (oscillation * facing).scaled(model_base_scale)
	model.position.y = model_base_y + bob


func _animate_bite(delta: float) -> void:
	"""
	Play the chomp: the head snaps down/up a couple of times while the body lunges
	forward (toward the player it just caught, since the crocodile keeps facing
	them while paused). The lunge eases in and back out, so the model returns
	cleanly to its rest pose as the bite ends.
	"""
	bite_timer -= delta
	if bite_timer <= 0.0:
		is_biting = false
		return

	# Progress through the bite: 0 at the start, 1 at the end.
	var p := 1.0 - clampf(bite_timer / BITE_DURATION, 0.0, 1.0)
	# Two fast chomps (sin over two cycles) and a single forward lunge (sin over
	# half a cycle, so it pushes out then pulls back to zero).
	var chomp := sin(p * TAU * 2.0)
	var lunge := sin(p * PI) * BITE_LUNGE

	var facing := Basis(Vector3.UP, MODEL_FACING_OFFSET)
	var snap := Basis.from_euler(Vector3(chomp * BITE_PITCH, 0.0, 0.0))
	model.transform.basis = (snap * facing).scaled(model_base_scale)
	# Lunge along the body's forward axis (+Z) and lift a touch on each snap.
	model.position = Vector3(0.0, model_base_y + absf(chomp) * 0.04, lunge)


# ============================================================================
# COLLISION DETECTION
# ============================================================================

func _handle_collisions() -> void:
	"""
	Check collisions with the player.

	Crocodiles are now SOLID to one another (their collision_mask includes their own
	layer), so move_and_slide already shoves two bumping crocodiles apart on its own
	— they push past each other instead of overlapping. We therefore do NOTHING on a
	crocodile-vs-crocodile contact (the earlier eat-on-touch "cannibalism" is gone);
	the physical push is the entire behaviour, and only the player still matters here.
	"""
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


func _start_bite() -> void:
	"""Begin the chomp animation (ignored if one is already playing)."""
	if is_biting:
		return
	is_biting = true
	bite_timer = BITE_DURATION


func _on_player_collision(player: Node) -> void:
	"""
	Handle collision with the player. Normally FATAL (chomp, then send them back),
	with two exceptions tied to special abilities:
	  * Giant-form Teibi CRUSHES the crocodile on contact instead of being bitten.
	  * A crocodile fleeing Phoboman's stink is harmless and just brushes past.
	"""
	# Giant Teibi squashes crocodiles on contact instead of being bitten.
	if player.has_method("crushes_crocodiles") and player.crushes_crocodiles():
		print("🐊 Squashed by a giant!")
		queue_free()
		return

	# While fleeing Phoboman's stink, crocodiles can't bring themselves to bite.
	if is_fleeing:
		return

	print("💀 Piglet Crocodile bites the player!")

	# Snap at the player so the hit reads clearly.
	_start_bite()

	# Tell the player it was bitten. hit_by_crocodile() plays the red flash /
	# camera shake / brief freeze and then respawns; older saves without it fall
	# back to a plain reset.
	if player.has_method("hit_by_crocodile"):
		player.hit_by_crocodile()
	elif player.has_method("reset_position"):
		player.reset_position()
	else:
		# Fallback: move player up and away
		if player is Node3D:
			player.global_position = Vector3(0, 2, 0)

	# Pause/turn away so we don't immediately re-trigger on the same overlap.
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
