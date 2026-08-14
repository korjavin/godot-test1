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
## public API (`enable()`, `disable()`, `set_steer_mode()`, `request_permission()`),
## never to the sensor object underneath.
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
const TOGGLE_WIDTH: float = 200.0
const TOGGLE_HEIGHT: float = 72.0

## Developer force-show key. F3 = perf overlay, F4 = motion readout, F5 = mobile_input
## force-enable; F6 is the next free function key. Pressing it toggles this UI on so a
## developer can see/test the buttons in the editor on a desktop (no touchscreen). It
## is a debug key, deliberately outside the project input map (like F3/F4/F5), and
## never affects a released desktop build because real play has no touchscreen.
const FORCE_SHOW_KEYCODE: Key = KEY_F6

## Grace period (seconds) after the enable tap during which we WATCH for motion data
## to actually start flowing before committing. iOS resolves `requestPermission()`
## asynchronously and a denial / non-secure-context / sensorless device produces NO
## `devicemotion` samples at all. If none arrive within this window we re-show the
## overlay ("tap to retry") instead of latching enabled — so a keyboardless phone is
## never stranded with the controls hidden and no way back. ~3.5 s comfortably covers
## the permission dialog round-trip plus a few sensor frames without feeling sticky.
const MOTION_ENABLE_TIMEOUT: float = 3.5

# ============================================================================
# STATE
# ============================================================================

## Cached driver reference, re-fetched via the group if it ever goes away. Found in
## `_ready()` and used by every button handler. May be null on a build with no
## MobileInput node (then the buttons safely no-op).
var _driver: Node = null

## True once the enable overlay has been tapped AND motion data actually started
## flowing, so we don't keep re-requesting permission / re-enabling on every later
## interaction. It is NOT set merely by tapping — see `_motion_watching` for the
## "tapped but waiting to confirm data" interim state.
var _motion_enabled: bool = false

## True while we are WATCHING for motion to start after an enable tap, but before it
## has actually been confirmed (or timed out). During this window the overlay is
## hidden (so play can begin immediately if data flows) but NOT latched, so if the
## grace period expires with no data we can re-show it for a retry. See `_process`.
var _motion_watching: bool = false

## Seconds elapsed in the current `_motion_watching` window, accumulated in `_process`
## (which already runs for the action-release queue). Compared against
## `MOTION_ENABLE_TIMEOUT` to decide "data started" vs "re-show the retry overlay".
var _motion_watch_elapsed: float = 0.0

## True while the UI is force-shown by the F6 debug key on a non-touch device, so a
## second F6 press toggles it back off. Independent of the auto (touch) visibility.
var _force_shown: bool = false

## Names of actions whose synthetic *press* was dispatched this frame and whose
## matching *release* must be dispatched on a GUARANTEED-LATER frame. See `_fire_action`
## / `_process` for why a same-frame `call_deferred` release is avoided.
var _actions_to_release: PackedStringArray = []

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
	# Pass an explicit PascalCase node name separate from the visible label, so the
	# node tree reads as `JumpButton`/`SpecialButton`/`SwitchButton` (clean, debuggable)
	# while the on-screen TEXT keeps its newline + "(F)"/"(R)" hint.
	_jump_button = _make_action_button("JUMP", "JumpButton", 1)
	_special_button = _make_action_button("SPECIAL\n(F)", "SpecialButton", 2)
	_switch_button = _make_action_button("SWITCH\n(R)", "SwitchButton", 3)

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
	_steer_toggle.add_theme_font_size_override("font_size", 30)
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


## Create one big square action button with the given visible `label`, an explicit
## PascalCase `node_name` (so the scene tree reads cleanly instead of deriving a
## messy name like "SPECIAL_(F)" from the label), and a stack `slot`. Slot 1 is the
## lowest (bottom-most) button; higher slots stack upward. Anchored to the
## bottom-right corner so the cluster stays put on any screen size.
func _make_action_button(label: String, node_name: String, slot: int) -> Button:
	var button := Button.new()
	button.name = node_name
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


## True on a phone/tablet. Delegates to `MobileSensors.is_touch_session()` — the ONE
## canonical detection rule (touchscreen probe, plus a web coarse-/not-fine-pointer
## fallback), shared with the player's mouse-capture guard so the two can never
## disagree. (Previously this rule lived here AND a *narrower* rule lived in
## `player_controller`, so a web phone could show this UI yet still capture the mouse.)
##
## We keep the F6 debug-force-show as a SEPARATE OR in `_apply_platform_visibility()`,
## not here, so this function stays a pure "is this really a touch device?" predicate.
## Everything JS in the canonical func is guarded behind `OS.has_feature("web")`, so
## desktop never evaluates JS and the desktop regression is preserved exactly.
func _is_touch_device() -> bool:
	return MobileSensors.is_touch_session()


# ============================================================================
# DRIVER LOOKUP (single mechanism — like _fire_action for input)
# ============================================================================

## Refresh and return the cached motion driver, re-resolving it via the
## `"mobile_input"` group if it was never found or has since been freed. Every
## handler that talks to the driver routes through this ONE helper (instead of
## repeating the null/`is_instance_valid` re-fetch inline), matching the project's
## single-mechanism-helper style (cf. `_fire_action` for input). Returns null on a
## build with no MobileInput node, so callers must still null-check the result.
func _ensure_driver() -> Node:
	if _driver == null or not is_instance_valid(_driver):
		_driver = get_tree().get_first_node_in_group("mobile_input")
	return _driver


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
## matching *released* event for a GUARANTEED-LATER frame so the action doesn't latch.
##
## RELEASE-NEXT-FRAME (not same-frame call_deferred):
## A `call_deferred` release fires later in the *same* idle frame, before the next
## physics/process tick polls input. In practice `is_action_just_pressed` still latches
## for one frame even then, but to remove all doubt we instead queue the release and
## flush it at the *top of the next `_process` frame* (see `_process`). That guarantees
## a full frame elapses with the action pressed, so every consumer — the polled
## `jump`/`special_ability` (read in the controller's `_physics_process`) and the
## `_input()`-handled `switch_character` — reliably sees exactly one press.
func _fire_action(action_name: String) -> void:
	var press := InputEventAction.new()
	press.action = action_name
	press.pressed = true
	# parse_input_event flows the synthetic event through the WHOLE pipeline, so it
	# reaches both polling and `_input()` consumers — the only way switch_character
	# (an `_input()`-handled action) can be triggered from code.
	Input.parse_input_event(press)
	# Queue the matching release for the next frame rather than this one.
	_actions_to_release.append(action_name)


## Send the matching released InputEventAction, ending the one-shot press above.
func _release_action(action_name: String) -> void:
	var release := InputEventAction.new()
	release.action = action_name
	release.pressed = false
	Input.parse_input_event(release)


## Per-frame housekeeping: (1) flush any synthetic-action releases queued last frame by
## `_fire_action` (the guaranteed-later-frame release that makes the press last exactly
## one frame), and (2) drive the enable-overlay motion WATCH so a denied/dataless enable
## re-shows the retry overlay instead of stranding the player. Both are cheap no-ops when
## idle, and the whole function is inert on desktop (the UI is hidden and never enabled).
func _process(delta: float) -> void:
	# --- 1. Flush queued action releases ----------------------------------
	if not _actions_to_release.is_empty():
		for action_name in _actions_to_release:
			_release_action(action_name)
		_actions_to_release.clear()

	# --- 2. Enable-overlay motion watch -----------------------------------
	_update_motion_watch(delta)


## Watch for motion to actually start after an enable tap. While `_motion_watching`:
## if a fresh real motion sample is flowing, CONFIRM — latch `_motion_enabled` and stop
## watching (the overlay is already hidden). Otherwise count down `MOTION_ENABLE_TIMEOUT`;
## on expiry with still no data, RE-SHOW the overlay with a retry prompt so the player can
## try again (re-grant permission, or it was a non-secure context). No-op when not watching.
func _update_motion_watch(delta: float) -> void:
	if not _motion_watching:
		return

	# Read the driver's owned sensor (shared instance, found via the group) and ask
	# whether a genuine motion sample is flowing. Null-safe at every hop: a missing
	# driver/sensor simply means "no data yet", which lets the timeout re-show the overlay.
	var receiving: bool = false
	var driver: Node = _ensure_driver()
	if driver != null:
		var sensors: MobileSensors = driver.get_sensors()
		if sensors != null:
			receiving = sensors.is_receiving_motion()

	if receiving:
		# Data confirmed: latch the feature on and stop watching. The overlay is already
		# hidden from the tap, so there's nothing more to do here.
		_motion_enabled = true
		_motion_watching = false
		return

	# Still no data — count down the grace window.
	_motion_watch_elapsed += delta
	if _motion_watch_elapsed >= MOTION_ENABLE_TIMEOUT:
		# Gave it a fair chance and nothing arrived (permission denied, non-secure
		# context, or no sensor). Stop watching and re-show the overlay so the player can
		# retry — never leave a keyboardless phone with the controls hidden and no way back.
		_motion_watching = false
		if _enable_overlay != null:
			_enable_overlay.text = "Motion unavailable — tap to retry"
			_enable_overlay.visible = true


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
	if _ensure_driver() == null:
		return
	# Cycle to the other mode. The driver's enum is SteerMode { TILT = 0, TWIST = 1 },
	# so the values are plain ints — hence the `: int` hints.
	var current: int = _driver.steer_mode
	var next: int = _driver.SteerMode.TWIST if current == _driver.SteerMode.TILT else _driver.SteerMode.TILT
	_driver.set_steer_mode(next)
	_update_steer_toggle_label()


## Refresh the steer toggle's caption to show the *current* mode, so the player can
## read which scheme is active at a glance. Falls back gracefully if the driver is
## missing (the toggle just shows a neutral label and does nothing on tap).
func _update_steer_toggle_label() -> void:
	if _steer_toggle == null:
		return
	if _ensure_driver() == null:
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
##
## RETRY PATH (the fix): tapping does NOT permanently latch the feature. There are two
## ways an enable can silently fail and strand a keyboardless phone:
##   * no MobileInput node (a stripped build), handled here by leaving the overlay up;
##   * permission DENIED / non-secure-context / sensorless device → `requestPermission()`
##     resolves (async) without ever delivering a `devicemotion` sample.
## So instead of hiding+latching outright, we kick off the driver and enter a short
## WATCH window (`_motion_watching`): the overlay is hidden so play can begin the moment
## data flows, but it is re-shown ("tap to retry") if no motion arrives within
## `MOTION_ENABLE_TIMEOUT` (driven in `_process`). Only when real motion is confirmed do
## we latch `_motion_enabled`. (With calibrate-on-first-data in MobileSensors, neutral is
## captured from the first REAL sample, not the stale pre-permission default, so iOS's
## async grant no longer biases steering.)
func _on_enable_overlay_pressed() -> void:
	# This tap is the guaranteed user gesture on mobile web — unlock audio here
	# (before any early return: no driver must not mean no sound). Null-safe, so
	# a scene without a SoundManager never errors.
	var sm := get_tree().get_first_node_in_group("sound_manager")
	if sm and sm.has_method("unlock_audio"):
		sm.unlock_audio()

	if _ensure_driver() == null:
		# No driver to talk to: do NOT latch enabled or hide the overlay. The overlay
		# stays visible and tappable so the player can retry (e.g. if the node appears
		# later), instead of being left with a hidden overlay and no controls at all.
		# Re-label so the player understands a retry is possible.
		if _enable_overlay != null:
			_enable_overlay.text = "Motion unavailable — tap to retry"
		return

	# Order matters: request permission first (still inside the user gesture), then
	# enable the driver. `enable()` already calibrates neutral from the current pose
	# (see mobile_input.enable()), so we deliberately do NOT call calibrate() again
	# here — that would double-calibrate redundantly.
	_driver.request_permission()
	_driver.enable()

	# Begin the watch rather than latching: hide the overlay so play can start, but keep
	# the door open to re-show it if motion never materialises. `_process` accumulates
	# `_motion_watch_elapsed` and either confirms (data arrived) or re-shows the overlay.
	_motion_watching = true
	_motion_watch_elapsed = 0.0
	if _enable_overlay != null:
		_enable_overlay.visible = false
