extends Control
## ============================================================================
## START OVERLAY — the first thing a player sees, and the only place
## multiplayer is impossible to miss
## ============================================================================
## The problem it exists for, from the owner's playtest of the deployed build:
## *"opened the URL, game just starts, no idea multiplayer exists."* The MP
## button was there the whole time, 110 px wide in the bottom-left corner of a
## running game whose mouse had already been captured — functional, and in
## practice invisible. Two hidden steps (press ESC to free the cursor, then find
## a small button) is not a feature a first-time visitor discovers.
##
## So the game no longer starts on its own. It opens on one screen with two
## choices:
##
##     PLAY SOLO        — one press, and everything is exactly as it was
##     MULTIPLAYER      — one press, and the room list is open
##
## Solo stays **one action deep**: a returning player who never wants
## multiplayer presses one button (or Enter/Space) and is in the game. That is
## the whole tax, and it buys the other half of the audience an entry point they
## can actually find.
##
## ----------------------------------------------------------------------------
## Built in code, no assets — the project convention
## ----------------------------------------------------------------------------
## `touch_controls.gd`, `mobile_settings_panel.gd`, `game_over_ui.gd` and
## `mp_ui.gd` all build their entire UI in `_ready()` from bare `Control`s and a
## `StyleBoxFlat`, so `main.tscn` carries nothing but a `Control` with this
## script on it. This one does the same, and it borrows `mp_ui`'s `_make_button`
## rule wholesale — see `_make_button()` below for why FOCUS_NONE is load-bearing
## and not a style preference.
##
## ----------------------------------------------------------------------------
## It pauses the tree, and it is the reason the mouse is not captured yet
## ----------------------------------------------------------------------------
## Two things have to be true while this screen is up, and one pause gives both:
##
##   * the world must not run — crocodiles chase, coins spawn and the fauna timer
##     ticks the moment `main.tscn` loads, and a player reading a menu should not
##     be losing hearts behind it; and
##   * the player must not be *driven* — `player_controller` reads gameplay
##     through the global polled `Input` state and through `_input()`, neither of
##     which a `Control` on top suppresses, so Space (Play Solo's own shortcut)
##     would also jump.
##
## `process_mode` gates `_input` and `_physics_process` together, so pausing is
## the one-line fix for both — exactly the argument `mp_ui._set_panel_open()`
## makes for the MP panel, and the `_paused_by_us` guard here is the same guard
## `pause_controller.gd`, `mobile_input.gd` and `mp_ui.gd` carry on each other:
## only ever release a pause WE took.
##
## **Mouse capture is handed over rather than suppressed.** `player_controller`
## captures the mouse in its own `_ready()`, which runs *before* this node's
## (`Player` is an earlier child of `Main` than `HUD`), so this overlay simply
## releases it while the menu is up and captures it again on dismiss — meaning
## `player_controller.gd` needed **no edit at all**. Capturing at dismiss is
## strictly better than the old boot-time capture on desktop web, where a
## browser refuses pointer lock outside a user gesture: the button press IS the
## gesture, so the camera now works from the first frame of play instead of
## waiting for the click-to-capture fallback.
##
## ----------------------------------------------------------------------------
## On a phone it waits its turn
## ----------------------------------------------------------------------------
## `touch_controls.gd` opens with a full-rect "tap to enable motion controls"
## overlay, and that tap is the ONE user gesture iOS grants
## `DeviceMotionEvent.requestPermission()` and the browser grants WebAudio. This
## Control is the last `HUD` child, so it draws above that overlay and would
## steal the tap — killing motion and all audio for the session. It therefore
## hides itself (and drops its pause) while `touch_controls.has_modal()`, the
## same three lines `mp_ui.gd` and `mobile_settings_panel.gd` run for the same
## reason. On a phone the order is: enable motion → choose Solo or Multiplayer.

# ============================================================================
# CONSTANTS — layout
# ============================================================================

## The centred card's minimum width — wide enough for the title, narrow enough to
## fit a portrait phone's short edge. Its HEIGHT is deliberately not a constant:
## the card sits in a `CenterContainer` and sizes to its own content, so a long
## game title that wraps to two lines grows the card instead of overflowing it.
const CARD_WIDTH: float = 420.0

## Buttons are past the ~44-48 pt minimum touch target, and PLAY SOLO is the
## taller of the two: it is the default action, and on a phone the difference in
## size is the fastest way to read which one that is.
const BUTTON_HEIGHT: float = 64.0

const TITLE_FONT_SIZE: int = 40
const BUTTON_FONT_SIZE: int = 24
const HINT_FONT_SIZE: int = 16

# ============================================================================
# STATE
# ============================================================================

## True once a choice has been made. From then on this node is inert forever —
## hidden, not processing, holding no pause. There is no way back to the menu by
## design: "Play Again" restarts in place and the MP panel is the way into a
## room, so a second visit to this screen would only be a way to lose the run.
var _dismissed: bool = false

## Whether the CURRENT tree pause is ours to release. See the header.
var _paused_by_us: bool = false

## Cached once — the touch-session probe can reach into JavaScriptBridge, so it
## is not re-evaluated per frame (the same caching `touch_controls.gd` does).
var _is_touch: bool = false

# --- Child node references (built in _ready, not from a .tscn) --------------

## Everything visible, in one child so the touch-modal yield is a single
## `visible` flip. The ROOT stays MOUSE_FILTER_IGNORE, so while this is hidden
## the overlay is completely transparent to input.
var _body: Control = null


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available
	# HUD piece (`mp_ui.gd`, `mobile_settings_panel.gd`, `MpManager`).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The root spans the screen but is never a hit-test target itself; `_body`
	# below is the modal that actually swallows input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_is_touch = MobileSensors.is_touch_session()
	_build_ui()

	# Take the pause and the cursor now, before the first gameplay frame runs.
	_apply_pause(true)


func _process(_delta: float) -> void:
	if _dismissed:
		return
	# Yield the screen to TouchControls' full-rect overlays — see the header for
	# why stealing that one tap would cost the session its motion permission and
	# all of its audio. Re-evaluated every frame rather than latched at _ready:
	# the enable overlay is dismissed by a tap, and this must come back when it
	# does.
	var blocked: bool = _touch_modal_up()
	if _body != null:
		_body.visible = not blocked
	# HIDE, BUT KEEP THE PAUSE. The overlay that is actually up at this moment on
	# every phone is the first-run "tap to enable motion controls" one
	# (`touch_controls` shows it whenever motion is not yet enabled), so releasing
	# here meant `_ready()`'s pause lasted exactly one frame and the world ran live
	# — crocodiles closing on a spawn bubble only 25 m wide — while the player had
	# not yet chosen PLAY SOLO or MULTIPLAYER. That is the one thing this node
	# exists to prevent.
	#
	# Nothing is stranded behind the held pause: all three of `has_modal()`'s
	# overlays are PROCESS_MODE_ALWAYS and dismiss themselves, and the resume
	# overlay in particular can never be the blocker here — it is gated on
	# `mobile_input.paused_by_driver`, which is false while WE own the pause.
	_apply_pause(true)


## True while `touch_controls.gd` has one of its own full-rect overlays up.
## Null-safe group lookup with a `has_method` guard, like every other cross-node
## reach in this project.
func _touch_modal_up() -> bool:
	var touch_ui: Node = get_tree().get_first_node_in_group("touch_controls")
	return touch_ui != null and touch_ui.has_method("has_modal") and bool(touch_ui.has_modal())


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	_body = Control.new()
	_body.name = "Body"
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: this is a modal. It has to swallow every click, or the
	# desktop-web click-to-capture in `player_controller._input()` fires through
	# it and warps the cursor to screen centre while the menu is still up.
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_body)

	# Dim the running world behind the card rather than hiding it: the terrain,
	# the sky and the fog are the game's own best screenshot, and a solid splash
	# would only be one more thing to art-direct.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(dim)

	# A CenterContainer rather than centre anchors + hand-computed offsets: it
	# centres its child at the child's OWN minimum size, so the card grows to fit
	# whatever the title turns out to be instead of clipping it.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(centre)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.06, 0.09, 0.94)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	centre.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.name = "Choices"
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title := Label.new()
	# Read from the project settings rather than hardcoded, so the game's name
	# lives in exactly one place and a rename never leaves the title screen
	# saying something else.
	title.text = String(ProjectSettings.get_setting("application/config/name", "")).to_upper()
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Run the road. Outrun the crocodiles."
	subtitle.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var solo := _make_button("PLAY SOLO", _on_play_solo_pressed)
	# The default action, and the taller of the two so which one that is reads at
	# a glance rather than from the label.
	solo.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT + 8.0)
	solo.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE + 2)
	vbox.add_child(solo)

	vbox.add_child(_make_button("MULTIPLAYER", _on_multiplayer_pressed))

	var hint := Label.new()
	hint.text = "Multiplayer: play the same world with up to 4 friends"
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)


## One full-width, thumb-sized button. FOCUS_NONE is copied from
## `mp_ui._make_button()` and carries the same warning: `ui_accept` is SPACE,
## SPACE is also `jump`, and Godot's `BaseButton` KEEPS the focus after a click.
## A focused button here would re-fire on the player's very first jump — and the
## first thing this one does is dismiss a menu, so the second press would land on
## whatever replaced it.
func _make_button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	return button


# ============================================================================
# CHOICES
# ============================================================================

## Enter / Space takes the default action, so a desktop player never has to reach
## for the mouse to start. Handled here rather than by focusing the button
## because focusing it is exactly the bug FOCUS_NONE exists to prevent (see
## `_make_button`) — this Control is PROCESS_MODE_ALWAYS, so it receives input
## under its own pause with nothing focused at all.
func _unhandled_input(event: InputEvent) -> void:
	# The touch-modal test is the same one `_process` uses to hide the body: while
	# one of `touch_controls`' full-rect overlays is up this card is INVISIBLE, and
	# without the test one Enter dismissed it anyway — permanently and unseen,
	# since `_dismissed` is one-way and there is no route back to this screen.
	if _dismissed or event == null or _touch_modal_up():
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_play_solo_pressed()


func _on_play_solo_pressed() -> void:
	_dismiss()


func _on_multiplayer_pressed() -> void:
	# NOT capturing the mouse: the panel is about to open and wants the cursor.
	# On web `Input.set_mouse_mode(CAPTURED)` only REQUESTS pointer lock — the
	# browser grants it on a later task — so `mp_ui._apply_pause()`'s
	# `mouse_mode == MOUSE_MODE_CAPTURED` test would read VISIBLE, decline to
	# release it, and the lock would then land with the panel open: cursor warped
	# to screen centre, Join/Copy/Leave/Close unreachable. Exactly the failure the
	# panel's pause exists to prevent.
	_dismiss(false)
	# Open the MP panel through the group, no hard reference — the same discovery
	# rule the rest of the HUD follows. `_dismiss()` released our pause and the
	# panel takes its own synchronously inside `open_panel()`, so the world is
	# never unpaused for even one frame in between.
	var panel: Node = get_tree().get_first_node_in_group("mp_ui")
	if panel != null and panel.has_method("open_panel"):
		panel.open_panel()


## Stand down for good: hide, stop processing, release the pause, hand the mouse
## back to the game.
func _dismiss(capture_mouse: bool = true) -> void:
	if _dismissed:
		return
	_dismissed = true
	if _body != null:
		_body.visible = false
	visible = false
	set_process(false)
	set_process_unhandled_input(false)
	_apply_pause(false)

	# A button press is a real user gesture, which is exactly what browsers
	# require for both of the things below — and the whole reason doing them HERE
	# is better than at boot.
	#
	# 1. Audio. `sound_manager` gates every `play_*` behind `unlock_audio()` and
	#    normally unlocks on its own `_input()` — which does not run while the
	#    tree is paused, so this press would otherwise not count and the first
	#    sound would wait for the next key or click in play.
	var sound: Node = get_tree().get_first_node_in_group("sound_manager")
	if sound != null and sound.has_method("unlock_audio"):
		sound.unlock_audio()

	# 2. Pointer lock. Skipped on a touch session for the same reason
	#    `player_controller._ready()` skips it: there is no mouse to capture and
	#    the request would pop a useless prompt over the touch controls.
	if capture_mouse and not _is_touch:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Take or release the pause for the overlay's current state, and hand the mouse
## across with it. Mirrors `mp_ui._apply_pause()`, including the "only ever
## release OUR pause" guard.
func _apply_pause(active: bool) -> void:
	if not active and not _paused_by_us:
		return
	var tree := get_tree()
	if active:
		if not tree.paused:
			tree.paused = true
			_paused_by_us = true
		# Free the cursor so the buttons are clickable. Unconditional — unlike
		# `mp_ui`, this node has no handover to remember: `_dismiss()` always
		# captures (on a non-touch session), whichever button was pressed.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_paused_by_us = false
		tree.paused = false
