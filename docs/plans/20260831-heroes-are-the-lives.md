# Heroes are the lives — deprecate hearts and every game-over that is not "all four jailed"

## Overview

Bead `godot-test1-0bc`. **Owner ruling 2026-08-31:** *"Let's forget the concept of
hearts/lives and game over because of them at all — deprecate it. Now game over is
when all four are jailed; besides this, other challenges are just fewer coins /
temporal freeze."*

The capture system (beads `3iy.9/10/11`) already implements the new end state: the
free-hero set going empty opens the full-custody protocol, and losing that ends the
run — solo and room-wide. This bead deletes the OTHER end state (hearts reaching
zero) and converts every contact that used to spend a heart into the setback that
already exists for the tower guard: **the caught freeze + a fraction of the run's
coins**, then respawn in place.

The whole change is subtraction plus one generalisation:

1. `_pay_guard_setback()` becomes the ONLY thing `_on_caught_finished()` does before
   respawning. It is already null-safe about the checkpoint knockback (the tower is a
   group lookup), so in the field it degrades to "coins only, no relocation" with no
   branch of its own.
2. Every `SPECIES` row grows a `coin_setback`, so the bill is per-predator data
   exactly like every other trait.
3. `lives`, `MAX_LIVES`, `LIVES_CAP`, `EXTRA_LIFE_COINS`, `next_extra_life_at`,
   `own_lives_spent`, the whole shared-hearts machine in `mp_manager.gd`, and
   `lives_hud.gd` + its scene node are **deleted**. The hero portrait HUD
   (`hero_hud.gd`, bead `#134`) is the roster/death display from here on.

## Decisions already made — do NOT re-open these

- **The extra-life coin thresholds grant NOTHING.** `EXTRA_LIFE_COINS` /
  `LIVES_CAP` / `next_extra_life_at` are removed outright rather than repurposed
  into a coin bonus. The coin setback below is the new coin-side stake; adding a
  coin bonus at the same time would be two untested tunings in one bead.
- **The pre-beat window is deliberately unlosable.** Systemic capture arms only
  after the authored Primm rescue (`_capture_is_armed()` → `TowerInterior.RESCUE_DONE`).
  Before that beat, with hearts gone, nothing can end a run: a pre-beat hunter grab
  costs the ordinary predator arithmetic (freeze + coins) and no more. That is the
  accepted early-game on-ramp. **Do not invent a pre-beat game over.** (If the owner
  wants pre-beat stakes it is a new bead.)
- **Wire compatibility by tolerant decoders**, not a protocol version bump — that is
  the existing pattern in `mp_manager.gd` (every optional field is read through
  `.get(key, default)`). Stop sending the heart fields; make the validators no longer
  require them; ignore them when an old peer still sends them.
- `lives_hud.gd` is **deleted**, not left as a dead widget (the bead forbids a dead
  widget). Its `[ext_resource]` line and its `[node name="LivesHUD"]` block come out
  of `scenes/main.tscn`. Leave `HeroHUD`'s offsets alone — it is fine where it is;
  do not re-layout the HUD in this bead.

## Invariants that MUST survive (read CLAUDE.md before you start)

- **The speed lattice.** `chase_speed` > `WALK_SPEED` (5.0) so walking gets you
  caught; `MAX_CHASE_SPEED` (8.5) < the slowest run so running always escapes; the
  `burst` arm's pounce-and-recovery cycle still loses to a runner. **Touch no speed
  number in `SPECIES`.** Pressure now comes from coins + captures, so contact must
  still hurt — that is what `coin_setback` is for.
- **The invulnerability gate.** The early return at the top of `hit_by_crocodile()`
  stays the single home of i-frames. Do not add a second one.
- **The streak resets on a bite** (`coin_streak = 0` in the caught path) — unchanged.
- **The tower guard's checkpoint knockback** stays, and stays guard-only: it is the
  `tower_interior` group lookup, which finds nothing in the field.
- **Lifetime coins are NEVER deducted.** The setback comes off `own_coins` and
  `coins_collected` (the RUN's numbers) and never off `progression.gd`'s lifetime
  count or `best_run_store.gd`. `progression.gd` and `best_run_store.gd` are NOT
  edited by this bead.
- **`"player"` means the LOCAL player.** No new group lookups that could pick up a
  `RemoteAvatar`.
- Node discovery stays group-based with `has_method` guards. GDScript with explicit
  type hints. Match the surrounding comment density — this codebase is written to be
  read, and the sections you are rewriting are the most heavily commented in it.

## Context — files and the exact sites (READ THESE BEFORE WRITING CODE)

### `scripts/player_controller.gd` (5191 lines) — the centre of the change

| Site | What is there now | What it becomes |
|---|---|---|
| `~281-287` | `EXTRA_LIFE_COINS`, `LIVES_CAP`, `next_extra_life_at` banner + consts | deleted |
| `~289-299` | `own_coins` / `own_lives_spent` banner | `own_lives_spent` deleted, banner rewritten for `own_coins` alone |
| `~372-383` | `caught_setback` banner ("0.0 for every ordinary contact") | rewritten: it is now the fraction for EVERY contact; the guard is just the row with a knockback behind it |
| `~385-391` | `MAX_LIVES`, `lives`, `is_game_over` banner | `MAX_LIVES` + `lives` deleted; `is_game_over` stays (still set by the custody-protocol failure and by `_trigger_game_over`) |
| `~1169-1172` | `if is_game_over:` freeze in `_physics_process` STEP 0a | stays; comment "out of lives" reworded |
| `~2017-2046` | `_coin_setback_of(attacker)` | stays as-is mechanically. Rewrite the docstring: it is no longer "0.0 for every ordinary contact" but "every predator's own bill". Keep the `clampf(..., 0.0, 1.0)` at the read and keep the `Node.get("spec")` null tolerance — the rotor bar and boss projectiles have no `spec` and must fall through to a default |
| `~2049-2117` | `_pay_guard_setback(fraction)` | rename `_pay_coin_setback(fraction)`. Delete the `ponytail:` block about the shared-heart threshold (the thing it worried about no longer exists). Keep the whole body otherwise; the tower group lookup is what makes it guard-only-relocating. Reword the final `print` |
| `~2649-2662` | the `while coins_collected >= next_extra_life_at` extra-life loop in `collect_coin()` | deleted (and its bullet in the docstring) |
| `~2685-2695` | `bank_awarded()`'s "NO extra-life while-loop" comment | deleted comment, no code change |
| `~2835-2900` | `_on_caught_finished()` | **the heart of the bead** — see below |
| `~3040-3041`, `~3560-3570`, `~3670-3685` | `restart_game()` / `new_run()` / `join_at()` resets of `lives`, `own_lives_spent`, `next_extra_life_at`, `caught_setback` | drop the dead fields, keep `caught_setback = 0.0` |
| `~4140-4205` | `_refresh_shared_totals()` — the shared bank/distance/hearts recompute | the hearts half deleted (`shared_lives`, `shared_lives_spent`, the solo-restore of `lives` / `next_extra_life_at`). The **bank and distance halves stay** |
| `~4205-4260` | `_check_shared_game_over()` | **deleted entirely**, along with its call site in `_physics_process`. The room now ends only through the room-wide captive set, which `_on_caught_finished()`'s roster clause already reads |
| `~3781` | `if _coin_setback_of(crocodile) > 0.0:` (a guard exemption in `clear_nearby_crocodiles()`) | now true for EVERY predator, so this test no longer means "is a guard". **Root-cause it**: the exemption exists to stop the respawn sweep freeing authored tower furniture. Re-key it on what it actually means — the body being parented under the tower interior / not chunk-parented — or on a new explicit row key. Read the exemption's own comment before choosing; do not leave a test that now matches everything |

**`_on_caught_finished()` after the change** — one shape, no heart branch:

```
func _on_caught_finished() -> void:
    # EVERY contact pays the same bill: the freeze that already happened, plus a
    # slice of the run's coins. Nothing here can end a run — the only ending left
    # is the empty free-hero set, tested below and handed to the break-out.
    _pay_coin_setback(caught_setback)      # relocates only inside the tower
    if not custody_protocol_active and free_hero_count() == 0 \
            and not captive_heroes.is_empty():
        _begin_custody_protocol()
    else:
        _respawn_in_place()
```

Two things to get right here, both currently load-bearing in the code you are
replacing:

- `_pay_guard_setback()` today ends with its OWN respawn tail (`_reset_ability_states()`,
  `velocity = ZERO`, `is_respawning = true`, `respawn_timer = RESPAWN_GRACE_DURATION`)
  because it deliberately does not route through `_respawn_in_place()` — that
  function's first act is to relocate the player to the room's group anchor, which
  would throw the guard's knockback across the map. Keep that: inside the tower the
  setback still ends the sequence itself; in the field `_respawn_in_place()` must
  still run (it is what keeps a room's members together). Simplest correct shape:
  `_pay_coin_setback()` returns whether it relocated, and the caller skips the
  respawn when it did. Do it with the smallest diff that keeps both behaviours —
  do NOT duplicate the respawn tail into two places.
- The `_refresh_shared_totals()` call that used to sit at the top of
  `_on_caught_finished()` existed ONLY to re-read the room's stale heart count
  before spending one. With hearts gone it has no reason to be there — delete it
  and its long comment.
- **`caught_setback` must still be latched in `hit_by_crocodile()`** (`~2808`) and
  cleared in `_pay_coin_setback()`, for the reason its banner gives: by the time the
  33-frame freeze ends the attacker may be slept, freed or gone.

### `scripts/piglet_crocodile_ai.gd` (6155 lines) — 14 `SPECIES` rows

Every row gets a `coin_setback`. Rows and line numbers of their opening brace:
`crocodile` 60, `sand_viper` 277, `timber_wolf` 551, `frost_bear` 765,
`mountain_cougar` 1023, `alley_hound` 1254, `titan` 1446, `green_dragon` 1684,
`hydra` 1917, `naga` 2027, `roc` 2135, `clown` 2272, `hunter_robot` 2443,
`tower_guard` 2685 (already has `0.07` — leave that number alone).

Suggested spread — bigger animals bill harder, and the whole range stays survivable
so the setback is a tax, not a soft game over. **Tune these if a playtest argues, but
keep every value in (0.0, 0.35] and keep `tower_guard` at 0.07:**

| row | `coin_setback` | why |
|---|---|---|
| `crocodile` | 0.10 | the baseline field predator |
| `sand_viper` | 0.08 | an ambush you barely saw; small bill |
| `alley_hound` | 0.10 | burst attacker, ordinary bill |
| `mountain_cougar` | 0.12 | burst attacker with reach |
| `timber_wolf` | 0.12 | you were surrounded; it earned it |
| `clown` | 0.12 | |
| `naga` | 0.15 | |
| `hydra` | 0.18 | |
| `roc` | 0.18 | |
| `frost_bear` | 0.20 | the bead's "bosses/bears can bite harder" |
| `green_dragon` | 0.22 | |
| `titan` | 0.25 | |
| `hunter_robot` | 0.25 | a grab you escaped costs the most |
| `tower_guard` | 0.07 | **unchanged** |

Follow the `tower_guard` row's comment style for the new key: a short block saying
what losing to THIS animal costs. Do not restate the same paragraph 13 times — write
the full rationale once (in the constants banner at the top of `SPECIES`, or on the
`crocodile` row) and give each other row one line.

**Rotor bar and boss projectiles have no `spec`.** `_coin_setback_of()` returns 0.0
for them today, which after this bead would mean "free hit". The bead says they take
the same coin bill and are never lethal. Give `_coin_setback_of()` a named default
const in `player_controller.gd` (e.g. `DEFAULT_COIN_SETBACK: float = 0.10`) returned
when the attacker has no row, and say so in its docstring. **Check `boss_projectile.gd`
and `tower_interior.gd`'s rotor bar for any path that decrements a life or triggers
game over directly** — grep both for `lives` / `_trigger_game_over` and route them
through the same bill.

### `scripts/mp_manager.gd` (5078 lines) — delete the shared-hearts machine

Delete: `_gone_spent` (589), the `_room_lives` / `_room_next_extra_at` /
`_room_spent_seen` / `_room_lives_owned` / `_room_lives_seen` block (675-708) and
their resets (914, 934-942), `shared_lives_spent()` (3229), `shared_lives()` (3258),
`_tick_room_lives()` (3310) and its call at 3468, `shared_lives_from()` (3408).
`_peer_state`'s `"spent"` field (496, 2763, 2841, 3880) goes with them.

Wire fields to stop sending, with their decoders relaxed:
- presence broadcast `"lv"` (3744) and `"rl"` (3755-3756) — remove from the encoder,
  remove from `_decode_presence_dict()`'s required-key validation, and delete the
  reads at 3880 and 3899.
- join snapshot `"ls"` (2769) and `"gs"` (2780) — same treatment in the encoder,
  `decode_state()`'s validation, and `_receive_state()` (2841, 2858).

**This is a trust boundary.** Everything relayed is unvalidated peer input: the
validators must still type-check every REMAINING field and drop anything malformed.
Relaxing them means "these keys are no longer required", never "stop validating".
An old peer that still sends `lv`/`rl`/`ls`/`gs` must be accepted and those fields
ignored.

The bank, distance, hero assignment, croc sync, claim and captive-set halves of
`_refresh_shared_totals()` / the presence packet are **untouched**.

### HUD and UI

- **Delete** `scripts/lives_hud.gd` + `scripts/lives_hud.gd.uid`, the
  `[ext_resource ... id="8_lives"]` line and the `[node name="LivesHUD"]` block in
  `scenes/main.tscn` (~line 171).
- `scripts/hero_hud.gd` — no functional change needed; it already dims captured
  heroes. Fix its two comments that call it "the squad row under the hearts" /
  "the `lives_hud.gd` idiom" (the latter can name the pattern without the file).
- `scripts/game_over_ui.gd` — the "Hidden until the player runs out of lives"
  comment (38) is now wrong; the screen is raised by the full-custody protocol's
  failure and by `_trigger_game_over()` alone. **Heads-up: PR #151 adds ~22 lines to
  `show_game_over` / `hide_game_over` in this file for an outro video — expect a
  merge conflict here and keep both changes.**
- `scripts/mp_ui.gd` (76) — comment naming "lives hearts" in the HUD layout budget.
- `scripts/help_overlay.gd` — check the keymap card and any run-state text for a
  lives/hearts row; if one exists, remove it and remove its `ui.csv` rows. Any NEW
  or CHANGED user-facing string goes through `assets/translations/ui.csv` (`keys,en,de`),
  **appending rows, never reordering existing ones**. Remember: the translation key
  IS the English source string, and `tr()` goes on the FORMAT string for anything
  composed at runtime.

### Self-checks to rewrite

- **`scripts/capture_selfcheck.gd` (2649 lines)** — the heaviest edit after
  `player_controller`. The heart assertions become the GLOBAL rule:
  - check 11 (`_check_a_guard_takes_coins_and_ground_not_a_heart`, ~851-1020) — its
    **control** at ~956-968 asserts "a crocodile's bite costs a heart". That control
    inverts: an ordinary predator now takes coins too, and the guard is distinguished
    ONLY by the checkpoint relocation. Rename the check accordingly and rewrite the
    control to prove the difference that still exists (ground, not hearts).
  - the last-free-hero checks (~475-520, ~1100-1120, ~1640-1720) currently prove
    "the roster ran out while hearts remained". With hearts gone the hearts half of
    every one of those assertions is meaningless — but the check itself is now
    STRONGER, not weaker: the empty free-hero set is the only game over there is.
    Rewrite the prose and the assertions; **delete the "would prove nothing" heart
    guards** (`if player.lives <= 0: _fail(...)`) rather than porting them.
  - the MP shared-hearts cases (~1400-1720, especially `(e1)`, the in-scene bite and
    `(f) the room's hearts outrank a running break-out`) — the room has no hearts to
    outrank anything with. Delete those cases outright; the room-wide captive set is
    the only shared death state and it is already covered.
  - the stub `shared_lives_spent()` at ~216-220 and `player.caught_setback = 0.0` at
    ~2578 and the summary paragraphs at ~2555-2570 all move with the above.
  - **Add one check the bead asks for by name:** no code path anywhere decrements a
    life or triggers game over except the empty free-hero set. The cheap, honest
    version: assert `player_controller.gd` declares no `lives` member at all
    (`"lives" in player` is false), so a reintroduction fails loudly.
- **`scripts/mp_selfcheck.gd` (2715 lines)** — remove/replace every shared-lives row
  (grep `shared_lives`, `own_lives_spent`, `"lv"`, `"rl"`, `"ls"`, `"gs"`). Where a
  row tested the heart arithmetic, replace it with a row asserting the decoder now
  ACCEPTS a packet that still carries the retired keys and ignores them — that is
  the old-peer tolerance this bead promises, and it is worth one check.
- **`scripts/enemy_spawn_selfcheck.gd`** — it iterates `SPECIES`, so add the row
  completeness check there: every species row carries a `coin_setback`, it is a
  float in `(0.0, 1.0]`, and it is the ONLY new key. Put it in the same check that
  already walks the table for the other required keys.
- **`scripts/tower_interior_selfcheck.gd`** (~2994) has a comment asserting a guard
  without `coin_setback` "would take a HEART instead" — reword; the claim no longer
  parses.

### `CLAUDE.md`

Rewrite the **"Death, lives, respawn"** section end to end — it is a map of a model
that no longer exists. The new text: heroes are the lives; the free-hero set going
empty opens the full-custody protocol and losing that is the only game over; every
other contact is the caught freeze plus the attacker's `coin_setback` off the run's
coins, respawn in place, no relocation outside the tower; the invulnerability gate is
still the single early return in `hit_by_crocodile()`; lifetime coins are never
touched. Also fix the **Multiplayer** section's shared-lives sentence ("Shared
bank/lives/distance are a sum of per-peer absolute broadcasts") and the
**Crocodiles** section to mention `coin_setback` as a required row key. Keep it a
map — the reasoning goes next to the code.

## Verification

Fresh worktree: run `godot --headless --path . --import` FIRST. Run each self-check
with an isolated HOME so a stale `user://` profile cannot poison it:

```bash
HOME=$(mktemp -d) godot --headless --path . --script res://scripts/<name>.gd
```

Every one must print `SELFCHECK OK` and exit 0:

- `capture_selfcheck` — the rewritten heart assertions; the last-free-hero check is
  the only game-over probe
- `mp_selfcheck` — shared-lives rows replaced
- `enemy_spawn_selfcheck` — the `coin_setback` table check; the speed lattice
  (checks 8 and the row-completeness check) must be untouched and green
- `hero_hud_selfcheck` — the portrait HUD is now the sole roster display
- `help_selfcheck` — keymap card vs the real input map
- `locale_selfcheck` — **re-run `godot --headless --path . --import` after any
  `ui.csv` edit** or it reports the stale imported table
- `progression_selfcheck` — proves lifetime coins are untouched by the setback
- `tower_interior_selfcheck`, `tower_selfcheck`, `tower_shell_selfcheck`,
  `tower_site_selfcheck` — the guard's checkpoint knockback still works
- `perf_selfcheck` — no new per-frame cost
- `boss_selfcheck`, `projectile_selfcheck` — the rotor/projectile bill
- `pause_selfcheck`, `view_selfcheck`, `minimap_selfcheck` — cheap regression net,
  they touch the HUD tree the deleted node lived in

Also: `godot --headless --path . --check-only --script res://scripts/player_controller.gd`
style parse checks are NOT a substitute — run the self-checks.

## Task list

### Task 1: `SPECIES` rows grow `coin_setback`
Add the key to all 13 rows that lack it, with the values in the table above and the
comment style described. Do not touch any speed, detection or gait number. Add the
row-completeness assertion to `enemy_spawn_selfcheck.gd`.
**Verify:** `enemy_spawn_selfcheck` prints `SELFCHECK OK`.

### Task 2: the coin bill becomes universal in `player_controller.gd`
Rename `_pay_guard_setback` → `_pay_coin_setback`; give `_coin_setback_of()` the
`DEFAULT_COIN_SETBACK` fallback for spec-less attackers; rewrite both docstrings.
Rewrite `_on_caught_finished()` to the shape above — no heart branch, no
`_refresh_shared_totals()` call, the tower knockback still suppressing the group-anchor
respawn. Re-key the `clear_nearby_crocodiles()` exemption at ~3781 on what it actually
means. Do NOT yet delete the `lives` field — that is Task 3, so this task stays
reviewable on its own.
**Verify:** the project parses; `capture_selfcheck` still runs (it may FAIL on the
heart assertions here — that is expected and Task 5 fixes it; note it, do not paper
over it).

### Task 3: delete hearts from `player_controller.gd`
Remove `MAX_LIVES`, `lives`, `LIVES_CAP`, `EXTRA_LIFE_COINS`, `next_extra_life_at`,
`own_lives_spent`, the extra-life loop in `collect_coin()`, the hearts half of
`_refresh_shared_totals()`, and `_check_shared_game_over()` + its call site. Update
every banner comment that described the heart model. `is_game_over` and
`_trigger_game_over()` STAY.
**Verify:** `grep -n '\blives\b' scripts/player_controller.gd` returns only prose that
means something else; the project parses.

### Task 4: delete the shared-hearts machine from `mp_manager.gd`
The deletions and wire-field removals listed above, validators relaxed but still
type-checking every remaining field.
**Verify:** `mp_selfcheck` runs (rows referencing the removed API are fixed in Task 5).

### Task 5: rewrite the self-checks
`capture_selfcheck.gd`, `mp_selfcheck.gd`, `tower_interior_selfcheck.gd` per the
section above, including the new "no `lives` member exists" check.
**Verify:** `capture_selfcheck`, `mp_selfcheck` and all four tower self-checks print
`SELFCHECK OK`.

### Task 6: HUD, UI strings and docs
Delete `lives_hud.gd` (+ `.uid`) and its two blocks in `scenes/main.tscn`; fix the
stale comments in `hero_hud.gd`, `game_over_ui.gd`, `mp_ui.gd`; audit
`help_overlay.gd` and `assets/translations/ui.csv`; rewrite CLAUDE.md's death section
and fix the two other sections named above.
**Verify:** `godot --headless --path . --import`, then `locale_selfcheck`,
`help_selfcheck`, `hero_hud_selfcheck`, `minimap_selfcheck`, `pause_selfcheck`,
`view_selfcheck`.

### Task 7: full sweep
Run EVERY self-check in the CLAUDE.md Commands list plus the tower and boss ones.
Fix whatever the sweep turns up. Confirm by inspection that no code path decrements a
life or triggers game over except the empty free-hero set (`grep -rn 'lives' scripts/`
should return only unrelated prose and `lifetime`).
**Verify:** every self-check prints `SELFCHECK OK` and exits 0.
