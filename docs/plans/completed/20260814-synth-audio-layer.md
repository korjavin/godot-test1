# Synthesized Audio Layer (no asset files)

## Overview
- The game is completely silent — zero audio code or assets anywhere in the repo. A silent browser game feels dead.
- Add a minimal synthesized audio layer: a single `scripts/sound_manager.gd` Node that **generates every sound in code** as `AudioStreamWAV` buffers at `_ready()` (sine/square/noise with simple envelopes) — **no .wav/.ogg asset files**, so the web build size is unchanged.
- Sounds: coin pickup blip (short chirp, slight random pitch per pickup), jump, landing thud, ability whoosh, crocodile bite/caught sting, game-over sting, and a very quiet looping ambient wind bed.
- Hook points are **one-liners** in existing scripts (`coin.gd`, `player_controller.gd`, `touch_controls.gd`), finding the manager via the `"sound_manager"` group with a null-safe lookup — the repo's group-discovery convention (like `hit_flash`, `game_over_ui`, `mobile_input`).
- Web gotcha handled: mobile browsers block audio until a user gesture. The manager stays silent until `unlock_audio()` fires (first input event, plus an explicit call from the touch UI's enable-overlay tap).

## Context (from discovery)
- **Repo conventions (CLAUDE.md):** group-based discovery, no hard refs; heavily-commented teaching style with `## SECTION` banners; explicit type hints; tunable constants at top; manager Nodes added once under `Main` in `scenes/main.tscn` (see `CrocodileLODManager` at line 38, `MobileInput` at line 41 — `MobileInput` shows the `groups=["..."]` syntax in the .tscn).
- **`scenes/main.tscn`:** `[gd_scene load_steps=N ...]` header with `ext_resource` script entries at the top; adding a scripted node requires one new `ext_resource` line, a `load_steps` bump, and one `[node]` block. Keep this diff surgical — other executors will touch this file later.
- **Hook points found:**
  - `scripts/coin.gd` `_on_body_entered()` (line ~70): sets `collected = true`, calls `body.collect_coin()`, `queue_free()`s. The pickup sound must NOT be played by a player attached to the coin (it dies with `queue_free`) — play through the manager's own players.
  - `scripts/player_controller.gd`:
    - Jump: `_physics_process` STEP 2 (line ~399): `if Input.is_action_just_pressed("jump") and is_on_floor() and not is_giant:` sets `velocity.y = JUMP_VELOCITY`.
    - Landing: `update_character_animation()` (line ~885) branch `elif not was_on_floor and current_on_floor:` calls `animate_landing()` — the landing sound one-liner goes in that branch (or at the top of `animate_landing()`, line ~1018).
    - Ability: SECTION 8 `try_activate_ability()` (line ~1365) dispatches per character and commits the cooldown when an ability actually fires — the whoosh one-liner goes where the cooldown is committed (so a failed Primm blink that costs no cooldown also makes no sound). A per-ability pitch variant is fine (pass the character index or name).
    - Bite: `hit_by_crocodile()` (line ~1074) — after the `if is_caught or is_respawning or is_game_over: return` guard.
    - Game over: `_trigger_game_over()` (line ~1131).
  - `scripts/touch_controls.gd` `_on_enable_overlay_pressed()` (line ~482): the first-run "Tap to enable motion controls" overlay tap — the guaranteed user gesture on mobile web; add a null-safe `unlock_audio()` one-liner there.
- **Existing null-safe group lookup pattern** (copy it): `var flash := get_tree().get_first_node_in_group("hit_flash")` / `if flash and flash.has_method("flash"): flash.flash()` in `hit_by_crocodile()`.
- **Godot 4.5**; web export is `gl_compatibility`. `AudioStreamWAV` supports `format = FORMAT_16_BITS`, `data` as `PackedByteArray` of little-endian s16 frames, `mix_rate`, and `loop_mode = LOOP_FORWARD` with `loop_begin`/`loop_end` (in frames) for the wind loop.
- **No test suite/linter exists.** Verification = headless parse/run if a `godot` binary is on PATH, else careful review.

## Development Approach
- **Testing approach**: NO unit tests. There is no test infrastructure in this repo at all; do not add any.
  - no integration tests either — a headless engine run is the only automatable check and it lives in the Verify task
- Complete each task fully before moving to the next
- Make small, focused changes; one-liner hooks only — do NOT restructure `player_controller.gd`
- Desktop keyboard play must remain unchanged apart from the new sounds
- **CRITICAL: update this plan file when scope changes during implementation**

## Testing Strategy
- **Unit tests**: none.
- **Integration tests**: none (no boundary a test could guard; no test infra exists).
- **E2E tests**: none (no suite exists).

## Progress Tracking
- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## What Goes Where
- **Implementation Steps**: the new script, the scene node, the one-liner hooks, headless verification
- **Post-Completion**: listening to the sounds on real hardware / real mobile browser (cannot be automated here)

## Implementation Steps

### Task 1: Create scripts/sound_manager.gd (synthesis + playback core)
- [x] create `scripts/sound_manager.gd` — `extends Node`, doc-comment header in the repo's teaching style explaining WHY sounds are synthesized (no assets → web build size unchanged) and how AudioStreamWAV s16 PCM buffers work
- [x] constants at top, all typed: `MIX_RATE: int = 22050` (plenty for chip-style effects, half the memory of 44.1k), per-sound tunables (`COIN_FREQ`, `COIN_PITCH_JITTER`, `JUMP_*`, `LAND_*`, `WHOOSH_*`, `BITE_*`, `GAME_OVER_*`, `WIND_*`), volume-in-dB constants per sound (wind clearly quietest, e.g. −26 dB), `ONESHOT_PLAYER_COUNT: int = 6`
- [x] `_ready()`: `add_to_group("sound_manager")`; build every `AudioStreamWAV` once (helper `_build_wav(samples: PackedFloat32Array) -> AudioStreamWAV` converting float −1..1 → s16 LE bytes, `FORMAT_16_BITS`, mono); create a small round-robin pool of `ONESHOT_PLAYER_COUNT` `AudioStreamPlayer` children (so overlapping one-shots don't cut each other off) plus one dedicated looping `AudioStreamPlayer` for wind
- [x] synthesis helpers (each returns `PackedFloat32Array`, commented like a mini-lesson): coin = short two-note sine chirp with exponential decay; jump = rising sine sweep; land = low sine thud + fast decay; whoosh = band-ish filtered noise swell (simple noise × envelope is fine); bite = harsh descending square/saw burst; game over = slow descending three-note minor phrase; wind = long (~2 s) heavily-smoothed (e.g. one-pole low-passed) noise loop with `loop_mode = LOOP_FORWARD`, `loop_begin = 0`, `loop_end = frame count`
- [x] public API, all typed and null-safe to call before unlock: `play_coin()` (applies `pitch_scale = 1.0 + randf_range(-COIN_PITCH_JITTER, COIN_PITCH_JITTER)`), `play_jump()`, `play_land()`, `play_ability(character_name: String)` (small fixed pitch offset per character — a Dictionary constant), `play_bite()`, `play_game_over()`, `unlock_audio()`
- [x] **web unlock**: `var _unlocked: bool = false`; every `play_*` early-returns while `!_unlocked`; `unlock_audio()` sets the flag and starts the wind loop; `_input(event)` in the manager itself calls `unlock_audio()` on the first key/mouse-button/screen-touch pressed event then `set_process_input(false)` — this covers desktop-web first keypress/click AND is harmless on native desktop (sounds simply start with the first input, which is when gameplay starts anyway). Comment the mobile-browser-gesture WHY prominently. No JavaScriptBridge needed — Godot 4.5 web resumes the AudioContext on a user gesture automatically; gating our own playback until a gesture guarantees no "AudioContext was not allowed to start" console errors

### Task 2: Add SoundManager node to scenes/main.tscn (surgical diff)
- [x] add one `ext_resource` line for `scripts/sound_manager.gd` (type="Script", new unique id), bump `load_steps` by 1 in the header
- [x] add `[node name="SoundManager" type="Node" parent="." groups=["sound_manager"]]` with the script, placed right after the `MobileInput` node block (mirrors `CrocodileLODManager`/`MobileInput` placement); touch nothing else in the file
- [x] do NOT hand-edit any `.gd.uid` files (Godot generates the new one; if the editor is unavailable, omitting the .uid is fine — Godot creates it on next import)

### Task 3: One-liner hooks in existing scripts
- [x] `scripts/coin.gd` `_on_body_entered()`: after `collected = true`, null-safe group lookup + `sm.play_coin()` (two lines, matching the `hit_flash` lookup pattern; brief comment: the coin frees itself, so the MANAGER owns the player — a sound attached to this dying node would be cut off)
- [x] `scripts/player_controller.gd` jump (STEP 2, inside the `is_action_just_pressed("jump")` branch): null-safe `play_jump()`
- [x] `scripts/player_controller.gd` landing (the `elif not was_on_floor and current_on_floor:` branch in `update_character_animation()`): null-safe `play_land()`
- [x] `scripts/player_controller.gd` `try_activate_ability()`: null-safe `play_ability(<current character name>)` at the single point where the ability actually fires / cooldown is committed (the shared `if used:` block that commits the cooldown — a Primm blink that finds no landing spot stays silent)
- [x] `scripts/player_controller.gd` `hit_by_crocodile()`: after the invulnerability guard, null-safe `play_bite()`
- [x] `scripts/player_controller.gd` `_trigger_game_over()`: null-safe `play_game_over()`
- [x] `scripts/touch_controls.gd` `_on_enable_overlay_pressed()`: null-safe lookup via `"sound_manager"` group + `unlock_audio()` (placed at the very top of the handler, BEFORE the no-driver early return — a missing motion driver must not mean no sound; comment explains the mobile-web gesture rule)
- [x] every hook is null-safe (`if sm and sm.has_method(...)`) so any scene running without Main (e.g. a character scene in isolation) never errors

### Task 4: Verify acceptance criteria
- [x] verify all sounds exist and are distinct in code (different waveform/envelope/pitch per sound); wind volume constant is clearly far below the one-shots (wind −26 dB vs one-shots −6..−10 dB; sine chirp / rising sweep / low thud / noise swell / square sweep / minor phrase / looped low-passed noise)
- [x] verify NO audio asset files were added (`git status` — only .gd/.tscn/.uid/plan changes)
- [x] verify `main.tscn` diff is minimal: one ext_resource line, load_steps 17→18, one node block
- [x] verify no `play_*` call can run before `unlock_audio()` (all play_* funnel through `_play_oneshot`, which early-returns on `!_unlocked`; the only other `.play()` is the wind loop inside `unlock_audio()` itself)
- [x] if a `godot` binary is on PATH: run `godot --headless --path . --quit-after 2` and confirm no script parse errors; otherwise do a careful self-review of every edited file for syntax (balanced indents, typed signatures) — ran on Godot 4.5.stable, exit 0, no parse errors

### Task 5: [Final] Update documentation
- [x] add a short "Synthesized audio" subsection to CLAUDE.md's Architecture section: the `sound_manager` group contract, the play_* API, the web unlock gesture rule, and the "no audio assets — everything is generated at _ready()" invariant

## Technical Details
- `AudioStreamWAV` fields: `format = AudioStreamWAV.FORMAT_16_BITS`, `mix_rate = MIX_RATE`, `stereo = false`, `data` = `PackedByteArray` (2 bytes/frame, little-endian signed 16-bit); float→s16: `clampi(int(sample * 32767.0), -32768, 32767)`.
- Wind loop: `loop_mode = AudioStreamWAV.LOOP_FORWARD`, `loop_begin = 0`, `loop_end = <frame count>`; a ~2 s smoothed-noise buffer loops without an audible click if the noise is low-passed and the envelope meets itself (fade the first/last ~50 ms toward the same level).
- Round-robin pool: `_players[_next_player]`, `_next_player = (_next_player + 1) % ONESHOT_PLAYER_COUNT`; set `stream`, `pitch_scale`, `volume_db` per call then `play()`.
- All randomness (coin pitch jitter) is cosmetic runtime randomness — it does NOT touch the terrain's deterministic chunk RNG.

## Post-Completion
**Manual verification:**
- Listen on desktop editor: coin/jump/land/ability/bite/game-over audibly distinct, wind barely audible.
- Web build on a phone: tap the motion-controls overlay → audio starts, no console errors ("AudioContext not allowed to start" must not appear).
- Desktop web: first keypress/click starts audio.
- Tune the frequency/volume constants by ear — they are starting defaults picked without hardware.
