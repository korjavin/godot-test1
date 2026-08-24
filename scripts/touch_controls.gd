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
##   * **View**       → fires the polled `toggle_camera` action (C key: 1st/3rd person).
##
## plus a first-run **"TAP TO START"** onboarding overlay (a mini how-to that also
## satisfies iOS Safari's user-gesture requirement for motion permission and
## calibrates the neutral pose, then gets out of the way — re-showable later as a
## help screen via `show_onboarding()`), and a full-screen **portrait guard** that
## asks the player to rotate to landscape.
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
## reads as a tidy group in the bottom-right thumb zone. 64 (raised from 24) keeps
## the bottom-most button clear of the iOS home-indicator swipe strip, which grew
## in on-screen size once TOUCH_CONTENT_SCALE started magnifying the whole UI.
const BUTTON_MARGIN: float = 64.0

## UI magnification applied on REAL touch sessions only (never desktop, never the
## F6 debug force-show). The math that motivates 1.8: the project renders a
## 1920x1080 design viewport with `canvas_items` stretch, so on an iPhone 14
## landscape (~844 CSS px wide) every design px is scaled by ~844/1920 ≈ 0.44 —
## and with `aspect=expand` fitting the shorter axis it lands nearer 0.364. That
## turns the 120 px JUMP button into ~44 CSS px, the bare Apple minimum (and ~25 px
## in portrait — hopeless). `content_scale_factor` multiplies the whole 2D/UI layer
## (3D render cost untouched): 120 × 1.8 × 0.364 ≈ 79 CSS px — comfortably tappable.
const TOUCH_CONTENT_SCALE: float = 1.8

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

## Onboarding overlay copy. The overlay doubles as a mini how-to: a big headline
## plus the three things a first-time phone player must know. The headline swaps
## to RETRY_HEADLINE when an enable attempt times out with no motion data (see
## `_update_motion_watch`) and back to ONBOARD_HEADLINE whenever the overlay is
## re-shown via `show_onboarding()` — the how-to body always stays underneath.
const ONBOARD_HEADLINE: String = "TAP TO START"
const RETRY_HEADLINE: String = "Motion unavailable — tap to retry"
const ONBOARD_BODY: String = "Step in place to walk\nTilt your phone to steer\nButtons bottom-right: Jump / Special / Switch"

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

## True once an enable attempt has already timed out with no data and the player has
## been offered one retry. It is what STOPS the retry cycle: the enable overlay is a
## full-rect MOUSE_FILTER_STOP button covering the whole control cluster, so on a
## device that will never deliver motion (iOS "Deny", the plain-http LAN host that
## ./serve.sh serves, or a touchscreen with no accelerometer) re-showing it after
## every timeout leaves the game permanently unplayable — the buttons underneath can
## never be reached. After the second failure we give up silently: buttons alone are
## a complete control scheme, and `show_onboarding()` is still the way back in.
var _motion_retry_offered: bool = false

## True while the UI is force-shown by the F6 debug key on a non-touch device, so a
## second F6 press toggles it back off. Independent of the auto (touch) visibility.
var _force_shown: bool = false

## Cached result of `MobileSensors.is_touch_session()` — the ONE canonical touch
## predicate (touchscreen probe, plus a web coarse-/not-fine-pointer fallback),
## shared with the player's mouse-capture guard so the two can never disagree.
## Whether a session is touch cannot change mid-run, and on a web desktop the
## fallback evaluates JS `matchMedia` probes — far too expensive to re-run every
## `_process` frame — so it is read ONCE in `_ready()` and every per-frame check
## consults this bool. (F6 debug-force-show is a SEPARATE OR in
## `_apply_platform_visibility()`, keeping this a pure "really a touch device?" flag.)
var _is_touch: bool = false

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
var _view_button: Button = null
var _fullscreen_button: Button = null
var _enable_overlay: Button = null

## Text children of the enable overlay. A Button cannot autowrap its own text, so
## the words live in Labels layered on top of it (mouse_filter IGNORE keeps them
## tap-transparent): `_enable_headline` carries the big "TAP TO START" (or the
## retry message), `_enable_body` the wrapping how-to lines beneath it.
var _enable_headline: Label = null
var _enable_body: Label = null

## Full-screen "Rotate your device" ColorRect, shown whenever a REAL touch session
## is held in portrait (viewport taller than wide). Drawn on top of everything and
## swallowing taps, because the 1920x1080 landscape layout is hopeless in portrait.
var _portrait_guard: ColorRect = null

## Full-screen "Paused — tap to resume" Button, shown while `get_tree().paused` on a
## real touch session (the focus-loss pause set by mobile_input.gd). Same tap-surface
## pattern as the enable overlay; its tap calls the driver's `resume_from_pause()`.
var _resume_overlay: Button = null


func _ready() -> void:
	# The resume overlay must stay tappable — and `_process` must keep running (it
	# flushes the synthetic-action release queue and drives this overlay's visibility)
	# — while `get_tree().paused` freezes everything else. SAFE while paused: all this
	# UI's outputs are one-shot synthetic InputEventActions the paused controller
	# simply won't consume until unpause, so nothing leaks into the frozen world.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Resolve the canonical touch predicate ONCE (see `_is_touch`); everything below
	# — initial visibility, content scale, and the per-frame overlay gates — reads
	# this cached bool instead of re-probing.
	_is_touch = MobileSensors.is_touch_session()

	# The root Control spans the whole screen (full-rect anchors set in the .tscn).
	# We keep its mouse_filter at PASS so it doesn't itself swallow touches meant for
	# the game world (the buttons below capture their own input via STOP), matching
	# the plan's "PASS on the root, buttons capture their own input" note.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Join the "touch_controls" group so other UI (the settings panel's "How to
	# play" button) can find us and call `show_onboarding()` — the same no-hard-refs
	# group-discovery convention as everything else in this project.
	add_to_group("touch_controls")

	# Find the motion driver by group — no hard reference, exactly like ability_hud
	# finds the player. May be null on a stripped build; every handler guards for it.
	_driver = get_tree().get_first_node_in_group("mobile_input")

	# Build the buttons + overlay in code so all their setup lives together.
	_build_ui()

	# Decide initial visibility from the platform. On a phone/tablet we show the UI
	# and the enable overlay; on desktop we hide everything and leave the driver idle
	# so keyboard+mouse play is untouched (the F6 key can still force-show for testing).
	_apply_platform_visibility()

	# Magnify the whole 2D/UI layer on real touch sessions (see TOUCH_CONTENT_SCALE
	# for the CSS-px math). Gate strictly on the canonical touch predicate — NOT on
	# `_force_shown` — so F6 debug on a desktop shows the buttons without rescaling
	# the desktop HUD, keeping desktop rendering byte-for-byte unchanged.
	if _is_touch:
		get_window().content_scale_factor = TOUCH_CONTENT_SCALE


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
	# FOCUS_NONE on EVERY button this HUD builds. `BaseButton` defaults to
	# FOCUS_ALL and keeps the focus after a tap, and a focused button is fired by
	# `ui_accept` — i.e. SPACE, which is also `jump`. So one tap here would make
	# every later jump ALSO flip the steer mode / fire the ability / switch
	# character, forever. This UI is touch-gated, but touch-gated is not
	# keyboard-free: `DisplayServer.is_touchscreen_available()` is true on a
	# touchscreen laptop or a Windows tablet that has a real keyboard attached
	# (and the F6 debug force-show puts it on any desktop).
	_steer_toggle.focus_mode = Control.FOCUS_NONE
	_steer_toggle.custom_minimum_size = Vector2(TOGGLE_WIDTH, TOGGLE_HEIGHT)
	_steer_toggle.add_theme_font_size_override("font_size", 30)
	# Same translucent family look as the action circles; half-height radius = pill.
	_apply_translucent_style(_steer_toggle, TOGGLE_HEIGHT / 2.0)
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

	# --- View toggle, LEFT of the steer toggle -----------------------------
	# Fires the `toggle_camera` action (the C key) through the same one-shot
	# `_fire_action` pipeline as the action cluster. The player controller POLLS
	# this action with `is_action_just_pressed`, which the parse_input_event press
	# satisfies for exactly one frame — no special casing needed. Same top strip,
	# same translucent family style, a square the height of the steer toggle,
	# mirrored on the toggle's left where the fullscreen button sits on its right.
	_view_button = Button.new()
	_view_button.name = "ViewButton"
	_view_button.focus_mode = Control.FOCUS_NONE  # see the steer toggle above
	_view_button.text = "View"
	_view_button.custom_minimum_size = Vector2(TOGGLE_HEIGHT, TOGGLE_HEIGHT)
	_view_button.add_theme_font_size_override("font_size", 24)
	# Touch-down like the action cluster — it fires the same kind of one-shot action.
	_view_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_apply_translucent_style(_view_button, TOGGLE_HEIGHT / 2.0)
	# Park it immediately to the LEFT of the centred steer toggle: same top-centre
	# anchoring, offsets pushed left past the toggle's half-width plus a margin
	# (the mirror image of the fullscreen button's placement below).
	_view_button.anchor_left = 0.5
	_view_button.anchor_right = 0.5
	_view_button.anchor_top = 0.0
	_view_button.anchor_bottom = 0.0
	_view_button.offset_right = -TOGGLE_WIDTH * 0.5 - BUTTON_MARGIN * 0.25
	_view_button.offset_left = -TOGGLE_WIDTH * 0.5 - BUTTON_MARGIN * 0.25 - TOGGLE_HEIGHT
	_view_button.offset_top = BUTTON_MARGIN
	_view_button.offset_bottom = BUTTON_MARGIN + TOGGLE_HEIGHT
	_view_button.pressed.connect(_on_view_pressed)
	add_child(_view_button)

	# --- Fullscreen toggle, right of the steer toggle (Android web only) ---
	# iOS Safari doesn't support requestFullscreen (the probe reports false there),
	# so this button only ever appears where it can actually work: Android/desktop
	# browsers with `document.fullscreenEnabled`. Same top strip, same translucent
	# family style, a square the height of the steer toggle. A Button.pressed
	# handler runs inside a user-gesture call stack — which is exactly what the
	# browser requires before it will grant an enter-fullscreen request.
	_fullscreen_button = Button.new()
	_fullscreen_button.name = "FullscreenButton"
	_fullscreen_button.focus_mode = Control.FOCUS_NONE  # see the steer toggle above
	_fullscreen_button.text = "⛶"
	_fullscreen_button.custom_minimum_size = Vector2(TOGGLE_HEIGHT, TOGGLE_HEIGHT)
	_fullscreen_button.add_theme_font_size_override("font_size", 30)
	_apply_translucent_style(_fullscreen_button, TOGGLE_HEIGHT / 2.0)
	# Park it immediately to the right of the centred steer toggle: same top-centre
	# anchoring, offsets pushed right past the toggle's half-width plus a margin.
	_fullscreen_button.anchor_left = 0.5
	_fullscreen_button.anchor_right = 0.5
	_fullscreen_button.anchor_top = 0.0
	_fullscreen_button.anchor_bottom = 0.0
	_fullscreen_button.offset_left = TOGGLE_WIDTH * 0.5 + BUTTON_MARGIN * 0.25
	_fullscreen_button.offset_right = TOGGLE_WIDTH * 0.5 + BUTTON_MARGIN * 0.25 + TOGGLE_HEIGHT
	_fullscreen_button.offset_top = BUTTON_MARGIN
	_fullscreen_button.offset_bottom = BUTTON_MARGIN + TOGGLE_HEIGHT
	# Visible only where fullscreen can actually be entered (Android web; false on
	# iOS Safari and on all native/desktop builds — see the probe's doc comment).
	_fullscreen_button.visible = MobileSensors.is_fullscreen_available()
	_fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	add_child(_fullscreen_button)

	# --- First-run enable overlay (full-rect) -----------------------------
	# A big, semi-transparent Button covering the whole screen (see
	# `_make_overlay_button` for the shared tap-surface pattern). We use a Button
	# (not a Panel) because it natively handles the tap and gives us the user-gesture
	# call stack iOS requires for DeviceMotionEvent.requestPermission(). It sits LAST
	# in the child order so it draws on top of the action buttons until dismissed.
	_enable_overlay = _make_overlay_button("EnableOverlay")
	_enable_overlay.pressed.connect(_on_enable_overlay_pressed)
	add_child(_enable_overlay)

	# The overlay's words: headline + how-to body, stacked in a full-rect VBox
	# centered vertically (the VBox lays the Labels out, hence fullrect = false).
	var overlay_text := VBoxContainer.new()
	overlay_text.name = "OnboardingText"
	overlay_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_text.anchor_right = 1.0
	overlay_text.anchor_bottom = 1.0
	overlay_text.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_text.add_theme_constant_override("separation", 28)
	_enable_overlay.add_child(overlay_text)

	# Headline — big and unmissable. Doubles as the error line on a retry (see
	# `_update_motion_watch`); the how-to body below never changes.
	_enable_headline = _make_overlay_label("OnboardHeadline", ONBOARD_HEADLINE, 40, false)
	overlay_text.add_child(_enable_headline)

	# How-to body — the three things a first-time phone player needs to know.
	_enable_body = _make_overlay_label("OnboardBody", ONBOARD_BODY, 28, false)
	overlay_text.add_child(_enable_body)

	# --- "Paused — tap to resume" overlay ----------------------------------
	# Shown while the tree is paused by the focus-loss handler in mobile_input.gd.
	# Same full-rect Button + centered Label pattern as the enable overlay (its tap
	# is also the WebAudio unlock gesture the browser wants after a backgrounded tab
	# returns). Child order matters: AFTER the enable overlay (so it could draw over
	# it, though `_process` never shows both at once) but BEFORE the portrait guard,
	# which must stay on top of everything.
	_resume_overlay = _make_overlay_button("ResumeOverlay")
	_resume_overlay.visible = false
	_resume_overlay.pressed.connect(_on_resume_overlay_pressed)
	_resume_overlay.add_child(_make_overlay_label("ResumeLabel", "Paused — tap to resume", 40, true))
	add_child(_resume_overlay)

	# --- Portrait "rotate your device" guard ------------------------------
	# Added LAST so it draws on top of everything (including the enable overlay):
	# the 1920x1080 landscape layout is unusable in portrait, so we black it out and
	# swallow all taps until the phone is rotated. Visibility is driven per-frame in
	# `_process` from the viewport aspect — `screen.orientation.lock` is deliberately
	# NOT used because in-browser iOS ignores it. Starts hidden; only ever shown on a
	# real touch session (never by the F6 desktop force-show). A ColorRect (not a
	# Button): it swallows taps via MOUSE_FILTER_STOP but nothing should fire on tap.
	_portrait_guard = ColorRect.new()
	_portrait_guard.name = "PortraitGuard"
	_portrait_guard.color = Color(0.0, 0.0, 0.0, 0.85)
	_portrait_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait_guard.anchor_right = 1.0
	_portrait_guard.anchor_bottom = 1.0
	_portrait_guard.visible = false
	_portrait_guard.add_child(_make_overlay_label("RotateLabel", "Rotate your device\n(landscape only)", 40, true))
	add_child(_portrait_guard)


## Create one big square action button with the given visible `label`, an explicit
## PascalCase `node_name` (so the scene tree reads cleanly instead of deriving a
## messy name like "SPECIAL_(F)" from the label), and a stack `slot`. Slot 1 is the
## lowest (bottom-most) button; higher slots stack upward. Anchored to the
## bottom-right corner so the cluster stays put on any screen size.
func _make_action_button(label: String, node_name: String, slot: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	# see the steer toggle in `_build_ui` — Space is `ui_accept` AND `jump`, so a
	# focused Jump/Special/Switch button re-fires on every jump for the rest of
	# the session. These three are the sharpest case: they ARE gameplay actions.
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 26)
	button.custom_minimum_size = Vector2(ACTION_BUTTON_SIZE, ACTION_BUTTON_SIZE)
	# Fire on touch-DOWN, not on release (Godot's default for a Button). These are
	# gameplay actions against a 5.5 m/s chaser: release mode costs the whole tap
	# duration in latency, and a thumb that slides off the circle mid-tap — routine
	# while the player is physically stepping in place — cancels the press entirely.
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	# Translucent dark circle instead of the opaque default theme panel, so the
	# buttons occlude far less of the 3D world behind them. A corner radius of half
	# the side length turns the square into a circle; the pressed variant is a bit
	# brighter so a registered tap reads visually.
	_apply_translucent_style(button, ACTION_BUTTON_SIZE / 2.0)
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


## Give a button the shared translucent rounded look (dark glassy fill, white text)
## used by the whole touch UI, so the action circles and the top-strip toggle read
## as one family. `corner_radius` = half the button's height makes a pill/circle.
## The "pressed" variant is the same shape with a brighter fill (alpha 0.55 → 0.75)
## so a registered tap is visible even under a thumb.
func _apply_translucent_style(button: Button, corner_radius: float) -> void:
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.10, 0.12, 0.16, 0.55)
	normal_style.corner_radius_top_left = int(corner_radius)
	normal_style.corner_radius_top_right = int(corner_radius)
	normal_style.corner_radius_bottom_left = int(corner_radius)
	normal_style.corner_radius_bottom_right = int(corner_radius)
	var pressed_style: StyleBoxFlat = normal_style.duplicate()
	pressed_style.bg_color = Color(0.10, 0.12, 0.16, 0.75)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", normal_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


## Build one full-screen tap-surface Button — the shared overlay pattern (enable
## overlay, resume overlay). The Button is purely the whole-screen tap target plus
## a translucent dark fill (so the world stays faintly visible behind the prompt);
## it carries NO text of its own because a Button cannot autowrap — the words live
## in `_make_overlay_label` children layered on top.
func _make_overlay_button(node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE  # see the steer toggle in `_build_ui`
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	# Full-rect: cover the whole Control (anchors_preset 15 equivalent).
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	return button


## Build one overlay text Label: centred, autowrapping (so it survives a narrow
## phone screen), MOUSE_FILTER_IGNORE so taps fall straight through to the surface
## underneath. `fullrect = true` centres it over the whole overlay; `false` leaves
## layout to a container parent (the enable overlay's VBox stacks its two Labels).
func _make_overlay_label(node_name: String, text: String, font_size: int, fullrect: bool) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fullrect:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
	return label


# ============================================================================
# PLATFORM GATING / VISIBILITY
# ============================================================================

## Show the whole UI only on a touch/mobile device (or when force-shown via F6);
## otherwise hide it entirely so desktop keyboard+mouse play is untouched. Also
## drives whether the enable overlay is presented (only when actually shown and not
## yet enabled).
func _apply_platform_visibility() -> void:
	# Visible if the platform is touch OR a developer force-showed it for testing.
	visible = _is_touch or _force_shown

	# The enable overlay only makes sense while the UI is up and motion hasn't been
	# enabled yet. If we're hidden, or already enabled, keep it down.
	_enable_overlay.visible = visible and not _motion_enabled


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
	# FROZEN while the tree is paused: a backgrounded/blurred tab delivers no sensor
	# events, so counting the grace window through a focus-loss pause would always
	# time out and spuriously flip the overlay to "Motion unavailable — tap to retry"
	# (and thereby suppress the resume overlay). Only foreground, unpaused time
	# counts toward the timeout; the watch resumes where it left off after the tap.
	if not get_tree().paused:
		_update_motion_watch(delta)

	# --- 3. Portrait guard -------------------------------------------------
	# Drive the "rotate your device" screen straight off the viewport aspect each
	# frame (cheap — one Vector2 compare on the cached touch bool). Gated on the REAL
	# touch predicate, not on `visible`, so the F6 desktop force-show can never
	# trigger it; a shrunk desktop/editor window is not a phone held wrong.
	if _is_touch:
		var view_size: Vector2 = get_viewport().get_visible_rect().size
		var portrait: bool = view_size.y > view_size.x
		# Entering portrait also PAUSES, via the same driver path as focus loss.
		# Without this the guard only blacks out the screen while the world keeps
		# running — and a portrait-held phone sits ~90° of roll from the landscape
		# neutral, so tilt steering saturates and the hero spins/walks blind.
		# After rotating back the guard hides and the standard "tap to resume"
		# overlay (which re-enables + recalibrates motion) takes over.
		# Gated on the TREE's paused state, not on the guard's visibility: with
		# somebody else's pause already up (the MP panel), `pause_game()` early-
		# returns while `visible` latches true, and when that other pause is
		# released nothing ever re-pauses — the game would run in portrait behind
		# an opaque guard with tilt steering saturated ~90° off neutral, and only
		# rotating out and back would recover. `pause_game()` is itself idempotent.
		if portrait and not get_tree().paused:
			var driver: Node = _ensure_driver()
			if driver != null:
				driver.pause_game()
		_portrait_guard.visible = portrait
	else:
		_portrait_guard.visible = false

	# --- 4. Pause / resume overlay -----------------------------------------
	# Mirror the tree's paused state (set by mobile_input.gd on focus loss) into the
	# resume overlay — but never over the initial enable overlay: if the tab was
	# backgrounded before first enable, the enable overlay stays the one prompt (its
	# tap enables motion, then THIS overlay appears for the unpause tap). Gated on
	# the real touch predicate so a desktop pause (from any future source) never
	# shows a phone overlay — desktop stays byte-for-byte unchanged.
	# `paused_by_driver` narrows "the tree is paused" to "WE paused it": the MP
	# panel pauses as well, and this overlay is full-rect — it would cover that
	# panel and its tap would unpause the game the panel deliberately froze.
	var driver: Node = _ensure_driver()
	var ours: bool = driver != null and bool(driver.get("paused_by_driver"))
	_resume_overlay.visible = _is_touch and get_tree().paused and ours and not _enable_overlay.visible


## True while one of the three full-rect overlays owns the screen (first-run enable,
## focus-loss resume, portrait guard). All three are meant to be EXCLUSIVE — they
## swallow every tap — but they can only swallow taps that reach them, and any HUD
## sibling declared after TouchControls draws on top and wins hit-testing. So a
## sibling with its own always-on button (the tuning gear) asks this and hides while
## it is true. Getting it wrong is not cosmetic: a tap stolen from the enable overlay
## is the ONE user gesture iOS grants DeviceMotionEvent.requestPermission() and the
## browser grants WebAudio, so motion AND all audio stay dead for the session.
func has_modal() -> bool:
	return _enable_overlay.visible or _resume_overlay.visible or _portrait_guard.visible


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
		if _motion_retry_offered:
			# Second failure: this device is not going to deliver motion. Stand down
			# for good rather than parking a full-rect overlay over the buttons every
			# 3.5 s forever (see _motion_retry_offered) — the buttons are playable on
			# their own, and show_onboarding() can still bring the overlay back.
			_enable_overlay.visible = false
			return
		_motion_retry_offered = true
		# PAUSE alongside raising it, exactly like the portrait guard above. This
		# overlay is a full-rect Button, so it swallows every tap — Jump, Special,
		# Switch and View all go dead while it is up. Over a LIVE world that means the
		# player stands there being chased with no controls until they tap. The tap
		# itself unpauses (see _on_enable_overlay_pressed). `driver` is the same handle
		# the receiving-check above already resolved.
		if driver != null:
			driver.pause_game()
		# Swap only the HEADLINE to the retry message — the how-to body stays
		# visible underneath, so a retrying player keeps the instructions.
		_enable_headline.text = RETRY_HEADLINE
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


## View button → the polled `toggle_camera` action (C key equivalent): flips the
## player between 3rd-person and first-person view.
func _on_view_pressed() -> void:
	_fire_action("toggle_camera")


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


## Fullscreen button → toggle the browser between fullscreen and windowed via
## DisplayServer (Godot's web port routes this to requestFullscreen/exitFullscreen).
## Running inside the Button's pressed signal keeps us in the user-gesture call
## stack the browser demands for ENTERING fullscreen; leaving needs no gesture.
func _on_fullscreen_pressed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


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

	if _motion_enabled:
		# Motion is already up and running — the overlay was re-shown as a help
		# screen via `show_onboarding()`. A tap just dismisses it; do NOT re-request
		# permission, re-enable the driver, or restart the motion watch.
		_enable_overlay.visible = false
		return

	if _ensure_driver() == null:
		# No driver to talk to: do NOT latch enabled or hide the overlay. The overlay
		# stays visible and tappable so the player can retry (e.g. if the node appears
		# later), instead of being left with a hidden overlay and no controls at all.
		# Re-label the headline so the player understands a retry is possible (the
		# how-to body stays put beneath it).
		_enable_headline.text = RETRY_HEADLINE
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
	_enable_overlay.visible = false

	# This tap is also the unpause. Two ways the tree can be paused under a visible
	# enable overlay: the retry prompt pauses when it raises itself (a tap-swallowing
	# overlay must not sit over live play), and a focus-loss pause before the first
	# enable is suppressed from showing the resume overlay while we are visible. Both
	# are cleared here, so a single tap always returns the player to a running game.
	# Ownership-gated exactly like the resume overlay above: a tree pause is no
	# longer ours alone (the MP panel pauses too), and unpausing somebody else's
	# pause would leave the game live and driveable under their still-open panel.
	if get_tree().paused and bool(_driver.get("paused_by_driver")):
		_driver.resume_from_pause()

## Resume overlay tap → unfreeze the game. Routed through the driver's
## `resume_from_pause()` so the driver can also restore its pre-pause active state
## (it remembers whether motion was running when focus was lost). The no-driver
## `else` is unreachable today (only mobile_input.gd ever pauses the tree, so a
## paused tree implies the driver exists) — kept as a two-line anti-softlock belt
## so the player is never stuck on a frozen screen if a future pause source appears.
func _on_resume_overlay_pressed() -> void:
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.resume_from_pause()
	else:
		get_tree().paused = false


# ============================================================================
# PUBLIC API (called by other UI via the "touch_controls" group)
# ============================================================================

## Re-show the onboarding overlay as a HELP SCREEN, with the default how-to text.
## Called by the settings panel's "How to play" button (found via the group). This
## deliberately does NOT reset `_motion_enabled` or touch the driver: if motion is
## already running, the tap handler sees `_motion_enabled` and simply hides the
## overlay again; if motion was never enabled, the overlay behaves exactly like the
## first run (tap = permission gesture + enable + watch).
func show_onboarding() -> void:
	_enable_headline.text = ONBOARD_HEADLINE
	_enable_overlay.visible = true
