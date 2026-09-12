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
## Usage: godot --path . scenes/style_shots.tscn -- <outdir> [only=<substring>[,<substring>...]]
##                                                           [hide=<groups>] [web]
##        godot --rendering-method gl_compatibility --path . … -- <outdir> web
##
## `--rendering-method gl_compatibility` IS NOT THE WEB BUILD, and a shot that
## claims to be one without `web` is not evidence (bead godot-test1-6n1, where a
## whole A/B had to be retaken). The flag switches the RENDERER; every `.web`
## project-setting override resolves on the `web` FEATURE TAG, which a desktop
## binary never carries. Pass `web` as well and `_emulate_web_settings()` forces
## what actually differs — see its docstring.
##
## It is a DEBUG TOOL and nothing in the game loads it: `scenes/style_shots.tscn`
## is its own scene, reached only from the command line.

const SEED: int = 20260904
const SETTLE_SECONDS: float = 9.0
const YAW_SECONDS: float = 1.5

var _out_dir: String = "user://shots"
## Optional `only=<substring>[,<substring>...]` command-line filter, so a bead
## that wants two shots does not sit through eleven. Empty means "every shot",
## which is what CI and the epic's A/B pairs want. Comma-separated (bead
## godot-test1-z3e.10): this environment's per-shot fixed cost (world/camp
## sweep, a real settle) dwarfs one shot's own camera work, so a caller wanting
## several shots that already share `_head_pose_settled` (16/17/18/19/20) asks
## for them in ONE process rather than paying the settle five times over.
var _only: String = ""

## Set by the `web` argument — see `_emulate_web_settings`. Off means "whatever
## this binary is", which is what every pre-existing shot was taken with.
var _emulate_web: bool = false

func _wanted(name: String) -> bool:
	if _only == "":
		return true
	for token in _only.split(",", false):
		if name.contains(token):
			return true
	return false

## Which ambience groups `hide=` suppresses. The default is the y1o list — this
## tool exists to A/B the BLOCK material and randomized ambience is noise against
## it — but bead 8gw.23 is about the crowd and the traffic THEMSELVES, so it
## passes `hide=weather,fauna` and keeps them on screen.
var _hidden_groups: PackedStringArray = PackedStringArray(["crowd", "traffic", "weather", "fauna"])

## Set by a shot that POSES a HUD widget, spent by `_shoot` just after it freezes
## the body — see the call site for why a posed widget needs re-asserting at all.
## A Callable rather than a (node, text) pair because the caller already holds
## both and this file should not learn what a caption is.
var _repose: Callable = Callable()

## Whether a head close-up has already teleported, settled and FROZEN the hero, so a
## second framing may reuse the pose. See `_shoot_head_closeup`'s `settle`.
var _head_pose_settled: bool = false

## Metres from the face. The bead's framing: "a ~2 m hero close-up".
const HEAD_SHOT_DISTANCE: float = 2.0
## The second framing, same camera position, a long lens instead — 2 m of a 75-degree
## default FOV puts a 0.26 m head across 8% of the frame, which is the honest in-game
## read and useless for judging a nose.
const FACE_SHOT_FOV: float = 16.0
## THE JAW (bead godot-test1-394; owner: "why do the heroes look like they have a
## beard?"). 16 and 17 are shot from slightly ABOVE the eye line, which is the one
## angle that hides the underside of the chin — exactly where a beard would be and
## exactly where both suspects (the lip paint band, and DIFFUSE_TOON's shadow band)
## land. This is the same camera dropped below the eye line so it looks UP at the
## chin, at a metre instead of two. `JAW_SHOT_DROP` is metres below the focus
## point; the camera still aims AT the focus, so the drop is the whole tilt.
const JAW_SHOT_DISTANCE: float = 1.0
const JAW_SHOT_DROP: float = 0.22

# ============================================================================
# SPIKE godot-test1-z3e.10 — THE HERO BODY VARIANTS
#
# A scratch-branch-only addition, in the shape of z3e.1's `head=<a|b|c>` (see
# git show dd22d7a^:scripts/style_shots.gd — `_apply_head_variant`, deleted
# once that spike's pick landed): `hero=<name>` picks which CHARACTERS entry
# is "the hero" for every shot that used to hardcode index 0/Windman. Absent,
# it reproduces every existing shot byte-for-byte.
#
# `body=<parts|uncut|skinned>` and `anim=<proc|clip>` lived here too, and RETIRED
# with bead godot-test1-5u3.3 exactly as bead 5u3.1 said they would: all three
# `body=` columns pointed at scratch scenes cut from a MakeHuman body that the
# SHIPPED Teibi now is, and `anim=proc` was a hand-rolled probe of the bone driver
# bead 5u3.2 then shipped for real. `hero=teibi` now shoots the skinned hero
# through the game's own `hero_rig_skeleton.gd`, which is the sharper instrument:
# a picture of this tool's own arithmetic could never catch a mis-wired seam.
# ============================================================================

# ----------------------------------------------------------------------------
# SPIKE godot-test1-td8 — `cloth=<a|b|d|all>`, the CLOTH columns, in the shape
# `body=` had before bead 5u3.3 retired it (git show cf60ca6^:scripts/
# style_shots.gd — `_apply_body_variant`). The variant is a SCRATCH .glb built by
# `scripts/build_hero.py --hero teibi --variant <name>`; nothing else in the game
# ever loads one and an absent `cloth=` reproduces every existing shot.
#
# It swaps the .glb UNDER the hero's `Body` rather than the whole `Body` node,
# which is the one simplification the skinned era allows: a skinned hero is one
# glTF scene instanced at `Body/Mesh` (scenes/characters/teibi.tscn), so the
# column is a different instance in the same slot and the `Body` node the landing
# squash and `capture_rest_pose()` write stays exactly where it was.
var _cloth: String = ""
const CLOTH_VARIANT_DIR: String = "res://assets/models/characters/teibi_parts/"

var _hero: String = "windman"
## True as soon as `hero=` is present. It is the one switch that lets the spike
## frame its own shots differently — see `_shoot_head_closeup` — while a run
## without it reproduces every pre-existing shot byte-for-byte.
var _spike: bool = false

## Metres from the body centre — `_shoot_head_closeup`'s camera, pulled back so
## the WHOLE hero fits (2 m at 75 degrees cuts the feet; 3 m does not).
const BODY_SHOT_DISTANCE: float = 3.0
const BODY_SHOT_FOCUS_HEIGHT: float = 0.9
const BODY_SHOT_FOV: float = 75.0
## Crown (beret included) to the middle of the face. Measured on today's Teibi,
## where the `Head` node origin IS the face centre: crown 1.78 m, origin 1.62 m.
const CROWN_TO_FACE: float = 0.16

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
		elif a.begins_with("hero="):
			_hero = a.substr(5)
			_spike = true
		elif a.begins_with("cloth="):
			_cloth = a.substr(6)
		elif a == "web":
			_emulate_web = true
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

	if _emulate_web:
		_emulate_web_settings(terrain)

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

	# SPIKE godot-test1-z3e.10 — make `hero=` the active character BEFORE anything
	# is shot, so the close-up and every other shot see the same one. A no-op
	# without `hero=` (index 0, Windman, is already active).
	player.set_active_character(_hero_index(player))

	# SPIKE godot-test1-td8 — and AFTER the line above, not before it: the swap
	# re-points `player.anim` at the new mesh, and `set_active_character` would
	# then re-point it at a body this function had already freed.
	_apply_cloth_variant(player)

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

	# THE HERO HEAD (spike godot-test1-z3e.1) — two framings from ONE camera spot,
	# because they answer two different questions: 16 is what a player at two metres
	# actually sees, 17 is whether the thing has a nose.
	await _shoot_head_closeup(terrain, player, field, 75.0, "16_head_2m")
	await _shoot_head_closeup(terrain, player, field, FACE_SHOT_FOV, "17_head_face", false)

	# THE JAW AT ONE METRE (bead godot-test1-394). Same settled, frozen pose, one
	# metre out and below the eye line looking UP at the chin — the framing 16 and
	# 17 cannot give, and the only one that says whether the smear under the jaw is
	# the lip paint or the toon shadow. See `JAW_SHOT_DROP`.
	await _shoot_head_closeup(terrain, player, field, FACE_SHOT_FOV, "21_jaw_1m",
			false, JAW_SHOT_DISTANCE, JAW_SHOT_DROP)

	# THE HERO BODY (spike godot-test1-z3e.10) — reuses `_head_pose_settled`
	# exactly as 16/17 do. 19 must run LAST: it poses the ALREADY-FROZEN hero
	# mid-stride by writing the animation clock directly, and nothing restores it.
	await _shoot_body(terrain, player, field, "18_body_3m", false, false)

	# THE TORSO AT ONE METRE (spike godot-test1-td8) — between 18 and 19, and
	# before 19 for 19's own reason: it writes the animation clock and nothing
	# restores it. 18 is the GAMEPLAY distance and it is what the cloth columns
	# are actually ruled on; this one is the control that says whether a column's
	# detail exists at all, or only exists at 3 m as a smudge.
	await _shoot_torso(terrain, player, field, "20_torso_1m")

	await _shoot_body(terrain, player, field, "19_body_stride", false, true)

	# THE STRIDE STRIP (spike godot-test1-5u3.1) — six frames over one stride
	# period, after 19 for the same reason 19 comes after 18: it writes the
	# animation clock and nothing restores it.
	await _shoot_body_strip(terrain, player, field, "20_body_strip")

	# THE IDLE AND AIR/LAND STRIPS (bead godot-test1-5u3.9) — the other two things
	# "natural movements" is ruled on and a stride strip cannot show: whether a
	# hero standing still is alive, and whether a jump and its landing read as a
	# body absorbing an impact. Same camera, same pause, same numbered-PNG output
	# as shot 20, and after it for the same reason it comes after 19: all three
	# write the animation clock and none of them restores it.
	await _shoot_idle_strip(terrain, player, field, "23_idle_strip")
	await _shoot_air_strip(terrain, player, field, "24_air_strip")

	# THE PREDATOR PORTRAITS (bead godot-test1-hb0) — the GD-SURVEY hunter in the
	# field and the SAME chassis on guard duty at the HQ, which is the pair the
	# owner rules the machine's redesign from. They come after the hero shots for
	# the reason 19 and 20 do: each one spawns a live body into the world and
	# takes the pause around it, so anything downstream would be shooting through
	# whatever they left behind.
	await _shoot_predator(terrain, player, field,
			"res://scenes/characters/hunter_robot.tscn", "hunter_robot",
			"25_hunter", false)
	await _shoot_predator(terrain, player, player.debug_destination_hq(),
			"res://scenes/characters/tower_guard.tscn", "tower_guard",
			"26_tower_guard", true)

	# THE CAPTIONS (bead godot-test1-y1o.38) — the respawn countdown and the
	# level-up line, the two biggest strings the game ever puts over the world.
	# One ground each rather than both: they are drawn dead centre at 48/40 px, so
	# the question is whether BONE-on-INK survives a bright field (the harder of
	# the two grounds for a light letter), not how they sit in a corner.
	await _shoot_caption(terrain, player, field, 0.0, "respawn_label",
		"Caught! Back in %.1f..." % 1.2, "16_caption_respawn")
	await _shoot_caption(terrain, player, field, 0.0, "level_up_label",
		"LEVEL 12\n+1 skill point", "17_caption_level_up")

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

	# THE WAYPOINT CIRCLES (bead godot-test1-sc6.1) — three of the eleven, one per
	# ground they have to read on: the open field beside the coin road, a Budapest
	# street, and the HQ's doorstep. The beams ship HIDDEN, so what these show is
	# the inert ring, which is the thing the owner judges.
	await _shoot_waypoint(terrain, player, "road_1", 9.0, "21_waypoint_field")
	await _shoot_waypoint(terrain, player, "gate", 9.0, "22_waypoint_budapest")
	await _shoot_waypoint(terrain, player, "hq", 14.0, "23_waypoint_hq_door")

	print("[SHOTS] done -> ", _out_dir)
	get_tree().quit(0)


func _shoot_waypoint(terrain: Node, player: Node3D, id: String, dist: float, name: String) -> void:
	"""
	Stand `dist` metres off one named waypoint circle and turn to face it.

	The site comes from the SHIPPED `TerrainWaypoints.waypoint_sites()` rather than
	from a hand-typed spot: the road's circles move with `run_seed`, and `_run()`
	has already written SEED (line ~163), so asking the table is what puts the
	camera on the same metre in the before shot and the after shot.

	No two-settle dance like `_shoot_landmark`'s — a waypoint's position is known
	before any chunk is built, because that is the whole point of the family.
	"""
	if not _wanted(name):
		return
	var at := Vector3.INF
	for row_v: Variant in TerrainWaypoints.waypoint_sites(terrain):
		var row: Dictionary = row_v
		if String(row["id"]) == id:
			at = row["pos"]
	if at == Vector3.INF:
		print("[SHOTS] no waypoint named ", id, " — skipped")
		return
	# Same framing arithmetic as `_shoot_landmark`: a Node3D's forward is -Z, so
	# yaw = atan2(back.x, back.z) turns the body back toward the subject.
	var back := Vector3(0.7, 0.0, 0.7).normalized() * dist
	await _shoot(terrain, player, at + back, atan2(back.x, back.z), name)

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
	if not _wanted(name):
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
	if not _wanted(name):
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
	if not _wanted(name):
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


func _shoot_caption(terrain: Node, player: Node3D, at: Vector3, yaw: float,
		group: String, line: String, name: String) -> void:
	"""
	One shot of a big centred caption — `_shoot_coin_line`'s twin, one group
	along, with the string passed in because the two captions this serves live in
	two different scripts.

	THE TEXT IS WRITTEN STRAIGHT ONTO THE LABEL rather than by provoking the
	event. The respawn countdown only exists inside a 1.5 s freeze that follows a
	real bite, and the level-up line inside a lifetime-coin threshold crossing —
	staging either would make this tool simulate gameplay to photograph a font.
	The label is the widget under test and its writers are untouched by the bead
	this serves, so posing it is honest. It is a debug tool that quits when it is
	done, so nothing restores the text.

	BUT THE RESPAWN LABEL HAS A LIVE PER-FRAME WRITER, so the pose is handed to
	`_shoot` as `_repose` and re-applied after the freeze. A crocodile arriving
	during the 9 s settle makes `player_controller._show_respawn_countdown()`
	rewrite the text and `_hide_respawn_message()` hide the label, and the shot
	came out EMPTY — reproduced on the shipped seed, one run in a few, with no
	error anywhere. (The level-up label has no such writer — `progression`
	`set_process(false)`s itself until a level-up — but it costs nothing to
	re-assert both through one seam.)
	"""
	if not _wanted(name):
		return
	var label := get_tree().get_first_node_in_group(group)
	if label == null:
		print("[SHOTS] no node in group ", group)
		return
	var pose := func() -> void:
		label.text = line
		_show_widget(group)
	pose.call()
	_repose = pose
	await _shoot(terrain, player, at, yaw, name)
	_repose = Callable()
	_show_widget(group, false)


func _apply_cloth_variant(player: Node3D) -> void:
	"""
	SPIKE godot-test1-td8. Replace the hero's skinned `.glb` instance with one of
	the cloth columns' scratch builds. A no-op without `cloth=`.

	`set_active_character()` RUNS AGAIN at the end, and that is the same rule the
	retired `_apply_body_variant` wrote down: `player.anim` caches node references
	INTO the body (the Skeleton3D and its bone indices, for a skinned hero), so a
	swap that does not re-activate leaves the driver posing a freed mesh.
	"""
	if _cloth == "":
		return
	# THE COLUMNS ARE TEIBI'S BODY. Without this, `cloth=b` on its own dresses
	# WINDMAN — index 0 is the default hero — in Teibi's mesh, and the run still
	# writes a full set of PNGs that look like a column and are not one.
	if _hero != "teibi":
		push_error("[SHOTS] cloth= is Teibi's spike (bd godot-test1-td8) and hero is "
				+ _hero + " — pass hero=teibi too")
		return
	var path: String = CLOTH_VARIANT_DIR + "teibi_cloth_" + _cloth + ".glb"
	if not ResourceLoader.exists(path):
		push_error("[SHOTS] no cloth column at " + path
				+ " — build it with build_hero.py --hero teibi --variant " + _cloth)
		return
	var hero: Node3D = player.character_instances[_hero_index(player)]
	var body := hero.get_node_or_null("Body") as Node3D
	if body == null:
		push_error("[SHOTS] hero " + _hero + " has no Body node to dress")
		return
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var mesh := (load(path) as PackedScene).instantiate() as Node3D
	mesh.name = "Mesh"
	body.add_child(mesh)
	# The same styling every OTHER hero's body gets from `preload_all_characters()`
	# — which is where column D's material split is actually read (`toon_shading.gd`).
	player.anim.apply_character_style(mesh)
	player.set_active_character(_hero_index(player))
	print("[SHOTS] cloth column ", _cloth, " -> ", path, " on hero ", _hero)


func _hero_index(player: Node) -> int:
	"""SPIKE godot-test1-z3e.10. Resolve `_hero` (a CHARACTERS name) to its index,
	the way `hero_hud.gd` and `remote_avatar.gd` already do off the same shared
	table. Falls back to 0 (Windman) for an unknown name, matching the default."""
	var chars: Array = player.CHARACTERS
	for i in chars.size():
		if String((chars[i] as Dictionary)["name"]) == _hero:
			return i
	return 0


## SPIKE godot-test1-5u3.1 — frames in one stride period for shot 20's strip.
const STRIP_FRAMES: int = 6


func _pose_walk(player: Node3D, t: float) -> void:
	"""Put the hero at walk-cycle time `t`, through the SHIPPED animation seam.

	One line of arithmetic and no branch, and that is the point: until bead
	godot-test1-5u3.3 this matched on an `anim=` column and a hand-rolled
	`_pose_skinned()` wrote bone rotations beside the game's own driver, because
	no shipped hero was skinned. Now one is, and `animate_walking()` poses him
	through `hero_rig.gd` — bones for Teibi, limb nodes for the other three —
	which is what makes a shot of him evidence about the game rather than about
	this file. It stays a named seam because shots 19 and 20 both call it.
	"""
	player.anim.animation_time = t
	player.anim.animate_walking(1.0 / 60.0, 1.0)


func _shoot_body(terrain: Node, player: Node3D, at: Vector3, name: String,
		settle: bool, stride: bool) -> void:
	"""
	SPIKE godot-test1-z3e.10. One ~3 m three-quarter-front shot of the WHOLE hero —
	`_shoot_head_closeup`'s camera, pulled back and re-focused at chest height
	instead of the face. Reuses its settle / measure / freeze sequence and the
	same `_head_pose_settled` rule (see that function's docstring).

	`stride` poses the ALREADY-FROZEN hero mid-stride (shot 19) through
	`_pose_walk()` at a clock a quarter of a stride in. NOTHING RESTORES IT, which
	is why 19 runs LAST of the body shots and why 20 follows it: a later shot that
	wants a standing hero gets whatever pose 19 left, unless it poses itself the
	way this function's own non-stride path does (`_pose_walk(player, 0.0)`, the
	rest pose).
	"""
	if not _wanted(name):
		return
	if settle or not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)

	# RE-ASSERT THE HERO WITH THE TICKS ALREADY OFF. The settle above is a LIVE
	# window and a `captures_hero` grab jails whoever is active and auto-switches
	# — the `set_active_character` inside the block is followed by YAW_SECONDS and
	# a `_measure()` of live frames, which is plenty. MEASURED on bead 5u3.1: one
	# 10.5 s settle logged three switches and framed WINDMAN in a `hero=teibi`
	# column. Here nothing can move it, and it is a no-op when the settle was
	# uneventful or was paid by shot 17.
	player.set_active_character(_hero_index(player))

	# BOTH body shots write the animation clock, not just the stride one. The
	# settle above is a LIVE window: a predator that reaches the hero in it taxes
	# a coin and respawns in place, and the walk cycle then freezes wherever the
	# clock happened to be — which is how the first round of this spike shot its
	# "standing" frame mid-gesture and made 18 and 19 nearly the same picture.
	# `animation_time = 0` is sin(0) = 0, i.e. every limb at `original_rotations`:
	# the rest pose, from the same seam and with nothing to restore.
	var gait := PlayerAnimation.gait_for(_hero)
	_pose_walk(player, (PI * 0.5 / float(gait["stride_rate"])) if stride else 0.0)

	var cam := _body_camera(player)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir + "/" + name + ".png")
	cam.queue_free()
	print("[SHOTS] wrote ", name, " at ", at, " hero=", _hero)


## SPIKE godot-test1-td8 — the torso close-up. One metre out at the body camera's
## own FOV, focused at chest height, so the frame is the polo and the waistband
## and nothing else. The two numbers are the whole shot.
const TORSO_SHOT_DISTANCE: float = 1.0
const TORSO_SHOT_FOCUS_HEIGHT: float = 1.15


func _shoot_torso(terrain: Node, player: Node3D, at: Vector3, name: String) -> void:
	"""
	SPIKE godot-test1-td8. `_shoot_body`'s three-quarter-front camera at ONE metre
	instead of three, framed on the chest. Same settle, same freeze, same rest
	pose, the same FOV and the same +0.10 m eye lift — it differs from shot 18 in
	the distance and the focus height and in nothing else, which is the point: the
	pair is a controlled comparison of what survives the gameplay distance.

	The NAME shares shot 20's ordinal with `20_body_strip`, which is what the bead
	asked for; the files do not collide (the strip writes `20_body_strip_<n>.png`)
	and the ordering rule is the one that matters — this runs after 18 and BEFORE
	19, because 19 writes the animation clock and nothing restores it.
	"""
	if not _wanted(name):
		return
	if not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)
	# Shot 18's reason, verbatim: the settle is a LIVE window and a grab
	# auto-switches whoever is active.
	player.set_active_character(_hero_index(player))
	_pose_walk(player, 0.0)

	var focus: Vector3 = player.global_position \
			+ Vector3(0.0, TORSO_SHOT_FOCUS_HEIGHT, 0.0)
	var cam := Camera3D.new()
	cam.fov = BODY_SHOT_FOV
	add_child(cam)
	var basis := player.global_transform.basis
	cam.global_position = focus + (-basis.z) * (TORSO_SHOT_DISTANCE * 0.88) \
			+ basis.x * (TORSO_SHOT_DISTANCE * 0.42) + Vector3(0.0, 0.10, 0.0)
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out_dir + "/" + name + ".png")
	cam.queue_free()
	print("[SHOTS] wrote ", name, " at ", at, " hero=", _hero)


func _settle_body_pose(terrain: Node, player: Node3D, at: Vector3, name: String) -> void:
	"""`_shoot_body`'s settle, lifted out so shot 20 can pay it too. IT IS A
	REQUEST, NOT AN ASSERTION — the same rule `_shoot_head_closeup` documents:
	`only=` can filter out the shot that was supposed to have done the settling,
	so every shot that needs a settled pose asks for one and gets a no-op when
	`_head_pose_settled` already holds."""
	var chunk := Vector2i(roundi(at.x / 50.0), roundi(at.z / 50.0))
	player.set_physics_process(true)
	player.set_process(true)
	terrain.new_run(SEED, chunk)
	player.global_position = at
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
	player.set_active_character(_hero_index(player))
	await get_tree().create_timer(YAW_SECONDS, true, false, true).timeout
	await _measure(name)
	player.global_position = at
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.visible = true
	var model := player.get_node_or_null("CharacterModel")
	if model is Node3D:
		(model as Node3D).visible = true
	player.set_physics_process(false)
	player.set_process(false)
	_head_pose_settled = true
	await get_tree().process_frame


func _body_camera(player: Node3D) -> Camera3D:
	"""`_shoot_body`'s three-quarter-front camera, lifted out so the six-frame
	stride strip (shot 20) frames every frame identically to shots 18/19."""
	var focus: Vector3 = player.global_position + Vector3(0.0, BODY_SHOT_FOCUS_HEIGHT, 0.0)
	var cam := Camera3D.new()
	cam.fov = BODY_SHOT_FOV
	add_child(cam)
	var basis := player.global_transform.basis
	cam.global_position = focus + (-basis.z) * (BODY_SHOT_DISTANCE * 0.88) \
			+ basis.x * (BODY_SHOT_DISTANCE * 0.42) + Vector3(0.0, 0.10, 0.0)
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	return cam


func _shoot_body_strip(terrain: Node, player: Node3D, at: Vector3, name: String) -> void:
	"""
	SPIKE godot-test1-5u3.1, shot 20. SIX frames evenly spaced across ONE stride
	period, same camera as shot 18. A single frozen frame says whether a pose is
	pretty; only a strip says whether the TIMING is — which is the whole question
	the owner rules "natural movements" from. Written as six numbered PNGs and
	montaged outside (ImageMagick composes the grids anyway), so no image code
	lives in here.
	"""
	if not _wanted(name):
		return
	if not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)
		player.set_active_character(_hero_index(player))
	# ONE CAMERA FOR ALL SIX FRAMES, and the world PAUSED around them. The single
	# shots get away with building a camera per shot because each is judged alone;
	# a strip is judged as a sequence, and anything that moves between its frames
	# reads as part of the motion. MEASURED on this bead, with a camera rebuilt per
	# frame off `player.global_transform` and the tree still running: the six
	# frames came back from six different angles (one dead side-on) with chunks
	# popping in behind — `set_physics_process(false)` stops the controller, not the
	# tweens that can still turn the body, and not the chunk queue. `PauseHub` is
	# the only sanctioned writer of `tree.paused` (CLAUDE.md); `process_frame` and
	# `frame_post_draw` both still fire while it holds, which is all this needs.
	var period: float = TAU / float(PlayerAnimation.gait_for(_hero)["stride_rate"])
	var cam := _body_camera(player)
	PauseHub.take(self)
	for frame in STRIP_FRAMES:
		_pose_walk(player, period * float(frame) / float(STRIP_FRAMES))
		await _save_frame(name, frame)
	PauseHub.release(self)
	cam.queue_free()
	print("[SHOTS] wrote ", STRIP_FRAMES, " frames of ", name, " over ",
			"%.3f s" % period, " hero=", _hero)


# ============================================================================
# THE PREDATOR PORTRAIT (bead godot-test1-hb0)
#
# The hero shots above all frame the PLAYER; nothing here framed an enemy, and
# the hunter robot's redesign is ruled from a silhouette. Three frames per call
# and one settle: a flat SIDE (the silhouette the owner rules from), a
# THREE-QUARTER front (where a chest decal and a visor actually read), and a
# WIDE frame with the hero standing beside the machine, which is the only one of
# the three that answers "how big is it".
# ============================================================================

## Metres from the machine. The bead's framing: the acquisition read "at 5 m".
const PREDATOR_SHOT_DISTANCE: float = 5.0
## Where the portrait camera looks — chest height on a ~2.5 m biped, which keeps
## the lens level rather than tilted up at a dome.
const PREDATOR_FOCUS_HEIGHT: float = 1.30
## A LONG LENS ON THE TWO PORTRAITS, and the distance stays 5 m. The game's own
## 75-degree field at five metres puts a 2.5 m machine across a tenth of the
## frame, which is the honest acquisition read and useless for ruling on a visor
## slit — the same split shots 16 and 17 make for the hero's face. The WIDE frame
## below keeps the game FOV, so the pair still answers both questions.
const PREDATOR_PORTRAIT_FOV: float = 40.0
## How far to the machine's own +X (its authored front) the hero stands. Off the
## camera axis rather than on it: at 2 m in front the hero simply eclipsed the
## subject, which is what the first round of this shot photographed.
const PREDATOR_HERO_GAP: float = 6.0
## The wide frame pulls back and looks at the gap between the two bodies, from
## roughly a standing hero's eye height — at nine metres and three up it was a
## drone shot of two dots, which answers nothing about how the machine reads
## across a field.
const PREDATOR_WIDE_DISTANCE: float = 7.5


func _shoot_predator(terrain: Node, player: Node3D, at: Vector3, scene_path: String,
		species: String, name: String, settle: bool) -> void:
	"""
	Three frames of a SHIPPED predator scene standing beside the settled hero.

	The scene is the real `.tscn`, not the `.glb`, and `species` is written
	BEFORE `add_child` — the call-order contract every spawner in the game
	honours, and the reason a portrait taken here is evidence about the thing
	that spawns rather than about a mesh file: a `Model` transform, a wrong row
	or a scene that no longer loads all show up in the picture.

	THE WORLD IS PAUSED AROUND ALL THREE FRAMES, for the reason the stride strip
	documents one function up and one more of its own: this body is a live
	`CharacterBody3D` whose `_physics_process` would walk it out of frame, and
	whose row makes it `captures_hero` — an unpaused hunter five metres from a
	frozen hero jails him and the shot becomes a picture of a respawn. `PauseHub`
	is the only sanctioned writer of `tree.paused` (CLAUDE.md); `process_frame`
	and `frame_post_draw` both still fire while it holds.

	The body is left at `rotation.y = 0`, i.e. the MESH's own +X (its authored
	forward) pointing at world +X, and the cameras are placed off that axis
	instead of off the body's travel facing. `_animate_body` is what applies
	`model_facing_offset`, and it never runs here — so framing off the authored
	axis is the only way the side view is the same side in every run.
	"""
	if not _wanted(name):
		return
	if settle or not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)
	player.set_active_character(_hero_index(player))
	_pose_walk(player, 0.0)

	var scene := load(scene_path) as PackedScene
	if scene == null:
		print("[SHOTS] no scene at ", scene_path, " — ", name, " skipped")
		return
	var body := scene.instantiate() as Node3D
	body.species = species
	# Stand it on the hero's +X, i.e. off to the side of both portrait cameras
	# (which live out on ±Z) rather than behind the hero on their axis.
	var spot := player.global_position + Vector3(PREDATOR_HERO_GAP, 0.0, 0.0)
	body.position = spot
	PauseHub.take(self)
	terrain.add_child(body)
	# NOMINAL SIZE, NOT ONE OF THE ROW'S ROLLS. `_ready()` has just multiplied the
	# body by `size_random_factor` off an unseeded RNG — ±5% on the hunter row, so
	# the machine in this frame would be 2.43-2.69 m tall and a DIFFERENT height
	# every run. The wide frame below is the shot that answers "how big is it" and
	# a before/after pair is compared at exactly that scale, so the portrait shows
	# the size the species row and the capsule actually describe. After
	# `add_child`, because that is when `_ready()` writes it.
	body.scale = Vector3.ONE
	await get_tree().process_frame
	await get_tree().process_frame

	var focus := spot + Vector3(0.0, PREDATOR_FOCUS_HEIGHT, 0.0)
	# +Z is the model's own LEFT (predator_parts' orientation contract), so a
	# camera out on +Z is a flat side view and one swung 55 degrees toward the
	# nose is the three-quarter front.
	await _capture_from(focus + Vector3(0.0, 0.0, PREDATOR_SHOT_DISTANCE), focus,
			PREDATOR_PORTRAIT_FOV, name + "_side")
	await _capture_from(focus + Vector3(0.82, 0.10, 0.57) * PREDATOR_SHOT_DISTANCE,
			focus, PREDATOR_PORTRAIT_FOV, name + "_quarter")
	var pair := (spot + player.global_position) * 0.5 + Vector3(0.0, 1.0, 0.0)
	await _capture_from(pair + Vector3(0.50, 0.16, 0.85) * PREDATOR_WIDE_DISTANCE,
			pair, BODY_SHOT_FOV, name + "_wide")

	body.queue_free()
	PauseHub.release(self)
	print("[SHOTS] wrote ", name, " side/quarter/wide at ", spot)


func _capture_from(eye: Vector3, focus: Vector3, fov: float, name: String) -> void:
	"""One frame from a throwaway camera. `_body_camera`'s tail, with the framing
	handed in rather than derived from the hero — the predator shots aim at
	something that is not the player."""
	var cam := Camera3D.new()
	cam.fov = fov
	add_child(cam)
	cam.global_position = eye
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	await _grab(name)
	cam.queue_free()


func _grab(png_name: String) -> void:
	"""Two process frames, a post-draw and a PNG — the four lines every shot in
	this file ends with, and the one place they live."""
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out_dir, png_name])


func _save_frame(name: String, frame: int) -> void:
	"""One numbered frame of a strip — shot 20's four lines, lifted out so the
	idle and air strips below spend them too rather than copying them."""
	await _grab("%s_%d" % [name, frame])


## BEAD godot-test1-5u3.9 — the idle strip's window and its frame count. Three
## seconds is the owner's ask and it is also the shortest window in which the
## driver's two idle terms can both be seen: the breath runs at ~0.25 Hz (one
## cycle in four seconds) and the standing weight shift slower still.
const IDLE_STRIP_SECONDS: float = 3.0
const IDLE_STRIP_FRAMES: int = 6
## ...and the air strip's: rise, apex, fall, land.
const AIR_STRIP_FRAMES: int = 4
## Where in the landing squash the fourth frame is taken — the peak of the
## `sin(progress * PI)` arc `player_controller` drives, i.e. the deepest absorb.
const AIR_STRIP_LAND_PROGRESS: float = 0.5


func _shoot_idle_strip(terrain: Node, player: Node3D, at: Vector3, name: String) -> void:
	"""
	BEAD godot-test1-5u3.9, shot 23. Six frames across three seconds of STANDING
	STILL, through `animate_idle()` — the game's own idle path, stepped at 60 Hz
	the way a real frame would step it, because idle is the one cycle that LERPS:
	sampling it at six clocks without walking it there would show six poses the
	game never draws.

	A hero who is alive while standing still is half of "natural movements" and a
	single frozen frame cannot show it at all.
	"""
	if not _wanted(name):
		return
	if not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)
		player.set_active_character(_hero_index(player))
	var cam := _body_camera(player)
	PauseHub.take(self)
	# Walk the idle in from the rest pose, so frame 0 is a settled stand rather
	# than whatever shot 20 left mid-stride.
	var step: float = 1.0 / 60.0
	player.anim.animation_time = 0.0
	for i in int(1.0 / step):
		player.anim.animation_time += step
		player.anim.animate_idle(step)
	var per_frame: int = int(IDLE_STRIP_SECONDS / step) / IDLE_STRIP_FRAMES
	for frame in IDLE_STRIP_FRAMES:
		for i in per_frame:
			player.anim.animation_time += step
			player.anim.animate_idle(step)
		await _save_frame(name, frame)
	PauseHub.release(self)
	cam.queue_free()
	print("[SHOTS] wrote ", IDLE_STRIP_FRAMES, " frames of ", name, " over ",
			"%.1f s" % IDLE_STRIP_SECONDS, " hero=", _hero)


func _shoot_air_strip(terrain: Node, player: Node3D, at: Vector3, name: String) -> void:
	"""
	BEAD godot-test1-5u3.9, shot 24. Four frames of a jump: three off
	`animate_jumping()` at a quarter, a half and three quarters of one wing-beat,
	then the LANDING — `animate_landing()` with the player's own landing-squash
	state set to the peak of its arc, which is what the skinned driver reads to
	absorb the impact through the knees.

	The landing frame deliberately does NOT run `update_character_animation()`:
	the `Body` dip and the container squash it writes are the CALLER's half of a
	landing and are unchanged by this bead. What the strip has to answer is
	whether the KNEES take the impact, and this is the pose that shows it alone.
	"""
	if not _wanted(name):
		return
	if not _head_pose_settled:
		await _settle_body_pose(terrain, player, at, name)
		player.set_active_character(_hero_index(player))
	var cam := _body_camera(player)
	PauseHub.take(self)
	var beat: float = TAU / 14.0   # `animate_jumping`'s own flap speed
	for frame in AIR_STRIP_FRAMES - 1:
		player.anim.animation_time = beat * (float(frame) + 1.0) / float(AIR_STRIP_FRAMES)
		player.anim.animate_jumping()
		await _save_frame(name, frame)
	# THE LANDING. `land_squash_timer` is the player's own field and the driver
	# reads it through `PlayerAnimation.land_squash_amount()`, so setting it here
	# poses exactly the frame the game draws on touchdown.
	player.land_squash_timer = player.LAND_SQUASH_DURATION * (1.0 - AIR_STRIP_LAND_PROGRESS)
	player.land_squash_strength = 1.0
	player.anim.animate_landing()
	var land_step: float = 1.0 / 60.0
	for i in 6:
		player.anim.animate_idle(land_step)
	await _save_frame(name, AIR_STRIP_FRAMES - 1)
	player.land_squash_timer = 0.0
	PauseHub.release(self)
	cam.queue_free()
	print("[SHOTS] wrote ", AIR_STRIP_FRAMES, " frames of ", name, " hero=", _hero)


func _crown_focus(player: Node3D, scope: Node) -> Vector3:
	"""SPIKE godot-test1-z3e.10. A face-height focus point that needs no node
	origin: the top of every `MeshInstance3D` under `scope`, dropped by the
	distance from a crown to the middle of a face. `scope` is the `Head` node
	when there is one and the whole `Body` otherwise — which since bead
	godot-test1-5u3.3 is every shot of Teibi, whose head is a region of one
	skinned mesh and not a node."""
	var fallback := player.global_position + Vector3(0.0, 1.6, 0.0)
	if scope == null:
		return fallback
	var top_y := -INF
	for m in scope.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		var aabb := mesh.get_aabb()
		for corner_i in 8:
			var corner := Vector3(
					aabb.position.x + float(corner_i & 1) * aabb.size.x,
					aabb.position.y + float((corner_i >> 1) & 1) * aabb.size.y,
					aabb.position.z + float((corner_i >> 2) & 1) * aabb.size.z)
			top_y = maxf(top_y, (mesh.global_transform * corner).y)
	if top_y == -INF:
		return fallback
	return Vector3(player.global_position.x, top_y - CROWN_TO_FACE, player.global_position.z)


func _shoot_head_closeup(terrain: Node, player: Node3D, at: Vector3, fov: float,
		name: String, settle: bool = true,
		distance: float = HEAD_SHOT_DISTANCE, drop: float = 0.0) -> void:
	"""
	SPIKE godot-test1-z3e.1. One shot of the hero's face from `HEAD_SHOT_DISTANCE`.

	It cannot reuse `_shoot`: the rig camera is `$CameraPivot/CameraArm/Camera3D` on
	a SpringArm3D behind the hero at chase distance, and this needs a camera in FRONT
	of the face at two metres. So it does `_shoot`'s own settle / measure / freeze
	sequence and then makes a throwaway Camera3D current for the grab.

	`settle` is false for a SECOND framing of a body that is already posed and already
	frozen: the world is built, nothing is ticking, and only the lens changes. Sixteen
	runs of this spike each paid a 9 s settle and a 300-frame measure for that.

	IT IS A REQUEST, NOT AN ASSERTION, and `_head_pose_settled` is why: `only=` can
	filter out the shot that was supposed to have done the settling, and a false here
	would then photograph the boot pose — a live, unfrozen hero on chunks that have
	not streamed in. So the caller says "reuse if there is anything to reuse" and this
	decides.
	"""
	if not _wanted(name):
		return
	if settle or not _head_pose_settled:
		var chunk := Vector2i(roundi(at.x / 50.0), roundi(at.z / 50.0))
		player.set_physics_process(true)
		player.set_process(true)
		terrain.new_run(SEED, chunk)
		player.global_position = at
		player.rotation.y = 0.0
		player.velocity = Vector3.ZERO
		await get_tree().create_timer(SETTLE_SECONDS, true, false, true).timeout
		player.set_active_character(_hero_index(player))
		await get_tree().create_timer(YAW_SECONDS, true, false, true).timeout
		await _measure(name)
		# Re-assert and freeze, `_shoot`'s reasoning verbatim — both ticks, because
		# the rig is written in `_process` and the body in `_physics_process`.
		player.global_position = at
		player.rotation.y = 0.0
		player.velocity = Vector3.ZERO
		player.visible = true
		var model := player.get_node_or_null("CharacterModel")
		if model is Node3D:
			(model as Node3D).visible = true
		player.set_physics_process(false)
		player.set_process(false)
		if _spike:
			# SPIKE godot-test1-z3e.10, same reason as `_shoot_body`: the settle
			# is a live window and a predator encounter in it leaves the walk
			# cycle frozen mid-gesture. Rest pose, from the animation's own seam.
			player.anim.animation_time = 0.0
			player.anim.animate_walking(1.0 / 60.0, 1.0)
		_head_pose_settled = true
		await get_tree().process_frame

	var hero: Node = player.character_instances[_hero_index(player)]
	var head := hero.get_node_or_null("Body/Head") as Node3D
	var focus: Vector3
	if head != null and not _spike:
		focus = head.global_position
	else:
		# SPIKE godot-test1-z3e.10. A `Head` NODE ORIGIN is only the face's
		# centre for the trimesh heroes, whose head mesh is modelled around it:
		# on the authored body that origin is MakeHuman's own NECK joint, and
		# aiming at it framed the chest with the face against the top edge
		# (measured). `uncut` has no `Head` node at all and a fixed-height guess
		# there framed empty air. One rule fixes both and keeps the three
		# columns of the grid comparable: aim just under the visible CROWN.
		focus = _crown_focus(player, head if head != null else hero.get_node_or_null("Body"))
	var cam := Camera3D.new()
	cam.fov = fov
	add_child(cam)
	# A three-quarter front view: dead-on hides the nose and the ears both, which
	# are the two things this spike is about.
	var basis := player.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	# `drop` (bead godot-test1-394) is the only thing that moves the camera BELOW
	# the eye line; at 0.0 this is byte-for-byte the 16/17 framing it always was.
	cam.global_position = focus + forward * (distance * 0.88) \
			+ right * (distance * 0.42) + Vector3(0.0, 0.10 - drop, 0.0)
	cam.look_at(focus, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out_dir + "/" + name + ".png")
	cam.queue_free()
	print("[SHOTS] wrote ", name, " at ", at)


func _shoot_field_bridge(terrain: Node, player: Node3D) -> void:
	"""
	Photograph the first field bridge on this seed twice: from the bank, and
	standing on the deck with the HUD up.

	The site is a pure function of (station index, run seed) through the road's
	centreline and the river field, so asking the terrain where the bridge is
	costs nothing and lands in the same place every run — the same property the
	landmark shots lean on one table along.
	"""
	# THE FILTER IS CHECKED HERE TOO, `_shoot_landmark`'s reasoning one family along
	# (spike godot-test1-z3e.1): the road growth and the two settles below run
	# BEFORE any `_shoot`, so `only=` on a shot in another family paid ~15 minutes of
	# river search and chunk streaming for two pictures it then threw away.
	if not _wanted("10_field_bridge_bank11_field_bridge_deck"):
		return

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

## The RUNNING field of view (`player_controller.FOV_MAX`). A shadow cascade is
## fitted to the camera sub-frustum, so the widest FOV the player ever holds is
## the worst case for its texel size — and this tool's frozen pose is a STANDING
## one. `web` forces it, so a shadow A/B is judged on the frame the game is
## actually played at rather than the calmest one.
const WEB_SHOT_FOV: float = 97.0

func _emulate_web_settings(terrain: Node) -> void:
	"""
	Make this desktop process render what the WEB EXPORT renders, as far as a
	desktop binary can (bead godot-test1-6n1).

	@param terrain: the EndlessTerrain, for its own web-gated tuning.

	WHY THE `.web` SETTINGS DO NOT ARRIVE ON THEIR OWN: they are FEATURE-TAG
	overrides. `OS.has_feature("web")` is true in a browser and nowhere else, so
	`--rendering-method gl_compatibility` on a desktop binary picks up the web
	RENDERER and none of the web SETTINGS — it still renders at the engine's
	desktop `directional_shadow/size` of 4096, with 4x MSAA and full internal
	resolution. Four times the shadow resolution the web build ships is not a
	detail on a bead about shadows; it is the whole axis.

	WHAT `web` FORCES, ACROSS TWO SITES. Here: the three `.web` keys in
	`project.godot`, and the game's own web-gated tuning (`apply_sun_shadow`).
	In `_shoot`, per shot rather than once: the running FOV (see WEB_SHOT_FOV),
	because `player_controller._process` eases `camera.fov` back toward FOV_BASE
	on every tick of the settle and would undo a write made here.

	Everything else about a browser — the GPU, the driver, the frame budget — a
	desktop capture cannot have, so this is an honest STAND-IN and a `web` shot is
	not a substitute for a real export when the question is performance.
	"""
	RenderingServer.directional_shadow_atlas_set_size(1024, true)   # size.web
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED                 # msaa_3d.web
	get_viewport().scaling_3d_scale = 0.8                           # scale.web
	# (the FOV is re-asserted per shot, in _shoot — `player_controller._process`
	# eases `camera.fov` back to FOV_BASE every frame of the settle, so writing it
	# here would be undone before the first grab.)
	# ...and the runtime half: anything the game itself gates on the web feature
	# tag has to be asked for explicitly here, for exactly the reason above.
	if terrain.has_method("apply_sun_shadow"):
		terrain.apply_sun_shadow(true)
	print("[SHOTS] web emulation: shadow atlas 1024, msaa off, 3d scale 0.8, fov ",
			WEB_SHOT_FOV)

func _shoot(terrain: Node, player: Node3D, where: Vector3, yaw: float, name: String) -> void:
	if not _wanted(name):
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
	# ...and the HUD's pose is re-asserted the same way, for the same bite. A
	# caller that POSES a widget (`_shoot_caption`) is posing something with a
	# live per-frame writer: `player_controller._show_respawn_countdown()` rewrites
	# the respawn label every frame of a real bite and `_hide_respawn_message()`
	# then hides it, so a crocodile arriving during the 9 s settle captured an
	# empty frame — reproduced, and it is a COIN FLIP rather than an error, which
	# is the worst shape for an acceptance tool. It goes here rather than in the
	# caller because it belongs BELOW the freeze on the next two lines: re-posing
	# above them leaves the writer one more tick to undo it.
	player.set_physics_process(false)
	player.set_process(false)
	# The running FOV, asserted AFTER the freeze because player_controller eases
	# `camera.fov` back toward FOV_BASE on every tick — see _emulate_web_settings.
	if _emulate_web:
		var shot_cam := get_viewport().get_camera_3d()
		if shot_cam != null:
			shot_cam.fov = WEB_SHOT_FOV
	if _repose.is_valid():
		_repose.call()
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
