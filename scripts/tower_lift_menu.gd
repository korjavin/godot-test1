extends Control
## ============================================================================
## THE HQ'S SERVICE LIFT — L on any landing, to any landing you have walked
## ============================================================================
##
## Bead `godot-test1-3iy.7`, the last item of tower phase 7 (the wing builder and
## the staged growth it was filed with were superseded by phase 14's ASCII plans),
## opened out by bead `godot-test1-b9m8` on an owner ruling: the lift stops at
## EVERY storey, called from any of them, up and down.
##
## ============================================================================
## A STOP IS AN ENTRY, AND UNLOCKED MEANS "IN THE OPENED SET"
## ============================================================================
##
## Nothing here is authored. `TowerGraph.lift_stops()` is every entry a MUTATION
## grants — one per storey above the ground since `b9m8` — and each row's `unlock`
## names the id that earns it in the tower's monotone opened set. So this panel
## holds no table, no floor number and no stop name: it asks the graph which stops
## exist, asks the SHELL which ids are open, and asks
## `TowerInterior.landing_floor()` which storey each one lands on. A new lift stop
## is a `TOWER_GRAPH` row and nothing else — the extension rule the whole building
## is written to.
##
## THE RIDE IS ALWAYS LEGAL, and that is the audit's doing rather than this file's:
## `tower_selfcheck` walks all fifteen hero subsets FROM every entry a mutation can
## grant, in every story and scar state, so a stop can only ever be somewhere the
## campaign is completable from. Landing you there needs no check of its own.
##
## ============================================================================
## WHERE IT OPENS, AND WHERE IT WILL TAKE YOU
## ============================================================================
##
## OPENS on any landing the building draws — the ground's (`lift_stand(0)`) or any
## storey's — within `CALL_RADIUS` of `TowerInterior.lift_stand()` for that floor.
## The gate on opening is REACHABILITY, not earning: if you are standing there you
## walked there, and a call button you may not press is a bug report. The "L — lift"
## hint below says so on the spot, which is how a player finds the pad at all.
##
## OFFERS the ground plus every landing ALREADY STOOD ON, minus the one you are on
## (owner ruling 3): the lift never skips you past content you have not walked
## once, and it always takes you home. Standing on a landing is what earns it —
## `TowerInterior`'s `LiftStopTrigger<floor>` writes that storey's entry id into the
## monotone opened set, which persists and rides the `gate` verb to the room.
##
## The refusals are `city_map_panel`'s and `landmark_toast`'s, for their reasons:
## IN A ROOM (the world is not yours to freeze, and a body that vanishes eight
## storeys up is a teleport three teammates did not agree to) and OVER GAME OVER
## (`GameOverUI` is pausable — a pause there kills Play Again). A caught hero is
## refused too: the freeze after a bite is a bill being paid, not a moment to leave
## the room in.
##
## ponytail: no car, no doors and no shaft geometry — the landing IS the lobby,
## exactly as `_build_lift_stops` draws nothing at the other end. The call cell's
## painted plate is bead `godot-test1-i1xj`, deliberately after this one.
##
## ============================================================================
## LOCALIZATION
## ============================================================================
##
## RULE 1 for the title (a plain literal on a Label). RULE 2 for the composed
## lines, `tr()` on the FORMAT string: a stop row's words are "Floor %d", the
## minimap's own key, so the storey number a player reads is written in ONE
## language-table row for both surfaces. The close hint is `city_map_panel`'s
## string, deliberately the same words for the same gesture. The pad hint is
## RULE 2 as well ("%s — lift", the key composed in) and it carries no width
## budget: it is transparent lettering with no frame, so German has nothing to
## overflow.

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
## Nine of them since bead `godot-test1-b9m8`, and nine is the whole offer by
## construction: ten storeys minus the one you are standing on. Check 1 asserts
## there are at least as many keys as `TowerGraph.lift_stops()` has rows.
const CHOICE_KEYCODES: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6,
		KEY_7, KEY_8, KEY_9]

# ============================================================================
# WHERE YOU HAVE TO BE STANDING
# ============================================================================

## How far from this storey's `TowerInterior.lift_stand()` the call button reaches,
## in metres.
## Under one storey height (`TowerShell.STOREY_HEIGHT`) BY ASSERTION in the
## self-check, not by luck: a sphere that reached the floor above would call the
## lift from the landing it is meant to be a shortcut to.
const CALL_RADIUS: float = 3.5

# ============================================================================
# THE CARD
# ============================================================================

const CARD_PADDING: int = 18
const TITLE_FONT_SIZE: int = 22
## THE PAD HINT's geometry — `HUD/CaptureHint`'s box (main.tscn: 400 wide, 32 high,
## 48 px off the bottom) lifted ONE ROW so the two can be on screen together. Its
## 22 is `capture_hint.gd`'s own size, and the row is transparent lettering with no
## frame, so German has nothing to overflow and `locale_selfcheck` needs no budget.
const HINT_PAD_FONT_SIZE: int = 22
const HINT_PAD_HALF_WIDTH: float = 200.0
const HINT_PAD_HEIGHT: float = 32.0
const HINT_PAD_BOTTOM: float = 80.0
const LINE_FONT_SIZE: int = 18
const HINT_FONT_SIZE: int = 14
## The card's chrome, off `HudTheme` (bead `godot-test1-y1o.33`): a BONE heading
## over a STEEL rule, BONE stops, and the corporation's own khaki for the fine
## print AND for "no floors unlocked yet" — the palette's `UNIT_KHAKI` is
## literally its "neutral / disabled" value, which is what an empty offer is.
const COLOR_TITLE: Color = HudTheme.BONE
const COLOR_TEXT: Color = HudTheme.BONE
const COLOR_HINT: Color = HudTheme.UNIT_KHAKI
## The 1 px STEEL rule under the heading — `city_map_panel`'s, and neither is a
## `HudTheme` builder yet; a third caller is the moment to lift it in.
const RULE_PX: float = 1.0

## The corporate stamp: GastroDefense's crossed fork and knife, small and khaki
## in the bottom-right of a card the CORPORATION is speaking on — and this lift
## is theirs. Drawn rather than a texture, because the HUD ships no image assets.
const STAMP_SIZE: float = 18.0
const STAMP_LINE: float = 1.5

## The composed lines. RULE 2: `tr()` runs on these, never on the result — except
## `STOP_LINE`, which is a frame of punctuation with no words in it and so has no
## CSV row to have (`locale_selfcheck` fails a row whose German equals its
## English, which is what a translated bracket would be).
## "Floor %d" is `minimap_hud`'s storey caption — one CSV row, both surfaces.
const STOP_LINE: String = "[%d]  %s"
const FLOOR_LINE: String = "Floor %d"
const CLOSE_HINT: String = "Press %s or Esc to close"
const EMPTY_LINE: String = "No floors unlocked yet."
## THE PAD HINT (owner ruling 2, bead `godot-test1-b9m8`): what tells a player
## standing on a landing that the pad under them does anything at all. RULE 2 —
## `tr()` on the format, the key is written here.
const HINT_LINE: String = "%s — lift"

var _open: bool = false
var _paused_by_us: bool = false
## The floors the rows currently offer, in row order. The panel's whole state, and
## what the self-check reads back instead of scraping labels.
var _offered: Array[int] = []

var _card: PanelContainer = null
var _rows: VBoxContainer = null
var _hint_label: Label = null
## The pad hint, drawn on the world rather than on the card — see `_build_hint()`.
var _hint: Label = null


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available HUD
	# piece (`city_map_panel`, `skill_tree_ui`, `mp_ui`).
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("tower_lift_menu")
	_build_ui()
	_hint.text = tr(HINT_LINE) % OS.get_keycode_string(TOGGLE_KEY)


func _process(_delta: float) -> void:
	# One rule, re-asserted every frame: a panel that may no longer be open is
	# closed. That covers joining a room with the menu up, dying with it up, and
	# walking away from the call point — and it is why `_apply_pause` never has to
	# reason about a state that changed underneath it (`mp_ui`'s concern).
	#
	# ...and the pad hint is the SAME predicate, which is the whole of its policy:
	# every refusal `can_open()` already answers — in a room, over game over,
	# mid-bite, off the pad — hides the hint for free, and it cannot ever promise a
	# key that would do nothing.
	var may := can_open()
	if _open and not may:
		set_open(false)
	_hint.visible = may and not _open


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
	Is the local player standing on a lift landing, in a session that may stop the
	world?

	Every refusal the header lists, in one predicate, so `_process`'s re-assert, the
	pad hint and the keypress all ask the same question. Null-safe throughout: a
	scene with no tower and no player answers false rather than erroring (the
	standalone degrade every group lookup in this project owes).
	"""
	if _in_room() or _game_over() or _caught():
		return false
	return _call_floor() >= 0


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

	`_visited_floors()` MINUS THE ONE YOU ARE ON, and that subtraction is the whole
	rule: the ground is always offered (you can always go home) and a landing you
	have never stood on never is (owner ruling 3 — the lift may not skip you past
	content you have not walked once).
	"""
	var here := _call_floor()
	var out: Array[int] = []
	for floor_index: int in _visited_floors():
		if floor_index != here:
			out.append(floor_index)
	out.sort()
	return out


func _visited_floors() -> Array[int]:
	"""
	Every storey this world may ride to at all: the ground, plus each landing
	somebody has stood on.

	@return: a fresh Array of `FLOOR_Y` indices, unsorted and not yet filtered by
	        where you are standing.

	Three rows of arithmetic and no table: a stop is an entry a mutation grants
	(`TowerGraph.lift_stops()`), it is VISITED when its `unlock` id is in the
	shell's monotone opened set, and it lands on the storey whose plan claims its
	room as the landing. A stop whose room no storey draws — a wave-C reservation —
	simply resolves to -1 and is skipped, `minimap_hud._gather_tower`'s degrade.

	The GROUND is not a stop row and never was: nothing has to grant the front
	door, so nothing can have failed to. It is in the list unconditionally, which
	is what makes the ride down always available.
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
	out.append(0)
	for row: Dictionary in TowerGraph.lift_stops():
		var unlock := String(row.get("unlock", ""))
		if unlock == "" or not bool(shell.call("is_opened", unlock)):
			continue
		var floor_index := TowerInterior.landing_floor(String(row.get("room", "")))
		if floor_index < 0 or out.has(floor_index):
			continue
		out.append(floor_index)
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
	"""
	The storey the lift is being called FROM, or -1 when the player is not on a
	landing this lift serves.

	@return: a `FLOOR_Y` index, or -1 — which is also the whole of `can_open()`'s
	        placement test and the pad hint's.

	GATED ON REACHABILITY, NOT ON EARNING. Every landing you can stand on is a
	landing you walked to, so a call button that refused there would be refusing
	the player a trip they have already paid for. Earning decides where the lift
	will GO (`_visited_floors`), never whether it answers.

	ONE `lift_stand()` CALL, deliberately: `current_floor()` already says which
	storey the body is on, so the 40 x 40 plan scan runs once instead of ten times —
	and `TowerInterior` memoises it besides, because this runs every frame for the
	hint (see there).
	"""
	var tree := get_tree()
	if tree == null:
		return -1
	var interior: Node = tree.get_first_node_in_group(INTERIOR_GROUP)
	var player: Node = tree.get_first_node_in_group(PLAYER_GROUP)
	if interior == null or player == null:
		return -1
	if not (interior is Node3D) or not (player is Node3D):
		return -1
	var local: Vector3 = (player as Node3D).global_position \
			- (interior as Node3D).global_position
	var here := TowerInterior.current_floor(local.y)
	if here != 0 and not TowerInterior.lift_stop_floors().has(here):
		return -1
	if local.distance_to(TowerInterior.lift_stand(here)) > CALL_RADIUS:
		return -1
	return here


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
		_rows.add_child(_stop_strip(STOP_LINE % [i + 1, floor_name]))
	if _hint_label != null:
		_hint_label.text = tr(CLOSE_HINT) % OS.get_keycode_string(TOGGLE_KEY)
	# The pad hint is re-composed here too, so a locale changed mid-run reaches it
	# on the next open rather than on the next process restart.
	_hint.text = tr(HINT_LINE) % OS.get_keycode_string(TOGGLE_KEY)


func _line(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _stop_strip(text: String) -> PanelContainer:
	"""
	ONE STOP, as the spec's raised strip: `HudTheme.strip()` (INK_RAISED, a STEEL
	frame, no shadow — it is already on a card) carrying the line in Oswald BOLD,
	so the bracketed digit you actually press reads as the chip it is.

	The line stays ONE label and `STOP_LINE` stays one format string. Splitting
	the digit into its own chip Label buys a little typography and costs the one
	string in this panel that is deliberately not translated (see `STOP_LINE`) —
	`locale_selfcheck` reasons about that row's absence, so it is not a shape to
	change for a border.
	"""
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", HudTheme.strip())
	var label := _line(text, LINE_FONT_SIZE, COLOR_TEXT)
	label.add_theme_font_override("font", HudTheme.heading_font())
	strip.add_child(label)
	return strip


func _rule() -> ColorRect:
	"""The 1 px STEEL rule the spec puts under a section heading."""
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = HudTheme.STEEL
	rule.custom_minimum_size = Vector2(0.0, RULE_PX)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _stamp() -> Control:
	"""
	The corporate cutlery stamp, bottom-right. A knife (one stroke with a spine)
	crossed with a fork (one stroke with three tines) in `UNIT_KHAKI` — flat,
	single-colour, no gradient, which is the spec's whole icon language.
	"""
	var stamp := Control.new()
	stamp.name = "Stamp"
	stamp.custom_minimum_size = Vector2(STAMP_SIZE, STAMP_SIZE)
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_END
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.draw.connect(_paint_stamp.bind(stamp))
	return stamp


func _paint_stamp(stamp: Control) -> void:
	var s: float = STAMP_SIZE
	# The two handles, crossed.
	stamp.draw_line(Vector2(s * 0.15, s * 0.9), Vector2(s * 0.85, s * 0.1),
			COLOR_HINT, STAMP_LINE)
	stamp.draw_line(Vector2(s * 0.85, s * 0.9), Vector2(s * 0.15, s * 0.1),
			COLOR_HINT, STAMP_LINE)
	# Three tines on the fork's head (top left) and a blade on the knife's.
	for k in range(3):
		var x: float = s * (0.06 + 0.09 * k)
		stamp.draw_line(Vector2(x, s * 0.04), Vector2(x + s * 0.1, s * 0.28),
				COLOR_HINT, STAMP_LINE)
	stamp.draw_line(Vector2(s * 0.72, s * 0.06), Vector2(s * 0.94, s * 0.06),
			COLOR_HINT, STAMP_LINE)


func _build_ui() -> void:
	# THE HUD SKIN, on THIS ROOT and nowhere else (bead `godot-test1-y1o.33`) —
	# the card's INK ground, its STEEL frame and its hard shadow arrive with it.
	theme = HudTheme.theme()

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
	title.add_theme_font_override("font", HudTheme.heading_font())
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	column.add_child(title)
	# BONE caps over a STEEL rule. The caps are the CSV row's own ("SERVICE LIFT"
	# / "LASTENAUFZUG"), never a `.to_upper()`: a `Label.text` IS the key.
	column.add_child(_rule())

	_rows = VBoxContainer.new()
	_rows.name = "Stops"
	_rows.add_theme_constant_override("separation", HudTheme.GRID / 2)
	column.add_child(_rows)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	column.add_child(_hint_label)

	column.add_child(_stamp())

	_hint = _build_hint()
	add_child(_hint)


func _build_hint() -> Label:
	"""
	THE PAD HINT: "L — lift", bottom-centre, while you stand on a landing.

	A CHILD OF THIS PANEL and not a `main.tscn` node, because its whole visibility
	rule is `can_open()` — the predicate that lives here. A scene node would need a
	script of its own whose only job was to ask this one a question.

	LETTERING ON THE WORLD, so it takes `capture_hint.gd`'s skin exactly (which is
	`world_caption`'s): the heading face, BONE on an INK outline at double the world
	stroke, and the hard panel-offset shadow — every value off `HudTheme`, none of
	them typed here (`hero_hud_selfcheck` greps for exactly that).

	ONE ROW ABOVE `HUD/CaptureHint`'s slot (main.tscn, offsets -80..-48), which is
	the other thing that can be on screen at the same time: a browser that has not
	captured the mouse yet still says "Click to look around" underneath this.
	"""
	var hint := Label.new()
	hint.name = "PadHint"
	hint.visible = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = -HINT_PAD_HALF_WIDTH
	hint.offset_right = HINT_PAD_HALF_WIDTH
	hint.offset_top = -HINT_PAD_BOTTOM - HINT_PAD_HEIGHT
	hint.offset_bottom = -HINT_PAD_BOTTOM
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", HudTheme.heading_font())
	hint.add_theme_font_size_override("font_size", HINT_PAD_FONT_SIZE)
	hint.add_theme_color_override("font_color", HudTheme.BONE)
	hint.add_theme_color_override("font_outline_color", HudTheme.INK)
	hint.add_theme_constant_override("outline_size", HudTheme.OUTLINE_PX * 2)
	hint.add_theme_color_override("font_shadow_color",
		Color(HudTheme.INK, HudTheme.SHADOW_ALPHA))
	hint.add_theme_constant_override("shadow_offset_x", HudTheme.SHADOW_PANEL_OFFSET.x)
	hint.add_theme_constant_override("shadow_offset_y", HudTheme.SHADOW_PANEL_OFFSET.y)
	return hint
