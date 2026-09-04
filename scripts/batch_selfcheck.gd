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
##      is the same rule billed per BIOME on the shipped spawners: forest 2,
##      everything else 1.
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
		_fail("the SCATTERED-BLOCK spawner emitted %d non-CUBE boxes over %d chunks. "
				% [non_cube, sampled]
				+ "Consumers of the kind slot are named beads judged by eye (the "
				+ "forest canopies are y1o.2's, and they are BIOME content, not "
				+ "these blocks) — a silhouette that changed here changed nowhere "
				+ "anybody asked for")
	if many_mmis > 0:
		_fail("%d of %d real field chunks built more than one MultiMeshInstance3D from "
				% [many_mmis, sampled] + "the scattered blocks alone — every kind they "
				+ "emit is the cube, so this must be exactly one. Check 5 bills the "
				+ "biome CONTENT, which is where the forest's second bucket lives")

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
	# The type every kind must hang at this aspect. CONE is the deliberate box.
	var want_type: Dictionary = {
		ChunkBatch.BoxKind.CUBE: "BoxShape3D",
		ChunkBatch.BoxKind.SPHERE: "SphereShape3D",
		ChunkBatch.BoxKind.CONE: "BoxShape3D",
		ChunkBatch.BoxKind.CYLINDER: "CylinderShape3D",
	}
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
			"the Taj's 2.25-aspect dome tier, the one shipped box past the gate"],
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
	THE PRICE OF THE FIRST CONSUMER, measured where it is paid.

	Check 2 proved the MACHINERY costs nothing; this proves the FOREST costs
	exactly one draw call and that nothing else in the field learned to. A forest
	chunk builds TWO MultiMeshInstance3Ds — the cube bucket (trunks, scattered
	blocks) and the sphere bucket (canopies) — and every other biome builds the
	ONE it always did. That is the whole web budget of bead y1o.2, and it is the
	kind of number that drifts silently: a `kind` argument left on a shared
	helper, or a builder copied from the forest, doubles a biome's block draw
	calls with no visual difference worth noticing.

	BUDAPEST IS NOT SWEPT HERE and does not need to be — `spawn_biome_content_in_chunk`
	returns early inside the rect, and budapest_selfcheck check 4 already asserts
	"1 MultiMeshInstance3D" over real city chunks built by the real city builders.
	Two homes for one rule is how they drift apart.

	IT ITERATES THE Biome ENUM, never a list of its own, so a biome added later is
	billed the day its row lands (the BIOME_SPECIES / SPECIES idiom).

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

	# How many MultiMeshInstance3Ds a chunk of each biome may build. One for
	# everybody; the forest's canopies are the one sanctioned second bucket.
	var sampled: Dictionary = {}   # biome value -> chunks measured
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
			var want: int = 2 if biome == forest_value else 1
			if nodes.size() != want and not wrong.has(biome):
				var names: Array = []
				for n_v: Variant in nodes:
					names.append((n_v as Node).name)
				wrong[biome] = "chunk %s built %d (%s), wanted %d" % [chunk, nodes.size(), ", ".join(names), want]
			# The forest's two must be exactly the cube and the sphere bucket —
			# "two nodes" alone would also be satisfied by a cone canopy.
			if biome == forest_value and nodes.size() == 2:
				for want_name: String in ["BlockMultiMesh", "BlockMultiMesh_SPHERE"]:
					if parent.get_node_or_null(NodePath(want_name)) == null:
						_fail("a forest chunk's two block buckets do not include '%s' — "
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
		if wrong.has(value):
			_fail("biome %s: %s. A forest chunk pays +1 draw call for its sphere canopies "
					% [biome_name, wrong[value]]
					+ "and NOTHING ELSE IN THE FIELD PAYS ANYTHING — that is bead y1o.2's "
					+ "whole web budget")
	terrain.free()
	Sentinel.done("draw_calls_per_biome")
