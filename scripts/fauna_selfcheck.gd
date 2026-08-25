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
##
## Don't grow this into a suite. It drives the manager's own _physics_process by
## hand inside a real physics frame (so the queries are legal and a 45 s
## crossing costs a second of wall clock instead of 45), which is the only
## non-obvious thing in here.

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
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
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
		_report()
		return
	_phase = 1


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
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
