// Ground shader — gives the infinite green plane a subtle large-scale
// mottling (two greens blended by noise) so it reads as terrain instead of
// a flat billiard table.
//
// PERFORMANCE CONTRACT (why this is nearly free, even on web/gl_compatibility):
// - ALL the noise math runs in vertex() — the chunk plane is subdivided 16x16
//   (see _get_shared_ground_mesh in endless_terrain.gd), so that's a few
//   hundred vertices per chunk, once each, not per pixel.
// - fragment() does ONLY a mix() between two uniform colors using the
//   interpolated varying. Fill rate is untouched vs the old StandardMaterial3D.
//
// SEAMLESSNESS CONTRACT: the noise is sampled at the WORLD-space XZ of each
// vertex (MODEL_MATRIX applied), so the pattern is one continuous field across
// the whole world — chunk seams land wherever they land in it and are
// invisible. Zero per-chunk setup, zero uniforms to update per chunk, which is
// what lets every chunk share ONE mesh + ONE material.
shader_type spatial;

// The two greens the noise blends between. Exposed as uniforms so an art pass
// can retint the ground from the material without touching this file.
uniform vec3 green_a: source_color = vec3(0.42, 0.55, 0.24); // sunlit grass
uniform vec3 green_b: source_color = vec3(0.20, 0.44, 0.26); // shaded moss

// Noise value computed per-vertex, interpolated for free across the triangle.
varying float v_noise;

// Classic sin/dot hash: turns a 2D lattice point into a pseudo-random 0..1
// value. Deterministic (pure function of position), so the pattern never
// swims between frames or differs between chunks.
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// One octave of value noise: hash the four corners of the lattice cell the
// point falls in, then blend with a smoothstep-shaped weight (f*f*(3-2f)) so
// the gradient is continuous — plain linear blending shows the grid.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	// World-space XZ of this vertex — the key to cross-chunk continuity.
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	// Two octaves: a broad ~40 m wash (dominant) plus ~13 m detail on top.
	// Weights sum to 1 so the result stays in 0..1 for the fragment lerp.
	float n = value_noise(world_xz * (1.0 / 40.0)) * 0.65
			+ value_noise(world_xz * (1.0 / 13.0)) * 0.35;
	v_noise = clamp(n, 0.0, 1.0);
}

void fragment() {
	// Just the lerp — see the performance contract at the top.
	ALBEDO = mix(green_a, green_b, v_noise);
	ROUGHNESS = 0.8; // match the old StandardMaterial3D ground roughness
}
