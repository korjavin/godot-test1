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

var _failures: Array[String] = []


func _initialize() -> void:
	# ONE FRAME FIRST: `_initialize()` runs before the main loop, and a node added
	# to `root` before it answers null to `get_tree()` — the lesson
	# `pause_selfcheck` and `minimap_selfcheck` both record at length.
	await process_frame

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

	Sets the four run totals to known nonzero values, teleports to the gate via
	the SHIPPED function, and asserts all four survive, the body lands near the
	destination on built ground, and the whole thing takes under a second.
	"""
	var boot: Array = await _boot()
	if bool(boot[0]):
		_fail(String(boot[1]))
		Sentinel.done("run_preserved")
		return
	var player: Node = boot[1]
	var terrain: Node = get_first_node_in_group("terrain")
	player.coins_collected = 100
	player.run_distance = 1500
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
	if player.global_position.y < -5.0 or player.global_position.y > 6.0:
		_fail("the player is at y=%.1f after the teleport — not on ground" % player.global_position.y)
	if player.coins_collected != 100 or player.run_distance != 1500 \
			or player.coin_streak != 7 or player.explored_mask != 3:
		_fail("the teleport changed run state (coins=%d distance=%d streak=%d mask=%d) — it must preserve the run" % [
			player.coins_collected, player.run_distance, player.coin_streak, player.explored_mask])
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
