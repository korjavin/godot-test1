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
##
## ponytail: a filter that skips the EARLIER shots also skips their settles, and
## some of what a shot photographs is populated by the ones before it — `only=cast_2`
## renders the forest with group `"crocodile"` empty and quietly poses nobody, where
## `only=cast` renders all three and finds one. Filter to a GROUP (`only=cast`), not
## to a single late shot, unless the shot stands alone.
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
		elif a.begins_with("cast="):
			# THE CAST'S DIFFUSE MODE (bead godot-test1-y1o.22). `cast=burley` is the
			# only writer of `ToonShading.cast_diffuse_burley`; anything else — and
			# the absence of the argument — is the shipped cel banding. Through the
			# setter, never the var: `main.tscn` is an EARLIER SIBLING of this node,
			# so the hero has already been styled and cached by the time this runs.
			ToonShading.set_cast_burley(a.substr(5) == "burley")
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
	var street := Vector3(1600.0 + 5.0 * 62.0, 0.0, 3.0 * 62.0)
	# ...and one on a real AVENUE (bead 8gw.23): every CITY_AVENUE_EVERY-th grid
	# line is the only place traffic_manager puts a car, so an ordinary street is
	# the one view of Budapest with no cars in it.
	var avenue := Vector3(1600.0 + 5.0 * 62.0, 0.0, 0.0)

	print("[SHOTS] field=", field, " forest=", forest, " street=", street, " avenue=", avenue)

	# THE CAST (bead godot-test1-y1o.22) — a hero AND a predator in frame, at three
	# light levels, so the owner can rule on `DIFFUSE_TOON` vs the world's Burley
	# from pictures. They share the `cast` prefix so `only=cast` renders exactly
	# these three and skips the six landmark sweeps, which are about the WORLD and
	# cost minutes each. Budapest gets no posed predator: the rect spawns no
	# ordinary crocodile, and dragging one onto a street would be a photograph of
	# something the game never shows.
	await _shoot(terrain, player, field, 0.0, "cast_1_field", true)
	await _shoot(terrain, player, forest, 0.0, "cast_2_forest", true)
	await _shoot(terrain, player, street, -PI * 0.5, "cast_3_budapest")

	await _shoot(terrain, player, field, 0.0, "1_field")
	await _shoot(terrain, player, forest, 0.0, "2_forest")
	await _shoot(terrain, player, street, -PI * 0.5, "3_budapest")
	await _shoot(terrain, player, avenue, -PI * 0.5, "3b_budapest_avenue")

	# THE FIELD BRIDGES (bead godot-test1-06o.2) — two shots, and the second one
	# keeps the HUD on because the minimap's river line is half of what it shows.
	await _shoot_field_bridge(terrain, player)

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

func _shoot_field_bridge(terrain: Node, player: Node3D) -> void:
	"""
	Photograph the first field bridge on this seed twice: from the bank, and
	standing on the deck with the HUD up.

	The site is a pure function of (station index, run seed) through the road's
	centreline and the river field, so asking the terrain where the bridge is
	costs nothing and lands in the same place every run — the same property the
	landmark shots lean on one table along.
	"""
	# THE ROAD CACHE IS NOT DROPPED BY set_run_seed(), only by new_run(), so a
	# tool that has not taken a shot yet is still holding the BOOT seed's
	# stations — and every bridge hangs off a station index. Re-seat the world on
	# SEED first; _shoot does the same thing again for the pose it frames.
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
	turned off; nothing is restored, because this tool takes its shots and quits.
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

# ============================================================================
# THE CAST CLOSE-UP (bead godot-test1-y1o.22)
# ============================================================================
# The gameplay rig frames the WORLD: `$CameraPivot/CameraArm/Camera3D` sits ten-odd
# metres back and high, which puts the hero at about 5% of the frame — fine for
# judging a biome's blocks, useless for ruling on how a 2 m body's diffuse falls
# off. So a cast shot gets its OWN camera, close and level, and stands the nearest
# predator beside the hero. Nothing about the gameplay rig is touched: a second
# `Camera3D` is added under the tree root and made `current`, which is also why it
# can be posed at all — a `SpringArm3D` overwrites its children's local position on
# its own internal physics tick, so writing the shipped camera's transform is
# silently undone.

## Where the cast camera stands relative to the hero: `CAST_CAM_BACK` metres along
## a FIXED world bearing (so the key light falls the same way in every cast shot
## and in both halves of every pair), `CAST_CAM_HEIGHT` up, aimed at chest height.
const CAST_CAM_BEARING := Vector3(0.72, 0.0, 0.69)
const CAST_CAM_BACK: float = 5.6
const CAST_CAM_HEIGHT: float = 2.0
const CAST_CAM_AIM_Y: float = 1.15

## Where the posed predator stands relative to the hero — beside him, slightly
## forward, so the two silhouettes never stack and both are square to the light.
const PREDATOR_POSE_SIDE: float = 2.5
const PREDATOR_POSE_AHEAD: float = 0.6

## A predator further than this was not in this neighbourhood, and dragging one
## across the world would photograph something the game never shows. Budapest is
## the case that matters: the rect spawns no ordinary crocodile, so the nearest is
## the Danube's, hundreds of metres off — that shot gets the hero alone, which is
## the honest picture of a city street.
const PREDATOR_POSE_MAX_DIST: float = 120.0


func _shoot(terrain: Node, player: Node3D, where: Vector3, yaw: float,
		name: String, cast_closeup: bool = false) -> void:
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
	# THE PREDATORS ARE FROZEN TOO (bead godot-test1-y1o.22), for the reason the
	# camera above is: a body mid-waddle in one half of an A/B pair and mid-turn in
	# the other is noise in the only thing the pair is asked to show. The LOD
	# manager would wake one inside the frames below — it ticks at ~9 Hz and
	# `set_lod_active(true)` restores exactly the `_physics_process` this clears —
	# so it stops first. Nothing is restored; this tool takes its shots and quits.
	var lod := get_tree().get_first_node_in_group("lod_manager")
	if lod != null:
		lod.set_physics_process(false)
		lod.set_process(false)
	for c_v: Variant in get_tree().get_nodes_in_group("crocodile"):
		(c_v as Node).set_physics_process(false)
	if cast_closeup:
		_frame_cast(player, where)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir + "/" + name + ".png")
	print("[SHOTS] wrote ", name, " at ", where)

func _frame_cast(player: Node3D, where: Vector3) -> void:
	"""
	Re-frame a cast shot: a close, level camera on the hero, and the nearest
	predator stood beside him.

	WHY A SECOND CAMERA. The shipped rig is a `SpringArm3D` that rewrites its
	child's local position on its own internal physics tick, so posing
	`$CameraPivot/CameraArm/Camera3D` is silently undone however frozen the player
	is. A plain `Camera3D` added under the tree root and made `current` is both
	controllable and completely inert as far as the game is concerned — this tool
	takes its shots and quits, so nothing is restored.

	WHY THE PREDATOR IS POSED AND NOT FOUND. Its SPAWN is deterministic in the seed
	but its wander is not (`piglet_crocodile_ai` rolls speed and rhythm off a
	`randomize()`d RNG), so "photograph whatever walked into shot" gives one half of
	the pair a crocodile and the other half an empty field — and a comparison of how
	the CAST is shaded needs a body in both frames or it shows nothing. Both
	variants stand the same species at the same metre under the same light, so the
	only difference left between the two PNGs is the material.

	It runs AFTER the freeze in `_shoot`, so nothing walks back out of frame in the
	two frames before the grab.
	"""
	var bearing: Vector3 = CAST_CAM_BEARING.normalized()
	var side := Vector3(bearing.z, 0.0, -bearing.x)

	# THE PREDATOR FIRST, so a refusal still leaves the camera framed on the hero.
	#
	# CHOSEN BY NAME, NEVER BY DISTANCE. A crocodile's node name is deterministic in
	# (chunk, seed) but its WANDER is not, so "the nearest one" answered a different
	# body in each half of the pair — and on the forest spot that was a white wolf
	# against a green crocodile, which is a photograph of two different animals and
	# says nothing at all about a material. The in-range set is the same in both
	# runs because the same seed loads the same chunks; sorting it makes the pick
	# the same too. (The per-instance SIZE roll is still random — documented noise,
	# and far quieter than a change of species.)
	var names: Array[String] = []
	var by_name: Dictionary = {}
	var best_d: float = INF
	for c_v: Variant in get_tree().get_nodes_in_group("crocodile"):
		var c := c_v as Node3D
		if c == null or not c.is_inside_tree():
			continue
		var d: float = c.global_position.distance_to(where)
		best_d = minf(best_d, d)
		if d > PREDATOR_POSE_MAX_DIST:
			continue
		names.append(String(c.name))
		by_name[String(c.name)] = c
	names.sort()
	var best: Node3D = null
	if not names.is_empty():
		best = by_name[names[0]]
	if best != null:
		best.global_position = Vector3(
				where.x + side.x * PREDATOR_POSE_SIDE + bearing.x * PREDATOR_POSE_AHEAD,
				where.y,
				where.z + side.z * PREDATOR_POSE_SIDE + bearing.z * PREDATOR_POSE_AHEAD)
		# Square to the lens, so the lit front and the shaded flank are both in
		# shot — the whole diffuse falloff the pair exists to compare.
		best.rotation.y = atan2(bearing.x, bearing.z)
		print("[SHOTS] posed ", best.name, " (was ", "%.1f" % best_d, " m away)")
	else:
		print("[SHOTS] no predator within ", PREDATOR_POSE_MAX_DIST, " m of ", where,
				" — hero alone (nearest ", "%.1f" % best_d, " m)")

	var cam := _cast_camera()
	var eye: Vector3 = where + bearing * CAST_CAM_BACK + Vector3(0.0, CAST_CAM_HEIGHT, 0.0)
	cam.global_position = eye
	cam.look_at(Vector3(where.x, where.y + CAST_CAM_AIM_Y, where.z), Vector3.UP)


func _cast_camera() -> Camera3D:
	"""The cast close-up camera, made once and reused, `current` from the moment it
	exists. Parented to the tree root rather than to the player, so nothing the
	body does between shots can move it."""
	var existing := get_tree().root.get_node_or_null("CastShotCamera")
	if existing is Camera3D:
		return existing as Camera3D
	var cam := Camera3D.new()
	cam.name = "CastShotCamera"
	get_tree().root.add_child(cam)
	cam.current = true
	return cam


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
