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
## Usage: godot --path . scenes/style_shots.tscn -- <outdir>
##        godot --rendering-method gl_compatibility --path . …   (the web renderer)
##
## It is a DEBUG TOOL and nothing in the game loads it: `scenes/style_shots.tscn`
## is its own scene, reached only from the command line.

const SEED: int = 20260904
const SETTLE_SECONDS: float = 9.0
const YAW_SECONDS: float = 1.5

var _out_dir: String = "user://shots"
var _hidden_groups: PackedStringArray = PackedStringArray(["crowd", "traffic", "weather", "fauna"])

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Without this the desktop window vsyncs at 60 and every frame-time reading
	# is the monitor's, not the renderer's.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	# Second arg: which ambience groups to hide, comma-separated. The default is
	# the y1o list (this tool exists to A/B the BLOCK material, and randomized
	# ambience is noise against it) — but bead 8gw.23 is about the crowd and the
	# traffic themselves, so it passes "weather,fauna" and keeps them on screen.
	if args.size() > 1:
		_hidden_groups = args[1].split(",", false)
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
	var street := Vector3(1600.0 + 5.0 * 62.0, 0.0, 3.0 * 62.0)
	# ...and one on a real AVENUE (bead 8gw.23): every CITY_AVENUE_EVERY-th grid
	# line is the only place traffic_manager puts a car, so an ordinary street is
	# the one view of Budapest with no cars in it.
	var avenue := Vector3(1600.0 + 5.0 * 62.0, 0.0, 0.0)

	print("[SHOTS] field=", field, " forest=", forest, " street=", street, " avenue=", avenue)

	await _shoot(terrain, player, field, 0.0, "1_field")
	await _shoot(terrain, player, forest, 0.0, "2_forest")
	await _shoot(terrain, player, street, -PI * 0.5, "3_budapest")
	await _shoot(terrain, player, avenue, -PI * 0.5, "3b_budapest_avenue")

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

func _shoot(terrain: Node, player: Node3D, where: Vector3, yaw: float, name: String) -> void:
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
