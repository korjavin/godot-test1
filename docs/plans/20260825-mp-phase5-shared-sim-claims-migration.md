# MP phase 5: master croc simulation, pickup claims, stall detection + migration

Delivers bd issue **godot-test1-s86.5**. Phases 3 and 4 (`s86.3` PR #29, `s86.4`
PR #33) plus the discoverability work (`s86.9` PR #36) and treasure chests
(`20z.1` PR #35) are merged into master and are the base this builds on.

**Read these before writing a line** — `scripts/mp_manager.gd`,
`scripts/lobby_client.gd`, `scripts/remote_avatar.gd`,
`scripts/piglet_crocodile_ai.gd`, `scripts/crocodile_lod_manager.gd`,
`scripts/coin.gd`, `scripts/treasure_chest.gd`, plus **all** of `CLAUDE.md`
(the croc-AI, LOD-manager and multiplayer sections are load-bearing here).
Every rule they document still holds and this phase must not weaken any of them:

- **the isolation contract** — a `RemoteAvatar` joins no group, has no collision,
  is parented to the manager;
- **`_rtc` is NEVER assigned to `multiplayer.multiplayer_peer`** — the mesh stays
  a plain `PacketPeer`;
- **the three trust boundaries** — `_on_lobby_relay`, `decode_state`,
  `decode_presence`; this phase adds a fourth and it must be built the same way
  (static, pure, validated whole or dropped whole);
- **inert until a room is joined** — solo play stays byte-for-byte unchanged;
- **`SIM_RADIUS` (45) ≫ `DETECTION_RADIUS` (15)** — unchanged, and the
  generalised awake test below must preserve it.

> ⛔ **`scripts/endless_terrain.gd` IS READ-ONLY IN THIS BRANCH.** A parallel bead
> (`godot-test1-20z.1` follow-ups) owns it. Read it as much as you like; do not
> edit one character. Where the design would like a terrain hook, it is specified
> as a **group-lookup call that does not exist yet** and recorded as a follow-up
> — see Task 4's "coverage ceiling". Also do not touch `.github/workflows/`,
> `project.godot` or `README.md`.

## Overview

Phase 4 put 2–4 browsers in one world with a shared bank, shared hearts and a
mid-run join. There is still **no shared simulation**: every peer runs its own
crocodiles, and two peers can both bank the same coin. Phase 5 closes that:

1. **Master-simulated crocodiles.** The room master simulates every *awake* croc
   and broadcasts its transform plus a coarse state byte at ~10 Hz. Other peers
   stop running that croc's AI and render the synced state instead. Sleeping
   crocs cost **zero** network — their spawn state is the phase-1 deterministic
   pure function and every peer computes it identically.
2. **Awake = near ANY peer.** The LOD manager's single-player distance test
   becomes a **minimum over all member positions**. Offline that set is a single
   element, so the result is byte-identical to today.
3. **Pickup claim arbitration.** A coin (or a treasure chest) is *claimed*, the
   master *confirms*, the confirm is *broadcast*. First claim wins. The master
   owns the room's coin streak and puts the awarded amount in the confirm, so the
   shared bank can no longer double-count and the multiplier is the room's.
4. **Bites and shared game over.** Bites stay decided by the bitten peer's own
   local collision — phase 4's shared-lives sum already debits the pool with no
   authority — and the run now **ends for everyone** when the shared hearts hit
   zero.
5. **Abilities that touch crocs go through the master.** Phoboman's Stink Wave
   and giant-Teibi's crush become requests the master applies to the shared croc
   state. Windman and Primm are self-only and untouched.
6. **Stall detection and master migration.** The master heartbeats ~1 Hz; peers
   missing N heartbeats report `stalled` to the lobby, which already implements
   the quorum re-election. The new master resumes croc simulation from its own
   replica — which it has by construction, because it has been rendering the
   synced state all along.

Everything above is **inert outside a room**, tested by the same gates phase 4
used. Solo play must be byte-for-byte unchanged.

## Context (from discovery — do not re-litigate)

### The lobby already implements stall re-election — do not add server code

Verified by reading `server/room.go`, `server/conn.go`, `server/README.md`:

| direction | frame | meaning |
|---|---|---|
| client → server | `stalled` | `{"type":"stalled","id":"<current master id>"}` — one vote |
| server → client | `master` | `{"type":"master","id":"<new master>"}` — already handled |

`Room.ReportStalled` drops the vote unless `subject == r.master` and the reporter
is not the subject; it re-elects once `len(votes)*2 > len(members)-1`, i.e.
**strictly more than half of the non-master members**. With two members that is
one vote. A voted-out peer is never elected again while the room lives unless
everyone has been voted out, in which case the slate is wiped. `electLocked`
picks the **oldest surviving** member. **`server/` needs no change in this phase**
beyond leaving its tests green.

`LobbyClient` has no sender for that frame yet — one method, Task 7.

### Crocodile identity — derived from the node name, so the terrain needs no edit

Every crocodile the terrain spawns is named deterministically, **before**
`add_child`, from data that is a pure function of chunk coords and `run_seed`:

| spawner | name |
|---|---|
| `spawn_crocodiles_in_chunk` | `Crocodile_<cx>_<cy>_<index>` |
| `spawn_platform_crocodiles` | `PatrolCrocodile_<cx>_<cy>_<count>` (`count` **is** incremented — verified) |
| `spawn_bosses_in_chunk` | `BossCrocodile_<boss index>` |

Two peers sharing a `run_seed` therefore put the *same* crocodile, with the same
name, in the same place — exactly the property `Coin.id_at()` exploits for coins.
So:

```gdscript
static func croc_id_for(node_name: String) -> int:
    return node_name.hash()
```

latched in `_ready()` into `var _croc_id: int`, exposed as `croc_id()`. **This is
why no line of `endless_terrain.gd` has to change** — the same reasoning, and the
same shape, as the coin-id scheme.

`ponytail:` two ceilings to name in the comment. (1) A crocodile spawned outside
the terrain (the standalone `piglet_crocodile.tscn`, a future spawner) has a
non-unique name and would collide; it never happens in a room, and the failure
mode is one croc following another's transform, not a crash. (2) `String.hash()`
is 32-bit, so a collision across the ~1000 loaded crocs is a ~1e-4 birthday
chance per run; the upgrade path is the same one the coin id has — thread an
explicit `(chunk, index)` id out of the spawners.

### Chunk parenting — the landmine, and the decision

The bead names this as the real design work and leaves the HOW to the developer.
**The decision, which the implementation must follow and CLAUDE.md must record:**

> **Crocodile lifetime does not change at all.** Crocs stay chunk-parented,
> per-peer, deterministic, freed on chunk unload — exactly as today. The sync
> layer **overlays dynamic state onto locally-existing nodes matched by
> deterministic id**; it never creates, re-parents or frees a crocodile.

Why this is correct rather than merely small — the two directions of the problem:

- **"A peer may not have generated the chunk a synced croc lives in."** It cannot
  happen for a croc that matters. A croc is only ever *awake* (and therefore only
  ever broadcast) when it is within `SIM_RADIUS` (45 m) of some peer, and a peer's
  own terrain builds `render_distance` chunks around itself — 3 × 50 m = **150 m**
  on the web build, 250 m on desktop. 45 ≪ 150, so **any croc near a peer is
  already loaded on that peer**. A sync sample naming a croc this peer does not
  have is simply dropped.
- **"The master may unload a chunk another peer still stands in."** It can, and
  this is the real ceiling. The master only simulates crocs *its own* terrain has
  loaded, so a peer more than ~150 m from the master is outside the master's
  coverage and its nearby crocs get no samples. Those crocs **fall back to local
  simulation** after `CROC_SYNC_TIMEOUT` — i.e. exactly today's behaviour, for
  exactly the peers who cannot see each other anyway (150 m is far past the fog).
  Two distant peers then disagree about croc positions, which is invisible to
  both. Nothing duplicates, nothing vanishes, no croc is ever created by the sync
  path.

`ponytail:` the coverage ceiling is "crocs further than the master's render
distance are locally simulated". The upgrade path is a terrain hook the master
calls with the union of peer positions —
`terrain.set_focus_points(points: Array[Vector3])`, keeping chunks loaded around
every peer rather than only the local player. **`endless_terrain.gd` is read-only
in this branch**, so define nothing for it here; record the hook in the handoff as
a follow-up bead.

This also delivers **hot standby for free**: a non-master's synced crocs are real
local nodes holding the master's last known transform, so promotion is
`remote_driven = false` + `set_physics_process(true)` and the croc carries on from
where it stood.

### Bites and the shared lives pool are ALREADY mostly built — do not build a protocol

Phase 4 made `lives` a pure function of the room's bank and the room's spent
lives (`shared_lives_from`), summed from the `lv` field every peer broadcasts in
presence, with departed peers frozen in `_gone_spent`. So:

- "the bite is decided by the peer being bitten, by its own local collision" —
  **already true**: `piglet_crocodile_ai._handle_collisions()` runs on the bitten
  peer's machine and calls `player.hit_by_crocodile()`.
- "reported to the master, which debits the shared lives pool and broadcasts" —
  **already achieved, with no master at all**: `own_lives_spent += 1` and the next
  presence packet 66 ms later carries it to everyone as an absolute value.

**The only missing piece is that the run does not end for everyone.** A peer who
was not bitten never reaches `_on_caught_finished()`, so it never notices the
room's hearts hit zero. That is Task 6 and it is a handful of lines, not a
protocol. **Do not add a bite message.**

### Treasure chests award the shared bank without arbitration — same bug class

`scripts/treasure_chest.gd` (merged three days ago) calls
`player.collect_coin(1)` N times over `CHEST_BURST_DURATION` instead of spawning
coin nodes. Chests are deterministic and exist on every peer, so in a room every
peer can open the same chest and each award lands in the shared bank — the same
double-count claim arbitration exists to fix, one order of magnitude larger
(a chest is ~12 pickups). It routes through the **same** claim machinery, keyed
by `Coin.id_at(chest.global_position)`, with the whole burst as one claim. Do not
build a second mechanism for it.

### Godot / project facts established during discovery

- The mesh is a plain `PacketPeer`. `_rtc.set_transfer_mode(...)` is set per send;
  presence uses `TRANSFER_MODE_UNRELIABLE`. Reliable sends are available and used
  by this phase for claims, confirms and kills.
- `decode_presence(bytes)` is the current mesh decoder and `mp_selfcheck.gd` pins
  its signature — **keep it**. New packet types are discriminated by a `"t"` key
  which today's presence packets do not carry, so a phase-3/4 peer keeps working
  and a phase-5 packet reaching an older peer falls through its validation and is
  dropped. That is the forward/backward compatibility rule already stated for
  `_on_lobby_relay`'s unknown verbs.
- `crocodile_lod_manager._scan_crocodiles()` also publishes the danger telegraph
  from the same pass. That must keep working for synced crocs — which it does,
  because a remote-driven croc's `is_chasing` is set from the state byte.
- `set_lod_active(false)` refuses to sleep a croc that is not `is_on_floor()`,
  zeroes velocity, and clears flee state. Read its docstring before touching it.
- The lobby is at `wss://ck.wandergeek.org`; a local one is `cd server && go run .`.
- `--lobby-only` skips the WebRTC mesh entirely. **Everything that must be
  testable headless has to ride the lobby relay, not the mesh** — that is why the
  heartbeat is on the relay (Task 7).

## Development Approach

- **Testing approach**: NO unit-test framework, no linter, no build script. The
  gates, all of which must pass before the final task is ticked:
  - `godot --headless --path . --import` — no script errors;
  - `godot --headless --path . scenes/main.tscn --quit-after 240` — boots and
    exits clean (**the solo-play regression gate**: MP is inert offline, so any
    error here means solo play broke);
  - `godot --headless --path . --script res://scripts/mp_selfcheck.gd` — prints
    `SELFCHECK OK`, exits 0;
  - `godot --headless --path . --script res://scripts/minimap_selfcheck.gd` —
    prints `SELFCHECK OK`, exits 0;
  - `cd server && go build ./... && go test ./...` — green (this phase adds no
    server code; the gate is that it stays green);
  - `bash scripts/mp_e2e.sh` — exits 0, now also proving stall → re-election.
- **NEVER run frontend/JS tests.** CI's web export is that gate, not a local one.
- Complete each task fully before moving to the next.
- **Match the project's comment density.** CLAUDE.md: "the codebase is written to
  be read". Explicit type hints on every var, param and return; tunables as
  `const` at the top of the script that owns them; a docstring on every function
  that says *why*, not *what*.
- Mark deliberate simplifications with a `ponytail:` comment naming the ceiling
  **and** the upgrade path.
- **Smallest coherent diff.** Reuse `_absorb_collected`'s sweep, `_collected_ids`,
  `shared_lives_from`, `_refresh_shared_totals`, the `"mp"` / `"terrain"` /
  `"player"` / `"crocodile"` / `"coin"` group lookups, `_sfx()`, `_is_number()`.
  Add no new manager node, no new scene, no new autoload, no new group.
- **Do not edit** `scripts/endless_terrain.gd`, `.github/workflows/`,
  `project.godot`, `README.md`.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: none.
- **Integration test**: `scripts/mp_selfcheck.gd`, extended (Task 8) with the new
  *pure* logic only — the croc-sync decoder against hostile input, croc-id
  stability, the claim/streak arithmetic and the stall predicate. Do not grow it
  into a suite and do not put anything needing a socket in it.
- **E2E**: `scripts/mp_e2e.sh`, extended (Task 9) to cover what `--lobby-only`
  *can* cover — a stalled master, a quorum report and a re-election. The croc
  mesh sync and the avatars still need two real browsers (Post-Completion).

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: `piglet_crocodile_ai.gd` — identity, remote-driven mode, the dead set

- [x] add `static func croc_id_for(node_name: String) -> int: return node_name.hash()`
      and `var _croc_id: int = 0` latched in `_ready()` from `String(name)`,
      exposed as `func croc_id() -> int`. Document the scheme and both
      `ponytail:` ceilings from the Context section. **Latch in `_ready()`, never
      recompute** — the same contract, for the same reason, as `coin.gd`'s `_id`.
- [x] add `var remote_driven: bool = false` plus
      `func set_remote_state(pos: Vector3, yaw: float, flags: int) -> void`, which
      stores `_remote_pos` / `_remote_yaw`, decodes the flag bits into
      `is_chasing` / `is_fleeing` / `is_paused` / `is_biting`, and on the FIRST
      sample (or when `global_position.distance_to(pos) > CROC_TELEPORT_DISTANCE`,
      a new `const` = 8.0) snaps rather than interpolates. Set
      `remote_driven = true` here; it is the only place that turns it on.
- [x] add `func clear_remote_drive() -> void` — `remote_driven = false`, resume
      normal simulation from wherever the body currently stands. Called on the
      sync timeout and on promotion to master.
- [x] at the very top of `_physics_process`, **above** the `lod_active` backstop,
      add the remote branch:
      ```gdscript
      if remote_driven:
          _tick_remote(delta)
          return
      ```
      `_tick_remote` eases `rotation.y` with `lerp_angle` toward `_remote_yaw`,
      drives `velocity` toward `_remote_pos` (`(_remote_pos - global_position) / delta`,
      clamped to a sane `CROC_REMOTE_MAX_SPEED` const so a bad sample cannot
      launch the body), calls `move_and_slide()`, then `_handle_collisions()` and
      `_animate_body(delta)`.
      **`move_and_slide()` is deliberate, not incidental**: it is what keeps a
      synced croc solid to the player and what makes the *bitten* peer detect its
      own bite locally, which is the bite rule this phase is specified against.
      Say so in the docstring.
- [x] in `_ready()`, after the group joins, ask the `"mp"` group (null-safe,
      `has_method("is_croc_dead")`) whether this id was already killed in this
      room; if so `queue_free()` and return. **Exactly the shape and placement
      `coin.gd` uses for `is_coin_collected`** — one failed group lookup per croc
      at spawn, never per frame, and a no-op offline.
- [x] in `_on_player_collision`, the giant-Teibi crush block: in a room the crush
      must be the master's decision, not this peer's. Before the local squash,
      ask the `"mp"` group `has_method("request_croc_kill")`; if it answers
      `true` (meaning "in a room — I have relayed the request"), **return without
      squashing** and let the master's kill broadcast free this croc. Offline (or
      when the manager is absent) it returns false and the existing squash runs
      **byte-for-byte unchanged**.
- [x] `flee_from()` is NOT changed. A remote-driven croc's flee state arrives in
      the flags byte; the local call is harmless because a remote-driven croc
      takes its motion from the samples. Say so in a comment so the next reader
      does not "fix" it.
- [x] `set_lod_active` is NOT changed.

⚠️ `minimap_selfcheck.gd` already fails on this branch's base commit
("SELFCHECK FAILED: minimap never read the player") — verified by stashing this
task's diff and re-running. Pre-existing and unrelated to phase 5; flagged here
for the final task's gate run.

### Task 2: `crocodile_lod_manager.gd` — awake means near ANY peer

- [x] in `_scan_crocodiles()`, build the position set once per scan:
      the local player's `global_position`, plus — when the `"mp"` group node
      answers `has_method("peer_positions")` — every position it returns.
      `peer_positions()` returns `null` offline (Task 3), so the offline set is a
      one-element array and **the whole pass stays byte-identical**. Say that in
      the comment: it is the load-bearing claim for "solo play is unchanged".
- [x] replace `dist_sq` with the **minimum** squared distance over that set. This
      is the "generalisation of the LOD test" the bead specifies, and it is what
      keeps `SIM_RADIUS ≫ DETECTION_RADIUS` true for every member, not just for
      the local one.
- [x] the danger-telegraph read (`is_chasing` / `detection_radius`) must keep
      using the **local player's** distance, not the min — the vignette is this
      player's own danger, not the room's. Keep both distances; name them
      clearly (`dist_sq_any` vs `dist_sq_local`).
- [x] skip the awake/asleep **decision** for a croc with `remote_driven == true`
      (`in` guard, same defensive style as `is_boss`) — the sync layer owns its
      processing and the LOD manager must not fight it. Do **not** skip the croc
      before the danger read: a synced croc chasing this player must still light
      the vignette.
- [x] `_scan_coins()` is unchanged.
- ➕ [x] `scripts/minimap_selfcheck.gd`: dismiss the start overlay (added by
      `s86.9`, merged into this branch's base) before the 2 s wait. The overlay
      pauses the tree at boot, so the gate was failing with "minimap never read
      the player" **before this task's first line** — verified against the
      unmodified file. The `await process_frame` before the press is load-bearing:
      `_initialize()` runs ahead of the scene's `_ready()`s, so an earlier press
      is undone by the overlay taking the pause afterwards with its `_process`
      already off. Gate now prints `SELFCHECK OK`.

### Task 3: `mp_manager.gd` — the fourth trust boundary and mesh packet dispatch

- [x] introduce the `"t"` discriminator. Split the current `_receive_presence()`
      loop so it decodes `bytes_to_var` **once** into a Dictionary, then:
      no `"t"` key → today's presence path; `"t"` present → `match str(state["t"])`
      over the new verbs; an unknown verb is ignored **without** a warning
      (forward compatibility, the same rule `_on_lobby_relay` states).
      **Keep `static func decode_presence(bytes: PackedByteArray) -> Dictionary`
      exactly as it is** — `mp_selfcheck.gd` pins it. Factor its body into a
      `static func _decode_presence_dict(state: Dictionary) -> Dictionary` that
      both paths call, so there is one validator, not two.
- [x] **`bytes_to_var`, never `bytes_to_var_with_objects`** — restate that in the
      new dispatcher's docstring. It is the sharpest rule in the file.
- [x] add the croc-sync decoder, the fourth trust boundary, static and
      `_rtc`-free so the selfcheck can beat on it:
      ```gdscript
      static func decode_croc_sync(state: Dictionary) -> Dictionary
      ```
      Wire format (`var_to_bytes` of):
      ```
      {"t": "croc",
       "i": PackedInt32Array,    # one croc id per entry
       "x": PackedFloat32Array,  # 4 per entry: px, py, pz, yaw
       "f": PackedByteArray}     # one state byte per entry
      ```
      Validate, **whole or nothing** (return `{}` on any failure), in this order:
      each field present and of exactly the right packed type; `i.size() == f.size()`;
      `x.size() == i.size() * 4`; `i.size() <= MAX_CROC_SYNC` (a new const, 192 —
      generous, it exists to reject hostile garbage, not to police the pack);
      every float finite **before any cast** and `absf(...) <= MAX_PRESENCE_COORD`
      (reuse the existing const; a NaN or a 1e30 would poison a croc's
      interpolation for the room's life exactly as it would an avatar's).
      Return `{"ids": PackedInt32Array, "xf": PackedFloat32Array, "flags": PackedByteArray}`.
      Wrap yaw with `fposmod(yaw, TAU)` for the same reason `decode_presence`
      does — `lerp_angle` is `from + short_way * weight` and `1e30 + small IS 1e30`.
- [x] add the state-byte constants next to it and use them on both sides:
      `CROC_FLAG_CHASING = 1`, `CROC_FLAG_FLEEING = 2`, `CROC_FLAG_PAUSED = 4`,
      `CROC_FLAG_BITING = 8`. One place, so the encoder and decoder cannot drift.
      *(Landed with Task 1, which needed them for `set_remote_state()`; the
      encoder in Task 4 reads the same consts.)*
- [x] add `func peer_positions() -> Variant` — an `Array[Vector3]` of every other
      member's last known position (from `_peer_state`), or **`null` offline**, so
      the LOD manager falls through to solo behaviour on one `== null` test. Same
      `null`-means-solo shape as `my_character_indices()` and `shared_bank()`.
- [x] `leave()` must reset every new room-scoped field this phase adds. It is
      already the single unwind point and it must stay complete — a field left
      behind is a bug that only shows up on the second room of a session.
      *(Verified: this task adds no new room-scoped mutable field — the decoder
      and the presence split are static/pure, and `peer_positions()` derives from
      `_peer_state`, which `leave()` already empties. Tasks 4 and 7 add fields and
      must extend `leave()` themselves.)*

### Task 4: `mp_manager.gd` — master croc simulation and the sync broadcast

- [x] add `const CROC_SYNC_HZ: float = 10.0` and a `_croc_accum` accumulator
      ticked in `_process` alongside `_send_accum`. Only the master sends.
- [x] add `const CROC_SYNC_RADIUS: float = 55.0` — the radius around **each
      target peer** whose crocs that peer is sent. It must exceed the LOD
      manager's sleep radius (`SIM_RADIUS + HYSTERESIS_MARGIN` = 50) so a croc
      cannot be awake-for-that-peer yet outside its sync window; assert the
      relationship in a comment, exactly as `SIM_RADIUS ≫ DETECTION_RADIUS` is
      asserted in the LOD manager.
- [x] `_send_croc_sync()` (master only, mesh, **unreliable** — a dropped sample is
      replaced 100 ms later and re-sending a stale transform would be strictly
      worse, the same argument presence makes): iterate the `"crocodile"` group
      **once**, and for each croc that is `is_instance_valid`, `lod_active`, not
      `remote_driven` and exposes `croc_id`, append it to the per-target buffer of
      every connected peer within `CROC_SYNC_RADIUS` of that peer's last known
      position. **One pass over the group, N buffers** — never one pass per peer.
      Then one `put_packet` per target.
      Per-peer filtering is what keeps this affordable: ~25 crocs inside 55 m of a
      peer × 21 bytes × 10 Hz ≈ 5 KB/s per peer, against ~100 KB/s for an
      unfiltered broadcast of the whole awake set. Put those numbers in the
      docstring — the file already documents presence's bandwidth this way.
- [x] receive side (non-master): on a `"croc"` packet, **drop it unless it came
      from the master** (`from_id != _master`), for the same reason only the
      master's `seed` is accepted — the mesh is peer input and a member could
      otherwise drive everyone's crocodiles. Then, for each entry, find the local
      croc with that id and call `set_remote_state(...)`. Record
      `_croc_seen[id] = Time.get_ticks_msec()`.
- [x] **croc lookup must not be a group scan per entry.** Maintain
      `_synced_crocs: Dictionary` (croc id → the croc node), populated lazily: on
      a miss, scan the `"crocodile"` group once, cache every id, and retry. Purge
      invalid instances on each sync tick. A miss that stays a miss (the chunk is
      not loaded here) is dropped silently — that is the expected case, not an
      error, and it must not warn at 10 Hz.
- [x] add `const CROC_SYNC_TIMEOUT: float = 2.0` and a tick that calls
      `clear_remote_drive()` on any croc whose last sample is older than that.
      This is what makes the master's **coverage ceiling** degrade gracefully
      (Context) *and* what makes migration seamless: a ~1 s election gap is well
      inside the window, so crocs never visibly stall during a handover.
- [x] on `_on_lobby_master_changed`, if **we** became master, call
      `clear_remote_drive()` on every synced croc immediately and empty
      `_synced_crocs` / `_croc_seen`. That is the "resume from the hot-standby
      replica" step, and it is one loop because the replica is just the local
      nodes holding the last synced transform.
- [x] on `leave()`, clear the remote drive on everything — a peer that leaves a
      room must not be left holding frozen crocodiles in its solo run.
- [x] `ponytail:` comment naming the coverage ceiling and the
      `terrain.set_focus_points()` upgrade path from the Context section.

### Task 5: pickup claims — `mp_manager.gd`, `coin.gd`, `treasure_chest.gd`, `player_controller.gd`

The protocol, all over the **mesh, reliable** (`TRANSFER_MODE_RELIABLE`):

```
claim   peer  → master  {"t":"clm","id":int,"n":int,"v":int}
confirm master→ all     {"t":"cnf","id":int,"by":int,"a":int,"m":int}
```
`n` = how many *pickups* (1 for a coin, the chest's count for a chest), `v` = the
base value per pickup (1, or `Coin.GEM_VALUE`), `by` = the winner's
`peer_int_id`, `a` = the total awarded after the room's multiplier, `m` = the
room's multiplier after the award (for the HUD suffix).

- [x] `mp_manager.gd`: `func claim_pickup(id: int, count: int, value: int) -> bool`.
      Returns **false offline** so every caller falls through to today's solo path
      on one test. In a room: if we are the master, resolve immediately; else send
      the claim and park it in `_pending_claims[id]`.
- [x] master resolution, `_resolve_claim(id, by_int, count, value)`:
      refuse if `_collected_ids.has(id)` (**first claim wins**, and this reuses the
      set phase 4 already keeps and already replays to joiners — do not add a
      second set); otherwise record it, advance the **room streak** `count` times
      (`_room_streak += 1`, `_room_streak_deadline = now + STREAK_WINDOW`; the
      window and the step come from `player_controller`'s existing constants,
      referenced, never re-typed), accumulate `value * multiplier` per pickup, and
      broadcast the confirm to every connected peer **and apply it locally**.
- [x] the room multiplier is one pure static function so the selfcheck can pin it:
      `static func room_multiplier_from(streak: int, per_step: int, max_bonus: int) -> int`
      — the same arithmetic as `player_controller.get_streak_multiplier()`,
      extracted rather than duplicated in spirit. Expose
      `func room_multiplier() -> Variant` returning `null` offline.
- [x] confirm handling on every peer: record the id in `_collected_ids`, sweep the
      live world for it (**reuse `_absorb_collected([id])`** — it already frees
      matching coins and makes arrival order irrelevant), drop any
      `_pending_claims[id]`, store `m`, and — only when `by == peer_int_id(_you)`
      — call `player.bank_awarded(a)`.
- [x] claim retry: `const CLAIM_RETRY_SEC: float = 0.5`,
      `const CLAIM_MAX_TRIES: int = 4`. Re-send an unconfirmed claim on that
      cadence; when the budget runs out, **resolve it locally** (bank it with the
      local multiplier and record the id) rather than eating the pickup.
      `ponytail:` the ceiling is a rare double-count when the confirm was merely
      slow; the alternative — a coin that vanished and paid nothing — is worse,
      and the upgrade path is a master ACK on the claim itself.
- [x] `_pending_claims` must be cleared by `leave()` and re-driven from `_process`
      (one dictionary walk, only while non-empty).
- [x] `coin.gd` `_on_body_entered`: when `mp.claim_pickup(coin_id(), 1, value)`
      returns true, set `collected = true`, hide the coin
      (`visible = false`, `set_deferred("monitoring", false)`) and play the pop and
      the blip so the pickup still *feels* instant — but **do not** call
      `collect_coin` and **do not** `queue_free`; the confirm's sweep owns both.
      When it returns false, today's path runs unchanged. The existing
      `report_coin_collected` call is now redundant on the claim path — keep it
      only on the offline path, or drop it and let `_resolve_claim` be the single
      writer; say which in a comment.
- [x] `treasure_chest.gd`: give the chest the same id
      (`Coin.id_at(global_position)`, latched in `_ready()` before anything moves
      it) and the same `is_coin_collected` check at spawn. In `_on_body_entered`,
      claim `(id, coin_count, 1)` as **one** claim; start the burst only when the
      confirm lands (a `_burst_armed` latch fed by the manager, or — simpler and
      preferred — the confirm calls `player.bank_awarded(a)` and the chest just
      plays its visual burst with **no** `collect_coin` calls at all in a room).
      Pick the second: the master already computed the whole award, so the chest's
      job in a room is purely the animation. Say so in the docstring.
- [x] `player_controller.gd`: add
      `func bank_awarded(amount: int) -> void` — `coins_collected += amount`,
      `own_coins += amount`, and the existing extra-life `while` loop, with a
      docstring saying the multiplier was **already applied by the master** so it
      must not be applied again. `collect_coin()` stays the solo/offline path,
      unchanged.
- [x] `player_controller.get_streak_multiplier()` consults the `"mp"` group's
      `room_multiplier()` and uses it when it is not null, else today's local
      value. That is one edit in one function, and it makes `coin_hud.gd` show the
      room's `(xN)` with **no HUD change** — the same trick phase 4 used for the
      bank and the hearts.

### Task 6: abilities through the master, and the shared game over

- [x] `mp_manager.gd`: `func request_croc_flee(origin: Vector3, duration: float) -> void`
      — a no-op offline. On the master, apply it directly to the local
      `"crocodile"` group (the existing loop); on a non-master, send
      `{"t":"flee","x","y","z","d"}` to the master, reliable. The master applies
      `flee_from` on receipt; the resulting `is_fleeing` reaches every peer in the
      next sync packet's flag byte, so **no separate flee broadcast is needed**.
      Validate `x`/`y`/`z`/`d` finite and bounded — it is peer input.
- [x] `player_controller.gd` Stink Wave: keep the existing local loop **exactly as
      it is** (harmless on remote-driven crocs, correct on locally-simulated ones)
      and additionally call `request_croc_flee(...)` through the null-safe `_mp()`
      helper. One added line.
- [x] `mp_manager.gd`: `func request_croc_kill(id: int) -> bool` — false offline
      (so Task 1's crush branch falls through to today's squash). In a room:
      master resolves immediately, non-master sends `{"t":"kill","id":int}`.
      Master resolution records the id in `_dead_crocs`, broadcasts
      `{"t":"dead","id":int}` reliably, and frees its own copy. Every peer on
      `"dead"`: record the id, find the croc (via the same `_synced_crocs` cache
      plus a group fallback) and run the existing squash-and-free visual, so a
      crush still *reads* as a crush on every screen.
- [x] `func is_croc_dead(id: int) -> bool` — `_state == IN_ROOM and _dead_crocs.has(id)`,
      for Task 1's `_ready()` check. `_dead_crocs` is room-scoped and cleared by
      `leave()`.
      `ponytail:` the dead set is **not** replayed in the join snapshot, so a peer
      joining later can see a crushed croc alive again, and a chunk reload can
      resurrect one for a peer whose set was cleared. It is the same class of
      ceiling as `MAX_STATE_IDS`; the upgrade path is an extra `dead` array on the
      join snapshot, bounded the same way.
- [x] **shared game over.** In `player_controller._refresh_shared_totals()` (or
      immediately after it in `_physics_process`), when the room's hearts are 0,
      we are not already `is_game_over`, and not mid-`is_caught`, call
      `_trigger_game_over()`. That is what makes "the run ends for everyone
      together" true for the peers who were not bitten. Guard it so it can only
      fire in a room (`shared_lives_spent(...) != null`) — solo, hearts only reach
      0 through `_on_caught_finished`, which already ends the run, and firing here
      would change solo behaviour.
- [x] Windman and Primm are **not** touched — they are self-only.

### Task 7: heartbeat, stall detection, migration — `lobby_client.gd` + `mp_manager.gd`

- [ ] `lobby_client.gd`: `func send_stalled(master_id: String) -> void` sending
      `{"type": "stalled", "id": master_id}`. One method, matching `send_hero`'s
      shape and docstring style, including the note that the lobby answers with a
      `master` broadcast **only** once the quorum is reached and says nothing
      otherwise — a vote is not a request.
- [ ] `mp_manager.gd`: `const HEARTBEAT_INTERVAL: float = 1.0`,
      `const HEARTBEAT_TIMEOUT: float = 4.0`,
      `const STALL_REPORT_INTERVAL: float = 2.0`.
- [ ] **the heartbeat rides the LOBBY RELAY, not the mesh, and that is a
      deliberate deviation from the bead's wording — document it.** Three
      reasons, all of which belong in the docstring: (1) it is what a *throttled
      tab* stops doing, and a throttled tab stops polling the socket and the mesh
      alike, so either transport detects it equally; (2) `--lobby-only` has no
      mesh, so a mesh heartbeat would make the whole migration path untestable
      headless — and `scripts/mp_e2e.sh` is where this phase's automated evidence
      lives; (3) it is 1 Hz to at most 3 peers, i.e. nothing, on a socket that
      already carries a 20 s ping.
- [ ] master side: broadcast `{"mp": "hb"}` through `_lobby.send_signal_to("")`
      every `HEARTBEAT_INTERVAL`. Add
      `@export var heartbeat_enabled: bool = true` so a headless test (and a
      developer) can simulate a throttled tab by turning it off — name it for what
      it is in the export's comment, and note that nothing in the UI exposes it.
- [ ] peer side: handle `"hb"` in `_on_lobby_relay` — accept it **only from the
      master** (the same rule as `seed`), stamp `_last_hb_msec`. The verb *is* the
      whole message, so there is nothing to validate; say that explicitly, as the
      `seed_req` handler already does, so it does not read as a missing check at a
      trust boundary.
- [ ] `_tick_stall_watch(delta)` in `_process`, ordered **before** the `_rtc`
      guard for the same reason `_tick_seed_request` is — it must work with no
      mesh. Early-return unless `IN_ROOM`, `_master` is non-empty, `_master != _you`
      and there is more than one member. When `now - _last_hb_msec > HEARTBEAT_TIMEOUT`,
      call `_lobby.send_stalled(_master)` at most once per `STALL_REPORT_INTERVAL`
      and emit a `status` line once ("Host not responding — voting to migrate…"),
      so a silent failure is visible in the panel with **no UI change**, exactly
      as the seed retry does.
- [ ] `_last_hb_msec` must be **stamped fresh** in `_on_lobby_joined` and in
      `_on_lobby_master_changed`. Without that a joiner votes to depose a
      perfectly healthy master four seconds after arriving, and a new master is
      deposed by the timer that was running against the old one.
- [ ] `_on_lobby_master_changed` additionally: reset the stall clock, and if we
      are the new master do Task 4's promotion (`clear_remote_drive()` on
      everything) and start heartbeating. If we are **not**, keep waiting on the
      new master. The existing seed re-broadcast behaviour stays exactly as it is.
- [ ] `leave()` resets the heartbeat and stall state.

### Task 8: extend `scripts/mp_selfcheck.gd`

Pure logic only. Keep the existing checks passing and follow their style — each
check is a function returning `""` on success or a message on failure.

- [ ] `_check_croc_sync_parser()`: a well-formed packet decodes with the right
      counts; each of these is dropped **whole**: a missing field, a wrong type
      per field (`Array` where a `PackedInt32Array` is required), `i.size()`
      mismatching `f.size()`, `x.size()` not `4 * i.size()`, a count past
      `MAX_CROC_SYNC`, a NaN, an infinity, a coordinate past `MAX_PRESENCE_COORD`.
      Also assert a `1e30` yaw comes back wrapped into `[0, TAU)` rather than
      dropped — the same normalise-don't-drop rule `decode_presence` applies.
- [ ] `_check_croc_ids()`: `croc_id_for("Crocodile_3_-4_2")` is stable across
      calls, differs from `Crocodile_3_-4_3` and from `PatrolCrocodile_3_-4_2`,
      and a live croc's `croc_id()` matches `croc_id_for(String(croc.name))`.
- [ ] `_check_room_multiplier()`: pin `room_multiplier_from` against the same
      table `player_controller.get_streak_multiplier()` produces — x1 at 0, the
      step at `STREAK_COINS_PER_STEP`, the cap at `1 + STREAK_MAX_BONUS`.
- [ ] `_check_presence_backcompat()` (existing) must still pass: a phase-3/4
      packet with **no** `"t"` key still decodes. Add the mirror: a packet whose
      `"t"` names an unknown verb is ignored rather than treated as presence.
- [ ] register the new checks in `_run_checks()` and keep the final
      `SELFCHECK OK` / exit 0 contract.

### Task 9: extend `scripts/mp_e2e.gd` + `scripts/mp_e2e.sh` — stall → re-election

`--lobby-only` has no mesh, so this covers the **relay half** of phase 5: a
stalled master, a quorum vote, a lobby re-election and the survivor learning it
is master. That is precisely the part `mp_selfcheck` cannot reach and two
browsers are needed for everything else.

- [ ] `mp_e2e.gd`: print `E2E_YOU=<our lobby id>` and `E2E_MASTER=<master id>`
      alongside the existing `E2E_ROOM=` / `E2E_SEED=` lines. Add a `--stall`
      flag for the host role that sets `mp.heartbeat_enabled = false` once the
      room exists — the simulated throttled tab. The host **must keep its socket
      open** (it still `--hold`s), or the lobby's ordinary disconnect
      re-election fires and the test would pass for the wrong reason. Say that in
      the file's header comment, in the same voice as the existing "the host must
      use `host()`, not a fixed code" warning.
- [ ] `mp_e2e.gd`: add a `--await-master` flag for the join role — after printing
      its lines, poll until the manager reports **itself** as master, then print
      `E2E_NEWMASTER=<id>` and quit 0; time out into the existing `_fail` path.
      Expose whatever minimal read it needs (`mp.get_master()` — add it to the
      manager if it does not exist; it is one line and `mp_ui.gd` can use it too).
- [ ] `mp_e2e.sh`: after the existing seed assertion, keep the same host process
      alive and add the stall phase — host started with `--stall`, joiner with
      `--await-master`; assert `E2E_NEWMASTER` from the joiner equals the joiner's
      own `E2E_YOU` and differs from the host's `E2E_YOU`. Size the host's
      `--hold` so it outlives the vote. Report a failure the way the script
      already does (`fail`, with the tail of every log), never as a note.
- [ ] keep the whole script's existing structure: per-run port, built (not
      `go run`) lobby binary, `cleanup` trap, `/rooms` check, seed comparison.
      Add a phase; do not restructure it.
- [ ] **Do NOT edit `.github/workflows/`.** Note in the handoff that wiring this
      script into CI remains the one-job follow-up phase 4 already recorded.

### Task 10: [Final] Update documentation

- [ ] `CLAUDE.md`: extend "Multiplayer (phases 3–4)" into a phases 3–5 account, in
      the file's existing voice and density. It must cover, at minimum:
      - **the croc-lifetime decision and why it is the shape it is** — crocs stay
        chunk-parented and per-peer; the sync layer only overlays dynamic state on
        locally-existing nodes matched by a deterministic id; the two directions of
        the chunk-parenting landmine and why neither can produce a duplicate or a
        vanished croc; the master's **coverage ceiling** and the
        `terrain.set_focus_points()` upgrade path. This is the bead's headline
        design decision — give it the space the "coin identity" and "join snapshot"
        paragraphs get.
      - **awake = near ANY peer**, and that `peer_positions()` returning `null`
        offline is what keeps the LOD pass byte-identical solo;
      - the croc id scheme and both `ponytail:` ceilings;
      - the **fourth trust boundary** (`decode_croc_sync`), the `"t"` discriminator
        and why a phase-3/4 peer is unaffected;
      - the sync packet's shape, rate, **per-peer radius filtering** and its
        measured bandwidth, next to the presence packet's existing paragraph;
      - **claim → confirm → broadcast**, first claim wins, the master-owned room
        streak, why `_collected_ids` is reused rather than duplicated, the retry
        budget and its resolve-locally ceiling, and that **treasure chests use the
        same claim**;
      - that **bites needed no protocol** — phase 4's shared-lives sum already
        does it — and that the only new piece is the shared game over;
      - abilities through the master, the dead set and its join-snapshot ceiling;
      - the heartbeat/stall/migration path, the **relay-not-mesh deviation and its
        three reasons**, and that the hot standby is free because a non-master's
        synced crocs *are* the replica;
      - move the phase-5 items out of "deliberately not built".
      Also update the "Commands" block if the E2E's description changed.
- [ ] **Do not touch** `README.md`, `project.godot`, `.github/` or
      `scripts/endless_terrain.gd`.
- [ ] re-run **every** gate from Development Approach and record the results here.

## Technical Details

### Why the croc sync rides the mesh but the heartbeat rides the relay

They are answering different questions. The croc stream is 10 Hz of bulk state
between players — exactly what the P2P mesh exists for, and putting it on the
lobby would drag game state onto the one server this architecture keeps
game-free. The heartbeat is one tiny liveness token per second whose entire job
is to be *missing*, and it has to work where the mesh does not exist
(`--lobby-only`), because that is the only configuration a headless test can
reach. Both transports die together when a tab is throttled, so detection is
identical either way.

### What is deliberately NOT built

- **No croc creation over the network.** The sync layer never spawns, re-parents
  or frees a crocodile except through the explicit kill broadcast; every
  crocodile still comes from the deterministic terrain spawn.
- **No bite protocol.** See Context.
- **No replication of the dead set on join** (ceiling documented).
- **No terrain change.** The master's chunk coverage is what it is; the focus-hook
  upgrade is a follow-up bead.
- **No `multiplayer.multiplayer_peer` assignment.** Still forbidden.

## Post-Completion

*No checkboxes — manual and external.*

**Manual verification** (two browsers plus the live lobby, or a local one):
- A hosts and runs 300 m; B joins. Both see the **same** crocodiles in the same
  places doing the same things, and a croc chases whichever of them it detects.
- A and B race one coin: exactly one bank increments, and both HUDs agree.
  Repeat with a treasure chest.
- B crushes a croc as giant Teibi: it dies on **both** screens.
- A fires Phoboman's Stink Wave: crocs near B flee too.
- Kill A's tab mid-chase (or background it long enough to throttle): within a few
  seconds B is master, the crocs keep moving with no stall and no duplicates, and
  the bank, hearts and distance are intact.
- Let the shared hearts hit zero: the Game Over screen comes up on both.
- Solo: boot with no room, play a run, open a chest, die, Play Again — identical
  to master.

**Follow-up beads to file in the handoff:**
- `terrain.set_focus_points(points)` so the master keeps chunks loaded around
  every peer, closing the coverage ceiling.
- Replay the dead-croc set in the join snapshot.
- Wire `scripts/mp_e2e.sh` into CI (still owned elsewhere).
