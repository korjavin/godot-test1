extends SceneTree
## The one runnable check for the minimap HUD. Run it headless:
##
##     godot --headless --path . --script res://scripts/minimap_selfcheck.gd
##
## Prints "SELFCHECK OK" and quits 0, or prints the first failure and quits 1.
## Explicit `if`s rather than `assert`s, for the same reason mp_selfcheck.gd gives:
## asserts are stripped from release builds and this file's value is that it still
## works when somebody runs it against one a year from now.
##
## WHAT IT GUARDS, and why each is worth a check:
##
##   1. The map reads the coin road out of endless_terrain's station cache through
##      `road_stations` / `road_k_min` / `road_k_max` / `_road_first_k_at_or_after_x`
##      — internals of another script, reached through a has_method() guard. That
##      guard is what makes a rename FAIL SILENTLY: the map keeps drawing, just with
##      no road on it, and nothing anywhere logs a word. This check is the alarm.
##   2. The north-up mapping (world +X → screen right, +Z → screen down). Getting a
##      sign wrong here mirrors the map, which looks plausible and is completely
##      wrong to navigate by.
##   3. The croc dot cap is a safety bound, not a limit play reaches — if it starts
##      biting, near crocodiles get dropped in favour of far ones (the group is in
##      spawn order, not distance order).
##
## It boots the real main scene, because the road station cache only exists once a
## chunk has generated — there is nothing pure to test in isolation here.

func _initialize() -> void:
	# _initialize() cannot await, so the scene-booting half runs as its own
	# coroutine; the tree keeps processing until it calls quit().
	_run()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	# The start overlay PAUSES THE TREE until somebody presses PLAY SOLO, and a
	# paused tree runs neither the minimap's `_process` nor the SceneTree timer
	# below — so without this the check would time out against a world frozen on
	# frame one and report "minimap never read the player". Pressing solo is
	# exactly what a player does; `has_method` keeps this inert if the overlay is
	# ever renamed or dropped.
	#
	# The `await` is load-bearing: `_initialize()` runs BEFORE the first idle
	# frame, so the scene's `_ready()`s have not run yet and dismissing here would
	# be undone by the overlay's own `_ready()` taking the pause a moment later —
	# with its `_process` already switched off, nothing would ever release it.
	await process_frame
	var overlay: Node = main.get_node_or_null("HUD/StartOverlay")
	if overlay != null and overlay.has_method("_on_play_solo_pressed"):
		overlay._on_play_solo_pressed()
	# Two seconds: long enough for the spawn ring of chunks to build (which is what
	# fills the road station cache) and for several 5 Hz minimap ticks to run.
	await create_timer(2.0).timeout
	var failure := _check()
	if failure.is_empty():
		print("SELFCHECK OK")
		quit(0)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _check() -> String:
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	if map == null:
		return "no MinimapHUD under Main/HUD — was it dropped from main.tscn?"
	var terrain: Node = get_first_node_in_group("terrain")
	if terrain == null:
		return "no node in the \"terrain\" group"

	# 1. The road window. The player spawns on station 0 at the world origin, so a
	#    healthy map has a road running right across the disc.
	if not terrain.has_method("_road_first_k_at_or_after_x"):
		return "endless_terrain._road_first_k_at_or_after_x is gone — minimap_hud." \
			+ "_gather_road() guards on it, so the road would silently vanish"
	if not map._have_data:
		return "minimap never read the player"
	if map._road_count < 2:
		return "road window is empty (%d points) — the station cache walk is broken" % map._road_count
	var on_disc := 0
	for i in range(map._road_count):
		if (map._road_points[i] - map.MAP_CENTER).length() <= map.MAP_RADIUS + 1.0:
			on_disc += 1
	if on_disc < 2:
		return "the road never crosses the map disc (%d of %d points on it)" % [on_disc, map._road_count]

	# 2. North-up orientation. The player spawns facing +X (the run direction), which
	#    must come out as screen RIGHT. A mirrored map passes every other check.
	if absf(map._facing.length() - 1.0) > 0.001:
		return "facing vector is not normalised: %s" % map._facing
	var player: Node3D = get_first_node_in_group("player")
	var forward: Vector3 = -player.global_transform.basis.z
	if absf(map._facing.x - forward.x) > 0.01 or absf(map._facing.y - forward.z) > 0.01:
		return "facing %s does not match the player's forward (%f, %f) — north-up mapping is wrong" \
			% [map._facing, forward.x, forward.z]

	# 3. The crocodile dot cap must be a bound, not a limit reached in play.
	if map._croc_count >= map.MAX_CROC_DOTS:
		return "croc dot cap (%d) is biting — nearby crocodiles can be dropped for far ones" \
			% map.MAX_CROC_DOTS

	print("road points %d (%d on disc) | facing %s | crocs %d/%d | biome %d river %s" % [
		map._road_count, on_disc, map._facing, map._croc_count, map.MAX_CROC_DOTS,
		map._biome, map._in_river])
	return ""
