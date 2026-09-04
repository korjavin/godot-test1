extends SceneTree
## Headless self-check for EVERY ENEMY THE TERRAIN SPAWNS, in every biome. Three
## subjects, one sweep:
##
##   OBSTACLE AVOIDANCE — no enemy of any species may spawn inside solid stone.
##   DETERMINISTIC PLACEMENT — where and what a chunk spawns is a pure function
##     of (chunk coords, run_seed), to the last bit, in any generation order.
##   MULTIPLAYER IDENTITY — every species shares one deterministic node name and
##     one state byte, which is the whole of how a peer recognises a predator.
##
## They live together rather than in three files because they are the same
## measurement on the same field: the spawner that must not put a body in stone
## is the spawner that decides what that body IS and what it is CALLED, and all
## three failures have the same shape — nothing errors, nothing logs, you just
## get the wrong animal, in the wrong place, that the room cannot agree on.
##
## THE COVERAGE IS DRIVEN BY THE TABLES, NOT BY A LIST IN THIS FILE. Adding a
## predator to this game is a `SPECIES` row, a `.tscn` and one `BIOME_SPECIES`
## line (see CLAUDE.md); so every loop below iterates those two tables and the
## `Biome` enum, and nothing here names a species. The consequences are the
## point: an unreachable row fails, an unvisited biome fails, a species the sweep
## never spawned fails, and a `behavior` string with no probe fails by name. The
## SEVENTH predator is covered the day its row lands.
##
##   godot --headless --path . --script res://scripts/enemy_spawn_selfcheck.gd
##
## THE BEHAVIOUR PROBES ARE IN `scripts/enemy_behavior_selfcheck.gd` — one per arm
## (pack, ambush, charge, burst, ranged, hunt, scent, leap, cone, crowd), split out
## by bead `godot-test1-ftn.13` because CI's `selfcheck-shard` globs
## `scripts/*_selfcheck.gd` and shards BY FILE, so a 5,100-line check that is a
## third of the suite's wall clock is a shard nothing can balance. The split is
## mechanical and the two halves stay bound in the direction that matters:
## PROBED_BEHAVIORS below fails, by name, a row whose `behavior` string has no
## probe over there — so a new arm still has to bring a probe with it.
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
##     list with a per-scale clearance, because a 9x boss needs ~6.3 m.
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
## Cost: ~1.2 s for 2 seeds x 289 chunks plus a 49-chunk determinism field. If a
## fourth spawner appears it belongs in the sweep, not in a new file, and a
## seventh species should cost it nothing at all.
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
const MP_SCRIPT: String = "res://scripts/mp_codec.gd"
const LOD_SCRIPT: String = "res://scripts/crocodile_lod_manager.gd"
const TOWER_INTERIOR_SCRIPT: String = "res://scripts/tower_interior.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

## How much room a row's `detection_radius` must leave under the LOD manager's
## SIM_RADIUS (check 4). CLAUDE.md states the invariant — SIM_RADIUS must stay
## WELL ABOVE every species' detection, because anything that can already smell
## the player has to be awake — and "well above" is the part a check has to pick a
## number for. 15 m is the margin the widest row in the table (the hunter's 25,
## which is also BOSS_DETECTION_RADIUS) already leaves under 45, so this asserts
## the status quo rather than inventing headroom nothing has: a new row may match
## the widest one, and may not go past it.
##
## WHY IT MATTERS THAT IT IS A MARGIN AND NOT `<`: a body wakes at SIM_RADIUS and
## sleeps a little outside it, so a row detecting at 44 would spend its life
## flickering between "chasing" and "physics off" at the boundary — legal under a
## bare inequality and completely broken in play.
const DETECTION_SIM_MARGIN: float = 15.0

## Every `behavior` string this file has a probe for. THE COVERAGE GATE: a
## SPECIES row carrying a behaviour that is not in here fails the run by name,
## because the alternative is the failure this whole epic's checks were written
## against — a new arm that ships, reads correctly, does nothing, and is measured
## by nobody. "solo" is in the list and has no probe of its own on purpose: it is
## the code ABOVE the dispatch (see the behaviour `match` in _update_chase_state),
## which the ambush trip-wire's crocodile control drives on every run.
const PROBED_BEHAVIORS: Array[String] = ["solo", "pack", "ambush", "charge", "burst",
		"ranged", "hunt", "leap"]

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

## Side of the field the determinism check regenerates, in chunks. Small on
## purpose — determinism is a property of one chunk's hash stream, so 49 chunks
## across four generations say everything 289 would, at a sixth of the cost.
const DETERMINISM_FIELD: int = 7

## The seed check 9's negative control regenerates the field under. ITS OWN
## CONSTANT, not RUN_SEEDS[1], because shortening RUN_SEEDS is a legitimate thing
## to do while bisecting a failure and an index off the end of it would take the
## whole run down — silently, since a script error before _report() means quit()
## is never reached and the process exits 0 with no verdict at all. That is the
## exact green lie this file's header is written against.
const DETERMINISM_CONTROL_SEED: int = 777

## How many consecutive road-station BOSSES check 11 walks, starting at boss 1.
## A boss owns every BOSS_INTERVAL_STATIONS-th station, so forty of them would
## stretch roughly twelve kilometres of centerline. The sweep's 289-chunk fields
## contain ONE boss each, which is why this check exists as its own walk rather
## than as a branch in there — one body cannot show that a rule keyed on a
## coordinate answers different questions at different coordinates.
##
## SINCE BEAD godot-test1-8gw.3 THIS IS A CEILING, NOT A COUNT. The coin road now
## ENDS at endless_terrain.ROAD_TERMINAL_X (1450 m, just west of Budapest's gate)
## — past it there is no road to guard and spawn_bosses_in_chunk places nothing.
## One road is therefore ~5 bosses long, not forty, and the walk clamps itself per
## seed to what the terminal station allows. Left at forty so the clamp is visible
## as a clamp; raising it alone buys nothing.
const BOSS_DISPATCH_COUNT: int = 40

## The seeds check 11's boss walk runs, and the reason it is its OWN list rather
## than RUN_SEEDS.
##
## REACH NOW COMES FROM SEED COUNT, NOT FROM DISTANCE. Before the road had a
## terminal station, forty bosses on two roads dragged the dispatch across twelve
## kilometres of biome bands and a river or two. A 1450 m road crosses one or two
## bands and almost never a river, so the same coverage has to be bought by
## walking MANY short roads instead of two long ones: every seed re-offsets the
## biome domain, so each one presents its five stations in a different band mix.
##
## Fourteen seeds put ~70 stations on the board — all six bands and three river
## crossings, measured 2026-09-02. The last two are in the list for the RIVER arm
## specifically (they are the only two crossings in seeds 1..40) and the comment
## is here so a future edit does not drop them as duplicates of nothing.
const BOSS_DISPATCH_SEEDS: Array[int] = [
	12345, 20260826, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	19, 39,
]

## Fewest of those bosses — over every seed in BOSS_DISPATCH_SEEDS together — that must
## actually reach the world. It is under the walk's length on purpose: a boss whose
## every candidate is buried in geometry is skipped by design (see
## spawn_bosses_in_chunk's claim rule), so a proportion of misses is correct.
##
## SINCE BEAD godot-test1-9k7 IT IS A PLACEMENT FLOOR, NOT JUST AN ANTI-VACUITY
## GATE, and that is the whole reason it moved. Bosses got 1.5x bigger
## (BOSS_BASE_SCALE 2.5 -> 3.75, BOSS_MAX_SCALE 6 -> 9), and the candidate walk
## rejects a spot within BOSS_FOOTPRINT_RADIUS_PER_SCALE * scale of an obstacle —
## so a size bump SILENTLY DELETES BOSSES from the road. It did: measured over
## this seed list, placement fell from 58 of 70 to 50 of 70 on the two-constant
## commit, and every gate in this check still passed, because "at least one of
## each kind reached the world" is true of a road with a third of its guardians
## missing. The number below is that measurement made into an assertion.
##
## 55 is set just under the 58 this walk places both before the bump and after it
## was paid for (BOSS_LATERAL_MAX 4 -> 9, BOSS_PLACE_TRIES 4 -> 8; a wider sweep
## over 25 seeds and 126 stations reads 105 -> 91 -> 106). The gap is deliberate
## slack for a future prop or landmark legitimately crowding a station or two —
## but a change that costs the road a tenth of its bosses now has to say so here.
const BOSS_DISPATCH_MIN_MEASURED: int = 55

## Fewest distinct biome bands those stations must land in. The dispatch is a
## FUNCTION of the band; asked the same question forty times it could be a
## constant and still pass, which is exactly the vacuous green this file is
## written against.
const BOSS_DISPATCH_MIN_BANDS: int = 3

## HOW TWO GENERATIONS OF THE SAME CHUNK ARE COMPARED: `var_to_bytes` of the
## signature array, i.e. bit for bit, with no formatting step in the middle to
## round anything away. That is the right instrument and a tolerance is not: two
## peers sharing a run_seed do not average their worlds, they either agree or
## they do not, and a placement that drifts in the last ulp is one that will
## eventually round to a visibly different metre. (GDScript's `%` has no `%g`, so
## a 17-digit text form is not available anyway — the bytes are both exact and
## cheaper.)

var _failures: Array[String] = []

## endless_terrain.gd's `Biome` enum, read out of the script's constant map in
## _run(). Read rather than restated so the biome COVERAGE gate below counts the
## bands the world actually has: a seventh biome makes this check demand a
## seventh band in the field, instead of silently never testing it.
var _biomes: Dictionary = {}

## Union across every run seed of the species the sweep actually spawned, and of
## the biomes its chunks actually landed in. The coverage verdict is taken over
## the UNION and not per seed, because a single 289-chunk field legitimately
## misses a band (seed 12345 contains no snow at all) — what may not happen is
## the whole run missing one.
var _species_seen_all: Dictionary = {}
var _biomes_seen_all: Dictionary = {}

## Species whose multiplayer contract (check 10) has already been probed. One
## probe per ROW, not per body: the contract is a property of the script and the
## scene, and 2800 crocodiles a seed would pay for the same answer 2800 times.
var _mp_probed: Dictionary = {}

## mp_codec.gd's CROC_FLAG_* constants, read through get_script_constant_map()
## for the same reason SPECIES is (a `const` is not a property, and MpCodec
## has no instance here). Named through CROC_STATE_BITS rather than restated, so
## a bit that is renamed there fails check 10 by name instead of silently
## comparing against a zero. The codec is where BOTH halves of the flag byte
## live since bead godot-test1-ftn.11 — the packing and the constants together.
var _mp_consts: Dictionary = {}

## piglet_crocodile_ai.gd's SPECIES table and endless_terrain.gd's BIOME_SPECIES
## map, read once in _run() through get_script_constant_map() — see the note there
## on why a `const` cannot be read as a property.
var _species_table: Dictionary = {}
var _biome_species: Dictionary = {}

## endless_terrain.gd's BIOME_BOSS map and BOSS_INTERVAL_STATIONS, read the same
## way. That map is now TOTAL over the Biome enum (check 4 asserts it against the
## enum), so check 11 below is a real per-band dispatch test in every band, and
## the crocodile it still measures comes from the RIVER arm alone.
var _biome_boss: Dictionary = {}
var _boss_interval: int = 0

## The two ends of the speed lattice, read off player_controller.gd and
## piglet_crocodile_ai.gd rather than restated — see the note in _run().
var _walk_speed: float = 0.0
var _max_chase_speed: float = 0.0

## Species dispatched from BIOME_BOSS and from nowhere in BIOME_SPECIES, filled
## in by _check_species_table (which runs before every probe). Two checks need
## the same answer — the lattice's lower bound is waived for these rows, and the
## ranged probe measures a boss-only archer's firing band against the BOSS
## detection radius rather than the row's — so it is derived once, from the
## dispatch maps, and never listed.
var _boss_only: Dictionary = {}

## crocodile_lod_manager.gd's SIM_RADIUS, read the same way. The ceiling every
## row's `detection_radius` sits under — see DETECTION_SIM_MARGIN.
var _sim_radius: float = 0.0

## endless_terrain.gd's HUNTER_SPECIES / HUNTER_SCENE — the THIRD door into the
## world, beside BIOME_SPECIES and BIOME_BOSS. A hunter belongs to no band (the
## corporation hunts everywhere), so it reaches the world through its own spawner
## on its own hash stream instead of through a dispatch map; read here so check
## 4's reachability gate counts that door too. Read, never restated: rename the
## const over there and this reports an unreachable row by name rather than
## quietly going on believing in a species the world stopped spawning.
var _hunter_species: String = ""
var _hunter_scene: PackedScene = null

## tower_interior.gd's GUARD_SPECIES / GUARD_SCENE / `guard_posts_table()` — the
## FOURTH door, and the first that is not in endless_terrain at all. A tower guard
## belongs to no band and no road station: it is parented to the BUILDING and stood
## on a post, so a reachability union over the dispatch maps and the hunter spawner
## alone would report it as a species nothing can spawn. Read, never restated,
## exactly like the hunter's pair.
##
## THE POSTS ARE A FUNCTION, NOT A CONST, since bd godot-test1-dn8 demolished the
## keep: the two hand-authored rows went with it and every post is now derived from
## a `G` character on a `TowerPlans` storey. `guard_posts_table()` is the seam the
## building itself calls, so asking it — rather than a table beside it — is what
## keeps this measuring the population the tower really stands up.
var _guard_species: String = ""
var _guard_scene_path: String = ""
var _guard_scene: PackedScene = null
var _guard_posts: Array = []


## endless_terrain.gd's SPAWN_SAFE_RADIUS — the predator-free bubble around the
## world origin, read rather than restated so a retune moves this check with it.
var _spawn_safe_radius: float = 0.0


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
	var player_consts: Dictionary = load(PLAYER_SCRIPT).get_script_constant_map()
	_walk_speed = float(player_consts.get("WALK_SPEED", 0.0))
	_mp_consts = load(MP_SCRIPT).get_script_constant_map()
	_sim_radius = float(load(LOD_SCRIPT).get_script_constant_map().get("SIM_RADIUS", 0.0))
	if _sim_radius <= 0.0:
		_fail("crocodile_lod_manager.gd has no SIM_RADIUS — the ceiling every row's"
				+ " detection_radius sits under is gone, so check 4's margin test"
				+ " would pass every row against zero")
	_spawn_safe_radius = float(consts.get("SPAWN_SAFE_RADIUS", 0.0))
	if _spawn_safe_radius <= 0.0:
		_fail("endless_terrain.gd has no SPAWN_SAFE_RADIUS — the spawn bubble the"
				+ " sweep measures hunters against would be a zero-radius disc that"
				+ " nothing can be inside of")
	_hunter_species = String(consts.get("HUNTER_SPECIES", ""))
	_hunter_scene = consts.get("HUNTER_SCENE", null) as PackedScene
	# THE FOURTH DOOR, and it is not in endless_terrain at all: the tower's guards
	# are parented to the BUILDING, not to a chunk, so the const pair lives on
	# TowerInterior. Read the same way and for the same reason as the hunter's —
	# never restated here, so the day that spawner is deleted the row it fed goes
	# back to being unreachable and check 4 says so by name.
	var tower_consts: Dictionary = load(TOWER_INTERIOR_SCRIPT).get_script_constant_map()
	_guard_species = String(tower_consts.get("GUARD_SPECIES", ""))
	# The PATH, then the load — TowerInterior deliberately does not `preload` the
	# guard scene (a cold-cache load-order diamond through the crocodile AI; see the
	# note on GUARD_SCENE_PATH), so this check resolves it the same way the tower
	# does rather than reaching for a const that is not allowed to exist.
	_guard_scene_path = String(tower_consts.get("GUARD_SCENE_PATH", ""))
	_guard_scene = (load(_guard_scene_path) as PackedScene) if _guard_scene_path != "" else null
	# The seam, not a table: `guard_posts_table()` walks the storeys' `G` cells, so
	# a plan that stopped drawing one is a post this check stops counting.
	_guard_posts = TowerInterior.guard_posts_table()
	_biome_species = consts.get("BIOME_SPECIES", {})
	_biome_boss = consts.get("BIOME_BOSS", {})
	_boss_interval = int(consts.get("BOSS_INTERVAL_STATIONS", 0))
	if _boss_interval < 1:
		_fail("endless_terrain.gd has no BOSS_INTERVAL_STATIONS — check 11 cannot"
				+ " work out which station a boss owns, so it cannot recompute the"
				+ " point the dispatch keys on")
	# The enum itself, so the coverage gate counts the bands the world HAS.
	_biomes = consts.get("Biome", {})
	if _biomes.is_empty():
		_fail("endless_terrain.gd exposes no `Biome` enum — the biome coverage gate"
				+ " has no list of bands to demand, so a band with no predator in it"
				+ " would go untested rather than reported")
	_check_species_table()
	# THE BEHAVIOUR PROBES ARE NOT HERE. One probe per arm — pack, ambush, charge,
	# burst, ranged, hunt, scent, leap, cone, crowd — lives in
	# `scripts/enemy_behavior_selfcheck.gd`, split out by bead `godot-test1-ftn.13`
	# because CI shards `scripts/*_selfcheck.gd` BY FILE and this one was a third of
	# the suite's wall clock on its own. The two halves are still bound: PROBED_BEHAVIORS
	# above fails, by name, a row whose `behavior` string has no probe over there.
	_check_determinism(terrain_script)
	_check_hunter_stream_independence(terrain_script)
	_check_hunter_field_cap(terrain_script)
	_check_boss_dispatch(terrain_script)
	_check_boss_coin_footprint(terrain_script)

	for run_seed: int in RUN_SEEDS:
		_sweep(terrain_script, run_seed, spawn_height, edge_inset)

	_check_coverage()
	_report()


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


# ============================================================================
# CHECK 4 (table half) — every SPECIES row is complete, legal and reachable
# ============================================================================

func _check_species_table() -> void:
	"""
	Read the two tables and prove a NEW ROW cannot ship broken.

	This is the cheap half of check 4 — no world, no chunks, pure data — and it
	exists because the biome-predator epic adds one species per bead, each of
	them a hand-copied dictionary of ~30 keys. The four ways that goes wrong are
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
	  * A `coin_setback` outside (0.0, 1.0] is the whole stake of a contact,
	    silently: zero is a predator you can walk into for free now that hearts
	    are gone, and over 1.0 is a fraction clampf() quietly rewrites.

	The key set is taken from the crocodile row rather than hardcoded here, so it
	tracks the AI: add a key to the table and every row must grow it, delete one
	and this stops demanding it. That is deliberately stricter than the engine —
	an unused key on one row is not a crash — and it is the point: 'the crocodile
	has it and you don't' is exactly the state that crashes later.
	"""
	if _species_table.is_empty():
		_fail("piglet_crocodile_ai.gd exposes no SPECIES table — the species dispatch"
				+ " this check measures has nothing to dispatch over")
		Sentinel.done("species_table")
		return
	if not _species_table.has("crocodile"):
		_fail("SPECIES has no 'crocodile' row — it is the fallback every unknown"
				+ " species name and every scene-less biome resolves to")
		Sentinel.done("species_table")
		return

	# WHICH ROWS ARE BOSS-ONLY: dispatched from BIOME_BOSS and from nowhere in
	# BIOME_SPECIES. They are the ONE legitimate exception to the lower end of the
	# lattice below, and the set is DERIVED from the two dispatch maps rather than
	# listed here — give a boss row an ordinary BIOME_SPECIES entry and it stops
	# being exempt on the same commit, with no edit in this file.
	var ordinary_species: Dictionary = {}
	for biome_v: Variant in _biome_species:
		ordinary_species[String(_biome_species[biome_v].get("species", ""))] = true
	_boss_only.clear()
	for biome_v: Variant in _biome_boss:
		var boss_species: String = String(_biome_boss[biome_v].get("species", ""))
		if not ordinary_species.has(boss_species):
			_boss_only[boss_species] = true

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
		#
		# THE LOWER BOUND IS ASKED OF ORDINARY PREDATORS ONLY, and the exception is
		# narrow on purpose. "Walking is caught" is the FAIL PRESSURE half of the
		# lattice; the promise the game is balanced on is the other half, "running
		# escapes", and a row slower than a walk keeps that one trivially. A
		# BOSS-ONLY row is allowed to be under it because a boss does not inherit
		# its row's chase speed at all by default (BOSS_CHASE_SPEED, 7.0, which is
		# comfortably over a walk) and because the one row that deliberately opts
		# out of that — the snow titan, an archer whose threat is its bolt and not
		# its feet — must be strollable-away-from or it is not an archer. That is
		# not a hole: the ranged probe below ASSERTS the sub-walk speeds for every
		# "ranged" row, so the exemption is paid for with a stricter check, and the
		# projectile's own fairness contract is measured in projectile_selfcheck.
		if row.has("chase_speed"):
			var chase: float = float(row["chase_speed"])
			if chase <= _walk_speed and not _boss_only.has(species_name):
				_fail("SPECIES['%s'].chase_speed %.2f is at or below %.2f —"
						% [species_name, chase, _walk_speed]
						+ " a player could stroll away from it")
			if chase > _max_chase_speed:
				_fail("SPECIES['%s'].chase_speed %.2f exceeds %.2f —"
						% [species_name, chase, _max_chase_speed]
						+ " the clamp hides it at runtime, so the row is simply wrong")
		# The boss speed opt-out is a SPEED like any other and owes the ceiling:
		# _ready() clamps it, so a row over the top would be a lie the clamp hides
		# — the same failure the chase_speed ceiling above is written against.
		if row.has("boss_chase_speed"):
			var boss_chase: float = float(row["boss_chase_speed"])
			if boss_chase > _max_chase_speed:
				_fail("SPECIES['%s'].boss_chase_speed %.2f exceeds %.2f —"
						% [species_name, boss_chase, _max_chase_speed]
						+ " _ready() clamps it, so the row is simply wrong")
		# THE OTHER GAME-WIDE CEILING, and the one with no runtime clamp behind it
		# to hide a breach: CLAUDE.md's LOD invariant. A body only simulates inside
		# crocodile_lod_manager's SIM_RADIUS, so a row that can smell the player
		# from further out than that is a predator asleep in the middle of its own
		# chase — and it looks like nothing at all, because it wakes and resumes the
		# moment you close. See DETECTION_SIM_MARGIN for why this is a margin.
		if row.has("detection_radius") and _sim_radius > 0.0:
			var detect: float = float(row["detection_radius"])
			if detect + DETECTION_SIM_MARGIN > _sim_radius:
				_fail("SPECIES['%s'].detection_radius %.1f leaves less than %.1f m under"
						% [species_name, detect, DETECTION_SIM_MARGIN]
						+ " crocodile_lod_manager's SIM_RADIUS %.1f — a body that can"
						% _sim_radius + " already smell the player may be slept, so its"
						+ " chase stalls at the boundary and resumes when you close")
		# THE OPTIONAL CONE. Absent is the common case and means a full circle; a
		# row that declares one owes a legal arc. Zero (or negative) is a body that
		# can never see anything, and over 360 is a row saying "wider than
		# everywhere", both of which read at runtime as a predator that behaves
		# oddly rather than as an error. The BEHAVIOUR of a declared cone is
		# measured on a live body in check 8e.
		if row.has("view_cone_deg"):
			var arc: float = float(row["view_cone_deg"])
			if arc <= 0.0 or arc > 360.0:
				_fail("SPECIES['%s'].view_cone_deg is %.1f — an arc has to be inside"
						% [species_name, arc] + " (0, 360]; this one is either a"
						+ " predator that can never acquire a quarry or a claim to"
						+ " see further round than a circle")
		# THE STAKE, and it is REQUIRED of every row rather than optional. Since
		# 2026-08-31 hearts are gone: a contact costs the caught freeze plus this
		# fraction of the run's coins and nothing else, so a row that omitted it
		# would be a predator you can walk into for free. PRESENCE is already
		# covered by the crocodile-derived `required` set above (the crocodile row
		# carries it, so every row owes it) — what only this block can see is
		# whether the value is a legal fraction. Zero is the free-hit row the bead
		# deleted; over 1.0 is a bill bigger than the purse, which clampf() in
		# _coin_setback_of hides at runtime, so the row would simply be a lie.
		#
		# The bound is (0.0, 1.0] and not the tuning range (0.0, 0.35] on purpose:
		# this file measures what CANNOT ship, and a playtest that wants 0.4 is a
		# tuning argument, not a broken row.
		if row.has("coin_setback"):
			var setback: float = float(row["coin_setback"])
			if setback <= 0.0 or setback > 1.0:
				_fail("SPECIES['%s'].coin_setback is %.3f — the bill for losing to a"
						% [species_name, setback] + " predator has to be inside"
						+ " (0.0, 1.0]; zero is a contact that costs nothing at all"
						+ " now that hearts are gone, and over 1.0 is a fraction"
						+ " clampf() silently rewrites")

	# ---- EVERY BEHAVIOUR IN THE TABLE MUST HAVE A PROBE IN THIS FILE --------
	# The gate that makes this check cover the SEVENTH predator without anyone
	# extending a list. Behaviour is the one field that is not data — it selects a
	# `match` arm of real code — so a new value here is new logic, and new logic
	# with no probe is exactly what every bead in this epic had to add one for. A
	# row is free to reuse an existing arm (two do); it is not free to invent an
	# arm nobody measures.
	for name_v: Variant in _species_table:
		var behavior: String = String(_species_table[name_v].get("behavior", ""))
		if behavior == "":
			_fail("SPECIES['%s'] declares no 'behavior' — the dispatch at the end of"
					% name_v + " _update_chase_state has no arm to send it to, so it"
					+ " degrades to solo and its own code is dead")
		elif not PROBED_BEHAVIORS.has(behavior):
			_fail("SPECIES['%s'] has behavior '%s', which no probe in this file"
					% [name_v, behavior] + " measures — add one beside the pack /"
					+ " ambush / charge / burst probes and list it in"
					+ " PROBED_BEHAVIORS, or the arm ships unmeasured")

	# ---- EVERY ROW MUST BE REACHABLE ---------------------------------------
	# A species is only ever instantiated through one of the two dispatch maps —
	# BIOME_SPECIES for a chunk's ordinary predators, BIOME_BOSS for a road
	# station's guardian — with the crocodile as the fallback every entry-less
	# biome takes in either. A row nothing dispatches to is a predator that exists
	# in the source, passes every check above, and has never once been in the
	# world — which is a half-landed bead, not a feature, and the one failure mode
	# a table-driven check can see and a hand-written list cannot.
	#
	# BOTH MAPS ARE UNIONED, and the boss half is not decoration: a boss-only row
	# (the snow titan, the forest dragon) is reachable from BIOME_BOSS and from
	# nowhere else, so a union over BIOME_SPECIES alone would report the first one
	# of them as unreachable on the very day it lands.
	#
	# AND THERE IS A THIRD DOOR, which is not a map: the HUNTER. It belongs to no
	# band — the corporation hunts everywhere — so endless_terrain spawns it from
	# its own function on its own hash stream rather than from a dispatch keyed on
	# a biome, and a union over the two maps alone would report a shipped, working,
	# world-reachable species as one nothing can spawn. It is counted here by
	# reading endless_terrain's own HUNTER_SPECIES const (never by name), so the
	# day that spawner is deleted the row it fed goes back to being unreachable and
	# this says so.
	var dispatched := { "crocodile": true }
	for biome_v: Variant in _biome_species:
		dispatched[String(_biome_species[biome_v].get("species", ""))] = true
	for biome_v: Variant in _biome_boss:
		dispatched[String(_biome_boss[biome_v].get("species", ""))] = true
	if _hunter_species != "":
		dispatched[_hunter_species] = true
		if not _species_table.has(_hunter_species):
			_fail("endless_terrain.HUNTER_SPECIES is '%s', which is not a SPECIES row"
					% _hunter_species + " — every hunter it spawns would silently fall"
					+ " back to a crocodile's numbers")
		if _hunter_scene == null:
			_fail("endless_terrain.HUNTER_SCENE did not resolve to a PackedScene —"
					+ " the hunter spawner has nothing to instantiate")
	# AND A FOURTH, which is not a map and not even in endless_terrain: the TOWER
	# GUARD. It belongs to no band and no road station — it is placed on an
	# authored post inside one building — so, exactly like the hunter above, a
	# union over the maps alone would report a shipped, working, world-reachable
	# species as one nothing can spawn. Counted by reading TowerInterior's own
	# consts, so deleting that spawner puts the row back to unreachable here.
	if _guard_species != "":
		dispatched[_guard_species] = true
		if not _species_table.has(_guard_species):
			_fail("TowerInterior.GUARD_SPECIES is '%s', which is not a SPECIES row"
					% _guard_species + " — every guard the tower stands up would"
					+ " silently fall back to a crocodile's numbers")
		if _guard_scene == null:
			_fail("TowerInterior.GUARD_SCENE_PATH ('%s') did not resolve to a"
					% _guard_scene_path + " PackedScene — the tower has nothing to"
					+ " instantiate its guards from")
		if _guard_posts.is_empty():
			_fail("TowerInterior.guard_posts_table() is empty — the row is in the"
					+ " table and the scene loads, but no guard is ever stood up, so"
					+ " the species is reachable only on paper")
	for name_v: Variant in _species_table:
		if not dispatched.has(String(name_v)):
			_fail("SPECIES['%s'] is in the table but in no BIOME_SPECIES or"
					% name_v + " BIOME_BOSS entry — nothing in the world can ever"
					+ " spawn it")

	# Both dispatch maps, by the same rules: biomes must exist, names must
	# resolve, scenes must load. BIOME_BOSS is BIOME_SPECIES one feature over
	# (same {species, scene} shape, same crocodile fallback, keyed on a road
	# station's centre instead of a chunk's), so it earns the same validation
	# rather than a second copy of it.
	_check_dispatch_map("BIOME_SPECIES", _biome_species)
	_check_dispatch_map("BIOME_BOSS", _biome_boss)

	# ---- BIOME_BOSS IS TOTAL OVER THE Biome ENUM ---------------------------
	# The one place the two dispatch maps DIFFER in what is demanded of them, and
	# it is a difference of design rather than of validation. BIOME_SPECIES is
	# deliberately partial — PLAINS has no ordinary predator of its own and takes
	# the crocodile, which is a band decision — but the boss family is finished:
	# every band's road stations have a named guardian, and the crocodile survives
	# as a boss ONLY on the two paths that are not a band lookup at all (a station
	# standing in a river, and the degrade path for a row that fails to resolve).
	#
	# So a band with no boss row is now a HOLE rather than a choice: it would put
	# a plain piglet crocodile on a road station at 6x scale and read as the boss
	# family having been forgotten one biome over. Stated against the enum, never
	# against a list here, so a SEVENTH biome demands its boss on the commit that
	# adds the band rather than shipping quietly boss-less.
	for biome_v: Variant in _biomes.values():
		if not _biome_boss.has(int(biome_v)):
			_fail("BIOME_BOSS has no row for Biome %d — every band owes its road"
					% int(biome_v) + " stations a named boss (the crocodile is the"
					+ " fallback for RIVER stations and for a row that fails to"
					+ " load, not for a whole band), so that band's bosses are"
					+ " 6x piglet crocodiles")

	# The negative control for this half: a table with one row and an empty
	# dispatch map passes every loop above without measuring anything.
	if _species_table.size() < 2 or _biome_species.is_empty():
		_fail("only %d SPECIES row(s) and %d dispatch entries — checks over the"
				% [_species_table.size(), _biome_species.size()]
				+ " species table ran against a world with one predator in it")
	Sentinel.done("species_table")


func _check_dispatch_map(label: String, map: Dictionary) -> void:
	"""
	One dispatch map's entries: real biome, real species row, loadable scene.

	@param label: the map's name in endless_terrain.gd, for the failure messages
	@param map: BIOME_SPECIES or BIOME_BOSS — Biome -> { species, scene }

	Every way one of these entries goes wrong is silent from the outside, because
	all three degrade to a crocodile: a dead key (a biome value that biome_at()
	can never return) never fires, a name that is not a SPECIES row is warned
	about once by the AI's _ready() and then behaves as a crocodile, and a scene
	path that does not load falls back to the crocodile scene. All three read to a
	player as "the new predator isn't in the game yet".

	An EMPTY map passes this vacuously, which is why BIOME_BOSS gets a totality
	gate beside the call to this one: entry-by-entry validation cannot see a band
	that has no entry at all.
	"""
	for biome_v: Variant in map:
		var entry: Dictionary = map[biome_v]
		if not _biomes.values().has(int(biome_v)):
			_fail("%s has an entry for %s, which is not a value of the"
					% [label, biome_v] + " Biome enum %s — biome_at() can never"
					% _biomes.values() + " answer it, so that entry is dead")
		var species_name: String = String(entry.get("species", ""))
		if not _species_table.has(species_name):
			_fail("%s[%s] dispatches to '%s', which is not a SPECIES row —"
					% [label, biome_v, species_name]
					+ " everything it spawns would silently fall back")
		var scene_path: String = String(entry.get("scene", ""))
		if not ResourceLoader.exists(scene_path) or load(scene_path) == null:
			_fail("%s[%s] points at '%s', which does not load"
					% [label, biome_v, scene_path])
	Sentinel.done("dispatch_map")


# ============================================================================
# CHECK 9 — PLACEMENT IS A PURE FUNCTION of (chunk coords, run_seed)
# ============================================================================

func _check_determinism(terrain_script: GDScript) -> void:
	"""
	Generate the same field THREE times and prove the world is reproducible.

	This is the invariant CLAUDE.md's terrain section opens with, and the one the
	whole multiplayer mesh is built on top of: two peers exchange a run_seed and
	nothing else, and from that alone they must put the same predator, of the same
	species, under the same name, at the same coordinates. Nothing checks it at
	runtime — a peer whose vipers stand half a metre off is a peer whose crocodile
	sync lands on bodies that are not quite where the master thinks, and the only
	symptom is enemies that jitter for some players and not others.

	Three generations, and the third is the negative control:

	  * FORWARD — chunks generated in raster order, the order the streamer uses.
	  * REVERSE — the SAME chunks, generated back to front. Byte-identical, or the
	    generation is carrying state between chunks, which is the failure the
	    "one shared hash stream" rule in CLAUDE.md exists to prevent: a revisited
	    chunk (the streamer rebuilds one every time you cross a boundary) would
	    then come back different from how you left it.
	  * DETERMINISM_CONTROL_SEED — must DIFFER. Without it, "the two fields matched" is also
	    true of a comparison of two empty fields, or of a signature that captured
	    nothing that varies.

	COMPARED AT 17 SIGNIFICANT DIGITS, i.e. bit for bit (see EXACT). A tolerance
	would be the wrong instrument entirely: two peers do not average their
	positions, they either agree or they do not.
	"""
	var forward: Dictionary = _generate_field(terrain_script, RUN_SEEDS[0], false)
	var reverse: Dictionary = _generate_field(terrain_script, RUN_SEEDS[0], true)
	var other: Dictionary = _generate_field(terrain_script, DETERMINISM_CONTROL_SEED, false)

	var bodies := 0
	var mismatches := 0
	var first := ""
	for key_v: Variant in forward:
		bodies += (forward[key_v] as Array).size()
		if var_to_bytes(forward[key_v]) != var_to_bytes(reverse.get(key_v, [])):
			mismatches += 1
			if first == "":
				first = _first_difference(key_v, forward[key_v], reverse.get(key_v, []))

	var differing := 0
	for key_v: Variant in forward:
		if var_to_bytes(forward[key_v]) != var_to_bytes(other.get(key_v, [])):
			differing += 1

	print("determinism: %d chunks / %d bodies regenerate identically back-to-front;"
			% [forward.size(), bodies]
			+ " %d of them differ under a second run seed" % differing)

	if mismatches > 0:
		_fail("%d of %d chunks generated DIFFERENTLY when the field was built back"
				% [mismatches, forward.size()]
				+ " to front — placement is not a pure function of (chunk coords,"
				+ " run_seed), so a revisited chunk changes under you and two peers"
				+ " sharing a seed do not share a world. First: %s" % first)
	if bodies < 1:
		_fail("the determinism field generated no enemies at all — the comparison"
				+ " above matched two empty signatures and measured nothing")
	if differing < forward.size() / 2:
		_fail("only %d of %d chunks changed when run_seed changed —" % [
				differing, forward.size()]
				+ " the signature is not capturing what run_seed varies, so the"
				+ " forward/reverse match above proves nothing")
	Sentinel.done("determinism")


func _first_difference(chunk_pos: Variant, a: Array, b: Array) -> String:
	"""
	The first entry two generations of one chunk disagree on, as one line.

	@param chunk_pos: the chunk, for the message
	@param a: the forward generation's signature entries
	@param b: the reverse generation's
	@return a one-line description of the first difference

	The first ENTRY rather than the whole chunk: a chunk holds a dozen bodies and
	printing both signatures in full buries the one number that moved under two
	kilobytes of the ones that did not.
	"""
	for i in range(maxi(a.size(), b.size())):
		var one: Variant = a[i] if i < a.size() else null
		var two: Variant = b[i] if i < b.size() else null
		if var_to_bytes(one) != var_to_bytes(two):
			return "chunk %s entry %d: forward %s, reverse %s" % [
					chunk_pos, i, var_to_str(one), var_to_str(two)]
	return "chunk %s (%d vs %d entries)" % [chunk_pos, a.size(), b.size()]


func _generate_field(terrain_script: GDScript, run_seed: int, backwards: bool) -> Dictionary:
	"""
	Build a DETERMINISM_FIELD-square field and return each chunk's exact signature.

	@param terrain_script: endless_terrain.gd
	@param run_seed: the seed to force through the public set_run_seed() seam
	@param backwards: generate the chunks in reverse raster order
	@return Vector2i -> one signature entry per enemy the chunk spawned

	A FRESH terrain node every call, so the second generation cannot be reading
	anything the first one cached. The chunk order is the only difference between
	the forward and reverse runs — same node type, same seed, same call sequence,
	which is what makes a difference in the answer mean exactly one thing.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)

	var order: Array[Vector2i] = []
	var half := DETERMINISM_FIELD / 2
	for cx in range(-half, half + 1):
		for cz in range(-half, half + 1):
			order.append(Vector2i(cx, cz))
	if backwards:
		order.reverse()

	var signatures := {}
	for chunk_pos: Vector2i in order:
		signatures[chunk_pos] = _chunk_signature(terrain, chunk_pos)
	return signatures


func _chunk_signature(terrain: Node, chunk_pos: Vector2i) -> Array:
	"""
	Everything one chunk spawns, as raw comparable values.

	@param terrain: a terrain node with its run seed already forced
	@param chunk_pos: the chunk to generate
	@return one [name, species, position, yaw] entry per enemy, unrounded

	The call sequence is create_chunk's, for the reason the sweep's is: the later
	spawners judge their candidates against footprints the earlier ones appended,
	so a signature taken from the crocodile spawner alone would be blind to a
	non-deterministic BLOCK — and a block that moves moves the crocodiles that
	were placed around it.
	"""
	var parent := _generate_chunk(terrain, chunk_pos)
	var parts: Array = []
	for child in parent.get_children():
		if not child.is_in_group("crocodile"):
			continue
		var node := child as Node3D
		parts.append([String(child.name), String(child.get("species")),
				node.position, node.rotation.y])
	parent.free()
	return parts


func _generate_chunk(terrain: Node, chunk_pos: Vector2i, with_coins: bool = false,
		out_obstacles: Array = []) -> MeshInstance3D:
	"""
	Run create_chunk's spawner sequence over one chunk. THE CALLER FREES the parent.

	@param terrain: a terrain node with its run seed already forced
	@param chunk_pos: the chunk to generate
	@param with_coins: also lay the chunk's slice of the COIN ROAD, which
	                   create_chunk does immediately after the hunters. Off by
	                   default because most callers here digest bodies and a coin
	                   is not one; check 14 needs it, because "a coin settled
	                   inside the boss" is a fact about the two together.
	@param out_obstacles: filled with the finished footprint list, so a caller can
	                      drive `_settle_coin_y` against exactly the obstacles the
	                      chunk really built (check 14 again)
	@return the chunk parent, in the tree at the chunk's world origin, holding
	        every body the chunk spawned

	THE CALL SEQUENCE IS create_chunk'S, and the order is the point: the later
	spawners judge their candidates against the footprints the earlier ones
	appended to `obstacles`, so a boss placed against a half-built obstacle list
	stands somewhere the real game would never put it — and a check measuring that
	boss is measuring a world nobody plays.
	"""
	var parent := _make_chunk_parent(terrain.chunk_to_world(chunk_pos))
	var platforms: Array = []
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
	terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
	terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_platform_crocodiles(chunk_pos, parent, platforms)
	terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_hunters_in_chunk(chunk_pos, parent, obstacles)
	if with_coins:
		terrain.spawn_coins_in_chunk(chunk_pos, parent, obstacles)
	out_obstacles.assign(obstacles)
	body.free()
	return parent


# ============================================================================
# CHECK 12 — the hunter stream does NOT touch the crocodile stream
# ============================================================================

func _check_hunter_stream_independence(terrain_script: GDScript) -> void:
	"""
	THE NEGATIVE CONTROL THAT MATTERS MOST ABOUT THIS FEATURE, and the reason it
	is measured rather than asserted.

	CLAUDE.md's determinism rule: an independent feature takes its OWN hash stream,
	with its own salt and its own coordinate primes, and consumes NO draw from the
	shared chunk RNG. The hunter is the newest feature to make that promise, and
	the cost of breaking it is invisible and total — a single extra draw from
	`spawn_crocodiles_in_chunk`'s rng slides EVERY crocodile in the world to a new
	spot, which nothing on screen would ever tell you and which two multiplayer
	peers on different builds would disagree about silently.

	So: generate the SAME field twice against the SAME code, once with hunters on
	and once with them off, and digest ONLY the crocodiles. The methodology is
	tower_site_selfcheck's A/B, one feature over — including its second half.

	  * CHECK 12a. Every chunk's CROCODILES must be byte-identical between the two
	    legs. They are compared through var_to_bytes for the reason check 9 gives:
	    two peers do not average their worlds.
	  * CHECK 12b, the negative control. Check 12a passes perfectly for a hunter
	    spawner that does nothing at all, so the hunters-on leg must actually have
	    put hunters in the field — otherwise this whole function measured an
	    inert feature agreeing with itself.

	`spawn_hunters` is the switch because it is the FIRST line of the spawner: with
	it false the hunter RNG is never even constructed, which is the strongest form
	of "off" available and exactly the state the world was in before this bead.
	"""
	var with_hunters: Dictionary = _hunter_ab_field(terrain_script, RUN_SEEDS[0], true)
	var without: Dictionary = _hunter_ab_field(terrain_script, RUN_SEEDS[0], false)

	var moved := 0
	var first := ""
	var crocs := 0
	var hunters := 0
	for key_v: Variant in with_hunters:
		var pair: Array = with_hunters[key_v]
		crocs += (pair[0] as Array).size()
		hunters += int(pair[1])
		var other: Array = without.get(key_v, [[], 0])
		if var_to_bytes(pair[0]) != var_to_bytes(other[0]):
			moved += 1
			if first == "":
				first = _first_difference(key_v, pair[0], other[0])

	print("hunter A/B: %d chunks, %d crocodiles unmoved by %d hunters"
			% [with_hunters.size(), crocs, hunters])

	if moved > 0:
		_fail("%d of %d chunks put their CROCODILES somewhere else once hunters were"
				% [moved, with_hunters.size()]
				+ " enabled — spawn_hunters_in_chunk is consuming (or skipping) a draw"
				+ " from the shared chunk RNG instead of running on its own"
				+ " HUNTER_SALT stream. First: %s" % first)
	if crocs < 1:
		_fail("the hunter A/B field contained no crocodiles at all — 12a compared two"
				+ " empty signatures and proved nothing")
	if hunters < 1:
		_fail("the hunter A/B field contained no HUNTERS at all, so the 'hunters on'"
				+ " leg is the same world as the 'hunters off' leg — check 12a above"
				+ " measured an inert feature agreeing with itself")
	Sentinel.done("hunter_stream_independence")


func _hunter_ab_field(terrain_script: GDScript, run_seed: int, hunters_on: bool) -> Dictionary:
	"""
	One leg of check 12: build a DETERMINISM_FIELD-square field and return
	Vector2i -> [crocodile signature entries, hunter count].

	@param terrain_script: endless_terrain.gd
	@param run_seed: forced through the public set_run_seed() seam
	@param hunters_on: the terrain's own `spawn_hunters` flag for this leg
	@return the per-chunk digest the A/B compares

	The crocodile half is check 9's signature EXACTLY (name, species, position,
	yaw, unrounded) minus the hunters, because the question is whether anything
	about a crocodile moved — not whether the two fields hold the same bodies. The
	hunter half is a COUNT and not a signature: check 9 already proves hunter
	placement is deterministic (they ride its shared _generate_chunk), so all this
	leg needs from them is proof they existed.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)
	terrain.spawn_hunters = hunters_on

	var out := {}
	var half := DETERMINISM_FIELD / 2
	for cx in range(-half, half + 1):
		for cz in range(-half, half + 1):
			var chunk_pos := Vector2i(cx, cz)
			var parent := _generate_chunk(terrain, chunk_pos)
			var parts: Array = []
			var hunter_count := 0
			for child in parent.get_children():
				if not child.is_in_group("crocodile"):
					continue
				if String(child.name).begins_with("Hunter_"):
					hunter_count += 1
					continue
				var node := child as Node3D
				parts.append([String(child.name), String(child.get("species")),
						node.position, node.rotation.y])
			parent.free()
			out[chunk_pos] = [parts, hunter_count]
	terrain.free()
	return out


# ============================================================================
# CHECK 13 — THE FIELD CAP on GD-SURVEY hunters (bead godot-test1-fhu)
# ============================================================================

## The square field checks 13b-e regenerate. Smaller than DETERMINISM_FIELD only
## because five legs are built over it and each one is a whole field; at
## HUNTER_CHANCE it still offers several hunters, which the positive control
## below insists on rather than assumes.
const CAP_FIELD: int = 9


func _check_hunter_field_cap(terrain_script: GDScript) -> void:
	"""
	The owner's ten (2026-09-02): "limit hunters on field with total number 10
	(inside HQ doesn't count)". THE FIX IS TWO HALVES and this checks both, because
	each covers exactly what the other cannot.

	  * 13a — THE RETUNED CHANCE, which is the half that holds everywhere. Read
	    HUNTER_CHANCE and `render_distance` off the shipped script and assert the
	    EXPECTED desktop residency is under HUNTER_FIELD_CAP. This is the only half
	    that is a pure function of (chunk, run_seed) — it works in a room, on every
	    peer, with no shared state — so a retune that breaks it must fail here even
	    though the hard cap below would still clamp a solo player's screen.
	  * 13b — THE HARD CAP FIRES. A field generated with HUNTER_FIELD_CAP hunter
	    bodies already standing in the tree must place NONE.
	  * 13c — AND IT IS THE COUNT, not "off". One body short of the cap must place
	    exactly the hunters the empty field placed — same count, same positions.
	    Without this, `return true` unconditionally passes 13b.
	  * 13d — THE HQ DOESN'T COUNT. The same bodies parented under the tower shell
	    must not cap anything: that is the owner's parenthesis, and it is why the
	    exclusion is by PARENT (a guard is in group "crocodile" like everything
	    else).
	  * 13e — AND IT IS OFF IN A ROOM, the documented ceiling: a live body count
	    differs per peer by where they walked, and crocodiles are master-simulated
	    but never network-spawned, so a hunter one peer capped away and the master
	    did not is a body they disagree about.
	  * 13f — NOTHING ELSE MOVED. Every crocodile, boss and COIN of the capped
	    field is byte-identical to the uncapped one. The cap is a post-draw skip at
	    the very bottom of the spawner, so turning it on may remove hunters and
	    may not slide anything else.

	Every leg drives the SHIPPED `spawn_hunters_in_chunk` through `_generate_chunk`,
	with the shipped `hunter_robot.tscn` as the standing population — the cap counts
	real bodies by their real `species`, so a stand-in Node3D would be measuring a
	rule this file invented rather than the one that ships.
	"""
	var consts: Dictionary = terrain_script.get_script_constant_map()
	if not consts.has("HUNTER_FIELD_CAP") or not consts.has("HUNTER_CHANCE"):
		_fail("endless_terrain.gd has no HUNTER_FIELD_CAP / HUNTER_CHANCE — the"
				+ " owner's field cap (bead godot-test1-fhu) is gone, so nothing"
				+ " here bounds the number of retrieval units in the world")
		Sentinel.done("hunter_field_cap")
		return
	if _hunter_scene == null:
		_fail("endless_terrain.gd exposes no HUNTER_SCENE — check 13 cannot put a"
				+ " standing population in the field, so the cap would be measured"
				+ " against an empty world and pass vacuously")
		Sentinel.done("hunter_field_cap")
		return
	var cap: int = int(consts["HUNTER_FIELD_CAP"])
	var chance: float = float(consts["HUNTER_CHANCE"])

	# ---- 13a: the expected desktop field, from the consts --------------------
	# render_distance is an @export, so it is read off a fresh node (whose _ready
	# never runs, detached) rather than restated here — the web build lowers it in
	# _ready and desktop is the wider of the two, which is the one to bound.
	var probe := Node3D.new()
	probe.set_script(terrain_script)
	var render_distance: int = int(probe.render_distance)
	probe.free()
	var residency: int = (2 * render_distance + 1) * (2 * render_distance + 1)
	var expected: float = float(residency) * chance
	print("hunter cap: render_distance %d -> %d chunks resident, expected %.2f"
			% [render_distance, residency, expected]
			+ " hunters at HUNTER_CHANCE %.3f, hard cap %d" % [chance, cap])
	if expected > float(cap):
		_fail("HUNTER_CHANCE %.3f over the %d-chunk desktop residency expects %.2f"
				% [chance, residency, expected]
				+ " hunters, above the cap of %d — the DETERMINISTIC half of the" % cap
				+ " field cap is broken, so a room (where the live cap is off by"
				+ " design) would run over the owner's ten. Lower HUNTER_CHANCE")

	# ---- 13b-f: the hard cap, driven on the shipped spawner ------------------
	var empty: Dictionary = _cap_field(terrain_script, RUN_SEEDS[0], 0, false, false)
	var full: Dictionary = _cap_field(terrain_script, RUN_SEEDS[0], cap, false, false)
	var one_short: Dictionary = _cap_field(terrain_script, RUN_SEEDS[0], cap - 1, false, false)
	var in_hq: Dictionary = _cap_field(terrain_script, RUN_SEEDS[0], cap, true, false)
	var in_room: Dictionary = _cap_field(terrain_script, RUN_SEEDS[0], cap, false, true)

	print("hunter cap: %d chunks placed %d hunters with an empty field, %d with %d"
			% [int(empty["chunks"]), int(empty["hunters"]), int(full["hunters"]), cap]
			+ " standing, %d with %d standing, %d with %d in the HQ, %d in a room"
					% [int(one_short["hunters"]), cap - 1, int(in_hq["hunters"]),
					cap, int(in_room["hunters"])])

	if int(empty["hunters"]) < 1:
		_fail("the field cap check placed no hunters at all with an empty field —"
				+ " every leg below compared zero against zero and measured nothing"
				+ " (widen CAP_FIELD or change RUN_SEEDS[0])")
	if int(full["hunters"]) != 0:
		_fail("%d hunter(s) spawned into a field that already held %d — the"
				% [int(full["hunters"]), cap]
				+ " HUNTER_FIELD_CAP skip in spawn_hunters_in_chunk is not firing,"
				+ " so the owner's ten is not a ceiling at all")
	if int(one_short["hunters"]) != int(empty["hunters"]):
		_fail("a field holding %d hunters (one short of the cap) placed %d more,"
				% [cap - 1, int(one_short["hunters"])]
				+ " but the empty field placed %d — the cap is not reading the"
						% int(empty["hunters"])
				+ " COUNT, it is refusing (or admitting) unconditionally")
	if int(in_hq["hunters"]) != int(empty["hunters"]):
		_fail("%d hunters standing INSIDE THE HQ capped the field down to %d"
				% [cap, int(in_hq["hunters"])]
				+ " (the empty field placed %d) — the owner's \"inside HQ doesn't"
						% int(empty["hunters"])
				+ " count\" is not honoured, so a guarded building starves the world"
				+ " of the predator the building is about")
	if int(in_room["hunters"]) != int(empty["hunters"]):
		_fail("the live cap fired in a ROOM (%d placed against %d) — a body count"
				% [int(in_room["hunters"]), int(empty["hunters"])]
				+ " is not shared between peers, so a hunter one peer capped away"
				+ " and the master did not is a body they disagree about")

	var moved := 0
	var first := ""
	var others := 0
	for key_v: Variant in (empty["world"] as Dictionary):
		var mine: Array = (empty["world"] as Dictionary)[key_v]
		others += mine.size()
		var theirs: Array = (full["world"] as Dictionary).get(key_v, [])
		if var_to_bytes(mine) != var_to_bytes(theirs):
			moved += 1
			if first == "":
				first = _first_difference(key_v, mine, theirs)
	if moved > 0:
		_fail("%d chunk(s) put their crocodiles, bosses or COINS somewhere else"
				% moved + " once the hunter cap was hit — the cap is not a post-draw"
				+ " skip at the bottom of spawn_hunters_in_chunk, so a full field"
				+ " reshapes the world around it. First: %s" % first)
	if others < 1:
		_fail("the capped/uncapped comparison held no crocodiles, bosses or coins"
				+ " at all — it matched two empty signatures and proved nothing")
	Sentinel.done("hunter_field_cap")


func _cap_field(terrain_script: GDScript, run_seed: int, standing: int,
		under_tower: bool, in_room: bool) -> Dictionary:
	"""
	One leg of check 13.

	@param terrain_script: endless_terrain.gd
	@param run_seed: forced through the public set_run_seed() seam
	@param standing: how many hunter bodies are already in the tree before the
	                 field is generated
	@param under_tower: park those bodies under the terrain's `_tower_shell`, which
	                    is what the cap's by-PARENT exclusion reads
	@param in_room: publish a group-"mp" node answering is_online() = true
	@return { chunks, hunters, world } — the hunter COUNT the field placed, and a
	        per-chunk signature of everything else it built

	THE STANDING POPULATION IS THE SHIPPED SCENE, with `species` assigned before
	add_child like every spawner does (`_ready()` resolves the row exactly once).
	The cap counts by that field, so a bare Node3D would be counted by nothing and
	the leg would silently become the empty one.

	Chunk parents are freed as they go, which is what keeps the hunters this leg
	SPAWNS from capping the leg itself — the real game frees a chunk's hunter with
	its chunk too, just at streaming distance instead of immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)

	var holder := Node3D.new()
	root.add_child(holder)
	if under_tower:
		# The seam the cap reads is `tower_shell()`, whose backing field is what the
		# real streamer assigns when the building is instanced. Set it here rather
		# than instancing an 80 m shell: the rule under test is ANCESTRY, and a
		# stand-in ancestor is the honest way to ask about ancestry.
		terrain._tower_shell = holder
	for i in standing:
		var body: Node = _hunter_scene.instantiate()
		body.name = "Standing_%d" % i
		body.species = _hunter_species
		holder.add_child(body)

	var mp_stub: Node = null
	if in_room:
		mp_stub = _room_stub()
		root.add_child(mp_stub)

	var world := {}
	var hunters := 0
	var half := CAP_FIELD / 2
	for cx in range(-half, half + 1):
		for cz in range(-half, half + 1):
			var chunk_pos := Vector2i(cx, cz)
			var parent := _generate_chunk(terrain, chunk_pos, true)
			var parts: Array = []
			for child in parent.get_children():
				var node := child as Node3D
				if node == null:
					continue
				if String(child.name).begins_with("Hunter_"):
					hunters += 1
					continue
				# ONLY A PREDATOR IS LABELLED BY ITS NAME. A crocodile's name IS its
				# room-wide id and is a pure function of its chunk; a coin, an
				# artifact prop or a camp piece is unnamed and takes the engine's
				# "@Area3D@8868", which counts up per PROCESS — so a name-keyed
				# signature reports every one of them as having moved when nothing
				# has. Class plus position says everything this comparison needs.
				var label: String = (String(child.name) + "|" + String(child.get("species"))
						if child.is_in_group("crocodile") else child.get_class())
				parts.append([label, node.position])
			parent.free()
			world[chunk_pos] = parts

	holder.free()
	if mp_stub != null:
		mp_stub.free()
	terrain.free()
	return { "chunks": world.size(), "hunters": hunters, "world": world }


func _room_stub() -> Node:
	"""
	A node in group "mp" that says a room exists, and nothing else.

	The cap asks `is_online()` behind `has_method`, the null-safe group lookup this
	project uses everywhere. Driving it with the real MpManager would boot a lobby
	client and a WebRTC peer to answer one bool; a four-line script is the whole
	contract the spawner depends on.
	"""
	var script := GDScript.new()
	script.source_code = "extends Node\nfunc is_online() -> bool:\n\treturn true\n"
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.add_to_group("mp")
	return stub


# ============================================================================
# CHECK 14 — a ROAD BOSS is a footprint, so no coin settles inside it
# ============================================================================

## Road bosses walked by check 14, and the seeds it walks them on. The bead
## (godot-test1-6op) asks for 25 seeds; the boss count per seed is small because
## every station generates a whole chunk WITH its coins, and a boss's owning chunk
## is the only one that can hold it (the claim rule in spawn_bosses_in_chunk).
const BOSS_COIN_SEED_COUNT: int = 25
const BOSS_COIN_BOSSES: int = 4

## "A coin came near a boss", as a multiple of the boss's own footprint radius.
## Purely a NON-VACUITY gate: the road's coins and the road's bosses share a
## centreline, so if not one coin in the whole walk lands within this of a boss,
## the walk is not testing what it thinks it is.
const BOSS_COIN_NEAR_FACTOR: float = 3.0


func _check_boss_coin_footprint(terrain_script: GDScript) -> void:
	"""
	THE BUG (bead godot-test1-6op, found by the 9k7 review of PR #187): a road boss
	appended NO footprint to `obstacles`, so `spawn_coins_in_chunk` — which runs
	after it in create_chunk — laid the road straight through a body up to 6.3 m
	across. It is visible in that PR's own screenshot as a coin at the crocodile's
	flank, and it is worth ~125 m² of swallowed coins per boss at 9x scale.

	TWO ASSERTIONS, and the first is the one that cannot go vacuous:

	  * 14a — THE PERCH RULE REFUSES THE BOSS'S OWN COLUMN. `_settle_coin_y` is
	    driven directly, at the boss's exact position, against the exact
	    `obstacles` list the chunk built, and must answer INF ("skip this coin").
	    That is the shipped rule reading the shipped footprint, so it fails the
	    moment the append is removed — no coin has to happen to land there.
	  * 14b — AND NO COIN THE CHUNK ACTUALLY SPAWNED IS INSIDE ONE. The field-level
	    consequence, over BOSS_COIN_SEED_COUNT roads.

	`top: 0.0, climbable: false` is what makes 14a true: a body is not a perch, so
	the tallest-overlap rule must SKIP the coin rather than stand it on the boss's
	head — the cactus / camp / tree-canopy call, one home for the rule.
	"""
	var consts: Dictionary = terrain_script.get_script_constant_map()
	var per_scale: float = float(consts.get("BOSS_FOOTPRINT_RADIUS_PER_SCALE", 0.0))
	if per_scale <= 0.0 or _boss_interval < 1:
		_fail("endless_terrain.gd has no usable BOSS_FOOTPRINT_RADIUS_PER_SCALE /"
				+ " BOSS_INTERVAL_STATIONS — check 14 has no radius to measure a"
				+ " boss's swallowed coins against")
		Sentinel.done("boss_coin_footprint")
		return

	var measured := 0
	var coins := 0
	var inside := 0
	var near := 0
	var perch_ok := 0
	var worst := ""

	for s in BOSS_COIN_SEED_COUNT:
		# Spread over the same kind of arbitrary seeds check 11 walks; the two lists
		# are deliberately different worlds, so between them the road is asked about
		# far more than one river and one band.
		var run_seed: int = 314159 + s * 7919
		var terrain := Node3D.new()
		terrain.set_script(terrain_script)
		terrain.set_run_seed(run_seed)
		terrain.crocodile_scene = load(CROC_SCENE)
		terrain.coin_scene = load(COIN_SCENE)

		# Grow the station cache until it really spans the last boss — by WORLD X,
		# not by index, exactly as check 11 does and for the same reason.
		var last_k: int = BOSS_COIN_BOSSES * _boss_interval
		var reach: float = float(last_k) * maxf(float(terrain.road_coin_spacing), 1.0)
		while terrain.road_k_max < last_k:
			terrain._road_extend_to_x(0.0, reach)
			reach *= 1.5
		var last_boss: int = mini(BOSS_COIN_BOSSES,
				terrain._road_terminal_k() / _boss_interval)

		for i in range(1, last_boss + 1):
			var boss: Dictionary = terrain._boss_at(i)
			var chunk_pos: Vector2i = terrain.world_to_chunk(boss["positions"][0])
			var obstacles: Array = []
			var parent := _generate_chunk(terrain, chunk_pos, true, obstacles)

			var body: Node3D = null
			for child in parent.get_children():
				if String(child.name) == "BossCrocodile_%d" % i:
					body = child as Node3D
					break
			if body == null:
				# Every candidate buried in geometry: a designed outcome, not a
				# failure (check 11 owns the floor on how often that may happen).
				parent.free()
				continue

			measured += 1
			var radius: float = per_scale * float(boss["scale"])

			# 14a — the shipped rule, at the body's own column.
			var settled: float = terrain._settle_coin_y(body.position.x,
					body.position.z, 0.5, obstacles)
			if is_inf(settled):
				perch_ok += 1
			elif worst == "":
				worst = ("seed %d boss %d (scale %.2f, footprint %.2f m): a coin at"
						+ " its exact centre settles at y = %.2f instead of being"
						+ " skipped") % [run_seed, i, float(boss["scale"]), radius,
						settled]

			# 14b — and nothing the chunk really spawned stands in it.
			for child in parent.get_children():
				if not child.is_in_group("coin"):
					continue
				var coin := child as Node3D
				coins += 1
				var d: float = Vector2(coin.position.x - body.position.x,
						coin.position.z - body.position.z).length()
				if d < radius:
					inside += 1
					if worst == "":
						worst = ("seed %d boss %d: a coin sits %.2f m from its"
								+ " centre, inside the %.2f m footprint"
								) % [run_seed, i, d, radius]
				elif d < radius * BOSS_COIN_NEAR_FACTOR:
					near += 1
			parent.free()
		terrain.free()

	print("boss footprint: %d road bosses over %d seeds, %d coins in their chunks;"
			% [measured, BOSS_COIN_SEED_COUNT, coins]
			+ " %d/%d refuse a coin at the boss's own column; %d coins inside a"
					% [perch_ok, measured, inside]
			+ " footprint, %d within %.0fx of one" % [near, BOSS_COIN_NEAR_FACTOR])

	if measured < 1:
		_fail("check 14 placed no road boss at all over %d seeds — it measured"
				% BOSS_COIN_SEED_COUNT + " nothing (see check 11's placement floor)")
	if perch_ok < measured:
		_fail("%d of %d road bosses do not refuse a coin at their own centre —"
				% [measured - perch_ok, measured]
				+ " spawn_bosses_in_chunk is not appending its {pos, radius, top:"
				+ " 0.0, climbable: false} footprint to `obstacles`, so"
				+ " _settle_coin_y cannot see the body and the road runs through"
				+ " it (bead godot-test1-6op). First: %s" % worst)
	if inside > 0:
		_fail("%d road coin(s) settled INSIDE a boss's footprint — the append is"
				% inside + " there but the coin pass is not reading it (order:"
				+ " spawn_bosses_in_chunk must run before spawn_coins_in_chunk in"
				+ " create_chunk). First: %s" % worst)
	if coins < 1:
		_fail("not one coin was spawned in any boss's chunk, so 14b compared"
				+ " nothing — the road and the bosses have come apart, or"
				+ " `coin_scene` never reached the terrain")
	if near < 1:
		_fail("no coin in the whole walk landed within %.0fx of a boss footprint —"
				% BOSS_COIN_NEAR_FACTOR + " the road's coins and the road's bosses"
				+ " no longer share a centreline, so 14b would pass over a world"
				+ " in which the bug could not occur")
	Sentinel.done("boss_coin_footprint")


# ============================================================================
# CHECK 10 — one identity scheme and one state byte, SHARED BY EVERY SPECIES
# ============================================================================

## Which member of the AI carries each bit of the sync byte, named against
## MpManager's own constants — the encoder's and the decoder's single source — so
## a bit renamed on one side and not the other fails here rather than desyncing a
## room.
##
## BITING is deliberately exempt from the "clears again" half below: it decodes
## through _start_bite(), which is a one-way "the chomp STARTED" edge cleared by
## the local animation timer, never by a zero in a later byte. That asymmetry is
## the documented design (see set_remote_state), so the check states it rather
## than measuring the opposite and failing on correct code.
const CROC_STATE_BITS: Dictionary = {
	"is_chasing": "CROC_FLAG_CHASING",
	"is_fleeing": "CROC_FLAG_FLEEING",
	"is_paused": "CROC_FLAG_PAUSED",
	"is_biting": "CROC_FLAG_BITING",
	"is_burrowed": "CROC_FLAG_BURROWED",
}


func _check_mp_contract(croc: Node, species_name: String, chunk_pos: Vector2i,
		expected_prefix: String) -> void:
	"""
	Prove ONE live body of one species can be recognised and driven by a peer.

	@param croc: a crocodile the sweep just spawned — a real body, _ready() run
	@param species_name: the species it resolved to
	@param chunk_pos: the chunk it was spawned in
	@param expected_prefix: the deterministic name prefix its SPAWNER owes it —
	                        the caller derives it from the classifier, so a body
	                        renamed to something no peer can derive fails here
	                        rather than being quietly accepted under a looser rule

	CALLED ONCE PER SPECIES, on the first body of it the sweep produces, so the
	cost is one probe per row rather than one per animal — and no species is
	silently skipped either, because the coverage gate demands the sweep produce
	one of each.

	TWO HALVES, both of which the epic deliberately made species-blind:

	  * IDENTITY. What the name has to be is DERIVABLE BY EVERY PEER FROM THE
	    SEED, because the name IS the room-wide id — croc_id_for() hashes it. So
	    every predator a chunk\'s crocodile spawner places is named
	    `Crocodile_<cx>_<cy>_<i>` whatever SPECIES it is (see the note over that
	    line in spawn_crocodiles_in_chunk): species is a pure function of position,
	    so a per-species prefix would churn every id in the room to say something
	    both peers already knew. A viper that named itself is a viper no peer can
	    address, which shows up as one animal syncing and another standing still.

	    THE PREFIX IS PER-SPAWNER, NOT PER-SPECIES, and the hunter is the case that
	    makes the distinction concrete: it comes from its OWN function on its own
	    stream with its own index sequence, so naming it "Crocodile_" would claim
	    a slot the crocodile spawner in the same chunk is already using — two
	    bodies, one id, and one of them unaddressable. Hence `expected_prefix`.
	  * THE STATE BYTE. Every bit MpManager encodes must decode back onto the
	    same member of the same body, for every species — a row is data, and the
	    sync layer is not allowed to grow a special case per animal.

	AND THE BURROW IS THE POINTED CASE. It rides a bit precisely because it is
	NOT derivable from the others (see CROC_FLAG_BURROWED): a peer recomputing
	`is_burrowed = not is_chasing` for itself is a bug this epic already shipped
	once and had to fix, and it looks like nothing at all — a viper standing on
	the sand on one screen and buried on another. So the two decodes below are
	chosen to be exactly the ones a re-derivation would get wrong: burrowed WHILE
	chasing, and surfaced while NOT chasing.
	"""
	# ---- identity -----------------------------------------------------------
	var node_name: String = String(croc.name)
	if not node_name.begins_with(expected_prefix):
		_fail("a '%s' spawned in chunk %s is named '%s', not '%s<index>' —" % [
				species_name, chunk_pos, node_name, expected_prefix]
				+ " the node name IS the room-wide id, so a species that renames"
				+ " itself is one no peer can address")
	if croc.croc_id() != croc.croc_id_for(node_name):
		_fail("'%s' latched croc_id %d, but its name '%s' hashes to %d — the id"
				% [species_name, croc.croc_id(), node_name, croc.croc_id_for(node_name)]
				+ " a peer derives from the name is not the id this body answers to")

	# ---- the state byte, encode then decode ---------------------------------
	for member_v: Variant in CROC_STATE_BITS:
		var member: String = String(member_v)
		var flag_name: String = String(CROC_STATE_BITS[member])
		if not _mp_consts.has(flag_name):
			_fail("mp_codec.gd has no %s — the bit '%s' rides is gone, so nothing"
					% [flag_name, member] + " the master says about it reaches a peer")
			continue
		var bit: int = int(_mp_consts[flag_name])
		for value: bool in [true, false]:
			croc.set(member, value)
			var carried: bool = (MpCodec._croc_flags(croc) & bit) != 0
			if carried != value:
				_fail("'%s': MpCodec._croc_flags() wrote %s for %s = %s —" % [
						species_name, "1" if carried else "0", member, value]
						+ " the master's byte does not describe this species, so"
						+ " every peer draws it in a pose it is not in")
		croc.set(member, false)

	var here: Vector3 = (croc as Node3D).global_position
	var all_bits: int = 0
	for member_v: Variant in CROC_STATE_BITS:
		all_bits |= int(_mp_consts.get(String(CROC_STATE_BITS[member_v]), 0))
	croc.set_remote_state(here, 0.0, all_bits)
	for member_v: Variant in CROC_STATE_BITS:
		if not bool(croc.get(String(member_v))):
			_fail("'%s': set_remote_state() ignored the %s bit — the master sends"
					% [species_name, member_v] + " it and this species never reads it")
	# And it clears again. BITING is exempt by design — see CROC_STATE_BITS.
	croc.set_remote_state(here, 0.0, 0)
	for member_v: Variant in CROC_STATE_BITS:
		if String(member_v) == "is_biting":
			continue
		if bool(croc.get(String(member_v))):
			_fail("'%s': %s stayed set through an all-clear state byte — it latches"
					% [species_name, member_v] + " on a peer and never comes back")

	# ---- the burrow is SENT, not re-derived ---------------------------------
	croc.set_remote_state(here, 0.0,
			int(_mp_consts.get("CROC_FLAG_CHASING", 0))
			| int(_mp_consts.get("CROC_FLAG_BURROWED", 0)))
	if not bool(croc.get("is_burrowed")):
		_fail("'%s': a byte saying CHASING and BURROWED at once surfaced the body —"
				% species_name + " the burrow is being re-derived from the chase"
				+ " flag on the receiving peer instead of read from the byte")
	croc.set_remote_state(here, 0.0, 0)
	if bool(croc.get("is_burrowed")):
		_fail("'%s': a byte with no BURROWED bit still left the body buried —"
				% species_name + " the burrow is being re-derived from `not"
				+ " is_chasing` on the receiving peer instead of read from the byte")
	Sentinel.done("mp_contract")


# ============================================================================
# CHECK 11 — a BOSS is dispatched on ITS STATION'S CENTRE, and rivers stay croc
# ============================================================================

func _check_boss_dispatch(terrain_script: GDScript) -> void:
	"""
	Walk BOSS_DISPATCH_COUNT road bosses and prove each one is the animal the rule
	names for its OWNING STATION's centre.

	WHY THIS IS ITS OWN CHECK AND NOT A BRANCH IN THE SWEEP: a boss is not
	chunk-keyed. BIOME_SPECIES answers for a chunk's ordinary predators because a
	chunk HAS a centre; a boss belongs to station i * BOSS_INTERVAL_STATIONS on
	the coin road, and its station's centre is the only coordinate it has that is
	pure in `i` + run_seed. The sweep's 289-chunk field around the origin contains
	exactly ONE boss, so it can never ask the rule more than one question. This
	walk asks it forty, spread over roughly twelve kilometres of road.

	WHAT IT CATCHES, AND WHAT IT DOES NOT. The expectation is recomputed here from
	the PUBLIC biome API at the station centre — never read back off the spawner —
	so a dispatch keyed on the wrong point fails as soon as that point and the
	station fall in different bands. For the CLAIMING CHUNK's centre (the
	BIOME_SPECIES mistake, made one feature over) that is most of the time. For the
	PLACED CANDIDATE it is measured and honest to say: almost never, because the
	candidate sits within a few metres of its station and a band is hundreds
	across — a mutant dispatching on it survives all eighty stations of this walk.
	That one is held by SHAPE rather than by sampling: spawn_bosses_in_chunk
	resolves the row above the candidate walk, before `local_pos` exists at all.

	BIOME_BOSS IS NOW TOTAL over the Biome enum, so this is a real per-band
	dispatch test everywhere and the only "crocodile" answers left in the walk are
	the RIVER ones — which is exactly why the `rivers < 1` gate below is the one
	that stops the fallback rotting. None of that needed an edit here when the
	rows landed: this file iterates the tables and never a list of its own.

	The `spec` half is the call-order contract (the landmine setup_as_boss has
	always carried, now with one more line in front of it): `species` is assigned
	BEFORE setup_as_boss BEFORE add_child, because _ready() resolves `spec` from
	`species` exactly once, on add_child. Assign it afterwards and the field says
	"snow_titan" while every speed, feeler and animation stays a crocodile's —
	invisible from the field alone, which is why one number off the resolved row
	is compared instead.
	"""
	if _boss_interval < 1:
		# Already reported by name in _run(). Returning rather than walking
		# anyway, because station 0 of an unseeded cache is a script error, and a
		# script error before _report() exits 0 with no verdict at all.
		Sentinel.done("boss_dispatch")
		return

	var measured := 0
	var rivers := 0
	var bands := {}
	## Which boss KINDS the walk actually put in the world, counted so the
	## coverage gate below can tell "the dispatch answered titan and a titan
	## spawned" from "no station in this walk ever stood in snow". Without it a
	## table-driven check happily verifies a rule it never once exercised.
	var kinds := {}
	var mismatches := 0
	var worst := ""

	## How many boss stations the walk actually offered, summed over the seeds —
	## the denominator every verdict below is reported against. It is COUNTED and
	## not `count * seeds` because the road's terminal station falls where the run
	## seed puts it, so one seed offers five bosses and the next one four.
	var offered := 0

	# EVERY seed in BOSS_DISPATCH_SEEDS, not just one, and the reason is the river
	# arm: a river is a thin contour, so whether one particular 1450 m road happens
	# to cross one is luck. Walking many short roads is what makes the arm the
	# owner named actually get asked, and the gate below says so out loud instead
	# of leaving it to chance.
	for run_seed: int in BOSS_DISPATCH_SEEDS:
		var terrain := Node3D.new()
		terrain.set_script(terrain_script)
		terrain.set_run_seed(run_seed)
		terrain.crocodile_scene = load(CROC_SCENE)
		terrain.coin_scene = load(COIN_SCENE)

		# The station cache has to span every station this walk asks about, and it
		# is extended by WORLD X, not by station index: a station advances X by at
		# most the spacing, less wherever the centerline is turning. So the first
		# guess is a lower bound and the loop grows it until the cache really
		# covers the last station, rather than assuming a straight road.
		var last_k: int = BOSS_DISPATCH_COUNT * _boss_interval
		var reach: float = float(last_k) * maxf(float(terrain.road_coin_spacing), 1.0)
		while terrain.road_k_max < last_k:
			terrain._road_extend_to_x(0.0, reach)
			reach *= 1.5

		# CLAMPED TO THE ROAD THAT EXISTS. spawn_bosses_in_chunk places nothing past
		# the terminal station (bead godot-test1-8gw.3), so asking about boss 40 on
		# a road that ends at boss 5 would not test the dispatch — it would just
		# count four hundred absences and report the cap as a coverage failure.
		# Read from the terrain, never restated here, so moving ROAD_TERMINAL_X
		# moves this walk with it.
		var last_boss: int = mini(BOSS_DISPATCH_COUNT,
				terrain._road_terminal_k() / _boss_interval)
		offered += last_boss
		for i in range(1, last_boss + 1):
			var centre: Vector2 = terrain._road_station(i * _boss_interval).center
			var in_river: bool = terrain.is_river_at(Vector3(centre.x, 0.0, centre.y))
			var biome: int = terrain.biome_at(centre.x, centre.y)
			# The rule, restated from the two pure public functions and the table —
			# the river arm first, because that is the arm the owner named ("river
			# - crocodile") and it overrides whatever band the station stands in.
			var want := "crocodile"
			if not in_river and _biome_boss.has(biome):
				want = String(_biome_boss[biome].get("species", ""))
			if not _species_table.has(want):
				# Already reported by name in _check_dispatch_map; guarded again so
				# this loop cannot index a missing row and die mid-walk, which
				# would skip _report() and exit 0 with no verdict at all.
				continue

			# THE ONE CHUNK THAT CAN SPAWN THIS BOSS is the one holding its first
			# candidate — that is the claim rule in spawn_bosses_in_chunk, and it
			# is what makes generating a single chunk here equivalent to walking
			# the whole field. A boss whose candidates are all buried simply does
			# not appear, which is a designed outcome, not a failure.
			var boss: Dictionary = terrain._boss_at(i)
			var parent := _generate_chunk(terrain, terrain.world_to_chunk(boss["positions"][0]))
			for child in parent.get_children():
				if String(child.name) != "BossCrocodile_%d" % i:
					continue
				measured += 1
				bands[biome] = int(bands.get(biome, 0)) + 1
				kinds[want] = int(kinds.get(want, 0)) + 1
				if in_river:
					rivers += 1
				var got: String = String(child.get("species"))
				var spec: Variant = child.get("spec")
				# THE CALL-ORDER DETECTOR, AND IT COMPARES THE WHOLE ROW.
				#
				# `species` is a plain public field, so a body whose species was
				# assigned AFTER add_child still REPORTS the right name — what is
				# wrong is `spec`, which _ready() resolved from whatever the field
				# held at the time (nothing, i.e. the crocodile). So the name half
				# above cannot see the violation at all; only the resolved row can.
				#
				# It used to compare `chase_speed` alone, and that was blind for any
				# boss row that happens to share the crocodile's 5.5 — which is
				# EXACTLY what a boss row is likely to do, since a boss overrides its
				# row's chase speed with BOSS_CHASE_SPEED and the row's own number is
				# hygiene rather than gameplay (see SPECIES["green_dragon"]). Measured
				# on 2026-08-29: with the assignment moved below add_child, the
				# one-key version killed the 5 titans (3.0 != 5.5) and let all 5 green
				# dragons through. Hashing the whole dictionary makes the check exact
				# for every row present and future, including one that is a crocodile
				# in every number but its behaviour string.
				var want_row: Dictionary = _species_table[want]
				var row_matches: bool = (spec is Dictionary
						and (spec as Dictionary).hash() == want_row.hash())
				# Still reported as a speed, because that is the readable half of the
				# difference and the one a human can act on.
				var want_speed: float = float(want_row["chase_speed"])
				var got_speed: float = (float(spec["chase_speed"])
						if spec is Dictionary and spec.has("chase_speed") else NAN)
				if got != want:
					mismatches += 1
					if worst == "":
						worst = ("seed %d boss %d (station %d, %s biome%s) is"
								+ " species '%s', expected '%s'") % [run_seed, i,
								i * _boss_interval,
								_biome_name(Vector3(centre.x, 0.0, centre.y), terrain),
								", in a river" if in_river else "", got, want]
				elif not row_matches:
					mismatches += 1
					if worst == "":
						worst = ("seed %d boss %d says species '%s' but resolved a"
								+ " DIFFERENT row (its chase_speed is %s, the table's"
								+ " is %s) — `species` was assigned AFTER add_child()"
								) % [run_seed, i, got, got_speed, want_speed]
			parent.free()

	print("boss dispatch: %d of %d road bosses reached the world across %d biome"
			% [measured, offered, bands.size()]
			+ " band(s); %d of their stations stand in a river; BIOME_BOSS has %d"
					% [rivers, _biome_boss.size()]
			+ " row(s); kinds spawned %s" % kinds)

	if mismatches > 0:
		_fail("%d of %d road bosses are not the species the dispatch names for"
				% [mismatches, measured]
				+ " their OWN STATION's centre — the boss kind is no longer a pure"
				+ " function of the boss index, so two peers sharing a run_seed put"
				+ " different animals on the same road. First: %s" % worst)
	if measured < BOSS_DISPATCH_MIN_MEASURED:
		_fail("only %d of %d road bosses actually spawned, under the %d floor —"
				% [measured, offered, BOSS_DISPATCH_MIN_MEASURED]
				+ " either the dispatch verdict above was taken over almost"
				+ " nothing, or something (a bigger BOSS_MAX_SCALE, a wider"
				+ " BOSS_FOOTPRINT_RADIUS_PER_SCALE, a new prop crowding the road)"
				+ " is quietly deleting bosses in spawn_bosses_in_chunk's"
				+ " clearance walk. Widen BOSS_LATERAL_MAX / BOSS_PLACE_TRIES, or"
				+ " lower this floor deliberately")
	if bands.size() < BOSS_DISPATCH_MIN_BANDS:
		_fail("the %d bosses measured stand in only %d biome band(s) %s — the"
				% [measured, bands.size(), bands.keys()]
				+ " dispatch was asked the same question every time, so a rule that"
				+ " ignored the band entirely would have passed")
	# The river arm is the one the owner stated in words ("river - crocodile") and
	# the one the band lookup can never reach, since it overrides the band. If no
	# station in the whole walk stands in water, that arm shipped unmeasured —
	# which is a coverage failure of THIS check, not of the code it measures, and
	# the fix is a longer walk or a different seed in RUN_SEEDS.
	if rivers < 1:
		_fail("not one of the %d bosses measured owns a station in a river —" % measured
				+ " the river arm of the dispatch was never asked, so nothing here"
				+ " covers the rule that water stays the crocodile's")
	# EVERY BIOME_BOSS ROW MUST ACTUALLY REACH THE WORLD, the same gate the
	# species sweep applies to BIOME_SPECIES. The loop above verifies the rule
	# wherever it is asked, which is silently vacuous for a band no station in
	# this walk happens to stand in: the row would be a boss kind that exists in
	# the source, loads, passes every table check, and has never once been on a
	# road. If this fires the fix is a longer walk (BOSS_DISPATCH_COUNT) or
	# another seed, not a weaker assertion.
	for biome_v: Variant in _biome_boss:
		var kind: String = String(_biome_boss[biome_v].get("species", ""))
		if not kinds.has(kind):
			_fail("BIOME_BOSS[%s] dispatches to '%s', but not one of the %d bosses"
					% [biome_v, kind, measured] + " this walk placed was one — the"
					+ " row was never exercised, so its whole dispatch is untested"
					+ " (lengthen the walk or change a run seed)")
	Sentinel.done("boss_dispatch")


# ============================================================================
# THE COVERAGE VERDICT — every biome visited, every species actually spawned
# ============================================================================

func _check_coverage() -> void:
	"""
	The gate that makes this file's title true: ALL SIX BIOMES, ALL SIX SPECIES.

	Everything above measures whatever the sweep happened to produce. This is what
	says the sweep produced all of it — and it is stated against the `Biome` enum
	and the `BIOME_SPECIES` map rather than a list here, so the seventh predator
	is demanded of the field the day its row lands, and a band nobody put a
	predator in is reported instead of quietly skipped.

	Taken over the UNION of the run seeds, not per seed: one 289-chunk field
	legitimately misses a band (seed 12345 contains no snow at all, which is a
	fact about the biome noise, not a bug). What may not happen is the WHOLE run
	missing one — the fix for that is another entry in RUN_SEEDS, and the failure
	message says so.
	"""
	var missing_biomes: Array[String] = []
	for name_v: Variant in _biomes:
		if not _biomes_seen_all.has(int(_biomes[name_v])):
			missing_biomes.append(String(name_v))
	if not missing_biomes.is_empty():
		_fail("no chunk of any run seed landed in %s — obstacle avoidance and"
				% str(missing_biomes) + " species dispatch were never measured in"
				+ " those bands. Add a run seed to RUN_SEEDS until they appear")

	var want := { "crocodile": true }
	for biome_v: Variant in _biome_species:
		want[String(_biome_species[biome_v].get("species", ""))] = true
	var missing_species: Array[String] = []
	for name_v: Variant in want:
		if not _species_seen_all.has(String(name_v)):
			missing_species.append(String(name_v))
	if not missing_species.is_empty():
		_fail("%s is dispatched by BIOME_SPECIES but never spawned in any field —"
				% str(missing_species) + " every measurement in this file skipped"
				+ " it, so it ships unmeasured. Add a run seed to RUN_SEEDS")

	# Check 10 is driven off the sweep, one probe on the first body of each
	# species — so "every dispatched species spawned" and "every dispatched
	# species had its multiplayer contract measured" are the same statement only
	# as long as the probe is actually wired into the loop. Stated separately
	# because that wiring is one `if` and this is what notices it going away.
	var unprobed: Array[String] = []
	for name_v: Variant in want:
		if not _mp_probed.has(String(name_v)):
			unprobed.append(String(name_v))
	if not unprobed.is_empty():
		_fail("%s never reached the multiplayer contract probe (check 10) —"
				% str(unprobed) + " their node names and state bytes are unmeasured,"
				+ " so a peer may not be able to address or pose them at all")

	print("coverage: %d biomes visited, %d species multiplayer-probed, ground"
			% [_biomes_seen_all.size(), _mp_probed.size()]
			+ " predators by species over all seeds %s" % _species_seen_all)
	Sentinel.done("coverage")


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
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
				# EVERY SHAPE AS ITS BOUNDING BOX, whatever create_box hung there.
				# Since bead godot-test1-y1o.10 a near-round SPHERE / CYLINDER entry
				# collides as a SphereShape3D / CylinderShape3D
				# (ChunkBatch.collision_shape_for), so a bare `as BoxShape3D` reads
				# null here and this loop would crash on `.size` the day a landmark
				# builder put a boulder in a swept chunk. The bounding box is the
				# right reduction for THIS check: it is a superset of the round
				# collider, so "no crocodile spawns inside stone" stays conservative.
				var half := _shape_half_extents(shape_node.shape)
				# The shape carries the block's chunk-local transform (create_box
				# assigns it whole); lift it to world so neighbours are comparable.
				var world := Transform3D(shape_node.transform.basis,
						shape_node.transform.origin + origin)
				solids.append({ "inv": world.affine_inverse(), "half": half })
			solid_count += solids.size()

			chunk_solids[chunk_pos] = solids
			chunk_obstacles[chunk_pos] = obstacles
			chunk_platforms[chunk_pos] = platforms
			parent.free()
			body.free()

	# ---- pass 2: spawn the crocodiles and measure ---------------------------
	var counts := { "ground": 0, "platform": 0, "boss": 0, "hunter": 0 }
	var worst_depth := 0.0
	var worst_desc := ""
	var in_stone := 0
	# Broken down by SPECIES, because "N crocodiles in stone" over a six-predator
	# world does not say whether the clearance rule broke everywhere or one
	# animal's footprint outgrew it — and those are different bugs.
	var in_stone_by_species := {}
	# The hunter's two OWN rejections, measured separately because they are new
	# code on a new stream: a river skip and a spawn-bubble skip that the crocodile
	# spawner has had for a long time and this spawner had to re-earn. Counted for
	# hunters only — the crocodile's versions are not this bead's subject and a
	# blanket tally would bury a hunter regression under 2800 other bodies.
	var hunters_wet := 0
	var hunters_in_bubble := 0
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
			# Which bands this field actually contains — the raw material of the
			# coverage verdict, and the reason it is taken over the union of the
			# seeds rather than per seed (see _check_coverage).
			_biomes_seen_all[int(terrain.biome_at(origin.x, origin.z))] = true

			terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
			terrain.spawn_platform_crocodiles(chunk_pos, parent, chunk_platforms[chunk_pos])
			terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)
			# THE HUNTER JOINS THIS SWEEP rather than getting a file of its own —
			# the house rule this check states at the top. Its own spawner, its own
			# stream, and exactly the same three questions asked of it: not in
			# stone, not in a river, not in the spawn bubble.
			terrain.spawn_hunters_in_chunk(chunk_pos, parent, obstacles)

			for child in parent.get_children():
				var node_name := String(child.name)
				var kind := ""
				if node_name.begins_with("Crocodile_"):
					kind = "ground"
				elif node_name.begins_with("PatrolCrocodile_"):
					kind = "platform"
				elif node_name.begins_with("BossCrocodile_"):
					kind = "boss"
				elif node_name.begins_with("Hunter_"):
					kind = "hunter"
				else:
					# THE FOUR PREFIXES ARE THE WHOLE NAMING SCHEME, and every
					# species shares them (see _check_mp_contract). Anything in
					# group "crocodile" wearing another name is a body this file
					# would silently stop measuring AND a body no peer can
					# address — one bug with two faces, so it is caught by the
					# classifier rather than by a count that quietly went down.
					if child.is_in_group("crocodile"):
						_fail("seed %d: chunk %s spawned '%s', which is in group"
								% [run_seed, chunk_pos, node_name]
								+ " \"crocodile\" but carries none of the four"
								+ " deterministic name prefixes — croc_id_for()"
								+ " cannot address it and this sweep cannot see it")
					continue
				counts[kind] = int(counts[kind]) + 1
				# Set by the ground branch below; drives the once-per-species
				# multiplayer probe at the end of this loop body.
				var resolved_species := ""

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
					# A dispatch entry naming a row that is not in SPECIES is
					# already reported once, by name, in _check_species_table.
					# Guarded again HERE only so the sweep does not index a
					# missing row and die mid-field: a script error before
					# _report() means quit() is never reached and the process
					# exits 0 with no verdict — the green lie this file exists
					# to avoid, arrived at by way of a correct failure.
					if not _species_table.has(want):
						continue
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
					_species_seen_all[got] = int(_species_seen_all.get(got, 0)) + 1
					resolved_species = got

				# THE SAME CALL-ORDER QUESTION, asked of the hunter's own spawner.
				# It is NOT the ground branch above and must not be folded into it:
				# a hunter is dispatched on nothing (it belongs to no band), so
				# there is no _expected_species to compare against — what there is
				# instead is a single fixed answer, endless_terrain.HUNTER_SPECIES.
				# The `spec` half is identical and is the half that matters:
				# assign `species` after add_child() and the field says
				# "hunter_robot" while every speed, feeler and animation stays a
				# crocodile's, which is invisible from the outside.
				elif kind == "hunter":
					var got_h: String = String(child.get("species"))
					var spec_h: Variant = child.get("spec")
					if got_h != _hunter_species:
						species_mismatches += 1
						if species_worst == "":
							species_worst = "%s is species '%s', expected the hunter's '%s'" % [
									node_name, got_h, _hunter_species]
					elif _species_table.has(_hunter_species):
						var want_h: float = float(_species_table[_hunter_species]["chase_speed"])
						var got_hs: float = (float(spec_h["chase_speed"])
								if spec_h is Dictionary and spec_h.has("chase_speed") else NAN)
						if not is_equal_approx(got_hs, want_h):
							species_mismatches += 1
							if species_worst == "":
								species_worst = ("%s says species '%s' but resolved a spec with"
										+ " chase_speed %s, not the table's %s — `species` was"
										+ " assigned AFTER add_child()") % [
										node_name, got_h, got_hs, want_h]
					_species_seen_all[got_h] = int(_species_seen_all.get(got_h, 0)) + 1
					resolved_species = got_h

				var world_pos: Vector3 = (child as Node3D).global_position
				if kind == "hunter":
					if terrain.is_river_at(world_pos):
						hunters_wet += 1
					if Vector2(world_pos.x, world_pos.z).length() < _spawn_safe_radius:
						hunters_in_bubble += 1
				var depth := _depth_in_stone(chunk_solids, chunk_pos, world_pos)
				if depth > EPSILON:
					in_stone += 1
					var label: String = resolved_species if resolved_species != "" else kind
					in_stone_by_species[label] = int(in_stone_by_species.get(label, 0)) + 1
					if depth > worst_depth:
						worst_depth = depth
						worst_desc = "%s %s %s at %v" % [kind, resolved_species, node_name, world_pos]

				# CHECK 10, once per species and LAST in this loop body — it
				# drives set_remote_state(), which moves the body, so it has to
				# run after every measurement taken off this one's position.
				if resolved_species != "" and not _mp_probed.has(resolved_species):
					_mp_probed[resolved_species] = true
					_check_mp_contract(child, resolved_species, chunk_pos,
							"%s_%d_%d_" % ["Hunter" if kind == "hunter" else "Crocodile",
									chunk_pos.x, chunk_pos.y])

			parent.free()

	if hunters_wet > 0:
		_fail("seed %d: %d of %d hunters are standing in a RIVER — spawn_hunters_in_chunk's"
				% [run_seed, hunters_wet, counts["hunter"]]
				+ " is_river_at rejection is not firing")
	if hunters_in_bubble > 0:
		_fail("seed %d: %d of %d hunters are inside the SPAWN_SAFE_RADIUS bubble — a"
				% [run_seed, hunters_in_bubble, counts["hunter"]]
				+ " predator with the table's widest detection radius would be chasing"
				+ " on frame one of a fresh boot")

	if in_stone > 0:
		_fail("seed %d: %d of %d enemies spawned INSIDE solid stone, by species %s"
				% [run_seed, in_stone, counts["ground"] + counts["platform"] + counts["boss"],
				   in_stone_by_species]
				+ " (worst %.2f m deep: %s)" % [worst_depth, worst_desc])

	if species_mismatches > 0:
		_fail("seed %d: %d of %d dispatched predators did not resolve the species they owe"
				% [run_seed, species_mismatches, counts["ground"] + counts["hunter"]]
				+ " (a ground body owes its chunk's biome, a hunter owes HUNTER_SPECIES)"
				+ " — first: %s" % species_worst)
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
	if counts["hunter"] < 1:
		_fail("seed %d: the sweep spawned no hunters at all over %d chunks — every hunter"
				% [run_seed, (FIELD + 1) * (FIELD + 1)]
				+ " measurement above (stone, river, spawn bubble, call order, MP identity)"
				+ " is trivially true of a spawner that produced nothing")
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
	print("seed %d: measured %d ground / %d platform / %d boss crocodiles / %d hunters against %d collision shapes, plus %d angle probes over %d platforms (%d humped)"
			% [run_seed, counts["ground"], counts["platform"], counts["boss"], counts["hunter"], solid_count,
			   platforms_seen * PLATFORM_ANGLE_SAMPLES, platforms_seen, humped_platforms])
	print("seed %d: ground predators by species %s" % [run_seed, species_seen])


func _shape_half_extents(shape: Shape3D) -> Vector3:
	"""
	Half the AABB of any shape `ChunkBatch.create_box` can hang on a chunk body.

	Deliberately a LOCAL helper and not a public seam on ChunkBatch: the shipped
	game never reads a chunk's collision shapes back, only this sweep does, and a
	one-caller inverse of collision_shape_for() belongs beside its caller. An
	unknown shape answers ZERO rather than guessing — a zero half-extent contains
	nothing, so a shape this file does not understand can never silently PASS a
	crocodile that is standing in it; the sweep just stops testing against that
	one piece of stone, and check 4's solid_count still prints how many it saw.
	"""
	var box := shape as BoxShape3D
	if box != null:
		return box.size * 0.5
	var sphere := shape as SphereShape3D
	if sphere != null:
		return Vector3.ONE * sphere.radius
	var cyl := shape as CylinderShape3D
	if cyl != null:
		return Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
	return Vector3.ZERO


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
	"""
	The chunk's biome as a readable name, for failure messages only.

	Reverse-looked-up out of the real `Biome` enum rather than a list here — a
	seventh band would otherwise print as a bare integer in exactly the message
	someone reads while trying to work out which band broke.
	"""
	var biome: int = terrain.biome_at(chunk_centre.x, chunk_centre.z)
	for name_v: Variant in _biomes:
		if int(_biomes[name_v]) == biome:
			return String(name_v)
	return str(biome)


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
