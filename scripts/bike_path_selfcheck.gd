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
##
## ...and child `.2` — the four authored signs and the traffic head — adds six
## (7, 8, 7c, 9, 10 and 11), which is what `_run()` calls:
##
##   7 + 8. WHAT STANDS ON THE POLES, in one sweep because they share it. Every
##      pole carries EXACTLY ONE top; every top is a legal kind; all four sign
##      kinds AND the signal head turn up across the seeds, because a kind that
##      can never be drawn is a dead branch and a broken dispatch looks exactly
##      like one. And every box this family emits is still a `BoxKind.CUBE` with
##      the signs and the heads present, which is `batch_selfcheck` check 5's
##      `KIND_CAP_BY_NAME` table needing no row changed, asserted where the boxes
##      are rather than promised in a comment.
##   7c. AND WHERE THAT TOP ACTUALLY STANDS. Every box a pole carries within the
##      post's own height must be IN FRONT of the post, measured off the emitted
##      transforms. Round 1 of the review found the sign plate built at the post's
##      own centre, inside a 0.16 m box — a grey bar down the middle of every sign
##      and CROSSING's centre pip swallowed whole — and NOTHING above could see it:
##      7 and 8 count, 9 indexes, 1 and 5 compare a build to a build. It is `.1`'s
##      25 m bug in miniature, and this is the assertion shaped like the one that
##      caught that. Its control is the predicate run on the post itself.
##   9. THE INDEX, AND IT IS THE REASON THIS BEAD WAS NOT MECHANICAL. A lamp's
##      MultiMesh instance index is its position among the CUBE ENTRIES ONLY —
##      `_build_block_multimesh` buckets by kind — so the index the marker records
##      is not its index in `block_batch` and an index one out still writes a
##      perfectly valid box. MULTIMESH INSTANCE DATA IS WRITE-ONLY UNDER THE
##      HEADLESS DUMMY RENDERER (measured — see that check), so "read the colour
##      back" is not available and would have read black at every index and passed
##      with any base. Instead the recorded index is compared against what the
##      SHIPPED `_build_block_multimesh` does with the very batch the spawner
##      wrote, on a fixture that holds non-CUBE boxes too; its control is that a
##      lens's batch index and its bucket index must be DIFFERENT NUMBERS, or the
##      check could not tell the two apart. Then the head's own Timer is fired
##      through its `timeout` signal on a real chunk, which steps the phase only if
##      the connection, the Timer -> bucket walk and the index range all hold — and
##      its control is a deliberately out-of-range index, which must not step.
##  10. THE CYCLE IS NOT ON THE SEED. Two terrains on the same seed build the head
##      geometry byte-identically (so nothing drawn depends on the `randomize()`d
##      clock), and the plant/tick/write functions are read AS TEXT: the plant
##      randomizes and never touches `run_seed`, the geometry never randomizes, and
##      the write linearises. `scarcity_selfcheck` check 3's shape, and the only
##      form of those three assertions a future edit cannot slip past.
##  11. AN UNLOADED CHUNK LEAVES NO TIMER BEHIND. The cycle Timer hangs off this
##      family's marker rather than off the chunk (a deliberate departure from the
##      bead — it keeps the Timer out of the child list check 1 compares), which is
##      only safe if it is still freed with the chunk. Measured through the shipped
##      `remove_chunk()`, which is `queue_free`, so this is the one check in the
##      file that awaits a frame. Its control is a second chunk left loaded, whose
##      Timer must still be alive at the end.

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

## Checks 7-8 sweep THREE seeds, so their square is smaller than `SWEEP_HALF`'s —
## 19x19 chunks per seed is a few hundred poles, which is two orders of magnitude
## more than the five-kind histogram needs and still a fraction of a second. The
## histogram is the assertion; the square is only its cost.
const TOP_SWEEP_HALF: int = 9

## How many boxes check 7c will read as a pole's top. `_draw_path_share` emits the
## post and then exactly one top, and the largest top is four boxes (a head plus its
## three lenses; CROSSING is a plate plus three pips). The run also stops at the next
## post or at ground level, so this is a bound and not a count.
const TOP_BOXES_MAX: int = 4

## Below this height, in metres, a box is this family's PAINT — the strip sits at 0.03
## and a dash at 0.075, so anything under it is the next segment's rather than the
## pole's top. It is what ends the run when a pole's top is shorter than
## `TOP_BOXES_MAX`.
const GROUND_BAND: float = 0.2

## Float slack on check 7c's clearance comparison, metres. The two sides are computed
## from the same constants a few calls apart, so this is precision and not an
## allowance: a real overlap is centimetres, not microns.
const CLEARANCE_TOLERANCE: float = 0.0005

## Check 9's fixture prefix: the kinds a real chunk already holds by the time this
## family runs — a mast, a rock, a wedged roof. THREE of the seven are CUBEs, so a
## bike-path box's CUBE-bucket index and its batch index are DIFFERENT NUMBERS,
## which is the only reason that check can tell one from the other. Check 9 (b)
## fails loudly if this stops being true.
const PREFIX_KINDS: Array[int] = [
	ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.ROCK,
	ChunkBatch.BoxKind.CUBE, ChunkBatch.BoxKind.CYLINDER, ChunkBatch.BoxKind.WEDGE,
	ChunkBatch.BoxKind.CUBE,
]

## How many chunks check 9 will build for real looking for a head that survived
## the pole's footprint skip. A bare-spawner hit is only a candidate — see that
## check — and at the shipped mix most candidates do survive, so this is a bound
## on a search that normally ends on its first try.
const LAMP_CANDIDATES: int = 12

## Check 10b reads this family AS TEXT.
const FAMILY_SCRIPT: String = "res://scripts/terrain_bike_paths.gd"

## `[function, needle, must contain, why]`. Each row is a rule that a behavioural
## check can only speak for the world it sampled, so it is read out of the source
## instead — `scarcity_selfcheck` check 3's form. The needles are deliberately the
## CODE spelling and not the prose one (`rng.randomize()`, not `randomize()`), so a
## rule cannot be satisfied by the docstring that explains it.
const TEXT_RULES: Array[Array] = [
	["_plant_signal_timers", "rng.randomize()", true,
		"the traffic light's phase and dwell are AMBIENCE and CLAUDE.md puts ambience "
		+ "outside the determinism contract on a randomize()d RNG. A seeded clock would "
		+ "put two peers' lamps in lockstep, which is a promise this game does not make "
		+ "and the wire does not carry"],
	["_plant_signal_timers", "run_seed", false,
		"the cycle must never read the seed — see the rule above. Placement is seeded; "
		+ "the clock is not"],
	["_build_signal_head", "rng.randomize()", false,
		"the head's GEOMETRY is the seed's business and is drawn from the spawner's "
		+ "fixed-seed generator. Randomising it would make the same chunk differ between "
		+ "two players, which is the one thing the world contract forbids"],
	["write_lamps", ".srgb_to_linear())", true,
		"create_box stores its colour already linearised (chunk_batch.gd's COLOUR SPACE "
		+ "paragraph), so a raw Color written into the MultiMesh renders one lamp "
		+ "brighter than every other box in the world, on desktop and on web"],
]

## How far two colours may differ and still count as the same. A float-comparison
## tolerance and not a design allowance: both sides of every comparison in check 9
## run the same `srgb_to_linear()` on the same constant, so anything above the
## MultiMesh buffer's own float precision is a different colour.
const COLOR_TOLERANCE: float = 0.002

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
	_check_tops_and_cubes(terrain_script)
	_check_sign_clearance(terrain_script)
	_check_lamp_indices(terrain_script)
	_check_cycle_off_the_seed(terrain_script)
	# AWAITED, and it is the only one that is: a chunk unloads through `queue_free`,
	# so the check has to let a frame pass before it can ask whether the Timer is
	# really gone. See `_check_unload`.
	await _check_unload(terrain_script)

	if _failures.is_empty():
		print("bike paths: the kill switch leaves every other box in the world where "
				+ "it was, each strip stands on the ground its own walk cleared, the "
				+ "per-chunk shares cover every segment exactly once, blocked paths "
				+ "truncate rather than gap, scarcity empties the far field, no chunk "
				+ "grew a MultiMesh bucket, only the poles claim a footprint, every "
				+ "pole carries one of the five authored tops and stands it clear of "
				+ "its own post, the CUBE-bucket index recorded for a lamp is the one "
				+ "the shipped bucketing really puts it at, the cycle is randomize()d "
				+ "ambience the seed cannot see, and an unloaded chunk leaves no Timer "
				+ "behind")
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
# CHECKS 7 + 8 — one top per pole, all five kinds drawn, and all of them CUBEs
# ============================================================================

func _check_tops_and_cubes(terrain_script: GDScript) -> void:
	"""
	Every pole carries exactly one top; every kind the table can produce is really
	produced; and every box this family emits is still a CUBE.

	ONE SWEEP FOR BOTH, because both are statements about the same boxes and the
	sweep is the expensive part.

	WHY "ALL FIVE KINDS APPEAR" IS THE ASSERTION AND NOT A NICETY: the top is a HASH
	DISPATCH into a fixed table, and the two ways that breaks are a fold that cannot
	reach part of the table (a negative modulo, a mask too narrow, a `% 4` left over
	from a four-row version) and a table row nothing indexes. Both leave a kind that
	can never be drawn — a dead branch that no other check in this file, and nothing
	in the game, would ever notice. Counting the histogram over three seeds is the
	control that catches it.

	THE CUBE HALF is `batch_selfcheck` check 5's `KIND_CAP_BY_NAME` ruling, asserted
	on the entries themselves. Check 5 above compares a chunk's BUCKETS with the
	paths on and off, which is the same statement from the outside; this one also
	fails if a sign plate is emitted as a CYLINDER in a chunk that already had a
	CYLINDER bucket from its own biome content — the case the bucket comparison
	cannot see, and exactly the mast the epic refused.
	"""
	var histogram: Dictionary = {}
	var poles_seen: int = 0
	var boxes_seen: int = 0
	for seed_value: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, seed_value, true)
		for ox in range(-TOP_SWEEP_HALF, TOP_SWEEP_HALF + 1):
			for oy in range(-TOP_SWEEP_HALF, TOP_SWEEP_HALF + 1):
				var chunk_pos := Vector2i(ox, oy)
				var built: Dictionary = _spawn_bare(terrain, chunk_pos)
				for entry_v: Variant in (built["batch"] as Array):
					boxes_seen += 1
					var kind: int = (entry_v as Dictionary).get("kind", ChunkBatch.BoxKind.CUBE)
					if kind != ChunkBatch.BoxKind.CUBE:
						_fail("seed %d chunk %s emitted a box of kind %s — this family is CUBE "
								% [seed_value, chunk_pos, ChunkBatch.BoxKind.find_key(kind)]
								+ "only, so that `KIND_CAP_BY_NAME` in batch_selfcheck needs no "
								+ "row changed and a path costs no chunk a second draw call")
						break
				for row: Dictionary in (built["paths"] as Array[Dictionary]):
					var poles: PackedInt32Array = row["poles"]
					var tops: PackedInt32Array = row["tops"]
					var signals: PackedInt32Array = row["signals"]
					poles_seen += poles.size()
					if tops.size() != poles.size():
						_fail("seed %d chunk %s origin %s built %d poles but recorded %d tops — "
								% [seed_value, chunk_pos, row["origin"], poles.size(), tops.size()]
								+ "every pole carries exactly one sign or one head, and a pole "
								+ "skipped for a footprint must skip its top with it")
					var heads: int = 0
					for top: int in tops:
						if top != BikePaths.POLE_TOP_SIGNAL \
								and (top < 0 or top >= BikePaths.SIGN_KINDS.size()):
							_fail("seed %d chunk %s: a pole carries top %d, which is neither a "
									% [seed_value, chunk_pos, top] + "SIGN_KINDS index nor "
									+ "POLE_TOP_SIGNAL — the dispatch fold is out of range")
							continue
						if top == BikePaths.POLE_TOP_SIGNAL:
							heads += 1
						histogram[top] = int(histogram.get(top, 0)) + 1
					if signals.size() != heads:
						_fail("seed %d chunk %s origin %s dispatched %d signal heads but recorded "
								% [seed_value, chunk_pos, row["origin"], heads]
								+ "%d lamp indices — the cycle would drive a head that is not "
								% signals.size() + "there, or leave one dark forever")
		terrain.free()

	if poles_seen == 0:
		_fail("checks 7-8 swept %d seeds x %dx%d chunks and found no pole at all, so every "
				% [SEEDS.size(), TOP_SWEEP_HALF * 2 + 1, TOP_SWEEP_HALF * 2 + 1]
				+ "assertion about what stands on one was vacuous")
	if boxes_seen == 0:
		_fail("checks 7-8 found no box at all in the sweep, so 'CUBE only' asserted nothing")
	for kind in BikePaths.SIGN_KINDS.size():
		if not histogram.has(kind):
			_fail("sign kind %d (`%s`) was never once drawn in %d seeds x %dx%d chunks over "
					% [kind, _sign_name(kind), SEEDS.size(), TOP_SWEEP_HALF * 2 + 1,
					TOP_SWEEP_HALF * 2 + 1] + "%d poles — it is a dead branch, which is what a "
					% poles_seen + "dispatch fold that cannot reach the whole of POLE_TOPS looks "
					+ "like from the outside")
	if not histogram.has(BikePaths.POLE_TOP_SIGNAL):
		_fail("not one traffic head was dispatched over %d poles — the cycling signal, which "
				% poles_seen + "is half of this bead, is never built and check 9 has nothing "
				+ "to read")
	Sentinel.done("tops_and_cubes")


func _sign_name(kind: int) -> String:
	## The authored sign kinds in `SIGN_KINDS` order, for a message a reader can act
	## on. A plain lookup table: the family stores no names (a sign carries no text,
	## which is the whole ruling), so this is the one place they are written down.
	return ["ROUTE", "YIELD", "STOP", "CROSSING"][kind] if kind >= 0 and kind < 4 \
			else "kind %d" % kind


# ============================================================================
# CHECK 7c — a sign stands CLEAR of its own post
# ============================================================================

func _check_sign_clearance(terrain_script: GDScript) -> void:
	"""
	EVERY BOX A POLE CARRIES THAT STANDS WITHIN THE POST'S OWN HEIGHT MUST BE IN
	FRONT OF THE POST, measured off the drawn boxes.

	This is round 1's major, turned into an assertion. A sign plate is
	`SIGN_PLATE_DEPTH` = 0.05 thick and the post it hangs on is `BIKE_POLE_WIDTH` =
	0.16 square, so a plate centred on the post's own XZ is INSIDE it: the sign reads
	with a grey bar straight down its middle, and CROSSING's centre bar — one of its
	three — is swallowed whole. NOTHING ELSE IN THIS FILE COULD SEE THAT. Checks 7
	and 8 count tops and box kinds, check 9 pins indices, check 1 compares a build to
	a build, and the style shot that would have shown it is deferred. It is the same
	shape as `.1`'s 25 m bug: every count was right and the geometry was wrong.

	MEASURED OFF THE TRANSFORMS AND NOT OFF THE CONSTANTS. A batch entry's own basis
	carries its facing and its size (`Basis(UP, yaw).scaled_local(dims)`, so
	`basis.x` is the approach axis scaled by the box's depth), so the post and the
	sign are each read from what was actually emitted — a check written against
	`SIGN_STANDOFF` would agree with any value of it, including zero.

	ONLY BOXES INSIDE THE POST'S HEIGHT are held to it: the traffic head sits ON TOP
	of the post (its lenses are above `BIKE_POLE_HEIGHT`), so it is not occluded by
	anything and is exempt by construction rather than by exception.

	ITS CONTROL is the predicate applied to the POST ITSELF, which must report a
	failure — a post is not clear of a post. Without it "every sign is clear" would
	also be what a predicate that can never fail prints.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var posts_seen: int = 0
	var signs_seen: int = 0
	var control_fired: bool = false
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, chunk_pos)
			var batch: Array = built["batch"]
			for row: Dictionary in (built["paths"] as Array[Dictionary]):
				for p: int in (row["poles"] as PackedInt32Array):
					if p < 0 or p >= batch.size():
						_fail("chunk %s: the marker records a pole at CUBE instance %d and the "
								% [chunk_pos, p] + "chunk's own batch holds %d boxes"
								% batch.size())
						continue
					var post: Transform3D = (batch[p] as Dictionary)["transform"]
					# THE INDEX IS THE TIE, and asserting it is free: `_spawn_bare` starts
					# from an EMPTY batch and this family emits CUBEs only, so a pole's
					# CUBE-bucket index IS its batch index here. If that ever stops being
					# true the entry at `p` is not a post and this says so, rather than
					# quietly measuring the wrong box.
					if not _is_post(post):
						_fail("chunk %s: the marker records a pole at index %d, but the box "
								% [chunk_pos, p] + "there is not a post — the recorded index and "
								+ "the geometry have come apart")
						continue
					posts_seen += 1
					if not control_fired:
						# THE CONTROL: a post is not clear of itself.
						control_fired = true
						if _clearance_fault(post, post) == "":
							_fail("check 7c's clearance predicate calls the POST ITSELF clear of "
									+ "the post, so it cannot fail and 'every sign stands clear' "
									+ "is an assertion about nothing")
					# THE TOP IS THE CONTIGUOUS RUN AFTER THE POST — `_draw_path_share`
					# emits the pole and then its one top, nothing between. Bounding it by
					# `TOP_BOXES_MAX` and stopping at the next post or at ground level is
					# what keeps a CROSSING path's strip out: two bike paths may cross, and
					# a filter that took every box within a radius of the post would read a
					# foreign 5 m strip box as a sign buried in it and fail a correct world.
					for k in range(p + 1, mini(p + 1 + TOP_BOXES_MAX, batch.size())):
						var box: Transform3D = (batch[k] as Dictionary)["transform"]
						if _is_post(box) or box.origin.y < GROUND_BAND:
							break
						# Above the post's own top nothing can be occluded by it — that is
						# where the traffic head lives, exempt by construction.
						if box.origin.y + box.basis.y.length() * 0.5 > BikePaths.BIKE_POLE_HEIGHT:
							continue
						signs_seen += 1
						var fault: String = _clearance_fault(post, box)
						if fault != "":
							_fail("chunk %s: box %d, which the pole at index %d carries, %s. A "
									% [chunk_pos, k, p, fault] + "plate or a pictogram inside the "
									+ "post reads with a grey bar down its middle, and a centred "
									+ "pip does not read at all — see `SIGN_STANDOFF`")
	terrain.free()
	if posts_seen == 0:
		_fail("check 7c swept %dx%d chunks and found no post at all, so it measured nothing"
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1])
	if signs_seen == 0:
		_fail("check 7c found %d posts and not one box standing on any of them within the "
				% posts_seen + "post's own height — the sign geometry it exists to measure was "
				+ "never looked at (did every plate move above BIKE_POLE_HEIGHT, or is "
				+ "TOP_BOXES_MAX now too small to reach one?)")
	Sentinel.done("sign_clearance")


func _is_post(t: Transform3D) -> bool:
	## A pole post, picked out by its own dimensions and its centre height — no meta
	## and no index, the same way `_strip_positions` finds a strip.
	return is_equal_approx(t.origin.y, BikePaths.BIKE_POLE_HEIGHT * 0.5) \
			and is_equal_approx(t.basis.y.length(), BikePaths.BIKE_POLE_HEIGHT) \
			and is_equal_approx(t.basis.x.length(), BikePaths.BIKE_POLE_WIDTH)


func _clearance_fault(post: Transform3D, box: Transform3D) -> String:
	"""
	Does `box` stand in front of `post` along the post's own approach axis?

	@return: "" when it does, otherwise the overlap in words.

	`basis.x` is the box's local +X scaled by its depth, and for this family local +X
	is the direction of travel (`yaw == -head`), so its normalised form is the axis
	and its length is the depth. A sign is built on the -X side, so "in front" is a
	NEGATIVE offset along that axis, and the near face must clear the post's own half
	width.
	"""
	var axis: Vector3 = post.basis.x.normalized()
	var along: float = (box.origin - post.origin).dot(axis)
	var depth: float = box.basis.x.length()
	var near: float = -along - depth * 0.5
	if near >= BikePaths.BIKE_POLE_WIDTH * 0.5 - CLEARANCE_TOLERANCE:
		return ""
	return "stands %.3f m in front of the post's centre and is %.3f m deep, so its near " \
			% [-along, depth] + "face is %.3f m out where the post's own is %.3f m" \
			% [near, BikePaths.BIKE_POLE_WIDTH * 0.5]


# ============================================================================
# CHECK 9 — the recorded CUBE-bucket index really is that lamp
# ============================================================================

func _check_lamp_indices(terrain_script: GDScript) -> void:
	"""
	THE CHECK THIS BEAD EXISTS FOR.

	`ChunkBatch._build_block_multimesh` buckets the batch BY KIND and emits in ENUM
	order, so a lamp's MultiMesh instance index is its position among the CUBE
	ENTRIES ONLY — never its index in `block_batch`. The spawner records the former,
	and an index one out still addresses a real box: the head above it, the lens
	below it, or some other family's block entirely. Nothing in the game would ever
	report that; one lamp would simply light the wrong thing.

	WHAT A HEADLESS CHECK CAN AND CANNOT SEE, measured before this check was written
	because the obvious form of it is a mirage: under the dummy rendering server
	`--headless` runs on, MULTIMESH INSTANCE DATA IS WRITE-ONLY.
	`get_instance_color()` returns opaque black and `get_instance_transform()` the
	identity for every instance of every MultiMesh, and `buffer` comes back empty
	(measured on a two-instance MultiMesh built by hand, in and out of the tree).
	So "read the colour back at the recorded index" cannot be the assertion here —
	it would read black at every index, pass with any base, and look like coverage.
	`instance_count` IS real, and so is everything in `block_batch`, and this check
	is built out of those two.

	  (a) THE INDEX, END TO END AND WITHOUT A SECOND COPY OF THE BUCKETING RULE. Run
	      the shipped spawner into a batch that already holds NON-CUBE entries (the
	      masts, rocks and trees a real chunk has by the time this family runs), find
	      the three lamp boxes in that batch by their own colour, and ask the SHIPPED
	      `ChunkBatch._build_block_multimesh` where each of them lands: built on the
	      batch TRUNCATED at a lamp, the CUBE bucket's `instance_count` IS that
	      lamp's CUBE-bucket index. That number must equal what the marker recorded.
	  (b) THE CONTROL, permanent and not a mutation someone once ran: the lamp's
	      BATCH index must differ from its CUBE-bucket index. If they were equal the
	      whole check would pass just as well on a spawner that recorded the batch
	      index — the exact bug it exists for — so a fixture that stopped containing
	      non-CUBE entries has to fail loudly rather than quietly assert nothing.
	  (c) THE LIVE PLUMBING, on a REAL chunk built through `create_chunk`. Fire the
	      head's own Timer through its `timeout` signal and assert the phase
	      ADVANCED — which it can only do if the connection reached
	      `BikePaths.tick_signal`, if `signal_multimesh()` found the chunk's CUBE
	      bucket from the Timer, and if `base + 3` really is inside that bucket's
	      `instance_count`; every one of those failures returns early and leaves the
	      phase alone. Its control is a Timer whose `lamp0` is deliberately out of
	      range, which must NOT advance.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)

	# THE SWEEP, and it collects two different things at once. The bare spawner below
	# is handed an EMPTY `obstacles`, so no pole is skipped and every chunk that CAN
	# carry a head does; in a real chunk a pole whose site is already taken is skipped
	# and takes its head with it. So a hit here is a candidate for (c) and nothing
	# more — while its batch, a real run of the shipped spawner, is what (a) needs.
	var candidates: Array[Vector2i] = []
	var probe := Vector2i(0, 0)
	var batch: Array = []
	var bases := PackedInt32Array()
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if candidates.size() >= LAMP_CANDIDATES:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var pos := Vector2i(ox, oy)
			var trial: Array = _prefix_batch()
			var obstacles: Array = []
			var body := StaticBody3D.new()
			var chunk := MeshInstance3D.new()
			BikePaths.spawn_bike_path_in_chunk(terrain, pos, chunk, obstacles, trial, body)
			var here := PackedInt32Array()
			for marker: Node in _markers(chunk):
				here.append_array(marker.get_meta("signals") as PackedInt32Array)
			chunk.free()
			body.free()
			if here.is_empty():
				continue
			candidates.append(pos)
			if batch.is_empty():
				probe = pos
				batch = trial
				bases = here
			if candidates.size() >= LAMP_CANDIDATES:
				break
	if bases.is_empty():
		_fail("check 9 swept %dx%d chunks on seed %d and found no traffic head at all, so the "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1, SEEDS[0]] + "one assertion in this "
				+ "file that ties a recorded MultiMesh index to the lamp it claims to address "
				+ "never fired")
		terrain.free()
		Sentinel.done("lamp_indices")
		return

	# --- (a) THE INDEX. Find the lenses in the batch by their own colour — the three
	# DARKENED lamp colours are the only boxes in the world drawn in them — and ask
	# the shipped bucketing function where each one lands.
	var dark := PackedColorArray()
	for j in 3:
		dark.append(BikePaths.lamp_color(terrain, j, false).srgb_to_linear())
	var lamp_rows: Array[Array] = []
	for t in batch.size():
		var c: Color = (batch[t] as Dictionary)["color"]
		for j in 3:
			if _same_color(c, dark[j]):
				lamp_rows.append([t, j])
				break
	if lamp_rows.size() != bases.size() * 3:
		_fail("chunk %s recorded %d traffic heads but its batch holds %d boxes painted in the "
				% [probe, bases.size(), lamp_rows.size()] + "three lens colours — a head is "
				+ "three lenses, and `signals` must carry exactly one entry per head")
	else:
		for n in bases.size():
			for j in 3:
				var row: Array = lamp_rows[n * 3 + j]
				if int(row[1]) != j:
					_fail("chunk %s head %d: the lenses are emitted out of order — `SIGNAL_LIT` "
							% [probe, n] + "and the cycle both assume the stack is built "
							+ "top-down red, amber, green")
					continue
				var want: int = bases[n] + j
				var got: int = _cube_index_of(batch, int(row[0]))
				if got != want:
					_fail("chunk %s head %d: the marker records its %s lens at CUBE instance %d, "
							% [probe, n, ["red", "amber", "green"][j], want]
							+ "but that box is batch entry %d, which the shipped "
							% int(row[0]) + "`_build_block_multimesh` puts at CUBE instance %d. "
							% got + "A lamp's instance index is its position among the CUBE "
							+ "ENTRIES ONLY (the batch is bucketed BY KIND and emitted in ENUM "
							+ "order) — recording a `block_batch` index, or forgetting the head "
							+ "box that precedes the lenses, is exactly what this looks like")
		# --- (b) THE CONTROL. If a lens's batch index and its CUBE-bucket index were
		# the same number, every assertion above would hold just as well for a spawner
		# that recorded the wrong one, and this check would be decoration.
		var first: Array = lamp_rows[0]
		if int(first[0]) == bases[0]:
			_fail("check 9's fixture has stopped containing non-CUBE boxes: the first lens is "
					+ "batch entry %d AND CUBE instance %d, so the assertions above cannot tell "
					% [int(first[0]), bases[0]] + "a batch index from a bucket index — which is "
					+ "the only bug they exist to catch. Restore PREFIX_KINDS")
		if bases[0] <= 0:
			_fail("check 9's fixture put the first lens at CUBE instance %d, so the offset this "
					% bases[0] + "check is about is zero and any bookkeeping would pass")

	# --- (c) THE LIVE PLUMBING, on a chunk built through the shipped `create_chunk`.
	var timer: Timer = null
	var live := Vector2i(0, 0)
	var instances: int = 0
	for candidate: Vector2i in candidates:
		terrain.create_chunk(candidate)
		var chunk_node: Node = terrain.active_chunks[candidate]
		var bucket: Node = chunk_node.get_node_or_null(CUBE_BUCKET)
		timer = _signal_timer(chunk_node)
		if timer == null or bucket == null:
			timer = null
			continue
		live = candidate
		instances = (bucket as MultiMeshInstance3D).multimesh.instance_count
		break
	if timer == null:
		_fail("check 9 built %d chunks that carry a traffic head through the bare spawner and "
				% candidates.size() + "not one of them grew a head and a CUBE bucket for real, "
				+ "so the Timer, its connection and the node walk from Timer to bucket are all "
				+ "untested. Raise LAMP_CANDIDATES, or find out why every candidate pole is "
				+ "being skipped")
		terrain.free()
		Sentinel.done("lamp_indices")
		return
	var live_base: int = int(timer.get_meta("lamp0"))
	if live_base + 3 > instances:
		_fail("chunk %s: the head's lenses are recorded at CUBE instances [%d, %d) and the built "
				% [live, live_base, live_base + 3] + "bucket holds %d — the cycle would write "
				% instances + "off the end of the buffer and silently do nothing forever")
	var phase: int = int(timer.get_meta("phase"))
	for step in 2:
		# A TICK THROUGH THE TIMER'S OWN SIGNAL, so the `connect` at plant time is
		# under test along with everything else. The phase can only advance if the
		# callable arrived, if `signal_multimesh()` walked Timer -> marker -> chunk ->
		# bucket, and if `base + 3` is inside that bucket: every other outcome returns
		# early and leaves the phase alone.
		timer.timeout.emit()
		var stepped: int = int(timer.get_meta("phase"))
		if stepped != (phase + 1) % 3:
			_fail("chunk %s: tick %d left the head at phase %d, not %d — either the Timer's "
					% [live, step, stepped, (phase + 1) % 3] + "`timeout` never reaches "
					+ "`BikePaths.tick_signal`, or the tick bailed out because it could not walk "
					+ "from the Timer to the chunk's '%s', or because the recorded index is "
					% CUBE_BUCKET + "outside that bucket. The lamps would never change")
			break
		phase = stepped
	# THE CONTROL ON THAT ASSERTION: the phase advances only where the write is really
	# addressable, so an index off the end must leave it exactly where it was. Without
	# this, "the phase advanced" would also be satisfied by a tick that stepped first
	# and checked afterwards — which is a tick that writes into a neighbour's boxes.
	timer.set_meta("lamp0", instances)
	var held: int = int(timer.get_meta("phase"))
	timer.timeout.emit()
	if int(timer.get_meta("phase")) != held:
		_fail("chunk %s: a head whose lenses are recorded at CUBE instance %d, one past the end "
				% [live, instances] + "of a %d-instance bucket, still stepped its phase — so the "
				% instances + "tick writes before it checks, and 'the phase advanced' says "
				+ "nothing about whether the write landed anywhere")
	terrain.free()
	Sentinel.done("lamp_indices")


func _prefix_batch() -> Array:
	"""
	A stand-in for the boxes a real chunk already holds when this family runs.

	THE POINT IS THE NON-CUBES. `_build_block_multimesh` buckets by kind, so a batch
	of nothing but CUBEs gives every box a bucket index equal to its batch index, and
	check 9 could not then tell the two apart. A real chunk has masts, rocks, trees
	and wedged roofs in it by the time the bike paths are drawn; these seven entries
	are the cheapest thing with that shape, and check 9 (b) fails if they stop having
	it.
	"""
	var out: Array = []
	for i in PREFIX_KINDS.size():
		out.append({
			"transform": Transform3D(Basis(), Vector3(float(i), 0.0, 0.0)),
			"color": Color(0.1, 0.1, 0.1),
			"kind": PREFIX_KINDS[i],
		})
	return out


func _cube_index_of(batch: Array, t: int) -> int:
	"""
	Where batch entry `t` lands in the CUBE bucket, ASKED OF THE SHIPPED BUCKETING
	FUNCTION rather than worked out here.

	Built on the batch TRUNCATED at `t`, the CUBE bucket's `instance_count` is
	exactly the number of CUBE entries before `t` — which is `t`'s own CUBE-bucket
	index. That is the whole trick, and it is why this check needs no second copy of
	`_build_block_multimesh`'s rule: a copy would agree with a broken original.
	`instance_count` is also one of the few things a MultiMesh will still tell you
	under the headless dummy renderer — see this check's docstring.
	"""
	var probe := MeshInstance3D.new()
	ChunkBatch._build_block_multimesh(probe, batch.slice(0, t))
	var node: Node = probe.get_node_or_null(CUBE_BUCKET)
	var n: int = 0 if node == null else (node as MultiMeshInstance3D).multimesh.instance_count
	probe.free()
	return n



# ============================================================================
# CHECK 10 — the cycle is ambience: the seed cannot see it
# ============================================================================

func _check_cycle_off_the_seed(terrain_script: GDScript) -> void:
	"""
	PLACEMENT is seeded, THE CYCLE IS NOT, and both halves are asserted here.

	(a) BEHAVIOURAL. Two SEPARATE terrains on the same seed build the same chunk
	    byte-identically. A `randomize()`d value that leaked into the geometry —
	    the obvious slip being to light the initial lamp from the rolled phase —
	    differs between two processes and between two terrains in one, so this is
	    the measurement that catches it. It is non-vacuous only if the chunk it
	    compares actually holds a head, which is what the sweep below insists on.

	(b) TEXTUAL, `scarcity_selfcheck` check 3's shape and for its reason: a
	    behavioural check can only speak for the world it sampled, and "this clock
	    is not on the seed" is a statement about the code. The plant randomizes and
	    never reads `run_seed`; the geometry never randomizes; the write linearises.
	    Each of the three is a rule a future edit would otherwise slip past, and the
	    check fails by name if a function it reads has been renamed away.
	"""
	# --- (a)
	var a: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var b: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var compared: int = 0
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if compared > 0:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var chunk_pos := Vector2i(ox, oy)
			var built_a: Dictionary = _spawn_bare(a, chunk_pos)
			var heads: int = 0
			for row: Dictionary in (built_a["paths"] as Array[Dictionary]):
				heads += (row["signals"] as PackedInt32Array).size()
			if heads == 0:
				continue
			var built_b: Dictionary = _spawn_bare(b, chunk_pos)
			compared += 1
			if var_to_bytes(built_a["batch"]) != var_to_bytes(built_b["batch"]):
				_fail("chunk %s carries %d traffic heads and two terrains on seed %d built it "
						% [chunk_pos, heads, SEEDS[0]] + "differently — something the "
						+ "`randomize()`d cycle rolls has leaked into the geometry, and the "
						+ "world is no longer a pure function of its seed")
			break
	if compared == 0:
		_fail("check 10a swept %dx%d chunks and found none with a traffic head in it, so its "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "same-seed comparison never "
				+ "covered the one feature in this family that has a randomize()d clock")
	a.free()
	b.free()

	# --- (b)
	var source: String = FileAccess.get_file_as_string(FAMILY_SCRIPT)
	if source.is_empty():
		_fail("could not read %s as text — check 10b cannot run" % FAMILY_SCRIPT)
		Sentinel.done("cycle_off_the_seed")
		return
	for rule: Array in TEXT_RULES:
		var fn: String = rule[0]
		var needle: String = rule[1]
		var must: bool = rule[2]
		var why: String = rule[3]
		var body: String = _function_body(source, fn)
		if body.strip_edges().is_empty():
			_fail("check 10b found no function `%s` in %s — it was renamed or removed, and "
					% [fn, FAMILY_SCRIPT] + "this assertion is now measuring nothing")
			continue
		if body.contains(needle) != must:
			_fail("`%s` %s `%s`: %s" % [fn, "must contain" if must else "must not contain",
					needle, why])
	Sentinel.done("cycle_off_the_seed")


# ============================================================================
# CHECK 11 — an unloaded chunk leaves no Timer behind
# ============================================================================

func _check_unload(terrain_script: GDScript) -> void:
	"""
	THE PARENTING RULE, MEASURED RATHER THAN TRUSTED.

	This family's Timer hangs off its MARKER, which hangs off the chunk — a
	deliberate departure from the bead, which said to parent it to the chunk itself,
	taken so the Timer stays out of the chunk's own child list (check 1 compares that
	list node for node to catch a stray draw). The departure is only safe if the
	Timer is still freed with the chunk, and "parented under it, so it must be" is a
	claim about Godot rather than a measurement. A per-chunk node that outlived its
	chunk in an endless runner is an unbounded leak AND a Timer ticking forever into
	a freed bucket.

	`remove_chunk()` is the shipped unload path and it uses `queue_free`, so this is
	the one check in the file that awaits a frame — a `free()` here would measure a
	teardown the game never performs.

	Non-vacuous by construction: it fails if it cannot find a chunk with a Timer in
	the first place, and it asserts the Timer was ALIVE before the unload as well as
	gone after it.

	ITS CONTROL IS A SECOND CHUNK THAT IS NOT UNLOADED, and its Timer must still be
	alive at the end. Without it, "the weak reference went null" is also what a check
	that had freed the whole world — or that was reading a reference which is null
	however the frame went — would print, and the assertion would pass whatever the
	unload did.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0], true)
	var found := Vector2i(0, 0)
	var timer: Timer = null
	var kept: Timer = null
	for ox in range(-SWEEP_HALF, SWEEP_HALF + 1):
		if timer != null and kept != null:
			break
		for oy in range(-SWEEP_HALF, SWEEP_HALF + 1):
			var pos := Vector2i(ox, oy)
			var built: Dictionary = _spawn_bare(terrain, pos)
			var heads: int = 0
			for row: Dictionary in (built["paths"] as Array[Dictionary]):
				heads += (row["signals"] as PackedInt32Array).size()
			if heads == 0:
				continue
			terrain.create_chunk(pos)
			var here: Timer = _signal_timer(terrain.active_chunks[pos])
			if here == null:
				continue
			if timer == null:
				timer = here
				found = pos
			elif kept == null:
				# THE CONTROL'S CHUNK: built, never unloaded, and its Timer must still
				# be alive when this check ends.
				kept = here
				break
	if timer == null:
		_fail("check 11 swept %dx%d chunks and built no chunk that carried a cycle Timer, so "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "'an unloaded chunk leaves none "
				+ "behind' was never once asked of a chunk that had one")
		terrain.free()
		Sentinel.done("unload")
		return
	var ref: WeakRef = weakref(timer)
	if ref.get_ref() == null:
		_fail("check 11's Timer was already dead before the chunk was unloaded")
	# REMEMBERED AS A BOOLEAN, AND THAT IS THE WHOLE POINT: in Godot a reference to a
	# FREED object compares equal to null, so a `kept != null` written after the unload
	# is false exactly when the control has something to say, and the guard below would
	# short-circuit itself into silence in the one state it exists to detect.
	var has_control: bool = kept != null
	if not has_control:
		_fail("check 11 found only one chunk with a cycle Timer in a %dx%d sweep, so it has no "
				% [SWEEP_HALF * 2 + 1, SWEEP_HALF * 2 + 1] + "second chunk to leave loaded — "
				+ "and without that control 'the Timer went away' is also what this check would "
				+ "print if nothing it holds survived the frame")
	var control: WeakRef = weakref(kept)
	terrain.remove_chunk(found)
	# `queue_free` frees at the end of the frame, which is why this check is awaited.
	await process_frame
	await process_frame
	if ref.get_ref() != null:
		_fail("chunk %s was unloaded through the shipped `remove_chunk()` and its bike-path "
				% found + "cycle Timer is still alive — every head the player walks past leaks "
				+ "a node that goes on ticking into a bucket that no longer exists")
	if terrain.active_chunks.has(found):
		_fail("chunk %s is still in `active_chunks` after `remove_chunk()`, so check 11 "
				% found + "measured an unload that did not happen")
	if has_control and control.get_ref() == null:
		_fail("check 11's control Timer, in a chunk that was never unloaded, died along with "
				+ "the one that was — so 'the Timer went away' says nothing about the unload")
	terrain.free()
	Sentinel.done("unload")


func _function_body(source: String, name: String) -> String:
	"""
	The lines of `func <name>(...)` up to the next top-level `func`, or "" when there
	is no such function. `scarcity_selfcheck`'s helper, and crude for its reason:
	GDScript's one-function-per-column-0-`func` layout is the whole grammar this
	needs, and `static func` counts — this family is static from end to end, so a
	matcher that only knew the instance spelling would find nothing at all and pass.
	"""
	var out: PackedStringArray = PackedStringArray()
	var inside := false
	for line: String in source.split("\n"):
		if line.begins_with("func " + name + "(") or line.begins_with("static func " + name + "("):
			inside = true
			continue
		if inside:
			if line.begins_with("func ") or line.begins_with("static func "):
				break
			out.append(line)
	return "\n".join(out)


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
			"poles": mine,
			# Child `.2`: what each of those poles carries, and each signal head's
			# first lens in CUBE-bucket coordinates. Checks 7-9.
			"tops": marker.get_meta("tops"),
			"signals": marker.get_meta("signals"),
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
	##
	## READ THIS BEFORE TRUSTING WHAT A COMPARISON OF TWO OF THESE PROVES (measured
	## at bead `.2`): under the dummy rendering server `--headless` runs on, MultiMesh
	## instance data is WRITE-ONLY — `get_instance_transform()` returns the identity
	## and `get_instance_color()` opaque black for every instance, and `buffer` comes
	## back empty. So the rows below are placeholders, and what a table-against-table
	## comparison really asserts is the BUCKET NAMES and each bucket's
	## `instance_count`. That is still the whole of check 5's claim and most of check
	## 1's (a stray draw changes a count), but the geometry itself is pinned by check
	## 2c, which reads `block_batch` directly — the batch is a plain Array of
	## Dictionaries and every field in it is real.
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


func _signal_timer(chunk: Node) -> Timer:
	## The first traffic head's cycle Timer in a built chunk. It hangs off this
	## family's MARKER rather than off the chunk itself — see
	## `BikePaths.SIGNAL_TIMER_NAME` for why — so this walks one level deeper than
	## `_markers` does.
	for marker: Node in _markers(chunk):
		for child: Node in marker.get_children():
			if child is Timer:
				return child as Timer
	return null


func _same_color(a: Color, b: Color) -> bool:
	## Equal to within float precision — see `COLOR_TOLERANCE`. Read off BATCH
	## ENTRIES, never off a built MultiMesh: instance data is write-only under the
	## headless dummy renderer (check 9's docstring carries that measurement).
	return absf(a.r - b.r) <= COLOR_TOLERANCE and absf(a.g - b.g) <= COLOR_TOLERANCE \
			and absf(a.b - b.b) <= COLOR_TOLERANCE


func _shape_count(chunk: Node) -> int:
	## How many collision shapes hang on the chunk's single shared block body.
	for child: Node in chunk.get_children():
		if String(child.name) == BLOCK_BODY:
			return child.get_child_count()
	return 0
