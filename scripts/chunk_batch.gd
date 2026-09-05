class_name ChunkBatch
extends RefCounted
## THE BATCH SEAM — every box the world streams goes through this file, and
## nothing in it knows about biomes, seeds or spawners.
##
## Lifted whole out of endless_terrain.gd by bead godot-test1-ftn.1, which is a
## MECHANICAL extraction: not one draw, transform, colour or collision shape
## moved, and a byte-identical world A/B is the bead's acceptance. The reasoning
## came WITH the code — the MultiMesh note, the RNG-sequence discipline in
## create_box, the colour-space conversion, the two spellings of "axis-aligned"
## that have to stay one function — because those are the comments a future
## author needs beside the lines they explain.
##
## WHAT IS HERE: the two halves of a chunk's blocks (create_box appends to the
## batch AND hangs a shape on the chunk's one body; _build_block_multimesh turns
## the batch into the chunk's ONE draw call), the two process-wide shared
## resources they instance, and the city splitter that cuts a box bigger than a
## chunk on the world grid before the centre rule ever sees it.
##
## WHAT IS NOT: any decision about WHERE a box goes. Placement, rarity, hash
## streams, scarcity and footprints stay in endless_terrain.gd — this file is
## handed a centre and a size and never asks why.
##
## STATIC, LIKE landmark_builders.gd, and for its reason: there is no batch
## state to hold, so there is nothing to instantiate. `terrain` is typed Node3D
## in the one function that needs it because endless_terrain.gd declares no
## class_name — the same ponytail note that file carries.
##
## endless_terrain.gd KEEPS one-line forwarders for create_box (600-odd call
## sites, plus landmark_builders' documented contract that a builder does its
## whole job through the terrain's own create_box) and for _build_block_multimesh
## (create_chunk and budapest_selfcheck both call it on the terrain node).
## Everything else here is called on ChunkBatch directly.


# ----------------------------------------------------------------------------
# SHARED RESOURCES FOR MULTIMESH BLOCK RENDERING (created once, reused forever)
# ----------------------------------------------------------------------------
##
## EDUCATIONAL NOTE — what a MultiMesh is and why we use it here:
## Previously every decorative block was its own MeshInstance3D with its OWN
## BoxMesh and its OWN StandardMaterial3D. With ~12 scattered objects + stacks +
## big feature structures per chunk and 121 active chunks, that is *thousands* of
## separate meshes and materials — and the GPU has to issue a separate "draw call"
## for each one. Draw calls are expensive (especially in a browser/WebGL), so this
## is the main thing that makes the web build stutter.
##
## A MultiMesh fixes this. It is ONE mesh (a single unit cube) drawn MANY times in
## a SINGLE draw call. Each "instance" gets its own Transform3D (so we can scale +
## rotate + move the unit cube to land exactly where a block should be) and its own
## per-instance Color (so each block keeps its individual earthy colour). One
## MultiMeshInstance3D per chunk therefore renders every block in that chunk with
## essentially one draw call instead of dozens — a huge win, with no visual change.
##
## We keep TWO resources shared across ALL chunks (creating them once avoids
## re-allocating identical resources for every chunk):
##   1. a unit (1×1×1) BoxMesh — the geometry every instance reuses; per-instance
##      scale in the transform stretches it to each block's real dimensions.
##   2. a StandardMaterial3D with `vertex_color_use_as_albedo = true` — this tells
##      the shader to use each instance's per-instance Color AS its albedo, so the
##      single shared material still paints every block its own earthy colour.

## Lazily-created shared unit BoxMesh (size 1×1×1). The MultiMesh instance
## transforms carry the per-axis scale, so this single cube becomes every block.
static var _shared_unit_box_mesh: BoxMesh

## WHICH SHAPE a batch entry draws (bead godot-test1-y1o.1, epic y1o "get rid of
## blocks"). Before this the world had exactly one silhouette — the shared unit
## cube — so a tree canopy, a boulder and a dune were all scaled boxes, which is
## most of what reads as Minecraft.
##
## THE ONE RULE, and everything downstream rests on it: **every unit mesh fits
## the UNIT CUBE exactly**, so an entry's `dimensions` still means its BOUNDING
## BOX whichever kind it is. That is what keeps prop_selfcheck's cube-corner
## reach helpers and landmark_selfcheck's extent helpers VALID UPPER BOUNDS with
## no edit — a sphere inscribed in the cube can only ever reach less far than the
## cube's corner — and it is what keeps world_block.gdshader's gradient
## meaningful, since its whole trick is that model-space `VERTEX.y` runs
## -0.5 .. +0.5 over any instance. `batch_selfcheck` asserts it per kind.
##
## COLLISION FOLLOWS THE KIND since bead godot-test1-y1o.10 — a near-round SPHERE
## collides as a `SphereShape3D` and a near-round CYLINDER as a `CylinderShape3D`,
## both INSCRIBED in `dimensions` exactly like the mesh. `collision_shape_for()`
## below is the one home of that mapping and carries the whole argument, including
## why a squashed box and every CONE keep their `BoxShape3D`. The shape COUNT is
## untouched: every colliding entry still hangs exactly one shape.
##
## THE RULE FOR CONSUMERS is therefore no longer "non-CUBE means don't stand on
## it" — a cylinder drum has a real flat top and a sphere a real curved one — but
## it IS still: a CONE collides as a box, so nothing may stand on a cone, and a
## climbable footprint (`obstacles`' flat-top contract, `_settle_coin_y`) wants a
## CUBE, a CYLINDER or a ROCK and never a SPHERE.
##
## ROCK IS THE ONE KIND SHAPED BY A GAMEPLAY CONTRACT rather than by a primitive
## (bead godot-test1-y1o.3). Rocks and boulders are the second-most-frequent block
## after trees and they are in EVERY biome, and MOST of them carry a CLIMBABLE
## footprint — the "rest from crocodiles" role the bare cubes used to play. So the
## silhouette had to lose the crate WITHOUT losing the flat top: a squashed SPHERE
## would have been the lazy answer and is wrong, because a sphere's surface falls
## away from the box top and the hero would stand floating over the rim. ROCK is
## therefore a faceted dome with a FLAT LID at exactly y = +0.5 and a flat base at
## y = -0.5, and it keeps the `BoxShape3D` of every other flat-topped kind — so
## every `top` a rock builder already recorded is still the surface you land on,
## byte for byte, and `_settle_coin_y` perches exactly where it did.
enum BoxKind { CUBE, SPHERE, CONE, CYLINDER, ROCK }

## Widest a round box may be, as a multiple of its narrowest axis, before its
## collider falls back to the bounding box. Read only by collision_shape_for(),
## whose docstring carries the measurement and the reasoning.
const ROUND_COLLIDER_MAX_ASPECT: float = 1.6

## Lazily-created shared unit meshes for the NON-CUBE kinds, keyed by BoxKind.
## The cube keeps its own `static var` above because it is also handed out on its
## own (the artifact accent instances it directly).
static var _shared_unit_meshes: Dictionary = {}

## Segment counts for the round kinds. THE FACETS ARE THE STYLE, not a budget
## compromise: style direction A is faceted low-poly, and the x7k clouds already
## shipped on the same reasoning. They are also what keeps a canopy affordable —
## a sphere at 8 x 4 is 64 triangles against a cube's 12.
const UNIT_SPHERE_RADIAL: int = 8
const UNIT_SPHERE_RINGS: int = 4
const UNIT_CYLINDER_RADIAL: int = 8
const UNIT_CONE_RADIAL: int = 6

## THE ROCK'S PROFILE, and it is the whole of the kind (bead godot-test1-y1o.3).
## Each row is one horizontal ring: `y` in unit-cube space and `r` as a fraction of
## the 0.5 half-extent. Read top-down the way the silhouette reads: a flat lid, a
## shoulder that swells to the full half-extent, and a base tucked back under it.
##
##   * The LID sits at y = +0.5 and is WIDE (0.80 of the half-extent). It is the
##     climbable surface, and the wider it is the less of the `BoxShape3D` top
##     hangs over open air — the one honest cost of keeping the box collider, and
##     the reason this is not a taste knob.
##   * The SHOULDER is the widest ROW at 1.0 — but the jitter below subtracts from
##     it like every other, so the widest VERTEX on the built mesh lands at 0.943
##     of the half-extent, not at 1.0. The row's job is to say where the swell is,
##     not to promise the box is filled.
##   * The BASE is tucked in (0.86), which is what makes the thing sit on the
##     ground like a boulder rather than stand on it like a bollard.
##
## `UNIT_ROCK_RADIAL` sides x 3 bands + two caps = 64 triangles, exactly the
## sphere's bill. `UNIT_ROCK_JITTER` then pulls each vertex's radius IN by up to
## that fraction off a fixed-seed stream (never `run_seed` — this mesh is built
## once per PROCESS and shared by every rock in the world), which is what stops
## eight identical facets reading as a turned prism. It only ever subtracts, so
## the unit-cube fit is true by construction and not by measurement.
const UNIT_ROCK_RADIAL: int = 8
const UNIT_ROCK_JITTER: float = 0.12
const UNIT_ROCK_PROFILE: Array[Vector2] = [
	Vector2(0.5, 0.80),    # the flat lid — you stand here
	Vector2(0.12, 1.00),   # the shoulder — the widest band
	Vector2(-0.22, 0.94),
	Vector2(-0.5, 0.86),   # the base
]

## Lazily-created shared material for the block MultiMesh. `vertex_color_use_as_albedo`
## lets one material show each instance's individual colour. Per-instance roughness
## is NOT supported by MultiMesh (only transform + color are per-instance), so we
## bake a single representative roughness here (0.85, mid-range of the old
## 0.7–1.0 spread). The visual difference is negligible.
##
## COLOUR SPACE: we leave `vertex_color_is_srgb` at its default (false) on purpose —
## the Compatibility (web) renderer IGNORES that flag, so we can't rely on it. Instead
## create_box pre-converts each instance colour with `srgb_to_linear()` before storing
## it, so the per-instance colour is already linear and matches what the OLD
## `albedo_color` (sRGB→linear) path produced. See the COLOUR SPACE note in create_box.
static var _shared_block_material: ShaderMaterial

## The world block shader — style direction A's top-lit gradient (see the file's
## own header for the whole argument). PRELOADED rather than `load()`ed on purpose:
## a missing or renamed shader is then a PARSE error in this script, which every
## self-check that touches the chunk batch already fails on, instead of a null
## material and a silently white world at runtime.
const WORLD_BLOCK_SHADER: Shader = preload("res://assets/shaders/world_block.gdshader")

## A representative roughness for the shared block material. The old per-block code
## picked a random roughness in [0.7, 1.0]; since MultiMesh can't vary roughness
## per instance, we use one mid-range value for all blocks. (We still CONSUME the
## same RNG call in create_box so the deterministic world layout is unchanged.)
const SHARED_BLOCK_ROUGHNESS: float = 0.85

## Style direction A's ONE tuning number: how dark the BOTTOM of every box gets, as
## a fraction of its own colour, fading to 1.0 (full colour) at its top. Handed to
## world_block.gdshader's `bottom_shade` uniform by _get_shared_block_material.
##
## THREE VALUES WORTH KNOWING, and the whole style is retuned by moving between them:
##   1.0  — the KILL SWITCH: the pre-style flat look, byte-for-byte, through this
##          same code path. That is why the gradient's floor is a named constant
##          rather than a literal in the shader, and it is how the A/B renders on
##          bead godot-test1-y1o.7 were taken honestly.
##   0.78 — the value bead y1o.7 specified. Correct, and too subtle to read at
##          street scale on anything but a tall box.
##   0.60 — SHIPPED, chosen from those renders on 2026-09-04. Where the Budapest
##          facades pick up a real ambient-occlusion read down the street canyon
##          and a forest trunk plants itself on the ground.
## It is one number and nothing else reads it, so retuning the look is this line.
const BLOCK_BOTTOM_SHADE: float = 0.60

## Curated block colour ramps (Task 8 of the rendering pass). The old code rolled
## each colour channel independently, which gave muddy, uncoordinated blocks. Now
## each of the three block "families" is a hand-picked two-colour RAMP sharing a
## warm undertone, and a block samples its ramp with ONE lerp — so every block
## still varies, but along an art-directed line instead of a random RGB cube.
## (The RNG draw count in create_box is unchanged — see the determinism note there.)
const RAMP_SANDSTONE_A := Color(0.72, 0.58, 0.42)  # warm sandstone …
const RAMP_SANDSTONE_B := Color(0.65, 0.38, 0.28)  # … to terracotta
const RAMP_SLATE_A := Color(0.38, 0.40, 0.45)      # slate …
const RAMP_SLATE_B := Color(0.55, 0.58, 0.63)      # … to blue-grey
const RAMP_MOSS_A := Color(0.42, 0.45, 0.26)       # olive …
const RAMP_MOSS_B := Color(0.30, 0.42, 0.28)       # … to moss

## The width below which a piece of a split city box is not a piece at all — see
## _chunk_grid_spans. Well above the f32 rounding on a world coordinate at the
## city's X (~0.24 mm), well below the thinnest thing any builder draws.
const SPAN_EPS: float = 0.001


static func _get_shared_unit_box_mesh() -> BoxMesh:
	"""
	Returns the shared unit (1×1×1) BoxMesh used by every block MultiMesh,
	creating it on first use. One cube reused everywhere; per-instance transforms
	scale it to each block's real size.
	"""
	if _shared_unit_box_mesh == null:
		_shared_unit_box_mesh = BoxMesh.new()
		_shared_unit_box_mesh.size = Vector3.ONE  # unit cube; scaled per-instance
	return _shared_unit_box_mesh

static func unit_mesh(kind: int) -> Mesh:
	"""
	The shared unit mesh for one BoxKind, created on first use and then reused by
	every chunk for the rest of the process — the cube's lazy singleton, one table
	wider.

	EVERY ONE OF THEM FITS THE UNIT CUBE, which is the enum's whole contract:
	SphereMesh at radius 0.5 / height 1.0 and CylinderMesh at radius 0.5 /
	height 1.0 are both centred on the origin and span -0.5 .. +0.5 on all three
	axes, and a cone is that cylinder with `top_radius = 0`. An inscribed polygon
	only ever sits INSIDE the circle it is inscribed in, so lowering a segment
	count can never break the bound. The ROCK is the one kind with no primitive
	behind it — Godot has no flat-topped dome — so it is built from
	UNIT_ROCK_PROFILE, whose own rule (radii at or under the half-extent, a jitter
	that only subtracts) makes the fit structural in the same way.

	An UNKNOWN kind degrades to the cube rather than returning null: a null mesh
	is an invisible chunk with no error anywhere, and this is the one place a bad
	int from a future consumer can arrive.
	"""
	if kind == BoxKind.CUBE:
		return _get_shared_unit_box_mesh()
	if _shared_unit_meshes.has(kind):
		return _shared_unit_meshes[kind]
	var mesh: Mesh
	match kind:
		BoxKind.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = UNIT_SPHERE_RADIAL
			sphere.rings = UNIT_SPHERE_RINGS
			mesh = _flat_faceted_mesh(sphere)
		BoxKind.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			cyl.radial_segments = UNIT_CYLINDER_RADIAL
			mesh = _flat_faceted_mesh(cyl)
		BoxKind.CONE:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = UNIT_CONE_RADIAL
			mesh = _flat_faceted_mesh(cone)
		BoxKind.ROCK:
			mesh = _build_unit_rock_mesh()
		_:
			return _get_shared_unit_box_mesh()
	_shared_unit_meshes[kind] = mesh
	return mesh

static func _flat_faceted_mesh(primitive: PrimitiveMesh) -> ArrayMesh:
	"""
	Converts a primitive mesh into an unindexed triangle mesh with flat (per-face)
	normals (bead godot-test1-y1o.9). Style direction A requires faceted low-poly
	shading rather than Gouraud-smooth shading.
	"""
	var arr: Array = primitive.get_mesh_arrays()
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var has_uv := not uvs.is_empty()
	var count := idx.size() if not idx.is_empty() else verts.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for j in count:
		var i: int = idx[j] if not idx.is_empty() else j
		if has_uv:
			st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	st.deindex()
	st.generate_normals()
	return st.commit()

static func _build_unit_rock_mesh() -> ArrayMesh:
	"""
	The unit ROCK: a faceted boulder inscribed in the unit cube, with a FLAT LID at
	y = +0.5 (bead godot-test1-y1o.3). See UNIT_ROCK_PROFILE for the silhouette and
	the BoxKind banner for why the lid — not the roundness — is the point.

	It is hand-built rather than derived from a `PrimitiveMesh` because Godot has
	no flat-topped dome; the profile table IS the shape, so restyling the rock is
	editing four numbers rather than this loop.

	THE JITTER ONLY EVER SUBTRACTS, which is the whole of the unit-cube proof: every
	ring radius starts at or below the 0.5 half-extent and the draw scales it DOWN,
	so no vertex can leave the cube however the table is retuned. The lid and the
	base keep their exact y, so the mesh spans the full height batch_selfcheck
	demands and the collider's top face is the drawn one.

	The stream is a FIXED seed. This mesh is built once per process and shared by
	every rock in every chunk, so `run_seed` would make one boulder's silhouette a
	property of the whole world — and it costs the chunk streams nothing either way,
	since choosing a kind draws nothing at all.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0C0FFEE

	# Radii first, so a ring is one row of numbers and the triangle loop below is
	# pure topology. rings[band][side] is the horizontal distance from the axis.
	var rings: Array[PackedFloat32Array] = []
	for band: Vector2 in UNIT_ROCK_PROFILE:
		var radii := PackedFloat32Array()
		for _s in UNIT_ROCK_RADIAL:
			radii.append(band.y * 0.5 * (1.0 - rng.randf() * UNIT_ROCK_JITTER))
		rings.append(radii)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var ring_point := func(band: int, side: int) -> Vector3:
		var a: float = TAU * float(side % UNIT_ROCK_RADIAL) / float(UNIT_ROCK_RADIAL)
		var r: float = rings[band][side % UNIT_ROCK_RADIAL]
		return Vector3(cos(a) * r, UNIT_ROCK_PROFILE[band].x, sin(a) * r)

	# The flanks, band by band. Winding is CLOCKWISE seen from OUTSIDE, which is
	# Godot's front face — get it backwards and every rock in the world is
	# backface-culled into an invisible hole with no error anywhere.
	for band in range(UNIT_ROCK_PROFILE.size() - 1):
		for side in UNIT_ROCK_RADIAL:
			var t0: Vector3 = ring_point.call(band, side)
			var t1: Vector3 = ring_point.call(band, side + 1)
			var b0: Vector3 = ring_point.call(band + 1, side)
			var b1: Vector3 = ring_point.call(band + 1, side + 1)
			for v: Vector3 in [t0, b0, b1, t0, b1, t1]:
				st.add_vertex(v)

	# The lid and the base, each a fan from its own centre. The lid is the surface
	# the climbability contract is about; the base is drawn because a rock sitting
	# in a dune's flank or on a slope shows its underside.
	var lid_c := Vector3(0.0, UNIT_ROCK_PROFILE[0].x, 0.0)
	var base_band: int = UNIT_ROCK_PROFILE.size() - 1
	var base_c := Vector3(0.0, UNIT_ROCK_PROFILE[base_band].x, 0.0)
	for side in UNIT_ROCK_RADIAL:
		for v: Vector3 in [lid_c, ring_point.call(0, side), ring_point.call(0, side + 1)]:
			st.add_vertex(v)
		for v: Vector3 in [base_c, ring_point.call(base_band, side + 1), ring_point.call(base_band, side)]:
			st.add_vertex(v)

	st.generate_normals()
	return st.commit()

static func _get_shared_block_material() -> ShaderMaterial:
	"""
	Returns the shared block material used by every block MultiMesh, creating it on
	first use. It is WORLD_BLOCK_SHADER, style direction A's top-lit gradient, and it
	does what the StandardMaterial3D before it did — the per-instance MultiMesh Color
	IS the albedo (that is what paints all the earthy browns/greys/mossy greens off
	one material), at SHARED_BLOCK_ROUGHNESS — plus a per-box vertical gradient
	darkening each box toward its own foot. Read the shader's header for why that
	gradient costs no per-instance data and no change to the MultiMesh layout.

	STILL ONE MATERIAL FOR THE WHOLE WORLD: the lazy singleton is unchanged, so the
	batching story ("one MultiMesh + one material per chunk") is exactly what it was.
	"""
	if _shared_block_material == null:
		_shared_block_material = ShaderMaterial.new()
		_shared_block_material.shader = WORLD_BLOCK_SHADER
		# Single representative roughness (see SHARED_BLOCK_ROUGHNESS note above) —
		# the same constant, now handed to the shader instead of to a
		# StandardMaterial3D property.
		_shared_block_material.set_shader_parameter("block_roughness", SHARED_BLOCK_ROUGHNESS)
		_shared_block_material.set_shader_parameter("bottom_shade", BLOCK_BOTTOM_SHADE)
	return _shared_block_material

static func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0), collide: bool = true, kind: int = BoxKind.CUBE) -> void:
	"""
	Register one box for rendering AND register its physics collision shape. Used for
	cube blocks and for the flat slabs that make up terraced mounds.

	VISUALS vs COLLISION are DECOUPLED (Tasks 4 + 5 of the perf plan):
	- VISUALS (Task 4): this function no longer instances a MeshInstance3D +
	  StandardMaterial3D per block. Instead it appends one
	  { "transform": Transform3D, "color": Color, "kind": int } entry to `block_batch`. The caller
	  (create_chunk) later turns the whole batch into ONE MultiMeshInstance3D, so all
	  of a chunk's blocks draw in a single draw call instead of dozens (see this
	  file's MultiMesh banner and _build_block_multimesh below). The blocks look EXACTLY
	  the same — same shapes, sizes, yaw and earthy-colour ranges — only how they're
	  SUBMITTED to the GPU changed.
	- COLLISION (Task 5): this function no longer creates a per-block StaticBody3D.
	  Instead it adds just a CollisionShape3D (with the shape collision_shape_for()
	  picks for this `kind`) as a child of the
	  CHUNK'S SINGLE shared `block_body`, positioning/rotating that shape node where
	  the block is.

	  WHY ONE BODY WITH MANY SHAPES == MANY ONE-SHAPE BODIES (for static geometry):
	  a StaticBody3D's job is to give its CollisionShape3D children a physics presence
	  in the world; the body itself doesn't move (static). Godot's physics engine
	  collides against each individual SHAPE — at that shape's own world transform —
	  regardless of whether the shapes are spread across many bodies or grouped under
	  one. The OLD code put each block's shape at the block's transform via the BODY's
	  position/rotation (shape sat at the body's local origin). The NEW code puts that
	  same transform directly on the CollisionShape3D node instead (it's a Node3D, so
	  it has its own position/rotation), giving the shape the IDENTICAL world placement.
	  So the player still can't walk through a block, and a crocodile's avoidance
	  raycast still hits it, byte-for-byte as before — we've only changed how the
	  collision nodes are GROUPED, not where any collision surface is. The payoff is
	  ~25× fewer nodes for blocks (one body per chunk instead of one per block), a real
	  CPU/web win with zero behavioural change.

	  The MultiMesh (block_batch → MultiMeshInstance3D) and this collision body are the
	  TWO HALVES of each chunk's blocks: one renders them, one collides with them.

	@param center_pos: Box centre position, local to the chunk (Y is the centre,
	                   so pass height/2 to sit a box on the ground)
	@param dimensions: Full box size on each axis (width, height, depth)
	@param yaw: Y rotation in radians (0 to keep faces axis-aligned)
	@param rng: The chunk's seeded RNG, used for the random earthy colour
	@param block_batch: Out-param; we append this block's per-instance transform +
	                   colour here for the chunk's MultiMesh.
	@param block_body: The chunk's single shared StaticBody3D; we add this block's
	                   CollisionShape3D child to it (see WHY note above).
	@param tilt: OPTIONAL rotation about the local X axis (radians), applied AFTER
	             yaw. Used by the lost-civilization artifacts for leaning stones.
	             Defaults to 0.0 — the extra Basis is then the identity, so every
	             existing call site produces a bit-for-bit identical transform.
	@param color_override: OPTIONAL colour that replaces the curated-ramp pick when
	                       its alpha > 0 (the default is fully transparent = inert).
	                       Used by artifacts for their weathered palette.
	@param collide: OPTIONAL — when false the box is VISUAL ONLY: it still joins the
	                chunk's MultiMesh batch, but no CollisionShape3D is created for
	                it. Defaults to true, so every pre-existing call site behaves
	                exactly as before. WHY IT EXISTS: forest tree CANOPIES are pure
	                decoration — you walk under leaves, and they sit above head
	                height anyway — so a forest chunk pays collision shapes for its
	                TRUNKS only instead of 3-4x that for trunk + canopy layers. Like
	                `tilt` and `color_override` this changes NO RNG behaviour: the
	                colour and roughness draws above happen identically whatever
	                `collide` is, so the deterministic world layout is untouched.
	@param kind: OPTIONAL — WHICH SHARED UNIT MESH this entry draws AND, through
	             collision_shape_for(), which Shape3D it collides as (see the
	             BoxKind banner up top for the unit-cube rule, the collision rule
	             and the rule for consumers). Defaults to CUBE, so all 600-odd
	             existing call sites are byte-for-byte what they were. Like every
	             optional above it, it COSTS NO RNG DRAW — the colour and
	             roughness draws are unchanged — so choosing a kind can never
	             move a spawn.
	"""
	# ----- Pick the block colour from a curated ramp -----------------------------
	# IMPORTANT (determinism): the chunk's world layout is seeded from this same RNG.
	# If we changed how many random numbers we draw here, every later block/crocodile/
	# coin in the chunk would shift. The COLOURS changed (per-channel randoms → curated
	# ramps, see the RAMP_* consts up top), but the DRAWS did not: same randi_range(0,2)
	# selector, then per branch the SAME number of randf_range calls with the SAME
	# argument ranges as the old code. The FIRST draw in each branch becomes the ramp
	# position `t` (normalised to 0..1 via inverse_lerp of its own range); the extra
	# draws that used to feed the other channels are consumed and DISCARDED purely to
	# advance the RNG — exactly like the roughness discard below. Keeping the calls
	# textually parallel to the old ones makes the sequence preservation auditable.
	var chosen_color: Color
	var color_choice := rng.randi_range(0, 2)
	match color_choice:
		0:  # Warm sandstone → terracotta (was: brown rocks, 3 draws — still 3)
			var t := inverse_lerp(0.3, 0.5, rng.randf_range(0.3, 0.5))
			rng.randf_range(0.2, 0.4)  # discarded — RNG-sequence padding (see note above)
			rng.randf_range(0.1, 0.3)  # discarded — RNG-sequence padding
			chosen_color = RAMP_SANDSTONE_A.lerp(RAMP_SANDSTONE_B, t)
		1:  # Slate → blue-grey (was: gray stones, 1 draw — still 1)
			var t := inverse_lerp(0.3, 0.6, rng.randf_range(0.3, 0.6))
			chosen_color = RAMP_SLATE_A.lerp(RAMP_SLATE_B, t)
		2:  # Olive → moss (was: dark green, 3 draws — still 3)
			var t := inverse_lerp(0.1, 0.3, rng.randf_range(0.1, 0.3))
			rng.randf_range(0.3, 0.5)  # discarded — RNG-sequence padding
			rng.randf_range(0.1, 0.3)  # discarded — RNG-sequence padding
			chosen_color = RAMP_MOSS_A.lerp(RAMP_MOSS_B, t)

	# Still DRAW the roughness random value to keep the RNG sequence identical to the
	# old code (so the procedural world is unchanged). The value itself is discarded:
	# MultiMesh can't vary roughness per instance, so the shared material uses one
	# representative roughness (SHARED_BLOCK_ROUGHNESS). The visual difference between
	# a fixed 0.85 and the old 0.7–1.0 spread is negligible. We DON'T store the result —
	# the CALL must stay (it advances the RNG), but the value is unused, so calling
	# randf_range purely for its determinism side effect is enough.
	rng.randf_range(0.7, 1.0)

	# ----- Optional colour override (artifacts) ----------------------------------
	# Applied AFTER the ramp match on purpose: the ramp draws above belong to the
	# CALLER'S RNG stream and must always happen to keep that stream's sequence
	# intact. Ordinary chunk blocks pass the shared chunk RNG (where skipping draws
	# would shift the whole world); artifacts pass their own private RNG, so the
	# discarded draws cost nothing. Either way the shared-stream discipline of this
	# function stays untouched — we only swap which colour VALUE gets used.
	if color_override.a > 0.0:
		chosen_color = color_override

	# ----- Append this block to the chunk's MultiMesh batch (VISUALS) ------------
	# A MultiMesh instance is just a Transform3D applied to the shared UNIT cube.
	# We build the basis as: rotate around UP by `yaw`, THEN scale each LOCAL axis by
	# `dimensions` — so the 1×1×1 cube becomes a (w, h, d) box turned by yaw. The
	# transform origin is `center_pos`, which is LOCAL to the chunk (same convention
	# the old per-block MeshInstance3D.position used). Because the MultiMeshInstance3D
	# is parented to the chunk at local origin, these local transforms land the blocks
	# in exactly the same spots as before.
	#
	# WHY `scaled_local` (NOT `scaled`): the order of scale vs rotation matters.
	#   * `Basis.scaled(dimensions)` post-multiplies each ROW → it scales in the
	#     PARENT/global frame, composing as `S * R`.
	#   * `Basis.scaled_local(dimensions)` scales in the basis's OWN/local frame
	#     (after the rotation), composing as `R * S`.
	# The collision path below builds a BoxShape3D sized to `dimensions` on a
	# CollisionShape3D that is THEN rotated by `yaw` — i.e. local-space scale, `R * S`.
	# We match that here with `scaled_local` so the rendered box and its collision
	# shape share the EXACT same transform. For an axis-aligned cube or a yaw of 0 the
	# two orders are identical, so every block in the game today looks the same either
	# way; but for a FUTURE non-uniform block at a non-zero yaw, `S * R` would shear /
	# mis-scale the visual relative to the (unchanged) collision shape — a latent
	# desync. Using `scaled_local` keeps visual and collision in lockstep for all cases.
	#
	# COLOUR SPACE (must match the old look exactly): the OLD per-block code set
	# `StandardMaterial3D.albedo_color = chosen_color`, and Godot treats albedo_color as
	# sRGB — it converts sRGB→linear before lighting, which slightly DARKENS the value.
	# A MultiMesh per-instance colour, however, is fed straight into the shader as the
	# vertex colour: with `vertex_color_is_srgb = false` (the default, and the ONLY
	# value the web/Compatibility renderer honours) that sRGB→linear step is skipped, so
	# the raw colour would render brighter/washed-out — a visible regression on desktop
	# AND web. To reproduce the old albedo output renderer-agnostically, we convert the
	# colour to linear OURSELVES here (`srgb_to_linear()`) so the final linear albedo
	# equals srgb_to_linear(chosen_color), exactly as the old material produced. This is
	# a pure value transform on an already-computed Color — it consumes NO RNG, so the
	# deterministic world layout is unchanged.
	#
	# TILT (artifacts): the rotation is built ONCE as `Basis(UP, yaw) * Basis(RIGHT,
	# tilt)` — yaw first, then a lean about the local X axis — and that SAME `rot` is
	# used for both halves: the visual gets `rot.scaled_local(dimensions)` (still the
	# `R * S` order documented above) and the collision shape below gets plain `rot`
	# on its own transform. Sharing one basis is what keeps a TILTED box's visual and
	# collision in lockstep. With the default `tilt == 0.0` the extra Basis is the
	# identity, so this transform is bit-for-bit what the yaw-only code produced.
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	#
	# `kind` IS ALWAYS WRITTEN, never written only when it is not CUBE. The entry
	# is a UNIFORM SHAPE: budapest_selfcheck's determinism A/B and prop_selfcheck's
	# purity check compare whole dicts (through var_to_bytes and `!=`), so a key
	# that is present on some entries and absent on others is a difference between
	# two runs that agree about every box.
	block_batch.append({
		"transform": Transform3D(rot.scaled_local(dimensions), center_pos),
		"color": chosen_color.srgb_to_linear(),
		"kind": kind,
	})

	# ----- Register the collision shape on the CHUNK'S shared body (COLLISION) ----
	# Instead of giving this block its OWN StaticBody3D (the old, node-heavy way), we
	# create just a CollisionShape3D and hang it on the chunk's single `block_body`.
	# The shape node carries the block's transform itself: we set its local
	# position = center_pos and rotation.y = yaw — the SAME chunk-local convention the
	# visual MultiMesh instance uses, and the same transform the old per-block body
	# applied. Because block_body is parented to the chunk (and the chunk is placed in
	# the world), this shape lands at the IDENTICAL world position/orientation the old
	# per-block body produced, so collision is byte-for-byte unchanged.
	#
	# Default collision layer/mask (1/1) — block_body never sets them, exactly like the
	# old per-block bodies, so the player's collision and crocodile avoidance raycasts
	# keep hitting blocks the same way.
	# The shape reuses the SAME `rot` basis the visual used (see the TILT note
	# above) via a whole-transform assignment — for the default tilt of 0 this is
	# exactly the old `position = center_pos; rotation.y = yaw` pair, and for a
	# tilted artifact stone it keeps collision matched to the leaning visual.
	#
	# VISUAL-ONLY BOXES: `collide == false` returns here, having already appended
	# the visual instance and consumed the exact same RNG draws. Only the physics
	# node is skipped — see the @param note above for why canopies want this.
	if not collide:
		return

	# ONE SHAPE PER KIND, resolved by collision_shape_for() — see its docstring
	# for the aspect rule and why a squashed round box keeps its box. The shape
	# node carries the SAME `rot` the visual did, which is what puts a cylinder's
	# axis and a yawed box's faces where the mesh drew them.
	var collision_shape := CollisionShape3D.new()
	collision_shape.transform = Transform3D(rot, center_pos)
	collision_shape.shape = collision_shape_for(kind, dimensions)

	# Add to the shared per-chunk body. (block_body is parented to the chunk by
	# create_chunk once generation finishes, so all these shapes unload with the chunk.)
	block_body.add_child(collision_shape)


static func collision_shape_for(kind: int, dimensions: Vector3) -> Shape3D:
	"""
	The collision shape one batch entry hangs on the chunk's body — the ONE home
	of "which `Shape3D` does a `BoxKind` collide as" (bead godot-test1-y1o.10).

	Until this bead every kind collided as a `BoxShape3D` of `dimensions`, which
	is conservative but WRONG TO WALK INTO: you stop 0.15-0.6 m short of a ball on
	a diagonal and can stand on an invisible flat square over it. The field spends
	152 colliding SPHEREs and 852 colliding CYLINDERs (Zugspitze scree, Trevi reef,
	Space Needle foot pads, Rushmore boulders, Colosseum piers, Kinderdijk drums,
	the Atomium base), so that is most of the round stone in the game.

	  SPHERE   -> SphereShape3D, radius = the SMALLEST half-extent
	  CYLINDER -> CylinderShape3D, radius = the smaller RADIAL half-extent,
	              height = `dimensions.y`
	  ROCK, CONE, CUBE, anything unknown -> BoxShape3D of `dimensions`

	THE ROCK'S BOX IS THE FEATURE, not the fallthrough (bead godot-test1-y1o.3).
	Its whole reason to be a kind of its own is that its lid is FLAT and at exactly
	the box's top face, so the boulder you climb has the surface where every rock
	builder's recorded `top` already promised it. Giving it a round collider would
	undo precisely the thing it was drawn for.

	WHAT IT COSTS IS NEW, AND HERE IS THE NUMBER. Unlike every other kind, the
	CUBE's mesh and its `BoxShape3D` coincide exactly — so a rock is the first
	thing in this game whose collider disagrees with its own silhouette, and the
	disagreement is not small. Measured on the shipped `UNIT_ROCK_PROFILE`: the lid
	is an octagon of circumradius 0.398 against the collider's 0.5 half-extent, so
	about HALF the top face you stand on is over drawn-empty air, guaranteed solid
	only within 0.735 of the half-extent; the base ring reaches ~0.40-0.43, so the
	collider is also a small invisible snag at ground level. That is the price of
	the flat lid landing exactly where every recorded `top` says, and it is why the
	lid's width in UNIT_ROCK_PROFILE is a contract and not a taste knob — but the
	next person to read this should know it is a real cost and not a rounding one.

	THE RADIUS IS THE SMALLEST HALF-EXTENT, so the collider is INSCRIBED in the
	entry's bounding box exactly like the unit mesh is (the BoxKind banner's one
	rule). A collider that poked outside `dimensions` would put stone outside the
	radius a landmark declares and the disc every spawner clears — the footprint
	currency would stop bounding the geometry. Being inside is free: the box it
	replaces was outside the mesh everywhere it mattered.

	THE CYLINDER'S AXIS IS LOCAL Y AND IS NEVER SEARCHED FOR. `CylinderMesh` is
	built along Y and `create_box` scales it with `rot.scaled_local(dimensions)`,
	so the drawn cylinder's axis IS the entry's local +Y; `CylinderShape3D` is
	also a Y-axis primitive and the shape node is handed the same `rot`. "The
	box's long axis" would be a different thing and would stand the collider up
	across a flat drum.

	A SQUASHED ROUND BOX KEEPS ITS BOX, and `ROUND_COLLIDER_MAX_ASPECT` is where
	the line is. A non-uniformly scaled sphere mesh draws an ELLIPSOID, and no
	`SphereShape3D` is an ellipsoid — Godot cannot scale a sphere or a cylinder
	shape non-uniformly. So the inscribed sphere is honest only while the box is
	near-cubic: at aspect `a` it falls `(a - 1)` x the small radius short on the
	LONG axis, while it is exact on the short axes and at every corner and the top
	— which is where the box is worst (a unit sphere's box misses by 0.73 r at a
	corner). At 1.6 the long-axis gap is still under the corner gap it removes, so
	the round shape is never the worse answer; past it the ellipsoid is a real
	ellipsoid and the bounding box is closer on the axes that matter.

	THE GATE IS THE ARGUMENT ABOVE, NOT A FIT TO THE DATA, and the data is why it
	is worth saying: MEASURED over all 28 field builders x 4 seeds (after bead
	y1o.11 reshaped the Taj and Kinderdijk), NOTHING SHIPPED IS PAST IT — 844
	colliding CYLINDERs at 1.00-1.25 in plan and 148 colliding SPHEREs at
	1.00-1.57, the worst being the Taj's chattri dome (1.1 x 0.7 x 1.1) with 0.03
	of headroom. So the fallback has no consumer today and is here for the shape a
	builder will one day squash; `batch_selfcheck` check 4 (d) drives BOTH ends of
	this constant on planted boxes precisely because the world stopped exercising
	one of them.
	"""
	match kind:
		BoxKind.SPHERE:
			var r: float = minf(dimensions.x, minf(dimensions.y, dimensions.z)) * 0.5
			if maxf(dimensions.x, maxf(dimensions.y, dimensions.z)) <= r * 2.0 * ROUND_COLLIDER_MAX_ASPECT:
				var sphere := SphereShape3D.new()
				sphere.radius = r
				return sphere
		BoxKind.CYLINDER:
			# RADIAL only: `dimensions.y` is the axis and is reproduced exactly, so
			# a 20 m column on a 1 m drum is not "squashed" and stays a cylinder.
			var radius: float = minf(dimensions.x, dimensions.z) * 0.5
			if maxf(dimensions.x, dimensions.z) <= radius * 2.0 * ROUND_COLLIDER_MAX_ASPECT:
				var cyl := CylinderShape3D.new()
				cyl.radius = radius
				cyl.height = dimensions.y
				return cyl
	# CONE keeps its box DELIBERATELY, and it is the one kind that stays wrong on
	# purpose: `landmark_builders.gd`'s rule 5c makes a cone the piece that ENDS a
	# taper, so its stone is a point at the top of a box-shaped ledge. Godot has no
	# cone primitive, and the honest alternatives are a `ConvexPolygonShape3D` (a
	# per-entry Resource, so no longer a shared cost) or `collide = false` (which
	# moves a chunk's shape COUNT and is a builder's call, not this seam's).
	# `landmark_selfcheck` check 9c is what keeps a cone off anything standable.
	var box := BoxShape3D.new()
	box.size = dimensions
	return box


static func _build_block_multimesh(parent_chunk: MeshInstance3D, block_batch: Array,
		cast_shadows: bool = true) -> void:
	"""
	Turn a chunk's whole batch of blocks into ONE MultiMeshInstance3D PER MESH KIND
	PRESENT, so every block in the chunk renders in one draw call per silhouette
	(instead of one draw call per block).

	ONE PER KIND *PRESENT* — never one per kind that exists. A MultiMesh holds ONE
	mesh, so a batch carrying two silhouettes cannot be one MultiMesh; but a chunk
	of nothing but cubes builds EXACTLY what it built before this bead — a single
	node, still named "BlockMultiMesh" — because the bucket for every other kind is
	empty and empty buckets emit nothing. Budapest never passes a kind, so the
	city's one-batch invariant (budapest_selfcheck check 4) holds BY CONSTRUCTION;
	that check asserts it anyway, and batch_selfcheck asserts the cube-only shape
	directly.

	THE PER-KIND SPLIT IS THE ONLY SANCTIONED MULTIPLICATION of a chunk's
	MultiMeshInstance3Ds. Do not split the cube batch again — not for shadows (that
	is an owner ruling, see CLAUDE.md), not for materials, not for anything.

	@param parent_chunk: The chunk mesh — we parent the MultiMeshInstance3Ds to it so
	                    they are freed automatically when the chunk unloads (same
	                    per-chunk parenting rule everything else follows).
	@param block_batch: The list of { "transform": Transform3D, "color": Color,
	                    "kind": int } entries create_box appended while building
	                    this chunk's blocks.
	@param cast_shadows: OPTIONAL — false makes this chunk's batch a shadow RECEIVER
	                    only. Defaults to true, so every pre-existing chunk in the
	                    world is byte-for-byte what it was; the ONE caller that
	                    passes false is a Budapest chunk, and the reason is measured
	                    in create_chunk's comment at the call site.

	EDUCATIONAL NOTE — how a MultiMesh renders many blocks in one draw call:
	- A MultiMesh holds ONE `mesh` (here the shared unit cube) plus a flat buffer of
	  per-instance data. We tell it the data layout up front:
	    * `transform_format = TRANSFORM_3D` — each instance carries a full 3D transform
	      (its basis encodes per-axis scale + yaw; its origin is the block centre).
	    * `use_colors = true` — each instance ALSO carries a Color. Paired with the
	      shared material's `vertex_color_use_as_albedo`, that colour becomes the
	      block's albedo, so every block keeps its own earthy shade from one material.
	- `instance_count` must be set BEFORE writing instances; it allocates the buffer.
	- The GPU then draws the unit cube `instance_count` times in essentially one draw
	  call. Fewer draw calls = the big web/WebGL performance win this task is after.
	"""
	# Bucket by kind. An entry with no "kind" is read as a CUBE, which is what lets
	# a self-check hand this function a hand-built batch without restating the key.
	# A kind that is not in the enum is bucketed as a CUBE rather than into a
	# bucket of its own: the loop below walks BoxKind.values(), so its own bucket
	# would never be visited and the boxes would silently vanish from the world.
	# unit_mesh() degrades the same way for the same reason.
	var buckets: Dictionary = {}
	for entry_v: Variant in block_batch:
		var k: int = (entry_v as Dictionary).get("kind", BoxKind.CUBE)
		if BoxKind.find_key(k) == null:
			k = BoxKind.CUBE
		if not buckets.has(k):
			buckets[k] = []
		(buckets[k] as Array).append(entry_v)

	# ENUM ORDER, not dictionary insertion order, so the chunk's children land in
	# the same sequence whatever order the spawners happened to emit their boxes in
	# — the same reason everything else in this world engine is deterministic.
	for k: int in BoxKind.values():
		if not buckets.has(k):
			continue
		_emit_kind_multimesh(parent_chunk, buckets[k], k, cast_shadows)


static func _emit_kind_multimesh(parent_chunk: MeshInstance3D, entries: Array,
		kind: int, cast_shadows: bool) -> void:
	"""
	One kind's bucket becomes one MultiMeshInstance3D. Split out of
	_build_block_multimesh so the loop above reads as the bucketing it is; the
	body below is what that function has always done.
	"""
	# Build the MultiMesh and declare its per-instance data layout.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D  # per-instance 3D transform
	mm.use_colors = true                          # per-instance colour (earthy shade)
	mm.mesh = unit_mesh(kind)                     # one unit mesh shared by all chunks
	mm.instance_count = entries.size()            # allocate the instance buffer

	# Fill in each instance's transform (size+yaw+position) and colour.
	for i in entries.size():
		var entry: Dictionary = entries[i]
		mm.set_instance_transform(i, entry["transform"])
		mm.set_instance_color(i, entry["color"])

	# Wrap the MultiMesh in a MultiMeshInstance3D so it lives in the scene tree.
	# THE CUBE KEEPS THE NAME "BlockMultiMesh" — budapest_selfcheck and the A/B
	# harnesses look the node up by it, and the cube is what every chunk that
	# existed before this bead builds.
	var mmi := MultiMeshInstance3D.new()
	mmi.name = ("BlockMultiMesh" if kind == BoxKind.CUBE
			else "BlockMultiMesh_%s" % BoxKind.find_key(kind))
	mmi.multimesh = mm
	# One shared material for every block WHATEVER ITS KIND; the shader's gradient
	# is model-space, so it works unchanged on a sphere or a cone (see the unit-cube
	# rule on BoxKind). vertex_color_use_as_albedo lets the per-instance colours
	# show through (see _get_shared_block_material).
	mmi.material_override = _get_shared_block_material()
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Parent at the chunk's LOCAL origin: the instance transforms are already local to
	# the chunk (create_box used chunk-local `center_pos`), and the chunk mesh itself
	# is positioned in the world — so the blocks land exactly where they did before.
	parent_chunk.add_child(mmi)


static func _chunk_grid_spans(chunk_size: float, centre: float, size: float) -> Array:
	"""
	One axis of split_city_boxes_on_chunk_grid: cut the interval
	[centre - size/2, centre + size/2] at every WORLD chunk boundary it crosses.

	@param chunk_size: The world's chunk pitch — the ONLY terrain state this
	                   family reads, handed down by the caller rather than held,
	                   because everything else in here is arithmetic.
	@param centre: The interval's centre in WORLD space (not chunk-local).
	@param size: Its full extent on that axis.
	@return: [Vector2(piece centre, piece size), ...], west/north to east/south.
	         One element — the input, unchanged — when the interval fits in a cell.

	World space is deliberate: the boundaries are `k * chunk_size`, which is the
	same set of lines whichever chunk is asking, so every chunk that runs a slot's
	builder cuts that slot's boxes into the SAME pieces. That identity is what lets
	the centre rule below stay the whole of the assignment.

	A boundary that coincides with an edge produces no zero-width piece, and
	SPAN_EPS is what makes that true rather than nearly true. `t.origin` is f32,
	so `chunk_center + origin` rounds differently in each chunk's local frame and
	an edge sitting ON a boundary lands a fraction of a millimetre either side of
	it depending on who is asking. Without the epsilon one frame cuts and another
	does not — the identity above is lost, and a sub-micron sliver box (or, for a
	colliding box, a degenerate BoxShape3D) is shipped into the live batch. The
	epsilon is far above the worst f32 ulp at city X (~0.24 mm) and far below any
	real geometry, so it only ever eats a piece that should not exist.

	Eating it is also what bounds every piece by `chunk_size` exactly, which is
	the inequality budapest_selfcheck check 5 asserts — see the loop.
	"""
	var lo := centre - size * 0.5
	var hi := centre + size * 0.5
	var spans: Array = []
	var k := floori(lo / chunk_size) + 1
	var cut := float(k) * chunk_size
	var start := lo
	while cut < hi - SPAN_EPS:
		if cut - start > SPAN_EPS:
			spans.append(Vector2((start + cut) * 0.5, cut - start))
		# `start` advances whether or not the piece was kept, so the epsilon EATS
		# the sliver rather than folding it into the next piece. Folding it looks
		# harmless — it is sub-millimetre geometry — but it makes that next piece
		# `chunk_size + SPAN_EPS` wide, which budapest_selfcheck check 5 rejects on
		# a strict `> chunk_size` with a message blaming the splitter for not
		# cutting at all. Dropping 0.5 mm off an edge is the invisible half.
		start = cut
		k += 1
		cut = float(k) * chunk_size
	spans.append(Vector2((start + hi) * 0.5, hi - start))
	return spans


static func _is_axis_aligned_basis(b: Basis) -> bool:
	"""
	Is this basis DIAGONAL — i.e. does the box it frames sit square to the world
	axes? One home for the test, read by both halves of
	split_city_boxes_on_chunk_grid(), because the two halves are handed different
	bases for the same box and a second spelling is how they drifted apart.

	Signs are deliberately not constrained: create_box builds the basis as
	`Basis(UP, yaw) * Basis(RIGHT, tilt)`, so yaw or tilt = PI is a diagonal with
	negative entries and frames a box that is still perfectly axis-aligned.

	DIAGONAL, NOT "SQUARE TO THE AXES", AND THE TWO DIFFER AT ONE ANGLE. A quarter
	turn (yaw = +-PI/2) is ANTI-diagonal: the box is still world-axis-aligned but
	this answers false, so it keeps the centre rule instead of being cut. Nothing
	ships one — the city builders yaw by 0, PI or a deliberate PI/4 — and a
	quarter-turned box wider than a chunk fails budapest_selfcheck check 5 loudly
	rather than vanishing silently, which is why the case is documented here
	instead of handled. Handling it means swapping the X/Z spans in the caller.

	ORTHONORMALIZED FIRST, AND THAT IS THE WHOLE POINT OF ONE HOME. is_zero_approx
	compares against an ABSOLUTE epsilon (1e-5), while the two bases handed here
	differ by the box's own dimensions — the batch entry carries
	`rot.scaled_local(dimensions)`, the shape node the bare `rot`. Basis is real_t
	(fp32), so `Basis(UP, PI)` leaves x.z ~ 8.7e-8: bare it is zero to the epsilon,
	but scaled by a 272 m Parliament plinth it is 2.4e-5 and is NOT. That is the two
	spellings drifting apart while reading one function — the drawn wall in one
	chunk and its collision in another, exactly what the caller says cannot happen.
	Normalising the columns makes the test scale-free and the two halves agree.
	"""
	var n := b.orthonormalized()
	return (is_zero_approx(n.x.y) and is_zero_approx(n.x.z)
			and is_zero_approx(n.y.x) and is_zero_approx(n.y.z)
			and is_zero_approx(n.z.x) and is_zero_approx(n.z.y))


static func split_city_boxes_on_chunk_grid(terrain: Node3D, chunk_center: Vector3, batch: Array, body: StaticBody3D) -> void:
	"""
	Cut every box in a landmark builder's output that is wider than a chunk into
	per-cell pieces, on the WORLD chunk grid, in place. Rule 2a of
	_spawn_city_landmarks_in_chunk — read that docstring for why it exists.

	@param terrain: The world engine — read for `chunk_size` and nothing else
	                (landmark_builders' idiom: a static library takes the terrain
	                as a plain first argument and holds no state of its own).
	@param chunk_center: The world centre of the chunk whose local frame `batch`
	                     and `body` are expressed in.
	@param batch: In/out — the scratch MultiMesh batch, rewritten.
	@param body: In/out — the scratch collision body, its shapes rewritten.

	BOTH HALVES, INDEPENDENTLY. They are cut by the same arithmetic but never
	paired by index: every `collide = false` box (domes, spires, cornices — these
	builders are full of them) makes the two lists different lengths, which is the
	same reason the clip itself treats them separately.

	AXIS-ALIGNED ONLY. A rotated box has no representation as axis-aligned pieces,
	so it is left alone and keeps the centre rule; budapest_selfcheck check 5 is
	what fails a rotated box big enough for that to matter.

	Public (no leading underscore) so the self-check can run it over a builder's
	unclipped output the way the streamer does, rather than restating it.
	"""
	var chunk_size: float = terrain.chunk_size
	var out: Array = []
	for entry_v: Variant in batch:
		var entry: Dictionary = entry_v
		var t: Transform3D = entry["transform"]
		var b := t.basis
		# A CUT CONE IS NOT TWO CONES. Cutting works because a box's pieces are
		# boxes; a sphere's are not spheres, so a non-CUBE entry is left whole and
		# keeps the centre rule, exactly like a rotated box below.
		#
		# The COLLISION half further down still cannot READ this decision — it walks
		# shapes, and a shape carries no kind — but since bead godot-test1-y1o.10 it
		# reaches the same answer on its own for the round cases: a near-round
		# SPHERE or CYLINDER hangs a SphereShape3D / CylinderShape3D, which its
		# `as BoxShape3D` cast refuses, so both halves leave that entry whole. The
		# residual gap is every kind collision_shape_for() still gives a BoxShape3D:
		# the SQUASHED round box, the CONE, and — since bead godot-test1-y1o.3 —
		# EVERY ROCK, unconditionally and at any aspect, which makes it much the
		# widest member of that class. The collision half would cut one while the
		# visual stayed whole (measured: a 3.4-chunk-wide ROCK comes back as one
		# mesh entry and eight shapes). That cannot happen today — this is
		# the CITY path and Budapest is pure cube (budapest_selfcheck asserts a city
		# chunk builds exactly one MultiMeshInstance3D), and no city builder passes
		# a kind. `ponytail:` if a kind ever reaches a city builder, close the
		# residual gap by carrying the kind onto the CollisionShape3D as metadata.
		if int(entry.get("kind", BoxKind.CUBE)) != BoxKind.CUBE:
			out.append(entry)
			continue
		if not _is_axis_aligned_basis(b):
			out.append(entry)
			continue
		var xs := _chunk_grid_spans(chunk_size, chunk_center.x + t.origin.x, absf(b.x.x))
		var zs := _chunk_grid_spans(chunk_size, chunk_center.z + t.origin.z, absf(b.z.z))
		if xs.size() == 1 and zs.size() == 1:
			out.append(entry)
			continue
		for xv: Vector2 in xs:
			for zv: Vector2 in zs:
				var nb := Basis(
						Vector3(signf(b.x.x) * xv.y, 0.0, 0.0),
						b.y,
						Vector3(0.0, 0.0, signf(b.z.z) * zv.y))
				out.append({
					"transform": Transform3D(nb, Vector3(
							xv.x - chunk_center.x, t.origin.y, zv.x - chunk_center.z)),
					"color": entry["color"],
					# Always CUBE by the early-out above, but CARRIED rather than
					# hardcoded: the entry shape must stay uniform (see create_box's
					# note on why a sometimes-present key is a difference between
					# two runs that agree about every box).
					"kind": entry.get("kind", BoxKind.CUBE),
				})
	batch.clear()
	batch.append_array(out)

	# get_children() hands back a copy, so the shapes added below are not revisited.
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		var box := cs.shape as BoxShape3D
		# THE SAME PREDICATE AS THE VISUAL HALF, and it has to be: create_box gives
		# the shape node the bare `rot` basis while the batch entry gets
		# `rot.scaled_local(dimensions)`, so an identity test here would refuse
		# exactly the boxes the loop above accepts — yaw = PI is a signed diagonal,
		# and a mirrored wing is the most ordinary thing a builder writes. Cutting
		# one half and not the other is a drawn wall whose collision lives in
		# another chunk. A diagonal ROTATION has entries of magnitude 1, so the
		# shape's world extents are its `size` and the pieces stay identity-framed
		# (a box is symmetric under a ±1 flip).
		if box == null or not _is_axis_aligned_basis(cs.transform.basis):
			continue
		var o := cs.transform.origin
		var xs := _chunk_grid_spans(chunk_size, chunk_center.x + o.x, box.size.x)
		var zs := _chunk_grid_spans(chunk_size, chunk_center.z + o.z, box.size.z)
		if xs.size() == 1 and zs.size() == 1:
			continue
		for xv: Vector2 in xs:
			for zv: Vector2 in zs:
				var piece := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(xv.y, box.size.y, zv.y)
				piece.shape = shape
				piece.transform = Transform3D(Basis.IDENTITY, Vector3(
						xv.x - chunk_center.x, o.y, zv.x - chunk_center.z))
				body.add_child(piece)
		body.remove_child(cs)
		cs.free()
