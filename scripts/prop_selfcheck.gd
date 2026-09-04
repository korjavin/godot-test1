extends SceneTree
## Headless self-check for the themed scattered props AND the themed feature
## structures.
##
##   godot --headless --path . --script res://scripts/prop_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as landmark_selfcheck.gd, and it exists for the same reason: the
## props replaced the bare cubes that carried three gameplay contracts, and every
## way of breaking one of them looks like ordinary scenery from the outside.
##
##   1. THE RETURNED RADIUS IS A TRUE BOUND ON THE PROP. Every builder is called
##      for real over many seeds and sizes, and every CORNER of every box it
##      emits is measured against the radius it returned. That radius is what
##      _settle_coin_y perches a road coin against, what spawn_crocodiles_in_chunk
##      keeps its NPCs out of, and what the mountain massif avoid-list reads — so
##      a box poking outside it is a crocodile spawned inside stone or a coin
##      buried in it, with no error anywhere. Corners are measured rather than a
##      half-diagonal formula, so no assumption is made about which axes a builder
##      rotated (a prop carries yaw AND tilt).
##
##   2. THE CLIMBABILITY CONTRACT — the reason the cubes existed. A prop that
##      records climbable = true must be mountable from flat ground: the check
##      collects every UNTILTED, COLLIDING box whose footprint actually covers the
##      prop's centre, sorts their top faces, and requires the ladder to start
##      within PROP_MAX_STEP of the ground, to have no gap over PROP_MAX_STEP, and
##      to END EXACTLY AT THE RETURNED `top`. That last clause is the sharp one:
##      a builder that crowns a cairn with a tilted capstone, or records the top
##      of a decoration instead of the surface you can stand on, produces a prop
##      that looks perfect and silently stops being a rest spot from crocodiles —
##      and _settle_coin_y then floats a road coin at a height with no floor under
##      it. Nothing else in the project asserts any of this.
##
##   3. THE INSTANCE / COLLISION BUDGET. 3-8 boxes of which 1-3 collide. Boxes are
##      nearly free (the whole chunk is one MultiMesh) but every colliding box is
##      a real CollisionShape3D node on the chunk's shared body, which is the
##      budget the per-chunk node count lives on. A builder quietly making all of
##      its trim solid triples that count with no visible symptom.
##
##   4. WITHIN-RUN PURITY, MEASURED THROUGH THE REAL SCATTER LOOP. The same chunk
##      generated twice must emit byte-identical geometry — the load-bearing half
##      of the determinism contract (cross-version identity with the pre-prop
##      world is deliberately NOT required; see the THEMED SCATTERED PROPS banner
##      in endless_terrain.gd). The same pass also pins that every footprint the
##      loop appends carries a prop radius, i.e. that the loop really routes
##      through _build_prop rather than through some surviving cube path.
##
##   5. THE FEATURE STRUCTURES ARE REALLY RE-THEMED, AND STILL FEED THE PATROL
##      CROCODILES. Same shape of check, one scale up: every role builder is run
##      against every territory's STRUCTURE_THEMES row and (a) every colour it
##      emits must lie on THAT territory's ramp — the negative control for a
##      builder that quietly fell back to create_block's global RAMP_* pick, which
##      would look fine and simply stop being themed — and (b) every walkable top
##      it registers in `platforms` must be reachable from the ground by untilted
##      colliding box tops in steps no taller than PROP_MAX_STEP, or the crocodile
##      confined to it is standing on nothing. The retirement of the Mayan pyramid
##      is asserted here too, with its replacement's geometry as the positive
##      control (an absent method is otherwise indistinguishable from a typo).
##
## HOUSE RULE, followed throughout: every check is an EFFECT measurement with a
## negative control, never a getter read-back. Check 1 is vacuous against a
## builder that emits nothing, so check 3's lower bound runs on the same batch;
## check 2 is vacuous against an empty ladder, so a climbable prop with no
## centred untilted collider is an explicit failure rather than a silent pass.
##
## Don't grow this into a suite.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"

## Every prop builder, with the biome it themes. Written out rather than derived,
## because the dispatch in _build_prop is a `match` over an enum — there is no
## registry to read, and a builder that exists but is never listed here is
## exactly the kind of drift a hand-written list makes visible in review.
const BUILDERS: Array = [
	["PLAINS", "_prop_boulder_cluster"],
	["PLAINS", "_prop_ruin_fragment"],
	["PLAINS", "_prop_bale_pile"],
	["DESERT", "_prop_sandstone_stack"],
	["DESERT", "_prop_broken_column"],
	["DESERT", "_prop_bone_pile"],
	["FOREST", "_prop_mossy_boulder"],
	["FOREST", "_prop_tree_stump"],
	["FOREST", "_prop_log_pile"],
	["MOUNTAIN", "_prop_scree_cluster"],
	["MOUNTAIN", "_prop_cairn"],
	["CITY", "_prop_crate_stack"],
	["CITY", "_prop_garden_wall"],
	["CITY", "_prop_paving_stack"],
	["SNOW", "_prop_ice_rock"],
	["SNOW", "_prop_snow_drift"],
	["SNOW", "_prop_frozen_stump"],
]

## Seeds per builder per size. Every variant is random-driven (tier heights,
## companion rings, chip counts), so one seed proves nothing — 24 seeds across 5
## sizes is 120 real props per builder, enough that a variant overflowing its
## radius on an unlucky draw cannot pass by luck. Nothing enters the tree, so the
## whole file still runs in well under a second.
const SEEDS_PER_BUILDER: int = 24

## The `size` values swept. object_size_min/max are 1.0/2.5; the ends are where
## a minf() clamp either bites or does not, so both are included explicitly.
const SIZES: Array[float] = [1.0, 1.4, 1.8, 2.2, 2.5]

## Float slack. Every measurement is a sum of products of floats; a corner landing
## exactly on the declared radius is correct, not a failure.
const EPSILON: float = 0.001

## How far a box's own axis may tip out of the horizontal and still count as
## "flat enough to stand on" for check 2. Builders pass tilt = 0.0 for every box
## they intend as a step, so this only absorbs float noise in the basis.
const FLAT_EPSILON: float = 0.001

## The unit cube's 8 corners — create_box builds each instance transform as
## Basis(UP, yaw) * Basis(RIGHT, tilt) scaled_local by the box dimensions over the
## shared 1x1x1 BoxMesh, so transforming these gives the real rotated extent.
const UNIT_CORNERS: Array[Vector3] = [
	Vector3(-0.5, -0.5, -0.5), Vector3(-0.5, -0.5, 0.5),
	Vector3(-0.5, 0.5, -0.5), Vector3(-0.5, 0.5, 0.5),
	Vector3(0.5, -0.5, -0.5), Vector3(0.5, -0.5, 0.5),
	Vector3(0.5, 0.5, -0.5), Vector3(0.5, 0.5, 0.5),
]

## The four feature-structure ROLES, as [label, method, takes_platforms]. Written
## out for BUILDERS' reason: the dispatch is a threshold chain over STRUCTURE_MIX,
## not a registry, so a role that exists but is never listed here is drift a
## hand-written list makes visible in review.
const ROLES: Array = [
	["wall", "spawn_wall", true],
	["lane", "spawn_corridor", false],
	["gate", "spawn_gate", true],
	["mound", "spawn_terraced_mound", true],
]

## The territories, as [label, Biome enum value]. Read off the terrain script's
## own enum rather than re-typed, so a renamed band fails loudly here.
const TERRITORIES: Array = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN", "CITY", "SNOW"]

## Structure trials per role per territory. Structures draw far more than a prop
## does (length, doubling, gaps, lintels), so the sweep needs breadth; 40 x 4 x 4
## is 640 real structures and still runs in well under a second.
const STRUCTURE_SEEDS: int = 40

## Colour slack. Every emitted colour is stored srgb_to_linear'd in the batch and
## converted back here, so a couple of round-trip ULPs have to be absorbed.
const COLOR_EPSILON: float = 0.004

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	# get_script_constant_map() is how a `const` is read from outside: constants
	# are not properties, so terrain.get("PROP_MAX_STEP") answers null and a check
	# written that way would pass vacuously against nothing at all.
	var consts: Dictionary = terrain_script.get_script_constant_map()

	if not consts.has("PROP_MAX_STEP") or not consts.has("PROP_RADIUS_FACTOR"):
		_fail("endless_terrain.gd has no PROP_MAX_STEP / PROP_RADIUS_FACTOR — the prop contract constants are gone")
	else:
		_check_builders(terrain_script, consts)
		_check_constants(consts)
		_check_chunk_purity(terrain_script, consts)
		_check_structures(terrain_script, consts)
		_check_biome_bands(terrain_script, consts)
		_check_city_content(terrain_script, consts)
		_check_snow_content(terrain_script, consts)
		_check_forest_content(terrain_script, consts)

	if _failures.is_empty():
		print("props: %d builders x %d seeds x %d sizes measured; radius bound, climb ladder, box budget and chunk purity OK"
				% [BUILDERS.size(), SEEDS_PER_BUILDER, SIZES.size()])
		print("structures: %d roles x %d territories x %d seeds measured; palette, patrol platforms and pyramid retirement OK"
				% [ROLES.size(), TERRITORIES.size(), STRUCTURE_SEEDS])
		print("bands:      threshold chain, river-in-plains, interior band widths and the shader parity uniforms OK")
		print("snow:       mammoth radius bound, 2-collider budget, non-climbable footprints and the chunk seam OK")
		print("forest:     chunk seam, one collider per tree, non-climbable footprints, leaf-shade spread and trunk lean OK")
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECKS 1-3 — measure what each builder actually emits
# ============================================================================

func _check_builders(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Call every builder for real and measure the geometry.

	The terrain node is DETACHED (never added to the tree) on purpose, exactly as
	landmark_selfcheck.gd does it: _ready() rolls a run seed, builds fog,
	materials and the first chunks, none of which a prop builder touches — a
	builder reaches only create_box. Keeping it out of the tree keeps this check
	to the geometry it is about.
	"""
	var max_step: float = float(consts["PROP_MAX_STEP"])
	var radius_factor: float = float(consts["PROP_RADIUS_FACTOR"])

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)

	for entry_variant: Variant in BUILDERS:
		var entry: Array = entry_variant
		var biome: String = String(entry[0])
		var builder: String = String(entry[1])

		if not terrain.has_method(builder):
			_fail("%s: no such builder method %s" % [biome, builder])
			continue

		# Worst case across the whole sweep, printed so the report says how much
		# headroom each contract has rather than merely "ok".
		var worst_reach_ratio := 0.0   # measured corner reach / returned radius
		var worst_step := 0.0          # tallest single step in any climb ladder
		var min_boxes := 99
		var max_boxes := 0
		var min_solid := 99
		var max_solid := 0

		for size: float in SIZES:
			for s in SEEDS_PER_BUILDER:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(Vector2i(s, int(size * 1000.0)))

				var batch: Array = []
				var body := StaticBody3D.new()
				var prop: Dictionary = terrain.call(
					builder, Vector3.ZERO, size, rng, batch, body
				)

				var solids: Array = body.get_children()
				min_boxes = mini(min_boxes, batch.size())
				max_boxes = maxi(max_boxes, batch.size())
				min_solid = mini(min_solid, solids.size())
				max_solid = maxi(max_solid, solids.size())

				# ---- CHECK 1: the returned radius bounds every emitted corner --
				var declared: float = float(prop["radius"])
				var expected: float = size * radius_factor
				if absf(declared - expected) > EPSILON:
					_fail("%s size %.1f seed %d: returned radius %.3f, expected size * PROP_RADIUS_FACTOR = %.3f"
							% [builder, size, s, declared, expected])
				var reach := _measured_reach(batch)
				if reach > declared + EPSILON:
					_fail("%s size %.1f seed %d: geometry reaches %.3f m from centre, past its declared radius %.3f m"
							% [builder, size, s, reach, declared])
				if declared > 0.0:
					worst_reach_ratio = maxf(worst_reach_ratio, reach / declared)

				# ---- CHECK 2: the climb ladder ------------------------------
				if bool(prop["climbable"]):
					var step := _check_ladder(builder, size, s, prop, batch, body, max_step)
					worst_step = maxf(worst_step, step)

				body.free()

		# ---- CHECK 3: the instance / collision budget -----------------------
		# The lower bounds are ALSO check 1's negative control: a builder that
		# emitted nothing would satisfy every radius comparison above trivially.
		if min_boxes < 3 or max_boxes > 8:
			_fail("%s: emits %d-%d boxes, outside the 3-8 budget" % [builder, min_boxes, max_boxes])
		if min_solid < 1 or max_solid > 3:
			_fail("%s: emits %d-%d COLLIDING boxes, outside the 1-3 budget" % [builder, min_solid, max_solid])

		print("  %-8s %-24s boxes %d-%d (%d-%d solid)  reach %.0f%% of radius  worst step %.2f m"
				% [biome, builder, min_boxes, max_boxes, min_solid, max_solid, worst_reach_ratio * 100.0, worst_step])

	terrain.free()
	Sentinel.done("builders")


func _measured_reach(batch: Array) -> float:
	"""
	The furthest any emitted corner gets from the prop centre, measured in XZ.

	Corners, not a half-diagonal formula: a prop's decoration carries both a yaw
	and a tilt, so the direction of its furthest corner is not something this
	check should have to assume.
	"""
	var worst := 0.0
	for entry_variant: Variant in batch:
		var entry: Dictionary = entry_variant
		var xform: Transform3D = entry["transform"]
		for corner: Vector3 in UNIT_CORNERS:
			var p := xform * corner
			worst = maxf(worst, Vector2(p.x, p.z).length())
	return worst


func _check_ladder(builder: String, size: float, seed_index: int, prop: Dictionary, batch: Array, body: StaticBody3D, max_step: float) -> float:
	"""
	Verify a climbable prop can actually be climbed, and return its tallest step.

	A step counts only if it is a box that (a) COLLIDES — you cannot stand on a
	visual-only canopy, (b) is UNTILTED, so it presents a flat top rather than a
	slope, and (c) whose footprint covers the prop's own centre, so the surface is
	where a player walking up to the prop would actually find it. Those three
	together are what "flat top at the recorded height" means; each is a way a
	builder can look right and silently stop being a rest spot.
	"""
	var tops: Array[float] = _standable_tops(body, Vector3.ZERO)

	if tops.is_empty():
		# The negative control for this whole check: without it, a builder that
		# stopped emitting a standable surface altogether would pass silently.
		_fail("%s size %.1f seed %d: records climbable = true but emits NO centred, untilted, colliding box — nothing to stand on"
				% [builder, size, seed_index])
		return 0.0

	tops.sort()
	var worst_step := 0.0
	var reached := 0.0
	for top: float in tops:
		var step := top - reached
		if step > max_step + EPSILON:
			_fail("%s size %.1f seed %d: %.2f m step up to %.2f m, past PROP_MAX_STEP %.2f — unclimbable"
					% [builder, size, seed_index, step, top, max_step])
		worst_step = maxf(worst_step, step)
		reached = maxf(reached, top)

	# The recorded `top` must BE the surface you end up standing on. A prop whose
	# footprint claims a height its geometry does not offer makes _settle_coin_y
	# float a road coin over thin air.
	var recorded: float = float(prop["top"])
	if absf(recorded - reached) > EPSILON:
		_fail("%s size %.1f seed %d: records top %.3f m but its highest standable surface is %.3f m"
				% [builder, size, seed_index, recorded, reached])
	Sentinel.done("ladder")
	return worst_step


func _standable_tops(body: StaticBody3D, centre: Vector3) -> Array[float]:
	"""
	The sorted heights of every surface a player could actually stand on above a
	given XZ spot, read off the real collision shapes.

	@param body: The collision body the builder filled.
	@param centre: The XZ column to measure (Y ignored). Props measure their own
	               origin; a structure measures a platform's centre.
	@return Ascending top-face heights of every box that COLLIDES, is UNTILTED
	        (so it presents a flat top rather than a slope), and whose footprint
	        actually covers `centre`.

	Those three conditions together are what "a flat top at this height" means,
	and each is a way a builder can look right while silently ceasing to be
	standable. Shared by the prop ladder and the structure platform check so the
	two can never drift apart on what "standable" means.
	"""
	var tops: Array[float] = []
	for shape_node: Node in body.get_children():
		var shape := shape_node as CollisionShape3D
		if shape == null:
			continue
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var basis := shape.transform.basis
		# Untilted means the box's own Y axis is world-up: create_box builds
		# Basis(UP, yaw) * Basis(RIGHT, tilt), so any tilt shows up here at once.
		if absf(basis.y.x) > FLAT_EPSILON or absf(basis.y.z) > FLAT_EPSILON:
			continue
		# Does this box's footprint cover the column? The box is yawed, so the
		# test projects the offset onto the box's own horizontal axes.
		var to_centre := centre - shape.transform.origin
		if absf(to_centre.dot(basis.x.normalized())) > box.size.x * 0.5:
			continue
		if absf(to_centre.dot(basis.z.normalized())) > box.size.z * 0.5:
			continue
		tops.append(shape.transform.origin.y + box.size.y * 0.5)
	tops.sort()
	return tops


# ============================================================================
# CHECK: the constant chain
# ============================================================================

func _check_constants(consts: Dictionary) -> void:
	"""
	Two inequalities a future retune breaks silently.
	"""
	var radius_factor: float = float(consts["PROP_RADIUS_FACTOR"])
	var max_step: float = float(consts["PROP_MAX_STEP"])
	var avoid_radius: float = float(consts["MOUNTAIN_AVOID_RADIUS"])
	# object_size_max is an @export, not a const, so its default is read off a
	# fresh instance of the script rather than the constant map.
	var probe := Node3D.new()
	probe.set_script(load(TERRAIN_SCRIPT))
	var size_max: float = float(probe.get("object_size_max"))
	probe.free()

	# 1. The widest prop stays under the massif avoid-radius, so props remain
	#    "fair game" to bury in a mountain exactly as the bare cubes were. Cross
	#    it and mountains start refusing to generate around ordinary scenery.
	var widest := size_max * radius_factor
	if widest >= avoid_radius:
		_fail("widest prop radius %.2f m >= MOUNTAIN_AVOID_RADIUS %.2f — massifs would start avoiding ordinary props"
				% [widest, avoid_radius])

	# 2. A step must stay under the player's jump apex. Read from the player
	#    script rather than re-typed, so a gravity/jump retune fails here.
	var player: GDScript = load("res://scripts/player_controller.gd")
	var pc: Dictionary = player.get_script_constant_map()
	if pc.has("JUMP_VELOCITY") and pc.has("gravity"):
		var apex: float = pow(float(pc["JUMP_VELOCITY"]), 2.0) / (2.0 * float(pc["gravity"]))
		if max_step >= apex:
			_fail("PROP_MAX_STEP %.2f m >= the player's jump apex %.3f m — a 'climbable' prop is not"
					% [max_step, apex])
	Sentinel.done("constants")


# ============================================================================
# CHECK 4 — within-run purity, through the real scatter loop
# ============================================================================

func _check_chunk_purity(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Generate the same chunk twice through the REAL spawn_objects_in_chunk and
	require byte-identical geometry.

	This is the one check that drives the integration rather than a builder in
	isolation, and within-run purity is the load-bearing half of the determinism
	contract: a revisited chunk must rebuild exactly as it was, or crocodiles,
	coins and collision all move under the player. The negative control is the
	non-empty assertion below — a loop that generated nothing at all would satisfy
	"both passes agree" perfectly.
	"""
	var _unused: float = float(consts["PROP_RADIUS_FACTOR"])

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)

	var chunks: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-7, 5), Vector2i(11, 9)]
	var props_seen := 0

	for chunk: Vector2i in chunks:
		var runs: Array = []
		var obstacle_runs: Array = []
		for _pass in 2:
			var batch: Array = []
			var body := StaticBody3D.new()
			var platforms: Array = []
			obstacle_runs.append(terrain.spawn_objects_in_chunk(chunk, platforms, batch, body))
			runs.append(batch)
			body.free()

		var a: Array = runs[0]
		var b: Array = runs[1]
		if a.size() != b.size():
			_fail("chunk %s regenerated %d boxes then %d — generation is not pure" % [chunk, a.size(), b.size()])
			continue
		for i in a.size():
			var ea: Dictionary = a[i]
			var eb: Dictionary = b[i]
			# KIND IS COMPARED TOO (bead godot-test1-y1o.1). A batch entry now
			# carries which shared unit mesh it draws, and a field nobody compares
			# is a field nobody tests: a builder that picked a sphere off a random
			# draw would regenerate as a cone here and this loop would shrug.
			if (ea["transform"] != eb["transform"] or ea["color"] != eb["color"]
					or ea["kind"] != eb["kind"]):
				_fail("chunk %s box %d differs between two generations of the same chunk" % [chunk, i])
				break

		# Negative control: an empty chunk would satisfy the comparison above.
		if a.is_empty() or obstacle_runs[0].is_empty():
			_fail("chunk %s produced no geometry at all — nothing was measured" % chunk)
			continue
		props_seen += a.size()

		var obs_a: Array = obstacle_runs[0]
		var obs_b: Array = obstacle_runs[1]
		if obs_a.size() != obs_b.size():
			_fail("chunk %s returned %d footprints then %d" % [chunk, obs_a.size(), obs_b.size()])
			continue
		for i in obs_a.size():
			if obs_a[i] != obs_b[i]:
				_fail("chunk %s footprint %d differs between two generations of the same chunk" % [chunk, i])
				break

	print("  purity     %d chunks regenerated twice, %d boxes compared" % [chunks.size(), props_seen])
	terrain.free()
	Sentinel.done("chunk_purity")


# ============================================================================
# CHECK 5 — the themed feature structures
# ============================================================================

func _check_structures(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Run every feature-structure ROLE against every TERRITORY'S theme and measure
	the two things the re-theme could break silently, plus the retirement.

	WHY A ROLE x THEME SWEEP RATHER THAN THE DISPATCH: spawn_feature_structure
	picks the theme from biome_at(chunk_center), so driving it would only ever
	exercise whichever band the sweep's coordinates happened to land in — and the
	bug being hunted is a builder that ignores the theme it was handed. Passing
	the theme explicitly is what makes "desert stone in a desert structure" a
	statement this file can actually falsify.
	"""
	var max_step: float = float(consts["PROP_MAX_STEP"])
	var themes: Dictionary = consts["STRUCTURE_THEMES"]
	var mix: Dictionary = consts["STRUCTURE_MIX"]
	var biome_enum: Dictionary = consts["Biome"]

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var half_chunk: float = float(terrain.get("chunk_size")) * 0.5

	# ---- RETIREMENT: the Mayan step-pyramid is gone from the generic pool -----
	# The positive control is spawn_terraced_mound below: an absent method on its
	# own is indistinguishable from a typo in this check's own method name.
	if terrain.has_method("spawn_pyramid"):
		_fail("spawn_pyramid still exists — the Mayan step-pyramid was supposed to be retired from the territory pool (a proper Giza belongs in landmark_builders.gd)")

	# ---- The four territories' palettes must be mutually distinguishable -----
	# A re-theme that copied one row into another reads as "themed" from inside
	# every other check in this function.
	for i in TERRITORIES.size():
		for j in TERRITORIES.size():
			if i == j:
				continue
			var a: Dictionary = themes[biome_enum[TERRITORIES[i]]]
			var b: Dictionary = themes[biome_enum[TERRITORIES[j]]]
			if _color_on_ramp(a["stone_a"], b["stone_a"], b["stone_b"]):
				_fail("%s's stone sits on %s's ramp — the two territories' structures would read as the same place"
						% [TERRITORIES[i], TERRITORIES[j]])

	for role_variant: Variant in ROLES:
		var role: Array = role_variant
		var label: String = String(role[0])
		var method: String = String(role[1])
		var takes_platforms: bool = bool(role[2])

		if not terrain.has_method(method):
			_fail("no such structure builder %s (role %s)" % [method, label])
			continue

		for territory: String in TERRITORIES:
			var theme: Dictionary = themes[biome_enum[territory]]
			var built := 0
			var platforms_seen := 0
			var worst_step := 0.0
			var boxes := 0

			for s in STRUCTURE_SEEDS:
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(Vector3i(s, hash(method), hash(territory)))

				# Spread the trials over the world so the river / bounds rejections
				# every builder carries are genuinely exercised rather than avoided.
				var chunk_center := Vector3((s % 8) * 50.0 - 200.0, 0.0, (s / 8) * 50.0 - 100.0)

				var batch: Array = []
				var body := StaticBody3D.new()
				var obstacles: Array = []
				var platforms: Array = []
				if takes_platforms:
					terrain.call(method, rng, half_chunk, chunk_center, theme, obstacles, platforms, batch, body)
				else:
					terrain.call(method, rng, half_chunk, chunk_center, theme, obstacles, batch, body)

				if batch.is_empty():
					body.free()
					continue  # rejected by the river / bounds test — legitimate
				built += 1
				boxes += batch.size()

				# ---- CHECK 5c: nothing straddles the chunk seam ----------------
				# A structure's mesh and collision belong to ONE chunk, so anything
				# reaching past the seam VANISHES when that chunk unloads while its
				# neighbour is still loaded. Every builder sizes a `limit` for this;
				# the trap is sizing it off an UNROTATED half-width when the box
				# carries a yaw (a mound terrace at 0.35 rad reaches 0.641 of its
				# base_size, not 0.5).
				var reach := _axis_reach(batch)
				if reach > half_chunk + EPSILON:
					_fail("%s/%s seed %d: geometry reaches %.2f m from the chunk centre, past the %.2f m seam — it would vanish with its own chunk"
							% [territory, label, s, reach, half_chunk])

				# ---- CHECK 5a: every colour comes off THIS territory's palette --
				for entry_variant: Variant in batch:
					var entry: Dictionary = entry_variant
					# create_box stores the colour srgb_to_linear'd for the MultiMesh.
					var c: Color = (entry["color"] as Color).linear_to_srgb()
					if _color_on_ramp(c, theme["stone_a"], theme["stone_b"]):
						continue
					if _color_close(c, theme["trim"]):
						continue
					if (theme["cap"] as Color).a > 0.0 and _color_close(c, theme["cap"]):
						continue
					_fail("%s/%s seed %d: emitted %s, which is on no part of that territory's palette — the builder is not using its theme"
							% [territory, label, s, c])
					break

				# ---- CHECK 5b: every patrol platform is real and reachable ------
				for plat_variant: Variant in platforms:
					var plat: Dictionary = plat_variant
					var centre: Vector3 = plat["center"]
					var half: Vector2 = plat["half"]
					platforms_seen += 1
					if half.x <= 0.0 or half.y <= 0.0:
						_fail("%s/%s seed %d: registers a platform with half-extents %s — a crocodile confined to it has nowhere to pace"
								% [territory, label, s, half])
						continue
					var tops: Array[float] = _standable_tops(body, centre)
					if tops.is_empty():
						_fail("%s/%s seed %d: registers a platform at %.2f m with NO untilted colliding box under it — its patrol crocodile stands on nothing"
								% [territory, label, s, centre.y])
						continue
					# THE CORNERS, not just the centre. set_confinement clamps a guard
					# against the WORLD X/Z extents of this rectangle, so every corner
					# of it must have real floor at the platform height — a summit slab
					# turned by a yaw is exactly the case where the centre is fine and
					# a corner hangs over nothing.
					var corner_ok := true
					for sx in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							var corner := Vector3(centre.x + sx * half.x, centre.y, centre.z + sz * half.y)
							if not _has_top(_standable_tops(body, corner), centre.y):
								corner_ok = false
					if not corner_ok:
						_fail("%s/%s seed %d: platform corner at half-extents %s hangs over nothing at %.3f m — a confined patrol crocodile paces off the edge"
								% [territory, label, s, half, centre.y])
					var reached := 0.0
					for top: float in tops:
						if top > centre.y + EPSILON:
							break  # decoration above the deck is not part of the climb
						var step := top - reached
						if step > max_step + EPSILON:
							_fail("%s/%s seed %d: %.2f m step up to %.2f m on the way to its platform, past PROP_MAX_STEP %.2f"
									% [territory, label, s, step, top, max_step])
						worst_step = maxf(worst_step, step)
						reached = maxf(reached, top)
					if absf(reached - centre.y) > EPSILON:
						_fail("%s/%s seed %d: platform sits at %.3f m but the highest standable surface under it is %.3f m"
								% [territory, label, s, centre.y, reached])

				body.free()

			# Negative control for 5a: a builder rejected on every trial would
			# satisfy every colour comparison above by emitting nothing at all.
			if built < STRUCTURE_SEEDS / 2:
				_fail("%s/%s built only %d of %d trials — nothing was measured"
						% [territory, label, built, STRUCTURE_SEEDS])

			# Negative control for 5b, and the actual acceptance criterion for the
			# re-theme: the roles that carry a walkable top must still register one,
			# or spawn_platform_crocodiles silently stops finding anything to guard.
			var wants_platform := label == "wall" or label == "mound" or (label == "gate" and int(theme["gate_style"]) == 2)
			var mound_banned := label == "mound" and float((mix[biome_enum[territory]] as Array)[3]) <= float((mix[biome_enum[territory]] as Array)[2])
			if wants_platform and not mound_banned and platforms_seen == 0:
				_fail("%s/%s registered NO patrol platform across %d trials — its walkable top is gone and platform crocodiles vanish with it"
						% [territory, label, built])
			if label == "lane" and platforms_seen > 0:
				_fail("%s/lane registered a patrol platform — the corridor is deliberately sheer and taller than a jump" % territory)

			print("  %-8s %-6s built %2d/%d  %4d boxes  %d platforms  worst climb step %.2f m"
					% [territory, label, built, STRUCTURE_SEEDS, boxes, platforms_seen, worst_step])

	terrain.free()
	Sentinel.done("structures")


func _color_close(a: Color, b: Color) -> bool:
	"""True when two colours are the same to within one sRGB round trip."""
	return absf(a.r - b.r) <= COLOR_EPSILON and absf(a.g - b.g) <= COLOR_EPSILON and absf(a.b - b.b) <= COLOR_EPSILON



# ============================================================================
# CHECK 6 — the biome BAND CHAIN and its half of the CPU/GPU parity contract
# ============================================================================

## The parity-critical uniforms _apply_biome_shader_params is supposed to push.
## Written out rather than derived, for BUILDERS' reason: there is no registry to
## read, and a uniform that GDScript pushes but the GLSL never declares (or the
## reverse) is exactly the drift a hand-written list makes visible in review.
const PARITY_UNIFORMS: Array = [
	["biome_desert_max", "BIOME_DESERT_MAX"],
	["biome_plains_max", "BIOME_PLAINS_MAX"],
	["biome_city_max", "BIOME_CITY_MAX"],
	["biome_forest_max", "BIOME_FOREST_MAX"],
	["biome_mountain_max", "BIOME_MOUNTAIN_MAX"],
	["river_level", "RIVER_LEVEL"],
	["river_half_width", "RIVER_HALF_WIDTH"],
	["biome_blend", "BIOME_BLEND"],
]

const GROUND_SHADER: String = "res://assets/shaders/ground.gdshader"

## A uniform the shader must NOT have. The declared-uniform read is the whole
## basis of the parity check, and a read that answered "declared" to everything
## would pass it vacuously.
const ABSENT_UNIFORM: String = "biome_ocean_max"


func _check_biome_bands(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Adding a band to the biome field is four edits in two languages, and three of
	the four ways to get it wrong are invisible from inside the game.

	  a. THE CHAIN. The thresholds must be strictly increasing, and — the part
	     monotonicity alone does not give you — every band must be REACHABLE by
	     biome_at over the real field. A typo that leaves a band with zero width,
	     or an if-chain that tests them out of order, produces a perfectly ordered
	     set of constants and a territory that simply never generates.
	  b. RIVER_LEVEL MUST STAY INSIDE THE PLAINS BAND. Rivers are a contour of the
	     same field, so a retune that slides a band boundary across RIVER_LEVEL
	     puts every river in the world inside the new band instead.
	  c. EVERY INTERIOR BAND MUST BE WIDER THAN ONE BLEND RADIUS, or the two
	     smoothsteps either side of it overlap completely and the colour never
	     reaches full strength anywhere — a band you can stand in and not see.
	     The two OUTER bands are exempt by construction (one blend edge each).
	  d. PARITY. Every threshold has to exist on BOTH sides: declared as a uniform
	     in ground.gdshader AND pushed by _apply_biome_shader_params. Miss the
	     GDScript half and the shader silently keeps its default (the ground shows
	     the OLD band layout while the CPU spawns the new one); miss the GLSL half
	     and the push is silently discarded. Neither errors anywhere.
	"""
	var desert_max: float = float(consts["BIOME_DESERT_MAX"])
	var plains_max: float = float(consts["BIOME_PLAINS_MAX"])
	var city_max: float = float(consts["BIOME_CITY_MAX"])
	var forest_max: float = float(consts["BIOME_FOREST_MAX"])
	var mountain_max: float = float(consts["BIOME_MOUNTAIN_MAX"])
	var river_level: float = float(consts["RIVER_LEVEL"])
	var river_half: float = float(consts["RIVER_HALF_WIDTH"])
	var blend: float = float(consts["BIOME_BLEND"])
	var biome_enum: Dictionary = consts["Biome"]

	# ---- a. the chain is strictly increasing --------------------------------
	var chain: Array = [
		["BIOME_DESERT_MAX", desert_max], ["BIOME_PLAINS_MAX", plains_max],
		["BIOME_CITY_MAX", city_max], ["BIOME_FOREST_MAX", forest_max],
		["BIOME_MOUNTAIN_MAX", mountain_max],
	]
	for i in range(1, chain.size()):
		if float(chain[i][1]) <= float(chain[i - 1][1]):
			_fail("%s (%.3f) is not above %s (%.3f) — that band has zero or negative width"
					% [chain[i][0], chain[i][1], chain[i - 1][0], chain[i - 1][1]])

	# ---- a (control). every band is actually reachable through biome_at ------
	# Sweep the real field rather than the constants: this is what catches an
	# if-chain that tests the thresholds in the wrong order, which leaves the
	# constants perfectly ordered and a band unreachable.
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var seen: Dictionary = {}
	for ix in 220:
		for iz in 220:
			seen[terrain.biome_at(float(ix) * 20.0, float(iz) * 20.0)] = true
	for name_variant: Variant in biome_enum.keys():
		var band_name: String = String(name_variant)
		if not seen.has(int(biome_enum[band_name])):
			_fail("Biome.%s is never returned by biome_at anywhere in a 4.4 km field — the band is unreachable"
					% band_name)

	# ---- b. the river contour stays in plains -------------------------------
	# Tested on the constants, because that is where the rule lives: the band is
	# river_level +/- river_half_width, and both edges must classify as PLAINS.
	if desert_max >= river_level - river_half or plains_max <= river_level + river_half:
		_fail("the river contour %.3f +/- %.3f is not strictly inside the plains band [%.3f, %.3f) — rivers would move biome"
				% [river_level, river_half, desert_max, plains_max])

	# ---- c. every INTERIOR band is wide enough to render ---------------------
	# Generalised rather than written for the city alone: the snow band's arrival
	# narrowed FOREST and MOUNTAIN too, and a per-band special case is exactly the
	# thing that gets forgotten by the retune after next. The first band (below
	# BIOME_DESERT_MAX) and the last (above BIOME_MOUNTAIN_MAX) are exempt by
	# construction — each has only one blend edge, so it reaches full strength
	# outright; only a band squeezed between two blends can wash out.
	for i in range(1, chain.size()):
		var band_width: float = float(chain[i][1]) - float(chain[i - 1][1])
		if band_width <= blend:
			_fail("the band below %s is %.3f wide against a blend radius of %.3f — its colour never reaches full strength anywhere"
					% [chain[i][0], band_width, blend])

	# ---- d. parity, both directions -----------------------------------------
	var shader: Shader = load(GROUND_SHADER)
	if shader == null:
		_fail("could not load %s — the shader half of the parity contract cannot be checked" % GROUND_SHADER)
		terrain.free()
		Sentinel.done("biome_bands")
		return

	var declared: Dictionary = {}
	for entry_variant: Variant in shader.get_shader_uniform_list():
		var entry: Dictionary = entry_variant
		declared[String(entry["name"])] = true
	if declared.has(ABSENT_UNIFORM) or declared.is_empty():
		_fail("the shader's declared-uniform list is not trustworthy (%d entries, has %s: %s) — the parity check below would pass vacuously"
				% [declared.size(), ABSENT_UNIFORM, declared.has(ABSENT_UNIFORM)])

	var mat := ShaderMaterial.new()
	mat.shader = shader
	terrain.set("terrain_material", mat)
	terrain.call("_apply_biome_shader_params")

	for pair_variant: Variant in PARITY_UNIFORMS:
		var pair: Array = pair_variant
		var uniform: String = String(pair[0])
		var const_name: String = String(pair[1])
		if not declared.has(uniform):
			_fail("ground.gdshader declares no uniform '%s' — GDScript pushes a value the GPU discards, and the ground keeps drawing the old band layout"
					% uniform)
			continue
		if not consts.has(const_name):
			_fail("endless_terrain.gd has no constant %s" % const_name)
			continue
		var pushed: Variant = mat.get_shader_parameter(uniform)
		if pushed == null:
			_fail("_apply_biome_shader_params never pushes '%s' — the shader silently keeps its own default for it"
					% uniform)
			continue
		if absf(float(pushed) - float(consts[const_name])) > 1e-6:
			_fail("uniform '%s' was pushed as %.6f but %s is %.6f — the band the player SEES is not the band the CPU decides"
					% [uniform, float(pushed), const_name, float(consts[const_name])])

	print("  bands      %d thresholds, %d parity uniforms, %d bands reachable"
			% [chain.size(), PARITY_UNIFORMS.size(), seen.size()])
	terrain.free()
	Sentinel.done("biome_bands")


# ============================================================================
# CHECK 7 — the CITY territory's own contracts, measured on real geometry
# ============================================================================

func _check_city_content(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Build real city chunks and measure the three things this territory promises.

	  1. EVERY HOUSE ROOF IS REACHABLE. A city's whole gameplay contribution is
	     that its roofs give back the rest-from-crocodiles role the trees and
	     massifs took away, and the only thing standing between that and a field
	     of unclimbable boxes is one constant (CITY_HOUSE_HEIGHT_MAX) staying under
	     PROP_MAX_STEP. So every CLIMBABLE footprint the builder appends is
	     measured against PROP_MAX_STEP, with "it appended at least one climbable
	     footprint" as the negative control — a builder that placed nothing but
	     lamp posts satisfies "no roof is too high" perfectly.
	  2. NOTHING STRADDLES THE CHUNK SEAM. A chunk's mesh and collision belong to
	     one chunk, so an overhang vanishes the moment that chunk unloads while its
	     neighbour stays loaded. The city is the first builder whose positions are
	     SNAPPED to a grid after being drawn inside the margin, which is exactly the
	     way to push one back out over the edge.
	  3. THE COLLISION BUDGET, AS AN EXACT INVARIANT: every city building pays
	     EXACTLY ONE CollisionShape3D, so the collider count must equal the
	     footprint count. A house is a solid hull plus a roof slab, a door and its
	     windows; a stall is a solid counter plus an awning and two posts; a signal
	     is a solid mast plus a head and three lamps — trim, all of it. A ">= some
	     fraction" bound is NOT enough here and was measured not to be: making just
	     the roof slabs solid takes the chunk from 142 to 241 colliders, which any
	     loose bound still passes, while the equality catches it exactly.
	"""
	var max_step: float = float(consts["PROP_MAX_STEP"])
	var biome_enum: Dictionary = consts["Biome"]
	var city_value: int = int(biome_enum["CITY"])

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var chunk_size: float = float(terrain.get("chunk_size"))
	var half_chunk := chunk_size * 0.5

	# Find real city chunks in the real field — driving the builder at made-up
	# coordinates would exercise the edge-feathering rejection instead of the city.
	var city_chunks: Array[Vector2i] = []
	for cx in range(-40, 41):
		for cz in range(-40, 41):
			if city_chunks.size() >= 12:
				break
			var centre: Vector3 = terrain.chunk_to_world(Vector2i(cx, cz))
			if terrain.biome_at(centre.x, centre.z) == city_value:
				city_chunks.append(Vector2i(cx, cz))

	if city_chunks.size() < 6:
		_fail("only %d city chunks found in an 81x81 field — the city band is far rarer than the measured 12%% share"
				% city_chunks.size())
		terrain.free()
		Sentinel.done("city_content")
		return

	var climbable := 0
	var footprints := 0
	var boxes := 0
	var solids := 0
	var worst_top := 0.0
	var worst_reach := 0.0

	for chunk: Vector2i in city_chunks:
		var centre: Vector3 = terrain.chunk_to_world(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(chunk.x, chunk.y, 4242))
		var batch: Array = []
		var body := StaticBody3D.new()
		var obstacles: Array = []
		terrain.call("_spawn_city_content", centre, rng, obstacles, batch, body)

		boxes += batch.size()
		solids += body.get_child_count()
		body.free()

		for entry_variant: Variant in batch:
			var entry: Dictionary = entry_variant
			var xform: Transform3D = entry["transform"]
			for corner: Vector3 in UNIT_CORNERS:
				var p: Vector3 = xform * corner
				worst_reach = maxf(worst_reach, maxf(absf(p.x), absf(p.z)))

		footprints += obstacles.size()
		for ob_variant: Variant in obstacles:
			var ob: Dictionary = ob_variant
			if not bool(ob["climbable"]):
				continue
			climbable += 1
			worst_top = maxf(worst_top, float(ob["top"]))

	if climbable == 0:
		_fail("%d city chunks produced NO climbable footprint at all — the roofs that are supposed to be the city's rest spots are not being recorded"
				% city_chunks.size())
	elif worst_top > max_step + EPSILON:
		_fail("a city roof is recorded at %.3f m, past PROP_MAX_STEP %.2f — it cannot be jumped onto from the pavement"
				% [worst_top, max_step])

	if worst_reach > half_chunk + EPSILON:
		_fail("city geometry reaches %.2f m from the chunk centre, past the %.2f m seam — it would vanish with its own chunk"
				% [worst_reach, half_chunk])

	if boxes == 0:
		_fail("the city builder emitted no geometry at all across %d city chunks" % city_chunks.size())
	elif solids != footprints:
		_fail("%d city buildings produced %d collision shapes — one per building is the budget; roofs, doors, windows, awnings, posts and lamps are supposed to be visual-only trim"
				% [footprints, solids])

	print("  city       %d chunks, %d boxes (%d collide, %d buildings), %d roofs, tallest %.2f m, reach %.2f / %.1f m"
			% [city_chunks.size(), boxes, solids, footprints, climbable, worst_top, worst_reach, half_chunk])
	terrain.free()
	Sentinel.done("city_content")


# ============================================================================
# CHECK 8 — the SNOW territory's own contracts, measured on real geometry
# ============================================================================

## Seeds the mammoth builder is driven over on its own. Its shape is random in
## five places (yaw, spine length, rib count, per-rib height, bone tint), and the
## radius bound is the kind of thing one lucky seed satisfies.
const MAMMOTH_SEEDS: int = 40


func _check_snow_content(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Build real snow chunks and drive the mammoth builder on its own, measuring the
	four things this territory promises that nothing else in the project asserts.

	  1. THE MAMMOTH'S DECLARED RADIUS IS A TRUE BOUND ON ITS BONES. MAMMOTH_RADIUS
	     is what the crocodile spawner keeps its NPCs out of and what the massif
	     avoid-list reads, so a tusk poking outside it is a crocodile standing
	     inside a skull with no error anywhere. This is check 1's rule applied to
	     the one builder that is too big to be a scattered prop — and it is the
	     check the tusk curve most deserves, because that curve is walked segment
	     by segment through a quarter-turned yaw and a sign error anywhere in it
	     sends the tusks out the back of the animal, still looking plausible.
	  2. EXACTLY TWO COLLIDERS PER SKELETON. A skeleton is 16-18 boxes of which the
	     skull and the spine collide; the ribs and tusks are silhouette. As an
	     EXACT equality, not a bound — the failure being caught is a builder that
	     quietly drops `false` from its create_box calls, which any "at most N"
	     bound still passes while turning one skeleton into 18 collision shapes.
	  3. NOTHING SNOW BUILDS IS CLIMBABLE, with "it appended at least one
	     footprint" as the negative control. A climbable mammoth would let
	     _settle_coin_y perch a road coin on the 5 m footprint circle's `top` —
	     inside a ribcage, over open ground, unreachable.
	  4. NOTHING STRADDLES THE CHUNK SEAM. A chunk's mesh and collision belong to
	     one chunk, so an overhang vanishes the moment that chunk unloads while its
	     neighbour stays loaded, and a 5 m skeleton on a 25 m half-chunk has real
	     room to do it.
	"""
	var biome_enum: Dictionary = consts["Biome"]
	var snow_value: int = int(biome_enum["SNOW"])
	var mammoth_radius: float = float(consts["MAMMOTH_RADIUS"])
	var edge_margin: float = float(consts["MAMMOTH_EDGE_MARGIN"])

	# The seam bound the placement rests on, checked as arithmetic rather than
	# hoped for: a margin under the radius puts bones over the edge by construction.
	if edge_margin <= mammoth_radius:
		_fail("MAMMOTH_EDGE_MARGIN (%.2f) is not above MAMMOTH_RADIUS (%.2f) — a skeleton can straddle a chunk seam"
				% [edge_margin, mammoth_radius])

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var chunk_size: float = float(terrain.get("chunk_size"))
	var half_chunk := chunk_size * 0.5

	# ---- 1 + 2. the mammoth builder, driven directly -------------------------
	var worst_bone := 0.0
	var boxes_min := 999
	var boxes_max := 0
	for s in MAMMOTH_SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(s, 7717, 31))
		var batch: Array = []
		var body := StaticBody3D.new()
		var top: float = terrain.call("_snow_mammoth", Vector3.ZERO, rng, batch, body)
		var solids := body.get_child_count()
		body.free()

		boxes_min = mini(boxes_min, batch.size())
		boxes_max = maxi(boxes_max, batch.size())
		if solids != 2:
			_fail("a mammoth skeleton emitted %d collision shapes — the budget is EXACTLY two (skull + spine); ribs and tusks are silhouette, not solids"
					% solids)
		if top <= 0.0:
			_fail("a mammoth skeleton reported a spine height of %.3f m — its footprint would record a top at ground level" % top)
		worst_bone = maxf(worst_bone, _measured_reach(batch))

	if boxes_max == 0:
		_fail("the mammoth builder emitted no geometry at all — nothing was measured")
	elif worst_bone > mammoth_radius + EPSILON:
		_fail("a mammoth reaches %.3f m from its centre, past the declared MAMMOTH_RADIUS %.2f — crocodiles would spawn inside it and road coins would be settled against the wrong circle"
				% [worst_bone, mammoth_radius])

	# ---- 3 + 4. whole snow chunks -------------------------------------------
	# Real chunks in the real field, for _check_city_content's reason: driving the
	# builder at made-up coordinates exercises the edge-feathering rejection
	# instead of the territory.
	var snow_chunks: Array[Vector2i] = []
	for cx in range(-40, 41):
		for cz in range(-40, 41):
			if snow_chunks.size() >= 14:
				break
			var centre: Vector3 = terrain.chunk_to_world(Vector2i(cx, cz))
			if terrain.biome_at(centre.x, centre.z) == snow_value:
				snow_chunks.append(Vector2i(cx, cz))

	if snow_chunks.size() < 6:
		_fail("only %d snow chunks found in an 81x81 field — the snow band is far rarer than the measured 6%% share"
				% snow_chunks.size())
		terrain.free()
		Sentinel.done("snow_content")
		return

	var boxes := 0
	var solids_total := 0
	var footprints := 0
	var climbable := 0
	var worst_reach := 0.0

	for chunk: Vector2i in snow_chunks:
		var centre: Vector3 = terrain.chunk_to_world(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(chunk.x, chunk.y, 4242))
		var batch: Array = []
		var body := StaticBody3D.new()
		var obstacles: Array = []
		terrain.call("_spawn_snow_content", centre, rng, obstacles, batch, body)

		boxes += batch.size()
		solids_total += body.get_child_count()
		body.free()

		worst_reach = maxf(worst_reach, _axis_reach(batch))
		footprints += obstacles.size()
		for ob_variant: Variant in obstacles:
			var ob: Dictionary = ob_variant
			if bool(ob["climbable"]):
				climbable += 1

	if boxes == 0:
		_fail("the snow builder emitted no geometry at all across %d snow chunks" % snow_chunks.size())
	if footprints == 0:
		_fail("%d snow chunks produced NO footprint at all — nothing would keep a crocodile out of a dead tree or a skeleton"
				% snow_chunks.size())
	elif climbable > 0:
		_fail("%d snow footprints record climbable = true — a dead tree's top is 4 m up in the branches and a skeleton's is inside its ribcage, so _settle_coin_y must SKIP a road coin there, not perch one"
				% climbable)

	if worst_reach > half_chunk + EPSILON:
		_fail("snow geometry reaches %.2f m from the chunk centre, past the %.2f m seam — it would vanish with its own chunk"
				% [worst_reach, half_chunk])

	print("  snow       %d chunks, %d boxes (%d collide, %d footprints, 0 climbable), reach %.2f / %.1f m"
			% [snow_chunks.size(), boxes, solids_total, footprints, worst_reach, half_chunk])
	print("  mammoth    %d seeds, %d-%d boxes, 2 colliders each, worst bone %.3f / %.2f m declared"
			% [MAMMOTH_SEEDS, boxes_min, boxes_max, worst_bone, mammoth_radius])
	terrain.free()
	Sentinel.done("snow_content")


## CHECK 10 — the forest's own restyle contract (bead godot-test1-u7a).
## How many distinct leaf shades a wood must show before it stops reading as one
## flat material. A chunk carries 25-40 trees, so anything above a handful proves
## the per-tree tint draw is really reaching the batch; the number is low on
## purpose — it is a floor against a REVERT to one colour, not a taste knob.
const FOREST_MIN_LEAF_SHADES: int = 8

## What fraction of a wood's trunks must actually lean. The draw is symmetric over
## [-TREE_TRUNK_TILT_MAX, +TREE_TRUNK_TILT_MAX] so in practice it is all of them;
## the bound is loose so a future retune that narrows the lean does not fail here
## for being tasteful, only for being ZERO.
const FOREST_MIN_LEANING_FRACTION: float = 0.9


func _check_forest_content(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	The forest had no check of its own before this bead, and the restyle gave it
	four things worth measuring — all of them driven through the SHIPPED
	_spawn_forest_content over real forest chunks, never re-derived here.

	  1. THE CHUNK SEAM. The trunk now LEANS and the canopy rides that lean, so a
	     canopy travels sideways from the trunk that placed it and the old seam
	     margin (canopy half-diagonal alone) stopped being an upper bound. A
	     canopy over the seam vanishes with its own chunk while the neighbour is
	     still drawn — the same failure _check_snow_content's clause 4 exists for.
	  2. ONE COLLIDER PER TREE, EXACTLY. Canopies pass collide = false; that is
	     the whole reason a 40-tree chunk is affordable. As an equality against
	     the footprint count, not a bound, because a builder that quietly drops a
	     `false` still satisfies any "at most" and turns each tree into four
	     collision shapes.
	  3. NOTHING IN A WOOD IS CLIMBABLE. A climbable tree footprint would let
	     _settle_coin_y perch a road coin on `top` — 4 m up a trunk, unreachable.
	  4. THE RESTYLE ITSELF, which is the only reason this check is new: the wood
	     must show many distinct leaf shades (a single flat green was the loudest
	     half of the Minecraft read the owner reported) and its trunks must
	     actually lean. Both are measured off the emitted batch, so reverting
	     either one in the builder fails here.
	  5. THE SILHOUETTE (bead godot-test1-y1o.2, retuning what u7a left here).
	     u7a asserted the canopy's PITCH, because a stack of level SLABS was the
	     shape that still read as a cube once the colours and the yaw were fixed.
	     A pitched sphere is the same sphere, so that clause measured nothing the
	     day the canopy stopped being a box: it is replaced by the thing that now
	     carries the silhouette — EVERY canopy entry is BoxKind.SPHERE and EVERY
	     trunk is BoxKind.CUBE. Both halves matter. A canopy that reverts to a
	     cube is the Minecraft read back; a TRUNK that drifts to a round kind is
	     the collision bug ChunkBatch's banner warns about, since the trunk is the
	     one colliding box in a tree and a shape carries no kind.

	The negative controls are the non-empty assertions: an empty batch would
	satisfy the seam bound, the equality and the climbable count perfectly.
	"""
	var biome_enum: Dictionary = consts["Biome"]
	var forest_value: int = int(biome_enum["FOREST"])
	# The two ends of the per-tree tint ramp, linearised the way create_box stores
	# them. Read from the constant map so a colour retune moves this with it.
	var leaf_a: Color = (consts["TREE_LEAF_COLOR"] as Color).srgb_to_linear()
	var leaf_b: Color = (consts["TREE_LEAF_COLOR_WARM"] as Color).srgb_to_linear()

	# A canopy layer is turned against the one below it, and a SQUARE has 90 deg
	# symmetry — so a step that is a multiple of PI/2 turns nothing at all and the
	# stack goes back to being aligned cubes. Asserted on the constant because the
	# effect (two layers of ONE tree crossing) cannot be recovered from a chunk
	# batch without re-grouping boxes into trees, which would re-implement the
	# builder inside the check.
	var yaw_step: float = float(consts["TREE_CANOPY_YAW_STEP"])
	if absf(fmod(absf(yaw_step), PI * 0.5)) < EPSILON:
		_fail("TREE_CANOPY_YAW_STEP %.4f is a multiple of PI/2 — a square canopy has 90 deg symmetry, so every layer lands back on the one below and the crown is a column of aligned cubes again"
				% yaw_step)

	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var chunk_size: float = float(terrain.get("chunk_size"))
	var half_chunk := chunk_size * 0.5

	var forest_chunks: Array[Vector2i] = []
	for cx in range(-40, 41):
		for cz in range(-40, 41):
			if forest_chunks.size() >= 12:
				break
			var centre: Vector3 = terrain.chunk_to_world(Vector2i(cx, cz))
			if terrain.biome_at(centre.x, centre.z) == forest_value:
				forest_chunks.append(Vector2i(cx, cz))

	if forest_chunks.size() < 6:
		_fail("only %d forest chunks found in an 81x81 field — the forest band is far rarer than the measured 10.7%% share"
				% forest_chunks.size())
		terrain.free()
		Sentinel.done("forest_content")
		return

	var boxes := 0
	var solids := 0
	var footprints := 0
	var climbable := 0
	var trunks := 0
	var leaning := 0
	var leaves := 0
	var boxy_leaves := 0
	var round_trunks := 0
	var shades: Dictionary = {}
	var worst_reach := 0.0

	for chunk: Vector2i in forest_chunks:
		var centre: Vector3 = terrain.chunk_to_world(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(chunk.x, chunk.y, 4242))
		var batch: Array = []
		var body := StaticBody3D.new()
		var obstacles: Array = []
		terrain.call("_spawn_forest_content", centre, rng, obstacles, batch, body)

		boxes += batch.size()
		solids += body.get_child_count()
		body.free()
		worst_reach = maxf(worst_reach, _axis_reach(batch))
		footprints += obstacles.size()
		for ob_variant: Variant in obstacles:
			if bool((ob_variant as Dictionary)["climbable"]):
				climbable += 1

		for entry_variant: Variant in batch:
			var entry: Dictionary = entry_variant
			var c: Color = entry["color"]
			if _color_on_ramp(c, leaf_a, leaf_b):
				# Quantised, so "how many shades" is a count of visibly different
				# greens rather than of float noise.
				shades[Vector3i(roundi(c.r * 400.0), roundi(c.g * 400.0), roundi(c.b * 400.0))] = true
				leaves += 1
				if int(entry["kind"]) != ChunkBatch.BoxKind.SPHERE:
					boxy_leaves += 1
				continue
			# Not a leaf: it is a trunk. Its local UP is only Vector3.UP when the
			# lean was zero.
			trunks += 1
			if int(entry["kind"]) != ChunkBatch.BoxKind.CUBE:
				round_trunks += 1
			var up: Vector3 = (entry["transform"] as Transform3D).basis.y.normalized()
			if up.distance_to(Vector3.UP) > EPSILON:
				leaning += 1

	if boxes == 0 or footprints == 0:
		_fail("%d forest chunks produced no trees at all — nothing was measured" % forest_chunks.size())
		terrain.free()
		Sentinel.done("forest_content")
		return

	if worst_reach > half_chunk + EPSILON:
		_fail("forest geometry reaches %.2f m from the chunk centre, past the %.2f m seam — a canopy would vanish with its own chunk while its neighbour still draws"
				% [worst_reach, half_chunk])
	if solids != footprints:
		_fail("a wood of %d footprints emitted %d collision shapes — it must be EXACTLY one per tree (the trunk); canopies are collide = false, which is what makes 40 trees a chunk affordable"
				% [footprints, solids])
	if climbable > 0:
		_fail("%d forest footprints record climbable = true — a tree's top is 4 m up the trunk, so _settle_coin_y must SKIP a road coin there, not perch one"
				% climbable)
	if shades.size() < FOREST_MIN_LEAF_SHADES:
		_fail("a wood of %d trees shows only %d distinct leaf shades (floor %d) — one flat green is the Minecraft read bead u7a exists to remove"
				% [footprints, shades.size(), FOREST_MIN_LEAF_SHADES])
	if trunks == 0:
		_fail("no forest box was coloured OFF the leaf ramp — the trunk sample is empty, so the lean and the kind below measured nothing")
	else:
		if float(leaning) / float(trunks) < FOREST_MIN_LEANING_FRACTION:
			_fail("only %d of %d forest trunks lean off vertical (floor %.0f%%) — an upright box on flat ground is a fence post, not a tree"
					% [leaning, trunks, FOREST_MIN_LEANING_FRACTION * 100.0])
		if round_trunks > 0:
			_fail("%d of %d forest trunks are not BoxKind.CUBE — a trunk is the ONE colliding box in a tree and a collision shape carries no kind, so a round trunk is a box you bump into that is not where you see it"
					% [round_trunks, trunks])
	# THE SILHOUETTE, replacing u7a's canopy-pitch clause (see clause 5 above): a
	# pitched sphere is the same sphere, so pitch stopped measuring anything the
	# day the canopy stopped being a box. This is an equality on EVERY canopy
	# entry rather than a fraction — there is no index alternation to excuse a
	# cube here — and `leaves == 0` is still its negative control.
	if leaves == 0:
		_fail("no forest box was coloured ON the leaf ramp — the canopy sample is empty, so the kind below measured nothing")
	elif boxy_leaves > 0:
		_fail("%d of %d forest canopy blobs are not BoxKind.SPHERE — a canopy back on the shared unit CUBE is the Minecraft silhouette bead y1o.2 exists to remove"
				% [boxy_leaves, leaves])

	print("  forest     %d chunks, %d boxes (%d collide, %d footprints, 0 climbable), %d leaf shades, %d/%d trunks lean, %d/%d canopy blobs are spheres, %d/%d trunks are cubes, reach %.2f / %.1f m"
			% [forest_chunks.size(), boxes, solids, footprints, shades.size(), leaning, trunks,
			   leaves - boxy_leaves, leaves, trunks - round_trunks, trunks, worst_reach, half_chunk])
	terrain.free()
	Sentinel.done("forest_content")


func _color_on_ramp(c: Color, a: Color, b: Color) -> bool:
	"""
	Is `c` a point on the straight line from `a` to `b` in sRGB?

	_structure_stone samples exactly that line, so this is the test for "this box
	was coloured by its territory's theme" — and, run across two different
	territories, the test for "these two territories look different".
	"""
	var d := Vector3(b.r - a.r, b.g - a.g, b.b - a.b)
	# Solve for t on whichever channel moves most, so a near-grey ramp does not
	# divide by ~0 and answer yes to everything.
	var axis := 0
	if absf(d.y) > absf(d[axis]):
		axis = 1
	if absf(d.z) > absf(d[axis]):
		axis = 2
	if absf(d[axis]) < COLOR_EPSILON:
		return _color_close(c, a)
	var cv := Vector3(c.r, c.g, c.b)
	var av := Vector3(a.r, a.g, a.b)
	var t: float = (cv[axis] - av[axis]) / d[axis]
	if t < -COLOR_EPSILON or t > 1.0 + COLOR_EPSILON:
		return false
	return (av + d * t - cv).length() <= COLOR_EPSILON * 2.0


func _has_top(tops: Array[float], y: float) -> bool:
	"""True when one of the standable surfaces sits at height `y`."""
	for top: float in tops:
		if absf(top - y) <= EPSILON:
			return true
	return false


func _axis_reach(batch: Array) -> float:
	"""
	The furthest any emitted corner gets from the chunk centre along X or Z.

	Per-AXIS, unlike _measured_reach's radial distance: a chunk is a square, so
	what a seam test needs is max(|x|, |z|), not the length of the offset.
	"""
	var worst := 0.0
	for entry_variant: Variant in batch:
		var entry: Dictionary = entry_variant
		var xform: Transform3D = entry["transform"]
		for corner: Vector3 in UNIT_CORNERS:
			var p := xform * corner
			worst = maxf(worst, maxf(absf(p.x), absf(p.z)))
	return worst
