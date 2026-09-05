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
##   1b. A NEW SEED RESEATS THE TABLE. The site table is memoized for the run, so
##      a seed assigned AFTER the first lookup — the multiplayer joiner's path —
##      would otherwise keep the OLD run's 48 landmarks while every other
##      seed-derived stream moved. Asserted on `set_run_seed()`, which CLAUDE.md
##      makes the ONLY place the seed is written and therefore the only seam that
##      sees every door.
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
##   5. THE MILE IS WALKED. Every site chunk is built THROUGH `create_chunk` (and
##      check 5 reads this file's own harness as text to keep it that way); the kinds that end
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
## EVERY FILE CHECK 4 READS `_landmark_at` OUT OF, and it is a LIST because the
## spawners keep moving house: the section left for `terrain_landmarks.gd` at bd
## `godot-test1-ftn.26` and `endless_terrain.gd` kept a one-line forwarder.
## Reading the terrain alone would therefore still FIND the name and read a body
## that is a single call — passing for the wrong reason, with a `randf` added to
## the real reverse lookup sailing through. `scarcity_selfcheck.SPAWNER_SCRIPTS`
## is the same shape for the same reason (bd ftn.7); a name found in NONE of
## these still fails by name, so the next extraction adds one line here.
const SOURCE_SCRIPTS: Array[String] = [
	"res://scripts/endless_terrain.gd",
	"res://scripts/terrain_landmarks.gd",
]
## This file, for check 5's guard on its own harness.
const SELF_SCRIPT: String = "res://scripts/landmark_sites_selfcheck.gd"
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
## Kinds built anywhere: measured 37 / 43 / 43 of 48, through `create_chunk`.
const MIN_KINDS_BUILT: int = 34
## N = 12, and it is the bead's own acceptance number: "at least 12 kinds stand
## within the road corridor of a 3 km run". A slot is a SITE and a site is not yet
## a landmark — its chunk still has to have room for the shape — so
## LANDMARK_MILE_SPACING is sized to put NINETEEN slots on the 1450 m mile to
## stand twelve. Measured 13 / 15 / 14, through `create_chunk`.
const MILE_MIN_IN_CORRIDOR: int = 12

## How far off the centreline still counts as "in the corridor" for check 5.
## LANDMARK_MILE_LATERAL_MAX (120) is where a mile site is placed; a chunk is
## 50 m wide and the candidate loop moves the stone up to 13 m inside it, so the
## band has to be at least that much wider or the check measures its own slack.
const CORRIDOR_PAD: float = 40.0

## Stations to compare between the re-seeded road and a freshly born one. Spread
## far enough apart that a road agreeing at all four by luck is not a thing that
## happens: the centreline is a random walk in heading, so two seeds diverge
## within a few stations and stay diverged.
##
## IT STARTS AT 2, NOT AT 1. Station 0 is the origin and station 1 is (6, 0) for
## EVERY seed — the recurrence has drawn no turn yet — so probing either of them
## is vacuous: they agree between two seeds because they agree between all seeds.
## The first station a seed can move is 2.
##
## `ROAD_PROBE_X` is walked first, because `_road_station()` only READS the cache
## (an index it does not hold is an out-of-bounds error, not a rebuild) and
## `_road_extend_to_x()` is what grows it — which is also what makes this assert
## the road was REBUILT and not merely emptied.
const ROAD_PROBE_STATIONS: Array[int] = [2, 40, 200, 900]
const ROAD_PROBE_X: float = 8000.0

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
	# ONE FRAME FIRST, and it is load-bearing: `root.add_child()` during
	# `_initialize()` does not put a node in the tree yet, so `_build_every_site`'s
	# `create_chunk` would build every chunk detached — and the spawners that ask a
	# chunk for its GLOBAL position or its tree (platform guards, the hunter cap)
	# would degrade with an engine error instead of running.
	await process_frame
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	var consts: Dictionary = terrain_script.get_script_constant_map()
	var registry: Array = load(BUILDERS_SCRIPT).get_script_constant_map().get("LANDMARKS", [])
	if registry.is_empty():
		_fail("landmark_builders.gd has no LANDMARKS registry — nothing to site")
	else:
		_check_unique(terrain_script, registry)
		_check_seed_reseats_the_table(terrain_script)
		_check_legal_sites(terrain_script, consts)
		var built: Array = _build_every_site(terrain_script)
		_check_spacing(consts, built)
		_check_no_draw(terrain_script, built)
		_check_corridor(consts, registry, built)
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
	"""
	A REAL terrain in the tree on `seed_value`, with the crocodile scene check 4
	needs. `tower_site_selfcheck`'s recipe, and both halves of it matter:

	IN THE TREE, because `create_chunk` parents its chunk to the terrain and
	several spawners ask that chunk for its GLOBAL position or its tree (the
	platform guards, the hunter cap, the chest's `setup`). Detached, they degrade
	with an engine error instead of running — which is a harness measuring a
	world the game does not build.

	SEEDED AFTER `add_child`, which is the trap: `_ready()` calls `_roll_run_seed()`,
	so a seed assigned before the node enters the tree is thrown away and every
	"deterministic" measurement below runs on a fresh random world. `_run()` awaits
	one frame first, because `root.add_child()` during `_initialize()` does not put
	a node in the tree at all.

	It never streams on its own: `_ready` finds no node in group "player", so
	`player` stays null and `_process` returns immediately.
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.crocodile_scene = load(CROC_SCENE)
	root.add_child(terrain)
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
		var sites: Dictionary = TerrainLandmarks.landmark_sites(terrain)
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
				var lm: Dictionary = TerrainLandmarks._landmark_at(terrain, chunk)
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
# CHECK 1b — a new seed reseats the table
# ============================================================================

func _check_seed_reseats_the_table(terrain_script: GDScript) -> void:
	"""
	`set_run_seed()` DROPS THE MEMOIZED SITE TABLE, and this is the check that
	says so.

	The table is built lazily and cached for the run. Nothing about that is wrong
	until a seed arrives AFTER the first lookup — which is not a corner case but
	the multiplayer join path: a peer rolls its own seed in `_ready()`, streams
	chunks, and is then handed the room's seed through `set_run_seed()`. Without
	the reset that peer keeps the OLD world's 48 landmarks while its road, its
	biome field, its crocodiles and every other seed-derived stream have moved —
	silently, because a cached Dictionary looks exactly like a correct one.
	Codex review of PR #228 found it.

	THE ASSERTION IS ON `set_run_seed()` AND NOT ON `new_run()`, deliberately.
	CLAUDE.md's rule is that `set_run_seed()` is the ONLY place the seed is
	written — so it is the only seam that sees every door, and it is the one a
	future joiner path has to be safe through. Driving `new_run()` here would
	certify the door this bug came through as unlocked.

	AND THE ROAD GOES WITH IT (bead godot-test1-bvq). The mile is strung along the
	centreline, and `road_stations` / `_road_terminal_k_cache` /
	`_approach_coin_line_cache` are memoized off the seed exactly like the site
	table — so while they were reset one level up, in `new_run()`, a BARE
	`set_run_seed()` rebuilt this run's sites onto the PREVIOUS run's road. This
	check used to clear them by hand before comparing, with a `ponytail:` note
	saying the move belonged to whoever owned the road. It does not any more:
	`set_run_seed()` calls `_drop_seeded_memos()`, so the road is asserted here
	directly instead of being papered over.

	AND THE CORRIDOR'S EAST END IS ASSERTED THE OTHER WAY UP (bd
	`godot-test1-2iu`). It was filed as a missing reset — it is the one memo in
	this family `_drop_seeded_memos()` does not clear — and it is not one: the
	function scans `BudapestPlan`'s authored polyline from the gate, so it is
	SEED-INDEPENDENT and clearing it would imply a dependency that does not exist.
	The bead's real product is the assertion below, which pins that property
	instead of leaving it to be re-derived from a docstring.

	MUTATION-TESTED, all three: drop the `_landmark_sites_cache` reset from
	`_drop_seeded_memos()` and the first assertion goes red; drop the
	`road_stations` reset and the CENTRELINE assertion does; make
	`_approach_coin_east_end()` read `run_seed` and the EAST END one does.
	"""
	var terrain := _terrain(terrain_script, SEEDS[0])
	# Build it, exactly as a chunk streaming in would.
	var first: Dictionary = TerrainLandmarks.landmark_sites(terrain).duplicate()
	# ...and POISON THE APPROACH CORRIDOR'S EAST END the same way (bd
	# `godot-test1-2iu`). It is memoized on first ask like the table above, so an
	# assertion that does not fill the cache HERE would pass on a terrain that
	# simply never cached — which is why this line is the setup and not the test.
	var first_east: float = terrain._approach_coin_east_end()
	if first.is_empty():
		_fail("seed %d sited nothing — check 1b cannot run" % SEEDS[0])
		terrain.free()
		Sentinel.done("seed_reseats_the_table")
		return

	# ...then hand it another seed, the way a multiplayer joiner is handed the
	# room's, and ask again.
	terrain.set_run_seed(SEEDS[1])
	var second: Dictionary = TerrainLandmarks.landmark_sites(terrain)
	if second == first:
		_fail("the site table survived set_run_seed(%d) — it is still seed %d's %d sites, "
				% [SEEDS[1], SEEDS[0], first.size()]
				+ "so a multiplayer joiner would walk the master's road past the LAST run's "
				+ "landmarks (the memo must be dropped where the seed is written)")

	# ...and it must be the RIGHT new table, not merely a different one: identical
	# to what a terrain born on that seed builds. Without this, a reset that
	# cleared the memo but left some other stale state would still pass above —
	# and THE ROAD IS THAT OTHER STALE STATE. No hand-clearing here any more (bead
	# godot-test1-bvq): the bare `set_run_seed()` above is the whole setup, so if
	# the road survived the re-seed the sites would be strung along the LAST run's
	# centreline and this comparison is what says so.
	var rebuilt: Dictionary = TerrainLandmarks.landmark_sites(terrain)
	var fresh := _terrain(terrain_script, SEEDS[1])
	var expected: Dictionary = TerrainLandmarks.landmark_sites(fresh)
	if rebuilt != expected:
		_fail("after set_run_seed(%d) the table has %d sites but a terrain "
				% [SEEDS[1], rebuilt.size()]
				+ "born on that seed builds %d — the rebuild is not a pure function of the "
				% expected.size()
				+ "new seed (a road memo that outlived the seed write is how)")

	# THE CENTRELINE ITSELF, directly. The table comparison above is transitive —
	# the sites ARE station indices — but "the sites match" is a long way from
	# "the road matches", and a future placement rule that leaned less on the road
	# would quietly stop asserting it. So walk the two roads station by station,
	# after growing BOTH caches over the same X through the shipped
	# `_road_extend_to_x()` — which is also what makes this prove the re-seeded
	# terrain REBUILDS a road rather than merely having dropped one.
	terrain._road_extend_to_x(0.0, ROAD_PROBE_X)
	fresh._road_extend_to_x(0.0, ROAD_PROBE_X)
	for k: int in ROAD_PROBE_STATIONS:
		var got: Vector2 = terrain._road_station(k)["center"]
		var want: Vector2 = fresh._road_station(k)["center"]
		if got.distance_to(want) > 1e-4:
			_fail("after set_run_seed(%d) road station %d is at %s but a terrain born on "
					% [SEEDS[1], k, got]
					+ "that seed puts it at %s — the station cache outlived the seed write, "
					% want
					+ "so every seeded consumer is being built onto the PREVIOUS run's road")
			break
	# ...AND THE ONE MEMO IN THIS FAMILY THAT IS *NOT* CLEARED, asserted from the
	# other side (bd `godot-test1-2iu`). `_approach_coin_east_end_cache` looks
	# exactly like `_approach_coin_line_cache`'s twin, and two readers in one day
	# filed it as a missing reset — but east of the gate the corridor IS the
	# avenue at z = 0, so that function scans `BudapestPlan`'s authored polyline
	# and takes a bridge's abutment: every term is a designer's constant, with no
	# `run_seed` in it. It is therefore SEED-INDEPENDENT, which is what makes
	# never clearing it correct, and this is the assertion that pins the claim so
	# nobody has to re-derive it from the docstring a third time. `first_east` was
	# taken BEFORE the re-seed, so the memo really was populated under SEEDS[0].
	var east: float = terrain._approach_coin_east_end()
	var want_east: float = fresh._approach_coin_east_end()
	if absf(east - want_east) > 1e-4 or absf(first_east - want_east) > 1e-4:
		_fail("the approach corridor's east end moved with the seed: %.3f under %d, "
				% [first_east, SEEDS[0]]
				+ "%.3f after set_run_seed(%d), %.3f on a terrain born there — it is "
				% [east, SEEDS[1], want_east]
				+ "supposed to be a pure function of BudapestPlan's authored polyline, "
				+ "which is the whole reason _drop_seeded_memos() does not clear its memo")
	fresh.free()
	terrain.free()
	print("  set_run_seed drops the memo: %d sites -> %d, and they are the new seed's own"
			% [first.size(), second.size()])
	Sentinel.done("seed_reseats_the_table")


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
		for chunk: Vector2i in TerrainLandmarks.landmark_sites(terrain):
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
		if TerrainLandmarks._landmark_site_ok(t, row[1] as Vector2i, {}):
			_fail("_landmark_site_ok accepted a chunk inside %s (%s) — that rule is gone"
					% [String(row[0]), str(row[1])])
	# The positive control: an accepted site's own chunk must still be accepted
	# when nothing is taken, or every refusal above proves only that the predicate
	# refuses everything.
	var legal: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	for chunk2: Vector2i in TerrainLandmarks.landmark_sites(t):
		legal = chunk2
		break
	if legal == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		_fail("seed %d sited nothing at all — check 2's positive control cannot run" % SEEDS[0])
	elif not TerrainLandmarks._landmark_site_ok(t, legal, {}):
		_fail("_landmark_site_ok refuses %s, which is one of its OWN sites — the four "
				% str(legal) + "refusals above prove nothing")
	# ...and the "somebody already took it" rule, which is the pairwise spacing.
	elif TerrainLandmarks._landmark_site_ok(t, legal, {legal: 0}):
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
	Build every site chunk of every seed THROUGH THE SHIPPED `create_chunk` and
	collect what was actually built.

	@return: Array of { "seed", "chunk", "kind", "world" (Vector3 centre),
	         "marker" (the real Node3D, still parented to its real chunk node) }.

	IT CALLS `create_chunk`, NOT A HAND-ROLLED PIPELINE, and that is the whole
	point of this function. The first version of this check ran props -> biome
	content -> landmark, which LOOKS like the real order and is not: production
	runs the ARTIFACT and the CAMP between them, and both append footprints to
	`obstacles` BEFORE `spawn_landmark_in_chunk` reads it. A candidate that clears
	a chunk without them can be rejected — or moved — in the game, so the harness
	was measuring a slightly emptier world than the one that ships (seed 20260904:
	38 built in the hand-rolled order, 37 through `create_chunk`) and every number
	downstream of it — the built floor, the corridor count, the spacing, the card —
	was asserted against that wrong world.
	Codex review of PR #228 found it.

	THE FIX IS TO DELETE THE ORDER, NOT TO EXTEND IT. A harness that lists the
	spawners in the right order is a second copy of `create_chunk`'s ordering
	comment, and the next spawner inserted before the landmark desynchronises it
	again in silence. Calling the shipped function makes the divergence
	unrepresentable, which is why there is no "harness matches create_chunk"
	assertion here: there is nothing left to disagree. What guards it instead is a
	TEXT check in check 5 — this function must call `create_chunk` and must not call
	`spawn_landmark_in_chunk` — because a construction argument fails silently.
	MUTATION-TESTED: put the hand-rolled order back and the counts move to
	38 / 42 / 43, check 5's two guards fire by name and check 6 fires as well.

	The terrain node goes INTO THE TREE, because `create_chunk` parents its chunk
	to it — the `tower_site_selfcheck` recipe. It still streams nothing on its own:
	`_ready` finds no node in group "player", so `player` stays null and `_process`
	returns immediately. `_free_built` frees each terrain, and its chunks with it.
	"""
	var out: Array = []
	for seed_value: int in SEEDS:
		var terrain := _terrain(terrain_script, seed_value)
		var sites: Dictionary = TerrainLandmarks.landmark_sites(terrain)
		for chunk: Vector2i in sites:
			terrain.create_chunk(chunk)
			var chunk_node: Node3D = terrain.active_chunks.get(chunk)
			if chunk_node == null:
				continue
			var marker: Node3D = null
			for child in chunk_node.get_children():
				if child is Node3D and child.is_in_group("landmark"):
					marker = child
					break
			if marker == null:
				continue
			out.append({
				"seed": seed_value,
				"chunk": chunk,
				"kind": int(sites[chunk]),
				"world": terrain.chunk_to_world(chunk) + marker.position,
				"marker": marker,
				"chunk_node": chunk_node,
				"terrain": terrain,
			})
	return out


func _free_built(built: Array) -> void:
	"""
	Drop every terrain `_build_every_site` kept alive, and with it every chunk
	`create_chunk` parented to one. Only about not printing a leak report at exit —
	which reads exactly like a failure in the CI log.
	"""
	var terrains: Dictionary = {}
	for row: Dictionary in built:
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

func _check_no_draw(terrain_script: GDScript, built: Array) -> void:
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
	var body := ""
	var unread := ""
	for path: String in SOURCE_SCRIPTS:
		var source: String = FileAccess.get_file_as_string(path)
		if source.is_empty():
			unread = path
			break
		body += _function_body(source, "_landmark_at") + "\n"
	if not unread.is_empty():
		_fail("could not read %s as text — check 4's text half cannot run" % unread)
	else:
		if body.strip_edges().is_empty():
			_fail("check 4 found no `_landmark_at` in any of %s — it was renamed, and "
					% ", ".join(SOURCE_SCRIPTS)
					+ "this assertion now measures nothing")
		for forbidden: String in ["RandomNumberGenerator", "randf", "randi", "scarcity_at("]:
			if body.contains(forbidden):
				_fail("`_landmark_at` contains `%s` — the reverse lookup takes no draw and asks "
						% forbidden + "no gradient (see the MUSEUM MILE banner)")

	var terrain := _terrain(terrain_script, SEEDS[0])
	var sites: Dictionary = TerrainLandmarks.landmark_sites(terrain)
	# The subject must be a site that really BUILT something, or the comparator's
	# own control below ("with a landmark, the boxes differ") is measuring a chunk
	# whose candidate loop failed and would fail for the wrong reason. It is taken
	# from `_build_every_site`'s list — which is `create_chunk`'s own answer — so
	# this check cannot pick a subject the game disagrees about.
	var site_chunk: Vector2i = Vector2i(0x7FFFFFFF, 0x7FFFFFFF)
	for row: Dictionary in built:
		if int(row["seed"]) == SEEDS[0]:
			site_chunk = row["chunk"]
			break
	if site_chunk == Vector2i(0x7FFFFFFF, 0x7FFFFFFF):
		_fail("seed %d built nothing at any of its %d sites — check 4's A/B cannot run"
				% [SEEDS[0], sites.size()])
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

	NOT `create_chunk` ITSELF, unlike `_build_every_site`, and for one reason: this
	needs the batch and the obstacle list SPLIT at the landmark, which only calling
	the spawners in order can give. So the order is written out here — and it is the
	real one, artifact and camp included, which is exactly the thing the build pass
	got wrong. Everything the split does not need runs after the split point.

	The terrain and its scratch chunk go into the tree, because the chest asks its
	parent for a global transform and a tree on `setup()`.
	"""
	var terrain := _terrain(terrain_script, SEEDS[0])
	terrain.spawn_landmarks = landmarks_on
	var platforms: Array = []
	var batch: Array = []
	var body := StaticBody3D.new()
	var obstacles: Array = terrain.spawn_objects_in_chunk(chunk, platforms, batch, body)
	terrain.spawn_biome_content_in_chunk(chunk, obstacles, batch, body)
	var chunk_node := MeshInstance3D.new()
	chunk_node.position = terrain.chunk_to_world(chunk)
	terrain.add_child(chunk_node)
	terrain.spawn_artifact_in_chunk(chunk, chunk_node, obstacles, batch, body)
	terrain.spawn_camp_in_chunk(chunk, chunk_node, obstacles, batch, body)
	var pre: PackedByteArray = var_to_bytes(batch) + var_to_bytes(obstacles)
	TerrainLandmarks.spawn_landmark_in_chunk(terrain, chunk, chunk_node, obstacles, batch, body)
	terrain.spawn_chest_in_chunk(chunk, chunk_node, obstacles, batch, body)
	var croc_parent := MeshInstance3D.new()
	croc_parent.position = terrain.chunk_to_world(chunk)
	terrain.add_child(croc_parent)
	terrain.spawn_crocodiles_in_chunk(chunk, croc_parent, obstacles)
	var crocs: PackedStringArray = PackedStringArray()
	for child in croc_parent.get_children():
		crocs.append("%s@%s" % [child.name, str((child as Node3D).position)])
	var boxes: PackedByteArray = var_to_bytes(batch)
	body.free()
	terrain.free()  # frees the scratch chunk and the croc parent with it
	return { "pre": pre, "boxes": boxes, "crocs": crocs }


func _function_body(source: String, name: String) -> String:
	"""
	The lines of `func <name>(...)` up to the next top-level `func` — the crude
	reader `scarcity_selfcheck.gd` uses, and for the same reason: GDScript's
	one-function-per-column-0-`func` layout is the whole grammar this needs.

	IT MATCHES `static func` TOO (bd `godot-test1-ftn.26`), and that one word is
	the difference between this check measuring the reverse lookup and measuring
	nothing. `_landmark_at` moved to `terrain_landmarks.gd` as a STATIC function,
	so a reader that only knew `func ` found the terrain's one-line forwarder,
	read a body with no `randf` in it, and passed — which is exactly the vacuous
	pass the SOURCE_SCRIPTS list was added to prevent. Caught by planting a
	`randf()` in the real function and watching the check stay green;
	`scarcity_selfcheck` learned the same thing at ftn.6.
	"""
	var out := ""
	var inside := false
	for line: String in source.split("\n"):
		if line.begins_with("func " + name + "(") \
				or line.begins_with("static func " + name + "("):
			inside = true
			continue
		if inside:
			if line.begins_with("func ") or line.begins_with("static func "):
				break
			out += line + "\n"
	return out


# ============================================================================
# CHECK 5 — the mile is walked
# ============================================================================

func _check_corridor(consts: Dictionary, registry: Array, built: Array) -> void:
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
	# THE HARNESS ITSELF, READ AS TEXT, and it is the assertion that keeps every
	# number below honest. `_build_every_site` must call `create_chunk` and must not
	# call the landmark spawner directly: a hand-rolled order is how this check came
	# to measure a world with no artifacts and no camps in it (see that function's
	# docstring). A behavioural comparison is impossible here — the harness IS the
	# shipped function, so there is nothing to compare it against — which is exactly
	# why the guard is on the source.
	var own_source: String = FileAccess.get_file_as_string(SELF_SCRIPT)
	var harness := _function_body(own_source, "_build_every_site")
	if harness.is_empty():
		_fail("could not read `_build_every_site` out of %s — the harness guard is measuring "
				% SELF_SCRIPT + "nothing")
	else:
		if not harness.contains("create_chunk("):
			_fail("`_build_every_site` no longer calls `create_chunk` — every count below is "
					+ "then measured against a hand-rolled spawner order, which is how this "
					+ "check once reported 38 built where the game builds 37")
		if harness.contains("spawn_landmark_in_chunk("):
			_fail("`_build_every_site` calls `spawn_landmark_in_chunk` directly — the landmark "
					+ "must be reached THROUGH `create_chunk`, or the artifact and camp "
					+ "footprints its candidate loop is judged against are missing")

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
			if world.x < 0.0 or world.x > terminal_x:
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
