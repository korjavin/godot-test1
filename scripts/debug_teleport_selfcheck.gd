extends SceneTree
## debug_teleport_selfcheck — the debug-only teleport (F2 Budapest gate / F8 HQ,
## bead godot-test1-xtl) preserves the run it moves, and fires only in debug
## builds outside rooms.
##
## Driven against the LIVE world (main.tscn: player, terrain, clock) because
## every claim is about what the shipped `debug_teleport_to()` does to a real
## run — a stub player would re-implement the wipe list the check exists to
## pin. The room half uses a real `MpManager` flipped to IN_ROOM the way
## `mp_selfcheck` flips it, so the refusal drives the shipped `_debug_in_room()`
## predicate, not a copy of it.

const PlayerScript: GDScript = preload("res://scripts/player_controller.gd")

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

## The raw-keycode panel registry, borrowed rather than copied — see
## `_check_keys_are_free()`.
const CityMapSelfcheck: GDScript = preload("res://scripts/city_map_selfcheck.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before it answers null to `get_tree()` — the lesson
	# `pause_selfcheck` and `minimap_selfcheck` both record at length.
	await process_frame

	_check_keys_are_free()
	_check_gate_table()
	_check_gate_wiring()
	await _check_run_preserved()
	await _check_absent_in_room()

	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: " + line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _check_keys_are_free() -> void:
	"""F2 and F8 collide with nothing — `city_map_selfcheck`'s idiom, its list.

	A panel key is not rebindable, so a collision is unfixable from inside the
	game: both surfaces fire, forever. The registry and the two scanners are
	`city_map_selfcheck`'s statics, borrowed rather than copied, so a panel key
	added there is compared against these two the day it lands (and vice versa
	— the teleport's own rows are in that list, and each subject skips its own).
	"""
	var owners: Array = CityMapSelfcheck.panel_key_owners()
	var subjects: Array = [
		[int(PlayerScript.DEBUG_TELEPORT_BUDAPEST_KEY), "player_controller.DEBUG_TELEPORT_BUDAPEST_KEY"],
		[int(PlayerScript.DEBUG_TELEPORT_HQ_KEY), "player_controller.DEBUG_TELEPORT_HQ_KEY"],
	]
	if subjects[0][0] == subjects[1][0]:
		_fail("both teleport keys are %s — one destination is unreachable"
			% OS.get_keycode_string(subjects[0][0]))
	for subject: Array in subjects:
		var key: int = subject[0]
		var label: String = subject[1]
		if key == 0:
			_fail("%s is 0 — it can never be pressed" % label)
			continue
		# Against the input map: a gameplay action is rebindable, this is not.
		# BARE PRESSES ONLY, `tower_lift_selfcheck`'s rule: Godot ships built-in
		# `ui_text_*` actions on modified keys, and a panel key is pressed with
		# nothing held, so a modified event is a different chord and not a
		# collision. Every action this GAME binds is modifier-free.
		for action: StringName in InputMap.get_actions():
			for event: InputEvent in InputMap.action_get_events(action):
				var as_key := event as InputEventKey
				if as_key == null:
					continue
				if as_key.ctrl_pressed or as_key.alt_pressed or as_key.meta_pressed \
						or as_key.shift_pressed:
					continue
				if int(as_key.keycode) == key or int(as_key.physical_keycode) == key:
					_fail("%s (%s) is also bound to the input action \"%s\""
						% [label, OS.get_keycode_string(key), action])
		# ...and against every other raw-keycode panel, its own row excepted.
		var others: Array = []
		for row: Array in owners:
			if String(row[1]) != label:
				others.append(row)
		var claimed: String = CityMapSelfcheck._owner_claiming(key, others)
		if not claimed.is_empty():
			_fail("%s (%s) is already %s" % [label, OS.get_keycode_string(key), claimed])
		# NEGATIVE CONTROL on the scan, `city_map_selfcheck`'s: a nested fake
		# owner must be caught, or the two nested rows in the real list (the
		# hero digits, the quiz answers) are not being compared at all.
		if CityMapSelfcheck._owner_claiming(key, [[[[key]], "a fake nested owner"]]).is_empty():
			_fail("the scan missed a fake owner holding %s — it cannot detect a real collision either" % label)
	Sentinel.done("keys_are_free")


func _check_gate_table() -> void:
	"""The gate predicate's whole truth table, on the shipped static."""
	if not PlayerScript.debug_teleport_allowed(true, false):
		_fail("debug teleport refused in a debug build outside rooms — its only legal case")
	if PlayerScript.debug_teleport_allowed(true, true):
		_fail("debug teleport allowed in a room — the key must be dead there")
	if PlayerScript.debug_teleport_allowed(false, false):
		_fail("debug teleport allowed in a release build — it defeats the win condition")
	if PlayerScript.debug_teleport_allowed(false, true):
		_fail("debug teleport allowed in a release build inside a room")
	Sentinel.done("gate_table")


func _check_gate_wiring() -> void:
	"""The handler really passes the build flag, not a constant.

	Headless runs ARE debug builds, so no runtime probe can distinguish "gated
	on OS.is_debug_build()" from "always on" — the `pause_selfcheck` source
	scan is the established idiom for exactly this: BOTH the key handler and
	`debug_teleport_to()` itself must pass the REAL flag (the handler avoids
	starting a rebuild in release; the function refuses direct callers too).
	Removing either gate must fail here.
	"""
	var text := FileAccess.get_file_as_string("res://scripts/player_controller.gd")
	if text.is_empty():
		_fail("could not read player_controller.gd — the debug gate cannot be verified")
	elif text.count("debug_teleport_allowed(OS.is_debug_build()") < 2:
		_fail("the teleport path no longer passes OS.is_debug_build() at both gates — it is reachable in release builds")
	Sentinel.done("gate_wiring")


func _boot() -> Array:
	"""main.tscn running: the minimap check's prelude (overlay dismissed)."""
	root.add_child(load("res://scenes/main.tscn").instantiate())
	await process_frame
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay == null or not overlay.has_method("_dismiss"):
		return [true, "no dismissible StartOverlay under Main/HUD"]
	overlay._dismiss()
	await process_frame
	var player: Node = get_first_node_in_group("player")
	var terrain: Node = get_first_node_in_group("terrain")
	if player == null or terrain == null:
		return [true, "no player or no terrain after boot"]
	return [false, player]


func _check_run_preserved() -> void:
	"""Teleporting moves the run without corrupting it (the bead's stated rule).

	Sets the run totals to known nonzero values, teleports to the gate via the
	SHIPPED function, and asserts they survive, the body lands near the
	destination on built ground, and the whole thing takes under a second.

	MEASURED A PHYSICS FRAME AFTER THE ARRIVAL, not in the window before one has
	run — `_physics_process` is where every distance total is re-derived from
	the body's position, so an assertion taken before it would pass on a
	teleport that inflates them all a frame later. That frame is why
	`own_distance` is on the list: the shipped function shifts
	`own_distance_origin` by the jump (`_respawn_in_place()`'s line), and
	without that shift this is the assertion that goes red. `run_distance` is
	deliberately NOT on it — it is a running max of raw displacement from the
	world origin, so it must grow, and the check below asserts that it did.
	"""
	var boot: Array = await _boot()
	if bool(boot[0]):
		_fail(String(boot[1]))
		Sentinel.done("run_preserved")
		return
	var player: Node = boot[1]
	var terrain: Node = get_first_node_in_group("terrain")
	player.coins_collected = 100
	player.own_coins = 100
	player.run_distance = 1500
	player.own_distance = 1500
	player.coin_streak = 7
	player.explored_mask = 3
	var dest: Vector3 = PlayerScript.debug_destination_budapest()
	var before: Vector3 = player.global_position
	var msec := Time.get_ticks_msec()
	var ok: bool = await player.debug_teleport_to(dest)
	var dt := Time.get_ticks_msec() - msec
	if not ok:
		_fail("debug_teleport_to() refused in a debug build outside rooms")
		Sentinel.done("run_preserved")
		return
	if dt >= 1000:
		_fail("the teleport took %d ms — the bead promises under a second" % dt)
	if player.global_position.distance_to(dest) > 20.0:
		_fail("the teleport landed %.0f m from its destination" % player.global_position.distance_to(dest))
	if player.global_position.distance_to(before) < 100.0:
		_fail("the teleport did not move the player (still near spawn)")
	var chunk: Vector2i = terrain.world_to_chunk(player.global_position)
	if not terrain.active_chunks.has(chunk):
		_fail("no built chunk under the player after the teleport")
	elif terrain.bare_chunks.has(chunk):
		# `new_run()` floors the ring synchronously, so `active_chunks` alone is
		# satisfied by HALF the sequence — a debt note in `bare_chunks` is the
		# only thing that can see `build_ring_now()` missing, which is the half
		# that stops `_place_near()` probing a bare ring and landing you inside
		# a block that appears two frames later.
		_fail("the chunk under the player is BARE (ground only) — build_ring_now() did not buy its content before _place_near() probed it")
	if player.global_position.y < -5.0 or player.global_position.y > 6.0:
		_fail("the player is at y=%.1f after the teleport — not on ground" % player.global_position.y)
	await physics_frame
	if player.coins_collected != 100 or player.own_coins != 100 \
			or player.coin_streak != 7 or player.explored_mask != 3:
		_fail("the teleport changed run state (coins=%d own_coins=%d streak=%d mask=%d) — it must preserve the run" % [
			player.coins_collected, player.own_coins, player.coin_streak, player.explored_mask])
	if player.own_distance != 1500:
		_fail("the teleport inflated the personal distance record to %d — own_distance_origin was not shifted by the jump" % player.own_distance)
	if player.run_distance <= 1500:
		_fail("run_distance did not follow the body to Budapest (%d) — it is raw displacement and must" % player.run_distance)
	Sentinel.done("run_preserved")


func _check_absent_in_room() -> void:
	"""In a room the key is dead: the shipped function refuses and moves nothing.

	A real `MpManager` flipped to a settled IN_ROOM (the `mp_selfcheck`
	two-assignment fake), so the refusal drives the shipped `_debug_in_room()`
	— `shared_bank()` non-null — and not a copy of the rule.
	"""
	var player: Node = get_first_node_in_group("player")
	if player == null:
		_fail("no player for the room check")
		Sentinel.done("room_absent")
		return
	# main.tscn carries its own solo Multiplayer node first in the "mp" group,
	# and `_mp()` answers the FIRST — so displace it, or the refusal below
	# would read the real solo manager and fire.
	for old: Node in get_nodes_in_group("mp"):
		old.free()
	var mp: Node = MpManager.new()
	mp.add_to_group("mp")
	root.add_child(mp)
	mp._state = MpManager.State.IN_ROOM
	mp._first_member = true
	var home: Vector3 = player.global_position
	player.coins_collected = 100
	var ok: bool = await player.debug_teleport_to(PlayerScript.debug_destination_budapest())
	mp.free()
	if ok:
		_fail("debug_teleport_to() fired inside a room — the key must be dead there")
	if player.global_position.distance_to(home) > 0.01:
		_fail("the refused teleport moved the player %.2f m" % player.global_position.distance_to(home))
	if player.coins_collected != 100:
		_fail("the refused teleport touched run state")
	Sentinel.done("room_absent")
