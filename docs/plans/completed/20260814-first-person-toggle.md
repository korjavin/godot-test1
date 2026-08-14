# First-Person View Toggle on C (bead godot-test1-afc.5)

## Overview
- Pressing **C** toggles the camera between the existing 3rd-person view and a
  first-person view from the active character's eyes; pressing C again returns.
- Reuses the **existing** camera rig — `$CameraPivot` (y=1.5) > `$CameraPivot/Camera3D`
  (local pos (0,2,8), baked −15° pitch, see `scenes/player.tscn`). **NO second camera.**
- View mode is a player *preference*: it survives respawn, restart, and character
  switches. The character model is hidden in FP so no self-geometry is visible.

## Context (from discovery)
- `scripts/player_controller.gd` (~1800 lines) is the only script to change besides
  `project.godot` and (optionally) `scripts/touch_controls.gd`.
- Camera rig facts (verified in code):
  - `camera_pivot` / `camera` are `@onready` refs (lines ~74–75). Mouse-look yaws the
    **body** and pitches the **pivot** (`_input`, clamped ±60°). The Camera3D itself
    carries a baked −15° pitch in its scene transform.
  - **Bite shake** (`_physics_process` ~lines 531–546) offsets `camera.position` from
    `camera_rest_position` and snaps back to it — so `camera_rest_position` MUST track
    whichever view mode is active, or the shake will teleport the camera to the wrong view.
  - `camera_rest_position` is captured once in `_ready()` (~line 337).
- **Character switching is visibility-based now**: all character instances are preloaded
  under `$CharacterModel` (`character_container`); `set_active_character()` flips each
  instance's `visible` flag. Hiding the **container** node is therefore orthogonal and
  survives switches — but re-apply defensively after a switch anyway (cheap, future-proof).
- **Teibi resize**: `_apply_teibi_scale(s)` (~line 1721) scales `character_container` and
  `collision_shape`, repinning the capsule bottom via `collision_base_y` /
  `collision_half_height`. FP eye height must track `s` (small Teibi = low eyes,
  giant = high). The current scale is readable as `collision_shape.scale.y`.
- `reset_position()` (~line 1387) zeroes pivot rotation but never touches the camera's
  own transform — so FP persists across respawn/restart automatically as long as nothing
  resets the new `first_person` flag. `restart_game()` funnels through `reset_position()`.
- `project.godot` `[input]` (lines 38–94): every action uses the same serialized
  `InputEventKey` format with `physical_keycode` + matching lowercase `unicode`.
  Physical keycode **67 (C, unicode 99)** is unused — verified.
- `scripts/touch_controls.gd` `_build_ui()` builds all buttons in code; `_fire_action()`
  → `Input.parse_input_event(InputEventAction)` (press now, release queued for the next
  `_process` frame) works for BOTH `_input()`-handled and polled actions — the player
  side here will poll with `is_action_just_pressed`, which `parse_input_event` satisfies.
- **HARD BOUNDARY**: do NOT edit `endless_terrain.gd`, any crocodile file, or
  `main.tscn` — a parallel executor owns them. `scenes/player.tscn` needs no edit
  (all camera moves are runtime). Never hand-edit `.gd.uid` files.
- Style landmines: teaching-density comments, explicit type hints everywhere, tunable
  constants at the top of the script (SECTION 3 area for camera constants).

## Development Approach
- **Testing approach**: NO unit tests (no test infra exists in this project). Verification
  is the headless import + short headless run, exactly as CI does.
- Complete each task fully before moving to the next.
- Make small, focused changes — keep the diff scoped to the camera/view concern.
- **CRITICAL: update this plan file when scope changes during implementation**
- Maintain backward compatibility: desktop 3rd-person play must be byte-for-byte
  identical until C is pressed.

## Testing Strategy
- **Unit tests**: none.
- **Integration tests**: none — no boundary here that a test could guard better than the
  headless run (`godot --headless --path . --import` then `--quit-after 3`, both clean).
- **E2E tests**: none exist; do not create any.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix
- Keep plan in sync with actual work done

## Implementation Steps

### Task 1: Add the "toggle_camera" input action
- [x] In `project.godot` `[input]`, add a `toggle_camera` action bound to physical C:
      copy the exact serialized `InputEventKey` format of the neighbouring actions
      (e.g. `special_ability`), with `"physical_keycode":67` and `"unicode":99`,
      placed after `special_ability` (keep `"deadzone": 0.5` like the others).
- [x] Update the CLAUDE.md "Conventions" input-action list to include `toggle_camera`
      (it enumerates the actions; keep it accurate).

### Task 2: First-person state + toggle in player_controller.gd
- [x] Add constants near the other camera constants (SECTION 3, with teaching comments):
      `FIRST_PERSON_EYE_HEIGHT: float = 1.65` (eye Y above the feet at normal scale —
      just under the ~1.8 m character head top) and
      `FIRST_PERSON_FORWARD_OFFSET: float = 0.2` (small −Z nudge so face/nose geometry
      never clips even if a model is ever left visible).
- [x] Add state near the other camera vars: `var first_person: bool = false` and
      `var third_person_camera_transform: Transform3D` cached from `camera.transform`
      in `_ready()` (right where `camera_rest_position` is captured today).
- [x] Add `_set_first_person(enabled: bool) -> void` that sets the flag and calls a new
      `_apply_view_mode() -> void` which does ALL the work idempotently:
      - **FP**: `camera.transform = Transform3D(Basis.IDENTITY, _first_person_eye_position())`
        — identity basis zeroes the baked −15° pitch so the pivot's pitch alone is the
        look pitch; hide the model (`character_container.visible = false`).
      - **3rd person**: restore `camera.transform = third_person_camera_transform`;
        show the model (`character_container.visible = true`).
      - **Both**: refresh `camera_rest_position = camera.position` so the bite-shake
        snap-back targets the current view's rest spot (see Context — this is the trap).
- [x] Add `_first_person_eye_position() -> Vector3` helper: local position under the
      pivot = `Vector3(0.0, scale_y * FIRST_PERSON_EYE_HEIGHT - camera_pivot.position.y,
      -FIRST_PERSON_FORWARD_OFFSET * scale_y)` where
      `scale_y := collision_shape.scale.y if collision_shape else 1.0` — deriving from
      the collision shape means Teibi's small/giant forms move the eyes automatically.
- [x] Poll the toggle in `_physics_process` alongside the other
      `Input.is_action_just_pressed` polls (jump/special):
      `if Input.is_action_just_pressed("toggle_camera"): _set_first_person(not first_person)`.
      Polling (not `_input`) keeps it friendly to synthesized touch input per the
      CLAUDE.md gotcha. Teaching comment explaining the choice.
- [x] Mouse-look needs NO change: it only touches body yaw + pivot pitch, which drive
      both views identically. Verify the ±60° pitch clamp reads fine in FP (it does —
      leave the clamp constants alone).

### Task 3: Interactions — Teibi scale, character switch, respawn persistence
- [x] At the end of `_apply_teibi_scale()`, if `first_person`, re-run `_apply_view_mode()`
      so eye height (and shake rest position) track the new capsule scale immediately.
- [x] At the end of `set_active_character()`, if `first_person`, re-run `_apply_view_mode()`
      — per-instance visibility toggling makes the container-hide survive switches
      already, but this is the cheap defensive re-apply the bead asks for (and the
      `_revert_teibi_to_normal()` inside the switch already funnels through the
      Teibi hook above; idempotent, so double-apply is harmless).
- [x] Confirm `reset_position()` / `restart_game()` / `_respawn_in_place()` do NOT touch
      `first_person` or `camera.transform` — the view mode is a preference and must
      survive both. (If any of them mutate `camera` beyond the pivot rotation reset,
      route them through `_apply_view_mode()` instead of resetting.)
- [x] The caught freeze/flash/shake path needs no change: the red flash + HUD are
      CanvasLayer (unaffected), and the shake now offsets from the refreshed
      `camera_rest_position` in either mode. Leave it as is.

### Task 4: Touch view-toggle button (small, optional but trivial here)
- [x] In `scripts/touch_controls.gd` `_build_ui()`, add a small "View" toggle button
      next to the existing steer-mode toggle (top-centre), wired through the existing
      `_fire_action("toggle_camera")` path — `parse_input_event` sets the polled action
      state, which the player's `is_action_just_pressed` poll sees exactly once.
      Match the steer-toggle's styling/sizing; keep it inside the same gating so
      desktop is untouched.

### Task 5: Verify acceptance criteria
- [x] `godot --headless --path . --import` completes without errors
- [x] `godot --headless --path . --quit-after 3` runs clean (no script errors)
- [x] grep-verify: no diffs in `scripts/endless_terrain.gd`, crocodile scripts, or
      `scenes/main.tscn` (hard boundary) — checked against this plan's commit range
      (9cd2f9d..HEAD): only CLAUDE.md, project.godot, player_controller.gd,
      touch_controls.gd, and this plan file changed
- [x] re-read the diff for style: teaching comments present, explicit type hints,
      constants at top, no `.gd.uid` files hand-edited

### Task 6: [Final] Update documentation
- [x] Add a short subsection to CLAUDE.md under the player section describing the
      first-person toggle (C / `toggle_camera`), the reused-rig design (no second
      camera), the hidden-model rule, the eye-height-tracks-Teibi rule, and the
      `camera_rest_position` shake gotcha — matching the file's existing density.
- [x] Note for the PR body (do not code it): the queued game-feel bead
      godot-test1-afc.2 will later add a SpringArm3D + FOV kick to this same rig and
      must respect `first_person` mode. (Also recorded as the closing bullet of the
      new CLAUDE.md subsection so it isn't lost if the PR body is rewritten.)

## Technical Details
- FP camera local transform under the pivot: identity basis (pivot pitch = look pitch;
  the baked −15° third-person pitch must NOT leak into FP), position
  `(0, s*1.65 − 1.5, −0.2*s)` where `s` is the Teibi capsule scale and 1.5 is the
  pivot's fixed local height. At normal scale that's eyes at world y≈1.65 with a 0.2 m
  forward nudge.
- 3rd-person restore is the *cached scene transform*, not a rebuilt one — byte-identical
  to the shipped view.
- `_apply_view_mode()` is deliberately idempotent so it can be re-run from the Teibi
  hook and character switch without state tracking.

## Post-Completion
*No checkboxes — manual/external items.*

**Manual verification** (needs a real desktop build / browser):
- C toggles smoothly; mouse-look identical in both modes; no self-geometry visible in
  FP for all 4 characters (switch with R while in FP); Teibi F-cycle moves the eyes
  down/up; die once (view survives respawn) and game-over → Play Again (view survives
  restart); bite shake looks right in FP.
- Touch: the View button toggles on a phone; web export builds in CI.
