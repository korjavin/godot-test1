extends SceneTree
## Headless self-check: NO CROCODILE MAY SPAWN INSIDE SOLID STONE — and, since
## the biome-predator epic, EVERY PREDATOR IS THE SPECIES ITS BIOME ASKED FOR.
##
## The second subject lives here rather than in a file of its own because it is
## the same measurement on the same sweep: the spawner that must not put a body
## in stone is the spawner that decides what that body IS, and the failure has
## the same shape — nothing errors, nothing logs, you just get the wrong animal.
##
##   godot --headless --path . --script res://scripts/croc_spawn_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as prop_selfcheck.gd / landmark_selfcheck.gd, and it exists for the
## same reason those do: every way of breaking this looks like ordinary scenery
## from the outside. A crocodile wedged in a block is not an error anywhere — it
## is a body the physics server shoves out sideways, or one that stands in a wall
## biting a player who cannot reach it, in a world where nothing logs anything.
##
## THE THREE SPAWNERS AND WHAT EACH RELIES ON, because they are not alike:
##
##   * spawn_crocodiles_in_chunk (ground) rejects candidates within
##     `ob.radius + min_object_clearance` of every footprint in `obstacles`.
##   * spawn_bosses_in_chunk walks BOSS_PLACE_TRIES candidates against the same
##     list with a per-scale clearance, because a 6x boss needs ~4.2 m.
##   * spawn_platform_crocodiles gets NO obstacles at all. It is handed walkable
##     tops and trusts their declared geometry — which is exactly where this
##     check earns its keep, and where the bug it was written for lived: a wall
##     ridge declared its surface at the SINGLE-block height while 30% of its
##     sections are DOUBLED, so a guard dropped in at surface + spawn height
##     landed inside a hump whenever the random angle picked one.
##
## HOUSE RULE, followed throughout: every check is an EFFECT measurement against
## the chunk's REAL collision shapes — the CollisionShape3D children of its
## BlockCollision body — never a read-back of the declared footprints, because
## the declared footprints are precisely what a bug here gets wrong. Every check
## has a negative control beside it, since "no crocodile was in stone" is also
## true of a sweep that generated no crocodiles, no stone, or no doubled wall.
##
## Cost: the whole file is ~1.3 s for 2 seeds x 289 chunks. Don't grow it into a
## suite; if a fourth spawner appears, it belongs in check 1's sweep, not in a
## new file.
##
## THE ONE THING IT PRINTS THAT IS NOT ITS OWN: a handful of "RID allocations …
## were leaked at exit" / "resources still in use at exit" lines AFTER the
## verdict. Those are the engine reporting the STATIC shared caches this project
## deliberately keeps — endless_terrain's shared unit box and ground meshes, the
## artifact glow and camp ember materials, ToonShading's styled-material cache,
## and the two PackedScenes loaded below — none of which is owned by, or
## releasable from, a check. They are the same lines any harness that loads the
## crocodile scene prints, they appear after the exit code is decided, and they
## are NOT a failure. Everything else must stay silent: a run that prints a
## SCRIPT ERROR beside SELFCHECK OK is measuring a world it did not build (see
## _make_chunk_parent and _boot for the two traps that caused exactly that).

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const CROC_AI_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"
const PLAYER_SCRIPT: String = "res://scripts/player_controller.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

## Field side in chunks. 17 x 17 = 289, the size every measurement in CLAUDE.md's
## terrain sections is quoted at, so a number printed here is comparable to them.
const FIELD: int = 17

## Two run seeds, not one. The biome offset is derived from run_seed, so a single
## seed can land most of a field in desert (few structures) and miss the walls
## entirely — check 3 is the control that says so out loud if it happens.
const RUN_SEEDS: Array[int] = [12345, 20260826]

## Angles walked around each platform's spawn ellipse in check 2. The spawner
## draws ONE angle per platform, so the live sweep in check 1 samples a single
## point per structure; 16 covers the arc a different run_seed would have picked.
const PLATFORM_ANGLE_SAMPLES: int = 16

## Float slack. A body resting exactly on a face is correct, not a failure.
const EPSILON: float = 0.001

var _failures: Array[String] = []

## piglet_crocodile_ai.gd's SPECIES table and endless_terrain.gd's BIOME_SPECIES
## map, read once in _run() through get_script_constant_map() — see the note there
## on why a `const` cannot be read as a property.
var _species_table: Dictionary = {}
var _biome_species: Dictionary = {}

## The two ends of the speed lattice, read off player_controller.gd and
## piglet_crocodile_ai.gd rather than restated — see the note in _run().
var _walk_speed: float = 0.0
var _max_chase_speed: float = 0.0


func _initialize() -> void:
	_boot()


func _boot() -> void:
	"""
	Wait ONE frame before generating anything.

	A node added to `root` from inside _initialize() is not `is_inside_tree()`
	until the first frame — the same trap best_run_e2e.gd is written around (there
	it makes HTTPRequest.request() answer ERR_UNCONFIGURED). Here it would make
	every chunk parent _make_chunk_parent() creates a detached node in disguise,
	so `treasure_chest.setup()` would still get a null tree and a zero global
	transform, and the check would go on printing engine errors beside its own OK.
	"""
	await process_frame
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	# get_script_constant_map() is how a `const` is read from outside: constants
	# are not properties, so terrain.get("PLATFORM_SPAWN_HEIGHT") answers null and
	# a check written that way would measure against 0.0 and pass vacuously.
	var consts: Dictionary = terrain_script.get_script_constant_map()
	if not consts.has("PLATFORM_SPAWN_HEIGHT") or not consts.has("PLATFORM_SPAWN_EDGE_INSET"):
		_fail("endless_terrain.gd has no PLATFORM_SPAWN_HEIGHT / PLATFORM_SPAWN_EDGE_INSET —"
				+ " the patrol drop-in constants this check measures against are gone")
		_report()
		return

	var spawn_height: float = float(consts["PLATFORM_SPAWN_HEIGHT"])
	var edge_inset: float = float(consts["PLATFORM_SPAWN_EDGE_INSET"])

	# The lattice's two ends are READ, never restated here: WALK_SPEED off the
	# player and MAX_CHASE_SPEED off the AI, so retuning either moves this check
	# with it instead of leaving it asserting a number nothing uses any more.
	var croc_ai: GDScript = load(CROC_AI_SCRIPT)
	var croc_consts: Dictionary = croc_ai.get_script_constant_map()
	_species_table = croc_consts.get("SPECIES", {})
	_max_chase_speed = float(croc_consts.get("MAX_CHASE_SPEED", 0.0))
	_walk_speed = float(load(PLAYER_SCRIPT).get_script_constant_map().get("WALK_SPEED", 0.0))
	_biome_species = consts.get("BIOME_SPECIES", {})
	_check_species_table()
	_check_pack_surround(croc_ai)
	_check_ambush_trip_wire()
	_check_charge_dodge(croc_ai)

	for run_seed: int in RUN_SEEDS:
		_sweep(terrain_script, run_seed, spawn_height, edge_inset)

	_report()


# ============================================================================
# CHECK 4 (table half) — every SPECIES row is complete, legal and reachable
# ============================================================================

func _check_species_table() -> void:
	"""
	Read the two tables and prove a NEW ROW cannot ship broken.

	This is the cheap half of check 4 — no world, no chunks, pure data — and it
	exists because the biome-predator epic adds one species per bead, each of
	them a hand-copied dictionary of ~30 keys. The three ways that goes wrong are
	all silent from the outside, which is this file's whole subject:

	  * A MISSING KEY is a crash in a per-frame path (`spec["sway_yaw"]` in
	    _animate_body), on the first frame the first one of them is visible, and
	    only in the biome that species lives in.
	  * A chase_speed OVER the lattice quietly breaks the promise the whole game
	    is balanced on — walking is caught, RUNNING ESCAPES. MAX_CHASE_SPEED
	    clamps it at runtime so nothing ever looks wrong; the row is just a lie.
	  * A dispatch entry naming a species that isn't in the table, or pointing at
	    a scene that doesn't load, degrades to a crocodile — which reads as "the
	    new predator isn't finished yet" rather than as a bug.

	The key set is taken from the crocodile row rather than hardcoded here, so it
	tracks the AI: add a key to the table and every row must grow it, delete one
	and this stops demanding it. That is deliberately stricter than the engine —
	an unused key on one row is not a crash — and it is the point: 'the crocodile
	has it and you don't' is exactly the state that crashes later.
	"""
	if _species_table.is_empty():
		_fail("piglet_crocodile_ai.gd exposes no SPECIES table — the species dispatch"
				+ " this check measures has nothing to dispatch over")
		return
	if not _species_table.has("crocodile"):
		_fail("SPECIES has no 'crocodile' row — it is the fallback every unknown"
				+ " species name and every scene-less biome resolves to")
		return

	var required: Array = _species_table["crocodile"].keys()
	for name_v: Variant in _species_table:
		var species_name: String = String(name_v)
		var row: Dictionary = _species_table[species_name]
		for key_v: Variant in required:
			if not row.has(key_v):
				_fail("SPECIES['%s'] is missing '%s', which the crocodile row has —"
						% [species_name, key_v]
						+ " a per-frame path reads it and will crash on the first"
						+ " frame one of these is on screen")
		# The lattice, stated in CLAUDE.md and in the SPECIES doc block: walking
		# (5.0) must be caught, and the slowest run (9.0) must escape. Every row
		# owes both ends; MAX_CHASE_SPEED is the ceiling and no row may raise it.
		if row.has("chase_speed"):
			var chase: float = float(row["chase_speed"])
			if chase <= _walk_speed:
				_fail("SPECIES['%s'].chase_speed %.2f is at or below %.2f —"
						% [species_name, chase, _walk_speed]
						+ " a player could stroll away from it")
			if chase > _max_chase_speed:
				_fail("SPECIES['%s'].chase_speed %.2f exceeds %.2f —"
						% [species_name, chase, _max_chase_speed]
						+ " the clamp hides it at runtime, so the row is simply wrong")

	# The dispatch map: names must resolve, scenes must load.
	for biome_v: Variant in _biome_species:
		var entry: Dictionary = _biome_species[biome_v]
		var species_name: String = String(entry.get("species", ""))
		if not _species_table.has(species_name):
			_fail("BIOME_SPECIES[%s] dispatches to '%s', which is not a SPECIES row —"
					% [biome_v, species_name]
					+ " every crocodile in that biome would silently fall back")
		var scene_path: String = String(entry.get("scene", ""))
		if not ResourceLoader.exists(scene_path) or load(scene_path) == null:
			_fail("BIOME_SPECIES[%s] points at '%s', which does not load"
					% [biome_v, scene_path])

	# The negative control for this half: a table with one row and an empty
	# dispatch map passes every loop above without measuring anything.
	if _species_table.size() < 2 or _biome_species.is_empty():
		_fail("only %d SPECIES row(s) and %d dispatch entries — checks over the"
				% [_species_table.size(), _biome_species.size()]
				+ " species table ran against a world with one predator in it")


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
	var wolf_species := ""
	for name_v: Variant in _species_table:
		if String(_species_table[name_v].get("behavior", "")) == "pack":
			wolf_species = String(name_v)
			break
	if wolf_species == "":
		_fail("no SPECIES row has behavior 'pack' — the pack steering this check"
				+ " measures is not reachable from any species")
		return

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
			var point: Vector3 = croc_ai.pack_steer_point(quarry, from, slot, pack_size, flank)
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
						target = croc_ai.pack_steer_point(
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
	var ambush_species := ""
	for name_v: Variant in _species_table:
		if String(_species_table[name_v].get("behavior", "")) == "ambush":
			ambush_species = String(name_v)
			break
	if ambush_species == "":
		_fail("no SPECIES row has behavior 'ambush' — the burrow-and-strike this"
				+ " check measures is not reachable from any species")
		return

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
	var charge_species := ""
	for name_v: Variant in _species_table:
		if String(_species_table[name_v].get("behavior", "")) == "charge":
			charge_species = String(name_v)
			break
	if charge_species == "":
		_fail("no SPECIES row has behavior 'charge' — the committed charge this"
				+ " check measures is not reachable from any species")
		return

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
			target = croc_ai.charge_steer_point(quarry, pos, lock, commit)
		var to_target := target - pos
		to_target.y = 0.0
		if to_target.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(to_target.x, to_target.z), CHARGE_PROBE_DT * turn)
		pos += Vector3(sin(yaw), 0.0, cos(yaw)) * chase * CHARGE_PROBE_DT
	return closest


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


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


# ============================================================================
# THE SWEEP — one whole field, generated exactly the way create_chunk does
# ============================================================================

func _sweep(terrain_script: GDScript, run_seed: int, spawn_height: float, edge_inset: float) -> void:
	"""
	Generate a FIELD x FIELD chunk field and measure every crocodile against the
	solid geometry around it.

	The terrain node is DETACHED (never added to the tree), the same way
	prop_selfcheck.gd and landmark_selfcheck.gd drive it: _ready() rolls a random
	run seed, awaits a frame and starts streaming chunks around the player, none
	of which this check wants. set_run_seed() is the public seam that makes the
	field reproducible (it is also what new_run() and the multiplayer forced seed
	go through, so it cannot rot), and the two scenes are assigned by hand because
	_ready() is what normally loads them.

	TWO PASSES, and the split is load-bearing: a block near a chunk edge reaches
	into the NEIGHBOURING chunk, while `obstacles` only ever describes the chunk
	being generated. So every chunk's geometry is built first and each crocodile
	is then measured against its own chunk AND its eight neighbours, in world
	space. A single-pass version passes while a crocodile stands in the corner of
	the wall next door.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)

	var chunk_solids := {}      # Vector2i -> Array of { inv, half } in WORLD space
	var chunk_obstacles := {}   # Vector2i -> the chunk's footprint list
	var chunk_platforms := {}   # Vector2i -> the chunk's walkable tops
	var solid_count := 0
	var half_field := FIELD / 2

	# ---- pass 1: build the geometry -----------------------------------------
	for cx in range(-half_field, half_field + 1):
		for cz in range(-half_field, half_field + 1):
			var chunk_pos := Vector2i(cx, cz)
			var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
			var parent := _make_chunk_parent(origin)
			var obstacles: Array = []
			var platforms: Array = []
			var batch: Array = []
			var body := StaticBody3D.new()

			# Same call ORDER as create_chunk, because the later spawners judge
			# their candidates against the footprints the earlier ones appended.
			obstacles = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
			terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
			terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)

			var solids: Array = []
			for child in body.get_children():
				var shape_node := child as CollisionShape3D
				var box := shape_node.shape as BoxShape3D
				# The shape carries the block's chunk-local transform (create_box
				# assigns it whole); lift it to world so neighbours are comparable.
				var world := Transform3D(shape_node.transform.basis,
						shape_node.transform.origin + origin)
				solids.append({ "inv": world.affine_inverse(), "half": box.size * 0.5 })
			solid_count += solids.size()

			chunk_solids[chunk_pos] = solids
			chunk_obstacles[chunk_pos] = obstacles
			chunk_platforms[chunk_pos] = platforms
			parent.free()
			body.free()

	# ---- pass 2: spawn the crocodiles and measure ---------------------------
	var counts := { "ground": 0, "platform": 0, "boss": 0 }
	var worst_depth := 0.0
	var worst_desc := ""
	var in_stone := 0
	# Check 4's live half — see the block inside the loop below.
	var species_mismatches := 0
	var species_worst := ""
	var species_seen := {}

	for cx in range(-half_field, half_field + 1):
		for cz in range(-half_field, half_field + 1):
			var chunk_pos := Vector2i(cx, cz)
			var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
			var parent := _make_chunk_parent(origin)
			var obstacles: Array = chunk_obstacles[chunk_pos]

			terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
			terrain.spawn_platform_crocodiles(chunk_pos, parent, chunk_platforms[chunk_pos])
			terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)

			for child in parent.get_children():
				var node_name := String(child.name)
				var kind := ""
				if node_name.begins_with("Crocodile_"):
					kind = "ground"
				elif node_name.begins_with("PatrolCrocodile_"):
					kind = "platform"
				elif node_name.begins_with("BossCrocodile_"):
					kind = "boss"
				else:
					continue
				counts[kind] = int(counts[kind]) + 1

				# CHECK 4 (live half): the biome dispatch actually reached the
				# body. The table itself is checked once, off-world, in
				# _check_species_table; what can only be seen HERE is whether
				# spawn_crocodiles_in_chunk assigned `species` at all, whether it
				# assigned it BEFORE add_child (an assignment after it leaves
				# `spec` resolved to the crocodile row, so the field and the row
				# disagree), and whether it picked the entry the chunk's biome
				# calls for. A boss or a platform guard is deliberately exempt —
				# neither is dispatched on a chunk centre.
				if kind == "ground":
					var want: String = _expected_species(terrain, origin)
					var got: String = String(child.get("species"))
					# `spec` is what the per-frame paths actually read, and it is
					# resolved in _ready(). Comparing ONE number off it against
					# the table is what catches the call-order break: assign
					# `species` after add_child() and the field says "sand_viper"
					# while every speed, feeler and animation stays a crocodile's.
					var spec: Variant = child.get("spec")
					var want_speed: float = float(_species_table[want]["chase_speed"])
					var got_speed: float = (float(spec["chase_speed"])
							if spec is Dictionary and spec.has("chase_speed") else NAN)
					if got != want:
						species_mismatches += 1
						if species_worst == "":
							species_worst = "%s (%s biome) is species '%s', expected '%s'" % [
									node_name, _biome_name(origin, terrain), got, want]
					elif not is_equal_approx(got_speed, want_speed):
						species_mismatches += 1
						if species_worst == "":
							species_worst = ("%s says species '%s' but resolved a spec with"
									+ " chase_speed %s, not the table's %s — `species` was"
									+ " assigned AFTER add_child()") % [
									node_name, got, got_speed, want_speed]
					species_seen[want] = int(species_seen.get(want, 0)) + 1

				var world_pos: Vector3 = (child as Node3D).global_position
				var depth := _depth_in_stone(chunk_solids, chunk_pos, world_pos)
				if depth > EPSILON:
					in_stone += 1
					if depth > worst_depth:
						worst_depth = depth
						worst_desc = "%s crocodile %s at %v" % [kind, node_name, world_pos]

			parent.free()

	if in_stone > 0:
		_fail("seed %d: %d of %d crocodiles spawned INSIDE solid stone (worst %.2f m deep: %s)"
				% [run_seed, in_stone, counts["ground"] + counts["platform"] + counts["boss"],
				   worst_depth, worst_desc])

	if species_mismatches > 0:
		_fail("seed %d: %d of %d ground predators are not the species their chunk's biome"
				% [run_seed, species_mismatches, counts["ground"]]
				+ " dispatches to (first: %s)" % species_worst)
	# The negative control for the live half: a field that is all one biome, or a
	# dispatch that never fired, agrees with itself perfectly and proves nothing.
	if species_seen.size() < 2:
		_fail("seed %d: every ground predator in the field was the same species (%s) —"
				% [run_seed, species_seen.keys()]
				+ " the biome dispatch was never actually exercised")

	# ---- CHECK 2: every angle of every platform, not just the drawn one ------
	# A guard's angle is one RNG draw, so check 1 samples ONE point per structure
	# and a producer that under-declares its `top` over half its length passes on
	# most seeds by luck. This walks the whole spawn ellipse.
	var platforms_seen := 0
	var humped_platforms := 0
	var bad_angles := 0
	var worst_angle_depth := 0.0
	var worst_angle_desc := ""

	for chunk_pos_v: Variant in chunk_platforms:
		var chunk_pos: Vector2i = chunk_pos_v
		var origin: Vector3 = terrain.chunk_to_world(chunk_pos)
		for platform_v: Variant in chunk_platforms[chunk_pos]:
			var platform: Dictionary = platform_v
			if not platform.has("top"):
				_fail("seed %d: a platform in chunk %s declares no `top` — spawn_platform_crocodiles"
						% [run_seed, chunk_pos]
						+ " drops its guard in from that field, so a producer without one"
						+ " cannot say where its tallest stone is")
				continue
			platforms_seen += 1
			var center: Vector3 = platform.center
			var half: Vector2 = platform.half
			var top: float = float(platform.top)
			# The control for the bug this file was written for: a wall whose
			# ridge carries a doubled hump declares a `top` ABOVE the surface it
			# paces. If no platform in the whole field does, checks 1 and 2 never
			# exercised the case at all (see check 3).
			if top > center.y + EPSILON:
				humped_platforms += 1

			for i in PLATFORM_ANGLE_SAMPLES:
				var ang := TAU * float(i) / float(PLATFORM_ANGLE_SAMPLES)
				var probe := origin + Vector3(
						center.x + maxf(0.0, half.x - edge_inset) * cos(ang),
						top + spawn_height,
						center.z + maxf(0.0, half.y - edge_inset) * sin(ang))
				var depth := _depth_in_stone(chunk_solids, chunk_pos, probe)
				if depth > EPSILON:
					bad_angles += 1
					if depth > worst_angle_depth:
						worst_angle_depth = depth
						worst_angle_desc = "chunk %s, angle %.2f rad, probe %v" % [chunk_pos, ang, probe]

	if bad_angles > 0:
		_fail("seed %d: %d platform spawn points (over %d platforms) fall inside solid stone"
				% [run_seed, bad_angles, platforms_seen]
				+ " (worst %.2f m deep: %s) — a platform's `top` is not a true bound"
				% [worst_angle_depth, worst_angle_desc]
				+ " on the stone standing in its own footprint")

	# ---- CHECK 3: the negative controls -------------------------------------
	# Everything above is trivially true of a sweep that produced nothing. Each of
	# these is a thing that must have EXISTED for the measurements to mean anything.
	if counts["ground"] < 1:
		_fail("seed %d: the sweep spawned no ground crocodiles at all — checks 1-2 measured nothing" % run_seed)
	if counts["platform"] < 1:
		_fail("seed %d: the sweep spawned no platform guards — the one spawner with no obstacle"
				% run_seed + " test is exactly what this file exists to measure")
	if solid_count < 1:
		_fail("seed %d: the sweep built no collision shapes — there was no stone to be inside of" % run_seed)
	if humped_platforms < 1:
		_fail("seed %d: no platform in the field declared a `top` above its paced surface, so the"
				% run_seed + " doubled-wall-hump case this check was written for was never exercised")

	# Counts only — the verdict is SELFCHECK OK / the FAIL lines, and a summary
	# that asserted "all clear" here would print it beside its own failures.
	print("seed %d: measured %d ground / %d platform / %d boss crocodiles against %d collision shapes, plus %d angle probes over %d platforms (%d humped)"
			% [run_seed, counts["ground"], counts["platform"], counts["boss"], solid_count,
			   platforms_seen * PLATFORM_ANGLE_SAMPLES, platforms_seen, humped_platforms])
	print("seed %d: ground predators by species %s" % [run_seed, species_seen])


func _expected_species(terrain: Node, chunk_centre: Vector3) -> String:
	"""
	What BIOME_SPECIES says a chunk should spawn — recomputed from the PUBLIC
	biome API, not read back off the spawner.

	@param terrain: The detached terrain node driving this sweep.
	@param chunk_centre: chunk_to_world(chunk_pos) — the exact point the spawner
	                     dispatches on, which is the whole reason this is a
	                     one-liner and not a reimplementation.
	@return: A key of SPECIES; "crocodile" for any biome with no entry.
	"""
	var biome: int = terrain.biome_at(chunk_centre.x, chunk_centre.z)
	if _biome_species.has(biome):
		return String(_biome_species[biome]["species"])
	return "crocodile"


func _biome_name(chunk_centre: Vector3, terrain: Node) -> String:
	"""The chunk's biome as a readable name, for failure messages only."""
	var names: Array = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN", "CITY", "SNOW"]
	var biome: int = terrain.biome_at(chunk_centre.x, chunk_centre.z)
	return names[biome] if biome >= 0 and biome < names.size() else str(biome)


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


func _depth_in_stone(chunk_solids: Dictionary, chunk_pos: Vector2i, world_pos: Vector3) -> float:
	"""
	How deep `world_pos` sits inside the nearest solid box of the 3x3 chunk block
	around `chunk_pos`. 0.0 when it is outside every one of them.

	@param chunk_solids: Vector2i -> Array of { inv: Transform3D, half: Vector3 }
	@param chunk_pos: The chunk to search around (its 8 neighbours included)
	@param world_pos: The point to test, in world space
	@return Penetration depth in metres; 0.0 means clear.

	The neighbours are what make this honest — see the two-pass note in _sweep.
	The point is transformed into each box's own frame rather than compared
	against an axis-aligned bound, because create_box gives a block a yaw (and an
	artifact stone a tilt as well), so a bounding box would report a corner region
	as solid and fail on crocodiles standing in clear air beside a rotated block.
	"""
	var deepest := 0.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var neighbour := chunk_pos + Vector2i(dx, dz)
			if not chunk_solids.has(neighbour):
				continue
			for solid_v: Variant in chunk_solids[neighbour]:
				var solid: Dictionary = solid_v
				var local: Vector3 = solid.inv * world_pos
				var half: Vector3 = solid.half
				# Distance to the nearest face, from the inside. Any axis already
				# outside the box means the point is outside it entirely.
				var gap := minf(half.x - absf(local.x),
						minf(half.y - absf(local.y), half.z - absf(local.z)))
				if gap > deepest:
					deepest = gap
	return deepest
