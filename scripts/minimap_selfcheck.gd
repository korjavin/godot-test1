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
##   4. ZOOM: that every layer really does derive from the ONE shared scale factor.
##      This is the check the zoom feature is written around, because a layer that
##      keeps its own hardcoded metre count still LOOKS right at the default zoom
##      and only parts company with the picture once somebody presses +. Each
##      assertion is therefore an EFFECT measurement with a negative control — a
##      real crocodile placed between the two radii, a road window counted at two
##      zooms — never a read-back of the getter, which a hardcoded site would
##      satisfy while ignoring it.
##   5. TEAMMATES: that the multiplayer teammate layer draws where it should, in
##      the peer's own colour, edge-clamps rather than clips, and — the negative
##      control that matters most — is completely absent solo.
##
## It boots the real main scene, because the road station cache only exists once a
## chunk has generated — there is nothing pure to test in isolation here.


## The values the map shipped with, before zoom existed. They are here as NEGATIVE
## CONTROLS: after a zoom step, a layer still sitting on one of these numbers is a
## layer that hardcoded it instead of deriving from `_view_radius()`.
const LEGACY_VIEW_RADIUS: float = 60.0
const LEGACY_CROC_VIEW_RADIUS: float = 30.0


## A stand-in for `MpManager`, so the teammate layer can be driven with known
## positions on a machine with no room, no lobby and no WebRTC addon. It answers
## the one method both HUDs reach for; `null` is what the real manager answers
## offline, which is how the solo half of the check is driven.
class StubMp extends Node:
	var markers: Variant = null

	func peer_markers() -> Variant:
		return markers


## A stand-in crocodile: a positioned node in the "crocodile" group, which is all
## `minimap_hud._gather_crocodiles()` reads. `set_lod_active` and `is_chasing` are
## the two things the LOD manager touches on a group member, so both are here —
## without them the manager's own scan errors on this node.
class StubCroc extends Node3D:
	var is_chasing: bool = false

	func set_lod_active(_active: bool) -> void:
		pass

func _initialize() -> void:
	# _initialize() cannot await, so the scene-booting half runs as its own
	# coroutine; the tree keeps processing until it calls quit().
	_run()


func _run() -> void:
	root.add_child(load("res://scenes/main.tscn").instantiate())
	# ONE FRAME BEFORE TOUCHING ANYTHING. `_initialize()` runs before the main loop
	# starts, so nothing added here has had `_ready()` called yet — every node's
	# script state is still default. Dismissing the start overlay in this window
	# looks like it worked and is then undone the moment its real `_ready()` runs
	# and takes the pause for the first time.
	await process_frame
	var failure := _start_the_game()
	if failure.is_empty():
		# Two seconds: long enough for the spawn ring of chunks to build (which is
		# what fills the road station cache) and for several 5 Hz minimap ticks.
		await create_timer(2.0).timeout
		failure = _check()
	if failure.is_empty():
		failure = _check_zoom()
	if failure.is_empty():
		failure = _check_teammates()
	if failure.is_empty():
		print("SELFCHECK OK")
		quit(0)
	else:
		printerr("SELFCHECK FAILED: " + failure)
		quit(1)


func _start_the_game() -> String:
	"""Press PLAY SOLO, because main.tscn no longer starts on its own.

	`start_overlay.gd` takes `tree.paused = true` in its `_ready()` — before this
	function gets control — and RE-ASSERTS it every `_process`, so simply clearing
	`paused` here would be undone on the next frame. The minimap is PAUSABLE (as it
	should be: a map has no business ticking behind a menu), so under that pause its
	`_process` is never dispatched, `_tick()` never runs and `_have_data` stays
	false — which is exactly the "minimap never read the player" failure this
	harness reported for a HUD that works fine in game. `SceneTree.create_timer()`
	defaults to `process_always = true`, so the 2 s wait below elapses under the
	pause and the check ran against a world that had never taken a frame.

	Any future harness that boots main.tscn and needs the game actually RUNNING has
	to do this too. `mp_selfcheck.gd` does not boot a scene, and `mp_e2e.gd`'s
	MpManager is PROCESS_MODE_ALWAYS, which is why neither noticed."""
	var overlay: Node = root.get_node_or_null("Main/HUD/StartOverlay")
	if overlay == null:
		return "no StartOverlay under Main/HUD — was it dropped from main.tscn?"
	# A missing _dismiss means the script failed to PARSE, and there is exactly one
	# way that happens here: run against a never-opened clone, whose empty global
	# class cache leaves `class_name` types (MobileSensors, ToonShading, …)
	# unresolved. Scripts then silently fail to attach — including this overlay's,
	# which is why a cold clone used to print SELFCHECK OK for the worst possible
	# reason: nothing paused because nothing loaded. Fail loudly instead.
	if not overlay.has_method("_dismiss"):
		return "StartOverlay has no script — run `godot --headless --path . --import` " \
			+ "first to build the global class cache, or every class_name type fails " \
			+ "to resolve and this check passes vacuously"
	overlay._dismiss()
	if paused:
		return "the tree is still paused after dismissing StartOverlay — something " \
			+ "else took a pause, and the minimap (PAUSABLE) will never tick"
	return ""


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


func _check_zoom() -> String:
	"""Every map layer must derive its reach from the ONE shared scale factor.

	The failure this is written against is silent and delayed: a layer that keeps
	its own hardcoded metre count draws perfectly at the default zoom and only
	disagrees with the picture once somebody presses +. So nothing here reads a
	getter back — each assertion MEASURES AN EFFECT (does this crocodile get a
	dot? did the road window widen?) and states the value a hardcoded site would
	still be sitting on."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	var player: Node3D = get_first_node_in_group("player")
	if map == null or player == null:
		return "no MinimapHUD or no player for the zoom checks"

	# 0. The shipped default must not have moved.
	if map._zoom_index != map.ZOOM_DEFAULT_INDEX:
		return "the map did not start at ZOOM_DEFAULT_INDEX (%d, got %d)" \
			% [map.ZOOM_DEFAULT_INDEX, map._zoom_index]
	if absf(map._view_radius() - LEGACY_VIEW_RADIUS) > 0.001:
		return "the default zoom is %.1f m, not the %.1f m the map shipped with" \
			% [map._view_radius(), LEGACY_VIEW_RADIUS]
	if absf(map._croc_view_radius() - LEGACY_CROC_VIEW_RADIUS) > 0.001:
		return "the default croc radius is %.1f m, not the %.1f m the map shipped with" \
			% [map._croc_view_radius(), LEGACY_CROC_VIEW_RADIUS]

	# 1. CROC RADIUS follows the zoom. The probe crocodile is placed deliberately
	#    BETWEEN the default radius (30 m) and the one-step-out radius (45 m), so
	#    it must be invisible at the default zoom and dotted after one press. A
	#    site still using a hardcoded 30 m passes the first half and fails the
	#    second. The measurement is a WITH/WITHOUT pair at each zoom rather than a
	#    count across zooms, because zooming out legitimately brings the world's
	#    own crocodiles into range too.
	var probe := StubCroc.new()
	root.add_child(probe)
	probe.global_position = player.global_position + Vector3(40.0, 0.0, 0.0)
	var failure := ""
	while true:  # one pass; `break` is the single exit that still frees the probe
		probe.remove_from_group("crocodile")
		map._tick()
		var without_default: int = map._croc_count
		probe.add_to_group("crocodile")
		map._tick()
		var with_default: int = map._croc_count
		if with_default != without_default:
			failure = "a crocodile 40 m away is dotted at the default zoom, whose " \
				+ "croc radius is only %.1f m" % map._croc_view_radius()
			break

		map._zoom_by(1)
		var zoomed_croc_radius: float = map._croc_view_radius()
		probe.remove_from_group("crocodile")
		map._tick()
		var without_zoomed: int = map._croc_count
		probe.add_to_group("crocodile")
		map._tick()
		var with_zoomed: int = map._croc_count
		if with_zoomed != without_zoomed + 1:
			failure = ("a crocodile 40 m away is still not dotted one zoom step out, " \
				+ "where the croc radius should be %.1f m — the crocodile layer is " \
				+ "not deriving its radius from the shared scale (a hardcoded %.1f m " \
				+ "behaves exactly like this)") % [zoomed_croc_radius, LEGACY_CROC_VIEW_RADIUS]
			break
		break
	probe.remove_from_group("crocodile")
	probe.queue_free()
	if not failure.is_empty():
		map._zoom_index = map.ZOOM_DEFAULT_INDEX
		return failure

	# 2. ROAD WINDOW follows the zoom. We are one step out from the check above;
	#    step back in and compare the point counts. A window hardcoded at
	#    LEGACY_VIEW_RADIUS gives the SAME count at both zooms, which is the
	#    negative control.
	var zoomed_road: int = map._road_count
	map._zoom_by(-1)
	map._tick()
	var default_road: int = map._road_count
	if zoomed_road <= default_road:
		return ("the road window did not widen when zooming out (%d points at %.0f m, " \
			+ "%d at %.0f m) — it is not using the shared view radius") \
			% [default_road, LEGACY_VIEW_RADIUS, zoomed_road, map.ZOOM_RADII[map.ZOOM_DEFAULT_INDEX + 1]]

	# 3. The steps are clamped at both ends rather than wrapping or running off.
	map._zoom_by(-100)
	if map._zoom_index != 0:
		return "zooming in past the first step landed on index %d" % map._zoom_index
	map._zoom_by(100)
	if map._zoom_index != map.ZOOM_RADII.size() - 1:
		return "zooming out past the last step landed on index %d" % map._zoom_index

	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	map._tick()
	print("zoom: %s m | croc radius follows | road window %d -> %d points" \
		% [map.ZOOM_RADII, default_road, zoomed_road])
	return ""


func _check_teammates() -> String:
	"""The multiplayer teammate layer: absent solo, present and correctly placed in
	a room, edge-clamped rather than clipped, and following the same zoom scale.

	Driven from a `StubMp` rather than a real room, because the assertions are
	about where a known position lands on the widget — a live room would give
	neither known positions nor a headless WebRTC mesh to carry them."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	var locator: Control = root.get_node_or_null("Main/HUD/TeammateLocator")
	var player: Node3D = get_first_node_in_group("player")
	if map == null:
		return "no MinimapHUD under Main/HUD"
	if locator == null:
		return "no TeammateLocator under Main/HUD — was it dropped from main.tscn?"
	if player == null:
		return "no node in the \"player\" group"

	# 0. Peer colours are a pure function of the id: stable across calls (or a
	#    teammate changes colour every tick) and distinct between peers (or two
	#    teammates are indistinguishable, which is the whole point of colouring).
	var color_a := MpManager.peer_color("aabbccddeeff0011")
	if color_a != MpManager.peer_color("aabbccddeeff0011"):
		return "MpManager.peer_color() is not stable for one peer id"
	if color_a == MpManager.peer_color("1100ffeeddccbbaa"):
		return "MpManager.peer_color() gave two different peers the same colour"

	# 1. SOLO — the negative control for the whole feature. The real manager is
	#    offline, so `peer_markers()` answers null and NOTHING is drawn or shown.
	map._tick()
	if map._peer_count != 0:
		return "the minimap drew %d teammate dots while solo" % map._peer_count
	locator._refresh_markers()
	if locator.visible:
		return "the teammate locator is visible while solo"

	# 2. Swap the offline manager out of the group for a stub with known positions.
	#    Removing it from the group (rather than freeing it) is the smallest change
	#    that redirects both HUDs; their cached references are cleared by hand
	#    because the node is still perfectly valid, just no longer the answer.
	var real_mp: Node = get_first_node_in_group("mp")
	if real_mp != null:
		real_mp.remove_from_group("mp")
	var stub := StubMp.new()
	stub.add_to_group("mp")
	root.add_child(stub)
	map._mp = null
	locator._mp = null

	var origin := player.global_position
	# Ahead (+X), to the player's right (+Z), and far away down the road.
	var far_offset := Vector3(200.0, 0.0, 0.0)
	stub.markers = [
		{"id": "peer-ahead", "pos": origin + Vector3(10.0, 0.0, 0.0), "color": Color(1, 0, 0, 1)},
		{"id": "peer-right", "pos": origin + Vector3(0.0, 0.0, 10.0), "color": Color(0, 1, 0, 1)},
		{"id": "peer-far", "pos": origin + far_offset, "color": Color(0, 0, 1, 1)},
	]

	var failure := _check_teammate_layers(map, locator, player, origin)

	# Put the world back the way it was found.
	stub.remove_from_group("mp")
	stub.queue_free()
	if real_mp != null:
		real_mp.add_to_group("mp")
	map._mp = null
	locator._mp = null
	return failure


func _check_teammate_layers(map: Control, locator: Control, player: Node3D, origin: Vector3) -> String:
	# --- MINIMAP DOTS -------------------------------------------------------
	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	map._tick()
	if map._peer_count != 3:
		return "the minimap drew %d teammate dots for a 3-peer room" % map._peer_count

	# The dot's own colour must be the one the manager handed over — the two
	# surfaces agreeing on a peer's colour is the feature.
	var green := Color(0, 1, 0, 1)
	var found_green := false
	for i in range(map._peer_count):
		var c: Color = map._peer_colors[i]
		if absf(c.r - green.r) < 0.01 and absf(c.g - green.g) < 0.01 and absf(c.b - green.b) < 0.01:
			found_green = true
	if not found_green:
		return "no teammate dot carries the colour the manager supplied"

	# North-up, exactly as the player arrow: +X is screen RIGHT and +Z is screen
	# DOWN. A mirrored map passes every other check here, which is why the two
	# signs are asserted separately.
	var ahead := _dot_center(map, 0)
	var right := _dot_center(map, 1)
	if ahead.x <= map.MAP_CENTER.x + 1.0 or absf(ahead.y - map.MAP_CENTER.y) > 1.0:
		return "the teammate 10 m along +X did not land to the RIGHT of centre (%s)" % ahead
	if right.y <= map.MAP_CENTER.y + 1.0 or absf(right.x - map.MAP_CENTER.x) > 1.0:
		return "the teammate 10 m along +Z did not land BELOW centre (%s)" % right

	# The far teammate is 200 m away, well past the 60 m disc: it must be CLAMPED
	# to the rim, not drawn 200 px off the widget. An unclamped implementation puts
	# this dot ~207 px from the centre, i.e. three disc-widths away — which is the
	# negative control the bound below is written against.
	var far := _dot_center(map, 2)
	var far_dist: float = (far - map.MAP_CENTER as Vector2).length()
	if far_dist > map.MAP_RADIUS + 1.0:
		return "an off-map teammate was drawn %.1f px from the centre, outside the %.1f px disc" \
			% [far_dist, map.MAP_RADIUS]
	if far_dist < map.MAP_RADIUS - map.PEER_EDGE_TICK - 1.0:
		return "an off-map teammate was not clamped to the rim (%.1f px from centre)" % far_dist

	# OFF-MAP MUST BE JUDGED AGAINST THE DISC EDGE, not against the inset the tick
	# is drawn from. 58 m is inside the 60 m view but in the outer band, and an
	# implementation that tests against `MAP_RADIUS - PEER_EDGE_TICK` declares the
	# whole of that band off-map — a teammate you can see gets drawn as a "keep
	# going" tick. That is a real bug this check caught; keep it.
	var stub: Node = get_first_node_in_group("mp")
	stub.markers = [{"id": "peer-outer", "pos": origin + Vector3(58.0, 0.0, 0.0), "color": Color(1, 1, 1, 1)}]
	map._tick()
	if _dot_is_clamped(map, 0):
		return ("a teammate 58 m away was drawn as an off-map tick on the %.0f m map " \
			+ "— off-map is being judged against an inset, not the disc edge") % LEGACY_VIEW_RADIUS

	# The teammate layer follows the ZOOM like every other layer. 70 m is off a
	# 60 m map and on a 130 m one, so the same peer must clamp at one zoom and not
	# at the other — a layer with its own hardcoded reach clamps at both.
	stub.markers = [{"id": "peer-mid", "pos": origin + Vector3(70.0, 0.0, 0.0), "color": Color(1, 1, 1, 1)}]
	map._tick()
	var clamped_near_zoom := _dot_is_clamped(map, 0)
	map._zoom_index = map.ZOOM_RADII.size() - 1
	map._tick()
	var clamped_far_zoom := _dot_is_clamped(map, 0)
	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	if not clamped_near_zoom:
		return "a teammate 70 m away was not clamped on the %.0f m map" % LEGACY_VIEW_RADIUS
	if clamped_far_zoom:
		return ("a teammate 70 m away is still rim-clamped on the %.0f m map — the " \
			+ "teammate layer is not using the shared scale") % map.ZOOM_RADII[map.ZOOM_RADII.size() - 1]

	# --- LOCATOR BAR --------------------------------------------------------
	stub.markers = [
		{"id": "peer-ahead", "pos": origin + Vector3(10.0, 0.0, 0.0), "color": Color(1, 0, 0, 1)},
		{"id": "peer-right", "pos": origin + Vector3(0.0, 0.0, 10.0), "color": Color(0, 1, 0, 1)},
		{"id": "peer-behind", "pos": origin + Vector3(-10.0, 0.0, 0.0), "color": Color(0, 0, 1, 1)},
	]
	locator._refresh_markers()
	if not locator.visible:
		return "the teammate locator stayed hidden with three teammates in the room"
	locator._player = player
	# Facing +X (yaw 0), so "ahead" is +X and the player's right hand is +Z.
	locator._build_segments(0.0)
	if locator._count != 4:
		return "the locator built %d segments for 3 teammates plus the centre notch" % locator._count
	var center_x: float = locator.size.x * 0.5
	if absf(locator._points[0].x - center_x) > 0.5:
		return "the locator's centre notch is not at the centre of the bar"
	var bar_ahead: float = locator._points[2].x
	var bar_right: float = locator._points[4].x
	var bar_behind: float = locator._points[6].x
	if absf(bar_ahead - center_x) > 1.0:
		return "a teammate straight ahead did not land at the centre of the locator (%.1f vs %.1f)" \
			% [bar_ahead, center_x]
	# The mirror negative control: with the bearing sign flipped this lands LEFT.
	if bar_right <= center_x + 1.0:
		return "a teammate to the player's RIGHT landed left of centre on the locator (%.1f)" % bar_right
	if absf(absf(bar_behind - center_x) - center_x) > 2.0:
		return "a teammate directly behind did not land at an end of the locator (%.1f)" % bar_behind

	print("teammates: 3 dots, rim clamp at %.0f px, locator ahead/right/behind = %.0f/%.0f/%.0f of %.0f" \
		% [map.MAP_RADIUS, bar_ahead, bar_right, bar_behind, locator.size.x])
	return ""


func _dot_is_clamped(map: Control, index: int) -> bool:
	"""Whether a teammate dot was drawn as an off-map rim tick.

	Read off the ALPHA rather than the geometry, because that is unambiguous: an
	off-map tick is the only thing that scales the peer's colour by
	PEER_EDGE_ALPHA, while a tick and an on-map blob are within 0.2 px of the same
	length and can sit at the same distance from the centre. It also happens to
	check the visual distinction the design promises."""
	var alpha: float = (map._peer_colors[index] as Color).a
	return alpha < 0.99


func _dot_center(map: Control, index: int) -> Vector2:
	"""The midpoint of a teammate dot's segment pair — the dot's actual position,
	whether it was drawn as an on-map blob or a rim tick."""
	return (map._peer_points[index * 2] + map._peer_points[index * 2 + 1]) * 0.5
