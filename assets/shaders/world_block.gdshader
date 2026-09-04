shader_type spatial;
// ---------------------------------------------------------------------------
// WORLD BLOCK MATERIAL — style direction A (faceted low-poly + top-lit gradient).
//
// This is the shared material of EVERY chunk's block MultiMesh (see
// chunk_batch.gd::_get_shared_block_material). It replaces a StandardMaterial3D
// that did exactly two things — `vertex_color_use_as_albedo = true` and
// `roughness = 0.85` — and it still does exactly those two things, PLUS one:
//
//   a per-box vertical gradient, dark at the foot and full colour at the top.
//
// WHY IT IS FREE. Every instance in the batch is the shared UNIT BoxMesh scaled by
// its per-instance transform, so the mesh's own local `VERTEX.y` runs -0.5 .. +0.5
// over that box whatever its real size is. `VERTEX.y + 0.5` is therefore the
// fraction of the box's own height, and the gradient needs NO per-instance data,
// no second UV channel and no extra buffer — the MultiMesh layout is untouched.
// It reads as cheap contact shading / fake AO: a tree trunk darkens toward the
// ground, a rock's crown catches the key light, and a wall of stacked boxes stops
// being one flat slab of colour.
//
// The render modes are StandardMaterial3D's own defaults, spelled out so this
// shader is a like-for-like swap and not a lighting change smuggled in beside a
// gradient. Web `gl_compatibility` runs this unchanged: one varying float, one
// mix, no branches, no texture fetches.
// ---------------------------------------------------------------------------
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The gradient's floor: how dark the BOTTOM of a box gets, as a fraction of its
// own colour. 1.0 reproduces the pre-style flat look exactly, which is what makes
// this the one number to tune (or to animate, if the look ever wants to breathe).
uniform float bottom_shade : hint_range(0.0, 1.0) = 0.78;

// Single representative roughness — the constant that was
// SHARED_BLOCK_ROUGHNESS on the StandardMaterial3D, moved here unchanged. A
// MultiMesh cannot vary roughness per instance, so one mid value serves all.
uniform float block_roughness : hint_range(0.0, 1.0) = 0.85;

// Height fraction within this box, 0 at its foot and 1 at its top.
varying float height_frac;

void vertex() {
	// VERTEX is in MODEL space here: the shared unit cube, NOT the instanced,
	// scaled, yawed box. That is the whole trick — the instance transform lives
	// in MODEL_MATRIX and never reaches this value, so every box of every size
	// gets the same 0..1 sweep over its own height.
	height_frac = clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	// COLOR is the MultiMesh per-instance colour (linear, exactly as
	// `vertex_color_use_as_albedo` consumed it), scaled by the gradient.
	ALBEDO = COLOR.rgb * mix(bottom_shade, 1.0, height_frac);
	ROUGHNESS = block_roughness;
}
