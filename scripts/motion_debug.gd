extends Label
## Motion sensor feasibility readout (debug HUD) — Task 1 of the mobile-motion plan.
##
## The whole mobile-controls feature rests on one unknown: **does the web (HTML5)
## build actually deliver live motion-sensor data on a phone, and does iOS need a
## permission prompt first?** Before we build the step-detector and tilt-steering
## on top of those sensors, we want to *see the raw numbers* on a real device.
##
## This Label prints, every frame, the four motion sensors Godot exposes plus two
## environment flags that tell us how to gate everything later:
##   * Accelerometer — total acceleration including gravity (m/s²).
##   * Gravity       — the gravity vector alone (where "down" is). Tilt-steering
##                     reads this; the difference (accel − gravity) is the player's
##                     own motion, which step-detection reads.
##   * Gyroscope     — angular velocity (rad/s). Twist-yaw integrates this.
##   * Magnetometer  — compass field; an alternate absolute-heading source.
##   * Touchscreen   — `DisplayServer.is_touchscreen_available()`, the primary
##                     "are we on a phone/tablet?" signal used to auto-show the UI.
##   * Web           — `OS.has_feature("web")`, true only in the HTML5 export.
##
## It deliberately mirrors `perf_overlay.gd`: a plain Label under the HUD
## CanvasLayer, throttled text refresh, a single debug toggle key, and it starts
## visible only in debug builds (or on web, where it is the on-phone diagnostic)
## so it never ends up in a release-desktop player's face. It touches no gameplay
## — it only reads sensor values and prints them.
##
## NOTE (Task 1 finding, see plan Context): on desktop/editor these `Input.*`
## sensor calls return zero vectors — there are no real sensors — so the readout
## showing all-zeros on desktop is the *expected, correct* behaviour, and proves
## the script loads and runs without disturbing keyboard+mouse play.

## Key that toggles the readout on/off. F4 is unused by any gameplay input action
## (move/jump/run/duck/switch_character/special_ability in project.godot) and sits
## right next to F3 (the perf overlay), keeping all debug toggles together.
const TOGGLE_KEYCODE: Key = KEY_F4

## How often (seconds) we rebuild the text. Sensors update fast, but a human can
## only read a few updates a second; ~10 Hz is smooth to watch while staying cheap
## and not flooding the label with unreadable jitter.
const REFRESH_INTERVAL: float = 0.1

## Seconds left until the next text refresh (counts down each frame).
var _time_until_refresh: float = 0.0


func _ready() -> void:
	# Join a group so the UI / other systems could find or toggle us later if needed
	# (matches the group-discovery convention used across this project).
	add_to_group("motion_debug")

	# Never let this debug label eat touches/clicks meant for the game or the
	# on-screen buttons we add later.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Legible over the bright sky: pale text with a dark outline. We anchor this
	# one to the bottom-left in the scene file so it stays clear of the perf
	# overlay (top-left), the coin counter and ability dial (top-right).
	add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_theme_constant_override("outline_size", 6)
	add_theme_font_size_override("font_size", 16)

	# Start visible in a debug build (so we always have numbers while developing)
	# and on the web export (this readout *is* the on-phone Task 1 diagnostic).
	# In a release desktop build it stays hidden until F4 is pressed, so it never
	# ships in a player's face. Task 6 will tighten/remove this scaffolding.
	visible = OS.is_debug_build() or OS.has_feature("web")

	# Seed the first refresh so text appears right away rather than after a delay.
	_time_until_refresh = 0.0


func _input(event: InputEvent) -> void:
	# Toggle visibility on the configured key. We read the raw key here (rather
	# than a named input action) on purpose: this is a developer/debug toggle, not
	# a gameplay control, so it intentionally lives outside the project's input map
	# — exactly like the perf overlay's F3.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEYCODE:
			visible = not visible
			# Force an immediate refresh so the readout feels instant when shown.
			if visible:
				_time_until_refresh = 0.0


func _process(delta: float) -> void:
	# Cheap-return while hidden so the readout costs essentially nothing when off.
	if not visible:
		return

	# Throttle the text rebuild to REFRESH_INTERVAL (see the constant's rationale).
	_time_until_refresh -= delta
	if _time_until_refresh > 0.0:
		return
	_time_until_refresh = REFRESH_INTERVAL

	_update_text()


## Read every motion sensor + environment flag and rebuild the label text.
func _update_text() -> void:
	# --- Motion sensors ----------------------------------------------------
	# All four return a Vector3. On hardware that lacks a given sensor (or on
	# desktop/editor) Godot returns Vector3.ZERO, which is exactly what we want to
	# observe: zeros here on a phone would mean "web isn't delivering this sensor",
	# the central Task 1 question that decides our sensor source for Task 2.
	var accel: Vector3 = Input.get_accelerometer()
	var gravity: Vector3 = Input.get_gravity()
	var gyro: Vector3 = Input.get_gyroscope()
	var mag: Vector3 = Input.get_magnetometer()

	# Linear (player-motion) acceleration = total accel minus gravity. This is the
	# signal the step-detector will threshold in Task 3; showing it here lets us
	# eyeball how big a real step's spike is before we pick STEP_ACCEL_THRESHOLD.
	var linear: Vector3 = accel - gravity

	# --- Environment / gating flags ---------------------------------------
	# These decide *whether* the mobile controls turn on at all (Task 5 gating).
	var touchscreen: bool = DisplayServer.is_touchscreen_available()
	var is_web: bool = OS.has_feature("web")

	# --- Compose the readout ----------------------------------------------
	# One metric per line, formatted like the perf overlay so it screenshots well
	# for recording the on-device findings back into the plan's Context section.
	text = "MOTION (F4)\n"
	text += "Accel:   (%6.2f, %6.2f, %6.2f)\n" % [accel.x, accel.y, accel.z]
	text += "Gravity: (%6.2f, %6.2f, %6.2f)\n" % [gravity.x, gravity.y, gravity.z]
	text += "Linear:  (%6.2f, %6.2f, %6.2f)\n" % [linear.x, linear.y, linear.z]
	text += "Gyro:    (%6.2f, %6.2f, %6.2f)\n" % [gyro.x, gyro.y, gyro.z]
	text += "Mag:     (%6.2f, %6.2f, %6.2f)\n" % [mag.x, mag.y, mag.z]
	text += "Touchscreen: %s\n" % ("yes" if touchscreen else "no")
	text += "Web: %s" % ("yes" if is_web else "no")
