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
##      barrel: measured here, 1.26 m of rider travel in ONE tick on an elephant
##      (30x the herd's own step), 5.64 m of slide across its deck, and a rider
##      that covered only 81% of the animal's distance because it had been left
##      behind. Nothing errors and nothing logs, and the wider the animal the
##      worse it is — which is the whole reason this row measures every species
##      rather than one.
##
##   5. A herd meets the GASTRODEFENSE HQ and walks AROUND it. This one is in
##      ROWS with rows 1-3 (it is a fourth entry there, not a fourth concern),
##      but it is listed last because it is the only row the lookahead cannot
##      solve: the HQ is an 80 m sealed shell on a 65 m exclusion disc, i.e.
##      wider than the probe's whole berth, so the reflex asks for its cap,
##      finds the wall still there, and the herd parks against the facade. It
##      is answered by a PLAN instead (fauna_manager._plan_tower_detour), and a
##      plan is exactly what keeps passing silently after someone reorders it
##      behind the probe that overwrites it. See the tower block below.
##
##   6. THE MULTIPLAYER REPLAY (bead godot-test1-6xc) — the owner's "my buddy in
##      the same game don't see them". Four things, each with the mutation that
##      breaks it: two builds off one seed are byte-identical (or the two screens
##      draw different flocks under one name), a replayed herd tracks the master's
##      centre and holds its formation at `centre + offset`, silence for
##      REMOTE_HERD_TIMEOUT frees it (or a dead master's herd is immortal), and a
##      room NON-MASTER rolls nothing of its own — with "out of the room it rolls
##      one" as that last row's positive control, because "spawned nothing" is
##      also what a harness that cannot spawn reports.
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
##   tower  — the GastroDefense HQ, the row the swept box CANNOT pass: an 80 m
##            sealed shell on a 65 m exclusion disc at a fixed address. Marked
##            with "tower", which switches the trial to the tower geometry (the
##            player is parked ON the site, so every migration line the field
##            rolls crosses the disc) and to the tower metrics below.
const ROWS: Array[Dictionary] = [
	{"name": "massif", "half": 10.0, "height": 12.0},
	{"name": "block", "half": 0.75, "height": 2.5},
	{"name": "empty", "half": 0.0, "height": 0.0},
	{"name": "tower", "half": 40.0, "height": 52.0, "tower": true},
]

# ---------------------------------------------------------------------------
# Row "tower" — the herd walks AROUND the HQ (godot-test1-8p7)
# ---------------------------------------------------------------------------
# The bug this row guards: fauna_manager's lookahead is a 45 m reflex that can
# open at most AVOID_MAX_OFFSET (30 m) of berth. The HQ is a wall 80 m across on
# a 65 m keep-out disc, so the reflex asks for its cap, finds the wall still
# there, and the herd parks against the facade — visibly, and with nothing
# logged anywhere. The fix is a PLAN (fauna_manager._plan_tower_detour), and a
# plan is exactly the kind of thing that keeps passing after somebody reorders
# it behind the probe that overwrites it, which is why this row exists.
#
# Setup is deliberately the REAL path and not a hand-seeded herd: the terrain
# stub is in group "terrain" and the player is parked on the tower site, so
# _spawn_herd lays its own line — and every line it can roll crosses the disc,
# because MIGRATION_MISS caps at 60 m and the clearance the herd needs is ~90.

## Where the stub tower stands, and how big its disc is. Both are the shipping
## values (endless_terrain.tower_site() at -tower_site_distance on +X, and
## TOWER_RADIUS); the manager reads them off the stub through the same group
## lookup and the same const name it reads off the real terrain.
const TOWER_SITE: Vector3 = Vector3(-400.0, 0.0, 0.0)
const TOWER_RADIUS: float = 65.0
## How far PAST the site (metres, along the herd's own heading) the centre must
## get for the crossing to count as completed rather than abandoned. Bounded
## above by DESPAWN_RADIUS: at the ~90 m berth the herd holds, a centre 65 m past
## the site is 111 m from the player standing on it, comfortably inside the
## 150 - _herd_offset_max despawn ring, while an oscillating or parked herd
## never gets there at all.
const TOWER_PASSED_MIN: float = 65.0
## The tower row's own tick budget, because it is the only row that has to watch
## a whole crossing rather than one encounter: the herd spawns ~110 m short of
## the site along its heading and has to get TOWER_PASSED_MIN past it, i.e. ~175 m
## at a 2-3 m/s amble — 60-90 s, where SIM_TICKS is 43. Left as a separate
## constant so rows 1-3 keep the exact budget they were tuned with. Still far
## under MAX_HERD_LIFETIME (240 s), so the crossing ends on the despawn radius
## like a real one and not on the lifetime cap.
const TOWER_SIM_TICKS: int = 7200


## The terrain, reduced to the two things fauna asks it about the tower. In group
## "terrain", so the manager finds it through the same group lookup it uses in
## the real game, and `tower_excludes` carries the real rule (disc plus the
## candidate's own radius) so the spawn rejection is exercised, not stubbed out.
class TerrainStub extends Node:
	const TOWER_RADIUS: float = 65.0

	func tower_site() -> Vector3:
		return TOWER_SITE

	func tower_excludes(world_x: float, world_z: float, radius: float = 0.0) -> bool:
		return Vector2(world_x - TOWER_SITE.x, world_z - TOWER_SITE.z).length() \
				< TOWER_RADIUS + radius

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
## How far in from each deck edge the rider is parked. Small enough to keep the
## lever arm near the corner's maximum, large enough that the 0.5 m capsule
## still rests on the box rather than teetering off it — the narrowest deck is
## the pack beast's 0.85 m, so an inset much past this would put the rider past
## the far edge entirely.
const RIDE_DECK_INSET: float = 0.3

## Worst per-tick rider displacement allowed BEYOND the animal's own. The herd
## walks RIDE_HERD_SPEED / 60 = 0.0417 m per tick. Measured after the fix:
## 0.0066 / 0.0032 / 0.0023 m (elephant / giraffe / beast — the deck's
## half-diagonal is the lever arm, so the order is the barrel order). With the
## yaw snap: 1.26 / 0.88 / 0.74 m. 0.02 leaves 3x headroom over the worst real
## figure while sitting 37x under the mildest bug reading, so the threshold sits
## in a two-order-of-magnitude gap and is not delicate.
const RIDE_EXCESS_MAX: float = 0.02
## How far the rider may SLIDE ACROSS THE DECK — displacement from where it
## settled, in the animal's own frame (see _finish_ride for why displacement and
## not distance-from-origin). Measured 0.04 m on every species after the fix,
## against 5.64 / 1.36 / 1.24 m with the bug. 0.5 m is 12x the real figure and
## still catches the mildest bug reading on every species, which the old 1.5 m
## did only on the elephant.
const RIDE_DRIFT_MAX: float = 0.5
## NEGATIVE CONTROL 1: the rider has to have been CARRIED for any of the above to
## mean anything. A rider that fell off on frame one and stood on the ground has
## a per-tick excess of zero (it moves less than the herd, not more) and would
## satisfy RIDE_EXCESS_MAX perfectly. So its total travel is measured against the
## herd's and must be nearly all of it. Measured 98% after the fix; a rider left
## behind by the elephant's snap covered 81%.
const RIDE_CARRY_MIN: float = 0.9
## NEGATIVE CONTROL 2: the herd has to have actually TURNED. Delete the swerve
## script — or the yaw write itself — and a herd walking a straight line carries
## its rider flawlessly, passing every assertion above while testing nothing.
## The scripted berth swings the facing ~0.5 rad each way, i.e. ~1.0 rad
## peak-to-peak across the swerve out and the unwind, which is what is measured.
const RIDE_YAW_SWING_MIN: float = 0.4

var _root: Node3D = null
var _manager: Node = null
var _obstacle: StaticBody3D = null
var _obstacle_box: BoxShape3D = null
var _obstacle_shape: CollisionShape3D = null
var _player: CharacterBody3D = null

var _row: int = 0
var _row_half: float = 0.0            # 0.0 == the empty-field control row
var _row_tower: bool = false          # the tower row measures against the SITE, not the box
var _trial: int = 0
var _phase: int = 0
var _wait: int = 0
var _ticks: int = 0
var _trial_min_gap: float = 1e9

## Worst clearance seen per obstacle row (parallel to ROWS), and the largest
## detour seen in the empty-field control.
var _worst_gap: Array[float] = []
var _open_max_avoid: float = 0.0
## Tower row: the closest ANY member came to the site across every trial, how far
## the centre got past it this trial, and how many trials completed the crossing.
var _tower_min_gap: float = 1e9
var _tower_progress: float = -1e9
var _tower_passed: int = 0
var _spawned: int = 0
var _failures: Array[String] = []

## Row 4 state — the species under test, its scripted swerve position, and the
## four figures measured per species (see the RIDE_* constants).
var _ride_species: int = 0
var _ride_phase_i: int = 0
var _ride_phase_left: int = 0
var _ride_prev_rider: Vector3 = Vector3.ZERO
var _ride_prev_herd: Vector3 = Vector3.ZERO
var _ride_start_local: Vector2 = Vector2.ZERO
var _ride_yaw_min: float = 0.0
var _ride_yaw_max: float = 0.0
var _ride_excess: float = 0.0
var _ride_rider_travel: float = 0.0
var _ride_herd_travel: float = 0.0
var _ride_lines: Array[String] = []

## Row 6's one report line (see _check_replay).
var _replay_line: String = ""


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
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

	# The terrain, in group "terrain", present for every row. Rows 1-3 keep the
	# player at the origin and the tower stands 400 m away, so their herds are
	# always more than 219 m from it — beyond TOWER_PLAN_RANGE if aimed at it and
	# far outside the clearance disc if not — and those rows are provably
	# untouched by the plan. Only the tower row parks the player at the site.
	var terrain := TerrainStub.new()
	terrain.add_to_group("terrain")
	_root.add_child(terrain)

	_worst_gap.resize(ROWS.size())
	_worst_gap.fill(1e9)

	_manager = Node.new()
	_manager.set_script(load("res://scripts/fauna_manager.gd"))
	_root.add_child(_manager)
	# NOTHING about the manager is configured here — see phase 0 in
	# _physics_process. A node added from _initialize gets its _ready() on the
	# FIRST FRAME, not now, and Godot's NOTIFICATION_READY re-enables
	# set_physics_process(true) for any script that overrides _physics_process
	# and re-runs fauna_manager._ready(), so both of the things phase 0 does to
	# it would be silently undone if they were done here.


func _physics_process(_delta: float) -> bool:
	match _phase:
		0:
			# Let the static bodies register with the physics server before any
			# query is run against them.
			_wait += 1
			if _wait > 3:
				# TURN THE MANAGER'S OWN PHYSICS CALLBACK OFF — here, past its
				# _ready(), never in _initialize (see the note there). Every row
				# drives _physics_process BY HAND, and a live node in the tree
				# ALSO gets it dispatched by the engine every physics frame, so
				# without this the manager ticks once MORE per frame than the row
				# thinks it does: rows 1-3 got 61 sub-steps instead of 60
				# (harmless), but row 4 ran at DOUBLE rate — i.e. it measured a
				# world with twice the FACING_YAW_RATE_MAX under test, which is
				# stricter than the real one and so silently misreports every
				# figure the constant is tuned against. It also parks the event
				# timer for good: _event_timer is only ever decremented inside
				# _physics_process, so with the dispatch off no herd can spawn
				# itself mid-trial.
				_manager.set_physics_process(false)
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
		7:
			# Row 6 needs no physics at all, so it runs whole in one frame and
			# then reports — see _check_replay.
			_check_replay()
			_report()
	return false


func _start_trial() -> void:
	_row = _trial / TRIALS_PER_ROW
	var row: Dictionary = ROWS[_row]
	_row_half = float(row["half"])
	_row_tower = bool(row.get("tower", false))
	if _row_half > 0.0:
		# Resize the collider for this row BEFORE the herd is aimed at it.
		_obstacle_box.size = Vector3(_row_half * 2.0, float(row["height"]), _row_half * 2.0)
		_obstacle_shape.position = Vector3(0.0, float(row["height"]) * 0.5, 0.0)
	if _row_tower:
		# BOTH placed before the spawn, unlike every other row: _spawn_herd lays
		# the migration line out around the LIVE player position, and this row is
		# the owner's playtest — a player standing at the HQ. That is also what
		# makes the row deterministic without seeding the herd by hand: the line
		# always passes within MIGRATION_MISS (25-60 m) of the player, i.e. always
		# well inside the ~90 m the herd needs to clear the disc.
		_obstacle.position = TOWER_SITE
		_player.position = TOWER_SITE + Vector3(0.0, PLAYER_Y, 0.0)
	_manager.call("_despawn_herd")
	_manager.call("_spawn_herd")
	var animals: Array = _manager.get("_animals")
	if animals.is_empty():
		_finish_trial()
		return
	_spawned += 1
	var herd_pos: Vector3 = _manager.get("_herd_position")
	var heading: Vector3 = _manager.get("_herd_heading")
	if _row_tower:
		pass                             # both already placed, before the spawn
	elif _row_half > 0.0:
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
	_tower_progress = -1e9
	_wait = 0
	_phase = 2


func _run_slice() -> void:
	var budget := TOWER_SIM_TICKS if _row_tower else SIM_TICKS
	for _i: int in TICKS_PER_FRAME:
		if _ticks >= budget:
			break
		_ticks += 1
		_manager.call("_physics_process", DT)
		var animals: Array = _manager.get("_animals")
		if animals.is_empty():
			break                        # herd despawned — the crossing is over
		if _row_tower:
			# Measured against the SITE and the exclusion disc — the contract the
			# rest of the game keeps around this building — not against the box,
			# and per MEMBER rather than per centre, because "did not touch the
			# facade" is a claim about the outermost giraffe.
			for animal: Dictionary in animals:
				var p: Vector3 = (animal["root"] as Node3D).global_position
				_trial_min_gap = minf(_trial_min_gap,
						Vector2(p.x - TOWER_SITE.x, p.z - TOWER_SITE.z).length())
			# Progress along the herd's own heading, past the site. The lateral
			# terms contribute nothing to it, so the line origin is the centre's
			# along-coordinate exactly.
			var pos: Vector3 = _manager.get("_herd_position")
			var head: Vector3 = _manager.get("_herd_heading")
			_tower_progress = maxf(_tower_progress,
					(pos.x - TOWER_SITE.x) * head.x + (pos.z - TOWER_SITE.z) * head.z)
		elif _row_half > 0.0:
			for animal: Dictionary in animals:
				_trial_min_gap = minf(_trial_min_gap,
						_gap_to_obstacle((animal["root"] as Node3D).global_position))
		else:
			_open_max_avoid = maxf(_open_max_avoid,
					absf(float(_manager.get("_avoid_offset"))))
	var animals_left: Array = _manager.get("_animals")
	if _ticks >= budget or animals_left.is_empty():
		_finish_trial()


func _gap_to_obstacle(p: Vector3) -> float:
	## Clearance from this animal to this row's obstacle in the XZ plane;
	## negative means the animal is standing inside it.
	var dx := absf(p.x - _obstacle.position.x) - (_row_half + ANIMAL_HALF_WIDTH)
	var dz := absf(p.z - _obstacle.position.z) - (_row_half + ANIMAL_HALF_WIDTH)
	return maxf(dx, dz)


func _finish_trial() -> void:
	if _row_tower:
		if _trial_min_gap < 1e8:
			_tower_min_gap = minf(_tower_min_gap, _trial_min_gap)
		if _tower_progress >= TOWER_PASSED_MIN:
			_tower_passed += 1
	elif _row_half > 0.0 and _trial_min_gap < 1e8:
		_worst_gap[_row] = minf(_worst_gap[_row], _trial_min_gap)
	_trial += 1
	if _trial >= ROWS.size() * TRIALS_PER_ROW:
		_phase = 4                       # on to row 4, the rider carry
		Sentinel.done("finish_trial")
		return
	_phase = 1
	Sentinel.done("finish_trial")


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

	# Park the rider at the deck's far CORNER — the LONGEST LEVER ARM, which is
	# what the flung distance `angular × r` is proportional to and therefore the
	# only worst case worth measuring. `r` is `hypot(local_x, local_z)` about the
	# root origin, and every barrel is longer than it is wide, so an offset on
	# the x axis alone is close to the MINIMUM: it gives r = 0.45 m on an
	# elephant, 0.15 on a giraffe and 0.075 on a pack beast, against 1.05 / 0.62
	# / 0.51 at the corner — i.e. a row 2-7x less sensitive than it reads.
	var animal_root: Node3D = record["root"]
	var shape: CollisionShape3D = animal_root.get_node("PlatformShape")
	var box: BoxShape3D = shape.shape
	var deck_top: float = shape.position.y + box.size.y * 0.5
	var inset := RIDE_DECK_INSET
	_player.global_position = animal_root.global_transform * Vector3(
			box.size.x * 0.5 - inset, deck_top + 1.05, box.size.z * 0.5 - inset)
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
	var animal_root: Node3D = animals[0]["root"]
	_ride_prev_rider = _player.global_position
	_ride_prev_herd = animal_root.global_position
	# Where the rider is standing IN THE ANIMAL'S OWN FRAME, captured after the
	# settle rather than at placement so the couple of centimetres gravity moves
	# it are not counted as slide. _finish_ride measures against this point.
	_ride_start_local = _local_xz(animal_root, _player.global_position)
	var yaw: float = animal_root.global_rotation.y
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


func _local_xz(animal_root: Node3D, world_pos: Vector3) -> Vector2:
	## Where a world point sits on the animal's deck, in the animal's own frame.
	var local: Vector3 = animal_root.global_transform.affine_inverse() * world_pos
	return Vector2(local.x, local.z)


func _finish_ride() -> void:
	var species_name: String = RIDE_SPECIES[_ride_species]["name"]
	var animals: Array = _manager.get("_animals")
	# Drift is how far the rider SLID ACROSS THE DECK — the displacement from
	# where it settled, measured in the ANIMAL'S OWN FRAME. That is what riding
	# means, and it is what the world-space per-tick figure alone cannot say.
	# Distance from the animal's ORIGIN would be the wrong quantity: the rider is
	# parked at the deck corner, so it starts ~1.1 m out and a reading of 1.16 m
	# would mean "barely moved" while reading like a metre of slide.
	var drift := 1e9
	if not animals.is_empty():
		drift = _local_xz(animals[0]["root"], _player.global_position).distance_to(_ride_start_local)
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
		Sentinel.done("finish_ride")
		_phase = 7
		return
	_phase = 4
	Sentinel.done("finish_ride")


# ---------------------------------------------------------------------------
# Row 6 — THE MULTIPLAYER REPLAY (bead godot-test1-6xc)
# ---------------------------------------------------------------------------

## The params one synthetic `herd` packet carries. `k` is the GIRAFFE index
## (read off the shipped table, never a literal) because the flock is the widest
## formation and the one the owner reported seeing alone.
const REPLAY_SEED: int = 987654321
const REPLAY_ORIGIN: Vector3 = Vector3(40.0, 0.0, -25.0)
const REPLAY_HEADING: float = PI * 0.75
const REPLAY_SPEED: float = 2.5
## How far OFF THE STRAIGHT LINE the synthetic master's centre stands — a berth
## it opened before the first packet, standing in for the meander and the
## obstacle detour, neither of which a peer can see: dead reckoning walks the
## heading and nothing else. The ease closes it geometrically (x0.7 a packet, so
## 5 x 0.7^6 = 0.59 m by the last one); delete the `p` ease in `apply_herd_sync`
## and the peer stays out by the whole 5 m.
const REPLAY_LATERAL_WANDER: float = 5.0
## How close the replayed centre must end up to the master's published one.
## Measured 0.13 m; the 0.59 m the ease is bound to leave sits under it and the
## 5 m the missing ease leaves sits far over, so the threshold is in a gap.
const REPLAY_CENTRE_TOLERANCE: float = 1.0
## How exactly the formation must hold. Every member shares one centre and one
## ease weight and starts on its slot, so member-to-member vectors are the
## difference of two offsets EXACTLY — this is float slop, not a budget.
const REPLAY_FORMATION_TOLERANCE: float = 1e-3
## Non-vacuity floor on (a): GIRAFFE_FLOCK_MIN is 4, so a build that produced one
## animal — or none — would compare two trivially equal signatures.
const GIRAFFE_MIN_FOR_ROW: int = 4
## The synthetic feed: six packets at the shipped 10 Hz sync tick (six frames of
## the harness's 60 Hz per packet), which is 0.6 s of room traffic.
const REPLAY_PACKETS: int = 6
const REPLAY_TICKS_PER_PACKET: int = 6
## Enough ticks for the event timer to fire and the herd to be built — the timer
## is set to one frame, so this is slack, not a schedule.
const REPLAY_SPAWN_TICKS: int = 5

## A room this peer is not the master of. Only the three methods
## `fauna_manager._mp_replays_the_herd()` asks for, so a rename there is a
## silently-skipped row here and not a false pass — the row drives the shipped
## predicate through the shipped group lookup.
const MP_STUB_SOURCE := """extends Node
var online: bool = true
func is_online() -> bool:
	return online
func get_master() -> String:
	return "themaster"
func my_id() -> String:
	return "us"
"""


func _herd_params() -> Dictionary:
	var builders: Array = _manager.get("HERD_BUILDERS")
	return {
		"k": builders.find("_spawn_giraffe_flock"),
		"o": REPLAY_ORIGIN, "h": REPLAY_HEADING,
		"sd": REPLAY_SEED, "sp": REPLAY_SPEED,
	}


func _formation_signature() -> PackedByteArray:
	## Every member's formation slot and stride phase — the two things a build
	## draws off the seeded RNG, and the whole of what "the same herd" means on
	## two machines. Byte-compared, so a one-ULP difference fails.
	var rows: Array = []
	for animal: Dictionary in (_manager.get("_animals") as Array):
		rows.append([animal["offset"], animal["phase"]])
	return var_to_bytes(rows)


func _check_replay() -> void:
	## The four things bead godot-test1-6xc has to be true for the buddy to see
	## the giraffe. Driven on the SHIPPED functions by hand, in one physics frame
	## each — none of this needs the physics server, unlike rows 1-4.
	_manager.call("_despawn_herd")
	_manager.set("_event_timer", 1e9)
	_player.global_position = Vector3(0.0, PLAYER_Y, 0.0)
	_obstacle.position = Vector3(0.0, 0.0, 9000.0)
	var params: Dictionary = _herd_params()

	# (a) ONE SEED, ONE HERD. Two builds off the same params must agree about
	# every member's slot and stride phase, or the master and the peer are
	# drawing two different flocks under one name.
	_manager.call("_build_herd", params)
	var first: PackedByteArray = _formation_signature()
	var members: int = (_manager.get("_animals") as Array).size()
	_manager.call("_despawn_herd")
	_manager.call("_build_herd", params)
	var second: PackedByteArray = _formation_signature()
	_manager.call("_despawn_herd")
	if members < GIRAFFE_MIN_FOR_ROW:
		_failures.append("build-from-params made %d giraffes — this row measured nothing" % members)
	if first != second:
		_failures.append("two builds from seed %d differ — a peer would draw a different herd from the master's"
				% REPLAY_SEED)

	# (b) A REPLAY TRACKS THE MASTER AND KEEPS ITS FORMATION. Six packets, each
	# describing a centre that has walked the line AND wandered off it (the
	# meander and the detour, which the peer cannot see), with the shipped
	# `_physics_process` ticked between them so the dead reckoning runs.
	var heading := Vector3(cos(REPLAY_HEADING), 0.0, sin(REPLAY_HEADING))
	var lateral := Vector3(-heading.z, 0.0, heading.x)
	var travelled := 0.0
	var published := REPLAY_ORIGIN
	for step: int in REPLAY_PACKETS:
		travelled += REPLAY_SPEED * DT * float(REPLAY_TICKS_PER_PACKET)
		published = REPLAY_ORIGIN + heading * travelled \
				+ lateral * REPLAY_LATERAL_WANDER
		var packet: Dictionary = params.duplicate()
		packet["p"] = published
		packet["y"] = REPLAY_HEADING
		packet["d"] = travelled
		_manager.call("apply_herd_sync", packet)
		for _tick: int in REPLAY_TICKS_PER_PACKET:
			_manager.call("_physics_process", DT)
	var animals: Array = _manager.get("_animals")
	if animals.size() != members:
		_failures.append("the replay built %d animals against the master's %d"
				% [animals.size(), members])
	elif animals.is_empty():
		_failures.append("the replay built nothing — this row measured nothing")
	else:
		# Placed at `centre + offset`: every member-to-member vector is the
		# difference of two slots. Measured this way rather than against the
		# centre itself because FORMATION_LERP_SPEED lags the whole formation
		# behind it by design, on the master exactly as here.
		var base_pos: Vector3 = (animals[0]["root"] as Node3D).position
		var base_off: Vector3 = animals[0]["offset"]
		var worst := 0.0
		for animal: Dictionary in animals:
			var drawn: Vector3 = (animal["root"] as Node3D).position - base_pos
			worst = maxf(worst, drawn.distance_to((animal["offset"] as Vector3) - base_off))
		if worst > REPLAY_FORMATION_TOLERANCE:
			_failures.append("replayed formation is out by %.4f m — members are not at centre + offset"
					% worst)
		var centre: Vector3 = _manager.get("_herd_centre")
		# Dead reckoning has run one more packet's worth of ticks since the last
		# `p`, so compare against where the master's centre would be by now.
		var expected: Vector3 = published + heading * (REPLAY_SPEED * DT * float(REPLAY_TICKS_PER_PACKET))
		var gap: float = centre.distance_to(expected)
		if gap > REPLAY_CENTRE_TOLERANCE:
			_failures.append("replayed centre is %.2f m from the master's (max %.2f) — the packet's centre is not being applied"
					% [gap, REPLAY_CENTRE_TOLERANCE])
		if float(_manager.get("_herd_travelled")) <= 0.0:
			_failures.append("replayed herd has walked 0 m — its legs never move")
		_replay_line = "replay: formation %.4f m, centre gap %.2f m, %d members" \
				% [worst, gap, animals.size()]

	# (c) SILENCE FREES IT. No packet for REMOTE_HERD_TIMEOUT and the herd goes,
	# which is the ONE test that also covers a deposed master, a leave and no MP
	# node at all — see fauna_manager.REMOTE_HERD_TIMEOUT.
	var timeout: float = float(_manager.get("REMOTE_HERD_TIMEOUT"))
	for _tick: int in int(timeout / DT) + 10:
		_manager.call("_physics_process", DT)
	if not (_manager.get("_animals") as Array).is_empty():
		_failures.append("a replayed herd survived %.1f s of silence — a dead master's herd is immortal"
				% timeout)

	# (d) A NON-MASTER ROLLS NOTHING, and the SAME manager rolls one the moment
	# the room is gone — the positive control, without which "spawns nothing"
	# would pass on a harness that simply cannot spawn.
	var mp_script := GDScript.new()
	mp_script.source_code = MP_STUB_SOURCE
	mp_script.reload()
	var mp: Node = mp_script.new()
	mp.add_to_group("mp")
	_root.add_child(mp)
	_manager.set("_event_timer", DT)
	for _tick: int in REPLAY_SPAWN_TICKS:
		_manager.call("_physics_process", DT)
	if not (_manager.get("_animals") as Array).is_empty():
		_failures.append("a room NON-MASTER rolled a herd of its own — two crossings in one room")
	if float(_manager.get("_event_timer")) <= 0.0:
		_failures.append("a non-master's event timer stopped re-arming — it would call _spawn_herd every frame")
	mp.set("online", false)
	_manager.set("_event_timer", DT)
	for _tick: int in REPLAY_SPAWN_TICKS:
		_manager.call("_physics_process", DT)
	if (_manager.get("_animals") as Array).is_empty():
		_failures.append("out of the room the manager still spawned nothing — the non-master assertion above measured nothing")
	_manager.call("_despawn_herd")
	mp.queue_free()
	Sentinel.done("check_replay")


func _report() -> void:
	var total := ROWS.size() * TRIALS_PER_ROW
	if _spawned < total:
		_failures.append("only %d of %d trials spawned a herd" % [_spawned, total])
	var line := ""
	for i: int in ROWS.size():
		var row: Dictionary = ROWS[i]
		if float(row["half"]) <= 0.0 or bool(row.get("tower", false)):
			continue          # the control row and the tower row have their own metrics
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

	# The tower: nothing may come inside the exclusion disc, and the crossing has
	# to actually FINISH. The second half is the negative control for the first —
	# a herd that stops dead at 120 m, or oscillates along the facade until it
	# despawns, never touches the disc either and would pass on gap alone.
	if _tower_min_gap > 1e8:
		_failures.append("no tower trial measured a clearance")
	elif _tower_min_gap <= TOWER_RADIUS:
		_failures.append("herd came %.1f m from the tower site — inside the %.0f m exclusion disc, i.e. into the facade"
				% [_tower_min_gap, TOWER_RADIUS])
	if _tower_passed < TRIALS_PER_ROW:
		_failures.append("only %d of %d tower crossings got %.0f m past the site — the rest parked against the building or oscillated along it"
				% [_tower_passed, TRIALS_PER_ROW, TOWER_PASSED_MIN])
	line += "tower: closest %.1f m (disc %.0f m), %d/%d crossings completed | " \
			% [_tower_min_gap, TOWER_RADIUS, _tower_passed, TRIALS_PER_ROW]

	if _failures.is_empty():
		print(line + "empty-field detour: %.2f m" % _open_max_avoid)
		for ride_line: String in _ride_lines:
			print("ride  ", ride_line)
		print(_replay_line)
		Sentinel.finish(self)
		return
	for ride_line: String in _ride_lines:
		print("ride  ", ride_line)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
