extends SceneTree
## Headless self-check for THE BIKE ROAD NETWORK's TOPOLOGY — the anchor table and
## the hash-dispatched trunk graph (epic `godot-test1-pnvb`, child `.1`).
##
##   godot --headless --path . --script res://scripts/bike_network_selfcheck.gd
##
## `scripts/bike_network.gd`'s banner carries the design; this file is the part of
## it a future edit cannot slip past. THE FAMILY UNDER TEST DRAWS NOTHING, so the
## usual trap of this epic — geometry that is consistently wrong against the world
## while every internal check passes — takes a different shape here: **a graph
## that is self-consistent and wrong.** An edge table that is stable,
## deterministic and joins the wrong things passes any count-based or
## determinism-based check ever written. Checks 1 and 5 are the two that tie it to
## something outside itself.
##
##   1. ZERO DRAWS, AND IT IS THE MOST IMPORTANT CHECK IN THE FILE. A field of
##      chunks built through the SHIPPED `create_chunk` twice on one seed: once
##      normally, once with `anchors()` and `edges()` asked for FIRST. Node for
##      node, MultiMesh bucket for MultiMesh bucket, collision shape for collision
##      shape. If merely ASKING for the network moves a box or slides a crocodile,
##      this bead is wrong and every child downstream inherits it. THE COMPARISON
##      COVERS EVERY CHUNK, with no exemption: this family appends no footprint and
##      emits no box, so unlike `bike_path_selfcheck` check 1 there is no chunk
##      where a difference would be sanctioned. Its controls run the other way —
##      the field must really hold chunk-parented bodies, the network really has to
##      have been built, and the comparator is proved able to FAIL by running it
##      against a second seed.
##   2. PURITY, AND THE RE-SEED. The same terrain answers identically across the
##      shipped `_drop_seeded_memos()`, so the memo is a cache and not the source
##      of truth. Then `set_run_seed()` to a different world and the tables must
##      CHANGE — a table that survives a re-seed is the multiplayer-joiner bug
##      CLAUDE.md names outright.
##   3. REACHABILITY — the owner's requirement, asserted rather than hoped. Over a
##      16-seed sweep the GATE anchor is reachable from the HQ anchor over
##      `edges()` in EVERY world. Prints the worst-case hop count and the longest
##      edge. Its control is that the walk really walks: a hop count of zero would
##      mean the two anchors were the same row.
##   4. WELL-FORMEDNESS, AND THE NUMBERS THE OWNER RETUNES AGAINST. No self-loop,
##      no duplicate unordered pair, every index in range, every dispatched degree
##      an entry of `TRUNK_DEGREES`, and — the amendment's acceptance addition —
##      NO EDGE WITH AN ENDPOINT BELOW `TRUNK_ANCHOR_MIN_K`, asserted over the
##      sweep rather than argued. Then it PRINTS: total anchors, trunkable anchors,
##      the edge-count histogram, and every refused anchor with its own k.
##   5. THE WORLD TIE. Every edge endpoint's position is re-derived FROM THE
##      SHIPPED ANCHOR SOURCES — `tower_site()`, `waypoint_sites()`,
##      `landmark_sites()`, `BudapestPlan.GATE` — by the id the row carries, and
##      compared against what `anchors()` put in the table. This is the assertion
##      that a self-consistent wrong graph cannot pass: checks 1-4 all compare the
##      table to itself or to a copy of itself, and would be just as green if every
##      anchor were at the origin. Its control is a deliberate perturbation, which
##      must be caught.
##
## MULTIMESH INSTANCE DATA IS WRITE-ONLY UNDER THE HEADLESS DUMMY RENDERER
## (measured at bead `godot-test1-z2yv.2`: `get_instance_color()` returns opaque
## black, `get_instance_transform()` the identity, `.buffer` empty, at every
## index). So check 1's bucket tables assert the bucket NAMES and each bucket's
## `instance_count`, which is exactly what a stray draw changes; reading a colour
## back would be vacuous coverage and there is none of it in this file.

## The end-of-check sentinel — see `scripts/selfcheck_sentinel.gd` for why every
## check stamps itself and the report site never prints SELFCHECK OK itself.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
## Check 1 builds real chunks, and a real chunk spawns real predators — without
## the scene the node half of that comparison has nothing to compare.
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## THE SWEEP. Sixteen worlds, because the network moves with `run_seed` and one
## world proves nothing about the rule — the `landmark_sites_selfcheck` /
## `scarcity_selfcheck` / `bike_path_selfcheck` house rule, widened to the count
## the bead asks for. `SEEDS[0]` is the one check 1 builds chunks on.
const SEEDS: Array[int] = [
	20260919, 777, 4242, 1, 99999, 20260904, 31337, 8675309,
	2, 123456, 555, 987654321, 42, 20250101, 6060842, 7,
]

## Check 1's A/B field: a band astride the road's first few hundred metres on
## `SEEDS[0]`, chosen because it is where the world is FURNISHED — crocodiles,
## coins and biome blocks — so the node half of the comparison has something to
## see. It moves when the stream does, which is why the check asserts the mix
## rather than trusting this comment.
const AB_X: Array[int] = [0, 1, 2, 3]
const AB_Y: Array[int] = [-1, 0, 1, 2]

## The chunk's single shared collision body — excluded from the node table, which
## is about spawned bodies, and counted separately.
const BLOCK_BODY: String = "BlockCollision"

## How far two world positions may differ and still be the same point. A float
## comparison tolerance: both sides of check 5 run the same arithmetic on the same
## doubles, so anything above this is a different place. The deliberate
## perturbation that controls it is a whole metre.
const POS_TOLERANCE: float = 0.001

var _failures: Array[String] = []


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# A coroutine because check 1 needs a terrain that is really IN the tree before
	# it calls `create_chunk` — `root.add_child()` inside `_initialize()` has not
	# put a node in the tree yet, and several spawners ask the chunk for a global
	# transform. `bike_path_selfcheck` / `waypoint_selfcheck`'s recipe.
	_run()


func _run() -> void:
	await process_frame
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	_check_zero_draws(terrain_script)
	_check_purity_and_reseed(terrain_script)
	_check_reachability(terrain_script)
	_check_well_formed(terrain_script)
	_check_world_tie(terrain_script)

	if _failures.is_empty():
		print("bike network: asking for the anchor table and the trunk graph moves "
				+ "nothing in the world, the tables are a pure function of run_seed "
				+ "across a memo drop and really change when it is rewritten, the gate "
				+ "is reachable from the HQ in every world of the sweep, no edge is "
				+ "malformed or ends outside the corridor, and every edge endpoint "
				+ "stands where the shipped anchor sources say it stands")
		Sentinel.finish(self)
		return
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


# ============================================================================
# CHECK 1 — zero draws, measured through the shipped create_chunk
# ============================================================================

func _check_zero_draws(terrain_script: GDScript) -> void:
	"""
	The same field of chunks with and without `anchors()` / `edges()` asked for
	first, compared through the SHIPPED `create_chunk` on both sides.

	WHY THE WHOLE PIPELINE AND NOT THE FAMILY ALONE: what has to hold is that this
	family costs the shared chunk / biome / crocodile streams NOTHING, and the only
	place that is visible is downstream of it. A single stray draw slides every
	crocodile and every coin in the chunk, which the node table sees. Asking the
	two functions on a bare terrain and diffing their output would prove nothing at
	all — it is exactly the self-consistent comparison this file exists to avoid.

	AND IT IS NOT ONLY ABOUT AN `rng.randi()` IN THIS FILE. `anchors()` warms the
	road station cache and the landmark site table by calling them EARLIER than a
	streaming world would. Those are memoized pure functions, so an earlier warm
	must be a no-op — and if one of them ever stops being pure, this is the check
	that says so.
	"""
	var plain: Node3D = _terrain(terrain_script, SEEDS[0])
	var asked: Node3D = _terrain(terrain_script, SEEDS[0])
	# ASKED FIRST, before a single chunk exists, which is the worst case: every
	# memo the anchor sources touch is built from cold and in this family's order
	# rather than in the streamer's.
	var anchor_rows: Array[Dictionary] = BikeNetwork.anchors(asked)
	var edge_rows: Array[Dictionary] = BikeNetwork.edges(asked)
	# A THIRD WORLD, only so the comparator below can be proved able to fail.
	var other: Node3D = _terrain(terrain_script, SEEDS[1])

	var nodes_seen: int = 0
	var buckets_seen: int = 0
	var shapes_seen: int = 0
	var comparator_bit: bool = false

	for x: int in AB_X:
		for y: int in AB_Y:
			var chunk_pos := Vector2i(x, y)
			plain.create_chunk(chunk_pos)
			asked.create_chunk(chunk_pos)
			other.create_chunk(chunk_pos)
			var a: Node = plain.active_chunks[chunk_pos]
			var b: Node = asked.active_chunks[chunk_pos]
			var c: Node = other.active_chunks[chunk_pos]

			# --- The bodies. THE HALF THAT CATCHES A STRAY DRAW: one extra draw from
			# the shared chunk stream slides every crocodile and every coin in the
			# chunk. No exemption anywhere in the field, because this family appends
			# no footprint — there is no chunk where a difference would be legal.
			var nodes_plain: Array[String] = _node_table(a)
			var nodes_asked: Array[String] = _node_table(b)
			nodes_seen += nodes_plain.size()
			if nodes_plain != nodes_asked:
				_fail("chunk %s holds %d chunk-parented nodes when the network was never "
						% [chunk_pos, nodes_plain.size()]
						+ "asked for and %d when it was asked for first. The bike network "
						% nodes_asked.size()
						+ "took a draw from the shared chunk stream — CLAUDE.md: one extra "
						+ "draw moves every spawn in the world")
			if nodes_plain != _node_table(c):
				comparator_bit = true

			# --- The boxes, bucket by bucket. Instance data is write-only headless,
			# so what this really asserts is the bucket names and their counts — which
			# is precisely what a moved or extra box changes.
			var table_plain: Dictionary = _multimesh_table(a)
			var table_asked: Dictionary = _multimesh_table(b)
			buckets_seen += table_plain.size()
			if table_plain.keys() != table_asked.keys():
				_fail("chunk %s has MultiMesh buckets %s without the network asked for and "
						% [chunk_pos, table_plain.keys()] + "%s with it — this family emits "
						% table_asked.keys() + "no box at all and may not change one")
			else:
				for name: String in table_plain:
					if var_to_bytes(table_plain[name]) != var_to_bytes(table_asked[name]):
						_fail("chunk %s: the '%s' bucket differs between the two builds — "
								% [chunk_pos, name] + "asking for the trunk graph moved "
								+ "somebody else's geometry")
						break

			# --- The collision shapes. Added inline by `create_box`, so a changed
			# count is a changed box even where the bucket count survived.
			var shapes: int = _shape_count(a)
			shapes_seen += shapes
			if shapes != _shape_count(b):
				_fail("chunk %s: %d collision shapes without the network and %d with it"
						% [chunk_pos, shapes, _shape_count(b)])

	# --- THE CONTROLS, and every one of them fails on ZERO rather than passing
	# quietly. "We found none of these" is the way an audit like this rots.
	if nodes_seen == 0:
		_fail("check 1 compared %d chunks and found no chunk-parented nodes in any of "
				% (AB_X.size() * AB_Y.size())
				+ "them — the half of this check that catches a stray draw is blind. "
				+ "Retune AB_X / AB_Y onto furnished ground")
	if buckets_seen == 0:
		_fail("check 1's field produced no MultiMesh buckets at all, so the box half of "
				+ "the comparison asserted nothing")
	if shapes_seen == 0:
		_fail("check 1's field produced no collision shapes at all, so the shape half of "
				+ "the comparison asserted nothing")
	if anchor_rows.is_empty() or edge_rows.is_empty():
		_fail("check 1 asked for the network and got %d anchors and %d edges — with an "
				% [anchor_rows.size(), edge_rows.size()]
				+ "empty table the two builds are identical by construction and this "
				+ "check passed for the wrong reason")
	if not comparator_bit:
		# THE MUTATION CONTROL, in the file rather than in a reviewer's head: a
		# `_node_table` that returned a constant would make every comparison above
		# succeed. Two different worlds must produce different tables somewhere in
		# the band, or the comparator cannot tell anything from anything.
		_fail("check 1's node comparator found NO difference between two different "
				+ "run_seeds anywhere in the band, so it cannot distinguish two worlds "
				+ "and its agreement above proves nothing")
	plain.free()
	asked.free()
	other.free()
	Sentinel.done("zero_draws")


# ============================================================================
# CHECK 2 — purity across the memo drop, and the re-seed
# ============================================================================

func _check_purity_and_reseed(terrain_script: GDScript) -> void:
	"""
	The memo is a cache, not the source of truth; and the tables really are a
	function of `run_seed`.

	THE SECOND HALF IS THE ONE WITH TEETH. A table that survives a re-seed hands a
	multiplayer joiner the wrong world — CLAUDE.md states it outright and
	`chunk_stream_selfcheck` check 6 audits the reset list structurally. This is
	the behavioural half of that, on this family: rewrite the seed through the one
	shipped door and demand the answer moves.
	"""
	var terrain: Node3D = _terrain(terrain_script, SEEDS[0])
	var anchors_a: PackedByteArray = var_to_bytes(BikeNetwork.anchors(terrain))
	var edges_a: PackedByteArray = var_to_bytes(BikeNetwork.edges(terrain))
	if anchors_a.is_empty() or edges_a.is_empty():
		_fail("check 2 serialised an empty anchor or edge table, so both of its "
				+ "comparisons below are trivially true")

	# a. THE DROP. `_drop_seeded_memos()` is the shipped function `set_run_seed()`
	# calls, and it is called here directly so the assertion is about the MEMO and
	# not about the seed write around it.
	terrain._drop_seeded_memos()
	if var_to_bytes(BikeNetwork.anchors(terrain)) != anchors_a:
		_fail("the anchor table changed across `_drop_seeded_memos()` on an unchanged "
				+ "seed — it is not a pure function of run_seed, so two peers in a room "
				+ "can disagree about where the network's endpoints are")
	if var_to_bytes(BikeNetwork.edges(terrain)) != edges_a:
		_fail("the trunk graph changed across `_drop_seeded_memos()` on an unchanged "
				+ "seed — the edge set is not a pure function of run_seed")

	# b. THE RE-SEED, through the one door CLAUDE.md allows.
	terrain.set_run_seed(SEEDS[1])
	var anchors_b: PackedByteArray = var_to_bytes(BikeNetwork.anchors(terrain))
	var edges_b: PackedByteArray = var_to_bytes(BikeNetwork.edges(terrain))
	if anchors_b == anchors_a:
		_fail("the anchor table is byte-identical across a `set_run_seed()` from %d to "
				% SEEDS[0] + "%d — `_bike_network_cache` outlived the re-seed, which is "
				% SEEDS[1] + "exactly the memo bug `_drop_seeded_memos()` exists to "
				+ "prevent (CLAUDE.md: it hands a multiplayer joiner the wrong world)")
	if edges_b == edges_a:
		_fail("the trunk graph is byte-identical across a `set_run_seed()` from %d to %d"
				% [SEEDS[0], SEEDS[1]])

	# c. ...AND BACK. The tables are not merely DIFFERENT after a re-seed, they are
	# the right ones: re-seeding to the first world must reproduce the first
	# world's answer exactly. Without this, a memo that simply cleared itself and
	# rebuilt from the clock would pass both halves above.
	terrain.set_run_seed(SEEDS[0])
	if var_to_bytes(BikeNetwork.anchors(terrain)) != anchors_a:
		_fail("re-seeding back to %d did not reproduce that world's anchor table — the "
				% SEEDS[0] + "tables depend on something that is not `run_seed`")
	if var_to_bytes(BikeNetwork.edges(terrain)) != edges_a:
		_fail("re-seeding back to %d did not reproduce that world's trunk graph"
				% SEEDS[0])
	terrain.free()
	Sentinel.done("purity_and_reseed")


# ============================================================================
# CHECK 3 — the owner's requirement: you can get to Budapest along them
# ============================================================================

func _check_reachability(terrain_script: GDScript) -> void:
	"""
	*"You should be able to GET TO BUDAPEST along them"* — over the whole sweep,
	asserted rather than hoped.

	THE REPAIR PASS IS WHAT MAKES THIS A PROPERTY OF THE CONSTRUCTION, and this is
	the check that says so out loud. If the corridor-only filter ever disconnects
	the gate from the HQ, that is a FINDING to report and not something to patch
	around by smuggling an annulus anchor back in (the epic's amendment says so in
	those words), so this check names the seed and stops.
	"""
	var worst_hops: int = 0
	var longest: float = 0.0
	var trivial: int = 0
	var walked: int = 0

	for run_seed: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, run_seed)
		var rows: Array[Dictionary] = BikeNetwork.anchors(terrain)
		var edges: Array[Dictionary] = BikeNetwork.edges(terrain)
		var hq: int = _index_of_kind(rows, BikeNetwork.KIND_HQ)
		var gate: int = _index_of_kind(rows, BikeNetwork.KIND_GATE)
		if hq < 0 or gate < 0:
			_fail("seed %d: the anchor table has no %s anchor at all"
					% [run_seed, "HQ" if hq < 0 else "GATE"])
			terrain.free()
			continue
		if hq == gate:
			trivial += 1

		var hops: Dictionary = _hop_counts(edges, hq)
		if not hops.has(gate):
			_fail("seed %d: the Budapest GATE anchor is NOT reachable from the HQ anchor "
					% run_seed + "over the %d trunks this world has. The owner's whole "
					% edges.size() + "requirement is that you can ride to the city — "
					+ "report this rather than patching around it: the repair pass may "
					+ "join components but may not reach outside the corridor")
		else:
			worst_hops = maxi(worst_hops, int(hops[gate]))
			walked += 1
		for row: Dictionary in edges:
			var pa: Vector2 = rows[int(row["a"])]["pos"]
			var pb: Vector2 = rows[int(row["b"])]["pos"]
			longest = maxf(longest, pa.distance_to(pb))
		terrain.free()

	if walked == 0:
		_fail("check 3 never once walked from the HQ to the gate across %d seeds, so its "
				% SEEDS.size() + "assertion never ran")
	if trivial > 0:
		_fail("check 3 found the HQ and the GATE at the SAME anchor index in %d of %d "
				% [trivial, SEEDS.size()] + "worlds — 'reachable' is trivially true there "
				+ "and the check proves nothing")
	if worst_hops <= 0:
		_fail("check 3's worst-case HQ-to-gate hop count came out %d over %d seeds — a "
				% [worst_hops, SEEDS.size()] + "walk of no hops is not a walk, so the "
				+ "graph search is not searching")
	print("bike network check 3: the gate is reachable from the HQ in all %d worlds; "
			% SEEDS.size() + "worst-case %d hops, longest single trunk %.0f m (cap %.0f m "
			% [worst_hops, longest, BikeNetwork.TRUNK_MAX_EDGE]
			+ "on the nearest-neighbour pass, %.0f m on the connectivity repair)"
			% BikeNetwork.TRUNK_REPAIR_MAX_EDGE)
	Sentinel.done("reachability")


# ============================================================================
# CHECK 4 — well-formedness, and the numbers the owner retunes against
# ============================================================================

func _check_well_formed(terrain_script: GDScript) -> void:
	"""
	The graph's own invariants, plus the amendment's acceptance addition (no edge
	ends outside k = 1), plus the PRINTOUT the density ruling asks for.

	RULING 2, 2026-09-19: *"the density knob must be left obvious and cheap to
	turn... check 4 prints the histogram and that printed number is what the owner
	retunes against."* And RULING 3's edge case: *"check 4 PRINTS how many landmark
	anchors were refused per seed, split by how far outside k = 1 they fell."*
	"""
	var histogram: Array[int] = []
	var trunkable_counts: Array[int] = []
	var total_anchors: int = 0
	var refused_landmarks: int = 0
	var refused_others: Array[String] = []
	var worst_landmark_k: float = 1.0
	var degrees_seen: int = 0
	var edges_seen: int = 0

	for run_seed: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, run_seed)
		var rows: Array[Dictionary] = BikeNetwork.anchors(terrain)
		var edges: Array[Dictionary] = BikeNetwork.edges(terrain)
		total_anchors = maxi(total_anchors, rows.size())

		var trunkable: int = 0
		var ids: Dictionary = {}
		for i: int in rows.size():
			# IDS ARE UNIQUE, and this assertion exists because check 5 caught the
			# collision it guards: `waypoint_sites()` carries its own "hq" and its own
			# "gate", 48 m and 124 m from this table's HQ and GATE respectively, so an
			# unprefixed row would make `id` name two different places. Every consumer
			# downstream (`.2`'s routes, `.5`'s minimap) looks a row up by id.
			if ids.has(rows[i]["id"]):
				_fail("seed %d: two anchors share the id '%s' (rows %d and %d) — an id "
						% [run_seed, rows[i]["id"], int(ids[rows[i]["id"]]), i]
						+ "that names two places is a lookup every consumer gets wrong")
			ids[rows[i]["id"]] = i
			var pos: Vector2 = rows[i]["pos"]
			var k: float = terrain.scarcity_at(Vector3(pos.x, 0.0, pos.y))
			# THE FILTER IS THE SHIPPED PURE FUNCTION, re-evaluated here rather than
			# read off the row: a `trunkable` field that had drifted from
			# `scarcity_at()` is exactly the bug the amendment forbids a second
			# rectangle in order to prevent.
			var expected: bool = k >= BikeNetwork.TRUNK_ANCHOR_MIN_K
			if bool(rows[i]["trunkable"]) != expected:
				_fail("seed %d: anchor '%s' is marked trunkable=%s but scarcity_at() at "
						% [run_seed, rows[i]["id"], rows[i]["trunkable"]]
						+ "its own position is %.4f — the corridor filter has drifted from "
						% k + "the shipped function it is defined as")
			if expected:
				trunkable += 1
			elif int(rows[i]["kind"]) == BikeNetwork.KIND_LANDMARK:
				refused_landmarks += 1
				worst_landmark_k = minf(worst_landmark_k, k)
			else:
				# A REFUSED NON-LANDMARK IS THE FINDING, not the design. The bead
				# expected the HQ, the waypoints and the gate to be inside the union by
				# construction; they are not. See the family banner.
				refused_others.append("seed %d %s k=%.3f at (%.0f, %.0f)"
						% [run_seed, rows[i]["id"], k, pos.x, pos.y])
			# THE DISPATCH ITSELF, asked of the shipped function: a degree outside the
			# table means the fold is out of range and some anchor silently took none.
			if expected:
				var deg: int = BikeNetwork._degree(terrain, i)
				degrees_seen += 1
				if not BikeNetwork.TRUNK_DEGREES.has(deg):
					_fail("seed %d: anchor %d dispatched degree %d, which is not an entry of "
							% [run_seed, i, deg] + "TRUNK_DEGREES %s"
							% str(BikeNetwork.TRUNK_DEGREES))

		var seen: Dictionary = {}
		for row: Dictionary in edges:
			edges_seen += 1
			var a: int = int(row["a"])
			var b: int = int(row["b"])
			if int(row["id"]) != edges.find(row):
				_fail("seed %d: edge row id %d is not its own index in edges()"
						% [run_seed, int(row["id"])])
			if a == b:
				_fail("seed %d: edge %d is a self-loop on anchor %d" % [run_seed, int(row["id"]), a])
			if a < 0 or b < 0 or a >= rows.size() or b >= rows.size():
				_fail("seed %d: edge %d indexes anchors (%d, %d) with only %d rows"
						% [run_seed, int(row["id"]), a, b, rows.size()])
				continue
			if a >= b:
				_fail("seed %d: edge %d is stored as (%d, %d) rather than (min, max), so "
						% [run_seed, int(row["id"]), a, b] + "the same trunk could appear "
						+ "twice under two orderings")
			var key := Vector2i(mini(a, b), maxi(a, b))
			if seen.has(key):
				_fail("seed %d: the unordered pair %s appears twice in edges()"
						% [run_seed, key])
			seen[key] = true
			for end: int in [a, b]:
				if not bool(rows[end]["trunkable"]):
					_fail("seed %d: edge %d ends at anchor '%s', which is OUTSIDE the "
							% [run_seed, int(row["id"]), rows[end]["id"]]
							+ "corridor (k < %.2f). Owner ruling 2026-09-19: the far field "
							% BikeNetwork.TRUNK_ANCHOR_MIN_K
							+ "is deliberately empty and gets no bare paint")

		histogram.append(edges.size())
		trunkable_counts.append(trunkable)
		terrain.free()

	# --- NON-VACUITY. Every "we found N of these" fails on N == 0.
	if edges_seen == 0:
		_fail("check 4 examined %d worlds and found not one edge, so every invariant "
				% SEEDS.size() + "above held over an empty table")
	if degrees_seen == 0:
		_fail("check 4 never evaluated `_degree()` on a single anchor, so the dispatch "
				+ "range assertion never ran")
	if total_anchors == 0:
		_fail("check 4 found no anchors in any world")

	histogram.sort()
	trunkable_counts.sort()
	print("bike network check 4 — THE DENSITY KNOB (owner ruling: MEDIUM). Over %d "
			% SEEDS.size() + "seeds: %d anchors per world, %d-%d of them trunkable; "
			% [total_anchors, trunkable_counts[0], trunkable_counts[-1]]
			+ "edge count %d-%d, median %d. Retune TRUNK_DEGREES %s against these."
			% [histogram[0], histogram[-1], histogram[histogram.size() / 2],
					str(BikeNetwork.TRUNK_DEGREES)])
	print("bike network check 4 — REFUSED ANCHORS. %d landmark anchors refused across "
			% refused_landmarks + "the sweep (worst k %.3f), which is the owner's stated "
			% worst_landmark_k + "intent: a landmark reachable only by leaving the "
			+ "corridor gets no trunk.")
	if refused_others.is_empty():
		print("bike network check 4 — no non-landmark anchor was refused.")
	else:
		# NOT A FAILURE, AND DELIBERATELY SO: the `>= 1.0` test is what the owner
		# ruled and it ships as written. This printout is the measurement the bead
		# asked for instead of a widened rectangle, and it says the corridor rect is
		# narrower than the road it was drawn around. See the family banner.
		print("bike network check 4 — FINDING, %d WAYPOINT anchors refused as trunk "
				% refused_others.size() + "endpoints. The bead expected the filter to "
				+ "bite only on landmarks; SCARCITY_CORRIDOR_RECT's own comment claims a "
				+ "measured max |z| of 129 m for the road and these stand further out. "
				+ "The rect is stale, not this filter:")
		for line: String in refused_others:
			print("    ", line)
	Sentinel.done("well_formed")


# ============================================================================
# CHECK 5 — THE WORLD TIE
# ============================================================================

func _check_world_tie(terrain_script: GDScript) -> void:
	"""
	EVERY EDGE ENDPOINT STANDS WHERE THE SHIPPED ANCHOR SOURCES SAY IT STANDS.

	THIS IS THE ONE ASSERTION IN THE FILE THAT IS NOT ABOUT THE TABLE'S RELATIONSHIP
	WITH ITSELF. Checks 1-4 compare a build to a build, a table to a copy of the
	table or a count to a count: an edge set that was stable, deterministic, well
	formed and joined entirely the wrong points would be green in all four. Two
	beads in the predecessor epic shipped geometry that was consistently wrong
	against the world while eleven checks between them passed, for exactly that
	reason (the strips drawn 25 m off; every sign plate built inside its post).
	This bead draws nothing, so its equivalent failure is a self-consistent wrong
	graph, and this is the assertion shaped like the one that would catch it.

	The re-derivation goes back to the FOUR SHIPPED SOURCES by the id the row
	carries — `tower_site()`, `TerrainWaypoints.waypoint_sites()`,
	`TerrainLandmarks.landmark_sites()`, `BudapestPlan.GATE` — and never to
	`anchors()`. Its control is a deliberate one-metre perturbation, which the
	comparator must catch.
	"""
	var checked: Dictionary = {}
	var endpoints: int = 0

	for run_seed: int in SEEDS:
		var terrain: Node3D = _terrain(terrain_script, run_seed)
		var rows: Array[Dictionary] = BikeNetwork.anchors(terrain)
		var edges: Array[Dictionary] = BikeNetwork.edges(terrain)
		# THE SOURCES, read independently of the table under test.
		var tower: Vector3 = terrain.tower_site()
		var waypoints: Dictionary = {}
		for site: Dictionary in TerrainWaypoints.waypoint_sites(terrain):
			var wp: Vector3 = site["pos"]
			waypoints[String(site["id"])] = Vector2(wp.x, wp.z)
		var landmarks: Dictionary = {}
		for chunk: Vector2i in TerrainLandmarks.landmark_sites(terrain):
			var centre: Vector3 = terrain.chunk_to_world(chunk)
			landmarks[int(TerrainLandmarks.landmark_sites(terrain)[chunk])] = Vector2(centre.x, centre.z)

		for row: Dictionary in edges:
			for end: int in [int(row["a"]), int(row["b"])]:
				var id: String = rows[end]["id"]
				var claimed: Vector2 = rows[end]["pos"]
				var truth := Vector2.INF
				var source: String = ""
				if id == "hq":
					truth = Vector2(tower.x, tower.z)
					source = "tower_site()"
				elif id == "gate":
					truth = Vector2(BudapestPlan.GATE.x, BudapestPlan.GATE.z)
					source = "BudapestPlan.GATE"
				elif id.begins_with("wp_") and waypoints.has(id.trim_prefix("wp_")):
					truth = waypoints[id.trim_prefix("wp_")]
					source = "TerrainWaypoints.waypoint_sites()"
				elif id.begins_with("landmark_"):
					var kind: int = int(id.trim_prefix("landmark_"))
					if not landmarks.has(kind):
						_fail("seed %d: edge %d ends at anchor '%s', but "
								% [run_seed, int(row["id"]), id]
								+ "TerrainLandmarks.landmark_sites() has no site for kind %d "
								% kind + "this run — the anchor table invented a monument")
						continue
					truth = landmarks[kind]
					source = "TerrainLandmarks.landmark_sites()"
				else:
					_fail("seed %d: edge %d ends at anchor '%s', whose id matches none of "
							% [run_seed, int(row["id"]), id] + "the four shipped anchor "
							+ "sources — this check cannot tie it to the world and would "
							+ "have skipped it silently")
					continue
				endpoints += 1
				checked[source] = int(checked.get(source, 0)) + 1
				if claimed.distance_to(truth) > POS_TOLERANCE:
					_fail("seed %d: edge %d ends at anchor '%s', which anchors() places at "
							% [run_seed, int(row["id"]), id] + "(%.3f, %.3f) — but %s puts "
							% [claimed.x, claimed.y, source] + "it at (%.3f, %.3f), %.2f m "
							% [truth.x, truth.y, claimed.distance_to(truth)]
							+ "away. The graph is self-consistent and wrong: it joins the "
							+ "right indices to the wrong places in the world")
		terrain.free()

	# --- NON-VACUITY, on every axis this check could go blind along.
	if endpoints == 0:
		_fail("check 5 tied NO edge endpoint to the world across %d seeds — the one "
				% SEEDS.size() + "assertion in this file that a self-consistent wrong "
				+ "graph cannot pass never ran")
	for source: String in ["tower_site()", "BudapestPlan.GATE",
			"TerrainWaypoints.waypoint_sites()", "TerrainLandmarks.landmark_sites()"]:
		if not checked.has(source):
			_fail("check 5 never re-derived a single endpoint from %s across the sweep, "
					% source + "so that source is untested — either no trunk ever ends "
					+ "there (a finding in its own right) or the id matching is broken")

	# --- THE CONTROL. A comparator that always agreed would make every assertion
	# above vacuous, so it is shown here disagreeing with a point one metre off.
	var probe: Node3D = _terrain(terrain_script, SEEDS[0])
	var probe_rows: Array[Dictionary] = BikeNetwork.anchors(probe)
	var real: Vector2 = probe_rows[0]["pos"]
	if real.distance_to(real + Vector2(1.0, 0.0)) <= POS_TOLERANCE:
		_fail("check 5's position comparator accepts a point a whole metre away as the "
				+ "same place, so every tie above was vacuous")
	probe.free()
	print("bike network check 5: %d edge endpoints re-derived from the shipped anchor "
			% endpoints + "sources — %s" % str(checked))
	Sentinel.done("world_tie")


# ============================================================================
# HELPERS
# ============================================================================

func _terrain(terrain_script: GDScript, seed_value: int) -> Node3D:
	"""
	A REAL terrain in the tree on `seed_value`, with the crocodile scene check 1
	needs. `bike_path_selfcheck` / `waypoint_selfcheck`'s recipe, and both halves
	of it matter: IN THE TREE because `create_chunk` parents its chunk to it and
	several spawners ask that chunk for a global transform, and SEEDED AFTER
	`add_child` because `_ready()` rolls its own seed and would throw an earlier
	one away.

	It never streams on its own: `_ready` finds no node in group "player", so
	`player` stays null and `_process` returns immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.crocodile_scene = load(CROC_SCENE)
	root.add_child(terrain)
	terrain.set_run_seed(seed_value)
	return terrain


func _index_of_kind(rows: Array[Dictionary], kind: int) -> int:
	"""The first anchor of a kind there is exactly one of — the HQ or the gate."""
	for i: int in rows.size():
		if int(rows[i]["kind"]) == kind:
			return i
	return -1


func _hop_counts(edges: Array[Dictionary], from_index: int) -> Dictionary:
	"""
	Breadth-first hop count from one anchor over `edges()`, as index -> hops.

	Deliberately NOT a reuse of anything in `bike_network.gd`: this check must walk
	the edge table the way a RIDER would, so that a union-find left in a wrong
	state cannot agree with itself. The graph is tens of edges, so the adjacency is
	built from scratch each time and the cost is nothing.
	"""
	var adjacency: Dictionary = {}
	for row: Dictionary in edges:
		var a: int = int(row["a"])
		var b: int = int(row["b"])
		if not adjacency.has(a):
			adjacency[a] = [] as Array[int]
		if not adjacency.has(b):
			adjacency[b] = [] as Array[int]
		(adjacency[a] as Array[int]).append(b)
		(adjacency[b] as Array[int]).append(a)
	var hops: Dictionary = { from_index: 0 }
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbour: int in (adjacency.get(current, [] as Array[int]) as Array[int]):
			if hops.has(neighbour):
				continue
			hops[neighbour] = int(hops[current]) + 1
			queue.append(neighbour)
	return hops


func _multimesh_table(chunk: Node) -> Dictionary:
	"""
	Every `BlockMultiMesh*` child as name -> [[transform, colour], ...].

	MULTIMESH INSTANCE DATA IS WRITE-ONLY UNDER THE HEADLESS DUMMY RENDERER
	(measured at bead `godot-test1-z2yv.2`), so the rows are placeholders and what
	a table-against-table comparison really asserts is the BUCKET NAMES and each
	bucket's `instance_count`. That is exactly what a stray draw or a moved box
	changes, which is all check 1 claims from it.
	"""
	var out: Dictionary = {}
	for child: Node in chunk.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
		var rows: Array = []
		for i: int in mm.instance_count:
			rows.append([mm.get_instance_transform(i), mm.get_instance_color(i)])
		out[String(child.name)] = rows
	return out


func _node_table(chunk: Node) -> Array[String]:
	"""
	Every chunk-parented NODE — crocodiles, coins, accents — as a sorted list of
	descriptors. This is the half of check 1 that catches a stray draw, since one
	extra draw slides every body in the chunk.

	CLASS AND POSITION, NEVER THE NODE NAME. Godot auto-names an unnamed instance
	with a process-wide counter, so the terrains this check builds side by side
	would disagree about every generated name while agreeing about every position —
	the one difference that means nothing.
	"""
	var out: Array[String] = []
	for child: Node in chunk.get_children():
		if child is MultiMeshInstance3D or String(child.name) == BLOCK_BODY:
			continue
		var at: Vector3 = (child as Node3D).position if child is Node3D else Vector3.ZERO
		out.append("%s|%.4f,%.4f,%.4f" % [child.get_class(), at.x, at.y, at.z])
	out.sort()
	return out


func _shape_count(chunk: Node) -> int:
	"""How many collision shapes hang on the chunk's single shared block body."""
	for child: Node in chunk.get_children():
		if String(child.name) == BLOCK_BODY:
			return child.get_child_count()
	return 0
