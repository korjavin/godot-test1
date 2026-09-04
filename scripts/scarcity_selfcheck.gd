extends SceneTree
## Headless self-check for the SCARCITY GRADIENT — one rule for every biome.
##
##   godot --headless --path . --script res://scripts/scarcity_selfcheck.gd
##
## Prints "SELFCHECK OK" and exits 0, or prints what failed and exits 1.
##
## THE BUG THIS FILE EXISTS FOR (bead `godot-test1-bn8`, a bug against 8gw.15).
## The gradient shipped as a per-FAMILY edit — every rarity roll a reviewer
## happened to look at got its `* k`, and several builders never did. Oases,
## dunes and mammoth skeletons kept their full density all the way out while the
## plains emptied, which is exactly what the owner reported: *"i see that object in
## plains rare and rare when we farther away from center hq+budapest, but I don't
## see this happening with desert and probably other biomes, it should be one rule
## for all"*. A per-family fix is a per-family regression waiting to happen, so the
## acceptance here is deliberately written against the BIOME ENUM and not against a
## list of builders: a biome added tomorrow is measured the day its row lands, and a
## builder that forgets `k` fails the build rather than being noticed in a screenshot.
##
## Three checks:
##
##   1. THE GRADIENT ITSELF — `scarcity_at` is monotone decreasing, exactly 1
##      inside the union of the Budapest rect and the HQ-to-gate corridor, and
##      exactly 0 at SCARCITY_PLAIN_DISTANCE, with `_SCARCITY_DENOM` bound to the
##      two constants it is derived from. (Moved here verbatim from
##      `prop_selfcheck`'s check 9, which is where the gradient's first acceptance
##      lived; that file says "don't grow this into a suite" and scarcity now has
##      more to assert than a prop check should carry.)
##
##   2. ONE RULE FOR EVERY BIOME — for each `Biome` value, a field of chunks NEAR
##      the centre and a field FAR beyond the plain distance, both built through
##      the shipped spawners. Far must build NOTHING; near must build something,
##      or "far is empty" proves only that the sweep found no chunks. The one
##      exemption is the mountain MASSIF (owner ruling 2026-09-04), and it is
##      asserted POSITIVELY — a far mountain band must still build stone — so the
##      exemption cannot rot into "the mountain builder is broken".
##
##   3. WHAT MUST NEVER THIN — predators, hunters, bosses and the coin road. Read
##      as TEXT out of `endless_terrain.gd`, because that is the only form of the
##      assertion a future edit cannot slip past: a behavioural count can only
##      prove the spawner did not thin at the places it was sampled. The predators
##      also get a real count, near against far, and the direction is UP (the
##      difficulty gradient widens the target with |x|) — thinning them would
##      REWARD walking away from Budapest, which is the opposite of the ruling.
##
## HOUSE RULE, as everywhere else: every assertion is an effect measurement with a
## control. Check 2's near field is check 2's control; check 3's `far >= near` has
## the far count's own non-zero as its control.

const TERRAIN_SCRIPT: String = "res://scripts/endless_terrain.gd"
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"

## CHECK 2's two sweeps, and they are DELIBERATELY LOPSIDED.
##
## The NEAR field is the control and it is expensive — every chunk really builds
## its props and its biome content — so ±22 chunks and eighteen samples per biome
## (six per seed) is enough; the sweep width is `batch_selfcheck` check 5's, for its
## reason: SNOW and CITY are the rare bands, so the square has to contain them.
##
## The FAR field has to be BIG, and that is what makes the mutation test bite. A
## far chunk builds nothing, so it costs almost nothing; but the rarest thing this
## check has to catch is one oasis in eight desert chunks, and eighteen samples
## miss that one time in ten. At 250 chunks per biome a builder that forgot k
## produces ~30 oases, ~50 dunes or ~250 mammoth candidates — not a coin flip.
## Sample counts are TOTALS across SEEDS, not per seed.
const NEAR_SWEEP: int = 22
const NEAR_SAMPLES: int = 18
const FAR_SWEEP: int = 60
const FAR_SAMPLES: int = 250

## Where the two fields stand. NEAR is ~700 m off the corridor's north edge — far
## enough out that k is well under 1 (so a builder reading k is really being
## exercised) and far enough from 0 that the field is obviously furnished. FAR is
## 8.2 km east of the Budapest rect, so its ±3 km square clears the plain distance
## with room to spare.
##
## NEITHER IS TRUSTED, THOUGH: `_sweep` asks `scarcity_at` about every chunk it
## takes and refuses one on the wrong side of k == 0. A 50 m chunk makes even the
## small sweep 2.2 km wide against a 4 km plain distance — the first version of
## this check put its far centre 4.6 km out, sampled chunks at 3.5 km with
## k = 0.048, and reported seven biomes as broken. The centres are where the
## fields are; the per-chunk test is what makes them the fields they claim to be.
const NEAR_CENTRE: Vector3 = Vector3(0.0, 0.0, 900.0)
const FAR_CENTRE: Vector3 = Vector3(12000.0, 0.0, 0.0)

## Seeds check 2 runs over. Three, because the biome field moves with `run_seed`
## and a single field could put a biome's samples somewhere unrepresentative.
const SEEDS: Array[int] = [20260904, 777, 4242]

## Every spawner that must NEVER read the gradient, by function name. Predators
## and the road are design-fixed (see the SCARCITY banner in endless_terrain.gd).
const NEVER_THINNED: Array[String] = [
	"spawn_crocodiles_in_chunk",
	"spawn_platform_crocodiles",
	"spawn_danube_crocodiles_in_chunk",
	"spawn_bosses_in_chunk",
	"spawn_hunters_in_chunk",
	"spawn_coins_in_chunk",
	"_road_coins_at",
]

var _failures: Array[String] = []


## THE END-OF-CHECK SENTINEL. A GDScript runtime error aborts the FUNCTION it
## lands in and lets the script carry on, so a check that dies halfway simply
## stops asserting and this file prints "SELFCHECK OK". Every check below stamps
## itself at its exit; the report site asks whether every stamp was reached.
## `scripts/selfcheck_sentinel.gd` carries the whole reasoning.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


func _initialize() -> void:
	var terrain_script: GDScript = load(TERRAIN_SCRIPT)
	var consts: Dictionary = terrain_script.get_script_constant_map()
	if not consts.has("SCARCITY_PLAIN_DISTANCE"):
		_fail("endless_terrain.gd has no SCARCITY_PLAIN_DISTANCE — the gradient is gone")
	else:
		_check_gradient(terrain_script, consts)
		_check_every_biome(terrain_script, consts)
		_check_never_thinned()
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
# CHECK 1 — the gradient itself
# ============================================================================

func _check_gradient(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	Scarcity gradient: objects thin logarithmically with distance from the UNION
	of Budapest rect and HQ-to-gate corridor (k=1 inside, 0 at 4 km).
	k = 1 - log(1+d/d0)/log(1+4000/d0), d0=400, clamped. Corridor Z from real
	coin-road envelope (see endless_terrain.gd SCARCITY_CORRIDOR_*).
	"""
	var terrain := Node3D.new()
	terrain.set_script(terrain_script)
	terrain.set_run_seed(20260826)
	var plain: float = float(consts["SCARCITY_PLAIN_DISTANCE"])
	var d0: float = float(consts["SCARCITY_D0"])
	var denom: float = float(consts["_SCARCITY_DENOM"])
	var corridor_rect: Rect2 = consts["SCARCITY_CORRIDOR_RECT"]
	# _SCARCITY_DENOM must be log(1+PLAIN/D0) = log(11); typed literal checked here.
	var expected_denom := log(1.0 + plain / d0)
	if absf(denom - expected_denom) > 1e-9:
		_fail("scarcity _SCARCITY_DENOM %.12f != log(1+PLAIN/D0) %.12f — keep in sync" % [denom, expected_denom])

	var bp: GDScript = load("res://scripts/budapest_plan.gd")
	var rect: Rect2 = bp.rect()
	var east_edge := rect.position.x + rect.size.x # 3800
	var samples: Array[float] = []
	var dists: Array[float] = [0.0, 1000.0, 2000.0, 3999.0, 4000.0]
	for d in dists:
		var probe_pos: Vector3
		if d == 0.0:
			probe_pos = Vector3(2700.0, 0.0, 0.0) # inside rect
		else:
			# Due east of rect (leaves the union east of both rect and corridor).
			probe_pos = Vector3(east_edge + d, 0.0, 0.0)
		samples.append(float(terrain.call("scarcity_at", probe_pos)))

	# Monotone decreasing.
	for i in range(1, samples.size()):
		if samples[i] > samples[i - 1] + 1e-6:
			_fail("scarcity k must be monotone decreasing: k at %d m (%.3f) > k at %d m (%.3f)" % [dists[i], samples[i], dists[i - 1], samples[i - 1]])
	# 0 at 4 km and just-inside non-vacuous.
	if absf(samples[4]) > 1e-6:
		_fail("scarcity k at 4 km must be 0, got %.6f" % samples[4])
	if not (samples[3] > 0.0 and samples[3] < 0.01):
		_fail("scarcity k at 3999 m must be >0 and <0.01, got %.6f" % samples[3])
	if samples[0] < 0.99:
		_fail("scarcity k inside Budapest must be ~1, got %.3f" % samples[0])
	# West of HQ disc must also be 1 inside corridor, 0 at 4 km west.
	var west_inside := Vector3(corridor_rect.position.x + 10.0, 0.0, 0.0)
	var west_outside := Vector3(corridor_rect.position.x - plain - 200.0, 0.0, 0.0)
	var k_west_in := float(terrain.call("scarcity_at", west_inside))
	var k_west_out := float(terrain.call("scarcity_at", west_outside))
	if k_west_in < 0.99:
		_fail("scarcity k inside corridor (west) must be ~1, got %.3f" % k_west_in)
	if absf(k_west_out) > 1e-6:
		_fail("scarcity k at 4 km west of corridor must be 0, got %.6f" % k_west_out)

	# The two fields check 2 builds must really straddle the gradient, or its
	# whole verdict is about two places that happen to look different. Asserted
	# here rather than assumed there: k is what this check owns.
	var k_near := float(terrain.call("scarcity_at", NEAR_CENTRE))
	var k_far := float(terrain.call("scarcity_at", FAR_CENTRE))
	if not (k_near > 0.2 and k_near < 0.95):
		_fail("check 2's NEAR_CENTRE has k = %.3f — it must be thinned but obviously furnished" % k_near)
	if k_far != 0.0:
		_fail("check 2's FAR_CENTRE has k = %.6f, must be exactly 0" % k_far)

	print("  gradient   k at 0/1/2/3999/4000 m: %.3f / %.3f / %.3f / %.3f / %.3f; near field k=%.3f, far field k=%.3f"
			% [samples[0], samples[1], samples[2], samples[3], samples[4], k_near, k_far])

	terrain.free()
	Sentinel.done("gradient")


# ============================================================================
# CHECK 2 — one rule for every biome
# ============================================================================

func _check_every_biome(terrain_script: GDScript, consts: Dictionary) -> void:
	"""
	FOR EVERY BIOME: a far field builds nothing, a near field builds something.

	Both fields are built through the SHIPPED spawners — `spawn_objects_in_chunk`
	(the scattered props, whose target is `roundi(target * k)`),
	`spawn_biome_content_in_chunk` (the biome's own builders) and the four rarity
	functions `_artifact_at` / `_camp_at` / `_chest_at` / `_landmark_at`. That is
	every family that puts something on the ground outside Budapest and the HQ.

	THE MASSIF IS THE ONE EXEMPTION and it is asserted POSITIVELY: a far MOUNTAIN
	chunk must still build biome boxes, because massifs are the impassable walls
	the flat-world invariant substitutes for terrain (owner ruling 2026-09-04,
	bead `godot-test1-bn8`). Asserting only "everything else is 0" would let the
	mountain builder break silently — the exemption would look exactly like a
	crash. Every OTHER family in that same far chunk is still held to 0, so the
	exemption is one builder wide and not one biome wide.

	PLAINS builds no biome content anywhere by design (its scattered props ARE its
	content), so its biome-box assertion is trivially satisfied; the props
	assertion in the same loop is what actually measures it.

	WHY THE ENUM AND NOT A LIST OF BUILDERS: a list is a second place to edit, and
	a builder added without touching it is silently unguarded — which is the exact
	defect this bead was filed for. Iterating `Biome` means a new band's content is
	measured the day the band exists.
	"""
	var biome_enum: Dictionary = terrain_script.get_script_constant_map()["Biome"]
	var mountain_value: int = int(biome_enum["MOUNTAIN"])

	# biome value -> { "chunks": int, "props": int, "biome": int, "features": int }
	var near: Dictionary = {}
	var far: Dictionary = {}

	for seed_value: int in SEEDS:
		var terrain := Node3D.new()
		terrain.set_script(terrain_script)
		terrain.set_run_seed(seed_value)
		_sweep(terrain, NEAR_CENTRE, near, false, NEAR_SWEEP, NEAR_SAMPLES)
		_sweep(terrain, FAR_CENTRE, far, true, FAR_SWEEP, FAR_SAMPLES)
		terrain.free()

	for biome_name_v: Variant in biome_enum:
		var biome_name: String = biome_name_v
		var value: int = int(biome_enum[biome_name])
		var n: Dictionary = near.get(value, {})
		var f: Dictionary = far.get(value, {})
		if int(n.get("chunks", 0)) < NEAR_SAMPLES:
			_fail("only %d NEAR chunks of biome %s were found (wanted %d) over %d seeds in a %dx%d sweep — "
					% [int(n.get("chunks", 0)), biome_name, NEAR_SAMPLES, SEEDS.size(), 2 * NEAR_SWEEP + 1, 2 * NEAR_SWEEP + 1]
					+ "that biome's gradient is unmeasured, not proven")
			continue
		if int(f.get("chunks", 0)) < FAR_SAMPLES:
			_fail("only %d FAR chunks of biome %s were found (wanted %d) over %d seeds in a %dx%d sweep — "
					% [int(f.get("chunks", 0)), biome_name, FAR_SAMPLES, SEEDS.size(), 2 * FAR_SWEEP + 1, 2 * FAR_SWEEP + 1]
					+ "that biome's gradient is unmeasured, not proven")
			continue

		# NEAR — the control. Without it "far is empty" says nothing at all.
		var near_total: int = int(n.get("props", 0)) + int(n.get("biome", 0)) + int(n.get("features", 0))
		if near_total == 0:
			_fail("scarcity: the NEAR field of biome %s builds nothing at all (k ~ 0.6) — " % biome_name
					+ "the control is vacuous, so the far field's emptiness proves nothing")

		# FAR — everything that is not a massif.
		if int(f.get("props", 0)) != 0:
			_fail("scarcity: the FAR field of biome %s builds %d scattered-prop boxes beyond %d m — "
					% [biome_name, int(f.get("props", 0)), int(float(consts["SCARCITY_PLAIN_DISTANCE"]))]
					+ "the prop scatter's roundi(target * k) is not being applied")
		if int(f.get("features", 0)) != 0:
			_fail("scarcity: the FAR field of biome %s still rolls %d artifacts/camps/chests/landmarks — "
					% [biome_name, int(f.get("features", 0))]
					+ "a rarity roll must be compared against chance * k")
		if value == mountain_value:
			# The exemption, measured rather than assumed.
			if int(f.get("biome", 0)) == 0:
				_fail("scarcity: the FAR MOUNTAIN field builds no biome boxes — massifs are "
						+ "EXEMPT from the gradient (owner ruling 2026-09-04) and a far "
						+ "mountain band without them is a plains band painted grey")
		elif int(f.get("biome", 0)) != 0:
			_fail("scarcity: the FAR field of biome %s builds %d biome-content boxes beyond the plain "
					% [biome_name, int(f.get("biome", 0))]
					+ "distance — some builder in that band is not reading k (the whole of bead bn8)")

	var line := "  per-biome "
	for biome_name_v2: Variant in biome_enum:
		var bn: String = biome_name_v2
		var v: int = int(biome_enum[bn])
		line += "%s near %d/far %d  " % [
			bn,
			int(near.get(v, {}).get("props", 0)) + int(near.get(v, {}).get("biome", 0)),
			int(far.get(v, {}).get("props", 0)) + int(far.get(v, {}).get("biome", 0)),
		]
	print(line.strip_edges())
	Sentinel.done("every_biome")


func _sweep(terrain: Node3D, centre: Vector3, into: Dictionary, want_zero_k: bool, sweep: int, cap: int) -> void:
	"""
	Build up to `cap` chunks of each biome around `centre` and accumulate
	their box / feature counts into `into`, keyed by biome value.

	@param want_zero_k: true for the FAR field — take only chunks whose k is
	                    EXACTLY 0; false for the NEAR field, which takes only
	                    chunks whose k is not. Asked of `scarcity_at` per chunk,
	                    never inferred from the sweep's geometry: the square is
	                    2.2 km wide and the plain distance is 4 km, so a centre
	                    chosen by eye puts thinned-but-not-empty chunks in the far
	                    field, which reads as "seven biomes forgot k".

	Budapest's own chunks are skipped: the city is authored, `in_budapest` turns
	every one of these spawners off inside the rect, and its chunks are all at
	k = 1 anyway. Neither field goes near it, so this is belt and braces.
	"""
	var origin: Vector2i = terrain.world_to_chunk(centre)
	for cx in range(-sweep, sweep + 1):
		for cz in range(-sweep, sweep + 1):
			var chunk: Vector2i = origin + Vector2i(cx, cz)
			var world: Vector3 = terrain.chunk_to_world(chunk)
			if terrain.in_budapest(world.x, world.z):
				continue
			if (float(terrain.scarcity_at(world)) == 0.0) != want_zero_k:
				continue
			var biome: int = int(terrain.biome_at(world.x, world.z))
			var row: Dictionary = into.get(biome, {"chunks": 0, "props": 0, "biome": 0, "features": 0})
			if int(row["chunks"]) >= cap:
				continue

			var prop_batch: Array = []
			var prop_body := StaticBody3D.new()
			var platforms: Array = []
			var obstacles: Array = terrain.spawn_objects_in_chunk(chunk, platforms, prop_batch, prop_body)
			prop_body.free()

			var biome_batch: Array = []
			var biome_body := StaticBody3D.new()
			terrain.spawn_biome_content_in_chunk(chunk, obstacles, biome_batch, biome_body)
			biome_body.free()

			var features := 0
			for fn: String in ["_artifact_at", "_camp_at", "_chest_at", "_landmark_at"]:
				var d: Dictionary = terrain.call(fn, chunk)
				if not d.is_empty():
					features += 1

			row["chunks"] = int(row["chunks"]) + 1
			row["props"] = int(row["props"]) + prop_batch.size()
			row["biome"] = int(row["biome"]) + biome_batch.size()
			row["features"] = int(row["features"]) + features
			into[biome] = row


# ============================================================================
# CHECK 3 — what must never thin
# ============================================================================

func _check_never_thinned() -> void:
	"""
	PREDATORS, HUNTERS, BOSSES AND ROAD COINS ARE NOT DECORATION.

	Owner ruling 2026-09-04 (bead `godot-test1-bn8`): the gradient exists to
	demotivate walking away from Budapest, so thinning the DANGER out there would
	reward exactly what it is meant to discourage — and the coin road is the guide
	to the city, which is the one thing a lost player has left.

	READ AS TEXT, because that is the assertion a future edit cannot slip past. A
	behavioural count can only speak for the chunks it sampled, and the road's own
	coins stop at the terminal station `T` (inside the union by construction), so
	there is nowhere 4 km out where a road coin could be counted at all — the road
	has no far field to measure. The text says `scarcity_at` appears in none of
	those function bodies, full stop.

	The predators DO get a real count on top, and the direction asserted is UP:
	`spawn_crocodiles_in_chunk`'s target widens with |chunk.x| (the difficulty
	gradient), so a far field must carry AT LEAST as many bodies as a near one.
	`>=` rather than `==` is the honest relation — "unchanged" was never true here
	and a check that demanded it would fail on the shipped difficulty curve.
	"""
	var source: String = FileAccess.get_file_as_string(TERRAIN_SCRIPT)
	if source.is_empty():
		_fail("could not read %s as text — check 3 cannot run" % TERRAIN_SCRIPT)
		Sentinel.done("never_thinned")
		return
	for fn: String in NEVER_THINNED:
		var body := _function_body(source, fn)
		if body.is_empty():
			_fail("check 3 found no function `%s` in endless_terrain.gd — it was renamed or " % fn
					+ "removed, and this assertion is now measuring nothing")
			continue
		for forbidden: String in ["scarcity_at(", "_scarcity_keep("]:
			if body.contains(forbidden):
				_fail("`%s` calls %s — predators, hunters, bosses and the coin road are NEVER " % [fn, forbidden]
						+ "thinned by distance (owner ruling 2026-09-04): fewer predators far "
						+ "out rewards leaving, and the road is the guide to Budapest")

	# ...and the behavioural half: a far field carries at least as many predators
	# as a near one. Built through the real spawner with the real scene, so a
	# thinning that lived in the placement loop rather than in a `scarcity_at`
	# call is caught too.
	var terrain := Node3D.new()
	terrain.set_script(load(TERRAIN_SCRIPT) as GDScript)
	terrain.set_run_seed(20260904)
	terrain.crocodile_scene = load(CROC_SCENE)
	var near_count := _count_predators(terrain, NEAR_CENTRE)
	var far_count := _count_predators(terrain, FAR_CENTRE)
	terrain.free()
	if far_count == 0:
		_fail("the FAR field spawned 0 predators — the field beyond 4 km must still be dangerous "
				+ "(and a zero here makes the comparison below vacuous)")
	elif far_count < near_count:
		_fail("the FAR field spawned %d predators against the NEAR field's %d — predator counts "
				% [far_count, near_count]
				+ "must never fall with distance; the difficulty gradient only widens them")
	print("  never thin %d spawners carry no scarcity term; predators near %d, far %d (must not fall)"
			% [NEVER_THINNED.size(), near_count, far_count])
	Sentinel.done("never_thinned")


func _count_predators(terrain: Node3D, centre: Vector3) -> int:
	"""Spawn a small field of chunks around `centre` and count the bodies."""
	var origin: Vector2i = terrain.world_to_chunk(centre)
	var total := 0
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			var chunk: Vector2i = origin + Vector2i(cx, cz)
			var parent := MeshInstance3D.new()
			parent.position = terrain.chunk_to_world(chunk)
			terrain.spawn_crocodiles_in_chunk(chunk, parent, [])
			total += parent.get_child_count()
			parent.free()
	return total


func _function_body(source: String, name: String) -> String:
	"""
	The lines of `func <name>(...)` up to the next top-level `func`, or "" when
	there is no such function. Crude on purpose: GDScript's one-function-per-
	column-0-`func` layout is the whole grammar this needs, and a parser would be
	a second thing to keep right.
	"""
	var lines: PackedStringArray = source.split("\n")
	var out: PackedStringArray = PackedStringArray()
	var inside := false
	for line: String in lines:
		if line.begins_with("func " + name + "("):
			inside = true
			continue
		if inside:
			if line.begins_with("func "):
				break
			out.append(line)
	return "\n".join(out)
