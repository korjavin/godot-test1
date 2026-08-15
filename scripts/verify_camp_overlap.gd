extends SceneTree

# Throwaway verification: build many camps and count interpenetrating SOLID pairs.
# Reads the collision shapes create_box actually emitted into the chunk's
# BlockCollision body — i.e. huts + crates + posts, everything the player can bump.
# A hut's 2-3 tiers are stacked at the SAME xz, so tiers are grouped back into one
# hut first; the comparison is then hut/crate/post against each other.
#
# The bound is exact, not heuristic: _camp_spot_clear tests half-DIAGONAL circles
# (s * 0.71 for a prop, base_width * 0.71 + 0.3 for a hut) and create_box emits
# exactly those boxes at exactly those positions — so after the fix, no two
# half-diagonal circles may overlap at all. Expected result: 0.

func _init() -> void:
	var terrain_script := load("res://scripts/endless_terrain.gd")
	var terrain = terrain_script.new()
	terrain.run_seed = 12345

	var camps := 0
	var bad_camps := 0
	var solids_total := 0

	for i in range(4000):
		var chunk_pos := Vector2i(i % 200, i / 200)
		if terrain._camp_at(chunk_pos).is_empty():
			continue

		var mesh := MeshInstance3D.new()
		var body := StaticBody3D.new()
		var batch: Array = []
		var obstacles: Array = []
		terrain.spawn_camp_in_chunk(chunk_pos, mesh, obstacles, batch, body)
		if body.get_child_count() == 0:
			mesh.free()
			body.free()
			continue
		camps += 1

		# Group the emitted boxes into solids by xz centre (hut tiers are concentric),
		# each as an xz circle of the widest tier's half-diagonal.
		var by_xz: Dictionary = {}
		for child in body.get_children():
			var shape: BoxShape3D = child.shape
			var s: Vector3 = shape.size
			var key := "%.3f,%.3f" % [child.position.x, child.position.z]
			var r := Vector2(s.x, s.z).length() / 2.0
			if by_xz.has(key):
				by_xz[key].r = maxf(by_xz[key].r, r)
			else:
				by_xz[key] = { "pos": Vector2(child.position.x, child.position.z), "r": r }

		var circles: Array = by_xz.values()
		solids_total += circles.size()

		for a in range(circles.size()):
			var hit := false
			for b in range(a + 1, circles.size()):
				var ca = circles[a]
				var cb = circles[b]
				if ca.pos.distance_to(cb.pos) < ca.r + cb.r:
					hit = true
					break
			if hit:
				bad_camps += 1
				break

		mesh.free()
		body.free()

	print("camps built: %d, solids: %d, camps with an interpenetrating pair: %d (%.1f%%)"
		% [camps, solids_total, bad_camps, 100.0 * float(bad_camps) / maxf(1.0, float(camps))])
	terrain.free()
	quit()
