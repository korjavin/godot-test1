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
## never spawned fails, and a `behavior` string with no probe in this file fails
## by name. The SEVENTH predator is covered the day its row lands.
##
##   godot --headless --path . --script res://scripts/enemy_spawn_selfcheck.gd
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
## Cost: ~1.2 s for 2 seeds x 289 chunks plus a 49-chunk determinism field — the
## same order as the single-species version it grew out of, because the added
## coverage is per SPECIES (six probes) and not per body. Don't grow it into a
## suite; if a fourth spawner appears it belongs in the sweep, not in a new file,
## and a seventh species should cost it nothing at all.
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

## The SLOWEST character's run — RUN_SPEED x the smallest CHARACTER_SPEED, both
## read off player_controller.gd in _run(). This is the number MAX_CHASE_SPEED is
## held under so that "running always escapes" is true, and check 8 races a burst
## predator's whole pounce/recovery cycle against it. Derived rather than written
## down as 9.0 because a new character with a lower speed stat would move it, and
## a check asserting a stale 9.0 would pass while the promise quietly broke.
var _slowest_run_speed: float = 0.0


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


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
	_boss_detection_radius = float(croc_consts.get("BOSS_DETECTION_RADIUS", 0.0))
	_boss_chase_speed = float(croc_consts.get("BOSS_CHASE_SPEED", 0.0))
	_boss_territory_radius = float(croc_consts.get("BOSS_TERRITORY_RADIUS", 0.0))
	var player_consts: Dictionary = load(PLAYER_SCRIPT).get_script_constant_map()
	_walk_speed = float(player_consts.get("WALK_SPEED", 0.0))
	# The slowest run, derived the way player_controller derives it (see
	# _slowest_run_speed). An empty table would leave this 0.0, which check 8
	# reports as a failure rather than passing vacuously against a zero ceiling.
	var character_speed: Dictionary = player_consts.get("CHARACTER_SPEED", {})
	var slowest_scale: float = INF
	for name_v: Variant in character_speed:
		slowest_scale = minf(slowest_scale, float(character_speed[name_v]))
	if slowest_scale < INF:
		_slowest_run_speed = float(player_consts.get("RUN_SPEED", 0.0)) * slowest_scale
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
			target = croc_ai.charge_steer_point(quarry, pos, lock, commit)
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
		var factor: float = croc_ai.burst_cycle_factor(pos, lock, row)
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
		var factor: float = croc_ai.burst_cycle_factor(pos, lock, probe_row)
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
		if croc_ai.ranged_shot_due(distance, RANGED_PROBE_DT, lock, ranged):
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
		var target: Vector3 = croc_ai.hunt_steer_point(quarry, pos, closing, standoff)
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
	var airtime: float = croc_ai.leap_airtime(row)
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
	var reach: float = croc_ai.leap_reach(_max_chase_speed, row)
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
	var airtime: float = croc_ai.leap_airtime(probe_row)

	var pos := Vector3.ZERO
	var quarry := Vector3(0.0, 0.0, BURST_RACE_GAP)
	var lock: Dictionary = {}
	var airborne_left: float = 0.0
	var hops: int = 0
	var steps := int(BURST_RACE_SECONDS / BURST_RACE_DT)
	for _step in range(steps):
		var grounded: bool = airborne_left <= 0.0
		var launched: bool = croc_ai.leap_due(grounded, landing_ok, BURST_RACE_DT,
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
