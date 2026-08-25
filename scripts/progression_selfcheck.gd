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
## THE ONE THING THAT STILL TOUCHES `user://best_run.cfg` IS THE PLAYER SCENE, and
## it is backed up and restored around the run. `player_controller._ready()`
## unconditionally builds its own `BestRunStore` and calls `fetch()`, which on a
## machine with no profile MINTS AND WRITES a player id — so booting the real
## player (which the streak check has to, since measuring the real
## `collect_coin()` is its whole point) leaves a file behind unless something puts
## it back. `_backup_local` / `_restore_local` are `best_run_e2e.gd`'s, verbatim,
## for the same reason.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## `coin.gd` has no `class_name`, so it is preloaded by path — the same line
## `scripts/mp_selfcheck.gd` carries, for the same reason.
const Coin: GDScript = preload("res://scripts/coin.gd")

var _failures: Array[String] = []

## The pre-run contents of `user://best_run.cfg`, restored on the way out. `null`
## when there was no file (the fresh-machine case), which `_restore_local`
## deletes for.
var _saved_cfg: Variant = null


func _backup_local() -> void:
	if FileAccess.file_exists(BestRunStore.CONFIG_PATH):
		_saved_cfg = FileAccess.get_file_as_bytes(BestRunStore.CONFIG_PATH)


func _restore_local() -> void:
	if _saved_cfg == null:
		DirAccess.remove_absolute(BestRunStore.CONFIG_PATH)
		return
	var f := FileAccess.open(BestRunStore.CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_buffer(_saved_cfg as PackedByteArray)
		f.close()


func _initialize() -> void:
	# The measuring half runs as its own coroutine: `_initialize()` cannot await,
	# and a verdict printed from here would be a frame-0 vacuous pass — the exact
	# failure the sibling self-checks in this repo document.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	_restore_local()
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
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
		return
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("collect_coin"):
		_fail("player has no collect_coin() — did the script fail to attach? "
				+ "(a fresh clone needs `godot --headless --path . --import` first)")
		player.queue_free()
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

	progression.free()


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
		return
	var player: Node = packed.instantiate()
	root.add_child(player)
	await physics_frame
	if not player.has_method("calculate_current_speed"):
		_fail("player has no calculate_current_speed() — did the script fail to attach?")
		player.queue_free()
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
	# Comfortably more points than this function spends (8 movement + 4 cooldown +
	# 3 Air Rush = 15). A budget that runs out mid-way makes every later purchase
	# a silent no-op and the measurement it feeds a silent pass, so `_spend_or_fail`
	# below says so instead.
	var progression := _make_progression()
	_grant_points(progression, 24)
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
		player.try_activate_ability()
		var unskilled: float = float(player.ability_cooldowns[teibi_index])
		var unskilled_ratio: float = float(player.get_ability_cooldown_ratio())
		player._revert_teibi_to_normal()
		if not is_equal_approx(unskilled, base_cooldown):
			_fail("an unranked teibi charged %.3f s of cooldown, wanted %.3f"
					% [unskilled, base_cooldown])

		for _i in 3:
			_spend_or_fail(progression, "teibi", "cd1")
		_spend_or_fail(progression, "teibi", "cd2")

		player.ability_cooldowns[teibi_index] = 0.0
		player.try_activate_ability()
		var skilled: float = float(player.ability_cooldowns[teibi_index])
		var skilled_ratio: float = float(player.get_ability_cooldown_ratio())
		player._revert_teibi_to_normal()
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
		player.windman_boost_timer = 0.0
		player.velocity = Vector3.ZERO

	progression.free()
	player.queue_free()


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
	POSTs nothing. `user://best_run.cfg` is already backed up and restored around
	this whole file (see the header), which is what makes writing to it safe.
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


func _run() -> void:
	# A node added from `_initialize()` gets its `_ready()` DEFERRED, so nothing
	# built before the first frame has run its own setup yet. One frame here makes
	# every later `add_child()` ready synchronously.
	await process_frame
	# Before anything can boot the player scene and mint a profile id into it.
	_backup_local()
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
	await _check_phase_echo_refunds_a_wall_pass()
	await _check_panel_spends_and_releases_its_pause()
	_report()
