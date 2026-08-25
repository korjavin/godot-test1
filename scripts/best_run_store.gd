extends Node
class_name BestRunStore
## Where the personal best-run records live, and how they reach the lobby.
##
## Two layers, and the split is the whole point:
##
##   * LOCAL — a `ConfigFile` at `user://best_run.cfg` on desktop, and
##     `window.localStorage` **on web**.
##
##     MEASURED, because the obvious story turned out to be wrong: `user://` on
##     the web export IS a working IndexedDB mount. Driven headless against the
##     deployed build, a record written at game over reached IndexedDB, came back
##     across a reload, and correctly suppressed the "NEW BEST!" flash — in
##     Chromium AND in WebKit. So the reported "every run flashes NEW BEST" is
##     **not** this code path failing; it is site storage not surviving in the
##     reporter's browser (Safari/iOS purges IndexedDB for sites without recent
##     interaction, a private window keeps none of it, and GitHub Pages vs the
##     deployment host are two different origins with two different stores) —
##     which is exactly the class of failure only a server-side store can fix.
##
##     localStorage is still the better local half, for two reasons that survive
##     that finding: the player id has to live there anyway (nothing else on web
##     is both synchronous and readable before the engine's first frame), and
##     `setItem` has committed when it returns, whereas an IndexedDB write is
##     flushed a frame or more later — a tab closed inside that window loses it.
##     A pre-existing `user://` record is still READ on web, so nobody's stored
##     best is thrown away by the switch; see `_read_local`.
##
##   * SERVER — `GET`/`POST <lobby>/best?id=<player id>` on the same Go lobby the
##     multiplayer code already talks to (`server/best.go`). This is what makes a
##     best follow a player **between devices**, and it is the owner-chosen fix.
##     Every failure is silent and non-fatal: the local layer has already
##     answered, so a lobby that is down, old, or blocked by CORS costs nothing
##     but the cross-device half.
##
## RECORDS ONLY EVER GO UP, on both layers and on the server. That is what makes
## the ordering irrelevant: `loaded` fires once with the local values (inside
## `fetch()`, synchronously) and possibly again when the server answers with
## better ones, and the player folds each in with `maxi`. A late reply cannot
## lower anything, a lost reply costs nothing, and a retried POST is idempotent.
##
## Deliberately NOT here: a leaderboard (owner: personal bests only), any
## authentication (see `server/best.go`'s trust-model note), and any retry timer —
## the next game over posts again.

# =============================================================================
# CONFIGURATION
# =============================================================================

## Desktop persistence. Kept at the path (and section) `player_controller.gd`
## already used, so an existing desktop record survives this change.
const CONFIG_PATH: String = "user://best_run.cfg"
const CONFIG_SECTION: String = "best"
const CONFIG_PLAYER_SECTION: String = "player"

## Web persistence: `localStorage` keys. Prefixed because the origin is shared
## with whatever else is served from it.
const LS_PLAYER_ID: String = "ck_player_id"
const LS_DISTANCE: String = "ck_best_distance"
const LS_COINS: String = "ck_best_coins"

## The player id is 128 random bits as 32 hex characters — inside the lobby's
## `^[A-Za-z0-9_-]{8,64}$` guard, and wide enough that guessing somebody else's
## is the only attack and it does not work.
const PLAYER_ID_HEX_LEN: int = 32

## `HTTPRequest`'s default timeout is *wait forever*, and a stuck request makes
## every later one on that node answer ERR_BUSY — the trap `lobby_client.gd`
## documents at length. Short, because nothing waits on these.
const REQUEST_TIMEOUT_SEC: float = 5.0

# =============================================================================
# SIGNALS
# =============================================================================

## Best-known records. May fire more than once (local first, then the server if
## it knows better); the values only ever rise.
signal loaded(distance: int, coins: int)

# =============================================================================
# STATE
# =============================================================================

## Best known to this store. Public so a caller can read them without waiting.
var distance: int = 0
var coins: int = 0

var _player_id: String = ""

## Two `HTTPRequest` nodes, deliberately — one node answers ERR_BUSY while a
## request is in flight, and the boot GET can still be running when a very short
## first run ends. Same reasoning (and the same fix) as `lobby_client.gd`'s
## `_http` / `_rooms_http` split.
var _get_http: HTTPRequest = null
var _post_http: HTTPRequest = null


# =============================================================================
# PUBLIC API
# =============================================================================

func fetch() -> void:
	"""
	Load the records. The local layer answers immediately (so a boot with no
	network behaves exactly as it always did), then the server is asked and may
	raise them.
	"""
	_read_local()
	loaded.emit(distance, coins)
	_request_get()


func submit(new_distance: int, new_coins: int) -> void:
	"""
	Record a run's results. Called from `_trigger_game_over()` only when a record
	actually moved, so this is not a per-frame path.

	It re-reads the local store first so that a `submit()` without a preceding
	`fetch()` cannot LOWER a stored record — `distance` starts at 0, and a plain
	`_write_local()` off that would overwrite a real best with this run's number.
	One file open per game over, and it makes call order stop mattering.
	"""
	_read_local()
	distance = maxi(distance, new_distance)
	coins = maxi(coins, new_coins)
	_write_local()
	_request_post()


func player_id() -> String:
	"""
	This player's persistent id, generated once and kept in the same local store
	as the records. Empty only when the store is unwritable (a private window
	with `localStorage` disabled), in which case the server half is simply
	skipped — see `_request_get`.
	"""
	if _player_id.is_empty():
		_player_id = _load_or_make_player_id()
	return _player_id


# =============================================================================
# LOCAL LAYER
# =============================================================================

func _read_local() -> void:
	"""
	Raise the in-memory records from the local store.

	The ConfigFile is read on EVERY platform, web included, and that is the
	one-way migration: a web player who already has a record in the old
	`user://best_run.cfg` keeps it, and the next `_write_local()` mirrors it into
	localStorage. Reading both costs one file open at boot and means the switch
	throws nobody's best away.
	"""
	if OS.has_feature("web"):
		distance = maxi(distance, maxi(0, _ls_get(LS_DISTANCE).to_int()))
		coins = maxi(coins, maxi(0, _ls_get(LS_COINS).to_int()))
	var cfg := ConfigFile.new()
	# A missing file (first ever run) is NOT an error — the zero defaults stand.
	if cfg.load(CONFIG_PATH) != OK:
		return
	distance = maxi(distance, maxi(0, int(cfg.get_value(CONFIG_SECTION, "distance", 0))))
	coins = maxi(coins, maxi(0, int(cfg.get_value(CONFIG_SECTION, "coins", 0))))


func _write_local() -> void:
	"""
	Persist the records (and the player id, which shares the store). Failures are
	ignored: an unpersisted record is non-fatal and must never interrupt the
	game-over flow.
	"""
	if OS.has_feature("web"):
		_ls_set(LS_DISTANCE, str(distance))
		_ls_set(LS_COINS, str(coins))
		return
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # keep any other section (the player id) intact
	cfg.set_value(CONFIG_SECTION, "distance", distance)
	cfg.set_value(CONFIG_SECTION, "coins", coins)
	cfg.save(CONFIG_PATH)


func _load_or_make_player_id() -> String:
	"""Read the stored id, or mint and store a fresh one."""
	var stored := ""
	if OS.has_feature("web"):
		stored = _ls_get(LS_PLAYER_ID)
	if stored.is_empty():
		# Also the web migration path: an id already in the ConfigFile is reused
		# rather than replaced, so a player who has one keeps their server record.
		var cfg := ConfigFile.new()
		if cfg.load(CONFIG_PATH) == OK:
			stored = str(cfg.get_value(CONFIG_PLAYER_SECTION, "id", ""))
	# Re-mint anything the lobby would refuse, so a corrupted store self-heals
	# instead of 400ing every request for the rest of this install's life.
	if stored.length() == PLAYER_ID_HEX_LEN and stored.is_valid_hex_number():
		return stored

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fresh := ""
	for _i in 4:
		fresh += "%08x" % rng.randi()

	if OS.has_feature("web"):
		_ls_set(LS_PLAYER_ID, fresh)
	else:
		var cfg := ConfigFile.new()
		cfg.load(CONFIG_PATH)
		cfg.set_value(CONFIG_PLAYER_SECTION, "id", fresh)
		cfg.save(CONFIG_PATH)
	return fresh


static func _ls_get(key: String) -> String:
	"""
	Read one `localStorage` key, or "" for anything that is not a stored string.

	The whole expression is wrapped in a JS `try` because `localStorage` *throws*
	rather than returning null when a browser has site data blocked (a private
	window, or a strict privacy setting) — an unguarded read would surface as a
	JavaScriptBridge error every boot. The key goes through `JSON.stringify` so it
	is a JS string literal and cannot break out of the call.
	"""
	if not OS.has_feature("web"):
		return ""
	var js := "(function(){try{return window.localStorage.getItem(%s)||'';}catch(e){return '';}})()"
	var value: Variant = JavaScriptBridge.eval(js % JSON.stringify(key), true)
	return value as String if typeof(value) == TYPE_STRING else ""


static func _ls_set(key: String, value: String) -> void:
	"""Write one `localStorage` key. Same throw guard and same quoting as _ls_get."""
	if not OS.has_feature("web"):
		return
	var js := "try{window.localStorage.setItem(%s,%s);}catch(e){}"
	JavaScriptBridge.eval(js % [JSON.stringify(key), JSON.stringify(value)], true)


# =============================================================================
# SERVER LAYER
# =============================================================================

func _endpoint() -> String:
	"""`<lobby origin>/best?id=<player id>`, honouring the usual lobby overrides."""
	return "%s/best?id=%s" % [LobbyClient.http_url(), player_id().uri_encode()]


func _request_get() -> void:
	"""Ask the lobby for this player's stored records. Failure is silent."""
	if player_id().is_empty():
		return
	if _get_http == null:
		_get_http = HTTPRequest.new()
		_get_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_get_http)
	var err: int = _get_http.request(_endpoint())
	if err != OK:
		# ERR_BUSY is an ordinary overlap and says nothing. Anything else — above
		# all ERR_UNCONFIGURED, which is what a node not yet inside the tree
		# answers — is the silent-no-sync failure this whole feature is prone to,
		# so say it out loud rather than degrading quietly.
		if err != ERR_BUSY:
			push_warning("BestRunStore: /best GET could not start (%d)" % err)
		return
	_get_http.request_completed.connect(_on_get_completed, CONNECT_ONE_SHOT)


func _on_get_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	"""
	Fold the server's records in. Anything unexpected — transport failure, a lobby
	too old to have the route, an unparseable body — is simply "no server record",
	which is the state a solo desktop player is permanently in.
	"""
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return
	var data := json.data as Dictionary
	var server_distance := maxi(0, int(data.get("distance", 0)))
	var server_coins := maxi(0, int(data.get("coins", 0)))
	# The server can be BEHIND us: a record set before this feature shipped, one
	# migrated out of the old `user://` file, or simply a run banked while the
	# lobby was unreachable. Without this the whole local history sits here until
	# the player happens to beat it, and never reaches their other devices — the
	# reply is the only moment we know what the server has, so it is where the
	# catch-up POST belongs. It converges: the next boot finds them equal.
	var server_is_behind := server_distance < distance or server_coins < coins
	var raised := server_distance > distance or server_coins > coins

	distance = maxi(distance, server_distance)
	coins = maxi(coins, server_coins)
	if raised:
		# Mirror down, so the next boot has them even with the lobby unreachable.
		_write_local()
		loaded.emit(distance, coins)
	if server_is_behind:
		_request_post()


func _request_post() -> void:
	"""
	Publish the records. The lobby merges rather than overwrites, so this is
	idempotent and a dropped POST costs nothing but a round of cross-device sync —
	the next game over sends the same numbers again.
	"""
	if player_id().is_empty():
		return
	if _post_http == null:
		_post_http = HTTPRequest.new()
		_post_http.timeout = REQUEST_TIMEOUT_SEC
		add_child(_post_http)
	var body := JSON.stringify({"distance": distance, "coins": coins})
	var err: int = _post_http.request(
		_endpoint(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body
	)
	# Same reasoning as the GET: the local record is already written, so a failure
	# here costs only the cross-device half — but it must not be invisible.
	if err != OK and err != ERR_BUSY:
		push_warning("BestRunStore: /best POST could not start (%d)" % err)
