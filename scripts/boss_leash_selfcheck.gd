extends SceneTree
## ============================================================================
## BOSS SELF-CHECK — THE LEASH
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_leash_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## ONE OF FIVE — see `boss_selfcheck.gd`'s header for the family and for why bead
## `godot-test1-ftn.24` split it; `scripts/boss_probe.gd` is the shared harness.
##
## WHY THIS IS ITS OWN FILE, AND WHY IT IS THE HEAVIEST OF THE FIVE. Both checks
## here are 240-frame walks on every one of the seven boss kinds, and every phase
## in this family is wall clock rather than CPU (`await physics_frame` is paced at
## the real 60 Hz), so this file is 4.0 + 4.0 s per kind and nothing can make it
## less. It is not split further because CHECK 4 AND CHECK 5 ARE ONE STATE CHAIN:
## the leash phase's whole argument is that the boss arrives at it parked against
## its own fence, ~8 m from the quarry it must nonetheless refuse. Start check 5
## from a freshly settled boss at home and the quarry 40 m out is outside the 25 m
## detection radius, nothing is ever smelled, and the check passes vacuously —
## which is the exact trap its own docstring is written against.
##
## THE ONE THING THE SPLIT CHANGED, AND IT IS A SETUP AND NOT AN ASSERTION.
## Check 4 used to inherit its starting state from check 3 — after four seconds of
## hunting a quarry at 20 m, the boss stood ~15 m out and was already chasing —
## and check 3 is `boss_selfcheck`'s now. Started cold from home with the quarry at
## 31.5 m, the boss is 6.5 m outside its own 25 m detection radius, never smells
## anything, and every kind but the crocodile fails `is_chasing` for a reason that
## has nothing to do with the leash (measured: six of the seven). So the boss is
## PLANTED at FENCE_APPROACH_X, which is where the hunt phase left it — the same
## geometry, stated instead of inherited, in the idiom check 6 already uses for its
## own plant. Both assertions are the ones they always were, and check 5 still
## chains off check 4 exactly as it did.
##
## WHAT IT PINS. THE LEASH IS A NEGATIVE: "the boss never leaves its area" is
## invisible while it holds and only shows up as a boss that followed you across
## half a biome, three chunks after the mistake. Nothing errors, nothing logs.
## Worse, the interesting case is not "quarry far away" (detection already handles
## that) but "quarry 15 m from the boss and OUTSIDE the circle" — the boss can
## smell you fine and must refuse anyway. Check 5 parks the player exactly there,
## which is the case a hand-written radius test in the wrong place (against the
## local player rather than the chosen `chase_target`, or below the behaviour
## dispatch instead of above it) gets wrong while still looking correct in play.
##
## The other half of the rule — that a boss HUNTS inside its area — is
## `boss_selfcheck`'s check 3, and the negative control for a boss frozen solid
## at its own fence is `boss_wander_selfcheck`'s check 6.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

## Where check 4 plants the boss, in metres out from home on +X — the spot the
## hunt phase used to hand it over at, and the whole of what the split changed.
## The arithmetic it reproduces: check 3 parks the quarry at 20 m and a boss at
## BOSS_CHASE_SPEED closes to bite range inside its four seconds, so the body
## stood ~15 m from home with the quarry it is about to be handed (31.5 m out)
## 16.5 m away — comfortably inside BOSS_DETECTION_RADIUS (25), which is the only
## property this number has to have. It is deliberately NOT nearer the fence: the
## point of the phase is a boss driving OUTWARD at chase speed into its own
## boundary, and a body planted on the boundary has no run-up to be stopped from.
const FENCE_APPROACH_X: float = 15.0

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
	await BossProbe.drive(self, _fail, _on_boss)
	_report()


func _on_boss(boss: CharacterBody3D, player: BossProbe.StubPlayer, home: Vector3) -> void:
	"""The chain, in order: the fence chase is check 5's setup as well as check 4's
	measurement — see the header."""
	await _check_hunts_at_fence(boss, player, home)
	await _check_leashed(boss, player, home)


func _check_hunts_at_fence(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
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

	THE PLANT is the split's one setup change and the header carries its whole
	reasoning: the boss stands where the hunt phase used to leave it, because that
	phase is `boss_selfcheck`'s now.
	"""
	boss.global_position = Vector3(
			home.x + FENCE_APPROACH_X, boss.global_position.y, home.z)
	player.global_position = home + Vector3(BossProbe.TERRITORY_RADIUS - 0.5, 0.0, 0.0)
	var worst := 0.0
	for _i in BossProbe.PHASE_FRAMES:
		await physics_frame
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if worst > BossProbe.TERRITORY_RADIUS + BossProbe.CONTAIN_EPS:
		_fail("fence: boss reached %.2f m from home chasing a quarry %.1f m out, "
				% [worst, BossProbe.TERRITORY_RADIUS - 0.5]
				+ "territory is %.1f m — the quarry was inside, the boss must not be "
				% BossProbe.TERRITORY_RADIUS + "outside")
	if not boss.is_chasing:
		_fail("fence: boss dropped a quarry that is %.1f m from home, i.e. INSIDE "
				% (BossProbe.TERRITORY_RADIUS - 0.5)
				+ "its %.1f m territory — the leash must bound where a boss can go, "
				% BossProbe.TERRITORY_RADIUS + "never how far it can smell")
	Sentinel.done("hunts_at_fence")


func _check_leashed(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
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
	for _i in BossProbe.PHASE_FRAMES:
		await physics_frame
		worst = maxf(worst, _flat_distance(boss.global_position, home))

	if worst > BossProbe.TERRITORY_RADIUS + BossProbe.CONTAIN_EPS:
		_fail("leash: boss reached %.2f m from home, territory is %.1f m — it left "
				% [worst, BossProbe.TERRITORY_RADIUS] + "its area chasing a quarry outside it")
	if boss.is_chasing:
		var gap := _flat_distance(boss.global_position, player.global_position)
		_fail("leash: boss still chasing a quarry %.1f m from home (territory %.1f); "
				% [_flat_distance(player.global_position, home), BossProbe.TERRITORY_RADIUS]
				+ "it is %.1f m away so detection alone will not drop it" % gap)
	Sentinel.done("leashed")
