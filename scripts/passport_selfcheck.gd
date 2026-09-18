extends SceneTree
## ============================================================================
## DISCOVERY PASSPORT SELF-CHECK — run headless, prints "SELFCHECK OK", exits 0
## ============================================================================
##
##     godot --headless --path . --script res://scripts/passport_selfcheck.gd
##
## Guards (bead godot-test1-0bnw.1), each mutation-tested:
##  a. UNION: merge [a,b] then [b,c] → [a,b,c], sorted, no duplicates; merge []
##     writes nothing (mtime unchanged); a hand-edited non-array, a 300-entry
##     array and an entry "../x" read back sanitized; the 129th id is dropped.
##  b. MONOTONE ACROSS new_game(): the found set survives a fresh world.
##  c. STAMP ON ARRIVAL: the real toast `_scan()` over a stub kind-0 marker
##     stamps "stonehenge" with no answer given; a second arrival, a re-seeded
##     re-arrival and a kind-less marker write nothing new.
##  d. KEY IS FREE: J collides with no input-map action and no other panel's
##     constant (the city_map_selfcheck check-1 pattern, delegated), and the
##     help card carries a J row.
##  e. PANEL: with 3 found the count line says 3, exactly 3 cards carry a name
##     and 45 carry none; without terrain the found cards show name + stamp and
##     no silhouette; with terrain the found three bake textures that are the
##     SAME object on a second open; solo open takes one pause, a stubbed room
##     or a game-over stub takes none, close releases.
##  f. NO PAYOUT: the panel's source names no coin, no submit(, no coin-adding
##     call — opening and stamping move no currency.
##  g. REGISTRY: 48 rows, every builder maps to a distinct store-shaped id,
##     every stamp ≤ 60 chars with a de row that differs.
##  h. CURSOR (round 2): open frees a CAPTURED mouse and remembers it, close
##     re-captures unless the game is over — pinned by source (headless ignores
##     a CAPTURED set, measured by capture check 21) plus the already-free
##     runtime round trip.
##  i. LOBBY FOLD (bead 0bnw.2): the GET reply's `found` unions through the
##     shipped sanitizer and merge (malformed shapes merge nothing, a smaller
##     set never shrinks), and the POST body carries the set.
##
## The store probes drive the REAL `BestRunStore` statics with
## `Sentinel.isolate_user_state()` first, so no real profile is touched.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")
const ToastScript := preload("res://scripts/landmark_toast.gd")
const TerrainScript := preload("res://scripts/endless_terrain.gd")
const CityMapCheck := preload("res://scripts/city_map_selfcheck.gd")
const HelpOverlay := preload("res://scripts/help_overlay.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	await process_frame
	_check_union()
	_check_monotone()
	_check_stamp()
	_check_key()
	await _check_panel()
	_check_no_payout()
	_check_registry()
	_check_cursor()
	_check_lobby_fold()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	printerr("SELFCHECK FAILED (%d)" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _write_found_raw(raw: String) -> void:
	"""Hand-edit the scratch profile's passport layer, bypassing the merge."""
	var cfg := ConfigFile.new()
	cfg.load(BestRunStore.config_path)
	cfg.set_value(BestRunStore.CONFIG_PASSPORT_SECTION, BestRunStore.CONFIG_PASSPORT_KEY, raw)
	cfg.save(BestRunStore.config_path)


func _read_found_raw() -> Array:
	"""The scratch profile's passport layer as stored, parse or bust."""
	var cfg := ConfigFile.new()
	if cfg.load(BestRunStore.config_path) != OK:
		return ["<unreadable>"]
	var parsed: Variant = JSON.parse_string(
			String(cfg.get_value(BestRunStore.CONFIG_PASSPORT_SECTION, BestRunStore.CONFIG_PASSPORT_KEY, "")))
	return parsed if typeof(parsed) == TYPE_ARRAY else ["<not-an-array>"]


func _check_union() -> void:
	## Assertion (a) — the found set merges by union, bounded and sanitized.
	BestRunStore.merge_found_landmark_ids(["alpha", "beta"])
	if BestRunStore.found_landmark_ids() != ["alpha", "beta"]:
		_fail("merge [alpha, beta] reads back %s, wanted [alpha, beta]"
				% str(BestRunStore.found_landmark_ids()))
	BestRunStore.merge_found_landmark_ids(["beta", "gamma"])
	if BestRunStore.found_landmark_ids() != ["alpha", "beta", "gamma"]:
		_fail("a second merge did not union: %s" % str(BestRunStore.found_landmark_ids()))
	# ...and the FILE holds exactly that — sorted, no duplicates. The read path
	# dedupes on the way in, so only the raw layer proves the write merged
	# rather than appended.
	if _read_found_raw() != ["alpha", "beta", "gamma"]:
		_fail("the stored layer holds %s, wanted the sorted deduped union"
				% str(_read_found_raw()))

	# An empty merge writes nothing — a revisit must not recreate a profile the
	# player deleted, nor cost a round trip.
	var mtime: int = FileAccess.get_modified_time(BestRunStore.config_path)
	BestRunStore.merge_found_landmark_ids([])
	if FileAccess.get_modified_time(BestRunStore.config_path) != mtime:
		_fail("merge [] rewrote the file — a no-op merge must not touch the disk")

	# A hand-edited non-array reads back as nothing found.
	_write_found_raw("oops")
	if not BestRunStore.found_landmark_ids().is_empty():
		_fail("a non-array passport layer reads back %s, wanted []"
				% str(BestRunStore.found_landmark_ids()))

	# A 300-entry dump is bounded at 128.
	var dump: Array = []
	for i in range(300):
		dump.append("place_%d" % i)
	_write_found_raw(JSON.stringify(dump))
	var bounded: Array[String] = BestRunStore.found_landmark_ids()
	if bounded.size() != BestRunStore.MAX_FOUND_IDS:
		_fail("a 300-entry dump reads back %d ids, wanted the %d bound"
				% [bounded.size(), BestRunStore.MAX_FOUND_IDS])

	# A hostile entry is skipped while the good one beside it is kept; the
	# 129th id is dropped.
	_write_found_raw("[]")
	BestRunStore.merge_found_landmark_ids(["../x", "ok_id"])
	if BestRunStore.found_landmark_ids() != ["ok_id"]:
		_fail("merge [../x, ok_id] reads back %s, wanted [ok_id]"
				% str(BestRunStore.found_landmark_ids()))
	var many: Array = []
	for i in range(129):
		many.append("site_%d" % i)
	BestRunStore.merge_found_landmark_ids(many)
	if BestRunStore.found_landmark_ids().size() != BestRunStore.MAX_FOUND_IDS:
		_fail("129 ids merged to %d, wanted the %d bound"
				% [BestRunStore.found_landmark_ids().size(), BestRunStore.MAX_FOUND_IDS])
	Sentinel.done("union")


func _check_monotone() -> void:
	## Assertion (b) — a fresh world keeps the passport.
	_write_found_raw("[]")
	BestRunStore.merge_found_landmark_ids(["alpha"])
	BestRunStore.new_game()
	if BestRunStore.found_landmark_ids() != ["alpha"]:
		_fail("new_game() left the passport at %s — the found set must outlive the run"
				% str(BestRunStore.found_landmark_ids()))
	Sentinel.done("monotone")


func _check_stamp() -> void:
	## Assertion (c) — the real toast `_scan()` stamps kind 0 as "stonehenge"
	## with no answer given, and repeats, re-seeds and kind-less markers add
	## nothing.
	_write_found_raw("[]")
	var toast := ToastScript.new()
	root.add_child(toast)
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	var seed_script := GDScript.new()
	seed_script.source_code = "extends Node3D\nvar run_seed: int = 7\n"
	if seed_script.reload() != OK:
		_fail("the run-seed stub script did not compile")
		return
	var seed_node := Node3D.new()
	seed_node.set_script(seed_script)
	seed_node.add_to_group("terrain")
	root.add_child(seed_node)
	var marker := Node3D.new()
	marker.set_meta("kind", 0)
	marker.set_meta("radius", 10.0)
	marker.add_to_group("landmark")
	root.add_child(marker)

	toast._scan()
	if BestRunStore.found_landmark_ids() != ["stonehenge"]:
		_fail("a first arrival at kind 0 stamped %s, wanted [stonehenge] — without any answer given"
				% str(BestRunStore.found_landmark_ids()))

	# A second arrival in the same run writes nothing new: walk out past the
	# latch, cancel the pending quiz, walk back in.
	player.position = Vector3(100.0, 0.0, 0.0)
	toast._scan()
	toast._cancel_quiz()
	player.position = Vector3.ZERO
	toast._scan()
	if BestRunStore.found_landmark_ids() != ["stonehenge"]:
		_fail("a second arrival restamped %s" % str(BestRunStore.found_landmark_ids()))

	# A re-seed empties the run's visited latch, so the arrival is first again —
	# but the union makes the repeat free.
	seed_node.set("run_seed", 8)
	player.position = Vector3(100.0, 0.0, 0.0)
	toast._scan()
	toast._cancel_quiz()
	player.position = Vector3.ZERO
	toast._scan()
	if BestRunStore.found_landmark_ids() != ["stonehenge"]:
		_fail("a re-seeded re-arrival restamped %s" % str(BestRunStore.found_landmark_ids()))

	# A marker with no kind meta (a city place has no marker at all) stamps
	# nothing, whatever the quiz says — probed against an EMPTY store so even
	# a repeat of an already-found id would show.
	_write_found_raw("[]")
	var bare := Node3D.new()
	# Far from every earlier marker: the per-run visited latch keys on position,
	# so a bare marker at the origin would return before ever reaching the stamp
	# under test and the probe would pass vacuously.
	bare.position = Vector3(500.0, 0.0, 500.0)
	root.add_child(bare)
	toast._first_visit(bare)
	if not BestRunStore.found_landmark_ids().is_empty():
		_fail("a kind-less marker stamped %s" % str(BestRunStore.found_landmark_ids()))

	for node in [marker, bare, player, seed_node]:
		root.remove_child(node)
		node.free()
	root.remove_child(toast)
	toast.free()
	Sentinel.done("stamp")


func _check_key() -> void:
	## Assertion (d) — J is free and the help card says so.
	var key: int = int(PassportPanel.TOGGLE_KEY)
	if key == 0:
		_fail("the panel's TOGGLE_KEY is 0 — it can never be pressed")
		Sentinel.done("key")
		return
	# Against the input map: a gameplay action is REBINDABLE and a panel key is
	# not, so a collision here is unfixable from inside the game.
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventKey):
				continue
			var as_key := event as InputEventKey
			if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
				_fail("TOGGLE_KEY %s is also bound to the input action \"%s\""
						% [OS.get_keycode_string(key), action])
	# Against every other raw-keycode panel: the city_map_selfcheck check-1
	# pattern, delegated — own row skipped by label, same as there.
	var owners: Array = []
	for row: Array in CityMapCheck.panel_key_owners():
		if String(row[1]) != "passport_panel.TOGGLE_KEY":
			owners.append(row)
	var claimed: String = CityMapCheck._owner_claiming(key, owners)
	if not claimed.is_empty():
		_fail("TOGGLE_KEY %s is already %s" % [OS.get_keycode_string(key), claimed])
	# The help card carries the J row, worded as its CSV key.
	var help_found := false
	for row: Array in HelpOverlay.ROWS:
		if String(row[0]) == "J":
			help_found = true
			if String(row[1]) != "Open your discovery passport.":
				_fail("the help J row says %s — it must read as its CSV key"
						% String(row[1]).c_escape())
	if not help_found:
		_fail("help_overlay carries no J row — a panel nobody can find is a panel that does not exist")
	Sentinel.done("key")


func _check_panel() -> void:
	## Assertion (e) — the grid, the bake-once silhouettes and the pause policy.
	_write_found_raw(JSON.stringify(["stonehenge", "moai", "giza"]))
	var panel := PassportPanel.new()
	root.add_child(panel)

	# WITHOUT terrain: found cards show name + stamp and no silhouette, and
	# nothing errors on the blank path.
	panel.set_panel_open(true)
	_assert_grid(panel, 3, 45, "blank path")
	for i in [0, 1, 2]:
		var card: Dictionary = (panel._cards as Array)[i]
		if (card["silhouette"] as TextureRect).visible:
			_fail("a found card shows a silhouette with no terrain in the tree")
		if String((card["name"] as Label).text).is_empty():
			_fail("a found card shows no name on the blank path")
		if String((card["stamp"] as Label).text).is_empty():
			_fail("a found card shows no stamp on the blank path")
	panel.set_panel_open(false)

	# WITH a live terrain: the found three bake textures. A bare body in the
	# player group lets its `_ready()` run past the player lookup; the render
	# distance is zeroed before the first frame so no chunk ever generates.
	var ready_player := Node3D.new()
	ready_player.add_to_group("player")
	root.add_child(ready_player)
	var terrain := Node3D.new()
	terrain.set_script(TerrainScript)
	root.add_child(terrain)
	terrain.set("render_distance", 0)
	terrain.set("spawn_crocodiles", false)
	await process_frame
	await process_frame
	panel.set_panel_open(true)
	_assert_grid(panel, 3, 45, "baked path")
	var first_textures: Array = []
	for i in [0, 1, 2]:
		var card: Dictionary = (panel._cards as Array)[i]
		var texture: Texture2D = (card["silhouette"] as TextureRect).texture
		if texture == null or not (card["silhouette"] as TextureRect).visible:
			_fail("found card %d baked no silhouette with a live terrain" % i)
		first_textures.append(texture)
	# A second open reuses the bake: the SAME texture objects, not lookalikes.
	panel.set_panel_open(false)
	panel.set_panel_open(true)
	for i in [0, 1, 2]:
		var card: Dictionary = (panel._cards as Array)[i]
		if (card["silhouette"] as TextureRect).texture != first_textures[i]:
			_fail("found card %d rebaked its silhouette on reopen — the bake is once, not per open" % i)
	panel.set_panel_open(false)

	# The bake is done: free the terrain and its body now, so the pause cases
	# below read exactly the stubs they stage — `get_first_node_in_group` answers
	# in join order, and a leftover body would shadow the game-over stub.
	root.remove_child(terrain)
	terrain.free()
	root.remove_child(ready_player)
	ready_player.free()

	# SOLO: one pause claim while open, none after close.
	panel.set_panel_open(true)
	if PauseHub.holder_count() != 1:
		_fail("a solo open holds %d pauses, wanted 1" % PauseHub.holder_count())
	panel.set_panel_open(false)
	if PauseHub.holder_count() != 0:
		_fail("closing the panel left %d pauses held" % PauseHub.holder_count())

	# IN A ROOM: the panel freezes nothing.
	var room_script := GDScript.new()
	room_script.source_code = "extends Node\nfunc is_busy() -> bool:\n\treturn true\n"
	if room_script.reload() != OK:
		_fail("the room stub script did not compile")
	else:
		var room := Node.new()
		room.set_script(room_script)
		room.add_to_group("mp")
		root.add_child(room)
		panel.set_panel_open(true)
		if PauseHub.holder_count() != 0:
			_fail("opening in a room holds %d pauses — the room policy freezes nothing" % PauseHub.holder_count())
		panel.set_panel_open(false)
		root.remove_child(room)
		room.free()

	# OVER GAME OVER: the same refusal.
	var over_script := GDScript.new()
	over_script.source_code = "extends Node\nvar is_game_over: bool = true\n"
	if over_script.reload() != OK:
		_fail("the game-over stub script did not compile")
	else:
		var over := Node.new()
		over.set_script(over_script)
		over.add_to_group("player")
		root.add_child(over)
		panel.set_panel_open(true)
		if PauseHub.holder_count() != 0:
			_fail("opening over game over holds %d pauses — GameOverUI owns that screen" % PauseHub.holder_count())
		panel.set_panel_open(false)
		root.remove_child(over)
		over.free()

	root.remove_child(panel)
	panel.free()
	Sentinel.done("panel")


func _assert_grid(panel: PassportPanel, named: int, dotted: int, where: String) -> void:
	"""Exactly `named` cards carry a name and `dotted` show only the frame."""
	var names := 0
	var frames := 0
	for card_variant: Variant in (panel._cards as Array):
		var card: Dictionary = card_variant
		if (card["name"] as Label).visible and not String((card["name"] as Label).text).is_empty():
			names += 1
		if (card["dotted"] as Control).visible:
			frames += 1
	if names != named:
		_fail("%s: %d cards carry a name, wanted %d" % [where, names, named])
	if frames != dotted:
		_fail("%s: %d cards show only the dotted frame, wanted %d" % [where, frames, dotted])
	# The count line says the number, never a percentage and never "of 48".
	var want: String = tr(PassportPanel.COUNT_LINE) % named
	if panel._count_label.text != want:
		_fail("%s: the count line says %s, wanted %s"
				% [where, panel._count_label.text.c_escape(), want.c_escape()])


func _check_no_payout() -> void:
	## Assertion (f) — opening and stamping move no currency: the panel's source
	## names no coin and no call that could pay one.
	var source: String = FileAccess.get_file_as_string("res://scripts/passport_panel.gd")
	if source.is_empty():
		_fail("could not read passport_panel.gd to scan it for payouts")
		return
	for word: String in ["coin", "submit(", "collect_coin", "bank_awarded", "add_coins", "_sfx("]:
		if source.contains(word):
			_fail("passport_panel.gd names %s — the passport counts, it never pays" % word.c_escape())
	Sentinel.done("no_payout")


func _check_registry() -> void:
	## Assertion (g) — 48 rows, distinct store-shaped ids, short translated stamps.
	var registry: Array = LandmarkBuilders.LANDMARKS
	if registry.size() != 48:
		_fail("the field registry holds %d rows, wanted the 48 the passport shows" % registry.size())
		Sentinel.done("registry")
		return
	var seen := {}
	for i in range(registry.size()):
		var entry: Dictionary = registry[i]
		for field: String in ["builder", "name", "fact", "radius", "region", "stamp"]:
			if not entry.has(field):
				_fail("row %d has no %s" % [i, field])
		var builder: String = String(entry.get("builder", ""))
		if not builder.begins_with("_landmark_"):
			_fail("row %d builder %s carries no _landmark_ prefix to strip" % [i, builder.c_escape()])
			continue
		var id: String = builder.trim_prefix("_landmark_")
		if seen.has(id):
			_fail("a second builder maps to %s — passport ids must be distinct" % id.c_escape())
		seen[id] = true
		# The id must survive the store it is written to: through the SHIPPED
		# sanitizer, not a copy of its rule.
		if BestRunStore._sanitize_found_ids([id]) != [id]:
			_fail("registry id %s does not survive the passport store's sanitizer" % id.c_escape())
		var stamp: String = String(entry.get("stamp", ""))
		if stamp.is_empty():
			_fail("row %d carries no stamp phrase" % i)
		elif stamp.length() > 60:
			_fail("the %s stamp is %d chars — the card holds 60" % [id.c_escape(), stamp.length()])
	var restore: String = TranslationServer.get_locale()
	TranslationServer.set_locale("de")
	for i in range(registry.size()):
		var stamp: String = String((registry[i] as Dictionary).get("stamp", ""))
		if stamp.is_empty():
			continue
		if tr(stamp) == stamp:
			_fail("the %s stamp has no de row — it would read English in a German game" % stamp.c_escape())
	TranslationServer.set_locale(restore)
	Sentinel.done("registry")


func _check_cursor() -> void:
	## Assertion (h, round 2) — the cursor is freed on open and given back on
	## close, `skill_tree_ui`'s rule mirrored.
	##
	## HEADLESS CAVEAT, MEASURED BY capture_selfcheck CHECK 21 (not re-assumed
	## here): the headless DisplayServer IGNORES `set_mouse_mode(CAPTURED)`, so
	## no probe can observe the release half — feeding CAPTURED through open
	## would pass vacuously. The release and the re-capture are therefore pinned
	## BY SOURCE (both mutation-tested), and the runtime probe covers what
	## headless CAN observe: the already-free round trip.
	var source: String = FileAccess.get_file_as_string("res://scripts/passport_panel.gd")
	if source.is_empty():
		_fail("could not read passport_panel.gd to check the cursor rule")
		Sentinel.done("cursor")
		return
	# The open arm frees a CAPTURED mouse and remembers that WE did it.
	if not source.contains("Input.mouse_mode == Input.MOUSE_MODE_CAPTURED"):
		_fail("the open path reads no CAPTURED guard — it would free a cursor it does not own")
	if not source.contains("Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)"):
		_fail("the open path never frees the mouse — the grid cannot be scrolled or clicked")
	if not source.contains("_recapture_mouse = true"):
		_fail("the open path remembers no release — close cannot know the cursor is ours")
	# The close arm gives the capture back, but never over game over.
	if not source.contains("Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)"):
		_fail("the close path never re-captures — the run resumes with a free cursor")
	if not source.contains("if not _game_over()"):
		_fail("the close path re-captures unconditionally — over game over the cursor is GameOverUI's")
	# Runtime, already-free round trip: VISIBLE in, VISIBLE out, flag untouched.
	var panel := PassportPanel.new()
	root.add_child(panel)
	var started: int = int(Input.mouse_mode)
	panel.set_panel_open(true)
	panel.set_panel_open(false)
	if int(Input.mouse_mode) != started:
		_fail("an already-free open/close moved the mouse mode from %d to %d"
				% [started, int(Input.mouse_mode)])
	if bool(panel._recapture_mouse):
		_fail("an already-free open set the re-capture flag — close would capture a free cursor")
	root.remove_child(panel)
	panel.free()
	Sentinel.done("cursor")


func _check_lobby_fold() -> void:
	## Assertion (i, bead 0bnw.2) — the GET reply's `found` folds through the
	## SHIPPED sanitizer and merge: union in, malformed out, never a shrink.
	## Drives the REAL `_on_get_completed` on a real store node with crafted
	## reply bodies — not a copy of the fold. (A fold that leaves the server
	## behind fires one fire-and-forget catch-up POST; the node is freed right
	## after, cancelling it — the probes assert the synchronous store state.)
	_write_found_raw(JSON.stringify(["bravo", "charlie"]))
	var store := BestRunStore.new()
	root.add_child(store)
	var reply := func(found: Variant) -> void:
		var body := JSON.stringify(
				{"distance": 0, "coins": 0, "lifetime": 0, "spent": 0, "found": found})
		store._on_get_completed(
				HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body.to_utf8_buffer())

	# Union: the server's alpha joins the local bravo/charlie. (`call` is
	# variadic — one argument that happens to be an Array arrives as that
	# Array, so no extra wrapping; `callv` would want the args list.)
	reply.call(["alpha", "bravo"])
	if BestRunStore.found_landmark_ids() != ["alpha", "bravo", "charlie"]:
		_fail("a found reply did not union: %s" % str(BestRunStore.found_landmark_ids()))

	# A non-array found merges nothing.
	reply.call("oops")
	if BestRunStore.found_landmark_ids() != ["alpha", "bravo", "charlie"]:
		_fail("a non-array found reply moved the set: %s" % str(BestRunStore.found_landmark_ids()))

	# Non-string entries are skipped while the shaped one beside them joins.
	reply.call(["delta", 42, null])
	if BestRunStore.found_landmark_ids() != ["alpha", "bravo", "charlie", "delta"]:
		_fail("a mixed found reply folded as %s" % str(BestRunStore.found_landmark_ids()))

	# A SMALLER reply never shrinks the local set.
	reply.call(["alpha"])
	if BestRunStore.found_landmark_ids() != ["alpha", "bravo", "charlie", "delta"]:
		_fail("a smaller found reply shrank the set: %s" % str(BestRunStore.found_landmark_ids()))

	# An unparseable body merges nothing at all.
	store._on_get_completed(
			HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "not json".to_utf8_buffer())
	if BestRunStore.found_landmark_ids() != ["alpha", "bravo", "charlie", "delta"]:
		_fail("an unparseable reply moved the set: %s" % str(BestRunStore.found_landmark_ids()))

	root.remove_child(store)
	store.free()

	# ...and the POST carries the set: without it no device ever learns what
	# the others found.
	var source: String = FileAccess.get_file_as_string("res://scripts/best_run_store.gd")
	if source.is_empty():
		_fail("could not read best_run_store.gd to check the POST body")
	elif not source.contains('"found": found_landmark_ids()'):
		_fail("the /best POST body carries no found set — cross-device sync sends nothing")
	Sentinel.done("lobby_fold")
