extends SceneTree
## ============================================================================
## CHUNK BATCH SELF-CHECK — the mesh-kind slot (bead godot-test1-y1o.1)
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
##      a batch of nothing but cubes, which is every chunk the world ships today.
##      A bucketing bug that emitted an empty node per kind would quadruple the
##      world's draw calls with no visual difference at all.
##   3. THE CITY SPLITTER LEAVES A NON-CUBE WHOLE. A cut cone is not two cones;
##      cutting works only because a box's pieces are boxes.
##   4. COLLISION IS UNCHANGED BY KIND — still a BoxShape3D of `dimensions`, the
##      conservative bound the climbable-top contract wants.
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

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	_check_unit_meshes_fit_the_cube()
	_check_multimesh_per_kind()
	_check_splitter_carries_kind()
	_check_collision_is_unchanged_by_kind()
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
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
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
	var field_batch: Array = []
	var field_body := StaticBody3D.new()
	var non_cube: int = 0
	var many_mmis: int = 0
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
			for entry_v: Variant in one_batch:
				if int((entry_v as Dictionary)["kind"]) != ChunkBatch.BoxKind.CUBE:
					non_cube += 1
			var one_parent := MeshInstance3D.new()
			ChunkBatch._build_block_multimesh(one_parent, one_batch)
			if _multimeshes(one_parent).size() != 1:
				many_mmis += 1
			one_parent.free()
			one_body.free()
			if field_batch.is_empty():
				field_batch = one_batch
	if sampled < 10:
		_fail("only %d of %d field chunks produced boxes — nothing was measured"
				% [sampled, (2 * FIELD_SWEEP + 1) * (2 * FIELD_SWEEP + 1)])
	if non_cube > 0:
		_fail("the shipped field spawner emitted %d non-CUBE boxes over %d chunks. "
				% [non_cube, sampled]
				+ "This bead adds the SLOT only: nothing in the world may change "
				+ "silhouette until its own consumer bead lands and is judged by eye")
	if many_mmis > 0:
		_fail("%d of %d real field chunks built more than one MultiMeshInstance3D — "
				% [many_mmis, sampled] + "with no consumer yet, every chunk must "
				+ "build exactly one")

	var planted_rng := RandomNumberGenerator.new()
	planted_rng.seed = 99
	ChunkBatch.create_box(Vector3(1.0, 4.0, 1.0), Vector3(3.0, 3.0, 3.0), 0.0,
			planted_rng, field_batch, field_body, 0.0, Color(0, 0, 0, 0), false,
			ChunkBatch.BoxKind.SPHERE)
	var planted_parent := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(planted_parent, field_batch)
	var planted: Array = _multimeshes(planted_parent)
	if planted.size() != 2:
		_fail("a field chunk carrying one SPHERE built %d MultiMeshInstance3Ds, not 2 "
				% planted.size() + "— a consumer costs exactly +1 draw call per kind")
	else:
		var mat: Material = (planted[0] as MultiMeshInstance3D).material_override
		if (planted[1] as MultiMeshInstance3D).material_override != mat:
			_fail("the planted SPHERE's batch does not share the cube batch's material")
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
	if spheres != 1:
		_fail("a SPHERE %.1f m wide came back as %d entries — a non-cube kind must "
				% [wide.x, spheres]
				+ "be left WHOLE and keep the centre rule, because a cut cone is "
				+ "not two cones")
	body.free()
	terrain.free()
	Sentinel.done("splitter_kind")


# ---------------------------------------------------------------------------
# CHECK 4 — collision is unchanged by kind
# ---------------------------------------------------------------------------

func _check_collision_is_unchanged_by_kind() -> void:
	"""
	A colliding non-cube keeps its BoxShape3D of `dimensions` — conservative (the
	unit mesh fits inside it, check 1) and what the climbable-top contract wants,
	since a flat box top is what `_settle_coin_y` perches a coin on.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var dims := Vector3(2.0, 5.0, 3.0)
	for kind: int in ChunkBatch.BoxKind.values():
		var batch: Array = []
		var body := StaticBody3D.new()
		ChunkBatch.create_box(Vector3(1.0, 2.5, -1.0), dims, 0.0, rng, batch, body,
				0.0, Color(0, 0, 0, 0), true, kind)
		var shapes: Array = body.get_children()
		var name: String = ChunkBatch.BoxKind.find_key(kind)
		if shapes.size() != 1:
			_fail("create_box(kind = %s, collide = true) hung %d shapes, not 1"
					% [name, shapes.size()])
		else:
			var cs := shapes[0] as CollisionShape3D
			var box := (cs.shape if cs != null else null) as BoxShape3D
			if box == null:
				_fail("create_box(kind = %s) hung a %s, not a BoxShape3D — collision "
						% [name, shapes[0].get_class()]
						+ "must stay the entry's bounding box whatever it draws")
			elif box.size != dims:
				_fail("create_box(kind = %s) sized its shape %s, not the dimensions %s"
						% [name, box.size, dims])
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
	Sentinel.done("collision_by_kind")
