extends SceneTree
## ============================================================================
## CHUNK BATCH SELF-CHECK — the mesh-kind slot (bead godot-test1-y1o.1) and the
## per-biome draw-call bill its consumers run up (check 5, bead godot-test1-y1o.2)
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/batch_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS. `ChunkBatch` gained a THIRD field on every batch entry — which
## shared unit mesh it draws — and with it the first sanctioned multiplication of
## a chunk's MultiMeshInstance3Ds since batching landed. Four things about that
## are load-bearing, none of them visible on a headless machine, and each one
## fails SILENTLY:
##
##   1. EVERY UNIT MESH FITS THE UNIT CUBE. That single rule is what lets an
##      entry's `dimensions` keep meaning its bounding box for every kind — which
##      is what keeps prop_selfcheck's cube-corner reach helpers and
##      landmark_selfcheck's extent helpers valid UPPER BOUNDS with no edit, and
##      what keeps world_block.gdshader's -0.5..+0.5 model-space gradient
##      meaningful. A SphereMesh left at its default radius 1.0 breaks all of it
##      and looks like nothing worse than a big canopy.
##   2. ONE MultiMeshInstance3D PER KIND PRESENT — and, above all, exactly ONE for
##      a batch of nothing but cubes, which is every chunk the world ships bar a
##      forest one. A bucketing bug that emitted an empty node per kind would
##      quadruple the world's draw calls with no visual difference at all. Check 5
##      is the same rule billed per BIOME on the shipped spawners, against the
##      per-biome ceiling in KIND_CAP_BY_NAME.
##   3. THE CITY SPLITTER LEAVES A NON-CUBE WHOLE. A cut cone is not two cones;
##      cutting works only because a box's pieces are boxes.
##   4. COLLISION FOLLOWS THE KIND (bead godot-test1-y1o.10) — a near-round SPHERE
##      collides as a SphereShape3D and a near-round CYLINDER as a
##      CylinderShape3D, both INSCRIBED in `dimensions`; a CONE and anything past
##      `ROUND_COLLIDER_MAX_ASPECT` keep the bounding box. The shape COUNT is
##      untouched, which every collision budget in the suite depends on.
##
## The AABB check reads the mesh's own VERTEX ARRAYS rather than `get_aabb()`:
## headless is the dummy rendering driver (the same reason tower_interior writes
## its dossier rack through `multimesh.buffer`), so a value that round-trips
## through the RenderingServer is not a measurement. Vertices are the geometry.
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

## Slack on a coordinate that should land exactly on a unit-cube face. The meshes
## are built from `radius = 0.5` and `height = 1.0`, so the only error here is
## fp32 in Godot's own primitive generation.
const EPS: float = 1e-5

## Half-width of the field square check 2 sweeps for "every box the world ships
## is still a CUBE". 15 x 15 chunks is enough to draw every feature
## `spawn_objects_in_chunk` can build — one chunk only measures whichever one
## that chunk happened to pick.
const FIELD_SWEEP: int = 7

## CHECK 5's sweep: how far out to walk looking for chunks of every biome, and how
## many chunks of each to bill. SNOW and CITY are the rare bands, so the square has
## to be wide; four samples each is enough that a per-chunk fluke cannot pass for a
## biome-wide answer, and small enough that the sweep stops early in the common
## bands rather than building 2,000 chunks.
const BIOME_SWEEP: int = 22
const BIOME_SAMPLES: int = 4

## CHECK 5's CEILING: the most block draw calls a chunk of each biome may spend,
## which is epic y1o's "a chunk with trees AND rocks is +2" written down per band.
## It is a CAP and not an expected count, because whether a chunk drew a rock is a
## draw of the prop scatter — see the check's own docstring for why the floor is
## held by the per-kind bucket equality and prop_selfcheck instead.
##
##   FOREST   3 — cubes (trunks, blocks) + SPHERE canopies + ROCK mossy boulders
##   PLAINS   2 — cubes + ROCK boulder clusters
##   DESERT   4 — and it is the one row that needs its own paragraph, below
##   MOUNTAIN 2 — cubes (massifs, cairn tiers) + ROCK scree
##   SNOW     2 — cubes (drifts, stumps) + ROCK glacier ice
##   CITY     2 — and the reason is worth knowing, because the field city band's
##                OWN props are crates, garden walls and paving and not one of
##                them is a rock. `TerrainProps.build_prop` picks its theme at each PROP's
##                world position, not at the chunk centre, which is what feathers
##                a biome edge across a chunk seam — so a city-band chunk on a
##                plains boundary legitimately grows a plains boulder. That the
##                city builders themselves stay cube is prop_selfcheck check 11's,
##                where it can be asserted builder by builder instead of being
##                inferred from a chunk that may be nowhere near an edge.
##
## THE DESERT IS FOUR, AND THAT IS ONE MORE THAN BEAD y1o.4 BUDGETED FOR — it is
## flagged here rather than quietly absorbed, because the number wants an owner's
## eye. That bead asked for "F3 at most +2 per desert chunk" and was written on
## 2026-09-03, when the desert drew nothing but CUBEs; its own dependency y1o.3
## then gave every sandstone stack and every oasis boulder a ROCK, so the band was
## already at 2 before this bead added a single cylinder. The four are CUBE
## (scattered blocks, dunes, the oasis water disc, rim and reeds), CYLINDER (cactus
## segments and arms, palm trunks), ROCK (sandstone, boulders) and CONE (palm
## fronds).
##
## MEASURED over 2,814 stone-bearing desert chunks at run_seed 20260904:
##   1 bucket   500 chunks (17.8%)
##   2 buckets 1616 chunks (57.4%)
##   3 buckets  587 chunks (20.9%)
##   4 buckets  111 chunks ( 3.9%)  <- exactly the chunks carrying an OASIS
## CONE appears in 111 chunks and nowhere else, so the fourth bucket IS the oasis
## and nothing but the oasis — a rare authored-feeling set piece, not the common
## desert. `ponytail:` the one-line way back under three is to give the fronds the
## trunks' CYLINDER instead of their own CONE; that costs the frond its taper (a
## palm blade becomes a round stick) and is a swap of two arguments in
## `_spawn_desert_oasis`, so it is an owner's call about a picture and not a
## refactor.
##
## ONLY THE FOREST AND THE DESERT GO PAST TWO, and the forest's asymmetry is
## structural rather than tuning: canopies come from `_spawn_forest_content`, which
## `spawn_biome_content_in_chunk` dispatches on the CHUNK CENTRE, so a SPHERE can
## only ever appear in a chunk whose centre is forest. Rocks come from the
## per-position prop themer and can appear anywhere.
##
## KEYED BY NAME and resolved against the live `Biome` enum, so this table reads as
## design intent rather than as ints, and a biome MISSING a row is failed by name.
##
## CITY IS 4 SINCE BEAD godot-test1-y1o.5 and it is the most expensive band in the
## world: CUBE (hulls, doors, windows, stalls) + WEDGE (the pitched roofs) +
## CYLINDER (the lamp masts and shades) + ROCK, which the per-position prop themer
## can put in any chunk. That is the price of the pitched roof and it is written
## down here rather than discovered later — the roofs are the single biggest
## de-block change a house gets, and the masts are the one other thing in the band
## that was obviously a stack of boxes. Nothing else moved: the drift's swell took
## ROCK precisely so no OTHER biome's cap had to rise.
const KIND_CAP_BY_NAME: Dictionary = {
	"FOREST": 3,
	"PLAINS": 2,
	"DESERT": 4,
	"MOUNTAIN": 2,
	"SNOW": 2,
	"CITY": 4,
}

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_check_unit_meshes_fit_the_cube()
	_check_multimesh_per_kind()
	_check_splitter_carries_kind()
	_check_collision_is_unchanged_by_kind()
	_check_draw_calls_per_biome()
	_check_block_shader_uniforms()
	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


# ---------------------------------------------------------------------------
# CHECK 1 — every BoxKind's unit mesh is inside the unit cube
# ---------------------------------------------------------------------------

func _check_unit_meshes_fit_the_cube() -> void:
	"""
	THE ENUM'S WHOLE CONTRACT. Half-extents <= 0.5 on all three axes for every
	kind, measured off the mesh's own vertices.

	It iterates `BoxKind` rather than a list of its own, so a kind added tomorrow
	is covered the day its row lands — the `enemy_spawn_selfcheck` discipline one
	seam along.
	"""
	var measured: int = 0
	for kind: int in ChunkBatch.BoxKind.values():
		var name: String = ChunkBatch.BoxKind.find_key(kind)
		var mesh: Mesh = ChunkBatch.unit_mesh(kind)
		if mesh == null:
			_fail("BoxKind.%s has no unit mesh — a null mesh is an invisible chunk "
					% name + "with no error anywhere")
			continue
		if mesh.get_surface_count() < 1:
			_fail("BoxKind.%s's unit mesh has no surface" % name)
			continue
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			_fail("BoxKind.%s's unit mesh has no vertices — nothing was measured" % name)
			continue
		var reach := Vector3.ZERO
		for v: Vector3 in verts:
			reach.x = maxf(reach.x, absf(v.x))
			reach.y = maxf(reach.y, absf(v.y))
			reach.z = maxf(reach.z, absf(v.z))
		if reach.x > 0.5 + EPS or reach.y > 0.5 + EPS or reach.z > 0.5 + EPS:
			_fail(("BoxKind.%s's unit mesh reaches %s from its own origin, outside "
					% [name, reach])
					+ "the unit cube's 0.5 half-extent. An entry's `dimensions` "
					+ "would stop meaning its bounding box, which silently invalidates "
					+ "prop_selfcheck's cube-corner reach helpers and "
					+ "landmark_selfcheck's extent helpers for every consumer of "
					+ "this kind")
		# The negative half of the same question: a mesh that reaches nowhere
		# passes the bound above and draws nothing.
		if reach.y < 0.5 - EPS:
			_fail(("BoxKind.%s's unit mesh spans only %.4f of the unit cube's height. "
					% [name, reach.y * 2.0])
					+ "world_block.gdshader's gradient is a model-space "
					+ "VERTEX.y + 0.5 sweep, so a short mesh never reaches full "
					+ "colour and every instance of this kind renders dark")

		# FACETED NORMAL CONTRACT (bead godot-test1-y1o.9): the non-cube unit
		# primitives must be unindexed meshes with flat per-face normals so
		# style A shades with crisp facets rather than Gouraud-smooth shading.
		if kind != ChunkBatch.BoxKind.CUBE:
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if norms.size() != verts.size():
				_fail("BoxKind.%s unit mesh normal count (%d) != vertex count (%d)"
						% [name, norms.size(), verts.size()])
			if idx != null and not (idx as PackedInt32Array).is_empty():
				_fail("BoxKind.%s unit mesh is indexed (%d indices) — style A requires unindexed flat triangles"
						% [name, (idx as PackedInt32Array).size()])
			for i in range(0, verts.size(), 3):
				if i + 2 < norms.size():
					if not norms[i].is_equal_approx(norms[i + 1]) or not norms[i].is_equal_approx(norms[i + 2]):
						_fail("BoxKind.%s has smooth or mismatched normals on triangle %d — style A requires flat per-face normals"
								% [name, i / 3])
						break
		measured += 1

	if measured != ChunkBatch.BoxKind.size():
		_fail("measured %d of %d BoxKind rows" % [measured, ChunkBatch.BoxKind.size()])
	Sentinel.done("unit_meshes")


# ---------------------------------------------------------------------------
# CHECK 2 — one MultiMeshInstance3D per kind PRESENT
# ---------------------------------------------------------------------------

func _check_multimesh_per_kind() -> void:
	"""
	The cube-only chunk first, because it is every chunk in the shipped world and
	the thing that must not have moved; then a mixed batch; then the field chunk
	the bead's acceptance names — one planted SPHERE among real cubes, which must
	cost exactly one extra draw call and share the one material.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# --- a) CUBE ONLY: exactly one node, still named BlockMultiMesh -----------
	var cube_batch: Array = []
	var cube_body := StaticBody3D.new()
	for i in 5:
		ChunkBatch.create_box(Vector3(float(i), 1.0, 0.0), Vector3.ONE, 0.0,
				rng, cube_batch, cube_body)
	var cube_parent := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(cube_parent, cube_batch)
	var cube_mmis: Array = _multimeshes(cube_parent)
	if cube_mmis.size() != 1:
		_fail(("a cube-only batch built %d MultiMeshInstance3Ds, not 1 — that is "
				% cube_mmis.size())
				+ "every chunk in the shipped world, and the one-batch-per-chunk "
				+ "invariant budapest_selfcheck check 4 defends")
	elif (cube_mmis[0] as Node).name != "BlockMultiMesh":
		_fail("the cube batch's node is named '%s', not 'BlockMultiMesh' — "
				% (cube_mmis[0] as Node).name
				+ "budapest_selfcheck and the world A/B harnesses look it up by name")
	elif (cube_mmis[0] as MultiMeshInstance3D).multimesh.instance_count != cube_batch.size():
		_fail("the cube batch has %d entries but its MultiMesh holds %d instances"
				% [cube_batch.size(), (cube_mmis[0] as MultiMeshInstance3D).multimesh.instance_count])
	cube_parent.free()
	cube_body.free()

	# --- b) MIXED: one node per kind present, and no node for a kind absent ---
	# Deliberately NOT one of each: CONE is left out so "per kind PRESENT" is
	# measured rather than "per kind in the enum".
	var mixed_plan: Array[int] = [
		ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.SPHERE, ChunkBatch.BoxKind.CUBE,
		ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.SPHERE, ChunkBatch.BoxKind.SPHERE,
	]
	var mixed_batch: Array = []
	var mixed_body := StaticBody3D.new()
	for i in mixed_plan.size():
		ChunkBatch.create_box(Vector3(float(i), 1.0, 0.0), Vector3(2.0, 3.0, 4.0), 0.0,
				rng, mixed_batch, mixed_body, 0.0, Color(0, 0, 0, 0), false, mixed_plan[i])
	var mixed_parent := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(mixed_parent, mixed_batch, false)
	var mixed_mmis: Array = _multimeshes(mixed_parent)

	var want_counts: Dictionary = {}
	for k: int in mixed_plan:
		want_counts[k] = int(want_counts.get(k, 0)) + 1
	if mixed_mmis.size() != want_counts.size():
		_fail("a batch of %d kinds built %d MultiMeshInstance3Ds"
				% [want_counts.size(), mixed_mmis.size()])

	var seen_total: int = 0
	var meshes_seen: Array = []
	for node_v: Variant in mixed_mmis:
		var mmi: MultiMeshInstance3D = node_v
		seen_total += mmi.multimesh.instance_count
		# ONE MATERIAL FOR THE WHOLE WORLD — the shader's gradient is model-space,
		# so a per-kind material would be a second lazy singleton for no reason
		# and a second thing to keep in step with BLOCK_BOTTOM_SHADE.
		if mmi.material_override != ChunkBatch._get_shared_block_material():
			_fail("'%s' does not share ChunkBatch._get_shared_block_material()" % mmi.name)
		# The cast_shadows flag is the CHUNK's, so every kind in a chunk must
		# answer the same way — a Budapest chunk that cast shadows from its
		# spheres alone is the 19 ms the owner ruled out.
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("'%s' ignored cast_shadows = false" % mmi.name)
		if mmi.multimesh.mesh in meshes_seen:
			_fail("'%s' draws a mesh another bucket in the same chunk already draws "
					% mmi.name + "— the buckets are not one per kind")
		meshes_seen.append(mmi.multimesh.mesh)
	if seen_total != mixed_batch.size():
		_fail("the mixed batch has %d entries but its MultiMeshes hold %d instances "
				% [mixed_batch.size(), seen_total]
				+ "in total — boxes were dropped or doubled by the bucketing")
	for k: int in want_counts:
		var want_name: String = ("BlockMultiMesh" if k == ChunkBatch.BoxKind.CUBE
				else "BlockMultiMesh_%s" % ChunkBatch.BoxKind.find_key(k))
		var node := mixed_parent.get_node_or_null(NodePath(want_name)) as MultiMeshInstance3D
		if node == null:
			_fail("no '%s' node for a kind the batch contains" % want_name)
		elif node.multimesh.instance_count != int(want_counts[k]):
			_fail("'%s' holds %d instances, expected %d"
					% [want_name, node.multimesh.instance_count, int(want_counts[k])])
		elif node.multimesh.mesh != ChunkBatch.unit_mesh(k):
			_fail("'%s' does not draw BoxKind.%s's unit mesh"
					% [want_name, ChunkBatch.BoxKind.find_key(k)])
	if mixed_parent.get_node_or_null(NodePath("BlockMultiMesh_CONE")) != null:
		_fail("a node was built for CONE, which no entry in the batch asked for — "
				+ "one MultiMeshInstance3D per kind PRESENT, never per kind that exists")
	mixed_parent.free()
	mixed_body.free()

	# --- c) A REAL FIELD CHUNK, plus one planted SPHERE -----------------------
	# The bead's acceptance: the machinery itself must change zero draw calls, and
	# a single consumer must cost exactly one. Driven on the shipped spawner so
	# the "before" number is the world's and not a hand-built batch's.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT) as GDScript)
	root.add_child(terrain)
	terrain.set_run_seed(424242)
	# A GRID, not one chunk. `spawn_objects_in_chunk` builds a different feature
	# per chunk (scatter, stacks, mounds, ramps, arches...), so a single sample
	# measures whichever one that chunk happened to draw and shrugs at a kind
	# planted anywhere else. FIELD_SWEEP squares is what makes "nothing in the
	# world has changed silhouette" a sweep rather than a spot check.
	#
	# THE SCATTERED BLOCKS ARE WHERE THE PROPS LIVE, so this sweep's allow-list is
	# not "CUBE only" any more (bead godot-test1-y1o.3): `TerrainProps.build_prop` runs inside
	# `spawn_objects_in_chunk`, and six of its builders now draw ROCK. Bead
	# godot-test1-y1o.5's snow drift joins them and needed NO widening here: its
	# swell is a ROCK, deliberately, because a prop's theme is picked at its own
	# position and a SPHERE drift would have put a new bucket into every band that
	# borders snow. What the sweep still refuses is a kind arriving here
	# unannounced — a SPHERE, a CONE, a CYLINDER or a WEDGE in the scatter is a
	# consumer nobody filed a bead for, and the allow-list is what makes that a
	# build failure instead of a rendering surprise. Note it is a set and not a
	# count: whether a chunk drew a rock is a draw of the scatter stream, so "how
	# many" is not a stable number.
	var field_batch: Array = []
	var field_body := StaticBody3D.new()
	var allowed_kinds: Array[int] = [ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.ROCK]
	var stray: Dictionary = {}     # kind -> boxes seen, for kinds not on the list
	var seen_kinds: Dictionary = {}
	var wrong_bucket_count: int = 0
	var sampled: int = 0
	for cx in range(-FIELD_SWEEP, FIELD_SWEEP + 1):
		for cz in range(-FIELD_SWEEP, FIELD_SWEEP + 1):
			var one_batch: Array = []
			var one_body := StaticBody3D.new()
			var platforms: Array = []
			terrain.spawn_objects_in_chunk(Vector2i(cx, cz), platforms, one_batch, one_body)
			if one_batch.is_empty():
				one_body.free()
				continue
			sampled += 1
			var here: Dictionary = {}
			for entry_v: Variant in one_batch:
				var k: int = int((entry_v as Dictionary)["kind"])
				here[k] = true
				seen_kinds[k] = true
				if not allowed_kinds.has(k):
					stray[k] = int(stray.get(k, 0)) + 1
			var one_parent := MeshInstance3D.new()
			ChunkBatch._build_block_multimesh(one_parent, one_batch)
			# One bucket per kind PRESENT, measured on the real world rather than
			# on planted boxes — an empty bucket or a missing one shows up here on
			# whatever the scatter actually drew.
			if _multimeshes(one_parent).size() != here.size():
				wrong_bucket_count += 1
			one_parent.free()
			one_body.free()
			if field_batch.is_empty():
				field_batch = one_batch
	if sampled < 10:
		_fail("only %d of %d field chunks produced boxes — nothing was measured"
				% [sampled, (2 * FIELD_SWEEP + 1) * (2 * FIELD_SWEEP + 1)])
	for stray_kind_v: Variant in stray:
		var stray_kind: int = stray_kind_v
		_fail("the SCATTERED-BLOCK spawner emitted %d boxes of kind %s over %d chunks. "
				% [stray[stray_kind], ChunkBatch.BoxKind.find_key(stray_kind), sampled]
				+ "Only CUBE and ROCK belong here — consumers of the kind slot are "
				+ "named beads judged BY EYE by the owner, so a silhouette that "
				+ "changed here changed nowhere anybody asked for")
	# The positive control for the allow-list: a sweep that drew no rock at all
	# would satisfy every line above and prove nothing about bead y1o.3.
	if not seen_kinds.has(ChunkBatch.BoxKind.ROCK):
		_fail("no ROCK box in %d field chunks — bead y1o.3 put rocks in every biome, "
				% sampled + "so this sweep is passing vacuously")
	if wrong_bucket_count > 0:
		_fail("%d of %d real field chunks did not build exactly one MultiMeshInstance3D "
				% [wrong_bucket_count, sampled] + "per kind PRESENT in their batch — an "
				+ "empty bucket is a free draw call, a missing one is invisible stone")

	# A PLANTED SPHERE COSTS EXACTLY ONE MORE BUCKET, whatever the chunk already
	# held — measured as a delta rather than against the literal 2 it was, because
	# the sampled chunk may legitimately carry rocks now.
	var before_parent := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(before_parent, field_batch)
	var before: int = _multimeshes(before_parent).size()
	before_parent.free()
	var planted_rng := RandomNumberGenerator.new()
	planted_rng.seed = 99
	ChunkBatch.create_box(Vector3(1.0, 4.0, 1.0), Vector3(3.0, 3.0, 3.0), 0.0,
			planted_rng, field_batch, field_body, 0.0, Color(0, 0, 0, 0), false,
			ChunkBatch.BoxKind.SPHERE)
	var planted_parent := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(planted_parent, field_batch)
	var planted: Array = _multimeshes(planted_parent)
	if planted.size() != before + 1:
		_fail("a field chunk of %d bucket(s) carrying one planted SPHERE built %d, not %d "
				% [before, planted.size(), before + 1]
				+ "— a consumer costs exactly +1 draw call per kind")
	else:
		var mat: Material = (planted[0] as MultiMeshInstance3D).material_override
		for extra_v: Variant in planted:
			if (extra_v as MultiMeshInstance3D).material_override != mat:
				_fail("bucket '%s' does not share the cube batch's material"
						% (extra_v as Node).name)
	planted_parent.free()
	field_body.free()
	terrain.free()
	Sentinel.done("multimesh_per_kind")


func _multimeshes(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
	return out


# ---------------------------------------------------------------------------
# CHECK 3 — the city splitter carries kind, and leaves a non-cube whole
# ---------------------------------------------------------------------------

func _check_splitter_carries_kind() -> void:
	"""
	`split_city_boxes_on_chunk_grid` REBUILDS every piece's dict from scratch, so
	a field it forgets is a field silently lost — and the entry shape has to stay
	uniform or budapest_selfcheck's whole-dict `var_to_bytes` signatures stop
	comparing equal between two runs that agree about every box.

	The non-cube half is the design rule: a cut cone is not two cones.

	BOTH HALVES ON ONE PREDICATE, and that is the half this check exists for since
	bead godot-test1-y1o.10. The splitter's two loops are handed DIFFERENT bases for
	the same box (the batch entry carries `rot.scaled_local(dimensions)`, the shape
	node the bare `rot`) and are joined only by `_is_axis_aligned_basis`; cutting
	one and not the other is a drawn wall whose collision lives in another chunk.
	So the wide CUBE below is asserted to be cut into the SAME number of pieces on
	both sides, and the wide colliding SPHERE to be left whole on both — the second
	being the new pairing: the visual half skips it on `kind`, and the collision
	half reaches the same answer with no knowledge of kind at all, because a
	`SphereShape3D` fails its `as BoxShape3D` cast.
	"""
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT) as GDScript)
	root.add_child(terrain)
	var chunk_size: float = terrain.chunk_size
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# One cube far wider than a chunk (so it MUST split) and one sphere the same
	# size (which must NOT), in one batch so their outputs cannot be confused.
	var batch: Array = []
	var body := StaticBody3D.new()
	var wide := Vector3(chunk_size * 3.4, 6.0, 4.0)
	ChunkBatch.create_box(Vector3.ZERO, wide, 0.0, rng, batch, body)
	ChunkBatch.create_box(Vector3(0.0, 20.0, 0.0), wide, 0.0, rng, batch, body,
			0.0, Color(0, 0, 0, 0), false, ChunkBatch.BoxKind.SPHERE)
	# A COLLIDING round box the same size, for the both-halves pairing: it is the
	# only entry here that reaches the collision loop with a non-box shape. Near
	# cubic (so it really is a SphereShape3D, not the aspect fallback) and still
	# far wider than a chunk on X, which is what the splitter measures.
	var wide_round := Vector3(chunk_size * 3.4, chunk_size * 3.0, chunk_size * 3.2)
	ChunkBatch.create_box(Vector3(0.0, 60.0, 0.0), wide_round, 0.0, rng, batch, body,
			0.0, Color(0, 0, 0, 0), true, ChunkBatch.BoxKind.SPHERE)
	var shapes_before: int = body.get_child_count()
	ChunkBatch.split_city_boxes_on_chunk_grid(terrain, Vector3.ZERO, batch, body)

	var cubes: int = 0
	var spheres: int = 0
	for entry_v: Variant in batch:
		var entry: Dictionary = entry_v
		if not entry.has("kind"):
			_fail("a split piece has no \"kind\" key — the entry shape must stay "
					+ "UNIFORM or budapest_selfcheck's whole-dict signatures stop "
					+ "comparing equal between two runs that agree about every box")
			break
		if int(entry["kind"]) == ChunkBatch.BoxKind.SPHERE:
			spheres += 1
		elif int(entry["kind"]) == ChunkBatch.BoxKind.CUBE:
			cubes += 1
		else:
			_fail("the splitter invented BoxKind.%s out of a CUBE/SPHERE batch"
					% ChunkBatch.BoxKind.find_key(int(entry["kind"])))
			break

	if cubes < 4:
		_fail("a cube %.1f m wide over a %.1f m chunk grid split into %d pieces — "
				% [wide.x, chunk_size, cubes]
				+ "the splitter did not run, so nothing about kind was measured")
	if spheres != 2:
		_fail("two SPHEREs %.1f m wide came back as %d entries — a non-cube kind must "
				% [wide.x, spheres]
				+ "be left WHOLE and keep the centre rule, because a cut cone is "
				+ "not two cones")

	# --- BOTH HALVES, ONE PREDICATE ------------------------------------------
	var box_shapes: int = 0
	var round_shapes: int = 0
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		if cs.shape is BoxShape3D:
			box_shapes += 1
		else:
			round_shapes += 1
	if shapes_before != 2:
		_fail("the splitter probe hung %d shapes before cutting, not the 2 it plants "
				% shapes_before + "(one cube, one colliding sphere) — the pairing "
				+ "assertions below are measuring the wrong batch")
	if box_shapes != cubes:
		_fail("the splitter cut the wide cube into %d MESH pieces but %d COLLISION "
				% [cubes, box_shapes]
				+ "pieces. The two halves are handed different bases for the same box "
				+ "and joined only by _is_axis_aligned_basis — one cut and not the "
				+ "other is a drawn wall whose collision lives in another chunk")
	if round_shapes != 1:
		_fail("a colliding SPHERE %.1f m wide left %d non-box collision shapes, not 1 "
				% [wide_round.x, round_shapes]
				+ "— the visual half leaves it whole on `kind`, so the collision half "
				+ "must leave it whole too (it does, by failing its BoxShape3D cast)")
	body.free()
	terrain.free()
	Sentinel.done("splitter_kind")


# ---------------------------------------------------------------------------
# CHECK 4 — collision is unchanged by kind
# ---------------------------------------------------------------------------

func _check_collision_is_unchanged_by_kind() -> void:
	"""
	THE COLLISION SHAPE IS THE KIND'S (bead godot-test1-y1o.10), and this is the
	only place the mapping is asserted.

	A near-round SPHERE hangs a `SphereShape3D` and a near-round CYLINDER a
	`CylinderShape3D`, both INSCRIBED in `dimensions`; a CONE, a CUBE and anything
	squashed past `ROUND_COLLIDER_MAX_ASPECT` hang a `BoxShape3D` OF `dimensions`.
	Read `ChunkBatch.collision_shape_for`'s docstring for why each of those is the
	answer — this function only measures that they still are.

	FOUR THINGS, and each fails silently on its own:
	  (a) THE TYPE per kind, on a NEAR-CUBIC box (the shape a landmark's boulder,
	      drum or pier really is). A revert to all-boxes is otherwise invisible.
	  (b) THE DIMENSIONS. A sphere's radius is the SMALLEST half-extent and a
	      cylinder's height is exactly `dimensions.y` — a radius taken off the
	      LARGEST axis instead would put stone outside the box, and outside the
	      radius every landmark declares.
	  (c) THE INSCRIPTION, measured rather than derived: no point of the shape's
	      own bounding box may leave `dimensions`.
	  (d) THE ASPECT FALLBACK, driven at BOTH ends of `ROUND_COLLIDER_MAX_ASPECT`
	      — a box just inside it is still round, one just outside is a box again.
	      Without the second half the constant could be raised to infinity and
	      every assertion here would still pass.

	THE SHAPE COUNT IS UNCHANGED and that is asserted too: exactly one shape per
	colliding entry, none for `collide = false`, whatever the kind. Every check
	that bills a chunk's collision (budapest's per-chunk budget, the tower's 640)
	counts shapes, so a kind that hung two would move numbers all over the suite.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	# Near-cubic on purpose: this is (a)'s subject, and a 2 x 5 x 3 box is past
	# the aspect gate — (d) drives that end deliberately, below.
	var dims := Vector3(3.0, 3.6, 3.2)
	# The type every kind must hang at this aspect. CONE is the deliberate box;
	# ROCK's box is the FEATURE (bead godot-test1-y1o.3) — its flat lid is at the
	# box's own top face, which is the whole reason the kind exists, and a round
	# collider under it would drop the climbable surface every rock builder's
	# recorded `top` promises. The dict is a TOTAL map over the enum: a kind added
	# without a row here fails below by name rather than crashing this loop.
	# The WEDGE is the one HULL (bead godot-test1-y1o.36): its roof is standable,
	# so its collider has to BE the drawn prism — the box over it is the "invisible
	# flat square" this whole check exists to forbid.
	var want_type: Dictionary = {
		ChunkBatch.BoxKind.CUBE: "BoxShape3D",
		ChunkBatch.BoxKind.SPHERE: "SphereShape3D",
		ChunkBatch.BoxKind.CONE: "BoxShape3D",
		ChunkBatch.BoxKind.CYLINDER: "CylinderShape3D",
		ChunkBatch.BoxKind.ROCK: "BoxShape3D",
		ChunkBatch.BoxKind.WEDGE: "ConvexPolygonShape3D",
	}
	for kind: int in ChunkBatch.BoxKind.values():
		var batch: Array = []
		var body := StaticBody3D.new()
		ChunkBatch.create_box(Vector3(1.0, 2.5, -1.0), dims, 0.0, rng, batch, body,
				0.0, Color(0, 0, 0, 0), true, kind)
		var shapes: Array = body.get_children()
		var name: String = ChunkBatch.BoxKind.find_key(kind)
		if not want_type.has(kind):
			_fail("BoxKind.%s has no row in this check's want_type table — a new kind "
					% name + "must declare which Shape3D it collides as, or its collider "
					+ "is unasserted rather than correct")
			body.free()
			continue
		if shapes.size() != 1:
			_fail("create_box(kind = %s, collide = true) hung %d shapes, not 1"
					% [name, shapes.size()])
		else:
			var cs := shapes[0] as CollisionShape3D
			var shape: Shape3D = cs.shape if cs != null else null
			var got: String = shape.get_class() if shape != null else "<none>"
			if got != String(want_type[kind]):
				_fail("create_box(kind = %s) on a near-cubic box hung a %s, wanted a %s — "
						% [name, got, want_type[kind]]
						+ "ChunkBatch.collision_shape_for's whole table")
			else:
				for problem: String in _shape_problems(name, shape, dims):
					_fail(problem)
		# ...and collide = false still hangs nothing, for every kind.
		var no_batch: Array = []
		var no_body := StaticBody3D.new()
		ChunkBatch.create_box(Vector3.ZERO, dims, 0.0, rng, no_batch, no_body,
				0.0, Color(0, 0, 0, 0), false, kind)
		if no_body.get_child_count() != 0:
			_fail("create_box(kind = %s, collide = false) still hung a shape" % name)
		if no_batch.size() != 1 or int((no_batch[0] as Dictionary)["kind"]) != kind:
			_fail("create_box(kind = %s, collide = false) did not record the kind on "
					% name + "its visual entry")
		body.free()
		no_body.free()

	# --- (d) the aspect gate, at both ends -----------------------------------
	# Driven on collision_shape_for directly: create_box only forwards to it, and
	# a pair of RNG-consuming calls per probe would say nothing extra.
	var a: float = ChunkBatch.ROUND_COLLIDER_MAX_ASPECT
	var probes: Array = [
		# kind, dimensions, expected class, what the case IS
		[ChunkBatch.BoxKind.SPHERE, Vector3(2.0 * (a - 0.05), 2.0, 2.0), "SphereShape3D",
			"a sphere just INSIDE the aspect gate"],
		[ChunkBatch.BoxKind.SPHERE, Vector3(2.0 * (a + 0.05), 2.0, 2.0), "BoxShape3D",
			"a sphere just OUTSIDE it (a squashed ellipsoid keeps its box)"],
		[ChunkBatch.BoxKind.SPHERE, Vector3(3.6, 1.6, 3.6), "BoxShape3D",
			"a 2.25-aspect lens dome — the shape the fallback exists for. NOTHING"
			+ " SHIPPED IS PAST THE GATE since bead y1o.11 reshaped the Taj (the"
			+ " worst colliding sphere in the field is now its 1.57 chattri), so"
			+ " this planted box is the ONLY thing exercising that half"],
		[ChunkBatch.BoxKind.CYLINDER, Vector3(2.0 * (a - 0.05), 40.0, 2.0), "CylinderShape3D",
			"a cylinder just INSIDE the gate — and 40 m TALL, because the axis is"
			+ " not part of the aspect: a column is not a squashed drum"],
		[ChunkBatch.BoxKind.CYLINDER, Vector3(2.0 * (a + 0.05), 4.0, 2.0), "BoxShape3D",
			"a cylinder whose PLAN is past the gate (an elliptic drum)"],
	]
	for probe_v: Variant in probes:
		var probe: Array = probe_v
		var pdims: Vector3 = probe[1]
		var shape := ChunkBatch.collision_shape_for(int(probe[0]), pdims)
		if shape.get_class() != String(probe[2]):
			_fail("%s (%s at %s) collided as a %s, wanted a %s"
					% [probe[3], ChunkBatch.BoxKind.find_key(int(probe[0])), pdims,
						shape.get_class(), probe[2]])
		else:
			for problem: String in _shape_problems(String(probe[3]), shape, pdims):
				_fail(problem)
	Sentinel.done("collision_by_kind")


func _shape_problems(label: String, shape: Shape3D, dims: Vector3) -> Array[String]:
	"""
	(b) + (c): the shape's dimensions, and that its own bounding box is INSIDE
	the entry's. Shared by the per-kind loop and the aspect probes so the two can
	never disagree about what "inscribed" means.

	The bound is measured from the shape's OWN fields rather than re-derived from
	`dims`, which is the point: a radius taken off the wrong axis shows up here as
	stone outside the box, not as a formula that matches itself.
	"""
	var out: Array[String] = []
	var half := Vector3.ZERO
	var sphere := shape as SphereShape3D
	var cyl := shape as CylinderShape3D
	var box := shape as BoxShape3D
	var hull := shape as ConvexPolygonShape3D
	if sphere != null:
		half = Vector3.ONE * sphere.radius
		var want_r: float = minf(dims.x, minf(dims.y, dims.z)) * 0.5
		if not is_equal_approx(sphere.radius, want_r):
			out.append("%s: SphereShape3D radius %.4f, wanted the SMALLEST half-extent %.4f"
					% [label, sphere.radius, want_r])
	elif cyl != null:
		half = Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)
		var want_radius: float = minf(dims.x, dims.z) * 0.5
		if not is_equal_approx(cyl.radius, want_radius):
			out.append("%s: CylinderShape3D radius %.4f, wanted the smaller RADIAL half-extent %.4f"
					% [label, cyl.radius, want_radius])
		if not is_equal_approx(cyl.height, dims.y):
			out.append("%s: CylinderShape3D height %.4f, wanted dimensions.y %.4f exactly — "
					% [label, cyl.height, dims.y]
					+ "the axis is reproduced, only the radius is inscribed")
	elif box != null:
		half = box.size * 0.5
		if box.size != dims:
			out.append("%s: BoxShape3D sized %s, not the dimensions %s" % [label, box.size, dims])
	elif hull != null:
		# The WEDGE, and the only hull in the table. The measurement is the POINT
		# SET itself against `ChunkBatch.UNIT_WEDGE_POINTS` scaled by `dims` — not
		# an AABB, which a hull that had lost its ridge and become a box would
		# still pass. Order is not asserted (the collider does not care), so this
		# is a set comparison; the mesh's winding depends on the order and check 1
		# is what measures that.
		var want_pts: Array[Vector3] = []
		for p: Vector3 in ChunkBatch.UNIT_WEDGE_POINTS:
			want_pts.append(p * dims)
		var got_pts: PackedVector3Array = hull.points
		if got_pts.size() != want_pts.size():
			out.append("%s: ConvexPolygonShape3D carries %d points, wanted the prism's %d"
					% [label, got_pts.size(), want_pts.size()])
		for want_p: Vector3 in want_pts:
			var found := false
			for got_p: Vector3 in got_pts:
				if got_p.is_equal_approx(want_p):
					found = true
					break
			if not found:
				out.append("%s: the hull has no vertex at %s — it is not the prism "
						% [label, want_p] + "`_build_unit_wedge_mesh` draws, so the "
						+ "slope you stand on is not the slope you see")
		for got_p: Vector3 in got_pts:
			half = Vector3(maxf(half.x, absf(got_p.x)), maxf(half.y, absf(got_p.y)),
					maxf(half.z, absf(got_p.z)))
	else:
		out.append("%s: collided as a %s, which this check cannot measure at all"
				% [label, shape.get_class()])
		return out
	if half.x > dims.x * 0.5 + EPS or half.y > dims.y * 0.5 + EPS \
			or half.z > dims.z * 0.5 + EPS:
		out.append("%s: the collider's own bounds %s reach outside the entry's %s — a "
				% [label, half * 2.0, dims]
				+ "collider must be INSCRIBED in `dimensions` like the unit mesh is, or "
				+ "it puts stone outside the radius a landmark declares")
	return out


# ---------------------------------------------------------------------------
# CHECK 5 — the draw-call bill, per biome (bead godot-test1-y1o.2)
# ---------------------------------------------------------------------------

func _check_draw_calls_per_biome() -> void:
	"""
	THE PRICE OF THE CONSUMERS, measured where it is paid.

	Check 2 proved the MACHINERY costs nothing; this bills what the field really
	spends, biome by biome, on the shipped spawners. It is the kind of number that
	drifts silently: a `kind` argument left on a shared helper, or a builder copied
	from the forest, doubles a biome's block draw calls with no visual difference
	worth noticing.

	TWO ASSERTIONS, AND THE SECOND IS WHY THE FIRST IS NOT A TAUTOLOGY.

	  (a) A chunk builds exactly one node PER DISTINCT KIND IN ITS BATCH — no empty
	      bucket, no missing one. Measured on real chunks rather than check 2's
	      planted ones, so it also covers a builder that emits a kind nothing else
	      in the suite knows about.
	  (b) A biome may not build MORE than KIND_CAP allows. That ceiling is the epic
	      y1o cap ("a chunk with trees AND rocks is +2") written down per biome, and
	      it is what makes a new consumer a DECISION instead of a drift.

	Why a cap rather than the exact count bead y1o.2 asserted: a rock is a PROP, and
	whether a given chunk drew one is a draw of the scatter stream. Demanding "2"
	of every plains chunk would fail on the ones that legitimately drew no prop; the
	old exact form worked only while the sole consumer was the forest, whose canopy
	is on every tree in a wood. The floor is kept honestly instead by (a) plus the
	forest's named buckets below and prop_selfcheck check 11, which asserts the
	rock builders emit ROCK entry by entry.

	THE BILL AS OF BEAD godot-test1-y1o.3 (rocks and boulders) is KIND_CAP_BY_NAME
	up top, which carries the per-biome reasoning including why the city band's
	cap is two despite having no rock builder of its own.

	BUDAPEST IS NOT SWEPT HERE and does not need to be — `spawn_biome_content_in_chunk`
	returns early inside the rect, and budapest_selfcheck check 4 already asserts
	"1 MultiMeshInstance3D" over real city chunks built by the real city builders.
	Two homes for one rule is how they drift apart.

	IT ITERATES THE Biome ENUM, never a list of its own, so a biome added later is
	billed the day its row lands (the BIOME_SPECIES / SPECIES idiom) — and a biome
	KIND_CAP forgets is failed BY NAME rather than silently defaulted, which is the
	same discipline one table along.

	The batch is BOTH field spawners into one array, which is what a real chunk
	does: `spawn_objects_in_chunk` (scattered blocks — every biome's cube bucket)
	plus `spawn_biome_content_in_chunk` (the biome's own content). A chunk that
	drew nothing at all is skipped rather than counted as a pass, and the
	per-biome sample counts are asserted so an unreachable biome is a failure
	instead of a silent zero.
	"""
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT) as GDScript)
	root.add_child(terrain)
	terrain.set_run_seed(20260904)

	var biome_enum: Dictionary = (terrain.get_script() as GDScript).get_script_constant_map()["Biome"]
	var forest_value: int = int(biome_enum["FOREST"])

	# KIND_CAP_BY_NAME resolved against the live enum, so the cap table is written
	# in the names a reader recognises and can never drift onto a stale int.
	var kind_cap: Dictionary = {}
	for cap_name_v: Variant in KIND_CAP_BY_NAME:
		var cap_name: String = cap_name_v
		if biome_enum.has(cap_name):
			kind_cap[int(biome_enum[cap_name])] = int(KIND_CAP_BY_NAME[cap_name])
		else:
			_fail("KIND_CAP_BY_NAME names biome '%s', which the Biome enum does not have" % cap_name)

	var sampled: Dictionary = {}   # biome value -> chunks measured
	var worst: Dictionary = {}     # biome value -> most buckets any sampled chunk built
	var paying: Dictionary = {}    # biome value -> chunks that built MORE than one
	var wrong: Dictionary = {}     # biome value -> "got n, wanted m" for the first offender

	for cx in range(-BIOME_SWEEP, BIOME_SWEEP + 1):
		for cz in range(-BIOME_SWEEP, BIOME_SWEEP + 1):
			var chunk := Vector2i(cx, cz)
			var centre: Vector3 = terrain.chunk_to_world(chunk)
			if terrain.in_budapest(centre.x, centre.z):
				continue
			var biome: int = terrain.biome_at(centre.x, centre.z)
			if int(sampled.get(biome, 0)) >= BIOME_SAMPLES:
				continue
			var batch: Array = []
			var body := StaticBody3D.new()
			var platforms: Array = []
			var obstacles: Array = []
			terrain.spawn_objects_in_chunk(chunk, platforms, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk, obstacles, batch, body)
			body.free()
			if batch.is_empty():
				continue
			sampled[biome] = int(sampled.get(biome, 0)) + 1
			var parent := MeshInstance3D.new()
			ChunkBatch._build_block_multimesh(parent, batch)
			var nodes: Array = _multimeshes(parent)
			worst[biome] = maxi(int(worst.get(biome, 0)), nodes.size())
			if nodes.size() > 1:
				paying[biome] = int(paying.get(biome, 0)) + 1

			# (a) ONE BUCKET PER DISTINCT KIND PRESENT, no more and no fewer. The
			# expectation is read off the batch the shipped spawners just filled,
			# so a builder emitting a kind this check has never heard of is still
			# billed correctly — and an empty bucket is caught for every biome, not
			# just the ones KIND_CAP happens to bound tightly.
			var kinds_present: Dictionary = {}
			for entry_v: Variant in batch:
				kinds_present[int((entry_v as Dictionary).get("kind", ChunkBatch.BoxKind.CUBE))] = true
			# (b) …and never more than this biome is allowed to spend.
			var cap: int = int(kind_cap.get(biome, -1))
			var want: int = kinds_present.size()
			if (nodes.size() != want or cap < 0 or nodes.size() > cap) and not wrong.has(biome):
				var names: Array = []
				for n_v: Variant in nodes:
					names.append((n_v as Node).name)
				wrong[biome] = ("chunk %s built %d (%s); its batch holds %d distinct kinds and its cap is %d"
						% [chunk, nodes.size(), ", ".join(names), want, cap])
			# The forest's cube and sphere buckets by NAME — a count alone would also
			# be satisfied by a cone canopy. It is the one biome whose second bucket
			# is on EVERY tree, so it is the one that can be named unconditionally.
			if biome == forest_value:
				for want_name: String in ["BlockMultiMesh", "BlockMultiMesh_SPHERE"]:
					if parent.get_node_or_null(NodePath(want_name)) == null:
						_fail("a forest chunk's block buckets do not include '%s' — "
								% want_name + "the canopies are BoxKind.SPHERE and the "
								+ "trunks BoxKind.CUBE, nothing else")
			parent.free()

	for biome_name_v: Variant in biome_enum:
		var biome_name: String = biome_name_v
		var value: int = int(biome_enum[biome_name])
		var n: int = int(sampled.get(value, 0))
		if n < BIOME_SAMPLES:
			_fail("only %d chunks of biome %s were measured (wanted %d) in a %dx%d sweep — "
					% [n, biome_name, BIOME_SAMPLES, 2 * BIOME_SWEEP + 1, 2 * BIOME_SWEEP + 1]
					+ "the draw-call bill for that biome is unmeasured, not proven")
		if not kind_cap.has(value):
			_fail("biome %s has no KIND_CAP_BY_NAME row — a new biome must declare how many "
					% biome_name + "block draw calls a chunk of it may spend, or its bill "
					+ "is unbilled rather than free")
		if wrong.has(value):
			_fail("biome %s: %s. One MultiMeshInstance3D per kind PRESENT, and never "
					% [biome_name, wrong[value]]
					+ "more than that biome's KIND_CAP_BY_NAME — the epic y1o ceiling is a chunk "
					+ "with trees AND rocks, which is two extra buckets and no third")
		# HOW OFTEN, not just how bad. The worst case alone reads as "some chunks"
		# when it may be nearly all of them — a cost that is under the cap on every
		# chunk and paid on 90% of them is still most of a web frame, and it is the
		# number an owner's by-eye ruling on a new consumer needs. Printed rather
		# than asserted: the frequency is a design fact for the reader, while the
		# thing that must not drift is the cap above.
		print("  %-8s worst %d block draw call(s), >1 on %d of %d chunks (cap %s)"
				% [biome_name, int(worst.get(value, 0)), int(paying.get(value, 0)),
						n, kind_cap.get(value, "-")])
	terrain.free()
	Sentinel.done("draw_calls_per_biome")


# ============================================================================
# CHECK 6 — world_block.gdshader's UNIFORMS: declared, valued, defaulted
# (bead godot-test1-y1o.35)
# ============================================================================

## The shared block material's shader, and the file that builds that material.
## Read as TEXT rather than through `load()`: headless Godot is the dummy
## rendering driver, so a shader's DEFAULTS come back from the RenderingServer
## unreliably — the same trap as tower_interior's dossier rack, which is why that
## writes `multimesh.buffer` instead of calling `set_instance_transform`. The
## source text is the only thing here that is a measurement.
const BLOCK_SHADER_PATH: String = "res://assets/shaders/world_block.gdshader"
const CHUNK_BATCH_SCRIPT: String = "res://scripts/chunk_batch.gd"

## THE TWO IDENTITY DEFAULTS, and the whole reason this check exists.
##
## Bead y1o.14 added `albedo` and `height_range` to a shader that already drew
## every chunk in the world, and the ENTIRE argument for that being a safe change
## is that both defaults are the IDENTITY of what the shader computed before them:
##
##   albedo        vec4(1.0)        -> `COLOR.rgb * 1.0` is the pre-uniform
##                                     expression bit for bit.
##   height_range  vec2(-0.5, 0.5)  -> `(VERTEX.y - -0.5) / (0.5 - -0.5)` is
##                                     `VERTEX.y + 0.5`, the sweep this shader has
##                                     always computed — a subtraction of -0.5 and
##                                     a division by 1.0, both EXACT in fp32.
##
## So every existing chunk batch renders bit-identically, which is what this
## file's own shared-material assertions rest on. A ONE-CHARACTER edit to either
## number silently re-shades the whole world, and since bead y1o.15 this shader
## has THREE consumers (the chunk batch, fauna herds, the crowd and traffic
## bodies), so more edits are coming. Nothing in the suite read these until now.
const BLOCK_IDENTITY_DEFAULTS: Dictionary = {
	"albedo": [1.0, 1.0, 1.0, 1.0],
	"height_range": [-0.5, 0.5],
}

## The one uniform-declaration pattern, used by the audit and by its own count.
## `uniform <type> <name><rest>;` where <rest> carries the optional hint and the
## optional `= <default>`. Splitting <rest> on its first "=" rather than matching
## the default in the same pattern is what keeps a bare
## `uniform vec2 height_range;` — legal GLSL, silently zero-filled by the
## compiler — VISIBLE as a declaration with no default, instead of simply not
## matching and being compared to nothing. That is altitude_selfcheck's hard-won
## lesson at its own `alt_*` defaults, one shader along.
const UNIFORM_RE: String = "uniform\\s+(\\w+)\\s+(\\w+)([^;]*);"


func _strip_shader_comments(shader_text: String) -> String:
	"""
	Removes `//` and block comments before any uniform is parsed.

	NOT optional, and not defensive: this shader's own header explains `albedo` in
	PROSE that contains the words "as a uniform instead. The default vec4(1.0)",
	and `UNIFORM_RE`'s `[^;]*` tail then ran from that sentence all the way to the
	real declaration's semicolon four lines later — inventing a uniform called
	`tint` with no default AND swallowing the `albedo` declaration whole, so the
	identity leg reported `albedo` as MISSING. Caught by check 6 on its own first
	run against the shipped file. A shader whose comments cannot say the word
	"uniform" is not a shader anybody should have to write.

	ONE PASS WITH AN ALTERNATION, never two passes. Two passes have to pick an
	order and BOTH orders leave a hole: strip block comments first and a `/*`
	written inside a `//` line opens a block that runs to the next `*/` anywhere
	below, deleting every real declaration in between; strip line comments first
	and a `//` inside a block comment ends that line early, leaving the block's
	`*/` to be parsed as code. A single alternation has no order to get wrong —
	whichever delimiter appears FIRST wins, which is exactly what a compiler does.
	"""
	return RegEx.create_from_string("//[^\\n]*|/\\*[\\s\\S]*?\\*/").sub(shader_text, "", true)


func _glsl_default_value(text: String, type_name: String) -> PackedFloat32Array:
	"""
	Parses a GLSL scalar or vector literal into its components.

	Handles the SPLAT — `vec4(1.0)` means all four components — which is exactly
	how the shader spells `albedo`'s identity, so a parser that read only the
	comma-separated form would have skipped the one default this check is most
	about.

	@param text: the literal, e.g. "0.78" or "vec2(-0.5, 0.5)"
	@param type_name: the uniform's declared type, e.g. "float" or "vec4"
	@return: its components, or an EMPTY array if this is not a literal the
	         parser understands — the caller reports that rather than silently
	         comparing against zeros.
	"""
	var body := text.strip_edges()
	var want := 1
	if type_name.begins_with("vec"):
		want = type_name.trim_prefix("vec").to_int()
		var open := body.find("(")
		if open < 0 or not body.ends_with(")"):
			return PackedFloat32Array()
		body = body.substr(open + 1, body.length() - open - 2)
	var out := PackedFloat32Array()
	for part: String in body.split(",", false):
		if not part.strip_edges().is_valid_float():
			return PackedFloat32Array()
		out.append(part.strip_edges().to_float())
	if out.size() == 1 and want > 1:
		while out.size() < want:  # GLSL's splat: one argument fills every component
			out.append(out[0])
	if out.size() != want:
		return PackedFloat32Array()
	return out


func _block_shader_problems(shader_text: String, batch_text: String) -> Array:
	"""
	The whole of check 6 as a PURE function of the two source texts, so the
	negative controls can drive it on a MUTATED copy and prove each leg really
	bites. A mutation control that has to re-implement the check is a control that
	measures its own copy.

	@param shader_text: world_block.gdshader's source
	@param batch_text: chunk_batch.gd's source
	@return: one string per problem; empty means the pair is well formed.
	"""
	var problems: Array = []
	var uniform_re := RegEx.new()
	uniform_re.compile(UNIFORM_RE)
	var declared: Dictionary = {}    # name -> type
	var defaults: Dictionary = {}    # name -> literal text; ABSENT means no default
	for m: RegExMatch in uniform_re.search_all(_strip_shader_comments(shader_text)):
		declared[m.get_string(2)] = m.get_string(1)
		var rest := m.get_string(3)
		var eq := rest.find("=")
		if eq >= 0:
			defaults[m.get_string(2)] = rest.substr(eq + 1).strip_edges()

	# NON-VACUITY, before anything is asserted about the set: a regex that matched
	# nothing would pass every loop below by having nothing to loop over, and a
	# RENAME would silently retire both identity legs while looking green.
	if declared.is_empty():
		problems.append("no uniform declaration was parsed out of %s — check 6 measured nothing"
				% BLOCK_SHADER_PATH)
	for uniform_name: String in BLOCK_IDENTITY_DEFAULTS:
		if not declared.has(uniform_name):
			problems.append(("%s declares no '%s' uniform. It is one of the two IDENTITY "
					% [BLOCK_SHADER_PATH, uniform_name])
					+ "defaults bead y1o.14's safety argument rests on — renaming it does not "
					+ "retire that argument, it only stops anything from checking it")

	# ---- a. every declared uniform is DEFAULTED ------------------------------
	# The chunk batch pushes two of the four and leaves the rest to the shader's
	# own defaults, so an undefaulted uniform is not a style nit: it is a value
	# nobody supplies, which GLSL zero-fills. `height_range` at vec2(0.0) is a
	# division by zero across every box in the world.
	for uniform_name: String in declared:
		if not defaults.has(uniform_name):
			problems.append(("%s declares 'uniform %s %s;' with NO default. "
					% [BLOCK_SHADER_PATH, declared[uniform_name], uniform_name])
					+ "Every consumer that does not push it then draws GLSL's zero-fill "
					+ "instead of the value the shader's own header promises")

	# ---- b. the two identity defaults ARE the identity -----------------------
	for uniform_name: String in BLOCK_IDENTITY_DEFAULTS:
		if not defaults.has(uniform_name):
			continue  # leg (a) has already reported it
		var want: Array = BLOCK_IDENTITY_DEFAULTS[uniform_name]
		var got := _glsl_default_value(defaults[uniform_name], String(declared[uniform_name]))
		if got.is_empty():
			problems.append("%s declares '%s = %s', which check 6 cannot read as a %s literal"
					% [BLOCK_SHADER_PATH, uniform_name, defaults[uniform_name],
							declared[uniform_name]])
			continue
		var same := got.size() == want.size()
		if same:
			for i in got.size():
				if absf(got[i] - float(want[i])) > EPS:
					same = false
		if not same:
			problems.append(("%s declares '%s = %s' but the IDENTITY is %s. "
					% [BLOCK_SHADER_PATH, uniform_name, defaults[uniform_name], str(want)])
					+ "That default is not a preference: it is the whole argument that adding "
					+ "this uniform left every existing chunk batch rendering BIT-IDENTICALLY "
					+ "(COLOR.rgb * 1.0, and (VERTEX.y - -0.5) / 1.0 = VERTEX.y + 0.5, both "
					+ "exact in fp32). Change it and the world is re-shaded with nothing red")

	# ---- c + d. what the SHARED material actually pushes ---------------------
	# Scoped to _get_shared_block_material's own body: the other two consumers
	# (fauna herds, crowd/traffic) bind their own spans deliberately, and
	# crowd_selfcheck / traffic_selfcheck assert those against the mesh they draw.
	# This leg is the chunk batch's alone.
	# The "(" closes the PREFIX case: a plain name find would also match a
	# `_get_shared_block_material_web` sibling and audit the wrong function's body.
	var start := batch_text.find("static func _get_shared_block_material(")
	if start < 0:
		problems.append(("%s has no _get_shared_block_material() — check 6 cannot tell what "
				% CHUNK_BATCH_SCRIPT) + "the shared material pushes")
		return problems
	var end := batch_text.find("\nstatic func ", start + 1)
	if end < 0:
		end = batch_text.length()
	var push_re := RegEx.new()
	push_re.compile("set_shader_parameter\\(\"(\\w+)\"")
	var pushed: Dictionary = {}
	for m: RegExMatch in push_re.search_all(batch_text.substr(start, end - start)):
		pushed[m.get_string(1)] = true
	if pushed.is_empty():
		problems.append("_get_shared_block_material() pushes no shader parameter at all — "
				+ "legs (c) and (d) would pass vacuously")

	# c. the identity only holds while the chunk batch LEAVES THEM ALONE.
	for uniform_name: String in BLOCK_IDENTITY_DEFAULTS:
		if pushed.has(uniform_name):
			problems.append(("_get_shared_block_material() pushes '%s'. " % uniform_name)
					+ "The shared material must leave both identity uniforms at their declared "
					+ "defaults — a pushed value is a SECOND place the world's shading is "
					+ "decided, and the one the shader's header argues from would no longer be "
					+ "the one that runs")

	# d. a set_shader_parameter typo is SILENT in Godot: no error, no warning, the
	# value simply goes nowhere and the uniform keeps its default. That is
	# `block_roughness` quietly reverting to 0.85 with SHARED_BLOCK_ROUGHNESS
	# still sitting in the source looking authoritative.
	for uniform_name: String in pushed:
		if not declared.has(uniform_name):
			problems.append(("_get_shared_block_material() pushes '%s' but %s declares no such "
					% [uniform_name, BLOCK_SHADER_PATH])
					+ "uniform. Godot discards an unknown shader parameter SILENTLY, so the "
					+ "constant beside that call reads as authoritative while the GPU goes on "
					+ "using the shader's default")
	return problems


func _check_block_shader_uniforms() -> void:
	"""
	CHECK 6: every uniform world_block.gdshader declares is DEFAULTED, the two
	IDENTITY defaults are exactly the identity, and the shared block material
	pushes only uniforms that exist and neither of the two identities.

	altitude_selfcheck's `alt_*` audit one shader along, and for the same reason:
	the shader's header ARGUES its defaults are safe, and until this bead nothing
	in the suite read them. Grep the glob before y1o.35 and no *_selfcheck.gd
	mentions `bottom_shade`, `world_block` or `WORLD_BLOCK_SHADER` outside two
	comments in this file.

	FOUR NEGATIVE CONTROLS, one per leg, each driven on a MUTATED COPY of the
	source through the same pure function the real text goes through. Each
	mutation asserts it actually CHANGED the text first — a search string that
	stopped matching would otherwise make its control pass by mutating nothing,
	which is the exact failure a mutation control exists to be immune to.
	"""
	var shader_text := FileAccess.get_file_as_string(BLOCK_SHADER_PATH)
	var batch_text := FileAccess.get_file_as_string(CHUNK_BATCH_SCRIPT)
	if shader_text.is_empty() or batch_text.is_empty():
		_fail("check 6 could not read %s (%d chars) / %s (%d chars)"
				% [BLOCK_SHADER_PATH, shader_text.length(),
						CHUNK_BATCH_SCRIPT, batch_text.length()])
		Sentinel.done("block_shader_uniforms")
		return

	for problem: String in _block_shader_problems(shader_text, batch_text):
		_fail(problem)

	# [which leg, which text to mutate, the search string, its replacement]
	var mutations: Array = [
		["b (the identity default)", "shader",
			"uniform vec4 albedo : source_color = vec4(1.0);",
			"uniform vec4 albedo : source_color = vec4(1.0, 0.0, 0.0, 1.0);"],
		["a (every uniform defaulted)", "shader",
			"uniform vec2 height_range = vec2(-0.5, 0.5);",
			"uniform vec2 height_range;"],
		["c (the batch leaves the identities alone)", "batch",
			"_shared_block_material.shader = WORLD_BLOCK_SHADER",
			"_shared_block_material.shader = WORLD_BLOCK_SHADER\n\t\t"
					+ "_shared_block_material.set_shader_parameter(\"albedo\", Color.RED)"],
		["d (a pushed name the shader declares)", "batch",
			"set_shader_parameter(\"block_roughness\"",
			"set_shader_parameter(\"block_roughnes\""],
	]
	for row: Array in mutations:
		var leg: String = row[0]
		var mutated_shader := shader_text
		var mutated_batch := batch_text
		if String(row[1]) == "shader":
			mutated_shader = shader_text.replace(String(row[2]), String(row[3]))
		else:
			mutated_batch = batch_text.replace(String(row[2]), String(row[3]))
		if mutated_shader == shader_text and mutated_batch == batch_text:
			_fail(("check 6's negative control for leg %s mutated NOTHING — its search string "
					% leg)
					+ "'%s' no longer appears in the source, so the control 'proved' the leg "
							% row[2]
					+ "bites by running it on the unmodified text")
			continue
		if _block_shader_problems(mutated_shader, mutated_batch).is_empty():
			_fail(("check 6's leg %s did not fire on a source mutated to break it — " % leg)
					+ "that leg passes vacuously")

	# "declared", not "declared and defaulted": this counts DECLARATIONS. On a
	# passing run leg (a) has already proved every one of them carries a default,
	# but the number itself is the declared set and the line must say so.
	#
	# COVERAGE, stated rather than asserted: only the two IDENTITY defaults are
	# value-checked. `bottom_shade` (0.78) and `block_roughness` (0.85) are checked
	# for EXISTENCE alone, deliberately — the chunk batch pushes its own
	# `BLOCK_BOTTOM_SHADE` (0.60) over the first, so binding the shader default to
	# that constant would encode an equality the code does not claim, while the
	# other two consumers (fauna, crowd/traffic) legitimately run the shader
	# default. Those two numbers are art, not an identity argument.
	var counter := RegEx.new()
	counter.compile(UNIFORM_RE)
	print("[batch] block shader: %d uniform(s) declared, %d identity default(s) value-checked, %d negative control(s) fired"
			% [counter.search_all(_strip_shader_comments(shader_text)).size(),
					BLOCK_IDENTITY_DEFAULTS.size(),
					mutations.size()])
	Sentinel.done("block_shader_uniforms")
