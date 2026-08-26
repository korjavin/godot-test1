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
const TERRITORIES: Array = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN"]

## Structure trials per role per territory. Structures draw far more than a prop
## does (length, doubling, gaps, lintels), so the sweep needs breadth; 40 x 4 x 4
## is 640 real structures and still runs in well under a second.
const STRUCTURE_SEEDS: int = 40

## Colour slack. Every emitted colour is stored srgb_to_linear'd in the batch and
## converted back here, so a couple of round-trip ULPs have to be absorbed.
const COLOR_EPSILON: float = 0.004

var _failures: Array[String] = []


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

	if _failures.is_empty():
		print("props: %d builders x %d seeds x %d sizes measured; radius bound, climb ladder, box budget and chunk purity OK"
				% [BUILDERS.size(), SEEDS_PER_BUILDER, SIZES.size()])
		print("structures: %d roles x %d territories x %d seeds measured; palette, patrol platforms and pyramid retirement OK"
				% [ROLES.size(), TERRITORIES.size(), STRUCTURE_SEEDS])
		print("SELFCHECK OK")
		quit(0)
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
			if ea["transform"] != eb["transform"] or ea["color"] != eb["color"]:
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


func _color_close(a: Color, b: Color) -> bool:
	"""True when two colours are the same to within one sRGB round trip."""
	return absf(a.r - b.r) <= COLOR_EPSILON and absf(a.g - b.g) <= COLOR_EPSILON and absf(a.b - b.b) <= COLOR_EPSILON


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
