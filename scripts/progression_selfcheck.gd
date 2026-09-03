extends SceneTree
## ============================================================================
## META-PROGRESSION SELF-CHECK
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/progression_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: every way this feature breaks is SILENT. A level curve that is
## off by one coin at a threshold still awards levels, just at the wrong moments.
## A hook wired to the post-streak value still counts coins, just five times too
## many — and nothing anywhere errors, because both numbers are perfectly valid
## ints. A `_on_progression_loaded` that assigns instead of `maxi`-ing still loads,
## and only takes a level away when a second device happens to answer with less.
## None of that shows up on a headless machine unless it is measured.
##
## SO EVERY CHECK HERE IS AN EFFECT MEASUREMENT WITH A NEGATIVE CONTROL — the
## house rule the minimap and fauna self-checks were written to, for the same
## reason: an assertion that is satisfied by a broken implementation is worse than
## no assertion. The streak check in particular asserts BOTH that lifetime rose by
## the base value AND that the score rose by more, because with a multiplier of 1
## the first half is true of the bug it exists to catch.
##
## PERSISTENCE IS DELIBERATELY NOT HERE. `progression.persistence_enabled` is off
## throughout, so no progression store is built and nothing here reads, rewrites
## or POSTs a profile; the store round trip (local layer AND server) is driven end
## to end by `scripts/best_run_e2e.gd` against the local lobby `scripts/mp_e2e.sh`
## already starts.
##
## THE LOCAL STORE THIS RUN USES IS A THROWAWAY FILE, not the machine's profile.
## Two things here reach `BestRunStore`'s local layer: the relaunch check writes
## and re-reads it deliberately, and the player scene mints a profile id into it
## as a side effect (`player_controller._ready()` unconditionally builds a store
## and calls `fetch()`, and the streak check has to boot the real player, since
## measuring the real `collect_coin()` is its whole point).
##
## THIS USED TO BACK THE REAL FILE UP AND PUT IT BACK, AND THAT WAS NOT ENOUGH —
## it is the bug this file was rewritten to fix. `_write_local()` is a monotone
## read-modify-write merge by design (see `best_run_store.gd`), so the relaunch
## check storing 1234 lifetime coins into a developer's real profile read back
## whatever larger number that profile already held, and the check FAILED for a
## reason that had nothing to do with the code it covers. It passed in CI only
## because a fresh container has no profile: a gate green for the wrong reason.
## Restoring afterwards cannot help — the merge happens while the check runs —
## and it left a real record one crashed assertion away from being clobbered.
##
## So `BestRunStore.config_path` is pointed at `LOCAL_STORE_PATH` for the whole
## run, before anything can build a store. Every assertion here is then made
## against state this file arranged; the developer's `user://best_run.cfg` is
## never opened, read, written or deleted, whatever it happens to hold and
## however this run ends.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## `coin.gd` has no `class_name`, so it is preloaded by path — the same line
## `scripts/mp_selfcheck.gd` carries, for the same reason.
const Coin: GDScript = preload("res://scripts/coin.gd")

## The throwaway profile this run reads and writes instead of the real one (see
## the header). Deleted on the way in as well as out, so a run killed halfway
## leaves nothing for the next one to inherit and read as its own arranged state.
const LOCAL_STORE_PATH: String = "user://progression_selfcheck_best_run.cfg"

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _isolate_local_store() -> void:
	BestRunStore.config_path = LOCAL_STORE_PATH
	DirAccess.remove_absolute(LOCAL_STORE_PATH)


func _initialize() -> void:
	# The measuring half runs as its own coroutine: `_initialize()` cannot await,
	# and a verdict printed from here would be a frame-0 vacuous pass — the exact
	# failure the sibling self-checks in this repo document.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	DirAccess.remove_absolute(LOCAL_STORE_PATH)
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _make_progression() -> Progression:
	"""A Progression node with persistence off, in the group the hooks look in."""
	var node := Progression.new()
	node.persistence_enabled = false
	root.add_child(node)
	return node


func _check_curve() -> void:
	"""
	The curve is exact at its own thresholds, and NOT one coin early.

	The negative control is the `- 1` line: `level_for` returning `n` for
	`threshold(n)` is also true of a function that rounds up, of a float `sqrt`
	inverse that lands a ulp high, and of an off-by-one loop — all of which pay a
	level out before it was earned. Only the pair pins it.
	"""
	# The documented shape, pinned so a change to LEVEL_COIN_STEP is a deliberate
	# act rather than a silent re-tuning of everybody's stored profile.
	var want: Array[int] = [0, 50, 150, 300, 500, 750]
	for n: int in want.size():
		var got := Progression.level_coin_threshold(n)
		if got != want[n]:
			_fail("level %d costs %d lifetime coins, wanted %d" % [n, got, want[n]])

	for n: int in range(1, 12):
		var at := Progression.level_coin_threshold(n)
		if Progression.level_for(at) != n:
			_fail("level_for(%d) = %d at the level-%d threshold, wanted %d"
					% [at, Progression.level_for(at), n, n])
		# NEGATIVE CONTROL: one coin short of the threshold is still the level below.
		if Progression.level_for(at - 1) != n - 1:
			_fail("level_for(%d) = %d one coin BEFORE the level-%d threshold, wanted %d"
					% [at - 1, Progression.level_for(at - 1), n, n - 1])
		# Thresholds must strictly increase, or `level_for`'s loop never terminates
		# in the sense it is written for.
		if at <= Progression.level_coin_threshold(n - 1):
			_fail("level %d costs no more than level %d — the curve is not increasing"
					% [n, n - 1])

	if Progression.level_for(0) != 0 or Progression.level_for(-5) != 0:
		_fail("a fresh (or corrupt) profile is not level 0")
	Sentinel.done("curve")


func _check_points_and_levelling() -> void:
	"""Coins in, levels and unspent points out — and the level-up signal firing."""
	var progression := _make_progression()
	var seen_levels: Array[int] = []
	progression.levelled_up.connect(func(new_level: int, _gained: int) -> void:
		seen_levels.append(new_level))

	if progression.level != 0 or progression.unspent_points() != 0:
		_fail("a fresh Progression is not level 0 with 0 points")

	# One coin short of level 1: no level, no point, no signal.
	progression.add_coins(Progression.level_coin_threshold(1) - 1)
	if progression.level != 0:
		_fail("levelled up %d coins before the threshold" % 1)
	if not seen_levels.is_empty():
		_fail("levelled_up fired below the threshold: %s" % [seen_levels])

	# The coin that earns it.
	progression.add_coins(1)
	if progression.level != 1 or progression.unspent_points() != 1:
		_fail("level %d / %d points at the level-1 threshold, wanted 1 / 1"
				% [progression.level, progression.unspent_points()])
	if seen_levels != [1]:
		_fail("levelled_up fired %s, wanted exactly [1]" % [seen_levels])

	# A single big credit (a treasure chest's burst, or a server reply) may cross
	# more than one threshold at once, and must not be clamped to one level.
	progression.add_coins(Progression.level_coin_threshold(4) - progression.lifetime_coins)
	if progression.level != 4 or progression.unspent_points() != 4:
		_fail("a multi-level credit landed at level %d / %d points, wanted 4 / 4"
				% [progression.level, progression.unspent_points()])

	# NEGATIVE CONTROL for "lifetime is never deducted": nothing may lower it, and
	# a level once earned is kept. This is the whole reason every layer under this
	# one can merge with a plain max.
	var before := progression.lifetime_coins
	progression.add_coins(-1000)
	progression.add_coins(0)
	if progression.lifetime_coins != before or progression.level != 4:
		_fail("a non-positive credit changed the profile: %d coins / level %d"
				% [progression.lifetime_coins, progression.level])

	# Spent points come off the unspent count, never off the level or the coins.
	progression.spent_points = 3
	if progression.unspent_points() != 1 or progression.level != 4:
		_fail("spending left %d unspent at level %d, wanted 1 at level 4"
				% [progression.unspent_points(), progression.level])

	progression.free()
	Sentinel.done("points_and_levelling")


func _check_store_load_is_monotone() -> void:
	"""
	A store answer may only ever RAISE the profile.

	`BestRunStore.progression_loaded` fires twice — once from the local layer, once
	if the lobby knows better — and the lobby's answer can legitimately be BEHIND
	(a record set before this shipped, or a run banked while it was unreachable).
	An assignment instead of a `maxi` here reads as working for every player whose
	server copy is ahead, and silently demotes everyone else.
	"""
	var progression := _make_progression()
	progression._on_progression_loaded(600, 2)
	if progression.lifetime_coins != 600 or progression.level != 4 or progression.spent_points != 2:
		_fail("loading 600 coins gave %d / level %d / %d spent, wanted 600 / 4 / 2"
				% [progression.lifetime_coins, progression.level, progression.spent_points])

	# NEGATIVE CONTROL: a lower answer lands afterwards and must change nothing.
	progression._on_progression_loaded(100, 0)
	if progression.lifetime_coins != 600 or progression.level != 4 or progression.spent_points != 2:
		_fail("a BEHIND store answer lowered the profile to %d / level %d / %d spent"
				% [progression.lifetime_coins, progression.level, progression.spent_points])
	progression.free()
	Sentinel.done("store_load_is_monotone")


func _check_streak_does_not_inflate_lifetime() -> void:
	"""
	BOTH HOOKS, measured through the real `player_controller` — `collect_coin()`
	(solo, and the loser of a multiplayer claim) and `bank_awarded()` (the winner
	of one, bead godot-test1-42n).

	Lifetime counts PICKUPS at their base worth; the streak and the room's
	multiplier multiply the SCORE. Wiring either hook to the multiplied value is
	the easy mistake — the line right above `collect_coin`'s does exactly that for
	`own_coins` — and it inflates every player's level by up to 5x with no error
	anywhere. Both halves therefore run against a live player and a live
	Progression, with the multiplier proven above 1 first.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("streak_does_not_inflate_lifetime")
		return
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("collect_coin"):
		_fail("player has no collect_coin() — did the script fail to attach? "
				+ "(a fresh clone needs `godot --headless --path . --import` first)")
		player.queue_free()
		Sentinel.done("streak_does_not_inflate_lifetime")
		return

	var progression := _make_progression()

	# Wind the streak up so the multiplier is genuinely above 1.
	player.coin_streak = 20
	player.streak_timer = player.STREAK_WINDOW
	var coins_before: int = player.coins_collected
	var gem_value: int = Coin.GEM_VALUE
	player.collect_coin(gem_value)
	var multiplier: int = player.get_streak_multiplier()

	# NEGATIVE CONTROL, and the load-bearing half: with a multiplier of 1 the
	# lifetime assertion below is ALSO true of the bug, so the check would pass
	# vacuously. Fail loudly rather than measure nothing.
	if multiplier <= 1:
		_fail("the streak multiplier is %d — this check cannot tell the base value "
				% multiplier + "from the multiplied one, so it proves nothing")
	if player.coins_collected - coins_before <= gem_value:
		_fail("the score rose by %d for a gem worth %d — the streak is not applied, "
				% [player.coins_collected - coins_before, gem_value]
				+ "so this check cannot distinguish the two values")

	if progression.lifetime_coins != gem_value:
		_fail("one gem credited %d lifetime coins, wanted %d (the PRE-streak value)"
				% [progression.lifetime_coins, gem_value])

	# And a plain coin is worth exactly 1, still regardless of the multiplier.
	player.collect_coin(1)
	if progression.lifetime_coins != gem_value + 1:
		_fail("a plain coin credited %d lifetime coins, wanted %d"
				% [progression.lifetime_coins - gem_value, 1])

	# THE SECOND HOOK, and the same rule (bead godot-test1-42n). In a multiplayer
	# room a pickup this peer WON is paid by `bank_awarded()`, which receives the
	# amount the room's master already multiplied plus, separately, what the claim
	# was worth before that multiplier. Only the second may reach lifetime coins,
	# or a room inflates every level by up to 5x — and before this bead the hook
	# was simply absent, so a peer in a room levelled almost not at all.
	#
	# The two figures are deliberately far apart and neither is zero, because the
	# two ways to get this wrong are "credit nothing" and "credit the award", and
	# an assertion that merely watched the count rise would pass for the second.
	var base_total: int = 30      # 3 gems, at their base worth.
	var awarded: int = 120        # ...priced by the room at x4.
	var before_award: int = progression.lifetime_coins
	var coins_before_award: int = player.coins_collected
	player.bank_awarded(awarded, base_total)
	var credited: int = progression.lifetime_coins - before_award
	if credited == 0:
		_fail("bank_awarded credited no lifetime coins — a pickup won through the "
				+ "multiplayer claim protocol still pays no progression")
	elif credited == awarded:
		_fail("bank_awarded credited the MULTIPLIED award (%d) as lifetime coins, "
				% awarded + "wanted the pre-multiplier base (%d)" % base_total)
	elif credited != base_total:
		_fail("bank_awarded credited %d lifetime coins, wanted the base total %d"
				% [credited, base_total])
	# ...while the run's own score still takes the full multiplied award, which is
	# the whole reason the two numbers travel separately.
	if player.coins_collected - coins_before_award != awarded:
		_fail("bank_awarded added %d to the run score, wanted the awarded %d"
				% [player.coins_collected - coins_before_award, awarded])

	# NEGATIVE CONTROL: the pre-42n call shape must still credit NOTHING, which is
	# what makes the trailing parameter a zero-behaviour-change API change.
	var before_default: int = progression.lifetime_coins
	player.bank_awarded(awarded)
	if progression.lifetime_coins != before_default:
		_fail("bank_awarded(amount) with no base_total credited %d lifetime coins — "
				% (progression.lifetime_coins - before_default)
				+ "the default must stay inert")

	progression.free()
	player.queue_free()
	Sentinel.done("streak_does_not_inflate_lifetime")


# =============================================================================
# SKILL TREES (bead godot-test1-20z.3)
# =============================================================================

func _grant_points(progression: Progression, points: int) -> void:
	"""Level the profile up until it has at least `points` unspent."""
	progression.add_coins(Progression.level_coin_threshold(points) - progression.lifetime_coins)


func _spend_or_fail(progression: Progression, hero: String, skill_id: String) -> void:
	"""
	Buy a rank the caller BELIEVES is affordable, and say so loudly when it is not.

	A `spend()` that quietly returns false — out of points, prerequisite not yet
	bought, already maxed — leaves the effect measurement downstream comparing a
	build against itself and passing. That happened while this file was being
	written (a points budget one short of what the checks spend), so the guard is
	the bug's own fix.
	"""
	if not progression.spend(hero, skill_id):
		_fail("could not buy %s.%s (%d unspent, rank %d) — the measurement using it proves nothing"
				% [hero, skill_id, progression.unspent_points(), progression.rank_of(hero, skill_id)])


func _settle_on_floor(player: Node) -> void:
	"""
	Drop the player onto the probe floor and wait until the body actually reports
	standing on it. `is_on_floor()` is written by `move_and_slide()`, so it only
	turns true after real physics frames have run — hence the wait rather than an
	assignment. Bounded, so a probe that can never land fails on the caller's
	precondition check instead of hanging the selfcheck.

	The bound is deliberately far above what the drop costs today (~18 ticks at
	60 Hz: 0.5 m at this gravity, plus the frame or two `physics_frame` leads
	`_physics_process` by). A bound sized to the measurement turns a raised
	`physics_ticks_per_second` into a spurious failure in a check that has
	nothing to do with tick rate — it only has to be small enough to fail fast.
	"""
	player.global_position = Vector3(0.0, 0.5, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 240:
		await physics_frame
		if player.is_on_floor():
			return


func _lift_into_the_air(player: Node) -> void:
	"""
	Put the player high above the probe floor and wait out the coyote window, so
	he is airborne by BOTH halves of the grounding gate — off the floor and past
	the ledge grace. Same bounded shape, and the same generous bound, as
	`_settle_on_floor`.
	"""
	player.global_position = Vector3(0.0, 20.0, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 240:
		await physics_frame
		if not player.is_on_floor() and player.coyote_timer <= 0.0:
			return


func _check_tree_data() -> void:
	"""
	The trees are hand-written data, and every way they go wrong is silent: a
	`prereq` naming a node that is not in that hero's array locks a branch forever
	with no error, a duplicated id makes `rank_of` and `spend` disagree about which
	node was bought, and an effect id nobody reads is a node that costs a point and
	does nothing.

	The last two assertions are the ones that matter most: they pin the two EPIC
	guardrails against the DATA rather than against the getter, so a later retune
	that pushes the tree past a cap fails here instead of being silently clamped
	(clamped is safe, but a node that visibly buys nothing is a bug either way).
	"""
	# Every effect id below is read at a real site in `player_controller.gd`. A new
	# one must be added here AND wired, or it is a node that costs a point for
	# nothing.
	var known_effects: Array[String] = [
		"cooldown", "run_speed",
		"windman_boost", "windman_lift",
		"primm_blink", "primm_refund",
		"teibi_form", "teibi_small_speed",
		"phoboman_flee", "phoboman_radius",
		# The active/exotic nodes (bead godot-test1-20z.4).
		"streak_burst", "windman_gravity", "teibi_quake",
	]
	for hero: String in Progression.SKILL_TREES:
		var seen: Array[String] = []
		var cooldown_total := 0.0
		var run_total := 0.0
		for def: Dictionary in Progression.skills_for(hero):
			var id := String(def.get("id", ""))
			if id.is_empty():
				_fail("%s has a skill with no id" % hero)
				continue
			if seen.has(id):
				_fail("%s has two skills with the id %s" % [hero, id])
			seen.append(id)
			var effect := String(def.get("effect", ""))
			if not known_effects.has(effect):
				_fail("%s.%s has effect %s, which nothing reads" % [hero, id, effect])
			if int(def.get("max_ranks", 0)) < 1:
				_fail("%s.%s has no ranks to buy" % [hero, id])
			if int(def.get("cost", 0)) < 1:
				_fail("%s.%s is free" % [hero, id])
			if float(def.get("per_rank", 0.0)) <= 0.0:
				_fail("%s.%s has a per_rank of 0 — it buys nothing" % [hero, id])
			if String(def.get("desc", "")).is_empty() or String(def.get("name", "")).is_empty():
				_fail("%s.%s has no name/desc for the panel to render" % [hero, id])
			var full := float(def.get("per_rank", 0.0)) * float(int(def.get("max_ranks", 1)))
			if effect == "cooldown":
				cooldown_total += full
			elif effect == "run_speed":
				run_total += full
		for def: Dictionary in Progression.skills_for(hero):
			var prereq := String(def.get("prereq", ""))
			if not prereq.is_empty() and not seen.has(prereq):
				_fail("%s.%s requires %s, which is not in that tree"
						% [hero, String(def["id"]), prereq])
		# The two epic guardrails, measured against the data a player can actually
		# buy — NOT read back off the clamp, which would pass however high the
		# tree went.
		if not is_equal_approx(1.0 - cooldown_total, Progression.COOLDOWN_MULT_MIN):
			_fail("%s's fully-bought cooldown tree gives x%.3f, and the −40%% cap is x%.3f"
					% [hero, 1.0 - cooldown_total, Progression.COOLDOWN_MULT_MIN])
		if 1.0 + run_total > Progression.RUN_SPEED_MULT_MAX + 0.0001:
			_fail("%s's fully-bought run tree gives x%.3f, past the x%.3f cap"
					% [hero, 1.0 + run_total, Progression.RUN_SPEED_MULT_MAX])
		# THE CATCHABLE-WALK CONTRACT, as an assertion rather than a comment: no
		# skill anywhere may scale walk speed. There is no walk effect id, so the
		# only way one could appear is somebody adding it.
		for def: Dictionary in Progression.skills_for(hero):
			if String(def.get("effect", "")).contains("walk"):
				_fail("%s.%s scales WALK speed — the catchable-walk contract forbids it"
						% [hero, String(def["id"])])
	Sentinel.done("tree_data")


func _check_spending() -> void:
	"""
	Spend, refuse, and every refusal's negative control.

	Each half of this is a pair on purpose: "the rank went up" is also true of a
	`spend()` that never checks anything, so every assertion that a purchase WORKED
	is accompanied by one that the same purchase is REFUSED when it should be.
	"""
	var progression := _make_progression()
	var hero := "windman"

	# NEGATIVE CONTROL 1 — no points, so nothing can be bought.
	if progression.spend(hero, "cd1"):
		_fail("bought a rank at level 0 with no skill points")
	if progression.rank_of(hero, "cd1") != 0 or progression.spent_points != 0:
		_fail("a refused spend still moved the profile: rank %d / %d spent"
				% [progression.rank_of(hero, "cd1"), progression.spent_points])

	_grant_points(progression, 8)
	if progression.unspent_points() != 8:
		_fail("granting 8 levels left %d unspent points" % progression.unspent_points())

	# NEGATIVE CONTROL 2 — the prerequisite gate, tested BEFORE its parent is
	# bought (afterwards it would pass whether or not the gate exists).
	if progression.is_unlocked(hero, "cd2"):
		_fail("cd2 is unlocked with no rank in its prerequisite cd1")
	if progression.spend(hero, "cd2"):
		_fail("bought a locked skill")
	if progression.spent_points != 0:
		_fail("a locked purchase charged %d points" % progression.spent_points)

	# NEGATIVE CONTROL 3 — an unknown hero and an unknown skill buy nothing.
	if progression.spend("nobody", "cd1") or progression.spend(hero, "not_a_skill"):
		_fail("bought a skill that does not exist")

	# The real purchase.
	if not progression.spend(hero, "cd1"):
		_fail("could not buy cd1 with 8 points and no prerequisite")
	if progression.rank_of(hero, "cd1") != 1 or progression.spent_points != 1:
		_fail("one purchase left rank %d / %d spent, wanted 1 / 1"
				% [progression.rank_of(hero, "cd1"), progression.spent_points])
	if progression.unspent_points() != 7:
		_fail("one purchase left %d unspent, wanted 7" % progression.unspent_points())
	# ...and the child is unlocked by it, which is the positive half of control 2.
	if not progression.is_unlocked(hero, "cd2"):
		_fail("cd2 is still locked after a rank in cd1")

	# LIFETIME COINS ARE NEVER DEDUCTED — the rule every layer under this one
	# depends on. Spending must move `spent_points` and nothing else.
	var lifetime_before := progression.lifetime_coins
	var level_before := progression.level
	progression.spend(hero, "cd1")
	if progression.lifetime_coins != lifetime_before or progression.level != level_before:
		_fail("spending changed the coin total / level: %d coins, level %d"
				% [progression.lifetime_coins, progression.level])

	# NEGATIVE CONTROL 4 — max ranks. cd1 is 3 ranks; the fourth must be refused
	# with points still in hand, or the cap is not a cap.
	progression.spend(hero, "cd1")
	if progression.rank_of(hero, "cd1") != 3:
		_fail("three purchases gave rank %d" % progression.rank_of(hero, "cd1"))
	var spent_at_max := progression.spent_points
	if progression.spend(hero, "cd1"):
		_fail("bought a fourth rank of a 3-rank skill")
	if progression.rank_of(hero, "cd1") != 3 or progression.spent_points != spent_at_max:
		_fail("the refused fourth rank still charged a point")

	# PER-HERO, not global: another hero's tree is untouched by all of that.
	if progression.rank_of("primm", "cd1") != 0:
		_fail("buying windman's cd1 gave primm %d ranks of it"
				% progression.rank_of("primm", "cd1"))
	# ...but the POINTS are shared, which is what makes the choice a choice.
	if progression.unspent_points() != 8 - spent_at_max:
		_fail("points are not shared across heroes: %d unspent after %d spent"
				% [progression.unspent_points(), spent_at_max])

	progression.free()
	Sentinel.done("spending")


func _check_caps() -> void:
	"""
	The two hard caps, measured at 0 ranks and at every rank bought.

	The 0-rank half is the negative control and it is the load-bearing one: a
	`skill_mult` that returned a constant 0.6 would satisfy the capped assertion
	on its own, and a player with no skills at all would be quietly 40% faster to
	recover than the game is designed around.
	"""
	var progression := _make_progression()
	var hero := "teibi"

	if not is_equal_approx(progression.skill_mult(hero, "cooldown"), 1.0):
		_fail("an unranked hero's cooldown multiplier is %.3f, wanted 1.0"
				% progression.skill_mult(hero, "cooldown"))
	if not is_equal_approx(progression.skill_mult(hero, "run_speed"), 1.0):
		_fail("an unranked hero's run multiplier is %.3f, wanted 1.0"
				% progression.skill_mult(hero, "run_speed"))
	if not is_equal_approx(progression.skill_mult(hero, "teibi_form"), 1.0):
		_fail("an unranked hero's form multiplier is %.3f, wanted 1.0"
				% progression.skill_mult(hero, "teibi_form"))
	if not is_equal_approx(progression.skill_bonus(hero, "primm_refund"), 0.0):
		_fail("an unranked hero has a %.3f s cooldown refund"
				% progression.skill_bonus(hero, "primm_refund"))
	# An unknown effect must be inert rather than an error, because that is what
	# lets `player_controller` call this at a site whose hero has no such node.
	if not is_equal_approx(progression.skill_mult(hero, "windman_lift"), 1.0):
		_fail("teibi has a windman_lift multiplier of %.3f"
				% progression.skill_mult(hero, "windman_lift"))

	_grant_points(progression, 10)
	for i in 3:
		progression.spend(hero, "cd1")
	progression.spend(hero, "cd2")
	progression.spend(hero, "fleet")
	progression.spend(hero, "fleet")

	if not is_equal_approx(progression.skill_mult(hero, "cooldown"), Progression.COOLDOWN_MULT_MIN):
		_fail("a fully-ranked cooldown tree gives x%.3f, wanted the x%.3f cap"
				% [progression.skill_mult(hero, "cooldown"), Progression.COOLDOWN_MULT_MIN])
	if not is_equal_approx(progression.skill_mult(hero, "run_speed"), 1.14):
		_fail("a fully-ranked run tree gives x%.3f, wanted x1.14"
				% progression.skill_mult(hero, "run_speed"))
	if progression.skill_mult(hero, "run_speed") > Progression.RUN_SPEED_MULT_MAX:
		_fail("the run multiplier passed its own cap")

	# THE STACKING CASE. Teibi's Scurry is a movement passive too, so the +20% cap
	# has to hold over the SUM rather than over each half: multiplying a capped
	# x1.14 by a capped x1.10 gives x1.254, which both halves individually respect
	# and the guardrail does not. `gait_mult()` is the one place that is decided.
	if not is_equal_approx(progression.gait_mult(hero, false), 1.14):
		_fail("a normal-form fully-ranked Teibi has a gait multiplier of x%.3f, wanted x1.14"
				% progression.gait_mult(hero, false))
	_spend_or_fail(progression, hero, "hold")  # Scurry's prerequisite
	_spend_or_fail(progression, hero, "scurry")
	if progression.gait_mult(hero, true) > Progression.RUN_SPEED_MULT_MAX + 0.0001:
		_fail("Fleet Foot + Scurry stack to x%.3f in small form, past the x%.3f cap"
				% [progression.gait_mult(hero, true), Progression.RUN_SPEED_MULT_MAX])
	if not is_equal_approx(progression.gait_mult(hero, true), Progression.RUN_SPEED_MULT_MAX):
		_fail("a maxed small Teibi has a gait multiplier of x%.3f, wanted the x%.3f cap"
				% [progression.gait_mult(hero, true), Progression.RUN_SPEED_MULT_MAX])
	# NEGATIVE CONTROL for that clamp: Scurry must still be worth its point to a
	# Teibi who has NOT maxed Fleet Foot, or the cap has turned it into a node that
	# silently buys nothing. Measured on a second, otherwise-empty profile.
	var lone := _make_progression()
	_grant_points(lone, 2)
	_spend_or_fail(lone, "teibi", "hold")
	_spend_or_fail(lone, "teibi", "scurry")
	if not is_equal_approx(lone.gait_mult("teibi", true), 1.10):
		_fail("Scurry alone gives x%.3f in small form, wanted x1.10"
				% lone.gait_mult("teibi", true))
	if not is_equal_approx(lone.gait_mult("teibi", false), 1.0):
		_fail("Scurry applies at x%.3f in NORMAL form — it is a small-form skill"
				% lone.gait_mult("teibi", false))
	lone.free()

	# THE CLAMP ITSELF, exercised past what the tree can reach: the caps are a
	# balance contract, so they have to hold for a hand-edited or migrated profile
	# too, not only for one the UI produced.
	progression.skill_ranks[hero]["cd1"] = 99
	if not is_equal_approx(progression.skill_mult(hero, "cooldown"), Progression.COOLDOWN_MULT_MIN):
		_fail("99 cooldown ranks broke the −40%% cap: x%.3f"
				% progression.skill_mult(hero, "cooldown"))
	progression.skill_ranks[hero]["fleet"] = 99
	if not is_equal_approx(progression.skill_mult(hero, "run_speed"), Progression.RUN_SPEED_MULT_MAX):
		_fail("99 run ranks broke the +20%% cap: x%.3f"
				% progression.skill_mult(hero, "run_speed"))

	# THE THIRD CAP (bead godot-test1-20z.4): Air Rush gravity. Same three-part
	# shape as the two above — inert unranked, exact at the buyable maximum, and
	# still clamped past what the tree can reach.
	var flier := _make_progression()
	if not is_equal_approx(flier.skill_mult("windman", "windman_gravity"), 1.0):
		_fail("an unranked Windman's Air Rush gravity is x%.3f, wanted 1.0"
				% flier.skill_mult("windman", "windman_gravity"))
	_grant_points(flier, 6)
	_spend_or_fail(flier, "windman", "gale")
	_spend_or_fail(flier, "windman", "updraft")
	_spend_or_fail(flier, "windman", "updraft")
	_spend_or_fail(flier, "windman", "soar")
	_spend_or_fail(flier, "windman", "soar")
	if not is_equal_approx(flier.skill_mult("windman", "windman_gravity"),
			Progression.WINDMAN_GRAVITY_MULT_MIN):
		_fail("a fully-ranked Feather Fall gives x%.3f, wanted the x%.3f cap"
				% [flier.skill_mult("windman", "windman_gravity"),
					Progression.WINDMAN_GRAVITY_MULT_MIN])
	# The second Updraft rank the active-skills bead added has to be REACHABLE,
	# not merely declared — a max_ranks bump with a stale prereq buys nothing.
	if not is_equal_approx(flier.skill_mult("windman", "windman_lift"), 1.40):
		_fail("Updraft x2 gives x%.3f lift, wanted x1.40"
				% flier.skill_mult("windman", "windman_lift"))
	flier.skill_ranks["windman"]["soar"] = 99
	if not is_equal_approx(flier.skill_mult("windman", "windman_gravity"),
			Progression.WINDMAN_GRAVITY_MULT_MIN):
		_fail("99 Feather Fall ranks broke the −20%% gravity cap: x%.3f"
				% flier.skill_mult("windman", "windman_gravity"))
	# NEGATIVE CONTROL for the clamp's direction: gravity is a REDUCING effect, so
	# a getter that fell through to the default `1.0 + total` branch would read
	# 1.20 here and make a skilled Air Rush drop FASTER than an unskilled one.
	if flier.skill_mult("windman", "windman_gravity") >= 1.0:
		_fail("Feather Fall did not reduce Air Rush gravity (x%.3f)"
				% flier.skill_mult("windman", "windman_gravity"))
	flier.free()

	progression.free()
	Sentinel.done("caps")


func _check_ranks_merge_is_monotone() -> void:
	"""
	`BestRunStore.merge_ranks()` is what makes the ranks safe to keep in a store
	that is read, re-read and rewritten from two places. It has exactly the same
	failure mode as the scalars beside it: an assignment instead of a max reads as
	working right up until a stale copy lands last, and then takes ranks away.
	"""
	var into: Dictionary = {"windman": {"cd1": 3, "fleet": 1}}
	BestRunStore.merge_ranks(into, {"windman": {"cd1": 1}, "primm": {"reach": 2}})
	# NEGATIVE CONTROL: the BEHIND entry must change nothing...
	if int(into["windman"]["cd1"]) != 3:
		_fail("a behind rank lowered cd1 to %d" % int(into["windman"]["cd1"]))
	if int(into["windman"]["fleet"]) != 1:
		_fail("merging dropped an entry the incoming map did not mention")
	# ...while a genuinely new hero and a genuinely higher rank both land.
	if int(into.get("primm", {}).get("reach", 0)) != 2:
		_fail("merging did not add a hero the local map had never seen")
	BestRunStore.merge_ranks(into, {"windman": {"cd1": 5}})
	if int(into["windman"]["cd1"]) != 5:
		_fail("a higher rank did not raise cd1")

	# Junk out of `localStorage` (a string a player can edit) is skipped per entry
	# rather than taking the whole map down with it.
	BestRunStore.merge_ranks(into, {"windman": "not a dict", 7: {"x": 1}})
	BestRunStore.merge_ranks(into, {"windman": {"cd1": "three", "fleet": -4}})
	if int(into["windman"]["cd1"]) != 5 or int(into["windman"]["fleet"]) != 1:
		_fail("a malformed rank map corrupted the real ranks: %s" % [into["windman"]])
	Sentinel.done("ranks_merge_is_monotone")


func _check_skill_effects_on_player() -> void:
	"""
	THE ACCEPTANCE MEASUREMENT: the skills reach the real `player_controller`, and
	the two things that must NOT move do not.

	Everything here is measured through the live player, with the SAME player
	measured before and after the ranks are bought — so the baseline is not a
	re-typed constant that could drift out of step with the one under test.

	The standalone case runs FIRST and is the negative control for the whole file:
	with no Progression node in the tree every multiplier must be 1.0, i.e. the
	player scene run on its own is the game exactly as it was before this bead.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("skill_effects_on_player")
		return
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("calculate_current_speed"):
		_fail("player has no calculate_current_speed() — did the script fail to attach?")
		player.queue_free()
		Sentinel.done("skill_effects_on_player")
		return

	# --- Baseline, with NO progression node anywhere ---------------------
	player.is_wading = false
	var base_walk: Dictionary = {}
	var base_run: Dictionary = {}
	for index in player.CHARACTERS.size():
		player.set_active_character(index)
		var hero: String = String(player.CHARACTERS[index]["name"])
		player.is_running = false
		player.is_ducking = false
		base_walk[hero] = float(player.calculate_current_speed())
		player.is_running = true
		base_run[hero] = float(player.calculate_current_speed())
		# Standalone means untouched: the gait must be exactly the shipped formula.
		var want_walk: float = player.WALK_SPEED * float(player.CHARACTER_SPEED.get(hero, 1.0))
		if not is_equal_approx(base_walk[hero], want_walk):
			_fail("standalone %s walks at %.3f, wanted the unskilled %.3f"
					% [hero, base_walk[hero], want_walk])

	# --- Now with a progression node and every speed node bought ---------
	# Comfortably more points than this function spends (8 movement + 4 teibi
	# cooldown + 3 Air Rush + 7 finishing Windman off for the grounding-gate probe
	# = 22). A budget that runs out mid-way makes every later purchase a silent
	# no-op and the measurement it feeds a silent pass, so `_spend_or_fail` below
	# says so instead.
	var progression := _make_progression()
	_grant_points(progression, 32)
	for hero: String in Progression.SKILL_TREES:
		_spend_or_fail(progression, hero, "fleet")
		_spend_or_fail(progression, hero, "fleet")

	for index in player.CHARACTERS.size():
		player.set_active_character(index)
		var hero: String = String(player.CHARACTERS[index]["name"])
		player.is_running = false
		player.is_ducking = false
		var walk: float = float(player.calculate_current_speed())
		player.is_running = true
		var run: float = float(player.calculate_current_speed())

		# THE CATCHABLE-WALK CONTRACT: byte-identical walking, with every speed
		# node maxed. This is the assertion the whole movement branch exists for.
		if walk != base_walk[hero]:
			_fail("%s's WALK speed moved from %.6f to %.6f with speed skills maxed — "
					% [hero, base_walk[hero], walk]
					+ "the catchable-walk contract forbids it")
		# ...and the negative control for that: running DID rise, or the check
		# above would also pass on a build where the skills do nothing at all.
		if run <= base_run[hero]:
			_fail("%s's run speed did not rise with the speed nodes maxed (%.3f → %.3f)"
					% [hero, base_run[hero], run])
		if not is_equal_approx(run, base_run[hero] * 1.14):
			_fail("%s runs at %.3f with +14%% bought, wanted %.3f"
					% [hero, run, base_run[hero] * 1.14])
		# "Running always escapes" still holds — it can only have got safer, since
		# skills never lower a gait, but the number is cheap to pin.
		if run < player.WADE_RUN_MIN_SPEED:
			_fail("%s runs at %.3f, under the %.3f the escape hatch needs"
					% [hero, run, player.WADE_RUN_MIN_SPEED])

		# Wading still hits its floor rather than falling through it.
		player.is_wading = true
		var wet_run: float = float(player.calculate_current_speed())
		player.is_wading = false
		if wet_run < player.WADE_RUN_MIN_SPEED:
			_fail("%s wades-runs at %.3f, below the WADE_RUN_MIN_SPEED floor"
					% [hero, wet_run])

	player.is_running = false

	# --- Cooldowns, and the HUD dial that divides by them ----------------
	# Teibi, because `_ability_teibi()` is the one ability that always fires (no
	# geometry, no weather, no direction needed).
	var teibi_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "teibi":
			teibi_index = index
	if teibi_index < 0:
		_fail("no teibi in CHARACTERS — the cooldown measurement needs it")
	else:
		player.set_active_character(teibi_index)
		var base_cooldown: float = float(player.ABILITY_COOLDOWN["teibi"])

		player.ability_cooldowns[teibi_index] = 0.0
		# The dial's READY and GATED states, on the hero that has no gates at all:
		# charged reads ready, and the reason stays empty either way (the gates are
		# Windman's — see the grounding-gate probe for those).
		_check_dial_contract(player, true, "", "a charged teibi")
		player.try_activate_ability()
		var unskilled: float = float(player.ability_cooldowns[teibi_index])
		# THE REVERT COMES FIRST since bead godot-test1-8rg: the press left him
		# SMALL, and an altered form waives the cooldown, so both reads below would
		# be measuring the waiver instead of the charge. `_revert_teibi_to_normal()`
		# does not touch `ability_cooldowns`, so the charge under test is untouched
		# — and the cooling arm is still measured on this hero, one line later.
		player._revert_teibi_to_normal()
		var unskilled_ratio: float = float(player.get_ability_cooldown_ratio())
		# ...and the COOLING state: a spent charge is not ready, with no gate to
		# blame — the arm the dial draws as an emptying amber arc.
		_check_dial_contract(player, false, "", "a just-fired teibi")
		if not is_equal_approx(unskilled, base_cooldown):
			_fail("an unranked teibi charged %.3f s of cooldown, wanted %.3f"
					% [unskilled, base_cooldown])

		for _i in 3:
			_spend_or_fail(progression, "teibi", "cd1")
		_spend_or_fail(progression, "teibi", "cd2")

		player.ability_cooldowns[teibi_index] = 0.0
		player.try_activate_ability()
		var skilled: float = float(player.ability_cooldowns[teibi_index])
		player._revert_teibi_to_normal()   # before the ratio — see above
		var skilled_ratio: float = float(player.get_ability_cooldown_ratio())
		if not is_equal_approx(skilled, base_cooldown * Progression.COOLDOWN_MULT_MIN):
			_fail("a fully-ranked teibi charged %.3f s of cooldown, wanted %.3f"
					% [skilled, base_cooldown * Progression.COOLDOWN_MULT_MIN])
		if skilled >= unskilled:
			_fail("cooldown ranks did not shorten the cooldown (%.3f → %.3f)"
					% [unskilled, skilled])
		# THE HUD LANDMINE: the dial divides by the cooldown length, so it must be
		# exactly full the instant the ability fires — in BOTH cases. Divide by the
		# UNSKILLED constant and this reads 0.6 for a skilled hero: no error
		# anywhere, just a dial that has stopped meaning what it says.
		if not is_equal_approx(unskilled_ratio, 1.0) or not is_equal_approx(skilled_ratio, 1.0):
			_fail("the cooldown dial starts at %.3f unranked / %.3f ranked, wanted 1.0 / 1.0"
					% [unskilled_ratio, skilled_ratio])

		# THE REFUND PATH, driven through the generic one-shot rather than through
		# Primm's blink (which needs real geometry to pass through): a pending
		# refund comes off the charge and is CONSUMED, so the next press pays full.
		player.ability_cooldowns[teibi_index] = 0.0
		player._pending_cooldown_refund = 1.0
		player.try_activate_ability()
		var refunded: float = float(player.ability_cooldowns[teibi_index])
		player._revert_teibi_to_normal()
		if not is_equal_approx(refunded, skilled - 1.0):
			_fail("a 1 s refund left %.3f s of cooldown, wanted %.3f" % [refunded, skilled - 1.0])
		player.ability_cooldowns[teibi_index] = 0.0
		player.try_activate_ability()
		var after_refund: float = float(player.ability_cooldowns[teibi_index])
		player._revert_teibi_to_normal()
		# NEGATIVE CONTROL: without this, a refund that latched instead of being
		# consumed would shorten every press for the rest of the run.
		if not is_equal_approx(after_refund, skilled):
			_fail("the cooldown refund was not consumed — the next press paid %.3f, wanted %.3f"
					% [after_refund, skilled])

		# --- THE RESIZE WAIVER (bead godot-test1-8rg) ------------------------
		# Owner: "teibi shouldn't mandatory wait in tiny state cooldown to become
		# giant". So while he is ALREADY in an altered form the cooldown is waived
		# — and the load-bearing half is that the waiver is read from ONE place
		# (`player._cooldown_remaining()`), which is what stops the dial saying
		# BLOCKED over a press that fires. `_check_dial_contract()` asserts that
		# triple, so it is the measurement here, not a hand-written comparison.
		#
		# The three shipped rulings that must survive a faster giant are driven
		# here too: entering an altered form still PAYS, the form budget is not
		# refilled by the free press, and normal size re-arms the price. (The
		# INDOOR refusal and the fit probe need a building — `capture_selfcheck`
		# check 9 drives those, now with the cooldown deliberately left hot.)
		player.ability_cooldowns[teibi_index] = 0.0
		player.try_activate_ability()                       # normal -> small
		if player.teibi_size_state != 1:
			_fail("the waiver probe could not make teibi small (state %d)"
					% player.teibi_size_state)
		var entry_cost: float = float(player.ability_cooldowns[teibi_index])
		if entry_cost <= 0.0:
			_fail("entering an altered form charged no cooldown — the waiver ate the price")
		# CHARGED BUT WAIVED reads exactly like ready, in all three of the dial's
		# inputs: no gate, a full ring (ratio 0) and no countdown to show.
		_check_dial_contract(player, true, "", "a small teibi holding a hot cooldown")
		if not is_zero_approx(float(player.get_ability_remaining())):
			_fail("the dial counts %.3f s down at a press that fires"
					% player.get_ability_remaining())
		# Part-spend the form budget, then take the free press: reaching giant
		# sooner must spend the SAME budget (TEIBI_FORM_DURATION is a total for the
		# whole excursion), or this bead shipped a longer giant, not a faster one.
		player.teibi_form_timer = 3.0
		player.try_activate_ability()                       # small -> giant, waived
		if player.teibi_size_state != 2 or not player.is_giant:
			_fail("a small teibi holding %.3f s of cooldown could not become giant (state %d)"
					% [entry_cost, player.teibi_size_state])
		if not is_equal_approx(float(player.teibi_form_timer), 3.0):
			_fail("the free press refilled the form budget to %.3f s, wanted the 3.000 s left"
					% player.teibi_form_timer)
		if float(player.ability_cooldowns[teibi_index]) > entry_cost:
			_fail("the free press charged cooldown on top: %.3f -> %.3f"
					% [entry_cost, player.ability_cooldowns[teibi_index]])
		player.try_activate_ability()                       # giant -> normal, waived
		if player.teibi_size_state != 0 or player.is_giant:
			_fail("the waived press home left teibi in state %d" % player.teibi_size_state)
		# ...AND THE PRICE IS BACK ON. Normal size reads the real timer again, which
		# is the whole "entering an altered form still pays" half of the ruling —
		# and the negative control for a waiver that latched instead of tracking
		# `teibi_size_state`.
		if float(player.ability_cooldowns[teibi_index]) <= 0.0:
			_fail("the press home charged no cooldown, so the next entry is free too")
		_check_dial_contract(player, false, "", "a normal-size teibi after the waived cycle")
		player.ability_cooldowns[teibi_index] = 0.0

	# --- Windman's two ability multipliers, measured on the body ---------
	var windman_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "windman":
			windman_index = index
	if windman_index >= 0:
		player.set_active_character(windman_index)
		player._ability_windman()
		var plain_lift: float = float(player.velocity.y)
		var plain_boost: float = float(player.windman_boost_timer)
		_spend_or_fail(progression, "windman", "gale")
		_spend_or_fail(progression, "windman", "gale")
		_spend_or_fail(progression, "windman", "updraft")
		player._ability_windman()
		var lifted: float = float(player.velocity.y)
		var boosted: float = float(player.windman_boost_timer)
		if not is_equal_approx(plain_lift, player.WINDMAN_LIFT):
			_fail("an unranked Air Rush launched at %.3f, wanted %.3f"
					% [plain_lift, player.WINDMAN_LIFT])
		if not is_equal_approx(lifted, player.WINDMAN_LIFT * 1.20):
			_fail("Updraft launched at %.3f, wanted %.3f"
					% [lifted, player.WINDMAN_LIFT * 1.20])
		if not is_equal_approx(plain_boost, player.WINDMAN_BOOST_DURATION):
			_fail("an unranked Air Rush lasted %.3f s, wanted %.3f"
					% [plain_boost, player.WINDMAN_BOOST_DURATION])
		if not is_equal_approx(boosted, player.WINDMAN_BOOST_DURATION * 1.30):
			_fail("Long Gale x2 lasted %.3f s, wanted %.3f"
					% [boosted, player.WINDMAN_BOOST_DURATION * 1.30])

		# --- THE GROUNDING GATE: one Air Rush per landing --------------------
		# The exploit this closes is arithmetic, and the arithmetic is STILL TRUE
		# below — nothing was retuned. Max the Focus branch and the cooldown
		# (8.0 x 0.60 = 4.80 s) comes back 0.4 s BEFORE the maxed flight
		# (4.0 x 1.30 = 5.20 s) has even finished, so with Updraft and Feather
		# Fall holding him up, the only thing between a fully-skilled Windman and
		# endless flight is the ground check in `try_activate_ability()`.
		#
		# Driven through `try_activate_ability()` rather than `_ability_windman()`
		# on purpose: the gate lives there, and that function is the single funnel
		# BOTH the F key and the touch "Special" button fire through — so proving
		# it here proves it on mobile too, with no second code path to test.
		#
		# Airborne and grounded are REAL physics states here, not a poked
		# variable: a floor is added under the player and he is moved on and off
		# it, with the precondition asserted each time. A probe that faked
		# `is_on_floor()` would still pass against a gate wired to the wrong thing.
		for _i in 3:
			_spend_or_fail(progression, "windman", "cd1")
		_spend_or_fail(progression, "windman", "cd2")
		_spend_or_fail(progression, "windman", "updraft")
		_spend_or_fail(progression, "windman", "soar")
		_spend_or_fail(progression, "windman", "soar")

		var cd_max: float = float(player._skilled_ability_cooldown())
		var fly_max: float = player.WINDMAN_BOOST_DURATION \
				* progression.skill_mult("windman", "windman_boost")
		if cd_max >= fly_max:
			# Not a gate failure — a shout that the numbers moved underneath this
			# probe, which would then be proving something easier than it was
			# written for (the cooldown alone would already break the chain).
			print("NOTE: windman cooldown %.2f s >= flight %.2f s; the grounding gate "
					% [cd_max, fly_max] + "is now belt-and-braces rather than the only guard")

		var floor_body := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		var floor_box := BoxShape3D.new()
		floor_box.size = Vector3(40.0, 2.0, 40.0)
		floor_shape.shape = floor_box
		floor_body.add_child(floor_shape)
		root.add_child(floor_body)
		floor_body.global_position = Vector3(0.0, -1.0, 0.0)  # top face at y = 0

		# 1. GROUNDED — the designed flight is untouched. This is the half that
		#    fails if the gate ever turns into a nerf of legitimate play.
		await _settle_on_floor(player)
		if not player.is_on_floor():
			_fail("the grounded case never landed — the gate probe below proves nothing")
		player.windman_boost_timer = 0.0
		player.ability_cooldowns[windman_index] = 0.0
		player.try_activate_ability()
		if not is_equal_approx(float(player.windman_boost_timer), fly_max):
			_fail("a grounded fully-skilled Air Rush lasted %.3f s, wanted the full %.3f"
					% [player.windman_boost_timer, fly_max])
		if not is_equal_approx(float(player.ability_cooldowns[windman_index]), cd_max):
			_fail("a grounded Air Rush charged %.3f s of cooldown, wanted %.3f"
					% [player.ability_cooldowns[windman_index], cd_max])

		# 2. AIRBORNE with the cooldown already back — the exploit's exact moment:
		#    0.4 s of flight still to run and the power ready again. Refuse it.
		await _lift_into_the_air(player)
		if player.is_on_floor() or player.coyote_timer > 0.0:
			_fail("the airborne case never left the ground (floor=%s coyote=%.3f)"
					% [player.is_on_floor(), player.coyote_timer])
		player.windman_boost_timer = 0.4
		player.ability_cooldowns[windman_index] = 0.0
		var falling: float = float(player.velocity.y)
		# THE MISLEADING DIAL (godot-test1-tw6): this is the exact state that used
		# to paint a green READY ring — cooldown spent, every press refused. The
		# HUD must see the gate, and must see it as its OWN state rather than as a
		# cooldown that has not finished.
		_check_dial_contract(player, false, "LAND", "an airborne charged windman")
		player.try_activate_ability()
		if not is_equal_approx(float(player.windman_boost_timer), 0.4):
			_fail("a mid-air Air Rush re-fired (boost jumped to %.3f s) — endless flight is still open"
					% player.windman_boost_timer)
		if player.velocity.y > falling:
			_fail("a refused Air Rush still launched him: %.3f m/s, was falling at %.3f"
					% [player.velocity.y, falling])
		# ...and refusing is FREE, exactly like the rain gate: pressing F in the
		# air is a no-op, not a punishment that eats the next landing's rush.
		if not is_zero_approx(float(player.ability_cooldowns[windman_index])):
			_fail("a refused mid-air press still charged %.3f s of cooldown"
					% player.ability_cooldowns[windman_index])

		# 3. LANDING RE-ARMS IT. The gate is a pure read of live state and stores
		#    nothing, so it has nothing to latch on: feet down, next press flies.
		#    (Same reason a respawn or a hero switch cannot strand him — neither
		#    has any gate state to clear.)
		player.windman_boost_timer = 0.0
		await _settle_on_floor(player)
		if not player.is_on_floor():
			_fail("the landing case never touched down — the latch check below "
					+ "would blame the gate for a probe that never landed")
		player.ability_cooldowns[windman_index] = 0.0
		# The dial clears the moment the gate does: landing is the fix it named.
		_check_dial_contract(player, true, "", "a landed charged windman")
		player.try_activate_ability()
		if is_zero_approx(float(player.windman_boost_timer)):
			_fail("Windman was still refused after landing — the grounding gate latched")

		# 3b. THE RAIN GATE, the other half of the same contract: grounded, charged
		#     and refused, with its own label so the dial can tell the player which
		#     fix applies (walk out of the storm, not land). Also proves the two
		#     gates are separate reads rather than one flag wearing two names.
		var weather := StubWeather.new()
		root.add_child(weather)
		weather.add_to_group("weather")
		player.windman_boost_timer = 0.0
		await _settle_on_floor(player)
		player.ability_cooldowns[windman_index] = 0.0
		_check_dial_contract(player, false, "RAIN", "a grounded windman in the rain")
		player.try_activate_ability()
		if not is_zero_approx(float(player.windman_boost_timer)):
			_fail("Windman took off inside a rain zone (boost %.3f s)"
					% player.windman_boost_timer)
		if not is_zero_approx(float(player.ability_cooldowns[windman_index])):
			_fail("a refused rainy press still charged %.3f s of cooldown"
					% player.ability_cooldowns[windman_index])
		weather.queue_free()
		await physics_frame
		_check_dial_contract(player, true, "", "windman once the storm passed")

		# 4. It is WINDMAN's gate, not a blanket airborne ban: a mid-air Teibi
		#    still transforms. (Switching heroes is blocked mid-boost in the real
		#    game, so clear the boost first, as expiry would.)
		if teibi_index >= 0:
			player.windman_boost_timer = 0.0
			player.set_active_character(teibi_index)
			await _lift_into_the_air(player)
			player.ability_cooldowns[teibi_index] = 0.0
			player.try_activate_ability()
			if is_zero_approx(float(player.ability_cooldowns[teibi_index])):
				_fail("the grounding gate refused a mid-air teibi — it must gate windman alone")
			player._revert_teibi_to_normal()
			player.set_active_character(windman_index)

		floor_body.queue_free()
		player.windman_boost_timer = 0.0
		player.velocity = Vector3.ZERO

	progression.free()
	player.queue_free()
	Sentinel.done("skill_effects_on_player")


func _check_ranks_survive_a_relaunch() -> void:
	"""
	Ranks come back after the game is closed — the bead's own acceptance line, and
	the one thing `merge_ranks()` on its own cannot prove.

	That unit check pins the MERGE RULE; this pins the SERIALIZATION either side of
	it, which fails in ways the merge never sees: a mistyped ConfigFile key, a
	Dictionary written raw where the reader expects JSON, or a `_read_local()` that
	simply never looks. All of those leave every in-memory assertion green and
	silently drop a player's whole tree on the next launch.

	Driven against the LOCAL layer only — a second `BestRunStore` reading what the
	first wrote IS what "relaunch" means here — so it makes no network request and
	POSTs nothing. That local layer is `LOCAL_STORE_PATH`, not the machine's
	profile (see the header): the write below is a monotone merge, so against a
	real profile this would read back that profile's numbers instead of its own.
	"""
	var ranks: Dictionary = {"windman": {"cd1": 2, "gale": 1}, "teibi": {"fleet": 2}}

	var writer := BestRunStore.new()
	writer.lifetime_coins = 1234
	writer.spent_points = 5
	BestRunStore.merge_ranks(writer.skill_ranks, ranks)
	writer._write_local()
	writer.free()

	# A brand-new store, exactly as the next launch would build one.
	var reader := BestRunStore.new()
	reader._read_local()
	if reader.spent_points != 5 or reader.lifetime_coins != 1234:
		_fail("the counters did not survive a relaunch: %d coins / %d spent"
				% [reader.lifetime_coins, reader.spent_points])
	if int(reader.skill_ranks.get("windman", {}).get("cd1", 0)) != 2 \
			or int(reader.skill_ranks.get("windman", {}).get("gale", 0)) != 1 \
			or int(reader.skill_ranks.get("teibi", {}).get("fleet", 0)) != 2:
		_fail("the skill ranks did not survive a relaunch: %s" % [reader.skill_ranks])

	# ...and a `Progression` built on that store reads them back as real ranks,
	# which is the half that would still be broken if `_on_progression_loaded`
	# ignored `store.skill_ranks` (it cannot come through the signal — see there).
	var progression := _make_progression()
	progression.store = reader
	progression._on_progression_loaded(reader.lifetime_coins, reader.spent_points)
	if progression.rank_of("windman", "cd1") != 2:
		_fail("a relaunched profile has %d ranks of windman.cd1, wanted 2"
				% progression.rank_of("windman", "cd1"))
	# NEGATIVE CONTROL: the ranks are the ones that were STORED, not a default —
	# an untouched node must still read 0, or "the ranks loaded" would also be true
	# of a loader that filled the tree in.
	if progression.rank_of("windman", "cd2") != 0:
		_fail("a relaunched profile invented %d ranks of an unbought skill"
				% progression.rank_of("windman", "cd2"))
	# The store is freed by hand rather than by the node, since it was never
	# added as a child.
	progression.store = null
	progression.free()
	reader.free()
	Sentinel.done("ranks_survive_a_relaunch")


func _check_phase_echo_refunds_a_wall_pass() -> void:
	"""
	Primm's Phase Echo pays out for going THROUGH something, and the wall is
	usually NOT at the landing spot.

	This is the bug the review found, kept as a check because it is invisible in
	every other way: the landing scan starts at the desired distance and only ever
	walks outward, so a 2 m block three metres ahead — the ordinary case, and the
	whole point of Phase Step — leaves the first candidate clear and the refund
	silently never fires. Nothing errors; the skill just does nothing most of the
	time.

	So it is measured against REAL geometry, with the negative control first: the
	same blink over open ground must refund nothing, or "the refund fired" would
	also be true of a build that refunds unconditionally.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("phase_echo_refunds_a_wall_pass")
		return
	var player: Node3D = packed.instantiate()
	root.add_child(player)
	await physics_frame

	var primm_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "primm":
			primm_index = index
	if primm_index < 0:
		_fail("no primm in CHARACTERS — the Phase Echo measurement needs it")
		player.queue_free()
		Sentinel.done("phase_echo_refunds_a_wall_pass")
		return
	player.set_active_character(primm_index)
	player.global_position = Vector3.ZERO
	player.global_rotation = Vector3.ZERO  # facing -Z, which is `-basis.z`

	var progression := _make_progression()
	_grant_points(progression, 4)
	_spend_or_fail(progression, "primm", "reach")  # Phase Echo's prerequisite
	_spend_or_fail(progression, "primm", "echo")
	var want_refund: float = progression.skill_bonus("primm", "primm_refund")
	if want_refund <= 0.0:
		_fail("Phase Echo is ranked but refunds %.3f s — nothing below can be measured"
				% want_refund)

	# NEGATIVE CONTROL: open ground, so no wall was passed and nothing is refunded.
	player._pending_cooldown_refund = 0.0
	if not player._ability_primm():
		_fail("the open-ground blink did not fire")
	if not is_equal_approx(player._pending_cooldown_refund, 0.0):
		_fail("a blink across open ground refunded %.3f s of cooldown"
				% player._pending_cooldown_refund)

	# Now a thin wall BETWEEN Primm and a clear landing spot. 2 m deep at 3 m out,
	# so the 7.2 m landing point (6.0 x Long Step's +20%) is well past it and the
	# landing scan's first candidate is clear — exactly the case that used to pay
	# nothing.
	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 2.0)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_position = Vector3(0.0, 1.0, -3.0)
	await physics_frame
	await physics_frame

	player._pending_cooldown_refund = 0.0
	if not player._ability_primm():
		_fail("the wall-pass blink did not fire — is the landing spot blocked too?")
	if not is_equal_approx(player._pending_cooldown_refund, want_refund):
		_fail("blinking through a wall refunded %.3f s, wanted %.3f — the refund only "
				% [player._pending_cooldown_refund, want_refund]
				+ "sees a wall AT the landing spot, not one on the way")

	wall.queue_free()
	progression.free()
	player.queue_free()
	Sentinel.done("phase_echo_refunds_a_wall_pass")


func _check_panel_spends_and_releases_its_pause() -> void:
	"""
	The panel buys a rank, and it hands the pause back.

	Two failures this exists for, both of which leave no error anywhere: a press
	that renders but never reaches `Progression.spend()` (a tree you can look at
	and not use), and a `_paused_by_us` that is set but never cleared — which
	freezes the whole game behind a closed panel, with the key that would reopen it
	running on a node that is now the only thing still processing.

	Driven against the real `Control` with no `main.tscn`: the panel finds
	everything it needs by group, which is exactly what makes that possible.
	"""
	var progression := _make_progression()
	_grant_points(progression, 4)

	var panel: Control = Control.new()
	panel.set_script(load("res://scripts/skill_tree_ui.gd"))
	root.add_child(panel)
	await process_frame

	if root.get_tree().paused:
		_fail("the tree was already paused before the panel opened")
	panel._set_panel_open(true)
	# NEGATIVE CONTROL for the release below: it has to have been taken first, or
	# "not paused afterwards" is true of a panel that never pauses at all.
	if not root.get_tree().paused:
		_fail("opening the skill panel did not pause the tree")

	var hero: String = String(Progression.SKILL_TREES.keys()[0])
	panel._view_hero = hero
	var before: int = progression.rank_of(hero, "cd1")
	panel._on_node_pressed("cd1")
	if progression.rank_of(hero, "cd1") != before + 1:
		_fail("pressing a skill node bought %d ranks, wanted 1"
				% (progression.rank_of(hero, "cd1") - before))

	# ...and an unaffordable press changes nothing rather than erroring, which is
	# what lets the panel leave every node pressable.
	var spent_before: int = progression.spent_points
	panel._on_node_pressed("not_a_skill")
	if progression.spent_points != spent_before:
		_fail("pressing a node that does not exist charged a point")

	panel._set_panel_open(false)
	if root.get_tree().paused:
		_fail("closing the skill panel left the tree paused")

	panel.queue_free()
	progression.free()
	Sentinel.done("panel_spends_and_releases_its_pause")


# =============================================================================
# ACTIVE / EXOTIC SKILLS (bead godot-test1-20z.4)
# =============================================================================

class StubWeather extends Node:
	## The smallest thing `player_controller._weather_is_raining_here()` will talk
	## to: a node in the "weather" group carrying `is_raining_at`. The real
	## `weather_manager` would need a player, a camera and its own randomized
	## cloud field to decide, and could then answer either way.
	var raining: bool = true

	func is_raining_at(_pos: Vector3) -> bool:
		return raining


class StubCroc extends Node3D:
	## The smallest thing `player_controller._scare_crocodiles()` will talk to: a
	## Node3D in the "crocodile" group carrying `flee_from`. A REAL crocodile is
	## no use here — `piglet_crocodile_ai._ready()` needs a terrain, a player and a
	## `lod_active` the LOD manager owns, and its own early returns (boss, slept)
	## would then decide the answer instead of the radius under test.
	var flee_calls: int = 0
	var last_duration: float = 0.0

	func flee_from(_origin: Vector3, duration: float, _tracks_player: bool = true) -> void:
		flee_calls += 1
		last_duration = duration


func _check_dial_contract(player: Node, expect_ready: bool, expect_reason: String,
		where: String) -> void:
	"""
	THE ABILITY DIAL'S CONTRACT (bead godot-test1-tw6), asserted as a PAIR.

	`ability_hud.gd` paints three states — cooling, gated-but-charged, ready — out
	of two inputs that measure different things: `get_ability_cooldown_ratio()` is
	the cooldown alone, `is_ability_ready()` is ACTUAL availability, cooldown AND
	gates. That only works while the two cannot contradict each other, so this
	asserts the whole triple at once rather than any one number: ready must be
	EXACTLY "charge full and no gate". Either half alone passes on the bug this
	replaced — a green READY ring painted over a press that bounces, because
	`is_ability_ready()` only ever looked at the cooldown.
	"""
	var ready: bool = bool(player.is_ability_ready())
	var reason: String = String(player.get_ability_block_reason())
	var ratio: float = float(player.get_ability_cooldown_ratio())
	if reason != expect_reason:
		_fail("%s: the dial names the gate %s, wanted %s"
				% [where, reason.c_escape(), expect_reason.c_escape()])
	if ready != expect_ready:
		_fail("%s: is_ability_ready() = %s, wanted %s" % [where, ready, expect_ready])
	if ready != (ratio <= 0.0 and reason == ""):
		_fail("%s: is_ability_ready() = %s but ratio %.3f / gate %s say otherwise — "
				% [where, ready, ratio, reason.c_escape()]
				+ "the dial's two inputs disagree about availability")
	Sentinel.done("dial_contract")


func _spawn_stub_croc(at: Vector3) -> StubCroc:
	var croc := StubCroc.new()
	root.add_child(croc)
	croc.global_position = at
	croc.add_to_group("crocodile")
	return croc


func _check_active_skills_on_player() -> void:
	"""
	THE ACCEPTANCE MEASUREMENT for the three active/exotic nodes, all driven
	through the real player and the real trigger rather than by poking the state
	they set. Every assertion that something HAPPENED is paired with one that it
	does not happen unranked or out of range — the file's standing rule, and the
	sharp one here, because each of these three effects is silent when it fails:
	a burst that never fires, a gravity multiplier that scales the wrong way and a
	shockwave with no bound all leave no error anywhere.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	if packed == null:
		_fail("could not load %s" % PLAYER_SCENE)
		Sentinel.done("active_skills_on_player")
		return
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("calculate_current_speed"):
		_fail("player has no calculate_current_speed() — did the script fail to attach?")
		player.queue_free()
		Sentinel.done("active_skills_on_player")
		return
	player.is_wading = false

	var progression := _make_progression()
	# Comfortably more than this function spends (2 fleet + 2 adrenaline + 5
	# windman + 4 teibi + 3 phoboman = 16); `_spend_or_fail` says so if not.
	_grant_points(progression, 30)

	await _check_speed_burst(player, progression)
	_check_air_rush_arc(player, progression)
	await _check_crush_quake(player, progression)
	await _check_stink_is_bounded(player, progression)

	progression.free()
	player.queue_free()
	Sentinel.done("active_skills_on_player")


func _check_speed_burst(player: Node, progression: Progression) -> void:
	"""
	ADRENALINE. The trigger is a real `collect_coin()` streak, not an assignment to
	`speed_burst_timer`, because the whole design decision behind this node is that
	it has NO key of its own — if the streak hook is wrong the skill is unreachable
	and a state-poking check would never notice.
	"""
	var hero_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "windman":
			hero_index = index
	if hero_index < 0:
		_fail("no windman in CHARACTERS — the speed-burst measurement needs one")
		Sentinel.done("speed_burst")
		return
	player.set_active_character(hero_index)
	_spend_or_fail(progression, "windman", "fleet")
	_spend_or_fail(progression, "windman", "fleet")
	_spend_or_fail(progression, "windman", "adrenaline")
	_spend_or_fail(progression, "windman", "adrenaline")
	var want_duration: float = 2.0 * 1.5

	player.speed_burst_timer = 0.0
	player.coin_streak = 0
	player.is_ducking = false
	player.is_running = false
	var walk_calm: float = float(player.calculate_current_speed())
	player.is_running = true
	var run_calm: float = float(player.calculate_current_speed())

	# NINE coins are not a streak step, so nothing may fire. Without this the
	# check would also pass on a burst that started on every single pickup — i.e.
	# on a permanent +30%, which is the failure mode a cap exists to prevent.
	for _i in 9:
		player.collect_coin(1)
	if player.speed_burst_timer > 0.0:
		_fail("a speed burst started after 9 coins (%.2f s left) — it must take a full streak step"
				% player.speed_burst_timer)
	player.collect_coin(1)
	if not is_equal_approx(player.speed_burst_timer, want_duration):
		_fail("the 10th coin started a %.2f s burst, wanted %.2f"
				% [player.speed_burst_timer, want_duration])

	var run_burst: float = float(player.calculate_current_speed())
	player.is_running = false
	var walk_burst: float = float(player.calculate_current_speed())
	player.is_running = true

	# THE CATCHABLE-WALK CONTRACT, again and for the active too: a burst is a
	# run/duck effect and walking must be byte-identical through one.
	if walk_burst != walk_calm:
		_fail("a speed burst moved WALK speed from %.6f to %.6f — the catchable-walk contract forbids it"
				% [walk_calm, walk_burst])
	# ...with the negative control right beside it, or "walk unchanged" would also
	# pass on a burst that does nothing at all.
	if not is_equal_approx(run_burst, run_calm * (1.0 + Progression.BURST_RUN_BONUS)):
		_fail("a burst runs at %.3f, wanted %.3f (x%.2f on the passive %.3f)"
				% [run_burst, run_calm * (1.0 + Progression.BURST_RUN_BONUS),
					1.0 + Progression.BURST_RUN_BONUS, run_calm])
	# The composed worst case the constant's comment claims, pinned as arithmetic
	# rather than as prose: maxed passives (+20% cap) times the burst.
	var composed: float = Progression.RUN_SPEED_MULT_MAX * (1.0 + Progression.BURST_RUN_BONUS)
	if composed > 1.56 + 0.0001:
		_fail("passives + burst compose to x%.3f, past the documented x1.56" % composed)
	# ...and the one thing that must never be true however they compose: a
	# crocodile still cannot outrun a running player. (It can only have got safer
	# — bursts raise the number — but this is the lattice's own assertion.)
	if run_burst <= player.WADE_RUN_MIN_SPEED:
		_fail("a bursting run is %.3f, at or under the %.3f escape floor"
				% [run_burst, player.WADE_RUN_MIN_SPEED])

	# THE BURST ENDS. A timer that latched would be a permanent +30%.
	player._update_ability_timers(want_duration + 0.1)
	if player.speed_burst_timer > 0.0:
		_fail("the speed burst did not expire (%.2f s left after %.2f s)"
				% [player.speed_burst_timer, want_duration + 0.1])
	var run_after: float = float(player.calculate_current_speed())
	if not is_equal_approx(run_after, run_calm):
		_fail("run speed stayed at %.3f after the burst expired, wanted %.3f"
				% [run_after, run_calm])

	# NEGATIVE CONTROL: an UNRANKED hero crossing the same streak step gets
	# nothing. Measured with the Progression node present and points unspent, so
	# the only difference from the case above is the rank.
	var other_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "phoboman":
			other_index = index
	if other_index >= 0:
		player.set_active_character(other_index)
		player.speed_burst_timer = 0.0
		player.coin_streak = 0
		for _i in 10:
			player.collect_coin(1)
		if player.speed_burst_timer > 0.0:
			_fail("an unranked hero got a %.2f s speed burst — Adrenaline must be bought"
					% player.speed_burst_timer)
	player.is_running = false
	player.speed_burst_timer = 0.0
	Sentinel.done("speed_burst")


func _check_air_rush_arc(player: Node, progression: Progression) -> void:
	"""
	HIGHER FLIGHT — the lift on the body, and the arc the two nodes compose into.

	The arc is measured from the player's OWN constants rather than re-typed, so
	this is the `WINDMAN_GRAVITY_MULT_MIN` comment made runnable: retune gravity,
	the lift, the boost duration or either node's ranks and the numbers this
	prints move, which is exactly when a human should be looking at them again.
	"""
	var windman_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "windman":
			windman_index = index
	if windman_index < 0:
		_fail("no windman in CHARACTERS — the Air Rush arc measurement needs one")
		Sentinel.done("air_rush_arc")
		return
	player.set_active_character(windman_index)

	# The unranked arc first: it is the negative control for everything below.
	var base_peak: float = _air_rush_peak(player, 1.0, 1.0, 1.0)
	if not is_equal_approx(snappedf(base_peak, 0.01), 11.11):
		_fail("an unranked Air Rush peaks at %.2f m, wanted the documented 11.11" % base_peak)
	# THE BEAD'S PREMISE, PINNED AS FALSE ON PURPOSE. 20z.4 asked for a cap
	# keeping the Air Rush under a mountain massif minimum (8 m) on the belief
	# that the base arc was "well below" it. It never was. Recording it as an
	# assertion means a future retune that DOES bring it under 8 m shows up as a
	# failure here and gets a decision, instead of silently changing what the
	# epic's "fly higher routes through Air Rush" rule means.
	if base_peak <= 8.0:
		_fail("the base Air Rush now peaks at %.2f m, under the 8 m massif minimum — "
				% base_peak
				+ "that is a DESIGN CHANGE (Windman could always clear a short massif)")

	_spend_or_fail(progression, "windman", "gale")
	_spend_or_fail(progression, "windman", "gale")
	_spend_or_fail(progression, "windman", "updraft")
	_spend_or_fail(progression, "windman", "updraft")
	_spend_or_fail(progression, "windman", "soar")
	_spend_or_fail(progression, "windman", "soar")

	# The lift, measured on the BODY through the real ability.
	player.windman_boost_timer = 0.0
	player.velocity = Vector3.ZERO
	player._ability_windman()
	var lift: float = float(player.velocity.y)
	player.windman_boost_timer = 0.0
	player.velocity = Vector3.ZERO
	if not is_equal_approx(lift, player.WINDMAN_LIFT * 1.40):
		_fail("a fully-ranked Air Rush launched at %.3f, wanted %.3f (+40%%)"
				% [lift, player.WINDMAN_LIFT * 1.40])

	# The gravity multiplier the player actually reads at the gravity step.
	var grav_mult: float = float(player._skill_mult("windman_gravity"))
	if not is_equal_approx(grav_mult, Progression.WINDMAN_GRAVITY_MULT_MIN):
		_fail("a fully-ranked Windman glides at x%.3f gravity, wanted x%.3f"
				% [grav_mult, Progression.WINDMAN_GRAVITY_MULT_MIN])

	var peak: float = _air_rush_peak(player, 1.40, grav_mult, 1.30)
	if not is_equal_approx(snappedf(peak, 0.01), 26.25):
		_fail("a fully-ranked Air Rush peaks at %.2f m, wanted the documented 26.25" % peak)

	# NEGATIVE CONTROL for the whole branch: another hero reads neither effect, so
	# `_skill_mult` is answering per-hero rather than globally.
	var teibi_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "teibi":
			teibi_index = index
	if teibi_index >= 0:
		player.set_active_character(teibi_index)
		if not is_equal_approx(float(player._skill_mult("windman_gravity")), 1.0):
			_fail("teibi reads a windman_gravity multiplier of %.3f, wanted 1.0"
					% player._skill_mult("windman_gravity"))
	Sentinel.done("air_rush_arc")


func _air_rush_peak(player: Node, lift_mult: float, gravity_mult: float, boost_mult: float) -> float:
	"""
	Peak height of one Air Rush, in metres, from the player's own constants.

	Two regimes and the boundary between them matters: if the apex arrives BEFORE
	the boost runs out the answer is the ordinary v²/2g; if it does not, the wings
	cut out mid-climb and the body coasts the rest of the way up under FULL
	gravity. Fully ranked it is the second case, which is why the arc cannot be
	read off the apex formula alone.
	"""
	var lift: float = float(player.WINDMAN_LIFT) * lift_mult
	var soft: float = float(player.gravity) * float(player.WINDMAN_GRAVITY_FACTOR) * gravity_mult
	var boost: float = float(player.WINDMAN_BOOST_DURATION) * boost_mult
	var time_to_apex: float = lift / soft
	if time_to_apex <= boost:
		return lift * lift / (2.0 * soft)
	var height_at_cutout: float = lift * boost - 0.5 * soft * boost * boost
	var speed_at_cutout: float = lift - soft * boost
	return height_at_cutout + speed_at_cutout * speed_at_cutout / (2.0 * float(player.gravity))


func _check_crush_quake(player: Node, progression: Progression) -> void:
	"""
	CRUSH QUAKE. Two stub crocodiles — one inside the 6 m reach, one outside — so
	"the near one fled" and "the far one did not" are asserted together; either
	alone passes on a broken build (an unbounded sweep, or a quake that never
	fires).
	"""
	var teibi_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "teibi":
			teibi_index = index
	if teibi_index < 0:
		_fail("no teibi in CHARACTERS — the Crush Quake measurement needs one")
		Sentinel.done("crush_quake")
		return
	player.set_active_character(teibi_index)
	player.global_position = Vector3.ZERO
	var near := _spawn_stub_croc(Vector3(3.0, 0.0, 0.0))
	var far := _spawn_stub_croc(Vector3(12.0, 0.0, 0.0))
	await physics_frame

	# NEGATIVE CONTROL FIRST: an unranked Teibi turning giant scares nobody.
	player._revert_teibi_to_normal()
	player._ability_teibi()  # normal → small
	player._ability_teibi()  # small → giant
	if near.flee_calls != 0:
		_fail("an unranked Teibi's giant form scared a crocodile %d time(s)" % near.flee_calls)
	player._revert_teibi_to_normal()

	_spend_or_fail(progression, "teibi", "hold")
	_spend_or_fail(progression, "teibi", "scurry")
	_spend_or_fail(progression, "teibi", "quake")

	# SECOND NEGATIVE CONTROL: turning SMALL is not a quake. Without it, a quake
	# fired on every resize press would pass the positive assertion below.
	player._ability_teibi()  # normal → small
	if near.flee_calls != 0:
		_fail("Teibi's SMALL form fired the quake %d time(s) — it is a giant-form effect"
				% near.flee_calls)

	player._ability_teibi()  # small → giant
	if near.flee_calls != 1:
		_fail("a ranked Teibi turning giant fired %d quake(s) on a crocodile 3 m away, wanted 1"
				% near.flee_calls)
	if not is_equal_approx(near.last_duration, player.TEIBI_QUAKE_FLEE_DURATION):
		_fail("the quake made a crocodile flee for %.2f s, wanted %.2f"
				% [near.last_duration, player.TEIBI_QUAKE_FLEE_DURATION])
	if far.flee_calls != 0:
		_fail("the quake reached a crocodile 12 m away (%d call(s)) — its radius is %.1f m"
				% [far.flee_calls, progression.skill_bonus("teibi", "teibi_quake")])

	player._revert_teibi_to_normal()
	near.queue_free()
	far.queue_free()
	await physics_frame
	Sentinel.done("crush_quake")


func _check_stink_is_bounded(player: Node, progression: Progression) -> void:
	"""
	THE STINK WAVE'S NEW BOUND, and the node it makes live.

	Through bead 20z.3 `_ability_phoboman()` swept the whole "crocodile" group with
	no distance test, so `phoboman_radius` bought a wider picture and nothing else
	(the architect's note on 20z.4). The bound is the balance change that decision
	settled on; this is what stops it silently reverting to unbounded, and what
	proves Billowing Cloud now buys reach.
	"""
	var phobo_index: int = -1
	for index in player.CHARACTERS.size():
		if String(player.CHARACTERS[index]["name"]) == "phoboman":
			phobo_index = index
	if phobo_index < 0:
		_fail("no phoboman in CHARACTERS — the stink-radius measurement needs one")
		Sentinel.done("stink_is_bounded")
		return
	player.set_active_character(phobo_index)
	player.global_position = Vector3.ZERO

	var inside := _spawn_stub_croc(Vector3(10.0, 0.0, 0.0))
	# Between the unranked 22 m and the Billowing Cloud 27.5 m, so it is the ONE
	# crocodile whose answer changes when the node is bought.
	var edge := _spawn_stub_croc(Vector3(25.0, 0.0, 0.0))
	var outside := _spawn_stub_croc(Vector3(60.0, 0.0, 0.0))
	await physics_frame

	player._ability_phoboman()
	if inside.flee_calls != 1:
		_fail("an unranked Stink Wave scared a crocodile 10 m away %d time(s), wanted 1"
				% inside.flee_calls)
	if edge.flee_calls != 0:
		_fail("an unranked Stink Wave reached 25 m — PHOBOMAN_FLEE_RADIUS is %.1f m"
				% player.PHOBOMAN_FLEE_RADIUS)
	if outside.flee_calls != 0:
		_fail("the Stink Wave reached a crocodile 60 m away — it is no longer bounded")
	if not is_equal_approx(inside.last_duration, player.PHOBOMAN_FLEE_DURATION):
		_fail("an unranked Stink Wave fled a crocodile for %.2f s, wanted %.2f"
				% [inside.last_duration, player.PHOBOMAN_FLEE_DURATION])

	_spend_or_fail(progression, "phoboman", "reek")
	_spend_or_fail(progression, "phoboman", "billow")
	player._ability_phoboman()
	# THE POINT OF THE WHOLE CHANGE: the node moved a crocodile from out of reach
	# to in reach. Before the bound existed this assertion was unwritable — every
	# crocodile in the world already fled at rank 0.
	if edge.flee_calls != 1:
		_fail("Billowing Cloud did not extend the stink to 25 m (%d call(s)); reach is %.1f m"
				% [edge.flee_calls, player.PHOBOMAN_FLEE_RADIUS
					* progression.skill_mult("phoboman", "phoboman_radius")])
	if outside.flee_calls != 0:
		_fail("Billowing Cloud reached 60 m — the node scales the bound, it does not remove it")
	if not is_equal_approx(inside.last_duration, player.PHOBOMAN_FLEE_DURATION * 1.20):
		_fail("Lingering Reek fled a crocodile for %.2f s, wanted %.2f"
				% [inside.last_duration, player.PHOBOMAN_FLEE_DURATION * 1.20])

	inside.queue_free()
	edge.queue_free()
	outside.queue_free()
	await physics_frame
	Sentinel.done("stink_is_bounded")


func _run() -> void:
	# A node added from `_initialize()` gets its `_ready()` DEFERRED, so nothing
	# built before the first frame has run its own setup yet. One frame here makes
	# every later `add_child()` ready synchronously.
	await process_frame
	# Before anything can build a BestRunStore — the relaunch check below, and the
	# player scene, which mints a profile id into whatever path is set here.
	_isolate_local_store()
	_check_curve()
	_check_points_and_levelling()
	_check_store_load_is_monotone()
	_check_tree_data()
	_check_spending()
	_check_caps()
	_check_ranks_merge_is_monotone()
	_check_ranks_survive_a_relaunch()
	await _check_streak_does_not_inflate_lifetime()
	await _check_skill_effects_on_player()
	await _check_active_skills_on_player()
	await _check_phase_echo_refunds_a_wall_pass()
	await _check_panel_spends_and_releases_its_pause()
	_report()
