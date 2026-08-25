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

## Sanity bounds on a presence packet's position and speed. Generous by design —
## a real run is a few km along +X — because these exist to reject hostile
## garbage, not to police where a peer may stand. See `decode_presence()`.
const MAX_PRESENCE_COORD: float = 1.0e7
const MAX_PRESENCE_SPEED: float = 1.0e4

## Caps on a join snapshot — see `decode_state()`. `MAX_STATE_IDS` bounds BOTH
## ends of BOTH id lists — the collected-coin set and the crushed-crocodile kill
## list, each in the one we send and the one we accept.
## `MAX_STATE_COUNTER` is a sanity bound on the coin/life/distance counters,
## generous by design because it exists to reject hostile garbage, not to police
## how long a run may get.
const MAX_STATE_IDS: int = 2048
const MAX_STATE_COUNTER: int = 1000000000

## Coin ids are `hash()` output, so 32 bits — but they cross the relay as JSON
## doubles, and `int()` on a value past a double's exact-integer range is
## undefined (on wasm the float→int trunc can trap the module outright). 2⁵³ is
## that range, so anything beyond it is refused before the cast.
const MAX_STATE_ID_MAGNITUDE: float = 9007199254740992.0

## The world seed's accepted range — `endless_terrain._roll_run_seed()` takes it
## from `RandomNumberGenerator.randi()`, so 0…2³²−1 is every seed that can
## honestly appear. It arrives over the relay as a JSON double, and a master is
## only the oldest member of a room whose code is public over `/rooms`, so this
## is peer input like any other: `1e999` parses to `INF`, and `int(INF)` is the
## undefined cast `MAX_STATE_ID_MAGNITUDE` exists to keep out (on wasm the
## float→int trunc can trap the module outright).
const MAX_RUN_SEED: float = 4294967295.0

## State byte carried by a crocodile sync entry (see `_send_croc_sync()` and
## `decode_croc_sync()`). Declared HERE, once, so the encoder on the master and
## the decoder in `piglet_crocodile_ai.set_remote_state()` cannot drift apart.
const CROC_FLAG_CHASING: int = 1
const CROC_FLAG_FLEEING: int = 2
const CROC_FLAG_PAUSED: int = 4
const CROC_FLAG_BITING: int = 8

## Most crocodile entries one sync packet may carry — see `decode_croc_sync()`.
## Generous by design: the master only ever sends the crocs awake around one
## peer, which is a couple of dozen. Like `MAX_STATE_IDS`, this exists to reject
## hostile garbage before it is walked, not to police the size of the pack.
const MAX_CROC_SYNC: int = 192

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
const VERB_BUDGET_PER_SEC: Dictionary = {
	"clm": 30, "kill": 10, "flee": 4, "croc": 40, "cnf": 150, "dead": 60,
}

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
## `{"coins": int, "spent": int, "dist": int, "pos": Vector3}`, seeded by that
## peer's join snapshot and kept current by every presence packet afterwards.
## Both are room-scoped: `leave()` empties them and `report_coin_collected()`
## refuses to record while offline, so a solo session allocates nothing here no
## matter how many coins it banks.
var _collected_ids: Dictionary = {}
var _peer_state: Dictionary = {}

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

## The FROZEN contributions of members who have left. A departing peer's coins
## and spent lives are folded in here rather than dropped: dropping them would
## shrink the room's bank in front of everyone and — much worse — REFUND the
## lives that peer spent. Room-scoped like the two above.
var _gone_coins: int = 0
var _gone_spent: int = 0

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
# PEER ID MAPPING
# =============================================================================

static func peer_int_id(lobby_id: String) -> int:
	"""
	Turn the lobby's 16-hex-character peer id into the `int` id
	`WebRTCMultiplayerPeer` requires.

	The first 7 hex digits give 28 bits, and `+ 2` puts the result safely clear of
	the two ids MultiplayerPeer reserves (0 = broadcast/none, 1 = server). Every
	peer derives every *other* peer's int id with this same pure function, so the
	whole mesh agrees on the numbering with **no extra protocol** — nobody has to
	be told what to call anybody.

	ponytail: two of four peers colliding on the same 28-bit prefix is a ~2e-7
	birthday chance. The upgrade path, if it ever matters, is having the room
	master assign small ids over the relay — which costs a round trip that this
	buys for free.
	"""
	return ("0x" + lobby_id.substr(0, 7)).hex_to_int() + 2


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
	_state_received = {}
	_first_member = true
	_join_applied = false
	_gone_coins = 0
	_gone_spent = 0
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
	var err: int = _rtc.create_mesh(peer_int_id(_you))
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
	# the ids it banked itself, while the shared bank, lives and distance are a
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
		_gone_spent += int(gone.get("spent", 0))
		_peer_state.erase(id)
	if _avatars.has(id):
		(_avatars[id] as RemoteAvatar).queue_free()
		_avatars.erase(id)
	_pending_signals.erase(id)
	if _connections.has(id):
		(_connections[id] as WebRTCPeerConnection).close()
		_connections.erase(id)
		# Only ever remove a peer the MESH still holds — `remove_peer()` errors on
		# an unknown id. `_connections` is not that answer: a peer that left in
		# the /ice window was never added, and `WebRTCMultiplayerPeer.poll()`
		# drops failed/closed connections itself, so a peer whose ICE never
		# completed is already gone from the mesh while `_connections` still
		# lists it. Ask the mesh.
		if _rtc != null and _rtc.has_peer(peer_int_id(id)):
			_rtc.remove_peer(peer_int_id(id))

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
			_resolve_claim(pickup_id, peer_int_id(_you), int(claim["n"]), int(claim["v"]))

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
		var pos: Vector3 = state["pos"] as Vector3
		var dist_sq: float = from.distance_squared_to(pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = pos
	return best


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
	"""
	if not my_hero().is_empty():
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

	if _rtc.add_peer(conn, peer_int_id(id)) != OK:
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
					or not _is_number(payload.get("index", null)):
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
		"state":
			# A join snapshot from an incumbent. THE THIRD TRUST BOUNDARY in
			# this file: `decode_state()` validates it whole, and anything that
			# fails any part of it is dropped whole.
			# One per sender for the room's life (see `_state_received`). A peer
			# that drops and reconnects gets a fresh lobby id, so this can never
			# refuse a snapshot the protocol actually wanted to send.
			if _state_received.has(from):
				return
			var snapshot: Dictionary = decode_state(payload)
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


static func _is_number(value: Variant) -> bool:
	"""JSON gives ints and floats interchangeably, so accept either."""
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


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
	if _has_seed or not _is_number(payload.get("seed", null)):
		return
	var raw_seed: float = float(payload["seed"])
	if not is_finite(raw_seed) or raw_seed < 0.0 or raw_seed > MAX_RUN_SEED:
		push_warning("MpManager: dropping out-of-range world seed")
		return
	_room_seed = int(raw_seed)
	_has_seed = true
	status.emit("Shared world seed received")

	# A MID-RUN JOINER MUST NOT BE RESET TO THE ORIGIN. Once a snapshot is in
	# hand the group's position is known, so hand straight over to the join
	# placement — it rebuilds the terrain around the anchor itself and must not
	# be preceded by a rebuild around (0,0) plus a teleport to spawn. The two
	# lines below stay the HOST / no-snapshot-yet path; a snapshot that arrives
	# after this calls `_apply_join_placement()` in its own turn.
	if _can_join_place():
		_apply_join_placement()
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
	# (`new_run`'s `around` builds that chunk plus ring 1 synchronously — the
	# guarantee a mid-run joiner already relies on).
	if not _arriving() and player != null and terrain != null \
			and terrain.has_method("new_run") and terrain.has_method("world_to_chunk"):
		terrain.new_run(_room_seed, terrain.world_to_chunk(player.global_position))
		return

	if terrain != null and terrain.has_method("new_run"):
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
	`new_run`'s `around` parameter puts the synchronously-built safety ring where
	the player is about to stand, so a joiner does not spend a frame over unbuilt
	ground kilometres from the origin.
	"""
	if not _can_join_place():
		return
	_join_applied = true

	var anchor: Vector3 = _join_anchor()
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("new_run") and terrain.has_method("world_to_chunk"):
		terrain.new_run(_room_seed, terrain.world_to_chunk(anchor))

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
	Where to arrive: the centroid of the snapshot positions, unless the group is
	spread wider than `GROUP_SPREAD_MAX`, in which case the MASTER's position —
	the centroid of two players who have gone opposite ways is empty ground
	between them, and arriving beside one player beats arriving beside none.
	A master that sent no snapshot (it may have joined after us and not yet
	replied) leaves the centroid as the fallback.

	`_peer_state` holds only other members, and this is only reached with at
	least one entry in it, so the divide is safe.
	"""
	var centroid: Vector3 = Vector3.ZERO
	for id: String in _peer_state:
		centroid += _peer_state[id]["pos"] as Vector3
	centroid /= float(_peer_state.size())

	for id: String in _peer_state:
		if (_peer_state[id]["pos"] as Vector3).distance_to(centroid) > GROUP_SPREAD_MAX:
			if _peer_state.has(_master):
				return _peer_state[_master]["pos"] as Vector3
			return centroid
	return centroid


# =============================================================================
# JOIN-TIME STATE REPLAY
# =============================================================================
#
# A peer joining a game already in progress has to be told what it missed: which
# coins are gone, how much the room has banked, how many lives it has spent, how
# far it has run, and where everybody is standing. That rides the LOBBY RELAY
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
	var spent: int = 0
	var dist: int = 0
	if player != null:
		pos = player.global_position
		# `own_coins` / `own_lives_spent` are this peer's OWN contributions,
		# which is what the room sums; `coins_collected` is the DISPLAYED number
		# and in a room that is already the room's total, so it must not be read
		# here. The `in` guards are the ones `_send_presence()` uses, for the
		# same reason: a player scene run standalone still answers something sane.
		coins = int(player.get("own_coins")) if "own_coins" in player else 0
		spent = int(player.get("own_lives_spent")) if "own_lives_spent" in player else 0
		dist = int(player.get("run_distance")) if "run_distance" in player else 0

	_lobby.send_signal_to(id, {
		"mp": "state",
		"cc": coins,
		"ls": spent,
		"dd": dist,
		"px": pos.x,
		"py": pos.y,
		"pz": pos.z,
		# The FROZEN share of members who left before the joiner arrived. Presence
		# only ever carries a live member's own numbers, so without these the
		# joiner's `shared_bank`/`shared_lives_spent` would be short by exactly
		# `_gone_*` for the room's life — a permanently smaller bank and fewer
		# hearts than everyone else is looking at.
		"gc": _gone_coins,
		"gs": _gone_spent,
		"ids": _recent_collected_ids(),
		# The room's KILL LIST, replayed for the same reason `ids` is: a joiner's
		# own terrain generates every crocodile the seed describes, including the
		# ones giant Teibi already crushed, so without this the newcomer walks into
		# a pack containing animals nobody else can see. Bounded like `ids`.
		"dead": _recent_dead_ids(),
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
	ids = ids.slice(maxi(0, ids.size() - MAX_STATE_IDS))  # keep the newest tail
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
	many, never a wrong bank or a wrong heart count). Reaching that cap means
	2048 crushes in one room, each of which needs a player standing on a
	crocodile as giant Teibi. The upgrade path is `_recent_collected_ids()`'s:
	filter by distance to the join anchor rather than by age.
	"""
	var ids: Array = _dead_crocs.keys()
	ids = ids.slice(maxi(0, ids.size() - MAX_STATE_IDS))  # keep the newest tail
	ids.reverse()  # ... most recent first
	return ids


func _receive_state(from: String, snapshot: Dictionary) -> void:
	"""Merge one validated join snapshot. `snapshot` came from `decode_state()`."""
	_peer_state[from] = {
		"coins": snapshot["cc"],
		"spent": snapshot["ls"],
		"dist": snapshot["dd"],
		"pos": snapshot["pos"],
	}
	# Adopt the room's frozen departed-member share with `maxi`, NOT `+=`: every
	# incumbent replays the same figure, so adding them would multiply it by the
	# number of snapshots received. `maxi` is also what keeps this correct once a
	# peer leaves AFTER we joined — we then fold that peer in ourselves, exactly
	# like the incumbents do, and the two paths converge on the same number.
	_gone_coins = maxi(_gone_coins, int(snapshot["gc"]))
	_gone_spent = maxi(_gone_spent, int(snapshot["gs"]))
	_absorb_collected(snapshot["ids"])
	# APPLYING THE SNAPSHOT'S WORLD-STATE DELTAS HERE IS THE JOIN EVENT ITSELF,
	# not a replay of somebody else's events: the `_state_received` latch above
	# admits exactly one snapshot per sender for the room's life, so neither sweep
	# can ever run a second time for the same peer.
	_absorb_dead(snapshot["dead"])
	# The snapshot may be the last thing the placement was waiting on (the seed
	# can equally well be). Both call in; the latch inside decides.
	_apply_join_placement()


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


static func decode_state(payload: Dictionary) -> Dictionary:
	"""
	The join-snapshot parser, and the THIRD trust boundary in this file.

	The lobby never inspects a relayed payload — that opacity is what keeps game
	logic off the server — so this is unvalidated peer input, arriving over JSON
	where *every* number is a float. Returns the validated snapshot
	(`{"cc": int, "ls": int, "dd": int, "gc": int, "gs": int, "pos": Vector3,
	"ids": Array[int], "dead": Array[int]}`) or
	an EMPTY DICTIONARY: trusted whole or dropped whole, exactly like
	`decode_presence()`, and static and `_rtc`-free for the same reason — so
	scripts/mp_selfcheck.gd can beat on it with a fistful of hostile payloads.
	"""
	for key: String in ["cc", "ls", "dd", "px", "py", "pz"]:
		if not _is_number(payload.get(key, null)):
			return {}

	# Finiteness is tested BEFORE every cast, for the reason `decode_presence()`
	# folds `c` into its finite gate: `int(NAN)` is undefined and on wasm the
	# trunc can trap the module, taking the tab down before any range check runs.
	var counters: Array[int] = []
	for key: String in ["cc", "ls", "dd"]:
		var raw: float = float(payload[key])
		if not is_finite(raw) or raw < 0.0 or raw > float(MAX_STATE_COUNTER):
			return {}
		counters.append(int(raw))

	# The departed-members totals. MISSING IS NOT MALFORMED — the same rule
	# `decode_presence()` applies to its counters: a peer on an older build sends
	# no `gc`/`gs`, and dropping its whole snapshot would cost the joiner a
	# position and an id list over two optional fields. Present-but-bad still
	# drops the payload, like every other field here.
	for key: String in ["gc", "gs"]:
		if not payload.has(key):
			counters.append(0)
			continue
		var raw: float = float(payload[key]) if _is_number(payload[key]) else NAN
		if not is_finite(raw) or raw < 0.0 or raw > float(MAX_STATE_COUNTER):
			return {}
		counters.append(int(raw))

	var pos: Vector3 = Vector3(
		float(payload["px"]), float(payload["py"]), float(payload["pz"])
	)
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	# Same bound as a presence position, and for the same reason: this feeds the
	# join placement, and an absurd-but-finite anchor would teleport the joiner
	# somewhere the terrain will never build.
	if absf(pos.x) > MAX_PRESENCE_COORD or absf(pos.y) > MAX_PRESENCE_COORD \
			or absf(pos.z) > MAX_PRESENCE_COORD:
		return {}

	if typeof(payload.get("ids", null)) != TYPE_ARRAY:
		return {}
	var ids: Variant = _decode_id_list(payload["ids"])
	if ids == null:
		return {}

	# The kill list. MISSING IS NOT MALFORMED, the rule `gc`/`gs` above follow and
	# for the same reason: a peer on a build without this field is still worth its
	# position, its counters and its coin ids. Present-but-not-an-array, or one bad
	# entry, still drops the whole snapshot.
	var dead: Variant = []
	if payload.has("dead"):
		if typeof(payload["dead"]) != TYPE_ARRAY:
			return {}
		dead = _decode_id_list(payload["dead"])
		if dead == null:
			return {}

	return {
		"cc": counters[0],
		"ls": counters[1],
		"dd": counters[2],
		"gc": counters[3],
		"gs": counters[4],
		"pos": pos,
		"ids": ids,
		"dead": dead,
	}


static func _decode_id_list(raw: Array) -> Variant:
	"""
	Validate one snapshot id array — the coin ids or the crocodile kill list, which
	are the same kind of thing over the same wire and so get one validator rather
	than two that can drift.

	Returns `Array[int]`, or `null` meaning "drop the whole snapshot".

	An over-long list is TRUNCATED, not rejected — the one place this parser keeps
	part of a payload. The sender orders both lists most-recent-first, so the head
	is the part nearest the joiner, and a snapshot whose list is too long is still
	worth its position and its counters, which are what the join placement and the
	shared bank actually need. A malformed *entry* is a different thing and still
	drops the whole snapshot.
	"""
	var ids: Array[int] = []
	for i: int in range(mini(raw.size(), MAX_STATE_IDS)):
		var entry: Variant = raw[i]
		if not _is_number(entry):
			return null
		var value: float = float(entry)
		if not is_finite(value) or absf(value) > MAX_STATE_ID_MAGNITUDE:
			return null
		ids.append(int(value))
	return ids


# =============================================================================
# SHARED TOTALS
# =============================================================================
# The room's bank, spent lives and distance are the SUM (or, for distance, the
# max) of every member's own contribution, with no authority and no round trips:
# each peer broadcasts its own absolute numbers and each peer adds them up. Every
# reader gets the same answer within one presence interval, and a peer that
# leaves has its share frozen rather than dropped.
#
# All three take the CALLER's own contribution as a parameter and return `null`
# offline, so the player falls through to today's solo behaviour with one
# `== null` test and the manager never has to reach into the player.

# THERE IS NO "retired contribution" HERE, and that is deliberate. "Play Again"
# inside a room LEAVES the room first (see `player_controller.restart_game`),
# because the shared hearts cannot recover from a local wipe — so this peer's
# contribution is always simply its live `own_coins` / `own_lives_spent`, and a
# restart never has to be hidden from the room's totals.

func _contributing() -> bool:
	"""
	Whether this peer's own coins / spent lives / distance belong in the room's
	totals yet.

	A MID-RUN JOINER'S SOLO TALLY IS NOT THE ROOM'S. `join_at()` zeroes
	`own_coins` / `own_lives_spent` / `own_distance` / `run_distance` for exactly
	that reason — but it only runs at PLACEMENT, which waits on the seed and on
	every incumbent's snapshot, while presence starts the moment the mesh
	connects. Nothing orders those two, so without this gate a joiner publishes
	its old world's numbers in the window between: `dd` is folded in with `maxi`,
	so a 3 km solo run raises the room's distance PERMANENTLY for everyone (a max
	has no way back down), and `lv` is subtracted from the room's shared hearts,
	so joining after two solo deaths takes two hearts off the whole room — and
	can drive it to zero and game-over everybody.

	Reading it locally is the same bug from the other end: a joiner who died solo
	sums its own `own_lives_spent` into `shared_lives_spent()`, computes zero
	hearts in a healthy room and fires `_check_shared_game_over()` on itself,
	which only the (seed-gated) placement can undo.

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
	relayed snapshot at a time — and each snapshot carries one peer's coins AND
	its spent lives, so a HALF-ARRIVED SET IS NOT A PARTIAL AVERAGE: it can be all
	of the room's deaths and none of the bank that paid for the extra hearts. A
	joiner reading it mid-fill computes zero hearts in a perfectly healthy room,
	`_check_shared_game_over()` fires, and the Game Over screen goes up — undone
	only if the placement runs, so a joiner still waiting on the seed sits there
	for the whole 20 s `seed_req` budget, or forever if the seed never lands.

	Until this is true the three getters below answer `null` and the player falls
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


func shared_lives_spent(own_spent: int) -> Variant:
	"""Lives spent by everyone who has been in this room, or `null` offline /
	before the join settles (see `_join_settled`)."""
	if _state != State.IN_ROOM or not _join_settled():
		return null
	var total: int = (own_spent if _contributing() else 0) + _gone_spent
	for state: Dictionary in _peer_state.values():
		total += int(state.get("spent", 0))
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


static func shared_lives_from(bank: int, spent: int, max_lives: int, per_extra: int, cap: int) -> int:
	"""
	The room's remaining lives: the starting hearts, plus one per `per_extra`
	coins the room has banked, minus every life anyone has spent, clamped into
	[0, cap]. Pure and static so scripts/mp_selfcheck.gd can pin the arithmetic
	without a room.

	ponytail: STATELESS, so it cannot reproduce solo exactly, and the difference
	is worth knowing. Solo grants at the moment a threshold is crossed and DROPS
	the grant if `lives` is already at the cap (player_controller.collect_coin's
	`if lives < LIVES_CAP`), i.e. overshoot is burnt. Here the overshoot is banked:
	while `bank / per_extra - spent` exceeds the cap headroom the HUD pins at `cap`
	and a death changes nothing visible, so a room that banks fast becomes hard to
	lose. No formula over (bank, spent) alone can fix that — solo's outcome depends
	on the ORDER of grants and deaths — and the obvious alternative
	(`mini(max_lives + bank / per_extra, cap) - spent`) trades it for a worse one:
	the room would get exactly `cap` lives for the whole run, and coins banked
	after a death would stop buying hearts back, which solo definitely does allow.
	The upgrade path is the master keeping the room's hearts as real state and
	broadcasting it, the way it already owns the room's streak.
	"""
	if per_extra <= 0:
		return clampi(max_lives - spent, 0, cap)  # No extra-life threshold: just the base.
	return clampi(max_lives + bank / per_extra - spent, 0, cap)


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
		# `_gone_*` to future joiners as `gc`/`gs`, which they merge alongside that
		# same peer's own snapshot and presence, counting its coins and its SPENT
		# LIVES twice (hearts the room actually has, gone from the joiner's HUD).
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
		if _rtc.has_peer(peer_int_id(id)):
			_rtc.remove_peer(peer_int_id(id))


func _send_presence() -> void:
	"""
	Broadcast one presence packet: where the local player is, which way it faces,
	who it is playing, how fast it is going and whether it is on the ground —
	everything `RemoteAvatar` needs to draw a convincing runner — plus this peer's
	own coins, spent lives and distance, which are what the room's shared totals
	are summed from.

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

	# `cc` / `lv` / `dd` are this peer's OWN contributions to the room's shared
	# bank, spent lives and distance — ABSOLUTE values, never deltas, so the
	# unreliable channel is self-healing: a dropped packet is corrected 66 ms
	# later instead of leaving the totals permanently short. Note `own_coins`,
	# not `coins_collected`: in a room the latter is already the room's total and
	# summing it would compound. The `in` guards keep a standalone player scene
	# answering something sane, exactly like `c` above.
	# Until the join lands, this peer contributes NOTHING to the room's totals —
	# its counters still describe the solo world it came from. See
	# `_contributing()`; publishing them early raises the room's distance
	# permanently and spends the room's hearts on deaths that happened elsewhere.
	var mine: bool = _contributing()
	var state: Dictionary = {
		"p": player.global_position,
		"y": player.rotation.y,
		"c": int(player.get("current_character_index")) if "current_character_index" in player else 0,
		"s": speed,
		"g": player.is_on_floor() if player.has_method("is_on_floor") else true,
		"cc": int(player.get("own_coins")) if mine and "own_coins" in player else 0,
		"lv": int(player.get("own_lives_spent")) if mine and "own_lives_spent" in player else 0,
		"dd": int(player.get("run_distance")) if mine and "run_distance" in player else 0,
	}

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
			if peer_int_id(id) == from_int:
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

		var kind: String = packet_kind(packet)
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

		var state: Dictionary = _decode_presence_dict(packet)
		if state.is_empty():
			continue

		avatar.visible = true
		avatar.receive_state(state["p"], state["y"], state["c"], state["s"], state["g"])
		# Keep this peer's contribution to the shared totals current. The join
		# snapshot only bootstraps it; from here on presence carries it, and the
		# values being absolute means a lost packet costs nothing.
		_peer_state[from_id] = {
			"coins": state["cc"],
			"spent": state["lv"],
			"dist": state["dd"],
			"pos": state["p"],
		}


static func packet_kind(packet: Dictionary) -> String:
	"""
	Which kind of mesh packet this is: `""` for presence, otherwise the verb.

	THE WHOLE BACKWARD-COMPATIBILITY RULE LIVES HERE. A phase-3/4 peer sends no
	`"t"` key, so its packet must land on the presence path; a packet carrying a
	verb — including one from a LATER build that this one has never heard of —
	must NOT, because the fields beside the verb can be a perfectly valid presence
	packet and would decode there. Pulled out as a pure static rather than left
	inline so `scripts/mp_selfcheck.gd` can pin both directions: driving
	`_receive_mesh_verb()` directly cannot test this, since that function has no
	presence branch to leak through and the assertion passes no matter what the
	dispatch does.
	"""
	return str(packet["t"]) if packet.has("t") else ""


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
	if _master != _you and not _is_mesh_peer_connected(peer_int_id(_master)):
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
		_resolve_claim(id, peer_int_id(_you), count, value)
		return true
	_pending_claims[id] = {"n": count, "v": value, "age": 0.0, "tries": 1}
	_send_claim(id, count, value)
	return true


func room_multiplier() -> Variant:
	"""
	The room's current coin multiplier, or `null` offline so
	`player_controller.get_streak_multiplier()` falls through to its own on one
	test — the same trick phase 4 used for the bank and the hearts, which is why
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
	if _master != _you and not _is_mesh_peer_connected(peer_int_id(_master)):
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

	var confirm: Dictionary = {
		"t": "cnf", "id": id, "by": by_int, "a": awarded, "m": _room_multiplier,
	}
	_broadcast_reliable(var_to_bytes(confirm))
	# And apply it to ourselves: the master is a player too, and this is the only
	# path that banks a pickup it claimed.
	_apply_confirm(id, by_int, awarded, _room_multiplier)


func _apply_confirm(id: int, by_int: int, awarded: int, multiplier: int) -> void:
	"""
	Every peer's half of a confirm: the pickup is gone room-wide, and whoever won
	it banks the amount the MASTER already multiplied.

	`_absorb_collected` does double duty here — it records the id AND sweeps the
	live world for a coin still holding it, which is what makes the confirm
	arrival order irrelevant (a coin spawned afterwards asks `is_coin_collected()`
	in its own `_ready()`).
	"""
	_absorb_collected([id])
	_pending_claims.erase(id)
	_room_multiplier = multiplier
	_room_streak_deadline_msec = Time.get_ticks_msec() + int(PLAYER_SCRIPT.STREAK_WINDOW * 1000.0)
	if by_int != peer_int_id(_you):
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("bank_awarded"):
		player.bank_awarded(awarded)


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
	var master_int: int = peer_int_id(_master)
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
	extra-life threshold and the print, and in a room it reads the ROOM's
	multiplier through `get_streak_multiplier()` anyway.
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
	_resolve_claim(int(packet["id"]), peer_int_id(from_id), count, value)


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
	if awarded < 0 or awarded > MAX_STATE_COUNTER:
		return
	# The multiplier only ever feeds the HUD suffix, but it is clamped to the range
	# the game can actually produce so a hostile master cannot print "x9000".
	var multiplier: int = clampi(int(packet["m"]), 1, 1 + PLAYER_SCRIPT.STREAK_MAX_BONUS)
	_apply_confirm(int(packet["id"]), int(packet["by"]), awarded, multiplier)


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
# ponytail: THE COVERAGE CEILING is "crocodiles further than the master's own
# render distance are simulated locally". The master only simulates the chunks
# ITS terrain has loaded (`render_distance` × 50 m = 150 m on web, 250 m on
# desktop), so a peer beyond that gets no samples for its neighbours and they
# fall back to local simulation after CROC_SYNC_TIMEOUT — i.e. today's behaviour,
# for exactly the peers who are too far apart to see each other (150 m is well
# past the fog). Nothing duplicates, nothing vanishes. The upgrade path is a
# terrain hook the master calls with the union of peer positions,
# `terrain.set_focus_points(points: Array[Vector3])`, so chunks stay loaded around
# every peer rather than only around the local player.

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
		var pid: int = peer_int_id(id)
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
		if "lod_active" in croc and not croc.lod_active:
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
		var flags: int = _croc_flags(croc)
		# `rotation.y`, not a global yaw: `set_remote_state()` writes `rotation.y`
		# on the far side, and a chunk (the crocodile's parent) is never rotated,
		# so the two are the same number and the round trip is symmetric.
		var yaw: float = body.rotation.y

		for t: int in count:
			if buf_ids[t].size() >= MAX_CROC_SYNC:
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


static func _croc_flags(croc: Node) -> int:
	"""
	Pack one crocodile's coarse behaviour into the state byte.

	Read back through the same CROC_FLAG_* constants in
	`piglet_crocodile_ai.set_remote_state()`, which is why they live in this file
	once — an encoder and a decoder that name their bits separately drift.
	"""
	var flags: int = 0
	if "is_chasing" in croc and croc.is_chasing:
		flags |= CROC_FLAG_CHASING
	if "is_fleeing" in croc and croc.is_fleeing:
		flags |= CROC_FLAG_FLEEING
	if "is_paused" in croc and croc.is_paused:
		flags |= CROC_FLAG_PAUSED
	if "is_biting" in croc and croc.is_biting:
		flags |= CROC_FLAG_BITING
	return flags


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
	var sync: Dictionary = decode_croc_sync(packet)
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
#     kill   peer   → master   {"t":"kill","id":int}           giant Teibi's crush
#     dead   master → everyone {"t":"dead","id":int}           the kill ruling
#
# THERE IS DELIBERATELY NO `flee` BROADCAST: `is_fleeing` is already a bit in the
# sync packet's flag byte, so the master applying `flee_from()` reaches every peer
# 100 ms later through machinery that already exists. A kill needs its own
# broadcast only because it FREES a node, which no amount of transform sync can
# express.

func request_croc_flee(origin: Vector3, duration: float, radius: float = 0.0) -> bool:
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
	_apply_flee(origin, duration, radius)
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
	if not _is_number(packet.get("x", null)) or not _is_number(packet.get("y", null)) \
			or not _is_number(packet.get("z", null)) or not _is_number(packet.get("d", null)):
		return
	var origin := Vector3(float(packet["x"]), float(packet["y"]), float(packet["z"]))
	var duration: float = float(packet["d"])
	# Finiteness is checked BEFORE anything is derived from these, the same rule
	# decode_presence() states: a NaN origin would poison every flee heading it
	# touched, and on wasm a non-finite float→int trunc can trap the module.
	if not is_finite(origin.x) or not is_finite(origin.y) or not is_finite(origin.z):
		return
	if absf(origin.x) > MAX_PRESENCE_COORD or absf(origin.y) > MAX_PRESENCE_COORD \
			or absf(origin.z) > MAX_PRESENCE_COORD:
		return
	if not is_finite(duration) or duration <= 0.0 or duration > MAX_FLEE_DURATION:
		return
	# `r` is optional (a phase-5.0 peer sends none) and bounded like everything
	# else here; a missing or malformed one reads as 0.0 = unbounded, which is
	# what that older peer meant.
	var radius: float = 0.0
	if _is_number(packet.get("r", null)):
		radius = float(packet["r"])
		if not is_finite(radius) or radius < 0.0 or radius > MAX_PRESENCE_COORD:
			return
	# tracks_player FALSE: the caster is on another screen, so the crocodiles must
	# run from `origin`, not from our own player.
	_apply_flee(origin, duration, radius, false)


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


static func decode_presence(bytes: PackedByteArray) -> Dictionary:
	"""
	The presence packet parser, and the whole trust boundary in one pure function.

	Returns the validated state, or an EMPTY DICTIONARY for anything that fails —
	a packet is trusted whole or dropped whole, there is no partial trust. Static
	and `_rtc`-free so scripts/mp_selfcheck.gd can hold it to that with a fistful
	of malformed byte arrays.

	Kept as the byte-array entry point even though `_receive_mesh_packets()` now
	decodes once and dispatches on `"t"`: the selfcheck pins this signature, and
	the validation itself lives in `_decode_presence_dict()` so there is ONE
	validator rather than two that can drift.
	"""
	var decoded: Variant = bytes_to_var(bytes)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	return _decode_presence_dict(decoded as Dictionary)


static func _decode_presence_dict(state: Dictionary) -> Dictionary:
	"""
	Validate an already-decoded presence Dictionary. See `decode_presence()` for
	the contract: whole or nothing, `{}` on any failure.
	"""
	if typeof(state.get("p", null)) != TYPE_VECTOR3 \
			or typeof(state.get("g", null)) != TYPE_BOOL \
			or not _is_number(state.get("y", null)) \
			or not _is_number(state.get("s", null)) \
			or not _is_number(state.get("c", null)):
		return {}

	var pos: Vector3 = state["p"]
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
		return {}
	var yaw: float = float(state["y"])
	var speed: float = float(state["s"])
	# `c` is folded into the SAME gate rather than trusted up to its range check:
	# `_is_number` accepts a float, and `int(NAN)` is undefined — on wasm the
	# float→int trunc can trap the module outright, so one hostile packet would
	# take the tab down before `char_index < 0` ever ran.
	if not (is_finite(yaw) and is_finite(speed) and is_finite(float(state["c"]))):
		return {}

	# `y` LATCHES TOO, and wrapping is the whole fix: an angle has no natural
	# magnitude limit, but `RemoteAvatar` assigns it to `rotation.y` (float32) and
	# then eases it with `lerp_angle`, which is `from + short_way * weight` — and
	# `1e30 + anything small IS 1e30`. One packet and that avatar's basis is
	# garbage (sin/cos of 1e30) for the rest of the room, with no path back.
	# Wrapping into [0, TAU) is lossless for every honest sender, so this
	# normalises rather than dropping.
	yaw = fposmod(yaw, TAU)

	# FINITE IS NOT THE SAME AS SANE, and `s` is the one that latches: 1e38 is
	# finite, and `RemoteAvatar._animate` does `stride_phase += move_speed *
	# delta * ...`, so ONE such packet makes the accumulator infinite and every
	# limb rotation NaN for the rest of the room — the same permanent poisoning
	# the position's finiteness check exists to prevent. Bound both.
	if absf(pos.x) > MAX_PRESENCE_COORD or absf(pos.y) > MAX_PRESENCE_COORD \
			or absf(pos.z) > MAX_PRESENCE_COORD or absf(speed) > MAX_PRESENCE_SPEED:
		return {}

	var char_index: int = int(state["c"])
	if char_index < 0 or char_index >= PLAYER_SCRIPT.CHARACTERS.size():
		return {}

	# The shared-total fields, validated exactly like `c`: number, finite,
	# non-negative, bounded. MISSING IS NOT MALFORMED — a phase-3 peer sends a
	# packet without them, and dropping those whole would make an older peer
	# invisible rather than merely un-counted — so absent reads as 0 and only a
	# value that is PRESENT and bad drops the packet.
	var counters: Dictionary = {}
	for key: String in ["cc", "lv", "dd"]:
		var raw: Variant = state.get(key, null)
		if raw == null:
			counters[key] = 0
			continue
		if not _is_number(raw):
			return {}
		var value: float = float(raw)
		if not is_finite(value) or value < 0.0 or value > float(MAX_STATE_COUNTER):
			return {}
		counters[key] = int(value)

	return {
		"p": pos, "y": yaw, "c": char_index, "s": speed, "g": state["g"],
		"cc": counters["cc"], "lv": counters["lv"], "dd": counters["dd"],
	}


static func decode_croc_sync(state: Dictionary) -> Dictionary:
	"""
	The crocodile-sync parser — the FOURTH trust boundary, and built exactly like
	the other three: static and `_rtc`-free so scripts/mp_selfcheck.gd can beat on
	it with hostile input, and whole-or-nothing, returning an EMPTY DICTIONARY for
	anything that fails so the caller drops the packet entire.

	Wire format, the `var_to_bytes` of:

	    {"t": "croc",
	     "i": PackedInt32Array,    # one crocodile id per entry
	     "x": PackedFloat32Array,  # 4 per entry: px, py, pz, yaw
	     "f": PackedByteArray}     # one CROC_FLAG_* state byte per entry

	Three parallel packed arrays rather than an array of Dictionaries because this
	goes out at 10 Hz to every peer: packed arrays serialise as a flat block with
	no per-entry key strings.

	@param state: the already-`bytes_to_var`-decoded packet — NEVER
	    `bytes_to_var_with_objects`, see `_receive_mesh_packets()`.
	@return `{"ids": PackedInt32Array, "xf": PackedFloat32Array,
	    "flags": PackedByteArray}` with every yaw wrapped into `[0, TAU)`, or `{}`.
	"""
	# EXACT packed types, not "some array": a plain Array of the right length
	# would index fine and then hand a String to `global_position`.
	if typeof(state.get("i", null)) != TYPE_PACKED_INT32_ARRAY \
			or typeof(state.get("x", null)) != TYPE_PACKED_FLOAT32_ARRAY \
			or typeof(state.get("f", null)) != TYPE_PACKED_BYTE_ARRAY:
		return {}

	var ids: PackedInt32Array = state["i"]
	var flags: PackedByteArray = state["f"]
	var raw_xf: PackedFloat32Array = state["x"]

	# SIZES FIRST, before anything is copied: the `duplicate()` below is a full
	# allocation, and an oversized hostile packet must not get to pay for one on
	# its way to being rejected. The three arrays describe the SAME entries, so
	# their sizes are not independent — a mismatch is exactly the shape a truncated
	# or hostile packet takes, and walking it would read off the end of one of them
	# per entry.
	if ids.size() != flags.size() or raw_xf.size() != ids.size() * 4:
		return {}
	if ids.size() > MAX_CROC_SYNC:
		return {}

	# Copied because the yaw wrap below writes into it, and a packed array read
	# out of a Dictionary is a reference until it is written to.
	var xf: PackedFloat32Array = raw_xf.duplicate()

	for entry: int in ids.size():
		var base: int = entry * 4
		# FINITENESS BEFORE ANY USE, for the reason `decode_presence()` spells
		# out at length: a crocodile assigned a NaN position interpolates to NaN
		# forever after, with no path back for the room's life, and 1e30 is
		# finite but just as permanent. The coordinate bound is the presence
		# packet's — a croc stands in the same world a player does.
		for axis: int in 3:
			var value: float = xf[base + axis]
			if not is_finite(value) or absf(value) > MAX_PRESENCE_COORD:
				return {}
		var yaw: float = xf[base + 3]
		if not is_finite(yaw):
			return {}
		# WRAPPED, not bounded, exactly as `decode_presence()` wraps `y`: an angle
		# has no natural magnitude limit, but it is eased with `lerp_angle`, which
		# is `from + short_way * weight` — and `1e30 + anything small IS 1e30`.
		xf[base + 3] = fposmod(yaw, TAU)

	# `flags` needs no validation: every one of the 256 byte values is a legal
	# combination of CROC_FLAG_* bits plus unknown bits, and the receiver reads it
	# with `&` so bits it does not know are ignored.
	return {"ids": ids, "xf": xf, "flags": flags}
