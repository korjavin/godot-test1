class_name BikeNetwork
extends RefCounted
## ============================================================================
## THE BIKE ROAD NETWORK — the anchor table and the trunk graph. TOPOLOGY ONLY.
## ============================================================================
## Epic `godot-test1-pnvb`, child `.1`. Owner, 2026-09-19, after playing the
## strips `godot-test1-z2yv` shipped (Russian, paraphrased): *"they are TOO SMALL
## and TOO RANDOM. They should look like a REAL ROAD NETWORK — they should LEAD
## somewhere, be long, maybe even cross via BRIDGES, you should be able to GET TO
## BUDAPEST along them, and there should be INTERSECTIONS."*
##
## THIS FILE DRAWS NOTHING. It answers two questions and no others: WHERE the
## world's fixed points are (`anchors()`) and WHICH PAIRS of them a trunk runs
## between (`edges()`). The route between a pair, the boxes, the bridges and the
## minimap are `.2`, `.3` and `.5`; `terrain_bike_paths.gd` — the spur tier —
## does not know this file exists yet and `.4` is what introduces them.
##
## A `class_name`d library of STATIC functions that RECEIVES the terrain as its
## first argument — the `terrain_bike_paths.gd` / `coin_road.gd` /
## `terrain_waypoints.gd` idiom, and the twelfth family written in it.
## `extends RefCounted` and everything `static`: this is a namespace, not a node.
## `terrain` is typed `Node3D` for `landmark_builders.gd`'s reason —
## `endless_terrain.gd` declares no `class_name`.
##
## ----------------------------------------------------------------------------
## WHY A GRAPH RATHER THAN A LONGER RANDOM WALK
## ----------------------------------------------------------------------------
## Two reasons, and both are architectural rather than aesthetic:
##
## 1. **A random walk cannot LEAD anywhere.** Lengthening one produces a longer
##    wander, not a destination. "Purposeful" is a different generator, one with
##    the destination in the recurrence — which is what `.2` builds on top of the
##    pairs below.
## 2. **A random walk cannot INTERSECT without breaking the RNG contract.** Two
##    walks seeded at their own origin chunks know nothing about each other, so a
##    junction would need either a shared lattice both snap to or cross-origin
##    awareness. A graph whose edges SHARE ENDPOINTS intersects BY CONSTRUCTION,
##    at zero determinism cost: two trunks meet at an anchor because both are
##    DEFINED to end there. There is no "did they meet?" query anywhere.
##
## ----------------------------------------------------------------------------
## NOT ONE DRAW, FROM ANY STREAM, ANYWHERE IN THIS FILE
## ----------------------------------------------------------------------------
## Every anchor source is already pure in `run_seed` and already memoized:
## `tower_site()` is a constant, `TerrainWaypoints.waypoint_sites()` says so in
## its own docstring ("Costs no draw"), `TerrainLandmarks.landmark_sites()` is a
## hash-per-attempt site table, and `BudapestPlan.GATE` is a const a designer
## typed. READING THEM CONSUMES NOTHING.
##
## And the edge set is a **HASH DISPATCH, NEVER A ROLL** — CLAUDE.md, *"dispatch
## (which species, which box kind, which boss) costs no draw"*. `_degree()` folds
## one `hash(Vector3i(...))` into `TRUNK_DEGREES`. The trunk tier is therefore
## strictly CHEAPER than the spur tier it will join: the spurs at least roll their
## rarity, and this rolls nothing at all — which is what makes the density knob
## below free to retune.
##
## ### WHAT ACTUALLY PROTECTS THE STREAMS HERE, STATED HONESTLY
## The usual framing — *"an `rng.randi()` in this file would slide every crocodile
## in the world"* — is **not true of this file**, and writing it down as if it were
## would point the next author's attention at the wrong risk (round 1 of the
## review measured this; the earlier draft of this banner said it).
##
## Every RNG in the world engine is FUNCTION-LOCAL and re-derived per chunk:
## `spawn_objects_in_chunk` builds `RandomNumberGenerator.new()` seeded on
## `hash(Vector3i(chunk.x * 73856093, chunk.y * 19349663, run_seed))` and it dies
## with the call; `terrain_biomes.gd` and `terrain_predators.gd` each do the same
## on their own salt. The terrain node holds NO member RNG at all. So no function
## here is handed a stream, and there is no stream a stray draw in this file could
## advance. **The zero-draw property is structural, not measured** — and it is
## worth saying which, because "we checked" and "it cannot happen" are different
## guarantees and only one of them survives a refactor.
##
## THE RISK THAT IS REAL, AND THE ONE `bike_network_selfcheck` CHECK 1 MEASURES,
## is the other half: `anchors()` calls the road station cache and the landmark
## site table EARLIER, and in a different order, than a streaming world would, and
## it holds live references to memos whose docstrings say "read-only to callers".
## Warming a pure memo early must be a no-op, and writing to one is a world
## changed under every spawner downstream. Check 1 is a field of chunks built
## through the shipped `create_chunk` twice — once normally, once with `anchors()`
## and `edges()` asked for first — node for node, bucket for bucket and collision
## shape for collision shape. Its mutation control is exactly that: one line
## writing into the shared landmark memo turns all three halves red.
##
## ----------------------------------------------------------------------------
## THE SEED: THIS FAMILY'S OWN SALT AND ITS OWN PRIME
## ----------------------------------------------------------------------------
## The prime is NEW, and that was checked against the whole tree the way
## `terrain_bike_paths.gd`'s banner demands rather than against the handful a
## reader remembers: `grep -rhoE '[0-9]{5,10}' scripts/ | sort -u` is 195 numbers
## and 43112609 is in none of them. Sharing a pair would correlate two features —
## an anchor index that draws a high degree would thereby be likelier to host
## something else — which is the one thing an independent stream exists to
## prevent. The next author owes the same grep.
##
## ONE prime and not two, deliberately: the dispatch's only coordinate is the
## ANCHOR INDEX. A second prime multiplying a constant zero would be decoration.
##
## ----------------------------------------------------------------------------
## CORRIDOR ONLY — OWNER RULING, 2026-09-19, AND IT OVERRULED THE ARCHITECT
## ----------------------------------------------------------------------------
## *"Trunks run between the HQ, the waypoints, the Budapest gate and CORRIDOR
## landmarks. Anchors in the 0.5-2.5 km annulus are refused as trunk endpoints.
## The far field is deliberately empty and it stays that way — no bare paint out
## there. If a landmark is reachable only by leaving the corridor, it simply gets
## no trunk."*
##
## `anchors()` still returns EVERY anchor — the table is useful to `.5`'s minimap
## and to `godot-test1-z2yv.3`'s racks whatever their eligibility, and throwing
## rows away here would be a second opinion the rest of the epic has to
## re-derive. The ruling lands as one `trunkable` field, and `edges()` builds over
## that subset only.
##
## THE TEST IS ONE SHIPPED PURE FUNCTION AND NOT A NEW CONSTANT:
##
##     trunkable = terrain.scarcity_at(Vector3(pos.x, 0.0, pos.y)) >= TRUNK_ANCHOR_MIN_K
##
## `scarcity_at()` returns exactly 1.0 inside the union of
## `SCARCITY_CORRIDOR_RECT` and `BudapestPlan.rect()` and falls off
## logarithmically outside it, so "inside the corridor" and "k = 1" ARE THE SAME
## STATEMENT. A second `Rect2` typed here would drift from the shipped one the
## moment anybody retuned it. It also separates the two landmark families for free
## without this file knowing which is which: the mile sits 60-120 m off the
## centreline (`LANDMARK_MILE_LATERAL_*`), the annulus 0.5-2.5 km
## (`LANDMARK_FIELD_LATERAL_*`).
##
## ### THE EDGE CASE — PREDICTED FOR LANDMARKS, THEN MEASURED WIDER THAN THAT
## `SCARCITY_CORRIDOR_RECT`'s Z half-width is 1000 m, and its own comment records
## the measurement behind it: *"measured max |z| 775 m across 1000 run_seeds
## (seeds 1..1000) plus the mile-landmark lateral offset 120 m plus half band
## 10 m = 905 m, rounded to 1000 m for margin."* A MILE landmark stands up to
## 120 m off that centreline, and that 120 m is already inside the 905 m the
## rect was measured against — so a refused mile landmark is genuinely far out,
## not a near miss. That much is not a defect — a refused landmark getting no
## trunk is exactly the owner's stated intent, and the far field staying empty
## is worth more than the last monument on the list.
##
## **UNDER THE OLD 200 m RECT THE FILTER REACHED THE ROAD WAYPOINTS TOO, WHICH
## THE BEAD DID NOT EXPECT — AND THAT IS HISTORY.** The bead states *"the HQ, all
## eleven waypoints and the GATE are inside the union by construction, so the
## filter only ever bites on landmarks."* Under the pre-#457 rect that was FALSE,
## and the number was in check 4's printout: across the 16-seed sweep, 26
## WAYPOINT anchors were refused on 14 of the 16 seeds — `approach` (which stands
## at x = -200, WEST of station 0 and therefore outside the span the old comment
## was measured over) and `road_1` / `road_2` / `road_3` on the centreline itself,
## the worst at `road_3` on seed 987654321, z = -488 m with k = 0.799. A road
## station at |z| 488 m was nearly four times the 129 m the old comment claimed
## as the measured maximum: the corridor rect was narrower than the road it was
## drawn around.
##
## PR #457 (bead godot-test1-q184) RE-MEASURED AND WIDENED instead of reasoning
## around it: half-width 200 → 1000 m against the 775 m envelope, the rect
## derived from the const so the two cannot drift, and `scarcity_selfcheck`
## check 4 guarding "every road station reads k = 1" — containment is now
## guarded rather than merely hoped. The `>= 1.0` test SHIPS AS WRITTEN, and the
## widening (never this family's edit to make: it moves scarcity for every
## spawner in the world) is why. `bike_network_selfcheck` check 4 still PRINTS
## the refusals SPLIT BY KIND: every refused WAYPOINT one line each with its own
## k and position — the tripwire that would catch the corridor under-covering
## the road a second time; the refused LANDMARKS per seed, banded by how far
## below 1.0 they fell, because there are hundreds of them and Ruling 3 asked for
## that distribution rather than a roll call. The network survives refusals either
## way: check 3 asserts the gate is still reachable from the HQ on every seed of
## the sweep, and it is, in 3 to 15 hops.
##
## If the sweep ever shows anchors being lost at a rate anyone cares about, the
## sanctioned stopgap is to lower the ONE named `TRUNK_ANCHOR_MIN_K` below —
## **never a second corridor rectangle.**
##
## ----------------------------------------------------------------------------
## THE MEMO LIVES ON THE TERRAIN
## ----------------------------------------------------------------------------
## `terrain._bike_network_cache`, dropped by `_drop_seeded_memos()` beside
## `_bike_path_cache` and `_landmark_sites_cache`. NOT a `static var` here: memo
## state `_drop_seeded_memos()` cannot reach survives every re-seed and hands a
## multiplayer joiner the wrong world — `chunk_stream_selfcheck` check 6c fails
## the build for one, and this family is in that check's audited set.
##
## IT IS NOT CAPPED, and that is a statement rather than an omission: unlike
## `_bike_path_cache` (one entry per origin chunk, unbounded in a long run) this
## is exactly TWO keys for the whole world. There is nothing for a cap to evict.

# ============================================================================
# THE SEED (see the banner)
# ============================================================================

## The degree dispatch's coordinate prime. Used nowhere else in this world engine
## — see the banner for the grep that says so.
const BIKE_NET_PRIME_I: int = 43112609

## "BIKE NET"-ish; an arbitrary fixed constant, XORed into `run_seed` so this
## family's dispatch is its own even where a prime would agree with another's.
const BIKE_NET_SALT: int = 0xB1_1E_4E7

# ============================================================================
# THE ANCHOR TABLE
# ============================================================================

## Anchor kinds. `.2` reads these to decide what a trunk does at each end — it
## stops at the rect edge for a CITY_WAYPOINT, because Budapest's streets are
## authored and `in_budapest()` exists to refuse a procedural strip across Váci
## utca; the GATE at x = 1600 is the city's real front door and is the one a trunk
## ends AT.
const KIND_HQ: int = 0
const KIND_WAYPOINT: int = 1
const KIND_CITY_WAYPOINT: int = 2
const KIND_GATE: int = 3
const KIND_LANDMARK: int = 4

## The corridor filter, and the ONLY knob it has. 1.0 means "exactly inside the
## union of SCARCITY_CORRIDOR_RECT and the Budapest rect", because that is where
## `scarcity_at()` returns exactly 1.0. See the banner's EDGE CASE section for the
## 905 m-against-1000 m measurement that is the one reason this would ever move,
## and for why the answer is this number and never a second rectangle.
const TRUNK_ANCHOR_MIN_K: float = 1.0

# ============================================================================
# THE TRUNK GRAPH
# ============================================================================

## THE DENSITY KNOB — owner ruling 2026-09-19, "MEDIUM: it should read as a
## NETWORK, not as a couple of highways". One entry per hash fold, the `POLE_TOPS`
## idiom: four anchors in six get two trunks and two get one, for a mean degree of
## 1.67.
##
## RETUNING THIS COSTS NO DRAW AND MOVES NOTHING — not one station, not one
## crocodile, not one coin — precisely because `_degree()` is a hash and not a
## roll. That is what makes the knob cheap enough to leave in the open.
##
## MEASURED, over `bike_network_selfcheck`'s 16-seed sweep on the shipped
## constants: 61 anchors (the HQ, 11 waypoints, the gate and 48 landmark kinds) on
## every seed of that sweep — the fixed head of 13 is constant by construction, but
## the landmark tail is NOT guaranteed, because a kind whose `LANDMARK_SITE_TRIES`
## attempts are all rejected simply has no site that run (`terrain_landmarks.gd`'s
## "honest degrade"). Check 4 prints the range rather than one number for exactly
## that reason. Of the 61, 36-46 are trunkable, producing **43-57 edges, 51.5 at
## the median**, and a hop count from the HQ to the gate of 3-16. Check 4 prints
## the histogram (pass 2b's drawn-chain parallels included), and that printed
## number is what the owner retunes against.
##
## THE SPREAD IS THE CORRIDOR FILTER'S, NOT THE DISPATCH'S: the trunkable count
## moves by a factor of two between seeds because how much of the museum mile
## falls inside k = 1 depends on how far that seed's road wanders. See the banner's
## EDGE CASE section and check 4's printout.
const TRUNK_DEGREES: Array[int] = [1, 2, 2, 1, 2, 2]

## The longest trunk the nearest-neighbour pass will draw. Measured against the
## world it has to span: road waypoints are `WAYPOINT_SPACING` 450 m apart and
## mile landmarks `LANDMARK_MILE_SPACING` 75 m, so at 700 m every anchor in the
## corridor has neighbours and nothing is joined across half the map. An anchor
## with NO neighbour inside it gets no edge from this pass — the honest degrade,
## and the repair below is what stops that becoming a hole in the network.
const TRUNK_MAX_EDGE: float = 700.0

## ...and the repair's own cap, deliberately looser: the repair joins whole
## COMPONENTS, and the gap between two clusters is by definition bigger than the
## gap inside one. A component that still cannot reach the gate inside this is
## DROPPED WHOLE rather than joined by a 6 km trunk across the empty field — the
## far field stays empty, which is the same ruling the corridor filter serves.
const TRUNK_REPAIR_MAX_EDGE: float = 1600.0


static func anchors(terrain: Node3D) -> Array[Dictionary]:
	"""
	THE WORLD'S FIXED POINTS THIS RUN, AT STABLE INDICES.

	@param terrain: The `EndlessTerrain`, for `tower_site()`, the road cache and
	                `scarcity_at()`.
	@return: Rows of `{ id: String, pos: Vector2 (world XZ), kind: int,
	         trunkable: bool }`. The memo itself, not a copy — it is asked once per
	         run per consumer and nobody may write to it.

	THE ORDER IS FIXED-COUNT FIRST: index 0 is the HQ, 1..N the waypoints in
	`waypoint_sites()`'s own order, N+1 the gate, and the landmarks after that in
	KIND order. Everything but the landmarks therefore sits at the same index in
	every world, and the landmark tail moves only because a kind that found no site
	this run is simply absent. Identity is carried by `id` for any consumer that
	needs it across seeds.

	COSTS NO DRAW. All four sources are already pure in `run_seed` and already
	memoized; see the banner.
	"""
	var cache: Dictionary = terrain._bike_network_cache
	if cache.has("anchors"):
		return cache["anchors"]

	var rows: Array[Dictionary] = []

	# --- 0: the HQ. A constant site (owner ruling 2026-08-29) — the one anchor
	# that is not even seeded.
	var tower: Vector3 = terrain.tower_site()
	rows.append(_anchor("hq", Vector2(tower.x, tower.z), KIND_HQ))

	# --- 1..N: the teleport circles, in the order that file fixes as a wire
	# format. THROUGH THE TERRAIN'S FORWARDER and never `TerrainWaypoints` by name
	# — CLAUDE.md, Conventions: a static family reaches a sibling family "through
	# the node that owns the state, never directly", because "a `const` alias or a
	# type annotation is a parse-time reference — one direction only, or it is a
	# cycle". `terrain_bike_paths.gd` already complies both ways, and `.4` is the
	# child that will make one of those files name THIS one.
	# Its `_road_extend_to_x` leaves the station cache warm, which is why
	# there is no second extend anywhere in this file: the road cache grows
	# contiguously from station 0 and an extra extend is wasted work in a family
	# that owns nothing about the road.
	for site: Dictionary in terrain.waypoint_sites():
		var pos: Vector3 = site["pos"]
		var flat := Vector2(pos.x, pos.z)
		# The five city circles stand INSIDE the authored rect. They stay in the
		# table (they are legitimate destinations) and are marked so `.2` can stop a
		# trunk at the rect edge rather than paint one across an authored street.
		var kind: int = KIND_CITY_WAYPOINT if terrain.in_budapest(flat.x, flat.y) else KIND_WAYPOINT
		# `wp_` PREFIXED, AND THAT IS NOT DECORATION. `waypoint_sites()` already
		# contains a circle called "hq" (the one round the corner from the tower's
		# door) and one called "gate" (BudapestPlan's, at x = 1724, two blocks INSIDE
		# the rect) — both of which are different places from this table's own "hq"
		# (the building's centre) and "gate" (the city's front door at x = 1600, 124 m
		# west of the circle). Unprefixed, an anchor id would name two positions and
		# every consumer that looks a row up by id would silently get the wrong one.
		# Check 5 found this on its first run, which is exactly what a world tie is
		# for; check 4 asserts the ids are unique so it cannot come back.
		rows.append(_anchor("wp_%s" % String(site["id"]), flat, kind))

	# --- N+1: the city's front door, an authored constant.
	rows.append(_anchor("gate", Vector2(BudapestPlan.GATE.x, BudapestPlan.GATE.z), KIND_GATE))

	# --- N+2..: the museum mile and the annulus, one site per kind that found one.
	#
	# THE CHUNK CENTRE IS THE ANCHOR, and that is the honest reading rather than a
	# rounding: `landmark_sites()` is chunk -> kind, and the exact metre inside the
	# chunk is chosen later by `spawn_landmark_in_chunk`'s candidate loop against
	# the finished `obstacles`. The centre is the only position of a landmark that
	# is computable for a chunk that has never streamed in, which is exactly what a
	# global table needs. A trunk arriving within half a chunk of a monument has
	# arrived at it.
	#
	# SORTED BY KIND rather than trusting the Dictionary's insertion order, so the
	# index a landmark takes is a property of the world and not of a container.
	var sites: Dictionary = terrain.landmark_sites()
	var by_kind: Array[Array] = []
	for chunk: Vector2i in sites:
		by_kind.append([int(sites[chunk]), chunk])
	by_kind.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for row: Array in by_kind:
		var centre: Vector3 = terrain.chunk_to_world(row[1] as Vector2i)
		rows.append(_anchor("landmark_%d" % int(row[0]), Vector2(centre.x, centre.z), KIND_LANDMARK))

	# THE CORRIDOR FILTER, in one place for every kind at once — see the banner.
	# It bites on landmarks as designed; the road waypoints now read k = 1 under
	# the widened rect, and `scarcity_selfcheck` check 4 guards that they keep doing
	# so. One pass over every kind and no exception list, because an exception list
	# is what hid the pre-#457 under-coverage.
	for row: Dictionary in rows:
		var pos: Vector2 = row["pos"]
		row["trunkable"] = terrain.scarcity_at(Vector3(pos.x, 0.0, pos.y)) >= TRUNK_ANCHOR_MIN_K

	cache["anchors"] = rows
	return rows


static func edges(terrain: Node3D) -> Array[Dictionary]:
	"""
	THE TRUNK GRAPH: which pairs of anchors a trunk runs between.

	@param terrain: The `EndlessTerrain`.
	@return: Rows of `{ id: int, a: int, b: int }` where `a < b` index
	         `anchors()`. `id` is the row's own position in this array. The memo
	         itself, not a copy.

	COSTS NO DRAW — it is a dispatch and arithmetic over a table that was already
	pure in `run_seed`, and the candidate walks it tests are `_bike_turn` hashes on
	the pair key: more calls of the same streamless hash, never a roll. See the banner.

	THREE PASSES, all deterministic:

	1. NEAREST NEIGHBOURS. Every TRUNKABLE anchor takes its `_degree()` closest
	   trunkable neighbours inside `TRUNK_MAX_EDGE`, exactly as before. `(i, j)` and
	   `(j, i)` are the same trunk AND the same walk now — the turn key packs the
	   unordered pair — so the pairs go into a set keyed on `(min, max)`. That is
	   also why the realised degree is not the dispatched one: an anchor that four
	   neighbours all chose ends up with four trunks and rolled nothing.
	2. CONNECT THE GATE. A union-find over pass 1, and for every component that
	   does not hold the gate, the single shortest edge joining it to one that does
	   — repeated until no component moves. Unchanged by bead .7: this joins the
	   GRAPH, and a dangling link joins it as well as a snapped one. That is what
	   makes *"you should be able to get to Budapest along them"* a property of the
	   construction rather than a hope, at the graph tier. It may join components;
	   it may NOT smuggle a non-trunkable anchor back in, and check 3's acceptance
	   says so.
	2b. DRAWN-REACHABILITY (bead .7). Pass 2 joins the graph; the drawn chain needs
	    the DRAWN links to connect, and a dangling pass-1 link (a rect-edge ending)
	    joins the graph but never the chain. So starting from the HQ over links that
	    draw AND snap both anchors exactly, extend the reached set toward the gate,
	    best-first, until it arrives or no strict pair extends it. Each added pair is
	    a graph edge too (and joins the union-find), so pass 3 keeps it.
	3. DROP THE UNREACHABLE. A component that pass 2 could not join inside
	   `TRUNK_REPAIR_MAX_EDGE` loses its edges entirely. An island of trunk with no
	   way to the city is exactly the thing the owner played and disliked.
	"""
	var cache: Dictionary = terrain._bike_network_cache
	if cache.has("edges"):
		return cache["edges"]

	var rows: Array[Dictionary] = anchors(terrain)
	var eligible: PackedInt32Array = PackedInt32Array()
	var gate: int = -1
	for i: int in rows.size():
		if not bool(rows[i]["trunkable"]):
			continue
		eligible.append(i)
		if int(rows[i]["kind"]) == KIND_GATE:
			gate = i

	# --- PASS 1: nearest neighbours, deduplicated into unordered pairs.
	var pairs: Dictionary = {}
	# Walk verdicts, keyed on the unordered pair so (i, j) is never walked twice.
	var tested: Dictionary = {}
	for i: int in eligible:
		var here: Vector2 = rows[i]["pos"]
		var cands: Array[Array] = []
		for j: int in eligible:
			if j == i:
				continue
			var there: Vector2 = rows[j]["pos"]
			cands.append([here.distance_to(there), j])
		# A TOTAL ORDER, tie-broken on the index: `sort_custom` is not stable, and
		# two anchors exactly equidistant from a third are not impossible in a world
		# whose road is symmetric about z = 0.
		cands.sort_custom(_nearer)
		var want: int = _degree(terrain, i)
		var taken: int = 0
		for c: Array in cands:
			if taken >= want:
				break
			if float(c[0]) > TRUNK_MAX_EDGE:
				# Sorted, so nothing further along is nearer. An anchor with no
				# neighbour inside the cap simply gets none here — the honest degrade.
				break
			pairs[Vector2i(mini(i, int(c[1])), maxi(i, int(c[1])))] = true
			taken += 1

	# --- PASS 2: connect every component to the gate's.
	var parent: Dictionary = {}
	for i: int in eligible:
		parent[i] = i
	for key: Vector2i in pairs:
		_union(parent, key.x, key.y)
	if gate >= 0:
		# To a fixpoint: a component processed early may have no candidate INTO the
		# gate's component yet and acquire one once a nearer component has joined.
		# Bounded by the component count, so at most `eligible.size()` sweeps.
		for _sweep: int in eligible.size():
			var joined: bool = false
			var gate_root: int = _find(parent, gate)
			# Grouped by root and walked in root order, so which component is repaired
			# first is a property of the anchor indices and not of a Dictionary.
			var roots: Array[int] = []
			for i: int in eligible:
				var r: int = _find(parent, i)
				if r != gate_root and not roots.has(r):
					roots.append(r)
			roots.sort()
			for root: int in roots:
				if _find(parent, root) == _find(parent, gate):
					continue  # already joined by an earlier repair this sweep
				var best: float = INF
				var best_pair := Vector2i(-1, -1)
				for i: int in eligible:
					if _find(parent, i) != root:
						continue
					for j: int in eligible:
						if _find(parent, j) != _find(parent, gate):
							continue
						var from: Vector2 = rows[i]["pos"]
						var to: Vector2 = rows[j]["pos"]
						var d: float = from.distance_to(to)
						# `<` and not `<=`, with the pair built as (min, max): the first
						# candidate at a tied distance wins and the loops run in index
						# order, so the winner is the lowest pair either way.
						if d < best:
							best = d
							best_pair = Vector2i(mini(i, j), maxi(i, j))
				if best <= TRUNK_REPAIR_MAX_EDGE and best_pair.x >= 0:
					pairs[best_pair] = true
					_union(parent, best_pair.x, best_pair.y)
					joined = true
			if not joined:
				break

	# --- PASS 2b: DRAWN-REACHABILITY (bead godot-test1-pnvb.7). Pass 2 joins the
	# GRAPH; the drawn chain needs the DRAWN links to connect, and a dangling
	# pass-1 link (a rect-edge ending) joins the graph but never the chain. So
	# starting from the HQ over links that draw AND snap both anchors exactly,
	# extend the reached set toward the gate, best-first, until it arrives or no
	# strict pair extends it. Each added pair is a graph edge too (and joins
	# `parent`), so pass 3 keeps it; a sweep that adds nothing ends the pass.
	var hq: int = -1
	for i: int in eligible:
		if int(rows[i]["kind"]) == KIND_HQ:
			hq = i
	if hq >= 0 and gate >= 0:
		for _sweep: int in eligible.size():
			var reached := _drawn_reach(terrain, rows, pairs, tested, hq)
			if reached.has(gate):
				break
			# Frontier: every (reached, unreached) pair inside the cap, walked
			# best-first until one draws AND snaps both anchors exactly.
			var frontier: Array[Array] = []
			for u: int in reached.keys():
				for v: int in eligible:
					if reached.has(v):
						continue
					var d: float = (rows[u]["pos"] as Vector2).distance_to(rows[v]["pos"])
					if d <= TRUNK_REPAIR_MAX_EDGE:
						frontier.append([d, mini(u, v), maxi(u, v)])
			frontier.sort_custom(_nearer_edge)
			var extended: bool = false
			for c: Array in frontier:
				if _strict_link(terrain, rows, tested, int(c[1]), int(c[2])):
					pairs[Vector2i(int(c[1]), int(c[2]))] = true
					_union(parent, int(c[1]), int(c[2]))
					extended = true
					break
			if not extended:
				break
	# --- PASS 3: drop whatever still cannot reach the city, then emit in a fixed
	# order so the row ids are a property of the world.
	var keys: Array[Vector2i] = []
	for key: Vector2i in pairs:
		if gate >= 0 and _find(parent, key.x) != _find(parent, gate):
			continue
		keys.append(key)
	keys.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return p.x < q.x if p.x != q.x else p.y < q.y)
	var out: Array[Dictionary] = []
	for key: Vector2i in keys:
		out.append({ "id": out.size(), "a": key.x, "b": key.y })

	cache["edges"] = out
	return out


static func _test_pair(terrain: Node3D, rows: Array[Dictionary], tested: Dictionary,
		i: int, j: int) -> Dictionary:
	"""
	Walk the trunk candidate between anchors i and j, ONCE per edge set (bead
	godot-test1-pnvb.7).

	The verdict cache is keyed on the unordered pair, but the walk always runs
	from the LOWER index: the emitted edge stores a=min, b=max, so the tested
	walk is bit-for-bit the walk the spawner will draw for it.

	@return: `{ "reason": String ("" when the pair draws), "first": Vector2,
	           "last": Vector2 }` — the route's own endpoints for the strict test.
	           COSTS NO DRAW: the walk is hashes on the pair key, never a roll.
	"""
	var key := Vector2i(mini(i, j), maxi(i, j))
	if tested.has(key):
		return tested[key]
	var reason: Array[String] = [""]
	var route: Array[Dictionary] = terrain.bike_trunk_walk(rows, key.x, key.y, reason)
	var verdict := {"reason": reason[0], "first": Vector2.ZERO, "last": Vector2.ZERO}
	if reason[0] == "" and not route.is_empty():
		verdict["first"] = route[0]["pos"]
		verdict["last"] = route[-1]["pos"]
	tested[key] = verdict
	return verdict


static func _drawn_reach(terrain: Node3D, rows: Array[Dictionary], pairs: Dictionary,
		tested: Dictionary, start: int) -> Dictionary:
	"""
	The anchors drawn-connected to `start` through links that draw AND snap both
	anchors exactly (bead godot-test1-pnvb.7) — the set pass 2b extends toward the
	gate. Pairs are walked on demand through `_strict_link` and cached in `tested`,
	so a sweep costs walks only along the reached frontier.
	"""
	var reached := {start: true}
	var adj := {}
	for key: Vector2i in pairs:
		if not adj.has(key.x):
			adj[key.x] = []
		if not adj.has(key.y):
			adj[key.y] = []
		(adj[key.x] as Array).append(key.y)
		(adj[key.y] as Array).append(key.x)
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb: int in adj.get(cur, []):
			if reached.has(nb):
				continue
			if _strict_link(terrain, rows, tested, cur, nb):
				reached[nb] = true
				queue.append(nb)
	return reached


static func _strict_link(terrain: Node3D, rows: Array[Dictionary], tested: Dictionary,
		a: int, b: int) -> bool:
	"""
	Would the trunk between anchors a and b draw AND snap both anchors exactly —
	the admission test for a DRAWN chain link (bead godot-test1-pnvb.7)? A rect-edge
	ending is drawn but dangling, so it joins the graph and never the chain.
	Walked from the lower index through `_test_pair`: the emitted edge stores
	a=min, b=max, so the tested walk is bit-for-bit the drawn one.
	"""
	var v: Dictionary = _test_pair(terrain, rows, tested, a, b)
	if String(v["reason"]) != "":
		return false
	var fa: Vector2 = rows[a]["pos"]
	var fb: Vector2 = rows[b]["pos"]
	return (v["first"] == fa and v["last"] == fb) \
			or (v["first"] == fb and v["last"] == fa)


static func _nearer_edge(a: Array, b: Array) -> bool:
	"""`[distance, i, j]` ordered by distance, ties broken on (i, j) — the `_nearer`
	idiom with the loop roles kept, so the winner at a tied distance is the pair the
	old index-ordered loops met first. Exact `==`, for `_nearer`'s transitivity reason."""
	return float(a[0]) < float(b[0]) \
			or (float(a[0]) == float(b[0]) and (int(a[1]) < int(b[1]) \
				or (int(a[1]) == int(b[1]) and int(a[2]) < int(b[2]))))


static func _anchor(id: String, pos: Vector2, kind: int) -> Dictionary:
	"""One anchor row, `trunkable` filled in by `anchors()`'s single filter pass."""
	return { "id": id, "pos": pos, "kind": kind, "trunkable": false }


static func _degree(terrain: Node3D, index: int) -> int:
	"""
	How many nearest neighbours anchor `index` reaches for: ONE FOLD OF ONE HASH.

	@param index: The anchor's index in `anchors()`.
	@return: An entry of `TRUNK_DEGREES`.

	A DISPATCH AND NOT A ROLL — CLAUDE.md, "dispatch costs no draw". NOT because a
	draw here would disturb a caller's stream: this function is handed no RNG and
	the terrain holds none, so there is no stream to disturb (see the banner's
	honest version of that claim). The reason is the one that survives: a roll
	makes the density knob above IMPOSSIBLE TO TURN, because retuning
	`TRUNK_DEGREES` would then change how many draws the graph consumes and move
	whatever shared the stream. As a hash it is free to retune forever, and that is
	what owner Ruling 2 asked for.

	`absi()` AND NOT A MASK: there is no second field to shift past, so the modulo
	is taken on the absolute value.

	AND NOTHING ASSERTS IT, WHICH IS DELIBERATE AND WORTH KNOWING. Dropping `absi()`
	would not raise — GDScript indexes an Array from the tail on a negative index,
	so `TRUNK_DEGREES[-5..-1]` are all entries of the table — and it would still
	produce a mix of degrees that still moved with `run_seed`, so neither of check
	4's dispatch assertions would see it either. That is acceptable: the effect is
	to reshuffle which index lands on which degree, i.e. a DIFFERENT world, not a
	broken one. It is spelled out because "check 4 covers it" is the natural thing
	to assume and it is not true. (Round 2 of the review; this paragraph previously
	said the opposite.)
	"""
	var h: int = hash(Vector3i(index * BIKE_NET_PRIME_I, 0, terrain.run_seed ^ BIKE_NET_SALT))
	return TRUNK_DEGREES[absi(h) % TRUNK_DEGREES.size()]


static func _nearer(a: Array, b: Array) -> bool:
	"""
	`[distance, index]` ordered by distance, ties broken on the index.

	EXACT `==` AND NOT `is_equal_approx`, which is `coin_road_selfcheck`'s own
	idiom one family along (`a[0] < c[0] or (a[0] == c[0] and a[1] < c[1])`).
	Approximate equality is NOT TRANSITIVE, so a comparator built on it is not the
	strict weak ordering `sort_custom` requires and three anchors inside one
	tolerance band can order cyclically. Exact is also the only version that is
	the TOTAL ORDER the caller's comment claims: both distances come out of the
	same arithmetic on the same doubles every run, so equality here means the same
	thing in every world, and the index tie-break settles it.
	"""
	return float(a[0]) < float(b[0]) \
			or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1]))


static func _find(parent: Dictionary, i: int) -> int:
	"""Union-find root of `i`, with path compression."""
	var root: int = i
	while int(parent[root]) != root:
		root = int(parent[root])
	while int(parent[i]) != i:
		var next: int = int(parent[i])
		parent[i] = root
		i = next
	return root


static func _union(parent: Dictionary, a: int, b: int) -> void:
	"""Merge two components, the LOWER index always becoming the root so that the
	repair pass walks them in an order the anchor table fixes."""
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra == rb:
		return
	parent[maxi(ra, rb)] = mini(ra, rb)
