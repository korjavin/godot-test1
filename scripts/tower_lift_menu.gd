extends Control
## ============================================================================
## THE HQ'S SERVICE LIFT — L at the ground landing, a stop you have earned
## ============================================================================
##
## Bead `godot-test1-3iy.7`, the last item of tower phase 7 (the wing builder and
## the staged growth it was filed with were superseded by phase 14's ASCII plans).
## The tower is ten storeys and the labyrinth is on eight of them; walking back up
## is the tax a SECOND visit pays, and this is the receipt for the first one.
##
## ============================================================================
## A STOP IS AN ENTRY, AND UNLOCKED MEANS "IN THE OPENED SET"
## ============================================================================
##
## Nothing here is authored. `TowerGraph.lift_stops()` is every entry a MUTATION
## grants — today `lift_stop_upper` (the checkpoint powers the lift) and
## `lift_stop_maze` (walking to the labyrinth's foot calls it there) — and each
## row's `unlock` names the id that earns it in the tower's monotone opened set.
## So this panel holds no table, no floor number and no stop name: it asks the
## graph which stops exist, asks the SHELL which ids are open, and asks
## `TowerInterior.landing_floor()` which storey each one lands on. A third lift
## stop is a `TOWER_GRAPH` row and nothing else — the extension rule the whole
## building is written to.
##
## THE RIDE IS ALWAYS LEGAL, and that is the audit's doing rather than this file's:
## `tower_selfcheck` walks all fifteen hero subsets FROM every entry a mutation can
## grant, in every story and scar state, so a stop can only ever be somewhere the
## campaign is completable from. Landing you there needs no check of its own.
##
## ============================================================================
## WHERE IT OPENS
## ============================================================================
##
## At the GROUND landing (`TowerInterior.lift_stand(0)`), within `CALL_RADIUS` —
## the foot of the ramp you climb anyway, so the call point is a place you already
## walk through rather than a thing to find. The two refusals are `city_map_panel`'s
## and `landmark_toast`'s, for their reasons: IN A ROOM (the world is not yours to
## freeze, and a body that vanishes eight storeys up is a teleport three teammates
## did not agree to) and OVER GAME OVER (`GameOverUI` is pausable — a pause there
## kills Play Again). A caught hero is refused too: the freeze after a bite is a
## bill being paid, not a moment to leave the room in.
##
## ponytail: ONE WAY, up from the ground floor. The graph's shaft edges are
## undirected and the lift could call from any unlocked landing, but going DOWN is
## a ramp with no gates on it and this is the trip that costs eight storeys. Make
## `_call_floor()` answer more than 0 if playtests ask for the round trip.
## ponytail: no car, no doors and no shaft geometry — the landing IS the lobby,
## exactly as `_build_lift_stop` draws nothing at the other end. Art, when the
## building gets an art pass; the box budgets do not move for this bead.
##
## ============================================================================
## LOCALIZATION
## ============================================================================
##
## RULE 1 for the title (a plain literal on a Label). RULE 2 for the composed
## lines, `tr()` on the FORMAT string: a stop row's words are "Floor %d", the
## minimap's own key, so the storey number a player reads is written in ONE
## language-table row for both surfaces. The close hint is `city_map_panel`'s
## string, deliberately the same words for the same gesture.

## The player's group and the two tower groups, discovered rather than referenced
## (CLAUDE.md: no `$`-paths, no exported references).
const PLAYER_GROUP: String = "player"
const INTERIOR_GROUP: String = "tower_interior"

# ============================================================================
# THE KEY
# ============================================================================

## The open/close key. A raw keycode OUTSIDE the input map, like `K`, `M`, `P` and
## `B`: a key that only opens a panel has nothing to rebind against (CLAUDE.md).
## `L` for lift, and it is free — `tower_lift_selfcheck` check 1 asserts that
## against `project.godot` and against every other panel's constant rather than
## against a list written down here.
const TOGGLE_KEY: Key = KEY_L

## The stop keys, in order: the first row is `1`. Raw keycodes again, and they are
## live ONLY while the panel is open, which is what lets them share the digits the
## hero picker and the landmark quiz already use.
const CHOICE_KEYCODES: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]

# ============================================================================
# WHERE YOU HAVE TO BE STANDING
# ============================================================================

## How far from `TowerInterior.lift_stand(0)` the call button reaches, in metres.
## Under one storey height (`TowerShell.STOREY_HEIGHT`) BY ASSERTION in the
## self-check, not by luck: a sphere that reached the floor above would call the
## lift from the landing it is meant to be a shortcut to.
const CALL_RADIUS: float = 3.5

# ============================================================================
# THE CARD
# ============================================================================

const CARD_PADDING: int = 18
const TITLE_FONT_SIZE: int = 22
const LINE_FONT_SIZE: int = 18
const HINT_FONT_SIZE: int = 14
const COLOR_TITLE: Color = Color(1.0, 0.84, 0.26)
const COLOR_TEXT: Color = Color(0.90, 0.92, 0.95)
const COLOR_HINT: Color = Color(0.62, 0.66, 0.72)

## The composed lines. RULE 2: `tr()` runs on these, never on the result — except
## `STOP_LINE`, which is a frame of punctuation with no words in it and so has no
## CSV row to have (`locale_selfcheck` fails a row whose German equals its
## English, which is what a translated bracket would be).
## "Floor %d" is `minimap_hud`'s storey caption — one CSV row, both surfaces.
const STOP_LINE: String = "[%d]  %s"
const FLOOR_LINE: String = "Floor %d"
const CLOSE_HINT: String = "Press %s or Esc to close"
const EMPTY_LINE: String = "No floors unlocked yet."

var _open: bool = false
var _paused_by_us: bool = false
## The floors the rows currently offer, in row order. The panel's whole state, and
## what the self-check reads back instead of scraping labels.
var _offered: Array[int] = []

var _card: PanelContainer = null
var _rows: VBoxContainer = null
var _hint_label: Label = null


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available HUD
	# piece (`city_map_panel`, `skill_tree_ui`, `mp_ui`).
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("tower_lift_menu")
	_build_ui()


func _process(_delta: float) -> void:
	# One rule, re-asserted every frame: a panel that may no longer be open is
	# closed. That covers joining a room with the menu up, dying with it up, and
	# walking away from the call point — and it is why `_apply_pause` never has to
	# reason about a state that changed underneath it (`mp_ui`'s concern).
	if _open and not can_open():
		set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if event == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	# Esc closes, and only while we are open — otherwise this eats the `ui_cancel`
	# `player_controller._input()` uses to release the mouse. `city_map_panel`'s
	# guard, for `city_map_panel`'s reason.
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_open(false)
		return
	if key.keycode == TOGGLE_KEY:
		if _open:
			get_viewport().set_input_as_handled()
			set_open(false)
		elif can_open():
			get_viewport().set_input_as_handled()
			set_open(true)
		return
	if _open:
		var choice := CHOICE_KEYCODES.find(key.keycode)
		if choice >= 0 and choice < _offered.size():
			get_viewport().set_input_as_handled()
			ride_to(_offered[choice])


func _exit_tree() -> void:
	# Never leave the world frozen behind a node that is going away.
	_apply_pause(false)


# ============================================================================
# OPEN / CLOSE
# ============================================================================

func is_open() -> bool:
	return _open


func can_open() -> bool:
	"""
	Is the local player standing at the ground-floor lift, in a session that may
	stop the world?

	Every refusal the header lists, in one predicate, so `_process`'s re-assert and
	the keypress ask the same question. Null-safe throughout: a scene with no tower
	and no player answers false rather than erroring (the standalone degrade every
	group lookup in this project owes).
	"""
	var tree := get_tree()
	if tree == null:
		return false
	if _in_room() or _game_over() or _caught():
		return false
	var interior: Node = tree.get_first_node_in_group(INTERIOR_GROUP)
	var player: Node = tree.get_first_node_in_group(PLAYER_GROUP)
	if interior == null or player == null:
		return false
	if not (interior is Node3D) or not (player is Node3D):
		return false
	var local: Vector3 = (player as Node3D).global_position \
			- (interior as Node3D).global_position
	return local.distance_to(TowerInterior.lift_stand(_call_floor())) <= CALL_RADIUS


func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	if open:
		_refresh()
	if _card != null:
		_card.visible = open
	_apply_pause(open)


func stop_floors() -> Array[int]:
	"""
	The storeys the lift may take you to right now, lowest first.

	@return: a fresh Array of `FLOOR_Y` indices — the offer, and the only thing
	        this panel decides.

	Three rows of arithmetic and no table: a stop is an entry a mutation grants
	(`TowerGraph.lift_stops()`), it is unlocked when its `unlock` id is in the
	shell's opened set, and it lands on the storey whose plan claims its room as
	the landing. A stop whose room no storey draws — a wave-C reservation — simply
	resolves to -1 and is skipped, `minimap_hud._gather_tower`'s degrade.
	"""
	var out: Array[int] = []
	var tree := get_tree()
	if tree == null:
		return out
	var interior: Node = tree.get_first_node_in_group(INTERIOR_GROUP)
	if interior == null:
		return out
	var shell: Node = interior.get_parent()
	if shell == null or not shell.has_method("is_opened"):
		return out
	var here := _call_floor()
	for row: Dictionary in TowerGraph.lift_stops():
		var unlock := String(row.get("unlock", ""))
		if unlock == "" or not bool(shell.call("is_opened", unlock)):
			continue
		var floor_index := TowerInterior.landing_floor(String(row.get("room", "")))
		if floor_index < 0 or floor_index == here or out.has(floor_index):
			continue
		out.append(floor_index)
	out.sort()
	return out


func ride_to(floor_index: int) -> bool:
	"""
	Take the lift to `floor_index`: the player is set down on that storey's landing.

	@return: true when the ride happened.

	A HARD MOVE AND NOTHING ELSE. The lift is a shortcut through a building that is
	already audited to be walkable from that landing, so there is no travel state to
	hold, nothing to animate and nothing to interrupt — and no ability state to
	clear, because a lift ride is not a respawn and not a character switch.
	`velocity` goes to zero for the one reason it always does: carried momentum
	against a wall eight storeys up is a body wedged in stone.
	"""
	if not _offered.has(floor_index):
		return false
	var tree := get_tree()
	var interior: Node = null if tree == null else tree.get_first_node_in_group(INTERIOR_GROUP)
	var player: Node = null if tree == null else tree.get_first_node_in_group(PLAYER_GROUP)
	if interior == null or player == null:
		return false
	var body := player as Node3D
	body.global_position = (interior as Node3D).global_position \
			+ TowerInterior.lift_stand(floor_index)
	if "velocity" in body:
		body.set("velocity", Vector3.ZERO)
	var sound: Node = null if tree == null else tree.get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method("play_level_up"):
		sound.call("play_level_up")
	set_open(false)
	return true


func _call_floor() -> int:
	"""The storey the lift is called FROM. Ground, and see the header's ponytail."""
	return 0


func _apply_pause(open: bool) -> void:
	"""
	Take or give back the pause. `PauseHub`, never `get_tree().paused` — the one
	rule `pause_selfcheck` check 3 scans every script in this directory for.

	No policy of its own: `can_open()` already refused every state the panel may not
	freeze, and `_process` closes it the moment one of them becomes true, so "open"
	and "may pause" are the same bit here.
	"""
	if not open and not _paused_by_us:
		return  # the overwhelmingly common case: closed panel, nothing to undo.
	if get_tree() == null:
		return
	if open and not _paused_by_us:
		PauseHub.take(self)
		_paused_by_us = true
	elif not open and _paused_by_us:
		_paused_by_us = false
		PauseHub.release(self)


func _in_room() -> bool:
	"""Is this peer engaged with the lobby at all? `is_busy()`, not `is_online()`:
	a join in flight is already a session somebody else's frames belong to."""
	var tree := get_tree()
	if tree == null:
		return false
	var mp: Node = tree.get_first_node_in_group("mp")
	return mp != null and mp.has_method("is_busy") and bool(mp.call("is_busy"))


func _game_over() -> bool:
	# `"x" in node`, not `node.get("x")`: `get()` answers null for a missing
	# property and `bool(null)` is a hard error, so this is what lets a scene whose
	# player is a stand-in degrade instead of throwing.
	var player: Node = _player()
	return player != null and "is_game_over" in player and bool(player.is_game_over)


func _caught() -> bool:
	var player: Node = _player()
	return player != null and "is_caught" in player and bool(player.is_caught)


func _player() -> Node:
	var tree := get_tree()
	return null if tree == null else tree.get_first_node_in_group(PLAYER_GROUP)


# ============================================================================
# THE UI
# ============================================================================

func _refresh() -> void:
	"""Rebuild the rows from `stop_floors()`. Called on every open — the offer
	changes only when a stop is earned, which cannot happen with the menu up."""
	_offered = stop_floors()
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	if _offered.is_empty():
		_rows.add_child(_line(tr(EMPTY_LINE), LINE_FONT_SIZE, COLOR_HINT))
	for i: int in _offered.size():
		# RULE 2 twice over, and deliberately: the storey number is the minimap's
		# own "Floor %d" row, and the bracketed key is this panel's frame round it.
		var floor_name: String = tr(FLOOR_LINE) % (_offered[i] + 1)
		_rows.add_child(_line(STOP_LINE % [i + 1, floor_name],
				LINE_FONT_SIZE, COLOR_TEXT))
	if _hint_label != null:
		_hint_label.text = tr(CLOSE_HINT) % OS.get_keycode_string(TOGGLE_KEY)


func _line(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _build_ui() -> void:
	# A CenterContainer so the card sizes to its own content and stays centred at
	# any resolution — `city_map_panel`'s and `start_overlay`'s shape. It also means
	# German grows the card instead of overflowing it, which is why this panel has
	# no `locale_selfcheck` width budget and may not need one.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	centre.add_child(_card)

	var margin := MarginContainer.new()
	margin.name = "Frame"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CARD_PADDING)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)

	# RULE 1: a plain literal on a Label, translated by the engine for free.
	var title := Label.new()
	title.text = "SERVICE LIFT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	column.add_child(title)

	_rows = VBoxContainer.new()
	_rows.name = "Stops"
	column.add_child(_rows)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	column.add_child(_hint_label)
