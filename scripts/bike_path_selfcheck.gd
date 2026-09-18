extends SceneTree
## Headless self-check for THE BICYCLE PATHS — the seeded station polyline, the
## flat strip, the dashes and the poles (epic `godot-test1-z2yv`, child `.1`).
##
##   godot --headless --path . --script res://scripts/bike_path_selfcheck.gd
##
## `scripts/terrain_bike_paths.gd`'s banner carries the design; this file is the
## part of it a future edit cannot slip past. Six checks, every one of them an
## effect measurement WITH A CONTROL — the house rule in this suite:
##
##   1. THE KILL SWITCH, and it is check 1 because it is the one that must never
##      go red. A field of chunks built through the SHIPPED `create_chunk` with
##      `spawn_bike_paths` off, against the same field with it on and this
##      family's boxes sliced out of the built CUBE MultiMesh by the marker's
##      own `cube_start` / `batch_count`: byte-identical, every other bucket
##      whole, and every crocodile and coin on the same metre. A stray draw from
##      the shared chunk stream slides every body in the chunk, so the node half
##      is what catches a draw hidden behind a helper. Its two controls run the
##      other way: the field must contain a chunk WITH a path (or the slice is
##      never exercised) and a chunk WITHOUT one (or "identical" is trivial).
##   2. PURITY, SEAMLESSNESS, AND WHERE THE GEOMETRY ACTUALLY LANDS. The same
##      chunk built twice is byte-identical, batch and `obstacles` both. Then, for
##      real paths across a real field: (b) the union of the segments drawn by
##      every chunk in reach is EXACTLY the station list — each segment once, none
##      missing — with a mutation control on the comparator in both directions;
##      and (c) every strip box's WORLD position is its segment's midpoint, which
##      is the only assertion in the file that ties a drawn box to the station
##      that produced it. Without (c) a wrong local frame — chunk-local is
##      relative to the chunk NODE, which stands at the chunk CENTRE, not its
##      corner — puts every strip half a chunk off the ground the walk cleared
##      and the other five checks all still pass.
##   3. TRUNCATION, NOT GAPS. Every station in the list is legal, measured against
##      the shipped predicate; a path shorter than `BIKE_PATH_MIN_STATIONS` is a
##      failure. Then a SWEEP over seeds and origins for a path that actually runs
##      into something, and it FAILS IF IT FINDS NONE — a check that can pass by
##      never testing the thing is not a check. The successor station is taken
##      from the shipped recurrence and asked whether it is blocked; that is a
##      NON-VACUITY COUNTER and not an assertion, deliberately, because a path may
##      also simply have run out of its rolled length and then has a perfectly
##      legal successor. "Never resumes past a block" is the prefix loop above it.
##   4. SCARCITY, form 2. Origins in the HQ corridor produce paths; origins
##      beyond `SCARCITY_PLAIN_DISTANCE` produce NONE. The near field is the
##      control — `scarcity_selfcheck` check 2's own shape — and `scarcity_at()`
##      is asserted to really be 0 out there, so the far half cannot pass because
##      the band was mis-chosen.
##   5. ZERO NEW BUCKETS. A chunk carrying a path has exactly the
##      `BlockMultiMesh_*` children it has without one. The "CUBE only" ruling
##      (`batch_selfcheck` check 5's `KIND_CAP_BY_NAME` needs no row changed),
##      made unfailable rather than promised in a comment.
##   6. FOOTPRINTS. Every pole appends exactly one `{climbable: false}` footprint
##      with the post's own radius and top; the strip and the dashes append
##      nothing at all. Non-vacuous: the sweep must find poles.

## The end-of-check sentinel — see `scripts/selfcheck_sentinel.gd` for why every
## check stamps itself and the report site never prints SELFCHECK OK itself.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
## Check 1 builds real chunks, and a real chunk spawns real predators.
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## The `landmark_sites_selfcheck` / `scarcity_selfcheck` / `waypoint_selfcheck`
## set. The paths move with `run_seed`, so one world proves nothing about the
## rule and only about that world.
const SEEDS: Array[int] = [20260904, 777, 4242]

## THE A/B FIELD: a 4x4 band of chunks off the road's north side on `SEEDS[0]`,
## chosen because it holds every kind of chunk check 1 needs — four carrying path
## geometry WITH poles, one carrying strip and dashes but NO pole (which is where
## the node-for-node comparison is made, see that check), and eleven carrying no
## path at all. It is a band and not a scatter so that a path crossing a seam is
## compared on both sides of it.
##
## IT MOVES WHEN THE STREAM DOES, which is the point of the controls below rather
## than a fragility: they assert the mix instead of trusting this comment, so a
## retuned prime, salt or chance empties the band LOUDLY. Re-derive it by
## sweeping `spawn_bike_path_in_chunk` over a band and reading which chunks draw.
const AB_X: Array[int] = [-5, -4, -3, -2]
const AB_Y: Array[int] = [8, 9, 10, 11]

## The CUBE bucket's node name — `ChunkBatch._emit_kind_multimesh` keeps the bare
## name for CUBE and suffixes every other kind, and this family builds CUBEs only.
const CUBE_BUCKET: String = "BlockMultiMesh"
## The chunk's single shared collision body.
const BLOCK_BODY: String = "BlockCollision"

## How many real paths check 2b walks the whole cover of. Every one of them costs
## `(2 * scan_radius + 1)^2` spawner calls, so this is a bound on the check's cost
## rather than on its meaning: the assertion is about the RULE, and six paths on
## six different stretches of field exercise it as well as thirty do.
const COVER_SAMPLE: int = 6

## Check 3's SEARCH SPACE in seeds, not a sample: it sweeps these in order and
## stops at the first seed by which it has seen both shapes it needs — a
## truncated path and one that ran to `BIKE_PATH_MAX_STATIONS`. The three CI
## `SEEDS` lead it only because they are cheap to try first, and
## `waypoint_selfcheck`'s CONTROL_SEEDS is the same shape.
const TRUNCATION_SEEDS: Array[int] = [20260904, 777, 4242, 1, 424242, 999983, 750, 99]

## How many station-strides `_check_half_step_control` samples looking for a
## narrow river band. The measured rate is one per ~49,000 dry pairs, so this is
## sized to find several and it stops at the first.
const HALF_STEP_SAMPLES: int = 250000

## Check 2's and check 3's search space, in chunks, centred on the origin. Big
## enough to hold several paths on every seed (measured: 3 to 20 per seed over
## this square) and small enough to stay a fraction of a second.
const SWEEP_HALF: int = 14

## How far a strip box's world centre may sit from its segment's midpoint in
## check 2c. Metres, and it is a float-comparison tolerance rather than a design
## allowance: the two numbers are computed from the same `Vector2` a few calls
## apart, so anything above millimetres is a real displacement.
const STRIP_TOLERANCE: float = 0.01

## Check 4's far field: origins this many chunks out on Z, which at chunk_size 50
## is ~6 km from both the Budapest rect and the HQ corridor — comfortably past
## `SCARCITY_PLAIN_DISTANCE` (4 km), where `scarcity_at()` is exactly 0.
const FAR_CHUNK_Y: int = 130

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# A coroutine because check 1 needs a terrain that is really IN the tree
	# before it calls `create_chunk` — `root.add_child()` inside `_initialize()`
	# has not put a node in the tree yet, and several spawners ask the chunk for a
	# global transform. `waypoint_selfcheck`'s recipe.
	_run()


func _run() -> void:
	await process_frame
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	_check_kill_switch(terrain_script)
	_check_purity_and_seams(terrain_script)
	_check_truncation(terrain_script)
	_check_scarcity(terrain_script)
	_check_no_new_buckets(terrain_script)
	_check_footprints(terrain_script)

	if _failures.is_empty():
		print("bike paths: the kill switch leaves every other box in the world where "
				+ "it was, each strip stands on the ground its own walk cleared, the "
				+ "per-chunk shares cover every segment exactly once, blocked paths "
				+ "truncate rather than gap, scarcity empties the far field, no chunk "
				+ "grew a MultiMesh bucket and only the poles claim a footprint")
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECK 1 — the kill switch, and therefore the RNG stream
# ============================================================================

func _check_kill_switch(terrain_script: GDScript) -> void:
	"""
	The same field of chunks with `spawn_bike_paths` true and false, compared
	through the SHIPPED `create_chunk` on both sides.

	WHY THE WHOLE PIPELINE AND NOT THE SPAWNER ALONE: what has to hold is that
	this family costs the shared chunk / biome / crocodile streams NOTHING, and
	the only place that is visible is downstream of it. A single stray draw slides
	every crocodile and every coin in the chunk, which the node table below sees;
	a box drawn in the wrong place the MultiMesh table sees. Calling the spawner
	on an empty batch would prove neither.

	THE SLICE is the `gag_start` / `gag_count` idiom (`camp_story_selfcheck`),
	moved into CUBE-bucket coordinates because by comparison time the batch is
	gone and the MultiMesh is what is left: `_build_block_multimesh` buckets by
	kind, so the marker's `cube_start` plus `batch_count` is exactly this family's
	run of instances in the CUBE bucket. Cutting it out must leave the OFF chunk.
	"""
	var on: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var off: Node3D = _terrain(terrain_script, SEEDS[0], false)
	var with_path: int = 0
	var without: int = 0
	var bare_path: int = 0
	var nodes_seen: int = 0

	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			on.create_chunk(chunk_pos)
			off.create_chunk(chunk_pos)
			var chunk_on: Node = on.active_chunks[chunk_pos]
			var chunk_off: Node = off.active_chunks[chunk_pos]

			var markers: Array[Node] = _markers(chunk_on)
			var poles: int = 0
			var sliced: int = 0
			for marker: Node in markers:
				poles += (marker.get_meta("poles") as PackedInt32Array).size()
			if not markers.is_empty():
				sliced = int(markers[0].get_meta("batch_count"))
			if markers.is_empty():
				without += 1
			else:
				with_path += 1

			# --- The boxes, bucket by bucket, with our own run cut out of CUBE.
			var table_on: Dictionary = _multimesh_table(chunk_on)
			var table_off: Dictionary = _multimesh_table(chunk_off)
			if not markers.is_empty():
				var start: int = int(markers[0].get_meta("cube_start"))
				var count: int = int(markers[0].get_meta("batch_count"))
				if not table_on.has(CUBE_BUCKET):
					_fail("chunk %s carries a bike path but has no '%s' child — every box "
							% [chunk_pos, CUBE_BUCKET] + "this family builds is a CUBE")
				else:
					var rows: Array = table_on[CUBE_BUCKET]
					if start + count > rows.size():
						_fail("chunk %s: the marker claims CUBE instances [%d, %d) but the "
								% [chunk_pos, start, start + count]
								+ "bucket holds %d — the cube-bucket invariant has broken "
								% rows.size()
								+ "(a later spawner now inserts rather than appends)")
					else:
						table_on[CUBE_BUCKET] = rows.slice(0, start) + rows.slice(start + count)
			if table_on.keys() != table_off.keys():
				_fail("chunk %s has MultiMesh buckets %s with the paths on and %s with them "
						% [chunk_pos, table_on.keys(), table_off.keys()] + "off")
			else:
				for name: String in table_off:
					if var_to_bytes(table_on[name]) != var_to_bytes(table_off[name]):
						_fail("chunk %s: the '%s' bucket differs between the two builds once "
								% [chunk_pos, name] + "this family's own %d boxes are sliced out "
								% sliced + "— the paths moved somebody else's geometry")
						break

			# --- The bodies: crocodiles, coins, everything parented to the chunk.
			#
			# ONLY WHERE THIS FAMILY APPENDED NO FOOTPRINT, and that is not a
			# weakening — it is where the claim is exactly true. A pole footprint is
			# read by the crocodile, boss and hunter spawners that run after this
			# one, and `terrain_predators.gd` says what follows: "a rejection still
			# skips the successful spawn's `rotation.y` draw below, so the rest of
			# this chunk's crocodile positions shift". That is the shared-currency
			# mechanism camps and chests use too, so a difference on a chunk with a
			# pole would be sanctioned behaviour and this comparator cannot tell it
			# from a stray draw. On a chunk with no pole nothing downstream can even
			# see the paths, so a single differing node IS a draw.
			if poles == 0:
				# ...and THIS is the one with any power: a chunk where the drawing code
				# really ran and still appended no footprint. Counted separately from
				# `nodes_seen`, which the band's eleven path-free chunks would keep
				# comfortably above zero on their own.
				if not markers.is_empty():
					bare_path += 1
				var nodes_on: Array[String] = _node_table(chunk_on)
				var nodes_off: Array[String] = _node_table(chunk_off)
				nodes_seen += nodes_off.size()
				if nodes_on != nodes_off:
					_fail("chunk %s carries no bike-path pole, so nothing downstream can see "
							% chunk_pos + "this family at all — yet it holds %d chunk-parented "
							% nodes_on.size() + "nodes with the paths on and %d with them off. "
							% nodes_off.size() + "A draw was taken from the shared chunk stream")

			# --- The collision body. Its shapes are added inline by `create_box`, so
			# they are not a list a marker indexes; what IS exactly stated is that
			# this family adds one shape per POLE and none for its paint.
			var shapes_on: int = _shape_count(chunk_on)
			var shapes_off: int = _shape_count(chunk_off)
			if shapes_on != shapes_off + poles:
				_fail("chunk %s: %d collision shapes with the paths on, %d without and %d "
						% [chunk_pos, shapes_on, shapes_off, poles]
						+ "poles built — the strip or the dashes are colliding")

	if with_path == 0:
		_fail("check 1's A/B field holds no chunk with a bike path in it, so the slice was "
				+ "never exercised and the comparison passed for the wrong reason — retune "
				+ "AB_X / AB_Y against the current seed")
	if without == 0:
		_fail("check 1's A/B field holds no chunk WITHOUT a bike path, so 'identical' was "
				+ "never the trivial case it needs as a control")
	if nodes_seen == 0:
		_fail("check 1 compared %d chunks and found no chunk-parented nodes at all in any of "
				% (AB_X.size() * AB_Y.size())
				+ "them — the half of this check that catches a stray draw is blind")
	if bare_path == 0:
		# THE CONTROL THE `poles == 0` GATE NEEDS, and it is not the same as
		# `with_path`. On a chunk with no path at all the spawner reaches no
		# `create_box` and the two builds are identical by construction whatever bug
		# exists, so the node comparison asserts nothing there. Only a chunk that
		# DREW and still appended no footprint can show a stray draw — and a retune
		# of the chance, the stride, the primes or the band that leaves every path
		# chunk carrying a pole would empty that set silently.
		_fail("check 1's A/B field holds no chunk that draws bike-path geometry AND appends "
				+ "no footprint, so its stray-draw comparison ran only on chunks where the "
				+ "spawner drew nothing and could not have failed. Retune AB_X / AB_Y until "
				+ "the band contains a path with no pole on it")
	on.free()
	off.free()
	Sentinel.done("kill_switch")


# ============================================================================
# CHECK 2 — purity, and the per-chunk shares of one polyline
# ============================================================================

func _check_purity_and_seams(terrain_script: GDScript) -> void:
	"""
	The same chunk twice is the same chunk; and across a field, the segments drawn
	by every chunk in reach of an origin are the polyline's own, each exactly once.

	THE SEAM IS THE POINT. A path is rolled at its ORIGIN and drawn by whichever
	chunk each segment's MIDPOINT falls in, so "no duplicate, no gap" is the whole
	statement of that rule — the failure it excludes is a strip that stops at a
	chunk edge and starts again half a metre later.

	The union is read off the markers' `segments` meta rather than recomputed
	here, deliberately: a second copy of the midpoint rule inside this check would
	agree with a broken one. What this check owns instead is the COMPARATOR, and
	the two mutations below are the control on it.

	...AND THEN (c) WHERE THE BOX ACTUALLY LANDS, which is the one assertion in
	this file that connects a drawn box to the station that produced it. Every
	other check compares a build against another build (1, 5), a list against
	itself (2a, 2b), a station list against a predicate (3, 4) or a count against
	a count (6) — all of which a uniformly wrong local frame satisfies perfectly.
	`create_box` takes a CHUNK-LOCAL centre and the chunk node stands at the chunk
	CENTRE, so a conversion that subtracted the corner instead would put every
	strip half a chunk off the ground `station_blocked` cleared, across the coin
	road and the rivers, with all six checks green. This is measured in WORLD
	space — the chunk node's position plus the batch entry's own origin — because
	that is the frame the claim is made in.

	WHAT IT DOES AND DOES NOT PIN, honestly: ANY partition of the segments is a
	perfect cover, so this does not prove the rule is the MIDPOINT one — it proves
	it is a partition. That is the property the seam needs, and the two realistic
	ways to lose it are exactly the two the mutations exercise: draw a segment in
	every chunk an endpoint touches (a strip drawn twice) and draw it only where
	both endpoints land (a hole at every seam).
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var radius: int = BikePaths.scan_radius_chunks(terrain)

	# --- a. WITHIN A RUN: the same chunk, built twice, down to the byte.
	var rebuilt: int = 0
	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			var first: Dictionary = _spawn_bare(terrain, chunk_pos)
			var second: Dictionary = _spawn_bare(terrain, chunk_pos)
			if var_to_bytes(first["batch"]) != var_to_bytes(second["batch"]):
				_fail("chunk %s built two different batches on two passes of the same run — "
						% chunk_pos + "a revisited chunk must regenerate identically")
			if var_to_bytes(first["obstacles"]) != var_to_bytes(second["obstacles"]):
				_fail("chunk %s appended two different obstacle lists on two passes"
						% chunk_pos)
			if var_to_bytes(first["paths"]) != var_to_bytes(second["paths"]):
				_fail("chunk %s recorded two different marker tables on two passes"
						% chunk_pos)
			if not (first["batch"] as Array).is_empty():
				rebuilt += 1
	if rebuilt == 0:
		_fail("check 2a rebuilt %d chunks and not one of them drew a box, so 'identical' "
				% (AB_X.size() * AB_Y.size()) + "was vacuous")

	# --- b. THE COVER, over every path in a sweep of origins.
	var covered: int = 0
	var strip_checked: int = 0
	var sample: Array = []  # one real per-chunk split, kept for the mutation control
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var origin := Vector2i(ox, oy)
			if covered >= COVER_SAMPLE:
				break
			var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
			if stations.size() < 2:
				continue
			var lists: Array = []
			for cx in range(ox - radius, ox + radius + 1):
				for cy in range(oy - radius, oy + radius + 1):
					var chunk_pos := Vector2i(cx, cy)
					var built: Dictionary = _spawn_bare(terrain, chunk_pos)
					var drawn := PackedInt32Array()
					for row: Dictionary in (built["paths"] as Array[Dictionary]):
						if row["origin"] == origin:
							drawn = row["segments"]
					if drawn.is_empty():
						continue
					lists.append(drawn)
					# --- c. AND THE BOXES ARE WHERE THE WALK SAID. See the docstring.
					var strips: Array[Vector2] = _strip_positions(terrain, chunk_pos, built["batch"])
					for i: int in drawn:
						var a: Vector2 = stations[i]["pos"]
						var b: Vector2 = stations[i + 1]["pos"]
						var want: Vector2 = (a + b) * 0.5
						var best: float = INF
						for at: Vector2 in strips:
							best = minf(best, at.distance_to(want))
						if best > STRIP_TOLERANCE:
							_fail("origin %s segment %d: chunk %s claims to draw it, but its nearest "
									% [origin, i, chunk_pos] + "strip box stands %.2f m from the "
									% best + "segment's midpoint %s. The strip is not on the ground "
									% want + "the walk cleared — check the chunk-local frame, which "
									+ "is centred on the chunk NODE and not on its corner")
							break
						strip_checked += 1
			var fault: String = _cover_fault(lists, stations.size() - 1)
			if fault != "":
				_fail("the path from origin %s is not covered by the chunks around it: %s"
						% [origin, fault])
			else:
				covered += 1
			if sample.is_empty() and lists.size() >= 2:
				sample = lists
	if covered == 0:
		_fail("check 2b found no path at all in a %dx%d sweep of origins on seed %d — the "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1, SEEDS[0]]
				+ "cover assertion was never made")
	if strip_checked == 0:
		_fail("check 2c located no strip box at all, so the one assertion in this file that "
				+ "ties a drawn box to the station that produced it never fired")
	if sample.is_empty():
		_fail("check 2b found no path that spans more than one chunk, so the seam — the "
				+ "whole subject of this check — was never crossed")
	else:
		# THE MUTATION CONTROL. Both directions, over the same real data: a rule
		# that dropped a segment and a rule that drew one twice must each be caught,
		# or a "perfect cover" verdict says nothing.
		var n: int = 0
		for list_v: Variant in sample:
			n += (list_v as PackedInt32Array).size()
		var gapped: Array = sample.duplicate(true)
		var first_list: PackedInt32Array = gapped[0]
		first_list.remove_at(0)
		gapped[0] = first_list
		if _cover_fault(gapped, n) == "":
			_fail("check 2b's comparator called a cover with a segment MISSING perfect — it "
					+ "would not notice a bike path with a hole at a chunk seam")
		var doubled: Array = sample.duplicate(true)
		doubled.append(sample[0])
		if _cover_fault(doubled, n) == "":
			_fail("check 2b's comparator called a cover with a segment drawn TWICE perfect — "
					+ "it would not notice two chunks both claiming the same strip")
	terrain.free()
	Sentinel.done("purity_and_seams")


func _cover_fault(lists: Array, segment_count: int) -> String:
	"""
	Is `lists` — one per-chunk list of segment indices — a perfect cover of
	`0 .. segment_count - 1`?

	@return: "" when it is, otherwise the first fault in words.
	"""
	var seen: Dictionary = {}
	for list_v: Variant in lists:
		for i: int in (list_v as PackedInt32Array):
			if seen.has(i):
				return "segment %d is drawn by two chunks" % i
			seen[i] = true
	for i in segment_count:
		if not seen.has(i):
			return "segment %d is drawn by no chunk at all" % i
	return ""


# ============================================================================
# CHECK 3 — blocked means truncated, never gapped
# ============================================================================

func _check_truncation(terrain_script: GDScript) -> void:
	"""
	Find paths that actually run into something and assert they STOP there.

	A SWEEP AND NOT A FIXTURE, and it fails when the sweep comes up empty: the
	rule under test is "a blocked station ends the path", and a check that never
	met a blocked station would report that rule as holding while saying nothing.
	TWO shapes have to turn up, not one — a truncated path and a path that ran to
	full length — and `TRUNCATION_SEEDS` is a search space rather than a sample.

	THE HALF-STEP SAMPLE IS CONTROLLED SEPARATELY, in `_check_half_step_control`
	below, because no path sweep this file can afford would ever meet the shape it
	guards. Read that function before trusting the segment assertion here.

	WHAT IS ASSERTED and what is only COUNTED, because the difference matters to
	the next reader. ASSERTED, per path: every station in the list passes the
	station predicate, every SEGMENT between two of them passes the half-step
	river sample, and the list is at least `BIKE_PATH_MIN_STATIONS` long. Both
	predicates, because the walk stops on both and the second is not implied by
	the first — two stations either side of a narrow band are each legal on their
	own. That set IS the "never resumes past a block" rule: a walk that resumed
	would leave a blocked station, or a drowned segment, inside the list.
	COUNTED, per path: whether the station
	after the last one is blocked. That cannot be asserted, and deliberately so —
	`_bike_path_at` rolls its length with `randi_range`, so a path that simply ran
	out has a perfectly legal successor. It is the NON-VACUITY GUARD at the bottom
	of this function instead, and the guard is the point: without it the two
	assertions above hold trivially in a world where nothing is ever blocked.

	The successor comes from `BikePaths.next_station()` and
	`BikePaths.segment_blocked()` — the shipped recurrence and the shipped
	half-step river sample, not copies of them here.
	"""
	var truncated: int = 0
	var full_length: int = 0
	var swept: int = 0
	for seed_value: int in TRUNCATION_SEEDS:
		# Stop at the first seed by which every shape has been seen. The prefix
		# assertions below ran on every path of every seed swept, so this bounds the
		# SEARCH and not the checking.
		if truncated > 0 and full_length > 0:
			break
		swept += 1
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
			for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
				var origin := Vector2i(ox, oy)
				var stations: Array[Dictionary] = BikePaths.bike_path_at(terrain, origin)
				if stations.is_empty():
					continue
				# THE PREFIX IS LEGAL, and that is BOTH predicates the walk stops on.
				# The stations first...
				for i in stations.size():
					if BikePaths.station_blocked(terrain, stations[i]["pos"]):
						_fail("seed %d origin %s: station %d of %d stands somewhere the walk "
								% [seed_value, origin, i, stations.size()]
								+ "should have stopped — the path is not a legal prefix")
						break
				# ...and then the GROUND BETWEEN THEM, which is a separate statement and
				# not a corollary of the one above: the whole reason `segment_blocked`
				# exists is that both stations flanking a river band narrower than the
				# station pitch are individually legal. Asserting only the stations would
				# pass a strip laid straight across the water.
				for i in range(stations.size() - 1):
					if BikePaths.segment_blocked(terrain, stations[i]["pos"], stations[i + 1]["pos"]):
						_fail("seed %d origin %s: the strip between stations %d and %d crosses "
								% [seed_value, origin, i, i + 1]
								+ "water, though both of its ends stand on dry ground — the "
								+ "half-step river sample is not stopping the walk")
						break
				if stations.size() < BikePaths.BIKE_PATH_MIN_STATIONS:
					_fail("seed %d origin %s: a path of %d stations survived, below "
							% [seed_value, origin, stations.size()]
							+ "BIKE_PATH_MIN_STATIONS %d — a stub should be dropped whole"
							% BikePaths.BIKE_PATH_MIN_STATIONS)
				var head: float = stations[0]["heading"]
				var next: Dictionary = BikePaths.next_station(terrain, origin, head,
						stations[-1], stations.size() - 1)
				if BikePaths.station_blocked(terrain, next["pos"]) \
						or BikePaths.segment_blocked(terrain, stations[-1]["pos"], next["pos"]):
					truncated += 1
				elif stations.size() == BikePaths.BIKE_PATH_MAX_STATIONS:
					full_length += 1
		terrain.free()

	if truncated == 0:
		_fail("check 3 swept %d seeds x %dx%d origins and found no path that was stopped by "
				% [swept, SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1]
				+ "the road, a river, the mountains, the city, the HQ, a landmark or a "
				+ "waypoint — the truncation rule is untested, so widen TRUNCATION_SEEDS "
				+ "rather than trusting this")
	if full_length == 0:
		_fail("check 3 found no path that ran to BIKE_PATH_MAX_STATIONS, so 'it stopped "
				+ "because it was blocked' has no control: every path may simply be short")
	_check_half_step_control(terrain_script)
	Sentinel.done("truncation")


func _check_half_step_control(terrain_script: GDScript) -> void:
	"""
	THE CONTROL ON `segment_blocked` ITSELF, because the sweep above cannot be one.

	The segment half of check 3's prefix assertion holds over every path swept —
	and it would hold just as perfectly if `segment_blocked` were `return false`.
	Widening the sweep does not fix that: MEASURED over 778,924 dry-dry pairs a
	station-stride apart, across four seeds and the whole corridor, exactly 16 had
	a wet midpoint. That is one narrow band per ~49,000 pairs, or roughly one path
	in four thousand — so a sweep big enough to meet one by chance would cost more
	than every other check in this file put together, and a sweep that did NOT
	meet one would report green either way.

	So the predicate is controlled DIRECTLY instead: search the field for the
	shape it exists for — two dry points a station apart with water between them —
	and assert it answers true there. That turns "no drawn segment crosses water"
	from a claim the suite cannot fail into one whose predicate is known to work,
	and it is the reason `segment_blocked` cannot be quietly emptied out.

	A FIXED-SEED sample and not `randomize()`: this is a search over a
	deterministic field, so a fixed generator makes the same search every run and
	a failure is reproducible. It stops at the first hit, which at the measured
	rate is a few thousand samples in.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var found: int = 0
	var dry_pairs: int = 0
	for _i in HALF_STEP_SAMPLES:
		var p := Vector2(rng.randf_range(-2000.0, 2000.0), rng.randf_range(-1500.0, 1500.0))
		var heading: float = rng.randf() * TAU
		var q: Vector2 = p + Vector2(cos(heading), sin(heading)) * BikePaths.BIKE_STATION_SPACING
		if terrain.is_river_at(Vector3(p.x, 0.0, p.y)) \
				or terrain.is_river_at(Vector3(q.x, 0.0, q.y)):
			continue
		dry_pairs += 1
		if BikePaths.segment_blocked(terrain, p, q):
			found += 1
			break
	terrain.free()
	if dry_pairs == 0:
		_fail("check 3's half-step control found no dry pair at all in %d samples — it is "
				% HALF_STEP_SAMPLES + "not sampling the field")
	elif found == 0:
		_fail("check 3's half-step control swept %d dry station-strides on seed %d and found "
				% [dry_pairs, SEEDS[0]] + "no pair with water between its two dry ends, so "
				+ "`BikePaths.segment_blocked()` was never once seen to answer true and could "
				+ "be `return false` with this file still green. Raise HALF_STEP_SAMPLES (the "
				+ "measured rate is about one such pair per 49,000)")
	Sentinel.done("half_step_control")


# ============================================================================
# CHECK 4 — scarcity, form 2
# ============================================================================

func _check_scarcity(terrain_script: GDScript) -> void:
	"""
	Paths near the HQ corridor, and NONE beyond `SCARCITY_PLAIN_DISTANCE`.

	`scarcity_selfcheck` check 2's shape: the near field is the control, because
	"no path out there" is also what a rarity roll that never fires looks like.
	The far band's own `scarcity_at()` is asserted to be 0 as well, so the check
	cannot pass because the band was chosen too close to the city.
	"""
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		var near: int = 0
		var far: int = 0
		var k_far: float = 0.0
		for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
			for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
				if not BikePaths.bike_path_at(terrain, Vector2i(ox, oy)).is_empty():
					near += 1
				var out := Vector2i(ox, FAR_CHUNK_Y + oy)
				k_far = maxf(k_far, terrain.scarcity_at(terrain.chunk_to_world(out)))
				if not BikePaths.bike_path_at(terrain, out).is_empty():
					far += 1
		if near == 0:
			_fail("seed %d: not one path in the %dx%d of origins around the corridor, where "
					% [seed_value, SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1]
					+ "scarcity is 1 — the rarity roll never fires and the far half of this "
					+ "check passes for the wrong reason")
		if k_far > 0.0:
			_fail("seed %d: check 4's far band reaches scarcity %.3f, so it is not past "
					% [seed_value, k_far] + "SCARCITY_PLAIN_DISTANCE at all — raise "
					+ "FAR_CHUNK_Y")
		elif far > 0:
			_fail("seed %d: %d paths stand beyond SCARCITY_PLAIN_DISTANCE, where "
					% [seed_value, far] + "scarcity_at() is 0 — the bike paths are exempting "
					+ "themselves from the one rule every biome shares")
		terrain.free()
	Sentinel.done("scarcity")


# ============================================================================
# CHECK 5 — CUBE only: no chunk grows a MultiMesh bucket
# ============================================================================

func _check_no_new_buckets(terrain_script: GDScript) -> void:
	"""
	A chunk carrying a path has exactly the `BlockMultiMesh_*` children it has
	without one.

	THE RULING, MADE UNFAILABLE. `batch_selfcheck` check 5 caps the draw calls per
	biome from a table its own sweep cannot reach this family with — it builds
	`spawn_objects_in_chunk` + `spawn_biome_content_in_chunk`, and a bike path is
	neither. So the guarantee that `KIND_CAP_BY_NAME` needs no row changed is
	asserted HERE, where the paths are: one new bucket would be +1 draw call on
	every PLAINS / SNOW / FOREST chunk that carries a strip, which is a great many
	more chunks than the eleven the waypoint disc is forgiven for.
	"""
	var on: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var off: Node3D = _terrain(terrain_script, SEEDS[0], false)
	var compared: int = 0
	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			on.create_chunk(chunk_pos)
			var chunk_on: Node = on.active_chunks[chunk_pos]
			if _markers(chunk_on).is_empty():
				continue
			off.create_chunk(chunk_pos)
			var chunk_off: Node = off.active_chunks[chunk_pos]
			compared += 1
			var buckets_on: Array = _multimesh_table(chunk_on).keys()
			var buckets_off: Array = _multimesh_table(chunk_off).keys()
			buckets_on.sort()
			buckets_off.sort()
			if buckets_on != buckets_off:
				_fail("chunk %s draws buckets %s with a bike path in it and %s without — a "
						% [chunk_pos, buckets_on, buckets_off]
						+ "bike path must be CUBEs and nothing else")
			if buckets_off.is_empty():
				_fail("chunk %s has no MultiMesh bucket at all with the paths off, so the "
						% chunk_pos + "comparison above cannot see a bucket being added")
	if compared == 0:
		_fail("check 5 found no chunk with a path in the A/B field — it asserted nothing")
	on.free()
	off.free()
	Sentinel.done("no_new_buckets")


# ============================================================================
# CHECK 6 — only the poles claim a footprint
# ============================================================================

func _check_footprints(terrain_script: GDScript) -> void:
	"""
	One `{climbable: false}` footprint per pole, and not one for the paint.

	The strip and the dashes are paint you walk over — `terrain_waypoints.gd`'s
	"no footprint, and why", the same ruling one family along — so the count of
	appended footprints must equal the count of poles the markers recorded, never
	the count of boxes. A post is NON-CLIMBABLE and its `top` is its full height:
	a mast has no top to stand on (`terrain_biomes.gd`'s street furniture).
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var poles_seen: int = 0
	var paint_seen: int = 0
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, chunk_pos)
			var batch: Array = built["batch"]
			var obstacles: Array = built["obstacles"]
			var poles: int = built["poles"]
			poles_seen += poles
			paint_seen += batch.size() - poles
			if obstacles.size() != poles:
				_fail("chunk %s built %d boxes of which %d are poles, and appended %d "
						% [chunk_pos, batch.size(), poles, obstacles.size()]
						+ "footprints — it must be exactly one per pole and none for the "
						+ "strip or the dashes")
				continue
			for entry_v: Variant in obstacles:
				var entry: Dictionary = entry_v
				if bool(entry["climbable"]):
					_fail("chunk %s appended a CLIMBABLE footprint — a post has no top to "
							% chunk_pos + "stand on")
				if not is_equal_approx(float(entry["top"]), BikePaths.BIKE_POLE_HEIGHT):
					_fail("chunk %s: a pole footprint's top is %.2f, not the post's own "
							% [chunk_pos, float(entry["top"])] + "height %.2f"
							% BikePaths.BIKE_POLE_HEIGHT)
				if not is_equal_approx(float(entry["radius"]), BikePaths.BIKE_POLE_RADIUS):
					_fail("chunk %s: a pole footprint claims radius %.2f, not "
							% [chunk_pos, float(entry["radius"])] + "BIKE_POLE_RADIUS %.2f"
							% BikePaths.BIKE_POLE_RADIUS)
	if poles_seen == 0:
		_fail("check 6 swept %dx%d chunks and found no pole at all, so 'one footprint per "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "pole' was vacuous")
	if paint_seen == 0:
		_fail("check 6 found poles but no strip or dash boxes, so 'and none for the paint' "
				+ "was vacuous")
	terrain.free()
	Sentinel.done("footprints")


# ============================================================================
# HELPERS
# ============================================================================

func _terrain(terrain_script: GDScript, seed_value: int, paths_on: bool) -> Node3D:
	"""
	A REAL terrain in the tree on `seed_value`, with the crocodile scene check 1
	needs. `waypoint_selfcheck` / `landmark_sites_selfcheck`'s recipe, and both
	halves of it matter: IN THE TREE because `create_chunk` parents its chunk to
	it and several spawners ask that chunk for a global transform, and SEEDED
	AFTER `add_child` because `_ready()` rolls its own seed and would throw an
	earlier one away.

	It never streams on its own: `_ready` finds no node in group "player", so
	`player` stays null and `_process` returns immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.spawn_bike_paths = paths_on
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _spawn_bare(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	Run the SHIPPED spawner alone into a throwaway batch, body and chunk, and
	return what it produced with every node freed again.

	@return: `{ "batch": Array, "obstacles": Array, "poles": int,
	            "paths": Array[Dictionary] }`, the last being one row per marker
	          carrying its `origin` and its `segments`.

	An EMPTY `obstacles` on purpose, in the checks that count footprints: with
	nothing already built no pole is skipped, so the pole count is the stride's
	own and the assertion is about this family rather than about whatever the
	chunk's blocks happened to be. Check 1 is the one that runs the real pipeline.
	"""
	var batch: Array = []
	var obstacles: Array = []
	var body := StaticBody3D.new()
	var chunk := MeshInstance3D.new()
	BikePaths.spawn_bike_path_in_chunk(terrain, chunk_pos, chunk, obstacles, batch, body)
	var paths: Array[Dictionary] = []
	var poles: int = 0
	for marker: Node in _markers(chunk):
		var mine: PackedInt32Array = marker.get_meta("poles")
		poles += mine.size()
		paths.append({
			"origin": marker.get_meta("origin"),
			"segments": marker.get_meta("segments"),
		})
	# Everything this call built is freed here — a self-check that leaked a node
	# per chunk over a 29x29 sweep would be the slowest check in the suite.
	chunk.free()
	body.free()
	return { "batch": batch, "obstacles": obstacles, "poles": poles, "paths": paths }


func _markers(chunk: Node) -> Array[Node]:
	## This family's bare Node3Ds, found BY GROUP the way the game finds them.
	var out: Array[Node] = []
	for child: Node in chunk.get_children():
		if child.is_in_group(BikePaths.BIKE_PATH_GROUP):
			out.append(child)
	return out


func _strip_positions(terrain: Node3D, chunk_pos: Vector2i, batch: Array) -> Array[Vector2]:
	"""
	The WORLD XZ centre of every STRIP box in `batch`.

	A strip is picked out by its height alone — `BIKE_PATH_THICKNESS * 0.5`, the
	only box this family puts there (the dashes ride on top of it and the posts
	stand half their own height up) — so this needs no index and no meta, which
	is what keeps it independent of the bookkeeping the rest of the file trusts.

	World, not chunk-local: the chunk node stands at `chunk_to_world(chunk_pos)`
	and a batch entry's transform origin is relative to it, so this is the sum.
	"""
	var at: Vector3 = terrain.chunk_to_world(chunk_pos)
	var out: Array[Vector2] = []
	for entry_v: Variant in batch:
		var t: Transform3D = (entry_v as Dictionary)["transform"]
		if not is_equal_approx(t.origin.y, BikePaths.BIKE_PATH_THICKNESS * 0.5):
			continue
		out.append(Vector2(at.x + t.origin.x, at.z + t.origin.z))
	return out


func _multimesh_table(chunk: Node) -> Dictionary:
	## Every `BlockMultiMesh*` child as name -> [[transform, colour], ...], which
	## is the batch as it survived into the GPU buffer.
	var out: Dictionary = {}
	for child: Node in chunk.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
		var rows: Array = []
		for i in mm.instance_count:
			rows.append([mm.get_instance_transform(i), mm.get_instance_color(i)])
		out[String(child.name)] = rows
	return out


func _node_table(chunk: Node) -> Array[String]:
	## Every chunk-parented NODE — crocodiles, coins, accents — as a sorted list of
	## descriptors. This is the half of check 1 that catches a stray draw from the
	## shared chunk stream, since one extra draw slides every body in the chunk.
	## The batch's own children and this family's markers are excluded: they are
	## compared by the MultiMesh table and by the slice respectively.
	var out: Array[String] = []
	for child: Node in chunk.get_children():
		if child is MultiMeshInstance3D or String(child.name) == BLOCK_BODY:
			continue
		if child.is_in_group(BikePaths.BIKE_PATH_GROUP):
			continue
		var at: Vector3 = (child as Node3D).position if child is Node3D else Vector3.ZERO
		# CLASS AND POSITION, NEVER THE NODE NAME. Godot auto-names an unnamed
		# instance with a process-wide counter, so the two terrains this check
		# builds side by side would disagree about every generated name while
		# agreeing about every position — the one difference that means nothing.
		out.append("%s|%.4f,%.4f,%.4f" % [child.get_class(), at.x, at.y, at.z])
	out.sort()
	return out


func _shape_count(chunk: Node) -> int:
	## How many collision shapes hang on the chunk's single shared block body.
	for child: Node in chunk.get_children():
		if String(child.name) == BLOCK_BODY:
			return child.get_child_count()
	return 0
