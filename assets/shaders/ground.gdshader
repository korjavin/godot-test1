// Ground shader — gives the infinite flat plane its look: a subtle large-scale
// mottling (two greens blended by noise) so it reads as terrain instead of a
// flat billiard table, PLUS the biome tint (desert / plains / city / forest /
// mountain / snow)
// and the blue river bands laid over it.
//
// THE GROUND IS FLAT (y = 0) IN EVERYTHING THAT SHIPS, and that paragraph used to
// be unconditional. It is now conditional on ONE uniform: with `alt_enabled` at
// its 0.0 default — which is what endless_terrain.gd pushes while
// `FIELD_ALTITUDE` is false, i.e. always, in every build — this file draws
// exactly the flat world it always drew, byte for byte, and biomes and rivers
// stay a PAINT JOB over it (block geometry and a speed penalty on the CPU side,
// no water mesh, no transparency). See the BIOME FIELD section of
// scripts/endless_terrain.gd for why.
//
// Behind alt_enabled is the FIELD ALTITUDE SPIKE (bead godot-test1-ope.1): a
// vertex-displaced heightfield, `field_height()` below, whose CPU twin is
// `height_at()`. It is a MEASUREMENT, not a shipped feature —
// docs/field-altitude-spike.md is the report and lists everything in this project
// that still assumes y = 0.
//
// CPU/GPU PARITY CONTRACT: biome_noise() below is the GPU copy of _biome_noise()
// in endless_terrain.gd, built out of the same hash2/value_noise this file
// already had. IT COVERS field_height() TOO, and there with more force: the
// ground you SEE displaced is the ground you STAND ON (the collision heightmap is
// sampled off height_at), so a millimetre of disagreement is a player sunk into a
// hill. altitude_selfcheck.gd is the assertion, both ways. The blue band the player SEES and the wading zone the player
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
// THE DEEP CHANNEL's share of the band (bead godot-test1-06o.3, owner ruling
// 2026-09-04/09-05 "why rivers, and danube are still walkable? fix this"). The
// inner `river_deep_fraction` of every band is IMPASSABLE on the CPU, so it is
// painted darker here off the SAME normalised depth — one number, two languages,
// the ordinary parity rule. Pushed by _apply_biome_shader_params beside
// river_half_width; the default matches RIVER_DEEP_FRACTION so a material that
// never met that function still paints what the terrain enforces.
//
// The CPU adds one clause this does not: a road crossing the field bridges
// REFUSED keeps a road-width FORD through the strip, or the road it stands on is
// softlocked. Running that here would cost a station search per fragment on a
// fill-rate-bound WebGL2 target for a gap at one crossing in thirty-nine, so the
// tint is the field value alone — see _deep_channel_ford in endless_terrain.gd,
// which carries this ceiling. The paint says "deep water"; the CPU says who may
// walk it.
uniform float river_deep_fraction = 0.4;
uniform float biome_blend = 0.05;             // smoothstep radius at each threshold
// THE TOWER'S DRY DISC — the GPU half of the mask in is_river_at(). The tower
// stands at a fixed, hand-planned address (endless_terrain.gd tower_site()), so
// rather than nudging the building out of the water we take the water out from
// under the building: no river band is painted inside this disc, and the CPU
// wade test refuses inside exactly the same one. Pushed together with the biome
// constants above; the -1 default leaves the mask OFF for a material nobody fed.
uniform vec2 tower_dry_center = vec2(0.0);
uniform float tower_dry_radius = -1.0;

// --- BUDAPEST — the GPU half of the authored city ---------------------------
// The city is hand-planned data (scripts/budapest_plan.gd), and every number
// below is pushed from it by _apply_biome_shader_params(). Three clauses, all of
// them the twin of something biome_at()/is_river_at() do on the CPU:
//   1. inside city_rect the ground is CITY, whatever the noise field says;
//   2. inside city_rect the river is the AUTHORED Danube polyline and nothing
//      else — the noise band is suppressed in there, exactly as the CPU's early
//      return suppresses it;
//   3. the Danube is punched out by city_dry — the bridge decks and Margaret
//      Island — because is_river_at() is XZ-only and a deck must be dry to both.
// The tower's dry disc does NOT apply inside the city: one river or the other,
// never both, and the two features are 2 km apart anyway.
// EDIT THIS TOGETHER WITH biome_at()/is_river_at(). The defaults are INERT
// (city_rect's max < its min, both counts 0), the tower_dry_radius = -1 pattern,
// so a material nobody fed draws exactly the world it always drew.
const int CITY_SEG_MAX = 8;
const int CITY_DRY_MAX = 8;
uniform vec4 city_rect = vec4(0.0, 0.0, -1.0, -1.0); // xmin, zmin, xmax, zmax
uniform vec4 city_river[CITY_SEG_MAX];               // x1, z1, x2, z2 per segment
uniform int city_river_count = 0;
uniform float city_river_half = 0.0;
uniform vec4 city_dry[CITY_DRY_MAX];                 // xmin, zmin, xmax, zmax
uniform int city_dry_count = 0;

// --- FIELD ALTITUDE — the GPU twin of the heightfield SPIKE -----------------
// The CPU half is `height_at()` in scripts/endless_terrain.gd, behind
// `FIELD_ALTITUDE`. EVERYTHING BELOW IS EDITED TOGETHER WITH IT — the ground you
// SEE displaced and the ground you STAND ON are the same surface (the collision
// heightmap is sampled off height_at), so this is the parity contract
// _biome_noise/biome_noise already live under, one clause wider.
//
// THE GATE IS A UNIFORM, NOT AN #ifdef: alt_enabled multiplies nothing away, it
// EARLY-RETURNS field_height() and guards the whole vertex() block, so the
// flag-off path costs exactly one compare per vertex. Its default is 0.0 — the
// tower_dry_radius = -1 precedent — so a material nobody fed draws exactly the
// flat world it always drew.
//
// Every default below equals the GDScript constant of the same name, for the
// same reason the biome block's do: a material previewed in the editor, or a
// shader loaded by a check that never ran _apply_biome_shader_params, still
// computes the shipped field rather than a made-up one.
// Restated from GDScript, because a GLSL array uniform is a fixed size —
// the CITY_SEG_MAX precedent, and altitude_selfcheck check 4 asserts this is
// >= the GDScript's ALT_ROAD_SEG_MAX. Kept on a line of its own with no
// trailing comment: that check parses the value off the text.
const int ALT_ROAD_SEG_MAX = 24;
// How far apart the two finite differences that rebuild NORMAL are taken, in
// metres. 1 m against the 260 m ALT_CELL_SIZE wavelength and the ~3.1 m vertex
// spacing: small enough that the slope it measures is the slope at this vertex,
// large enough that the fp32 subtraction below has bits left. FORWARD
// differences, reusing the vertex's own height as the third sample, so the
// normal costs TWO extra field_height() evaluations and not four — the cost this
// spike exists to measure.
const float ALT_NORMAL_EPS = 1.0;
uniform float alt_enabled = 0.0;                // 0 = the flat world, byte for byte
uniform vec2 alt_offset = vec2(37.0, 71.0);     // ALT_OFFSET_SALT: altitude's OWN
                                                // domain shift, added ON TOP of
                                                // biome_offset so hills never
                                                // correlate with biomes
uniform float alt_cell_size = 260.0;            // wavelength (m), deliberately not
                                                // biome_cell_size
uniform float alt_detail_scale = 3.1;
uniform float alt_detail_weight = 0.3;
uniform vec2 alt_detail_shift = vec2(17.0, 31.0); // the detail octave's own shift
// The six per-biome amplitudes, in metres — the half-range of the signed height.
uniform float alt_amp_desert = 2.5;
uniform float alt_amp_plains = 3.5;
uniform float alt_amp_city = 1.0;
uniform float alt_amp_forest = 6.0;
uniform float alt_amp_mountain = 22.0;
uniform float alt_amp_snow = 16.0;
// The four forced-flat zones' skirts. Budapest's rect is the EXISTING city_rect
// uniform and the HQ disc the EXISTING tower_dry_center/tower_dry_radius — no
// second copy of either, the same rule that keeps in_budapest() delegating to
// BudapestPlan. The river's skirt is in FIELD units (a multiple of
// river_half_width), which is what keeps the flat edge and the wading edge one
// number.
uniform float alt_city_skirt = 120.0;
uniform float alt_tower_skirt = 60.0;
uniform float alt_river_skirt_k = 3.5;
uniform float alt_road_flat_half = 22.0;
uniform float alt_road_skirt = 40.0;
// The coin road as a COARSE polyline, packed (x1, z1, x2, z2) per segment — the
// same array the CPU's _alt_road_distance() reads, built once by
// _alt_road_segments() and pushed here, so the two corridors are parity BY
// CONSTRUCTION rather than by re-derivation. Count 0 is inert: no road, no
// corridor, and alt_road_distance() answers "far away".
uniform vec4 alt_road_seg[ALT_ROAD_SEG_MAX];
uniform int alt_road_seg_count = 0;

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

// The Danube's soft waterline, in METRES rather than as a fraction of the band.
// The noise river's fraction would be 24 m of fade on a 120 m half-width; the
// Danube's edge is a shoreline, so it gets the same ~2 m of softness the noise
// river actually has and is centred on the gameplay edge for the same reason
// (see RIVER_EDGE_SOFT above): the CPU's test is a hard `< half`, so half the
// unavoidable error goes on each bank.
const float CITY_RIVER_EDGE_SOFT = 2.0;

// How much darker the impassable deep channel is than the wadeable band around
// it. A multiplier on the SAME river_color rather than a second uniform: the
// strip has to read as deeper water, not as a different material, and the
// gradient between the two is what tells a player where the wall is.
const float RIVER_DEEP_SHADE = 0.45;

// Ground mottling computed per-vertex, interpolated for free across the triangle.
varying float v_noise;
// The raw biome field value at this vertex — thresholded in fragment(), and the
// river band is derived from it there too (see the note in fragment()).
varying float v_biome;
// World XZ, carried through only so the river shimmer can animate in world
// space (so it doesn't swim when the chunk it belongs to is elsewhere).
varying vec2 v_world_xz;
// The AUTHORED Danube's band factor — 1 mid-river, 0 on dry land.
//
// WHY THIS ONE IS PER-VERTEX WHILE THE NOISE RIVER IS PER-FRAGMENT: it is a
// sampling-rate argument and nothing else. The noise band is ~8 m wide against
// the chunk plane's ~3 m vertex spacing (16x16 over 50 m) — 2.6x, undersampled,
// so interpolating it would move the blue a metre or two off the wading zone.
// The Danube is 240 m wide against the same 3 m spacing — 40x OVERSAMPLED — so
// interpolating its band factor costs no accuracy you could see, and it keeps an
// 8-segment point-to-segment loop off a fill-rate-bound WebGL2 target. The HARD
// part of the city river, the dry-deck mask, stays per-fragment for the mirror
// image of this reason (see fragment()).
varying float v_city_river;
// The same for the Danube's DEEP CHANNEL — 1 mid-channel, 0 at the strip's edge.
// Per-vertex for exactly v_city_river's reason: 0.4 x 120 m of half-width against
// 3 m of vertex spacing is oversampled many times over, and it rides the one
// city_river_distance() call the vertex already pays for.
varying float v_city_river_deep;

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

// Shortest distance from a world XZ to the authored Danube polyline — the GPU
// twin of BudapestPlan.danube_distance(), the same clamped point-to-segment
// projection, which is why that one is written in Vector2 (f32) throughout.
float city_river_distance(vec2 p) {
	float best = 1.0e9;
	for (int i = 0; i < city_river_count; i++) {
		vec2 a = city_river[i].xy;
		vec2 b = city_river[i].zw;
		vec2 ab = b - a;
		float len_sq = dot(ab, ab);
		float t = len_sq <= 0.0 ? 0.0 : clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
		best = min(best, distance(p, a + ab * t));
	}
	return best;
}

// Shortest distance from a world XZ to the CACHED coarse coin-road polyline —
// the GPU twin of _alt_road_distance(). It is city_river_distance()'s loop over
// a different array and nothing else: one clamped point-to-segment projection in
// this project, so the corridor the ground is FLATTENED along cannot drift from
// the corridor the CPU flattens. Count 0 (the inert default, and every frame the
// spike is off) returns the same 1e9 "nowhere near a road" the empty CPU cache
// answers as INF.
float alt_road_distance(vec2 p) {
	float best = 1.0e9;
	for (int i = 0; i < alt_road_seg_count; i++) {
		vec2 a = alt_road_seg[i].xy;
		vec2 b = alt_road_seg[i].zw;
		vec2 ab = b - a;
		float len_sq = dot(ab, ab);
		float t = len_sq <= 0.0 ? 0.0 : clamp(dot(p - a, ab) / len_sq, 0.0, 1.0);
		best = min(best, distance(p, a + ab * t));
	}
	return best;
}

// The altitude field's two octaves — the GPU twin of _alt_value_noise_pair().
// Reuses value_noise/hash2 above, which is the whole parity argument: ONE lattice
// hash in the project, so the GDScript port has exactly one thing to mirror.
float alt_value_noise_pair(vec2 p) {
	return value_noise(p) * (1.0 - alt_detail_weight)
			+ value_noise(p * alt_detail_scale + alt_detail_shift) * alt_detail_weight;
}

// How tall the ground may be where the biome field reads `b` — the GPU twin of
// _alt_amplitude(). IT IS fragment()'s COLOUR CHAIN WITH SIX METRES INSTEAD OF
// SIX COLOURS: same thresholds, same biome_blend, same low-to-high order, so a
// band cannot be tall where it looks like sand, and adding a band is one extra
// mix() here exactly as it is one extra mix() down there.
float alt_amplitude(float b) {
	float amp = alt_amp_desert;
	amp = mix(amp, alt_amp_plains,
			smoothstep(biome_desert_max - biome_blend, biome_desert_max + biome_blend, b));
	amp = mix(amp, alt_amp_city,
			smoothstep(biome_plains_max - biome_blend, biome_plains_max + biome_blend, b));
	amp = mix(amp, alt_amp_forest,
			smoothstep(biome_city_max - biome_blend, biome_city_max + biome_blend, b));
	amp = mix(amp, alt_amp_mountain,
			smoothstep(biome_forest_max - biome_blend, biome_forest_max + biome_blend, b));
	amp = mix(amp, alt_amp_snow,
			smoothstep(biome_mountain_max - biome_blend, biome_mountain_max + biome_blend, b));
	return amp;
}

// HOW MUCH ALTITUDE THIS POINT IS ALLOWED — the GPU twin of _alt_flat_mask().
// A PRODUCT OF FOUR INDEPENDENT 0..1 FACTORS, so a point in two zones is flat and
// never twice flat, and a fifth zone one day is one more factor.
//
// `b` is passed in rather than re-derived because vertex() spends it three times
// over for the finite-difference normals — the same reason the GDScript twin
// takes it as an argument.
float alt_flat_mask(vec2 w, float b) {
	// CLAUSE 1 — BUDAPEST. The EXISTING city_rect uniform: the authored Danube,
	// the plateaus and every DRY_RECTS row live inside it, so none of them needs a
	// clause of its own. Inert default (max < min) leaves this factor at 1.
	float mask = 1.0;
	if (city_rect.z >= city_rect.x) {
		vec2 d = max(max(city_rect.xy - w, w - city_rect.zw), vec2(0.0));
		mask = smoothstep(0.0, alt_city_skirt, length(d));
	}
	// CLAUSE 2 — THE HQ DISC. The EXISTING tower_dry_center/tower_dry_radius: the
	// shell is not chunk-parented and never rebuilt, so the ground under it may not
	// move by a millimetre. Inert default (radius -1) leaves this factor at 1.
	if (tower_dry_radius >= 0.0) {
		mask *= smoothstep(tower_dry_radius, tower_dry_radius + alt_tower_skirt,
				distance(w, tower_dry_center));
	}
	// CLAUSE 3 — EVERY RIVER BAND, IN FIELD UNITS. The same
	// |b - river_level| < river_half_width test is_river_at() makes, so the flat
	// edge and the wading edge are readouts of ONE number: rivers stay at y = 0 and
	// wading stays XZ-only with no edit anywhere. Deliberately the RAW field, like
	// the CPU twin — the city and tower overrides is_river_at() applies are readout
	// policy, and both those zones are flattened by the clauses above already.
	mask *= smoothstep(river_half_width, river_half_width * alt_river_skirt_k,
			abs(b - river_level));
	// CLAUSE 4 — THE COIN ROAD CORRIDOR. The road is the spike's CONTROL: the coin
	// road is where the player walks, so a hilly one would send coin settling, road
	// bosses and road clearance red at once and hide which breakage is the
	// heightfield's.
	mask *= smoothstep(alt_road_flat_half, alt_road_flat_half + alt_road_skirt,
			alt_road_distance(w));
	return mask;
}

// THE FIELD'S ALTITUDE at a world XZ — the GPU twin of height_at().
// Gated by alt_enabled BEFORE any noise, exactly as height_at() is gated by
// FIELD_ALTITUDE on its first line: with the spike off the whole heightfield
// costs one compare per evaluation.
float field_height(vec2 w) {
	if (alt_enabled <= 0.0) {
		return 0.0;
	}
	// The same expression in the same ORDER as height_at(): the biome_offset term
	// is added before alt_offset, because fp32 addition is not associative and a
	// pre-summed offset would round differently from the CPU's.
	vec2 p = w / alt_cell_size + biome_offset + alt_offset;
	float n = alt_value_noise_pair(p);
	// ONE biome_noise() evaluation, spent twice — the amplitude ladder and the
	// mask's river clause are readouts of the same number.
	float b = biome_noise(w);
	// 0..1 -> -1..1, so the field cuts valleys as well as raising hills and its
	// mean stays at the y = 0 the whole game is written against.
	return (n - 0.5) * 2.0 * alt_amplitude(b) * alt_flat_mask(w, b);
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

	// The Danube, ditto — see the note on v_city_river for why this one is safe
	// to interpolate and the noise river is not. Zero when no city is fed, which
	// is what makes the inert defaults inert.
	v_city_river = 0.0;
	v_city_river_deep = 0.0;
	if (city_river_count > 0) {
		float city_d = city_river_distance(world_xz);
		v_city_river = 1.0 - smoothstep(city_river_half - CITY_RIVER_EDGE_SOFT,
				city_river_half + CITY_RIVER_EDGE_SOFT, city_d);
		float city_deep_half = city_river_half * river_deep_fraction;
		v_city_river_deep = 1.0 - smoothstep(city_deep_half - CITY_RIVER_EDGE_SOFT,
				city_deep_half + CITY_RIVER_EDGE_SOFT, city_d);
	}

	// THE HEIGHTFIELD — the spike, and the ONE thing in this file that moves a
	// vertex. Guarded rather than multiplied by zero so the flag-off path costs a
	// single compare per vertex and not three field evaluations: with alt_enabled
	// at its 0.0 default this block is skipped entirely and the plane is the flat
	// plane it has always been, byte for byte.
	//
	// VERTEX and NORMAL are MODEL space. A chunk's ground is translated and never
	// rotated or scaled (see _ensure_chunk_ground), so model Y is world Y here and
	// the displacement needs no basis transform — if a chunk ever gains a rotation
	// this is the line that has to learn about it.
	if (alt_enabled > 0.0) {
		float h = field_height(world_xz);
		VERTEX.y += h;
		// NORMALS ARE RECOMPUTED, because a displaced plane wearing the flat
		// plane's straight-up normal reads as a shading bug rather than as a hill:
		// every slope would be lit as though it were level ground. Two FORWARD
		// differences reusing h, so the whole normal costs TWO extra field_height()
		// evaluations (three per vertex in total) — the number this spike exists to
		// measure. The tangent vectors are (eps, dh/dx, 0) and (0, dh/dz, eps);
		// their cross product, divided through by eps, is what is normalized here.
		float dhdx = (field_height(world_xz + vec2(ALT_NORMAL_EPS, 0.0)) - h) / ALT_NORMAL_EPS;
		float dhdz = (field_height(world_xz + vec2(0.0, ALT_NORMAL_EPS)) - h) / ALT_NORMAL_EPS;
		NORMAL = normalize(vec3(-dhdx, 1.0, -dhdz));
	}
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

	// BUDAPEST forces CITY over the whole chain above. The rect test is done here
	// and not interpolated from a varying: v_world_xz is exact per fragment, and
	// the city's edge is an authored line the CPU answers with a hard compare, so
	// the two agree to the pixel. `city_rect.z < city_rect.x` is the inert
	// default — no city fed, nothing changes.
	bool in_city = city_rect.z >= city_rect.x
			&& v_world_xz.x >= city_rect.x && v_world_xz.x <= city_rect.z
			&& v_world_xz.y >= city_rect.y && v_world_xz.y <= city_rect.w;
	if (in_city) {
		albedo = city_color * mottle;
	}

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

	// THE DEEP CHANNEL, the GPU half of it — the same expression one factor in,
	// so the darker water and the wall a body meets are readouts of ONE number.
	// Per-fragment for v_river's own sampling reason: 0.4 of an ~8 m band is
	// 3 m wide, under the ~3 m vertex spacing.
	float v_deep = 1.0 - smoothstep(
			river_half_width * river_deep_fraction * (1.0 - RIVER_EDGE_SOFT),
			river_half_width * river_deep_fraction * (1.0 + RIVER_EDGE_SOFT),
			abs(v_biome - river_level));

	// River last, on top of whatever biome it cuts through — rivers are an
	// overlay, not a biome (same rule as is_river_at() on the CPU side).
	//
	// ...except under the tower. THE DRY DISC is the twin of the extra step
	// is_river_at() takes on the CPU — same centre, same radius, same <= — so the
	// blue you SEE and the wading you FEEL still part company nowhere, and the
	// hard rim is exactly what lets the two agree (it is hidden under the shell
	// and its yard). Folded INTO this branch rather than standing above it: only a
	// river pixel can be masked, so only a river pixel pays for the distance, which
	// is the rule this `if` exists to enforce on a fill-rate-bound web target.
	// Inside the city the noise river is REPLACED by the authored Danube — one
	// river or the other, never both, the twin of is_river_at()'s early return —
	// and the Danube is then punched out by the dry rects.
	//
	// WHY THE DRY MASK IS PER-FRAGMENT while the band factor is per-vertex: a
	// bridge deck is 32 m wide and its edge is HARD. Interpolated over ~3 m of
	// vertex spacing it would fade, and the blue you see would stand a metre and
	// a half off the deck the CPU answers exactly. Up to 8 rects, four compares
	// each, and only for pixels actually inside the city.
	// KNOWN CPU/GPU DIVERGENCE, and it is the under-deck exception's shadow: the
	// dry rects below zero BOTH factors, so the bed at y = 0 under an authored
	// deck is painted DRY while a BODY there wades and meets the deep channel.
	// That is `is_river_at` (this) and `is_wading_at` (the CPU) answering two
	// different questions on purpose — see is_wading_at in endless_terrain.gd —
	// and it is only ever seen from under a 12 m bridge. Painting it wet instead
	// would put blue on the deck's own footprint at every other viewing angle,
	// which is the bug DRY_RECTS exists for.
	if (in_city) {
		v_river = v_city_river;
		v_deep = v_city_river_deep;
		for (int i = 0; i < city_dry_count; i++) {
			if (v_world_xz.x >= city_dry[i].x && v_world_xz.x <= city_dry[i].z
					&& v_world_xz.y >= city_dry[i].y && v_world_xz.y <= city_dry[i].w) {
				v_river = 0.0;
				v_deep = 0.0;
			}
		}
	}

	// The tower's dry disc does not apply inside the city (the `in_city ||`): the
	// mask exists to take the NOISE river out from under the shell, and inside
	// the rect there is no noise river left to take.
	if (v_river > 0.0
			&& (in_city || distance(v_world_xz, tower_dry_center) > tower_dry_radius)) {
		// Cheap crossed-sine shimmer: two sines drifting in opposite senses so
		// the interference pattern never reads as a repeating grid. World-space
		// input keeps it continuous across chunk seams, TIME makes it flow.
		float shimmer = sin(v_world_xz.x * 1.7 + TIME * 1.3)
				* sin(v_world_xz.y * 2.3 - TIME * 0.9);
		vec3 wet = river_color * (1.0 + shimmer * 0.12);
		albedo = mix(albedo, wet, v_river);
		// ...and the impassable centre strip darker still, on top of the band it
		// sits inside. One more mix and no new colour uniform: deep water is the
		// same water with less light coming back out of it.
		albedo = mix(albedo, wet * RIVER_DEEP_SHADE, v_deep);
		// Wet sheen for free — no transparency, no reflection, no extra pass.
		roughness = mix(roughness, 0.3, v_river);
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
