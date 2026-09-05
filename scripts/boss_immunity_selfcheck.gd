extends SceneTree
## ============================================================================
## BOSS SELF-CHECK — CRUSH IMMUNITY IS AN ORDERING, AND THE ROW-KEY GUARDS
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/boss_immunity_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## ONE OF FIVE — see `boss_selfcheck.gd`'s header for the family and for why bead
## `godot-test1-ftn.24` split it; `scripts/boss_probe.gd` is the shared harness.
##
##   1. CRUSH IMMUNITY IS AN ORDERING. `_on_player_collision` early-returns for
##      is_boss ABOVE the giant-Teibi crush block; swap those two blocks and
##      giant Teibi one-shots the game's biggest threat with no error anywhere.
##      Check 7 pins the order — with a NON-boss negative control, because "the
##      boss survived" is also true of a stub that never crushed anything.
##
##   2. ROW IMMUNITY IS THE SAME TWO GUARDS, ONE STEP OUT. `stink_immune` and
##      `crush_immune` let a row opt out of Phoboman's wave and giant Teibi's
##      squash, and they fail exactly as silently: a dropped guard is an armoured
##      machine that pops underfoot, a stray key is an ordinary crocodile nobody
##      can kill. Check 8 drives EVERY row in SPECIES through both real code
##      paths and asserts the outcome the row asked for — so the animals are the
##      negative control, for free, and a future immune species is covered the
##      day its row lands. It lives in THIS file because these two guards sit
##      beside the is_boss guards check 7 owns; enemy_spawn_selfcheck owns
##      spawning, not collision.
##
## THIS FILE DOES NOT USE `BossProbe.drive()`, and that is a saving rather than an
## omission: check 7 builds its OWN pair of bodies (a boss and an ordinary one of
## the same species) and check 8 builds one body per SPECIES row, so the driver's
## settled boss would be a third body standing on the same spot for no reason. It
## walks `BossProbe.subjects()` directly instead — the same table, the same
## coverage, the same "a row added to BIOME_BOSS is measured on the commit that
## adds it".
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

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


class StubMpManager:
	extends Node
	var avatars: Array = []

	func remote_avatars() -> Array:
		return avatars

	func nearest_member_position(_from: Vector3) -> Variant:
		return null


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


func _run() -> void:
	BossProbe.build_floor(root)
	var player: BossProbe.StubPlayer = BossProbe.build_player(root)

	# EVERY boss kind, not just the crocodile — see BossProbe.subjects().
	for entry: Dictionary in BossProbe.subjects():
		BossProbe.subject = String(entry["species"])
		var packed: PackedScene = load(String(entry["scene"]))
		if packed == null:
			_fail("could not load %s" % entry["scene"])
			continue
		await _check_crush_immunity(packed, BossProbe.subject, player)
	BossProbe.subject = ""

	await _check_row_immunities(player)

	player.queue_free()
	await _frames(2)
	_report()


func _check_crush_immunity(packed: PackedScene, species_name: String,
		giant: BossProbe.StubPlayer) -> void:
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
	boss.setup_as_boss(BossProbe.BOSS_SCALE)
	boss.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(boss)
	var victim: CharacterBody3D = packed.instantiate()
	victim.species = species_name
	victim.position = Vector3(10.0, 1.0, 0.0)
	root.add_child(victim)
	await _frames(BossProbe.SETTLE_FRAMES)

	# The harness guards `BossProbe.drive()` asks on every other file's behalf.
	# They are asked here too, because before the split this check ran at the
	# BOTTOM of `_run_subject` and so was simply never reached for a kind that
	# failed one of them. Without this a scene whose script did not attach reports
	# "a boss was squashed by giant Teibi", which sends the reader to the crush
	# ordering instead of to the missing import.
	var bad: String = BossProbe.ready_failure(boss, species_name)
	if not bad.is_empty():
		_fail(bad)
		giant.giant = false
		boss.queue_free()
		victim.queue_free()
		await _frames(2)
		Sentinel.done("crush_immunity")
		return

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



func _check_row_immunities(giant: BossProbe.StubPlayer) -> void:
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
	var packed: PackedScene = load(BossProbe.CROC_SCENE)
	if packed == null:
		_fail("immunity: could not load %s" % BossProbe.CROC_SCENE)
		Sentinel.done("row_immunities")
		return
	# How many rows actually exercised each guard, for the vacuity check below.
	var opted_in: Dictionary = {
		"fears_giant_radius": 0,
	}
	for key: String in IMMUNITY_KEYS:
		opted_in[key] = 0

	for species_name: String in BossProbe.CROC_SCRIPT.SPECIES.keys():
		BossProbe.subject = species_name
		var row: Dictionary = BossProbe.CROC_SCRIPT.SPECIES[species_name]
		var stink_immune: bool = bool(row.get("stink_immune", false))
		var crush_immune: bool = bool(row.get("crush_immune", false))
		var fears_giant_radius: float = float(row.get("fears_giant_radius", 0.0))
		if stink_immune:
			opted_in["stink_immune"] += 1
		if crush_immune:
			opted_in["crush_immune"] += 1
		if fears_giant_radius > 0.0:
			opted_in["fears_giant_radius"] += 1

		# Same call-order contract as everywhere else: species BEFORE add_child,
		# because _ready() resolves `spec` from it exactly once.
		var body: CharacterBody3D = packed.instantiate()
		body.species = species_name
		body.position = Vector3(0.0, 1.0, 0.0)
		root.add_child(body)
		await _frames(BossProbe.SETTLE_FRAMES)
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

		if species_name == "hunter_robot":
			if stink_immune:
				_fail("stink: hunter_robot carries stink_immune — reversed by owner ruling 2026-09-04 (bead bvh)")
			var src := body.global_position + Vector3(3.0, 0.0, 0.0)
			var d_before := body.global_position.distance_to(src)
			await _frames(10)
			var d_after := body.global_position.distance_to(src)
			if d_after <= d_before:
				_fail("stink: hunter_robot is_fleeing but did not move away from stink source (before=%.2f, after=%.2f)" % [d_before, d_after])

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

		# ---- C. GIANT TEIBI'S FEAR (bead godot-test1-upu) -----------------------
		body.is_fleeing = false
		body.flee_time_remaining = 0.0
		body.is_chasing = false
		body.player_node = giant
		giant.giant = true
		giant.global_position = body.global_position + Vector3(5.0, 0.0, 0.0)

		# Drive shipped _update_chase_state() with giant 5 m away
		body._update_chase_state()
		if fears_giant_radius > 0.0:
			if not body.is_fleeing:
				_fail("giant fear: row carries fears_giant_radius=%.1f and giant is 5m away, but body did not flee" % fears_giant_radius)
		else:
			if body.is_fleeing:
				_fail("giant fear: row carries no fears_giant_radius, but giant Teibi caused it to flee")

		if species_name == "tower_guard":
			if fears_giant_radius > 0.0 or row.has("fears_giant_radius"):
				_fail("giant fear: tower_guard must not carry fears_giant_radius — the keep is a stealth challenge (bead upu)")

		if species_name == "hunter_robot":
			if fears_giant_radius <= 0.0:
				_fail("giant fear: hunter_robot must carry fears_giant_radius > 0 (bead upu)")

			# 1. Normal Teibi beside hunter: must not flee, must keep chasing
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			giant.giant = false
			giant.global_position = body.global_position + Vector3(5.0, 0.0, 0.0)
			body._update_chase_state()
			if body.is_fleeing:
				_fail("giant fear: hunter fled a NORMAL-size Teibi 5m away")
			if not body.is_chasing:
				_fail("giant fear: hunter did not chase normal Teibi 5m away")

			# 2. Giant Teibi beyond radius: must not flee
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			giant.giant = true
			giant.global_position = body.global_position + Vector3(fears_giant_radius + 5.0, 0.0, 0.0)
			body._update_chase_state()
			if body.is_fleeing:
				_fail("giant fear: giant Teibi beyond radius (%.1f m > %.1f m) caused hunter to flee" % [fears_giant_radius + 5.0, fears_giant_radius])

			# 3. Fear holds while giant stands and releases ~GIANT_FEAR_HOLD after revert
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			giant.giant = true
			giant.global_position = body.global_position + Vector3(5.0, 0.0, 0.0)
			body._update_chase_state()
			if not body.is_fleeing:
				_fail("giant fear: hunter failed to flee giant at 5m")
			# Hold while giant stands
			await _frames(20)
			if not body.is_fleeing:
				_fail("giant fear: fear dropped while giant still in range")
			# Giant reverts to normal
			giant.giant = false
			# Fear must still hold midway through GIANT_FEAR_HOLD (~0.5s = 30 frames)
			await _frames(30)
			if not body.is_fleeing:
				_fail("giant fear: fear released prematurely before GIANT_FEAR_HOLD elapsed")
			# Fear must release once GIANT_FEAR_HOLD has passed (~0.75s more = 45 frames)
			await _frames(45)
			if body.is_fleeing:
				_fail("giant fear: fear did not release after GIANT_FEAR_HOLD elapsed")

			# 4. Flee refresh must never shorten an active flee (Codex P2)
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			body.flee_from(body.global_position + Vector3(3.0, 0.0, 0.0), 10.0)
			giant.giant = true
			giant.global_position = body.global_position + Vector3(5.0, 0.0, 0.0)
			body._update_chase_state()
			if not body.is_fleeing:
				_fail("giant fear: hunter failed to maintain flee after giant refresh")
			if body.flee_time_remaining < 9.0:
				_fail("giant fear (P2): fear refresh truncated active 10s flee to %.2fs (< 9.0s)" % body.flee_time_remaining)

			# 5. Giant fear must not depend on scent/quarry choice (Codex P1/P2)
			# Closer normal player (2m) would steal quarry under old code, but
			# giant teammate (5m) must still trigger fear.
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			giant.giant = false
			giant.global_position = body.global_position + Vector3(2.0, 0.0, 0.0)
			var mock_mp := StubMpManager.new()
			root.add_child(mock_mp)
			var remote_giant := RemoteAvatar.new()
			mock_mp.add_child(remote_giant)
			remote_giant.ability_bits = 4  # ABILITY_BIT_GIANT
			remote_giant.target_pos = body.global_position + Vector3(5.0, 0.0, 0.0)
			# Put interpolated global_position far away to verify authoritative target_pos is read (Codex P2)
			remote_giant.global_position = body.global_position + Vector3(50.0, 0.0, 0.0)
			mock_mp.avatars = [remote_giant]
			body.mp_node = mock_mp
			body._update_chase_state()
			if not body.is_fleeing:
				_fail("giant fear (P1): hunter did not flee giant teammate 5m away when normal player 2m away")
			body.mp_node = null
			mock_mp.queue_free()

			# 6. Real player.tscn contract (Opus SHOULD-FIX 3)
			# Proves real player_controller.crushes_crocodiles() drives giant fear, not only the stub.
			body.is_fleeing = false
			body.flee_time_remaining = 0.0
			body.is_chasing = false
			var real_player: Node3D = load("res://scenes/player.tscn").instantiate() as Node3D
			root.add_child(real_player)
			real_player.is_giant = true
			real_player.global_position = body.global_position + Vector3(5.0, 0.0, 0.0)
			body.player_node = real_player
			body._update_chase_state()
			if not body.is_fleeing:
				_fail("giant fear (real player): hunter did not flee real player.tscn in giant form at 5m")
			body.player_node = giant
			real_player.queue_free()
			await _frames(2)

		body.queue_free()
		await _frames(2)
	BossProbe.subject = ""

	# ---- D. THE TABLE ACTUALLY EXERCISES ALL GUARDS ------------------------
	for key: String in IMMUNITY_KEYS:
		if int(opted_in[key]) <= 0:
			_fail("immunity: no row in SPECIES carries '%s', so the loop above "
					% key + "never took that guard and proves nothing about it — "
					+ "delete the guard or restore the row key")
	if int(opted_in.get("fears_giant_radius", 0)) <= 0:
		_fail("giant fear: no row in SPECIES carries fears_giant_radius > 0")

	# ---- E. THE ANCHOR ------------------------------------------------------
	# Part A/B/C read the row, so a row that turned immune by mistake would be
	# measured as correct. The baseline predator is pinned by name instead.
	var baseline: Dictionary = BossProbe.CROC_SCRIPT.SPECIES.get(BASELINE_SPECIES, {})
	if baseline.is_empty():
		_fail("immunity: SPECIES has no '%s' row to anchor against" % BASELINE_SPECIES)
	for key: String in IMMUNITY_KEYS:
		if bool(baseline.get(key, false)):
			_fail("immunity: the '%s' row carries '%s' — the game's ordinary "
					% [BASELINE_SPECIES, key] + "enemy is flesh and has a nose, "
					+ "and making it immune would quietly break the whole "
					+ "Phoboman/giant-Teibi half of the toolbox")
	if float(baseline.get("fears_giant_radius", 0.0)) > 0.0:
		_fail("immunity: the '%s' row carries fears_giant_radius" % BASELINE_SPECIES)
	Sentinel.done("row_immunities")
