extends SceneTree
## Headless self-check: THE HQ'S SERVICE LIFT MENU — bead `godot-test1-3iy.7`.
##
##   godot --headless --path . --script res://scripts/tower_lift_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1.
##
## WHAT IT GUARDS. The lift is a TELEPORT, which makes every one of its refusals a
## way to break the game rather than a nicety:
##
##  1. THE KEY IS FREE. `L` against `project.godot`'s input map and against every
##     other raw-keycode panel's own constant — `city_map_selfcheck` check 1's
##     idiom, including its two negative controls on the scan itself, because a
##     panel key is NOT rebindable and a collision is unfixable from inside the
##     game. The stop digits are deliberately NOT in that scan: they are shared
##     with the hero picker and the landmark quiz on purpose, and check 3 proves
##     the sharing is safe by driving the shipped handler under the menu's pause.
##  2. EVERY STOP IS AN AUDITED ENTRY, AND THERE IS EXACTLY ONE PER STOREY.
##     `TowerGraph.lift_stops()` is derived from the mutation table, so this asserts
##     the derivation lands on rows that are really entries, really `built`, really
##     carry an `unlock` id equal to their own id (which is what makes the trigger's
##     bind and the menu's read the same fact), and really resolve to a storey whose
##     landing the arrival point stands on — one row per storey above the ground,
##     none twice, none on the ground. That is the bead's acceptance and it is what
##     binds the menu to `tower_selfcheck`'s fifteen-subset walk, which already
##     starts from each of these entries.
##  3. THE MENU ON A REAL SHELL, from the ground. A tower with an empty opened set
##     offers nothing; the stop the trigger writes appears the moment it is opened
##     and not before; choosing one puts a real `player.tscn` on that storey's `s`
##     landing; and a floor that was never offered is refused.
##  3b. AND FROM EVERY OTHER STOREY (its own world, its own empty profile). L
##     answers on an upper landing with NOTHING earned — reachability, not earning —
##     and offers only the ground; two visited landings are offered and the storey
##     you stand on is not; a landing never stood on is not, with the mutation that
##     opens it as the control; and the ride DOWN lands on the ground landing, which
##     is the trip the old menu could not make at all.
##  4. THE REFUSALS. In a room, over game over, mid-bite, away from the call point
##     and out on a storey's plain floor — every one of them asserted with the
##     refusal REMOVED as the control, because a `can_open()` that answered false
##     for the wrong reason would pass them all otherwise. Plus the pause: taken
##     solo through `PauseHub`, handed back on close, and handed back by `_process`
##     when a refusal becomes true under an open panel.
##  5. THE PAD HINT (bead `godot-test1-b9m8`, owner ruling 2), read off the node
##     rather than off the panel's bookkeeping: up on a pad, down off it, down
##     under the open menu, down in a room, down under a FOREIGN pause (every
##     full-screen overlay in this HUD draws beneath this node), following a live
##     locale switch, and spelling the key it really is.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches — same note as
## the other tower self-checks.

const LiftMenu: GDScript = preload("res://scripts/tower_lift_menu.gd")
const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

# Every other owner of a raw keycode, for check 1. Read rather than restated, so
# a panel that moves its key fails here instead of silently colliding.
const HelpOverlay := preload("res://scripts/help_overlay.gd")
const MinimapHud := preload("res://scripts/minimap_hud.gd")
const PauseController := preload("res://scripts/pause_controller.gd")
const PerfOverlay := preload("res://scripts/perf_overlay.gd")
const SkillTreeUi := preload("res://scripts/skill_tree_ui.gd")
const CityMapPanel := preload("res://scripts/city_map_panel.gd")
const LandmarkToast := preload("res://scripts/landmark_toast.gd")
const MultiplayerUI := preload("res://scripts/mp_ui.gd")

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"


class StubMp extends Node:
	var busy: bool = false

	func is_busy() -> bool:
		return busy


## THE END-OF-CHECK SENTINEL — see `scripts/selfcheck_sentinel.gd`.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_fresh_store()
	# ONE FRAME FIRST: a node added to `root` from inside `_initialize()` is not
	# `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (every tower check records this).
	await process_frame

	_check_key_is_free()
	_check_stops_are_audited_entries()
	await _check_the_menu_on_a_real_shell()
	await _check_every_storey_is_a_call_point()
	await _check_the_refusals()
	await _check_the_pad_hint()
	await _check_the_memory_is_per_run()

	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# 1. THE KEY IS FREE
# ============================================================================

func _check_key_is_free() -> void:
	var key: int = int(LiftMenu.TOGGLE_KEY)
	if key == 0:
		_fail("the menu's TOGGLE_KEY is 0 — it can never be pressed")
		Sentinel.done("key_is_free")
		return

	# --- Against the input map ---------------------------------------------
	# BARE PRESSES ONLY. Godot ships built-in `ui_text_*` actions on modified keys
	# (`L` is Cmd+Shift+L, "add caret below"), and a panel key is pressed with
	# nothing held — so an event carrying a modifier is a different chord and not a
	# collision. Every action this GAME binds is modifier-free, which is what keeps
	# the rule strict where it matters.
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey):
				continue
			var as_key := event as InputEventKey
			if as_key.ctrl_pressed or as_key.alt_pressed or as_key.meta_pressed \
					or as_key.shift_pressed:
				continue
			if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
				_fail("TOGGLE_KEY %s is also bound to the input action \"%s\""
					% [OS.get_keycode_string(key), action])

	# --- Against every other raw-keycode panel ------------------------------
	var owners: Array = [
		[[MinimapHud.TOGGLE_KEYCODE], "minimap_hud.TOGGLE_KEYCODE"],
		[MinimapHud.ZOOM_IN_KEYCODES, "minimap_hud.ZOOM_IN_KEYCODES"],
		[MinimapHud.ZOOM_OUT_KEYCODES, "minimap_hud.ZOOM_OUT_KEYCODES"],
		[[PauseController.PAUSE_KEY], "pause_controller.PAUSE_KEY"],
		[[SkillTreeUi.TOGGLE_KEY], "skill_tree_ui.TOGGLE_KEY"],
		[[CityMapPanel.TOGGLE_KEY], "city_map_panel.TOGGLE_KEY"],
		[[MultiplayerUI.TOGGLE_KEY], "mp_ui.TOGGLE_KEY"],
		[HelpOverlay.HELP_KEYCODES, "help_overlay.HELP_KEYCODES"],
		[LandmarkToast.ANSWER_KEYCODES, "landmark_toast.ANSWER_KEYCODES"],
		[PlayerScript.HERO_KEYCODES, "player_controller.HERO_KEYCODES"],
		[[PlayerScript.CHEAT_ARM_KEY], "player_controller.CHEAT_ARM_KEY"],
		# BARE KEYS ONLY (review round 1): the Ctrl-held HUD chords live in
		# `city_map_selfcheck.panel_chord_owners()` and are compared only
		# against their own half — listing them here would compare them as
		# bare keys, the opposite of the pair rule.
	]
	# ...pinned, not just commented: a chord row smuggled back in would be
	# compared as a bare key again, exactly the bug above.
	for row: Array in owners:
		if String(row[1]).ends_with(" (ctrl)"):
			_fail("bare-key list carries chord row %s — it would be compared as a bare key" % String(row[1]))
	var claimed: String = _owner_claiming(key, owners)
	if not claimed.is_empty():
		_fail("TOGGLE_KEY %s is already %s" % [OS.get_keycode_string(key), claimed])

	# NEGATIVE CONTROLS on the scan itself — `city_map_selfcheck`'s, and its second
	# one is why they are here: two owners above are arrays of ARRAYS, and a scan
	# that raised on the inner Array would abort this function and print a pass.
	if _owner_claiming(key, [[[key], "a fake flat owner"]]).is_empty():
		_fail("the scan missed a fake owner holding TOGGLE_KEY in a flat array — "
			+ "it cannot detect a real collision either")
	if _owner_claiming(key, [[[[key]], "a fake nested owner"]]).is_empty():
		_fail("the scan missed a fake owner holding TOGGLE_KEY in a NESTED array — "
			+ "landmark_toast.ANSWER_KEYCODES and player_controller.HERO_KEYCODES "
			+ "are exactly that shape, so their keys are not really being compared")

	# The stop digits are SHARED on purpose (see the header). What must hold is
	# that there are enough of them for every stop the graph can offer.
	if (LiftMenu.CHOICE_KEYCODES as Array).size() < TowerGraph.lift_stops().size():
		_fail("the menu has %d choice keys for %d authored stops — a stop nobody "
			% [(LiftMenu.CHOICE_KEYCODES as Array).size(), TowerGraph.lift_stops().size()]
			+ "can press is a stop that does not exist")
	Sentinel.done("key_is_free")


static func _flatten_keycodes(value: Variant) -> Array:
	"""Every keycode inside `value`, however deeply nested, as plain ints."""
	var out: Array = []
	if value is Array or value is PackedInt32Array or value is PackedInt64Array:
		for item in value:
			out.append_array(_flatten_keycodes(item))
	else:
		out.append(int(value))
	return out


static func _owner_claiming(key: int, owners: Array) -> String:
	"""The label of the first `[keycodes, label]` owner that already holds `key`,
	or "" if it is free. Pure, so the negative controls above can drive it."""
	for entry: Array in owners:
		if _flatten_keycodes(entry[0]).has(key):
			return String(entry[1])
	return ""


# ============================================================================
# 2. EVERY STOP IS AN AUDITED ENTRY THAT LANDS ON A LANDING
# ============================================================================

func _check_stops_are_audited_entries() -> void:
	var stops: Array[Dictionary] = TowerGraph.lift_stops()
	if stops.is_empty():
		_fail("TowerGraph.lift_stops() is empty — the lift has nowhere to go, and "
			+ "every assertion below would pass vacuously")
		Sentinel.done("stops_are_entries")
		return

	# The one stop named here, because it is the one the building itself writes:
	# `LiftStopTrigger` opens `ENTRY_LIFT_MAZE`, and a rename that lost the menu
	# would otherwise leave both halves internally consistent and disconnected.
	var by_id: Dictionary = {}
	for row: Dictionary in stops:
		by_id[String(row["id"])] = row
	if not by_id.has(TowerGraph.ENTRY_LIFT_MAZE):
		_fail("the labyrinth's stop '%s' is not among the lift's stops — the trigger "
			% TowerGraph.ENTRY_LIFT_MAZE + "earns an id nothing offers")

	for row: Dictionary in stops:
		var id := String(row["id"])
		# The derivation must land on rows this file's own lookup agrees are entries.
		if TowerGraph.entry(id).is_empty():
			_fail("lift stop '%s' is not an entry row — `tower_selfcheck` never walks "
				% id + "from it, so the ride is into an unaudited part of the graph")
			continue
		if not bool(row.get("built", false)):
			_fail("lift stop '%s' is offered by the menu but its entry row still says "
				% id + "built: false — the audit reads that as a way in nobody has")
		if String(row.get("unlock", "")) == "":
			_fail("lift stop '%s' carries no `unlock` id, so nothing can ever earn it"
				% id)
		# `unlock` IS the id, for every stop (bead godot-test1-b9m8). That is not
		# tidiness: `TowerInterior._build_lift_stops` binds each trigger to the row's
		# `id` and the menu reads its `unlock`, so a row where they differ is a
		# landing you can stand on forever without the lift ever offering it.
		elif String(row.get("unlock", "")) != id:
			_fail(("lift stop '%s' is earned by '%s' rather than by itself — the trigger "
				+ "writes the id and the menu reads the unlock, so they must be one string")
				% [id, String(row.get("unlock", ""))])
		var floor_index: int = TowerInterior.landing_floor(String(row.get("room", "")))
		if floor_index < 0:
			_fail("lift stop '%s' names room '%s', which no storey claims as its landing"
				% [id, String(row.get("room", ""))])
			continue
		if floor_index == 0:
			_fail("lift stop '%s' lands on the ground floor, which is where the lift "
				% id + "is called from")
		# THE ARRIVAL POINT IS A LANDING CELL. `landing_rect()`'s centre is only
		# accidentally standable (the ground floor's landing has a doorway bitten out
		# of it), so `lift_stand` snaps to a real `s` and this is what says so.
		if not _is_landing_cell(floor_index, TowerInterior.lift_stand(floor_index)):
			_fail("lift stop '%s' would set the player down off storey %d's landing"
				% [id, floor_index])

	# --- ONE STOP PER STOREY, NONE TWICE (bead godot-test1-b9m8) -------------
	# The owner's ruling is "every storey", and the only mechanical form of that is
	# counting: every floor the plans draw above the ground carries exactly one stop
	# row. A storey added to `tower_plans.gd` without its `TOWER_GRAPH` rows is a
	# floor the lift cannot reach and a landing whose hint never appears, and this
	# is where that lands — on the day the plan row does.
	var stops_by_floor: Dictionary = {}
	for row: Dictionary in stops:
		var f: int = TowerInterior.landing_floor(String(row.get("room", "")))
		if f < 0:
			continue
		if stops_by_floor.has(f):
			_fail("storey %d has two lift stops ('%s' and '%s') — the menu would offer "
				% [f, String(stops_by_floor[f]), String(row["id"])] + "it twice")
			continue
		stops_by_floor[f] = String(row["id"])
	for f2: int in TowerPlans.floors():
		if f2 == 0:
			continue
		if not stops_by_floor.has(f2):
			_fail("storey %d is drawn but carries no lift stop — the lift stops at EVERY "
				% f2 + "storey (owner ruling 2026-09-16), and this one it cannot reach")

	# RIDING DOWN LANDS ON AN AUDITED ENTRY. The ground is in the offer
	# unconditionally and is NOT a stop row, so nothing above says its landing is a
	# place the audit walks from. This does: it is the front door's own room.
	var ground_room: String = String(TowerPlans.storey(0).get("landing", ""))
	if ground_room != String(TowerGraph.entry("front_door").get("room", "")):
		_fail(("the ground landing is room '%s' but the front door enters '%s' — the ride "
			+ "DOWN would set the player in a room `tower_selfcheck` never walks from")
			% [ground_room, String(TowerGraph.entry("front_door").get("room", ""))])

	# --- THE PREDICATE THE STORE FILTERS ON (bead godot-test1-4ban) ----------
	# `TowerGraph.is_lift_stop_id()` decides which ids the profile refuses to keep,
	# so it has to answer YES for exactly these rows and NO for every other id the
	# opened set may hold. THE MUTATION IDS ARE THE POINT: each of these stops is
	# granted by a mutation spelled `lift_stop_*_unlocked`, which a
	# `begins_with("lift_stop")` rule would swallow whole — and those ARE persisted
	# progression. This loop is what makes the table-derived version the only one
	# that passes.
	for row: Dictionary in stops:
		if not TowerGraph.is_lift_stop_id(String(row.get("unlock", ""))):
			_fail("is_lift_stop_id() says '%s' is not a lift stop — the store would "
				% String(row.get("unlock", "")) + "persist a landing and the lift "
				+ "would remember it across runs")
	var must_persist: Array[String] = [
		TowerGraph.GATE_CHECKPOINT, TowerGraph.RESCUE_DONE,
	]
	for key: Variant in TowerGraph.TOWER_GRAPH["gates"]:
		must_persist.append(String(key))
	for mut: Dictionary in TowerGraph.TOWER_GRAPH["mutations"]:
		must_persist.append(String(mut.get("id", "")))
	for sid: String in TowerGraph.scar_ids():
		must_persist.append(sid)
	for id: String in must_persist:
		if id != "" and TowerGraph.is_lift_stop_id(id):
			_fail("is_lift_stop_id() claims '%s' is a lift stop — the store would " % id
				+ "silently stop persisting earned progression")

	# --- negative controls --------------------------------------------------
	if TowerInterior.landing_floor("a_room_no_storey_has") >= 0:
		_fail("landing_floor() resolved a room that does not exist — a wave-C "
			+ "reservation would be offered as a floor")
	if _is_landing_cell(0, TowerInterior.lift_stand(0) + Vector3(0.0, 0.0, 60.0)):
		_fail("the landing-cell probe called a point 60 m off the landing a landing "
			+ "cell — it cannot see a bad arrival point either")
	Sentinel.done("stops_are_entries")


func _is_landing_cell(floor_index: int, local: Vector3) -> bool:
	"""Does this interior-local point stand on an `s` cell of that storey's plan?"""
	var plan: Dictionary = TowerPlans.storey(floor_index)
	if plan.is_empty():
		return false
	var col: int = int(floor((local.x + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL))
	var row_index: int = int(floor((local.z + TowerPlans.PLAN_HALF) / TowerPlans.PLAN_CELL))
	if row_index < 0 or row_index >= plan["rows"].size():
		return false
	var line := String(plan["rows"][row_index])
	if col < 0 or col >= line.length():
		return false
	return line[col] == TowerPlans.LANDING_CHAR


# ============================================================================
# 3. THE MENU ON A REAL SHELL
# ============================================================================

func _check_the_menu_on_a_real_shell() -> void:
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("the tower has no TowerInterior child — the interior is not assembled")
		await _clear(null, shell, null)
		Sentinel.done("menu_on_a_shell")
		return
	var player: Node3D = await _make_player()
	var panel: Control = await _make_panel()
	_stand_at_the_lift(player, interior, 0)
	await process_frame

	if not panel.can_open():
		_fail("the menu refuses to open at the ground landing of a real tower — "
			+ "every assertion below would be measuring a closed panel")
		await _clear(player, shell, panel)
		Sentinel.done("menu_on_a_shell")
		return

	# --- NOTHING IS OFFERED BEFORE IT IS EARNED ------------------------------
	panel.set_open(true)
	await process_frame
	if not (panel.stop_floors() as Array).is_empty():
		_fail("a tower with an empty opened set offered %s — the lift lists stops "
			% str(panel.stop_floors()) + "nobody has reached")
	if _row_count(panel) != 1:
		_fail("the empty menu drew %d rows — it should carry exactly the one line "
			% _row_count(panel) + "that says there is nothing to ride to")
	if not paused or PauseHub.holder_count() != 1:
		_fail("the menu opened solo and the world kept running (paused=%s, holders=%d)"
			% [paused, PauseHub.holder_count()])

	# THE DIGITS ARE SHARED AND THAT IS SAFE, because every other owner refuses
	# under a foreign pause. Driven through the SHIPPED handler rather than argued.
	var before: int = int(player.current_character_index)
	var other: int = (before + 1) % (PlayerScript.CHARACTERS as Array).size()
	# `_unhandled_input`, which is where `HERO_KEYCODES` is really read — `_input`
	# handles R and the mouse and would let this pass while proving nothing.
	player._unhandled_input(_digit_event(int((PlayerScript.HERO_KEYCODES[other] as Array)[0])))
	if int(player.current_character_index) != before:
		_fail("a digit pressed with the lift menu up also switched hero — the menu's "
			+ "pause is supposed to be what stops that")

	# --- THE STOP THE TRIGGER WRITES -----------------------------------------
	panel.set_open(false)
	shell.call("mark_opened", TowerGraph.ENTRY_LIFT_MAZE)
	var maze_floor: int = TowerInterior.landing_floor(
			String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_MAZE).get("room", "")))
	panel.set_open(true)
	await process_frame
	var offered: Array = panel.stop_floors()
	if offered != [maze_floor]:
		_fail("with only '%s' opened the menu offered %s, not [%d]"
			% [TowerGraph.ENTRY_LIFT_MAZE, str(offered), maze_floor])
	if _row_count(panel) != 1:
		_fail("one unlocked stop drew %d rows" % _row_count(panel))

	# --- A FLOOR NOBODY OFFERED IS REFUSED -----------------------------------
	var parked: Vector3 = player.global_position
	if panel.ride_to(maze_floor + 1):
		_fail("the lift rode to a floor it never offered")
	if not player.global_position.is_equal_approx(parked):
		_fail("a refused ride moved the player anyway")

	# --- THE RIDE ------------------------------------------------------------
	if not panel.ride_to(maze_floor):
		_fail("the lift refused the one stop it was offering")
	await process_frame
	_assert_landed(player, interior, maze_floor, "the ride up")
	if panel.is_open() or paused or PauseHub.holder_count() != 0:
		_fail("the lift arrived with the menu still up (open=%s, paused=%s, holders=%d)"
			% [panel.is_open(), paused, PauseHub.holder_count()])

	await _clear(player, shell, panel)
	Sentinel.done("menu_on_a_shell")


# ============================================================================
# 3b. EVERY STOREY IS A CALL POINT, AND THE OFFER IS WHERE YOU HAVE BEEN
#     (bead godot-test1-b9m8, owner rulings 1 and 3)
# ============================================================================

func _check_every_storey_is_a_call_point() -> void:
	"""
	The owner's report, as a check: stand on an upper storey's pad, press L, and
	the lift answers — with the ground plus the landings already walked and nothing
	else.

	ITS OWN WORLD, on a fresh profile: the check above earns stops, and the shell
	hydrates its opened set from `BestRunStore` (which has no cache of its own), so
	this starts from a genuinely empty set rather than from the last check's.
	"""
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var player: Node3D = await _make_player()
	var panel: Control = await _make_panel()
	if interior == null:
		_fail("the tower has no TowerInterior child — nothing to call the lift from")
		await _clear(player, shell, panel)
		Sentinel.done("every_storey_calls")
		return
	var maze_floor: int = TowerInterior.landing_floor(
			String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_MAZE).get("room", "")))
	var offered: Array = []

	# CALLABLE BY REACHABILITY, NOT BY EARNING. Standing on storey 3's landing with
	# an EMPTY opened set — nothing earned anywhere — the lift still answers, and it
	# offers exactly one thing: the way home. That is the whole shape of ruling 3 in
	# two assertions, and it is the owner's bug report ("stood on the pad, pressed L,
	# nothing happened") turned into a test.
	var call_floor: int = 3
	_stand_at_the_lift(player, interior, call_floor)
	# NO FRAME BETWEEN THE MOVE AND THE QUESTION, deliberately (revmux round 1):
	# standing on the pad puts this body inside `LiftStopTrigger3`, and a physics
	# tick inside an `await` would EARN that storey before the question is asked —
	# leaving the one assertion in this suite that says "reachability, not earning"
	# unable to tell the two apart. `can_open()` is synchronous and needs no frame,
	# so the assertion is made on a set this line proves is still empty.
	if shell.call("is_opened", _stop_id_for_floor(call_floor)):
		_fail("storey %d was already earned before the reachability assertion — the "
			% call_floor + "control it depends on is gone")
	if not panel.can_open():
		_fail("the menu refused on storey %d's landing with nothing opened — a landing "
			% call_floor + "you can stand on is a landing you walked to, so L must answer")
	panel.set_open(true)
	await process_frame
	var from_nothing: Array = panel.stop_floors()
	if from_nothing != [0]:
		_fail("from storey %d with nothing earned the lift offered %s, not [0] — the "
			% [call_floor, str(from_nothing)] + "ground is always the way home")

	# TWO VISITED LANDINGS, and the offer is exactly those plus the ground, minus
	# here. THE PAIR IS CHOSEN SO THE SORT IS LOAD-BEARING (revmux round 1 caught
	# the first pair agreeing with the insertion order, which made this assertion
	# blind to `out.sort()` being deleted): `_visited_floors()` appends in
	# `lift_stops()` order, which is `entries` order — storey 1, then the maze at 7,
	# then s3 at 2 and up. So the maze against s3's landing arrives as [0, 7, 2] and
	# only the sort turns it into [0, 2, 7].
	var lower: int = TowerInterior.landing_floor("s3_landing")
	var upper: int = maze_floor
	panel.set_open(false)
	shell.call("mark_opened", _stop_id_for_floor(lower))
	shell.call("mark_opened", _stop_id_for_floor(upper))
	shell.call("mark_opened", _stop_id_for_floor(call_floor))
	panel.set_open(true)
	await process_frame
	offered = panel.stop_floors()
	if offered != [0, lower, upper]:
		_fail("from storey %d with storeys %d, %d and %d visited the lift offered %s, "
			% [call_floor, lower, upper, call_floor, str(offered)]
			+ "not [0, %d, %d] — the storey you stand on is never in the offer" % [lower, upper])
	if _row_count(panel) != offered.size():
		_fail("the menu drew %d rows for %d stops" % [_row_count(panel), offered.size()])

	# A FLOOR NEVER VISITED IS NOT OFFERED, with the mutation as its own control:
	# the floor is absent, then its id is opened and it is there.
	var never: int = 5
	if offered.has(never):
		_fail("storey %d was offered without ever being stood on" % never)
	panel.set_open(false)
	shell.call("mark_opened", _stop_id_for_floor(never))
	panel.set_open(true)
	await process_frame
	if not (panel.stop_floors() as Array).has(never):
		_fail("opening storey %d's own id did not put it in the offer — the control for "
			% never + "the assertion above never fired, so that assertion proves nothing")

	# --- AND THE RIDE DOWN ---------------------------------------------------
	# The trip the old menu could not make at all (it only ever called from 0).
	if not panel.ride_to(0):
		_fail("the lift refused to take a player on storey %d back to the ground" % call_floor)
	await process_frame
	_assert_landed(player, interior, 0, "the ride down")

	await _clear(player, shell, panel)
	Sentinel.done("every_storey_calls")


func _assert_landed(player: Node3D, interior: Node3D, want: int, what: String) -> void:
	"""The player stands on storey `want`'s landing cell, within a hand's width."""
	var local: Vector3 = player.global_position - interior.global_position
	# A hand's width of slack, not exact equality: the ride is a hard write and the
	# menu's pause stops physics, but a check that fails on one settling frame would
	# be measuring the pause rather than the lift. Mutation-tested: a ride that lands
	# at the front door misses by 36 m.
	if local.distance_to(TowerInterior.lift_stand(want)) > 0.05:
		_fail("%s put the player at %s, not on storey %d's landing (%s)"
			% [what, str(local), want, str(TowerInterior.lift_stand(want))])
	if TowerInterior.current_floor(local.y) != want:
		_fail("%s left the player on storey %d rather than %d"
			% [what, TowerInterior.current_floor(local.y), want])
	if not _is_landing_cell(want, local):
		_fail("%s set the player down off the landing — not on built floor" % what)


func _stop_id_for_floor(floor_index: int) -> String:
	"""The opened-set id that earns storey `floor_index`'s stop, "" when it has none.
	Read off the graph, so the check names no id and cannot go stale on a rename."""
	for row: Dictionary in TowerGraph.lift_stops():
		if TowerInterior.landing_floor(String(row.get("room", ""))) == floor_index:
			return String(row.get("unlock", ""))
	_fail("storey %d carries no lift stop to open — check 2 should have caught that"
		% floor_index)
	return ""


# ============================================================================
# 4. THE REFUSALS, EACH WITH THE REFUSAL REMOVED AS ITS CONTROL
# ============================================================================

func _check_the_refusals() -> void:
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var player: Node3D = await _make_player()
	var panel: Control = await _make_panel()
	if interior == null:
		_fail("no interior to drive the refusals against")
		await _clear(player, shell, panel)
		Sentinel.done("refusals")
		return
	shell.call("mark_opened", TowerGraph.ENTRY_LIFT_MAZE)
	_stand_at_the_lift(player, interior, 0)
	await process_frame

	# The CALL POINT, bounded against the building's own storey height rather than
	# eyeballed. Since bead godot-test1-b9m8 this no longer prevents calling from the
	# floor above — `_call_floor()` resolves the storey first and measures only
	# against that storey's stand point — so it is a sanity bound on the number and
	# the const says so.
	if LiftMenu.CALL_RADIUS >= TowerShell.STOREY_HEIGHT:
		_fail("CALL_RADIUS (%.1f) is taller than a storey (%.1f) — a call radius that "
			% [LiftMenu.CALL_RADIUS, TowerShell.STOREY_HEIGHT]
			+ "reaches the floor above is a number nobody is thinking about any more")
	if not panel.can_open():
		_fail("the control case failed: standing at the lift, the menu still refuses")
	player.global_position += Vector3(LiftMenu.CALL_RADIUS + 5.0, 0.0, 0.0)
	if panel.can_open():
		_fail("the menu opened %.1f m from the call point — the lift is a place, not "
			% (LiftMenu.CALL_RADIUS + 5.0) + "a keypress")

	# ...and the same refusal UP A STOREY, where every landing is now a call point
	# (bead godot-test1-b9m8): being on the right floor is not being on the pad.
	# Its own control is the line after it, which stands back on that same landing.
	var storey: int = 3
	_stand_at_the_lift(player, interior, storey)
	player.global_position += Vector3(LiftMenu.CALL_RADIUS + 5.0, 0.0, 0.0)
	if panel.can_open():
		_fail("the menu opened %.1f m off storey %d's landing — a storey's plain floor "
			% [LiftMenu.CALL_RADIUS + 5.0, storey] + "is not a call point")
	_stand_at_the_lift(player, interior, storey)
	if not panel.can_open():
		_fail("the control failed: back on storey %d's landing the menu still refuses, "
			% storey + "so the refusal above proves nothing")
	_stand_at_the_lift(player, interior, 0)

	# --- IN A ROOM -----------------------------------------------------------
	var mp := StubMp.new()
	mp.busy = true
	mp.add_to_group("mp")
	root.add_child(mp)
	await process_frame
	if panel.can_open():
		_fail("the menu opened inside a room — the world is not this peer's to stop, "
			+ "and a body that vanishes eight storeys up is a teleport nobody agreed to")
	# ...and a panel already up when the room starts must close and hand the pause
	# back, which is what the per-frame re-assert in `_process` is for.
	mp.busy = false
	await process_frame
	panel.set_open(true)
	await process_frame
	mp.busy = true
	await process_frame
	if panel.is_open() or paused or PauseHub.holder_count() != 0:
		_fail("a room started under an open lift menu and it stayed up (open=%s, "
			% panel.is_open() + "paused=%s, holders=%d)" % [paused, PauseHub.holder_count()])
	mp.busy = false
	await process_frame
	if not panel.can_open():
		_fail("leaving the room did not give the lift back")

	# --- OVER GAME OVER ------------------------------------------------------
	player.is_game_over = true
	if panel.can_open():
		_fail("the menu opened over Game Over — `GameOverUI` is PAUSABLE and Play "
			+ "Again would stop answering")
	player.is_game_over = false
	if not panel.can_open():
		_fail("clearing Game Over did not give the lift back")

	# --- MID-BITE ------------------------------------------------------------
	player.is_caught = true
	if panel.can_open():
		_fail("the menu opened while the hero was being caught — the freeze after a "
			+ "bite is a bill being paid, not a moment to leave the room in")
	player.is_caught = false

	# --- AND A NODE THAT GOES AWAY RELEASES WHAT IT HELD ---------------------
	panel.set_open(true)
	await process_frame
	if not paused:
		_fail("the control for the free-while-open case never took the pause")
	panel.queue_free()
	await process_frame
	await process_frame
	if paused or PauseHub.holder_count() != 0:
		_fail("the menu was freed while open and left the tree paused forever "
			+ "(paused=%s, holders=%d)" % [paused, PauseHub.holder_count()])

	mp.queue_free()
	await _clear(player, shell, null)
	Sentinel.done("refusals")


# ============================================================================
# 5. THE PAD HINT — bead godot-test1-b9m8, owner ruling 2
# ============================================================================

func _check_the_pad_hint() -> void:
	"""
	"L — lift" is up exactly while pressing L would do something.

	READ OFF THE NODE BY NAME, never off `can_open()`: the hint exists because the
	owner stood on a pad and had no way to know the key existed, so a check that
	asked the same predicate the label asks would prove nothing about the label.
	"""
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	var player: Node3D = await _make_player()
	var panel: Control = await _make_panel()
	if interior == null:
		_fail("no interior to drive the pad hint against")
		await _clear(player, shell, panel)
		Sentinel.done("pad_hint")
		return
	var hint := panel.get_node_or_null("PadHint") as Label
	if hint == null:
		_fail("the lift panel builds no PadHint label — a pad with no hint is the bug "
			+ "this bead was filed for")
		await _clear(player, shell, panel)
		Sentinel.done("pad_hint")
		return

	# THE WORDS. The format string is SPELLED HERE and not read off `HINT_LINE`,
	# deliberately: a translation key IS the English string, so comparing the label
	# to the constant it was built from would assert nothing and would go on passing
	# after a reword that left `assets/translations/ui.csv` (and German) behind.
	# The KEY is still derived, because that half must follow `TOGGLE_KEY`.
	var want: String = tr("%s — lift") % OS.get_keycode_string(LiftMenu.TOGGLE_KEY)
	if hint.text != want:
		_fail(("the pad hint reads '%s', not '%s' — the words are a CSV key and the key "
			+ "it names must be the key it is") % [hint.text, want])
	if LiftMenu.HINT_LINE != "%s — lift":
		_fail("the pad hint's format string is '%s' — reword it in ui.csv too, or German "
			% LiftMenu.HINT_LINE + "silently falls back to English")

	# --- UP ON A PAD, on an UPPER storey: the owner's exact case ------------
	var storey: int = 3
	_stand_at_the_lift(player, interior, storey)
	await process_frame
	if not hint.visible:
		_fail("the pad hint stayed hidden while the player stood on storey %d's landing"
			% storey)

	# --- DOWN OFF IT --------------------------------------------------------
	player.global_position += Vector3(LiftMenu.CALL_RADIUS + 5.0, 0.0, 0.0)
	await process_frame
	if hint.visible:
		_fail("the pad hint stayed up %.1f m off the pad — it would promise a key that "
			% (LiftMenu.CALL_RADIUS + 5.0) + "does nothing")

	# --- DOWN UNDER THE OPEN MENU, and back up when it closes ---------------
	_stand_at_the_lift(player, interior, storey)
	await process_frame
	panel.set_open(true)
	await process_frame
	if hint.visible:
		_fail("the pad hint stayed up behind the open card — it is the thing that says "
			+ "the card exists, and the card is already saying so")
	panel.set_open(false)
	await process_frame
	if not hint.visible:
		_fail("closing the card did not bring the pad hint back — the control for the "
			+ "assertion above never fired")

	# --- DOWN IN A ROOM -----------------------------------------------------
	# One refusal is enough to prove the hint inherits ALL of them: it reads
	# `can_open()`, which check 4 drives through every one.
	var mp := StubMp.new()
	mp.busy = true
	mp.add_to_group("mp")
	root.add_child(mp)
	await process_frame
	if hint.visible:
		_fail("the pad hint stayed up inside a room, where the lift refuses to open")
	mp.busy = false
	await process_frame
	if not hint.visible:
		_fail("leaving the room did not bring the pad hint back")
	mp.queue_free()

	# --- DOWN UNDER SOMEBODY ELSE'S PAUSE (revmux round 1) ------------------
	# Every full-screen overlay in this HUD — the help card's 0.82 dim, the city
	# map, the skill tree — draws UNDER this node and holds the pause while it is
	# up. An always-on label would float on top of all of them. Driven through
	# `PauseHub` with a foreign holder, which is exactly what those panels are.
	var other := Node.new()
	root.add_child(other)
	PauseHub.take(other)
	await process_frame
	if hint.visible:
		_fail("the pad hint stayed up under a foreign pause — it would draw over the "
			+ "help card, the city map and the skill tree, all of which are beneath it")
	if panel.can_open():
		_fail("the lift would open over a full-screen overlay that already holds the "
			+ "pause — two PauseHub holders and a card on top of a card")
	PauseHub.release(other)
	other.queue_free()
	await process_frame
	if not hint.visible:
		_fail("releasing the foreign pause did not bring the pad hint back — the "
			+ "control for the assertion above never fired")

	# --- AND IT FOLLOWS A LIVE LOCALE SWITCH --------------------------------
	# `_hint.text` is COMPOSED, so it is not its own key and Godot's auto-translate
	# cannot re-resolve it: the panel carries `NOTIFICATION_TRANSLATION_CHANGED`
	# for that, and this is what says so. `locale_selfcheck`'s idiom.
	var was_locale: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	await process_frame
	var want_de: String = tr("%s — lift") % OS.get_keycode_string(LiftMenu.TOGGLE_KEY)
	if want_de == want:
		_fail("the German row for the pad hint equals the English one — this assertion "
			+ "would pass on a label frozen in English")
	elif hint.text != want_de:
		_fail("after switching to German the pad hint still reads '%s', not '%s' — a "
			% [hint.text, want_de] + "composed string needs the translation hook")
	TranslationServer.set_locale(was_locale)
	await process_frame
	if hint.text != want:
		_fail("switching back to '%s' left the pad hint reading '%s', not '%s'"
			% [was_locale, hint.text, want])

	await _clear(player, shell, panel)
	Sentinel.done("pad_hint")


# ============================================================================
# HARNESS
# ============================================================================

# ============================================================================
# 6. THE MEMORY IS PER-RUN (bead godot-test1-4ban, owner ruling 2026-09-16)
# ============================================================================

func _check_the_memory_is_per_run() -> void:
	"""
	The owner's report, as a check: a landing walked in an EARLIER session must
	not be on the menu of a fresh run.

	THE LIFETIME IS THE SHELL'S, and that is the whole design. A visited landing
	rides the shell's monotone opened set exactly as a gate does — so it is
	room-shared over `gate`/`g`/`go` for free, with no verb and no codec change —
	and the only thing that differs is that `BestRunStore` refuses to store it
	(`TowerGraph.is_lift_stop_id`). The shell is freed by `_tower_reset()` on
	every seed write and by nothing else, which IS "per run, and a waypoint hop
	keeps it". So nothing new clears anything, and what this check has to pin is
	the two halves of that sentence: the profile never sees a landing, and a gate
	earned in the same breath still does.

	Leg (d) drives the real terrain seam rather than arguing it. The other half of
	it — a `relocate()` hop keeping the landing — is pinned in
	`waypoint_travel_selfcheck`'s check 3, which already has a booted world and
	the shell-identity assertion this would otherwise duplicate.
	"""
	_fresh_store()
	var shell := await _make_tower()
	var interior := shell.get_node_or_null("TowerInterior") as TowerInterior
	if interior == null:
		_fail("the tower has no TowerInterior child — the per-run probe has no subject")
		await _clear(null, shell, null)
		Sentinel.done("memory_is_per_run")
		return
	var player: Node3D = await _make_player()
	var panel: Control = await _make_panel()
	_stand_at_the_lift(player, interior, 0)
	await process_frame

	# --- (a) EARNED THROUGH THE SHIPPED TRIGGER, OFFERED, NEVER SAVED --------
	# `_on_lift_stop_enter` and not `mark_opened`: the claim is about the path the
	# building really walks, persist flag and all.
	var storey: int = 3
	var stop_id: String = _stop_id_for_floor(storey)
	interior._on_lift_stop_enter(player, stop_id)
	panel.set_open(true)
	await process_frame
	var offered: Array = panel.stop_floors()
	if offered != [storey]:
		_fail("standing on storey %d's landing left the menu offering %s"
			% [storey, str(offered)])
	panel.set_open(false)
	if BestRunStore.tower_opened_ids().has(stop_id):
		_fail("the landing '%s' reached the profile — the lift would remember it "
			% stop_id + "on every future run")

	# --- (b) NEGATIVE CONTROL: a gate earned in the same run DOES persist ----
	shell.call("mark_opened", TowerInterior.GATE_CHECKPOINT)
	if not BestRunStore.tower_opened_ids().has(TowerInterior.GATE_CHECKPOINT):
		_fail("the checkpoint stopped persisting — the filter is eating earned "
			+ "progression, not just the lift's landings")

	# --- (c) A NEW RUN: the shell is freed and streamed again ----------------
	# `_tower_reset()` + `_tower_stream()`, in the only form that matters to this
	# claim — the second shell hydrates from the profile and from nothing else.
	await _clear(null, shell, null)
	var second := await _make_tower()
	var second_interior := second.get_node_or_null("TowerInterior") as TowerInterior
	if second_interior == null:
		_fail("the rebuilt tower has no TowerInterior child")
		await _clear(player, second, panel)
		Sentinel.done("memory_is_per_run")
		return
	if not second.is_opened(TowerInterior.GATE_CHECKPOINT):
		_fail("the new run's tower forgot a gate earned in the old one — the filter "
			+ "took the whole set with it")
	if second.is_opened(stop_id):
		_fail("the new run's tower came up with landing '%s' already walked — the "
			% stop_id + "owner's bug, exactly")
	_stand_at_the_lift(player, second_interior, 0)
	await process_frame
	panel.set_open(true)
	await process_frame
	if not (panel.stop_floors() as Array).is_empty():
		_fail("the new run's lift offered %s from the ground — a fresh run rides "
			% str(panel.stop_floors()) + "nowhere until a landing is walked")
	if _row_count(panel) != 1:
		_fail("the new run's menu drew %d rows, not the one line that says there "
			% _row_count(panel) + "is nothing to ride to")
	panel.set_open(false)
	await _clear(player, second, panel)

	# --- (d) THE REAL SEAM: a seed write frees the shell ---------------------
	# `tower_shell_selfcheck`'s terrain idiom — the streaming is driven directly,
	# because the trigger is that file's subject and the RESET is this one's.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	terrain.set_run_seed(1234)
	terrain._tower_stream(terrain.tower_site())
	var streamed: Node3D = terrain.tower_shell()
	if streamed == null:
		_fail("streaming at the site built no shell — the reset probe has no subject")
	else:
		streamed.call("mark_opened", stop_id)
		if not bool(streamed.call("is_opened", stop_id)):
			_fail("the streamed shell did not take the landing — the reset probe "
				+ "measured no setup")
		terrain.set_run_seed(5678)
		if terrain.tower_shell() != null:
			_fail("a seed write left the shell standing — `_tower_reset()` is what "
				+ "ends the lift's memory, and nothing else does")
	terrain.queue_free()
	await process_frame
	_fresh_store()
	Sentinel.done("memory_is_per_run")


func _make_tower() -> Node3D:
	## Shell plus interior, assembled the way `endless_terrain` assembles them — the
	## interior added BEFORE the shell enters the tree, so it can see its parent.
	var shell := load(SHELL_SCENE).instantiate() as Node3D
	shell.add_child(load(INTERIOR_SCENE).instantiate())
	root.add_child(shell)
	await process_frame
	return shell


func _make_player() -> Node3D:
	"""A real `player.tscn` in the tree, with whatever the staging frame did to it
	undone — `city_map_selfcheck._make_player`'s rule and its reason."""
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	player.is_caught = false
	player.is_respawning = false
	player.is_game_over = false
	return player as Node3D


func _make_panel() -> Control:
	var panel: Control = Control.new()
	panel.set_script(LiftMenu)
	root.add_child(panel)
	await process_frame
	return panel


func _stand_at_the_lift(player: Node3D, interior: Node3D, floor_index: int) -> void:
	"""Put the player on storey `floor_index`'s landing cell — its call point."""
	player.global_position = interior.global_position + TowerInterior.lift_stand(floor_index)


func _row_count(panel: Control) -> int:
	"""How many lines the card is really showing — read off the nodes, not off the
	panel's own bookkeeping, so a menu that computed the right offer and drew the
	wrong thing still fails."""
	var rows := panel.get_node_or_null("Centre/Card/Frame/Column/Stops")
	return 0 if rows == null else rows.get_child_count()


func _digit_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _clear(player: Node, shell: Node, panel: Node) -> void:
	"""Free a check's probes. NOT tidiness: a leftover probe leaves a second node in
	group "player", and the next check's `get_first_node_in_group` picks one of them
	at random (`TowerProbe.clear`'s lesson)."""
	for node: Node in [player, shell, panel]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame


func _fresh_store() -> void:
	"""Delete the throwaway save, so the next assertion starts from a clean profile.
	Never the real one — `Sentinel.isolate_user_state()` moved
	`BestRunStore.config_path` into this process's own scratch directory."""
	DirAccess.remove_absolute(BestRunStore.config_path)
