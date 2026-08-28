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
##      Check 5 pins the order — with a NON-boss negative control, because "the
##      boss survived" is also true of a stub that never crushed anything.
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
## Read from the file that OWNS it — the whole point of check 1 is that the
## crocodile's territory and the LOD manager's sleep radius must stay in step,
## and re-typing 45.0 here would make the check pass through a copy of the bug.
const LOD_SCRIPT: GDScript = preload("res://scripts/crocodile_lod_manager.gd")

const TERRITORY_RADIUS: float = CROC_SCRIPT.BOSS_TERRITORY_RADIUS
const DETECTION_RADIUS: float = CROC_SCRIPT.BOSS_DETECTION_RADIUS
const SIM_RADIUS: float = LOD_SCRIPT.SIM_RADIUS

## Body scale for the test boss. The terrain's schedule hands out 2.5x–6x; a
## middling one keeps the capsule from dominating the distances measured here.
const BOSS_SCALE: float = 3.0

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
const HUNT_CLOSE_MIN: float = 3.0

## How far the boss must travel after disengaging for "it still wanders" to be
## proven. Wander speed is ~2 m/s, so 4 s is ~8 m even with pauses and turns.
const WANDER_MIN: float = 2.0

var _failures: Array[String] = []


## The player stand-in. Deliberately a plain Node3D and NOT a CharacterBody3D:
## `_update_chase_state` asks the quarry `is_on_floor()` and a CharacterBody3D
## that never ran move_and_slide answers false, i.e. "jumped", i.e. unsmellable —
## every chase check below would then pass vacuously. This answers the one
## question the AI asks, and carries the two methods `_on_player_collision`
## dispatches on so check 5 can drive the crush ordering directly.
class StubPlayer:
	extends Node3D
	## Flipped by check 5 only; the chase checks want an ordinary player.
	var giant: bool = false
	var bitten: int = 0

	func is_on_floor() -> bool:
		return true

	func crushes_crocodiles() -> bool:
		return giant

	func hit_by_crocodile() -> void:
		bitten += 1


func _initialize() -> void:
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there — reporting here would print a verdict at frame 0.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
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


func _run() -> void:
	_check_constants()

	var packed: PackedScene = load(CROC_SCENE)
	if packed == null:
		_fail("could not load %s" % CROC_SCENE)
		_report()
		return

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

	var boss: CharacterBody3D = packed.instantiate()
	# CALL-ORDER CONTRACT: setup_as_boss() must run BEFORE add_child, because
	# _ready() is where is_boss is read — it resolves the boss detection radius,
	# the fixed boss speeds, and (this bead) captures home_position. Called after,
	# this whole file would be measuring an ordinary crocodile.
	boss.setup_as_boss(BOSS_SCALE)
	boss.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(boss)
	await _frames(SETTLE_FRAMES)

	if not boss.has_method("in_territory"):
		_fail("boss: no in_territory() on %s — did the script fail to attach? " % CROC_SCENE
				+ "(a fresh clone needs `godot --headless --path . --import` first)")
		_report()
		return
	if not boss.is_boss:
		_fail("boss: setup_as_boss() left is_boss false")
		_report()
		return

	var home: Vector3 = boss.home_position
	_check_home(boss, home)
	await _check_hunts_inside(boss, player, home)
	await _check_leashed(boss, player, home)
	await _check_wanders_contained(boss, player, home)

	boss.queue_free()
	player.queue_free()
	await _frames(2)
	await _check_crush_immunity(packed)

	_report()


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


func _check_leashed(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 4 — THE LEASH. Quarry parked outside the circle: the boss disengages and
	its own body never crosses the boundary.

	The placement is the check. 40 m from home is outside the territory (32) but
	the boss arrives here from check 3 sitting ~20 m out, i.e. well INSIDE its
	detection radius of the quarry — it can smell you perfectly and must refuse
	anyway. Without the leash the ordinary chase code sails straight past the
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


func _check_wanders_contained(boss: CharacterBody3D, player: StubPlayer, home: Vector3) -> void:
	"""
	CHECK 5 — after disengaging the boss keeps MOVING ("they walk inside some
	area") and stays inside it.

	The negative control for check 4: a boss frozen solid at the boundary also
	never leaves its territory, and would pass the leash check while being a
	statue. The quarry is teleported far away first so nothing here is a chase.
	"""
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
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


func _check_crush_immunity(packed: PackedScene) -> void:
	"""
	CHECK 6 — ALL bosses are crush-immune, and it is the block ORDER that does it.

	Owner, verbatim: "yes, for now all bosses immune. we will think about it later
	on." Immunity is a property of boss-ness, so it is asserted on the is_boss
	flag and not on any species name — every boss kind added later inherits both
	the rule and this check.

	`_on_player_collision` is driven directly rather than through a staged physics
	contact: the thing under test is which of its two blocks runs first, and a
	real collision only adds ways for the check to flake without adding anything
	it can catch.

	NEGATIVE CONTROL: the same giant stub against a NON-boss crocodile must crush
	it. Without that half, an in_territory typo — or a stub whose
	crushes_crocodiles() quietly answered false — would leave "the boss survived"
	true for a reason that has nothing to do with the ordering.
	"""
	var giant := StubPlayer.new()
	giant.giant = true
	root.add_child(giant)
	giant.add_to_group("player")

	var boss: CharacterBody3D = packed.instantiate()
	boss.setup_as_boss(BOSS_SCALE)
	boss.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(boss)
	var victim: CharacterBody3D = packed.instantiate()
	victim.position = Vector3(10.0, 1.0, 0.0)
	root.add_child(victim)
	await _frames(SETTLE_FRAMES)

	giant.global_position = boss.global_position
	boss._on_player_collision(giant)
	if not boss.is_in_group("crocodile"):
		_fail("crush: a boss was squashed by giant Teibi — the is_boss early return "
				+ "in _on_player_collision must stay ABOVE the crush block")
	if giant.bitten != 1:
		_fail("crush: boss contact called hit_by_crocodile %d times, expected 1 — "
				% giant.bitten + "a boss takes the BITE path, not the squash path")

	# The control. Same stub, same call, ordinary crocodile: this one must die.
	victim._on_player_collision(giant)
	if victim.is_in_group("crocodile"):
		_fail("crush: the giant stub failed to crush an ORDINARY crocodile, so the "
				+ "boss surviving above proves nothing about the block ordering")
	if giant.bitten != 1:
		_fail("crush: an ordinary crocodile bit a crushing giant (hit count %d)"
				% giant.bitten)

	boss.queue_free()
	giant.queue_free()
	await _frames(2)
