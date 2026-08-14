extends Node
## Central simulation/animation LOD (Level-of-Detail) Manager.
##
## Historically this managed only crocodiles (the node keeps its
## CrocodileLODManager name for history), but it is now the small central home
## for BOTH cheap distance-based LOD gates: crocodile *simulation* sleep (below)
## and coin *animation* freezing (`_scan_coins` — distant coins stop paying for
## their per-frame spin/bob `_process`; collection is Area3D-signal driven, so a
## frozen coin still collects normally).
##
## This is Task 3 of the web-performance-optimization plan. The world spawns a
## LOT of crocodiles (roughly one thousand active across the loaded chunks), and
## every one of them runs a full physics+AI step every frame — gravity, chase
## scanning, obstacle-avoidance raycasts, move_and_slide and body animation.
## The overwhelming majority of those crocodiles are
## nowhere near the player and could never affect the game this frame, yet they
## cost the same as the few that matter. That wasted CPU/physics work is the main
## cause of the in-browser stutter.
##
## "LOD" here is a *simulation* LOD, not a visual one: instead of dropping a
## distant crocodile's mesh detail, we drop its *behaviour* detail. A crocodile
## that is far from the player is put to sleep — it freezes in place and stops
## paying for AI, movement and collision — while a crocodile near the player runs
## exactly as it always did.
##
## ----------------------------------------------------------------------------
## Why this is GAMEPLAY-NEUTRAL (the important part)
## ----------------------------------------------------------------------------
## A crocodile can only interact with the player at all when the player is within
## its DETECTION_RADIUS (15 m — it starts chasing) or physically touching it. So
## as long as we keep *fully simulating* every crocodile that the player could
## possibly come into contact with, sleeping the rest changes nothing the player
## can observe. We therefore pick a SIM_RADIUS that is comfortably LARGER than
## DETECTION_RADIUS (see below). Any crocodile inside SIM_RADIUS behaves
## byte-for-byte as before; only crocodiles well beyond the player's reach are
## frozen, and they thaw seamlessly the moment the player gets close.
##
## ----------------------------------------------------------------------------
## How it works
## ----------------------------------------------------------------------------
## This node is added once to main.tscn. It does NOT hold a hard reference to the
## player or to any crocodile — it follows the project's group-based discovery
## convention: the player is found via the "player" group, and crocodiles via the
## "crocodile" group (the exact group endless_terrain.gd spawns them into). On a
## throttled tick (a few times a second, NOT every frame), it measures each
## crocodile's squared distance to the player and flips that crocodile's
## `lod_active` flag through its `set_lod_active()` setter. The crocodile script
## reads that flag and cheap-returns the heavy work while asleep.

# ============================================================================
# CONSTANTS
# ============================================================================

## Radius (metres) within which a crocodile is fully simulated. This MUST exceed
## the crocodile's DETECTION_RADIUS (15 m) by a comfortable buffer: a crocodile
## right at the edge of detection is already interacting with the player, and the
## player can move toward it between our throttled scans, so we want a generous
## margin to guarantee that anything that could *become* relevant is already awake
## and running normally. 45 m is 3× the detection radius — far more than enough
## that no crocodile the player could reach is ever asleep, while still letting
## the vast field of distant crocodiles sleep. Tune larger if you ever see a
## crocodile "pop" into motion noticeably late.
const SIM_RADIUS: float = 45.0

## Hysteresis margin (metres). To avoid a crocodile flickering between awake and
## asleep when it sits right on the SIM_RADIUS boundary, we use two thresholds:
## a crocodile must come within SIM_RADIUS to *wake up*, but only goes back to
## sleep once it is beyond SIM_RADIUS + this margin. The small dead-band in
## between keeps already-awake crocodiles awake, so a body hovering near the
## edge doesn't toggle every scan.
const HYSTERESIS_MARGIN: float = 5.0

## How often (seconds) we run the scan. We deliberately do NOT scan every frame:
## iterating ~1,000 crocodiles every frame would itself burn the CPU we are
## trying to save, and the player simply can't cross the SIM_RADIUS buffer in a
## fraction of a second, so ~9 Hz is plenty responsive. (1/0.11s ≈ 9 scans/sec.)
const SCAN_INTERVAL: float = 0.11

# ============================================================================
# DERIVED CONSTANTS
# ============================================================================
# We compare SQUARED distances throughout so we never pay for a square root on
# every crocodile every scan. The two thresholds below are the squared forms of
# the wake/sleep radii described above.

## Squared distance at/under which a sleeping crocodile WAKES (enters SIM_RADIUS).
const WAKE_DISTANCE_SQ: float = SIM_RADIUS * SIM_RADIUS

## Squared distance beyond which an awake crocodile goes back to SLEEP
## (SIM_RADIUS + HYSTERESIS_MARGIN). The gap between this and WAKE_DISTANCE_SQ is
## the anti-flicker dead-band.
const SLEEP_DISTANCE_SQ: float = (SIM_RADIUS + HYSTERESIS_MARGIN) * (SIM_RADIUS + HYSTERESIS_MARGIN)

# ============================================================================
# COIN ANIMATION GATING
# ============================================================================
# Coins run a per-frame `_process` (spin + bob) purely for looks. At 30 m+ that
# motion is invisible, so we `set_process(false)` on far coins and re-enable it
# as the player approaches — the same throttled-scan + hysteresis + only-on-
# state-change discipline as the crocodile pass above. Nothing about collection
# changes: pickup is driven by the Area3D `body_entered` signal, which fires
# regardless of `_process`, and collision layers/masks are untouched.

## Radius (metres) within which a coin animates. Far smaller than SIM_RADIUS —
## a coin has no behaviour to preserve, only a visual flourish nobody can see
## from 30 m away.
const COIN_ANIM_RADIUS: float = 30.0

## Same anti-flicker dead-band idea as HYSTERESIS_MARGIN: animate within 30 m,
## freeze only beyond 35 m.
const COIN_HYSTERESIS: float = 5.0

## Squared thresholds (avoid sqrt per coin per scan, as with the croc pass).
const COIN_WAKE_DISTANCE_SQ: float = COIN_ANIM_RADIUS * COIN_ANIM_RADIUS
const COIN_FREEZE_DISTANCE_SQ: float = (COIN_ANIM_RADIUS + COIN_HYSTERESIS) * (COIN_ANIM_RADIUS + COIN_HYSTERESIS)

# ============================================================================
# STATE
# ============================================================================

## Cached player reference. Looked up via the "player" group and re-fetched if it
## ever becomes invalid (we stay defensive — the player node persists across a
## respawn, but a future change could replace it). Never a hard scene-path ref.
var _player: Node3D = null

## Seconds left until the next scan (counts down each frame).
var _time_until_scan: float = 0.0


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Find the player once up front; if it isn't ready yet (scene still loading),
	# the scan loop will keep trying until it appears.
	_find_player()
	# Run the first scan immediately so distant crocodiles are slept right away
	# instead of all running for the first fraction of a second.
	_time_until_scan = 0.0


func _process(delta: float) -> void:
	# Throttle: only do the (relatively expensive) group scan a few times a second.
	# Every other frame this function does almost nothing, so the manager itself is
	# effectively free.
	_time_until_scan -= delta
	if _time_until_scan > 0.0:
		return
	_time_until_scan = SCAN_INTERVAL

	_scan_crocodiles()
	_scan_coins()


# ============================================================================
# CORE
# ============================================================================

func _find_player() -> void:
	## Locate the player through the "player" group (group-based discovery, never a
	## hard $-path or exported reference — matches the rest of the codebase).
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_player = player
	else:
		_player = null


func _scan_crocodiles() -> void:
	## One LOD pass: decide, for every crocodile, whether it should be awake
	## (fully simulating) or asleep (frozen), and tell it only when that decision
	## actually changes — so we never spam the setter every tick.

	# Be defensive about the player ref: it can go stale if the player node is
	# ever freed/replaced. If we don't have a valid one, try to (re)acquire it.
	if not is_instance_valid(_player):
		_find_player()
		if not is_instance_valid(_player):
			# Still no player (scene mid-load). Skip this scan; we'll try again on
			# the next tick. We do NOT touch any crocodile without a player to
			# measure against.
			return

	var player_pos: Vector3 = _player.global_position

	for croc in get_tree().get_nodes_in_group("crocodile"):
		# Skip anything that isn't a live Node3D (e.g. queued for deletion).
		if not is_instance_valid(croc) or not (croc is Node3D):
			continue
		# We drive LOD purely through the crocodile's own setter, so a crocodile
		# that doesn't implement it (a different enemy type that happened to join
		# the group) is simply left alone — never crash on a missing method.
		if not croc.has_method("set_lod_active"):
			continue

		# Squared distance is enough to compare against our squared thresholds, and
		# avoids a sqrt per crocodile per scan.
		var dist_sq: float = croc.global_position.distance_squared_to(player_pos)

		# Read the crocodile's current LOD state so we can apply hysteresis and
		# only call the setter on a real transition. We already filtered to crocs
		# that declare `set_lod_active` (above), and every such croc is a real
		# PigletCrocodile that ALSO declares `lod_active`, so we can read it directly
		# without a membership guard. `lod_active` defaults to true, so a just-spawned
		# one reads as awake here.
		var currently_active: bool = croc.lod_active

		var should_be_active: bool = currently_active
		if currently_active:
			# Awake → only sleep once we're clearly OUTSIDE the buffer (hysteresis).
			if dist_sq > SLEEP_DISTANCE_SQ:
				should_be_active = false
		else:
			# Asleep → wake as soon as we're back INSIDE SIM_RADIUS.
			if dist_sq <= WAKE_DISTANCE_SQ:
				should_be_active = true

		# Only notify the crocodile when its state actually flips. The setter is
		# also idempotent, but skipping the call entirely keeps this loop cheap.
		if should_be_active != currently_active:
			croc.set_lod_active(should_be_active)


func _scan_coins() -> void:
	## One coin-animation pass: freeze the spin/bob `_process` of coins the
	## player can't see moving, thaw the ones nearby. We read each coin's
	## current state straight off `is_processing()` — the engine already tracks
	## it, so no bookkeeping Dictionary is needed — and call `set_process` only
	## on a real transition, mirroring the crocodile pass.
	if not is_instance_valid(_player):
		# _scan_crocodiles() already tried to (re)acquire the player this tick;
		# if it's still missing we simply skip coins too.
		return

	var player_pos: Vector3 = _player.global_position

	for coin in get_tree().get_nodes_in_group("coin"):
		if not is_instance_valid(coin) or not (coin is Node3D):
			continue

		var dist_sq: float = coin.global_position.distance_squared_to(player_pos)
		var animating: bool = coin.is_processing()

		if animating:
			# Animating → freeze only once clearly outside the buffer (hysteresis).
			if dist_sq > COIN_FREEZE_DISTANCE_SQ:
				coin.set_process(false)
		else:
			# Frozen → resume as soon as we're back inside COIN_ANIM_RADIUS.
			if dist_sq <= COIN_WAKE_DISTANCE_SQ:
				coin.set_process(true)
