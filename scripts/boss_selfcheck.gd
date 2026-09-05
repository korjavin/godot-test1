extends SceneTree
## ============================================================================
## BOSS SELF-CHECK — THE CONSTANTS, THE SEAM, AND THAT A BOSS HUNTS INSIDE
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## ONE OF FIVE. Bead `godot-test1-ftn.24` split the 1,529-line boss check by
## CHECK FAMILY, the way bead `godot-test1-ftn.13` split enemy_spawn: CI's
## `selfcheck-shard` globs `scripts/*_selfcheck.gd` and shards BY FILE, so a file
## that is 181 s of a 505 s suite is a floor no partition can beat. The five are
##
##     boss_selfcheck             the const chain, the territory seam, that a
##                                boss HUNTS inside its area, the resolved boss
##                                speed, the rigid model and the footprint
##     boss_leash_selfcheck       the fence chase and THE LEASH (one state chain)
##     boss_wander_selfcheck      it still WANDERS, contained, after disengaging
##     boss_arms_selfcheck        what a boss kind ADDS: the ranged arm, the leap
##     boss_immunity_selfcheck    crush immunity as an ORDERING, and every
##                                SPECIES row through the two row-key guards
##
## and `scripts/boss_probe.gd` is the harness they share. The split is mechanical:
## every check below is the code it always was, stamping the name it always
## stamped. The cut is where the MEASUREMENT put it — every phase is wall clock
## (`await physics_frame` is paced at the real 60 Hz, so a check costs its
## physics-frame count over 60), and the four 240-frame walking phases were 4.0 s
## each on every one of the seven boss kinds.
##
## WHY THIS FAMILY EXISTS. A boss is a MODIFIER on a species, so the rules pinned
## across these five files are inherited by every boss kind that follows the
## crocodile — and they fail SILENTLY. The half that lives here:
##
##   * THE CONST CHAIN (check 1) is a cross-file inequality nothing else guards:
##     BOSS_DETECTION_RADIUS <= BOSS_TERRITORY_RADIUS < crocodile_lod_manager's
##     SIM_RADIUS. Break the left link and a boss growls at a quarry it is
##     forbidden to walk to; break the right one and a boss can be asleep inside
##     its own territory.
##   * THE SEAM (check 2), at both ends of the boundary. An in_territory() that
##     forgot to subtract home, or a radius accessor wired to the wrong const,
##     passes every motion check in every one of these files by simply never
##     being false.
##   * THE OTHER HALF OF THE LEASH (check 3). The owner's sharpening was explicit
##     — "bosses limited by area, and hunt you inside it" — so a boss that merely
##     patrols fails this bead as hard as one that follows you home. This is the
##     half a leash written too aggressively breaks, and it is measured here
##     rather than beside the leash because it is the only phase the model-rigid
##     check can be asked after (it needs a body mid-chase).
##
## Harness style follows wade_selfcheck: a real physics world (a slab to stand
## on), a real boss instantiated from its real scene with setup_as_boss() called
## BEFORE add_child, and a scripted stand-in for the player — all of it in
## `boss_probe.gd` now, shared by the five.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

## How much closer the boss must get to a quarry inside its territory for
## "it HUNTS" to be proven rather than merely "it did not run away". At 7 m/s
## over 4 s it should close ~15 m; 3 m is far outside any drift or turn lag.
##
## IT IS ALSO WELL UNDER WHAT THE SLOWEST BOSS KIND MANAGES, which matters now
## that every BIOME_BOSS kind is driven through here: the snow titan chases at
## 3 m/s (an archer, deliberately under a walking player) and still closes ~12 m
## in the window. A kind slow enough to fail this is not a boss that hunts.
const HUNT_CLOSE_MIN: float = 3.0

## Float slack on the resolved chase speed, in m/s. The comparison is against a
## number the row states, so this is pure representation noise.
const SPEED_EPS: float = 0.01

## How far the animated model's basis may drift from square, as the largest
## absolute dot product between its normalized columns. 1e-4 is representation
## noise; the smallest shear this can produce is two orders of magnitude bigger
## (a 14-degree chase lean against a 1.6x stretch gives 0.37).
const ORTHO_EPS: float = 1e-4

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


func _run() -> void:
	_check_constants()
	# EVERY boss kind, not just the crocodile — see BossProbe.subjects().
	await BossProbe.drive(self, _fail, _on_boss)
	_report()


func _on_boss(boss: CharacterBody3D, player: BossProbe.StubPlayer, home: Vector3) -> void:
	"""This file's checks, against ONE boss kind, in the order they were run in
	before the split: the model must be asked mid-chase, so it follows the hunt."""
	_check_home(boss, home)
	_check_resolved_speed(boss)
	await _check_hunts_inside(boss, player, home)
	_check_model_rigid(boss)
	_check_footprint(boss)


func _check_constants() -> void:
	"""
	CHECK 1 — the inequality chain, which is the reason the number is 32 and not
	whatever felt right. See BOSS_TERRITORY_RADIUS for what each link buys.
	"""
	if BossProbe.DETECTION_RADIUS > BossProbe.TERRITORY_RADIUS:
		_fail("consts: BOSS_DETECTION_RADIUS (%.1f) > BOSS_TERRITORY_RADIUS (%.1f) — "
				% [BossProbe.DETECTION_RADIUS, BossProbe.TERRITORY_RADIUS]
				+ "a boss could smell a quarry it is forbidden to walk to, and would "
				+ "growl once and then stand still")
	if BossProbe.TERRITORY_RADIUS >= BossProbe.SIM_RADIUS:
		_fail("consts: BOSS_TERRITORY_RADIUS (%.1f) >= LOD SIM_RADIUS (%.1f) — "
				% [BossProbe.TERRITORY_RADIUS, BossProbe.SIM_RADIUS]
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
	if _flat_distance(home, Vector3.ZERO) > BossProbe.CONTAIN_EPS:
		_fail("home: home_position is %s, expected the spawn spot (0,0)" % home)
	if not boss.in_territory(home):
		_fail("seam: in_territory() says the boss's own home is outside its territory")
	# The seam, at both ends of the boundary. A radius accessor wired to the wrong
	# const, or an in_territory() that forgot to subtract home, passes every
	# motion check in every one of these files by simply never being false.
	var just_in := home + Vector3(BossProbe.TERRITORY_RADIUS - 0.5, 0.0, 0.0)
	var just_out := home + Vector3(BossProbe.TERRITORY_RADIUS + 0.5, 0.0, 0.0)
	if not boss.in_territory(just_in):
		_fail("seam: in_territory() rejects a point %.1f m from home (radius is %.1f)"
				% [BossProbe.TERRITORY_RADIUS - 0.5, BossProbe.TERRITORY_RADIUS])
	if boss.in_territory(just_out):
		_fail("seam: in_territory() accepts a point %.1f m from home (radius is %.1f)"
				% [BossProbe.TERRITORY_RADIUS + 0.5, BossProbe.TERRITORY_RADIUS])
	if absf(boss.territory_radius() - BossProbe.TERRITORY_RADIUS) > BossProbe.CONTAIN_EPS:
		_fail("seam: territory_radius() returned %.2f, expected %.2f"
				% [boss.territory_radius(), BossProbe.TERRITORY_RADIUS])
	Sentinel.done("home")


func _check_hunts_inside(boss: CharacterBody3D, player: BossProbe.StubPlayer,
		home: Vector3) -> void:
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
	await _frames(BossProbe.PHASE_FRAMES)
	var after := _flat_distance(boss.global_position, player.global_position)

	if not boss.is_chasing:
		_fail("hunt: quarry %.1f m away, inside detection (%.1f) and inside the "
				% [after, BossProbe.DETECTION_RADIUS]
				+ "territory (%.1f), and the boss is not chasing" % BossProbe.TERRITORY_RADIUS)
	if before - after < HUNT_CLOSE_MIN:
		_fail("hunt: boss closed only %.2f m in %d frames (needed %.1f) — a boss "
				% [before - after, BossProbe.PHASE_FRAMES, HUNT_CLOSE_MIN]
				+ "inside its own territory must hunt, not patrol")
	BossProbe.assert_contained(_fail, boss, home, "hunt")
	Sentinel.done("hunts_inside")


func _check_model_rigid(boss: CharacterBody3D) -> void:
	"""
	CHECK 6c — the animated model is a RIGID body, however its scene scaled it.

	Called with the boss mid-chase (straight after the hunt phase), so its model
	is carrying a real forward lean and a real waddle roll rather than sitting at
	identity, which is the only state in which this can fail. That dependency is
	why it stayed in this file when the leash and the wander left it.

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

	AND AS OF 2026-09-05 THAT LAST SENTENCE IS NO LONGER TRUE, WHICH IS WORTH
	SAYING OUT LOUD: every shipped boss scene's `Model` node now sits at identity
	(the clown's included), so `model_base_scale` is Vector3.ONE and the two
	compositions are indistinguishable — mutating `scaled_local` to `scaled` in
	both `_animate_*` sites passes this check, on this file AND on the one it was
	split out of. The check is DORMANT, not wrong: it costs nothing, it is asked
	of every kind, and it bites again the day an art bead ships a stretched model.
	Restoring its teeth needs a subject with a non-uniform rest scale, which is a
	bead of its own and not a line to add here.

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

	It is asked of every kind `BossProbe.subjects()` yields, so a boss added to
	BIOME_BOSS is measured on the commit that adds it and an art bead that swaps in
	a bigger mesh cannot quietly outgrow its station.
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

	var budget: float = BossProbe.TERRAIN_SCRIPT.BOSS_FOOTPRINT_RADIUS_PER_SCALE
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
	else in this family could see that go wrong: at 7 m/s a titan passes the hunt
	check, the fence check and the leash check exactly as it does at 3 m/s — it
	just silently becomes the melee giant the owner said it is not.

	The row is read here rather than restated, so this is a comparison between the
	table and the body, which is the only pair that can disagree. The boss stands
	at x = 0, where the distance gradient's factor is exactly 1.0, so the expected
	value is the row's number with the MAX_CHASE_SPEED clamp on top and nothing
	else in the way.
	"""
	var row: Dictionary = BossProbe.CROC_SCRIPT.SPECIES.get(BossProbe.subject, {})
	var wanted: float = minf(
			float(row.get("boss_chase_speed", BossProbe.CROC_SCRIPT.BOSS_CHASE_SPEED)),
			BossProbe.CROC_SCRIPT.MAX_CHASE_SPEED)
	if absf(float(boss.chase_speed_instance) - wanted) > SPEED_EPS:
		_fail("speed: _ready() resolved chase_speed_instance %.2f, but the row asks "
				% boss.chase_speed_instance + "for %.2f — a boss inherits "
				% wanted + "BOSS_CHASE_SPEED (%.1f) unless its row opts out with "
				% BossProbe.CROC_SCRIPT.BOSS_CHASE_SPEED + "boss_chase_speed, and this kind's "
				+ "row is not being honoured")
	Sentinel.done("resolved_speed")
