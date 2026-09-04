extends Node
class_name MpManager
## Multiplayer manager — the whole client side of "2–4 browsers in a shared-seed
## world". Node `Multiplayer` under `Main` in `main.tscn`, group `"mp"`.
##
## It owns four things and nothing else:
##
##   1. the lobby socket (`scripts/lobby_client.gd`) — signalling and membership,
##   2. a `WebRTCMultiplayerPeer` **full mesh** between every member,
##   3. **seed distribution**, so every peer's `endless_terrain` generates the
##      same world (the whole point: shared terrain with zero shared simulation),
##   4. **presence** — a 15 Hz position/pose packet per peer, rendered by the
##      visual-only `RemoteAvatar` nodes it parents (see `scripts/remote_avatar.gd`
##      for the isolation contract those avatars must honour).
##
## ----------------------------------------------------------------------------
## INERT UNTIL A ROOM IS JOINED — the rule that keeps solo play unchanged
## ----------------------------------------------------------------------------
## Nothing here runs until `host()` or `join()` is called: `_process` early-returns
## while `_state == State.OFFLINE`, no socket is opened, no avatar exists, and no
## other system is touched. This mirrors `scripts/mobile_input.gd`'s
## "idle unless active" rule, for the same reason — a feature that costs a frame
## of work when unused is a feature that regresses single player.
##
## `leave()` unwinds all of it and is idempotent, so a dropped socket, a lobby
## error and a player pressing "Leave" all land in exactly the same place.
##
## ----------------------------------------------------------------------------
## THE CODEC IS `scripts/mp_codec.gd` — every parser this file used to carry
## ----------------------------------------------------------------------------
## `decode_presence` / `decode_state` / `decode_croc_sync` / `decode_captive` /
## `decode_room` / `decode_pad` / `decode_lmk` / `decode_herd`, `packet_kind`, the `_croc_flags`
## byte packing, the two `*_in_reach` proximity tests, `peer_int_id` and the
## wire-format bounds all of them are written against now live in `MpCodec`
## (bead godot-test1-ftn.11 — a mechanical, behaviour-preserving move). They
## were already `static` and `_rtc`-free so the self-checks could beat on them
## with hostile packets; the split is that shape made into a file boundary.
##
## The rule for a new verb: its PARSER is a static in `mp_codec.gd` next to its
## siblings, with its trust-boundary bound; its HANDLER — authority, rate limit,
## and what it does to the room — stays here, where the state is.
##
## ----------------------------------------------------------------------------
## WHAT IS DELIBERATELY NOT HERE (phase 3 scope)
## ----------------------------------------------------------------------------
## No shared crocodiles, no shared coins (each peer collects its own), no mid-run
## state replay (a joiner restarts at spawn in the shared world) and no stall
## detection — the lobby's `stalled` message is left unused on purpose.
## Crocodiles, coins, weather and fauna stay fully local per peer and ignore
## remote players entirely. The hero split IS implemented: see the HERO POOL
## section, where the lobby is the source of truth.

# =============================================================================
# CONFIGURATION
# =============================================================================

## How often presence packets go out, in hertz. Deliberately NOT per-frame: at
## 60 fps that would be 4× the traffic for motion the smoothing in
## `RemoteAvatar` already reconstructs. ~60 bytes × 15 Hz × 3 peers ≈ 2.7 KB/s
## outbound, which is smaller than the UDP headers carrying it.
const PRESENCE_HZ: float = 15.0

## Presence packets read per peer per frame before the rest of the backlog is
## dropped. Sized a few times over PRESENCE_HZ / physics rate so an honest peer's
## burst after a hitch still drains, while a flood cannot.
const MAX_PRESENCE_PACKETS_PER_PEER: int = 8

## Hard ceiling on packets DEQUEUED per frame, across every sender. Sized well
## above MAX_PRESENCE_PACKETS_PER_PEER × MAX_MEMBERS so an honest room never
## reaches it: it exists only so that discarding one peer's over-quota flood
## (which costs a `get_packet` each) still terminates the loop.
const MAX_DRAIN_PACKETS_PER_FRAME: int = 256

## Fallback display name when none was configured. The lobby clamps names to 32
## characters server-side, so we do not need to.
const DEFAULT_DISPLAY_NAME: String = "player"

## How many relayed signals we will hold for a peer whose connection does not
## exist yet (see `_buffer_signal`). One offer plus its ICE candidates is a
## handful; this is the trust-boundary cap, not a capacity estimate.
const MAX_BUFFERED_SIGNALS: int = 64

## The world seed's accepted range — `endless_terrain._roll_run_seed()` takes it
## from `RandomNumberGenerator.randi()`, so 0…2³²−1 is every seed that can
## honestly appear. It arrives over the relay as a JSON double, and a master is
## only the oldest member of a room whose code is public over `/rooms`, so this
## is peer input like any other: `1e999` parses to `INF`, and `int(INF)` is the
## undefined cast `MAX_STATE_ID_MAGNITUDE` exists to keep out (on wasm the
## float→int trunc can trap the module outright).
const MAX_RUN_SEED: float = 4294967295.0

## How often the room master broadcasts crocodile sync packets, in hertz.
## Deliberately slower than PRESENCE_HZ: a crocodile is a background actor the
## receiver eases toward (see `piglet_crocodile_ai._tick_remote`), while the
## player avatar is what the eye tracks. 10 Hz is the cheapest rate at which the
## easing still reads as motion rather than as stepping.
const CROC_SYNC_HZ: float = 10.0

## Radius (metres) around EACH TARGET PEER whose crocodiles that peer is sent.
##
## THE RELATIONSHIP THAT MUST HOLD — and it is the same kind of invariant as the
## LOD manager's `SIM_RADIUS ≫ DETECTION_RADIUS`: this must EXCEED the LOD
## manager's sleep radius, `SIM_RADIUS + HYSTERESIS_MARGIN` = 50 m. A crocodile
## between the two would be awake for that peer (so its local AI is running) yet
## outside its sync window (so no sample ever arrives), and the two simulations
## would silently disagree about a crocodile close enough to bite. 55 > 50 leaves
## 5 m of slack; retune this if either LOD constant moves.
const CROC_SYNC_RADIUS: float = 55.0

## How long a crocodile keeps following the master's samples after the last one
## arrived, in seconds, before it is handed back to its own local AI.
##
## This is what makes the master's COVERAGE CEILING degrade gracefully (a peer
## further than the master's render distance gets no samples for its neighbours,
## so they simply resume local simulation — today's behaviour, for peers who
## cannot see each other anyway) AND what makes migration seamless: a lobby
## re-election takes ~1 s, well inside this window, so crocodiles never visibly
## stall during a handover.
const CROC_SYNC_TIMEOUT: float = 2.0

## PICKUP CLAIMS. An unconfirmed claim is re-sent every CLAIM_RETRY_SEC, at most
## CLAIM_MAX_TRIES times; 0.5 s × 4 is 2 s, comfortably over a relay-free mesh
## round trip and short enough that a player never notices a coin "thinking".
const CLAIM_RETRY_SEC: float = 0.5
const CLAIM_MAX_TRIES: int = 4

## Trust-boundary bounds on a claim (see `_receive_claim`). `n` drives a LOOP on
## the master, so it is the one field a hostile peer could turn into a frame
## stall — the largest honest claim in the game is a treasure chest's
## CHEST_COINS_MAX (15) pickups, so 64 is generous. `v` is the base value per
## pickup: 1 for a coin, `Coin.GEM_VALUE` (10) for a gem.
const MAX_CLAIM_PICKUPS: int = 64
const MAX_CLAIM_VALUE: int = 1000

## Trust-boundary bound on a relayed Stink Wave (see `_receive_flee`). A flee
## duration is peer input and it is applied to the WHOLE pack, so an unbounded one
## would leave every crocodile in the room fleeing — and a fleeing crocodile is
## harmless — for the room's life: a one-packet griefing button. Phoboman's own
## PHOBOMAN_FLEE_DURATION is 10 s, so this is six times the honest value.
const MAX_FLEE_DURATION: float = 60.0

## Trust-boundary bound on the RATE of the three state-mutating verbs, per peer
## per second. Bounding their fields is not enough: the drain budget passes up to
## MAX_PRESENCE_PACKETS_PER_PEER × peers (24) packets per FRAME, and each of these
## verbs is expensive out of all proportion to its 20-odd bytes —
##
##   flee  walks the whole "crocodile" group (~1000 nodes) calling flee_from on
##         every one. At the drain rate that is ~1.4 M calls/s: a hard frame stall
##         on the gl_compatibility web build, and MAX_FLEE_DURATION does nothing
##         about it because re-sending every frame keeps the pack harmless just as
##         effectively as one long duration would.
##   kill  writes an unbounded `_dead_crocs` entry, and on the common id-names-no-
##         local-croc path triggers a full group rescan — on the master AND, via
##         the `dead` broadcast it provokes, on every other peer. ~4× amplified.
##   clm   writes an unbounded `_collected_ids` entry (the set replayed to every
##         future joiner), broadcasts a reliable confirm to the room, and makes
##         every peer sweep the whole "coin" group in `_absorb_collected`.
##
## Room codes are public over `/rooms`, so "a peer in the room" means "anyone" —
## the same premise `_receive_mesh_packets`' bounded drain is written against. The
## budgets are far above honest play: Phoboman's ability cools down for seconds, a
## crush needs a body under your feet (and `piglet_crocodile_ai` latches its
## request), and a running player crosses a coin every few hundred ms.
##
## ponytail: a whole-second window rather than a token bucket, so a peer can spend
## its budget in one frame and then wait. Fine here — the point is the sustained
## rate, and a dropped claim is re-driven by `_tick_claims` 0.5 s later.
##
## THE MASTER-ONLY VERBS ARE METERED TOO, and the authority check is not a
## substitute. "Master" is just the oldest member — and anyone may HOST a room,
## which is then listed publicly over `/rooms` — so a hostile master is an
## ordinary peer with a title, not a trusted party. Unmetered, each of its three
## verbs is the same amplifier the budgets above exist to close, at the bounded
## drain's ~1440 packets/s: `dead` writes an unbounded `_dead_crocs` entry and
## rescans the ~1000-node "crocodile" group, `cnf` writes an unbounded
## `_collected_ids` entry and sweeps the whole "coin" group, `croc` carries up to
## MAX_CROC_SYNC entries and rescans the group on a miss. The ceilings below sit
## far above honest play: `croc` is sent at CROC_SYNC_HZ (10), and `cnf`/`dead`
## are each bounded by the `clm`/`kill` budgets of the up-to-three peers the
## master answers.
##   cap   writes the room's captive set, which decides who may still be played
##         and - once it is full - ends the run for everybody. Bounded at 8/s
##         because an honest capture needs a hunter's whole telegraph-shadow-close
##         beat first, which is seconds; the SET is bounded independently by the
##         one-captive-per-peer rule in `_receive_captive`, so this budget is only
##         about the cost of the packet, not about the damage a flood could do.
##   room  is the MASTER'S PERIODIC TRUTH about the captive set. Master-only and applied wholesale, so it is the `dead` class of
##         verb: budgeted a few times its own ROOM_SYNC_HZ so a burst after a hitch
##         still drains while a flood cannot.
##   pad   is one press of an HQ lure plate (bead godot-test1-3iy.22). Budgeted
##         like `flee` and for the same reason: it is a rare deliberate act with a
##         20 s cooldown on the plate itself, so anything above a trickle is a peer
##         that is not playing. It costs the master one `investigate_point()` call
##         that a busy guard refuses outright.
##   lmk   is one Budapest landmark claim (bead godot-test1-8gw.5). There are 22
##         of them in a run and each is claimed once, so a trickle is the honest
##         traffic; budgeted like `kill` so a burst after a hitch still drains
##         while a flood cannot. Master-only, and it costs the master one range
##         test plus one proximity test against its own presence table.
##   herd  is the master's migrating herd (bead godot-test1-6xc), sent on the same
##         tick as `croc` and budgeted at the same 40: it is one packet per tick,
##         not one per crocodile, and a peer over that ceiling is not playing. It
##         is master-only and costs the receiver a dictionary of eight validated
##         fields plus — for a herd it has not seen before — one seeded build of at
##         most ten animals, which the one-herd invariant bounds absolutely.
const VERB_BUDGET_PER_SEC: Dictionary = {
	"clm": 30, "kill": 10, "flee": 4, "croc": 40, "cnf": 150, "dead": 60,
	"cap": 8, "room": 12, "pad": 4, "lmk": 10, "herd": 40,
}

## How often the master publishes the room's captive set, in hertz.
##
## SLOW ON PURPOSE. It is a repair channel, not motion: the live
## `cap` verb carries every change the instant it happens, and this exists for the
## windows that verb cannot reach (a peer whose mesh was still negotiating). Twice a
## second costs a handful of bytes.
const ROOM_SYNC_HZ: float = 2.0

## The player script, preloaded ONLY to read constants it owns: the coin-economy
## ones (STREAK_WINDOW / STREAK_COINS_PER_STEP / STREAK_MAX_BONUS) and the
## CHARACTERS list. The room's streak has to step on exactly the same schedule as
## a solo one or the `(xN)` the HUD shows would mean something different in a
## room; re-typing the numbers here is precisely how that drifts. ONE name for
## this resource in this file, please — reaching it a second way (through
## `RemoteAvatar.PLAYER_SCRIPT`, which is the same preload) just makes a reader
## check whether the two are the same thing.
const PLAYER_SCRIPT := preload("res://scripts/player_controller.gd")

## How far the group may be spread before its centroid stops being a sensible
## place to arrive. Tuned BY EYE, not derived: 60 m is a bit over one chunk, well
## inside the fog, so a joiner landing at the centroid of a group this tight can
## still see somebody. Past it the centroid is empty ground between two players
## who have gone their separate ways, so the master's own position is used
## instead — arriving beside one player beats arriving beside none.
const GROUP_SPREAD_MAX: float = 60.0

## PEER COLOUR — how many distinct hues `peer_color()` can hand out, and the
## saturation/value it paints them at. One hue per degree is finer than any eye
## needs; what matters is that the mapping is a pure function of the peer id, so
## every surface that draws a teammate (the minimap dots, the locator strip, and
## anything added later) agrees on the colour with no shared state and no lookup
## table to keep in step. Saturation stays under 1 so the colours read on a light
## sky, value stays at 1 so they read on the minimap's dark disc.
const PEER_HUE_STEPS: int = 360
const PEER_COLOR_SATURATION: float = 0.75
const PEER_COLOR_VALUE: float = 1.0

## The lobby errors that must NOT end the session. `server/room.go` answers a
## refused hero claim with a plain `error` frame on a socket it deliberately
## keeps OPEN (`errUnknownHero` / `errHeroTaken`), and two peers reaching for the
## same hero at the same moment is an ordinary event — the blanket `leave()`
## every other error takes would drop BOTH of them out of a perfectly good room.
## Matched by exact string, because the string is all the frame carries.
const HERO_ERRORS: PackedStringArray = ["unknown hero", "hero already taken"]

## SEED SELF-HEAL. A joiner with no seed asks the master for one every
## `SEED_REQUEST_INTERVAL` seconds, `SEED_REQUEST_MAX_TRIES` times, then gives up
## asking (but stays in the room). 2 s is well over a relay round trip on any
## connection worth playing on, and 10 tries is 20 s — long enough to cover a
## master still booting its terrain, short enough that a dead host is reported
## while the player is still looking at the panel.
const SEED_REQUEST_INTERVAL: float = 2.0
const SEED_REQUEST_MAX_TRIES: int = 10

## STALL DETECTION. The master says "still here" every `HEARTBEAT_INTERVAL`
## seconds; a peer that has heard nothing for `HEARTBEAT_TIMEOUT` votes to depose
## it, at most once per `STALL_REPORT_INTERVAL`. 1 s / 4 s means three consecutive
## missed beats are needed to fire — well past any ordinary relay hiccup — and the
## first vote goes out `STALL_REPORT_INTERVAL` after that, so a genuinely dead
## host is reported within about six seconds. The report interval is slower than
## the beat so a room that is merely slow to re-elect does not spray votes the
## lobby has already counted.
const HEARTBEAT_INTERVAL: float = 1.0
const HEARTBEAT_TIMEOUT: float = 4.0
const STALL_REPORT_INTERVAL: float = 2.0

## How long a joiner waits for EVERY incumbent's join snapshot before placing
## itself with whatever arrived.
##
## The anchor is the centroid of the group (or the master's position when the
## group is spread), so it is only the documented anchor once all the snapshots
## are in — place on the first one and a three-player room drops the joiner beside
## whichever peer's relay message happened to win the race. The snapshots are one
## small message each, sent the instant the lobby announces the join, so in
## practice they land together and this deadline never fires. It exists because
## the alternative is waiting forever on a peer that is wedged, on an older build,
## or gone: falling back to a worse anchor beats never placing the player at all.
const JOIN_SNAPSHOT_WAIT: float = 1.5

## HOW LONG AFTER `welcome` A RELAY PACKET MAY STILL MOVE THE LOCAL PLAYER.
##
## The placement is owed to the ARRIVAL, not to the data, and this is the whole
## difference. `_can_join_place()` is otherwise a pure state test — "we still owe
## a placement, and both inputs are now in hand" — and `JOIN_SNAPSHOT_WAIT` does
## not disarm it: that deadline only stops the WAITING (`_tick_join_wait` returns
## early once it is spent), it never says "too late". So whichever of the two
## inputs is last to land fires the teleport, however many seconds of play later
## that is — and either one can be arbitrarily late: a backgrounded browser tab
## stops polling its socket, `seed_req` retries for `SEED_REQUEST_INTERVAL` ×
## `SEED_REQUEST_MAX_TRIES` (20 s), and a master migration hands that whole budget
## back (`_on_lobby_master_changed`). Measured before this window existed: a peer
## that arrived, waited out the deadline with a silent master, then walked 400 m
## was teleported to the world origin by the late `seed` (via `reset_position()`,
## which also wipes its coins, distance and streak) and then onto the group's ring
## by the late `state` — 397 m of drag, twice, while alive and playing.
##
## The healthy case is nowhere near this bound: every incumbent sends the seed and
## its snapshot from the SAME handler that observes our arrival
## (`_on_lobby_peer_joined`), so both land in one relay round trip — tens of ms.
## Five seconds is ~100× that, so the only joins this window ever refuses are the
## ones where the player has genuinely been playing.
##
## ponytail: a wall clock, so it cannot tell "playing for 5 s" from "tab
## backgrounded for 5 s during the arrival" — the latter loses its placement and
## plays on where it stands (and, having never run `join_at()`, stays a
## non-contributor to the room's totals, exactly as a peer whose seed never
## arrived at all already did). That is the safe direction to be wrong in: the
## upgrade path is the player publishing a "has taken control" bit for this to
## read instead of a clock, which needs a `player_controller.gd` change.
const JOIN_PLACE_WINDOW: float = 5.0

## Where the desktop WebRTC GDExtension lives when a developer has installed it.
## See README — the browser build needs nothing, desktop needs this addon.
const WEBRTC_ADDON_PATH: String = "res://addons/webrtc/webrtc.gdextension"

## Connection lifecycle. CONNECTING covers "socket opening"; IN_ROOM starts the
## moment the `welcome` frame lands, while the mesh is still negotiating — peers
## appear in the member list before their data channels open, which is what the
## UI wants to show.
enum State { OFFLINE, CONNECTING, IN_ROOM }

# =============================================================================
# EXPORTS
# =============================================================================

## Lobby base URL override. Empty (the default) means "use
## `LobbyClient.resolve_lobby_url()`'s precedence" — command line, then `?lobby=`
## query string, then this export, then the placeholder default.
@export var lobby_url: String = ""

## Name shown on this peer's avatar to everyone else. Empty = DEFAULT_DISPLAY_NAME.
@export var display_name: String = ""

## Send the master's heartbeat. TRUE in every real session — turning it off is
## how a headless test (and a developer) SIMULATES A THROTTLED TAB: the socket
## stays open and the room stays intact, but the beats stop, which is exactly
## what a backgrounded browser tab looks like from the other peers' side. Nothing
## in the UI exposes this; `scripts/mp_e2e.gd`'s `--stall` flag is its one caller.
@export var heartbeat_enabled: bool = true

# =============================================================================
# SIGNALS (for scripts/mp_ui.gd — nothing else listens)
# =============================================================================

## The room, or its membership, changed. `members` is the lobby's
## `[{"id": String, "name": String}, ...]`, including ourselves.
signal room_changed(code: String, members: Array)

## Human-readable one-liner for the UI's status line. Every failure path emits
## one of these rather than crashing or leaving a half-torn-down mesh.
signal status(message: String)

## The room's hero assignments changed: `heroes` maps hero name → holder peer id,
## `pool` is every hero the lobby offers. A straight re-emit of `LobbyClient`'s
## signal of the same name, so the UI only ever talks to the manager — the same
## shape, and the same reason, as `room_changed`.
signal heroes_changed(heroes: Dictionary, pool: Array)

# =============================================================================
# STATE
# =============================================================================

var _state: State = State.OFFLINE

## The lobby socket, created on the first join and reused afterwards.
var _lobby: LobbyClient = null

## The mesh. See the big comment on `_setup_mesh()` for why this is NEVER
## assigned to `multiplayer.multiplayer_peer`.
var _rtc: WebRTCMultiplayerPeer = null

## Relay-only mode: join the room over the lobby socket and skip the WebRTC mesh
## entirely, so the seed / snapshot / hero path can be exercised where WebRTC does
## not exist. Set once in `_init()` from `--lobby-only` in the user command line,
## the same precedence shape `LobbyClient.resolve_lobby_url()` uses for `--lobby=`.
##
## ponytail: a TEST/DEV mode for the headless E2E (scripts/mp_e2e.sh) and for a
## desktop developer with no `webrtc-native` addon — NOT a shipped degraded mode.
## Its ceiling is that there is no mesh, so no presence and no avatars: you are in
## the room and share its world, but nobody moves. Opt-in from the command line
## only — nothing in the UI exposes it and the web build never sets it.
var lobby_only: bool = false

## lobby id (16 hex chars) → WebRTCPeerConnection
var _connections: Dictionary = {}

## lobby id → RemoteAvatar (a child of this node)
var _avatars: Dictionary = {}

## lobby id → Array of relayed payloads that arrived BEFORE we had a connection
## to that peer, replayed in order by `_add_peer`. See `_buffer_signal()` for
## why this window exists at all.
var _pending_signals: Dictionary = {}

## Our own lobby id, the room code, the current master's id, and the member list
## exactly as the lobby reports it.
var _you: String = ""
var _room: String = ""
var _master: String = ""
var _members: Array = []

## The invite code the player actually typed ("" when hosting). The lobby CREATES
## a room for any well-formed code it does not know (server/room.go's Join), so a
## one-character typo joins a brand-new empty room and reports it as success —
## which is exactly what a real join looks like from the `welcome` frame alone.
## Keeping the request is what lets `_on_lobby_joined` tell them apart.
var _requested_code: String = ""

## The world seed shared by everyone in this room, and whether we know it yet.
## `0` is a legitimate seed value, hence the separate flag rather than a sentinel.
var _room_seed: int = 0
var _has_seed: bool = false

## THE LOBBY IS THE SOURCE OF TRUTH FOR HEROES. `_heroes` maps hero name → the
## lobby id holding it, `_pool` is every hero the lobby offers. Both are replaced
## wholesale by each `heroes` broadcast and are never edited locally: a claim
## changes this peer's body only once the lobby confirms it, which is what makes
## two peers racing for the same hero impossible to get wrong. The lobby also
## releases a departing member's hero itself, so this client must never do that.
var _heroes: Dictionary = {}
var _pool: Array[String] = []

## JOIN-TIME STATE REPLAY. `_collected_ids` is the union of every coin id anyone
## in this room has banked — a Dictionary used as a set (the value is ignored),
## kept in INSERTION ORDER so `_recent_collected_ids()` can truncate the oldest.
## `_peer_state` holds one entry per other member,
## `{"coins": int, "dist": int, "pos": Vector3}`, seeded by that
## peer's join snapshot and kept current by every presence packet afterwards.
## Both are room-scoped: `leave()` empties them and `report_coin_collected()`
## refuses to record while offline, so a solo session allocates nothing here no
## matter how many coins it banks.
var _collected_ids: Dictionary = {}
var _peer_state: Dictionary = {}

## THE ROOM'S CAPTIVE SET (bead godot-test1-3iy.10) - a Dictionary used as a SET of
## hero names. GAME state, not LOBBY state: the lobby does signalling, membership
## and master naming and deliberately no game logic, so this rides the mesh (verb
## `cap`) and the join snapshot rather than `server/room.go`.
##
## Room-scoped: `leave()` empties it, the `report_*` verbs refuse to record while
## offline, and a solo session never allocates an entry.
var _captives: Dictionary = {}

## THE LAST LOBBY HOLDER OF EACH HERO - `{hero name: peer id}`, and the whole of
## what authorizes a capture (see `_apply_captive`).
##
## IT IS NOT `_heroes`, AND THE DIFFERENCE IS THE RACE. `SetHero` releases the
## claim on the hero just taken as it grants the new one, so by the time a `cap`
## packet is processed the lobby may already have said "nobody holds primm" - and
## the two facts travel different transports (the mesh, and the lobby's `heroes`
## frame), so no delay on this side can order them. This map only ever LEARNS a
## holder and never forgets one, so "bob was the last member the lobby named as
## primm's holder" stays true across the reassignment that made him ask, and the
## capture is authorized whichever frame arrives first.
##
## It is not a weaker check than `_heroes` would be: a hero is only ever re-holderd
## by an actual lobby claim, so a member can still only assert the hero the lobby
## last put it in - which is exactly the reach the game gives it.
var _last_holder: Dictionary = {}

## RELEASES THAT ARRIVED BEFORE THE CAPTURE THEY UNDO - `{hero name: msec}`.
##
## A capture is broadcast by the peer that lost the hero; the release is broadcast
## by whoever WALKED INTO THE CELL, which is somebody else. Reliable delivery
## orders a single sender's packets and says nothing about two, so a third peer can
## see the liberation first, drop it (that hero is not in its set yet) and then
## accept the capture - leaving a hero locked up on one screen for the rest of the
## run, with nobody able to free him a second time.
##
## The real order is never in doubt: a liberation is CAUSED by the capture it
## undoes. So a release for a hero we have not heard about yet is remembered, and
## the capture that turns up behind it is dropped as the stale packet it is.
##
## ponytail: a time window rather than a per-hero version counter. The window only
## has to cover transport reordering (milliseconds) while the shortest honest
## re-capture is a lobby round trip plus a whole hunter telegraph-shadow-close beat
## (tens of seconds), so RELEASE_GRACE_MSEC sits three orders of magnitude inside
## the gap. The upgrade path is a sequence number per hero carried in the packet,
## which costs an agreement this protocol otherwise never needs.
var _released_msec: Dictionary = {}

## ...and its mirror: when we last accepted a CAPTURE for each hero, so the
## master's periodic set cannot undo one it has not heard about yet. Same window,
## same reason, opposite direction - see `_adopt_room_captives()`.
var _captured_msec: Dictionary = {}

## How long a release outruns a capture for the same hero, and a capture outruns
## the master's periodic set. See `_released_msec` and `_captured_msec`.
const RELEASE_GRACE_MSEC: int = 3000

## Seconds accumulated toward the master's next room publish.
var _room_accum: float = 0.0

## THE ROOM'S EXPLORED SET — 22 bits of Budapest, one per `BudapestPlan.SLOTS`
## row (bead godot-test1-8gw.5). The room-wide union of what every member has
## walked into; `player_controller.explored_mask` is this peer's own copy and the
## two are folded into each other exactly as `_captives` and `captive_heroes` are.
##
## ADD-ONLY, which is the whole reason this needs none of the captive set's
## machinery. `_apply_explored()` ORs, so ordering between the live `lmk` verb,
## the master's periodic `room` packet and a join snapshot does not matter, a
## repeat is free, and a stale master can un-explore nothing — there is no
## `_released_msec` here because there is no release.
##
## Room-scoped: `leave()` empties it and a solo session never touches it. The
## PLAYER's copy deliberately survives a room join — see `report_landmark_explored`.
var _explored_mask: int = 0

## Landmark claims this peer has made and not yet seen the master publish back:
## `{ slot index : true }`. THE ONLY RETRY QUEUE IN THIS FILE, and the reason is
## in `report_landmark_explored()` — a claim is made exactly once per run, so a
## dropped one is a landmark permanently missing from the ROOM's win set, which
## no other verb here is true of. Bounded by the plan's 22 slots, drained one per
## `room` beat, and normally empty. Master-side it is always empty (a master
## unions its own claims directly); `leave()` empties it with the room.
##
## NOT to be confused with `_pending_claims`, which is the coin-pickup arbitration's
## in-flight table — a different verb (`clm`) about a different kind of claim.
var _pending_landmarks: Dictionary = {}

## The last captive-set-and-verdict the master RELAYED, as a string to compare
## against. The relay leg fires only when this changes - see `_send_room_state()`,
## where the reason is the lobby's own stall rule and not tidiness.
var _room_relay_digest: String = ""

## ONE SNAPSHOT PER SENDER, EVER — the set of peers whose `state` frame we have
## already folded in. The protocol sends exactly one per (incumbent, joiner) pair,
## but a relayed payload is unvalidated peer input: without this latch a member
## looping `state` frames grows `_collected_ids` without limit (the
## `MAX_STATE_IDS` cap bounds one message, not the total) and forces a full
## `"coin"` group sweep per frame. Room-scoped like the two above.
var _state_received: Dictionary = {}

## JOIN PLACEMENT, which happens at most once per room. `_first_member` is true
## when the `welcome` frame found us alone — a host has nobody to join, so its
## spawn is left exactly as phase 3 left it. `_join_applied` is the latch that
## keeps the placement to one shot even though it is attempted from both the
## seed and every snapshot (either may land first). Both are reset by `leave()`.
var _first_member: bool = true
var _join_applied: bool = false

## The FROZEN contribution of members who have left. A departing peer's coins are
## folded in here rather than dropped: dropping them would shrink the room's bank
## in front of everyone. Room-scoped like the two above.
var _gone_coins: int = 0

## How many join snapshots this peer is still waiting on before it places itself,
## and how long it has waited (seconds). See `JOIN_SNAPSHOT_WAIT`.
var _expected_snapshots: int = 0
var _join_wait: float = 0.0

## When the `welcome` frame landed, i.e. when the arrival this peer owes a
## placement for happened. Read only through `_arriving()`; see
## `JOIN_PLACE_WINDOW` for why the placement needs an expiry and not just a latch.
## A wall-clock stamp rather than a ticked accumulator on purpose: it costs no
## per-frame work, and it keeps running while a throttled tab's `_process` does
## not — which is the case the window exists to refuse.
var _join_msec: int = 0

## The `/ice` payload, fetched once per join and reused for every connection.
var _ice: Dictionary = {}

## Presence send accumulator (seconds).
var _send_accum: float = 0.0

## Crocodile-sync send accumulator (seconds). See CROC_SYNC_HZ.
var _croc_accum: float = 0.0

## Crocodile id → the local crocodile node with that id, populated LAZILY on a
## lookup miss (one scan of the `"crocodile"` group caches every id at once) and
## purged of freed instances on each sync tick. It exists so that receiving a
## packet naming 25 crocodiles is 25 dictionary hits rather than 25 scans of a
## group holding ~1000 nodes at 10 Hz.
var _synced_crocs: Dictionary = {}

## Crocodile id → `Time.get_ticks_msec()` of the last sample the master sent for
## it. Drives CROC_SYNC_TIMEOUT. Room-scoped, cleared by `leave()`.
var _croc_seen: Dictionary = {}

## Crocodile ids the ROOM has killed (giant Teibi crushed one on some peer and the
## master ruled on it). Read by `is_croc_dead()` from every crocodile's `_ready()`,
## so one that dies here does not walk back in when its chunk regenerates.
## Room-scoped and cleared by `leave()`; unbounded within a room, which is fine
## because entries only ever arrive at the rate a player can physically stand on
## crocodiles as giant Teibi — a rate the `kill` verb's VERB_BUDGET_PER_SEC entry
## is what actually holds a hostile peer to.
var _dead_crocs: Dictionary = {}

## `"<peer id>:<verb>"` → `{"start": msec, "count": int}`: the current one-second
## window of the rate limit on state-mutating mesh verbs. See VERB_BUDGET_PER_SEC
## and `_verb_rate_ok()`. Room-scoped, cleared by `leave()`.
var _verb_rate: Dictionary = {}

## Seed self-heal state: seconds since the last `seed_req` went out, and how many
## have gone out this room. Both are room-scoped and reset by `leave()`.
var _seed_req_accum: float = 0.0
var _seed_req_tries: int = 0

## STALL WATCH. `_hb_accum` paces the master's own beat; `_last_hb_msec` is when
## we last heard one (or joined, or learned of a new master — see
## `_tick_stall_watch`, which explains why both of those count as a beat);
## `_stall_accum` paces our votes and `_stall_reported` keeps the status line to
## one message per stall rather than one every two seconds. All room-scoped and
## reset by `leave()`.
var _hb_accum: float = 0.0
var _last_hb_msec: int = 0
var _stall_accum: float = 0.0
var _stall_reported: bool = false

## PICKUP CLAIMS AWAITING A CONFIRM: pickup id → `{"n": int, "v": int,
## "age": float, "tries": int}`. Only ever non-empty on a NON-master peer in a
## room (the master resolves its own claims on the spot), and only for the few
## hundred milliseconds a confirm takes. Driven by `_tick_claims()` and cleared
## by `leave()`.
var _pending_claims: Dictionary = {}

## THE ROOM'S COIN STREAK, owned by the master and mirrored by everyone else.
##
## `_room_streak` is only meaningful on the master — it is what
## `_resolve_claim()` advances and what the confirm's `m` field is derived from.
## Every peer keeps `_room_multiplier` and `_room_streak_deadline_msec` so
## `room_multiplier()` can answer the HUD without a round trip, and so the
## multiplier expires on its own when the room stops picking things up rather
## than sticking at x5 forever.
var _room_streak: int = 0
var _room_multiplier: int = 1
var _room_streak_deadline_msec: int = 0

## Whether we are currently holding a `PauseHub` claim on behalf of a room member
## who pressed P — see `_apply_remote_pause()`. ONE claim however many peers are
## pausing, because the hub counts holders by node identity and this node is one
## node; the bit is only here so the take and the release happen on the edge
## rather than every frame.
var _paused_by_remote: bool = false



func _init() -> void:
	# Idle until host()/join(). Belt-and-braces only: NOTIFICATION_READY turns
	# `_process` back on for any script that overrides it, so the real guard is
	# `_process`'s `_state == OFFLINE` early return. In `_init` rather than
	# `_ready` for the same reason LobbyClient does it: `_ready` runs an idle
	# frame later and would undo a `set_process(true)` issued by a caller that
	# joins immediately.
	set_process(false)
	# Relay-only opt-in, command line only. See `lobby_only`'s own comment.
	lobby_only = OS.get_cmdline_user_args().has("--lobby-only")
	# Keep polling the socket and the mesh while the tree is paused. A pause
	# (the P key, the mobile focus-loss pause, an open MP panel) that stopped
	# `_process` would stop `LobbyClient`'s `_socket.poll()` too, and the lobby
	# reaps a peer that stops answering its 20 s ping — pausing would silently
	# drop you out of the room. Children (the socket, the avatars) inherit this.
	process_mode = Node.PROCESS_MODE_ALWAYS


# =============================================================================
# AVAILABILITY
# =============================================================================

static func webrtc_available() -> bool:
	"""
	Can this build actually open a WebRTC connection?

	The browser export has WebRTC built in (it is backed by the browser's own
	implementation). **Desktop Godot 4.5 has the classes but no implementation** —
	`WebRTCPeerConnection.new()` prints "No default WebRTC extension configured"
	and every call fails — until the official `webrtc-native` GDExtension is
	dropped into `addons/`.

	ponytail: a file-existence probe, because Godot exposes no API to ask whether
	a default WebRTC extension is registered. Upgrade to that API if one ever
	lands; until then a missing file is exactly as good a signal and costs one
	stat call, once per join.
	"""
	if OS.has_feature("web"):
		return true
	return FileAccess.file_exists(WEBRTC_ADDON_PATH)


# =============================================================================
# PUBLIC API
# =============================================================================

func host() -> void:
	"""Create a fresh room. The lobby treats an empty room code as 'make me one'."""
	join("")


func join(code: String) -> void:
	"""
	Join room `code` (empty = create). Idempotent in the sense that joining while
	already in a room leaves the old one first — there is only ever one mesh.
	"""
	if not lobby_only and not webrtc_available():
		status.emit("Multiplayer needs the WebRTC addon on desktop — see README")
		return

	leave()
	_ensure_lobby()

	_requested_code = code
	_state = State.CONNECTING
	set_process(true)
	var label: String = display_name if not display_name.is_empty() else DEFAULT_DISPLAY_NAME
	# Status FIRST: `connect_to_room` can fail synchronously (a malformed URL
	# emits `lobby_error` before it returns), and that handler's own status line
	# has to be the one left standing — otherwise the panel reports "Connecting…"
	# forever for a join that never started.
	status.emit("Connecting to %s…" % LobbyClient.resolve_lobby_url(lobby_url))
	_lobby.connect_to_room(code, label, lobby_url)


func _ensure_lobby() -> LobbyClient:
	"""
	The `LobbyClient` child, created and wired on first use.

	Creating it opens NO socket and changes no state — `connect_to_room()` does
	that — which is what lets `list_rooms()` browse the lobby while still fully
	OFFLINE. `leave()` deliberately keeps the node, so the wiring below happens
	once per session however many rooms are joined.
	"""
	if _lobby == null:
		_lobby = LobbyClient.new()
		_lobby.name = "Lobby"
		add_child(_lobby)
		_lobby.joined.connect(_on_lobby_joined)
		_lobby.peer_joined.connect(_on_lobby_peer_joined)
		_lobby.peer_left.connect(_on_lobby_peer_left)
		_lobby.master_changed.connect(_on_lobby_master_changed)
		_lobby.relay.connect(_on_lobby_relay)
		_lobby.heroes_changed.connect(_on_lobby_heroes)
		_lobby.lobby_error.connect(_on_lobby_error)
		_lobby.closed.connect(_on_lobby_closed)
	return _lobby


func list_rooms(callback: Callable) -> void:
	"""
	Ask the lobby for its open rooms and hand `callback` the array (see
	`LobbyClient.fetch_rooms` for the shape and for why failure reads as an empty
	list rather than an error).

	Exposed here so `mp_ui.gd` keeps talking only to the manager through the `"mp"`
	group — it never learns the lobby URL, or that a `LobbyClient` exists at all.

	Works while OFFLINE, which is the entire point: the list is what a player
	browses *before* joining anything. It opens no socket and does not touch
	`_state`, so calling it changes nothing about a solo run.
	"""
	_ensure_lobby().fetch_rooms(callback, lobby_url)


func leave() -> void:
	"""
	Tear everything down and return to OFFLINE, leaving no trace: no avatars, no
	connections, no mesh, no socket, no per-frame work. Solo play resumes exactly
	as it was. Safe to call from any state, including OFFLINE.
	"""
	# RESOLVE PENDING CLAIMS FIRST, before anything below is torn down. Every one
	# of them names a pickup the player has already visibly taken: `coin.gd` hid
	# the coin and left it UNFREED for the confirm's sweep to collect, and
	# `treasure_chest.gd` skipped its own award for the same reason. Wiping the
	# dictionary alone stranded that coin in the tree and in the "coin" group
	# until its chunk unloaded — invisible, uncollectable, paying nothing, still
	# ticked by the LOD manager's coin scan — and paid a chest's whole 8-15 coin
	# burst nothing at all while running the full shower animation.
	# `_resolve_claim_locally` is exactly the path `_tick_claims` would have taken
	# a second later, and it needs `_state` still IN_ROOM, hence the position at
	# the very top of this function.
	for pickup_id: int in _pending_claims.keys():
		var claim: Dictionary = _pending_claims[pickup_id]
		_resolve_claim_locally(pickup_id, int(claim["n"]), int(claim["v"]))
	_pending_claims.clear()

	for avatar: RemoteAvatar in _avatars.values():
		avatar.queue_free()
	_avatars.clear()

	for conn: WebRTCPeerConnection in _connections.values():
		conn.close()
	_connections.clear()
	_pending_signals.clear()

	if _rtc != null:
		_rtc.close()
		_rtc = null

	# Set OFFLINE *before* closing the socket, so the `closed` signal this
	# provokes is recognised as our own teardown and not a lost connection.
	_state = State.OFFLINE
	if _lobby != null:
		_lobby.disconnect_from_room()

	_you = ""
	_room = ""
	_master = ""
	_members = []
	_requested_code = ""
	_heroes = {}
	_pool = []
	_collected_ids = {}
	_peer_state = {}
	# The room's captive set dies with the room: back in solo play the player's own
	# `captive_heroes` is the whole truth again, and `player_controller.leave`'s
	# caller (Play Again, the Leave button, a dropped socket) has already decided
	# what happens to that. Nothing is pushed into the player from here - a leave
	# is not a liberation.
	_captives = {}
	# The ROOM's explored set dies with the room, like the captive set above it.
	# Nothing is pushed into the player from here: a leave is not an un-exploring,
	# and the player's own bits are its own truth again the moment it is solo.
	_explored_mask = 0
	_pending_landmarks = {}
	_last_holder = {}
	_released_msec = {}
	_captured_msec = {}
	_room_accum = 0.0
	_room_relay_digest = ""
	_state_received = {}
	# THE ROOM'S PAUSE DIES WITH THE ROOM, IMMEDIATELY. `_peer_state` is empty
	# now, so this releases; and it has to be called explicitly because `_process`
	# early-returns on OFFLINE and would never reach the release on its own —
	# leaving solo play frozen with nothing alive that could unfreeze it.
	_apply_remote_pause()
	_first_member = true
	_join_applied = false
	_gone_coins = 0
	_expected_snapshots = 0
	_join_wait = 0.0
	_join_msec = 0
	_ice = {}
	_send_accum = 0.0
	_croc_accum = 0.0
	_seed_req_accum = 0.0
	_seed_req_tries = 0
	_hb_accum = 0.0
	_last_hb_msec = 0
	_stall_accum = 0.0
	_stall_reported = false
	# Already drained at the top of this function (see there): each pending claim
	# was resolved locally so its hidden pickup is freed and paid, rather than
	# re-driven at a master we are no longer talking to.
	_pending_claims = {}
	_room_streak = 0
	_room_multiplier = 1
	_room_streak_deadline_msec = 0
	# The room's kill list dies with the room: back in solo play every crocodile
	# the local terrain generates is this player's own again.
	_dead_crocs = {}
	_verb_rate = {}
	# Hand every synced crocodile back to its own AI. A peer that leaves a room
	# must not be left standing in its solo run among frozen crocodiles waiting
	# for samples from a master it is no longer talking to.
	_release_synced_crocs()
	# `_room_seed` is deliberately kept: leaving a room does not regenerate the
	# world, so the player keeps walking the terrain they are on. `_has_seed` is
	# CLEARED, because it is the "we already adopted this room's seed" latch that
	# `_receive_seed` early-returns on — carrying it across a leave would make
	# the next room's seed be dropped on the floor ("host, nobody joins, leave,
	# join a friend's code" is the ordinary flow that hits it), and the two peers
	# would walk visibly different worlds while the UI reported success.
	_has_seed = false
	set_process(false)
	room_changed.emit("", [])
	heroes_changed.emit({}, [])


func get_room_code() -> String:
	"""The 6-character invite code, or "" when offline."""
	return _room


func get_members() -> Array:
	"""The lobby's member list, `[{"id": String, "name": String}, ...]`, us included."""
	return _members


func my_id() -> String:
	"""Our own 16-hex lobby id, or "" when offline."""
	return _you


func get_master() -> String:
	"""The room's current master id, or "" when offline. `get_master() == my_id()` is "we are the master"."""
	return _master


func is_online() -> bool:
	"""True from `welcome` until `leave()` — i.e. while a room actually exists."""
	return _state == State.IN_ROOM


func is_busy() -> bool:
	"""
	True from the moment `join()` is called until `leave()` — the WIDER window,
	covering the seconds a join spends CONNECTING (socket, then ICE) before
	`welcome` makes it a room.

	`is_online()` answers "is there a room", which is what every gameplay path
	wants. This answers "is this peer engaged with the lobby at all", which is what
	anything about to disrupt the session — `build_version.gd`'s auto-reload — has
	to ask instead: a reload during CONNECTING abandons the join in flight, and the
	player just sees the button do nothing.
	"""
	return _state != State.OFFLINE


func room_seed() -> Variant:
	"""
	The world seed everyone in this room shares, or `null` when there is no room
	or its seed has not arrived yet.

	Untyped-with-a-null-default for the same reason `endless_terrain.new_run()`'s
	`forced_seed` is: `0` is a legitimate seed, so no int can mean "none". This
	exists for `player_controller.restart_game()` — "Play Again" must regenerate
	the SHARED world, not roll a private one, or the first death in a room ends
	the whole premise with two peers on different terrain.
	"""
	if _state != State.IN_ROOM or not _has_seed:
		return null
	return _room_seed


# =============================================================================
# LOBBY EVENTS
# =============================================================================

func _on_lobby_joined(you: String, room: String, master: String, members: Array) -> void:
	"""
	The `welcome` frame — always the first one, and it already carries the master
	and the full member list (including us). Everything the mesh needs to start.
	"""
	# A TYPO IS NOT A ROOM. The lobby creates any well-formed code it does not
	# know, so "join ABC123" with one wrong character succeeds into a fresh empty
	# room — two friends then sit in different rooms, each watching a member list
	# that will never grow, with no error anywhere. We asked for a code and came
	# out alone AND master, which only happens when the lobby minted the room for
	# us: that is the typo, so say so instead of reporting a room.
	if not _requested_code.is_empty() and master == you and members.size() <= 1:
		status.emit("No room %s — check the code" % room)
		leave()
		return

	_you = you
	_room = room
	_master = master
	_members = members
	# Alone in the `welcome` frame means the lobby just minted this room for us:
	# there is no run in progress to join, so no placement is ever applied.
	_first_member = members.size() <= 1
	# THE HOST'S BUDAPEST WALK IS THE ROOM'S STARTING UNION (codex review
	# 2026-09-02). A host is the one peer whose world is NOT replaced — it never
	# adopts a foreign seed, so `reset_position()` never runs and its
	# `explored_mask` deliberately survives into the room. Left out of
	# `_explored_mask` those landmarks would be invisible to every peer for the
	# room's life, because `explore_landmark()` refuses a bit it has already set and
	# so can never report them again — the host would then be the only member
	# counting them, which is exactly the divergence a room-wide set exists to stop.
	# Only for the host: a JOINER's mask is cleared by `_receive_seed` and importing
	# it here could race that clear.
	if _first_member:
		var host_player: Node = get_tree().get_first_node_in_group("player")
		if host_player != null and "explored_mask" in host_player:
			_explored_mask |= int(host_player.explored_mask) \
					& ((1 << BudapestPlan.SLOTS.size()) - 1)
	# Every member already here sends us exactly one join snapshot, so this is how
	# many the placement waits for (see JOIN_SNAPSHOT_WAIT). Peers arriving AFTER
	# us are deliberately not counted: the protocol sends snapshots to the joiner,
	# so a later arrival never sends us one and waiting for it would always burn
	# the full deadline.
	_expected_snapshots = maxi(0, members.size() - 1)
	_join_wait = 0.0
	# The arrival the placement is owed to. Past `JOIN_PLACE_WINDOW` from here,
	# nothing on the wire may move the local player again (see the constant).
	_join_msec = Time.get_ticks_msec()
	# ARRIVING COUNTS AS A BEAT. Without this stamp `_last_hb_msec` is 0, i.e.
	# already `HEARTBEAT_TIMEOUT` in the past, and a joiner votes to depose a
	# perfectly healthy master four seconds after walking in — before that master
	# has had a chance to send its first beat.
	_last_hb_msec = Time.get_ticks_msec()
	_stall_accum = 0.0
	_stall_reported = false
	_state = State.IN_ROOM
	# A ROOM'S CAPTIVE SET IS THE ROOM'S. `join()` unwinds through `leave()`, which
	# deliberately leaves the local player's own `captive_heroes` alone (a leave is
	# not a liberation) - so without this a host would walk into a shared world
	# still holding a solo run's captures while its manager exported an empty set,
	# and a joiner would carry the previous room's names past the master's snapshot.
	# Cleared to the room's truth, which the master's snapshot then fills in.
	_reset_player_captives()
	status.emit("In room %s (%d/4)" % [room, members.size()])
	room_changed.emit(room, members)

	# SEED DISTRIBUTION IS MESH-INDEPENDENT, and this line is what makes it so.
	# The seed rides the lobby relay, which is open the moment `welcome` lands —
	# it has no business waiting on ICE. It used to: `_has_seed` was latched only
	# inside `_setup_mesh()`, i.e. after an HTTP round trip to `/ice`, so a master
	# whose fetch was still in flight when somebody joined answered the direct
	# send in `_on_lobby_peer_joined` with a silently skipped `_has_seed` check —
	# the joiner then walked its own private world for the room's life with no
	# error anywhere. Latching here publishes the master's terrain seed as soon as
	# there is a room to publish it to.
	_broadcast_seed_if_master()

	# The mesh cannot start before we know which STUN/TURN servers to use, so the
	# rest of setup hangs off the /ice callback. `lobby_only` stops here: no /ice,
	# no mesh, no presence — everything above this line rides the relay and keeps
	# working, which is the whole point of the mode.
	if lobby_only:
		return
	_lobby.fetch_ice(_on_ice_ready)


func _on_ice_ready(ice: Dictionary) -> void:
	"""ICE config in hand (real or the STUN-only fallback) — build the mesh."""
	if _state != State.IN_ROOM:
		return  # Left the room while /ice was in flight.
	# The mesh's ICE config is fixed for the room's life. A stale reply landing
	# after `_setup_mesh()` already ran off FALLBACK_ICE (see the ERR_BUSY path
	# below) must NOT overwrite `_ice`: peers added before it would be STUN-only
	# and peers added after would have TURN, so in a 3–4 player room behind
	# symmetric NAT some pairs connect and some silently never do.
	if _rtc != null:
		return
	_ice = ice
	_setup_mesh()


func _setup_mesh() -> void:
	"""
	Create the mesh and open a connection to every member already in the room.

	**`_rtc` is NEVER assigned to `multiplayer.multiplayer_peer`, and that is the
	single most important line in this file.** It is used as a plain `PacketPeer`:
	`poll()` in `_process`, `put_packet()` to send, `get_packet()` /
	`get_packet_peer()` to receive. Leaving the global `MultiplayerAPI` untouched
	is what keeps solo play byte-for-byte unchanged — no scene replication, no
	RPC checks, no `multiplayer_peer` for some other system to trip over. This
	phase has no shared simulation to replicate, so the whole high-level
	multiplayer stack would be cost with no benefit.
	"""
	# Build the mesh once per room. A second call would strand the working one:
	# `_add_peer` early-returns for every id already in `_connections`, so the
	# replacement `_rtc` would carry zero peers — a room whose avatars never
	# appear and which nothing times out. The path in is a stale `/ice` reply:
	# `leave()` does not cancel an in-flight HTTPRequest, and a rejoin inside
	# that window gets ERR_BUSY → the synchronous FALLBACK_ICE builds the mesh,
	# then the original request lands on the same callback.
	if _rtc != null:
		return

	_rtc = WebRTCMultiplayerPeer.new()
	var err: int = _rtc.create_mesh(MpCodec.peer_int_id(_you))
	if err != OK:
		_rtc = null
		status.emit("Could not start the WebRTC mesh (error %d)" % err)
		leave()
		return

	for member: Variant in _members:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var id: String = str((member as Dictionary).get("id", ""))
		if id.is_empty() or id == _you:
			continue
		_add_peer(id, str((member as Dictionary).get("name", "")))

	# Idempotent re-send, kept because a master RE-ELECTED while its own mesh was
	# still building reaches this line without having passed the one above.
	# GUARDED BY `_has_seed` FOR THE SAME REASON `_on_lobby_master_changed` is:
	# without it, a peer promoted inside its own `/ice` window arrives here with
	# no seed, falls through to `_broadcast_seed_if_master`'s read-the-terrain
	# path and publishes its own PRIVATE solo world as the room's — which every
	# peer already holding the real seed drops on `_receive_seed`'s latch,
	# leaving the master alone on different ground while the UI reports success.
	# The genuinely seedless room is covered from the other end, by `seed_req`.
	if _has_seed:
		_broadcast_seed_if_master()


func _on_lobby_peer_joined(id: String, peer_name: String) -> void:
	"""A peer arrived after us. Same setup as a welcome-list member."""
	if _state != State.IN_ROOM or id.is_empty() or id == _you:
		return
	# THE NEW MEMBER HAS HEARD NONE OF IT. The relay digest is global — one string
	# for "what the room was last told" — so without this, a peer that joins after
	# the last change is skipped by every subsequent unchanged publish and never
	# learns the current set over the relay at all. One extra relay per join, which
	# is nowhere near the lobby's stall window.
	_room_relay_digest = ""
	# Append only if this id is not already listed. `_members.size()` is
	# load-bearing — `_tick_stall_watch` uses it as the "is there anybody to elect"
	# guard — so a duplicate `peer_join` (a reconnect race, a malformed frame)
	# must not inflate it. Mirrors the removal loop in `_on_lobby_peer_left`.
	for member: Variant in _members:
		if typeof(member) == TYPE_DICTIONARY and str((member as Dictionary).get("id", "")) == id:
			return
	_members.append({"id": id, "name": peer_name})
	_add_peer(id, peer_name)
	# A joiner missed the broadcast that went out before it existed, so if we are
	# the master, send the seed straight to it.
	if _master == _you and _has_seed:
		_lobby.send_signal_to(id, {"mp": "seed", "seed": _room_seed})
	# EVERY member snapshots itself to the joiner, not just the master. The seed
	# above is a single value the master owns, but the join state is not: the
	# collected-coin set is the UNION across the room and each peer only knows
	# the ids it banked itself, while the shared bank and distance are a
	# sum over per-peer contributions. A snapshot from the master alone would
	# hand the joiner a world still full of coins the others took and a bank
	# missing their share.
	_send_state_to(id)
	status.emit("%s joined" % peer_name)
	room_changed.emit(_room, _members)


func _on_lobby_peer_left(id: String) -> void:
	"""
	A peer left: drop its avatar, its connection and anything buffered for it —
	but FREEZE its contribution to the room's totals rather than dropping it (see
	`_gone_coins`). Distance needs no freezing: it is a max, and the local
	`run_distance` is a running max that already latched it.
	"""
	if _peer_state.has(id):
		var gone: Dictionary = _peer_state[id]
		_gone_coins += int(gone.get("coins", 0))
		_peer_state.erase(id)
	if _avatars.has(id):
		(_avatars[id] as RemoteAvatar).queue_free()
		_avatars.erase(id)
	_pending_signals.erase(id)
	# A LEAVING MEMBER IS ALSO A CHANGE OF AUDIENCE. The relay digest is one string
	# for the whole room rather than one per recipient, so it is invalidated on any
	# membership change and the next publish goes out to whoever is there now.
	_room_relay_digest = ""
	if _connections.has(id):
		(_connections[id] as WebRTCPeerConnection).close()
		_connections.erase(id)
		# Only ever remove a peer the MESH still holds — `remove_peer()` errors on
		# an unknown id. `_connections` is not that answer: a peer that left in
		# the /ice window was never added, and `WebRTCMultiplayerPeer.poll()`
		# drops failed/closed connections itself, so a peer whose ICE never
		# completed is already gone from the mesh while `_connections` still
		# lists it. Ask the mesh.
		if _rtc != null and _rtc.has_peer(MpCodec.peer_int_id(id)):
			_rtc.remove_peer(MpCodec.peer_int_id(id))

	for i: int in range(_members.size() - 1, -1, -1):
		var member: Variant = _members[i]
		if typeof(member) == TYPE_DICTIONARY and str((member as Dictionary).get("id", "")) == id:
			_members.remove_at(i)
	room_changed.emit(_room, _members)


func _on_lobby_master_changed(id: String) -> void:
	"""
	The lobby re-elected a master (the old one dropped). The new master keeps the
	seed it already has and re-broadcasts it — it does **not** re-roll, which
	would yank the world out from under everyone mid-run. Real mid-run state
	replay is phase 4's problem.
	"""
	_master = id
	# A NEW MASTER STARTS WITH A CLEAN STALL CLOCK. The timer that was running
	# against the old master must not carry over, or the peer that just deposed a
	# dead host immediately deposes its replacement too — the replacement has by
	# definition not sent a beat yet.
	_last_hb_msec = Time.get_ticks_msec()
	_stall_accum = 0.0
	_stall_reported = false
	# A NEW MASTER IS A NEW CHANCE AT THE SEED, so the retry budget is a new one
	# too. `_tick_seed_request` gives up permanently past SEED_REQUEST_MAX_TRIES,
	# and phase 5 made spending that budget on a master that cannot answer the
	# ordinary case: a host whose tab is throttled is exactly what the stall vote
	# deposes, and it takes 20 s of unanswered `seed_req` down with it. Without
	# this reset the peer never asks the NEW master — which does hold the real
	# seed — so `_has_seed` stays false, `room_seed()` answers null, the join
	# placement never runs, and that player walks a private world for the room's
	# life while the panel reports a healthy room. The comment below promising
	# that "a seedless peer keeps sending seed_req to whoever the master
	# currently is" is only true because of these three lines.
	if not _has_seed:
		_seed_req_tries = 0
		_seed_req_accum = 0.0
	# PROMOTION IS A HOT STANDBY HANDOVER, and it is one loop because the replica
	# is just the local nodes. Every crocodile we have been rendering from the old
	# master's samples is a real local body holding that master's last known
	# transform, so dropping the remote-drive flag resumes simulation from exactly
	# where each one stands — no state replay, no snapshot, no gap.
	#
	# We also start heartbeating from here: `_tick_heartbeat` reads `_master`
	# every frame, so there is nothing to switch on beyond the beat accumulator,
	# which is zeroed so the first beat goes out a full interval from now rather
	# than at whatever phase the old accumulator happened to be in. If we are NOT
	# the new master we simply keep waiting, now on the new one's beats.
	if _master == _you:
		_release_synced_crocs()
		_hb_accum = 0.0
		# ADOPT OUR OWN PENDING CLAIMS. A claim waiting on the old master's confirm
		# can never get one now: `_send_reliable_to_master` refuses to send to
		# ourselves, so `_tick_claims` would just count `tries` up and then resolve
		# the pickup LOCALLY — banking it with the local multiplier and recording
		# the id in nobody's set but ours. The coin would still be standing on every
		# other screen, and the next peer to walk over it would claim it to us, get
		# refused by `_collected_ids` (silently, with no confirm), time out and bank
		# it a second time. Arbitrating them here is the same path they were always
		# headed for; `.keys()` is a copy, so `_apply_confirm`'s erase is safe.
		for pickup_id: int in _pending_claims.keys():
			var claim: Dictionary = _pending_claims[pickup_id]
			_pending_claims.erase(pickup_id)
			_resolve_claim(pickup_id, MpCodec.peer_int_id(_you), int(claim["n"]), int(claim["v"]))

	# ONLY re-broadcast a seed we actually adopted. A master elected before the
	# seed reached it (the old master dropping inside our /ice window) has
	# `_has_seed` false, and the terrain-read path below would publish its own
	# PRIVATE solo world as the room's seed — which every peer that already holds
	# the real one drops on `_receive_seed`'s latch, leaving the master alone on
	# different ground for the room's life while the UI reports success. Staying
	# quiet keeps the peers that already agree agreeing — and the gap it leaves
	# is now closed from the other end: a seedless peer keeps sending `seed_req`
	# to whoever the master currently is, and this one answers off its own
	# terrain when asked.
	if _has_seed:
		_broadcast_seed_if_master()


func _on_lobby_error(message: String) -> void:
	"""
	Bad room code, room full, malformed frame — all of them end the attempt.

	**Except a refused hero claim.** The lobby keeps the socket open for those and
	its last `heroes` broadcast is still the truth, so we report it, re-publish
	that truth (which snaps the UI's hero row back off the button the player
	optimistically pressed) and stay in the room. See HERO_ERRORS.
	"""
	if HERO_ERRORS.has(message):
		status.emit("Hero: %s" % message)
		heroes_changed.emit(_heroes, _pool)
		return
	status.emit("Lobby: %s" % message)
	leave()


func _on_lobby_closed(code: int, reason: String) -> void:
	"""
	The socket dropped. If we are already OFFLINE this is our own `leave()`
	unwinding and there is nothing to report.
	"""
	if _state == State.OFFLINE:
		return
	status.emit("Disconnected from the lobby (%d %s)" % [code, reason])
	leave()


# =============================================================================
# HERO POOL — who is playing which body, decided by the lobby
# =============================================================================
#
# The lobby already owns this: `server/room.go` holds one hero per member, hands
# the assignments out in `welcome` (with the full `pool`) and broadcasts a
# `heroes` frame on every claim, release and departure. So there is no election
# and no arbitration here — this side asks, applies what comes back, and offers
# the result to the UI. Everything is derived BY NAME, never by index, so a
# reorder of the lobby's `Heroes` slice or of `CHARACTERS` cannot silently swap
# two players' bodies.

func my_hero() -> String:
	"""The hero this peer holds, or "" when offline or holding none."""
	if _state != State.IN_ROOM:
		return ""
	for hero: String in _heroes:
		if str(_heroes[hero]) == _you:
			return hero
	return ""


func hero_holder(hero: String) -> String:
	"""The lobby id holding `hero`, or "" if nobody does."""
	if _state != State.IN_ROOM:
		return ""
	return str(_heroes.get(hero, ""))


func available_heroes() -> Array[String]:
	"""
	Every hero this peer may press: the unclaimed ones, plus the one we already
	hold — re-picking what you have is a no-op, not a refusal. Empty when offline.
	"""
	var free: Array[String] = []
	if _state != State.IN_ROOM:
		return free
	var mine: String = my_hero()
	for hero: String in _pool:
		# A HERO IN A CELL IS NOBODY'S TO PICK, his own holder included - the bead's
		# rule that a client never offers a captive hero in the picker. Tested
		# before the `mine` clause on purpose: re-picking what you hold is normally
		# a harmless no-op, but the one moment it matters is the frame after your
		# hero was taken, and offering it there is offering a body in a cell.
		if _captives.has(hero):
			continue
		if hero == mine or hero_holder(hero).is_empty():
			free.append(hero)
	return free


func claim_hero(hero: String) -> void:
	"""
	Ask the lobby for `hero` (`""` releases the one we hold).

	**Nothing changes locally here.** The body only moves when the lobby's
	`heroes` broadcast confirms the claim, so two peers pressing the same button
	in the same frame can never both end up in the same body — one is refused, and
	a refusal is a status line rather than a disconnect (see HERO_ERRORS).
	"""
	if _state != State.IN_ROOM or _lobby == null:
		return
	_lobby.send_hero(hero)


# =============================================================================
# THE ROOM'S CAPTIVE SET (bead godot-test1-3iy.10)
# =============================================================================
#
# A retrieval unit that lands its grab keeps the hero who was walking. Solo that
# is `player_controller.captive_heroes` and nothing else; in a room the set is
# ROOM-WIDE, because the owner's ruling makes both of the questions it answers
# room-wide: nobody may pick a hero who is in a cell, and the run ends when the
# room has no free hero left.
#
# THE OWNER'S RULE IS "REASSIGN FIRST, IMPRISON LAST", and the reassignment needs
# NO SERVER CHANGE: `server/room.go`'s `SetHero` already releases every hero claim
# a member holds and claims the new one under the process-wide room lock, refusing
# a contested claim with `errHeroTaken` and re-broadcasting the heroes truth. So a
# benched client simply calls `claim_hero()` on a free hero. Two peers losing a
# hero in the same frame serialize on that lock: the first wins, the second gets
# the refusal plus fresh truth and either picks again on its next tick or falls to
# the prison role. `claimable_hero()` below is the only thing this side adds.
#
# THE WIRE, one verb, broadcast reliable (a capture is a one-off event and a lost
# one is a hero the room believes is still playable):
#
#     cap    anyone -> everyone   {"t":"cap","h":String,"c":bool}
#
# and the whole set as ABSOLUTE VALUES in the join snapshot's `cap` field, which
# is the trust boundary a joiner has exactly one chance to hear.
#
# WHO MAY ASSERT WHAT - the asymmetry is deliberate and it is the whole security
# argument:
#
#   CAPTURE (`c` true) is the harmful direction (it removes a hero from the room
#     and, four times over, ends every run), so THE SENDER MUST BE THE HERO'S
#     HOLDER, asked of the lobby's own `_heroes` map. A capture is a fact about
#     the hero you were WALKING AS, so "the lobby says you are playing him" is
#     exactly the authorization the event has, and a member naming somebody else's
#     hero is refused. It must also be in `_pool` and not already captive, so an
#     assertion is idempotent and cannot be re-made.
#
#     THIS IS WHY THE REASSIGNMENT WAITS FOR `_tick_prison()` AND IS NOT SENT FROM
#     THE CAPTURE ITSELF. `SetHero` releases our claim on the hero just taken, so a
#     claim sent in the same frame as the `cap` packet races the lobby's `heroes`
#     broadcast on every OTHER peer: whoever processes the broadcast first no
#     longer sees us as the holder and drops the capture, and the room's sets
#     diverge for the rest of the run. Half a second later there is no race - and
#     it is spent inside the caught freeze, so nothing is visibly slower.
#
#   RELEASE (`c` false) is the benign direction and is open to any member,
#     because liberation is performed by whoever walks into the cell and that is
#     deliberately NOT the captive's holder ("uniform cells": liberation asks
#     nobody's name). A hostile release only makes the room believe a hero is free
#     who is not - and `available_heroes()` is the only thing that would offer
#     him, one press, refused by the lobby if somebody still holds him. The cost is
#     a delayed world game over, never a stolen body.
#
#   A LEAVER KEEPS HIS CAPTIVE, deliberately. The way out of a cell is somebody
#     walking into it, and that verb asks nobody's name - so a hero whose captor
#     quit is not a phantom, he is a rescue anybody in the room can still perform.

func is_hero_captive(hero: String) -> bool:
	"""Is this hero in a cell anywhere in the room? False offline."""
	return _captives.has(hero)


func captive_heroes() -> Array:
	"""Every hero the room is holding, in `_pool` order. A fresh array."""
	var out: Array = []
	for hero: String in _pool:
		if _captives.has(hero):
			out.append(hero)
	return out


func claimable_hero() -> String:
	"""
	A hero this peer could be reassigned to right now, or `""` when there is none.

	@return: a `_pool` name that nobody holds, nobody has captive and this build
	    has a body for - the FIRST such in pool order, so two peers racing pick the
	    same one and the lobby's room lock decides between them rather than luck.

	Deliberately excludes the hero we already hold: this is asked the moment ours
	was taken, and answering with it would be answering with a body in a cell.
	"""
	if _state != State.IN_ROOM:
		return ""
	var mine: String = my_hero()
	for hero: String in _pool:
		if hero == mine or _captives.has(hero):
			continue
		if not hero_holder(hero).is_empty():
			continue
		if hero_index(hero) < 0:
			continue  # A hero the lobby offers that this build has no character for.
		return hero
	return ""


func request_reassignment() -> bool:
	"""
	REASSIGN FIRST: ask the lobby to move us into a free hero.

	@return: true when a claim was sent, so the caller waits for the `heroes`
	    broadcast rather than benching the player; false when the room has nothing
	    to give and the prison role is the answer.

	Nothing changes locally - `claim_hero()`'s contract - so a claim that loses the
	race to `errHeroTaken` simply leaves us where we were, and the caller's next
	tick asks again against the fresher truth the refusal came with.
	"""
	var hero: String = claimable_hero()
	if hero.is_empty():
		return false
	claim_hero(hero)
	return true


func report_hero_captured(hero: String) -> void:
	"""
	The local player just lost `hero` to a retrieval unit. Tell the room.

	ROUTED THROUGH `_apply_captive` WITH OUR OWN ID, so the sender is held to the
	same holder rule every receiver holds it to - and so the two can never drift.
	At this instant the lobby still has us down as `hero`'s holder, which is what
	makes it pass; the reassignment that releases that claim is `_tick_prison()`'s,
	half a second later, for exactly this reason.

	A no-op offline (solo the player's own set is the whole truth) and idempotent.
	"""
	if _state != State.IN_ROOM or not _apply_captive(_you, hero, true):
		return
	_publish_captive(hero, true)


func report_hero_freed(hero: String) -> void:
	"""
	The local player walked into an occupied cell. Tell the room.

	Idempotent for the same reason `player_controller.hero_freed()` is: the tower
	re-drives its mirror, and freeing somebody who is not held is a no-op.
	"""
	if _state != State.IN_ROOM or not _apply_captive(_you, hero, false):
		return
	_publish_captive(hero, false)


func _publish_captive(hero: String, held: bool) -> void:
	"""
	Tell the room about one captive-set change, over BOTH transports.

	THE MESH FOR EVERYBODY IT CAN REACH, AND THE LOBBY RELAY FOR EVERYBODY IT
	CANNOT. `_broadcast_reliable()` writes only to peers whose data channel is
	already open, and ICE takes seconds - so a capture that lands while somebody is
	still negotiating would be missed by that peer for the room's life, and the
	join snapshot cannot cover it either (it was sent the moment they arrived,
	before this happened). The joiner would then offer a hero who is in a cell,
	claim him, and play a body every other screen shows locked up.

	This is the seed's own reasoning one verb along: the relay is open from
	`welcome`, so it is what reaches a peer the mesh has not finished building. The
	payload and the rule are IDENTICAL on both sides - `decode_captive()` and
	`_apply_captive()`, once - so the two transports cannot drift.
	"""
	# ponytail: TWO TRANSPORTS, NO RESYNC. One window survives both: a capture that
	# lands in the gap between the master sending a joiner its snapshot and US
	# learning that joiner exists reaches neither — the snapshot was already stale
	# and the loop below has nobody to send to. That joiner's picture of the cells is
	# then wrong for the room's life. The ceiling is one hero, and only for a capture
	# inside a sub-second window of a join; the upgrade path is the MASTER
	# re-publishing its whole set to peers still negotiating, which needs a
	# master-only set verb (the per-hero one here is authorized by `_last_holder` and
	# a master cannot re-assert somebody else's capture under that rule).
	var packet: Dictionary = {"t": "cap", "h": hero, "c": held}
	_broadcast_reliable(var_to_bytes(packet))
	_relay_to_negotiating({"mp": "cap", "h": hero, "c": held})


func _relay_to_negotiating(payload: Dictionary) -> void:
	"""
	Send one payload over the LOBBY RELAY to every member whose mesh is not up yet.

	`_broadcast_reliable()` writes only to peers whose data channel is open and ICE
	takes seconds, so this is how a peer mid-negotiation hears anything at all. The
	relay is open from `welcome`, which is the seed's own reasoning.

	Bounded by the room (at most three sends) and only ever called on events or at
	ROOM_SYNC_HZ, so it cannot become traffic.
	"""
	if _lobby == null:
		return
	for member: Variant in _members:
		if typeof(member) != TYPE_DICTIONARY:
			continue
		var id: String = str((member as Dictionary).get("id", ""))
		if id.is_empty() or id == _you:
			continue
		if _is_mesh_peer_connected(MpCodec.peer_int_id(id)):
			continue  # Already had it over the mesh; a second copy is a no-op anyway.
		_lobby.send_signal_to(id, payload)


func _send_room_state() -> void:
	"""
	MASTER ONLY: publish the room's captive set.

	`cd` / `co` ARE PUBLISHED AS ZEROS AND NOTHING READS THEM (owner veto
	2026-09-01, bead `godot-test1-ueg`). They carried the break-out's clock and
	verdict; the scene is gone and the ending is now decided per peer off the
	mirrored captive set below, which needs no authority because every peer reaches
	the same empty free set. The FIELDS stay on the wire because `decode_room()`
	drops a packet missing either and mixed-build rooms are real — see
	`MAX_CUSTODY_SECONDS`.

	ponytail: `co: 0` TELLS A PRE-VETO PEER "the master has no scene", so once its
	own roster empties it waits out `CUSTODY_MASTER_SILENCE_MSEC` and runs its
	legacy 35 s break-out alone — the old build behaving like the old build, which
	is the honest degrade and the ceiling here (codex review 2026-09-01). Publishing
	a standing `co: 2` to end it instead is WORSE, and measurably so: that peer's
	scene opens in the same window the master's verdict latches, so its
	`_custody_stale_verdict` refuses the first one, no later `co: 0` ever arrives to
	clear the refusal, and `verdict != 0` keeps `_custody_master_idle` false — it can
	neither be ended nor self-authorize, and sits sealed in the block for the room's
	life. The real upgrade path is a protocol version, not a value.

	WHAT IT REPAIRS, and why the live `cap` verb is not enough on its own: a capture
	that lands in the gap between the master snapshotting a joiner and the CAPTOR
	learning that joiner exists reaches neither — the snapshot was already stale and
	the captor has nobody to relay to. Nothing else in the protocol would ever
	correct it. This does, within half a second, because the master's set is the
	room's and the master hears every `cap`.

	Sent over the mesh every tick, AND over the relay ONLY WHEN THE SET OR THE
	VERDICT CHANGES.

	THE RELAY LEG IS EVENT-DRIVEN AND THAT IS NOT AN OPTIMISATION — it is the
	lobby's own stall rule. `server/room.go` refuses to act on a quorum of stall
	votes while the lobby has heard anything from the master inside
	`stallMasterSilence` (3 s), so a master relaying this twice a second looks ALIVE
	TO THE LOBBY however dead its heartbeat is, and a genuinely throttled tab can
	never be deposed. `scripts/mp_e2e.sh`'s stall phase is what caught that, and it
	is the reason this leg is not simply "send it every time".

	THE ZEROED FIELDS ARE DELIBERATELY OUTSIDE THE COMPARISON, which is now free:
	the SET is the only fact this verb carries, and the set is exactly what the
	change test watches.
	"""
	if _state != State.IN_ROOM or _master != _you:
		return
	var payload: Dictionary = {
		"t": "room", "cap": captive_heroes(), "cd": 0.0, "co": 0,
		# BUDAPEST'S EXPLORED SET (bead godot-test1-8gw.5). A NEW OPTIONAL FIELD:
		# `decode_room()` treats a missing `m` as absent rather than malformed, so
		# an older master's packet still repairs the cells it always did — the
		# `dead` / `gc` rule, and the opposite of `cd`/`co`, which are REQUIRED by
		# every peer that already shipped and so can never be dropped.
		"m": _explored_mask,
	}
	_broadcast_reliable(var_to_bytes(payload))
	var digest: String = "%s|%d" % [payload["cap"], _explored_mask]
	if digest == _room_relay_digest:
		return
	_room_relay_digest = digest
	var relayed: Dictionary = payload.duplicate()
	relayed.erase("t")
	relayed["mp"] = "room"
	_relay_to_negotiating(relayed)


func _receive_room(from_id: String, packet: Dictionary) -> void:
	"""
	The master's periodic truth. MASTER ONLY — the same authority rule the seed,
	`cnf`, `dead` and the croc sync all enforce, and for the same reason: this is
	applied WHOLESALE, so honouring a stranger's copy would let any member rewrite
	the room's cells.

	`cd` / `co` are decoded and then deliberately unused — see `decode_room()`.
	"""
	if from_id != _master:
		return
	var msg: Dictionary = MpCodec.decode_room(packet)
	if msg.is_empty():
		return
	_adopt_room_captives(msg["cap"])
	# THE EXPLORED SET NEEDS NO `_adopt_*` OF ITS OWN, and that is the whole payoff
	# of it being add-only: there is no direction for the master's older picture to
	# undo, so there is nothing for a grace window to protect. An old master sends
	# no `m`, which decodes as 0 and ORs to nothing — the documented mixed-room
	# ceiling, not a special case. This is also the beat that re-drives a win the
	# join gate deferred; see `_apply_explored()`.
	var published: int = int(msg["m"])
	_apply_explored(published)
	# THE ACK. This packet is the master's own truth, so a pending claim it carries
	# has landed and may stop being re-sent — see `_tick_landmark_claims()`. It is
	# done HERE and not in `_apply_explored()` because that function is also fed by
	# our OWN bits, and a claim cannot acknowledge itself.
	if not _pending_landmarks.is_empty():
		for index: int in _pending_landmarks.keys():
			if published & (1 << index) != 0:
				_pending_landmarks.erase(index)


func _adopt_room_captives(names: Array) -> void:
	"""
	Converge our captive set on the master's, in both directions.

	A REPAIR, NOT AN OVERWRITE, and the two grace windows are what make it one. The
	master's picture is up to ROOM_SYNC_HZ old, so a capture or a liberation we
	applied a moment ago may not be in it yet — adopting it flat would undo our own
	fresh assertion, and the master would put it back on its next publish: a visible
	flap at the publish rate. So a hero we captured or released inside
	RELEASE_GRACE_MSEC is left alone, and everything else is made to agree.

	Both directions are needed. The missing-capture case is the join gap this verb
	exists for; the missing-release case is the same gap with the packets the other
	way round, and leaving it out would strand a freed hero in a cell on one screen.
	"""
	var now: int = Time.get_ticks_msec()
	var wanted: Dictionary = {}
	for entry: Variant in names:
		var hero: String = String(entry)
		if not _pool.has(hero):
			continue  # Not a hero this room deals in.
		wanted[hero] = true
		if _captives.has(hero):
			continue
		if now - int(_released_msec.get(hero, -RELEASE_GRACE_MSEC)) < RELEASE_GRACE_MSEC:
			continue  # We freed him just now; the master has not heard yet.
		_captives[hero] = true
		_captured_msec[hero] = now
		_captive_changed(hero, true)
	for hero: String in _captives.keys():
		if wanted.has(hero):
			continue
		if now - int(_captured_msec.get(hero, -RELEASE_GRACE_MSEC)) < RELEASE_GRACE_MSEC:
			continue  # We took him just now; the master has not heard yet.
		_captives.erase(hero)
		_captive_changed(hero, false)


func _receive_captive(from_id: String, packet: Dictionary) -> void:
	"""
	One `cap` from the mesh. Unvalidated peer input - see the section header for
	who is allowed to assert what, and why the two directions differ.
	"""
	var msg: Dictionary = MpCodec.decode_captive(packet)
	if msg.is_empty():
		return
	_apply_captive(from_id, String(msg["h"]), bool(msg["c"]))


func _apply_captive(from_id: String, hero: String, held: bool) -> bool:
	"""
	Apply one captive assertion from `from_id`, under the rules in the section
	header. The ONE gate, shared by the `cap` verb and by our own capture, so the
	sender and every receiver cannot drift.

	@return: whether the room's set actually changed.
	"""
	if not _pool.has(hero):
		return false  # Not a hero this room deals in.
	if held:
		if _captives.has(hero):
			return false  # Already held: an assertion cannot be re-made.
		# A LIBERATION WE HEARD FIRST WINS - see `_released_msec`. The two verbs
		# come from different senders, so nothing orders them for us.
		if Time.get_ticks_msec() - int(_released_msec.get(hero, -RELEASE_GRACE_MSEC)) \
				< RELEASE_GRACE_MSEC:
			return false
		# THE AUTHORIZATION, and the only one this verb has: a capture is a fact
		# about the hero the sender was WALKING AS. A member naming a hero the
		# lobby never put it in is naming a body it cannot have lost.
		#
		# ASKED OF `_last_holder` AND NOT `hero_holder()` - see that field. The
		# reassignment this capture provokes releases the lobby claim, so the live
		# map stops naming the captor at an unpredictable moment relative to the
		# packet; the last-holder map never stops.
		if String(_last_holder.get(hero, "")) != from_id:
			return false
		_captives[hero] = true
		_captured_msec[hero] = Time.get_ticks_msec()
	else:
		# REMEMBERED WHETHER OR NOT WE HAD HIM, which is the whole point: the
		# release we drop here is exactly the one that overtook its capture.
		_released_msec[hero] = Time.get_ticks_msec()
		if not _captives.has(hero):
			return false
		_captives.erase(hero)
	_captive_changed(hero, held)
	return true


func _captive_changed(hero: String, held: bool) -> void:
	"""
	One entry moved: mirror it into the player and repaint the hero picker.

	THE PICKER REFRESH IS NOT OPTIONAL. `mp_ui` relabels its buttons on
	`heroes_changed` and on nothing else, and a capture or a liberation changes
	what may be pressed WITHOUT changing the lobby's assignment map - so a
	liberated hero would sit disabled and labelled "in a cell" until some unrelated
	claim happened to provoke the next `heroes` broadcast. Re-emitting the
	unchanged truth is the whole fix: the UI is a pure function of it plus this set.
	"""
	_push_captive_to_player(hero, held)
	heroes_changed.emit(_heroes, _pool)


func _reset_player_captives() -> void:
	"""
	Clear the local player's captive mirror, hero by hero through the same seam a
	liberation uses - so the tower's cell frames are repainted with it.

	Walks the PLAYER's own roster rather than `_pool`, because the pool is not
	known yet when this runs (the `heroes` frame follows `welcome`) and because it
	is the player's set that has to end up empty.
	"""
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("set_hero_captive"):
		return
	for entry: Variant in PLAYER_SCRIPT.CHARACTERS:
		player.call("set_hero_captive", String((entry as Dictionary).get("name", "")), false)


func _push_captive_to_player(hero: String, held: bool) -> void:
	"""
	Mirror one room-side change into the local player's own captive set.

	Null-safe and `has_method`-guarded like every other reach into the player here,
	so the manager keeps working in a scene with no player at all (every headless
	harness) and against a build whose player has not grown the set.
	"""
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_hero_captive"):
		player.call("set_hero_captive", hero, held)


func peer_positions() -> Variant:
	"""
	Where every OTHER member of the room last reported standing, or `null` when
	there is no room — the same "`null` means fall through to solo behaviour"
	shape `my_character_indices()` and `shared_bank()` use, so a caller needs one
	`== null` test and no branch of its own.

	`scripts/crocodile_lod_manager.gd` is the caller: a crocodile must be awake
	when it is near ANY member, not only near us. Offline this returns `null`, the
	manager's focus set stays the one-element `[player_pos]`, and its awake test is
	byte-for-byte the single-player one it has always been.

	Positions come from `_peer_state`, which the join snapshot seeds and every
	presence packet refreshes at 15 Hz — so a peer whose mesh has not come up yet
	simply is not in the set, which is the correct answer rather than a stale one.

	A peer whose mesh connection died while its lobby socket stayed up is marked
	`stale` by `_prune_dead_connections()` and skipped here: its last position is
	frozen and nobody is standing on it, so holding crocodiles awake around it
	would burn the pack on empty ground for the room's life.
	"""
	# MASTER ONLY, and that is a perf rule rather than a correctness one. The only
	# thing the union buys is that the master keeps awake every crocodile it has
	# to PUBLISH — `_send_croc_sync()` skips sleeping bodies, and it is the sole
	# consumer of that state. On a non-master the extra bodies woken are exactly
	# those >SIM_RADIUS from us and within it of a teammate: past our fog and past
	# VISUAL_CULL_DISTANCE, never sent to us either (the sync filters per peer by
	# THAT peer's position), so they simulate invisibly and authoritatively for
	# nobody — up to ~4x the pack in a spread-out four-player room, each body a
	# move_and_slide plus three avoidance raycasts per physics tick, on the
	# gl_compatibility web build this manager exists to protect.
	#
	# Safe in both directions: a remote-driven croc is skipped by the awake/asleep
	# decision anyway, and on promotion the union is back within one SCAN_INTERVAL
	# (0.11 s), two orders of magnitude inside CROC_SYNC_TIMEOUT (2 s).
	if _state != State.IN_ROOM or _master != _you:
		return null
	var positions: Array[Vector3] = []
	for state: Dictionary in _peer_state.values():
		if bool(state.get("stale", false)):
			continue
		positions.append(state["pos"] as Vector3)
	return positions


func nearest_member_position(from: Vector3) -> Variant:
	"""
	The closest OTHER member's last known position, or `null` when there is no
	room (or nobody else's presence has arrived yet) — the same "`null` means fall
	through to solo behaviour" shape `peer_positions()` above uses.

	`scripts/piglet_crocodile_ai.gd` is the caller, and it needs the *nearest one*
	rather than the whole array so its per-frame detection test allocates nothing.
	Why it needs it at all: in a room the master simulates every awake crocodile
	for everybody, and by the isolation contract a remote peer is a `RemoteAvatar`
	in NO group — so a crocodile resolving "the player" through
	`get_nodes_in_group("player")` can only ever hunt whoever happens to be
	master, and every other peer walks through the pack untouched.

	Skips `stale` peers for the same reason `peer_positions()` does — a whole pack
	hunting a coordinate nobody is standing on is worse than not hunting at all.

	**SKIPS AIRBORNE PEERS TOO, and that is the point of bead godot-test1-s86.15.**
	"Jumping breaks the scent" is a real escape hatch in this game — the local
	player is only a candidate in `piglet_crocodile_ai._update_chase_state()`
	while `is_on_floor()` — and presence has always carried the on-floor bit as
	`g`, but this function ignored it, so the hatch worked solo and against your
	own crocodiles and silently did nothing for a REMOTE member. On the master,
	which simulates the pack for everybody, that meant a teammate could jump all
	day and still be hunted on every screen. The bit lives in `_peer_state` as
	`floor` (see `_receive_state` / the presence drain).

	**A peer whose presence has not arrived yet counts as GROUNDED.** The join
	snapshot carries no `g` field — it is a position and a set of counters, not a
	pose — so `floor` defaults true and the behaviour up to the first presence
	packet (66 ms) is exactly what it was. Defaulting the other way would make
	every joiner briefly unsmellable, which is a stealth exploit rather than a
	conservative default.

	`peer_positions()` deliberately does NOT take the same test: that one is the
	LOD manager's awake set, and a crocodile standing next to a jumping teammate
	must stay simulated — it is about coverage, not about scent.
	"""
	if _state != State.IN_ROOM:
		return null
	var best: Variant = null
	var best_dist_sq: float = INF
	# Iterated by key, NOT through `.values()`: that builds a fresh Array on every
	# call, and this runs once per awake crocodile per physics frame — on the
	# master, the union of every member's 45 m sphere. The docstring's "allocates
	# nothing" is the contract; keep it true.
	for peer: String in _peer_state:
		var state: Dictionary = _peer_state[peer]
		if bool(state.get("stale", false)):
			continue
		if not bool(state.get("floor", true)):
			continue  # Mid-jump: no scent, exactly as for the local player.
		var pos: Vector3 = state["pos"] as Vector3
		var dist_sq: float = from.distance_squared_to(pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = pos
	return best


func remote_avatars() -> Array:
	"""
	All active RemoteAvatar children for peers in the room.
	Read by piglet_crocodile_ai to evaluate giant fear across all room members (Codex P1).
	"""
	if _state != State.IN_ROOM:
		return []
	return _avatars.values()


static func peer_color(peer_id: String) -> Color:
	"""
	The colour a given peer is drawn in, ANYWHERE it is drawn. A pure function of
	the lobby id, so the minimap dot and the locator marker for one teammate are
	the same colour without either surface telling the other anything — and the
	colour survives a master migration, a rejoin and a hero swap, because none of
	those change the id.

	Static on purpose: it needs no room and no manager, so a HUD can colour a peer
	from a join snapshot, and `mp_selfcheck.gd` can pin its stability without a
	socket. `String.hash()` is the same 32-bit hash `croc_id_for()` leans on; here
	only its distribution matters (a collision means two teammates share a hue,
	which is a legibility annoyance, not a correctness bug), so no sign extension
	is needed — the modulo of an unsigned value is already in range.
	"""
	var hue := float(peer_id.hash() % PEER_HUE_STEPS) / float(PEER_HUE_STEPS)
	return Color.from_hsv(hue, PEER_COLOR_SATURATION, PEER_COLOR_VALUE)


func peer_markers() -> Variant:
	"""
	Every OTHER member of the room as `{"id": String, "pos": Vector3, "color":
	Color}`, or `null` when there is no room — the same "`null` means fall through
	to solo behaviour" shape `peer_positions()` and `shared_bank()` use, so a HUD
	needs one `== null` test and no branch of its own.

	WHY THIS EXISTS BESIDE `peer_positions()`, which looks like the same query:
	that one is deliberately MASTER-ONLY (see its comment — waking crocodiles for
	the whole room is a cost only the master gets anything back for) and hands out
	bare positions with no ids. A locator bar on a non-master would therefore
	show nothing at all, and neither surface could colour a peer stably. This one
	answers for every member of the room, and carries the id and its colour.

	It ALLOCATES (one array, one small dictionary per peer), which is why it is
	documented for HUD tick rates — the two callers ask at 5 Hz — and why
	`nearest_member_position()` still exists for the per-physics-frame crocodile
	query that must allocate nothing. Do not call this per frame.

	`stale` peers are skipped for the reason the two siblings skip them: their
	position is frozen and nobody is standing on it, so a marker there points at
	empty ground.
	"""
	if _state != State.IN_ROOM:
		return null
	var markers: Array[Dictionary] = []
	for peer: String in _peer_state:
		var state: Dictionary = _peer_state[peer]
		if bool(state.get("stale", false)):
			continue
		markers.append({
			"id": peer,
			"pos": state["pos"] as Vector3,
			"color": peer_color(peer),
		})
	return markers


func my_character_indices() -> Variant:
	"""
	Which `CHARACTERS` entries this peer may embody, or `null` meaning "all of
	them" — the solo semantics, which is also what an offline peer and a peer
	holding no hero get. `player_controller.switch_to_next_character()` therefore
	keeps its existing behaviour behind a single `== null` test.

	The lobby holds at most one hero per member, so in practice this is a
	singleton and the E-cycle degenerates to a no-op; the set form costs nothing
	and needs no special case if that ever changes.
	"""
	if _state != State.IN_ROOM:
		return null
	var indices: Array[int] = []
	for hero: String in _heroes:
		if str(_heroes[hero]) != _you:
			continue
		var index: int = hero_index(hero)
		if index >= 0:
			indices.append(index)
	# Holding nothing — or only heroes this build has no character for — means
	# UNRESTRICTED, not frozen: locking E against an empty set would be a worse
	# answer than solo behaviour to a state that is normally momentary (the gap
	# between `welcome` and our auto-claim being confirmed).
	if indices.is_empty():
		return null
	return indices


static func hero_index(hero: String) -> int:
	"""
	The `player_controller.CHARACTERS` index of a hero name, or -1 if this build
	has no such character. Static and pure so scripts/mp_selfcheck.gd can pin it.
	"""
	var characters: Array = PLAYER_SCRIPT.CHARACTERS
	for i: int in range(characters.size()):
		if str((characters[i] as Dictionary).get("name", "")) == hero:
			return i
	return -1


func _on_lobby_heroes(heroes: Dictionary, pool: Array) -> void:
	"""
	The lobby published the room's hero assignments — from `welcome`, or from any
	later claim, release or departure (the lobby releases a leaver's hero itself,
	which is why nothing here does).
	"""
	if _state != State.IN_ROOM:
		return

	# The lobby is our own server, but this is still parsed JSON: keep both sides
	# of the mapping strings so `hero_holder()` can never hand back a float.
	_heroes = {}
	for hero: Variant in heroes:
		_heroes[str(hero)] = str(heroes[hero])
	# ...and REMEMBER every holder the lobby has ever named, which is what a capture
	# is authorized against. Written here and cleared only by `leave()`: a release
	# must not erase it, or the reassignment a capture provokes would revoke that
	# capture's own authorization mid-flight. An empty holder is not a holder.
	for hero: String in _heroes:
		if not String(_heroes[hero]).is_empty():
			_last_holder[hero] = String(_heroes[hero])
	_pool = []
	for hero: Variant in pool:
		_pool.append(str(hero))

	heroes_changed.emit(_heroes, _pool)
	_apply_my_hero()
	_auto_claim_hero()


func _apply_my_hero() -> void:
	"""
	Put the local player in the body the lobby says we hold.

	**Routed through `set_active_character()`, never by poking
	`current_character_index`.** That setter is what frees the old model,
	instances the new one, clears Teibi's resize state, re-runs `_apply_view_mode()`
	and restores the rest pose — writing the index alone leaves the player wearing
	the wrong body with the right number.
	"""
	var hero: String = my_hero()
	if hero.is_empty():
		return
	var index: int = hero_index(hero)
	if index < 0:
		return  # A hero the lobby offers that this build has no character for.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("set_active_character"):
		return
	if "current_character_index" in player and int(player.get("current_character_index")) == index:
		return
	player.set_active_character(index)


func _auto_claim_hero() -> void:
	"""
	Claim a hero as soon as the pool is known, so nobody has to open the panel to
	end up a distinct character. Preference is the body the player is already in;
	if somebody else holds it, take the first hero nobody holds.

	AT MOST ONE CLAIM PER `heroes` FRAME, and never a loop: the lobby answers a
	claim with another `heroes` broadcast, so retrying in place would be a claim
	storm. Losing the race just means the next broadcast lands us on the next free
	hero.

	IT WAITS FOR THE JOIN TO SETTLE, which is the whole of "a client never offers a
	captive hero" applied to the one claim nobody presses. `welcome` arrives before
	any snapshot, so `_captives` is empty on that frame and a joiner would happily
	take a hero the room has in a cell — briefly playing, in the field, a body every
	other screen shows locked up. `_join_settled()` is the condition the room's
	totals already wait on and it has a deadline of its own (`JOIN_SNAPSHOT_WAIT`),
	so a room whose snapshot never comes still gets a hero rather than none.
	Re-driven from `_receive_state()` and from that deadline, and idempotent, so
	whichever settles it also claims.
	"""
	if not my_hero().is_empty() or not _join_settled():
		return
	var free: Array[String] = available_heroes()
	if free.is_empty():
		return  # 4 heroes, 4-member cap — only reachable if the pool arrived empty.

	var wanted: String = ""
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and "current_character_index" in player:
		var index: int = int(player.get("current_character_index"))
		var characters: Array = PLAYER_SCRIPT.CHARACTERS
		if index >= 0 and index < characters.size():
			wanted = str((characters[index] as Dictionary).get("name", ""))
	claim_hero(wanted if free.has(wanted) else free[0])


# =============================================================================
# SIGNALLING — offers, answers, ICE candidates over the lobby's opaque relay
# =============================================================================

func _add_peer(id: String, peer_name: String) -> void:
	"""
	Open a WebRTC connection to one peer and give it an avatar.

	**Glare-free offer rule:** the peer whose lobby id string sorts LOWER creates
	the offer; the other one waits for it. Both sides know both ids the moment
	they learn about each other, so this needs no negotiation round trip and can
	never produce the classic glare where both ends offer at once and both
	connections collapse.

	`add_peer()` is called BEFORE `create_offer()` on purpose:
	`WebRTCMultiplayerPeer` creates its data channels inside `add_peer`, and they
	have to exist before the offer that describes them is generated.
	"""
	if _rtc == null or _connections.has(id):
		return

	var conn: WebRTCPeerConnection = WebRTCPeerConnection.new()
	if conn.initialize(_ice) != OK:
		status.emit("WebRTC unavailable — see README for the desktop addon")
		# Drop anything buffered for a peer we will never connect: nothing replays
		# it, and every later relay from that peer keeps appending until
		# MAX_BUFFERED_SIGNALS, warning once per candidate for the room's life.
		_pending_signals.erase(id)
		return

	conn.session_description_created.connect(_on_session_description_created.bind(id))
	conn.ice_candidate_created.connect(_on_ice_candidate_created.bind(id))

	if _rtc.add_peer(conn, MpCodec.peer_int_id(id)) != OK:
		# Close the half-built connection rather than leaving it alive with its
		# signals still bound to us, relaying candidates for a peer we dropped.
		conn.close()
		status.emit("Could not add %s to the mesh" % id)
		_pending_signals.erase(id)
		return

	_connections[id] = conn

	# The avatar exists from now on, but stays hidden until its first presence
	# packet — otherwise a nameplate hovers over the spawn point on a body that
	# has not told us where it is yet.
	var avatar: RemoteAvatar = RemoteAvatar.new()
	avatar.name = "Peer_%s" % id
	avatar.visible = false
	add_child(avatar)
	avatar.setup(peer_name)
	_avatars[id] = avatar

	if _you < id:
		conn.create_offer()

	# Anything this peer relayed before the connection existed is replayed now,
	# in arrival order (offer first, then its ICE candidates — which is the order
	# WebRTC requires). See `_buffer_signal()`.
	for payload: Dictionary in _pending_signals.get(id, [] as Array):
		_on_lobby_relay(id, payload)
	_pending_signals.erase(id)


func _on_session_description_created(type: String, sdp: String, id: String) -> void:
	"""
	Our own offer (we called `create_offer`) or our own answer (generated when we
	set a remote offer). Either way: adopt it locally, then relay it to the peer
	it belongs to.
	"""
	if not _connections.has(id):
		return
	(_connections[id] as WebRTCPeerConnection).set_local_description(type, sdp)
	_lobby.send_signal_to(id, {"mp": type, "sdp": sdp})


func _on_ice_candidate_created(media: String, index: int, candidate_name: String, id: String) -> void:
	"""One of our ICE candidates — relay it verbatim to the peer."""
	_lobby.send_signal_to(id, {
		"mp": "ice", "media": media, "index": index, "name": candidate_name
	})


func _on_lobby_relay(from: String, payload: Dictionary) -> void:
	"""
	A relayed payload from `from`. **This is a trust boundary** — the lobby never
	inspects payloads (that opacity is what keeps game logic off the server), so
	everything here is unvalidated peer input. Every field is type-checked before
	use and anything unexpected is dropped with a warning, never trusted.

	A payload with no `"mp"` key is silently ignored rather than warned about:
	later phases share this same relay, and refusing to choke on their traffic is
	what makes this client forward compatible.
	"""
	if not payload.has("mp"):
		return

	match str(payload["mp"]):
		"offer", "answer":
			if typeof(payload.get("sdp", null)) != TYPE_STRING:
				push_warning("MpManager: dropped %s with no sdp from %s" % [payload["mp"], from])
				return
			if not _connections.has(from):
				_buffer_signal(from, payload)
				return
			var conn: WebRTCPeerConnection = _connections[from]
			# Setting a remote OFFER makes the connection generate an answer,
			# which arrives back through `session_description_created` with
			# `type == "answer"` — so there is no separate create_answer() call.
			conn.set_remote_description(str(payload["mp"]), str(payload["sdp"]))
		"ice":
			if typeof(payload.get("media", null)) != TYPE_STRING \
					or typeof(payload.get("name", null)) != TYPE_STRING \
					or not MpCodec._is_number(payload.get("index", null)):
				push_warning("MpManager: dropped malformed ice candidate from %s" % from)
				return
			if not _connections.has(from):
				_buffer_signal(from, payload)
				return
			(_connections[from] as WebRTCPeerConnection).add_ice_candidate(
				str(payload["media"]), int(payload["index"]), str(payload["name"])
			)
		"seed":
			# ONLY the master hands out the world seed. The relay is opaque to
			# the lobby, so without this any member could race the master's
			# broadcast; `_receive_seed`'s `_has_seed` latch would then drop the
			# real seed and that peer walks a different world for the room's
			# life. `_master` is always current here — the lobby's `master`
			# frame reaches us before a re-elected master can rebroadcast.
			if from != _master:
				push_warning("MpManager: ignoring seed from non-master %s" % from)
				return
			_receive_seed(payload)
		"seed_req":
			# A peer that has not got the world seed asking us for it. The verb
			# IS the whole message — there are no payload fields, so there is
			# nothing to validate; that is why no check follows, rather than an
			# oversight at a trust boundary. A non-master has no answer to give.
			if _you != _master:
				return
			# Latches from our own terrain first if we never had one (the case
			# `_on_lobby_master_changed` used to leave open: a master elected
			# before the seed reached it), then answers the asker directly —
			# it already missed at least one broadcast, so a broadcast is no use,
			# and answering room-wide would let one peer's spam evict the others.
			_latch_seed_from_terrain()
			if _has_seed:
				_lobby.send_signal_to(from, {"mp": "seed", "seed": _room_seed})
		"hb":
			# The master's heartbeat. Accepted ONLY from the master, the same
			# rule (and for the same reason) as `seed`: the relay is opaque to
			# the lobby, so any member could otherwise forge beats and keep a
			# dead host in office forever. The verb IS the whole message — there
			# are no payload fields, so there is nothing to validate; that is why
			# no check follows, rather than an oversight at a trust boundary.
			if from != _master:
				return
			_last_hb_msec = Time.get_ticks_msec()
			# Both halves of the stall clock, not just the flag: a residual accumulator
			# left over from an episode that recovered makes the NEXT episode's first
			# vote fire early, before a full STALL_REPORT_INTERVAL of silence.
			_stall_accum = 0.0
			_stall_reported = false
		"cap":
			# A captive-set change from a peer whose mesh we have not finished
			# building — see `_publish_captive()` for why the relay carries this
			# one at all. SAME PARSER, SAME RULE, SAME FUNCTION as the mesh verb:
			# the transport changes and nothing else does, which is the only way
			# two transports for one fact stay honest. Rate-limited on the same
			# budget, because a relayed packet is peer input like any other.
			#
			# `c` arrives as a JSON bool here rather than a `var_to_bytes` one, and
			# `decode_captive()` demands TYPE_BOOL either way — JSON's `true` parses
			# to a real bool, so the same gate holds without a second spelling.
			if not _verb_rate_ok(from, "cap"):
				return
			_receive_captive(from, payload)
		"lmk":
			# A Budapest landmark claim from a peer whose mesh we have not finished
			# building — see `report_landmark_explored()` for why the relay carries
			# this one at all. SAME PARSER, SAME AUTHORITY CHECK, SAME FUNCTION as
			# the mesh verb, and rate-limited on the same budget, because a relayed
			# packet is peer input like any other.
			#
			# `i` arrives as a JSON number here rather than a `var_to_bytes` int, and
			# `decode_lmk()` demands TYPE_INT either way. JSON parses a whole number
			# to an int in Godot 4, so the same gate holds without a second spelling
			# — and a fractional one is a peer not speaking this protocol.
			if not _verb_rate_ok(from, "lmk"):
				return
			_receive_lmk(from, payload)
		"room":
			# The master's periodic truth, for a peer whose mesh is not up yet —
			# which is the whole reason this verb exists (see `_send_room_state`).
			# Same parser, same authority check, same function as the mesh arm.
			if not _verb_rate_ok(from, "room"):
				return
			_receive_room(from, payload)
		"state":
			# A join snapshot from an incumbent. THE THIRD TRUST BOUNDARY in
			# this file: `decode_state()` validates it whole, and anything that
			# fails any part of it is dropped whole.
			# One per sender for the room's life (see `_state_received`). A peer
			# that drops and reconnects gets a fresh lobby id, so this can never
			# refuse a snapshot the protocol actually wanted to send.
			if _state_received.has(from):
				return
			var snapshot: Dictionary = MpCodec.decode_state(payload)
			if snapshot.is_empty():
				push_warning("MpManager: dropped malformed state snapshot from %s" % from)
				return
			_state_received[from] = true
			_receive_state(from, snapshot)
		_:
			# An "mp" verb from a later phase. Ignore it, do not warn.
			pass


func _buffer_signal(from: String, payload: Dictionary) -> void:
	"""
	Hold an offer/candidate that arrived before we had a connection to `from`,
	for `_add_peer` to replay.

	THE WINDOW IS REAL, and dropping these is a connection that never forms.
	`_on_lobby_joined` cannot build the mesh straight away — it first has to
	fetch `/ice` over HTTP — while the lobby tells the peers already in the room
	about us *immediately*. Whichever of them sorts lower by the offer rule then
	offers at once, and over the internet that offer beats our `/ice` round trip
	roughly half the time. Nothing re-offers and nothing times out, so both sides
	would sit in a room showing each other's names with avatars that never
	appear. (On localhost `/ice` answers in ~1 ms, which is exactly why the
	documented dev recipe never reproduces it.)

	Bounded because this is peer input over an opaque relay: past
	`MAX_BUFFERED_SIGNALS` the peer is not racing us, it is flooding us.
	"""
	if _state != State.IN_ROOM:
		return
	var queued: Array = _pending_signals.get(from, [] as Array)
	if queued.size() >= MAX_BUFFERED_SIGNALS:
		push_warning("MpManager: dropping relayed signal from %s — buffer full" % from)
		return
	queued.append(payload)
	_pending_signals[from] = queued


# =============================================================================
# WORLD SEED DISTRIBUTION
# =============================================================================
#
# The seed travels over the LOBBY RELAY, not over the mesh, and that is
# deliberate: it has to arrive before any data channel is open, because the
# joiner needs to regenerate its world at once rather than after ICE finishes.
# It is also tiny and sent about once per room, so the relay's cost is nothing.

func _broadcast_seed_if_master() -> void:
	"""
	If we are the room master, publish the world seed everyone will share.

	The master's own world is the reference: we read `run_seed` straight off the
	terrain instead of rolling a new one, so the master never has its own ground
	regenerated underneath it just because somebody joined.
	"""
	if _master != _you or _state != State.IN_ROOM:
		return

	# A RE-ELECTED master re-sends the seed it already adopted and never re-reads
	# the terrain (`_latch_seed_from_terrain` early-returns on `_has_seed`). The
	# two are normally the same value — `_receive_seed` set the terrain from
	# `_room_seed` — but the room's agreed seed is the authority here, not
	# whatever this peer's ground happens to be running on.
	_latch_seed_from_terrain()
	if _has_seed:
		_lobby.send_signal_to("", {"mp": "seed", "seed": _room_seed})


static func _should_noop_on_seed(adopted_seed: int, current_seed: int) -> bool:
	"""
	Pure seed-equality guard for the host no-op case (bead godot-test1-ank).

	Adopting a seed already ours changes nothing — no new_run, no
	reset_position, no explored_mask wipe. Guard on equality, not on
	"am I the master", so a peer that happens to hold same seed is also spared.
	Testable without a mesh: mp_selfcheck drives this directly.
	"""
	return adopted_seed == current_seed


func _latch_seed_from_terrain() -> void:
	"""
	Adopt our own terrain's `run_seed` as the room's, if we have not got one yet.

	Split out of `_broadcast_seed_if_master()` so the `seed_req` handler can latch
	WITHOUT broadcasting: answering a request room-wide turns one peer's message
	into N, and the relay payload is unvalidated peer input, so a member spamming
	`seed_req` would fill every other member's bounded lobby send queue and get
	them disconnected (`server/room.go` drops a peer that cannot drain).
	"""
	if _has_seed:
		return
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain == null or not ("run_seed" in terrain):
		return
	_room_seed = int(terrain.get("run_seed"))
	_has_seed = true


func _receive_seed(payload: Dictionary) -> void:
	"""
	Adopt the master's world seed: regenerate the terrain from it and put the
	local player back at spawn, so a joiner starts at the beginning of the shared
	world rather than at whatever coordinates its solo run had reached.

	That spawn reset is the path for a room with nothing to join yet. When a join
	snapshot has already told us where the group is standing, `_apply_join_placement()`
	takes over instead and the origin is never touched.

	JSON NUMBER GOTCHA: `JSON.parse_string` produces floats for every number, so
	`payload["seed"]` arrives as a `float`. `run_seed` comes from
	`RandomNumberGenerator.randi()` (0…2³²−1), which a double represents exactly,
	so the value round-trips without loss — but the `int()` cast below is
	**mandatory, not cosmetic**: passing the float straight through would make
	every downstream `hash(Vector3i(...))` see a different type.

	...and that cast is why `_is_number()` alone is NOT the check. It accepts any
	float, `1e999` is well-formed JSON that parses to `INF`, and `int(INF)` is
	undefined — on wasm the float→int trunc can trap the module. `MAX_RUN_SEED`
	is the same finite-and-bounded-before-any-cast rule `decode_state()` and
	`decode_presence()` already apply to every other number a peer sends; a
	master is only the oldest member of a room whose code is public over
	`/rooms`, so its `seed` is peer input like the rest.
	"""
	if _has_seed or not MpCodec._is_number(payload.get("seed", null)):
		return
	var raw_seed: float = float(payload["seed"])
	if not is_finite(raw_seed) or raw_seed < 0.0 or raw_seed > MAX_RUN_SEED:
		push_warning("MpManager: dropping out-of-range world seed")
		return
	_room_seed = int(raw_seed)
	_has_seed = true
	status.emit("Shared world seed received")

	# BUDAPEST IS UNEXPLORED IN A WORLD WE HAVE NOT WALKED. Adopting a foreign seed
	# is the one event that REPLACES this peer's world, and it is the single site
	# above all three branches below — the spawn reset, the mid-run rebuild and the
	# hand-over to `_apply_join_placement()`, only the first of which calls
	# `reset_position()`. Without it a peer carrying a finished solo mask wins
	# somebody else's run on its first `room` packet (codex review 2026-09-02). A
	# HOST never gets here, which is correct: its own run continues, seed and all.
	var seed_player: Node = get_tree().get_first_node_in_group("player")
	if seed_player != null and "explored_mask" in seed_player:
		# Don't wipe mask for same-seed rejoin (no world change) — guard here too
		var _mask_terrain: Node = get_tree().get_first_node_in_group("terrain")
		var _mask_cur: Variant = _mask_terrain.get("run_seed") if _mask_terrain != null else null
		if _mask_cur == null or not _should_noop_on_seed(_room_seed, int(_mask_cur)):
			seed_player.set("explored_mask", 0)

	# A MID-RUN JOINER MUST NOT BE RESET TO THE ORIGIN. Once a snapshot is in
	# hand the group's position is known, so hand straight over to the join
	# placement — it rebuilds the terrain around the anchor itself and must not
	# be preceded by a rebuild around (0,0) plus a teleport to spawn. The two
	# lines below stay the HOST / no-snapshot-yet path; a snapshot that arrives
	# after this calls `_apply_join_placement()` in its own turn.
	if _can_join_place():
		_apply_join_placement()
		return

	# Guard for same-room rejoin (review item 4) — same seed is no-op, but
	# placed BELOW the join hand-over so _apply_join_placement isn't skipped
	# for the reachable rejoin case. Host never reaches here today (welcome
	# latch at _on_lobby_joined sets _has_seed synchronously), but leave-and-
	# rejoin does. See review.
	var _rejoin_terrain: Node = get_tree().get_first_node_in_group("terrain")
	if _rejoin_terrain != null:
		var _cur2: Variant = _rejoin_terrain.get("run_seed")
		if _cur2 != null and _should_noop_on_seed(_room_seed, int(_cur2)):
			return

	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	var player: Node = get_tree().get_first_node_in_group("player")

	# A LATE SEED MUST NOT YANK A PLAYING PEER BACK TO SPAWN. The two lines below
	# are the host / nothing-to-join-yet path, where the player is standing on the
	# spawn point anyway and the reset is free. Once the arrival window has closed
	# they are neither: `reset_position()` teleports to the world origin AND wipes
	# the coins, distance and streak of a run in progress — which is what a peer
	# whose master was silent for the first few seconds used to get the moment that
	# master woke up. So outside the window we adopt the seed exactly the same way
	# and simply rebuild the world AROUND THE PLAYER instead of around chunk (0,0):
	# same shared world, no teleport, and still on solid ground the same frame
	# (`new_run`'s `around` floors that chunk plus ring 1 synchronously — the
	# guarantee a mid-run joiner already relies on).
	if not _arriving() and player != null and terrain != null \
			and terrain.has_method("new_run") and terrain.has_method("world_to_chunk"):
		terrain.new_run(_room_seed, terrain.world_to_chunk(player.global_position))
		return

	if terrain != null and terrain.has_method("new_run"):
		var _master_pos: Variant = null
		if _arriving() and _master != "" and _peer_state.has(_master):
			var _md: Dictionary = _peer_state[_master] as Dictionary
			if _md.has("pos") and _md["pos"] is Vector3:
				_master_pos = _md["pos"] as Vector3
		if _master_pos != null:
			var _master_anchor: Vector3 = _master_pos as Vector3
			terrain.new_run(_room_seed, terrain.world_to_chunk(_master_anchor))
			if terrain.has_method("build_ring_now"):
				terrain.build_ring_now(terrain.world_to_chunk(_master_anchor))
			await get_tree().physics_frame
			if _state != State.IN_ROOM:
				return
			if player != null:
				if player.has_method("join_at"):
					player.join_at(_master_anchor)
				elif "global_position" in player:
					player.global_position = Vector3(_master_anchor.x, 2.0, _master_anchor.z)
			return
		terrain.new_run(_room_seed)

	if player != null and player.has_method("reset_position"):
		player.reset_position()


# =============================================================================
# JOIN PLACEMENT — arrive beside the group, not at the world origin
# =============================================================================

func _arriving() -> bool:
	"""
	Whether this peer is still ARRIVING, i.e. whether a relay packet is still
	allowed to move the local player.

	This is the one-shot gate the placement is missing without it: `_join_applied`
	stops a SECOND placement, but nothing stopped the FIRST one from landing
	minutes into a run on whatever packet finally completed the condition. Both
	placement sites — the group pull in `_apply_join_placement()` and
	`_receive_seed()`'s teleport back to spawn — are gated on this, so a player who
	is alive and playing is never repositioned from the network. See
	`JOIN_PLACE_WINDOW` for the measured failure this closes and for the ceiling.
	"""
	return Time.get_ticks_msec() - _join_msec <= int(JOIN_PLACE_WINDOW * 1000.0)


func _can_join_place() -> bool:
	"""
	Whether a join placement is still owed: we joined a room that already had
	somebody in it, we have not placed yet, we are still ARRIVING (see
	`_arriving()` — placement belongs to the arrival, never to mid-run play), and
	both halves of what a placement needs — the world seed and at least one
	snapshot position — are in hand.
	"""
	if _join_applied or _first_member or not _has_seed or _peer_state.is_empty():
		return false
	if not _arriving():
		return false
	# ... and either every incumbent's snapshot is in, so the anchor is the whole
	# group's, or we waited long enough that a missing one is not coming. Counted
	# off `_state_received` (snapshots) rather than `_peer_state`, which presence
	# packets also fill — a peer whose mesh connected before its snapshot landed
	# would otherwise be counted as having sent one.
	return _state_received.size() >= _expected_snapshots or _join_wait >= JOIN_SNAPSHOT_WAIT


func _apply_join_placement() -> void:
	"""
	Drop this peer into the run beside the group, ONCE per room.

	Called from both `_receive_seed()` and `_receive_state()` because either can
	be the last piece to land, and guarded by `_can_join_place()` so whichever
	arrives second is the one that does the work.

	The terrain is rebuilt AROUND THE ANCHOR rather than around chunk (0,0):
	`new_run`'s `around` parameter puts the synchronously-floored safety ring where
	the player is about to stand, so a joiner does not spend a frame over unbuilt
	ground kilometres from the origin.

	...AND THEN, UNIQUELY ON THIS PATH, ITS CONTENT TOO. `update_chunks` only
	guarantees the ring's GROUND this frame; the blocks and crocodiles arrive over
	the following frames, which is fine for everyone who walks into fresh terrain
	and wrong for the one caller that INTERROGATES it: `join_at()` below probes
	~32 candidate spots against the physics space and then sweeps crocodiles off
	the winner. Against a ring that is still bare, every candidate reads clear and
	the sweep finds nothing, so the joiner can land inside a block that appears two
	frames later. `build_ring_now()` buys that ring up front — the same 9-chunk
	build this path paid before the ground/content split existed.
	"""
	if not _can_join_place():
		return
	_join_applied = true

	var anchor: Vector3 = _join_anchor()
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("new_run") and terrain.has_method("world_to_chunk"):
		terrain.new_run(_room_seed, terrain.world_to_chunk(anchor))
		if terrain.has_method("build_ring_now"):
			terrain.build_ring_now(terrain.world_to_chunk(anchor))

	# WAIT ONE PHYSICS FRAME BEFORE PLACING. We are on an idle frame (this whole
	# chain hangs off LobbyClient's `_process`), and `new_run()` has just freed
	# the old chunks — deferred to the end of the frame — and added the new ones,
	# neither of which the physics space knows about until it next steps. Placing
	# now would run `join_at`'s ~32 clear-spot probes against the OLD run's
	# geometry: every candidate judged on blocks that no longer exist, none on
	# the blocks that now do, and the joiner dropped inside one of them.
	# `_join_applied` was latched above, so nothing can re-enter across the await.
	await get_tree().physics_frame

	# The Leave button, a dropped socket or a lobby error can all land inside that
	# one-frame window. Teleporting a player into a room they are no longer in is
	# bad enough; `join_at` also zeroes their own contributions on the way, which
	# would silently wipe the solo run they just fell back to.
	if _state != State.IN_ROOM:
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("join_at"):
		player.join_at(anchor)

	status.emit("Joined the run at %dm" % int(anchor.x))


func _join_anchor() -> Vector3:
	"""
	Where to arrive: `_anchor_of()` over the JOIN SNAPSHOT positions, which is all
	a peer that has not seen a single presence packet yet has to go on.

	`_peer_state` holds only other members, and this is only reached with at
	least one entry in it, so `_anchor_of()`'s divide is safe. Stale entries are
	deliberately NOT skipped here (unlike `group_anchor()` below): during the
	arrival window nothing has had time to be pruned, and skipping is a behaviour
	change on a path the drag fix (bead godot-test1-s86.17) already pinned.
	"""
	var positions: Dictionary = {}
	for id: String in _peer_state:
		positions[id] = _peer_state[id]["pos"] as Vector3
	return _anchor_of(positions, _master)


func group_anchor() -> Variant:
	"""
	Where the group is standing RIGHT NOW, or `null` when there is no room and
	nobody to stand beside — the same "`null` means fall through to solo
	behaviour" shape `peer_positions()` and `shared_bank()` use, so the caller
	needs one `== null` test and no branch of its own.

	`player_controller._respawn_in_place()` is the caller (bead
	godot-test1-s86.18): dying in a room brings you back beside your team instead
	of alone at whatever end of the map the pack ran you down at — the same
	reason a mid-run joiner is placed at `_join_anchor()`. The anchor RULE is
	shared with the join (`_anchor_of()` is the one implementation of "centroid,
	unless the group is spread, then the master"); only the INPUT differs — this
	reads the LIVE presence positions, the join reads the one-shot snapshots.

	`stale` peers are skipped for exactly the reason `peer_positions()` skips
	them: a peer whose mesh died while its lobby socket stayed up holds a frozen
	coordinate nobody is standing on, and respawning onto that is strictly worse
	than respawning where you fell. An empty set answers `null`, never the origin.

	IT ONLY ANSWERS — no latch, no window, no side effect. The one-shot
	discipline the drag fix (bead godot-test1-s86.17) established stays where it
	belongs: this is read from the respawn EVENT, never from a packet arrival
	that happens to complete a condition, so there is nothing here to gate.
	"""
	if _state != State.IN_ROOM:
		return null
	var positions: Dictionary = {}
	for id: String in _peer_state:
		if bool((_peer_state[id] as Dictionary).get("stale", false)):
			continue
		positions[id] = _peer_state[id]["pos"] as Vector3
	if positions.is_empty():
		return null
	return _anchor_of(positions, _master)


static func _anchor_of(positions: Dictionary, master_id: String) -> Vector3:
	"""
	The group's anchor over a NON-EMPTY `lobby id -> Vector3` map: the centroid,
	unless somebody is further than `GROUP_SPREAD_MAX` from it, in which case a
	real player's position — the centroid of two players who have gone opposite
	ways is empty ground between them, and standing beside one player beats
	standing beside none. `master_id` is the preferred pick when the group is
	spread, because it is the one member every peer agrees on.

	**A SPREAD GROUP NEVER FALLS BACK TO THE CENTROID.** `master_id` can be
	missing from the map two ways — a master that has not reported yet or has
	gone `stale`, and (the one `group_anchor()` hits) a **dying master**, whose
	own position is never in `_peer_state` at all, since that dictionary holds
	only OTHER members. Returning the centroid there would put exactly the anchor
	rule's stated failure back: the master respawning onto empty ground between
	two teammates who went opposite ways. So the fallback is the live position
	NEAREST the centroid — still a real player, still deterministic, and still
	the most central one.

	Static and `_rtc`-free, so `mp_selfcheck.gd` can pin it; callers guarantee a
	non-empty map, so the divide is safe.
	"""
	var centroid: Vector3 = Vector3.ZERO
	for id: String in positions:
		centroid += positions[id] as Vector3
	centroid /= float(positions.size())

	for id: String in positions:
		if (positions[id] as Vector3).distance_to(centroid) > GROUP_SPREAD_MAX:
			if positions.has(master_id):
				return positions[master_id] as Vector3
			var nearest: Vector3 = centroid
			var best_sq: float = INF
			for other: String in positions:
				var pos: Vector3 = positions[other] as Vector3
				var dist_sq: float = pos.distance_squared_to(centroid)
				if dist_sq < best_sq:
					best_sq = dist_sq
					nearest = pos
			return nearest
	return centroid


# =============================================================================
# JOIN-TIME STATE REPLAY
# =============================================================================
#
# A peer joining a game already in progress has to be told what it missed: which
# coins are gone, how much the room has banked, how far it has run, and where
# everybody is standing. That rides the LOBBY RELAY
# for the same reason the seed does — it must be usable BEFORE any data channel
# opens, and ICE takes seconds — and it is sent exactly once per
# (incumbent, joiner) pair, so the relay carries at most three of these a join.
#
# Presence (below) keeps the counters current afterwards; this only bootstraps.

func _send_state_to(id: String) -> void:
	"""
	Send this peer's own contribution to a peer that has just joined.

	ABSOLUTE VALUES, never deltas — a joiner has exactly one chance to hear this,
	so nothing here may depend on having heard anything earlier.
	"""
	if _state != State.IN_ROOM or _lobby == null:
		return

	var player: Node = get_tree().get_first_node_in_group("player")
	var pos: Vector3 = Vector3.ZERO
	var coins: int = 0
	var dist: int = 0
	if player != null:
		pos = player.global_position
		# `own_coins` is this peer's OWN contribution, which is what the room
		# sums; `coins_collected` is the DISPLAYED number and in a room that is
		# already the room's total, so it must not be read here. The `in` guards
		# are the ones `_send_presence()` uses, for the same reason: a player
		# scene run standalone still answers something sane.
		coins = int(player.get("own_coins")) if "own_coins" in player else 0
		dist = int(player.get("run_distance")) if "run_distance" in player else 0

	_lobby.send_signal_to(id, {
		"mp": "state",
		"cc": coins,
		# THE RETIRED HEART COUNTERS, SENT AS INERT ZEROES FOR ONE RELEASE, and this
		# is the send-side half of the tolerance `decode_state()` states below it.
		# Hearts are gone (bead godot-test1-0bc) and no build reads these any more —
		# but the PREVIOUS build REQUIRES `ls`, and drops a snapshot without it
		# whole. `build_version` deliberately refuses to reload a peer that is
		# mid-run or in a room, so an old client outlives the deploy, and dropping
		# its one and only snapshot would cost it this peer's position, collected-coin
		# ids, kill list and frozen bank for the room's whole life. Delete both keys
		# once no pre-godot-test1-0bc client can still be running.
		"ls": 0,
		"gs": 0,
		"dd": 0,
		"px": pos.x,
		"py": pos.y,
		"pz": pos.z,
		# The FROZEN share of members who left before the joiner arrived. Presence
		# only ever carries a live member's own numbers, so without this the
		# joiner's `shared_bank` would be short by exactly `_gone_coins` for the
		# room's life — a permanently smaller bank than everyone else is looking at.
		"gc": _gone_coins,
		"ids": _recent_collected_ids(),
		# The room's KILL LIST, replayed for the same reason `ids` is: a joiner's
		# own terrain generates every crocodile the seed describes, including the
		# ones giant Teibi already crushed, so without this the newcomer walks into
		# a pack containing animals nobody else can see. Bounded like `ids`.
		"dead": _recent_dead_ids(),
		# THE CAPTIVE SET, absolute and never a delta - a joiner hears this once.
		# The WHOLE room's set, which only the master's copy is honoured (see
		# `_receive_state`): a live `cap` is authorized by the lobby saying the
		# sender holds that hero, and a capture whose loser has since been
		# reassigned has no such holder left to prove it, so a replay cannot be
		# authorized the same way.
		"cap": captive_heroes(),
		# BUDAPEST'S EXPLORED SET, absolute and never a delta — the `cap` rule, and
		# honoured from the MASTER alone for a simpler version of `cap`'s reason: a
		# live `lmk` authorizes itself by the sender's own published position, and a
		# replay has no position left to check, so the room's own authority is the
		# only honest source. `lm`, not `m`: this snapshot already spends `dd` and
		# `gc` on two-letter counters and a one-letter key beside them reads as a
		# typo.
		"lm": _explored_mask,
	})


func _recent_collected_ids() -> Array:
	"""
	The collected-coin ids to replay: MOST RECENT FIRST, capped at
	`MAX_STATE_IDS` — the same cap `decode_state()` enforces on the way in.

	ponytail: a long enough run overflows the cap and the OLDEST ids are the ones
	dropped. The ceiling is one already-taken coin reappearing kilometres behind
	the group, in chunks nobody is near and the joiner's terrain will not even
	have built. The upgrade path is filtering by distance to the join anchor
	rather than by age, which needs the anchor to be known before the send.
	"""
	var ids: Array = _collected_ids.keys()
	ids = ids.slice(maxi(0, ids.size() - MpCodec.MAX_STATE_IDS))  # keep the newest tail
	ids.reverse()  # ... most recent first
	return ids


func _recent_dead_ids() -> Array:
	"""
	The crushed-crocodile ids to replay, MOST RECENT FIRST and capped at
	`MAX_STATE_IDS` — the same shape, and the same cap, as
	`_recent_collected_ids()`, because the joiner-side parser bounds both with it.

	ponytail: the cap is shared rather than a `dead`-specific constant because the
	two lists are the same kind of thing and one number is one number to keep in
	step. The ceiling is the collected set's, one class quieter: a room that
	crushes more than `MAX_STATE_IDS` crocodiles drops the OLDEST kills, so a
	joiner can see one alive again — kilometres behind the group, in a chunk its
	terrain will not even have built, and cosmetic when it does (a crocodile too
	many, never a wrong bank or a wrong shared total). Reaching that cap means
	2048 crushes in one room, each of which needs a player standing on a
	crocodile as giant Teibi. The upgrade path is `_recent_collected_ids()`'s:
	filter by distance to the join anchor rather than by age.
	"""
	var ids: Array = _dead_crocs.keys()
	ids = ids.slice(maxi(0, ids.size() - MpCodec.MAX_STATE_IDS))  # keep the newest tail
	ids.reverse()  # ... most recent first
	return ids


func _receive_state(from: String, snapshot: Dictionary) -> void:
	"""Merge one validated join snapshot. `snapshot` came from `decode_state()`."""
	_peer_state[from] = {
		"coins": snapshot["cc"],
		"dist": snapshot["dd"],
		"pos": snapshot["pos"],
		# GROUNDED UNTIL TOLD OTHERWISE. A snapshot is a position and a set of
		# counters, not a pose — there is no `g` in it — and the first presence
		# packet is 66 ms away. Defaulting an unknown pose to "airborne" would
		# make every incumbent briefly unsmellable to the joiner's crocodiles,
		# i.e. a stealth window, where defaulting to grounded is exactly the
		# behaviour that shipped. See `nearest_member_position()`.
		"floor": true,
	}
	# Adopt the room's frozen departed-member share with `maxi`, NOT `+=`: every
	# incumbent replays the same figure, so adding them would multiply it by the
	# number of snapshots received. `maxi` is also what keeps this correct once a
	# peer leaves AFTER we joined — we then fold that peer in ourselves, exactly
	# like the incumbents do, and the two paths converge on the same number.
	_gone_coins = maxi(_gone_coins, int(snapshot["gc"]))
	_absorb_collected(snapshot["ids"])
	# THE KILL LIST IS TAKEN FROM THE MASTER ALONE, and that asymmetry with `ids`
	# right above it is the point. The collected set is a UNION — each peer only
	# knows the coins it banked itself, so every incumbent's ids are needed and
	# every incumbent is entitled to assert them. A kill is the opposite: it is
	# ARBITRATED (`_resolve_kill` on the master, broadcast as `dead`), so every
	# member's `_dead_crocs` is already a copy of the master's one set and there
	# is nothing a non-master can add — while `_apply_dead` deletes a crocodile
	# permanently on this peer, which is exactly why `_receive_dead` accepts the
	# live verb from the master only. Honouring a stranger's list here would have
	# reopened that hole through the relay, which any room member can reach
	# (`GET /rooms` makes every code public).
	#
	# APPLYING THE SNAPSHOT'S WORLD-STATE DELTAS AT ALL IS THE JOIN EVENT ITSELF,
	# not a replay of somebody else's events: the `_state_received` latch above
	# admits exactly one snapshot per sender for the room's life, so neither sweep
	# can ever run a second time for the same peer.
	#
	# The cost of the rule is that a wedged or older-build master leaves the
	# joiner without a kill list — the same degradation its missing coin ids
	# already cause, and `JOIN_SNAPSHOT_WAIT` already refuses to strand the
	# joiner over it.
	if from == _master:
		_absorb_dead(snapshot["dead"])
	# THE CAPTIVE SET IS TAKEN FROM THE MASTER ALONE, the same rule as the kill list
	# right above it and for a related reason. A LIVE capture authorizes itself:
	# the lobby says the sender holds that hero. A REPLAY cannot - by then the loser
	# has usually been reassigned and holds something else, so there is no holder
	# left to check against - which leaves the room's own authority as the only
	# honest source. Same degradation as `dead`, too: a wedged or older-build master
	# leaves the joiner without the set, and every later `cap` still lands.
	if from == _master:
		for hero: Variant in snapshot.get("cap", []):
			var name: String = String(hero)
			if not _pool.has(name) or _captives.has(name):
				continue
			# THE SAME RELEASE GUARD THE LIVE VERB USES, and for the same reason one
			# step further out: a snapshot is a picture of the master's set when the
			# joiner arrived, and the rescuer's `cap` release can reach the joiner
			# first. Importing over it would resurrect a capture the whole room has
			# already forgotten, on the one peer that cannot tell.
			if Time.get_ticks_msec() - int(_released_msec.get(name, -RELEASE_GRACE_MSEC)) \
					< RELEASE_GRACE_MSEC:
				continue
			_captives[name] = true
			_captive_changed(name, true)
	# BUDAPEST'S EXPLORED SET, from the master alone — the captive set's authority
	# rule, and it needs none of the guards above it: the set is add-only, so a
	# snapshot that is a moment stale can only ever be a subset of the truth and
	# there is no release for it to resurrect over. Unconditional (a peer on an
	# older build decodes to 0 and ORs to nothing) and re-drives the win check the
	# `_join_settled()` gate has been deferring — which is precisely the gate this
	# snapshot is what closes.
	# The snapshot may be the last thing the placement was waiting on (the seed
	# can equally well be). Both call in; the latch inside decides.
	_apply_join_placement()
	# BUDAPEST'S EXPLORED SET, AFTER THE PLACEMENT AND NOT BEFORE (codex review
	# 2026-09-02). This snapshot can be the frame that makes `_join_settled()` true
	# AND the frame that carries eighteen landmarks, so applied above the placement
	# it opens the victory screen synchronously — and `join_at()` then reads that as
	# a pre-join game over and hides it, only for the next `room` packet to raise it
	# again half a second later. Placed here the joiner is put down first and the
	# win lands once, on a body that is already standing where the room is.
	if from == _master:
		_apply_explored(int(snapshot.get("lm", 0)))
	# ...and the last thing the AUTO-CLAIM was waiting on, for the reason in
	# `_auto_claim_hero()`: this snapshot is where a joiner learns which heroes are
	# in a cell, and claiming before it lands is claiming one of them.
	_auto_claim_hero()


func _absorb_collected(ids: Array) -> void:
	"""
	Fold somebody else's collected-coin ids into ours AND sweep the live world.

	THE SWEEP IS WHAT MAKES ORDERING IRRELEVANT. A snapshot landing after the
	terrain was already built despawns the coins it names right here, and a coin
	spawned after the snapshot asks `is_coin_collected()` in its own `_ready()`
	and frees itself — so the seed and the snapshots may arrive in either order
	and neither has to wait on the other.

	CHESTS ARE SWEPT BY THE SAME PASS, and that is the whole of the "a chest
	somebody else emptied still stands and pays nothing" fix. A chest's id IS a
	coin id (`treasure_chest.gd` latches `Coin.id_at(global_position)`), so its
	id already rode the snapshot's `ids` and already rides every `cnf` confirm —
	the only thing missing was that this sweep walked the `"coin"` group and a
	chest is not in it. It is in `"chest"`, hence the second loop, and fixing it
	HERE rather than at the join covers the live case too: a teammate emptying a
	chest mid-run now spends our copy of it the moment the confirm lands, not
	just for a peer who happens to join afterwards.
	"""
	var fresh: Dictionary = {}
	for id: int in ids:
		if _collected_ids.has(id):
			continue
		_collected_ids[id] = true
		fresh[id] = true
	if fresh.is_empty():
		return
	for coin: Node in get_tree().get_nodes_in_group("coin"):
		if coin.has_method("coin_id") and fresh.has(coin.coin_id()):
			coin.queue_free()
	for chest: Node in get_tree().get_nodes_in_group("chest"):
		if chest.has_method("chest_id") and fresh.has(chest.chest_id()):
			# NOT queue_free() — a chest mid-burst is paying out an award the room
			# already priced, and freeing it would cut that short. The chest owns
			# that decision; see `treasure_chest.consume_silently()`.
			chest.consume_silently()


func _absorb_dead(ids: Array) -> void:
	"""
	Fold the room's kill list into ours AND sweep the live world, the exact shape
	`_absorb_collected()` uses one thing over — including the reason for the
	shape: a joiner's snapshot may land before or after its terrain built the
	chunk holding a crushed crocodile, and this covers the "after" while
	`piglet_crocodile_ai._ready()`'s `is_croc_dead()` check covers the "before".

	ONE group walk for the whole list, never one per id. `_apply_dead()` is the
	single-id path and rebuilds the id cache on a miss, which is right for the one
	kill it handles and quadratic here — a joiner's list is mostly ids naming
	crocodiles in chunks this peer has not built, i.e. mostly misses.
	"""
	var fresh: Dictionary = {}
	for id: int in ids:
		if _dead_crocs.has(id):
			continue
		_dead_crocs[id] = true
		fresh[id] = true
	if fresh.is_empty():
		return
	for croc: Node in get_tree().get_nodes_in_group("crocodile"):
		if not croc.has_method("croc_id"):
			continue
		var id: int = croc.croc_id()
		if not fresh.has(id):
			continue
		# Same bookkeeping drop as `_apply_dead()`: a dead crocodile is nobody's to
		# drive, and the cache holds a hard reference to a node about to free itself.
		_synced_crocs.erase(id)
		_croc_seen.erase(id)
		if croc.has_method("squash_and_die"):
			croc.squash_and_die()


func is_coin_collected(id: int) -> bool:
	"""
	True when somebody in this room has already banked the coin with this id.

	`coin.gd` asks this once per coin at spawn through the `"mp"` group. Offline
	the set is empty and the answer is always false, so a solo coin is never
	removed and the cost is one failed group lookup per coin — paid at spawn,
	never per frame.
	"""
	return _state == State.IN_ROOM and _collected_ids.has(id)


func report_coin_collected(id: int) -> void:
	"""
	Record a local pickup so a peer joining later has it replayed.

	OFFLINE THIS IS A NO-OP, deliberately: solo play must allocate nothing here,
	and without the guard the set would grow for every coin of every solo run in
	the session. `leave()` empties it.
	"""
	if _state != State.IN_ROOM:
		return
	_collected_ids[id] = true


# =============================================================================
# SHARED TOTALS
# =============================================================================
# The room's bank and distance are the SUM (or, for distance, the max) of every
# member's own contribution, with no authority and no round trips: each peer
# broadcasts its own absolute numbers and each peer adds them up. Every reader
# gets the same answer within one presence interval, and a peer that leaves has
# its share frozen rather than dropped.
#
# Both take the CALLER's own contribution as a parameter and return `null`
# offline, so the player falls through to today's solo behaviour with one
# `== null` test and the manager never has to reach into the player.

# THERE IS NO "retired contribution" HERE, and that is deliberate. "Play Again"
# inside a room LEAVES the room first (see `player_controller.restart_game`), so
# this peer's contribution is always simply its live `own_coins`, and a restart
# never has to be hidden from the room's totals.

func _contributing() -> bool:
	"""
	Whether this peer's own coins and distance belong in the room's totals yet.

	A MID-RUN JOINER'S SOLO TALLY IS NOT THE ROOM'S. `join_at()` zeroes
	`own_coins` / `own_distance` / `run_distance` for exactly that reason — but it
	only runs at PLACEMENT, which waits on the seed and on every incumbent's
	snapshot, while presence starts the moment the mesh connects. Nothing orders
	those two, so without this gate a joiner publishes its old world's numbers in
	the window between: `dd` is folded in with `maxi`, so a 3 km solo run raises
	the room's distance PERMANENTLY for everyone (a max has no way back down), and
	`cc` credits the room's bank with coins nobody in it ever picked up.

	Zeroing at `welcome` instead would not work: `run_distance` is recomputed as
	`maxi(run_distance, int(global_position.x))` every physics tick, so it climbs
	straight back while the player is still standing in the solo world.

	A host contributes from the start — `_first_member` means there was no run to
	join, and its own tally IS the room's opening balance.
	"""
	return _first_member or _join_applied


func _join_settled() -> bool:
	"""
	Whether the room's totals can be trusted yet.

	A joiner is IN_ROOM from the `welcome` frame, but `_peer_state` fills one
	relayed snapshot at a time, so a HALF-ARRIVED SET IS NOT A PARTIAL TOTAL: it
	is a bank and a distance missing whole members, and the room's HUD would show
	them climbing as the snapshots land. The placement that settles it waits on
	the seed, so a joiner still waiting sits there for the whole 20 s `seed_req`
	budget, or forever if the seed never lands.

	Until this is true the two getters below answer `null` and the player falls
	through to solo semantics on the `== null` test it already makes. Same
	condition `_can_join_place()` uses, minus the seed: the totals become readable
	as soon as the SNAPSHOTS are in (or their deadline is spent), whether or not a
	world has arrived to place into.
	"""
	return _first_member or _join_applied \
		or _state_received.size() >= _expected_snapshots or _join_wait >= JOIN_SNAPSHOT_WAIT


func shared_bank(own_coins: int) -> Variant:
	"""The room's banked coins, or `null` offline / before the join settles."""
	if _state != State.IN_ROOM or not _join_settled():
		return null
	var total: int = (own_coins if _contributing() else 0) + _gone_coins
	for state: Dictionary in _peer_state.values():
		total += int(state.get("coins", 0))
	return total


func shared_distance(own_distance: int) -> Variant:
	"""
	The furthest anyone in the room has got, or `null` offline.

	A max, so feeding it back into the player's own running max cannot inflate it
	— which is also why a departed peer needs no frozen accumulator: whatever it
	reached was already folded in while it was here.

	`null` offline, and while the join is still settling (see `_join_settled`).
	"""
	if _state != State.IN_ROOM or not _join_settled():
		return null
	var best: int = own_distance if _contributing() else 0
	for state: Dictionary in _peer_state.values():
		best = maxi(best, int(state.get("dist", 0)))
	return best


# =============================================================================
# PER-FRAME: PRESENCE SEND + RECEIVE
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.OFFLINE:
		return

	# Runs BEFORE the `_rtc` guard on purpose: the seed travels over the lobby
	# relay, so a room whose mesh never built (or was never asked for) must still
	# be able to self-heal a missing world.
	_tick_seed_request(delta)
	_tick_join_wait(delta)
	# Also ABOVE the `_rtc` guard: a claim parked when the mesh was alive must
	# still run its retry budget down and resolve locally if the mesh dies, or the
	# player would have watched a coin vanish and pay nothing.
	_tick_claims(delta)
	# ALSO above the `_rtc` guard, and that is the whole point of putting the
	# heartbeat on the relay — see the section comment on `_tick_heartbeat`.
	_tick_heartbeat(delta)
	_tick_stall_watch(delta)
	# ABOVE THE `_rtc` GUARD like the three above it: a mesh that dies (or was
	# never built) must still be able to RELEASE a pause we are holding, and the
	# game-over exemption inside is a moving condition that has to be re-asked
	# every frame — `mp_ui._apply_pause`'s reason, one node along.
	_apply_remote_pause()
	# The room's captive set, slower still — and ABOVE THE `_rtc`
	# GUARD, which is half the point of this publish: the LOBBY RELAY leg reaches peers whose
	# mesh has not come up (and every peer of a `--lobby-only` master, whose mesh
	# never will). Below the guard it would be silent in exactly the case it exists
	# for. Master-only inside, so a non-master pays one float add and a comparison.
	_room_accum += delta
	var room_interval: float = 1.0 / ROOM_SYNC_HZ
	if _room_accum >= room_interval:
		_room_accum = fmod(_room_accum, room_interval)
		_send_room_state()
		_tick_landmark_claims()

	if _rtc == null:
		return

	# The mesh is a plain PacketPeer here — nobody else polls it for us, because
	# it was deliberately never handed to the global MultiplayerAPI.
	_rtc.poll()
	_prune_dead_connections()
	_receive_mesh_packets()

	_send_accum += delta
	var interval: float = 1.0 / PRESENCE_HZ
	if _send_accum >= interval:
		_send_accum = fmod(_send_accum, interval)
		_send_presence()

	# The crocodile sync runs on its own, slower accumulator. The master sends;
	# everybody else watches the clock on what it last sent them.
	_croc_accum += delta
	var croc_interval: float = 1.0 / CROC_SYNC_HZ
	if _croc_accum >= croc_interval:
		_croc_accum = fmod(_croc_accum, croc_interval)
		if _master == _you:
			_send_croc_sync()
			# The migrating herd rides the same tick and needs no timeout branch
			# of its own: a peer that stops hearing about a herd frees it from
			# `fauna_manager` itself (REMOTE_HERD_TIMEOUT), which is the one test
			# that also covers a master change, a leave and no MP node at all.
			_send_herd_sync()
		else:
			_tick_croc_timeout()



func _tick_join_wait(delta: float) -> void:
	"""
	Run the join-placement deadline.

	`_apply_join_placement()` is otherwise only called when a seed or a snapshot
	arrives, so a room where the last snapshot never comes has nothing left to
	re-trigger it and the joiner would stand at the origin for the room's life.
	This is the only thing that fires that case. It stops the moment the placement
	is applied (`_join_applied`), so it costs one float add per frame for at most
	`JOIN_SNAPSHOT_WAIT` seconds, once per room, and nothing at all for a host.
	"""
	if _state != State.IN_ROOM or _join_applied or _first_member:
		return
	if _join_wait >= JOIN_SNAPSHOT_WAIT:
		return  # Deadline already spent; the attempt below has run at least once.
	_join_wait += delta
	if _join_wait >= JOIN_SNAPSHOT_WAIT:
		_apply_join_placement()
		# The same deadline releases the auto-claim: a room whose snapshots never
		# arrive must still hand this player a hero. See `_auto_claim_hero()`.
		_auto_claim_hero()


func _tick_seed_request(delta: float) -> void:
	"""
	Ask the master for the world seed until it arrives — the second, independent
	belt against the bug `_on_lobby_joined`'s early latch fixes at the source.

	Both belts stay. The ordering fix removes the known way the direct send got
	skipped; this one covers every unknown way a single relayed message can go
	missing (a master mid-election, a frame lost while its socket reconnected, a
	peer that joined during the master's own boot). One retry loop is cheaper
	than a class of silent failures where the UI reports a healthy room.
	"""
	if _state != State.IN_ROOM or _has_seed or _master == _you or _master.is_empty():
		return
	if _seed_req_tries > SEED_REQUEST_MAX_TRIES:
		return  # Given up asking. We stay in the room; the player was told.

	_seed_req_accum += delta
	if _seed_req_accum < SEED_REQUEST_INTERVAL:
		return
	_seed_req_accum = 0.0
	_seed_req_tries += 1

	if _seed_req_tries > SEED_REQUEST_MAX_TRIES:
		# One past the budget: the give-up message, emitted exactly once because
		# the early return above catches every later tick.
		status.emit("No world from the host — is their tab still open?")
		return
	if _seed_req_tries == 1:
		# Make a silent failure visible. `mp_ui.gd` renders `status` straight
		# into the panel's label, so this needs no UI change.
		status.emit("Waiting for the shared world…")
	_lobby.send_signal_to(_master, {"mp": "seed_req"})


# =============================================================================
# HEARTBEAT, STALL DETECTION AND MASTER MIGRATION (phase 5)
# =============================================================================
#
# THE HEARTBEAT RIDES THE LOBBY RELAY, NOT THE MESH — a deliberate deviation
# from the epic's wording, for three reasons:
#
#   1. What this detects is a THROTTLED OR DEAD TAB, and such a tab stops
#      polling its socket and its mesh alike. Either transport detects it
#      equally well, so the choice is free on the merits and decided by the two
#      reasons below.
#   2. `--lobby-only` has no mesh at all. A mesh heartbeat would make the whole
#      migration path untestable headless, and `scripts/mp_e2e.sh` is where this
#      phase's automated evidence lives.
#   3. The cost is nothing: 1 Hz to at most three peers, on a socket that
#      already carries the lobby's own 20 s ping.
#
# The lobby already implements the re-election (`server/room.go`'s
# `ReportStalled` + `electLocked`), so no server code exists for this — a peer
# votes, and the lobby decides.

func _tick_heartbeat(delta: float) -> void:
	"""
	Say "still here" once per `HEARTBEAT_INTERVAL` while we are the master.

	Broadcast (`send_signal_to("")`) rather than addressed per peer: every member
	needs it, and the lobby fans one frame out for us. A room of one still beats —
	nobody is listening, but branching on the member count would only add a way
	for the first joiner's window to be silent.
	"""
	if _state != State.IN_ROOM or _master != _you or not heartbeat_enabled:
		return
	_hb_accum += delta
	if _hb_accum < HEARTBEAT_INTERVAL:
		return
	_hb_accum = 0.0
	_lobby.send_signal_to("", {"mp": "hb"})


func _tick_stall_watch(delta: float) -> void:
	"""
	Watch the master's beats and vote to depose it when they stop.

	The vote goes to the lobby, which counts it: a re-election happens only once
	strictly more than half of the non-master members agree, so one peer whose own
	connection is the broken one cannot depose a healthy host on its own. We keep
	voting every `STALL_REPORT_INTERVAL` until either a `master` frame lands (which
	resets this clock through `_on_lobby_master_changed`) or the old master's beats
	resume (which reset it through the `hb` relay handler) — the lobby says nothing
	to a vote that has not reached quorum, so there is no reply to wait for.

	Silent only until the first vote: the status line makes a stalled host visible
	in the panel with NO UI change, exactly as the seed retry does.
	"""
	if _state != State.IN_ROOM or _master.is_empty() or _master == _you:
		return
	# Alone in the room there is nobody to elect and the lobby would drop the vote
	# anyway (`len(votes)*2 > len(members)-1` is unsatisfiable at one member).
	if _members.size() <= 1:
		return
	if Time.get_ticks_msec() - _last_hb_msec <= int(HEARTBEAT_TIMEOUT * 1000.0):
		return

	_stall_accum += delta
	if _stall_accum < STALL_REPORT_INTERVAL:
		return
	_stall_accum = 0.0
	if not _stall_reported:
		_stall_reported = true
		status.emit("Host not responding — voting to migrate…")
	_lobby.send_stalled(_master)


func _prune_dead_connections() -> void:
	"""
	Drop the avatar of a peer whose WebRTC connection died while its LOBBY socket
	stayed up — a network change, a NAT rebind, a TURN allocation expiring.

	`peer_left` never fires for those (the lobby still has them in the room), and
	`_rtc.poll()` drops them from the MESH only, so without this their avatar
	stands frozen exactly where the last presence packet put it for the rest of
	the room's life. Only the two TERMINAL states count: STATE_DISCONNECTED is
	ICE's "lost it, still trying" and recovers on its own.

	The peer is deliberately left in `_members` — it IS still in the room, and
	the member list reports lobby membership, not reachability.
	"""
	for id: String in _connections.keys():
		var conn: WebRTCPeerConnection = _connections[id]
		var conn_state: int = conn.get_connection_state()
		if conn_state != WebRTCPeerConnection.STATE_FAILED \
				and conn_state != WebRTCPeerConnection.STATE_CLOSED:
			continue
		conn.close()
		_connections.erase(id)
		_pending_signals.erase(id)
		# MARKED STALE, NOT FROZEN-AND-ERASED. `_peer_state` is the ONLY source
		# for `peer_positions()` (the LOD manager's focus points) and
		# `nearest_member_position()` (what every crocodile hunts), and no
		# `peer_left` is coming — so leaving the entry live meant the master's
		# whole pack chased, and the LOD manager held awake, an empty patch of
		# ground for the room's life. But folding it into `_gone_*` the way
		# `_on_lobby_peer_left` does is wrong here for the opposite reason: THIS
		# PEER HAS NOT LEFT. It is still in the room, still playing, still counted
		# live by every peer whose mesh link to it survived — and we replay
		# `_gone_coins` to future joiners as `gc`, which they merge alongside that
		# same peer's own snapshot and presence, COUNTING ITS COINS TWICE — a bank
		# on the joiner's HUD that nobody else in the room is looking at.
		# So keep the counters attributed to the peer, drop only its position from
		# the per-frame readers, and let the real `peer_left` freeze the correct
		# final figure if and when it ever arrives.
		if _peer_state.has(id):
			(_peer_state[id] as Dictionary)["stale"] = true
		if _avatars.has(id):
			(_avatars[id] as RemoteAvatar).queue_free()
			_avatars.erase(id)
		# Same rule as `_on_lobby_peer_left`: only remove a peer the mesh still
		# holds, because `remove_peer()` errors on an unknown id.
		if _rtc.has_peer(MpCodec.peer_int_id(id)):
			_rtc.remove_peer(MpCodec.peer_int_id(id))


func _send_presence() -> void:
	"""
	Broadcast one presence packet: where the local player is, which way it faces,
	who it is playing, how fast it is going and whether it is on the ground —
	everything `RemoteAvatar` needs to draw a convincing runner — plus this peer's
	own coins and distance, which are what the room's shared totals are summed
	from.

	Sent UNRELIABLE on purpose: a dropped sample is replaced by the next one 66 ms
	later, and re-transmitting stale positions would be strictly worse than
	skipping them.
	"""
	# `_connections` holds every peer we have STARTED negotiating with — a peer
	# lands there the moment `_rtc.add_peer()` succeeds, long before ICE finishes
	# and its data channels open. A channel only accepts packets once it is open,
	# so broadcasting off `_connections` pushes packets at peers that are still
	# CONNECTING: send errors at 15 Hz through the whole negotiation, and forever
	# for a peer whose ICE never completes. `get_peers()` is the mesh's own answer
	# to "who is actually reachable", so send targeted to those and nobody else.
	var peers: Dictionary = _rtc.get_peers()
	var connected: Array[int] = []
	for pid: int in peers:
		if bool((peers[pid] as Dictionary).get("connected", false)):
			connected.append(pid)
	if connected.is_empty():
		return  # Nobody to tell.

	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var speed: float = 0.0
	if "velocity" in player:
		var v: Vector3 = player.get("velocity")
		speed = Vector2(v.x, v.z).length()

	# `cc` / `dd` are this peer's OWN contributions to the room's shared bank and
	# distance — ABSOLUTE values, never deltas, so the unreliable channel is
	# self-healing: a dropped packet is corrected 66 ms later instead of leaving
	# the totals permanently short. Note `own_coins`, not `coins_collected`: in a
	# room the latter is already the room's total and summing it would compound.
	# The `in` guards keep a standalone player scene answering something sane,
	# exactly like `c` above.
	# Until the join lands, this peer contributes NOTHING to the room's totals —
	# its counters still describe the solo world it came from. See
	# `_contributing()`; publishing them early raises the room's distance
	# permanently and credits its bank with another world's coins.
	var mine: bool = _contributing()
	var state: Dictionary = {
		"p": player.global_position,
		"y": player.rotation.y,
		"c": int(player.get("current_character_index")) if "current_character_index" in player else 0,
		"s": speed,
		"g": player.is_on_floor() if player.has_method("is_on_floor") else true,
		"cc": int(player.get("own_coins")) if mine and "own_coins" in player else 0,
		"dd": 0,
	}
	# `ab` — THE ABILITY STATE A WATCHER CAN SEE (bead godot-test1-69p): Teibi's
	# Resize form and Windman's Air Rush, as `player_controller.ABILITY_BIT_*`
	# flags. OMITTED WHEN ZERO, which is both the normal case and exactly what an
	# older build sends, so the decoder's missing-is-not-malformed rule reads the
	# two the same way — "nothing special to draw". Unreliable suits it for the
	# counters' reason: the value is absolute and idempotent, and an ability lasts
	# seconds, so a dropped packet costs one 66 ms tick of the pose.
	var ability: int = int(player.call("ability_visual_state")) \
			if player.has_method("ability_visual_state") else 0
	if ability != 0:
		state["ab"] = ability
	# `pz` — THE ROOM-WIDE PAUSE (bead godot-test1-3a2, owner: "when I click pause
	# in the MP it should be paused for all"). OMITTED WHEN FALSE, exactly like
	# `ab`, so an older build sees the packet shape it has always seen and simply
	# never pauses anybody.
	#
	# WHY IT RIDES PRESENCE RATHER THAN BEING A VERB. Presence is re-sent at
	# PRESENCE_HZ, so the bit is its own repair channel: a dropped packet heals in
	# 66 ms, a joiner learns the room is frozen on the first sample it receives,
	# and a pauser whose tab dies simply stops sending — no lock can outlive the
	# peer holding it, which is the failure mode a reliable "pause" verb would
	# have to invent a lease to avoid. It is also already rate-bounded by
	# MAX_PRESENCE_PACKETS_PER_PEER, so it needs no VERB_BUDGET_PER_SEC row.
	# THE WINDOW IT CANNOT REACH IS A PEER STILL NEGOTIATING ICE, and that is a
	# documented ceiling rather than an oversight (bead godot-test1-3a2). The seed
	# takes the relay leg because it must arrive BEFORE any channel opens or the
	# joiner walks a different world; a pause is not that — it is idempotent, it
	# is re-sent 15 times a second, and the worst it costs is that a joiner runs
	# for the second or two its ICE takes and then freezes with everybody else.
	# Buying that second costs a reliable verb, a relay leg AND a join-snapshot
	# field, which is three more shapes of packet for a peer that is still
	# staring at a loading world. If it ever matters, that is the upgrade path.
	#
	# THIS IS THE P KEY AND NOTHING ELSE. The help card, the skill tree, the MP
	# panel, the map, the lift and the quiz stay LOCAL pauses — see the list in
	# `pause_hub.gd` — because reading a card must not stop three other people.
	var pauser: Node = get_tree().get_first_node_in_group("pause_controller")
	if pauser != null and pauser.has_method("is_pausing") and bool(pauser.call("is_pausing")):
		state["pz"] = true

	var bytes: PackedByteArray = var_to_bytes(state)
	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for pid: int in connected:
		_rtc.set_target_peer(pid)
		_rtc.put_packet(bytes)


func _receive_mesh_packets() -> void:
	"""
	Drain the mesh and dispatch each packet to the handler for its kind.

	**This is the other trust boundary, and the sharper one.** Decoding uses
	`bytes_to_var`, *never* `bytes_to_var_with_objects` — the "with objects" form
	will instantiate arbitrary classes named in the byte stream, which hands any
	peer in the room code execution in our process. There is no situation in this
	game where a peer needs to send us an object. That rule holds for EVERY packet
	kind below; there is exactly one `bytes_to_var` call in this function and
	every handler is handed the Dictionary it produced.

	Past that, every field is type-checked, the position is rejected if any
	component is non-finite (a NaN would poison the avatar's smoothing forever),
	and the character index is range-checked before it can index CHARACTERS. A
	packet that fails any of it is dropped whole — there is no partial trust.

	PACKET KINDS ARE DISCRIMINATED BY A `"t"` KEY, and its absence is the presence
	packet — which is what keeps a phase-3/4 peer working: it sends no `"t"`, so
	it lands on the presence path, and a packet kind it has never heard of falls
	through its own validation and is dropped. Symmetrically, an unknown verb here
	is ignored SILENTLY (no warning), the same forward-compatibility rule
	`_on_lobby_relay` states for relayed verbs.
	"""
	# BOUNDED DRAIN. Room membership is an invite code shared over chat, so a peer
	# in the room is not trusted — that is the premise of both trust boundaries
	# here. An unbounded `while` lets one peer flooding the unreliable channel
	# stall the frame on the gl_compatibility web build. Discarding the backlog is
	# strictly correct rather than lossy: presence is unreliable and every packet
	# fully replaces the last, so the newest state still arrives 66 ms later.
	#
	# THE BUDGET IS PER SENDER, not one shared pool, and that distinction is the
	# whole point: WebRTCMultiplayerPeer merges every peer's channels into ONE
	# FIFO, so a shared pool is owned by whoever fills the queue. One peer
	# flooding the unreliable channel then starved the honest ones out of their
	# own share — stale `_peer_state` positions (which is what every crocodile on
	# the master hunts, and what the LOD manager holds chunks awake around) and,
	# worse, the master's RELIABLE `cnf`/`dead` packets queued behind the flood
	# until `_tick_claims` gave up and double-banked the pickup, which is exactly
	# what the claim protocol exists to prevent. Over-quota packets are still
	# DEQUEUED (a `get_packet` and an int compare) rather than left in the FIFO,
	# so the drain still reaches everybody else's traffic behind them.
	var per_peer: Dictionary = {}
	var drained: int = 0
	while drained < MAX_DRAIN_PACKETS_PER_FRAME and _rtc.get_available_packet_count() > 0:
		drained += 1
		var from_int: int = _rtc.get_packet_peer()
		var bytes: PackedByteArray = _rtc.get_packet()
		# ponytail: linear scan rather than a third dictionary kept in step with
		# `_connections` and `_avatars` — `peer_int_id` is pure and a room holds
		# at most 4 peers, so this is 3 hashes against a map that could desync.
		var avatar: RemoteAvatar = null
		var from_id: String = ""
		for id: String in _avatars:
			if MpCodec.peer_int_id(id) == from_int:
				avatar = _avatars[id]
				from_id = id
				break
		if avatar == null:
			continue

		# ONE `bytes_to_var` FOR EVERY PACKET KIND — see the docstring. A packet
		# that is not even a Dictionary is dropped here, before any handler runs.
		var decoded: Variant = bytes_to_var(bytes)
		if typeof(decoded) != TYPE_DICTIONARY:
			continue
		var packet: Dictionary = decoded as Dictionary

		var kind: String = MpCodec.packet_kind(packet)
		if not kind.is_empty():
			_receive_mesh_verb(from_id, kind, packet)
			continue

		# THE PER-SENDER BUDGET METERS PRESENCE ONLY, and it has to sit BELOW the
		# discriminator to do that. Applied above it, it discarded whatever the
		# peer had sent past its quota REGARDLESS OF KIND — including the master's
		# RELIABLE `cnf` / `dead`, which no re-send replaces. The master alone
		# sends 25 packets/s (15 Hz presence + 10 Hz croc sync), so any ~330 ms
		# gap between `_process` calls — one chunk-generation hitch, a tab
		# regaining focus — overran the 8-packet quota with no hostile peer
		# involved, and a dropped `cnf` is precisely the double-bank the claim
		# protocol exists to prevent (the loser gets no reply by design, so
		# `_tick_claims` times out and pays the pickup a second time), while a
		# dropped `dead` walks a crushed crocodile back into the world.
		# The verbs are not unmetered: `MAX_DRAIN_PACKETS_PER_FRAME` bounds the
		# whole drain and `VERB_BUDGET_PER_SEC` bounds each verb per peer.
		var used: int = int(per_peer.get(from_int, 0))
		per_peer[from_int] = used + 1
		if used >= MAX_PRESENCE_PACKETS_PER_PEER:
			continue

		var state: Dictionary = MpCodec._decode_presence_dict(packet)
		if state.is_empty():
			continue

		avatar.visible = true
		avatar.receive_state(state["p"], state["y"], state["c"], state["s"], state["g"],
			state["ab"])
		# Keep this peer's contribution to the shared totals current. The join
		# snapshot only bootstraps it; from here on presence carries it, and the
		# values being absolute means a lost packet costs nothing.
		_peer_state[from_id] = {
			"coins": state["cc"],
			"dist": state["dd"],
			"pos": state["p"],
			# The on-floor bit the packet has always carried and nothing read.
			# `nearest_member_position()` skips a peer that is off the ground, so
			# jumping breaks the scent for a REMOTE member exactly as it does for
			# the local player (bead godot-test1-s86.15).
			"floor": state["g"],
			# Whether this peer is holding the room-wide pause. Kept HERE rather
			# than in a dictionary of its own so every way a peer leaves the
			# table — `peer_left`'s erase, `leave()`'s clear, the stale mark a
			# dead mesh link earns — drops its pause with it, with no fourth
			# erase site to forget. `_apply_remote_pause()` reads it each frame.
			"pz": state["pz"],
		}


# =============================================================================
# THE ROOM-WIDE PAUSE
# =============================================================================

func _apply_remote_pause() -> void:
	"""
	Hold exactly one `PauseHub` claim while any live room member is pausing, and
	drop it the moment none is. Called every frame from `_process` (this node is
	PROCESS_MODE_ALWAYS, so it keeps running under the pause it takes — without
	that nothing could ever release it) and once more from `leave()`.

	THE STATE IS `_peer_state` AND NOTHING ELSE, which is the whole reason this
	needs no erase site of its own: a peer that leaves is erased there
	(`_on_lobby_peer_left`), a peer whose mesh link died is marked `stale` there
	(`_prune_dead_connections`) and skipped below, and `leave()` clears the table
	outright. A separate `_remote_pausers` dictionary would be a fourth place to
	forget, and the failure mode of forgetting is a world frozen for the rest of
	the run with nobody left to unfreeze it.

	ONE CLAIM, NOT ONE PER PEER: `PauseHub` counts holders by node identity, so
	two pausing peers are the same single claim from this node and the first of
	them to resume cannot start the world under the second.

	THE GAME-OVER REFUSAL is `pause_controller._toggle_pause()`'s and
	`mp_ui._apply_pause()`'s, for their reason: `GameOverUI` is PAUSABLE, so a
	pause over it kills Play Again and `ui_accept` and there is no way out of the
	screen. It is a MOVING condition — a teammate can pause while we are dead and
	we can die while they are paused — which is why this runs per frame rather
	than on the packet.
	"""
	var wanted: bool = false
	for id: String in _peer_state:
		var entry: Dictionary = _peer_state[id]
		if bool(entry.get("stale", false)):
			continue
		if bool(entry.get("pz", false)):
			wanted = true
			break
	if wanted:
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and bool(player.get("is_game_over")):
			wanted = false
	if wanted == _paused_by_remote:
		return
	_paused_by_remote = wanted
	if wanted:
		PauseHub.take(self)
	else:
		PauseHub.release(self)


func remote_pauser_name() -> String:
	"""
	The lobby name of a member who has frozen the room, or `""` when nobody has —
	including when somebody has but we are not honouring it (the game-over
	exemption above). `pause_controller` draws its card off this and is the only
	caller; nothing outside this file needs to know the pause came over the wire.

	ponytail: with two pausers this names whichever the table iterates first, and
	P stays inert under a foreign pause, so the OTHER one is who you actually wait
	for. Naming both is a longer card for a case the owner has not asked about —
	the escape hatch for a peer who will not resume is the MP panel's Leave, which
	is PROCESS_MODE_ALWAYS and opens under a foreign pause.
	"""
	if not _paused_by_remote:
		return ""
	for id: String in _peer_state:
		var entry: Dictionary = _peer_state[id]
		if bool(entry.get("stale", false)) or not bool(entry.get("pz", false)):
			continue
		for member: Variant in _members:
			if typeof(member) != TYPE_DICTIONARY:
				continue
			if str((member as Dictionary).get("id", "")) == id:
				return str((member as Dictionary).get("name", ""))
		return id  # In the state table but not (yet) in the member list.
	return ""


func _receive_mesh_verb(from_id: String, verb: String, packet: Dictionary) -> void:
	"""
	Handle one non-presence mesh packet, identified by its `"t"` discriminator.

	@param from_id: the lobby id of the sender — already resolved from the mesh's
	    integer peer id, so a packet from someone we have no avatar for never got
	    here. Handlers that need an authority check (only the master may drive the
	    crocodiles) test it against `_master` themselves.
	@param verb: `str(packet["t"])`.
	@param packet: the already-`bytes_to_var`-decoded packet. NEVER
	    `bytes_to_var_with_objects` — see `_receive_mesh_packets()`.

	An unknown verb returns silently and deliberately WITHOUT a warning: a peer on
	a later build may send packet kinds this one has never heard of, and a room
	should keep working rather than spew one line per packet per second.
	"""
	if not _verb_rate_ok(from_id, verb):
		return
	match verb:
		"croc":
			_receive_croc_sync(from_id, packet)
		"herd":
			_receive_herd(from_id, packet)
		"clm":
			_receive_claim(from_id, packet)
		"cnf":
			_receive_confirm(from_id, packet)
		"flee":
			_receive_flee(from_id, packet)
		"kill":
			_receive_kill(from_id, packet)
		"dead":
			_receive_dead(from_id, packet)
		"pad":
			_receive_pad(from_id, packet)
		"lmk":
			_receive_lmk(from_id, packet)
		"cap":
			_receive_captive(from_id, packet)
		"room":
			_receive_room(from_id, packet)
		_:
			# Forward compatibility. Not a warning — see the docstring.
			pass


func _verb_rate_ok(from_id: String, verb: String) -> bool:
	"""
	Whether this peer may spend one more of this verb in the current one-second
	window. Every verb `_receive_mesh_verb` dispatches is listed in
	VERB_BUDGET_PER_SEC, including the master-only ones — see the constant for why
	"only the master sends this" is not a rate bound.

	Dropped silently, like every other trust-boundary rejection here: a peer over
	budget is either hostile or on a broken build, and neither is worth one warning
	line per packet. The map is keyed by peer and verb, so it holds at most
	`members × VERB_BUDGET_PER_SEC.size()` entries and cannot grow with traffic.
	"""
	if not VERB_BUDGET_PER_SEC.has(verb):
		return true
	var key: String = from_id + ":" + verb
	var now: int = Time.get_ticks_msec()
	var window: Dictionary = _verb_rate.get(key, {"start": 0, "count": 0})
	if now - int(window["start"]) >= 1000:
		window = {"start": now, "count": 0}
	var spent: int = int(window["count"])
	window["count"] = spent + 1
	_verb_rate[key] = window
	return spent < int(VERB_BUDGET_PER_SEC[verb])


# =============================================================================
# PICKUP CLAIMS (phase 5)
# =============================================================================
#
# Coins and treasure chests are deterministic: every peer in the room has its own
# copy of the same pickup in the same place. Through phase 4 that meant two peers
# walking over one coin each banked it into the SHARED bank — the room paid twice
# for one coin, and a chest (~12 pickups) paid twice for twelve.
#
# The fix is an arbitrated claim, all over the MESH and RELIABLE (a lost claim is
# a pickup that pays nothing; a lost confirm is a pickup that pays twice — neither
# is something an unreliable channel may drop):
#
#     claim    peer   → master   {"t":"clm","id":int,"n":int,"v":int}
#     confirm  master → everyone {"t":"cnf","id":int,"by":int,"a":int,"m":int}
#
# `n` is how many PICKUPS (1 for a coin, the whole burst for a chest), `v` the
# base value of each (1, or Coin.GEM_VALUE). `by` is the winner's `peer_int_id`,
# `a` the total awarded AFTER the room's multiplier, and `m` the room's
# multiplier after the award, so every peer's HUD shows the same `(xN)`.
#
# FIRST CLAIM WINS, and the set that decides it is `_collected_ids` — the very
# set phase 4 already keeps and already replays to a joiner. A second claim for an
# id already in it is refused with no confirm, and the loser's pickup is simply
# gone: it was already gone on the winner's screen.

func claim_pickup(id: int, count: int, value: int) -> bool:
	"""
	Ask the room for this pickup. Returns true when the claim was taken over (the
	caller must NOT award anything — the confirm does that), false when the caller
	should run its ordinary solo path.

	FALSE OFFLINE, so every call site falls through to today's behaviour on one
	test — the same `null`/`false` discipline `shared_bank()` and friends use.

	@param id: the pickup's stable id (`Coin.id_at`), which every peer derives
	    identically because every spawner is a pure function of `run_seed`.
	@param count: how many PICKUPS this is worth for streak purposes — 1 for a
	    coin, the whole burst for a chest, which is what makes a chest step the
	    room's multiplier exactly as it steps a solo one.
	@param value: the base value of each pickup, before the room's multiplier.
	"""
	if _state != State.IN_ROOM:
		return false
	# No mesh means no arbitration is possible: `--lobby-only`, or a room whose
	# ICE never completed. Falling back to the solo path banks the pickup locally,
	# which is exactly the phase-4 behaviour this replaces — a double-count is a
	# far better failure than a coin that pays nobody.
	if _rtc == null:
		return false
	if _collected_ids.has(id):
		# Somebody already took it. Claim it anyway (true) so the caller hides the
		# pickup without awarding: that is the truth on every other screen.
		return true
	if _master != _you and not _is_mesh_peer_connected(MpCodec.peer_int_id(_master)):
		# A MESH THAT EXISTS IS NOT A MESH THAT CONNECTS. `_rtc` is built the
		# moment /ice answers, seconds before any data channel opens — and never
		# opens at all behind a symmetric NAT with no TURN — so the guard above
		# does not actually cover the case its comment describes. Answering true
		# here hid the pickup, sent a claim nobody could receive, and paid it
		# CLAIM_RETRY_SEC × CLAIM_MAX_TRIES (2 s) later from `_tick_claims`; worse,
		# only `_apply_confirm` advances `room_multiplier()`, so with no confirms
		# landing the room was pinned at x1 for the whole run. Same discipline as
		# `request_croc_kill()`: if the request cannot leave, fall through NOW.
		return false
	if _master == _you:
		_resolve_claim(id, MpCodec.peer_int_id(_you), count, value)
		return true
	_pending_claims[id] = {"n": count, "v": value, "age": 0.0, "tries": 1}
	_send_claim(id, count, value)
	return true


func room_multiplier() -> Variant:
	"""
	The room's current coin multiplier, or `null` offline so
	`player_controller.get_streak_multiplier()` falls through to its own on one
	test — the same trick phase 4 used for the bank, which is why
	`coin_hud.gd` shows the room's `(xN)` with no HUD change at all.

	Expires on its own: a room that stops picking things up for STREAK_WINDOW is
	back to x1 without anybody having to send a "streak broke" message.

	THE GUARDS MUST MATCH `claim_pickup()`'s EXACTLY, and that pairing is the
	whole correctness of the fall-through. When arbitration is impossible
	(`--lobby-only`, ICE never completed, a symmetric NAT with no TURN) that
	function banks the pickup through the ordinary solo path — but this one used
	to keep answering non-null on `_state` alone, and only `_apply_confirm` ever
	advances the room streak, so it returned a hard `1` forever: every coin banked
	at x1 with `(x1)` on the HUD while the peer's own perfectly good `coin_streak`
	was ignored. Falling through to solo has to be BOTH halves or it is neither.
	"""
	if _state != State.IN_ROOM or _rtc == null:
		return null
	if _master != _you and not _is_mesh_peer_connected(MpCodec.peer_int_id(_master)):
		return null
	if Time.get_ticks_msec() > _room_streak_deadline_msec:
		return 1
	return _room_multiplier


static func room_multiplier_from(streak: int, per_step: int, max_bonus: int) -> int:
	"""
	The score multiplier for a streak of `streak` pickups — the same arithmetic as
	`player_controller.get_streak_multiplier()`, pulled out as a pure static so
	scripts/mp_selfcheck.gd can pin it against the player's own constants without
	a room, a player or a socket.
	"""
	if per_step <= 0:
		return 1  # No step size, no bonus — guards the division below.
	return 1 + mini(max_bonus, streak / per_step)


func _resolve_claim(id: int, by_int: int, count: int, value: int) -> void:
	"""
	MASTER ONLY: award a claimed pickup, or refuse it silently.

	The refusal is `_collected_ids.has(id)` and it is the whole arbitration —
	first claim wins, and a second claimant gets no confirm at all rather than a
	"denied" message, because there is nothing for it to do with one: its pickup
	is already hidden and the id will reach it in a confirm or a join snapshot.

	The room's streak advances ONCE PER PICKUP, exactly as `collect_coin()` does
	per coin, so a chest's burst steps the multiplier the same way in a room as it
	does solo — that is what `count` is for.
	"""
	if _collected_ids.has(id):
		return
	# NOT recorded here: `_apply_confirm` below records it, through
	# `_absorb_collected`, which skips ids already in the set and then returns
	# early when nothing was fresh. Recording it up front therefore turned the
	# master's own sweep of the `"coin"` group into a no-op, and `coin.gd`
	# deliberately does not `queue_free()` on the claimed path (it only hides the
	# coin and stops monitoring) — so every coin the MASTER picked up stayed in
	# the tree, invisible and still in the `"coin"` group, until its chunk
	# unloaded. `_resolve_kill` has the same shape and gets it right: `_dead_crocs`
	# is written inside `_apply_dead`, not before it.
	#
	# Safe because nothing between here and `_apply_confirm` re-enters this
	# function: `_broadcast_reliable` is a synchronous `put_packet` loop.

	var now: int = Time.get_ticks_msec()
	if now > _room_streak_deadline_msec:
		_room_streak = 0  # The window lapsed: the room's chain is broken.
	var awarded: int = 0
	for _pickup: int in count:
		_room_streak += 1
		awarded += value * room_multiplier_from(
			_room_streak, PLAYER_SCRIPT.STREAK_COINS_PER_STEP, PLAYER_SCRIPT.STREAK_MAX_BONUS
		)
	_room_multiplier = room_multiplier_from(
		_room_streak, PLAYER_SCRIPT.STREAK_COINS_PER_STEP, PLAYER_SCRIPT.STREAK_MAX_BONUS
	)
	_room_streak_deadline_msec = now + int(PLAYER_SCRIPT.STREAK_WINDOW * 1000.0)

	# The PRE-MULTIPLIER worth of the whole claim — `count` pickups at `value`
	# each — for meta-progression (bead godot-test1-42n): lifetime coins count what
	# was physically picked up, so they can never be credited from `a`, which the
	# room's multiplier is already in.
	#
	# IT DOES NOT GO ON THE WIRE, and that is a security decision rather than a
	# saving. A confirm is signed by nothing: the master names the winner in `by`,
	# so a hostile master could address a confirm to somebody else and, with a base
	# value on the wire, hand them any number of LIFETIME coins — which are
	# monotone and persisted, so unlike the run-scoped `a` beside it the damage
	# outlives the room. Every peer can derive this figure for itself instead: the
	# master from the claim it is resolving right here, and a non-master from its
	# own `_pending_claims` entry, which still holds `n`/`v` when the confirm lands
	# (see `_receive_confirm`). So `bank_awarded`'s base total is never anything a
	# peer told us.
	var base_total: int = count * value
	var confirm: Dictionary = {
		"t": "cnf", "id": id, "by": by_int, "a": awarded, "m": _room_multiplier,
	}
	_broadcast_reliable(var_to_bytes(confirm))
	# And apply it to ourselves: the master is a player too, and this is the only
	# path that banks a pickup it claimed.
	_apply_confirm(id, by_int, awarded, _room_multiplier, base_total)


func _apply_confirm(id: int, by_int: int, awarded: int, multiplier: int, base_total: int = 0) -> void:
	"""
	Every peer's half of a confirm: the pickup is gone room-wide, and whoever won
	it banks the amount the MASTER already multiplied.

	`_absorb_collected` does double duty here — it records the id AND sweeps the
	live world for a coin still holding it, which is what makes the confirm
	arrival order irrelevant (a coin spawned afterwards asks `is_coin_collected()`
	in its own `_ready()`).

	@param base_total: the claim's PRE-MULTIPLIER worth, for the lifetime-coin
	    counter. ALWAYS DERIVED BY THE CALLER FROM ITS OWN STATE — the master from
	    the claim it is resolving, a peer from its own `_pending_claims` entry —
	    and never taken off the wire, because a confirm names its own winner and a
	    forgeable base value would mint PERSISTED progression rather than a
	    run-scoped bank. Trailing and defaulting to 0 so nothing that does not know
	    about it changes behaviour: 0 means "no base value known" and
	    `bank_awarded()` credits no lifetime coins, which is exactly what every
	    call did before bead godot-test1-42n.
	"""
	_absorb_collected([id])
	_pending_claims.erase(id)
	_room_multiplier = multiplier
	_room_streak_deadline_msec = Time.get_ticks_msec() + int(PLAYER_SCRIPT.STREAK_WINDOW * 1000.0)
	if by_int != MpCodec.peer_int_id(_you):
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("bank_awarded"):
		player.bank_awarded(awarded, base_total)


func _send_claim(id: int, count: int, value: int) -> void:
	"""Send one claim to the master, RELIABLE. A no-op when the master's data
	channel is not open — `_tick_claims` will try again."""
	_send_reliable_to_master(var_to_bytes({"t": "clm", "id": id, "n": count, "v": value}))


func _send_reliable_to_master(bytes: PackedByteArray) -> bool:
	"""
	Send one packet to the room's master, RELIABLE, and report whether it left.

	False means there was nobody to send it to — no mesh, no master yet, we ARE
	the master (callers resolve those locally instead), or the master's data
	channel is still negotiating. Every caller uses that answer to fall back
	rather than to drop something on the floor.
	"""
	if _rtc == null or _master == "" or _master == _you:
		return false
	var master_int: int = MpCodec.peer_int_id(_master)
	if not _is_mesh_peer_connected(master_int):
		return false
	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_rtc.set_target_peer(master_int)
	_rtc.put_packet(bytes)
	return true


func _broadcast_reliable(bytes: PackedByteArray) -> void:
	"""
	Send one packet to every peer whose data channel is actually OPEN, reliably.

	Targeted rather than broadcast-to-peer-0 for the reason `_send_presence()`
	spells out: `_connections` holds peers negotiation has merely STARTED with,
	and pushing at those is a send error per packet for the whole negotiation.
	"""
	if _rtc == null:
		return
	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	var peers: Dictionary = _rtc.get_peers()
	for pid: int in peers:
		if not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		_rtc.set_target_peer(pid)
		_rtc.put_packet(bytes)


func _is_mesh_peer_connected(int_id: int) -> bool:
	"""Whether this mesh peer's data channels are open (not merely negotiating)."""
	if _rtc == null:
		return false
	var peers: Dictionary = _rtc.get_peers()
	if not peers.has(int_id):
		return false
	return bool((peers[int_id] as Dictionary).get("connected", false))


func _tick_claims(delta: float) -> void:
	"""
	Re-drive claims still waiting on a confirm, and give up on the ones that never
	get one.

	ponytail: giving up RESOLVES THE PICKUP LOCALLY — banked with the local
	multiplier and the id recorded — rather than eating it. The ceiling is a rare
	double-count when the confirm was merely slow (2 s slow); the alternative is a
	coin that visibly vanished and paid nothing, which is worse. The upgrade path
	is the master ACKing the claim itself, so a slow confirm can be distinguished
	from a lost one.
	"""
	if _pending_claims.is_empty():
		return
	for id: int in _pending_claims.keys():
		var claim: Dictionary = _pending_claims[id]
		claim["age"] = float(claim["age"]) + delta
		if float(claim["age"]) < CLAIM_RETRY_SEC:
			continue
		claim["age"] = 0.0
		if int(claim["tries"]) >= CLAIM_MAX_TRIES:
			_pending_claims.erase(id)
			_resolve_claim_locally(id, int(claim["n"]), int(claim["v"]))
			continue
		claim["tries"] = int(claim["tries"]) + 1
		_send_claim(id, int(claim["n"]), int(claim["v"]))


func _resolve_claim_locally(id: int, count: int, value: int) -> void:
	"""
	The retry budget ran out: bank the pickup ourselves through the ordinary solo
	path, so the player is paid for something they visibly picked up.

	`collect_coin` is deliberately the vehicle — it already owns the streak, the
	HUD and the print, and in a room it reads the ROOM's multiplier through
	`get_streak_multiplier()` anyway.
	"""
	# Through `_absorb_collected` rather than a bare set write, so the hidden
	# pickup waiting on that confirm is actually freed — the same sweep the
	# confirm would have run.
	_absorb_collected([id])
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("collect_coin"):
		return
	for _pickup: int in count:
		player.collect_coin(value)


func _receive_claim(from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: one peer's claim, arriving over the mesh as unvalidated peer
	input — so every field is type-checked and bounded before it is used, and a
	packet failing any of it is dropped whole (no partial trust, exactly like the
	other four boundaries in this file).

	`n` is the field that matters: it drives the award loop in `_resolve_claim`,
	so an unbounded one would be a frame stall any peer in the room could ask for.
	"""
	if _master != _you:
		return  # Not ours to arbitrate. A peer on a stale master will retry.
	if typeof(packet.get("id", null)) != TYPE_INT \
			or typeof(packet.get("n", null)) != TYPE_INT \
			or typeof(packet.get("v", null)) != TYPE_INT:
		return
	var count: int = packet["n"]
	var value: int = packet["v"]
	if count < 1 or count > MAX_CLAIM_PICKUPS:
		return
	if value < 1 or value > MAX_CLAIM_VALUE:
		return
	_resolve_claim(int(packet["id"]), MpCodec.peer_int_id(from_id), count, value)


func _receive_confirm(from_id: String, packet: Dictionary) -> void:
	"""
	The master's ruling on a claim. ONLY the master's is accepted: the mesh is
	peer-to-peer, so without that check any member could mint confirms and pay
	itself the room's bank — the same authority rule `_receive_croc_sync()` and
	the seed broadcast both enforce.
	"""
	if from_id != _master:
		return
	if typeof(packet.get("id", null)) != TYPE_INT \
			or typeof(packet.get("by", null)) != TYPE_INT \
			or typeof(packet.get("a", null)) != TYPE_INT \
			or typeof(packet.get("m", null)) != TYPE_INT:
		return
	var awarded: int = packet["a"]
	if awarded < 0 or awarded > MpCodec.MAX_STATE_COUNTER:
		return
	# The multiplier only ever feeds the HUD suffix, but it is clamped to the range
	# the game can actually produce so a hostile master cannot print "x9000".
	var multiplier: int = clampi(int(packet["m"]), 1, 1 + PLAYER_SCRIPT.STREAK_MAX_BONUS)
	# THE BASE VALUE FOR META-PROGRESSION IS DERIVED HERE, NEVER READ OFF THE WIRE
	# (bead godot-test1-42n). It comes from OUR OWN pending claim — the entry we
	# wrote in `claim_pickup()` before sending the claim, which still holds `n`/`v`
	# because `_apply_confirm` only erases it further down.
	#
	# Why not a `b` field with a bound on it: a confirm names its own winner, so a
	# hostile master could address one to another member with any base value it
	# liked, and that member would permanently gain those LIFETIME coins for a
	# pickup it never claimed. `a` is forgeable the same way and always has been,
	# but that inflates a run-scoped bank; lifetime coins are monotone and
	# persisted, so the same forgery there outlives the room. Deriving it locally
	# is both smaller and unforgeable: a peer credits progression only for a pickup
	# it can prove to itself that it asked for.
	#
	# Zero when there is no matching claim, which is the correct answer in all
	# three cases it happens: the confirm is for somebody else (we do not bank at
	# all), it is a duplicate whose entry we already consumed, or `_tick_claims`
	# gave up and `_resolve_claim_locally` already paid the progression through
	# `collect_coin`.
	var pickup_id: int = int(packet["id"])
	var base_total: int = 0
	if _pending_claims.has(pickup_id):
		var claim: Dictionary = _pending_claims[pickup_id]
		base_total = int(claim["n"]) * int(claim["v"])
	_apply_confirm(pickup_id, int(packet["by"]), awarded, multiplier, base_total)


# =============================================================================
# CROCODILE SYNC (phase 5)
# =============================================================================
#
# The room MASTER simulates the crocodiles and broadcasts their transforms; every
# other peer stops running that crocodile's AI and renders the synced state.
#
# THE SYNC LAYER NEVER CREATES, RE-PARENTS OR FREES A CROCODILE. Crocodiles stay
# chunk-parented, per-peer, deterministic and freed on chunk unload exactly as in
# single player; this only overlays dynamic state onto nodes that already exist
# locally, matched by `croc_id()`. That is what keeps a sleeping crocodile free:
# its spawn state is already a pure function of chunk coords + `run_seed`, which
# every peer computes identically, so only the AWAKE ones cost any network at all.
#
# COVERAGE: the master simulates only the crocodiles ITS OWN terrain has loaded,
# which used to stop at `render_distance` × 50 m (150 m on web) — a peer beyond
# that got no samples for its neighbours and they fell back to local simulation
# after CROC_SYNC_TIMEOUT. That is now closed from the terrain side (bead
# godot-test1-s86.14): `crocodile_lod_manager.gd` hands the same peer-position
# array it already builds to `endless_terrain.set_focus_points()`, which keeps a
# 3×3 chunk block loaded around each teammate — 50 m of ground in every
# direction, covering the 45 m SIM_RADIUS inside which a crocodile is awake at
# all. Focus points decide only WHICH CHUNKS STAY LOADED, never what one
# contains; chunk content is still a pure function of coords + `run_seed`.
#
# ponytail: the residual ceiling is the CAP — at most three teammates and 27
# extra chunks are honoured (`endless_terrain.MAX_FOCUS_POINTS` /
# `MAX_FOCUS_CHUNKS`), because the union of peer areas multiplies the active
# chunk count and the web build is what all of this exists to protect. A room
# whose four players stand in four different places pins 27 chunks and the rest
# degrades exactly as before: local simulation, for peers far past each other's
# fog. Nothing duplicates, nothing vanishes either way.

func _send_croc_sync() -> void:
	"""
	Master only: send each connected peer the crocodiles awake near IT.

	Sent UNRELIABLE, for the same reason presence is: a dropped sample is
	replaced 100 ms later, and re-transmitting a stale transform would be strictly
	worse than skipping it.

	PER-PEER FILTERING IS WHAT KEEPS THIS AFFORDABLE. ~25 crocodiles inside
	CROC_SYNC_RADIUS of one peer × 21 bytes an entry × 10 Hz ≈ 5 KB/s per peer,
	against ~100 KB/s if the whole awake set (which spans the whole room) were
	broadcast unfiltered.

	ONE PASS OVER THE GROUP, N BUFFERS — never one pass per peer. The group holds
	~1000 nodes and this runs 10 times a second, so the loop order is the whole
	cost model.
	"""
	# Who is actually reachable, and where they last told us they were. Built off
	# `_rtc.get_peers()` rather than `_connections` for the reason `_send_presence`
	# spells out: `_connections` holds peers whose channels are still negotiating.
	var peers: Dictionary = _rtc.get_peers()
	var target_int: Array[int] = []
	var target_pos: Array[Vector3] = []
	for id: String in _peer_state:
		var pid: int = MpCodec.peer_int_id(id)
		if not peers.has(pid) or not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		target_int.append(pid)
		target_pos.append(_peer_state[id]["pos"])
	if target_int.is_empty():
		return  # Nobody to tell.

	var count: int = target_int.size()
	var buf_ids: Array[PackedInt32Array] = []
	var buf_xf: Array[PackedFloat32Array] = []
	var buf_flags: Array[PackedByteArray] = []
	for _t: int in count:
		buf_ids.append(PackedInt32Array())
		buf_xf.append(PackedFloat32Array())
		buf_flags.append(PackedByteArray())

	var radius_sq: float = CROC_SYNC_RADIUS * CROC_SYNC_RADIUS
	for croc: Node in get_tree().get_nodes_in_group("crocodile"):
		# Defensive `in` / `has_method` guards in the LOD manager's style: the
		# group is a contract, not a type.
		if not is_instance_valid(croc) or not croc.has_method("croc_id") or not (croc is Node3D):
			continue
		# Asleep crocodiles cost zero network — every peer already agrees on where
		# a sleeping one stands, because that is its deterministic spawn state.
		#
		# EXCEPT A SLEEPER THAT HAS STALKED, which is the one body that has left
		# that state without waking: `crocodile_lod_manager` walks a sleeping
		# tracker up the scent trail on its own scan (see `advance_tracking`), so
		# the master's copy is somewhere the peer's deterministic spawn position
		# is not, and skipping it would pop the unit into place the frame it woke.
		# No protocol change and no measurable traffic — the per-peer radius filter
		# below still applies, and a hunter is one body per few chunks.
		#
		# `has_stalked` and NOT `is_tracking`, deliberately: the question is whether
		# the spawn position is still a true statement about this body, and it stops
		# being one permanently the first time the unit takes a step. A tracker whose
		# trail has gone cold is just as displaced as one still walking.
		if "lod_active" in croc and not croc.lod_active:
			if not ("has_stalked" in croc and croc.has_stalked):
				continue
		# A crocodile WE are being driven on is not ours to publish. This cannot
		# normally be true on the master (promotion releases them all), but a
		# sample in flight across an election could land just after we were
		# elected, and echoing it back would be a loop.
		if "remote_driven" in croc and croc.remote_driven:
			continue

		var body: Node3D = croc as Node3D
		var pos: Vector3 = body.global_position
		var id: int = croc.croc_id()
		var flags: int = MpCodec._croc_flags(croc)
		# `rotation.y`, not a global yaw: `set_remote_state()` writes `rotation.y`
		# on the far side, and a chunk (the crocodile's parent) is never rotated,
		# so the two are the same number and the round trip is symmetric.
		var yaw: float = body.rotation.y

		for t: int in count:
			if buf_ids[t].size() >= MpCodec.MAX_CROC_SYNC:
				continue  # Packet full for this peer; the rest wait 100 ms.
			if pos.distance_squared_to(target_pos[t]) > radius_sq:
				continue
			buf_ids[t].append(id)
			buf_xf[t].append(pos.x)
			buf_xf[t].append(pos.y)
			buf_xf[t].append(pos.z)
			buf_xf[t].append(yaw)
			buf_flags[t].append(flags)

	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for t: int in count:
		if buf_ids[t].is_empty():
			continue
		var bytes: PackedByteArray = var_to_bytes({
			"t": "croc", "i": buf_ids[t], "x": buf_xf[t], "f": buf_flags[t],
		})
		_rtc.set_target_peer(target_int[t])
		_rtc.put_packet(bytes)


func _receive_croc_sync(from_id: String, packet: Dictionary) -> void:
	"""
	Apply one crocodile-sync packet from the master.

	DROPPED UNLESS IT CAME FROM THE MASTER, for exactly the reason only the
	master's `seed` is accepted: the mesh is peer input, and without this check
	any member of the room could drive everybody's crocodiles. A packet arriving
	while WE are the master is dropped too — we are the authority, not a listener.
	"""
	if from_id != _master or _master == _you:
		return
	var sync: Dictionary = MpCodec.decode_croc_sync(packet)
	if sync.is_empty():
		return  # The fourth trust boundary refused it; whole or nothing.

	var ids: PackedInt32Array = sync["ids"]
	var xf: PackedFloat32Array = sync["xf"]
	var flags: PackedByteArray = sync["flags"]
	var now: int = Time.get_ticks_msec()
	# At most ONE group scan per packet, not one per missing id.
	var rescanned: bool = false

	for entry: int in ids.size():
		var id: int = ids[entry]
		var croc: Node = _croc_by_id(id)
		if croc == null and not rescanned:
			_rebuild_croc_cache()
			rescanned = true
			croc = _croc_by_id(id)
		if croc == null:
			# EXPECTED, NOT AN ERROR: this peer has not generated the chunk that
			# crocodile lives in. Silent on purpose — warning here would be one
			# line per crocodile at 10 Hz.
			continue
		var base: int = entry * 4
		croc.set_remote_state(
			Vector3(xf[base], xf[base + 1], xf[base + 2]), xf[base + 3], int(flags[entry])
		)
		_croc_seen[id] = now


func _tick_croc_timeout() -> void:
	"""
	Hand back any crocodile whose samples have stopped, and purge the id cache of
	crocodiles whose chunk has since unloaded.

	Runs on the sync tick (10 Hz) rather than per frame — CROC_SYNC_TIMEOUT is
	2 s, so a tenth of a second of granularity is free.
	"""
	var cutoff: int = Time.get_ticks_msec() - int(CROC_SYNC_TIMEOUT * 1000.0)
	for id: int in _croc_seen.keys():
		if int(_croc_seen[id]) > cutoff:
			continue
		_croc_seen.erase(id)
		var croc: Node = _croc_by_id(id)
		if croc != null:
			croc.clear_remote_drive()

	# The cache holds hard references, so a crocodile freed with its chunk would
	# otherwise sit here as a freed instance until its id came round again.
	for id: int in _synced_crocs.keys():
		if not is_instance_valid(_synced_crocs[id]):
			_synced_crocs.erase(id)


# =============================================================================
# FAUNA HERD SYNC (bead godot-test1-6xc)
# =============================================================================
#
# THE MASTER SIMULATES, PEERS REPLAY — the whole of the owner's report ("in
# multiplayer i can see giraffes and I ride on one of them but my buddy in the
# same game don't see them"). Fauna still never touches `run_seed`; this is the
# SCENT TRAIL's precedent — runtime state the master broadcasts, outside the
# determinism contract, costing no seeded stream a draw.
#
# ONE PACKET PER TICK, NOT ONE PER ANIMAL. A herd's whole state is its build
# params plus (centre, facing yaw, metres travelled): every member sits at
# `centre + offset` and every limb angle is a pure function of metres walked, so
# ~70 bytes at CROC_SYNC_HZ describes up to ten animals completely. The params
# ride EVERY tick rather than once, which is what makes it self-healing for a
# dropped packet, for a peer whose mesh was still negotiating and for a late
# joiner — no relay leg and no join-snapshot field.
#
# THE SYNC LAYER CREATES NO NODE AND FREES NONE, exactly like the crocodile sync
# above it. `fauna_manager.gd` owns the animals at both ends: `herd_sync_state()`
# describes its own herd, `apply_herd_sync()` builds or eases one, and the
# silence timeout that frees a replay lives beside the state it frees.
#
# MIXED-BUILD CEILING, documented like the `room` verb's: a master on a build
# without this verb publishes nothing, and a peer in that room draws no fauna at
# all (it will not roll its own — see `_mp_replays_the_herd`). It converges the
# moment the room's master is on this build.

func _send_herd_sync() -> void:
	"""
	Master only: tell every peer about the herd crossing our field, or that none
	is (`k: -1`, the all-clear — see `MpCodec.decode_herd`).

	Sent UNRELIABLE, for the reason presence is: another one follows in 100 ms and
	re-transmitting a stale centre would be strictly worse than skipping it. Sent
	UNCONDITIONALLY rather than only while a herd is alive, because the all-clear
	is what frees a peer's copy promptly when a crossing ends; it is ~26 bytes at
	10 Hz to at most three peers, half a percent of what the crocodile sync costs.
	"""
	if _rtc == null:
		return
	var state: Dictionary = {"k": -1}
	var fauna := get_tree().get_first_node_in_group("fauna")
	if fauna != null and fauna.has_method("herd_sync_state"):
		var live: Dictionary = fauna.call("herd_sync_state")
		if not live.is_empty():
			state = live
	state["t"] = "herd"
	var bytes: PackedByteArray = var_to_bytes(state)
	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# Targeted, not broadcast-to-peer-0, for the reason `_send_presence()` spells
	# out: `_connections` holds peers negotiation has merely STARTED with.
	var peers: Dictionary = _rtc.get_peers()
	for pid: int in peers:
		if not bool((peers[pid] as Dictionary).get("connected", false)):
			continue
		_rtc.set_target_peer(pid)
		_rtc.put_packet(bytes)


func _receive_herd(from_id: String, packet: Dictionary) -> void:
	"""
	Apply one herd packet from the master.

	DROPPED UNLESS IT CAME FROM THE MASTER, and dropped while WE are the master,
	for exactly `_receive_croc_sync()`'s reasons: the mesh is peer input, so
	without the first any member could put a giraffe in front of everybody, and
	without the second our own herd would be driven by an echo of itself.
	"""
	if from_id != _master or _master == _you:
		return
	var state: Dictionary = MpCodec.decode_herd(packet)
	if state.is_empty():
		return  # The eighth trust boundary refused it; whole or nothing.
	var fauna := get_tree().get_first_node_in_group("fauna")
	if fauna == null or not fauna.has_method("apply_herd_sync"):
		return  # No fauna manager in this scene — not an error, the LOD idiom.
	fauna.call("apply_herd_sync", state)


func _croc_by_id(id: int) -> Node:
	"""The local crocodile with this id, or `null`. Purges a freed instance it
	finds on the way; does NOT scan the group — see `_rebuild_croc_cache()`."""
	var cached: Variant = _synced_crocs.get(id, null)
	if cached == null:
		return null
	if not is_instance_valid(cached):
		_synced_crocs.erase(id)
		return null
	return cached as Node


func _rebuild_croc_cache() -> void:
	"""Cache every loaded crocodile's id in one pass. Called on a lookup miss —
	at most once per packet — because a miss usually means a chunk streamed in
	since the last scan, and re-caching one id at a time would rescan per entry."""
	_synced_crocs.clear()
	for croc: Node in get_tree().get_nodes_in_group("crocodile"):
		# Filtered on the method the SYNC needs, not merely on `croc_id` — every
		# consumer of this cache calls `set_remote_state` / `clear_remote_drive`
		# straight off it, and a group member exposing an id but not the phase-5
		# API would be a hard runtime error inside `_process`. GDScript unwinds
		# the whole erroring function, so that would silently abandon the rest of
		# the sync packet and the timeout sweep with it.
		if is_instance_valid(croc) and croc.has_method("set_remote_state"):
			_synced_crocs[croc.croc_id()] = croc


func _release_synced_crocs() -> void:
	"""Hand every crocodile we were rendering from the master's samples back to
	its own AI, and forget the sync bookkeeping. Used by promotion (the hot
	standby handover) and by `leave()`."""
	for croc: Variant in _synced_crocs.values():
		if is_instance_valid(croc) and (croc as Node).has_method("clear_remote_drive"):
			(croc as Node).clear_remote_drive()
	_synced_crocs.clear()
	_croc_seen.clear()


# =============================================================================
# CROCODILE ABILITIES THROUGH THE MASTER (phase 5)
# =============================================================================
#
# Two player abilities change a crocodile's state rather than merely reading it,
# and once the master simulates the pack, a peer doing either LOCALLY changes
# nothing anybody else can see — the very next sync packet overwrites it. So both
# are routed to the master, over the MESH and RELIABLE (each is a one-off event:
# a lost one is an ability that visibly did nothing):
#
#     flee   peer   → master   {"t":"flee","x","y","z","d"}    Phoboman's wave
#     pad    peer   → master   {"t":"pad","f":int,"p":int}     an HQ lure plate
#     kill   peer   → master   {"t":"kill","id":int}           giant Teibi's crush
#     dead   master → everyone {"t":"dead","id":int}           the kill ruling
#
# THERE IS DELIBERATELY NO `flee` BROADCAST: `is_fleeing` is already a bit in the
# sync packet's flag byte, so the master applying `flee_from()` reaches every peer
# 100 ms later through machinery that already exists. A kill needs its own
# broadcast only because it FREES a node, which no amount of transform sync can
# express.

func request_croc_flee(origin: Vector3, duration: float, radius: float = 0.0,
		tracks_player: bool = true) -> bool:
	"""
	Phoboman's Stink Wave, made room-wide: scare the crocodiles this peer can see
	AND ask the master to scare the ones it is the authority for, so a wave set
	off on one screen turns the pack on every other one too.

	A NO-OP OFFLINE. `_ability_phoboman()`'s own local loop stays exactly as it
	was; the local pass here is what `clear_nearby_crocodiles()` needs, since that
	caller has no local alternative left in a room. Applying locally as well as
	relaying is not redundant: the master only drives the crocodiles ITS terrain
	has loaded, so a peer more than a render distance away from the master gets
	nothing back at all — the same coverage ceiling the croc sync documents — and
	a respawning player would have had no spawn protection whatsoever.

	`tracks_player` is false when the CASTER is not the local player, so the flight
	runs from the fixed `origin` - the same distinction `_receive_flee()` makes for a
	relayed wave, exposed here because the vent purge is a local caller naming a
	remote position.

	`radius` bounds the wave to `radius` metres of `origin`; 0.0 means unbounded
	(Phoboman's wave, which is global by design). WITHOUT IT the bounded sweep
	`clear_nearby_crocodiles()` performs solo became a room-wide one: every death
	by any peer disarmed every awake crocodile in the room for four seconds.

	RETURNS whether the room has taken it over — false offline only, so a caller
	whose LOCAL alternative would break the room
	(`player_controller.clear_nearby_crocodiles()`, which frees bodies the master
	is the authority for) can fall through on one test, the same shape
	`request_croc_kill()` uses. It is true even when the relay could not leave,
	because the local pass above still ran and freeing is never right in a room.
	"""
	if _state != State.IN_ROOM:
		return false
	# Whatever we can reach ourselves, scare now. Harmless on remote-driven
	# crocodiles (the next sample overwrites the flag 100 ms later) and on the
	# master this IS the authoritative application.
	# `tracks_player` FALSE for a caster who is not the local player - the cell
	# block's vent purge, which names a TEAMMATE's position. Default true, so
	# Phoboman's wave and `clear_nearby_crocodiles()` are byte-for-byte unchanged;
	# without it a purge fired on the master would send the pack running from the
	# prisoner in the tower, i.e. straight at the teammate it was meant to help.
	_apply_flee(origin, duration, radius, tracks_player)
	if _master == _you:
		return true
	_send_reliable_to_master(var_to_bytes({
		"t": "flee", "x": origin.x, "y": origin.y, "z": origin.z,
		"d": duration, "r": radius,
	}))
	return true


func _apply_flee(origin: Vector3, duration: float, radius: float = 0.0, tracks_player: bool = true) -> void:
	"""
	The same group loop `player_controller._ability_phoboman()` runs, over the
	crocodiles this peer drives.

	No boss test here on purpose — `flee_from()` itself early-returns for a boss
	(Stink Wave immunity), so the rule stays in the one file that owns it.

	`tracks_player` is false for a RELAYED wave: this peer has no body for the
	caster, so the flight must run from the fixed `origin` rather than from our
	own player — see `piglet_crocodile_ai.flee_from()`.
	"""
	var radius_sq: float = radius * radius
	for croc: Node in get_tree().get_nodes_in_group("crocodile"):
		# `is Node3D` alongside the has_method guard, like every other group loop
		# here: `croc as Node3D` on a non-Node3D yields null, and the property read
		# below is then a hard error — which in GDScript unwinds the whole function,
		# abandoning every remaining crocodile mid-sweep.
		if not is_instance_valid(croc) or not (croc is Node3D) or not croc.has_method("flee_from"):
			continue
		if radius > 0.0 and (croc as Node3D).global_position.distance_squared_to(origin) > radius_sq:
			continue
		croc.flee_from(origin, duration, tracks_player)


func _receive_flee(_from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer's Stink Wave, arriving over the mesh as unvalidated
	peer input — so the origin and the duration are both checked finite and
	bounded before either reaches a crocodile, and a packet failing any of it is
	dropped whole (no partial trust, exactly like the other boundaries here).

	`d` is the field that matters: a fleeing crocodile is a harmless one, so an
	unbounded duration would disarm the whole room for its lifetime.
	"""
	if _master != _you:
		return
	if not MpCodec._is_number(packet.get("x", null)) or not MpCodec._is_number(packet.get("y", null)) \
			or not MpCodec._is_number(packet.get("z", null)) or not MpCodec._is_number(packet.get("d", null)):
		return
	var origin := Vector3(float(packet["x"]), float(packet["y"]), float(packet["z"]))
	var duration: float = float(packet["d"])
	# Finiteness is checked BEFORE anything is derived from these, the same rule
	# decode_presence() states: a NaN origin would poison every flee heading it
	# touched, and on wasm a non-finite float→int trunc can trap the module.
	if not is_finite(origin.x) or not is_finite(origin.y) or not is_finite(origin.z):
		return
	if absf(origin.x) > MpCodec.MAX_PRESENCE_COORD or absf(origin.y) > MpCodec.MAX_PRESENCE_COORD \
			or absf(origin.z) > MpCodec.MAX_PRESENCE_COORD:
		return
	if not is_finite(duration) or duration <= 0.0 or duration > MAX_FLEE_DURATION:
		return
	# `r` is optional (a phase-5.0 peer sends none) and bounded like everything
	# else here; a missing or malformed one reads as 0.0 = unbounded, which is
	# what that older peer meant.
	var radius: float = 0.0
	if MpCodec._is_number(packet.get("r", null)):
		radius = float(packet["r"])
		if not is_finite(radius) or radius < 0.0 or radius > MpCodec.MAX_PRESENCE_COORD:
			return
	# tracks_player FALSE: the caster is on another screen, so the crocodiles must
	# run from `origin`, not from our own player.
	_apply_flee(origin, duration, radius, false)


func request_guard_lure(floor_index: int, pad_index: int) -> bool:
	"""
	An HQ lure plate was stepped on: divert that storey's guard, room-wide.

	@return: whether the room has taken it over — false OFFLINE ONLY, which is the
	    caller's signal to apply the press itself (`TowerInterior._press_lure_pad`,
	    the same one-test shape `request_croc_flee()` gives its callers).

	THE `flee` VERB'S SHAPE, ONE VERB ALONG, and everything it does not do is the
	point: no transform, no flag, no broadcast. The master applies the press to the
	guard it is the authority for and the walk reaches every other screen through
	the crocodile sync that is already running — a lured guard is just a crocodile
	that is somewhere else 100 ms later.

	APPLIED LOCALLY AS WELL AS RELAYED, for the coverage reason the flee's own
	docstring states: the master only drives the bodies ITS terrain has streamed
	in, so a peer standing in the HQ while the master is a kilometre away in the
	field would otherwise press a plate that did nothing at all. On that peer the
	guard is nobody's remote, so the local pass IS the simulation; where the master
	does drive it, `investigate_point()` refuses a remote-driven body and the local
	pass is a no-op.
	"""
	if _state != State.IN_ROOM:
		return false
	_apply_guard_lure(floor_index, pad_index)
	if _master == _you:
		return true
	_send_reliable_to_master(var_to_bytes({
		"t": "pad", "f": floor_index, "p": pad_index,
	}))
	return true


func _apply_guard_lure(floor_index: int, pad_index: int) -> void:
	"""
	Hand one press to the building. Group-discovered and `has_method`-guarded like
	every other cross-system call here: no tower streamed in on this machine and
	there is no guard to divert, which is not an error.
	"""
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("lure_guard"):
		return
	interior.call("lure_guard", floor_index, pad_index)


func _receive_pad(from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer stepped on a lure plate.

	THE VERB CARRIES INTENT AND NOTHING ELSE — a storey and a plate index — so
	there is no position to spoof and no body to name. What makes it safe is the
	pair of questions asked here, both against things this machine owns:

	  1. IS THERE SUCH A PLATE? `pad_world()` reads the authored plan, so a peer
	     naming storey 12 plate 9 names nothing.
	  2. WAS THE SENDER THERE? Its last published presence position has to be
	     within `MAX_PAD_PRESS_DISTANCE` of that plate. Without this a modified
	     client would divert any guard in the building from the far side of the
	     world, which is the whole attack this verb could otherwise offer.

	A master with no tower streamed in answers `Vector3.INF` to question 1 and
	drops the packet — correct, because it also has no guard to divert.
	"""
	if _master != _you:
		return
	var msg: Dictionary = MpCodec.decode_pad(packet)
	if msg.is_empty():
		return
	var interior := get_tree().get_first_node_in_group("tower_interior")
	if interior == null or not interior.has_method("pad_world"):
		return
	var where: Variant = interior.call("pad_world", int(msg["f"]), int(msg["p"]))
	if typeof(where) != TYPE_VECTOR3:
		return
	if not _peer_state.has(from_id):
		return
	var sender: Variant = (_peer_state[from_id] as Dictionary).get("pos", null)
	if typeof(sender) != TYPE_VECTOR3:
		return
	if not MpCodec.pad_press_in_reach(sender as Vector3, where as Vector3):
		return
	_apply_guard_lure(int(msg["f"]), int(msg["p"]))


# =============================================================================
# BUDAPEST'S EXPLORED SET — the `lmk` claim, and the mask that carries it
# =============================================================================
#
# Epic `godot-test1-8gw`, bead .5. Eighteen of the city's 22 authored landmarks
# ends the run in victory, and in a room a landmark counts when ANY member walks
# into it — so the set is room-wide and the master owns it.
#
#     lmk    peer   → master   {"t":"lmk","i":int}    "I walked into slot i"
#     room   master → everyone {..., "m":int}         the union, 2 Hz, OPTIONAL
#     state  master → joiner   {..., "lm":int}        the absolute set, once
#
# THREE THINGS THIS IS NOT, each on purpose:
#
#   * NOT THE GENERIC PICKUP LIST. `clm`/`cnf` arbitrate ONE winner for a coin
#     two peers raced for; exploring is not a race and has no loser. And the join
#     replay truncates its id list at `MAX_STATE_IDS`, which would silently drop
#     landmarks out of a win condition.
#   * NOT A POSITION. The packet carries an INDEX into an AUTHORED table, so
#     there is nothing to spoof: `_receive_lmk` asks the plan whether that slot
#     exists and its own presence table whether the sender was standing there.
#     `pad`'s rule, one verb along.
#   * NOT AUTHORITY OVER THE WIN. Game over is decided per peer off the mirrored
#     mask (the captive set's rule since the break-out veto), and a peer's own
#     walk counts locally the moment it happens. The master's job is the UNION —
#     making your teammates' landmarks yours — not permission to have walked.
#
# THE MIXED-ROOM CEILING, stated because it is a real state: `build_version`
# refuses to reload a peer that is in a room, so a master on a pre-.5 build is
# reachable. It publishes no `m` and drops no packet over ours (`decode_room`
# treats a missing field as absent, never as malformed), so the room's union
# never advances: every peer still counts its OWN walk and nobody inherits a
# teammate's. Eighteen alone still wins; eighteen between two people does not.

func report_landmark_explored(index: int) -> void:
	"""
	The local player walked into Budapest landmark `index`. Tell the room.

	A no-op offline — solo the player's own `explored_mask` is the whole truth,
	which is why this returns nothing for the caller to branch on (unlike
	`request_croc_flee`, where the master taking over means the caller must NOT
	also act locally; here both always act).

	APPLIED LOCALLY AS WELL AS SENT, `request_guard_lure`'s shape: our own bit
	belongs in the room mask this peer publishes and reads, whether or not we are
	the master and whether or not the master ever answers.

	OVER THE MESH AND THE LOBBY RELAY, `_publish_captive`'s rule for
	`_publish_captive`'s reason: ICE takes seconds, and a claim made in that window
	would otherwise be lost to the room for the rest of the run — this peer's own
	bit is set for good, so nothing would ever re-send it. The relay leg reaches
	exactly the peers whose mesh is not up (normally none, so normally zero sends);
	a non-master that receives it drops it in `_receive_lmk`.
	"""
	if _state != State.IN_ROOM:
		return
	if index < 0 or index >= BudapestPlan.SLOTS.size():
		return
	_apply_explored(1 << index)
	if _master == _you:
		return   # we ARE the union; `_send_room_state` publishes it
	# ONE-SHOT SENDS ARE NOT ENOUGH HERE, and this is the one place in the file
	# where that is true (codex review 2026-09-02). Every other event verb can
	# afford to be dropped — a lost `flee` is an ability that visibly did nothing —
	# but this claim is made ONCE PER RUN by construction: `explore_landmark()` sets
	# the local bit and refuses to report the same slot again, so a claim the master
	# discards is a landmark permanently missing from the ROOM's win set. And the
	# master discards it on a case that really happens: a joiner reaching a landmark
	# before its first presence packet has arrived has no entry in the master's
	# `_peer_state`, so `_receive_lmk` has nowhere to check its position against.
	#
	# So it is remembered and re-sent by `_tick_landmark_claims()` until the
	# master's own published mask says it landed. That is an ACK we already have and
	# did not have to invent — the `room` packet's `m` is the master's truth.
	_pending_landmarks[index] = true
	_send_landmark_claim(index)


func _send_landmark_claim(index: int) -> void:
	"""
	Put one `lmk` on the wire, over BOTH transports.

	`_publish_captive`'s rule for `_publish_captive`'s reason: ICE takes seconds
	and the relay is open from `welcome`, so the relay leg is what reaches a master
	whose mesh channel is not up. It writes to peers whose mesh is down (normally
	none, so normally zero sends) and a non-master that receives one drops it in
	`_receive_lmk`.
	"""
	_send_reliable_to_master(var_to_bytes({"t": "lmk", "i": index}))
	_relay_to_negotiating({"mp": "lmk", "i": index})


func _tick_landmark_claims() -> void:
	"""
	The claim retry, on the `room` publish beat — see `report_landmark_explored()`
	for why a landmark claim is the one verb in this file that may not be dropped.

	ONE CLAIM PER TICK, and the bound is what makes the retry safe: 22 slots at
	`ROOM_SYNC_HZ` is 2 packets a second against the verb's own budget of 10, so a
	peer whose every claim is outstanding still cannot rate-limit itself out. It
	drains in index order and is normally EMPTY — a claim that landed is forgotten
	the moment the master's next `m` carries it (`_apply_explored`).

	THE SECOND JOB IS THE WIN RETRY, and it is one line because `_apply_explored`
	already pushes the mask into the player unconditionally.
	`player_controller._check_budapest_win()` refuses to decide before
	`_join_settled()`, so something has to ask again; a master that has gone quiet
	would otherwise leave a settled joiner's eighteenth landmark undecided forever.
	"""
	if _state != State.IN_ROOM:
		return
	# Re-drive the deferred win check (and re-seed a player that entered the tree
	# after us). Costs one group lookup and a popcount of at most 22 bits, twice a
	# second, and only in a room.
	_apply_explored(0)
	if _master == _you:
		# A re-election made US the union: everything outstanding is already in
		# `_explored_mask` and goes out on the next `room` packet.
		_pending_landmarks.clear()
		return
	if _pending_landmarks.is_empty():
		return
	for index: int in _pending_landmarks.keys():
		_send_landmark_claim(index)
		return


func room_explored_mask() -> Variant:
	"""
	The room's explored set, or `null` offline / before the join settles.

	`shared_bank()`'s exact shape, and the `null` carries `shared_bank()`'s exact
	meaning: a joiner is IN_ROOM from the `welcome` frame while its picture of the
	room is still arriving one snapshot at a time, so a mask read there is a
	partial one — and the epic's decision 7 is that victory is never evaluated
	before `_join_settled()`. `player_controller._check_budapest_win()` waits on
	this and is re-driven by the next `room` packet.
	"""
	if _state != State.IN_ROOM or not _join_settled():
		return null
	return _explored_mask


func _receive_lmk(from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: another peer says it walked into a Budapest landmark.

	The two questions, both asked against things this machine owns:

	  1. IS THERE SUCH A SLOT? `decode_lmk` reads the authored plan's size, so a
	     peer naming slot 40 names nothing.
	  2. WAS THE SENDER THERE? Its last published presence position has to be
	     within the slot's own radius plus `MAX_LANDMARK_CLAIM_PAD`. Without this
	     a modified client wins the run from the gate.

	A REFUSED CLAIM COSTS THE ROOM'S UNION AND NOT THE CLAIMANT'S OWN BIT, which
	is the honest reading of a peer-to-peer mesh: a modified client can always lie
	to itself, and game over is decided per peer (the captive set's rule). What the
	master protects is everybody ELSE's mask.
	"""
	if _master != _you:
		return
	var msg: Dictionary = MpCodec.decode_lmk(packet)
	if msg.is_empty():
		return
	if not _peer_state.has(from_id):
		return
	var sender: Variant = (_peer_state[from_id] as Dictionary).get("pos", null)
	if typeof(sender) != TYPE_VECTOR3:
		return
	var index: int = int(msg["i"])
	var slot: Dictionary = BudapestPlan.SLOTS[index]
	if not MpCodec.landmark_claim_in_reach(
			sender as Vector3, slot["pos"] as Vector3, float(slot["radius"])):
		return
	_apply_explored(1 << index)


func _apply_explored(mask: int) -> void:
	"""
	Fold `mask` into the room's explored set and mirror it into the player.

	OR AND NEVER ASSIGN — the one gate every source goes through (our own walk, a
	peer's `lmk`, the master's `room` packet, a join snapshot), so no two of them
	can drift and none of them can undo another.

	THE PLAYER IS PUSHED UNCONDITIONALLY, even when nothing moved, and that is
	load-bearing rather than lazy: `player_controller._check_budapest_win()` REFUSES
	to decide a win before `_join_settled()`, so the packet that re-drives it is the
	next `room` packet — which usually carries a mask this peer already has.
	`adopt_explored_mask()` is an OR and a popcount of at most 22 bits.
	"""
	_explored_mask |= mask & ((1 << BudapestPlan.SLOTS.size()) - 1)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("adopt_explored_mask"):
		player.call("adopt_explored_mask", _explored_mask)


func request_croc_kill(id: int) -> bool:
	"""
	Giant Teibi crushed a crocodile: ask the room to kill THAT crocodile
	everywhere.

	Returns true when the room has taken it over — the caller must then NOT run
	its own squash, because the master's `dead` broadcast frees the body on every
	peer including this one. FALSE OFFLINE, and false whenever the request could
	not actually leave (no mesh, master's channel still negotiating), so the
	caller falls through to today's local squash on one test rather than leaving a
	crocodile the player visibly stood on still walking around.
	"""
	if _state != State.IN_ROOM or _rtc == null:
		return false
	if _dead_crocs.has(id):
		# Already dead room-wide, but this body is somehow still standing (a chunk
		# that regenerated between the broadcast and now). Free it here rather than
		# answering true and leaving it: the packet that killed it has been and gone.
		_apply_dead(id)
		return true
	if _master == _you:
		_resolve_kill(id)
		return true
	return _send_reliable_to_master(var_to_bytes({"t": "kill", "id": id}))


func _resolve_kill(id: int) -> void:
	"""
	MASTER ONLY: rule that a crocodile is dead, tell the room, and kill our own
	copy through the same path everyone else takes.

	First kill wins and a repeat is dropped silently — the same shape
	`_resolve_claim()` uses for a pickup, one set per thing being arbitrated.
	"""
	if _dead_crocs.has(id):
		return
	_broadcast_reliable(var_to_bytes({"t": "dead", "id": id}))
	_apply_dead(id)


func _apply_dead(id: int) -> void:
	"""
	Every peer's half of a kill: remember the id and run the ORDINARY squash on
	the local body, so a crush READS as a crush on every screen rather than as a
	crocodile blinking out.

	The id is recorded even when no body is found, which is the common case and
	NOT an error: this peer may never have generated that chunk, and the record is
	what stops the crocodile walking back in when it does
	(`piglet_crocodile_ai._ready()` asks `is_croc_dead`).
	"""
	_dead_crocs[id] = true
	var croc: Node = _croc_by_id(id)
	if croc == null:
		# At most one group scan, and only on a miss — see `_rebuild_croc_cache()`.
		_rebuild_croc_cache()
		croc = _croc_by_id(id)
	# Drop the sync bookkeeping either way: a dead crocodile is nobody's to drive,
	# and the cache holds a hard reference to a node about to free itself.
	_synced_crocs.erase(id)
	_croc_seen.erase(id)
	if croc != null and croc.has_method("squash_and_die"):
		croc.squash_and_die()


func _receive_kill(_from_id: String, packet: Dictionary) -> void:
	"""
	MASTER ONLY: a peer's crush. One int to validate, and nothing to bound — the
	id space is the whole of `String.hash()`, so an id naming no crocodile simply
	finds nothing and costs one dictionary write.
	"""
	if _master != _you:
		return
	if typeof(packet.get("id", null)) != TYPE_INT:
		return
	_resolve_kill(int(packet["id"]))


func _receive_dead(from_id: String, packet: Dictionary) -> void:
	"""
	The master's kill ruling. ONLY the master's is accepted, the same authority
	rule `_receive_confirm()` and `_receive_croc_sync()` enforce: the mesh is
	peer-to-peer, so without it any member could free every crocodile in the room.
	"""
	if from_id != _master:
		return
	if typeof(packet.get("id", null)) != TYPE_INT:
		return
	_apply_dead(int(packet["id"]))


func is_croc_dead(id: int) -> bool:
	"""
	Whether the ROOM has already killed this crocodile. Asked once per crocodile
	AT SPAWN, never per frame — the same shape and placement `coin.gd` uses for
	`is_coin_collected` — so a chunk regenerating on a peer that saw the kill does
	not walk the crocodile back in. False offline, where the set is always empty
	anyway.

	The set IS replayed in the join snapshot (`_recent_dead_ids()` on the way out,
	`_absorb_dead()` on the way in), so a peer joining after a crush no longer
	sees the crocodile alive again. What remains is `_recent_dead_ids()`'s
	`MAX_STATE_IDS` ceiling, documented there. A peer that left and rejoined
	starts from an empty set of its own and re-learns the room's from the
	incumbents' snapshots — the same answer by a different route.
	"""
	return _state == State.IN_ROOM and _dead_crocs.has(id)
