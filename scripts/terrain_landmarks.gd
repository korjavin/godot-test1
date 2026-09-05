class_name TerrainLandmarks
extends RefCounted
## ============================================================================
## THE GEO LANDMARKS — one site per kind, strung along the museum mile
## ============================================================================
## Lifted out of `endless_terrain.gd` whole by bd `godot-test1-ftn.26`, in the
## idiom the seven extractions before it settled (`terrain_props`,
## `terrain_structures`, `terrain_features`, `terrain_biomes`,
## `terrain_predators`, `coin_road`, `budapest_streamer`): a `class_name`d
## library of STATIC functions that RECEIVES the terrain as its first argument
## and calls `terrain.create_box` / `terrain._road_station` /
## `terrain._settle_coin_y` back through the reference.
##
## ----------------------------------------------------------------------------
## IT WAS LEFT BEHIND TWICE, BOTH TIMES FOR A REASON THAT NO LONGER HOLDS
## ----------------------------------------------------------------------------
## `ftn.4` (the private-stream features) left it because "its site table is
## `run_seed`-memoized INSTANCE state that `_drop_seeded_memos()` owns"; `ftn.7`
## (the coin road) left it again because the road is the museum mile's
## COORDINATE SYSTEM and not its family. The first reason was dissolved by ftn.7
## itself, which moved the road's functions and left its station cache on the
## terrain under the one seed write that clears it; the second was never a reason
## to keep it in the WORLD ENGINE, only a reason not to put it in `coin_road.gd`.
## So it lands here, as its own family, and the memo does exactly what the
## station cache did.
##
## **`_landmark_sites_cache` / `_landmark_sites_built` STAY on the terrain.**
## `_drop_seeded_memos()` is deliberately ONE function under the seed write (bd
## `godot-test1-bvq`, PR #276) clearing every cache derived from the road
## centreline, and these two are among them — a table kept across a re-seed would
## string this run's landmarks along the LAST run's road. Moving them here would
## split that reset, which is the exact bug `bvq` closed.
##
## ----------------------------------------------------------------------------
## THE CONSTANT BANNER DID NOT COME WITH IT
## ----------------------------------------------------------------------------
## The twenty `LANDMARK_*` constants stay in `endless_terrain.gd`, read as
## `terrain.LANDMARK_RADIUS` — `terrain_biomes.gd`'s precedent (bd ftn.5), whose
## ~160 tuning constants stayed for the same reason: the bead asks for the
## FUNCTIONS, the banner has readers that can already see it, and cutting a
## banner out is its own mechanical pass with its own A/B. Nothing about the
## values changes, and every self-check reading them off the terrain's
## `get_script_constant_map()` is untouched.
##
## ----------------------------------------------------------------------------
## THE RULES ARE UNCHANGED, AND THEY ARE WHAT THIS FILE IS MEASURED ON
## ----------------------------------------------------------------------------
## A GEO LANDMARK KIND EXISTS EXACTLY ONCE IN A WORLD (owner ruling 2026-09-04,
## bead `godot-test1-bcf`), the placement is INVERTED — a site per row rather
## than a rarity roll per chunk — and `_landmark_at` is a REVERSE LOOKUP that
## costs the chunk stream **not one draw and not one hash**. Illegal sites (the
## HQ disc, the Budapest rect, the spawn bubble, a river, a chunk already taken)
## are resolved by deterministic RE-HASH, never by a draw.
## `landmark_sites_selfcheck` reads `_landmark_at` AS TEXT for exactly that, and
## since this move it reads THIS file — see its `SOURCE_SCRIPTS`.

# ============================================================================
# GEO LANDMARKS (see the GEO LANDMARKS constant banner)
# ============================================================================

static func landmark_sites(terrain: Node3D) -> Dictionary:
	"""
	THE WHOLE FIELD LANDMARK PLACEMENT FOR THIS RUN: chunk Vector2i -> kind index.

	@return: The memoized site table. At most one entry per LANDMARKS kind, at most
	         one kind per chunk. Read-only to callers — it is the cache itself, not
	         a copy, because it is asked once per chunk generated.

	Pure in `run_seed` (and in the road centreline, which is itself pure in
	run_seed), so every peer in a room and every regeneration of the same run agree
	for free — the same argument the old per-chunk roll made, one level up. Built
	lazily on the first ask and dropped by `set_run_seed()` (through
	`_drop_seeded_memos()`) beside the station cache it is derived from; see the
	MUSEUM MILE banner for the design.
	"""
	if terrain._landmark_sites_built:
		return terrain._landmark_sites_cache
	terrain._landmark_sites_cache = _build_landmark_sites(terrain)
	terrain._landmark_sites_built = true
	return terrain._landmark_sites_cache


static func landmark_site(terrain: Node3D, kind: int) -> Vector2i:
	"""
	Where kind `kind` stands this run, as CHUNK coordinates.

	@param kind: Index into LandmarkBuilders.LANDMARKS.
	@return: The kind's chunk, or LANDMARK_SITE_NONE when every attempt was
	         rejected and this run simply has no such place. Callers must test.

	The forward direction of `landmark_sites()`, and the one a future minimap mark
	for an UNVISITED landmark would read: it answers for a chunk that has never
	streamed in. Linear in the table (48 entries), which is fine for a UI ask and
	is why the SPAWNER uses the reverse lookup instead.
	"""
	var sites: Dictionary = landmark_sites(terrain)
	for chunk: Vector2i in sites:
		if int(sites[chunk]) == kind:
			return chunk
	return terrain.LANDMARK_SITE_NONE


static func _build_landmark_sites(terrain: Node3D) -> Dictionary:
	"""
	Choose one site per LANDMARKS kind. Called once per run by landmark_sites().

	@return: chunk Vector2i -> kind index.

	THE MILE AND THE ANNULUS. The corridor is the road centreline from STATION 0
	(the spawn, where the road is defined to begin) to the terminal station T,
	which is every metre of road a run's consumers acknowledge. It is divided into
	slots LANDMARK_MILE_SPACING
	apart; kinds 0..slots-1 take one slot each, and every remaining kind takes a
	station drawn uniformly from the same span with a 0.5-2.5 km lateral offset
	instead of a 60-120 m one. There is no third case: the mile and the annulus
	differ ONLY in the offset band and in how the station is picked.

	A SLOT IS METRES OF X, NOT A COUNT OF STATIONS, and that is not a nicety. The
	road CURVES, so a station advances `_road_spacing() * cos(heading)` of X and
	not the full 6 m — measured 4.0 m over the shipped corridor. Counting stations
	per slot therefore packs the mile ~1.5x denser than LANDMARK_MILE_SPACING says,
	and does it differently on every seed (the same 1450 m spans a different number
	of stations in every world). So a slot's target X is arithmetic and the STATION
	is looked up from it, through the same binary search every other road consumer
	uses.

	ONE HASH PER ATTEMPT, and it carries everything. `hash(Vector3i(...))` is folded
	into three independent fields — 12 bits of along-slot jitter, 12 bits of
	lateral offset, one bit of side — so a rejected attempt re-hashes with a new
	`attempt` and moves the whole site rather than nudging one axis. That is the
	bead's "deterministic re-hash with a bounded attempt count, never a chunk draw".

	SIDES ALTERNATE BY KIND PARITY on the mile (walking the trail should not be
	48 detours to the left) and are hashed in the annulus, where there is no walk
	order to alternate along.

	A kind whose LANDMARK_SITE_TRIES attempts are all rejected has NO SITE this
	run. That is the honest degrade: the alternative is relaxing a rule that exists
	because the HQ, the city, the spawn bubble and the river are places a monument
	must not stand in.

	AND THE CORRIDOR STOPS AT THE SPAWN RATHER THAN REACHING BACK TO THE HQ, which
	is a CONSTRAINT and not a preference. This table is global and pre-computed, so
	anything it reads is read for the WHOLE world — it cannot take the post-draw
	skip every per-chunk rejection in this file takes. `tower_site_selfcheck`
	check 5 is what says so out loud: it moves the tower and demands that a chunk
	the disc does not reach be byte-identical, and a corridor whose west end was
	`tower_site().x` moved all 48 sites when the tower moved. Station 0 is the
	road's own origin and depends on nothing. The 400 m of road west of the spawn
	is the HQ's approach and belongs to the building, not to the museum.
	"""
	var sites: Dictionary = {}
	var kinds: int = LandmarkBuilders.LANDMARKS.size()

	# The corridor, in station indices: station 0 (the spawn, where the road is
	# DEFINED to begin) to the terminal station T. _road_extend_to_x is the uncapped
	# station cache (see _road_terminal_k's docstring for why the CONSUMERS cap and
	# it does not); T is the consumer cap and this is consumer number five.
	var mile_x_min: float = 0.0
	terrain._road_extend_to_x(mile_x_min, terrain.ROAD_TERMINAL_X)
	var k_first: int = terrain._road_first_k_at_or_after_x(mile_x_min)
	var k_last: int = terrain._road_terminal_k()
	var span: int = maxi(1, k_last - k_first)
	# The corridor in METRES of X (see the docstring for why not in stations), and
	# how many LANDMARK_MILE_SPACING slots fit in it.
	var corridor: float = maxf(1.0, terrain._road_station(k_last).center.x - mile_x_min)
	var mile_slots: int = clampi(int(corridor / terrain.LANDMARK_MILE_SPACING), 0, kinds)

	for kind in kinds:
		for attempt in terrain.LANDMARK_SITE_TRIES:
			var h: int = hash(Vector3i(
				kind * terrain.LANDMARK_HASH_PRIME_X,
				attempt * terrain.LANDMARK_HASH_PRIME_Y,
				terrain.run_seed ^ terrain.LANDMARK_SITE_SALT))
			# Three independent fields off one hash. Mask AFTER the shift: hash()
			# may return a negative and `>>` on one is arithmetic.
			var u_along: float = float(h & 0xFFF) / 4096.0
			var u_lateral: float = float((h >> 12) & 0xFFF) / 4096.0
			var station: int
			var lateral: float
			var side: float
			if kind < mile_slots:
				# MILE — an evenly spaced slot, jittered inside its own slot so two
				# runs do not stand their monuments on the same metre marks.
				var target_x: float = mile_x_min + (float(kind) + u_along) * terrain.LANDMARK_MILE_SPACING
				station = terrain._road_first_k_at_or_after_x(target_x)
				lateral = lerpf(terrain.LANDMARK_MILE_LATERAL_MIN, terrain.LANDMARK_MILE_LATERAL_MAX, u_lateral)
				side = 1.0 if kind % 2 == 0 else -1.0
			else:
				# ANNULUS — anywhere along the same corridor, far off it.
				station = k_first + int(u_along * float(span))
				lateral = lerpf(terrain.LANDMARK_FIELD_LATERAL_MIN, terrain.LANDMARK_FIELD_LATERAL_MAX, u_lateral)
				side = 1.0 if ((h >> 24) & 1) == 0 else -1.0
			station = clampi(station, k_first, k_last)
			var st: Dictionary = terrain._road_station(station)
			var heading: float = st.heading
			# Same perp construction as _road_coins_at / _boss_at (XZ plane;
			# Vector2.x is world X, Vector2.y is world Z).
			var perp := Vector2(-sin(heading), cos(heading))
			var spot: Vector2 = st.center + perp * (side * lateral)
			var chunk: Vector2i = terrain.world_to_chunk(Vector3(spot.x, 0.0, spot.y))
			if _landmark_site_ok(terrain, chunk, sites):
				sites[chunk] = kind
				break

	return sites


static func _landmark_site_ok(terrain: Node3D, chunk: Vector2i, taken: Dictionary) -> bool:
	"""
	May kind K stand in this chunk? Asked of a CHUNK, not of a spot, because the
	site table is chunk-keyed and the exact metre inside it is still chosen by
	spawn_landmark_in_chunk's candidate loop against the finished `obstacles`.

	@param chunk: Candidate chunk coordinates.
	@param taken: Sites accepted so far this build.
	@return: false when the chunk is somebody else's, the HQ's, the city's, the
	         spawn bubble's or a river's.

	THE PAIRWISE SPACING RULE IS "DISTINCT CHUNKS", AND THAT IS ARITHMETIC.
	The bead asks for >= 2x the largest declared radius (2 * LANDMARK_RADIUS = 19 m)
	between two sites. A candidate stays LANDMARK_EDGE_MARGIN (12) inside its own
	chunk, so its centre is at most chunk_size/2 - 12 = 13 m from the chunk centre.
	Two landmarks in edge-adjacent chunks are therefore at least 50 - 13 - 13 = 24 m
	apart, and diagonally at least 70.7 - 2*13*sqrt(2) = 33.9 m. Both clear 19, so
	one Dictionary lookup buys the whole rule and there is no distance loop here.
	`landmark_sites_selfcheck` asserts the CONSEQUENCE (>= 19 m, measured on real
	built centres) rather than this argument.

	THE WHOLE CHUNK IS TESTED against the HQ and the spawn bubble, not its centre:
	a chunk half inside the disc would put its candidate loop to work looking for
	the one corner that clears it, and a monument crowding the HQ gate is the thing
	tower_excludes() exists to prevent. `chunk_size` as the radius is the diagonal
	half-width rounded up, i.e. deliberately generous.

	THE HQ CLAUSE CANNOT FIRE TODAY and it stays anyway. No station of the museum
	mile's corridor is west of the spawn and no annulus site is within 500 m of the
	centreline, so nothing this table proposes reaches a disc 400 m west on the road
	— which is exactly what keeps the table's global pre-computation compatible with
	`tower_site_selfcheck` check 5 (see `_build_landmark_sites`). It is one line and
	it is the project's single home for tower clearance, which every sibling spawner
	also calls; if a future corridor DOES reach the HQ, this is where the rejection
	belongs, and that check is where the consequence will be argued out.

	THE RIVER TEST is at the chunk CENTRE only, and it is a cheap pre-reject rather
	than the rule: `_biome_spot_ok` still refuses a wet candidate metre by metre in
	the spawner. Rejecting the chunk here is what stops a kind spending every one of
	its LANDMARK_PLACE_TRIES in a band it can never clear and vanishing from the run.
	"""
	if taken.has(chunk):
		return false
	var world: Vector3 = terrain.chunk_to_world(chunk)
	# Budapest owns its ground: the city's landmarks are the plan's 22 authored
	# slots, and a rolled Eiffel beside the authored one is the bug DEC-9 named.
	if terrain.in_budapest(world.x, world.z):
		return false
	if terrain.tower_excludes(world.x, world.z, terrain.chunk_size):
		return false
	if Vector2(world.x, world.z).length() < terrain.SPAWN_SAFE_RADIUS + terrain.chunk_size:
		return false
	if terrain.is_river_at(world):
		return false
	return true


static func _landmark_at(terrain: Node3D, chunk_pos: Vector2i) -> Dictionary:
	"""
	THE REVERSE LOOKUP: does any kind's site land in this chunk?

	@param chunk_pos: Chunk coordinates to decide for.
	@return: {} when no kind stands here (all but ~48 chunks in the world);
	         otherwise { "seed": int, "kind": int } — the seed for the landmark's
	         private RNG (spawn_landmark_in_chunk uses it for placement, geometry
	         and the coin ring) and the index into LANDMARKS of WHICH famous place
	         this is.

	Same signature and same contract as `_chest_at` / `_camp_at` / `_artifact_at`,
	and still consumes NO draw from the shared chunk RNG — but it is no longer a
	rarity roll at all. It is one Dictionary lookup in `landmark_sites()`, which is
	pure in run_seed and built once per run. See the MUSEUM MILE banner for why the
	question was inverted and why `scarcity_at` is no longer asked here.

	THE PRIVATE SEED IS KEYED ON THE KIND, not on the chunk. The kind is unique now,
	so (kind, run_seed) identifies the landmark exactly as (chunk, run_seed) used
	to — and the builders' stream touches COLOUR ONLY plus the in-chunk candidate
	spot, so this is the same "a private stream per landmark" contract it always
	was. Keying it on the chunk instead would work too and would be strictly worse:
	the palette would then depend on where the site happened to land.

	WHY THERE IS STILL NO CANDIDATE LOOP HERE. This is the landmine that BOTH
	artifacts and camps had to be dug out of, and it is worth restating rather than
	cross-referencing, because the next person to add a landmark family member will
	reach for it again: when this function runs, THE CHUNK HAS NO GEOMETRY YET. The
	only tests available are river and road, and neither rejects the thing that
	actually matters — overlap with the chunk's ~12 scattered blocks, its feature
	structure, its biome trees and massifs, its artifact and its camp. So the
	LANDMARK_PLACE_TRIES loop lives in spawn_landmark_in_chunk, where `obstacles`
	exists, and this function does exactly one thing: answer whether.

	EDUCATIONAL NOTE — the determinism contract:
	- Within a run the same chunk yields the IDENTICAL landmark (same place, same
	  spot, same stone jitter, same coin ring) however often it unloads and
	  regenerates: the site table is pure in run_seed, and every draw downstream
	  comes off one stream seeded from the kind in a fixed order.
	- Across runs, new_run() re-rolls run_seed, so a new world puts the same 48
	  places somewhere else entirely (and the road they are strung along moves too).
	- MULTIPLAYER NEEDS ZERO WORK because of exactly that: run_seed is already
	  shared by every peer in a room, so every peer generates the same landmark in
	  the same chunk by construction. No packet, no claim, no sync.
	- Whether a candidate is ACCEPTED is likewise load-order independent: the road
	  test reads the station cache (pure in `k`), the river test reads the biome
	  field (pure in world position + run_seed) and the overlap test reads the
	  chunk's own obstacle list (pure in chunk coords + run_seed).
	"""
	var sites: Dictionary = landmark_sites(terrain)
	if not sites.has(chunk_pos):
		return {}
	var kind: int = int(sites[chunk_pos])
	return {
		"seed": hash(Vector3i(kind, terrain.LANDMARK_SALT, terrain.run_seed)),
		"kind": kind,
	}


static func spawn_landmark_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Spawn this chunk's geo landmark, if a kind's site lands here, plus its coin
	ring and its marker node. Called from create_chunk AFTER spawn_camp_in_chunk and
	BEFORE spawn_chest_in_chunk (and therefore before _build_block_multimesh + the
	block_body attach), so every box the builder emits joins the chunk's SINGLE
	MultiMesh draw call and SINGLE BlockCollision body — a whole Eiffel Tower costs
	zero extra draw calls and zero extra physics bodies.

	That ordering is also WHY the candidate loop lives here rather than in
	_landmark_at: by this point the chunk's scattered blocks, feature structure,
	artifact, biome geometry and camp are all in `obstacles`, so every try is judged
	against the test that actually rejects. Both artifacts and camps had to have
	that loop dug back OUT of their roll for exactly this reason.

	@param chunk_pos: Chunk coordinates being generated.
	@param parent_chunk: The chunk mesh — the reward coins, any emissive accent and
	                     the marker Node3D parent here (per-chunk parenting rule:
	                     they are freed automatically when the chunk unloads, so
	                     there is no registry to keep in step and nothing to leak).
	@param obstacles: The chunk's footprint list. READ to place the landmark, then
	                  appended to with the landmark's own single footprint.
	@param block_batch / block_body: The chunk's visual batch + collision body,
	                                 threaded through to create_box.
	"""
	# BUDAPEST — no FIELD geo landmarks in the city (DEC-9). The builders are the
	# same ones the rect uses, but WHERE they stand is the plan's 22 authored slots
	# and not the museum mile — two Eiffel Towers, one authored and one sited, in
	# the same district. NOT tower_excludes(): per-system answers.
	#
	# BELT AND BRACES SINCE THE MUSEUM MILE: `_landmark_site_ok` already refuses a
	# chunk in the rect, so no site is ever here. It stays because this is the
	# spawner's own statement of the city policy every sibling spawner also makes,
	# and it costs one rectangle test on a path that already reads chunk_to_world.
	var lm_center: Vector3 = terrain.chunk_to_world(chunk_pos)
	if terrain.in_budapest(lm_center.x, lm_center.z):
		return
	if not terrain.spawn_landmarks:
		return
	var lm := _landmark_at(terrain, chunk_pos)
	if lm.is_empty():
		return

	# The landmark's OWN private RNG, seeded off (kind, run_seed) by _landmark_at:
	# it picks the spot AND feeds the builder AND draws the coin ring, so each
	# consumes as many draws as it needs without any other stream caring.
	var rng := RandomNumberGenerator.new()
	rng.seed = lm.seed

	var chunk_center: Vector3 = terrain.chunk_to_world(chunk_pos)
	# Candidates stay LANDMARK_EDGE_MARGIN (12 > LANDMARK_RADIUS 9.5) inside the
	# chunk, so nothing the builder emits straddles a seam.
	var half: float = terrain.chunk_size / 2.0 - terrain.LANDMARK_EDGE_MARGIN

	# Try a few spots; accept the FIRST that clears _biome_spot_ok — the single home
	# of the river + road-clearance + overlap rule (do not write a second copy). The
	# road half is what makes a landmark an off-road DESTINATION rather than
	# something you trip over on the trail; the overlap half is what keeps the
	# silhouette readable.
	#
	# EVERY TRY FAILING MEANS NO LANDMARK, and since the museum mile that means NO
	# SUCH PLACE IN THIS WORLD rather than "one chunk in fifty went without" — the
	# whole reason LANDMARK_PLACE_TRIES is 200 and not 4. It is still the right
	# call: the Eiffel Tower sticking out of a mountain massif reads far worse than
	# a world without an Eiffel Tower.
	#
	# THE RADIUS ASKED FOR IS THE ROW'S OWN, NOT LANDMARK_RADIUS, and that changed
	# with the museum mile (bead godot-test1-bcf). The sibling spawners hand over
	# "the widest this could be" because their shape is drawn from the same stream
	# AFTER the spot is chosen, so its real width is genuinely unknown here — but a
	# landmark's is DECLARED in its registry row, `landmark_selfcheck` asserts every
	# builder fits inside it, and the kind is known before the loop starts. Asking
	# for 9.5 m when the row says 4.2 was pure conservatism, and it stopped being
	# free the moment a rejected chunk meant the Sagrada Familia is not in this
	# world at all rather than "one chunk in fifty went without". LANDMARK_RADIUS
	# stays the GLOBAL BOUND every inequality in the banner is derived from
	# (the edge margin, the road clearance, the coin-ring pad) — this is the one
	# place that wanted the specific number instead of the bound.
	var entry: Dictionary = LandmarkBuilders.LANDMARKS[lm.kind]
	var want_radius: float = minf(float(entry.radius), terrain.LANDMARK_RADIUS)
	var local_x := 0.0
	var local_z := 0.0
	var placed := false
	var tries := 0
	while tries < terrain.LANDMARK_PLACE_TRIES and not placed:
		tries += 1
		local_x = rng.randf_range(-half, half)
		local_z = rng.randf_range(-half, half)
		if terrain._biome_spot_ok(chunk_center, local_x, local_z, want_radius, terrain.LANDMARK_ROAD_CLEARANCE, obstacles):
			placed = true
	if not placed:
		return

	var center := Vector3(local_x, 0.0, local_z)

	# --- Build it. The registry is pure data (and lives with its builders in
	# scripts/landmark_builders.gd), so the dispatch is one call() on a method-name
	# String and adding a famous place touches no code here at all. `builder` being
	# a String rather than a Callable is what lets LANDMARKS be a `const`; the cost
	# is that a typo'd method name is caught at call time, which is why
	# landmark_selfcheck.gd calls every builder in the table.
	#
	# `terrain` is passed as the builder's first argument because the builders are
	# STATIC on LandmarkBuilders: they hold no state, they only need this terrain's
	# create_box / _spawn_artifact_accent. Object.call() dispatches a GDScript
	# static method exactly as it dispatched these when they were methods here.
	var footprint: Dictionary = terrain._landmark_builders.call(entry.builder, terrain, center, rng, parent_chunk, block_batch, block_body)

	# --- The reward: a small ring of ordinary coins round the base, and
	# DELIBERATELY NO GEM (the guaranteed gem stays the artifacts' distinction — see
	# the REWARD DECISION in the constant banner). These are ordinary chunk-local
	# coins parented to the chunk; the road's station-claim logic is not involved.
	#
	# ORDER MATTERS, and this is the same ordering gotcha artifacts and camps both
	# carry: the landmark's own footprint is appended to `obstacles` only AFTER these
	# coins are settled. That footprint is a CIRCLE with a `top`, but Stonehenge, the
	# Plaza Mayor and the Golden Gate are mostly HOLLOW — settling their reward coins
	# against that circle would perch them on the silhouette top, i.e. floating
	# several metres up in open air over an empty middle. Settling first means they
	# meet only real block stone and land where the player can actually pick them up.
	if terrain.spawn_coins and terrain.coin_scene != null:
		var coin_count := rng.randi_range(terrain.LANDMARK_COIN_MIN, terrain.LANDMARK_COIN_MAX)
		var ring_radius: float = footprint.radius + rng.randf_range(terrain.LANDMARK_COIN_RING_PAD_MIN, terrain.LANDMARK_COIN_RING_PAD_MAX)
		var i := 0
		while i < coin_count:
			i += 1
			var a := rng.randf_range(0.0, TAU)
			var cx := center.x + cos(a) * ring_radius
			var cz := center.z + sin(a) * ring_radius
			# Same perch-or-skip rule as road coins (one home: _settle_coin_y): the
			# ring can graze a neighbouring block, so a coin perches on a climbable
			# top or is dropped under a sheer wall.
			var cy: float = terrain._settle_coin_y(cx, cz, terrain.COIN_GROUND_HEIGHT, obstacles)
			if is_inf(cy):
				continue
			var coin = terrain.coin_scene.instantiate()
			coin.position = Vector3(cx, cy, cz)
			parent_chunk.add_child(coin)

	# --- The marker: the landmark's only other non-batched node, and it has no mesh,
	# no script and no physics — a bare Node3D costs ZERO draw calls and ZERO
	# physics. It exists so scripts/landmark_toast.gd can find landmarks the way
	# EVERY other system in this project finds things: BY GROUP, never by reference
	# (CLAUDE.md "Node discovery is group-based"). Parenting it to the chunk means it
	# is freed automatically when the chunk unloads, so there is no registry to keep
	# in step, nothing to leak, and a landmark that streams back in re-registers
	# itself for free.
	#
	# The four metas are the whole contract with the toast: the English name and
	# fact (which ARE the translation keys — CLAUDE.md Localization RULE 1), the
	# shape's real radius, so the toast can measure "within ~15 m of the STONE"
	# rather than "within 15 m of a point" and a small statue and a wide plaza both
	# trigger where they look like they should, and the REGISTRY INDEX — which is
	# what lets the toast ask LandmarkBuilders.quiz_options() for two plausible
	# wrong answers. The index is carried rather than re-derived because the name
	# is a translation key, not an identity: looking the row up by name would break
	# the moment two places shared one.
	var marker := Node3D.new()
	marker.name = "LandmarkMarker"
	marker.position = center
	marker.add_to_group("landmark")
	marker.set_meta("name_key", entry.name)
	marker.set_meta("fact_key", entry.fact)
	marker.set_meta("radius", footprint.radius)
	marker.set_meta("kind", lm.kind)
	parent_chunk.add_child(marker)

	# --- ONE round footprint, and it is NON-CLIMBABLE, unlike a chest's. These are
	# 5-18 m tall, so a road coin perched on the "top" of the circle would float
	# unreachably high — the same call the tree/canopy and cactus footprints make.
	# _settle_coin_y therefore SKIPS a road coin whose column crosses a landmark
	# instead of stranding it in the sky.
	#
	# This single footprint IS the crocodile exclusion: spawn_crocodiles_in_chunk
	# already rejects candidates within ob.radius + min_object_clearance of a
	# footprint, so a landmark reads as a calm pocket with NO EDIT to the crocodile
	# spawner. Known consequence, exactly as camps document it: the croc COUNT is
	# unchanged (the retry budget absorbs the rejections) but the croc POSITIONS in a
	# landmark chunk DO shift, because a rejected candidate skips the successful
	# spawn's rotation.y draw and shifts the rest of that chunk's croc stream.
	# Within-run determinism still holds unconditionally — the footprint is a pure
	# function of chunk coords + run_seed.
	#
	# ponytail: one circle + one top is the whole footprint vocabulary the coin and
	# crocodile rules speak, so a hollow landmark reserves its empty middle too. That
	# errs toward "no coin here" rather than "a coin buried in stone", which is the
	# failure the rule exists to prevent; if it ever looks wrong, give the footprint
	# a per-shape solid-centre height rather than a richer vocabulary.
	obstacles.append({ "pos": center, "radius": footprint.radius, "top": footprint.top, "climbable": false })
