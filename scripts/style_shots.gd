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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Without this the desktop window vsyncs at 60 and every frame-time reading
	# is the monitor's, not the renderer's.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for a in OS.get_cmdline_user_args():
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
	# them uses the block material this bead touches — hide them.
	for g in ["crowd", "traffic", "weather"]:
		var amb := get_tree().get_first_node_in_group(g)
		if amb is Node3D:
			(amb as Node3D).visible = false

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

	print("[SHOTS] field=", field, " forest=", forest, " street=", street)

	await _shoot(terrain, player, field, 0.0, "1_field")
	await _shoot(terrain, player, forest, 0.0, "2_forest")
	await _shoot(terrain, player, street, -PI * 0.5, "3_budapest")

	print("[SHOTS] done -> ", _out_dir)
	get_tree().quit(0)

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
	player.set_physics_process(true)
	terrain.new_run(SEED, chunk)
	player.global_position = where
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
	await _measure(name)
	# Always the same hero, whatever a crocodile did while the chunks landed.
	player.set_active_character(0)
	await get_tree().create_timer(YAW_SECONDS, true, false, true).timeout
	# Re-assert the pose and FREEZE it: the camera pivot is written every physics
	# frame from a LAGGED yaw, so a run where a bite nudged the body frames the
	# street differently. Writing the pivot and stopping the physics tick is what
	# makes the before/after pair the same camera.
	player.global_position = where
	player.rotation.y = yaw
	player.velocity = Vector3.ZERO
	player.camera_pivot.rotation = Vector3(0.0, yaw, 0.0)
	# The respawn blink toggles visibility, so a bite during the settle can leave
	# the hero mid-blink and absent from one shot of the pair.
	player.visible = true
	var model := player.get_node_or_null("CharacterModel")
	if model is Node3D:
		(model as Node3D).visible = true
	player.set_physics_process(false)
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

func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for c in root.get_children():
		out.append_array(_all_nodes(c))
	return out
