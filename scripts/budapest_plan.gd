class_name BudapestPlan
extends RefCounted
## BUDAPEST, DRAWN AS NUMBERS — the authored plan of the one city in this game.
##
## Epic godot-test1-8gw ("Escape to Budapest"), bead .3, the keystone. This file
## is DATA, the way `tower_plans.gd` is data and `tower_graph.gd` is data: `const`
## dicts and arrays of plain values, a handful of pure static helpers over them,
## no logic, no `Resource`, no class hierarchy, and NOTHING THAT DEPENDS ON ANY
## OTHER SCRIPT — which is what lets `piglet_crocodile_ai.gd` read `GATE.x` for
## its difficulty clamp without opening a `class_name` cycle.
##
## It is read by exactly three things: `endless_terrain.gd`, which streams the
## city's cells out of it through the ordinary chunk machinery;
## `assets/shaders/ground.gdshader`, which is fed the same numbers as uniforms so
## the band you SEE is the band you WADE; and `budapest_selfcheck.gd`, which
## measures the plan against itself and against the world it produces.
##
## ============================================================================
## WHY IT IS AUTHORED — no seed, no draw, no hashing, and there may never be one
## ============================================================================
##
## The owner's ruling on the HQ was "plan it once and forever", and `tower_site()`
## is that ruling as one CONSTANT `Vector3`. Budapest is the same ruling one scale
## up. A city that moved between runs would be a different city: the win condition
## of this epic is exploring 18 of the 22 landmarks below, and a landmark whose
## position is a function of the run seed cannot be put on a map, cannot be
## audited for reachability, and cannot be described to a player in words.
##
## So: there is no run seed in this file, no draw from any stream, no hashing, and
## no derived-from-position number anywhere. THE NUMBERS ARE THE DESIGN RECORD.
## There is nothing to reroll — a future author who wants the Opera somewhere else
## edits the table, exactly as a designer editing a storey edits `TowerPlans.rows`.
## `budapest_selfcheck` check 1 reads this file as TEXT and fails the build if a
## seed, a draw or a hashing call ever appears in it.
##
## The one number here that is a SALT rather than a coordinate is
## `CITY_LANDMARK_SALT`, and it is not an exception: it is mixed with a SLOT INDEX
## and nothing else to seed a landmark builder's private colour stream. No run
## seed, so the city is the same city every run; no chunk coordinate, so a
## building sliced across nine chunks is one colour and not nine — see THE
## SLICING CONTRACT below.
##
## ============================================================================
## THE ORIENTATION — read this before you read a single coordinate
## ============================================================================
##
## **+X is EAST. +Z is SOUTH. +Y is up.**
##
## Every coordinate below is meaningless without that sentence, and a reader
## coming from a paper map will otherwise assume +Z is north and mirror the whole
## city about the Danube in their head. North is -Z: Margaret Island is at
## z = -880 because it is upstream, and Gellért Hill is at z = +760 because it is
## downstream. The Danube polyline is listed NORTH TO SOUTH, i.e. in increasing z.
##
## The city sits east of the GastroDefense HQ, which is at x = -400. The gate is
## at x = 1600 — the owner's "about 2 km from HQ" — and the far edge of the rect
## at x = 3800 puts Parliament-to-Gellért at roughly the real 2.2 km.
##
## ============================================================================
## THE LIBERTIES TAKEN WITH THE REAL MAP, and why each one
## ============================================================================
##
## The layout is a real-map RELATIVE layout at roughly real scale: west bank is
## Buda (the two hills), east bank is Pest (the flat grid), the bridges cross in
## the real order north to south — Margaret, Chain, Elisabeth, Liberty — and the
## Parliament faces the river from the Pest side opposite Castle Hill. Three
## things are deliberately not real:
##
##   1. THE DANUBE IS NARROWED to 240 m (`DANUBE_HALF_WIDTH` 120) against the real
##      ~350 m at Budapest. Not for gameplay: Castle Hill and Gellért Hill have to
##      fit on the west bank at roughly real scale inside a 2.2 km rect, and every
##      100 m of river is 100 m the hills do not get. The river still reads as the
##      dominant feature of the city — it is 240 m of wading against a 16 m
##      avenue.
##
##   2. THE ANDRÁSSY END IS FOLDED IN. Heroes' Square, Vajdahunyad and the
##      Széchenyi bath (slots 15-17) sit ~800 m closer to the river than the real
##      2.5 km up Andrássy út, because the alternative is a 2.5 km corridor of
##      nothing between the inner city and three landmarks the win condition
##      needs. The epic asked for the fold explicitly.
##
##   3. THE HILLS ARE FLAT-TOPPED PLATEAUS WITH ONE RAMP EACH. This game's ground
##      is a single plane at y = 0 and mountains are impassable block massifs you
##      walk around; a heightfield Castle Hill would break the flat-world
##      invariant every coin height, every predator's gravity settle and every
##      block base in the world depends on. So a hill is a massif with a walkable
##      lid and one tilted ramp — never steps, the HQ's "no traversal may demand a
##      jump-height" rule applied outdoors.
##
## ============================================================================
## THE SLICING CONTRACT — why a landmark's seed is the SLOT INDEX
## ============================================================================
##
## The Parliament is 268 m long and Buda Castle's disc is 156 m in radius, while a
## chunk is 50 m and the web build keeps 49 of them resident. A landmark builder
## therefore cannot emit into "its" chunk: every chunk whose square meets a slot's
## disc runs that slot's builder and keeps only the boxes whose CENTRE falls in
## its own square. That works because the city builders are pure functions of
## (centre, rng) whose random stream touches COLOUR ONLY — so the same builder run
## from the same seed in a neighbouring chunk emits the same boxes at the same
## world positions, and clipping is a filter on the output.
##
## "The same seed" is the load-bearing half, and it is why the seed is a function
## of `SLOTS` index and `CITY_LANDMARK_SALT` alone. Mix a chunk coordinate in and
## every slice draws its own colours: the Parliament would be tie-dyed along its
## chunk seams, and no self-check that looks at one chunk would ever see it.
##
## ============================================================================
## WHAT IS NOT HERE
## ============================================================================
##
## GEOMETRY. A slot is a position and a radius; the stone is
## `landmark_builders.gd`'s, addressed by the METHOD-NAME STRING its registry
## already dispatches on. A slot whose builder has not landed yet carries
## `"builder": ""` and is skipped by the streamer — that is the whole of "leave
## the slot empty", and it is what lets the seven wave-C places below exist as
## reservations from day one.
##
## STREETS. `STREET_PITCH` and `AVENUE_HALF_WIDTH` are the grid PARAMETERS; the
## streets themselves are bead `godot-test1-8gw.9`. This bead draws exactly one
## street, the avenue out of the gate, because the gate district has to be walked.

# ============================================================================
# SECTION 1 — THE SITE
# ============================================================================

## The city rect, in world XZ. A CONSTANT, like `tower_site()`: 2200 x 2200 m
## with the gate on the west edge. `contains()` is the only reader of these two,
## and it is asked twice per physics frame by `is_river_at`, so keep it cheap.
const BUDAPEST_MIN := Vector2(1600.0, -1100.0)
const BUDAPEST_MAX := Vector2(3800.0, 1100.0)

## Where the road's approach corridor meets the city, on the west edge at z = 0.
## The HQ is at x = -400, so this is 2 km east of it — the owner's number. `y` is
## 0 because the ground is 0 everywhere; it is a `Vector3` only so callers that
## want a world point do not have to build one.
const GATE := Vector3(1600.0, 0.0, 0.0)

# ============================================================================
# SECTION 2 — THE DANUBE
# ============================================================================

## The river, as a 5-point polyline in (x, z), NORTH TO SOUTH — increasing z. The
## bend at z = -40 is the real one the Chain Bridge crosses.
##
## This is PAINT PLUS A WADE PENALTY AND NOTHING ELSE. There is no water mesh, no
## depth, no transparency and no vertex displacement anywhere in this game, and
## the city does not get to be the exception: the ground stays one flat plane at
## y = 0 and the Danube is a tinted band the player walks through slowly. The band
## is computed on the CPU by `danube_wet()` for wading and on the GPU by
## `ground.gdshader` for the tint — TWO LANGUAGES, ONE CONTRACT, edited together,
## the same rule `_biome_noise` / `biome_noise` already live under.
const DANUBE: Array = [
	Vector2(2560.0, -1100.0),
	Vector2(2530.0, -560.0),
	Vector2(2470.0, -40.0),
	Vector2(2500.0, 520.0),
	Vector2(2570.0, 1100.0),
]

## Half the river's width: 240 m against the real ~350. See LIBERTIES (1) above —
## the hills need the bank.
const DANUBE_HALF_WIDTH: float = 120.0

# ============================================================================
# SECTION 3 — DRY RECTS: one mechanism, three users
# ============================================================================

## `is_river_at()` is XZ-only and the wade test ignores Y, so a bridge deck 12 m
## above the water would still wade. The answer is not a Y-aware river — it is a
## small table of axis-aligned rects the band is PUNCHED OUT BY, in both
## languages, so the deck is dry to the wade test and un-tinted to the shader.
##
## MARGARET ISLAND RIDES THE SAME TABLE AS THE DECKS, and that is the point of
## the mechanism: "an island" and "a bridge deck" are the same question asked of
## `is_river_at` — *this XZ is inside the band and is not water*. Bead
## `godot-test1-8gw.4` needs no new machinery for the island's parkland; it has a
## row here already.
##
## Rect2(x, z, width, depth). Up to 8 rows: `ground.gdshader`'s `city_dry` array
## is `CITY_DRY_MAX = 8` and the two must move together.
const DRY_RECTS: Array = [
	Rect2(2380.0, -716.0, 320.0, 32.0),   # Margaret Bridge deck
	Rect2(2330.0, -16.0, 290.0, 32.0),    # Chain Bridge deck
	Rect2(2350.0, 404.0, 290.0, 32.0),    # Elisabeth Bridge deck
	Rect2(2360.0, 684.0, 300.0, 32.0),    # Liberty Bridge deck
	Rect2(2470.0, -950.0, 130.0, 310.0),  # Margaret Island — dry land in the river
]

# ============================================================================
# SECTION 4 — THE PLATEAUS: massifs with a lid, and one tilted ramp each
# ============================================================================

## Castle Hill and Gellért Hill. Each is a rect, a `top` height, and ONE ramp.
##
## THE PLATEAU IS CHUNK-SLICED FOR FREE: a chunk inside the rect emits exactly one
## box — the chunk square intersected with the plateau rect, from y = 0 to `top` —
## with one collision shape and one `obstacles` footprint at `climbable: false`,
## the mountain-massif convention. Cliffs on every side; the only way up is the
## ramp. A mountain you walk around, with a walkable lid.
##
## THE RAMP IS A TILTED BOX, NEVER STEPS. `CharacterBody3D` cannot climb a step at
## all, and the HQ's rule — no traversal may demand a jump-height — is the same
## rule outdoors. `ramp_dir` is +X for both: the ramp climbs eastward, so its
## foot is on the west side and its head meets the plateau's west edge.
##
## THE SLOPE IS MEASURED, NOT ASSERTED. Castle Hill is 30 / 140 = 0.214, Gellért
## is 46 / 210 = 0.219, and `budapest_selfcheck` check 11 compares both against
## `TowerInterior.PLAN_RAMP_MAX_SLOPE` — READ from there, never restated here, so
## retuning the one ramp in this game anybody has actually walked retunes this
## ceiling with it.
const PLATEAUS: Array = [
	{
		"id": "castle_hill",
		"rect": Rect2(1970.0, -860.0, 400.0, 800.0),
		"top": 30.0,
		"ramp": Rect2(1830.0, -466.0, 140.0, 12.0),
		"ramp_dir": 1,   # +X: climbs eastward, head against the plateau's west face
	},
	{
		"id": "gellert",
		"rect": Rect2(2090.0, 570.0, 280.0, 380.0),
		"top": 46.0,
		"ramp": Rect2(1880.0, 734.0, 210.0, 12.0),
		"ramp_dir": 1,
	},
]

# ============================================================================
# SECTION 5 — THE STREET GRID AND THE AVENUE
# ============================================================================

## Pest's block pitch. PARAMETER ONLY in this bead — bead `godot-test1-8gw.9`
## draws the streets off it. 62 m is a Pest block: wide enough that the authored
## landmark discs below sit inside blocks rather than straddling four of them, and
## a whole multiple of neither the 50 m chunk nor the 25 m house pitch, so a
## street line never lands on a chunk seam for every chunk in a row.
const STREET_PITCH: float = 62.0

## Half-width of the ONE street this bead draws: the avenue running east out of
## the gate along z = 0, to the Danube's west bank. 16 m wide. It is a thin,
## non-colliding pavement slab — the avenue is a READ, not a corridor, and the
## thing that makes it walkable is that nothing else is built on it.
const AVENUE_HALF_WIDTH: float = 8.0

## Spacing of the approach + avenue coin line, from the road's terminal station to
## the west bank. ZERO RNG: an authored line at a fixed pitch, so there is no
## stream here to keep independent of the chunk's and nothing to A/B. Coins are
## the headline score since bead .1 retired distance, and capping the road's coins
## at the terminal would otherwise freeze the score for the last 900 m.
const CITY_COIN_SPACING: float = 8.0

# ============================================================================
# SECTION 6 — THE GATE DISTRICT
# ============================================================================

## The one district this bead builds for real: ~200 x 260 m immediately east of
## the gate. It is deliberately the SMALLEST slice that exercises every dangerous
## seam at once — the avenue, authored houses, the city prop builders, a plateau
## ramp one chunk west, and (900 m east, streaming in when you walk there) a dry
## bridge deck.
const DISTRICT := Rect2(1620.0, -130.0, 200.0, 260.0)

## Sixteen authored houses, eight either side of the avenue at z = +-26, every
## 25 m from x = 1640. Hull + eaves roof + door + windows: the `_spawn_city_content`
## house recipe with the dimensions AUTHORED instead of drawn.
##
## `size` is (width, height, depth) and EVERY `height` IS <= `PROP_MAX_STEP` (2.6),
## which is the city biome's own climbability contract as a number: a hull top is
## one jump from the pavement, the footprint is `climbable: true`, and a city block
## is a field of croc-free perches. A house here that broke that would be the one
## unreachable roof in the city.
##
## `wall_shade` and `roof_shade` are FACTORS, not colours — 0.0..1.0 lerps between
## the two plaster tints and between the tile and slate roofs that
## `endless_terrain.gd` already declares. Colour lives with the builder; this file
## holds the plan. Keeping them as floats is also what keeps this table free of
## any dependency on that script's constants.
const DISTRICT_HOUSES: Array = [
	# ---- north side of the avenue (z = -26) --------------------------------
	{"pos": Vector3(1640.0, 0.0, -26.0), "size": Vector3(4.2, 2.55, 3.4), "wall_shade": 0.10, "roof_shade": 0.0},
	{"pos": Vector3(1665.0, 0.0, -26.0), "size": Vector3(3.6, 2.30, 3.2), "wall_shade": 0.65, "roof_shade": 1.0},
	{"pos": Vector3(1690.0, 0.0, -26.0), "size": Vector3(4.4, 2.60, 3.8), "wall_shade": 0.30, "roof_shade": 0.0},
	{"pos": Vector3(1715.0, 0.0, -26.0), "size": Vector3(3.2, 2.10, 2.8), "wall_shade": 0.85, "roof_shade": 1.0},
	{"pos": Vector3(1740.0, 0.0, -26.0), "size": Vector3(4.0, 2.45, 3.6), "wall_shade": 0.20, "roof_shade": 0.0},
	{"pos": Vector3(1765.0, 0.0, -26.0), "size": Vector3(3.8, 2.35, 3.0), "wall_shade": 0.55, "roof_shade": 0.0},
	{"pos": Vector3(1790.0, 0.0, -26.0), "size": Vector3(4.4, 2.60, 4.0), "wall_shade": 0.40, "roof_shade": 1.0},
	{"pos": Vector3(1815.0, 0.0, -26.0), "size": Vector3(3.4, 2.20, 3.0), "wall_shade": 0.75, "roof_shade": 0.0},
	# ---- south side of the avenue (z = +26) --------------------------------
	{"pos": Vector3(1640.0, 0.0, 26.0), "size": Vector3(3.8, 2.40, 3.2), "wall_shade": 0.50, "roof_shade": 1.0},
	{"pos": Vector3(1665.0, 0.0, 26.0), "size": Vector3(4.4, 2.60, 3.9), "wall_shade": 0.15, "roof_shade": 0.0},
	{"pos": Vector3(1690.0, 0.0, 26.0), "size": Vector3(3.2, 2.05, 2.9), "wall_shade": 0.90, "roof_shade": 1.0},
	{"pos": Vector3(1715.0, 0.0, 26.0), "size": Vector3(4.0, 2.50, 3.5), "wall_shade": 0.35, "roof_shade": 0.0},
	{"pos": Vector3(1740.0, 0.0, 26.0), "size": Vector3(3.6, 2.25, 3.1), "wall_shade": 0.70, "roof_shade": 0.0},
	{"pos": Vector3(1765.0, 0.0, 26.0), "size": Vector3(4.2, 2.55, 3.7), "wall_shade": 0.25, "roof_shade": 1.0},
	{"pos": Vector3(1790.0, 0.0, 26.0), "size": Vector3(3.4, 2.15, 3.0), "wall_shade": 0.80, "roof_shade": 0.0},
	{"pos": Vector3(1815.0, 0.0, 26.0), "size": Vector3(4.0, 2.45, 3.4), "wall_shade": 0.45, "roof_shade": 1.0},
]

# ============================================================================
# SECTION 7 — THE 22 LANDMARK SLOTS
# ============================================================================

## The salt the per-slot colour stream is seeded from, mixed with the SLOT INDEX
## and nothing else. See THE SLICING CONTRACT in the header for why no run seed
## and no chunk coordinate may ever join it.
const CITY_LANDMARK_SALT: int = 0xB0DA9E51

## THE WIN SET. 22 places; bead `godot-test1-8gw.5` calls 18 of them a win.
##
## A slot is `{ id, builder, pos, radius }` and NOTHING ELSE — position and size.
## `builder` is the method-name string from `LandmarkBuilders.CITY_LANDMARKS`,
## which dispatches on exactly that string already, so this file references the
## registry without editing it or importing it.
##
## `pos.y` is the BASE HEIGHT the builder is placed at: 0 everywhere except the
## four slots standing on a plateau, which carry that plateau's `top`.
##
## `radius` for rows 0-14 is the registry's OWN declared radius, copied. Check 2
## asserts the two agree, so a later edit to a shipped builder's radius fails this
## build instead of silently overhanging into the street.
##
## `radius` for rows 15-21 — the seven whose builders are wave C — is a
## RESERVATION: authored generously here so the catalogue and the reachability
## audit have 22 slots to work with from day one, and so wave C's builders have a
## declared bound to hit. An empty `builder` is skipped by the streamer and exempt
## from the registry check.
const SLOTS: Array = [
	# ---- the Danube core ---------------------------------------------------
	{"id": "parliament", "builder": "_city_parliament", "pos": Vector3(2760.0, 0.0, -480.0), "radius": 151.0},
	{"id": "buda_castle", "builder": "_city_buda_castle", "pos": Vector3(2170.0, 30.0, -240.0), "radius": 156.0},
	{"id": "matthias", "builder": "_city_matthias_bastion", "pos": Vector3(2170.0, 30.0, -640.0), "radius": 80.0},
	{"id": "citadella", "builder": "_city_citadella", "pos": Vector3(2230.0, 46.0, 760.0), "radius": 120.0},
	{"id": "margaret_island", "builder": "_city_margaret_island", "pos": Vector3(2535.0, 0.0, -880.0), "radius": 56.0},
	{"id": "chain_bridge", "builder": "_city_chain_bridge", "pos": Vector3(2475.0, 0.0, 0.0), "radius": 124.0},
	{"id": "liberty_bridge", "builder": "_city_liberty_bridge", "pos": Vector3(2510.0, 0.0, 700.0), "radius": 104.0},
	{"id": "elisabeth_bridge", "builder": "_city_elisabeth_bridge", "pos": Vector3(2495.0, 0.0, 420.0), "radius": 122.0},
	{"id": "margaret_bridge", "builder": "_city_margaret_bridge", "pos": Vector3(2540.0, 0.0, -700.0), "radius": 114.0},
	# ---- Pest's inner city -------------------------------------------------
	{"id": "basilica", "builder": "_city_basilica", "pos": Vector3(2920.0, 0.0, -280.0), "radius": 58.0},
	{"id": "market_hall", "builder": "_city_market_hall", "pos": Vector3(2820.0, 0.0, 620.0), "radius": 82.0},
	{"id": "synagogue", "builder": "_city_synagogue", "pos": Vector3(2960.0, 0.0, 200.0), "radius": 49.0},
	{"id": "vaci_utca", "builder": "_city_vaci_utca", "pos": Vector3(2760.0, 0.0, 300.0), "radius": 78.0},
	{"id": "national_museum", "builder": "_city_national_museum", "pos": Vector3(2920.0, 0.0, 440.0), "radius": 62.0},
	{"id": "opera", "builder": "_city_opera", "pos": Vector3(3000.0, 0.0, -180.0), "radius": 49.0},
	# ---- the Andrássy end, folded in (see LIBERTIES 2) ---------------------
	{"id": "heroes_square", "builder": "", "pos": Vector3(3520.0, 0.0, -520.0), "radius": 110.0},
	{"id": "vajdahunyad", "builder": "", "pos": Vector3(3680.0, 0.0, -340.0), "radius": 100.0},
	{"id": "szechenyi_bath", "builder": "", "pos": Vector3(3620.0, 0.0, -760.0), "radius": 90.0},
	# ---- the baths and the odd ones ----------------------------------------
	{"id": "gellert_bath", "builder": "", "pos": Vector3(2420.0, 0.0, 1000.0), "radius": 70.0},
	{"id": "rudas_bath", "builder": "", "pos": Vector3(2370.0, 0.0, 560.0), "radius": 50.0},
	{"id": "shoes_on_the_danube", "builder": "", "pos": Vector3(2640.0, 0.0, -300.0), "radius": 40.0},
	{"id": "budapest_eye", "builder": "", "pos": Vector3(2870.0, 0.0, -60.0), "radius": 40.0},
]

# ============================================================================
# SECTION 8 — PURE HELPERS
# ============================================================================
#
# ALL of these are static, allocation-light and safe to call per tick.
# `is_river_at()` calls `contains()` and `danube_wet()` EVERY PHYSICS FRAME for
# the player and for every awake predator, so nothing here may allocate an Array,
# a Dictionary or a String, and nothing here may loop over anything longer than
# the five-point polyline and the five dry rects.
#
# THE fp32 RULE: every step of the segment-distance arithmetic is routed through
# `Vector2`, never through scalar float maths. GDScript floats are f64 and
# `Vector2` components are f32; the shader half of this contract has only f32, so
# doing the CPU half in f64 gives a DIFFERENT band, not a more precise one. This
# is the same discipline `_biome_noise` is written under and for the same reason.


static func contains(x: float, z: float) -> bool:
	"""Is this world XZ inside the city rect? The one membership test; every
	spawner policy, the biome override and the river override all read it."""
	return x >= BUDAPEST_MIN.x and x <= BUDAPEST_MAX.x \
			and z >= BUDAPEST_MIN.y and z <= BUDAPEST_MAX.y


static func rect() -> Rect2:
	"""The site as a `Rect2`, for callers that want to intersect against it."""
	return Rect2(BUDAPEST_MIN, BUDAPEST_MAX - BUDAPEST_MIN)


static func danube_distance(x: float, z: float) -> float:
	"""
	Shortest distance from a world XZ to the Danube polyline.

	Four segments, each tested by projecting onto it and clamping the parameter
	to [0, 1] — the standard point-to-segment, written entirely in `Vector2` so
	every intermediate is f32 and matches what the shader computes.
	"""
	var p := Vector2(x, z)
	var best := INF
	for i in range(DANUBE.size() - 1):
		var a: Vector2 = DANUBE[i]
		var b: Vector2 = DANUBE[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		# A zero-length segment would divide by zero; the table has none, but a
		# future author editing the polyline should not have to know that.
		var t := 0.0 if len_sq <= 0.0 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
	return best


static func is_dry(x: float, z: float) -> bool:
	"""Is this world XZ standing on a bridge deck or on Margaret Island? Up to
	eight rect tests, four compares each — see `DRY_RECTS`."""
	for i in range(DRY_RECTS.size()):
		var r: Rect2 = DRY_RECTS[i]
		if x >= r.position.x and x <= r.position.x + r.size.x \
				and z >= r.position.y and z <= r.position.y + r.size.y:
			return true
	return false


static func danube_wet(x: float, z: float) -> bool:
	"""
	Is this world XZ WATER? Inside the band and not on a dry rect.

	This is the CPU half of a two-language contract: `ground.gdshader` computes
	the same predicate from the same numbers, pushed to it as uniforms, and the
	blue you see has to be the water you wade. Edit one, edit the other.
	"""
	return danube_distance(x, z) < DANUBE_HALF_WIDTH and not is_dry(x, z)


static func plateau_top_at(x: float, z: float) -> float:
	"""
	The walking height at this world XZ: a plateau's `top` if it is standing on
	one, otherwise 0.0 — the flat world.

	The ramp is deliberately NOT included: a ramp is a tilted box whose surface
	height varies continuously across its own footprint, and a caller that wants
	"how high is the ground here" on a ramp wants the box, not this.
	"""
	for i in range(PLATEAUS.size()):
		var r: Rect2 = PLATEAUS[i]["rect"]
		if x >= r.position.x and x <= r.position.x + r.size.x \
				and z >= r.position.y and z <= r.position.y + r.size.y:
			return PLATEAUS[i]["top"]
	return 0.0


static func road_approach_point(terminal: Vector2, x: float) -> Vector2:
	"""
	The approach corridor, from the road's terminal station to the gate.

	The coin road's centreline Z is a function of the run seed — only station 0
	is fixed — so a FIXED city cannot simply wait at the end of a wandering road.
	This is the join: west of the terminal there is only the road, east of the
	gate there is only the avenue at z = 0, and in between the Z is eased from
	one to the other by a `smoothstep`, so the corridor meets the road with no
	kink at the terminal and no kink at the gate.

	Pure in (`terminal`, `x`), and therefore deterministic in the run seed
	through the terminal alone — which is what makes "the corridor reaches the
	gate for 50 seeds" a measurement.

	@param terminal: The terminal station's centre, (x, z).
	@param x: The world X to answer for.
	@return The corridor centreline point at that X, as (x, z).
	"""
	if x <= terminal.x:
		return terminal
	if x >= GATE.x:
		return Vector2(x, GATE.z)
	var t := smoothstep(terminal.x, GATE.x, x)
	return Vector2(x, lerpf(terminal.y, GATE.z, t))


# ponytail: TWO DELIBERATE DEFERRALS, recorded here so the next reader knows they
# are decisions and not oversights.
#
#   1. NO HORIZON IMPOSTORS. The bead says the city "may" have them. The tower's
#      fog-exempt impostor is manager-parented, and CLAUDE.md says the tower is
#      the ONE manager-parented exception and must stay one. A city impostor
#      would be a second lifetime model for the sake of a silhouette; the city is
#      chunk-streamed like everything else, and fog does the rest. Add one only
#      if somebody measures that the approach reads as empty.
#
#   2. FAUNA IS NOT EXCLUDED FROM THE RECT. `fauna_manager.gd` plans a detour
#      around the HQ by reading `tower_site()` / `TOWER_RADIUS`, and knows
#      nothing about this rect, so a giraffe herd can walk down Váci utca. It is
#      not a bug: fauna joins no group, has no collision and is parented to the
#      manager, so it cannot be grabbed, cannot block anything and cannot leak —
#      it is ambience in the wrong place. Bead `godot-test1-8gw.10` (the CROWDS
#      bead) is where the city's population is decided, and excluding the herds
#      belongs in the same pass that adds the citizens; doing it here would mean
#      editing a file this bead's branch has no other reason to touch.
