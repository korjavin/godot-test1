extends Control
## On-screen touch controls — Task 5 of the mobile-motion plan.
##
## This is the player-facing half of the mobile-controls feature. The motion
## driver (`mobile_input.gd`) turns the phone's sensors into the *analog* actions
## (`move_forward` from stepping, `turn_left`/`turn_right` from tilt/twist); this
## Control supplies the buttons for everything that has **no** motion gesture:
##
##   * **Jump**       → fires the polled `jump` action.
##   * **Special (F)**→ fires the polled `special_ability` action.
##   * **Switch (R)** → fires the *event-driven* `switch_character` action.
##   * **steer toggle**→ flips the driver between TILT and TWIST steering.
##
## plus a first-run **"Tap to enable motion controls"** overlay that satisfies
## iOS Safari's user-gesture requirement for motion permission and calibrates the
## neutral pose, then gets out of the way.
##
## ----------------------------------------------------------------------------
## No hard references — found by group, like the rest of the HUD
## ----------------------------------------------------------------------------
## Following the project convention (see `ability_hud.gd`, `CrocodileLODManager`),
## this UI holds **no** hard reference to the motion driver. It locates it through
## the `"mobile_input"` group with `get_tree().get_first_node_in_group(...)`, so it
## keeps working regardless of scene wiring order. It talks *only* to that driver's
## public API (`enable()`, `disable()`, `set_steer_mode()`, `request_permission()`,
## `calibrate()`), never to the sensor object underneath.
##
## ----------------------------------------------------------------------------
## The discrete-button → action gotcha (critical — see the plan)
## ----------------------------------------------------------------------------
## `player_controller.gd` consumes its inputs two different ways, and the buttons
## must match each one:
##   * `jump` and `special_ability` are **polled** with `is_action_just_pressed()`.
##     Driving them with `Input.action_press()` + `action_release()` (next frame)
##     sets the polled state the controller reads — that works.
##   * `switch_character` is handled in the controller's **`_input()`** callback,
##     NOT polled. `Input.action_press("switch_character")` would set the polled
##     state but never dispatch an `InputEventAction` through `_input()`, so the
##     switch would silently not fire. It therefore MUST go through
##     `Input.parse_input_event(InputEventAction)`, which flows the synthetic event
##     through the full input pipeline (including every `_input()`). We use that
##     same `parse_input_event` path for jump/special too, so all three buttons use
##     ONE consistent mechanism (a pressed event now, a matching released event next
##     frame) — simpler to reason about than mixing `action_press` and events.
##
## ----------------------------------------------------------------------------
## Mobile-only gating (desktop stays byte-for-byte unchanged)
## ----------------------------------------------------------------------------
## Per the project's platform discipline, this whole Control is hidden and the
## driver left idle on desktop, so keyboard+mouse play is untouched. We auto-show
## it only on a touch device (`DisplayServer.is_touchscreen_available()`, plus a
## web coarse-pointer check), and provide a developer **F6** force-show so the UI
## can be exercised in the editor on desktop without affecting a release build.

# ============================================================================
# CONSTANTS — layout / tuning
# ============================================================================

## Side length (px) of the three big action buttons. Phone touch targets want to
## be large and forgiving; ~120 px clears Apple's/Google's ~44-48 pt minimum with
## room to spare even on a high-DPI display.
const ACTION_BUTTON_SIZE: float = 120.0

## Gap (px) between stacked action buttons and from the screen edge, so the cluster
## reads as a tidy group in the bottom-right thumb zone without crowding the edge.
const BUTTON_MARGIN: float = 24.0

## Size of the small steer-mode toggle, parked top-centre away from the action
## cluster and clear of the existing HUD (coins top-right, perf/lives top-left).
const TOGGLE_WIDTH: float = 150.0
const TOGGLE_HEIGHT: float = 64.0

## Developer force-show key. F3 = perf overlay, F4 = motion readout, F5 = mobile_input
## force-enable; F6 is the next free function key. Pressing it toggles this UI on so a
## developer can see/test the buttons in the editor on a desktop (no touchscreen). It
## is a debug key, deliberately outside the project input map (like F3/F4/F5), and
## never affects a released desktop build because real play has no touchscreen.
const FORCE_SHOW_KEYCODE: Key = KEY_F6

# ============================================================================
# STATE
# ============================================================================

## Cached driver reference, re-fetched via the group if it ever goes away. Found in
## `_ready()` and used by every button handler. May be null on a build with no
## MobileInput node (then the buttons safely no-op).
var _driver: Node = null

## True once the enable overlay has been tapped, so we don't keep re-requesting
## permission / re-enabling on every later interaction.
var _motion_enabled: bool = false

## True while the UI is force-shown by the F6 debug key on a non-touch device, so a
## second F6 press toggles it back off. Independent of the auto (touch) visibility.
var _force_shown: bool = false

# --- Child node references (built in _ready, not from the .tscn) ------------
# The buttons are created in code rather than declared in the scene so all their
# wiring (text, size, anchors, signal connections) lives in one readable place and
# the .tscn stays a trivial single-node container. They are added as children here.

var _jump_button: Button = null
var _special_button: Button = null
var _switch_button: Button = null
var _steer_toggle: Button = null
var _enable_overlay: Button = null


func _ready() -> void:
	# The root Control spans the whole screen (full-rect anchors set in the .tscn).
	# We keep its mouse_filter at PASS so it doesn't itself swallow touches meant for
	# the game world (the buttons below capture their own input via STOP), matching
	# the plan's "PASS on the root, buttons capture their own input" note.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Find the motion driver by group — no hard reference, exactly like ability_hud
	# finds the player. May be null on a stripped build; every handler guards for it.
	_driver = get_tree().get_first_node_in_group("mobile_input")

	# Build the buttons + overlay in code so all their setup lives together.
	_build_ui()

	# Decide initial visibility from the platform. On a phone/tablet we show the UI
	# and the enable overlay; on desktop we hide everything and leave the driver idle
	# so keyboard+mouse play is untouched (the F6 key can still force-show for testing).
	_apply_platform_visibility()


func _input(event: InputEvent) -> void:
	# Developer force-show toggle (F6). Raw key, not a named action: this is a debug
	# aid that intentionally sits outside the project input map, like the F3/F4/F5
	# debug keys. It lets us see the touch UI in the editor on a desktop with no
	# touchscreen; on a release desktop build there's no touchscreen so the UI still
	# never auto-shows, and a player would have to press F6 deliberately to see it.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == FORCE_SHOW_KEYCODE:
			_force_shown = not _force_shown
			_apply_platform_visibility()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

## Build every button and the enable overlay and wire their signals. Called once
## from _ready(). Buttons are anchored so they reposition correctly on any screen
## size / orientation without us tracking the viewport ourselves.
func _build_ui() -> void:
	# --- Action cluster: Jump / Special / Switch, stacked bottom-RIGHT -----
	# Bottom-right is the natural right-thumb zone and is clear of the existing HUD
	# (coins top-right, ability dial top-right, perf/lives top-left, motion debug
	# bottom-left). We stack three big square buttons up from the bottom edge.
	#
	# Anchoring: each button anchors to the bottom-right corner (anchor 1,1) and is
	# pushed in/up by negative offsets, so it stays glued to that corner on resize.
	_jump_button = _make_action_button("JUMP", 1)
	_special_button = _make_action_button("SPECIAL\n(F)", 2)
	_switch_button = _make_action_button("SWITCH\n(R)", 3)

	# Connect each to its routing handler. Jump/Special use the "fire once" pulse;
	# Switch uses the same event path (its handler is identical but named for clarity).
	_jump_button.pressed.connect(_on_jump_pressed)
	_special_button.pressed.connect(_on_special_pressed)
	_switch_button.pressed.connect(_on_switch_pressed)

	# --- Steer-mode toggle, parked top-CENTRE -----------------------------
	# Small, away from the action cluster and clear of the corner HUD elements. Its
	# label reflects the current steer mode so the player always knows which way a
	# tap will flip it.
	_steer_toggle = Button.new()
	_steer_toggle.name = "SteerToggle"
	_steer_toggle.custom_minimum_size = Vector2(TOGGLE_WIDTH, TOGGLE_HEIGHT)
	_steer_toggle.add_theme_font_size_override("font_size", 22)
	# Anchor to the top-centre: both horizontal anchors at 0.5 centres it, then we
	# pull it left by half its width and down a margin from the top.
	_steer_toggle.anchor_left = 0.5
	_steer_toggle.anchor_right = 0.5
	_steer_toggle.anchor_top = 0.0
	_steer_toggle.anchor_bottom = 0.0
	_steer_toggle.offset_left = -TOGGLE_WIDTH * 0.5
	_steer_toggle.offset_right = TOGGLE_WIDTH * 0.5
	_steer_toggle.offset_top = BUTTON_MARGIN
	_steer_toggle.offset_bottom = BUTTON_MARGIN + TOGGLE_HEIGHT
	_steer_toggle.pressed.connect(_on_steer_toggle_pressed)
	add_child(_steer_toggle)
	# Seed its label from the driver's current mode (TILT by default).
	_update_steer_toggle_label()

	# --- First-run enable overlay (full-rect) -----------------------------
	# A big, semi-transparent Button covering the whole screen. We use a Button (not
	# a Panel) because it natively handles the tap and gives us the user-gesture call
	# stack iOS requires for DeviceMotionEvent.requestPermission(). It sits LAST in
	# the child order so it draws on top of the action buttons until dismissed.
	_enable_overlay = Button.new()
	_enable_overlay.name = "EnableOverlay"
	_enable_overlay.text = "Tap to enable motion controls"
	_enable_overlay.add_theme_font_size_override("font_size", 32)
	# A translucent dark fill so the world is still faintly visible behind the prompt.
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	_enable_overlay.add_theme_stylebox_override("normal", overlay_style)
	_enable_overlay.add_theme_stylebox_override("hover", overlay_style)
	_enable_overlay.add_theme_stylebox_override("pressed", overlay_style)
	# Full-rect: cover the whole Control (anchors_preset 15 equivalent).
	_enable_overlay.anchor_right = 1.0
	_enable_overlay.anchor_bottom = 1.0
	_enable_overlay.offset_left = 0.0
	_enable_overlay.offset_top = 0.0
	_enable_overlay.offset_right = 0.0
	_enable_overlay.offset_bottom = 0.0
	_enable_overlay.pressed.connect(_on_enable_overlay_pressed)
	add_child(_enable_overlay)


## Create one big square action button with the given label and stack slot. Slot 1
## is the lowest (bottom-most) button; higher slots stack upward. Anchored to the
## bottom-right corner so the cluster stays put on any screen size.
func _make_action_button(label: String, slot: int) -> Button:
	var button := Button.new()
	button.name = label.replace("\n", "_")
	button.text = label
	button.add_theme_font_size_override("font_size", 26)
	button.custom_minimum_size = Vector2(ACTION_BUTTON_SIZE, ACTION_BUTTON_SIZE)
	# Anchor to the bottom-right corner (1,1).
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	# Horizontal: glue the right edge a margin in from the screen's right edge.
	button.offset_right = -BUTTON_MARGIN
	button.offset_left = -BUTTON_MARGIN - ACTION_BUTTON_SIZE
	# Vertical: stack upward from the bottom. Slot 1 sits one margin up from the
	# bottom; each higher slot adds another (button height + margin).
	var bottom_offset: float = -BUTTON_MARGIN - float(slot - 1) * (ACTION_BUTTON_SIZE + BUTTON_MARGIN)
	button.offset_bottom = bottom_offset
	button.offset_top = bottom_offset - ACTION_BUTTON_SIZE
	add_child(button)
	return button


# ============================================================================
# PLATFORM GATING / VISIBILITY
# ============================================================================

## Show the whole UI only on a touch/mobile device (or when force-shown via F6);
## otherwise hide it entirely so desktop keyboard+mouse play is untouched. Also
## drives whether the enable overlay is presented (only when actually shown and not
## yet enabled).
func _apply_platform_visibility() -> void:
	var on_touch: bool = _is_touch_device()
	# Visible if the platform is touch OR a developer force-showed it for testing.
	visible = on_touch or _force_shown

	# The enable overlay only makes sense while the UI is up and motion hasn't been
	# enabled yet. If we're hidden, or already enabled, keep it down.
	if _enable_overlay != null:
		_enable_overlay.visible = visible and not _motion_enabled


## True on a phone/tablet. Primary signal is Godot's own touchscreen probe; on web
## we also accept a CSS coarse-pointer media query, because some mobile browsers do
## not report a touchscreen through `DisplayServer` but DO match `pointer: coarse`.
## Everything JS is guarded behind `OS.has_feature("web")` so desktop never evals JS.
func _is_touch_device() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	# Web fallback: a coarse pointer (finger) strongly implies a touch device. Guard
	# the JavaScriptBridge call behind the web feature so desktop/editor never touch JS.
	if OS.has_feature("web"):
		var coarse = JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches", true)
		if coarse != null and bool(coarse):
			return true
	return false


# ============================================================================
# BUTTON ROUTING → INPUT ACTIONS
# ============================================================================
# All three action buttons funnel through `_fire_action()` for ONE consistent
# mechanism. See the class header's "discrete-button → action gotcha": switch_character
# is handled in the controller's _input() (not polled), so we MUST dispatch a real
# InputEventAction through parse_input_event() — and we use that same path for jump /
# special so every button behaves identically.

## Dispatch a one-shot press of a named action through the full input pipeline. We
## send a *pressed* InputEventAction now (which makes both the polled-state readers
## like `is_action_just_pressed("jump")` AND the event readers like the controller's
## `event.is_action_pressed("switch_character")` in `_input()` see it), then queue a
## matching *released* event for the next frame so the action doesn't latch on.
func _fire_action(action_name: String) -> void:
	var press := InputEventAction.new()
	press.action = action_name
	press.pressed = true
	# parse_input_event flows the synthetic event through the WHOLE pipeline, so it
	# reaches both polling and `_input()` consumers — the only way switch_character
	# (an `_input()`-handled action) can be triggered from code.
	Input.parse_input_event(press)
	# Release on the next frame so just-pressed fires exactly once and the action
	# isn't left stuck "held". call_deferred runs after the current frame's input.
	call_deferred("_release_action", action_name)


## Send the matching released InputEventAction, ending the one-shot press above.
func _release_action(action_name: String) -> void:
	var release := InputEventAction.new()
	release.action = action_name
	release.pressed = false
	Input.parse_input_event(release)


## Jump button → the polled `jump` action (controller reads is_action_just_pressed).
func _on_jump_pressed() -> void:
	_fire_action("jump")


## Special button → the polled `special_ability` action (F key equivalent).
func _on_special_pressed() -> void:
	_fire_action("special_ability")


## Switch button → the event-driven `switch_character` action (R key equivalent).
## This is the one that *requires* the parse_input_event path (see header) because
## the controller handles it in `_input()`, not by polling.
func _on_switch_pressed() -> void:
	_fire_action("switch_character")


## Steer toggle → flip the driver's steer mode TILT <-> TWIST and update the label.
## `set_steer_mode()` also recalibrates (re-zeros neutral), so the toggle doubles as
## the player's manual "re-centre steering" gesture, per the plan.
func _on_steer_toggle_pressed() -> void:
	if _driver == null or not is_instance_valid(_driver):
		_driver = get_tree().get_first_node_in_group("mobile_input")
	if _driver == null:
		return
	# Cycle to the other mode. The driver's enum is SteerMode { TILT = 0, TWIST = 1 }.
	var current = _driver.steer_mode
	var next = _driver.SteerMode.TWIST if current == _driver.SteerMode.TILT else _driver.SteerMode.TILT
	_driver.set_steer_mode(next)
	_update_steer_toggle_label()


## Refresh the steer toggle's caption to show the *current* mode, so the player can
## read which scheme is active at a glance. Falls back gracefully if the driver is
## missing (the toggle just shows a neutral label and does nothing on tap).
func _update_steer_toggle_label() -> void:
	if _steer_toggle == null:
		return
	if _driver == null or not is_instance_valid(_driver):
		_driver = get_tree().get_first_node_in_group("mobile_input")
	if _driver == null:
		_steer_toggle.text = "Tilt/Twist"
		return
	# Show the active mode in the label, e.g. "Steer: Tilt".
	if _driver.steer_mode == _driver.SteerMode.TILT:
		_steer_toggle.text = "Steer: Tilt"
	else:
		_steer_toggle.text = "Steer: Twist"


## First tap of the enable overlay: satisfy the iOS motion-permission gesture and
## start the driver. This handler runs inside the tap's user-gesture call stack,
## which is exactly what iOS Safari requires for DeviceMotionEvent.requestPermission().
## We then hide the overlay so the game (and the action buttons beneath) is usable.
func _on_enable_overlay_pressed() -> void:
	if _driver == null or not is_instance_valid(_driver):
		_driver = get_tree().get_first_node_in_group("mobile_input")
	if _driver != null:
		# Order matters: request permission first (still inside the user gesture), then
		# enable the driver. `enable()` already calibrates neutral from the current pose
		# (see mobile_input.enable()), so we deliberately do NOT call calibrate() again
		# here — that would double-calibrate redundantly.
		_driver.request_permission()
		_driver.enable()
	_motion_enabled = true
	# Drop the overlay so play can begin; the action buttons underneath become usable.
	if _enable_overlay != null:
		_enable_overlay.visible = false
