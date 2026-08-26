extends SceneTree
## Headless self-check for fauna_manager.gd's obstacle lookahead.
##
##   godot --headless --path . --script res://scripts/fauna_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 —
## the same shape as mp_selfcheck.gd and minimap_selfcheck.gd, and it exists for
## the same reason those do: it guards the things here that would fail
## SILENTLY, with no error anywhere and nothing visible until somebody happened
## to watch a herd cross a mountain.
##
##   1. A herd aimed at a massif goes AROUND it. Everything about the steering
##      lives behind a physics query, so a wrong mask, a wrong probe height, a
##      box swept from the wrong origin or an unwind that fires while the rock
##      is still abeam all degrade to "the herd walks through it" — exactly the
##      state this feature replaced.
##   2. A herd aimed at a lone 1.5 m SCATTERED BLOCK goes around that too. This
##      is the row the swept box exists for and the row the three-ray v1 failed:
##      three infinitely thin samples of a 30 m corridor walk a small block
##      between two of them, with nothing to see but elephants strolling through
##      scenery. Narrowing the box back toward a ray passes row 1 and fails here.
##   3. An EMPTY field deflects a herd by nothing at all — and in particular the
##      PLAYER never deflects one. The player is a CharacterBody3D on layer 1,
##      the very layer the sweep watches, so it is excluded by RID
##      (fauna_manager._refresh_probe_exclude). Drop that one line and fauna
##      starts reacting to the player, which is the loudest possible breach of
##      the isolation contract and the least visible: it only shows when
##      somebody stands in front of a passing herd. It is also the negative
##      control for rows 1-2: without it, "always swerve" would pass them both.
##   4. A RIDER PARKED ON EACH SPECIES' BACK IS CARRIED, NOT FLUNG. The three
##      rideable roots are AnimatableBody3Ds, so Godot hands a rider standing on
##      one the platform velocity at its own point — `linear + angular × r`. The
##      facing yaw is derived from a term (`_avoid_velocity`) that is a step
##      function, so before FACING_YAW_RATE_MAX it snapped ~0.77 rad in a single
##      tick on both ends of every avoidance swerve and threw the player off the
##      barrel: measured 0.72 m of rider travel in ONE tick on an elephant and
##      19 m of deck drift over one crossing. Nothing errors, nothing logs, and
##      the wider the animal the worse it is — which is the whole reason this
##      row measures every species rather than one.
##
## Don't grow this into a suite. Two non-obvious things in here. (a) Rows 1-3
## drive the manager's own _physics_process by hand, SUB-STEPPED inside a real
## physics frame, so the queries are legal and a 45 s crossing costs a second of
## wall clock instead of 45. (b) Row 4 must NOT do that: platform velocity is
## read out of the physics server's body state, which only advances on a REAL
## step, so a sub-stepped rider would be carried by a stale sample and the row
## would measure nothing. It runs one manager tick per real physics frame.

const TRIALS_PER_ROW: int = 4
const SIM_TICKS: int = 2600           # ~43 s at 60 Hz — well past the obstacle
const TICKS_PER_FRAME: int = 60       # manager sub-steps per real physics frame
const DT: float = 1.0 / 60.0
const OBSTACLE_AHEAD: float = 70.0    # metres down the herd's freshly rolled line
const ANIMAL_HALF_WIDTH: float = 1.0  # credited to the animal when measuring clearance
const PLAYER_AHEAD: float = 30.0      # empty-field trials: player parked this far down the line
## Lifts the player's 2 m capsule so it straddles fauna_manager's probe height
## (1.0) instead of ending exactly on it.
const PLAYER_Y: float = 0.5

## The rows, in order. `half` is the obstacle's XZ half-extent and `height` its
## full height; `half == 0.0` marks the negative-control row, which parks the
## obstacle out of the world and puts the PLAYER on the herd's line instead.
##   massif — a mountain massif (a real one is ~9.7 m half-width).
##   block  — ONE 1.5 m scattered decorative block, the smallest solid the
##            terrain scatters, and the whole reason the rays became a box.
const ROWS: Array[Dictionary] = [
	{"name": "massif", "half": 10.0, "height": 12.0},
	{"name": "block", "half": 0.75, "height": 2.5},
	{"name": "empty", "half": 0.0, "height": 0.0},
]

# ---------------------------------------------------------------------------
# Row 4 — the rider carry (see the header). One species at a time, one animal
# each, one manager tick per REAL physics frame.
# ---------------------------------------------------------------------------

## The three rideable species, by the builder each one is made with. Herders are
## deliberately absent: they carry no collider at all (see _build_herder).
const RIDE_SPECIES: Array[Dictionary] = [
	{"name": "elephant", "build": "_build_elephant", "adult": true},
	{"name": "giraffe", "build": "_build_giraffe", "adult": false},
	{"name": "beast", "build": "_build_pack_beast", "adult": false},
]

## The swerve script, as (frames, `_avoid_target`) pairs. `_avoid_target` is the
## exact variable the lookahead probe writes, so easing it by hand drives the
## real move_toward -> `_avoid_velocity` -> yaw path a real obstacle produces —
## and it does it in 5 s per species instead of the ~40 s a herd needs to walk
## up to a massif, turn, and unwind. The probe itself is parked for the row
## (`_probe_timer` set out of reach), so nothing else writes the target.
## Every entry and exit of a swerve is a yaw step change, which is the event
## under test; 120 frames covers the full AVOID_EASE_SPEED ease of a 4 m berth.
const RIDE_PHASES: Array = [
	[60, 0.0],      # pure meander
	[120, 4.0],     # swerve out — the entry step, the hold, then the exit step
	[120, 0.0],     # unwind — the same two steps with the sign flipped
]
const RIDE_SETTLE_FRAMES: int = 10
const RIDE_HERD_SPEED: float = 2.5

## Worst per-tick rider displacement allowed BEYOND the animal's own. The herd
## walks RIDE_HERD_SPEED / 60 = 0.0417 m per tick; measured after the fix the
## worst excess is 0.0076 m (elephant, the widest deck), and with the yaw snap
## it was 0.72 m. 0.02 leaves 2.6x headroom over the real figure while sitting
## 36x under the bug — the gap this row exists in is two orders of magnitude, so
## the exact threshold is not delicate.
const RIDE_EXCESS_MAX: float = 0.02
## How far the rider may end up from where it was placed IN THE ANIMAL'S OWN
## FRAME. Measured 0.40 m (elephant) after the fix, 19.11 m with the bug — i.e.
## thrown off and left behind. 1.5 m is inside every deck.
const RIDE_DRIFT_MAX: float = 1.5
## NEGATIVE CONTROL 1: the rider has to have been CARRIED for any of the above to
## mean anything. A rider that fell off on frame one and stood on the ground has
## a per-tick excess of zero (it moves less than the herd, not more) and would
## satisfy RIDE_EXCESS_MAX perfectly. So its total travel is measured against the
## herd's and must be nearly all of it.
const RIDE_CARRY_MIN: float = 0.9
## NEGATIVE CONTROL 2: the herd has to have actually TURNED. Delete the swerve
## script — or the yaw write itself — and a herd walking a straight line carries
## its rider flawlessly, passing every assertion above while testing nothing.
## The scripted berth swings the facing ~0.77 rad each way.
const RIDE_YAW_SWING_MIN: float = 0.4

var _root: Node3D = null
var _manager: Node = null
var _obstacle: StaticBody3D = null
var _obstacle_box: BoxShape3D = null
var _obstacle_shape: CollisionShape3D = null
var _player: CharacterBody3D = null

var _row: int = 0
var _row_half: float = 0.0            # 0.0 == the empty-field control row
var _trial: int = 0
var _phase: int = 0
var _wait: int = 0
var _ticks: int = 0
var _trial_min_gap: float = 1e9

## Worst clearance seen per obstacle row (parallel to ROWS), and the largest
## detour seen in the empty-field control.
var _worst_gap: Array[float] = []
var _open_max_avoid: float = 0.0
var _spawned: int = 0
var _failures: Array[String] = []

## Row 4 state — the species under test, its scripted swerve position, and the
## four figures measured per species (see the RIDE_* constants).
var _ride_species: int = 0
var _ride_phase_i: int = 0
var _ride_phase_left: int = 0
var _ride_prev_rider: Vector3 = Vector3.ZERO
var _ride_prev_herd: Vector3 = Vector3.ZERO
var _ride_yaw_min: float = 0.0
var _ride_yaw_max: float = 0.0
var _ride_excess: float = 0.0
var _ride_rider_travel: float = 0.0
var _ride_herd_travel: float = 0.0
var _ride_lines: Array[String] = []


func _initialize() -> void:
	_root = Node3D.new()
	root.add_child(_root)

	# Flat ground on layer 1, shaped like a terrain chunk's ground box (a 0.1 m
	# slab straddling y = 0), so the probe meets the same thing it meets in the
	# real world and a probe height regression shows up here.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(800.0, 0.1, 800.0)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	_root.add_child(ground)

	# A real CharacterBody3D in group "player", on layer 1 exactly like
	# scenes/player.tscn — this node IS the control row, and that row MOVES it
	# onto the herd's probe corridor (see _start_trial). Leaving it at the
	# origin is not enough and looks like it is: _spawn_herd offsets the whole
	# migration line by MIGRATION_MISS_MIN..MAX (25-60 m), which is wider than
	# the probe reaches, so a player at the origin is outside it and the check
	# passes whether or not the RID exclusion exists.
	# collision_mask 5 = world (layer 1) + fauna (layer 3), exactly what
	# scenes/player.tscn carries. Rows 1-3 never move it so the mask is inert
	# there; row 4 cannot ride anything without it.
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_mask = 5
	var player_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	player_shape.shape = capsule
	_player.add_child(player_shape)
	_root.add_child(_player)

	# The obstacle: one box on layer 1, RESIZED per row and parked out of the
	# world for the control row. One body rather than one per row, so every row
	# meets the same collider through the same code path.
	_obstacle = StaticBody3D.new()
	_obstacle_shape = CollisionShape3D.new()
	_obstacle_box = BoxShape3D.new()
	_obstacle_box.size = Vector3(20.0, 12.0, 20.0)
	_obstacle_shape.shape = _obstacle_box
	_obstacle.add_child(_obstacle_shape)
	_root.add_child(_obstacle)

	_worst_gap.resize(ROWS.size())
	_worst_gap.fill(1e9)

	_manager = Node.new()
	_manager.set_script(load("res://scripts/fauna_manager.gd"))
	_root.add_child(_manager)
	# Park the manager's own event timer — trials drive _spawn_herd directly.
	_manager.set("_event_timer", 1e9)


func _physics_process(_delta: float) -> bool:
	match _phase:
		0:
			# Let the static bodies register with the physics server before any
			# query is run against them.
			_wait += 1
			if _wait > 3:
				_phase = 1
		1:
			_start_trial()
		2:
			# Same again after moving/resizing the obstacle.
			_wait += 1
			if _wait > 2:
				_phase = 3
		3:
			_run_slice()
		4:
			_start_ride()
		5:
			_settle_ride()
		6:
			_run_ride()
	return false


func _start_trial() -> void:
	_row = _trial / TRIALS_PER_ROW
	var row: Dictionary = ROWS[_row]
	_row_half = float(row["half"])
	if _row_half > 0.0:
		# Resize the collider for this row BEFORE the herd is aimed at it.
		_obstacle_box.size = Vector3(_row_half * 2.0, float(row["height"]), _row_half * 2.0)
		_obstacle_shape.position = Vector3(0.0, float(row["height"]) * 0.5, 0.0)
	_manager.call("_despawn_herd")
	_manager.call("_spawn_herd")
	var animals: Array = _manager.get("_animals")
	if animals.is_empty():
		_finish_trial()
		return
	_spawned += 1
	var herd_pos: Vector3 = _manager.get("_herd_position")
	var heading: Vector3 = _manager.get("_herd_heading")
	if _row_half > 0.0:
		_obstacle.position = herd_pos + heading * OBSTACLE_AHEAD
		_player.position = Vector3(0.0, PLAYER_Y, 0.0)
	else:
		# Empty field, and the player parked squarely ON the herd's probe
		# corridor at probe height — so a herd that reacts to the player has
		# nothing else it could be reacting to. Placed AFTER _spawn_herd, which
		# reads the player position to lay the migration line out.
		_obstacle.position = Vector3(0.0, 0.0, 9000.0)
		_player.position = herd_pos + heading * PLAYER_AHEAD + Vector3(0.0, PLAYER_Y, 0.0)
	_ticks = 0
	_trial_min_gap = 1e9
	_wait = 0
	_phase = 2


func _run_slice() -> void:
	for _i: int in TICKS_PER_FRAME:
		if _ticks >= SIM_TICKS:
			break
		_ticks += 1
		_manager.call("_physics_process", DT)
		var animals: Array = _manager.get("_animals")
		if animals.is_empty():
			break                        # herd despawned — the crossing is over
		if _row_half > 0.0:
			for animal: Dictionary in animals:
				_trial_min_gap = minf(_trial_min_gap,
						_gap_to_obstacle((animal["root"] as Node3D).global_position))
		else:
			_open_max_avoid = maxf(_open_max_avoid,
					absf(float(_manager.get("_avoid_offset"))))
	var animals_left: Array = _manager.get("_animals")
	if _ticks >= SIM_TICKS or animals_left.is_empty():
		_finish_trial()


func _gap_to_obstacle(p: Vector3) -> float:
	## Clearance from this animal to this row's obstacle in the XZ plane;
	## negative means the animal is standing inside it.
	var dx := absf(p.x - _obstacle.position.x) - (_row_half + ANIMAL_HALF_WIDTH)
	var dz := absf(p.z - _obstacle.position.z) - (_row_half + ANIMAL_HALF_WIDTH)
	return maxf(dx, dz)


func _finish_trial() -> void:
	if _row_half > 0.0 and _trial_min_gap < 1e8:
		_worst_gap[_row] = minf(_worst_gap[_row], _trial_min_gap)
	_trial += 1
	if _trial >= ROWS.size() * TRIALS_PER_ROW:
		_phase = 4                       # on to row 4, the rider carry
		return
	_phase = 1


# ---------------------------------------------------------------------------
# ROW 4 — a rider parked on each species' back through a meander and a swerve
# ---------------------------------------------------------------------------

func _start_ride() -> void:
	## Stand ONE animal of the species under test on flat ground with the herd
	## state _spawn_herd would have left behind, and park the rider on its deck.
	##
	## Built by hand rather than through _spawn_herd because that rolls a random
	## migration type: this row has to measure every species, and a species this
	## row never happened to roll would silently go untested.
	_manager.call("_despawn_herd")
	_manager.set("_event_timer", 1e9)
	_obstacle.position = Vector3(0.0, 0.0, 9000.0)
	_manager.set("_herd_heading", Vector3(1.0, 0.0, 0.0))
	_manager.set("_herd_lateral", Vector3(0.0, 0.0, 1.0))
	_manager.set("_herd_position", Vector3.ZERO)
	_manager.set("_herd_speed", RIDE_HERD_SPEED)
	_manager.set("_herd_travelled", 0.0)
	_manager.set("_herd_age", 0.0)
	_manager.set("_herd_offset_max", 0.0)
	_manager.set("_avoid_target", 0.0)
	_manager.set("_avoid_offset", 0.0)
	_manager.set("_avoid_velocity", 0.0)
	_manager.set("_avoid_hold_until", 0.0)
	# _spawn_herd seeds the slew-limited facing from the heading; do the same by
	# hand, or the first tick slews in from world north and the yaw-swing
	# negative control passes on the spin-up instead of on the swerve.
	_manager.set("_facing_yaw", atan2(-1.0, 0.0))
	# Out of reach: no lookahead probe fires during this row, so the only thing
	# writing _avoid_target is RIDE_PHASES.
	_manager.set("_probe_timer", 1e9)

	var species: Dictionary = RIDE_SPECIES[_ride_species]
	var record: Dictionary
	if bool(species["adult"]):
		record = _manager.call(species["build"], true)
	else:
		record = _manager.call(species["build"])
	_manager.call("_add_animal", record, Vector3.ZERO)

	# Park the rider near the barrel's EDGE. The flung distance is `angular × r`,
	# so the edge is the worst case and the middle would understate every species
	# — and understate the widest one most, which is the one that was reported.
	var animal_root: Node3D = record["root"]
	var shape: CollisionShape3D = animal_root.get_node("PlatformShape")
	var box: BoxShape3D = shape.shape
	var deck_top: float = shape.position.y + box.size.y * 0.5
	var edge_x: float = box.size.x * 0.5 - 0.35
	_player.global_position = animal_root.global_transform * Vector3(edge_x, deck_top + 1.05, 0.0)
	_player.velocity = Vector3.ZERO

	_ride_phase_i = 0
	_ride_phase_left = int(RIDE_PHASES[0][0])
	_ride_excess = 0.0
	_ride_rider_travel = 0.0
	_ride_herd_travel = 0.0
	_wait = 0
	_phase = 5


func _settle_ride() -> void:
	## A few frames of gravity only, so the rider is genuinely resting on the
	## deck (and its platform RID is latched) before anything is measured.
	_player.velocity = Vector3(0.0, -10.0, 0.0)
	_player.move_and_slide()
	_wait += 1
	if _wait < RIDE_SETTLE_FRAMES:
		return
	var animals: Array = _manager.get("_animals")
	_ride_prev_rider = _player.global_position
	_ride_prev_herd = (animals[0]["root"] as Node3D).global_position
	var yaw: float = (animals[0]["root"] as Node3D).global_rotation.y
	_ride_yaw_min = yaw
	_ride_yaw_max = yaw
	_phase = 6


func _run_ride() -> void:
	## ONE manager tick per REAL physics frame — see (b) in the header for why
	## this row cannot be sub-stepped like the three above it.
	if _ride_phase_left <= 0:
		_ride_phase_i += 1
		if _ride_phase_i >= RIDE_PHASES.size():
			_finish_ride()
			return
		_ride_phase_left = int(RIDE_PHASES[_ride_phase_i][0])
		_manager.set("_avoid_target", float(RIDE_PHASES[_ride_phase_i][1]))
	_ride_phase_left -= 1

	_manager.call("_physics_process", DT)
	var animals: Array = _manager.get("_animals")
	if animals.is_empty():
		_failures.append("%s: the herd despawned mid-ride" % RIDE_SPECIES[_ride_species]["name"])
		_finish_ride()
		return
	_player.velocity = Vector3(0.0, -10.0, 0.0)
	_player.move_and_slide()

	var animal_root: Node3D = animals[0]["root"]
	var herd_now: Vector3 = animal_root.global_position
	var rider_now: Vector3 = _player.global_position
	var herd_step := _flat_distance(herd_now, _ride_prev_herd)
	var rider_step := _flat_distance(rider_now, _ride_prev_rider)
	_ride_excess = maxf(_ride_excess, rider_step - herd_step)
	_ride_herd_travel += herd_step
	_ride_rider_travel += rider_step
	var yaw: float = animal_root.global_rotation.y
	_ride_yaw_min = minf(_ride_yaw_min, yaw)
	_ride_yaw_max = maxf(_ride_yaw_max, yaw)
	_ride_prev_herd = herd_now
	_ride_prev_rider = rider_now


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _finish_ride() -> void:
	var species_name: String = RIDE_SPECIES[_ride_species]["name"]
	var animals: Array = _manager.get("_animals")
	# Drift is measured in the ANIMAL'S OWN FRAME: "did the rider stay where it
	# was put on the deck", which is what riding means and what the world-space
	# per-tick figure alone cannot say.
	var drift := 1e9
	if not animals.is_empty():
		var animal_root: Node3D = animals[0]["root"]
		var local: Vector3 = animal_root.global_transform.affine_inverse() * _player.global_position
		drift = Vector2(local.x, local.z).length()
	var carried := 0.0
	if _ride_herd_travel > 0.0:
		carried = _ride_rider_travel / _ride_herd_travel
	var swing := _ride_yaw_max - _ride_yaw_min

	if _ride_excess > RIDE_EXCESS_MAX:
		_failures.append("%s: rider moved %.3f m MORE than the animal in one tick (max %.3f) — it is being flung by the platform's angular velocity"
				% [species_name, _ride_excess, RIDE_EXCESS_MAX])
	if drift > RIDE_DRIFT_MAX:
		_failures.append("%s: rider ended %.2f m from where it was put on the deck (max %.2f) — it was dragged off"
				% [species_name, drift, RIDE_DRIFT_MAX])
	if carried < RIDE_CARRY_MIN:
		_failures.append("%s: rider travelled only %.0f%% of the animal's distance — it was never carried, so this row measured nothing"
				% [species_name, carried * 100.0])
	if swing < RIDE_YAW_SWING_MIN:
		_failures.append("%s: the animal's facing only swung %.2f rad — it never turned, so this row measured nothing"
				% [species_name, swing])
	_ride_lines.append("%s: worst tick excess %.4f m, deck drift %.2f m, carried %.0f%%, yaw swing %.2f rad"
			% [species_name, _ride_excess, drift, carried * 100.0, swing])

	_ride_species += 1
	if _ride_species >= RIDE_SPECIES.size():
		_report()
		return
	_phase = 4


func _report() -> void:
	var total := ROWS.size() * TRIALS_PER_ROW
	if _spawned < total:
		_failures.append("only %d of %d trials spawned a herd" % [_spawned, total])
	var line := ""
	for i: int in ROWS.size():
		var row: Dictionary = ROWS[i]
		if float(row["half"]) <= 0.0:
			continue
		var row_name: String = row["name"]
		if _worst_gap[i] > 1e8:
			_failures.append("no %s trial measured a clearance" % row_name)
		elif _worst_gap[i] < 0.0:
			_failures.append("herd walked INTO the %s (worst clearance %.2f m)"
					% [row_name, _worst_gap[i]])
		line += "%s: worst clearance %.2f m | " % [row_name, _worst_gap[i]]
	if _open_max_avoid > 0.0:
		_failures.append("empty field deflected the herd by %.2f m — fauna is reacting to the player or to the ground"
				% _open_max_avoid)

	if _failures.is_empty():
		print(line + "empty-field detour: %.2f m" % _open_max_avoid)
		for ride_line: String in _ride_lines:
			print("ride  ", ride_line)
		print("SELFCHECK OK")
		quit(0)
		return
	for ride_line: String in _ride_lines:
		print("ride  ", ride_line)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
