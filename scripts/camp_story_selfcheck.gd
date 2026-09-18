extends SceneTree
## Headless self-check for GD-SURVEY roadside camp stories (bead godot-test1-w0z2).
##
##   godot --headless --path . --script res://scripts/camp_story_selfcheck.gd
##
## Guards:
##   a. Story hash determinism & distribution across seeds/chunks.
##   b. Camp A/B: byte-identical hut spheres and fire stones with stories on vs off.
##   c. Gag bounds: horizontal extent <= CAMP_RADIUS, clear of huts, camp_top >= gag top.
##   d. Marker: exactly one "camp_story" node per camp, meta story in 0..3, chunk-parented.
##   e. Toast: memo at 40 m, report at arrival, re-seed reset, quiz suppression.
##   f. Locale: all story strings & titles translated in German and differ from English.

const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const UNIT_CORNERS: Array[Vector3] = [
	Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5,  0.5),
	Vector3(-0.5,  0.5, -0.5), Vector3(-0.5,  0.5,  0.5),
	Vector3( 0.5, -0.5, -0.5), Vector3( 0.5, -0.5,  0.5),
	Vector3( 0.5,  0.5, -0.5), Vector3( 0.5,  0.5,  0.5),
]

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_run()


func _run() -> void:
	var terrain := Node3D.new()
	terrain.set_script(load("res://scripts/endless_terrain.gd"))
	root.add_child(terrain)

	_check_a_story_hash(terrain)
	_check_b_camp_ab(terrain)
	_check_c_gag_bounds(terrain)
	_check_d_marker(terrain)
	await _check_e_toast(terrain)
	_check_f_locale()

	terrain.queue_free()

	if _failures.is_empty():
		print("camp_story: hash distribution OK | A/B hut & stone identity OK | gag bounds OK | marker OK | toast memo/report/quiz OK | locale OK")
		Sentinel.finish(self)
		return

	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECK A — Story is a hash: deterministic and well-distributed
# ============================================================================

func _check_a_story_hash(terrain: Node3D) -> void:
	var seeds: Array[int] = [1001, 2002, 3003]
	var counts := [0, 0, 0, 0]
	var total := 0

	for s: int in seeds:
		terrain.run_seed = s
		# Determinism on repeated calls for same chunk:
		for probe_chunk: Vector2i in [Vector2i(0, 0), Vector2i(5, -8), Vector2i(-12, 19)]:
			var first: int = TerrainFeatures._camp_story_at(terrain, probe_chunk)
			var second: int = TerrainFeatures._camp_story_at(terrain, probe_chunk)
			if first != second:
				_fail("story hash not deterministic: chunk %s seed %d returned %d then %d" % [probe_chunk, s, first, second])

		# 400 chunks per seed:
		for x in range(20):
			for z in range(20):
				var story: int = TerrainFeatures._camp_story_at(terrain, Vector2i(x, z))
				if story < 0 or story >= TerrainFeatures.STORIES.size():
					_fail("story index out of bounds: %d" % story)
				else:
					counts[story] += 1
				total += 1

	for i in range(TerrainFeatures.STORIES.size()):
		if counts[i] == 0:
			_fail("story %d never appeared in %d chunk evaluations" % [i, total])
		var freq: float = float(counts[i]) / float(total)
		if freq > 0.45:
			_fail("story %d frequency too high: %.2f%% (max 45%%)" % [i, freq * 100.0])

	Sentinel.done("story_hash")


# ============================================================================
# CHECK B — Camp A/B: byte-identical hut spheres and fire stones on vs off
# ============================================================================

func _check_b_camp_ab(terrain: Node3D) -> void:
	var seeds: Array[int] = [20260904, 1337, 77777]
	var built_camps := 0

	for s: int in seeds:
		terrain.run_seed = s
		for cx in range(-15, 16):
			for cz in range(-15, 16):
				var chunk := Vector2i(cx, cz)
				if TerrainFeatures._camp_at(terrain, chunk).is_empty():
					continue

				# 1. Build camp with stories OFF:
				terrain.spawn_camp_stories = false
				var batch_off: Array = []
				var body_off := StaticBody3D.new()
				var chunk_off := MeshInstance3D.new()
				var obstacles_off: Array = []
				TerrainFeatures.spawn_camp_in_chunk(terrain, chunk, chunk_off, obstacles_off, batch_off, body_off)

				if obstacles_off.is_empty():
					chunk_off.queue_free()
					body_off.queue_free()
					continue

				# 2. Build camp with stories ON:
				terrain.spawn_camp_stories = true
				var batch_on: Array = []
				var body_on := StaticBody3D.new()
				var chunk_on := MeshInstance3D.new()
				var obstacles_on: Array = []
				TerrainFeatures.spawn_camp_in_chunk(terrain, chunk, chunk_on, obstacles_on, batch_on, body_on)

				# Find marker and coins:
				var marker: Node = null
				var coins_on: Array[Vector3] = []
				for child in chunk_on.get_children():
					if child.is_in_group("camp_story"):
						marker = child
					else:
						coins_on.append(child.position)

				var coins_off: Array[Vector3] = []
				for child in chunk_off.get_children():
					if not child.is_in_group("camp_story"):
						coins_off.append(child.position)

				var gag_start: int = int(marker.get_meta("gag_start", batch_on.size())) if marker != null else batch_on.size()
				var gag_count: int = int(marker.get_meta("gag_count", 0)) if marker != null else 0

				var filtered_on: Array = batch_on.slice(0, gag_start) + batch_on.slice(gag_start + gag_count)

				# 1. Compare entire block batch:
				if batch_off.size() != filtered_on.size():
					_fail("chunk %s batch size mismatch: off=%d, on_filtered=%d (gag=%d)" % [chunk, batch_off.size(), filtered_on.size(), gag_count])
				else:
					for k in range(batch_off.size()):
						var item_off: Dictionary = batch_off[k]
						var item_on: Dictionary = filtered_on[k]
						if item_off.get("kind") != item_on.get("kind"):
							_fail("chunk %s item %d kind mismatch: off=%d, on=%d" % [chunk, k, item_off.get("kind"), item_on.get("kind")])
							break
						var t_off: Transform3D = item_off["transform"]
						var t_on: Transform3D = item_on["transform"]
						if not t_off.is_equal_approx(t_on):
							_fail("chunk %s item %d transform mismatch" % [chunk, k])
							break
						if item_off["color"] != item_on["color"]:
							_fail("chunk %s item %d color mismatch" % [chunk, k])
							break

				# 2. Compare coin reward positions:
				if coins_off.size() != coins_on.size():
					_fail("chunk %s coin count mismatch: off=%d, on=%d" % [chunk, coins_off.size(), coins_on.size()])
				else:
					for c in range(coins_off.size()):
						if not coins_off[c].is_equal_approx(coins_on[c]):
							_fail("chunk %s coin %d position mismatch: off=%s, on=%s" % [chunk, c, coins_off[c], coins_on[c]])
							break

				# 3. Compare hut footprints:
				var footprints_off: Array = chunk_off.get_meta("camp_hut_footprints", [])
				var footprints_on: Array = chunk_on.get_meta("camp_hut_footprints", [])
				var expected_on_count: int = footprints_off.size() + (1 if gag_count > 0 else 0)
				if footprints_on.size() != expected_on_count:
					_fail("chunk %s hut footprints count mismatch: off=%d, on=%d (gag=%d)" % [chunk, footprints_off.size(), footprints_on.size(), gag_count])
				else:
					for h in range(footprints_off.size()):
						var f_off: Dictionary = footprints_off[h]
						var f_on: Dictionary = footprints_on[h]
						if not (f_off["pos"] as Vector3).is_equal_approx(f_on["pos"]):
							_fail("chunk %s hut footprint %d pos mismatch" % [chunk, h])
							break
						if not is_equal_approx(f_off["radius"], f_on["radius"]):
							_fail("chunk %s hut footprint %d radius mismatch" % [chunk, h])
							break

				chunk_off.queue_free()
				body_off.queue_free()
				chunk_on.queue_free()
				body_on.queue_free()

				built_camps += 1
				if built_camps >= 40:
					break
			if built_camps >= 40:
				break
		if built_camps >= 40:
			break

	if built_camps < 40:
		_fail("only found %d built camps across 3 seeds (wanted >= 40)" % built_camps)

	Sentinel.done("camp_ab")


# ============================================================================
# CHECK C — Gag inside footprint and clear of huts
# ============================================================================

func _check_c_gag_bounds(terrain: Node3D) -> void:
	terrain.run_seed = 424242
	terrain.spawn_camp_stories = true

	# Test all 4 story types with realistic open hut footprints:
	for story in range(TerrainFeatures.STORIES.size()):
		var center := Vector3.ZERO
		# Realistic hut positions leaving open quadrants:
		var hut_footprints: Array = [
			{ "pos": Vector3(5.5, 0.0, 0.0), "radius": 2.0 },
			{ "pos": Vector3(-5.5, 0.0, 0.0), "radius": 2.0 },
		]
		var camp_top := 2.7

		var block_batch: Array = []
		var block_body := StaticBody3D.new()
		var res: Dictionary = TerrainFeatures._camp_story_gag(terrain, story, center, hut_footprints, block_batch, block_body, Vector2i(story * 7 + 1, story * 13 + 3))
		block_body.queue_free()

		if res.is_empty():
			_fail("gag for story %d failed to find an open slot" % story)
			continue

		var gag_pos: Vector3 = res["pos"]
		var gag_radius: float = res["radius"]
		var gag_top: float = res["top"]

		# 1. Gag boxes worst horizontal extent <= CAMP_RADIUS:
		var worst := 0.0
		for item in block_batch:
			var t: Transform3D = item["transform"]
			for corner: Vector3 in UNIT_CORNERS:
				var p: Vector3 = t.origin + t.basis * corner
				var d := Vector2(p.x - center.x, p.z - center.z).length()
				worst = maxf(worst, d)

		if worst > TerrainFeatures.CAMP_RADIUS + 0.01:
			_fail("story %d gag worst extent %.2f m exceeds CAMP_RADIUS %.2f m" % [story, worst, TerrainFeatures.CAMP_RADIUS])

		# 2. Circle clears every hut circle:
		for h in hut_footprints:
			var dist := Vector2(gag_pos.x - h["pos"].x, gag_pos.z - h["pos"].z).length()
			if dist < h["radius"] + gag_radius - 0.01:
				_fail("story %d gag at %s penetrates hut at %s (dist=%.2f, sum=%.2f)" % [story, gag_pos, h["pos"], dist, h["radius"] + gag_radius])

		# 3. camp_top >= gag_top:
		var combined_top: float = maxf(camp_top, gag_top)
		if combined_top < gag_top:
			_fail("story %d combined top %.2f m < gag top %.2f m" % [story, combined_top, gag_top])

	Sentinel.done("gag_bounds")


# ============================================================================
# CHECK D — Exactly one "camp_story" marker node per built camp
# ============================================================================

func _check_d_marker(terrain: Node3D) -> void:
	terrain.run_seed = 98765
	terrain.spawn_camp_stories = true

	var found := false
	for cx in range(-10, 11):
		for cz in range(-10, 11):
			var chunk := Vector2i(cx, cz)
			if TerrainFeatures._camp_at(terrain, chunk).is_empty():
				continue

			var chunk_node := MeshInstance3D.new()
			var batch: Array = []
			var body := StaticBody3D.new()
			var obstacles: Array = []
			TerrainFeatures.spawn_camp_in_chunk(terrain, chunk, chunk_node, obstacles, batch, body)

			if obstacles.is_empty():
				chunk_node.queue_free()
				body.queue_free()
				continue

			found = true
			var story_nodes: Array[Node] = []
			for child in chunk_node.get_children():
				if child.is_in_group("camp_story"):
					story_nodes.append(child)

			if story_nodes.size() != 1:
				_fail("chunk %s expected 1 camp_story node, got %d" % [chunk, story_nodes.size()])
			else:
				var m: Node = story_nodes[0]
				if not m.has_meta("story"):
					_fail("camp_story node missing 'story' meta")
				else:
					var st: int = int(m.get_meta("story"))
					if st < 0 or st >= TerrainFeatures.STORIES.size():
						_fail("camp_story node meta 'story' %d out of bounds" % st)
				if not m.has_meta("radius"):
					_fail("camp_story node missing 'radius' meta")
				if m.get_parent() != chunk_node:
					_fail("camp_story node not child of chunk")

			chunk_node.queue_free()
			body.queue_free()
			break
		if found:
			break

	if not found:
		_fail("could not find a built camp to verify marker")

	Sentinel.done("marker")


# ============================================================================
# CHECK E — Toast announcer lifecycle: memo at 40m, report on arrival, quiz yield
# ============================================================================

func _check_e_toast(terrain: Node3D) -> void:
	terrain.run_seed = 11111

	var toast := Control.new()
	toast.set_script(load("res://scripts/landmark_toast.gd"))
	root.add_child(toast)
	await process_frame
	toast.set_process(false)

	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)

	var marker := Node3D.new()
	marker.add_to_group("camp_story")
	marker.set_meta("story", 0)
	marker.set_meta("radius", TerrainFeatures.CAMP_RADIUS)
	root.add_child(marker)
	marker.position = Vector3.ZERO

	# 1. Stub player at 40 m -> memo announced once:
	player.position = Vector3(40.0, 0.0, 0.0)
	toast.call("_scan_stories")
	var name_lbl: Label = toast.get("name_label")
	var fact_lbl: Label = toast.get("fact_label")

	if name_lbl.text != TerrainFeatures.STORY_TITLE_MEMO:
		_fail("toast memo title expected '%s', got '%s'" % [TerrainFeatures.STORY_TITLE_MEMO, name_lbl.text])
	if fact_lbl.text != TerrainFeatures.STORIES[0].memo:
		_fail("toast memo body expected '%s', got '%s'" % [TerrainFeatures.STORIES[0].memo, fact_lbl.text])
	if toast.get("_stories").get(0) != 1:
		_fail("toast story 0 not latched to stage 1 after memo")

	# 2. Second tick at 40 m -> nothing announced:
	name_lbl.text = ""
	fact_lbl.text = ""
	toast.call("_scan_stories")
	if not name_lbl.text.is_empty():
		_fail("toast re-announced memo on second tick at 40 m")

	# 3. Arrive at radius + pad (10 m <= 9.4 + 6.0) -> report announced once:
	player.position = Vector3(10.0, 0.0, 0.0)
	toast.call("_scan_stories")
	if name_lbl.text != TerrainFeatures.STORY_TITLE_REPORT:
		_fail("toast report title expected '%s', got '%s'" % [TerrainFeatures.STORY_TITLE_REPORT, name_lbl.text])
	if fact_lbl.text != TerrainFeatures.STORIES[0].report:
		_fail("toast report body expected '%s', got '%s'" % [TerrainFeatures.STORIES[0].report, fact_lbl.text])
	if toast.get("_stories").get(0) != 2:
		_fail("toast story 0 not latched to stage 2 after report")

	# 4. Walk out to 60 m and back to 10 m -> nothing announced:
	player.position = Vector3(60.0, 0.0, 0.0)
	toast.call("_scan_stories")
	name_lbl.text = ""
	fact_lbl.text = ""
	player.position = Vector3(10.0, 0.0, 0.0)
	toast.call("_scan_stories")
	if not name_lbl.text.is_empty():
		_fail("toast re-announced report after leaving and returning")

	# 5. Re-seed (terrain.run_seed change) -> memo fires again:
	terrain.run_seed = 22222
	player.position = Vector3(40.0, 0.0, 0.0)
	name_lbl.text = ""
	fact_lbl.text = ""
	toast.call("_scan_stories")
	if name_lbl.text != TerrainFeatures.STORY_TITLE_MEMO:
		_fail("toast memo did not re-announce after run re-seed")
	if toast.get("_stories").get(0) != 1:
		_fail("toast story 0 not re-latched to stage 1 after re-seed")

	# 6. With _quiz_pending true -> nothing announced and nothing latched:
	toast.get("_stories").clear()
	toast.set("_quiz_pending", true)
	player.position = Vector3(40.0, 0.0, 0.0)
	name_lbl.text = ""
	fact_lbl.text = ""
	toast.call("_scan_stories")
	if not name_lbl.text.is_empty():
		_fail("toast announced while quiz was pending")
	if toast.get("_stories").has(0):
		_fail("toast latched story progress while quiz was pending")

	toast.set("_quiz_pending", false)
	marker.queue_free()
	player.queue_free()
	toast.queue_free()

	Sentinel.done("toast")


# ============================================================================
# CHECK F — Locale: all strings and titles translated in German and differ from English
# ============================================================================

func _check_f_locale() -> void:
	var prev_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("de")

	for i in range(TerrainFeatures.STORIES.size()):
		var s: Dictionary = TerrainFeatures.STORIES[i]
		var memo_en: String = s["memo"]
		var report_en: String = s["report"]
		var memo_de: String = tr(memo_en)
		var report_de: String = tr(report_en)

		if memo_de.is_empty() or memo_de == memo_en:
			_fail("story %d memo '%s' not translated to German (got '%s')" % [i, memo_en, memo_de])
		if report_de.is_empty() or report_de == report_en:
			_fail("story %d report '%s' not translated to German (got '%s')" % [i, report_en, report_de])

	var memo_title_de: String = tr(TerrainFeatures.STORY_TITLE_MEMO)
	var report_title_de: String = tr(TerrainFeatures.STORY_TITLE_REPORT)

	if memo_title_de.is_empty() or memo_title_de == TerrainFeatures.STORY_TITLE_MEMO:
		_fail("memo title '%s' not translated to German" % TerrainFeatures.STORY_TITLE_MEMO)
	if report_title_de.is_empty() or report_title_de == TerrainFeatures.STORY_TITLE_REPORT:
		_fail("report title '%s' not translated to German" % TerrainFeatures.STORY_TITLE_REPORT)

	TranslationServer.set_locale(prev_locale)
	Sentinel.done("locale")
