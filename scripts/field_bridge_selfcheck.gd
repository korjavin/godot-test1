extends SceneTree
## ============================================================================
## FIELD BRIDGE SELF-CHECK (bead godot-test1-06o.2)
## ============================================================================
##
## Run headless:
##     godot --headless --path . --script res://scripts/field_bridge_selfcheck.gd
## Prints "SELFCHECK OK" and exits 0, or prints every failure and exits 1.
##
## WHY THIS EXISTS: the rivers epic is about to make a river's centre NOT
## WALKABLE (bead godot-test1-06o.3). The coin road is the route the game asks
## you to follow, and it has crossed rivers by wading since the day it was
## written — so from that ruling on, THESE BRIDGES ARE THE ONLY THING KEEPING A
## RUN CROSSABLE. Every failure mode here is a softlock nobody would see until a
## player walked into a river 900 m out and could not get to the other side:
##
##   1. A crossing with NO bridge. Check 1 walks the road station by station on
##      several seeds and asks the shipped predicate at every one.
##   2. A bridge with a HOLE in it — a slab that a chunk seam swallowed, or a
##      wedge of open air at the outer parapet of a turn (the road turns up to
##      18 degrees a station, and two abutting slabs do not cover a turn). Check
##      2 walks the surface metre by metre in three lanes against the boxes the
##      chunks REALLY build, not against the plan.
##   3. A ramp too steep to walk up, or a STEP where a slab overhangs one. A step
##      is the one thing CharacterBody3D cannot climb at all, so it is a jump
##      gate outdoors, which is the same rule the HQ's interior is held to. Check
##      3 measures the built stone against TowerInterior.PLAN_RAMP_MAX_SLOPE.
##   4. An ABUTMENT IN THE WATER — a ramp whose foot is wet is a bridge you have
##      to wade to. Check 4, with the mid-span as its wet control.
##   5. A deck that is DRY IN THE PLAN AND WET UNDER THE FEET. The Y-aware wade
##      is a one-line clause in three files; check 7 drives a REAL player.tscn
##      across a REAL deck metre by metre, with two controls — a metre off the
##      parapet, and the same walk with the bridges switched off.
##
## And two contract checks that are not about softlocks: check 5 (the deck is
## narrower than every road clearance in the file, so no prop can ever stand on
## one) and check 6 (the A/B — with the feature off, every crocodile, hunter,
## boss, prop and landmark in the chunk is byte-identical, and the road's coins
## move in Y and only in Y).
##
## Deliberately NOT localized (a debug surface, per CLAUDE.md).

const TERRAIN_SCRIPT: GDScript = preload("res://scripts/endless_terrain.gd")
const CROC_SCENE: String = "res://scenes/characters/piglet_crocodile.tscn"
const COIN_SCENE: String = "res://scenes/collectibles/coin.tscn"
const PLAYER_SCENE: String = "res://scenes/player.tscn"

## Seeds check 1 walks the whole road on. Arbitrary, fixed, and different from
## every other check's list in the project — between them the road is asked
## about a lot more than one river.
## 72 is not arbitrary: its road walks 84 m of water through a bend whose CHORD
## is only 79.2 m, so it is the world where "the cap is metres walked" and "the
## cap is the straight line across" give different answers — see check 1.
const CROSSING_SEEDS: Array[int] = [11, 2027, 90210, 777001, 424243, 8, 131313,
		606060, 5150, 99991, 31337, 271828, 72]

## The walk must actually MEET rivers, or check 1 is a green lie about a road
## that never got its feet wet. Measured today: 40+ crossings over the 12 seeds.
const MIN_CROSSINGS: int = 8

## Metre / m-per-second slop. Everything measured here is decimetres or bigger.
const EPS: float = 0.01

## The deck's walking height, read from the file that owns it.
const FIELD_TOP: float = TERRAIN_SCRIPT.FIELD_BRIDGE_TOP

## Physics frames allowed for the player to fall onto a deck and settle.
const SETTLE_FRAMES: int = 40

var _failures: Array[String] = []

## THE END-OF-CHECK SENTINEL — see scripts/selfcheck_sentinel.gd. Every check
## stamps itself at its exit and the report site asks whether every stamp was
## reached, because a GDScript runtime error aborts only the function it lands
## in and lets this file print "SELFCHECK OK" over the wreckage.
const Sentinel := preload("res://scripts/selfcheck_sentinel.gd")


## A forwarder that puts the SHIPPED wading rule in the "terrain" group without
## putting a whole world-engine node in the tree.
##
## The player asks `get_tree().get_first_node_in_group("terrain")` for
## `is_wading_at`; a real EndlessTerrain in the tree would start streaming chunks
## around a player this check is deliberately teleporting around a bridge. So the
## group holds this, and it answers by CALLING THE REAL TERRAIN — the rule under
## test is `endless_terrain.is_wading_at` itself, not a stub's idea of it.
class TerrainProxy:
	extends Node
	var real: Node = null
	func is_wading_at(pos: Vector3) -> bool:
		return real.is_wading_at(pos)
	func is_river_at(pos: Vector3) -> bool:
		return real.is_river_at(pos)


func _initialize() -> void:
	Sentinel.isolate_user_state()
	# _initialize() cannot await, so the measuring half runs as its own coroutine
	# and reports from in there — reporting here would print a verdict at frame 0.
	_run()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		Sentinel.finish(self)
	else:
		for line: String in _failures:
			printerr("FAIL: %s" % line)
		printerr("SELFCHECK FAILED (%d)" % _failures.size())
		quit(1)


func _frames(n: int) -> void:
	for _i in n:
		await physics_frame


func _run() -> void:
	# ONE FRAME FIRST, and it is not a nicety: a node added to `root` from
	# _initialize() is not `is_inside_tree()` until the tree has ticked once, and
	# a chunk harness that generates a TREASURE CHEST hands its `setup()` a node
	# with no tree — `global_position` returns identity and the group lookup
	# errors out. Every check below builds real chunks.
	await _frames(1)
	_check_every_crossing_is_bridged()
	_check_the_stone_covers_the_walk()
	_check_slope()
	_check_abutments_are_dry()
	_check_deck_fits_every_clearance()
	_check_ab_against_the_feature_off()
	_check_deck_coins_stand_on_stone()
	await _check_the_crossing_is_dry_underfoot()
	_report()


# ----------------------------------------------------------------------------
# Harness
# ----------------------------------------------------------------------------

func _terrain(run_seed: int) -> Node3D:
	"""A terrain node with its seed forced and the scenes a chunk needs loaded."""
	var terrain := Node3D.new()
	terrain.set_script(TERRAIN_SCRIPT)
	terrain.set_run_seed(run_seed)
	terrain.crocodile_scene = load(CROC_SCENE)
	terrain.coin_scene = load(COIN_SCENE)
	return terrain


func _first_bridge(terrain: Node3D, seed_hint: int) -> Dictionary:
	"""
	The westmost bridge on this road, or {} when the seed's road crosses nothing.

	@param seed_hint: only for the failure message.

	Walks FORWARD from station 1 to the terminal, asking the shipped
	field_bridge_at at every one — the same question every chunk asks.
	"""
	terrain._road_extend_to_x(0.0, TERRAIN_SCRIPT.ROAD_TERMINAL_X)
	var terminal: int = terrain._road_terminal_k()
	for k in range(2, terminal):
		var row: Dictionary = terrain.field_bridge_at(k)
		if not row.is_empty():
			return row
	return {}


func _bridge_boxes(terrain: Node3D, row: Dictionary) -> Array:
	"""
	Every box the CHUNKS really build for one bridge, in WORLD space.

	@return Array of { "xform": Transform3D (world), "chunk": Vector2i }.

	Each candidate chunk is generated on its own through the shipped
	spawn_field_bridges_in_chunk and its entries are lifted into world space by
	the chunk's origin — which is what makes "the centre rule kept every piece
	exactly once" measurable: a piece dropped by every chunk is a hole, and a
	piece kept by two is a duplicate.
	"""
	var poly: PackedVector2Array = row["poly"]
	var half: float = row["half"]
	var seen: Dictionary = {}
	var boxes: Array = []
	# Every chunk within a deck-width of the walking line, plus a chunk of margin
	# for the slab stretch — a superset, so nothing the builder emits is missed.
	for p in poly:
		var c0: Vector2i = terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))
		var span := ceili((half + terrain.chunk_size) / terrain.chunk_size)
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				var cp := c0 + Vector2i(dx, dz)
				if seen.has(cp):
					continue
				seen[cp] = true
				var origin: Vector3 = terrain.chunk_to_world(cp)
				var batch: Array = []
				var body := StaticBody3D.new()
				terrain.spawn_field_bridges_in_chunk(cp, batch, body)
				for entry_v: Variant in batch:
					var entry: Dictionary = entry_v
					var xf: Transform3D = entry["transform"]
					var world: Vector3 = xf.origin + origin
					# A chunk near one bridge can hold a slice of the NEXT one:
					# keep only the pieces standing on THIS walking line, so
					# "built exactly once" and "no stone off the parapet" stay
					# statements about one bridge.
					if terrain._field_bridge_surface_on(row,
							Vector3(world.x, 0.0, world.z)) <= -INF:
						continue
					boxes.append({
						"xform": Transform3D(xf.basis, world),
						"chunk": cp,
					})
				body.free()
	return boxes


func _covered(boxes: Array, point: Vector3) -> bool:
	"""
	Is this world point inside one of the built boxes?

	A batch entry's basis is the box's rotation SCALED BY ITS DIMENSIONS, so the
	inverse transform maps a world point into the unit cube — one affine_inverse
	per box and no trigonometry, and it is exactly as true of a tilted ramp slab
	as of a flat deck.
	"""
	for box_v: Variant in boxes:
		var box: Dictionary = box_v
		var xf: Transform3D = box["xform"]
		var local: Vector3 = xf.affine_inverse() * point
		# 0.5 is the unit cube's face; the slop is the terrain's EDGE_EPS in the
		# box's own local units, so "on the face" reads the same here as it does
		# in the shipped query.
		if absf(local.x) <= 0.502 and absf(local.y) <= 0.502 and absf(local.z) <= 0.502:
			return true
	return false


func _walk(row: Dictionary, step: float) -> Array:
	"""
	Sample the walking line every `step` metres.

	@return Array of { "pos": Vector2 (world XZ), "s": float (distance along),
	                   "perp": Vector2 (unit normal) }.
	"""
	var poly: PackedVector2Array = row["poly"]
	var along: PackedFloat32Array = row["along"]
	var total: float = along[along.size() - 1]
	var out: Array = []
	var s := 0.0
	while s <= total:
		# Which segment this distance lands on.
		var i := 0
		while i < along.size() - 2 and along[i + 1] < s:
			i += 1
		var a: Vector2 = poly[i]
		var seg: Vector2 = poly[i + 1] - a
		var t: float = 0.0 if seg.length() <= 0.0 else (s - along[i]) / seg.length()
		var p: Vector2 = a + seg * clampf(t, 0.0, 1.0)
		var dir: Vector2 = seg.normalized()
		out.append({ "pos": p, "s": s, "perp": Vector2(-dir.y, dir.x) })
		s += step
	return out


# ============================================================================
# CHECK 1 — every river crossing on the road gets exactly one bridge
# ============================================================================

func _check_every_crossing_is_bridged() -> void:
	"""
	THE SOFTLOCK CHECK. Walk every station of the road from the spawn to the
	terminal station on CROSSING_SEEDS worlds; every station that ENTERS the
	water (wet here, dry behind) must anchor exactly one bridge, unless the water
	runs on past FIELD_BRIDGE_MAX_SPAN — which is the documented lake case, and
	which is counted and printed rather than silently allowed.

	It also asserts the converse, which is what makes "exactly one" mean
	something: NO station that is not a crossing entry may anchor a bridge, so
	two bridges can never be built over one river.

	Driven entirely on the shipped `_field_bridge_wet` / `field_bridge_at`, so a
	retune of the probe or of the entry rule is measured rather than mirrored.
	"""
	var crossings := 0
	var bridged := 0
	var lakes := 0
	var curved := 0
	var worst := ""

	for run_seed in CROSSING_SEEDS:
		var terrain := _terrain(run_seed)
		terrain._road_extend_to_x(0.0, TERRAIN_SCRIPT.ROAD_TERMINAL_X)
		var terminal: int = terrain._road_terminal_k()
		var prev_wet: bool = terrain._field_bridge_wet(1)
		for k in range(2, terminal - 1):
			var wet: bool = terrain._field_bridge_wet(k)
			var row: Dictionary = terrain.field_bridge_at(k)
			var entry := wet and not prev_wet
			prev_wet = wet
			if not entry:
				if not row.is_empty() and worst == "":
					worst = ("seed %d station %d anchors a bridge but is not a"
							% [run_seed, k] + " crossing ENTRY (wet here: %s) —"
							% wet + " two decks can now cover one river")
					_fail(worst)
				continue
			crossings += 1
			if not row.is_empty():
				bridged += 1
				# THE CAP IS METRES WALKED, not the chord back to the entry —
				# a curved wet run is longer than the straight line across it,
				# and the chord let a crossing over the cap through (seed 72).
				var span_walked := 0.0
				var span_chord: float = terrain._road_station(int(row["k0"])).center \
						.distance_to(terrain._road_station(int(row["k1"])).center)
				for j in range(int(row["k0"]), int(row["k1"])):
					span_walked += terrain._road_station(j + 1).center.distance_to(
							terrain._road_station(j).center)
				if span_walked > TERRAIN_SCRIPT.FIELD_BRIDGE_MAX_SPAN + EPS:
					_fail("seed %d station %d is bridged over %.1f m of WALKED"
							% [run_seed, k, span_walked] + " water, past the"
							+ " %.0f m cap (its chord is only %.1f m — the cap"
							% [TERRAIN_SCRIPT.FIELD_BRIDGE_MAX_SPAN, span_chord]
							+ " must measure the road, not the straight line)")
				if span_walked > span_chord + 0.5:
					curved += 1
				continue
			# No bridge: the only sanctioned reason is the span cap. Measure the
			# water the road walks from here and hold the refusal to it.
			# MEASURED THE WAY THE SHIPPED CAP MEASURES — metres WALKED. Asking
			# the chord here is the same bug one level up: it reported seed 72's
			# 84 m crossing as 79.2 m and then failed the build for refusing it.
			var j := k
			var wide := false
			var water := 0.0
			while j < terminal - 1 and terrain._field_bridge_wet(j + 1):
				j += 1
				water += terrain._road_station(j).center.distance_to(
						terrain._road_station(j - 1).center)
				if water > TERRAIN_SCRIPT.FIELD_BRIDGE_MAX_SPAN:
					wide = true
					break
			if wide:
				lakes += 1
				continue
			if worst == "":
				worst = ("seed %d: the road enters the water at station %d and"
						% [run_seed, k] + " walks %.1f m of it, well inside the"
						% water
						+ " %.0f m cap — and there is NO BRIDGE. That crossing is"
						% TERRAIN_SCRIPT.FIELD_BRIDGE_MAX_SPAN
						+ " a softlock the day rivers stop being walkable")
				_fail(worst)
		terrain.free()

	print("field bridges: %d road river crossings over %d seeds — %d bridged, %d"
			% [crossings, CROSSING_SEEDS.size(), bridged, lakes]
			+ " over the %.0f m span cap (wade, by design); %d of the bridged"
					% [TERRAIN_SCRIPT.FIELD_BRIDGE_MAX_SPAN, curved]
			+ " really curve (walked > chord)")

	if crossings < MIN_CROSSINGS:
		_fail("check 1 found only %d road river crossings over %d seeds (wanted"
				% [crossings, CROSSING_SEEDS.size()]
				+ " >= %d) — it is not measuring what it claims to" % MIN_CROSSINGS)
	if bridged < 1:
		_fail("check 1 bridged NOTHING — every crossing it found was written off"
				+ " as a lake, so no geometry was ever built")
	if curved < 1:
		_fail("not one bridged crossing is CURVED (walked > chord) over %d seeds"
				% CROSSING_SEEDS.size() + " — the walked-vs-chord assertion above"
				+ " is true of a straight road and measures nothing")
	Sentinel.done("every_crossing_is_bridged")


# ============================================================================
# CHECK 2 — the stone the chunks build really covers the walk
# ============================================================================

func _check_the_stone_covers_the_walk() -> void:
	"""
	THE PLAN IS NOT THE STONE. `field_bridge_surface_y` answers a nice continuous
	profile whatever the chunks did, so a slab dropped at a seam by the centre
	rule, or a wedge of open air at the outer parapet of a turn, is invisible to
	every plan-level assertion in this file.

	So: build every chunk the bridge touches through the shipped
	spawn_field_bridges_in_chunk, and walk the surface METRE BY METRE in THREE
	LANES — the centreline and both parapets — asking whether there is stone
	immediately under the walking height. Budapest's check 14 measures its four
	decks the same way and for the same reason.

	Three more properties fall out of the same box list:
	  * every piece is SMALLER THAN A CHUNK (the centre rule is only safe for a
	    box a chunk can contain — budapest_selfcheck check 5's rule);
	  * no piece is built TWICE (the half-open centre rule);
	  * a metre outside the parapet there is NO stone, which is the control that
	    keeps the coverage sweep from passing on a slab the width of the world.
	"""
	var terrain := _terrain(CROSSING_SEEDS[0])
	var row := _first_bridge(terrain, CROSSING_SEEDS[0])
	if row.is_empty():
		_fail("check 2 found no bridge at all on seed %d — nothing to measure"
				% CROSSING_SEEDS[0])
		terrain.free()
		Sentinel.done("stone_covers_the_walk")
		return

	var boxes := _bridge_boxes(terrain, row)
	var half: float = row["half"]
	var chunk: float = terrain.chunk_size

	# Every piece fits inside a chunk, and no two pieces are the same piece.
	var seen: Dictionary = {}
	for box_v: Variant in boxes:
		var box: Dictionary = box_v
		var xf: Transform3D = box["xform"]
		var size := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
		if size.x > chunk or size.z > chunk:
			_fail("a field bridge box is %.1f x %.1f m, bigger than the %.0f m"
					% [size.x, size.z, chunk] + " chunk that owns it by the CENTRE"
					+ " rule — it will vanish at the residency edge (the rule"
					+ " budapest_selfcheck check 5 states)")
			break
		var key := "%.3f|%.3f|%.3f" % [xf.origin.x, xf.origin.y, xf.origin.z]
		if seen.has(key):
			_fail("two chunks (%s and %s) both built the bridge piece at %s — the"
					% [seen[key], box["chunk"], key]
					+ " centre rule must be half-open on both axes")
			break
		seen[key] = box["chunk"]

	var holes := 0
	var worst := ""
	# THE FULL WIDTH, not a metre inside it: the parapet lane is where a foot
	# corner in the water was found (check 4), and a coverage sweep that stops a
	# metre short cannot see a slab that is narrower than the plan says.
	var lanes: Array[float] = [0.0, half - 0.1, -(half - 0.1)]
	for sample_v: Variant in _walk(row, 1.0):
		var sample: Dictionary = sample_v
		var p: Vector2 = sample["pos"]
		var perp: Vector2 = sample["perp"]
		for lane in lanes:
			var at := Vector2(p.x + perp.x * lane, p.y + perp.y * lane)
			var surface: float = terrain.field_bridge_surface_y(
					Vector3(at.x, 0.0, at.y))
			if surface <= -INF:
				_fail("the plan says there is no bridge %.1f m off the walking"
						% lane + " line at s = %.1f, but that is inside the deck"
						% float(sample["s"]))
				break
			# Just under the walking surface: stone here means the deck is solid
			# AND at the height the plan promises. Both halves of "flush".
			var probe := Vector3(at.x, surface - 0.05, at.y)
			if _covered(boxes, probe):
				continue
			holes += 1
			if worst == "":
				worst = ("no stone under the walking surface at s = %.1f m, lane"
						% float(sample["s"]) + " %.1f m, world (%.1f, %.1f),"
						% [lane, at.x, at.y] + " surface %.2f m" % surface)

	# THE CONTROL: a metre outside the parapet is open water, not deck.
	var mid: Dictionary = _walk(row, 1.0)[int(_walk(row, 1.0).size() / 2)]
	var mp: Vector2 = mid["pos"]
	var mperp: Vector2 = mid["perp"]
	var off := Vector3(mp.x + mperp.x * (half + 1.0), TERRAIN_SCRIPT.FIELD_BRIDGE_TOP - 0.05,
			mp.y + mperp.y * (half + 1.0))
	if _covered(boxes, off):
		_fail("there is deck stone a metre OUTSIDE the parapet — check 2's"
				+ " coverage sweep would pass on a slab of any width")

	print("field bridges: %d boxes over the first bridge on seed %d, %d holes in"
			% [boxes.size(), CROSSING_SEEDS[0], holes]
			+ " a 3-lane metre-by-metre walk of %.1f m" % float(row["along"][row["along"].size() - 1]))
	if holes > 0:
		_fail("%d sample(s) of the bridge's walking surface have NO stone under"
				% holes + " them — the deck has holes in it. First: %s" % worst)
	terrain.free()
	Sentinel.done("stone_covers_the_walk")


# ============================================================================
# CHECK 3 — nothing on a bridge demands a jump
# ============================================================================

func _check_slope() -> void:
	"""
	NO TRAVERSAL OUTDOORS MAY DEMAND A JUMP-HEIGHT — the HQ interior's rule, and
	the one Budapest's approach ramps are held to. Two ways it can break here and
	both are measured off the SAMPLED SURFACE rather than off a constant:

	  * the ramp is too steep (retune FIELD_BRIDGE_TOP and forget the run);
	  * there is a STEP, which is worse — CharacterBody3D cannot climb a step at
	    all, so a slab overhanging the head of a ramp by the slab stretch is a
	    37 cm wall you cannot get back up. A step reads here as a slope of
	    infinity between two 10 cm samples.

	The ceiling is TowerInterior.PLAN_RAMP_MAX_SLOPE, READ from the file that
	owns it. NEGATIVE CONTROL: the same measurement over the same profile with
	the run halved must fail it, so a measurement that silently answered zero
	could not pass.
	"""
	var ceiling: float = TowerInterior.PLAN_RAMP_MAX_SLOPE
	var terrain := _terrain(CROSSING_SEEDS[0])
	var row := _first_bridge(terrain, CROSSING_SEEDS[0])
	if row.is_empty():
		_fail("check 3 found no bridge on seed %d" % CROSSING_SEEDS[0])
		terrain.free()
		Sentinel.done("slope")
		return

	# The profile as (distance along, height) pairs, sampled at 10 cm — fine
	# enough that a STEP shows up as one enormous slope between two samples.
	var profile: Array = []
	for sample_v: Variant in _walk(row, 0.1):
		var sample: Dictionary = sample_v
		var p: Vector2 = sample["pos"]
		profile.append(Vector2(float(sample["s"]),
				terrain.field_bridge_surface_y(Vector3(p.x, 0.0, p.y))))

	var measured := _max_slope(profile)
	print("field bridges: steepest sampled slope %.3f at s = %.1f m against"
			% [measured.y, measured.x] + " TowerInterior.PLAN_RAMP_MAX_SLOPE %.3f"
			% ceiling)
	if measured.y > ceiling + EPS:
		_fail("a field bridge climbs at %.3f (at s = %.1f m), steeper than"
				% [measured.y, measured.x] + " TowerInterior.PLAN_RAMP_MAX_SLOPE"
				+ " %.3f — that is a jump gate outdoors" % ceiling)

	# THE NEGATIVE CONTROL, and it is the failure that actually threatens this
	# feature: not a steeper ramp but a STEP. One sample raised by the slab
	# thickness is exactly what a deck overhanging the head of a ramp looks like,
	# and the measurement above must refuse it.
	var mutant: Array = profile.duplicate()
	var at_index := int(mutant.size() / 3)
	mutant[at_index] = Vector2(mutant[at_index].x,
			mutant[at_index].y + TERRAIN_SCRIPT.FIELD_BRIDGE_THICKNESS)
	if _max_slope(mutant).y <= ceiling:
		_fail("check 3's control is inert: a %.2f m STEP in the middle of the"
				% TERRAIN_SCRIPT.FIELD_BRIDGE_THICKNESS + " deck measures as"
				+ " %.3f, still under the %.3f ceiling — the assertion above"
				% [_max_slope(mutant).y, ceiling] + " cannot fail")
	terrain.free()
	Sentinel.done("slope")


func _max_slope(profile: Array) -> Vector2:
	"""
	The steepest rise between two consecutive samples of a walking profile.

	@param profile: Array of Vector2(distance along, height).
	@return Vector2(distance where it was measured, the slope itself).

	Its own function so check 3 can run it over a DELIBERATELY BROKEN copy of the
	same profile — a measurement with no mutation control is a measurement that
	can quietly start answering zero.
	"""
	var worst := Vector2(0.0, 0.0)
	for i in range(1, profile.size()):
		var run: float = maxf(profile[i].x - profile[i - 1].x, 0.0001)
		var slope: float = absf(profile[i].y - profile[i - 1].y) / run
		if slope > worst.y:
			worst = Vector2(profile[i].x, slope)
	return worst


# ============================================================================
# CHECK 4 — both abutments stand on dry land
# ============================================================================

func _check_abutments_are_dry() -> void:
	"""
	A ramp whose foot is in the water is a bridge you have to wade to, which is
	the whole feature undone. Both feet of EVERY bridge on every seed are asked of
	the shipped `is_river_at` — the XZ band, deliberately, because this is a
	question about the GROUND and not about a body.

	BOTH CORNERS, NOT THE CENTRELINE POINT, and that is the assertion the fix is
	measured by: an abutment is a 16 m wide slab at y = 0, so a corner of it can
	stand in the water while its centre is dry — and a player walking up that
	flank keeps wading until the ramp has risen past WADE_SURFACE_MAX (found on
	seed 12, station 116). `_field_bridge_foot` pushes the foot back until all
	three probes are dry; this walks every foot in twelve worlds and asks.

	TWO CONTROLS. The mid-span must be WET, or "the feet are dry" is true of a
	world with no rivers in it; and the push must have FIRED somewhere, or the
	corner probe is decoration that never moved a foot.
	"""
	var measured := 0
	var wet_controls := 0
	var pushes := 0
	var longest := 0.0
	for run_seed in CROSSING_SEEDS:
		var terrain := _terrain(run_seed)
		for row_v: Variant in _all_bridges(terrain):
			var row: Dictionary = row_v
			measured += 1
			var poly: PackedVector2Array = row["poly"]
			var half_w: float = row["half"]
			for end in [0, poly.size() - 1]:
				var deck_end: Vector2 = poly[1] if end == 0 else poly[poly.size() - 2]
				var foot: Vector2 = poly[end]
				var inward: Vector2 = (deck_end - foot).normalized()
				var perp := Vector2(-inward.y, inward.x) * half_w
				var ramp := foot.distance_to(deck_end)
				longest = maxf(longest, ramp)
				if ramp > _base_run() + EPS:
					pushes += 1
				for probe in [foot, foot + perp, foot - perp]:
					if terrain.is_river_at(Vector3(probe.x, 0.0, probe.y)):
						_fail("seed %d: a field bridge's abutment reaches"
								% run_seed + " (%.1f, %.1f), which is IN the"
								% [probe.x, probe.y] + " river — the whole WIDTH"
								+ " of a foot has to be on the bank")
			# ...and the control: the middle of the span is water.
			var samples := _walk(row, 1.0)
			var mp: Vector2 = samples[int(samples.size() / 2)]["pos"]
			if terrain.is_river_at(Vector3(mp.x, 0.0, mp.y)):
				wet_controls += 1
		terrain.free()

	print("field bridges: %d bridges measured for dry abutments — %d feet needed"
			% [measured, pushes] + " a push, longest ramp %.1f m (base %.1f, push"
					% [longest, _base_run()]
			+ " budget %.0f); %d span water at mid-point"
					% [TERRAIN_SCRIPT.FIELD_BRIDGE_FOOT_PUSH_MAX, wet_controls])
	if measured < 1:
		_fail("check 4 measured no bridge at all")
	if wet_controls < 1:
		_fail("check 4's wet control never fired: not one bridge's mid-point is"
				+ " in a river, so 'the feet are dry' is true of a dry world")
	if pushes < 1:
		_fail("not one abutment in %d bridges needed pushing back, so the corner"
				% measured + " probe in _field_bridge_foot has never moved a foot"
				+ " — the fix it is the assertion for is untested here")
	Sentinel.done("abutments_are_dry")


func _base_run() -> float:
	"""The ramp run before any push — the terrain's own derivation, not a number
	typed here (FIELD_BRIDGE_TOP over Budapest's deck slope)."""
	return TERRAIN_SCRIPT.FIELD_BRIDGE_TOP * BudapestPlan.BRIDGE_RAMP_RUN \
			/ BudapestPlan.BRIDGE_DECK_TOP


func _all_bridges(terrain: Node3D) -> Array:
	"""
	EVERY bridge on this road, west to east. The plan-level walk check 1 makes,
	kept as a helper because check 4 wants all of them and not just the first —
	twelve first bridges is twelve feet, and the corner rule is about ragged banks
	that only show up in numbers.
	"""
	terrain._road_extend_to_x(0.0, TERRAIN_SCRIPT.ROAD_TERMINAL_X)
	var out: Array = []
	for k in range(2, terrain._road_terminal_k()):
		var row: Dictionary = terrain.field_bridge_at(k)
		if not row.is_empty():
			out.append(row)
	return out


# ============================================================================
# CHECK 5 — a deck is narrower than every road clearance in the file
# ============================================================================

func _check_deck_fits_every_clearance() -> void:
	"""
	A deck has NO `obstacles` footprint (it is meant to be walked), so nothing
	downstream will move a prop out of its way. What keeps a cactus, a chest or a
	camp off a bridge is that every one of them is placed at least its own
	*_ROAD_CLEARANCE from the road centreline, and the deck reaches only
	FIELD_BRIDGE_HALF_WIDTH from it.

	ITERATED OFF THE CONSTANT MAP, never a list typed here: a new spawner with a
	tighter clearance than the deck's half-width is exactly the regression this
	is for, and it should fail the day that constant lands.
	"""
	var consts: Dictionary = TERRAIN_SCRIPT.get_script_constant_map()
	var half: float = float(consts["FIELD_BRIDGE_HALF_WIDTH"])
	var tightest := INF
	var tightest_name := ""
	for name_v: Variant in consts.keys():
		var name := String(name_v)
		if not name.ends_with("_ROAD_CLEARANCE"):
			continue
		var value: float = float(consts[name])
		if value < tightest:
			tightest = value
			tightest_name = name
	if tightest_name == "":
		_fail("check 5 found no *_ROAD_CLEARANCE constant in endless_terrain.gd —"
				+ " it is measuring nothing")
		Sentinel.done("deck_fits_every_clearance")
		return
	print("field bridges: deck half-width %.1f m against the tightest road"
			% half + " clearance %s = %.1f m" % [tightest_name, tightest])
	if half >= tightest:
		_fail("FIELD_BRIDGE_HALF_WIDTH %.1f m reaches at least as far as %s"
				% [half, tightest_name] + " (%.1f m), so that spawner can stand"
				% tightest + " something on a bridge deck")
	Sentinel.done("deck_fits_every_clearance")


# ============================================================================
# CHECK 6 — the A/B: nothing else in the world moved
# ============================================================================

func _check_ab_against_the_feature_off() -> void:
	"""
	THE DETERMINISM CLAIM, MEASURED. A field bridge takes not one draw from any
	stream anybody else reads — the site is the road's centreline plus the river
	field, both pure, and the boxes come off a private generator at a fixed seed.
	So with `spawn_field_bridges` off, a bridge's own chunks must regenerate:

	  * the same footprint list, the same bodies (crocodiles, hunters, bosses)
	    and the same batch, byte for byte, as a PREFIX of the bridged one — the
	    bridge's boxes are appended after everything else, so anything that moved
	    shows up as a prefix mismatch rather than as a diff nobody reads;
	  * the same coins in X and Z, differing in Y on exactly the coins that stand
	    on a deck — and at least one really does, or the coin rule is untested.

	Two regenerations of the same chunk are compared as well, which is the
	within-run half of the determinism contract (a revisited chunk is
	byte-identical).
	"""
	var run_seed: int = CROSSING_SEEDS[0]
	var terrain := _terrain(run_seed)
	var row := _first_bridge(terrain, run_seed)
	if row.is_empty():
		_fail("check 6 found no bridge on seed %d" % run_seed)
		terrain.free()
		Sentinel.done("ab_against_the_feature_off")
		return
	var poly: PackedVector2Array = row["poly"]
	var mid: Vector2 = poly[int(poly.size() / 2)]
	var chunk_pos: Vector2i = terrain.world_to_chunk(Vector3(mid.x, 0.0, mid.y))
	terrain.free()

	var on_a := _generate(run_seed, chunk_pos, true)
	var on_b := _generate(run_seed, chunk_pos, true)
	var off := _generate(run_seed, chunk_pos, false)

	if on_a["signature"] != on_b["signature"]:
		_fail("two regenerations of chunk %s disagree — a field bridge chunk is"
				% chunk_pos + " not deterministic")
	# ...and the same chunk on a terrain that WALKED THE WHOLE ROAD first. The
	# bridge table is memoized, and the one answer it must never remember is
	# "the station cache does not reach that far yet" — that is a fact about
	# which chunk the player reached first, and remembering it deletes a bridge
	# for the rest of the run. Two visit orders, one world.
	var walked := _generate(run_seed, chunk_pos, true, true)
	if walked["signature"] != on_a["signature"]:
		_fail("chunk %s comes out DIFFERENT on a terrain that walked the road"
				% chunk_pos + " first — the bridge memo is remembering how far"
				+ " the station cache had grown, not what the world is")
	walked["terrain"].free()
	if off["bridge_boxes"] != 0:
		_fail("spawn_field_bridges = false still built %d bridge box(es) — the"
				% off["bridge_boxes"] + " A/B switch does not switch")
	if on_a["bridge_boxes"] < 1:
		_fail("chunk %s holds no bridge box at all, so check 6's A/B compares"
				% chunk_pos + " two identical worlds")
	if on_a["obstacles"] != off["obstacles"]:
		_fail("the footprint list of chunk %s CHANGED when the bridges were"
				% chunk_pos + " switched on — a deck must append none")
	if on_a["bodies"] != off["bodies"]:
		_fail("the bodies in chunk %s changed when the bridges were switched on:"
				% chunk_pos + " %s vs %s" % [off["bodies"], on_a["bodies"]])
	var prefix: Array = on_a["batch"].slice(0, off["batch"].size())
	if prefix != off["batch"]:
		_fail("the non-bridge boxes of chunk %s moved when the bridges were"
				% chunk_pos + " switched on — the builder is drawing from a"
				+ " stream somebody else reads")

	# The coins: same XZ, and the ones on the deck are lifted onto it.
	var lifted := 0
	if on_a["coins"].size() != off["coins"].size():
		_fail("the road laid %d coins in chunk %s with the bridges on and %d"
				% [on_a["coins"].size(), chunk_pos, off["coins"].size()]
				+ " with them off — a deck may move a coin in Y, never drop one")
	else:
		for i in on_a["coins"].size():
			var a: Vector3 = on_a["coins"][i]
			var b: Vector3 = off["coins"][i]
			if not is_equal_approx(a.x, b.x) or not is_equal_approx(a.z, b.z):
				_fail("a road coin MOVED in XZ when the bridges were switched on"
						+ " (%s vs %s)" % [b, a])
				break
			if is_equal_approx(a.y, b.y):
				continue
			lifted += 1
			var world := Vector3(a.x, 0.0, a.z) \
					+ terrain_origin(chunk_pos)
			var surface: float = on_a["terrain"].field_bridge_surface_y(world)
			var want: float = surface + TERRAIN_SCRIPT.COIN_GROUND_HEIGHT
			if surface <= -INF or absf(a.y - want) > EPS:
				_fail("a lifted road coin sits at y = %.2f where the deck"
						% a.y + " surface says %.2f" % want)
				break
	print("field bridges: chunk %s — %d bridge boxes, %d road coin(s) lifted onto"
			% [chunk_pos, on_a["bridge_boxes"], lifted] + " the deck")
	on_a["terrain"].free()
	on_b["terrain"].free()
	off["terrain"].free()
	Sentinel.done("ab_against_the_feature_off")


var _origin_terrain: Node3D = null

func terrain_origin(chunk_pos: Vector2i) -> Vector3:
	"""chunk_to_world for a chunk, without holding a terrain node open for it."""
	if _origin_terrain == null:
		_origin_terrain = _terrain(1)
	return _origin_terrain.chunk_to_world(chunk_pos)


func _generate(run_seed: int, chunk_pos: Vector2i, bridges: bool,
		walk_first: bool = false) -> Dictionary:
	"""
	Generate one chunk through create_chunk's own spawner sequence.

	@return { terrain, batch (Array[PackedByteArray]), bridge_boxes, obstacles
	          (PackedByteArray), bodies (Array[String]), coins (Array[Vector3]),
	          signature (PackedByteArray) }. THE CALLER FREES `terrain`.

	The sequence is create_chunk's, bridges included in their real position (with
	the city, before the coins), because the whole claim under test is that the
	ORDER the streams are consumed in did not change.
	"""
	var terrain := _terrain(run_seed)
	terrain.spawn_field_bridges = bridges
	if walk_first:
		_first_bridge(terrain, run_seed)
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
	var before := batch.size()
	terrain.spawn_field_bridges_in_chunk(chunk_pos, batch, body)
	var bridge_boxes := batch.size() - before
	terrain.spawn_crocodiles_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_bosses_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_hunters_in_chunk(chunk_pos, parent, obstacles)
	terrain.spawn_coins_in_chunk(chunk_pos, parent, obstacles)

	var entries: Array = []
	for entry_v: Variant in batch:
		entries.append(var_to_bytes(entry_v))
	var bodies: Array = []
	var coins: Array = []
	for child in parent.get_children():
		if child.is_in_group("coin"):
			coins.append((child as Node3D).position)
			continue
		bodies.append("%s@%s" % [child.name, (child as Node3D).position])
	body.free()
	parent.queue_free()
	return {
		"terrain": terrain,
		"batch": entries,
		"bridge_boxes": bridge_boxes,
		"obstacles": var_to_bytes(obstacles),
		"bodies": bodies,
		"coins": coins,
		"signature": var_to_bytes([entries, bodies, coins]),
	}


# ============================================================================
# CHECK 7 — the crossing is DRY underfoot, and wet a metre off the parapet
# ============================================================================

func _check_the_crossing_is_dry_underfoot() -> void:
	"""
	THE ACCEPTANCE, and the only check here that runs a hero.

	A real player.tscn is dropped onto a REAL deck — the collision shapes the
	shipped builder put on the chunk's own body — and walked across it metre by
	metre. At every sample the shipped `is_wading` must be FALSE while the
	shipped `is_river_at` says the band is right there underneath, which is the
	whole of "the water is still painted under the bridge, and you are not in
	it".

	TWO CONTROLS, and they are the mutations the bead asks for:
	  * a metre off the parapet, standing on the ground, the same player at the
	    same XZ band must WADE — so the deck is doing the work, not a dry patch;
	  * THE DECK REMOVED (`spawn_field_bridges = false`, the same A/B switch as
	    check 6): the same walk at ground level must wade at the samples over the
	    water. A bridge that stopped being built has to turn the crossing wet
	    again, or this check would pass with no bridges in the game at all.
	"""
	var run_seed: int = CROSSING_SEEDS[0]
	var terrain := _terrain(run_seed)
	var row := _first_bridge(terrain, run_seed)
	if row.is_empty():
		_fail("check 7 found no bridge on seed %d" % run_seed)
		terrain.free()
		Sentinel.done("crossing_is_dry_underfoot")
		return

	# The terrain answers through a forwarder in the group — see TerrainProxy.
	var proxy := TerrainProxy.new()
	proxy.real = terrain
	root.add_child(proxy)
	proxy.add_to_group("terrain")

	# The ground: a slab whose top is y = 0, the flat-world invariant, so a
	# player who steps off the deck lands in the river bed like anyone wading.
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(400.0, 1.0, 400.0)
	ground_shape.shape = ground_box
	var poly: PackedVector2Array = row["poly"]
	var centre: Vector2 = poly[int(poly.size() / 2)]
	ground_shape.position = Vector3(centre.x, -0.5, centre.y)
	ground.add_child(ground_shape)
	root.add_child(ground)

	var packed: PackedScene = load(PLAYER_SCENE)
	var player: CharacterBody3D = packed.instantiate()
	player.position = Vector3(poly[0].x, 1.0, poly[0].y)
	root.add_child(player)
	await _frames(4)

	# ---- the bridged walk ---------------------------------------------------
	var stone := _bridge_bodies(terrain, row)
	var samples := _walk(row, 1.0)
	var wet_on_deck := 0
	var not_landed := 0
	var over_water := 0
	var worst := ""
	for sample_v: Variant in samples:
		var sample: Dictionary = sample_v
		var p: Vector2 = sample["pos"]
		var surface: float = terrain.field_bridge_surface_y(Vector3(p.x, 0.0, p.y))
		if terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
			over_water += 1
		if not await _stand(player, Vector3(p.x, surface + 0.6, p.y)):
			not_landed += 1
			if worst == "":
				worst = ("the hero never settled on the deck at s = %.1f m (y ="
						% float(sample["s"]) + " %.2f, surface %.2f)"
						% [player.global_position.y, surface])
			continue
		if player.is_wading:
			wet_on_deck += 1
			if worst == "":
				worst = ("the hero WADES standing on the deck at s = %.1f m,"
						% float(sample["s"]) + " y = %.2f (surface %.2f)"
						% [player.global_position.y, surface])

	# ---- control 1: a metre off the parapet ---------------------------------
	var half: float = row["half"]
	var wet_off := 0
	var off_samples := 0
	for sample_v: Variant in samples:
		var sample: Dictionary = sample_v
		var p: Vector2 = sample["pos"]
		var perp: Vector2 = sample["perp"]
		var at := Vector2(p.x + perp.x * (half + 1.0), p.y + perp.y * (half + 1.0))
		if not terrain.is_river_at(Vector3(at.x, 0.0, at.y)):
			continue
		off_samples += 1
		if not await _stand(player, Vector3(at.x, 1.0, at.y)):
			continue
		if player.is_wading:
			wet_off += 1

	# ---- control 2: the deck removed ----------------------------------------
	for node in stone:
		node.queue_free()
	await _frames(4)
	var wet_without := 0
	for sample_v: Variant in samples:
		var sample: Dictionary = sample_v
		var p: Vector2 = sample["pos"]
		if not terrain.is_river_at(Vector3(p.x, 0.0, p.y)):
			continue
		if not await _stand(player, Vector3(p.x, 1.0, p.y)):
			continue
		if player.is_wading:
			wet_without += 1

	print("field bridges: %d deck samples (%d over water) — %d waded, %d never"
			% [samples.size(), over_water, wet_on_deck, not_landed]
			+ " landed; off the parapet %d/%d wade; with the deck gone %d wade"
			% [wet_off, off_samples, wet_without])

	if over_water < 1:
		_fail("check 7's bridge does not cross water at all — nothing it measures"
				+ " is about wading")
	if not_landed > 0:
		_fail("%d of %d deck samples never put the hero on the stone — the deck"
				% [not_landed, samples.size()] + " has a hole in it or the"
				+ " surface height is wrong. First: %s" % worst)
	if wet_on_deck > 0:
		_fail("%d of %d deck samples leave the hero WADING while standing on the"
				% [wet_on_deck, samples.size()] + " bridge — the Y-aware wade"
				+ " clause is not doing its job. First: %s" % worst)
	if off_samples > 0 and wet_off < off_samples:
		_fail("%d of %d samples a metre off the parapet, standing in the river"
				% [off_samples - wet_off, off_samples] + " bed, do NOT wade — the"
				+ " Y-aware clause has dried out the whole band")
	if wet_without < 1:
		_fail("with the deck removed the crossing is STILL dry at every sample —"
				+ " check 7 would pass with no bridges in the game")

	player.queue_free()
	ground.queue_free()
	proxy.queue_free()
	await _frames(2)
	terrain.free()
	Sentinel.done("crossing_is_dry_underfoot")


func _bridge_bodies(terrain: Node3D, row: Dictionary) -> Array:
	"""
	Build the bridge's real collision, chunk by chunk, INTO THE TREE.

	@return the parent nodes, so the caller can free them and re-measure the
	        crossing with the deck gone (check 7's second control).
	"""
	var poly: PackedVector2Array = row["poly"]
	var half: float = row["half"]
	var seen: Dictionary = {}
	var parents: Array = []
	for p in poly:
		var c0: Vector2i = terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))
		var span := ceili((half + terrain.chunk_size) / terrain.chunk_size)
		for dx in range(-span, span + 1):
			for dz in range(-span, span + 1):
				var cp := c0 + Vector2i(dx, dz)
				if seen.has(cp):
					continue
				seen[cp] = true
				var batch: Array = []
				var body := StaticBody3D.new()
				terrain.spawn_field_bridges_in_chunk(cp, batch, body)
				if body.get_child_count() == 0:
					body.free()
					continue
				var parent := Node3D.new()
				parent.position = terrain.chunk_to_world(cp)
				parent.add_child(body)
				root.add_child(parent)
				parents.append(parent)
	return parents


func _stand(player: CharacterBody3D, at: Vector3) -> bool:
	"""
	Teleport the hero to `at` and let him settle.

	@return whether he ended the drop on the floor — false is a hole in whatever
	        he was aimed at, which is a finding and not an error.
	"""
	player.global_position = at
	player.velocity = Vector3.ZERO
	for _i in SETTLE_FRAMES:
		await physics_frame
		if player.is_on_floor():
			# One more frame so _physics_process recomputes is_wading with
			# is_on_floor() already true — the flag is read at STEP 1.5, above
			# the move, so the landing frame still carries the airborne answer.
			await physics_frame
			return true
	return false


# ============================================================================
# CHECK 8 — every coin standing on a deck has a SLAB under it
# ============================================================================

## Seeds check 8 lays real coins on. Fewer than check 1's list because each one
## generates whole chunks; 26 is the seed the capsule bug was found on.
const COIN_SEEDS: Array[int] = [26, 11, 2027, 90210]


func _check_deck_coins_stand_on_stone() -> void:
	"""
	THE BUG THE RECTANGLE FIX EXISTS FOR (Codex review of PR #232). The surface
	query used to be a point-to-POLYLINE distance — which describes a CAPSULE,
	not the slabs the builder emits. At a joint on the outside of a turn a point
	can be within half a deck of the walking line and outside every rectangle, so
	`spawn_coins_in_chunk` stood a coin at deck height over open air (seed 26,
	station 34, near (246.25, 17.93)).

	So: lay the road's REAL coins through the shipped spawner over every chunk a
	bridge touches, and for every coin the deck lifted, assert there is a BUILT
	BOX under it. The boxes come from `_bridge_boxes` and the coins from
	`spawn_coins_in_chunk`; neither reads the other, so this measures the two
	halves agreeing rather than one of them twice.

	THE MUTATION CONTROL is the old test itself: `_capsule_hit` is the rejected
	implementation, and somewhere on these bridges there must be a point it calls
	deck which no slab covers. If there is not, the rectangle fix changed nothing
	measurable and this check is decoration.
	"""
	var lifted := 0
	var floating := 0
	var capsule_lies := 0
	var worst := ""

	for run_seed in COIN_SEEDS:
		var terrain := _terrain(run_seed)
		var row := _first_bridge(terrain, run_seed)
		if row.is_empty():
			terrain.free()
			continue
		var poly: PackedVector2Array = row["poly"]
		var half: float = row["half"]
		# EVERY bridge's stone over the chunks below, not just this row's: a
		# neighbouring crossing can lay coins in the same chunks, and a coin
		# blamed on missing stone that another bridge is holding up is a lie.
		var boxes := _chunk_bridge_boxes(terrain, poly, 2)

		# THE CONTROL, on geometry rather than on luck: walk a ring at exactly the
		# deck's half-width around every joint. The capsule accepts all of it; the
		# slabs do not, on the outside of every turn.
		for i in range(1, poly.size() - 1):
			for step in 72:
				var ang := TAU * float(step) / 72.0
				var probe := poly[i] + Vector2(cos(ang), sin(ang)) * (half - 0.05)
				if not _capsule_hit(poly, probe, half):
					continue
				if not _covered(boxes, Vector3(probe.x, FIELD_TOP - 0.05, probe.y)):
					capsule_lies += 1

		# ...and the real coins, chunk by chunk along the bridge.
		var seen: Dictionary = {}
		for p in poly:
			var cp: Vector2i = terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var at := cp + Vector2i(dx, dz)
					if seen.has(at):
						continue
					seen[at] = true
					var built := _generate(run_seed, at, true)
					var origin: Vector3 = terrain.chunk_to_world(at)
					for coin_v: Variant in built["coins"]:
						var coin: Vector3 = coin_v
						var world := coin + origin
						# A DECK COIN IS ONE THE QUERY CLAIMS, not one that sits
						# high: `_settle_coin_y` perches ordinary coins on top of
						# a climbable prop, and those are somebody else's rule.
						var surface: float = terrain.field_bridge_surface_y(world)
						if surface <= -INF:
							continue
						lifted += 1
						if not is_equal_approx(world.y,
								surface + TERRAIN_SCRIPT.COIN_GROUND_HEIGHT):
							floating += 1
							if worst == "":
								worst = ("seed %d: a coin over the deck at"
										% run_seed + " (%.2f, %.2f) sits at y ="
										% [world.x, world.z] + " %.2f where the"
										% world.y + " surface says %.2f" % surface)
							continue
						if _covered(boxes, Vector3(world.x, surface - 0.05, world.z)):
							continue
						floating += 1
						if worst == "":
							worst = ("seed %d: a coin at (%.2f, %.2f) was raised"
									% [run_seed, world.x, world.z] + " to y = %.2f"
									% world.y + " with NO slab under it")
					built["terrain"].free()
		terrain.free()

	print("field bridges: %d road coins raised onto a deck over %d seeds, %d of"
			% [lifted, COIN_SEEDS.size(), floating]
			+ " them over open air; the rejected capsule test accepts %d points"
					% capsule_lies + " no slab covers")

	if lifted < 1:
		_fail("check 8 found no coin standing on a deck at all — it measured"
				+ " nothing (the road's coins should ride every crossing)")
	if floating > 0:
		_fail("%d road coin(s) stand at deck height over open air — the deck"
				% floating + " query is accepting points outside the slabs the"
				+ " chunks really build. First: %s" % worst)
	if capsule_lies < 1:
		_fail("check 8's mutation control is inert: the rejected point-to-polyline"
				+ " (capsule) test accepts nothing the slabs refuse, so the"
				+ " rectangle containment it replaced cannot be shown to matter")
	Sentinel.done("deck_coins_stand_on_stone")


func _chunk_bridge_boxes(terrain: Node3D, poly: PackedVector2Array, ring: int) -> Array:
	"""
	Every field-bridge box the chunks around a walking line build, in WORLD space
	and with NO filtering by which bridge it belongs to.

	@param ring: How many chunks past the line's own to sweep.

	`_bridge_boxes` keeps one bridge's stone so check 2 can say "built exactly
	once"; this one keeps ALL of it, because check 8 asks the opposite question —
	is there anything at all under this coin — and a neighbouring crossing's deck
	is a perfectly good answer.
	"""
	var seen: Dictionary = {}
	var boxes: Array = []
	for p in poly:
		var c0: Vector2i = terrain.world_to_chunk(Vector3(p.x, 0.0, p.y))
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				var cp := c0 + Vector2i(dx, dz)
				if seen.has(cp):
					continue
				seen[cp] = true
				var batch: Array = []
				var body := StaticBody3D.new()
				terrain.spawn_field_bridges_in_chunk(cp, batch, body)
				var origin: Vector3 = terrain.chunk_to_world(cp)
				for entry_v: Variant in batch:
					var entry: Dictionary = entry_v
					var xf: Transform3D = entry["transform"]
					boxes.append({
						"xform": Transform3D(xf.basis, xf.origin + origin),
						"chunk": cp,
					})
				body.free()
	return boxes


func _capsule_hit(poly: PackedVector2Array, p: Vector2, half: float) -> bool:
	"""
	THE REJECTED IMPLEMENTATION, kept here as check 8's mutation: a clamped
	point-to-segment distance over the whole polyline, i.e. "is this within half a
	deck of the walking line". It rounds off every joint into a disc, which is why
	it accepts open air on the outside of a turn.
	"""
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var seg: Vector2 = poly[i + 1] - a
		var len_sq := seg.length_squared()
		var t: float = 0.0 if len_sq <= 0.0 else clampf((p - a).dot(seg) / len_sq, 0.0, 1.0)
		if p.distance_to(a + seg * t) <= half:
			return true
	return false
