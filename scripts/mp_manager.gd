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

## The lobby errors that must NOT end the session. `server/room.go` answers a
## refused hero claim with a plain `error` frame on a socket it deliberately
## keeps OPEN (`errUnknownHero` / `errHeroTaken`), and two peers reaching for the
## same hero at the same moment is an ordinary event — the blanket `leave()`
## every other error takes would drop BOTH of them out of a perfectly good room.
## Matched by exact string, because the string is all the frame carries.
const HERO_ERRORS: PackedStringArray = ["unknown hero", "hero already taken"]

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

## The `/ice` payload, fetched once per join and reused for every connection.
var _ice: Dictionary = {}

## Presence send accumulator (seconds).
var _send_accum: float = 0.0


func _init() -> void:
	# Idle until host()/join(). Belt-and-braces only: NOTIFICATION_READY turns
	# `_process` back on for any script that overrides it, so the real guard is
	# `_process`'s `_state == OFFLINE` early return. In `_init` rather than
	# `_ready` for the same reason LobbyClient does it: `_ready` runs an idle
	# frame later and would undo a `set_process(true)` issued by a caller that
	# joins immediately.
	set_process(false)
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
	if not webrtc_available():
		status.emit("Multiplayer needs the WebRTC addon on desktop — see README")
		return

	leave()

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
	_ice = {}
	_send_accum = 0.0
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
	_state = State.IN_ROOM
	status.emit("In room %s (%d/4)" % [room, members.size()])
	room_changed.emit(room, members)

	# The mesh cannot start before we know which STUN/TURN servers to use, so the
	# rest of setup hangs off the /ice callback.
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

	# The master hands out the world seed the moment it has a mesh to talk about.
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
	status.emit("%s joined" % peer_name)
	room_changed.emit(_room, _members)


func _on_lobby_peer_left(id: String) -> void:
	"""A peer left: drop its avatar, its connection and anything buffered for it."""
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
	# ONLY re-broadcast a seed we actually adopted. A master elected before the
	# seed reached it (the old master dropping inside our /ice window) has
	# `_has_seed` false, and the terrain-read path below would publish its own
	# PRIVATE solo world as the room's seed — which every peer that already holds
	# the real one drops on `_receive_seed`'s latch, leaving the master alone on
	# different ground for the room's life while the UI reports success. Staying
	# quiet keeps the peers that already agree agreeing. Asking a member for the
	# seed is phase 4's problem, along with the rest of mid-run state replay.
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
	# the terrain. The two are normally the same value — `_receive_seed` set the
	# terrain from `_room_seed` — but the room's agreed seed is the authority
	# here, not whatever this peer's ground happens to be running on.
	if _has_seed:
		_lobby.send_signal_to("", {"mp": "seed", "seed": _room_seed})
		return

	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain == null or not ("run_seed" in terrain):
		return
	_room_seed = int(terrain.get("run_seed"))
	_has_seed = true
	_lobby.send_signal_to("", {"mp": "seed", "seed": _room_seed})


func _receive_seed(payload: Dictionary) -> void:
	"""
	Adopt the master's world seed: regenerate the terrain from it and put the
	local player back at spawn, so a joiner starts at the beginning of the shared
	world rather than at whatever coordinates its solo run had reached.

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

	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain != null and terrain.has_method("new_run"):
		terrain.new_run(_room_seed)

	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("reset_position"):
		player.reset_position()

	status.emit("Shared world seed received")


# =============================================================================
# PER-FRAME: PRESENCE SEND + RECEIVE
# =============================================================================

func _process(delta: float) -> void:
	if _state == State.OFFLINE or _rtc == null:
		return

	# The mesh is a plain PacketPeer here — nobody else polls it for us, because
	# it was deliberately never handed to the global MultiplayerAPI.
	_rtc.poll()
	_prune_dead_connections()
	_receive_presence()

	_send_accum += delta
	var interval: float = 1.0 / PRESENCE_HZ
	if _send_accum >= interval:
		_send_accum = fmod(_send_accum, interval)
		_send_presence()


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
	everything `RemoteAvatar` needs to draw a convincing runner, and nothing else.

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

	var state: Dictionary = {
		"p": player.global_position,
		"y": player.rotation.y,
		"c": int(player.get("current_character_index")) if "current_character_index" in player else 0,
		"s": speed,
		"g": player.is_on_floor() if player.has_method("is_on_floor") else true,
	}

	var bytes: PackedByteArray = var_to_bytes(state)
	_rtc.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	for pid: int in connected:
		_rtc.set_target_peer(pid)
		_rtc.put_packet(bytes)


func _receive_presence() -> void:
	"""
	Drain inbound presence packets and feed them to the right avatar.

	**This is the other trust boundary, and the sharper one.** Decoding uses
	`bytes_to_var`, *never* `bytes_to_var_with_objects` — the "with objects" form
	will instantiate arbitrary classes named in the byte stream, which hands any
	peer in the room code execution in our process. There is no situation in this
	game where a peer needs to send us an object.

	Past that, every field is type-checked, the position is rejected if any
	component is non-finite (a NaN would poison the avatar's smoothing forever),
	and the character index is range-checked before it can index CHARACTERS. A
	packet that fails any of it is dropped whole — there is no partial trust.
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
		for id: String in _avatars:
			if peer_int_id(id) == from_int:
				avatar = _avatars[id]
				break
		if avatar == null:
			continue

		var state: Dictionary = decode_presence(bytes)
		if state.is_empty():
			continue

		avatar.visible = true
		avatar.receive_state(state["p"], state["y"], state["c"], state["s"], state["g"])


static func decode_presence(bytes: PackedByteArray) -> Dictionary:
	"""
	The presence packet parser, and the whole trust boundary in one pure function.

	Returns the validated state, or an EMPTY DICTIONARY for anything that fails —
	a packet is trusted whole or dropped whole, there is no partial trust. Static
	and `_rtc`-free so scripts/mp_selfcheck.gd can hold it to that with a fistful
	of malformed byte arrays.
	"""
	var decoded: Variant = bytes_to_var(bytes)
	if typeof(decoded) != TYPE_DICTIONARY:
		return {}
	var state: Dictionary = decoded as Dictionary

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

	return { "p": pos, "y": yaw, "c": char_index, "s": speed, "g": state["g"] }
