extends Node
## Mobile motion-input **driver** — Task 3 of the mobile-motion plan (step-to-walk).
##
## This is the bare `Node` that turns the phone's motion sensors into the game's
## existing input actions, so the player controller never has to know mobile
## controls exist. It is added once under `Main` in `main.tscn` (exactly like
## `CrocodileLODManager`) and discovered by other systems through the
## `"mobile_input"` group — no hard references, per the project convention.
##
## ----------------------------------------------------------------------------
## What this task adds: STEP TO WALK
## ----------------------------------------------------------------------------
## The phone's accelerometer spikes each time the player physically takes a step
## (the foot-strike jolts the device). We detect those spikes and translate them
## into forward movement of the hero:
##
##   1. Every frame we read `MobileSensors.linear_accel()` — acceleration with
##      gravity already removed — and take its magnitude. At rest that magnitude
##      hovers near zero; a footstep produces a sharp transient peak.
##   2. A **peak detector** registers a "step" when that magnitude crosses
##      `STEP_ACCEL_THRESHOLD` going *upward*, but only if at least
##      `STEP_MIN_INTERVAL` seconds have passed since the last accepted step (a
##      refractory period that prevents a single noisy footfall from counting as
##      several steps).
##   3. Each accepted step pumps `STEP_WALK_PER_STEP` into a `walk_energy` float
##      that continuously **decays** by `STEP_WALK_DECAY` per second. Keep
##      stepping and the energy stays topped up; stop stepping and it bleeds away.
##   4. The forward strength fed to the controller is `clamp(walk_energy, 0, 1)`.
##      Above `WALK_DEADZONE` we drive `Input.action_press("move_forward",
##      strength)`; below it we `Input.action_release("move_forward")` so the hero
##      coasts to a stop rather than twitching on residual energy.
##
## `move_forward` is an **analog** action the controller polls with
## `Input.get_axis("move_forward", "move_backward")`, so `action_press(action,
## strength)` is the right mechanism — the strength flows straight through. (The
## plan's gotcha: this differs from `switch_character`, which is event-driven and
## needs `parse_input_event`; that is a later task and not touched here.)
##
## ----------------------------------------------------------------------------
## Low coupling / desktop safety (the important part)
## ----------------------------------------------------------------------------
## This driver writes to `Input` **only when it is active**. It starts inactive,
## so on desktop/editor it does nothing at all and the existing keyboard W/S
## movement is byte-for-byte unchanged — the driver never calls `action_press` or
## `action_release` while disabled, so it can't fight the keyboard. `enable()` /
## `disable()` flip the `active` flag (Task 5's UI will call them on a real phone);
## a debug force-enable key (F5) lets a developer exercise the driver in the editor
## without a device, again without touching release-desktop behaviour.
##
## ----------------------------------------------------------------------------
## What this task adds: TILT / TWIST TO STEER (Task 4)
## ----------------------------------------------------------------------------
## On top of step-to-walk this file now also synthesizes the *turning* actions
## (`turn_left` / `turn_right`) from the phone's orientation, so the player can
## steer the hero without a keyboard. There are two interchangeable steer modes,
## selectable from the on-screen toggle (Task 5):
##
##   * **TILT (default)** — roll the phone left/right around its long axis. We read
##     `MobileSensors.tilt()` (roll/pitch vs the calibrated neutral, in radians),
##     convert the roll to degrees, subtract a small `STEER_DEADZONE_DEG`, and scale
##     what's left across `STEER_FULL_DEG` into a `[0, STEER_MAX_STRENGTH]` turn
##     strength. The *sign* of the roll picks `turn_left` vs `turn_right`. Tilt is
##     drift-free (gravity is an absolute reference), which is why it's the default.
##   * **TWIST** — rotate the phone around its vertical axis (like turning a
##     steering wheel held flat). We read `MobileSensors.yaw()` (twist vs neutral,
##     radians — absolute compass heading when the browser supplies it, else
##     integrated gyro) and run it through the *same* deadzone→scale→press path. The
##     toggle that selects TWIST also recalibrates, re-zeroing neutral, because
##     integrated-gyro yaw drifts.
##
## Both paths end in the same primitive: above the deadzone we
## `Input.action_press("turn_left"/"turn_right", strength)`; back inside the
## deadzone we release both. `turn_left`/`turn_right` are analog actions the
## controller polls with `Input.get_axis("turn_right", "turn_left")`, so pressing
## them with a strength flows straight through exactly like `move_forward`.
##
## SIGN CONVENTION (critical — see player_controller.gd:523 `handle_turning()`):
##   `turn_input = Input.get_axis("turn_right", "turn_left")` and a *positive*
##   turn_input (i.e. `turn_left` pressed) spins the body **counter-clockwise**,
##   which is the hero's **left**. So "press turn_left" == "hero turns left". We
##   therefore map a *left* tilt / *left* twist of the phone to `turn_left`, so the
##   physical gesture and the on-screen result agree (tilt left → hero goes left).
##   The exact roll/yaw sign that corresponds to "phone tilted left" can vary by
##   device/browser axis convention, so the chosen sign here is documented at the
##   mapping and is one of the things confirmed/flipped during on-device tuning
##   (Task 6) — same posture Task 3 takes with its accelerometer axes.
##
## The same low-coupling guard applies: steering only writes Input while `active`,
## so desktop keyboard A/D turning is byte-for-byte untouched, and `disable()`
## releases both turn actions so nothing is left stuck pressed.

# ============================================================================
# CONSTANTS — step-to-walk tuning (final values set on-device in Task 6)
# ============================================================================
# These are sensible *starting* values picked from the physics of a footstep on a
# hand-held phone. They will be tuned against the real `MobileSensors.linear_accel()`
# magnitudes once a device is available (the Task 1 `motion_debug.gd` F4 readout is
# the instrument for reading a real step's peak height). Until then they are
# conservative enough to walk without false-triggering on hand jitter.

## Linear-acceleration magnitude (m/s²) a footstep must exceed to count as a step.
## At rest the gravity-removed signal sits near 0; a deliberate step on a held
## phone typically peaks well above ~2–3 m/s². Set above resting jitter but below a
## real step's peak so ordinary hand-shake doesn't register as walking.
const STEP_ACCEL_THRESHOLD: float = 2.5

## Refractory period (seconds) — the minimum time between two accepted steps. Human
## walking cadence tops out around ~2.5 steps/second, so ~0.28 s comfortably admits
## a brisk pace while rejecting the multiple frames a single foot-strike spike spans
## (which would otherwise be double/triple-counted).
const STEP_MIN_INTERVAL: float = 0.28

## How fast `walk_energy` bleeds away per second when no new steps arrive (units of
## energy/second). Higher = the hero stops sooner after the player stops stepping;
## lower = more "coasting". Tuned so a couple of missed steps still keeps the hero
## moving smoothly but a real stop halts within a beat.
const STEP_WALK_DECAY: float = 1.6

## How much `walk_energy` each accepted step injects. With energy clamped to [0,1]
## for the final strength, a value near 0.6 means a single step gives a strong-but-
## not-instant-full push and a second step within the decay window saturates to full
## walk — so a steady cadence reads as a confident, sustained walk.
const STEP_WALK_PER_STEP: float = 0.6

## Forward-strength deadzone. Below this clamped `walk_energy` we release
## `move_forward` entirely rather than feed a tiny analog value, so the hero comes
## to a clean stop (and the controller's idle animation can take over) instead of
## creeping on decay remnants.
const WALK_DEADZONE: float = 0.08

# ============================================================================
# CONSTANTS — steering tuning (final values set on-device in Task 6)
# ============================================================================
# These map a *degree* of tilt or twist (away from the calibrated neutral) onto a
# turn strength fed to `turn_left`/`turn_right`. Like the step constants they are
# sensible starting points chosen from comfortable hand-held phone angles; the
# real feel is dialled in against a device in Task 6.

## Steering deadzone, in **degrees** of tilt/twist from neutral. Below this the
## phone is treated as "centred" and no turn is applied — so small, unavoidable
## wobble while holding the phone (or stepping) doesn't make the hero drift. Set
## small enough that a deliberate lean is still responsive but large enough to
## swallow resting jitter.
const STEER_DEADZONE_DEG: float = 6.0

## Degrees of tilt/twist (measured *past* the deadzone) that map to full turn
## strength. A ~25° lean past the 6° deadzone (≈31° total) gives a full-rate turn;
## anything beyond just saturates. Smaller = twitchier/more sensitive steering,
## larger = you must lean further for the same turn. Tuned for a comfortable wrist
## tilt on-device in Task 6.
const STEER_FULL_DEG: float = 25.0

## Ceiling for the synthesized turn strength, in [0,1]. The controller multiplies
## the polled axis by its own `TURN_SPEED`, so 1.0 here means "tilt can command the
## same top turn rate the A/D keys do". Capped at 1.0 (a full key press); kept as a
## constant so the on-device pass can soften peak turn speed without touching the
## scaling math.
const STEER_MAX_STRENGTH: float = 1.0

## Debug force-enable key. F3 (perf overlay) and F4 (motion readout) are taken, so
## F5 is the next free function key — pressing it toggles this driver on/off in the
## editor so a developer can exercise step-to-walk without a phone. It is a
## developer toggle, deliberately *outside* the project input map (like F3/F4), and
## never affects a released desktop build's play because the driver still no-ops
## with no live sensor data.
const FORCE_ENABLE_KEYCODE: Key = KEY_F5

# ============================================================================
# STEER MODE
# ============================================================================

## The two ways the phone's orientation can steer the hero. TILT (the default) is
## drift-free roll-to-turn; TWIST is yaw-to-turn (rotating the phone flat). The UI
## toggle (Task 5) flips between them via `set_steer_mode()`.
enum SteerMode {
	TILT,   ## Default: roll the phone left/right (gravity-based, drift-free).
	TWIST,  ## Optional: twist the phone around its vertical axis (yaw-based).
}

# ============================================================================
# STATE
# ============================================================================

## The sensor abstraction this driver reads. Owned and added as a child in
## `_ready()` (like `motion_debug.gd` does) so it runs its own per-frame poll. All
## sensor access goes through this one object, so the driver is source-agnostic.
var _sensors: MobileSensors = null

## Master gate. While false the driver does NO Input writes — it returns early in
## the per-frame step, so the keyboard is never contested. Flipped by
## `enable()`/`disable()` (Task 5 UI) and by the F5 debug toggle. Default off so
## desktop is untouched.
var active: bool = false

## Running forward "energy". Steps pump it up; it decays every frame. The clamped
## value is the analog `move_forward` strength. See the class header for the model.
var walk_energy: float = 0.0

## Seconds since the last accepted step, used to enforce `STEP_MIN_INTERVAL`. Seeded
## large so the very first step is accepted immediately.
var _time_since_step: float = 999.0

## Previous frame's linear-accel magnitude, so we can detect an *upward* crossing of
## the threshold (a rising edge) rather than firing every frame the signal is high.
var _prev_accel_mag: float = 0.0

## True only while we are actively holding `move_forward` pressed, so we release it
## exactly once when energy drops back under the deadzone (and never spam releases).
var _pressing_forward: bool = false

## Current steering scheme. Defaults to TILT (drift-free roll) per the plan; the
## UI toggle flips it to TWIST via `set_steer_mode()`, which also recalibrates.
var steer_mode: SteerMode = SteerMode.TILT

## True only while we are actively holding `turn_left` pressed, so we release it
## exactly once when steering returns to the deadzone (and never spam releases).
var _pressing_turn_left: bool = false

## True only while we are actively holding `turn_right` pressed. Same one-shot
## release discipline as `_pressing_turn_left`.
var _pressing_turn_right: bool = false


func _ready() -> void:
	# Join the discovery group so the touch-controls UI (Task 5) can find this driver
	# via `get_tree().get_first_node_in_group("mobile_input")` — the same no-hard-
	# references pattern the rest of the project uses.
	add_to_group("mobile_input")

	# Stand up the sensor abstraction and add it as a child so it runs its own
	# _process poll. We enable it (harmless on desktop: no real sensors → it reports
	# has_data() == false and writes nothing) and calibrate once so a later tilt/yaw
	# task starts from the current resting pose. The driver itself stays inactive.
	_sensors = MobileSensors.new()
	_sensors.name = "MobileInputSensors"
	add_child(_sensors)
	_sensors.enabled = true
	_sensors.calibrate()


func _input(event: InputEvent) -> void:
	# Developer force-enable toggle (F5). Read the raw key, not a named action: this
	# is debug-only and intentionally lives outside the project input map, exactly
	# like the perf overlay (F3) and motion readout (F4) toggles. On a real phone the
	# UI calls enable()/disable() instead, so this is purely an editor convenience.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == FORCE_ENABLE_KEYCODE:
			if active:
				disable()
			else:
				enable()


func _physics_process(delta: float) -> void:
	# Drive movement off the physics step so the analog strength we press lines up
	# with the controller's own `_physics_process` polling of `move_forward`.
	#
	# THE LOW-COUPLING GUARD: while inactive we touch nothing — no decay, no Input
	# writes — so the keyboard owns `move_forward` completely on desktop. We do make
	# sure that if we are *transitioning* to inactive we have already released the
	# action (handled in disable()), so we can safely just return here.
	if not active:
		return

	_update_step_to_walk(delta)
	# Steering shares the same active-gated path so it, too, never writes turn
	# actions while disabled — keeping desktop A/D turning byte-for-byte untouched.
	_update_steering(delta)


# ============================================================================
# PUBLIC API (called by the Task 5 touch-controls UI; safe to call any time)
# ============================================================================

## Turn the driver on. Recalibrates the sensors' neutral pose so steering (a later
## task) starts centred from however the player is holding the phone, and resets the
## step state so we don't carry stale energy into a fresh session. From here the
## per-frame step loop runs and may write `move_forward`.
func enable() -> void:
	if active:
		return
	active = true
	# Fresh neutral + clean step state on every enable. Calibrating here is what
	# makes steering centred from however the player is *currently* holding the
	# phone: tilt() and yaw() are both measured relative to this captured neutral,
	# so whatever pose they enable in reads as "no turn".
	if _sensors != null:
		_sensors.calibrate()
	_reset_step_state()
	_reset_steer_state()


## Turn the driver off and IMMEDIATELY hand `move_forward` back to the keyboard. We
## release the action here (not just stop pressing it) so a hero that was walking on
## sensor energy doesn't get stuck "pressed" when control returns to the keyboard.
func disable() -> void:
	if not active:
		return
	active = false
	_release_forward()
	# Hand the turn actions straight back to the keyboard too, so a hero that was
	# mid-turn on tilt doesn't get stuck "pressed" when control returns to A/D.
	_release_turns()
	_reset_step_state()
	_reset_steer_state()


## Switch the steering scheme AND recalibrate. The UI toggle (Task 5) calls this;
## per the plan it doubles as a *recalibrate* so the player can re-zero neutral
## (drift-prone twist-yaw especially benefits) simply by tapping the toggle.
## Releasing any held turn here prevents a stale press carrying across the switch.
func set_steer_mode(mode: SteerMode) -> void:
	steer_mode = mode
	if _sensors != null:
		_sensors.calibrate()
	# Drop any turn we were holding so the new mode starts from a clean centre.
	_release_turns()
	_reset_steer_state()


## Thin passthrough to the owned sensor's iOS-permission entry point. The Task 5
## touch-controls UI talks **only** to this driver (via the "mobile_input" group),
## never to the `MobileSensors` child directly, so it can't reach the sensor's
## `request_permission()` itself. This forwards the call so the "Tap to enable
## motion controls" overlay can satisfy iOS Safari's user-gesture requirement
## without coupling the UI to the sensor object. Safe no-op off-web / when the
## sensor isn't present yet.
func request_permission() -> void:
	if _sensors != null:
		_sensors.request_permission()


## Thin passthrough to the owned sensor's `calibrate()` (capture the current pose
## as the new neutral). Exposed for the same reason as `request_permission()`: the
## UI only knows about this driver, so it routes a manual recalibrate through here.
## Note `enable()` already calibrates, so the overlay does **not** need to call this
## separately on first enable — it exists for any UI that wants an explicit re-zero.
func calibrate() -> void:
	if _sensors != null:
		_sensors.calibrate()


# ============================================================================
# INTERNAL: the step-to-walk loop
# ============================================================================

## One frame of step detection + walk-energy bookkeeping + Input drive. Only ever
## called while `active`, so every Input write below is gated by that flag.
func _update_step_to_walk(delta: float) -> void:
	# Advance the refractory clock every frame regardless of detection.
	_time_since_step += delta

	# --- 1. Read the step signal ------------------------------------------
	# linear_accel() is acceleration with gravity removed; its magnitude is the
	# footstep transient we threshold. With no live sensor (desktop, or web before
	# permission) this is the zero vector → magnitude 0 → no steps, energy decays to
	# nothing, and we release move_forward. So even "active on desktop" is harmless.
	var accel_mag: float = 0.0
	if _sensors != null:
		accel_mag = _sensors.linear_accel().length()

	# --- 2. Peak detector: rising-edge crossing + refractory --------------
	# A step is the moment the magnitude rises *through* the threshold (it was below
	# last frame, it's at/above now). Requiring the rising edge means one sustained
	# spike fires exactly once, and the STEP_MIN_INTERVAL gate rejects the cluster of
	# frames a single foot-strike spans.
	var crossed_up: bool = _prev_accel_mag < STEP_ACCEL_THRESHOLD and accel_mag >= STEP_ACCEL_THRESHOLD
	if crossed_up and _time_since_step >= STEP_MIN_INTERVAL:
		walk_energy += STEP_WALK_PER_STEP
		_time_since_step = 0.0
	_prev_accel_mag = accel_mag

	# --- 3. Decay the energy ----------------------------------------------
	# Continuous bleed so the hero coasts to a stop when stepping stops. Clamp to
	# [0,1]: 0 floor so it never goes negative, 1 ceiling so the analog strength we
	# press never exceeds a normal full walk.
	walk_energy = clampf(walk_energy - STEP_WALK_DECAY * delta, 0.0, 1.0)

	# --- 4. Drive move_forward --------------------------------------------
	# Above the deadzone, press the analog action at the current strength (the
	# controller reads this via get_axis). Below it, release once so the hero stops
	# cleanly. We track _pressing_forward so we only emit a single release.
	var strength: float = walk_energy
	if strength > WALK_DEADZONE:
		Input.action_press("move_forward", strength)
		_pressing_forward = true
	else:
		_release_forward()


## Release `move_forward` exactly once (idempotent). Used by the deadzone branch and
## by disable() so the action is never left stuck pressed.
func _release_forward() -> void:
	if _pressing_forward:
		Input.action_release("move_forward")
		_pressing_forward = false


## Clear all step/walk state so enabling or disabling starts from a clean slate
## (no leftover energy, refractory clock seeded to accept the first step at once).
func _reset_step_state() -> void:
	walk_energy = 0.0
	_time_since_step = 999.0
	_prev_accel_mag = 0.0


# ============================================================================
# INTERNAL: the steering loop (tilt / twist)
# ============================================================================

## One frame of steering: read the active source (roll in TILT mode, twist in TWIST
## mode) as a signed angle in **degrees**, deadzone + scale it to a turn strength,
## and drive the matching turn action. Only ever called while `active`, so every
## Input write below is gated by that flag (desktop A/D turning stays untouched).
func _update_steering(_delta: float) -> void:
	# --- 1. Read the steer angle (signed, degrees) ------------------------
	# Both sources come from MobileSensors relative to the calibrated neutral, in
	# radians; we convert to degrees so the deadzone/full-scale constants read in
	# intuitive units. With no live sensor (desktop, or web before permission) the
	# getters return 0, so angle == 0 → no turn → the keyboard keeps A/D.
	var angle_deg: float = 0.0
	if _sensors != null:
		if steer_mode == SteerMode.TILT:
			# tilt() is Vector2(roll, pitch); roll (x) is the left/right lean.
			angle_deg = rad_to_deg(_sensors.tilt().x)
		else:  # SteerMode.TWIST
			# yaw() is the twist about the vertical axis (absolute alpha or gyro).
			angle_deg = rad_to_deg(_sensors.yaw())

	# --- 2. Deadzone + scale to a turn strength ---------------------------
	# `_steer_strength` returns a *signed* value in [-STEER_MAX_STRENGTH,
	# +STEER_MAX_STRENGTH]: 0 inside the deadzone, ramping to the cap over
	# STEER_FULL_DEG of lean past the deadzone. The sign carries the direction.
	var signed_strength: float = _steer_strength(angle_deg)

	# --- 3. Drive the turn actions ----------------------------------------
	# SIGN MAPPING (see the class header): we want a *left* lean/twist of the phone
	# to turn the hero left, and `turn_left` is the CCW/left action (its polled
	# axis is positive). We treat a **positive** signed_strength as "lean/twist
	# left" → press `turn_left`; a **negative** value as "lean/twist right" →
	# press `turn_right`. Which physical direction yields a positive roll/yaw can
	# differ by device/browser; if a real phone steers backwards, this single
	# comparison is the one place to flip (an on-device Task-6 confirmation).
	if signed_strength > 0.0:
		_press_turn_left(signed_strength)
	elif signed_strength < 0.0:
		_press_turn_right(-signed_strength)
	else:
		# Inside the deadzone (or no data): release both so the hero stops turning.
		_release_turns()


## Map a signed steer angle (degrees from neutral) to a signed turn strength in
## [-STEER_MAX_STRENGTH, +STEER_MAX_STRENGTH]. Inside `STEER_DEADZONE_DEG` the
## result is exactly 0; past it, the magnitude ramps linearly to the cap over
## `STEER_FULL_DEG` degrees and then saturates. The sign of the input is preserved.
func _steer_strength(angle_deg: float) -> float:
	var magnitude: float = absf(angle_deg) - STEER_DEADZONE_DEG
	if magnitude <= 0.0:
		# Within the deadzone: treat as centred, no turn.
		return 0.0
	# Scale the past-deadzone amount across STEER_FULL_DEG, clamp to the cap, and
	# re-apply the original sign so direction is preserved.
	var strength: float = clampf(magnitude / STEER_FULL_DEG, 0.0, 1.0) * STEER_MAX_STRENGTH
	return signf(angle_deg) * strength


## Press `turn_left` at the given strength and ensure `turn_right` is not also held
## (the two are mutually exclusive — we only ever turn one way at a time).
func _press_turn_left(strength: float) -> void:
	Input.action_press("turn_left", strength)
	_pressing_turn_left = true
	_release_turn_right()


## Press `turn_right` at the given strength and ensure `turn_left` is released.
func _press_turn_right(strength: float) -> void:
	Input.action_press("turn_right", strength)
	_pressing_turn_right = true
	_release_turn_left()


## Release `turn_left` exactly once (idempotent), so we never spam releases.
func _release_turn_left() -> void:
	if _pressing_turn_left:
		Input.action_release("turn_left")
		_pressing_turn_left = false


## Release `turn_right` exactly once (idempotent).
func _release_turn_right() -> void:
	if _pressing_turn_right:
		Input.action_release("turn_right")
		_pressing_turn_right = false


## Release both turn actions (used in the deadzone branch, on disable, and on a
## mode switch) so neither is ever left stuck pressed when we hand back to keyboard.
func _release_turns() -> void:
	_release_turn_left()
	_release_turn_right()


## Clear steering press-tracking so enabling/disabling/mode-switching starts clean
## (mirrors `_reset_step_state`). We only reset the bookkeeping flags here; the
## actual action releases are done by `_release_turns()` at those same call sites.
func _reset_steer_state() -> void:
	_pressing_turn_left = false
	_pressing_turn_right = false
