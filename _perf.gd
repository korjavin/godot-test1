extends SceneTree
## THROWAWAY frame-spike probe for the tower interior — deleted after use.
##   godot --path . --script res://_perf.gd --resolution 1280x720 -- <leg>
## <leg> is field | shell | interior. ONE LEG PER PROCESS, because legs run in the
## same process are not comparable: crocodile population and chunk count grow with
## time, so a later leg is measured in a heavier world than an earlier one.

const SETTLE: int = 480
const SAMPLE: int = 600


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var leg: String = args[0] if args.size() > 0 else "field"
	await process_frame
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 30:
		await process_frame
	var overlay := main.get_node_or_null("HUD/StartOverlay") as Control
	if overlay != null and overlay.has_method("_on_play_solo_pressed"):
		overlay.call("_on_play_solo_pressed")
	paused = false
	for _i in 20:
		await process_frame

	var player := main.get_node_or_null("Player") as Node3D
	var terrain := main.get_node_or_null("EndlessTerrain") as Node3D
	var perf := main.get_node_or_null("HUD/PerfOverlay")
	var site: Vector3 = terrain.call("tower_site")
	var start := site + (Vector3(0.0, 0.0, 260.0) if leg == "field" else Vector3(4.0, 0.0, 2.0))

	player.global_position = start
	for _i in 200:
		await process_frame
	if leg == "noshadow":
		var shell2: Node = terrain.call("tower_shell")
		var stack2: Array[Node] = [shell2.get_node("TowerInterior")]
		while not stack2.is_empty():
			var n: Node = stack2.pop_back()
			for c: Node in n.get_children():
				stack2.append(c)
			if n is GeometryInstance3D:
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if leg == "shell" or leg == "six":
		var shell: Node = terrain.call("tower_shell")
		var interior := shell.get_node_or_null("TowerInterior") as Node3D
		if leg == "shell":
			interior.visible = false
			interior.set_process(false)
		else:
			# Keep the six movers drawn and hide the rest, i.e. simulate what a
			# merged static mesh would leave behind.
			var keep := ["DemandShutter", "IdentityMass", "Band1", "Band2", "Band3", "Band4"]
			var stack: Array[Node] = [interior]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				for c: Node in n.get_children():
					stack.append(c)
				if n is MeshInstance3D and not keep.has(String(n.name)):
					(n as MeshInstance3D).visible = false
	for _i in SETTLE:
		await process_frame

	perf.call("reset_spike_stats")
	var samples: Array[float] = []
	for i in SAMPLE:
		var t := float(i) / float(SAMPLE) * TAU
		player.global_position = start + Vector3(sin(t) * 4.0, 0.0, cos(t) * 3.0)
		player.rotation = Vector3(0.0, t, 0.0)
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	samples.sort()
	var s: Dictionary = perf.call("get_spike_summary")
	var total := 0.0
	for v: float in samples:
		total += v
	print("LEG %s -> %s  draws %d  process mean %.1f ms median %.1f p95 %.1f" % [
		leg, s, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		total / float(samples.size()), samples[samples.size() / 2],
		samples[int(float(samples.size()) * 0.95)]])
	quit(0)
