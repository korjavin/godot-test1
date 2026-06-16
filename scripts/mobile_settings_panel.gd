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
##   * One **slider per adjustable parameter** writes straight back to the driver via
##     `set_tuning(key, value)`, which also persists to `user://mobile_tuning.cfg` so
##     the tuning survives a page reload (IndexedDB on web).
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

## Size of the always-visible gear/"Tune" button. Parked top-LEFT, clear of the steer
## toggle (top-centre), the action cluster (bottom-right) and the coin/lives HUD
## corners — a comfortably large touch target on a phone.
const GEAR_WIDTH: float = 92.0
const GEAR_HEIGHT: float = 56.0

## Margin (px) from the screen edge for the gear button and the panel.
const EDGE_MARGIN: float = 16.0

## The open panel's size. Tall and fairly wide so the sliders are easy to grab; it is
## scrollable (a ScrollContainer) in case a short phone in landscape can't show it all.
const PANEL_WIDTH: float = 360.0
const PANEL_HEIGHT: float = 560.0

## Minimum height of each slider row, so the slider grab area is finger-friendly. Phone
## touch targets want ~44-48 pt minimum; 56 px clears that comfortably.
const ROW_HEIGHT: float = 56.0

## Developer force-show key. F3 = perf overlay, F4 = motion readout, F5 = mobile_input
## force-enable, F6 = touch UI force-show; F7 is the next free function key and toggles
## THIS panel's gear visible so a developer can exercise the tuner in the editor on a
## desktop with no touchscreen. Debug-only, outside the project input map (like F3-F6),
## and never affects a released desktop build (real desktop play has no touchscreen).
const FORCE_SHOW_KEYCODE: Key = KEY_F7

## The adjustable parameters, in display order. Each entry is
## [key, label, min, max, step] — the key MUST match what `mobile_input.get_tuning()`
## returns and `set_tuning()` accepts, the rest drive the slider. Keeping the spec in
## one array means adding a knob later is a one-line change here.
const SLIDER_SPECS: Array = [
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

## The collapsible panel body (a PanelContainer) holding diagnostics + sliders.
var _panel_body: PanelContainer = null

## The multi-line diagnostics label, refreshed every `_process` frame while open.
var _diag_label: Label = null

## Per-slider value labels, keyed by the param key, so each slider can show its current
## numeric value next to its name without re-walking the tree.
var _value_labels: Dictionary = {}

## The HSliders, keyed by param key, so "Reset to defaults" can push refreshed values
## back into them without firing their `value_changed` recursively (we guard that).
var _sliders: Dictionary = {}

## The invert-steering checkbox, refreshed by "Reset to defaults".
var _invert_check: CheckButton = null

## Guard flag: true while we are programmatically setting slider/checkbox values (seed
## or reset), so the `value_changed`/`toggled` handlers don't echo straight back into
## the driver. Without this, seeding the UI from `get_tuning()` would re-save every key.
var _suppress_signals: bool = false


func _ready() -> void:
	# Span the whole screen but let touches pass through to the game where there's no
	# control, exactly like touch_controls — the gear/panel capture their own input.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Find the motion driver by group (no hard reference). May be null on a stripped
	# build; every handler guards for it via `_ensure_driver()`.
	_driver = get_tree().get_first_node_in_group("mobile_input")

	# Build the gear + collapsible panel in code so all the wiring lives here.
	_build_ui()

	# Seed the sliders/checkbox from the driver's current (possibly persisted) tuning.
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
	# --- Gear / "Tune" toggle, top-LEFT ----------------------------------
	# Top-left is clear of the steer toggle (top-centre), the action cluster
	# (bottom-right) and the coin counter / lives hearts in the very corners — we nudge
	# it down a bit from the top-left so it doesn't collide with the lives HUD.
	_gear_button = Button.new()
	_gear_button.name = "TuneButton"
	_gear_button.text = "⚙ Tune"  # ⚙ gear glyph + label
	_gear_button.add_theme_font_size_override("font_size", 22)
	_gear_button.custom_minimum_size = Vector2(GEAR_WIDTH, GEAR_HEIGHT)
	_gear_button.anchor_left = 0.0
	_gear_button.anchor_right = 0.0
	_gear_button.anchor_top = 0.0
	_gear_button.anchor_bottom = 0.0
	_gear_button.offset_left = EDGE_MARGIN
	_gear_button.offset_right = EDGE_MARGIN + GEAR_WIDTH
	# Pushed down below the lives HUD (hearts top-left) so the two don't overlap.
	_gear_button.offset_top = EDGE_MARGIN + 48.0
	_gear_button.offset_bottom = EDGE_MARGIN + 48.0 + GEAR_HEIGHT
	_gear_button.pressed.connect(_on_gear_pressed)
	add_child(_gear_button)

	# --- Panel body (collapsible), anchored top-LEFT under the gear -------
	# A PanelContainer gives a translucent rounded background; inside it a
	# ScrollContainer + VBox holds the diagnostics label and all the rows, so a short
	# screen can scroll. It starts hidden (collapsed) — the gear opens it.
	_panel_body = PanelContainer.new()
	_panel_body.name = "TunePanel"
	_panel_body.anchor_left = 0.0
	_panel_body.anchor_right = 0.0
	_panel_body.anchor_top = 0.0
	_panel_body.anchor_bottom = 0.0
	_panel_body.offset_left = EDGE_MARGIN
	_panel_body.offset_right = EDGE_MARGIN + PANEL_WIDTH
	# Sit the panel just under the gear button.
	_panel_body.offset_top = EDGE_MARGIN + 48.0 + GEAR_HEIGHT + 8.0
	_panel_body.offset_bottom = _panel_body.offset_top + PANEL_HEIGHT
	# Translucent dark background so the world stays faintly visible behind the panel.
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.09, 0.88)
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
	vbox.add_theme_constant_override("separation", 8)
	# Make the VBox fill the scroll width so sliders stretch the full panel width.
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0.0)
	scroll.add_child(vbox)

	# --- Diagnostics read-out (top of the panel) -------------------------
	var diag_title := Label.new()
	diag_title.text = "DIAGNOSTICS"
	diag_title.add_theme_font_size_override("font_size", 16)
	diag_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(diag_title)

	_diag_label = Label.new()
	_diag_label.name = "Diagnostics"
	_diag_label.add_theme_font_size_override("font_size", 17)
	# A fixed-ish multi-line block; autowrap off so columns line up.
	_diag_label.text = "Sensor: ..."
	vbox.add_child(_diag_label)

	# A thin separator before the sliders.
	vbox.add_child(HSeparator.new())

	var tune_title := Label.new()
	tune_title.text = "TUNING"
	tune_title.add_theme_font_size_override("font_size", 16)
	tune_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(tune_title)

	# --- One labeled slider per adjustable param -------------------------
	for spec in SLIDER_SPECS:
		_build_slider_row(vbox, spec)

	# --- Invert steering checkbox ----------------------------------------
	_invert_check = CheckButton.new()
	_invert_check.name = "InvertSteering"
	_invert_check.text = "Invert steering"
	_invert_check.add_theme_font_size_override("font_size", 18)
	_invert_check.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	_invert_check.toggled.connect(_on_invert_toggled)
	vbox.add_child(_invert_check)

	vbox.add_child(HSeparator.new())

	# --- Action buttons: Recalibrate / Reset / Close ---------------------
	var recal_button := Button.new()
	recal_button.name = "Recalibrate"
	recal_button.text = "Recalibrate (re-zero)"
	recal_button.add_theme_font_size_override("font_size", 18)
	recal_button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	recal_button.pressed.connect(_on_recalibrate_pressed)
	vbox.add_child(recal_button)

	var reset_button := Button.new()
	reset_button.name = "ResetDefaults"
	reset_button.text = "Reset to defaults"
	reset_button.add_theme_font_size_override("font_size", 18)
	reset_button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	reset_button.pressed.connect(_on_reset_pressed)
	vbox.add_child(reset_button)

	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Close"
	close_button.add_theme_font_size_override("font_size", 18)
	close_button.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)


## Build one labeled slider row [key, label, min, max, step] and append it to `parent`.
## The row is a VBox: a header label ("Name: value") above an HSlider sized for a thumb.
func _build_slider_row(parent: VBoxContainer, spec: Array) -> void:
	var key: String = spec[0]
	var label_text: String = spec[1]
	var min_val: float = spec[2]
	var max_val: float = spec[3]
	var step_val: float = spec[4]

	var row := VBoxContainer.new()
	row.name = key
	row.add_theme_constant_override("separation", 2)
	row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)

	# Header label shows the parameter name and its current numeric value.
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 16)
	header.text = label_text + ": ..."
	row.add_child(header)
	_value_labels[key] = header
	# Stash the display name on the label via meta so the value updater can rebuild text.
	header.set_meta("label_text", label_text)

	# The slider itself. We make it tall (custom_minimum_size height) so the grab area
	# is finger-friendly on a phone.
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0.0, 32.0)
	# Bind the key so one handler serves every slider.
	slider.value_changed.connect(_on_slider_changed.bind(key))
	row.add_child(slider)
	_sliders[key] = slider

	parent.add_child(row)


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


## Open or collapse the panel body and refresh its contents on open so the sliders and
## diagnostics reflect the latest driver state the moment it appears.
func _set_panel_open(open: bool) -> void:
	_panel_open = open
	if _panel_body != null:
		_panel_body.visible = open
	if open:
		# Re-seed in case the driver was found late or tuning changed elsewhere.
		_seed_controls_from_driver()
		_update_diagnostics()


# ============================================================================
# SEEDING / REFRESH
# ============================================================================

## Push the driver's current tuning into the sliders + checkbox WITHOUT echoing each
## change back to the driver (the `_suppress_signals` guard). Used on `_ready()`, on
## open, and after a reset. Safe when the driver is missing (controls just keep defaults).
func _seed_controls_from_driver() -> void:
	var driver: Node = _ensure_driver()
	if driver == null:
		return
	var tuning: Dictionary = driver.get_tuning()
	_suppress_signals = true
	for key in _sliders:
		if tuning.has(key):
			var slider: HSlider = _sliders[key]
			slider.value = float(tuning[key])
			_refresh_value_label(key, float(tuning[key]))
	if _invert_check != null and tuning.has("invert_steering"):
		_invert_check.button_pressed = bool(tuning["invert_steering"])
	_suppress_signals = false


## Rebuild a slider row's header text to "Name: value" with a tidy number of decimals.
func _refresh_value_label(key: String, value: float) -> void:
	if not _value_labels.has(key):
		return
	var header: Label = _value_labels[key]
	var label_text: String = String(header.get_meta("label_text", key))
	# Two decimals reads cleanly for both the small (0.10..0.60) and large (8..45) ranges.
	header.text = "%s: %.2f" % [label_text, value]


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

## A slider moved: push the new value into the driver (which clamps + persists) and
## refresh the row's numeric label. Ignored while we're programmatically seeding/resetting.
func _on_slider_changed(value: float, key: String) -> void:
	if _suppress_signals:
		return
	_refresh_value_label(key, value)
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.set_tuning(key, value)


## The invert-steering checkbox toggled: push it to the driver (persisted). Ignored
## while seeding/resetting so the seed doesn't re-save.
func _on_invert_toggled(pressed: bool) -> void:
	if _suppress_signals:
		return
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.set_tuning("invert_steering", pressed)


## Recalibrate button: re-zero the neutral pose from however the player is holding the
## phone right now. Backs a player diagnosing drifting/unresponsive steering.
func _on_recalibrate_pressed() -> void:
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.recalibrate()


## Reset-to-defaults button: tell the driver to restore + persist the shipped values,
## then re-seed the controls so the sliders/checkbox snap to the new (default) state.
func _on_reset_pressed() -> void:
	var driver: Node = _ensure_driver()
	if driver != null:
		driver.reset_tuning_to_defaults()
	_seed_controls_from_driver()
