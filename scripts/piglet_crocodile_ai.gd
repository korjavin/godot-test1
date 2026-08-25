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

## Base speeds for randomization. Chase speed is deliberately ABOVE the player's
## WALK_SPEED (5.0), so a merely-walking player WILL get caught — escaping a chase
## takes running, jumping (crocodiles lose the scent when you leave the ground), or
## a special ability. This is the game's core fail pressure.
const BASE_MOVE_SPEED: float = 2.5
const BASE_CHASE_SPEED: float = 5.5

## Difficulty gradient: crocodiles chase faster the farther from origin they spawn.
## The multiplier is 1.0 + clamp(|x| / DENOM, 0, MAX) — +60% at 3 km and capped there,
## so late-run walking is lethal but running/abilities still escape.
const DISTANCE_SPEED_SCALE_DENOM: float = 3000.0
const DISTANCE_SPEED_SCALE_MAX: float = 0.6

## Hard ceiling on the final chase speed. The per-croc ±50% roll and the distance
## factor MULTIPLY (worst case 5.5 × 1.5 × 1.6 = 13.2), which would outrun even a
## RUNNING player (RUN_SPEED 10.0 — 9.0 for the slowest character) and silently
## break the "running still escapes" promise above. Capping just under the slowest
## run speed keeps that escape hatch true; the gradient still bites walkers hard.
const MAX_CHASE_SPEED: float = 8.5

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

# ----- Boss crocodiles -----
## Bosses are the rare, huge road-guardian crocodiles the terrain places
## deterministically along the coin road (see endless_terrain.gd). They reuse
## this exact AI wholesale — a boss differs only in a handful of flags set via
## setup_as_boss() below, never in behaviour code.
##
## Boss chase speed: above WALK_SPEED (5.0) so a walking player is run down,
## but the MAX_CHASE_SPEED cap (8.5) keeps it under the slowest RUN (9.0), so
## RUNNING always escapes — the core escape hatch survives.
const BOSS_CHASE_SPEED: float = 7.0

## Boss detection radius: wider "smell" than a regular crocodile so the boss
## reads as a real threat guarding the road. INVARIANT: must stay well below
## the LOD manager's SIM_RADIUS (45.0) — any crocodile that can detect the
## player must always be awake, so near-player behaviour never changes.
const BOSS_DETECTION_RADIUS: float = 25.0

## Visual draw cull: past this distance the crocodile's MESHES stop being drawn
## (visibility_range_end on every GeometryInstance3D in the model subtree). This
## is a pure RENDERING cull — the crocodile entity itself stays alive and counted;
## the LOD manager sleeps its SIMULATION separately at 45/50 m. Entity counts are
## unchanged: nothing is removed, meshes just skip the draw when far away. 60 m is
## deliberately wider than the 50 m sleep radius so a visible crocodile is never a
## frozen-mid-stride sleeper close up, and the universal depth fog hides the pop.
const VISUAL_CULL_DISTANCE: float = 60.0
## Fade margin for the cull boundary (Godot hysteresis band, avoids flicker).
const VISUAL_CULL_MARGIN: float = 8.0

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

## ---------------------------------------------------------------------------
## MULTIPLAYER SYNC (phase 5) — see set_remote_state() for the whole scheme
## ---------------------------------------------------------------------------

## How far a synced sample may land from the body before we SNAP to it instead of
## easing. A master migration, a chunk rebuild or a burst of dropped packets all
## move a crocodile further than one 10 Hz step ever could; without the snap the
## body would take a long serene glide to catch up. Same rule, same reason, as
## RemoteAvatar's TELEPORT_DISTANCE.
const CROC_TELEPORT_DISTANCE: float = 8.0

## Ceiling on the velocity a remote sample may ask for (m/s). The samples already
## passed the manager's decoder, so this is belt-and-braces: it bounds how far one
## bad-but-finite sample can fling the body. Comfortably above MAX_CHASE_SPEED
## (8.5), so honest catch-up after a dropped packet still works.
const CROC_REMOTE_MAX_SPEED: float = 40.0

## How fast a remote-driven crocodile eases toward the synced yaw (per second).
const CROC_REMOTE_TURN_RATE: float = 12.0

## How fast a remote-driven crocodile closes the gap to the latest sample (per
## second). Deliberately the SAMPLE rate (MpManager.CROC_SYNC_HZ), never the frame
## rate: dividing the gap by the frame delta asks for a velocity that lands
## exactly on the sample THIS frame, so the body arrives in one frame and then
## sits at velocity ~0 for the other five — a 10 Hz teleport-and-freeze rather
## than the easing this is documented to do. Worse, `_animate_body` derives its
## stride from `velocity`, so those five frames take the `move_factor < 0.05`
## branch and the crocodile visibly flips between sprinting and idle breathing ten
## times a second on every peer that is NOT the master. Closing over the sample
## period instead gives the same exponential smoothing RemoteAvatar uses, and a
## croc moving at its own top speed asks for its own top speed.
const CROC_REMOTE_INTERP_RATE: float = 10.0

## How near the local player a giant-Teibi crush has to be for it to kick the
## camera (metres). Only ever meaningful in a room, where squash_and_die() also
## runs for a teammate's kill an unknown distance away; a contact crush is a
## couple of metres, so the single-player feel is unchanged.
const CRUSH_SHAKE_RADIUS: float = 6.0

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
## The smell's origin — the "run from here" point whenever the wave did not come
## from the local player (see flee_from), and the fallback when it did but the
## player reference is momentarily missing.
var flee_source: Vector3 = Vector3.ZERO
## Whether this flight tracks the LOCAL player (true: the player's own wave) or
## the fixed `flee_source` (false: a wave relayed from another peer in the room).
var flee_tracks_player: bool = true

## Boss flags, set by the terrain via setup_as_boss() BEFORE this node enters
## the tree (so _ready sees them). A boss skips the per-instance random
## speed/size rolls — its size comes from the deterministic schedule instead.
var is_boss: bool = false
## Uniform body scale for a boss (from the terrain's size schedule; 1.0 = unused).
var boss_scale: float = 1.0

## Deterministic seed for this crocodile's per-instance speed/size rolls, handed
## over by the terrain via setup_roll_seed() BEFORE this node enters the tree —
## the same call-order contract as setup_as_boss(), for the same reason (_ready()
## is where the rolls happen). When it is set, `rng` is seeded from it instead of
## randomize()d, so every peer in a multiplayer session derives the same pack from
## the shared run_seed. When it is NOT set — piglet_crocodile.tscn run standalone,
## or any future spawner that doesn't know about the contract — _ready() falls
## back to rng.randomize() and the crocodile behaves exactly as it always did.
var roll_seed: int = 0
var has_roll_seed: bool = false

## This crocodile's effective "smell" range — the ONE place that resolves the
## regular-vs-boss detection radius. `_update_chase_state` reads it, and so does
## the danger telegraph in `crocodile_lod_manager` (which must normalise each
## chaser's distance by ITS OWN radius: a boss acquires the player at 25 m, so a
## telegraph hardcoded to the regular 15 m would stay dark and silent for the
## first 10 m of the game's biggest threat closing on you). Resolved in _ready()
## because `setup_as_boss()` is contracted to run before the node enters the tree.
var detection_radius: float = DETECTION_RADIUS

## Reference to the player node
var player_node: Node3D = null

## The multiplayer manager, cached once in _find_player() (it is a fixed child of
## Main, so it exists for the whole session and never has to be re-looked-up).
## Null in any scene without it, which is what keeps solo play untouched.
var mp_node: Node = null

## Where this crocodile is currently heading when chasing — the local player, or
## in a room the nearest MEMBER of it. Refreshed by _update_chase_state() every
## frame it runs, read by _chase_player(). See _update_chase_state for why the
## local player alone is not enough.
var chase_target: Vector3 = Vector3.ZERO

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
## possibly matter this frame, so _physics_process is disabled entirely (with a
## cheap-return backstop at its top — see set_lod_active, which is also what makes
## a slept croc harmless). Defaults to TRUE so a crocodile spawned before the manager's
## first scan behaves normally for that brief window (the manager will sleep it on
## its next tick if it's far away). See crocodile_lod_manager.gd for the contract.
var lod_active: bool = true

## ---------------------------------------------------------------------------
## MULTIPLAYER IDENTITY AND REMOTE DRIVE (phase 5)
## ---------------------------------------------------------------------------
## This crocodile's room-wide id, LATCHED IN _ready() from the node name and never
## recomputed — the same contract, for the same reason, as coin.gd's `_id`.
var _croc_id: int = 0

## True while the room MASTER is driving this body (see set_remote_state, the only
## place that turns it on, and clear_remote_drive, the only place that turns it
## off). Always false outside a room, which is what keeps solo play unchanged.
var remote_driven: bool = false
## The last transform the master sent, and whether any sample has arrived yet.
var _remote_pos: Vector3 = Vector3.ZERO
var _remote_yaw: float = 0.0
var _has_remote_sample: bool = false

## When this body last asked the room master to kill it (giant-Teibi crush), in
## `Time.get_ticks_msec()`, or -1 for never.
##
## The master's `dead` broadcast is a round trip, and the body stays alive, solid
## and overlapping the player until it lands — so `_handle_collisions` fires the
## crush again on EVERY physics frame in between, and each one would put another
## RELIABLE packet on the one channel that also carries claims and confirms.
## Latched here rather than in the manager because the request is per-crocodile.
##
## It EXPIRES rather than latching forever, because nothing acknowledges the
## request: `request_croc_kill()` reports only that the packet left. The master's
## own `VERB_BUDGET_PER_SEC` drops `kill` past 10/s per peer SILENTLY, and a
## giant Teibi crossing a dense far-out pack touches more than that in a second —
## so a permanent latch left those crocodiles unable to be crushed AND unable to
## bite (the early return is above the bite path), i.e. immortal harmless
## obstacles for the rest of the run. A stall vote deposing the master mid-round-
## trip, or a channel mid-renegotiation, lose a request the same way.
var _kill_requested_msec: int = -1
## How long to wait for the master's ruling before asking again. Long enough that
## the per-frame re-send this exists to suppress still costs one packet; short
## enough that a dropped request is retried while the player is still standing on
## the crocodile.
const KILL_RETRY_MSEC: int = 1000

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
	# Seed the RNG. The terrain hands every crocodile it spawns a deterministic
	# seed (setup_roll_seed, called before add_child), so the size/speed rolls
	# below — and every other draw this instance ever takes — are a pure function
	# of chunk coords + croc index + run_seed. Only a crocodile spawned WITHOUT
	# that seed (the standalone scene) falls back to a random one.
	if has_roll_seed:
		rng.seed = roll_seed
	else:
		rng.randomize()

	# Difficulty gradient: scale CHASE speed up with distance from the world origin.
	# global_position is already valid here because the terrain parents the crocodile
	# into the chunk BEFORE _ready runs, so |x| is the true spawn distance. Only the
	# chase speed scales — wandering stays lazy everywhere; it's being HUNTED that
	# gets scarier the farther you push. Shared by both branches below so the
	# gradient applies to bosses too.
	var distance_factor := 1.0 + clampf(
		absf(global_position.x) / DISTANCE_SPEED_SCALE_DENOM, 0.0, DISTANCE_SPEED_SCALE_MAX
	)

	if is_boss:
		# Bosses take NO per-instance random rolls: their size comes from the
		# terrain's deterministic schedule (boss_scale) and their speeds are fixed,
		# so a boss regenerates byte-identically when its chunk is revisited.
		detection_radius = BOSS_DETECTION_RADIUS
		move_speed_instance = BASE_MOVE_SPEED
		# The MAX_CHASE_SPEED cap keeps the running-escape hatch true at any distance.
		chase_speed_instance = minf(BOSS_CHASE_SPEED * distance_factor, MAX_CHASE_SPEED)
		scale = Vector3.ONE * boss_scale
	else:
		# Set instance-specific speeds. One shared multiplier drives both speeds, so a
		# "fast" crocodile is fast at everything (and its chase always still outpaces its
		# own wander) instead of the two speeds drifting apart independently.
		var speed_factor := rng.randf_range(1.0 - SPEED_RANDOM_FACTOR, 1.0 + SPEED_RANDOM_FACTOR)
		move_speed_instance = BASE_MOVE_SPEED * speed_factor
		# The min() keeps a top-rolled far croc from outrunning a RUNNING player — see
		# MAX_CHASE_SPEED above.
		chase_speed_instance = minf(BASE_CHASE_SPEED * speed_factor * distance_factor, MAX_CHASE_SPEED)

		# Give this crocodile a randomized overall size. We scale the whole body
		# uniformly so the visual model and the physics capsule grow/shrink together;
		# gravity then settles it onto the ground regardless of size. The model's OWN
		# local scale stays 1, so model_base_scale cached below is unaffected and the
		# procedural body animation composes correctly on top of this body scale.
		var size_scale := rng.randf_range(1.0 - SIZE_RANDOM_FACTOR, 1.0 + SIZE_RANDOM_FACTOR)
		scale = Vector3.ONE * size_scale

	# Set initial random direction
	_choose_new_direction()

	# Latch this crocodile's room-wide id from its (deterministic) node name, before
	# anything downstream can rename the node — see croc_id_for() for the scheme.
	_croc_id = croc_id_for(String(name))

	# Add to "crocodile" group for easy detection
	add_to_group("crocodile")
	add_to_group("enemy")

	# In a multiplayer room, a crocodile the ROOM has already killed (giant Teibi
	# crushed it on some peer and the master confirmed) must not come back when its
	# chunk regenerates here. One failed group lookup per crocodile AT SPAWN, never
	# per frame, and a plain no-op offline — exactly the shape and placement coin.gd
	# uses for is_coin_collected.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp and mp.has_method("is_croc_dead") and mp.is_croc_dead(croc_id()):
		queue_free()
		return

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
		# One walk over the model subtree applies all per-mesh styling (draw
		# cull + shared toon materials).
		_style_model_meshes(model)

	# Find the player node (defer to allow scene to fully load)
	call_deferred("_find_player")


func _style_model_meshes(node: Node) -> void:
	"""
	Recursively apply per-mesh styling to every GeometryInstance3D under the model.

	Two treatments per mesh, one walk:
	- Visual draw-range cull: beyond VISUAL_CULL_DISTANCE the renderer simply
	  skips drawing these meshes (works in gl_compatibility too). This changes
	  RENDERING only — the crocodile body, its AI, and its collision all stay
	  exactly as they were; the LOD manager's sleep radius handles the
	  simulation side independently. Entity counts are never reduced by this.
	- Shared toon+rim styling via ToonShading.apply_to_mesh, so crocs match the
	  hero's cel-shaded look. Its static cache hands every croc the SAME styled
	  material per source, so ~490 bodies add only a handful of materials.
	  Deliberately NO inverted-hull outline overlay here (the player has one):
	  that is a second draw call per mesh × ~490 crocs — unaffordable.
	"""
	if node is GeometryInstance3D:
		# Bosses scale the cull range by their body scale: a 6x boss is visible
		# from ~6x further, so culling it at the regular 60 m would make a
		# mountain of crocodile pop into view. Regular crocs (boss_scale = 1.0)
		# get byte-identical values to before.
		node.visibility_range_end = VISUAL_CULL_DISTANCE * boss_scale
		node.visibility_range_end_margin = VISUAL_CULL_MARGIN * boss_scale
	if node is MeshInstance3D:
		# Bosses get the darker/red-shifted shared variant so they read
		# menacing; both paths cache per SOURCE material, never per body.
		if is_boss:
			ToonShading.apply_boss_to_mesh(node)
		else:
			ToonShading.apply_to_mesh(node)
	for child in node.get_children():
		_style_model_meshes(child)


func _physics_process(delta: float) -> void:
	"""Update movement, body animation and collisions every physics frame."""
	# ------------------------------------------------------------------------
	# REMOTE DRIVE (multiplayer phase 5) — ABOVE the LOD backstop on purpose
	# ------------------------------------------------------------------------
	# In a room the master simulates every awake crocodile and broadcasts its
	# transform at 10 Hz; every other peer renders that instead of running its own
	# AI, so the whole room sees one crocodile in one place. This sits above the
	# lod_active backstop because a remote-driven crocodile is by definition near
	# SOME peer and must keep moving even in the window before this peer's own LOD
	# bookkeeping has caught up with that.
	if remote_driven:
		_tick_remote(delta)
		return

	# ------------------------------------------------------------------------
	# LOD SLEEP GATE (simulation level-of-detail) — BACKSTOP ONLY
	# ------------------------------------------------------------------------
	# Normally this never runs while asleep: set_lod_active(false) disables the
	# _physics_process callback entirely via set_physics_process(false), so a
	# slept crocodile costs zero script dispatches per tick. This early-return is
	# kept purely as a defensive backstop — if anything ever re-enables physics
	# processing on a slept crocodile, we still freeze in place (zero velocity,
	# no move_and_slide, no gravity — a distant croc was already standing on the
	# terrain, and skipping gravity is what keeps it perfectly put) instead of
	# half-simulating. Every other piece of state (heading, chase flags, phases,
	# confinement) is preserved untouched, so waking resumes seamlessly.
	if not lod_active:
		velocity = Vector3.ZERO
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# Snapshot BEFORE the branch below, which can clear is_paused mid-frame. The
	# collision check after move_and_slide must judge the frame we actually just
	# simulated: on the frame a pause expires the crocodile still stood perfectly
	# still, so handling collisions there would re-arm the bite a frame early and
	# defeat the point of _pause_and_change_direction's recovery window.
	var was_paused: bool = is_paused

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
	if not was_paused:
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
	"""Find and store reference to the player node (plus the MP manager, if any)."""
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_node = players[0]
	# Cached once, group-based and null-safe like every other cross-system lookup
	# in this project — a scene run without Main simply leaves it null and every
	# read below falls through to the single-player behaviour.
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("nearest_member_position"):
		mp_node = mp


func _update_chase_state() -> void:
	"""Check distance to the nearest quarry and update chase state."""
	if not player_node:
		is_chasing = false
		return

	# Check if the local player is grounded (can be smelled).
	# If the player jumps (is not on floor), crocodiles lose the scent.
	var player_is_grounded = true
	if player_node.has_method("is_on_floor"):
		player_is_grounded = player_node.is_on_floor()

	# Nearest SMELLABLE quarry, not nearest quarry — the two candidates are judged
	# INDEPENDENTLY. Letting the nearest one's groundedness stand for both means
	# one airborne peer vetoes the scent of a grounded teammate standing right
	# beside it, and on the master (which simulates the pack for everybody) that is
	# one player bunny-hopping to call every crocodile in range off their friend.
	chase_target = player_node.global_position
	var distance_to_player: float = INF
	if player_is_grounded:
		distance_to_player = global_position.distance_to(chase_target)

	# IN A ROOM, "the player" means "the nearest MEMBER of the room". The master
	# simulates every awake crocodile for everybody, and by the isolation contract
	# a remote peer is a RemoteAvatar in NO group — so a crocodile that resolves
	# its quarry through group "player" alone can only ever hunt whoever happens
	# to be master, and the other one to three peers walk through the pack
	# untouched on every screen. Offline `nearest_member_position` answers null
	# and this whole block is skipped, so single-player is byte-for-byte unchanged.
	#
	# The bite still lands correctly with no protocol: the crocodile is
	# remote-driven on the quarry's own machine, where _tick_remote runs
	# move_and_slide + _handle_collisions against a real local player body.
	#
	# ponytail: a remote member is always treated as smellable — presence carries
	# an on-floor bit but peer_positions()/nearest_member_position() do not, so the
	# "jumping breaks the scent" escape hatch stays local-only. Thread `g` through
	# the manager if that asymmetry ever matters.
	if mp_node != null:
		var remote: Variant = mp_node.nearest_member_position(global_position)
		if remote != null:
			# A remote member is always smellable (see the ponytail note above), so
			# it is a candidate unconditionally — which is also what makes it able
			# to win when the local player is mid-jump and therefore not one.
			var remote_distance: float = global_position.distance_to(remote as Vector3)
			if remote_distance < distance_to_player:
				distance_to_player = remote_distance
				chase_target = remote as Vector3

	# Update chase state based on detection radius. `distance_to_player` is INF
	# when nothing is smellable, so the grounded rule is folded into this one test.
	# Bosses smell farther (still well under the LOD SIM_RADIUS — see the const);
	# `detection_radius` is resolved once in _ready(), see the var.
	if distance_to_player <= detection_radius:
		if not is_chasing:
			# Just started chasing
			is_chasing = true
			# Bosses announce themselves with a growl on the not-chasing →
			# chasing transition (null-safe group lookup, like every SFX hook —
			# a scene run without Main just stays silent).
			if is_boss:
				var sm := get_tree().get_first_node_in_group("sound_manager")
				if sm and sm.has_method("play_boss_growl"):
					sm.play_boss_growl()
	else:
		if is_chasing:
			# Lost the player (too far OR player jumped)
			is_chasing = false
			# Choose new random direction
			_choose_new_direction()


func _chase_player() -> void:
	"""Set movement direction toward whatever _update_chase_state picked."""
	if not player_node:
		return

	# Calculate direction to the quarry (on XZ plane). `chase_target` is the local
	# player's position solo, and in a room the nearest member's — see
	# _update_chase_state; it is only ever read on a frame that function just set it.
	var direction_to_player = chase_target - global_position
	direction_to_player.y = 0  # Keep movement on horizontal plane
	movement_direction = direction_to_player.normalized()


func _flee() -> void:
	"""
	Run directly AWAY from the player (Phoboman's stink). Falls back to the
	remembered smell origin if the player reference is momentarily missing, and to
	the current heading if we somehow sit right on top of the source.
	"""
	var away := Vector3.ZERO
	if player_node and flee_tracks_player:
		away = global_position - player_node.global_position
	else:
		# `flee_tracks_player` false means the smell came from SOMEBODY ELSE'S
		# screen (MpManager relayed it to the master). The local player is then
		# the wrong reference entirely — running from it would herd the pack
		# straight at the peer who cast the wave — so the remembered origin is
		# the only correct one. See flee_from().
		away = global_position - flee_source
	away.y = 0.0

	if away.length() < 0.01:
		away = Vector3(sin(wander_heading), 0.0, cos(wander_heading))

	movement_direction = away.normalized()
	# Keep the wander heading in sync so obstacle-avoidance steering composes
	# cleanly and the croc holds its escape course instead of curving back.
	wander_heading = atan2(movement_direction.x, movement_direction.z)


func flee_from(source: Vector3, duration: float, tracks_player: bool = true) -> void:
	"""
	Public hook called by Phoboman's Stink Wave (via the "crocodile" group): make
	this crocodile turn tail and run from the player for `duration` seconds. Drops
	any current chase. `source` is the smell's origin.

	`tracks_player` is what makes the source mean something. Solo — and for the
	local player's own wave — it stays true and the flight tracks the player as it
	always has. A wave RELAYED from another peer passes false, because the master
	applying it has no body for the caster: `_flee()` would otherwise run every
	crocodile away from the MASTER's player, i.e. straight toward the peer who
	actually cast it, and `player_controller.clear_nearby_crocodiles()` would herd
	the pack onto a respawning teammate instead of off them.
	"""
	# Bosses shrug the stink off. They KEEP group "crocodile" membership — the
	# wave still finds them, they just don't care; immunity lives here, not in
	# group tricks (so LOD sleep and every other group consumer stays intact).
	if is_boss:
		return
	# A SLEPT croc ignores the stink too, and that is a correctness rule, not a
	# nicety: set_lod_active(false) turns physics dispatch off, so its
	# flee_time_remaining can never tick down. It would hold is_fleeing until it
	# woke and then flee for the FULL duration — one press would leave every
	# crocodile in every loaded chunk (~1000 of them) harmless-on-wake for as
	# long as the player keeps advancing. A slept croc is > 50 m away (see
	# SIM_RADIUS in crocodile_lod_manager); no smell reaches that far anyway.
	if not lod_active:
		return
	# NOT guarded on remote_driven, and that is deliberate — do not "fix" it. A
	# remote-driven crocodile takes its motion (and its flee flag) from the
	# master's samples, so setting the flag here is harmless: the next sample
	# overwrites it. Meanwhile the master, whose own crocodiles are never
	# remote-driven, gets the real flee from this very call — see
	# MpManager.request_croc_flee.
	is_fleeing = true
	flee_time_remaining = duration
	flee_source = source
	flee_tracks_player = tracks_player
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

	# Both probe dimensions SCALE WITH THE BODY (inert at scale 1, i.e. for every
	# regular crocodile). _ready() sets `scale = ONE * boss_scale` for a boss, so a
	# 6x boss's capsule alone reaches 0.7 * 6 = 4.2 m ahead of its origin — past the
	# fixed 3 m world-space feeler, leaving avoidance completely dead from boss 4 on
	# (useful reach 1.25 m, 0.64 m, 0.03 m, 0, 0 …) against a body that is also 6x
	# wider and needs MORE clearance. The height likewise has to rise, or a big boss
	# samples the ground at its own feet instead of a block's side wall.
	var probe_scale := maxf(scale.x, scale.z)
	var origin := global_position + Vector3(0.0, AVOID_FEELER_HEIGHT * scale.y, 0.0)
	var reach := AVOID_LOOK_AHEAD * probe_scale
	var forward := movement_direction.normalized()

	# Nothing straight ahead? Then there's nothing to steer around.
	if not _feeler_blocked(space, origin, forward, reach):
		return false

	# Probe both sides and pick a clear way around.
	var left_dir := forward.rotated(Vector3.UP, AVOID_FEELER_ANGLE)
	var right_dir := forward.rotated(Vector3.UP, -AVOID_FEELER_ANGLE)
	var left_blocked := _feeler_blocked(space, origin, left_dir, reach)
	var right_blocked := _feeler_blocked(space, origin, right_dir, reach)

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


func _feeler_blocked(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, reach: float) -> bool:
	"""
	Cast one feeler ray and report whether a *block* sits within `reach`.
	The player, other crocodiles and the (horizontal) ground are not blocks.

	@param space: The physics space to query
	@param origin: Ray start, already lifted to feeler height
	@param dir: Direction to probe (need not be normalized)
	@param reach: Ray length — AVOID_LOOK_AHEAD scaled by the body (see _avoid_obstacles)
	@return true if the ray hits something we should steer around
	"""
	# OUR OWN MASK, not `create()`'s default of all 32 layers. Fauna roots are
	# `AnimatableBody3D` bodies on layer 3 which crocodiles deliberately do not
	# mask (mask 3 = layers 1+2), and they are in no group, so the group test
	# below cannot reject them. Ordinary crocodiles are saved only by geometry —
	# the feeler sits at 0.28-0.43 m, under every deck — but `_avoid_obstacles`
	# scales both probe dimensions by the body, so a boss at scale >= 3.375 lifts
	# it to 1.1 m+ and starts swerving away from, and cutting speed for, a pack
	# beast it cannot touch.
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + dir.normalized() * reach, collision_mask
	)
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

	What actually keeps a sleeping crocodile from harming the player is that its
	physics step never runs: set_physics_process(false) below stops the engine from
	dispatching _physics_process at all, which means the crocodile never runs
	move_and_slide nor _handle_collisions — and _handle_collisions (reading
	get_slide_collision()) is the ONLY code path that calls player.reset_position().
	So a slept crocodile is harmless; no contact damage can occur.

	Why set_physics_process instead of relying only on the early-return inside
	_physics_process? With ~460 slept crocodiles, even a cheap-return still costs
	~460 script dispatches (engine→GDScript call overhead) every physics tick.
	Disabling the callback removes those dispatches entirely; the early-return
	stays in _physics_process purely as a backstop in case something else ever
	re-enables processing on a slept crocodile.

	We still zero velocity here (not just in the backstop) so the freeze is
	immediate — the body holds exactly its current spot from this frame on.
	"""
	# No-op if nothing actually changed (defensive; the manager already guards this).
	if active == lod_active:
		return

	# REFUSE to sleep a crocodile that has not landed yet. The terrain spawns crocs
	# ABOVE the ground (local y 0.5 on the ground, +0.6 over a platform) and lets
	# gravity settle them, but every chunk outside the synchronous ring is built
	# ≥100 m away — so the manager's next scan (≤ SCAN_INTERVAL 0.11 s later, ~0.06 m
	# of fall) would sleep them mid-air, and sleeping stops gravity FOREVER. The
	# whole pack would hang ~0.44 m up until the player closed to SIM_RADIUS, and
	# the draw cull (60 m) is deliberately WIDER than the sleep radius (45/50 m), so
	# the floaters would be visibly drawn. The manager re-reads `lod_active` every
	# scan and re-issues the call while the states disagree, so refusing here just
	# costs a few extra calls until the body is on the floor.
	if not active and not is_on_floor():
		return

	lod_active = active

	# Stop (or resume) the per-tick physics callback itself. Asleep → the engine
	# never calls _physics_process on this crocodile, saving the script dispatch.
	set_physics_process(active)
	if not active:
		velocity = Vector3.ZERO
		# Drop any flee state on the way down. flee_time_remaining is decremented
		# ONLY in _physics_process, which we just switched off — so a croc slept
		# mid-flee would hold is_fleeing (and stay harmless on contact) for its
		# whole sleep, which is the exact failure flee_from's own slept-croc guard
		# exists to prevent, reached from the other direction: Stink Wave, then Air
		# Rush across the 50 m sleep boundary.
		is_fleeing = false
		flee_time_remaining = 0.0


# ============================================================================
# MULTIPLAYER SYNC (phase 5)
# ============================================================================

static func croc_id_for(node_name: String) -> int:
	"""
	This crocodile's room-wide id, derived from its NODE NAME alone.

	Every crocodile the terrain spawns is named deterministically BEFORE add_child
	from data that is a pure function of chunk coords + run_seed
	(`Crocodile_<cx>_<cy>_<index>`, `PatrolCrocodile_<cx>_<cy>_<count>`,
	`BossCrocodile_<index>`), so two peers sharing a run_seed put the SAME
	crocodile, under the SAME name, in the same place. The name therefore
	identifies it across the room — which is why not one line of
	endless_terrain.gd has to change. Exactly the reasoning, and exactly the
	shape, of Coin.id_at().

	ponytail: two ceilings, both cosmetic by construction. (1) A crocodile spawned
	OUTSIDE the terrain (the standalone piglet_crocodile.tscn, or a future
	spawner) has a non-unique name and could collide with another's id; it never
	happens in a room, and the failure mode is one crocodile following another's
	transform, not a crash. (2) String.hash() is 32-bit, so a collision across the
	~1000 loaded crocodiles is a ~1e-4 birthday chance per run. The upgrade path
	for both is the coin id's: thread an explicit (chunk, index) id out of the
	spawners.

	SIGN-EXTENDED TO int32, AND THAT IS LOAD-BEARING, NOT TIDINESS. String.hash()
	is an unsigned 32-bit value widened into a GDScript int, so it runs to 2^32-1
	— but mp_manager ships these ids in the sync packet's PackedInt32Array ("i"),
	which stores int32_t. Every id above INT32_MAX therefore WRAPPED NEGATIVE in
	transit, missed the receiver's `_synced_crocs` lookup (whose keys were the
	unwrapped values), and landed on the deliberately-silent "this peer has not
	generated that chunk" path. Measured over the real name scheme, 43% of
	crocodiles hash above INT32_MAX — so nearly half the pack was silently never
	synced, fell back to local simulation after CROC_SYNC_TIMEOUT and drifted, in
	the one code path engineered to say nothing. Sign-extending here (rather than
	widening the packet) keeps sender, receiver, `_dead_crocs` and `_synced_crocs`
	all naming a crocodile by the same number, at zero bandwidth.
	"""
	var h: int = node_name.hash()
	return h - 4294967296 if h > 2147483647 else h


func croc_id() -> int:
	"""This crocodile's room-wide id. Valid from _ready on — the name is latched
	once there and never recomputed (see _croc_id), so nothing that touches the
	node later can quietly rename this crocodile mid-run."""
	return _croc_id


func set_remote_state(pos: Vector3, yaw: float, flags: int) -> void:
	"""
	Overlay the MASTER's simulation of this crocodile onto this local body.

	The sync layer never creates, re-parents or frees a crocodile: crocs stay
	chunk-parented, per-peer, deterministic and freed on chunk unload exactly as
	in single player. This only overlays DYNAMIC state onto a node that already
	exists here, matched by croc_id(); a sample naming a crocodile this peer has
	not generated is dropped by the manager before it ever reaches this method.

	This is the ONLY place remote_driven is turned on. The first sample — and any
	sample further than CROC_TELEPORT_DISTANCE from where the body currently
	stands — SNAPS; everything else is eased in _tick_remote, so 10 Hz samples
	read as smooth motion at 60 fps.

	@param flags: the state byte, decoded with MpManager.CROC_FLAG_* so the
	    encoder and this decoder cannot drift. Biting goes through _start_bite()
	    rather than a raw assignment, so the chomp gets its usual timer and the
	    local animation clears it — a flag that only ever says "started".
	"""
	# A body already dying (squash_and_die leaves the group and stops physics) is
	# never driven again — the sample forcing processing back on below would
	# otherwise walk a corpse through its own squash tween, still solid and still
	# able to bite. The manager erases a killed id from its cache, so this only
	# catches a sample that was already in flight.
	if not is_in_group("crocodile"):
		return

	_remote_pos = pos
	_remote_yaw = fposmod(yaw, TAU)

	is_chasing = (flags & MpManager.CROC_FLAG_CHASING) != 0
	is_fleeing = (flags & MpManager.CROC_FLAG_FLEEING) != 0
	is_paused = (flags & MpManager.CROC_FLAG_PAUSED) != 0
	if (flags & MpManager.CROC_FLAG_BITING) != 0:
		_start_bite()

	if not _has_remote_sample or global_position.distance_to(pos) > CROC_TELEPORT_DISTANCE:
		global_position = pos
		rotation.y = _remote_yaw
		velocity = Vector3.ZERO

	_has_remote_sample = true
	remote_driven = true

	# TURN THE PHYSICS CALLBACK BACK ON. A crocodile the LOD manager had already
	# put to sleep has had set_physics_process(false) called on it, so
	# _tick_remote() — which lives at the top of _physics_process — would never
	# run: the body would jump CROC_TELEPORT_DISTANCE at a time on the snap
	# branch above, never animate, and (the sharp part) never reach
	# move_and_slide/_handle_collisions, so it would be neither solid nor able to
	# bite. That last one breaks the rule this whole phase is specified against —
	# the BITTEN peer detects its own bite locally.
	#
	# It is not an edge case: the master syncs every crocodile within
	# CROC_SYNC_RADIUS (55 m) of a peer, while that peer's own LOD sleeps anything
	# past SIM_RADIUS + HYSTERESIS_MARGIN (50 m), so the 50–55 m band is exactly
	# this. `lod_active` is deliberately left alone — the sync layer owns the
	# processing switch only while it is driving, and clear_remote_drive() hands
	# it straight back to whatever the LOD manager last decided.
	set_physics_process(true)


func clear_remote_drive() -> void:
	"""
	Hand this crocodile back to its own local AI, from wherever the body now
	stands. Called when the master's samples stop arriving (the sync timeout — the
	master is too far away to have this chunk loaded, or the room ended) and when
	THIS peer is promoted to master.

	Promotion is seamless precisely because a synced crocodile is a real local
	node holding the master's last known transform: dropping the flag resumes
	simulation from that exact spot, so the whole pack is a hot standby replica
	for free.
	"""
	if not remote_driven:
		return
	remote_driven = false
	_has_remote_sample = false
	# Same guard, same reason, as set_remote_state(): a body already dying
	# (squash_and_die left the group and stopped physics) must not have physics
	# handed back to it. It can still be remote-driven here — a local crush runs
	# when request_croc_kill() could not reach the master, so no `dead` broadcast
	# erases us from the manager's cache — and the set_physics_process below would
	# then walk the corpse through its own squash tween under the FULL LOCAL AI,
	# solid and able to bite.
	if not is_in_group("crocodile"):
		return
	velocity = Vector3.ZERO
	# Hand the physics switch back to the LOD manager's last decision. While we
	# were remote-driven set_remote_state() forced processing ON regardless of
	# `lod_active` (see there); leaving it on for a crocodile the manager thinks is
	# asleep would silently un-sleep it — and it would not sleep again, because
	# set_lod_active() no-ops when the state already matches.
	set_physics_process(lod_active)


func squash_and_die() -> void:
	"""
	Die the giant-Teibi death: physics stops, a dust puff pops, a crunch plays,
	the nearby player's camera gets a tiny kick, and the body squashes flat before
	freeing itself.

	Public because in a multiplayer room the crush is arbitrated by the master, so
	this has to be runnable from `mp_manager._apply_dead()` on a peer where nobody
	touched this crocodile at all — a crush must READ as a crush on every screen,
	not as a crocodile blinking out. Idempotent: a second call finds us already out
	of the "crocodile" group and returns.
	"""
	if not is_in_group("crocodile"):
		return
	print("🐊 Squashed by a giant!")
	# Guard re-entry FIRST: stop physics and leave the "crocodile" group so
	# the dying body can't crush-trigger a second time (or be found by the
	# stink wave / danger telegraph / croc sync) during the short squash tween.
	set_physics_process(false)
	remove_from_group("crocodile")
	# Dust puff at the body, parented to the croc's PARENT (the chunk) so it
	# outlives this node — the same self-freeing wave pattern as the coin pop.
	var fx_parent := get_parent()
	if fx_parent:
		var fx := MeshInstance3D.new()
		fx.set_script(preload("res://scripts/ability_effect.gd"))
		fx_parent.add_child(fx)
		fx.global_position = global_position
		fx.setup(Color(0.75, 0.7, 0.6, 0.5), 1.8, 0.3)
	# Crunch sound + a small nudge on the player's camera shake (both null-safe,
	# matching the project's group-lookup convention).
	var sound_manager := get_tree().get_first_node_in_group("sound_manager")
	if sound_manager and sound_manager.has_method("play_crunch"):
		sound_manager.play_crunch()
	# The shake is RANGE-GATED, which it did not have to be when this only ever ran
	# on the crushing player's own screen: in a room a teammate's kill three chunks
	# away arrives here as a "dead" packet, and jolting the camera for a crocodile
	# nobody can see reads as a bug. Contact crushes are metres away, so the local
	# case is unchanged.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D and "shake_amount" in player \
			and global_position.distance_to((player as Node3D).global_position) <= CRUSH_SHAKE_RADIUS:
		player.shake_amount = maxf(player.shake_amount, 0.15)
	# Squash flat, then free — the TWEEN owns the queue_free. A tween dies
	# with its node, so a chunk unloading mid-squash frees us safely anyway.
	var squash := create_tween()
	squash.tween_property(self, "scale:y", scale.y * 0.15, 0.12)
	squash.tween_callback(queue_free)


func _tick_remote(delta: float) -> void:
	"""
	Drive the body toward the master's latest sample for one physics frame.

	move_and_slide() here is DELIBERATE, not incidental: it is what keeps a synced
	crocodile SOLID to the player, and what makes the BITTEN peer detect its own
	bite locally through _handle_collisions — which is the bite rule this whole
	phase is specified against ("the bite is decided by the peer being bitten, on
	its own machine"). Never replace it with a direct global_position write.
	"""
	# Velocity that closes the gap over one SAMPLE period, not one frame — see
	# CROC_REMOTE_INTERP_RATE for why the frame delta is the wrong divisor.
	# Clamped so one bad-but-finite sample cannot launch the body across the map.
	var wanted: Vector3 = (_remote_pos - global_position) * CROC_REMOTE_INTERP_RATE
	if wanted.length() > CROC_REMOTE_MAX_SPEED:
		wanted = wanted.normalized() * CROC_REMOTE_MAX_SPEED
	velocity = wanted

	rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(delta * CROC_REMOTE_TURN_RATE, 1.0))

	move_and_slide()
	# GATED ON is_paused, exactly as the local path gates on `was_paused`. The
	# pause IS _pause_and_change_direction's post-bite recovery window, and the
	# master ships it in the sample's CROC_FLAG_PAUSED bit precisely so every peer
	# knows this crocodile is standing down. Ungated, a synced crocodile kept
	# re-triggering _on_player_collision throughout a pause the master treats as
	# harmless — so the peer it had just bitten could be bitten again the instant
	# its respawn i-frames lapsed, i.e. bites were strictly harsher for everyone
	# who is not the master, which is the opposite of what the sync is for.
	if not is_paused:
		_handle_collisions()

	# Animate from the speed we actually moved at, exactly like the local path.
	_animate_body(delta)


# ============================================================================
# BOSS SETUP
# ============================================================================

func setup_as_boss(body_scale: float) -> void:
	"""
	Mark this crocodile as a road-guardian BOSS. CALL-ORDER CONTRACT: the terrain
	must call this on the fresh instance BEFORE add_child() — _ready() branches on
	these flags (skipping the random speed/size rolls and applying the scale), so
	setting them after the node enters the tree would be too late.

	@param body_scale: Uniform body scale from the terrain's deterministic
	    size schedule (2.5x and up — always bigger than any regular croc's roll)
	"""
	is_boss = true
	boss_scale = body_scale


func setup_roll_seed(seed_value: int) -> void:
	"""
	Hand this crocodile the deterministic seed for its per-instance speed/size
	rolls. CALL-ORDER CONTRACT, exactly like setup_as_boss above: the terrain must
	call this on the fresh instance BEFORE add_child(), because _ready() is where
	the rolls happen — seeding after the node enters the tree would be too late and
	the crocodile would already have randomize()d itself.

	Bosses may be given a seed too; it simply goes unused, since the is_boss branch
	in _ready() takes no size/speed roll at all.

	@param seed_value: Seed from the terrain's independent croc-roll hash stream
	    (see endless_terrain._croc_roll_seed)
	"""
	roll_seed = seed_value
	has_roll_seed = true


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
		# Put the model back on the capsule's centreline. _animate_body only ever
		# writes position.y, so without this the last drawn lunge frame (~3.6 cm
		# of forward +Z) would stay baked into the model FOREVER — every crocodile
		# that has ever bitten drifts permanently ahead of its own collider.
		model.position = Vector3(0.0, model_base_y, 0.0)
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
	# A BOSS is bigger than even giant-form Teibi (2.5x+ vs the giant scale), so
	# giant form gets bitten like anyone else — bosses are never crushable. This
	# early check sits ABOVE the crush block so that block stays untouched.
	# ponytail: the few bite lines below are duplicated from the normal path on
	# purpose — a shared helper would tangle this with the crush block another
	# change owns; fold them together once that settles.
	if is_boss:
		print("💀 BOSS crocodile bites the player!")
		_start_bite()
		if player.has_method("hit_by_crocodile"):
			player.hit_by_crocodile()
		elif player.has_method("reset_position"):
			player.reset_position()
		_pause_and_change_direction()
		return

	# Giant Teibi squashes crocodiles on contact instead of being bitten.
	# Instead of vanishing in one frame, the croc visibly dies: physics stops,
	# a dust puff pops, a crunch plays, the player's camera gets a tiny kick,
	# and the body squashes flat before freeing itself.
	if player.has_method("crushes_crocodiles") and player.crushes_crocodiles():
		# In a ROOM the kill belongs to the master, not to whichever screen it
		# happened on: it has to free the SAME crocodile on every peer. The manager
		# answers true when it is in a room and has relayed the request, and we then
		# return WITHOUT squashing — the master's kill broadcast frees this body
		# everywhere, including here. Offline, or with no manager in the scene, it
		# answers false and the squash below runs byte-for-byte unchanged.
		var now_msec: int = Time.get_ticks_msec()
		if _kill_requested_msec >= 0 and now_msec - _kill_requested_msec < KILL_RETRY_MSEC:
			return  # Already asked; waiting on the master's ruling. See the var.
		var mp := get_tree().get_first_node_in_group("mp")
		if mp and mp.has_method("request_croc_kill") and mp.request_croc_kill(croc_id()):
			_kill_requested_msec = now_msec
			return
		squash_and_die()
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
