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
## Steering (tilt / twist) and the on-screen buttons are *later* tasks; this file
## currently owns the sensor instance and the step-to-walk loop only.

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

## Debug force-enable key. F3 (perf overlay) and F4 (motion readout) are taken, so
## F5 is the next free function key — pressing it toggles this driver on/off in the
## editor so a developer can exercise step-to-walk without a phone. It is a
## developer toggle, deliberately *outside* the project input map (like F3/F4), and
## never affects a released desktop build's play because the driver still no-ops
## with no live sensor data.
const FORCE_ENABLE_KEYCODE: Key = KEY_F5

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
	# Fresh neutral + clean step state on every enable.
	if _sensors != null:
		_sensors.calibrate()
	_reset_step_state()


## Turn the driver off and IMMEDIATELY hand `move_forward` back to the keyboard. We
## release the action here (not just stop pressing it) so a hero that was walking on
## sensor energy doesn't get stuck "pressed" when control returns to the keyboard.
func disable() -> void:
	if not active:
		return
	active = false
	_release_forward()
	_reset_step_state()


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
