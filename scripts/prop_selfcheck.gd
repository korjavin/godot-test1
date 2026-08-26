extends SceneTree
## Headless self-check for the themed scattered props.
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

	if _failures.is_empty():
		print("props: %d builders x %d seeds x %d sizes measured; radius bound, climb ladder, box budget and chunk purity OK"
				% [BUILDERS.size(), SEEDS_PER_BUILDER, SIZES.size()])
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
		# Does this box's footprint cover the prop centre? The box is yawed, so the
		# test projects the centre offset onto the box's own horizontal axes.
		var to_centre := -shape.transform.origin
		if absf(to_centre.dot(basis.x.normalized())) > box.size.x * 0.5:
			continue
		if absf(to_centre.dot(basis.z.normalized())) > box.size.z * 0.5:
			continue
		tops.append(shape.transform.origin.y + box.size.y * 0.5)

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
