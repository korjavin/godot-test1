extends SceneTree
## THROWAWAY measurement sweep for the CITY band (godot-test1-jb7.3).
## Runs the SAME field through the baseline terrain script (origin/master, copied
## to scripts/_baseline_terrain.gd) and this branch's, and reports:
##   * byte-identity on every chunk the retune did NOT reclassify
##   * per-chunk instance / collision / draw-call shape
##   * within-run purity on this branch (same field twice)
##   * crocodile counts, split by band (the city thinning)
## Not shipped — deleted before the PR.
##   godot --headless --path . --script res://scripts/_sweep_city.gd

const NEW_SCRIPT: String = "res://scripts/endless_terrain.gd"
const OLD_SCRIPT: String = "res://scripts/_baseline_terrain.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

const SEEDS: Array[int] = [20260826, 991, 4242, 70707]
const HALF_FIELD: int = 8           # (2*HALF+1)^2 chunks per seed
const CROC_SEEDS: Array[int] = [20260826, 991]
const CROC_HALF_FIELD: int = 4

## Chunk sample grid used to decide "did the retune touch this chunk at all?".
const SAMPLES: int = 5


func _initialize() -> void:
	_geometry_sweep()
	_croc_sweep()
	quit(0)


func _make_terrain(path: String, seed_value: int, crocs: bool) -> Node3D:
	var t := Node3D.new()
	t.set_script(load(path))
	# DETACHED — never added to the tree, the landmark/prop selfcheck pattern.
	# _ready() would roll its own seed and build a whole field before we could set
	# ours; create_chunk's add_child works fine on a node outside the tree.
	t.set("spawn_crocodiles", crocs)
	t.set("coin_scene", load(COIN_SCENE))
	if crocs:
		t.set("crocodile_scene", load(CROC_SCENE))
	t.call("set_run_seed", seed_value)
	return t


func _digest(chunk: Node) -> Array:
	"""Order-stable digest of one chunk. NEVER hashes node names — Godot
	auto-names duplicate siblings off a global counter, so two runs of the
	identical world produce different names for identical geometry."""
	var boxes: Array = []
	var shapes: Array = []
	var coins: Array = []
	var crocs: Array = []
	var mm := 0
	for child in chunk.get_children():
		if child is MultiMeshInstance3D:
			mm += 1
			var m: MultiMesh = (child as MultiMeshInstance3D).multimesh
			for i in m.instance_count:
				boxes.append([m.get_instance_transform(i), m.get_instance_color(i)])
		elif child is StaticBody3D:
			for sh in child.get_children():
				if sh is CollisionShape3D:
					var cs := sh as CollisionShape3D
					var size := Vector3.ZERO
					if cs.shape is BoxShape3D:
						size = (cs.shape as BoxShape3D).size
					shapes.append([cs.transform, size])
		elif child is Area3D:
			coins.append(child.position)
		elif child is CharacterBody3D:
			crocs.append(child.position)
	return [boxes, shapes, coins, crocs, mm]


func _geometry_sweep() -> void:
	var identical := 0
	var reclassified := 0
	var differ_unaffected := 0
	var boxes_old := 0
	var boxes_new := 0
	var shapes_old := 0
	var shapes_new := 0
	var coins_old := 0
	var coins_new := 0
	var chunks := 0
	var mm_max := 0
	var pure_ok := 0
	var pure_bad := 0
	var city_chunks := 0
	var city_boxes := 0
	var city_shapes := 0
	var forest_chunks := 0
	var forest_boxes := 0
	var forest_shapes := 0
	var box_max := 0

	for seed_value in SEEDS:
		var old_t := _make_terrain(OLD_SCRIPT, seed_value, false)
		var new_t := _make_terrain(NEW_SCRIPT, seed_value, false)
		var new2_t := _make_terrain(NEW_SCRIPT, seed_value, false)
		var chunk_size: float = float(new_t.get("chunk_size"))
		var city_value: int = int(load(NEW_SCRIPT).get_script_constant_map()["Biome"]["CITY"])
		var forest_value: int = int(load(NEW_SCRIPT).get_script_constant_map()["Biome"]["FOREST"])

		for cx in range(-HALF_FIELD, HALF_FIELD + 1):
			for cz in range(-HALF_FIELD, HALF_FIELD + 1):
				var pos := Vector2i(cx, cz)
				var centre: Vector3 = new_t.call("chunk_to_world", pos)
				chunks += 1

				# Did the retune touch anything this chunk asks about? Sample a
				# grid: the prop dispatch and the content builders both ask
				# biome_at at their OWN positions, not only at the centre.
				var touched := false
				for ix in SAMPLES:
					for iz in SAMPLES:
						var wx: float = centre.x + (float(ix) / float(SAMPLES - 1) - 0.5) * chunk_size
						var wz: float = centre.z + (float(iz) / float(SAMPLES - 1) - 0.5) * chunk_size
						if int(old_t.call("biome_at", wx, wz)) != int(new_t.call("biome_at", wx, wz)):
							touched = true
				old_t.call("create_chunk", pos)
				new_t.call("create_chunk", pos)
				new2_t.call("create_chunk", pos)

				var d_old: Array = _digest(old_t.get("active_chunks")[pos])
				var d_new: Array = _digest(new_t.get("active_chunks")[pos])
				var d_new2: Array = _digest(new2_t.get("active_chunks")[pos])

				boxes_old += d_old[0].size()
				boxes_new += d_new[0].size()
				shapes_old += d_old[1].size()
				shapes_new += d_new[1].size()
				coins_old += d_old[2].size()
				coins_new += d_new[2].size()
				mm_max = maxi(mm_max, int(d_new[4]))
				box_max = maxi(box_max, d_new[0].size())

				if d_new == d_new2:
					pure_ok += 1
				else:
					pure_bad += 1

				var band: int = int(new_t.call("biome_at", centre.x, centre.z))
				if band == city_value:
					city_chunks += 1
					city_boxes += d_new[0].size()
					city_shapes += d_new[1].size()
				elif band == forest_value:
					forest_chunks += 1
					forest_boxes += d_new[0].size()
					forest_shapes += d_new[1].size()

				if touched:
					reclassified += 1
				elif d_old == d_new:
					identical += 1
				else:
					differ_unaffected += 1

		old_t.free()
		new_t.free()
		new2_t.free()

	print("=== GEOMETRY, %d chunks over %d seeds ===" % [chunks, SEEDS.size()])
	print("  reclassified by the retune : %d (%.1f%%)" % [reclassified, 100.0 * reclassified / chunks])
	print("  untouched AND byte-identical: %d" % identical)
	print("  untouched BUT DIFFERENT     : %d   <-- must be 0" % differ_unaffected)
	print("  within-run purity           : %d identical / %d differing  <-- differing must be 0" % [pure_ok, pure_bad])
	print("  boxes/chunk    %.1f -> %.1f (max %d)" % [float(boxes_old) / chunks, float(boxes_new) / chunks, box_max])
	print("  colliders/chunk %.1f -> %.1f" % [float(shapes_old) / chunks, float(shapes_new) / chunks])
	print("  coins total     %d -> %d" % [coins_old, coins_new])
	print("  MultiMesh instances per chunk, max: %d   <-- must be 1" % mm_max)
	if city_chunks > 0:
		print("  CITY   chunks %d: %.1f boxes, %.1f colliders each" % [city_chunks, float(city_boxes) / city_chunks, float(city_shapes) / city_chunks])
	if forest_chunks > 0:
		print("  FOREST chunks %d: %.1f boxes, %.1f colliders each" % [forest_chunks, float(forest_boxes) / forest_chunks, float(forest_shapes) / forest_chunks])


func _croc_sweep() -> void:
	var by_band_new: Dictionary = {}
	var by_band_count: Dictionary = {}
	var total_old := 0
	var total_new := 0
	var chunks := 0

	for seed_value in CROC_SEEDS:
		var old_t := _make_terrain(OLD_SCRIPT, seed_value, true)
		var new_t := _make_terrain(NEW_SCRIPT, seed_value, true)
		for cx in range(-CROC_HALF_FIELD, CROC_HALF_FIELD + 1):
			for cz in range(-CROC_HALF_FIELD, CROC_HALF_FIELD + 1):
				var pos := Vector2i(cx, cz)
				chunks += 1
				old_t.call("create_chunk", pos)
				new_t.call("create_chunk", pos)
				var n_old: int = _digest(old_t.get("active_chunks")[pos])[3].size()
				var n_new: int = _digest(new_t.get("active_chunks")[pos])[3].size()
				total_old += n_old
				total_new += n_new
				var centre: Vector3 = new_t.call("chunk_to_world", pos)
				var band: int = int(new_t.call("biome_at", centre.x, centre.z))
				by_band_new[band] = float(by_band_new.get(band, 0.0)) + float(n_new)
				by_band_count[band] = int(by_band_count.get(band, 0)) + 1
		old_t.free()
		new_t.free()

	print("")
	print("=== CROCODILES, %d chunks over %d seeds ===" % [chunks, CROC_SEEDS.size()])
	print("  total %d -> %d" % [total_old, total_new])
	var names: Dictionary = load(NEW_SCRIPT).get_script_constant_map()["Biome"]
	for band_name_variant: Variant in names.keys():
		var band_name: String = String(band_name_variant)
		var v: int = int(names[band_name])
		if by_band_count.has(v):
			print("  %-9s %d chunks, %.2f crocs/chunk" % [band_name, by_band_count[v], float(by_band_new[v]) / float(by_band_count[v])])
