extends SceneTree
## ============================================================================
## BOSS SELF-CHECK — IT STILL WANDERS, AND THE CONTAINMENT HOLDS WHILE IT DOES
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_wander_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## ONE OF FIVE — see `boss_selfcheck.gd`'s header for the family and for why bead
## `godot-test1-ftn.24` split it; `scripts/boss_probe.gd` is the shared harness.
##
## THE ONE CHECK HERE IS `boss_leash_selfcheck`'s NEGATIVE CONTROL, and it is in a
## file of its own for cost alone: it is another 240-frame walk on every one of the
## seven boss kinds (4.0 s each, wall clock — every phase in this family is paced
## at the real 60 Hz), and adding it to the leash file would make that one 87 s,
## which is the number the whole split exists to get rid of. It needs nothing the
## leash phase leaves behind: it PLANTS the boss against its own fence and aims it
## outward itself, which is exactly what makes it the control.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

## How far the boss must travel after disengaging for "it still wanders" to be
## proven. Wander speed is ~2 m/s, so 4 s is ~8 m even with pauses and turns.
const WANDER_MIN: float = 2.0

var _failures: Array[String] = []


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
	_failures.append(message if BossProbe.subject.is_empty()
			else "[%s] %s" % [BossProbe.subject, message])


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return BossProbe.flat_distance(a, b)


func _run() -> void:
	# EVERY boss kind, not just the crocodile — see BossProbe.subjects().
	await BossProbe.drive(self, _fail, _check_wanders_contained)
	_report()


func _check_wanders_contained(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
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
	    still passed every other check in this family — a disengaged boss simply
	    never wandered far enough to meet its own fence inside the window. So the
	    boss is PLANTED one metre inside the boundary and AIMED STRAIGHT OUT
	    (wander_heading and rotation.y both, so there is no turn lag to bleed the
	    energy away) before the window starts. Unleashed it walks clean out to
	    ~39 m; leashed it must slide along the fence.

	The quarry is teleported far away first so nothing here is a chase — this is
	the boss's own wandering meeting the boundary, with no help from the gate.
	"""
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
	boss.global_position = Vector3(
			home.x + BossProbe.TERRITORY_RADIUS - 1.0, boss.global_position.y, home.z)
	# heading 0 is +Z (see _choose_new_direction), so +X — dead outward — is PI/2.
	boss.wander_heading = PI / 2.0
	boss.rotation.y = PI / 2.0
	var start := boss.global_position
	var travelled := 0.0
	var worst := 0.0
	var previous := start
	for _i in BossProbe.PHASE_FRAMES:
		await physics_frame
		travelled += _flat_distance(boss.global_position, previous)
		previous = boss.global_position
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if travelled < WANDER_MIN:
		_fail("wander: boss travelled %.2f m in %d frames after disengaging "
				% [travelled, BossProbe.PHASE_FRAMES]
				+ "(needed %.1f) — it is pinned against its own fence, not walking "
				% WANDER_MIN + "inside its area")
	if worst > BossProbe.TERRITORY_RADIUS + BossProbe.CONTAIN_EPS:
		_fail("wander: boss reached %.2f m from home while wandering, territory is "
				% worst + "%.1f m" % BossProbe.TERRITORY_RADIUS)
	Sentinel.done("wanders_contained")
