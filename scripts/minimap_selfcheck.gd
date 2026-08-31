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
##   6. LANDMARKS: that a marker in the "landmark" group gets an X where it should,
##      that the rim clamp follows the shared zoom scale, and — the negative
##      control — that nothing at all is drawn when the group is empty. The whole
##      interface to the landmark feature is that group name, so this is also the
##      alarm for it being renamed out from under the map (which, like the road
##      cache above, would fail SILENTLY: the map keeps drawing, just with no
##      landmarks on it).
##   7. TERRAIN: that the biome field painted across the disc is (a) drawn in the
##      GROUND SHADER'S colours — parsed straight out of ground.gdshader, because a
##      map that invents its own greens tells the player the desert is somewhere it
##      isn't; (b) actually sampled from the world, run-length merged, spanning the
##      disc in both axes and following the shared zoom scale; and (c) sampled on
##      the TICK and never in `_draw()`, which is the whole performance shape of
##      this widget.
##   8. WIDGET RECT: MAP_RADIUS and MAP_CENTER live in minimap_hud.gd but the
##      control's SIZE lives in main.tscn, so the two drift apart silently — a disc
##      that outgrows its rect puts the caption off the disc's axis and walks the
##      widget into its HUD neighbours.
##   9. INDOORS (bd godot-test1-kox): that the storey line and the jail's floor
##      appear while sheltered and NOWHERE ELSE, that the labyrinth degrades the
##      line rather than blanking it, that NO CONTINUOUS BEARING is ever drawn
##      before the anti-stall timer, and that the timer's PROGRESS signal is a
##      first-time room or a storey gained — re-entering a room you have already
##      been in must NOT reset it, which is the whole difference between an
##      anti-stall rescue and a compass. Driven through a `StubTower`, because the
##      real shell is 400 m from spawn and is not built at all out there.
##
## It boots the real main scene, because the road station cache only exists once a
## chunk has generated — there is nothing pure to test in isolation here.


## The values the map shipped with, before zoom existed. They are here as NEGATIVE
## CONTROLS: after a zoom step, a layer still sitting on one of these numbers is a
## layer that hardcoded it instead of deriving from `_view_radius()`.
const LEGACY_VIEW_RADIUS: float = 60.0
const LEGACY_CROC_VIEW_RADIUS: float = 30.0

## The ground shader, read as TEXT. Its `uniform vec3 <name>: source_color =
## vec3(...)` defaults are the one true biome palette — endless_terrain pushes the
## numeric biome params into the material but never the colours, which are declared
## shader-side only, so this file is where the map's copy of them gets compared to
## the original. Parsing the source is deliberate: reading the live material back
## would answer with whatever an art pass happened to override, rather than with
## what the two files agree on.
const GROUND_SHADER_PATH: String = "res://assets/shaders/ground.gdshader"

## Which shader uniform each row of `minimap_hud.BIOME_TINTS` must equal, indexed by
## endless_terrain's Biome enum. PLAINS has no uniform of its own — the shader
## mottles between `green_a` and `green_b` per vertex — so it is checked against
## their MIDPOINT, which is what that mottle averages to.
const BIOME_UNIFORMS: Array[String] = ["", "desert_color", "forest_color",
	"mountain_color", "city_color", "snow_color"]


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
## A stand-in world for the terrain layer, so the samples it takes are KNOWN and
## COUNTABLE: it answers `biome_at()` from a plain X split and records every call.
## `minimap_hud._tick()` re-fetches its terrain only when the cached one is null or
## freed, so assigning this over `map._terrain` redirects the layer for as long as
## the check wants it and the real world goes straight back afterwards.
class StubTerrain extends Node:
	var calls: int = 0
	var min_x: float = INF
	var max_x: float = -INF
	## World X the answer flips at, and the two biomes either side. INF puts the
	## whole disc in `low`, which is the single-biome case.
	var split_x: float = INF
	var low: int = 1    # Biome.DESERT
	var high: int = 5   # Biome.SNOW

	func reset() -> void:
		calls = 0
		min_x = INF
		max_x = -INF

	func biome_at(world_x: float, _world_z: float) -> int:
		calls += 1
		min_x = minf(min_x, world_x)
		max_x = maxf(max_x, world_x)
		return low if world_x < split_x else high

	func is_river_at(_world_pos: Vector3) -> bool:
		return false


class StubCroc extends Node3D:
	var is_chasing: bool = false

	func set_lod_active(_active: bool) -> void:
		pass


## A stand-in for `TowerShell`, in the "tower" group — the one node the indoor half
## of the map reaches for, and the one that is NOT built at spawn: the HQ stands 400
## m away and `endless_terrain` instances it only within `DRAW_RADIUS`. It answers
## `sheltered()` from a flag, and being an unrotated `Node3D` its `to_local()` is the
## interior frame the check positions the player in.
class StubTower extends Node3D:
	var inside: bool = true

	func sheltered(_pos: Vector3) -> bool:
		return inside

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
		failure = _check_landmarks()
	if failure.is_empty():
		failure = await _check_terrain()
	if failure.is_empty():
		failure = _check_widget_rect()
	if failure.is_empty():
		failure = _check_indoors()
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


func _check_landmarks() -> String:
	"""The geo-landmark layer: an X where the landmark is, a rim clamp that follows
	the shared zoom scale, and NOTHING drawn when the group is empty.

	Driven from a bare probe Node3D in the "landmark" group, because that group IS
	the entire interface between the terrain's landmark spawner and this HUD — the
	map reads a position off a group member and nothing else. A real landmark is
	~1 chunk in 46 and lands 22 m off the road, so waiting for one to generate near
	spawn is not a test, it is a coin flip.

	Every assertion is a WITH/WITHOUT pair around the probe rather than an absolute
	count, for the reason the crocodile zoom check gives: the world is allowed to
	have landmarks of its own loaded, and an absolute count would then be measuring
	the seed rather than the layer."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	var player: Node3D = get_first_node_in_group("player")
	if map == null or player == null:
		return "no MinimapHUD or no player for the landmark checks"

	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	map._tick()
	var baseline: int = map._landmark_count
	if baseline >= map.MAX_LANDMARK_DOTS:
		return "landmark marker cap (%d) is already biting with no probe placed" \
			% map.MAX_LANDMARK_DOTS

	var probe := Node3D.new()
	root.add_child(probe)
	var origin := player.global_position
	var failure := ""
	while true:  # one pass; every `break` still frees the probe below
		# 1. NEAR — 10 m along +X, comfortably inside the 60 m disc. It must add
		#    exactly one marker, land to the RIGHT of centre (north-up, the same
		#    sign convention the player arrow and the teammate dots are checked
		#    against) and be drawn at full strength, i.e. NOT rim-clamped.
		probe.global_position = origin + Vector3(10.0, 0.0, 0.0)
		probe.add_to_group("landmark")
		map._tick()
		if map._landmark_count != baseline + 1:
			failure = ("a landmark 10 m away drew %d markers, not the %d expected — " \
				+ "the map is not reading the \"landmark\" group") \
				% [map._landmark_count, baseline + 1]
			break
		var near := _landmark_center(map, baseline)
		if near.x <= map.MAP_CENTER.x + 1.0 or absf(near.y - map.MAP_CENTER.y) > 1.0:
			failure = "the landmark 10 m along +X did not land to the RIGHT of centre (%s)" % near
			break
		if _landmark_reach(map, baseline) > map.MAP_RADIUS:
			failure = "a landmark inside the view was drawn outside the disc (%s)" % near
			break
		if _landmark_is_clamped(map, baseline):
			failure = "a landmark 10 m away was dimmed as if it were off the map"
			break

		# 2. THE ZOOM, measured as an EFFECT with the pair that only the shared
		#    scale can satisfy: 70 m is off a 60 m map and on a 130 m one, so the
		#    same probe must clamp at one zoom and not at the other. A layer with
		#    its own hardcoded reach clamps at both — that is the negative control
		#    the crocodile and teammate zoom checks are built on too.
		probe.global_position = origin + Vector3(70.0, 0.0, 0.0)
		map._tick()
		var clamped_near_zoom := _landmark_is_clamped(map, baseline)
		var clamped_dist: float = (_landmark_center(map, baseline) - map.MAP_CENTER as Vector2).length()
		# Measured on the FURTHEST PAINTED CORNER, not the centre. An X's corners sit
		# at arm * sqrt(2) from its centre, so a rim inset that subtracts the arm
		# length instead of the real reach clamps the centre perfectly and still
		# hangs the corners over the ring — invisible to a centre-only assertion.
		var clamped_reach: float = _landmark_reach(map, baseline)
		map._zoom_index = map.ZOOM_RADII.size() - 1
		map._tick()
		var clamped_far_zoom := _landmark_is_clamped(map, baseline)
		map._zoom_index = map.ZOOM_DEFAULT_INDEX
		if not clamped_near_zoom:
			failure = "a landmark 70 m away was not rim-clamped on the %.0f m map" % LEGACY_VIEW_RADIUS
			break
		if clamped_reach > map.MAP_RADIUS:
			failure = ("an off-map landmark's X reaches %.1f px from the centre, past the " \
				+ "%.1f px disc — the rim inset is not the mark's real reach") \
				% [clamped_reach, map.MAP_RADIUS]
			break
		if clamped_dist < map.MAP_RADIUS - map.LANDMARK_MARK_REACH - 1.0:
			failure = "an off-map landmark was not clamped to the rim (%.1f px from centre)" % clamped_dist
			break
		if clamped_far_zoom:
			failure = ("a landmark 70 m away is still rim-clamped on the %.0f m map — the " \
				+ "landmark layer is not using the shared scale") \
				% map.ZOOM_RADII[map.ZOOM_RADII.size() - 1]
			break
		break

	# 3. THE NEGATIVE CONTROL, in two halves. First: with the probe out of the group
	#    the layer must fall back to exactly what it drew before it. Then the one
	#    that matters — the group is emptied OUTRIGHT (the world's own markers are
	#    pulled out of it too, and put straight back) and the layer must draw
	#    NOTHING. Comparing against `baseline` alone is not enough on a seed that
	#    loaded a real landmark: a layer that drew its group members correctly AND
	#    one extra marker unconditionally keeps the same delta and passes.
	probe.remove_from_group("landmark")
	map._tick()
	if failure.is_empty() and map._landmark_count != baseline:
		failure = "removing the probe left %d markers, not the %d there were before it" \
			% [map._landmark_count, baseline]
	probe.queue_free()
	var real_markers := get_nodes_in_group("landmark")
	for marker in real_markers:
		marker.remove_from_group("landmark")
	map._tick()
	var empty_count: int = map._landmark_count
	for marker in real_markers:
		marker.add_to_group("landmark")
	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	map._tick()
	if not failure.is_empty():
		return failure
	if empty_count != 0:
		return "the map drew %d landmark markers with an EMPTY \"landmark\" group" % empty_count

	print("landmarks: %d loaded + probe -> X at disc, rim clamp follows zoom, none when unregistered" \
		% baseline)
	return ""


func _check_terrain() -> String:
	"""The terrain colour layer: the ground shader's palette, sampled from the world
	on the TICK, run-length merged, spanning the disc at every zoom.

	The colour half is a FILE COMPARISON, because the failure it guards is not a
	crash — a map painted in its own invented greens looks perfectly fine and lies
	about where the desert is. It is the same parity discipline `_biome_noise`
	carries against `biome_noise`, one layer up.

	The sampling half is driven from a `StubTerrain`, for the reason `StubMp` exists:
	assertions about how many samples were taken, where, and when need a world that
	answers known values and counts the questions."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	var player: Node3D = get_first_node_in_group("player")
	if map == null or player == null:
		return "no MinimapHUD or no player for the terrain checks"

	# 0. THE PALETTE IS THE GROUND SHADER'S, not the map's own.
	var palette_failure := _check_palette_matches_shader(map)
	if not palette_failure.is_empty():
		return palette_failure

	# 1. Against the REAL world: the layer painted something, and the cell under the
	#    player arrow agrees with the biome the caption names. TERRAIN_GRID is odd on
	#    purpose so the centre cell is sampled at the player's own position, which
	#    makes this an exact cross-check of two independent reads rather than an
	#    approximate one — and it is the alarm for the grid's world mapping being
	#    offset by half a cell, which nothing else here would notice.
	map._tick()
	if map._terrain_count <= 0:
		return "the terrain layer painted nothing — it never sampled the world"
	var under := _terrain_biome_at_pixel(map, map.MAP_CENTER)
	if under != map._biome:
		return ("the terrain cell under the player arrow is biome %d but the caption " \
			+ "says %d — the grid's world mapping is off") % [under, map._biome]

	# 2. Everything below drives a STUB world. The real terrain goes back at the end.
	var real_terrain: Node = map._terrain
	var stub := StubTerrain.new()
	map._terrain = stub
	var failure := ""
	var rows := 0
	while true:  # one pass; every exit is a `break`, so the stub is always restored
		# 2a. ONE BIOME EVERYWHERE. Each row of the grid must collapse to at most ONE
		#     bar. The negative control is the obvious implementation: a rect per
		#     cell would paint ~177 of them and cost ~177 draw calls instead of 1.
		stub.reset()
		stub.split_x = INF
		map._tick()
		rows = map._terrain_count
		if rows <= 0 or rows > map.TERRAIN_GRID:
			failure = ("a single-biome world painted %d bars for a %d-row grid — the " \
				+ "run-length merge is not merging (one bar per CELL would be ~%d)") \
				% [rows, map.TERRAIN_GRID, map.TERRAIN_GRID * map.TERRAIN_GRID * 3 / 4]
			break
		if stub.calls <= rows or stub.calls > map.TERRAIN_GRID * map.TERRAIN_GRID:
			failure = ("the terrain layer took %d biome_at() samples for a %dx%d grid " \
				+ "— it is not sampling a grid across the disc") \
				% [stub.calls, map.TERRAIN_GRID, map.TERRAIN_GRID]
			break

		# 2b. TWO BIOMES, split at the player's own X. Every row must now split into
		#     exactly two bars, DESERT to the left and SNOW to the right. That is the
		#     terrain layer's own north-up assertion (+X is screen RIGHT, the check
		#     the road and arrow layers each get separately) and its proof that the
		#     grid spans the disc in X rather than sampling one column and flooding.
		stub.reset()
		stub.split_x = player.global_position.x
		map._tick()
		if map._terrain_count != rows * 2:
			failure = ("a world split down the middle painted %d bars, not the %d a " \
				+ "two-run row each would give — the grid does not span the disc in X") \
				% [map._terrain_count, rows * 2]
			break
		var left := _terrain_biome_at_pixel(map, map.MAP_CENTER - Vector2(map.MAP_RADIUS * 0.5, 0.0))
		var right := _terrain_biome_at_pixel(map, map.MAP_CENTER + Vector2(map.MAP_RADIUS * 0.5, 0.0))
		if left != stub.low or right != stub.high:
			failure = ("half a disc west of the player painted biome %d and half a disc " \
				+ "east painted %d, expected %d / %d — the map is mirrored in X") \
				% [left, right, stub.low, stub.high]
			break

		# 2c. THE GRID SPANS THE DISC AT EVERY ZOOM, measured as the world width the
		#     samples actually covered. Sample CENTRES are inset half a cell at each
		#     end, so the widest row spans (GRID-1)/GRID of the disc's diameter — in
		#     metres, that over the shared scale. The negative control is a layer
		#     with its own hardcoded reach: it reports the SAME span at both zooms.
		var expected_default := _expected_sample_span(map)
		stub.reset()
		map._tick()
		var span_default := stub.max_x - stub.min_x
		if absf(span_default - expected_default) > 1.0:
			failure = "the terrain grid sampled %.1f m across at the default zoom, expected %.1f m" \
				% [span_default, expected_default]
			break
		map._zoom_by(1)
		var expected_zoomed := _expected_sample_span(map)
		stub.reset()
		map._tick()
		var span_zoomed := stub.max_x - stub.min_x
		map._zoom_by(-1)
		if absf(span_zoomed - expected_zoomed) > 1.0:
			failure = ("the terrain grid sampled %.1f m across one zoom step out, expected " \
				+ "%.1f m (a layer with its own hardcoded reach reports %.1f m at both)") \
				% [span_zoomed, expected_zoomed, expected_default]
			break

		# 2d. THE TICK SAMPLES, `_draw()` NEVER DOES. This is the widget's whole
		#     performance shape: a `biome_at()` grid inside `_draw()` would run at
		#     frame rate instead of 5 Hz. The tick is pushed out of reach first so
		#     `_process` cannot take one during the wait, then a redraw is forced and
		#     the sample counter must not move. (Under the headless dummy renderer
		#     `_draw()` may not be dispatched at all, which makes this half of the
		#     assertion weak rather than wrong — the count check in 2a is what proves
		#     the samples happen on the tick.)
		stub.reset()
		map._tick()
		var after_tick: int = stub.calls
		map._time_until_tick = 10.0
		map.queue_redraw()
		await process_frame
		await process_frame
		if stub.calls != after_tick:
			failure = ("_draw() took %d biome_at() samples — the terrain layer must read " \
				+ "the tick's snapshot, never the world") % [stub.calls - after_tick]
			break
		break

	# Put the real world back whatever happened, and re-tick so the map is live again.
	map._terrain = real_terrain
	stub.free()
	map._zoom_index = map.ZOOM_DEFAULT_INDEX
	map._time_until_tick = 0.0
	map._tick()
	if not failure.is_empty():
		return failure

	print("terrain: palette matches ground.gdshader | %d bars/%d rows, run-length merged | " \
		% [rows, map.TERRAIN_GRID] + "grid span follows zoom | no sampling in _draw()")
	return ""


func _check_palette_matches_shader(map: Control) -> String:
	"""Every row of `minimap_hud.BIOME_TINTS` against the ground shader's own uniform
	default. Parsed out of the shader SOURCE — see GROUND_SHADER_PATH."""
	var text := FileAccess.get_file_as_string(GROUND_SHADER_PATH)
	if text.is_empty():
		return "could not read %s — the map's palette cannot be checked against the ground" \
			% GROUND_SHADER_PATH
	var green_a: Variant = _shader_color(text, "green_a")
	var green_b: Variant = _shader_color(text, "green_b")
	if green_a == null or green_b == null:
		return "ground.gdshader has no green_a/green_b uniform — the PLAINS tint cannot be derived"
	for biome in range(map.BIOME_TINTS.size()):
		# PLAINS (the empty uniform name) is the midpoint of the two greens the
		# shader mottles between; every other band has a uniform of its own.
		var want: Variant = (green_a as Color).lerp(green_b as Color, 0.5) \
			if BIOME_UNIFORMS[biome].is_empty() else _shader_color(text, BIOME_UNIFORMS[biome])
		if want == null:
			return "ground.gdshader has no `%s` uniform — the map mirrors a colour that is gone" \
				% BIOME_UNIFORMS[biome]
		var got: Color = map.BIOME_TINTS[biome]
		var expect: Color = want
		if absf(got.r - expect.r) > 0.005 or absf(got.g - expect.g) > 0.005 \
				or absf(got.b - expect.b) > 0.005:
			return ("minimap BIOME_TINTS[%d] is (%.3f, %.3f, %.3f) but ground.gdshader paints " \
				+ "that biome (%.3f, %.3f, %.3f) — the map and the ground disagree about a colour") \
				% [biome, got.r, got.g, got.b, expect.r, expect.g, expect.b]
		if absf(got.a - map.TERRAIN_ALPHA) > 0.001:
			return "minimap BIOME_TINTS[%d] is drawn at alpha %.3f, not TERRAIN_ALPHA" % [biome, got.a]
	return ""


func _shader_color(text: String, uniform: String) -> Variant:
	"""One `uniform vec3 <name>: source_color = vec3(r, g, b);` default out of the
	shader source, or null when there is no such uniform."""
	var decl := text.find("uniform vec3 %s" % uniform)
	if decl < 0:
		return null
	var open_paren := text.find("vec3(", decl + 13)
	var close_paren := text.find(")", open_paren)
	if open_paren < 0 or close_paren < 0:
		return null
	var parts := text.substr(open_paren + 5, close_paren - open_paren - 5).split(",")
	if parts.size() != 3:
		return null
	return Color(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


func _expected_sample_span(map: Control) -> float:
	"""How wide in world metres the terrain grid's samples should reach at the
	current zoom. Sample CENTRES sit half a cell in from each edge, so they span
	(GRID-1)/GRID of the disc's diameter — which in metres is that over the ONE
	shared scale, i.e. purely a function of `_view_radius()`."""
	return float(map.TERRAIN_GRID - 1) / float(map.TERRAIN_GRID) * 2.0 * map._view_radius()


func _terrain_biome_at_pixel(map: Control, at: Vector2) -> int:
	"""Which biome the terrain layer actually PAINTED at a point on the widget: find
	the bar covering it and match its colour back to a palette row. Reading the
	painted output rather than re-sampling keeps every assertion above an EFFECT
	measurement, in this file's usual style. -1 = nothing painted there, -2 = painted
	a colour that is in no palette row."""
	var half: float = map.TERRAIN_CELL * 0.5
	for i in range(map._terrain_count):
		var a: Vector2 = map._terrain_points[i * 2]
		var b: Vector2 = map._terrain_points[i * 2 + 1]
		if absf(at.y - a.y) > half or at.x < a.x or at.x > b.x:
			continue
		var painted: Color = map._terrain_colors[i]
		for biome in range(map.BIOME_TINTS.size()):
			if (map.BIOME_TINTS[biome] as Color).is_equal_approx(painted):
				return biome
		return -2
	return -1


func _check_widget_rect() -> String:
	"""The widget's own rect, which lives in main.tscn while MAP_RADIUS/MAP_CENTER
	live in minimap_hud.gd — two files that can drift apart in silence.

	The caption is centred across `size.x` starting at x = 0, so a width that is not
	exactly twice MAP_CENTER.x slides the coordinates off the disc's axis; a disc
	taller than the rect walks the widget into whatever the HUD puts beside it. The
	neighbour list is the LEFT-EDGE column — the only side this centre-left-anchored
	widget can grow into — and includes the debug overlays, which are laid out
	whether or not they happen to be visible."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	if map == null:
		return "no MinimapHUD under Main/HUD"
	if absf(map.size.x - map.MAP_CENTER.x * 2.0) > 0.5:
		return ("the MinimapHUD control is %.0f px wide but the disc is centred at x = %.0f " \
			+ "— the caption is centred across size.x and would sit off the disc's axis") \
			% [map.size.x, map.MAP_CENTER.x]
	if map.MAP_CENTER.x - map.MAP_RADIUS < 0.0 or map.MAP_CENTER.y - map.MAP_RADIUS < 0.0:
		return "the %.0f px disc pokes out of the top/left of its own control" % map.MAP_RADIUS
	# Two lines of caption below the disc: the first baseline sits TEXT_TOP_GAP under
	# the rim, the second roughly a font size below that, plus its descent.
	var caption_bottom: float = map.MAP_CENTER.y + map.MAP_RADIUS + map.TEXT_TOP_GAP \
		+ map.TEXT_SIZE * 2.0
	if map.size.y < caption_bottom:
		return "the MinimapHUD control is %.0f px tall but the disc + caption need %.0f px" \
			% [map.size.y, caption_bottom]
	var rect := map.get_global_rect()
	var viewport_width := map.get_viewport_rect().size.x
	for neighbour_name in ["LivesHUD", "HeroHUD", "PerfOverlay", "MotionDebug", "TouchControls"]:
		var other: Control = root.get_node_or_null("Main/HUD/%s" % neighbour_name) as Control
		# Skip the full-screen overlays: they legitimately cover everything.
		if other == null or other.size.x >= viewport_width - 1.0:
			continue
		if rect.intersects(other.get_global_rect()):
			return "the %.0f px minimap widget overlaps %s (%s vs %s)" \
				% [map.MAP_RADIUS, neighbour_name, rect, other.get_global_rect()]
	print("widget: %.0f px disc in a %.0f x %.0f rect, clear of its HUD neighbours" \
		% [map.MAP_RADIUS, map.size.x, map.size.y])
	return ""


func _check_indoors() -> String:
	"""Check 9 — the indoor caption and the anti-stall arrow (bd godot-test1-kox).

	EVERY ASSERTION IS AN EFFECT with the storey CHOSEN HERE and read back out of the
	caption, never a re-run of the map's own formula: the check parks the player on
	storey k and requires the line to say k, so an off-by-one or a floor read off the
	wrong frame fails rather than agreeing with itself.

	The negative controls are the point of the feature. Outside the building nothing
	is drawn at all; inside, no bearing is drawn until the stall timer has run; and
	re-entering a room already visited does NOT restart that timer, which is what
	stops the arrow from being a compass you can farm by walking through a doorway."""
	var map: Control = root.get_node_or_null("Main/HUD/MinimapHUD")
	var player: Node3D = get_first_node_in_group("player")
	if map == null or player == null:
		return "no MinimapHUD or no player for the indoor checks"

	# The storeys this check drives, picked off the plans rather than written down:
	# the first non-maze, non-block storey with two rooms to walk between, and the
	# first storey of the labyrinth.
	var office := -1
	var letters: Array = []
	var maze := -1
	var jail := TowerInterior.block_floor()
	for f: int in TowerPlans.floors():
		if TowerInterior.is_maze_floor(f):
			if maze < 0:
				maze = f
			continue
		if f == jail or office >= 0:
			continue
		var rooms: Dictionary = TowerPlans.storey(f)["rooms"]
		if rooms.size() >= 2:
			office = f
			letters = rooms.keys()
			letters.sort()
	if office < 0 or maze < 0 or jail < 0:
		return "the plans have no office storey (%d), no labyrinth (%d) or no cell block (%d)" \
			% [office, maze, jail]
	var zone_a := _room_cell_local(office, String(letters[0]))
	var zone_b := _room_cell_local(office, String(letters[1]))
	var zone_maze := _room_cell_local(maze, String(TowerPlans.storey(maze)["rooms"].keys()[0]))
	if zone_a == Vector3.INF or zone_b == Vector3.INF or zone_maze == Vector3.INF:
		return "could not find a room cell to stand in on storey %d / %d" % [office, maze]

	var tower := StubTower.new()
	tower.add_to_group("tower")
	root.add_child(tower)
	var failure := ""
	while true:  # one pass; every exit is a `break`, so the stub is always freed
		# 1. OUTSIDE — the negative control, and it is the whole gate on this feature.
		tower.inside = false
		_stand_in(tower, player, zone_a)
		map._tick()
		if not map._floor_text.is_empty() or not map._jail_text.is_empty() \
				or map._jail_alpha > 0.0:
			failure = "outside the HQ the map still shows \"%s\" / \"%s\" (arrow alpha %.2f)" \
				% [map._floor_text, map._jail_text, map._jail_alpha]
			break

		# 2. INSIDE, on a known storey. The caption must name THAT storey and the cell
		#    block's, as the lift numbers them (a FLOOR_Y index plus one).
		tower.inside = true
		map._tick()
		if not map._floor_text.contains(str(office + 1)):
			failure = "standing on storey %d the map says \"%s\"" % [office + 1, map._floor_text]
			break
		if not map._jail_text.contains("F%d" % (jail + 1)):
			failure = "the jail line \"%s\" never names the block's storey F%d" \
				% [map._jail_text, jail + 1]
			break
		if not map._jail_text.contains("^%d" % (jail - office)):
			failure = "the jail line \"%s\" is missing the ^%d floor delta" \
				% [map._jail_text, jail - office]
			break
		# 3. NO CONTINUOUS BEARING. This is the design note's central refusal: a live
		#    arrow ranks the corridors at every junction and solves the building.
		if map._jail_alpha > 0.0:
			failure = "an arrow is drawn on arrival (alpha %.2f) — that is a continuous bearing" \
				% map._jail_alpha
			break

		# 4. PROGRESS is a FIRST-TIME room or a storey gained, and nothing else.
		map._tick()
		if not is_equal_approx(map._stall, map.TICK_INTERVAL):
			failure = "a second tick in the same room left the stall timer at %.2f s, not %.2f" \
				% [map._stall, map.TICK_INTERVAL]
			break
		_stand_in(tower, player, zone_b)
		map._tick()
		if map._stall > 0.0:
			failure = "walking into a room for the first time did not reset the stall timer (%.2f s)" \
				% map._stall
			break
		_stand_in(tower, player, zone_a)
		map._tick()
		if not is_equal_approx(map._stall, map.TICK_INTERVAL):
			failure = ("walking back into an ALREADY VISITED room reset the stall timer " \
				+ "(%.2f s) — the arrow can then be farmed by pacing a doorway") % map._stall
			break
		# The clock counts SECONDS, not ticks: a slow frame rate ticks the map less
		# often, and a rescue promised in 90 s must not become one in 150 s on the
		# machine that most needs it (codex review).
		map._tick(1.0)
		if not is_equal_approx(map._stall, map.TICK_INTERVAL + 1.0):
			failure = "a %.2f s tick advanced the stall clock to %.2f s, not %.2f" \
				% [1.0, map._stall, map.TICK_INTERVAL + 1.0]
			break

		# 5. Past the threshold the arrow fades in, on the true bearing to the block.
		map._stall = map.STALL_SECONDS
		map._tick()
		if map._jail_alpha <= 0.0:
			failure = "no anti-stall arrow after %.0f s without progress" % map.STALL_SECONDS
			break
		var target: Vector3 = tower.to_global(
				(TowerInterior.block_min() + TowerInterior.block_max()) * 0.5)
		var want := Vector2(target.x - map._player_pos.x, target.z - map._player_pos.z).normalized()
		var centre: Vector2 = map.MAP_CENTER
		var tip: Vector2 = map._jail_points[0]
		var got := (tip - centre).normalized()
		if want.dot(got) < 0.999:
			failure = "the anti-stall arrow points %s, not at the cell block (%s)" % [got, want]
			break

		# 6. THE LABYRINTH degrades the line instead of blanking it, and its arrow
		#    flickers on a coarse bearing rather than holding a true one.
		_stand_in(tower, player, zone_maze)
		map._tick()
		if not map._floor_text.contains(str(maze + 1)):
			failure = "in the labyrinth the storey line reads \"%s\"" % map._floor_text
			break
		if map._jail_text.contains("F%d" % (jail + 1)):
			failure = "the labyrinth still holds a lock on the block: \"%s\"" % map._jail_text
			break
		if not map._jail_text.contains("^%d" % (jail - maze)):
			failure = "the degraded line \"%s\" dropped the ^%d floor delta" \
				% [map._jail_text, jail - maze]
			break
		map._stall = map.STALL_SECONDS
		var lit := 0
		var dark := 0
		var coarse := true
		# One flicker period and a quarter, at TICK_INTERVAL a tick.
		for _i: int in int(map.MAZE_FLICKER_PERIOD * 1.25 / map.TICK_INTERVAL):
			map._tick()
			if map._jail_alpha <= 0.0:
				dark += 1
				continue
			lit += 1
			var lit_tip: Vector2 = map._jail_points[0]
			var angle: float = (lit_tip - centre).angle()
			var over: float = fposmod(angle, map.MAZE_BEARING_STEP)
			if minf(over, map.MAZE_BEARING_STEP - over) > 0.001:
				coarse = false
		if lit == 0 or dark == 0:
			failure = ("the labyrinth's unstable lock is not unstable: %d ticks lit, %d dark " \
				+ "— a degraded system that always answers is not degraded") % [lit, dark]
			break
		if not coarse:
			failure = "the labyrinth's bearing is not snapped to %.2f rad" % map.MAZE_BEARING_STEP
			break

		# 7. Out of the door, everything is forgotten — including the rooms, so the
		#    next visit starts a fresh timer rather than one that is already expired.
		tower.inside = false
		map._tick()
		if not map._floor_text.is_empty() or not map._jail_text.is_empty() \
				or map._jail_alpha > 0.0 or map._stall > 0.0 or not map._visited.is_empty():
			failure = "leaving the HQ left %d rooms and %.1f s of stall behind" \
				% [map._visited.size(), map._stall]
		break

	tower.free()
	map._tick()
	if not failure.is_empty():
		return failure
	print("indoors: storey line + jail intent on storey %d, degraded on %d, arrow anti-stall only" \
		% [office + 1, maze + 1])
	return ""


func _room_cell_local(floor_index: int, letter: String) -> Vector3:
	"""One cell of one room, as a point on that storey's walking surface in the
	interior's own frame — `Vector3.INF` when the room has no cells."""
	var cells: Array[Vector2i] = TowerInterior._room_cells(
			TowerPlans.storey(floor_index)["rows"], letter)
	if cells.is_empty():
		return Vector3.INF
	var cell: Vector2i = cells[cells.size() / 2]
	return Vector3(TowerInterior._grid_x(float(cell.x) + 0.5),
			TowerInterior.FLOOR_Y[floor_index] + 0.1,
			TowerInterior._grid_z(float(cell.y) + 0.5))


func _stand_in(tower: Node3D, player: Node3D, local: Vector3) -> void:
	"""Park the stub tower so the (stationary) player stands at `local` inside it.

	Moving the BUILDING rather than the player is what keeps this honest: the player
	is a live `CharacterBody3D` on a live world and teleporting it up a hundred
	metres would put it in freefall through everything else the tick reads."""
	tower.global_position = player.global_position - local


func _landmark_is_clamped(map: Control, index: int) -> bool:
	"""Whether a landmark X was drawn as an off-map (rim-clamped) mark.

	Read off the ALPHA for the reason `_dot_is_clamped` gives: an off-map mark is
	the only thing that scales the colour by LANDMARK_EDGE_ALPHA, while a clamped
	X and one drawn at the very edge of the view sit within a pixel of each other."""
	var alpha: float = (map._landmark_colors[index * 2] as Color).a
	return alpha < map.COLOR_LANDMARK.a - 0.001


func _landmark_center(map: Control, index: int) -> Vector2:
	"""The centre of a landmark X — the midpoint of its first arm, which is the
	same point both arms cross at."""
	return (map._landmark_points[index * 4] + map._landmark_points[index * 4 + 1]) * 0.5


func _landmark_reach(map: Control, index: int) -> float:
	"""How far the furthest PAINTED point of a landmark X sits from the map centre
	— the four arm ends, plus half the stroke width the two segments are drawn at.
	The mark's ink, not its anchor, is what may not cross the ring."""
	var furthest := 0.0
	for i in range(index * 4, index * 4 + 4):
		var d: float = (map._landmark_points[i] - map.MAP_CENTER as Vector2).length()
		furthest = maxf(furthest, d)
	return furthest + map.LANDMARK_MARK_WIDTH * 0.5


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
