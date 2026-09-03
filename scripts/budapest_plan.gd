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
	# The Liberty Bridge's deck starts at 2380 and not at the 2360 the keystone
	# authored, because bead .4 put STONE on these rects: Gellért Hill's massif
	# ends at x = 2370, and a 2360 abutment buried the first 10 m of the western
	# approach inside 46 m of impassable rock with a cliff across the way onto it.
	# The whole rect moved east so the slot stays its centre (see BRIDGES).
	Rect2(2380.0, 684.0, 300.0, 32.0),    # Liberty Bridge deck
	Rect2(2470.0, -950.0, 130.0, 310.0),  # Margaret Island — dry land in the river
]

# ============================================================================
# SECTION 3b — THE FOUR BRIDGES' DECKS (bead godot-test1-8gw.4)
# ============================================================================

## A BRIDGE IS TWO FILES, and this table is the joint.
##
## The PYLONS, towers, chains, trusses, cutwaters and lions are
## `landmark_builders.gd`'s — placed on the `SLOTS` row of the same id, which is
## where a bridge IS. The DECK — the flat roadway you walk and the ramp at each
## end that gets you up onto it — is `endless_terrain.gd`'s, built off this table.
## Every one of those builders' docstrings says "the deck is bead .4's" and hangs
## its chains, its arches and its lamp standards at a roadway 12 m up; this is
## that roadway.
##
## THE DECK RECT IS ALREADY IN `DRY_RECTS`, so a row here names its INDEX rather
## than restating it. One rect, two readers: the band is punched out by it (in
## both languages) and the stone is built on it, and there is no second number to
## drift. `budapest_selfcheck` check 14 asserts each rect is centred on its own
## slot, so the deck and the ornament cannot come apart.
##
## THE ORDER IS THE RIVER'S, north to south — Margaret, Chain, Elisabeth,
## Liberty — which is the real one and also `DRY_RECTS`'s.
const BRIDGES: Array = [
	{"id": "margaret_bridge", "dry": 0},
	{"id": "chain_bridge", "dry": 1},
	{"id": "elisabeth_bridge", "dry": 2},
	{"id": "liberty_bridge", "dry": 3},
]

## The deck's WALKING HEIGHT, and it is 12 m because the ORNAMENT SAYS SO. The
## Chain Bridge's hangers and the Elisabeth's both stop at y = 12, the Liberty's
## river piers are 12 m tall, the Margaret's lamp standards start at 12 and its
## arches spring from 11. A deck anywhere else would leave every one of them
## hanging in air or buried in stone, and none of that is data this file can read
## — so the number is authored here, and check 14 is what pins the ornament and
## the roadway to one XZ position.
const BRIDGE_DECK_TOP: float = 12.0

## The RAMPED APPROACH at each end of a deck, in metres of X.
##
## No jump gates, indoors or out: `CharacterBody3D` cannot climb a step at all,
## so the 12 m rise is a tilted slab exactly like a plateau's — the same helper,
## the same slice arithmetic, the same flushness check. 48 m gives a slope of
## 0.25, comfortably under `TowerInterior.PLAN_RAMP_MAX_SLOPE` (check 14 reads it
## from there rather than restating it) and a touch steeper than the two hills,
## which is right: a bridge approach is a ramp, a hillside is a road.
##
## BOTH RAMPS LIVE INSIDE THE DECK RECT, and that is the whole reason the approach
## needs no new dry rows and no shader edit. A deck rect overhangs the 240 m band
## by 21-41 m at both ends (check 14 measures it), so the ramp's FOOT stands on
## the bank while its head reaches out over the water — which is what a bridge
## approach is — and every metre of it is already punched out of the river.
const BRIDGE_RAMP_RUN: float = 48.0


static func bridge_deck(row: Dictionary) -> Rect2:
	"""The deck rect of a `BRIDGES` row — its `DRY_RECTS` entry, never a copy."""
	return DRY_RECTS[int(row["dry"])]


static func bridge_ramp(row: Dictionary, east: bool) -> Rect2:
	"""
	One of a bridge's two ramped approaches, in world XZ.

	@param row: a `BRIDGES` row.
	@param east: the east ramp (which rises WESTWARD) rather than the west one.
	@return the ramp's footprint — full deck width, `BRIDGE_RAMP_RUN` of X, at the
	        deck rect's own end.
	"""
	var d := bridge_deck(row)
	var x := d.end.x - BRIDGE_RAMP_RUN if east else d.position.x
	return Rect2(x, d.position.y, BRIDGE_RAMP_RUN, d.size.y)


static func bridge_flat(row: Dictionary) -> Rect2:
	"""The level part of a bridge's deck: what is left of the rect between the two
	ramps. Every shipped row is 290 m or longer against a 96 m pair of ramps, and
	check 14 fails a row whose ramps met in the middle."""
	var d := bridge_deck(row)
	return Rect2(d.position.x + BRIDGE_RAMP_RUN, d.position.y,
			d.size.x - 2.0 * BRIDGE_RAMP_RUN, d.size.y)


static func bridge_surface_y(row: Dictionary, x: float) -> float:
	"""
	The walking height of a bridge's deck at a world X: 0 at either end of the
	rect, `BRIDGE_DECK_TOP` across the middle, linear up each ramp.

	The IDEAL the built boxes are measured against (check 14), and the one place
	the deck's profile is written down. Answers for the flat span and both ramps
	off one expression, because the two ramps are the same climb mirrored.
	"""
	var d := bridge_deck(row)
	var from_end := minf(x - d.position.x, d.end.x - x)
	return clampf(from_end / BRIDGE_RAMP_RUN, 0.0, 1.0) * BRIDGE_DECK_TOP


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
##
## AND A HILL MAY NOT STAND IN THE RIVER. `is_river_at()` is XZ-only, so a lid at
## y = 30 standing over the band would WADE — the exact bug `DRY_RECTS` exists for,
## one axis further out — and `spawn_danube_crocodiles_in_chunk` re-tests only
## `danube_wet()`, so it would drop a crocodile inside 30 m of solid stone. Neither
## symptom is worth a mechanism when the rects are authored: both hills simply stop
## short of the band, with margin, and `budapest_selfcheck` check 11 measures every
## rect and every ramp against `DANUBE_HALF_WIDTH` so a future author who widens one
## is told rather than discovering it in the water.
const PLATEAUS: Array = [
	{
		"id": "castle_hill",
		# 370 m, not the 400 the real hill's bank would take: 400 puts the SE corner
		# 101 m from the polyline, 19 m inside the band. 370 clears it by 11 m.
		"rect": Rect2(1970.0, -860.0, 370.0, 800.0),
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

## Spacing of the CITY's own street coins — the avenue lines and the bridge decks.
## It is a SECOND constant and not the one above, because the two lines are two
## different things: the corridor above is a GUIDE from the road's terminal to the
## gate and has to read as a trail, while the city's is a REWARD scattered over a
## 2.2 km grid the player already knows how to navigate.
##
## OWNER, 2026-09-04: "coins should be really rare in Budapest". At the corridor's
## 8 m the ~18 avenues each way carried thousands of pickups and Pest read as a
## carpet; at 64 m an avenue offers one coin per city block, which is a thing you
## walk to rather than through. This is a DESIGN change to entity counts, which is
## the one reason the performance conventions allow them to move at all.
##
## IT IS ALSO WIDER THAN STREET_PITCH (62 m), AND THAT IS WHAT MAKES THE GEM RULE
## PURE PARITY — see _city_square_here in endless_terrain.gd: at most one coin can
## fall in any one cross-street's span, so "is this coin at a square" stops being a
## distance and becomes the parity of the two nearest street lines.
const CITY_STREET_COIN_SPACING: float = 64.0

# ----------------------------------------------------------------------------
# SECTION 5b — THE BLOCKS (bead godot-test1-8gw.9)
# ----------------------------------------------------------------------------
#
# THE GRID IS THE LEVEL EDITOR, AND IT IS ARITHMETIC RATHER THAN A TABLE.
#
# The owner's direction was "Budapest seems really empty, but it is full of multi
# storey buildings in fact — like what we can see on google map walking mode". A
# street-view city is not a scatter of houses; it is a CONTINUOUS STREET WALL with
# a hollow courtyard behind it, which is exactly what a Pest block is. So the
# grid `STREET_PITCH` already parameterises stops being a parameter and becomes
# the thing itself: every square between four street lines is a BLOCK, and every
# block the city has not reserved for something else is FILLED.
#
# A CELL IS AN INTEGER PAIR, AND THAT IS THE WHOLE ADDRESSING SCHEME. Cell
# (k, m) spans x in [street_x(k), street_x(k + 1)] and z in [street_z(m),
# street_z(m + 1)], and `block_rect()` insets that by `AVENUE_HALF_WIDTH` on all
# four sides — so the 16 m street around every grid line is CLEAR BY
# CONSTRUCTION and not by a check. That is the answer to "a solid piece must
# never sever a street": nothing is ever built on one. `budapest_selfcheck`
# check 15 sweeps the collision shapes anyway, because "by construction" is a
# claim and a sweep is a measurement.
#
# THE ORIGIN IS THE GATE, so street row m = 0 IS the avenue this file already
# draws at z = 0 and street column k = 0 is the city's west edge. There is no
# second alignment to keep in step, and the one street bead .3 shipped is row 0
# of the grid bead .9 fills in around it.
#
# NOTHING HERE IS SEEDED OR HASHED — check 1 bans the hashing CALL in this file
# outright, which is why the per-cell facade stream lives in `endless_terrain.gd`
# (its `CITY_BLOCK_SALT`, the tower furniture precedent) and only the LAYOUT
# lives here. The layout is pure integer arithmetic over authored constants.

## How deep a street wall is: the wing that faces the street, in metres.
##
## A block's buildable interior is `STREET_PITCH - 2 * AVENUE_HALF_WIDTH` = 46 m,
## so 13 m of wing on all four sides leaves a 20 m COURTYARD, which is hollow and
## which nothing ever builds in. That hollow is the point: it is what makes a
## block a ring of buildings rather than a solid 46 m cube, it is what the eye
## reads through a gateway, and it is 4 boxes per block instead of 1 giant one.
const BLOCK_WING_DEPTH: float = 13.0

## The PAVEMENT: how far a facade stands back from the edge of the carriageway.
##
## `AVENUE_HALF_WIDTH` is the CARRIAGEWAY, and a facade built flush against it is
## a wall standing on the last metre of the one corridor bead .3 promises —
## check 13 says so, in metres, the moment the blocks land. It is also where the
## proud bands go: a balcony course stands 0.52 m off its wall and a cornice
## 0.46 m, and a balcony hanging over the middle of a street is a thing you walk
## your head through. 1.2 m clears the widest of them with room to spare and
## turns "the street is clear" from a boundary case into a measured margin.
const BLOCK_PAVEMENT: float = 1.2

## How many buildings one side of a block is broken into. Two, because a single
## 46 m facade box reads as a wall and two segments at different heights read as
## a STREET — a stepped roofline is the cheapest thing that says "these are
## separate houses" without a box per window. Raising it multiplies the block's
## box count directly, so it is measured against `CITY_CHUNK_BOX_BUDGET`.
const BLOCK_SEGMENTS: int = 2

## Storeys, as (min, max) inclusive, either side of the river. Pest is the
## eclectic 4-6 storey grid the owner asked for; Buda is 2-3 storey hillside
## houses under the castle. `is_buda()` is what picks, off the Danube's own
## polyline, so a plan that reshaped the river reshapes the skyline with it.
const BLOCK_STOREYS_PEST := Vector2i(4, 6)
const BLOCK_STOREYS_BUDA := Vector2i(2, 3)

## Every Nth street line is an AVENUE — the routes the city's coins ride.
##
## COINS ARE THE HEADLINE SCORE since bead .1 retired distance, and bead .3's
## approach line stops at the Danube's west bank, so the whole 1.4 km of Pest
## shipped with no coin source at all. Putting coins on EVERY street would be
## ~35 lines each way and a coin every 8 m of a 2.2 km city; putting them on
## every FOURTH line is one avenue every 248 m, which is a route you follow
## rather than a carpet you stand in. Nine avenues each way over the rect.
const CITY_AVENUE_EVERY: int = 4

## Which avenues carry a GEM where they cross: every other one on each axis, so a
## quarter of the squares — ~496 m apart along an avenue. Grid parity and nothing
## else (no hash, no seed: the city is authored, and budapest_selfcheck check 1
## reads this file as text to keep it that way).
const CITY_GEM_AVENUE_EVERY: int = CITY_AVENUE_EVERY * 2


static func street_x(k: int) -> float:
	"""The world X of street column `k`. Column 0 is the gate's own meridian."""
	return GATE.x + float(k) * STREET_PITCH


static func street_z(m: int) -> float:
	"""The world Z of street row `m`. Row 0 is the avenue out of the gate."""
	return GATE.z + float(m) * STREET_PITCH


static func block_cell(x: float, z: float) -> Vector2i:
	"""Which block cell a world XZ falls in — a point on a street belongs to the
	cell east/south of it, which is a convention and not a decision: callers ask
	for a RANGE of cells and take the union."""
	return Vector2i(floori((x - GATE.x) / STREET_PITCH),
			floori((z - GATE.z) / STREET_PITCH))


static func block_rect(cell: Vector2i) -> Rect2:
	"""
	The BUILDABLE interior of one block: the square between four street lines,
	inset by `AVENUE_HALF_WIDTH + BLOCK_PAVEMENT` on every side.

	The inset IS the street. Every facade this plan describes lies inside this
	rect, so the 16 m carriageway around each grid line — plus a metre of
	pavement either side for the balconies to hang over — can never be built on,
	which is the whole of the "a solid piece must never sever a street" rule.
	"""
	var inset := AVENUE_HALF_WIDTH + BLOCK_PAVEMENT
	return Rect2(street_x(cell.x) + inset, street_z(cell.y) + inset,
			STREET_PITCH - 2.0 * inset, STREET_PITCH - 2.0 * inset)


static func block_courtyard(cell: Vector2i) -> Rect2:
	"""The hollow in the middle of a block — the buildable rect less one
	`BLOCK_WING_DEPTH` wing on every side. Nothing is ever built here; check 15
	measures it empty."""
	return block_rect(cell).grow(-BLOCK_WING_DEPTH)


static func is_avenue(i: int) -> bool:
	"""Is street line `i` (a column or a row — the grid is square) an AVENUE, i.e.
	one of the lines the city's coin routes run down?"""
	return i % CITY_AVENUE_EVERY == 0


static func is_gem_avenue(i: int) -> bool:
	"""Is street line `i` one of the avenues whose crossings carry a GEM? A subset
	of is_avenue by construction, so a gem is always on a coin route."""
	return i % CITY_GEM_AVENUE_EVERY == 0


static func river_x_at(z: float) -> float:
	"""
	Where the Danube's centreline is at this Z, by walking the polyline.

	@return the interpolated X, clamped to the end segments north and south of the
	        authored span.

	The polyline's Z is strictly increasing (check 2 would have nothing to say
	about a river that doubled back, so this is the plan's shape and not a
	coincidence), which is what makes one linear scan enough.
	"""
	var last: int = DANUBE.size() - 1
	if z <= (DANUBE[0] as Vector2).y:
		return (DANUBE[0] as Vector2).x
	if z >= (DANUBE[last] as Vector2).y:
		return (DANUBE[last] as Vector2).x
	for i in range(last):
		var a: Vector2 = DANUBE[i]
		var b: Vector2 = DANUBE[i + 1]
		if z >= a.y and z <= b.y:
			return a.x + (b.x - a.x) * (z - a.y) / maxf(b.y - a.y, 0.001)
	return (DANUBE[last] as Vector2).x


static func is_buda(x: float, z: float) -> bool:
	"""West of the Danube — the hillside half of the city, 2-3 storeys instead of
	Pest's 4-6. Asked of the river's OWN polyline so the skyline follows a plan
	that reshapes it."""
	return x < river_x_at(z)


static func block_buildable(cell: Vector2i) -> bool:
	"""
	May this block be FILLED with buildings?

	@param cell: the block's integer coordinates.
	@return false when the block's rect is outside the city, meets a landmark
	        slot's disc, a plateau or its ramp, the gate district, a dry rect
	        (a bridge deck, Margaret Island) or the Danube's band.

	ONE PREDICATE, AND EVERY REFUSAL IN IT IS A THING THAT IS ALREADY THERE. A
	block over the Parliament's disc would clip through it; a block on a plateau
	would stand inside 30 m of solid stone; a block in the band would be a street
	wall you WADE through, because `is_river_at()` is XZ-only. The gate district
	is refused because bead .3 authored sixteen houses there by hand and this
	would build over them.

	THE RIVER IS SAMPLED ON NINE POINTS, not on the centre. The band is 240 m
	wide against a 46 m block, so corners-plus-edge-midpoints is comfortably
	enough to catch a block whose corner dips in, and the alternative — a proper
	rect-to-polyline distance — is arithmetic nobody needs for a 20:1 ratio.
	"""
	var r := block_rect(cell)
	var city := rect()
	if not (city.has_point(r.position) and city.has_point(r.end)):
		return false
	if r.intersects(DISTRICT):
		return false
	for row_v: Variant in PLATEAUS:
		var row: Dictionary = row_v
		if r.intersects(row["rect"] as Rect2) or r.intersects(row["ramp"] as Rect2):
			return false
	for dry_v: Variant in DRY_RECTS:
		if r.intersects(dry_v as Rect2):
			return false
	for slot_v: Variant in SLOTS:
		var slot: Dictionary = slot_v
		var pos: Vector3 = slot["pos"]
		var near := Vector2(clampf(pos.x, r.position.x, r.end.x),
				clampf(pos.z, r.position.y, r.end.y))
		if Vector2(pos.x - near.x, pos.z - near.y).length() < float(slot["radius"]):
			return false
	for p: Vector2 in [
			r.position, Vector2(r.end.x, r.position.y),
			Vector2(r.position.x, r.end.y), r.end, r.get_center(),
			Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y),
			Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]:
		if danube_distance(p.x, p.y) < DANUBE_HALF_WIDTH:
			return false
	return true


static func block_wing(cell: Vector2i, side: int) -> Rect2:
	"""
	One of a block's four street walls, in world XZ.

	@param side: 0 north (-Z face), 1 south (+Z), 2 west (-X), 3 east (+X).

	The north and south wings span the block's FULL width and the two side wings
	fill what is left between them, so the four tile the ring exactly: no overlap
	at the corners (which would be two boxes in one metre) and no gap (which would
	be a hole in the street wall you could see the courtyard through).
	"""
	var r := block_rect(cell)
	var d := BLOCK_WING_DEPTH
	match side:
		0: return Rect2(r.position.x, r.position.y, r.size.x, d)
		1: return Rect2(r.position.x, r.end.y - d, r.size.x, d)
		2: return Rect2(r.position.x, r.position.y + d, d, r.size.y - 2.0 * d)
		_: return Rect2(r.end.x - d, r.position.y + d, d, r.size.y - 2.0 * d)


static func block_wing_outward(side: int) -> Vector2:
	"""The direction a wing's street face looks in — the axis its shopfront band
	and its doorways stand proud of."""
	match side:
		0: return Vector2(0.0, -1.0)
		1: return Vector2(0.0, 1.0)
		2: return Vector2(-1.0, 0.0)
		_: return Vector2(1.0, 0.0)

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
## three slots standing on a plateau (buda_castle, matthias, citadella), which
## carry that plateau's `top`. Check 2 prints the count.
##
## `radius` is the registry's OWN declared radius, copied. Check 2 asserts the two
## agree, so a later edit to a shipped builder's radius fails this build instead
## of silently overhanging into the street.
##
## ALL 22 ROWS NOW CARRY A BUILDER. Rows 15-21 were RESERVATIONS through waves A
## and B — a position and a generous radius, `"builder": ""`, skipped by the
## streamer and exempt from the registry check, which is the whole of "leave the
## slot empty". Wave C (bead `godot-test1-8gw.8`) landed their geometry, so each
## took its builder's name and its registry radius, which is TIGHTER than the
## reservation was in every case (110 -> 62, 100 -> 54, 90 -> 60, 70 -> 52,
## 50 -> 42, 40 -> 32, 40 -> 38): a reservation is authored generously on purpose
## and the real building is measured. The empty-builder path is still live code —
## it is what a future 23rd place would use — and check 2 still exempts one.
const SLOTS: Array = [
	# ---- the Danube core ---------------------------------------------------
	{"id": "parliament", "builder": "_city_parliament", "pos": Vector3(2760.0, 0.0, -480.0), "radius": 151.0},
	{"id": "buda_castle", "builder": "_city_buda_castle", "pos": Vector3(2170.0, 30.0, -240.0), "radius": 156.0},
	{"id": "matthias", "builder": "_city_matthias_bastion", "pos": Vector3(2170.0, 30.0, -640.0), "radius": 80.0},
	{"id": "citadella", "builder": "_city_citadella", "pos": Vector3(2230.0, 46.0, 760.0), "radius": 120.0},
	{"id": "margaret_island", "builder": "_city_margaret_island", "pos": Vector3(2535.0, 0.0, -880.0), "radius": 56.0},
	{"id": "chain_bridge", "builder": "_city_chain_bridge", "pos": Vector3(2475.0, 0.0, 0.0), "radius": 124.0},
	# 2530, moved east with its deck rect — see the note on DRY_RECTS row 3.
	{"id": "liberty_bridge", "builder": "_city_liberty_bridge", "pos": Vector3(2530.0, 0.0, 700.0), "radius": 104.0},
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
	{"id": "heroes_square", "builder": "_city_heroes_square", "pos": Vector3(3520.0, 0.0, -520.0), "radius": 62.0},
	{"id": "vajdahunyad", "builder": "_city_vajdahunyad", "pos": Vector3(3680.0, 0.0, -340.0), "radius": 54.0},
	{"id": "szechenyi_bath", "builder": "_city_szechenyi_baths", "pos": Vector3(3620.0, 0.0, -760.0), "radius": 60.0},
	# ---- the baths and the odd ones ----------------------------------------
	# THE TWO BATHS MOVED WHEN THEIR BUILDERS LANDED, and the reason is the same
	# one that moved the Liberty Bridge's deck: a reservation is a position nothing
	# has ever been built at, and both of these turned out to be positions where
	# the stone would not fit. Gellért was authored 136.9 m from the polyline with
	# a 52 m disc and Rudas 133.9 m with a 42 m one, so both platforms overhung the
	# 240 m band — and `is_river_at()` is XZ-only, so you WADE standing on them.
	# Rudas was worse: its disc also reached into Gellért Hill's massif, which is
	# solid stone to its 46 m lid.
	#
	# Both slid along the bank at the foot of the hill, which is where they really
	# are: Gellért 40.3 m south-west (175.1 m out, 3.1 m of disc to spare), Rudas
	# 49.5 m north-west past the massif's corner (165.0 m out, 3.0 m to spare).
	# Check 14 measures the stone rather than the disc and holds both there.
	{"id": "gellert_bath", "builder": "_city_gellert_baths", "pos": Vector3(2380.0, 0.0, 1005.0), "radius": 52.0},
	{"id": "rudas_bath", "builder": "_city_rudas_baths", "pos": Vector3(2335.0, 0.0, 525.0), "radius": 42.0},
	{"id": "shoes_on_the_danube", "builder": "_city_shoes_on_danube", "pos": Vector3(2640.0, 0.0, -300.0), "radius": 32.0},
	{"id": "budapest_eye", "builder": "_city_budapest_eye", "pos": Vector3(2870.0, 0.0, -60.0), "radius": 38.0},
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
		var d := segment_distance(p, DANUBE[i], DANUBE[i + 1])
		if d < best:
			best = d
	return best


static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	"""
	Distance from `p` to the SEGMENT ab — project, clamp the parameter to [0, 1].

	The one home of that arithmetic on this side: the Danube polyline and the
	approach corridor's polyline both want it, and a second copy is how the two
	drift. Written entirely in `Vector2` so every intermediate is f32 and matches
	what the shader computes.
	"""
	var ab := b - a
	var len_sq := ab.length_squared()
	# A zero-length segment would divide by zero; neither caller produces one
	# today, but a future author editing a polyline should not have to know that.
	var t := 0.0 if len_sq <= 0.0 else clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


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


## How finely the corridor is sampled when it is measured as a CURVE rather than
## read at one X: the sub-step, in metres of X, used by road_approach_distance()
## and approach_coin_line(). The corridor spans GATE.x - terminal.x (~150 m), so
## this is ~150 segments — far below the smoothstep's curvature and cheap enough
## to walk on every clearance query.
const APPROACH_SAMPLE_STEP: float = 1.0


static func road_approach_distance(terminal: Vector2, p: Vector2) -> float:
	"""
	Shortest distance from a world XZ to the approach CORRIDOR — the corridor read
	as a curve, not sampled at the point's own X.

	@param terminal: The terminal station's centre, (x, z).
	@param p: The world point, as (x, z).
	@return Distance to the nearest point of the corridor centreline.

	WHY IT IS NOT `absf(p.y - road_approach_point(terminal, p.x).y)`. The road's Z
	at the terminal is seeded and can be hundreds of metres off the avenue's line,
	so the smoothstep has to cover that drop in 150 m of X — measured over 500
	seeds the corridor's own maximum slope reaches 6.4 m of Z per metre of X. On a
	stretch that steep the nearest point of the corridor is nowhere near the
	candidate's X, and the same-X reading overstates the distance by
	sqrt(1 + slope^2): a massif reading a comfortable 24 m can be under 4 m from
	the walk it is supposed to leave alone. So the corridor is walked as a
	polyline and every segment is asked, exactly as the Danube is.

	Pure in (`terminal`, `p`), like road_approach_point itself.
	"""
	var best := INF
	var prev := road_approach_point(terminal, terminal.x)
	var x := terminal.x
	while x < GATE.x:
		x = minf(x + APPROACH_SAMPLE_STEP, GATE.x)
		var cur := road_approach_point(terminal, x)
		var d := segment_distance(p, prev, cur)
		if d < best:
			best = d
		prev = cur
	return best


static func approach_coin_line(terminal: Vector2, start_x: float, east_x: float) -> PackedVector2Array:
	"""
	The approach + avenue coin line: points at a uniform CITY_COIN_SPACING pitch
	ALONG THE CORRIDOR, from `start_x` east to `east_x`.

	@param terminal: The terminal station's centre, (x, z).
	@param start_x: World X of the first coin (the road's terminal cap).
	@param east_x: World X to stop at (the Danube's west bank).
	@return The coin centres, in increasing X.

	WHY IT IS NOT `start_x + n * CITY_COIN_SPACING`. Stepping the PITCH IN X makes
	the physical gap 8 * sqrt(1 + slope^2), and the corridor's slope is seeded (see
	road_approach_distance) — on a steep seed that is a 50 m gap between coins on
	the one stretch of the walk that has nothing else to read. A trail is a pitch
	along its own length, so the corridor is resampled by ARC LENGTH: sub-step in
	X, accumulate the distance actually travelled, and emit a coin every
	CITY_COIN_SPACING metres of it (interpolating inside the sub-step, so the pitch
	is exact and not quantised to the step).

	Still ZERO RNG and still pure in (`terminal`, `start_x`, `east_x`) — the run's
	seed reaches this line only through the terminal, exactly as before.
	"""
	var pts := PackedVector2Array()
	if east_x <= start_x:
		return pts
	var prev := road_approach_point(terminal, start_x)
	pts.append(prev)
	var carried := 0.0  # arc length walked since the last coin
	var x := start_x
	while x < east_x:
		x = minf(x + APPROACH_SAMPLE_STEP, east_x)
		var cur := road_approach_point(terminal, x)
		var seg := prev.distance_to(cur)
		# A sub-step can be long enough for several coins when the corridor is
		# steep, so this is a loop and not an `if`.
		while seg > 0.0 and carried + seg >= CITY_COIN_SPACING:
			var t := (CITY_COIN_SPACING - carried) / seg
			prev = prev.lerp(cur, t)
			pts.append(prev)
			carried = 0.0
			seg = prev.distance_to(cur)
		carried += seg
		prev = cur
	return pts


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
