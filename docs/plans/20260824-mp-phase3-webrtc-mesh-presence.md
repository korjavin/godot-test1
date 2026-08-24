# MP phase 3: WebRTC mesh + presence — see friends in a shared-seed world

Delivers bd issue **godot-test1-s86.3**. Phases 1 (deterministic croc rolls) and 2
(the Go lobby in `server/`) are already merged into master.

## Overview

First in-game multiplayer: 2–4 browsers in a room see each other running in the
**same** world. No shared simulation — crocodiles, coins, weather and fauna stay
fully local per peer and ignore remote players entirely.

Four new client-side pieces plus one small terrain change:

1. **`scripts/lobby_client.gd`** — a `WebSocketPeer` wrapper over the lobby's
   `/ws` protocol (`server/conn.go` / `server/room.go`) plus an `HTTPRequest`
   fetch of `/ice` for the STUN/TURN config.
2. **`scripts/mp_manager.gd`** — owns the lobby client, the
   `WebRTCMultiplayerPeer` full mesh, seed distribution and presence
   send/receive. Node `Multiplayer` under `Main`, group `"mp"`.
3. **`scripts/remote_avatar.gd`** — a *visual-only* `Node3D` that renders one
   remote peer with the existing character scenes and the project's procedural
   limb animation.
4. **`scripts/mp_ui.gd`** — a code-built `Control` under `HUD`: host / join by
   invite code, share the code, member list, leave. Touch-friendly.
5. **`scripts/endless_terrain.gd`** — one new `set_run_seed(value)` entry point
   that `_roll_run_seed()` converges into, and `new_run(forced_seed = null)`.

**The whole feature is inert until a room is joined.** Solo play must be
byte-for-byte unchanged.

## Context (from discovery)

### The lobby wire protocol — as implemented in `server/`, verified by reading the code

Connect: `<LOBBY_URL>/ws?room=<CODE>&name=<label>`. Empty/unknown `room` creates
one. Codes are 6 chars from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no `0/O/1/I/L`),
upper-cased and trimmed server-side; anything else is refused with an `error`
frame and the socket closes. Room cap is 4 (`MaxMembers`); the 5th gets
`error` + close.

Server → client frames (all JSON objects with a `type`):

| type | fields |
|---|---|
| `welcome` | `you`, `room`, `master`, `members[]` (`{id,name}`), `heroes{}`, `pool[]` |
| `peer_join` | `peer{id,name}` |
| `peer_leave` | `id` |
| `master` | `id` |
| `heroes` | `heroes{hero:id}` |
| `signal` | `from`, `payload` (opaque, relayed verbatim) |
| `pong` | — |
| `error` | `error` |

Client → server: `{"type":"signal","to":"<peer id>|\"\"","payload":<anything>}`,
`{"type":"hero","hero":"..."}`, `{"type":"stalled","id":"..."}`,
`{"type":"ping"}`.

`GET /ice` returns `{"iceServers":[{"urls":[...]},{"urls":[...],"username":...,"credential":...}]}`
— **exactly the dictionary `WebRTCPeerConnection.initialize()` wants**, so it is
passed through with no reshaping. It sends CORS headers honouring
`LOBBY_ALLOWED_ORIGINS`.

Notes taken from the code that the client must respect:
- The `welcome` frame is **always the first frame** and already carries the
  master. Only *subsequent* master changes arrive as a `master` frame.
- `members[]` in `welcome` **includes yourself**.
- Peer ids are 16 lowercase hex chars (`newID()` = 8 random bytes).
- Read limit is 64 KB per frame — fine for SDP.
- The lobby **never inspects `payload`**; anything JSON-serialisable travels.
- `hero` / `stalled` are **phase 4/5 concerns — do not use them in this phase.**

### Godot-side facts established during discovery (do not re-litigate)

- **`WebRTCPeerConnection` has no implementation on desktop Godot 4.5.** Verified
  by running a headless probe: `WARNING: No default WebRTC extension configured.`
  It **is** built in on the **Web** export (browser-backed). Desktop therefore
  needs the official `webrtc-native` GDExtension addon — see Task 7. This is why
  the addon-presence probe and the honest error message exist.
- `main.tscn` already references several scripts by **path only, with no `uid=`
  attribute** (`coin_hud.gd`, `hit_flash.gd`, `perf_overlay.gd`, …). **New
  scripts must be referenced the same way** — no `uid=` attribute, and do not
  hand-write `.gd.uid` files. Godot generates those on import.
- `scripts/player_controller.gd` has **no `class_name`**. Reach its `CHARACTERS`
  const via `preload("res://scripts/player_controller.gd").CHARACTERS`.
- Character scenes (`windman_updated.tscn`, `primm.tscn`, `teibi.tscn`,
  `phoboman.tscn`) are **pure `Node3D` trees with no collision bodies** — they
  are already only ever instanced under the player's `$CharacterModel` `Node3D`.
  Instancing one under a bare `Node3D` therefore adds zero physics.
- The procedural-animation node-naming contract: `Body`, and under it
  `LeftArm` / `RightArm` / `LeftLeg` / `RightLeg`.
- `scripts/pause_controller.gd` holds the idiom for releasing and recapturing the
  mouse around an overlay (`_recapture_mouse`). Copy it for the MP panel.
- `scripts/touch_controls.gd` / `scripts/mobile_settings_panel.gd` hold the idiom
  for a code-built `Control` under the `HUD` `CanvasLayer`.
- `scripts/fauna_manager.gd` holds the isolation idiom: entities in **no group**,
  with **no collision**, parented to their **manager** (never to a terrain chunk,
  which would free them on chunk unload).
- Existing `new_run()` (line ~4437 of `endless_terrain.gd`) re-rolls the seed,
  clears the road station cache to its `road_k_min = 1 / road_k_max = 0`
  sentinel, clears `pending_chunks`, frees every chunk, and rebuilds ring 1
  synchronously around `(0,0)`. Only step 1 changes.

### Dependencies

- Phase 2 lobby (merged, in `server/`). Run locally with `cd server && go run .`
  → `http://localhost:8080`, websocket at `ws://localhost:8080/ws`.
- No new Godot addons are required **for the web build** (the shipping target).

## Development Approach

- **Testing approach**: NO unit tests. This project has no test suite, linter or
  build script (see CLAUDE.md "Commands"). The verification is:
  - `godot --headless --path . --import` — must complete with no script errors,
  - `godot --headless --path . scenes/main.tscn --quit-after 120` — must boot and
    exit clean with no errors,
  - **one** runnable self-check, `scripts/mp_selfcheck.gd` (Task 8), which is the
    single automatable guard on the isolation contract and the untrusted-packet
    parser. Do not grow it into a suite.
- Complete each task fully before moving to the next.
- **Match the project's comment density.** CLAUDE.md: "the codebase is written to
  be read — scripts are heavily commented for teaching purposes". Explicit type
  hints on every var, param and return. Constants for tunables at the top of each
  script.
- Mark deliberate simplifications with a `ponytail:` comment naming the ceiling
  and the upgrade path — the project already uses this convention.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Testing Strategy

- **Unit tests**: none.
- **Integration tests**: one — `scripts/mp_selfcheck.gd`, guarding the hard
  isolation contract (a remote avatar is in no group and carries no
  `CollisionObject3D`) and the untrusted-packet parser. That boundary is real:
  a regression there silently makes crocodiles chase a remote avatar, and no
  amount of manual play in a single browser would catch it.
- **E2E**: none. The project has no e2e suite; two-browser verification is manual
  and lives in Post-Completion.

## Progress Tracking

- Mark completed items with `[x]` immediately when done
- Add newly discovered tasks with ➕ prefix
- Document issues/blockers with ⚠️ prefix

## Implementation Steps

### Task 1: Forced-seed entry point in `endless_terrain.gd`

The bead: *"needs a 'set seed explicitly' entry point next to `_roll_run_seed()`
— keep it one function, both paths converge."*

- [x] add `func set_run_seed(value: int) -> void:` right beside `_roll_run_seed()`
      — it assigns `run_seed = value` and calls `_roll_biome_offset()`. Document
      that the biome offset is derived from `run_seed`, so **every** assignment of
      `run_seed` must route through here or the shader and the wade-zone disagree.
- [x] rewrite `_roll_run_seed()` to roll its throwaway `RandomNumberGenerator`
      exactly as today and then **call `set_run_seed(seed_rng.randi())`** — so the
      two paths converge on one function and cannot drift. Behaviour for solo play
      must be identical: same RNG, same `randomize()`, same `randi()`.
- [x] change `new_run()` to `func new_run(forced_seed = null) -> void:` — when
      `forced_seed == null` call `_roll_run_seed()` (today's behaviour, so every
      existing `new_run()` call site is untouched and byte-identical); otherwise
      call `set_run_seed(int(forced_seed))`. Leave steps 2–4 of `new_run` exactly
      as they are, including the `_apply_biome_shader_params()` call immediately
      after. Update the existing docstring's numbered step 1 to describe both paths.
      *(An untyped default is deliberate: `0` is a legitimate seed value, so a
      sentinel int would be wrong. Note this in a comment.)*
- [x] verify no other call site assigns `run_seed` directly:
      `grep -n 'run_seed *=' scripts/endless_terrain.gd` must show only the
      assignment inside `set_run_seed` and the `var run_seed: int = 0` declaration.

### Task 2: `scripts/lobby_client.gd` — websocket + `/ice`

A bare `Node`, `class_name LobbyClient`. Owns **only** the lobby socket; knows
nothing about WebRTC, the game, or the UI.

- [x] `_process`-driven `WebSocketPeer` lifecycle: `poll()` every frame, drain
      `get_available_packet_count()`, `JSON.parse_string` each text packet,
      dispatch on `type`. Handle `STATE_CLOSED` → emit `closed(code, reason)` and
      stop polling. Ignore unknown frame types (including `heroes` and `pong`) —
      forward compatibility with phases 4/5 costs one `_:` branch.
- [x] signals: `joined(you: String, room: String, master: String, members: Array)`,
      `peer_joined(id: String, name: String)`, `peer_left(id: String)`,
      `master_changed(id: String)`, `relay(from: String, payload: Dictionary)`,
      `lobby_error(message: String)`, `closed(code: int, reason: String)`.
- [x] `connect_to_room(code: String, display_name: String) -> void` builds
      `"%s/ws?room=%s&name=%s"` with `String.uri_encode()` on **both** query
      values and calls `WebSocketPeer.connect_to_url()`. An empty `code` is a
      create — send it as an empty parameter, exactly as the JS test page does.
- [x] `send_signal_to(to: String, payload: Dictionary) -> void` →
      `{"type":"signal","to":to,"payload":payload}`. `to == ""` broadcasts.
- [x] `disconnect_from_room() -> void` — close the socket, clear state, safe to
      call when never connected.
- [x] `fetch_ice(callback: Callable) -> void`: a child `HTTPRequest` GETs
      `<http(s) form of lobby_url>/ice`, parses `{"iceServers":[...]}` and hands
      the **whole dictionary through unchanged** to the callback — it is already
      the shape `WebRTCPeerConnection.initialize()` takes. On any failure
      (request error, non-200, unparseable body) fall back to
      `{"iceServers":[{"urls":["stun:stun.l.google.com:19302"]}]}` and log a
      warning: a STUN-only mesh still works on most networks, and failing the
      whole join because TURN is unreachable would be worse than degrading.
      Derive the HTTP URL by swapping the scheme (`wss:`→`https:`, `ws:`→`http:`).
- [x] **URL resolution** — a `static func resolve_lobby_url(override: String) -> String`
      with this precedence, documented in a comment:
      1. `--lobby=<url>` in `OS.get_cmdline_user_args()` (desktop dev: two editor
         instances against `ws://localhost:8080`),
      2. `?lobby=<url>` in `location.search`, read via `JavaScriptBridge` and
         gated behind `OS.has_feature("web")` (browser dev, and the escape hatch
         while the production hostname is unsettled),
      3. the `override` argument (the `@export var lobby_url` on `mp_manager`,
         when non-empty),
      4. `const DEFAULT_LOBBY_URL: String = "wss://lobby.example.com"`.
      Leave the default as that literal with a comment saying it is a
      **placeholder pending the phase-2 deployment hostname**, and that `?lobby=`
      overrides it without a rebuild. Do not invent a hostname.

### Task 3: `scripts/remote_avatar.gd` — the visual-only peer avatar

`extends Node3D`, `class_name RemoteAvatar`. **This file is where the hard
isolation contract lives — lead the docstring with it.**

- [x] header docstring stating the contract explicitly: this node joins **no
      group**, adds **no** `CollisionObject3D`/`Area3D`, and is parented to the
      MP manager (never to a terrain chunk). Name the systems that call
      `get_tree().get_first_node_in_group("player")` and must keep meaning the
      **local** player: terrain chunk streaming, `piglet_crocodile_ai.gd` chase,
      `crocodile_lod_manager.gd`, `danger_vignette.gd`, `fauna_manager.gd`,
      `weather_manager.gd`. Point at `fauna_manager.gd` as the precedent.
- [x] `setup(peer_name: String) -> void`: build a billboarded `Label3D` ~2.2 m up
      showing the peer's name (small, `no_depth_test = false`, `pixel_size` tuned
      so it is readable but not a banner). One `Label3D` — nothing else chrome.
- [x] `set_character(index: int) -> void`: free the current model and instance
      `preload("res://scripts/player_controller.gd").CHARACTERS[index]["scene_path"]`
      under a `$Model` `Node3D`; clamp/ignore an out-of-range index (untrusted
      input from the network). Cache the `Body`/`LeftArm`/`RightArm`/`LeftLeg`/
      `RightLeg` node references and their rest rotations, exactly as
      `player_controller.setup_animation_references()` does. Apply
      `ToonShading.apply_to_mesh` to the model's meshes so a remote avatar matches
      the local look (walk the subtree the way the crocodile `_ready` does).
      **ponytail:** models are instanced on demand rather than preloaded four-deep
      per peer — a character switch on a remote peer is rare; upgrade to the
      player's preload-all-and-toggle-visibility scheme if switching ever hitches.
- [x] `receive_state(pos: Vector3, yaw: float, char_index: int, speed: float, on_floor: bool) -> void`
      stores the target; a character index change calls `set_character`.
- [x] `_process(delta)`: move toward the target with
      `global_position = global_position.lerp(target_pos, 1.0 - exp(-INTERP_RATE * delta))`
      and `rotation.y = lerp_angle(rotation.y, target_yaw, ...)` — frame-rate
      independent smoothing, `INTERP_RATE` ≈ 12.0. Snap instead of lerping when
      the error exceeds `TELEPORT_DISTANCE` (10 m) so a respawn or a Phase Step
      does not produce a long glide across the field.
      **ponytail:** exponential smoothing toward the latest sample, not a
      timestamped interpolation buffer — at 15 Hz over a LAN/TURN hop it reads
      smooth; upgrade to a buffered-delay interpolator if it visibly rubber-bands.
- [x] walk animation: advance a phase by `speed * delta * STRIDE_FREQUENCY` and
      drive the limb rotations from sines off the cached rest pose, mirroring the
      player's walk cycle (arms and legs in diagonal opposition). Fade to the rest
      pose as `speed` approaches 0. Airborne (`on_floor == false`) uses a static
      tucked pose, as the player's jump pose does. **Constants local to this file**
      — three numbers duplicated from `player_controller` is cheaper than coupling
      the two scripts; note that in a comment.

### Task 4: `scripts/mp_manager.gd` — mesh, seed, presence

`extends Node`. Node `Multiplayer` under `Main`, group `"mp"`. **Every code path
is inert until `host()`/`join()` is called**, and `_process` early-returns while
`_state == State.OFFLINE` — mirror `mobile_input.gd`'s "idle unless active" rule.

- [x] `@export var lobby_url: String = ""` (empty = use `LobbyClient.resolve_lobby_url`
      precedence) and `@export var display_name: String = ""` (empty = "player").
- [x] `host() -> void` / `join(code: String) -> void` / `leave() -> void`, plus
      signals `room_changed(code: String, members: Array)` and
      `status(message: String)` for the UI. `host()` is `join("")`.
- [x] **WebRTC availability probe**, run before anything else on `host()`/`join()`:
      available when `OS.has_feature("web")`, else when
      `FileAccess.file_exists("res://addons/webrtc/webrtc.gdextension")`.
      Unavailable → emit `status("Multiplayer needs the WebRTC addon on desktop — see README")`
      and stay `OFFLINE`. **ponytail:** a file probe, because Godot exposes no API
      to ask whether a default WebRTC extension is registered; upgrade if one ever
      lands.
- [x] **Peer-id mapping.** `WebRTCMultiplayerPeer` needs `int` ids; the lobby
      gives 16-hex-char strings. Map with a `static func peer_int_id(lobby_id: String) -> int`
      returning `("0x" + lobby_id.substr(0, 7)).hex_to_int() + 2` — 28 bits, always
      ≥ 2 so it can never collide with the MultiplayerPeer-reserved 0 and 1. Every
      peer derives every other peer's int id the same way, so the mesh agrees with
      no extra protocol. **ponytail:** birthday collision across 4 peers is ~2e-7;
      upgrade path is master-assigned ids over the relay if it ever matters.
- [x] **Mesh setup.** On `welcome`: fetch `/ice`, then
      `WebRTCMultiplayerPeer.new()` + `create_mesh(peer_int_id(you))`. For each
      already-present member other than yourself, and for each later `peer_join`,
      create a `WebRTCPeerConnection`, `initialize(ice_config)`, connect its
      `session_description_created` and `ice_candidate_created` signals, and
      `rtc.add_peer(conn, peer_int_id(their_id))`.
      **`_rtc` must NEVER be assigned to `multiplayer.multiplayer_peer`.** It is
      used as a plain `PacketPeer`: `poll()` it in `_process`, `put_packet()` to
      send, `get_packet()`/`get_packet_peer()` to receive. Say why in a comment:
      leaving the global `MultiplayerAPI` untouched is what keeps solo play
      byte-for-byte unchanged and keeps RPC/replication out of the picture — this
      phase has no shared simulation to replicate.
- [x] **Glare-free offer rule**: the peer whose **lobby id string sorts lower**
      creates the offer (`conn.create_offer()`); the other waits. Deterministic on
      both sides from data both already have, so no negotiation round-trip.
      Comment it.
- [x] **Signalling payloads** over the lobby relay, always addressed `to` the
      specific peer:
      - `{"mp":"offer","sdp":<String>}`
      - `{"mp":"answer","sdp":<String>}`
      - `{"mp":"ice","media":<String>,"index":<int>,"name":<String>}`
      On receipt: `set_remote_description(type, sdp)` for offer/answer (answering
      an offer with `create_answer()` from the `session_description_created`
      callback, which fires with `type == "answer"`), `add_ice_candidate(...)` for
      ice. **Every field is validated before use** — a frame missing a key, or
      carrying the wrong type, is dropped with a warning, never trusted. Ignore
      any relay payload without an `"mp"` key (forward compatibility with later
      phases sharing the same relay).
- [x] **Seed distribution over the lobby relay, not the mesh** — it must work
      before any data channel is open:
      - keep `_room_seed: int`;
      - if `welcome.master == welcome.you`, I am master: read the terrain's
        current `run_seed` (group `"terrain"`, `has_method` guarded), store it and
        broadcast `{"mp":"seed","seed":<int>}` to everyone. Re-send it directly to
        each later `peer_join`.
      - otherwise: on receiving `{"mp":"seed",...}` for the first time, call
        `terrain.new_run(int(payload["seed"]))` then the local player's
        `reset_position()` (group `"player"`, `has_method` guarded) so the joiner
        starts at spawn in the shared world.
      - **JSON number gotcha, comment it:** `JSON.parse_string` yields floats.
        `run_seed` comes from `RandomNumberGenerator.randi()` (0…2³²−1), which is
        exactly representable in a double, so `int(payload["seed"])` round-trips
        exactly — but the `int()` cast is mandatory, not cosmetic.
      - on `master_changed`, the new master keeps `_room_seed` and re-broadcasts
        it; it does **not** re-roll. (Phase 4 owns real mid-run state replay.)
- [x] **Presence send** on a `PRESENCE_HZ = 15.0` accumulator (not every frame).
      Read the local player via the `"player"` group; build
      `{"p": Vector3, "y": float, "c": int, "s": float, "g": bool}` (position,
      body yaw, character index, horizontal speed, on-floor), then
      `_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)`,
      `set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)`,
      `put_packet(var_to_bytes(state))`. Skip the send entirely when no peer is
      connected.
- [x] **Presence receive** — the trust boundary, so validate hard:
      drain packets in `_process`; for each, `get_packet_peer()` gives the sender's
      int id → look up its `RemoteAvatar`. Decode with **`bytes_to_var`, never
      `bytes_to_var_with_objects`** (which would let a peer instantiate objects in
      our process) — state that reason in a comment. Then check
      `typeof(v) == TYPE_DICTIONARY` and each field's type
      (`p` `TYPE_VECTOR3`, `y`/`s` numeric, `c` numeric, `g` `TYPE_BOOL`) before
      use; reject the packet otherwise. Clamp `c` into `CHARACTERS` range and
      guard `p` against non-finite components (`is_finite`).
- [x] **Avatar lifecycle**: create a `RemoteAvatar` on `peer_join` (and for every
      member already in `welcome`), `add_child` it **to this manager**, and
      `queue_free` it on `peer_left`. `leave()` frees every avatar, closes every
      `WebRTCPeerConnection`, drops `_rtc`, disconnects the lobby and returns to
      `OFFLINE` — leaving no trace, so solo play resumes exactly as before.
- [x] `get_room_code()`, `get_members()`, `is_online()` for the UI; `_process`
      early-return while `OFFLINE`.

### Task 5: `scripts/mp_ui.gd` — host / join panel

A code-built `Control` under `HUD`, in the style of `mobile_settings_panel.gd`.

- [x] a small **"MP"** button in a corner that does not collide with the existing
      HUD furniture (lives top-left, coins/ability top-right, tune gear top-left
      under lives, view/steer toggles top-centre) — put it **bottom-left**. Opens
      and closes the panel.
- [x] panel contents: a status line, a **Host** button, a `LineEdit` for the
      invite code + a **Join** button, the room code shown large with a **Copy**
      button once in a room (`DisplayServer.clipboard_set`), a member list, and a
      **Leave** button. Uppercase the typed code and set `max_length = 6` on the
      `LineEdit` so a typo is rejected client-side before the lobby has to.
- [x] wire to the manager through the **`"mp"` group only** (`get_first_node_in_group`
      + `has_method` guards) — the same no-hard-references rule the rest of the
      project uses; subscribe to its `room_changed` / `status` signals.
- [x] **mouse handling**: opening the panel releases a captured mouse and closing
      recaptures it, copying `pause_controller.gd`'s `_recapture_mouse` flag so it
      never fights the pause overlay or the touch path. Do **not** pause the tree —
      the world keeps running while the panel is open.
- [x] touch-friendly: minimum ~48 px touch targets, and the panel must be usable
      with the on-screen keyboard (`LineEdit` handles the virtual keyboard).
      Unlike `touch_controls`, this UI is **visible on every platform** — desktop
      needs it too (acceptance criterion 4) — so it is **not** gated on
      `DisplayServer.is_touchscreen_available()`.

### Task 6: Wire into `main.tscn`

- [x] add `[node name="Multiplayer" type="Node" parent="." groups=["mp"]]` with
      `scripts/mp_manager.gd`, and `[node name="MultiplayerUI" type="Control" parent="HUD"]`
      with `scripts/mp_ui.gd` (full-rect anchors, `mouse_filter` set so the panel
      does not eat gameplay clicks while closed).
- [x] add both `[ext_resource type="Script" path="res://scripts/..." id="..."]`
      lines **without a `uid=` attribute**, matching the existing path-only
      entries, and bump `load_steps` in the `[gd_scene]` header accordingly.
- [x] `godot --headless --path . --import` must complete with no errors, then
      `godot --headless --path . scenes/main.tscn --quit-after 120` must boot and
      exit clean. Both are required before this task is marked done.

### Task 7: Desktop WebRTC addon path (dev iteration)

The web build needs nothing. Desktop has no WebRTC implementation, so
two-editor-instance testing needs the official `webrtc-native` GDExtension.
**Do not commit binaries.**

- [x] add `addons/` to `.gitignore` (if not already ignored) with a comment saying
      the WebRTC addon is fetched, not vendored.
- [x] add `server/../docs` — no: document it in **`README.md`** under a short
      "Multiplayer (dev setup)" heading: download the `webrtc-native` release for
      Godot 4.x from `https://github.com/godotengine/webrtc-native/releases`,
      unzip into `addons/`, restart the editor. Note that the **web export needs
      none of this**.
- [x] document the two dev-iteration recipes in the same section: run the lobby
      with `cd server && go run .`, then launch two instances with
      `godot --path . scenes/main.tscn -- --lobby=ws://localhost:8080`, or open the
      web build twice with `?lobby=ws://localhost:8080`.

### Task 8: `scripts/mp_selfcheck.gd` — the one runnable check

`extends SceneTree`, run with
`godot --headless --path . --script res://scripts/mp_selfcheck.gd`. Prints
`SELFCHECK OK` and quits 0, or prints the failure and quits 1. Plain `assert`-free
explicit checks (asserts are stripped in release builds).

- [x] **isolation contract** (the reason this file exists): build a `RemoteAvatar`,
      `set_character(0)`, then assert its `get_groups()` is empty, every node in
      its subtree has empty groups, and **no node in the subtree is a
      `CollisionObject3D`**. This is the guard that a future refactor cannot
      silently make crocodiles chase a remote avatar.
- [x] **untrusted packet parser**: the presence decoder accepts a well-formed
      packet and rejects, without crashing, each of: random bytes, a
      `var_to_bytes` of a non-dictionary, a dictionary missing `p`, a dictionary
      with `p` as a String, and a `c` far out of range.
- [x] **forced seed**: instance `endless_terrain.gd`, call `set_run_seed(12345)`
      twice and assert `run_seed == 12345` and that `biome_offset` is identical
      both times (the seed→biome derivation is deterministic).
- [x] **peer id mapping**: `peer_int_id` is ≥ 2, stable across calls, and
      distinct for a handful of sample 16-hex-char ids.
- [x] run it and make it pass.

### Task 9: Verify acceptance criteria

- [x] **solo unchanged**: `grep` every new group name and confirm no new node
      joins `"player"`; confirm `mp_manager._process` early-returns while offline;
      confirm `multiplayer.multiplayer_peer` is never assigned anywhere
      (`grep -rn 'multiplayer_peer' scripts/` must show no assignment);
      confirm `new_run()` with no argument follows exactly the old path.
- [x] `godot --headless --path . --import` clean.
- [x] `godot --headless --path . scenes/main.tscn --quit-after 120` clean.
- [x] `scripts/mp_selfcheck.gd` passes.
- [x] `cd server && go build ./... && go test ./...` still passes (the lobby is
      untouched, but the PR must not break it).

### Task 10: [Final] Update documentation

- [x] add a **"Multiplayer (phase 3): WebRTC mesh + presence"** section to
      `CLAUDE.md`, matching the density and voice of its neighbours. It must
      record, at minimum: the hard isolation contract and why (naming the
      `get_first_node_in_group("player")` callers); that `_rtc` is deliberately
      never installed as `multiplayer.multiplayer_peer`; the peer-id derivation
      and its collision ceiling; the lexicographic offer rule; that the seed
      travels over the **lobby relay** rather than the mesh, and why; the
      `bytes_to_var`-not-`_with_objects` rule; the lobby-URL precedence; and that
      desktop needs the webrtc-native addon while web does not.
- [x] update the `CLAUDE.md` "Node discovery is group-based" section to list the
      new `"mp"` group, and note that `"player"` still means **only** the local
      player.
- [x] add the dev-setup section to `README.md` — already delivered in Task 7
      (`README.md` "Multiplayer (dev setup)": addon download, `go run .` lobby,
      the two `--lobby=` / `?lobby=` recipes); verified present, no edit needed.

## Technical Details

### Presence packet

`var_to_bytes({"p": Vector3, "y": float, "c": int, "s": float, "g": bool})` —
~60 bytes, sent unreliable, broadcast, 15 Hz. At 4 peers that is 3 × 15 × 60 ≈
2.7 KB/s outbound per peer. No compression, no delta encoding, no baseline —
**ponytail:** the upgrade path if it ever matters is quantising position to
16-bit fixed point, but at this size the packet is smaller than its own UDP
header overhead.

### State machine (`mp_manager`)

`OFFLINE → CONNECTING (websocket) → IN_ROOM (welcome received, mesh negotiating)`.
`leave()` returns to `OFFLINE` from any state and is idempotent. Any lobby error
or socket close returns to `OFFLINE` with a status message — never a crash, never
a half-torn-down mesh.

### What is deliberately NOT built (per the bead's "not in scope")

Shared crocodiles; shared coins (each peer collects its own — a known temporary
duplication); mid-run join state replay (joiners restart at spawn in the shared
world); hero-split enforcement (the lobby's `hero` message is left unused);
master migration and stall detection (the lobby's `stalled` message is left
unused). Do not implement any of these.

## Post-Completion

*No checkboxes — manual and external.*

**Manual verification** (needs two browsers and a reachable lobby):
- Two tabs, same room: identical terrain, coin road, artifacts and biome bands;
  each tab sees the other's avatar moving smoothly.
- Crocodiles chase only the local player; the remote avatar collects no coins,
  triggers no danger vignette, and is not counted by the LOD overlay (F3
  `Crocs (active/total)` unaffected).
- Character switch (E) on one tab swaps the model shown in the other.
- One tab leaves → its avatar disappears in the other; master re-election is
  visible in the lobby's own test page at `/`.
- Phone (touch) can host and join through the on-screen panel.

**External**:
- The **production lobby hostname is not yet settled**; the client ships with a
  placeholder default plus `?lobby=` / `--lobby=` overrides. Set the real
  `wss://` URL in `DEFAULT_LOBBY_URL` once the phase-2 deployment lands.
- Once the game's origin is known, narrow the lobby's `LOBBY_ALLOWED_ORIGINS`
  from `*` to the GitHub Pages host — the `/ice` body is the TURN credentials.
- Desktop developers must fetch the `webrtc-native` addon once (README).
