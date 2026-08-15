# Game Feel: Coin Juice, Camera, Jump Arc, Danger Telegraph (bead godot-test1-afc.2)

## Overview
The game feels dead in the hand: every existing juice system (hit flash, shake, cooldown
dial) fires only on the rarest event (being bitten), while the per-second events (moving,
collecting coins, being hunted) have zero feedback. This plan adds feedback to all of them:
coin pickup pops, a snappy jump arc, a chased-by-croc telegraph (vignette + heartbeat), a
collision-aware eased camera with speed FOV, landing impact, a shorter respawn freeze with
blink invulnerability, ability punch, croc-crush feedback, horizontal acceleration +
footsteps, a life-lost heart pulse, and desktop-web click-to-capture.

Hard constraints from the bead:
- NO `GPUParticles3D` (web is gl_compatibility) — all particles are `scripts/ability_effect.gd` waves.
- NO `AudioStreamGenerator` — new sounds are baked `AudioStreamWAV` synthesis in `scripts/sound_manager.gd` (22050 Hz mono), same as every existing sound.
- Match the heavily-commented teaching style, explicit type hints, constants at top of each script.
- Do NOT touch `scripts/endless_terrain.gd`. In `scripts/piglet_crocodile_ai.gd` touch ONLY the crush branch of `_on_player_collision` (~line 858). A parallel executor owns those files.
- Keep mouse look 1:1 (only keyboard turning is eased).
- The first-person toggle (C key, `first_person` state in `player_controller.gd`) MUST keep working: SpringArm bypass + FOV kick in both views.

## Context (from discovery)
- `scripts/player_controller.gd` (1881 lines) — jump/gravity SECTION 2, camera SECTION 3, `_apply_view_mode()` (~:417) + `_first_person_eye_position()` (~:445), `_physics_process` STEP 1/2 (~:536-549) jump+gravity, STEP 8 (~:582-589) direct velocity assignment, `_process` (~:598) camera shake writes `camera.position`, `animate_walking` (~:1074) walk sine, `animate_landing` (~:1193) one-frame `position.y = -0.1`, `hit_by_crocodile` (~:1274) invulnerability guard, `_respawn_in_place` (~:1321), `is_respawning` branch (~:502), `try_activate_ability` (~:1638) silent cooldown return, `_ability_windman/_primm/_teibi` (~:1668-1773), `_apply_teibi_scale` (~:1791), `_spawn_ability_effect` (~:1816), `RESPAWN_GRACE_DURATION = 5.0` (~:187).
- `scenes/player.tscn` — `CameraPivot` (y=1.5) → `Camera3D` at position (0,2,8) with baked −15° pitch.
- `scripts/crocodile_lod_manager.gd` — `_scan_crocodiles()` already iterates every croc ~9 Hz with the player position in hand; crocs expose `is_chasing: bool` (piglet_crocodile_ai.gd:168) and `DETECTION_RADIUS = 15.0`.
- `scripts/sound_manager.gd` — `_build_wav()`, `_synth_*` bakers, `_play_oneshot()`, `get_loop_player(name)` (lazily creates a dedicated looping AudioStreamPlayer), `is_unlocked()` web-gesture gate. The wind loop shows the LOOP_FORWARD + loop_end recipe (~:164-167).
- `scripts/hit_flash.gd` — hardcodes red at `_ready` (`color = Color(0.7, 0.0, 0.0, 0.0)`), `flash()` takes no args.
- `scripts/coin.gd` — `_on_body_entered` (~:130) already plays the pitch-jittered blip via the sound manager; just needs the gold wave before `queue_free()`.
- `scripts/coin_hud.gd` — a bare `Label`, no pop.
- `scripts/lives_hud.gd` — `_draw()`-based hearts, redraw-on-change only.
- `scripts/ability_hud.gd` — `_draw()`-based dial; has NO group registration yet.
- `scripts/piglet_crocodile_ai.gd` `_on_player_collision` crush branch (~:857-861): bare `queue_free()`.
- `scenes/main.tscn` — HUD `CanvasLayer` holds HitFlash, CoinHUD, LivesHUD, AbilityHUD, RespawnLabel, PerfOverlay etc.

## Development Approach
- **Testing approach**: NO unit tests (there is no test suite in this repo at all). The only
  automatable check is the headless import/run smoke: `godot --headless --path . --import`
  then `godot --headless --path . --quit-after 3` must exit clean (no script errors).
- Complete each task fully before moving to the next.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Desktop keyboard play changes here are INTENTIONAL cross-platform polish (jump arc, camera,
  acceleration). This is the sanctioned exception to the "desktop byte-for-byte" convention —
  but mouse look stays 1:1 and the touch/mobile pipeline is untouched.

## Testing Strategy
- **Unit tests**: none.
- **Integration tests**: none possible (pure Godot project, no suite). Headless smoke run per task.
- Manual verification list lives in Post-Completion.

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: New baked sounds in sound_manager (footstep, heartbeat loop, buzz, crunch)
Later tasks call these, so they land first. All follow the existing baker pattern:
constants at top, `_synth_*()` returning `PackedFloat32Array`, `_build_wav()` in `_ready()`,
`play_*()` through `_play_oneshot()` (which already enforces the web-unlock gate).
- [x] `scripts/sound_manager.gd`: add `_synth_footstep()` — a very short (~0.06 s) low-passed noise tap (soft "pat"), volume ~−14 dB; `play_footstep()` with a per-call `pitch_scale` jitter parameter-free random (like `play_coin`)
- [x] add `_synth_buzz()` — a short (~0.15 s) low square-wave buzz (~90 Hz, fast decay), volume ~−10 dB; `play_buzz()` (used by the blocked-ability press)
- [x] add `_synth_crunch()` — a short (~0.2 s) harsh noise burst with fast decay (croc crush), volume ~−8 dB; `play_crunch()`
- [x] add `_synth_heartbeat()` — ONE "lub-dub" cycle (~0.8 s: two low sine thumps ~55 Hz with fast decay, the second slightly quieter, then silence to pad the loop) built as a LOOP_FORWARD `AudioStreamWAV` exactly like the wind loop recipe (loop_begin 0, loop_end = data.size()/2); in `_ready()` create the dedicated loop player, assign the stream, store it as `_loop_players["heartbeat"]` (do NOT play it — the danger vignette drives play/stop/pitch/volume via `get_loop_player("heartbeat")` + `is_unlocked()`)
- [x] headless smoke: import + `--quit-after 3` clean

### Task 2: hit_flash color parameter + coin pickup juice
- [x] `scripts/hit_flash.gd`: give `flash()` a color argument with the current red as default — `func flash(flash_color: Color = Color(0.7, 0.0, 0.0)) -> void:` — that sets `color = Color(flash_color.r, flash_color.g, flash_color.b, 0.0)` before popping `current_alpha` (existing `player_controller.hit_by_crocodile` caller keeps working unchanged)
- [x] `scripts/coin.gd` `_on_body_entered`: before `queue_free()`, spawn a gold `ability_effect.gd` wave at the coin's `global_position` — bare `MeshInstance3D` + `set_script(preload(...))`, parented to the COIN'S PARENT (the chunk — same self-freeing pattern as `player_controller._spawn_ability_effect`), `setup(Color(1.0, 0.85, 0.2, 0.5), 1.2, 0.25)`
- [x] `scripts/coin_hud.gd`: scale-pop on pickup — track last-seen `coins_collected`; when it increases set `scale = Vector2.ONE * 1.25` (with `pivot_offset = size * 0.5` so it pops around its centre), and every `_process` frame lerp `scale` back toward `Vector2.ONE` (~10/s); keep the existing text logic untouched
- [x] headless smoke clean

### Task 3: Jump arc retune + coyote time + jump buffer
Apex invariant: `v²/2g` stays exactly 3.6125 m (10.2²/28.8), so the 2.5 m block level
design and ≤3 m climb steps at player_controller.gd:47-49 are untouched; airtime halves
(2.83 s → 1.42 s). Crocs drop chase when the player is airborne, so shorter airtime means
crocs hold aggro more — intended difficulty change per the bead.
- [x] `scripts/player_controller.gd`: `JUMP_VELOCITY` 5.1 → 10.2; `gravity` 3.6 → 14.4; update BOTH teaching comment blocks (SECTION 2) to explain the new arcade-snappy arc and the preserved apex math
- [x] `WINDMAN_GRAVITY_FACTOR` 0.45 → 0.1125 (14.4 × 0.1125 = 1.62 — byte-identical glide gravity to the old 3.6 × 0.45, so Windman's Air Rush feel is preserved exactly; say so in the comment)
- [x] add `const COYOTE_TIME: float = 0.12` and `const JUMP_BUFFER_TIME: float = 0.12` (SECTION 2) with vars `coyote_timer` / `jump_buffer_timer`; each physics frame: `coyote_timer = COYOTE_TIME` while `is_on_floor()`, else tick down; on `Input.is_action_just_pressed("jump")` set `jump_buffer_timer = JUMP_BUFFER_TIME`, else tick down
- [x] replace the jump check at STEP 2 (~:546): fire when `jump_buffer_timer > 0.0 and (is_on_floor() or coyote_timer > 0.0) and not is_giant`; on firing zero BOTH timers (prevents a coyote double-jump) and keep the existing `_sfx("play_jump")`
- [x] headless smoke clean

### Task 4: Horizontal acceleration + footstep events
- [x] `scripts/player_controller.gd` STEP 8 (~:582-585): replace the direct `velocity.x/z = planar_velocity.x/z` assignment with `move_toward` toward the target at `const MOVE_ACCELERATION: float = 40.0` m/s² (`velocity.x = move_toward(velocity.x, planar_velocity.x, MOVE_ACCELERATION * delta)`, same for z); the no-input friction branch stays as-is
- [x] `animate_walking` (~:1074): footstep events from the walk-sine zero crossings — track the sign of `sin(time_factor)` in a member var (`_last_walk_sine_sign`); on a sign flip (each flip = one foot planting) call `_sfx("play_footstep")` — but only while `is_on_floor()`; rate scales with `is_running` automatically because `time_factor` already advances 1.5× when running
- [x] reset `_last_walk_sine_sign` state cleanly when not walking so a first step after idle doesn't mis-fire (reset to a 0 sentinel in `update_character_animation` whenever the walking state isn't active; sidestep deliberately keeps the cycle history)
- [x] headless smoke clean

### Task 5: Camera rig — SpringArm3D, shake via offsets, FP bypass, eased keyboard turn, speed FOV
The trickiest task. **SpringArm3D gotcha: it OVERRIDES its Node3D children's local position
every physics frame** (slides them along its local Z by the clamped hit length). So the
camera's `position` can no longer be written by anyone — the shake and the FP eye placement
must move OFF `camera.position`:
- Shake moves to `Camera3D.h_offset` / `v_offset` (view-space offsets, unaffected by the arm; work identically in FP).
- FP eye placement moves to the ARM: in FP the arm gets `position = eye offset`, `rotation = 0`, `spring_length = 0` (camera slides to the arm origin = the eyes; zero length ⇒ no collision cast ⇒ "bypass collision in FP" for free).
- [x] `scenes/player.tscn`: insert `SpringArm3D` (name `CameraArm`) under `CameraPivot`; move `Camera3D` under it. Arm: `position = (0, 0, 0)`, `rotation_degrees.x = -14` (the old camera offset (0,2,8) sits 14.04° above the pivot's horizontal), `spring_length = 8.25` (|(0,2,8)| ≈ 8.246), `margin = 0.25`. Camera: identity position, keep only the residual pitch `rotation_degrees.x = -1` (−15° baked pitch minus the arm's −14°) so the shipped framing is visually preserved
- [x] `scripts/player_controller.gd`: add `@onready var camera_arm: SpringArm3D = $CameraPivot/CameraArm`; in `_ready()` call `camera_arm.add_excluded_object(get_rid())` so the arm never collides with the player's own capsule; cache the arm's scene transform + spring_length (replaces `third_person_camera_transform` / `camera_rest_position` caching — remove or repurpose those)
- [x] rewrite `_apply_view_mode()`: FP ⇒ `camera_arm.spring_length = 0.0`, `camera_arm.transform = Transform3D(Basis.IDENTITY, _first_person_eye_position())`, `camera.rotation = Vector3.ZERO` (kill the residual pitch so pivot pitch alone is the look pitch), hide model; 3P ⇒ restore cached arm transform + length + camera residual pitch, show model. `_first_person_eye_position()` stays as-is (arm-local == pivot-local when the arm basis is identity). Keep the `_apply_teibi_scale`/`set_active_character` re-apply calls working
- [x] rewrite the shake in `_process`: drive `camera.h_offset` / `camera.v_offset` with the same decaying random ± `shake_amount`, settling both to 0.0 — delete the `camera.position` / `camera_rest_position` writes entirely (update every comment that references the old mechanism, including the FP section's "shake gotcha" note)
- [x] eased keyboard turn: in `handle_turning`, after `rotate_y(turn_delta)`, subtract the same `turn_delta` from a new `camera_yaw_lag: float` member; each frame apply `camera_pivot.rotation.y = camera_yaw_lag` and decay `camera_yaw_lag = lerpf(camera_yaw_lag, 0.0, minf(1.0, CAMERA_TURN_EASE * delta))` with `const CAMERA_TURN_EASE: float = 10.0` — the camera trails a keyboard turn and eases in, while MOUSE turns (which rotate the body in `_input` without touching the lag) stay 1:1. Zero the lag in `reset_position()` (which already resets pivot rotation)
- [x] speed-scaled FOV: `const FOV_BASE: float = 75.0`, `const FOV_MAX: float = 97.0`; each `_process` frame compute horizontal speed `Vector2(velocity.x, velocity.z).length()`, map `WALK_SPEED → WINDMAN_AIR_SPEED` onto `FOV_BASE → FOV_MAX` (clamped), add the transient `fov_punch` (declared now at 0.0; Task 7 drives it), and ease `camera.fov` toward the target (~5/s lerp). Applies in BOTH views (a Camera3D property, transform-independent)
- [x] headless smoke clean + verify in comments that FP toggle, Teibi eye height, and bite shake all still route correctly

### Task 6: Landing impact — squash, dust, shake by impact speed
- [x] `scripts/player_controller.gd`: capture the fall speed each airborne physics frame (`_fall_speed = -velocity.y` while `velocity.y < 0`, BEFORE `move_and_slide` zeroes it on touchdown)
- [x] in `update_character_animation`, on the floor transition (where the land thud already fires): start `land_squash_timer = LAND_SQUASH_DURATION` (`const := 0.18`) and store the impact strength `land_squash_strength = clampf(_fall_speed / 10.0, 0.2, 1.0)`
- [x] replace `animate_landing`'s one-frame `character_body.position.y = -0.1` (~:1202) with an eased squash applied AFTER the animation branch chain in `update_character_animation` (so the walk bob at :1105 / idle breathe at :1234 can't overwrite it): a `sin(progress * PI)` arc over the timer drives `character_body.position.y -= dip` (dip ≈ 0.14 × strength) and a slight container scale squash `character_container.scale = base * Vector3(1 + 0.2*k, 1 - 0.3*k, 1 + 0.2*k)` where `base` is the current Teibi scale (add a small `_current_teibi_scale()` helper reading `teibi_size_state`); skip the scale part while the Task-7 Teibi tween is running (`_teibi_tween` member declared now, assigned by Task 7)
- [x] above `LAND_HARD_SPEED := 4.0` m/s impact: add a small shake (`shake_amount = maxf(shake_amount, 0.12)`) and a flat dust ring — `_spawn_ability_effect(feet position, Color(0.75, 0.7, 0.6, 0.45), 1.6, 0.3)` (the existing land thud in `_sfx("play_land")` already covers audio; keep it firing on every landing)
- [x] headless smoke clean

### Task 7: Ability punch — blocked-press feedback, Teibi tween, Primm trail, Windman FOV punch
- [x] `scripts/ability_hud.gd`: `add_to_group("ability_hud")` in `_ready()`; add `flash_blocked()` — sets a `_blocked_timer = 0.15` that `_process` ticks down (forcing `queue_redraw` while active) and `_draw` renders the cooldown arc + F key in red (`Color(1.0, 0.25, 0.2)`) while it runs
- [x] `scripts/player_controller.gd` `try_activate_ability` cooldown branch (~:1647): instead of the silent `return`, call `flash_blocked()` on the `"ability_hud"` group node (null-safe `has_method` guard) and `_sfx("play_buzz")`
- [x] Teibi scale tween: in `_apply_teibi_scale`, tween the VISUAL `character_container.scale` to the target over 0.25 s with overshoot (`create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)`), killing any previous scale tween first (store it in a member `_teibi_tween`); the COLLISION shape keeps its instant snap (physics must never lag the visual — say so in the comment). First-person `_apply_view_mode()` re-seat stays instant as today
- [x] Primm blink trail: in `_ability_primm` after the target is found, spawn 3 small staggered flashes along the path — `for i in range(3): _spawn_ability_effect(global_position.lerp(target, (i + 1) / 4.0), Color(0.45, 0.5, 1.0, 0.4), 1.0, 0.25, i * 0.05)` — between the existing departure and arrival flashes
- [x] Windman FOV punch: add `fov_punch: float` member; `_ability_windman` sets `fov_punch = 12.0`; the Task-5 FOV code adds it to the target and decays it (~`fov_punch = maxf(0.0, fov_punch - 30.0 * delta)`)
- [x] headless smoke clean

### ⚠️ Resumption note (session limit interrupted; master merged in)
Tasks 1–7 are DONE and verified in code (commit bf3785c was mislabelled "wip" — all four
Task-7 items actually landed: blocked-press flash + buzz, Teibi TRANS_BACK tween, Primm
3-flash trail, Windman `fov_punch`). Resume at Task 8. Since the plan was written,
`origin/master` merged in **boss crocodiles (PR #15)** and the rendering PR (#14), so:
- **All line numbers below are stale — grep for the code, don't trust the `~:NNN`.**
- `piglet_crocodile_ai.gd` `_on_player_collision` now has a **boss early-return block ABOVE
  the giant-Teibi crush block** (`if is_boss: … return`, ~:937). Task 10 must edit ONLY the
  crush block *below* it and leave the boss guard byte-for-byte intact.
- Bosses are in the same `"crocodile"` group and expose `is_chasing`, so Task 8's danger
  telegraph picks them up automatically — no boss-specific code needed.
- `lives_hud.gd` no longer has its own `MAX_LIVES`; it reads the pip total from the player
  (`maxi(player.MAX_LIVES, player.lives)`) because coins can grant up to `LIVES_CAP` (5)
  hearts. Task 10's heart pulse must keep using that player-derived total.
- Task 12 must update the CLAUDE.md text as it stands AFTER the merge (it now documents
  `RESPAWN_GRACE_DURATION = 5.0`, the old camera shake gotcha, and gravity 3.6 — all three
  are now wrong and are exactly what Task 12 fixes).

### Task 8: Danger telegraph — LOD manager publishes nearest chasing croc, vignette + heartbeat
- [x] `scripts/crocodile_lod_manager.gd`: inside the existing `_scan_crocodiles()` loop (zero extra passes), track the minimum `dist_sq` among crocs whose `is_chasing` is true (guard with `"is_chasing" in croc`); after the loop publish `sqrt` of it (or `INF` when none) to the `"danger_vignette"` group node via a null-safe `set_danger_distance(d)` call — group-based, no hard refs, matching the manager's conventions. Chasing crocs are always awake (SIM_RADIUS 45 ≫ DETECTION_RADIUS 15), so the scan sees every chaser
- [x] new `scripts/danger_vignette.gd` (a `Control` in group `"danger_vignette"`, `MOUSE_FILTER_IGNORE`): a full-rect red screen-EDGE vignette — one `ColorRect` child with a tiny `canvas_item` shader built in code (`Shader.new()` + `code` string: radial distance from centre → alpha ramp toward the edges, tinted `vec3(0.8, 0.05, 0.05)`) — kept deliberately cheap (one fullscreen 2D quad). Danger level `t = clampf(1.0 - distance / 15.0, 0.0, 1.0)` (15 = croc DETECTION_RADIUS); ease the displayed alpha toward `t * MAX_ALPHA` (~0.45) each frame so scans at 9 Hz don't step visibly; fully transparent (and shader cost skipped via `visible = false`) when no chaser
- [x] heartbeat: the same `danger_vignette.gd` `_process` drives the sound manager's loop — fetch via group `get_loop_player("heartbeat")`, `play()` when danger appears AND `is_unlocked()`, `stop()` when it clears; scale `pitch_scale` 1.0 → 1.8 and `volume_db` −18 → −6 with `t` as the croc closes 15 m → 0
- [x] `scenes/main.tscn`: add the `DangerVignette` node under the HUD `CanvasLayer` (full-rect anchors), BELOW HitFlash in the stack so a bite flash still reads on top
- [x] headless smoke clean

### Task 9: Respawn split — 1.5 s frozen + 2.5 s mobile blinking invulnerability
This is a state split, not new logic; the invulnerability guard must stay airtight.
- [x] `scripts/player_controller.gd`: `RESPAWN_GRACE_DURATION` 5.0 → 1.5; add `const RESPAWN_BLINK_DURATION: float = 2.5`, `const RESPAWN_BLINK_CADENCE: float = 0.1`, and `var respawn_blink_timer: float = 0.0`
- [x] when the frozen `is_respawning` window ends (~:507): set `respawn_blink_timer = RESPAWN_BLINK_DURATION` (keep the final `clear_nearby_crocodiles` sweep); the player then moves NORMALLY — the blink phase adds no freeze branch
- [x] tick `respawn_blink_timer` down each physics frame (e.g. alongside `_update_ability_timers`); while it runs, toggle `character_container.visible` on the 0.1 s cadence (`fmod(respawn_blink_timer, 0.2) < 0.1`) — but ONLY when `not first_person` (FP already hides the model); when it hits 0, restore visibility through `_apply_view_mode()` (idempotent, respects the current view)
- [x] extend the invulnerability guard in `hit_by_crocodile` (~:1286) to `if is_caught or is_respawning or is_game_over or respawn_blink_timer > 0.0: return` — and zero `respawn_blink_timer` (+ restore visibility via `_apply_view_mode()`) in `restart_game()` and `reset_position()` so state never leaks across a restart
- [x] update the respawn countdown label text/comments for the shorter window (one-decimal countdown readout so the 1.5 s window visibly ticks)
- [x] headless smoke clean

### Task 10: Croc crush feedback + life-lost heart pulse + click-to-capture
- [ ] `scripts/piglet_crocodile_ai.gd` `_on_player_collision` crush branch ONLY (~:857-861): before freeing — squash (tween `scale.y` to ~15% over 0.12 s, `tween_callback(queue_free)` so the tween owns the free; a tween dies with its node, so chunk unload stays safe), spawn a small dust puff `ability_effect` wave at the croc's position parented to the croc's PARENT (the chunk — outlives the croc), fire `play_crunch()` via the `"sound_manager"` group (null-safe), nudge the player's shake (null-safe: `if "shake_amount" in player: player.shake_amount = maxf(player.shake_amount, 0.15)`), and guard re-entry (`set_physics_process(false)` + remove from `"crocodile"` group) so the dying croc can't crush-trigger twice
- [ ] `scripts/lives_hud.gd`: when `lives` DECREASES, record the lost heart's index and start `_pulse_timer = 0.6`; while it runs, `_process` forces `queue_redraw` and `_draw` renders that heart oversized (~1.4× easing back to 1×) in a bright flash colour fading to `EMPTY_COLOR` — so the heart visibly dies instead of just not being drawn
- [ ] `scripts/player_controller.gd` `_input`: desktop-web click-to-capture — on `InputEventMouseButton` pressed, if `Input.mouse_mode != MOUSE_MODE_CAPTURED and not MobileSensors.is_touch_session() and not is_game_over`, set `MOUSE_MODE_CAPTURED` (browsers reject the `_ready()` capture outside a user gesture, so every desktop-web load currently has a dead camera until the undiscoverable ESC recapture)
- [ ] new `scripts/capture_hint.gd` (a `Label`, added under HUD in `scenes/main.tscn`, centred near the bottom): shows "Click to look around" and self-manages visibility in `_process` — visible only when NOT a touch session AND `Input.mouse_mode != MOUSE_MODE_CAPTURED` AND the game-over screen isn't up (poll the player's `is_game_over` via the `"player"` group, null-safe); zero coupling, no signals needed
- [ ] headless smoke clean

### Task 11: Verify acceptance criteria
- [ ] re-read the bead's acceptance list and confirm every item is implemented: coin pop (visual+HUD+audio), camera no longer clips (SpringArm), keyboard turn eased, mouse 1:1, FOV kicks when fast, jump airtime ~1.42 s with apex 3.61 m (2.5 m blocks jumpable — verify the math in SECTION 2 comments), vignette+heartbeat before a bite lands, respawn control back in 1.5 s + 2.5 s blink invulnerability, blocked F press flashes+buzzes, croc crush feedback, footsteps, heart pulse, click-to-capture + hint
- [ ] confirm `piglet_crocodile_ai.gd` diff touches ONLY the crush branch; confirm `endless_terrain.gd` is untouched
- [ ] confirm no `GPUParticles3D`, no `AudioStreamGenerator`, no new asset files anywhere in the diff
- [ ] `godot --headless --path . --import` then `godot --headless --path . --quit-after 3` — both exit clean with no script errors
- [ ] headless web export builds: `mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html` (skip gracefully if export templates are missing in this environment — note it as a deferral)

### Task 12: Update documentation
- [ ] `CLAUDE.md`: update the affected sections — jump/gravity convention note (gravity is now 14.4 with the preserved 3.61 m apex), the camera rig (SpringArm3D + h/v_offset shake + FOV, and how FP bypasses the arm), the respawn contract (1.5 s frozen + 2.5 s blink phases, the extended invulnerability guard), the danger telegraph (LOD manager publish + vignette/heartbeat), the new sound manager bakers, and the hit_flash color arg

## Technical Details
- Apex math: `10.2² / (2 × 14.4) = 3.6125 m` (old: `5.1² / (2 × 3.6) = 3.6125 m`) — identical. Airtime `2v/g`: 2.833 s → 1.417 s.
- Windman glide gravity: old `3.6 × 0.45 = 1.62`; new `14.4 × 0.1125 = 1.62` — identical.
- SpringArm3D overrides children's local position each physics frame — nothing else may write `camera.position`; shake uses `h_offset`/`v_offset`, FP moves the arm itself.
- Heartbeat loop stream must set `loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = data.size() / 2` (frames, not bytes) — same recipe as the wind loop.
- All group lookups null-safe with `has_method`/`in` guards, matching project convention.

## Post-Completion
**Manual verification** (needs a real browser / desktop run — not automatable here):
- Play the web build on desktop: click captures the mouse, hint label hides, camera never clips through blocks when backing into them, FOV kicks during Windman Air Rush.
- Get chased: vignette + heartbeat ramp as the croc closes; blink invulnerability visibly protects for ~2.5 s after the 1.5 s freeze.
- Verify 2.5 m blocks are still comfortably jumpable with the new arc.
- Audio balance pass on the new bakers (footstep/buzz/crunch/heartbeat volumes are starting guesses).
