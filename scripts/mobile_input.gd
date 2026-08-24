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
# DEFAULT TUNING VALUES (live-adjustable — see the `var`s just below)
# ============================================================================
# These `const DEFAULT_*` values are the *starting points* picked from the physics
# of a footstep on a hand-held phone. They are now ONLY the defaults: the live values
# the driver actually reads each frame are the plain `var`s further down, which the
# on-device **tuning panel** (`mobile_settings_panel.gd`) edits at runtime via
# `set_tuning()` and persists to `user://mobile_tuning.cfg`. Keeping the defaults as
# named consts lets "Reset to defaults" (and a missing config file) fall back to the
# exact values that used to be hard-coded — so behaviour is byte-for-byte identical
# until the player deliberately changes a slider.

## Default linear-acceleration magnitude (m/s²) a footstep must exceed to count as a
## step. At rest the gravity-removed signal sits near 0; a deliberate step on a held
## phone typically peaks well above ~2–3 m/s². Set above resting jitter but below a
## real step's peak so ordinary hand-shake doesn't register as walking.
const DEFAULT_STEP_ACCEL_THRESHOLD: float = 2.5

## Default refractory period (seconds) — the minimum time between two accepted steps.
## Human walking cadence tops out around ~2.5 steps/second, so ~0.28 s comfortably
## admits a brisk pace while rejecting the multiple frames a single foot-strike spike
## spans (which would otherwise be double/triple-counted).
const DEFAULT_STEP_MIN_INTERVAL: float = 0.28

## Default `walk_energy` bleed per second when no new steps arrive (units of
## energy/second). Higher = the hero stops sooner after the player stops stepping;
## lower = more "coasting".
const DEFAULT_STEP_WALK_DECAY: float = 1.6

## Default `walk_energy` each accepted step injects. With energy clamped to [0,1] for
## the final strength, ~0.6 means a single step gives a strong-but-not-instant-full
## push and a second step within the decay window saturates to full walk.
const DEFAULT_STEP_WALK_PER_STEP: float = 0.6

## Default steering deadzone, in **degrees** of tilt/twist from neutral. Below this
## the phone is "centred" and no turn is applied, so resting wobble doesn't drift.
const DEFAULT_STEER_DEADZONE_DEG: float = 6.0

## Default degrees of tilt/twist (measured *past* the deadzone) that map to full turn
## strength. Smaller = twitchier/more sensitive steering, larger = lean further.
const DEFAULT_STEER_FULL_DEG: float = 25.0

# ============================================================================
# LIVE TUNING VARS — what the driver actually reads each frame
# ============================================================================
# These are the runtime-adjustable knobs. They START at the `DEFAULT_*` consts above
# (so a fresh install / missing config behaves exactly like the old hard-coded code),
# are OVERWRITTEN from `user://mobile_tuning.cfg` in `_ready()` if a saved file exists,
# and are edited live by the on-device tuning panel through `set_tuning()` (which also
# re-saves). The on-device tuner is how the final feel gets dialled in — see the plan's
# Task 6 note that no hardware was available in the build env, so these can now be tuned
# by the player on a real phone instead of guessed in code.

## Live step threshold — see `DEFAULT_STEP_ACCEL_THRESHOLD`.
var STEP_ACCEL_THRESHOLD: float = DEFAULT_STEP_ACCEL_THRESHOLD

## Live step refractory period — see `DEFAULT_STEP_MIN_INTERVAL`.
var STEP_MIN_INTERVAL: float = DEFAULT_STEP_MIN_INTERVAL

## Live walk-energy decay — see `DEFAULT_STEP_WALK_DECAY`.
var STEP_WALK_DECAY: float = DEFAULT_STEP_WALK_DECAY

## Live walk-energy per step — see `DEFAULT_STEP_WALK_PER_STEP`.
var STEP_WALK_PER_STEP: float = DEFAULT_STEP_WALK_PER_STEP

## Live steering deadzone (degrees) — see `DEFAULT_STEER_DEADZONE_DEG`.
var STEER_DEADZONE_DEG: float = DEFAULT_STEER_DEADZONE_DEG

## Live full-turn angle (degrees) — see `DEFAULT_STEER_FULL_DEG`.
var STEER_FULL_DEG: float = DEFAULT_STEER_FULL_DEG

## Flip which way tilt/twist turns the hero. Some devices/browsers report roll/yaw
## with the opposite sign than this code assumes, so a player whose steering feels
## *reversed* can tick this from the tuning panel to fix it — it simply negates the
## signed steer strength in `_update_steering`. Persisted like the numeric knobs.
var invert_steering: bool = false

# ============================================================================
# CONSTANTS — steering tuning that stays fixed (not exposed in the panel)
# ============================================================================

## Forward-strength deadzone. Below this clamped `walk_energy` we release
## `move_forward` entirely rather than feed a tiny analog value, so the hero comes
## to a clean stop (and the controller's idle animation can take over) instead of
## creeping on decay remnants. Not panel-exposed: it's an internal floor, not a feel knob.
const WALK_DEADZONE: float = 0.08

## Ceiling for the synthesized turn strength, in [0,1]. The controller multiplies
## the polled axis by its own `TURN_SPEED`, so 1.0 here means "tilt can command the
## same top turn rate the A/D keys do". Capped at 1.0 (a full key press); kept a
## constant — the panel tunes sensitivity via the deadzone/full-angle, not this cap.
const STEER_MAX_STRENGTH: float = 1.0

# ============================================================================
# PERSISTENCE
# ============================================================================

## Where the live tuning is saved. `user://` maps to IndexedDB on the web export, so
## the values **persist across page reloads** — which is exactly what lets a player
## experiment with the sliders, reload, and keep their tuning. A missing file is fine:
## `_load_tuning()` just keeps the defaults. The single `[tuning]` section holds one
## key per adjustable var (matching the keys `get_tuning()`/`set_tuning()` use).
const TUNING_CONFIG_PATH: String = "user://mobile_tuning.cfg"
const TUNING_SECTION: String = "tuning"

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

## DIAGNOSTICS (read by the on-device tuning panel via `get_diagnostics()`).
## These mirror the live signals so a player can SEE the controls working: whether
## data flows, how big their step spikes are (the key number for setting the
## threshold), and how many steps have registered. None of them affect behaviour —
## they are pure read-outs computed alongside the existing step/steer math.

## Current frame's linear-accel magnitude (m/s²). Cached so the panel and the step
## detector read the same value. This is "accel now" in the readout.
var _diag_accel_mag: float = 0.0

## Rolling, decaying maximum of `_diag_accel_mag` over roughly the last
## `ACCEL_PEAK_HALFLIFE` seconds. THE number to set the step threshold by: glance at
## the peak while walking and set `STEP_ACCEL_THRESHOLD` a touch below it. It rises
## instantly to a new high and bleeds back down so an old spike doesn't stick forever.
var _diag_accel_peak: float = 0.0

## Total accepted steps since the last `enable()` / state reset. Shown as "steps:" in
## the panel so the player can confirm each physical step is being detected one-for-one.
var _diag_step_count: int = 0

## How fast the rolling accel peak decays. Expressed as a half-life: the peak loses
## half its excess over the current magnitude every `ACCEL_PEAK_HALFLIFE` seconds, so
## a spike from a step stays visible for ~1.5 s (a couple of steps) before fading.
const ACCEL_PEAK_HALFLIFE: float = 0.5

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

## Whether the driver was `active` at the moment the app lost focus (browser tab
## backgrounded / app switched). Remembered across the pause so `resume_from_pause()`
## can restore exactly the pre-pause state: a player who had motion running gets it
## back automatically on the resume tap, while one who never enabled it isn't
## surprise-enabled by merely switching tabs.
var _was_active_before_pause: bool = false


## The analog actions whose per-action deadzone we zero in `_ready()` (see there for
## why). The driver actively *drives* `move_forward` (from stepping) and
## `turn_left`/`turn_right` (from tilt/twist) via `Input.action_press(action,
## strength)`; `move_backward` is **never** synthesized (the design is forward-only —
## you turn around to go back), but it is the negative half of the controller's
## `get_axis("move_forward", "move_backward")` read, so we clear its deadzone too for
## consistency. Clearing a deadzone we never press is harmless.
const SYNTHESIZED_ANALOG_ACTIONS: PackedStringArray = [
	"move_forward", "move_backward", "turn_left", "turn_right",
]


func _ready() -> void:
	# PAUSING: this node deliberately keeps the DEFAULT process mode, so the
	# focus-loss pause below freezes its `_physics_process` (and the sensors child's
	# polling) along with the rest of the world — structurally guaranteeing the
	# driver never writes `Input` while paused. Nothing here needs to tick during
	# the pause: `_notification()` is delivered regardless of pause mode, and
	# `resume_from_pause()` is a direct method call from the touch UI (whose own
	# node IS `PROCESS_MODE_ALWAYS` so its resume overlay stays tappable).

	# Join the discovery group so the touch-controls UI (Task 5) can find this driver
	# via `get_tree().get_first_node_in_group("mobile_input")` — the same no-hard-
	# references pattern the rest of the project uses.
	add_to_group("mobile_input")

	# DEADZONE GUARD (defensive — see the empirical note below).
	# The four actions we drive analog-style declare `"deadzone": 0.5` in project.godot
	# (a sensible default for *keyboard/joypad* axes). The synthesized walk/steer ramps
	# can legitimately sit *below* 0.5 (e.g. STEP_WALK_PER_STEP=0.6 decaying away, or the
	# lower half of the tilt ramp). If the controller's `Input.get_axis(...)` →
	# `get_action_strength()` read applied that 0.5 deadzone, the entire lower half of our
	# analog range would be silently swallowed and steering/walk would feel dead.
	#
	# EMPIRICALLY (Godot 4.5): `Input.action_press(action, strength)` actually BYPASSES
	# the per-action deadzone — a 0.1/0.3/0.6 press reads back unchanged via both
	# `get_action_strength()` and `get_axis()`. So the swallow does NOT happen today.
	# We still zero the deadzone here as a cheap, harmless belt-and-braces guarantee: it
	# makes the analog ramp correct regardless of any future engine change, and it does
	# NOT affect desktop keyboard input (a key press is strength 1.0, well above any
	# deadzone). Done once at startup; the project.godot values are otherwise untouched.
	# Gated on the touch predicate like every other platform-visible change in this
	# codebase: this permanently mutates the PROJECT input map for four gameplay
	# actions, and it is inert today only because none of them has a joypad binding.
	# Bind a stick axis tomorrow and an ungated zero would cost desktop its 0.5
	# deadzone and let a drifting stick walk the player. The driver only ever writes
	# Input on a touch session anyway, so that is the only session that needs it.
	if MobileSensors.is_touch_session():
		for action in SYNTHESIZED_ANALOG_ACTIONS:
			if InputMap.has_action(action):
				InputMap.action_set_deadzone(action, 0.0)

	# Stand up the sensor abstraction and add it as a child so it runs its own
	# _process poll. We enable it (harmless on desktop: no real sensors → it reports
	# has_data() == false and writes nothing) and calibrate once so a later tilt/yaw
	# task starts from the current resting pose. The driver itself stays inactive.
	_sensors = MobileSensors.new()
	_sensors.name = "MobileInputSensors"
	add_child(_sensors)
	_sensors.enabled = true
	_sensors.calibrate()

	# Load any previously-saved live tuning. On web this comes back from IndexedDB, so a
	# player's dialled-in feel survives a page reload. A missing/old file is harmless —
	# `_load_tuning()` only overwrites the keys it finds and leaves the rest at defaults.
	_load_tuning()


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


func _notification(what: int) -> void:
	# PAUSE ON FOCUS LOSS (touch sessions only). The browser fires this when the tab
	# is backgrounded or the phone app-switches — the player is gone, so freeze the
	# world rather than let crocodiles keep hunting a hero nobody is steering.
	#
	# Gated on the canonical touch predicate: desktop alt-tab must NOT pause (the
	# acceptance bar is desktop byte-for-byte unchanged), and `is_touch_session()` is
	# false everywhere a keyboard player could alt-tab.
	#
	# We deliberately do NOT auto-resume on NOTIFICATION_APPLICATION_FOCUS_IN: resume
	# is the explicit "tap to resume" in the touch UI, which doubles as the WebAudio
	# unlock gesture browsers require after a tab returns from the background.
	#
	# PAUSE INTERACTIONS (sanity-checked, nothing else to do here): the respawn
	# countdown and the game-over UI live under default-process_mode nodes, so while
	# the tab is hidden they freeze WITH the tree and resume cleanly on the tap — a
	# frozen countdown is the *correct* behavior (no losing lives while backgrounded).
	# Neither script is touched by this feature.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not MobileSensors.is_touch_session():
			return
		pause_game()


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


## True only while the tree pause was created by `pause_game()` (focus loss or the
## portrait guard). The touch UI's full-screen "tap to resume" overlay is gated on
## this, because a tree pause is no longer ours alone — the multiplayer panel pauses
## too, and an overlay claiming the screen for somebody else's pause both hides that
## panel and unpauses the game out from under it on the next tap.
var paused_by_driver: bool = false


## Freeze the tree, remembering whether motion was running so `resume_from_pause()`
## can restore it. Called on focus loss (above) and by the touch UI when the phone
## rotates to portrait. IDEMPOTENT — the early return when already paused matters:
## a second focus loss while paused (double app-switch without a resume tap) would
## otherwise overwrite `_was_active_before_pause` with the now-false `active`,
## leaving motion permanently dead after the resume tap (the UI has no other
## re-enable path).
func pause_game() -> void:
	var tree := get_tree()
	if tree.paused:
		return
	# Never pause over the Game Over screen — same rule as pause_controller's
	# _toggle_pause(). The resume overlay lives inside TouchControls, which sits
	# BELOW the full-rect GameOver panel in the HUD; a paused Control gets no GUI
	# input but still blocks the PROCESS_MODE_ALWAYS one beneath it, so "Play
	# Again" and the resume tap would BOTH be dead and only a page reload escapes.
	var player := tree.get_first_node_in_group("player")
	if player != null and bool(player.get("is_game_over")):
		return
	# Remember whether motion was running so the resume tap can restore it, then
	# disable FIRST (releases every held action so nothing stays latched pressed
	# through the pause) and freeze the whole tree.
	_was_active_before_pause = active
	disable()
	tree.paused = true
	paused_by_driver = true


## Unfreeze the tree after a focus-loss pause. Called by the touch UI's full-screen
## "Paused — tap to resume" overlay (via the "mobile_input" group). Re-enables the
## driver only if it was active when focus was lost — `enable()` also recalibrates
## neutral, which is exactly right after a pause: the player is re-settling into
## however they're NOW holding the phone.
func resume_from_pause() -> void:
	get_tree().paused = false
	paused_by_driver = false
	if _was_active_before_pause:
		enable()
	_was_active_before_pause = false


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


## Expose the owned `MobileSensors` so other systems (e.g. the `motion_debug.gd`
## readout) can READ the *same* live sensor instead of standing up a second one. Two
## independent MobileSensors would each attach their own JS `devicemotion`/
## `deviceorientation` listeners and fight over the shared `window.__gd_*` scratchpad;
## sharing this one avoids duplicate listeners entirely. May be null very early (before
## `_ready()`), so callers should null-check.
func get_sensors() -> MobileSensors:
	return _sensors


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


## Re-zero the neutral pose on demand. This is a thin passthrough to the owned
## sensor's `calibrate()`, re-added because the on-device tuning panel now exposes a
## "Recalibrate (re-zero)" button: a player diagnosing unresponsive steering wants to
## re-centre from however they're CURRENTLY holding the phone without toggling steer
## mode. (A prior cleanup removed this as dead code; it is now a live UI affordance.)
## Safe no-op before the sensor exists.
func recalibrate() -> void:
	if _sensors != null:
		_sensors.calibrate()


# ============================================================================
# PUBLIC API — live tuning (called by the on-device tuning panel)
# ============================================================================

## Return the current value of every adjustable parameter, keyed by the SAME strings
## `set_tuning()` accepts and `_load_tuning()`/`_save_tuning()` persist. The tuning
## panel reads this once to seed its sliders/toggle; it is the single authoritative
## list of what is tunable, so the panel never hard-codes the parameter set.
func get_tuning() -> Dictionary:
	return {
		"step_accel_threshold": STEP_ACCEL_THRESHOLD,
		"step_walk_per_step": STEP_WALK_PER_STEP,
		"step_walk_decay": STEP_WALK_DECAY,
		"step_min_interval": STEP_MIN_INTERVAL,
		"steer_deadzone_deg": STEER_DEADZONE_DEG,
		"steer_full_deg": STEER_FULL_DEG,
		"invert_steering": invert_steering,
	}


## Update ONE tuning parameter live and immediately persist the whole set. The panel
## calls this from each slider's `value_changed` / the checkbox's `toggled`. Unknown
## keys are ignored (defensive), and each numeric key is clamped to the same range the
## panel offers so a bad value can never wedge the feel. Saving on every change is what
## makes the tuning survive a page reload (see `_save_tuning`).
func set_tuning(key: String, value) -> void:
	match key:
		"step_accel_threshold":
			STEP_ACCEL_THRESHOLD = clampf(float(value), 0.2, 6.0)
		"step_walk_per_step":
			STEP_WALK_PER_STEP = clampf(float(value), 0.1, 2.0)
		"step_walk_decay":
			STEP_WALK_DECAY = clampf(float(value), 0.3, 4.0)
		"step_min_interval":
			STEP_MIN_INTERVAL = clampf(float(value), 0.10, 0.60)
		"steer_deadzone_deg":
			STEER_DEADZONE_DEG = clampf(float(value), 0.0, 20.0)
		"steer_full_deg":
			STEER_FULL_DEG = clampf(float(value), 8.0, 45.0)
		"invert_steering":
			invert_steering = bool(value)
		_:
			# Unknown key: ignore rather than crash, so a future panel field can't break here.
			return
	_save_tuning()


## Restore every adjustable parameter to its `DEFAULT_*` value and persist. Backs the
## panel's "Reset to defaults" button — a one-tap escape hatch if a player tunes
## themselves into an unusable corner.
func reset_tuning_to_defaults() -> void:
	STEP_ACCEL_THRESHOLD = DEFAULT_STEP_ACCEL_THRESHOLD
	STEP_WALK_PER_STEP = DEFAULT_STEP_WALK_PER_STEP
	STEP_WALK_DECAY = DEFAULT_STEP_WALK_DECAY
	STEP_MIN_INTERVAL = DEFAULT_STEP_MIN_INTERVAL
	STEER_DEADZONE_DEG = DEFAULT_STEER_DEADZONE_DEG
	STEER_FULL_DEG = DEFAULT_STEER_FULL_DEG
	invert_steering = false
	_save_tuning()


## Return a snapshot of the LIVE signals for the panel's diagnostics readout. This is
## the centrepiece for diagnosing "controls feel unresponsive": the player can SEE
## whether data is flowing, how big their step spikes are (`accel_peak` — set the
## threshold just under it), the resulting walk energy, the running step count, and the
## current tilt/yaw in degrees. All values are plain reads of state the driver already
## maintains, so calling this every frame is cheap and side-effect-free.
func get_diagnostics() -> Dictionary:
	var has_data: bool = false
	var source: String = "none"
	var tilt_deg: float = 0.0
	var yaw_deg: float = 0.0
	if _sensors != null:
		has_data = _sensors.has_data()
		source = _sensors.current_source()
		# tilt().x is the roll (left/right lean) used by TILT steering; show it in degrees.
		tilt_deg = rad_to_deg(_sensors.tilt().x)
		yaw_deg = rad_to_deg(_sensors.yaw())
	return {
		"has_data": has_data,
		"source": source,
		"accel_mag": _diag_accel_mag,
		"accel_peak": _diag_accel_peak,
		"walk_energy": walk_energy,
		"step_count": _diag_step_count,
		"tilt_deg": tilt_deg,
		"yaw_deg": yaw_deg,
	}


# ============================================================================
# INTERNAL: persistence (ConfigFile at user://mobile_tuning.cfg)
# ============================================================================

## Load the saved tuning over the defaults. A missing file (first run) is NOT an error:
## `ConfigFile.load` returns a non-OK code and we simply keep the defaults. Each value
## is read with the current live value as the fallback, so a partially-written or
## older file only overrides the keys it actually contains. We funnel every loaded
## value back through `set_tuning`'s clamping by assigning then re-clamping via the
## same ranges, guarding against a hand-edited out-of-range file.
func _load_tuning() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(TUNING_CONFIG_PATH)
	if err != OK:
		# No saved file yet (or unreadable) — keep the DEFAULT_* values. This is the
		# expected first-run path and must NOT be treated as a failure.
		return
	# Read each key with the current value as the default, then clamp through the same
	# ranges set_tuning() enforces so a tampered file can't push the feel out of bounds.
	STEP_ACCEL_THRESHOLD = clampf(
		float(cfg.get_value(TUNING_SECTION, "step_accel_threshold", STEP_ACCEL_THRESHOLD)), 0.2, 6.0)
	STEP_WALK_PER_STEP = clampf(
		float(cfg.get_value(TUNING_SECTION, "step_walk_per_step", STEP_WALK_PER_STEP)), 0.1, 2.0)
	STEP_WALK_DECAY = clampf(
		float(cfg.get_value(TUNING_SECTION, "step_walk_decay", STEP_WALK_DECAY)), 0.3, 4.0)
	STEP_MIN_INTERVAL = clampf(
		float(cfg.get_value(TUNING_SECTION, "step_min_interval", STEP_MIN_INTERVAL)), 0.10, 0.60)
	STEER_DEADZONE_DEG = clampf(
		float(cfg.get_value(TUNING_SECTION, "steer_deadzone_deg", STEER_DEADZONE_DEG)), 0.0, 20.0)
	STEER_FULL_DEG = clampf(
		float(cfg.get_value(TUNING_SECTION, "steer_full_deg", STEER_FULL_DEG)), 8.0, 45.0)
	invert_steering = bool(cfg.get_value(TUNING_SECTION, "invert_steering", invert_steering))


## Write the current live tuning to disk. On web `user://` is IndexedDB-backed, so this
## is what makes a player's tuning survive a reload. `ConfigFile.save` creates the file
## if it doesn't exist (no error on first save) and overwrites it otherwise; we ignore
## the return code because a failed save just means the tuning isn't persisted this run,
## which is non-fatal and must never interrupt play.
func _save_tuning() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(TUNING_SECTION, "step_accel_threshold", STEP_ACCEL_THRESHOLD)
	cfg.set_value(TUNING_SECTION, "step_walk_per_step", STEP_WALK_PER_STEP)
	cfg.set_value(TUNING_SECTION, "step_walk_decay", STEP_WALK_DECAY)
	cfg.set_value(TUNING_SECTION, "step_min_interval", STEP_MIN_INTERVAL)
	cfg.set_value(TUNING_SECTION, "steer_deadzone_deg", STEER_DEADZONE_DEG)
	cfg.set_value(TUNING_SECTION, "steer_full_deg", STEER_FULL_DEG)
	cfg.set_value(TUNING_SECTION, "invert_steering", invert_steering)
	cfg.save(TUNING_CONFIG_PATH)


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

	# DIAGNOSTICS: cache the current magnitude and track a decaying rolling peak so the
	# tuning panel can show "accel now" and "peak". The peak rises instantly to any new
	# high and otherwise bleeds toward the current magnitude at the half-life rate, so a
	# step's spike stays readable for ~a second instead of vanishing in one frame.
	_diag_accel_mag = accel_mag
	if accel_mag > _diag_accel_peak:
		_diag_accel_peak = accel_mag
	else:
		# Exponential decay of the *excess* over the current magnitude toward 0.
		var decay: float = pow(0.5, delta / ACCEL_PEAK_HALFLIFE)
		_diag_accel_peak = accel_mag + (_diag_accel_peak - accel_mag) * decay

	# --- 2. Peak detector: rising-edge crossing + refractory --------------
	# A step is the moment the magnitude rises *through* the threshold (it was below
	# last frame, it's at/above now). Requiring the rising edge means one sustained
	# spike fires exactly once, and the STEP_MIN_INTERVAL gate rejects the cluster of
	# frames a single foot-strike spans.
	var crossed_up: bool = _prev_accel_mag < STEP_ACCEL_THRESHOLD and accel_mag >= STEP_ACCEL_THRESHOLD
	if crossed_up and _time_since_step >= STEP_MIN_INTERVAL:
		walk_energy += STEP_WALK_PER_STEP
		_time_since_step = 0.0
		_diag_step_count += 1  # diagnostics: count this accepted step for the panel readout.
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
## Also zeroes the diagnostics that are meaningful per-session: the step counter
## restarts at 0 on each `enable()` so the panel's "steps:" reflects this session, and
## the rolling accel peak resets so a stale spike from a previous session doesn't show.
func _reset_step_state() -> void:
	walk_energy = 0.0
	_time_since_step = 999.0
	_prev_accel_mag = 0.0
	_diag_step_count = 0
	_diag_accel_peak = 0.0
	_diag_accel_mag = 0.0


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

	# INVERT STEERING (panel toggle): some devices/browsers report roll/yaw with the
	# opposite sign than the SIGN MAPPING below assumes, which makes steering feel
	# reversed. Negating the signed strength here cleanly swaps left<->right without
	# touching the press logic, so a player can fix a backwards-steering phone from the
	# tuning panel instead of needing a code change.
	if invert_steering:
		signed_strength = -signed_strength

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
