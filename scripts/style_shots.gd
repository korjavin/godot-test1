extends Node
## Acceptance capture tool for the y1o visual-style epic (bead godot-test1-y1o.7).
## Runs the real main.tscn, forces one fixed run_seed, teleports the player to
## three fixed spots (open field, forest, Budapest street), waits for the chunk
## queue to fill, and saves a PNG of the viewport for each.
##
## It also prints a [PERF] line per spot — average frame time, draw calls and the
## shipped spike telemetry's summary — taken on the LIVE game before the pose is
## frozen, which is the F3 reading the epic asks every child PR for.
##
## Usage: godot --path . scenes/style_shots.tscn -- <outdir> [only=<substring>]
##                                                           [hide=<groups>]
##        godot --rendering-method gl_compatibility --path . …   (the web renderer)
##
## It is a DEBUG TOOL and nothing in the game loads it: `scenes/style_shots.tscn`
## is its own scene, reached only from the command line.

const SEED: int = 20260904
const SETTLE_SECONDS: float = 9.0
const YAW_SECONDS: float = 1.5

var _out_dir: String = "user://shots"
## Optional `only=<substring>` command-line filter, so a bead that wants two
## shots does not sit through eleven. Empty means "every shot", which is what CI
## and the epic's A/B pairs want.
var _only: String = ""

## Which ambience groups `hide=` suppresses. The default is the y1o list — this
## tool exists to A/B the BLOCK material and randomized ambience is noise against
## it — but bead 8gw.23 is about the crowd and the traffic THEMSELVES, so it
## passes `hide=weather,fauna` and keeps them on screen.
var _hidden_groups: PackedStringArray = PackedStringArray(["crowd", "traffic", "weather", "fauna"])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Without this the desktop window vsyncs at 60 and every frame-time reading
	# is the monitor's, not the renderer's.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5)
		elif a.begins_with("hide="):
			_hidden_groups = a.substr(5).split(",", false)
		else:
			_out_dir = a
	DirAccess.make_dir_recursive_absolute(_out_dir)
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	# Kill the start card (it holds the pause and covers the screen).
	var start := get_tree().get_first_node_in_group("start_overlay")
	if start != null:
		start._dismiss()
	await get_tree().process_frame

	# Hide every HUD CanvasLayer so the shot is the WORLD.
	for n in _all_nodes(get_tree().root):
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false

	# The ambience managers all use randomize()d RNG, so their content differs
	# between two runs of this tool and would drown the A/B in noise. None of
	# them uses the block material this tool exists to compare — hide them.
	#
	# HIDE THE DESCENDANTS, NOT THE MANAGER. `crowd` and `traffic` are Node3Ds
	# whose root flip would do, but `weather` is a plain `Node` (WeatherManager
	# extends Node and parents its cloud/rain/bird MultiMeshes to itself), so a
	# `manager is Node3D` test silently skips the one system whose randomized
	# clouds actually show up in the sky of every shot.
	for g in _hidden_groups:
		for amb in get_tree().get_nodes_in_group(g):
			_hide_visuals(amb)

	var terrain := get_tree().get_first_node_in_group("terrain")
	var player := get_tree().get_first_node_in_group("player")
	if terrain == null or player == null:
		push_error("no terrain/player")
		get_tree().quit(1)
		return

	terrain.set_run_seed(SEED)

	# Find the two field spots deterministically off THIS seed, so the before/after
	# pair lands on byte-identical world content.
	var field := _find_biome(terrain, terrain.Biome.PLAINS)
	var forest := _find_biome(terrain, terrain.Biome.FOREST)
	# DESERT and SNOW join the set for bead godot-test1-y1o.23: that bead repaints
	# the GROUND, and these are the two bands where the ground is most of the frame
	# — a forest shot is mostly canopy. Additive, so every existing shot name and
	# every earlier A/B pair is untouched.
	var desert := _find_biome(terrain, terrain.Biome.DESERT)
	var snow := _find_biome(terrain, terrain.Biome.SNOW)
	# The CITY BAND (bead godot-test1-y1o.5) is the procedural biome, NOT Budapest
	# — the two shots below it are the authored city and have nothing to do with
	# this one. Its houses, stalls and lamps are `_spawn_city_content`'s.
	var band := _find_biome(terrain, terrain.Biome.CITY)
	# ...and a real NOMAD CAMP, found by asking the shipped spawner rather than by
	# a hand-typed chunk: a camp is a pure function of (chunk, run_seed), so the
	# same SEED puts it in the same place for the before shot and the after shot.
	var camp := _find_camp(terrain)
	var street := Vector3(1600.0 + 5.0 * 62.0, 0.0, 3.0 * 62.0)
	# ...and one on a real AVENUE (bead 8gw.23): every CITY_AVENUE_EVERY-th grid
	# line is the only place traffic_manager puts a car, so an ordinary street is
	# the one view of Budapest with no cars in it.
	var avenue := Vector3(1600.0 + 5.0 * 62.0, 0.0, 0.0)

	print("[SHOTS] field=", field, " forest=", forest, " street=", street, " avenue=", avenue)
	# _find_biome SILENTLY falls back to a fixed spot when its sweep finds nothing,
	# which would hand you a "snow" shot of plains and no way to tell. Print the
	# biome each spot actually resolved to, so a fallback is visible in the log.
	for probe: Array in [[field, "1_field"], [forest, "2_forest"],
			[desert, "1b_desert"], [snow, "1c_snow"]]:
		var p: Vector3 = probe[0]
		print("[SHOTS] ", probe[1], " at ", p, " is biome ", terrain.biome_at(p.x, p.z))

	await _shoot(terrain, player, field, 0.0, "1_field")
	await _shoot(terrain, player, desert, 0.0, "1b_desert")
	await _shoot(terrain, player, snow, 0.0, "1c_snow")
	await _shoot(terrain, player, forest, 0.0, "2_forest")
	await _shoot(terrain, player, band, 0.0, "2b_city_band")
	if camp != Vector3.INF:
		# Stand off the camp and look back at it, the field bridge's idiom: the
		# huts are the subject, so the camera wants them in front of it.
		await _shoot(terrain, player, camp + Vector3(-16.0, 0.0, -10.0),
				atan2(-16.0, -10.0), "2c_camp")
	else:
		print("[SHOTS] no camp within the sweep on seed ", SEED, " — skipped")
	await _shoot(terrain, player, street, -PI * 0.5, "3_budapest")
	await _shoot(terrain, player, avenue, -PI * 0.5, "3b_budapest_avenue")

	# THE FIELD BRIDGES (bead godot-test1-06o.2) — two shots, and the second one
	# keeps the HUD on because the minimap's river line is half of what it shows.
	await _shoot_field_bridge(terrain, player)

	# THE HERO ROW (bead godot-test1-y1o.24) — the HUD skin's pilot, and the pair
	# the owner rules the whole style spec from. Two spots because the row is
	# drawn OVER the world: a bright field and a dark city street are the two
	# grounds an ink-on-bone palette has to stay legible against.
	await _shoot_hero_row(terrain, player, field, 0.0, "12_hero_row_field")
	await _shoot_hero_row(terrain, player, street, -PI * 0.5, "13_hero_row_budapest")

	# THE SCORE LINE (bead godot-test1-y1o.26) — the same two grounds, for the same
	# reason: the coin counter is the one place the palette's amber is the TEXT
	# colour, and amber-on-INK has to read over bright grass AND a dark street.
	await _shoot_coin_line(terrain, player, field, 0.0, "14_coin_line_field")
	await _shoot_coin_line(terrain, player, street, -PI * 0.5, "15_coin_line_budapest")

	# LANDMARKS (bead godot-test1-y1o.6). Each one is found by BUILDER NAME rather
	# than by a hand-typed chunk: `_landmark_at` is a pure function of (chunk,
	# run_seed), so sweeping it answers "where is the Taj in this world" without
	# building anything, and the same SEED puts it in the same chunk for the
	# before shot and the after shot. `dist` is per-place because the registry's
	# shapes run from a 4 m bronze to a 20 m cathedral.
	for shot_v: Variant in LANDMARK_SHOTS:
		var shot: Dictionary = shot_v
		await _shoot_landmark(terrain, player, String(shot["builder"]),
				float(shot["dist"]), String(shot["name"]))

	print("[SHOTS] done -> ", _out_dir)
	get_tree().quit(0)

## The landmark shots, by BUILDER NAME — the registry's own identity, and the one
## thing that cannot drift when a row is appended (the `kind` index can).
const LANDMARK_SHOTS: Array = [
	{ "builder": "_landmark_taj", "dist": 22.0, "name": "4_taj" },
	{ "builder": "_landmark_st_basil", "dist": 19.0, "name": "5_st_basil" },
	{ "builder": "_landmark_cologne", "dist": 26.0, "name": "6_cologne" },
	{ "builder": "_landmark_parthenon", "dist": 24.0, "name": "7_parthenon" },
	{ "builder": "_landmark_pisa", "dist": 18.0, "name": "8_pisa" },
	{ "builder": "_landmark_kinderdijk", "dist": 24.0, "name": "9_kinderdijk" },
]

## How far out the sweep looks for a chunk carrying the wanted landmark. The
## registry is 48 places at LANDMARK_CHANCE, so one particular place is rare —
## this is a few thousand chunks, which costs a hash each and nothing else.
const LANDMARK_SWEEP: int = 60


func _landmark_kind(builder: String) -> int:
	for i in LandmarkBuilders.LANDMARKS.size():
		if String((LandmarkBuilders.LANDMARKS[i] as Dictionary)["builder"]) == builder:
			return i
	return -1


func _find_landmark_chunks(terrain: Node, kind: int) -> Array:
	"""
	Every chunk near spawn whose deterministic landmark ROLL is this kind, nearest
	first. A roll is not a building: spawn_landmark_in_chunk's candidate loop can
	still reject every spot in the chunk, which is why the caller walks this list
	and checks for a real marker rather than trusting the first hit.
	"""
	var out: Array = []
	for ring in range(1, LANDMARK_SWEEP):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dz) != ring:
					continue   # only the ring's edge; the inside was walked already
				var lm: Dictionary = terrain._landmark_at(Vector2i(dx, dz))
				if not lm.is_empty() and int(lm["kind"]) == kind:
					out.append(Vector2i(dx, dz))
		if out.size() >= 6:
			return out
	return out


func _shoot_landmark(terrain: Node, player: Node3D, builder: String, dist: float, name: String) -> void:
	"""
	Stand `dist` metres from one named landmark and photograph it.

	TWO SETTLES, because the marker only exists once the chunk is BUILT: the first
	teleport is to the chunk centre (which is where `_landmark_at` says the place
	is, to within half a chunk), and only then can the `landmark` group be asked
	where the stone actually stands. The second pose is inside chunks that are
	already up, so it needs no rebuild — `_shoot` re-runs the settle anyway, which
	is what freezes the same camera for both halves of an A/B.
	"""
	if _only != "" and not name.contains(_only):
		return   # the filter is checked HERE too: the sweep below is the cost
	var kind := _landmark_kind(builder)
	if kind < 0:
		print("[SHOTS] no registry row named ", builder)
		return
	var at := Vector3.INF
	# THE MARKER'S OWN `kind` META IS THE TEST, not "the nearest marker": a rolled
	# chunk whose candidate loop found no spot builds nothing, and the nearest
	# marker is then some OTHER landmark hundreds of metres away — which is a shot
	# of the wrong building with the right filename, the one failure this tool
	# cannot afford (measured: the Taj and the Parthenon both photographed Big Ben).
	for chunk_v: Variant in _find_landmark_chunks(terrain, kind):
		var chunk: Vector2i = chunk_v
		var centre: Vector3 = terrain.chunk_to_world(chunk) + Vector3(25.0, 2.0, 25.0)
		player.set_physics_process(true)
		player.set_process(true)
		terrain.new_run(SEED, chunk)
		player.global_position = centre
		player.velocity = Vector3.ZERO
		await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
		for n_v: Variant in get_tree().get_nodes_in_group("landmark"):
			var n: Node3D = n_v
			if int(n.get_meta("kind", -1)) == kind and n.global_position.distance_to(centre) < 60.0:
				at = n.global_position
		if at != Vector3.INF:
			break
	if at == Vector3.INF:
		print("[SHOTS] ", builder, " rolled but never built within the sweep — skipped")
		return
	# Stand south-east of it and turn to face it. A Node3D's forward is -Z, so
	# `Basis(UP, yaw) * -Z` must equal `-back`: sin yaw = back.x, cos yaw = back.z,
	# i.e. yaw = atan2(back.x, back.z).
	var back := Vector3(0.7, 0.0, 0.7).normalized() * dist
	await _shoot(terrain, player, at + back + Vector3(0.0, 2.0, 0.0),
			atan2(back.x, back.z), name)

func _shoot_hero_row(terrain: Node, player: Node3D, at: Vector3, yaw: float,
		name: String) -> void:
	"""
	One shot of a spot with ONLY the hero portrait row on screen.

	`_show_widget` is bead 06o.2's and does exactly this job already — the HUD is
	one shared CanvasLayer, so it turns that layer on, the row's own branch on and
	every other branch off. It hides siblings and never restores them, so the two
	shot families used to clobber whichever ran second; that is fixed in
	`_show_widget` itself rather than by an ordering rule here, because an
	ordering rule is invisible to the next person who appends a shot.
	"""
	if _only != "" and not name.contains(_only):
		return
	_show_widget("hero_hud")
	await _shoot(terrain, player, at, yaw, name)
	_show_widget("hero_hud", false)


func _shoot_coin_line(terrain: Node, player: Node3D, at: Vector3, yaw: float,
		name: String) -> void:
	"""
	One shot of a spot with ONLY the score line on screen — `_shoot_hero_row`'s
	twin, one group along.

	The line is SET first, because the one the owner has to rule on is the FULL
	one (level, coins, the skill-point suffix) and a fresh harness reads
	"Lv 1 Coins: 0" — a shot of three glyphs says nothing about how a long amber
	string sits over a street.

	**Both halves are pinned, and the level is the half that matters**: coins are
	a run number this tool owns, but `Progression` is LIFETIME state loaded from
	`user://`, so it climbs between two runs of this tool — the before shot of an
	A/B pair read "Lv 15 … 8 SP" against the after shot's "Lv 5", which is two
	different strings and therefore not a comparison. It is a debug tool that
	quits when it is done, so nothing restores either.
	"""
	if _only != "" and not name.contains(_only):
		return
	if "coins_collected" in player:
		player.coins_collected = 1287
	var progression := get_tree().get_first_node_in_group("progression")
	if progression != null and "level" in progression and "spent_points" in progression:
		progression.level = 12
		progression.spent_points = 0
	_show_widget("coin_hud")
	await _shoot(terrain, player, at, yaw, name)
	_show_widget("coin_hud", false)


func _shoot_field_bridge(terrain: Node, player: Node3D) -> void:
	"""
	Photograph the first field bridge on this seed twice: from the bank, and
	standing on the deck with the HUD up.

	The site is a pure function of (station index, run seed) through the road's
	centreline and the river field, so asking the terrain where the bridge is
	costs nothing and lands in the same place every run — the same property the
	landmark shots lean on one table along.
	"""
	# EVERY BRIDGE HANGS OFF A STATION INDEX, so a tool that has not taken a shot
	# yet is still holding the BOOT seed's road. `new_run(SEED)` re-seats the
	# whole world on SEED — which since bead godot-test1-bvq drops the road memos
	# through `set_run_seed()`, so a bare `set_run_seed(SEED)` would do for the
	# road alone; the full `new_run` stays because this also wants the chunks.
	# _shoot does the same thing again for the pose it frames.
	terrain.new_run(SEED, Vector2i.ZERO)
	terrain._road_extend_to_x(0.0, 1450.0)
	var row: Dictionary = {}
	for k in range(2, terrain._road_terminal_k()):
		row = terrain.field_bridge_at(k)
		if not row.is_empty():
			break
	if row.is_empty():
		print("[SHOTS] seed ", SEED, " has no field bridge — skipped")
		return
	var poly: PackedVector2Array = row["poly"]
	var foot: Vector2 = poly[0]
	var mid: Vector2 = poly[int(poly.size() / 2)]

	# 1. FROM THE BANK: stand back and to one side of the west ramp's foot and
	# look up the crossing, so the shot carries the ramp, the deck and the water.
	var to_mid := (mid - foot).normalized()
	var side := Vector2(-to_mid.y, to_mid.x)
	var eye := foot - to_mid * 6.0 + side * 16.0
	var look := Vector3(mid.x - eye.x, 0.0, mid.y - eye.y)
	await _shoot(terrain, player, Vector3(eye.x, 2.0, eye.y),
			atan2(-look.x, -look.z), "10_field_bridge_bank")

	# 2. ON THE DECK, MINIMAP UP: the minimap's river line (bead godot-test1-06o.1)
	# is the other half of this picture — the hero is standing on the blue band.
	# ONE widget's layer, not every CanvasLayer: a HUD widget hides by flipping
	# its own layer's `visible`, so showing them all reveals the pause card and
	# the F3/F4 debug panels over the shot.
	_show_widget("minimap")
	var deck_y: float = terrain.field_bridge_surface_y(Vector3(mid.x, 0.0, mid.y))
	await _shoot(terrain, player, Vector3(mid.x, deck_y + 1.0, mid.y),
			atan2(-to_mid.x, -to_mid.y), "11_field_bridge_deck")
	_show_widget("minimap", false)


func _show_widget(group: String, on: bool = true) -> void:
	"""
	Show ONE HUD widget and nothing else on its layer.

	The HUD is one shared CanvasLayer, so flipping the layer reveals the coin
	label, the ability dial and the hero row along with the widget asked for —
	which is three things too many in a shot whose point is the minimap. The
	layer is turned on and every branch of it that does not lead to the widget is
	turned off.

	IT SHOWS THE TARGET BRANCH TOO, and that line is the whole reason two callers
	can coexist. Turning the LAYER on says nothing about a branch a PREVIOUS call
	hid: `_show_widget("minimap")` hides `HeroHUD`, and a later
	`_show_widget("hero_hud")` that only flipped the layer would photograph an
	empty corner — which is exactly what happened to whichever of the two shot
	families ran second, in both orders. Nothing is restored on the way OUT (the
	tool takes its shots and quits), and it does not need to be: every caller
	states what it wants shown.
	"""
	for n_v: Variant in get_tree().get_nodes_in_group(group):
		var n: Node = n_v
		var branch: Node = n
		while n != null and not (n is CanvasLayer):
			branch = n
			n = n.get_parent()
		if n == null:
			continue
		(n as CanvasLayer).visible = on
		if on and branch is CanvasItem:
			(branch as CanvasItem).visible = true
		for sibling in (n as CanvasLayer).get_children():
			if sibling == branch:
				continue
			if sibling is CanvasItem:
				(sibling as CanvasItem).visible = false


func _find_biome(terrain: Node, want: int) -> Vector3:
	var x: float = 250.0
	while x < 1500.0:
		for zi in range(-6, 7):
			var z: float = float(zi) * 40.0
			if terrain.biome_at(x, z) != want:
				continue
			# Dry for 40 m all round, so the shot is the BIOME and not a riverbank.
			var dry := true
			for o in [Vector3(0, 0, 0), Vector3(40, 0, 0), Vector3(-40, 0, 0),
					Vector3(0, 0, 40), Vector3(0, 0, -40)]:
				if terrain.is_river_at(Vector3(x, 0.0, z) + o):
					dry = false
			if dry:
				return Vector3(x, 2.0, z)
		x += 25.0
	return Vector3(300.0, 2.0, 0.0)

func _find_camp(terrain: Node) -> Vector3:
	"""
	A spot a few metres off a REAL nomad camp's huts, or Vector3.INF when the
	sweep finds none (bead godot-test1-y1o.5).

	Found by running the SHIPPED spawner over a chunk window and keeping the first
	chunk that actually built something — the landmark sweep's idiom, and the
	reason it is not a hand-typed coordinate: a camp is a pure function of (chunk,
	run_seed), so this lands on the same camp for the before shot and the after
	shot, and it keeps working the day the camp rate is retuned.
	"""
	for cx in range(2, 30):
		for cz in range(-6, 7):
			var chunk := Vector2i(cx, cz)
			var parent := MeshInstance3D.new()
			parent.position = terrain.chunk_to_world(chunk)
			var batch: Array = []
			var body := StaticBody3D.new()
			var platforms: Array = []
			# THE REAL SEQUENCE, not the camp call on its own: a camp accepts the
			# first spot that clears `_biome_spot_ok`, which reads the `obstacles`
			# the earlier spawners filled — so probing with an empty list picks a
			# spot the shipped chunk rejects, and the camera then frames bare grass
			# beside the camp (measured the slow way). EVERY spawner create_chunk
			# runs before the camp has to be here, the ARTIFACT included: it lands
			# a footprint too, and on seed 57 leaving it out picked chunk (4, -2)
			# where the live path's first camp is (6, -1).
			var obstacles: Array = terrain.spawn_objects_in_chunk(chunk, platforms, batch, body)
			terrain.spawn_artifact_in_chunk(chunk, parent, obstacles, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk, obstacles, batch, body)
			var before: int = batch.size()
			terrain.spawn_camp_in_chunk(chunk, parent, obstacles, batch, body)
			var built: int = batch.size() - before
			body.free()
			parent.free()
			if built == 0:
				continue
			# The camp's own centre, not the chunk's, and only the CAMP's boxes: a
			# 50 m chunk is wide enough that framing its centre shows you empty
			# grass next to a village.
			var mean := Vector3.ZERO
			for i in range(before, batch.size()):
				mean += (batch[i] as Dictionary)["transform"].origin
			mean /= float(built)
			var at: Vector3 = terrain.chunk_to_world(chunk) + Vector3(mean.x, 2.0, mean.z)
			print("[SHOTS] camp in chunk ", chunk, ": ", built, " boxes, centre ", at)
			return at
	return Vector3.INF

func _shoot(terrain: Node, player: Node3D, where: Vector3, yaw: float, name: String) -> void:
	if _only != "" and not name.contains(_only):
		return
	var chunk := Vector2i(roundi(where.x / 50.0), roundi(where.z / 50.0))
	# The previous shot froze both ticks (see below) — hand the body back.
	player.set_physics_process(true)
	player.set_process(true)
	terrain.new_run(SEED, chunk)
	player.global_position = where
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
	await _measure(name)
	# Always the same hero, whatever a crocodile did while the chunks landed.
	player.set_active_character(0)
	await get_tree().create_timer(YAW_SECONDS, true, false, true).timeout
	# Re-assert the pose and FREEZE it: the camera pivot is written from a LAGGED
	# yaw plus a shake offset, so a run where a bite nudged the body frames the
	# street differently. Writing the pivot and stopping the tick is what makes
	# the before/after pair the same camera.
	#
	# BOTH TICKS, and that is the whole point: `player_controller` writes
	# `camera_pivot.rotation` in `_process`, not in `_physics_process`, so
	# stopping physics alone leaves the rig free to drift back over the frames
	# this waits for before grabbing the buffer.
	player.global_position = where
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	# THE PIVOT'S YAW IS A LAG OFFSET, NOT A HEADING (`camera_yaw_lag`, which
	# player_controller decays to zero) — it is a child of the body, so writing the
	# heading here TURNED THE CAMERA TWICE and framed everything 45 degrees off the
	# thing the shot was aimed at (measured on the Taj, bead godot-test1-y1o.6).
	# Zero the yaw, keep the pitch the rig is holding.
	player.camera_pivot.rotation = Vector3(player.camera_pivot.rotation.x, 0.0, 0.0)
	# The respawn blink toggles visibility, so a bite during the settle can leave
	# the hero mid-blink and absent from one shot of the pair.
	player.visible = true
	var model := player.get_node_or_null("CharacterModel")
	if model is Node3D:
		(model as Node3D).visible = true
	player.set_physics_process(false)
	player.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir + "/" + name + ".png")
	print("[SHOTS] wrote ", name, " at ", where)

## 300 frames of the game running normally at this spot: frame time, draw calls,
## and whatever the shipped spike telemetry logged. Taken BEFORE the pose is
## frozen, so it measures the live game and not a stopped one.
func _measure(name: String) -> void:
	var frames := 300
	var t0 := Time.get_ticks_usec()
	var draws := 0
	var worst := 0.0
	for i in frames:
		var f0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		worst = maxf(worst, float(Time.get_ticks_usec() - f0) / 1000.0)
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	var perf := get_tree().root.find_child("PerfOverlay", true, false)
	var spikes := {}
	if perf != null and perf.has_method("get_spike_summary"):
		spikes = perf.get_spike_summary()
	print("[PERF] ", name, " avg_ms=%.2f fps=%.1f worst_ms=%.1f draws=%d spikes=%s"
			% [ms, 1000.0 / maxf(ms, 0.001), worst, draws / frames, str(spikes)])

## Hide everything drawable under `root`, root included. Walks the subtree rather
## than flipping one `visible`, because an ambience manager may be a plain `Node`
## with drawable children (WeatherManager is).
func _hide_visuals(root: Node) -> void:
	for n in _all_nodes(root):
		if n is Node3D:
			(n as Node3D).visible = false

func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out
