// Ground shader — gives the infinite flat plane its look: a subtle large-scale
// mottling (two greens blended by noise) so it reads as terrain instead of a
// flat billiard table, PLUS the biome tint (desert / plains / city / forest /
// mountain / snow)
// and the blue river bands laid over it.
//
// THE GROUND IS ALWAYS FLAT (y = 0). Biomes and rivers are a PAINT JOB here plus
// block geometry and a speed penalty on the CPU side — there is no heightfield,
// no water mesh, no transparency. See the BIOME FIELD section of
// scripts/endless_terrain.gd for why (and for the upgrade path).
//
// CPU/GPU PARITY CONTRACT: biome_noise() below is the GPU copy of _biome_noise()
// in endless_terrain.gd, built out of the same hash2/value_noise this file
// already had. The blue band the player SEES and the wading zone the player
// FEELS are the same field, so the two copies MUST BE EDITED TOGETHER. The
// uniforms marked "must match GDScript" are pushed from
// _apply_biome_shader_params(); the pure-art colours below are shader-side only,
// so an art pass can retint from the material without touching GDScript.
//
// PERFORMANCE CONTRACT (why this is nearly free, even on web/gl_compatibility):
// - ALL the noise math — the ground mottling AND the biome field — runs in
//   vertex(). The chunk plane is subdivided 16x16 (see _get_shared_ground_mesh
//   in endless_terrain.gd), so that's a few hundred vertices per chunk, once
//   each, not per pixel.
// - fragment() does a handful of mix()/smoothstep() ops on interpolated
//   varyings: no noise, no texture fetch, no branching for the 95% of the world
//   that is dry land.
// - The river band factor is the ONE thing derived per-pixel (a subtract, an
//   abs and a smoothstep off the interpolated field value — still no noise), and
//   it has to be: see the note at its computation in fragment(). The shimmer on
//   top of it lives inside `if (v_river > 0.0)`, so only pixels actually inside
//   a river band pay for that.
//   WebGL2 fill rate is the tightest budget in the project — keep it that way.
//
// SEAMLESSNESS CONTRACT: every noise here is sampled at the WORLD-space XZ of
// each vertex (MODEL_MATRIX applied), so both the mottling and the biome field
// are one continuous field across the whole world — chunk seams land wherever
// they land in it and are invisible. Biome BOUNDARIES are softened separately,
// by the smoothstep blends in fragment() over biome_blend: that softness is
// about the desert-meets-plains edge, not the chunk edge. Zero per-chunk setup,
// zero per-chunk uniforms, which is what lets every chunk share ONE mesh + ONE
// material.
shader_type spatial;

// The two greens the noise blends between. Exposed as uniforms so an art pass
// can retint the ground from the material without touching this file.
uniform vec3 green_a: source_color = vec3(0.42, 0.55, 0.24); // sunlit grass
uniform vec3 green_b: source_color = vec3(0.20, 0.44, 0.26); // shaded moss

// --- Biome field parameters — MUST MATCH the GDScript constants -------------
// Defaults equal the GDScript values, so the shader still looks right if
// nothing ever pushes them (e.g. the material previewed in the editor).
uniform vec2 biome_offset = vec2(0.0);        // per-run domain shift (run_seed)
uniform float biome_cell_size = 400.0;        // noise wavelength in metres
uniform float biome_desert_max = 0.34;        // n < this  -> desert
uniform float biome_plains_max = 0.575;       // n < this  -> plains
uniform float biome_city_max = 0.66;          // n < this  -> city
uniform float biome_forest_max = 0.75;        // n < this  -> forest
uniform float biome_mountain_max = 0.83;      // n < this  -> mountain, else snow
uniform float river_level = 0.5;              // the contour rivers follow
uniform float river_half_width = 0.007;       // half-thickness of that contour
uniform float biome_blend = 0.05;             // smoothstep radius at each threshold

// --- Biome colours — pure art, never read by GDScript -----------------------
uniform vec3 desert_color: source_color = vec3(0.78, 0.68, 0.44);   // ochre sand
// Paved warm grey — dusty flagstone / worn asphalt. Deliberately well clear of
// mountain_color's grey-brown, even though the two bands can never touch (forest
// always sits between them), so a screenshot of one is never mistaken for the
// other.
uniform vec3 city_color: source_color = vec3(0.50, 0.48, 0.45);     // paved grey
uniform vec3 forest_color: source_color = vec3(0.13, 0.30, 0.17);   // deep cool green
uniform vec3 mountain_color: source_color = vec3(0.45, 0.43, 0.40); // grey-brown scree
// Frost-pale tundra: near-white with a cold blue cast, deliberately a shade
// DIMMER and BLUER than the massif snow caps (MOUNTAIN_SNOW_COLOR 0.92/0.94/0.96)
// that now stand on it — close enough that a capped peak reads as the same
// weather, far enough that the cap still separates from the ground behind it.
uniform vec3 snow_color: source_color = vec3(0.85, 0.89, 0.93);     // frost-pale tundra
uniform vec3 river_color: source_color = vec3(0.10, 0.28, 0.34);    // dark blue-teal

// Width of the soft waterline, as a fraction of the band half-width, CENTRED on
// the gameplay edge: the tint is full strength up to (1 - soft) * half_width,
// half strength exactly AT half_width, and gone by (1 + soft) * half_width.
//
// The centring is the point. A hard edge would shimmer along the waterline, so
// the tint has to fade over some distance — but fading it INWARD (full strength
// at 0.55, zero at 1.0, as this first did) makes the outer ~15% of the wading
// band look like dry land: the player slows to 0.6x and starts splashing about
// half a metre before any blue shows, on each bank. That is exactly the
// "the blue you SEE is the water you FEEL" contract the whole two-language noise
// arrangement exists to enforce. Straddling the edge splits the unavoidable
// error evenly instead of putting all of it on one side.
const float RIVER_EDGE_SOFT = 0.2;

// Ground mottling computed per-vertex, interpolated for free across the triangle.
varying float v_noise;
// The raw biome field value at this vertex — thresholded in fragment(), and the
// river band is derived from it there too (see the note in fragment()).
varying float v_biome;
// World XZ, carried through only so the river shimmer can animate in world
// space (so it doesn't swim when the chunk it belongs to is elsewhere).
varying vec2 v_world_xz;

// Sine-free 2D lattice hash: turns a lattice point into a pseudo-random 0..1
// value. Deterministic (pure function of position), so the pattern never
// swims between frames or differs between chunks.
//
// PRECISION: distance is this game's headline score, so world X reaches many
// kilometres — the classic fract(sin(dot(p, big)) * 43758.5453) hash feeds
// sin() inputs of 1e4+ out there, where fp32 sin loses its low bits and the
// noise collapses into visible banding (worst on mobile GPUs, the web
// target). So we wrap the lattice point with mod() first — hash inputs stay
// small everywhere, at the cost of the noise tiling every 289 lattice cells
// (~11.5 km for the broad octave; far beyond anything the fog lets you see).
// The wrap is seamless: lattice point 289 hashes identically to 0, so the
// cells on either side of the wrap boundary share their corner values.
float hash2(vec2 p) {
	p = mod(p, 289.0);
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
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

// THE biome field — the GPU twin of _biome_noise() in endless_terrain.gd.
// Reusing hash2/value_noise above is the whole point: one lattice hash, one
// blend recipe, so the CPU port has exactly one thing to mirror and parity
// stays honest. Regions AND rivers are both readouts of this single number,
// which is why they agree with each other for free.
float biome_noise(vec2 world_xz) {
	vec2 p = world_xz / biome_cell_size + biome_offset;
	return clamp(value_noise(p), 0.0, 1.0);
}

void vertex() {
	// World-space XZ of this vertex — the key to cross-chunk continuity.
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	v_world_xz = world_xz;
	// Two octaves: a broad ~40 m wash (dominant) plus ~13 m detail on top.
	// Weights sum to 1 so the result stays in 0..1 for the fragment lerp.
	float n = value_noise(world_xz * (1.0 / 40.0)) * 0.65
			+ value_noise(world_xz * (1.0 / 13.0)) * 0.35;
	v_noise = clamp(n, 0.0, 1.0);

	// The biome field, sampled once per vertex like everything else here.
	v_biome = biome_noise(world_xz);
}

void fragment() {
	// Plains stays exactly what it always was: the two-green mottle.
	vec3 albedo = mix(green_a, green_b, v_noise);
	// The same mottle, as a brightness wobble, keeps the other three biomes
	// from reading as flat painted plastic. Three multiplies, no extra noise.
	float mottle = mix(0.88, 1.12, v_noise);
	// Blend across each threshold with smoothstep over biome_blend, so a biome
	// boundary is a soft gradient several metres wide rather than a hard line.
	// Chained low-to-high: desert below, then plains, city, forest, mountain, snow.
	// The chain is why adding a band is one extra mix() in the right place and
	// nothing else — each step only has to say "above THIS threshold, become the
	// NEXT band". An INTERIOR band is only as saturated as its width allows: its
	// two smoothsteps overlap, so at the midpoint the band renders
	// s(w) * (1 - (1 - s(w))) where s is the smoothstep at (w/2 + blend)/(2*blend).
	// City 0.085 -> 96.8%, forest 0.09 -> 98.6%, mountain 0.08 -> 94.5%. The SNOW
	// band is the topmost, so it has only a lower edge and reaches full strength
	// outright — which is why the newly-narrowed mountain band, not snow, is the
	// one the width rule is now watching (see the note on BIOME_MOUNTAIN_MAX).
	albedo = mix(desert_color * mottle, albedo,
			smoothstep(biome_desert_max - biome_blend, biome_desert_max + biome_blend, v_biome));
	albedo = mix(albedo, city_color * mottle,
			smoothstep(biome_plains_max - biome_blend, biome_plains_max + biome_blend, v_biome));
	albedo = mix(albedo, forest_color * mottle,
			smoothstep(biome_city_max - biome_blend, biome_city_max + biome_blend, v_biome));
	albedo = mix(albedo, mountain_color * mottle,
			smoothstep(biome_forest_max - biome_blend, biome_forest_max + biome_blend, v_biome));
	albedo = mix(albedo, snow_color * mottle,
			smoothstep(biome_mountain_max - biome_blend, biome_mountain_max + biome_blend, v_biome));

	float roughness = 0.8; // matches the old StandardMaterial3D ground roughness

	// River = a thin CONTOUR of the same field: distance from the contour,
	// remapped so the band centre is 1 and the edge fades to 0.
	//
	// WHY THIS IS PER-FRAGMENT WHILE EVERY OTHER NOISE READ IS PER-VERTEX: the
	// band is only ~8 m wide and its soft edge spans under 2 m, while the chunk
	// plane's vertex spacing is ~3 m (16x16 over 50 m). Interpolating the band
	// factor itself would therefore undersample it by more than a vertex, and
	// the blue you SEE would part company with the wading zone you FEEL by a
	// metre or two — exactly the mismatch the CPU/GPU parity contract exists to
	// prevent. v_biome is safe to interpolate (a 400 m wavelength is near-linear
	// over 3 m); the cheap NONLINEAR part is what has to be evaluated here. Cost
	// is a subtract, an abs and a smoothstep — no noise, no texture fetch.
	float v_river = 1.0 - smoothstep(river_half_width * (1.0 - RIVER_EDGE_SOFT),
			river_half_width * (1.0 + RIVER_EDGE_SOFT), abs(v_biome - river_level));

	// River last, on top of whatever biome it cuts through — rivers are an
	// overlay, not a biome (same rule as is_river_at() on the CPU side).
	if (v_river > 0.0) {
		// Cheap crossed-sine shimmer: two sines drifting in opposite senses so
		// the interference pattern never reads as a repeating grid. World-space
		// input keeps it continuous across chunk seams, TIME makes it flow.
		float shimmer = sin(v_world_xz.x * 1.7 + TIME * 1.3)
				* sin(v_world_xz.y * 2.3 - TIME * 0.9);
		vec3 wet = river_color * (1.0 + shimmer * 0.12);
		albedo = mix(albedo, wet, v_river);
		// Wet sheen for free — no transparency, no reflection, no extra pass.
		roughness = mix(roughness, 0.3, v_river);
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
