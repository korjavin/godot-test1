extends Control
## ============================================================================
## MULTIPLAYER UI — host / join a room by invite code
## ============================================================================
## The player-facing face of `mp_manager.gd`. A small "MP" button parked in the
## bottom-left corner opens a panel that can:
##
##   * show the **list of open rooms** the lobby is currently hosting, one
##     tappable row each, and join one in a single press — this LEADS the panel
##     because the owner's verdict on the invite-code-only flow was "copy code
##     not convenient, show a list of opened lobbies",
##   * **Host** a room (the lobby mints a fresh 6-character invite code),
##   * **Join** one by typing a friend's code — kept as the fallback for reaching
##     one *specific* person's room, not the way in,
##   * show the room's code large with a **Copy** button so it can be pasted
##     into a chat, plus who is currently in the room,
##   * **pick a hero** from the lobby's pool — one button per hero, the ones
##     other players hold disabled and named with their holder,
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
## `get_room_code()`, `get_members()`, `is_online()`, `my_hero()`,
## `claim_hero()`), every call behind a `has_method` guard. So a scene run
## WITHOUT the Multiplayer node (say `scenes/characters/primm.tscn` standalone)
## shows an inert button instead of erroring. Live updates arrive on the
## manager's `room_changed` / `status` / `heroes_changed` signals, connected
## once when the manager is first found.
##
## ----------------------------------------------------------------------------
## The MP button IS the room indicator
## ----------------------------------------------------------------------------
## While in a room the toggle relabels itself to the code and the head count
## ("ABC234  2/4") instead of "MP". That is the persistent "you are online"
## indicator the plan asks for, at the cost of no extra node and no extra draw:
## the one control that is always on screen already, saying the one thing a
## player in a room needs to see without opening anything.
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
## It is drawn in the HUD SKIN, and that is one line on the root
## ----------------------------------------------------------------------------
## Bead `godot-test1-y1o.29`: `theme = HudTheme.theme()` in `_build_ui()` is where
## every colour, face and StyleBox in this file comes from — the panel owns no hex
## of its own any more. What the theme does NOT reach is the handful of classes it
## has no slot for (`LineEdit`, `Slider`, the scroll bar) and the three things this
## panel decides for itself: the caps SECTION HEADINGS (`_heading_label()`), the
## per-hero chip TINTS, and the speaking DOT — see `DOT_SPEAKING`, which is green
## on purpose and against the bead's letter.
##
## ----------------------------------------------------------------------------
## The tree IS paused while the panel is open
## ----------------------------------------------------------------------------
## See `_set_panel_open()` for why (clicks re-capturing the mouse, and an invite
## code whose alphabet contains W A S D E F C R driving the player). Nothing is
## lost by it: `MpManager` is PROCESS_MODE_ALWAYS, so the mesh, the lobby socket
## and the presence stream keep ticking underneath — pausing must never stall the
## very connection the player is waiting on. The panel also releases a captured
## mouse so the buttons are clickable, and recaptures it on close. That flag
## (`_recapture_mouse`) is copied from `pause_controller.gd` for the same reason
## it exists there: we must only ever recapture a mouse WE released, or this
## panel would silently steal the cursor back from the pause overlay or from a
## touch session that never captured it in the first place.

# ============================================================================
# CONSTANTS — layout
# ============================================================================

## The always-visible "MP" toggle button. Bottom-LEFT is the corner the plan
## picked because the rest of the HUD is spoken for: the hero portrait row + perf
## overlay own the top-left column, coins + the ability dial the top-right, the view /
## steer toggles the top-centre, and the Jump/Special/Switch cluster the
## bottom-right. `mobile_settings_panel.gd`'s ⚙ Tune gear also lives
## bottom-left, so this button is stacked ABOVE it (see `_build_ui`) rather
## than on top of it — the gear is touch-only, this one is everywhere.
const MP_BUTTON_WIDTH: float = 110.0
const MP_BUTTON_HEIGHT: float = 56.0

## The same button, widened for its in-room label ("ABC234  2/4"). Six code
## characters plus the head count do not fit the 110 px "MP" width, and a button
## that clips its own room code is not an indicator.
const MP_BUTTON_WIDTH_ONLINE: float = 190.0
const MP_BUTTON_FONT_SIZE: int = 24
const MP_BUTTON_FONT_SIZE_ONLINE: int = 19

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
## controls, the hero row, the code + member list and Leave; scrollable so a
## short phone screen can still reach the bottom row. Grown from 420 by one
## `TOUCH_MIN_HEIGHT` button plus the VBox separation and the row's own label,
## which is what the hero picker added.
##
## 376 AND NOT 360 SINCE THE HUD SKIN (bead godot-test1-y1o.29), and the sixteen
## pixels are a locale budget rather than taste. `locale_selfcheck`'s MP rows are
## every one of them written against a **320 px usable width**, and the skin spends
## into that from both sides: `HudTheme.card()` pads the panel by `CARD_PADDING`
## (12) a side where this panel used to pad by 10, and `HudTheme.button()` pads a
## button face by another 12 a side where the engine default theme padded by 4. At
## 360 a full-width button would have had 304, which is a budget measured 16 px
## wider than the control it measures. The arithmetic that has to hold is
##
##   PANEL_WIDTH - 2*CARD_PADDING - SCROLLBAR_WIDTH - 2*CARD_PADDING == 320
##
## and it is what `vbox.custom_minimum_size` below is derived from too. Keeping the
## budgets true this way is what keeps this bead's diff to the one script it owns.
const PANEL_WIDTH: float = 376.0
const PANEL_HEIGHT: float = 620.0

## The scroll bar's own width, on the spec's 8 px grid and the same 8 px the engine
## default theme gives it. Declared rather than assumed because the body's width —
## and therefore every budget above — is the panel less the card padding less THIS
## (codex review 2026-09-05: the first draft's styleboxes carried no margins, so
## the bar computed a width of 0, which both hid the thumb and made the 320 px come
## out right by accident).
const SCROLLBAR_WIDTH: float = 8.0

## Minimum height for every interactive row (button, LineEdit). Past the ~44-48
## pt minimum touch target so the panel is thumb-usable on a phone.
const TOUCH_MIN_HEIGHT: float = 48.0

## Invite codes are exactly 6 characters (`server/room.go`'s `CodeLength`), from
## an alphabet with no `0/O/1/I/L`. Clamping the LineEdit means an over-long
## typo is rejected before the lobby ever has to see it.
const CODE_LENGTH: int = 6

## The lobby's room cap (`server/room.go`'s `MaxMembers`). Mirrored rather than
## fetched, exactly like `TUNE_GEAR_HEIGHT` above: a stale value here costs a
## wrong "n/4" in a label, never a wrong join — the lobby refuses a fifth member
## whatever this says.
const MAX_MEMBERS: int = 4

## How many room rows to draw at most. The lobby's answer is untrusted input off
## an HTTP socket, and a busy public lobby is a legitimate reason for it to be
## long; either way a panel with two hundred buttons in it is not a list a player
## reads. Refresh is the way to see a changed set, not scrolling.
const ROOM_ROW_MAX: int = 8

## How many claimed heroes a room row names before it stops. The row is one
## clipped line inside a 360 px panel, so this is a width budget: two names plus
## the code and the head count is about what fits before the clip starts eating
## characters.
const ROOM_ROW_HERO_MAX: int = 2

## Font sizes: the room code is shown large because it is the thing a player
## reads aloud or copies to a friend.
const CODE_FONT_SIZE: int = 34
const BODY_FONT_SIZE: int = 18

## The member row (bead godot-test1-xtr.3): a speaking dot, the name, and a mute
## toggle narrow enough to leave a 32-character lobby name room to clip in.
##
## 120 AND NOT 104 SINCE THE HUD SKIN, for `PANEL_WIDTH`'s reason exactly: this is
## the one NARROW control in the panel and `locale_selfcheck` budgets "Mute" /
## "Muted" at `MUTE_BUTTON_WIDTH` less the button stylebox's horizontal padding —
## 96 px, written when that padding was the engine default's 8. `HudTheme.button()`
## pads by `CARD_PADDING` (12) a side, so 104 would leave 80 and the check would be
## measuring 16 px that are not there. The name label beside it still clips.
const DOT_WIDTH: float = 18.0
const MUTE_BUTTON_WIDTH: float = 120.0

## THE SPEAKING DOT IS GREEN AND THAT IS DELIBERATE — read the note before
## changing it (bead godot-test1-y1o.29).
##
## The bead asked for `VISOR_AMBER` here. It does not ship, because the HUD skin
## that landed BEFORE it (the pilot, bead y1o.24) ruled the other way and is the
## authority on how a panel consumes the palette: `hud_theme.gd`'s own palette note
## lists the speaking green among the colours that are SEMANTIC rather than
## stylistic and that "a palette pass may not quietly recolour", and `hero_hud.gd`
## mirrors it under "one speaking colour for the whole game, and the palette has no
## green". A talking teammate is already green on his `RemoteAvatar` name tag and
## green on his hero tile; amber HERE would be the same fact in two colours on
## three surfaces, and amber is also the colour the row next door uses for a mic
## that was DENIED. So the value is `remote_avatar.LABEL_SPEAKING_COLOR`, mirrored
## the way `hero_hud` mirrors it (both are `draw`/`modulate` consumers of a script
## that owns no `class_name`, so neither can preload it) rather than the panel's own
## slightly different green — which IS the bead's "today's dot colour moves to the
## palette", one word of it aside. **The owner's eye rules; flagged in the PR.**
const DOT_SPEAKING: Color = Color(0.55, 1.0, 0.55)
## An idle dot is inactive, and inactive is STEEL — the panel's own 25% white is
## gone with every other literal `HudTheme` owns.
const DOT_IDLE: Color = HudTheme.STEEL

## The per-hero identity tints, so a hero chip reads as that hero. `hero_hud.gd`
## owns the table (`hud_theme.gd` names it as the one home of the tints and
## deliberately keeps them out of the palette, being identity and not style); it
## carries no `class_name`, so the script object is the only way to reach it — a
## const table is exactly what CLAUDE.md allows a script dependency to be, and
## nothing is instanced here.
const HeroHud := preload("res://scripts/hero_hud.gd")

## The key `voice_chat.gd` reports the LOCAL microphone's level under. Mirrored
## rather than preloaded: `voice_chat.gd` is found through the group like every
## other system here, and a preload for one string would be this panel's only
## hard reference to it.
const VOICE_SELF_KEY: String = "me"

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

## The hero picker: one button per hero the lobby offers. `_hero_pool` is the
## pool the buttons were built for, so the row is rebuilt only when the lobby's
## offer actually changes (once per room in practice) and merely relabelled on
## every `heroes` broadcast. Hidden entirely while offline — solo play cycles
## characters with E and has no pool to pick from.
var _hero_row: VBoxContainer = null
var _hero_buttons: Array[Button] = []
var _hero_pool: Array[String] = []

## The open-room list: the section wrapper (hidden while in a room — there is
## nothing to pick once you are in one), the one-line status/empty message, the
## box the room buttons live in, and those buttons. Rebuilt wholesale on every
## answer, like `_rebuild_hero_buttons()`, because a room list is small and a
## diff of it would be more code than a rebuild.
var _rooms_section: VBoxContainer = null
var _rooms_status: Label = null
var _rooms_box: VBoxContainer = null
var _rooms_buttons: Array[Button] = []

## True while a `/rooms` fetch is in flight, so a mashed ↻ does not stack
## requests the lobby will answer with ERR_BUSY anyway.
var _rooms_pending: bool = false

## Host / Join are only useful offline, Leave only in a room — `_refresh()`
## flips them so the panel never offers a meaningless action.
var _host_button: Button = null
var _join_button: Button = null
var _leave_button: Button = null

## Voice chat controls (bead godot-test1-xtr.2, extended by .3).
var _voice_section: VBoxContainer = null
var _voice_mode_button: Button = null
var _mic_state_label: Label = null
var _mic_mute_button: Button = null
var _deafen_button: Button = null
## The incoming-volume dial and its readout (bead godot-test1-xtr.9).
var _volume_label: Label = null
var _volume_slider: HSlider = null
## The opt-in camera toggle (bead godot-test1-xtr.6).
var _camera_button: Button = null
var _voice: Node = null
var _voice_signals_connected: bool = false

## The member ROWS (bead godot-test1-xtr.3): one `{id, dot, mute}` per name under
## `_members_box`. Rebuilt wholesale — like `_rebuild_room_buttons()`, and for the
## same reason: four rows is smaller than a diff of four rows — but only when the
## SIGNATURE below actually changes, because `_refresh()` fires on every presence
## broadcast and rebuilding a button the player is mid-tap on eats the tap.
var _members_box: VBoxContainer = null
var _member_rows: Array = []
var _member_sig: String = ""

## The panel's caps SECTION HEADINGS, as `{label, source}` — see `_heading_label()`.
## They carry their own English source because `.to_upper()` at the draw site means
## the label cannot auto-translate, so a live language switch has to re-resolve them.
var _headings: Array = []



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

	# The start overlay's "Multiplayer" button opens this panel through the group,
	# the same no-hard-references rule everything else here follows.
	add_to_group("mp_ui")

	_build_ui()
	_ensure_manager()
	_ensure_voice()
	_refresh()



## Yield the screen to TouchControls' full-rect overlays — the exact three lines
## `mobile_settings_panel.gd` runs for its ⚙ gear, for the exact same reason.
## This Control draws above TouchControls (only `StartOverlay`, the boot-time
## modal, sits later in `HUD` than it does) and
## wins hit-testing: an unhidden MP button in the bottom-left corner steals taps
## from the first-run "tap to enable motion controls" overlay — and that tap is
## the ONE user gesture iOS grants `DeviceMotionEvent.requestPermission()` and
## the browser grants WebAudio, so motion AND all audio would stay dead for the
## session. The panel body is force-closed too (which also releases our pause),
## or it covers the overlay it just stole the tap from.
func _process(_delta: float) -> void:
	if _mp_button == null:
		return
	var touch_ui: Node = get_tree().get_first_node_in_group("touch_controls")
	var modal: bool = touch_ui != null and touch_ui.has_method("has_modal") and touch_ui.has_modal()

	# Yield to the ⚙ Tune panel for the same reason, one sibling further along.
	# That panel's body opens UPWARD from just above its gear — bottom offsets
	# [-664, -84], left [16, 396] — which contains this button's [-140, -84] x
	# [16, 126] entirely. MultiplayerUI draws after MobileSettingsPanel, so it wins
	# the panel and wins hit-testing: without this the panel's bottom-left corner
	# (where its Close row sits) opens the MP panel instead.
	var tune_ui: Node = get_tree().get_first_node_in_group("mobile_settings")
	if tune_ui != null and tune_ui.has_method("is_panel_open") and tune_ui.is_panel_open():
		modal = true

	_mp_button.visible = not modal
	if modal and _panel_open:
		_set_panel_open(false)

	# The pause decision is re-evaluated every frame, not just at open time —
	# see `_apply_pause()` for why (this node is PROCESS_MODE_ALWAYS, so it keeps
	# ticking under its own pause).
	_apply_pause(_panel_open)

	# The speaking dots follow speech, which `_refresh()`'s lobby events cannot;
	# only while the panel is actually open, because nothing here is visible
	# otherwise. This node is PROCESS_MODE_ALWAYS, so the dots keep moving under a
	# pause — which they must, since voice does (epic godot-test1-xtr).
	if _panel_open:
		_update_member_rows()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

## Build the MP button and the collapsible panel, and wire every signal. Called
## once from `_ready()`; anchored so it repositions on any screen size.
func _build_ui() -> void:
	# THE SKIN, AND IT IS ONE LINE ON THIS ROOT (bead godot-test1-y1o.29). Every
	# colour, face and StyleBox below comes off `HudTheme` from here on: the panel's
	# ground, every Button's four states, every Label's BONE. **On this node and
	# never on `ProjectSettings`** — a project-wide flip would restyle every
	# `Control` in the game at once and move every German width budget in one PR,
	# which is exactly what the per-panel beads exist to do one file at a time. It
	# covers the MP toggle too, which is the point: the button IS this panel.
	theme = HudTheme.theme()

	# --- "MP" toggle, BOTTOM-LEFT above the ⚙ Tune gear -------------------
	_mp_button = Button.new()
	_mp_button.name = "MPButton"
	_mp_button.text = "MP"
	_mp_button.add_theme_font_size_override("font_size", MP_BUTTON_FONT_SIZE)
	_mp_button.custom_minimum_size = Vector2(MP_BUTTON_WIDTH, MP_BUTTON_HEIGHT)
	# NEVER let a gameplay HUD button take keyboard focus. Godot's `BaseButton`
	# defaults to `FOCUS_ALL` and KEEPS the focus after a click, and a focused
	# button is activated by `ui_accept` — which is SPACE, which is also `jump`.
	# So one click on "MP" turned every later jump into another panel toggle, for
	# the rest of the session, with no way to click the focus away (this Control
	# is MOUSE_FILTER_IGNORE, so a click on the world lands on nothing focusable).
	# This button is the one that bites hardest because it never hides — the
	# panel's own buttons at least lose focus when the panel is hidden — but every
	# Button here is FOCUS_NONE for the same reason. See `_make_button`.
	_mp_button.focus_mode = Control.FOCUS_NONE
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
	# No stylebox override: the theme's `PanelContainer` slot IS `HudTheme.card()` —
	# INK at the panel alpha, square corners, a 1 px STEEL frame and the hard 2 px
	# offset shadow. The rounded translucent-blue box that used to be typed here is
	# the literal this bead deletes.
	_panel_body.visible = false
	add_child(_panel_body)

	# Scroll + vertical stack inside, so a short screen reaches every row.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body.add_child(scroll)
	# The scrollbar is a `VScrollBar` CHILD, so `theme()`'s Panel/Button/Label slots
	# never reach it and it stays the engine's light-grey pill on an INK card. INK
	# track, STEEL grabber — the palette's own "frame / inactive" pair. Reached
	# through `get_v_scroll_bar()` because that is the only handle to it.
	var track := StyleBoxFlat.new()
	track.bg_color = HudTheme.INK
	track.set_corner_radius_all(0)
	track.anti_aliasing = false
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = HudTheme.STEEL
	grabber.set_corner_radius_all(0)
	grabber.anti_aliasing = false
	var vbar := scroll.get_v_scroll_bar()
	vbar.add_theme_stylebox_override("scroll", track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		vbar.add_theme_stylebox_override(state, grabber)
	# A `ScrollBar`'s minimum cross-axis size comes from its styleboxes' MARGINS, so
	# a flat box with none makes the bar 0 px wide: the thumb vanishes and there is
	# nothing left to drag. Pin the width instead of margin-padding four boxes.
	vbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0.0)

	# A `ScrollContainer` does NOT reserve its bar's width — the bar is drawn OVER
	# the content — so without this gutter the right-hand STEEL border of every
	# button and every member strip sits under it. One `MarginContainer` is cheaper
	# than a right margin on each of the four sections, and it makes
	# `PANEL_WIDTH`'s arithmetic literally true rather than true-once-you-know.
	var gutter := MarginContainer.new()
	gutter.name = "Gutter"
	gutter.add_theme_constant_override("margin_right", int(SCROLLBAR_WIDTH))
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)

	var vbox := VBoxContainer.new()
	vbox.name = "Body"
	# The spec's 8 px grid. The minimum width is the card less its own padding (12 a
	# side) less the scroll bar's gutter, which is exactly the space the body gets —
	# a minimum any wider than that is clipped by the ScrollContainer, since
	# horizontal scrolling is disabled. See `PANEL_WIDTH`'s arithmetic.
	vbox.add_theme_constant_override("separation", HudTheme.GRID)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(
		PANEL_WIDTH - HudTheme.CARD_PADDING * 2.0 - SCROLLBAR_WIDTH, 0.0)
	gutter.add_child(vbox)

	_add_heading(vbox, "MULTIPLAYER")

	# --- Status line ------------------------------------------------------
	# Every manager failure path emits a `status` string; this is where they land.
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.text = "Offline"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_status_label)

	# --- Open rooms: the LEADING way in -----------------------------------
	# Every open room on the lobby is public and appears here (`GET /rooms`) —
	# there is no opt-in and no way to hide a room. One press on a row joins it,
	# which is the whole reason this exists: the owner's playtest verdict on the
	# code-only flow was that copying a code around is not convenient.
	_rooms_section = VBoxContainer.new()
	_rooms_section.name = "Rooms"
	_rooms_section.add_theme_constant_override("separation", 6)
	_rooms_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_rooms_section)

	var rooms_header := HBoxContainer.new()
	rooms_header.add_theme_constant_override("separation", 8)
	rooms_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_section.add_child(rooms_header)

	# The one heading that shares its line with a control, so the rule goes under
	# the whole header row rather than under the label.
	var rooms_title := _heading_label("Open rooms")
	rooms_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rooms_header.add_child(rooms_title)

	var refresh_button := _make_button("Refresh", _on_refresh_rooms_pressed)
	refresh_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	rooms_header.add_child(refresh_button)

	_add_rule(_rooms_section)

	_rooms_status = Label.new()
	_rooms_status.name = "RoomsStatus"
	_rooms_status.text = ""
	_rooms_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rooms_status.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_rooms_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_section.add_child(_rooms_status)

	_rooms_box = VBoxContainer.new()
	_rooms_box.name = "RoomList"
	_rooms_box.add_theme_constant_override("separation", 6)
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_section.add_child(_rooms_box)

	# --- Host -------------------------------------------------------------
	_host_button = _make_button("Host a new room", _on_host_pressed)
	vbox.add_child(_host_button)

	# --- Join by code (the FALLBACK, for reaching one specific friend) -----
	_add_heading(vbox, "…or join by invite code")

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
	# `HudTheme.theme()` styles Panel / Button / Label / CheckBox and stops there —
	# a `LineEdit` left alone keeps the engine's rounded grey field on an INK card.
	# Three overrides off the palette rather than a fifth `theme()` slot: this is
	# the ONE text field in the HUD, and `hud_theme.gd` is not this bead's file.
	# **A theme gap, named in the PR**: a second panel with a field should promote
	# these into `HudTheme` rather than copy them.
	_code_input.add_theme_stylebox_override("normal", HudTheme.strip())
	_code_input.add_theme_stylebox_override("focus", HudTheme.button("focus"))
	_code_input.add_theme_color_override("font_color", HudTheme.BONE)
	_code_input.add_theme_color_override("font_placeholder_color", HudTheme.STEEL)
	_code_input.add_theme_color_override("caret_color", HudTheme.VISOR_AMBER)
	# AND THE READ-ONLY STATE, which is the one this panel spends most of its life
	# in: `_refresh()` sets `editable = false` the moment you are in a room, and a
	# `LineEdit` then draws its `read_only` box and `font_uneditable_color` instead
	# of the two overridden above — so the engine's rounded grey field came back on
	# the online panel (codex review 2026-09-05). Disabled is UNIT_KHAKI on the ink
	# ground, exactly as `HudTheme.button("disabled")` spells it for a Button.
	_code_input.add_theme_stylebox_override("read_only", HudTheme.button("disabled"))
	_code_input.add_theme_color_override("font_uneditable_color", HudTheme.UNIT_KHAKI)
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

	# --- Hero picker (shown only while in a room) -------------------------
	# Built empty: the pool arrives with the lobby's `welcome` frame, so the
	# buttons are filled in by `_rebuild_hero_buttons()` the first time a
	# `heroes` broadcast names one.
	_hero_row = VBoxContainer.new()
	_hero_row.name = "Heroes"
	_hero_row.add_theme_constant_override("separation", 6)
	_hero_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_row.visible = false
	vbox.add_child(_hero_row)

	_add_heading(_hero_row, "Hero")

	# --- Current room code + Copy (shown only while in a room) ------------
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 8)
	_code_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.visible = false
	vbox.add_child(_code_row)

	_code_label = Label.new()
	_code_label.name = "RoomCode"
	_code_label.text = ""
	# THE PANEL'S ONE AMBER, and it is the number a player reads out loud — the
	# spec rations the accent to one thing per screen region and lists "the coin
	# counter" as exactly this shape of element. Oswald BOLD and already all-caps:
	# the lobby's alphabet has no lower case, so there is nothing to `to_upper()`.
	_code_label.add_theme_font_override("font", HudTheme.heading_font())
	_code_label.add_theme_color_override("font_color", HudTheme.VISOR_AMBER)
	_code_label.add_theme_font_size_override("font_size", CODE_FONT_SIZE)
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_row.add_child(_code_label)

	var copy_button := _make_button("Copy", _on_copy_pressed)
	copy_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_code_row.add_child(copy_button)

	# --- Member list ------------------------------------------------------
	# The heading is a heading like every other; the names below it are one ROW
	# each since bead godot-test1-xtr.3, because a speaking dot and a per-peer mute
	# toggle are not things a joined string can carry. NO rule under this one: the
	# strips underneath draw their own 1 px STEEL frame, and the heading is empty
	# (nobody in the room) exactly as often as it is not.
	_members_label = _heading_label("")
	_members_label.name = "Members"
	_members_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_members_label)

	_members_box = VBoxContainer.new()
	_members_box.name = "MemberRows"
	_members_box.add_theme_constant_override("separation", 4)
	_members_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_members_box)

	# --- Voice chat controls (shown only while in a room) ------------------
	_voice_section = VBoxContainer.new()
	_voice_section.name = "VoiceSection"
	_voice_section.add_theme_constant_override("separation", 6)
	_voice_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_section.visible = false
	vbox.add_child(_voice_section)

	_voice_mode_button = _make_button("Voice: always on", _on_voice_mode_pressed)
	_voice_section.add_child(_voice_mode_button)

	_mic_mute_button = _make_button("Mute mic", _on_mic_mute_pressed)
	_voice_section.add_child(_mic_mute_button)

	_deafen_button = _make_button("Deafen", _on_deafen_pressed)
	_voice_section.add_child(_deafen_button)

	# INCOMING VOLUME (bead godot-test1-xtr.9) — the dial beside the switch. A
	# label carrying the value plus a slider, because a bare slider on a panel
	# with no tooltips says nothing about what it does or where it is set.
	_volume_label = Label.new()
	_volume_label.name = "VoiceVolume"
	_volume_label.text = tr("Voice volume: %d%%") % 100
	_volume_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_volume_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_volume_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_section.add_child(_volume_label)

	_volume_slider = HSlider.new()
	_volume_slider.name = "VoiceVolumeSlider"
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	# STEP 1, and not a nicer 5 (codex review 2026-09-05): `Range` snaps `value` to
	# `step` even through `set_value_no_signal`, so a stored 37% would draw its
	# thumb at 35 while the label and the audio said 37, and the first drag would
	# jump the setting. A step of 1 is the whole fix — quantizing on load instead
	# would be a second rounding rule to keep in step with this number.
	_volume_slider.step = 1.0
	_volume_slider.value = 100.0
	# Same reason every button in this panel is FOCUS_NONE: a focused Range eats
	# the arrow keys and `ui_accept`, both of which are gameplay input here.
	_volume_slider.focus_mode = Control.FOCUS_NONE
	# A `Slider` is another class `HudTheme.theme()` says nothing about, and the
	# engine's grey pill on an INK card is the one control that still reads as
	# somebody else's UI. The TRACK is a STEEL strip and the FILLED part is amber —
	# the spec's ability-dial language, and this section's single accent. The
	# grabber keeps its default texture: it is a knob, not a colour.
	_volume_slider.add_theme_stylebox_override("slider", HudTheme.strip())
	var volume_fill := StyleBoxFlat.new()
	volume_fill.bg_color = HudTheme.VISOR_AMBER
	volume_fill.set_corner_radius_all(0)
	volume_fill.anti_aliasing = false
	_volume_slider.add_theme_stylebox_override("grabber_area", volume_fill)
	_volume_slider.add_theme_stylebox_override("grabber_area_highlight", volume_fill)
	_volume_slider.custom_minimum_size = Vector2(0.0, TOUCH_MIN_HEIGHT)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_voice_volume_changed)
	_voice_section.add_child(_volume_slider)

	# OPT-IN AND OFF BY DEFAULT (owner ruling 2026-09-04, bead godot-test1-xtr.6):
	# the camera permission prompt is asked on the FIRST PRESS of this button and
	# nowhere else, so a player who never presses it is never asked.
	_camera_button = _make_button("Camera off", _on_camera_pressed)
	_voice_section.add_child(_camera_button)

	_mic_state_label = Label.new()
	_mic_state_label.name = "MicState"
	_mic_state_label.text = "Mic: off — press V"
	_mic_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mic_state_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_mic_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_section.add_child(_mic_state_label)

	# --- Leave + Close ----------------------------------------------------
	_leave_button = _make_button("Leave room", _on_leave_pressed)

	vbox.add_child(_leave_button)

	vbox.add_child(_make_button("Close", _on_mp_button_pressed))


## One SECTION HEADING: Oswald Bold, ALL CAPS, BONE — the spec's, and the caps are
## applied `.to_upper()` at the DRAW SITE, never in `ui.csv`, where the translation
## key IS the English source string (CLAUDE.md localization rule 1).
##
## Which is why the label cannot auto-translate: its `text` is the already-resolved
## German, upper-cased, and that string is a key in no table. So the source is kept
## in `_headings` and re-applied on `NOTIFICATION_TRANSLATION_CHANGED`, which is the
## notification Godot's own auto-translation rides and which `skill_tree_ui.gd`
## already hooks for the same reason (it composes its titles).
##
## Registration is skipped for an empty source: the member heading is a heading in
## LOOK only — `_rebuild_member_rows()` writes its text on every refresh.
func _heading_label(source: String) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override("font", HudTheme.heading_font())
	label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	label.add_theme_color_override("font_color", HudTheme.BONE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not source.is_empty():
		_headings.append({"label": label, "source": source})
		label.text = tr(source).to_upper()
	return label


## A heading plus the STEEL rule the spec puts under one, both parented to `parent`.
func _add_heading(parent: Control, source: String) -> void:
	parent.add_child(_heading_label(source))
	_add_rule(parent)


## The rule itself: a 1 px STEEL line, hard-edged like everything else here.
## `HSeparator` draws its `separator` StyleBox centred in `separation` px of space.
func _add_rule(parent: Control) -> void:
	var line := StyleBoxLine.new()
	line.color = HudTheme.STEEL
	line.thickness = HudTheme.BORDER_PX
	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", line)
	rule.add_theme_constant_override("separation", HudTheme.GRID / 2)
	parent.add_child(rule)


## Re-resolve every registered heading when the language changes. Without this a
## live `TranslationServer.set_locale()` would leave the caps headings in the
## language they were built in — the price of `.to_upper()` at the draw site.
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED:
		return
	for entry: Variant in _headings:
		var row: Dictionary = entry as Dictionary
		var label: Label = row.get("label", null)
		if label != null and is_instance_valid(label):
			label.text = tr(String(row.get("source", ""))).to_upper()
	# The member heading composes its own text; `_refresh()` is where that happens.
	# Guarded on a built panel: this notification also arrives while the node is
	# entering the tree, which is before `_build_ui()` has made anything to refresh.
	if _members_label != null:
		_refresh()


## Make one full-width, thumb-sized button wired to `handler`. Every button in
## the panel goes through here so the touch-target minimum — and the FOCUS_NONE
## rule below — can't be forgotten by the next button somebody adds.
func _make_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	# Keyboard focus is poison on a gameplay HUD — see `_build_ui`. Space is both
	# `ui_accept` and `jump`, so a focused Host/Join/Copy/Leave button fires again
	# on every jump. Panel buttons are less sticky than the MP toggle (hiding the
	# panel drops focus), but "less sticky" is not "fixed": Host and Join leave the
	# panel OPEN, so the very next Space press re-hosts or re-joins.
	button.focus_mode = Control.FOCUS_NONE
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
	# The cached node is gone (or was never found). Any connection we made was to
	# THAT object, so clear the latch — otherwise the re-fetch below hands back a
	# manager whose `room_changed`/`status` are silently unwired and the panel
	# goes permanently stale, which is the opposite of what this re-fetch promises.
	_signals_connected = false
	var tree := get_tree()
	if tree == null:
		return null
	_manager = tree.get_first_node_in_group("mp")
	if _manager != null and not _signals_connected:

		# `has_signal` guards keep this safe against a stand-in node that merely
		# happens to be in the group.
		if _manager.has_signal("room_changed"):
			_manager.room_changed.connect(_on_room_changed)
		if _manager.has_signal("status"):
			_manager.status.connect(_on_status)
		if _manager.has_signal("heroes_changed"):
			_manager.heroes_changed.connect(_on_heroes_changed)
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
		_on_status(tr("An invite code is %d characters") % CODE_LENGTH)
		return
	# Done typing — drop the caret so a phone's on-screen keyboard folds away and
	# stops covering the status line this join is about to write. Both entry
	# points land here (the Join button and Enter/"go" via `text_submitted`), so
	# this is the one place it belongs. It matters MORE now that Join is
	# FOCUS_NONE: tapping the button no longer steals the focus off the field.
	_code_input.release_focus()
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
	_on_status(tr("Copied %s to the clipboard") % code)


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
	_update_voice_ui()


# ============================================================================
# OPEN-ROOM LIST
# ============================================================================
## EVERY open room on the lobby appears here — rooms are public by default and
## there is no opt-in flag (the owner overrode the epic's invite-code-only
## framing: "copy code not convenient, show a list of opened lobbies"). The
## invite code stays as the way to reach one *specific* friend's room.
##
## The list is pulled on demand — when the panel opens and when Refresh is
## pressed — and never polled. A timer would run for the whole session to keep a
## list fresh that is only looked at in the seconds the panel is open, and the
## lobby has no push channel for it that would not mean joining a room first.

func _on_refresh_rooms_pressed() -> void:
	_refresh_rooms()


## Ask the manager for the lobby's open rooms. Safe to call any time: in a room
## the section is hidden and there is nothing to draw, and without a manager it
## says so instead of erroring.
func _refresh_rooms() -> void:
	if _rooms_pending:
		return
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("list_rooms"):
		_clear_room_buttons()
		_set_rooms_status("Multiplayer is not available in this scene")
		return
	_rooms_pending = true
	_set_rooms_status("Looking for rooms…")
	manager.list_rooms(_on_rooms_listed)


## Draw the lobby's answer.
##
## The array is untrusted input off an HTTP socket, so every row is checked
## whole before it becomes a button — the same rule `_member_lines()` applies to
## the member list, and for the same reason: a malformed entry must cost that one
## row, not the panel. A code that is not exactly `CODE_LENGTH` characters is
## dropped rather than trimmed, because a button that joins a code the lobby
## never offered would create a junk room.
func _on_rooms_listed(rooms: Array) -> void:
	_rooms_pending = false
	# The fetch outlives nothing here (this is a HUD node), but a callback landing
	# after a scene change would otherwise touch freed children.
	if not is_inside_tree():
		return
	_clear_room_buttons()

	for entry: Variant in rooms:
		if _rooms_buttons.size() >= ROOM_ROW_MAX:
			break
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = entry as Dictionary
		# TYPE-CHECKED, not converted. `String(v)` / `int(v)` are Variant
		# CONSTRUCTORS with no overload for most types — `String({})` raises
		# "Nonexistent 'String' constructor" at runtime, and a GDScript runtime
		# error unwinds the whole calling function, so one malformed row from a
		# hostile or buggy lobby (the URL is settable with `?lobby=`) aborted this
		# loop mid-way: the rows already built stayed on screen and the trailing
		# `_set_rooms_status()` / `_refresh()` never ran, leaving the panel stuck
		# on "Looking for rooms…". `_hero_summary()` below already does it this way.
		var raw_code: Variant = room.get("code", "")
		if typeof(raw_code) != TYPE_STRING:
			continue
		var code: String = (raw_code as String).strip_edges().to_upper()
		if code.length() != CODE_LENGTH:
			continue
		var raw_count: Variant = room.get("members", 0)
		if typeof(raw_count) != TYPE_INT and typeof(raw_count) != TYPE_FLOAT:
			continue
		# Finiteness BEFORE the cast, the rule every decoder in mp_manager.gd
		# states: `1e999` is well-formed JSON, parses to INF, and the lobby URL is
		# attacker-settable with `?lobby=` — so on wasm a crafted /rooms body
		# could trap the module on the float→int trunc the moment the panel opens.
		var count_f: float = float(raw_count)
		if not is_finite(count_f):
			continue
		var count: int = int(count_f)
		# The lobby already withholds full and empty rooms; re-checking here means
		# an older or misbehaving lobby cannot put an unjoinable row on screen.
		if count < 1 or count >= MAX_MEMBERS:
			continue
		var label: String = "%s  ·  %d/%d" % [code, count, MAX_MEMBERS]
		var heroes: String = _hero_summary(room.get("heroes", []))
		if not heroes.is_empty():
			label += "  ·  %s" % heroes
		# `bind` rather than a capturing lambda, for the same reason the hero
		# buttons use it: the code a row joins is fixed at build time.
		var button := _make_button(label, _on_room_row_pressed.bind(code))
		# One line, clipped rather than wrapped or widened: the row must stay a
		# fixed-height touch target whatever the lobby put in it, and the code —
		# the part that identifies the room — is at the front where clipping
		# cannot reach it.
		button.clip_text = true
		_rooms_box.add_child(button)
		_rooms_buttons.append(button)

	if _rooms_buttons.is_empty():
		_set_rooms_status("No open rooms — host one and a friend can join it here")
	else:
		_set_rooms_status("Tap a room to join")
	# Rows are only pressable while offline; `_refresh()` owns that rule.
	_refresh()


## One press on a row IS the join — no code to read, type or copy.
func _on_room_row_pressed(code: String) -> void:
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("join"):
		_on_status("Multiplayer is not available in this scene")
		return
	manager.join(code)


func _clear_room_buttons() -> void:
	if _rooms_box == null:
		return
	for button: Button in _rooms_buttons:
		# Unparent BEFORE freeing — `queue_free` only lands at the end of the
		# frame, so a stale row would sit under its replacement for one frame of a
		# visibly doubled list. Same rule as `_rebuild_hero_buttons()`.
		_rooms_box.remove_child(button)
		button.queue_free()
	_rooms_buttons.clear()


func _set_rooms_status(message: String) -> void:
	if _rooms_status != null:
		_rooms_status.text = message


## "Windman, Primm" from the lobby's hero array, so a row says who is already in
## the room. Untrusted like everything else in the entry: non-strings are skipped
## and the list is capped, because this is a button label, not a document.
func _hero_summary(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY:
		return ""
	var names: PackedStringArray = PackedStringArray()
	for hero: Variant in value as Array:
		if names.size() >= ROOM_ROW_HERO_MAX:
			break
		if typeof(hero) != TYPE_STRING:
			continue
		var text: String = (hero as String).strip_edges()
		if text.is_empty():
			continue
		names.append(text.capitalize())
	if names.is_empty():
		return ""
	return ", ".join(names)


# ============================================================================
# HERO PICKER
# ============================================================================
## THE LOBBY IS THE SOURCE OF TRUTH. Pressing a hero only sends a claim; the
## button state below is redrawn from the `heroes` broadcast that answers it, so
## two players reaching for the same hero can never both look like they got it.
## A refused claim comes back as a status line and leaves the room intact (see
## `MpManager.HERO_ERRORS`), which is why nothing here has a failure path of its
## own.

func _on_heroes_changed(heroes: Dictionary, pool: Array) -> void:
	var names: Array[String] = []
	for hero: Variant in pool:
		# TYPE-CHECKED, not converted, for exactly the reason spelled out over the
		# room rows in `_on_rooms_listed`: `String(v)` is a Variant CONSTRUCTOR
		# with no overload for most types, and the resulting runtime error unwinds
		# this whole function. `LobbyClient` type-checks the CONTAINER, never the
		# elements, so one non-string in the pool from a hostile or older lobby
		# (the URL is settable with `?lobby=`) aborted before `_rebuild_hero_buttons`
		# ever ran — leaving the room with no hero picker at all.
		if typeof(hero) != TYPE_STRING:
			continue
		names.append(hero as String)
	if names != _hero_pool:
		_rebuild_hero_buttons(names)
	_refresh_hero_buttons(heroes)


## Replace the row's buttons, one per hero the lobby offers. Called only when the
## pool itself changes — in practice once per room, and once more with an empty
## pool when `leave()` emits `heroes_changed({}, [])`.
func _rebuild_hero_buttons(pool: Array[String]) -> void:
	if _hero_row == null:
		return
	for button: Button in _hero_buttons:
		# Unparent BEFORE freeing: `queue_free` only takes effect at the end of
		# the frame, so a button left in place would sit under the replacements
		# added just below for one frame of a visibly doubled row.
		_hero_row.remove_child(button)
		button.queue_free()
	_hero_buttons.clear()
	_hero_pool = pool
	for hero: String in pool:
		# `bind` rather than a capturing lambda so the hero name a button sends
		# is fixed at build time and cannot drift with the loop variable.
		var button := _make_button(hero.capitalize(), _on_hero_pressed.bind(hero))
		# THE CHIP WEARS THE HERO'S OWN TINT — the identity colour the portrait row
		# already paints that hero's tile in, so the picker and the HUD agree.
		# Overriding only `font_color` leaves `font_disabled_color` alone, which the
		# theme has already set to UNIT_KHAKI: the corporation's neutral is exactly
		# the spec's "a teammate has him" / "she is in a cell" state, and it comes
		# out of the palette for free rather than being a second decision here.
		var tint: Variant = HeroHud.HERO_COLORS.get(hero, null)
		if tint != null:
			button.add_theme_color_override("font_color", tint as Color)
			button.add_theme_color_override("font_hover_color", tint as Color)
			button.add_theme_color_override("font_pressed_color", tint as Color)
		_hero_row.add_child(button)
		_hero_buttons.append(button)


## Relabel every hero button for the current assignments: ours is marked, one
## somebody else holds is disabled and named with its holder, a free one is
## pressable.
func _refresh_hero_buttons(heroes: Dictionary) -> void:
	var manager := _ensure_manager()
	var mine: String = ""
	if manager != null and manager.has_method("my_hero"):
		mine = String(manager.my_hero())
	for i: int in range(_hero_buttons.size()):
		var hero: String = _hero_pool[i]
		var button: Button = _hero_buttons[i]
		# Same trust boundary as the pool above: an assignment whose holder is not
		# a string must read as "free", not abort the relabel loop and leave the
		# rest of the row stuck on stale text and a stale `disabled`.
		var raw_holder: Variant = heroes.get(hero, "")
		var holder: String = (raw_holder as String) if typeof(raw_holder) == TYPE_STRING else ""
		# A HERO IN A CELL IS OFFERED TO NOBODY (bead godot-test1-3iy.10), and this
		# clause is FIRST for the same reason the captive test comes before the
		# `mine` clause in `MpManager.available_heroes()`: the one press this rule
		# has to refuse is the benched player re-picking the body that was just
		# taken off them, which every clause below would have shown as pressable.
		# `has_method`-guarded like every other manager read here.
		var captive: bool = manager != null and manager.has_method("is_hero_captive") \
				and bool(manager.is_hero_captive(hero))
		if captive:
			button.text = tr("%s — in a cell") % hero.capitalize()
			button.disabled = true
		elif hero == mine:
			button.text = tr("%s  ✓ you") % hero.capitalize()
			button.disabled = false
		elif holder.is_empty():
			button.text = hero.capitalize()
			button.disabled = false
		else:
			button.text = "%s — %s" % [hero.capitalize(), _member_name(manager, holder)]
			button.disabled = true
	# Visibility is decided the same way in `_refresh()`; both paths run, because
	# a `heroes` broadcast and a `room_changed` do not arrive together.
	if _hero_row != null:
		var online: bool = manager != null and manager.has_method("is_online") and bool(manager.is_online())
		_hero_row.visible = online and not _hero_buttons.is_empty()


func _on_hero_pressed(hero: String) -> void:
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("claim_hero"):
		_on_status("Multiplayer is not available in this scene")
		return
	manager.claim_hero(hero)


## A lobby id's display name, falling back to a short form of the id itself so a
## held hero is never labelled with a blank. The member list is parsed JSON from
## the lobby, so every entry is checked before it is read.
func _member_name(manager: Node, id: String) -> String:
	if manager != null and manager.has_method("get_members"):
		for member: Variant in manager.get_members():
			if typeof(member) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = member as Dictionary
			# Type-checked rather than converted — see `_on_heroes_changed`.
			var raw_id: Variant = entry.get("id", "")
			if typeof(raw_id) != TYPE_STRING or (raw_id as String) != id:
				continue
			var raw_name: Variant = entry.get("name", "")
			if typeof(raw_name) == TYPE_STRING:
				return raw_name as String
			break
	return id.substr(0, 4)


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
## Open the panel from outside — the start overlay's "Multiplayer" button, found
## through the `"mp_ui"` group. Idempotent, so a second press is harmless.
##
## The overlay releases its own pause before calling this, and `_set_panel_open`
## takes ours synchronously, so the tree is never unpaused for even one frame
## between the two.
func open_panel() -> void:
	if not _panel_open:
		_set_panel_open(true)


func _set_panel_open(open: bool) -> void:
	_panel_open = open
	if _panel_body != null:
		_panel_body.visible = open

	_apply_pause(open)

	if open:
		# Clamp the panel to the space actually above the button — a phone's
		# scaled viewport can be shorter than the full stack, and a
		# PanelContainer poking past the screen top is unreachable even through
		# its own ScrollContainer (which scrolls its CONTENT, not its frame).
		var view_height: float = get_viewport().get_visible_rect().size.y
		_panel_body.offset_top = maxf(_panel_body.offset_bottom - PANEL_HEIGHT, -view_height + EDGE_MARGIN)
		_refresh()
		# Pull the room list on open — the panel is the only place it is read, so
		# this is the moment it needs to be fresh, and it is why no timer polls it.
		# Skipped in a room: the section is hidden there and a request for a list
		# nobody can see is a request not worth making.
		if not _is_online():
			_refresh_rooms()
	else:
		# The code field is the ONE control in this panel that legitimately takes
		# keyboard focus — you have to type into it — so it cannot be FOCUS_NONE
		# like the buttons. Hand the focus back on the way out: hiding a Control
		# already drops it, but this also dismisses a phone's on-screen keyboard,
		# and it means no future refactor that closes the panel WITHOUT hiding it
		# can leave a text field quietly eating W/A/S/D.
		if _code_input != null:
			_code_input.release_focus()
		if _recapture_mouse:
			# Closing is a user gesture, which is exactly what browser pointer-lock
			# needs, so this works on desktop web too.
			_recapture_mouse = false
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Take or release the pause for the panel's current state.
##
## Called every frame from `_process`, not just at open time, because the
## game-over exemption below is a MOVING condition: open the panel over the Game
## Over screen (deliberately unpaused), then hit Play Again or Enter, and the
## world is live again underneath a panel that never took the pause — restoring
## both failures the pause exists to prevent (clicks re-capturing the mouse,
## typed invite codes walking the player, since the code alphabet holds W/A/S/D).
##
## Never pause over the Game Over screen itself — the same rule (and the same
## reason) as `pause_controller._toggle_pause()` and `mobile_input.pause_game()`:
## `GameOverUI` is PAUSABLE, so a pause there kills both its "Play Again" button
## and its `ui_accept` handler, and the phone's resume overlay is gated on
## `paused_by_driver` so it would not appear either. The panel still OPENS — it
## is readable and closable — it just does not freeze the tree, which is safe
## because a game-over player is already frozen and the desktop-web
## click-to-capture is itself guarded on `is_game_over`.
func _apply_pause(open: bool) -> void:
	if not open and not _paused_by_us:
		return  # The overwhelmingly common case: closed panel, nothing to undo.
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player")
	var game_over: bool = player != null and bool(player.get("is_game_over"))
	if open and not game_over:
		# `not _paused_by_us`, where this used to read `not tree.paused`: the pause
		# is refcounted now (scripts/pause_hub.gd), so the question at a call site
		# is only ever "do WE already hold a claim". Opening this panel over the
		# help card or a P-pause therefore adds a second holder instead of riding
		# somebody else's — and neither one can start the world under the other.
		if not _paused_by_us:
			PauseHub.take(self)
			_paused_by_us = true
			# Free a captured mouse so the buttons can be clicked. This lives HERE
			# and not in `_set_panel_open` because the pause is taken lazily: open
			# the panel over Game Over (exempt, mouse already free), then hit Play
			# Again — `restart_game()` re-captures the mouse and the NEXT frame this
			# function finally pauses. Releasing only at open time left that path
			# paused with a captured cursor pinned to screen centre and every escape
			# hatch dead (ESC/P/`ui_accept` all run on PAUSABLE nodes) — a softlock.
			# Only remember the handover when WE did it — see the header comment.
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				_recapture_mouse = true
	elif _paused_by_us:
		# Only ever release OUR claim — `pause_controller` and `mobile_input`
		# carry the mirror-image guard, and `PauseHub` starts the world again only
		# once the last of them has let go.
		_paused_by_us = false
		PauseHub.release(self)


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

	# The room list is a way IN, so it is hidden once you are in a room — unlike
	# Host/Join it is not merely meaningless there, it is a whole section of rows
	# that would push everything a player actually needs (code, heroes, Leave)
	# below the fold. Rows are disabled too, in case one is somehow pressed
	# between a join landing and this refresh.
	if _rooms_section != null:
		_rooms_section.visible = not online
	for button: Button in _rooms_buttons:
		button.disabled = online

	# THE PERSISTENT ROOM INDICATOR. The always-on toggle becomes the read-out:
	# code plus head count while in a room, plain "MP" while solo. See the header.
	if _mp_button != null:
		if online and not code.is_empty():
			var count: int = 0
			if manager.has_method("get_members"):
				count = manager.get_members().size()
			_mp_button.text = "%s  %d/%d" % [code, count, MAX_MEMBERS]
			_mp_button.add_theme_font_size_override("font_size", MP_BUTTON_FONT_SIZE_ONLINE)
			_mp_button.offset_right = EDGE_MARGIN + MP_BUTTON_WIDTH_ONLINE
		else:
			_mp_button.text = "MP"
			_mp_button.add_theme_font_size_override("font_size", MP_BUTTON_FONT_SIZE)
			_mp_button.offset_right = EDGE_MARGIN + MP_BUTTON_WIDTH

	if _hero_row != null:
		_hero_row.visible = online and not _hero_buttons.is_empty()

	if _code_row != null:
		_code_row.visible = not code.is_empty()
	if _code_label != null:
		_code_label.text = code

	var heading: String = _rebuild_member_rows(manager)
	if _members_label != null:
		_members_label.text = heading

	_update_voice_ui()



## True while the manager reports an actual room. False with no manager at all,
## so a scene without the Multiplayer node reads as "solo" everywhere.
func _is_online() -> bool:
	var manager := _ensure_manager()
	return manager != null and manager.has_method("is_online") and bool(manager.is_online())


## The current room code, or "" when there is no room (or no manager).
func _current_code() -> String:
	var manager := _ensure_manager()
	if manager == null or not manager.has_method("get_room_code"):
		return ""
	return String(manager.get_room_code())


## Rebuild the member ROWS from the lobby's `[{"id": ..., "name": ...}, ...]`.
## One row per member: a speaking dot, the name, and — for everybody but you — a
## per-peer mute toggle. The lobby is a trust boundary, so a member entry that is
## not a dictionary with a string name is skipped rather than crashing the HUD.
##
## Returns the heading the caller puts above the rows ("" when there is nobody,
## which also hides the box).
func _rebuild_member_rows(manager: Node) -> String:
	var entries: Array = []
	var sig: String = ""
	var you: String = ""
	if manager != null and manager.has_method("my_id"):
		you = String(manager.my_id())
	if manager != null and manager.has_method("get_members"):
		for member: Variant in manager.get_members():
			if typeof(member) != TYPE_DICTIONARY:
				continue
			# Type-checked rather than converted — see `_on_heroes_changed`.
			# `has("name")` only proved the key exists, so a non-string name still
			# aborted the render and blanked the whole member list.
			var raw_name: Variant = (member as Dictionary).get("name", null)
			if typeof(raw_name) != TYPE_STRING:
				continue
			var id: String = str((member as Dictionary).get("id", ""))
			entries.append({"id": id, "name": raw_name as String})
			sig += "%s%s" % [id, raw_name as String]
	sig += "%s" % you

	if sig != _member_sig:
		_member_sig = sig
		_member_rows.clear()
		for child: Node in _members_box.get_children():
			child.queue_free()
		for entry: Variant in entries:
			_members_box.add_child(_make_member_row(entry as Dictionary, you))

	if _members_box != null:
		_members_box.visible = not entries.is_empty()
	_update_member_rows()
	# `.to_upper()` at the draw site, like every other heading here.
	return tr("In room:").to_upper() if not entries.is_empty() else ""


## One member as an INK_RAISED STRIP (bead godot-test1-y1o.29) — the spec's raised
## secondary row, `HudTheme.strip()`, which is why this returns the wrapper and not
## the `HBoxContainer` it used to. Everything else about the row is unchanged.
func _make_member_row(entry: Dictionary, you: String) -> PanelContainer:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", HudTheme.strip())
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HudTheme.GRID / 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(row)

	# The dot is a glyph, not a word — nothing to translate and nothing to fit.
	# `font_color` and NOT `modulate`: the theme paints a `Label` BONE, and a
	# modulate MULTIPLIES that, so a STEEL dot would come out a muddy two-thirds
	# STEEL. The override replaces the colour outright.
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	dot.custom_minimum_size = Vector2(DOT_WIDTH, 0.0)
	dot.add_theme_color_override("font_color", DOT_IDLE)
	row.add_child(dot)

	# `clip_text` is the room rows' own rule (see `locale_selfcheck`'s header):
	# a lobby name is up to 32 characters of somebody else's choosing, so the
	# label must be structurally unable to overflow rather than merely short.
	var name_label := Label.new()
	name_label.text = String(entry.get("name", ""))
	# A lobby name is somebody's own text, and a bare `Label` AUTO-TRANSLATES it
	# (CLAUDE.md's rule 1: the key IS the English string) — so a player calling
	# themselves "Hero" or "Mute" would show up in German as this panel's own
	# widget labels. The old joined "• %s" line was safe by accident; a row is
	# not (codex review 2026-09-04).
	name_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	var id: String = String(entry.get("id", ""))
	var mute: Button = null
	# No mute button on your own row: silencing yourself is the "Mute mic" button
	# above, which is a different thing (send side, not receive side).
	if not id.is_empty() and id != you:
		mute = _make_button("Mute", _on_peer_mute_pressed.bind(id))
		mute.size_flags_horizontal = Control.SIZE_SHRINK_END
		mute.custom_minimum_size = Vector2(MUTE_BUTTON_WIDTH, TOUCH_MIN_HEIGHT)
		# Built always, SHOWN only where there is voice to mute — the availability
		# check is `_update_member_rows()`'s, not this builder's, because voice is
		# found through the group and may not be in the tree yet when the first
		# member list lands. Off the web export it never appears at all, which is
		# the same gate `_voice_section` is behind (codex review 2026-09-04: a
		# 104 px button that mutes nothing was eating the name's width on desktop).
		mute.visible = false
		row.add_child(mute)

	_member_rows.append({"id": id, "dot": dot, "mute": mute})
	return strip


## Repaint the dots and relabel the per-peer buttons. Driven from `_process`,
## because a dot has to follow speech at the voice module's own 10 Hz and
## `_refresh()` only fires on lobby events. Four rows and two dictionary lookups
## each — cheaper than deciding whether it is worth skipping.
func _update_member_rows() -> void:
	if _member_rows.is_empty():
		return
	var voice := _ensure_voice()
	var available: bool = voice != null and voice.has_method("is_available") \
			and bool(voice.is_available())
	var speaks: bool = available and voice.has_method("is_speaking")
	var mutes: bool = available and voice.has_method("is_peer_muted")
	var you: String = ""
	var manager := _ensure_manager()
	if manager != null and manager.has_method("my_id"):
		you = String(manager.my_id())
	for row: Variant in _member_rows:
		var entry: Dictionary = row as Dictionary
		var id: String = String(entry.get("id", ""))
		var dot: Label = entry.get("dot", null)
		if dot != null and is_instance_valid(dot):
			# Your own dot is driven by the LOCAL microphone's level, which the
			# voice module reports under its own key rather than under your lobby
			# id (nothing on the wire carries your own audio back to you).
			var key: String = VOICE_SELF_KEY if (not you.is_empty() and id == you) else id
			var on: bool = speaks and not key.is_empty() and bool(voice.is_speaking(key))
			# `font_color`, not `modulate` — see `_make_member_row()`.
			dot.add_theme_color_override("font_color", DOT_SPEAKING if on else DOT_IDLE)
		var mute: Button = entry.get("mute", null)
		if mute != null and is_instance_valid(mute):
			mute.visible = mutes
			if mutes:
				mute.text = "Muted" if bool(voice.is_peer_muted(id)) else "Mute"


# ============================================================================
# VOICE CHAT CONTROLS (bead godot-test1-xtr.2)
# ============================================================================

func _ensure_voice() -> Node:
	if _voice != null and is_instance_valid(_voice):
		return _voice
	var tree := get_tree()
	if tree == null:
		return null
	_voice = tree.get_first_node_in_group("voice")
	if _voice != null and not _voice_signals_connected:
		_voice_signals_connected = true
		if _voice.has_signal("mode_changed"):
			_voice.connect("mode_changed", _on_voice_mode_changed)
		if _voice.has_signal("tx_changed"):
			_voice.connect("tx_changed", _on_voice_tx_changed)
		if _voice.has_signal("mic_denied_changed"):
			_voice.connect("mic_denied_changed", _on_voice_mic_denied_changed)
		if _voice.has_signal("camera_changed"):
			_voice.connect("camera_changed", _on_camera_changed)
	return _voice


func _on_voice_mode_changed(_mode: Variant) -> void:
	_update_voice_ui()


func _on_voice_tx_changed(_tx: Variant) -> void:
	_update_voice_ui()


func _on_voice_mic_denied_changed(_denied: Variant) -> void:
	_update_voice_ui()


func _on_voice_mode_pressed() -> void:
	var voice := _ensure_voice()
	if voice == null:
		return
	var current_mode: int = voice.get_mode()
	var new_mode: int = 1 if current_mode == 0 else 0
	voice.set_mode(new_mode)
	_update_voice_ui()


## The three escape hatches (bead godot-test1-xtr.3). Each is a plain toggle on
## the voice node — no confirmation, no persistence — because the whole point of
## an escape hatch from somebody else's microphone is that it takes one press.

func _on_mic_mute_pressed() -> void:
	var voice := _ensure_voice()
	if voice == null or not voice.has_method("set_mic_muted"):
		return
	voice.set_mic_muted(not bool(voice.is_mic_muted()))
	_update_voice_ui()


func _on_deafen_pressed() -> void:
	var voice := _ensure_voice()
	if voice == null or not voice.has_method("set_deafened"):
		return
	voice.set_deafened(not bool(voice.is_deafened()))
	_update_voice_ui()


func _on_camera_pressed() -> void:
	var voice := _ensure_voice()
	if voice == null or not voice.has_method("set_camera_enabled"):
		return
	voice.set_camera_enabled(not bool(voice.is_camera_on()))
	_update_voice_ui()


func _on_camera_changed(_on: Variant) -> void:
	# The press is synchronous; the permission prompt's answer is not, so the
	# button's label is repainted when it lands rather than polled for.
	_update_voice_ui()


func _on_peer_mute_pressed(id: String) -> void:
	var voice := _ensure_voice()
	if voice == null or not voice.has_method("set_peer_muted"):
		return
	voice.set_peer_muted(id, not bool(voice.is_peer_muted(id)))
	_update_member_rows()


## The slider moved. The percent is the panel's unit and the voice node's API is
## the fraction, so the one conversion in the feature happens here.
func _on_voice_volume_changed(value: float) -> void:
	var voice := _ensure_voice()
	if voice == null or not voice.has_method("set_volume"):
		return
	voice.set_volume(value / 100.0)
	_update_voice_ui()


func _update_voice_ui() -> void:
	if _voice_section == null:
		return
	var voice := _ensure_voice()
	var available: bool = voice != null and voice.has_method("is_available") and bool(voice.is_available())
	var online := _is_online()
	_voice_section.visible = online and available
	if not _voice_section.visible or voice == null:
		return

	var mode: int = voice.get_mode()
	var tx: bool = voice.is_tx()

	if _voice_mode_button != null:
		if mode == 1:
			_voice_mode_button.text = "Voice: push to talk"
		else:
			_voice_mode_button.text = "Voice: always on"

	if _mic_mute_button != null:
		var muted: bool = voice.has_method("is_mic_muted") and bool(voice.is_mic_muted())
		_mic_mute_button.text = "Mic muted" if muted else "Mute mic"

	if _deafen_button != null:
		var deaf: bool = voice.has_method("is_deafened") and bool(voice.is_deafened())
		_deafen_button.text = "Deafened" if deaf else "Deafen"

	if _volume_slider != null and voice.has_method("get_volume"):
		var pct: int = int(roundf(float(voice.get_volume()) * 100.0))
		# `set_value_no_signal` or this write re-enters `_on_voice_volume_changed`
		# on every panel refresh, which would write the store on every repaint.
		_volume_slider.set_value_no_signal(float(pct))
		if _volume_label != null:
			# tr() on the FORMAT string (CLAUDE.md localization rule 2) — the
			# formatted result is a key in no table.
			_volume_label.text = tr("Voice volume: %d%%") % pct

	if _camera_button != null:
		var can_cam: bool = voice.has_method("set_camera_enabled")
		_camera_button.visible = can_cam
		if can_cam:
			# A refusal is reported ON the button that asked, which is why the
			# camera needs no status line of its own beside the microphone's.
			if voice.has_method("camera_denied") and bool(voice.camera_denied()):
				_camera_button.text = "Camera blocked"
				_camera_button.disabled = true
			else:
				var on: bool = voice.has_method("is_camera_on") and bool(voice.is_camera_on())
				_camera_button.disabled = false
				_camera_button.text = "Camera on" if on else "Camera off"

	if _mic_state_label != null:
		# MUTE WINS over the V state, so it wins the label too: reporting
		# "transmitting" while the track is disabled is the one lie this row must
		# never tell.
		if voice.has_method("is_mic_muted") and voice.is_mic_muted():
			_mic_state_label.text = "Mic: muted"
		elif voice.has_method("mic_denied") and voice.mic_denied():
			_mic_state_label.text = "Mic: blocked — listening only"
		elif mode == 1:
			_mic_state_label.text = "Mic: transmitting" if tx else "Mic: off — hold V"
		else:
			_mic_state_label.text = "Mic: on — press V" if tx else "Mic: off — press V"

