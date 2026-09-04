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
##  2. EVERY STOP IS AN AUDITED ENTRY. `TowerGraph.lift_stops()` is derived from
##     the mutation table, so this asserts the derivation lands on rows that are
##     really entries, really `built`, really carry an `unlock` id, and really
##     resolve to a storey whose landing the arrival point stands on. That is the
##     bead's acceptance ("every stop is an audited entry in tower_graph entries")
##     and it is what binds the menu to `tower_selfcheck`'s fifteen-subset walk,
##     which already starts from each of these entries.
##  3. THE MENU ON A REAL SHELL. A tower with an empty opened set offers NOTHING;
##     the stop the trigger writes appears the moment it is opened and not before;
##     the checkpoint's id lights the OTHER stop, which is the whole of `unlock`
##     being a row field rather than the entry's own name; choosing one puts a real
##     `player.tscn` on that storey's `s` landing; and a floor that was never
##     offered is refused. Each with its mutation control.
##  4. THE REFUSALS. In a room, over game over, mid-bite and away from the call
##     point — every one of them asserted with the refusal REMOVED as the control,
##     because a `can_open()` that answered false for the wrong reason would pass
##     all four otherwise. Plus the pause: taken solo through `PauseHub`, handed
##     back on close, and handed back by `_process` when a refusal becomes true
##     under an open panel.
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
const MotionDebug := preload("res://scripts/motion_debug.gd")
const MobileInput := preload("res://scripts/mobile_input.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const MobileSettingsPanel := preload("res://scripts/mobile_settings_panel.gd")
const SkillTreeUi := preload("res://scripts/skill_tree_ui.gd")
const CityMapPanel := preload("res://scripts/city_map_panel.gd")
const LandmarkToast := preload("res://scripts/landmark_toast.gd")

const SHELL_SCENE: String = "res://scenes/tower/tower_shell.tscn"
const INTERIOR_SCENE: String = "res://scenes/tower/tower_interior.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"

## Throwaway save file this check points `BestRunStore.config_path` at for its
## whole run. NOTHING HERE MAY OPEN THE MACHINE'S `user://best_run.cfg`: a shell
## hydrates from the store on entering the tree and WRITES THROUGH on every id it
## opens, so without the redirect check 3 would store lift ids into a developer's
## real profile — `tower_interior_selfcheck`'s trap, verbatim.
const LOCAL_STORE_PATH: String = "user://tower_lift_selfcheck_best_run.cfg"


class StubMp extends Node:
	var busy: bool = false

	func is_busy() -> bool:
		return busy


## THE END-OF-CHECK SENTINEL — see `scripts/selfcheck_sentinel.gd`.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	BestRunStore.config_path = LOCAL_STORE_PATH
	_fresh_store()
	# ONE FRAME FIRST: a node added to `root` from inside `_initialize()` is not
	# `is_inside_tree()` until the first frame, so anything reading a global
	# transform measures a detached world (every tower check records this).
	await process_frame

	_check_key_is_free()
	_check_stops_are_audited_entries()
	await _check_the_menu_on_a_real_shell()
	await _check_the_refusals()

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
		[HelpOverlay.HELP_KEYCODES, "help_overlay.HELP_KEYCODES"],
		[LandmarkToast.ANSWER_KEYCODES, "landmark_toast.ANSWER_KEYCODES"],
		[PlayerScript.HERO_KEYCODES, "player_controller.HERO_KEYCODES"],
		[[PerfOverlay.TOGGLE_KEYCODE], "perf_overlay.TOGGLE_KEYCODE"],
		[[MotionDebug.TOGGLE_KEYCODE], "motion_debug.TOGGLE_KEYCODE"],
		[[MobileInput.FORCE_ENABLE_KEYCODE], "mobile_input.FORCE_ENABLE_KEYCODE"],
		[[TouchControls.FORCE_SHOW_KEYCODE], "touch_controls.FORCE_SHOW_KEYCODE"],
		[[MobileSettingsPanel.FORCE_SHOW_KEYCODE], "mobile_settings_panel.FORCE_SHOW_KEYCODE"],
	]
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
	_stand_at_the_lift(player, interior)
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
	player._input(_digit_event(int((PlayerScript.HERO_KEYCODES[other] as Array)[0])))
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
	var local: Vector3 = player.global_position - interior.global_position
	# A hand's width of slack, not exact equality: the ride is a hard write and the
	# menu's pause stops physics, but a check that fails on one settling frame would
	# be measuring the pause rather than the lift. Mutation-tested: a ride that lands
	# at the front door misses by 36 m.
	if local.distance_to(TowerInterior.lift_stand(maze_floor)) > 0.05:
		_fail("the ride put the player at %s, not on storey %d's landing (%s)"
			% [str(local), maze_floor, str(TowerInterior.lift_stand(maze_floor))])
	if TowerInterior.current_floor(local.y) != maze_floor:
		_fail("the ride left the player on storey %d rather than %d"
			% [TowerInterior.current_floor(local.y), maze_floor])
	if not _is_landing_cell(maze_floor, local):
		_fail("the ride set the player down off the landing — not on built floor")
	if panel.is_open() or paused or PauseHub.holder_count() != 0:
		_fail("the lift arrived with the menu still up (open=%s, paused=%s, holders=%d)"
			% [panel.is_open(), paused, PauseHub.holder_count()])

	# --- THE OTHER STOP IS THE CHECKPOINT'S, WHICH IS WHAT `unlock` BUYS ------
	_stand_at_the_lift(player, interior)
	shell.call("mark_opened", TowerGraph.GATE_CHECKPOINT)
	var upper_floor: int = TowerInterior.landing_floor(
			String(TowerGraph.entry(TowerGraph.ENTRY_LIFT_UPPER).get("room", "")))
	panel.set_open(true)
	await process_frame
	offered = panel.stop_floors()
	if not offered.has(upper_floor):
		_fail("lighting the checkpoint did not offer storey %d — `unlock` names the "
			% upper_floor + "id that earns a stop, and this one is not the entry's own")
	if _row_count(panel) != offered.size():
		_fail("the menu drew %d rows for %d stops" % [_row_count(panel), offered.size()])
	panel.set_open(false)
	await process_frame

	await _clear(player, shell, panel)
	Sentinel.done("menu_on_a_shell")


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
	_stand_at_the_lift(player, interior)
	await process_frame

	# The CALL POINT. A radius that reached a whole storey up would call the lift
	# from the landing it is a shortcut to, so it is asserted against the building's
	# own storey height rather than eyeballed.
	if LiftMenu.CALL_RADIUS >= TowerShell.STOREY_HEIGHT:
		_fail("CALL_RADIUS (%.1f) reaches past one storey (%.1f) — the lift would be "
			% [LiftMenu.CALL_RADIUS, TowerShell.STOREY_HEIGHT] + "callable from the floor above")
	if not panel.can_open():
		_fail("the control case failed: standing at the lift, the menu still refuses")
	player.global_position += Vector3(LiftMenu.CALL_RADIUS + 5.0, 0.0, 0.0)
	if panel.can_open():
		_fail("the menu opened %.1f m from the call point — the lift is a place, not "
			% (LiftMenu.CALL_RADIUS + 5.0) + "a keypress")
	_stand_at_the_lift(player, interior)

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
# HARNESS
# ============================================================================

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


func _stand_at_the_lift(player: Node3D, interior: Node3D) -> void:
	player.global_position = interior.global_position + TowerInterior.lift_stand(0)


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
	at random (`tower_interior_selfcheck._clear`'s lesson)."""
	for node: Node in [player, shell, panel]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	await process_frame


func _fresh_store() -> void:
	"""Delete the throwaway save, so the next assertion starts from a clean profile.
	Never the real one — see `LOCAL_STORE_PATH`."""
	DirAccess.remove_absolute(LOCAL_STORE_PATH)
