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
## IT NEVER OPENS THE MACHINE'S `user://best_run.cfg`. `BestRunStore.config_path`
## is pointed at `LOCAL_STORE_PATH` before the first store is built, so this runs
## against a throwaway profile with a throwaway player id. It used to back the
## real file up and put it back, and that was wrong twice over: every local write
## is a monotone read-modify-write merge, so a developer's real record leaked into
## what this measured and got POSTed to the lobby under their real id; and a run
## that died between the backup and the restore left the real record zeroed by
## `_clear_local_records()`. `--lobby=` is read by `LobbyClient.resolve_lobby_url()`,
## which `BestRunStore` goes through, so this needs no argument of its own.

const TIMEOUT_SEC: float = 20.0
const POLL_SEC: float = 0.5

## The throwaway profile this run uses instead of the real one. Removed on the
## way in as well as out, so a killed run leaves nothing behind to be inherited.
const LOCAL_STORE_PATH: String = "user://best_run_e2e.cfg"


func _initialize() -> void:
	_run()


func _finish(code: int, message: String) -> void:
	DirAccess.remove_absolute(LOCAL_STORE_PATH)
	print(message)
	quit(code)


func _isolate_local_store() -> void:
	BestRunStore.config_path = LOCAL_STORE_PATH
	DirAccess.remove_absolute(LOCAL_STORE_PATH)


func _clear_local_records() -> void:
	"""Zero the stored records, keeping the player id — that is the whole point."""
	var cfg := ConfigFile.new()
	cfg.load(BestRunStore.config_path)
	cfg.set_value(BestRunStore.CONFIG_SECTION, "distance", 0)
	cfg.set_value(BestRunStore.CONFIG_SECTION, "coins", 0)
	cfg.set_value(BestRunStore.CONFIG_PROGRESSION_SECTION, "lifetime_coins", 0)
	cfg.set_value(BestRunStore.CONFIG_PROGRESSION_SECTION, "spent_points", 0)
	cfg.save(BestRunStore.config_path)


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

	_isolate_local_store()

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

	# A coin count nobody could reach by playing, so the assertion cannot be
	# satisfied by whatever this machine's real record happens to be.
	var target_coins := 4242 + (Time.get_ticks_msec() % 1000)
	store.submit(0, target_coins)

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
	while waited < TIMEOUT_SEC and reader.coins < target_coins:
		reader.fetch()
		await create_timer(POLL_SEC).timeout
		waited += POLL_SEC

	if reader.coins < target_coins:
		_finish(1, "BEST_RUN FAILED: server never returned the submitted coins (got %d, wanted %d)"
			% [reader.coins, target_coins])
		return

	# CATCH-UP: a record the server has never seen — the upgrade case, where a
	# player already has a local best from before this feature shipped, or banked
	# one while the lobby was unreachable. `fetch()` must PUSH it, not merely read
	# past it, or that history never reaches the player's other devices until they
	# happen to beat it. `_write_local` is the store's own path, so this fakes the
	# pre-existing record the way the old build would have left it.
	var catch_up_coins := target_coins + 1000
	var cfg := ConfigFile.new()
	cfg.load(BestRunStore.config_path)
	cfg.set_value(BestRunStore.CONFIG_SECTION, "coins", catch_up_coins)
	cfg.save(BestRunStore.config_path)

	var upgrader := _make_store()
	upgrader.fetch()
	await create_timer(2.0).timeout

	# Clear local again, so only the lobby can supply the number.
	_clear_local_records()
	var checker := _make_store()
	waited = 0.0
	while waited < TIMEOUT_SEC and checker.coins < catch_up_coins:
		checker.fetch()
		await create_timer(POLL_SEC).timeout
		waited += POLL_SEC
	if checker.coins < catch_up_coins:
		_finish(1, "BEST_RUN FAILED: a pre-existing local record was never pushed to the server (got %d, wanted %d)"
			% [checker.coins, catch_up_coins])
		return

	# PROGRESSION (bead godot-test1-20z.2). Lifetime coins and spent skill points
	# ride the SAME record and the SAME request, so the only thing left to prove
	# from the client side is that they actually survive the round trip — a field
	# the server drops, or a response key the parser never reads, is invisible on
	# this side and shows up as a player's LEVEL resetting on their next device.
	# Driven through the same store, so it also covers the local layer.
	var target_lifetime := 700000 + (Time.get_ticks_msec() % 1000)
	var target_spent := 7
	var writer := _make_store()
	writer.submit_progression(target_lifetime, target_spent)
	_clear_local_records()

	var prog_reader := _make_store()
	waited = 0.0
	while waited < TIMEOUT_SEC and prog_reader.lifetime_coins < target_lifetime:
		prog_reader.fetch()
		await create_timer(POLL_SEC).timeout
		waited += POLL_SEC
	if prog_reader.lifetime_coins < target_lifetime:
		_finish(1, "BEST_RUN FAILED: server never returned lifetime coins (got %d, wanted %d)"
			% [prog_reader.lifetime_coins, target_lifetime])
		return
	if prog_reader.spent_points < target_spent:
		_finish(1, "BEST_RUN FAILED: server returned spent points %d, wanted at least %d"
			% [prog_reader.spent_points, target_spent])
		return
	# The level the player would come back to. Derived, never stored — this is the
	# thing the whole round trip exists to protect.
	var level := Progression.level_for(prog_reader.lifetime_coins)
	if level <= 0:
		_finish(1, "BEST_RUN FAILED: %d lifetime coins derived level %d"
			% [prog_reader.lifetime_coins, level])
		return

	# "Records only ever go up" is pinned server-side in server/best_test.go, which
	# is where it belongs — repeating it from here would only re-test the Go code
	# over a slower wire.
	_finish(0, "BEST_RUN OK: id %s, coins %d, catch-up %d, lifetime %d (level %d), spent %d"
		% [id, reader.coins, checker.coins,
			prog_reader.lifetime_coins, level, prog_reader.spent_points])
