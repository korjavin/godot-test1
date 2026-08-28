extends SceneTree
## ============================================================================
## BOSS PROJECTILE SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/projectile_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: `scripts/boss_projectile.gd` is the first ranged attack in
## the game, and every single thing it can get wrong is SILENT.
##
##   • THE FAIRNESS CONTRACT IS AN INEQUALITY BETWEEN NUMBERS IN THREE FILES —
##     the style's speed and hit radius in boss_projectile, WALK_SPEED and
##     RUN_SPEED over in player_controller. Nothing enforces it at runtime,
##     nothing looks wrong in the editor, and the symptom of breaking it is "the
##     snow boss feels unfair", reported weeks later by a player who cannot say
##     why. Somebody making the bolt "feel snappier" is a two-character edit away
##     from a shot you cannot dodge at a walk, and a slightly larger one away
##     from a shot that runs a fleeing player down from behind. So both
##     inequalities are MEASURED, per style, with a stated margin.
##   • A LOB IS A SOLVED ARC, not a tuned one. Drop the ½ out of the ballistic
##     solve, use the 3D distance where the horizontal one belongs, or integrate
##     the gravity in the wrong order, and it still flies, still looks like an
##     arc, and simply misses — permanently and harmlessly. So the landing point
##     is measured against the aim point.
##   • THE DODGE IS THE WHOLE FEATURE. "Aim at where they were" and "aim at where
##     they are" are one line apart in the source and indistinguishable from a
##     screenshot; the second one is a homing missile aimed by an unkillable
##     boss. So a scripted body WALKS out of the way and must survive — and, as
##     the negative control, a body that does NOT move must die. Half of that
##     pair alone would pass for a projectile that never hits anything at all.
##   • THE CAP IS THE WEB BUILD'S ONLY DEFENCE. A cooldown bug in some future
##     boss arm is a spray of live nodes; `fire()` is where that stops, and a cap
##     that leaks its count (a decrement in the wrong place, a chunk unload that
##     bypasses it) degrades to "no cap", or worse to "this boss may never fire
##     again", without any error.
##
## Every check carries a NEGATIVE CONTROL, because "it did not hit me" is also
## true of a projectile that is broken, frozen, or never spawned.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PROJECTILE: GDScript = preload("res://scripts/boss_projectile.gd")

## The player's gaits are read from the file that OWNS them rather than retyped,
## which is the entire point of check 1: these two constants and the style table
## must stay in step, and a retune on either side has to break this check.
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")

## The SPECIES table, scanned for `"ranged"` rows so a ranged boss landing later
## extends check 1 with no edit here.
const CROC_SCRIPT: GDScript = preload("res://scripts/piglet_crocodile_ai.gd")

## The cue table, so a style cannot ship without a muzzle sound (see check 1d).
const SOUND_SCRIPT: GDScript = preload("res://scripts/sound_manager.gd")

## Every key a params dict must carry. Listed here and not derived from one of
## the shipped styles on purpose: deriving it would let a style that DROPS a key
## redefine the requirement instead of failing it.
const REQUIRED_KEYS: Array[String] = [
	"style", "trajectory", "speed", "gravity", "hit_radius",
	"min_fire_range", "max_range", "lifetime", "max_live", "color", "mesh_scale",
]

## The lethality target: a Node3D in group "player" exposing the one method
## BossProjectile calls, counting the calls into a shared array. A stub rather
## than the real player scene because what is under test is the PROJECTILE's
## decision — and hit_by_crocodile() on the real controller spends a life,
## freezes the body and respawns it, all of which would move the target.
const HIT_STUB_SOURCE: String = """
extends Node3D
var hits: Array = []
func hit_by_crocodile() -> void:
	if hits.size() > 0:
		hits[0] += 1
"""

## Metre slop for straight-line flight, which is exact arithmetic (constant
## velocity, no integration error) — this is float noise and nothing else.
const EPS: float = 0.01

## Metre slop for where a LOB comes down. Two known, bounded sources, neither a
## bug: the arcade gravity is integrated semi-implicitly (velocity first, then
## position — the repo's convention everywhere), which lands the arc
## 0.5*g*dt*t low over the throw and therefore a little short; and the ground
## test is sampled once per physics frame, which is another 0.1 m of travel at
## 6 m/s. 0.35 m is comfortably above both and still an order of magnitude under
## any real mis-solve (dropping the ½ from the ballistic solve overshoots by
## metres, and using the 3D distance instead of the horizontal one undershoots
## by a similar margin).
const EPS_LANDING: float = 0.35

## How many physics frames a flight may take before we call it stuck. Every
## style here dies inside ~6 s; 900 frames is 15 s at 60 Hz.
const MAX_FRAMES: int = 900

var _failures: Array[String] = []


func _initialize() -> void:
	# `_initialize()` cannot await, so the measuring half runs as its own
	# coroutine and reports from in there. Reporting HERE would print a verdict
	# at frame 0, before a single projectile had moved — the vacuous pass every
	# sibling selfcheck in this repo warns about.
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


func _run() -> void:
	# Nothing added from _initialize() is in the tree yet, and a Node3D outside
	# the tree has no global transform — every placement below would silently
	# land at the origin. One frame settles it.
	await process_frame

	# CHECK 0 — did the thing under test even compile? A GDScript with a parse
	# error still LOADS: `PROJECTILE` becomes an empty script, every call into it
	# errors to the console, each check aborts mid-function without appending a
	# failure, and this file prints SELFCHECK OK having measured nothing. That is
	# the vacuous pass, and it is not hypothetical — it happened while this check
	# was being written. Probed with get(), which returns null instead of erroring.
	var styles: Variant = PROJECTILE.get("STYLES")
	if typeof(styles) != TYPE_DICTIONARY or (styles as Dictionary).is_empty():
		_fail("boss_projectile.gd did not compile, or exposes no STYLES — every "
				+ "check below would abort silently and this file would still "
				+ "print OK. Scroll up for the parse error.")
		_report()
		return

	_check_fairness()
	await _check_straight_flight()
	await _check_lob_landing()
	await _check_dodges()
	await _check_cap()
	_report()


# ============================================================================
# CHECK 1 — THE FAIRNESS CONTRACT (pure arithmetic, no simulation)
# ============================================================================

func _all_styles() -> Dictionary:
	"""
	Every params dict this game can fire, from BOTH sources: the styles the
	capability ships with, and any `"ranged"` dict a SPECIES row declares.

	The second half is what makes check 1 self-extending — the day the snow
	Titan's row lands, its numbers fall under the fairness contract without
	anybody remembering to come back here. Keyed by a label so a failure names
	which one broke.
	"""
	var out: Dictionary = {}
	for style_name in PROJECTILE.STYLES:
		out["STYLES[%s]" % style_name] = PROJECTILE.STYLES[style_name]
	for species in CROC_SCRIPT.SPECIES:
		var row: Dictionary = CROC_SCRIPT.SPECIES[species]
		if row.has("ranged"):
			out["SPECIES[%s].ranged" % species] = row["ranged"]
	return out


func _check_fairness() -> void:
	var styles: Dictionary = _all_styles()
	# Negative control on the scan itself: an empty (or one-entry) table would
	# pass every inequality below vacuously, which is exactly how a "generic"
	# check quietly stops checking anything.
	if styles.size() < 2:
		_fail("fairness: found %d projectile styles — this capability ships with "
				% styles.size() + "TWO on purpose (a lone style proves nothing "
				+ "about whether this is a capability or one boss's feature)")

	var walk: float = PLAYER_SCRIPT.WALK_SPEED
	var run: float = PLAYER_SCRIPT.RUN_SPEED

	for label in styles:
		var p: Dictionary = styles[label]

		var missing: Array[String] = []
		for key: String in REQUIRED_KEYS:
			if not p.has(key):
				missing.append(key)
		if not missing.is_empty():
			_fail("%s: params missing %s — see the key list in boss_projectile.gd's "
					% [label, missing] + "header")
			continue

		var trajectory: String = str(p["trajectory"])
		if trajectory != "straight" and trajectory != "lob":
			_fail("%s: trajectory is '%s' — there are exactly two ('straight', "
					% [label, trajectory] + "'lob'), and an unknown one silently "
					+ "flies straight")

		var speed: float = float(p["speed"])
		var hit_radius: float = float(p["hit_radius"])
		var min_range: float = float(p["min_fire_range"])
		if speed <= 0.0 or hit_radius <= 0.0 or min_range <= 0.0:
			_fail("%s: speed %.2f / hit_radius %.2f / min_fire_range %.2f must all "
					% [label, speed, hit_radius, min_range] + "be positive")
			continue

		# ---- 1a. DODGEABLE BY WALKING ----
		# The shortest flight this style can ever have is the one fired from its
		# own minimum range; measure the worst case, not a typical one.
		var flight: float = min_range / speed
		var walked: float = flight * walk
		var needed: float = PROJECTILE.DODGE_MARGIN * hit_radius
		if walked < needed:
			_fail(("%s: fired from its %.1f m minimum at %.1f m/s it is airborne "
					+ "%.2f s, in which a WALKING player (%.1f m/s) covers only "
					+ "%.2f m against a %.2f m hit radius — the contract needs "
					+ "%.1fx that radius (%.2f m). Slow it down, widen "
					+ "min_fire_range, or shrink the hit radius.")
					% [label, min_range, speed, flight, walk, walked, hit_radius,
					PROJECTILE.DODGE_MARGIN, needed])

		# ---- 1b. CANNOT RUN A FLEEING PLAYER DOWN ----
		if speed >= run:
			_fail("%s: horizontal speed %.2f m/s is not under RUN_SPEED (%.2f) — a "
					% [label, speed, run] + "projectile fired at a fleeing "
					+ "player's back must lose the race, the same way "
					+ "MAX_CHASE_SPEED sits under the slowest run")

		# ---- 1c. RANGE AND LIFETIME MUST OUTLAST THE FLIGHT ----
		# A style whose lifetime expires mid-flight, or whose max_range is inside
		# its own minimum firing range, is a shot that evaporates before it can
		# arrive — which LOOKS exactly like a fair, dodgeable projectile.
		var max_range: float = float(p["max_range"])
		var lifetime: float = float(p["lifetime"])
		if max_range <= min_range:
			_fail("%s: max_range %.1f m does not exceed min_fire_range %.1f m — "
					% [label, max_range, min_range] + "every shot would free "
					+ "itself before reaching its aim point")
		if lifetime <= max_range / speed:
			_fail("%s: lifetime %.2f s is not longer than the %.2f s it takes to "
					% [label, lifetime, max_range / speed] + "fly max_range — the "
					+ "lifetime is the backstop, the range is what should end a "
					+ "normal flight")
		if int(p["max_live"]) < 1:
			_fail("%s: max_live is %d — a cap under 1 means the boss can never "
					% [label, int(p["max_live"])] + "fire at all")

		# ---- 1d. EVERY STYLE HAS A MUZZLE CUE ----
		# The fairness contract measures the dodge from the muzzle flash. A style
		# with no announced cue is a style that kills people from off-screen, and
		# the sound manager's fallback would hide that behind a generic noise.
		if not SOUND_SCRIPT.PROJECTILE_SOUNDS.has(str(p["style"])):
			_fail("%s: style '%s' has no entry in sound_manager.PROJECTILE_SOUNDS "
					% [label, str(p["style"])] + "— it would fall back to a "
					+ "generic cue, and the telegraph is what makes the dodge fair")


# ============================================================================
# HARNESS
# ============================================================================

func _make_parent(offset: Vector3 = Vector3.ZERO) -> Node3D:
	"""
	Stand-in for the chunk a boss is parented to — and deliberately a HOSTILE
	one: scaled, rotated and displaced. A projectile that forgot `top_level`
	would inherit all three, so every flight measured through this parent is
	also a test that it did not.
	"""
	var parent := Node3D.new()
	root.add_child(parent)
	parent.global_position = offset
	parent.scale = Vector3(3.0, 3.0, 3.0)
	parent.rotation.y = PI / 3.0
	return parent


func _make_hit_stub(at: Vector3, hits: Array) -> Node3D:
	## A body in group "player" that records every hit_by_crocodile() call.
	var script := GDScript.new()
	script.source_code = HIT_STUB_SOURCE
	if script.reload() != OK:
		_fail("harness: the hit-counter stub script did not compile")
		return null
	var stub := Node3D.new()
	stub.set_script(script)
	stub.hits = hits
	root.add_child(stub)
	stub.global_position = at
	stub.add_to_group("player")
	return stub


func _fly(p: BossProjectile) -> Array:
	"""
	Step physics until the projectile frees itself, recording the whole path.

	Returns [positions: Array, ages: Array, frames: int] — the two arrays are
	PARALLEL, and that pairing is the point. A coroutine resumed from the
	`physics_frame` signal does not resume at a fixed place relative to when the
	nodes themselves are stepped, so "position after N awaits" is a quantity with
	an off-by-one in it. The projectile's own `_age` accumulator, on the other
	hand, is advanced in the very same lines that move it: sampling the two
	together gives a (position, time) pair that is exact by construction, at any
	tick rate, with no assumption about signal ordering at all.

	The LAST pair is the state it died in.
	"""
	var path: Array[Vector3] = []
	var ages: Array[float] = []
	var frames: int = 0
	while is_instance_valid(p) and frames < MAX_FRAMES:
		path.append(p.global_position)
		ages.append(p._age)
		if p.is_queued_for_deletion():
			break
		await physics_frame
		frames += 1
	return [path, ages, frames]


func _tick() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


# ============================================================================
# CHECK 2 — STRAIGHT FLIGHT
# ============================================================================

func _check_straight_flight() -> void:
	"""
	The thunder bolt: constant speed, dead straight, and it must end on RANGE.

	Fired LEVEL (muzzle and aim at the same height) so the ground test cannot be
	what ends it — that is what makes "it stopped at max_range" a real
	measurement instead of a coincidence.
	"""
	var params: Dictionary = PROJECTILE.STYLES["thunder_bolt"]
	var parent: Node3D = _make_parent(Vector3(50.0, 0.0, -20.0))
	var from := Vector3(0.0, 2.0, 0.0)
	var aim := Vector3(40.0, 2.0, 0.0)
	var p: BossProjectile = PROJECTILE.fire(from, aim, parent, params)
	if p == null:
		_fail("straight: fire() returned null with no shooter and no cap in play")
		parent.queue_free()
		return
	if not p.top_level:
		_fail("straight: the projectile is not top_level — it would inherit the "
				+ "chunk's (and a 6x boss's) transform, so a big boss would fire "
				+ "a big bolt travelling proportionally too far")

	var speed: float = float(params["speed"])
	var dir: Vector3 = (aim - from).normalized()
	var result: Array = await _fly(p)
	var path: Array = result[0]
	var ages: Array = result[1]
	var age: float = ages[ages.size() - 1]

	if path.size() < 10:
		_fail("straight: the bolt lived %d physics frames — it should be airborne "
				% path.size() + "for seconds, not frames")
		parent.queue_free()
		return

	# Every sample must sit exactly on the fire ray at exactly the declared
	# speed. Both halves matter: the ray test alone would pass a bolt that
	# crawls, and the speed test alone would pass one that curves.
	var worst_off_ray: float = 0.0
	var worst_speed_error: float = 0.0
	for i in range(path.size()):
		worst_off_ray = maxf(worst_off_ray, (path[i] - from).cross(dir).length())
		worst_speed_error = maxf(worst_speed_error,
				absf(from.distance_to(path[i]) - speed * float(ages[i])))
	if worst_off_ray > EPS:
		_fail("straight: the path leaves its fire ray by up to %.3f m — a "
				% worst_off_ray + "\"straight\" trajectory has no gravity and no "
				+ "steering")
	if worst_speed_error > EPS:
		_fail("straight: distance travelled is off by up to %.3f m from %.1f m/s "
				% [worst_speed_error, speed] + "— it is not moving at its "
				+ "declared speed")

	# It must end because it ran out of RANGE, with lifetime to spare.
	var travelled: float = from.distance_to(path[path.size() - 1])
	var max_range: float = float(params["max_range"])
	# One physics step of slop either side: the range test is sampled once per
	# tick, and the last state we can observe may be one tick before deletion.
	var slop: float = speed * _tick() + EPS
	if absf(travelled - max_range) > slop:
		_fail("straight: freed %.2f m from the muzzle against a %.1f m max_range"
				% [travelled, max_range])
	if age >= float(params["lifetime"]):
		_fail("straight: freed on LIFETIME (%.2f s) rather than on range — the "
				% age + "lifetime is meant to be the backstop, not the normal end")

	# Negative control on the range test: the same style with an absurd range
	# must still die, and die on the lifetime. Without this, a projectile that
	# frees itself for some unrelated reason passes everything above.
	var forever: Dictionary = params.duplicate(true)
	forever["max_range"] = 100000.0
	var q: BossProjectile = PROJECTILE.fire(from, aim, parent, forever)
	if q == null:
		_fail("straight: fire() returned null for the lifetime control")
	else:
		var qresult: Array = await _fly(q)
		var qages: Array = qresult[1]
		var qage: float = float(qages[qages.size() - 1])
		if qresult[2] >= MAX_FRAMES:
			_fail("straight: with the range removed the bolt never freed itself in "
					+ "%d frames — the lifetime backstop does not work, so a boss "
					% MAX_FRAMES + "firing forever leaks a node per shot")
		elif absf(qage - float(params["lifetime"])) > 2.0 * _tick():
			_fail("straight: with the range removed it freed at %.2f s instead of "
					% qage + "its %.2f s lifetime" % float(params["lifetime"]))

	parent.queue_free()
	await physics_frame


# ============================================================================
# CHECK 3 — LOB LANDING
# ============================================================================

func _check_lob_landing() -> void:
	"""
	The ice cream: it must come down ON the aim point, and it must come down
	because it hit the GROUND.

	The arc test below is the one that separates a lob from a straight shot at
	all — a mid-flight sample has to be measurably ABOVE the straight line from
	muzzle to aim, or "lob" is just a slower "straight".
	"""
	var params: Dictionary = PROJECTILE.STYLES["ice_cream"]
	var parent: Node3D = _make_parent(Vector3(-30.0, 0.0, 15.0))
	var from := Vector3(0.0, 3.0, 0.0)
	# Aimed AT THE GROUND PLANE, so "lands at the aim point" and "frees on ground
	# contact" are the same event and one measurement tests both.
	var aim := Vector3(0.0, 0.0, 12.0)
	var p: BossProjectile = PROJECTILE.fire(from, aim, parent, params)
	if p == null:
		_fail("lob: fire() returned null")
		parent.queue_free()
		return

	var result: Array = await _fly(p)
	var path: Array = result[0]
	var ages: Array = result[1]
	var age: float = ages[ages.size() - 1]
	if path.size() < 10:
		_fail("lob: lived only %d physics frames" % path.size())
		parent.queue_free()
		return

	var landed: Vector3 = path[path.size() - 1]
	if landed.distance_to(aim) > EPS_LANDING:
		_fail(("lob: came down at %v, %.2f m from the aim point %v (tolerance "
				+ "%.2f m) — the ballistic solve is not putting the arc through "
				+ "the point it was aimed at")
				% [landed, landed.distance_to(aim), aim, EPS_LANDING])
	if age >= float(params["lifetime"]):
		_fail("lob: freed on lifetime at %.2f s rather than on ground contact — "
				% age + "it never came down")
	if landed.y > PROJECTILE.GROUND_Y + EPS_LANDING:
		_fail("lob: freed %.2f m above the ground plane" % landed.y)

	# The arc itself. Halfway through the flight the projectile must be clearly
	# above the straight line it would have taken — this is what fails if the lob
	# quietly degrades into a straight shot.
	var mid: Vector3 = path[path.size() / 2]
	var chord_y: float = lerpf(from.y, aim.y, 0.5)
	if mid.y <= chord_y + 0.5:
		_fail("lob: at mid-flight it is %.2f m up against %.2f m for a straight "
				% [mid.y, chord_y] + "line to the same point — this is not an arc")

	# Horizontal speed is CONSTANT in a lob (no drag, no horizontal
	# acceleration), which is exactly what lets the fairness inequality use one
	# `speed` number for both trajectories. If that stopped being true, check 1
	# would be measuring a quantity the simulation does not have.
	var speed: float = float(params["speed"])
	var worst: float = 0.0
	for i in range(path.size()):
		var flat := Vector2(path[i].x - from.x, path[i].z - from.z)
		worst = maxf(worst, absf(flat.length() - speed * float(ages[i])))
	if worst > EPS:
		_fail("lob: horizontal travel drifts up to %.3f m from a constant %.1f m/s "
				% [worst, speed] + "— the fairness contract's flight-time formula "
				+ "assumes that constant")

	parent.queue_free()
	await physics_frame


# ============================================================================
# CHECK 4 — THE DODGE, AND ITS NEGATIVE CONTROL
# ============================================================================

func _check_dodges() -> void:
	## Run both halves for EVERY shipped style, not just the bolt: a lob and a
	## straight shot fail this in completely different ways.
	for style_name in PROJECTILE.STYLES:
		await _check_dodge(str(style_name), true)
		await _check_dodge(str(style_name), false)


func _check_dodge(style_name: String, walking: bool) -> void:
	"""
	Fire from exactly `min_fire_range` — the worst case the contract is written
	about — at a body that either walks perpendicular at WALK_SPEED or stands
	perfectly still.

	@param walking: true = the dodge (must SURVIVE), false = the negative control
	                (must be HIT). Both are needed: "never hit" is also what a
	                projectile that cannot hit anything looks like.
	"""
	var params: Dictionary = PROJECTILE.STYLES[style_name]
	var range_m: float = float(params["min_fire_range"])
	var parent: Node3D = _make_parent()
	# The quarry stands on the ground plane at +X; the muzzle is behind it and
	# above, roughly the height a large boss would actually shoot from.
	var hits: Array = [0]
	var stub: Node3D = _make_hit_stub(Vector3(range_m, 0.0, 0.0), hits)
	if stub == null:
		parent.queue_free()
		return
	var from := Vector3(0.0, 2.5, 0.0)

	var p: BossProjectile = PROJECTILE.fire(from, stub.global_position, parent, params)
	if p == null:
		_fail("dodge[%s]: fire() returned null" % style_name)
		stub.queue_free()
		parent.queue_free()
		return

	var step: float = PLAYER_SCRIPT.WALK_SPEED * _tick()
	var frames: int = 0
	var closest: float = INF
	while is_instance_valid(p) and not p.is_queued_for_deletion() and frames < MAX_FRAMES:
		closest = minf(closest, p.global_position.distance_to(stub.global_position))
		await physics_frame
		frames += 1
		if walking and is_instance_valid(stub):
			# Perpendicular to the fire ray (which runs along +X), at a plain
			# WALK. No running, no jumping, no ability.
			stub.global_position += Vector3(0.0, 0.0, step)
	if is_instance_valid(p):
		closest = minf(closest, p.global_position.distance_to(stub.global_position))

	var hit_radius: float = float(params["hit_radius"])
	if walking:
		if hits[0] != 0:
			_fail(("dodge[%s]: a player who merely WALKED perpendicular from the "
					+ "muzzle flash was still hit (closest approach %.2f m against "
					+ "a %.2f m hit radius). This is the fairness contract failing "
					+ "in SIMULATION, not in arithmetic — look for homing or a "
					+ "mid-flight retarget.") % [style_name, closest, hit_radius])
		if closest <= hit_radius * PROJECTILE.DODGE_MARGIN:
			_fail(("dodge[%s]: the walking body cleared the shot by only %.2f m, "
					+ "inside the %.1fx margin (%.2f m) check 1 promises — the "
					+ "arithmetic and the simulation disagree.")
					% [style_name, closest, PROJECTILE.DODGE_MARGIN,
					hit_radius * PROJECTILE.DODGE_MARGIN])
	else:
		if hits[0] != 1:
			_fail(("dodge[%s]: NEGATIVE CONTROL FAILED — a body standing still at "
					+ "the aim point was hit %d times, expected exactly 1 "
					+ "(closest approach %.2f m against a %.2f m hit radius). "
					+ "Everything else in this check passes trivially for a "
					+ "projectile that cannot hit anything.")
					% [style_name, hits[0], closest, hit_radius])

	if is_instance_valid(stub):
		stub.queue_free()
	parent.queue_free()
	await physics_frame


# ============================================================================
# CHECK 5 — THE PER-SHOOTER CAP, AND THE NO-PLAYER PATH
# ============================================================================

func _check_cap() -> void:
	"""
	Spam fire() from two shooters and from none, and watch the cap.

	The two-shooter half is the one that matters: a cap accidentally kept per
	CHUNK or per world would still bound the count, and would still be wrong —
	the second boss on the road would be silenced by the first one's volley.
	"""
	var params: Dictionary = PROJECTILE.STYLES["thunder_bolt"]
	var cap: int = int(params["max_live"])
	var parent: Node3D = _make_parent()
	var boss_a := Node3D.new()
	var boss_b := Node3D.new()
	root.add_child(boss_a)
	root.add_child(boss_b)

	var granted_a: int = 0
	var granted_b: int = 0
	for i in range(cap * 5):
		if PROJECTILE.fire(Vector3(0.0, 2.0, 0.0), Vector3(30.0, 2.0, 0.0),
				parent, params, boss_a) != null:
			granted_a += 1
		if PROJECTILE.fire(Vector3(0.0, 2.0, 5.0), Vector3(30.0, 2.0, 5.0),
				parent, params, boss_b) != null:
			granted_b += 1

	if granted_a != cap or granted_b != cap:
		_fail("cap: spamming fire() %d times granted %d shots to boss A and %d to "
				% [cap * 5, granted_a, granted_b] + "boss B, expected %d each — "
				% cap + "the cap is not being enforced inside fire()")
	if PROJECTILE.live_count(boss_a) != cap or PROJECTILE.live_count(boss_b) != cap:
		_fail("cap: live_count reports %d / %d against a cap of %d"
				% [PROJECTILE.live_count(boss_a), PROJECTILE.live_count(boss_b), cap])

	var alive: int = 0
	for child in parent.get_children():
		if child.get_script() == PROJECTILE:
			alive += 1
	if alive != cap * 2:
		_fail("cap: %d projectile nodes are parented to the chunk, expected %d "
				% [alive, cap * 2] + "(the count is bounded, but something else "
				+ "is spawning nodes)")

	# CHUNK UNLOAD. Freeing the parent must free the projectiles AND give their
	# cap slots back — a decrement that only ran on the queue_free() paths would
	# leave a boss permanently unable to shoot after one chunk cycle, which
	# nothing anywhere would report.
	parent.queue_free()
	await physics_frame
	await physics_frame
	if PROJECTILE.live_count(boss_a) != 0 or PROJECTILE.live_count(boss_b) != 0:
		_fail("cap: after the chunk was freed the live counts are %d / %d, not 0 "
				% [PROJECTILE.live_count(boss_a), PROJECTILE.live_count(boss_b)]
				+ "— the cap leaks, so a boss goes permanently silent")

	# And the slots really are usable again — the negative control on the line
	# above, which a bookkeeping dict nobody reads would also pass.
	var parent2: Node3D = _make_parent()
	var refired: int = 0
	for i in range(cap * 3):
		if PROJECTILE.fire(Vector3(0.0, 2.0, 0.0), Vector3(30.0, 2.0, 0.0),
				parent2, params, boss_a) != null:
			refired += 1
	if refired != cap:
		_fail("cap: after the chunk reload the shooter got %d shots, expected %d"
				% [refired, cap])

	# NO PLAYER IN THE TREE. Nothing here is in group "player", so every flight
	# in checks 2, 3 and 5 has been exercising that path — but it must also end
	# cleanly rather than hanging, so fly one to its natural death.
	var lone: BossProjectile = PROJECTILE.fire(Vector3(0.0, 2.0, 0.0),
			Vector3(30.0, 2.0, 0.0), parent2, params)
	if lone == null:
		_fail("no-player: fire() returned null for the uncapped lone shot")
	else:
		var lone_result: Array = await _fly(lone)
		if lone_result[2] >= MAX_FRAMES:
			_fail("no-player: a projectile fired into a tree with no player never "
					+ "freed itself")

	parent2.queue_free()
	boss_a.queue_free()
	boss_b.queue_free()
	await physics_frame
