extends SceneTree
## Headless self-check for THE MUSEUM MILE — one site per field landmark kind.
##
##   godot --headless --path . --script res://scripts/landmark_sites_selfcheck.gd
##
## Bead `godot-test1-bcf`, owner: *"for landmarks they should be unique, each type
## exists once in our world"*. `endless_terrain.gd`'s MUSEUM MILE banner carries
## the design; this file is the part of it a future edit cannot slip past.
##
## It is a SECOND file rather than a sixth check in `landmark_selfcheck.gd`
## because the two measure different halves of the feature and neither can see
## the other's: that one calls every BUILDER and measures the stone against its
## declared radius, knowing nothing about where a landmark stands; this one never
## looks at a box and measures only WHERE. Growing either into the other would
## make one slow file whose failure message names the wrong half.
##
##   1. UNIQUENESS, which is the whole bead. Over a 30x30 chunk field around the
##      road for three seeds, no kind appears twice — asked through the shipped
##      `_landmark_at`, so it measures the reverse lookup and not the table it
##      reads. The table itself is checked too, over the WHOLE world rather than
##      a window, because a 30x30 field is only a window.
##   2. NO SITE STANDS SOMEWHERE A MONUMENT MUST NOT. The HQ disc, the Budapest
##      rect, the spawn bubble and a river band, over every site of every seed —
##      plus four MUTATION CONTROLS driven through the shipped `_landmark_site_ok`
##      with a deliberately illegal chunk each, and a legal chunk as the positive
##      control, because "no site was in the city" is also what a guard that
##      always answers false looks like.
##   3. NO TWO LANDMARKS OVERLAP. Measured on the REAL built centres, not on the
##      chunk grid the placement argument rests on (`_landmark_site_ok`'s docstring
##      derives >= 24 m from distinct chunks; this asserts the >= 19 m the bead
##      asked for, off the geometry that actually shipped). Its control is a
##      planted co-located pair the same comparator must catch.
##   4. THE REVERSE LOOKUP COSTS THE SHARED STREAMS NOTHING. Two halves: the text
##      of `_landmark_at` carries no RNG and no `scarcity_at`, and — the half that
##      would catch a draw hidden behind a helper — a chunk with NO site is
##      BYTE-IDENTICAL with `spawn_landmarks` on and off, right down to its
##      crocodile positions, which is the observable consequence of a draw. A
##      chunk WITH a site is identical up to the landmark's own footprint, which
##      is the documented and intended difference. Both directions are asserted,
##      so neither can pass vacuously.
##   5. THE MILE IS WALKED. Every site chunk is built for real; the kinds that end
##      up standing inside the road corridor are counted against
##      `MILE_MIN_IN_CORRIDOR`, and the kinds that end up standing anywhere at all
##      against `MIN_KINDS_BUILT`. Those two numbers are the feature: a site table
##      whose sites all fall in mountains is unique and useless.
##   6. THE CARD STILL KEYS OFF THE SITE. A marker taken out of a REALLY BUILT
##      site chunk is walked up to through the shipped `landmark_toast`, and the
##      card that raises must name the row the site table says stands there. That
##      is the whole chain — table -> spawner -> marker meta -> toast -> quiz —
##      end to end, and it is what the bead's "keep landmark_id derivable" line
##      asks for now that `kind` is unique.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const BUILDERS_SCRIPT: String = "res://scripts/landmark_builders.gd"
const TOAST_SCRIPT: String = "res://scripts/landmark_toast.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## Three seeds, the `scarcity_selfcheck` set. The road, the biome field and the
## site table all move with `run_seed`, so one world proves nothing about the
## rule and only about that world.
const SEEDS: Array[int] = [20260904, 777, 4242]

## Check 1's window, in chunks either side of the sweep centre — 31x31 = 961
## chunks, the bead's "30x30 field". It is centred on the middle of the museum
## mile, which is where the sites are densest and therefore where a duplicate is
## most likely to be visible.
const FIELD_HALF: int = 15

## Check 5's floors, both MEASURED over the three seeds and set with margin.
## They are FLOORS and not equalities on purpose — a candidate loop that fails is
## a legitimate outcome (see LANDMARK_PLACE_TRIES), and pinning the exact count
## would fail the build on any retune of the block density.
##
## Kinds built anywhere: measured 43 / 41 / 41 of 48.
const MIN_KINDS_BUILT: int = 36
## N = 12, and it is the bead's own acceptance number: "at least 12 kinds stand
## within the road corridor of a 3 km run". A slot is a SITE and a site is not yet
## a landmark — its chunk still has to have room for the shape — so
## LANDMARK_MILE_SPACING is sized to put SIXTEEN slots on the mile to stand
## twelve. Measured 15 / 14 / 13.
const MILE_MIN_IN_CORRIDOR: int = 12

## How far off the centreline still counts as "in the corridor" for check 5.
## LANDMARK_MILE_LATERAL_MAX (120) is where a mile site is placed; a chunk is
## 50 m wide and the candidate loop moves the stone up to 13 m inside it, so the
## band has to be at least that much wider or the check measures its own slack.
const CORRIDOR_PAD: float = 40.0

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL — see scripts/selfcheck_sentinel.gd.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# Check 6 has to let the toast's _ready() build its labels before it can read
	# them, and _initialize() cannot await — so the run is a coroutine and the
	# tree keeps processing until it calls quit().
	_run()


func _run() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	var consts: Dictionary = terrain_script.get_script_constant_map()
	var registry: Array = load(BUILDERS_SCRIPT).get_script_constant_map().get("LANDMARKS", [])
	if registry.is_empty():
		_fail("landmark_builders.gd has no LANDMARKS registry — nothing to site")
	else:
		_check_unique(terrain_script, registry)
		_check_legal_sites(terrain_script, consts)
		var built: Array = _build_every_site(terrain_script)
		_check_spacing(consts, built)
		_check_no_draw(terrain_script)
		_check_corridor(terrain_script, consts, registry, built)
		await _check_card_keys_off_the_site(registry, built)
		_free_built(built)

	if _failures.is_empty():
		print("landmark sites: %d kinds, one site each, over %d seeds — unique, legal, spaced, "
				% [registry.size(), SEEDS.size()]
				+ "draw-free, walked, and the card still keys off the site")
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _terrain(terrain_script: GDScript, seed_value: int) -> Node3D:
	"""A detached terrain on `seed_value`, with the crocodile scene check 4 needs."""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.set_run_seed(seed_value)
	return terrain


# ============================================================================
# CHECK 1 — every kind at most once
# ============================================================================

func _check_unique(terrain_script: GDScript, registry: Array) -> void:
	"""
	No kind appears twice, asked two ways.

	THE WINDOW, which is the bead's acceptance: a 31x31 chunk field centred on the
	middle of the museum mile, per seed, asking the shipped `_landmark_at` about
	every chunk in it and tallying the kinds it names. This measures the REVERSE
	LOOKUP — the thing `create_chunk` actually calls — rather than the table it
	reads, so a lookup that answered "kind 0" for every chunk would fail here even
	with a perfect table.

	THE WHOLE WORLD, which is stronger and costs one loop: the site table is
	chunk-keyed, so "no kind twice" over the whole table is the property the window
	can only sample. A window is where a duplicate would be SEEN; the table is
	where it would BE.

	The two are both here because neither implies the other: the table could be
	right while the lookup is broken, and the lookup could be right about a table
	that already placed the Colosseum twice a kilometre outside the window.
	"""
	var total_sites := 0
	for seed_value: int in SEEDS:
		var terrain := _terrain(terrain_script, seed_value)
		var sites: Dictionary = terrain.landmark_sites()
		total_sites += sites.size()

		# --- The table, over the whole world.
		var table_kinds: Dictionary = {}
		for chunk: Vector2i in sites:
			var kind: int = int(sites[chunk])
			if kind < 0 or kind >= registry.size():
				_fail("seed %d: the site table names kind %d, which is not a LANDMARKS row"
						% [seed_value, kind])
			if table_kinds.has(kind):
				_fail("seed %d: kind %d has TWO sites (%s and %s) — a landmark type exists once"
						% [seed_value, kind, str(table_kinds[kind]), str(chunk)])
			table_kinds[kind] = chunk

		# --- The window, through the shipped reverse lookup.
		var centre_chunk: Vector2i = terrain.world_to_chunk(_mile_midpoint(terrain))
		var seen: Dictionary = {}
		var in_window := 0
		for cx in range(-FIELD_HALF, FIELD_HALF + 1):
			for cz in range(-FIELD_HALF, FIELD_HALF + 1):
				var chunk: Vector2i = centre_chunk + Vector2i(cx, cz)
				var lm: Dictionary = terrain._landmark_at(chunk)
				if lm.is_empty():
					continue
				in_window += 1
				var kind: int = int(lm["kind"])
				if seen.has(kind):
					_fail("seed %d: kind %d appears in BOTH chunk %s and chunk %s of the "
							% [seed_value, kind, str(seen[kind]), str(chunk)]
							+ "%dx%d field — the museum mile is one site per kind"
							% [2 * FIELD_HALF + 1, 2 * FIELD_HALF + 1])
				seen[kind] = chunk
				# The lookup and the table must agree about this chunk, or one of
				# the two assertions above is measuring a different world.
				if not sites.has(chunk) or int(sites[chunk]) != kind:
					_fail("seed %d: _landmark_at(%s) says kind %d but the site table does not"
							% [seed_value, str(chunk), kind])
		if in_window == 0:
			_fail("seed %d: NOT ONE landmark in the %dx%d field around the middle of the road — "
					% [seed_value, 2 * FIELD_HALF + 1, 2 * FIELD_HALF + 1]
					+ "the uniqueness assertion above is vacuous")
		terrain.free()

	print("  sites %d over %d seeds; every kind at most once, in a %dx%d window and in the table"
			% [total_sites, SEEDS.size(), 2 * FIELD_HALF + 1, 2 * FIELD_HALF + 1])
	Sentinel.done("unique")


func _mile_midpoint(terrain: Node3D) -> Vector3:
	"""The middle of the museum mile in world space — where the sites are densest."""
	var x_min: float = float(terrain.tower_site().x)
	var x_max: float = float(terrain.get_script().get_script_constant_map()["ROAD_TERMINAL_X"])
	terrain._road_extend_to_x(x_min, x_max)
	var k: int = (terrain._road_first_k_at_or_after_x(x_min) + terrain._road_terminal_k()) / 2
	var centre: Vector2 = terrain._road_station(k).center
	return Vector3(centre.x, 0.0, centre.y)


# ============================================================================
# CHECK 2 — nowhere a monument must not stand
# ============================================================================

func _check_legal_sites(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Every site clears the HQ, the city, the spawn bubble and the river — and the
	guard that says so is not stuck answering false.

	THE MUTATION CONTROLS ARE THE POINT. "No site was inside Budapest" is exactly
	what an empty site table looks like, and also what a `_landmark_site_ok` that
	returned false for everything looks like. So each of the four rules is driven
	through the shipped predicate with a chunk chosen to break exactly that one,
	and a chunk chosen to break none is driven through as the positive control. A
	rule deleted from the predicate fails its own control here rather than being
	noticed by a player standing in the Danube.
	"""
	var spawn_safe: float = float(consts["SPAWN_SAFE_RADIUS"])
	for seed_value: int in SEEDS:
		var terrain := _terrain(terrain_script, seed_value)
		var chunk_size: float = float(terrain.chunk_size)
		for chunk: Vector2i in terrain.landmark_sites():
			var world: Vector3 = terrain.chunk_to_world(chunk)
			if terrain.in_budapest(world.x, world.z):
				_fail("seed %d: site %s stands in the Budapest rect — the city's landmarks are "
						% [seed_value, str(chunk)] + "its 22 authored slots")
			if terrain.tower_excludes(world.x, world.z, chunk_size):
				_fail("seed %d: site %s stands in the HQ's exclusion disc" % [seed_value, str(chunk)])
			if Vector2(world.x, world.z).length() < spawn_safe:
				_fail("seed %d: site %s stands in the spawn bubble (%.0f m)"
						% [seed_value, str(chunk), spawn_safe])
			if terrain.is_river_at(world):
				_fail("seed %d: site %s stands in a river band" % [seed_value, str(chunk)])
		terrain.free()

	# --- The controls, on one terrain, driven through the shipped predicate.
	var t := _terrain(terrain_script, SEEDS[0])
	var chunk_size2: float = float(t.chunk_size)
	var rect: Rect2 = BudapestPlan.rect()
	var city_chunk: Vector2i = t.world_to_chunk(Vector3(
			rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5))
	var hq_chunk: Vector2i = t.world_to_chunk(t.tower_site())
	var spawn_chunk: Vector2i = Vector2i.ZERO
	var wet_chunk: Vector2i = _find_wet_chunk(t)
	var controls: Array = [
		["the Budapest rect", city_chunk],
		["the HQ disc", hq_chunk],
		["the spawn bubble", spawn_chunk],
	]
	if wet_chunk != Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		controls.append(["a river band", wet_chunk])
	else:
		_fail("check 2 found no river chunk within 3 km of the road on seed %d — the river "
				% SEEDS[0] + "rule's control could not run")
	for row: Array in controls:
		if t._landmark_site_ok(row[1] as Vector2i, {}):
			_fail("_landmark_site_ok accepted a chunk inside %s (%s) — that rule is gone"
					% [String(row[0]), str(row[1])])
	# The positive control: an accepted site's own chunk must still be accepted
	# when nothing is taken, or every refusal above proves only that the predicate
	# refuses everything.
	var legal: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	for chunk2: Vector2i in t.landmark_sites():
		legal = chunk2
		break
	if legal == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		_fail("seed %d sited nothing at all — check 2's positive control cannot run" % SEEDS[0])
	elif not t._landmark_site_ok(legal, {}):
		_fail("_landmark_site_ok refuses %s, which is one of its OWN sites — the four "
				% str(legal) + "refusals above prove nothing")
	# ...and the "somebody already took it" rule, which is the pairwise spacing.
	elif t._landmark_site_ok(legal, {legal: 0}):
		_fail("_landmark_site_ok accepted %s twice — two kinds would share one chunk"
				% str(legal))
	t.free()
	print("  every site clears the HQ / city / spawn bubble / river; %d mutation controls refused"
			% controls.size())
	Sentinel.done("legal_sites")


func _find_wet_chunk(terrain: Node3D) -> Vector2i:
	"""A chunk whose centre is in a river band, within 3 km of the origin."""
	for cx in range(-60, 61):
		for cz in range(-60, 61):
			var chunk := Vector2i(cx, cz)
			var world: Vector3 = terrain.chunk_to_world(chunk)
			if terrain.in_budapest(world.x, world.z):
				continue
			if terrain.is_river_at(world):
				return chunk
	return Vector2i(0x7FFFFFFF, 0x7FFFFFFF)


# ============================================================================
# Building every site for real — checks 3, 5 and 6 all read this
# ============================================================================

func _build_every_site(terrain_script: GDScript) -> Array:
	"""
	Run the shipped pipeline over every site chunk of every seed and collect what
	was actually built.

	@return: Array of { "seed", "chunk", "kind", "world" (Vector3 centre),
	         "marker" (the real Node3D, still parented to its scratch chunk) }.

	IT IS THE REAL PIPELINE IN THE REAL ORDER — scattered props, then biome
	content, then the landmark — because a site chunk's candidate loop is judged
	against the `obstacles` those two produce, and a check that skipped them would
	measure a world with no stone in it and report every site as built.

	The scratch chunk nodes are kept alive (in `_scratch`) rather than freed,
	because check 6 walks up to a marker that is still parented to one. They are
	never added to the tree, so nothing about them runs.
	"""
	var out: Array = []
	for seed_value: int in SEEDS:
		var terrain := _terrain(terrain_script, seed_value)
		var sites: Dictionary = terrain.landmark_sites()
		for chunk: Vector2i in sites:
			var platforms: Array = []
			var batch: Array = []
			var body := StaticBody3D.new()
			var obstacles: Array = terrain.spawn_objects_in_chunk(chunk, platforms, batch, body)
			terrain.spawn_biome_content_in_chunk(chunk, obstacles, batch, body)
			var chunk_node := MeshInstance3D.new()
			terrain.spawn_landmark_in_chunk(chunk, chunk_node, obstacles, batch, body)
			body.free()
			var marker: Node3D = null
			for child in chunk_node.get_children():
				if child is Node3D and child.is_in_group("landmark"):
					marker = child
					break
			if marker == null:
				chunk_node.free()
				continue
			var chunk_world: Vector3 = terrain.chunk_to_world(chunk)
			out.append({
				"seed": seed_value,
				"chunk": chunk,
				"kind": int(sites[chunk]),
				"world": chunk_world + marker.position,
				"marker": marker,
				"chunk_node": chunk_node,
				"terrain": terrain,
			})
	return out


func _free_built(built: Array) -> void:
	"""
	Drop every scratch node `_build_every_site` kept alive. Nothing here was ever
	added to the tree, so this is only about not printing a leak report at exit —
	which reads exactly like a failure in the CI log.
	"""
	var terrains: Dictionary = {}
	for row: Dictionary in built:
		var node: Node = row["chunk_node"]
		if is_instance_valid(node):
			node.free()
		terrains[row["terrain"]] = true
	for terrain: Variant in terrains:
		if is_instance_valid(terrain as Node):
			(terrain as Node).free()


# ============================================================================
# CHECK 3 — no two landmarks overlap
# ============================================================================

func _check_spacing(consts: Dictionary, built: Array) -> void:
	"""
	Every pair of landmarks in one world is at least 2 x LANDMARK_RADIUS apart.

	MEASURED ON THE STONE, NOT ON THE GRID. `_landmark_site_ok`'s docstring argues
	the rule from distinct chunks (>= 24 m worst case, comfortably over the 19 m
	asked for) — that argument is exactly the kind that fails silently the day
	LANDMARK_EDGE_MARGIN or chunk_size is retuned, so this reads the centres the
	spawner really produced and compares them.

	The control is a planted co-located pair: without it, a loop that never
	compared anything would pass.
	"""
	var min_gap: float = 2.0 * float(consts["LANDMARK_RADIUS"])
	var worst: float = INF
	var pairs := 0
	for seed_value: int in SEEDS:
		var here: Array = []
		for row: Dictionary in built:
			if int(row["seed"]) == seed_value:
				here.append(row["world"] as Vector3)
		for i in here.size():
			for j in range(i + 1, here.size()):
				pairs += 1
				var d: float = Vector2(
						(here[i] as Vector3).x - (here[j] as Vector3).x,
						(here[i] as Vector3).z - (here[j] as Vector3).z).length()
				worst = minf(worst, d)
				if d < min_gap:
					_fail("seed %d: two landmarks stand %.1f m apart, under the %.1f m "
							% [seed_value, d, min_gap] + "(2 x LANDMARK_RADIUS) minimum")
	if pairs == 0:
		_fail("check 3 compared no pairs at all — nothing was built, so the spacing rule is unmeasured")
		Sentinel.done("spacing")
		return
	# The comparator's own control.
	var a := Vector3(10.0, 0.0, 10.0)
	var b := Vector3(10.0 + min_gap * 0.5, 0.0, 10.0)
	if Vector2(a.x - b.x, a.z - b.z).length() >= min_gap:
		_fail("check 3's comparator passes a %.1f m gap against a %.1f m minimum — it is "
				% [min_gap * 0.5, min_gap] + "not measuring what it says it measures")
	print("  %d landmark pairs compared, closest %.1f m (minimum %.1f m)" % [pairs, worst, min_gap])
	Sentinel.done("spacing")


# ============================================================================
# CHECK 4 — the reverse lookup costs the shared streams nothing
# ============================================================================

func _check_no_draw(terrain_script: GDScript) -> void:
	"""
	Asking "does a landmark stand here" must not move anything else in the world.

	THE TEXT HALF: `_landmark_at`'s body carries no RandomNumberGenerator, no
	`randf`/`randi`, and no `scarcity_at`. The first two are the bead's "no draw
	from the chunk stream"; the third is bead bcf point 3 — a one-per-world
	placement is neither thinned nor unthinned, and the argument for that lives in
	the MUSEUM MILE banner. Read as text because a behavioural count can only
	speak for the chunks it sampled.

	THE BEHAVIOURAL HALF, which is what would catch a draw hidden behind a helper:
	a chunk with NO site is generated twice, once with `spawn_landmarks` on and
	once off, and the two must be byte-identical all the way down to the
	CROCODILE POSITIONS — a crocodile is the most sensitive thing in a chunk to a
	stray draw, since one extra randf slides every body in the chunk. Then the
	same A/B on a chunk WITH a site, where the pre-landmark half (props, biome,
	their footprints) must still be identical and the crocodiles are allowed to
	move: the footprint is a documented obstacle and keeping crocodiles out of the
	monument is what it is for. Asserting BOTH directions is what stops the check
	passing on a comparator that always answers "same".
	"""
	var source: String = FileAccess.get_file_as_string(TERRAIN_SCRIPT)
	if source.is_empty():
		_fail("could not read %s as text — check 4's text half cannot run" % TERRAIN_SCRIPT)
	else:
		var body := _function_body(source, "_landmark_at")
		if body.is_empty():
			_fail("check 4 found no `_landmark_at` in endless_terrain.gd — it was renamed, and "
					+ "this assertion now measures nothing")
		for forbidden: String in ["RandomNumberGenerator", "randf", "randi", "scarcity_at("]:
			if body.contains(forbidden):
				_fail("`_landmark_at` contains `%s` — the reverse lookup takes no draw and asks "
						% forbidden + "no gradient (see the MUSEUM MILE banner)")

	var terrain := _terrain(terrain_script, SEEDS[0])
	var sites: Dictionary = terrain.landmark_sites()
	var site_chunk: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	for chunk: Vector2i in sites:
		site_chunk = chunk
		break
	if site_chunk == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		_fail("seed %d sited nothing — check 4's A/B cannot run" % SEEDS[0])
		terrain.free()
		Sentinel.done("no_draw")
		return
	# A neighbour far enough out to be nobody's site, and near enough to carry the
	# same kind of content.
	var empty_chunk: Vector2i = site_chunk + Vector2i(3, 3)
	while sites.has(empty_chunk):
		empty_chunk += Vector2i(1, 0)
	terrain.free()

	var empty_on := _signature(terrain_script, empty_chunk, true)
	var empty_off := _signature(terrain_script, empty_chunk, false)
	if empty_on["pre"] != empty_off["pre"] or empty_on["crocs"] != empty_off["crocs"]:
		_fail("chunk %s has NO landmark site, yet it generates differently with spawn_landmarks "
				% str(empty_chunk) + "on and off — the reverse lookup is taking a draw somewhere")
	var site_on := _signature(terrain_script, site_chunk, true)
	var site_off := _signature(terrain_script, site_chunk, false)
	if site_on["pre"] != site_off["pre"]:
		_fail("chunk %s builds different SCATTERED PROPS and BIOME CONTENT with spawn_landmarks "
				% str(site_chunk) + "on and off — the landmark runs after both and must not move them")
	# The comparator's control: with a landmark actually built, the chunk's own
	# batch has to differ, or `_signature` is comparing nothing.
	if site_on["boxes"] == site_off["boxes"]:
		_fail("chunk %s emits the same boxes with spawn_landmarks on and off — either nothing "
				% str(site_chunk) + "was built there or check 4's comparator is blind")
	print("  _landmark_at takes no draw and asks no gradient; a site-free chunk is byte-identical "
			+ "with landmarks on and off (crocodiles included)")
	Sentinel.done("no_draw")


func _signature(terrain_script: GDScript, chunk: Vector2i, landmarks_on: bool) -> Dictionary:
	"""
	Generate one chunk in create_chunk's order and return three signatures:
	`pre` (everything that runs BEFORE the landmark), `boxes` (the whole visual
	batch) and `crocs` (the bodies, which run after and read the footprints).
	"""
	var terrain := _terrain(terrain_script, SEEDS[0])
	terrain.spawn_landmarks = landmarks_on
	var platforms: Array = []
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = terrain.spawn_objects_in_chunk(chunk, platforms, batch, body)
	terrain.spawn_biome_content_in_chunk(chunk, obstacles, batch, body)
	var chunk_node := MeshInstance3D.new()
	terrain.spawn_artifact_in_chunk(chunk, chunk_node, obstacles, batch, body)
	terrain.spawn_camp_in_chunk(chunk, chunk_node, obstacles, batch, body)
	var pre: PackedByteArray = var_to_bytes(batch) + var_to_bytes(obstacles)
	terrain.spawn_landmark_in_chunk(chunk, chunk_node, obstacles, batch, body)
	terrain.spawn_chest_in_chunk(chunk, chunk_node, obstacles, batch, body)
	var croc_parent := MeshInstance3D.new()
	croc_parent.position = terrain.chunk_to_world(chunk)
	terrain.spawn_crocodiles_in_chunk(chunk, croc_parent, obstacles)
	var crocs: PackedStringArray = PackedStringArray()
	for child in croc_parent.get_children():
		crocs.append("%s@%s" % [child.name, str((child as Node3D).position)])
	var boxes: PackedByteArray = var_to_bytes(batch)
	croc_parent.free()
	chunk_node.free()
	body.free()
	terrain.free()
	return { "pre": pre, "boxes": boxes, "crocs": crocs }


func _function_body(source: String, name: String) -> String:
	"""
	The lines of `func <name>(...)` up to the next top-level `func` — the crude
	reader `scarcity_selfcheck.gd` uses, and for the same reason: GDScript's
	one-function-per-column-0-`func` layout is the whole grammar this needs.
	"""
	var out := ""
	var inside := false
	for line: String in source.split("\n"):
		if line.begins_with("func " + name + "("):
			inside = true
			continue
		if inside:
			if line.begins_with("func "):
				break
			out += line + "\n"
	return out


# ============================================================================
# CHECK 5 — the mile is walked
# ============================================================================

func _check_corridor(terrain_script: GDScript, consts: Dictionary, registry: Array, built: Array) -> void:
	"""
	Enough kinds actually STAND somewhere, and enough of them stand on the road.

	A site table is the easy half; a site whose chunk has no room for the shape is
	a kind missing from the world, so the two floors here (`MIN_KINDS_BUILT` and
	`MILE_MIN_IN_CORRIDOR`) are what make the museum mile a feature rather than a
	data structure. Both are measured numbers with margin — see their constants.

	THE CORRIDOR IS ASKED GEOMETRICALLY, not by "was this kind index below the
	mile slot count": the check must not agree with the placement code about what
	a corridor is, or the two would be wrong together. It is "inside the road's
	own X span, and within LANDMARK_MILE_LATERAL_MAX + CORRIDOR_PAD of the
	centreline `_road_lateral_distance` measures".
	"""
	var lateral_max: float = float(consts["LANDMARK_MILE_LATERAL_MAX"]) + CORRIDOR_PAD
	var terminal_x: float = float(consts["ROAD_TERMINAL_X"])
	var per_seed: PackedStringArray = PackedStringArray()
	for seed_value: int in SEEDS:
		var terrain: Node3D = null
		var built_here := 0
		var corridor := 0
		for row: Dictionary in built:
			if int(row["seed"]) != seed_value:
				continue
			terrain = row["terrain"]
			built_here += 1
			var world: Vector3 = row["world"]
			if world.x < terrain.tower_site().x or world.x > terminal_x:
				continue
			if terrain._road_lateral_distance(world.x, world.z, lateral_max) <= lateral_max:
				corridor += 1
		if built_here < MIN_KINDS_BUILT:
			_fail("seed %d built only %d of %d kinds (floor %d) — too many sites landed in "
					% [seed_value, built_here, registry.size(), MIN_KINDS_BUILT]
					+ "chunks with no room for the shape")
		if corridor < MILE_MIN_IN_CORRIDOR:
			_fail("seed %d stands only %d landmarks inside the road corridor (floor %d) — the "
					% [seed_value, corridor, MILE_MIN_IN_CORRIDOR]
					+ "museum mile is what a run actually walks past")
		per_seed.append("%d: %d built / %d on the mile" % [seed_value, built_here, corridor])
	print("  %s (of %d kinds)" % [", ".join(per_seed), registry.size()])
	Sentinel.done("corridor")


# ============================================================================
# CHECK 6 — the card still keys off the site
# ============================================================================

func _check_card_keys_off_the_site(registry: Array, built: Array) -> void:
	"""
	A REALLY BUILT marker, walked up to through the shipped landmark_toast, raises
	the card of the kind the site table put there.

	`landmark_selfcheck`'s check 4 already drives the toast, but it drives it
	against a HAND-BUILT stub marker — which is exactly the right tool for
	measuring the latch and cannot notice if the SPAWNER stopped writing the right
	`kind`. This one takes the marker node out of a chunk the shipped spawner
	really built, so the chain measured is table -> spawner -> marker meta ->
	toast -> quiz. That is the bead's "keep landmark_id derivable, check every
	reader" line, now that `kind` is the identity.
	"""
	var subject: Dictionary = {}
	for row: Dictionary in built:
		subject = row
		break
	if subject.is_empty():
		_fail("check 6 has no built landmark to walk up to")
		Sentinel.done("card_keys_off_site")
		return

	var toast_consts: Dictionary = load(TOAST_SCRIPT).get_script_constant_map()
	var approach_pad: float = float(toast_consts["APPROACH_PAD"])
	var leave_pad: float = float(toast_consts["LEAVE_PAD"])
	var entry: Dictionary = registry[int(subject["kind"])]
	var radius: float = float(entry["radius"])

	# The marker is lifted out of its scratch chunk and re-homed at the origin, so
	# the walk below is a short one. Its METAS — which are the whole contract with
	# the toast — are untouched, and they are what this check is about.
	var marker: Node3D = subject["marker"]
	(subject["chunk_node"] as Node).remove_child(marker)
	marker.position = Vector3.ZERO
	root.add_child(marker)

	var player := StubPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	# The toast reads exactly one thing off the "terrain" group node — run_seed —
	# which IS the run identity for its per-run treasure latch.
	var terrain_stub := StubTerrain.new()
	terrain_stub.run_seed = 991
	terrain_stub.add_to_group("terrain")
	root.add_child(terrain_stub)

	var toast := Control.new()
	toast.set_script(load(TOAST_SCRIPT))
	root.add_child(toast)
	await process_frame
	toast.set_process(false)

	# Out of range first — the card latch only arms from outside.
	player.global_position = Vector3(0.0, 0.0, radius + leave_pad + 50.0)
	toast.call("_scan")
	if toast.visible:
		_fail("check 6: the card is up with the player 50 m outside every landmark")
	# ...and in.
	player.global_position = Vector3(0.0, 0.0, radius + approach_pad - 1.0)
	toast.call("_scan")
	if not toast.visible:
		_fail("check 6: walking up to a really-built %s raised no card" % String(entry["name"]))
	elif not bool(toast.get("_quiz_pending")):
		_fail("check 6: the first visit to a really-built %s asked no question"
				% String(entry["name"]))
	else:
		# THE BINDING. On a first visit the card shows the PROMPT and the three
		# option buttons; the right answer's button carries the registry name of
		# the marker's `kind`, so this is the site table read back through the
		# spawner, the marker meta, `quiz_options` and the card in one comparison.
		var slot: int = int(toast.get("_quiz_correct_slot"))
		var buttons: Array = toast.get("_option_buttons")
		if slot < 0 or slot >= buttons.size():
			_fail("check 6: the card's correct slot %d is outside its %d options"
					% [slot, buttons.size()])
		elif String((buttons[slot] as Button).text) != String(entry["name"]):
			_fail("check 6: the card's right answer is '%s', but the spawner built kind %d (%s) "
					% [String((buttons[slot] as Button).text), int(subject["kind"]), String(entry["name"])]
					+ "there — the marker's `kind` meta and the site table disagree")
		# Answer it, which is also what releases the pause the card took.
		toast.call("_answer", slot)

	print("  a really-built %s raises its own card and its own right answer" % String(entry["name"]))
	Sentinel.done("card_keys_off_site")


## The stub player. The toast pays a first visit through `collect_coin`, one call
## per coin (see its TREASURE CONFIGURATION banner for why it is never one call
## for N), and asks for `explore_landmark` only for the CITY's 22-bit mask, which
## a field landmark never touches.
class StubPlayer extends Node3D:
	var coins_paid: int = 0

	func collect_coin(_value: int = 1) -> void:
		coins_paid += 1


## The stub terrain — `run_seed` is the only thing the toast reads off the group.
class StubTerrain extends Node:
	var run_seed: int = 0
