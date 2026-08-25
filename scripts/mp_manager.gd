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
## ends of the collected-coin set: the one we send and the one we accept.
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

## How far the group may be spread before its centroid stops being a sensible
## place to arrive. Tuned BY EYE, not derived: 60 m is a bit over one chunk, well
## inside the fog, so a joiner landing at the centroid of a group this tight can
## still see somebody. Past it the centroid is empty ground between two players
## who have gone their separate ways, so the master's own position is used
## instead — arriving beside one player beats arriving beside none.
const GROUP_SPREAD_MAX: float = 60.0

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

## THIS peer's own contribution from runs it has already finished in this room —
## what "Play Again" retired when `reset_position()` zeroed `own_coins` /
## `own_lives_spent` (see `retire_own_contribution`).
##
## Deliberately NOT folded into `_gone_*`. Those are the room-wide frozen share of
## members who LEFT, and every peer derives them independently from the same
## `peer_leave` frame, so they converge. A restart is observed by nobody else: a
## `_gone_*` write here would raise this peer's totals alone, while every other
## peer saw the restarter's next presence packet report zero and dropped the
## coins and REFUNDED the lives — the room permanently disagreeing about its own
## bank and hearts. Kept as part of our OWN contribution instead, it rides the
## existing `cc`/`lv` fields in presence and in the join snapshot, so every peer
## sums the same numbers with no new protocol and no extra message.
var _retired_coins: int = 0
var _retired_spent: int = 0

## How many join snapshots this peer is still waiting on before it places itself,
## and how long it has waited (seconds). See `JOIN_SNAPSHOT_WAIT`.
var _expected_snapshots: int = 0
var _join_wait: float = 0.0

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

## Seed self-heal state: seconds since the last `seed_req` went out, and how many
## have gone out this room. Both are room-scoped and reset by `leave()`.
var _seed_req_accum: float = 0.0
var _seed_req_tries: int = 0


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
	_retired_coins = 0
	_retired_spent = 0
	_expected_snapshots = 0
	_join_wait = 0.0
	_ice = {}
	_send_accum = 0.0
	_croc_accum = 0.0
	_seed_req_accum = 0.0
	_seed_req_tries = 0
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
	# PROMOTION IS A HOT STANDBY HANDOVER, and it is one loop because the replica
	# is just the local nodes. Every crocodile we have been rendering from the old
	# master's samples is a real local body holding that master's last known
	# transform, so dropping the remote-drive flag resumes simulation from exactly
	# where each one stands — no state replay, no snapshot, no gap.
	if _master == _you:
		_release_synced_crocs()

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
	"""
	if _state != State.IN_ROOM:
		return null
	var positions: Array[Vector3] = []
	for state: Dictionary in _peer_state.values():
		positions.append(state["pos"] as Vector3)
	return positions


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
	var characters: Array = RemoteAvatar.PLAYER_SCRIPT.CHARACTERS
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
		var characters: Array = RemoteAvatar.PLAYER_SCRIPT.CHARACTERS
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
	"""
	if _has_seed or not _is_number(payload.get("seed", null)):
		return
	_room_seed = int(payload["seed"])
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
	if terrain != null and terrain.has_method("new_run"):
		terrain.new_run(_room_seed)

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("reset_position"):
		player.reset_position()


# =============================================================================
# JOIN PLACEMENT — arrive beside the group, not at the world origin
# =============================================================================

func _can_join_place() -> bool:
	"""
	Whether a join placement is still owed: we joined a room that already had
	somebody in it, we have not placed yet, and both halves of what a placement
	needs — the world seed and at least one snapshot position — are in hand.
	"""
	if _join_applied or _first_member or not _has_seed or _peer_state.is_empty():
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
		# Through `own_reported_*` so an earlier run retired by "Play Again" in this
		# room travels with the live one — see `_retired_coins`.
		coins = own_reported_coins(int(player.get("own_coins")) if "own_coins" in player else 0)
		spent = own_reported_spent(int(player.get("own_lives_spent")) if "own_lives_spent" in player else 0)
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
	(`{"cc": int, "ls": int, "dd": int, "pos": Vector3, "ids": Array[int]}`) or
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
	var raw_ids: Array = payload["ids"]
	# An over-long id list is TRUNCATED, not rejected — the one place this parser
	# keeps part of a payload. The sender orders the ids most-recent-first, so the
	# head is the part nearest the joiner, and a snapshot whose list is too long
	# is still worth its position and its counters, which are what the join
	# placement and the shared bank actually need. A malformed *entry* is a
	# different thing and still drops the whole snapshot.
	var ids: Array[int] = []
	for i: int in range(mini(raw_ids.size(), MAX_STATE_IDS)):
		var entry: Variant = raw_ids[i]
		if not _is_number(entry):
			return {}
		var value: float = float(entry)
		if not is_finite(value) or absf(value) > MAX_STATE_ID_MAGNITUDE:
			return {}
		ids.append(int(value))

	return {
		"cc": counters[0],
		"ls": counters[1],
		"dd": counters[2],
		"gc": counters[3],
		"gs": counters[4],
		"pos": pos,
		"ids": ids,
	}


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

func retire_own_contribution(coins: int, spent: int) -> void:
	"""
	Freeze this peer's own coins and spent lives into the room's totals before it
	wipes them, exactly as `_on_lobby_peer_left` does for a departing member.

	"Play Again" inside a room is the case: `reset_position()` zeroes `own_coins`
	and `own_lives_spent`, and without this the room's bank shrinks in front of
	everyone and — much worse — every life that peer spent is REFUNDED to the
	shared hearts. One member restarting would top the room's lives back up
	indefinitely. A no-op offline, so a solo restart still costs nothing.

	It lands in `_retired_*`, NOT `_gone_*` — see those fields for why the
	distinction is the whole fix: a restart is invisible to every other peer, so
	the frozen amount has to travel as part of what we REPORT as our own
	contribution, not as a room-wide total only we know about.
	"""
	if _state != State.IN_ROOM:
		return
	_retired_coins += coins
	_retired_spent += spent


func own_reported_coins(own_coins: int) -> int:
	"""
	What this peer contributes to the room's bank: its live run plus everything
	earlier runs in this room retired. THE ONE PLACE that sum is written, so the
	four sites that report or use it — presence, the join snapshot, `shared_bank`
	and `shared_lives_spent`'s sibling below — cannot drift apart.
	"""
	return own_coins + _retired_coins


func own_reported_spent(own_spent: int) -> int:
	"""Lives this peer owes the room: its live run plus what earlier runs retired."""
	return own_spent + _retired_spent


func shared_bank(own_coins: int) -> Variant:
	"""The room's banked coins, or `null` offline."""
	if _state != State.IN_ROOM:
		return null
	var total: int = own_reported_coins(own_coins) + _gone_coins
	for state: Dictionary in _peer_state.values():
		total += int(state.get("coins", 0))
	return total


func shared_lives_spent(own_spent: int) -> Variant:
	"""Lives spent by everyone who has been in this room, or `null` offline."""
	if _state != State.IN_ROOM:
		return null
	var total: int = own_reported_spent(own_spent) + _gone_spent
	for state: Dictionary in _peer_state.values():
		total += int(state.get("spent", 0))
	return total


func shared_distance(own_distance: int) -> Variant:
	"""
	The furthest anyone in the room has got, or `null` offline.

	A max, so feeding it back into the player's own running max cannot inflate it
	— which is also why a departed peer needs no frozen accumulator: whatever it
	reached was already folded in while it was here.
	"""
	if _state != State.IN_ROOM:
		return null
	var best: int = own_distance
	for state: Dictionary in _peer_state.values():
		best = maxi(best, int(state.get("dist", 0)))
	return best


static func shared_lives_from(bank: int, spent: int, max_lives: int, per_extra: int, cap: int) -> int:
	"""
	The room's remaining lives: the starting hearts, plus one per `per_extra`
	coins the room has banked, minus every life anyone has spent, clamped into
	[0, cap]. Pure and static so scripts/mp_selfcheck.gd can pin the arithmetic
	without a room.
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
	var state: Dictionary = {
		"p": player.global_position,
		"y": player.rotation.y,
		"c": int(player.get("current_character_index")) if "current_character_index" in player else 0,
		"s": speed,
		"g": player.is_on_floor() if player.has_method("is_on_floor") else true,
		# `own_reported_*` folds in what "Play Again" retired in this room, so a
		# restart never makes this peer's contribution appear to drop — see
		# `_retired_coins` for the desync that caused.
		"cc": own_reported_coins(int(player.get("own_coins")) if "own_coins" in player else 0),
		"lv": own_reported_spent(int(player.get("own_lives_spent")) if "own_lives_spent" in player else 0),
		"dd": int(player.get("run_distance")) if "run_distance" in player else 0,
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
	var budget: int = MAX_PRESENCE_PACKETS_PER_PEER * maxi(1, _avatars.size())
	while budget > 0 and _rtc.get_available_packet_count() > 0:
		budget -= 1
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

		if packet.has("t"):
			_receive_mesh_verb(from_id, str(packet["t"]), packet)
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
	match verb:
		"croc":
			_receive_croc_sync(from_id, packet)
		_:
			# Forward compatibility. Not a warning — see the docstring.
			pass


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
		if is_instance_valid(croc) and croc.has_method("croc_id"):
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
	if char_index < 0 or char_index >= RemoteAvatar.PLAYER_SCRIPT.CHARACTERS.size():
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
	# Copied because the yaw wrap below writes into it, and a packed array read
	# out of a Dictionary is a reference until it is written to.
	var xf: PackedFloat32Array = (state["x"] as PackedFloat32Array).duplicate()

	# The three arrays describe the SAME entries, so their sizes are not
	# independent. A mismatch is exactly the shape a truncated or hostile packet
	# takes, and walking it would read off the end of one of them per entry.
	if ids.size() != flags.size() or xf.size() != ids.size() * 4:
		return {}
	if ids.size() > MAX_CROC_SYNC:
		return {}

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
