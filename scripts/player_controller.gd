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

## Speed multiplier applied to the GROUNDED gaits (duck/run/walk) while the
## player is standing in a river — see is_wading and calculate_current_speed().
## 0.6 is a ~40% slowdown: enough to feel like wading and to make crossing a
## river a real decision. Deliberately NOT applied to Windman's Air Rush —
## flying over a river is not wading.
const WADE_SPEED_FACTOR: float = 0.6

## Floor under the RUN gait while wading. The project's difficulty contract is
## "running always escapes": crocodile chase speed is capped at MAX_CHASE_SPEED
## (8.5 in piglet_crocodile_ai.gd) precisely so it stays under the slowest
## character's run (RUN_SPEED 10.0 × CHARACTER_SPEED 0.9 = 9.0). Applying the
## full wade factor to the run gait drops that to 5.4 — below even the BASE
## chase speed of 5.5 — which would make a river band an unescapable death
## trap rather than a decision, and river crossings are not length-bounded (see
## the RIVER_HALF_WIDTH note in endless_terrain.gd). So walk and duck take the
## full drag and the run is floored here instead.
const WADE_RUN_MIN_SPEED: float = 9.0

## How fast A / D rotate the character, in radians per second.
## A and D no longer strafe — they turn the body (tank-style steering), so
## whatever way the character ends up facing is the way W will walk.
const TURN_SPEED: float = 2.6

## Sidestep ("step aside") tuning for Q / E.
## A step is a short, self-contained burst sideways: STEP_SPEED for STEP_DURATION
## seconds, so the character slides about STEP_SPEED * STEP_DURATION metres over.
const STEP_SPEED: float = 5.5
const STEP_DURATION: float = 0.28

## How quickly horizontal velocity approaches the input's target speed, in m/s².
## Instead of snapping instantly to full speed the moment W is pressed, velocity
## ramps toward it — at 40 m/s² a standing start reaches walk speed (5 m/s) in
## ~0.125 s. Barely perceptible as "sluggishness", but it gives starts and
## direction changes a sense of weight. Stopping keeps the separate friction
## branch below, which was already gradual.
const MOVE_ACCELERATION: float = 40.0

# ============================================================================
# SECTION 2: JUMP AND PHYSICS CONSTANTS
# ============================================================================

## Jump velocity determines how high the character can jump
## Higher values = higher jumps
## Physics Note: This is the initial upward velocity when jumping.
## Apex height scales with the SQUARE of this: JUMP_VELOCITY^2 / (2 * gravity).
## We doubled velocity (5.1 -> 10.2) AND quadrupled gravity (3.6 -> 14.4), so the
## apex is EXACTLY unchanged: 10.2^2 / (2 * 14.4) = 3.6125 m — same as the old
## 5.1^2 / (2 * 3.6). Single blocks top out at 2.5 m and structures are climbed
## in <=3 m steps, so everything stays jumpable. What DID change is airtime
## (2v/g): 2.83 s -> 1.42 s — the jump reads arcade-snappy instead of floaty.
const JUMP_VELOCITY: float = 10.2

## Gravity value (meters per second squared)
## Deliberately unphysical: 14.4 (about 1.5× Earth) makes the jump arc snappy —
## the character pops up and comes right back down instead of floating. Paired
## with JUMP_VELOCITY above so the apex height is preserved (see the math there).
## For reference, real planets: Moon 1.6, Mars 3.7, Earth 9.8, Jupiter 24.8.
var gravity: float = 14.4

##  ProjectSettings.get_setting("physics/3d/default_gravity")

## Coyote time: for this many seconds AFTER walking off a ledge the jump still
## fires, as if the ground were still underfoot. Players expect it — without it
## a jump pressed one frame late at a block edge silently eats the input.
const COYOTE_TIME: float = 0.12
## Jump buffer: a jump pressed this many seconds BEFORE landing is remembered
## and fires on the first grounded frame, so button-mashing near the ground
## never drops a jump.
const JUMP_BUFFER_TIME: float = 0.12
## Countdown timers for the two grace windows above (ticked in _physics_process).
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

## Landing impact ("squash"): touching down compresses the character for a brief
## moment, scaled by how fast we were falling — a soft hop barely dips, a long
## drop visibly squashes. Purely visual; the collision capsule never changes.
const LAND_SQUASH_DURATION: float = 0.18
## Impacts faster than this (m/s downward) also get a small camera shake and a
## flat dust ring at the feet — the "heavy landing" tier.
const LAND_HARD_SPEED: float = 4.0
## Seconds left in the current squash (0 = none) and its 0.2–1.0 strength.
var land_squash_timer: float = 0.0
var land_squash_strength: float = 0.0
## Downward speed recorded every airborne falling frame — move_and_slide zeroes
## velocity.y on touchdown, so the landing code reads this instead.
var _fall_speed: float = 0.0

# ============================================================================
# SECTION 3: CAMERA AND ROTATION SETTINGS
# ============================================================================

## How fast the character rotates to face the movement direction
## Higher values = faster rotation (more responsive but less smooth)
## Lower values = slower rotation (smoother but less responsive)
const ROTATION_SPEED: float = 10.0

## Camera rig references. The chain is CameraPivot → CameraArm → Camera3D:
## the pivot carries the mouse-look pitch, and the SpringArm3D between pivot
## and camera pulls the camera in whenever a wall/block sits in the way, so the
## view never clips through geometry. NOTE: a SpringArm3D OVERRIDES its
## children's local position every physics frame (it slides them along its
## local Z by the collision-clamped length) — so nothing may ever write
## camera.position. The bite shake uses Camera3D.h_offset/v_offset (view-space
## offsets the arm doesn't touch) and first-person moves the ARM itself
## (see _apply_view_mode).
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_arm: SpringArm3D = $CameraPivot/CameraArm
@onready var camera: Camera3D = $CameraPivot/CameraArm/Camera3D

## Mouse sensitivity for camera rotation
const MOUSE_SENSITIVITY: float = 0.003

## Keyboard-turn camera easing: when A/D spin the body, the camera pivot lags
## the turn and eases back in at this rate (higher = catches up faster), so a
## keyboard turn sweeps smoothly instead of snapping with the body. MOUSE turns
## deliberately bypass this (they never touch camera_yaw_lag) and stay 1:1.
const CAMERA_TURN_EASE: float = 10.0

## Speed-scaled field of view: the camera widens from FOV_BASE (the Camera3D
## default) toward FOV_MAX as horizontal speed climbs from WALK_SPEED up to
## Windman's air-rush speed — fast movement literally looks fast. Eased at
## FOV_EASE per second so the lens never snaps.
const FOV_BASE: float = 75.0
const FOV_MAX: float = 97.0
const FOV_EASE: float = 5.0
## Transient FOV kick on Windman's Air Rush launch (degrees) and how fast the
## kick bleeds off (degrees per second) — a punch, not a sustained zoom.
const FOV_PUNCH_WINDMAN: float = 12.0
const FOV_PUNCH_DECAY: float = 30.0

## Camera pitch limits (prevents camera from flipping over)
const CAMERA_PITCH_MIN: float = -60.0  # Looking down limit (degrees)
const CAMERA_PITCH_MAX: float = 60.0   # Looking up limit (degrees)

## First-person view (toggled with C / the "toggle_camera" action).
## Eye height above the FEET at normal scale — just under the ~1.8 m head top,
## so the camera sits where the character's eyes would be.
const FIRST_PERSON_EYE_HEIGHT: float = 1.65

## Safe spawn radius - crocodiles within this distance will be removed on respawn
const SPAWN_SAFE_RADIUS: float = 25.0

# ============================================================================
# SECTION 4: STATE VARIABLES
# ============================================================================

## Tracks if the player is currently ducking
var is_ducking: bool = false

## Tracks if the player is currently running
var is_running: bool = false

## True while the player is standing in a river band (see the terrain's biome
## field). Recomputed from scratch every physics tick — it is a pure question
## about where we are standing right now, so it holds no history and needs no
## reset plumbing on respawn/restart. Drives the WADE_SPEED_FACTOR slowdown and
## swaps the footstep sound for a splash.
var is_wading: bool = false

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

## Coin streak multiplier: picking up coins in quick succession (each pickup
## within STREAK_WINDOW seconds of the last) builds a streak. Every
## STREAK_COINS_PER_STEP consecutive coins raise the score multiplier by +1, up
## to 1 + STREAK_MAX_BONUS (x5). Letting the window lapse — or getting bitten
## (see hit_by_crocodile) — resets the streak to zero. This rewards staying ON
## the coin road and moving fast, which is exactly the risk the difficulty
## gradient punishes.
const STREAK_WINDOW: float = 2.5
const STREAK_MAX_BONUS: int = 4
const STREAK_COINS_PER_STEP: int = 10
var coin_streak: int = 0
var streak_timer: float = 0.0

## Extra lives from coins: every EXTRA_LIFE_COINS coins banked grants +1 life,
## capped at LIVES_CAP hearts. next_extra_life_at is the next threshold to cross
## (collect_coin advances it in a while-loop, because one gem at a high streak
## multiplier can jump across a whole threshold — or even two).
const EXTRA_LIFE_COINS: int = 75
const LIVES_CAP: int = 5
var next_extra_life_at: int = EXTRA_LIFE_COINS

## Headline score: how far this run has travelled, in metres — the farthest
## HORIZONTAL DISPLACEMENT from the (0,0) spawn point ever reached this run.
## (Originally this tracked farthest world X — the coin road's forward axis —
## but playtesting showed that reads as a broken counter the moment the player
## wanders any other direction: the number just sits at 0. Displacement is
## direction-agnostic, and for a player following the road it is almost exactly
## the same number, since the road's X is strictly increasing by construction.)
## We track a running max so backtracking never lowers it. Reset to 0 only on a
## full restart (restart_game / reset_position).
var run_distance: int = 0

## Spawn facing: -PI/2 turns the body's -Z forward onto +X — straight down the
## coin road — so "just walk forward" from spawn follows the coin trail and the
## distance counter climbs immediately. (With the default 0.0 facing, a new
## player walks off along Z, sees Distance stuck at 0, and reads it as a bug.)
const SPAWN_FACING_Y: float = -PI / 2

## Best-run records, persisted across sessions in a ConfigFile at
## BEST_RUN_CONFIG_PATH (same pattern as mobile_input.gd's tuning file: on web
## `user://` is IndexedDB-backed, so the records survive a page reload; a missing
## file on first run is NOT an error — we just keep the zero defaults). The two
## records are tracked INDEPENDENTLY: best_distance is the farthest any run got,
## best_coins the richest any run got — a long-but-poor run can set one without
## the other. Updated + saved in _trigger_game_over(), loaded once in _ready().
const BEST_RUN_CONFIG_PATH: String = "user://best_run.cfg"
const BEST_RUN_SECTION: String = "best"
var best_distance: int = 0
var best_coins: int = 0

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

## Post-respawn grace, in TWO phases. Phase 1: after losing a life we stand
## frozen and invulnerable for RESPAWN_GRACE_DURATION seconds (with crocodiles
## swept out of the area). Phase 2: control returns immediately after, but we
## stay invulnerable for RESPAWN_BLINK_DURATION more seconds while the model
## blinks (classic arcade i-frames) — so we get moving again fast without a
## wandering crocodile biting us the instant we recover. The blink toggles
## visibility every RESPAWN_BLINK_CADENCE seconds (skipped in first-person,
## where the model is already hidden). hit_by_crocodile treats a running
## respawn_blink_timer exactly like the frozen window: bites are ignored.
var is_respawning: bool = false
var respawn_timer: float = 0.0
var respawn_blink_timer: float = 0.0
const RESPAWN_GRACE_DURATION: float = 1.5
const RESPAWN_BLINK_DURATION: float = 2.5
const RESPAWN_BLINK_CADENCE: float = 0.1

## Camera shake, used by the crocodile-bite hit effect. Decays back to 0.
## The shake drives Camera3D.h_offset/v_offset (view-space slide of the lens),
## NOT camera.position — the SpringArm3D owns the camera's local position and
## would stomp any write there every physics frame. Offsets also work
## identically in first-person, so the shake needs no per-view rest caching.
var shake_amount: float = 0.0
const SHAKE_MAX: float = 0.25
const SHAKE_DECAY: float = 1.0

## Keyboard-turn camera lag (radians). handle_turning subtracts each frame's
## body turn into this; _process applies it to the pivot's yaw and decays it to
## zero, so the camera trails an A/D turn and eases in behind the body. Mouse
## turns never touch it, keeping mouse look 1:1. Zeroed in reset_position().
var camera_yaw_lag: float = 0.0

## Transient FOV kick (degrees) added on top of the speed-scaled target — set
## to FOV_PUNCH_WINDMAN by Windman's Air Rush launch, decayed back to zero at
## FOV_PUNCH_DECAY per second by the FOV code in _process.
var fov_punch: float = 0.0

## First-person view mode. This is a player PREFERENCE, not transient state: it
## deliberately survives respawn, restart, and character switches (nothing in
## those paths resets it). Toggled with C in _physics_process (STEP 0.55).
var first_person: bool = false
## The spring arm's original scene-file transform (−14° pitch at the pivot) and
## length (8.25 — the old camera's (0,2,8) offset expressed as an arm), plus the
## camera's residual −1° pitch, cached in _ready() so leaving first-person
## restores the shipped third-person framing byte-for-byte. First-person
## commandeers the ARM (identity basis at the eyes, zero length ⇒ no collision
## cast ⇒ the arm is bypassed in FP for free) — see _apply_view_mode().
var third_person_arm_transform: Transform3D = Transform3D.IDENTITY
var third_person_arm_length: float = 0.0
var third_person_camera_rotation: Vector3 = Vector3.ZERO

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

## Footstep tracking: the sign of the walk-cycle sine last frame. Each sign flip
## of sin(time_factor) is one leg passing through centre — i.e. one foot
## planting — so flips are exactly the footstep moments, at any walk/run speed.
## 0 means "not walking" (the reset state), so the first frame of a new walk
## just records the sign instead of mis-firing a step.
var _last_walk_sine_sign: int = 0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	"""
	Called when the node enters the scene tree.
	This is where we do initial setup.
	"""
	# Face straight down the coin road (+X) from the very first frame, so "just
	# walk forward" follows the coin trail and the distance counter climbs
	# immediately (see SPAWN_FACING_Y for why this beats the default facing).
	rotation.y = SPAWN_FACING_Y

	# Desktop pause handler (P key). Instanced in code — not a main.tscn node —
	# so any scene that runs the player standalone gets pausing for free; see
	# pause_controller.gd for why it must be a separate PROCESS_MODE_ALWAYS node.
	add_child(preload("res://scripts/pause_controller.gd").new())

	# Capture the mouse so it doesn't leave the game window — but ONLY when this is NOT
	# a touch session. On a phone/tablet the mobile controls are active and there is no
	# mouse to capture; requesting pointer-lock there would pop a useless permission
	# prompt and can leave the page in a weird captured state. So we skip the capture
	# on a touch session, leaving the cursor visible for the on-screen touch buttons.
	#
	# CANONICAL DETECTION (the fix): we ask `MobileSensors.is_touch_session()` — the
	# SAME static rule the touch UI uses (cached there as `_is_touch`) — instead
	# of the narrower `DisplayServer.is_touchscreen_available()`. Previously the UI could
	# decide "mobile" (via the web coarse-pointer check) while this guard still captured
	# the mouse, an inconsistency on web phones that report no Godot touchscreen.
	#
	# DESKTOP SAFETY: on a native desktop build (no touchscreen, not web) the static func
	# returns false WITHOUT touching JavaScriptBridge, so mouse capture happens exactly as
	# before — desktop keyboard+mouse play is byte-for-byte unchanged. (Mobile-motion plan.)
	if not MobileSensors.is_touch_session():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Load the persisted best-run records (a missing file on first run is fine —
	# the zero defaults stand). See the comment block above BEST_RUN_CONFIG_PATH.
	_load_best_run()

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

	# Cache the spring arm's scene pose (transform + length) and the camera's
	# residual pitch so the first-person toggle (C) can restore the exact
	# shipped third-person view when switching back. Also exclude our own
	# capsule from the arm's collision cast — otherwise the arm would "hit"
	# the player and yank the camera into the back of our head.
	if camera_arm:
		camera_arm.add_excluded_object(get_rid())
		third_person_arm_transform = camera_arm.transform
		third_person_arm_length = camera_arm.spring_length
	if camera:
		third_person_camera_rotation = camera.rotation

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

	# DESKTOP-WEB CLICK-TO-CAPTURE: browsers refuse pointer lock outside a user
	# gesture, so the `_ready()` capture silently fails on a fresh web page load
	# and the camera is dead until the (undiscoverable) double-ESC re-capture.
	# Any click while the mouse is free re-captures it — a click IS the required
	# gesture. Same touch-session guard as the sites above, and never during Game
	# Over (the Play Again button needs a visible, clickable cursor).
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and not MobileSensors.is_touch_session() and not is_game_over:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Handle character switching with E key
	if event.is_action_pressed("switch_character"):
		switch_to_next_character()

# ============================================================================
# FIRST-PERSON VIEW TOGGLE
# ============================================================================

func _apply_view_mode() -> void:
	"""
	Moves the EXISTING camera (no second Camera3D!) to match the current view
	mode. Deliberately idempotent — safe to re-run any time (e.g. after a Teibi
	resize or a character switch) without tracking what the previous state was.
	"""
	if not camera or not camera_arm:
		return
	if first_person:
		# First-person commandeers the ARM, not the camera (the arm owns the
		# camera's local position — see the rig note in SECTION 3). Identity
		# basis zeroes the arm's −14° scene pitch so the pivot's pitch alone
		# (mouse-look) is the look pitch; the arm origin moves to the eyes; and
		# zero spring length means the camera slides to the arm origin AND no
		# collision ray is cast — the arm is bypassed in FP for free. The
		# camera's residual −1° pitch is zeroed too. Hide the model so we
		# don't see our own head from the inside.
		camera_arm.spring_length = 0.0
		camera_arm.transform = Transform3D(Basis.IDENTITY, _first_person_eye_position())
		camera.rotation = Vector3.ZERO
		if character_container:
			character_container.visible = false
	else:
		# Restore the CACHED scene arm pose + camera pitch — byte-identical to
		# the shipped third-person view — and show the model again.
		camera_arm.transform = third_person_arm_transform
		camera_arm.spring_length = third_person_arm_length
		camera.rotation = third_person_camera_rotation
		if character_container:
			character_container.visible = true
	# No shake bookkeeping needed here: the bite shake lives on the camera's
	# h_offset/v_offset, which are view-space and identical in both views.


func _first_person_eye_position() -> Vector3:
	"""
	The first-person eye point as a local position UNDER THE PIVOT (in FP the
	spring arm gets an identity basis, so arm-local == pivot-local and this
	value seats the ARM — the camera rides at its origin). The pivot sits at
	a fixed local height (1.5), so we subtract it from the desired eye height.
	Deriving the scale from the collision capsule means Teibi's small/giant
	forms move the eyes down/up automatically.
	"""
	var scale_y: float = collision_shape.scale.y if collision_shape else 1.0
	return Vector3(0.0, scale_y * FIRST_PERSON_EYE_HEIGHT - camera_pivot.position.y, 0.0)

# ============================================================================
# PHYSICS PROCESSING (CALLED EVERY FRAME)
# ============================================================================

func _physics_process(delta: float) -> void:
	"""
	Called every physics frame (usually 60 times per second).
	This is where we handle movement and physics.

	@param delta: Time elapsed since last frame (in seconds)
	"""

	# STEP 0: First-person toggle (C). POLLED rather than handled in _input() on
	# purpose: the touch UI synthesizes actions via Input.parse_input_event,
	# which polled is_action_just_pressed() sees reliably — same reasoning as the
	# switch_character gotcha in CLAUDE.md. Polled BEFORE the frozen-state early
	# returns below so a press during the caught/respawn/game-over windows isn't
	# silently dropped — the view is a pure camera preference and safe to flip
	# while frozen (_apply_view_mode() only touches the camera rig and model).
	if Input.is_action_just_pressed("toggle_camera"):
		first_person = not first_person
		_apply_view_mode()

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

	# STEP 0c: Post-respawn grace, phase 1 (frozen). We keep standing still and
	# invulnerable (see hit_by_crocodile) while a short countdown runs, then hand
	# control back and start the phase-2 blink i-frames. A final crocodile sweep
	# on the last frame keeps the resume spot clear.
	if is_respawning:
		_freeze_with_gravity(delta)
		update_character_animation(delta, Vector2.ZERO)
		respawn_timer -= delta
		_show_respawn_countdown()
		if respawn_timer <= 0.0:
			is_respawning = false
			_hide_respawn_message()
			clear_nearby_crocodiles(global_position)
			respawn_blink_timer = RESPAWN_BLINK_DURATION
		return

	# STEP 0.35: Post-respawn grace, phase 2 (blinking i-frames). We move
	# NORMALLY — no freeze branch — but stay invulnerable while the timer runs,
	# with the model blinking on a fixed cadence so the protection is readable.
	# First-person skips the toggle (the model is already hidden there); when
	# the timer expires, _apply_view_mode() restores visibility idempotently,
	# respecting whichever view we're in.
	if respawn_blink_timer > 0.0:
		respawn_blink_timer = maxf(0.0, respawn_blink_timer - delta)
		if respawn_blink_timer <= 0.0:
			_apply_view_mode()
		elif not first_person and character_container:
			# One on/off blink per two cadence intervals: visible for the first
			# half of each 2×cadence window, hidden for the second.
			character_container.visible = fmod(respawn_blink_timer, RESPAWN_BLINK_CADENCE * 2.0) < RESPAWN_BLINK_CADENCE

	# STEP 0.4: Record the headline distance score — the farthest horizontal
	# displacement from the spawn point reached this run (see run_distance above
	# for why displacement, not raw X). Spawn is world (0,0) on the XZ plane, so
	# the displacement is just the length of the horizontal position.
	run_distance = maxi(run_distance, int(Vector2(global_position.x, global_position.z).length()))

	# STEP 0.45: Tick the coin-streak window down; when it lapses the streak is
	# over and the score multiplier drops back to x1 (see collect_coin).
	if streak_timer > 0.0:
		streak_timer = maxf(0.0, streak_timer - delta)
		if streak_timer <= 0.0:
			coin_streak = 0

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
		# Record the fall speed while dropping — move_and_slide zeroes velocity.y
		# the frame we touch down, so the landing squash reads this snapshot.
		if velocity.y < 0.0:
			_fall_speed = -velocity.y

	# STEP 2: Handle Jumping (with coyote time + jump buffer — see SECTION 2)
	# Refresh the coyote window while grounded; tick it down while airborne.
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
	# A fresh press arms the buffer; otherwise the buffer ticks down.
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	else:
		jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	# Fire when a buffered press meets ground OR the coyote window. Giant Teibi
	# is too heavy to leave the ground, so he can't jump while transformed.
	if jump_buffer_timer > 0.0 and (is_on_floor() or coyote_timer > 0.0) and not is_giant:
		# Set upward velocity for jump. Zero BOTH timers so the same press can't
		# fire twice (e.g. a coyote jump immediately re-triggering off the buffer).
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_sfx("play_jump")

	# STEP 3: Handle Ducking
	handle_ducking()

	# STEP 4: Handle Running
	is_running = Input.is_action_pressed("run") and not is_ducking

	# STEP 5: Turn the character with A / D (changes which way it faces)
	handle_turning(delta)

	# STEP 6: Advance any in-progress sidestep, and start a new one on Q / E
	update_sidestep(delta)

	# STEP 6.5: Are we standing in a river? One noise evaluation per physics tick
	# (see the terrain's is_river_at) — that is the entire budget for wading, and
	# it is asked BEFORE calculate_current_speed() below so this frame's speed
	# already knows. Only meaningful with feet on the ground: a jumping or flying
	# player is over the water, not in it.
	is_wading = is_on_floor() and _terrain_is_river_here()

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
		# Accelerate toward the target velocity instead of snapping to it —
		# see MOVE_ACCELERATION in SECTION 1 for the feel rationale.
		velocity.x = move_toward(velocity.x, planar_velocity.x, MOVE_ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, planar_velocity.z, MOVE_ACCELERATION * delta)
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
	Per-frame visual camera work that doesn't belong in the physics step:
	the bite shake (random view-space offsets that decay to zero), the eased
	keyboard-turn lag, and the speed-scaled FOV.
	"""
	if not camera:
		return

	# Bite shake — driven through h_offset/v_offset (a view-space slide of the
	# lens), because the SpringArm3D overwrites camera.position every physics
	# frame. Offsets ride on top of whatever the arm decides, in both views.
	if shake_amount > 0.0:
		shake_amount = maxf(0.0, shake_amount - SHAKE_DECAY * delta)
		camera.h_offset = randf_range(-1.0, 1.0) * shake_amount
		camera.v_offset = randf_range(-1.0, 1.0) * shake_amount
	elif camera.h_offset != 0.0 or camera.v_offset != 0.0:
		# Settle exactly back to rest once the shake is done.
		camera.h_offset = 0.0
		camera.v_offset = 0.0

	# Eased keyboard turn: the pivot's yaw holds the lag handle_turning banked,
	# then the lag decays toward zero — so the camera starts behind an A/D turn
	# and smoothly catches up. Mouse turns never bank lag, so they stay 1:1.
	camera_pivot.rotation.y = camera_yaw_lag
	camera_yaw_lag = lerpf(camera_yaw_lag, 0.0, minf(1.0, CAMERA_TURN_EASE * delta))

	# Speed-scaled FOV: map horizontal speed from WALK_SPEED → Windman's
	# air-rush speed onto FOV_BASE → FOV_MAX, add any transient ability punch,
	# and ease the lens toward it. A Camera3D property, so it applies
	# identically in first- and third-person.
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var speed_blend := clampf(
		(horizontal_speed - WALK_SPEED) / (WINDMAN_AIR_SPEED - WALK_SPEED), 0.0, 1.0)
	var target_fov := lerpf(FOV_BASE, FOV_MAX, speed_blend) + fov_punch
	camera.fov = lerpf(camera.fov, target_fov, minf(1.0, FOV_EASE * delta))
	# The launch punch bleeds off on its own, so the kick reads then settles.
	fov_punch = maxf(0.0, fov_punch - FOV_PUNCH_DECAY * delta)

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
	# Deliberately BEFORE the wading factor: flying over a river is not wading.
	if windman_boost_timer > 0.0 and not is_on_floor():
		return WINDMAN_AIR_SPEED

	# Each character has a modest speed stat (see CHARACTER_SPEED) that scales
	# every grounded gait. Unknown names fall back to 1.0 — a new character
	# without an entry just moves at baseline speed.
	var char_name: String = CHARACTERS[current_character_index]["name"]
	var speed_scale: float = float(CHARACTER_SPEED.get(char_name, 1.0))

	# Wading through a river drags on every grounded gait (see WADE_SPEED_FACTOR).
	# Folded into the same multiplier so duck/run/walk all slow by the same share.
	if is_wading:
		speed_scale *= WADE_SPEED_FACTOR

	if is_ducking:
		return DUCK_SPEED * speed_scale
	elif is_running:
		# The wading drag applies here too, but never below WADE_RUN_MIN_SPEED:
		# running has to keep outpacing a chasing crocodile even in the water.
		#
		# AS THE CONSTANTS STAND THE FLOOR ALWAYS WINS: the fastest character is
		# 10.0 * 1.15 * 0.6 = 6.9, under the 9.0 floor, so EVERY character runs at
		# exactly 9.0 while wading and the drag is fully absorbed. The maxf stays
		# as the general expression — retune CHARACTER_SPEED or WADE_SPEED_FACTOR
		# and the drag starts biting again without this line needing a thought.
		if is_wading:
			return maxf(RUN_SPEED * speed_scale, WADE_RUN_MIN_SPEED)
		return RUN_SPEED * speed_scale
	else:
		return WALK_SPEED * speed_scale

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
		var turn_delta := turn_input * TURN_SPEED * delta
		rotate_y(turn_delta)
		# Bank the same turn as camera lag: the pivot counter-rotates by it and
		# eases back to zero in _process, so the camera trails the keyboard
		# turn instead of snapping with the body. (Mouse turns happen in
		# _input and never touch this, keeping mouse look 1:1.)
		camera_yaw_lag -= turn_delta

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
	# This also re-applies the first-person view when active: _apply_teibi_scale
	# ends with `if first_person: _apply_view_mode()`, keeping the model hidden
	# and the camera at the eyes across the switch.
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

	The actual styling now lives in the shared ToonShading helper
	(scripts/toon_shading.gd) so crocodiles get the identical treatment; its
	static material cache is correct for the player too — the same source
	material always maps to the same styled duplicate.

	@param mesh: The mesh whose surface materials should be cel-shaded
	"""
	ToonShading.apply_to_mesh(mesh)

func _sfx(method: String, arg: Variant = null) -> void:
	"""
	Fire one SoundManager one-shot (e.g. "play_jump") via the "sound_manager"
	group — null-safe like the hit_flash pattern, so a scene run without Main
	just stays silent instead of erroring.
	"""
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method(method):
		if arg == null:
			sm.call(method)
		else:
			sm.call(method, arg)

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

	# Landing thud, keyed to the raw floor transition rather than the animation
	# branch below — an active sidestep would otherwise swallow it — and muted
	# during the frozen caught/respawn/game-over windows (this function still
	# runs there, and settling under gravity mid-freeze shouldn't thud).
	if current_on_floor and not was_on_floor \
			and not (is_caught or is_respawning or is_game_over):
		_sfx("play_land")
		# Start the landing squash, scaled by impact speed (see SECTION 2). The
		# eased dip itself is applied AFTER the branch chain below, so the walk
		# bob / idle breathe can't overwrite it on the same frame.
		land_squash_timer = LAND_SQUASH_DURATION
		land_squash_strength = clampf(_fall_speed / 10.0, 0.2, 1.0)
		# Heavy landings additionally kick the camera and puff a flat dust ring
		# at the feet (the thud above already covers audio on every landing).
		if _fall_speed > LAND_HARD_SPEED:
			shake_amount = maxf(shake_amount, 0.12)
			_spawn_ability_effect(global_position, Color(0.75, 0.7, 0.6, 0.45), 1.6, 0.3)
		_fall_speed = 0.0

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

	# Landing squash — applied AFTER the branch chain so whatever body position
	# the active animation just wrote gets the dip added on top (instead of the
	# walk bob / idle breathe overwriting it). A sin(progress * PI) arc eases the
	# compression in and back out, ending at exactly zero so the pose hands back
	# to the animations with no snap. The scale squash stretches the container
	# wide and short (volume-preserving cartoon squash) around the current Teibi
	# base scale; it is skipped while a Teibi resize tween is animating that same
	# property, so the two never fight.
	if land_squash_timer > 0.0:
		land_squash_timer = maxf(0.0, land_squash_timer - delta)
		var squash_progress := 1.0 - land_squash_timer / LAND_SQUASH_DURATION
		var k := sin(squash_progress * PI) * land_squash_strength
		if character_body:
			character_body.position.y -= 0.14 * k
		if character_container and (_teibi_tween == null or not _teibi_tween.is_running()):
			var base := _current_teibi_scale()
			character_container.scale = base * Vector3(1.0 + 0.2 * k, 1.0 - 0.3 * k, 1.0 + 0.2 * k)

	# Not in the walking state (idle, airborne)? Reset the footstep tracker to
	# its "no history" sentinel so the first frame of the next walk records the
	# sine sign instead of mis-firing a phantom step. (A sidestep deliberately
	# does NOT reset it — the walk cycle resumes where it left off, and a step
	# sound on the post-sidestep foot plant is a real plant anyway.)
	if not (is_moving and current_on_floor):
		_last_walk_sine_sign = 0

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

	# Footstep sounds, keyed to the walk cycle itself: each sign flip of the
	# swing sine is a leg passing through centre — a foot planting. Because
	# time_factor already advances 1.5× when running, the step rate speeds up
	# automatically. Sign 0 is the "just started walking" reset state: record
	# the current sign silently so the first frame never mis-fires a step.
	# Wading swaps the pat for a wet slap on the very same trigger, so the
	# "occasional splash" cadence comes free from the walk cycle — no new timer.
	var sine_sign: int = 1 if sin(time_factor) >= 0.0 else -1
	if _last_walk_sine_sign != 0 and sine_sign != _last_walk_sine_sign and is_on_floor():
		_sfx("play_splash" if is_wading else "play_footstep")
	_last_walk_sine_sign = sine_sign

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
	Brief animation when the character lands on the ground. The impact crouch
	itself is no longer set here — the eased landing squash at the end of
	update_character_animation drives it over LAND_SQUASH_DURATION instead of
	the old single -0.1 frame — so this only lowers the wings back to rest.
	"""
	if not character_body:
		return

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

func collect_coin(value: int = 1) -> void:
	"""
	Add a pickup's worth to the coin count. Called by a coin's Area3D when the
	player touches it (see coin.gd) — a plain coin passes 1, a purple gem passes
	its GEM_VALUE (10). The HUD picks up the new value on its next frame.

	Two layered bonuses happen here:
	- STREAK: each pickup refreshes the streak window; the pickup's value is
	  multiplied by the current streak multiplier (see get_streak_multiplier).
	  The streak counts *pickups*, not value — a gem is one link in the chain.
	- EXTRA LIVES: every EXTRA_LIFE_COINS banked grants +1 life up to LIVES_CAP.
	  A while-loop, not an if: one gem at x5 is worth 50 and can jump across a
	  whole threshold (or two), and each crossed threshold must still pay out.
	"""
	streak_timer = STREAK_WINDOW
	coin_streak += 1
	coins_collected += value * get_streak_multiplier()
	while coins_collected >= next_extra_life_at:
		next_extra_life_at += EXTRA_LIFE_COINS
		if lives < LIVES_CAP:
			lives += 1
			print("Extra life! Lives: %d" % lives)
	print("Collected a coin worth %d (x%d streak)! Total: %d" % [value, get_streak_multiplier(), coins_collected])


func get_streak_multiplier() -> int:
	"""
	Current score multiplier from the coin streak: x1 with no streak, +1 per
	STREAK_COINS_PER_STEP consecutive coins, capped at 1 + STREAK_MAX_BONUS.
	Read by the coin HUD to show the "(xN)" suffix.
	"""
	return 1 + mini(STREAK_MAX_BONUS, coin_streak / STREAK_COINS_PER_STEP)


func hit_by_crocodile() -> void:
	"""
	Called by a crocodile when it bites the player (see piglet_crocodile_ai.gd).

	Rather than teleporting away instantly, we play a clear "caught" signal: a red
	screen flash, a camera shake, and a brief freeze (handled in _physics_process).
	When that window ends _on_caught_finished() spends a life and either respawns
	us in place or ends the run.

	Bites are ignored while we are already caught, inside either post-respawn
	grace phase (frozen OR blinking), or on the game-over screen — those states
	make us invulnerable.
	"""
	if is_caught or is_respawning or is_game_over or respawn_blink_timer > 0.0:
		return
	# A real bite breaks the coin streak. Deliberately AFTER the invulnerability
	# early-return above, so an ignored bite (grace window etc.) costs nothing.
	coin_streak = 0
	streak_timer = 0.0
	is_caught = true
	caught_timer = CAUGHT_DURATION

	# Bite sting.
	_sfx("play_bite")

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

	# Game-over sting.
	_sfx("play_game_over")

	# Best-run bookkeeping: distance is the headline record, so IT decides the
	# "NEW BEST!" flash; the coin record updates on its own max independently
	# (see the comment block above BEST_RUN_CONFIG_PATH). Only write the file
	# when a record actually moved — no pointless disk/IndexedDB churn.
	var is_new_best := run_distance > best_distance
	if is_new_best or coins_collected > best_coins:
		best_distance = maxi(best_distance, run_distance)
		best_coins = maxi(best_coins, coins_collected)
		_save_best_run()

	var panel := get_tree().get_first_node_in_group("game_over_ui")
	if panel and panel.has_method("show_game_over"):
		panel.show_game_over(coins_collected, run_distance, best_distance, best_coins, is_new_best)
	print("Game over! Distance: %dm, final coins: %d" % [run_distance, coins_collected])


func _load_best_run() -> void:
	"""
	Load the persisted best-run records over the zero defaults. A missing file
	(first ever run) is NOT an error: ConfigFile.load returns a non-OK code and
	we simply keep 0/0 — the expected first-run path, same as mobile_input.gd's
	tuning load. Values are clamped non-negative so a hand-edited file can't
	show a nonsense negative record.
	"""
	var cfg := ConfigFile.new()
	if cfg.load(BEST_RUN_CONFIG_PATH) != OK:
		return
	best_distance = maxi(0, int(cfg.get_value(BEST_RUN_SECTION, "distance", best_distance)))
	best_coins = maxi(0, int(cfg.get_value(BEST_RUN_SECTION, "coins", best_coins)))


func _save_best_run() -> void:
	"""
	Write the current records to disk. On web `user://` is IndexedDB-backed, so
	this is what makes a best score survive a page reload. The return code is
	ignored: a failed save just means the record isn't persisted this session,
	which is non-fatal and must never interrupt the game-over flow.
	"""
	var cfg := ConfigFile.new()
	cfg.set_value(BEST_RUN_SECTION, "distance", best_distance)
	cfg.set_value(BEST_RUN_SECTION, "coins", best_coins)
	cfg.save(BEST_RUN_CONFIG_PATH)


func restart_game() -> void:
	"""
	Start a brand-new run. Called by the Game Over screen's "Play Again" button.
	Everything resets: coins to 0, lives back to full, and the player is sent to
	the origin spawn with the mouse recaptured.
	"""
	# Coins/distance/streak are wiped by reset_position() below — the one owner of
	# the "hard reset" wipe list, so the two can never drift out of sync.
	lives = MAX_LIVES
	is_game_over = false
	is_caught = false
	is_respawning = false
	# Ability cooldowns are NOT part of reset_position()'s wipe list, and
	# _update_ability_timers() sits below the is_game_over early return in
	# _physics_process — so they freeze the moment the run ends and would carry
	# into the new one at full value (die right after a Stink Wave, hit Play
	# Again, and F is refused for ~12 s with the HUD dial nearly full).
	ability_cooldowns.fill(0.0)
	# Drop any mid-blink i-frames and restore model visibility for the current
	# view — blink state must never leak into a fresh run.
	respawn_blink_timer = 0.0
	_apply_view_mode()
	_hide_respawn_message()
	# Re-roll the world BEFORE teleporting back to spawn: new_run() re-seeds the
	# terrain and synchronously rebuilds the chunks around (0,0), so reset_position()
	# lands us on freshly generated solid ground in the same frame. Group-based
	# lookup with a has_method guard — the project's no-hard-references convention.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("new_run"):
		terrain.new_run()
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
	"""
	Show the centred respawn countdown (a plain Label found via group). The
	frozen window is only 1.5 s now, so a one-decimal readout keeps the short
	countdown visibly moving (a whole-seconds "2... 1..." would barely change).
	"""
	var label := get_tree().get_first_node_in_group("respawn_label")
	if label:
		label.visible = true
		label.text = "Caught! Back in %.1f..." % maxf(respawn_timer, 0.0)


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

	# A full restart wipes the coin count, the distance score, and the streak /
	# extra-life progress that hangs off the coin count.
	coins_collected = 0
	run_distance = 0
	coin_streak = 0
	streak_timer = 0.0
	next_extra_life_at = EXTRA_LIFE_COINS

	# Clear any crocodiles near the spawn point
	clear_nearby_crocodiles(spawn_point)

	# Reset position to spawn point
	global_position = spawn_point

	# Reset velocity to prevent carrying momentum
	velocity = Vector3.ZERO

	# Reset camera and character rotation to default
	rotation.y = SPAWN_FACING_Y  # Face straight down the coin road (+X)
	if camera_pivot:
		camera_pivot.rotation.x = 0.0  # Reset camera vertical rotation
		camera_pivot.rotation.y = 0.0  # Reset camera horizontal rotation
	camera_yaw_lag = 0.0  # Drop any keyboard-turn lag along with the pivot yaw

	# Reset character state
	is_ducking = false
	is_running = false

	# Drop any mid-blink i-frames and restore model visibility for the current
	# view (idempotent — see _apply_view_mode).
	respawn_blink_timer = 0.0
	_apply_view_mode()

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

## Per-character movement speed multiplier, applied to duck/run/walk in
## calculate_current_speed() (NOT to Windman's Air Rush — that ability defines
## its own absolute speed). The spread is deliberately modest (0.9–1.15) so
## every character stays playable: Primm is the sprinter, Teibi the tank whose
## power compensates, and the others sit near baseline.
const CHARACTER_SPEED := {
	"windman": 1.0,
	"primm": 1.15,
	"teibi": 0.9,
	"phoboman": 1.05,
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
## Retuned with the snappy-jump gravity change: 14.4 × 0.1125 = 1.62 m/s² —
## byte-identical to the old 3.6 × 0.45, so the Air Rush glide feel is
## preserved exactly even though base gravity quadrupled.
const WINDMAN_GRAVITY_FACTOR: float = 0.1125
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

## The Teibi resize scale tween, when one is animating character_container.scale
## (null/finished otherwise). The landing squash checks it so the two writers of
## that property never fight.
var _teibi_tween: Tween = null


func _weather_is_raining_here() -> bool:
	"""
	Whether the player is standing in a storm cloud's rain zone, asked of the
	weather manager through the "weather" group — null-safe with a has_method
	guard exactly like _sfx(), so a scene without the manager (or the player
	scene run on its own) simply answers "no rain" instead of erroring.
	"""
	var weather := get_tree().get_first_node_in_group("weather")
	if weather and weather.has_method("is_raining_at"):
		return weather.is_raining_at(global_position)
	return false


func _terrain_is_river_here() -> bool:
	"""
	Whether the player is standing in a river band, asked of the terrain through
	the "terrain" group — the same null-safe group + has_method shape as
	_weather_is_raining_here() above and _sfx(), so the player scene run on its
	own (no EndlessTerrain in the tree) simply answers "no river" instead of
	erroring.

	EDUCATIONAL NOTE:
	- is_river_at() is one evaluation of the terrain's biome noise: no allocation,
	  no physics query, no node lookup beyond this one — cheap enough to ask
	  every physics tick, which is exactly what _physics_process does.

	@return bool: true when this exact spot is inside a river band.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain and terrain.has_method("is_river_at"):
		return terrain.is_river_at(global_position)
	return false


func _update_ability_timers(delta: float) -> void:
	"""Count down cooldowns, the Windman air boost, and Teibi's form timer."""
	for i in ability_cooldowns.size():
		if ability_cooldowns[i] > 0.0:
			ability_cooldowns[i] = maxf(0.0, ability_cooldowns[i] - delta)
	if windman_boost_timer > 0.0:
		windman_boost_timer = maxf(0.0, windman_boost_timer - delta)
		# Wet wings: a Windman who flies INTO a storm cloud's rain zone drops out
		# of the Air Rush immediately — the boost timer is zeroed and the normal
		# gravity/speed rules take back over mid-air. (Only checked while a boost
		# is actually running, so a grounded player never pays for this.)
		if windman_boost_timer > 0.0 and _weather_is_raining_here():
			windman_boost_timer = 0.0
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

	# Still cooling down? The press doesn't fire, but it must not feel dead:
	# flash the cooldown dial red (via the "ability_hud" group — null-safe, no
	# hard reference, like every other HUD hookup) and play a low denial buzz.
	if ability_cooldowns[current_character_index] > 0.0:
		var hud := get_tree().get_first_node_in_group("ability_hud")
		if hud and hud.has_method("flash_blocked"):
			hud.flash_blocked()
		_sfx("play_buzz")
		return

	# Windman can't take off in the rain: pressing F inside a storm cloud's rain
	# zone fails EXACTLY like a cooling-down press (same dial flash, same denial
	# buzz) — and crucially costs no cooldown, so the player can try again the
	# moment they walk out from under the storm.
	if char_name == "windman" and _weather_is_raining_here():
		var rain_hud := get_tree().get_first_node_in_group("ability_hud")
		if rain_hud and rain_hud.has_method("flash_blocked"):
			rain_hud.flash_blocked()
		_sfx("play_buzz")
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
		# costs no cooldown stays silent too.
		_sfx("play_ability", char_name)


func _ability_windman() -> bool:
	"""Air Rush: launch up and forward, then soar fast with softened gravity."""
	var forward := -transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	windman_boost_timer = WINDMAN_BOOST_DURATION
	# Kick the lens wide for the launch moment — the FOV code in _process adds
	# this on top of the speed-scaled target and decays it back to zero.
	fov_punch = FOV_PUNCH_WINDMAN
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

	# A quick flash where he leaves and where he arrives, to sell the teleport —
	# plus three small staggered flashes along the path between them, so the eye
	# can track WHERE the blink went instead of seeing two disconnected pops.
	_spawn_ability_effect(global_position, Color(0.45, 0.5, 1.0, 0.5), 2.0, 0.35)
	for i in range(3):
		_spawn_ability_effect(global_position.lerp(target, (i + 1) / 4.0),
			Color(0.45, 0.5, 1.0, 0.4), 1.0, 0.25, i * 0.05)
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


func _current_teibi_scale() -> float:
	"""The character's current base scale from Teibi's size cycle (1.0 for every
	other character — their state is always 0). The landing squash multiplies
	around this so a squashed small/giant Teibi stays small/giant."""
	match teibi_size_state:
		1:
			return TEIBI_SCALE_SMALL
		2:
			return TEIBI_SCALE_BIG
		_:
			return 1.0


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
		# The VISUAL scale tweens with a springy overshoot so the resize pops
		# instead of snapping. Kill any in-flight resize tween first so rapid
		# F-presses don't leave two tweens fighting over the same property.
		if _teibi_tween:
			_teibi_tween.kill()
		_teibi_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_teibi_tween.tween_property(character_container, "scale", Vector3(s, s, s), 0.25)
	if collision_shape:
		# The COLLISION capsule snaps to the new size instantly — physics must
		# never lag the visual, or a "still shrinking" giant could clip blocks
		# and the first-person eye height would be mid-tween wrong.
		collision_shape.scale = Vector3(s, s, s)
		var bottom := collision_base_y - collision_half_height
		collision_shape.position.y = bottom + s * collision_half_height
	# First-person eyes are derived from this capsule scale, so a resize must
	# immediately re-seat the spring arm (which carries the camera) at the new
	# height — small Teibi looks from down low, giant Teibi from up high.
	# _apply_view_mode() is idempotent, so this is safe from every caller
	# (F-cycle, form timeout, character switch, respawn).
	if first_person:
		_apply_view_mode()


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
	# Sidestep is transient too: the caught/respawn/game-over branches all return
	# BEFORE update_sidestep(), so a player caught mid-step would otherwise come
	# back with is_stepping still true and slide sideways out of the spawn.
	if is_stepping:
		is_stepping = false
		step_timer = 0.0
		step_direction = 0.0
		reset_sidestep_pose()


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
