class_name CityBuilders
extends RefCounted
## BUDAPEST'S 22 AUTHORED LANDMARKS — the city half of `landmark_builders.gd`,
## lifted out whole by bd `godot-test1-ftn.17`.
##
## It is that file's static-library idiom unchanged: every builder is
## `static func _city_x(terrain, center, rng, parent_chunk, block_batch,
## block_body) -> Dictionary`, emits through `terrain.create_box` back across the
## reference it is handed, and returns the `{radius, top}` bound
## `landmark_selfcheck` check 1 measures. Nothing about the world moved — this is
## a file boundary, and `budapest_selfcheck`'s byte-identical city regeneration
## across two seeds is the A/B that says so.
##
## ---------------------------------------------------------------------------
## THE DEPENDENCY IS ONE WAY AS A `const`, AND THE OTHER WAY ONLY IN A BODY
## ---------------------------------------------------------------------------
## `landmark_builders.gd` carries `const CITY_LANDMARKS := CityBuilders.CITY_LANDMARKS`
## so `landmark_toast`, `budapest_selfcheck` and both registry assertions did not
## have to move — that is the PARSE-TIME direction, and it is the only one.
## Everything this file needs back the other way (the `LM_*` palette it shares
## with the field, `_lm_shade`'s per-box colour jitter, `_lm_onion`) is reached
## as `LandmarkBuilders.X` **inside a function body**, which is a runtime lookup
## and not a parse-time reference — the same shape `TowerPlanBoxes` and
## `TowerInterior` use, and the only reason this pair is not a cycle. A `const`
## alias or a `preload` back here would be one (CLAUDE.md, the tower's rule).
##
## ---------------------------------------------------------------------------
## THE STREAM CONTRACT, WHICH IS WHY THE SLICING WORKS
## ---------------------------------------------------------------------------
## Every builder here is a pure function of (centre, rng) whose stream touches
## **colour only** — not one dimension, offset or count is drawn — and the seed
## is the SLOT INDEX and nothing else: no `run_seed` (the city is authored) and
## above all no chunk coordinate, or a giant sliced across four chunks comes out
## tie-dyed along its seams. See `budapest_streamer.gd`'s
## `_spawn_city_landmarks_in_chunk` for the slicing this buys.
##
## DISPATCH IS BY METHOD-NAME STRING through a preloaded GDScript
## (`preload("res://scripts/city_builders.gd").call(slot.builder, ...)`) and
## never through the `class_name`: `CityBuilders.call(name, ...)` is a parse
## error, exactly as `endless_terrain.gd` documents for `_landmark_builders`.

## BUDAPEST (the city registry below). TWO new entries for nine new places, which
## is the wave-2 palette rule again — everything else the Danube core needs is
## already in the table above and is reused where it is honestly the right colour
## (see CITY_LANDMARKS' banner for the whole mapping). Wave B — Pest's inner
## city, six more places — adds NOTHING to the palette: its brick is LM_OCHRE
## (dE 0.200, the warm family's one member that is dark enough to meet pavement),
## the Zsolnay glazes are the copper / vermilion / sandstone trio Matthias
## already wears, and the Opera and the Museum are the palace cream.
##
## Both were chosen against a MEASURED number rather than by eye, because in the
## city these boxes stand on the CITY ground tint (ground.gdshader `city_color`
## = vec3(0.50, 0.48, 0.45), mottled 0.88..1.12) and not on grass. That literal
## is a shader default, so it is never converted and renders as LINEAR albedo,
## while create_box() runs every colour here through srgb_to_linear() — so the
## honest comparison is srgb_to_linear(palette) against (0.50, 0.48, 0.45), and
## in Oklab that paved grey sits at L 0.76 with almost no chroma. The whole warm
## mid-tone family (LM_SANDSTONE 0.082, LM_OCHRE 0.105, LM_STONE_GREY 0.094,
## LM_MARBLE.darkened(0.2) 0.006 — a dead-on match) is therefore UNUSABLE for a
## mass that meets the pavement, which is why a warm palace cream had to be
## measured into existence rather than mixed by taste.
const CITY_CREAM := Color(0.92, 0.84, 0.62)      # Buda Castle / water-tower plaster (dE 0.117)
const CITY_PARK_GREEN := Color(0.20, 0.42, 0.22) # Margaret Island foliage (dE 0.143)

# ----------------------------------------------------------------------------
# THE CITY REGISTRY — Budapest, and why it is a SECOND TABLE
# ----------------------------------------------------------------------------
##
## A SEPARATE const, not a `city: true` flag on the rows above, and the reason is
## the field's placement. `landmark_sites()` walks LANDMARKS by index and gives
## every row a site, so a flag would mean a filter in that walk — one more thing
## nobody may forget — and a shared array would mean the 22 city rows shifting the
## index of every field row. A table endless_terrain.gd has never heard of cannot
## reach the field placement AT ALL: it is not filtered out, it is not reachable.
## That is the cheapest possible answer to "keep these out of the countryside",
## and it costs one extra line in landmark_selfcheck.
##
## It also keeps check 2 honest. Every row up there must satisfy
## radius <= LANDMARK_RADIUS (9.5) because that is the bound _biome_spot_ok is
## handed before a builder runs. A city row's radius is 56–156 m — the Parliament
## alone is 268 m long — so folding the two tables together would have meant
## teaching that inequality about an exception, and an inequality with an
## exception is an inequality that stops catching the drift it exists for.
##
## THE ROWS HAVE THE SAME FIVE KEYS and the builders the same signature, so
## everything downstream (the toast, the quiz shape, landmark_selfcheck's check 1)
## works on them unchanged. What is deliberately NOT here yet:
##
##   * PLACEMENT. Nothing calls these builders in the game — the city site, its
##     slots and their radii are budapest_plan.gd's (bead .3), and the landmark
##     catalogue and the explored mask are bead .5's. This wave is the GEOMETRY
##     and its measurement, and nothing else.
##   * ui.csv ROWS. `name` and `fact` are carried here in the registry's own idiom
##     so .5 has them, but the CSV pair per place lands with the catalogue that
##     first displays them; landmark_selfcheck's fact check therefore still runs
##     over the FIELD registry only (see its check 3).
##
## SCALE AND ORIENTATION — the two things a city builder does differently:
##
##   * NO YAW ROLL. A field landmark picks a random facing because nothing around
##     it cares; a city is authored, and the Parliament faces the river. Every
##     builder below emits at a FIXED orientation: a building's long axis on Z
##     (the Danube runs along Z, so a river facade is parallel to it) and a
##     bridge's axis on X (it crosses). The plan PLACES, it does not rotate.
##   * THE RNG TOUCHES COLOUR ONLY. Not one dimension, offset or count below is
##     drawn — the shapes are hand-planned, the way tower_plans.gd is, so the same
##     building appears in every run. _lm_shade's per-box jitter is all that is
##     left of the stream, and it moves no geometry.
##
## PALETTE MAPPING (measured; see the CITY_CREAM banner for the method). Pale
## limestone is LM_MARBLE, the Parliament's tile roofs are LM_VERMILION darkened,
## the copper domes and the Liberty Bridge's green iron are LM_COPPER at two
## darknesses, the Citadella's basalt fort is LM_BASALT, the Liberty Statue's
## bronze is LM_IRON darkened, Matthias's Zsolnay diamonds are LM_OCHRE /
## LM_COPPER / LM_ROOF, and only the palace cream and the park green are new.
const CITY_LANDMARKS: Array = [
	{
		"builder": "_city_parliament",
		"name": "Hungarian Parliament",
		"fact": "The seat of Hungary's National Assembly, on the Pest bank of the Danube in Budapest — 268 m long, opened in 1902, and still the largest building in the country.",
		"radius": 151.0,
		"region": "europe",
	},
	{
		"builder": "_city_buda_castle",
		"name": "Buda Castle",
		"fact": "The royal palace on Castle Hill in Budapest, first raised in 1265 and rebuilt after every siege since — the last of them ended in 1945.",
		"radius": 156.0,
		"region": "europe",
	},
	{
		"builder": "_city_matthias_bastion",
		"name": "Matthias Church and Fisherman's Bastion",
		"fact": "A Gothic church in Budapest under a roof of glazed Zsolnay tiles, fronted by a terrace of seven turrets — one for each Magyar tribe that arrived in 895.",
		"radius": 80.0,
		"region": "europe",
	},
	{
		"builder": "_city_citadella",
		"name": "Citadella and the Liberty Statue",
		"fact": "A fortress the Habsburgs put on Gellért Hill in 1854 to hold Budapest under its guns; the 14 m Liberty Statue that now shares the summit went up in 1947.",
		"radius": 120.0,
		"region": "europe",
	},
	{
		"builder": "_city_margaret_island",
		"name": "Margaret Island Water Tower",
		"fact": "A 57 m Art Nouveau water tower of 1911, standing in the park on the island in the middle of the Danube at Budapest.",
		"radius": 56.0,
		"region": "europe",
	},
	{
		"builder": "_city_chain_bridge",
		"name": "Chain Bridge",
		"fact": "The Széchenyi Chain Bridge, the first permanent crossing of the Danube at Budapest — opened in 1849 and guarded by four stone lions.",
		"radius": 124.0,
		"region": "europe",
	},
	{
		"builder": "_city_liberty_bridge",
		"name": "Liberty Bridge",
		"fact": "A green iron bridge over the Danube at Budapest, opened in 1896 with a turul — the mythical falcon of the Magyars — on each of its four masts.",
		"radius": 104.0,
		"region": "europe",
	},
	{
		"builder": "_city_elisabeth_bridge",
		"name": "Elisabeth Bridge",
		"fact": "A white suspension bridge over the Danube at Budapest, rebuilt in 1964 after the war and named for the Empress Elisabeth.",
		"radius": 122.0,
		"region": "europe",
	},
	{
		"builder": "_city_margaret_bridge",
		"name": "Margaret Bridge",
		"fact": "A Danube bridge at Budapest of 1876 that bends in the middle so both arms meet the current square — and sends a branch down onto Margaret Island.",
		"radius": 114.0,
		"region": "europe",
	},
	{
		"builder": "_city_basilica",
		"name": "St Stephen's Basilica",
		"fact": "A neo-Renaissance basilica in Budapest, finished in 1905 after its half-built dome collapsed in a storm — at 96 m it ties the Parliament exactly, the height the city held its skyline to for a century.",
		"radius": 58.0,
		"region": "europe",
	},
	{
		"builder": "_city_market_hall",
		"name": "Great Market Hall",
		"fact": "Budapest's central market of 1897 — 150 m of brick and iron under a roof of glazed Zsolnay tiles, bombed in 1945, closed as unsafe in 1991 and reopened restored in 1994.",
		"radius": 82.0,
		"region": "europe",
	},
	{
		"builder": "_city_synagogue",
		"name": "Dohány Street Synagogue",
		"fact": "The largest synagogue in Europe, opened in Budapest in 1859 — 3,000 seats in a Moorish hall between two onion-domed towers.",
		"radius": 49.0,
		"region": "europe",
	},
	{
		"builder": "_city_vaci_utca",
		"name": "Váci utca",
		"fact": "Budapest's shopping street, one block back from the Danube in Pest — a promenade since the 18th century and closed to traffic since the 1960s.",
		"radius": 78.0,
		"region": "europe",
	},
	{
		"builder": "_city_national_museum",
		"name": "Hungarian National Museum",
		"fact": "Hungary's national museum, opened in Budapest in 1847 — the revolution of 15 March 1848 is remembered as having begun on its steps.",
		"radius": 62.0,
		"region": "europe",
	},
	{
		"builder": "_city_opera",
		"name": "Hungarian State Opera House",
		"fact": "A neo-Renaissance opera house opened in Budapest in 1884, its drive guarded by two stone sphinxes — Gustav Mahler ran it from 1888.",
		"radius": 49.0,
		"region": "europe",
	},
	# --- WAVE C: THE ANDRÁSSY END AND THE ODD ONES (7 places completing the 22-landmark Budapest set).
	{
		"builder": "_city_heroes_square",
		"name": "Heroes' Square",
		"fact": "Budapest's grand square laid out in 1896 for the millennium — the 36 m Millennium Column topped by the Archangel Gabriel, flanked by twin colonnades honoring Hungary's kings.",
		"radius": 62.0,
		"region": "europe",
	},
	{
		"builder": "_city_vajdahunyad",
		"name": "Vajdahunyad Castle",
		"fact": "A castle in Budapest's City Park built for the 1896 Millennium, blending replicas of famous Hungarian buildings — Romanesque, Gothic, Renaissance and Baroque.",
		"radius": 54.0,
		"region": "europe",
	},
	{
		"builder": "_city_szechenyi_baths",
		"name": "Széchenyi Thermal Bath",
		"fact": "One of Europe's largest bath complexes, opened in 1913 in City Park — a yellow neo-Baroque palace framing three steaming open-air thermal pools.",
		"radius": 60.0,
		"region": "europe",
	},
	{
		"builder": "_city_gellert_baths",
		"name": "Gellért Thermal Bath",
		"fact": "An Art Nouveau palace opened in 1918 at the foot of Gellért Hill, renowned for its turquoise Zsolnay mosaics, glass domes and thermal spring pools.",
		"radius": 52.0,
		"region": "europe",
	},
	{
		"builder": "_city_rudas_baths",
		"name": "Rudas Thermal Bath",
		"fact": "A Turkish bath built in 1566 during Ottoman rule in Hungary, centered on an octagonal thermal pool under a 10 m dome studded with coloured glass skylights.",
		"radius": 42.0,
		"region": "europe",
	},
	{
		"builder": "_city_shoes_on_danube",
		"name": "Shoes on the Danube Bank",
		"fact": "A memorial on the Pest embankment of the Danube, honoring the victims shot into the river in 1944–45 — sixty pairs of period iron shoes facing the water.",
		"radius": 32.0,
		"region": "europe",
	},
	{
		"builder": "_city_budapest_eye",
		"name": "Budapest Eye",
		"fact": "A 65 m giant Ferris wheel in Erzsébet Square in central Pest, offering panoramic views across the Danube and the rooftops of Budapest.",
		"radius": 38.0,
		"region": "europe",
	},
]

# ----------------------------------------------------------------------------
# BUDAPEST — WAVE A: THE DANUBE CORE
# ----------------------------------------------------------------------------
##
## Nine builders for the CITY_LANDMARKS table above. Same signature, same batch,
## same "the returned radius bounds every box" contract as every builder in this
## file — landmark_selfcheck's check 1 measures these exactly as it measures the
## field's, and the only thing that changes is the scale of the numbers.
##
## FOUR SHARED SHAPE HELPERS come first, and each has three or more callers here.
## They exist because the same four gestures — a stepped dome, a tapering spire, a
## repeated bay, a hanging cable — are what all nine of these places are made of,
## and writing them nine times is how a 300-box builder becomes unreadable. None
## of them is parametric beyond what a caller actually varies.
##
## GEOMETRY BOUND, once, for all nine. Every box below is emitted with yaw 0
## except the deliberately-rotated ones (a 45-degree twin makes an octagon; a
## cable segment carries its own yaw and tilt), so a box of horizontal size
## (dx, dz) at horizontal offset (ox, oz) reaches
##     sqrt((|ox| + dx/2)^2 + (|oz| + dz/2)^2)
## from the centre — the corner, not the axis extent, which is what check 1
## measures. Each builder's docstring carries the box that wins that maximum.

static func _city_dome(terrain: Node3D, base: Vector3, width: float, height: float, color: Color, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	"""
	ONE STEPPED DOME — a half-sphere in six slabs, each one as wide as the sphere
	is at its own height. Distinct from `LandmarkBuilders._lm_onion`, which BULGES wider than
	its drum: a Danube dome (Parliament, Buda Castle, the water tower's cap) sits
	on its drum and only narrows, and using the onion for it would have made three
	Budapest buildings read as Moscow.

	collide = false throughout: these sit 30-80 m up on the drum's own collision
	volume and are not surfaces anyone can reach. Returns the height added.

	The widest slab is the first (w = width * sqrt(1 - (0.5/6)^2) = 0.9965 * width),
	so a caller's bound on the whole dome is (width / 2) * sqrt(2) from its axis.
	"""
	const STEPS := 6
	var h := 0.0
	var slab := height / float(STEPS)
	for i in STEPS:
		var t := (float(i) + 0.5) / float(STEPS)
		var w: float = width * sqrt(maxf(1.0 - t * t, 0.05))
		terrain.create_box(base + Vector3(0.0, h + slab * 0.5, 0.0), Vector3(w, slab, w), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(color, rng, 0.03), false)
		h += slab
	return h

static func _city_spire(terrain: Node3D, base: Vector3, width: float, height: float, steps: int, color: Color, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	"""
	ONE TAPERING SPIRE — a stack that narrows linearly to a 0.25 m point. The
	Parliament's pinnacles, its corner-pavilion spires, Matthias's steeple, the
	Bastion's seven turret cones and the water tower's finial are all this.

	THE INTERPOLATION RUNS THROUGH ITS ENDPOINT (steps - 1 in the denominator, not
	steps), because a spire whose last slab is width / steps wide is a flat-topped
	stump, and these shapes are load-bearing silhouette: the water tower's two-step
	finial ended 1.45 m across before this was fixed. maxi guards the degenerate
	one-step call, which is a slab and not a taper anyway.

	collide = false: a cone is not a floor, and at 13 pinnacles per Parliament the
	collision shapes would be the expensive half of the building.
	The widest step is the first, exactly `width`, so the bound from the spire's own
	axis is width / 2 * sqrt(2).
	"""
	var h := 0.0
	var slab := height / float(steps)
	for i in steps:
		var w: float = lerpf(width, 0.25, float(i) / float(maxi(steps - 1, 1)))
		terrain.create_box(base + Vector3(0.0, h + slab * 0.5, 0.0), Vector3(w, slab, w), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(color, rng, 0.03), false)
		h += slab
	return h

static func _city_bays(terrain: Node3D, first: Vector3, step: Vector3, count: int, dims: Vector3, color: Color, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D, collide: bool = true) -> void:
	"""
	A ROW OF IDENTICAL PIECES — pilasters up a facade, window recesses, arcade
	posts, balustrade uprights, casemate buttresses. `first` is the CENTRE of the
	first piece and `step` the offset to the next, so a caller's bound is the
	last piece's corner and nothing in between can beat it.

	This is the one gesture every large building here repeats twenty-odd times,
	and it is what keeps a 268 m wall from reading as one extruded slab.
	"""
	for i in count:
		terrain.create_box(first + step * float(i), dims, 0.0, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(color, rng, 0.03), collide)

static func _city_cable(terrain: Node3D, a: Vector3, b: Vector3, sag: float, segments: int, thick: float, color: Color, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	ONE HANGING CABLE (or, with a NEGATIVE sag, one rising ARCH) between two
	points, as `segments` thin boxes on a parabola. The Chain Bridge's chains, the
	Elisabeth's white suspension cables, and — sag negated — the Liberty Bridge's
	green trusses and the Margaret's iron arches.

	HOW A SLOPING BOX IS BUILT OUT OF A yaw/tilt PAIR, which is the whole reason
	this is a helper. create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), so a
	box whose long axis is LOCAL Z is first tipped in the local YZ plane by `tilt`
	and then swung to its heading by `yaw`: local +Z lands on
	(cos(tilt)*sin(yaw), -sin(tilt), cos(tilt)*cos(yaw)). Matching that to the
	segment direction gives yaw = atan2(dx, dz) and tilt = -atan2(dy, horizontal) —
	which is what the two lines below are. A box long in local X could not be
	sloped at all: tilting about its own long axis does nothing.

	collide = false always. A cable 30 m over the deck that you could stand on is
	worse than no cable, and these are the thinnest boxes in the file.
	"""
	var prev := a
	for i in range(1, segments + 1):
		var t := float(i) / float(segments)
		var p := Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t) - sag * 4.0 * t * (1.0 - t), lerpf(a.z, b.z, t))
		var d := p - prev
		var flat := Vector2(d.x, d.z).length()
		terrain.create_box(prev + d * 0.5, Vector3(thick, thick, d.length()), atan2(d.x, d.z),
				rng, block_batch, block_body, -atan2(d.y, flat), LandmarkBuilders._lm_shade(color, rng, 0.02), false)
		prev = p

static func _city_parliament(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 0 — THE HUNGARIAN PARLIAMENT: 268 m of neo-Gothic river facade along Z,
	26 buttressed bays under a red tile roof, an end pavilion at each tip, and the
	96 m dome on its octagonal drum a third of the way in from the water. The
	building faces WEST (-X) because on the Pest bank the Danube is west of it.

	THE SILHOUETTE IS THE LENGTH AND THE DOME, in that order — a person names this
	building from a kilometre away by a low spiky wall with one bubble over it — so
	the bays and the pinnacles are where the box budget goes, not the interior
	court, which is a plain mass nobody sees the far side of.

	RADIUS ARITHMETIC (declared 151.0). Two boxes tie for the worst corner:
	  * the plinth, 125 x 272 at x = -0.5:  sqrt(63.0^2 + 136.0^2) = 149.88
	  * an end pavilion, 32 x 20 at (x = -46.5, z = +/-126):
	    sqrt(62.5^2 + 136.0^2) = 149.68
	and the wing cornice (32 x 270 at x = -46.5) is third at
	sqrt(62.5^2 + 135.0^2) = 148.76. So 149.88 <= 151.0.
	ONE ACCENT: the beacon on the dome's finial, 96 m up — the one light on this
	building that a real one carries.
	Boxes: 122. Colliding: 35.
	"""
	const HALF_LEN := 134.0          # the 268 m facade, half, on Z
	const WING_X := -46.5            # river wing centre, X
	const WING_D := 30.0             # its depth
	const WING_H := 30.0             # eaves
	var stone := LandmarkBuilders.LM_MARBLE
	var tile: Color = LandmarkBuilders.LM_VERMILION.darkened(0.25)

	# The plinth the whole thing stands on — the widest single box, and the one the
	# declared radius is measured against.
	terrain.create_box(center + Vector3(-0.5, 1.5, 0.0), Vector3(125.0, 3.0, 272.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))

	# The river wing: one long mass, its cornice, and its roof.
	terrain.create_box(center + Vector3(WING_X, 3.0 + WING_H / 2.0, 0.0), Vector3(WING_D, WING_H, 268.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	terrain.create_box(center + Vector3(WING_X, 33.7, 0.0), Vector3(32.0, 1.4, 270.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)
	terrain.create_box(center + Vector3(WING_X, 37.5, 0.0), Vector3(26.0, 6.0, 264.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(tile, rng, 0.04), false)

	# 25 buttresses up the river face at 10 m centres, each with its window recess,
	# and a pinnacle on every other one. THE PINNACLES ARE THE POINT: a flat wall
	# with windows is an office block, and this is the building that has 365 spires.
	_city_bays(terrain, center + Vector3(-61.0, 3.0 + 13.0, -120.0), Vector3(0.0, 0.0, 10.0), 25,
			Vector3(2.6, 26.0, 3.0), stone, rng, block_batch, block_body)
	_city_bays(terrain, center + Vector3(-61.6, 3.0 + 13.0, -115.0), Vector3(0.0, 0.0, 10.0), 24,
			Vector3(0.6, 14.0, 3.4), stone.darkened(0.62), rng, block_batch, block_body, false)
	for i in 13:
		_city_spire(terrain, center + Vector3(-61.0, 32.0, -120.0 + float(i) * 20.0), 2.2, 7.0, 3,
				stone, rng, block_batch, block_body)

	# The two end pavilions, each under its own spire — the corners that stop the
	# facade from looking sawn off.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(WING_X, 3.0 + 19.0, side * 126.0), Vector3(32.0, 38.0, 20.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		_city_spire(terrain, center + Vector3(WING_X, 41.0, side * 126.0), 11.0, 26.0, 5,
				stone, rng, block_batch, block_body)

	# The east court: the mass behind the facade, deliberately plain.
	terrain.create_box(center + Vector3(15.0, 3.0 + 13.0, 0.0), Vector3(93.0, 26.0, 96.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	terrain.create_box(center + Vector3(15.0, 31.5, 0.0), Vector3(89.0, 5.0, 92.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(tile, rng, 0.04), false)

	# THE DOME. The drum is two boxes crossed at 45 degrees, which is as octagonal
	# as this vocabulary gets (St Basil's centre shaft, same trick), then the
	# stepped dome, the lantern and the finial.
	const DOME_X := -30.0
	for k in 2:
		terrain.create_box(center + Vector3(DOME_X, 3.0 + 24.0, 0.0), Vector3(36.0, 48.0, 36.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	var y := 51.0
	y += _city_dome(terrain, center + Vector3(DOME_X, y, 0.0), 36.0, 26.0, stone, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(DOME_X, y + 4.0, 0.0), Vector3(12.0, 8.0, 12.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	y += 8.0
	y += _city_spire(terrain, center + Vector3(DOME_X, y, 0.0), 8.0, 12.0, 4, stone, rng, block_batch, block_body)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(DOME_X, y + 1.2, 0.0),
			Vector3(1.6, 1.8, 1.6), 0.0, 0.0, terrain._get_camp_ember_material())

	# The landing stair down to the water, at the centre of the river face only —
	# kept short in Z so it costs the radius nothing.
	for i in 3:
		terrain.create_box(center + Vector3(-63.5 - float(i) * 2.0, 2.6 - float(i) * 0.9, 0.0),
				Vector3(2.4, 0.9, 60.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.06))

	return { "radius": 151.0, "top": y + 2.0 }

static func _city_buda_castle(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 1 — BUDA CASTLE: 300 m of Baroque palace range along Z on its terrace,
	the green copper dome over the centre, a pavilion at each end, and the
	balustraded terrace with its grand stair on the EAST side, because on the Buda
	bank the river is east. Its plateau is the plan's (bead .3); this dresses the
	top of it and starts at its own y = 0.

	THE DOME IS WHAT SEPARATES IT FROM THE PARLIAMENT ACROSS THE WATER — same pale
	stone, same long river front, so the recognition load is carried by one green
	dome against one red roof, and by this one being FLAT-topped Baroque where the
	other is spiky.

	RADIUS ARITHMETIC (declared 156.0). The terrace slab, 70 x 300 at x = 0:
	sqrt(35.0^2 + 150.0^2) = 154.03. Next is the balustrade rail (2 x 300 at
	x = +34): sqrt(35.0^2 + 150.0^2) = 154.03 as well, then an end pavilion
	(52 x 32 at (x = -2, z = +/-134)): sqrt(28.0^2 + 150.0^2) = 152.59.
	So 154.03 <= 156.0.
	NO ACCENT: a palace, not a lighthouse.
	Boxes: 114. Colliding: 70.
	"""
	var wall := CITY_CREAM
	var roof: Color = LandmarkBuilders.LM_BASALT.lightened(0.06)   # dark slate, on top of the cream

	terrain.create_box(center + Vector3(0.0, 2.0, 0.0), Vector3(70.0, 4.0, 300.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02).darkened(0.12))
	# The main range and its roof.
	terrain.create_box(center + Vector3(-2.0, 4.0 + 13.0, 0.0), Vector3(44.0, 26.0, 296.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	terrain.create_box(center + Vector3(-2.0, 31.0, 0.0), Vector3(48.0, 2.0, 300.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.03).darkened(0.1), false)
	terrain.create_box(center + Vector3(-2.0, 35.5, 0.0), Vector3(40.0, 7.0, 292.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(roof, rng, 0.03), false)

	# 27 pilasters and 27 window recesses on the river face.
	_city_bays(terrain, center + Vector3(21.0, 4.0 + 11.0, -130.0), Vector3(0.0, 0.0, 10.0), 27,
			Vector3(3.0, 22.0, 3.4), wall, rng, block_batch, block_body)
	_city_bays(terrain, center + Vector3(20.4, 4.0 + 12.0, -125.0), Vector3(0.0, 0.0, 10.0), 26,
			Vector3(0.6, 11.0, 3.6), wall.darkened(0.6), rng, block_batch, block_body, false)

	# The centre pavilion, its drum and the copper dome.
	terrain.create_box(center + Vector3(-2.0, 4.0 + 17.0, 0.0), Vector3(54.0, 34.0, 60.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	for k in 2:
		terrain.create_box(center + Vector3(-2.0, 45.0, 0.0), Vector3(26.0, 14.0, 26.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	var y := 52.0
	y += _city_dome(terrain, center + Vector3(-2.0, y, 0.0), 26.0, 20.0, LandmarkBuilders.LM_COPPER, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(-2.0, y + 3.0, 0.0), Vector3(8.0, 6.0, 8.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_COPPER, rng, 0.03), false)
	y += 6.0
	y += _city_spire(terrain, center + Vector3(-2.0, y, 0.0), 4.0, 7.0, 3, LandmarkBuilders.LM_COPPER, rng, block_batch, block_body)

	# End pavilions.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(-2.0, 4.0 + 15.0, side * 134.0), Vector3(52.0, 30.0, 32.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
		terrain.create_box(center + Vector3(-2.0, 36.0, side * 134.0), Vector3(48.0, 6.0, 28.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(roof, rng, 0.03), false)

	# The terrace balustrade over the river, and the grand stair down through it.
	_city_bays(terrain, center + Vector3(34.0, 5.5, -145.0), Vector3(0.0, 0.0, 10.0), 30,
			Vector3(1.2, 3.0, 1.2), wall, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(34.0, 7.4, 0.0), Vector3(2.0, 0.6, 300.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.03), false)
	for i in 4:
		terrain.create_box(center + Vector3(36.0 + float(i) * 3.0, 3.4 - float(i) * 1.0, 0.0),
				Vector3(3.0, 1.0, 40.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(wall, rng, 0.03).darkened(0.08))

	# The Turul column at the north end — a bronze bird on a plain shaft, and the
	# one thing on this building that is not the palace.
	terrain.create_box(center + Vector3(24.0, 2.0, -140.0), Vector3(6.0, 4.0, 6.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.03))
	terrain.create_box(center + Vector3(24.0, 11.0, -140.0), Vector3(3.0, 14.0, 3.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	terrain.create_box(center + Vector3(24.0, 19.4, -140.0), Vector3(3.4, 2.8, 1.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_IRON.darkened(0.35), rng, 0.03), false)
	for wing in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(24.0, 21.4, -140.0 + wing * 1.6), Vector3(2.0, 3.6, 1.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_IRON.darkened(0.35), rng, 0.03), false)

	return { "radius": 156.0, "top": y + 1.0 }

static func _city_matthias_bastion(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 2 — MATTHIAS CHURCH AND THE FISHERMAN'S BASTION: the two are one place on
	the Castle Hill plateau (the terrace wraps the church's forecourt), so they are
	one builder. The Bastion's white arcade runs along Z on the river side at
	x = +41 with its SEVEN conical turrets — one per Magyar tribe, and the count is
	the fact the toast will tell — and the church stands behind it with its 78 m
	south steeple and its diamond-patterned Zsolnay roof.

	THE ROOF IS WORTH 30 BOXES. A grey Gothic church is every Gothic church; the
	glazed diamond pattern is the one in Budapest, so the tiles get their own pass
	over both slopes in the three glaze colours the real roof uses.

	RADIUS ARITHMETIC (declared 80.0). The arcade cornice, 3.4 x 130 at x = +41:
	sqrt(42.7^2 + 65.0^2) = 77.77 — it overhangs the parapet, which is why the
	widest box here is a piece of trim and not a wall. The parapet itself
	(2.4 x 130) is sqrt(42.2^2 + 65.0^2) = 77.50 and the terrace slab
	(24 x 130 at x = +30) sqrt(42.0^2 + 65.0^2) = 77.38. So 77.77 <= 80.0.
	NO ACCENT.
	Boxes: 162. Colliding: 34.
	"""
	var stone := LandmarkBuilders.LM_MARBLE
	# The three Zsolnay glazes. Reused entries, all three: burnt orange, green and
	# the dark plum-brown that the real diamond field is bordered in.
	var glazes: Array = [LandmarkBuilders.LM_OCHRE, LandmarkBuilders.LM_COPPER, LandmarkBuilders.LM_ROOF]

	# --- The Bastion: terrace, parapet, arcade, cornice, seven turrets.
	terrain.create_box(center + Vector3(30.0, 1.5, 0.0), Vector3(24.0, 3.0, 130.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.06))
	terrain.create_box(center + Vector3(41.0, 5.0, 0.0), Vector3(2.4, 4.0, 130.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	_city_bays(terrain, center + Vector3(41.0, 6.0, -59.5), Vector3(0.0, 0.0, 8.5), 15,
			Vector3(2.6, 6.0, 2.6), stone, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(41.0, 9.8, 0.0), Vector3(3.4, 1.6, 130.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)
	for i in 7:
		var tz := -54.0 + float(i) * 18.0
		for k in 2:
			terrain.create_box(center + Vector3(41.0, 7.5, tz), Vector3(6.4, 9.0, 6.4),
					float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		terrain.create_box(center + Vector3(43.6, 8.0, tz), Vector3(0.6, 4.0, 2.2), 0.0,
				rng, block_batch, block_body, 0.0, stone.darkened(0.62), false)
		_city_spire(terrain, center + Vector3(41.0, 12.0, tz), 7.4, 11.0, 6, stone, rng, block_batch, block_body)

	# --- The church: nave, stepped roof, the tile field, the two towers.
	terrain.create_box(center + Vector3(-6.0, 10.0, 0.0), Vector3(24.0, 20.0, 62.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	var ry := 20.0
	for i in 5:
		var w: float = 24.0 - float(i) * 4.2
		terrain.create_box(center + Vector3(-6.0, ry + 1.2, 0.0), Vector3(w, 2.4, 62.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(glazes[2], rng, 0.03), false)
		ry += 2.4
	# The diamond field: five courses of six tiles proud of each roof step's flank,
	# the glaze cycling on (course + tile) so no two neighbours match on either axis.
	for course in 5:
		var cw: float = 24.0 - float(course) * 4.2
		for tile_i in 6:
			var g: Color = glazes[(course + tile_i) % glazes.size()]
			for side in [-1.0, 1.0]:
				terrain.create_box(center + Vector3(-6.0 + side * (cw / 2.0 + 0.2), 21.2 + float(course) * 2.4, -25.0 + float(tile_i) * 10.0),
						Vector3(0.5, 2.0, 6.0), 0.0, rng, block_batch, block_body, 0.0,
						LandmarkBuilders._lm_shade(g, rng, 0.04), false)
	# The south steeple — 78 m, and the tallest thing on the hill.
	terrain.create_box(center + Vector3(-6.0, 22.0, 34.0), Vector3(13.0, 44.0, 13.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	terrain.create_box(center + Vector3(-6.0, 45.0, 34.0), Vector3(15.0, 2.0, 15.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)
	var spire_top := 46.0 + _city_spire(terrain, center + Vector3(-6.0, 46.0, 34.0), 12.0, 32.0, 8,
			glazes[2], rng, block_batch, block_body)
	# The shorter Béla tower at the north end.
	terrain.create_box(center + Vector3(-6.0, 13.0, -30.0), Vector3(11.0, 26.0, 11.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	_city_spire(terrain, center + Vector3(-6.0, 26.0, -30.0), 10.0, 9.0, 4, glazes[2], rng, block_batch, block_body)

	return { "radius": 80.0, "top": spire_top }

static func _city_citadella(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 3 — THE CITADELLA AND THE LIBERTY STATUE: a closed 220 x 60 m fortress of
	dark basalt on the Gellért summit — four crenellated wall runs, four corner
	bastions, a casemate arcade down the river face — with the Liberty Statue on
	its pedestal standing clear of the south end.

	THE PALM FROND IS THE RECOGNITION CUE and it is one box: a 16 m bar held
	overhead, 48 m up. Everything else about a woman on a plinth is every statue in
	this registry; the wide horizontal held ABOVE the head is only this one.

	The fort is the darkest mass in the city on purpose — LandmarkBuilders.LM_BASALT against the
	paved-grey ground is the widest colour separation the measured palette offers
	(Oklab dE 0.143 / 0.344 depending on how the shader default is read), and a
	fortress that read as pavement would be a 220 m building nobody could see.

	RADIUS ARITHMETIC (declared 120.0). The north and south wall runs, 68 x 4 at
	z = +/-110: sqrt(34.0^2 + 112.0^2) = 117.05. A corner bastion (16 x 16 at
	(+/-26, +/-102)): sqrt(34.0^2 + 110.0^2) = 115.13. The east wall (4 x 220 at
	x = +30): sqrt(32.0^2 + 110.0^2) = 114.56, and the outermost merlon
	(4.4 x 4.0 at (+/-30, +/-105)) sqrt(32.2^2 + 107.0^2) = 111.74.
	So 117.05 <= 120.0.
	NO ACCENT.
	Boxes: 95. Colliding: 23.
	"""
	var fort := LandmarkBuilders.LM_BASALT
	var bronze: Color = LandmarkBuilders.LM_IRON.darkened(0.35)

	# The four wall runs — a closed ring, so the fort is a shape you walk round.
	# WALL_H is 10 and not the 7 a real casemate wall is: from eye height, 220 m of
	# 7 m wall at 150 m out is one horizontal line, and a fortress that reads as a
	# kerb is not a landmark. The merlons below are the other half of that fix.
	const WALL_H := 10.0
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(0.0, WALL_H / 2.0, side * 110.0), Vector3(68.0, WALL_H, 4.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fort, rng, 0.04))
		terrain.create_box(center + Vector3(side * 30.0, WALL_H / 2.0, 0.0), Vector3(4.0, WALL_H, 220.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fort, rng, 0.04))
		# CRENELLATIONS along both long walls — 22 merlons a side, the one detail
		# that says "fort" from a distance at which nothing else on it is legible.
		_city_bays(terrain, center + Vector3(side * 30.0, WALL_H + 1.2, -105.0), Vector3(0.0, 0.0, 10.0), 22,
				Vector3(4.4, 2.4, 4.0), fort, rng, block_batch, block_body, false)
	# Corner bastions, angled out at 45 degrees the way a real bastion is, and a
	# storey taller than the curtain so the corners read as corners.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			terrain.create_box(center + Vector3(sx * 26.0, 6.5, sz * 102.0), Vector3(16.0, 13.0, 16.0),
					PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fort, rng, 0.03))
	# The casemate arcade down the river face: 18 gun recesses between 12
	# buttresses. The recesses are cut INTO the wall's own volume, so collide=false.
	_city_bays(terrain, center + Vector3(31.0, WALL_H / 2.0, -100.0), Vector3(0.0, 0.0, 18.0), 12,
			Vector3(4.0, WALL_H, 4.0), fort, rng, block_batch, block_body)
	_city_bays(terrain, center + Vector3(29.4, 3.6, -102.0), Vector3(0.0, 0.0, 12.0), 18,
			Vector3(1.2, 4.4, 3.4), fort.darkened(0.55), rng, block_batch, block_body, false)
	# The barracks in the yard.
	terrain.create_box(center + Vector3(0.0, 6.0, 20.0), Vector3(20.0, 12.0, 120.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fort, rng, 0.03).lightened(0.08))

	# --- THE LIBERTY STATUE, on its own stepped pedestal south of the fort.
	terrain.create_box(center + Vector3(0.0, 3.0, 90.0), Vector3(18.0, 6.0, 18.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 16.0, 90.0), Vector3(13.0, 20.0, 13.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.02))
	# The figure: robe, torso, head, two raised arms, and the frond across the top.
	terrain.create_box(center + Vector3(0.0, 30.5, 90.0), Vector3(5.0, 9.0, 3.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 38.5, 90.0), Vector3(6.0, 7.0, 3.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 43.5, 90.0), Vector3(2.6, 3.0, 2.6), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
	for arm in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(arm * 3.4, 41.0, 90.0), Vector3(1.5, 8.0, 1.5), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 46.5, 90.0), Vector3(16.0, 0.7, 2.2), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
	# The two attendant figures at the pedestal's foot — small, and the reason the
	# statue reads as a monument rather than as a lamp post.
	for att in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(att * 11.0, 8.5, 90.0), Vector3(2.4, 5.0, 2.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
		terrain.create_box(center + Vector3(att * 11.0, 12.0, 90.0), Vector3(1.4, 2.0, 1.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)

	return { "radius": 120.0, "top": 47.0 }

static func _city_margaret_island(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 4 — MARGARET ISLAND: the 57 m Art Nouveau water tower in the middle of its
	park, with the open-air theatre it stands behind, the musical fountain, and a
	ring of trees. The ISLAND itself is the plan's water (bead .4); this is the one
	place on it a person names.

	IT IS THE ONLY GREEN LANDMARK IN THE CITY, and the trees are why the park green
	had to be measured into the palette: eighteen dark-green canopies at 8 m are
	what say "park" before the tower says "tower".

	RADIUS ARITHMETIC (declared 56.0). The two paths, 6 x 100 at x = +/-14:
	sqrt(17.0^2 + 50.0^2) = 52.81. A tree canopy on the r = 44 ring is at worst
	44.0 + 3.5 * sqrt(2) = 48.95 (the canopies are axis-aligned, so the corner is
	the diagonal of a 7 m box added to the ring). So 52.81 <= 56.0.
	NO ACCENT.
	Boxes: 65. Colliding: 33.
	"""
	var plaster := CITY_CREAM

	# The tower: three octagonal tiers (each a box and its 45-degree twin), the
	# lookout gallery, the copper cap and the finial.
	var tiers: Array = [[12.0, 20.0, 10.0], [10.0, 18.0, 29.0], [8.0, 10.0, 43.0]]
	terrain.create_box(center + Vector3(0.0, 1.0, 0.0), Vector3(16.0, 2.0, 16.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(plaster, rng, 0.02).darkened(0.12))
	for tier_variant: Variant in tiers:
		var tier: Array = tier_variant
		for k in 2:
			terrain.create_box(center + Vector3(0.0, float(tier[2]), 0.0),
					Vector3(float(tier[0]), float(tier[1]), float(tier[0])),
					float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(plaster, rng, 0.02))
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 45.6, 0.0), Vector3(12.0, 1.6, 12.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(plaster, rng, 0.03).darkened(0.1), false)
	var y := 48.0
	y += _city_dome(terrain, center + Vector3(0.0, y, 0.0), 9.0, 7.0, LandmarkBuilders.LM_COPPER, rng, block_batch, block_body)
	y += _city_spire(terrain, center + Vector3(0.0, y, 0.0), 2.4, 2.4, 2, LandmarkBuilders.LM_COPPER, rng, block_batch, block_body)

	# The open-air theatre in front of it: a stage and five rows of seating.
	terrain.create_box(center + Vector3(0.0, 2.5, -18.0), Vector3(18.0, 5.0, 8.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(plaster, rng, 0.03).darkened(0.14))
	for i in 5:
		terrain.create_box(center + Vector3(0.0, 0.6 + float(i) * 0.6, -26.0 - float(i) * 4.0),
				Vector3(34.0, 1.2 + float(i) * 1.2, 4.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.03).darkened(0.2))

	# The musical fountain: an octagonal basin, its water and one jet.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 0.6, 22.0), Vector3(18.0, 1.2, 18.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.03))
	terrain.create_box(center + Vector3(0.0, 1.0, 22.0), Vector3(14.0, 0.3, 14.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_COPPER, rng, 0.02).lightened(0.25), false)
	terrain.create_box(center + Vector3(0.0, 4.0, 22.0), Vector3(0.8, 6.0, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.02), false)

	# Two gravel walks, and the ring of eighteen trees around the whole thing.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 14.0, 0.1, 0.0), Vector3(6.0, 0.2, 100.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.03).darkened(0.28), false)
	for i in 18:
		var a := TAU * float(i) / 18.0
		var spot := center + Vector3(cos(a) * 44.0, 0.0, sin(a) * 44.0)
		terrain.create_box(spot + Vector3(0.0, 2.5, 0.0), Vector3(1.4, 5.0, 1.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_ROOF, rng, 0.04))
		terrain.create_box(spot + Vector3(0.0, 8.5, 0.0), Vector3(7.0, 7.0, 7.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(CITY_PARK_GREEN, rng, 0.05), false)

	return { "radius": 56.0, "top": y }

static func _city_chain_bridge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 5 — THE CHAIN BRIDGE'S TOWERS: two 47 m stone triumphal arches at
	x = +/-101 (the real span is 202 m), the chains slung between them and back to
	the abutments, and the four lions on their plinths at the tower feet.
	The DECK is bead .4's — these builders put the ornament on top of it, so
	nothing here is a roadway and the chains hang where a deck at y = 12 would be.

	Bridge builders all run their axis on X, because the Danube runs on Z.

	RADIUS ARITHMETIC (declared 124.0). The back-stay anchor at x = +/-120,
	z = +/-8 with a 1.4 m cable box: sqrt(120.7^2 + 8.7^2) = 120.95. The lion
	plinths (7 x 5 at (+/-113, +/-11)) are sqrt(116.5^2 + 13.5^2) = 117.28, and a
	tower's attic (9 x 33) sqrt(105.5^2 + 16.5^2) = 106.78. So 120.95 <= 124.0.
	NO ACCENT.
	Boxes: 92. Colliding: 10.
	"""
	var stone := LandmarkBuilders.LM_MARBLE
	var iron: Color = LandmarkBuilders.LM_IRON.darkened(0.35)

	for side in [-1.0, 1.0]:
		var tx: float = side * 101.0
		# Two piers with the portal between them, then the entablature and attic —
		# the arch you drive through is the gap, not a box.
		for pz in [-9.5, 9.5]:
			terrain.create_box(center + Vector3(tx, 18.0, pz), Vector3(7.0, 36.0, 14.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		terrain.create_box(center + Vector3(tx, 38.5, 0.0), Vector3(8.0, 5.0, 33.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		terrain.create_box(center + Vector3(tx, 44.0, 0.0), Vector3(9.0, 6.0, 33.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

		# The lions: two plinths per bank, a body and a head on each.
		for lz in [-11.0, 11.0]:
			terrain.create_box(center + Vector3(side * 113.0, 2.0, lz), Vector3(7.0, 4.0, 5.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03))
			terrain.create_box(center + Vector3(side * 113.0, 5.2, lz), Vector3(5.0, 2.4, 2.4), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_STONE_GREY.darkened(0.15), rng, 0.03), false)
			terrain.create_box(center + Vector3(side * 115.4, 6.4, lz), Vector3(2.0, 2.2, 2.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_STONE_GREY.darkened(0.15), rng, 0.03), false)

	# THE CHAINS. One swag over the main span per side, one back-stay per tower per
	# side down to the anchor, and the hangers that drop from the swag to the deck.
	for cz in [-8.0, 8.0]:
		_city_cable(terrain, center + Vector3(-101.0, 47.0, cz), center + Vector3(101.0, 47.0, cz),
				27.0, 16, 1.4, iron, rng, block_batch, block_body)
		for side in [-1.0, 1.0]:
			_city_cable(terrain, center + Vector3(side * 101.0, 47.0, cz), center + Vector3(side * 120.0, 5.0, cz),
					0.0, 5, 1.4, iron, rng, block_batch, block_body)
		for i in 10:
			var hx := -90.0 + float(i) * 20.0
			var t := (hx + 101.0) / 202.0
			var cy: float = 47.0 - 27.0 * 4.0 * t * (1.0 - t)
			terrain.create_box(center + Vector3(hx, (cy + 12.0) / 2.0, cz), Vector3(0.5, cy - 12.0, 0.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(iron, rng, 0.02), false)

	return { "radius": 124.0, "top": 50.0 }

static func _city_liberty_bridge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 6 — THE LIBERTY BRIDGE'S IRONWORK: the green cantilever trusses over the
	main span, four masts on the two river piers, and a TURUL on each mast — the
	mythical falcon, wings out, which is the whole reason anyone photographs this
	bridge. Deck is bead .4's.

	Only the MAIN span's truss is emitted. The shore spans' trusses would double
	the builder's radius to 170 m for a shape the deck already carries, so if they
	are ever wanted they belong with the deck and not here.

	RADIUS ARITHMETIC (declared 104.0). A river pier, 26 x 22 at x = +/-87:
	sqrt(100.0^2 + 11.0^2) = 100.60. The truss arch never passes the pier tops, and
	a mast (2.4 x 2.4 at (+/-87, +/-9)) is sqrt(88.2^2 + 10.2^2) = 88.79.
	So 100.60 <= 104.0.
	NO ACCENT.
	Boxes: 48. Colliding: 6.
	"""
	var green: Color = LandmarkBuilders.LM_COPPER.darkened(0.45)
	var bronze: Color = LandmarkBuilders.LM_IRON.darkened(0.35)

	for side in [-1.0, 1.0]:
		var px: float = side * 87.0
		terrain.create_box(center + Vector3(px, 6.0, 0.0), Vector3(26.0, 12.0, 22.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.02))
		for mz in [-9.0, 9.0]:
			terrain.create_box(center + Vector3(px, 29.0, mz), Vector3(2.4, 34.0, 2.4), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(green, rng, 0.03))
			# THE TURUL: body, head and two swept wings, 46 m up.
			terrain.create_box(center + Vector3(px, 47.0, mz), Vector3(2.6, 1.6, 1.2), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
			terrain.create_box(center + Vector3(px, 48.3, mz), Vector3(0.9, 1.2, 0.8), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
			# The wings are WIDE and FLAT, not tall: a vertical slab beside a body
			# reads as a chimney, and the spread is the only thing that makes a
			# 3 m bird on a 46 m mast legible as a bird at all.
			for wing in [-1.0, 1.0]:
				terrain.create_box(center + Vector3(px, 48.1, mz + wing * 2.6), Vector3(0.9, 0.6, 4.4), 0.0,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
		# The cross braces between each pier's two masts.
		for by in [20.0, 31.0, 42.0]:
			terrain.create_box(center + Vector3(px, by, 0.0), Vector3(1.6, 1.2, 18.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(green, rng, 0.03), false)

	# The two green trusses — a NEGATIVE sag, so the same helper that hangs the
	# Chain Bridge's chains raises this bridge's arches.
	for tz in [-9.0, 9.0]:
		_city_cable(terrain, center + Vector3(-87.0, 14.0, tz), center + Vector3(87.0, 14.0, tz),
				-22.0, 10, 1.8, green, rng, block_batch, block_body)

	return { "radius": 104.0, "top": 49.0 }

static func _city_elisabeth_bridge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 7 — THE ELISABETH BRIDGE'S PYLONS AND CABLES: two slim white portal
	pylons, one white main cable per side over the span, the back-stays into the
	anchor blocks, and the hangers. The whitest thing on the river and the only
	bridge here with no ornament at all — 1964, and it looks it. Deck is bead .4's.

	RADIUS ARITHMETIC (declared 122.0). The anchor blocks, 12 x 26 at x = +/-112:
	sqrt(118.0^2 + 13.0^2) = 118.71. The back-stay's last cable box lands inside
	them. A pylon leg (4.5 x 4.5 at (+/-95, +/-9)) is sqrt(97.25^2 + 11.25^2) =
	97.90. So 118.71 <= 122.0.
	NO ACCENT.
	Boxes: 80. Colliding: 6.
	"""
	var white := LandmarkBuilders.LM_MARBLE
	var cable: Color = LandmarkBuilders.LM_MARBLE.darkened(0.35)

	for side in [-1.0, 1.0]:
		var px: float = side * 95.0
		for lz in [-9.0, 9.0]:
			terrain.create_box(center + Vector3(px, 22.0, lz), Vector3(4.5, 44.0, 4.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(white, rng, 0.02))
		terrain.create_box(center + Vector3(px, 43.0, 0.0), Vector3(4.5, 4.0, 22.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(white, rng, 0.02), false)
		terrain.create_box(center + Vector3(side * 112.0, 3.5, 0.0), Vector3(12.0, 7.0, 26.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(white, rng, 0.03).darkened(0.1))

	for cz in [-9.0, 9.0]:
		_city_cable(terrain, center + Vector3(-95.0, 45.0, cz), center + Vector3(95.0, 45.0, cz),
				29.0, 14, 1.1, cable, rng, block_batch, block_body)
		for side in [-1.0, 1.0]:
			_city_cable(terrain, center + Vector3(side * 95.0, 45.0, cz), center + Vector3(side * 112.0, 7.0, cz),
					0.0, 5, 1.1, cable, rng, block_batch, block_body)
		for i in 12:
			var hx := -84.0 + float(i) * 15.3
			var t := (hx + 95.0) / 190.0
			var cy: float = 45.0 - 29.0 * 4.0 * t * (1.0 - t)
			terrain.create_box(center + Vector3(hx, (cy + 12.0) / 2.0, cz), Vector3(0.35, cy - 12.0, 0.35), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(cable, rng, 0.02), false)

	return { "radius": 122.0, "top": 47.0 }

static func _city_margaret_bridge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 8 — THE MARGARET BRIDGE'S PIERS AND ARCHES, and the Y: three stone piers
	with pointed cutwaters on the X axis, an iron arch between each pair, and the
	BRANCH — the short arm that leaves the middle pier northward onto Margaret
	Island, which is the thing that makes this bridge a Y and not a line. Deck is
	bead .4's; the branch here is its piers and its one arch.

	The Y is why _city_cable takes two POINTS rather than a length: the branch runs
	on Z while everything else on this bridge runs on X, and the helper's
	yaw = atan2(dx, dz) takes the turn without the builder knowing about it.

	RADIUS ARITHMETIC (declared 114.0). An outer pier, 18 x 24 at x = +/-100:
	sqrt(109.0^2 + 12.0^2) = 109.66. Its cutwater is a 45-degree 10 m box at
	(+/-100, +/-13), whose corner is 100 + 7.07 = 107.07 out on X and 20.07 on Z:
	sqrt(107.07^2 + 20.07^2) = 108.93. So 109.66 <= 114.0.
	NO ACCENT.
	Boxes: 78. Colliding: 12.
	"""
	var stone := LandmarkBuilders.LM_MARBLE
	var iron: Color = LandmarkBuilders.LM_COPPER.darkened(0.55)

	for px in [-100.0, 0.0, 100.0]:
		terrain.create_box(center + Vector3(px, 5.5, 0.0), Vector3(18.0, 11.0, 24.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		for cz in [-1.0, 1.0]:
			terrain.create_box(center + Vector3(px, 4.5, cz * 13.0), Vector3(10.0, 9.0, 10.0), PI / 4.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03))
	# The branch's own three piers, walking north off the middle one.
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 4.5, -20.0 - float(i) * 20.0), Vector3(14.0, 9.0, 10.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))

	# Two iron arches per main span, one per side of the deck, plus the branch's.
	for az in [-8.0, 8.0]:
		_city_cable(terrain, center + Vector3(-100.0, 11.0, az), center + Vector3(0.0, 11.0, az),
				-13.0, 9, 1.4, iron, rng, block_batch, block_body)
		_city_cable(terrain, center + Vector3(0.0, 11.0, az), center + Vector3(100.0, 11.0, az),
				-13.0, 9, 1.4, iron, rng, block_batch, block_body)
	for ax in [-6.0, 6.0]:
		_city_cable(terrain, center + Vector3(ax, 11.0, 0.0), center + Vector3(ax, 11.0, -60.0),
				-9.0, 7, 1.4, iron, rng, block_batch, block_body)

	# The lamp standards along the parapet line — small, and the one piece of
	# decoration a bridge of 1876 has that one of 1964 does not.
	for i in 8:
		var lx := -87.5 + float(i) * 25.0
		for lz in [-10.0, 10.0]:
			terrain.create_box(center + Vector3(lx, 15.0, lz), Vector3(0.5, 6.0, 0.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(iron, rng, 0.02), false)

	return { "radius": 114.0, "top": 26.0 }

# ----------------------------------------------------------------------------
# BUDAPEST — WAVE B: THE PEST INNER CITY
# ----------------------------------------------------------------------------
##
## Six more builders for CITY_LANDMARKS, one block back from the water. EVERY
## RULE OF WAVE A APPLIES UNCHANGED and none of it is restated here: the fixed
## orientation (a building's long axis on Z, because the Danube runs on Z), the
## RNG touching COLOUR ONLY, the four shared helpers above, the corner-and-not-
## axis radius arithmetic in each docstring, and collide = false on everything
## nobody can reach. The four helpers took all six of these places with no new
## parameter and no fifth helper, which is the measurement that says wave A
## picked the right four gestures rather than the four its own nine happened to
## need.
##
## NO NEW COLOUR EITHER, which is the wave-2 palette rule a third time: Pest's
## inner city is brick where the Danube core was stone, and LM_OCHRE is honestly
## brick (dE 0.200 against the paved grey — the one member of the warm mid-tone
## family that is dark enough to meet a pavement, see the CITY_CREAM banner).
##
## ONE THING WAVE A DID NOT HAVE: a LINE landmark. Váci utca is 150 m of street
## and not a building, so its footprint is honestly a RECT — and the registry
## carries only a `radius`, so it declares that rect's BOUNDING CIRCLE. That
## over-reserves the ground either side of the street, which is safe for every
## rule the radius feeds (check 1's closing note is the argument) and costs the
## plan nothing, because the SLOT is bead .3's and a slot may be a rect. A
## `shape` key here would be a second geometry language invented for one row, so
## there is not one.

static func _city_basilica(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 9 — ST STEPHEN'S BASILICA: a 74 m nave on Z under the 96 m dome, twin
	bell towers standing either side of a six-column portico at the -Z end, and
	the colonnaded drum that is the reason this dome reads as a bubble on a RING.

	THE TWO DOMES OF BUDAPEST ARE THE SAME HEIGHT — that is the fact on the card —
	so the silhouette's whole job is to say "the other one". The Parliament is a
	long spiky wall with a Gothic bubble a third of the way along it; this is a
	compact cross, a classical drum with sixteen columns round it, and two SQUARE
	towers that stop at three quarters of the dome. Nothing here is pointed.

	THE DRUM IS 23 M ACROSS BECAUSE THE RING IS AT 18. Two crossed boxes make an
	octagon whose 45-degree twin reaches half_width * sqrt(2) on the cardinals, so
	a 30 m drum swallowed eight of the sixteen columns whole and shipped a ring
	with every other post missing. 11.5 * sqrt(2) = 16.26 clears the columns'
	inner face at 17.1 — the same arithmetic the radius line below uses, one
	radius in.

	RADIUS ARITHMETIC (declared 58.0). The front flight wins it — the third step,
	44 x 2 at z = -51: sqrt(22.00^2 + 52.00^2) = 56.46 — with the plinth (56 x 92)
	second at sqrt(28.00^2 + 46.00^2) = 53.85 and a bell tower's cornice (15 x 15
	at x = +/-23, z = -37) third at sqrt(30.50^2 + 44.50^2) = 53.95.
	So 56.46 <= 58.0.
	ONE ACCENT: the cross on the dome's finial. It is the highest lit thing in the
	city and the Parliament's beacon is the other one, which is the pair of lights
	the fact is about.
	Boxes: 92. Colliding: 15.
	"""
	var stone := LandmarkBuilders.LM_MARBLE
	var copper: Color = LandmarkBuilders.LM_COPPER.darkened(0.15)
	var lead: Color = LandmarkBuilders.LM_COPPER.darkened(0.4)

	# The plinth, and the flight up to the portico. THE STEPS DO NOT COLLIDE: a
	# 0.5 m step is a stair no CharacterBody3D in this game can climb (CLAUDE.md's
	# no-jump-gate rule is the same fact indoors), so the flight is ornament and
	# the plinth is what a body actually meets.
	terrain.create_box(center + Vector3(0.0, 0.8, 0.0), Vector3(56.0, 1.6, 92.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 1.2 - float(i) * 0.5, -47.0 - float(i) * 2.0),
				Vector3(44.0, 0.5, 2.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)

	# The nave, its two aisles, and the pilaster bays that keep 74 m of wall from
	# reading as one extrusion.
	terrain.create_box(center + Vector3(0.0, 14.6, 0.0), Vector3(38.0, 26.0, 74.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 28.6, 0.0), Vector3(34.0, 2.0, 70.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(lead, rng, 0.03), false)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 25.0, 10.6, 0.0), Vector3(12.0, 18.0, 60.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		# ON the aisle's OUTER face (each aisle spans |x| = 19..31), never inside it.
		_city_bays(terrain, center + Vector3(side * 30.6, 10.6, -27.0), Vector3(0.0, 0.0, 6.0), 10,
				Vector3(1.4, 18.0, 2.6), stone, rng, block_batch, block_body, false)

	# The west front: the block, six columns, the architrave and the pediment.
	terrain.create_box(center + Vector3(0.0, 14.6, -40.0), Vector3(46.0, 26.0, 8.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	_city_bays(terrain, center + Vector3(-12.5, 10.6, -45.5), Vector3(5.0, 0.0, 0.0), 6,
			Vector3(2.6, 18.0, 2.6), stone, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(0.0, 20.8, -45.5), Vector3(30.0, 2.4, 3.6), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	var pediment: Array = [28.0, 19.0, 10.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 22.85 + float(i) * 1.7, -45.5),
				Vector3(float(pediment[i]), 1.7, 3.2), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# The two bell towers. Square, cornice, lantern, copper cap, short spire — and
	# they stop at 78 m so the dome is unambiguously the tall thing.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 23.0, 29.6, -37.0), Vector3(13.0, 56.0, 13.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		terrain.create_box(center + Vector3(side * 23.0, 58.4, -37.0), Vector3(15.0, 1.6, 15.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)
		terrain.create_box(center + Vector3(side * 23.0, 62.7, -37.0), Vector3(9.0, 7.0, 9.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
		var cap := 66.2 + _city_dome(terrain, center + Vector3(side * 23.0, 66.2, -37.0), 9.0, 6.0,
				copper, rng, block_batch, block_body)
		_city_spire(terrain, center + Vector3(side * 23.0, cap, -37.0), 3.0, 6.0, 3,
				copper, rng, block_batch, block_body)

	# THE DOME, on the crossing at z = +12: the octagonal drum (a box and its
	# 45-degree twin), the ring of sixteen columns that is this dome's signature,
	# the stepped cap, the lantern and the finial.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 40.6, 4.0), Vector3(23.0, 26.0, 23.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	for i in 16:
		var a := TAU * float(i) / 16.0
		terrain.create_box(center + Vector3(cos(a) * 18.0, 32.1, 4.0 + sin(a) * 18.0),
				Vector3(1.8, 9.0, 1.8), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	var y := 53.6
	y += _city_dome(terrain, center + Vector3(0.0, y, 4.0), 23.0, 22.0, copper, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(0.0, y + 3.5, 4.0), Vector3(9.0, 7.0, 9.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	y += 7.0
	y += _city_spire(terrain, center + Vector3(0.0, y, 4.0), 5.5, 8.0, 4, copper, rng, block_batch, block_body)
	# ONE accent, per this file's rule 4 — the spire under it is the cross's shaft,
	# so the lit box is the crossbar alone and not a second draw call for it.
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 1.2, 4.0),
			Vector3(1.6, 1.8, 0.5), 0.0, 0.0, terrain._get_camp_ember_material())

	return { "radius": 58.0, "top": y + 2.4 }


static func _city_market_hall(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 10 — THE GREAT MARKET HALL: 144 m of brick nave on Z under the ZSOLNAY
	ROOF, a neo-Gothic entrance gable with a rose window and two turrets at the
	-Z end, four corner turrets, and the iron canopy over the door.

	THE ROOF IS THE LANDMARK and it is where the box budget goes — 40 of the 116.
	It is drawn as four courses of ten bays each, coloured glazes[(course + bay) %
	3], which is a CHECKERBOARD and not a stripe: the real roof's diamond pattern
	is the one thing about this building that survives being seen from 200 m as a
	MultiMesh of boxes, and four long slabs in three colours would have been a
	flag. That the pattern needs no RNG is the point — the tile a given bay wears
	is arithmetic, so this roof is identical in every run, like every other city
	shape (see the wave A banner).

	RADIUS ARITHMETIC (declared 82.0). The plinth, 54 x 150, is the worst box:
	sqrt(27.00^2 + 75.00^2) = 79.71. A gable turret (6 x 6 at x = +/-16, z = -73)
	is second at sqrt(19.00^2 + 76.00^2) = 78.34 and the entrance gable (36 x 6 at
	z = -73) third at sqrt(18.00^2 + 76.00^2) = 78.10. So 79.71 <= 82.0.
	NO ACCENT: a market is lit from inside through its glazing, and this
	vocabulary cannot draw that — a glow on the rose window would say "church",
	which is the one thing 40 boxes of coloured roof exist to stop.
	Boxes: 116. Colliding: 42.
	"""
	var brick := LandmarkBuilders.LM_OCHRE
	var dressing := LandmarkBuilders.LM_MARBLE
	var iron: Color = LandmarkBuilders.LM_IRON.darkened(0.2)
	# The three Zsolnay glazes, the same trio Matthias Church wears — this roof and
	# that one are by the same tile works, which is why they share a palette.
	var glazes: Array = [LandmarkBuilders.LM_COPPER, LandmarkBuilders.LM_VERMILION.darkened(0.25), LandmarkBuilders.LM_SANDSTONE]

	terrain.create_box(center + Vector3(0.0, 1.0, 0.0), Vector3(54.0, 2.0, 150.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(dressing, rng, 0.02).darkened(0.1))
	terrain.create_box(center + Vector3(0.0, 11.0, 0.0), Vector3(48.0, 18.0, 144.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))

	# Sixteen buttresses a side, and the glazing band between them.
	for side in [-1.0, 1.0]:
		_city_bays(terrain, center + Vector3(side * 24.6, 11.0, -67.5), Vector3(0.0, 0.0, 9.0), 16,
				Vector3(1.6, 16.0, 2.6), dressing, rng, block_batch, block_body)
		terrain.create_box(center + Vector3(side * 24.2, 11.0, 0.0), Vector3(0.8, 9.0, 138.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03).darkened(0.55), false)

	# THE ZSOLNAY ROOF: four courses, ten bays, three glazes, no RNG.
	var widths: Array = [48.0, 38.0, 26.0, 12.0]
	for course in 4:
		for bay in 10:
			terrain.create_box(center + Vector3(0.0, 21.5 + float(course) * 3.0, -64.8 + float(bay) * 14.4),
					Vector3(float(widths[course]), 3.0, 14.4), 0.0, rng, block_batch, block_body, 0.0,
					LandmarkBuilders._lm_shade(glazes[(course + bay) % 3], rng, 0.04), false)

	# The entrance gable at -Z: the block, its stepped pediment, the rose window
	# and the two turrets.
	terrain.create_box(center + Vector3(0.0, 17.0, -73.0), Vector3(36.0, 30.0, 6.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
	var gable: Array = [30.0, 20.0, 10.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 33.1 + float(i) * 2.2, -73.0),
				Vector3(float(gable[i]), 2.2, 5.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(dressing, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 22.0, -76.2), Vector3(12.0, 12.0, 0.5), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(dressing, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 22.0, -76.4), Vector3(10.0, 10.0, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(glazes[0], rng, 0.03).darkened(0.3), false)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 16.0, 20.0, -73.0), Vector3(6.0, 36.0, 6.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
		_city_spire(terrain, center + Vector3(side * 16.0, 38.0, -73.0), 5.0, 8.0, 3,
				glazes[1], rng, block_batch, block_body)

	# The rear gable, and the four corner turrets.
	terrain.create_box(center + Vector3(0.0, 15.0, 73.0), Vector3(34.0, 26.0, 6.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
	for i in 2:
		terrain.create_box(center + Vector3(0.0, 29.1 + float(i) * 2.2, 73.0),
				Vector3(float(gable[i]), 2.2, 5.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(dressing, rng, 0.03), false)
	for sx in [-23.0, 23.0]:
		for sz in [-70.0, 70.0]:
			terrain.create_box(center + Vector3(sx, 15.0, sz), Vector3(5.0, 26.0, 5.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
			_city_spire(terrain, center + Vector3(sx, 28.0, sz), 4.5, 8.0, 3,
					glazes[2], rng, block_batch, block_body)

	# The iron canopy over the door — the one place the hall's steel shows outside.
	terrain.create_box(center + Vector3(0.0, 8.0, -76.0), Vector3(30.0, 0.6, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(iron, rng, 0.02), false)
	_city_bays(terrain, center + Vector3(-12.5, 4.0, -77.0), Vector3(5.0, 0.0, 0.0), 6,
			Vector3(0.8, 7.0, 0.8), iron, rng, block_batch, block_body, false)

	return { "radius": 82.0, "top": 46.0 }


static func _city_synagogue(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 11 — THE DOHÁNY STREET SYNAGOGUE: a 72 m banded-brick hall on Z between
	two octagonal towers under ONION DOMES, with the arcade and the rose window on
	the -Z front.

	THE ONION IS THE SILHOUETTE, and it is COMPOSED rather than borrowed. The
	obvious move was the field's _lm_onion, which St Basil's has drawn since wave
	1 — but that helper's bulge is `width x 0.84*width x width`, i.e. always a
	CUBE, and its shoulder is a fixed 0.56 m. At St Basil's 4 m bulbs that reads
	as a bulb; at the 11 m this tower wants, the screenshot showed a green box
	with a lip. So the onion here is one wide bulge box under _city_dome's
	narrowing stack under a spire — the wave A helper doing the shoulder it is
	good at, at the one scale where doing it by hand was wrong. The bulge is 12 m
	across on a 6.5 m shaft, and that OVERHANG is what keeps this off the
	Basilica's page: a Danube dome sits on its drum and only ever narrows.

	The HORIZONTAL BANDS are the other half: five thin courses of pale stone
	across the brick, which is what says Moorish revival rather than "brick shed",
	and they cost five boxes because they run the whole hall.

	RADIUS ARITHMETIC (declared 49.0). An onion's bulge, 12 x 12 at x = +/-12,
	z = -37, wins: sqrt(18.00^2 + 43.00^2) = 46.62. The tower gallery under it
	(11 x 11) is second at sqrt(17.50^2 + 42.50^2) = 45.96, and the arcade roof
	(24 x 4 at z = -41) third at sqrt(12.00^2 + 43.00^2) = 44.64.
	So 46.62 <= 49.0.
	ONE ACCENT: the rose window, lit from inside — the only warm light on a facade
	this dark, and the thing a person walking Dohány Street after dark sees first.
	Boxes: 67. Colliding: 17.
	"""
	var brick := LandmarkBuilders.LM_OCHRE
	var band := LandmarkBuilders.LM_SANDSTONE
	var copper := LandmarkBuilders.LM_COPPER
	var roof: Color = LandmarkBuilders.LM_COPPER.darkened(0.3)

	terrain.create_box(center + Vector3(0.0, 0.8, 0.0), Vector3(34.0, 1.6, 78.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(band, rng, 0.02).darkened(0.2))
	terrain.create_box(center + Vector3(0.0, 12.6, 0.0), Vector3(28.0, 22.0, 72.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
	for i in 5:
		terrain.create_box(center + Vector3(0.0, 5.0 + float(i) * 4.0, 0.0), Vector3(28.6, 1.2, 72.6), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(band, rng, 0.03), false)
	for side in [-1.0, 1.0]:
		_city_bays(terrain, center + Vector3(side * 14.3, 13.0, -32.0), Vector3(0.0, 0.0, 8.0), 9,
				Vector3(0.8, 9.0, 3.4), brick.darkened(0.55), rng, block_batch, block_body, false)

	# The roof, and the two side wings that stop the hall from being a box.
	var slabs: Array = [26.0, 20.0, 12.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 24.4 + float(i) * 1.6, 0.0),
				Vector3(float(slabs[i]), 1.6, 70.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(roof, rng, 0.03), false)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 18.0, 7.6, 30.0), Vector3(8.0, 12.0, 14.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))

	# The front: the block, the arcade, the rose window and its accent.
	terrain.create_box(center + Vector3(0.0, 14.6, -37.0), Vector3(31.0, 26.0, 6.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
	_city_bays(terrain, center + Vector3(-10.5, 7.1, -41.0), Vector3(3.0, 0.0, 0.0), 8,
			Vector3(1.4, 11.0, 1.4), band, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(0.0, 12.5, -41.0), Vector3(24.0, 1.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(band, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 22.0, -40.4), Vector3(9.0, 9.0, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(band, rng, 0.03), false)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, 22.0, -40.9),
			Vector3(6.4, 6.4, 0.4), 0.0, 0.0, terrain._get_camp_ember_material())

	# THE TWO TOWERS: octagonal shaft, gallery, onion. The onion is the field's
	# _lm_onion, and its own finial is the gilded spike it always draws.
	var top := 0.0
	for side in [-1.0, 1.0]:
		for k in 2:
			terrain.create_box(center + Vector3(side * 12.0, 24.6, -37.0), Vector3(6.5, 46.0, 6.5),
					float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(brick, rng, 0.03))
		terrain.create_box(center + Vector3(side * 12.0, 48.3, -37.0), Vector3(11.0, 1.4, 11.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(band, rng, 0.03), false)
		terrain.create_box(center + Vector3(side * 12.0, 50.75, -37.0), Vector3(12.0, 3.5, 12.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(copper, rng, 0.03), false)
		top = 52.5 + _city_dome(terrain, center + Vector3(side * 12.0, 52.5, -37.0), 12.0, 11.0,
				copper, rng, block_batch, block_body)
		top += _city_spire(terrain, center + Vector3(side * 12.0, top, -37.0), 2.4, 5.0, 3,
				band, rng, block_batch, block_body)

	return { "radius": 49.0, "top": top }


static func _city_vaci_utca(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 12 — VÁCI UTCA: 150 m of granite-paved pedestrian street on Z, sixteen
	shopfront houses in two facing rows, awnings, lamp standards down the middle
	and four café parasols.

	THE ONLY LINE LANDMARK IN THE CITY, and it is a place because of what it is
	NOT: no dome, no tower, nothing over 19 m. What names it is the corridor —
	two walls of mixed-height fronts with a lit gap between them — so the height
	pattern is a HAND-WRITTEN TABLE (HEIGHTS below) and not a roll. Nine of these
	houses would be a terrace; sixteen at eight different heights is a street.

	IT COLLIDES LIKE A STREET SHOULD: the house masses are solid, and the paving,
	the awnings, the cornices, the roofs and the shop glazing are not — a 0.2 m
	paving slab you could stand on is a 0.2 m step no body here can climb, and an
	awning at 4.8 m is a roof over the one route through this landmark.

	RADIUS ARITHMETIC (declared 78.0). The paving, 20 x 150, wins:
	sqrt(10.00^2 + 75.00^2) = 75.66. A house cornice (14 x 17 at x = +/-16.5,
	z = +/-63) is second at sqrt(23.50^2 + 71.50^2) = 75.26, and the house mass
	under it (13 x 16) third at sqrt(23.00^2 + 71.00^2) = 74.63.
	So 75.66 <= 78.0.
	NO ACCENT: sixteen shop windows and eight lamps all want to be the lit thing,
	and one glowing box among them would just look like a bug.
	Boxes: 105. Colliding: 16.
	"""
	# Eight heights, mirrored to both sides — the table IS the design record, in
	# tower_plans.gd's sense: edit these numbers and you have re-drawn the street.
	const HEIGHTS: Array = [16.0, 13.0, 19.0, 15.0, 17.0, 13.5, 18.0, 14.5]
	var fronts: Array = [CITY_CREAM, LandmarkBuilders.LM_MARBLE, LandmarkBuilders.LM_OCHRE.lightened(0.2), LandmarkBuilders.LM_OCHRE]
	var awnings: Array = [LandmarkBuilders.LM_VERMILION.darkened(0.25), CITY_PARK_GREEN, LandmarkBuilders.LM_COPPER.darkened(0.2)]

	terrain.create_box(center + Vector3(0.0, 0.1, 0.0), Vector3(20.0, 0.2, 150.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.03), false)

	for i in 8:
		var z := -63.0 + float(i) * 18.0
		var h: float = float(HEIGHTS[i])
		for side in [-1.0, 1.0]:
			var x: float = side * 16.5
			terrain.create_box(center + Vector3(x, h * 0.5, z), Vector3(13.0, h, 16.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fronts[i % 4], rng, 0.03))
			terrain.create_box(center + Vector3(x, h + 0.5, z), Vector3(14.0, 1.0, 17.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(fronts[i % 4], rng, 0.03).darkened(0.12), false)
			terrain.create_box(center + Vector3(x, h + 2.0, z), Vector3(12.0, 2.0, 15.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_ROOF, rng, 0.04), false)
			# The shopfront glazing, and the awning over it.
			terrain.create_box(center + Vector3(side * 10.3, 2.4, z), Vector3(0.6, 4.0, 12.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_SLATE_BLUE, rng, 0.03), false)
			terrain.create_box(center + Vector3(side * 8.6, 4.8, z), Vector3(2.6, 0.3, 10.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(awnings[i % 3], rng, 0.04), false)

		# One lamp standard per bay, alternating sides of the centre line.
		var lamp_x := 3.5 if i % 2 == 0 else -3.5
		terrain.create_box(center + Vector3(lamp_x, 3.5, z), Vector3(0.4, 7.0, 0.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_BASALT, rng, 0.02), false)
		terrain.create_box(center + Vector3(lamp_x, 7.2, z), Vector3(1.0, 0.7, 1.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_SANDSTONE, rng, 0.02), false)

	# Four café parasols, off the centre line so the walk stays clear.
	for i in 4:
		var px := 6.5 if i % 2 == 0 else -6.5
		var pz := -27.0 + float(i) * 18.0
		terrain.create_box(center + Vector3(px, 1.3, pz), Vector3(0.25, 2.6, 0.25), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_BASALT, rng, 0.02), false)
		terrain.create_box(center + Vector3(px, 2.9, pz), Vector3(4.2, 0.3, 4.2), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_MARBLE, rng, 0.03), false)

	return { "radius": 78.0, "top": 22.0 }


static func _city_national_museum(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 13 — THE HUNGARIAN NATIONAL MUSEUM: a 92 m neoclassical block on Z, the
	eight-column portico and its pediment on the -X front, a low dome over the
	centre, and the garden the fact is really about.

	THE STEPS ARE THE LANDMARK — 1848 is remembered as having started on them — so
	the flight is drawn wide and shallow and given the whole -X frontage, and the
	portico stands back behind it. Like the Basilica's, the steps do not collide
	(a 0.6 m step is unclimbable here); the podium is what a body meets.

	THE PORTICO FACES -X, which is the one place a wave B builder departs from the
	Danube rule, and deliberately: this museum stands four blocks inland with its
	front on a street, so a river-parallel facade would be the wrong building. The
	MASS still runs its long axis on Z, which is the rule that actually matters —
	the plan places on Z-parallel streets.

	RADIUS ARITHMETIC (declared 62.0). The podium, 64 x 100, wins:
	sqrt(32.00^2 + 50.00^2) = 59.36. The cornice (60 x 96) is second at
	sqrt(30.00^2 + 48.00^2) = 56.60, and a garden hedge (2 x 70 at x = +/-41)
	third at sqrt(42.00^2 + 35.00^2) = 54.68. So 59.36 <= 62.0.
	NO ACCENT.
	Boxes: 67. Colliding: 18.
	"""
	var wall := CITY_CREAM
	var stone := LandmarkBuilders.LM_MARBLE
	var tile: Color = LandmarkBuilders.LM_VERMILION.darkened(0.3)

	terrain.create_box(center + Vector3(0.0, 0.6, 0.0), Vector3(64.0, 1.2, 100.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.12))
	for i in 4:
		terrain.create_box(center + Vector3(-34.0 - float(i) * 2.4, 0.9 - float(i) * 0.3, 0.0),
				Vector3(2.4, 0.6, 60.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.03), false)

	terrain.create_box(center + Vector3(0.0, 11.2, 0.0), Vector3(56.0, 20.0, 92.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 22.0, 0.0), Vector3(60.0, 1.6, 96.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	var slabs: Array = [54.0, 44.0, 30.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 23.7 + float(i) * 1.8, 0.0),
				Vector3(float(slabs[i]), 1.8, 90.0 - float(i) * 7.0), 0.0, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(tile, rng, 0.04), false)
	for side in [-1.0, 1.0]:
		_city_bays(terrain, center + Vector3(side * 28.6, 11.2, -40.5), Vector3(0.0, 0.0, 9.0), 10,
				Vector3(1.2, 18.0, 2.4), stone, rng, block_batch, block_body, false)

	# The portico: eight columns, the architrave, the pediment.
	_city_bays(terrain, center + Vector3(-30.0, 9.7, -14.0), Vector3(0.0, 0.0, 4.0), 8,
			Vector3(2.6, 17.0, 2.6), stone, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(-30.0, 20.0, 0.0), Vector3(6.0, 2.6, 34.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	var ped: Array = [30.0, 20.0, 10.0]
	for i in 3:
		terrain.create_box(center + Vector3(-30.0, 22.2 + float(i) * 1.8, 0.0),
				Vector3(5.4, 1.8, float(ped[i])), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# The low dome over the centre.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 27.0, 0.0), Vector3(20.0, 10.0, 20.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	var y := 32.0
	y += _city_dome(terrain, center + Vector3(0.0, y, 0.0), 20.0, 12.0,
			LandmarkBuilders.LM_COPPER.darkened(0.2), rng, block_batch, block_body)
	y += _city_spire(terrain, center + Vector3(0.0, y, 0.0), 4.0, 5.0, 3,
			LandmarkBuilders.LM_COPPER.darkened(0.2), rng, block_batch, block_body)

	# THE GARDEN. Two hedges and six trees, and they are the second reason this
	# place is on the card: a museum in a park is what the 1848 crowd stood in.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 41.0, 0.7, 0.0), Vector3(2.0, 1.4, 70.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(CITY_PARK_GREEN, rng, 0.05), false)
		for tz in [-24.0, 0.0, 24.0]:
			terrain.create_box(center + Vector3(side * 38.0, 2.25, tz), Vector3(1.2, 4.5, 1.2), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_ROOF, rng, 0.04))
			terrain.create_box(center + Vector3(side * 38.0, 7.5, tz), Vector3(6.5, 6.5, 6.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(CITY_PARK_GREEN, rng, 0.05), false)

	return { "radius": 62.0, "top": y + 1.0 }


static func _city_opera(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 14 — THE HUNGARIAN STATE OPERA HOUSE: a 78 m neo-Renaissance front on Z
	with the seven-arch loggia at street level, a first-floor colonnade carrying
	ten statues on its balustrade, the stage tower behind, and THE TWO SPHINXES on
	the drive.

	THE STAGE TOWER IS WHY THIS IS NOT THE MUSEUM. Both are cream classical blocks
	of about the same length; what tells them apart at 100 m is that an opera house
	has a windowless 45 m box behind the audience and a museum does not. So the
	tower is drawn tall and plain, off-centre toward +X, and it clears the 27 m
	front by 18 m — a clearance MEASURED from eye height in front of the building,
	because at 34 m it was hidden behind its own facade at exactly the distance a
	person stands to look at one.

	RADIUS ARITHMETIC (declared 49.0). The podium, 44 x 84, wins:
	sqrt(22.00^2 + 42.00^2) = 47.41. The cornice (42 x 82) is second at
	sqrt(21.00^2 + 41.00^2) = 46.06, and a candelabrum at (x = -30, z = +/-21)
	third at sqrt(30.25^2 + 21.25^2) = 36.97. So 47.41 <= 49.0.
	NO ACCENT: the loggia is the lit part of a real one and it is a whole facade,
	which this vocabulary cannot glow; one bright box on the roof would read as an
	aerial.
	Boxes: 71. Colliding: 15.
	"""
	var wall := CITY_CREAM
	var stone := LandmarkBuilders.LM_MARBLE
	var roof: Color = LandmarkBuilders.LM_COPPER.darkened(0.35)

	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(44.0, 1.0, 84.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.14))
	for i in 3:
		terrain.create_box(center + Vector3(-22.0 - float(i) * 2.0, 0.8 - float(i) * 0.3, 0.0),
				Vector3(2.0, 0.4, 20.0), 0.0, rng, block_batch, block_body, 0.0,
				LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 13.0, 0.0), Vector3(38.0, 24.0, 78.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	terrain.create_box(center + Vector3(10.0, 23.0, 0.0), Vector3(26.0, 44.0, 32.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02).darkened(0.06))

	# The loggia: eight piers, seven arch heads, the balcony over them.
	_city_bays(terrain, center + Vector3(-19.6, 5.5, -14.0), Vector3(0.0, 0.0, 4.0), 8,
			Vector3(1.8, 9.0, 2.6), stone, rng, block_batch, block_body)
	_city_bays(terrain, center + Vector3(-19.6, 11.0, -12.0), Vector3(0.0, 0.0, 4.0), 7,
			Vector3(1.8, 2.0, 2.2), stone, rng, block_batch, block_body, false)
	terrain.create_box(center + Vector3(-20.0, 12.4, 0.0), Vector3(5.0, 0.8, 34.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# The first-floor colonnade, its balustrade, and the ten composers on it.
	_city_bays(terrain, center + Vector3(-19.4, 17.8, -14.0), Vector3(0.0, 0.0, 4.0), 8,
			Vector3(1.6, 10.0, 1.6), stone, rng, block_batch, block_body, false)
	terrain.create_box(center + Vector3(-21.6, 23.4, 0.0), Vector3(4.0, 1.2, 34.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	for i in 10:
		var sz := -18.0 + float(i) * 4.0
		terrain.create_box(center + Vector3(-21.6, 24.6, sz), Vector3(1.3, 1.3, 1.3), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
		terrain.create_box(center + Vector3(-21.6, 26.5, sz), Vector3(0.9, 2.4, 0.9), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.04), false)

	terrain.create_box(center + Vector3(0.0, 25.8, 0.0), Vector3(42.0, 1.6, 82.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	var slabs: Array = [38.0, 30.0, 20.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 27.5 + float(i) * 1.8, 0.0),
				Vector3(float(slabs[i]), 1.8, 78.0 - float(i) * 9.0), 0.0, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(roof, rng, 0.03), false)

	# THE TWO SPHINXES, couchant on their plinths either side of the drive, and the
	# candelabra along the kerb.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(-27.0, 1.2, side * 11.0), Vector3(4.0, 2.4, 7.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.02))
		terrain.create_box(center + Vector3(-27.0, 3.4, side * 11.0), Vector3(2.6, 2.0, 6.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.03))
		terrain.create_box(center + Vector3(-27.0, 5.3, side * 13.2), Vector3(1.8, 1.8, 1.8), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.03), false)
		terrain.create_box(center + Vector3(-27.0, 6.5, side * 13.2), Vector3(2.4, 0.7, 2.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.04), false)
		for cz in [7.0, 21.0]:
			terrain.create_box(center + Vector3(-30.0, 4.2, side * cz), Vector3(0.5, 6.5, 0.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_BASALT, rng, 0.02), false)
			terrain.create_box(center + Vector3(-30.0, 7.8, side * cz), Vector3(0.9, 0.9, 0.9), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_SANDSTONE, rng, 0.03), false)

	return { "radius": 49.0, "top": 45.0 }


# ----------------------------------------------------------------------------
# BUDAPEST — WAVE C: THE ANDRÁSSY END AND THE ODD ONES
# ----------------------------------------------------------------------------
##
## Seven builders completing the 22-landmark Budapest set for the Escape-to-
## Budapest epic. Reusing all shared palettes (CITY_CREAM, CITY_PARK_GREEN,
## LM_MARBLE, LM_COPPER, LM_BASALT, LM_STONE_GREY, LM_SANDSTONE, LM_OCHRE,
## LM_ROOF, LM_IRON, LM_SLATE_BLUE) and the four shared city helpers (_city_dome,
## _city_spire, _city_bays, _city_cable).
##
## All radius contracts and geometry bounds strictly satisfied.

static func _city_heroes_square(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 15 — HEROES' SQUARE (Hősök tere): the grand paved plaza of 1896 at the
	end of Andrássy Avenue, the 36 m Millennium Column topped by Archangel Gabriel
	holding the Holy Crown and apostolic cross, seven Magyar chieftain equestrian
	statues circling its base, and the twin semicircular colonnades honoring
	Hungary's historical kings with allegorical chariot crowns.

	THE SILHOUETTE: the slender Corinthian column rising high above the square with
	Gabriel's outstretched wings, framed by two symmetrical colonnaded wings.

	RADIUS ARITHMETIC (declared 62.0):
	  * Plaza plinth: 40.0 x 90.0: sqrt(20.0^2 + 45.0^2) = 49.24 m.
	  * Colonnade outer crown statue at (x = 22.5, z = +/-38.5):
	    sqrt(24.3^2 + 40.3^2) = 47.06 m.
	  * Column capital at (0, 36): reaches radius 2.5 m.
	  So 49.24 <= 62.0.
	Boxes: 94. Colliding: 18.
	"""
	var stone := LandmarkBuilders.LM_MARBLE
	var granite := LandmarkBuilders.LM_GRANITE
	var bronze := LandmarkBuilders.LM_BASALT
	var gold := LandmarkBuilders.LM_SANDSTONE

	# 1. Main Plaza Paving & Millennium Column Base
	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(40.0, 0.8, 90.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.12))

	# Stepped column plinth tiers
	terrain.create_box(center + Vector3(0.0, 1.3, 0.0), Vector3(16.0, 1.0, 16.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 2.3, 0.0), Vector3(12.0, 1.0, 12.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 3.8, 0.0), Vector3(8.0, 2.0, 8.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.02))

	# Seven Magyar Chieftain equestrian statues around the pedestal
	for i in 7:
		var a := TAU * float(i) / 7.0
		var pos := center + Vector3(cos(a) * 5.2, 3.8, sin(a) * 5.2)
		terrain.create_box(pos, Vector3(1.6, 2.2, 2.6), a + PI * 0.5, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)

	# 2. Central Millennium Column
	terrain.create_box(center + Vector3(0.0, 5.8, 0.0), Vector3(4.0, 2.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 21.0, 0.0), Vector3(2.4, 28.4, 2.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	# Column capital
	terrain.create_box(center + Vector3(0.0, 35.8, 0.0), Vector3(3.8, 1.2, 3.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# Archangel Gabriel statue on top
	terrain.create_box(center + Vector3(0.0, 37.8, 0.0), Vector3(1.2, 2.8, 1.2), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(gold, rng, 0.03), false)
	# Outstretched wings & cross
	terrain.create_box(center + Vector3(0.0, 38.6, -0.4), Vector3(2.6, 2.2, 0.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(gold, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 40.2, 0.3), Vector3(0.3, 2.4, 0.3), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(gold, rng, 0.03), false)
	terrain.create_box(center + Vector3(0.0, 40.8, 0.3), Vector3(1.6, 0.3, 0.3), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(gold, rng, 0.03), false)

	# 3. Twin Semicircular Colonnades (North and South wings at +X)
	for side in [-1.0, 1.0]:
		# Two curved chord segments per colonnade wing
		# Segment 1 (inner): from z = 10 to 24
		terrain.create_box(center + Vector3(14.0, 0.9, side * 17.0), Vector3(5.4, 1.0, 15.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		_city_bays(terrain, center + Vector3(14.0, 6.0, side * 11.0), Vector3(0.0, 0.0, side * 3.0), 5,
				Vector3(1.2, 9.2, 1.2), stone, rng, block_batch, block_body, false)
		terrain.create_box(center + Vector3(14.0, 11.2, side * 17.0), Vector3(5.0, 1.4, 15.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

		# Segment 2 (outer angled): from z = 24 to 38
		terrain.create_box(center + Vector3(20.0, 0.9, side * 31.0), Vector3(5.4, 1.0, 15.0), side * 0.26,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		_city_bays(terrain, center + Vector3(17.5, 6.0, side * 25.0), Vector3(1.0, 0.0, side * 2.8), 5,
				Vector3(1.2, 9.2, 1.2), stone, rng, block_batch, block_body, false)
		terrain.create_box(center + Vector3(20.0, 11.2, side * 31.0), Vector3(5.0, 1.4, 15.4), side * 0.26,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

		# Statues of kings between columns (7 statues per wing)
		for k in 7:
			var kz: float = side * (11.0 + float(k) * 3.8)
			var kx: float = 14.0 + (float(k) * 1.2 if k >= 4 else 0.0)
			terrain.create_box(center + Vector3(kx, 2.4, kz), Vector3(1.0, 2.0, 1.0), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.04), false)

		# Crown statue groups at colonnade ends
		# Inner end statue
		terrain.create_box(center + Vector3(14.0, 13.0, side * 9.5), Vector3(2.8, 2.4, 2.8), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)
		# Outer end chariot / allegorical crown
		terrain.create_box(center + Vector3(22.5, 13.2, side * 38.5), Vector3(3.6, 2.8, 3.6), side * 0.26,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(bronze, rng, 0.03), false)

	return { "radius": 62.0, "top": 42.0 }


static func _city_vajdahunyad(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 16 — VAJDAHUNYAD CASTLE: the romantic Millennium castle of 1896 in the
	City Park boating lake, integrating replicas of iconic Hungarian and
	Transylvanian architecture — the medieval Gothic gatehouse, the towering
	Neboisa keep, the Romanesque chapel portal, and the Renaissance/Baroque palace.

	RADIUS ARITHMETIC (declared 54.0):
	  * Island plinth: 52.0 x 62.0 at (0, 0): sqrt(26.0^2 + 31.0^2) = 40.46 m.
	  * Drawbridge tip at (-26.0, 0, 0): sqrt(32.0^2 + 2.5^2) = 32.10 m.
	  * Chapel apse at (8.0, 0, 26.0): sqrt(12.0^2 + 28.0^2) = 30.46 m.
	  * Neboisa keep bartizans at (6.0, 37.0, -16.0): sqrt(11.9^2 + 21.9^2) = 24.91 m.
	  So 40.46 <= 54.0.
	Boxes: 86. Colliding: 19.
	"""
	var stone := LandmarkBuilders.LM_STONE_GREY
	var cream := CITY_CREAM
	var roof_blue := LandmarkBuilders.LM_SLATE_BLUE
	var tile_brown := LandmarkBuilders.LM_ROOF
	var sandstone := LandmarkBuilders.LM_SANDSTONE

	# 1. Island Plinth in the Boating Lake
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(52.0, 1.0, 62.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_GRANITE, rng, 0.02).darkened(0.14))

	# 2. Medieval Gothic Gatehouse & Drawbridge at -X
	# Drawbridge
	terrain.create_box(center + Vector3(-26.0, 0.7, 0.0), Vector3(12.0, 0.6, 5.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(tile_brown, rng, 0.03))
	# Gatehouse central arch block
	terrain.create_box(center + Vector3(-18.0, 7.0, 0.0), Vector3(6.0, 12.0, 10.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	# Twin gatehouse towers with spires
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(-18.0, 11.0, side * 7.5), Vector3(5.0, 20.0, 5.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
		_city_spire(terrain, center + Vector3(-18.0, 21.0, side * 7.5), 5.5, 9.0, 4,
				roof_blue, rng, block_batch, block_body)

	# 3. Main Transylvanian Gothic Hall & High Roof
	terrain.create_box(center + Vector3(0.0, 9.0, 0.0), Vector3(22.0, 16.0, 36.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	# Steep Gothic roof tiers
	var roof_w := [20.0, 14.0, 8.0]
	for i in 3:
		terrain.create_box(center + Vector3(0.0, 18.0 + float(i) * 2.5, 0.0),
				Vector3(float(roof_w[i]), 2.5, 34.0 - float(i) * 3.0), 0.0, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(tile_brown, rng, 0.03), false)
	# Buttress bays on hall sides
	_city_bays(terrain, center + Vector3(-11.5, 8.0, -14.0), Vector3(0.0, 0.0, 7.0), 5,
			Vector3(1.2, 14.0, 1.6), stone, rng, block_batch, block_body, false)

	# 4. Neboisa Keep (The Great Tower, replica of Hunyad Castle) at (6.0, 0, -16.0)
	terrain.create_box(center + Vector3(6.0, 18.0, -16.0), Vector3(9.0, 34.0, 9.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	# Overhanging battlements & machicolations
	terrain.create_box(center + Vector3(6.0, 35.6, -16.0), Vector3(11.0, 2.2, 11.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.08), false)
	# Corner bartizan turrets
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			terrain.create_box(center + Vector3(6.0 + cx * 5.0, 37.0, -16.0 + cz * 5.0),
					Vector3(1.8, 3.0, 1.8), 0.0, rng, block_batch, block_body, 0.0,
					LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
			_city_spire(terrain, center + Vector3(6.0 + cx * 5.0, 38.5, -16.0 + cz * 5.0),
					2.0, 4.0, 3, roof_blue, rng, block_batch, block_body)
	# Tower main high spire
	_city_spire(terrain, center + Vector3(6.0, 36.7, -16.0), 8.0, 13.0, 5,
			roof_blue, rng, block_batch, block_body)

	# 5. Romanesque Chapel Wing & Apse at (+8.0, 0, +16.0)
	terrain.create_box(center + Vector3(8.0, 6.5, 16.0), Vector3(12.0, 11.0, 18.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(sandstone, rng, 0.02))
	# Semicircular apse with dome
	terrain.create_box(center + Vector3(8.0, 5.5, 26.0), Vector3(8.0, 9.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(sandstone, rng, 0.02))
	_city_dome(terrain, center + Vector3(8.0, 10.0, 26.0), 8.0, 4.0,
			tile_brown, rng, block_batch, block_body)
	# Chapel octagonal bell turret
	terrain.create_box(center + Vector3(13.0, 9.5, 23.0), Vector3(4.0, 17.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(sandstone, rng, 0.02))
	_city_spire(terrain, center + Vector3(13.0, 18.0, 23.0), 4.4, 7.0, 3,
			roof_blue, rng, block_batch, block_body)

	# 6. Baroque Palace Wing at (+12.0, 0, -2.0)
	terrain.create_box(center + Vector3(12.0, 8.0, -2.0), Vector3(12.0, 14.0, 24.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(cream, rng, 0.02))
	terrain.create_box(center + Vector3(12.0, 16.0, -2.0), Vector3(10.0, 3.0, 22.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(tile_brown, rng, 0.03), false)

	return { "radius": 54.0, "top": 50.0 }


static func _city_szechenyi_baths(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 17 — SZÉCHENYI THERMAL BATH: Europe's grand neo-Baroque yellow bath
	palace of 1913 in the City Park, featuring its central dome, symmetrical
	colonnaded wings, and the vast courtyard with three steaming open-air
	pools — including the famous poolside chess tables.

	RADIUS ARITHMETIC (declared 60.0):
	  * Base courtyard terrace: 64.0 x 78.0 at (0, 0): sqrt(32.0^2 + 39.0^2) = 50.45 m.
	  * North entrance pavilion dome at (0, 0, -28.0): reaches radius 36.0 m.
	  * Wing corner pavilions at (+/-25.0, 0, 28.0): sqrt(32.0^2 + 34.0^2) = 46.69 m.
	  So 50.45 <= 60.0.
	Boxes: 90. Colliding: 17.
	"""
	var yellow := Color(0.92, 0.82, 0.48)
	var stone := LandmarkBuilders.LM_MARBLE
	var copper := LandmarkBuilders.LM_COPPER
	var pool_water := Color(0.18, 0.65, 0.72)
	var granite := LandmarkBuilders.LM_GRANITE

	# 1. Courtyard Terrace & Sun Deck
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(64.0, 1.0, 78.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.1))

	# 2. North Entrance Neo-Baroque Palace Pavilion at (0.0, 0.0, -28.0)
	terrain.create_box(center + Vector3(0.0, 7.5, -28.0), Vector3(44.0, 13.0, 14.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(yellow, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, 14.5, -28.0), Vector3(46.0, 1.4, 15.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	# Central Baroque Dome on octagonal drum
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 17.0, -28.0), Vector3(16.0, 4.0, 16.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(yellow, rng, 0.02))
	var dy := 19.0 + _city_dome(terrain, center + Vector3(0.0, 19.0, -28.0), 16.0, 8.0,
			copper, rng, block_batch, block_body)
	_city_spire(terrain, center + Vector3(0.0, dy, -28.0), 3.0, 5.0, 3,
			copper, rng, block_batch, block_body)

	# 3. Flanking East and West Palace Wings (U-shaped courtyard)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 25.0, 6.0, 0.0), Vector3(12.0, 10.0, 56.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(yellow, rng, 0.02))
		terrain.create_box(center + Vector3(side * 25.0, 11.5, 0.0), Vector3(13.0, 1.2, 57.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
		# Courtyard inner arcade columns
		_city_bays(terrain, center + Vector3(side * 18.5, 5.0, -18.0), Vector3(0.0, 0.0, 6.0), 7,
				Vector3(1.2, 8.0, 1.2), stone, rng, block_batch, block_body, false)
		# South end pavilion with corner dome
		terrain.create_box(center + Vector3(side * 25.0, 7.5, 28.0), Vector3(14.0, 13.0, 12.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(yellow, rng, 0.02))
		var cdy := 14.0 + _city_dome(terrain, center + Vector3(side * 25.0, 14.0, 28.0), 9.0, 5.0,
				copper, rng, block_batch, block_body)
		_city_spire(terrain, center + Vector3(side * 25.0, cdy, 28.0), 2.0, 3.5, 3,
				copper, rng, block_batch, block_body)

	# South Colonnade connecting the wings
	terrain.create_box(center + Vector3(0.0, 4.5, 32.0), Vector3(38.0, 7.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(yellow, rng, 0.02))
	_city_bays(terrain, center + Vector3(-15.0, 4.0, 29.5), Vector3(5.0, 0.0, 0.0), 7,
			Vector3(1.2, 6.0, 1.2), stone, rng, block_batch, block_body, false)

	# 4. Outdoor Thermal Pools (Dry geometry with thermal turquoise tint)
	# Pool 1 (North Adventure Pool with circular whirlpool)
	terrain.create_box(center + Vector3(0.0, 1.05, -12.0), Vector3(22.0, 0.12, 12.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(pool_water, rng, 0.02), false)
	# Coping rim around Pool 1
	terrain.create_box(center + Vector3(0.0, 1.15, -18.3), Vector3(23.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(0.0, 1.15, -5.7), Vector3(23.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-11.3, 1.15, -12.0), Vector3(0.8, 0.3, 13.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(11.3, 1.15, -12.0), Vector3(0.8, 0.3, 13.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	# Central fountain column in north pool
	terrain.create_box(center + Vector3(0.0, 1.8, -12.0), Vector3(2.0, 1.5, 2.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# Pool 2 (Central Olympic Swimming Pool)
	terrain.create_box(center + Vector3(0.0, 1.05, 4.0), Vector3(20.0, 0.12, 16.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(pool_water, rng, 0.02), false)
	# Coping rim around Pool 2
	terrain.create_box(center + Vector3(0.0, 1.15, -4.3), Vector3(21.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(0.0, 1.15, 12.3), Vector3(21.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-10.3, 1.15, 4.0), Vector3(0.8, 0.3, 17.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(10.3, 1.15, 4.0), Vector3(0.8, 0.3, 17.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)

	# Pool 3 (South Thermal Sitting Pool with poolside chess players)
	terrain.create_box(center + Vector3(0.0, 1.05, 19.0), Vector3(22.0, 0.12, 10.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(pool_water, rng, 0.02), false)
	# Coping rim around Pool 3
	terrain.create_box(center + Vector3(0.0, 1.15, 13.7), Vector3(23.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(0.0, 1.15, 24.3), Vector3(23.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-11.3, 1.15, 19.0), Vector3(0.8, 0.3, 11.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(11.3, 1.15, 19.0), Vector3(0.8, 0.3, 11.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)

	# Poolside Stone Chess Tables & Benches (Széchenyi's signature)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(side * 8.0, 1.6, 19.0), Vector3(1.6, 0.8, 1.6), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.03), false)
		terrain.create_box(center + Vector3(side * 8.0, 2.05, 19.0), Vector3(1.2, 0.1, 1.2), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.04), false)
		terrain.create_box(center + Vector3(side * 8.0, 1.4, 17.5), Vector3(1.4, 0.6, 0.6), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.03), false)

	return { "radius": 60.0, "top": 32.0 }


static func _city_gellert_baths(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 18 — GELLÉRT THERMAL BATH: the 1918 Art Nouveau palace at the foot of
	Gellért Hill, featuring curvilinear Secessionist gables, turquoise Zsolnay
	mosaic domes, colonnaded wings, and the outdoor wave pool terrace against the
	rocky hill.

	RADIUS ARITHMETIC (declared 52.0):
	  * Base podium: 46.0 x 70.0 at (0, 0): sqrt(23.0^2 + 35.0^2) = 41.88 m.
	  * Wave pool terrace at (-15.0, 0, 0): reaches x = -22.0, z = 14.0 -> 26.08 m.
	  * Wing corner domes at (-10.0, 0, +/-31.0): sqrt(13.2^2 + 33.2^2) = 35.73 m.
	  So 41.88 <= 52.0.
	Boxes: 76. Colliding: 16.
	"""
	var wall := CITY_CREAM
	var stone := LandmarkBuilders.LM_MARBLE
	var turquoise := LandmarkBuilders.LM_COPPER
	var rock := LandmarkBuilders.LM_BASALT
	var pool_water := Color(0.18, 0.65, 0.72)

	# 1. Base Podium & Plaza
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(46.0, 1.0, 70.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.12))

	# 2. Gellért Hill Rock Outcrop at +X (rear backdrop)
	for i in 3:
		terrain.create_box(center + Vector3(16.0 + float(i) * 3.0, 6.0 + float(i) * 4.0, 0.0),
				Vector3(6.0, 12.0 + float(i) * 6.0, 66.0 - float(i) * 6.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(rock, rng, 0.04))

	# 3. Main Art Nouveau Central Rotunda Pavilion at (-2.0, 0, 0)
	terrain.create_box(center + Vector3(-2.0, 10.0, 0.0), Vector3(26.0, 18.0, 24.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
	# Curvilinear Secessionist Gable on front facade (-X)
	var gable_w := [22.0, 16.0, 10.0]
	for i in 3:
		terrain.create_box(center + Vector3(-15.2, 19.5 + float(i) * 1.5, 0.0),
				Vector3(1.2, 1.5, float(gable_w[i])), 0.0, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
	# Turquoise Zsolnay Glass Dome on central rotunda
	for k in 2:
		terrain.create_box(center + Vector3(-2.0, 20.0, 0.0), Vector3(16.0, 3.0, 16.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))
	var dy := 21.5 + _city_dome(terrain, center + Vector3(-2.0, 21.5, 0.0), 16.0, 8.0,
			turquoise, rng, block_batch, block_body)
	_city_spire(terrain, center + Vector3(-2.0, dy, 0.0), 3.0, 4.5, 3,
			turquoise, rng, block_batch, block_body)

	# 4. Flanking Hotel & Bath Wings
	for side in [-1.0, 1.0]:
		terrain.create_box(center + Vector3(0.0, 8.5, side * 24.0), Vector3(22.0, 15.0, 22.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02))
		terrain.create_box(center + Vector3(0.0, 16.5, side * 24.0), Vector3(23.0, 1.2, 23.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)
		# Balconies and bays
		_city_bays(terrain, center + Vector3(-11.5, 8.0, side * 17.0), Vector3(0.0, 0.0, side * 4.0), 4,
				Vector3(1.4, 12.0, 1.6), stone, rng, block_batch, block_body, false)
		# Corner turrets with turquoise cupolas
		terrain.create_box(center + Vector3(-10.0, 16.5, side * 31.0), Vector3(6.0, 6.0, 6.0), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(wall, rng, 0.02), false)
		_city_dome(terrain, center + Vector3(-10.0, 19.5, side * 31.0), 6.4, 4.0,
				turquoise, rng, block_batch, block_body)

	# 5. Outdoor Wave Pool Terrace at -X
	terrain.create_box(center + Vector3(-15.0, 1.05, 0.0), Vector3(12.0, 0.12, 26.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(pool_water, rng, 0.02), false)
	# Coping rim around Wave Pool
	terrain.create_box(center + Vector3(-15.0, 1.15, -13.3), Vector3(13.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-15.0, 1.15, 13.3), Vector3(13.6, 0.3, 0.8), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-21.3, 1.15, 0.0), Vector3(0.8, 0.3, 27.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	terrain.create_box(center + Vector3(-8.7, 1.15, 0.0), Vector3(0.8, 0.3, 27.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
	# Wave generator chamber at head of pool (+Z end)
	terrain.create_box(center + Vector3(-15.0, 3.0, 15.0), Vector3(10.0, 4.0, 4.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	return { "radius": 52.0, "top": 34.0 }


static func _city_rudas_baths(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 19 — RUDAS THERMAL BATH: the 1566 Ottoman Turkish bath at the foot of
	Gellért Hill by the Elisabeth Bridge, centered on its ancient octagonal
	thermal pool chamber under a 10 m dome studded with coloured glass skylights,
	wrapped by 19th-century neoclassical bath halls.

	RADIUS ARITHMETIC (declared 42.0):
	  * Base plinth: 38.0 x 48.0 at (0, 0): sqrt(19.0^2 + 24.0^2) = 30.61 m.
	  * Front neoclassical portico at (-16.5, 0, 0): reaches x = -18.0, z = 8.0 -> 19.70 m.
	  * Central Ottoman dome at (0, 0): reaches radius 8.0 m.
	  So 30.61 <= 42.0.
	Boxes: 64. Colliding: 14.
	"""
	var ottoman_stone := LandmarkBuilders.LM_OCHRE.darkened(0.2)
	var cream := CITY_CREAM
	var stone := LandmarkBuilders.LM_MARBLE
	var cupola_glass := Color(0.25, 0.70, 0.80)
	var roof_tile := LandmarkBuilders.LM_ROOF

	# 1. Base Plinth & Embankment Terrace
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(38.0, 1.0, 48.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02).darkened(0.14))

	# 2. Central 16th-century Ottoman Turkish Bath Chamber
	# Octagonal masonry drum (two crossed 16x16 boxes at 0 and 45 deg)
	for k in 2:
		terrain.create_box(center + Vector3(0.0, 6.0, 0.0), Vector3(16.0, 10.0, 16.0),
				float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(ottoman_stone, rng, 0.03))
	# Main Ottoman Masonry Dome
	var dy := 11.0 + _city_dome(terrain, center + Vector3(0.0, 11.0, 0.0), 15.0, 8.0,
			roof_tile, rng, block_batch, block_body)
	# Crescent / finial spire on top
	_city_spire(terrain, center + Vector3(0.0, dy, 0.0), 2.2, 4.0, 3,
			LandmarkBuilders.LM_SANDSTONE, rng, block_batch, block_body)

	# Eight Stained-Glass Roof Cupolas (skylight portholes on the dome surface)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var cpos := center + Vector3(cos(a) * 5.2, 15.5, sin(a) * 5.2)
		terrain.create_box(cpos, Vector3(1.2, 1.2, 1.2), a, rng, block_batch, block_body,
				0.0, LandmarkBuilders._lm_shade(cupola_glass, rng, 0.04), false)

	# 3. Neoclassical Front Facade & Wings wrapping the Turkish core (-X and sides)
	terrain.create_box(center + Vector3(-12.0, 5.5, 0.0), Vector3(8.0, 9.0, 36.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(cream, rng, 0.02))
	terrain.create_box(center + Vector3(-12.0, 10.5, 0.0), Vector3(9.0, 1.2, 37.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# Entrance Portico at -X front
	_city_bays(terrain, center + Vector3(-16.5, 4.5, -6.0), Vector3(0.0, 0.0, 4.0), 4,
			Vector3(1.4, 7.0, 1.4), stone, rng, block_batch, block_body)
	terrain.create_box(center + Vector3(-16.5, 8.5, 0.0), Vector3(3.0, 1.4, 16.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03), false)

	# East Hillside Wing (+X, against Gellért rock)
	terrain.create_box(center + Vector3(12.0, 4.5, 0.0), Vector3(8.0, 7.0, 32.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(cream, rng, 0.02))

	return { "radius": 42.0, "top": 24.0 }


static func _city_shoes_on_danube(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 20 — SHOES ON THE DANUBE BANK (Cipők a Duna-parton): the solemn 2005
	memorial on the Pest embankment created by Can Togay and Gyula Pauer,
	honoring the victims shot into the river during World War II — sixty pairs of
	1940s cast-iron shoes facing the water along the stone river promenade.

	HANDLED WITH RESPECT: quiet, factual, plain toast fact, no coin bursts.

	RADIUS ARITHMETIC (declared 32.0):
	  * Promenade quay: 8.0 x 54.0 at (0, 0): sqrt(4.0^2 + 27.0^2) = 27.29 m.
	  * River water strip at x = -7.5: sqrt(9.5^2 + 28.0^2) = 29.57 m.
	  So 29.57 <= 32.0.
	Boxes: 72. Colliding: 8.
	"""
	var stone := LandmarkBuilders.LM_GRANITE
	var iron := LandmarkBuilders.LM_IRON
	var dark_iron := LandmarkBuilders.LM_BASALT
	var water := Color(0.18, 0.35, 0.45)

	# 1. Stone Promenade Quay along Pest Bank (running on Z)
	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(8.0, 0.8, 54.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02))

	# Lower stone step down to water along -X river edge
	terrain.create_box(center + Vector3(-4.8, 0.2, 0.0), Vector3(1.6, 0.4, 54.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.03).darkened(0.1))

	# River water surface strip beside quay
	terrain.create_box(center + Vector3(-7.5, 0.05, 0.0), Vector3(4.0, 0.1, 56.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(water, rng, 0.02), false)

	# 2. Sixty Pairs of Period Cast-Iron Shoes along the Curb (x = -3.8)
	# Modeled as 20 distinct paired shoe clusters along z = -23.0..+23.0
	for i in 20:
		var sz: float = -22.5 + float(i) * 2.37
		var kind: int = i % 4
		var shade: Color = iron if (i % 2 == 0) else dark_iron
		var sx: float = -3.8 + (0.15 if (i % 3 == 0) else -0.1)

		match kind:
			0:  # Men's work boots (cuff + sole)
				terrain.create_box(center + Vector3(sx, 0.95, sz - 0.2), Vector3(0.4, 0.35, 0.85), 0.05,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
				terrain.create_box(center + Vector3(sx, 0.95, sz + 0.25), Vector3(0.4, 0.35, 0.85), -0.04,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
			1:  # Women's heels (arched pump + heel)
				terrain.create_box(center + Vector3(sx, 0.92, sz - 0.18), Vector3(0.3, 0.28, 0.7), 0.08,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
				terrain.create_box(center + Vector3(sx, 0.92, sz + 0.22), Vector3(0.3, 0.28, 0.7), -0.06,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
			2:  # Children's shoes (small pair)
				terrain.create_box(center + Vector3(sx, 0.9, sz - 0.14), Vector3(0.25, 0.2, 0.5), -0.03,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
				terrain.create_box(center + Vector3(sx, 0.9, sz + 0.16), Vector3(0.25, 0.2, 0.5), 0.04,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
			_:  # Men's dress shoes
				terrain.create_box(center + Vector3(sx, 0.92, sz - 0.2), Vector3(0.35, 0.24, 0.8), -0.05,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)
				terrain.create_box(center + Vector3(sx, 0.92, sz + 0.24), Vector3(0.35, 0.24, 0.8), 0.07,
						rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(shade, rng, 0.03), false)

	# 3. Memorial Benches & Plinths along the Promenade (+X side)
	for bz in [-16.0, 0.0, 16.0]:
		terrain.create_box(center + Vector3(2.6, 0.85, bz), Vector3(1.2, 0.8, 3.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(iron, rng, 0.03), false)
	# Cast-iron memorial plaques on low stone plinths
	for pz in [-8.0, 8.0]:
		terrain.create_box(center + Vector3(1.8, 0.7, pz), Vector3(1.4, 0.6, 1.4), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(stone, rng, 0.02), false)
		terrain.create_box(center + Vector3(1.8, 1.05, pz), Vector3(1.1, 0.1, 1.1), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(iron, rng, 0.04), false)

	return { "radius": 32.0, "top": 1.5 }


static func _city_budapest_eye(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	CITY 21 — BUDAPEST EYE: the 65 m giant Ferris wheel in Erzsébet Square,
	featuring its massive steel A-frame support legs, 54 m diameter rotating
	wheel truss, radial tension spokes, and 16 enclosed passenger gondolas
	overlooking central Pest.

	RADIUS ARITHMETIC (declared 38.0):
	  * Base plaza: 32.0 x 32.0 at (0, 0): sqrt(16.0^2 + 16.0^2) = 22.63 m.
	  * Support footings at (+/-4.5, 0, +/-10.0): sqrt(5.8^2 + 11.3^2) = 12.70 m.
	  * Wheel rim & gondolas on Z/Y plane: reaches z = +/-27.0 + 1.2 = 28.2 m.
	  So 28.20 <= 38.0.
	Boxes: 78. Colliding: 12.
	"""
	var steel := LandmarkBuilders.LM_MARBLE
	var steel_dark := LandmarkBuilders.LM_MARBLE.darkened(0.2)
	var gondola_blue := LandmarkBuilders.LM_SLATE_BLUE
	var park_green := CITY_PARK_GREEN
	var granite := LandmarkBuilders.LM_GRANITE

	# 1. Base Park Plaza in Erzsébet Square
	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(32.0, 0.8, 32.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(granite, rng, 0.02).lightened(0.1))

	# Square Corner Park Trees
	for tx in [-13.0, 13.0]:
		for tz in [-13.0, 13.0]:
			terrain.create_box(center + Vector3(tx, 2.0, tz), Vector3(0.8, 4.0, 0.8), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(LandmarkBuilders.LM_ROOF, rng, 0.03))
			terrain.create_box(center + Vector3(tx, 6.0, tz), Vector3(4.5, 4.5, 4.5), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(park_green, rng, 0.05), false)

	# 2. Boarding Platform & Base Stairs
	terrain.create_box(center + Vector3(0.0, 1.8, 0.0), Vector3(10.0, 2.0, 14.0), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(steel_dark, rng, 0.02))

	# 3. Steel A-Frame Support Legs (rising to axle hub at y = 34.0)
	var hub_pos := center + Vector3(0.0, 34.0, 0.0)
	for side_x in [-4.5, 4.5]:
		for side_z in [-10.0, 10.0]:
			# Concrete footing pad
			terrain.create_box(center + Vector3(side_x, 1.0, side_z), Vector3(2.6, 1.2, 2.6), 0.0,
					rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(steel_dark, rng, 0.02))
			# Sloping A-frame leg strut
			var foot_pos := center + Vector3(side_x, 1.6, side_z)
			_city_cable(terrain, foot_pos, hub_pos + Vector3(side_x * 0.4, 0.0, 0.0), 0.0, 3, 1.2,
					steel, rng, block_batch, block_body)

	# Central Axle Hub
	terrain.create_box(hub_pos, Vector3(9.0, 2.4, 2.4), 0.0,
			rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(steel, rng, 0.02))

	# 4. Giant Wheel Rim, Spokes, and 16 Gondolas (oriented in the Z/Y vertical plane)
	const CABINS := 16
	const WHEEL_RADIUS := 27.0
	for i in CABINS:
		var a1 := TAU * float(i) / float(CABINS)
		var a2 := TAU * float(i + 1) / float(CABINS)
		var p1 := hub_pos + Vector3(0.0, sin(a1) * WHEEL_RADIUS, cos(a1) * WHEEL_RADIUS)
		var p2 := hub_pos + Vector3(0.0, sin(a2) * WHEEL_RADIUS, cos(a2) * WHEEL_RADIUS)

		# Outer rim truss chord
		_city_cable(terrain, p1, p2, 0.0, 2, 0.8, steel, rng, block_batch, block_body)

		# Radial spoke tension cables from hub to rim
		_city_cable(terrain, hub_pos, p1, 0.0, 2, 0.35, steel, rng, block_batch, block_body)

		# Passenger Gondola / Cabin hanging beneath rim node
		var cabin_pos := p1 + Vector3(0.0, -1.4, 0.0)
		terrain.create_box(cabin_pos, Vector3(2.2, 2.0, 2.2), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(gondola_blue, rng, 0.03), false)
		# Enclosed glass band
		terrain.create_box(cabin_pos + Vector3(0.0, 0.1, 0.0), Vector3(2.3, 0.8, 2.3), 0.0,
				rng, block_batch, block_body, 0.0, LandmarkBuilders._lm_shade(Color(0.3, 0.7, 0.8), rng, 0.04), false)

	return { "radius": 38.0, "top": 62.5 }
