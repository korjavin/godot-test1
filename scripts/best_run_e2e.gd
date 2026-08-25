extends SceneTree
## End-to-end check of the CLIENT half of the personal best-run store, against a
## real lobby.
##
##     godot --headless --path . --script res://scripts/best_run_e2e.gd -- \
##         --lobby=ws://127.0.0.1:8080
##
## Prints `BEST_RUN OK` and exits 0; any failure prints `BEST_RUN FAILED: …` and
## exits 1. `scripts/mp_e2e.sh` runs it against the lobby it already started.
##
## WHY THIS EXISTS RATHER THAN A UNIT TEST: `server/best_test.go` already pins the
## store's semantics from the Go side, and none of that catches the ways the
## CLIENT half fails silently — a wrong URL (the lobby's origin is derived from a
## `wss://` one), a POST the server refuses over its method or content type, a
## response shape the parser drops, or a request that never leaves at all. Every
## one of those ends in "records just never sync", with no error anywhere, which
## is precisely the failure this bead was filed about. So the check drives the
## real `BestRunStore` over real HTTP.
##
## TWO TRAPS IT HAD TO BE WRITTEN AROUND, both of which made an earlier version
## pass while sending nothing at all:
##
##   1. A node added to `root` inside `_initialize()` is NOT `is_inside_tree()`
##      until the first frame, and `HTTPRequest.request()` answers
##      ERR_UNCONFIGURED there. Hence the `await process_frame` before anything
##      is built. (The game is unaffected — `player_controller` adds the store
##      from its own `_ready()`.)
##   2. The reader would happily satisfy the assertion out of the LOCAL store,
##      which `submit()` has just written. So the local record is cleared between
##      the write and the read, and only a server answer can raise it again.
##
## It leaves the machine's `user://best_run.cfg` exactly as it found it — see
## `_restore_local`. `--lobby=` is read by `LobbyClient.resolve_lobby_url()`,
## which `BestRunStore` goes through, so this needs no argument of its own.

const TIMEOUT_SEC: float = 20.0
const POLL_SEC: float = 0.5

## The pre-run contents of the local config, restored on the way out. `null` when
## there was no file (the fresh-machine case), which `_restore_local` deletes for.
var _saved_cfg: Variant = null


func _initialize() -> void:
	_run()


func _finish(code: int, message: String) -> void:
	_restore_local()
	print(message)
	quit(code)


func _backup_local() -> void:
	if FileAccess.file_exists(BestRunStore.CONFIG_PATH):
		_saved_cfg = FileAccess.get_file_as_bytes(BestRunStore.CONFIG_PATH)


func _restore_local() -> void:
	if _saved_cfg == null:
		DirAccess.remove_absolute(BestRunStore.CONFIG_PATH)
		return
	var f := FileAccess.open(BestRunStore.CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_buffer(_saved_cfg as PackedByteArray)
		f.close()


func _clear_local_records() -> void:
	"""Zero the stored records, keeping the player id — that is the whole point."""
	var cfg := ConfigFile.new()
	cfg.load(BestRunStore.CONFIG_PATH)
	cfg.set_value(BestRunStore.CONFIG_SECTION, "distance", 0)
	cfg.set_value(BestRunStore.CONFIG_SECTION, "coins", 0)
	cfg.save(BestRunStore.CONFIG_PATH)


func _make_store() -> BestRunStore:
	var store := BestRunStore.new()
	root.add_child(store)
	return store


func _run() -> void:
	# Trap 1 (see the header): without this every request answers ERR_UNCONFIGURED.
	await process_frame

	var lobby: String = LobbyClient.http_url()
	print("BEST_RUN: lobby %s" % lobby)
	if not (lobby.begins_with("http://") or lobby.begins_with("https://")):
		_finish(1, "BEST_RUN FAILED: http_url() produced %s — the ws→http rewrite is broken" % lobby)
		return

	_backup_local()

	var store := _make_store()

	# The id has to be stable and acceptable to the lobby's `^[A-Za-z0-9_-]{8,64}$`
	# guard — a regenerated or malformed id means every request 400s and the whole
	# feature silently does nothing.
	var id := store.player_id()
	if id.length() != BestRunStore.PLAYER_ID_HEX_LEN or not id.is_valid_hex_number():
		_finish(1, "BEST_RUN FAILED: player id '%s' is not %d hex characters"
			% [id, BestRunStore.PLAYER_ID_HEX_LEN])
		return
	if store.player_id() != id:
		_finish(1, "BEST_RUN FAILED: player id is not stable within one store")
		return

	# A distance nobody could reach by playing, so the assertion cannot be
	# satisfied by whatever this machine's real record happens to be.
	var target_distance := 900000 + (Time.get_ticks_msec() % 1000)
	var target_coins := 4242
	store.submit(target_distance, target_coins)

	# Trap 2: the record is now in the LOCAL store as well. Clear it, so the only
	# thing that can raise the reader's numbers is the lobby.
	_clear_local_records()

	# A SECOND store, so the read cannot come out of the first one's memory. It
	# shares the id, which is the point: that is how the same player on another
	# device finds their record.
	var reader := _make_store()
	if reader.player_id() != id:
		_finish(1, "BEST_RUN FAILED: a second store minted a different id — the id does not persist")
		return

	# Polled rather than awaited once, because the POST above is still in flight:
	# the first GET may legitimately beat it to the server.
	var waited := 0.0
	while waited < TIMEOUT_SEC and reader.distance < target_distance:
		reader.fetch()
		await create_timer(POLL_SEC).timeout
		waited += POLL_SEC

	if reader.distance < target_distance:
		_finish(1, "BEST_RUN FAILED: server never returned the submitted distance (got %d, wanted %d)"
			% [reader.distance, target_distance])
		return
	if reader.coins < target_coins:
		_finish(1, "BEST_RUN FAILED: server returned coins %d, wanted at least %d"
			% [reader.coins, target_coins])
		return

	# "Records only ever go up" is pinned server-side in server/best_test.go, which
	# is where it belongs — repeating it from here would only re-test the Go code
	# over a slower wire.
	_finish(0, "BEST_RUN OK: id %s, distance %d, coins %d" % [id, reader.distance, reader.coins])
