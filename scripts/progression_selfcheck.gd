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
## throughout, so this never touches the developer's `user://best_run.cfg` and
## never POSTs to the deployed lobby; the store round trip (local layer AND server)
## is driven end to end by `scripts/best_run_e2e.gd` against the local lobby
## `scripts/mp_e2e.sh` already starts.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const PLAYER_SCENE: String = "res://scenes/player.tscn"

## `coin.gd` has no `class_name`, so it is preloaded by path — the same line
## `scripts/mp_selfcheck.gd` carries, for the same reason.
const Coin: GDScript = preload("res://scripts/coin.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# The measuring half runs as its own coroutine: `_initialize()` cannot await,
	# and a verdict printed from here would be a frame-0 vacuous pass — the exact
	# failure the sibling self-checks in this repo document.
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
	THE HOOK, measured through the real `player_controller.collect_coin()`.

	Lifetime counts PICKUPS at their base worth; the streak multiplies the SCORE.
	Wiring the hook to the multiplied value is the easy mistake — the line right
	above it does exactly that for `own_coins` — and it inflates every player's
	level by up to 5x with no error anywhere.
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

	progression.free()
	player.queue_free()


func _run() -> void:
	# A node added from `_initialize()` gets its `_ready()` DEFERRED, so nothing
	# built before the first frame has run its own setup yet. One frame here makes
	# every later `add_child()` ready synchronously.
	await process_frame
	_check_curve()
	_check_points_and_levelling()
	_check_store_load_is_monotone()
	await _check_streak_does_not_inflate_lifetime()
	_report()
