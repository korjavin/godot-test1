extends SceneTree
## ============================================================================
## BOSS TERRITORY SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS. A boss is a MODIFIER on a species, so both rules pinned here
## are inherited by every boss kind that follows the crocodile — and both fail
## SILENTLY, in the two ways this project's rules fail worst:
##
##   1. THE LEASH IS A NEGATIVE. "The boss never leaves its area" is invisible
##      while it holds and only shows up as a boss that followed you across half
##      a biome, three chunks after the mistake. Nothing errors, nothing logs.
##      Worse, the interesting case is not "quarry far away" (detection already
##      handles that) but "quarry 15 m from the boss and OUTSIDE the circle" —
##      the boss can smell you fine and must refuse anyway. Check 3 parks the
##      player exactly there, which is the case a hand-written radius test in the
##      wrong place (against the local player rather than the chosen
##      `chase_target`, or below the behaviour dispatch instead of above it) gets
##      wrong while still looking correct in play.
##
##   2. CRUSH IMMUNITY IS AN ORDERING. `_on_player_collision` early-returns for
##      is_boss ABOVE the giant-Teibi crush block; swap those two blocks and
##      giant Teibi one-shots the game's biggest threat with no error anywhere.
##      Check 7 pins the order — with a NON-boss negative control, because "the
##      boss survived" is also true of a stub that never crushed anything.
##
##   2b. A HOP IS A NEGATIVE TOO, TWICE OVER. "The winged bosses leave the
##      ground" fails as a body that reads exactly like the heavy quadruped it was
##      — no error, no log, the arm running perfectly and setting a velocity
##      nothing ever gets to use — and "a hop does not clear the fence" fails the
##      way the leash does, three chunks later. Check 9 drives both against a real
##      boss on a real slab, because the arm is the one in this file that depends
##      on `is_on_floor()` and `velocity`: no amount of pure probing in
##      enemy_spawn_selfcheck can tell a launch that happens from one that is
##      computed. It also drives the pre-launch territory gate DIRECTLY, with a
##      positive control at the same geometry, the way check 8 drives the ranged
##      one.
##
##   3. ROW IMMUNITY IS THE SAME TWO GUARDS, ONE STEP OUT. `stink_immune` and
##      `crush_immune` let a row opt out of Phoboman's wave and giant Teibi's
##      squash, and they fail exactly as silently: a dropped guard is an armoured
##      machine that pops underfoot, a stray key is an ordinary crocodile nobody
##      can kill. Check 8 drives EVERY row in SPECIES through both real code
##      paths and asserts the outcome the row asked for — so the animals are the
##      negative control, for free, and a future immune species is covered the
##      day its row lands. It lives in THIS file because these two guards sit
##      beside the is_boss guards check 7 already owns; enemy_spawn_selfcheck
##      owns spawning, not collision.
##
## The const chain (check 1) is a cross-file inequality nothing else guards:
## BOSS_DETECTION_RADIUS <= BOSS_TERRITORY_RADIUS < crocodile_lod_manager's
## SIM_RADIUS. Break the left link and a boss growls at a quarry it is forbidden
## to walk to; break the right one and a boss can be asleep inside its own zone.
##
## Harness style follows wade_selfcheck: a real physics world (a slab to stand
## on), a real boss instantiated from its real scene with setup_as_boss() called
## BEFORE add_child, and a scripted stand-in for the player.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const CROC_SCRIPT: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")
## The boss dispatch map, so EVERY boss kind the world can spawn is driven
## through the checks below instead of the crocodile standing in for all of them.
## Read from the file that owns it for the same reason SIM_RADIUS is: a boss is a
## MODIFIER on a species, so "the leash and the crush immunity are inherited" is a
## claim about kinds nobody has written yet, and the only way to keep it true is
## to iterate the table rather than a list in here. A new row is covered the day
## it lands (see _subjects()).
const TERRAIN_SCRIPT: GDScript = preload("res://scripts/endless_terrain.gd")
## Read from the file that OWNS it — the whole point of check 1 is that the
## crocodile's territory and the LOD manager's sleep radius must stay in step,
## and re-typing 45.0 here would make the check pass through a copy of the bug.
const LOD_SCRIPT: GDScript = preload("res://scripts/crocodile_lod_manager.gd")

const TERRITORY_RADIUS: float = CROC_SCRIPT.BOSS_TERRITORY_RADIUS
const DETECTION_RADIUS: float = CROC_SCRIPT.BOSS_DETECTION_RADIUS
const SIM_RADIUS: float = LOD_SCRIPT.SIM_RADIUS

## Body scale for the test boss. The terrain's schedule hands out 3.75x–9x; a
## middling one keeps the capsule from dominating the distances measured here.
## Deliberately NOT the cap: check 7 already measures the footprint promise
## against BOSS_MAX_SCALE arithmetically, and a 9x capsule here would swamp the
## 25/32/45 m radii checks 1-6 are actually about.
const BOSS_SCALE: float = 3.0

## Any fixed seed: it makes the WANDER stream deterministic (a boss takes no
## size/speed roll, so that is all it does here), which is what keeps check 6's
## fence walk from being a coin flip on rng.randomize().
const BOSS_ROLL_SEED: int = 20260828

## Frames to let a freshly added body fall onto the slab and run its deferred
## _ready()/_find_player(). Same number, same reason, as wade_selfcheck.
const SETTLE_FRAMES: int = 30

## Frames per simulated phase. 240 @ 60 Hz = 4 s — long enough for a boss at
## BOSS_CHASE_SPEED (7 m/s) to cross its whole territory twice over, which is
## what makes "it never got out" mean something.
const PHASE_FRAMES: int = 240

## Containment tolerance (metres). The clamp pulls the body back onto the circle
## with no epsilon at all, so this is pure float slop; anything the leash misses
## is metres out, not centimetres.
const CONTAIN_EPS: float = 0.05

## How much closer the boss must get to a quarry inside its territory for
## "it HUNTS" to be proven rather than merely "it did not run away". At 7 m/s
## over 4 s it should close ~15 m; 3 m is far outside any drift or turn lag.
##
## IT IS ALSO WELL UNDER WHAT THE SLOWEST BOSS KIND MANAGES, which matters now
## that every BIOME_BOSS kind is driven through here: the snow titan chases at
## 3 m/s (an archer, deliberately under a walking player) and still closes ~12 m
## in the window. A kind slow enough to fail this is not a boss that hunts.
const HUNT_CLOSE_MIN: float = 3.0

## How far the boss must travel after disengaging for "it still wanders" to be
## proven. Wander speed is ~2 m/s, so 4 s is ~8 m even with pauses and turns.
const WANDER_MIN: float = 2.0

## How long the ranged phase runs, in physics frames. 300 @ 60 Hz = 5 s, which is
## one full `fire_cooldown` plus most of a second: long enough that a cadence
## bug (an archer that fires every frame) cannot hide inside the per-shooter
## `max_live` cap, and short enough that a titan closing at its own 3 m/s is
## still inside its firing band when the window ends.
const RANGED_FRAMES: int = 300

## Float slack on the resolved chase speed, in m/s. The comparison is against a
## number the row states, so this is pure representation noise.
const SPEED_EPS: float = 0.01

## How long the leap phase runs, in physics frames. 600 @ 60 Hz = 10 s, which is
## two full hop cycles for either winged boss (4.8 s for the dragon, 5.8 s for the
## roc) — long enough that a cadence bug shows up as hundreds of launches rather
## than as an off-by-one, and short enough that the whole file stays quick.
const LEAP_FRAMES: int = 600

## The share of its own declared apex a hop must actually reach for the launch to
## count as one. Half, deliberately loosely: the arc is measured through a real
## physics tick against a real collision capsule, and a boss that lands its bite
## mid-air takes a `_pause_and_change_direction` window during which the arm does
## not run at all and the body falls under the file's own GRAVITY (measured: a
## dragon reaches 3.10 m of its declared 3.56). So this is a guard against a hop
## that DOES NOT HAPPEN, or one a row tuned to a 4 cm bounce — the ARC itself is
## pinned by the airtime tolerance below, which the bite window does not blur.
const LEAP_APEX_FRACTION: float = 0.5

## How far the longest COMPLETE arc's measured airtime may sit from the one the
## row's two constants imply (2 x launch / gravity). The measurement is clean —
## a dragon's 1.78 s against a declared 1.778, a roc's 2.27 s against 2.25 — so
## 15% is far outside anything the physics tick or the bite window produces, and
## comfortably inside the 18% error an arc falling under the file's GRAVITY
## instead of the row's would show. It is the tightest thing this phase asserts,
## and deliberately: the airtime is the ONLY output of `leap_gravity` that
## `leap_reach` (and therefore the leash gate) is computed from.
const LEAP_AIRTIME_TOLERANCE: float = 0.15

## Slack, in launches, on the hop count a phase may show above the cadence its row
## allows. Two: the window is not a whole number of cycles and the first hop fires
## on the acquisition frame. A clock that is never re-armed launches on every
## grounded frame, so the failure this bounds is three orders of magnitude out.
const LEAP_HOP_SLACK: int = 2


## The baseline predator, named on purpose. Everything in check 8 is read off
## the row under test, which means a row that turned immune BY MISTAKE would be
## measured as correct — so the game's ordinary enemy is anchored by name: it
## must carry neither key, and any edit that gives it one fails here rather than
## quietly shipping a crocodile nobody can kill.
const BASELINE_SPECIES: String = "crocodile"

## The two row keys check 8 drives. Iterated rather than spelled out twice
## because both are the same claim about the same table.
const IMMUNITY_KEYS: PackedStringArray = ["stink_immune", "crush_immune"]

var _failures: Array[String] = []

## Which boss kind the current phase is measuring, for the failure messages. A
## file that runs every check over N species has to say WHICH one broke, and
## prefixing in _fail() is cheaper than threading a label through twenty calls.
var _subject: String = ""


## The player stand-in. Deliberately a plain Node3D and NOT a CharacterBody3D:
## `_update_chase_state` asks the quarry `is_on_floor()` and a CharacterBody3D
## that never ran move_and_slide answers false, i.e. "jumped", i.e. unsmellable —
## every chase check below would then pass vacuously. This answers the one
## question the AI asks, and carries the two methods `_on_player_collision`
## dispatches on so check 7 can drive the crush ordering directly.
class StubPlayer:
	extends Node3D
	## Flipped by check 7 only; the chase checks want an ordinary player.
	var giant: bool = false
	var bitten: int = 0

	func is_on_floor() -> bool:
		return true

	func crushes_crocodiles() -> bool:
		return giant

	func hit_by_crocodile(_attacker: Node = null) -> void:
		bitten += 1


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there — reporting here would print a verdict at frame 0.
	_run()


func _fail(message: String) -> void:
	_failures.append(message if _subject.is_empty() else "[%s] %s" % [_subject, message])


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _flat_distance(a: Vector3, b: Vector3) -> float:
	"""XZ distance — the axes the territory is measured on (the world is flat)."""
	return Vector2(a.x - b.x, a.z - b.z).length()


func _assert_contained(boss: CharacterBody3D, home: Vector3, phase: String) -> void:
	"""Containment is asserted in EVERY phase, not just the leash one — a boss
	that slips out while hunting a quarry inside its area is the same bug."""
	var out := _flat_distance(boss.global_position, home)
	if out > TERRITORY_RADIUS + CONTAIN_EPS:
		_fail("%s: boss is %.2f m from home, territory is %.1f m"
				% [phase, out, TERRITORY_RADIUS])


func _subjects() -> Array[Dictionary]:
	"""
	Every boss kind the world can spawn: the crocodile (the fallback every
	entry-less biome and every river station takes) plus one entry per BIOME_BOSS
	row, deduplicated by species.

	@return [{ "species": String, "scene": String }], crocodile first

	NOTHING HERE NAMES THE TITAN, and that is the point — the same rule
	enemy_spawn_selfcheck follows. Both boss rules this file pins (the leash, the
	crush ordering) are properties of BOSS-NESS and are inherited by every kind,
	so a check that only ever drove the crocodile would keep passing while a new
	kind quietly broke them. A row added to BIOME_BOSS is measured on the commit
	that adds it, with no edit here.
	"""
	var out: Array[Dictionary] = [{ "species": "crocodile", "scene": CROC_SCENE }]
	var seen: Dictionary = { "crocodile": true }
	for biome_v: Variant in TERRAIN_SCRIPT.BIOME_BOSS:
		var row: Dictionary = TERRAIN_SCRIPT.BIOME_BOSS[biome_v]
		var species_name: String = String(row.get("species", ""))
		if species_name.is_empty() or seen.has(species_name):
			continue
		seen[species_name] = true
		out.append({ "species": species_name, "scene": String(row.get("scene", "")) })
	return out


func _run() -> void:
	_check_constants()

	# Something to stand on. The world is flat at y = 0 by invariant, so this is a
	# slab whose TOP is the ground plane — wide enough that a boss roaming its
	# whole territory never runs out of floor and starts falling.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)

	# The quarry goes in FIRST: the boss's _find_player() is call_deferred from
	# _ready(), so a player added afterwards is simply never found and every chase
	# assertion below would pass for the wrong reason.
	var player := StubPlayer.new()
	# `position`, not `global_position`: a node added from _initialize() is not yet
	# is_inside_tree() at this point and global_position errors out — the same trap
	# wade_selfcheck documents. Every later move happens after a frame, so those
	# use global_position normally.
	player.position = Vector3.ZERO
	root.add_child(player)
	player.add_to_group("player")

	# EVERY boss kind, not just the crocodile — see _subjects(). The player stub
	# is shared across them (it is already in the tree, which is what the deferred
	# _find_player() needs); each subject gets its own body at its own spawn spot.
	for subject: Dictionary in _subjects():
		_subject = String(subject["species"])
		var packed: PackedScene = load(String(subject["scene"]))
		if packed == null:
			_fail("could not load %s" % subject["scene"])
			continue
		await _run_subject(packed, String(subject["species"]), player)
	_subject = ""

	await _check_row_immunities(player)

	player.queue_free()
	await _frames(2)
	_report()


func _run_subject(packed: PackedScene, species_name: String, player: StubPlayer) -> void:
	"""
	Every check in this file, against ONE boss kind.

	@param packed: the kind's scene, from BIOME_BOSS (or the crocodile's)
	@param species_name: its SPECIES key — assigned BEFORE setup_as_boss below
	@param player: the shared quarry stub
	"""
	var boss: CharacterBody3D = packed.instantiate()
	# CALL-ORDER CONTRACT, and it is three deep: `species` BEFORE setup_as_boss
	# BEFORE add_child. _ready() resolves `spec` from `species` exactly once and
	# branches on is_boss in the same pass, so an assignment after add_child
	# leaves a body with a crocodile's spec, or one that took the random speed and
	# size rolls a boss must not have — with no error anywhere. This is the same
	# order endless_terrain.spawn_bosses_in_chunk uses, on purpose.
	boss.species = species_name
	boss.setup_as_boss(BOSS_SCALE)
	# Same call-order contract. A boss takes no size/speed roll, so the seed goes
	# unused there (setup_roll_seed says so explicitly) — what it buys HERE is a
	# deterministic wander stream, which is what stops check 6's fence walk from
	# being a coin flip. Without it a boss falls back to rng.randomize().
	boss.setup_roll_seed(BOSS_ROLL_SEED)
	boss.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(boss)
	await _frames(SETTLE_FRAMES)

	if not boss.has_method("in_territory"):
		_fail("boss: no in_territory() on this scene — did the script fail to "
				+ "attach? (a fresh clone needs `godot --headless --path . --import` first)")
		boss.queue_free()
		return
	if not boss.is_boss:
		_fail("boss: setup_as_boss() left is_boss false")
		boss.queue_free()
		return
	if String(boss.species) != species_name:
		_fail("boss: species is '%s' after _ready(), expected '%s' — an unknown "
				% [boss.species, species_name] + "name falls back to the crocodile, "
				+ "so this kind would be measured as one")
		boss.queue_free()
		return

	var home: Vector3 = boss.home_position
	_check_home(boss, home)
	_check_resolved_speed(boss)
	await _check_hunts_inside(boss, player, home)
	_check_model_rigid(boss)
	_check_footprint(boss)
	await _check_hunts_at_fence(boss, player, home)
	await _check_leashed(boss, player, home)
	await _check_wanders_contained(boss, player, home)
	await _check_ranged(boss, player, home)
	await _check_leap(boss, player, home)

	boss.queue_free()
	await _frames(2)
	await _check_crush_immunity(packed, species_name, player)


func _check_constants() -> void:
	"""
	CHECK 1 — the inequality chain, which is the reason the number is 32 and not
	whatever felt right. See BOSS_TERRITORY_RADIUS for what each link buys.
	"""
	if DETECTION_RADIUS > TERRITORY_RADIUS:
		_fail("consts: BOSS_DETECTION_RADIUS (%.1f) > BOSS_TERRITORY_RADIUS (%.1f) — "
				% [DETECTION_RADIUS, TERRITORY_RADIUS]
				+ "a boss could smell a quarry it is forbidden to walk to, and would "
				+ "growl once and then stand still")
	if TERRITORY_RADIUS >= SIM_RADIUS:
		_fail("consts: BOSS_TERRITORY_RADIUS (%.1f) >= LOD SIM_RADIUS (%.1f) — "
				% [TERRITORY_RADIUS, SIM_RADIUS]
				+ "a boss could be asleep inside its own territory")
	Sentinel.done("constants")


func _check_home(boss: CharacterBody3D, home: Vector3) -> void:
	"""
	CHECK 2 — the territory centre is the SPAWN spot, and the seam agrees with it.

	home_position is captured in _ready() from global_position, which the terrain
	guarantees is already the real spawn spot. If that capture ever moves to a
	later frame the centre silently becomes "wherever the boss had wandered to",
	and the leash still looks like it works — it just drifts across the world.
	"""
	if _flat_distance(home, Vector3.ZERO) > CONTAIN_EPS:
		_fail("home: home_position is %s, expected the spawn spot (0,0)" % home)
	if not boss.in_territory(home):
		_fail("seam: in_territory() says the boss's own home is outside its territory")
	# The seam, at both ends of the boundary. A radius accessor wired to the wrong
	# const, or an in_territory() that forgot to subtract home, passes every
	# motion check below by simply never being false.
	var just_in := home + Vector3(TERRITORY_RADIUS - 0.5, 0.0, 0.0)
	var just_out := home + Vector3(TERRITORY_RADIUS + 0.5, 0.0, 0.0)
	if not boss.in_territory(just_in):
		_fail("seam: in_territory() rejects a point %.1f m from home (radius is %.1f)"
				% [TERRITORY_RADIUS - 0.5, TERRITORY_RADIUS])
	if boss.in_territory(just_out):
		_fail("seam: in_territory() accepts a point %.1f m from home (radius is %.1f)"
				% [TERRITORY_RADIUS + 0.5, TERRITORY_RADIUS])
	if absf(boss.territory_radius() - TERRITORY_RADIUS) > CONTAIN_EPS:
		_fail("seam: territory_radius() returned %.2f, expected %.2f"
				% [boss.territory_radius(), TERRITORY_RADIUS])
	Sentinel.done("home")


func _check_hunts_inside(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 3 — inside the territory a boss HUNTS: normal chase, full speed, closes.

	This is the half of the rule that a leash written too aggressively breaks. The
	owner's sharpening was explicit — "bosses limited by area, and hunt you inside
	it" — so a boss that merely patrols and ignores you fails this bead just as
	hard as one that follows you home.

	The quarry is parked at 20 m: inside detection (25) and inside the territory
	(32), and far enough out that closing the gap is a measurable metres-long walk
	rather than turn jitter.
	"""
	player.global_position = home + Vector3(20.0, 0.0, 0.0)
	var before := _flat_distance(boss.global_position, player.global_position)
	await _frames(PHASE_FRAMES)
	var after := _flat_distance(boss.global_position, player.global_position)

	if not boss.is_chasing:
		_fail("hunt: quarry %.1f m away, inside detection (%.1f) and inside the "
				% [after, DETECTION_RADIUS]
				+ "territory (%.1f), and the boss is not chasing" % TERRITORY_RADIUS)
	if before - after < HUNT_CLOSE_MIN:
		_fail("hunt: boss closed only %.2f m in %d frames (needed %.1f) — a boss "
				% [before - after, PHASE_FRAMES, HUNT_CLOSE_MIN]
				+ "inside its own territory must hunt, not patrol")
	_assert_contained(boss, home, "hunt")
	Sentinel.done("hunts_inside")


func _check_hunts_at_fence(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 4 — a quarry hugging the INSIDE of the fence is hunted, and the boss
	still does not cross.

	This is the containment stressor, and it is deliberately a CHASE rather than a
	wander: a chase heading is recomputed toward the target every frame, so unlike
	the wander in check 6 there is no random drift to bleed the outward energy
	away. The boss is aimed at BOSS_CHASE_SPEED (7 m/s) straight at a point half a
	metre inside its own boundary, for four seconds. Delete the steer and the
	clamp and it walks out and keeps going (measured: past 39 m); with them it
	slides along the fence.

	It is also the check for the half of _steer_within_territory's docstring that
	is a GAMEPLAY claim rather than a containment one — a boss must still hunt you
	at the fence. A leash that turned dead-inward at the boundary would send the
	boss home instead, so `is_chasing` is asserted at the end: the quarry is
	legitimately inside the territory and inside detection, and nothing about
	being near the edge may drop it.
	"""
	player.global_position = home + Vector3(TERRITORY_RADIUS - 0.5, 0.0, 0.0)
	var worst := 0.0
	for _i in PHASE_FRAMES:
		await physics_frame
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if worst > TERRITORY_RADIUS + CONTAIN_EPS:
		_fail("fence: boss reached %.2f m from home chasing a quarry %.1f m out, "
				% [worst, TERRITORY_RADIUS - 0.5]
				+ "territory is %.1f m — the quarry was inside, the boss must not be "
				% TERRITORY_RADIUS + "outside")
	if not boss.is_chasing:
		_fail("fence: boss dropped a quarry that is %.1f m from home, i.e. INSIDE "
				% (TERRITORY_RADIUS - 0.5)
				+ "its %.1f m territory — the leash must bound where a boss can go, "
				% TERRITORY_RADIUS + "never how far it can smell")
	Sentinel.done("hunts_at_fence")


func _check_leashed(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 5 — THE LEASH. Quarry parked outside the circle: the boss disengages and
	its own body never crosses the boundary.

	The placement is the check. 40 m from home is outside the territory (32), but
	the boss arrives here from check 4 parked against its own fence, i.e. ~8 m
	from the quarry and so well INSIDE its 25 m detection radius of it — it can
	smell you perfectly and must refuse anyway. Without the leash the ordinary chase code sails straight past the
	boundary, which is exactly today's shipped bug.

	Containment is sampled EVERY frame, not just at the end: a boss that overshot
	to 45 m and walked back would pass an endpoint-only test.
	"""
	player.global_position = home + Vector3(40.0, 0.0, 0.0)
	var worst := 0.0
	for _i in PHASE_FRAMES:
		await physics_frame
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if worst > TERRITORY_RADIUS + CONTAIN_EPS:
		_fail("leash: boss reached %.2f m from home, territory is %.1f m — it left "
				% [worst, TERRITORY_RADIUS] + "its area chasing a quarry outside it")
	if boss.is_chasing:
		var gap := _flat_distance(boss.global_position, player.global_position)
		_fail("leash: boss still chasing a quarry %.1f m from home (territory %.1f); "
				% [_flat_distance(player.global_position, home), TERRITORY_RADIUS]
				+ "it is %.1f m away so detection alone will not drop it" % gap)
	Sentinel.done("leashed")


func _check_wanders_contained(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 6 — after disengaging the boss keeps MOVING ("they walk inside some
	area"), and the PHYSICAL containment holds while it does.

	Two jobs, and the setup is what makes both of them real:

	  * The negative control for check 5. A boss frozen solid at the boundary also
	    never leaves its territory, and would pass the leash check while being a
	    statue.
	  * The only check that exercises _steer_within_territory and
	    _clamp_to_territory AT ALL. Measured (mutation test, 2026-08-28): with the
	    chase gate alone doing the work, deleting BOTH the steer and the clamp
	    still passed every other check in this file — a disengaged boss simply
	    never wandered far enough to meet its own fence inside the window. So the
	    boss is PLANTED one metre inside the boundary and AIMED STRAIGHT OUT
	    (wander_heading and rotation.y both, so there is no turn lag to bleed the
	    energy away) before the window starts. Unleashed it walks clean out to
	    ~39 m; leashed it must slide along the fence and stay in.

	The quarry is teleported far away first so nothing here is a chase — this is
	the boss's own wandering meeting the boundary, with no help from the gate.
	"""
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
	boss.global_position = Vector3(
			home.x + TERRITORY_RADIUS - 1.0, boss.global_position.y, home.z)
	# heading 0 is +Z (see _choose_new_direction), so +X — dead outward — is PI/2.
	boss.wander_heading = PI / 2.0
	boss.rotation.y = PI / 2.0
	var start := boss.global_position
	var travelled := 0.0
	var worst := 0.0
	var previous := start
	for _i in PHASE_FRAMES:
		await physics_frame
		travelled += _flat_distance(boss.global_position, previous)
		previous = boss.global_position
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if travelled < WANDER_MIN:
		_fail("wander: boss travelled %.2f m in %d frames after disengaging "
				% [travelled, PHASE_FRAMES]
				+ "(needed %.1f) — it is pinned against its own fence, not walking "
				% WANDER_MIN + "inside its area")
	if worst > TERRITORY_RADIUS + CONTAIN_EPS:
		_fail("wander: boss reached %.2f m from home while wandering, territory is "
				% worst + "%.1f m" % TERRITORY_RADIUS)
	Sentinel.done("wanders_contained")


## How far the animated model's basis may drift from square, as the largest
## absolute dot product between its normalized columns. 1e-4 is representation
## noise; the smallest shear this can produce is two orders of magnitude bigger
## (a 14-degree chase lean against a 1.6x stretch gives 0.37).
const ORTHO_EPS: float = 1e-4


func _check_model_rigid(boss: CharacterBody3D) -> void:
	"""
	CHECK 6c — the animated model is a RIGID body, however its scene scaled it.

	Called with the boss mid-chase (straight after the hunt phase), so its model
	is carrying a real forward lean and a real waddle roll rather than sitting at
	identity, which is the only state in which this can fail.

	WHAT IT IS FOR. `_animate_body` and `_animate_bite` rebuild the model's basis
	every frame as rotation-then-rest-scale. A rest scale applied in the PARENT's
	axes (`Basis.scaled`) instead of the model's own (`Basis.scaled_local`) is
	identical for a UNIFORM scale — a uniform scale commutes with rotation — and
	is a SHEAR for any other, so the whole class of bug is invisible until the
	first species ships a stretched model. The green dragon was that species when
	this check landed — a crocodile mesh at (1, 1.6, 1) that, under the
	parent-frame composition, would have grown taller in world y instead of along
	its own spine every time it leaned into a chase. The art beads have since
	replaced those placeholders with purpose-built meshes worn at IDENTITY, and
	the clown's phoboman at (0.75, 1, 0.75) is what still carries the case.

	Orthogonality is the exact test rather than a proxy: a rotation scaled along
	its OWN axes keeps mutually perpendicular columns (each is a unit column times
	one factor), and a shear is precisely the loss of that. So this passes for a
	uniform model, passes for a correctly-stretched one, and fails for a sheared
	one — no reference pose to restate and nothing to retune when the numbers
	move. It is asked of every BIOME_BOSS kind, so the uniformly scaled ones (the
	crocodile fallback, the titan, and every purpose-built boss mesh) are its
	negative control and any NON-uniformly scaled scene — the clown today, and
	whatever a future art bead reaches for — is the case that can actually fail
	it. THE COVERAGE IS THE ITERATION, NOT THE LIST: this asks every kind, so it
	keeps its teeth as scenes come and go.
	"""
	var model: Node3D = boss.get_node_or_null("Model")
	if model == null:
		_fail("model: no Model child — every predator scene must have one")
		Sentinel.done("model_rigid")
		return
	var b: Basis = model.transform.basis
	if b.x.is_zero_approx() or b.y.is_zero_approx() or b.z.is_zero_approx():
		_fail("model: a basis column collapsed to zero (%s) — a zero rest scale" % b)
		Sentinel.done("model_rigid")
		return
	var cx: Vector3 = b.x.normalized()
	var cy: Vector3 = b.y.normalized()
	var cz: Vector3 = b.z.normalized()
	var worst: float = maxf(maxf(absf(cx.dot(cy)), absf(cy.dot(cz))), absf(cz.dot(cx)))
	if worst > ORTHO_EPS:
		_fail("model: the animated basis is SHEARED (worst column dot %.4f, scale %s)"
				% [worst, model.scale] + " — `_animate_body` must compose the rest"
				+ " scale with scaled_local (the model's own axes), not scaled"
				+ " (the parent's), or a non-uniformly scaled species distorts"
				+ " every time it leans")
	Sentinel.done("model_rigid")


func _check_footprint(boss: CharacterBody3D) -> void:
	"""
	CHECK 7 — a boss's collision capsule fits inside the clearance the SPAWNER
	reserved for it.

	endless_terrain.spawn_bosses_in_chunk walks obstacle footprints with
	BOSS_FOOTPRINT_RADIUS_PER_SCALE * boss_scale of clearance and places the boss
	only where that circle is clear. The constant is a flat number, not a per-kind
	measurement, so it is a PROMISE EVERY SCENE MAKES and nothing until now made
	the scene keep it: a capsule reaching further than 0.7 m at body scale 1 gets
	placed overlapping a tree or a rock and, at the 9x cap, wedges there.

	THE TRAP IS THE OFFSET, and it has already been hit once (the hydra, PR #125):
	the reach of a LAID capsule is not its radius and not its half-length, it is
	the distance from the BODY's origin to the far cap — the collider's own offset
	PLUS its extent. A mesh whose mass sits forward of its origin spends the 0.7
	twice while every number in its .tscn still looks small. So this measures the
	real thing: a capsule is a segment swept by a sphere, so its two segment
	endpoints are pushed into the body's frame by the collider's own transform and
	the radius is added to whichever is further out horizontally.

	Body scale is deliberately divided out rather than avoided: the boss under test
	is already scaled by setup_as_boss, but a CollisionShape3D's own `transform` and
	its shape are in the SCENE's frame and the terrain's clearance is likewise per
	unit scale, so both sides of the comparison are at scale 1 with nothing to undo.

	It is asked of every kind `_subjects()` yields, so a boss added to BIOME_BOSS is
	measured on the commit that adds it and an art bead that swaps in a bigger mesh
	cannot quietly outgrow its station.
	"""
	var collider: CollisionShape3D = null
	for child: Node in boss.get_children():
		if child is CollisionShape3D:
			collider = child
			break
	if collider == null:
		_fail("footprint: no CollisionShape3D on this scene — a boss with no body "
				+ "is neither solid nor placeable")
		Sentinel.done("footprint")
		return
	var capsule := collider.shape as CapsuleShape3D
	if capsule == null:
		_fail("footprint: collision shape is %s, not a CapsuleShape3D — this check "
				% collider.shape + "measures a swept segment and cannot judge it")
		Sentinel.done("footprint")
		return

	# The capsule's segment: half its cylinder, along the collider's own +Y, from
	# the collider's own origin. Both endpoints are taken because a rotated
	# collider aims that axis anywhere, and `maxf(0.0, ...)` because a capsule
	# whose height is at most two radii is a sphere with a degenerate segment.
	var half_axis: float = maxf(0.0, capsule.height * 0.5 - capsule.radius)
	var axis: Vector3 = collider.transform.basis.y.normalized() * half_axis
	var here: Vector3 = collider.transform.origin
	var reach: float = 0.0
	for end_point: Vector3 in [here + axis, here - axis]:
		reach = maxf(reach, Vector2(end_point.x, end_point.z).length())
	reach += capsule.radius

	var budget: float = TERRAIN_SCRIPT.BOSS_FOOTPRINT_RADIUS_PER_SCALE
	if reach > budget:
		_fail("footprint: capsule reaches %.3f m horizontally at body scale 1, "
				% reach + "over BOSS_FOOTPRINT_RADIUS_PER_SCALE (%.2f) — the "
				% budget + "spawner clears only %.2f m per unit scale, so this "
				% budget + "kind gets placed overlapping a prop and wedges in it "
				+ "at the 9x cap. Shorten the mesh, or centre it on its own "
				+ "origin: the reach is the collider's offset PLUS its extent, so "
				+ "an off-centre body spends the budget twice.")
	Sentinel.done("footprint")


func _check_resolved_speed(boss: CharacterBody3D) -> void:
	"""
	CHECK 6b — the boss speed a kind's ROW asks for is the speed it actually gets.

	A boss normally throws its row's chase speed away and takes the game-wide
	BOSS_CHASE_SPEED; `boss_chase_speed` is the one opt-out, and it exists for the
	snow titan, whose whole design is being SLOWER than a walking player. Nothing
	else in this file could see that go wrong: at 7 m/s a titan passes the hunt
	check, the fence check and the leash check exactly as it does at 3 m/s — it
	just silently becomes the melee giant the owner said it is not.

	The row is read here rather than restated, so this is a comparison between the
	table and the body, which is the only pair that can disagree. The boss stands
	at x = 0, where the distance gradient's factor is exactly 1.0, so the expected
	value is the row's number with the MAX_CHASE_SPEED clamp on top and nothing
	else in the way.
	"""
	var row: Dictionary = CROC_SCRIPT.SPECIES.get(_subject, {})
	var wanted: float = minf(
			float(row.get("boss_chase_speed", CROC_SCRIPT.BOSS_CHASE_SPEED)),
			CROC_SCRIPT.MAX_CHASE_SPEED)
	if absf(float(boss.chase_speed_instance) - wanted) > SPEED_EPS:
		_fail("speed: _ready() resolved chase_speed_instance %.2f, but the row asks "
				% boss.chase_speed_instance + "for %.2f — a boss inherits "
				% wanted + "BOSS_CHASE_SPEED (%.1f) unless its row opts out with "
				% CROC_SCRIPT.BOSS_CHASE_SPEED + "boss_chase_speed, and this kind's "
				+ "row is not being honoured")
	Sentinel.done("resolved_speed")


func _live_projectiles() -> int:
	"""How many boss projectiles are in the tree right now (they parent to root
	here, because the harness stands in for the firing boss's chunk)."""
	var live: int = 0
	for child in root.get_children():
		if child is BossProjectile:
			live += 1
	return live


func _check_leap(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 9 — a LEAPING boss really leaves the ground, comes back to it, hops on
	its own clock, and cannot bound over its own fence. Skipped entirely for a kind
	whose row is not `behavior: "leap"`.

	Owner, verbatim: "let those Rock and Dragons be able to make a decent jumps
	like windman does with F key."

	enemy_spawn_selfcheck's leap probe already drives the pure rules — `leap_due`,
	`leap_airtime`, `leap_reach` — over the cadence and the whole escape race. What
	only a live world can show is the four things the ARM adds around them, and
	this arm needs a live world more than any other in the file: it is the only one
	whose inputs are `is_on_floor()` and whose output is `velocity`, and neither
	exists outside a physics tick. A pure probe cannot tell a launch that HAPPENS
	from a launch that is merely computed.

	  A. THE BODY ACTUALLY LEAVES THE GROUND, AND COMES BACK. A real boss, a real
	     quarry inside its own territory, and a rise measured against the body's
	     own resting height — so the assertion survives whatever y a kind's capsule
	     puts its origin at. An arm that sets `velocity.y` on a body whose gravity
	     block then overwrites it, or a `match` with no "leap" case at all, both
	     leave this flat and both are silent everywhere else. The landing half is
	     the flat-world invariant restated as a measurement: a hop is a transient
	     arc, so the feet must be back on y = 0 by the end of it, by the arc and
	     not by anything writing a position.
	  B. IT HOPS ON A CLOCK. Launches over the window, bounded above by what the
	     row's airtime and cooldown allow. A recovery that is never re-armed
	     launches on every grounded frame — a boss that never touches down, which
	     to a check that only asserted "it left the ground" is a pass.
	  C. CONTAINMENT, WITH HOPPING, ON THE WAY OUT. The quarry is parked at the far
	     edge of what the boss can SMELL and the boss starts at home, so it bounds
	     outward hop after hop and its last legal arc lands as close to the fence as
	     the gate below will ever allow one to. Two geometries are wrong here and
	     both pass vacuously: a quarry outside the territory is refused by the
	     detection gate (no chase, no hop), and a quarry outside the detection
	     radius is not smelled at all — so the phase asserts that a launch actually
	     happened, and every frame of the window is contained, mid-arc frames
	     included.
	  D. THE PRE-LAUNCH TERRITORY GATE, driven directly, the way check 8 drives the
	     ranged one. The boss is parked inside its fence with a quarry bearing
	     outward: `_behave_leap` must refuse. The control is the SAME boss at the
	     SAME spot with the quarry bearing inward, which must launch — without it,
	     "it refused" is also true of a broken cooldown, a missing key, or an arm
	     that never fires at all.
	"""
	var row: Dictionary = CROC_SCRIPT.SPECIES.get(_subject, {})
	if String(row.get("behavior", "")) != "leap":
		Sentinel.done("leap")
		return
	var airtime: float = CROC_SCRIPT.leap_airtime(row)
	if airtime <= 0.0:
		_fail("leap: behaviour is 'leap' but the row's arc constants give no"
				+ " airtime — already reported in enemy_spawn_selfcheck")
		Sentinel.done("leap")
		return
	var apex: float = float(row["leap_launch_speed"]) * airtime * 0.25
	var cycle: float = airtime + float(row["leap_cooldown"])

	# ---- A and B. IT LEAVES THE GROUND, LANDS, AND HOPS ON A CLOCK ---------
	boss.global_position = Vector3(home.x, boss.global_position.y, home.z)
	boss.velocity = Vector3.ZERO
	# Inside BOSS_DETECTION_RADIUS and inside the territory, so the boss engages
	# through the ordinary detection path rather than through anything set here.
	player.global_position = home + Vector3(DETECTION_RADIUS * 0.5, 0.0, 0.0)
	# SETTLE FIRST, THEN ARM THE CLOCK. An empty lock means "ready now", so a boss
	# left to settle after clearing it spends its first hop in the settle frames —
	# outside the window, where nothing counts it. This ordering is the difference
	# between measuring the mechanic and measuring the frames after it.
	await _frames(4)
	var rest_y: float = boss.global_position.y
	boss._leap_lock.clear()
	var highest: float = 0.0
	var launches: int = 0
	var landings: int = 0
	var ground_drift: float = 0.0
	var air_frames: int = 0
	var longest_air: int = 0
	var grounded: bool = boss.is_on_floor()
	for _i in LEAP_FRAMES:
		await physics_frame
		highest = maxf(highest, boss.global_position.y - rest_y)
		var now_grounded: bool = boss.is_on_floor()
		if not now_grounded:
			air_frames += 1
		if grounded and not now_grounded:
			launches += 1
			air_frames = 1
		elif now_grounded and not grounded:
			landings += 1
			longest_air = maxi(longest_air, air_frames)
		if now_grounded:
			# THE FLAT-WORLD INVARIANT, ASSERTED WHERE IT LIVES. Every frame the
			# feet are down they must be down at the SAME height they started at —
			# a hop is a transient arc, not terrain. Measured on grounded frames
			# rather than on the last frame of the window, which can legitimately
			# land mid-arc.
			ground_drift = maxf(ground_drift, absf(boss.global_position.y - rest_y))
		grounded = now_grounded
		_assert_contained(boss, home, "leap/hop")
	if highest < apex * LEAP_APEX_FRACTION:
		_fail("leap: the boss rose %.2f m over %d frames chasing a quarry %.1f m"
				% [highest, LEAP_FRAMES, DETECTION_RADIUS * 0.5] + " away inside its"
				+ " own territory; its row claims a %.2f m apex. The arm computed a"
				% apex + " launch nothing applied, or the `match` in"
				+ " _update_chase_state has no \"leap\" case and the whole mechanic"
				+ " is unreachable in the real game")
	if launches <= 0:
		_fail("leap: no ground-to-air transition in %d frames — see the rise"
				% LEAP_FRAMES + " above; nothing in this phase measured a hop")
	elif landings <= 0:
		_fail("leap: %d launch(es) and not one landing in %d frames — the arc never"
				% [launches, LEAP_FRAMES] + " brings the body back down, which on a"
				+ " world that is flat at y = 0 is not a hop but flight")
	print("leap (%s): apex %.2f m (row says %.2f), airtime %.2f s (row says %.2f),"
			% [_subject, highest, apex, float(longest_air) / 60.0, airtime]
			+ " %d launches / %d landings in %.1f s"
			% [launches, landings, float(LEAP_FRAMES) / 60.0])
	if landings > 0 and absf(float(longest_air) / 60.0 - airtime) > airtime * LEAP_AIRTIME_TOLERANCE:
		_fail("leap: the longest complete arc lasted %.2f s; the row's %.2f m/s"
				% [float(longest_air) / 60.0, float(row["leap_launch_speed"])]
				+ " launch under its own %.2f m/s^2 arc gravity implies %.2f s."
				% [float(row["leap_gravity"]), airtime] + " The body is not falling"
				+ " at the gravity its row states, so leap_reach() — and the leash"
				+ " gate that projects a landing with it — is computed from an arc"
				+ " that is not the one being flown")
	if ground_drift > apex * LEAP_APEX_FRACTION:
		_fail("leap: the boss stood %.2f m off its own resting height on a GROUNDED"
				% ground_drift + " frame — a hop is a transient arc, so every"
				+ " landing is back on the one ground plane this world has."
				+ " Something is writing y outside the arc")
	var ceiling: int = LEAP_HOP_SLACK + int(float(LEAP_FRAMES) / 60.0 / cycle)
	if launches > ceiling:
		_fail("leap: %d launches in %.1f s at a %.2f s arc plus a %.2f s recovery"
				% [launches, float(LEAP_FRAMES) / 60.0, airtime,
						float(row["leap_cooldown"])] + " (at most %d fit) — the"
				% ceiling + " grounded recovery clock is not being spent, so the"
				+ " boss hops on every frame its feet touch down")

	# ---- C. CONTAINMENT, HOPPING, AT THE FENCE -----------------------------
	# AT THE EDGE OF WHAT IT CAN SMELL, not at the edge of the territory. Outside
	# BOSS_DETECTION_RADIUS the quarry is not smelled at all and the boss wanders;
	# outside BOSS_TERRITORY_RADIUS the detection gate above the dispatch refuses
	# it and the boss disengages. Either way `_behave_leap` returns on its
	# not-chasing branch and the containment asserted below is a walking boss's.
	# From home, a quarry here is the farthest thing the boss will bound at, so its
	# last legal arc lands as close to the fence as the pre-launch gate allows.
	var lure: float = DETECTION_RADIUS - 1.0
	player.global_position = home + Vector3(lure, 0.0, 0.0)
	boss.global_position = Vector3(home.x, boss.global_position.y, home.z)
	boss.velocity = Vector3.ZERO
	await _frames(4)
	boss._leap_lock.clear()          # armed AFTER the settle — see phase A
	var fence_launches: int = 0
	grounded = boss.is_on_floor()
	for _i in LEAP_FRAMES:
		await physics_frame
		var now_grounded: bool = boss.is_on_floor()
		if grounded and not now_grounded:
			fence_launches += 1
		grounded = now_grounded
		_assert_contained(boss, home, "leap/fence")
	if fence_launches <= 0:
		_fail("leap: hop-chasing a quarry %.1f m from home for %.1f s produced no"
				% [lure, float(LEAP_FRAMES) / 60.0] + " launch at"
				+ " all, so the containment asserted through that window is the"
				+ " containment of a boss that walked — it says nothing about hops")

	# ---- D. THE PRE-LAUNCH TERRITORY GATE ----------------------------------
	# Driven directly, the way check 8 drives the ranged gate and check 7 drives
	# the crush ordering: what is under test is one decision inside one function,
	# and both halves are taken at the SAME position with the SAME spent clock, so
	# only the BEARING differs and the control isolates the guard.
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
	var reach: float = CROC_SCRIPT.leap_reach(boss.chase_speed_instance, row)
	# TWO METRES INSIDE THE FENCE, the same spot check 8 parks a ranged boss at.
	# It is the geometry where the two bearings differ in the only way that
	# matters: outward the projected landing clears the circle, inward it does not.
	var gate_at: float = TERRITORY_RADIUS - 2.0
	if gate_at + reach <= TERRITORY_RADIUS:
		# THE PHASE'S OWN NEGATIVE CONTROL. A reach short enough to land inside the
		# circle from two metres off the fence has no illegal landing for the gate
		# to refuse, so "it refused" below would be a hop the cooldown declined.
		_fail("leap: a %.1f m hop from %.1f m out lands inside the %.1f m"
				% [reach, gate_at, TERRITORY_RADIUS] + " territory, so this phase"
				+ " has no illegal landing to refuse and the gate goes untested")
		Sentinel.done("leap")
		return
	# PUT IT DOWN FIRST. Phase C ends wherever the window ended, which is as often
	# as not mid-arc, and both halves below drive the arm's GROUNDED branch — a
	# boss still falling would take the airborne early return and refuse the
	# control shot for a reason that has nothing to do with the leash.
	boss.global_position = Vector3(home.x + gate_at, rest_y + 0.5, home.z)
	boss.velocity = Vector3.ZERO
	for _i in SETTLE_FRAMES:
		await physics_frame
		if boss.is_on_floor():
			break
	if not boss.is_on_floor():
		_fail("leap: the boss is not on the floor at the start of the gate phase,"
				+ " so _behave_leap's grounded branch is unreachable and neither"
				+ " half below means anything")
		Sentinel.done("leap")
		return
	boss.is_chasing = true

	boss._leap_lock.clear()
	boss.velocity.y = 0.0
	# Outward: a quarry it may legally hunt, and a landing it may not reach.
	boss.chase_target = Vector3(boss.global_position.x + 1.0, 0.0, home.z)
	boss._behave_leap()
	if boss.velocity.y > 0.0:
		_fail("leap: launched outward from %.1f m out with a %.1f m reach — the"
				% [gate_at, reach] + " projected landing is %.1f m from home and"
				% (gate_at + reach) + " the territory is %.1f m, so the leash no"
				% TERRITORY_RADIUS + " longer bounds the jump and the one rule this"
				+ " boss family is built on is broken by the very ability that"
				+ " makes it interesting")

	boss._leap_lock.clear()
	boss.velocity.y = 0.0
	# The control: same spot, same spent clock, bearing INWARD — a legal landing.
	boss.chase_target = Vector3(boss.global_position.x - 1.0, 0.0, home.z)
	boss._behave_leap()
	if boss.velocity.y <= 0.0:
		_fail("leap: the control hop — same spot, same clock, bearing INWARD and so"
				+ " landing %.1f m from home, well inside the %.1f m territory —"
				% [absf(gate_at - reach), TERRITORY_RADIUS]
				+ " did not launch either, so the refusal above proves nothing about"
				+ " the territory gate")
	# THE DEGENERATE BEARING, which is the one geometry the projection can lose. A
	# boss standing ON its quarry has no bearing to the target at all, and the
	# tempting reading — no bearing, so land where you are — is an UNGUARDED LAUNCH:
	# the body still travels for the whole airtime, along its own FACING. So face it
	# at the fence, put the target under its feet, and demand the same refusal.
	boss._leap_lock.clear()
	boss.velocity.y = 0.0
	boss.rotation.y = PI * 0.5          # (sin, cos) = (1, 0): pointing +X, outward
	boss.chase_target = boss.global_position
	boss._behave_leap()
	if boss.velocity.y > 0.0:
		_fail("leap: launched from %.1f m out with its quarry UNDER ITS FEET and its"
				% gate_at + " nose at the fence — with no bearing to project, the arm"
				+ " fell back on 'land where you are' and let a %.1f m hop go"
				% reach + " unjudged. A hop travels whether or not there is anywhere"
				+ " to travel to")

	boss.velocity.y = 0.0
	boss.is_chasing = false
	boss._leap_lock.clear()
	Sentinel.done("leap")


func _clear_projectiles() -> void:
	"""Free every bolt in the air. Called before a measurement window because the
	per-shooter `max_live` cap is real: two bolts left over from an earlier phase
	would make the next phase's boss refuse to fire, which reads as a broken arm."""
	for child in root.get_children():
		if child is BossProjectile:
			child.free()


func _check_ranged(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 8 — a RANGED boss actually fires, on its cooldown, and only where it is
	allowed to. Skipped entirely for a kind whose row is not `behavior: "ranged"`.

	enemy_spawn_selfcheck already drives the pure firing RULE
	(piglet_crocodile_ai.ranged_shot_due) over its whole band and cadence. What
	only a live world can show is the three things the ARM adds around it, and
	each of the phases below is one of them:

	  A. IT REALLY FIRES. A real boss, a real quarry inside its own territory and
	     firing band, and a BossProjectile that really appears in the tree — i.e.
	     the arm calls fire() with arguments the capability accepts. An arm that
	     computed a perfect cadence and then passed a null parent would pass every
	     pure probe in the other file and put nothing in the world. The count is
	     also bounded above, so an archer that fires every frame fails here too.

	  B. THE TERRITORY GATE, driven directly. The boss is parked two metres inside
	     its own fence, which is the ONLY geometry where a point can be inside the
	     firing band and outside the territory at once (the band's 22 m ceiling is
	     well under the 32 m radius). Both calls are made at the SAME in-band
	     distance and differ only in which side of the boundary the quarry stands,
	     so the positive control isolates the guard: delete
	     `if is_boss and not in_territory(chase_target)` from the arm and the first
	     half fails while the second still passes.

	  C. NO SHOT WHILE NOT CHASING. A wandering titan that shells the horizon is
	     the same bug as a boss that leaves its area.

	B and C call `_behave_ranged()` directly, the way check 7 calls
	`_on_player_collision`: what is under test is a guard inside one function, and
	staging a physics situation for it would add flake without adding reach — the
	detection code above the dispatch would refuse these quarries long before the
	arm ever saw them, which is precisely why the arm's own guard needs driving.
	"""
	var row: Dictionary = CROC_SCRIPT.SPECIES.get(_subject, {})
	if String(row.get("behavior", "")) != "ranged":
		Sentinel.done("ranged")
		return
	if not row.has("ranged"):
		_fail("ranged: behaviour is 'ranged' but the row carries no \"ranged\" dict")
		Sentinel.done("ranged")
		return
	var ranged: Dictionary = row["ranged"]
	var min_range: float = float(ranged["min_fire_range"])
	var max_range: float = float(ranged["max_fire_range"])
	var band_mid: float = (min_range + max_range) * 0.5

	# ---- A. IT REALLY FIRES ------------------------------------------------
	_clear_projectiles()
	boss.global_position = Vector3(home.x, boss.global_position.y, home.z)
	boss._ranged_lock.clear()
	# At the TOP of the band: the boss closes at its own (deliberately slow) chase
	# speed while the window runs, so starting at the ceiling is what keeps it
	# inside the band for the whole of it.
	player.global_position = home + Vector3(max_range, 0.0, 0.0)
	await _frames(2)
	var seen: Dictionary = {}
	for _i in RANGED_FRAMES:
		await physics_frame
		for child in root.get_children():
			if child is BossProjectile:
				seen[child.get_instance_id()] = true
	var cooldown: float = float(ranged["fire_cooldown"])
	var ceiling: int = 1 + int(float(RANGED_FRAMES) / 60.0 / cooldown)
	if seen.is_empty():
		_fail("ranged: no projectile in %d frames with the quarry %.1f m away — "
				% [RANGED_FRAMES, max_range] + "inside the territory, inside "
				+ "detection and inside the firing band, so the arm should have "
				+ "fired on the acquisition frame")
	elif seen.size() > ceiling:
		_fail("ranged: %d projectiles in %.1f s at a %.2f s cooldown (at most %d "
				% [seen.size(), float(RANGED_FRAMES) / 60.0, cooldown, ceiling]
				+ "should fit) — the cooldown is not being spent")

	# ---- B. THE TERRITORY GATE ---------------------------------------------
	_clear_projectiles()
	await _frames(2)
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
	boss.global_position = Vector3(
			home.x + TERRITORY_RADIUS - 2.0, boss.global_position.y, home.z)
	boss.is_chasing = true
	boss._ranged_lock.clear()
	# Outward from a boss standing near its fence: in the band, out of the circle.
	boss.chase_target = Vector3(boss.global_position.x + band_mid, 0.0, home.z)
	var before: int = _live_projectiles()
	boss._behave_ranged()
	if _live_projectiles() > before:
		_fail("ranged: fired at a quarry %.1f m from home (territory is %.1f) from "
				% [_flat_distance(boss.chase_target, home), TERRITORY_RADIUS]
				+ "%.1f m away — a boss that can shell you outside its own area "
				% band_mid + "gives back the only counterplay there is")
	# The control, at the SAME distance and the other side of the fence.
	boss._ranged_lock.clear()
	boss.chase_target = Vector3(boss.global_position.x - band_mid, 0.0, home.z)
	before = _live_projectiles()
	boss._behave_ranged()
	if _live_projectiles() <= before:
		_fail("ranged: the control shot — same %.1f m range, quarry %.1f m from "
				% [band_mid, _flat_distance(boss.chase_target, home)] + "home and "
				+ "so INSIDE the territory — did not fire either, so the refusal "
				+ "above proves nothing about the territory gate")

	# ---- C. NO SHOT WHILE NOT CHASING --------------------------------------
	_clear_projectiles()
	await _frames(2)
	boss.is_chasing = false
	boss._ranged_lock.clear()
	# The target is re-stated HERE, and it is the whole check. The boss's own
	# _physics_process ran during the frames above and left `chase_target` on the
	# player, who is parked 300 m away — out of the firing band, so an arm with
	# its not-chasing guard DELETED would still refuse this shot and the phase
	# would pass having measured the band gate a second time. Setting the target
	# back to the same in-band, in-territory point the control above fired at
	# leaves `is_chasing` as the only difference between the two calls.
	# (Measured, 2026-08-29: without this line the mutant passes.)
	boss.chase_target = Vector3(boss.global_position.x - band_mid, 0.0, home.z)
	before = _live_projectiles()
	boss._behave_ranged()
	if _live_projectiles() > before:
		_fail("ranged: fired while not chasing, at the same quarry the control "
				+ "above fired at — a titan that has not smelled anybody must not "
				+ "shell the horizon")

	_clear_projectiles()
	await _frames(2)
	Sentinel.done("ranged")


func _check_crush_immunity(packed: PackedScene, species_name: String,
		giant: StubPlayer) -> void:
	"""
	CHECK 7 — ALL bosses are crush-immune, and it is the block ORDER that does it.

	Owner, verbatim: "yes, for now all bosses immune. we will think about it later
	on." Immunity is a property of boss-ness, so it is asserted on the is_boss
	flag and not on any species name — and every boss kind is driven through here,
	so "the titan inherits it" is measured rather than assumed.

	`_on_player_collision` is driven directly rather than through a staged physics
	contact: the thing under test is which of its two blocks runs first, and a
	real collision only adds ways for the check to flake without adding anything
	it can catch.

	NEGATIVE CONTROL: the same giant stub against a NON-boss body of the SAME
	species must crush it. Without that half, an is_boss typo — or a stub whose
	crushes_crocodiles() quietly answered false — would leave "the boss survived"
	true for a reason that has nothing to do with the ordering.

	@param packed: the kind's scene
	@param species_name: its SPECIES key, assigned before setup_as_boss
	@param giant: the shared quarry stub, flipped to giant for this check only.
	              Reused rather than a second stub because two nodes in group
	              "player" would make _find_player()'s answer an ordering
	              accident for every body spawned after it.

	BITE COUNTS ARE MEASURED AS DELTAS, not against absolutes: a ranged boss may
	have put a bolt in this stub earlier in the run, and an absolute count would
	turn that into a failure about crush ordering.
	"""
	giant.giant = true
	var boss: CharacterBody3D = packed.instantiate()
	boss.species = species_name
	boss.setup_as_boss(BOSS_SCALE)
	boss.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(boss)
	var victim: CharacterBody3D = packed.instantiate()
	victim.species = species_name
	victim.position = Vector3(10.0, 1.0, 0.0)
	root.add_child(victim)
	await _frames(SETTLE_FRAMES)

	giant.global_position = boss.global_position
	var before: int = giant.bitten
	boss._on_player_collision(giant)
	if not boss.is_in_group("crocodile"):
		_fail("crush: a boss was squashed by giant Teibi — the is_boss early return "
				+ "in _on_player_collision must stay ABOVE the crush block")
	if giant.bitten - before != 1:
		_fail("crush: boss contact called hit_by_crocodile %d times, expected 1 — "
				% (giant.bitten - before) + "a boss takes the BITE path, not the squash path")

	# The control. Same stub, same call, ordinary body of the same species: this
	# one must die.
	before = giant.bitten
	victim._on_player_collision(giant)
	if victim.is_in_group("crocodile"):
		_fail("crush: the giant stub failed to crush an ORDINARY body of this "
				+ "species, so the boss surviving above proves nothing about the "
				+ "block ordering")
	if giant.bitten - before != 0:
		_fail("crush: an ordinary body bit a crushing giant (hit count %d)"
				% (giant.bitten - before))

	giant.giant = false
	boss.queue_free()
	victim.queue_free()
	await _frames(2)
	Sentinel.done("crush_immunity")



func _check_row_immunities(giant: StubPlayer) -> void:
	"""
	CHECK 8 — `stink_immune` / `crush_immune` are ROW DATA, and both guards work.

	Owner ruling, from the hunter epic: a GD-SURVEY unit is a sealed machine, so
	a smell weapon does nothing to it, and it is armoured, so giant Teibi does
	not pop it. Both landed as `spec.get(key, false)` reads beside the existing
	is_boss guards — one in `flee_from()`, one on the crush block in
	`_on_player_collision()` — rather than as a name test, because species are
	data and not subclasses (CLAUDE.md).

	SO THIS CHECK IS TABLE-DRIVEN AND NAMES NOTHING. It walks every key of
	SPECIES, reads what that row asked for, and drives both real code paths. Two
	things fall out of that shape:
	  * the seven ANIMAL rows are the negative control — they carry neither key,
	    so they must still flee and must still be squashed. Delete either guard
	    and the machine row fails; widen either guard to everything and all seven
	    animal rows fail.
	  * a future armoured predator is covered the day its row lands, with no edit
	    here — the same treatment enemy_spawn_selfcheck gives the dispatch maps.

	EVERY ROW IS INSTANTIATED FROM THE CROCODILE'S SCENE, deliberately. `spec` is
	resolved from the `species` string in _ready() and both guards read only
	`spec`, so the mesh is irrelevant to what is being measured — and going
	through a scene MAP would mean this check silently skipped any row whose
	.tscn had not been written yet, which is exactly the row most likely to have
	got its immunity wrong.

	VACUITY IS ASSERTED TOO. If nothing in the table carries a key, the loop
	above proves only that the guard is never TAKEN, so the tail requires at
	least one row per key — that is what makes "drop the row key and the guard is
	dead code" a failure instead of a silent pass.

	@param giant: the shared quarry stub, flipped to giant for the crush half
	              only. Reused for the same reason check 7 reuses it — two nodes
	              in group "player" would make _find_player() an ordering
	              accident.
	"""
	var packed: PackedScene = load(CROC_SCENE)
	if packed == null:
		_fail("immunity: could not load %s" % CROC_SCENE)
		Sentinel.done("row_immunities")
		return
	# How many rows actually exercised each guard, for the vacuity check below.
	var opted_in: Dictionary = {}
	for key: String in IMMUNITY_KEYS:
		opted_in[key] = 0

	for species_name: String in CROC_SCRIPT.SPECIES.keys():
		_subject = species_name
		var row: Dictionary = CROC_SCRIPT.SPECIES[species_name]
		var stink_immune: bool = bool(row.get("stink_immune", false))
		var crush_immune: bool = bool(row.get("crush_immune", false))
		if stink_immune:
			opted_in["stink_immune"] += 1
		if crush_immune:
			opted_in["crush_immune"] += 1

		# Same call-order contract as everywhere else: species BEFORE add_child,
		# because _ready() resolves `spec` from it exactly once.
		var body: CharacterBody3D = packed.instantiate()
		body.species = species_name
		body.position = Vector3(0.0, 1.0, 0.0)
		root.add_child(body)
		await _frames(SETTLE_FRAMES)
		if String(body.species) != species_name:
			_fail("immunity: species is '%s' after _ready() — an unknown name "
					% body.species + "falls back to the crocodile row, so this "
					+ "row would be measured as one")
			body.queue_free()
			await _frames(2)
			continue

		# ---- A. THE STINK WAVE ------------------------------------------------
		# flee_from() is the whole ability as far as a predator is concerned:
		# Phoboman's dispatch walks group "crocodile" and calls exactly this (see
		# player_controller.trigger_stink_wave), so calling it directly measures
		# the guard and not the group scan.
		body.flee_from(body.global_position + Vector3(3.0, 0.0, 0.0), 3.0)
		if body.is_fleeing == stink_immune:
			if stink_immune:
				_fail("stink: row says stink_immune, but flee_from() set the body "
						+ "fleeing — a sealed machine has no nose, and the guard "
						+ "in flee_from() is what says so")
			else:
				_fail("stink: this row asks for no immunity, but flee_from() left "
						+ "it not fleeing — Phoboman's wave must still work on "
						+ "every ordinary predator")

		# The flee flag is cleared BEFORE the crush half, and it has to be: a
		# fleeing body early-returns out of the bite path at the bottom of
		# _on_player_collision, which would make an immune row look like it took
		# no path at all. Fleeing is what part A just proved; here it is setup.
		body.is_fleeing = false
		body.flee_time_remaining = 0.0

		# ---- B. GIANT TEIBI'S CRUSH -------------------------------------------
		# Driven straight into _on_player_collision for check 7's reason: what is
		# under test is which block runs, and a staged physics contact only adds
		# ways to flake.
		giant.giant = true
		giant.global_position = body.global_position
		var before: int = giant.bitten
		body._on_player_collision(giant)
		var survived: bool = body.is_in_group("crocodile")
		giant.giant = false
		if survived != crush_immune:
			if crush_immune:
				_fail("crush: row says crush_immune, but giant Teibi squashed it "
						+ "— an armoured chassis must fall through the crush "
						+ "block to the ordinary bite path")
			else:
				_fail("crush: this row asks for no immunity, but giant Teibi "
						+ "failed to squash it — the crush block must still work "
						+ "on every ordinary predator")
		# The bite count is the OTHER half, and without it "it survived" is also
		# true of a body that did nothing at all: an immune row must have taken
		# the bite path, a crushable one must not have.
		var expected_bites: int = 1 if crush_immune else 0
		if giant.bitten - before != expected_bites:
			_fail("crush: contact called hit_by_crocodile %d times, expected %d "
					% [giant.bitten - before, expected_bites]
					+ "— an immune body bites the giant, a crushable one dies "
					+ "without biting")

		body.queue_free()
		await _frames(2)
	_subject = ""

	# ---- C. THE TABLE ACTUALLY EXERCISES BOTH GUARDS ------------------------
	for key: String in IMMUNITY_KEYS:
		if int(opted_in[key]) <= 0:
			_fail("immunity: no row in SPECIES carries '%s', so the loop above "
					% key + "never took that guard and proves nothing about it — "
					+ "delete the guard or restore the row key")

	# ---- D. THE ANCHOR ------------------------------------------------------
	# Part A/B read the row, so a row that turned immune by mistake would be
	# measured as correct. The baseline predator is pinned by name instead.
	var baseline: Dictionary = CROC_SCRIPT.SPECIES.get(BASELINE_SPECIES, {})
	if baseline.is_empty():
		_fail("immunity: SPECIES has no '%s' row to anchor against" % BASELINE_SPECIES)
	for key: String in IMMUNITY_KEYS:
		if bool(baseline.get(key, false)):
			_fail("immunity: the '%s' row carries '%s' — the game's ordinary "
					% [BASELINE_SPECIES, key] + "enemy is flesh and has a nose, "
					+ "and making it immune would quietly break the whole "
					+ "Phoboman/giant-Teibi half of the toolbox")
	Sentinel.done("row_immunities")
