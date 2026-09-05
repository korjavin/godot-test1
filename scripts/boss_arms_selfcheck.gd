extends SceneTree
## ============================================================================
## BOSS SELF-CHECK — THE ARMS A BOSS KIND ADDS: THE RANGED SHOT AND THE LEAP
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_arms_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## ONE OF FIVE — see `boss_selfcheck.gd`'s header for the family and for why bead
## `godot-test1-ftn.24` split it; `scripts/boss_probe.gd` is the shared harness.
##
## BOTH CHECKS SKIP A KIND WHOSE ROW DOES NOT CARRY THEIR BEHAVIOUR, so this file
## is driven over every BIOME_BOSS kind exactly like its four siblings and costs
## real time on four of the seven: the two archers (~5 s each) and the two winged
## bosses (~21 s each). A new ranged or leaping row is measured the day it lands,
## with no edit here.
##
## A HOP IS A NEGATIVE, TWICE OVER. "The winged bosses leave the ground" fails as
## a body that reads exactly like the heavy quadruped it was — no error, no log,
## the arm running perfectly and setting a velocity nothing ever gets to use — and
## "a hop does not clear the fence" fails the way the leash does, three chunks
## later. Check 9 drives both against a real boss on a real slab, because the arm
## is the one in this family that depends on `is_on_floor()` and `velocity`: no
## amount of pure probing in enemy_behavior_selfcheck can tell a launch that
## happens from one that is computed. It also drives the pre-launch territory gate
## DIRECTLY, with a positive control at the same geometry, the way check 8 drives
## the ranged one.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

## How long the ranged phase runs, in physics frames. 300 @ 60 Hz = 5 s, which is
## one full `fire_cooldown` plus most of a second: long enough that a cadence
## bug (an archer that fires every frame) cannot hide inside the per-shooter
## `max_live` cap, and short enough that a titan closing at its own 3 m/s is
## still inside its firing band when the window ends.
const RANGED_FRAMES: int = 300

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


func _frames(n: int) -> void:
	await BossProbe.frames(self, n)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return BossProbe.flat_distance(a, b)


func _assert_contained(boss: CharacterBody3D, home: Vector3, phase: String) -> void:
	BossProbe.assert_contained(_fail, boss, home, phase)


func _run() -> void:
	# EVERY boss kind, not just the crocodile — see BossProbe.subjects().
	await BossProbe.drive(self, _fail, _on_boss)
	_report()


func _on_boss(boss: CharacterBody3D, player: BossProbe.StubPlayer, home: Vector3) -> void:
	"""Both arms, in the order they ran in before the split."""
	await _check_ranged(boss, player, home)
	await _check_leap(boss, player, home)


func _live_projectiles() -> int:
	"""How many boss projectiles are in the tree right now (they parent to root
	here, because the harness stands in for the firing boss's chunk)."""
	var live: int = 0
	for child in root.get_children():
		if child is BossProjectile:
			live += 1
	return live


func _clear_projectiles() -> void:
	"""Free every bolt in the air. Called before a measurement window because the
	per-shooter `max_live` cap is real: two bolts left over from an earlier phase
	would make the next phase's boss refuse to fire, which reads as a broken arm."""
	for child in root.get_children():
		if child is BossProjectile:
			child.free()


func _check_ranged(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
	"""
	CHECK 8 — a RANGED boss actually fires, on its cooldown, and only where it is
	allowed to. Skipped entirely for a kind whose row is not `behavior: "ranged"`.

	enemy_behavior_selfcheck already drives the pure firing RULE
	(croc_steering.ranged_shot_due) over its whole band and cadence. What
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

	B and C call `_behave_ranged()` directly, the way the crush check calls
	`_on_player_collision`: what is under test is a guard inside one function, and
	staging a physics situation for it would add flake without adding reach — the
	detection code above the dispatch would refuse these quarries long before the
	arm ever saw them, which is precisely why the arm's own guard needs driving.
	"""
	var row: Dictionary = BossProbe.CROC_SCRIPT.SPECIES.get(BossProbe.subject, {})
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
			home.x + BossProbe.TERRITORY_RADIUS - 2.0, boss.global_position.y, home.z)
	boss.is_chasing = true
	boss._ranged_lock.clear()
	# Outward from a boss standing near its fence: in the band, out of the circle.
	boss.chase_target = Vector3(boss.global_position.x + band_mid, 0.0, home.z)
	var before: int = _live_projectiles()
	boss._behave_ranged()
	if _live_projectiles() > before:
		_fail("ranged: fired at a quarry %.1f m from home (territory is %.1f) from "
				% [_flat_distance(boss.chase_target, home), BossProbe.TERRITORY_RADIUS]
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


func _check_leap(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
	"""
	CHECK 9 — a LEAPING boss really leaves the ground, comes back to it, hops on
	its own clock, and cannot bound over its own fence. Skipped entirely for a kind
	whose row is not `behavior: "leap"`.

	Owner, verbatim: "let those Rock and Dragons be able to make a decent jumps
	like windman does with F key."

	enemy_behavior_selfcheck's leap probe already drives the pure rules — `leap_due`,
	`leap_airtime`, `leap_reach` — over the cadence and the whole escape race. What
	only a live world can show is the four things the ARM adds around them, and
	this arm needs a live world more than any other in the family: it is the only
	one whose inputs are `is_on_floor()` and whose output is `velocity`, and neither
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
	var row: Dictionary = BossProbe.CROC_SCRIPT.SPECIES.get(BossProbe.subject, {})
	if String(row.get("behavior", "")) != "leap":
		Sentinel.done("leap")
		return
	var airtime: float = CrocSteering.leap_airtime(row)
	if airtime <= 0.0:
		_fail("leap: behaviour is 'leap' but the row's arc constants give no"
				+ " airtime — already reported in enemy_behavior_selfcheck")
		Sentinel.done("leap")
		return
	var apex: float = float(row["leap_launch_speed"]) * airtime * 0.25
	var cycle: float = airtime + float(row["leap_cooldown"])

	# ---- A and B. IT LEAVES THE GROUND, LANDS, AND HOPS ON A CLOCK ---------
	boss.global_position = Vector3(home.x, boss.global_position.y, home.z)
	boss.velocity = Vector3.ZERO
	# Inside BOSS_DETECTION_RADIUS and inside the territory, so the boss engages
	# through the ordinary detection path rather than through anything set here.
	player.global_position = home + Vector3(BossProbe.DETECTION_RADIUS * 0.5, 0.0, 0.0)
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
				% [highest, LEAP_FRAMES, BossProbe.DETECTION_RADIUS * 0.5] + " away inside its"
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
			% [BossProbe.subject, highest, apex, float(longest_air) / 60.0, airtime]
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
	var lure: float = BossProbe.DETECTION_RADIUS - 1.0
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
	# Driven directly, the way check 8 drives the ranged gate and the crush check
	# drives the collision ordering: what is under test is one decision inside one
	# function, and both halves are taken at the SAME position with the SAME spent
	# clock, so only the BEARING differs and the control isolates the guard.
	player.global_position = home + Vector3(300.0, 0.0, 0.0)
	var reach: float = CrocSteering.leap_reach(boss.chase_speed_instance, row)
	# TWO METRES INSIDE THE FENCE, the same spot check 8 parks a ranged boss at.
	# It is the geometry where the two bearings differ in the only way that
	# matters: outward the projected landing clears the circle, inward it does not.
	var gate_at: float = BossProbe.TERRITORY_RADIUS - 2.0
	if gate_at + reach <= BossProbe.TERRITORY_RADIUS:
		# THE PHASE'S OWN NEGATIVE CONTROL. A reach short enough to land inside the
		# circle from two metres off the fence has no illegal landing for the gate
		# to refuse, so "it refused" below would be a hop the cooldown declined.
		_fail("leap: a %.1f m hop from %.1f m out lands inside the %.1f m"
				% [reach, gate_at, BossProbe.TERRITORY_RADIUS] + " territory, so this phase"
				+ " has no illegal landing to refuse and the gate goes untested")
		Sentinel.done("leap")
		return
	# PUT IT DOWN FIRST. Phase C ends wherever the window ended, which is as often
	# as not mid-arc, and both halves below drive the arm's GROUNDED branch — a
	# boss still falling would take the airborne early return and refuse the
	# control shot for a reason that has nothing to do with the leash.
	boss.global_position = Vector3(home.x + gate_at, rest_y + 0.5, home.z)
	boss.velocity = Vector3.ZERO
	for _i in BossProbe.SETTLE_FRAMES:
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
				% BossProbe.TERRITORY_RADIUS + " longer bounds the jump and the one rule this"
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
				% [absf(gate_at - reach), BossProbe.TERRITORY_RADIUS]
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
