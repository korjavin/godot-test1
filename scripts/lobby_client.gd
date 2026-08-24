extends Node
class_name LobbyClient
## Thin `WebSocketPeer` wrapper over the multiplayer lobby's `/ws` protocol
## (implemented in `server/conn.go` + `server/room.go`), plus an `HTTPRequest`
## fetch of `/ice` for the STUN/TURN configuration.
##
## This file owns **only the lobby socket**. It knows nothing about WebRTC, the
## game world, or the UI — it turns JSON frames into signals and turns
## `send_signal_to()` calls back into JSON frames. Everything above that lives in
## `scripts/mp_manager.gd`.
##
## Wire protocol, as the Go lobby actually implements it:
##
##   connect:  <lobby_url>/ws?room=<CODE>&name=<label>   (empty room = create one)
##   server →  welcome | peer_join | peer_leave | master | signal | heroes | pong | error
##   client →  {"type":"signal","to":...,"payload":...} | hero | stalled | ping
##
## Notes the lobby's code guarantees, which this client relies on:
##   * `welcome` is **always the first frame** and already carries the master —
##     only *subsequent* master changes arrive as a separate `master` frame.
##   * `welcome.members[]` **includes yourself**.
##   * peer ids are 16 lowercase hex characters.
##   * the lobby never inspects `payload`, so anything JSON-serialisable relays.
##
## `heroes` / `pong` are parsed but deliberately unused: hero assignment and
## stall detection are phase 4/5 concerns.

# =============================================================================
# CONFIGURATION
# =============================================================================

## Fallback lobby URL, used when nothing overrides it.
##
## ponytail: this is a **placeholder pending the phase-2 deployment hostname** —
## the production lobby host is not settled yet, and inventing one would be worse
## than an obvious stub. `?lobby=<url>` (web) or `--lobby=<url>` (desktop)
## overrides it with no rebuild, so playtesting is never blocked on this literal.
const DEFAULT_LOBBY_URL: String = "wss://lobby.example.com"

## Used when `/ice` cannot be reached or returns nonsense. A STUN-only mesh still
## connects on most home networks; failing the whole join because the TURN relay
## is down would be strictly worse than degrading to "works unless both peers are
## behind symmetric NAT".
const FALLBACK_ICE: Dictionary = {
	"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]
}

# =============================================================================
# SIGNALS
# =============================================================================

## The `welcome` frame: our own peer id, the room code, the current master's id,
## and every member (including us) as `{"id": String, "name": String}`.
signal joined(you: String, room: String, master: String, members: Array)

## Another peer entered the room.
signal peer_joined(id: String, name: String)

## A peer left the room.
signal peer_left(id: String)

## The master changed *after* the welcome frame (the welcome carries the first one).
signal master_changed(id: String)

## An opaque relayed payload from `from`. The lobby never looks inside it.
signal relay(from: String, payload: Dictionary)

## The lobby refused something (bad room code, room full, malformed frame).
signal lobby_error(message: String)

## The socket closed, for any reason including a clean `disconnect_from_room()`.
signal closed(code: int, reason: String)

# =============================================================================
# STATE
# =============================================================================

## The socket. Non-null only between `connect_to_room()` and the close.
var _socket: WebSocketPeer = null

## Base lobby URL (e.g. `wss://host` or `ws://localhost:8080`), no trailing slash.
var _lobby_url: String = ""

## Child `HTTPRequest`, created lazily on the first `fetch_ice()` call.
var _http: HTTPRequest = null


# =============================================================================
# LOBBY URL RESOLUTION
# =============================================================================

static func resolve_lobby_url(override: String) -> String:
	"""
	Pick the lobby URL, highest precedence first:

	  1. `--lobby=<url>` in the user command line — how two desktop editor
	     instances are pointed at a locally running `go run .` lobby.
	  2. `?lobby=<url>` in `location.search` (web only) — how two browser tabs are
	     pointed at a local lobby, and the escape hatch while the production
	     hostname is unsettled.
	  3. `override` — the `@export var lobby_url` on the MP manager, when set.
	  4. DEFAULT_LOBBY_URL.

	Command line beats query string beats export beats default, so the most
	specific thing a developer typed always wins.
	"""
	# 1. Desktop: `godot --path . scenes/main.tscn -- --lobby=ws://localhost:8080`.
	#    Everything after the bare `--` lands in get_cmdline_user_args().
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--lobby="):
			return _strip_trailing_slash(arg.substr("--lobby=".length()))

	# 2. Web: `index.html?lobby=ws://localhost:8080`. Every JavaScriptBridge touch
	#    is gated behind the web feature, so desktop never reaches this at all.
	if OS.has_feature("web"):
		var from_query: Variant = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('lobby') || ''", true
		)
		if typeof(from_query) == TYPE_STRING and not (from_query as String).is_empty():
			return _strip_trailing_slash(from_query as String)

	# 3. The exported override on mp_manager.
	if not override.is_empty():
		return _strip_trailing_slash(override)

	# 4. Placeholder.
	return DEFAULT_LOBBY_URL


static func _strip_trailing_slash(url: String) -> String:
	"""Normalise so we can always concatenate `/ws` and `/ice` without doubling."""
	return url.strip_edges().rstrip("/")


# =============================================================================
# CONNECTION LIFECYCLE
# =============================================================================

func connect_to_room(code: String, display_name: String, lobby_url_override: String = "") -> void:
	"""
	Open the lobby socket. An **empty `code` creates a room** — the lobby treats an
	empty or unknown `room` parameter as "make me a fresh one" and reports the
	generated code back in the welcome frame, exactly as its own JS test page does.

	Both query values go through `uri_encode()`: the display name is arbitrary
	user text and must never be able to inject another query parameter.
	"""
	disconnect_from_room()
	_lobby_url = resolve_lobby_url(lobby_url_override)

	var url: String = "%s/ws?room=%s&name=%s" % [
		_lobby_url, code.uri_encode(), display_name.uri_encode()
	]
	_socket = WebSocketPeer.new()
	var err: int = _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		lobby_error.emit("Cannot reach the lobby at %s (error %d)" % [_lobby_url, err])
		return
	set_process(true)


func disconnect_from_room() -> void:
	"""Close the socket and clear state. Safe to call when never connected."""
	if _socket != null:
		_socket.close()
		_socket = null
	set_process(false)


func is_connected_to_lobby() -> bool:
	"""True once the socket is open (not merely connecting)."""
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func get_lobby_url() -> String:
	"""The base URL actually in use, for the UI's status line."""
	return _lobby_url


# =============================================================================
# SENDING
# =============================================================================

func send_signal_to(to: String, payload: Dictionary) -> void:
	"""
	Relay an opaque payload through the lobby. `to == ""` broadcasts it to every
	other member. The lobby never inspects the payload — that opacity is what
	keeps signalling logic out of the server.
	"""
	_send({"type": "signal", "to": to, "payload": payload})


func _send(frame: Dictionary) -> void:
	"""Serialise and send one frame, silently dropping it if the socket is not open."""
	if not is_connected_to_lobby():
		return
	_socket.send_text(JSON.stringify(frame))


# =============================================================================
# POLLING
# =============================================================================

func _init() -> void:
	# Idle until connect_to_room() — the whole feature is inert until a room is
	# joined, so an unused LobbyClient costs nothing per frame.
	#
	# This lives in `_init`, NOT `_ready`, and that is load-bearing: a node added
	# to a tree that has not started yet gets its `_ready` on the first idle frame,
	# i.e. *after* a caller that does `add_child(client)` then `connect_to_room()`
	# in the same frame. A `_ready` that disabled processing would silently undo
	# that call's `set_process(true)` and the socket would never be polled past
	# STATE_CONNECTING. `_init` runs at construction, so nothing can race it.
	set_process(false)


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _socket.get_available_packet_count() > 0:
				_handle_text(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code: int = _socket.get_close_code()
			var reason: String = _socket.get_close_reason()
			_socket = null
			set_process(false)
			closed.emit(code, reason)
		_:
			# STATE_CONNECTING / STATE_CLOSING — nothing to do but keep polling.
			pass


func _handle_text(text: String) -> void:
	"""
	Parse one inbound frame and turn it into a signal. Everything here is
	untrusted input off a socket, so each field is type-checked before use and a
	malformed frame is dropped rather than propagated.
	"""
	# An instance `JSON` rather than the static `JSON.parse_string()`: the static
	# helper prints an engine error on malformed input, and this is a socket a
	# hostile peer could spray garbage at. Dropping it quietly is the right answer.
	var json: JSON = JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("LobbyClient: dropped malformed frame")
		return
	var frame: Dictionary = json.data as Dictionary

	match str(frame.get("type", "")):
		"welcome":
			joined.emit(
				str(frame.get("you", "")),
				str(frame.get("room", "")),
				str(frame.get("master", "")),
				frame.get("members", []) as Array
			)
		"peer_join":
			var peer: Variant = frame.get("peer", null)
			if typeof(peer) != TYPE_DICTIONARY:
				return
			peer_joined.emit(
				str((peer as Dictionary).get("id", "")),
				str((peer as Dictionary).get("name", ""))
			)
		"peer_leave":
			peer_left.emit(str(frame.get("id", "")))
		"master":
			master_changed.emit(str(frame.get("id", "")))
		"signal":
			var payload: Variant = frame.get("payload", null)
			if typeof(payload) != TYPE_DICTIONARY:
				return
			relay.emit(str(frame.get("from", "")), payload as Dictionary)
		"error":
			lobby_error.emit(str(frame.get("error", "unknown lobby error")))
		_:
			# `heroes` and `pong` land here, as will anything phases 4/5 add.
			# Ignoring unknown types is what makes this client forward compatible.
			pass


# =============================================================================
# ICE CONFIGURATION
# =============================================================================

func fetch_ice(callback: Callable) -> void:
	"""
	GET `<lobby>/ice` and hand the parsed body to `callback` as a Dictionary.

	The body is passed through **unchanged**: the lobby already returns exactly
	`{"iceServers": [...]}`, which is the shape `WebRTCPeerConnection.initialize()`
	takes, so reshaping it would only be a chance to get it wrong. Any failure —
	transport error, non-200, unparseable body, missing `iceServers` — falls back
	to FALLBACK_ICE with a warning instead of failing the join.
	"""
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)

	# The lobby serves both the socket and /ice; only the scheme differs.
	var http_url: String = _lobby_url
	if http_url.begins_with("wss://"):
		http_url = "https://" + http_url.substr("wss://".length())
	elif http_url.begins_with("ws://"):
		http_url = "http://" + http_url.substr("ws://".length())

	# Connect only once the request is actually in flight, so a refused request
	# leaves no dangling callback behind. CONNECT_ONE_SHOT drops the binding as
	# soon as it fires, so a second join re-uses the node without stacking up.
	var err: int = _http.request(http_url + "/ice")
	if err != OK:
		push_warning("LobbyClient: /ice request failed to start (%d), using STUN only" % err)
		callback.call(FALLBACK_ICE)
		return
	_http.request_completed.connect(_on_ice_completed.bind(callback), CONNECT_ONE_SHOT)


func _on_ice_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray,
	callback: Callable
) -> void:
	"""Validate the /ice response, degrading to STUN-only on anything unexpected."""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("LobbyClient: /ice unreachable (result %d, HTTP %d), using STUN only"
			% [result, response_code])
		callback.call(FALLBACK_ICE)
		return

	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK \
			or typeof(json.data) != TYPE_DICTIONARY \
			or not (json.data as Dictionary).has("iceServers"):
		push_warning("LobbyClient: /ice body unusable, using STUN only")
		callback.call(FALLBACK_ICE)
		return

	callback.call(json.data as Dictionary)
