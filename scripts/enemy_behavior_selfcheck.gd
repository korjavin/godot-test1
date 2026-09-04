extends SceneTree
## Headless self-check for WHAT A PREDATOR DOES ONCE IT HAS SEEN YOU — one probe
## per behaviour arm in piglet_crocodile_ai.gd, plus the two capabilities that are
## row keys rather than arms (the view cone, the scent nose).
##
##   godot --headless --path . --script res://scripts/enemy_behavior_selfcheck.gd
##
## THE OTHER HALF IS `scripts/enemy_spawn_selfcheck.gd`: where a body lands, what
## species a chunk resolves, and what a peer calls it. The two were ONE 5,100-line
## file until bead `godot-test1-ftn.13` split them by check family, and the split
## is mechanical — every probe below is the code it always was, stamping the name
## it always stamped. They are separate FILES and not separate measurements: CI's
## `selfcheck-shard` globs `scripts/*_selfcheck.gd` and shards by count, so a file
## that is a third of the suite's wall clock on its own is a shard nothing can
## balance.
##
## THE COVERAGE IS DRIVEN BY THE TABLE, NOT BY A LIST IN THIS FILE. `_species_with()`
## asks `SPECIES` who carries an arm, so a SECOND burst row or a THIRD coned row is
## measured the day it lands and nothing here names an animal. The gate that makes
## that binding two-way lives in the spawn check — `enemy_spawn_selfcheck`'s
## `PROBED_BEHAVIORS` fails, BY NAME, a row whose `behavior` string has no probe
## here — so a new arm has to bring a probe with it.
##
## HOUSE RULE, followed throughout: every probe drives the SHIPPED arm on a LIVE
## body against a live stub quarry and measures the trajectory that came out.
## "A pack surrounds" and "a charge can be sidestepped" are claims about a path
## through space, and nothing but a path can answer them; a probe that read the
## row back would pass on a species whose arm never runs at all. Every check has a
## negative control beside it for the same reason.
##
## THE ONE THING IT PRINTS THAT IS NOT ITS OWN: a handful of "RID allocations …
## were leaked at exit" / "resources still in use at exit" lines AFTER the
## verdict. Those are the engine reporting the STATIC shared caches this project
## deliberately keeps — endless_terrain's shared unit box, ToonShading's
## styled-material cache, and the crocodile PackedScene loaded below — none of
## which is owned by, or releasable from, a check. They appear after the exit code
## is decided and are NOT a failure. Everything else must stay silent: a run that
## prints a SCRIPT ERROR beside SELFCHECK OK is measuring a world it did not
## build.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const CROC_AI_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"
const LOD_SCRIPT: String = "res://scripts/crocodile_lod_manager.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## How much room a row's `detection_radius` must leave under the LOD manager's
## SIM_RADIUS. The hunt probe measures a ring against it; the ASSERTION on the
## whole table is `enemy_spawn_selfcheck`'s check 4, which is where the constant's
## reasoning is written down. Restated here rather than reached for, because a
## self-check importing another self-check's constants is a dependency between two
## files that are meant to be readable one at a time.
const DETECTION_SIM_MARGIN: float = 15.0

## Field side in chunks, for the tracker-adoption walk (check 8g) — the one probe
## here that streams real chunks. 17 x 17 = 289, the size every measurement in
## CLAUDE.md's terrain sections is quoted at.
const FIELD: int = 17

## Two run seeds, not one. The biome offset is derived from run_seed, so a single
## seed can land most of a field in one band and present the adoption walk with
## nothing to adopt.
const RUN_SEEDS: Array[int] = [12345, 20260826]

## Float slack. A body resting exactly on a face is correct, not a failure.
const EPSILON: float = 0.001


var _failures: Array[String] = []

## piglet_crocodile_ai.gd's SPECIES table and endless_terrain.gd's BIOME_SPECIES /
## BIOME_BOSS maps, read once in _run() through get_script_constant_map() —
## constants are not properties, so `croc.get("SPECIES")` answers null and a probe
## written that way would measure an empty table and pass vacuously.
var _species_table: Dictionary = {}
var _biome_species: Dictionary = {}
var _biome_boss: Dictionary = {}

## The two ends of the speed lattice, read off player_controller.gd and
## piglet_crocodile_ai.gd rather than restated — see the note in _run().
var _walk_speed: float = 0.0
var _max_chase_speed: float = 0.0

## BOSS_DETECTION_RADIUS off piglet_crocodile_ai.gd. The ranged probe needs it
## because a boss overrides its row's detection radius with this one, so it is
## the number a BOSS-ONLY archer's firing band has to fit inside.
var _boss_detection_radius: float = 0.0

## BOSS_CHASE_SPEED and BOSS_TERRITORY_RADIUS, read the same way and for the same
## reason. The leap probe needs both: a BOSS-ONLY leaper's row states a
## `chase_speed` that a boss OVERRIDES (see the is_boss branch in _ready()), so
## racing its stated 5.5 would measure an animal the game never builds — and the
## reach of a hop is judged against the territory it must land inside.
var _boss_chase_speed: float = 0.0
var _boss_territory_radius: float = 0.0

## Species dispatched from BIOME_BOSS and from nowhere in BIOME_SPECIES, filled
## in by _derive_boss_only() before any probe runs. Two probes need the same
## answer — the ranged probe measures a boss-only archer's firing band against the
## BOSS detection radius rather than the row's, and the leap probe races the boss
## speed rather than the row's — so it is derived once, from the dispatch maps,
## and never listed.
var _boss_only: Dictionary = {}

## crocodile_lod_manager.gd's SIM_RADIUS, read the same way. The ceiling every
## row's `detection_radius` sits under; the scent check measures a nose against it,
## because a tracker that never sleeps needs none of `advance_tracking`.
var _sim_radius: float = 0.0

## The SLOWEST character's run — RUN_SPEED x the smallest CHARACTER_SPEED, both
## read off player_controller.gd in _run(). This is the number MAX_CHASE_SPEED is
## held under so that "running always escapes" is true, and the burst and leap
## races are run against it. Derived rather than written down as 9.0 because a new
## character with a lower speed stat would move it, and a check asserting a stale
## 9.0 would pass while the promise quietly broke.
var _slowest_run_speed: float = 0.0


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_boot()


func _boot() -> void:
	"""
	Wait ONE frame before generating anything.

	A node added to `root` from inside _initialize() is not `is_inside_tree()`
	until the first frame — the same trap best_run_e2e.gd is written around. Here
	it would make every chunk parent _make_chunk_parent() creates a detached node
	in disguise, so anything reading a global transform would see a zero one and
	the check would go on printing engine errors beside its own OK.
	"""
	await process_frame
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	# get_script_constant_map() is how a `const` is read from outside: constants
	# are not properties, so terrain.get("BIOME_SPECIES") answers null and a probe
	# written that way would measure against {} and pass vacuously.
	var consts: Dictionary = terrain_script.get_script_constant_map()

	# The lattice's two ends are READ, never restated here: WALK_SPEED off the
	# player and MAX_CHASE_SPEED off the AI, so retuning either moves these probes
	# with it instead of leaving them asserting a number nothing uses any more.
	var croc_ai: GDScript = load(CROC_AI_SCRIPT)
	var croc_consts: Dictionary = croc_ai.get_script_constant_map()
	_species_table = croc_consts.get("SPECIES", {})
	_max_chase_speed = float(croc_consts.get("MAX_CHASE_SPEED", 0.0))
	_boss_detection_radius = float(croc_consts.get("BOSS_DETECTION_RADIUS", 0.0))
	_boss_chase_speed = float(croc_consts.get("BOSS_CHASE_SPEED", 0.0))
	_boss_territory_radius = float(croc_consts.get("BOSS_TERRITORY_RADIUS", 0.0))
	var player_consts: Dictionary = load(PLAYER_SCRIPT).get_script_constant_map()
	_walk_speed = float(player_consts.get("WALK_SPEED", 0.0))
	# The slowest run, derived the way player_controller derives it (see
	# _slowest_run_speed). An empty table would leave this 0.0, which the burst and
	# leap probes report as a failure rather than passing vacuously against a zero
	# ceiling.
	var character_speed: Dictionary = player_consts.get("CHARACTER_SPEED", {})
	var slowest_scale: float = INF
	for name_v: Variant in character_speed:
		slowest_scale = minf(slowest_scale, float(character_speed[name_v]))
	if slowest_scale < INF:
		_slowest_run_speed = float(player_consts.get("RUN_SPEED", 0.0)) * slowest_scale
	# NO GUARD ON A ZERO HERE, deliberately: the table's own completeness — an
	# empty SPECIES, a missing SIM_RADIUS, a band with no boss — is
	# `enemy_spawn_selfcheck`'s check 4, and a second copy of those messages in a
	# second file is a second place to edit when one of them is retuned.
	_sim_radius = float(load(LOD_SCRIPT).get_script_constant_map().get("SIM_RADIUS", 0.0))
	_biome_species = consts.get("BIOME_SPECIES", {})
	_biome_boss = consts.get("BIOME_BOSS", {})
	_derive_boss_only()

	# One call per BEHAVIOUR, and each one probes EVERY species carrying it — see
	# _species_with(). Nothing here names an animal; a second charger or a third
	# burst row is measured the moment its row lands.
	_check_pack_surround(croc_ai)
	_check_ambush_trip_wire()
	_check_charge_dodge(croc_ai)
	_check_burst_escape(croc_ai)
	_check_ranged_cadence(croc_ai)
	_check_hunt_pacing(croc_ai)
	_check_scent_tracking()
	_check_wanderer_adoption(terrain_script)
	_check_leap_cycle(croc_ai)
	_check_view_cone(croc_ai)
	_check_crowd_confusion(croc_ai)

	_report()


func _derive_boss_only() -> void:
	"""
	WHICH ROWS ARE BOSS-ONLY: dispatched from BIOME_BOSS and from nowhere in
	BIOME_SPECIES.

	DERIVED from the two dispatch maps rather than listed — give a boss row an
	ordinary BIOME_SPECIES entry and it stops being exempt on the same commit,
	with no edit in this file. `enemy_spawn_selfcheck` derives the same set the
	same way for the lattice's lower bound; the eight lines are duplicated rather
	than shared because a self-check reaching into another self-check is a
	dependency between two files that are meant to be readable one at a time.
	"""
	var ordinary_species: Dictionary = {}
	for biome_v: Variant in _biome_species:
		ordinary_species[String(_biome_species[biome_v].get("species", ""))] = true
	_boss_only.clear()
	for biome_v: Variant in _biome_boss:
		var boss_species: String = String(_biome_boss[biome_v].get("species", ""))
		if not ordinary_species.has(boss_species):
			_boss_only[boss_species] = true


func _species_with(behavior: String) -> Array[String]:
	"""
	Every SPECIES row carrying this `behavior`, in table order.

	@param behavior: the value of the row's "behavior" key
	@return the species names, possibly empty

	The reason the behaviour probes below take a LIST rather than the first match:
	two rows already share the burst arm (the cougar and the alley hound, same
	code and different numbers), which is the shape the epic settled on — so
	"find the pack species" is a question with no stable answer, and a probe
	written that way silently stops measuring the second wolf the day it ships.
	"""
	var found: Array[String] = []
	for name_v: Variant in _species_table:
		if String(_species_table[name_v].get("behavior", "")) == behavior:
			found.append(String(name_v))
	return found


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _make_chunk_parent(origin: Vector3) -> MeshInstance3D:
	"""
	A stand-in for the chunk MeshInstance3D, IN THE TREE at its world origin.

	@param origin: The chunk's world position (chunk_to_world).
	@return The parent node the spawners are handed. Freed with queue_free().

	IT HAS TO BE IN THE TREE, unlike prop_selfcheck.gd's terrain node, and the
	difference is which functions are being driven. A prop builder reaches only
	create_box; the chunk spawners reach node code that asks the tree about
	itself — `treasure_chest.setup()` calls `get_global_transform()` and
	`get_tree().get_first_node_in_group(...)`, and `spawn_platform_crocodiles`
	hands `set_confinement` a `parent_chunk.global_position`. Detached, all three
	answer with an engine error and a zero: a run printed 195 error lines and
	still exited 0 with SELFCHECK OK, which is the exact "green lie" this
	project's checks exist to avoid (its two siblings print none). In the tree at
	the real origin they are all simply correct, and `global_position` can then be
	read straight off a crocodile rather than reconstructed.

	The terrain node itself stays DETACHED — its _ready() would roll a random run
	seed over the one this sweep set and start streaming chunks of its own.
	"""
	var parent := MeshInstance3D.new()
	parent.position = origin
	root.add_child(parent)
	return parent


func _bearing_spread_deg(bearings: Array[float]) -> float:
	"""
	The arc a set of compass bearings covers, in degrees.

	Sort them, find the widest EMPTY gap on the circle, and the answer is 360°
	minus that gap. This is the standard circular-range measure and it is the
	right one here for a reason a naive max-minus-min would get wrong: bearings
	wrap, so four wolves at 10°, 100°, 190° and 350° span 340°, not 340° in one
	direction and a spurious 0 in the other.
	"""
	if bearings.size() < 2:
		return 0.0
	var sorted: Array[float] = bearings.duplicate()
	sorted.sort()
	var widest_gap: float = TAU - (sorted[-1] - sorted[0])   # the wrap-around gap
	for i in range(1, sorted.size()):
		widest_gap = maxf(widest_gap, sorted[i] - sorted[i - 1])
	return rad_to_deg(TAU - widest_gap)


# ============================================================================
# CHECK 5 — a pack ACTUALLY surrounds, and a solo predator actually doesn't
# ============================================================================

## How many wolves stand in for one chunk's pack, and over how many chunks the
## measurement is repeated. The ids come from the REAL node-name scheme, so this
## is not a sample of a random variable — every number below is a constant of the
## shipped name hash and re-measuring gives the same answer forever.
const PACK_PROBE_WOLVES: int = 6
const PACK_PROBE_CHUNKS: int = 24

## The pack starts clustered on ONE bearing at this range — the hardest possible
## start for a surround, and the one a straight-line chaser handles perfectly.
const PACK_PROBE_START: float = 16.0
## Where a wolf counts as having ARRIVED, and where its attack bearing is read.
## Well outside the ring (4 m) so the reading is not taken from the noise of the
## final metre, and well inside the 18 m detection radius.
const PACK_PROBE_ARRIVE: float = 3.0
## Integration step and budget. 12 s is nearly double the ~6.5 s a 6.8 m/s wolf
## needs to walk 16 m plus a half-circle, so failing to arrive means STALLED.
const PACK_PROBE_DT: float = 1.0 / 30.0
const PACK_PROBE_SECONDS: float = 12.0

## The verdict. A pack's mean spread of attack bearings must clear 100°, and the
## same wolves with the flank switched off must stay under 5° — see the note in
## _check_pack_surround on why both numbers are stated and neither is tight.
## Today's steering measures ~136° against ~0°.
const PACK_SPREAD_MIN_DEG: float = 100.0
const PACK_CONTROL_MAX_DEG: float = 5.0


func _check_pack_surround(croc_ai: GDScript) -> void:
	"""
	MEASURE the surround. Do not assert it.

	`pack_steer_point()` is easy to write in a way that reads correctly and does
	not work: a ring that never tapers leaves the pack orbiting a player who can
	stand still in the middle of it, a taper that closes too early collapses the
	pack into the single-file queue it was built to replace, and an id-to-slot
	mapping that degenerates (every wolf in a chunk drawing the same bearing)
	looks fine in the source and produces a conga line on screen. None of those
	is an error anywhere — which is this file's entire subject.

	So this simulates. Six wolves, ids taken from the REAL deterministic node
	names spawn_crocodiles_in_chunk gives them, all starting CLUSTERED ON ONE
	BEARING 16 m out and all facing the quarry — the worst case for a surround
	and the case a straight-line chaser handles perfectly. Each step re-runs the
	shipped steering and the shipped two lines of movement (lerp_angle toward the
	heading at the species' own turn_smoothness, then travel along the facing at
	its own chase_speed), so what is being measured is the code that ships, not a
	restatement of it. The bearing each wolf holds when it first closes to 3 m is
	the angle it ATTACKED from, and the spread of those bearings is the surround.

	THE NEGATIVE CONTROL IS THE OTHER HALF, following this file's house rule: the
	identical run with the flank offset switched off must collapse to a single
	bearing. Without it, "the wolves attacked from many angles" is also true of a
	check that spread them out in its own setup.

	WHAT THE MODEL LEAVES OUT, honestly: obstacle feelers, wolf-on-wolf collision
	and gravity. All three perturb the PATH; none can change where the ring slots
	are, because a slot is a pure function of an id. They would widen the arcs,
	not narrow them.

	The thresholds are deliberately loose — 100° against a measured ~136°, 5°
	against a measured 0° — because this is a guard against the behaviour being
	GONE or DEGENERATE, not a pin on today's exact tuning. Retuning
	pack_flank_radius should not have to come here; PACK_FLANK_TAPER, which the
	arc is directly proportional to, has a hard bound of its own checked below.
	"""
	var names: Array[String] = _species_with("pack")
	if names.is_empty():
		_fail("no SPECIES row has behavior 'pack' — the pack steering this check"
				+ " measures is not reachable from any species")
		Sentinel.done("pack_surround")
		return
	for wolf_species: String in names:
		_probe_pack(croc_ai, wolf_species)
	Sentinel.done("pack_surround")


func _probe_pack(croc_ai: GDScript, wolf_species: String) -> void:
	"""
	Run the whole surround measurement against ONE pack species.

	@param croc_ai: the AI script, for its static pack_steer_point
	@param wolf_species: the SPECIES key to probe

	Split out of _check_pack_surround — which holds the argument for all of this
	— so that every row carrying the behaviour is measured, not the first one the
	table happens to hand back.
	"""
	var row: Dictionary = _species_table[wolf_species]
	for key: String in ["pack_size", "pack_flank_radius"]:
		if not row.has(key):
			_fail("SPECIES['%s'] has behavior 'pack' but no '%s' —" % [wolf_species, key]
					+ " _behave_pack reads it every frame it chases")
			return
	var pack_size: int = int(row["pack_size"])
	var flank: float = float(row["pack_flank_radius"])
	var speed: float = float(row["chase_speed"])
	var turn: float = float(row["turn_smoothness"])
	if pack_size < 2:
		_fail("SPECIES['%s'].pack_size is %d — a ring with fewer than two slots"
				% [wolf_species, pack_size] + " is a single-file queue")
		return

	# ---- the anti-orbit invariant, stated directly on the function ----------
	# A wolf standing ON its own slot bearing at distance d is offered the point
	# d * TAPER along that same bearing. At TAPER >= 1.0 that point is the wolf's
	# own position (or further out) — every point of its slot ray is a fixed
	# point, and the pack freezes in a ring around a player who then strolls
	# away. This is the singularity PACK_FLANK_TAPER's doc block is about, and it
	# is checked here rather than trusted because the failure is a pack that
	# looks perfectly composed while being completely harmless.
	#
	# AND IT IS CHECKED AS ARITHMETIC RATHER THAN LEFT TO THE SIMULATION BELOW
	# BECAUSE THE SIMULATION DOES NOT CATCH IT. Measured: with TAPER set to
	# exactly 1.0 the probe still reports a healthy 152° of surround and every
	# wolf still arrives, because a wolf approaching at an angle never lands
	# exactly on its own slot ray and so never meets the fixed point. The freeze
	# is a measure-zero set the integrator steps straight over, and a live wolf
	# tracking a player who happens to walk along its bearing finds it. Two
	# halves, then: the bound is proved, the shape is measured.
	var taper: float = float(load(CROC_AI_SCRIPT).get_script_constant_map()
			.get("PACK_FLANK_TAPER", 1.0))
	if taper >= 1.0 or taper <= 0.0:
		_fail("PACK_FLANK_TAPER is %.2f — outside (0, 1) the flank ring either" % taper
				+ " vanishes or becomes an orbit no wolf can ever leave")
	var quarry := Vector3(11.0, 0.0, -7.0)   # nothing special, just not the origin
	for slot in range(pack_size):
		for d: float in [0.5, 1.0, 4.0, 9.0, 18.0, 40.0]:
			var from := quarry + Vector3(d, 0.0, 0.0)
			var point: Vector3 = CrocSteering.pack_steer_point(quarry, from, slot, pack_size, flank)
			var ring: float = (point - quarry).length()
			# Both ceilings the function promises: the taper (which is what
			# guarantees a wolf always has somewhere left to walk) and the row's
			# own flank radius.
			if ring > d * taper + EPSILON:
				_fail(("SPECIES['%s'] slot %d at %.1f m steers %.2f m off the quarry —"
						% [wolf_species, slot, d, ring])
						+ " past the %.2f taper, so a wolf on its own slot bearing" % taper
						+ " has nowhere left to walk")
			if ring > flank + EPSILON:
				_fail("SPECIES['%s'] slot %d steers %.2f m off the quarry, past its own"
						% [wolf_species, slot, ring]
						+ " pack_flank_radius %.2f" % flank)

	# ---- the emergence measurement -----------------------------------------
	var pack_spread := 0.0
	var control_spread := 0.0
	var stalled := 0
	var worst_stall := ""
	var slots_seen_total := 0

	for c in range(PACK_PROBE_CHUNKS):
		# Real chunk coordinates, spread over the field so this is not one
		# lucky corner of the hash. The name scheme is the spawner's own.
		var chunk := Vector2i(c % 6 - 3, c / 6 - 2)
		var ids: Array[int] = []
		var slots := {}
		for i in range(PACK_PROBE_WOLVES):
			var id: int = croc_ai.croc_id_for("Crocodile_%d_%d_%d" % [chunk.x, chunk.y, i])
			ids.append(id)
			slots[posmod(id, pack_size)] = true
		slots_seen_total += slots.size()

		for flanking in [true, false]:
			var bearings: Array[float] = []
			for i in range(ids.size()):
				# All six on the SAME spot 16 m out (+X), all facing the quarry.
				# Identical starts are what make the negative control absolute:
				# with the flank off, six wolves that begin at one point and run
				# the same steering must arrive on ONE bearing, spread 0°. Any
				# separation this probe could have handed them for free is a
				# separation the flank did not have to earn.
				var pos := quarry + Vector3(PACK_PROBE_START, 0.0, 0.0)
				var yaw := atan2(quarry.x - pos.x, quarry.z - pos.z)
				var arrived := false
				var steps := int(PACK_PROBE_SECONDS / PACK_PROBE_DT)
				for _step in range(steps):
					var target: Vector3 = quarry
					if flanking:
						target = CrocSteering.pack_steer_point(
								quarry, pos, ids[i], pack_size, flank)
					var to_target := target - pos
					to_target.y = 0.0
					# The two lines _physics_process actually runs, verbatim in
					# shape: turn toward the heading, then travel along the
					# facing (never along the raw direction).
					if to_target.length() > 0.1:
						yaw = lerp_angle(yaw, atan2(to_target.x, to_target.z),
								PACK_PROBE_DT * turn)
					pos += Vector3(sin(yaw), 0.0, cos(yaw)) * speed * PACK_PROBE_DT
					if pos.distance_to(quarry) <= PACK_PROBE_ARRIVE:
						arrived = true
						# The bearing FROM the quarry: which side it came in on.
						bearings.append(atan2(pos.x - quarry.x, pos.z - quarry.z))
						break
				if not arrived:
					stalled += 1
					if worst_stall == "":
						worst_stall = "%s wolf %d of chunk %v stopped %.1f m out" % [
								"flanking" if flanking else "control", i, chunk,
								pos.distance_to(quarry)]
			var spread := _bearing_spread_deg(bearings)
			if flanking:
				pack_spread += spread
			else:
				control_spread += spread

	pack_spread /= float(PACK_PROBE_CHUNKS)
	control_spread /= float(PACK_PROBE_CHUNKS)
	var mean_slots := float(slots_seen_total) / float(PACK_PROBE_CHUNKS)
	print("pack surround: %d wolves x %d chunks reach %.1f m on bearings spanning"
			% [PACK_PROBE_WOLVES, PACK_PROBE_CHUNKS, PACK_PROBE_ARRIVE]
			+ " %.0f° (same wolves, flank off: %.0f°); %.1f of %d ring slots claimed"
			% [pack_spread, control_spread, mean_slots, pack_size])

	if stalled > 0:
		_fail("%d of %d pack probes never reached the quarry (first: %s) —" % [
				stalled, PACK_PROBE_WOLVES * PACK_PROBE_CHUNKS * 2, worst_stall]
				+ " the flank ring became an orbit")
	if pack_spread < PACK_SPREAD_MIN_DEG:
		_fail("a pack starting on one bearing attacks from only %.0f° of arc"
				% pack_spread + " (want >= %.0f°) — the surround is gone"
				% PACK_SPREAD_MIN_DEG)
	if control_spread > PACK_CONTROL_MAX_DEG:
		_fail("the NEGATIVE CONTROL spread %.0f° with the flank switched off"
				% control_spread + " — the %.0f° measured with it on is coming from"
				% pack_spread + " the probe's own setup, not from the steering")
	# The pack must actually be USING its ring. Six ids collapsing onto one or two
	# slots is a conga line the spread test above could still pass by luck.
	if mean_slots < 3.0:
		_fail("six wolves claim only %.1f of %d ring slots on average —" % [
				mean_slots, pack_size]
				+ " `id %% pack_size` has degenerated and they share bearings")


# ============================================================================
# CHECK 6 — an ambusher really does LIE THERE, and really does strike
# ============================================================================

## The two lanes a quarry is walked past the ambusher on, in metres of lateral
## offset. OUTSIDE is beyond the viper's 5 m trigger and comfortably inside the
## crocodile's 15 m one, which is what makes the same lane serve as this check's
## negative control. INSIDE is a third of the trigger: unmistakably stepped on.
const AMBUSH_LANE_OUTSIDE: float = 8.0
const AMBUSH_LANE_INSIDE: float = 1.5

## How far up and down the lane the quarry walks, and at what resolution. 12 m
## either side of the predator is well past every detection radius in the table,
## so every probe starts and ends with nothing smelled.
const AMBUSH_WALK_HALF: float = 12.0
const AMBUSH_PROBE_DT: float = 1.0 / 60.0

## Where the strike counts as LANDED. The viper's node origin is its head (see
## the capsule note in the SPECIES row) and the player is not a point, so a metre
## between origins is contact with room to spare.
const AMBUSH_STRUCK: float = 1.0

## How far a predator may drift while a quarry walks past outside its trigger.
## This is a real zero, not a tolerance: `move_speed` 0.0 makes the wander
## velocity identically zero at every point of the sin cycle.
const AMBUSH_DRIFT_MAX: float = EPSILON


func _check_ambush_trip_wire() -> void:
	"""
	MEASURE the ambush. Do not assert it.

	An ambusher is defined by two behaviours that are the opposite of each other,
	and both of them are invisible from the outside — which is this file's whole
	subject. It must NOT close on a player who walks past outside its trigger (a
	viper that creeps is not buried, it is just a slow crocodile), and it MUST
	strike a player who walks through it (a viper that does not is a rock). Every
	way of losing either is silent: raise `move_speed` off zero and the ambusher
	wanders out of the patch it was hiding in; drop `chase_speed` under WALK_SPEED
	or let `sniff_pause_chance` back above zero and the strike simply never
	arrives, with nothing logged anywhere.

	So this walks a quarry past a stationary predator at WALK_SPEED, twice, and
	runs the shipped movement shape each step: the detection test out of
	_update_chase_state (distance against the row's own radius), then the two
	lines out of _physics_process (lerp_angle toward the heading at the row's own
	turn_smoothness, then travel along the FACING — never along the raw
	direction — at the row's own speed).

	THE NEGATIVE CONTROL IS THE SAME TWO WALKS RUN AGAINST THE CROCODILE ROW, and
	the outside lane is chosen so it lands inside the crocodile's 15 m detection
	and outside the viper's 5 m one. Without it, "the predator did not move" is
	also true of a probe that never moves anything and "it never got closer" is
	also true of a probe that measures the wrong distance.

	WHAT THE MODEL LEAVES OUT, honestly: obstacle feelers, gravity, the per-frame
	wander steer (the probe holds a fixed idle heading, so the drift it reports is
	a floor on the real one, never a ceiling) and the per-instance speed roll. The
	roll is covered separately and arithmetically — the row's spread is checked
	against WALK_SPEED in _check_species_table — and it cannot rescue a zero:
	anything times `move_speed` 0.0 is 0.0.
	"""
	var names: Array[String] = _species_with("ambush")
	if names.is_empty():
		_fail("no SPECIES row has behavior 'ambush' — the burrow-and-strike this"
				+ " check measures is not reachable from any species")
		Sentinel.done("ambush_trip_wire")
		return
	for ambush_species: String in names:
		_probe_ambush(ambush_species)
	Sentinel.done("ambush_trip_wire")


func _probe_ambush(ambush_species: String) -> void:
	"""
	Run the whole trip-wire measurement against ONE ambush species.

	@param ambush_species: the SPECIES key to probe

	Split out of _check_ambush_trip_wire — which holds the argument for all of
	this — so every ambusher is measured rather than the first one found.
	"""
	var row: Dictionary = _species_table[ambush_species]
	for key: String in ["ambush_burrow_depth", "ambush_surface_ease_speed"]:
		if not row.has(key):
			_fail("SPECIES['%s'] has behavior 'ambush' but no '%s' —" % [ambush_species, key]
					+ " _tick_river_sink reads it on every frame it is buried")
			return

	# ---- the burrow actually buries, measured off the MESH --------------------
	# The house rule again: the depth is checked against the model's real AABB,
	# not against the figure quoted in the row's comment, because a regenerated
	# GLB is exactly the kind of change that leaves a comment true and a number
	# wrong — and the failure is a snake-shaped ridge lying in the sand, which no
	# system anywhere considers an error.
	var scene_path := ""
	for biome_v: Variant in _biome_species:
		if String(_biome_species[biome_v].get("species", "")) == ambush_species:
			scene_path = String(_biome_species[biome_v].get("scene", ""))
			break
	var mesh_top: float = _model_top(scene_path)
	var burrow: float = float(row["ambush_burrow_depth"])
	# The bob is the highest the animation ever lifts the model off its rest
	# height (breathing is shallower), so mesh top + bob is the tallest this
	# animal ever stands and the depth has to clear it.
	var needed: float = mesh_top + float(row["bob_amount"])
	if mesh_top <= 0.0:
		_fail("could not measure a model AABB for '%s' from '%s' —" % [ambush_species, scene_path]
				+ " the burrow depth check has nothing to measure against")
	elif burrow < needed:
		_fail("SPECIES['%s'].ambush_burrow_depth %.3f does not clear its own mesh"
				% [ambush_species, burrow]
				+ " (%.4f tall + %.3f of bob) — it waits in ambush with its back out"
				% [mesh_top, float(row["bob_amount"])])
	# Surfacing must be FASTER than sinking, which is the whole "surfaces rapidly"
	# half of the spec: at or below the sink ease the strike is a slow reveal.
	if float(row["ambush_surface_ease_speed"]) <= float(row["river_sink_ease_speed"]):
		_fail("SPECIES['%s'] surfaces at %.2f m/s but sinks at %.2f —" % [ambush_species,
				float(row["ambush_surface_ease_speed"]), float(row["river_sink_ease_speed"])]
				+ " an ambusher that rises no faster than it settles has no strike")

	# ---- AN AMBUSHER IS NOT A SPRINTER (bead godot-test1-lyk) ---------------
	# It shipped as the FASTEST chase_speed in the table, and the lattice never
	# noticed because MAX_CHASE_SPEED clamped the product — the row was legal and
	# unplayable at the same time, which is precisely the state _check_species_table
	# says a bad row hides in. The design rule that came out of it: a predator you
	# cannot see coming is paid in SURPRISE, so it does not also get to be the
	# quickest thing in the world. Stated against the table rather than a literal,
	# so retuning any other row keeps this honest.
	#
	# Stated as ">= the fastest OTHER row" rather than "is the max", because a TIE
	# at the top is the same animal: a viper matching the cougar's 7.8 is jointly
	# the fastest thing in the world and still invisible. Written the other way —
	# scanning for the maximum and comparing names — a tie resolves to whichever
	# row Dictionary iteration reached first, so the check would pass or fail on
	# key order. A tie at the BOTTOM is fine and deliberate: 5.5 alongside the
	# crocodile is exactly what this bead asked for.
	var fastest_other := -INF
	var fastest_other_name := ""
	for name_v: Variant in _species_table:
		if String(name_v) == ambush_species:
			continue
		var speed: float = float(_species_table[name_v].get("chase_speed", 0.0))
		if speed > fastest_other:
			fastest_other = speed
			fastest_other_name = String(name_v)
	var ambush_speed: float = float(row.get("chase_speed", 0.0))
	if fastest_other_name == "":
		_fail("SPECIES has no non-ambush row to compare '%s' against —" % ambush_species
				+ " the ambusher-is-not-a-sprinter check has nothing to measure")
	elif ambush_speed >= fastest_other:
		_fail("'%s' chase_speed %.2f is at or above the fastest other row ('%s' %.2f) —"
				% [ambush_species, ambush_speed, fastest_other_name, fastest_other]
				+ " it is buried, unseen and the quickest animal in the game at once;"
				+ " the clamp hides it, and the player only finds out on the strike")

	# ---- the trip-wire measurement ------------------------------------------
	var results := {}
	for probe_species: String in [ambush_species, "crocodile"]:
		for lane: float in [AMBUSH_LANE_OUTSIDE, AMBUSH_LANE_INSIDE]:
			results["%s@%.1f" % [probe_species, lane]] = _walk_past(
					_species_table[probe_species], lane)

	var out_amb: Dictionary = results["%s@%.1f" % [ambush_species, AMBUSH_LANE_OUTSIDE]]
	var in_amb: Dictionary = results["%s@%.1f" % [ambush_species, AMBUSH_LANE_INSIDE]]
	var out_croc: Dictionary = results["crocodile@%.1f" % AMBUSH_LANE_OUTSIDE]
	var in_croc: Dictionary = results["crocodile@%.1f" % AMBUSH_LANE_INSIDE]

	print("ambush trip-wire: a %.1f m/s quarry passing at %.1f m leaves the %s"
			% [_walk_speed, AMBUSH_LANE_OUTSIDE, ambush_species]
			+ " %.3f m from where it started (closest %.2f m) and the crocodile"
			% [out_amb["travelled"], out_amb["closest"]]
			+ " %.2f m (closest %.2f m); at %.1f m they close to %.2f m and %.2f m"
			% [out_croc["travelled"], out_croc["closest"], AMBUSH_LANE_INSIDE,
					in_amb["closest"], in_croc["closest"]])

	if out_amb["travelled"] > AMBUSH_DRIFT_MAX:
		_fail("'%s' moved %.3f m while a quarry walked past %.1f m away —" % [
				ambush_species, out_amb["travelled"], AMBUSH_LANE_OUTSIDE]
				+ " a buried ambusher does not close distance on anything")
	if out_amb["closest"] < AMBUSH_LANE_OUTSIDE - EPSILON:
		_fail("'%s' let the quarry get %.2f m away on a lane %.1f m wide —" % [
				ambush_species, out_amb["closest"], AMBUSH_LANE_OUTSIDE]
				+ " it followed rather than waited")
	if in_amb["closest"] > AMBUSH_STRUCK:
		_fail("'%s' only reached %.2f m of a quarry that walked straight through"
				% [ambush_species, in_amb["closest"]]
				+ " its %.1f m trigger (want <= %.1f m) — the strike is gone"
				% [float(row["detection_radius"]), AMBUSH_STRUCK])
	# The controls: the same two walks against a species that hunts.
	if out_croc["travelled"] <= AMBUSH_DRIFT_MAX or out_croc["closest"] >= AMBUSH_LANE_OUTSIDE:
		_fail("the NEGATIVE CONTROL: a crocodile moved %.3f m and closed to %.2f m"
				% [out_croc["travelled"], out_croc["closest"]]
				+ " on the same %.1f m lane — the probe cannot see a predator move,"
				% AMBUSH_LANE_OUTSIDE + " so the ambusher's stillness measures nothing")
	if in_croc["closest"] > AMBUSH_STRUCK:
		_fail("the NEGATIVE CONTROL: a crocodile failed to reach a quarry walking"
				+ " %.1f m past it (closest %.2f m) — the probe cannot see a strike"
				% [AMBUSH_LANE_INSIDE, in_croc["closest"]])


func _walk_past(row: Dictionary, lane: float) -> Dictionary:
	"""
	Walk a quarry in a straight line past a predator sitting at the origin, and
	report how far the predator travelled and how close it ever got.

	The predator starts facing +Z, which is across the quarry's +X path: it has a
	quarter turn to make before it can strike, exactly as a real one would from
	whatever heading `_choose_new_direction` left it on.

	@param row: the SPECIES row to simulate
	@param lane: the quarry's lateral offset in metres
	@return { travelled: float, closest: float }
	"""
	var pos := Vector3.ZERO
	var yaw := 0.0
	var detect: float = float(row["detection_radius"])
	var chase: float = float(row["chase_speed"])
	var turn: float = float(row["turn_smoothness"])
	# The fastest this row can ever wander: the top of the sin cycle, before the
	# per-instance roll. The probe holds one idle heading rather than drifting, so
	# the drift it reports is a floor on the real one — see the docstring.
	var idle: float = float(row["move_speed"])
	var closest := INF
	var steps := int(2.0 * AMBUSH_WALK_HALF / (_walk_speed * AMBUSH_PROBE_DT))
	for step in range(steps):
		var quarry := Vector3(-AMBUSH_WALK_HALF + _walk_speed * float(step) * AMBUSH_PROBE_DT,
				0.0, lane)
		var distance := pos.distance_to(quarry)
		closest = minf(closest, distance)
		var speed := idle
		if distance <= detect:
			speed = chase
			var to_quarry := quarry - pos
			to_quarry.y = 0.0
			if to_quarry.length() > 0.1:
				yaw = lerp_angle(yaw, atan2(to_quarry.x, to_quarry.z),
						AMBUSH_PROBE_DT * turn)
		pos += Vector3(sin(yaw), 0.0, cos(yaw)) * speed * AMBUSH_PROBE_DT
	return { "travelled": pos.length(), "closest": closest }


func _model_top(scene_path: String) -> float:
	"""
	How tall the `Model` subtree of a predator scene stands, in model-local
	metres, measured off the real mesh AABBs.

	Instantiated but never added to the tree, so no _ready() runs and no physics
	body is registered — the same detached-instance trick prop_selfcheck.gd uses,
	and the reason this costs a few milliseconds rather than a frame.
	"""
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return -1.0
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return -1.0
	var instance: Node = packed.instantiate()
	var model: Node = instance.get_node_or_null("Model")
	var top := -1.0
	if model != null:
		top = _aabb_top(model, Transform3D.IDENTITY)
	instance.free()
	return top


func _aabb_top(node: Node, xform: Transform3D) -> float:
	"""The highest point of every VisualInstance3D under `node`, in `xform`'s frame."""
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	var top := -1.0
	if node is VisualInstance3D:
		var box: AABB = here * (node as VisualInstance3D).get_aabb()
		top = box.position.y + box.size.y
	for child in node.get_children():
		top = maxf(top, _aabb_top(child, here))
	return top


# ============================================================================
# CHECK 7 — a committed charge can be SIDESTEPPED, and a tracking one cannot
# ============================================================================

## Where the quarry starts, straight in front of the charger. Inside the bear's
## 14 m detection, so it is locked on from the first step and the charge is
## already committed when the dodge happens.
const CHARGE_PROBE_START: float = 12.0

## The distances at which the quarry starts its sidestep. The lock refreshes
## every `charge_commit` metres of TRAVEL, so a single trigger distance would
## measure one arbitrary phase of that cycle — five of them, averaged, measure
## the behaviour instead. All are inside the commitment and outside contact.
const CHARGE_DODGE_AT: Array[float] = [3.0, 4.0, 5.0, 6.0, 7.0]

const CHARGE_PROBE_DT: float = 1.0 / 60.0
const CHARGE_PROBE_SECONDS: float = 6.0

## The verdict, and both halves are deliberately loose — a guard against the
## commitment being GONE, not a pin on today's tuning. A committed charge must
## miss a WALKING sidestep by several times the bear's own 0.43 m width; the same
## bear with the commitment switched off must stay inside a metre of the quarry,
## which on a 0.43 m animal beside a player is on top of them. Today's numbers are
## 3.02 m against 0.78 m — a four-fold difference, which is the statement, not the
## two absolute figures.
const CHARGE_DODGE_MIN: float = 1.5
const CHARGE_TRACK_MAX: float = 1.0


func _check_charge_dodge(croc_ai: GDScript) -> void:
	"""
	MEASURE the dodge. Do not assert it.

	"High momentum" is the easiest thing in this epic to write in a way that reads
	correctly and does nothing. A charge that re-aims every frame is an ordinary
	chase with a heavy comment; a commitment shorter than a sidestep is invisible;
	a commitment that never expires is a bear running off the edge of the world.
	None of the three is an error anywhere — you get a predator that feels like
	all the others, which is the one outcome this bead exists to prevent.

	So this simulates the dodge and reports the miss. A quarry stands directly in
	the bear's path at 12 m, lets it commit, and at `CHARGE_DODGE_AT` metres steps
	sideways at WALK_SPEED — a walk, not a run, because the point of the behaviour
	is that footwork beats a predator you cannot outrun. Each step runs the
	SHIPPED steering (`charge_steer_point`, the same static function the arm
	calls) and the shipped two lines of movement.

	THE NEGATIVE CONTROL IS THE SAME BEAR WITH THE COMMITMENT SWITCHED OFF —
	identical row, identical turn_smoothness, aiming at the quarry's live position
	every frame. It must still catch the sidestep. That is what separates "the
	charge commits" from "the bear turns slowly": if the momentum ever quietly
	migrated out of `charge_steer_point` and into `turn_smoothness`, the control
	would start missing too and this check says so.

	WHAT THE MODEL LEAVES OUT, honestly: obstacle feelers, gravity, the bite's own
	lunge and the per-instance speed roll. The first two perturb the path without
	touching where the lock points; the roll is bounded by the lattice at one end
	and by ±20% at the other, and a slower bear misses by MORE.
	"""
	var names: Array[String] = _species_with("charge")
	if names.is_empty():
		_fail("no SPECIES row has behavior 'charge' — the committed charge this"
				+ " check measures is not reachable from any species")
		Sentinel.done("charge_dodge")
		return
	for charge_species: String in names:
		_probe_charge(croc_ai, charge_species)
	Sentinel.done("charge_dodge")


func _probe_charge(croc_ai: GDScript, charge_species: String) -> void:
	"""
	Run the whole dodge measurement against ONE charging species.

	@param croc_ai: the AI script, for its static charge_steer_point
	@param charge_species: the SPECIES key to probe

	Split out of _check_charge_dodge — which holds the argument for all of this —
	so every charger is measured rather than the first one found.
	"""
	var row: Dictionary = _species_table[charge_species]
	if not row.has("charge_commit"):
		_fail("SPECIES['%s'] has behavior 'charge' but no 'charge_commit' —" % charge_species
				+ " _behave_charge reads it every frame it chases")
		return
	var commit: float = float(row["charge_commit"])
	if commit <= 0.0:
		_fail("SPECIES['%s'].charge_commit is %.2f — a charge that re-aims every"
				% [charge_species, commit] + " frame is an ordinary chase")
		return

	var committed := 0.0
	var tracking := 0.0
	for dodge_at: float in CHARGE_DODGE_AT:
		committed += _charge_miss(croc_ai, row, dodge_at, true)
		tracking += _charge_miss(croc_ai, row, dodge_at, false)
	committed /= float(CHARGE_DODGE_AT.size())
	tracking /= float(CHARGE_DODGE_AT.size())

	print("charge dodge: a %.1f m/s sidestep at %s m beats a committed %s by"
			% [_walk_speed, str(CHARGE_DODGE_AT), charge_species]
			+ " %.2f m on average (same bear, commitment off: %.2f m)"
			% [committed, tracking])

	if committed < CHARGE_DODGE_MIN:
		_fail("a walking sidestep only beats a committed charge by %.2f m" % committed
				+ " (want >= %.2f m) — the commitment is gone and the bear is"
				% CHARGE_DODGE_MIN + " just another chaser")
	if tracking > CHARGE_TRACK_MAX:
		_fail("the NEGATIVE CONTROL missed by %.2f m with the commitment SWITCHED"
				% tracking + " OFF — the %.2f m measured with it on is coming from"
				% committed + " turn_smoothness, not from charge_steer_point")


func _charge_miss(croc_ai: GDScript, row: Dictionary, dodge_at: float,
		committed: bool) -> float:
	"""
	Run one charge against one sidestep and report the closest the bear ever got.

	@param croc_ai: the AI script, for its static charge_steer_point
	@param row: the SPECIES row to simulate
	@param dodge_at: how close the bear is when the quarry starts moving
	@param committed: true to run the shipped steering, false for the control
	@return closest approach in metres

	THE RUN ENDS WHEN THE CHARGE IS SPENT — the first frame after the dodge began
	on which the bear stops closing — and that window is the measurement, not a
	convenience. Left running, every probe converges to zero and says nothing:
	the quarry walks a straight line forever at 5 m/s and the bear does 6, so it
	re-acquires from behind and eventually arrives no matter what happened at the
	dodge. That is CORRECT (walking is caught, running escapes, and a dodge buys
	the separation you then run with) and it is a different measurement from this
	one, which asks only whether the sidestep beat the charge that was in flight.
	The control does not trip the rule at all — a tracking bear never stops
	closing — so it runs the full budget and reports the contact it makes.
	"""
	var quarry := Vector3(0.0, 0.0, CHARGE_PROBE_START)
	var pos := Vector3.ZERO
	var yaw := 0.0                      # already facing the quarry, along +Z
	var chase: float = float(row["chase_speed"])
	var turn: float = float(row["turn_smoothness"])
	var commit: float = float(row["charge_commit"])
	var lock := {}
	var dodging := false
	var closest := INF
	var previous := INF
	var steps := int(CHARGE_PROBE_SECONDS / CHARGE_PROBE_DT)
	for _step in range(steps):
		var distance := pos.distance_to(quarry)
		if dodging and distance > previous + EPSILON:
			break                       # the charge is spent — see the docstring
		previous = distance
		closest = minf(closest, distance)
		if distance <= dodge_at:
			dodging = true
		if dodging:
			# Straight across the bear's original line, at a WALK.
			quarry.x += _walk_speed * CHARGE_PROBE_DT
		var target := quarry
		if committed:
			target = CrocSteering.charge_steer_point(quarry, pos, lock, commit)
		var to_target := target - pos
		to_target.y = 0.0
		if to_target.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(to_target.x, to_target.z), CHARGE_PROBE_DT * turn)
		pos += Vector3(sin(yaw), 0.0, cos(yaw)) * chase * CHARGE_PROBE_DT
	return closest


# ============================================================================
# CHECK 8 — a burst predator cannot outrun a RUNNING player, and CAN catch a
#           walking one, measured over the WHOLE pounce/recovery cycle
# ============================================================================

## How long each straight-line race runs. Long enough for many complete cycles at
## either species' cadence (the cougar's is ~1.0 s at the clamp, the hound's
## ~0.61 s), because one cycle in isolation says nothing: the burst is supposed to
## take ground back, and the recovery is supposed to hand more of it over.
const BURST_RACE_SECONDS: float = 20.0
const BURST_RACE_DT: float = 1.0 / 60.0

## Where the quarry starts. Comfortably outside contact and inside every burst
## row's detection radius, so the predator is locked on for the whole race.
const BURST_RACE_GAP: float = 12.0

## THE VERDICT AGAINST A RUNNER, and it is deliberately loose. A running player
## must END the race further away than they started — the gap must GROW, not
## merely fail to reach zero — by at least this much. It is a guard against the
## recovery window being gone, not a pin on today's tuning: today's figures are
## +39.8 m (cougar) and +30.4 m (hound) at the worst speed the game can produce.
const BURST_RUNNER_GAIN_MIN: float = 5.0

## THE VERDICT AGAINST A WALKER, the other end of the same lattice and the end a
## burst is likelier to break. A recovery deep enough to drag the CYCLE AVERAGE
## under WALK_SPEED would not be a nerf, it would be a predator you stroll away
## from — so a nominal-speed animal must close the whole 12 m gap and make
## contact inside the race.
const BURST_WALKER_MUST_CATCH: bool = true

## THE CIRCLING PROBE. Radius of the tight circle the fourth race walks, in
## metres — deliberately SMALLER than either species' burst_distance (2.5 and
## 4.0), so a predator that measured its leg as DISPLACEMENT FROM WHERE THE LEG
## STARTED would never travel far enough from that point to finish a pounce and
## would burst forever. That is not a hypothetical: it is what this function did
## before review, and it is the one way a bounded burst silently becomes an
## unbounded one. Path length has no such hole, so the fraction of frames spent
## bursting on a circle must match the straight-line cycle.
const BURST_CIRCLE_RADIUS: float = 1.5

## Ceiling on the share of frames a circling predator may spend on the burst leg.
## The honest figure is the cycle's own duty ratio — (Db/Fb) / (Db/Fb + Dr/Fr) —
## which is 0.36 for the cougar and 0.36 for the hound; the displacement bug puts
## it at 1.00. 0.60 sits far from both, so this fails on the bug and not on a
## retune.
const BURST_CIRCLE_DUTY_MAX: float = 0.60


func _check_burst_escape(croc_ai: GDScript) -> void:
	"""
	MEASURE the escape. Do not assert it.

	THIS IS THE ONE CHECK IN THIS FILE GUARDING A DELIBERATE BREAK OF THE GAME'S
	TIGHTEST CONTRACT. Every other species is clamped to MAX_CHASE_SPEED and that
	is the end of it; the two `behavior: "burst"` rows multiply that clamped speed
	by `burst_factor` for the length of a pounce, so a cougar at the top of the
	distance gradient touches 11.05 m/s — above the ceiling AND above the slowest
	character's run. The bead authorised that (">8.5 m/s"); what it authorised it
	ON is that a running player still gets away across the FULL pounce-plus-
	recovery cycle. That is a claim about a gap over time, so it is simulated
	here rather than argued in a comment.

	Three races per species, all straight lines, all driving the SHIPPED
	`burst_cycle_factor` — the same static function the arm calls — so this
	measures the cycle that ships and not a restatement of it:

	  * A RUNNER at the slowest character's run, against the predator at the
	    WORST speed the game can produce (chase clamped to MAX_CHASE_SPEED by the
	    distance gradient). The gap must GROW.
	  * A WALKER at WALK_SPEED, against the predator at its nominal chase speed.
	    Contact must be made. Without this half, "the runner escapes" is also true
	    of a species whose recovery made it slower than walking, which is not a
	    predator.
	  * THE NEGATIVE CONTROL: the same predator at the same clamped speed with the
	    RECOVERY REMOVED (recover_factor pinned to the burst factor, i.e. a
	    sustained burst). It MUST catch the runner. That is what separates "the
	    recovery window is what saves the player" from "the numbers happened to
	    work out": if the burst ever quietly stopped being applied at all — a
	    typo'd key, a factor of 1.0, an arm that never fires — the control would
	    stop catching and this check says so.

	WHAT THE MODEL LEAVES OUT, honestly: turning, obstacle feelers, gravity, the
	bite's own lunge and the per-instance size roll. All of them are straight-line
	races down a corridor, which is both the simplest case and the WORST case for
	the player — every one of those effects slows the predator relative to a
	quarry running in a straight line, so a predator that cannot catch a runner
	here cannot catch one anywhere.
	"""
	if _slowest_run_speed <= 0.0:
		_fail("could not derive the slowest character's run from player_controller.gd"
				+ " (RUN_SPEED x the smallest CHARACTER_SPEED) — check 8 would have"
				+ " raced the burst against a ceiling of zero and passed vacuously")
		Sentinel.done("burst_escape")
		return

	var burst_species: Array[String] = []
	for name_v: Variant in _species_table:
		if String(_species_table[name_v].get("behavior", "")) == "burst":
			burst_species.append(String(name_v))
	if burst_species.is_empty():
		_fail("no SPECIES row has behavior 'burst' — the bounded burst this check"
				+ " measures is not reachable from any species")
		Sentinel.done("burst_escape")
		return

	for species_name: String in burst_species:
		var row: Dictionary = _species_table[species_name]
		var missing: Array[String] = []
		for key: String in ["burst_distance", "recover_distance", "burst_factor",
				"recover_factor"]:
			if not row.has(key):
				missing.append(key)
		if not missing.is_empty():
			_fail("SPECIES['%s'] has behavior 'burst' but no %s —" % [species_name, missing]
					+ " burst_cycle_factor reads them every frame it chases, and"
					+ " answers 1.0 (an ordinary chase) when they are gone")
			continue

		var chase: float = float(row["chase_speed"])
		var burst_peak: float = _max_chase_speed * float(row["burst_factor"])

		# THE BURST MUST ACTUALLY BE A BURST. A `burst_factor` at or under 1.0 is
		# the silent failure this whole check exists for: everything below still
		# runs, the runner still escapes, and the species is a slow crocodile with
		# a long comment. The bead's own bar is the ceiling it is allowed to break.
		if burst_peak <= _max_chase_speed:
			_fail("SPECIES['%s'].burst_factor %.2f puts the peak at %.2f m/s, not"
					% [species_name, float(row["burst_factor"]), burst_peak]
					+ " above MAX_CHASE_SPEED (%.2f) — there is no burst" % _max_chase_speed)
		if float(row["recover_factor"]) >= 1.0:
			_fail("SPECIES['%s'].recover_factor %.2f is at or above 1.0 — the"
					% [species_name, float(row["recover_factor"])]
					+ " 'recovery' costs the animal nothing and the burst is a"
					+ " permanent speed-up over the whole cycle")

		# 1. The runner, against the fastest this species can ever be.
		var runner := _burst_race(croc_ai, row, _max_chase_speed, _slowest_run_speed, false)
		# 2. The walker, against the nominal animal.
		var walker := _burst_race(croc_ai, row, chase, _walk_speed, false)
		# 3. The control: same worst-case animal, recovery removed.
		var control := _burst_race(croc_ai, row, _max_chase_speed, _slowest_run_speed, true)
		# 4. The circling probe — see BURST_CIRCLE_RADIUS.
		var duty := _burst_circle_duty(croc_ai, row, _max_chase_speed)

		print("burst escape (%s): peak %.2f m/s vs the %.2f ceiling; a %.1f m/s run"
				% [species_name, burst_peak, _max_chase_speed, _slowest_run_speed]
				+ " opens the %.1f m gap to %.1f m over %.0f s, a %.1f m/s walk closes"
				% [BURST_RACE_GAP, runner, BURST_RACE_SECONDS, _walk_speed]
				+ " it to %.1f m (same animal, recovery OFF: %.1f m);"
				% [walker, control]
				+ " circling inside %.1f m it bursts %.0f%% of frames"
				% [BURST_CIRCLE_RADIUS, duty * 100.0])

		if runner - BURST_RACE_GAP < BURST_RUNNER_GAIN_MIN:
			_fail("a running player only gained %.2f m on a %s over %.0f s"
					% [runner - BURST_RACE_GAP, species_name, BURST_RACE_SECONDS]
					+ " (want >= %.2f m) — the pounce is above MAX_CHASE_SPEED and"
					% BURST_RUNNER_GAIN_MIN
					+ " the recovery is no longer paying for it, so running has"
					+ " stopped escaping and that is the promise the game is"
					+ " balanced on")
		if BURST_WALKER_MUST_CATCH and walker > 0.0:
			_fail("a %s never caught a WALKING player — it stayed %.2f m short over"
					% [species_name, walker] + " %.0f s. The cycle average has"
					% BURST_RACE_SECONDS + " fallen under WALK_SPEED (%.2f), which"
					% _walk_speed + " is not a difficulty knob but a broken predator")
		if control > 0.0:
			_fail("the NEGATIVE CONTROL for %s did NOT catch the runner with the"
					% species_name + " RECOVERY SWITCHED OFF — it stayed %.2f m"
					% control + " short. The escape measured with it on is therefore"
					+ " not coming from the recovery window, so this check is not"
					+ " measuring the burst at all")
		if duty > BURST_CIRCLE_DUTY_MAX:
			_fail("a %s circling inside %.1f m spent %.0f%% of its frames on the"
					% [species_name, BURST_CIRCLE_RADIUS, duty * 100.0]
					+ " BURST leg (want <= %.0f%%) — the leg is being measured as"
					% (BURST_CIRCLE_DUTY_MAX * 100.0)
					+ " displacement from where it started rather than as path"
					+ " length, so a predator that never gets far from one spot"
					+ " never finishes a pounce and holds a speed above"
					+ " MAX_CHASE_SPEED indefinitely")
	Sentinel.done("burst_escape")


func _burst_circle_duty(croc_ai: GDScript, row: Dictionary, chase: float) -> float:
	"""
	Walk a burst predator round a tight circle and report how much it spends bursting.

	@param croc_ai: the AI script, for its static burst_cycle_factor
	@param row: the SPECIES row to simulate
	@param chase: the predator's clamped chase speed
	@return the fraction of frames the cycle spent on the burst leg

	The path is a circle of BURST_CIRCLE_RADIUS — smaller than the burst leg, so
	the body never gets `burst_distance` away from any point on it while covering
	unlimited GROUND. That is the real chase geometry this models: a player who
	circles, or a predator steered round a massif by the obstacle feelers. Arc
	length per frame is `chase * factor * dt`, so a bursting animal walks the
	circle faster, exactly as it would in the world.
	"""
	var lock := {}
	var angle := 0.0
	var bursts := 0
	var steps := int(BURST_RACE_SECONDS / BURST_RACE_DT)
	var burst_factor: float = float(row["burst_factor"])
	for _step in range(steps):
		var pos := Vector3(cos(angle), 0.0, sin(angle)) * BURST_CIRCLE_RADIUS
		var factor: float = CrocSteering.burst_cycle_factor(pos, lock, row)
		if is_equal_approx(factor, burst_factor):
			bursts += 1
		angle += (chase * factor * BURST_RACE_DT) / BURST_CIRCLE_RADIUS
	return float(bursts) / float(steps)


func _burst_race(croc_ai: GDScript, row: Dictionary, chase: float, quarry_speed: float,
		no_recovery: bool) -> float:
	"""
	Race one burst predator against one quarry down a straight line.

	@param croc_ai: the AI script, for its static burst_cycle_factor
	@param row: the SPECIES row to simulate
	@param chase: the predator's clamped chase speed (what _ready() resolved)
	@param quarry_speed: the quarry's constant speed
	@param no_recovery: the negative control — pin the recovery leg to the burst
	                    factor, so the animal never pays for a pounce
	@return the gap in metres at the end, or 0.0 if contact was made

	The predator drives the SHIPPED `burst_cycle_factor` with the SHIPPED row, so
	the leg lengths, the flip rule and both factors are the ones that ship. Only
	the control mutates anything, and it mutates a COPY.
	"""
	var probe_row: Dictionary = row
	if no_recovery:
		probe_row = row.duplicate()
		probe_row["recover_factor"] = row["burst_factor"]

	var pos := Vector3.ZERO
	var quarry := Vector3(0.0, 0.0, BURST_RACE_GAP)
	var lock := {}
	var steps := int(BURST_RACE_SECONDS / BURST_RACE_DT)
	for _step in range(steps):
		var factor: float = CrocSteering.burst_cycle_factor(pos, lock, probe_row)
		pos.z += chase * factor * BURST_RACE_DT
		quarry.z += quarry_speed * BURST_RACE_DT
		if quarry.z - pos.z <= 0.0:
			return 0.0
	return quarry.z - pos.z


# ============================================================================
# CHECK 8b — a RANGED predator is an archer: sub-walk speed, a firing BAND with
#            a floor as well as a ceiling, and a cadence it cannot cheat
# ============================================================================

## How long each cadence race runs, and at what tick. 30 s is ten of the titan's
## 3 s cooldowns, so an off-by-one at either end of the window moves the expected
## count by 10% and not by 100% — the count means the cadence, not the boundary.
const RANGED_PROBE_SECONDS: float = 30.0
const RANGED_PROBE_DT: float = 1.0 / 60.0

## How far outside the firing band the two refusal races stand, in metres. Half a
## metre: the check is that the band has EDGES, so it is measured just past them
## rather than at some comfortable distance a broken gate would also refuse.
const RANGED_BAND_MARGIN: float = 0.5


func _check_ranged_cadence(croc_ai: GDScript) -> void:
	"""
	THE FIFTH ARM'S PROBE. Drive the shipped firing rule and count the shots.

	`ranged_shot_due()` is static and pure for exactly this reason (the shape
	`burst_cycle_factor` and `pack_steer_point` established): what is measured
	here is the function `_behave_ranged` calls, not a restatement of it that can
	drift. What this file CANNOT reach — that the arm actually calls
	BossProjectile.fire(), that it refuses outside the boss territory, and that a
	titan resolves the slow boss speed its row asks for — is measured live in
	boss_selfcheck.gd, which has a physics world and a real boss in it.

	Three things are asserted, and the first is the one that makes the species
	legible at all:

	  1. THE ARCHER CONTRACT. Every speed a "ranged" row can resolve to — its
	     wander, its chase, and the boss speed it opts into — is BELOW WALK_SPEED.
	     This is the assertion that PAYS FOR the lattice exemption a boss-only row
	     gets in check 4: the titan is allowed under the walk line because being
	     under it is the design, so a retune back over it must fail here rather
	     than pass quietly as an ordinary predator would.
	  2. THE BAND HAS A FLOOR. Out-of-band races at both edges must fire NOTHING.
	     The ceiling is the ordinary "don't shoot what you can't see"; the FLOOR
	     is the counterplay — walk INTO a titan and it cannot shoot you, because
	     inside `min_fire_range` the bolt arrives faster than a walking player can
	     clear its hit radius (the contract projectile_selfcheck measures).
	  3. THE CADENCE IS THE ROW'S. In-band, the shot count over a long window
	     matches `fire_cooldown` to the frame. A cooldown that is not re-armed
	     fires every tick — 1800 shots instead of 11 — which in play reads as a
	     wall of lightning nobody could dodge and, in a check that only asserted
	     "it fires", as a pass.
	"""
	var shooters: Array[String] = _species_with("ranged")
	if shooters.is_empty():
		# The negative control for this whole check: with no ranged row, every
		# loop below iterates zero times and the file would report OK having
		# measured nothing. The arm exists in the AI, so a table with no row
		# carrying it is a half-landed bead.
		_fail("no SPECIES row has behavior 'ranged' — the firing rule this check"
				+ " drives is in the AI (_behave_ranged / ranged_shot_due) with"
				+ " nothing dispatching to it")
		Sentinel.done("ranged_cadence")
		return
	for species_name: String in shooters:
		_probe_ranged(croc_ai, species_name)
	Sentinel.done("ranged_cadence")


func _probe_ranged(croc_ai: GDScript, species_name: String) -> void:
	"""
	One ranged species: its speeds, its band, and its cadence.

	@param croc_ai: piglet_crocodile_ai.gd, for the shipped ranged_shot_due()
	@param species_name: the SPECIES key to probe
	"""
	var row: Dictionary = _species_table[species_name]
	if not row.has("ranged"):
		_fail("SPECIES['%s'] has behavior 'ranged' but no 'ranged' dict —"
				% species_name + " _behave_ranged reads spec[\"ranged\"] on the"
				+ " frame it first smells a player and would crash there")
		return
	var ranged: Dictionary = row["ranged"]
	for key: String in ["min_fire_range", "max_fire_range", "fire_cooldown", "muzzle_height"]:
		if not ranged.has(key):
			_fail("SPECIES['%s'].ranged has no '%s' — the arm reads it every"
					% [species_name, key] + " frame it is engaged")
			return

	# ---- 1. THE ARCHER CONTRACT --------------------------------------------
	# EVERY speed slot the row fills, because a boss and a plain predator read
	# different ones and a retune of either alone is exactly how "slow archer"
	# becomes a melee giant. `boss_chase_speed` is checked only when the row
	# declares it: a ranged row that does not is not a boss-only row, so what it
	# would resolve to is the ordinary chase speed one line up.
	var speed_slots: Array = [
		["move_speed", float(row["move_speed"])],
		["chase_speed", float(row["chase_speed"])],
	]
	if row.has("boss_chase_speed"):
		speed_slots.append(["boss_chase_speed", float(row["boss_chase_speed"])])
	for pair: Array in speed_slots:
		if float(pair[1]) >= _walk_speed:
			_fail("SPECIES['%s'].%s is %.2f, at or above WALK_SPEED %.2f — a"
					% [species_name, pair[0], float(pair[1]), _walk_speed]
					+ " ranged predator's threat is its shot, and one that can run"
					+ " a walking player down is a melee predator holding a bow."
					+ " (A boss-only row is exempt from the lattice's lower bound"
					+ " precisely because THIS is asserted instead.)")

	var min_range: float = float(ranged["min_fire_range"])
	var max_range: float = float(ranged["max_fire_range"])
	var cooldown: float = float(ranged["fire_cooldown"])
	if min_range <= 0.0 or max_range <= min_range:
		_fail("SPECIES['%s'].ranged band is [%.1f, %.1f] — the ceiling must be"
				% [species_name, min_range, max_range] + " above a positive floor"
				+ " or the arm can never fire")
		return
	if cooldown <= 0.0:
		_fail("SPECIES['%s'].ranged fire_cooldown is %.2f — a cooldown at or"
				% [species_name, cooldown] + " below zero is a shot every physics"
				+ " frame")
		return
	# The band must fit inside what this predator can SMELL, because the arm only
	# runs while chasing: a ceiling outside detection is a number that can never
	# be reached, which reads as a longer reach than the boss actually has.
	var smell: float = float(row["detection_radius"])
	if _boss_only.has(species_name):
		# A boss overrides its row's detection radius with the game-wide one, so
		# for a BOSS-ONLY archer that is the number the band has to fit inside —
		# and only for one: an ordinary ranged predator would never resolve it.
		smell = maxf(smell, _boss_detection_radius)
	if max_range > smell:
		_fail("SPECIES['%s'].ranged max_fire_range %.1f exceeds the %.1f m it can"
				% [species_name, max_range, smell] + " smell — the arm only runs"
				+ " while chasing, so those metres of reach do not exist")

	# ---- 2. THE BAND HAS EDGES ---------------------------------------------
	var too_close: Array[int] = _ranged_shots(croc_ai, ranged, min_range - RANGED_BAND_MARGIN)
	if not too_close.is_empty():
		_fail("SPECIES['%s']: %d shot(s) fired from %.2f m, inside its own %.1f m"
				% [species_name, too_close.size(), min_range - RANGED_BAND_MARGIN, min_range]
				+ " minimum — a bolt from there arrives before a walking player"
				+ " can clear its hit radius, which is the one thing the fairness"
				+ " contract cannot fix from inside the projectile")
	var too_far: Array[int] = _ranged_shots(croc_ai, ranged, max_range + RANGED_BAND_MARGIN)
	if not too_far.is_empty():
		_fail("SPECIES['%s']: %d shot(s) fired from %.2f m, past its own %.1f m"
				% [species_name, too_far.size(), max_range + RANGED_BAND_MARGIN, max_range]
				+ " ceiling")

	# ---- 3. THE CADENCE IS THE ROW'S ---------------------------------------
	# Mid-band, so neither edge is in play, and measured as the GAPS BETWEEN
	# SHOTS rather than as a count against a formula: a count has to reason about
	# whether the last shot fell inside the window, which is an off-by-one waiting
	# to be "fixed" by loosening the assertion. Gaps have no such edge, and they
	# are the thing the cooldown actually is.
	var mid: float = (min_range + max_range) * 0.5
	var fired: Array[int] = _ranged_shots(croc_ai, ranged, mid)
	var gap_frames: int = int(round(cooldown / RANGED_PROBE_DT))
	var expected_shots: int = int(RANGED_PROBE_SECONDS / cooldown)
	if fired.size() < expected_shots - 1 or fired.size() > expected_shots + 1:
		_fail("SPECIES['%s']: %d shot(s) in %.0f s at %.1f m, expected about %d at"
				% [species_name, fired.size(), RANGED_PROBE_SECONDS, mid, expected_shots]
				+ " a %.2f s cooldown — a cooldown that is never re-armed fires"
				% cooldown + " every physics frame, which no player can dodge")
		return
	if fired.is_empty() or fired[0] != 0:
		_fail("SPECIES['%s']: the first shot came on frame %s, not the first —"
				% [species_name, "never" if fired.is_empty() else str(fired[0])]
				+ " an empty lock means READY, so an archer that has just acquired"
				+ " a quarry shoots rather than standing through a silent cooldown")
		return
	for i in range(1, fired.size()):
		var gap: int = fired[i] - fired[i - 1]
		# One frame of slack, and one only: the countdown is float and the tick is
		# 1/60, so a boundary can land either side of a frame. Two frames of slack
		# would start hiding a cooldown that is a tick short of the row's.
		if absi(gap - gap_frames) > 1:
			_fail("SPECIES['%s']: shots %d and %d are %d frames apart, expected %d"
					% [species_name, i - 1, i, gap, gap_frames] + " (%.2f s at"
					% cooldown + " %.4f s/frame) — the cadence is not the row's"
					% RANGED_PROBE_DT)
			return


func _ranged_shots(croc_ai: GDScript, ranged: Dictionary, distance: float) -> Array[int]:
	"""
	Every frame on which the SHIPPED firing rule releases a shot, at a fixed range.

	@param croc_ai: piglet_crocodile_ai.gd
	@param ranged: the row's "ranged" dict, passed through untouched
	@param distance: the quarry's flat distance, held constant for the window
	@return the frame indices where ranged_shot_due() answered true

	Nothing is mutated and nothing is restated: the lock is the same plain
	Dictionary the arm hands it, so the cooldown bookkeeping under test is the
	shipped one.
	"""
	var lock: Dictionary = {}
	var shots: Array[int] = []
	var steps: int = int(RANGED_PROBE_SECONDS / RANGED_PROBE_DT)
	for step in range(steps):
		if CrocSteering.ranged_shot_due(distance, RANGED_PROBE_DT, lock, ranged):
			shots.append(step)
	return shots


# ============================================================================
# CHECK 8c — a HUNTER holds its ring before it commits, and after a grab it
#            BACKS OFF instead of re-chomping
# ============================================================================

## The walk resolution and budget for the three geometry probes. 12 s is several
## times what a 6.5 m/s unit needs to cross the 20 m today's hunter starts at, so
## a probe that fails to settle fails on the steering rather than on a short
## budget.
const HUNT_PROBE_DT: float = 1.0 / 60.0
const HUNT_PROBE_SECONDS: float = 12.0

## Where the shadow and close walks start, as a MULTIPLE of the row's own ring,
## clamped to its own detection radius. Derived rather than written down as the
## 20 m it works out to for today's hunter, because both ends have to hold for
## every future row: outside the ring (or the "shadow" walk would be measuring a
## withdrawal) and inside detection (or the walk begins from a place the unit
## could not have acquired you from). Doubling the ring satisfies the first with
## room, and the clamp satisfies the second by construction.
const HUNT_PROBE_START_FACTOR: float = 2.0

## Where the WITHDRAW walk starts: on top of the quarry, which is exactly where a
## grab leaves the unit standing. Not zero — a hunter sitting on the quarry's
## origin has no bearing to hold a ring on and the geometry says so (it answers
## the quarry) — so this is contact distance, the state the collision path is
## actually entered from.
const HUNT_WITHDRAW_START: float = 0.5

## How close to its declared ring a settled shadow must sit, in metres. This is a
## SETTLING tolerance, not a slop allowance: the walk runs the same yaw-lerp
## movement model the charge probe does, so a unit converging on the ring
## overshoots by a fraction of one 6.5 m/s frame. A tenth of a metre would fail on
## the integrator; a metre would pass a hunter whose ring had quietly halved.
const HUNT_RING_TOLERANCE: float = 0.35

## Where a grab counts as reachable, in metres between origins. The same idea as
## AMBUSH_STRUCK and the same number: the bodies are not points, so a metre
## between origins is contact with room to spare. A SHADOWING hunter must never
## get this close — that is this check's negative control.
const HUNT_CONTACT: float = 1.0


func _check_hunt_pacing(croc_ai: GDScript) -> void:
	"""
	MEASURE the pacing. Do not assert it.

	A hunter that chases like a crocodile is a reskinned crocodile, and every way
	of ending up with one is silent. Drop the telegraph and the unit walks
	straight in with a warning nobody got; let the ring collapse and "shadowing"
	is an ordinary chase with a comment on it; forget the disengage and the
	machine stands on the respawn point billing coins every 0.3 s. None of the
	three errors anywhere — you get a fast crocodile in a hazard livery, which is
	the one outcome this bead exists to prevent.

	So this measures the shipped behaviour at BOTH levels, and it needs both:

	  * THE GEOMETRY, through `hunt_steer_point` — the same static function the
	    arm calls, for the same reason `pack_steer_point` and `charge_steer_point`
	    are static. Three walks: one shadowing (must settle ON the ring and never
	    reach contact), one closing (must close monotonically and make contact),
	    one withdrawing from contact (must back OUT to the ring). The shadow walk
	    is the negative control for the closing one — identical row, identical
	    movement model, one boolean apart — so "it closed" cannot be satisfied by
	    a probe that simply walks everything into the quarry.
	  * THE DISPATCH AND THE CLOCK, through a LIVE body running the shipped
	    `_update_chase_state`. The geometry probes cannot see whether the `match`
	    ever reaches `_behave_hunt`, whether the telegraph window is honoured, or
	    whether a landed grab starts a disengage — delete the arm from the dispatch
	    and all three static walks still pass. This half drives the real function
	    on a real node and reads `chase_target` back, which is the only thing the
	    arm is allowed to bend.

	WHAT THE MODEL LEAVES OUT, honestly: obstacle feelers, gravity, the bite lunge
	and the per-instance speed roll. The first two perturb the path without
	touching where the geometry points; the roll is bounded by the lattice at one
	end and by the row's own spread at the other, and neither end can turn a ring
	into a chase.
	"""
	var names: Array[String] = _species_with("hunt")
	if names.is_empty():
		_fail("no SPECIES row has behavior 'hunt' — the telegraph, ring and"
				+ " disengage this check measures are not reachable from any species")
		Sentinel.done("hunt_pacing")
		return
	for hunt_species: String in names:
		_probe_hunt_geometry(croc_ai, hunt_species)
		_probe_hunt_dispatch(hunt_species)
	Sentinel.done("hunt_pacing")


func _probe_hunt_geometry(croc_ai: GDScript, hunt_species: String) -> void:
	"""
	Walk one hunt species in, out and around its ring, through the SHIPPED steering.

	@param croc_ai: the AI script, for its static hunt_steer_point
	@param hunt_species: the SPECIES key to probe

	Split out of _check_hunt_pacing — which holds the argument for all of this —
	so every retrieval unit is measured rather than the first one found.
	"""
	var row: Dictionary = _species_table[hunt_species]
	for key: String in ["hunt_telegraph_time", "hunt_standoff", "hunt_disengage_time"]:
		if not row.has(key):
			_fail("SPECIES['%s'] has behavior 'hunt' but no '%s' —" % [hunt_species, key]
					+ " _behave_hunt reads it every frame it chases")
			return
	var standoff: float = float(row["hunt_standoff"])
	var telegraph: float = float(row["hunt_telegraph_time"])
	var disengage: float = float(row["hunt_disengage_time"])
	if telegraph <= 0.0:
		_fail("SPECIES['%s'].hunt_telegraph_time is %.2f s — a hunter that may"
				% [hunt_species, telegraph] + " close on the acquisition frame gave"
				+ " the player no warning at all, which is the one thing the"
				+ " telegraph exists to be")
		return
	if standoff <= HUNT_CONTACT:
		_fail("SPECIES['%s'].hunt_standoff is %.2f m — a ring inside contact"
				% [hunt_species, standoff] + " range (%.2f m) is not a standoff,"
				% HUNT_CONTACT + " it is a chase")
		return
	if disengage <= 0.0:
		_fail("SPECIES['%s'].hunt_disengage_time is %.2f s — a hunter that"
				% [hunt_species, disengage] + " re-commits on the frame after a grab"
				+ " stands on the respawn point billing coins every second")
		return
	# The ring has to fit INSIDE what the unit can smell, with room. A hunter
	# shadowing at or past its own detection radius drops the chase the moment it
	# arrives, clears the lock, re-acquires and starts the telegraph over — the
	# same boundary flicker DETECTION_SIM_MARGIN prevents one level up, and it
	# would read in play as a machine that cannot make up its mind.
	var detection: float = float(row["detection_radius"])
	if standoff >= detection:
		_fail("SPECIES['%s'] shadows at %.1f m but only smells %.1f m —"
				% [hunt_species, standoff, detection] + " a unit that loses the chase"
				+ " the moment it reaches its own ring re-telegraphs forever")
		return

	var start: float = minf(standoff * HUNT_PROBE_START_FACTOR, detection)
	var shadow: Dictionary = _hunt_walk(croc_ai, row, start, false)
	var close: Dictionary = _hunt_walk(croc_ai, row, start, true)
	var withdraw: Dictionary = _hunt_walk(croc_ai, row, HUNT_WITHDRAW_START, false)

	print("hunt pacing: %s shadows from %.0f m to %.2f m (closest %.2f m, ring"
			% [hunt_species, start, float(shadow["final"]),
			float(shadow["closest"])]
			+ " %.1f m), closes to %.2f m, withdraws from %.1f m back out to %.2f m"
			% [standoff, float(close["final"]), HUNT_WITHDRAW_START,
			float(withdraw["final"])])

	if absf(float(shadow["final"]) - standoff) > HUNT_RING_TOLERANCE:
		_fail("a shadowing %s settled %.2f m from its quarry, not on its %.1f m"
				% [hunt_species, float(shadow["final"]), standoff] + " ring — it is"
				+ " not holding a standoff, it is doing something else")
	if float(shadow["closest"]) <= HUNT_CONTACT:
		_fail("a SHADOWING %s got within %.2f m of the quarry (contact is %.2f m)"
				% [hunt_species, float(shadow["closest"]), HUNT_CONTACT] + " — the"
				+ " pre-commit half of the behaviour reaches the player anyway, so"
				+ " the telegraph buys nothing")
	if float(close["final"]) > HUNT_CONTACT:
		_fail("a CLOSING %s never got closer than %.2f m (contact is %.2f m) —"
				% [hunt_species, float(close["final"]), HUNT_CONTACT] + " the"
				+ " commitment does not commit, and the shadow walk beside it is"
				+ " therefore measuring nothing")
	if not bool(close["monotone"]):
		_fail("a CLOSING %s stopped closing mid-walk — hunt_steer_point is bending"
				% hunt_species + " the aim point while it commits, which is the"
				+ " shadow's job and not the close's")
	if float(withdraw["final"]) <= HUNT_WITHDRAW_START:
		_fail("a %s standing %.2f m from its quarry after a grab ended the walk at"
				% [hunt_species, HUNT_WITHDRAW_START] + " %.2f m — it never backed"
				% float(withdraw["final"]) + " off, so the disengage has no geometry")
	if absf(float(withdraw["final"]) - standoff) > HUNT_RING_TOLERANCE:
		_fail("a withdrawing %s settled %.2f m out, not on its %.1f m ring —"
				% [hunt_species, float(withdraw["final"]), standoff] + " the same"
				+ " expression serves both halves of shadowing, so one of them is"
				+ " no longer running it")


func _hunt_walk(croc_ai: GDScript, row: Dictionary, start: float,
		closing: bool) -> Dictionary:
	"""
	Walk one hunter at a stationary quarry and report where it ended up.

	@param croc_ai: the AI script, for its static hunt_steer_point
	@param row: the SPECIES row to simulate
	@param start: the unit's opening distance from the quarry, metres
	@param closing: the one boolean the geometry takes — false shadows, true commits
	@return { "final", "closest", "monotone" }

	The movement model is the charge probe's, line for line: aim through the
	SHIPPED steering, lerp the yaw toward it at the row's own turn_smoothness,
	then travel along the FACING at the row's own chase speed. The quarry stands
	still, because what is under test is the ring the unit holds around it and not
	its ability to follow one — a moving quarry would let a shadow that simply
	trails behind pass the settling test.

	"monotone" is the closing walk's verdict and is measured on every walk because
	it costs a comparison: true when the distance never grew by more than EPSILON
	between consecutive frames. A shadowing unit is EXPECTED to break it (it stops
	on the ring, and a withdrawing one runs backwards), which is why only the
	closing walk asserts it.
	"""
	var quarry := Vector3.ZERO
	var pos := Vector3(0.0, 0.0, start)
	var yaw := PI                       # facing the quarry, the state a chase starts in
	var chase: float = float(row["chase_speed"])
	var turn: float = float(row["turn_smoothness"])
	var standoff: float = float(row["hunt_standoff"])
	var closest := INF
	var previous := start
	var monotone := true
	var steps: int = int(HUNT_PROBE_SECONDS / HUNT_PROBE_DT)
	for _step in range(steps):
		var distance := pos.distance_to(quarry)
		closest = minf(closest, distance)
		if distance > previous + EPSILON:
			monotone = false
		previous = distance
		var target: Vector3 = CrocSteering.hunt_steer_point(quarry, pos, closing, standoff)
		var to_target := target - pos
		to_target.y = 0.0
		if to_target.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(to_target.x, to_target.z), HUNT_PROBE_DT * turn)
			pos += Vector3(sin(yaw), 0.0, cos(yaw)) * chase * HUNT_PROBE_DT
	return {
		"final": pos.distance_to(quarry),
		"closest": closest,
		"monotone": monotone,
	}


## The stub the dispatch probe hands the AI as its quarry. It is a real Node3D in
## group "player" with the two methods `_update_chase_state` and
## `_on_player_collision` actually call on one — `is_on_floor()`, because a quarry
## that cannot answer it is smelled unconditionally and the grounded rule would go
## untested, and `hit_by_crocodile()`, because the collision path's fallback for a
## player without it TELEPORTS the body to (0, 2, 0), which would move the quarry
## out from under the probe mid-measurement. Counting the calls is also how the
## check states the acceptance criterion out loud: a landed grab costs EXACTLY one
## predator hit, the same one a crocodile's bite costs.
const HUNT_STUB_SOURCE: String = """
extends Node3D
var hits: int = 0
func is_on_floor() -> bool:
	return true
func hit_by_crocodile(_attacker: Node = null) -> void:
	hits += 1
"""


func _probe_hunt_dispatch(hunt_species: String) -> void:
	"""
	Drive the SHIPPED `_update_chase_state` on a live body and read the arm back.

	@param hunt_species: the SPECIES key to probe

	This is the half that cannot be faked. Everything the geometry probe measures
	is still true of a build where the `match` in _update_chase_state has no
	"hunt" arm at all — `hunt_steer_point` would be a correct function nothing
	calls, which is the exact failure this file's header is written against. So
	this instantiates one body, points it at a stub quarry INSIDE its own ring,
	and asks the shipped function what it steers at:

	  frame 1              the hunt lock is non-empty (the arm RAN — nothing else
	                       populates it) and chase_target has been pushed OUT to
	                       the ring. Two gates rather than one because the code
	                       above the dispatch sets chase_target to the quarry, so
	                       "steering at the quarry" is what BOTH a missing arm and
	                       a missing telegraph look like, and they must not be
	                       reported as each other.
	  just before the      still on the ring — this is what makes it a WINDOW and
	  telegraph expires    not merely a flag that was set once.
	  just after           chase_target is the quarry itself: it committed.
	  after a grab         exactly one hit_by_crocodile, and the next frame is
	                       back on the ring for the whole disengage window.

	The body is the CROCODILE scene rather than the hunter's own, deliberately:
	`species` is a plain var read in _ready(), the behaviour lives entirely in the
	shared script, and every other live-body probe in this file uses that scene.
	What differs between the two .tscn files is the model, which no line of this
	measurement touches.

	The one line of noise in this file's output is the grab's own "bites the
	player" print, which is the shipped collision path talking. It is left alone:
	silencing it for a check would be the check changing the thing it measures.

	ponytail: the arm is driven by calling _update_chase_state() in a loop rather
	than by awaiting real physics frames — the same trade every other probe here
	makes. The ceiling is that nothing in _physics_process runs, so this measures
	the decision and not the travel; the geometry probe above owns the travel.
	"""
	var row: Dictionary = _species_table[hunt_species]
	if not row.has("hunt_standoff") or not row.has("hunt_telegraph_time"):
		return                          # already reported by the geometry probe
	var standoff: float = float(row["hunt_standoff"])
	var telegraph: float = float(row["hunt_telegraph_time"])
	var disengage: float = float(row["hunt_disengage_time"])

	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	# INSIDE the ring on purpose: the ring point is then BEHIND the hunter, which
	# no reading of the code above the dispatch can produce by accident.
	stub.global_position = Vector3(0.0, 0.0, standoff * 0.5)

	var croc: Node = load(CROC_SCENE).instantiate()
	croc.species = hunt_species         # before add_child, the row's own contract
	root.add_child(croc)
	croc.global_position = Vector3.ZERO
	# _ready() defers the quarry lookup to the end of the frame ("defer to allow
	# scene to fully load") and this probe never yields, so run the SHIPPED
	# lookup by hand rather than assigning `player_node` — a probe that set the
	# reference itself would also be free to set one the game could never resolve.
	croc._find_player()

	# The clock the arm counts its windows down against, read off the live node
	# rather than assumed: _behave_hunt takes it from get_physics_process_delta_time().
	var dt: float = croc.get_physics_process_delta_time()
	if dt <= 0.0:
		_fail("the live hunter reports a physics delta of %.4f s — the telegraph"
				% dt + " and disengage windows cannot drain, so this probe would"
				+ " measure a hunter frozen on its ring forever")
		_free_hunt_probe(croc, stub)
		return

	var quarry: Vector3 = stub.global_position
	croc._update_chase_state()
	if not croc.is_chasing:
		_fail("a %s %.1f m from a grounded quarry it smells %.1f m away did not"
				% [hunt_species, quarry.length(), float(row["detection_radius"])]
				+ " start chasing — the probe never reached the dispatch at all")
		_free_hunt_probe(croc, stub)
		return
	# TWO DIFFERENT FAILURES LOOK IDENTICAL FROM `chase_target` ALONE on this
	# frame — an arm that never ran, and an arm that ran and committed instantly —
	# so they are separated before either is reported. The lock is empty exactly
	# when _behave_hunt has not executed, which is the only thing the dispatch
	# decides; everything after this line is about what the arm then DID.
	if croc._hunt_lock.is_empty():
		_fail("a chasing %s left its hunt lock empty — the `match` in" % hunt_species
				+ " _update_chase_state is not reaching _behave_hunt, so the arm"
				+ " ships unrun and every static probe above it measures a function"
				+ " nothing calls")
		_free_hunt_probe(croc, stub)
		return
	# TWO CAUSES REMAIN ONCE THE ARM IS KNOWN TO HAVE RUN, and the message names
	# both rather than picking one: either the telegraph is not holding the unit
	# (it commits on the frame it smells you) or `hunt_steer_point` is no longer
	# producing a ring for it to hold. The geometry probe above pins down which —
	# it fails on the second and passes on the first.
	var acquired: float = croc.chase_target.distance_to(quarry)
	if absf(acquired - standoff) > EPSILON:
		_fail("on the acquisition frame a %s steered %.2f m from its quarry, not"
				% [hunt_species, acquired] + " at its %.1f m ring — either the"
				% standoff + " telegraph is not holding it (a hunter that commits on"
				+ " the frame it smells you owes the player a warning it never"
				+ " gave) or hunt_steer_point has stopped producing the ring")
		_free_hunt_probe(croc, stub)
		return

	# ---- the telegraph is a WINDOW ------------------------------------------
	# One frame short of the declared window it must still be shadowing; a few
	# frames past it, committed. Both ends, because "it eventually closed" is also
	# true of a hunter with no telegraph and "it shadowed once" of one that never
	# closes.
	var frames: int = int(telegraph / dt)
	for _i in range(maxi(frames - 2, 0)):
		croc._update_chase_state()
	var late: float = croc.chase_target.distance_to(quarry)
	if absf(late - standoff) > EPSILON:
		_fail("a %s had already committed %.2f s into its %.2f s telegraph"
				% [hunt_species, float(maxi(frames - 2, 0)) * dt, telegraph]
				+ " (steering %.2f m from the quarry) — the window is shorter than"
				% late + " the row declares, or is not a window at all")
	for _i in range(4):
		croc._update_chase_state()
	var committed: float = croc.chase_target.distance_to(quarry)
	if committed > EPSILON:
		_fail("a %s was still steering %.2f m off its quarry %.2f s after its"
				% [hunt_species, committed, telegraph] + " telegraph expired — it"
				+ " shadows and never closes, which is a predator that cannot"
				+ " reach you")

	# ---- the grab lands at full cost, THEN the unit disengages ---------------
	croc._on_player_collision(stub)
	if stub.hits != 1:
		_fail("one grab by a %s cost the player %d predator hits, not exactly 1 —"
				% [hunt_species, stub.hits] + " the disengage is meant to be pacing"
				+ " around a hit that lands at full parity, never a pulled punch"
				+ " and never a double charge")
	croc._update_chase_state()
	var after_grab: float = croc.chase_target.distance_to(quarry)
	if absf(after_grab - standoff) > EPSILON:
		_fail("the frame after a %s landed its grab it was still steering %.2f m"
				% [hunt_species, after_grab] + " from the quarry, not back out to"
				+ " its %.1f m ring — it re-chomps instead of withdrawing" % standoff)
	# …and it stays disengaged for the whole declared window, then re-commits.
	# Without the second half, "it backed off" is also true of a unit that never
	# comes back, which is a hunter the player can ignore.
	var hold: int = int(disengage / dt) - 4
	for _i in range(maxi(hold, 0)):
		croc._update_chase_state()
	var holding: float = croc.chase_target.distance_to(quarry)
	if absf(holding - standoff) > EPSILON:
		_fail("a %s re-committed %.2f s into its %.2f s disengage (steering %.2f m"
				% [hunt_species, float(maxi(hold, 0)) * dt, disengage, holding]
				+ " from the quarry) — the withdrawal is shorter than the row"
				+ " declares")
	for _i in range(8):
		croc._update_chase_state()
	var recommitted: float = croc.chase_target.distance_to(quarry)
	if recommitted > EPSILON:
		_fail("a %s never re-committed after its %.2f s disengage expired"
				% [hunt_species, disengage] + " (still %.2f m off the quarry) —"
				% recommitted + " one grab retired it from the encounter")

	print("hunt dispatch: %s holds its ring at %.2f m through a %.2f s telegraph,"
			% [hunt_species, late, telegraph] + " then steers %.2f m off the quarry;"
			% committed + " one grab costs %d hit and puts it back out at %.2f m for"
			% [stub.hits, after_grab] + " %.1f s (%.2f m at the end of it, %.2f m"
			% [disengage, holding, recommitted] + " after)")

	_free_hunt_probe(croc, stub)


# ============================================================================
# CHECK 8f — THE SCENT TRAIL: a tracker arrives on a walker, never on a runner
# ============================================================================
# The hunt arm's SECOND LEG (owner design ruling 2026-08-31). Out of detection a
# hunter follows the breadcrumb trail `crocodile_lod_manager` records, walking it
# at its own chase speed while ASLEEP — advanced kinematically by the LOD scan,
# because a body 150 m out runs no `_physics_process` and must not be woken for
# this. Three things can silently break and none of them errors:
#
#   * the trail stops being recorded, or expires wrong — the nose smells nothing
#     and hunters are exactly as absent as the bead was filed about;
#   * the LOD manager stops calling `advance_tracking` — tracking then only works
#     inside SIM_RADIUS, which is where direct detection already worked;
#   * tracking outruns the lattice — a tracker that catches a RUNNING player has
#     quietly repealed "running always escapes", the tightest promise in the game.
#
# So this drives the SHIPPED manager and the SHIPPED arm on live nodes, over a
# walk and a run, and measures both ends.

## Metres the probe quarry walks before stopping — the acceptance's "walks 200 m
## and stops".
const SCENT_WALK_M: float = 200.0

## Metres the tracker is seeded BEHIND the quarry's start, the acceptance's
## "seeded 150 m behind". Read against SIM_RADIUS (45) this is the whole point:
## the unit spends almost the entire probe asleep.
const SCENT_LEAD_M: float = 150.0

## Probe timestep. Coarser than a physics frame on purpose — the LOD scan it
## drives runs at ~9 Hz, so nothing here resolves finer than that anyway.
const SCENT_DT: float = 0.1

## Seconds the probe gives the tracker to arrive. The honest arithmetic: 150 m of
## lead plus 200 m of walking, closed at 6.5 - 5.0 = 1.5 m/s while the quarry
## moves and at 6.5 m/s after it stops, is ~50 s. 180 s is a generous ceiling that
## still fails a tracker which has stopped closing at all.
const SCENT_LIMIT_S: float = 180.0


func _check_scent_tracking() -> void:
	"""
	Every SPECIES row that declares a nose, walked and run against.

	Iterates `scent_radius` across the table rather than naming the hunter, the
	same discipline as `_species_with(behavior)`: the day a second retrieval unit
	gets a nose it is measured, with no edit here.
	"""
	var names: Array[String] = []
	for key: Variant in _species_table:
		if float((_species_table[key] as Dictionary).get("scent_radius", 0.0)) > 0.0:
			names.append(String(key))
	if names.is_empty():
		_fail("no SPECIES row declares a 'scent_radius' — the hunt arm's scent"
				+ " tracking leg is unreachable from any species, so hunters are"
				+ " back to idling where they spawned")
		Sentinel.done("scent_tracking")
		return
	for species_name: String in names:
		var row: Dictionary = _species_table[species_name]
		# A nose belongs to the arm that knows what to do with one. `_track_scent`
		# is called from `_behave_hunt` and from nowhere else, so a row that
		# declares a radius under any other behaviour has bought dead data.
		if String(row.get("behavior", "")) != "hunt":
			_fail("SPECIES['%s'] declares scent_radius but its behavior is '%s' —"
					% [species_name, String(row.get("behavior", ""))]
					+ " the tracking leg only runs inside the 'hunt' arm, so the"
					+ " nose is data nothing reads")
			continue
		# A nose narrower than the eyes is the same dead data by a different route:
		# anything it could smell it has already detected, and detection wins.
		var detection: float = float(row.get("detection_radius", 0.0))
		var scent: float = float(row["scent_radius"])
		if scent <= detection:
			_fail("SPECIES['%s'] smells %.1f m but SEES %.1f m — a nose inside the"
					% [species_name, scent, detection] + " detection radius never"
					+ " fires, because direct detection out-votes it every frame")
			continue
		# The whole reason the LOD manager had to be involved: a body that could do
		# its tracking while awake would need none of `advance_tracking`.
		if scent <= _sim_radius:
			_fail("SPECIES['%s'] smells %.1f m, inside SIM_RADIUS %.1f — a tracker"
					% [species_name, scent, _sim_radius] + " that never sleeps is"
					+ " not the feature that was asked for, and the slept-but-"
					+ "stalking half of this check would be measuring nothing")
		_probe_scent(species_name, true)
		_probe_scent(species_name, false)
	Sentinel.done("scent_tracking")


func _probe_scent(species_name: String, walking: bool) -> void:
	"""
	Seed a tracker `SCENT_LEAD_M` behind a moving quarry and see whether it arrives.

	@param species_name: the SPECIES key to probe
	@param walking: true = the quarry walks SCENT_WALK_M and stops (it must be
	                caught up with); false = the quarry keeps RUNNING (it must not)

	TWO PHASES, because the feature has two halves and each can fail alone:

	  phase 1  SLEPT. `lod_active` is forced false and the manager's own `_process`
	           is driven. Nothing here calls a movement function on the body — if
	           it moves at all, it is because `_scan_crocodiles` reached
	           `advance_tracking`, which is the dispatch this half exists to prove.
	           It ends when the manager WAKES the unit at SIM_RADIUS, which is the
	           "wakes normally once inside SIM_RADIUS" half of the ruling.
	  phase 2  AWAKE. The shipped `_update_chase_state` is driven and the body is
	           integrated along the `movement_direction` that `_track_move` sets,
	           until direct detection takes over (`is_chasing`). This is the leg
	           the `_physics_process` movement branch selects on `is_tracking`.

	The RUN control is the negative half, and it is what makes the walk half mean
	something: identical row, identical machinery, one speed apart. A probe where
	everything is caught has measured no lattice at all.

	ponytail: phase 2 integrates the heading by hand rather than awaiting real
	physics frames — the same trade every live-body probe in this file makes. The
	ceiling is that gravity, the feelers and the bite lunge are not modelled; none
	of them can turn "walks up a trail" into "does not".
	"""
	var row: Dictionary = _species_table[species_name]
	var quarry_speed: float = _walk_speed if walking else _slowest_run_speed
	if quarry_speed <= 0.0:
		_fail("the scent probe has no %s speed to move its quarry at — check 8f"
				% ("walk" if walking else "run") + " would measure a stationary"
				+ " player, which every tracker reaches trivially")
		return

	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	stub.global_position = Vector3.ZERO

	# The SHIPPED manager, not a restatement of it: this is the node that records
	# the trail and the node that walks a sleeper along it, so a change to either
	# is a change to what this check measures.
	var lod := Node.new()
	lod.set_script(load(LOD_SCRIPT))
	root.add_child(lod)

	var croc: Node = load(CROC_SCENE).instantiate()
	croc.species = species_name         # before add_child, the row's own contract
	root.add_child(croc)
	croc.global_position = Vector3(-SCENT_LEAD_M, 0.0, 0.0)
	croc._find_player()
	# ASLEEP BY HAND. `set_lod_active(false)` refuses a body that is not
	# `is_on_floor()`, and a headless probe has no floor — so the setter would
	# leave this unit awake and the slept half of the feature would go untested.
	# Writing the flag and the callback switch is exactly what the setter does.
	croc.lod_active = false
	croc.set_physics_process(false)

	var detection: float = float(row.get("detection_radius", 0.0))
	var start_gap: float = croc.global_position.distance_to(stub.global_position)
	var t: float = 0.0
	var walked: float = 0.0

	# ---- phase 1: slept, advanced only by the manager's scan -----------------
	# SCAN FIRST, THEN MOVE, and the order matters: the quarry has to lay a crumb
	# where it is STANDING before it walks off, or the first crumb is already
	# further than the seed distance and a tracker seeded exactly SCENT_LEAD_M out
	# can never smell anything at all. That also makes this probe the boundary
	# case on purpose — the nose is 150 m and the seed is 150 m, so a `scent_radius`
	# that stopped being inclusive at its own edge fails here.
	while t < SCENT_LIMIT_S and not croc.lod_active:
		lod._process(SCENT_DT)
		if not walking or walked < SCENT_WALK_M:
			stub.global_position.x += quarry_speed * SCENT_DT
			walked += quarry_speed * SCENT_DT
		t += SCENT_DT

	var woke_at: float = t
	var slept_gap: float = croc.global_position.distance_to(stub.global_position)

	if not walking:
		# THE NEGATIVE CONTROL. A runner lays the same trail; the tracker simply
		# cannot close on it, and the gap has to be WIDER than it started.
		if croc.lod_active:
			_fail("a %s tracked a RUNNING quarry (%.1f m/s) all the way to"
					% [species_name, quarry_speed] + " SIM_RADIUS in %.0f s — the"
					% woke_at + " scent leg has outrun the speed lattice, and"
					+ " 'running always escapes' is no longer true")
		elif slept_gap <= start_gap:
			_fail("a %s closed from %.0f m to %.0f m on a RUNNING quarry — it"
					% [species_name, start_gap, slept_gap] + " should be falling"
					+ " behind at %.1f m/s, so tracking is moving it faster than"
					% (quarry_speed - float(row["chase_speed"])) + " its row's"
					+ " chase_speed")
		else:
			print("scent tracking: %s never caught a %.1f m/s runner — %.0f m"
					% [species_name, quarry_speed, start_gap] + " became %.0f m"
					% slept_gap + " in %.0f s, still asleep" % t)
		_free_scent_probe(croc, stub, lod)
		return

	if not croc.lod_active:
		_fail("a %s seeded %.0f m behind a quarry that walked %.0f m and stopped"
				% [species_name, start_gap, SCENT_WALK_M] + " was still %.0f m"
				% slept_gap + " away after %.0f s — either the trail is not being"
				% t + " recorded, or the LOD scan never reached advance_tracking,"
				+ " so a slept hunter does not stalk and the nose is decoration")
		_free_scent_probe(croc, stub, lod)
		return

	# ---- phase 2: awake, the arm's own leg ----------------------------------
	var arrived: bool = false
	while t < SCENT_LIMIT_S:
		croc._update_chase_state()
		if croc.is_chasing:
			arrived = true
			break
		if not croc.is_tracking:
			_fail("a woken %s standing %.0f m from its quarry is neither chasing"
					% [species_name, croc.global_position.distance_to(stub.global_position)]
					+ " nor tracking — the awake half of the leg drops the trail"
					+ " the moment the body wakes, so it stalls at SIM_RADIUS")
			break
		croc._track_move()
		croc.global_position += croc.movement_direction * croc.chase_speed_instance * SCENT_DT
		lod._process(SCENT_DT)
		t += SCENT_DT

	if not arrived:
		_fail("a %s that woke %.0f m from its quarry never reached its own %.1f m"
				% [species_name, slept_gap, detection] + " detection radius within"
				+ " %.0f s — the trail brought it near and then stopped bringing"
				% SCENT_LIMIT_S + " it in")
	else:
		print("scent tracking: %s seeded %.0f m behind a quarry that walked %.0f m"
				% [species_name, start_gap, SCENT_WALK_M] + " woke at %.0f m after"
				% slept_gap + " %.0f s asleep and acquired it %.0f s in (nose"
				% [woke_at, t] + " %.0f m, eyes %.0f m)"
				% [float(row["scent_radius"]), detection])

	_free_scent_probe(croc, stub, lod)


# ============================================================================
# CHECK 8g — a tracker that walks off its birth chunk SURVIVES, and leaves no twin
# ============================================================================
# The half of scent tracking that check 8f cannot see, because its probe has no
# terrain: everything the world spawns is parented to its chunk so that unloading
# the chunk frees it, and a tracker WALKS. Its birth chunk falls behind the player
# it is following and takes the unit with it — deleting the hunter precisely for
# doing the thing the feature exists to make it do, which is a silent regression
# to the bug this bead was filed about. `adopt_wanderer` re-parents it to the
# ground under its feet; the cost of that is that the birth chunk can regenerate
# while the unit lives, so the slot registry has to refuse to build the twin.
#
# Both halves are measured here, and the second needs the first: a registry that
# never releases a slot is a hunter that never comes back.

## How far to sweep for a chunk that actually rolls a hunter. HUNTER_CHANCE is
## 0.15, so a few dozen candidates is overwhelming odds; a sweep that finds none
## is reported rather than skipped.
const ADOPT_SCAN_CHUNKS: int = 60


func _check_wanderer_adoption(terrain_script: GDScript) -> void:
	"""
	Walk one real hunter off its chunk and check who owns it afterwards.

	@param terrain_script: endless_terrain.gd, driven DETACHED — `adopt_wanderer`
	                       needs only `world_to_chunk` (pure) and `active_chunks`,
	                       while the chunk parents and the unit are really in the
	                       tree, which is what `reparent` needs. Attaching the
	                       terrain would start it streaming a world of its own
	                       (see `_make_chunk_parent`).
	"""
	var terrain: Node = Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(RUN_SEEDS[0])

	# Find a chunk this seed really gives a hunter to, rather than assuming one.
	var birth := Vector2i.ZERO
	var birth_parent: MeshInstance3D = null
	var hunter: Node3D = null
	for i: int in ADOPT_SCAN_CHUNKS:
		var cp := Vector2i(FIELD + i, FIELD)
		var parent := _make_chunk_parent(terrain.chunk_to_world(cp))
		terrain.spawn_hunters_in_chunk(cp, parent, [])
		if parent.get_child_count() > 0:
			birth = cp
			birth_parent = parent
			hunter = parent.get_child(0) as Node3D
			break
		parent.free()
	if hunter == null:
		_fail("no chunk in a %d-chunk sweep spawned a hunter at HUNTER_CHANCE —"
				% ADOPT_SCAN_CHUNKS + " check 8g has no subject, so the migration"
				+ " that keeps a tracker alive across a chunk unload is untested")
		terrain.free()
		Sentinel.done("wanderer_adoption")
		return
	var slot: String = hunter.name

	# The chunk it is about to walk onto, one chunk along. Both go into
	# `active_chunks` because that map is the terrain's answer to "what ground is
	# loaded", and `adopt_wanderer` refuses to hand a body to ground that is not.
	var dest := birth + Vector2i(1, 0)
	var dest_parent := _make_chunk_parent(terrain.chunk_to_world(dest))
	terrain.active_chunks[birth] = birth_parent
	terrain.active_chunks[dest] = dest_parent

	# Stand it in the middle of the destination chunk and hand it over.
	var dest_centre: Vector3 = terrain.chunk_to_world(dest)
	hunter.global_position = Vector3(dest_centre.x, hunter.global_position.y, dest_centre.z)
	var stood_at: Vector3 = hunter.global_position
	terrain.adopt_wanderer(hunter)

	if hunter.get_parent() != dest_parent:
		_fail("a hunter standing in chunk %s is still parented to its birth chunk"
				% str(dest) + " %s — the chunk that unloads when the player walks"
				% str(birth) + " away will delete a tracker that is doing exactly"
				+ " what the scent leg asks of it")
	var drift: float = hunter.global_position.distance_to(stood_at)
	if drift > EPSILON:
		_fail("adopt_wanderer moved the body it re-parented by %.2f m — the"
				% drift + " transfer has to keep the GLOBAL transform, or every"
				+ " migration teleports the unit by one chunk origin (50 m) and a"
				+ " tracker crossing a boundary jumps instead of walking")

	# ...and the birth chunk must now refuse to build its twin, because the name is
	# the room-wide crocodile id and two bodies cannot share one.
	var rebuilt := _make_chunk_parent(terrain.chunk_to_world(birth))
	terrain.spawn_hunters_in_chunk(birth, rebuilt, [])
	if rebuilt.get_child_count() > 0:
		_fail("chunk %s rebuilt its hunter while the migrated one is still alive —"
				% str(birth) + " two bodies now answer to '%s', which is one" % slot
				+ " crocodile id shared by two transforms in every room")
	rebuilt.free()

	# ...and it must build it again once that body is gone, or a slot leaks for the
	# life of the run and the world quietly loses a hunter every migration.
	hunter.free()
	var revived := _make_chunk_parent(terrain.chunk_to_world(birth))
	terrain.spawn_hunters_in_chunk(birth, revived, [])
	if revived.get_child_count() == 0:
		_fail("chunk %s never rebuilt its hunter after the migrated body was"
				% str(birth) + " freed — the slot registry holds a dead name, so"
				+ " every tracker the world loses is lost permanently")
	else:
		print("wanderer adoption: '%s' moved from chunk %s to %s, the birth chunk"
				% [slot, str(birth), str(dest)] + " refused to rebuild it, and"
				+ " rebuilt it once the body was freed")
	revived.free()

	birth_parent.free()
	dest_parent.free()
	terrain.free()
	Sentinel.done("wanderer_adoption")


func _free_scent_probe(croc: Node, stub: Node, lod: Node) -> void:
	"""
	Tear the scent probe down IMMEDIATELY — same argument as `_free_hunt_probe`.

	The manager matters as much as the stub here: it stands in group
	"lod_manager", which every crocodile the 289-chunk sweep spawns would resolve
	through `_track_scent`, and it holds a trail that would answer them.
	"""
	croc.free()
	stub.free()
	lod.free()


func _free_hunt_probe(croc: Node, stub: Node) -> void:
	"""
	Tear the live pair down IMMEDIATELY, not at the end of the frame.

	@param croc: the probe's hunter body
	@param stub: the probe's quarry

	`free()` rather than `queue_free()` because the stub sits in group "player"
	and the 289-chunk sweep runs after this check: a quarry still standing in the
	tree is one every crocodile the sweep spawns would resolve through
	`_find_player`, which is a probe perturbing the measurement that follows it.
	Safe here for the same reason it is safe in _model_top — this runs from
	_run(), never from inside a physics or signal callback.
	"""
	croc.free()
	stub.free()


# ============================================================================
# CHECK 8d — a LEAPING boss hops on a clock, lands inside its leash, and still
#            loses a foot race it must lose
# ============================================================================

## The smallest apex, in metres, a "leap" row may claim and still be called a hop.
## A metre clears the tallest thing this world puts on flat ground short of a
## block, and it is far above anything `bob_amount` or the waddle can produce —
## so a row whose arc constants make a 4 cm bounce fails here instead of shipping
## an arm that runs perfectly and is invisible.
const LEAP_APEX_MIN: float = 1.0

## Slack on the hop COUNT over a race, in hops. The race window is not a whole
## number of cycles and the first hop fires on frame 1, so the count is expected
## to land within one of `seconds / (airtime + cooldown)`; anything further out
## is a cadence that is not the row's.
const LEAP_HOP_COUNT_SLACK: float = 1.0


func _check_leap_cycle(croc_ai: GDScript) -> void:
	"""
	THE SEVENTH ARM'S PROBE. Drive the shipped hop rule and race what it produces.

	Owner, verbatim: "let those Rock and Dragons be able to make a decent jumps
	like windman does with F key." A hop is the cougar's bounded burst with a
	vertical component — a leg above the sustained ceiling paid for by a mandatory
	recovery leg below it — so this check is check 8's, in seconds instead of
	metres, and it asserts the same four things for the same four reasons. Read
	_check_burst_escape first; everything it says about why an escape is SIMULATED
	rather than argued in a comment applies here unchanged.

	What this file measures is the PURE half — `leap_due()`, `leap_airtime()` and
	`leap_reach()`, the three static functions `_behave_leap` itself calls, so the
	cadence and the cycle average measured here are the shipped ones. What it
	cannot reach — that the body actually leaves the ground, that the arc brings it
	back to y = 0, that the `match` in _update_chase_state reaches the arm at all,
	and that the territory gate refuses a hop over the fence in a live world — is
	measured in boss_selfcheck.gd, which has a physics world and a real boss in it.
	Neither half is sufficient alone and both ship.

	FIVE THINGS, and each is a way the arm can be wrong while reading correctly:

	  1. THE ARC IS AN ARC. Both constants positive (a zero `leap_gravity` is a
	     boss that never comes down) and an apex over LEAP_APEX_MIN — because "the
	     arm ran" is also true of a hop 4 cm tall, which is the one failure that
	     survives every other assertion here and is invisible in play as anything
	     but a boss that still reads as a heavy quadruped.
	  2. THE HOP IS A BURST AND THE RECOVERY COSTS SOMETHING. `leap_speed_factor`
	     over 1.0 and `leap_recover_factor` under it, check 8's two guards
	     verbatim: at 1.0 the "hop" is an ordinary chase with a comment, and a
	     recovery at or above 1.0 is a permanent speed-up over the whole cycle.
	  3. THE REACH FITS THE LEASH. `_behave_leap` refuses to launch when the
	     projected landing falls outside the territory, so a row whose reach
	     approaches BOSS_TERRITORY_RADIUS is a boss that may only ever hop from a
	     shrinking disc around its own home — legal, silent, and not what anyone
	     tuned. The legal launch disc is `radius - reach`, and this reports it.
	  4. THE CADENCE IS THE ROW'S. Hops counted over a long window must match
	     `airtime + leap_cooldown`. A cooldown that is never re-armed launches
	     every grounded frame, which is a boss that never touches the ground —
	     and, to a check that only asserted "it hopped", a pass.
	  5. THE ESCAPE, over repeated cycles, in three races with a control:
	     a runner at the slowest character's run against the WORST animal the game
	     can build (a boss's speed is clamped to MAX_CHASE_SPEED) must GAIN; a
	     walker must be caught, or the "predator" is slower than walking; and the
	     same worst animal with the RECOVERY REMOVED must catch the runner, which
	     is what proves the recovery window is what saves them rather than the
	     numbers happening to work out.

	The races reuse check 8's BURST_RACE_* constants deliberately: it is the same
	corridor, the same gap and the same window, so the two arms' escapes are
	directly comparable numbers rather than two similar-looking ones.
	"""
	if _slowest_run_speed <= 0.0:
		_fail("could not derive the slowest character's run from player_controller.gd"
				+ " (RUN_SPEED x the smallest CHARACTER_SPEED) — the leap check would"
				+ " have raced the hop against a ceiling of zero and passed vacuously")
		Sentinel.done("leap_cycle")
		return

	var leapers: Array[String] = _species_with("leap")
	if leapers.is_empty():
		# The negative control for the whole check, the ranged probe's verbatim:
		# with no leaping row every loop below iterates zero times and this file
		# reports OK having measured nothing. The arm exists in the AI, so a table
		# with no row carrying it is a half-landed bead.
		_fail("no SPECIES row has behavior 'leap' — the hop rule this check drives"
				+ " is in the AI (_behave_leap / leap_due) with nothing dispatching"
				+ " to it")
		Sentinel.done("leap_cycle")
		return
	for species_name: String in leapers:
		_probe_leap(croc_ai, species_name)
	Sentinel.done("leap_cycle")


func _probe_leap(croc_ai: GDScript, species_name: String) -> void:
	"""
	One leaping species: its arc, its reach, its cadence and its escape.

	@param croc_ai: piglet_crocodile_ai.gd, for the shipped leap_* statics
	@param species_name: the SPECIES key to probe
	"""
	var row: Dictionary = _species_table[species_name]
	var missing: Array[String] = []
	for key: String in ["leap_launch_speed", "leap_gravity", "leap_speed_factor",
			"leap_cooldown", "leap_recover_factor"]:
		if not row.has(key):
			missing.append(key)
	if not missing.is_empty():
		_fail("SPECIES['%s'] has behavior 'leap' but no %s — leap_due() and"
				% [species_name, missing] + " leap_airtime() read them every frame"
				+ " it chases, and answer 'no hop' when they are gone, so the boss"
				+ " ships as an ordinary ground chaser with a long comment")
		return

	# ---- 1. THE ARC IS AN ARC ----------------------------------------------
	var airtime: float = CrocSteering.leap_airtime(row)
	if airtime <= 0.0:
		_fail("SPECIES['%s'] leap_launch_speed %.2f / leap_gravity %.2f give an"
				% [species_name, float(row["leap_launch_speed"]), float(row["leap_gravity"])]
				+ " airtime of %.3f s — leap_due() refuses every hop, so the arm"
				% airtime + " runs and does nothing")
		return
	var apex: float = float(row["leap_launch_speed"]) * airtime * 0.25
	if apex < LEAP_APEX_MIN:
		_fail("SPECIES['%s'] hops %.2f m high (want >= %.1f m) — the arm runs,"
				% [species_name, apex, LEAP_APEX_MIN] + " the body technically"
				+ " leaves the ground, and the winged boss this bead exists for"
				+ " still reads as a heavy quadruped")

	# ---- 2. IT IS A BURST, AND THE RECOVERY IS PAID ------------------------
	var speed_factor: float = float(row["leap_speed_factor"])
	var recover_factor: float = float(row["leap_recover_factor"])
	if speed_factor <= 1.0:
		_fail("SPECIES['%s'].leap_speed_factor %.2f is at or under 1.0 — the hop"
				% [species_name, speed_factor] + " carries the body no faster than"
				+ " a walk-in would, so the arc is decoration on an ordinary chase")
	if recover_factor >= 1.0:
		_fail("SPECIES['%s'].leap_recover_factor %.2f is at or above 1.0 — the"
				% [species_name, recover_factor] + " 'recovery' costs the animal"
				+ " nothing and the hop is a permanent speed-up over the cycle")

	# The two speeds the game can actually resolve for this row. A BOSS-ONLY row's
	# stated chase_speed is overridden at spawn, so racing it would measure an
	# animal that is never built (see _boss_chase_speed).
	var nominal: float = float(row["chase_speed"])
	if _boss_only.has(species_name):
		nominal = minf(float(row.get("boss_chase_speed", _boss_chase_speed)),
				_max_chase_speed)
	var peak: float = _max_chase_speed * speed_factor

	# ---- 3. THE REACH FITS THE LEASH ---------------------------------------
	var reach: float = CrocSteering.leap_reach(_max_chase_speed, row)
	if _boss_only.has(species_name) and reach >= _boss_territory_radius:
		_fail("SPECIES['%s'] hops %.1f m, which is not inside its own %.1f m"
				% [species_name, reach, _boss_territory_radius] + " territory —"
				+ " _behave_leap projects the landing point and refuses a hop that"
				+ " would cross the fence, so at this reach the legal launch disc"
				+ " has closed to nothing and the boss can never leave the ground")

	# ---- 4 and 5. THE CADENCE AND THE ESCAPE, over repeated cycles ---------
	var runner: Dictionary = _leap_race(croc_ai, row, _max_chase_speed,
			_slowest_run_speed, false)
	var walker: Dictionary = _leap_race(croc_ai, row, nominal, _walk_speed, false)
	var control: Dictionary = _leap_race(croc_ai, row, _max_chase_speed,
			_slowest_run_speed, true)

	print("leap cycle (%s): %.2f m apex over %.2f s, reach %.1f m inside a %.1f m"
			% [species_name, apex, airtime, reach, _boss_territory_radius]
			+ " territory; peak %.2f m/s vs the %.2f ceiling; a %.1f m/s run opens"
			% [peak, _max_chase_speed, _slowest_run_speed]
			+ " the %.1f m gap to %.1f m over %.0f s in %d hops, a %.1f m/s walk"
			% [BURST_RACE_GAP, float(runner["gap"]), BURST_RACE_SECONDS,
					int(runner["hops"]), _walk_speed]
			+ " closes it to %.1f m (same animal, recovery OFF: %.1f m)"
			% [float(walker["gap"]), float(control["gap"])])

	var expected_hops: float = BURST_RACE_SECONDS / (airtime + float(row["leap_cooldown"]))
	if absf(float(runner["hops"]) - expected_hops) > LEAP_HOP_COUNT_SLACK:
		_fail("a %s hopped %d times in %.0f s; its %.2f s arc and %.2f s cooldown"
				% [species_name, int(runner["hops"]), BURST_RACE_SECONDS, airtime,
						float(row["leap_cooldown"])]
				+ " allow %.1f — the recovery clock is not the one the row states,"
				% expected_hops + " and a clock that is never re-armed launches on"
				+ " every grounded frame")

	if float(runner["gap"]) - BURST_RACE_GAP < BURST_RUNNER_GAIN_MIN:
		_fail("a running player only gained %.2f m on a %s over %.0f s"
				% [float(runner["gap"]) - BURST_RACE_GAP, species_name, BURST_RACE_SECONDS]
				+ " (want >= %.2f m) — the hop is above MAX_CHASE_SPEED and the"
				% BURST_RUNNER_GAIN_MIN + " recovery window is no longer paying for"
				+ " it, so running has stopped escaping and that is the promise the"
				+ " game is balanced on")
	if BURST_WALKER_MUST_CATCH and float(walker["gap"]) > 0.0:
		_fail("a %s never caught a WALKING player — it stayed %.2f m short over"
				% [species_name, float(walker["gap"])] + " %.0f s at its resolved"
				% BURST_RACE_SECONDS + " %.2f m/s. The cycle average has fallen"
				% nominal + " under WALK_SPEED (%.2f), which is not a difficulty"
				% _walk_speed + " knob but a broken predator")
	if float(control["gap"]) > 0.0:
		_fail("the NEGATIVE CONTROL for %s did NOT catch the runner with the"
				% species_name + " RECOVERY SWITCHED OFF — it stayed %.2f m short."
				% float(control["gap"]) + " The escape measured with it on is"
				+ " therefore not coming from the recovery window, so this check is"
				+ " not measuring the hop cycle at all")

	# ---- THE LEASH GATE, isolated ------------------------------------------
	# `leap_due` takes the territory verdict as a parameter precisely so it can be
	# driven from both sides here. Refused for a whole window it must never fire —
	# and the positive control at the same clock must, or the refusal proves
	# nothing about the gate and everything about a broken cooldown.
	var refused: Dictionary = _leap_race(croc_ai, row, nominal, _walk_speed, false, false)
	if int(refused["hops"]) > 0:
		_fail("a %s launched %d time(s) with the projected landing REFUSED —"
				% [species_name, int(refused["hops"])] + " leap_due() is ignoring"
				+ " the territory verdict _behave_leap hands it, so a boss can hop"
				+ " over its own fence and the leash is only a ground rule")
	if int(walker["hops"]) <= 0:
		_fail("a %s launched nothing over %.0f s with the landing ALLOWED — the"
				% [species_name, BURST_RACE_SECONDS] + " refusal above therefore"
				+ " proves nothing about the leash gate, only that this row never"
				+ " hops at all")


func _leap_race(croc_ai: GDScript, row: Dictionary, chase: float, quarry_speed: float,
		no_recovery: bool, landing_ok: bool = true) -> Dictionary:
	"""
	Race one leaping predator against one quarry down a straight line.

	@param croc_ai: the AI script, for its static leap_due / leap_airtime
	@param row: the SPECIES row to simulate
	@param chase: the predator's resolved chase speed (what _ready() left it at)
	@param quarry_speed: the quarry's constant speed
	@param no_recovery: the negative control — pin the recovery leg to the hop's
	                    own factor, so the animal never pays for a bound
	@param landing_ok: the territory verdict `_behave_leap` computes and hands to
	                   leap_due(); false drives the refusal path
	@return { "gap": metres at the end (0.0 on contact), "hops": launches counted }

	THE LOOP IS `_behave_leap`'s, ONE STATEMENT PER BRANCH, and it drives the
	SHIPPED `leap_due()` every frame with the real grounded flag — including the
	airborne frames, where the function's early return is what stops the recovery
	clock draining in the air. A probe that only called it while grounded would
	pass on a build where that early return had been deleted, which is exactly the
	cadence bug worth catching.

	WHAT THE MODEL LEAVES OUT, honestly, is check 8's list unchanged: turning,
	obstacle feelers, the bite's lunge, and the vertical axis itself — the arc's
	HEIGHT does not enter a ground race, only its duration does. All of them slow
	the predator relative to a quarry running in a straight line, so a predator
	that cannot catch a runner here cannot catch one anywhere.
	"""
	var probe_row: Dictionary = row
	if no_recovery:
		probe_row = row.duplicate()
		probe_row["leap_recover_factor"] = row["leap_speed_factor"]

	var speed_factor: float = float(probe_row["leap_speed_factor"])
	var recover_factor: float = float(probe_row["leap_recover_factor"])
	var airtime: float = CrocSteering.leap_airtime(probe_row)

	var pos := Vector3.ZERO
	var quarry := Vector3(0.0, 0.0, BURST_RACE_GAP)
	var lock: Dictionary = {}
	var airborne_left: float = 0.0
	var hops: int = 0
	var steps := int(BURST_RACE_SECONDS / BURST_RACE_DT)
	for _step in range(steps):
		var grounded: bool = airborne_left <= 0.0
		var launched: bool = CrocSteering.leap_due(grounded, landing_ok, BURST_RACE_DT,
				lock, probe_row)
		if launched:
			airborne_left = airtime
			hops += 1
		var factor: float = recover_factor if (grounded and not launched) else speed_factor
		if airborne_left > 0.0:
			airborne_left -= BURST_RACE_DT
		pos.z += chase * factor * BURST_RACE_DT
		quarry.z += quarry_speed * BURST_RACE_DT
		if quarry.z - pos.z <= 0.0:
			return { "gap": 0.0, "hops": hops }
	return { "gap": quarry.z - pos.z, "hops": hops }


# ============================================================================
# CHECK 8e — a CONED predator only sees ahead, and gives you a beat before it
#            commits
# ============================================================================

## How far into the cone's own detection radius the probe stands its quarry. Well
## inside, so "not detected" can only ever be about the BEARING — a fraction near
## 1.0 would let a rounding error in the radius test masquerade as a cone.
const CONE_PROBE_FRACTION: float = 0.85

## How many frames past the declared telegraph the probe waits before demanding a
## chase. Two, and no more: "it eventually chased" is also true of a body with no
## cone at all, so the check has to be able to say the beat was still holding one
## frame earlier.
const CONE_PROBE_SLACK: int = 2


func _check_view_cone(croc_ai: GDScript) -> void:
	"""
	Check 8e. Drive the SHIPPED detection code on a live body carrying a
	`view_cone_deg`, from behind and from in front.

	@param croc_ai: the crocodile AI script, for its consts

	`view_cone_deg` is the first SPECIES field that changes whether a predator can
	see you at all, and it is the one kind of field that ships broken invisibly: a
	cone applied in the wrong space, or read off the wrong axis, produces a guard
	that behaves exactly like every guard before it and a stealth mechanic that
	simply is not there. So this measures the two halves of the claim on the real
	`_update_chase_state`, and nothing here reimplements the geometry:

	  BEHIND    a quarry well inside the detection radius and directly behind the
	            body is NOT chased, for longer than the telegraph — which is what
	            makes "sneak up behind it" a move rather than a hope.
	  AHEAD     the same quarry, same distance, in front: chased — but NOT on the
	            frame it enters the cone, and not one frame before
	            `SPOT_TELEGRAPH_TIME` is spent. Both ends, because a beat that
	            never expires is a blind predator and a beat of zero is no beat.

	AND THE 360 CONTROL, which is what stops this passing on a build where the cone
	code accidentally blinds everything: the crocodile row declares no cone, and it
	must chase the same quarry standing directly behind it.

	IT ITERATES THE TABLE, never a list of its own — every row carrying the field
	is probed, so the second coned species is covered the day its row lands, and a
	cone typed onto a row that no probe reaches cannot happen.
	"""
	var coned: Array[String] = []
	for name_v: Variant in _species_table:
		var row: Dictionary = _species_table[name_v]
		if float(row.get("view_cone_deg", 360.0)) < 360.0:
			coned.append(String(name_v))
	if coned.is_empty():
		# Not a failure: nothing in the table claims a cone, so there is nothing to
		# measure. The control below is skipped with it — it exists to prove the
		# cone code did not blind the un-coned rows, and there is no cone code in
		# play to have done that.
		Sentinel.done("view_cone")
		return

	var telegraph: float = float(croc_ai.get("SPOT_TELEGRAPH_TIME"))
	if telegraph <= 0.0:
		_fail("piglet_crocodile_ai.SPOT_TELEGRAPH_TIME is %.2f — a coned predator"
				% telegraph + " commits on the frame it sees you, so the arc it"
				+ " cannot see behind it is the ONLY warning the player gets")
	for species_name: String in coned:
		_probe_view_cone(species_name, telegraph)
	# The control, on the row every unknown species falls back to.
	_probe_view_cone("crocodile", telegraph)
	print("view cones: %s probed from behind and ahead through a %.2f s beat,"
			% [str(coned), telegraph] + " crocodile (no cone) as the control")
	Sentinel.done("view_cone")


func _probe_view_cone(species_name: String, telegraph: float) -> void:
	"""
	One row, both bearings. A `view_cone_deg`-less row is the CONTROL and inverts
	the behind expectation — it must be chased from any bearing at all.

	@param species_name: the SPECIES key to probe
	@param telegraph: `SPOT_TELEGRAPH_TIME`, in seconds

	Same shape as the hunt dispatch probe below: a real body, a real stub quarry in
	group "player", and `_update_chase_state()` called in a loop rather than awaited
	as physics frames. The ceiling is the same one, and it is the right one here —
	this measures a DECISION, and the decision is made entirely inside that
	function.
	"""
	var row: Dictionary = _species_table[species_name]
	var cone: float = float(row.get("view_cone_deg", 360.0))
	var has_cone: bool = cone < 360.0
	var reach: float = float(row["detection_radius"]) * CONE_PROBE_FRACTION

	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)

	var croc: Node = load(CROC_SCENE).instantiate()
	croc.species = species_name       # before add_child, the row's own contract
	root.add_child(croc)
	croc.global_position = Vector3.ZERO
	# Yaw 0 is +Z (`_chase_player` drives velocity off sin/cos of rotation.y), so
	# +Z is dead ahead and -Z is dead behind. Set explicitly rather than assumed:
	# a body freshly out of a scene has whatever yaw the scene authored.
	croc.rotation.y = 0.0
	croc._find_player()

	var dt: float = croc.get_physics_process_delta_time()
	var frames: int = int(telegraph / maxf(dt, 0.0001)) + CONE_PROBE_SLACK

	# ---- BEHIND -------------------------------------------------------------
	stub.global_position = Vector3(0.0, 0.0, -reach)
	for _i in range(frames):
		croc._update_chase_state()
	if has_cone and croc.is_chasing:
		_fail("a %s with a %.0f degree cone chased a quarry standing %.2f m"
				% [species_name, cone, reach] + " DIRECTLY BEHIND it (its detection"
				+ " radius is %.1f m) — the cone is not being applied to the"
				% float(row["detection_radius"]) + " acquisition decision, so"
				+ " sneaking up behind one does nothing")
	if not has_cone and not croc.is_chasing:
		_fail("a %s — which declares no view_cone_deg — did NOT chase a quarry"
				% species_name + " %.2f m directly behind it. The cone code has"
				% reach + " blinded a row that never asked for one, which is every"
				+ " predator in the field")

	# ---- AHEAD: the beat, at both ends --------------------------------------
	stub.global_position = Vector3(0.0, 0.0, reach)
	croc._update_chase_state()
	if has_cone and croc.is_chasing:
		_fail("a %s committed on the very frame its quarry entered the cone —"
				% species_name + " SPOT_TELEGRAPH_TIME is declared as %.2f s but"
				% telegraph + " nothing is counting it, so a coned predator is"
				+ " simply a harsher one and there is no stealth read at all")
	for _i in range(frames):
		croc._update_chase_state()
	if not croc.is_chasing:
		_fail("a %s never chased a quarry standing %.2f m DEAD AHEAD, %.2f s after"
				% [species_name, reach, float(frames) * dt] + " it entered the"
				+ " %.0f degree cone — the beat never expires, which is a predator"
				% cone + " that cannot engage at all")
	# The `?` is the player-facing half of the beat and is the only thing that
	# makes it readable; a silent 0.6 s pause is indistinguishable from lag.
	if has_cone and croc.get("_spot_label") == null:
		_fail("a %s ran its whole telegraph without ever building the `?` label —"
				% species_name + " the beat happens and the player cannot see it")

	croc.free()
	stub.free()


# ============================================================================
# CROWD CONFUSION — Budapest crowd false-arrest (bead godot-test1-8gw.16)
# ============================================================================

func _check_crowd_confusion(croc_ai: GDScript) -> void:
	"""
	Every SPECIES row declaring `crowd_confusion_chance` is probed:

	  * Outside Budapest the acquisition is never refused (negative control).
	  * Inside with a citizen in range, over N trials the refusal rate lands
	    near the row's chance; every stall in [2,10] s; no chase flag while
	    stalled and errand survives N extra frames with quarry still in range;
	    state clears and the hunter resumes; scent nose not confused.
	  * A key-less row (crocodile) is unchanged as the control.

	Runs on a live body driven through the shipped _update_chase_state /
	investigate_point seam — not a copy of it. The pure helper _should_confuse
	is exercised only as a unit test of its own truth table; the city and crowd
	gates are measured on the body, because the shipped call site hardcodes both
	booleans to true and the helper alone cannot see the early returns.
	"""
	var confused: Array[String] = []
	for name_v: Variant in _species_table:
		if _species_table[name_v].has("crowd_confusion_chance"):
			confused.append(str(name_v))
	if confused.is_empty():
		print("crowd confusion: no SPECIES row declares the key — probe vacuous")
	else:
		print("crowd confusion: probing %s" % str(confused))
	for species_name: String in confused:
		var row: Dictionary = _species_table[species_name]
		var chance: float = float(row.get("crowd_confusion_chance", 0.0))
		if chance < 0.0 or chance > 0.7 + 1e-6:
			_fail("SPECIES['%s'].crowd_confusion_chance is %.3f — outside [0,0.7], the owner's ceiling" % [species_name, chance])
		# Helper truth table — does not prove the city/crowd gates, which are
		# early returns in _try_crowd_confusion and are measured on the body below.
		if not croc_ai._should_confuse(chance, true, true, chance * 0.5):
			_fail("helper _should_confuse: SPECIES['%s'] with chance %.2f did not confuse on roll %.3f < chance" % [species_name, chance, chance * 0.5])
		if croc_ai._should_confuse(chance, true, true, minf(chance + 0.01, 1.0)):
			_fail("helper _should_confuse: SPECIES['%s'] confused on roll above its chance" % species_name)
	# ---- LIVE BODY: outside Budapest never refused (real city gate) ----
	for species_name: String in confused:
		_probe_crowd_outside(species_name)
	# ---- LIVE BODY: inside with citizen — rate near chance, stall in [2,10], no chase, persists N frames, clears ----
	for species_name: String in confused:
		_probe_crowd_inside(species_name)
	# ---- CONTROL: crocodile is unchanged even inside with citizen ----
	_probe_crowd_crocodile_inside()
	# Also exercise the outside control for crocodile explicitly (was previously dead via if chance>0).
	_probe_crowd_outside("crocodile")
	Sentinel.done("crowd_confusion")


func _probe_crowd_outside(species_name: String) -> void:
	# A stub quarry in group "player" at a position OUTSIDE Budapest.
	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	stub.global_position = Vector3(0.0, 0.0, 0.0)
	# A crowd that DOES have a citizen nearby — but we are outside the city.
	var crowd := Node3D.new()
	var crowd_script := GDScript.new()
	crowd_script.source_code = "extends Node3D\nfunc nearest_citizen_to(pos: Vector3, max_dist: float = 40.0) -> Variant:\n\treturn pos + Vector3(5, 0, 0)\n"
	crowd_script.reload()
	crowd.set_script(crowd_script)
	crowd.add_to_group("crowd")
	root.add_child(crowd)
	var croc: Node = load(CROC_SCENE).instantiate()
	croc.species = species_name
	root.add_child(croc)
	croc.global_position = Vector3(0.0, 0.0, 0.0)
	croc.rotation.y = 0.0
	croc._find_player()
	# Ensure grounded for scent check.
	croc._update_chase_state()
	# Place quarry inside detection.
	stub.global_position = croc.global_position + Vector3(5, 0, 0)
	for _i in range(5):
		croc._update_chase_state()
	if bool(croc.get("is_investigating")):
		_fail("SPECIES['%s'] confused OUTSIDE Budapest — city gate not applied on a live body" % species_name)
	if not bool(croc.get("is_chasing")) and not bool(croc.get("is_investigating")):
		# Outside city it must chase, not stall and not idle — detection failed.
		_fail("SPECIES['%s'] did not chase outside Budapest with quarry 5 m away" % species_name)
	croc.free()
	stub.free()
	crowd.free()


func _probe_crowd_inside(species_name: String) -> void:
	var row: Dictionary = _species_table[species_name]
	var chance: float = float(row.get("crowd_confusion_chance", 0.0))
	if chance <= 0.0:
		return
	# Pick a point INSIDE Budapest — 2000,0,0 is inside the plan's rect.
	var city_pos := Vector3(2000.0, 0.0, 0.0)
	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	stub.global_position = city_pos + Vector3(5, 0, 0)
	var crowd := Node3D.new()
	var crowd_script := GDScript.new()
	crowd_script.source_code = "extends Node3D\nfunc nearest_citizen_to(pos: Vector3, max_dist: float = 40.0) -> Variant:\n\treturn pos + Vector3(1, 0, 0)\n"
	crowd_script.reload()
	crowd.set_script(crowd_script)
	crowd.add_to_group("crowd")
	root.add_child(crowd)
	var trials: int = 600
	var refuses: int = 0
	var seen_bad_stall := false
	var seen_chase_while_stalled := false
	var seen_tracking_while_stalled := false
	var seen_spot_not_cleared := false
	var seen_not_persisted := false
	var seen_no_clear := false
	for _t in range(trials):
		var croc: Node = load(CROC_SCENE).instantiate()
		croc.species = species_name
		root.add_child(croc)
		croc.global_position = city_pos
		croc.rotation.y = 0.0
		croc._find_player()
		# Pre-arm tracking and telegraph so the clear on confusion is not vacuous (findings #4/#5).
		croc.set("is_tracking", true)
		croc.set("spot_clock", 0.8)
		croc._update_chase_state()
		if bool(croc.get("is_investigating")):
			refuses += 1
			var hold: float = float(croc.get("_investigate_hold"))
			if hold < 1.95 or hold > 10.01:
				seen_bad_stall = true
			if bool(croc.get("is_chasing")):
				seen_chase_while_stalled = true
			if bool(croc.get("is_tracking")):
				seen_tracking_while_stalled = true
			if float(croc.get("spot_clock")) > 0.01:
				# spot_clock must have been zeroed on the refusal (finding #4).
				seen_spot_not_cleared = true
			# Errand must SURVIVE N extra frames with quarry still in range (finding #1).
			var persisted := true
			for _f in range(5):
				croc._update_chase_state()
				if not bool(croc.get("is_investigating")) or bool(croc.get("is_chasing")):
					persisted = false
					break
			if not persisted:
				seen_not_persisted = true
			# State must clear after the hold expires and hunter resumes.
			# Walk the errand to completion via _investigate_move, then verify it
			# can chase again. Also assert cooldown still >0 at clear (finding #3).
			var cleared_cd: float = -1.0
			for _s in range(int(hold / 0.016) + 120):
				croc._investigate_move(0.016)
				croc._tick_crowd_cooldown(0.016)
				if not bool(croc.get("is_investigating")):
					cleared_cd = float(croc.get("_crowd_confusion_cooldown"))
					break
			if bool(croc.get("is_investigating")):
				seen_no_clear = true
			else:
				if cleared_cd <= 0.01:
					_fail("SPECIES['%s'] cooldown was 0 at errand clear — guard expired during walk+hold and errands will chain (finding #3)" % species_name)
				# After clearing, with cooldown expired it must be able to chase again.
				croc.set("_crowd_confusion_cooldown", 0.0)
				croc.set("is_chasing", false)
				croc._update_chase_state()
				# We do not fail if this rolls a second confusion — that is rate;
				# we just ensure the errand itself cleared.
				pass
		croc.free()
	var rate: float = float(refuses) / float(trials)
	var lo: float = chance - 0.12
	var hi: float = chance + 0.12
	if rate < lo or rate > hi:
		_fail("SPECIES['%s'] crowd refusal rate %.2f outside [%.2f, %.2f] over %d trials inside Budapest (chance %.2f)" % [species_name, rate, lo, hi, trials, chance])
	if seen_bad_stall:
		_fail("SPECIES['%s'] produced a stall outside [2,10] s" % species_name)
	if seen_chase_while_stalled:
		_fail("SPECIES['%s'] lit is_chasing while stalled on a citizen" % species_name)
	if seen_tracking_while_stalled:
		_fail("SPECIES['%s'] kept is_tracking while stalled — scent nose is supposed to be untouched and cleared on confusion" % species_name)
	if seen_spot_not_cleared:
		_fail("SPECIES['%s'] spot_clock not zeroed on confusion — coned row would freeze with ? (finding #4)" % species_name)
	if seen_not_persisted:
		_fail("SPECIES['%s'] errand did not survive 5 extra frames with quarry still in range — the stall is destroyed ~16 ms after it starts (finding #1)" % species_name)
	if seen_no_clear:
		_fail("SPECIES['%s'] is_investigating never cleared after hold expiry — hunter never resumes" % species_name)
	# --- _track_scent must not hijack the crowd errand (finding #2) ---
	# While _crowd_errand the hunter must keep walking to the citizen, not to a scent crumb.
	# The hang needs quarry OUTSIDE detection (25) but INSIDE scent_radius (150).
	if not seen_no_clear and refuses > 0:
		var track_croc: Node = load(CROC_SCENE).instantiate()
		track_croc.species = species_name
		root.add_child(track_croc)
		track_croc.global_position = city_pos
		track_croc.rotation.y = 0.0
		track_croc._find_player()
		var got_track_confusion := false
		for _a2 in range(80):
			track_croc.set("_crowd_confusion_cooldown", 0.0)
			track_croc.set("is_investigating", false)
			track_croc.set("_crowd_errand", false)
			track_croc.set("is_chasing", false)
			track_croc.set("is_tracking", false)
			track_croc.set("_investigate_hold", 0.0)
			track_croc._update_chase_state()
			if bool(track_croc.get("is_investigating")) and bool(track_croc.get("_crowd_errand")):
				got_track_confusion = true
				break
			track_croc.set("is_chasing", false)
			track_croc._choose_new_direction()
		if got_track_confusion:
			# Publish a scent crumb that would make _track_scent set is_tracking true
			# if the early-return were missing. Use a lod_manager stub.
			var lod_stub := Node3D.new()
			var lod_script := GDScript.new()
			lod_script.source_code = "extends Node3D\nfunc scent_point(pos: Vector3, radius: float) -> Variant:\n\treturn pos + Vector3(30, 0, 0)\n"
			lod_script.reload()
			lod_stub.set_script(lod_script)
			lod_stub.add_to_group("lod_manager")
			root.add_child(lod_stub)
			# Move quarry outside detection (60 m) but inside scent (150).
			stub.global_position = city_pos + Vector3(60, 0, 0)
			var hold_before: float = float(track_croc.get("_investigate_hold"))
			track_croc._update_chase_state()
			if bool(track_croc.get("is_tracking")):
				_fail("SPECIES['%s'] set is_tracking while _crowd_errand — _track_scent early-return missing (finding #2)" % species_name)
			# Hold must still decrement via _investigate_move, not via _track_move.
			track_croc._investigate_move(0.016)
			var hold_after: float = float(track_croc.get("_investigate_hold"))
			if hold_after >= hold_before - 0.001:
				_fail("SPECIES['%s'] hold did not tick while _crowd_errand with quarry at 60 m — movement branch was hijacked by _track_move (finding #2)" % species_name)
			lod_stub.free()
		else:
			_fail("SPECIES['%s'] produced 0 track-test confusions in 80 inside-city trials — cannot guard _track_scent" % species_name)
		track_croc.free()
		# Restore stub quarry for the cooldown guard below.
		stub.global_position = city_pos + Vector3(5, 0, 0)
	# Cooldown re-roll guard: a live confused body that we keep calling
	# _update_chase_state on must keep refusing while is_investigating, and
	# after we artificially end the errand but keep the cooldown, it must chase
	# not re-confuse.
	var croc2: Node = load(CROC_SCENE).instantiate()
	croc2.species = species_name
	root.add_child(croc2)
	croc2.global_position = city_pos
	croc2.rotation.y = 0.0
	croc2._find_player()
	var got_confusion := false
	for _a in range(80):
		croc2.set("_crowd_confusion_cooldown", 0.0)
		croc2.set("is_investigating", false)
		croc2.set("is_chasing", false)
		croc2.set("_investigate_hold", 0.0)
		croc2.set("is_tracking", false)
		croc2._update_chase_state()
		if bool(croc2.get("is_investigating")):
			got_confusion = true
			break
		croc2.set("is_chasing", false)
		croc2._choose_new_direction()
	if got_confusion:
		# While still investigating, next frame must still refuse (persist).
		var still_refusing := true
		for _b in range(4):
			croc2._update_chase_state()
			if not bool(croc2.get("is_investigating")) or bool(croc2.get("is_chasing")):
				still_refusing = false
				break
		if not still_refusing:
			_fail("SPECIES['%s'] did not persist refusal while is_investigating — errand killed on next frame" % species_name)
		# Now end the errand naturally and keep the cooldown: must NOT re-confuse.
		# Use _end_investigation to clear is_investigating but leave cooldown.
		croc2.call("_end_investigation")
		# cooldown is still >0 from the confusion; next edge must chase, not confuse.
		var re_confused := false
		for _b in range(6):
			croc2.set("is_chasing", false)
			croc2._update_chase_state()
			if bool(croc2.get("is_investigating")):
				re_confused = true
				break
		if re_confused:
			_fail("SPECIES['%s'] re-confused immediately after a just-finished errand — per-body re-roll guard not applied" % species_name)
	else:
		# 80 trials with 0.7 chance should almost never fail to get one confusion.
		_fail("SPECIES['%s'] produced 0 confusions in 80 inside-city trials — chance %.2f not being honoured" % [species_name, chance])
	croc2.free()
	stub.free()
	crowd.free()
	print("crowd inside %s: %d/%d refuses (rate %.2f), stall/persist/clear/re-roll checked" % [species_name, refuses, trials, rate])


func _probe_crowd_crocodile_inside() -> void:
	# Crocodile inside Budapest with a citizen nearby must still never confuse.
	var city_pos := Vector3(2000.0, 0.0, 0.0)
	var stub_script := GDScript.new()
	stub_script.source_code = HUNT_STUB_SOURCE
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	stub.add_to_group("player")
	root.add_child(stub)
	stub.global_position = city_pos + Vector3(5, 0, 0)
	var crowd := Node3D.new()
	var crowd_script := GDScript.new()
	crowd_script.source_code = "extends Node3D\nfunc nearest_citizen_to(pos: Vector3, max_dist: float = 40.0) -> Variant:\n\treturn pos + Vector3(3, 0, 0)\n"
	crowd_script.reload()
	crowd.set_script(crowd_script)
	crowd.add_to_group("crowd")
	root.add_child(crowd)
	var croc: Node = load(CROC_SCENE).instantiate()
	croc.species = "crocodile"
	root.add_child(croc)
	croc.global_position = city_pos
	croc.rotation.y = 0.0
	croc._find_player()
	for _i in range(8):
		croc._update_chase_state()
		if bool(croc.get("is_investigating")):
			_fail("crocodile (no crowd_confusion_chance) was confused inside Budapest with a citizen nearby")
			break
		croc.set("is_chasing", false)
	croc.free()
	stub.free()
	crowd.free()
