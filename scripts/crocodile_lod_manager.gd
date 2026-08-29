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

## Lifetime count of scan ticks run. Public and monotonic purely so
## `perf_overlay.gd` can attribute a frame spike to "the LOD scan fired on this
## frame" — a full ~1,000-crocodile pass is one of the few things that only
## costs on some frames, which is exactly the signature of a periodic hitch.
## Sampled by polling (never a signal), so it cannot perturb the scan it counts.
var lod_scans_total: int = 0


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	# Group-based discovery, as everywhere else: the perf overlay finds us here
	# to read `lod_scans_total`. Nothing gameplay-facing hangs off this group.
	add_to_group("lod_manager")

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
	lod_scans_total += 1

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
	##
	## The same loop ALSO feeds the danger telegraph for free: for every croc that
	## is actively chasing (`is_chasing`) we compute how far it has closed its OWN
	## detection radius and publish the worst of them to the DangerVignette after
	## the loop — zero extra passes. This is guaranteed complete because any croc
	## that could be chasing is inside its detection radius (15 m regular, 25 m
	## boss), far inside SIM_RADIUS (45 m), so it is always awake and always seen
	## by this scan.

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

	# ------------------------------------------------------------------------
	# WHO COUNTS AS "NEAR" (multiplayer generalisation)
	# ------------------------------------------------------------------------
	# A crocodile must be awake when it is near ANY member of the room, not only
	# when it is near the local player: in a room the master simulates every awake
	# croc for everybody, so a croc slept here because *we* walked away would stop
	# being simulated for the teammate standing next to it. The awake test is
	# therefore the MINIMUM distance over the whole set of member positions.
	#
	# LOAD-BEARING CLAIM FOR "SOLO PLAY IS BYTE-FOR-BYTE UNCHANGED": offline (and
	# in a room before the mesh comes up) `peer_positions()` returns null, so this
	# set is the one-element array [player_pos] and the minimum over it is exactly
	# the old single distance. No branch below can behave differently.
	#
	# It also returns null on a NON-MASTER, because only the master publishes
	# crocodile state and so only its LOD decision can strand a teammate's
	# neighbours unsimulated — see `MpManager.peer_positions()` for why widening
	# the set anywhere else is pure cost.
	#
	# Group-based + null-safe like every other cross-system hook: no MP manager in
	# the scene (a character scene run in isolation) means we simply skip it.
	var focus_points: Array[Vector3] = [player_pos]
	var mp := get_tree().get_first_node_in_group("mp")
	if mp != null and mp.has_method("peer_positions"):
		var remotes: Variant = mp.peer_positions()
		if remotes is Array:
			for p: Variant in remotes:
				if p is Vector3:
					focus_points.append(p)

	# THE SAME SET, HANDED TO THE TERRAIN (bead godot-test1-s86.14). Waking a
	# crocodile standing next to a far teammate is only half the job — the master
	# can only simulate crocodiles its own terrain has LOADED, so past
	# `render_distance` (150 m on web) there was nothing awake to wake and those
	# crocodiles fell back to local simulation on every peer. `set_focus_points`
	# keeps the chunks around each teammate loaded; it decides only which chunks
	# STAY loaded and never what one contains (see its docstring).
	#
	# `slice(1)` drops the local player, whose chunks the terrain already owns —
	# spending one of the terrain's three focus slots on it would be pure waste.
	# Sent EVERY scan, including the empty array: offline / on a non-master
	# `peer_positions()` is null, the slice is empty, and that empty push is what
	# RELEASES chunks pinned by a room this peer has left. `set_focus_points`
	# no-ops on an unchanged set, so the steady state costs one compare at 9 Hz.
	#
	# This manager is the caller rather than `mp_manager.gd` because it already
	# builds exactly this array, already master-gates it (that is what
	# `peer_positions()` returning null on a non-master means) and already runs on
	# a throttled tick — no new state, no new tick, no second group lookup.
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("set_focus_points"):
		terrain.set_focus_points(focus_points.slice(1))

	# Danger telegraph level: 0 = nobody hunting, 1 = a chaser at point blank.
	# NORMALISED per chaser (distance ÷ that croc's own detection radius) rather
	# than published as raw metres, because a boss acquires the player at 25 m
	# while a regular croc only smells at 15 m — a single hardcoded range on the
	# vignette side would leave the game's biggest threat un-telegraphed for the
	# first 10 m of its approach. Published to the vignette after the loop.
	#
	# TWO CHANNELS, ONE SCAN (owner ruling, bead godot-test1-9rm.6). A GD-SURVEY
	# hunter is a different KIND of threat from an animal — it retrieves rather
	# than eats, it cannot be crushed or stunk away, and it announces itself with
	# a machine's ping — so it gets its own dread channel instead of reddening
	# the same screen edge. What it does NOT get is a scan of its own: it is the
	# same loop, the same per-chaser normalisation, one more `maxf` into a second
	# accumulator. Both are published together below, and the vignette composes
	# them (see there) rather than letting either overwrite the other.
	#
	# Split on the BEHAVIOUR, not the species name — the same rule as the
	# acquisition cue in piglet_crocodile_ai — so a second retrieval unit joins
	# the machine channel with its SPECIES row and no edit here. The `in` guard
	# is the file's usual defensive style: a group member with no `spec` is an
	# animal as far as this is concerned.
	var danger_level: float = 0.0
	var hunter_level: float = 0.0

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
		# avoids a sqrt per crocodile per scan. TWO distances, deliberately:
		#   * `dist_sq_local` — to THIS player, and only this player. It feeds the
		#     danger telegraph, which is this player's own fear, not the room's: a
		#     croc hunting a teammate 80 m away must not redden our screen.
		#   * `dist_sq_any` — the minimum over every member position, which is what
		#     the awake/asleep decision uses so `SIM_RADIUS ≫ DETECTION_RADIUS`
		#     holds for every member rather than only for us.
		# Offline the two are the same number (focus_points is [player_pos]).
		var croc_pos: Vector3 = croc.global_position
		var dist_sq_local: float = croc_pos.distance_squared_to(player_pos)
		var dist_sq_any: float = dist_sq_local
		for i: int in range(1, focus_points.size()):
			dist_sq_any = minf(dist_sq_any, croc_pos.distance_squared_to(focus_points[i]))

		# Danger telegraph: remember the closest ACTIVE hunter. The `in` guard
		# keeps us safe against a group member that doesn't expose the flag
		# (same defensive style as the has_method filter above). Bosses live in
		# the same group and expose the same flag, so they telegraph too.
		if "is_chasing" in croc and croc.is_chasing and "detection_radius" in croc:
			# `detection_radius` is the croc's OWN resolved smell range (15 regular,
			# 25 boss) — never a constant duplicated here, so retuning either radius
			# moves the telegraph with it. maxf guards a hand-zeroed radius.
			var radius: float = maxf(croc.detection_radius, 0.001)
			var level: float = 1.0 - sqrt(dist_sq_local) / radius
			if "spec" in croc and String(croc.spec.get("behavior", "")) == "hunt":
				hunter_level = maxf(hunter_level, level)
			else:
				danger_level = maxf(danger_level, level)

		# A remote-driven crocodile (one the room master is simulating for us) is
		# owned by the sync layer: `set_remote_state()` forces that croc's
		# `_physics_process` ON so it can tick the samples in, and
		# `clear_remote_drive()` hands the switch back to whatever we last decided
		# here. The LOD manager must not fight it for that switch in between — but
		# this `continue` sits BELOW the danger read on purpose, so a
		# synced croc chasing us still lights the vignette. Same defensive `in`
		# guard as the `is_chasing` / `is_boss` reads.
		if "remote_driven" in croc and croc.remote_driven:
			continue

		# Read the crocodile's current LOD state so we can apply hysteresis and
		# only call the setter on a real transition. We already filtered to crocs
		# that declare `set_lod_active` (above), and every such croc is a real
		# PigletCrocodile that ALSO declares `lod_active`, so we can read it directly
		# without a membership guard. `lod_active` defaults to true, so a just-spawned
		# one reads as awake here.
		var currently_active: bool = croc.lod_active

		var should_be_active: bool = currently_active
		# BOSSES NEVER SLEEP. Every croc's draw cull is deliberately WIDER than the
		# sleep radius so a visible crocodile is never a frozen-mid-stride sleeper —
		# but `piglet_crocodile_ai` scales a boss's `visibility_range_end` by its
		# `boss_scale` (60 m × 2.5…6.0 = 150…360 m) so a mountain of crocodile doesn't
		# pop into view, which inverts that invariant for exactly the entity the
		# player looks at most: a boss standing on the road ahead would be drawn as a
		# motionless statue for the first 100–310 m of its approach. Keeping them
		# awake restores the invariant and costs nothing — bosses sit one per 300 m of
		# road, so at most a couple are ever loaded. Same defensive `in` guard as the
		# `is_chasing` read above.
		if "is_boss" in croc and croc.is_boss:
			should_be_active = true
		elif currently_active:
			# Awake → only sleep once we're clearly OUTSIDE the buffer (hysteresis).
			if dist_sq_any > SLEEP_DISTANCE_SQ:
				should_be_active = false
		else:
			# Asleep → wake as soon as we're back INSIDE SIM_RADIUS.
			if dist_sq_any <= WAKE_DISTANCE_SQ:
				should_be_active = true

		# Only notify the crocodile when its state actually flips. The setter is
		# also idempotent, but skipping the call entirely keeps this loop cheap.
		if should_be_active != currently_active:
			croc.set_lod_active(should_be_active)

	# A game-over player is out of play, so the telegraph must go quiet. Nothing
	# else would ever clear it: the body stays frozen inside DETECTION_RADIUS, so
	# its chasers keep `is_chasing` true and we would keep republishing ~1 m at
	# 9 Hz — the heartbeat pounding at full pitch and the red vignette lit behind
	# the Game Over screen until Play Again wipes the chunks. Same defensive `in`
	# guard as the is_chasing read above.
	if "is_game_over" in _player and _player.is_game_over:
		danger_level = 0.0
		hunter_level = 0.0

	# Publish the danger level (0..1; 0 = nobody chasing). Group-based and
	# null-safe like every other cross-system hook: no vignette in the scene
	# (e.g. a character scene run in isolation) means we simply skip it.
	var vignette := get_tree().get_first_node_in_group("danger_vignette")
	if vignette != null and vignette.has_method("set_danger_level"):
		vignette.set_danger_level(clampf(danger_level, 0.0, 1.0),
				clampf(hunter_level, 0.0, 1.0))


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
