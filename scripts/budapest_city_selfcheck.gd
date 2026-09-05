extends SceneTree
## Headless self-check: THE CITY THE CHUNKS ACTUALLY BUILD — you can walk it, it
## is full of buildings, and the four bridges get you dry across the Danube.
##
##   godot --headless --path . --script res://scripts/budapest_city_selfcheck.gd
##
## THE OTHER HALF IS `scripts/budapest_selfcheck.gd`: the PLAN (purity, well
## formed), the STREAMING contract (regeneration, budgets, slicing, CPU/GPU
## parity, determinism) and the seams to the seeded world (the approach corridor,
## the road's consumers, the spawner policy, the difficulty clamp). The two were
## ONE 4,100-line file until bead `godot-test1-ftn.13` split them by check family,
## and the split is mechanical — every check below is the code it always was,
## stamping the name it always stamped. They are separate FILES and not separate
## measurements: CI's `selfcheck-shard` globs `scripts/*_selfcheck.gd` and shards
## by count, so a file that is a third of the suite's wall clock on its own is a
## shard nothing can balance.
##
## ============================ WHAT IT GUARDS ============================
##
## The numbering is the original file's and stays that way, because the check
## numbers are quoted in CLAUDE.md, in the bead trail and in every failure message:
##
##  11. THE PLATEAU RAMPS. The only way onto a hill. A ramp too steep, hanging
##      above y = 0, or whose slices disagree at a seam is a hill you cannot
##      climb — and the four landmarks on the two lids are unreachable with it.
##  13. THE AVENUE IS WALKABLE. The one corridor bead .3 promises: gate to west
##      bank, nothing solid standing in it.
##  14. THE FOUR BRIDGES. Each deck bound to the SLOTS row its pylons stand on,
##      both abutments on the bank, the crossing DRY metre by metre with a wet
##      control off the parapet, and the surface the chunks really build measured
##      against the plan's profile. Plus Margaret Island dry and inside the band,
##      the Danube's crocodiles bucketed north/middle/south, and NOTHING STANDING
##      IN THE RIVER OR IN A MASSIF — with a mutation control that runs a shipped
##      builder mid-channel.
##  15. THE CITY IS FULL, AND STILL A CITY (bead godot-test1-8gw.9). Every block
##      of the grid the plan does not reserve is filled with a street wall, which
##      is ~1,250 buildings and four ways to be quietly wrong: a block over a
##      landmark, a facade standing in a street, a courtyard filled solid, and a
##      coin route that drops pickups inside a wall or skips a bridge. The COST
##      half of that bead — the web residency window — stayed with check 4 in
##      `budapest_selfcheck`, because it is a statement about streaming.
##  16. REACHABILITY. One hero, no ability: every slot flood-reachable from the
##      gate over streets, decks, ramps and plateau tops, height-gated at
##      PROP_MAX_STEP, with two negative controls.
##
## Deliberately NOT covered: how any of it LOOKS. This file measures the
## contracts; the eye measures the rest.
##
## The "RID allocations … were leaked at exit" lines after the verdict are the
## engine reporting this project's deliberate static shared caches (the shared
## unit box mesh, the crocodile/coin PackedScenes). They are not a failure — the
## same note enemy_spawn_selfcheck.gd's header carries.

const TERRAIN_PATH: String = "res://scripts/endless_terrain.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"

## The one seed every check here runs under. The city is authored, so the seed is
## irrelevant BY THE PROPERTY UNDER TEST — proving THAT is `budapest_selfcheck`'s
## checks 3 and 18, which is why they kept the second seed and this file needs one.
const RUN_SEED: int = 20260902

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

## How far check 15 lets the walked avenue's coin count stray from what
## CITY_STREET_COIN_SPACING owes it. Wide, because the walk crosses landmarks,
## a plateau and the gate corridor, each of which legitimately eats coins —
## these bound the ORDER of the density, which is the only thing the owner's
## "really rare" is a statement about. A revert to the corridor's 8 m pitch is
## eight times the ceiling, not a few percent over it.
const COIN_PITCH_TOLERANCE_LO: float = 0.5
const COIN_PITCH_TOLERANCE_HI: float = 1.6

## The floor under CITY_STREET_COIN_SPACING itself — the owner's 2026-09-04
## "coins should be really rare in Budapest" as a number. It is separate from the
## tolerances above because those are DERIVED from that constant and would follow
## it back down to the corridor's 8 m without a word.
const CITY_STREET_COIN_MIN_PITCH: float = 32.0

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

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	_boot()


func _boot() -> void:
	# ONE FRAME BEFORE ANYTHING, for the reason enemy_spawn_selfcheck.gd gives: a
	# node added to `root` from inside _initialize() is not `is_inside_tree()`
	# until the first frame, and several spawners here read a global transform.
	await process_frame
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_PATH)

	var terrain := _make_terrain(RUN_SEED)
	_check_ramps(terrain)
	_check_avenue(terrain)
	_check_bridges(terrain)
	_check_city_blocks(terrain)
	_check_reachability(terrain, terrain_script)
	terrain.free()

	_report()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


# ============================================================================
# HARNESS — the same four helpers budapest_selfcheck.gd carries, duplicated
# rather than shared: a self-check reaching into another self-check is a
# dependency between two files that are each meant to be readable on their own.
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


func _build_city_chunk(terrain: Node3D, chunk_pos: Vector2i, include_coins: bool = false) -> Dictionary:
	"""
	Run the city streamer over ONE chunk into fresh receptacles.

	@param terrain: a terrain with its run seed already forced
	@param chunk_pos: the chunk to build
	@param include_coins: if true, coins are built inside the timed window
	@return { parent, batch, body, obstacles, msec, coin_parent? } — THE CALLER
	        FREES `parent`, `body` and `coin_parent` if present.

	Only spawn_city_in_chunk, because inside the rect that is the only thing that
	builds anything (the spawner policy is what check 9 measures). `parent` is
	positioned at the chunk's world origin the way create_chunk's is, so anything
	that reads a global transform sees the truth. Coins are built on a separate
	coin_parent so the accent/Area3D check on parent does not see them.
	"""
	var parent := MeshInstance3D.new()
	parent.position = terrain.chunk_to_world(chunk_pos)
	root.add_child(parent)
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = []
	var coin_parent: MeshInstance3D = null
	if include_coins:
		coin_parent = MeshInstance3D.new()
		root.add_child(coin_parent)
		coin_parent.position = terrain.chunk_to_world(chunk_pos)
	var t0 := Time.get_ticks_usec()
	terrain.spawn_city_in_chunk(chunk_pos, parent, obstacles, batch, body)
	if include_coins:
		terrain.spawn_city_coins_in_chunk(chunk_pos, coin_parent, obstacles)
	var msec := float(Time.get_ticks_usec() - t0) / 1000.0
	var out := {"parent": parent, "batch": batch, "body": body,
			"obstacles": obstacles, "msec": msec}
	if include_coins:
		out["coin_parent"] = coin_parent
	return out


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
	# THE SAME SCRIPT OBJECT THE STREAMER DISPATCHES THROUGH (bd
	# `godot-test1-ftn.17`): a builder is a METHOD-NAME STRING, and
	# `CityBuilders.call(...)` on the class_name is a parse error.
	BudapestStreamer.CITY_BUILDERS.call(String(slot["builder"]), terrain, center, rng,
			chunk, batch, body)
	ChunkBatch.split_city_boxes_on_chunk_grid(terrain, chunk_center, batch, body)
	return {"batch": batch, "body": body, "chunk": chunk,
			"accents": chunk.get_child_count()}


func _free_builder(built: Dictionary) -> void:
	(built["body"] as Node).free()
	(built["chunk"] as Node).free()


# ============================================================================
# CHECK 6 — CPU/GPU parity: the band you see is the band you wade
# ============================================================================


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
	Sentinel.done("ramps")


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
	Sentinel.done("avenue")


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
	city_builders.gd's, standing on the SLOTS row of the same id; the deck is
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
	Sentinel.done("bridges")


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
	Sentinel.done("nothing_stands_in_the_river")


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
		Sentinel.done("river_rule_control")
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
	Sentinel.done("river_rule_control")


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
		Sentinel.done("no_reward_under_a_deck")
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
	Sentinel.done("no_reward_under_a_deck")


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
	Sentinel.done("bridge_profile_control")


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
		Sentinel.done("one_bridge")
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
		Sentinel.done("one_bridge")
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
		Sentinel.done("one_bridge")
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
	Sentinel.done("one_bridge")


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
		Sentinel.done("margaret_island")
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
		Sentinel.done("margaret_island")
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
	Sentinel.done("margaret_island")


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
	Sentinel.done("danube_crocodiles")


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
	  d. THE COINS RIDE THE AVENUES AND EVERY BRIDGE, AT THE PITCH THE PLAN
	     DECLARES. With a gem at a square, and with every coin on a carriageway —
	     a coin the routes put inside a building would be unreachable, and one
	     that skipped a whole bridge would leave the crossing unrewarded. Since
	     bead godot-test1-1qm the walked avenue's count is also held between a
	     floor and a CEILING derived from CITY_STREET_COIN_SPACING: the owner's
	     "coins should be really rare in Budapest" is a statement about density,
	     and only a ceiling can fail a return to the 8 m carpet.
	"""
	var consts := (terrain.get_script() as GDScript).get_script_constant_map()

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

	# ---- b's NEGATIVE CONTROL, which every sibling check in this file carries --
	# "0 boxes in a street" is a COUNT THAT STAYS ZERO whether the streets are
	# genuinely clear or the judgement is broken — an exemption that swallowed
	# everything, or an _in_carriageway that always answered false, both pass the
	# loop above in silence. So one deliberately street-cutting building is put
	# through the SAME judgement and must be caught.
	#
	# Driven on the predicate rather than on a rebuilt world, because the predicate
	# IS the judgement: the loop above only feeds it each shape's world centre and
	# half-extents, which is exactly what these two lines hand it.
	var cut_line: float = BudapestPlan.street_x(BudapestPlan.CITY_AVENUE_EVERY * 4)
	if not _in_carriageway(cut_line, 4.0, BudapestPlan.GATE.x):
		_fail("check 15's negative control was NOT caught: a 8 m wall straddling "
				+ "the grid line at x = %.0f reads as clear of the street, so the "
				% cut_line + "sweep's zero above measures nothing")
	# ...and the matching POSITIVE control, so the predicate is not simply always
	# true: a facade standing where the blocks really put it, one pavement back
	# from the kerb, must read as clear.
	var facade := cut_line + BudapestPlan.AVENUE_HALF_WIDTH \
			+ BudapestPlan.BLOCK_PAVEMENT + BudapestPlan.BLOCK_WING_DEPTH * 0.5
	if _in_carriageway(facade, BudapestPlan.BLOCK_WING_DEPTH * 0.5, BudapestPlan.GATE.x):
		_fail("check 15's positive control failed: a wing sitting exactly where "
				+ "block_rect puts it reads as standing in the street, so the "
				+ "sweep would fail on every building in Budapest")

	# ---- d's GEOMETRY: no band may reach the carriageway --------------------
	# THE AWNING IS THE WIDEST THING A FACADE HANGS OVER THE PAVEMENT, and the
	# only reason a coin on the avenue is not underneath one is that
	# BLOCK_PAVEMENT is wider than it. That is arithmetic, so it is asserted as
	# arithmetic rather than left as a comment somebody has to find: widen any
	# proud past the pavement and the routes start stranding pickups under stone,
	# with nothing on screen to say so.
	var widest: float = maxf(maxf(consts["CITY_AWNING_PROUD"], consts["CITY_BALCONY_PROUD"]),
			maxf(consts["CITY_CORNICE_PROUD"], consts["CITY_SHOPFRONT_PROUD"]))
	if widest >= BudapestPlan.BLOCK_PAVEMENT:
		_fail("the widest facade band stands %.2f m proud against a %.2f m "
				% [widest, BudapestPlan.BLOCK_PAVEMENT] + "pavement — it reaches "
				+ "the carriageway, so an avenue coin can end up under it and the "
				+ "street sweep above has decoration to exempt")

	# ---- d. the coin routes -------------------------------------------------
	var coins := 0
	var gems := 0
	var avenue_coins := 0
	var off_route := 0
	var bridge_coins: Dictionary = {}
	for row_v: Variant in BudapestPlan.BRIDGES:
		bridge_coins[String((row_v as Dictionary)["id"])] = 0
	# One column avenue's worth of chunks, plus every chunk each bridge deck
	# touches — the two things the routes promise, walked rather than asserted.
	# The dictionary's VALUE is "this chunk is on the walked avenue column", which
	# is what lets the pitch assertion below count that column's own coins and
	# nothing else — a bridge chunk carries other avenues and a whole deck line.
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
			var at: Vector2i = terrain.world_to_chunk(Vector3(x, 0.0, deck.get_center().y))
			walk[at] = bool(walk.get(at, false))
			x += cell_m * 0.5

	for chunk_pos_v: Variant in walk.keys():
		var chunk_pos: Vector2i = chunk_pos_v
		var on_walked_avenue: bool = bool(walk[chunk_pos_v])
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
			if on_walked_avenue \
					and absf(world.x - avenue_x) <= BudapestPlan.AVENUE_HALF_WIDTH:
				avenue_coins += 1
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
				+ "GEM avenues cross are supposed to be worth stopping at")
	# A LINE ACROSS EVERY BRIDGE, and "a line" is now measured against the deck's
	# own length rather than being one coin at the abutment (bead
	# godot-test1-1qm). "At least one" survived a pitch of 12.8 km in a mutation
	# test, which is a coin on each bridge and a crossing rewarded nowhere.
	for row_v: Variant in BudapestPlan.BRIDGES:
		var row: Dictionary = row_v
		var id := String(row["id"])
		var owed := (BudapestPlan.bridge_deck(row_v) as Rect2).size.x \
				/ BudapestPlan.CITY_STREET_COIN_SPACING
		var floor_n := maxi(1, floori(owed * COIN_PITCH_TOLERANCE_LO))
		if int(bridge_coins[id]) < floor_n:
			_fail("bridge '%s' carries %d coins over a %.0f m deck, under the %d "
					% [id, int(bridge_coins[id]),
							(BudapestPlan.bridge_deck(row_v) as Rect2).size.x, floor_n]
					+ "a %.0f m pitch owes it — 'coins ... across every bridge' "
					% BudapestPlan.CITY_STREET_COIN_SPACING
					+ "is the bead's own wording, and one coin is not a line")

	# ...AND THE PITCH IS THE DESIGN, SO THE PITCH IS WHAT IS MEASURED (bead
	# godot-test1-1qm, owner: "coins should be really rare in Budapest").
	# "At least one coin somewhere" was just as happy with the 8 m carpet the
	# city shipped with as with the rarity that replaced it, so the walked
	# avenue's own coins are counted against the pitch they are laid at. BOTH
	# ENDS ARE LOAD-BEARING and for opposite reasons: the FLOOR is the old
	# promise (an avenue you follow must actually pay), and the CEILING is the
	# new one — it is the only thing here that goes red if the pitch is ever
	# put back to the corridor's, which is exactly the regression the owner
	# asked to be rid of. The expectation is DERIVED from the shipped constant
	# rather than written down, so a future retune moves one number and this
	# check follows it.
	#
	# THE CONSTANT ITSELF IS ASSERTED FIRST, and it has to be: everything below
	# is DERIVED from it, so a one-character edit putting it back to 8 would
	# retune the expectation with it and pass in silence. This line is the owner
	# ruling written as a number the build can check.
	if BudapestPlan.CITY_STREET_COIN_SPACING < CITY_STREET_COIN_MIN_PITCH:
		_fail("CITY_STREET_COIN_SPACING is %.0f m, under the %.0f m floor the "
				% [BudapestPlan.CITY_STREET_COIN_SPACING, CITY_STREET_COIN_MIN_PITCH]
				+ "owner's 'coins should be really rare in Budapest' put on it "
				+ "— the city is a carpet of pickups again")
	var span := float(COIN_WALK_CHUNKS) * cell_m
	var expect := span / BudapestPlan.CITY_STREET_COIN_SPACING
	if float(avenue_coins) < expect * COIN_PITCH_TOLERANCE_LO:
		_fail("the walked avenue carries %d coins over %.0f m, under the %.1f "
				% [avenue_coins, span, expect * COIN_PITCH_TOLERANCE_LO]
				+ "a %.0f m pitch owes it — an avenue is a route the player "
				% BudapestPlan.CITY_STREET_COIN_SPACING
				+ "follows, and one that pays nothing is not one")
	if float(avenue_coins) > expect * COIN_PITCH_TOLERANCE_HI:
		_fail("the walked avenue carries %d coins over %.0f m, over the %.1f a "
				% [avenue_coins, span, expect * COIN_PITCH_TOLERANCE_HI]
				+ "%.0f m pitch allows — Budapest is carpeted again, which is "
				% BudapestPlan.CITY_STREET_COIN_SPACING
				+ "the owner's 'coins should be really rare' undone")

	print("blocks: %d of %d city cells filled, %d of %d swept collision shapes "
			% [buildable, scanned, shapes_seen - exempt, shapes_seen]
			+ "judged (every %dth chunk), %d in a street and %d in a courtyard; "
			% [BLOCK_SWEEP_STRIDE, in_street, in_courtyard]
			+ "densest city chunk %d boxes at %s"
			% [block_chunk_worst, block_chunk_worst_at])
	print("city coins: %d over %d walked chunks (%d gems), %s on the four decks, "
			% [coins, walk.size(), gems, str(bridge_coins.values())]
			+ "%d off the grid; %d on the walked avenue over %.0f m "
			% [off_route, avenue_coins, span]
			+ "(a %.0f m pitch owes %.1f, tolerated %.1f-%.1f)"
			% [BudapestPlan.CITY_STREET_COIN_SPACING, expect,
					expect * COIN_PITCH_TOLERANCE_LO, expect * COIN_PITCH_TOLERANCE_HI])
	Sentinel.done("city_blocks")


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


# ============================================================================
# CHECK 16 — REACHABILITY: one hero, no jump gate, all 22 slots flood-fill
# ============================================================================

## How fine the reachability grid is, in metres. 4 m gives ~550 per side over the
## 2.2 km rect (302 k cells) — fine enough that a 16 m carriageway is four cells
## across and the 12 m bridge ramps are three, and coarse enough that the flood
## over the whole city is a few hundred milliseconds. Half the cell must clear the
## street half-width, otherwise a street would be one cell wide and a single
## rounding error severs it.
const REACH_CELL: float = 4.0

## Anything higher than this is a ramp or a cliff, never a step. 2.6 m is
## PROP_MAX_STEP — the one jump every hero can do without wind or shrink — and
## the apex 3.6125 is the height a jump can never demand.
const REACH_MAX_STEP: float = 2.6


func _check_reachability(terrain: Node3D, terrain_script: GDScript) -> void:
	"""
	Check 16. With ONE hero left (any of the four) and no ability, no jump gate:
	every one of the 22 landmark slots flood-fill reachable from the gate over
	the plan's walkable cells (streets, bridge decks, ramps, plateau tops) with
	every block and builder footprint treated as stone, and every step ≤ 2.6 m
	or a ramp within PLAN_RAMP_MAX_SLOPE. Negative control: a deliberately
	severed copy of a street must FAIL.
	"""
	var ceiling: float = TowerInterior.PLAN_RAMP_MAX_SLOPE
	var prop_step: float = terrain_script.get_script_constant_map()["PROP_MAX_STEP"]
	if not is_equal_approx(prop_step, REACH_MAX_STEP):
		_fail("PROP_MAX_STEP is %.2f but REACH_MAX_STEP is %.2f — the audit's "
				% [prop_step, REACH_MAX_STEP] + "step ceiling has drifted from the build's")

	# ---- the walkable grid --------------------------------------------------
	var gx := int(ceil((BudapestPlan.BUDAPEST_MAX.x - BudapestPlan.BUDAPEST_MIN.x) / REACH_CELL))
	var gz := int(ceil((BudapestPlan.BUDAPEST_MAX.y - BudapestPlan.BUDAPEST_MIN.y) / REACH_CELL))
	var walkable: Array[bool] = []
	var heights: Array[float] = []
	walkable.resize(gx * gz)
	heights.resize(gx * gz)
	var walk_count := 0
	for iz in range(gz):
		for ix in range(gx):
			var x := BudapestPlan.BUDAPEST_MIN.x + (float(ix) + 0.5) * REACH_CELL
			var z := BudapestPlan.BUDAPEST_MIN.y + (float(iz) + 0.5) * REACH_CELL
			var h := _reach_height_at(x, z)
			var w := _reach_walkable_cell(x, z)
			if w and _reach_blocked_by_landmark(x, z):
				w = false
			var idx := iz * gx + ix
			walkable[idx] = w
			heights[idx] = h
			if w:
				walk_count += 1

	# ---- stone from every city block / prop footprint (bead .7 + .6a–c) --------
	# Check 17 already walks _rect_chunks; reuse the same builder output here as
	# the shared footprint currency (obstacles {pos, radius, top, climbable}).
	# Rasterize each disc into the grid as stone unless it is a climbable perch
	# at or below the step (a roof you can hop onto in one jump is not a wall).
	var stone_cells := 0
	for chunk_pos: Vector2i in _rect_chunks(terrain):
		var built := _build_city_chunk(terrain, chunk_pos)
		var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
		for ob_v: Variant in built["obstacles"] as Array:
			var ob: Dictionary = ob_v
			if bool(ob.get("climbable", false)) and float(ob.get("top", 0.0)) <= REACH_MAX_STEP:
				continue
			var world_pos: Vector3 = ob["pos"] as Vector3
			var wx := world_pos.x + centre.x
			var wz := world_pos.z + centre.z
			var r: float = ob["radius"]
			# Rasterize this disc into the grid. Streets are the walkable
			# network and must stay clear: a footprint that would otherwise
			# cover a carriageway is the wall's disc reaching into the street
			# by ~2 m, but the street centre itself is still walkable by
			# construction (block_rect inset). Skip cells that are on a
			# carriageway so the audit does not sever the city with its own
			# walls.
			var ix0 := clampi(int(floor((wx - r - BudapestPlan.BUDAPEST_MIN.x) / REACH_CELL)), 0, gx - 1)
			var ix1 := clampi(int(floor((wx + r - BudapestPlan.BUDAPEST_MIN.x) / REACH_CELL)), 0, gx - 1)
			var iz0 := clampi(int(floor((wz - r - BudapestPlan.BUDAPEST_MIN.y) / REACH_CELL)), 0, gz - 1)
			var iz1 := clampi(int(floor((wz + r - BudapestPlan.BUDAPEST_MIN.y) / REACH_CELL)), 0, gz - 1)
			for iz_s in range(iz0, iz1 + 1):
				for ix_s in range(ix0, ix1 + 1):
					var cx := BudapestPlan.BUDAPEST_MIN.x + (float(ix_s) + 0.5) * REACH_CELL
					var cz := BudapestPlan.BUDAPEST_MIN.y + (float(iz_s) + 0.5) * REACH_CELL
					if Vector2(cx - wx, cz - wz).length() < r:
						# Keep the carriageway, ramps, plateau tops and dry
						# rects clear — the wall disc's edge reaches into the
						# street by design, but the street centre must stay
						# walkable or the flood is vacuous. Likewise a ramp
						# and its lid must stay clear or the plateau becomes
						# unreachable in the audit even though the shipped city
						# leaves it open.
						if _on_a_carriageway(cx, BudapestPlan.GATE.x) or _on_a_carriageway(cz, BudapestPlan.GATE.z):
							continue
						if BudapestPlan.plateau_top_at(cx, cz) > 0.0 or _reach_is_ramp_cell(cx, cz) or BudapestPlan.is_dry(cx, cz):
							continue
						var sidx := iz_s * gx + ix_s
						if walkable[sidx]:
							walkable[sidx] = false
							stone_cells += 1
		(built["body"] as Node).free()
		(built["parent"] as Node).free()
	if stone_cells > 0:
		walk_count -= stone_cells
		# Recompute walk_count from the grid to keep it honest for the print.
		walk_count = 0
		for v: bool in walkable:
			if v:
				walk_count += 1

	# ---- flood from the gate ------------------------------------------------
	var gate_ix := clampi(int(floor((BudapestPlan.GATE.x - BudapestPlan.BUDAPEST_MIN.x) / REACH_CELL)), 0, gx - 1)
	var gate_iz := clampi(int(floor((BudapestPlan.GATE.z - BudapestPlan.BUDAPEST_MIN.y) / REACH_CELL)), 0, gz - 1)
	var gate_idx := gate_iz * gx + gate_ix
	if not walkable[gate_idx]:
		_fail("the gate cell %s is not walkable — the flood has nowhere to start"
				% Vector2i(gate_ix, gate_iz))
		Sentinel.done("reachability")
		return

	var visited: Array[bool] = []
	visited.resize(gx * gz)
	for i in range(visited.size()):
		visited[i] = false
	var queue: Array[int] = [gate_idx]
	visited[gate_idx] = true
	var qhead := 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var reached_cells := 1
	while qhead < queue.size():
		var cur: int = queue[qhead]
		qhead += 1
		var cx := cur % gx
		var cz := cur / gx
		var ch := heights[cur]
		var ramp_here := _reach_is_ramp_cell(
				BudapestPlan.BUDAPEST_MIN.x + (float(cx) + 0.5) * REACH_CELL,
				BudapestPlan.BUDAPEST_MIN.y + (float(cz) + 0.5) * REACH_CELL)
		for d: Vector2i in dirs:
			var nx := cx + d.x
			var nz := cz + d.y
			if nx < 0 or nx >= gx or nz < 0 or nz >= gz:
				continue
			var nidx := nz * gx + nx
			if visited[nidx] or not walkable[nidx]:
				continue
			var nh := heights[nidx]
			var ramp_there := _reach_is_ramp_cell(
					BudapestPlan.BUDAPEST_MIN.x + (float(nx) + 0.5) * REACH_CELL,
					BudapestPlan.BUDAPEST_MIN.y + (float(nz) + 0.5) * REACH_CELL)
			var dh := absf(nh - ch)
			if dh > REACH_MAX_STEP and not ramp_here and not ramp_there:
				continue
			# Also enforce ramp slope via per-cell rise: a ramp cell's own
			# neighbours along its length rise ≤ slope * CELL.
			if ramp_here or ramp_there:
				var max_rise := ceiling * REACH_CELL + 0.1
				if dh > max_rise:
					continue
			visited[nidx] = true
			queue.append(nidx)
			reached_cells += 1

	# ---- every slot reachable ------------------------------------------------
	var unreachable: Array[String] = []
	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		var id := String(slot["id"])
		var pos: Vector3 = slot["pos"]
		# The building disc itself is stone, so walkable is false there. Reach
		# means a walkable neighbour within the disc's edge is visited — the
		# hero stands at the door, not inside the nave.
		var found := false
		var best := INF
		for iz2 in range(gz):
			for ix2 in range(gx):
				var idx2 := iz2 * gx + ix2
				if not visited[idx2]:
					continue
				var x2 := BudapestPlan.BUDAPEST_MIN.x + (float(ix2) + 0.5) * REACH_CELL
				var z2 := BudapestPlan.BUDAPEST_MIN.y + (float(iz2) + 0.5) * REACH_CELL
				var d := Vector2(x2 - pos.x, z2 - pos.z).length()
				if d < best:
					best = d
				if d < float(slot["radius"]) + REACH_CELL * 1.5:
					found = true
					break
			if found:
				break
		if not found:
			# Plateau slots: landing on the lid is the reach, even if the
			# footprint blocked the centre. Check a visited walkable cell ON
			# the lid within the disc edge, not a street cell 40 m away at y=0.
			var lid := BudapestPlan.plateau_top_at(pos.x, pos.z)
			if lid > 0.0:
				for iz2 in range(gz):
					for ix2 in range(gx):
						var idx2 := iz2 * gx + ix2
						if not visited[idx2]:
							continue
						var x2 := BudapestPlan.BUDAPEST_MIN.x + (float(ix2) + 0.5) * REACH_CELL
						var z2 := BudapestPlan.BUDAPEST_MIN.y + (float(iz2) + 0.5) * REACH_CELL
						if not is_equal_approx(heights[idx2], lid):
							continue
						if Vector2(x2 - pos.x, z2 - pos.z).length() < float(slot["radius"]) + REACH_CELL * 1.5:
							found = true
							break
					if found:
						break
			# Margaret Island is not a plateau but a dry rect in the river;
			# the landmark disc sits on the island and the walkable ring is the
			# island itself. Check any visited cell on the island dry rect.
			if not found and id == "margaret_island":
				var island_rect: Rect2 = BudapestPlan.DRY_RECTS[4]
				for iz2 in range(gz):
					for ix2 in range(gx):
						var idx2 := iz2 * gx + ix2
						if not visited[idx2]:
							continue
						var x2 := BudapestPlan.BUDAPEST_MIN.x + (float(ix2) + 0.5) * REACH_CELL
						var z2 := BudapestPlan.BUDAPEST_MIN.y + (float(iz2) + 0.5) * REACH_CELL
						if island_rect.has_point(Vector2(x2, z2)):
							found = true
							break
					if found:
						break
		if not found:
			unreachable.append("%s (%.0f,%.0f closest %.1f)" % [id, pos.x, pos.z, best])

	if not unreachable.is_empty():
		_fail("reachability: %d of %d slots not flood-reachable from the gate (%d walkable cells, %d reached): %s"
				% [unreachable.size(), BudapestPlan.SLOTS.size(), walk_count, reached_cells, ", ".join(unreachable)])
	else:
		print("reachability: all %d slots flood-reachable from the gate (%d walkable cells, %d reached, cell %.1f m, step %.1f ramp %.3f)"
				% [BudapestPlan.SLOTS.size(), walk_count, reached_cells, REACH_CELL, REACH_MAX_STEP, ceiling])

	# ---- negative controls --------------------------------------------------
	# Control A: sever ONE real street segment between two slots with a
	# footprint-sized wall (not a 2200-cell guillotine). A building footprint
	# is ~8 m radius, so a disc there blocks one carriageway. Margaret Bridge
	# is the only way onto Margaret Island, so a wall on its deck must strand
	# that island's landmark while leaving the other 21 reachable — the flood
	# must be measuring street connectivity, not just any walkable cell.
	var severed: Array[bool] = walkable.duplicate()
	var severed_count := 0
	var bridge_wall_r := 8.0
	var margaret_deck: Rect2 = BudapestPlan.bridge_deck(BudapestPlan.BRIDGES[0])
	var cx_wall := margaret_deck.get_center().x
	var cz_wall := margaret_deck.get_center().y
	for iz3 in range(gz):
		for ix3 in range(gx):
			var x3 := BudapestPlan.BUDAPEST_MIN.x + (float(ix3) + 0.5) * REACH_CELL
			var z3 := BudapestPlan.BUDAPEST_MIN.y + (float(iz3) + 0.5) * REACH_CELL
			if Vector2(x3 - cx_wall, z3 - cz_wall).length() < bridge_wall_r:
				var idx3 := iz3 * gx + ix3
				if severed[idx3]:
					severed_count += 1
				severed[idx3] = false
	var visited2: Array[bool] = []
	visited2.resize(gx * gz)
	for i in range(visited2.size()):
		visited2[i] = false
	var q2: Array[int] = []
	if walkable[gate_idx] and not severed[gate_idx]:
		q2.append(gate_idx)
		visited2[gate_idx] = true
	var qh2 := 0
	while qh2 < q2.size():
		var cur2: int = q2[qh2]
		qh2 += 1
		var cx2 := cur2 % gx
		var cz2 := cur2 / gx
		var ch2 := heights[cur2]
		var ramp2 := _reach_is_ramp_cell(
				BudapestPlan.BUDAPEST_MIN.x + (float(cx2) + 0.5) * REACH_CELL,
				BudapestPlan.BUDAPEST_MIN.y + (float(cz2) + 0.5) * REACH_CELL)
		for d2: Vector2i in dirs:
			var nx2 := cx2 + d2.x
			var nz2 := cz2 + d2.y
			if nx2 < 0 or nx2 >= gx or nz2 < 0 or nz2 >= gz:
				continue
			var nidx2 := nz2 * gx + nx2
			if visited2[nidx2] or not severed[nidx2]:
				continue
			var nh2 := heights[nidx2]
			var rampn2 := _reach_is_ramp_cell(
					BudapestPlan.BUDAPEST_MIN.x + (float(nx2) + 0.5) * REACH_CELL,
					BudapestPlan.BUDAPEST_MIN.y + (float(nz2) + 0.5) * REACH_CELL)
			var dh2 := absf(nh2 - ch2)
			if dh2 > REACH_MAX_STEP and not ramp2 and not rampn2:
				continue
			if (ramp2 or rampn2) and dh2 > ceiling * REACH_CELL + 0.1:
				continue
			visited2[nidx2] = true
			q2.append(nidx2)

	var still_reached := 0
	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		var pos: Vector3 = slot["pos"]
		for iz4 in range(gz):
			for ix4 in range(gx):
				var idx4 := iz4 * gx + ix4
				if not visited2[idx4]:
					continue
				var x4 := BudapestPlan.BUDAPEST_MIN.x + (float(ix4) + 0.5) * REACH_CELL
				var z4 := BudapestPlan.BUDAPEST_MIN.y + (float(iz4) + 0.5) * REACH_CELL
				if Vector2(x4 - pos.x, z4 - pos.z).length() < float(slot["radius"]) + REACH_CELL * 1.5:
					still_reached += 1
					break
	if still_reached == BudapestPlan.SLOTS.size():
		_fail("reachability negative control A (bridge wall): footprint wall on Margaret Bridge (%d cells) still leaves all %d slots reachable — the flood is not measuring street connectivity at all" % [severed_count, BudapestPlan.SLOTS.size()])
	else:
		print("reachability negative control A: Margaret Bridge wall (%d cells) -> %d/%d still reached (expected <%d)" % [severed_count, still_reached, BudapestPlan.SLOTS.size(), BudapestPlan.SLOTS.size()])

	# Control B: remove one plateau's ramp (Castle Hill). The plateau lid is at
	# 30 m; without its ramp the only way up is a 30 m cliff, which the step
	# rule refuses. The two slots on that lid must become unreachable.
	var ramp_removed: Array[bool] = walkable.duplicate()
	var ramp_cells_removed := 0
	var castle_ramp: Rect2 = (BudapestPlan.PLATEAUS[0] as Dictionary)["ramp"]
	for iz5 in range(gz):
		for ix5 in range(gx):
			var x5 := BudapestPlan.BUDAPEST_MIN.x + (float(ix5) + 0.5) * REACH_CELL
			var z5 := BudapestPlan.BUDAPEST_MIN.y + (float(iz5) + 0.5) * REACH_CELL
			if castle_ramp.has_point(Vector2(x5, z5)):
				var idx5 := iz5 * gx + ix5
				if ramp_removed[idx5]:
					ramp_cells_removed += 1
				ramp_removed[idx5] = false
	var visited3: Array[bool] = []
	visited3.resize(gx * gz)
	for i in range(visited3.size()):
		visited3[i] = false
	var q3: Array[int] = []
	if walkable[gate_idx] and ramp_removed[gate_idx]:
		q3.append(gate_idx)
		visited3[gate_idx] = true
	var qh3 := 0
	while qh3 < q3.size():
		var cur3: int = q3[qh3]
		qh3 += 1
		var cx3 := cur3 % gx
		var cz3 := cur3 / gx
		var ch3 := heights[cur3]
		var ramp3 := _reach_is_ramp_cell(
				BudapestPlan.BUDAPEST_MIN.x + (float(cx3) + 0.5) * REACH_CELL,
				BudapestPlan.BUDAPEST_MIN.y + (float(cz3) + 0.5) * REACH_CELL)
		# If the ramp itself is removed, treat it as not ramp for the height gate
		if castle_ramp.has_point(Vector2(
				BudapestPlan.BUDAPEST_MIN.x + (float(cx3) + 0.5) * REACH_CELL,
				BudapestPlan.BUDAPEST_MIN.y + (float(cz3) + 0.5) * REACH_CELL)):
			ramp3 = false
		for d3: Vector2i in dirs:
			var nx3 := cx3 + d3.x
			var nz3 := cz3 + d3.y
			if nx3 < 0 or nx3 >= gx or nz3 < 0 or nz3 >= gz:
				continue
			var nidx3 := nz3 * gx + nx3
			if visited3[nidx3] or not ramp_removed[nidx3]:
				continue
			var nh3 := heights[nidx3]
			var rampn3 := _reach_is_ramp_cell(
					BudapestPlan.BUDAPEST_MIN.x + (float(nx3) + 0.5) * REACH_CELL,
					BudapestPlan.BUDAPEST_MIN.y + (float(nz3) + 0.5) * REACH_CELL)
			if castle_ramp.has_point(Vector2(
					BudapestPlan.BUDAPEST_MIN.x + (float(nx3) + 0.5) * REACH_CELL,
					BudapestPlan.BUDAPEST_MIN.y + (float(nz3) + 0.5) * REACH_CELL)):
				rampn3 = false
			var dh3 := absf(nh3 - ch3)
			if dh3 > REACH_MAX_STEP and not ramp3 and not rampn3:
				continue
			if (ramp3 or rampn3) and dh3 > ceiling * REACH_CELL + 0.1:
				continue
			visited3[nidx3] = true
			q3.append(nidx3)

	var plateau_still := 0
	var castle_rect: Rect2 = (BudapestPlan.PLATEAUS[0] as Dictionary)["rect"]
	# Grow by the largest slot radius on that hill so a slot whose disc
	# straddles the rect edge is still counted as on the hill when the
	# plan moves.
	var castle_grown := castle_rect.grow(160.0)
	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		if BudapestPlan.plateau_top_at((slot["pos"] as Vector3).x, (slot["pos"] as Vector3).z) <= 0.0:
			continue
		var pos3: Vector3 = slot["pos"]
		if not castle_grown.has_point(Vector2(pos3.x, pos3.z)):
			continue
		for iz6 in range(gz):
			for ix6 in range(gx):
				var idx6 := iz6 * gx + ix6
				if not visited3[idx6]:
					continue
				var x6 := BudapestPlan.BUDAPEST_MIN.x + (float(ix6) + 0.5) * REACH_CELL
				var z6 := BudapestPlan.BUDAPEST_MIN.y + (float(iz6) + 0.5) * REACH_CELL
				if Vector2(x6 - pos3.x, z6 - pos3.z).length() < float(slot["radius"]) + REACH_CELL * 1.5:
					plateau_still += 1
					break
	# Castle Hill has two slots (buda_castle, matthias)
	if plateau_still == 2:
		_fail("reachability negative control B (ramp removed): Castle Hill ramp made stone (%d cells) still leaves both plateau slots reachable — the height gate is not biting" % ramp_cells_removed)
	else:
		print("reachability negative control B: Castle Hill ramp removed (%d cells) -> %d/2 plateau slots still reached (expected <2)" % [ramp_cells_removed, plateau_still])
	Sentinel.done("reachability")


func _reach_walkable_cell(x: float, z: float) -> bool:
	"""Is this XZ walkable at all — before stone."""
	if BudapestPlan.danube_wet(x, z):
		return false
	# Plateau tops, ramps and dry rects (bridge decks + island) are walkable
	# even off the street grid — the city is not only its carriageways.
	if BudapestPlan.plateau_top_at(x, z) > 0.0:
		return true
	if _reach_is_ramp_cell(x, z):
		return true
	if BudapestPlan.is_dry(x, z):
		return true
	if _on_a_carriageway(x, BudapestPlan.GATE.x) or _on_a_carriageway(z, BudapestPlan.GATE.z):
		return true
	# The apron between a street and a ramp foot or a bridge foot and its
	# bank street is open ground (no block, no water) and must be walkable or
	# the plateau/bridge becomes an island. The grid is carriageway-only, but
	# a ramp foot 12–50 m from the nearest street is still the only way onto
	# the hill or across the river, so cells within ~60 m of any ramp,
	# plateau or bridge deck are walkable as open ground. This is the minimal
	# apron that makes the shipped ramps and bridges connect without making
	# the whole city walkable (the old "every city cell walkable" default).
	if _reach_near_ramp_or_plateau(x, z, 60.0):
		return true
	return false


func _reach_near_ramp_or_plateau(x: float, z: float, dist: float) -> bool:
	"""Is this XZ within `dist` of any ramp, plateau or bridge deck? The apron."""
	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		if _rect_point_distance(row["rect"], Vector2(x, z)) < dist:
			return true
		if _rect_point_distance(row["ramp"], Vector2(x, z)) < dist:
			return true
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if _rect_point_distance(deck, Vector2(x, z)) < dist:
			return true
	return false


func _reach_height_at(x: float, z: float) -> float:
	"""Walking height at this XZ: plateau lid, bridge deck, ramp, or 0."""
	var lid := BudapestPlan.plateau_top_at(x, z)
	if lid > 0.0:
		return lid
	for row_v: Variant in BudapestPlan.PLATEAUS:
		var row: Dictionary = row_v
		var ramp: Rect2 = row["ramp"]
		if ramp.has_point(Vector2(x, z)):
			var run := ramp.size.x
			var top: float = row["top"]
			var climbed := clampf((x - ramp.position.x) / run, 0.0, 1.0)
			if int(row["ramp_dir"]) < 0:
				climbed = 1.0 - climbed
			return top * climbed
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if deck.has_point(Vector2(x, z)):
			return BudapestPlan.bridge_surface_y(row_v, x)
	return 0.0


func _reach_is_ramp_cell(x: float, z: float) -> bool:
	"""Is this XZ on any ramp — plateau or bridge approach — where a slope is expected."""
	for row_v: Variant in BudapestPlan.PLATEAUS:
		if (row_v["ramp"] as Rect2).has_point(Vector2(x, z)):
			return true
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if not deck.has_point(Vector2(x, z)):
			continue
		var ramp_w := BudapestPlan.bridge_ramp(row_v, false)
		var ramp_e := BudapestPlan.bridge_ramp(row_v, true)
		if ramp_w.has_point(Vector2(x, z)) or ramp_e.has_point(Vector2(x, z)):
			return true
	return false


func _reach_blocked_by_landmark(x: float, z: float) -> bool:
	"""Is this XZ inside a landmark's disc treated as stone? Bridge slots are
	exempt on their own deck — the roadway is the crossing, the piers are not
	a wall across it. Plateau slots are not exempt: the castle occupies its lid."""
	for slot_v: Variant in BudapestPlan.SLOTS:
		var slot: Dictionary = slot_v
		var pos: Vector3 = slot["pos"]
		var r: float = slot["radius"]
		if Vector2(x - pos.x, z - pos.z).length() >= r:
			continue
		var id := String(slot["id"])
		# Bridge decks: the landmark shares the deck rect; the stone is the
		# pier/tower beside the road, not a wall across it.
		for row_v: Variant in BudapestPlan.BRIDGES:
			if String((row_v as Dictionary)["id"]) == id and BudapestPlan.is_dry(x, z):
				return false
		return true
	return false
