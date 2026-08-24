extends Control
## ============================================================================
## MULTIPLAYER UI — host / join a room by invite code
## ============================================================================
## The player-facing face of `mp_manager.gd`. A small "MP" button parked in the
## bottom-left corner opens a panel that can:
##
##   * **Host** a room (the lobby mints a fresh 6-character invite code),
##   * **Join** one by typing a friend's code,
##   * show the room's code large with a **Copy** button so it can be pasted
##     into a chat, plus who is currently in the room,
##   * **Leave**, returning to solo play.
##
## Everything is built in code in `_ready()` — the same convention as
## `touch_controls.gd`, `mobile_settings_panel.gd` and `pause_controller.gd`,
## so `main.tscn` needs nothing but a bare `Control` node carrying this script.
##
## ----------------------------------------------------------------------------
## No hard references — found by group, like the rest of the HUD
## ----------------------------------------------------------------------------
## This panel never holds a scene path or an exported reference to the manager.
## It locates it through the `"mp"` group with `get_first_node_in_group(...)`
## and talks only to its public API (`host()`, `join()`, `leave()`,
## `get_room_code()`, `get_members()`, `is_online()`), every call behind a
## `has_method` guard. So a scene run WITHOUT the Multiplayer node (say
## `scenes/characters/primm.tscn` standalone) shows an inert button instead of
## erroring. Live updates arrive on the manager's `room_changed` / `status`
## signals, connected once when the manager is first found.
##
## ----------------------------------------------------------------------------
## Visible on EVERY platform — deliberately not touch-gated
## ----------------------------------------------------------------------------
## `touch_controls.gd` and `mobile_settings_panel.gd` hide themselves on desktop
## (they exist only to replace a keyboard). This one does the opposite: hosting
## and joining is a desktop feature too, and there is no keyboard shortcut for
## it, so the button is the ONLY way in. It is still sized for a thumb
## (`TOUCH_MIN_HEIGHT`), and the code `LineEdit` raises the on-screen keyboard
## on a phone for free.
##
## ----------------------------------------------------------------------------
## The tree is NOT paused while the panel is open
## ----------------------------------------------------------------------------
## Deliberate: the world keeps running behind the panel, because the mesh, the
## lobby socket and the presence stream all live on `_process` — pausing would
## stall the very connection the player is waiting on. What the panel DOES do is
## release a captured mouse so the buttons are clickable, and recapture it on
## close. That flag (`_recapture_mouse`) is copied from `pause_controller.gd`
## for the same reason it exists there: we must only ever recapture a mouse WE
## released, or this panel would silently steal the cursor back from the pause
## overlay or from a touch session that never captured it in the first place.

# ============================================================================
# CONSTANTS — layout
# ============================================================================

## The always-visible "MP" toggle button. Bottom-LEFT is the corner the plan
## picked because the rest of the HUD is spoken for: lives hearts + perf overlay
## own the top-left column, coins + the ability dial the top-right, the view /
## steer toggles the top-centre, and the Jump/Special/Switch cluster the
## bottom-right. `mobile_settings_panel.gd`'s ⚙ Tune gear also lives
## bottom-left, so this button is stacked ABOVE it (see `_build_ui`) rather
## than on top of it — the gear is touch-only, this one is everywhere.
const MP_BUTTON_WIDTH: float = 110.0
const MP_BUTTON_HEIGHT: float = 56.0

## Margin (px) from the screen edge, matching the settings panel's spacing.
const EDGE_MARGIN: float = 16.0

## Height of the ⚙ Tune gear this button stacks above, plus the gap between
## them. Mirrors `mobile_settings_panel.GEAR_HEIGHT` — duplicated rather than
## reached for across scripts, because a hard reference to that panel is exactly
## what the group-discovery convention exists to avoid, and a stale value here
## costs a few pixels of gap, not a bug.
const TUNE_GEAR_HEIGHT: float = 60.0
const BUTTON_STACK_GAP: float = 8.0

## The open panel's size. Tall enough for the status line, the host/join
## controls, the code + member list and Leave; scrollable so a short phone
## screen can still reach the bottom row.
const PANEL_WIDTH: float = 360.0
const PANEL_HEIGHT: float = 420.0

## Minimum height for every interactive row (button, LineEdit). Past the ~44-48
## pt minimum touch target so the panel is thumb-usable on a phone.
const TOUCH_MIN_HEIGHT: float = 48.0

## Invite codes are exactly 6 characters (`server/room.go`'s `CodeLength`), from
## an alphabet with no `0/O/1/I/L`. Clamping the LineEdit means an over-long
## typo is rejected before the lobby ever has to see it.
const CODE_LENGTH: int = 6

## Font sizes: the room code is shown large because it is the thing a player
## reads aloud or copies to a friend.
const CODE_FONT_SIZE: int = 34
const BODY_FONT_SIZE: int = 18

# ============================================================================
# STATE
# ============================================================================

## Cached manager, re-fetched through the `"mp"` group if it was never found or
## has since been freed (mirrors `touch_controls._ensure_driver()`). Null on a
## build with no Multiplayer node — every caller guards.
var _manager: Node = null

## True once we have connected to the manager's signals, so `_ensure_manager()`
## can be called freely without stacking duplicate connections.
var _signals_connected: bool = false

## True while the panel body is open. Starts closed: only the MP button shows.
var _panel_open: bool = false

## Whether we released a captured mouse when opening, and so should recapture it
## on close. See the header — never recapture a mouse we did not release.
var _recapture_mouse: bool = false

## True only while the CURRENT tree pause was started by us, so closing the panel
## can never cancel somebody else's pause (`pause_controller.gd`'s P key, or
## `mobile_input.gd`'s focus-loss pause). Same guard those two use on each other.
var _paused_by_us: bool = false

# --- Child node references (built in _ready, not from a .tscn) --------------

var _mp_button: Button = null
var _panel_body: PanelContainer = null

## One-line status, fed by the manager's `status` signal ("Connecting…",
## "In room ABCDEF (2/4)", any lobby error). The single place a failure surfaces.
var _status_label: Label = null

## The room code, shown large once in a room; hidden with its Copy button while
## offline.
var _code_label: Label = null
var _code_row: HBoxContainer = null

## Where a friend's invite code is typed, plus the Join button beside it.
var _code_input: LineEdit = null

## Who is in the room, one line each. Empty while offline.
var _members_label: Label = null

## Host / Join are only useful offline, Leave only in a room — `_refresh()`
## flips them so the panel never offers a meaningless action.
var _host_button: Button = null
var _join_button: Button = null
var _leave_button: Button = null


func _ready() -> void:
	# Keep working while the tree is paused, for the same reason
	# `mobile_settings_panel.gd` does: this Control sits above the touch UI in
	# the HUD, and its Button / PanelContainer children carry the default
	# MOUSE_FILTER_STOP. A PAUSABLE control receives no GUI input yet still
	# blocks the PROCESS_MODE_ALWAYS one beneath it, so a pause would leave taps
	# landing here dead instead of falling through.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The root spans the screen but must NOT be a hit-test target itself, or it
	# would swallow gameplay clicks (and the touch UI's overlays) everywhere the
	# panel is not. IGNORE makes the empty area transparent to input; the button
	# and the open panel body keep their own STOP filter and still get their taps.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_ui()
	_ensure_manager()
	_refresh()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

## Build the MP button and the collapsible panel, and wire every signal. Called
## once from `_ready()`; anchored so it repositions on any screen size.
func _build_ui() -> void:
	# --- "MP" toggle, BOTTOM-LEFT above the ⚙ Tune gear -------------------
	_mp_button = Button.new()
	_mp_button.name = "MPButton"
	_mp_button.text = "MP"
	_mp_button.add_theme_font_size_override("font_size", 24)
	_mp_button.custom_minimum_size = Vector2(MP_BUTTON_WIDTH, MP_BUTTON_HEIGHT)
	_mp_button.anchor_left = 0.0
	_mp_button.anchor_right = 0.0
	_mp_button.anchor_top = 1.0
	_mp_button.anchor_bottom = 1.0
	_mp_button.offset_left = EDGE_MARGIN
	_mp_button.offset_right = EDGE_MARGIN + MP_BUTTON_WIDTH
	# Offsets are measured from the BOTTOM edge (anchor 1), so they are negative.
	# Sit one gear-height + gap up, leaving the corner itself to the Tune gear.
	_mp_button.offset_bottom = -EDGE_MARGIN - TUNE_GEAR_HEIGHT - BUTTON_STACK_GAP
	_mp_button.offset_top = _mp_button.offset_bottom - MP_BUTTON_HEIGHT
	_mp_button.pressed.connect(_on_mp_button_pressed)
	add_child(_mp_button)

	# --- Panel body, opening UPWARD from just above the button ------------
	_panel_body = PanelContainer.new()
	_panel_body.name = "MPPanel"
	_panel_body.anchor_left = 0.0
	_panel_body.anchor_right = 0.0
	_panel_body.anchor_top = 1.0
	_panel_body.anchor_bottom = 1.0
	_panel_body.offset_left = EDGE_MARGIN
	_panel_body.offset_right = EDGE_MARGIN + PANEL_WIDTH
	_panel_body.offset_bottom = _mp_button.offset_top - BUTTON_STACK_GAP
	_panel_body.offset_top = _panel_body.offset_bottom - PANEL_HEIGHT
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	_panel_body.add_theme_stylebox_override("panel", panel_style)
	_panel_body.visible = false
	add_child(_panel_body)

	# Scroll + vertical stack inside, so a short screen reaches every row.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "Body"
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0.0)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "MULTIPLAYER"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# --- Status line ------------------------------------------------------
	# Every manager failure path emits a `status` string; this is where they land.
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "Offline"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_status_label)

	# --- Host -------------------------------------------------------------
	_host_button = _make_button("Host a room", _on_host_pressed)
	vbox.add_child(_host_button)

	# --- Join by code -----------------------------------------------------
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	join_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(join_row)

	_code_input = LineEdit.new()
	_code_input.name = "CodeInput"
	_code_input.placeholder_text = "CODE"
	# Six characters is the whole alphabet of a valid code (`server/room.go`), so
	# a longer typo can never even be entered, let alone sent.
	_code_input.max_length = CODE_LENGTH
	_code_input.custom_minimum_size = Vector2(0.0, TOUCH_MIN_HEIGHT)
	_code_input.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Upper-case as it is typed: the lobby upper-cases anyway, but showing the
	# player the code in the form they were given avoids a "did I mistype it?"
	# moment. Re-setting `text` moves the caret, so restore it.
	_code_input.text_changed.connect(_on_code_text_changed)
	# Enter in the field is the same as pressing Join — the obvious expectation,
	# and on a phone it is the on-screen keyboard's "go" key.
	_code_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	join_row.add_child(_code_input)

	_join_button = _make_button("Join", _on_join_pressed)
	_join_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	join_row.add_child(_join_button)

	# --- Current room code + Copy (shown only while in a room) ------------
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 8)
	_code_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.visible = false
	vbox.add_child(_code_row)

	_code_label = Label.new()
	_code_label.name = "RoomCode"
	_code_label.text = ""
	_code_label.add_theme_font_size_override("font_size", CODE_FONT_SIZE)
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_label)

	var copy_button := _make_button("Copy", _on_copy_pressed)
	copy_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_code_row.add_child(copy_button)

	# --- Member list ------------------------------------------------------
	_members_label = Label.new()
	_members_label.name = "Members"
	_members_label.text = ""
	_members_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_members_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_members_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_members_label)

	# --- Leave + Close ----------------------------------------------------
	_leave_button = _make_button("Leave room", _on_leave_pressed)
	vbox.add_child(_leave_button)

	vbox.add_child(_make_button("Close", _on_mp_button_pressed))


## Make one full-width, thumb-sized button wired to `handler`. Every button in
## the panel goes through here so the touch-target minimum can't be forgotten.
func _make_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	button.custom_minimum_size = Vector2(0.0, TOUCH_MIN_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return button


# ============================================================================
# MANAGER DISCOVERY (group only — no hard references)
# ============================================================================

## Return the multiplayer manager from the `"mp"` group, caching it and
## connecting its signals the first time it is found. Null when the scene has no
## Multiplayer node, in which case every handler below degrades to a status line.
func _ensure_manager() -> Node:
	if _manager != null and is_instance_valid(_manager):
		return _manager
	_manager = get_tree().get_first_node_in_group("mp")
	if _manager != null and not _signals_connected:
		# `has_signal` guards keep this safe against a stand-in node that merely
		# happens to be in the group.
		if _manager.has_signal("room_changed"):
			_manager.room_changed.connect(_on_room_changed)
		if _manager.has_signal("status"):
			_manager.status.connect(_on_status)
		_signals_connected = true
	return _manager


# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_mp_button_pressed() -> void:
	_set_panel_open(not _panel_open)


func _on_host_pressed() -> void:
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("host"):
		_on_status("Multiplayer is not available in this scene")
		return
	manager.host()


func _on_join_pressed() -> void:
	# Validate the typed code FIRST, before looking for the manager: it is purely
	# local input validation, and telling a player "that code is too short" is
	# more useful than a generic availability message when both are true.
	# Rejecting here also spares the lobby a socket it would close with an error
	# frame a round-trip later.
	var code: String = _code_input.text.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		_on_status("An invite code is %d characters" % CODE_LENGTH)
		return
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("join"):
		_on_status("Multiplayer is not available in this scene")
		return
	manager.join(code)


func _on_leave_pressed() -> void:
	var manager := _ensure_manager()
	if manager != null and manager.has_method("leave"):
		manager.leave()
	# `leave()` emits `room_changed("", [])`, which refreshes the panel; refresh
	# anyway so a manager-less scene still resets its own display.
	_refresh()


func _on_copy_pressed() -> void:
	var code: String = _current_code()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_on_status("Copied %s to the clipboard" % code)


## Keep the typed code upper-case without eating the caret position. Godot moves
## the caret to 0 when `text` is assigned, so it is restored by hand.
func _on_code_text_changed(new_text: String) -> void:
	var upper: String = new_text.to_upper()
	if upper == new_text:
		return
	var caret: int = _code_input.caret_column
	_code_input.text = upper
	_code_input.caret_column = caret


# ============================================================================
# MANAGER SIGNALS
# ============================================================================

func _on_room_changed(_code: String, _members: Array) -> void:
	_refresh()


func _on_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


# ============================================================================
# PANEL STATE
# ============================================================================

## Open or close the panel body, handling the tree pause and the mouse handover.
##
## THE PANEL PAUSES THE GAME, and that is not decoration — `player_controller`
## reads gameplay through the GLOBAL polled `Input` state and through `_input()`,
## neither of which a focused `Control` suppresses. Left running:
##
##   * every click INSIDE the panel re-triggers the desktop-web click-to-capture
##     in `player_controller._input()`, which warps the cursor to screen centre —
##     so after the first click Join / Copy / Leave / Close are all unreachable
##     and the camera swings behind the open panel; and
##   * typing an invite code drives the player, because the lobby's code alphabet
##     (`23456789ABCDEFGHJKMNPQRSTUVWXYZ`) contains W, A, S, D, E, F, C and R —
##     the player walks, turns, switches character, fires its ability and flips
##     to first person while crocodiles keep hunting.
##
## Pausing is the one-line fix for both, because `process_mode` gates `_input`
## and `_physics_process` together. `MpManager` sets itself PROCESS_MODE_ALWAYS,
## so the socket and the mesh keep being polled while the panel is up.
func _set_panel_open(open: bool) -> void:
	_panel_open = open
	if _panel_body != null:
		_panel_body.visible = open

	var tree := get_tree()
	if open and not tree.paused:
		tree.paused = true
		_paused_by_us = true
	elif not open and _paused_by_us:
		_paused_by_us = false
		tree.paused = false

	if open:
		# Clamp the panel to the space actually above the button — a phone's
		# scaled viewport can be shorter than the full stack, and a
		# PanelContainer poking past the screen top is unreachable even through
		# its own ScrollContainer (which scrolls its CONTENT, not its frame).
		var view_height: float = get_viewport().get_visible_rect().size.y
		_panel_body.offset_top = maxf(_panel_body.offset_bottom - PANEL_HEIGHT, -view_height + EDGE_MARGIN)
		# Free a captured mouse so the buttons can be clicked. Only remember the
		# handover when WE did it — see the header comment.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			_recapture_mouse = true
		_refresh()
	elif _recapture_mouse:
		# Closing is a user gesture, which is exactly what browser pointer-lock
		# needs, so this works on desktop web too.
		_recapture_mouse = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Re-render everything that depends on the manager's state: which actions are
## offered, the room code, and who is in the room.
func _refresh() -> void:
	var manager := _ensure_manager()
	var online: bool = manager != null and manager.has_method("is_online") and bool(manager.is_online())
	var code: String = _current_code()

	# Host/Join make sense only offline; Leave only in a room. Disabled rather
	# than hidden so the panel does not jump about as the state changes.
	if _host_button != null:
		_host_button.disabled = online
	if _join_button != null:
		_join_button.disabled = online
	if _code_input != null:
		_code_input.editable = not online
	if _leave_button != null:
		_leave_button.disabled = not online

	if _code_row != null:
		_code_row.visible = not code.is_empty()
	if _code_label != null:
		_code_label.text = code

	if _members_label != null:
		_members_label.text = _member_lines(manager)


## The current room code, or "" when there is no room (or no manager).
func _current_code() -> String:
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("get_room_code"):
		return ""
	return String(manager.get_room_code())


## Render the lobby's `[{"id": ..., "name": ...}, ...]` member list as one name
## per line. The lobby is a trust boundary, so a member entry that is not a
## dictionary with a name is skipped rather than crashing the HUD.
func _member_lines(manager: Node) -> String:
	if manager == null or not manager.has_method("get_members"):
		return ""
	var lines: PackedStringArray = PackedStringArray()
	for member: Variant in manager.get_members():
		if member is Dictionary and member.has("name"):
			lines.append("• %s" % String(member["name"]))
	if lines.is_empty():
		return ""
	return "In room:\n" + "\n".join(lines)
