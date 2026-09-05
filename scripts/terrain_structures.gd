class_name TerrainStructures
extends RefCounted
## THE THEMED FEATURE STRUCTURES — the four ROLES (mound, gate, corridor, wall)
## and the per-territory table that dresses them, lifted whole out of
## endless_terrain.gd by bead godot-test1-ftn.3. `terrain_props.gd`'s sibling, one
## scale up: a prop is scenery you walk past, a structure is scenery you climb.
##
## MECHANICAL MOVE, and the A/B is the proof: not one draw, transform, colour,
## footprint, platform or collision shape changed. Every function below is
## byte-identical to the one it replaced apart from the rewrites the move itself
## forces — a leading `terrain: Node3D`, `create_box(` / `biome_at(` /
## `is_river_at(` / `tower_excludes(` / `Biome.` reached through it, the sibling
## `spawn_*` and `_structure_*` calls passing `terrain` on, and the two tables
## above read as `terrain.STRUCTURE_*`. The reasoning came WITH the code.
##
## WHAT IS HERE: `spawn_feature_structure` (the per-territory role pick), the four
## role builders, `_structure_chance_at` (the per-territory threshold) and
## `_structure_stone` (the theme's colour sampler), plus the `STRUCT_GATE_*`
## styles and the `MOUND_*` knobs.
##
## WHAT STAYED IN endless_terrain.gd: `STRUCTURE_MIX` and `STRUCTURE_THEMES`.
## They are KEYED BY `Biome`, an enum declared over there, and a `const` in this
## file cannot name it — `terrain.Biome.X` resolves on an INSTANCE, which no const
## initialiser has. A table keyed by the world engine's own enum is world-engine
## data anyway, so the two are read off `terrain` here and the chosen `theme` is
## passed to each role builder as the plain parameter it always was.
##
## WHAT IS NOT: WHETHER a chunk gets one. The roll lives in
## `spawn_objects_in_chunk` beside the scarcity factor it is multiplied by, on the
## SHARED chunk object stream — and that is the load-bearing part of this move:
## these builders draw from the chunk RNG the scatter loop and the crocodiles
## share, so the extraction may not change the draw ORDER by one call. It does
## not; the 625-chunk A/B is `cmp`-clean.
##
## STATIC, LIKE landmark_builders.gd and terrain_props.gd, and `terrain` is typed
## `Node3D` for their reason: endless_terrain.gd declares no `class_name`.
##
## THE PALETTES STAYED IN TerrainProps, AND THAT IS A DELIBERATE JUDGEMENT.
## Bead ftn.2 moved the whole prop constant banner — including the CITY_* and
## SNOW_* TERRITORY palettes that the structures also read — and its header said
## re-homing them was this bead's call once the structures moved too. The call is:
## LEAVE THEM. A third file holding nothing but ~29 colours, read by exactly two
## static libraries, is a file to keep in step for no behavioural gain, and the
## dependency it would replace is already the simplest one available —
## `TerrainStructures` -> `TerrainProps`, ONE WAY and acyclic. As it turns out
## this file needs none of them directly: the one table that names a palette
## (`STRUCTURE_THEMES`) stayed in endless_terrain.gd for the Biome reason above,
## where those names are already that file's own TerrainProps aliases and read
## exactly as they did. So the colours moved nowhere, nothing was duplicated, and
## no third file was created. Revisit it only if a THIRD family needs them.

# ----------------------------------------------------------------------------
# THEMED FEATURE STRUCTURES — the same re-skin, one scale up from the props
# ----------------------------------------------------------------------------
# spawn_feature_structure used to pick wall / corridor / gate / Mayan step-pyramid
# from ONE global table, so the identical grey boxes stood in every region and the
# pyramid (the owner's "especially ugly") stood in all four. It now picks from a
# PER-TERRITORY table and dresses whichever ROLE it picked in that territory's
# materials — exactly the phase-1 prop move, one scale up:
#
#   * THE FOUR ROLES ARE FIXED and each keeps its gameplay job. A wall is a
#     barrier with a walkable ridge; a corridor is a lane you sprint down; a gate
#     is a thing you run under; the mound is the climbable stepped centrepiece
#     with a platform on top — the pyramid's ROLE, none of its look.
#   * WHAT CHANGES PER TERRITORY is the mix (which roles come up, and how often),
#     the palette, and a handful of shape knobs in STRUCTURE_THEMES below. That is
#     what makes a desert colonnade, a forest log bridge and a mountain fort out of
#     three lines of table instead of twelve builders.
#   * ONE rng.randf() PICK DRAW, exactly as before. The biome is read from
#     chunk_center — a pure function of chunk coords — so choosing the table costs
#     no draw at all and the dispatch stays post-draw.
#   * TRIM NEVER GOES ON A WALKABLE TOP. Themed clutter (rubble, moss, cornices,
#     capstones) is `collide = false` and either beside the structure or a thin
#     film over it; the box whose top face a platform or a climbable footprint
#     names is always an untilted, colliding, full-size one. That is prop rule 2
#     restated for structures, and prop_selfcheck.gd measures it.
#
# DRAW-COUNT CONSEQUENCE, stated plainly: the builders draw a different number of
# randoms than they used to, so a chunk's scattered blocks, crocodiles and coins
# shuffle relative to the pre-theme world. That is the same licence the biome
# feature-skip note and the phase-1 prop re-skin already took — WITHIN-RUN purity
# is the load-bearing half, and it holds unconditionally because every placement
# is still a pure function of chunk coords + run_seed.

## The gate's three dressings. A `gate_style` in STRUCTURE_THEMES picks one.
const STRUCT_GATE_ARCH: int = 0   # broken arch: one stunted pillar, a stub lintel
const STRUCT_GATE_LINTEL: int = 1 # intact monumental gate (+ a cornice if capped)
const STRUCT_GATE_LOG: int = 2    # a felled giant on two stumps — a WALKABLE deck

## The widest a mound terrace can reach in WORLD X/Z as a fraction of base_size.
## A terrace is a (w, d) slab turned by up to MOUND_TERRACE_YAW, so its rotated
## world half-extent is 0.5 * (w * cos + d * sin) — at the base terrace's widest
## (d == w == base_size) and the full yaw, 0.5 * (cos 0.35 + sin 0.35) = 0.641 of
## base_size, NOT the 0.5 the unrotated half-width suggests. That difference is up
## to 2.8 m on a 20 m mound, which is enough to hang a terrace over the chunk seam
## — and a mound's mesh and collision belong to ONE chunk, so the overhang would
## vanish the moment that chunk unloaded while its neighbour stayed loaded.
## 0.65 bounds 0.641 with slack; it stays under the footprint radius factor 0.71,
## so the obstacle circle is still an honest bound on the stone.
const MOUND_ROT_EXTENT: float = 0.65

## The most a terrace may be turned. Bounded rather than free because
## MOUND_ROT_EXTENT above is derived from it — widen one and re-derive the other.
const MOUND_TERRACE_YAW: float = 0.35

## Lateral wobble (metres) allowed per terrace of a terraced mound. Bounded, not
## chosen by eye: the mound's footprint radius is base_size * 0.71 and a terrace
## above the base is at most 0.72 * base_size wide, i.e. 0.51 * base_size of
## half-diagonal, so 0.9 m of wobble still fits inside the declared radius for the
## smallest mound the builder can draw (8 m base: 4.07 + 0.9 = 4.97 < 5.68).
const MOUND_TERRACE_JITTER: float = 0.9

## Mountain chunks build a feature structure a bit less often — massifs already
## dominate the skyline there, and a fort stub competing with a 20 m wall of rock
## reads as clutter. THIS IS A THRESHOLD, NOT AN EXTRA ROLL: _structure_chance_at
## scales the number the ONE existing rng.randf() is compared against, so no draw
## is inserted anywhere and the gate stays a pure function of chunk coords (the
## same discipline DESERT_BLOCK_KEEP_EVERY follows for scattered blocks).
const MOUNTAIN_STRUCTURE_CHANCE_FACTOR: float = 0.55

static func _structure_chance_at(terrain: Node3D, chunk_center: Vector3) -> float:
	"""
	How likely THIS chunk is to get a feature structure.

	@param chunk_center: World-space centre of the chunk.
	@return: terrain.structure_chance, scaled down in the mountain band.

	A THRESHOLD, NOT A ROLL. spawn_objects_in_chunk still draws exactly one
	rng.randf() and compares it against this number, so no draw is inserted or
	removed anywhere and the shared chunk stream is untouched by the biome —
	the same discipline DESERT_BLOCK_KEEP_EVERY follows by lowering a TARGET
	rather than rolling per candidate. biome_at is a pure function of world
	position, so the gate stays a pure function of chunk coords + run_seed.

	The consequence when the gate DOES reject is the documented one: the whole
	structure's draw sequence is skipped, so that mountain chunk's scattered
	blocks land differently than they would have. Within-run purity is unharmed.
	"""
	if terrain.biome_at(chunk_center.x, chunk_center.z) == terrain.Biome.MOUNTAIN:
		return terrain.structure_chance * MOUNTAIN_STRUCTURE_CHANCE_FACTOR
	return terrain.structure_chance

static func _structure_stone(terrain: Node3D, theme: Dictionary, rng: RandomNumberGenerator) -> Color:
	"""
	One solid box's colour, sampled off this territory's two-colour ramp.

	@param theme: A terrain.STRUCTURE_THEMES row.
	@param rng: The chunk's seeded RNG — one draw, so the sequence cost of a
	            themed box is a constant the builders can reason about.
	@return: The colour to hand create_box as its color_override.

	One lerp off a curated pair, exactly like the RAMP_* blocks it replaces —
	so a structure varies stone to stone without any territory's structures
	ever sharing a colour with another's. prop_selfcheck.gd measures that: it
	requires every emitted colour to lie on its own theme's segment, and the
	four segments to be pairwise distinct.
	"""
	var a: Color = theme["stone_a"]
	var b: Color = theme["stone_b"]
	return a.lerp(b, rng.randf())

static func spawn_feature_structure(terrain: Node3D, rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Pick and build one "feature" structure for variety, dressed in the territory
	it stands in: a barrier wall, a run-through lane, a gate, or a terraced mound.
	Walls, mounds and the forest's log bridge also register a walkable top
	(platforms) that a patrolling crocodile can be placed on.

	@param rng: The chunk's seeded RNG (so the choice is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World-space centre of the chunk. TWO jobs: it picks the
	                  territory (a pure function of chunk coords, so choosing the
	                  mix and the palette costs no RNG draw), and each builder
	                  turns its chunk-LOCAL centre into a world position for the
	                  river test — structures never stand in the water.
	@param obstacles: Footprint list each piece is appended to (crocodiles + coins)
	@param platforms: Walkable-top descriptors for patrolling crocodiles
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body, threaded down to
	                  create_box so each block's shape hangs on it (Task 5)

	THE MAYAN STEP-PYRAMID IS GONE and is not coming back here. The owner called
	it out as the ugliest thing in the field, and the ROLE it played — a climbable
	stepped centrepiece with a flat platform top — is now spawn_terraced_mound's.
	A properly-built Giza trio exists, in the geo-landmark registry
	(landmark_builders.gd), where a named recognizable DESTINATION belongs;
	territories stay anonymous ambience. Don't reintroduce a "nicer pyramid" here.

	EDUCATIONAL NOTE — the river rule for structures: a structure is placed as ONE
	object, so it gets ONE test, on its chosen centre, taken right after the draws
	that produced that centre. A footprint-vs-band intersection test would be more
	precise and much fiddlier for a band that winds; a centre test is enough to keep
	walls and mounds out of the water, which is all the rule is for.

	ONE PICK DRAW, POST-DRAW DISPATCH. The `rng.randf()` below is the same single
	draw the global table used; only the thresholds it is compared against are now
	per-territory (terrain.STRUCTURE_MIX). A band of zero width is how mountain declines
	the mound with no special case here.
	"""
	# Typed explicitly: `terrain` is a plain Node3D here (endless_terrain.gd
	# declares no class_name), so `biome_at` has no inferable return type.
	var biome: int = terrain.biome_at(chunk_center.x, chunk_center.z)
	var theme: Dictionary = terrain.STRUCTURE_THEMES[biome]
	var mix: Array = terrain.STRUCTURE_MIX[biome]

	var pick := rng.randf()
	if pick < mix[0]:
		spawn_wall(terrain, rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)
	elif pick < mix[1]:
		spawn_corridor(terrain, rng, half_chunk, chunk_center, theme, obstacles, block_batch, block_body)
	elif pick < mix[2]:
		spawn_gate(terrain, rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)
	else:
		spawn_terraced_mound(terrain, rng, half_chunk, chunk_center, theme, obstacles, platforms, block_batch, block_body)

static func spawn_terraced_mound(terrain: Node3D, rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a terraced mound — the climbable stepped centrepiece that REPLACES the
	Mayan step-pyramid. A plains ruin mound, a desert mesa, a forest tor: 2-4 wide
	irregular terraces, each yawed and nudged off the one below, with a flat top
	you can stand on.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the base
	@param theme: This territory's terrain.STRUCTURE_THEMES row
	@param obstacles: Footprint list (one entry for the whole base, with the top
	                  height as its top so a coin can perch up there)
	@param platforms: Gets the flat top registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)

	WHY THIS IS NOT A PYRAMID, in the two ways that matter:
	  * FEW, WIDE terraces (2-4, each 1.2-2.2 m) instead of 3-15 thin concentric
	    slabs. That is what makes it read as a weathered hill rather than a temple.
	  * Every terrace is a NON-SQUARE slab carrying its own yaw and a lateral
	    nudge, so no two edges line up and there is no axis to sight down.

	WHAT IT KEEPS, because these are the pyramid's gameplay job and not its look:
	  * ONE round footprint of radius base_size * 0.71 with the summit as its top.
	    That radius stays well above MOUNTAIN_AVOID_RADIUS (2.0) at every drawable
	    base size (8 m base -> 5.68 m), so a massif still refuses to grow through a
	    mound exactly as it refused to grow through a pyramid.
	  * A PLATFORM at the summit, so patrol crocodiles keep their perch.
	  * A CLIMBABLE ladder: terrace height is drawn at or under TerrainProps.PROP_MAX_STEP, so
	    every step up is inside the player's jump arc. prop_selfcheck.gd measures
	    the emitted boxes rather than trusting this comment.
	"""
	# Bases run from a modest hummock to a real mesa. Terraces are FEW and TALL,
	# which is the whole difference from a ziggurat.
	var base_size := rng.randf_range(8.0, 20.0)
	var terraces := rng.randi_range(2, 4)
	# Capped at PROP_MAX_STEP: a terrace taller than the jump arc turns the
	# "climbable" footprint into a lie and floats any road coin that perches on it.
	var terrace_h := minf(rng.randf_range(1.2, 2.2), TerrainProps.PROP_MAX_STEP)

	# Keep the whole base inside the chunk. The jitter allowance is in the bound
	# because an upper terrace may sit that far off the base's centre.
	# The ROTATED extent, not the half-width — see MOUND_ROT_EXTENT for why the
	# difference is load-bearing at a chunk seam.
	var limit := half_chunk - (base_size * MOUND_ROT_EXTENT + 1.0 + MOUND_TERRACE_JITTER)
	if limit <= 0.0:
		return  # chunk too small for this mound; skip it
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# No mounds in the water (centre test, taken right after the centre draws).
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if terrain.is_river_at(chunk_center + Vector3(cx, 0.0, cz)) \
			or terrain.tower_excludes(chunk_center.x + cx, chunk_center.z + cz, half_chunk):
		return

	var y := 0.0
	var w := base_size
	var top_span := base_size * 0.5   # the summit slab's own half-width (for the cap)
	var top_half := base_size * 0.5   # the largest AXIS-ALIGNED square inside it
	var top_x := cx
	var top_z := cz

	for i in terraces:
		# The base terrace sits square on the spot so the footprint circle is
		# honest; everything above it wanders.
		var jx := 0.0
		var jz := 0.0
		if i > 0:
			jx = rng.randf_range(-MOUND_TERRACE_JITTER, MOUND_TERRACE_JITTER)
			jz = rng.randf_range(-MOUND_TERRACE_JITTER, MOUND_TERRACE_JITTER)
		var d := w * rng.randf_range(0.78, 1.0)
		# YAW, never tilt: a yawed box still presents a flat top to stand on,
		# which is what the climb ladder and the patrol platform both need.
		var yaw := rng.randf_range(-MOUND_TERRACE_YAW, MOUND_TERRACE_YAW)
		terrain.create_box(
			Vector3(cx + jx, y + terrace_h * 0.5, cz + jz), Vector3(w, terrace_h, d), yaw,
			rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
		)
		y += terrace_h
		# THE PLATFORM MUST BE MEASURED IN THE SLAB'S OWN YAW FRAME. set_confinement
		# clamps a patrol crocodile against WORLD X/Z extents, but the summit slab is
		# turned by `yaw`, so the largest axis-aligned square that really fits inside
		# a (w, d) box turned by yaw has half-extent min(w, d)/2 / (|cos| + |sin|) —
		# the corner of the square projects onto BOTH box axes. Take the plain
		# half-width and a guard paces off the corner of a yawed summit and falls:
		# measured before this divisor, a 11.34 x 9.87 slab at yaw 0.087 registered
		# 4.63 m of half-extent whose corner reached 5.02 m along the slab's own Z,
		# past its 4.93 m half-depth.
		top_span = minf(w, d) * 0.5
		top_half = top_span / (absf(cos(yaw)) + absf(sin(yaw)))
		top_x = cx + jx
		top_z = cz + jz
		w *= rng.randf_range(0.58, 0.72)

	# A thin themed film over the summit — snow-pale slab on a mountain fort's
	# stub, moss on a forest tor. collide = false, so it cannot raise or roughen
	# the surface the platform and the climbable footprint both name.
	var cap: Color = theme["cap"]
	if cap.a > 0.0:
		terrain.create_box(
			Vector3(top_x, y + 0.06, top_z), Vector3(top_span * 1.9, 0.12, top_span * 1.9),
			rng.randf_range(0.0, TAU), rng, block_batch, block_body, 0.0, cap, false
		)

	# Fallen stone shed off the terraces, ringed OUTSIDE the base slab but inside
	# the declared footprint radius, so it never obstructs the climb.
	var trim: Color = theme["trim"]
	for _i in 3:
		var ts := base_size * rng.randf_range(0.05, 0.09)
		var ta := rng.randf_range(0.0, TAU)
		var ring := base_size * 0.58
		terrain.create_box(
			Vector3(cx + cos(ta) * ring, ts * 0.4, cz + sin(ta) * ring),
			Vector3(ts, ts * 0.8, ts * 1.2), rng.randf_range(0.0, TAU),
			rng, block_batch, block_body, rng.randf_range(-0.4, 0.4), trim, false
		)

	# One footprint for the whole base; top = summit height. Mounds are climbable
	# via their terraces, so a coin on the summit is reachable (just a climb).
	#
	# ponytail: ONE CIRCLE WITH ONE TOP is the whole vocabulary the coin and
	# crocodile rules speak (the same ceiling CLAUDE.md records for landmarks), so
	# a road coin landing near the rim is perched at the SUMMIT height with only
	# the base terrace under it. That is inherited from the pyramid, not
	# introduced here, and it is the cheaper end of it: measured over 25x25 chunks
	# x 4 seeds, perched road coins with no floor under them went 15 -> 13 and the
	# worst air gap 4.43 m -> 2.86 m (coins buried IN stone stayed 0). The real fix
	# is a richer footprint (per-tier tops, or a solid-centre height) in
	# _settle_coin_y, which every landmark, camp and artifact would have to learn
	# — deliberately out of this bead.
	obstacles.append({ "pos": Vector3(cx, 0, cz), "radius": base_size * 0.71, "top": y, "climbable": true })

	# Register the flat summit as a patrol platform (if it's big enough to stand on).
	# `top` equals `center.y` here — the summit slab IS the tallest SOLID thing in
	# its own footprint (the themed cap above it is collide = false, and the fallen
	# trim is ringed outside the slab), so the patrol guard's drop-in height is the
	# surface height. A wall's is not; see the platform "top" note in spawn_wall
	# for why the two are separate fields at all.
	var plat_half := top_half - 0.3
	if plat_half > 0.4:
		platforms.append({ "center": Vector3(top_x, y, top_z), "half": Vector2(plat_half, plat_half), "top": y })

static func spawn_gate(terrain: Node3D, rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a gate: two uprights with a beam across the top, leaving an opening to
	walk through. The territory decides which KIND of gate:

	  * STRUCT_GATE_LINTEL (desert, mountain) — the shipped monumental gate. The
	    pillars are about as tall as a full jump, so reaching the coin that perches
	    on the lintel is genuinely hard: hop onto a pillar, then up onto the beam.
	    That's intentional "hard to reach" gameplay and is deliberately NOT held to
	    the TerrainProps.PROP_MAX_STEP climb rule.
	  * STRUCT_GATE_ARCH (plains) — the same gate, broken: one pillar stunted, the
	    beam a stub that no longer spans the opening.
	  * STRUCT_GATE_LOG (forest) — a felled giant across two stumps. The deck is
	    low and wide enough to be a WALKABLE TOP, so this one registers a patrol
	    platform and a climbable perch, and its whole height stays inside
	    TerrainProps.PROP_MAX_STEP so you can hop straight onto it from the ground.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the gate
	@param theme: This territory's terrain.STRUCTURE_THEMES row
	@param obstacles: Footprint list (pillars, plus a perch on the beam)
	@param platforms: Gets the log bridge's deck registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var style := int(theme["gate_style"])
	var log_bridge := style == STRUCT_GATE_LOG

	var pillar_w := rng.randf_range(1.3, 1.8)
	# ONE height draw for every style, scaled rather than re-drawn, so the draw
	# count does not depend on the territory. A log bridge's stumps are low: the
	# 0.40 factor puts the finished deck at 1.98-2.54 m, i.e. inside PROP_MAX_STEP
	# (2.6) and therefore mountable from flat ground in a single hop.
	var pillar_h := rng.randf_range(2.7, 3.1)
	if log_bridge:
		pillar_h *= 0.40
	var depth := rng.randf_range(1.3, 2.0)
	if log_bridge:
		depth *= 1.15  # a giant trunk is deep enough to walk along
	var opening := rng.randf_range(3.0, 4.5)
	var lintel_h := rng.randf_range(0.9, 1.3)
	var total_w := opening + 2.0 * pillar_w  # full span across both uprights

	# A broken arch loses one upright to time. Drawn unconditionally so the
	# sequence is style-independent; only used by the arch.
	var stunt := rng.randf_range(0.5, 0.72)
	var stub := rng.randf_range(0.45, 0.7)

	# Pillars are separated along X (and you walk through along Z) or vice-versa.
	var along_x := rng.randf() < 0.5

	# Conservative bound that fits the gate whichever way it's turned.
	var limit := half_chunk - (total_w * 0.5 + 1.0)
	if limit <= 0.0:
		return
	var cx := rng.randf_range(-limit, limit)
	var cz := rng.randf_range(-limit, limit)

	# No gates in the water (centre test, taken right after the centre draws).
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if terrain.is_river_at(chunk_center + Vector3(cx, 0.0, cz)) \
			or terrain.tower_excludes(chunk_center.x + cx, chunk_center.z + cz, half_chunk):
		return

	# Distance from the gate centre to each pillar's centre.
	var half_span := opening * 0.5 + pillar_w * 0.5

	for pillar_sign in 2:
		var s := -1.0 if pillar_sign == 0 else 1.0
		var px: float = cx + (s * half_span if along_x else 0.0)
		var pz: float = cz + (0.0 if along_x else s * half_span)
		# The broken arch's second upright is a stump.
		var ph := pillar_h
		if style == STRUCT_GATE_ARCH and pillar_sign == 1:
			ph *= stunt
		# Pillar is pillar_w across the span axis and `depth` across the other.
		var pillar_dims: Vector3 = Vector3(pillar_w, ph, depth) if along_x else Vector3(depth, ph, pillar_w)
		terrain.create_box(
			Vector3(px, ph * 0.5, pz), pillar_dims, 0.0,
			rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
		)
		# Each pillar is its own footprint, so crocodiles can still pass through
		# the opening between them.
		# `guarded` only for the log bridge — it is the one gate style that registers
		# a patrol deck, so it is the one whose stone a massif must keep off.
		obstacles.append({ "pos": Vector3(px, 0, pz), "radius": maxf(pillar_w, depth) * 0.71, "top": ph, "climbable": true, "guarded": log_bridge })

	# The beam. An arch's is a shortened stub pushed back over the tall upright;
	# every style keeps it UNTILTED, because a tilted beam has no flat top and the
	# perch footprint below promises one.
	var beam_w := total_w
	var beam_shift := 0.0
	if style == STRUCT_GATE_ARCH:
		beam_w = total_w * stub
		beam_shift = -(total_w - beam_w) * 0.5  # slid onto the surviving pillar
	var beam_dims: Vector3 = Vector3(beam_w, lintel_h, depth) if along_x else Vector3(depth, lintel_h, beam_w)
	var beam_x: float = cx + (beam_shift if along_x else 0.0)
	var beam_z: float = cz + (0.0 if along_x else beam_shift)
	terrain.create_box(
		Vector3(beam_x, pillar_h + lintel_h * 0.5, beam_z), beam_dims, 0.0,
		rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
	)

	var beam_top := pillar_h + lintel_h

	# A cornice over an intact lintel — collide = false, so it can never raise the
	# surface the perch footprint (and, for a log bridge, the platform) names.
	var cap: Color = theme["cap"]
	if cap.a > 0.0 and not log_bridge:
		var cornice: Vector3 = Vector3(beam_w * 1.06, 0.16, depth * 1.2) if along_x else Vector3(depth * 1.2, 0.16, beam_w * 1.06)
		terrain.create_box(
			Vector3(beam_x, beam_top + 0.08, beam_z), cornice, 0.0,
			rng, block_batch, block_body, 0.0, cap, false
		)

	# Register the beam centre as a coin perch. For a log bridge it is a genuine
	# rest spot one hop off the ground; for the other styles it is the shipped
	# deliberately-awkward one.
	obstacles.append({ "pos": Vector3(beam_x, 0, beam_z), "radius": 1.0, "top": beam_top, "climbable": true, "guarded": log_bridge })

	# THE LOG BRIDGE IS THE ONE GATE WITH A WALKABLE DECK, so it is the one gate
	# that feeds spawn_platform_crocodiles. Half-extents are the beam's own, inset
	# so a patrol never paces off the end.
	#
	# `top` equals `center.y` here — the beam IS the tallest solid thing in its own
	# footprint, and the one thing that could stand above it (the cornice) is built
	# only for a NON-log-bridge gate, so it can never be over this deck. See the
	# platform "top" note in spawn_wall for why the field exists at all: the patrol
	# guard is dropped in from it, and a `top` that under-declares its stone puts
	# the guard inside that stone.
	if log_bridge:
		var half_along := beam_w * 0.5 - 0.4
		var half_across := depth * 0.5 - 0.3
		var deck_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
		if half_along > 1.0 and half_across > 0.2:
			platforms.append({ "center": Vector3(beam_x, beam_top, beam_z), "half": deck_half, "top": beam_top })

static func spawn_corridor(terrain: Node3D, rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a corridor: two parallel two-block-high sides with a gap between them
	that the player can sprint down. THE LANE IS THE POINT — it is the one feature
	structure with movement value, so every territory's re-dress keeps a clear
	run-through, and only the SIDES change:

	  * solid walls (plains ruin lane, mountain fort passage), or
	  * COLUMN PAIRS with `lane_spaced` (a desert temple colonnade, a forest
	    corridor of standing dead trunks), some of them still bridged overhead by
	    a portico beam.

	@param rng: The chunk's seeded RNG
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  corridor's midpoint
	@param theme: This territory's terrain.STRUCTURE_THEMES row
	@param obstacles: Footprint list each block is appended to
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)
	"""
	var block_size := rng.randf_range(1.8, 2.4)
	var step := block_size * 0.98
	var length := rng.randi_range(terrain.wall_min_length + 1, terrain.wall_max_length + 1)
	# Width of the walkable gap between the two sides.
	var gap := rng.randf_range(2.5, 4.0)

	var along_x := rng.randf() < 0.5
	var limit := half_chunk - 2.0

	# Trim the corridor if it's longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Bail if the chunk can't fit the corridor's width.
	if limit - gap * 0.5 <= -limit + gap * 0.5:
		return
	var start := rng.randf_range(-limit, limit - span)
	# Centreline of the corridor on the perpendicular axis.
	var center_perp := rng.randf_range(-limit + gap * 0.5, limit - gap * 0.5)

	# No corridors in the water. The corridor's centre is the midpoint of its run
	# along one axis and the centreline on the other (centre test, taken right
	# after the draws that fixed both).
	var mid_along := start + span * 0.5
	var corridor_center: Vector3 = Vector3(mid_along, 0.0, center_perp) if along_x else Vector3(center_perp, 0.0, mid_along)
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if terrain.is_river_at(chunk_center + corridor_center) \
			or terrain.tower_excludes(chunk_center.x + corridor_center.x, chunk_center.z + corridor_center.z, half_chunk):
		return

	var spaced: bool = theme["lane_spaced"]
	var gap_chance: float = theme["gap_chance"]
	var lintel_chance: float = theme["lintel_chance"]
	var trim: Color = theme["trim"]

	for i in length:
		# A colonnade stands on every OTHER slot — that is what turns the same
		# loop into columns instead of a wall, at the cost of no extra draw.
		if spaced and i % 2 == 1:
			continue

		var along := start + i * step
		# A ruin is missing pieces. Post-draw skip, exactly like the scatter
		# loop's river test: the draw has already happened, so nothing shifts.
		var fallen := rng.randf() < gap_chance

		for side_sign in 2:
			var side := -1.0 if side_sign == 0 else 1.0
			var perp := center_perp + side * gap * 0.5
			var x := along if along_x else perp
			var z := perp if along_x else along

			if fallen:
				# Rubble where the section came down: visual-only, and no
				# footprint, because nothing solid stands here any more.
				var rs := block_size * rng.randf_range(0.28, 0.42)
				terrain.create_box(
					Vector3(x, rs * 0.4, z), Vector3(rs, rs * 0.75, rs * 1.15),
					rng.randf_range(0.0, TAU), rng, block_batch, block_body,
					rng.randf_range(-0.45, 0.45), trim, false
				)
				continue

			# Two blocks tall so it reads as an enclosed passage. Sheer and taller
			# than a jump, so it's not climbable (no coins perch on the roof).
			terrain.create_box(
				Vector3(x, block_size * 0.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
			)
			terrain.create_box(
				Vector3(x, block_size * 1.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
			)
			obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": 2.0 * block_size, "climbable": false })

		# A portico beam bridging the pair, well above head height so the sprint
		# lane is untouched. NO FOOTPRINT: footprints model ground occupancy and
		# there is nothing on the ground under a beam — a crocodile walks under it
		# and a road coin may sit beneath it, both correctly.
		if spaced and not fallen and lintel_chance > 0.0 and rng.randf() < lintel_chance:
			var beam_span := gap + block_size
			var beam_dims: Vector3 = Vector3(block_size * 0.8, block_size * 0.55, beam_span) if along_x else Vector3(beam_span, block_size * 0.55, block_size * 0.8)
			var bx := along if along_x else center_perp
			var bz := center_perp if along_x else along
			terrain.create_box(
				Vector3(bx, 2.0 * block_size + block_size * 0.275, bz), beam_dims, 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
			)

static func spawn_wall(terrain: Node3D, rng: RandomNumberGenerator, half_chunk: float, chunk_center: Vector3, theme: Dictionary, obstacles: Array, platforms: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build a single barrier wall — a line of touching blocks the player must run
	around — somewhere inside the chunk, dressed in this territory's stone: a
	broken-backed plains ruin, a low desert temple wall, an overgrown forest wall,
	a solid battlemented mountain fort wall.

	@param rng: The chunk's seeded RNG (so the wall is deterministic)
	@param half_chunk: Half the chunk width, for bounds
	@param chunk_center: World centre of the chunk, for the river test on the
	                  wall's midpoint
	@param theme: This territory's terrain.STRUCTURE_THEMES row
	@param obstacles: Footprint list to append each wall block to (for crocodiles)
	@param platforms: Gets the wall ridge registered as a patrol platform
	@param block_batch: Out-param threaded down to create_box for MultiMesh batching
	@param block_body: The chunk's shared block-collision body (Task 5)

	THE RIDGE PLATFORM IS THE LONGEST UNBROKEN RUN, not the whole span, and that
	is the one behavioural change a ruined wall forced. A doubled hump is fine to
	pace over (the shipped comment's point — the guard's feelers turn it back), but
	a MISSING segment is a hole, and a crocodile confined to a ridge box spanning
	one would walk into thin air. So the run is broken by gaps only; a territory
	with gap_chance 0 registers exactly the ridge it always did.
	"""
	# Uniform block size so the wall reads as one solid line.
	var block_size := rng.randf_range(1.6, 2.4)
	# Step slightly less than the block size so neighbours overlap — no gaps.
	var step := block_size * 0.98
	var length := rng.randi_range(terrain.wall_min_length, terrain.wall_max_length)

	# Run the wall along X or along Z.
	var along_x := rng.randf() < 0.5
	var margin := 2.0
	var limit := half_chunk - margin

	# Distance from the first block centre to the last. Trim the wall if it would
	# be longer than the chunk can hold.
	var span := (length - 1) * step
	if span > 2.0 * limit:
		length = int(floor((2.0 * limit) / step)) + 1
		span = (length - 1) * step

	# Pick where the wall starts along its axis, and its fixed perpendicular coord.
	var start := rng.randf_range(-limit, limit - span)
	var fixed := rng.randf_range(-limit, limit)

	# Midpoint of the wall's run — used for the river test here; the patrol ridge
	# at the bottom of this function is measured off its own surviving run.
	var mid_along := start + (length - 1) * step * 0.5

	# No walls in the water (centre test, taken right after the draws that placed
	# the wall).
	var wall_center: Vector3 = Vector3(mid_along, 0.0, fixed) if along_x else Vector3(fixed, 0.0, mid_along)
	# ...and none on the tower's site, judged with `half_chunk` as the extent: a
	# structure never leaves its own chunk by construction (see the `limit`
	# above), so half a chunk is a conservative bound on how far its blocks reach.
	if terrain.is_river_at(chunk_center + wall_center) \
			or terrain.tower_excludes(chunk_center.x + wall_center.x, chunk_center.z + wall_center.z, half_chunk):
		return

	var gap_chance: float = theme["gap_chance"]
	var double_chance: float = theme["double_chance"]
	var cap: Color = theme["cap"]
	var trim: Color = theme["trim"]

	# Longest unbroken run of standing segments — see the docstring.
	var run_start := 0
	var run_len := 0
	var best_start := 0
	var best_len := 0

	# Each section's own top, so the patrol platform below can take the MAXIMUM over
	# the surviving run it actually registers rather than over the whole wall. A
	# fallen section keeps its 0.0 and is never inside a run by construction. See
	# the platform "top" note at the bottom of this function for why the maximum
	# (and not the walkable height) is what the patrol spawner needs.
	var section_top := PackedFloat32Array()
	section_top.resize(length)

	for i in length:
		var along := start + i * step
		var x := along if along_x else fixed
		var z := fixed if along_x else along

		# This section fell. Post-draw skip: the randf() above has already
		# advanced the stream, so removing the block inserts no draw anywhere.
		if rng.randf() < gap_chance:
			if run_len > best_len:
				best_len = run_len
				best_start = run_start
			run_len = 0
			# Its stones, scattered where they landed. Visual-only trim, and no
			# footprint — nothing solid stands here now.
			var rs := block_size * rng.randf_range(0.26, 0.4)
			terrain.create_box(
				Vector3(x, rs * 0.4, z), Vector3(rs, rs * 0.75, rs * 1.15),
				rng.randf_range(0.0, TAU), rng, block_batch, block_body,
				rng.randf_range(-0.45, 0.45), trim, false
			)
			continue

		if run_len == 0:
			run_start = i
		run_len += 1

		# Wall blocks are axis-aligned (yaw 0) so they sit flush against each other.
		terrain.create_box(
			Vector3(x, block_size * 0.5, z), Vector3(block_size, block_size, block_size), 0.0,
			rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
		)
		var top := block_size
		# A single-block section is low enough to hop onto; a doubled one is not.
		var climbable := true

		# Now and then double a section up so the wall isn't a uniform single row.
		if rng.randf() < double_chance:
			terrain.create_box(
				Vector3(x, block_size * 1.5, z), Vector3(block_size, block_size, block_size), 0.0,
				rng, block_batch, block_body, 0.0, _structure_stone(terrain, theme, rng)
			)
			top = 2.0 * block_size
			climbable = false
			# A capstone crowns the HUMP only, never the ridge — the ridge is the
			# surface a patrol paces and a player stands on. collide = false makes
			# it inert either way; keeping it off the ridge keeps the rule simple.
			if cap.a > 0.0:
				terrain.create_box(
					Vector3(x, top + 0.07, z), Vector3(block_size * 1.05, 0.14, block_size * 1.05), 0.0,
					rng, block_batch, block_body, 0.0, cap, false
				)

		section_top[i] = top
		# `guarded` marks stone that a patrol crocodile is going to be dropped onto,
		# and it exists for exactly one reader: _spawn_mountain_content's avoid-list.
		# A massif must clear it whatever its radius or height — see the note there.
		obstacles.append({ "pos": Vector3(x, 0, z), "radius": block_size * 0.71, "top": top, "climbable": climbable, "guarded": true })

	if run_len > best_len:
		best_len = run_len
		best_start = run_start

	# Register the surviving ridge as a thin patrol platform (a crocodile can pace
	# it end to end). Surface is the single-block height; doubled humps just become
	# obstacles its feelers turn it back at.
	#
	# WHY THE DICT CARRIES BOTH `center.y` AND `top`, and why they differ here:
	# `center.y` is the SURFACE the guard paces — the single-block height, and the
	# height set_confinement is handed (which reads only .x/.z, so nothing else
	# consumes it). `top` is the TALLEST SOLID STONE standing anywhere inside the
	# platform's footprint, which for a wall is the doubled humps.
	# spawn_platform_crocodiles drops its guard in from `top`, not from `center.y`,
	# and that distinction is the whole bug this pair exists to close: a share of a
	# wall's sections are doubled, occupying y in [block_size, 2 * block_size], and
	# the spawner picks a point at a RANDOM ANGLE along the ridge with no idea
	# which sections those are. Dropping in at `center.y + PLATFORM_SPAWN_HEIGHT`
	# therefore put the guard INSIDE a hump whenever the angle landed on one —
	# penetrating by up to the full drop-in offset. Measured over a 17x17 chunk
	# field on four run seeds: 3-7 patrol crocodiles per field stood in solid
	# stone, i.e. 12-18% of every platform guard the world spawned, and EVERY
	# crocodile-in-stone in the whole field was one of them (the ground and boss
	# spawners, which do test `obstacles`, were clean at 0). Dropping in from the
	# maximum instead lands the guard on the ridge or on a hump's top face and
	# gravity settles it either way.
	#
	# The maximum is taken over the SURVIVING RUN this platform actually covers,
	# not over the whole wall: a hump in a section that fell, or in a stretch on
	# the far side of a gap, is not inside this footprint and would only lift the
	# drop-in for nothing. The hump capstones are collide = false, so they are
	# correctly not part of it.
	if best_len > 0:
		var ridge_along := start + (best_start + (best_len - 1) * 0.5) * step
		var ridge_center: Vector3 = Vector3(ridge_along, block_size, fixed) if along_x else Vector3(fixed, block_size, ridge_along)
		var half_along := (best_len - 1) * step * 0.5 + block_size * 0.5 - 0.4
		var half_across := block_size * 0.5 - 0.3
		var ridge_half: Vector2 = Vector2(half_along, half_across) if along_x else Vector2(half_across, half_along)
		var ridge_top := block_size
		for i in range(best_start, best_start + best_len):
			ridge_top = maxf(ridge_top, section_top[i])
		if half_along > 1.0 and half_across > 0.2:
			platforms.append({ "center": ridge_center, "half": ridge_half, "top": ridge_top })
