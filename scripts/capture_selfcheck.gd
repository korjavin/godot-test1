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
##  13-16. **THE FULL-CUSTODY PROTOCOL** (bead godot-test1-3iy.11), which is what
##      the empty-roster branch now opens instead of a screen: the scene opens and
##      is playable, surviving it takes exactly one AUTHORED scar, losing it
##      archives the world (and Continue/New Game mean what they say), and the
##      scene-scoped roster override does not leak. See the block above check 13.
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
## Check 10 needs REAL bodies, not the row stubs the checks above use — see there.
const HUNTER_SCENE: String = "res://scenes/characters/hunter_robot.tscn"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
## The tower's sentry: the scene, its SPECIES row's name, and the tolerance the
## knockback is measured to. The row name is read from `TowerInterior` rather than
## typed, so a rename fails by name instead of silently probing a row that no
## longer exists.
const GUARD_SCENE: String = "res://scenes/characters/tower_guard.tscn"
const GUARD_SPECIES: String = TowerInterior.GUARD_SPECIES
const SETBACK_EPS: float = 1e-3
## How far from the probe player a live predator body is stood up. Far enough that
## it cannot overlap and bite on its own during an awaited frame (a chase covers
## ~0.09 m in one), near enough to be nothing but a stand-off.
const PROBE_STANDOFF: float = 3.0

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

	## The rest of the manager surface `_tick_prison()` reads (bead
	## godot-test1-3iy.10), modelled rather than faked: `held` is what the LOBBY
	## says this peer holds, and `request_reassignment()` moves it the way
	## `server/room.go`'s `SetHero` plus the `heroes` broadcast that follows it do —
	## atomically, and only when there is something to move to. `claimable` empty is
	## a room with nothing to give, which is the only thing that may bench anybody.
	var online: bool = true
	## Who the lobby says the master is, and who we are — the pair
	## `player_controller._custody_authority()` compares. Defaulting BOTH to "me"
	## keeps every other check in this file on the solo-shaped path it has always
	## taken; only check 18 makes them differ.
	var master: String = "me"
	var me: String = "me"
	var held: String = ""
	var claimable: String = ""
	var reassignments: int = 0
	var reported: Array = []

	func my_character_indices() -> Variant:
		return null if hand.is_empty() else hand

	func is_online() -> bool:
		return online

	func get_master() -> String:
		return master

	func my_id() -> String:
		return me

	func my_hero() -> String:
		return held

	func report_hero_captured(hero: String) -> void:
		reported.append([hero, true])

	func report_hero_freed(hero: String) -> void:
		reported.append([hero, false])

	func request_reassignment() -> bool:
		if claimable.is_empty():
			return false
		reassignments += 1
		held = claimable
		claimable = ""
		return true

	## ...and the two the cell block's VENT PURGE reads.
	##
	## `peer_markers()` REPRODUCES THE REAL SHAPE EXACTLY — an Array of
	## `{"pos": Vector3, "color": Color}`, `null` when there is no room — because
	## the shape is the thing under test. The purge was first written against
	## `peer_positions()`, which looks like the same query and is MASTER-ONLY and
	## returns a bare `Array[Vector3]`: with a stub that answered a Dictionary the
	## check passed while the pad did nothing for three prisoners out of four.
	var team: Array = []
	var flees: Array = []

	func peer_markers() -> Variant:
		return null if team.is_empty() else team

	## FOUR PARAMETERS, matching the real manager exactly. `tracks_player` is the
	## one the purge has to pass false for — the position it names is a TEAMMATE's,
	## not the caster's — and a stub one argument short does not raise a type error,
	## it makes the call fail and the pad do nothing.
	func request_croc_flee(origin: Vector3, duration: float, radius: float = 0.0,
			tracks_player: bool = true) -> bool:
		flees.append([origin, duration, radius, tracks_player])
		return true

	## The one shared-total query `_check_shared_game_over()` gates on. `null` is
	## the real manager's "no room" answer and is the default here, so every check
	## that does not set it keeps solo semantics — deliberately NOT `shared_bank`,
	## which would put `_refresh_shared_totals()` in charge of `lives` and overwrite
	## the very number these checks set by hand.
	var shared_spent: Variant = null

	func shared_lives_spent(_own: int) -> Variant:
		return shared_spent


## A terrain that answers exactly one question: where the building stands. The
## prison role marches the benched player there through the same `"terrain"` group
## lookup the full-custody protocol uses, so a stub in that group is on the real
## code path.
class TerrainStub extends Node:
	const SITE := Vector3(512.0, 0.0, -96.0)

	func tower_site() -> Vector3:
		return SITE


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
	await _check_the_ai_says_who_bit()
	await _check_a_guard_takes_coins_and_ground_not_a_heart()
	await _check_the_sweep_spares_a_guard()
	await _check_the_protocol_opens_and_can_be_played()
	await _check_the_break_out_scars_the_world()
	await _check_reassign_first_imprison_last()
	await _check_two_clients_cannot_disagree()
	await _check_the_recall_archives_the_world()
	await _check_the_scene_does_not_leak()
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
			_fail("a '%s' contact moved the coin count — only a body carrying a"
				% label + " `coin_setback` row key does that (check 11)")
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
	An empty free-hero set ENDS FIELD PLAY with hearts still in hand.

	The hearts are the point. Game over on lives already existed, so a check that
	drained the roster and the hearts together would pass on a build with no
	capture trigger at all; here the player keeps most of its hearts and field play
	stops anyway, which only the free-set clause can do.

	SINCE BEAD godot-test1-3iy.11 THAT CLAUSE OPENS THE FULL-CUSTODY PROTOCOL rather
	than the Game Over screen — the one line this check had to move with. What is
	measured here is still the CLAUSE (it fired, on hearts it did not need); what
	the scene then does is checks 13-16.

	And the negative control on the same path — three of four heroes held, hearts
	in hand — must leave the run alone entirely, or "the clause fired" would only
	mean "something happened".
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
	if not player.in_custody_protocol():
		_fail("the last free hero was captured with %d hearts left and field play went on"
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
	if player.is_game_over or player.in_custody_protocol():
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

	What is measured here is that capture does not BREAK the assignment that already
	ships: the auto-switch must never reach past the hand and step this peer into a
	teammate's hero — the lobby is the source of truth for hero assignment and
	nothing may be decided locally. That is why `available_character_indices()`
	exists rather than two copies of one intersection. The negative control — a
	two-hero hand — proves the switch still moves when there IS somewhere to go, so
	"it did not step out of the hand" cannot be satisfied by a switch that never
	happens.

	...AND THAT THE ENDING IS NOT RAISED HERE (bead godot-test1-3iy.10). An emptied
	HAND used to end this peer's run; under the owner's world-level reading it must
	not, because three heroes are still free somewhere in the room and the answer is
	a reassignment or the prison role, both of which `_tick_prison()` owns. The
	positive control is right underneath: mark the other three captive too and the
	SAME code path does open the protocol, so "it did not end the run" cannot be
	satisfied by an ending that never fires.
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
	if player.in_custody_protocol():
		_fail(("an emptied HAND opened the full-custody protocol while %d heroes are still "
			+ "free in the room — game over is world-level (bead godot-test1-3iy.10)")
			% player.free_hero_count())
	if not player.is_respawning:
		_fail("a benched peer with free heroes left in the room neither respawned nor was benched")

	# The positive control, on the same player and the same call: take the other
	# three and the world really is out of heroes.
	player.is_respawning = false
	for hero: Variant in TowerGraph.HEROES:
		player.captive_heroes[String(hero)] = true
	if player.free_hero_count() != 0:
		_fail("the positive control did not empty the roster, so it proves nothing")
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.lives <= 0:
		_fail("the positive control ran out of hearts, so it proves nothing")
	if not player.in_custody_protocol():
		_fail("the room ran out of heroes entirely and field play went on")
	# The scene is left running and the player is freed under it. Deliberately NOT
	# closed through `_end_custody_protocol(false)`: that writes the world archive,
	# which every later check would then come up inside.
	_clear(player)

	# (b) the negative control: two heroes in hand, and the switch moves.
	player = await _make_player()
	var other: int = TowerGraph.HEROES.find("teibi")
	room.hand = [mine, other] as Array[int]
	player.set_active_character(mine)
	# E FIRST, before anybody is captive: the hand alone must already bound the
	# cycle. This is pre-existing behaviour that nothing else measures, and the
	# captive filter rewrote the block that implements it — four presses is more
	# than a lap of a two-hero hand, so a cycle that could leave it would.
	for press: int in 4:
		player.switch_to_next_character()
		if player.current_character_index != mine and player.current_character_index != other:
			_fail("E left the room's hand and landed on %s" % player.hero_name())
			break
	player.set_active_character(mine)
	player.hit_by_crocodile(_hunter())
	if player.current_character_index != other:
		_fail("with a two-hero hand the capture landed on %s, expected %s"
			% [player.hero_name(), TowerGraph.HEROES[other]])
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.is_game_over or player.in_custody_protocol():
		_fail("the run ended with %s still in hand" % TowerGraph.HEROES[other])
	_clear(player)
	room.queue_free()
	await process_frame


# ============================================================================
# HARNESS
# ============================================================================

# ============================================================================
# 10. THE AI ACTUALLY SAYS WHO BIT
# ============================================================================

func _check_the_ai_says_who_bit() -> void:
	"""
	THE WHOLE MECHANIC IS ONE ARGUMENT, AND NOTHING ABOVE THIS CHECKS IT.

	Every check above hands `hit_by_crocodile()` an attacker itself, so they all
	pass with perfect indifference to whether anything in the game ever does. It
	shipped that way: `_on_player_collision` in piglet_crocodile_ai.gd called
	`player.hit_by_crocodile()` with no argument at both bite sites, so `attacker`
	was null, `_is_hunter_grab` answered false, and systemic capture was
	unreachable code in a build whose nine checks were green.

	That is the exact shape of failure this file exists for — silent, invisible in
	a screenshot, and indistinguishable from "capture is armed but nobody has been
	grabbed yet". So this check drives the SHIPPED collision handler on REAL bodies
	instead of calling the damage verb itself. It is the only check here that can
	fail when the AI stops passing `self`, and it is deliberately the last one: if
	it ever passes while check 2 fails, the argument is being passed but the
	arithmetic is wrong, which is a different bug.

	The crocodile is the control, and it is not decoration: `_on_player_collision`
	now passes `self` from BOTH bite sites unconditionally, so "an animal reaches
	the same line" is a live possibility rather than a hypothetical, and only the
	row's `behavior` separates them.
	"""
	_beat_done()
	for label: String in ["hunter_robot", "crocodile"]:
		var player := await _make_player()
		var body: Node = load(HUNTER_SCENE if label == "hunter_robot" else CROC_SCENE).instantiate()
		# `species` BEFORE add_child: _ready() is where the row resolves into `spec`.
		body.species = label
		root.add_child(body)
		await process_frame
		if String(body.spec.get("behavior", "")) != ("hunt" if label == "hunter_robot" else "solo"):
			_fail("the '%s' probe resolved behaviour '%s' — this check would measure the wrong thing"
					% [label, str(body.spec.get("behavior", ""))])

		# The shipped handler, called the way a real overlap calls it.
		body._on_player_collision(player)

		var took: bool = player.captive_heroes.size() > 0
		if label == "hunter_robot" and not took:
			_fail("a LIVE hunter's collision took no hero — _on_player_collision is not telling "
					+ "hit_by_crocodile who bit, so systemic capture is unreachable in the game "
					+ "even though every check above passes")
		if label == "crocodile" and took:
			_fail("a LIVE crocodile's collision took %s — an animal is reaching the capture path"
					% str(player.captive_heroes.keys()))
		body.queue_free()
		_clear(player)
		await process_frame

	# ---- AND THE SAME QUESTION FOR THE THIRD STAKE -------------------------
	# Check 11 hands `hit_by_crocodile` a row stub, so it is indifferent to whether
	# the thing standing in the tower ever reaches that line — the exact
	# indifference that let systemic capture ship unreachable. So: a REAL guard from
	# the shipped scene, its own `_on_player_collision`, and the coins have to move.
	# A guard is not on the hunt arm, so this is also the negative control for
	# capture that a live body can give and a stub cannot.
	#
	# NO TOWER IN THE TREE, DELIBERATELY, and it was a real green-on-my-machine /
	# red-on-CI bug: building one stands three MORE live guards up beside the probe,
	# any of which can bite the player in the awaited frame — and a player who is
	# already `is_caught` takes `hit_by_crocodile`'s invulnerability early return, so
	# the probe's own collision resolves to nothing on a machine whose frame timing
	# happens to let a guard land first. The knockback is not what this block
	# measures (check 11 measures it, both branches, with a real tower); the COINS
	# are, and they move with or without a building. Anything that has to be true
	# for the measurement to mean something is asserted below rather than assumed.
	var mark := await _make_player()
	mark.coins_collected = SETBACK_PROBE_COINS
	mark.own_coins = SETBACK_PROBE_COINS
	var sentry: Node = load(GUARD_SCENE).instantiate()
	sentry.species = GUARD_SPECIES
	root.add_child(sentry)
	# STOOD OFF THE PLAYER, which is the other half of the same bug: a live body
	# dropped ON the probe overlaps it, and its own `_physics_process` calls
	# `_on_player_collision` during the awaited frame — so the explicit call below
	# lands on an already-invulnerable player and measures nothing, on whichever
	# machine wins that race. `PROBE_STANDOFF` is inside the row's detection radius
	# but far more than one frame of chase, so the ONLY contact in this block is the
	# one this check makes on purpose.
	(sentry as Node3D).global_position = (mark as Node3D).global_position \
			+ Vector3(PROBE_STANDOFF, 0.0, 0.0)
	await process_frame
	if float(sentry.spec.get("coin_setback", 0.0)) <= 0.0:
		_fail("the live probe guard resolved a row with no coin_setback — it is"
				+ " running on the crocodile fallback, so this block would be asking"
				+ " an animal to take coins")
	if mark.is_caught or mark.is_respawning or mark.is_game_over \
			or mark.respawn_blink_timer > 0.0:
		_fail("the probe player was already invulnerable before the collision —"
				+ " something else hit it first and hit_by_crocodile will take its"
				+ " early return, so this block would measure nothing")
	sentry._on_player_collision(mark)
	mark.is_caught = false
	mark.call("_on_caught_finished")
	if mark.coins_collected >= SETBACK_PROBE_COINS:
		_fail("a LIVE guard's collision took no coins — _on_player_collision is not"
				+ " telling hit_by_crocodile who bit, so the whole setback is"
				+ " unreachable in the game even though check 11 passes")
	if mark.captive_heroes.size() > 0:
		_fail("a LIVE guard's collision took %s — a guard is not a retrieval unit"
			% str(mark.captive_heroes.keys()))
	sentry.queue_free()
	_clear(mark)
	await process_frame


# ============================================================================
# 11. THE THIRD STAKE — a tower guard takes coins and ground, never a heart
# ============================================================================

## What this check starts the player with. Round enough that the expected loss is
## exact at 7% (200 -> 14) and big enough that an off-by-one in the arithmetic is
## visible rather than lost in a rounding argument.
const SETBACK_PROBE_COINS: int = 200

func _check_a_guard_takes_coins_and_ground_not_a_heart() -> void:
	"""
	The tower's own stake, and the ruling it enforces: the building may NEVER end a
	run (owner, 2026-08-27).

	THE HEARTS ARE THE POINT, exactly as they are in check 6 one direction over.
	The probe goes in with ONE heart and capture ARMED — the two states in which
	every other contact in this game is fatal — and comes out still standing, with
	the heart, the roster and the run all intact and a slice of the bank gone
	instead. A build where a guard fell through to the ordinary predator path would
	show a dead player here; a build where the setback also spent a heart would show
	a game over.

	FOUR THINGS ARE MEASURED AND ALL FOUR ARE SEPARATE FAILURES:

	  * the coins: exactly `floor(own_coins x coin_setback)`, off BOTH the displayed
	    figure and this peer's own contribution, read from the ROW rather than from
	    a 0.07 typed in here — retune the row and this check retunes with it;
	  * the heart: unspent, and no game over, with the run's last heart in hand;
	  * the hero: untaken, WITH CAPTURE ARMED, which is the "guards never capture"
	    half of the ruling;
	  * the ground: the body is standing on the last checkpoint it lit — and on the
	    doorway instead when it has lit none, which is the other branch of
	    `setback_point()` and would otherwise never be executed by anything.

	And the crocodile control on the same path, because every one of those
	assertions is also true of a build where `hit_by_crocodile` stopped working
	altogether.
	"""
	_beat_done()
	var row: Dictionary = load(CROC_SCRIPT).get_script_constant_map() \
			.get("SPECIES", {}).get(GUARD_SPECIES, {})
	var fraction: float = float(row.get("coin_setback", 0.0))
	if fraction <= 0.0:
		_fail("SPECIES['%s'] carries no coin_setback — the third stake has no" % GUARD_SPECIES
				+ " arithmetic, so a guard would take a heart like any animal")
		return
	var expected_loss: int = int(floor(float(SETBACK_PROBE_COINS) * fraction))
	if expected_loss <= 0:
		_fail("a %.3f setback on %d coins rounds to nothing — this check would pass"
			% [fraction, SETBACK_PROBE_COINS] + " against a build that took nothing")
		return

	for lit: bool in [false, true]:
		var shell := await _make_tower()
		var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
		# The two branches of `setback_point()`, driven explicitly rather than
		# inherited from whatever the profile on disk happens to hold.
		if lit:
			shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
		else:
			(shell.get("opened") as Dictionary).erase(TowerInterior.GATE_CHECKPOINT)
		var want_spot: Vector3 = interior.global_position + (TowerInterior.CHECKPOINT_STAND
				if lit else TowerInterior.ENTRY_STAND)

		var player := await _make_player()
		player.coins_collected = SETBACK_PROBE_COINS
		player.own_coins = SETBACK_PROBE_COINS
		player.lives = 1
		var hero: String = player.hero_name()

		player.hit_by_crocodile(_attacker_row(GUARD_SPECIES))
		player.is_caught = false
		player.call("_on_caught_finished")

		if player.lives != 1:
			_fail("a guard's hit spent a heart (%d left) — the building can end a run"
				% player.lives)
		if player.is_game_over:
			_fail("a guard's hit ended the run — the tower is not allowed to game-over"
					+ " the player mid-rescue")
		if player.captive_heroes.has(hero):
			_fail("a guard took %s with capture armed — guards never capture" % hero)
		if player.coins_collected != SETBACK_PROBE_COINS - expected_loss:
			_fail("a guard's setback left %d of %d displayed coins, expected %d"
				% [player.coins_collected, SETBACK_PROBE_COINS,
					SETBACK_PROBE_COINS - expected_loss])
		if player.own_coins != SETBACK_PROBE_COINS - expected_loss:
			_fail("a guard's setback left %d of %d own_coins, expected %d — in a room"
				% [player.own_coins, SETBACK_PROBE_COINS,
					SETBACK_PROBE_COINS - expected_loss]
				+ " that is this peer's contribution to the shared bank")
		if (player as Node3D).global_position.distance_to(want_spot) > SETBACK_EPS:
			_fail("a guard's setback left the player at %s, not on the %s at %s"
				% [str((player as Node3D).global_position),
					("checkpoint" if lit else "doorway"), str(want_spot)])
		if not player.is_respawning:
			_fail("a guard's setback did not open a grace window — the guard that just"
					+ " hit you gets a free second bite")
		_clear(player)
		shell.queue_free()
		await process_frame

	# ---- THE CONTROL: an animal still costs a heart, coins and ground ---------
	var shell_c := await _make_tower()
	var player_c := await _make_player()
	player_c.coins_collected = SETBACK_PROBE_COINS
	player_c.own_coins = SETBACK_PROBE_COINS
	var where: Vector3 = (player_c as Node3D).global_position
	var hearts: int = player_c.lives
	player_c.hit_by_crocodile(_attacker_row("crocodile"))
	player_c.is_caught = false
	player_c.call("_on_caught_finished")
	if player_c.lives != hearts - 1:
		_fail("a crocodile's bite left %d hearts of %d — the control is not on the"
			% [player_c.lives, hearts] + " ordinary predator path, so the guard"
			+ " branch above proves nothing about being different")
	if player_c.coins_collected != SETBACK_PROBE_COINS:
		_fail("a crocodile's bite moved the coin count to %d — the setback is"
			% player_c.coins_collected + " reaching rows that do not carry it")
	if (player_c as Node3D).global_position.distance_to(where) > 1.0:
		_fail("a crocodile's bite knocked the player to the tower — the knockback is"
				+ " reaching rows that do not carry a setback")
	_clear(player_c)
	shell_c.queue_free()
	await process_frame


# ============================================================================
# 12. THE RESPAWN SWEEP MUST NOT EAT THE BUILDING'S POPULATION
# ============================================================================

func _check_the_sweep_spares_a_guard() -> void:
	"""
	`clear_nearby_crocodiles()` FREES bodies, and a guard must not be one of them.

	THIS IS NOT ABOUT A GUARD'S OWN BITE. Every other way to lose inside the tower
	routes through the ordinary respawn — the rotor bar, the wing's press, a
	crocodile that followed you in through the doorway — and that path sweeps a
	25 m radius, which from anywhere in a 17.6 m building is the WHOLE floor. Left
	unexempted, dying to the rotor is the cheapest way to clear a guarded room, and
	the population comes back at the next doorway crossing rather than never — so
	the bug is invisible in the code and obvious at the keyboard.

	Driven on REAL bodies from the shipped scenes, because the exemption is a row
	read (`coin_setback`) on a live `spec`: a stub would prove the branch compiles
	and nothing about whether the thing standing in the tower carries the key.

	The crocodile beside it is the control. Without it "the guard survived" is also
	true of a sweep that was never called, never found the group, or has quietly
	stopped freeing anything at all.
	"""
	var player := await _make_player()
	var spot: Vector3 = (player as Node3D).global_position

	var guard: Node = load(GUARD_SCENE).instantiate()
	guard.species = GUARD_SPECIES
	root.add_child(guard)
	var croc: Node = load(CROC_SCENE).instantiate()
	root.add_child(croc)
	await process_frame
	(guard as Node3D).global_position = spot + Vector3(1.0, 0.0, 0.0)
	(croc as Node3D).global_position = spot + Vector3(2.0, 0.0, 0.0)
	if String(guard.spec.get("behavior", "")) == "" \
			or float(guard.spec.get("coin_setback", 0.0)) <= 0.0:
		_fail("the probe guard did not resolve the '%s' row — check 12 would be"
			% GUARD_SPECIES + " measuring a crocodile that happens to be exempt")

	player.clear_nearby_crocodiles(spot)
	await process_frame
	await process_frame

	if not is_instance_valid(guard):
		_fail("the respawn sweep freed a tower guard — any death inside the building"
				+ " would clear the floor, and the population is supposed to come"
				+ " back at the doorway, not at whatever hazard you lost to")
	elif guard.is_queued_for_deletion():
		_fail("the respawn sweep queued a tower guard for deletion")
	if is_instance_valid(croc) and not croc.is_queued_for_deletion():
		_fail("the respawn sweep spared an ordinary crocodile too — it is not"
				+ " sweeping anything, so sparing the guard proves nothing")

	if is_instance_valid(guard):
		guard.queue_free()
	if is_instance_valid(croc):
		croc.queue_free()
	_clear(player)
	await process_frame


# ============================================================================
# 13-16. THE FULL-CUSTODY PROTOCOL (bead godot-test1-3iy.11)
# ============================================================================
#
# WHY THESE FOUR EXIST. The protocol is the end of the capture arc and every one
# of its failure modes is silent — it replaces a screen with a scene, so a build
# where the trigger is wrong looks exactly like a build where it is right until
# somebody plays for twenty minutes and loses their last hero:
#
#   * it never OPENS, and the roster clause quietly shows the Game Over screen the
#     way it did before this bead;
#   * it opens but is UNPLAYABLE, because the roster grant is missing and there is
#     nobody to be — the availability set is empty by definition inside the scene;
#   * it is survived and the world is NOT SCARRED, so the one sanctioned exception
#     to the graph's edge-additive law ships inert past a green build;
#   * it is lost and the world is NOT ARCHIVED, so "the campaign ends" ends nothing
#     and the next launch hands out another run;
#   * it LEAKS — the scene marks every hero captive, and an exit that does not put
#     the entry set back leaves a peer in a room holding heroes that belong to
#     teammates.
#
# EVERY ONE OF THEM IS DRIVEN THROUGH THE REAL ENTRY, `hit_by_crocodile()` plus
# `_on_caught_finished()`, and the outcomes are decided by REAL PHYSICS FRAMES
# rather than by calling `_end_custody_protocol()` — which is the whole point. A
# check that opened the scene by hand would pass on a build where the roster clause
# still calls `_trigger_game_over()` and the scene is unreachable in the game.
# Only the CLOCK is fast-forwarded (it is 35 s of real state, and a check may set
# state); the decision that reads it is the shipped one.

func _check_the_protocol_opens_and_can_be_played() -> void:
	"""
	Check 13. Losing the last hero opens the break-out, and the break-out is playable.

	The two halves are one check because either alone is a lie: a scene nobody can
	enter and an entrance into a scene with no roster are the same shipped-inert bug
	at two sites.
	"""
	_fresh_store()
	_beat_done()

	# THE NEGATIVE CONTROL COMES FIRST, and it is not ceremony. Everything below
	# measures a scene that opened; nothing below would notice a scene that opens by
	# ITSELF. `_tick_custody()` runs on every physics frame of every ordinary run and
	# is one missing guard away from closing a break-out nobody entered — scarring
	# the tower, on the first frame, in a run where nobody was ever captured.
	var idle := await _make_player()
	var idle_store := BestRunStore.tower_opened_ids()
	for _i in 4:
		await physics_frame
	if idle.in_custody_protocol():
		_fail("an ordinary run with nobody captive opened the full-custody protocol")
	if BestRunStore.tower_opened_ids() != idle_store:
		_fail("an ordinary run scarred the tower by standing still: %s -> %s"
			% [str(idle_store), str(BestRunStore.tower_opened_ids())])
	if idle.custody_timer != 0.0:
		_fail("an ordinary run is running a recall clock (%.2f s left)" % idle.custody_timer)
	_clear(idle)
	await process_frame

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
	if player.is_game_over:
		_fail("the last free hero was taken with %d hearts left and the run ENDED — the "
			% player.lives + "roster clause must open the full-custody protocol, not a screen")
	if not player.in_custody_protocol():
		_fail("the last free hero was taken and no protocol opened")
		_clear(player)
		return
	if player.custody_timer <= 0.0:
		_fail("the protocol opened with no recall clock running")

	# EVERY HERO IS A PRISONER, which is both the fiction and the cell block's paint.
	if player.free_hero_count() != 0:
		_fail("the protocol opened with %d hero(es) still free — full custody means all four"
			% player.free_hero_count())
	# ...and the scene grants a confined all-four set anyway, or there is nobody to be.
	var granted: Array = player.available_character_indices()
	if granted.size() != TowerGraph.HEROES.size():
		_fail("inside the protocol the roster grant offers %s — the scene must grant all four"
			% str(granted))
	# Driven through the REAL cycle, not the array: E is what a player presses, and
	# `switch_to_next_character()` refuses outright on a hand of one.
	var walked := {}
	for press: int in TowerGraph.HEROES.size():
		walked[player.hero_name()] = true
		player.switch_to_next_character()
	if walked.size() != TowerGraph.HEROES.size():
		_fail("E reached only %d of the four heroes inside the protocol: %s"
			% [walked.size(), str(walked.keys())])
	_clear(player)


func _check_the_break_out_scars_the_world() -> void:
	"""
	Check 14. A liberation ends the scene, resumes play and takes exactly one scar.

	THE SCAR IS THE OUTCOME RECORD, so this is also the check that stops the one
	sanctioned exception to design law 3 from shipping inert. Three separate
	assertions, because a scar can fail in three ways: not written at all, written
	as an id nobody authored, or written twice.

	The liberation is `hero_freed()` — the cell block's own seam, and what
	`TowerInterior._liberate()` calls when the player walks into an occupied cell
	(check 8 drives that whole loop). The DECISION is left to a real physics frame.
	"""
	_fresh_store()
	_beat_done()
	var before := BestRunStore.tower_opened_ids()
	var player := await _make_player()
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("scar: no protocol to survive")
		_clear(player)
		return

	# Walk into a cell. One hero out is the whole success condition.
	var freed: String = String(TowerGraph.HEROES[0])
	player.hero_freed(freed)
	await physics_frame
	await physics_frame

	if player.in_custody_protocol():
		_fail("a hero was freed and the protocol did not close")
	if player.is_game_over:
		_fail("the break-out was survived and the run ended anyway")
	if player.free_hero_count() < 1:
		_fail("systemic play resumed with nobody free to play")
	if not player.available_character_indices().has(player.current_character_index):
		_fail("the protocol handed play back as %s, who is still in a cell" % player.hero_name())

	var after := BestRunStore.tower_opened_ids()
	var fresh: Array[String] = []
	for id: String in after:
		if not before.has(id):
			fresh.append(id)
	if fresh.size() != 1:
		_fail("a survived protocol wrote %s to the tower's set — exactly one scar was due"
			% str(fresh))
	elif not TowerGraph.scar_ids().has(fresh[0]):
		_fail("the protocol wrote '%s', which is not an AUTHORED scar (%s) — a scar must be "
			% [fresh[0], str(TowerGraph.scar_ids())]
			+ "enumerated in TOWER_GRAPH or the softlock audit never saw it")
	_clear(player)

	# ...and the scar is PERMANENT, so a second protocol in the same world takes no
	# second one. The budget is the authored list, not a counter.
	var scarred := BestRunStore.tower_opened_ids()
	player = await _make_player()
	await _drive_into_custody(player)
	player.hero_freed(String(TowerGraph.HEROES[1]))
	await physics_frame
	await physics_frame
	if BestRunStore.tower_opened_ids() != scarred:
		_fail("a second break-out changed the tower's set from %s to %s — there is one more "
			% [str(scarred), str(BestRunStore.tower_opened_ids())]
			+ "authored scar than the graph declares")
	_clear(player)


func _check_the_recall_archives_the_world() -> void:
	"""
	Check 15. The recall completing ends the campaign and archives the world.

	AND WHAT ARCHIVED MEANS, which is the half a "did we write the flag" check would
	miss entirely: a FRESH player built against the same profile comes up on the
	ending screen instead of a run (Continue), and Play Again clears it (New Game).
	Both are driven through the shipped entry points — `_ready()` and
	`restart_game()` — because the flag is worth nothing if nothing reads it.
	"""
	_fresh_store()
	_beat_done()
	var player := await _make_player()
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("archive: no protocol to lose")
		_clear(player)
		return
	if BestRunStore.world_archived():
		_fail("the world was archived the moment the protocol opened, before it was lost")

	# Fast-forward the CLOCK, not the decision: the branch that reads it is shipped.
	player.custody_timer = 0.001
	await physics_frame
	await physics_frame

	if player.in_custody_protocol():
		_fail("the recall completed and the protocol did not close")
	if not player.is_game_over:
		_fail("the recall completed and the campaign did not end")
	if not BestRunStore.world_archived():
		_fail("the recall completed and the world was not archived — Continue would hand "
			+ "out another run in a campaign that is over")
	_clear(player)
	await process_frame

	# CONTINUE: a fresh boot against the archived profile reopens the ending.
	var continued := await _make_player()
	await process_frame
	if not continued.is_game_over:
		_fail("a player booted into an archived world came up playable — Continue must "
			+ "reopen the ending screen")
	# NEW GAME: Play Again mints a fresh world and the latch is gone.
	continued.restart_game()
	if BestRunStore.world_archived():
		_fail("Play Again left the world archived — there is no way out of the ending")
	if continued.is_game_over:
		_fail("Play Again left the ending screen up")
	_clear(continued)

	# ...and the OTHER way to lose it: the last heart, spent inside the block. It is
	# the same outcome and must be recorded exactly once — two sites deciding one
	# ending is two stings and an archive written behind a screen that went up for a
	# different reason.
	_fresh_store()
	_beat_done()
	var bled := await _make_player()
	await _drive_into_custody(bled)
	if not bled.in_custody_protocol():
		_fail("archive: no protocol to bleed out in")
		_clear(bled)
		_fresh_store()
		return
	bled.lives = 1
	bled.hit_by_crocodile(_hunter())
	bled.is_caught = false
	bled.call("_on_caught_finished")
	if bled.in_custody_protocol():
		_fail("the last heart went inside the block and the scene ran on")
	if not bled.is_game_over:
		_fail("the last heart went inside the block and the campaign did not end")
	if not BestRunStore.world_archived():
		_fail("the last heart went inside the block and the world was not archived")
	# ...and the clock must not then decide it a second time.
	var timer_after: float = bled.custody_timer
	await physics_frame
	await physics_frame
	if bled.custody_timer != timer_after:
		_fail("the recall clock kept running after the scene ended")
	_clear(bled)
	_fresh_store()


func _check_the_scene_does_not_leak() -> void:
	"""
	Check 16. The bead's landmine: the scene-scoped roster override must not leak.

	The scene marks EVERY hero captive — that is the fiction and it is what paints
	four red cells — so the exit has to restore what was true before, minus whoever
	was freed. Solo that is a no-op and proves nothing, so this is driven IN A ROOM
	with a one-hero hand: three of the four heroes belong to teammates and were
	never this peer's to hold.

	AND THE BUILDING IS PUT BACK TOO, on the failing outcome as well as the winning
	one — raised containment is scene state with no home, and a Play Again keeps the
	same profile and the same tower.

	SINCE bead godot-test1-3iy.10 THE OVER-MARKING IS STRUCTURALLY A NO-OP, and that
	is worth saying rather than deleting the check. Game over is world-level now, so
	the protocol only ever opens when EVERY hero is already captive — the scene's
	"mark all four" loop can no longer add anybody, and the entry set is simply what
	was true. What is measured below is therefore the surviving half of the same
	invariant: the exit restores exactly the set it entered with (not the raw
	all-four the scene painted), through the same `entry INTERSECT still-held` line.
	"""
	_fresh_store()
	_beat_done()
	var room := RoomStub.new()
	room.add_to_group("mp")
	root.add_child(room)
	var shell := await _make_tower()
	var interior: Node = shell.get_child(0)

	var player := await _make_player()
	var mine: int = TowerGraph.HEROES.find("primm")
	room.hand = [mine] as Array[int]
	player.set_active_character(mine)
	# THE ROOM IS OUT OF HEROES, which is the only thing that opens the scene now:
	# the three heroes this peer never held are in teammates' cells, and the grab
	# below takes the last one. Driven through the real entry so a build whose
	# roster clause stopped firing fails here instead of measuring a scene this
	# check opened itself.
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("leak: the room ran out of heroes and no peer entered the protocol")
		_clear(player)
		room.queue_free()
		shell.queue_free()
		await process_frame
		return

	# The building raised containment, whatever a hundred earlier rescues opened.
	for door: Dictionary in TowerInterior.SPINE_DOORS:
		if not bool(interior.call("is_locked_down", String(door["gate"]))):
			_fail("the protocol opened and spine door '%s' was left standing open — the "
				% String(door["gate"]) + "break-out is three metres of walking")

	# Lose it, which is the harsher half: a failed scene still has to tidy up.
	player.custody_timer = 0.001
	await physics_frame
	await physics_frame

	for hero: String in TowerGraph.HEROES:
		if not player.is_hero_captive(hero):
			_fail(("the scene left %s free after it ended, and nobody was liberated in it — "
				+ "the exit set must be `entry INTERSECT still-held`, not a wipe") % hero)
	if player.free_hero_count() != 0:
		_fail("a failed protocol handed the room %d heroes back" % player.free_hero_count())
	for door: Dictionary in TowerInterior.SPINE_DOORS:
		if bool(interior.call("is_locked_down", String(door["gate"]))):
			_fail("the protocol ended and '%s' is still under lockdown — containment "
				% String(door["gate"]) + "outlived the scene that raised it")
	_clear(player)
	room.queue_free()
	shell.queue_free()
	await process_frame
	_fresh_store()


# ============================================================================
# 17. REASSIGN FIRST, IMPRISON LAST (bead godot-test1-3iy.10)
# ============================================================================

func _check_reassign_first_imprison_last() -> void:
	"""
	Check 17. The multiplayer capture consequence, driven through real physics.

	THE MECHANIC HAS TO BE REACHABLE FROM THE GAME, which is the only reason this
	is a live check and not arithmetic: every decision below is made inside
	`_tick_prison()`, which nothing calls but `_physics_process`, on a half-second
	cadence. So the player here is a real `player.tscn`, the room is in group `"mp"`,
	the tower's site comes through the `"terrain"` group, and the only thing this
	file does is bite the player and wait. A build where the tick was never wired up
	fails every part of this.

	Four claims, in the order the owner's rule states them:

	  (a) REASSIGN FIRST, AND NOT IN THE SAME FRAME AS THE CAPTURE. The grab
	      reports the capture to the room and asks the lobby for NOTHING yet; the
	      claim goes out on the next `_tick_prison()`, and nobody is benched. The
	      delay is load-bearing rather than incidental: `SetHero` releases the claim
	      on the hero just taken, so a claim sent from the grab races the `cap`
	      packet on every other peer and the room's captive sets diverge. The
	      reassignment must also go through the ROOM — a local index write would put
	      two peers in one body — so what is measured is the call, not the result.
	  (b) IMPRISON LAST. The same capture with NOTHING free stands the player up in
	      their own cell inside the block, and confines them there: shoved out, they
	      are back inside on the next physics frame. That is "no phasing, no solo
	      escape" as a measurement rather than a promise.
	  (c) THE BLOCK'S SYSTEMS ARE REACHABLE FROM INSIDE IT, AND THE ROLE HAS NO
	      OTHERS. The cell stand and the vent-purge pad are both inside the
	      confinement box — a role confined to a box that excluded its own systems
	      would be a cell with nothing in it, and nothing else in this file would
	      notice — and every character ability is refused while the role runs, which
	      is "no phasing, no combat loop" measured at the one gate the HUD reads.
	  (d) THE WAY OUT, THREE WAYS. A hero freed elsewhere in the room ends the role
	      and the liberation is told to the room; a hero that becomes claimable
	      LATER ends it through the tick's own retry, which is the half of
	      "reassign first" that only exists after the bench; and a prisoner may free
	      a CELLMATE but never themselves.
	  (f) THE ROOM'S HEARTS OUTRANK A RUNNING BREAK-OUT. The grab that empties the
	      roster can also spend the room's last shared heart: the peer that was
	      bitten ends on the hearts clause, while every other peer hears only the
	      `cap` packet and opens the scene. So the shared game over has to be able
	      to CLOSE a running protocol — and to close it without archiving the world
	      or taking a scar, because the scene was overtaken and not lost.
	  (e) THE ENDING, from both sides. The grab that takes the room's LAST hero
	      still costs its heart and gets its full freeze — the bench tick polls at
	      0.5 s and the freeze runs 0.55 s, so a tick that did not stand aside for
	      it would open the protocol first, clear `is_caught` under
	      `_on_caught_finished()` and make the final grab free. And a peer that was
	      never bitten at all still ends its run when the ROOM runs out, which is
	      the world-level reading and the only part of it no other check can see.
	"""
	_fresh_store()
	_beat_done()
	var room := RoomStub.new()
	room.add_to_group("mp")
	root.add_child(room)
	var terrain := TerrainStub.new()
	terrain.add_to_group("terrain")
	root.add_child(terrain)

	# ---- (a) reassign first ------------------------------------------------
	var player := await _make_player()
	var mine: int = TowerGraph.HEROES.find("primm")
	room.hand = [mine] as Array[int]
	room.held = "primm"
	room.claimable = "teibi"
	player.set_active_character(mine)
	player.hit_by_crocodile(_hunter())
	if room.reported != [["primm", true]]:
		_fail("the capture did not reach the room (%s) — every other peer's picker, "
			% str(room.reported) + "roster and ending would still be offering a hero in a cell")
	if room.reassignments != 0:
		_fail("the grab itself sent %d SetHero calls — the claim releases the captured "
			% room.reassignments + "hero's lobby entry, so a peer that has not yet heard "
			+ "the `cap` packet will refuse it and the room's captive sets diverge")
	await _tick(POST_BITE_FRAMES)
	if room.reassignments != 1:
		_fail("a capture with a free hero in the room made %d SetHero calls, expected 1"
			% room.reassignments)
	if player.prisoner_active:
		_fail("a peer that was handed a free hero was benched anyway — reassign FIRST")
	_clear(player)
	await process_frame

	# ---- (b) imprison last -------------------------------------------------
	room.reported.clear()
	room.reassignments = 0
	room.held = "primm"
	room.claimable = ""
	player = await _make_player()
	player.set_active_character(mine)
	player.hit_by_crocodile(_hunter())
	await _tick(POST_BITE_FRAMES)
	if not player.prisoner_active:
		_fail("the room had no free hero and nobody was benched — the prison role is "
			+ "unreachable from the game")
		_clear(player)
		room.queue_free()
		terrain.queue_free()
		await process_frame
		return
	if player.free_hero_count() != TowerGraph.HEROES.size() - 1:
		_fail("the bench fired with %d heroes free — it must only ever fire when the ROOM "
			% player.free_hero_count() + "has nothing to give, never as a stand-in for game over")
	var lo: Vector3 = TerrainStub.SITE + TowerInterior.block_min()
	var hi: Vector3 = TerrainStub.SITE + TowerInterior.block_max()
	if not _inside(player.global_position, lo, hi):
		_fail("the benched player stood up at %s, outside the cell block (%s .. %s)"
			% [player.global_position, lo, hi])
	# CONFINEMENT, measured by breaking it: shoved through the spine wall and out of
	# the building entirely, one physics frame must put the body back.
	player.global_position = TerrainStub.SITE + Vector3(0.0, 0.0, -40.0)
	await _tick(2)
	if not _inside(player.global_position, lo, hi):
		_fail("a prisoner shoved to %s stayed out of the block — the confinement is a "
			% player.global_position + "suggestion, and the role has a solo escape")

	# ---- (c) the systems are inside the box --------------------------------
	for hero: Variant in TowerGraph.HEROES:
		var stand: Vector3 = TerrainStub.SITE + TowerInterior.cell_stand(String(hero))
		if not _inside(stand, lo, hi):
			_fail("%s's cell stand is outside the confinement box — a prisoner would be "
				% String(hero) + "clamped out of their own cell on the first frame")
	var pad := TerrainStub.SITE + Vector3(TowerInterior.PURGE_PAD_X, 0.0, TowerInterior.PURGE_PAD_Z)
	if not _inside(pad, lo, hi):
		_fail("the vent-purge pad at %s is outside the confinement box — the block's system "
			% pad + "cannot be operated by the only player who is ever locked in with it")
	# ...and no ability at all. Asked of `get_ability_block_reason()`, which is the
	# ONE home of the gates — the F press and the HUD dial both read it, so a gate
	# that lived only at the press would show a green READY dial over a dead key.
	if player.get_ability_block_reason() != "CELL":
		_fail("the prison role's ability gate answers '%s' — the role is defined as no "
			% player.get_ability_block_reason() + "phasing and no combat loop, and every one "
			+ "of the four powers is one or the other")
	if player.is_ability_ready():
		_fail("the HUD would show the ability READY inside the cell block")

	# ---- (d1) a cellmate, never yourself -----------------------------------
	#
	# The prisoner plays as their own captive, so their own recess is the one
	# liberation the owner's ruling forbids — walk into it and nothing happens. The
	# cell beside it is the block's second system and must still work, which is the
	# negative control that stops "no solo escape" being implemented as "no
	# liberation at all".
	var shell := await _make_tower()
	shell.global_position = TerrainStub.SITE
	var interior: Node = shell.get_child(0)
	interior.set_captive("primm", true)
	interior.call("_on_cell_enter", player, "primm")
	if not interior.is_captive("primm"):
		_fail("a prisoner walked into their OWN cell and freed themselves — the role has a "
			+ "solo escape, which is the one thing the owner's ruling forbids it")
	interior.set_captive("teibi", true)
	interior.call("_on_cell_enter", player, "teibi")
	if interior.is_captive("teibi"):
		_fail("a prisoner could not free a CELLMATE — the refusal above is refusing every "
			+ "liberation, and the block's second system does nothing")
	# ---- (d1b) the block's system, operated from inside it -----------------
	#
	# THE PURGE IS THE ROLE'S ONE OUTWARD VERB, and "each operated system gives the
	# outside team an immediate opening" is the requirement it answers. Driven
	# through the interior's real `_process`, so a pad that was built and never
	# ticked fails here rather than reading fine.
	# Cleared first: `clear_nearby_crocodiles()` relays its own bounded wave through
	# the same manager verb on every placement and respawn, so the log already holds
	# the bench's own.
	room.flees.clear()
	interior.call("_on_purge_enter", player)
	interior._process(0.1)
	if not room.flees.is_empty():
		_fail("the vent purge fired with no room — solo it would be a panic button over the "
			+ "player's own pack, and there is no team outside to open anything for")
	var mate := TerrainStub.SITE + Vector3(300.0, 0.0, 0.0)
	room.team = [{"pos": mate, "color": Color.WHITE}]
	interior._process(0.1)
	if room.flees.size() != 1:
		_fail("standing on the purge pad relayed %d flee requests, expected one per teammate"
			% room.flees.size())
	else:
		var fired: Array = room.flees[0]
		if (fired[0] as Vector3).distance_to(mate) > SETBACK_EPS:
			_fail("the purge scattered the pack at %s, not around the teammate at %s — it "
				% [fired[0], mate] + "opens nothing for anybody standing there")
		if float(fired[1]) != TowerInterior.PURGE_FLEE_SECONDS \
				or float(fired[2]) != TowerInterior.PURGE_FLEE_RADIUS:
			_fail("the purge relayed %.1f s / %.1f m, not its own constants" % [fired[1], fired[2]])
		if bool(fired[3]):
			_fail("the purge asked the pack to run from the CASTER — on a prisoner who is "
				+ "also the room master that is the tower, i.e. roughly towards the teammate "
				+ "the purge was bought to help")
	interior._process(0.1)
	if room.flees.size() != 1:
		_fail("the purge fired again inside its cooldown (%d requests) — held down, it is a "
			% room.flees.size() + "flee packet per frame and the room's rate budget drops the rest")
	interior._process(TowerInterior.PURGE_COOLDOWN + 0.1)
	if room.flees.size() != 2:
		_fail("the purge never came back after its cooldown (%d requests)" % room.flees.size())
	interior.call("_on_purge_exit", player)
	interior._process(TowerInterior.PURGE_COOLDOWN + 0.1)
	if room.flees.size() != 2:
		_fail("the purge kept firing after the player stepped off the pad")
	# THE NEGATIVE CONTROL, and it is the one that keeps the pad the prisoner's: a
	# rescuer crosses this gallery on every ordinary liberation in the game, and a
	# party that could stand on it in passing would be handed the bench's whole
	# compensation for free.
	player.prisoner_active = false
	interior.call("_on_purge_enter", player)
	interior._process(TowerInterior.PURGE_COOLDOWN + 0.1)
	if room.flees.size() != 2:
		_fail("an ordinary rescuer standing on the purge pad fired it (%d requests) — it is "
			% room.flees.size() + "the prison role's system, not the party's")
	interior.call("_on_purge_exit", player)
	player.prisoner_active = true
	room.team = []

	shell.queue_free()
	await process_frame

	# ---- (d2) a hero that becomes claimable later --------------------------
	#
	# THE TICK'S OWN RETRY, and nothing else reaches it: the claim in
	# `_capture_active_hero()` already failed once (that is what benched us), so the
	# only thing that can ever put this peer back in the field through a lobby grant
	# is `_tick_prison()` asking again against fresher truth.
	if not player.prisoner_active:
		_fail("the prisoner left the role before the retry could be measured")
	room.claimable = "teibi"
	# TWO decisions' worth, and that is the shape of the rule rather than slack: the
	# tick that sends the claim RETURNS on it, because nothing has moved yet; the
	# next one reads the answer off `my_hero()` and lifts the role.
	await _tick(90)
	if room.reassignments != 1:
		_fail("a teammate freed a hero and the benched peer made %d SetHero calls, expected 1 "
			% room.reassignments + "— reassignment must be retried from the bench, not only at "
			+ "the moment of capture")
	if player.prisoner_active:
		_fail("the lobby granted a free hero and the player stayed in the cell block")

	# ---- (d3) a liberation, and the room hearing about it ------------------
	room.reported.clear()
	room.held = "primm"
	await _tick(45)
	if not player.prisoner_active:
		_fail("the peer was put back on its captive hero and was not benched again")
	player.hero_freed("primm")
	if room.reported != [["primm", false]]:
		_fail("a liberation did not reach the room (%s) — the peer who lost that hero "
			% str(room.reported) + "would stay in a cell the room no longer believes in")
	await _tick(45)
	if player.prisoner_active:
		_fail("the hero was freed and the player is still serving the prison role")
	_clear(player)
	await process_frame

	# ---- (e1) the last grab still costs a heart ----------------------------
	room.held = "phoboman"
	var last_index: int = TowerGraph.HEROES.find("phoboman")
	room.hand = [last_index] as Array[int]
	room.claimable = ""
	player = await _make_player()
	player.set_active_character(last_index)
	for hero: Variant in TowerGraph.HEROES:
		if String(hero) != "phoboman":
			player.set_hero_captive(String(hero), true)
	var hearts: int = player.lives
	player.hit_by_crocodile(_hunter())
	await _tick(POST_BITE_FRAMES)
	if player.lives != hearts - 1:
		_fail("the grab that took the room's last hero cost %d hearts, expected one — the "
			% (hearts - player.lives) + "bench tick outran the caught freeze and "
			+ "`_on_caught_finished()` never got to spend it")
	if not player.in_custody_protocol():
		_fail("the room's last hero was taken and the protocol did not open")

	# ...AND A SURVIVABLE BITE INSIDE THE SCENE STAYS ON THE RESPAWN PATH. The
	# break-out pins the free-hero count at 0 for its whole length — that is how its
	# outcome test knows nobody has been let out yet — so the world-level roster
	# clause is true on EVERY hit in the cell block. Unguarded, each one re-enters a
	# protocol that is already running, `_begin_custody_protocol()` returns on its
	# own latch, and the player is left with no grace window, no ability reset and no
	# crocodile sweep, standing next to the guard that just hit them.
	if player.lives <= 1:
		_fail("the in-scene bite has no heart to spend, so it proves nothing")
	var inside: int = player.lives
	player.is_respawning = false
	player.respawn_blink_timer = 0.0
	player.hit_by_crocodile(_hunter())
	player.is_caught = false
	player.call("_on_caught_finished")
	if player.lives != inside - 1:
		_fail("a survivable bite inside the break-out cost %d hearts, expected one"
			% (inside - player.lives))
	if not player.is_respawning:
		_fail("a survivable bite inside the break-out opened no grace window — the guard "
			+ "that just hit you gets a free second hit, every hit, for the whole scene")
	if not player.in_custody_protocol():
		_fail("a survivable bite inside the break-out ended the scene")
	player.custody_protocol_active = false
	_clear(player)
	await process_frame

	# ---- (f) the room's hearts outrank a running break-out -----------------
	_fresh_store()
	_beat_done()
	room.held = "phoboman"
	room.hand = [last_index] as Array[int]
	player = await _make_player()
	player.set_active_character(last_index)
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("the overtake case could not open a protocol, so it proves nothing")
	# The room's hearts are gone — the same state the peer who was actually bitten
	# reached — and this peer was not the one bitten. `shared_spent` non-null is
	# what makes this a ROOM rather than solo play, which is the gate the function
	# under test uses.
	room.shared_spent = 3
	player.lives = 0
	player.is_caught = false
	player.call("_check_shared_game_over")
	if player.in_custody_protocol():
		_fail("the room ran out of hearts and this peer stayed in the break-out — the room "
			+ "is now split between an ending screen and a scene, permanently")
	if not player.is_game_over:
		_fail("the room ran out of hearts under the break-out and no ending was raised")
	if BestRunStore.world_archived():
		_fail("a heart the room spent somewhere else archived this world — the scene was "
			+ "overtaken, not lost, and only losing it ends the campaign")
	room.shared_spent = null
	_clear(player)
	await process_frame
	_fresh_store()

	# ---- (e2) the world-level ending, on a peer nothing ever bit -----------
	room.held = "windman"
	room.hand = [TowerGraph.HEROES.find("windman")] as Array[int]
	room.claimable = ""
	player = await _make_player()
	for hero: Variant in TowerGraph.HEROES:
		player.set_hero_captive(String(hero), true)
	await _tick(45)
	if not player.in_custody_protocol():
		_fail("the room ran out of heroes and a peer that was never bitten kept playing — "
			+ "game over is world-level, and this is the only peer that can prove it")
	player.custody_protocol_active = false
	_clear(player)
	room.queue_free()
	terrain.queue_free()
	await process_frame
	_fresh_store()


# ============================================================================
# 18. TWO CLIENTS CANNOT DISAGREE ABOUT THE BREAK-OUT (bead godot-test1-3iy.10)
# ============================================================================

func _check_two_clients_cannot_disagree() -> void:
	"""
	Check 18. The recall clock is the MASTER'S, and so is the outcome it decides.

	THE BUG THIS EXISTS FOR is not a crash, it is two screens telling two players
	different things about the same event. A room-wide protocol with a per-client
	clock gives every peer its own 35 s off its own packets, so a liberation landing
	within a packet's flight of the deadline is a survival on one machine and an
	ARCHIVED WORLD — the campaign over, permanently — on another. Nothing in the
	game would report that; the two players would simply be in different worlds.

	So the assertion is the disagreement itself, staged rather than hoped for: a
	non-master whose OWN clock has run out, handed the master's verdict of SURVIVED.
	The two answers are as far apart as they can be, and the master's has to win.

	  (a) A NON-MASTER DOES NOT DECIDE. Its clock reaches zero and the scene runs
	      on, unarchived — the peer is showing a countdown, not adjudicating one.
	  (b) THE VERDICT IS WHAT ENDS IT, and a SURVIVED verdict over a spent local
	      clock ends the scene as a survival: a scar, and no archive.
	  (c) THE NEGATIVE CONTROL — the same spent clock ON THE MASTER really does
	      decide, and really does archive. Without it, (a) would pass just as
	      happily against a build where the recall clock does nothing at all.
	  (d) THE MASTER PUBLISHES WHAT IT DECIDED, so there is something for (b) to
	      deliver: `custody_wire_state()` carries the verdict after the scene ends.
	"""
	_fresh_store()
	_beat_done()
	var room := RoomStub.new()
	room.add_to_group("mp")
	root.add_child(room)
	room.held = "primm"
	room.hand = [TowerGraph.HEROES.find("primm")] as Array[int]

	# ---- (a) a non-master's spent clock decides nothing ---------------------
	room.master = "somebody_else"
	var player := await _make_player()
	player.set_active_character(TowerGraph.HEROES.find("primm"))
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("check 18 could not open a protocol, so it proves nothing")
		_clear(player)
		room.queue_free()
		await process_frame
		_fresh_store()
		return
	player.custody_timer = 0.0
	await _tick(4)
	if not player.in_custody_protocol():
		_fail("a NON-MASTER ended the break-out on its own clock — every peer runs its own "
			+ "35 s, so a rescue near the wire is a survival on one screen and an archived "
			+ "world on another")
	if BestRunStore.world_archived():
		_fail("a non-master archived the world off its own clock — the campaign is over on "
			+ "one machine and running on the others")

	# ...and it is SHOWING the master's number, not its own. A peer that ignored the
	# published clock would count down from wherever its own scene started and reach
	# zero at a different instant, which is the disagreement one step earlier.
	player.call("apply_room_custody", 9.0, 0)
	if absf(player.custody_timer - 9.0) > 0.05:
		_fail("the master published 9.0 s and this peer is showing %.2f — it is running its "
			% player.custody_timer + "own clock, and two clocks reach zero at two moments")

	# ---- (b) the master's verdict is what ends it --------------------------
	player.call("apply_room_custody", 0.0, 1)
	if player.in_custody_protocol():
		_fail("the master said the room survived and this peer stayed in the scene")
	if BestRunStore.world_archived():
		_fail("the master said SURVIVED and this peer archived the world anyway — the two "
			+ "clients disagree about the outcome, which is the whole thing this owns")
	if not BestRunStore.tower_opened_ids().has(TowerGraph.SCAR_CUSTODY):
		_fail("the master's SURVIVED verdict did not take the scar, so this peer's tower "
			+ "disagrees with the room's for the rest of the campaign")
	_clear(player)
	await process_frame
	_fresh_store()

	# ---- (c) the negative control: the MASTER's clock does decide ----------
	# Re-armed: `_fresh_store()` above wiped the profile, and capture is gated on the
	# authored rescue being in it. Without this the control opens no protocol and
	# reports the failure as if the clock were broken.
	_beat_done()
	room.master = "me"
	room.held = "primm"
	player = await _make_player()
	player.set_active_character(TowerGraph.HEROES.find("primm"))
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("the negative control could not open a protocol")
	player.custody_timer = 0.0
	await _tick(4)
	if player.in_custody_protocol():
		_fail("the MASTER's clock ran out and the scene ran on — claim (a) would pass "
			+ "against a build whose recall clock does nothing at all")
	if not BestRunStore.world_archived():
		_fail("the master's recall completed and the world was not archived")

	# ---- (d) ...and it publishes what it decided ---------------------------
	var wire: Array = player.call("custody_wire_state") as Array
	if wire.size() != 2 or int(wire[1]) != 2:
		_fail("the master decided FAILED and publishes %s — with no verdict on the wire "
			% str(wire) + "there is nothing for the other peers to agree with")
	_clear(player)
	room.queue_free()
	await process_frame
	_fresh_store()


func _inside(point: Vector3, lo: Vector3, hi: Vector3) -> bool:
	"""Is this point inside the confinement box on the two axes it clamps?"""
	return point.x >= lo.x - SETBACK_EPS and point.x <= hi.x + SETBACK_EPS \
		and point.z >= lo.z - SETBACK_EPS and point.z <= hi.z + SETBACK_EPS


## Physics frames to run after a BITE before the prison role can have decided
## anything. The two clocks are sequential and neither is short-circuited here:
## `_tick_prison()` refuses to run at all while `is_caught` (so the life a grab
## costs is always spent first), which is CAUGHT_DURATION, and only then does its
## own PRISON_TICK cadence start. 75 frames at 60 Hz is 1.25 s against 1.05 s of
## clock, so the margin is a quarter of a second rather than a guess.
const POST_BITE_FRAMES: int = 75


func _tick(frames: int) -> void:
	"""Run real physics. The prison role decides on a 0.5 s cadence, so 45 frames
	(0.75 s at 60 Hz) is one decision plus slack when no bite is in the way — see
	`POST_BITE_FRAMES` for when one is."""
	for _i: int in frames:
		await physics_frame


func _drive_into_custody(player: Node) -> void:
	"""
	Take a player's whole roster the way the game does, and let the scene open.

	The last grab goes through `hit_by_crocodile` + `_on_caught_finished` — the real
	entry — so a build whose roster clause still ends the run fails every check that
	calls this instead of quietly measuring a scene it opened itself.
	"""
	var last_one: String = player.hero_name()
	for hero: String in TowerGraph.HEROES:
		if hero != last_one:
			player.captive_heroes[hero] = true
	player.hit_by_crocodile(_hunter())
	player.is_caught = false
	player.call("_on_caught_finished")
	await physics_frame


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
