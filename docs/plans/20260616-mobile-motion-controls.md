# Mobile Motion Controls (step-to-walk + tilt-steer + on-screen buttons)

## Overview
Make the **web build playable on a phone with no keyboard**. The hero is driven by
physically moving the device:

- **Step to walk** — the accelerometer detects the player physically stepping; each
  detected step advances the hero forward (forward-only; see design note below).
- **Tilt to steer (default)** — rolling the phone left/right turns the hero. A
  **twist-yaw** mode (rotate the phone around its vertical axis) is available via an
  on-screen toggle, which also re-zeros the neutral pose (doubling as a recalibrate).
- **On-screen buttons** for the keyboard-only actions: **Jump**, **Switch character
  (R / `switch_character`)**, **Special ability (F / `special_ability`)**, plus the
  small steer-mode toggle.

It integrates with the existing input system **without rewriting the player
controller**: `player_controller.gd` already reads everything through named input
actions (`move_forward`, `turn_left`/`turn_right`, `jump`, `switch_character`,
`special_ability`). The new code **synthesizes those same actions** from sensor data
and touch buttons, so the controller logic, animation, and abilities are untouched.

All of this is **mobile/touch-only**: on desktop the UI is hidden and the motion
driver is idle, so keyboard + mouse play is byte-for-byte unchanged — matching the
project's "visual/behavioral changes are platform-gated, desktop stays full quality"
convention.

### Design notes / non-goals
- **Forward-only stepping.** There is no reliable "step backward" gesture; the game is
  forward-oriented. To go back, the player turns 180° via steering. An optional
  on-screen "back" button is explicitly out of scope.
- **Twist-yaw drifts.** Gyro-integrated yaw (and compass heading) drift/are noisy. We
  mitigate with re-zeroing on the toggle and on enable, but tilt-steer is the
  recommended default precisely because it is drift-free.
- **No sensitivity slider.** Tuning is via constants at the top of the scripts, set
  during the on-device tuning pass (Task 6).

## Context (from discovery)
- **Engine:** Godot **4.5**, ships primarily as a **web (WebGL / `gl_compatibility`)**
  build to GitHub Pages — the exact mobile target. `OS.has_feature("web")` and `.web`
  project-setting overrides are the established web-gating mechanism.
- **Input is fully action-based** (`project.godot` `[input]`): `move_forward`/
  `move_backward`, `turn_left`/`turn_right` (tank-style: forward/back + body rotation,
  not free-strafe), `step_left`/`step_right`, `jump`, `run`, `duck`,
  `switch_character` (**R**, physical_keycode 82), `special_ability` (**F**). The "r"
  and "f" the user asked for already exist as named actions.
- **`scripts/player_controller.gd`** consumes input only via:
  - `Input.get_axis("move_forward", "move_backward")` → `get_input_direction()`
  - `Input.get_axis("turn_right", "turn_left")` → `handle_turning()` (`player_controller.gd:523`)
  - `Input.is_action_just_pressed("jump")` (`:376`, gated on `is_on_floor()` and `not is_giant`)
  - `Input.is_action_just_pressed("special_ability")` (`:359` → `try_activate_ability()`)
  - `event.is_action_pressed("switch_character")` in **`_input()`** (`:306` → `switch_to_next_character()`)
  - Mouse camera in `_input()` (`:284-296`) and **mouse capture** `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)` (`:237`).
- **HUD** is a single `CanvasLayer` named `HUD` in `scenes/main.tscn` holding
  `CoinLabel`, `PerfOverlay`, `AbilityHUD` (Control), `LivesHUD` (Control),
  `RespawnLabel`, `GameOver` — the natural parent for an on-screen touch-controls
  `Control`.
- **Convention:** systems are wired by **groups**, not hard references (player in
  `"player"`, found via `get_tree().get_first_node_in_group(...)`); HUD scripts like
  `ability_hud.gd` already follow this. `CrocodileLODManager` is the model for a
  bare `Node` added once under `Main` that drives behavior without hard refs.
- **No test suite / linter / build script.** Verification is manual (run scene / web
  export on phone) plus a headless "loads with no script errors" smoke check.

### Key technical gotchas discovered
- **`switch_character` is handled in `_input()`, not polled.** `Input.action_press(...)`
  sets the *polled* action state but does **not** dispatch an `InputEventAction` through
  `_input()`, so a button that only calls `action_press("switch_character")` would
  **not** trigger the switch. Discrete buttons must use
  `Input.parse_input_event(InputEventAction)` (which flows through the full pipeline
  including `_input`) — or call `switch_to_next_character()` on the player directly via
  the `"player"` group. Analog held actions (`move_forward`, `turn_*`) can safely use
  `Input.action_press(action, strength)` / `action_release(action)` since the controller
  polls them with `get_axis`/`get_action_strength`.
- **Sensor delivery on web is the #1 risk (Task 1 spike).** It is not guaranteed that
  Godot 4.5's `Input.get_accelerometer()/get_gravity()/get_gyroscope()` return live data
  in the HTML5 export, and **iOS Safari requires `DeviceMotionEvent.requestPermission()`
  from a user gesture** before any `devicemotion`/`deviceorientation` events fire. The
  plan therefore (a) spikes native availability first, and (b) provides a
  `JavaScriptBridge` shim (DOM event listeners + `requestPermission()` on first tap) as a
  fallback sensor source, behind one abstraction so the rest of the code doesn't care
  which source won.
- **Task 1 finding (DEFAULT decision — device-untested).** On-device verification could
  not be run in the build environment (no physical phone, no HTTPS LAN host for the
  iOS-secure-context requirement), so the spike's "which sensor source?" question cannot
  be answered empirically here. The **safe default for Task 2 is to support BOTH paths**
  behind the single `MobileSensors` abstraction:
  1. **Native Godot `Input` sensors** (`get_accelerometer()`/`get_gravity()`/
     `get_gyroscope()`/`get_magnetometer()`) — used when `MobileSensors.has_data()`
     reports live (non-zero, changing) values. This is the simplest path and needs no JS.
  2. **`JavaScriptBridge` DOM shim** as the fallback — `window.addEventListener(
     'devicemotion'/'deviceorientation', …)` with the values polled into GDScript, and
     **iOS `DeviceMotionEvent.requestPermission()` called from a user-gesture tap** (the
     on-screen "enable motion" overlay) before any listener is attached. This path is
     guaranteed by the spec where the native one is *not* — web sensor delivery through
     Godot is not promised, and iOS Safari fires **no** `devicemotion`/`deviceorientation`
     events until permission is granted from a gesture in a **secure (HTTPS) context**.
  Rationale: because web sensor delivery via Godot's `Input.*` is not guaranteed and iOS
  hard-requires a permission gesture, committing to native-only would risk a dead feature
  on the exact target (mobile web). Building both behind `MobileSensors` (native preferred,
  JS-bridge fallback, iOS permission gated behind the enable tap) is the lowest-risk
  default and lets the on-device tuning pass (Task 6) simply confirm which path won
  without changing any downstream code. The desktop/editor build no-ops cleanly either
  way: native sensors read zero and the JS bridge is guarded behind `OS.has_feature("web")`.
  The `motion_debug.gd` F4 readout added in Task 1 is the on-phone instrument that, once a
  device is available, will record the actual native-availability result back into this note.

## Development Approach
- **Verification approach (chosen): Manual + headless smoke** — this project has no test
  framework, so the per-task "tests" are: (1) a `godot --headless` load that reports **no
  parse/script errors**, (2) running the scene / web export and **observing the
  documented behavior on a phone**, and (3) a **desktop regression check** that
  keyboard+mouse play is unchanged. Sensor/touch I/O fundamentally cannot be unit-tested
  here; it is verified on a real device.
- Complete each task fully (including its verification block) before starting the next.
- Make small, focused changes; keep heavy commenting to match the surrounding teaching
  style of the codebase.
- **Platform discipline (project convention):** anything a player can see or feel
  (on-screen UI, motion driving the hero) is **touch/mobile-gated**; desktop/editor stay
  identical. Entity counts and gameplay tuning are never changed as a side effect.
- **Keep the player controller untouched where possible.** Drive existing input actions
  rather than adding code paths inside `player_controller.gd`. The only allowed edit to
  it is the small "don't capture the mouse on touch devices" guard (Task 5).
- Update this plan file (checkboxes, ➕ new tasks, ⚠️ blockers) as implementation
  proceeds — especially after the Task 1 spike, whose findings pick the sensor source.

## Testing Strategy
- **No unit/e2e framework exists** (confirmed: pure Godot, no GUT). Do **not** fabricate
  unit tests. Each task's verification is the trio above (headless smoke + on-device
  behavior + desktop regression).
- **Headless smoke command** (per task, catches parse/load errors without a GPU):
  ```bash
  godot --headless --path . scenes/main.tscn --quit-after 120 2>&1 | grep -iE "error|script|SCRIPT" || echo "no errors"
  ```
  (`--quit-after N` exits after N frames; tune as needed. The goal is "scene + new
  scripts load and run a few frames without errors".)
- **Web export command** (same as CI, for on-phone testing):
  ```bash
  mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html
  ./serve.sh   # then open the LAN URL on the phone
  ```
- **On-device matrix:** test iOS Safari **and** Android Chrome if available — the iOS
  motion-permission gate and per-browser sensor axis conventions differ. Record findings
  in the Context section as they're learned.

## Progress Tracking
- Mark completed items `[x]` immediately when done.
- Add newly discovered tasks with a ➕ prefix; document blockers with ⚠️.
- After Task 1, **write the spike findings into "Context → Key technical gotchas"** and
  adjust Task 2's sensor source accordingly.

## Solution Overview
Three new pieces, all touch/mobile-gated, wired by groups:

1. **`scripts/mobile_sensors.gd`** — a sensor **abstraction**. Exposes a clean API
   (`enabled`, `has_data()`, linear acceleration, gravity/tilt, gyro/yaw, absolute
   orientation when available, `request_permission()`, `calibrate()`). Internally sources
   data from native Godot `Input` sensors **or** a `JavaScriptBridge` DOM shim
   (`devicemotion`/`deviceorientation` + iOS `DeviceMotionEvent.requestPermission()`),
   decided by the Task 1 spike. Everything else depends only on this API.

2. **`scripts/mobile_input.gd`** — a bare `Node` added once under `Main` (like
   `CrocodileLODManager`), in group `"mobile_input"`. Owns a `MobileSensors`. Each frame
   it: runs **step peak-detection** → drives `move_forward` with a decaying analog
   strength; computes **steering** (tilt-roll default, or twist-yaw) → drives
   `turn_left`/`turn_right`. Exposes `enable()/disable()`, `calibrate()`,
   `set_steer_mode(mode)`, `request_permission()` for the UI to call. Idle (no Input
   writes) unless enabled, so desktop is untouched.

3. **`scenes/ui/touch_controls.tscn` + `scripts/touch_controls.gd`** — a `Control` under
   the `HUD` `CanvasLayer`. Anchored, large-hit-area buttons: **Jump**, **Special (F)**,
   **Switch (R)**, **steer-mode toggle**; plus a first-run **"Tap to enable motion
   controls"** overlay that satisfies the iOS permission gesture and calibrates neutral.
   Discrete buttons fire actions via `Input.parse_input_event(InputEventAction)` (switch)
   / `action_press` (jump, special). Finds `mobile_input` via its group. Auto-visible
   only on touch/mobile (`DisplayServer.is_touchscreen_available()` or web coarse-pointer)
   with a debug force-enable for editor testing.

### Key design decisions & rationale
- **Synthesize existing input actions instead of editing the controller** → near-zero
  coupling, the controller's movement/animation/abilities keep working as-is, and desktop
  behavior is provably unchanged.
- **One sensor abstraction with a JS-bridge fallback** → isolates the biggest unknown
  (does web deliver sensors? does iOS need a permission tap?) so the rest of the plan is
  stable regardless of the spike outcome.
- **Tilt-steer default, twist optional** → drift-free steering out of the box; the literal
  "twist" is still available for the player to try on the real device.
- **Group discovery + a `Node`-under-`Main` driver** → matches `CrocodileLODManager` and
  the rest of the codebase's no-hard-references rule.

## Technical Details
- **Step detection:** compute linear-accel magnitude `a = |accelerometer − gravity|`
  (or the JS-shim's `acceleration` which already excludes gravity). Peak detector: a step
  is registered when `a` crosses `STEP_ACCEL_THRESHOLD` upward and at least
  `STEP_MIN_INTERVAL` has elapsed since the last step (refractory period kills double
  counts). Each step adds to a `walk_energy` float that **decays** by `STEP_WALK_DECAY`
  per second; `move_forward` strength = `clamp(walk_energy, 0, 1)`. Stop stepping → energy
  decays → hero stops. Constants at top of `mobile_input.gd`:
  `STEP_ACCEL_THRESHOLD`, `STEP_MIN_INTERVAL`, `STEP_WALK_DECAY`, `STEP_WALK_PER_STEP`,
  `WALK_DEADZONE`.
- **Tilt-steer:** roll angle derived from gravity relative to the calibrated neutral
  (`gravity.x` / `atan2` of the relevant axes). Apply `STEER_DEADZONE_DEG`, scale to
  `[-1, 1]` over `STEER_FULL_DEG`, then `action_press("turn_left"/"turn_right", strength)`
  matching `handle_turning`'s sign convention (`turn_left` positive = CCW). Hold tilt =
  keep turning.
- **Twist-yaw:** prefer absolute `deviceorientation.alpha` (compass) when present; else
  integrate gyro `z` over time. Both stored relative to neutral captured at
  `calibrate()`. Same deadzone→strength→`action_press` path. Re-zeroed on mode toggle.
- **Discrete buttons → actions:**
  - Jump: `Input.parse_input_event` with a pressed+released `InputEventAction("jump")`
    (or `action_press/release("jump")` across two frames). Controller polls
    `is_action_just_pressed("jump")`.
  - Special: same for `"special_ability"` (controller polls it).
  - Switch: **must** go through `parse_input_event(InputEventAction("switch_character"))`
    so `player_controller._input()` sees it (it is not polled). Fallback:
    `get_tree().get_first_node_in_group("player").switch_to_next_character()`.
- **iOS permission / JS bridge** (web only, via `JavaScriptBridge`):
  - On first tap of the enable overlay: if `typeof DeviceMotionEvent.requestPermission
    === 'function'`, call it (returns a Promise) and only start listening on `'granted'`.
  - Register `window.addEventListener('devicemotion', ...)` and `'deviceorientation'`,
    stash latest values on a JS object that GDScript polls via `JavaScriptBridge.eval`
    (or a `JavaScriptObject` callback). Guard everything behind `OS.has_feature("web")`.
- **Mobile detection / gating:** `DisplayServer.is_touchscreen_available()` is the primary
  signal; on web also accept `JavaScriptBridge.eval("matchMedia('(pointer: coarse)').matches")`.
  A debug force-enable (e.g. an unused key like F4, or `OS.is_debug_build()` + a flag)
  shows the UI on desktop for editor iteration **without** affecting release desktop.
- **Mouse capture guard:** in `player_controller._ready()`, skip
  `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)` when mobile controls are active (touch
  device), so no pointer-lock prompt and no captured-mouse weirdness on phones.

## What Goes Where
- **Implementation Steps** (`[ ]`): all script/scene/project changes + per-task
  verification, achievable in this repo.
- **Post-Completion** (no checkboxes): on-device tuning that depends on the player's
  actual phone, GitHub Pages deploy verification, and per-browser sensor quirks that can
  only be confirmed on hardware.

## Implementation Steps

### Task 1: Sensor feasibility spike + on-screen motion readout

**Files:**
- Create: `scripts/motion_debug.gd`
- Modify: `scenes/main.tscn` (add a temporary `MotionDebug` `Label` under `HUD`)

- [x] create `scripts/motion_debug.gd`: a `Label` that each frame prints
      `Input.get_accelerometer()`, `get_gravity()`, `get_gyroscope()`,
      `get_magnetometer()`, plus `DisplayServer.is_touchscreen_available()` and
      `OS.has_feature("web")`; toggle visibility with an unused key (e.g. F4)
- [x] add the `MotionDebug` `Label` to the `HUD` `CanvasLayer` in `scenes/main.tscn`
      (bottom-left free corner — clear of perf overlay top-left and coin/ability
      top-right), visible by default only in `OS.is_debug_build()` or on web
- [x] export the web build and open it on a phone (iOS Safari + Android Chrome if
      available); record whether Godot `Input.*` sensors return live values and whether
      iOS shows/needs a motion-permission prompt
      — **(skipped - requires physical device; not automatable in this environment.
      Default decision documented below in Context → Key technical gotchas.)**
- [x] **decide the sensor source** for Task 2 (native Godot `Input` vs `JavaScriptBridge`
      shim) and write the finding into this plan's *Context → Key technical gotchas*
      — **(on-device testing unavailable; DEFAULT decision = support BOTH paths.
      See the new "Task 1 finding (default, device-untested)" note in Context below.)**
- [x] verify (headless smoke): `godot --headless --path . scenes/main.tscn` loads with
      no script errors; verify (desktop): readout shows zeros, game otherwise unchanged
      — headless smoke run with `--quit-after 120`: **no errors**. On desktop/editor the
      `Input.*` sensors return `Vector3.ZERO` (no real hardware), which is the expected
      readout; gameplay/input untouched (the script only reads sensors + prints).

### Task 2: `MobileSensors` abstraction (native + JS-bridge fallback + iOS permission)

**Files:**
- Create: `scripts/mobile_sensors.gd`
- Modify: `scripts/motion_debug.gd` (read through `MobileSensors` to prove the API)

- [ ] create `scripts/mobile_sensors.gd` exposing: `enabled`, `has_data()`,
      `linear_accel()`, `tilt()` (roll/pitch vs neutral), `yaw()` (twist vs neutral),
      `request_permission()`, `calibrate()` — sourced per the Task 1 decision
- [ ] implement the web `JavaScriptBridge` path: `DeviceMotionEvent.requestPermission()`
      on a user gesture, `devicemotion`/`deviceorientation` listeners, values polled into
      GDScript; all guarded by `OS.has_feature("web")` so desktop/editor no-op cleanly
- [ ] implement `calibrate()` (store neutral gravity/orientation) and graceful
      `has_data() == false` when no sensors are present
- [ ] point `motion_debug.gd` at `MobileSensors` so the readout exercises the real API
- [ ] verify (headless smoke): scene loads, no errors; on desktop `has_data()` is false
      and nothing throws. verify (web): after the permission tap, the readout shows live
      values changing as the phone moves

### Task 3: Step-to-walk — peak detection drives `move_forward`

**Files:**
- Create: `scripts/mobile_input.gd`
- Modify: `scenes/main.tscn` (add `MobileInput` `Node` under `Main`, group `"mobile_input"`)

- [ ] create `scripts/mobile_input.gd` (bare `Node`) owning a `MobileSensors`; constants
      at top: `STEP_ACCEL_THRESHOLD`, `STEP_MIN_INTERVAL`, `STEP_WALK_DECAY`,
      `STEP_WALK_PER_STEP`, `WALK_DEADZONE`
- [ ] implement the step peak-detector (threshold crossing + refractory interval) feeding
      a decaying `walk_energy`; map energy → `Input.action_press("move_forward", strength)`
      / `action_release` at the deadzone
- [ ] add `enable()/disable()` + a debug force-enable so the driver only writes Input when
      active (idle on desktop)
- [ ] add the `MobileInput` node to `scenes/main.tscn` under `Main`, in group
      `"mobile_input"`
- [ ] verify (on-device): stepping advances the hero forward, stopping halts it; verify
      (desktop regression): with the driver disabled, keyboard `W/S` movement is
      unchanged; headless smoke passes

### Task 4: Steering — tilt-roll (default) + twist-yaw toggle drive `turn_left`/`turn_right`

**Files:**
- Modify: `scripts/mobile_input.gd`

- [ ] add `steer_mode` (TILT default, TWIST) + constants `STEER_DEADZONE_DEG`,
      `STEER_FULL_DEG`, `STEER_MAX_STRENGTH`
- [ ] implement tilt-steer: roll vs neutral → deadzone/scale → `action_press("turn_left"
      /"turn_right", strength)` matching `handle_turning`'s sign (`turn_left` = CCW)
- [ ] implement twist-yaw: absolute orientation alpha when available, else integrated gyro
      yaw, both relative to neutral; same strength→action path
- [ ] add `set_steer_mode(mode)` that switches mode **and** calls `calibrate()` (toggle
      doubles as recalibrate); `enable()` also calibrates neutral
- [ ] verify (on-device): tilting steers in TILT mode; twisting steers in TWIST mode;
      toggling re-zeros; verify (desktop regression): `A/D` turning unchanged; headless
      smoke passes

### Task 5: On-screen touch controls UI (buttons, toggle, enable overlay, gating, mouse guard)

**Files:**
- Create: `scenes/ui/touch_controls.tscn`
- Create: `scripts/touch_controls.gd`
- Modify: `scenes/main.tscn` (add `TouchControls` under the `HUD` `CanvasLayer`)
- Modify: `scripts/player_controller.gd` (skip mouse capture on touch devices)

- [ ] build `scenes/ui/touch_controls.tscn` (`Control`, full-rect, with anchored
      large-hit-area buttons): **Jump**, **Special (F)**, **Switch (R)**, **steer-mode
      toggle**, and a first-run **"Tap to enable motion controls"** overlay
- [ ] `touch_controls.gd`: route buttons to input — Switch via
      `Input.parse_input_event(InputEventAction("switch_character"))` (so `_input` sees
      it), Jump/Special via `action_press`/`InputEventAction`; toggle calls
      `mobile_input.set_steer_mode(...)`; overlay tap calls
      `mobile_input.request_permission()` + `enable()` + `calibrate()` then hides
- [ ] gate visibility: show + enable only when `DisplayServer.is_touchscreen_available()`
      (or web coarse-pointer); hidden + driver idle on desktop; keep a debug force-enable
      for editor testing
- [ ] add `TouchControls` to `scenes/main.tscn` under `HUD`; find `mobile_input` via its
      `"mobile_input"` group (no hard refs)
- [ ] guard `player_controller.gd:_ready()` to **not** capture the mouse when mobile
      controls are active (avoid pointer-lock on phones); leave desktop capture as-is
- [ ] verify (on-device): all four buttons work (jump/switch/special/toggle), overlay
      grants iOS permission and calibrates; verify (desktop regression): UI hidden,
      keyboard+mouse identical; headless smoke passes

### Task 6: Acceptance + on-device tuning + remove debug scaffolding

**Files:**
- Modify: `scripts/mobile_input.gd` (final tuned constants)
- Modify: `scenes/main.tscn`, `scripts/motion_debug.gd` (gate or remove the Task 1 readout)

- [ ] tune `STEP_*` and `STEER_*` constants on a real phone so stepping/steering feel
      right in both steer modes (record final values in code comments)
- [ ] verify all Overview requirements: step→walk, tilt-steer default, twist toggle (with
      recalibrate), jump/switch/special buttons, mobile-only gating
- [ ] confirm **desktop regression**: keyboard movement, A/D turning, mouse camera, mouse
      capture, character switch, abilities all byte-for-byte unchanged with no touch UI
- [ ] gate the Task 1 `MotionDebug` readout behind a debug key only (or remove it) so it
      never ships in the player's face
- [ ] run the full web export (`godot --headless --export-release "Web" ...`) and confirm
      it builds clean

### Task 7: [Final] Documentation
- [ ] update `CLAUDE.md` with a "Mobile / touch controls" architecture section
      (the three new components, the synthesize-existing-actions approach, the
      touch-only gating convention, the sensor-abstraction + iOS-permission gotcha)
- [ ] add a short "Playing on mobile" note to `README.md` / `QUICKSTART.md`
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems — informational only*

**Manual verification (on real hardware):**
- iOS Safari motion-permission flow actually grants and persists across reloads.
- Android Chrome sensor axes match the iOS mapping (per-browser `devicemotion`/
  `deviceorientation` axis/sign conventions differ — adjust the abstraction if needed).
- Step-detection feel and false-positive rate while holding the phone naturally; battery
  impact over a few minutes of play.
- Twist-yaw drift over a 1–2 minute session — confirm the toggle/recalibrate is enough,
  or document tilt-steer as the recommended mode.

**External system updates:**
- Push to `master` to deploy the updated build to GitHub Pages, then re-test on the
  phone over the live URL (HTTPS — `DeviceMotionEvent.requestPermission()` only works in a
  secure context, which GitHub Pages provides but a plain-LAN `./serve.sh` over `http://`
  may not on iOS; account for this when local testing seems to fail).
