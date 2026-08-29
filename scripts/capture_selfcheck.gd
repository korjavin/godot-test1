extends SceneTree
## Headless self-check: **SYSTEMIC CAPTURE TAKES THE HERO, AND ONLY EVER THE HERO.**
##
##   godot --headless --path . --script res://scripts/capture_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the shape
## every check in this project uses. Epic godot-test1-3iy, phase 9.
##
## ============================================================================
## WHY THIS EXISTS
## ============================================================================
##
## Capture is the first mechanic in the game that takes something a coin cannot buy
## back, and it fires on a COLLISION — the least observable event there is. Three
## of its failure modes are silent:
##
##   * it arms EARLY, and a hunter takes a hero before the beat that teaches the
##     rule has played (the mechanic reads as a bug, and the beat then teaches
##     nothing);
##   * it takes the WRONG contact — a crocodile bite, a boss bolt, the tower's
##     rotor bar — and the roster drains for reasons the player cannot see;
##   * it takes a hero during the post-respawn blink, so one grab strips the whole
##     roster a frame at a time and the run ends on a screen nobody can account for.
##
## None of those show up in a screenshot and every one of them is one `if` away. So
## the gates are measured here, through the REAL `player_controller`, against the
## REAL species rows — and the auto-switch is measured for the landmine it carries:
## a capture that swapped the body without going through `set_active_character()`
## would hand the next hero a live Air Rush.
##
## ============================================================================
## WHAT IT GUARDS, check by check
## ============================================================================
##
##   1. **THE ARMING GATE.** Pre-beat, an earned hunter grab costs the ordinary
##      predator arithmetic and no hero. Post-beat it takes the active one. The
##      beat is `TowerInterior.RESCUE_DONE` in the stored tower set, which is what
##      the authored rescue writes.
##   2. **ATTRIBUTION.** Post-beat, a predator that is not on the hunt arm, a body
##      with no row at all, and a contact that names no attacker take nobody. Keyed
##      on the row's `behavior`, so a second retrieval unit is covered by its row.
##   3. **INVULNERABILITY COVERS THE HERO TOO.** A grab inside any of the four
##      invulnerable states costs nothing — `hit_by_crocodile()`'s early return is
##      the one place that rule lives and the capture must sit under it.
##   4. **THE CYCLE LOSES HIM, AND THE SWITCH IS CLEAN.** E never lands on a
##      captive, E is a refusal when one hero is left, and the body that walks out
##      of the grab carries no transient ability state — the bead's landmine.
##   5. **LIBERATION RESTORES THE INDEX.** `hero_freed()` is the cell block's seam
##      and it must put the hero straight back in the cycle, idempotently.
##   6. **THE LAST FREE HERO ENDS THE RUN**, with hearts still in hand — game over
##      is "nobody left to play", not only "no lives left".
##   7. **THE SET STAYS OUT OF THE MONOTONE STORE.** A capture must not write the
##      profile's tower set: that set is a UNION that can only grow, and a captive
##      folded into it could never be freed.
##   8. **A TOWER STREAMED IN LATER HOLDS HIM.** The field takes heroes where the
##      building is not loaded, so the interior re-seeds its mirror from the player
##      on build — and walking into the cell frees him all the way back into the
##      E-cycle.
##
## ============================================================================
## LANDMINES
## ============================================================================
##
## THE STORE IS REDIRECTED FIRST, before any player exists. `player_controller`
## builds a `BestRunStore` in `_ready()`, and the arming gate READS the tower set
## off disk — so a run against the real `user://best_run.cfg` would both read the
## player's own save and write to it. `LOCAL_STORE_PATH` is this file's throwaway,
## pointed at in `_initialize()` and deleted again at the end.
##
## THE CAUGHT FREEZE IS NOT WAITED OUT. `_on_caught_finished()` is called directly
## rather than ticking 0.55 s of physics per grab: the freeze is a presentation
## delay, the decision is the thing being measured, and a dozen grabs would
## otherwise make this the slowest check in the suite for no assertion at all.

const PLAYER_SCENE: String = "res://scenes/player.tscn"
const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const CROC_SCRIPT: String = "res://scripts/piglet_crocodile_ai.gd"

## This check's own profile. Never the real one — see the landmine above.
const LOCAL_STORE_PATH: String = "user://capture_selfcheck_best_run.cfg"

var _failures: Array[String] = []

## The attacker stubs, made once and freed in `_report()`. Each is an orphan Node
## (never added to the tree — `_is_hunter_grab()` only ever reads its `spec`), so
## nothing reclaims them but this file.
var _stubs: Dictionary = {}


## A body that names a `spec` row, which is all `_is_hunter_grab()` reads of an
## attacker.
##
## THE ROW IS THE REAL ONE, pulled out of `SPECIES` by name rather than written out
## here: the whole point of keying on `behavior` is that the table decides, so a
## check that typed `{"behavior": "hunt"}` into a literal would still pass on the
## day the arm was renamed and capture had silently stopped firing.
class AttackerStub extends Node:
	var spec: Dictionary = {}


## A stand-in for the multiplayer manager, in group "mp", answering exactly the
## one method the roster reads.
##
## `my_character_indices()` returns `null` for "all of them" — offline, no room, or
## holding no hero yet — and never an empty array, which is the real manager's
## contract verbatim (`mp_manager.gd`: "locking E against an empty set would be a
## worse answer than solo behaviour"). Reproducing that here is the point: check 9
## exists to prove the capture path respects a HAND, and a stub that could answer
## `[]` would be testing a state the lobby never produces.
class RoomStub extends Node:
	var hand: Array[int] = []

	func my_character_indices() -> Variant:
		return null if hand.is_empty() else hand


func _initialize() -> void:
	BestRunStore.config_path = LOCAL_STORE_PATH
	_fresh_store()
	# ONE FRAME BEFORE ANYTHING: a node added to `root` from inside `_initialize()`
	# is not `is_inside_tree()` until the first frame.
	await process_frame
	await _run()


func _run() -> void:
	await _check_the_arming_gate()
	await _check_only_a_hunter_takes_a_hero()
	await _check_invulnerability_covers_the_hero_too()
	await _check_the_cycle_loses_him_and_the_switch_is_clean()
	await _check_liberation_restores_the_index()
	await _check_the_last_free_hero_ends_the_run()
	await _check_the_set_stays_out_of_the_monotone_store()
	await _check_a_tower_streamed_in_later_holds_him()
	await _check_capture_respects_the_rooms_hand()
	_report()


# ============================================================================
# 1. THE ARMING GATE
# ============================================================================

func _check_the_arming_gate() -> void:
	"""
	Owner-ruled sequencing: capture arms only after the authored Primm beat.

	BOTH HALVES, because only the pair is a gate. "Nothing happened pre-beat" is
	also true of a capture path wired to nothing at all, and "the hero was taken"
	is also true of one with no gate on it.
	"""
	_fresh_store()
	var player := await _make_player()
	var before: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if player.captive_heroes.size() != 0:
		_fail(("PRE-BEAT: a hunter grab took %s before the authored rescue — capture must "
			+ "arm on TowerInterior.RESCUE_DONE, because the beat is where the rule is "
			+ "taught") % str(player.captive_heroes.keys()))
	if player.hero_name() != before:
		_fail("PRE-BEAT: the grab switched the hero away from %s" % before)
	_clear(player)

	# ...and now the beat lands. This is the id the authored rescue writes through
	# `TowerShell.mark_opened()`, so the check arms capture exactly as the game does.
	_beat_done()
	player = await _make_player()
	before = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if not player.is_hero_captive(before):
		_fail(("POST-BEAT: an earned hunter grab left %s free — the active hero must join "
			+ "the captive set") % before)
	if player.hero_name() == before:
		_fail("POST-BEAT: the grab did not auto-switch off the captured hero %s" % before)
	_clear(player)


# ============================================================================
# 2. ATTRIBUTION — two stakes, never both, and never the wrong one
# ============================================================================

func _check_only_a_hunter_takes_a_hero() -> void:
	"""
	Post-beat, every contact that is NOT a retrieval unit costs the predator
	arithmetic and nothing more.

	Three shapes, because they fail differently: an ordinary predator row (the
	crocodile), a body with no `spec` property at all (a boss projectile, the
	tower's rotor bar), and the plain no-argument call every caller in the codebase
	makes today.
	"""
	_beat_done()
	for label: String in ["crocodile", "no spec", "no attacker"]:
		var player := await _make_player()
		var coins_before: int = player.coins_collected
		match label:
			"crocodile":
				player.hit_by_crocodile(_attacker_row("crocodile"))
			"no spec":
				var bare := Node.new()
				player.hit_by_crocodile(bare)
				bare.free()
			_:
				player.hit_by_crocodile()
		if player.captive_heroes.size() != 0:
			_fail(("a '%s' contact took %s — only a predator on the hunt arm takes a hero")
				% [label, str(player.captive_heroes.keys())])
		if player.coins_collected != coins_before:
			_fail("a '%s' contact moved the coin count, which no contact in this game does"
				% label)
		_clear(player)


# ============================================================================
# 3. INVULNERABILITY
# ============================================================================

func _check_invulnerability_covers_the_hero_too() -> void:
	"""
	A grab the player is invulnerable to costs no hero.

	THE FAILURE THIS PREVENTS IS THE WHOLE ROSTER. `hit_by_crocodile()`'s early
	return is the one place invulnerability lives, and the blink window after a
	respawn is a second or more of overlap with whatever just bit you — a capture
	placed ABOVE that return would strip four heroes in four frames.

	All four invulnerable states, because they are four separate flags and one
	return covers all of them; a capture moved above it fails on every one.
	"""
	_beat_done()
	for state: String in ["blinking", "caught", "respawning", "game over"]:
		var player := await _make_player()
		match state:
			"blinking":
				player.respawn_blink_timer = 1.0
			"caught":
				player.is_caught = true
			"respawning":
				player.is_respawning = true
			_:
				player.is_game_over = true
		var hero: String = player.hero_name()
		player.hit_by_crocodile(_hunter())
		if player.is_hero_captive(hero):
			_fail("a grab while '%s' took %s — an ignored bite must cost nothing"
				% [state, hero])
		_clear(player)


# ============================================================================
# 4. THE CYCLE, AND THE LANDMINE
# ============================================================================

func _check_the_cycle_loses_him_and_the_switch_is_clean() -> void:
	"""
	What E does after a capture, and what state the new body is in.

	THE LANDMINE (bead godot-test1-3iy.9): transient ability state already clears
	on a character switch, and the capture-time auto-switch has to go through that
	same path. Measured by arming Air Rush and a sidestep and asserting both are
	gone on the other side of the grab — which is what makes the assertion sharp,
	because `switch_to_next_character()` REFUSES a press while Air Rush is running,
	so a capture routed through the cycle would not switch at all.
	"""
	_beat_done()
	var player := await _make_player()

	# Air Rush running and the body mid-sidestep on the frame the grab lands.
	player.windman_boost_timer = 5.0
	player.is_stepping = true
	var taken: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if player.windman_boost_timer != 0.0 or player.is_stepping:
		_fail(("the auto-switch left transient ability state alive (boost %.2f, stepping %s) "
			+ "— capture must switch through set_active_character(), which is where "
			+ "_reset_ability_states() lives")
			% [player.windman_boost_timer, str(player.is_stepping)])
	if player.is_hero_captive(player.hero_name()):
		_fail("the auto-switch landed on %s, who is captive" % player.hero_name())
	if player.hero_name() == taken:
		_fail("the auto-switch did not move off %s" % taken)

	# ...and E now walks the free heroes and only the free heroes. Four presses is
	# more than a full lap of the three that are left, so a cycle that COULD reach
	# the captive would have to.
	for press: int in 4:
		player.switch_to_next_character()
		if player.is_hero_captive(player.hero_name()):
			_fail("E landed on the captive %s — availability is hand INTERSECT free"
				% player.hero_name())
			break
	_clear(player)

	# One free hero left: E is a refusal, not a wrap onto a captive. The same shape
	# the lobby's single-hero hand already takes, for the same reason.
	player = await _make_player()
	var alone: String = player.hero_name()
	for hero: String in TowerGraph.HEROES:
		if hero != alone:
			player.captive_heroes[hero] = true
	player.switch_to_next_character()
	if player.hero_name() != alone:
		_fail("with one free hero E moved off %s onto %s" % [alone, player.hero_name()])
	if player.free_hero_count() != 1:
		_fail("free_hero_count() says %d with three heroes held" % player.free_hero_count())
	_clear(player)


# ============================================================================
# 5. LIBERATION
# ============================================================================

func _check_liberation_restores_the_index() -> void:
	"""
	`hero_freed()` — the cell block's seam — puts a hero straight back in the cycle.

	CAPTURE MUST NEVER SHIP WITHOUT THE WAY BACK, which is why this bead depends on
	the cell-block bead. Idempotence is asserted too: the tower re-drives this seam
	from more than one place, so freeing somebody who is not held has to be a no-op
	rather than a crash or a phantom entry.
	"""
	_beat_done()
	var player := await _make_player()
	var taken: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if not player.is_hero_captive(taken):
		_fail("liberation: nobody was captured, so there was nothing to free")
		_clear(player)
		return
	player.hero_freed(taken)
	if player.is_hero_captive(taken):
		_fail("hero_freed(%s) left him captive" % taken)
	player.hero_freed(taken)
	player.hero_freed("nobody_by_that_name")
	if player.free_hero_count() != TowerGraph.HEROES.size():
		_fail("a repeated / unknown hero_freed() disturbed the roster (%d free, expected %d)"
			% [player.free_hero_count(), TowerGraph.HEROES.size()])
	_clear(player)


# ============================================================================
# 6. THE GAME-OVER TRIGGER
# ============================================================================

func _check_the_last_free_hero_ends_the_run() -> void:
	"""
	An empty free-hero set ends the run WITH HEARTS STILL IN HAND.

	The hearts are the point. Game over on lives already existed, so a check that
	drained the roster and the hearts together would pass on a build with no
	capture trigger at all; here the player keeps most of its hearts and the run
	ends anyway, which only the free-set clause can do.

	And the negative control on the same path — three of four heroes held, hearts
	in hand — must NOT end the run, or "ends the run" would only mean "ends".
	"""
	_beat_done()
	var player := await _make_player()
	var last_one: String = player.hero_name()
	for hero: String in TowerGraph.HEROES:
		if hero != last_one:
			player.captive_heroes[hero] = true
	player.hit_by_crocodile(_hunter())
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.lives <= 0:
		_fail("the roster ran out but so did the hearts — this check would prove nothing")
	if not player.is_game_over:
		_fail("the last free hero was captured with %d hearts left and the run did not end"
			% player.lives)
	_clear(player)

	# Negative control: one hero left free, and the run goes on.
	player = await _make_player()
	var free_one: String = player.hero_name()
	for hero: String in TowerGraph.HEROES:
		if hero != free_one:
			player.captive_heroes[hero] = true
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.is_game_over:
		_fail("the run ended with %s still free and %d hearts left"
			% [free_one, player.lives])
	_clear(player)


# ============================================================================
# 7. WHERE THE SET IS NOT STORED
# ============================================================================

func _check_the_set_stays_out_of_the_monotone_store() -> void:
	"""
	A capture writes nothing to the profile's tower set.

	THE CAPTIVE SET IS NON-MONOTONE — captures add, liberations remove — and
	`best_run_store.gd` is a store whose every field is monotone on purpose, merged
	with a union or a max so a late reply or a retry can never lower a record. A
	captive folded in there could never be freed: the union has no verb for
	removal, and the hero would come back held on every relaunch, forever. So the
	set lives in plain world state, and the store must be untouched across a grab.
	"""
	# FROM A KNOWN STORE, and that is not tidiness. A union only ever GROWS, so a
	# before/after diff taken over a store some earlier check already dirtied would
	# be blind to a second write of an id that is already in it — which is exactly
	# what a per-hero capture id would be on the second grab of the same hero. So
	# the profile is emptied, re-armed, and the whole stored set is compared to the
	# one id the beat is allowed to have put there.
	_fresh_store()
	_beat_done()
	var player := await _make_player()
	var before := BestRunStore.tower_opened_ids()
	if before != ([TowerInterior.RESCUE_DONE] as Array[String]):
		_fail("store baseline is %s — expected the beat's id and nothing else" % str(before))
	var taken: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if not player.is_hero_captive(taken):
		_fail("store: nobody was captured, so nothing was measured")
	# Both directions of the non-monotone verb, because a union has no removal and
	# the liberation is the half that would need one.
	player.hero_freed(taken)
	var after := BestRunStore.tower_opened_ids()
	if after != before:
		_fail(("a capture/liberation changed the monotone tower set from %s to %s — the "
			+ "captive set is non-monotone and must never ride a union merge")
			% [str(before), str(after)])
	_clear(player)


# ============================================================================
# 8. THE MIRROR
# ============================================================================

func _check_a_tower_streamed_in_later_holds_him() -> void:
	"""
	A hero taken in the field has a cell waiting when the building streams in.

	THE ONE THAT KEEPS THE SOFTLOCK AUDIT HONEST. `tower_selfcheck` proves every
	non-empty free-hero subset can reach a cell; that proof is worth nothing if the
	cell the player walks to does not know it is holding anybody, because
	`TowerInterior._liberate()` early-returns on a hero it has no record of. Grabs
	happen kilometres from the tower, so the player owns the set and the interior
	re-seeds from it on build — and this walks the whole loop: capture in the
	field, build the tower, walk into the cell, hero back in the cycle.
	"""
	_beat_done()
	var player := await _make_player()
	var taken: String = player.hero_name()
	player.hit_by_crocodile(_hunter())

	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("mirror: the tower has no TowerInterior child")
		shell.queue_free()
		_clear(player)
		return
	if not interior.is_captive(taken):
		_fail(("a tower built AFTER a field capture does not hold %s (it holds %s) — the "
			+ "interior must re-seed its mirror from the player, or his cell can never be "
			+ "opened") % [taken, str(interior.captives())])
	# The authored captive is the TOWER's own staging, not a hero the field took off
	# you, so after the beat he is nobody's captive. Asserted so the re-seed can
	# never quietly become "mirror the whole cell block back onto the roster".
	if taken != TowerInterior.AUTHORED_CAPTIVE \
			and player.is_hero_captive(TowerInterior.AUTHORED_CAPTIVE):
		_fail("the tower's authored staging leaked into the player's captive set")

	# Walk in. Any hero frees any cell, so the body that arrives is whoever we are.
	interior.call("_liberate", taken)
	if player.is_hero_captive(taken):
		_fail("walking into %s's cell did not put him back in the player's cycle" % taken)
	if interior.is_captive(taken):
		_fail("the cell still reads occupied after the liberation")

	# THE OTHER DIRECTION, on the same standing tower: a grab that lands while the
	# building IS streamed in has to push into it, because the re-seed above only
	# runs at build time and there will be no second build. Getting caught on the
	# HQ grounds is the likeliest place in the world to be caught at all, so this
	# is the common case and not the exotic one.
	# The caught freeze from the first grab is still on: end it the way
	# `_physics_process` does, or the second grab is correctly ignored as a bite
	# during invulnerability (which check 3 is the one that measures).
	player.is_caught = false
	var second: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if not player.is_hero_captive(second):
		_fail("mirror: the second grab took nobody")
	elif not interior.is_captive(second):
		_fail(("a grab with the tower ALREADY standing left %s out of the cell block (it "
			+ "holds %s) — the capture must push through set_captive()")
			% [second, str(interior.captives())])
	shell.queue_free()
	_clear(player)
	await process_frame


# ============================================================================
# 9. THE ROOM'S HAND
# ============================================================================

func _check_capture_respects_the_rooms_hand() -> void:
	"""
	In a room, capture is bounded by the heroes the LOBBY assigned this peer.

	MP capture proper is its own bead; what is measured here is that this bead does
	not BREAK the assignment that already ships. Two ways it could, and they are
	the same mistake at two sites:

	  * the auto-switch reaching past the hand and stepping this peer into a
	    teammate's hero — the lobby is the source of truth for hero assignment and
	    nothing may be decided locally;
	  * the end-of-run test asking whether any hero anywhere is free, so a peer
	    whose only assigned hero has just been taken respawns as somebody else's.

	Both are why `available_character_indices()` exists rather than three copies of
	one intersection. The negative control — a two-hero hand — proves the switch
	still moves when there IS somewhere to go, so "it did not step out of the hand"
	cannot be satisfied by a switch that never happens.
	"""
	_beat_done()

	# (a) a one-hero hand, and that hero is taken.
	var room := RoomStub.new()
	room.add_to_group("mp")
	root.add_child(room)
	var player := await _make_player()
	var mine: int = TowerGraph.HEROES.find("primm")
	room.hand = [mine] as Array[int]
	player.set_active_character(mine)
	var taken: String = player.hero_name()
	player.hit_by_crocodile(_hunter())
	if player.hero_name() != taken:
		_fail(("the capture stepped this peer from %s into %s, which the lobby assigned to "
			+ "somebody else — the auto-switch must stay inside the hand")
			% [taken, player.hero_name()])
	if not player.available_character_indices().is_empty():
		_fail("a peer whose only assigned hero was taken still reports %s available"
			% str(player.available_character_indices()))
	if player.free_character_indices().size() != TowerGraph.HEROES.size() - 1:
		_fail("free_character_indices() should still list the three heroes the room gave away")
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.lives <= 0:
		_fail("the room case ran out of hearts, so it proves nothing")
	if not player.is_game_over:
		_fail("this peer's hand was emptied by a capture and the run did not end")
	_clear(player)

	# (b) the negative control: two heroes in hand, and the switch moves.
	player = await _make_player()
	var other: int = TowerGraph.HEROES.find("teibi")
	room.hand = [mine, other] as Array[int]
	player.set_active_character(mine)
	player.hit_by_crocodile(_hunter())
	if player.current_character_index != other:
		_fail("with a two-hero hand the capture landed on %s, expected %s"
			% [player.hero_name(), TowerGraph.HEROES[other]])
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.is_game_over:
		_fail("the run ended with %s still in hand" % TowerGraph.HEROES[other])
	_clear(player)
	room.queue_free()
	await process_frame


# ============================================================================
# HARNESS
# ============================================================================

func _make_player() -> Node:
	"""A real `player.tscn`, in the tree and ready to be bitten."""
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	root.add_child(player)
	await process_frame
	return player


func _make_tower() -> Node3D:
	## Shell plus interior, assembled the way `endless_terrain` assembles them — the
	## interior added BEFORE the shell enters the tree, so it can see its parent.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	root.add_child(shell)
	await process_frame
	return shell


func _clear(player: Node) -> void:
	if player != null:
		player.queue_free()


func _hunter() -> Node:
	"""The real GD-SURVEY row, by name."""
	return _attacker_row("hunter_robot")


func _attacker_row(species: String) -> Node:
	"""
	A stub carrying `species`'s REAL row out of `PigletCrocodile.SPECIES`.

	Reading the table rather than typing a literal is the whole point: capture is
	keyed on the row's `behavior`, so if the arm is ever renamed this check moves
	with it instead of quietly passing on a string nothing uses any more.
	"""
	if _stubs.has(species):
		return _stubs[species]
	var stub := AttackerStub.new()
	var table: Dictionary = load(CROC_SCRIPT).get_script_constant_map().get("SPECIES", {})
	if table.has(species):
		stub.spec = table[species]
	else:
		_fail("PigletCrocodile.SPECIES has no '%s' row" % species)
	_stubs[species] = stub
	return stub


func _beat_done() -> void:
	"""Arm capture the way the authored rescue does: the id, in the stored set."""
	BestRunStore.merge_tower_opened_ids([TowerInterior.RESCUE_DONE])


func _fresh_store() -> void:
	"""Delete this check's throwaway profile. Never the real one — see the header."""
	DirAccess.remove_absolute(LOCAL_STORE_PATH)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	_fresh_store()
	for stub: Node in _stubs.values():
		stub.free()
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
