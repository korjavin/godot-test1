class_name TerrainProps
extends RefCounted
## THE THEMED SCATTERED PROPS — the seventeen builders that dress an accepted
## scatter spot, lifted whole out of endless_terrain.gd by bead godot-test1-ftn.2.
##
## MECHANICAL MOVE, and the A/B is the proof: not one draw, transform, colour,
## footprint or collision shape changed. Every function below is byte-identical to
## the one it replaced apart from the four rewrites the move itself forces — a
## leading `terrain: Node3D` parameter, `create_box(` becoming
## `terrain.create_box(`, the dispatch's `biome_at` / `Biome.` becoming
## `terrain.biome_at` / `terrain.Biome.`, and the inner `_prop_*` calls passing
## `terrain` on. The reasoning came WITH the code: the SHARED-STREAM RULE, the
## climbability contract, the per-builder box budgets and every palette note are
## the comments they always were, because they are what a future author needs
## beside the lines they explain.
##
## WHAT IS HERE: `build_prop` (the biome dispatch, one variant per territory) and
## the seventeen `_prop_*` builders, plus the family's whole constant banner.
##
## WHAT IS NOT: any decision about WHERE a prop goes. The scatter loop, its
## spacing rule, its river skip, its `DESERT_BLOCK_KEEP_EVERY` target and the
## `obstacles` append all stay in `spawn_objects_in_chunk` — this file is handed a
## spot that was already accepted and never asks how it was chosen.
##
## STATIC, LIKE landmark_builders.gd, and for its reason: there is no prop state
## to hold, so there is nothing to instantiate. `terrain` is typed `Node3D` in
## every signature because endless_terrain.gd declares no `class_name` — the same
## `ponytail:` note landmark_builders.gd carries, with the same cost (create_box
## resolves dynamically) and the same mitigation (prop_selfcheck calls all
## seventeen by name, so a rename fails the build rather than one chunk in fifty).
##
## THE CONSTANT BANNER MOVED WHOLE, AND EVERY CONSTANT IS ALIASED BACK. The epic's
## rule is that a family owns its constants; the measurement is that every one of
## these is ALSO read by the feature structures, the biome content or a self-check
## (PROP_MAX_STEP as far away as budapest_plan.gd). So the declarations live here
## and `endless_terrain.gd` re-exports each one as `const X := TerrainProps.X` —
## the `species_table.gd` precedent — which is what keeps all ~90 existing readers,
## `get_script_constant_map()` included, untouched by a move that was supposed to
## change nothing. A territory palette shared with the structures is arguably
## neither family's; re-homing it is ftn.3's call once the structures move too.

# ----------------------------------------------------------------------------
# THEMED SCATTERED PROPS — the re-skin of the old bare cube / cube-tower scatter
# ----------------------------------------------------------------------------
# The scatter loop in spawn_objects_in_chunk is UNCHANGED in everything that has
# consequences — same position draws, same min_object_spacing, same river skip,
# same DESERT_BLOCK_KEEP_EVERY target, same footprint entry. The only thing that
# changed is the GEOMETRY emitted at an accepted spot: instead of one cube (plus
# an occasional cube tower, which is why the old `stack_chance` / `stack_max_extra`
# exports are gone — the cairn and slab-stack VARIANTS are those towers now), a
# themed prop builder runs, chosen by biome_at at the PROP'S OWN position so the
# themes feather across a biome edge exactly like the biome content does.
#
# SHARED-STREAM RULE (the one thing a prop builder may never break): the chunk's
# RNG pays a FIXED cost per accepted spot — one randf_range for `size`, then ONE
# randi() as the prop SEED — whatever the variant. Builders run on a PRIVATE
# RandomNumberGenerator built from that seed (the artifact/camp private-RNG
# pattern, one level down) and are handed no shared rng at all, so a 3-box stump
# and an 8-box bone pile advance the chunk stream identically and prop complexity
# can never reshuffle the crocodiles, coins or structures that draw after them.
# Byte-identity with the PRE-prop world is deliberately not preserved (the same
# licence CLAUDE.md's biome feature-skip note takes); within-run purity is, and
# it holds unconditionally because every placement is still a pure function of
# chunk coords + run_seed.

## Footprint radius of a prop as a fraction of its drawn `size`. Every builder
## keeps ALL of its geometry — including tilted decoration — inside this radius
## of the prop's centre, so the returned radius stays an HONEST bound: it is what
## _settle_coin_y perches road coins against, what spawn_crocodiles_in_chunk
## keeps its NPCs out of, and what the mountain massifs avoid-list reads.
##
## 0.71 IS THE BARE CUBE'S OWN FACTOR, kept deliberately: the footprint rule is
## then literally unchanged from the cubes, so `size` still means the same thing,
## the range is still 0.71-1.78 m, and the value stays under MOUNTAIN_AVOID_RADIUS
## (2.0) — props remain "fair game" to bury in a massif exactly as cubes were, and
## the constant chain around that inequality needed no re-derivation.
const PROP_RADIUS_FACTOR: float = 0.71

## THE CLIMBABILITY CONTRACT, as a number. A prop that records `climbable: true`
## must be mountable from flat ground in steps no taller than this, each step
## landing on a FLAT (untilted) top — that is the "rest spot from crocodiles"
## role the bare cubes carried, and it breaks difficulty silently if it is lost.
## 2.6 sits under the player's jump apex (JUMP_VELOCITY^2 / 2*gravity = 3.6125 m)
## with room for the arc, and matches the old 2.5 m single-cube step that has
## been the proven size since the first chunk was generated.
## prop_selfcheck.gd measures the emitted geometry against this, per variant.
const PROP_MAX_STEP: float = 2.6

## --- Prop palettes. Deliberately distinct from the warm RAMP_* block ramps (the
## feature structures still use those), the artifacts' grey-green, the camps'
## bone white and the landmarks' place-specific colours — a themed prop should
## read as belonging to its BIOME, not to the generic block palette.
const PROP_BOULDER_A := Color(0.54, 0.52, 0.47)   # plains fieldstone …
const PROP_BOULDER_B := Color(0.40, 0.39, 0.36)   # … to darker granite
const PROP_RUIN_STONE := Color(0.68, 0.64, 0.55)  # cut, weathered masonry
const PROP_HAY := Color(0.79, 0.66, 0.31)         # straw bale
const PROP_CRATE := Color(0.44, 0.31, 0.18)       # cart timber
const PROP_SANDSTONE_A := Color(0.82, 0.67, 0.43) # wind-worn desert sandstone …
const PROP_SANDSTONE_B := Color(0.66, 0.50, 0.32) # … to its shaded underside
const PROP_BONE := Color(0.89, 0.87, 0.79)        # sun-bleached bone
const PROP_MOSS_ROCK := Color(0.39, 0.44, 0.32)   # damp forest boulder
const PROP_MOSS_CAP := Color(0.26, 0.41, 0.23)    # the moss growing on it
const PROP_STUMP := Color(0.35, 0.25, 0.16)       # cut stump / root flare
const PROP_LOG := Color(0.44, 0.32, 0.21)         # fallen log bark
const PROP_SCREE_A := Color(0.57, 0.57, 0.59)     # mountain scree …
const PROP_SCREE_B := Color(0.39, 0.40, 0.43)     # … to shadowed rock
const PROP_CAIRN := Color(0.50, 0.49, 0.46)       # stacked cairn slabs

## --- CITY palette. Eight new colours for a whole territory, and the count is a
## decision rather than an accident: the phase-1 rule is that every colour added
## is one more thing for a MultiMesh of boxes to fail to be distinct from, so the
## city reuses PROP_CRATE for every piece of timber it owns (doors, stall
## counters, market crates) and PROP_RUIN_STONE for its paving and garden walls,
## and spends new constants only where a city is unmistakable: limewashed
## plaster, a tiled or slated roof, and the three signal lamps.
##
## THE PLASTER RAMP IS DELIBERATELY BRIGHTER THAN EVERY OTHER TERRITORY'S STONE
## (r 0.71-0.87 against a highest-elsewhere 0.82 at the desert's sandstone, which
## is two bands away and can never touch it). That is not taste — prop_selfcheck
## requires each territory's stone_a to lie off every other territory's ramp, and
## the near-miss it is dodging is the mountain's PROP_SCREE_A, which sits almost
## exactly on a cooler grey plaster ramp.
const CITY_PLASTER_A := Color(0.87, 0.85, 0.79)   # limewashed wall, sunlit …
const CITY_PLASTER_B := Color(0.71, 0.66, 0.58)   # … to weathered render
const CITY_ROOF_TILE := Color(0.55, 0.29, 0.21)   # terracotta pantile
const CITY_ROOF_SLATE := Color(0.33, 0.34, 0.37)  # slate roof / awning canvas
const CITY_METAL := Color(0.26, 0.27, 0.29)       # lamp post, signal mast, head
const CITY_LAMP_AMBER := Color(0.96, 0.82, 0.36)  # bright ALBEDO, never emissive
const CITY_LAMP_RED := Color(0.86, 0.24, 0.20)
const CITY_LAMP_GREEN := Color(0.32, 0.76, 0.36)

## --- SNOW palette. FOUR new colours for a whole territory — the leanest of the
## six, and deliberately so: a tundra is a place with almost nothing in it, so the
## one thing it must not do is arrive with a paint box. Ice gets a ramp (it is the
## territory's stone), snow gets one flat near-white, and dead timber gets one
## grey-brown. Everything BONE reuses PROP_BONE, which the desert's bone pile
## already defines — the desert band (n < 0.34) and the snow band (n >= 0.83) can
## never touch, and a mammoth's ribs and a camel's ribs are honestly the same
## colour, so a fifth constant would buy nothing but one more near-white for a
## MultiMesh of boxes to fail to be distinct from.
##
## SNOW_ICE_A IS THE ONLY ONE WITH A CONSTRAINT ON IT: prop_selfcheck requires each
## territory's structure `stone_a` to lie off every other territory's ramp, and the
## near-miss it is dodging here is CITY_PLASTER_A — a bright off-white that a
## desaturated pale ice would sit straight on top of. The blue cast (b 0.96 against
## a red 0.80) is what separates them, not the brightness.
const SNOW_ICE_A := Color(0.80, 0.90, 0.96)     # sunlit glacier ice …
const SNOW_ICE_B := Color(0.50, 0.66, 0.80)     # … to its blue shadowed core
const SNOW_PACK := Color(0.95, 0.96, 0.98)      # wind-packed drift snow
const SNOW_DEADWOOD := Color(0.47, 0.44, 0.42)  # frost-bleached dead timber

# ============================================================================
# THEMED SCATTERED PROPS
# ============================================================================
# Everything below runs on a PRIVATE RandomNumberGenerator seeded from the one
# randi() the scatter loop drew for it. NONE of these functions takes the chunk
# RNG, which is what makes the fixed-shared-stream-cost rule structural instead
# of a discipline somebody has to remember. Draw as many or as few numbers as a
# variant needs.
#
# THREE RULES EVERY BUILDER OBEYS, because breaking any of them fails silently:
#
#  1. EVERY BOX STAYS INSIDE `size * PROP_RADIUS_FACTOR` OF THE PROP CENTRE.
#     That radius is the number returned, and it is what _settle_coin_y perches
#     road coins against, what spawn_crocodiles_in_chunk keeps crocodiles out of,
#     and what the massif avoid-list reads. A box poking outside it means a
#     crocodile spawned inside stone or a coin buried in it, with no error
#     anywhere. The bound used when sizing an offset decoration is half its own
#     3D DIAGONAL (`0.5 * dims.length()`), because a box carrying both a yaw and
#     a tilt can present a corner in any direction. prop_selfcheck.gd measures the
#     real emitted corners rather than trusting these comments.
#
#  2. A CLIMBABLE PROP IS ACTUALLY CLIMBABLE. The box whose top face is the
#     returned `top` is UNTILTED (a tilted box has no flat top to stand on) and
#     centred on the prop, and the untilted collidable tops form a ladder from
#     the ground up with no gap over PROP_MAX_STEP. Tilted decoration is welcome
#     — it is what stops a prop reading as a box — but it goes BESIDE the prop,
#     never on the surface the contract promises. This is the "rest spot from
#     crocodiles" role the bare cubes carried.
#
#  3. 3-8 BOXES, OF WHICH 1-3 COLLIDE. The whole chunk draws in one MultiMesh
#     whatever the box count, so instances are nearly free — but each colliding
#     box is a real CollisionShape3D node on the chunk's shared body, and that is
#     the budget the per-chunk node count lives on. Trim (chips, rubble, root
#     flares, ribs, loose stones) passes `collide = false`, exactly as a forest
#     canopy does.

static func build_prop(terrain: Node3D, local: Vector3, size: float, prop_seed: int, chunk_center: Vector3, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Build ONE themed scattered prop at a spot the scatter loop already accepted.

	@param local: The prop's chunk-LOCAL position, y = 0 (it sits on the ground).
	@param size: The prop's overall scale — the same object_size_min..max draw the
	             bare cube used, so props inherit the field's existing size spread.
	@param prop_seed: The one randi() the chunk stream paid for this prop. Every
	                  choice below hangs off it, so the prop is a pure function of
	                  chunk coords + run_seed like everything else in generation.
	@param chunk_center: World centre of the chunk — the prop's own WORLD position
	                     is what picks the theme (see below).
	@param block_batch / block_body: The chunk's single MultiMesh batch and single
	                     collision body. A prop adds ZERO draw calls and at most
	                     three collision shapes.
	@return { "radius": float, "top": float, "climbable": bool } — the footprint
	        the caller appends to `obstacles`, in exactly the shape the bare cube
	        used to append.

	THE THEME IS PICKED PER POSITION, NOT PER CHUNK CENTRE. That is deliberate and
	it is the same rule the biome content builders follow: a chunk straddling a
	forest edge grows stumps on the wooded half and boulders on the open half, so
	the transition follows the noise contour instead of stopping dead on a straight
	chunk seam. One extra noise evaluation per prop (~12 a chunk) buys it.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = prop_seed

	match terrain.biome_at(chunk_center.x + local.x, chunk_center.z + local.z):
		terrain.Biome.DESERT:
			match rng.randi_range(0, 2):
				0:
					return _prop_sandstone_stack(terrain, local, size, rng, block_batch, block_body)
				1:
					return _prop_broken_column(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_bone_pile(terrain, local, size, rng, block_batch, block_body)
		terrain.Biome.FOREST:
			match rng.randi_range(0, 2):
				0:
					return _prop_mossy_boulder(terrain, local, size, rng, block_batch, block_body)
				1:
					return _prop_tree_stump(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_log_pile(terrain, local, size, rng, block_batch, block_body)
		terrain.Biome.MOUNTAIN:
			match rng.randi_range(0, 1):
				0:
					return _prop_scree_cluster(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_cairn(terrain, local, size, rng, block_batch, block_body)
		terrain.Biome.CITY:
			match rng.randi_range(0, 2):
				0:
					return _prop_crate_stack(terrain, local, size, rng, block_batch, block_body)
				1:
					return _prop_garden_wall(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_paving_stack(terrain, local, size, rng, block_batch, block_body)
		terrain.Biome.SNOW:
			match rng.randi_range(0, 2):
				0:
					return _prop_ice_rock(terrain, local, size, rng, block_batch, block_body)
				1:
					return _prop_snow_drift(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_frozen_stump(terrain, local, size, rng, block_batch, block_body)
		_:  # PLAINS — also the fallback, so a future biome band still gets props.
			match rng.randi_range(0, 2):
				0:
					return _prop_boulder_cluster(terrain, local, size, rng, block_batch, block_body)
				1:
					return _prop_ruin_fragment(terrain, local, size, rng, block_batch, block_body)
				_:
					return _prop_bale_pile(terrain, local, size, rng, block_batch, block_body)

# ----- PLAINS ---------------------------------------------------------------

static func _prop_boulder_cluster(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — a field boulder with two smaller rocks nestled against it.

	The big rock is the climbable one, so it stays UNTILTED and its top face is
	the returned `top`. The companions carry the tilt that stops the whole thing
	reading as a cube, and they sit beside it rather than on it (rule 2 above).
	3 boxes, 3 collide.

	ALL THREE ARE `BoxKind.ROCK` since bead godot-test1-y1o.3 — a faceted dome with
	the flat lid still exactly at the box top, so the climbable surface, the
	collider and every number below are byte-for-byte what they were and only the
	silhouette moved. See ChunkBatch's BoxKind banner for why a squashed sphere was
	the wrong answer here.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var w := size * 0.9
	var h := minf(size * 0.85, PROP_MAX_STEP)
	var yaw := rng.randf_range(0.0, TAU)

	terrain.create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.92), yaw,
		rng, block_batch, block_body, 0.0, PROP_BOULDER_A.lerp(PROP_BOULDER_B, rng.randf()),
		true, ChunkBatch.BoxKind.ROCK
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.28, 0.42)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * 0.32
		terrain.create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.9, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.35, 0.35),
			PROP_BOULDER_A.lerp(PROP_BOULDER_B, rng.randf()), true, ChunkBatch.BoxKind.ROCK
		)

	return { "radius": r, "top": h, "climbable": true }

static func _prop_ruin_fragment(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — a stub of broken wall with one block fallen off it and rubble around.

	The wall stub is the climbable perch (untilted, flat top). 4 boxes, 2 collide
	— the chips are trim and would only make the base a snag to walk into.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	# The tallest prop step in the set, and deliberately capped at the bare cube's
	# own proven 2.5 m rather than at PROP_MAX_STEP: a stub that needed the very
	# last centimetre of the jump arc would be a rest spot only in theory.
	var h := minf(size * 1.05, 2.5)

	terrain.create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(size * 0.85, h, size * 0.42), yaw,
		rng, block_batch, block_body, 0.0, PROP_RUIN_STONE
	)

	# The fallen block, tilted where it came to rest, thrown clear of the wall face.
	var bs := size * rng.randf_range(0.30, 0.42)
	var ba := yaw + PI * 0.5 + rng.randf_range(-0.5, 0.5)
	terrain.create_box(
		local + Vector3(cos(ba) * size * 0.32, bs * 0.42, sin(ba) * size * 0.32),
		Vector3(bs, bs * 0.85, bs * 1.1), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(0.2, 0.5), PROP_RUIN_STONE
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.12, 0.22)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.45)
		terrain.create_box(
			local + Vector3(cos(a) * ring, cs * 0.4, sin(a) * ring),
			Vector3(cs, cs * 0.7, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4), PROP_RUIN_STONE, false
		)

	return { "radius": r, "top": h, "climbable": true }

static func _prop_bale_pile(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	PLAINS — two stacked hay bales with a cart crate against them and loose planks.

	The two-bale stack IS the old cube tower, re-skinned: both tiers are untilted
	and each is one easy step, so the climb the towers provided survives intact.
	5 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)

	var h1 := minf(size * 0.66, PROP_MAX_STEP)
	var w1 := size * 0.82
	terrain.create_box(
		local + Vector3(0.0, h1 * 0.5, 0.0), Vector3(w1, h1, w1 * 0.9), yaw,
		rng, block_batch, block_body, 0.0, PROP_HAY
	)

	var h2 := minf(h1 * 0.8, PROP_MAX_STEP)
	var w2 := w1 * 0.78
	terrain.create_box(
		local + Vector3(0.0, h1 + h2 * 0.5, 0.0), Vector3(w2, h2, w2 * 0.9),
		yaw + rng.randf_range(-0.4, 0.4), rng, block_batch, block_body, 0.0, PROP_HAY
	)

	var cs := size * rng.randf_range(0.22, 0.34)
	var ca := rng.randf_range(0.0, TAU)
	terrain.create_box(
		local + Vector3(cos(ca) * size * 0.38, cs * 0.5, sin(ca) * size * 0.38),
		Vector3(cs, cs, cs), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(-0.25, 0.25), PROP_CRATE
	)

	for _i in 2:
		var pl := size * rng.randf_range(0.30, 0.45)
		var pa := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.25, 0.40)
		terrain.create_box(
			local + Vector3(cos(pa) * ring, size * 0.05, sin(pa) * ring),
			Vector3(pl, size * 0.08, size * 0.16), pa + rng.randf_range(-0.5, 0.5),
			rng, block_batch, block_body, rng.randf_range(-0.15, 0.15), PROP_CRATE, false
		)

	return { "radius": r, "top": h1 + h2, "climbable": true }

# ----- DESERT ---------------------------------------------------------------

static func _prop_sandstone_stack(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — 2-3 wind-worn sandstone slabs stacked and shrinking, with one broken
	flake leaning at the base.

	The slabs are untilted so the stack climbs; the flake is the tilted character
	and sits BESIDE the stack, never on the top slab. 3-4 boxes, 2-3 collide.

	`BoxKind.ROCK` throughout since bead godot-test1-y1o.3: a wind-worn slab is a
	dome with a flat lid, which is exactly the kind's shape, and the lid keeps the
	stack's every step where the ladder already measured it.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var tiers := rng.randi_range(2, 3)
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.88
	var top := 0.0

	for _i in tiers:
		var th := minf(size * rng.randf_range(0.42, 0.68), PROP_MAX_STEP)
		terrain.create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.82),
			yaw + rng.randf_range(-0.3, 0.3), rng, block_batch, block_body, 0.0,
			PROP_SANDSTONE_A.lerp(PROP_SANDSTONE_B, rng.randf() * 0.7),
			true, ChunkBatch.BoxKind.ROCK
		)
		top += th
		w *= 0.82

	var fs := size * rng.randf_range(0.30, 0.45)
	var fa := rng.randf_range(0.0, TAU)
	terrain.create_box(
		local + Vector3(cos(fa) * size * 0.32, fs * 0.5, sin(fa) * size * 0.32),
		Vector3(fs, fs * 1.2, fs * 0.25), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(0.5, 0.9), PROP_SANDSTONE_B, false,
		ChunkBatch.BoxKind.ROCK
	)

	return { "radius": r, "top": top, "climbable": true }

static func _prop_broken_column(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — a half-buried column: one surviving drum still standing on its broken
	flat top, the toppled shaft lying beside it, chips around the base.
	4 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var dw := size * 0.62
	var dh := minf(size * rng.randf_range(0.7, 1.0), PROP_MAX_STEP)

	terrain.create_box(
		local + Vector3(0.0, dh * 0.5, 0.0), Vector3(dw, dh, dw), yaw,
		rng, block_batch, block_body, 0.0, PROP_SANDSTONE_A
	)

	# The fallen shaft, offset PERPENDICULAR to its own long axis so its length
	# stays inside the radius (offsetting along the axis would push a corner out).
	var sa := rng.randf_range(0.0, TAU)
	var sl := size * rng.randf_range(0.55, 0.75)
	var perp := Vector3(cos(sa + PI * 0.5), 0.0, sin(sa + PI * 0.5)) * size * 0.26
	terrain.create_box(
		local + perp + Vector3(0.0, dw * 0.28, 0.0),
		Vector3(sl, dw * 0.56, dw * 0.56), sa,
		rng, block_batch, block_body, rng.randf_range(-0.15, 0.15),
		PROP_SANDSTONE_A.lerp(PROP_SANDSTONE_B, 0.5)
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.12, 0.20)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		terrain.create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.8, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5), PROP_SANDSTONE_B, false
		)

	return { "radius": r, "top": dh, "climbable": true }

static func _prop_bone_pile(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	DESERT — a bleached ribcage scattered in the sand. THE ONE NON-CLIMBABLE
	VARIANT: a heap of tilted ribs has no flat top to stand on, so it honestly
	records climbable = false and _settle_coin_y SKIPS a road coin over it rather
	than floating one on a surface that is not there (the tree-canopy rule).

	Keeping it to one variant of eleven is deliberate — the bare cubes' rest-spot
	role is the thing this whole re-skin must not quietly delete, so desert still
	offers two climbable props in three and every other biome offers three.
	5-7 boxes, 1 collides (the skull lump, so the heap is not walk-through).
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var ss := size * rng.randf_range(0.30, 0.42)

	terrain.create_box(
		local + Vector3(0.0, ss * 0.45, 0.0), Vector3(ss, ss * 0.85, ss * 1.15), yaw,
		rng, block_batch, block_body, rng.randf_range(-0.2, 0.2), PROP_BONE
	)

	for _i in rng.randi_range(4, 6):
		var rib := size * rng.randf_range(0.35, 0.60)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.0, 0.22)
		terrain.create_box(
			local + Vector3(cos(a) * ring, size * rng.randf_range(0.05, 0.18), sin(a) * ring),
			Vector3(rib, size * 0.07, size * 0.09), a + rng.randf_range(-0.6, 0.6),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5), PROP_BONE, false
		)

	return { "radius": r, "top": ss * 0.9, "climbable": false }

# ----- FOREST ---------------------------------------------------------------

static func _prop_mossy_boulder(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — a damp boulder wearing a cap of moss, with two small rocks at its foot.

	The moss cap COLLIDES and its top face is the returned `top`, so you stand on
	the moss rather than clipping into it — and the rock height is derived from
	PROP_MAX_STEP minus the cap, so cap + rock together still clear in one jump
	however object_size_max is retuned. 4 boxes, 2 collide.

	`BoxKind.ROCK` throughout since bead godot-test1-y1o.3, THE MOSS CAP INCLUDED —
	the cap is the surface you stand on, and a cube lid on a domed boulder would
	read as a plate balanced on it. Both are drawn at the same yaw, so the cap's
	facets line up with the flanks under them and the two read as one stone.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var cap_h := size * 0.14
	var bh := minf(size * 0.72, PROP_MAX_STEP - cap_h)
	var bw := size * 0.88

	terrain.create_box(
		local + Vector3(0.0, bh * 0.5, 0.0), Vector3(bw, bh, bw * 0.9), yaw,
		rng, block_batch, block_body, 0.0, PROP_MOSS_ROCK, true, ChunkBatch.BoxKind.ROCK
	)
	terrain.create_box(
		local + Vector3(0.0, bh + cap_h * 0.5, 0.0), Vector3(bw * 0.96, cap_h, bw * 0.87), yaw,
		rng, block_batch, block_body, 0.0, PROP_MOSS_CAP, true, ChunkBatch.BoxKind.ROCK
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.22, 0.34)
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.34, cs * 0.4, sin(a) * size * 0.34),
			Vector3(cs, cs * 0.75, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.45, 0.45), PROP_MOSS_ROCK, false,
			ChunkBatch.BoxKind.ROCK
		)

	return { "radius": r, "top": bh + cap_h, "climbable": true }

static func _prop_tree_stump(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — a wide cut stump with three root flares splaying out at ground level.

	The roots are VISUAL ONLY: they spread past the stump's own width, and making
	them solid would turn every stump into a ring of ankle-height snags. The flat
	saw-cut top is the perch. 4 boxes, 1 collides.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var sw := size * 0.86
	var sh := minf(size * rng.randf_range(0.55, 0.80), PROP_MAX_STEP)

	terrain.create_box(
		local + Vector3(0.0, sh * 0.5, 0.0), Vector3(sw, sh, sw * 0.94), yaw,
		rng, block_batch, block_body, 0.0, PROP_STUMP
	)

	for i in 3:
		var a := yaw + TAU * float(i) / 3.0 + rng.randf_range(-0.35, 0.35)
		var rl := size * rng.randf_range(0.36, 0.50)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.36, size * 0.09, sin(a) * size * 0.36),
			Vector3(rl, size * 0.18, size * 0.22), a,
			rng, block_batch, block_body, rng.randf_range(-0.25, -0.05), PROP_STUMP, false
		)

	return { "radius": r, "top": sh, "climbable": true }

static func _prop_log_pile(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	FOREST — two felled logs side by side with a third laid across them, plus a
	couple of loose branches.

	The upper log's top face is flat and one short step up, so the pile stays a
	rest spot. 5 boxes, 3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var a := rng.randf_range(0.0, TAU)
	var log_len := size * 0.9
	var log_d := size * 0.30
	var perp := Vector3(cos(a + PI * 0.5), 0.0, sin(a + PI * 0.5)) * log_d * 0.55

	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		terrain.create_box(
			local + perp * s + Vector3(0.0, log_d * 0.5, 0.0),
			Vector3(log_len, log_d, log_d), a,
			rng, block_batch, block_body, 0.0, PROP_LOG
		)

	terrain.create_box(
		local + Vector3(0.0, log_d * 1.5, 0.0),
		Vector3(log_len * 0.85, log_d, log_d), a + rng.randf_range(-0.5, 0.5),
		rng, block_batch, block_body, 0.0, PROP_LOG
	)

	for _i in 2:
		var bl := size * rng.randf_range(0.25, 0.40)
		var ba := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		terrain.create_box(
			local + Vector3(cos(ba) * ring, size * 0.05, sin(ba) * ring),
			Vector3(bl, size * 0.10, size * 0.12), ba + rng.randf_range(-0.6, 0.6),
			rng, block_batch, block_body, rng.randf_range(-0.3, 0.3), PROP_LOG, false
		)

	return { "radius": r, "top": log_d * 2.0, "climbable": true }

# ----- MOUNTAIN -------------------------------------------------------------

static func _prop_scree_cluster(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	MOUNTAIN — one flat slab of fallen rock with 3-4 shattered chips tumbled round
	it. The slab is the perch; the chips carry the tilt. 4-5 boxes, 1 collides.

	`BoxKind.ROCK` throughout since bead godot-test1-y1o.3. The chips could have
	been CONEs — the bead offers both — and are not, on the draw-call bill: a cone
	bucket would make a mountain chunk carrying scree cost THREE block draw calls
	where the epic's cap for a chunk is two, and nothing here would look better for
	it.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var sw := size * 0.84
	var sh := minf(size * rng.randf_range(0.45, 0.70), PROP_MAX_STEP)

	terrain.create_box(
		local + Vector3(0.0, sh * 0.5, 0.0), Vector3(sw, sh, sw * 0.88), yaw,
		rng, block_batch, block_body, 0.0, PROP_SCREE_A.lerp(PROP_SCREE_B, rng.randf()),
		true, ChunkBatch.BoxKind.ROCK
	)

	for _i in rng.randi_range(3, 4):
		var cs := size * rng.randf_range(0.16, 0.30)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.30, 0.42)
		terrain.create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.8, cs * 1.2), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.6, 0.6),
			PROP_SCREE_A.lerp(PROP_SCREE_B, rng.randf()), false, ChunkBatch.BoxKind.ROCK
		)

	return { "radius": r, "top": sh, "climbable": true }

static func _prop_cairn(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	MOUNTAIN — a three-slab cairn with two loose stones at its foot. THIS IS THE
	OLD CUBE TOWER, re-skinned: the tallest prop in the set, all three tiers
	untilted and each one a short step, so the tower's climb survives its cube.

	NO CAPSTONE ON TOP, deliberately — a tilted stone crowning the cairn would
	look right and quietly destroy the flat surface the climbability contract
	promises. The loose stones go beside it instead. 5 boxes, 3 collide.

	THE TIERS STAY `CUBE`, and that is the bead's own ruling (godot-test1-y1o.3): a
	cairn IS stacked, split, flat-faced stones, so the one prop in the set that
	should read as blocks is this one. Only the loose stones at its foot — which
	were never stacked by anybody — take `BoxKind.ROCK`.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.72
	var top := 0.0

	for _i in 3:
		var th := minf(size * rng.randf_range(0.38, 0.58), PROP_MAX_STEP)
		terrain.create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.9),
			yaw + rng.randf_range(-0.5, 0.5), rng, block_batch, block_body, 0.0,
			PROP_CAIRN.lerp(PROP_SCREE_B, rng.randf() * 0.5)
		)
		top += th
		w *= 0.8

	for _i in 2:
		var cs := size * rng.randf_range(0.18, 0.28)
		var a := rng.randf_range(0.0, TAU)
		var ring := size * rng.randf_range(0.32, 0.44)
		terrain.create_box(
			local + Vector3(cos(a) * ring, cs * 0.45, sin(a) * ring),
			Vector3(cs, cs * 0.85, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
			PROP_CAIRN.lerp(PROP_SCREE_B, rng.randf() * 0.5), false, ChunkBatch.BoxKind.ROCK
		)

	return { "radius": r, "top": top, "climbable": true }

# ----- CITY -----------------------------------------------------------------
#
# Street clutter, at the same scale the bare cubes were: crates against a wall, a
# low garden wall with its planter, a pallet of paving slabs from the roadworks.
# All three keep the climbability contract (the box whose top face is the returned
# `top` is untilted, colliding and centred on the prop), and all three reuse the
# existing PROP_CRATE / PROP_RUIN_STONE timber and stone rather than adding a
# colour — the CITY_* palette is spent on the buildings, which is where a person
# actually reads "city".

static func _prop_crate_stack(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — two market crates stacked against each other with a third tipped over
	beside them. The stack is the perch: both crates untilted, colliding and
	centred, each one a short step. The tipped crate carries the tilt and is trim.
	3 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.62
	var top := 0.0

	for i in 2:
		var th := minf(size * rng.randf_range(0.42, 0.60), PROP_MAX_STEP)
		terrain.create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.95),
			yaw + rng.randf_range(-0.25, 0.25), rng, block_batch, block_body, 0.0,
			PROP_CRATE.lerp(CITY_PLASTER_B, rng.randf() * 0.35)
		)
		top += th
		w *= 0.88

	# The tipped crate. Its offset is bounded by half its own 3D diagonal
	# (cs * 0.866 for a near-cube), because a box carrying a yaw AND a tilt can
	# present a corner in any direction: 0.30 + 0.32 * 0.866 = 0.577 of size,
	# inside PROP_RADIUS_FACTOR 0.71.
	var cs := size * rng.randf_range(0.24, 0.32)
	var a := rng.randf_range(0.0, TAU)
	terrain.create_box(
		local + Vector3(cos(a) * size * 0.30, cs * 0.45, sin(a) * size * 0.30),
		Vector3(cs, cs * 0.9, cs), rng.randf_range(0.0, TAU),
		rng, block_batch, block_body, rng.randf_range(-0.5, 0.5),
		PROP_CRATE.lerp(CITY_PLASTER_B, rng.randf() * 0.35), false
	)

	return { "radius": r, "top": top, "climbable": true }

static func _prop_garden_wall(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — a stub of low garden wall with a planter box set against it and a
	couple of pots tipped at its foot.

	The wall is the perch and is CENTRED on the prop, which is the part that
	matters: prop_selfcheck's climb ladder only counts untilted colliding boxes
	whose footprint covers the prop's centre, so a pair of offset wall segments
	with nothing in the middle would be a prop that records climbable = true and
	has nothing to stand on. 4 boxes, 2 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var h := minf(size * rng.randf_range(0.55, 0.80), PROP_MAX_STEP)
	var wall_len := size * 1.02
	var wall_d := size * 0.28

	terrain.create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(wall_len, h, wall_d), yaw,
		rng, block_batch, block_body, 0.0,
		PROP_RUIN_STONE.lerp(CITY_PLASTER_B, rng.randf())
	)

	# Planter, set against the wall's face. Reach = 0.40 + 0.5*hypot(0.34, 0.34)
	# = 0.64 of size, inside the declared 0.71.
	var pw := size * 0.34
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var normal := Vector3(cos(yaw + PI * 0.5), 0.0, sin(yaw + PI * 0.5))
	terrain.create_box(
		local + normal * (size * 0.40 * side) + Vector3(0.0, pw * 0.5, 0.0),
		Vector3(pw, pw, pw), yaw, rng, block_batch, block_body, 0.0, PROP_CRATE
	)

	for _i in 2:
		var cs := size * rng.randf_range(0.13, 0.18)
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.42, cs * 0.45, sin(a) * size * 0.42),
			Vector3(cs, cs * 1.1, cs), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4),
			CITY_ROOF_TILE, false
		)

	return { "radius": r, "top": h, "climbable": true }

static func _prop_paving_stack(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY — a pallet of paving slabs from the roadworks, with a couple of loose
	slabs leaning against it. Flat, wide and low: the shortest climb in the set.
	4-5 boxes, 2-3 collide.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.72
	var top := 0.0

	for _i in rng.randi_range(2, 3):
		var th := minf(size * rng.randf_range(0.22, 0.34), PROP_MAX_STEP)
		terrain.create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.82),
			yaw + rng.randf_range(-0.12, 0.12), rng, block_batch, block_body, 0.0,
			PROP_RUIN_STONE.lerp(CITY_METAL, rng.randf() * 0.35)
		)
		top += th
		w *= 0.94

	# Loose slabs, leaning. Half their 3D diagonal is 0.5 * |(0.50, 0.09, 0.42)|
	# = 0.338 of size, so a 0.34 ring reaches 0.678 — inside the declared 0.71.
	for _i in 2:
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.34, size * 0.10, sin(a) * size * 0.34),
			Vector3(size * 0.50, size * 0.09, size * 0.42), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.7, 0.7),
			PROP_RUIN_STONE.lerp(CITY_METAL, rng.randf() * 0.35), false
		)

	return { "radius": r, "top": top, "climbable": true }

# ----- SNOW -----------------------------------------------------------------
#
# The tundra's small clutter, at the same scale the bare cubes were. All three are
# CLIMBABLE, and in this one territory that is a design statement rather than an
# incidental: snow is the most hostile band in the game (croc density is the
# ordinary distance-scaled figure — only the city thins it), so the ice you can
# stand on top of is the whole of the rest-from-crocodiles role out here. Every
# perch is therefore an untilted, colliding, centred box whose top face IS the
# returned `top`; the shards, scour lumps and broken branches carry the tilt and
# sit beside the prop, never on it.

static func _prop_ice_rock(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — a flat-topped block of glacier ice with two or three shards split off it
	and leaning against its flanks. The block is the perch. 3-4 boxes, 1 collides.

	OPAQUE, never transparent: the blue-white ramp is what has to read as ice, and
	an alpha-blended box would cost fill rate on a mobile GPU AND drop out of the
	chunk's one MultiMesh (which has a single opaque material) for the privilege.

	`BoxKind.ROCK` since bead godot-test1-y1o.3 — glacier ice is a weathered lump
	with a wind-scoured flat top, which is the kind's exact profile, and the shards
	take it too so a snow chunk pays for ONE extra bucket and not two.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.86
	var h := minf(size * rng.randf_range(0.60, 0.95), PROP_MAX_STEP)

	terrain.create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.90), yaw,
		rng, block_batch, block_body, 0.0, SNOW_ICE_A.lerp(SNOW_ICE_B, rng.randf() * 0.7),
		true, ChunkBatch.BoxKind.ROCK
	)

	# The split shards. Half a shard's 3D diagonal is
	# 0.5 * |(0.16, 0.55, 0.20)| = 0.303 of size, so a 0.38 ring reaches 0.683 —
	# inside the declared 0.71, whatever yaw and tilt it ends up carrying.
	for _i in rng.randi_range(2, 3):
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.38, size * 0.24, sin(a) * size * 0.38),
			Vector3(size * 0.16, size * 0.55, size * 0.20), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.55, 0.55),
			SNOW_ICE_A.lerp(SNOW_ICE_B, rng.randf()), false, ChunkBatch.BoxKind.ROCK
		)

	return { "radius": r, "top": h, "climbable": true }

static func _prop_snow_drift(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — a wind-packed drift: two wide shallow tiers with a couple of scour lumps
	tumbled off the lee side. The lowest, widest prop in the whole set — a drift is
	a shape the wind made, so it spreads rather than stacks. 4-5 boxes, 2 collide.

	THE LOWER TIER IS A `BoxKind.ROCK` AND THE UPPER ONE STAYS A CUBE (bead
	godot-test1-y1o.5). Wind-packed snow is a swell, so the base wanted to stop
	being a slab — but this prop is one of the three that carry the SNOW band's
	entire "rest from crocodiles" role (`climbable: true`, and `_settle_coin_y`
	perches a road coin on the returned `top`), so the LANDING has to stay a real
	flat top and the cap stays a cube.

	ROCK RATHER THAN THE SPHERE THE BEAD SKETCHED, and the reason is the draw-call
	bill, not taste. A prop's theme is picked at ITS OWN position (that is what
	feathers a biome edge), so a snow drift appears in every band that borders
	snow — measured: it put a SPHERE bucket into MOUNTAIN chunks as well as SNOW
	ones, i.e. a new MultiMeshInstance3D in three or four biomes for one prop.
	ROCK is already in every biome (bead y1o.3), so the same faceted swell costs
	**nothing anywhere**, and a wind-carved drift is closer to the rock's
	irregular faceting than to a smooth ellipsoid anyway.

	NOT ONE DIMENSION OR CENTRE MOVED, and ROCK keeps the `BoxShape3D` every
	flat-topped kind has — so the collider is byte-for-byte the one it always had.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	# Half-diagonal of the base tier is 0.5 * |(0.95, 0.85)| = 0.637 of size, so
	# even at full yaw the widest tier stays inside the declared 0.71.
	var w := size * 0.95
	var top := 0.0

	for i in 2:
		var th := minf(size * rng.randf_range(0.20, 0.32), PROP_MAX_STEP)
		terrain.create_box(
			local + Vector3(0.0, top + th * 0.5, 0.0), Vector3(w, th, w * 0.89),
			yaw + rng.randf_range(-0.18, 0.18), rng, block_batch, block_body, 0.0,
			SNOW_PACK.lerp(SNOW_ICE_A, rng.randf() * 0.5), true,
			ChunkBatch.BoxKind.ROCK if i == 0 else ChunkBatch.BoxKind.CUBE
		)
		top += th
		w *= 0.80

	# Scour lumps. Half a lump's 3D diagonal at its widest is
	# 0.5 * 0.22 * |(1, 0.7, 1.3)| = 0.196 of size; a 0.42 ring reaches 0.616.
	for _i in rng.randi_range(1, 2):
		var cs := size * rng.randf_range(0.14, 0.22)
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.42, cs * 0.42, sin(a) * size * 0.42),
			Vector3(cs, cs * 0.7, cs * 1.3), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.35, 0.35),
			SNOW_PACK.lerp(SNOW_ICE_A, rng.randf() * 0.5), false
		)

	return { "radius": r, "top": top, "climbable": true }

static func _prop_frozen_stump(terrain: Node3D, local: Vector3, size: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	SNOW — the frost-split stump of a dead tree, with two or three broken branch
	stubs still jutting out of it and a cap of drifted snow on the break.

	The stump is the perch, so the snow cap is a THIN FILM over it (collide = false,
	the STRUCTURE_THEMES `cap` arrangement) rather than another tier: the surface
	the player stands on is the stump's own top face, which is the height returned.
	4-6 boxes, 1 collides.
	"""
	var r := size * PROP_RADIUS_FACTOR
	var yaw := rng.randf_range(0.0, TAU)
	var w := size * 0.62
	# Capped at the bare cube's proven 2.5 m rather than at PROP_MAX_STEP (2.6), the
	# same call _prop_ruin_fragment makes and for the same reason: a perch that
	# needed the very last centimetre of the jump arc is a rest spot only on paper.
	var h := minf(size * rng.randf_range(0.70, 1.05), 2.5)

	terrain.create_box(
		local + Vector3(0.0, h * 0.5, 0.0), Vector3(w, h, w * 0.94), yaw,
		rng, block_batch, block_body, 0.0, SNOW_DEADWOOD
	)

	# Snow on the break: a film, not a step. 6 cm of it at size 1.
	terrain.create_box(
		local + Vector3(0.0, h + size * 0.03, 0.0), Vector3(w * 1.05, size * 0.06, w * 0.99),
		yaw, rng, block_batch, block_body, 0.0, SNOW_PACK, false
	)

	# Broken branch stubs. Half a stub's 3D diagonal is
	# 0.5 * |(0.10, 0.42, 0.10)| = 0.222 of size; a 0.24 ring reaches 0.462.
	for _i in rng.randi_range(2, 3):
		var a := rng.randf_range(0.0, TAU)
		terrain.create_box(
			local + Vector3(cos(a) * size * 0.24, h * rng.randf_range(0.45, 0.85), sin(a) * size * 0.24),
			Vector3(size * 0.10, size * 0.42, size * 0.10), a,
			rng, block_batch, block_body, rng.randf_range(0.7, 1.2), SNOW_DEADWOOD, false
		)

	return { "radius": r, "top": h, "climbable": true }
