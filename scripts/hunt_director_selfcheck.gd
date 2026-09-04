extends SceneTree
## ============================================================================
## HUNT ENCOUNTER DIRECTOR SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/hunt_director_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: `scripts/hunt_director.gd` is the ENTIRE fairness budget of
## the hunter class. Hunters are exempt from the Stink Wave and uncrushable by a
## giant Teibi, so unlike every other predator they have no ability-based
## counterplay at all — what keeps an encounter tense instead of a dead end is
## the pursuer cap, the lull and the guaranteed open escape sector, and all three
## live in one file that nothing else in the game reads.
##
## Every way that file can break is SILENT, and each way looks like the others
## from the outside:
##
##   • A CAP THAT DOES NOT CAP looks exactly like a cap that works, right up to
##     the moment four robots converge. Nothing errors, no frame is dropped, and
##     the report is "the hunters feel unfair", weeks later, from a player who
##     cannot say why.
##   • A LULL THAT NEVER EXPIRES and a lull that never STARTS are both "the
##     hunters behaved oddly once". So both ends are measured, in both
##     directions, each with the negative control it needs — including a
##     PARTLY-expired lull, which is what separates a real 15 s window from one
##     that is cleared by the first tick that sees it.
##   • THE ESCAPE SECTOR IS PURE GEOMETRY OVER A WRAPPING CIRCLE, the classic
##     home of an off-by-one-turn bug that answers plausibly for most inputs and
##     catastrophically for the surround. It is therefore checked against an
##     INDEPENDENT oracle written a different way (an O(n²) modular minimum: no
##     sort, no normalisation pass, no wrap term) rather than against a
##     restatement of the same algorithm — two implementations sharing no
##     arithmetic cannot share an arithmetic bug. The sweep also asserts that it
##     DENIED something, because a function that grants everything satisfies
##     "granted configurations leave an open sector" vacuously.
##   • BUCKETING BY QUARRY is the whole multiplayer story, and a GLOBAL cap
##     passes every single-quarry check above while starving a room.
##   • THE ABSENT-DIRECTOR DEGRADE is what lets the standalone
##     `hunter_robot.tscn`, every self-check and every headless harness keep
##     working. It is measured through the SHIPPED `_hunt_close_granted()` on a
##     LIVE hunter, in both directions: without a director it must grant, and
##     with one it must actually take the director's answer. Either half alone
##     passes for a seam wired to nothing.
##
## The pure decision core (`grant_engagement`, `escape_sector_open`) is driven
## DIRECTLY, so what is measured is the logic the game ships rather than a copy
## of it — the same discipline `hunt_steer_point`, `pack_steer_point` and
## `charge_steer_point` are held to.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const DIRECTOR: GDScript = preload("res://scripts/hunt_director.gd")

## The standalone hunter scene the bead names by hand as the thing that must keep
## working with no director in the world.
const HUNTER_SCENE: String = "res://scenes/characters/hunter_robot.tscn"

## The SPECIES row whose behaviour is "hunt", assigned before add_child (the
## call-order contract in piglet_crocodile_ai.gd) so the live probe is a real
## hunter and not a crocodile wearing a robot mesh.
const HUNT_SPECIES: String = "hunter_robot"

## Check 8 drives the real telegraph end to end rather than restating it — see
## there for why a stub would not notice the interesting breakages.
const LOD_SCRIPT: String = "res://scripts/crocodile_lod_manager.gd"
const VIGNETTE_SCRIPT: String = "res://scripts/danger_vignette.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## A stand-in for a hunter, exposing exactly the four members the director reads
## off one and nothing else. A stub rather than the real scene because what is
## under test in checks 4 and 5 is the DIRECTOR's bookkeeping: instantiating a
## handful of live CharacterBody3Ds would drag in gravity, model loading and the
## whole hunt arm, none of which decides anything those checks measure. The live
## scene is used in check 6, where it IS the subject.
const HUNTER_STUB_SOURCE: String = """
extends Node3D
var spec: Dictionary = {"behavior": "hunt"}
var is_chasing: bool = true
var chase_target: Vector3 = Vector3.ZERO
var _hunt_lock: Dictionary = {"closing": false, "disengage": 0.0}
"""

## How many adversarial bearing sets the escape-sector sweep draws, and the seed
## it draws them from — fixed, so a failure is reproducible. This file is pacing
## and debug, and stands outside the world's determinism contract exactly as the
## director itself does.
const SWEEP_SETS: int = 400
const SWEEP_SEED: int = 20260828

## Radian slop for the sector comparisons. The oracle is fed the SAME float32
## values the shipped function sees (see the sweep), so this covers only the
## ordering noise between a sort-and-difference and a modular minimum — orders
## of magnitude under the smallest thing either could get wrong. Sets whose
## widest gap lands inside this band of the guarantee are skipped rather than
## judged; the two hand-built near-boundary cases below cover that band exactly.
const EPS: float = 1e-4

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# The live probe in check 6 needs the tree to have settled, so the measuring
	# half runs as its own coroutine and reports from in there. Reporting from
	# here would print a verdict at frame 0 — the vacuous pass every sibling
	# selfcheck in this repo warns about.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _run() -> void:
	await process_frame

	# CHECK 0 — did the thing under test even compile? A GDScript with a parse
	# error still LOADS: `DIRECTOR` becomes an empty script, every call into it
	# errors to the console, each check aborts mid-function without appending a
	# failure, and this file prints SELFCHECK OK having measured nothing. Probed
	# with get(), which returns null instead of erroring.
	var cap: Variant = DIRECTOR.get("MAX_PURSUERS")
	if typeof(cap) != TYPE_INT or int(cap) < 1:
		_fail("hunt_director.gd did not compile, or exposes no MAX_PURSUERS — "
				+ "every check below would abort silently and this file would "
				+ "still print OK. Scroll up for the parse error.")
		_report()
		return

	_check_cap()
	_check_lull_pure()
	_check_escape_sector()
	_check_live_pacing()
	_check_reaped_grab()
	_check_two_quarries()
	await _check_absent_director()
	await _check_dread_channels()
	_report()


# ============================================================================
# CHECK 1 — RULE 1, the pursuer cap
# ============================================================================

func _check_cap() -> void:
	## Drives the shipped `grant_engagement` at every count from 0 to N+1 with the
	## other two rules held OPEN (no lull, no bearings), so the only thing that
	## can deny is the cap and a denial here is unambiguous.
	if not _rules_isolated():
		Sentinel.done("cap")
		return
	var cap: int = DIRECTOR.MAX_PURSUERS
	for closing: int in range(cap + 2):
		var granted: bool = DIRECTOR.grant_engagement(
				PackedFloat32Array(), closing, 0.0, 0.0)
		var expected: bool = closing < cap
		if granted == expected:
			continue
		if expected:
			_fail("cap: with %d hunter(s) already closing (cap is %d) the director "
					% [closing, cap] + "REFUSED a fresh engagement on an otherwise "
					+ "open quarry — no lull and no bearings, so nothing but the "
					+ "cap could have denied it. The cap is starving the class "
					+ "instead of pacing it.")
		else:
			_fail("cap: with %d hunter(s) already closing the director granted a "
					% closing + "%dth (cap is %d). Rule 1 is not enforced — that "
					% [closing + 1, cap] + "is the surround the escape-sector rule "
					+ "exists to make impossible, arriving through the front door.")
	Sentinel.done("cap")


# ============================================================================
# CHECK 2 — RULE 2 as pure logic
# ============================================================================

func _check_lull_pure() -> void:
	## The lull, driven directly with the cap and the sector held open. Both
	## directions: any time left denies, no time left grants. A one-sided check
	## passes for a director that denies everything forever.
	if not _rules_isolated():
		Sentinel.done("lull_pure")
		return
	if not DIRECTOR.grant_engagement(PackedFloat32Array(), 0, 0.0, 0.0):
		_fail("lull: with zero seconds of lull left, an unopposed hunter on an "
				+ "empty quarry was still refused — every engagement in the game "
				+ "is denied and no hunter ever closes on anything")
	if DIRECTOR.grant_engagement(PackedFloat32Array(), 0, 0.001, 0.0):
		_fail("lull: a quarry with 0.001 s of lull left still granted a fresh "
				+ "engagement. Rule 2 is not enforced, so a grab buys the player "
				+ "nothing and 'hunters frighten constantly, take almost never' "
				+ "is not true of this build.")
	if DIRECTOR.grant_engagement(PackedFloat32Array(), 0, DIRECTOR.ENGAGE_LULL, 0.0):
		_fail("lull: a quarry with a FULL %.1f s lull granted a fresh engagement"
				% DIRECTOR.ENGAGE_LULL)
	Sentinel.done("lull_pure")


# ============================================================================
# CHECK 3 — RULE 3, the escape-sector guarantee
# ============================================================================

func _check_escape_sector() -> void:
	var min_sector: float = DIRECTOR.MIN_ESCAPE_SECTOR
	if min_sector <= 0.0 or min_sector >= TAU:
		_fail("escape sector: MIN_ESCAPE_SECTOR is %.3f rad — outside (0, TAU) it "
				% min_sector + "is either always open (no guarantee at all) or "
				+ "never open (every hunter frozen on its ring forever)")
		Sentinel.done("escape_sector")
		return
	var guarantee_deg: float = rad_to_deg(min_sector)

	# ---- the merciful degenerate case ---------------------------------------
	# One lone hunter has the whole circle behind the player. It must be granted;
	# a director that refuses here paces nothing, it simply never engages.
	if not DIRECTOR.escape_sector_open(PackedFloat32Array(), 1.234):
		_fail("escape sector: a LONE hunter (no other bearings at all) was "
				+ "refused. With 360° open there is nothing to guard, so this is "
				+ "the wrap arithmetic collapsing the one-element case to a zero "
				+ "gap — and it would freeze the very first hunter you ever meet.")

	# ---- the surround, spelled out ------------------------------------------
	# Five bearings 72° apart leave every gap under the guarantee, so a sixth
	# approach from ANY direction must be refused. This is the exact
	# configuration the rule exists to forbid.
	var surround := PackedFloat32Array()
	for i: int in range(5):
		surround.append(TAU * float(i) / 5.0)
	for probe: int in range(12):
		var bearing: float = TAU * float(probe) / 12.0
		if DIRECTOR.escape_sector_open(surround, bearing):
			_fail("escape sector: a hunter approaching on %.0f° was granted into "
					% rad_to_deg(bearing) + "a ring of five already 72° apart — "
					+ "every gap is under the %.0f° guarantee before it even "
					% guarantee_deg + "arrives. That is the instant surround, and "
					+ "this class has no ability counterplay to it.")
			break

	# ---- both sides of the boundary -----------------------------------------
	# Five bearings arranged so the widest gap is 90.1° (must grant) and the same
	# shape at 89.9° (must deny). A guarantee read off the wrong constant, or a
	# gap computation that is off by a term, breaks one of the pair. Deliberately
	# NOT probed at exactly 90.000°: the shipped function works in float32
	# (PackedFloat32Array) so the exact-equality case is decided by rounding, and
	# a check that depended on it would be measuring the float format.
	var just_open := _ring_with_widest_gap(90.1)
	if not DIRECTOR.escape_sector_open(just_open, 0.0):
		_fail("escape sector: a ring whose widest gap is 90.1° — just OVER the "
				+ "%.0f° guarantee — was refused. The threshold is set too high, "
				% guarantee_deg + "so hunters stall on their rings in geometry "
				+ "the player can plainly run out of.")
	var just_closed := _ring_with_widest_gap(89.9)
	if DIRECTOR.escape_sector_open(just_closed, 0.0):
		_fail("escape sector: a ring whose widest gap is 89.9° — just UNDER the "
				+ "%.0f° guarantee — was granted. The threshold is not being "
				% guarantee_deg + "enforced, only the gross surround above it.")

	# ---- the adversarial sweep, against the oracle ---------------------------
	# Includes bearings pushed outside (-PI, PI] by whole turns: atan2 never
	# produces those, but the function is public, static and pure, so a caller
	# handing it un-normalised angles must not get a different circle. That is
	# what the fposmod normalisation in the shipped function is for.
	var rng := RandomNumberGenerator.new()
	rng.seed = SWEEP_SEED
	var denials: int = 0
	var grants: int = 0
	var skipped: int = 0
	for s: int in range(SWEEP_SETS):
		var n: int = rng.randi_range(0, 6)
		# One packed array holds everything, so the oracle below judges the SAME
		# float32 values the shipped function sees. Feeding it the float64
		# originals instead would make float format the thing under test.
		var packed := PackedFloat32Array()
		for i: int in range(n + 1):
			packed.append(rng.randf_range(-PI, PI)
					+ TAU * float(rng.randi_range(-2, 2)))
		var bearings: PackedFloat32Array = packed.slice(0, n)
		var candidate: float = packed[n]

		var full: Array[float] = []
		for b: float in packed:
			full.append(b)
		var widest: float = _widest_gap_oracle(full)

		# Right on the threshold the two implementations may legitimately round
		# apart. Those inputs are covered exactly by the hand-built pair above.
		if absf(widest - min_sector) < EPS:
			skipped += 1
			continue

		var granted: bool = DIRECTOR.escape_sector_open(bearings, candidate)
		if granted:
			grants += 1
		else:
			denials += 1

		if granted != (widest >= min_sector):
			_fail("escape sector: set #%d %s + candidate %.4f — the shipped "
					% [s, str(bearings), candidate] + "function said %s but the "
					% ("GRANT" if granted else "DENY") + "independent oracle "
					+ "measures a widest gap of %.4f rad (%.1f°) against a %.1f° "
					% [widest, rad_to_deg(widest), guarantee_deg] + "guarantee. "
					+ "The sort, the wrap term and the normalisation disagree "
					+ "with modular arithmetic on this ring.")
			break

		# THE HARD INVARIANT ITSELF, stated independently of the comparison above
		# so it survives a rewrite of either: whatever is granted must leave the
		# quarry a way out.
		if granted and widest < min_sector:
			_fail("escape sector: set #%d was GRANTED but the resulting ring's "
					% s + "widest gap is only %.1f°, under the %.1f° guarantee. "
					% [rad_to_deg(widest), guarantee_deg] + "A quarry can be "
					+ "surrounded with no way out, which is the one thing this "
					+ "rule exists to prevent.")
			break

	# NEGATIVE CONTROLS on the sweep. A function that returns true unconditionally
	# satisfies "everything granted leaves an open sector" vacuously and would
	# sail through every assertion above except the first of these.
	if denials == 0:
		_fail("escape sector: %d adversarial sets produced ZERO denials (%d "
				% [SWEEP_SETS, skipped] + "skipped at the threshold) — the sweep "
				+ "is measuring a rule that cannot refuse anything, so its "
				+ "invariant holds vacuously")
	if grants == 0:
		_fail("escape sector: %d adversarial sets produced ZERO grants — the rule "
				% SWEEP_SETS + "refuses everything, which paces nothing and "
				+ "freezes every hunter in the world on its standoff ring")
	Sentinel.done("escape_sector")


func _ring_with_widest_gap(widest_deg: float) -> PackedFloat32Array:
	## Five bearings whose widest gap is exactly `widest_deg`: three gaps of that
	## size and the remaining two turns split evenly between them. Built rather
	## than hand-typed so the two boundary probes above cannot drift apart, and so
	## the shape is obviously the same on both sides of the threshold.
	var wide: float = deg_to_rad(widest_deg)
	var rest: float = (TAU - 3.0 * wide) * 0.5
	var out := PackedFloat32Array()
	var at: float = 0.0
	for gap: float in [wide, wide, wide, rest, rest]:
		out.append(at)
		at += gap
	return out


func _widest_gap_oracle(bearings: Array[float]) -> float:
	## INDEPENDENT implementation of "the widest gap around the circle", written
	## deliberately unlike the shipped one: for each bearing, the modular distance
	## to its nearest neighbour going one fixed way round, maximised. No sort, no
	## normalisation pass, no wrap term — fposmod maps every difference into
	## [0, TAU) regardless of how many whole turns either angle carries, so no
	## input is out of range by construction.
	if bearings.size() <= 1:
		return TAU
	var widest: float = 0.0
	for a: float in bearings:
		var nearest: float = TAU
		for b: float in bearings:
			var d: float = fposmod(b - a, TAU)
			# `d == 0` is `a` itself, or another hunter on precisely the same
			# bearing — neither is a gap.
			if d > 0.0:
				nearest = minf(nearest, d)
		widest = maxf(widest, nearest)
	return widest


# ============================================================================
# CHECK 4 — RULE 2 on the live director: grab -> lull -> expiry -> hard chase
# ============================================================================

func _check_live_pacing() -> void:
	## The bookkeeping half of rule 2 on a real director node. A grab must deny
	## the next engagement on that quarry, a PARTLY expired lull must still deny
	## it, an expired one must grant it again, and a chase that runs past
	## HARD_CHASE_LIMIT must buy the same lull with no grab at all.
	##
	## Three stubs, placed on bearings 0°, 180° and 90°, so every ring below has
	## a gap of at least 180° and rule 3 can never be the reason for a denial.
	## Every refusal in this check is therefore the lull or the cap, and the two
	## are separated by keeping the cap deliberately un-full.
	var director: Node = _make_director()
	var quarry := Vector3.ZERO
	var a: Node3D = _make_stub(quarry, Vector3(6.0, 0.0, 0.0))
	var b: Node3D = _make_stub(quarry, Vector3(-6.0, 0.0, 0.0))
	var c: Node3D = _make_stub(quarry, Vector3(0.0, 0.0, 6.0))

	if not director.request_hunt_close(a):
		_fail("live pacing: the FIRST hunter on an untouched quarry was refused — "
				+ "no cap pressure, no lull, and a 180° gap on the circle, so "
				+ "nothing in the rules could have denied it")
		_teardown([director, a, b, c])
		Sentinel.done("live_pacing")
		return

	# THE GRAB, reported through the public verb the bead specifies. The hit
	# itself was already paid in full by the ordinary collision path before this
	# runs — nothing here softens it; it only paces what comes next.
	a._hunt_lock["closing"] = false
	a._hunt_lock["disengage"] = 8.0
	director.report_grab(a)

	if director.request_hunt_close(b):
		_fail("live pacing: a second hunter was granted immediately after a grab "
				+ "landed on the same quarry. There is no post-grab lull at all, "
				+ "so the player is re-taken on the respawn frame.")

	# HALF the lull. Still denied — the control that separates a real 15 s window
	# from one the first tick clears.
	var aged: float = _age(director, DIRECTOR.ENGAGE_LULL * 0.4)
	if director.request_hunt_close(b):
		_fail("live pacing: the lull was gone after only %.1f s of a %.1f s "
				% [aged, DIRECTOR.ENGAGE_LULL] + "window — the tick is clearing "
				+ "it rather than counting it down")

	# The rest of it, with margin. It must grant again: a lull that never lifts is
	# a hunter class that retires after its first success.
	aged += _age(director, DIRECTOR.ENGAGE_LULL + 1.0)
	if not director.request_hunt_close(b):
		_fail("live pacing: after %.1f s — well past the %.1f s lull — the quarry "
				% [aged, DIRECTOR.ENGAGE_LULL] + "still refuses every engagement. "
				+ "The lull never expires, so one grab retires the hunters "
				+ "permanently.")
		_teardown([director, a, b, c])
		Sentinel.done("live_pacing")
		return

	# ---- rule 2's second half: the hard chase -------------------------------
	# `b` keeps closing, which is what the arm writes back after a grant. One
	# closer against a cap of at least two leaves a free slot, so the refusal
	# below cannot be the cap — it can only be the hard-chase timer.
	b._hunt_lock["closing"] = true
	_age(director, DIRECTOR.HARD_CHASE_LIMIT + 1.0)
	if director.request_hunt_close(c):
		_fail("hard chase: after %.1f s of unbroken engagement on one quarry a "
				% DIRECTOR.HARD_CHASE_LIMIT + "fresh hunter was still granted, "
				+ "with a cap slot free and a 90° gap open — so nothing but the "
				+ "hard-chase timer could have refused it, and it did not. A "
				+ "pursuit can rotate new robots in forever and never let up.")

	# And that lull expires like any other: the control proving the line above
	# measured a TIMER rather than a permanently poisoned bucket.
	_age(director, DIRECTOR.ENGAGE_LULL + 1.0)
	if not director.request_hunt_close(c):
		_fail("hard chase: the lull a long pursuit bought never expired — after "
				+ "%.1f s that quarry refuses every hunter for the rest of the "
				% DIRECTOR.ENGAGE_LULL + "run")

	_teardown([director, a, b, c])
	Sentinel.done("live_pacing")


# ============================================================================
# CHECK 4b — the route a grab ACTUALLY takes to this director
# ============================================================================

func _check_reaped_grab() -> void:
	## Nothing in `piglet_crocodile_ai.gd` calls `report_grab`. The bite path
	## writes `hunt_disengage_time` into the arm's own `_hunt_lock` and the
	## director's tick READS it — so a unit that has dropped out of `closing` with
	## time left on that clock is the only signal in the game that a retrieval
	## landed, and reaping it is the only live route rule 2 has.
	##
	## THIS CHECK EXISTS BECAUSE MUTATION TESTING FOUND ITS ABSENCE. Check 4 calls
	## the public verb directly, so deleting the reap's grab detection entirely
	## left the whole suite green while the shipped game lost its post-grab lull.
	##
	## The NEGATIVE CONTROL is the substance of it: a hunter that merely LOST its
	## quarry drops out through the same code with an empty disengage clock, and
	## must buy the player nothing. Without that half, "every disengagement starts
	## a lull" passes — and that reads in play as hunters that go quiet whenever
	## you break line of sight, which is a tell, which is the one thing this class
	## is not allowed to give the player.

	# ---- it took you: the tick must find the withdrawal and start the lull ----
	var took: Node = _make_director()
	var a: Node3D = _make_stub(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var b: Node3D = _make_stub(Vector3.ZERO, Vector3(-6.0, 0.0, 0.0))
	if not took.request_hunt_close(a):
		_fail("reaped grab: the harness could not seat the hunter that is about "
				+ "to grab, so neither half of this check would mean anything")
		_teardown([took, a, b])
		Sentinel.done("reaped_grab")
		return
	# Exactly what the bite path leaves behind: no longer closing, seconds owed on
	# the disengage clock. Nobody calls report_grab — the director must notice.
	a._hunt_lock["closing"] = false
	a._hunt_lock["disengage"] = 8.0
	_age(took, 1.0)
	if took.request_hunt_close(b):
		_fail("reaped grab: a hunter withdrew with time still on its disengage "
				+ "clock — the signature of a landed grab, and the ONLY signal "
				+ "the game gives this director — and no lull started. Nothing "
				+ "calls report_grab in the shipped code, so rule 2 is inert in "
				+ "play however well it passes when driven by hand.")
	_teardown([took, a, b])

	# ---- it lost you: the same drop must buy the player nothing --------------
	var lost: Node = _make_director()
	var c: Node3D = _make_stub(Vector3.ZERO, Vector3(6.0, 0.0, 0.0))
	var d: Node3D = _make_stub(Vector3.ZERO, Vector3(-6.0, 0.0, 0.0))
	if not lost.request_hunt_close(c):
		_fail("reaped grab: the harness could not seat the hunter that is about "
				+ "to lose its quarry, so the negative control is untested")
		_teardown([lost, c, d])
		Sentinel.done("reaped_grab")
		return
	c._hunt_lock["closing"] = false
	c._hunt_lock["disengage"] = 0.0
	_age(lost, 1.0)
	if not lost.request_hunt_close(d):
		_fail("reaped grab: a hunter that merely LOST its quarry — nothing taken, "
				+ "an empty disengage clock — still put that quarry into a lull. "
				+ "Every broken line of sight now pauses the class, which the "
				+ "player reads as a tell.")
	_teardown([lost, c, d])
	Sentinel.done("reaped_grab")


# ============================================================================
# CHECK 5 — the multiplayer rule: two quarries bucket independently
# ============================================================================

func _check_two_quarries() -> void:
	## A cap that is global instead of per-quarry passes every check above and
	## still starves a room: two hunters committed to a teammate 100 m away would
	## leave nothing for the hunter standing on you. Group "player" is by
	## definition the LOCAL player, so this is the one rule that cannot be
	## verified by looking at a single quarry at all.
	var director: Node = _make_director()
	var here := Vector3.ZERO
	var there := Vector3(100.0, 0.0, 0.0)
	var cap: int = DIRECTOR.MAX_PURSUERS

	# Fill quarry A to its cap, spread evenly so rule 3 stays open throughout.
	var filled: Array[Node3D] = []
	for i: int in range(cap):
		var angle: float = TAU * float(i) / float(cap)
		var unit: Node3D = _make_stub(here,
				here + Vector3(cos(angle), 0.0, sin(angle)) * 6.0)
		filled.append(unit)
		if not director.request_hunt_close(unit):
			_fail("two quarries: the harness could not fill quarry A to its cap "
					+ "(hunter %d of %d was refused), so the isolation test below "
					% [i + 1, cap] + "would have proved nothing")
			_teardown([director] + filled)
			Sentinel.done("two_quarries")
			return
		unit._hunt_lock["closing"] = true

	# Confirm A really is full, or the next assertion measures nothing. Placed
	# just off the first bearing so the ring keeps a gap far wider than the
	# guarantee and only the cap can refuse it.
	var extra: Node3D = _make_stub(here, here + Vector3(cos(0.2), 0.0, sin(0.2)) * 6.0)
	if director.request_hunt_close(extra):
		_fail("two quarries: quarry A granted a hunter past its cap of %d, so it "
				% cap + "was never full and the per-quarry isolation below is "
				+ "untested")

	# The teammate 100 m away. This MUST be granted — a global cap denies it.
	var far: Node3D = _make_stub(there, there + Vector3(6.0, 0.0, 0.0))
	if not director.request_hunt_close(far):
		_fail("two quarries: with quarry A at its cap of %d, a hunter on a SECOND "
				% cap + "quarry 100 m away was refused. The cap is global rather "
				+ "than per quarry, so in a room two hunters anywhere starve every "
				+ "other member's encounter — and group \"player\" being the LOCAL "
				+ "player means nothing here would ever notice.")
	far._hunt_lock["closing"] = true

	# ---- a quarry that MOVES must not leave one unit holding two slots ------
	# In a room a hunter re-targets when a nearer member appears, which lands it
	# in a different bucket. If the old slot is not handed back at that moment it
	# stays occupied until the next tick reaps it, and for that half second the
	# abandoned quarry is capped by a robot that is not chasing it any more.
	var mover: Node3D = filled[0]
	mover.chase_target = there
	mover.global_position = there + Vector3(0.0, 0.0, 6.0)
	if not director.request_hunt_close(mover):
		_fail("moved quarry: a hunter that re-targeted to a second quarry with a "
				+ "free cap slot there was refused, so the slot-handback assertion "
				+ "below would have proved nothing")
	var replacement: Node3D = _make_stub(here,
			here + Vector3(cos(0.2), 0.0, sin(0.2)) * 6.0)
	if not director.request_hunt_close(replacement):
		_fail("moved quarry: after a hunter re-targeted away from quarry A, that "
				+ "quarry still refused a replacement — the unit is holding a cap "
				+ "slot on a quarry it is no longer chasing AND one on the quarry "
				+ "it moved to, so it counts twice against a cap of %d."
				% cap)

	# The lull is bucketed the same way: a grab landing over there must not calm
	# the hunters standing on this player. The cap slots on A are handed back
	# through the public verb first, so what is measured is the LULL and not the
	# cap left over from above.
	director.report_grab(far)
	for unit: Node3D in filled:
		director.report_disengage(unit)
	var here_again: Node3D = _make_stub(here,
			here + Vector3(cos(PI + 0.2), 0.0, sin(PI + 0.2)) * 6.0)
	if not director.request_hunt_close(here_again):
		_fail("two quarries: a grab that landed on a quarry 100 m away put THIS "
				+ "quarry into a lull, with every cap slot here already handed "
				+ "back. The cooldown is global rather than per quarry, so one "
				+ "teammate being caught pauses the hunters chasing everybody.")

	_teardown([director, extra, far, replacement, here_again] + filled)
	Sentinel.done("two_quarries")


# ============================================================================
# CHECK 6 — the absent-director degrade, through the SHIPPED seam
# ============================================================================

func _check_absent_director() -> void:
	## `hunter_robot.tscn` standalone, every self-check and every headless harness
	## run with nothing in group "hunt_director", and the arm's
	## `_hunt_close_granted()` must answer true there. Measured on a LIVE hunter
	## through the shipped function — a restatement here would not notice the arm
	## changing which group it looks in, or losing the lookup entirely.
	##
	## Both directions, because either half alone is worthless: without a director
	## it must GRANT (or the standalone scene ships a robot frozen on its ring),
	## and with one it must take the DIRECTOR'S answer (or the seam is wired to
	## nothing and every rule in hunt_director.gd is dead code).
	if get_first_node_in_group("hunt_director") != null:
		_fail("absent director: something was still in group 'hunt_director' when "
				+ "this check started — an earlier check leaked its node, and the "
				+ "degrade path cannot be measured with one in the world")
		Sentinel.done("absent_director")
		return

	var hunter: Node = load(HUNTER_SCENE).instantiate()
	# Assigned BEFORE add_child: the SPECIES call-order contract, same as
	# setup_as_boss(). _ready() is where the row is resolved into `spec`.
	hunter.species = HUNT_SPECIES
	root.add_child(hunter)
	await process_frame

	if hunter.spec.get("behavior", "") != "hunt":
		_fail("absent director: the live probe resolved species '%s' to behaviour "
				% HUNT_SPECIES + "'%s', not 'hunt' — it is not on the arm whose "
				% str(hunter.spec.get("behavior", "")) + "seam this check exists "
				+ "to measure")
		hunter.queue_free()
		await process_frame
		Sentinel.done("absent_director")
		return

	hunter.chase_target = Vector3.ZERO
	if not hunter._hunt_close_granted():
		_fail("absent director: with NOTHING in group 'hunt_director', a live "
				+ "hunter was refused permission to close. The standalone "
				+ "hunter_robot.tscn, every self-check and every headless harness "
				+ "would ship a robot that paces its ring and never commits.")

	# Now put one in the world and make it say no. If the answer does not change,
	# the arm is not consulting the director at all.
	var director: Node = _make_director()
	var stub: Node3D = _make_stub(Vector3.ZERO, Vector3(5.0, 0.0, 0.0))
	director.report_grab(stub)
	if hunter._hunt_close_granted():
		_fail("absent director: a director holding a full %.1f s lull on this "
				% DIRECTOR.ENGAGE_LULL + "quarry was consulted and IGNORED — the "
				+ "arm's group lookup or its has_method guard is not reaching "
				+ "request_hunt_close, so every rule in hunt_director.gd is dead "
				+ "code in the shipped game.")

	_teardown([director, stub])
	hunter.queue_free()
	await process_frame
	Sentinel.done("absent_director")


# ============================================================================
# CHECK 8 — the hunter's own dread channel
# ============================================================================

func _check_dread_channels() -> void:
	"""
	A CLOSING HUNTER LIGHTS THE MACHINE CHANNEL, A CROCODILE LIGHTS THE RED ONE,
	AND NEITHER SUPPRESSES THE OTHER.

	The owner's ruling for this class (bead godot-test1-9rm.6) is that a hunter is
	a different KIND of threat and must read as one, driven off the LOD manager's
	existing ~9 Hz scan rather than a second scan of its own. Three ways that
	breaks, all of them silent in a headless build and none of them an error:

	  • THE SPLIT NEVER HAPPENS and a hunter reddens the predator vignette like
	    any crocodile. Nothing errors; the feature is simply not there, and it
	    looks exactly like a hunter that is telegraphed correctly.
	  • THE SPLIT INVERTS — the behaviour test is negated, or reads the species
	    name that the row does not carry — and now every animal in the game
	    telegraphs as a machine. Also silent, also plausible on a screenshot.
	  • ONE CHANNEL OVERWRITES THE OTHER when a predator and a hunter close
	    together. This is the case the ruling explicitly asks to be decided rather
	    than left to whichever writes last, so it is measured with BOTH in range
	    at once and both levels asserted non-zero.

	Driven through the SHIPPED path end to end: a real CrocodileLODManager, a real
	DangerVignette in its real group, real bodies of both kinds. A restatement of
	the normalisation here would not notice the manager changing which method it
	calls, or the vignette changing its signature back.

	The NORMALISATION is the fourth claim and it is the one the bead asks to be
	verified rather than rebuilt: a hunter smells at 25 m and an animal at 15, so
	the published level must come from each chaser's OWN detection_radius. A
	hunter and a crocodile placed at the SAME distance must therefore publish
	DIFFERENT levels, and the hunter's must be HIGHER: the published number is
	`1 - dist/radius`, so a chaser with a longer reach is already further into its
	approach at the same metres — which is exactly why the boss's 25 m needed the
	normalisation in the first place. A hardcoded radius on either side collapses
	that to equality.
	"""
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector3.ZERO

	var vignette := Control.new()
	vignette.set_script(load(VIGNETTE_SCRIPT))
	root.add_child(vignette)

	var lod := Node.new()
	lod.set_script(load(LOD_SCRIPT))
	root.add_child(lod)
	await process_frame  # _ready() + the deferred player lookup

	# THE SHADER IS BUILT FROM A STRING AT RUNTIME, so a typo in it is not a parse
	# error anywhere — it is one `SHADER ERROR:` line in a console nobody reads,
	# after which the whole telegraph draws NOTHING and every level assertion
	# below still passes. Godot reports the failure by handing back an empty
	# uniform list, which is checkable, so it is checked. Both names, because a
	# shader that compiles but lost the second uniform is the exact half-landed
	# state this bead introduces.
	var uniforms: Array = []
	for u: Dictionary in (vignette._rect.material as ShaderMaterial).shader.get_shader_uniform_list():
		uniforms.append(String(u["name"]))
	for required: String in ["vignette_alpha", "hunter_alpha"]:
		if required not in uniforms:
			_fail("dread channels: the vignette shader exposes no '%s' uniform (it has %s) — it did not compile, and the telegraph draws nothing at all. Scroll up for the SHADER ERROR line."
					% [required, str(uniforms)])

	# Both bodies at the SAME distance, both chasing, both inside SIM_RADIUS.
	var hunter: Node = load(HUNTER_SCENE).instantiate()
	hunter.species = HUNT_SPECIES
	root.add_child(hunter)
	var croc: Node = load(CROC_SCENE).instantiate()
	root.add_child(croc)
	await process_frame
	var probe_distance: float = 10.0
	hunter.global_position = Vector3(probe_distance, 0.0, 0.0)
	croc.global_position = Vector3(-probe_distance, 0.0, 0.0)
	hunter.is_chasing = true
	croc.is_chasing = true

	if hunter.spec.get("behavior", "") != "hunt":
		_fail("dread channels: the probe hunter is not on the hunt arm — every claim below is vacuous")
	if croc.spec.get("behavior", "") == "hunt":
		_fail("dread channels: the control crocodile IS on the hunt arm — it cannot be the control")
	if float(hunter.detection_radius) <= float(croc.detection_radius):
		_fail("dread channels: the hunter's detection radius (%.1f) is not longer than the crocodile's (%.1f) — the per-chaser normalisation claim cannot fail"
				% [hunter.detection_radius, croc.detection_radius])

	lod._scan_crocodiles()

	var red: float = float(vignette._danger_level)
	var machine: float = float(vignette._hunter_level)
	if machine <= 0.0:
		_fail("dread channels: a hunter chasing at %.0f m published NOTHING on the machine channel (%.3f) — the hunter has no telegraph of its own"
				% [probe_distance, machine])
	if red <= 0.0:
		_fail("dread channels: a crocodile chasing at %.0f m published NOTHING on the predator channel (%.3f) — the split swallowed the animal"
				% [probe_distance, red])
	if absf(red - machine) < EPS:
		_fail("dread channels: a hunter and a crocodile at the same %.0f m published the SAME level (%.3f) — one of the two sides is normalising by a hardcoded radius instead of the chaser's own"
				% [probe_distance, red])
	if machine <= red:
		_fail("dread channels: the hunter (reach %.1f m) published %.3f, not MORE than the crocodile's %.3f (reach %.1f m) at equal distance — the longer reach is not reaching the level, so some radius is hardcoded"
				% [hunter.detection_radius, machine, red, croc.detection_radius])

	# The control that makes the split a split: with the hunter alone, the
	# predator channel must go dark. Without this, a manager that published the
	# same number into both accumulators passes everything above.
	croc.is_chasing = false
	lod._scan_crocodiles()
	if float(vignette._danger_level) > 0.0:
		_fail("dread channels: with only a hunter chasing, the PREDATOR channel still read %.3f — a hunter is reddening the animal vignette as well as its own"
				% vignette._danger_level)
	if float(vignette._hunter_level) <= 0.0:
		_fail("dread channels: a lone hunter lit nothing at all")

	# And the mirror: a lone crocodile must leave the machine channel dark.
	hunter.is_chasing = false
	croc.is_chasing = true
	lod._scan_crocodiles()
	if float(vignette._hunter_level) > 0.0:
		_fail("dread channels: with only a crocodile chasing, the MACHINE channel read %.3f — every animal in the game telegraphs as a robot"
				% vignette._hunter_level)

	hunter.queue_free()
	croc.queue_free()
	lod.queue_free()
	vignette.queue_free()
	player.queue_free()
	await process_frame
	Sentinel.done("dread_channels")


# ============================================================================
# HARNESS
# ============================================================================

func _rules_isolated() -> bool:
	## Checks 1 and 2 isolate their own rule by holding the other two OPEN — no
	## lull, no cap pressure, and an EMPTY bearing set. That last part is only an
	## isolation if rule 3 actually grants a lone hunter, so it is confirmed here
	## rather than assumed.
	##
	## THIS EXISTS BECAUSE OF A REAL MISDIAGNOSIS. With the wrap term dropped from
	## `escape_sector_open`, rule 3 refuses everything — including the empty set —
	## and checks 1 and 2 then reported "the cap is starving the class" and "every
	## engagement in the game is denied", naming two rules that were both fine. A
	## check that fails is worth little if it fails pointing at the wrong file.
	if DIRECTOR.escape_sector_open(PackedFloat32Array(), 0.0):
		return true
	_fail("isolation: rule 3 refuses even a LONE hunter with no other bearings, "
			+ "so the cap and lull probes cannot hold it open and would report "
			+ "their own rules as broken. Fix the escape-sector failure first — "
			+ "checks 1 and 2 were skipped, not passed.")
	return false


func _make_director() -> Node:
	## A live director node in the tree (its _ready joins the group) with engine
	## ticking switched OFF, so the only time that passes is the time `_age` hands
	## it. A director driven by real frames would make every timing assertion in
	## this file a race.
	var node := Node.new()
	node.set_script(DIRECTOR)
	root.add_child(node)
	node.set_process(false)
	return node


func _age(director: Node, seconds: float) -> float:
	## Push the director's throttled tick forward, and return how much time it
	## actually aged. One `_process` call with a delta past the interval fires
	## exactly one tick, and that tick charges the interval PLUS the overshoot —
	## which is the shipped behaviour, and is why a 15 s lull stays 15 s long at
	## any frame rate. The countdown starts at a full interval, so what a tick
	## charges is exactly the time handed to it.
	director._process(seconds)
	return seconds


func _make_stub(quarry: Vector3, at: Vector3) -> Node3D:
	## A hunter stand-in in group "crocodile" — which is where the director scans
	## for the bearings rule 3 reads — chasing `quarry` from `at`.
	var script := GDScript.new()
	script.source_code = HUNTER_STUB_SOURCE
	if script.reload() != OK:
		_fail("harness: the hunter stub script did not compile, so every live "
				+ "check below is measuring an empty object")
	var node := Node3D.new()
	node.set_script(script)
	node.add_to_group("crocodile")
	root.add_child(node)
	node.global_position = at
	node.chase_target = quarry
	return node


func _teardown(nodes: Array) -> void:
	## `free()` rather than `queue_free()`: the next check asserts that nothing is
	## left in group "hunt_director", and a deferred free would still be pending
	## when it looks.
	for n: Variant in nodes:
		if n is Node and is_instance_valid(n):
			(n as Node).free()
