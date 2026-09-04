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
static var _shared_block_material: StandardMaterial3D

## A representative roughness for the shared block material. The old per-block code
## picked a random roughness in [0.7, 1.0]; since MultiMesh can't vary roughness
## per instance, we use one mid-range value for all blocks. (We still CONSUME the
## same RNG call in create_box so the deterministic world layout is unchanged.)
const SHARED_BLOCK_ROUGHNESS: float = 0.85

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

static func _get_shared_block_material() -> StandardMaterial3D:
	"""
	Returns the shared block material used by every block MultiMesh, creating it on
	first use. `vertex_color_use_as_albedo = true` makes each MultiMesh instance's
	per-instance Color show up as that block's albedo, so one material can paint all
	the earthy browns/grays/mossy greens.
	"""
	if _shared_block_material == null:
		_shared_block_material = StandardMaterial3D.new()
		# THE key line: take the per-instance vertex colour and use it as albedo.
		_shared_block_material.vertex_color_use_as_albedo = true
		# Single representative roughness (see SHARED_BLOCK_ROUGHNESS note above).
		_shared_block_material.roughness = SHARED_BLOCK_ROUGHNESS
	return _shared_block_material

static func create_block(center_pos: Vector3, size: float, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Create one cube block. Thin wrapper over create_box for the common case where
	all three dimensions are equal (scattered blocks, towers, walls, corridors).

	@param block_batch: Out-param forwarded to create_box for MultiMesh batching.
	@param block_body: The chunk's shared block-collision body, forwarded to
	                  create_box so this block's shape hangs on it (Task 5).
	"""
	create_box(center_pos, Vector3(size, size, size), yaw, rng, block_batch, block_body)

static func create_box(center_pos: Vector3, dimensions: Vector3, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, tilt: float = 0.0, color_override: Color = Color(0.0, 0.0, 0.0, 0.0), collide: bool = true) -> void:
	"""
	Register one box for rendering AND register its physics collision shape. Used for
	cube blocks and for the flat slabs that make up terraced mounds.

	VISUALS vs COLLISION are DECOUPLED (Tasks 4 + 5 of the perf plan):
	- VISUALS (Task 4): this function no longer instances a MeshInstance3D +
	  StandardMaterial3D per block. Instead it appends one
	  { "transform": Transform3D, "color": Color } entry to `block_batch`. The caller
	  (create_chunk) later turns the whole batch into ONE MultiMeshInstance3D, so all
	  of a chunk's blocks draw in a single draw call instead of dozens (see this
	  file's MultiMesh banner and _build_block_multimesh below). The blocks look EXACTLY
	  the same — same shapes, sizes, yaw and earthy-colour ranges — only how they're
	  SUBMITTED to the GPU changed.
	- COLLISION (Task 5): this function no longer creates a per-block StaticBody3D.
	  Instead it adds just a CollisionShape3D (with a BoxShape3D) as a child of the
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
	block_batch.append({
		"transform": Transform3D(rot.scaled_local(dimensions), center_pos),
		"color": chosen_color.srgb_to_linear(),
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

	var collision_shape := CollisionShape3D.new()
	collision_shape.transform = Transform3D(rot, center_pos)

	var box_shape := BoxShape3D.new()
	box_shape.size = dimensions
	collision_shape.shape = box_shape

	# Add to the shared per-chunk body. (block_body is parented to the chunk by
	# create_chunk once generation finishes, so all these shapes unload with the chunk.)
	block_body.add_child(collision_shape)

static func _build_block_multimesh(parent_chunk: MeshInstance3D, block_batch: Array,
		cast_shadows: bool = true) -> void:
	"""
	Turn a chunk's whole batch of blocks into ONE MultiMeshInstance3D, so every block
	in the chunk renders in a single draw call (instead of one draw call per block).

	@param parent_chunk: The chunk mesh — we parent the MultiMeshInstance3D to it so it
	                    is freed automatically when the chunk unloads (same per-chunk
	                    parenting rule everything else follows).
	@param block_batch: The list of { "transform": Transform3D, "color": Color } entries
	                    create_box appended while building this chunk's blocks.
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
	# Build the MultiMesh and declare its per-instance data layout.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D  # per-instance 3D transform
	mm.use_colors = true                          # per-instance colour (earthy shade)
	mm.mesh = _get_shared_unit_box_mesh()         # one unit cube shared by all chunks
	mm.instance_count = block_batch.size()        # allocate the instance buffer

	# Fill in each instance's transform (size+yaw+position) and colour.
	for i in block_batch.size():
		var entry: Dictionary = block_batch[i]
		mm.set_instance_transform(i, entry["transform"])
		mm.set_instance_color(i, entry["color"])

	# Wrap the MultiMesh in a MultiMeshInstance3D so it lives in the scene tree.
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BlockMultiMesh"
	mmi.multimesh = mm
	# One shared material for every block; vertex_color_use_as_albedo lets the
	# per-instance colours show through (see _get_shared_block_material).
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
