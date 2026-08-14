extends Control
## On-device live tuning / diagnostics panel for the mobile motion controls.
##
## This is the player-facing **tuning instrument** for the phone controls. The motion
## driver (`mobile_input.gd`) turns the phone's sensors into movement, but the right
## sensitivity for a *footstep spike* or a *comfortable lean* can only be found on a
## real device — and the build environment had no hardware (see the completed plan's
## Task 6 note). So instead of guessing the `STEP_*`/`STEER_*` numbers in code, this
## panel lets the player dial them in live ON THE PHONE and watch a real-time read-out
## of the sensor signals, which is also how they diagnose "the controls feel dead":
##
##   * A **live diagnostics** block at the top shows whether sensor data is flowing,
##     where it's coming from, the current vs. peak step-acceleration (THE number to
##     set the step threshold by), the resulting walk energy + step count, and the
##     current tilt/yaw. If it reads "NO DATA" the player instantly knows the problem
##     is permission/sensors, not tuning.
##   * Each adjustable parameter gets a big **−  value  +  stepper row** (a "spinner"),
##     not a slider: tiny slider grabs are unusable on a small phone, while large +/−
##     buttons with the exact number between them are easy to thumb and read. Every step
##     writes straight back to the driver via `set_tuning(key, value)`, which also
##     persists to `user://mobile_tuning.cfg` so the tuning survives a page reload
##     (IndexedDB on web).
##   * An **Invert steering** toggle fixes a phone whose roll/yaw sign is reversed.
##   * **Recalibrate** re-zeros the neutral pose from the current hold; **Reset to
##     defaults** restores the shipped values.
##
## ----------------------------------------------------------------------------
## No hard references — found by group, like the rest of the HUD
## ----------------------------------------------------------------------------
## Exactly like `touch_controls.gd` and `ability_hud.gd`, this panel holds NO hard
## reference to the driver. It locates it through the `"mobile_input"` group with
## `get_tree().get_first_node_in_group(...)` and talks only to that driver's public
## API (`get_tuning()`, `set_tuning()`, `get_diagnostics()`, `recalibrate()`,
## `reset_tuning_to_defaults()`). The whole UI is built in code in `_ready()`, matching
## `touch_controls.gd`'s style, so a single Control node with this script under HUD is
## all the scene needs.
##
## ----------------------------------------------------------------------------
## Mobile-only gating (desktop stays byte-for-byte unchanged)
## ----------------------------------------------------------------------------
## Per the project's platform discipline, the gear button and panel appear ONLY on a
## touch session (`MobileSensors.is_touch_session()` — the SAME canonical rule the
## touch UI and the player's mouse guard share) or when force-shown by the debug key.
## On desktop the panel is hidden and inert, so keyboard+mouse play is untouched.

# ============================================================================
# CONSTANTS — layout / tuning
# ============================================================================

## Size of the always-visible gear/"Tune" button. Parked BOTTOM-LEFT, the free
## corner of the release HUD: the steer toggle owns top-centre, the action cluster
## bottom-right, the lives hearts + perf overlay top-left and the coin/ability HUD
## top-right. (The debug-only MotionDebug readout also sits bottom-left, so the
## gear overlaps it in debug builds — acceptable: the label ignores mouse input so
## the gear stays tappable, and release/web builds start with it hidden.) A
## comfortably large touch target on a phone.
const GEAR_WIDTH: float = 110.0
const GEAR_HEIGHT: float = 60.0

## Margin (px) from the screen edge for the gear button and the panel.
const EDGE_MARGIN: float = 16.0

## The open panel's size. Wide enough for the −/value/+ steppers and the diagnostics
## text to read large; it is scrollable (a ScrollContainer) so a short phone screen can
## still reach every row.
const PANEL_WIDTH: float = 380.0
const PANEL_HEIGHT: float = 580.0

## Side length (px) of the big −/+ stepper buttons. Generous so they are easy to thumb
## on a small screen (well past the ~44-48 pt minimum touch target).
const STEP_BUTTON_SIZE: float = 60.0

## Minimum height of the secondary action buttons (Invert/Recalibrate/Reset/Close), so
## they stay finger-friendly.
const ACTION_ROW_HEIGHT: float = 60.0

## Developer force-show key. F3 = perf overlay, F4 = motion readout, F5 = mobile_input
## force-enable, F6 = touch UI force-show; F7 is the next free function key and toggles
## THIS panel's gear visible so a developer can exercise the tuner in the editor on a
## desktop with no touchscreen. Debug-only, outside the project input map (like F3-F6),
## and never affects a released desktop build (real desktop play has no touchscreen).
const FORCE_SHOW_KEYCODE: Key = KEY_F7

## The adjustable parameters, in display order. Each entry is
## [key, label, min, max, step] — the key MUST match what `mobile_input.get_tuning()`
## returns and `set_tuning()` accepts, the rest drive the stepper. Keeping the spec in
## one array means adding a knob later is a one-line change here.
const TUNING_SPECS: Array = [
	["step_accel_threshold", "Step threshold", 0.2, 6.0, 0.1],
	["step_walk_per_step", "Step power", 0.1, 2.0, 0.05],
	["step_walk_decay", "Walk decay", 0.3, 4.0, 0.1],
	["step_min_interval", "Step min interval", 0.10, 0.60, 0.02],
	["steer_deadzone_deg", "Steer deadzone", 0.0, 20.0, 1.0],
	["steer_full_deg", "Steer full angle", 8.0, 45.0, 1.0],
]

# ============================================================================
# STATE
# ============================================================================

## Cached driver reference, re-fetched via the group if it ever goes away (mirrors
## `touch_controls._ensure_driver()`). May be null on a build with no MobileInput node.
var _driver: Node = null

## True while the panel body is open. The gear toggles it; it starts closed so the
## gear alone is on screen until the player taps it.
var _panel_open: bool = false

## True while force-shown by F7 on a non-touch device, so a second F7 toggles it off.
var _force_shown: bool = false

# --- Child node references (built in _ready, not from a .tscn) --------------

## The always-visible gear/"Tune" toggle button.
var _gear_button: Button = null

## The collapsible panel body (a PanelContainer) holding diagnostics + steppers.
var _panel_body: PanelContainer = null

## The multi-line diagnostics label, refreshed every `_process` frame while open.
var _diag_label: Label = null

## Current value of each tunable param, keyed by param key. The steppers mutate this and
## push it to the driver; the displays render it. Seeded from `get_tuning()`.
var _step_values: Dictionary = {}

## The big numeric value labels shown between the − and + buttons, keyed by param key,
## so a step (or a reset) can refresh just that row's number.
var _value_displays: Dictionary = {}

## Per-key [min, max, step] pulled from TUNING_SPECS, so the stepper handler can clamp
## and snap without re-walking the spec array.
var _spec_by_key: Dictionary = {}

## The invert-steering checkbox, refreshed by "Reset to defaults".
var _invert_check: CheckButton = null

## Guard flag: true while we programmatically set the checkbox value (seed or reset), so
## its `toggled` handler doesn't echo straight back into the driver and re-save.
var _suppress_signals: bool = false


func _ready() -> void:
	# This root spans the whole screen, but it must NOT be a hit-test target itself:
	# it sits ABOVE the TouchControls sibling in the HUD, and Godot's MOUSE_FILTER_PASS
	# only re-propagates to a control's *ancestors*, never to sibling controls drawn
	# beneath it. A full-rect PASS root therefore swallows every tap before it can reach
	# the "tap to enable" overlay (and the action buttons) inside TouchControls. IGNORE
	# makes the empty areas of this root transparent to input, so taps fall through to
	# the sibling below, while the gear button and the open panel body — which carry
	# their own STOP filter (Button/PanelContainer default) — still receive their taps.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Find the motion driver by group (no hard reference). May be null on a stripped
	# build; every handler guards for it via `_ensure_driver()`.
	_driver = get_tree().get_first_node_in_group("mobile_input")

	# Build the gear + collapsible panel in code so all the wiring lives here.
	_build_ui()

	# Seed the steppers/checkbox from the driver's current (possibly persisted) tuning.
	_seed_controls_from_driver()

	# Decide initial visibility from the platform: shown on touch / when force-shown,
	# hidden + inert on desktop so keyboard+mouse play is untouched.
	_apply_platform_visibility()


func _input(event: InputEvent) -> void:
	# Developer force-show toggle (F7). Raw key, not a named action — a debug aid that
	# intentionally sits outside the project input map like F3-F6. Lets us see the tuner
	# in the editor on a desktop with no touchscreen; a release desktop build has no
	# touchscreen so it still never auto-shows.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == FORCE_SHOW_KEYCODE:
			_force_shown = not _force_shown
			_apply_platform_visibility()


func _process(_delta: float) -> void:
	# Only do work while the panel is actually open and visible — the diagnostics read
	# is cheap but pointless when nobody can see it, and on desktop the panel is hidden
	# so this early-returns immediately.
	if not visible or not _panel_open:
		return
	_update_diagnostics()


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

## Build the gear button and the collapsible panel body and wire every signal. Called
## once from `_ready()`. Anchored so it repositions correctly on any screen size.
func _build_ui() -> void:
	# --- Gear / "Tune" toggle, BOTTOM-LEFT --------------------------------
	# Bottom-left is the free corner of the release HUD: lives hearts + perf overlay
	# own the top-left column, the coin counter / ability dial the top-right, the
	# steer toggle the top-centre, and the Jump/Special/Switch cluster the bottom-
	# right. (Debug builds also draw the MotionDebug readout here — a debug-only
	# overlap; see the GEAR_WIDTH doc comment.) Anchored to the bottom edge
	# (anchor y = 1) so it hugs the corner on any screen.
	_gear_button = Button.new()
	_gear_button.name = "TuneButton"
	_gear_button.text = "⚙ Tune"  # ⚙ gear glyph + label
	_gear_button.add_theme_font_size_override("font_size", 26)
	_gear_button.custom_minimum_size = Vector2(GEAR_WIDTH, GEAR_HEIGHT)
	_gear_button.anchor_left = 0.0
	_gear_button.anchor_right = 0.0
	_gear_button.anchor_top = 1.0
	_gear_button.anchor_bottom = 1.0
	_gear_button.offset_left = EDGE_MARGIN
	_gear_button.offset_right = EDGE_MARGIN + GEAR_WIDTH
	# Offsets are measured from the BOTTOM edge (anchor 1), so they are negative.
	_gear_button.offset_top = -EDGE_MARGIN - GEAR_HEIGHT
	_gear_button.offset_bottom = -EDGE_MARGIN
	_gear_button.pressed.connect(_on_gear_pressed)
	add_child(_gear_button)

	# --- Panel body (collapsible), anchored bottom-left ABOVE the gear ----
	# A PanelContainer gives a translucent rounded background; inside it a
	# ScrollContainer + VBox holds the diagnostics label and all the rows, so a short
	# screen can scroll. It starts hidden (collapsed) — the gear opens it. It opens
	# UPWARD from just above the gear; `_set_panel_open` clamps its height to the
	# visible viewport on open (a phone's scaled viewport is shorter than the full
	# PANEL_HEIGHT stack), and the inner ScrollContainer then reaches every row.
	_panel_body = PanelContainer.new()
	_panel_body.name = "TunePanel"
	_panel_body.anchor_left = 0.0
	_panel_body.anchor_right = 0.0
	_panel_body.anchor_top = 1.0
	_panel_body.anchor_bottom = 1.0
	_panel_body.offset_left = EDGE_MARGIN
	_panel_body.offset_right = EDGE_MARGIN + PANEL_WIDTH
	# Sit the panel just above the gear button (offsets from the bottom edge).
	_panel_body.offset_bottom = -EDGE_MARGIN - GEAR_HEIGHT - 8.0
	_panel_body.offset_top = _panel_body.offset_bottom - PANEL_HEIGHT
	# Translucent dark background so the world stays faintly visible behind the panel.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.09, 0.9)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	_panel_body.add_theme_stylebox_override("panel", panel_style)
	_panel_body.visible = false
	add_child(_panel_body)

	# Scroll + vertical stack inside the panel.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_body.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "Body"
	vbox.add_theme_constant_override("separation", 10)
	# Make the VBox fill the scroll width so rows stretch the full panel width.
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0.0)
	scroll.add_child(vbox)

	# --- Diagnostics read-out (top of the panel) -------------------------
	var diag_title := Label.new()
	diag_title.text = "DIAGNOSTICS"
	diag_title.add_theme_font_size_override("font_size", 18)
	diag_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(diag_title)

	_diag_label = Label.new()
	_diag_label.name = "Diagnostics"
	# Big, because reading the live sensor numbers (especially "peak") on a small phone
	# is the whole point of this block.
	_diag_label.add_theme_font_size_override("font_size", 24)
	_diag_label.text = "Sensor: ..."
	vbox.add_child(_diag_label)

	# A thin separator before the steppers.
	vbox.add_child(HSeparator.new())

	var tune_title := Label.new()
	tune_title.text = "TUNING  (tap −/+)"
	tune_title.add_theme_font_size_override("font_size", 18)
	tune_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(tune_title)

	# --- One −/value/+ stepper row per adjustable param ------------------
	for spec in TUNING_SPECS:
		_build_stepper_row(vbox, spec)

	# --- Invert steering checkbox ----------------------------------------
	_invert_check = CheckButton.new()
	_invert_check.name = "InvertSteering"
	_invert_check.text = "Invert steering"
	_invert_check.add_theme_font_size_override("font_size", 22)
	_invert_check.custom_minimum_size = Vector2(0.0, ACTION_ROW_HEIGHT)
	_invert_check.toggled.connect(_on_invert_toggled)
	vbox.add_child(_invert_check)

	vbox.add_child(HSeparator.new())

	# --- Action buttons: How to play / Recalibrate / Reset / Close -------
	vbox.add_child(_make_action_button("How to play", _on_how_to_play_pressed))
	vbox.add_child(_make_action_button("Recalibrate (re-zero)", _on_recalibrate_pressed))
	vbox.add_child(_make_action_button("Reset to defaults", _on_reset_pressed))
	vbox.add_child(_make_action_button("Close", _on_close_pressed))


## Build one full-width secondary action button (Recalibrate/Reset/Close) with a big
## font and finger-friendly height, wired to `handler`.
func _make_action_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 22)
	button.custom_minimum_size = Vector2(0.0, ACTION_ROW_HEIGHT)
	button.pressed.connect(handler)
	return button


## Build one "spinner" row [key, label, min, max, step] and append it to `parent`.
## Layout: a name label on its own line, then a [ − ] [ big value ] [ + ] horizontal
## stepper. The big buttons + large centred number replace the old hard-to-grab slider.
func _build_stepper_row(parent: VBoxContainer, spec: Array) -> void:
	var key: String = spec[0]
	var label_text: String = spec[1]
	var min_val: float = spec[2]
	var max_val: float = spec[3]
	var step_val: float = spec[4]
	_spec_by_key[key] = [min_val, max_val, step_val]

	var row := VBoxContainer.new()
	row.name = key
	row.add_theme_constant_override("separation", 2)

	# Name label (its own line so a long name never squeezes the stepper).
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.text = label_text
	row.add_child(name_label)

	# The −  value  +  stepper line.
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 10)

	var minus := _make_step_button("−", key, -1.0)
	stepper.add_child(minus)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 26)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text = "..."
	stepper.add_child(value_label)
	_value_displays[key] = value_label

	var plus := _make_step_button("+", key, 1.0)
	stepper.add_child(plus)

	row.add_child(stepper)
	parent.add_child(row)


## Build one big square −/+ button bound to a param key and a direction (-1 or +1).
func _make_step_button(text: String, key: String, direction: float) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 34)
	button.custom_minimum_size = Vector2(STEP_BUTTON_SIZE, STEP_BUTTON_SIZE)
	button.pressed.connect(_on_step_pressed.bind(key, direction))
	return button


# ============================================================================
# DRIVER LOOKUP (single mechanism, mirrors touch_controls._ensure_driver)
# ============================================================================

## Refresh and return the cached motion driver, re-resolving it via the group if it was
## never found or has since been freed. Returns null on a build with no MobileInput
## node, so callers must still null-check.
func _ensure_driver() -> Node:
	if _driver == null or not is_instance_valid(_driver):
		_driver = get_tree().get_first_node_in_group("mobile_input")
	return _driver


# ============================================================================
# PLATFORM GATING / VISIBILITY
# ============================================================================

## Show the gear (and, if open, the panel) only on a touch session or when force-shown
## via F7; otherwise hide everything so desktop keyboard+mouse play is untouched. This
## reuses the SAME canonical detection as touch_controls (`MobileSensors.is_touch_session()`).
func _apply_platform_visibility() -> void:
	var on_touch: bool = MobileSensors.is_touch_session()
	visible = on_touch or _force_shown
	# When hidden, also collapse the panel so re-showing starts from the gear alone.
	if not visible:
		_panel_open = false
		if _panel_body != null:
			_panel_body.visible = false


# ============================================================================
# GEAR / PANEL OPEN-CLOSE
# ============================================================================

## Toggle the panel open/closed. Tapping the gear is the player's way in and out.
func _on_gear_pressed() -> void:
	_set_panel_open(not _panel_open)


## Close button inside the panel — same effect as tapping the gear again.
func _on_close_pressed() -> void:
	_set_panel_open(false)


## Open or collapse the panel body and refresh its contents on open so the steppers and
## diagnostics reflect the latest driver state the moment it appears.
func _set_panel_open(open: bool) -> void:
	_panel_open = open
	if _panel_body != null:
		_panel_body.visible = open
	if open:
		# Clamp the panel to the space actually above the gear. With the touch UI's
		# content_scale_factor (1.8) magnifying the whole 2D layer, the visible
		# design viewport on a phone is only ~600 px tall — shorter than the full
		# gear + gap + PANEL_HEIGHT stack (~664 px) — and a PanelContainer poking
		# past the screen top is unreachable even through its inner ScrollContainer
		# (a ScrollContainer scrolls its CONTENT, not its own off-screen frame).
		# Shrinking the panel keeps its whole frame on-screen and lets the
		# ScrollContainer genuinely reach every row. Recomputed on every open so it
		# tracks the current viewport (e.g. after an orientation change).
		var view_height: float = get_viewport().get_visible_rect().size.y
		_panel_body.offset_top = maxf(_panel_body.offset_bottom - PANEL_HEIGHT, -view_height + EDGE_MARGIN)
		# Re-seed in case the driver was found late or tuning changed elsewhere.
		_seed_controls_from_driver()
		_update_diagnostics()


# ============================================================================
# SEEDING / REFRESH
# ============================================================================

## Pull the driver's current tuning into `_step_values` + the displays and the invert
## checkbox. Used on `_ready()`, on open, and after a reset. The checkbox set is wrapped
## in `_suppress_signals` so seeding it doesn't echo back into the driver. Safe when the
## driver is missing (controls just keep defaults).
func _seed_controls_from_driver() -> void:
	var driver: Node = _ensure_driver()
	if driver == null:
		return
	var tuning: Dictionary = driver.get_tuning()
	for spec in TUNING_SPECS:
		var key: String = spec[0]
		if tuning.has(key):
			_step_values[key] = float(tuning[key])
			_refresh_value_display(key)
	if _invert_check != null and tuning.has("invert_steering"):
		_suppress_signals = true
		_invert_check.button_pressed = bool(tuning["invert_steering"])
		_suppress_signals = false


## Rebuild a stepper row's value label from `_step_values`, formatted with a sensible
## number of decimals: integer for whole-number steps (degrees), two decimals otherwise.
func _refresh_value_display(key: String) -> void:
	if not _value_displays.has(key) or not _step_values.has(key):
		return
	var value: float = _step_values[key]
	var step_val: float = _spec_by_key[key][2]
	var label: Label = _value_displays[key]
	if step_val >= 1.0:
		label.text = "%d" % int(round(value))
	else:
		label.text = "%.2f" % value


## Refresh the live diagnostics block from the driver. Called every `_process` frame
## while the panel is open. Reads the source-agnostic `get_diagnostics()` dictionary so
## this UI never touches the sensor directly.
func _update_diagnostics() -> void:
	if _diag_label == null:
		return
	var driver: Node = _ensure_driver()
	if driver == null:
		_diag_label.text = "Sensor: (no driver)"
		return
	var d: Dictionary = driver.get_diagnostics()
	var has_data: bool = bool(d.get("has_data", false))
	var source: String = String(d.get("source", "none"))
	# Build the multi-line read-out. The "peak" line is the key one for setting the
	# step threshold (set it just under the peak you see while walking in place).
	var sensor_line: String
	if has_data:
		sensor_line = "Sensor: LIVE (%s)" % source
	else:
		sensor_line = "Sensor: NO DATA"
	_diag_label.text = "\n".join([
		sensor_line,
		"accel now: %.2f   peak: %.2f" % [float(d.get("accel_mag", 0.0)), float(d.get("accel_peak", 0.0))],
		"energy: %.2f   steps: %d" % [float(d.get("walk_energy", 0.0)), int(d.get("step_count", 0))],
		"tilt: %d°   yaw: %d°" % [int(round(float(d.get("tilt_deg", 0.0)))), int(round(float(d.get("yaw_deg", 0.0))))],
	])


# ============================================================================
# CONTROL HANDLERS → driver.set_tuning / recalibrate / reset
# ============================================================================

## A − or + stepper was tapped: nudge the value by one step (clamped + snapped to the
## step grid), refresh the display, and push it to the driver (which clamps + persists).
func _on_step_pressed(key: String, direction: float) -> void:
	if not _spec_by_key.has(key):
		return
	var spec: Array = _spec_by_key[key]
	var min_val: float = spec[0]
	var max_val: float = spec[1]
	var step_val: float = spec[2]
	var current: float = float(_step_values.get(key, min_val))
	# Snap to the step grid so repeated taps don't accumulate float drift.
	var next_val: float = clampf(snappedf(current + direction * step_val, step_val), min_val, max_val)
	_step_values[key] = next_val
	_refresh_value_display(key)
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.set_tuning(key, next_val)


## The invert-steering checkbox toggled: push it to the driver (persisted). Ignored
## while seeding/resetting so the seed doesn't re-save.
func _on_invert_toggled(pressed: bool) -> void:
	if _suppress_signals:
		return
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.set_tuning("invert_steering", pressed)


## "How to play" button: re-show the touch UI's onboarding how-to overlay, then close
## this panel so the help screen isn't buried under it. The touch UI is found through
## the "touch_controls" group (the same no-hard-refs convention as the driver lookup);
## null-safe so a build without TouchControls just closes the panel.
func _on_how_to_play_pressed() -> void:
	var touch_ui: Node = get_tree().get_first_node_in_group("touch_controls")
	if touch_ui != null:
		touch_ui.show_onboarding()
	_set_panel_open(false)


## Recalibrate button: re-zero the neutral pose from however the player is holding the
## phone right now. Backs a player diagnosing drifting/unresponsive steering.
func _on_recalibrate_pressed() -> void:
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.recalibrate()


## Reset-to-defaults button: tell the driver to restore + persist the shipped values,
## then re-seed the controls so the steppers/checkbox snap to the new (default) state.
func _on_reset_pressed() -> void:
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.reset_tuning_to_defaults()
	_seed_controls_from_driver()
