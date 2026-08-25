// ============================================================================
// Cel / toon OUTLINE shader  (inverted-hull technique)
// ============================================================================
// This draws a crisp black silhouette around a mesh, like the outlines in
// classic cel-shaded games such as Okami. It is meant to be assigned as a *material
// overlay* on a MeshInstance3D, so it renders as an extra pass on top of the
// character's normal (toon) material without replacing it.
//
// HOW INVERTED HULL WORKS:
//   1. We push every vertex OUTWARD along its surface normal, growing a
//      slightly larger "shell" around the model.
//   2. We cull the FRONT faces (`cull_front`), so only the *back* of that
//      grown shell is drawn. From the camera, the only place the back of the
//      shell is visible is right at the silhouette edge -> a clean outline.
//
// We expand in CLIP space (screen space) so the outline stays a roughly
// constant thickness no matter how big the body part is or how far away it is.
// This works on every renderer, including the Compatibility renderer used for
// the web export.
// ============================================================================
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;

// Outline colour. A near-black with a hint of warmth reads softer than pure 0.
uniform vec4 outline_color : source_color = vec4(0.06, 0.05, 0.07, 1.0);

// Outline thickness, in (roughly) screen pixels at 1080p. Bump this up to make
// the cel look bolder, down for a finer line.
uniform float outline_thickness : hint_range(0.0, 12.0) = 3.5;

void vertex() {
	// Position and normal in clip space.
	vec4 clip_pos = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 clip_normal = normalize((PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Push the silhouette outward. Multiplying by clip_pos.w keeps the line a
	// constant on-screen width under perspective.
	clip_pos.xy += clip_normal.xy * outline_thickness * 0.002 * clip_pos.w;
	POSITION = clip_pos;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
