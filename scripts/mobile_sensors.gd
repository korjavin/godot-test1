extends Node
class_name MobileSensors
## Mobile motion-sensor **abstraction** — Task 2 of the mobile-motion plan.
##
## The whole "step to walk + tilt to steer" feature reads the phone's motion
## sensors. The problem (the plan's #1 risk, Task 1) is that there are *two*
## possible places that data can come from on the web target, and we couldn't
## test on a real phone in this environment to know which one actually works:
##
##   1. **Native Godot `Input` sensors** — `Input.get_accelerometer()`,
##      `get_gravity()`, `get_gyroscope()`, `get_magnetometer()`. Simplest path,
##      no JavaScript at all. But it is *not guaranteed* that Godot 4.5's HTML5
##      export delivers live sensor data in the browser.
##   2. **A `JavaScriptBridge` DOM shim** (web only) — we attach the browser's own
##      `devicemotion` / `deviceorientation` event listeners, stash the latest
##      values, and poll them into GDScript. This path is *guaranteed* by the web
##      platform where the native one is merely hoped-for — but iOS Safari fires
##      **no** motion events until `DeviceMotionEvent.requestPermission()` is
##      granted from a user-gesture tap in a secure (HTTPS) context.
##
## Per the Task 1 "DEFAULT decision" (no physical device was available, see the
## plan's Context → Key technical gotchas), this class **supports BOTH paths
## behind one clean API** and prefers whichever is actually delivering data:
##   * native first (cheapest, no JS) when its accel/gravity read non-zero,
##   * else the JS-bridge shim (once permission is granted and events arrive).
##
## Everything downstream (`mobile_input.gd` in Task 3+, and the `motion_debug.gd`
## readout) talks **only** to this API and never cares which source won:
##   * `enabled`              — turn polling on/off (idle by default so desktop is untouched).
##   * `has_data()`           — true only when a source is delivering live values.
##   * `linear_accel()`       — acceleration with gravity removed (the *step* signal).
##   * `tilt()`               — roll/pitch relative to the calibrated neutral (the *steer* signal).
##   * `yaw()`                — twist relative to neutral (absolute alpha if available, else integrated gyro).
##   * `request_permission()` — iOS gesture entry point (safe no-op off-web).
##   * `calibrate()`          — capture the current pose as the new "neutral".
##
## Platform behaviour:
##   * On **desktop/editor** there are no real sensors: native reads return zero,
##     the JS bridge is guarded behind `OS.has_feature("web")` and never runs, so
##     `has_data()` returns false and nothing throws.
##   * On **web** the JS listeners feed `_js_*` members which the per-frame poll
##     copies into the same fields the native path would fill, so the rest of the
##     API is source-agnostic.
##
## This is a bare `Node` (not added to any scene yet) with `class_name
## MobileSensors` so `mobile_input.gd` can `MobileSensors.new()` and add it as a
## child. It needs `_ready()`/`_process()`, hence `Node` rather than `RefCounted`.

# --- Tuning constants ------------------------------------------------------

## A source counts as "alive" only if at least one of its vectors has a magnitude
## above this floor. Real accelerometers always read ~9.8 m/s² of gravity even at
## rest, so any live source clears this easily; a dead/absent sensor reads exactly
## zero and stays below it. Keeps `has_data()` honest on desktop (all zeros).
const LIVE_DATA_EPSILON: float = 0.05

## How long (seconds) we trust the last JS-delivered sample before declaring the
## web source stale. Browsers push `devicemotion` at ~60 Hz when active; if the
## tab is backgrounded or permission lapses the events stop, and after this window
## `has_data()` should report false rather than steer on a frozen reading.
const JS_SAMPLE_TIMEOUT: float = 1.0

## Standard gravity magnitude. Used to normalise the gravity vector into a clean
## "down" direction for the tilt math, independent of the device's exact reading.
const GRAVITY_MAGNITUDE: float = 9.80665

# --- Public state ----------------------------------------------------------

## When false the node does no per-frame work and reports `has_data() == false`,
## so an owner can park an instance without it touching anything. `mobile_input`
## flips this on `enable()`. Default off → desktop is byte-for-byte unchanged.
var enabled: bool = false

# --- Internal: the "current sample" (filled from whichever source won) ------
# These hold the latest reading in a *source-agnostic* form. The native path and
# the JS path both write here; the public getters read only from here, so they
# never branch on the source.

## Gravity-only vector (m/s²) — where "down" points in device axes. Total acceleration
## (incl. gravity) is read as a *local* in the readers, not stored, since only gravity
## and the gravity-removed `_linear` are needed past the read.
var _gravity: Vector3 = Vector3.ZERO

## Player-motion acceleration (gravity already removed). On native we compute it
## as `accel - gravity`; the JS `devicemotion.acceleration` field already excludes
## gravity, so we copy it straight in.
var _linear: Vector3 = Vector3.ZERO

## Angular velocity (rad/s) — gyro. Twist-yaw integrates `z` from this when no
## absolute compass heading is available.
var _gyro: Vector3 = Vector3.ZERO

## Absolute orientation in degrees from `deviceorientation` (alpha/beta/gamma).
## `_has_orientation` says whether the browser actually supplied it this frame.
var _orientation: Vector3 = Vector3.ZERO
var _has_orientation: bool = false

## True once *some* source produced a live reading this frame.
var _has_live: bool = false

# --- Internal: which source is active --------------------------------------

## True only on the HTML5 export — gates every `JavaScriptBridge` touch so this
## whole file is inert (and never errors) on desktop/editor.
var _is_web: bool = false

## True once the JS listeners are attached and at least one event has arrived.
var _js_active: bool = false

## Seconds since the last JS sample; compared against JS_SAMPLE_TIMEOUT so a
## stalled stream (backgrounded tab) stops counting as "live".
var _js_age: float = 0.0

# --- Internal: JavaScriptBridge handles ------------------------------------
# CRITICAL: GDScript's JavaScriptBridge callbacks are garbage-collected the moment
# nothing references them — which would silently detach our listeners. We therefore
# keep every created callback and interface in member vars for the node's lifetime.

## The `window` JS object (our scratchpad for stashed sensor values lives on it).
var _js_window: JavaScriptObject = null

## The JS callbacks bound to the DOM events. Held so they survive GC (see above).
var _js_motion_cb: JavaScriptObject = null
var _js_orientation_cb: JavaScriptObject = null

# --- Internal: calibration (neutral pose) ----------------------------------
# "Neutral" is the pose the player holds when standing still / looking straight.
# Tilt and yaw are measured *relative* to it so the player can hold the phone at
# any comfortable angle and have that count as centred.

## Gravity direction captured at the last `calibrate()`. Tilt is the angular
## offset of current gravity from this.
var _neutral_gravity: Vector3 = Vector3.DOWN * GRAVITY_MAGNITUDE

## Absolute yaw (degrees) captured at calibrate, when a compass heading exists.
var _neutral_yaw_deg: float = 0.0

## Gyro-integrated yaw accumulator (radians), used as the twist source when no
## absolute compass alpha is available. Reset to zero on `calibrate()`.
var _integrated_yaw: float = 0.0


func _ready() -> void:
	# Detect the web export once. Everything JS-related is gated on this flag so
	# the file is completely inert on desktop/editor (where JavaScriptBridge calls
	# would otherwise be meaningless or unavailable).
	_is_web = OS.has_feature("web")

	# Start from a sane neutral so the getters never divide by a zero vector even
	# before the first calibrate(): "down" is the obvious resting gravity.
	_neutral_gravity = Vector3.DOWN * GRAVITY_MAGNITUDE


func _exit_tree() -> void:
	# Detach our DOM listeners when the node leaves the tree. The game RELOADS on
	# restart / game-over, and without this each reload would stack another pair of
	# `devicemotion`/`deviceorientation` listeners on the persistent `window`, leaking
	# handlers (and double-counting events) across sessions. removeEventListener needs
	# the *same* function reference we added, which is exactly why we retained the
	# callbacks in member vars — we pass those very objects back here. Web-only; inert
	# (and never errors) on desktop because `_js_window`/callbacks stay null off-web.
	if not _is_web or _js_window == null:
		return
	if _js_motion_cb != null:
		_js_window.removeEventListener("devicemotion", _js_motion_cb)
	if _js_orientation_cb != null:
		_js_window.removeEventListener("deviceorientation", _js_orientation_cb)
	_js_active = false


func _process(delta: float) -> void:
	# Do nothing at all while parked — keeps desktop cost at zero and guarantees
	# no Input/sensor side effects unless an owner explicitly enabled us.
	if not enabled:
		return

	# Refresh the "current sample" from whichever source is live this frame.
	_poll_sources(delta)


# ===========================================================================
# PUBLIC API
# ===========================================================================

## True only when a sensor source is actually delivering live data this frame.
## Desktop/editor (no sensors) and a stalled/un-permissioned web stream both
## return false, so callers can cleanly fall back to keyboard with no special-casing.
func has_data() -> bool:
	return enabled and _has_live


## Player-motion acceleration (m/s²) with gravity already removed — the signal the
## step-detector thresholds. Zero vector when there is no live data.
func linear_accel() -> Vector3:
	return _linear


## Tilt of the device relative to the calibrated neutral, in **radians**, as a
## `Vector2(roll, pitch)`:
##   * x = roll  — leaning the phone left/right around its long axis (drives steering).
##   * y = pitch — tipping the top of the phone toward/away from you.
## Both are signed offsets from neutral, so holding the phone at any comfortable
## angle and calibrating makes that pose read (0, 0). Returns (0,0) with no data.
func tilt() -> Vector2:
	if not _has_live:
		return Vector2.ZERO

	# Roll/pitch from the gravity vector. With the phone's standard device frame
	# (x = right edge, y = top edge, z = out of screen) gravity's components tell
	# us how the screen is oriented relative to "down":
	#   roll  = atan2(gravity.x, gravity.z-ish)  → left/right lean
	#   pitch = atan2(gravity.y, ...)            → fore/aft tip
	# We compute the *current* angles and the *neutral* angles the same way, then
	# return the difference, so the result is relative to calibration.
	var cur := _gravity_angles(_gravity)
	var neutral := _gravity_angles(_neutral_gravity)
	# wrapf keeps the difference in (-PI, PI] so a small lean near the wrap point
	# doesn't read as a near-full-circle turn.
	var roll := wrapf(cur.x - neutral.x, -PI, PI)
	var pitch := wrapf(cur.y - neutral.y, -PI, PI)
	return Vector2(roll, pitch)


## Twist (yaw) of the device around its vertical axis relative to neutral, in
## **radians**. Prefers the absolute compass heading (`deviceorientation.alpha`)
## when the browser supplies it — that source is drift-free — otherwise falls back
## to integrating the gyro's z over time (which drifts, hence the toggle/recalibrate
## mitigation noted in the plan). Returns 0.0 with no live data.
func yaw() -> float:
	if not _has_live:
		return 0.0

	if _has_orientation:
		# Absolute heading available: alpha is degrees [0,360). Offset from the
		# neutral heading captured at calibrate, wrapped to (-PI, PI].
		var cur_yaw := deg_to_rad(_orientation.x)
		var neutral_yaw := deg_to_rad(_neutral_yaw_deg)
		return wrapf(cur_yaw - neutral_yaw, -PI, PI)

	# No compass: use the gyro-integrated accumulator (already relative to the last
	# calibrate, which zeroes it). Wrap so a long twist stays in (-PI, PI].
	return wrapf(_integrated_yaw, -PI, PI)


## iOS-permission entry point. Must be called **from a user gesture** (a button/tap
## handler) because iOS Safari only grants motion access in response to one. On
## non-web platforms (and browsers that don't require permission, e.g. Android
## Chrome) this safely attaches the listeners directly. No-op-safe to call anywhere.
func request_permission() -> void:
	# Off the web there is nothing to permission; native sensors (if any) are
	# already readable, so this is a clean no-op.
	if not _is_web:
		return

	_request_web_permission()


## Whether iOS Safari's motion-permission request has been *granted*. Reads back the
## `window.__gd_perm_granted` flag the permission Promise sets on 'granted' (see
## `_install_ios_permission_flow`). Lets a caller distinguish "permission denied" (this
## returns false but the gesture happened) from "no sensors on this device" — useful if
## the UI ever wants to surface that difference. On non-iOS browsers permission isn't
## gated, so the flag stays 0 and this returns false even though sensors work; treat it
## as "iOS-grant confirmed", not a general has-sensors signal (use `has_data()` for that).
func permission_granted() -> bool:
	if not _is_web or _js_window == null:
		return false
	return _js_num("__gd_perm_granted") > 0.5


## Capture the current pose as the new "neutral". Tilt and yaw are reported as
## offsets from this, so calling calibrate() while the player holds the phone in a
## comfortable resting pose re-centres steering. Also re-zeroes the gyro-integrated
## yaw so twist starts fresh. Safe to call any time (uses the last sample, or the
## default neutral if no data has arrived yet).
func calibrate() -> void:
	# Use the freshest gravity reading as the new "down"; if we have no live data
	# yet, keep the default downward neutral rather than a zero vector.
	if _gravity.length() > LIVE_DATA_EPSILON:
		_neutral_gravity = _gravity
	# Capture the current absolute heading (if any) as the zero for twist-yaw.
	if _has_orientation:
		_neutral_yaw_deg = _orientation.x
	# Reset the drift-prone integrated yaw so the new neutral really is zero twist.
	_integrated_yaw = 0.0


# ===========================================================================
# INTERNAL: source polling
# ===========================================================================

## Refresh the source-agnostic "current sample" from native sensors or the JS shim,
## preferring whichever is actually live. Called once per frame while enabled.
func _poll_sources(delta: float) -> void:
	# Age the JS stream so a stalled feed eventually stops counting as live.
	if _js_active:
		_js_age += delta

	# Read the native sensors ONCE up front and reuse the values for both the
	# "is native alive?" test and the actual fill — avoids the previous double-read
	# (it used to call get_accelerometer()/get_gravity() in the liveness check and then
	# AGAIN inside the reader). A real device reads ~1g of gravity at rest, so a
	# non-trivial accel/gravity magnitude is the reliable "native is live" signal;
	# desktop reads exact zero and we fall through.
	var native_accel := Input.get_accelerometer()
	var native_gravity := Input.get_gravity()
	if native_accel.length() > LIVE_DATA_EPSILON or native_gravity.length() > LIVE_DATA_EPSILON:
		_read_native(delta, native_accel, native_gravity)
		return

	# Native isn't delivering. On web, fall back to the JS-bridge shim if it has a
	# fresh sample. (Off-web there is no shim, so we simply report no data.)
	if _is_web and _js_active and _js_age <= JS_SAMPLE_TIMEOUT:
		_read_js(delta)
		return

	# Neither source produced data this frame: report nothing live and zero the
	# motion signal so downstream getters return neutral values.
	_has_live = false
	_has_orientation = false
	_linear = Vector3.ZERO


## Fill the current sample from the already-read native `Input` sensor values and
## advance the gyro-integrated yaw. Gravity comes straight from the sensor; linear
## accel is the classic `accel - gravity`. (accel/gravity are passed in by the caller
## so we never re-read them — see `_poll_sources`.)
func _read_native(delta: float, accel: Vector3, gravity: Vector3) -> void:
	_gravity = gravity
	# If the platform reports total accel but no separate gravity vector, treat the
	# accelerometer itself as the gravity proxy at rest so tilt still works.
	if _gravity.length() <= LIVE_DATA_EPSILON:
		_gravity = accel
	_linear = accel - _gravity
	_gyro = Input.get_gyroscope()

	# Twist-yaw source preference (even when native wins for tilt):
	# Godot's native `Input` exposes no trustworthy absolute compass heading, so the
	# native path would normally fall back to the drift-prone integrated gyro. BUT on
	# web the JS `deviceorientation` shim may still be delivering a fresh absolute
	# `alpha` (compass) heading even while native sensors drive tilt. That absolute
	# heading is drift-free, so prefer it for yaw() when it's fresh — only integrate the
	# gyro when no live compass sample is available.
	if _is_web and _js_window != null and _js_num("__gd_has_orient") > 0.5:
		_has_orientation = true
		_orientation = Vector3(
			_js_num("__gd_ori_alpha"),
			_js_num("__gd_ori_beta"),
			_js_num("__gd_ori_gamma"))
	else:
		_has_orientation = false
		_integrated_yaw += _gyro.z * delta

	_has_live = true


## Fill the current sample from the JS-shim values stashed on `window` by the DOM
## event listeners. All values are read through `JavaScriptBridge` and converted to
## GDScript floats. Web-only; never reached on desktop.
func _read_js(delta: float) -> void:
	if _js_window == null:
		return

	# devicemotion.accelerationIncludingGravity → accel (local; only used transiently here).
	# devicemotion.acceleration (gravity already excluded) → our _linear.
	# devicemotion.rotationRate (deg/s) → our _gyro (converted to rad/s).
	# We stash each as a flat numeric field on window in the JS callback, so here
	# we just read primitives (robust across browsers that null out sub-objects).
	var accel := Vector3(
		_js_num("__gd_acc_g_x"), _js_num("__gd_acc_g_y"), _js_num("__gd_acc_g_z"))
	_linear = Vector3(
		_js_num("__gd_acc_x"), _js_num("__gd_acc_y"), _js_num("__gd_acc_z"))

	# Gyro: browsers report rotationRate in **degrees/sec**; convert to rad/s to
	# match the native path's units so downstream math is identical either way.
	_gyro = Vector3(
		deg_to_rad(_js_num("__gd_rot_x")),
		deg_to_rad(_js_num("__gd_rot_y")),
		deg_to_rad(_js_num("__gd_rot_z")))

	# Gravity isn't delivered directly by devicemotion; recover it as
	# (accelIncludingGravity − acceleration), which is exactly the gravity vector.
	_gravity = accel - _linear
	if _gravity.length() <= LIVE_DATA_EPSILON:
		_gravity = accel

	# Absolute orientation (deviceorientation): alpha/beta/gamma in degrees.
	# `__gd_has_orient` is set to 1 by the orientation listener once it fires.
	_has_orientation = _js_num("__gd_has_orient") > 0.5
	if _has_orientation:
		_orientation = Vector3(
			_js_num("__gd_ori_alpha"),
			_js_num("__gd_ori_beta"),
			_js_num("__gd_ori_gamma"))
	else:
		# No compass alpha → fall back to integrating the gyro like the native path.
		_integrated_yaw += _gyro.z * delta

	_has_live = true


# ===========================================================================
# INTERNAL: JavaScriptBridge shim (web only)
# ===========================================================================

## Request iOS motion permission (if required) and, on grant, attach the DOM
## listeners. Web-only; assumes `_is_web` was already checked by the caller.
##
## Flow:
##   * If `DeviceMotionEvent.requestPermission` is a function (iOS 13+ Safari), it
##     returns a Promise; we attach listeners only inside its `'granted'` branch.
##   * Otherwise (Android Chrome, desktop browsers) permission isn't gated, so we
##     attach the listeners immediately.
func _request_web_permission() -> void:
	# Grab the window interface once and keep it (it backs the value scratchpad).
	if _js_window == null:
		_js_window = JavaScriptBridge.get_interface("window")
	if _js_window == null:
		# No JS window (shouldn't happen on web, but never assume) — bail safely.
		return

	# Build (and *retain*) the listener callbacks before we might attach them.
	_ensure_js_callbacks()

	# Does this browser require an explicit permission gesture (iOS)? We evaluate a
	# small JS snippet that returns the boolean, rather than poking the API from
	# GDScript, so the feature-detect lives in one place and is browser-robust.
	var needs_permission: bool = bool(JavaScriptBridge.eval(
		"(typeof DeviceMotionEvent !== 'undefined' && " +
		"typeof DeviceMotionEvent.requestPermission === 'function')", true))

	if needs_permission:
		# iOS: requestPermission() returns a Promise. We can't await it from
		# GDScript, so we hand it a JS continuation that, on 'granted', sets a flag
		# and (re)attaches the listeners. We then poll that flag here cheaply: the
		# simplest robust approach is to do the attach inside the JS itself, calling
		# back into our retained add-listener helper exposed on window.
		_install_ios_permission_flow()
	else:
		# No gesture gate (Android/desktop browsers): attach right away.
		_attach_js_listeners()


## Create the two DOM-event callbacks once and stash them in member vars so the
## GDScript GC can't collect them out from under the live listeners. Idempotent.
func _ensure_js_callbacks() -> void:
	if _js_motion_cb == null:
		_js_motion_cb = JavaScriptBridge.create_callback(_on_js_devicemotion)
	if _js_orientation_cb == null:
		_js_orientation_cb = JavaScriptBridge.create_callback(_on_js_deviceorientation)


## Attach `devicemotion` / `deviceorientation` listeners, wiring them to our
## retained GDScript callbacks. Marks the JS source active.
func _attach_js_listeners() -> void:
	if _js_window == null:
		return
	# addEventListener is a method on window; call it with our callbacks. The
	# callbacks receive the DOM event as their single argument (a JS array of args).
	_js_window.addEventListener("devicemotion", _js_motion_cb)
	_js_window.addEventListener("deviceorientation", _js_orientation_cb)
	_js_active = true
	_js_age = 0.0


## iOS path: call DeviceMotionEvent.requestPermission() and only attach listeners
## on 'granted'. We register our GDScript callbacks as window-scoped functions the
## JS can invoke, then run the permission Promise which calls them back.
func _install_ios_permission_flow() -> void:
	# Expose our retained callbacks on window so the Promise's .then can attach the
	# real listeners using the very same (GC-safe) callback objects.
	_js_window.__gd_motion_cb = _js_motion_cb
	_js_window.__gd_orientation_cb = _js_orientation_cb

	# Kick off the permission request. On 'granted', attach both listeners using
	# the stashed callbacks. Everything here runs inside the user-gesture call
	# stack that invoked request_permission(), satisfying iOS's requirement.
	JavaScriptBridge.eval("""
		(function() {
			DeviceMotionEvent.requestPermission().then(function(state) {
				if (state === 'granted') {
					window.addEventListener('devicemotion', window.__gd_motion_cb);
					window.addEventListener('deviceorientation', window.__gd_orientation_cb);
					window.__gd_perm_granted = 1;
				}
			}).catch(function(_e) { /* denied or error: stay on keyboard */ });
		})();
	""", true)

	# We can't know synchronously whether it was granted; the poll loop treats the
	# stream as live only once events actually start arriving (which sets the
	# stashed fields), so marking _js_active here is safe — _js_age gating handles
	# the "permission denied, no events" case by timing the (empty) stream out.
	_js_active = true
	_js_age = 0.0


## `devicemotion` handler. `args` is a JS array; args[0] is the DOM event. We pull
## the numeric fields off it and stash them as flat primitives on window, which the
## GDScript poll reads via `_js_num`. Stashing primitives (not the live event)
## avoids cross-call lifetime issues with the event object.
func _on_js_devicemotion(args: Array) -> void:
	if _js_window == null or args.is_empty():
		return
	var ev: JavaScriptObject = args[0]
	if ev == null:
		return

	# accelerationIncludingGravity and acceleration are sub-objects with x/y/z;
	# either can be null on some browsers, so guard each access.
	var acc_g: JavaScriptObject = ev.accelerationIncludingGravity
	if acc_g != null:
		_js_window.__gd_acc_g_x = acc_g.x if acc_g.x != null else 0.0
		_js_window.__gd_acc_g_y = acc_g.y if acc_g.y != null else 0.0
		_js_window.__gd_acc_g_z = acc_g.z if acc_g.z != null else 0.0
	var acc: JavaScriptObject = ev.acceleration
	if acc != null:
		_js_window.__gd_acc_x = acc.x if acc.x != null else 0.0
		_js_window.__gd_acc_y = acc.y if acc.y != null else 0.0
		_js_window.__gd_acc_z = acc.z if acc.z != null else 0.0
	var rot: JavaScriptObject = ev.rotationRate
	if rot != null:
		# TWIST-AXIS MAPPING (critical — must agree with yaw()).
		# yaw() integrates _gyro.**z** as the twist-around-vertical signal, and the
		# native path feeds that from `Input.get_gyroscope().z`. For a phone held in
		# portrait, the DOM `rotationRate` axis that measures twist-around-vertical is
		# **alpha** (NOT gamma). So alpha → _gyro.z to keep the JS and native sources on
		# one convention (twist always lands in .z, whichever source is live). beta and
		# gamma fill the other two components for completeness (unused by yaw()).
		_js_window.__gd_rot_z = rot.alpha if rot.alpha != null else 0.0
		_js_window.__gd_rot_x = rot.beta if rot.beta != null else 0.0
		_js_window.__gd_rot_y = rot.gamma if rot.gamma != null else 0.0

	# Mark the stream fresh so the poll's staleness timer resets.
	_js_age = 0.0
	_js_active = true


## `deviceorientation` handler. Stash alpha (compass heading), beta, gamma so the
## poll can use the absolute heading for drift-free twist-yaw when present.
func _on_js_deviceorientation(args: Array) -> void:
	if _js_window == null or args.is_empty():
		return
	var ev: JavaScriptObject = args[0]
	if ev == null:
		return
	# alpha is the compass-like heading [0,360); it can be null if the device lacks a
	# magnetometer. We must CLEAR __gd_has_orient when alpha goes absent, not just set
	# it when present — otherwise the flag latches to 1 forever and the poll keeps
	# trusting a stale heading after the compass drops out. So: set on a valid alpha,
	# reset on a null/absent one (the poll then falls back to integrated gyro).
	if ev.alpha != null:
		_js_window.__gd_ori_alpha = ev.alpha
		_js_window.__gd_ori_beta = ev.beta if ev.beta != null else 0.0
		_js_window.__gd_ori_gamma = ev.gamma if ev.gamma != null else 0.0
		_js_window.__gd_has_orient = 1
	else:
		_js_window.__gd_has_orient = 0
	# Touching orientation also counts as a live sample for staleness purposes.
	_js_age = 0.0
	_js_active = true


# ===========================================================================
# INTERNAL: small helpers
# ===========================================================================

## Read a numeric field stashed on `window` by the JS listeners, as a GDScript
## float. Missing/undefined fields read as 0.0 so an absent sensor is harmless.
func _js_num(field: String) -> float:
	if _js_window == null:
		return 0.0
	var v = _js_window[field]
	if v == null:
		return 0.0
	return float(v)


## Convert a gravity vector into (roll, pitch) angles in radians. Both `tilt()`'s
## current and neutral poses go through this, so the *difference* is what matters
## and the exact axis convention only has to be self-consistent.
##   roll  = atan2(gravity.x, gravity.y) — lean around the screen's long axis.
##   pitch = atan2(gravity.z, gravity.y) — tip the top toward/away from you.
func _gravity_angles(g: Vector3) -> Vector2:
	# Guard against a zero vector (no data) so atan2 stays well-defined.
	if g.length() <= LIVE_DATA_EPSILON:
		return Vector2.ZERO
	var roll := atan2(g.x, g.y)
	var pitch := atan2(g.z, g.y)
	return Vector2(roll, pitch)
