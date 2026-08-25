extends SceneTree
## Headless self-check for fauna_manager.gd's obstacle lookahead.
##
##   godot --headless --path . --script res://scripts/fauna_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 —
## the same shape as mp_selfcheck.gd and minimap_selfcheck.gd, and it exists for
## the same reason those do: it guards the two things here that would fail
## SILENTLY, with no error anywhere and nothing visible until somebody happened
## to watch a herd cross a mountain.
##
##   1. A herd aimed at a massif goes AROUND it. Everything about the steering
##      lives behind a ray query, so a wrong mask, a wrong probe height, a
##      feeler cast from the wrong origin or an unwind that fires while the rock
##      is still abeam all degrade to "the herd walks through it" — exactly the
##      state this feature replaced.
##   2. An EMPTY field deflects a herd by nothing at all — and in particular the
##      PLAYER never deflects one. The player is a CharacterBody3D on layer 1,
##      the very layer the feelers watch, so it is excluded by RID
##      (fauna_manager._refresh_probe_exclude). Drop that one line and fauna
##      starts reacting to the player, which is the loudest possible breach of
##      the isolation contract and the least visible: it only shows when
##      somebody stands in front of a passing herd.
##
## Don't grow this into a suite. It drives the manager's own _physics_process by
## hand inside a real physics frame (so ray queries are legal and a 45 s
## crossing costs a second of wall clock instead of 45), which is the only
## non-obvious thing in here.

const TRIALS: int = 12
const SIM_TICKS: int = 2600           # ~43 s at 60 Hz — well past the obstacle
const TICKS_PER_FRAME: int = 60       # manager sub-steps per real physics frame
const DT: float = 1.0 / 60.0
const MASSIF_AHEAD: float = 70.0      # metres down the herd's freshly rolled line
const MASSIF_HALF: float = 10.0       # half-width of the test massif (a real one is ~9.7)
const ANIMAL_HALF_WIDTH: float = 1.0  # credited to the animal when measuring clearance

var _root: Node3D = null
var _manager: Node = null
var _massif: StaticBody3D = null
var _massif_live: bool = true

var _trial: int = 0
var _phase: int = 0
var _wait: int = 0
var _ticks: int = 0
var _trial_min_gap: float = 1e9

var _worst_gap: float = 1e9           # worst clearance seen with the massif on the line
var _open_max_avoid: float = 0.0      # largest detour seen with the field empty
var _spawned: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_root = Node3D.new()
	root.add_child(_root)

	# Flat ground on layer 1, shaped like a terrain chunk's ground box (a 0.1 m
	# slab straddling y = 0), so the feelers meet the same thing they meet in the
	# real world and a probe height regression shows up here.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(800.0, 0.1, 800.0)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	_root.add_child(ground)

	# A real CharacterBody3D in group "player", left at the origin — which is
	# where every herd's migration line is aimed, so the open-field trials below
	# put it squarely in front of the herd. Layer defaults to 1 exactly like
	# scenes/player.tscn: this node IS check 2.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var player_shape := CollisionShape3D.new()
	player_shape.shape = CapsuleShape3D.new()
	player.add_child(player_shape)
	_root.add_child(player)

	# The massif: one 20 x 12 x 20 block, parked out of the world until a trial
	# moves it onto the herd's line.
	_massif = StaticBody3D.new()
	var massif_shape := CollisionShape3D.new()
	var massif_box := BoxShape3D.new()
	massif_box.size = Vector3(MASSIF_HALF * 2.0, 12.0, MASSIF_HALF * 2.0)
	massif_shape.shape = massif_box
	massif_shape.position = Vector3(0.0, 6.0, 0.0)
	_massif.add_child(massif_shape)
	_root.add_child(_massif)

	_manager = Node.new()
	_manager.set_script(load("res://scripts/fauna_manager.gd"))
	_root.add_child(_manager)
	# Park the manager's own event timer — trials drive _spawn_herd directly.
	_manager.set("_event_timer", 1e9)


func _physics_process(_delta: float) -> bool:
	match _phase:
		0:
			# Let the static bodies register with the physics server before any
			# ray is cast against them.
			_wait += 1
			if _wait > 3:
				_phase = 1
		1:
			_start_trial()
		2:
			# Same again after moving the massif.
			_wait += 1
			if _wait > 2:
				_phase = 3
		3:
			_run_slice()
	return false


func _start_trial() -> void:
	# First half of the trials walk into a massif; the rest walk an empty field.
	_massif_live = _trial < TRIALS / 2
	_manager.call("_despawn_herd")
	_manager.call("_spawn_herd")
	var animals: Array = _manager.get("_animals")
	if animals.is_empty():
		_finish_trial()
		return
	_spawned += 1
	if _massif_live:
		var herd_pos: Vector3 = _manager.get("_herd_position")
		var heading: Vector3 = _manager.get("_herd_heading")
		_massif.position = herd_pos + heading * MASSIF_AHEAD
	else:
		_massif.position = Vector3(0.0, 0.0, 9000.0)
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
		if _massif_live:
			for animal: Dictionary in animals:
				_trial_min_gap = minf(_trial_min_gap,
						_gap_to_massif((animal["root"] as Node3D).global_position))
		else:
			_open_max_avoid = maxf(_open_max_avoid,
					absf(float(_manager.get("_avoid_offset"))))
	var animals_left: Array = _manager.get("_animals")
	if _ticks >= SIM_TICKS or animals_left.is_empty():
		_finish_trial()


func _gap_to_massif(p: Vector3) -> float:
	## Clearance from this animal to the massif in the XZ plane; negative means
	## the animal is standing inside the rock.
	var dx := absf(p.x - _massif.position.x) - (MASSIF_HALF + ANIMAL_HALF_WIDTH)
	var dz := absf(p.z - _massif.position.z) - (MASSIF_HALF + ANIMAL_HALF_WIDTH)
	return maxf(dx, dz)


func _finish_trial() -> void:
	if _massif_live and _trial_min_gap < 1e8:
		_worst_gap = minf(_worst_gap, _trial_min_gap)
	_trial += 1
	if _trial >= TRIALS:
		_report()
		return
	_phase = 1


func _report() -> void:
	if _spawned < TRIALS:
		_failures.append("only %d of %d trials spawned a herd" % [_spawned, TRIALS])
	if _worst_gap > 1e8:
		_failures.append("no massif trial measured a clearance")
	elif _worst_gap < 0.0:
		_failures.append("herd walked INTO the massif (worst clearance %.2f m)" % _worst_gap)
	if _open_max_avoid > 0.0:
		_failures.append("empty field deflected the herd by %.2f m — fauna is reacting to the player or to the ground"
				% _open_max_avoid)

	if _failures.is_empty():
		print("massif trials: worst clearance %.2f m | empty-field detour: %.2f m"
				% [_worst_gap, _open_max_avoid])
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
