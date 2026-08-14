# Web Shell & Mobile UX Overhaul (bead godot-test1-afc.4)

## Overview

The web export preset customizes nothing (stock Godot splash on black, no page metadata, no PWA), and the touch UI is far below Apple's 44pt minimum: at 1920x1080 base with `canvas_items` stretch + `expand` aspect, an iPhone-14-landscape scale factor of ~0.364 renders the 120-unit JUMP button at ~44 CSS px (portrait: ~25px, unplayable). Phones start in portrait and nothing detects it. This plan fixes the page shell, the touch UI scale/ergonomics, onboarding, and adds PWA + pause-on-focus-loss.

**HARD FILE-OWNERSHIP BOUNDARY — parallel executors own everything else. Only these files may be edited:**
- `scripts/touch_controls.gd`
- `scripts/mobile_settings_panel.gd`
- `scripts/mobile_input.gd`
- `scripts/mobile_sensors.gd`
- `scenes/ui/touch_controls.tscn`
- `export_presets.cfg`
- `project.godot`
- `serve.sh`
- new files under `assets/ui/` (only if genuinely needed — see Task 2 note: probably none)

**DO NOT touch** `player_controller.gd` (mouse-capture fix is another bead), `endless_terrain.gd`, `coin*`, crocodile files, `main.tscn`, HUD scripts (`lives_hud.gd`, `perf_overlay.gd`, `ability_hud.gd`, `game_over_ui.gd`, `motion_debug.gd`), or `CLAUDE.md`/README (doc updates are deferred to the PR description — CLAUDE.md is outside the ownership boundary).

## Context (from discovery — already researched, do NOT re-research)

Facts confirmed against the Godot **4.5-stable** source (`misc/dist/html/full-size.html` and `platform/web/export/export_plugin.cpp`):

1. **The stock web shell already has** a viewport meta tag (`width=device-width, user-scalable=no, initial-scale=1.0`) and `touch-action: none` on `body`. Do NOT re-add a viewport meta.
2. **`$GODOT_HEAD_INCLUDE` is injected AFTER the stock `<style>` block** (near the end of `<head>`), so a plain `html, body { background-color: #5a6570; }` rule in `html/head_include` wins the cascade over the stock `body { background-color: black; }` (same specificity, later in document). No `!important` needed.
3. **`$GODOT_SPLASH_COLOR`** (background of the loading/status overlay) is substituted from `application/boot_splash/bg_color` in project.godot. Setting that one project setting fixes both the engine boot flash and the page's loading overlay.
4. **PWA enum values** (bead text said "display=3 fullscreen" — that is WRONG; verified from `export_plugin.cpp`):
   - `progressive_web_app/display`: `0=Fullscreen, 1=Standalone, 2=Minimal UI, 3=Browser` → use **0** (Fullscreen).
   - `progressive_web_app/orientation`: `0=Any, 1=Landscape, 2=Portrait` → use **1** (Landscape). This is the only real orientation lock available on iOS home-screen installs; in-browser iOS ignores `screen.orientation.lock`, hence the runtime portrait guard (Task 4).
5. **Empty PWA icon fields fall back to the project icon automatically**: `_add_manifest_icon()` with an empty path loads the project icon (`icon.svg`) and resizes it to 144/180/512 itself. So NO icon generation, NO converter, NO new files under `assets/ui/` are needed — leave the three `icon_*` fields `""`.
6. `export_presets.cfg` string values may contain literal newlines inside double quotes, with inner quotes escaped as `\"` (see the existing `ssh_remote_deploy/run_script` entries). The `html/head_include` value uses this format.
7. Local env: `godot` 4.5.stable at `/opt/homebrew/bin/godot`. Export templates may or may not be installed (a background download was started); if `godot --headless --export-release "Web" ...` fails with a missing-template error, that is an environment gap, NOT a preset error — verify what can be verified (see Task 9) and flag it.
8. `project.godot` display settings: `window/stretch/mode="canvas_items"`, `aspect="keep"` + `aspect.web="expand"`, base 1920x1080. `content_scale_factor` on the root `Window` scales all 2D/UI without touching 3D render cost.
9. Existing gating convention: `MobileSensors.is_touch_session()` (static) is the ONE canonical touch-session predicate; every new visual/behavioral change here must gate on it (or `OS.has_feature("web")` for web-only bits) so desktop keyboard/mouse play stays byte-for-byte unchanged.
10. `touch_controls.gd` structure: UI built in code in `_build_ui()`; `_apply_platform_visibility()` decides visibility; `_process()` flushes the `_actions_to_release` queue and drives the motion watch; the enable overlay is a full-rect `Button` (`_enable_overlay`) with a retry path in `_update_motion_watch()` (lines ~386-416) that re-shows it with "Motion unavailable — tap to retry".
11. `mobile_input.gd`: driver with `active` flag; `enable()`/`disable()` (disable releases all held actions); public tuning/diagnostics API used by `mobile_settings_panel.gd` via the `"mobile_input"` group.
12. `mobile_settings_panel.gd`: gear button currently top-LEFT (`GEAR_WIDTH/GEAR_HEIGHT` consts, positioned around lines 200-209), colliding with the LivesHUD/PerfOverlay column; panel body is a `PanelContainer` sized `PANEL_WIDTH x PANEL_HEIGHT`.

## Development Approach

- **Testing approach**: NO unit tests (none exist in this project; there is no test framework). The one real verification boundary is the **headless web export** — it validates every `export_presets.cfg`/`project.godot` edit and is the hard acceptance gate (Task 9). GDScript parse validity is checked by running the export (it compiles scripts) or `godot --headless --check-only` equivalents.
- Match the project's **teaching-comment density** and **explicit type hints** in every edited `.gd` file. GDScript files use TABS for indentation.
- Complete each task fully before moving to the next.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Desktop play must remain byte-for-byte unchanged: every visible/behavioral change is gated on `MobileSensors.is_touch_session()` (runtime) or lives in web-export-only surfaces (`export_presets.cfg` head_include/PWA affect only the exported page).

## Testing Strategy

- **Unit tests**: none.
- **Integration tests**: none to write — the headless web export IS the integration gate and is run in Task 9 (and by CI on push).
- Manual on-device verification goes in Post-Completion.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Page shell metadata + PWA + texture compression in export_presets.cfg

All edits go in `[preset.3.options]` (the Web preset) of `export_presets.cfg`. Keep the existing key order/formatting style exactly (`key=value`, strings double-quoted); this file is editor-generated but hand-editable — a malformed line breaks the headless export, which Task 9 catches.

- [ ] set `html/head_include` to a multiline string (literal newlines inside the quotes, inner quotes escaped `\"`) containing exactly: a `<meta name=\"theme-color\" content=\"#5a6570\">` (matches the sky horizon), `<meta name=\"apple-mobile-web-app-capable\" content=\"yes\">`, `<meta name=\"apple-mobile-web-app-status-bar-style\" content=\"black-translucent\">`, and a `<style>` block with `html, body { background-color: #5a6570; overscroll-behavior: none; touch-action: none; -webkit-user-select: none; user-select: none; }`. Do NOT add a viewport meta (stock shell has one — Context #1). The background rule kills the black flash before the engine paints (Context #2); `overscroll-behavior: none` kills pull-to-refresh; `touch-action: none` on `html` complements the stock body rule (kills double-tap zoom on the page edges).
- [ ] set `vram_texture_compression/for_mobile=true` (keep `for_desktop=true`) — the trap for the first shipped texture on mobile GPUs.
- [ ] enable PWA: `progressive_web_app/enabled=true`, `progressive_web_app/display=0` (Fullscreen — Context #4, the bead's "3" was wrong), `progressive_web_app/orientation=1` (Landscape — the only real orientation lock on iOS installs), `progressive_web_app/background_color=Color(0.353, 0.396, 0.439, 1)` (matches the boot splash), and add `progressive_web_app/ensure_cross_origin_isolation_headers=false` (thread_support is false, so COOP/COEP isolation is unnecessary and would change page semantics; the option's engine default is true, so it must be written explicitly).
- [ ] leave `progressive_web_app/icon_144x144`/`180x180`/`512x512` as `""` — Godot auto-generates all three PNGs from the project icon (`icon.svg`) when the fields are empty (Context #5). No files under `assets/ui/` needed.
- [ ] add a short comment nowhere — `export_presets.cfg` does NOT support comments; keep it pure key=value (explanations live in the PR/commit message instead).

### Task 2: Boot splash background color in project.godot

- [ ] in `[application]` of `project.godot`, add `boot_splash/bg_color=Color(0.353, 0.396, 0.439, 1)` (the sky-horizon tone; also feeds `$GODOT_SPLASH_COLOR` in the web shell's loading overlay — Context #3). Keep the existing `;`-comment style of the file if adding an explanatory comment (project.godot DOES support `;` comments — see the `[display]` section).
- [ ] skip `boot_splash/image`: leaving it unset shows the plain bg color (no black flash, no stock Godot logo file needed in-repo). This is the honest minimal fix; note the deferral in the PR.

### Task 3: Touch UI scale, safe-area margins, translucent circular buttons (touch_controls.gd)

- [ ] in `_ready()` (after `_apply_platform_visibility()`), when `MobileSensors.is_touch_session()` is true, set `get_window().content_scale_factor = TOUCH_CONTENT_SCALE` (new `const TOUCH_CONTENT_SCALE: float = 1.8`). With `canvas_items` stretch this scales ALL 2D/UI only (3D render cost unchanged); the 120px JUMP button becomes ~79 CSS px on an iPhone 14 landscape. Gate strictly on the real touch predicate, NOT on `_force_shown` (F6 debug on desktop must not rescale the desktop HUD). Add a teaching comment explaining the 0.364 iPhone scale-factor math.
- [ ] raise `BUTTON_MARGIN` from `24.0` to `64.0` so the bottom-right action cluster clears the iOS home-indicator strip after the scale change (update the const's comment).
- [ ] give the three action buttons a translucent circular look: in `_make_action_button()`, build a `StyleBoxFlat` with `bg_color = Color(0.10, 0.12, 0.16, 0.55)` and all four `corner_radius_*` set to `ACTION_BUTTON_SIZE / 2.0` (a circle), apply it as the `"normal"` and `"hover"` stylebox override, plus a slightly brighter variant (e.g. alpha 0.75) for `"pressed"`; also override the font color to white for legibility. The buttons now occlude far less of the 3D world.
- [ ] style the steer toggle with the same translucent treatment (rounded, `TOGGLE_HEIGHT / 2.0` corner radius) so the top bar reads as one family.

### Task 4: Onboarding overlay rewrite + portrait "rotate your device" guard (touch_controls.gd)

- [ ] rewrite the enable overlay into a mini how-to. A `Button` cannot autowrap its text, so: set `_enable_overlay.text = ""` and add a full-rect `Label` child (`mouse_filter = MOUSE_FILTER_IGNORE` so taps still hit the button, `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART`, centered h/v alignment) named e.g. `_enable_label`. Its text: a headline "TAP TO START" plus lines "Step in place to walk", "Tilt your phone to steer", "Buttons bottom-right: Jump / Special / Switch". Keep font sizes generous (headline ~40, body ~28 — remember these are pre-scale design px).
- [ ] keep the existing retry path intact: `_update_motion_watch()` (~lines 386-416) and `_on_enable_overlay_pressed()`'s no-driver branch must now write their "Motion unavailable — tap to retry" message to `_enable_label.text` instead of `_enable_overlay.text` (retry keeps the how-to lines below the error headline, or just replaces the headline — keep it simple: replace the headline line, keep the how-to).
- [ ] add a public `show_onboarding()` method that re-shows the overlay with the default how-to text WITHOUT resetting `_motion_enabled` (a tap while already enabled just hides it again — guard `_on_enable_overlay_pressed()`: if `_motion_enabled`, only hide, don't re-request/re-enable/re-watch). Add the node to a new `"touch_controls"` group in `_ready()` so the settings panel can find it (same group-discovery convention as everything else).
- [ ] portrait guard: in `_build_ui()`, build a full-rect `ColorRect` (`color = Color(0.0, 0.0, 0.0, 0.85)`, `mouse_filter = MOUSE_FILTER_STOP` so it swallows taps) with a centered autowrapping `Label` "Rotate your device\n(landscape only)"; add it LAST so it draws on top of everything, start hidden. In `_process()`, when visible-and-touch-session, set its visibility each frame from `get_viewport().get_visible_rect().size` → `visible = size.y > size.x` (drive from the existing `_process`, cheap; do NOT rely on `screen.orientation.lock` — iOS in-browser ignores it). Gate: only ever show it when `_is_touch_device()` is true (F6 force-show on desktop must not trigger it).

### Task 5: Fullscreen toggle button, Android web only (touch_controls.gd + mobile_sensors.gd)

- [ ] add a static helper to `mobile_sensors.gd`: `static func is_fullscreen_available() -> bool` — returns false unless `OS.has_feature("web")`; on web, feature-detect via `JavaScriptBridge.eval("document.fullscreenEnabled === true", true)` (iOS Safari reports false — `requestFullscreen` is unsupported there; Android Chrome reports true). Follows the file's existing pattern of web-gated static JS probes (`is_touch_session()`).
- [ ] in `touch_controls.gd` `_build_ui()`, add a small `"⛶"` fullscreen `Button` right of the steer toggle (same top strip, same translucent style, roughly `TOGGLE_HEIGHT` square). Visible only when `MobileSensors.is_fullscreen_available()`. Its `pressed` handler toggles via `DisplayServer.window_set_mode(...)`: if current mode is `WINDOW_MODE_FULLSCREEN` → `WINDOW_MODE_WINDOWED`, else `WINDOW_MODE_FULLSCREEN`. A `Button.pressed` handler IS a user gesture, which the browser requires for entering fullscreen.

### Task 6: Pause on focus loss + tap-to-resume (mobile_input.gd + touch_controls.gd)

- [ ] `mobile_input.gd`: in `_ready()`, set `process_mode = Node.PROCESS_MODE_ALWAYS` with a teaching comment — this node must keep processing while `get_tree().paused` so it can coordinate resume; its `_physics_process` is already safe while paused because pause sets `active = false` (early return), so it never writes Input during the pause.
- [ ] `mobile_input.gd`: add `_notification(what)` handling `NOTIFICATION_APPLICATION_FOCUS_OUT` (fires when the browser tab is backgrounded / app switched): gate on `MobileSensors.is_touch_session()` (desktop alt-tab must NOT pause — acceptance requires desktop unchanged), then remember whether the driver was active (`_was_active_before_pause: bool`), call `disable()` (releases all held actions so nothing latches), and set `get_tree().paused = true`. Do NOT auto-resume on `FOCUS_IN` — resume is the explicit tap (which doubles as the WebAudio unlock gesture for the audio system that may land on master in parallel).
- [ ] `mobile_input.gd`: add public `func resume_from_pause() -> void`: `get_tree().paused = false`; re-`enable()` only if `_was_active_before_pause`. Called by the touch UI's resume overlay.
- [ ] `touch_controls.gd`: set `process_mode = Node.PROCESS_MODE_ALWAYS` in `_ready()` (comment: the resume overlay must be tappable and `_process` must keep running while the tree is paused; safe because all its outputs are one-shot synthetic events the paused controller simply won't consume until unpause — and the release-queue flush in `_process` still runs).
- [ ] `touch_controls.gd`: build a full-rect "Paused — tap to resume" overlay `Button` (same translucent-dark style + centered `Label` pattern as the onboarding overlay), hidden by default, drawn on top (add after the enable overlay, but BELOW the portrait guard in child order). In `_process()`, when on a touch session: `_resume_overlay.visible = get_tree().paused` (but never show it over the initial enable overlay — skip when `_enable_overlay.visible`). Its `pressed` handler calls `_ensure_driver().resume_from_pause()` (null-safe: if no driver, just `get_tree().paused = false`).
- [ ] sanity-check the pause interactions and document them in comments: the respawn countdown and game-over UI live under paused-by-default nodes — while the tab is hidden they freeze WITH the tree and resume cleanly on tap (frozen countdown is correct behavior: no losing lives while backgrounded); nothing here touches those scripts.

### Task 7: Relocate the settings gear out of the top-left HUD column (mobile_settings_panel.gd)

- [ ] move the gear button (currently top-left, ~lines 200-209) to the BOTTOM-LEFT corner: anchor (0,1), `offset_left = EDGE_MARGIN`, `offset_bottom = -EDGE_MARGIN`, `offset_top = -EDGE_MARGIN - GEAR_HEIGHT`. Bottom-left is free (action cluster is bottom-right, lives/perf top-left, coins/ability top-right). Update the const-doc comments that say "top-LEFT".
- [ ] re-anchor the open panel body so it remains fully on-screen from its new corner: anchor bottom-left, opening UPWARD from just above the gear (`offset_bottom = -EDGE_MARGIN - GEAR_HEIGHT - 8`, `offset_top = offset_bottom - PANEL_HEIGHT`), clamped by the existing ScrollContainer if the screen is short.
- [ ] add a "How to play" button to the panel's action-button rows (same `ACTION_ROW_HEIGHT` style as Recalibrate/Reset/Close): finds the touch UI via the new `"touch_controls"` group and calls `show_onboarding()`, then closes the panel. Null-safe if the group is empty.

### Task 8: serve.sh cleanups

- [ ] fix the header comment (lines 4-5): the script sets NO SharedArrayBuffer/COOP/COEP headers — say plainly that it's a plain static server and that this project's export has `thread_support=false` so no such headers are needed.
- [ ] fix the Linux-only `hostname -I` (line 108): detect macOS (`uname -s` = Darwin) and use `ipconfig getifaddr en0` (fall back to `en1`, then omit the Network line if empty); keep `hostname -I` for Linux.
- [ ] print a note near the instructions: iOS motion sensors require a SECURE context — `http://<lan-ip>` will NOT grant `DeviceMotionEvent` permission on iOS; test motion on the GitHub Pages (HTTPS) build or an HTTPS tunnel.

### Task 9: Verify acceptance criteria (the hard gate)

- [ ] run the headless web export from the repo root: `mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html` — it MUST exit 0. This validates every `export_presets.cfg` and `project.godot` edit AND compiles all GDScript. If it fails on a missing-export-template error (env gap, templates may still be downloading), fall back to `godot --headless --import` (script/scene validation) and mark this item with ⚠️ so the PR flags that CI is the real gate.
- [ ] if the export succeeded, inspect the output: `build/web/index.html` must contain the theme-color meta + the background style; `build/web/index.manifest.json` must have `"display": "fullscreen"`, `"orientation": "landscape"`, three icon entries; the `index.144x144.png`/`index.180x180.png`/`index.512x512.png` files must exist. `grep` is sufficient.
- [ ] verify desktop neutrality by reading (not editing) the gates: every new behavior in the diff must be behind `MobileSensors.is_touch_session()` or `OS.has_feature("web")`; `content_scale_factor` is never touched on desktop; the F6/F7 debug force-shows must not trigger the scale, the portrait guard, or the pause path.
- [ ] confirm no file outside the ownership boundary is in the diff (`git diff --name-only` against the base) — especially `player_controller.gd`, `main.tscn`, HUD scripts, `CLAUDE.md`.
- [ ] confirm `scenes/ui/touch_controls.tscn` needed no change (all UI is code-built; if a change WAS needed, it is within the boundary — just verify it parses via the export/import run).

## Technical Details

- Sky-horizon color: CSS `#5a6570` == `Color(0.353, 0.396, 0.439)` (used for theme-color, page background, boot splash, PWA background — one tone everywhere so no flash at any load stage).
- `content_scale_factor = 1.8`: effective design viewport shrinks from 1920 wide to ~1067, so every anchored Control (including HUD scripts owned by other beads) grows ~1.8x on phones at runtime — no file edits needed for them, which keeps the ownership boundary clean.
- Pause semantics: `get_tree().paused` freezes everything with default `process_mode`; only `mobile_input` (coordinator) and `touch_controls` (resume overlay + release-queue flush) are `PROCESS_MODE_ALWAYS`.
- New public surface: `mobile_input.resume_from_pause()`, `touch_controls.show_onboarding()` (via new `"touch_controls"` group), `MobileSensors.is_fullscreen_available()`.

## Post-Completion

**Manual verification (needs a real phone — not possible in this env):**
- iPhone Safari: buttons ≥ ~70 CSS px, onboarding readable, portrait shows rotate prompt, no pull-to-refresh/double-tap-zoom, page background matches sky during load, backgrounding the tab pauses and tap resumes, gear opens bottom-left, fullscreen button HIDDEN.
- Android Chrome: all of the above plus fullscreen button visible and working; "Add to Home Screen" installs the PWA fullscreen + landscape-locked.
- Desktop browser + native desktop: identical to before (no scale change, no overlays, no pause on alt-tab).

**Known deferrals (flag in the PR):**
- `boot_splash/image` not set (plain bg color only) — deliberate, avoids shipping a generated PNG.
- PWA service worker caches aggressively; a deployed update may need a reload/reinstall to pick up. Inherent to Godot's PWA implementation.
- CLAUDE.md documentation of the new surface is outside this bead's file-ownership boundary — noted for the parent to fold in.
