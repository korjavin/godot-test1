# MP phase 4: mid-run join — state replay, spawn placement, hero split

Delivers bd issue **godot-test1-s86.4**. Phase 3 (`godot-test1-s86.3`, PR #29) is
merged into master and is the base this builds on. **Read `scripts/mp_manager.gd`,
`scripts/lobby_client.gd`, `scripts/remote_avatar.gd` and `scripts/mp_ui.gd`
before writing a line** — every rule they document (the isolation contract, the
two trust boundaries, "never assign `multiplayer.multiplayer_peer`", "inert until
a room is joined") still holds and this phase must not weaken any of them.

## Overview

Phase 3 put 2–4 browsers in a shared-seed world but a joiner restarted at spawn
with its own coins, its own lives and no idea which hero anyone else was playing.
Phase 4 makes joining a *running* game correct:

1. **State replay on join** — every incumbent sends a snapshot to the joiner over
   the lobby relay (available immediately, before ICE completes): its own
   contributed coins, lives spent, distance, world position, and the set of coin
   ids it has already collected. The joiner merges them.
2. **Spawn placement** — the joiner lands near the group (centroid, or the
   master's position when the group is spread beyond `GROUP_SPREAD_MAX`), on solid
   ground found with the existing `_is_body_blocked_at()` probe, with crocodiles
   swept exactly like `clear_nearby_crocodiles()`.
3. **Shared bank / lives / distance** — while in a room the HUD numbers are the
   room's, not this peer's. Solo play is byte-for-byte unchanged.
4. **Hero split** — the lobby is the source of truth (it already implements
   `hero` / `heroes` / `pool`; see `server/room.go`). A joiner picks from the
   unclaimed heroes, an incumbent keeps the hero it is embodying, its E-cycle is
   restricted to its assignment, and leaving returns the hero to the pool.

**The whole feature stays inert outside a room.** No new per-frame work while
`_state == OFFLINE`; every new player-side read is null-guarded through the `"mp"`
group with a `has_method` check, exactly like `_weather_is_raining_here()` and
`_terrain_is_river_here()`.

## Context (from discovery)

### The lobby already implements the hero pool — do not add server code

Verified by reading `server/room.go` / `server/conn.go` / `server/README.md`:

| direction | frame | meaning |
|---|---|---|
| server → client | `welcome` | carries `heroes{hero:id}` **and** `pool[]` alongside `you`/`room`/`master`/`members[]` |
| server → client | `heroes` | `{"type":"heroes","heroes":{hero:id}}` — broadcast whenever a hero is claimed or released |
| client → server | `hero` | `{"type":"hero","hero":"<name>"}`; `""` releases |

- `var Heroes = []string{"windman", "primm", "teibi", "phoboman"}` — the same
  order and the same names as `player_controller.CHARACTERS`. The index into
  `CHARACTERS` is therefore the index into `pool`, but **derive it by name, never
  by index** (`_hero_index(name)` scanning `CHARACTERS[i]["name"]`), so a
  reordering on either side cannot silently swap two players' bodies.
- `SetHero` holds **at most one hero per member** — claiming a second releases
  the first. So an "assigned subset" is in practice a singleton, and an
  incumbent's E-cycle in a room is a no-op. Implement the general
  cycle-within-the-allowed-set anyway (it degenerates correctly and needs no
  special case).
- `Leave` deletes the departing member's hero and broadcasts `heroes` — **hero
  release on leave is already server-side; the client must not duplicate it.**
- A rejected claim (`unknown hero`, `hero already taken`) comes back as a plain
  `{"type":"error","error":...}` frame **on the same socket, without closing it**.

### ⚠️ LANDMINE: a hero-claim rejection currently kicks you out of the room

`MpManager._on_lobby_error()` calls `leave()` on *every* `error` frame. Two peers
racing for the same hero would therefore both be dropped from a working room.
`_on_lobby_error` must treat the hero errors as **non-fatal**: emit a status line,
re-sync from the last `heroes` broadcast, and stay in the room. Match on the
lobby's exact strings (`errUnknownHero` = `"unknown hero"`, `errHeroTaken` =
`"hero already taken"` in `server/room.go`) and keep `leave()` for everything else.

### Coin identity — the scheme, and why

Coins come from **three** spawners in `endless_terrain.gd` (road scatter in
`spawn_coins_in_chunk`, artifact reward ring + gem in `spawn_artifact_in_chunk`,
camp fire coins in `spawn_camp_in_chunk`), all of them deterministic in
`run_seed`. Rather than thread an id through three call sites, derive the id
**from the coin's own world position** in `coin.gd` — the one file every coin
already routes through, both at spawn (`_ready`) and at collection
(`_on_body_entered`):

```
id = hash(Vector3i(roundi(x * COIN_ID_QUANT), roundi(y * COIN_ID_QUANT), roundi(z * COIN_ID_QUANT)))
```

with `COIN_ID_QUANT = 8.0` (12.5 cm cells). Position is already set before
`add_child` at every spawn site, so `_ready()` sees the final `global_position`.

`ponytail:` the two ceilings, both to be named in a comment in `coin.gd`:
two distinct coins landing inside the same 12.5 cm cell would share an id (the
road scatter makes that vanishingly rare, and the cost is one extra coin vanishing
for a joiner); and a coin sitting exactly on a cell boundary could round the other
way on a peer whose float arithmetic differs by an ulp, so its id would not match
and the coin would simply not be despawned. Both degrade to a cosmetic duplicate,
never to a crash or a wrong bank. The upgrade path is threading an explicit
`(k, slot)` / `(chunk, index)` id through the three spawners.

### Shared bank / lives / distance — sum of per-peer contributions, no authority

Do **not** build a master-authoritative bank with round trips. Each peer
broadcasts its **own absolute contribution** and every peer sums:

- `bank = Σ own_coins` over current members + the frozen totals of departed ones
- `spent = Σ own_lives_spent` (same frozen-on-leave rule)
- `lives = clampi(MAX_LIVES + bank / EXTRA_LIFE_COINS - spent, 0, LIVES_CAP)`
- `distance = max` over peers (already idempotent — `run_distance` is a running
  max, so feeding a peer's max back in cannot inflate it)

Absolute values, not deltas, so the unreliable presence channel is self-healing:
a dropped packet is corrected 66 ms later.

**Freeze a departing peer's contribution, do not drop it** (`_gone_coins` /
`_gone_spent` accumulators updated in `_on_lobby_peer_left`). Dropping it would
make the bank visibly shrink and — much worse — *refund* the lives that peer
spent.

### Godot-side facts established during discovery (do not re-litigate)

- `player_controller.CHARACTERS` is the 4-entry array; `set_active_character(i)`
  is the ONLY correct way to change body (it clears Teibi's resize state, re-runs
  `_apply_view_mode()` and restores the rest pose). **Hero assignment must route
  through it** — the bead names this landmine explicitly.
- `switch_to_next_character()` refuses while `windman_boost_timer > 0.0` or
  `teibi_size_state != 0`. Keep that guard ahead of the new hero filter.
- `_is_body_blocked_at(pos)` (Primm's blink probe) is a sphere cast at capsule
  centre height, so flat ground never counts as blocked. Reuse it.
- `clear_nearby_crocodiles(spawn_point)` already exempts bosses. Reuse it as-is.
- `endless_terrain.new_run(forced_seed)` rebuilds **around chunk (0,0)** and that
  is hardcoded — a mid-run joiner needs it around the anchor chunk instead.
- `endless_terrain.update_chunks(player_chunk)` builds the Chebyshev ≤
  `SYNC_RING` ring synchronously; `_process` fills the rest one chunk per frame.
- `lives_hud.gd` reads `player.MAX_LIVES` / `player.lives`; `coin_hud.gd` reads
  `player.coins_collected` / `player.run_distance` / `get_streak_multiplier()`.
  **Neither HUD may be edited** — feed them shared values through the player's
  existing fields.
- `RemoteAvatar.target_pos` holds a peer's last presence position, but presence
  only flows after ICE completes (seconds). Join placement must therefore use the
  positions carried in the **relay snapshot**, not the avatars.
- `mp_selfcheck.gd` is the one runnable check (`godot --headless --path .
  --script res://scripts/mp_selfcheck.gd` → `SELFCHECK OK`, exit 0). It is not
  wired into CI; keep it passing and keep it small.

### Dependencies

- Phase 3, merged. The lobby is live at `wss://ck.wandergeek.org` (the default in
  `LobbyClient.DEFAULT_LOBBY_URL`), and a local one runs with `cd server && go run .`.
- A parallel bead (`godot-test1-s86.8`) is vendoring the desktop WebRTC
  GDExtension and touches `project.godot`, `README.md` and possibly CI.
  **Do not edit those three files in this branch.**

## Development Approach

- **Testing approach**: NO unit-test framework. This project has no test suite,
  linter or build script (CLAUDE.md "Commands"). Verification is:
  - `godot --headless --path . --import` — completes with no script errors,
  - `godot --headless --path . scenes/main.tscn --quit-after 240` — boots and
    exits clean (this is the solo-play regression gate: MP is inert offline, so
    any error here means solo play was broken),
  - `godot --headless --path . --script res://scripts/mp_selfcheck.gd` — prints
    `SELFCHECK OK`, exits 0.
- **NEVER run frontend/JS tests.** The web export is CI's gate, not a local one.
- Complete each task fully before moving to the next.
- **Match the project's comment density.** CLAUDE.md: "the codebase is written to
  be read". Explicit type hints on every var, param and return; tunables as
  `const` at the top of the script that owns them.
- Mark deliberate simplifications with a `ponytail:` comment naming the ceiling
  **and** the upgrade path.
- **Smallest coherent diff.** Reuse `_is_body_blocked_at`, `clear_nearby_crocodiles`,
  `set_active_character`, `_settle_coin_y`, the `"mp"`/`"terrain"`/`"player"` group
  lookups. Add no new manager node, no new scene, no new autoload.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: none.
- **Integration test**: `scripts/mp_selfcheck.gd`, extended (Task 9) with the new
  *pure* logic only — coin-id derivation, the shared-total arithmetic, the
  snapshot parser against hostile input, and the hero-index-by-name lookup. Do
  not grow it into a suite and do not put anything needing a socket in it.
- **E2E**: none. Two-browser verification is manual, in Post-Completion.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: `endless_terrain.new_run` can rebuild around any chunk

- [x] change the signature to
      `func new_run(forced_seed = null, around: Vector2i = Vector2i.ZERO) -> void:`
      and replace the two hardcoded `Vector2i(0, 0)` uses in step 4
      (`update_chunks(...)` and `last_player_chunk = ...`) with `around`.
- [x] the default keeps every existing call site (`restart_game`, `_receive_seed`)
      byte-identical — say so in the docstring, and explain that a mid-run joiner
      passes the chunk it is about to be placed in so the synchronous
      `SYNC_RING` build lands under its feet in the same frame, exactly as the
      spawn-chunk build does for a restart.
- [x] no other change to the terrain in this task.

### Task 2: coin identity in `coin.gd`

- [x] add `const COIN_ID_QUANT: float = 8.0` and
      `static func id_at(pos: Vector3) -> int` returning
      `hash(Vector3i(roundi(pos.x * COIN_ID_QUANT), roundi(pos.y * COIN_ID_QUANT), roundi(pos.z * COIN_ID_QUANT)))`.
      Static and pure so the selfcheck can exercise it. Document the scheme and
      both `ponytail:` ceilings from the Context section above.
- [x] add `func coin_id() -> int: return id_at(global_position)`.
- [x] in `_ready()`, **after** `base_y` is captured: ask the `"mp"` group node
      (null-safe, `has_method("is_coin_collected")`) whether this id is already
      collected; if so `queue_free()` and return before connecting `body_entered`.
      Offline there is no `"mp"` node method answer to give, so the branch is a
      single failed group lookup per coin — note that cost is paid once per coin
      at spawn, never per frame.
- [x] in `_on_body_entered()`, after `body.collect_coin(value)`, report the
      pickup to the same group node via `has_method("report_coin_collected")`.
- [x] **do not** touch the three spawners in `endless_terrain.gd`.

### Task 3: `lobby_client.gd` — hero frames

- [x] add `signal heroes_changed(heroes: Dictionary, pool: Array)`.
- [x] in `_handle_text`, emit it from **both** the `welcome` branch (type-checking
      `frame["heroes"]` as a Dictionary and `frame["pool"]` as an Array, each
      defaulting to empty — malformed means empty, never a crash) and a new
      `"heroes"` branch (which carries no `pool`; re-emit the pool we last saw,
      stored in a member var, so subscribers always get a complete picture).
- [x] add `func send_hero(hero: String) -> void:` → `_send({"type": "hero", "hero": hero})`.
      `""` releases.
- [x] update the file's header comment: `heroes` is no longer "parsed but
      deliberately unused"; `pong` still is.

### Task 4: `mp_manager.gd` — hero pool

- [x] state: `_heroes: Dictionary` (hero name → peer id), `_pool: Array[String]`,
      wired from `LobbyClient.heroes_changed`. Cleared by `leave()`.
- [x] `signal heroes_changed(heroes: Dictionary, pool: Array)` re-emitted for
      `mp_ui.gd` (the only listener), same shape as `room_changed`.
- [x] public API, all null-returning/empty when offline so callers stay trivial:
      - `available_heroes() -> Array[String]` — pool entries with no holder, plus
        our own current hero (a player may always re-pick what it already holds).
      - `my_hero() -> String` — the hero this peer holds, `""` if none.
      - `hero_holder(hero: String) -> String` — peer id or `""`.
      - `claim_hero(hero: String) -> void` — `_lobby.send_hero(hero)`; the local
        body only changes when the lobby's `heroes` broadcast confirms it, so two
        peers racing can never both switch.
      - `my_character_indices() -> Variant` — `null` when offline or when no hero
        is held (solo semantics: every character allowed), otherwise an
        `Array[int]` of `CHARACTERS` indices this peer may use. Derived **by name**.
- [x] on `welcome`/`heroes`: if we hold a hero whose index differs from the
      player's `current_character_index`, call `player.set_active_character(idx)`
      through the `"player"` group with a `has_method` guard. **Never** poke
      `current_character_index` directly (the bead's landmine).
- [x] **auto-claim on join**: once `_heroes` is known, if we hold nothing, claim
      the player's current character when it is unclaimed, else the first
      available hero. One claim attempt per `heroes` frame at most — do not loop.
- [x] `_on_lobby_error`: hero rejections (`"unknown hero"`, `"hero already
      taken"`) emit a status line and **return**; everything else keeps today's
      `leave()`. See the ⚠️ LANDMINE above.

### Task 5: `mp_manager.gd` — join-time state replay

Snapshot payload, over the **lobby relay** (not the mesh — it must arrive before
ICE completes), one message per incumbent, sent only to the new peer:

```
{"mp": "state", "cc": int, "ls": int, "dd": int,
 "px": float, "py": float, "pz": float, "ids": [int, ...]}
```

- [ ] in `_on_lobby_peer_joined`, **every** member (not just the master) sends its
      own snapshot to the joining id, right beside the master's existing seed
      send. Document why it is every member: the collected-coin set is the *union*
      across the room and each peer only knows its own, and per-peer contributions
      are what the shared totals sum.
- [ ] `"state"` is handled in `_on_lobby_relay` as a third verb. **It is the third
      trust boundary in this file** — type-check every field, reject non-finite or
      out-of-range positions with the existing `MAX_PRESENCE_COORD` bound, clamp
      `cc`/`ls`/`dd` to non-negative and to sane caps, and accept at most
      `MAX_STATE_IDS` (2048) ids, each an int. A malformed snapshot is dropped
      whole. Factor the parse into a **static** `decode_state(payload) -> Dictionary`
      (empty on failure) so the selfcheck can beat on it, exactly like
      `decode_presence`.
- [ ] `MAX_STATE_IDS` is also the cap on the set we **send** (most recent first —
      keep the collected set in insertion order). `ponytail:` name the ceiling: a
      very long run's oldest collected coins are in chunks nobody is near any
      more, so truncating the tail costs a joiner nothing; the upgrade path is
      filtering by proximity to the anchor before sending.
- [ ] merging: `_collected_ids` (a `Dictionary` used as a set) absorbs the ids;
      `_peer_state[from] = {"coins": cc, "spent": ls, "dist": dd}`.
- [ ] **`_absorb_collected(ids)` also sweeps the live world**: for every node in
      the `"coin"` group whose `coin_id()` is in the newly-absorbed set,
      `queue_free()` it. This is what makes a snapshot that lands *after* the
      terrain was already built still correct, and it is why the ordering of the
      seed and the snapshots does not need coordinating.
- [ ] `is_coin_collected(id: int) -> bool` and `report_coin_collected(id: int) -> void`
      are the public API `coin.gd` calls. `report_coin_collected` records into
      `_collected_ids` **only while in a room** (offline it must be a no-op, so
      solo play allocates nothing and the set cannot grow unbounded across a
      session). `leave()` clears the set.

### Task 6: `mp_manager.gd` — shared totals + extended presence

- [ ] extend the presence packet with `"cc"` (own coins), `"lv"` (own lives
      spent) and `"dd"` (own distance), read off the player through the same
      `"x" in player` style guards `_send_presence` already uses. Update the
      packet's docstring and the CLAUDE.md description in Task 10.
- [ ] `decode_presence` validates the three new fields exactly like `c`: number,
      finite, non-negative, bounded. **Keep it static and keep the
      trusted-whole-or-dropped-whole rule** — a packet missing them is *not*
      malformed (forward/backward compatibility with a phase-3 peer): treat
      missing as 0 and only reject values that are present and bad.
- [ ] `_receive_presence` updates `_peer_state[id]` from those three fields.
- [ ] `_on_lobby_peer_left` folds the departing peer's `_peer_state` entry into
      `_gone_coins` / `_gone_spent` before erasing it, and drops its
      `_peer_state`. (Distance needs no freezing — it is a max, and the local
      `run_distance` already latched it.)
- [ ] public API, each returning `null` when offline so the player can fall
      through to today's solo behaviour with one `== null` test:
      - `shared_bank(own_coins: int) -> Variant`
      - `shared_lives_spent(own_spent: int) -> Variant`
      - `shared_distance(own_distance: int) -> Variant`
      Taking the caller's own contribution as a parameter keeps *all* the summing
      in one place and means the manager never has to reach into the player.
- [ ] a **static, pure** `shared_lives_from(bank: int, spent: int, max_lives: int, per_extra: int, cap: int) -> int`
      implementing `clampi(max_lives + bank / per_extra - spent, 0, cap)`, so the
      selfcheck can pin the arithmetic without a room.

### Task 7: `player_controller.gd` — shared HUD values, join placement, hero-restricted E

Keep every existing solo path byte-identical. All new MP reads go through **one**
null-safe helper, `_mp()` (group `"mp"`, returns the node or `null`), in the shape
of `_weather_is_raining_here()`.

- [ ] new fields: `var own_coins: int = 0` and `var own_lives_spent: int = 0` —
      this peer's contributions, which are what gets broadcast. `collect_coin()`
      adds the same multiplied value to `own_coins` that it adds to
      `coins_collected` (one line); `_on_caught_finished()` increments
      `own_lives_spent` where it already spends a life. `reset_position()` (the
      hard-reset wipe list) and `restart_game()` reset both, next to the existing
      `coins_collected = 0` / `lives = MAX_LIVES` lines.
- [ ] once per physics tick, after the existing `run_distance` update and **only**
      when `_mp()` reports a room, overwrite the three *displayed* fields:
      - `coins_collected = shared_bank(own_coins)`
      - `run_distance = shared_distance(run_distance)`
      - `lives = shared_lives_from(...)` using `shared_bank` / `shared_lives_spent`
      Offline nothing runs and the fields keep today's meaning exactly. **The two
      HUD scripts are not edited** — they read these same fields, so they show the
      room's numbers in a room and this peer's solo.
      ⚠️ Order matters: do this **after** `collect_coin`'s own bookkeeping in the
      same frame, and remember `collect_coin`'s solo extra-life `while` loop still
      runs — in a room the shared recompute overwrites `lives` right after, which
      is intended and must be commented as such.
- [ ] `switch_to_next_character()`: keep the existing ability guard first, then
      ask `_mp().my_character_indices()`. `null` → today's `(i + 1) % size`
      behaviour, unchanged. An array → step to the next entry in it (wrapping);
      when it holds one entry the press is a no-op — fire the same
      `ability_hud.flash_blocked()` + `play_buzz()` feedback a refused F press
      uses, so the player learns the hero is locked rather than thinking E broke.
- [ ] `func join_at(anchor: Vector3) -> void:` — the joiner's placement, called by
      the manager:
      - scan for a clear spot: `JOIN_RING_RADII` (e.g. 3, 5, 8, 12 m) × 8 evenly
        spaced angles around `anchor`, taking the first where
        `_is_body_blocked_at()` is false at the candidate's capsule-centre height;
        fall back to `anchor` itself if every candidate is blocked (the terrain
        is flat, so a total failure is close to impossible — say so in a comment).
      - teleport there at spawn height, zero `velocity`, face `SPAWN_FACING_Y`,
        reset the camera pivot exactly as `reset_position()` does (reuse its
        lines; do NOT wipe coins/distance — this is not a restart).
      - `clear_nearby_crocodiles(spot)` so a joiner is not bitten on frame one.
      - `_reset_ability_states()` and `respawn_blink_timer = 0.0` +
        `_apply_view_mode()`, same hygiene as `reset_position()`.
      Constants (`JOIN_RING_RADII`, the angle count) at the top of SECTION 8 or
      beside `SPAWN_SAFE_RADIUS` — the project's convention.

### Task 8: `mp_manager.gd` — apply the join, and `mp_ui.gd` — the hero picker

- [ ] `_apply_join_placement()` runs once per room, when the seed **and** at least
      one snapshot are in hand (guard with a `_joined_applied` latch cleared by
      `leave()`), and only when we were **not** the room's first member (a host
      has nobody to join — leave its spawn exactly as phase 3 left it):
      - anchor = centroid of the snapshot positions; if any snapshot position is
        further than `GROUP_SPREAD_MAX` (60.0 m, a `const` with a comment saying
        it is tuned by eye) from that centroid, use the **master's** snapshot
        position instead. If the master sent no snapshot, fall back to the
        centroid.
      - `terrain.new_run(_room_seed, terrain.world_to_chunk(anchor))` — the Task 1
        parameter, so the synchronous ring is built where the player is about to
        stand, not at the origin.
      - `player.join_at(anchor)`.
      - status line so the panel says what happened.
      ⚠️ `_receive_seed` currently calls `new_run(seed)` + `player.reset_position()`.
      Keep that as the **host / no-snapshot** path, but do not let it fight the
      join placement: if a snapshot has already arrived, go straight to
      `_apply_join_placement()` instead of resetting to the origin.
- [ ] `mp_ui.gd`: a hero row in the panel — one button per `pool` entry, built
      once and refreshed on `heroes_changed`. A hero held by someone else is
      `disabled` and labelled with the holder's name; the one we hold is visibly
      selected. Pressing one calls `manager.claim_hero(name)`. Same
      `_ensure_manager()` + `has_method` guards the rest of the file uses, so a
      scene without the manager shows an inert row. Keep the existing panel
      dimensions working (grow `PANEL_HEIGHT` if the row does not fit) and keep
      every button at least `TOUCH_MIN_HEIGHT` tall.

### Task 9: extend `scripts/mp_selfcheck.gd`

Add checks only for the new **pure** logic. Same explicit-`if` style (no
`assert` — release builds strip them), same "first failure wins" structure.

- [ ] `Coin.id_at()` is stable for the same position, differs for positions a
      metre apart, and survives a sub-millimetre jitter on the same coin.
- [ ] `MpManager.decode_state()` against hostile input: not a dictionary, missing
      fields, NaN/INF position, absurd coordinates, negative counters, an `ids`
      array that is not an array, an over-long `ids` array (truncated or
      rejected — assert whichever the implementation chose), and a well-formed
      payload (accepted, fields correct).
- [ ] `MpManager.decode_presence()` still accepts a **phase-3 shaped** packet
      (no `cc`/`lv`/`dd`) — the backward-compatibility rule from Task 6.
- [ ] `MpManager.shared_lives_from()` arithmetic: base case, extra lives from the
      bank, spending below zero clamps to 0, and the `LIVES_CAP` clamp.
- [ ] hero index by name: every `player_controller.CHARACTERS` name resolves, and
      an unknown name resolves to `-1`.
- [ ] the existing four checks must still pass unchanged.

### Task 10: [Final] Update documentation

- [ ] `CLAUDE.md`: extend the "Multiplayer (phase 3)" section into a phase-3/4
      account. Cover, in the file's existing voice and density: the hero pool and
      that the **lobby is the source of truth** (with the "release on leave is
      server-side" note), the E-cycle restriction, the coin-id scheme and both its
      ceilings, the shared bank/lives/distance as a **sum of per-peer
      contributions with departed peers frozen**, the join snapshot as the
      **third trust boundary**, the `new_run(seed, around)` parameter and why the
      anchor chunk matters, and the hero-error-is-not-fatal landmine. Update the
      presence-packet field list. Move the phase-4 items out of the "deliberately
      not built" list and leave phase 5's there (shared croc sim, coin claim
      arbitration, migration, stall detection).
- [ ] **Do not touch `README.md`, `project.godot` or `.github/`** — a parallel
      bead owns those.
- [ ] re-run all three verification commands from Development Approach.

## Technical Details

### Snapshot vs presence — why both

The snapshot rides the **lobby relay** because it must be usable before any data
channel opens: the joiner needs the group's position to place itself and the
collected-coin set to generate its first chunks correctly, and ICE takes seconds.
Presence rides the **mesh** because it is 15 Hz forever and has no business on the
signalling socket. The snapshot is sent exactly once per (incumbent, joiner) pair.

### What is deliberately NOT built (phase 5 owns it)

Shared crocodile simulation; coin **claim arbitration** (two peers can still both
bank the same coin — the collected set is replayed at join and swept locally, not
arbitrated live); master stall detection and migration (the lobby's `stalled`
message stays unused). Do not implement any of these.

## Post-Completion

*No checkboxes — manual and external.*

**Manual verification** (needs two browsers and the live lobby, or a local one):
- A hosts, runs ~300 m banking coins and losing a life; B joins. B lands beside A
  on solid ground, is not bitten on arrival, sees no coins A already took, and
  both HUDs show the same bank, the same hearts and the same distance.
- B's hero row offers exactly the three heroes A is not embodying; A's E does
  nothing and buzzes; B leaving frees B's hero back into A's row.
- Two peers pressing the same hero button at once: one wins, the other gets a
  status line and **stays in the room**.
- Solo: boot with no room, play a run, die, Play Again — identical to master.
