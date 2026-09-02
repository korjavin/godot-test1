extends SceneTree
## Headless self-check: BUDAPEST IS AUTHORED, AND IT IS STREAMED LIKE EVERYTHING ELSE.
##
##   godot --headless --path . --script res://scripts/budapest_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1 — the
## same shape as tower_shell_selfcheck.gd / chunk_stream_selfcheck.gd, and it
## exists for the same reason those do: every way of breaking a 2.2 km city looks
## like ordinary scenery from inside it.
##
## ============================ WHAT IT GUARDS ============================
##
## Bead godot-test1-8gw.3. The city is a table of constants (budapest_plan.gd)
## drawn by the ordinary chunk streamer (endless_terrain.gd). Both halves fail
## silently, which is what every check below is for:
##
##   1. PLAN PURITY. A `run_seed` or a `randf()` in the plan would move the
##      Opera between runs. Nothing on screen says so — the city looks like a
##      city — but the win condition (explore 18 of 22 landmarks), the map and
##      the reachability audit are all statements about a FIXED layout.
##   2. THE PLAN IS WELL FORMED. A slot whose disc leaves the rect, overlaps its
##      neighbour, stands in the water or disagrees with the registry's radius is
##      a building that clips through another building — 900 m from anywhere the
##      player usually is, in a chunk nobody streamed while the change was made.
##   3. TWO IDENTICAL REGENERATIONS, ACROSS SEEDS. Not "deterministic within a
##      run" (which every spawner promises) but IDENTICAL BETWEEN RUNS, which
##      only the city claims. A seed leaking into it is invisible until two
##      players compare screenshots.
##   4. PER-CHUNK BUDGETS. A landmark builder that stopped being a pure function
##      of (centre, rng) would emit its whole 122-box self into all 49 chunks its
##      disc touches. The frame cost is the only symptom, and the frame it lands
##      on is one chunk out of the drain.
##   5. THE SLICING DECISION. Every box the unclipped builder emits, kept exactly
##      once across the slices. Lose one and there is a hole in the Parliament;
##      keep it twice and two z-fighting walls stand in the same metre; draw the
##      slices off different seeds and the building is tie-dyed along its seams.
##   6. CPU/GPU PARITY. The blue you see and the water you wade are two languages
##      computing one predicate. They drift silently: the ground stays painted.
##   7. THE APPROACH CORRIDOR REACHES THE GATE. The road's Z wanders with the run
##      seed and the city does not, so this is the one seam where an authored
##      world meets a seeded one. A corridor that missed would leave the player
##      walking into a rect edge with no coins and nothing to follow.
##   8. THE CONSUMERS STOP AT T. Four of them, in three files. One left uncapped
##      lays a second coin trail through Pest, or paints a road on the map that
##      carries nothing, or stands a boss in a suburb.
##   9. THE SPAWNER POLICY. The city rect is not tower_excludes(): it is five
##      per-system answers. A missed early return puts a cactus in Váci utca; a
##      too-broad one kills the hunters (which is why check 9 carries a positive
##      control for them).
##  10. THE CROCODILE STREAM. The Danube's spawner takes its own hash stream. One
##      draw taken from the shared one slides EVERY crocodile in the world, which
##      nothing on screen would ever tell you and which two peers on different
##      builds would disagree about in silence.
##  11. THE PLATEAU RAMPS. The only way onto a hill. A ramp too steep, hanging
##      above y = 0, or whose slices disagree at a seam is a hill you cannot
##      climb — and the four landmarks on the two lids are unreachable with it.
##  12. THE DIFFICULTY CLAMP. Pinned at the gate's X. Uncaught, walking east
##      through the city keeps escalating a gradient the run was supposed to end.
##  13. THE AVENUE IS WALKABLE. The one corridor this bead promises: gate to west
##      bank, nothing solid standing in it.
##  15. THE CITY IS FULL, AND STILL A CITY (bead godot-test1-8gw.9). Every block
##      of the grid the plan does not reserve is filled with a street wall, which
##      is ~1,250 new buildings and four ways to be quietly wrong: a block over a
##      landmark, a facade standing in a street, a courtyard filled solid, and a
##      coin route that drops pickups inside a wall or skips a bridge. Check 4
##      grew the WEB RESIDENCY window with it, because filling the city moved the
##      cost from "one expensive chunk" to "1,631 ordinary ones" and a per-chunk
##      ceiling cannot see that at all.
##
## Deliberately NOT covered: the full one-hero reachability audit over all 22
## slots (bead godot-test1-8gw.10), and how any of it LOOKS. This file measures
## the contracts; the eye measures the rest.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches (the shared
## unit box mesh, the crocodile/coin PackedScenes). They are not a failure — the
## same note enemy_spawn_selfcheck.gd's header carries.

const PLAN_PATH: String = "res://scripts/budapest_plan.gd"
const TERRAIN_PATH: String = "res://scripts/endless_terrain.gd"
const SHADER_PATH: String = "res://assets/shaders/ground.gdshader"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

## The one seed most checks run under. The city is authored, so for nearly
## everything here the seed is irrelevant BY THE PROPERTY UNDER TEST — which is
## exactly why check 3 uses two of them and check 7 uses fifty.
const RUN_SEED: int = 20260902
const SECOND_SEED: int = 771133

## How many run seeds check 7 drives the road -> city join through. The road's
## terminal station is the ONE place a run's seed reaches the city, so this is
## the only check in the file that needs a population rather than a sample.
const APPROACH_SEEDS: int = 50

## The tokens check 1 refuses to find in the plan. `hash(` catches the call and
## not the word, so the header's own prose about hashing is not a false positive.
const BANNED_TOKENS: Array[String] = ["run_seed", "randf", "randi", "hash("]

## Check 11's tolerance, in metres, and it is not a fudge factor: a ramp slab is
## CITY_RAMP_THICKNESS thick and TILTED, so the top edge of its END FACE sits
## thickness/2 * (1 - cos(tilt)) below the ideal plane — 1.1 cm on both of this
## city's ramps. The measurement is printed, so a ramp that drifted would show up
## as a number long before it hit this bound.
const RAMP_FLUSH_TOL: float = 0.02

## How far outside the Danube's band check 11 demands the hills and their ramps
## stay, in metres. A margin and not a zero, because the band's edge is where the
## wade begins and a hill authored flush against it is one retune of
## DANUBE_HALF_WIDTH away from standing in the water. Both hills clear it today.
const PLATEAU_DRY_MARGIN: float = 10.0

## Check 9's sweep: every Nth chunk of the rect in both axes, which lands ~60
## chunks spread over the whole 2.2 km rather than a corner of it.
const POLICY_CHUNK_STRIDE: int = 6

## How many extra times check 4 rebuilds a chunk that went over the wall-clock
## budget before believing it. See the block that reads it: the budget is a
## runaway detector on a shared machine, and four retries is the difference
## between catching a builder that got slow and catching the CI scheduler.
const MS_REMEASURES: int = 4

## Check 4's ceiling on the emissive accents ONE city chunk may hang beside its
## batch. An accent is a real MeshInstance3D and therefore a real extra draw call
## — the one thing the city is allowed to add on top of its single batched mesh,
## because the batch's shared material is matte and an accent glows. Measured, not
## guessed: the worst city chunk is printed beside it.
const CITY_CHUNK_ACCENT_BUDGET: int = 4

## The web build's chunk residency radius — `endless_terrain.WEB_RENDER_DISTANCE`
## restated here only because check 4's window has to be a compile-time square.
## 3 means a 7 x 7 = 49-chunk view, which is the number CLAUDE.md's whole "the
## city is streamed and the tower is not" argument rests on.
const WEB_RENDER_DISTANCE: int = 3

## What the worst 49-chunk WEB VIEW of Budapest may hold. MEASURED, not guessed —
## the reading is printed beside each one, and see _check_web_residency for why a
## per-chunk budget cannot answer this question. Both are order-of-magnitude
## guards on a number that quadrupled when bead .9 filled the blocks.
const CITY_RESIDENCY_BOX_BUDGET: int = 3000
const CITY_RESIDENCY_SHAPE_BUDGET: int = 900

## How many chunk columns / rows of the rect check 15's collision sweep walks.
## The sweep is the expensive half of that check (every shape in every chunk,
## projected through its own basis), and the property it measures — "no solid box
## overlaps a street" — is a claim about the BUILDER, not about a neighbourhood,
## so a stride that lands ~230 chunks spread over the whole 2.2 km proves it as
## well as all 2,025 would.
const BLOCK_SWEEP_STRIDE: int = 3

## Check 15's tolerance where a facade meets a street, in metres. A hull's own
## edge sits BLOCK_PAVEMENT (1.2 m) back from the carriageway, so anything this
## check reports is a real overlap and not an f32 boundary — the epsilon only
## stops a box that ends exactly on a courtyard line from reading as inside it.
const BLOCK_TOUCH_EPS: float = 0.01

## How far along one avenue check 15 walks looking for its coins, in chunks.
const COIN_WALK_CHUNKS: int = 24

var _failures: Array[String] = []


func _initialize() -> void:
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING, for the reason enemy_spawn_selfcheck.gd gives: a
	# node added to `root` from inside _initialize() is not `is_inside_tree()`
	# until the first frame, and several spawners here read a global transform.
	await process_frame
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_PATH)

	_check_plan_purity()
	_check_plan_well_formed()

	var terrain := _make_terrain(RUN_SEED)
	_check_regeneration(terrain_script)
	_check_budgets(terrain, terrain_script)
	_check_slicing(terrain)
	_check_parity(terrain)
	_check_approach_corridor(terrain_script)
	_check_consumers_stop(terrain, terrain_script)
	_check_spawner_policy(terrain)
	_check_crocodile_stream_ab(terrain_script)
	_check_ramps(terrain)
	_check_difficulty_clamp()
	_check_avenue(terrain)
	_check_bridges(terrain)
	_check_city_blocks(terrain)
	terrain.free()

	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("SELFCHECK OK")
		quit(0)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


# ============================================================================
# HARNESS
# ============================================================================

func _make_terrain(run_seed: int) -> Node3D:
	"""
	A real terrain node in the tree, with its run seed forced through the public
	set_run_seed() seam — the same one new_run() and the multiplayer forced seed
	go through, so this harness cannot rot away from the game.

	It never streams on its own: _ready() finds no node in group "player", so
	`player` stays null and _process returns immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_PATH))
	root.add_child(terrain)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)
	return terrain


func _detached_terrain(terrain_script: GDScript, run_seed: int) -> Node3D:
	"""A terrain that never joins the tree, for the checks that only ask it pure
	questions (the road cache, the city streamer). THE CALLER FREES IT."""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)
	return terrain


func _build_city_chunk(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Run the city streamer over ONE chunk into fresh receptacles.

	@param terrain: a terrain with its run seed already forced
	@param chunk_pos: the chunk to build
	@return { parent, batch, body, obstacles, msec } — THE CALLER FREES `parent`
	        and `body`.

	Only spawn_city_in_chunk, because inside the rect that is the only thing that
	builds anything (the spawner policy is what check 9 measures). `parent` is
	positioned at the chunk's world origin the way create_chunk's is, so anything
	that reads a global transform sees the truth.
	"""
	var parent := MeshInstance3D.new()
	parent.position = terrain.chunk_to_world(chunk_pos)
	root.add_child(parent)
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = []
	var t0 := Time.get_ticks_usec()
	terrain.spawn_city_in_chunk(chunk_pos, parent, obstacles, batch, body)
	var msec := float(Time.get_ticks_usec() - t0) / 1000.0
	return {"parent": parent, "batch": batch, "body": body,
			"obstacles": obstacles, "msec": msec}


func _generate_chunk(terrain: Node3D, chunk_pos: Vector2i) -> MeshInstance3D:
	"""
	create_chunk's WHOLE spawner sequence over one chunk. THE CALLER FREES the
	parent.

	The order is create_chunk's and the order is the point: the later spawners
	judge their candidates against footprints the earlier ones appended, so a
	body placed against a half-built obstacle list stands somewhere the real game
	would never put it.
	"""
	var parent := MeshInstance3D.new()
	parent.position = terrain.chunk_to_world(chunk_pos)
	root.add_child(parent)
	var platforms: Array = []
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
	terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
	terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_city_in_chunk(chunk_pos, parent, obstacles, batch, body)
	terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_platform_crocodiles(chunk_pos, parent, platforms)
	terrain.spawn_danube_crocodiles_in_chunk(chunk_pos, parent)
	terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_hunters_in_chunk(chunk_pos, parent, obstacles)
	body.free()
	return parent


func _rect_chunks(terrain: Node3D, stride: int = 1) -> Array[Vector2i]:
	"""Every stride'th chunk whose square can meet the city rect."""
	var lo: Vector2i = terrain.world_to_chunk(
			Vector3(BudapestPlan.BUDAPEST_MIN.x, 0.0, BudapestPlan.BUDAPEST_MIN.y))
	var hi: Vector2i = terrain.world_to_chunk(
			Vector3(BudapestPlan.BUDAPEST_MAX.x, 0.0, BudapestPlan.BUDAPEST_MAX.y))
	var out: Array[Vector2i] = []
	var cx := lo.x
	while cx <= hi.x:
		var cz := lo.y
		while cz <= hi.y:
			out.append(Vector2i(cx, cz))
			cz += stride
		cx += stride
	return out


func _slot_index(id: String) -> int:
	for i in range(BudapestPlan.SLOTS.size()):
		if String((BudapestPlan.SLOTS[i] as Dictionary)["id"]) == id:
			return i
	return -1


# ============================================================================
# CHECK 1 — the plan is DATA: no seed, no draw, no hash
# ============================================================================

func _check_plan_purity() -> void:
	"""
	Read budapest_plan.gd as TEXT and refuse to find a seed, a draw or a hashing
	call in it.

	AS TEXT, not through the parser, because the failure this catches is a future
	author reaching for the thing every other spawner in this project reaches for.
	The file's own header states the rule; this is what makes it a rule.
	"""
	var text := FileAccess.get_file_as_string(PLAN_PATH)
	if text.is_empty():
		_fail("could not read %s — check 1 measured nothing" % PLAN_PATH)
		return

	var hits := _scan_banned(text)
	if not hits.is_empty():
		# PARENTHESISED: `%` binds tighter than `+`, so without the brackets the
		# format applies to the LAST fragment — which carries no specifier — and
		# the only thing this check has to say (what it found, and where) is
		# replaced by an engine formatting error.
		_fail(("budapest_plan.gd is supposed to be pure authored DATA, but it "
				+ "contains %s — a city that moves between runs cannot be put on a "
				+ "map, audited for reachability or described to a player")
				% ", ".join(hits))

	# THE NEGATIVE CONTROL. A scanner with a typo in its token list passes this
	# file perfectly, so it is shown a string that must trip it.
	var control := _scan_banned("var x := hash(Vector3i(1, 2, run_seed))\n")
	if control.size() < 2:
		_fail("check 1's scanner did not flag a line containing BOTH hash( and "
				+ "run_seed (found %d) — the scan above proved nothing" % control.size())

	print("plan purity: %d lines scanned for %s, %d hits (control: %d)" % [
			text.split("\n").size(), ", ".join(BANNED_TOKENS), hits.size(), control.size()])


func _scan_banned(text: String) -> Array[String]:
	"""Every (token, line) the banned list appears at, as printable strings."""
	var out: Array[String] = []
	var lines := text.split("\n")
	for i in range(lines.size()):
		for token: String in BANNED_TOKENS:
			if lines[i].contains(token):
				out.append("%s on line %d" % [token, i + 1])
	return out


# ============================================================================
# CHECK 2 — the plan is well formed
# ============================================================================

func _check_plan_well_formed() -> void:
	"""
	The 22 slots, measured against the rect, against each other, against the
	registry that owns their geometry and against the river they stand beside.

	The registry comparison is the sharpest of them: a slot copies
	LandmarkBuilders.CITY_LANDMARKS' declared radius, so a later edit to a
	shipped builder's radius has to fail HERE — otherwise the building simply
	starts overhanging into the street, 900 m from the spawn point.
	"""
	var slots: Array = BudapestPlan.SLOTS
	if slots.size() != 22:
		_fail("BudapestPlan.SLOTS holds %d rows, not the 22 the win set is "
				% slots.size() + "counted against (bead godot-test1-8gw.5)")

	var registry := {}
	for row_v: Variant in LandmarkBuilders.CITY_LANDMARKS:
		var row: Dictionary = row_v
		registry[String(row["builder"])] = float(row["radius"])

	var rect: Rect2 = BudapestPlan.rect()
	var reserved := 0
	var on_plateau := 0
	var in_band := 0
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var id := String(slot["id"])
		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]

		# The whole disc, not the centre: a building that overhangs the rect is a
		# building half of whose chunks are outside every city rule in the game.
		if pos.x - radius < rect.position.x or pos.x + radius > rect.end.x \
				or pos.z - radius < rect.position.y or pos.z + radius > rect.end.y:
			_fail("slot '%s' (r=%.0f at %.0f, %.0f) reaches outside the city rect"
					% [id, radius, pos.x, pos.z])

		for j in range(i + 1, slots.size()):
			var other: Dictionary = slots[j]
			var op: Vector3 = other["pos"]
			var gap := Vector2(pos.x - op.x, pos.z - op.z).length() - radius - float(other["radius"])
			if gap < 0.0:
				_fail("slots '%s' and '%s' overlap by %.1f m — two authored "
						% [id, String(other["id"]), -gap]
						+ "buildings would be drawn through each other")

		var builder := String(slot["builder"])
		if builder.is_empty():
			# A wave-C reservation: a position and a radius, no stone yet. Exempt
			# from the registry check BY DESIGN — that is the whole of "leave the
			# slot empty".
			reserved += 1
		elif not registry.has(builder):
			_fail("slot '%s' names builder '%s', which is not a row of "
					% [id, builder] + "LandmarkBuilders.CITY_LANDMARKS")
		elif not is_equal_approx(float(registry[builder]), radius):
			_fail("slot '%s' declares radius %.1f but the registry declares %.1f "
					% [id, radius, float(registry[builder])]
					+ "for '%s' — the plan and the geometry disagree" % builder)

		# NOTHING STANDS IN THE RIVER, and the exemption is the mechanism rather
		# than a name list: a slot inside the band is legal exactly when it stands
		# on a DRY_RECTS row, which is what a bridge deck and Margaret Island both
		# are. So the band test and the dry test are one statement.
		if BudapestPlan.danube_distance(pos.x, pos.z) < BudapestPlan.DANUBE_HALF_WIDTH:
			in_band += 1
			if not BudapestPlan.is_dry(pos.x, pos.z):
				_fail("slot '%s' stands in the Danube (%.0f m from the polyline, "
						% [id, BudapestPlan.danube_distance(pos.x, pos.z)]
						+ "band half-width %.0f) and on no dry rect"
						% BudapestPlan.DANUBE_HALF_WIDTH)

		# A slot's authored base height IS its plateau's lid, or 0. Asked of every
		# row in both directions, so a slot that drifted onto a hill without its
		# `pos.y` following fails here rather than being buried inside it.
		var lid: float = BudapestPlan.plateau_top_at(pos.x, pos.z)
		if not is_equal_approx(lid, pos.y):
			_fail("slot '%s' is authored at y = %.1f but the ground under it is "
					% [id, pos.y] + "%.1f — it would stand inside or above its hill" % lid)
		if lid > 0.0:
			on_plateau += 1

	print("plan: %d slots (%d wave-C reservations), %d on a plateau lid, %d "
			% [slots.size(), reserved, on_plateau, in_band]
			+ "inside the Danube band and all of them on a dry rect")


# ============================================================================
# CHECK 3 — two identical regenerations, on two different run seeds
# ============================================================================

func _check_regeneration(terrain_script: GDScript) -> void:
	"""
	Build the same city chunks from two fresh terrains on two DIFFERENT run seeds
	and compare every box and every collision shape byte for byte.

	THIS IS A STRONGER STATEMENT THAN ANY OTHER SPAWNER IN THIS GAME MAKES. The
	rest of the world promises "a revisited chunk regenerates identically WITHIN a
	run"; the city promises it ACROSS runs, because it is authored and because the
	win condition is a statement about a fixed layout. The two seeds are what say
	so — a seed leaking into the streamer passes a same-seed comparison perfectly.
	"""
	var a := _detached_terrain(terrain_script, RUN_SEED)
	var b := _detached_terrain(terrain_script, SECOND_SEED)

	# One chunk of each kind the city builds: a giant's slice, the gate district,
	# and a plateau ramp. A signature taken from one of them would be blind to the
	# other two entirely.
	var probes: Array[Vector2i] = [
		a.world_to_chunk(Vector3(2760.0, 0.0, -480.0)),   # the Parliament's centre
		a.world_to_chunk(Vector3(1690.0, 0.0, -26.0)),    # the gate district
		a.world_to_chunk(Vector3(1900.0, 0.0, -460.0)),   # Castle Hill's ramp
		# ...and a DENSE PEST BLOCK (bead .9). The block streamer carries a
		# per-cell RNG of its own, which is the newest place a run seed could
		# leak into an authored city — and the three probes above would never
		# see it, because not one of them fills a block.
		a.world_to_chunk(_dense_pest_chunk_probe()),
	]

	var boxes := 0
	for chunk_pos: Vector2i in probes:
		var sig_a := _city_signature(a, chunk_pos)
		var sig_b := _city_signature(b, chunk_pos)
		boxes += (sig_a[0] as Array).size()
		if var_to_bytes(sig_a) != var_to_bytes(sig_b):
			_fail("city chunk %s came out DIFFERENT under two run seeds (%d/%d "
					% [chunk_pos, (sig_a[0] as Array).size(), (sig_b[0] as Array).size()]
					+ "boxes, %d/%d shapes) — something seeded reached the "
					% [(sig_a[1] as Array).size(), (sig_b[1] as Array).size()]
					+ "streamer, and Budapest is supposed to be the same city every run")
	if boxes < 1:
		_fail("the regeneration probes built no boxes at all — check 3 compared "
				+ "two empty signatures and proved nothing")

	print("regeneration: %d chunks / %d boxes identical across run seeds %d and %d"
			% [probes.size(), boxes, RUN_SEED, SECOND_SEED])
	a.free()
	b.free()


func _dense_pest_chunk_probe() -> Vector3:
	"""
	A world point inside a block Pest actually FILLS — the first buildable cell
	east of the Danube, scanned rather than typed, so a plan edit that moved the
	river or a landmark cannot leave this probe pointing at an empty field and
	quietly turn check 3's fourth signature into a comparison of two zeroes.
	"""
	for k in range(BudapestPlan.CITY_AVENUE_EVERY * 4, 34):
		for m in range(-8, 9):
			var cell := Vector2i(k, m)
			if not BudapestPlan.block_buildable(cell):
				continue
			var c := BudapestPlan.block_rect(cell).get_center()
			if not BudapestPlan.is_buda(c.x, c.y):
				return Vector3(c.x, 0.0, c.y)
	_fail("no buildable Pest block was found anywhere east of the Danube — the "
			+ "city the owner asked to fill is empty")
	return Vector3(2900.0, 0.0, 100.0)


func _city_signature(terrain: Node3D, chunk_pos: Vector2i) -> Array:
	"""[every batch entry, every collision shape transform] for one city chunk."""
	var built := _build_city_chunk(terrain, chunk_pos)
	var body: StaticBody3D = built["body"]
	var shapes: Array = []
	for child in body.get_children():
		shapes.append((child as CollisionShape3D).transform)
	var out: Array = [built["batch"], shapes]
	body.free()
	(built["parent"] as Node).free()
	return out


# ============================================================================
# CHECK 4 — a city chunk is an ORDINARY chunk
# ============================================================================

func _check_budgets(terrain: Node3D, terrain_script: GDScript) -> void:
	"""
	Every chunk in the 2.2 km rect, measured against the three ceilings the
	streamer declares — and against the one-draw-call invariant.

	The worst chunk and its coordinates are printed beside each ceiling, so the
	budgets can be retuned from a measurement rather than from a guess (which is
	how they were set: see CITY_CHUNK_BOX_BUDGET in endless_terrain.gd).

	THE ONE MultiMesh IS THE INVARIANT THE OTHERS SERVE. Boxes are cheap because
	they are instances in one mesh; the moment the city hangs a MeshInstance3D of
	its own on a chunk, the box count stops meaning anything.
	"""
	var consts := terrain_script.get_script_constant_map()
	var box_budget: int = consts["CITY_CHUNK_BOX_BUDGET"]
	var shape_budget: int = consts["CITY_CHUNK_SHAPE_BUDGET"]
	var ms_budget: float = consts["CITY_CHUNK_MS_BUDGET"]

	var worst_boxes := 0
	var worst_boxes_at := Vector2i.ZERO
	var worst_shapes := 0
	var worst_shapes_at := Vector2i.ZERO
	var worst_ms := 0.0
	var worst_ms_at := Vector2i.ZERO
	var worst_accents := 0
	var worst_accents_at := Vector2i.ZERO
	var built_chunks := 0
	var total_boxes := 0
	# Per-chunk tallies, kept for the WEB RESIDENCY window below — which is a
	# statement about 49 chunks at once and cannot be made one chunk at a time.
	var boxes_at: Dictionary = {}
	var shapes_at: Dictionary = {}

	for chunk_pos: Vector2i in _rect_chunks(terrain):
		var built := _build_city_chunk(terrain, chunk_pos)
		var parent: MeshInstance3D = built["parent"]
		var batch: Array = built["batch"]
		var body: StaticBody3D = built["body"]

		boxes_at[chunk_pos] = batch.size()
		shapes_at[chunk_pos] = body.get_child_count()
		if batch.size() > worst_boxes:
			worst_boxes = batch.size()
			worst_boxes_at = chunk_pos
		if body.get_child_count() > worst_shapes:
			worst_shapes = body.get_child_count()
			worst_shapes_at = chunk_pos
		if float(built["msec"]) > worst_ms:
			worst_ms = built["msec"]
			worst_ms_at = chunk_pos

		if not batch.is_empty():
			built_chunks += 1
			total_boxes += batch.size()
			# THE INVARIANT, AND IT IS MEASURED BEFORE THE BATCH'S OWN MultiMesh IS
			# BUILT. Counting "BlockMultiMesh" nodes AFTER calling
			# _build_block_multimesh asks nothing: that function constructs exactly
			# one and names it, so the count is 1 for every implementation whatever,
			# including a city that also hung a MeshInstance3D per box. What the
			# streamer left on the chunk BEFORE the batch is built is the real
			# question — every one of those nodes is a draw call the city added on
			# top of its one batch.
			#
			# ACCENTS ARE THE SANCTIONED EXCEPTION and the only one: an emissive box
			# cannot join a batch whose one shared material is matte (see
			# _spawn_artifact_accent). So they are counted against a budget rather
			# than banned, and anything that is not one — above all a
			# MultiMeshInstance3D, which is a builder that grew a batch of its own —
			# fails outright.
			for child in parent.get_children():
				var mi := child as MeshInstance3D
				if mi == null or child is MultiMeshInstance3D or mi.material_override == null:
					_fail("city chunk %s hangs a %s ('%s') on the chunk — the "
							% [chunk_pos, child.get_class(), child.name]
							+ "city's stone has left the chunk's one batched draw call")
					break
			if parent.get_child_count() > CITY_CHUNK_ACCENT_BUDGET:
				_fail("city chunk %s hangs %d emissive accents, over %d — each one "
						% [chunk_pos, parent.get_child_count(), CITY_CHUNK_ACCENT_BUDGET]
						+ "is its own draw call, so the box budget beside it stops "
						+ "meaning anything")
			if parent.get_child_count() > worst_accents:
				worst_accents = parent.get_child_count()
				worst_accents_at = chunk_pos
			# ...and then the chunk's ONE draw call, built exactly the way
			# create_chunk builds it.
			terrain._build_block_multimesh(parent, batch)

		body.free()
		parent.free()

	if worst_boxes > box_budget:
		_fail("city chunk %s emits %d boxes, over CITY_CHUNK_BOX_BUDGET %d — a "
				% [worst_boxes_at, worst_boxes, box_budget]
				+ "landmark builder has stopped emitting only its own slice")
	if worst_shapes > shape_budget:
		_fail("city chunk %s hangs %d collision shapes on its one body, over "
				% [worst_shapes_at, worst_shapes]
				+ "CITY_CHUNK_SHAPE_BUDGET %d" % shape_budget)
	# WALL-CLOCK GETS A SECOND OPINION, and only when it has already accused
	# somebody. CITY_CHUNK_MS_BUDGET is a RUNAWAY DETECTOR on whatever machine CI
	# happens to be — its own comment says so — and CI runs every self-check in
	# this repo back to back: a chunk that reads 1.2 ms on an idle machine has been
	# measured at 15.8 under that load, which is the scheduler and not the
	# streamer. So the accused chunk is rebuilt and the BEST reading is the
	# verdict. A genuine runaway is slow every time; a hiccup is not, and a check
	# that fails on machine load is a check people learn to re-run.
	var settled_ms := worst_ms
	if worst_ms > ms_budget:
		for _try in MS_REMEASURES:
			var again := _build_city_chunk(terrain, worst_ms_at)
			settled_ms = minf(settled_ms, float(again["msec"]))
			(again["body"] as Node).free()
			(again["parent"] as Node).free()
		if settled_ms > ms_budget:
			_fail("city chunk %s took %.2f ms to build (best of %d), over "
					% [worst_ms_at, settled_ms, MS_REMEASURES + 1]
					+ "CITY_CHUNK_MS_BUDGET %.1f — it is one chunk of the "
					% ms_budget + "one-per-frame drain, like a chunk of cactus")
	if built_chunks < 1:
		_fail("no chunk in the city rect built anything at all — check 4 measured "
				+ "an empty city against three ceilings")

	print("budgets over %d city chunks (%d of them with stone, %d boxes total):"
			% [_rect_chunks(terrain).size(), built_chunks, total_boxes])
	print("  boxes  worst %d at %s (budget %d)" % [worst_boxes, worst_boxes_at, box_budget])
	print("  shapes worst %d at %s (budget %d)" % [worst_shapes, worst_shapes_at, shape_budget])
	print("  build  worst %.2f ms at %s (settled %.2f, budget %.1f)"
			% [worst_ms, worst_ms_at, settled_ms, ms_budget])
	print("  accents worst %d at %s (budget %d) — everything else the city draws "
			% [worst_accents, worst_accents_at, CITY_CHUNK_ACCENT_BUDGET]
			+ "is in the chunk's one batch")

	_check_web_residency(boxes_at, shapes_at)


func _check_web_residency(boxes_at: Dictionary, shapes_at: Dictionary) -> void:
	"""
	THE WEB RESIDENCY PROOF: what the whole VIEW costs, not what one chunk costs.

	@param boxes_at, shapes_at: every city chunk's tallies, from check 4's sweep.

	The per-chunk budgets above are a statement about ONE frame of the
	one-chunk-per-frame drain. They say nothing at all about what is on screen,
	and since bead .9 filled every block that is the number that moved: the city
	went from 378 chunks with stone to ~1630, so a per-chunk ceiling that was
	never approached can stay exactly where it is while the RESIDENT set behind it
	quadruples.

	WEB_RENDER_DISTANCE is 3, so the web build holds a 7 x 7 = 49-chunk square
	around the player, each an instance in its own MultiMesh and a shape on its
	own body. This walks every such window that fits in the city rect and takes
	the worst — which is the densest thing a web player can ever be standing in
	the middle of. Both ceilings are MEASURED, printed beside the reading, and
	deliberately generous: they are here to catch a change of ORDER (a builder
	that stopped slicing, a block table that stopped excluding), not to be tuned.
	"""
	var side := 2 * WEB_RENDER_DISTANCE + 1
	var worst_boxes := 0
	var worst_shapes := 0
	var worst_at := Vector2i.ZERO
	for origin_v: Variant in boxes_at.keys():
		var origin: Vector2i = origin_v
		var boxes := 0
		var shapes := 0
		for dx in side:
			for dz in side:
				var at := origin + Vector2i(dx, dz)
				boxes += int(boxes_at.get(at, 0))
				shapes += int(shapes_at.get(at, 0))
		if boxes > worst_boxes:
			worst_boxes = boxes
			worst_shapes = shapes
			worst_at = origin
	if worst_boxes > CITY_RESIDENCY_BOX_BUDGET:
		_fail("the worst %d-chunk web window (at %s) holds %d boxes, over "
				% [side * side, worst_at, worst_boxes]
				+ "CITY_RESIDENCY_BOX_BUDGET %d — the per-chunk budget passed "
				% CITY_RESIDENCY_BOX_BUDGET
				+ "because the cost moved into the number of chunks, not into one")
	if worst_shapes > CITY_RESIDENCY_SHAPE_BUDGET:
		_fail("the worst %d-chunk web window (at %s) hangs %d collision shapes, "
				% [side * side, worst_at, worst_shapes]
				+ "over CITY_RESIDENCY_SHAPE_BUDGET %d" % CITY_RESIDENCY_SHAPE_BUDGET)
	print("  web residency: worst %d-chunk window at %s holds %d boxes (budget "
			% [side * side, worst_at, worst_boxes]
			+ "%d) and %d shapes (budget %d)"
			% [CITY_RESIDENCY_BOX_BUDGET, worst_shapes, CITY_RESIDENCY_SHAPE_BUDGET])


# ============================================================================
# CHECK 5 — the slicing decision, asserted
# ============================================================================

func _check_slicing(terrain: Node3D) -> void:
	"""
	THE KEYSTONE DECISION, MEASURED. For the two biggest buildings in the city:
	every box the unclipped builder emits is kept by EXACTLY ONE chunk, with the
	SAME colour it was built with, and the accent node exists exactly once.

	HOW IT IS COMPARED, and why not by world position. The builder is a pure
	function of (centre, rng), so re-running it rebased to a chunk produces the
	same list in the same ORDER, bit for bit, as the streamer's own run for that
	chunk. So this walks indexes: for each overlapping chunk, run the builder the
	way the streamer does, then find which of its entries came back in the
	streamer's output by exact byte equality. Comparing world positions instead
	would be comparing f32 rebasing noise, and would need a tolerance where the
	property is exact.

	A box kept twice is two z-fighting walls in one metre. A box kept by nobody is
	a hole. A box whose colour differs between slices is the Parliament tie-dyed
	along its chunk seams — the failure the per-slot seed exists to prevent, and
	the one no single-chunk check could ever see.
	"""
	# ONE PREDICATE, BOTH HALVES — asserted directly, because the slicing walk
	# below cannot see it. `create_box` hands the batch entry
	# `rot.scaled_local(dimensions)` and the shape node the bare `rot`, so a test
	# against an ABSOLUTE epsilon answers differently for the same box the bigger
	# it is: Basis(UP, PI) is fp32 and leaves an 8.7e-8 off-diagonal, which a 272 m
	# plinth scales to 2.4e-5 — over is_zero_approx's 1e-5, under it bare. That is
	# a drawn wall homed in one chunk and its collision cut across six. Nothing
	# ships a yawed giant today, which is exactly why it is measured here rather
	# than found later.
	var yawed := Basis(Vector3.UP, PI)
	for dim: Vector3 in [Vector3(1.0, 1.0, 1.0), Vector3(125.0, 3.0, 272.0)]:
		if not terrain._is_axis_aligned_basis(yawed.scaled_local(dim)):
			_fail("a PI-yawed %.0f x %.0f box reads as ROTATED to the splitter "
					% [dim.x, dim.z] + "while its own collision basis reads as "
					+ "axis-aligned — the two halves are testing different things")
	if terrain._is_axis_aligned_basis(Basis(Vector3.UP, PI * 0.25)):
		_fail("a 45-degree yaw reads as axis-aligned — the splitter would cut a "
				+ "rotated box into pieces that do not reassemble")

	for id: String in ["parliament", "buda_castle"]:
		var index := _slot_index(id)
		if index < 0:
			_fail("check 5 asked for slot '%s', which is not in BudapestPlan.SLOTS" % id)
			continue
		var slot: Dictionary = BudapestPlan.SLOTS[index]
		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]
		var builder := String(slot["builder"])

		# The unclipped build, once, for the box and accent COUNTS this slot owes.
		var whole := _run_builder(terrain, index, Vector3(pos.x, pos.y, pos.z), Vector3.ZERO)
		var total: int = (whole["batch"] as Array).size()
		var shape_total: int = _shape_keys(whole["body"]).size()
		var whole_accents: int = (whole["accents"] as int)
		_free_builder(whole)

		# Every chunk whose square meets the disc.
		var lo: Vector2i = terrain.world_to_chunk(Vector3(pos.x - radius, 0.0, pos.z - radius))
		var hi: Vector2i = terrain.world_to_chunk(Vector3(pos.x + radius, 0.0, pos.z + radius))
		var claimed := {}          # index in the builder's output -> how many chunks kept it
		var shape_claimed := {}    # ...and the same tally for its COLLISION shapes
		var accents := 0
		var chunks := 0
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var chunk_pos := Vector2i(cx, cz)
				var centre: Vector3 = terrain.chunk_to_world(chunk_pos)

				# The same builder run the streamer is about to make, in the same
				# frame, so its entries are byte-comparable with what comes back.
				var rebased := _run_builder(terrain, index,
						Vector3(pos.x - centre.x, pos.y, pos.z - centre.z), centre)
				var by_bytes := {}
				var rebased_batch: Array = rebased["batch"]
				for i in range(rebased_batch.size()):
					by_bytes[var_to_bytes(rebased_batch[i])] = i
				# THE COLLISION HALF, and it needs its own map because the two lists
				# are different lengths: every `collide = false` box (domes, spires,
				# cornices — these builders are full of them) is in the batch and not
				# in the body, which is why neither the clip nor the splitter pairs
				# them by index. Without this tally the clip's and the splitter's
				# collision halves are both entirely unmeasured, and a hole you fall
				# through prints SELFCHECK OK.
				var by_shape := {}
				var rebased_shapes: Array = _shape_keys(rebased["body"])
				for i in range(rebased_shapes.size()):
					by_shape[rebased_shapes[i]] = i
				# THE ACCENT HALF, and it needs the same byte map for the same
				# reason the other two do: the streamer builds EVERY slot reaching
				# the chunk, so a bare `parent.get_child_count()` also tallies the
				# accents of any other accent-bearing slot whose centre lands in
				# this rect — it would fail rule 4 for a city that is correct, or
				# hide a doubled beacon behind a slot that emits one fewer.
				# Reparenting preserves the local transform and both nodes share
				# the chunk's frame, so the match is exact.
				var by_accent := {}
				for child in (rebased["chunk"] as Node).get_children():
					by_accent[var_to_bytes((child as Node3D).transform)] = true
				_free_builder(rebased)

				# ...and the streamer's own output for that chunk. It carries every
				# slot that reaches the chunk; only this slot's entries can match.
				var parent := MeshInstance3D.new()
				parent.position = centre
				root.add_child(parent)
				var batch: Array = []
				var body := StaticBody3D.new()
				var obstacles: Array = []
				terrain._spawn_city_landmarks_in_chunk(centre, parent, obstacles, batch, body)
				var kept := 0
				for entry_v: Variant in batch:
					var key := var_to_bytes(entry_v)
					if not by_bytes.has(key):
						continue
					var i: int = by_bytes[key]
					claimed[i] = int(claimed.get(i, 0)) + 1
					kept += 1
				for key_v: Variant in _shape_keys(body):
					if not by_shape.has(key_v):
						continue
					var si: int = by_shape[key_v]
					shape_claimed[si] = int(shape_claimed.get(si, 0)) + 1
					kept += 1
				if kept > 0:
					chunks += 1
				for child in parent.get_children():
					if by_accent.has(var_to_bytes((child as Node3D).transform)):
						accents += 1
				body.free()
				parent.free()

		var doubled := 0
		for i_v: Variant in claimed:
			if int(claimed[i_v]) > 1:
				doubled += 1
		var lost := total - claimed.size()

		if lost != 0 or doubled != 0:
			_fail("'%s': of %d boxes the builder emits, %d were kept by no chunk "
					% [id, total, lost] + "and %d by more than one — the half-open "
					% doubled + "clip has a hole or an overlap in it")

		var shape_doubled := 0
		for i_v: Variant in shape_claimed:
			if int(shape_claimed[i_v]) > 1:
				shape_doubled += 1
		var shape_lost := shape_total - shape_claimed.size()
		if shape_lost != 0 or shape_doubled != 0:
			_fail("'%s': of %d COLLISION shapes the builder emits, %d were kept by "
					% [id, shape_total, shape_lost] + "no chunk and %d by more than "
					% shape_doubled + "one — the drawn stone and the stone you walk "
					+ "into are not in the same chunks (the clip or the splitter "
					+ "treats the two halves differently)")
		# The accent count is the whole of rule 4: ten of these builders hang a
		# glowing mesh on their chunk, and under slicing that would be one beacon
		# per overlapping chunk.
		if accents != whole_accents:
			_fail("'%s' put %d accent nodes on its %d chunks, but one unclipped "
					% [id, accents, chunks] + "build emits %d — an accent is "
					% whole_accents + "supposed to exist exactly once, on the chunk "
					+ "holding the slot's centre")

		print("slicing '%s': %d boxes and %d collision shapes over %d chunks, each "
				% [id, total, shape_total, chunks] + "kept exactly once, "
				+ "%d accent(s) total" % accents)

	_check_no_box_outgrows_a_chunk(terrain)


func _check_no_box_outgrows_a_chunk(terrain: Node3D) -> void:
	"""
	THE OTHER HALF OF THE KEYSTONE, and the one the "kept exactly once" tally is
	blind to: a box KEPT ONCE but BIGGER THAN THE CHUNK THAT KEPT IT.

	The centre rule slices a LANDMARK, not a BOX. Buda Castle's terrace is a single
	70 x 300 box and a chunk is 50 m, so before rule 2a the whole palace lived in
	one chunk and unloaded with it — on the web build (render_distance 3, a 150 m
	Chebyshev square) that is the building disappearing while you stand on its far
	end, 11 m from stone you can see. Every existing assertion passed through it:
	check 4 counts boxes, check 5 counts how many chunks kept each one, and a box
	of any size satisfies both.

	So: run EVERY slot's builder through the streamer's own splitter and fail any
	surviving box whose own W x D outgrows a chunk.

	MEASURED ON THE BOX'S OWN DIMENSIONS, NOT ITS WORLD AABB, and that is the whole
	subtlety. An axis-aligned box's dimensions ARE its world footprint, so for
	everything the splitter cuts the two are the same test. A ROTATED box is the one
	case the splitter deliberately skips — a turned box has no representation as
	axis-aligned pieces — so it keeps the centre rule, and the question is how far
	it can then reach past its own cell. A box whose own dimensions fit a chunk
	reaches at most sqrt(2)/2 of a chunk from its centre instead of 1/2, i.e. 0.21
	of a chunk further than an aligned one (the Parliament's dome drum, 36 x 36 at
	45 degrees, is the only box in the city that spends any of it). That is a
	chunk-sized pop at the residency edge, which is what every prop in the game
	already is; a 300 m palace vanishing is not.
	"""
	var worst := 0.0
	var worst_id := ""
	for index in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[index]
		if String(slot["builder"]).is_empty():
			continue
		var pos: Vector3 = slot["pos"]
		var built := _run_builder(terrain, index, pos, Vector3.ZERO)
		# The collision half, on the same bound. A shape wider than a chunk unloads
		# with the chunk holding its centre exactly like a mesh does — you then walk
		# through the far end of a building you can still see.
		for child in (built["body"] as StaticBody3D).get_children():
			var cs := child as CollisionShape3D
			if cs == null:
				continue
			var sbox := cs.shape as BoxShape3D
			if sbox == null:
				continue
			var sb := cs.transform.basis
			var sw := sbox.size.x * sb.x.length()
			var sd := sbox.size.z * sb.z.length()
			if maxf(sw, sd) > terrain.chunk_size:
				_fail("'%s' hangs a %.1f x %.1f m COLLISION shape, bigger than the "
						% [slot["id"], sw, sd] + "%.0f m chunk that would keep it "
						% terrain.chunk_size + "whole — the splitter cut the mesh "
						+ "and not the body")
		for entry_v: Variant in (built["batch"] as Array):
			var b: Basis = (entry_v as Dictionary)["transform"].basis
			# create_box builds the basis as rot.scaled_local(dimensions), so a
			# column's LENGTH is that dimension whatever the rotation is.
			var w := b.x.length()
			var d := b.z.length()
			var big := maxf(w, d)
			if big > worst:
				worst = big
				worst_id = String(slot["id"])
			if big > terrain.chunk_size:
				_fail("'%s' emits a %.1f x %.1f m box, bigger than the %.0f m "
						% [slot["id"], w, d, terrain.chunk_size] + "chunk that "
						+ "would keep it whole — it unloads while you are standing "
						+ "on it (rule 2a stopped cutting, or a ROTATED box outgrew "
						+ "the one case the splitter skips)")
		_free_builder(built)

	print("no box outgrows a chunk: worst %.1f m ('%s') against a %.0f m chunk"
			% [worst, worst_id, terrain.chunk_size])


func _shape_keys(body_v: Variant) -> Array:
	"""
	A body's box shapes as comparable BYTES — one entry per CollisionShape3D,
	`[transform, size]`, in tree order. The collision-side twin of
	var_to_bytes(batch_entry), and the thing that lets check 5 tally the half it
	used to be blind to.
	"""
	var out: Array = []
	for child in (body_v as StaticBody3D).get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		out.append(var_to_bytes([cs.transform, box.size]))
	return out


func _run_builder(terrain: Node3D, index: int, center: Vector3, chunk_center: Vector3) -> Dictionary:
	"""
	One landmark builder, run exactly the way _spawn_city_landmarks_in_chunk runs
	it: the SEED is the slot index and the plan's salt, and nothing else, and the
	output is then cut on the world chunk grid by the streamer's OWN splitter (rule
	2a — never a restatement of it here). THE CALLER PASSES THE RESULT TO
	_free_builder.

	@param center: The builder's centre, in the frame `chunk_center` names.
	@param chunk_center: The world centre of the chunk that frame belongs to; pass
	                     Vector3.ZERO to work directly in world space.
	"""
	var slot: Dictionary = BudapestPlan.SLOTS[index]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(index, BudapestPlan.CITY_LANDMARK_SALT, 0))
	var chunk := MeshInstance3D.new()
	var batch: Array = []
	var body := StaticBody3D.new()
	terrain._landmark_builders.call(String(slot["builder"]), terrain, center, rng,
			chunk, batch, body)
	terrain.split_city_boxes_on_chunk_grid(chunk_center, batch, body)
	return {"batch": batch, "body": body, "chunk": chunk,
			"accents": chunk.get_child_count()}


func _free_builder(built: Dictionary) -> void:
	(built["body"] as Node).free()
	(built["chunk"] as Node).free()


# ============================================================================
# CHECK 6 — CPU/GPU parity: the band you see is the band you wade
# ============================================================================

func _check_parity(terrain: Node3D) -> void:
	"""
	Both halves of the two-language contract, each measured in its own language.

	CPU: biome_at() and is_river_at(), which is what the player FEELS — the paved
	band and the wade penalty. GPU: the shader read as TEXT, because a uniform
	that stopped being declared (or an array one row too short) is a silent
	truncation — the river simply loses its last bend and the ground stays
	painted, which nothing anywhere would report.
	"""
	# ---- CPU: the forced CITY band ------------------------------------------
	var city: int = terrain.Biome.CITY
	var forced := 0
	for i in range(200):
		# A deterministic lattice over the rect rather than a random sample: a
		# check that changes what it measures between runs is a check that fails
		# on somebody else's machine.
		var fx := float(i % 20) / 19.0
		var fz := float(i / 20) / 9.0
		var x := lerpf(BudapestPlan.BUDAPEST_MIN.x + 1.0, BudapestPlan.BUDAPEST_MAX.x - 1.0, fx)
		var z := lerpf(BudapestPlan.BUDAPEST_MIN.y + 1.0, BudapestPlan.BUDAPEST_MAX.y - 1.0, fz)
		if terrain.biome_at(x, z) == city:
			forced += 1
	if forced != 200:
		_fail("only %d of 200 points inside the city rect answered CITY — the "
				% forced + "biome override is not total, so Pest has patches of "
				+ "desert and forest in it")

	# The negative control: ONE METRE outside the rect the override must not
	# apply. The noise field is free to answer CITY there on its own, so the
	# statement is that not every point does — a forcing clause that had crept
	# outside the rect would make all of them.
	var outside_city := 0
	var outside_total := 0
	for i in range(200):
		var f := float(i) / 199.0
		var x := lerpf(BudapestPlan.BUDAPEST_MIN.x, BudapestPlan.BUDAPEST_MAX.x, f)
		var z := BudapestPlan.BUDAPEST_MIN.y - 1.0
		outside_total += 1
		if terrain.biome_at(x, z) == city:
			outside_city += 1
		x = BudapestPlan.BUDAPEST_MAX.x + 1.0
		z = lerpf(BudapestPlan.BUDAPEST_MIN.y, BudapestPlan.BUDAPEST_MAX.y, f)
		outside_total += 1
		if terrain.biome_at(x, z) == city:
			outside_city += 1
	if outside_city >= outside_total:
		_fail("every one of %d points ONE METRE outside the city rect answered "
				% outside_total + "CITY too — the override is not bounded by the rect")

	# ---- CPU: the Danube -----------------------------------------------------
	var wet := 0
	for i in range(BudapestPlan.DANUBE.size()):
		var v: Vector2 = BudapestPlan.DANUBE[i]
		if terrain.is_river_at(Vector3(v.x, 0.0, v.y)):
			wet += 1
		else:
			_fail("the Danube's polyline vertex %d (%.0f, %.0f) is not wet — the "
					% [i, v.x, v.y] + "river you see is not the river you wade")
		if i + 1 < BudapestPlan.DANUBE.size():
			var w: Vector2 = BudapestPlan.DANUBE[i + 1]
			var mid := (v + w) * 0.5
			if terrain.is_river_at(Vector3(mid.x, 0.0, mid.y)):
				wet += 1
			elif not BudapestPlan.is_dry(mid.x, mid.y):
				# A midpoint standing on a DRY_RECTS row is dry on purpose — the
				# 0-1 midpoint is Margaret Island, which is the mechanism working
				# and not the river failing. Anything else mid-channel is a hole
				# in the band.
				_fail("the Danube is dry midway between vertices %d and %d, and "
						% [i, i + 1] + "not on any dry rect — the band has a hole in it")
		# ...and 200 m beyond the band on both sides, which is the bank.
		for side in [-1.0, 1.0]:
			var off: float = v.x + side * (BudapestPlan.DANUBE_HALF_WIDTH + 200.0)
			if terrain.is_river_at(Vector3(off, 0.0, v.y)):
				_fail("the river is wet %.0f m off its own centreline at z = %.0f"
						% [BudapestPlan.DANUBE_HALF_WIDTH + 200.0, v.y])

	# Every dry rect, at its centre and all four corners: a bridge deck and
	# Margaret Island are the same question asked of is_river_at.
	var dry_points := 0
	for rect_v: Variant in BudapestPlan.DRY_RECTS:
		var r: Rect2 = rect_v
		var points: Array[Vector2] = [r.get_center(), r.position,
				Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]
		for p: Vector2 in points:
			dry_points += 1
			if terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
				_fail("dry rect at (%.0f, %.0f) is WET at (%.0f, %.0f) — a bridge "
						% [r.position.x, r.position.y, p.x, p.y]
						+ "deck you wade across is not a bridge")

	# AND THE TOWER'S DISC IS STILL DRY — the city grew is_river_at() a second
	# early return and this is the one thing already standing under the first.
	#
	# WHAT THIS DOES NOT MEASURE, deliberately stated rather than claimed: the
	# ORDER of the two clauses. tower_site() is the constant (-400, 0, 0) and the
	# city rect starts at x = 1600, so the two regions are disjoint and swapping
	# them answers identically at every point in the world. There is nothing here
	# to assert; if the HQ ever moves inside the rect, THAT is when the order
	# becomes a rule and this probe starts being able to see it.
	var site: Vector3 = terrain.tower_site()
	for angle in range(8):
		var a := TAU * float(angle) / 8.0
		var p: Vector3 = site + Vector3(cos(a), 0.0, sin(a)) * (terrain.TOWER_RADIUS * 0.5)
		if terrain.is_river_at(p):
			_fail("the GastroDefense HQ's disc answers WET at (%.0f, %.0f) — the "
					% [p.x, p.z] + "tower's mask has stopped masking")

	# ---- GPU: the shader, as text -------------------------------------------
	var shader := FileAccess.get_file_as_string(SHADER_PATH)
	if shader.is_empty():
		_fail("could not read %s — the GPU half of check 6 measured nothing" % SHADER_PATH)
		return
	var terrain_text := FileAccess.get_file_as_string(TERRAIN_PATH)
	var uniforms: Array[String] = ["city_rect", "city_river", "city_river_count",
			"city_river_half", "city_dry", "city_dry_count"]
	# MATCHED AS A DECLARATION, not as a substring. `shader.contains(name)` is
	# satisfied by the prose above the uniform block (which names city_rect and
	# city_dry) and by a longer sibling (`city_river` is inside `city_river_half`,
	# `city_river_count`, `v_city_river` and `city_river_distance`) — so deleting
	# the declaration outright left the old test green.
	var decl := RegEx.new()
	for name: String in uniforms:
		decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+%s\\s*(\\[|=|;)" % name)
		if decl.search(shader) == null:
			_fail("ground.gdshader declares no '%s' — the GPU is drawing a river "
					% name + "the CPU is not wading")
		if not terrain_text.contains("set_shader_parameter(\"%s\"" % name):
			_fail("endless_terrain.gd never pushes '%s' to the ground shader — "
					% name + "the uniform is declared and left at its inert default")

	var seg_max := _shader_int(shader, "CITY_SEG_MAX")
	var dry_max := _shader_int(shader, "CITY_DRY_MAX")
	if seg_max < BudapestPlan.DANUBE.size() - 1:
		_fail("the plan's Danube has %d segments but ground.gdshader's "
				% (BudapestPlan.DANUBE.size() - 1) + "CITY_SEG_MAX is %d — the "
				% seg_max + "river would silently lose its last bend on the GPU")
	if dry_max < BudapestPlan.DRY_RECTS.size():
		_fail("the plan has %d dry rects but ground.gdshader's CITY_DRY_MAX is "
				% BudapestPlan.DRY_RECTS.size() + "%d — a bridge deck would be "
				% dry_max + "painted as water")

	print("parity: 200/200 points CITY inside the rect (%d/%d one metre outside), "
			% [outside_city, outside_total]
			+ "%d wet river samples, %d dry-rect points, shader arrays %d/%d >= %d/%d"
			% [wet, dry_points, seg_max, dry_max,
					BudapestPlan.DANUBE.size() - 1, BudapestPlan.DRY_RECTS.size()])

	_check_parity_packing(terrain, shader)


func _check_parity_packing(terrain: Node3D, shader: String) -> void:
	"""
	THE HALF A TEXT SCAN CANNOT REACH: whether the numbers pushed into the shader's
	array uniforms are PACKED the way the shader unpacks them.

	The scan above proves each uniform is declared and pushed. It cannot see that
	ground.gdshader reads city_dry[i] as (xmin, zmin, xmax, zmax) while DRY_RECTS
	is stored as Rect2(position, SIZE) — one plausible line in _city_dry_rects,

	    rects[i] = Vector4(r.position.x, r.position.y, r.size.x, r.size.y)

	turns the Chain Bridge's test into `x >= 2330 && x <= 290`, never true, and
	every bridge deck and Margaret Island are painted as open water while
	is_river_at keeps them dry. That is exactly the "the blue you see is not the
	water you wade" failure check 6 exists for, and nothing else in this file sees
	it.

	So: run the SHADER'S OWN predicate here, in GDScript, driven off the values
	read back OFF THE MATERIAL (not off BudapestPlan — reading the plan again would
	just re-derive the packing this is trying to test), and compare it to
	is_river_at over a lattice across the rect plus the corners and centre of every
	dry rect. Samples within CITY_RIVER_EDGE_SOFT of the band edge are skipped:
	that edge is a smoothstep on the GPU and a hard `<` on the CPU, which is the
	one place the two are deliberately allowed to differ.
	"""
	# _ready() returns at its "no player" guard long before it builds the default
	# ground material, so the harness stands one up the same way _ready does. The
	# PUSH is still the shipped one — _apply_biome_shader_params below is the only
	# thing that writes a uniform, here and in the game.
	if terrain.terrain_material == null:
		var ground := ShaderMaterial.new()
		ground.shader = load(SHADER_PATH)
		terrain.terrain_material = ground
	terrain._apply_biome_shader_params()
	var mat := terrain.terrain_material as ShaderMaterial
	if mat == null:
		_fail("the terrain's material is not a ShaderMaterial — check 6 could not "
				+ "read back a single pushed uniform")
		return

	var rect: Vector4 = mat.get_shader_parameter("city_rect")
	var segs: PackedVector4Array = mat.get_shader_parameter("city_river")
	var seg_count: int = mat.get_shader_parameter("city_river_count")
	var half: float = mat.get_shader_parameter("city_river_half")
	var dry: PackedVector4Array = mat.get_shader_parameter("city_dry")
	var dry_count: int = mat.get_shader_parameter("city_dry_count")
	# `CITY_RIVER_EDGE_SOFT` is a `const float`, so _shader_int's is_valid_int()
	# can never parse it — read it with the float parser and FAIL if it is gone,
	# rather than substituting a literal that quietly stops tracking the shader.
	var soft := _shader_float(shader, "CITY_RIVER_EDGE_SOFT")
	if soft <= 0.0:
		_fail("ground.gdshader declares no CITY_RIVER_EDGE_SOFT — check 6's "
				+ "smoothstep tolerance would be a number written down twice")
		return

	var points: Array[Vector2] = []
	var lo := BudapestPlan.BUDAPEST_MIN
	var span := BudapestPlan.BUDAPEST_MAX - lo
	for ix in range(61):
		for iz in range(61):
			points.append(lo + Vector2(span.x * float(ix) / 60.0, span.y * float(iz) / 60.0))
	# The dry rects are the whole point of the packing, so hit every corner and
	# centre of every one of them as well as the lattice.
	for r_v: Variant in BudapestPlan.DRY_RECTS:
		var r: Rect2 = r_v
		points.append(r.position + r.size * 0.5)
		for cx in [0.02, 0.98]:
			for cz in [0.02, 0.98]:
				points.append(r.position + Vector2(r.size.x * cx, r.size.y * cz))

	var disagreed := 0
	var checked := 0
	var gpu_dry_hits := 0
	for p: Vector2 in points:
		# in_city, verbatim from ground.gdshader's fragment().
		if not (rect.z >= rect.x and p.x >= rect.x and p.x <= rect.z
				and p.y >= rect.y and p.y <= rect.w):
			continue
		# city_river_distance(), verbatim: clamped point-to-segment, min over the
		# first city_river_count entries.
		var best := 1.0e9
		for i in range(seg_count):
			var a := Vector2(segs[i].x, segs[i].y)
			var b := Vector2(segs[i].z, segs[i].w)
			var ab := b - a
			var len_sq := ab.dot(ab)
			var t := 0.0 if len_sq <= 0.0 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t))
		if absf(best - half) <= soft:
			continue   # the smoothstep band: the two are allowed to differ here
		# The per-fragment dry mask, verbatim.
		var is_dry := false
		for i in range(dry_count):
			if p.x >= dry[i].x and p.x <= dry[i].z and p.y >= dry[i].y and p.y <= dry[i].w:
				is_dry = true
				break
		if is_dry:
			gpu_dry_hits += 1
		var gpu_wet := best < half and not is_dry
		checked += 1
		if gpu_wet != terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
			disagreed += 1
			if disagreed == 1:
				_fail("the ground shader's OWN predicate, run on the values pushed "
						+ "into its uniforms, says (%.0f, %.0f) is %s while "
						% [p.x, p.y, "WET" if gpu_wet else "DRY"]
						+ "is_river_at says the opposite — the city's array "
						+ "uniforms are packed in an order the shader does not "
						+ "unpack (city_dry is (xmin, zmin, xmax, zmax), NOT "
						+ "Rect2's position + size)")

	if gpu_dry_hits < BudapestPlan.DRY_RECTS.size():
		_fail("only %d sample landed on a dry rect out of %d rows — the packing "
				% [gpu_dry_hits, BudapestPlan.DRY_RECTS.size()] + "check walked "
				+ "past the bridges it exists to measure")

	print("  packing: %d in-city samples agree between the shader's predicate on "
			% checked + "its PUSHED uniforms and is_river_at (%d of them on a dry "
			% gpu_dry_hits + "rect), %d disagreements" % disagreed)


func _shader_int(shader: String, name: String) -> int:
	"""The value of a `const int NAME = n;` line in the shader, or -1."""
	for line in shader.split("\n"):
		if not line.contains(name) or not line.contains("="):
			continue
		var tail := line.split("=")[1].strip_edges().replace(";", "")
		if tail.is_valid_int():
			return tail.to_int()
	return -1


func _shader_float(shader: String, name: String) -> float:
	"""
	The value of a `const float NAME = n.n;` line in the shader, or -1.

	Its own function because is_valid_int() is FALSE for "2.0" — _shader_int
	fed a float constant returns -1 for every shader ever written, which is a
	parser that cannot fail and a caller that never notices.
	"""
	for line in shader.split("\n"):
		if not line.contains(name) or not line.contains("="):
			continue
		var tail := line.split("=")[1].strip_edges().replace(";", "")
		if tail.is_valid_float():
			return tail.to_float()
	return -1.0


# ============================================================================
# CHECK 7 — the approach corridor reaches the gate, for 50 seeds
# ============================================================================

func _check_approach_corridor(terrain_script: GDScript) -> void:
	"""
	THE ONE SEAM WHERE A SEEDED WORLD MEETS AN AUTHORED ONE, driven through fifty
	run seeds because the road's Z at the terminal is exactly what varies.

	Per seed: the terminal station lands within one station spacing of
	ROAD_TERMINAL_X; the corridor arrives at the gate; it is continuous, bounded
	by smoothstep's OWN maximum slope (1.5 * dz / span, which is arithmetic and
	not a tuning constant); and it JOINS TANGENTIALLY at both ends — the first
	step off the terminal and the last step into the gate are a fraction of the
	step in the middle, which is the whole reason the join is a smoothstep and not
	a straight line.
	"""
	var consts := terrain_script.get_script_constant_map()
	var terminal_x: float = consts["ROAD_TERMINAL_X"]

	var worst_offset := 0.0
	var worst_kink := 0.0
	var worst_gap := 0.0
	var measured := 0
	for s in range(APPROACH_SEEDS):
		var terrain := _detached_terrain(terrain_script, RUN_SEED + s * 977)
		var k: int = terrain._road_terminal_k()
		var spacing: float = terrain._road_spacing()
		var terminal: Vector2 = terrain._road_station(k).center
		var offset := absf(terminal.x - terminal_x)
		worst_offset = maxf(worst_offset, offset)
		if offset > spacing:
			_fail("seed %d: the terminal station stands %.1f m from "
					% [RUN_SEED + s * 977, offset] + "ROAD_TERMINAL_X, further "
					+ "than one station spacing (%.1f)" % spacing)

		var at_gate: Vector2 = BudapestPlan.road_approach_point(terminal, BudapestPlan.GATE.x)
		if absf(at_gate.x - BudapestPlan.GATE.x) > 0.001 or absf(at_gate.y - BudapestPlan.GATE.z) > 0.001:
			_fail("seed %d: the corridor arrives at (%.2f, %.2f) instead of the "
					% [RUN_SEED + s * 977, at_gate.x, at_gate.y]
					+ "gate (%.0f, %.0f)" % [BudapestPlan.GATE.x, BudapestPlan.GATE.z])

		# Continuity, against smoothstep's own analytic maximum derivative.
		var span := BudapestPlan.GATE.x - terminal.x
		var drop := absf(BudapestPlan.GATE.z - terminal.y)
		if span <= 0.0:
			_fail("seed %d: the terminal station is not west of the gate" % (RUN_SEED + s * 977))
			terrain.free()
			continue
		var bound := 1.5 * drop / span + 0.0005
		var step := 0.5
		var prev: Vector2 = BudapestPlan.road_approach_point(terminal, terminal.x)
		var first_step := -1.0
		var last_step := 0.0
		var max_step := 0.0
		var x := terminal.x + step
		while x <= BudapestPlan.GATE.x:
			var p: Vector2 = BudapestPlan.road_approach_point(terminal, x)
			var d := absf(p.y - prev.y) / step
			if d > bound:
				_fail("seed %d: the corridor turns at %.3f m/m at x = %.0f, over "
						% [RUN_SEED + s * 977, d, x] + "smoothstep's own bound of "
						+ "%.3f — it is not the join it claims to be" % bound)
				break
			if first_step < 0.0:
				first_step = d
			last_step = d
			max_step = maxf(max_step, d)
			prev = p
			x += step

		# THE CORRIDOR IS KEPT CLEAR. CAP 2 stops the road's clearance at T, so the
		# corridor has to answer the clearance question itself or the last 150 m
		# into the gate become ordinary procedural ground with a coin line through
		# it — a massif across it is non-climbable, and the trail simply stops.
		# Asked on the centreline from ROAD_TERMINAL_X east, which is exactly where
		# the cap bites: west of it the stations themselves answer, and the corridor
		# is at most a station spacing off them there.
		#
		#
		# PROBED OFF THE CENTRELINE, BOTH SIDES OF THE SWATH'S EDGE, and never ON
		# it: feeding _road_lateral_distance the point road_approach_point() just
		# returned makes it compute the distance from that point to ITSELF, which
		# is 0.0 for any implementation whatever and measures nothing. Offsetting
		# is what turns the leg into a measurement of the swath's WIDTH — a
		# clearance band with no edge suppresses every spawner across the whole
		# approach, and one that reads INF a metre out gives the walk no clearance
		# at all. (The centreline's own placement cannot be pinned here without
		# restating BudapestPlan.road_approach_point, so it deliberately is not:
		# the coin line and the swath ride the one function on purpose.)
		#
		# OFFSET ALONG THE CORRIDOR'S OWN NORMAL, not along +Z, and that is the
		# whole strength of this leg. The road's Z at the terminal is seeded, so
		# the smoothstep can be far steeper than 45 degrees (6.4 m of Z per metre
		# of X, measured over 500 seeds); a Z-offset probe then asks for a point
		# only 8 / sqrt(1 + slope^2) metres from the walk, and an implementation
		# that reads the corridor at the candidate's own X answers "8 m" to it and
		# passes while waving massifs through at under 4 m. The normal is taken
		# from the curve numerically, so it needs no second copy of the corridor.
		var cx := terminal_x + 1.0
		while cx < BudapestPlan.GATE.x:
			var cp: Vector2 = BudapestPlan.road_approach_point(terminal, cx)
			var ahead: Vector2 = BudapestPlan.road_approach_point(terminal, cx + 0.5)
			var behind: Vector2 = BudapestPlan.road_approach_point(terminal, cx - 0.5)
			var normal := (ahead - behind).orthogonal().normalized()
			# Inside the swath. `min` over the stations too, so this is an upper
			# bound only — a station near T can legitimately answer closer.
			var p8 := cp + normal * 8.0
			var near: float = terrain._road_lateral_distance(p8.x, p8.y, 24.0)
			if near > 8.01:
				_fail("seed %d: 8 m off the approach corridor at x = %.0f reads "
						% [RUN_SEED + s * 977, cx] + "%.1f m from the road — the "
						% near + "walk into the gate has no clearance swath "
						+ "around it, only a zero-width line")
				break
			# ...AND THE SWATH HAS AN EDGE, which is the half that actually bites.
			# The previous spelling of this leg probed 400 m past the corridor's
			# whole Z EXTENT and demanded 399 m back: outside the clearance window
			# _road_lateral_distance is documented to return INF, and INF passes any
			# lower bound, so the leg could not fail for the reason it named. A band
			# with no edge — one that answers "on the road" everywhere — is caught
			# only by a probe just OUTSIDE it, taken along the same normal as the
			# inside probe so a steep seed cannot flatter it.
			#
			# Asked only where the STATION scan is already empty, so this is purely
			# a measurement of the corridor: past the terminal by the scan window
			# (clearance + two spacings) PLUS the offset itself, since the normal on
			# a steep stretch points mostly along X and would otherwise carry the
			# probe's own window back over T.
			var out_off := 24.0 + 4.0
			if cx - (24.0 + spacing * 2.0 + out_off) <= terminal.x:
				cx += 25.0
				continue
			var p_out := cp + normal * out_off
			var far: float = terrain._road_lateral_distance(p_out.x, p_out.y, 24.0)
			if far <= 24.0:
				_fail("seed %d: %.0f m off the approach corridor at x = %.0f still "
						% [RUN_SEED + s * 977, out_off, cx] + "reads %.1f m from "
						% far + "the road — the clearance swath has no edge, so it "
						+ "is suppressing every spawner across the whole band")
				break
			cx += 25.0

		# THE COIN LINE IS PITCHED ALONG THE CORRIDOR, NOT ALONG X. Stepping the
		# pitch in X opens the physical gap to CITY_COIN_SPACING * sqrt(1 + slope^2)
		# — up to ~50 m on a steep seed, on the one stretch of the walk that has
		# nothing else to read. Measured on the shipped line, between consecutive
		# coins, which is the only thing the player can see.
		var pitch: float = BudapestPlan.CITY_COIN_SPACING
		var line: PackedVector2Array = terrain._approach_coin_line()
		if line.size() < 2:
			_fail("seed %d: the approach coin line has %d coins"
					% [RUN_SEED + s * 977, line.size()])
		# Measured as the STRAIGHT LINE between neighbours, which is what the
		# player walks past; the pitch is along the corridor, so on a bend the
		# chord sits a little under it and can never sit over it.
		for i in range(1, line.size()):
			var gap := line[i - 1].distance_to(line[i])
			worst_gap = maxf(worst_gap, gap)
			if gap > pitch + 0.05 or gap < pitch * 0.8:
				_fail("seed %d: approach coins %d and %d stand %.1f m apart, not "
						% [RUN_SEED + s * 977, i - 1, i, gap] + "the %.0f m pitch "
						% pitch + "— the line is spaced in X instead of along the "
						+ "corridor, so a steep seed reads as a broken trail")
				break

		# THE TANGENTIAL JOIN. Skipped, counted, when the road happens to arrive
		# almost on the avenue's own line: every step is then ~0 and the ratio is
		# noise over noise, not a measurement.
		if max_step > 0.01:
			measured += 1
			var kink := maxf(first_step, last_step) / max_step
			worst_kink = maxf(worst_kink, kink)
			if kink > 0.25:
				_fail("seed %d: the corridor's end steps are %.0f%% of its middle "
						% [RUN_SEED + s * 977, kink * 100.0] + "step — it meets the "
						+ "road (or the avenue) at a kink instead of tangentially")
		terrain.free()

	print("approach: %d seeds, terminal within %.1f m of ROAD_TERMINAL_X, "
			% [APPROACH_SEEDS, worst_offset]
			+ "worst end-step %.0f%% of the mid-span step over %d measurable joins, "
			% [worst_kink * 100.0, measured]
			+ "worst coin gap %.2f m against a %.0f m pitch"
			% [worst_gap, BudapestPlan.CITY_COIN_SPACING])


# ============================================================================
# CHECK 8 — every consumer of the road stops at the terminal station
# ============================================================================

func _check_consumers_stop(terrain: Node3D, terrain_script: GDScript) -> void:
	"""
	The four caps of DEC-7, each measured through the thing that consumes the
	road: its coins, its clearance, its bosses and the map's drawn line.

	EACH ONE FAILS DIFFERENTLY AND ALL OF THEM QUIETLY. An uncapped coin walk
	lays a second wandering trail across the avenue; an uncapped clearance shoves
	city geometry aside to keep a swath clear that does not exist; an uncapped
	boss stands in a suburb; an uncapped map paints a road nobody can follow.
	"""
	var k: int = terrain._road_terminal_k()
	var terminal: Vector2 = terrain._road_station(k).center

	# ---- CAP 1: the coins ---------------------------------------------------
	terrain._road_extend_to_x(terminal.x, terminal.x + 600.0)
	var coins_before := 0
	for j in range(1, 51):
		coins_before += (terrain._road_coins_at(k - j) as Array).size()
	var coins_after := 0
	for j in range(1, 51):
		coins_after += (terrain._road_coins_at(k + j) as Array).size()
	if coins_after != 0:
		_fail("the road lays %d coins on the 50 stations PAST its terminal — a "
				% coins_after + "second wandering coin trail runs through Pest")
	if coins_before < 1:
		_fail("the road lays no coins on the 50 stations BEFORE its terminal "
				+ "either — check 8 measured a road that carries nothing")

	# ---- CAP 2: the clearance ------------------------------------------------
	var far: float = terrain._road_lateral_distance(terminal.x + 400.0, terminal.y, 30.0)
	if not is_inf(far):
		_fail("_road_lateral_distance answers %.1f m 400 m past the terminal "
				% far + "station — it is still shoving geometry off a road that ended")
	var near: float = terrain._road_lateral_distance(terminal.x - 100.0, terminal.y, 30.0)
	if is_inf(near):
		_fail("_road_lateral_distance answers INF 100 m BEFORE the terminal — the "
				+ "cap has eaten the road it was supposed to end")

	# ---- CAP 3: the bosses ---------------------------------------------------
	# Driven on the ONLY chunks that could ever spawn them: a boss is claimed by
	# the chunk its first candidate lands in, which is its own station's chunk or
	# a neighbour. Sweeping the whole road would measure the same thing far more
	# slowly.
	var consts := terrain_script.get_script_constant_map()
	var interval: int = consts["BOSS_INTERVAL_STATIONS"]
	var past := _bosses_near_stations(terrain, k + 1, k + 400, interval)
	var before := _bosses_near_stations(terrain, maxi(1, k - 400), k, interval)
	if past != 0:
		_fail("%d boss crocodiles stand past the road's terminal station — they "
				% past + "guard a road that is not there")
	if before < 1:
		_fail("no boss stands on the 400 stations BEFORE the terminal either — "
				+ "check 8's boss cap measured an inert road")

	# ---- CAP 4: the map ------------------------------------------------------
	var map := Control.new()
	map.set_script(load("res://scripts/minimap_hud.gd"))
	root.add_child(map)
	map._terrain = terrain
	# Standing ON the terminal, so the map's window reaches well past it in both
	# directions and the clamp is the only thing that can stop the line.
	map._player_pos = Vector3(terminal.x, 0.0, terminal.y)
	map._gather_road()
	var k_start: int = terrain._road_first_k_at_or_after_x(terminal.x - map._view_radius())
	var k_last: int = k_start + map._road_count - 1
	if map._road_count < 2:
		_fail("the minimap gathered %d road points at the terminal station — the "
				% map._road_count + "line vanished instead of stopping")
	elif k_last > k:
		_fail("the minimap draws the road out to station %d, %d stations past the "
				% [k_last, k_last - k] + "terminal — a painted road that carries "
				+ "no coins and steers nobody")
	map.free()

	print("caps: coins %d -> 0 across T, clearance %.1f -> INF, bosses %d -> 0, "
			% [coins_before, near, before]
			+ "map stops at station %d of %d" % [k_last, k])


func _bosses_near_stations(terrain: Node3D, k_from: int, k_to: int, interval: int) -> int:
	"""How many bosses the chunks around a range of BOSS stations actually spawn."""
	terrain._road_extend_to_x(terrain._road_station(maxi(1, k_from)).center.x - 100.0,
			terrain._road_station(maxi(1, k_from)).center.x + 100.0)
	var seen := {}
	var count := 0
	var i := int(ceil(float(k_from) / float(interval)))
	while i * interval <= k_to:
		var k := i * interval
		i += 1
		if k > terrain.road_k_max:
			terrain._road_extend_to_x(terrain._road_station(terrain.road_k_max).center.x,
					terrain._road_station(terrain.road_k_max).center.x + 400.0)
			if k > terrain.road_k_max:
				break
		var centre: Vector2 = terrain._road_station(k).center
		var home: Vector2i = terrain.world_to_chunk(Vector3(centre.x, 0.0, centre.y))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var chunk_pos := Vector2i(home.x + dx, home.y + dz)
				if seen.has(chunk_pos):
					continue
				seen[chunk_pos] = true
				var parent := MeshInstance3D.new()
				parent.position = terrain.chunk_to_world(chunk_pos)
				root.add_child(parent)
				terrain.spawn_bosses_in_chunk(chunk_pos, parent, [])
				for child in parent.get_children():
					if String(child.name).begins_with("BossCrocodile_"):
						count += 1
				parent.free()
	return count


# ============================================================================
# CHECK 9 — the spawner policy: five answers, not one exclusion disc
# ============================================================================

func _check_spawner_policy(terrain: Node3D) -> void:
	"""
	~60 chunks spread over the whole rect, each run through create_chunk's own
	sequence, and every spawner asked what it put in Pest.

	THE POSITIVE CONTROLS ARE THE POINT. "Nothing spawned" is also what a broken
	sweep reports, and a policy that silently killed the hunters — the one
	predator the city keeps everywhere — would pass every negative in this check.
	So the hunters and the Danube's crocodiles both have to be FOUND.
	"""
	var chunks := _rect_chunks(terrain, POLICY_CHUNK_STRIDE)
	var props := 0
	var features := 0
	var hunters := 0
	var danube_crocs := 0
	var bosses := 0
	var strangers := 0
	var dry_crocs := 0

	for chunk_pos: Vector2i in chunks:
		# The five silent spawners, each asked on its own so the failure message
		# can name which one answered.
		var platforms: Array = []
		var batch: Array = []
		var body := StaticBody3D.new()
		var parent := MeshInstance3D.new()
		parent.position = terrain.chunk_to_world(chunk_pos)
		root.add_child(parent)

		var obstacles: Array = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
		props += obstacles.size()
		features += batch.size()
		var mark := batch.size()
		terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
		terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
		terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
		terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
		terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)
		if batch.size() != mark or not parent.get_children().is_empty():
			_fail("chunk %s inside the city built %d boxes and %d nodes from the "
					% [chunk_pos, batch.size() - mark, parent.get_child_count()]
					+ "artifact / biome / camp / geo-landmark / chest family — the "
					+ "city rect is supposed to answer no to all five")

		# ...and then the predators, through the same sequence create_chunk runs.
		terrain.spawn_city_in_chunk(chunk_pos, parent, obstacles, batch, body)
		terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
		terrain.spawn_platform_crocodiles(chunk_pos, parent, platforms)
		terrain.spawn_danube_crocodiles_in_chunk(chunk_pos, parent)
		terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)
		terrain.spawn_hunters_in_chunk(chunk_pos, parent, obstacles)

		for child in parent.get_children():
			if not (child is Node3D) or not (child as Node).is_in_group("crocodile"):
				continue
			var node := child as Node3D
			var name := String(node.name)
			if name.begins_with("Hunter_"):
				hunters += 1
				continue
			if name.begins_with("BossCrocodile_"):
				bosses += 1
				continue
			var species := String(node.get("species"))
			if species != "crocodile":
				strangers += 1
				_fail("chunk %s inside the city spawned a '%s' — the rect's one "
						% [chunk_pos, species] + "predator answer is the Danube's "
						+ "crocodiles, and BIOME_SPECIES would put a dog in the water")
				continue
			danube_crocs += 1
			var world: Vector3 = node.position + terrain.chunk_to_world(chunk_pos)
			if not BudapestPlan.danube_wet(world.x, world.z):
				dry_crocs += 1
				_fail("a Danube crocodile stands on DRY land at (%.0f, %.0f) — on "
						% [world.x, world.z] + "a bridge deck, an island or the bank")
		body.free()
		parent.free()

	if props > 0 or features > 0:
		_fail("%d prop footprints and %d structure boxes were built inside the "
				% [props, features] + "city rect — Pest has cacti and barrier walls in it")
	if bosses > 0:
		_fail("%d road bosses spawned inside the city rect — the road ends west "
				% bosses + "of the gate, so there is nothing there for them to guard")
	if hunters < 1:
		_fail("not one GD-SURVEY hunter spawned anywhere in the city sweep — the "
				+ "corporation hunts every band, and a policy that killed them "
				+ "would pass every negative in this check")
	if danube_crocs < 1:
		_fail("not one crocodile spawned in the Danube across the sweep — the "
				+ "'crocodiles only where it is wet' result above is vacuous")

	print("policy over %d city chunks: 0 props, 0 structures, 0 artifacts/camps/"
			% chunks.size() + "landmarks/chests/biome content, 0 bosses; %d Danube "
			% danube_crocs + "crocodiles (all wet, %d dry) and %d hunters"
			% [dry_crocs, hunters])


# ============================================================================
# CHECK 10 — the crocodile stream, A/B (enemy_spawn_selfcheck check 12's method)
# ============================================================================

func _check_crocodile_stream_ab(terrain_script: GDScript) -> void:
	"""
	Build a field of chunks twice — once with the city streamer live, once with it
	not called at all — and compare the crocodiles byte for byte.

	"Not called at all" is the strongest form of off available and needs no flag:
	the harness drives create_chunk's sequence itself, so a leg simply omits the
	call. What it measures is CLAUDE.md's determinism rule — an independent feature
	takes its OWN hash stream and consumes no draw from a stream somebody else
	reads — and the cost of breaking it is invisible and total: one extra draw
	slides every crocodile the other spawner places.

	TWO FIELDS, BECAUSE ONE OF THEM CANNOT FAIL AND SAYING SO IS THE POINT. The
	two crocodile spawners gate on in_budapest(chunk centre) with OPPOSITE
	polarity, and BUDAPEST_MIN/MAX are exact multiples of chunk_size, so no chunk
	in the world ever runs both:

	  - WEST OF THE GATE the subject is the ORDINARY chunk crocodile, and the city
	    streamer's own rect reject means neither city call reaches a draw. The A/B
	    is therefore a statement that the reject really is the first thing either
	    function does — true, worth keeping, and structurally unable to fail on the
	    stream question.
	  - ON THE DANUBE the subject is the DANUBE crocodile, which shares its chunks
	    with the city streamer — 20-odd landmark builders, the plateaus, the ramps
	    and the avenue, all running in the same call. THAT is the leg that can
	    fail, and it is the one CLAUDE.md's "the Danube crocodiles' own stream
	    A/B'd against the shared one" is actually about.

	BOTH HALVES OF BOTH FIELDS, like check 12: byte-identical AND non-empty.
	"""
	var west_crocs := _croc_ab_pair(terrain_script, "west of the gate", 2,
			Vector3(BudapestPlan.BUDAPEST_MIN.x - 400.0, 0.0, 0.0))
	var river_crocs := _croc_ab_pair(terrain_script, "on the Danube", 4,
			Vector3(BudapestPlan.DANUBE[2].x, 0.0, BudapestPlan.DANUBE[2].y))

	print("croc A/B: %d ordinary crocodiles west of the gate and %d Danube "
			% [west_crocs, river_crocs] + "crocodiles in the city's own chunks, "
			+ "none moved by the city streamer")


func _croc_ab_pair(terrain_script: GDScript, where: String, reach: int, at: Vector3) -> int:
	"""
	One A/B: the same field with and without spawn_city_in_chunk, compared byte for
	byte. @return the crocodile count, so the caller can prove the field was not
	empty (a comparison of two empty signatures proves nothing).
	"""
	var live := _croc_ab_field(terrain_script, true, at, reach)
	var off := _croc_ab_field(terrain_script, false, at, reach)

	var moved := 0
	var crocs := 0
	for key_v: Variant in live:
		var mine: Array = live[key_v]
		crocs += mine.size()
		if var_to_bytes(mine) != var_to_bytes(off.get(key_v, [])):
			moved += 1

	if moved > 0:
		_fail("%d of %d chunks %s put their crocodiles somewhere else once the "
				% [moved, live.size(), where] + "city streamer was live — it is "
				+ "drawing from a stream a crocodile spawner reads, instead of "
				+ "from its own CITY_STREAM_SEED / DANUBE_SALT")
	if crocs < 1:
		_fail("the A/B field %s contained no crocodiles at all — check 10 "
				% where + "compared two empty signatures and proved nothing")
	return crocs


func _croc_ab_field(terrain_script: GDScript, city_on: bool, at: Vector3, reach: int) -> Dictionary:
	"""One leg of check 10: chunk -> [name, species, position, yaw] per crocodile."""
	# DELIBERATELY NOT IN THE TREE. endless_terrain's _ready() re-rolls run_seed
	# FIRST THING, so a terrain added to the tree after set_run_seed() throws the
	# forced seed away — and two legs of an A/B would then be two different worlds
	# agreeing about nothing. (_make_terrain, which the in-tree checks use, adds
	# first and forces the seed second for exactly this reason.)
	var terrain := _detached_terrain(terrain_script, RUN_SEED)
	var origin: Vector2i = terrain.world_to_chunk(at)
	var out := {}
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var chunk_pos := Vector2i(origin.x + dx, origin.y + dz)
			var parent := MeshInstance3D.new()
			parent.position = terrain.chunk_to_world(chunk_pos)
			root.add_child(parent)
			var platforms: Array = []
			var batch: Array = []
			var body := StaticBody3D.new()
			var obstacles: Array = terrain.spawn_objects_in_chunk(chunk_pos, platforms, batch, body)
			terrain.spawn_artifact_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk_pos, obstacles, batch, body)
			terrain.spawn_camp_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_landmark_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_chest_in_chunk(chunk_pos, parent, obstacles, batch, body)
			if city_on:
				terrain.spawn_city_in_chunk(chunk_pos, parent, obstacles, batch, body)
			terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
			terrain.spawn_platform_crocodiles(chunk_pos, parent, platforms)
			# ALWAYS, in both legs: the Danube's spawner is a SUBJECT of this
			# A/B on the river field, not the variable. The variable is the city
			# streamer above, which is the thing that shares its chunks.
			terrain.spawn_danube_crocodiles_in_chunk(chunk_pos, parent)
			var parts: Array = []
			for child in parent.get_children():
				if not (child as Node).is_in_group("crocodile"):
					continue
				var node := child as Node3D
				parts.append([String(node.name), String(node.get("species")),
						node.position, node.rotation.y])
			out[chunk_pos] = parts
			body.free()
			parent.free()
	terrain.free()
	return out


# ============================================================================
# CHECK 11 — the plateau ramps are the only way up, so they have to work
# ============================================================================

func _check_ramps(terrain: Node3D) -> void:
	"""
	Both hills' ramps, measured on the BOXES the streamer actually builds.

	The slope ceiling is TowerInterior.PLAN_RAMP_MAX_SLOPE, READ from that script
	and never restated: it is the slope of the one ramp in this game anybody has
	walked, so retuning that retunes this with it.

	The rest is the seam. A ramp is sliced across four or five chunks, and two
	slices that disagree about the plane by a few centimetres are a step —
	something CharacterBody3D cannot climb at all. So each slice's top surface is
	compared against the UNSLICED plane at both of its ends, which also settles
	"the foot is at y = 0" and "the head is flush with the lid" in the same
	arithmetic.
	"""
	var ceiling: float = TowerInterior.PLAN_RAMP_MAX_SLOPE
	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		var id := String(row["id"])
		var ramp: Rect2 = row["ramp"]
		var plateau: Rect2 = row["rect"]
		var top: float = row["top"]
		var run: float = ramp.size.x
		var slope := top / run

		if slope > ceiling:
			_fail("'%s' climbs %.0f m over %.0f (slope %.3f), over "
					% [id, top, run, slope] + "TowerInterior.PLAN_RAMP_MAX_SLOPE "
					+ "%.3f — the hill's only way up is too steep to walk" % ceiling)

		# The head has to MEET the lid: a ramp that stops a metre short leaves a
		# step at the top, which is the same unwalkable thing at the other end.
		var head := ramp.position.x + run if int(row["ramp_dir"]) > 0 else ramp.position.x
		var edge := plateau.position.x if int(row["ramp_dir"]) > 0 else plateau.end.x
		if absf(head - edge) > 0.001:
			_fail("'%s' ramp's head is at x = %.1f but its plateau's face is at "
					% [id, head] + "%.1f — the two do not meet" % edge)
		if ramp.position.y < plateau.position.y or ramp.end.y > plateau.end.y:
			_fail("'%s' ramp is not against its plateau's face in Z" % id)

		# NEITHER THE HILL NOR ITS RAMP MAY STAND IN THE DANUBE, and the two
		# symptoms are why: is_river_at() is XZ-only, so a lid at y = 30 over the
		# band WADES, and spawn_danube_crocodiles_in_chunk re-tests only
		# danube_wet(), so it would put a crocodile inside 30 m of solid stone.
		# Both hills clear the band by more than PLATEAU_DRY_MARGIN today (Castle
		# Hill by 11 m, Gellért by 15) — see the note over BudapestPlan.PLATEAUS,
		# which is why the SE corner is authored at 370 m and not 400.
		#
		# Measured on the PERIMETER at 1 m, which bounds the interior too: the
		# polyline runs from z = -1100 to z = +1100, so it cannot lie inside one of
		# these rects without crossing its edge, and a crossing reads ~0 here.
		var wettest := INF
		for area: Rect2 in [plateau, ramp]:
			for ux in range(int(area.size.x) + 1):
				wettest = minf(wettest, minf(
						BudapestPlan.danube_distance(area.position.x + float(ux), area.position.y),
						BudapestPlan.danube_distance(area.position.x + float(ux), area.end.y)))
			for uz in range(int(area.size.y) + 1):
				wettest = minf(wettest, minf(
						BudapestPlan.danube_distance(area.position.x, area.position.y + float(uz)),
						BudapestPlan.danube_distance(area.end.x, area.position.y + float(uz))))
		if wettest < BudapestPlan.DANUBE_HALF_WIDTH + PLATEAU_DRY_MARGIN:
			_fail("'%s' (hill or ramp) reaches %.1f m from the Danube's polyline "
					% [id, wettest] + "(band half-width %.0f) — a hill standing in "
					% BudapestPlan.DANUBE_HALF_WIDTH
					+ "the river wades on its own lid and spawns crocodiles "
					+ "inside its own stone")

		# The slices, and the plane they all have to agree with.
		var lo: Vector2i = terrain.world_to_chunk(Vector3(ramp.position.x, 0.0, ramp.position.y))
		var hi: Vector2i = terrain.world_to_chunk(Vector3(ramp.end.x, 0.0, ramp.end.y))
		var worst := 0.0
		var slices := 0
		var lowest := INF
		var highest := -INF
		# Every slice's X span, so the seams can be measured as well as the ends:
		# a slab that stopped being longer than its X width by the slope's own
		# hypotenuse ratio still lands its ends on the ideal plane — it just leaves
		# a gap at every chunk seam, which is a hole to fall through.
		var spans: Array[Vector2] = []
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var chunk_pos := Vector2i(cx, cz)
				var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
				var built := _build_city_chunk(terrain, chunk_pos)
				for entry_v: Variant in (built["batch"] as Array):
					var entry: Dictionary = entry_v
					var xf: Transform3D = entry["transform"]
					# A ramp slab is the only TILTED box the city builds; the
					# plateau lids, the houses and the pavement are all axis-aligned.
					if absf(xf.basis.y.normalized().y - 1.0) < 0.0001:
						continue
					slices += 1
					# The top surface's two end points, on the slab's centre line:
					# up half a thickness, then half the slab's length either way.
					var up := xf.basis.y * 0.5
					var span := Vector2(INF, -INF)
					for sign in [-1.0, 1.0]:
						var p: Vector3 = xf.origin + up + xf.basis.z * (0.5 * sign)
						var wx := p.x + centre.x
						var ideal := top * clampf((wx - ramp.position.x) / run, 0.0, 1.0)
						worst = maxf(worst, absf(p.y - ideal))
						lowest = minf(lowest, p.y)
						highest = maxf(highest, p.y)
						# The SPAN is taken on the slab's mid-height end faces, not
						# on the top edge: tilting the slab slides its top face
						# thickness/2 * sin(tilt) along X (10.5 cm here), and two
						# slabs that meet perfectly still show that as a "gap" if
						# it is measured up there.
						var mid: Vector3 = xf.origin + xf.basis.z * (0.5 * sign)
						span = Vector2(minf(span.x, mid.x + centre.x),
								maxf(span.y, mid.x + centre.x))
					spans.append(span)
				(built["body"] as Node).free()
				(built["parent"] as Node).free()

		if slices < 2:
			_fail("'%s' ramp came out as %d chunk slices — a 140 m ramp crosses "
					% [id, slices] + "several chunks, so this measured the wrong boxes")
		if worst > RAMP_FLUSH_TOL:
			_fail("'%s' ramp's surface is %.3f m off the unsliced plane at a slice "
					% [id, worst] + "end — two slices disagree, which is a STEP, and "
					+ "CharacterBody3D cannot climb one at all")
		if absf(lowest) > RAMP_FLUSH_TOL:
			_fail("'%s' ramp's foot sits at y = %.3f instead of on the ground" % [id, lowest])
		if absf(highest - top) > RAMP_FLUSH_TOL:
			_fail("'%s' ramp's head sits at y = %.3f, not flush with its lid at "
					% [id, highest] + "%.1f" % top)

		# ...and the seams themselves: the slabs have to COVER the ramp rect end to
		# end, with no gap between one slice's east end and the next one's west.
		spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var reach := ramp.position.x
		var gap := 0.0
		for span: Vector2 in spans:
			gap = maxf(gap, span.x - reach)
			reach = maxf(reach, span.y)
		gap = maxf(gap, ramp.end.x - reach)
		if gap > RAMP_FLUSH_TOL:
			_fail("'%s' ramp's slices leave a %.3f m gap in its own footprint — "
					% [id, gap] + "neighbouring chunks' slabs do not meet, so the "
					+ "climb has a hole in it")

		print("ramp '%s': slope %.3f <= %.3f, %d slices, worst %.3f m off the "
				% [id, slope, ceiling, slices, worst]
				+ "plane, worst seam gap %.3f, foot %.3f, head %.3f (lid %.0f), "
				% [gap, lowest, highest, top]
				+ "nearest Danube %.1f m (band %.0f + margin %.0f)"
				% [wettest, BudapestPlan.DANUBE_HALF_WIDTH, PLATEAU_DRY_MARGIN])


# ============================================================================
# CHECK 12 — the difficulty gradient is pinned at the gate
# ============================================================================

func _check_difficulty_clamp() -> void:
	"""
	Driven on real bodies at three world X values, because the clamp is one
	`minf` inside piglet_crocodile_ai's _ready() and the only way to prove it
	fired is to read the speed it produced.

	BOSSES, so the measurement is not a random roll: a boss takes no per-instance
	speed roll at all. The titan is the subject because its `boss_chase_speed`
	(3.0) leaves the gradient well clear of MAX_CHASE_SPEED at every X here — a
	subject that saturated the clamp would answer "equal" everywhere and prove
	nothing.

	  * x = GATE.x and x = 3800 (the rect's east edge) must be EQUAL: walking
	    east through the city is exactly as dangerous as arriving was.
	  * x = -3800 must NOT be: `absf` stays outside the `minf`, so travelling WEST
	    past the HQ is untouched by the city's existence.
	"""
	var scene: PackedScene = load(CROC_SCENE)
	var at_gate := _boss_chase_speed_at(scene, BudapestPlan.GATE.x)
	var past_gate := _boss_chase_speed_at(scene, BudapestPlan.BUDAPEST_MAX.x)
	var westward := _boss_chase_speed_at(scene, -BudapestPlan.BUDAPEST_MAX.x)

	if not is_equal_approx(at_gate, past_gate):
		_fail("a boss at the city's east edge chases at %.3f m/s but one at the "
				% past_gate + "gate chases at %.3f — the difficulty gradient is "
				% at_gate + "still escalating across Budapest, which is the run's "
				+ "destination and not another 2.2 km of it")
	if is_equal_approx(at_gate, westward):
		_fail("a boss 3800 m WEST chases at the same %.3f m/s as one at the gate "
				% westward + "— the clamp has swallowed the whole gradient instead "
				+ "of pinning its eastern end (absf belongs outside the minf)")

	print("difficulty: chase speed %.3f at the gate, %.3f at the rect's east edge "
			% [at_gate, past_gate] + "(pinned), %.3f 3800 m west (free)" % westward)


func _boss_chase_speed_at(scene: PackedScene, world_x: float) -> float:
	"""One titan boss, placed at a world X, asked what speed it resolved."""
	var croc := scene.instantiate()
	croc.species = "titan"
	croc.setup_as_boss(2.5)
	croc.position = Vector3(world_x, 0.0, 0.0)
	root.add_child(croc)
	var speed: float = croc.chase_speed_instance
	croc.free()
	return speed


# ============================================================================
# CHECK 13 — the avenue out of the gate is walkable
# ============================================================================

func _check_avenue(terrain: Node3D) -> void:
	"""
	The one corridor this bead promises: 16 m wide, from the gate east to the
	Danube's west bank, with nothing solid standing in it.

	MEASURED ON THE COLLISION SHAPES, not on the footprints, because a footprint
	is a keep-out CLAIM and a collision shape is a wall. Each shape's box is
	projected onto the XZ plane through its own basis, so a tilted ramp slab or a
	rotated house is measured as what it actually occupies.

	The footprint discs are checked too, one exemption named: the CHAIN BRIDGE.
	The avenue's east end IS its western abutment — the corridor is supposed to
	arrive at the bridge — so its disc reaches the last metre of the corridor by
	design, and the collision sweep above is what says the arrival is walkable.

	AND SINCE BEAD .4 THE COLLISION SWEEP EXEMPTS THE DECK ITSELF — by rect, so
	the exemption is exactly the bridge and not a radius around it. The Chain
	Bridge's western approach begins 22 m short of the bank and runs straight up
	the middle of the avenue, which is the correct city: the road out of the gate
	arrives at the bridge and climbs onto it. That ramp is solid stone whose top
	surface is flush with the ground at its foot, so "nothing solid stands here" is
	the wrong question to ask of it; check 14 asks the right ones — slope under
	TowerInterior.PLAN_RAMP_MAX_SLOPE, flush at both ends, no step at a chunk seam,
	no gap to fall through. Everything else in the corridor is still a wall.

	The full one-hero reachability audit over all 22 slots is bead
	godot-test1-8gw.10; this is the one corridor .3 promises.
	"""
	var half: float = BudapestPlan.AVENUE_HALF_WIDTH
	var east: float = terrain._approach_coin_east_end()
	var corridor := Rect2(BudapestPlan.GATE.x, -half, east - BudapestPlan.GATE.x, half * 2.0)

	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		if (row["rect"] as Rect2).intersects(corridor):
			_fail("plateau '%s' stands in the avenue — the corridor out of the "
					% String(row["id"]) + "gate runs into a cliff")

	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		var id := String(slot["id"])
		if id == "chain_bridge":
			continue   # the avenue ARRIVES at it; see the docstring
		var pos: Vector3 = slot["pos"]
		var near := Vector2(clampf(pos.x, corridor.position.x, corridor.end.x),
				clampf(pos.z, corridor.position.y, corridor.end.y))
		var d := Vector2(pos.x - near.x, pos.z - near.y).length()
		if d < float(slot["radius"]):
			_fail("landmark '%s' overlaps the avenue by %.1f m" % [id, float(slot["radius"]) - d])

	var lo: Vector2i = terrain.world_to_chunk(Vector3(corridor.position.x - 60.0, 0.0, -60.0))
	var hi: Vector2i = terrain.world_to_chunk(Vector3(corridor.end.x + 60.0, 0.0, 60.0))
	var blockers := 0
	# THE POSITIVE CONTROL. Every other absence check in this file carries one, and
	# this sweep needs it most: its whole verdict is a count that stays 0 whether
	# the corridor is genuinely clear or the city built NOTHING in these chunks. A
	# rect-membership regression, or an east end that moved, would turn the avenue
	# into unbuilt scenery and still report a pass.
	var shapes_examined := 0
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var chunk_pos := Vector2i(cx, cz)
			var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
			var built := _build_city_chunk(terrain, chunk_pos)
			var body: StaticBody3D = built["body"]
			for child in body.get_children():
				var shape := child as CollisionShape3D
				var box := shape.shape as BoxShape3D
				if box == null:
					continue
				shapes_examined += 1
				var xf: Transform3D = shape.transform
				var e: Vector3 = box.size * 0.5
				# The box's own half-extent along world X and Z, through its basis.
				var ax := absf(xf.basis.x.x) * e.x + absf(xf.basis.y.x) * e.y + absf(xf.basis.z.x) * e.z
				var az := absf(xf.basis.x.z) * e.x + absf(xf.basis.y.z) * e.y + absf(xf.basis.z.z) * e.z
				var wx := xf.origin.x + centre.x
				var wz := xf.origin.z + centre.z
				if wx + ax < corridor.position.x or wx - ax > corridor.end.x:
					continue
				if wz + az < corridor.position.y or wz - az > corridor.end.y:
					continue
				# THE ONE EXEMPTION, and it is a rect and not a radius: a bridge's
				# own deck. See the docstring — the avenue arrives at the Chain
				# Bridge and climbs it, and a ramp is measured by check 14, not by
				# an absence of stone.
				if _on_a_bridge_deck(wx, wz):
					continue
				blockers += 1
				if blockers <= 3:
					_fail("a solid box stands in the avenue at (%.0f, %.0f), "
							% [wx, wz] + "%.1f x %.1f m — the one corridor this "
							% [ax * 2.0, az * 2.0] + "bead promises is blocked")
			body.free()
			(built["parent"] as Node).free()

	if shapes_examined < 1:
		_fail("the avenue sweep examined no collision shape at all over the %d "
				% ((hi.x - lo.x + 1) * (hi.y - lo.y + 1)) + "chunks around the "
				+ "corridor — the city built nothing there, so a clear corridor "
				+ "is not what was measured")

	print("avenue: %.0f m from the gate to the west bank at x = %.0f, %d solid "
			% [corridor.size.x, east, blockers] + "boxes inside its 16 m (the Chain "
			+ "Bridge's approach exempted), out of %d shapes examined" % shapes_examined)


func _on_a_bridge_deck(x: float, z: float) -> bool:
	"""Is this world XZ homed on one of the four bridges' deck rects? The avenue
	sweep's one exemption, and the same rect the band is punched out by."""
	for row_v: Variant in BudapestPlan.BRIDGES:
		if (BudapestPlan.bridge_deck(row_v) as Rect2).has_point(Vector2(x, z)):
			return true
	return false


# ============================================================================
# CHECK 14 — the four bridges: a walking player crosses each one, dry
# ============================================================================

## How far a deck rect's END has to stand clear of the 240 m band before the ramp
## whose foot sits on it counts as landing on the BANK. A margin and not a zero
## for PLATEAU_DRY_MARGIN's reason: an approach authored flush against the water's
## edge is one retune of DANUBE_HALF_WIDTH away from starting in it.
const BRIDGE_BANK_MARGIN: float = 10.0

## How far outside a deck's long edge check 14 starts asking "is it still the
## river?". Small, because the point is that the cutout is exactly the deck and
## not a fairway around it — two metres off the parapet you are wading.
const BRIDGE_WET_PROBE: float = 2.0

## ...and how far it will keep stepping out while the answer is another AUTHORED
## dry rect. The Margaret Bridge crosses Margaret Island, so its northern parapet
## has 232 m of lawn beside it and its southern 44; 60 gives that side a verdict
## and lets the northern one abstain, which is the mechanism working rather than
## the band failing.
const BRIDGE_WET_PROBE_REACH: float = 60.0

## Check 14's crocodile sweep buckets the Danube into three by Z — upstream, the
## bend, downstream — and every bucket has to be populated. "The policy runs along
## the whole length" is otherwise satisfied by one crocodile at the bend.
const DANUBE_BUCKETS: int = 3


func _check_bridges(terrain: Node3D) -> void:
	"""
	The four decks, Margaret Island, and the crocodiles along the whole river.

	THE ACCEPTANCE IS "A WALKING PLAYER CROSSES EACH BRIDGE WITHOUT WADING", and
	it splits into two questions measured in two different places:

	  DRY is is_river_at()'s, walked metre by metre along the deck's centre line,
	  with a WET control two metres off the parapet — the cutout has to be exactly
	  the deck and not a fairway around it.

	  WALKABLE is the BOXES', held to the standard check 11 holds the plateau ramps
	  to, because CharacterBody3D cannot climb a step at all: the surface every
	  slice actually builds is compared against BudapestPlan.bridge_surface_y() at
	  both ends of every slab, and the slabs have to COVER the rect on both axes
	  with no seam gap to fall through. The slope ceiling is
	  TowerInterior.PLAN_RAMP_MAX_SLOPE, READ from there and never restated.

	AND THE ORNAMENT HAS TO AGREE. The pylons, towers, chains and lions are
	landmark_builders.gd's, standing on the SLOTS row of the same id; the deck is
	built off the DRY_RECTS row. Nothing in the engine binds those two, so this is
	where they are bound: every BRIDGES row names a slot that exists, has a
	builder, and sits at the deck rect's own centre.

	# ponytail: THE HEIGHT IS NOT BOUND, only the XZ position. Every bridge
	# builder's ornament stops at y = 12 (the Chain's and the Elisabeth's hangers
	# hang to it, the Liberty's river piers top out on it, the Margaret's lamp
	# standards stand on it), but those are literals inside those functions and not
	# data anything can read. Retuning BRIDGE_DECK_TOP therefore leaves the chains
	# hanging in air with nothing here to say so — cosmetic, which is why it is a
	# note. Binding it means measuring the ornament's own boxes for a horizontal
	# edge at the deck's height; worth doing the day the deck height moves.
	"""
	_check_bridge_profile_control()
	var ceiling: float = TowerInterior.PLAN_RAMP_MAX_SLOPE
	var slope: float = BudapestPlan.BRIDGE_DECK_TOP / BudapestPlan.BRIDGE_RAMP_RUN
	if slope > ceiling:
		_fail("a bridge approach climbs %.1f m over %.0f (slope %.3f), over "
				% [BudapestPlan.BRIDGE_DECK_TOP, BudapestPlan.BRIDGE_RAMP_RUN, slope]
				+ "TowerInterior.PLAN_RAMP_MAX_SLOPE %.3f — no traversal in this "
				% ceiling + "game may demand a jump-height, indoors or out")

	var claimed: Dictionary = {}
	for row_v: Variant in BudapestPlan.BRIDGES:
		var row: Dictionary = row_v
		var id := String(row["id"])
		var dry := int(row["dry"])
		if dry < 0 or dry >= BudapestPlan.DRY_RECTS.size():
			_fail("bridge '%s' names DRY_RECTS row %d, which does not exist — its "
					% [id, dry] + "deck would be built where the band was never "
					+ "punched out")
			continue
		if claimed.has(dry):
			_fail("bridges '%s' and '%s' both claim DRY_RECTS row %d — two decks "
					% [id, String(claimed[dry]), dry] + "cannot stand on one rect")
		claimed[dry] = id
		_check_one_bridge(terrain, row, id, slope, ceiling)

	_check_no_reward_under_a_deck(terrain)
	_check_nothing_stands_in_the_river(terrain)
	_check_margaret_island(terrain, claimed)
	_check_danube_crocodiles(terrain)


## The one slot whose STONE stands in the Danube on purpose. Sixty pairs of iron
## shoes on the embankment facing the water IS the memorial — moving them onto dry
## ground would be moving the thing itself. Authored, named here, and the only
## name in this file: everything else is exempted by a MECHANISM (standing on a
## DRY_RECTS row, or on a plateau's lid) or is not exempt at all.
const WET_STONE_ALLOWED: Array[String] = ["shoes_on_the_danube"]


func _check_nothing_stands_in_the_river(terrain: Node3D) -> void:
	"""
	NO LANDMARK'S STONE MAY STAND IN THE DANUBE, AND NONE MAY STAND IN A MASSIF.

	Both halves are the same bug one axis apart, and it is the bug that moved the
	two baths and the Liberty Bridge's deck: `is_river_at()` is XZ-only, so a
	platform over the band WADES however high it is, and a plateau is solid stone
	from the ground to its lid, so a building inside one is buried and unreachable.

	THE WET HALF IS MEASURED ON THE COLLIDING BOXES, NOT ON THE DISC, and that
	distinction is the whole reason this check is worth writing. A slot's radius is
	an axis-agnostic BOUND: the Parliament is 268 m long on Z and 125 m on X, so
	its 151 m disc reaches 33 m into the water while not one stone of it does. A
	disc rule would have to allow-list the Parliament, and that exemption would
	then hide a real Parliament that DID reach the river. Boxes have no such
	slack — and they are what you stand on, which is what wading is about.

	Non-colliding boxes are ignored on purpose: a cornice, a canopy or a cable
	overhanging the water is a thing you look at, not a thing you stand on.

	THE PLATEAU HALF IS THE DISC, because there the bound is the right instrument:
	a massif is a keep-out volume, the disc is the slot's claim on the map, and a
	claim that overlaps one is an authoring mistake whichever way the building is
	elongated.

	TWO MECHANISM EXEMPTIONS AND ONE NAME. A slot standing on a DRY_RECTS row is a
	bridge or Margaret Island — a bridge's piers are in open water because that is
	what a pier is — and a slot whose `pos.y` is a lid stands ON a plateau by
	design. Neither is a list that can rot. The one name is WET_STONE_ALLOWED.
	"""
	_check_river_rule_control(terrain)
	var checked := 0
	var exempt := 0
	for i in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[i]
		var id := String(slot["id"])
		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]

		# ---- the massif half, on the disc ------------------------------------
		# Exempt: a slot authored at a lid height stands on that plateau.
		if pos.y <= 0.0:
			for plateau_v: Variant in BudapestPlan.PLATEAUS:
				var plateau: Dictionary = plateau_v
				var gap := _rect_point_distance(plateau["rect"], Vector2(pos.x, pos.z)) - radius
				if gap < 0.0:
					_fail("landmark '%s' overlaps the '%s' massif by %.1f m — that "
							% [id, String(plateau["id"]), -gap] + "hill is solid "
							+ "stone to its %.0f m lid, so the building is buried "
							% float(plateau["top"]) + "in it and unreachable")

		# ---- the river half, on the stone -----------------------------------
		if String(slot["builder"]).is_empty():
			continue
		if id in WET_STONE_ALLOWED or BudapestPlan.is_dry(pos.x, pos.z):
			exempt += 1
			continue
		checked += 1
		var wettest := _landmark_wettest(terrain, i, pos)
		var worst: float = wettest["d"]
		var worst_at: Vector2 = wettest["at"]
		if worst < BudapestPlan.DANUBE_HALF_WIDTH:
			_fail("landmark '%s' puts colliding stone %.1f m from the Danube's "
					% [id, worst] + "polyline at (%.0f, %.0f), inside the %.0f m "
					% [worst_at.x, worst_at.y, BudapestPlan.DANUBE_HALF_WIDTH]
					+ "band — is_river_at() is XZ-only, so a player standing on "
					+ "that platform WADES on it")

	print("nothing in the river: %d landmarks' colliding stone measured against "
			% checked + "the band, %d exempt (on a dry rect, or %s)"
			% [exempt, str(WET_STONE_ALLOWED)])


func _landmark_wettest(terrain: Node3D, index: int, centre: Vector3) -> Dictionary:
	"""
	The closest any COLLIDING box of one landmark builder comes to the Danube's
	polyline, run at `centre`.

	@return { d: metres from the polyline, at: the offending box's XZ centre }.

	Taking the centre as a PARAMETER rather than reading the slot is what lets the
	mutation control below run a real shipped builder somewhere it must fail — the
	measurement and the control are then the same code, which is the only way the
	control proves anything about the check.
	"""
	var built := _run_builder(terrain, index, centre, Vector3.ZERO)
	var worst := INF
	var worst_at := Vector2.ZERO
	for child in (built["body"] as Node).get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var box := shape.shape as BoxShape3D
		if box == null:
			continue
		var xf: Transform3D = shape.transform
		var e: Vector3 = box.size * 0.5
		# The box's world-axis half-extents, through its own basis — the same
		# projection check 13's avenue sweep uses on the same kind of node.
		var ax := absf(xf.basis.x.x) * e.x + absf(xf.basis.y.x) * e.y + absf(xf.basis.z.x) * e.z
		var az := absf(xf.basis.x.z) * e.x + absf(xf.basis.y.z) * e.y + absf(xf.basis.z.z) * e.z
		var foot := Rect2(xf.origin.x - ax, xf.origin.z - az, ax * 2.0, az * 2.0)
		var d := _rect_polyline_distance(foot)
		if d < worst:
			worst = d
			worst_at = foot.get_center()
	_free_builder(built)
	return {"d": worst, "at": worst_at}


func _check_river_rule_control(terrain: Node3D) -> void:
	"""
	THE MUTATION CONTROL for the rule above, in two parts, because the rule has two
	pieces that can each fail silently and agreeably.

	THE MEASUREMENT: a real shipped builder is run at a centre ON THE DANUBE'S
	CENTRELINE and has to be reported as wet. Same function, same builder, moved
	input — which is the only version of this control that says anything about the
	check people actually run. A rule that could not see a bath in mid-river would
	pass every bath ever authored.

	THE GEOMETRY: _rect_polyline_distance's exactness, on the case the docstring
	claims it for — a rect that SPANS the river with all four corners on dry land.
	A corner-sampling implementation reads that as 272 m of clearance; the right
	answer is zero. That is not a hypothetical: it is what a long east-west plinth
	on the embankment looks like the day somebody widens one.
	"""
	var probe := _slot_index("rudas_bath")
	if probe < 0:
		_fail("check 14's river control could not find a builder to mutate")
		return
	var mid: Vector2 = BudapestPlan.DANUBE[2]
	var wet := _landmark_wettest(terrain, probe, Vector3(mid.x, 0.0, mid.y))
	if float(wet["d"]) >= BudapestPlan.DANUBE_HALF_WIDTH:
		_fail("a landmark built ON the Danube's centreline measured %.1f m from "
				% float(wet["d"]) + "the polyline — the river rule cannot see "
				+ "stone standing in mid-channel, so it proves nothing about the "
				+ "landmarks it passed")

	# All four corners > 120 m from the polyline at z = 0 (the band there is
	# x 2352..2592), and the rect contains the river.
	var spanning := Rect2(2200.0, -5.0, 550.0, 10.0)
	if _rect_polyline_distance(spanning) > 0.001:
		_fail("a rect spanning the Danube from bank to bank measured %.1f m of "
				% _rect_polyline_distance(spanning) + "clearance — the rect / "
				+ "polyline distance is sampling corners, so a plinth laid across "
				+ "the river reads as dry")
	# ...and the positive control beside it: genuinely dry ground stays dry.
	if _rect_polyline_distance(Rect2(1700.0, -10.0, 20.0, 20.0)) <= BudapestPlan.DANUBE_HALF_WIDTH:
		_fail("a rect 650 m west of the Danube measured as inside the band — the "
				+ "rect / polyline distance answers wet for everything")


func _rect_point_distance(r: Rect2, p: Vector2) -> float:
	"""Distance from a point to an axis-aligned rect, 0 inside it."""
	return Vector2(maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x),
			maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)).length()


func _rect_polyline_distance(r: Rect2) -> float:
	"""
	Shortest distance from an axis-aligned rect to the Danube's polyline — the
	EXACT minimum over the whole rect, not a sample of it.

	A box that pokes into the band between its own corners is exactly the case a
	corner sample misses, and a grid sample fine enough to catch it over the
	Parliament's 125 x 272 m plinth is thousands of points. It needs neither: for
	two DISJOINT convex sets in the plane the minimum distance is attained at a
	VERTEX of one of them, so asking the four rect corners against each segment and
	the two segment endpoints against the rect is the whole answer.

	DISJOINT IS THE LOAD-BEARING WORD, and the control above is what taught it: a
	segment that CROSSES the rect has no vertex anywhere near it — the Danube's
	z = -40 and z = 520 endpoints are both far outside a 10 m-deep plinth laid
	across the river — and the vertex enumeration cheerfully returns 35 m for two
	shapes that overlap. So the crossing is tested first, and answers 0.
	"""
	var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y),
			Vector2(r.position.x, r.end.y), r.end]
	var best := INF
	for i in range(BudapestPlan.DANUBE.size() - 1):
		var a: Vector2 = BudapestPlan.DANUBE[i]
		var b: Vector2 = BudapestPlan.DANUBE[i + 1]
		if _segment_hits_rect(a, b, r):
			return 0.0
		for c: Vector2 in corners:
			best = minf(best, BudapestPlan.segment_distance(c, a, b))
		best = minf(best, _rect_point_distance(r, a))
		best = minf(best, _rect_point_distance(r, b))
	return best


func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	"""
	Does segment ab meet the axis-aligned rect? Liang-Barsky's slab clip: walk the
	four half-planes, narrowing the segment's own [0, 1] parameter window, and the
	segment meets the rect exactly when the window survives.

	A segment PARALLEL to a slab and outside it (p == 0, q < 0) is rejected
	outright rather than dividing by zero — the Danube's near-vertical segments
	against a wide, shallow plinth are exactly that case on the X axis.
	"""
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var ps: Array[float] = [-d.x, d.x, -d.y, d.y]
	var qs: Array[float] = [a.x - r.position.x, r.end.x - a.x,
			a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		var p: float = ps[i]
		var q: float = qs[i]
		if is_zero_approx(p):
			if q < 0.0:
				return false
			continue
		var t := q / p
		if p < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	return t0 <= t1


func _check_no_reward_under_a_deck(terrain: Node3D) -> void:
	"""
	NO COIN OF THE APPROACH LINE STANDS ON A BRIDGE'S FOOTPRINT.

	The corridor out of the gate runs east along z = 0, which is exactly where the
	Chain Bridge crosses — and a deck rect overhangs the band on purpose, so the
	bridge's western approach begins ~22 m short of the water and climbs 12 m over
	those metres. A ramp takes no `obstacles` footprint (it is the one thing you
	are MEANT to walk up), so _settle_coin_y cannot see it and would leave the last
	coins of the line at COIN_GROUND_HEIGHT with several metres of colliding stone
	over them — a reward you can see and never reach.

	Measured on the LINE the spawner actually uses, not on the east end it was
	clamped to: a clamp asserted against itself proves nothing, and the line is
	resampled by arc length so its last point is not simply the end value.
	"""
	var line: PackedVector2Array = terrain._approach_coin_line()
	if line.size() < 2:
		_fail("the approach coin line came out as %d points — check 14's buried-"
				% line.size() + "reward sweep measured nothing")
		return
	var buried := 0
	for p: Vector2 in line:
		if _on_a_bridge_deck(p.x, p.y):
			buried += 1
			if buried <= 3:
				_fail("an approach coin at (%.0f, %.0f) stands on a bridge deck's "
						% [p.x, p.y] + "footprint — it is spawned at ground height "
						+ "under a colliding ramp slab, so it can be seen and "
						+ "never picked up")

	print("approach coins: %d on the line, last at x = %.0f, %d of them under a "
			% [line.size(), line[line.size() - 1].x, buried] + "bridge deck")


func _check_bridge_profile_control() -> void:
	"""
	THE TWO PIECES OF NEW PURE LOGIC EVERYTHING ELSE IN CHECK 14 LEANS ON, driven
	on values whose answers are known — because both are the kind of helper that
	fails SILENTLY AND AGREEABLY.

	BudapestPlan.bridge_surface_y() is the profile every built slab is measured
	against, so a wrong profile makes the geometry agree with the wrong shape and
	reports 0.000 m of error. _span_gap() is the coverage test, and a coverage test
	that can never see a hole passes over a deck with a hole in it. So: the profile
	is asserted at both feet, at both ramp heads and across the middle, and the gap
	finder is handed intervals with a hole cut in them and has to find it.
	"""
	var row: Dictionary = BudapestPlan.BRIDGES[0]
	var deck: Rect2 = BudapestPlan.bridge_deck(row)
	var run: float = BudapestPlan.BRIDGE_RAMP_RUN
	var top: float = BudapestPlan.BRIDGE_DECK_TOP
	# (world X, expected height): the two feet, the two heads, the middle, and one
	# point half way up each ramp.
	var want: Array = [
		[deck.position.x, 0.0], [deck.end.x, 0.0],
		[deck.position.x + run, top], [deck.end.x - run, top],
		[deck.get_center().x, top],
		[deck.position.x + run * 0.5, top * 0.5],
		[deck.end.x - run * 0.5, top * 0.5],
	]
	for pair_v: Variant in want:
		var pair: Array = pair_v
		var got: float = BudapestPlan.bridge_surface_y(row, float(pair[0]))
		if absf(got - float(pair[1])) > RAMP_FLUSH_TOL:
			_fail("BudapestPlan.bridge_surface_y answers %.3f m at x = %.1f where "
					% [got, float(pair[0])] + "the deck's profile is %.3f — every "
					% float(pair[1]) + "geometry assertion in check 14 is measured "
					+ "against this, so it would agree with the wrong shape")

	# ...and the gap finder, with a 3 m hole cut out of the middle of a covered run.
	var solid: Array[Vector2] = [Vector2(0.0, 10.0), Vector2(10.0, 20.0)]
	if _span_gap(solid, 0.0, 20.0) > 0.001:
		_fail("_span_gap reports a hole in two intervals that meet exactly — the "
				+ "bridge coverage test would fail every deck it measured")
	var holed: Array[Vector2] = [Vector2(0.0, 10.0), Vector2(13.0, 20.0)]
	if absf(_span_gap(holed, 0.0, 20.0) - 3.0) > 0.001:
		_fail("_span_gap missed a 3 m hole between two intervals — check 14's "
				+ "coverage test cannot see a deck with a hole in it")
	if absf(_span_gap(solid, 0.0, 25.0) - 5.0) > 0.001:
		_fail("_span_gap missed 5 m of deck missing off the END of the run — a "
				+ "bridge that stopped short of its own abutment would pass")


func _check_one_bridge(terrain: Node3D, row: Dictionary, id: String,
		slope: float, ceiling: float) -> void:
	"""One deck: its binding to the ornament's slot, its abutments, the surface it
	actually builds, and the wade read along the crossing."""
	var deck: Rect2 = BudapestPlan.bridge_deck(row)
	var top: float = BudapestPlan.BRIDGE_DECK_TOP
	var centre := deck.get_center()

	# ---- 1. THE DECK AND THE ORNAMENT ARE THE SAME BRIDGE --------------------
	var si := _slot_index(id)
	if si < 0:
		_fail("bridge '%s' has no SLOTS row — its deck would be built where "
				% id + "nothing ever puts a pylon under it")
		return
	var slot: Dictionary = BudapestPlan.SLOTS[si]
	if String(slot["builder"]).is_empty():
		_fail("bridge '%s' has an empty builder — a roadway 12 m up with no "
				% id + "towers, no cables and no piers is a floating slab")
	var pos: Vector3 = slot["pos"]
	var off := Vector2(pos.x - centre.x, pos.z - centre.y).length()
	if off > RAMP_FLUSH_TOL:
		_fail("bridge '%s': its deck rect is centred at (%.1f, %.1f) but its slot "
				% [id, centre.x, centre.y] + "stands at (%.1f, %.1f), %.1f m away "
				% [pos.x, pos.z, off] + "— the roadway and the towers that are "
				+ "supposed to carry it have come apart")

	# ---- 2. NO DECK MAY MEET A PLATEAU --------------------------------------
	# A plateau is an IMPASSABLE MASSIF with cliffs on every side, floor to lid, so
	# a deck rect that reaches into one buries the foot of an approach inside the
	# rock and puts a vertical face across the only way onto it. There is no
	# gameplay reading of that overlap — it is not "the bridge lands on the hill",
	# because the lid is 34 m above the deck and the only way up is a ramp on the
	# far side. The whole rect is tested and not just the ramps: a deck through a
	# massif is wrong at every metre of it.
	for plateau_v: Variant in BudapestPlan.PLATEAUS:
		var plateau: Dictionary = plateau_v
		if (plateau["rect"] as Rect2).intersects(deck):
			_fail("bridge '%s': its deck rect meets the '%s' massif, which is "
					% [id, String(plateau["id"])] + "solid stone from the ground to "
					+ "its lid at %.0f m — the approach's foot is inside the rock "
					% float(plateau["top"]) + "and there is a cliff across the way "
					+ "onto it")

	# ---- 3. THE TWO RAMPS FIT, AND THEIR FEET ARE ON THE BANK ----------------
	var flat := BudapestPlan.bridge_flat(row)
	if flat.size.x <= 0.0:
		_fail("bridge '%s' is %.0f m long against two %.0f m approaches — the "
				% [id, deck.size.x, BudapestPlan.BRIDGE_RAMP_RUN] + "ramps meet in "
				+ "the middle and there is no level deck at all")
		return
	var driest := INF
	for end_x: float in [deck.position.x, deck.end.x]:
		for k in 5:
			var z := lerpf(deck.position.y, deck.end.y, float(k) / 4.0)
			driest = minf(driest, BudapestPlan.danube_distance(end_x, z))
	if driest < BudapestPlan.DANUBE_HALF_WIDTH + BRIDGE_BANK_MARGIN:
		_fail("bridge '%s': an end of its deck rect reaches %.1f m from the "
				% [id, driest] + "polyline (band %.0f + margin %.0f) — the foot of "
				% [BudapestPlan.DANUBE_HALF_WIDTH, BRIDGE_BANK_MARGIN]
				+ "an approach stands in the water, so there is no dry way on")
	# ...and the deck really does SPAN the river rather than ending mid-channel.
	if terrain.is_river_at(Vector3(deck.position.x - 1.0, 0.0, centre.y)) \
			or terrain.is_river_at(Vector3(deck.end.x + 1.0, 0.0, centre.y)):
		_fail("bridge '%s' does not reach dry ground on both banks — one metre "
				% id + "off an end of the deck is still the river")

	# ---- 4. THE WADE READ ALONG THE CROSSING, AND ITS WET CONTROL ------------
	var dry_samples := 0
	var x := deck.position.x
	while x <= deck.end.x:
		if terrain.is_river_at(Vector3(x, 0.0, centre.y)):
			_fail("bridge '%s' is WET at x = %.0f — a crossing you have to wade "
					% [id, x] + "is not a bridge")
			break
		dry_samples += 1
		x += 1.0
	# The WET CONTROL: step off the parapet until the point is on no dry rect at
	# all, and the first such point has to be river. Stepping rather than probing
	# once is Margaret Island's fault and is the mechanism working — that deck runs
	# ACROSS the island, so two metres off its parapet is still authored dry land,
	# and a fixed probe would report the bridge's own cutout as a fairway. So the
	# statement is "the water starts again as soon as the AUTHORED dry stops", and
	# a side that never leaves dry ground inside the reach abstains.
	var wet_control := 0
	var probes := 0
	for side: float in [-1.0, 1.0]:
		var out := BRIDGE_WET_PROBE
		while out <= BRIDGE_WET_PROBE_REACH:
			var z := centre.y + side * (deck.size.y * 0.5 + out)
			if not BudapestPlan.is_dry(centre.x, z):
				probes += 1
				if terrain.is_river_at(Vector3(centre.x, 0.0, z)):
					wet_control += 1
				else:
					_fail("bridge '%s': %.0f m off its parapet at (%.0f, %.0f) is "
							% [id, out, centre.x, z] + "neither a dry rect nor the "
							+ "river — the cutout is a fairway round the bridge "
							+ "instead of the bridge")
				break
			out += 1.0
	if probes < 1:
		_fail("bridge '%s': neither side of its deck leaves authored dry ground "
				% id + "within %.0f m — the wet control probed nothing and the "
				% BRIDGE_WET_PROBE_REACH + "cutout's edge was never measured")

	# ---- 5. THE SURFACE, ON THE BOXES THE STREAMER ACTUALLY BUILDS -----------
	var lo: Vector2i = terrain.world_to_chunk(Vector3(deck.position.x, 0.0, deck.position.y))
	var hi: Vector2i = terrain.world_to_chunk(Vector3(deck.end.x, 0.0, deck.end.y))
	var boxes := 0
	var shapes := 0
	var worst := 0.0
	var x_spans: Array[Vector2] = []
	var z_spans: Array[Vector2] = []
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var chunk_centre: Vector3 = terrain.chunk_to_world(Vector2i(cx, cz))
			var batch: Array = []
			var body := StaticBody3D.new()
			terrain.spawn_city_bridges_in_chunk(chunk_centre, batch, body)
			for entry_v: Variant in batch:
				var entry: Dictionary = entry_v
				var xf: Transform3D = entry["transform"]
				var wx := xf.origin.x + chunk_centre.x
				var wz := xf.origin.z + chunk_centre.z
				# A chunk square can meet two bridges' rects at a corner, so the
				# box is homed by its own centre — the streamer's own rule.
				if wx < deck.position.x or wx > deck.end.x \
						or wz < deck.position.y or wz > deck.end.y:
					continue
				boxes += 1
				var span := Vector2(INF, -INF)
				if absf(xf.basis.y.normalized().y - 1.0) > 0.0001:
					# A RAMP, measured exactly as check 11 measures a plateau's:
					# the top surface's two end points on the slab's centre line,
					# with the X SPAN taken on the MID-HEIGHT end faces (tilting
					# slides the top face along X, and two slabs that meet
					# perfectly still read as a gap if it is measured up there).
					var up := xf.basis.y * 0.5
					for sign: float in [-1.0, 1.0]:
						var p: Vector3 = xf.origin + up + xf.basis.z * (0.5 * sign)
						worst = maxf(worst, absf(p.y - BudapestPlan.bridge_surface_y(
								row, p.x + chunk_centre.x)))
						var mid: Vector3 = xf.origin + xf.basis.z * (0.5 * sign)
						span = Vector2(minf(span.x, mid.x + chunk_centre.x),
								maxf(span.y, mid.x + chunk_centre.x))
					# The slab's WIDTH runs on local X, which yaw = +-PI/2 lays
					# on world Z — not on basis.z, which is the climb.
					var hz := absf(xf.basis.x.z) * 0.5
					z_spans.append(Vector2(wz - hz, wz + hz))
				else:
					# THE LEVEL SPAN. One height, and it is the WALKING height: the
					# slab hangs under it, so a thickness retune must never move
					# the surface the two ramps meet.
					worst = maxf(worst, absf(xf.origin.y + absf(xf.basis.y.y) * 0.5 - top))
					var hx := absf(xf.basis.x.x) * 0.5
					span = Vector2(wx - hx, wx + hx)
					var hz2 := absf(xf.basis.z.z) * 0.5
					z_spans.append(Vector2(wz - hz2, wz + hz2))
				x_spans.append(span)
			# A DECK YOU FALL THROUGH IS NOT A DECK: every box here collides.
			for child in body.get_children():
				if child is CollisionShape3D:
					shapes += 1
			body.free()

	if boxes < 3:
		_fail("bridge '%s' came out as %d boxes — a %.0f m deck crosses several "
				% [id, boxes, deck.size.x] + "chunks, so this measured the wrong thing")
		return
	if shapes != boxes:
		_fail("bridge '%s' built %d boxes but %d collision shapes — a deck you "
				% [id, boxes, shapes] + "fall through is not a deck")
	if worst > RAMP_FLUSH_TOL:
		_fail("bridge '%s': its surface is %.3f m off BudapestPlan.bridge_surface_y "
				% [id, worst] + "at a slice end — two slices disagree, which is a "
				+ "STEP, and CharacterBody3D cannot climb one at all")
	var gap_x := _span_gap(x_spans, deck.position.x, deck.end.x)
	if gap_x > RAMP_FLUSH_TOL:
		_fail("bridge '%s': its slabs leave a %.3f m gap ALONG the crossing — "
				% [id, gap_x] + "neighbouring chunks' slices do not meet, so there "
				+ "is a hole to fall through in the middle of the river")
	var gap_z := _span_gap(z_spans, deck.position.y, deck.end.y)
	if gap_z > RAMP_FLUSH_TOL:
		_fail("bridge '%s': its slabs leave a %.3f m gap ACROSS the deck — the "
				% [id, gap_z] + "roadway is narrower than the rect the river was "
				+ "punched out by, so its edge is a hole over open water")

	print("bridge '%s': %.0f m deck at y = %.1f (slope %.3f <= %.3f), %d boxes / "
			% [id, deck.size.x, top, slope, ceiling, boxes]
			+ "%d shapes, worst %.3f m off the profile, seam gaps %.3f / %.3f, "
			% [shapes, worst, gap_x, gap_z]
			+ "%d dry samples across, abutments %.0f m out from the polyline"
			% [dry_samples, driest])


func _span_gap(spans: Array[Vector2], from: float, to: float) -> float:
	"""
	The widest hole a set of 1-D intervals leaves in [from, to].

	Check 11's arithmetic, lifted here because the bridges want it on BOTH axes:
	sort by start, walk, and take the worst of (the step from the current reach to
	the next span's start) and (whatever is left over at the end).
	"""
	var sorted: Array[Vector2] = spans.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var reach := from
	var gap := 0.0
	for span: Vector2 in sorted:
		gap = maxf(gap, span.x - reach)
		reach = maxf(reach, span.y)
	return maxf(gap, to - reach)


func _check_margaret_island(terrain: Node3D, claimed: Dictionary) -> void:
	"""
	MARGARET ISLAND IS DRY LAND IN THE RIVER, on the same mechanism as a deck —
	which is the point of DRY_RECTS and the reason this bead needed no machinery
	for it. Three things it has to be: a DRY_RECTS row no bridge claims, dry over
	its whole area, and INSIDE the band. An "island" whose rect reaches the bank is
	a headland, and its cutout is then punching a hole in dry ground for nothing.
	"""
	var island := -1
	for i in range(BudapestPlan.DRY_RECTS.size()):
		if not claimed.has(i):
			island = i
			break
	if island < 0:
		_fail("every DRY_RECTS row is claimed by a bridge deck — Margaret Island "
				+ "has stopped being dry land in the river")
		return
	var r: Rect2 = BudapestPlan.DRY_RECTS[island]
	var wet := 0
	var outside := 0
	for i in range(11):
		for k in range(11):
			var p := Vector2(lerpf(r.position.x, r.end.x, float(i) / 10.0),
					lerpf(r.position.y, r.end.y, float(k) / 10.0))
			if terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
				wet += 1
			if BudapestPlan.danube_distance(p.x, p.y) > BudapestPlan.DANUBE_HALF_WIDTH:
				outside += 1
	if wet > 0:
		_fail("%d of 121 points on Margaret Island answer WET — an island you "
				% wet + "wade across is a shallow, not an island")
	if outside > 0:
		_fail("%d of 121 points on Margaret Island lie OUTSIDE the %.0f m band — "
				% [outside, BudapestPlan.DANUBE_HALF_WIDTH] + "its rect has reached "
				+ "the bank, so it is a headland and its cutout is punching a hole "
				+ "in ground that was already dry")

	# ...and the landmark that names it stands ON it, disc and all.
	var si := _slot_index("margaret_island")
	if si < 0:
		_fail("no 'margaret_island' slot — the island is dry land nobody names")
		return
	var slot: Dictionary = BudapestPlan.SLOTS[si]
	var pos: Vector3 = slot["pos"]
	var rad: float = slot["radius"]
	if pos.x - rad < r.position.x or pos.x + rad > r.end.x \
			or pos.z - rad < r.position.y or pos.z + rad > r.end.y:
		_fail("the Margaret Island landmark's %.0f m disc at (%.0f, %.0f) "
				% [rad, pos.x, pos.z] + "overhangs its island rect — its water "
				+ "tower and its park would stand in the river")

	print("Margaret Island: DRY_RECTS row %d, %.0f x %.0f m, 121/121 points dry "
			% [island, r.size.x, r.size.y] + "and every one inside the band; the "
			+ "landmark's %.0f m disc fits on it" % rad)


func _check_danube_crocodiles(terrain: Node3D) -> void:
	"""
	THE CROCODILE POLICY ALONG THE WHOLE LENGTH — the river read north to south
	rather than sampled at the bend.

	Check 9 already proves the policy is per-system and that a Danube crocodile is
	wet; what it cannot say is that the river is populated END TO END, because its
	stride lands ~60 chunks over a 2.2 km rect and ONE crocodile satisfies it. So
	this walks EVERY wet chunk, buckets them into three by Z, and requires all
	three to answer — the whole 2.2 km of water is the threat line, not its middle.

	It also re-states the deck rule on the BODIES: nothing may stand within
	DANUBE_CROC_DECK_MARGIN of a dry rect, which is what keeps a crocodile out of a
	bridge pier's overhanging stone and off Margaret Island's lawn.
	"""
	var lo: Vector2i = terrain.world_to_chunk(
			Vector3(BudapestPlan.BUDAPEST_MIN.x, 0.0, BudapestPlan.BUDAPEST_MIN.y))
	var hi: Vector2i = terrain.world_to_chunk(
			Vector3(BudapestPlan.BUDAPEST_MAX.x, 0.0, BudapestPlan.BUDAPEST_MAX.y))
	var buckets: Array[int] = []
	for i in DANUBE_BUCKETS:
		buckets.append(0)
	var wet_chunks := 0
	var total := 0
	var near_deck := 0
	var margin: float = terrain.DANUBE_CROC_DECK_MARGIN
	var span: float = BudapestPlan.BUDAPEST_MAX.y - BudapestPlan.BUDAPEST_MIN.y
	for cx in range(lo.x, hi.x + 1):
		for cz in range(lo.y, hi.y + 1):
			var chunk_pos := Vector2i(cx, cz)
			var chunk_centre: Vector3 = terrain.chunk_to_world(chunk_pos)
			if not BudapestPlan.danube_wet(chunk_centre.x, chunk_centre.z):
				continue
			wet_chunks += 1
			var parent := MeshInstance3D.new()
			parent.position = chunk_centre
			root.add_child(parent)
			terrain.spawn_danube_crocodiles_in_chunk(chunk_pos, parent)
			for child in parent.get_children():
				var node := child as Node3D
				if node == null or not node.is_in_group("crocodile"):
					continue
				total += 1
				var world: Vector3 = node.position + chunk_centre
				if terrain._near_dry_rect(world.x, world.z, margin):
					near_deck += 1
					if near_deck <= 3:
						_fail("a Danube crocodile stands within %.0f m of a dry "
								% margin + "rect at (%.0f, %.0f) — inside a bridge "
								% [world.x, world.z] + "pier's stone, or on "
								+ "Margaret Island's lawn")
				var b := clampi(int(float(DANUBE_BUCKETS)
						* (world.z - BudapestPlan.BUDAPEST_MIN.y) / span),
						0, DANUBE_BUCKETS - 1)
				buckets[b] += 1
			parent.free()

	var names: Array[String] = ["northern", "middle", "southern"]
	for i in DANUBE_BUCKETS:
		if buckets[i] < 1:
			_fail("the %s third of the Danube holds no crocodile at all across "
					% names[i] + "%d wet chunks — the policy runs along part of "
					% wet_chunks + "the river and not its whole length")

	print("Danube crocodiles: %d over %d wet chunks along the full 2.2 km, "
			% [total, wet_chunks] + "buckets %s north -> south, %d within %.0f m "
			% [str(buckets), near_deck, margin] + "of a deck or the island")


# ============================================================================
# CHECK 15 — the blocks are a CITY: streets clear, courtyards hollow, coins on
#            the avenues and every bridge
# ============================================================================

func _check_city_blocks(terrain: Node3D) -> void:
	"""
	THE OWNER'S BEAD, MEASURED. "budapest seems really empty, but it is full of
	multi story buildings in fact ... like what we can see on google map walking
	mode" — so the question this check answers is whether the city is FULL, and
	whether filling it broke the two things a filled city can break.

	Four parts, and each is a different way for the feature to be quietly wrong:

	  a. THE PLAN REFUSES WHAT IS ALREADY THERE. Every landmark slot, both
	     plateaus, the gate district and the river must fall in cells
	     block_buildable() says no to — with the count of cells it says YES to
	     printed, because a predicate that refuses everything passes every one of
	     those assertions and ships an empty city.
	  b. NO SOLID PIECE SEVERS A STREET. The bead's own landmine. It is true BY
	     CONSTRUCTION (block_rect insets by the carriageway plus a pavement), and
	     that is exactly why it is worth measuring: a construction argument fails
	     silently the day somebody adds a piece that is not drawn off block_rect.
	     Measured on the COLLISION SHAPES, through each one's own basis, the way
	     check 13 measures the avenue.
	  c. THE COURTYARDS ARE HOLLOW. The other half of "a block is a ring": if a
	     wing's depth ever exceeded half the block, the four would meet in the
	     middle and every block in Budapest would be a solid 44 m cube with a
	     cornice on it.
	  d. THE COINS RIDE THE AVENUES AND EVERY BRIDGE. With a gem at a square, and
	     with every coin on a carriageway — a coin the routes put inside a
	     building would be unreachable, and one that skipped a whole bridge would
	     leave the crossing unrewarded.
	"""
	# ---- a. the plan refuses what is already there ---------------------------
	var buildable := 0
	var scanned := 0
	var lo: Vector2i = BudapestPlan.block_cell(
			BudapestPlan.BUDAPEST_MIN.x, BudapestPlan.BUDAPEST_MIN.y)
	var hi: Vector2i = BudapestPlan.block_cell(
			BudapestPlan.BUDAPEST_MAX.x, BudapestPlan.BUDAPEST_MAX.y)
	for k in range(lo.x, hi.x + 1):
		for m in range(lo.y, hi.y + 1):
			scanned += 1
			if BudapestPlan.block_buildable(Vector2i(k, m)):
				buildable += 1
	if buildable < scanned / 4:
		_fail("only %d of %d city cells are buildable — the owner asked for a "
				% [buildable, scanned] + "city full of buildings and this one is "
				+ "mostly empty lots")

	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		var pos: Vector3 = slot["pos"]
		var at: Vector2i = BudapestPlan.block_cell(pos.x, pos.z)
		if BudapestPlan.block_buildable(at):
			_fail("a city block would be built over landmark '%s' at cell %s"
					% [String(slot["id"]), at])
	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		var c := (row["rect"] as Rect2).get_center()
		if BudapestPlan.block_buildable(BudapestPlan.block_cell(c.x, c.y)):
			_fail("a city block would be built on plateau '%s', which is solid "
					% String(row["id"]) + "stone to its lid")
	var mid_river: Vector2 = BudapestPlan.DANUBE[2]
	if BudapestPlan.block_buildable(BudapestPlan.block_cell(mid_river.x, mid_river.y)):
		_fail("a city block would be built in the middle of the Danube")
	var gate_c := BudapestPlan.DISTRICT.get_center()
	if BudapestPlan.block_buildable(BudapestPlan.block_cell(gate_c.x, gate_c.y)):
		_fail("a city block would be built over the authored gate district")

	# ---- b + c. streets clear, courtyards hollow ----------------------------
	var shapes_seen := 0
	var exempt := 0
	var in_street := 0
	var in_courtyard := 0
	var block_chunk_worst := 0
	var block_chunk_worst_at := Vector2i.ZERO
	for chunk_pos: Vector2i in _rect_chunks(terrain, BLOCK_SWEEP_STRIDE):
		var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
		var built := _build_city_chunk(terrain, chunk_pos)
		var body: StaticBody3D = built["body"]
		var batch: Array = built["batch"]
		if batch.size() > block_chunk_worst:
			block_chunk_worst = batch.size()
			block_chunk_worst_at = chunk_pos
		for child in body.get_children():
			var shape := child as CollisionShape3D
			var box := shape.shape as BoxShape3D
			if box == null:
				continue
			shapes_seen += 1
			var xf: Transform3D = shape.transform
			var e: Vector3 = box.size * 0.5
			var ax := absf(xf.basis.x.x) * e.x + absf(xf.basis.y.x) * e.y + absf(xf.basis.z.x) * e.z
			var az := absf(xf.basis.x.z) * e.x + absf(xf.basis.y.z) * e.y + absf(xf.basis.z.z) * e.z
			var wx := xf.origin.x + centre.x
			var wz := xf.origin.z + centre.z
			var cell: Vector2i = BudapestPlan.block_cell(wx, wz)
			# WHAT THE SWEEP IS ABOUT. The grid is the BLOCKS' contract, and a
			# cell block_buildable() refuses is where bead .3's AUTHORED city
			# stands instead — a landmark's plinth, the gate district's houses, a
			# plateau's massif, a bridge's abutment. Those are placed by hand, are
			# governed by checks 11, 13 and 14, and legitimately reach across a
			# line the block grid draws over them. So a box is judged only when it
			# is homed in a cell the blocks are allowed to fill, and the number of
			# boxes that exemption covers is printed rather than hidden.
			#
			# THE HILLS AND THE DECKS NEED A SECOND, RECT-SHAPED EXEMPTION on top
			# of the cell one, because they are SLICED: a chunk's 10 m slice of
			# Gellért's massif can have its centre in a cell whose own block rect
			# clears the hill by 3 m while the slice reaches across the line. The
			# rect is the honest test for a thing built off a rect.
			if not BudapestPlan.block_buildable(cell) \
					or _on_a_plateau(wx, wz) or _on_a_bridge_deck(wx, wz):
				exempt += 1
				continue
			# THE STREET TEST. A box is only ever judged against the ONE grid line
			# nearest each of its own faces, so this is two comparisons and not a
			# walk of 35 lines: the pitch is wider than any piece a block draws, so
			# a box clear of its nearest carriageway is clear of every other.
			if _in_carriageway(wx, ax, BudapestPlan.GATE.x) \
					or _in_carriageway(wz, az, BudapestPlan.GATE.z):
				in_street += 1
				if in_street <= 3:
					_fail("a solid box at (%.0f, %.0f), %.1f x %.1f m, stands in "
							% [wx, wz, ax * 2.0, az * 2.0] + "a street of the city "
							+ "grid — a block has severed the route past it")
			var yard: Rect2 = BudapestPlan.block_courtyard(cell).grow(-BLOCK_TOUCH_EPS)
			if Rect2(wx - ax, wz - az, ax * 2.0, az * 2.0).intersection(yard).has_area():
				in_courtyard += 1
				if in_courtyard <= 3:
					_fail("a solid box at (%.0f, %.0f) stands in block %s's "
							% [wx, wz, cell] + "COURTYARD — the block is a solid "
							+ "cube, not a ring of buildings")
		body.free()
		(built["parent"] as Node).free()
	if shapes_seen - exempt < 1:
		_fail("check 15's sweep judged no collision shape at all (%d seen, %d in "
				% [shapes_seen, exempt] + "cells nothing may be built on) — the "
				+ "blocks built nothing, so clear streets is not what was measured")

	# ---- d. the coin routes -------------------------------------------------
	var coins := 0
	var gems := 0
	var off_route := 0
	var bridge_coins: Dictionary = {}
	for row_v: Variant in BudapestPlan.BRIDGES:
		bridge_coins[String((row_v as Dictionary)["id"])] = 0
	# One column avenue's worth of chunks, plus every chunk each bridge deck
	# touches — the two things the routes promise, walked rather than asserted.
	var walk: Dictionary = {}
	var cell_m: float = terrain.chunk_size
	var avenue_x: float = BudapestPlan.street_x(BudapestPlan.CITY_AVENUE_EVERY * 4)
	for i in COIN_WALK_CHUNKS:
		var z: float = BudapestPlan.BUDAPEST_MIN.y + float(i) * cell_m
		walk[terrain.world_to_chunk(Vector3(avenue_x, 0.0, z))] = true
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		var x := deck.position.x
		while x <= deck.end.x:
			walk[terrain.world_to_chunk(Vector3(x, 0.0, deck.get_center().y))] = true
			x += cell_m * 0.5

	for chunk_pos_v: Variant in walk.keys():
		var chunk_pos: Vector2i = chunk_pos_v
		var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
		var built := _build_city_chunk(terrain, chunk_pos)
		var parent: MeshInstance3D = built["parent"]
		terrain.spawn_city_coins_in_chunk(chunk_pos, parent, built["obstacles"])
		for child in parent.get_children():
			var pickup := child as Node3D
			if pickup == null or not pickup.is_in_group("coin"):
				continue
			var world: Vector3 = pickup.position + centre
			coins += 1
			if int(pickup.get("value")) > 1:
				gems += 1
			var on_deck := false
			for row_v: Variant in BudapestPlan.BRIDGES:
				if (BudapestPlan.bridge_deck(row_v) as Rect2).has_point(
						Vector2(world.x, world.z)):
					bridge_coins[String((row_v as Dictionary)["id"])] += 1
					on_deck = true
			if on_deck:
				continue
			# EVERY OTHER COIN IS ON A CARRIAGEWAY. A coin the routes dropped
			# inside a block would be standing in a wall, which is the one way an
			# authored reward line can be worse than none at all.
			if not (_on_a_carriageway(world.x, BudapestPlan.GATE.x)
					or _on_a_carriageway(world.z, BudapestPlan.GATE.z)):
				off_route += 1
				if off_route <= 3:
					_fail("a city coin at (%.0f, %.0f) is on no street of the "
							% [world.x, world.z] + "grid — the routes have put a "
							+ "pickup inside a building")
		(built["body"] as Node).free()
		parent.free()

	if coins < 1:
		_fail("the city's coin routes laid no coin at all over %d chunks of one "
				% walk.size() + "avenue and four bridges — Pest is still the "
				+ "1.4 km with no coin source bead .3 left behind")
	if gems < 1:
		_fail("no gem anywhere on the walked avenue — the squares where two "
				+ "avenues cross are supposed to be worth stopping at")
	for id_v: Variant in bridge_coins.keys():
		if int(bridge_coins[id_v]) < 1:
			_fail("bridge '%s' carries no coin at all — 'coins ... across every "
					% String(id_v) + "bridge' is the bead's own wording")

	print("blocks: %d of %d city cells filled, %d of %d swept collision shapes "
			% [buildable, scanned, shapes_seen - exempt, shapes_seen]
			+ "judged (every %dth chunk), %d in a street and %d in a courtyard; "
			% [BLOCK_SWEEP_STRIDE, in_street, in_courtyard]
			+ "densest city chunk %d boxes at %s"
			% [block_chunk_worst, block_chunk_worst_at])
	print("city coins: %d over %d walked chunks (%d gems), %s on the four decks, "
			% [coins, walk.size(), gems, str(bridge_coins.values())]
			+ "%d off the grid" % off_route)


func _in_carriageway(w: float, half_extent: float, origin: float) -> bool:
	"""Does a box centred at `w` with this half-extent reach into the 16 m
	carriageway around the NEAREST grid line? The nearest line is enough: the
	pitch (62 m) is wider than any piece a block draws, so a box clear of its own
	nearest line is clear of all of them."""
	var line := origin + roundf((w - origin) / BudapestPlan.STREET_PITCH) \
			* BudapestPlan.STREET_PITCH
	return absf(w - line) - half_extent < BudapestPlan.AVENUE_HALF_WIDTH - BLOCK_TOUCH_EPS


func _on_a_carriageway(w: float, origin: float) -> bool:
	"""Is this world coordinate ON the carriageway of its nearest grid line — the
	POINT form of _in_carriageway, for a coin rather than a box."""
	return _in_carriageway(w, 0.0, origin)


func _on_a_plateau(x: float, z: float) -> bool:
	"""Is this world XZ standing on one of the two hills, or on its ramp? The
	street sweep's second exemption — see the call site."""
	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		if (row["rect"] as Rect2).has_point(Vector2(x, z)) \
				or (row["ramp"] as Rect2).has_point(Vector2(x, z)):
			return true
	return false
