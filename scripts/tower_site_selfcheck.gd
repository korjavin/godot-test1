extends SceneTree
## Headless self-check: THE TOWER HAS ONE SITE AND NOTHING ELSE STANDS ON IT.
##
##   godot --headless --path . --script res://scripts/tower_site_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the same
## shape as chunk_stream_selfcheck.gd / enemy_spawn_selfcheck.gd, and it exists for
## the same reason those do: every way of breaking this looks like ordinary scenery
## from the outside.
##
## WHAT IT GUARDS (bead godot-test1-3iy.1, the tower epic's keystone). The whole
## epic parents to one position — shell, horizon impostor, minimap marker, door,
## interior — and phase 1 is only the two promises that position makes:
##
##   1. IT IS THE SAME POSITION EVERY TIME. tower_site() is pure in (run_seed,
##      tower_site_distance) and consumes no RNG draw. If it ever drifted, two
##      multiplayer peers walking the same seed would walk to two different towers,
##      and a revisited site would move under a building already standing on it.
##      Checks 1 and 2.
##   2. THE SITE IS DRY, AND IT IS EMPTY. is_river_at() ignores Y by contract and
##      the player's wade test is XZ-only, so a tower over a river band would wade
##      on every floor; and a mountain massif, a nomad camp or a 6x boss standing
##      in the lobby is the same bug with a different silhouette. Checks 3 and 4.
##
## And the invariant the exclusion is not allowed to cost:
##
##   3. THE REST OF THE WORLD IS UNTOUCHED. Every rejection is a post-draw skip, so
##      chunks that do not meet the disc must come out byte-identical whether the
##      tower is at 400 m or a hundred kilometres away. Check 5 — with check 6 as
##      its negative control, because "identical everywhere" is also what a
##      completely inert feature looks like.
##
## Deliberately NOT covered: the COIN ROAD, which is excluded from the exclusion on
## purpose (cutting a hole in the coin trail would break "follow the coins" — see
## TOWER_RADIUS). Check 4 therefore ignores coins, and reports the road's measured
## distance from the site as information for the phase-2 shell rather than as an
## assertion.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches. They are not a
## failure — same note as enemy_spawn_selfcheck.gd's header.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

## Seed sample. Small on purpose: every check here is about a fixed disc in a
## world whose only per-seed input is the river field, so seeds buy VARIETY OF
## RIVER, not statistical power — five different river fields is plenty to catch a
## nudge that does not nudge, and the field generation each one costs is the
## expensive part of this file.
const SEEDS: Array[int] = [20260827, 1, 424242, 999983, -775511]

## The seed the two expensive whole-field checks (4, 5, 6) run on. One is enough:
## they are about the GENERATOR, not about a particular world.
const FIELD_SEED: int = 20260827

## Where to put the tower for the "feature off" leg of the A/B. Far enough that its
## disc cannot touch any chunk either leg generates, so the two runs differ in
## nothing but whether the exclusion has anything to say.
const TOWER_FAR_AWAY: float = 100000.0

var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING, for the reason enemy_spawn_selfcheck.gd gives: a
	# node added to `root` from inside _initialize() is not `is_inside_tree()` until
	# the first frame, so anything reading a global transform measures a detached
	# world.
	await process_frame
	_run()


func _run() -> void:
	_check_site_is_stable_and_pure()
	_check_site_is_the_same_in_a_second_terrain()
	_check_footprint_is_dry()
	_check_nothing_stands_on_the_site()
	_check_the_rest_of_the_world_is_byte_identical()
	_report()


# ============================================================================
# CHECKS
# ============================================================================

func _check_site_is_stable_and_pure() -> void:
	"""
	Check 1. Repeated calls answer the same thing, the memo is not lying about it,
	and the site is where the ruling says it is.

	The memo is checked by INVALIDATING IT and re-deriving: a cache that has drifted
	from the function it caches would agree with itself forever and be wrong. This
	is the closest a single process can get to "the same across repeated headless
	runs" — check 2 covers the other half by building a second world from scratch.
	"""
	for seed_value: int in SEEDS:
		var terrain := _make_terrain(seed_value)
		var first: Vector3 = terrain.tower_site()
		if terrain.tower_site() != first:
			_fail("seed %d: tower_site() answered twice and differed — it is not pure" % seed_value)
		# Blow the memo away (the sentinel the field itself documents) and re-derive.
		terrain._tower_site_dist = -1.0
		var recomputed: Vector3 = terrain.tower_site()
		if recomputed != first:
			_fail("seed %d: tower_site() re-derived to %s but the memo held %s — the cache is stale" % [
				seed_value, recomputed, first])

		if not is_zero_approx(first.y):
			_fail("seed %d: tower site is off the ground at y=%f — the world is flat" % [seed_value, first.y])
		if first.x > 0.0:
			_fail("seed %d: tower site landed at x=%f — the ruling puts it on -X" % [seed_value, first.x])

		# The nudge may move the site, but only within the lattice it is allowed to
		# scan. Anything further means the scan is not bounded the way it claims.
		var reach: float = terrain.TOWER_NUDGE_STEP * float(terrain.TOWER_NUDGE_RINGS)
		var nominal := Vector3(-terrain.tower_site_distance, 0.0, 0.0)
		if absf(first.x - nominal.x) > reach + 0.001 or absf(first.z) > reach + 0.001:
			_fail("seed %d: tower site %s is outside the %.0f m nudge lattice around %s" % [
				seed_value, first, reach, nominal])

		# The two fixed discs in the world may never touch (see SPAWN_SAFE_RADIUS).
		var from_origin := Vector2(first.x, first.z).length()
		if from_origin < terrain.SPAWN_SAFE_RADIUS + terrain.TOWER_RADIUS:
			_fail("seed %d: tower site is %.1f m from spawn — the spawn bubble and the tower disc overlap" % [
				seed_value, from_origin])
		terrain.free()


func _check_site_is_the_same_in_a_second_terrain() -> void:
	"""
	Check 2. A second world built from scratch on the same seed puts the tower in
	the same place — the property multiplayer rests on (every peer is handed the
	seed and nothing else, and they must all walk to the same building).
	"""
	for seed_value: int in SEEDS:
		var a := _make_terrain(seed_value)
		var b := _make_terrain(seed_value)
		if a.tower_site() != b.tower_site():
			_fail("seed %d: two terrains on the same seed sited the tower at %s and %s" % [
				seed_value, a.tower_site(), b.tower_site()])
		a.free()
		b.free()

	# ...and different seeds must be allowed to differ, or the nudge is inert.
	var sites := {}
	for seed_value: int in SEEDS:
		var t := _make_terrain(seed_value)
		sites[t.tower_site()] = true
		t.free()
	if sites.size() == 1:
		print("NOTE: every sampled seed sited the tower identically — the nominal site was dry in all %d" % SEEDS.size())


func _check_footprint_is_dry() -> void:
	"""
	Check 3. THE WHOLE footprint disc is out of the water, not just its centre.

	Re-measured here with the terrain's own sampler, then again independently on a
	finer grid: a bug that made the sampler blind (too coarse a step, a rim-only
	scan) would satisfy the terrain's own test and still put the tower in a river.
	"""
	for seed_value: int in SEEDS:
		var terrain := _make_terrain(seed_value)
		var site: Vector3 = terrain.tower_site()
		if terrain._tower_wet_samples(site.x, site.z) != 0:
			_fail("seed %d: the site the scan chose is wet by its own sampler" % seed_value)

		# Independent, finer sweep — 2 m, well under the ~8 m band width.
		var wet := 0
		var r: float = terrain.TOWER_RADIUS
		var step := 2.0
		var i := -r
		while i <= r + 0.001:
			var j := -r
			while j <= r + 0.001:
				if Vector2(i, j).length() <= r and terrain.is_river_at(Vector3(site.x + i, 0.0, site.z + j)):
					wet += 1
				j += step
			i += step
		if wet > 0:
			_fail("seed %d: tower footprint at %s has %d wet points on a 2 m grid — the tower would wade" % [
				seed_value, site, wet])
		terrain.free()


func _check_nothing_stands_on_the_site() -> void:
	"""
	Check 4. Generate every chunk the disc reaches and assert the site came out
	empty: no crocodile, no boss, no block, no prop, no camp, no artifact, no chest,
	no landmark, no biome geometry.

	Measured off the FINISHED WORLD rather than off the spawners' own opinions —
	every node in those chunks and every instance in their block MultiMeshes, in
	world space. A spawner nobody remembered to gate is exactly the failure this
	catches, and it catches it without knowing the spawner exists.

	Coins are excluded by design (see the header) and are the one thing skipped.
	"""
	var terrain := _make_terrain(FIELD_SEED)
	var site: Vector3 = terrain.tower_site()
	var radius: float = terrain.TOWER_RADIUS

	var closest := INF
	var offender := ""
	for chunk_pos: Vector2i in _chunks_covering(terrain, site):
		terrain.create_chunk(chunk_pos)
		var chunk: Node3D = terrain.active_chunks.get(chunk_pos)
		if chunk == null:
			_fail("chunk %s over the tower site never got built" % chunk_pos)
			continue
		for entry: Array in _world_points(chunk):
			var where: Vector3 = entry[0]
			var d := Vector2(where.x - site.x, where.z - site.z).length()
			if d < closest:
				closest = d
				offender = "%s at %.1f m" % [entry[1], d]
			if d < radius:
				_fail("%s stands %.1f m from the tower site — inside the %.0f m disc" % [entry[1], d, radius])

	print("tower site %s: nearest world content is %s (disc is %.0f m)" % [site, offender, radius])

	# INFORMATION, NOT AN ASSERTION: the coin road is deliberately not excluded.
	# Phase 2 needs to know whether the trail runs through the front door.
	terrain._road_extend_to_x(site.x - 100.0, site.x + 100.0)
	var road: float = terrain._road_lateral_distance(site.x, site.z, 200.0)
	print("coin road passes %.1f m from the tower site (not excluded, by design)" % road)

	terrain.free()


func _check_the_rest_of_the_world_is_byte_identical() -> void:
	"""
	Checks 5 and 6 — the A/B, in the methodology the landmark constants document:
	generate the SAME field twice against the SAME code, once with the tower where
	it belongs and once with it moved out of the world, and digest both.

	Check 5: chunks nowhere near the disc must be IDENTICAL. Every rejection this
	bead added is a post-draw skip, so a chunk the disc does not reach must not
	notice the tower exists — if one does, some rejection is consuming or skipping a
	draw and every crocodile downstream of it has slid.

	Check 6, the negative control: the chunks the disc DOES reach must DIFFER. Check
	5 passes trivially for a feature that does nothing at all, and a tower exclusion
	that excludes nothing is precisely the regression nobody would notice.
	"""
	var near := _digest_field(_chunks_around(Vector2i(-8, 0)), FIELD_SEED, 400.0)
	var near_off := _digest_field(_chunks_around(Vector2i(-8, 0)), FIELD_SEED, TOWER_FAR_AWAY)
	var far := _digest_field(_chunks_around(Vector2i(0, 0)), FIELD_SEED, 400.0)
	var far_off := _digest_field(_chunks_around(Vector2i(0, 0)), FIELD_SEED, TOWER_FAR_AWAY)

	for chunk_pos: Vector2i in far.keys():
		if far[chunk_pos] != far_off[chunk_pos]:
			_fail("chunk %s (far from the tower) changed when the tower moved — a rejection is shifting an RNG stream" % chunk_pos)

	var differing := 0
	for chunk_pos: Vector2i in near.keys():
		if near[chunk_pos] != near_off[chunk_pos]:
			differing += 1
	if differing == 0:
		_fail("no chunk over the tower site changed when the tower moved — the exclusion is inert")


# ============================================================================
# HELPERS
# ============================================================================

func _make_terrain(seed_value: int) -> Node3D:
	## A REAL terrain node in the tree, not a stub — the chunk_stream_selfcheck
	## recipe. It never streams on its own: `_ready` finds no node in group
	## "player", so `player` stays null and `_process` returns immediately.
	## set_run_seed() is the public seam every other seed path goes through.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT))
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _chunks_covering(terrain: Node3D, site: Vector3) -> Array[Vector2i]:
	## Every chunk the exclusion disc can reach, plus one ring of slack so a
	## structure centred in a neighbour and reaching in is still generated.
	var middle: Vector2i = terrain.world_to_chunk(site)
	return _chunks_around(middle)


func _chunks_around(middle: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(middle.x - 2, middle.x + 3):
		for z in range(middle.y - 2, middle.y + 3):
			out.append(Vector2i(x, z))
	return out


func _digest_field(chunks: Array[Vector2i], seed_value: int, distance: float) -> Dictionary:
	## Build one field and return { chunk_pos: signature }. The tower distance is
	## set BEFORE any chunk is generated (and after the seed, so the memo the seed
	## warmed is re-derived at the new distance on first use).
	var terrain := _make_terrain(seed_value)
	terrain.tower_site_distance = distance
	var out := {}
	for chunk_pos: Vector2i in chunks:
		terrain.create_chunk(chunk_pos)
		var chunk: Node3D = terrain.active_chunks.get(chunk_pos)
		out[chunk_pos] = _signature(chunk) if chunk != null else PackedStringArray()
	terrain.free()
	return out


func _signature(chunk: Node3D) -> PackedStringArray:
	## Every world point in the chunk as "label@x,y,z", sorted — the order things
	## were created in is not part of the world, only the set of things and where
	## they are. Engine-named nodes contribute their CLASS instead of their name,
	## because that name carries a process-global counter that is higher in the
	## second build than the first however identical the two are (the reason
	## chunk_stream_selfcheck.gd gives).
	var out := PackedStringArray()
	for entry: Array in _world_points(chunk):
		var p: Vector3 = entry[0]
		out.append("%s@%.3f,%.3f,%.3f" % [entry[1], p.x, p.y, p.z])
	out.sort()
	return out


func _world_points(chunk: Node3D) -> Array:
	## [[world position, label], ...] for everything in a chunk EXCEPT coins — every
	## descendant node, plus every instance transform inside the chunk's block
	## MultiMesh, which is where all decorative geometry lives (blocks are not
	## nodes, so a node walk alone would see none of the world's stone).
	var out: Array = []
	_collect(chunk, chunk.global_position, out)
	return out


func _collect(node: Node, chunk_origin: Vector3, out: Array) -> void:
	for child: Node in node.get_children():
		var label := _label(child)
		# COINS are excluded by design (see the header), and so is the chunk's GROUND
		# body — the flat floor is not content, it is the chunk itself, and it sits at
		# the chunk origin where it would read as something standing on the site. It is
		# the one unnamed StaticBody3D here; the block collision body is named.
		if label.begins_with("Coin"):
			continue
		if child is StaticBody3D and child.name != "BlockCollision":
			continue
		if child is Node3D and not _is_container(child):
			out.append([(child as Node3D).global_position, label])
		if child is MultiMeshInstance3D:
			var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
			if mm != null:
				for i in mm.instance_count:
					out.append([chunk_origin + mm.get_instance_transform(i).origin, "block"])
		_collect(child, chunk_origin, out)


func _is_container(node: Node3D) -> bool:
	## The two per-chunk batch containers (see CLAUDE.md: one MultiMesh and one
	## collision body per chunk). Both sit at the chunk origin whatever they hold, so
	## their own position says nothing about where anything is — we walk INTO them
	## for the blocks and shapes that do.
	return node is MultiMeshInstance3D or node.name == "BlockCollision"


func _label(node: Node) -> String:
	if node.name.begins_with("@"):
		return node.get_class()
	return str(node.name)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)
