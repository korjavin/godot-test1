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
##   2. **ATTRIBUTION.** Post-beat, the two GD-SURVEY rows — the field's retrieval
##      unit and the HQ's sentry — take the hero; an animal, a body with no row at
##      all, and a contact that names no attacker take nobody. Keyed on the
##      `captures_hero` ROW KEY and not on `behavior` (bead godot-test1-3iy.19), so
##      the guard arrests without ever joining the hunt arm and the next machine is
##      covered by its row.
##   3. **INVULNERABILITY COVERS THE HERO TOO.** A grab inside any of the four
##      invulnerable states costs nothing — `hit_by_crocodile()`'s early return is
##      the one place that rule lives and the capture must sit under it.
##   4. **THE CYCLE LOSES HIM, AND THE SWITCH IS CLEAN.** E never lands on a
##      captive, E is a refusal when one hero is left, and the body that walks out
##      of the grab carries no transient ability state — the bead's landmine.
##   5. **LIBERATION RESTORES THE INDEX.** `hero_freed()` is the cell block's seam
##      and it must put the hero straight back in the cycle, idempotently.
##   6. **THE LAST FREE HERO ENDS THE RUN**, and since bead godot-test1-0bc it is
##      the ONLY thing that does: hearts are gone, so "nobody left to play" is the
##      whole of the game's failure state and every other contact is a coin bill.
##      Check 17 pins the absence itself, so a reintroduced `lives` fails loudly.
##   7. **THE SET STAYS OUT OF THE MONOTONE STORE.** A capture must not write the
##      profile's tower set: that set is a UNION that can only grow, and a captive
##      folded into it could never be freed.
##   8. **A TOWER STREAMED IN LATER HOLDS HIM.** The field takes heroes where the
##      building is not loaded, so the interior re-seeds its mirror from the player
##      on build — and walking into the cell frees him all the way back into the
##      E-cycle.
##   9. **RESIZE IS NOT A LIFT** (bead godot-test1-3uh). Teibi's giant form is
##      refused wherever the grown capsule would overlap the building — measured
##      inside the real interior against a WALL (on a storey tall enough that its
##      ceiling cannot be the reason) and against a CEILING (on the storey whose
##      clear height is below the giant's own height, where no spot on the floor
##      admits him). The body's storey index must be the same before and after
##      every press, small and giant, because a growth that depenetrates upward is
##      a free lift past every gate `tower_selfcheck`'s softlock audit models. With
##      its negative control: out in the annulus, where 11 m of air stands over
##      him, the same press goes through.
##  17. **THERE IS NO SECOND WAY TO LOSE** (bead godot-test1-0bc). The player
##      declares no `lives` / `MAX_LIVES` / `EXTRA_LIFE_COINS` member at all, so a
##      reintroduced heart model fails here on the day it is typed rather than on
##      the day something starts spending it.
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
## (never added to the tree — `_takes_a_hero()` only ever reads its `spec`), so
## nothing reclaims them but this file.
var _stubs: Dictionary = {}


## A body that names a `spec` row, which is all `_takes_a_hero()` reads of an
## attacker.
##
## THE ROW IS THE REAL ONE, pulled out of `SPECIES` by name rather than written out
## here: the whole point of keying on a row key is that the table decides, so a
## check that typed `{"captures_hero": true}` into a literal would still pass on the
## day the key was renamed and capture had silently stopped firing.
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

	## Where the room's other members are standing, for `_respawn_in_place()`'s
	## relocation. DEFAULTS TO NULL, which is what every check above case (e) needs:
	## null is the solo answer, so a stub that always named a spot would quietly
	## teleport the subject of sixteen other checks off the bite it was measuring.
	var anchor: Variant = null

	func group_anchor() -> Variant:
		return anchor

	func my_hero() -> String:
		return held

	func hero_holder(hero: String) -> String:
		return "me" if held == hero else ""

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

	## NO SHARED-TOTAL STUB LIVES HERE ANY MORE. It used to answer
	## `shared_lives_spent()` for `_check_shared_game_over()`, and both went with the
	## hearts in bead godot-test1-0bc: a room's only shared death state is the
	## room-wide captive set, which the `cap` verb below already carries.


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
	await _check_a_guard_takes_coins_and_ground()
	await _check_the_sweep_spares_a_guard()
	await _check_the_protocol_opens_and_can_be_played()
	await _check_the_break_out_scars_the_world()
	await _check_reassign_first_imprison_last()
	await _check_two_clients_cannot_disagree()
	await _check_the_recall_archives_the_world()
	await _check_the_scene_does_not_leak()
	await _check_resize_is_not_a_lift()
	await _check_air_sight_is_the_indoor_air_rush()
	await _check_no_second_way_to_lose()
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
	Post-beat, WHO TAKES A HERO IS A ROW KEY — `captures_hero` — and nothing else.

	BOTH SIDES OF THE KEY, because either alone is satisfied by a build that has
	stopped reading it. The POSITIVE side is the whole of bead godot-test1-3iy.19:
	both GD-SURVEY rows arrest, and they are the field's retrieval unit (on the
	`hunt` arm) and the HQ's sentry (on `solo`, leashed to its storey), so a
	predicate that had drifted back onto `behavior` passes for the first and fails
	for the second. The NEGATIVE side is every other shape of contact, and the
	three below fail differently: an ordinary predator row (the crocodile), a body
	with no `spec` property at all (a boss projectile, the tower's rotor bar), and
	the plain no-argument call most callers in the codebase make.

	The rows are ENUMERATED FROM THE TABLE, not listed here, so the day a third
	machine opts in it is measured without anybody editing this file — and an
	animal that grew the key by accident fails on the negative half.
	"""
	_beat_done()

	# ---- POSITIVE: every row the table says arrests, really does ----------------
	var table: Dictionary = load(CROC_SCRIPT).get_script_constant_map().get("SPECIES", {})
	var arresting: Array[String] = []
	for name_v: Variant in table:
		if bool((table[name_v] as Dictionary).get("captures_hero", false)):
			arresting.append(String(name_v))
	if not arresting.has(GUARD_SPECIES):
		_fail("SPECIES['%s'] does not carry `captures_hero` — a catch inside the HQ"
			% GUARD_SPECIES + " must imprison the hero like a field grab (owner"
			+ " ruling 2026-09-01)")
	if arresting.size() < 2:
		_fail("only %d row carries `captures_hero` — with one row this check cannot"
			% arresting.size() + " tell the key apart from a `behavior` test")
	for species: String in arresting:
		var taker := await _make_player()
		var hero: String = taker.hero_name()
		taker.hit_by_crocodile(_attacker_row(species))
		if not taker.is_hero_captive(hero):
			_fail("a '%s' grab left %s free, though its row declares `captures_hero`"
				% [species, hero] + " — the predicate is reading something other than"
				+ " the key (the `behavior` arm, most likely)")
		if taker.hero_name() == hero:
			_fail("a '%s' grab did not auto-switch off the captured hero %s"
				% [species, hero])
		_clear(taker)

	# ---- NEGATIVE: and nothing else does ---------------------------------------
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
			_fail(("a '%s' contact took %s — only a row carrying `captures_hero` takes a hero")
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
	An empty free-hero set is THE ONLY THING THAT ENDS FIELD PLAY.

	Since bead godot-test1-0bc there is no second ending to confuse this with:
	hearts are gone, and every contact that used to spend one now pays the
	attacker's `coin_setback` and respawns. So the clause measured here is not one
	ending among two any more — it is the whole of the game's failure state, and a
	build that lost it would be a game nobody can lose.

	THAT CLAUSE OPENS THE FULL-CUSTODY PROTOCOL rather than the Game Over screen
	(bead godot-test1-3iy.11). What is measured here is the CLAUSE; what the scene
	then does is checks 13-16.

	Two things make it a measurement rather than a coincidence, and both are asked
	below: the run's coins are DELIBERATELY LEFT FAT before the grab, so nothing
	about the bank can be what stopped play; and the negative control — three of
	four heroes held — must leave the run alone entirely, or "the clause fired"
	would only mean "something happened".

	DRIVEN ON BOTH ARRESTING ROWS. Since bead godot-test1-3iy.19 a tower guard
	takes the last free hero too, and the ruling's own note is that this is now
	REACHABLE INSIDE THE BUILDING — which is the intent, not a hole: an arrest can
	never end a run, it opens the break-out, and the break-out is played in the
	cell block the guard was standing in.
	"""
	_beat_done()
	var player: Node = null
	for species: String in ["hunter_robot", GUARD_SPECIES]:
		player = await _make_player()
		var last_one: String = player.hero_name()
		for hero: String in TowerGraph.HEROES:
			if hero != last_one:
				player.captive_heroes[hero] = true
		# Coins the setback cannot exhaust: the only reason field play may stop here is
		# the empty roster.
		player.coins_collected = 1000
		player.own_coins = 1000
		player.hit_by_crocodile(_attacker_row(species))
		player.is_caught = false
		player.call("_on_caught_finished")
		if player.coins_collected <= 0:
			_fail("the probe's bank was emptied by the setback, so a coin clause could be"
				+ " what stopped play — this check would prove nothing")
		if not player.in_custody_protocol():
			_fail("a '%s' took the last free hero with %d coins in hand and field play"
				% [species, player.coins_collected] + " went on")
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
		_fail("the run ended with %s still free" % free_one)
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

	# In a room, a captive hero may still have a live lobby holder while that
	# prison-role body is being placed. The cell must not draw a duplicate; once
	# the holder is released, the same captive-set write shows the static body.
	var room := RoomStub.new()
	room.add_to_group("mp")
	room.held = taken
	root.add_child(room)
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("mirror: the tower has no TowerInterior child")
		shell.queue_free()
		room.queue_free()
		_clear(player)
		return
	if not interior.is_captive(taken):
		_fail(("a tower built AFTER a field capture does not hold %s (it holds %s) — the "
			+ "interior must re-seed its mirror from the player, or his cell can never be "
			+ "opened") % [taken, str(interior.captives())])
	_assert_cell_body(interior, taken, false)
	room.held = ""
	interior.set_captive(taken, true)
	_assert_cell_body(interior, taken, true)
	# The authored captive is the TOWER's own staging, not a hero the field took off
	# you, so after the beat he is nobody's captive. Asserted so the re-seed can
	# never quietly become "mirror the whole cell block back onto the roster".
	if taken != TowerInterior.AUTHORED_CAPTIVE \
			and player.is_hero_captive(TowerInterior.AUTHORED_CAPTIVE):
		_fail("the tower's authored staging leaked into the player's captive set")

	# Walk in. Any hero frees any cell, so the body that arrives is whoever we are.
	interior.call("_liberate", taken)
	await process_frame
	_assert_cell_body(interior, taken, false)
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
	room.queue_free()
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
	was null, `_takes_a_hero` answered false, and systemic capture was
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

	# ---- AND THE SAME QUESTION FOR THE BUILDING'S OWN SENTRY ----------------
	# Check 11 hands `hit_by_crocodile` a row stub, so it is indifferent to whether
	# the thing standing in the tower ever reaches that line — the exact
	# indifference that let systemic capture ship unreachable. So: a REAL guard from
	# the shipped scene, its own `_on_player_collision`, and BOTH halves of its
	# stake have to land — the coins and, since bead godot-test1-3iy.19, the hero.
	# A guard is on the `solo` arm, so this is also the one place a LIVE body proves
	# the arrest is keyed on `captures_hero` and not on how the thing steers.
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
	if mark.captive_heroes.size() != 1:
		_fail("a LIVE guard's collision imprisoned %s — with capture armed, a catch"
			% str(mark.captive_heroes.keys()) + " inside the HQ takes exactly the"
			+ " hero who was walking (owner ruling 2026-09-01), and this is the only"
			+ " block that drives it through the shipped collision handler")
	sentry.queue_free()
	_clear(mark)
	await process_frame


# ============================================================================
# 11. THE GUARD'S STAKE — coins like everybody, and the GROUND, which is his alone
# ============================================================================

## What this check starts the player with. Round enough that both expected losses
## are exact (7% of 200 -> 14 for the guard, 10% -> 20 for the crocodile control)
## and big enough that an off-by-one in the arithmetic is visible rather than lost
## in a rounding argument.
const SETBACK_PROBE_COINS: int = 200
## The control's row. An ordinary field predator, on the ordinary path, with a
## `coin_setback` of its own — which since bead godot-test1-0bc is every row in the
## table, and is the reason this check's control had to be rewritten.
const CONTROL_SPECIES: String = "crocodile"

func _check_a_guard_takes_coins_and_ground() -> void:
	"""
	The tower's own stake, ON BOTH SIDES OF THE ARMING GATE — which is what makes
	this one check instead of two, because the guard's two behaviours are the same
	contact told a different thing about the world.

	PRE-BEAT (the first half) IS TODAY'S GUARD, BYTE FOR BYTE: coins plus the
	knockback to the last checkpoint, and no hero. That is not legacy left standing
	— it is required (bead godot-test1-3iy.19). The authored Primm rescue happens
	INSIDE this building, so the first guards a player ever meets are met before the
	scene that teaches capture; a tutorial visit that stripped the roster would be
	the mechanic firing before its own lesson.

	POST-BEAT (the second half) IS THE 2026-09-01 RULING: the same grab imprisons
	the hero exactly as a field hunter's does, and the hero who steps in RESUMES
	WHERE THE PARTY FELL — no knockback, because the survivors "continue to play
	from the same place after cooldown". The coin bill is not waived by the arrest:
	one arithmetic everywhere.

	THE GROUND IS STILL THE BUILDING'S AND NOT THE ROW'S. `_pay_coin_setback()`
	asks the `tower_interior` group for a `setback_point()` and takes it if one
	answers, whoever bit you — the rotor bar, the press, a crocodile that followed
	you through the doorway — and the arrest latch is the ONE thing that waives it.
	In the FIELD nothing answers and nothing relocates. The controls below measure
	exactly that: an animal in the field left standing where it fell, and the same
	animal INSIDE the building knocked back to the plate like everybody else.

	FOUR THINGS ARE MEASURED ON THE PRE-BEAT GUARD AND ALL FOUR ARE SEPARATE
	FAILURES:

	  * the coins: exactly `floor(own_coins x coin_setback)`, off BOTH the displayed
	    figure and this peer's own contribution, read from the ROW rather than from
	    a 0.07 typed in here — retune the row and this check retunes with it;
	  * the run: no game over, which is the ruling itself. It is a weaker claim than
	    it once was (nothing ends a run but the empty roster now) and it is kept
	    because it is free and it is the sentence the owner wrote;
	  * the hero: untaken, WITH THE BEAT UNPLAYED, which is the arming gate seen
	    from inside the building — the one place it decides anything, since the
	    beat itself is a room in here;
	  * the ground: the body is standing on the last checkpoint it lit — and on the
	    doorway instead when it has lit none, which is the other branch of
	    `setback_point()` and would otherwise never be executed by anything.

	And the crocodile controls on the same path, because every one of those
	assertions is also true of a build where `hit_by_crocodile` stopped working
	altogether.
	"""
	# THE BEAT IS UNPLAYED for the first half, and this is the only check in the
	# file that has to un-arm capture after arming it — every check above leaves the
	# id in the store. The second half re-arms before the controls, so what runs
	# after this function sees exactly the world it always did.
	_fresh_store()
	var species: Dictionary = load(CROC_SCRIPT).get_script_constant_map().get("SPECIES", {})
	var row: Dictionary = species.get(GUARD_SPECIES, {})
	var fraction: float = float(row.get("coin_setback", 0.0))
	if fraction <= 0.0:
		_fail("SPECIES['%s'] carries no coin_setback — the guard has no" % GUARD_SPECIES
				+ " arithmetic, so his hit would be free")
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
		# Both stands are DERIVED from the drawing since bd godot-test1-dn8 demolished
		# the keep — `checkpoint_stand()` off the checkpoint room's plan rect, and
		# `entry_stand()` off the shell's doorway — so this reads the functions the
		# game reads and cannot drift from the plates the player is knocked onto.
		var want_spot: Vector3 = interior.global_position + (TowerInterior.checkpoint_stand()
				if lit else TowerInterior.entry_stand())

		var player := await _make_player()
		player.coins_collected = SETBACK_PROBE_COINS
		player.own_coins = SETBACK_PROBE_COINS
		var hero: String = player.hero_name()

		player.hit_by_crocodile(_attacker_row(GUARD_SPECIES))
		player.is_caught = false
		player.call("_on_caught_finished")

		if player.is_game_over:
			_fail("a guard's hit ended the run — the tower is not allowed to game-over"
					+ " the player mid-rescue")
		if player.captive_heroes.has(hero):
			_fail("a PRE-BEAT guard took %s — the authored Primm rescue is a room in" % hero
					+ " this building, so the guards met on the way to it must charge"
					+ " the ordinary tax and nothing more; capture arms at the beat")
		if player.coins_collected != SETBACK_PROBE_COINS - expected_loss:
			_fail("a pre-beat guard's setback left %d of %d displayed coins, expected %d"
				% [player.coins_collected, SETBACK_PROBE_COINS,
					SETBACK_PROBE_COINS - expected_loss])
		if player.own_coins != SETBACK_PROBE_COINS - expected_loss:
			_fail("a pre-beat guard's setback left %d of %d own_coins, expected %d — in a room"
				% [player.own_coins, SETBACK_PROBE_COINS,
					SETBACK_PROBE_COINS - expected_loss]
				+ " that is this peer's contribution to the shared bank")
		if (player as Node3D).global_position.distance_to(want_spot) > SETBACK_EPS:
			_fail("a pre-beat guard's setback left the player at %s, not on the %s at %s"
				% [str((player as Node3D).global_position),
					("checkpoint" if lit else "doorway"), str(want_spot)])
		if not player.is_respawning:
			_fail("a pre-beat guard's setback did not open a grace window — the guard that just"
					+ " hit you gets a free second bite")
		_clear(player)
		shell.queue_free()
		await process_frame

	# ---- POST-BEAT: THE ARREST, AND THE GROUND THAT DOES NOT MOVE -------------
	#
	# The owner ruling of 2026-09-01 in one contact: the hero goes to prison exactly
	# as a field grab sends them, the coins are billed exactly as the row asks, and
	# the hero who steps in is standing where the party fell — "if other characters
	# left not caught they continue to play from the same place after cooldown".
	#
	# THE CHECKPOINT IS DELIBERATELY LIT AND THE BODY IS DELIBERATELY NOWHERE NEAR
	# IT. Without both, "no knockback" is unfalsifiable: an unlit plate or a player
	# already standing on the plate passes a build that relocates on every hit. The
	# stand is the cell block's, which is inside the walls (so `inside_walls()` says
	# yes and the relocation is genuinely one `if` away) and ten storeys above the
	# checkpoint the arrest must NOT drag them to.
	_beat_done()
	var arrest_shell := await _make_tower()
	var arrest_interior := arrest_shell.get_node_or_null("TowerInterior") as TowerInterior
	arrest_shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
	var plate_far: Vector3 = arrest_interior.global_position + TowerInterior.checkpoint_stand()
	var arrested := await _make_player()
	arrested.coins_collected = SETBACK_PROBE_COINS
	arrested.own_coins = SETBACK_PROBE_COINS
	var stood: Vector3 = arrest_interior.global_position + TowerInterior.custody_stand()
	(arrested as Node3D).global_position = stood
	if stood.distance_to(plate_far) <= SETBACK_EPS:
		_fail("the arrest probe is standing on the checkpoint plate — a knockback"
				+ " would move it nowhere and the whole block would be vacuous")
	if not TowerInterior.inside_walls(stood - arrest_interior.global_position):
		_fail("the arrest probe is standing outside the walls, where nothing"
				+ " relocates anybody — the knockback this block asserts is refused"
				+ " would never have fired")
	var arrested_hero: String = arrested.hero_name()
	arrested.hit_by_crocodile(_attacker_row(GUARD_SPECIES))
	arrested.is_caught = false
	arrested.call("_on_caught_finished")
	if not arrested.is_hero_captive(arrested_hero):
		_fail("a post-beat guard left %s free — a catch inside the HQ follows the"
			% arrested_hero + " same procedure as a catch outside it (owner ruling"
			+ " 2026-09-01), so the hero goes to a cell")
	if arrested.hero_name() == arrested_hero:
		_fail("an arrest did not auto-switch off %s — the party plays on, and it"
			% arrested_hero + " cannot play on as the hero in the cell")
	if arrested.coins_collected != SETBACK_PROBE_COINS - expected_loss:
		_fail("an arrest billed %d coins, not the %d the guard's row asks — the"
			% [SETBACK_PROBE_COINS - arrested.coins_collected, expected_loss]
			+ " hero is the stake ON TOP of the bill, never instead of it")
	if arrested.own_coins != SETBACK_PROBE_COINS - expected_loss:
		_fail("an arrest left %d own_coins of %d, expected %d"
			% [arrested.own_coins, SETBACK_PROBE_COINS, SETBACK_PROBE_COINS - expected_loss])
	if (arrested as Node3D).global_position.distance_to(stood) > SETBACK_EPS:
		_fail("an arrest threw the surviving hero from %s to %s — the checkpoint"
			% [str(stood), str((arrested as Node3D).global_position)]
			+ " knockback is refused for a contact that captured, so the party"
			+ " resumes from the same place (and on the storey the cells are on)")
	if not arrested.is_respawning:
		_fail("an arrest opened no grace window — the guard that just took a hero"
				+ " gets the next one for free")
	if arrested.in_custody_protocol() or arrested.is_game_over:
		_fail("an arrest with three heroes still free ended field play")
	if arrested.get("caught_captured"):
		_fail("the arrest latch survived the contact it was set for — the next hit"
				+ " taken indoors would have its knockback waived for free")
	_clear(arrested)
	arrest_shell.queue_free()
	await process_frame

	# ---- THE CONTROLS: an ordinary animal, outside and then inside ------------
	#
	# The bill it is expected to pay is read from its OWN row and must differ from
	# the guard's, or "the two paths charge different amounts" would be satisfied by
	# a build that charges everybody 7%.
	var control_fraction: float = float(species.get(CONTROL_SPECIES, {}).get("coin_setback", 0.0))
	if control_fraction <= 0.0:
		_fail("SPECIES['%s'] carries no coin_setback — the control is not on the" % CONTROL_SPECIES
				+ " ordinary predator path, so the guard branch above proves nothing")
		return
	var control_loss: int = int(floor(float(SETBACK_PROBE_COINS) * control_fraction))
	if control_loss <= 0 or control_loss == expected_loss:
		_fail("a %.3f control setback on %d coins bills %d, the guard's %d — the two"
			% [control_fraction, SETBACK_PROBE_COINS, control_loss, expected_loss]
			+ " arithmetics must be distinguishable or this control measures nothing")
		return

	# (a) IN THE FIELD, WITH THE BUILDING STANDING: the bill lands, the ground does
	#     not move. THE TOWER IS STOOD UP ON PURPOSE, and staging it is the whole
	#     point — `endless_terrain` instances the shell at TOWER_LOAD_RADIUS (360 m)
	#     and never frees it for the rest of the run, so "the player is in the
	#     field" and "the `tower_interior` group answers" are true AT THE SAME TIME
	#     for every bite after the first approach to the HQ. An empty tree measured
	#     only the opening minutes of a run and passed a build that teleported every
	#     death in the world back to the doorway.
	var field_shell := await _make_tower()
	var player_c := await _make_player()
	player_c.coins_collected = SETBACK_PROBE_COINS
	player_c.own_coins = SETBACK_PROBE_COINS
	# A LEG WORTH BANKING. With hearts, the third bite ended the run and
	# `_trigger_game_over()` writing the record was the same event as the player
	# stopping. Heroes being the lives took that away — the only ending left needs
	# all four heroes held AND the break-out lost, which most sessions never reach —
	# so a bite is what replaced the ending as the end of a leg, and it has to bank.
	# Without this the "Best" line and the lobby's record are frozen forever for
	# practically every player, which is invisible in a checkless build.
	player_c.own_distance = SETBACK_PROBE_COINS
	player_c.best_distance = 0
	# Out of the walls and out of every hazard's reach, which is where the field is.
	(player_c as Node3D).global_position = Vector3(4.0 * TowerPlans.PLAN_HALF, 0.0, 0.0)
	var where: Vector3 = (player_c as Node3D).global_position
	player_c.hit_by_crocodile(_attacker_row(CONTROL_SPECIES))
	player_c.is_caught = false
	player_c.call("_on_caught_finished")
	if player_c.is_game_over or player_c.in_custody_protocol():
		_fail("an ordinary bite ended the run — heroes are the lives, and this peer"
				+ " still has all four")
	if player_c.coins_collected != SETBACK_PROBE_COINS - control_loss:
		_fail("a %s's bite left %d of %d displayed coins, expected %d — every row"
			% [CONTROL_SPECIES, player_c.coins_collected, SETBACK_PROBE_COINS,
				SETBACK_PROBE_COINS - control_loss]
			+ " bills its own setback now, so the field path must charge it too")
	if player_c.own_coins != SETBACK_PROBE_COINS - control_loss:
		_fail("a %s's bite left %d of %d own_coins, expected %d"
			% [CONTROL_SPECIES, player_c.own_coins, SETBACK_PROBE_COINS,
				SETBACK_PROBE_COINS - control_loss])
	if (player_c as Node3D).global_position.distance_to(where) > 1.0:
		_fail("a %s's bite in the FIELD relocated the player — the knockback is gated"
			% CONTROL_SPECIES + " on standing INSIDE the walls, not on the tower node"
			+ " existing, or every death in the world teleports to the HQ once the"
			+ " shell has streamed in")
	if not player_c.is_respawning:
		_fail("a %s's bite in the field opened no grace window" % CONTROL_SPECIES)
	if player_c.best_distance != SETBACK_PROBE_COINS:
		_fail("a bite banked no record (best_distance %d, ran %d) — with no hearts the"
			% [player_c.best_distance, SETBACK_PROBE_COINS]
			+ " run no longer ENDS at a bite, so banking only at game over leaves a"
			+ " whole session unwritten to best_run.cfg, localStorage and the lobby")
	# ...and the FLASH survives its own banking. The bite above raised
	# best_distance to own_distance, so the ending panel re-deriving
	# `own_distance > best_distance` reads false on exactly the runs that earned
	# "NEW BEST!". The latch is what it reads instead; the second call here is the
	# negative control — it must report no fresh record while the latch holds.
	if not player_c.run_beat_record:
		_fail("a record-setting bite left run_beat_record false — the ending's"
			+ " NEW BEST flash reads the latch, so this is the flash going dark")
	if player_c.call("_bank_records"):
		_fail("banking twice reported a SECOND fresh record — best_distance was"
			+ " already raised to own_distance, so this assertion is measuring"
			+ " nothing and the latch above is untested")
	if not player_c.run_beat_record:
		_fail("a repeat bank cleared run_beat_record — the latch is per RUN, and"
			+ " only the two places that wipe own_distance may clear it")
	# ...and a LATE LOBBY REPLY reconciles it AT THE ENDING. The store answers
	# asynchronously, so a bite early in a run banks against whatever had loaded by
	# then (0, if the lobby leg is still in flight) — a record this run never beat
	# has to take the flash back with it, or the ending claims a best the player's
	# other device already holds.
	#
	# Driven on `server_best_distance`, the store's PRE-MERGE server number, which
	# is the whole point of that field existing: the emitted/merged value contains
	# this run's own banked distance by now, so it cannot tell an echo of our own
	# submission from another device's record. A reconciliation reading the merged
	# number is wrong in one direction or the other whichever comparison it picks.
	var probe_store: BestRunStore = player_c.best_run_store
	if probe_store == null:
		_fail("the player built no BestRunStore — the record latch has nothing to"
			+ " reconcile against and the assertions below measure nothing")
		return
	probe_store.server_best_distance = 0
	player_c.call("_reconcile_record_latch")
	if not player_c.run_beat_record:
		_fail("an unreachable lobby (no server record at all) cleared"
			+ " run_beat_record — 0 outranks nothing and the local comparison stands")
	probe_store.server_best_distance = SETBACK_PROBE_COINS - 1
	player_c.call("_reconcile_record_latch")
	if not player_c.run_beat_record:
		_fail("a server record BELOW this run's distance cleared run_beat_record —"
			+ " the run really is ahead of it, so the flash was earned")
	# THE TIE is the case a merged-value reconciliation cannot see at all: a server
	# already holding exactly this distance raises nothing, so `loaded` never fires
	# — and the run matched a record rather than setting one.
	probe_store.server_best_distance = SETBACK_PROBE_COINS
	player_c.call("_reconcile_record_latch")
	if player_c.run_beat_record:
		_fail("a server record EQUAL to this run's distance left run_beat_record set"
			+ " — the run TIED the record another device holds and beat nothing, so"
			+ " the ending would flash NEW BEST for a number it only matched")
	player_c.run_beat_record = true
	probe_store.server_best_distance = SETBACK_PROBE_COINS + 1
	player_c.call("_reconcile_record_latch")
	if player_c.run_beat_record:
		_fail("a server record ABOVE this run's distance left run_beat_record set —"
			+ " the ending would flash NEW BEST for a record another device holds")
	# ...and a COIN-ONLY store emission still leaves it alone. `BestRunStore` emits
	# `loaded` on distance OR coins, and the bank above already submitted this
	# run's distance, so such a reply carries a distance EQUAL to own_distance by
	# construction — the echo that a `>=` reconciliation on the emitted value used
	# to eat the earned flash with.
	probe_store.server_best_distance = 0
	player_c.run_beat_record = true
	player_c.call("_on_best_run_loaded", SETBACK_PROBE_COINS, SETBACK_PROBE_COINS * 10)
	if not player_c.run_beat_record:
		_fail("a coin-only store emission cleared run_beat_record — it echoes this"
			+ " run's own banked distance back and beat nothing the run did not")
	player_c.run_beat_record = true  # ...and back, for the join_at check below.

	# ...and the BASELINE ITSELF refuses a reply that raced our own submission.
	# Everything above assumes `server_best_distance` holds another device's
	# number, and the two `HTTPRequest` nodes are exactly what can break that: the
	# boot GET and a bite's POST overlap by design, the lobby serves them
	# concurrently, and a POST merged first makes the GET reply an echo of this
	# run. Driven on the store's own reply handler with a synthetic 200 body — the
	# leg the assignments above deliberately skip.
	# The body carries the store's OWN merged numbers, so `server_is_behind` reads
	# false and the handler fires no catch-up POST — a self-check may not talk to
	# the real lobby. Distance is this run's, which is the echo being modelled.
	var echo_distance: int = maxi(SETBACK_PROBE_COINS, probe_store.distance)
	var echo_body := JSON.stringify({
		"distance": echo_distance,
		"coins": probe_store.coins,
		"lifetime": probe_store.lifetime_coins,
		"spent": probe_store.spent_points,
	}).to_utf8_buffer()
	probe_store.server_best_distance = 0
	probe_store.set("_get_in_flight", true)
	probe_store.set("_get_baseline_ok", false)  # ...as a POST inside the window leaves it.
	probe_store.call(
		"_on_get_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), echo_body
	)
	if probe_store.server_best_distance != 0:
		_fail("a /best GET reply that a POST had already raced was recorded as a"
			+ " pre-existing server record (server_best_distance %d)"
			% probe_store.server_best_distance
			+ " — that number is this run's own bank coming back, and the ending"
			+ " would take away a NEW BEST the player earned")
	if probe_store.get("_get_in_flight"):
		_fail("the GET reply left its own request in flight — the next POST would"
			+ " retire a baseline that no longer exists and every later boot would"
			+ " report no server record at all")
	# The control: an unraced reply is exactly what the field is for.
	probe_store.set("_get_in_flight", true)
	probe_store.set("_get_baseline_ok", true)
	probe_store.call(
		"_on_get_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), echo_body
	)
	if probe_store.server_best_distance != echo_distance:
		_fail("an unraced /best GET reply recorded no server record"
			+ " (server_best_distance %d)" % probe_store.server_best_distance
			+ " — the guard above ate the case it exists to protect and the"
			+ " reconciliation can never fire")
	probe_store.server_best_distance = 0

	# ...and it does not outlive the distance it is derived from. `join_at()` is
	# the OTHER place own_distance and run_distance restart at zero (a mid-run
	# join to a room), and a latch left standing across it flashes "NEW BEST!"
	# over a room leg that started at zero and beat nothing.
	player_c.call("join_at", where)
	if player_c.run_beat_record:
		_fail("joining a room left run_beat_record set — join_at() zeroes the very"
			+ " distance the latch records having beaten, so the ending would claim"
			+ " a record for a leg that ran from zero")
	_clear(player_c)
	field_shell.queue_free()
	await process_frame

	# (b) INSIDE THE BUILDING, same animal, same row: the plate takes it too. This
	#     is the assertion that keeps the docstring honest — the knockback is the
	#     BUILDING's rule and not the guard's key, and reading it the other way is
	#     what would have somebody "fix" the field's rotor bar into a free hit.
	var shell_c := await _make_tower()
	var interior_c := shell_c.get_node_or_null("TowerInterior") as TowerInterior
	(shell_c.get("opened") as Dictionary).erase(TowerInterior.GATE_CHECKPOINT)
	var plate: Vector3 = interior_c.global_position + TowerInterior.entry_stand()
	var indoors := await _make_player()
	indoors.coins_collected = SETBACK_PROBE_COINS
	indoors.own_coins = SETBACK_PROBE_COINS
	indoors.hit_by_crocodile(_attacker_row(CONTROL_SPECIES))
	indoors.is_caught = false
	indoors.call("_on_caught_finished")
	if indoors.coins_collected != SETBACK_PROBE_COINS - control_loss:
		_fail("a %s's bite indoors billed %d, not the %d its own row asks — the tower"
			% [CONTROL_SPECIES, SETBACK_PROBE_COINS - indoors.coins_collected, control_loss]
			+ " is charging the guard's rate for somebody else's bite")
	if (indoors as Node3D).global_position.distance_to(plate) > SETBACK_EPS:
		_fail("a %s's bite inside the HQ left the player at %s, not on the doorway plate"
			% [CONTROL_SPECIES, str((indoors as Node3D).global_position)]
			+ " at %s — the checkpoint is the BUILDING's, so it must catch every hit"
			% str(plate) + " taken in here, not only a guard's")
	_clear(indoors)

	# (c) ...AND THE ONE PLACE INSIDE THE BUILDING WHERE IT MUST NOT. During the
	#     break-out the party stands in a SEALED cell block with containment raised
	#     and the recall on the clock, so a knockback to the doorway plate is not a
	#     setback — it is the scene lost to a survivable hazard, with every spine
	#     door shut behind it. The block's own press bills through this path
	#     (`hit_by_crocodile()` with nobody named), so this is reachable play and
	#     not a hypothetical. The COIN bill still lands: only the ground is frozen.
	var caught := await _make_player()
	caught.coins_collected = SETBACK_PROBE_COINS
	caught.own_coins = SETBACK_PROBE_COINS
	caught.custody_protocol_active = true
	var held: Vector3 = interior_c.global_position + TowerInterior.custody_stand()
	(caught as Node3D).global_position = held
	caught.hit_by_crocodile()
	caught.is_caught = false
	caught.call("_on_caught_finished")
	# `player_controller.gd` carries no `class_name`, so its consts are read the way
	# every other check in this file reads one: off the script's constant map.
	var default_fraction: float = float((caught.get_script() as GDScript)
			.get_script_constant_map().get("DEFAULT_COIN_SETBACK", 0.0))
	if caught.coins_collected != SETBACK_PROBE_COINS - int(floor(
			float(SETBACK_PROBE_COINS) * default_fraction)):
		_fail("a hazard during the break-out billed %d coins, not the default"
			% (SETBACK_PROBE_COINS - caught.coins_collected)
			+ " — the bill is universal even where the knockback is refused")
	if (caught as Node3D).global_position.distance_to(held) > 1.0:
		_fail("a hazard during the break-out threw the player from %s to %s — out of"
			% [str(held), str((caught as Node3D).global_position)]
			+ " a SEALED block with the recall running, which loses the scene and"
			+ " archives the world for one press the player was meant to survive")
	caught.custody_protocol_active = false
	_clear(caught)

	# (d) AND THE SECOND PLACE, one storey further on: a BENCHED peer. A prisoner
	#     stands in a cell on storey 9, which is inside the walls, so a guard's bite
	#     or the block's press would knock them to the plate ten storeys below —
	#     and `_confine_to_block()` clamps x and z but deliberately NOT y, so the
	#     next physics frame drags them back into the block's column at ground
	#     level, under the block, with no ramp inside the clamp. The role is then
	#     unplayable for the rest of the run: they can free no cellmate and work no
	#     purge, which is the only way their hero comes back. `_respawn_in_place()`
	#     already carries this refusal for the same reason; the bill still lands.
	var benched := await _make_player()
	benched.coins_collected = SETBACK_PROBE_COINS
	benched.own_coins = SETBACK_PROBE_COINS
	benched.prisoner_active = true
	var cell: Vector3 = interior_c.global_position \
			+ TowerInterior.cell_stand(TowerGraph.HEROES[0])
	(benched as Node3D).global_position = cell
	benched.hit_by_crocodile(_attacker_row(CONTROL_SPECIES))
	benched.is_caught = false
	benched.call("_on_caught_finished")
	if benched.coins_collected != SETBACK_PROBE_COINS - control_loss:
		_fail("a %s's bite on a benched peer billed %d, not the %d its row asks"
			% [CONTROL_SPECIES, SETBACK_PROBE_COINS - benched.coins_collected,
				control_loss]
			+ " — only the knockback is refused for a prisoner, never the bill")
	if (benched as Node3D).global_position.distance_to(cell) > 1.0:
		_fail("a %s's bite threw a benched peer from its cell at %s to %s — the"
			% [CONTROL_SPECIES, str(cell), str((benched as Node3D).global_position)]
			+ " checkpoint plate is ten storeys below the block, and _confine_to_block()"
			+ " clamps x/z only, so the role is stranded under the block for good")
	benched.prisoner_active = false
	_clear(benched)
	shell_c.queue_free()
	await process_frame


# ============================================================================
# 12. THE RESPAWN SWEEP MUST NOT EAT THE BUILDING'S POPULATION
# ============================================================================

func _check_the_sweep_spares_a_guard() -> void:
	"""
	`clear_nearby_crocodiles()` FREES bodies, and a guard must not be one of them.

	THIS IS NOT ABOUT A GUARD'S OWN BITE. Every other way to lose inside the tower
	routes through the ordinary respawn — the rotor bar, the block's press, a
	crocodile that followed you in through the doorway — and that path sweeps a
	25 m radius, which from anywhere in a 17.6 m building is the WHOLE floor. Left
	unexempted, dying to the rotor is the cheapest way to clear a guarded room, and
	the population comes back at the next doorway crossing rather than never — so
	the bug is invisible in the code and obvious at the keyboard.

	Driven on REAL bodies from the shipped scenes, because the exemption is a row
	read (`sweep_exempt`) on a live `spec`: a stub would prove the branch compiles
	and nothing about whether the thing standing in the tower carries the key. The
	key is the guard's OWN and says its own name — it used to be inferred from
	`coin_setback` being non-zero, which stopped naming anything the day every row
	in the table grew one (bead godot-test1-0bc).

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
			or not bool(guard.spec.get("sweep_exempt", false)):
		_fail("the probe guard did not resolve the '%s' row — check 12 would be"
			% GUARD_SPECIES + " measuring a crocodile that happens to be exempt")
	if bool(croc.spec.get("sweep_exempt", false)):
		_fail("the control crocodile carries sweep_exempt — the exemption has spread"
				+ " past the building's own furniture and the sweep frees nothing")

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

	if player.is_game_over:
		_fail("the last free hero was taken and the run ENDED on a screen — the roster "
				+ "clause must open the full-custody protocol, which is the run's one "
				+ "remaining chance to get somebody back")
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

	# ...AND THE CLOCK IS THE ONLY THING THAT CAN LOSE IT. There used to be a second
	# way out of the block — the last heart, spent inside it — and bead
	# godot-test1-0bc deleted the concept, so the case that measured it is now the
	# opposite assertion: a bite in the cell block is SURVIVABLE, and the run must
	# come out of it still in the scene with its clock still running.
	#
	# That is not a formality. Inside the break-out `free_hero_count()` is pinned at
	# 0 (it is how the scene's outcome test knows nobody has been let out yet), so
	# every bite in here reaches the roster clause in `_on_caught_finished()` and
	# only the `custody_protocol_active` guard keeps it from re-entering the
	# protocol — which would swallow the respawn, the grace window and the ability
	# reset, and hand the guard that just hit you a free second hit.
	_fresh_store()
	_beat_done()
	var bitten := await _make_player()
	await _drive_into_custody(bitten)
	if not bitten.in_custody_protocol():
		_fail("archive: no protocol to be bitten inside")
		_clear(bitten)
		_fresh_store()
		return
	var clock_before: float = bitten.custody_timer
	bitten.coins_collected = SETBACK_PROBE_COINS
	bitten.own_coins = SETBACK_PROBE_COINS
	bitten.hit_by_crocodile(_hunter())
	bitten.is_caught = false
	bitten.call("_on_caught_finished")
	if not bitten.in_custody_protocol():
		_fail("a bite inside the block closed the scene — heroes are the lives, and a"
				+ " grab in here takes a hero who is already in a cell")
	if bitten.is_game_over:
		_fail("a bite inside the block ended the campaign — the recall clock is the only"
				+ " way to lose the break-out")
	if BestRunStore.world_archived():
		_fail("a bite inside the block archived the world")
	if bitten.coins_collected >= SETBACK_PROBE_COINS:
		_fail("a bite inside the block cost nothing — the coin bill is the stake in here"
				+ " too, and without it the scene has no cost at all")
	if not bitten.is_respawning:
		_fail("a bite inside the block opened no grace window — the roster clause"
				+ " swallowed the respawn and the next hit lands free")
	# ...and the clock kept running rather than being reset or stopped by the hit.
	if bitten.custody_timer > clock_before:
		_fail("a bite inside the block put %.2f s back on a %.2f s recall clock"
			% [bitten.custody_timer, clock_before])
	_clear(bitten)
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
	  (e) THE ENDING, from both sides. The grab that takes the room's LAST hero
	      still pays its bill and gets its full freeze — the bench tick polls at
	      0.5 s and the freeze runs 0.55 s, so a tick that did not stand aside for
	      it would open the protocol first, clear `is_caught` under
	      `_on_caught_finished()` and make the final grab free. Since bead
	      godot-test1-0bc the bill is COINS rather than a heart, which is what that
	      assertion is now read off. And a peer that was never bitten at all still
	      ends its run when the ROOM runs out, which is the world-level reading and
	      the only part of it no other check can see. Last, the two roles are
	      MUTUALLY EXCLUSIVE: the scene opened from a bite on a peer already in a
	      cell drops the prison role, because the bench tick — the only other way in,
	      and the only one that ever remembered to — cannot run inside the scene to
	      drop it later.

	THERE IS NO (f) ANY MORE. It measured the room's shared HEARTS overtaking a
	running break-out, and bead godot-test1-0bc deleted the shared-heart machine
	along with the concept: a room's only shared death state is the captive set,
	which is what opens the scene rather than something that can outrank it. The
	OVERTAKEN verdict went with it — `_end_custody_protocol()` has two outcomes and
	the wire's `co` is bounded at 2, because a verdict no master can send is a
	branch no peer can reach.
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
	var pad := TerrainStub.SITE + TowerInterior.purge_pad()
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
	# ONE TICK FIRST, so the interior has bound `_player`. `_liberate()` reaches the
	# player through that reference and it is written in `_process` — without this,
	# every liberation below quietly tells nobody and the claims about what the room
	# is (and is not) told would pass against any code at all.
	interior._process(0.1)
	if interior._player != player:
		_fail("the interior did not bind the player, so nothing below can measure the seam")
	interior.set_captive("primm", true)
	interior.call("_on_cell_enter", player, "primm")
	if not interior.is_captive("primm"):
		_fail("a prisoner walked into their OWN cell and freed themselves — the role has a "
			+ "solo escape, which is the one thing the owner's ruling forbids it")
	room.reported.clear()
	interior.set_captive("teibi", true)
	interior.call("_on_cell_enter", player, "teibi")
	if interior.is_captive("teibi"):
		_fail("a prisoner could not free a CELLMATE — the refusal above is refusing every "
			+ "liberation, and the block's second system does nothing")
	# ...AND A LIBERATION OF SOMEBODY THE ROOM NEVER HELD IS NOT REPORTED. The tower
	# calls `hero_freed()` for its AUTHORED staging too, which no player ever had
	# taken off them. Telling the room leaves a release tombstone on a hero nobody
	# captured, and the very next thing that rescue enables is hunter captures — so
	# a real grab of that hero seconds later is dropped as a stale packet and the
	# room never hears about it.
	if not room.reported.is_empty():
		_fail("freeing a hero the room does not hold was reported as a release (%s) — the "
			% str(room.reported) + "tombstone that leaves swallows the next real capture of him")
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

	# ---- (e1) the last grab still pays its bill ----------------------------
	#
	# THE RACE, not the arithmetic: the bench tick polls every 0.5 s and the caught
	# freeze runs 0.55 s, so a tick that did not stand aside while `is_caught` would
	# open the protocol first and clear the freeze out from under
	# `_on_caught_finished()`, making the grab that ends the run the one grab in the
	# game that costs nothing. Read off the COINS since bead godot-test1-0bc — the
	# bill is the only thing a contact takes now, so it is also the only witness
	# that the freeze ran to completion.
	room.held = "phoboman"
	var last_index: int = TowerGraph.HEROES.find("phoboman")
	room.hand = [last_index] as Array[int]
	room.claimable = ""
	player = await _make_player()
	player.set_active_character(last_index)
	for hero: Variant in TowerGraph.HEROES:
		if String(hero) != "phoboman":
			player.set_hero_captive(String(hero), true)
	player.coins_collected = SETBACK_PROBE_COINS
	player.own_coins = SETBACK_PROBE_COINS
	player.hit_by_crocodile(_hunter())
	await _tick(POST_BITE_FRAMES)
	if player.coins_collected >= SETBACK_PROBE_COINS:
		_fail("the grab that took the room's last hero cost nothing — the bench tick "
				+ "outran the caught freeze and `_on_caught_finished()` never got to "
				+ "settle the bill")
	if not player.in_custody_protocol():
		_fail("the room's last hero was taken and the protocol did not open")
	player.custody_protocol_active = false
	_clear(player)
	await process_frame

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
	await process_frame

	# ---- (e3) the bench and the break-out cannot both be running -----------
	#
	# THE OTHER DOOR INTO THE SCENE. `_tick_prison()` drops the prison role before it
	# opens the protocol, but the roster clause in `_on_caught_finished()` is reached
	# from a BITE and not from that tick — and a benched peer is exactly who is
	# standing in the block when the room's last hero falls. Left standing the role
	# can never be cleared (the tick returns above every decision while the protocol
	# runs) and `_confine_to_block()` clamps to the gallery and its cells, which is
	# the far side of the spine wall from the service corridor `custody_stand()`
	# marches the party into: the party is dragged into a cell, which is a
	# liberation, so the scene is won on frame one and pays its permanent scar.
	room.reported.clear()
	room.reassignments = 0
	room.held = "primm"
	room.hand = [mine] as Array[int]
	room.claimable = ""
	player = await _make_player()
	player.set_active_character(mine)
	player.hit_by_crocodile(_hunter())
	await _tick(POST_BITE_FRAMES)
	if not player.prisoner_active:
		_fail("(e3) could not bench the peer, so the overlap it measures was never staged")
	# The grace window from that first bite is staging, not the subject — cleared so
	# the second bite is the one this case is about.
	player.is_respawning = false
	player.respawn_blink_timer = 0.0
	# The room runs out from under a peer already in a cell AND the bite lands in the
	# same frame: the window the bench's own 0.5 s poll cannot cover.
	for hero: Variant in TowerGraph.HEROES:
		player.set_hero_captive(String(hero), true)
	player.hit_by_crocodile(_hunter())
	await _tick(POST_BITE_FRAMES)
	if not player.in_custody_protocol():
		_fail("(e3) the room emptied under a benched peer and the break-out never opened")
	if player.prisoner_active:
		_fail("the break-out opened over a live prison role — nothing can clear it now, "
			+ "and its confinement clamp owns the body for the whole scene")
	await _tick(4)
	var stand: Vector3 = TerrainStub.SITE + TowerInterior.custody_stand()
	var drift := Vector2(player.global_position.x - stand.x,
			player.global_position.z - stand.z).length()
	if drift > SETBACK_EPS:
		_fail("the break-out's party was pulled %.2f m off the service corridor (at %s, "
			% [drift, player.global_position] + "stand %s) — through the spine wall and "
			% stand + "into a cell, which wins the scene it just opened")
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
	  (e) AND A SURVIVABLE BITE INSIDE THE SCENE STAYS INSIDE IT. The room's group
	      anchor is the one thing that can move a body out of a sealed cell block,
	      and only a room has one — so this is the disagreement's other half: the
	      clock decides the scene, and nothing else may hand it a verdict by
	      teleporting the party somewhere they cannot come back from.
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

	# ...and a verdict never speaks for the NEXT round. The roster is full again and
	# this peer's own scene has not opened yet (the bench polls at 2 Hz), so what it
	# publishes in that window would otherwise be the LAST round's answer beside a
	# full-custody set — read by a peer already inside the new scene as an instant
	# success, containment down and all.
	# Staged exactly: the LAST round survived, the corporation has everybody again,
	# and the run is still going. That is the only state in which a latched verdict
	# is somebody else's answer — and no single verdict produces it, so the three
	# facts are set directly rather than driven through one.
	_fresh_store()
	_beat_done()
	_clear(player)
	await process_frame
	player = await _make_player()
	for hero: String in TowerGraph.HEROES:
		player.captive_heroes[hero] = true
	player.custody_verdict = 1
	if player.is_game_over or player.free_hero_count() != 0 or player.in_custody_protocol():
		_fail("the stale-verdict window was not staged, so it proves nothing")
	var window: Array = player.call("custody_wire_state") as Array
	if window.size() != 2 or int(window[1]) != 0:
		_fail("with the roster full and no scene open this peer publishes verdict %s — the "
			% str(window) + "last round's answer, beside this round's set")
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
	await process_frame
	_fresh_store()

	# ---- (e) A SURVIVABLE BITE INSIDE THE SCENE DOES NOT LEAVE THE BLOCK ----
	# The scene is a SEALED room on a clock: `begin_lockdown()` re-shuts every spine
	# door and there is no way back up ten storeys. `_pay_coin_setback()` refuses the
	# checkpoint knockback for exactly that reason and hands the body to
	# `_respawn_in_place()` — which, IN A ROOM, relocates to the group anchor and
	# whose `_place_near()` discards Y outright, dropping the party's last hope at
	# JOIN_SPAWN_HEIGHT with the recall still running. That is a survivable hazard
	# (a guard, the press, a rotor bar) deciding a run, which is the one thing bead
	# godot-test1-0bc says nothing but the clock may do.
	#
	# Solo cannot see it — `group_anchor()` answers null — so the room stub names a
	# spot, which is what makes this a room-shaped check and not a repeat of 13.
	_beat_done()
	room.master = "me"
	room.held = "primm"
	room.anchor = Vector3(600.0, 0.0, 600.0)
	player = await _make_player()
	player.set_active_character(TowerGraph.HEROES.find("primm"))
	await _drive_into_custody(player)
	if not player.in_custody_protocol():
		_fail("case (e) could not open a protocol, so it proves nothing")
	else:
		var stood: Vector3 = player.global_position
		player.hit_by_crocodile(_hunter())
		player.is_caught = false
		player.call("_on_caught_finished")
		await physics_frame
		# Read on X/Z, the axes the relocation actually crosses. Y is left out on
		# purpose: the body is a `CharacterBody3D` settling under gravity, so it
		# drifts a few thousandths between frames while standing perfectly still,
		# and a jump to `JOIN_SPAWN_HEIGHT` is a whole 600 m of X and Z anyway.
		var moved: float = Vector2(stood.x, stood.z).distance_to(
				Vector2(player.global_position.x, player.global_position.z))
		if moved > SETBACK_EPS:
			_fail("a survivable bite inside the running break-out moved the body %.2f m "
				% moved + "from %s — in a room the respawn relocates to the group "
				% str(stood) + "anchor and _place_near() throws Y away, so the party "
				+ "lands under a locked-down building and the clock they cannot beat "
				+ "archives the world")
		if not player.in_custody_protocol():
			_fail("a survivable bite ended the break-out — the recall clock is the scene's "
				+ "only failure condition")
	room.anchor = null
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


# ============================================================================
# 9. RESIZE IS NOT A LIFT
# ============================================================================

## How far the wall subject stands off the wall it is tested against: touching it,
## so the NORMAL capsule is clear and the GIANT one is not. `EPS`-sized, because a
## bigger gap would let the giant fit and a smaller one would bury the normal body.
const RESIZE_WALL_GAP: float = 0.02

## How far the ceiling subject stands off the nearest wall: enough that the giant
## capsule cannot be touching it, so the only thing left to refuse the growth is
## the lid. See `_check_resize_is_not_a_lift` for why the ARITHMETIC is what
## actually isolates it.
const RESIZE_CEILING_GAP: float = 0.3

## How hard, and for how many physics frames, a subject leans on the wall it was
## parked against after each press. See `_shove()` for why leaning is what makes
## the storey-index assertion a measurement rather than a formality; the speed is
## a walk, not a stunt.
const RESIZE_SHOVE_FRAMES: int = 30
const RESIZE_SHOVE_SPEED: float = 5.0

## Where the negative control stands, as interior-local XZ on the storey the check
## picked for its WALL subject — the one whose clear height is over the giant's
## height, so a spot with nothing beside it is a spot he fits in.
##
## IT USED TO BE THE ANNULUS ON FLOOR 0, under the 11 m of air the keep's mezzanine
## left over the ground floor. Bead `godot-test1-dn8` demolished the keep and drew
## floors 0 and 1 as full plates, so the ground storey has a 4.20 m lid everywhere
## and admits a giant NOWHERE — the control had to move to a storey that is tall,
## not to a corner of one that is short. Several spots are tried in turn because
## every planned storey has partitions in it.
const RESIZE_OPEN_SPOTS: Array[Vector2] = [
	Vector2(20.0, 20.0), Vector2(-20.0, 20.0),
	Vector2(20.0, -20.0), Vector2(-20.0, -20.0),
	Vector2(10.0, 10.0), Vector2(-10.0, 10.0),
	Vector2(10.0, -10.0), Vector2(-10.0, -10.0),
	Vector2(30.0, 0.0), Vector2(-30.0, 0.0),
	Vector2(0.0, 30.0), Vector2(0.0, -30.0),
]


func _check_resize_is_not_a_lift() -> void:
	"""
	Check 9. TEIBI'S RESIZE IS A DISGUISE AND A WEAPON, NEVER A STAIRCASE.

	THE BUG (owner playtest, bead godot-test1-3uh): growing inside geometry buries
	the grown capsule in it, and the physics server's depenetration then squirts the
	body out along the shallowest axis — which, standing against an interior wall
	under a storey that is barely taller than the giant, is UP. Resize became a free
	lift onto the next floor, which does not merely skip a gate: it falsifies
	`tower_selfcheck`'s whole 15-subset softlock audit, because the graph says a
	route is gated and the body says it is not.

	TWO ASSERTIONS, AND THEY ARE NOT THE SAME CLAIM. The one that BITES is that the
	growth is refused: strip the gate and the six failures below name both subjects.
	The one that matters is the STOREY INDEX — every press is followed by real
	physics frames, leaning on the wall (see `_shove()`), and then
	`TowerInterior.current_floor()`, the same function the interior's visibility
	window uses to decide what floor the player is on. Stated honestly: headless,
	with the gate removed, the growth goes through but the pop does not reproduce —
	`move_and_slide` finds the horizontal way out of these two spots. So the storey
	index is here as the INVARIANT the fix exists to preserve and as the guard
	against a future "shove him somewhere he fits" fix that moves the body, not as a
	reproduction of the owner's playtest.

	THE TWO CAUSES ARE ISOLATED BY ARITHMETIC, not by hoping the placement missed
	something. The subjects are chosen off the shipped numbers:

	  * WALL — a storey whose clear height is ABOVE the giant's own height, so its
	    ceiling provably cannot be what refuses the growth. Only the wall he is
	    touching can be.
	  * CEILING — the storey whose clear height is BELOW the giant's height, where
	    NO spot on the floor admits him however far from a wall he stands. That
	    number is the isolation; the standoff only keeps the picture honest.

	AND SINCE bead godot-test1-xdf THERE IS A SECOND, DESIGN REFUSAL OVER THE TOP OF
	BOTH: the owner ruled that Teibi may not be giant anywhere inside the HQ, so the
	dial answers "INDOOR" throughout the building and `_teibi_grow_blocked()` — still
	unweakened, and still the whole of the refusal outdoors — is asked DIRECTLY above
	rather than through its label. Three subjects follow from that:

	  * the two above, where both gates agree and the arithmetic says which physical
	    one would have fired;
	  * the middle of an empty tall room, where the physical gate provably answers
	    "it fits" and the refusal is the ruling alone;
	  * and THE DOOR — a giant grown outside and walked in must revert on the
	    threshold, because the press is not the only way the state can arrive.

	The control moved OUTDOORS with the ruling: three shell-widths from the site the
	same two presses must still make a giant, or a gate that always refuses would
	pass every assertion above and quietly delete the ability.
	"""
	var tower := await _make_tower()
	var interior: Node3D = get_first_node_in_group("tower_interior")
	if interior == null:
		_fail("the tower built no interior — check 9 has nothing to stand in")
		tower.queue_free()
		return
	var player := await _make_player()
	if not _become(player, "teibi"):
		_fail("player.tscn has no teibi in CHARACTERS — check 9 cannot drive Resize")
		_clear(player)
		tower.queue_free()
		return

	# The giant body, off the shipped capsule and the shipped scale.
	if player.collision_shape == null or not (player.collision_shape.shape is CapsuleShape3D):
		_fail("player.tscn's collider is not a CapsuleShape3D — check 9 cannot size a giant")
		_clear(player)
		tower.queue_free()
		return
	var capsule: CapsuleShape3D = player.collision_shape.shape as CapsuleShape3D
	var scale_big: float = player.TEIBI_SCALE_BIG
	var giant_height: float = capsule.height * scale_big
	var giant_radius: float = capsule.radius * scale_big

	# Pick the two storeys by the arithmetic that isolates each cause.
	var wall_floor := -1
	var ceiling_floor := -1
	for f: int in TowerPlans.floors():
		var clear: float = TowerInterior.plan_clear_height(f)
		if clear > giant_height and wall_floor < 0:
			wall_floor = f
		if clear < giant_height and ceiling_floor < 0:
			ceiling_floor = f
	print("giant capsule %.2f m tall, %.2f m radius; wall storey %d, ceiling storey %d" % [
		giant_height, giant_radius, wall_floor, ceiling_floor])
	if wall_floor < 0:
		_fail("no planned storey is taller than the giant — check 9 cannot isolate a wall")
	if ceiling_floor < 0:
		_fail("no planned storey is shorter than the giant (%.2f m) any more — check 9 can no longer measure a ceiling; retune the form or retire this half" % giant_height)

	if wall_floor >= 0:
		await _resize_is_refused(player, interior, wall_floor,
			giant_radius, RESIZE_WALL_GAP, "a wall")
	if ceiling_floor >= 0:
		await _resize_is_refused(player, interior, ceiling_floor,
			giant_radius, giant_radius + RESIZE_CEILING_GAP, "a ceiling",
			giant_radius)
	if wall_floor >= 0:
		await _resize_is_refused_in_the_open(player, interior, wall_floor)
	# The control and the door, in that order — the control is what grows the giant
	# the door then has to take away, so it hands its spot to the walk back in.
	await _resize_is_allowed_outdoors(player, tower)
	if wall_floor >= 0:
		await _giant_reverts_at_the_door(player, interior, wall_floor)
	_reset_form(player)

	_clear(player)
	tower.queue_free()
	await process_frame


func _resize_is_refused(player: Node, interior: Node3D, floor_index: int,
		giant_radius: float, gap: float, cause: String,
		clear_radius: float = 0.0) -> void:
	"""
	One subject: stand on `floor_index` beside a wall and press F twice.

	`clear_radius` > 0 asks for the CEILING subject's extra isolation — that a
	capsule of that radius, kept entirely under the storey's ceiling, is free where
	the body stands. If it is, nothing horizontal can be what refuses the growth and
	the only thing left above is the lid. (codex review, 2026-08-30: the storey's
	arithmetic already makes the refusal unconditional across the whole floor, but a
	regression in the vertical half could hide behind a wall that happened to be in
	reach, and this is the measurement that says it did not.)
	"""
	var placed := await _stand_beside_a_wall(player, interior, floor_index, gap,
			clear_radius)
	if placed.is_empty():
		_fail("found nowhere to stand on storey %d — check 9's %s subject is vacuous" % [
			floor_index, cause])
		return
	var spot: Vector3 = placed["pos"]
	var into: Vector3 = -(placed["out"] as Vector3)
	print("storey %d (%.2f m clear), %s subject at (%.1f, %.1f, %.1f)" % [
		floor_index, TowerInterior.plan_clear_height(floor_index), cause,
		spot.x, spot.y, spot.z])

	# Re-asked here rather than trusted from the search, because `_shove()` and the
	# settle in between are physics and could have slid the body somewhere else.
	if clear_radius > 0.0 and not _horizontally_clear(player, floor_index, clear_radius):
		_fail("storey %d's %s subject has stone within %.2f m horizontally — the refusal below could be a wall, so the ceiling is not isolated" % [
			floor_index, cause, clear_radius])

	# NORMAL SIZE IS NOT GATED. The refusal is about the growth alone; a Teibi who
	# could not even shrink here would be a different bug wearing the same message.
	if player.get_ability_block_reason() != "":
		_fail("standing on storey %d at normal size, Teibi is gated by %s" % [
			floor_index, player.get_ability_block_reason()])

	# Press 1: normal -> small. Always fits (small is inside the normal capsule).
	player.try_activate_ability()
	await _shove(player, into)
	if player.teibi_size_state != 1:
		_fail("F on storey %d did not make Teibi small (state %d)" % [
			floor_index, player.teibi_size_state])
	_storey_held(player, interior, floor_index, "small", cause)

	# Press 2: small -> giant, and this is the one the building must refuse.
	player.ability_cooldowns[player.current_character_index] = 0.0
	# THE PHYSICS GATE IS ASKED DIRECTLY, and since bead godot-test1-xdf that is the
	# only honest way to ask it in here: "no giant anywhere in the HQ" now answers
	# first, so the dial says INDOOR on every square of every storey and the label
	# stopped being able to tell a wall from a ceiling from an empty room. What #142
	# fixed is `_teibi_grow_blocked()` itself, so that is what this half measures —
	# unchanged in strength, and still isolated to one cause by the storey arithmetic
	# above. Delete the indoor rule tomorrow and both assertions still hold.
	if not bool(player.call("_teibi_grow_blocked")):
		_fail("beside %s on storey %d the grown capsule reports that it FITS — #142's gate is gone" % [
			cause, floor_index])
	if player.get_ability_block_reason() != "INDOOR":
		_fail("beside %s on storey %d the giant form is not gated: reason %s" % [
			cause, floor_index, player.get_ability_block_reason()])
	player.try_activate_ability()
	await _shove(player, into)
	if player.teibi_size_state != 1 or player.is_giant:
		_fail("beside %s on storey %d Teibi grew anyway (state %d, giant %s)" % [
			cause, floor_index, player.teibi_size_state, player.is_giant])
	# A refused press costs nothing — the player may try again the instant he steps
	# clear, exactly like the cooling and RAIN/LAND refusals.
	if player.ability_cooldowns[player.current_character_index] > 0.0:
		_fail("the refused growth charged %.2f s of cooldown" % \
			player.ability_cooldowns[player.current_character_index])
	_storey_held(player, interior, floor_index, "giant (refused)", cause)
	_reset_form(player)


func _resize_is_refused_in_the_open(player: Node, interior: Node3D,
		floor_index: int) -> void:
	"""
	THE OWNER'S RULING, AND THE HALF THE GEOMETRY CANNOT EXPLAIN (bead
	godot-test1-xdf): "Teibi can't be huge inside the HQ." So the refusal has to hold
	where every physical excuse for it is gone — the middle of the room, on a storey
	whose clear height is OVER the giant's, with nothing in reach horizontally.

	`floor_index` is the WALL subject's storey, chosen for exactly that height. This
	spot used to be check 9's negative control ("in the open the growth goes
	through") and it is the same spot for the same reason: it is the one place inside
	this building where `_teibi_grow_blocked()` answers false, which is what makes
	INDOOR the only thing left that can be refusing. The control moved outdoors —
	see `_resize_is_allowed_outdoors()`, which is what still stops a gate that always
	says no from quietly deleting the ability.

	SMALL STAYS ALLOWED IN HERE, and that is asserted too: it is the
	stealth-flavoured form and the bead keeps it explicitly.
	"""
	var placed := false
	for spot: Vector2 in RESIZE_OPEN_SPOTS:
		player.global_position = interior.to_global(
			Vector3(spot.x, TowerInterior.FLOOR_Y[floor_index], spot.y))
		await _settle(player)
		if TowerInterior.current_floor(interior.to_local(player.global_position).y) == floor_index \
				and not player.call("_teibi_grow_blocked"):
			placed = true
			break
	if not placed:
		_fail("nowhere on storey %d is clear of geometry — check 9 cannot isolate the indoor rule from TIGHT"
				% floor_index)
		return
	# Normal -> small is not gated indoors, and the press has to actually land.
	if player.get_ability_block_reason() != "":
		_fail("in open floor on storey %d, normal-size Teibi is gated by %s" % [
			floor_index, player.get_ability_block_reason()])
	player.try_activate_ability()          # -> small
	await _settle(player)
	if player.teibi_size_state != 1:
		_fail("in open floor on storey %d Teibi could not go small (state %d) — the indoor rule took the wrong form" % [
			floor_index, player.teibi_size_state])
	player.ability_cooldowns[player.current_character_index] = 0.0
	if player.get_ability_block_reason() != "INDOOR":
		_fail("in open floor on storey %d the growth is gated by %s, not INDOOR" % [
			floor_index, player.get_ability_block_reason()])
	player.try_activate_ability()          # -> refused
	await _settle(player)
	if player.teibi_size_state != 1 or player.is_giant:
		_fail("in open floor on storey %d Teibi grew anyway (state %d, giant %s)" % [
			floor_index, player.teibi_size_state, player.is_giant])
	if player.ability_cooldowns[player.current_character_index] > 0.0:
		_fail("the refused indoor growth charged %.2f s of cooldown" % \
			player.ability_cooldowns[player.current_character_index])
	if player.teibi_form_timer <= 0.0:
		_fail("the refused indoor growth spent the form timer as well")
	print("indoor rule: storey %d refuses a giant in the middle of an empty room" % floor_index)
	_reset_form(player)


func _resize_is_allowed_outdoors(player: Node, shell: Node3D) -> Vector3:
	"""
	The negative control, now that the building refuses the growth everywhere: OUT IN
	THE FIELD the same two presses still make a giant. A gate that always said no
	would pass every assertion above and quietly delete the ability.

	@return: The outdoor spot the giant is standing on, so the caller can walk him
	        back through the door from it.

	Three shell-widths from the middle of the site and asserted `sheltered()`-false
	before anything is pressed, because "outdoors" is the entire premise here and a
	standoff that silently landed under the roof would turn this control into a
	second copy of the check above.
	"""
	var spot := shell.global_position + Vector3(TowerShell.OUTER_HALF * 3.0, 0.0, 0.0)
	player.global_position = spot
	await _settle(player)
	if bool(shell.call("sheltered", player.global_position)):
		_fail("check 9's outdoor control is standing under the roof — it cannot be a control")
		return spot
	if player.get_ability_block_reason() != "":
		_fail("outdoors, normal-size Teibi is gated by %s" % player.get_ability_block_reason())
	player.try_activate_ability()          # -> small
	await _settle(player)
	player.ability_cooldowns[player.current_character_index] = 0.0
	if player.get_ability_block_reason() != "":
		_fail("outdoors the growth is gated by %s — the indoor rule leaked into the field" % \
			player.get_ability_block_reason())
	player.try_activate_ability()          # -> giant
	await _settle(player)
	if player.teibi_size_state != 2 or not player.is_giant:
		_fail("outdoors Teibi did not grow (state %d) — the ability has been deleted, not gated" % \
			player.teibi_size_state)
	print("control: outdoors the same two presses still make a giant")
	return player.global_position


func _giant_reverts_at_the_door(player: Node, interior: Node3D,
		floor_index: int) -> void:
	"""
	The other half of the ruling: a Teibi who is ALREADY giant when he reaches the
	door reverts on crossing the threshold, so the state cannot exist inside however
	he got there.

	Refusing the press is not enough on its own — the press is not the only way in.
	Walking is, and it is the way a player will actually find. So the body is grown
	outdoors, teleported onto a storey, and given real physics frames: the revert
	rides `_update_ability_timers()`, the same tick and the same
	`_revert_teibi_to_normal()` path the form timer uses, which is what makes it
	clean transient state rather than a second, parallel undo.
	"""
	if not player.is_giant:
		_fail("check 9 could not grow a giant outdoors, so the door has nothing to revert")
		return
	player.global_position = interior.to_global(
		Vector3(0.0, TowerInterior.FLOOR_Y[floor_index], 0.0))
	await _settle(player)
	if player.is_giant or player.teibi_size_state != 0:
		_fail("a giant Teibi walked into the HQ and stayed giant (state %d, giant %s)" % [
			player.teibi_size_state, player.is_giant])
		return
	if player.teibi_form_timer > 0.0:
		_fail("the door's revert left %.2f s of form timer running" % player.teibi_form_timer)
	print("the door: a giant Teibi crossing into the HQ reverted to normal")


func _storey_held(player: Node, interior: Node3D, floor_index: int, form: String,
		cause: String) -> void:
	"""The one assertion this check exists for: the body did not change storeys."""
	var now := TowerInterior.current_floor(interior.to_local(player.global_position).y)
	if now != floor_index:
		_fail("%s beside %s moved the body from storey %d to storey %d — Resize is a lift" % [
			form, cause, floor_index, now])


func _horizontally_clear(player: Node, floor_index: int, radius: float) -> bool:
	"""
	True when a `radius`-wide capsule that stays UNDER this storey's ceiling is free
	where the body stands — i.e. nothing beside the player is close enough to be
	what a full-height probe would hit.

	It asks through `player._shape_blocked()`, the same query the gate itself uses,
	so the mask, the self-exclusion and the notion of "solid" are the shipped ones
	and not a second opinion.
	"""
	var clear: float = TowerInterior.plan_clear_height(floor_index)
	var probe := CapsuleShape3D.new()
	probe.radius = radius
	# Held off the deck and off the ceiling by the same margin, so neither can be
	# the thing this reports.
	probe.height = maxf(2.0 * radius, clear - 2.0 * RESIZE_CEILING_GAP)
	var centre: Vector3 = player.global_position + Vector3(0.0, clear * 0.5, 0.0)
	return not player.call("_shape_blocked", probe, centre)


func _shove(player: Node, into: Vector3) -> void:
	"""
	Settle, but leaning ON the wall — `into` is the horizontal direction of the face
	the subject is standing against.

	WHY THE PUSH IS PART OF THE MEASUREMENT: `CharacterBody3D` resolves an overlap
	inside `move_and_slide`, which only has an overlap to resolve while the body is
	being driven into something. A capsule that grew into a wall and was then left
	alone just sits there, so a check that only waited would be watching the one
	frame the exploit cannot happen in. Holding him against the stone is what a
	player pressing forward does, and it is where the depenetration has to choose a
	way out. See the check's docstring for how far that gets headless.
	"""
	for i in range(RESIZE_SHOVE_FRAMES):
		player.velocity.x = into.x * RESIZE_SHOVE_SPEED
		player.velocity.z = into.z * RESIZE_SHOVE_SPEED
		await physics_frame
	await _settle(player)


func _stand_beside_a_wall(player: Node, interior: Node3D, floor_index: int,
		gap: float, clear_radius: float = 0.0) -> Dictionary:
	"""
	Park the player on `floor_index`'s deck, `gap` metres off the face of one of its
	full-height walls, and return `{pos, out}` — where it ended up and the outward
	normal of that face (empty if no candidate worked). Walls are found by geometry
	— a box standing on this deck and running to this storey's ceiling — so the
	check follows a replanned storey instead of naming a cell that moved.

	`clear_radius` > 0 makes the CEILING subject's isolation part of the SEARCH and
	not a verdict on whatever face came first: a candidate with other stone inside
	that radius is skipped, not failed. Since bd godot-test1-dn8 drew floor 0 on the
	grid, the ground storey is a floor of rooms rather than one 80 m annulus, so the
	first full-height face in the table is quite likely to be in a corner — which is
	a fact about the drawing, not a regression in the gate this check guards.
	"""
	var deck: float = TowerInterior.FLOOR_Y[floor_index]
	var clear: float = TowerInterior.plan_clear_height(floor_index)
	var radius: float = (player.collision_shape.shape as CapsuleShape3D).radius
	for box: Dictionary in TowerInterior.plan_boxes(floor_index):
		if not box["collide"]:
			continue
		var pos: Vector3 = box["pos"]
		var size: Vector3 = box["size"]
		if absf(pos.y - size.y * 0.5 - deck) > SETBACK_EPS or absf(size.y - clear) > SETBACK_EPS:
			continue  # not a wall: it does not run this storey's floor to ceiling
		var out := Vector3(size.x * 0.5, 0.0, 0.0) if size.x < size.z \
				else Vector3(0.0, 0.0, size.z * 0.5)
		for way: float in [1.0, -1.0]:
			var normal := out.normalized() * way
			player.global_position = interior.to_global(Vector3(pos.x, deck, pos.z)
					+ out * way + normal * (radius + gap))
			await _settle(player)
			var local := interior.to_local(player.global_position)
			if TowerInterior.current_floor(local.y) != floor_index:
				continue  # fell through, or the deck is not under this face
			if player.call("_is_body_blocked_at", player.global_position):
				continue  # the normal body is already in the stone here
			if clear_radius > 0.0 and not _horizontally_clear(player, floor_index, clear_radius):
				continue  # a corner or a partition too near: the lid is not isolated
			return {"pos": player.global_position, "out": normal}
	return {}


func _settle(player: Node) -> void:
	"""A few physics frames, then undo whatever the building landed on the body —
	the same race `_make_player` documents, re-run because these checks teleport
	into rooms with hazards in them."""
	for i in range(4):
		await physics_frame
	player.is_caught = false
	player.caught_timer = 0.0
	player.is_respawning = false
	player.respawn_timer = 0.0


func _reset_form(player: Node) -> void:
	"""Back to normal size and a spent-nothing cooldown, so one subject cannot
	inherit another's form."""
	player.call("_revert_teibi_to_normal")
	player.ability_cooldowns[player.current_character_index] = 0.0


func _check_air_sight_is_the_indoor_air_rush() -> void:
	"""
	Check 10 (bead godot-test1-oht). WINDMAN'S F IS ONE KEY AND TWO ABILITIES, and
	which one it is is decided by the roof over his head.

	`tower_interior_selfcheck`'s check 19 owns the other half — that the swap reaches
	the WALLS and nothing else, and restores. This half is the PLAYER's: that the
	dispatch picks Air Sight in here and Air Rush out there, that the ability really
	drives the building rather than merely setting a timer, and — the part that would
	otherwise ship broken and look fine — that it CANNOT BLEED.

	THE BLEED IS THE INTERESTING FAILURE. Every other ability's leftovers are a float
	on the player, so a missed reset is invisible; this one lives in the BUILDING's
	materials, so a switch, a respawn or a walk out of the door that forgot to clear
	it leaves a permanently see-through HQ with nobody holding it that way. Three
	exits are driven here — the character switch, the walk out through the door, and
	the timer — and all three are asked of the interior, never of the timer.
	"""
	var tower := await _make_tower()
	var interior: Node3D = get_first_node_in_group("tower_interior")
	if interior == null:
		_fail("the tower built no interior — check 10 has nothing to see through")
		tower.queue_free()
		return
	var player := await _make_player()
	if not _become(player, "windman"):
		_fail("player.tscn has no windman in CHARACTERS — check 10 cannot drive Air Sight")
		_clear(player)
		tower.queue_free()
		return

	var indoors := interior.to_global(Vector3(0.0, TowerInterior.FLOOR_Y[0], 0.0))
	var outdoors := tower.global_position + Vector3(TowerShell.OUTER_HALF * 3.0, 0.0, 0.0)

	# --- Indoors: F is Air Sight. ---
	player.global_position = indoors
	await _settle(player)
	if not bool(tower.call("sheltered", player.global_position)):
		_fail("check 10's indoor spot is not under the roof — the whole check is vacuous")
	if player.get_ability_name() != "Air Sight":
		_fail("indoors the HUD still advertises %s" % player.get_ability_name())
	if player.get_ability_block_reason() != "":
		_fail("indoors Air Sight is gated by %s — the take-off gates leaked into it" % \
			player.get_ability_block_reason())
	player.ability_cooldowns[player.current_character_index] = 0.0
	player.try_activate_ability()
	await process_frame
	if not bool(interior.call("xray_active")):
		_fail("F indoors did not make the walls see-through")
	if player.windman_boost_timer > 0.0:
		_fail("F indoors fired the Air Rush as well — the two abilities are not exclusive")
	if player.ability_cooldowns[player.current_character_index] <= 0.0:
		_fail("Air Sight fired and charged no cooldown — the dial has nothing to run")

	# ONE LOOK AT A TIME (codex review). A fully-ranked Windman's cooldown (4.80 s) is
	# SHORTER than the look (7 s), so a press on every recharge would hold the walls
	# open forever — the `"LAND"` bug one ability along. The state invariant is what
	# closes it, so it is asked as state: charge the cooldown to zero, which is the
	# strongest form of the press the skill tree can ever produce, and the gate must
	# still be the thing standing in the way.
	player.ability_cooldowns[player.current_character_index] = 0.0
	if player.get_ability_block_reason() != "SEEING":
		_fail("with Air Sight already running and the cooldown spent, the next press is gated by %s — a skilled Windman can chain it forever" % \
			player.get_ability_block_reason())
	var look_left: float = player.windman_sight_timer
	player.try_activate_ability()
	await process_frame
	if player.windman_sight_timer > look_left:
		_fail("the refused press refreshed the look (%.2f s -> %.2f s)" % [
			look_left, player.windman_sight_timer])
	if player.ability_cooldowns[player.current_character_index] > 0.0:
		_fail("the refused Air Sight press charged %.2f s of cooldown" % \
			player.ability_cooldowns[player.current_character_index])

	# --- The switch clears it, and it is the BUILDING that has to say so. ---
	if not _become(player, "primm"):
		_fail("player.tscn has no primm — check 10 cannot drive the switch")
	if bool(interior.call("xray_active")):
		_fail("switching character left the HQ see-through — Air Sight bled across the swap")
	if player.windman_sight_timer > 0.0:
		_fail("switching character left %.2f s of Air Sight running" % player.windman_sight_timer)
	if not _become(player, "windman"):
		_fail("could not switch back to windman")

	# --- Walking out of the door ends it too. ---
	player.ability_cooldowns[player.current_character_index] = 0.0
	player.try_activate_ability()
	await process_frame
	if not bool(interior.call("xray_active")):
		_fail("F indoors did not re-arm Air Sight after the switch")
	player.global_position = outdoors
	await _settle(player)
	if bool(interior.call("xray_active")):
		_fail("walking out of the HQ left it see-through behind us")
	if player.windman_sight_timer > 0.0:
		_fail("walking out left %.2f s of Air Sight running" % player.windman_sight_timer)

	# --- Outdoors F is Air Rush again, unchanged. ---
	if player.get_ability_name() != "Air Rush":
		_fail("outdoors the HUD advertises %s" % player.get_ability_name())
	player.ability_cooldowns[player.current_character_index] = 0.0
	player.velocity = Vector3.ZERO
	player.try_activate_ability()
	await process_frame
	if player.windman_boost_timer <= 0.0:
		_fail("outdoors F no longer launches an Air Rush — the indoor branch swallowed it")
	if bool(interior.call("xray_active")):
		_fail("an outdoor Air Rush made the HQ see-through")

	# --- And the timer is the third exit: it must expire on its own indoors. ---
	player.global_position = indoors
	await _settle(player)
	player.ability_cooldowns[player.current_character_index] = 0.0
	player.try_activate_ability()
	await process_frame
	if not bool(interior.call("xray_active")):
		_fail("Air Sight would not re-arm for the expiry subject")
	# Wind the timer down to the last tick rather than waiting seven real seconds —
	# the expiry PATH is what is being measured, and it is the same one either way.
	player.windman_sight_timer = 0.001
	await _settle(player)
	if bool(interior.call("xray_active")):
		_fail("Air Sight's timer ran out and the walls stayed see-through")
	print("air sight: indoors it swaps the walls, outdoors F is still Air Rush, and all three exits clear it")

	_clear(player)
	tower.queue_free()
	await process_frame


# ============================================================================
# 17. THERE IS NO SECOND WAY TO LOSE
# ============================================================================

## The retired heart model, by name. Every one of these was a member or a const of
## `player_controller` before bead godot-test1-0bc, and the bead's whole promise is
## that nothing decrements a life or ends a run except the empty free-hero set — so
## the cheapest honest way to keep that promise is to assert the vocabulary is gone.
const RETIRED_HEART_MEMBERS: Array[String] = [
	"lives", "MAX_LIVES", "LIVES_CAP", "EXTRA_LIFE_COINS", "next_extra_life_at",
	"own_lives_spent",
]

func _check_no_second_way_to_lose() -> void:
	"""
	Check 17. The player declares NO heart model at all, so one cannot come back
	quietly.

	Every other check in this file measures behaviour, and behaviour is exactly what
	a reintroduced life would not change on the day it landed: a `lives` field that
	nothing spends yet passes all sixteen. This one measures the VOCABULARY instead.
	`"lives" in player` is false on a `player_controller` that has no such member,
	and a `var lives: int = 3` typed back in flips it to true the moment it is
	saved — which is a loud failure at the one place a reviewer would want one,
	rather than a silent second ending discovered by a player.

	IT IS DELIBERATELY A SPELLING TEST AND SAYS SO. A second ending under another
	name would walk straight past it; what it buys is that the OLD one cannot walk
	back in, and the old one is the whole of what this bead removed.

	The positive control is on the same line: `is_game_over` must still be a member,
	or `"X in player"` has stopped meaning what this check reads it as (a freed
	player, a renamed script, a typo in the probe) and every assertion above it is
	vacuously true.
	"""
	var player := await _make_player()
	if not ("is_game_over" in player):
		_fail("the probe player has no `is_game_over` member — `in` is not reading this "
				+ "object's properties, so the absences below prove nothing")
	for member: String in RETIRED_HEART_MEMBERS:
		if member in player:
			_fail("player_controller declares `%s` again — heroes are the lives (owner " % member
					+ "ruling 2026-08-31) and a second way to end a run is exactly what "
					+ "bead godot-test1-0bc removed")
	_clear(player)
	await process_frame


func _become(player: Node, hero: String) -> bool:
	"""Switch through `set_active_character()` — the same door capture uses."""
	var characters: Array = player.CHARACTERS
	for i in range(characters.size()):
		if String(characters[i]["name"]) == hero:
			player.set_active_character(i)
			return player.hero_name() == hero
	return false


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
	"""
	A real `player.tscn`, in the tree and ready to be bitten — BY THE CHECK, and
	not by the building it is standing in.

	THE BUILDING GETS THE FIRST BITE ON A SLOW MACHINE, and that is a real race
	this staging used to lose silently. Every check here parks the tower at the
	origin and a fresh player spawns at the origin, i.e. INSIDE it, next to the
	interior's own hazards. One `await process_frame` is one process frame but an
	UNBOUNDED number of physics ticks — Godot runs as many as the elapsed wall
	clock asks for, up to `max_physics_steps_per_frame` (8) — so on a fast desktop
	one or two tick past and nothing reaches the body, while on a loaded CI runner
	eight do and the rotor bar lands a hit. `hit_by_crocodile` then early-returns
	on its own invulnerability gate for the check's hit, `caught_setback` stays 0,
	and the guard check watches a bank the building already billed — six failures
	that look like the game is broken and reproduce nowhere.

	(Reproduce the old behaviour with `godot --headless --fixed-fps 5 ...`: a fifth
	of a second per process frame is exactly the slow runner, and it fails every
	time.)

	So undo whatever the building landed while we were staging. This clears the
	invulnerability gate and the caught/respawn timers that re-raise it — and
	NOTHING else: coins and the roster are what each check sets and asserts on, so
	restoring those would be this harness hiding a regression rather than a race.
	"""
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	root.add_child(player)
	await process_frame
	player.is_caught = false
	player.caught_timer = 0.0
	player.caught_setback = 0.0
	player.caught_captured = false
	player.is_respawning = false
	player.respawn_timer = 0.0
	player.respawn_blink_timer = 0.0
	return player


func _make_tower() -> Node3D:
	## Shell plus interior, assembled the way `endless_terrain` assembles them — the
	## interior added BEFORE the shell enters the tree, so it can see its parent.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	root.add_child(shell)
	await process_frame
	return shell


func _assert_cell_body(interior: Node, hero: String, expected: bool) -> void:
	"""Check the captive model's lifecycle and RemoteAvatar isolation contract."""
	var floor_index := TowerInterior.block_floor()
	var path := "Floor%d/%s%s" % [floor_index, TowerInterior.CAPTIVE_BODY_PREFIX, hero.capitalize()]
	var body := interior.get_node_or_null(path) as Node3D
	if expected and body == null:
		_fail("capture: %s's cell has no visual body under %s" % [hero, path])
		return
	if not expected:
		if body != null:
			_fail("liberation: %s's cell still has a visual body" % hero)
		return
	if body.get_parent() == null or String(body.get_parent().name) != "Floor%d" % floor_index:
		_fail("capture: %s's body is not parented to its storey floor" % hero)
	if absf(body.position.y - TowerInterior.FLOOR_Y[floor_index]) > 0.001:
		_fail("capture: %s's body is at y %.3f, not the storey walking surface %.3f" % [
			hero, body.position.y, TowerInterior.FLOOR_Y[floor_index]])
	if body.process_mode != Node.PROCESS_MODE_DISABLED:
		_fail("capture: %s's cell body has processing enabled" % hero)
	var pending: Array[Node] = [body]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D:
			_fail("capture: %s's cell body contains a collision object (%s)" % [hero, node.name])
		if not node.get_groups().is_empty():
			_fail("capture: %s's cell body contains group membership (%s)" % [hero, node.name])
		for child: Node in node.get_children():
			pending.append(child)


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
	keyed on the row's `captures_hero`, so if that key is ever renamed this check
	moves with it instead of quietly passing on a flag nothing reads any more.
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
