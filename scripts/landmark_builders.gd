class_name LandmarkBuilders
extends RefCounted
## THE GEO-LANDMARK REGISTRY AND ITS SHAPE BUILDERS — the "which famous places
## exist and what does each one look like" half of the feature, lifted whole out
## of endless_terrain.gd so that adding a place is an edit to ONE file that
## nothing else in the project has to know about.
##
## THE SPLIT, and why it falls exactly here. endless_terrain.gd keeps the
## POLICY — how rare a landmark is (LANDMARK_CHANCE), which hash stream decides
## it (_landmark_at), how far off the coin road it must sit, how its reward ring
## and its crocodile-exclusion footprint are sized (spawn_landmark_in_chunk).
## This file keeps the CONTENT — the palette, the registry, and the builder that
## turns a spot into stone. Policy is about the WORLD and reads a dozen sibling
## constants; content is about a PLACE and reads none of them. That is the whole
## seam, and it is why LANDMARK_RADIUS (a bound the placement test hands to
## _biome_spot_ok before any builder has run) stays over there while each entry's
## own `radius` lives in the registry here.
##
## THE REGISTRY IS THE EXTENSION POINT, and it is in this file precisely so the
## builder it names is a screen away rather than a file away: a new famous place
## is ONE builder function, ONE registry entry and TWO ui.csv rows, all of them
## here except the CSV. Nothing in endless_terrain.gd, in landmark_toast.gd or in
## landmark_selfcheck.gd has to learn about it.
##
## WHY STATIC FUNCTIONS THAT TAKE `terrain`. A builder's whole job is to append
## boxes to the chunk's ONE MultiMesh batch and ONE BlockCollision body, which it
## does through the terrain's own create_box / _spawn_artifact_accent /
## _get_camp_ember_material. Handing it the terrain as a plain first argument
## keeps that call unchanged and costs no object: there is no builder state to
## hold, so there is nothing to instantiate, and the dispatch stays the same one
## line it was — LandmarkBuilders.call(entry.builder, self, ...) — because
## Object.call() dispatches a GDScript static method exactly as it dispatched the
## method when it lived on the terrain node.
##
## ponytail: `terrain` is typed Node3D rather than a terrain class, because
## endless_terrain.gd declares no class_name and giving it one to satisfy a
## parameter hint would be a bigger change than the move it enables. The cost is
## that create_box is resolved dynamically; the self-check calls every builder in
## the registry, so a rename still fails loudly rather than in one chunk in fifty.

## --- Palette. Deliberately distinct from the warm RAMP_* block ramps, the
## artifacts' grey-green weathered stone and the camps' bone white, because the
## whole point of a landmark is that it does not read as scenery. Each place gets
## the colour a person would actually name it by.
const LM_STONE_GREY := Color(0.62, 0.61, 0.57)   # Stonehenge sarsen
const LM_BASALT := Color(0.34, 0.32, 0.30)       # Moai volcanic tuff
const LM_SANDSTONE := Color(0.80, 0.68, 0.44)    # Giza limestone
const LM_GRANITE := Color(0.48, 0.46, 0.47)      # plinths, pedestals, ahu
const LM_ORANGE := Color(0.75, 0.24, 0.10)       # Golden Gate International Orange
const LM_COPPER := Color(0.42, 0.71, 0.60)       # Liberty's oxidised copper
const LM_OCHRE := Color(0.72, 0.44, 0.24)        # Plaza Mayor walls
const LM_ROOF := Color(0.36, 0.20, 0.15)         # Plaza Mayor slate/tile trim
const LM_IRON := Color(0.45, 0.36, 0.28)         # Eiffel "brun tour Eiffel"
const LM_MARBLE := Color(0.93, 0.91, 0.87)       # Taj Mahal marble, Neuschwanstein limestone
## Wave 2. Only TWO new entries for ten new places, on purpose: a landmark is
## recognised by its silhouette, and every colour added is one more thing for a
## MultiMesh of grey boxes to fail to be distinct from. Where an existing entry is
## honestly the right colour it is reused — the Sphinx is Giza's own limestone,
## the Colosseum and the Great Wall are weathered sarsen grey, Cologne's soot-black
## Gothic stone is the Moai's basalt, and Neuschwanstein's white walls are the
## Taj's marble (its BLUE ROOFS are what tell the two apart at 30 m, which is
## exactly why the slate blue is one of the two that earned its place).
const LM_VERMILION := Color(0.78, 0.20, 0.14)    # Itsukushima torii lacquer
const LM_SLATE_BLUE := Color(0.30, 0.34, 0.45)   # Neuschwanstein's blue-grey spire roofs

## THE REGISTRY. Pure data, so it can be a `const` — and it is const precisely to
## make "add a place" a data edit rather than a code edit.
##
## `builder` is a METHOD-NAME STRING, invoked as call(entry.builder, ...). It is a
## String and not a Callable because a `const` Array cannot hold a Callable (a
## Callable binds an object at runtime, so it is not a constant expression); a
## String keeps the whole registry pure data and const-able, at the cost of the
## method name being checked at call time rather than parse time — which
## landmark_selfcheck.gd covers by calling every builder in the table.
##
## `name` and `fact` are the ENGLISH SOURCE STRINGS, not identifiers, because in
## this project THE TRANSLATION KEY IS THE ENGLISH SOURCE STRING (CLAUDE.md
## Localization RULE 1). The toast assigns them straight to a Label.text and gets
## translation AND live locale-switching for free, with no tr() call anywhere. Do
## not "fix" that by inventing HUD_LANDMARK_* keys — it would break the fallback
## that makes a place with no CSV row render as readable English.
##
## `radius` is that shape's OWN footprint radius (metres), which is what the
## reward ring and the obstacle footprint are measured from. It must be
## <= LANDMARK_RADIUS, and it must be a true bound on the stone the builder
## actually emits; landmark_selfcheck.gd measures both.
##
## ORDER IS LOAD-BEARING ONLY IN THAT IT IS THE KIND ROLL — _landmark_at draws
## randi_range(0, LANDMARKS.size() - 1) into this array, so appending is safe and
## reordering re-rolls every landmark in every existing world (harmless: worlds
## are per-run anyway).
const LANDMARKS: Array = [
	{
		"builder": "_landmark_stonehenge",
		"name": "Stonehenge",
		"fact": "A Neolithic stone circle on Salisbury Plain, England, raised around 2500 BC.",
		"radius": 7.6,
	},
	{
		"builder": "_landmark_moai",
		"name": "Moai of Easter Island",
		"fact": "Nearly 900 stone figures carved by the Rapa Nui on Easter Island, Chile, between 1250 and 1500.",
		"radius": 6.6,
	},
	{
		"builder": "_landmark_giza",
		"name": "Pyramids of Giza",
		"fact": "Three royal tombs near Cairo, Egypt, built around 2560 BC — the last surviving Wonder of the Ancient World.",
		"radius": 9.4,
	},
	{
		"builder": "_landmark_golden_gate",
		"name": "Golden Gate Bridge",
		"fact": "A 2.7 km suspension bridge over San Francisco Bay, USA, opened in 1937 and painted International Orange.",
		"radius": 9.4,
	},
	{
		"builder": "_landmark_liberty",
		"name": "Statue of Liberty",
		"fact": "A 93 m copper statue in New York Harbor, USA — a gift from France, dedicated in 1886.",
		"radius": 5.4,
	},
	{
		"builder": "_landmark_plaza_mayor",
		"name": "Plaza Mayor",
		"fact": "The arcaded central square of Madrid, Spain, completed in 1619 and ringed by 237 balconies.",
		"radius": 8.6,
	},
	{
		"builder": "_landmark_eiffel",
		"name": "Eiffel Tower",
		"fact": "A 330 m iron tower in Paris, France, built for the 1889 World's Fair and meant to stand only 20 years.",
		"radius": 6.2,
	},
	{
		"builder": "_landmark_taj",
		"name": "Taj Mahal",
		"fact": "A white marble mausoleum in Agra, India, built by Shah Jahan for his wife Mumtaz Mahal in 1653.",
		"radius": 8.6,
	},
	# --- WAVE 2 (appended, never inserted — see the ORDER note above). Ten more
	# places chosen for one property only: whether a person names them from the
	# SILHOUETTE alone. A ring of arches, a clock tower, a stack that leans, a lion
	# with a human head, a figure with its arms out, a two-beam gate, a wall with a
	# watchtower, a colonnade under a chariot, a castle of blue spires, twin
	# openwork spires. Three are German because the game's players are, and three
	# is the cap: the rest of that pool is a wave of its own.
	{
		"builder": "_landmark_colosseum",
		"name": "Colosseum",
		"fact": "A Roman amphitheatre completed in AD 80 that seated over 50,000 spectators in the heart of Rome, Italy.",
		"radius": 8.6,
	},
	{
		"builder": "_landmark_big_ben",
		"name": "Big Ben",
		"fact": "The 96 m clock tower of the Palace of Westminster in London, England — Big Ben is properly the bell inside it.",
		"radius": 4.4,
	},
	{
		"builder": "_landmark_pisa",
		"name": "Leaning Tower of Pisa",
		"fact": "A 12th-century bell tower in Pisa, Italy that began tilting during construction because of the soft ground beneath it.",
		"radius": 4.4,
	},
	{
		"builder": "_landmark_sphinx",
		"name": "Great Sphinx of Giza",
		"fact": "A 73 m limestone lion with a human head, carved from the bedrock at Giza, Egypt around 2500 BC.",
		"radius": 7.6,
	},
	{
		"builder": "_landmark_redeemer",
		"name": "Christ the Redeemer",
		"fact": "A 30 m soapstone statue that has stood on Corcovado mountain above Rio de Janeiro, Brazil since 1931.",
		"radius": 4.8,
	},
	{
		"builder": "_landmark_torii",
		"name": "Itsukushima Torii",
		"fact": "The vermilion gate of Itsukushima Shrine in Japan, which stands in the sea and appears to float at high tide.",
		"radius": 5.6,
	},
	{
		"builder": "_landmark_great_wall",
		"name": "Great Wall of China",
		"fact": "A chain of walls and watchtowers across northern China, over 20,000 km long and built over some 2,000 years.",
		"radius": 9.4,
	},
	{
		"builder": "_landmark_brandenburg",
		"name": "Brandenburg Gate",
		"fact": "A sandstone gate in Berlin, Germany, finished in 1791 and crowned by the Quadriga — a chariot drawn by four horses.",
		"radius": 8.4,
	},
	{
		"builder": "_landmark_neuschwanstein",
		"name": "Neuschwanstein Castle",
		"fact": "A hillside castle in Bavaria, Germany, begun in 1869 for King Ludwig II and never finished in his lifetime.",
		"radius": 8.0,
	},
	{
		"builder": "_landmark_cologne",
		"name": "Cologne Cathedral",
		"fact": "A Gothic cathedral in Cologne, Germany — begun in 1248, halted for 300 years and completed only in 1880.",
		"radius": 8.6,
	},
	# --- WAVE 3 (appended, never inserted — see the ORDER note above). Ten more,
	# picked on the same single property: whether a person names the place from the
	# SILHOUETTE alone. A crown of onion domes, a row of white sails, a stepped
	# pyramid with one grand stair, a facade cut into a cliff, four heads in a rock
	# face, five lotus towers in a quincunx, terraces under a sharp peak, three
	# tiers of arches, a row of windmills, a three-stage tower with a fire on top.
	#
	# NO GERMAN ENTRIES ON PURPOSE — the German pack is its own wave, and spending
	# the pool here would leave it the leftovers (the same reasoning that capped
	# wave 2 at three). The ten are ten different countries instead, none of which
	# the registry already had except Egypt and France, and in both of those cases
	# the new shape shares nothing with the old one (a tapering lighthouse against
	# pyramids and a lion; an arcade of arches against a lattice tower).
	#
	# ZERO NEW PALETTE ENTRIES, which is a decision and not luck. Wave 2 added two
	# for ten places and said why: a landmark is recognised by its silhouette, and
	# every colour added is one more thing for a MultiMesh of grey boxes to fail to
	# be distinct from. St Basil's is the only place here that is ABOUT its colours,
	# and the four it needs are already in the table — LM_VERMILION brick, LM_COPPER
	# oxidised green, LM_MARBLE white and LM_SANDSTONE standing in for gold leaf,
	# which at the 30 m these are judged from is exactly what a warm tan reads as.
	{
		"builder": "_landmark_st_basil",
		"name": "St Basil's Cathedral",
		"fact": "A cathedral of nine coloured onion domes on Red Square in Moscow, Russia, completed in 1561 for Ivan the Terrible.",
		"radius": 6.4,
	},
	{
		"builder": "_landmark_sydney_opera",
		"name": "Sydney Opera House",
		"fact": "A performing-arts centre on Sydney Harbour, Australia, opened in 1973 and roofed with over a million tiles.",
		"radius": 8.2,
	},
	{
		"builder": "_landmark_chichen_itza",
		"name": "Chichén Itzá",
		"fact": "El Castillo, a Maya step pyramid in Chichén Itzá, Mexico, whose four stairways total 365 steps — one for every day.",
		"radius": 8.4,
	},
	{
		"builder": "_landmark_petra",
		"name": "Petra",
		"fact": "Al-Khazneh, a temple facade carved into a rose-red sandstone cliff at Petra, Jordan, around the 1st century AD.",
		"radius": 8.0,
	},
	{
		"builder": "_landmark_rushmore",
		"name": "Mount Rushmore",
		"fact": "Four 18 m presidential heads carved into a granite cliff in South Dakota, USA, between 1927 and 1941.",
		"radius": 8.6,
	},
	{
		"builder": "_landmark_angkor_wat",
		"name": "Angkor Wat",
		"fact": "The largest religious monument on Earth, raised in Cambodia around 1150 and still flown on the national flag.",
		"radius": 9.0,
	},
	{
		"builder": "_landmark_machu_picchu",
		"name": "Machu Picchu",
		"fact": "An Inca city on a 2,430 m ridge in Peru, built around 1450 and unknown to the outside world until 1911.",
		"radius": 9.0,
	},
	{
		"builder": "_landmark_pont_du_gard",
		"name": "Pont du Gard",
		"fact": "A three-tier Roman aqueduct bridge over the Gardon in France, built around AD 50 to carry water 50 km to Nîmes.",
		"radius": 8.8,
	},
	{
		"builder": "_landmark_kinderdijk",
		"name": "Kinderdijk Windmills",
		"fact": "Nineteen windmills built around 1740 to drain the polders of Kinderdijk, the Netherlands — a UNESCO World Heritage site.",
		"radius": 8.2,
	},
	{
		"builder": "_landmark_pharos",
		"name": "Lighthouse of Alexandria",
		"fact": "A 100 m lighthouse on the island of Pharos at Alexandria, Egypt — a Wonder of the Ancient World, toppled by earthquakes.",
		"radius": 6.6,
	},
]

# ----------------------------------------------------------------------------
# THE BUILDERS (one per registry entry, in registry order)
# ----------------------------------------------------------------------------
##
## Every builder has the identical signature
##   _landmark_x(center, rng, parent_chunk, block_batch, block_body) -> Dictionary
## and returns { "radius": float, "top": float } — no `gem_offset`, because a
## landmark deliberately pays NO GEM (see the REWARD DECISION in the constant
## banner). `center` is CHUNK-LOCAL, exactly as the artifact builders take it.
##
## Shared rules, all four of them load-bearing:
##  1. EVERY solid box goes through create_box with a color_override, so it lands
##     in the chunk's ONE MultiMesh and ONE BlockCollision body. A landmark is
##     therefore free at the draw-call level however many boxes it is made of.
##  2. `collide = false` for pure trim that sits INSIDE another box's collision
##     volume (dark recesses, thin cornices, brows, cable strands overhead). The
##     chest's brass band and the camp's fire stones are the precedent.
##  3. The returned `radius` must BOUND every box actually emitted, measured as
##     horizontal centre offset + the rotated box's horizontal half-diagonal —
##     which is exactly what landmark_selfcheck.gd measures over 25 seeds per
##     builder. Each builder's comment carries its own worst-case arithmetic, so
##     a retune can be checked by reading rather than by running.
##  4. AT MOST ONE emissive accent, and only where a real light belongs (a
##     capstone, a torch, a beacon). An accent is a genuine extra draw call, and
##     it reuses terrain._get_camp_ember_material() — the warm one. DO NOT add a third
##     glow material; two temperatures is the whole vocabulary.
##
## The RNG is the landmark's PRIVATE stream (seeded from _landmark_at's `seed`),
## so a builder may draw as freely as its shape needs — nothing else reads it.

static func _lm_shade(base: Color, rng: RandomNumberGenerator, amount: float = 0.06) -> Color:
	"""
	One stone's colour: the landmark's base palette entry nudged by up to `amount`
	in each channel. Mortared ruins and quarried blocks are never one flat colour,
	and a per-box jitter is what stops a MultiMesh of identical greys reading as a
	single extruded blob. Deliberately SMALL — a landmark has to stay recognizable,
	which means its silhouette does the work and the colour stays quiet.
	"""
	var d := rng.randf_range(-amount, amount)
	return Color(clampf(base.r + d, 0.0, 1.0), clampf(base.g + d, 0.0, 1.0), clampf(base.b + d, 0.0, 1.0))

static func _landmark_stonehenge(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 0 — STONEHENGE: an outer ring of 5 trilithons (two uprights carrying a
	lintel laid across their tops) around an inner horseshoe of 4 shorter, drunkenly
	leaning standing stones. Salisbury Plain in cubes.

	RADIUS ARITHMETIC (declared 7.6). The widest thing is a lintel: its centre sits
	on the RING_R (5.6) ring and its horizontal half-diagonal is
	0.5*sqrt(3.4^2 + 1.0^2) = 1.77, so 5.6 + 1.77 = 7.37 <= 7.6. The uprights sit
	further out along the tangent (sqrt(5.6^2 + 1.2^2) = 5.73) but are much thinner
	(half-diagonal 0.71), so 6.44. RING_R is 5.6 rather than the 6.0 a real plan
	would suggest precisely because of that lintel term.
	NO ACCENT: Stonehenge is a sundial, not a lamp.
	"""
	const RING_R := 5.6
	const TRILITHONS := 5
	const UPRIGHT := Vector3(1.0, 4.2, 1.0)
	const LINTEL := Vector3(3.4, 0.8, 1.0)
	# One shared orientation for the whole monument, so the ring reads as built
	# rather than scattered.
	var base_a := rng.randf_range(0.0, TAU)

	for i in TRILITHONS:
		var a := base_a + TAU * float(i) / float(TRILITHONS)
		# yaw = PI/2 - a points the stone's local Z (its thin depth axis) along the
		# radius, i.e. the trilithon FACES the centre and its long X axis runs along
		# the tangent — the same face-the-centre trick the artifact stone circle uses.
		var yaw := PI / 2.0 - a
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var ring_pos := center + radial * RING_R
		# The two uprights, offset along the tangent so the lintel bridges them.
		for side in [-1.0, 1.0]:
			terrain.create_box(ring_pos + tangent * (side * 1.2) + Vector3(0.0, UPRIGHT.y / 2.0, 0.0),
					UPRIGHT, yaw + rng.randf_range(-0.05, 0.05), rng, block_batch, block_body,
					0.0, _lm_shade(LM_STONE_GREY, rng))
		# The lintel laid flat across both tops — the detail that makes a trilithon
		# read as Stonehenge and not as a stone circle.
		terrain.create_box(ring_pos + Vector3(0.0, UPRIGHT.y + LINTEL.y / 2.0, 0.0),
				LINTEL, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_STONE_GREY, rng))

	# Inner horseshoe: 4 shorter bluestones over a 3/4 arc (a horseshoe, not a
	# second ring), each leaning a little — a thousand years of frost heave.
	const INNER_R := 2.8
	for i in 4:
		var a := base_a + 0.35 + (TAU * 0.75) * float(i) / 3.0
		var dims := Vector3(1.0, rng.randf_range(2.2, 2.9), 0.7)
		var lean := rng.randf_range(-0.15, 0.15)
		terrain.create_box(center + Vector3(cos(a) * INNER_R, dims.y / 2.0 - 0.15, sin(a) * INNER_R),
				dims, PI / 2.0 - a, rng, block_batch, block_body, lean, _lm_shade(LM_STONE_GREY, rng))

	return { "radius": 7.6, "top": UPRIGHT.y + LINTEL.y }

static func _landmark_moai(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 1 — MOAI OF EASTER ISLAND: five heavy figures standing shoulder to
	shoulder on a low ahu platform, ALL FACING THE SAME WAY (inland, as the real
	ones do). The row plus the shared gaze is the whole recognition cue.

	RADIUS ARITHMETIC (declared 6.6). The ahu slab is the widest box:
	0.5*sqrt(11.0^2 + 3.0^2) = 5.70. The outermost statue body sits at x = 4.4 with
	half-diagonal 0.79 => 5.19. So 5.70 <= 6.6.
	NO ACCENT.
	"""
	const AHU := Vector3(11.0, 0.7, 3.0)
	const STATUES := 5
	const SPACING := 2.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_BASALT, rng, 0.03)  # one quarry, one colour family
	terrain.create_box(center + Vector3(0.0, AHU.y / 2.0, 0.0), AHU, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))

	var tallest := AHU.y
	for i in STATUES:
		var offset := (float(i) - float(STATUES - 1) / 2.0) * SPACING
		var base := center + rot * Vector3(offset, 0.0, 0.0)
		# Each figure is carved separately, so each leans a hair differently — but
		# the wobble stays tiny, because "all facing one way" is the recognition cue.
		var wobble := rng.randf_range(-0.09, 0.09)
		var body := Vector3(1.3, rng.randf_range(2.7, 3.2), 0.9)
		terrain.create_box(base + Vector3(0.0, AHU.y + body.y / 2.0, 0.0), body, yaw + wobble, rng, block_batch, block_body, 0.0, stone)
		var head := Vector3(1.15, 1.5, 1.0)
		var head_y := AHU.y + body.y + head.y / 2.0
		terrain.create_box(base + Vector3(0.0, head_y, 0.0), head, yaw + wobble, rng, block_batch, block_body, 0.0, stone)
		# The heavy brow ridge, proud of the face — visual trim only (it sits on the
		# head's own collision volume), so collide = false.
		terrain.create_box(base + Vector3(0.0, head_y + 0.25, 0.0) + Basis(Vector3.UP, yaw + wobble) * Vector3(0.0, 0.0, head.z / 2.0 + 0.06),
				Vector3(1.2, 0.35, 0.18), yaw + wobble, rng, block_batch, block_body, 0.0,
				_lm_shade(LM_BASALT, rng, 0.02).darkened(0.25), false)
		tallest = maxf(tallest, AHU.y + body.y + head.y)

	return { "radius": 6.6, "top": tallest }

static func _landmark_giza(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 2 — PYRAMIDS OF GIZA: three stepped pyramids of descending size on the
	shallow diagonal the real ones stand on, plus ONE emissive capstone on the
	Great Pyramid (the pyramidion that is missing in Cairo and present here).

	RADIUS ARITHMETIC (declared 9.4). Worst case is the SMALLEST pyramid, because
	it is the one pushed furthest out: centre offset sqrt(5.0^2 + 3.0^2) = 5.83 plus
	its base half-diagonal 0.5*sqrt(2*4.0^2) = 2.83 => 8.66. The Great Pyramid is
	2.5 out with a 4.95 half-diagonal => 7.45. So 8.66 <= 9.4.
	Sizes and offsets are FIXED rather than rolled: three pyramids in descending
	size on a diagonal IS the recognition cue, and a roll that shuffled them would
	sometimes produce three equal lumps.
	"""
	# base width, layer count, offset from the group centre — largest first.
	var plan := [
		{ "base": 7.0, "layers": 9, "off": Vector2(-2.0, -1.5) },
		{ "base": 5.5, "layers": 7, "off": Vector2(2.2, 1.0) },
		{ "base": 4.0, "layers": 5, "off": Vector2(5.0, 3.0) },
	]
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var great_top := 0.0
	for p in plan:
		var base_w: float = p.base
		var layers: int = p.layers
		var spot: Vector3 = center + rot * Vector3(p.off.x, 0.0, p.off.y)
		# Same tapering-stack recipe as spawn_pyramid, so a stepped pyramid is
		# climbable the same way theirs is.
		var layer_h: float = base_w / float(layers) * 0.62
		var shrink: float = base_w / float(layers + 1)
		var y := 0.0
		for i in layers:
			var w: float = base_w - float(i) * shrink
			terrain.create_box(spot + Vector3(0.0, y + layer_h / 2.0, 0.0), Vector3(w, layer_h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng))
			y += layer_h
		if great_top == 0.0:
			great_top = y
			# THE one accent: a gilded capstone on the Great Pyramid.
			terrain._spawn_artifact_accent(parent_chunk, spot + Vector3(0.0, y + 0.35, 0.0),
					Vector3(0.9, 0.7, 0.9), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 9.4, "top": great_top + 0.7 }

static func _landmark_golden_gate(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 3 — GOLDEN GATE BRIDGE: two International Orange towers, a deck slab
	spanning and overhanging them, and the main cable as a chain of small boxes
	sagging from tower top to tower top in a shallow catenary.

	THE DECK IS SOLID ON PURPOSE. It goes through create_box like every other solid,
	so downstream it IS ordinary block stone: it has a real CollisionShape3D in the
	chunk's one BlockCollision body and the player stands on it rather than falling
	through, which is what stops the span reading as a painted backdrop.

	ponytail: it is solid but NOT REACHABLE from flat ground — the deck top sits at
	DECK_Y + DECK.y/2 = 5.3 m against the player's 3.6125 m jump apex, and the
	towers are smooth 11 m boxes with no ledge. So you walk under this bridge, not
	over it. Upgrade path if crossing it is ever wanted: drop DECK_Y to ~2.9 (top
	3.2), or add a step block at each abutment; both change the silhouette's
	proportions, which is why neither was done for a shape whose whole job is to be
	recognisable at 30 m. Note also that a road coin whose column crosses this
	landmark is SKIPPED, not perched — spawn_landmark_in_chunk appends the footprint
	`climbable: false` for every landmark (they are 5-18 m tall), so _settle_coin_y
	drops it rather than stranding it on the circle's top.

	RADIUS ARITHMETIC (declared 9.4). The deck is the widest box:
	0.5*sqrt(17.0^2 + 3.0^2) = 8.63. A tower leg sits at sqrt(5.5^2 + 1.2^2) = 5.63
	with half-diagonal 0.64 => 6.27. So 8.63 <= 9.4.
	NO ACCENT: the towers already carry the loudest colour in the whole palette.
	"""
	const TOWER_X := 5.5          # half the tower spacing (towers 11 m apart)
	const LEG := Vector3(0.9, 11.0, 0.9)
	const LEG_Z := 1.2            # half the spacing between a tower's two legs
	const DECK := Vector3(17.0, 0.6, 3.0)
	const DECK_Y := 5.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var orange := _lm_shade(LM_ORANGE, rng, 0.04)

	for side in [-1.0, 1.0]:
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(side * TOWER_X, LEG.y / 2.0, z_side * LEG_Z),
					LEG, yaw, rng, block_batch, block_body, 0.0, orange)
		# Two crossbeams tying each tower's legs together — the ladder look that
		# says "suspension tower" rather than "two posts".
		for beam_y in [DECK_Y + 1.4, LEG.y - 1.0]:
			terrain.create_box(center + rot * Vector3(side * TOWER_X, beam_y, 0.0),
					Vector3(0.7, 0.6, LEG_Z * 2.0 + LEG.z), yaw, rng, block_batch, block_body, 0.0, orange)

	# The deck, overhanging both towers so the span reads as part of a longer road.
	terrain.create_box(center + rot * Vector3(0.0, DECK_Y, 0.0), DECK, yaw, rng, block_batch, block_body, 0.0,
			_lm_shade(LM_ORANGE, rng, 0.04).darkened(0.2))

	# The main cable: a chain of short boxes on a parabola from tower top, dipping
	# to just above the deck at mid-span, back up to the other tower top. Two of
	# them, one per side, hung off the same LEG_Z the legs use.
	# collide = false — a 30 cm strand of cable overhead is decoration, and giving
	# it a collision shape would let the player stand on thin air at mid-span.
	const CABLE_SEGMENTS := 11
	var top_y := LEG.y
	var sag_y := DECK_Y + 0.9
	for z_side in [-1.0, 1.0]:
		for i in CABLE_SEGMENTS:
			var t := float(i) / float(CABLE_SEGMENTS - 1)   # 0..1 across the span
			var u := t * 2.0 - 1.0                          # -1..1, 0 at mid-span
			var x := u * TOWER_X
			var y: float = sag_y + (top_y - sag_y) * u * u   # parabola == shallow catenary
			terrain.create_box(center + rot * Vector3(x, y, z_side * LEG_Z), Vector3(TOWER_X * 2.0 / float(CABLE_SEGMENTS - 1) + 0.15, 0.3, 0.3),
					yaw, rng, block_batch, block_body, 0.0, orange, false)

	return { "radius": 9.4, "top": LEG.y }

static func _landmark_liberty(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 4 — STATUE OF LIBERTY: a stepped pedestal, a robe tapering upward, a head
	wearing a seven-point crown, and a raised right arm carrying ONE emissive torch.
	The crown and the raised torch are the whole silhouette; everything else is
	scaffolding for them.

	RADIUS ARITHMETIC (declared 5.4). The widest box is the bottom pedestal slab,
	0.5*sqrt(2*4.6^2) = 3.25, at the centre. The arm reaches out ~1.9 with a small
	half-diagonal => under 3.0. So 3.25 <= 5.4, with room to spare for the crown
	spikes' tilt.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var granite := _lm_shade(LM_GRANITE, rng)
	var copper := _lm_shade(LM_COPPER, rng, 0.03)

	# Pedestal: three shrinking slabs (Fort Wood's star fort, flattened to steps).
	var y := 0.0
	for i in 3:
		var w := 4.6 - float(i) * 0.7
		var h := 1.2
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, granite)
		y += h

	# Robe: four boxes narrowing as they rise — a cone, in the house's box vocabulary.
	for i in 4:
		var w: float = 2.6 - float(i) * 0.33
		var h := 1.6
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w * 0.85), yaw, rng, block_batch, block_body, 0.0, copper)
		y += h

	# Head.
	var head_h := 1.1
	terrain.create_box(center + Vector3(0.0, y + head_h / 2.0, 0.0), Vector3(1.0, head_h, 1.0), yaw, rng, block_batch, block_body, 0.0, copper)
	var crown_y := y + head_h

	# The seven-point crown: spikes radiating outward and up. Trim only (they hang
	# off the head's own volume), so collide = false.
	#
	# SIGN GOTCHA, the same one the Eiffel legs record and the treasure chest's lid
	# records before that: create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt),
	# Basis(RIGHT, t) tips local +Y toward local +Z, and the yaw PI/2 - a maps local
	# +Z onto (cos a, sin a) — radially OUTWARD. So "radiating outward" is a POSITIVE
	# tilt. Measured with it negative, the spikes ran from r = 1.07 at their bases to
	# r = 0.63 at their tips: a cage closing over the head rather than a crown.
	for i in 7:
		var a := yaw + PI * (float(i) / 6.0 - 0.5)   # a half-circle fan, facing forward
		terrain.create_box(center + Vector3(cos(a) * 0.85, crown_y + 0.15, sin(a) * 0.85), Vector3(0.22, 1.0, 0.22),
				PI / 2.0 - a, rng, block_batch, block_body, 0.45, copper, false)

	# The raised arm: two vertical boxes stepping outward and up (upper arm, then
	# forearm), with the torch on top. Deliberately NOT tilted — a tilted arm box
	# would need its own sign reasoning for a limb that reads fine as a step at the
	# 30 m the silhouette is judged from.
	var shoulder := center + rot * Vector3(1.0, y - 0.6, 0.0)
	terrain.create_box(shoulder + rot * Vector3(0.35, 0.8, 0.0), Vector3(0.5, 2.0, 0.5), yaw, rng, block_batch, block_body, 0.0, copper)
	var hand := shoulder + rot * Vector3(0.7, 2.6, 0.0)
	terrain.create_box(hand, Vector3(0.6, 1.6, 0.6), yaw, rng, block_batch, block_body, 0.0, copper)
	# THE one accent: the torch flame, warm — the only thing on this statue that
	# should be visible from the coin road at night.
	terrain._spawn_artifact_accent(parent_chunk, hand + Vector3(0.0, 1.2, 0.0), Vector3(0.55, 0.8, 0.55), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 5.4, "top": maxf(crown_y + 0.9, hand.y + 1.6) }

static func _landmark_plaza_mayor(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 5 — PLAZA MAYOR: a square of three-storey ochre buildings enclosing an
	open courtyard, with an arcade of pillars along the inner faces, an arched
	entrance gap in one side, and a statue plinth in the middle. The one landmark
	you go INSIDE.

	WHY EACH SIDE IS THREE SEGMENTS AND NOT ONE LONG WALL. Purely the radius bound:
	a single 11.4 m wall has a horizontal half-diagonal of 5.79, which added to its
	4.7 offset is 10.5 — over the declared 8.6, even though its actual far corner is
	only at 8.4. The bound the self-check measures is offset + half-diagonal, so
	splitting each side into three bays (half-diagonal 2.14) brings the worst case
	to sqrt(3.75^2 + 4.7^2) + 2.14 = 6.01 + 2.14 = 8.15 <= 8.6. It also happens to
	read better: three bays per side is what an arcaded square looks like.
	NO ACCENT.
	"""
	const SIDE := 11.4        # outer side of the square
	const WALL_T := 2.0       # building depth
	const BAY := 3.8          # one segment's length
	const STOREY := 2.2
	const STOREYS := 3
	var yaw := rng.randf_range(0.0, TAU)
	var wall_line := SIDE / 2.0 - WALL_T / 2.0
	var ochre := _lm_shade(LM_OCHRE, rng, 0.05)

	# Four sides; side 0 is the entrance side and skips its middle bay.
	for side_i in 4:
		var side_yaw := yaw + PI / 2.0 * float(side_i)
		var side_rot := Basis(Vector3.UP, side_yaw)
		for bay in 3:
			if side_i == 0 and bay == 1:
				continue  # the archway: left open, spanned by a lintel below
			var along := (float(bay) - 1.0) * BAY
			var foot := center + side_rot * Vector3(along, 0.0, wall_line)
			for s in STOREYS:
				terrain.create_box(foot + Vector3(0.0, STOREY * float(s) + STOREY / 2.0, 0.0),
						Vector3(BAY, STOREY, WALL_T), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(ochre, rng, 0.03))
			# Slate cornice capping the bay — trim sitting on the wall's own volume.
			terrain.create_box(foot + Vector3(0.0, STOREY * float(STOREYS) + 0.18, 0.0),
					Vector3(BAY + 0.2, 0.36, WALL_T + 0.3), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
		# The arcade: three squat pillars along this side's inner face, standing
		# proud of the wall — the colonnade you walk behind.
		for p in 3:
			var px := (float(p) - 1.0) * BAY
			terrain.create_box(center + side_rot * Vector3(px, STOREY / 2.0, wall_line - WALL_T / 2.0 - 0.35),
					Vector3(0.5, STOREY, 0.5), side_yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.05))

	# The entrance arch: two piers either side of the missing bay plus a lintel over
	# it, so the gap reads as a doorway rather than as a demolition.
	var arch_rot := Basis(Vector3.UP, yaw)
	for s in [-1.0, 1.0]:
		terrain.create_box(center + arch_rot * Vector3(s * (BAY / 2.0 - 0.35), STOREY, wall_line),
				Vector3(0.7, STOREY * 2.0, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)
	terrain.create_box(center + arch_rot * Vector3(0.0, STOREY * 2.0 + STOREY / 2.0, wall_line),
			Vector3(BAY, STOREY, WALL_T), yaw, rng, block_batch, block_body, 0.0, ochre)

	# The courtyard's centrepiece: Felipe III on his plinth, abstracted to two boxes.
	terrain.create_box(center + Vector3(0.0, 0.4, 0.0), Vector3(1.4, 0.8, 1.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	terrain.create_box(center + Vector3(0.0, 0.8 + 0.85, 0.0), Vector3(0.55, 1.7, 0.55), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.03))

	# ponytail: the roof is a cornice band, not a pitched roof — a real one needs
	# tilted slabs whose collision would then be a ramp the player slides off. Add
	# tilted eaves if the square ever reads too flat from a distance.
	return { "radius": 8.6, "top": STOREY * float(STOREYS) + 0.36 }

static func _landmark_eiffel(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 6 — EIFFEL TOWER: four legs leaning inward in two segments each (the
	curve, in two straight pieces), a broad first platform, a smaller second one, a
	tapering shaft and an antenna, with ONE emissive beacon at the top.

	WHY THE LEGS ARE TWO SEGMENTS. Partly the curve — a single straight leg reads
	as a pylon — and partly the radius bound: a tilted box contributes
	sin(tilt) * height/2 of horizontal reach, so one 7 m leg tilted 0.3 rad reaches
	further than two 3.5 m ones that each restart closer to the axis.

	RADIUS ARITHMETIC (declared 6.2). Worst case is the FIRST PLATFORM,
	0.5*sqrt(2*6.0^2) = 4.24 at the centre. A lower leg segment sits at
	sqrt(2*2.2^2) = 3.11 with a tilted horizontal half-reach under 1.5 => 4.6.
	So 4.6 <= 6.2.
	"""
	const LEG_TILT := 0.30
	const SEG := Vector3(0.85, 3.6, 0.85)
	var yaw := rng.randf_range(0.0, TAU)
	var iron := _lm_shade(LM_IRON, rng, 0.04)

	# Four legs at the corners of a square, each leaning toward the axis. The tilt
	# is applied about the leg's own local X after a yaw that points that X along
	# the tangent, so every leg leans INWARD rather than all four leaning north.
	#
	# THE TILT IS NEGATED, AND THAT SIGN IS THE WHOLE SHAPE. create_box composes
	# Basis(UP, yaw) * Basis(RIGHT, tilt), and Basis(RIGHT, t) tips the box's local
	# +Y toward its local +Z (the same gotcha the treasure chest's lid records, one
	# axis over). The yaw here is PI/2 - a, which maps local +Z onto (cos a, sin a)
	# — i.e. RADIALLY OUTWARD from the tower axis. So a POSITIVE tilt splays the
	# legs out. Measured with the sign wrong: the lower segment ran from r = 1.67 at
	# the ground to r = 2.73 at its top, the upper segment restarted at r = 0.90 and
	# rose to 1.50, so all four legs flared outward AND had a 1.83 m horizontal
	# discontinuity where the two segments are supposed to meet. Negated, the lower
	# runs 2.73 -> 1.67 and the upper 1.50 -> 0.90: converging, and the joint closes
	# to a 0.17 m step. The radius bound is unaffected either way (the magnitude of
	# the widest leg point is the same, it just moves from the top to the bottom).
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var lower := center + Vector3(cos(a) * 2.2, SEG.y / 2.0, sin(a) * 2.2)
		terrain.create_box(lower, SEG, PI / 2.0 - a, rng, block_batch, block_body, -LEG_TILT, iron)
		var upper := center + Vector3(cos(a) * 1.2, SEG.y * 1.5 - 0.1, sin(a) * 1.2)
		terrain.create_box(upper, Vector3(SEG.x * 0.85, SEG.y, SEG.z * 0.85), PI / 2.0 - a, rng, block_batch, block_body, -LEG_TILT * 0.55, iron)

	# First platform — the wide one you can see people standing on from the Champ
	# de Mars, and here a genuinely reachable roof if you climb the legs.
	var p1_y := SEG.y * 2.0 - 0.2
	terrain.create_box(center + Vector3(0.0, p1_y + 0.25, 0.0), Vector3(6.0, 0.5, 6.0), yaw, rng, block_batch, block_body, 0.0, iron)
	# Second platform.
	var p2_y := p1_y + 4.0
	terrain.create_box(center + Vector3(0.0, p2_y + 0.2, 0.0), Vector3(3.6, 0.4, 3.6), yaw, rng, block_batch, block_body, 0.0, iron)

	# The shaft between and above the platforms: three boxes narrowing upward.
	var y := p1_y + 0.5
	for i in 3:
		var w: float = 2.4 - float(i) * 0.55
		var h := 3.5
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, iron)
		y += h

	# Antenna, and THE one accent: the aircraft beacon at the very top.
	terrain.create_box(center + Vector3(0.0, y + 1.25, 0.0), Vector3(0.3, 2.5, 0.3), yaw, rng, block_batch, block_body, 0.0, iron)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 2.7, 0.0), Vector3(0.4, 0.4, 0.4), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.2, "top": y + 2.5 }

static func _landmark_taj(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 7 — TAJ MAHAL: a white marble plinth carrying a cubic mausoleum under a
	stacked onion dome, four corner minarets, and a dark iwan arch recessed into
	the front face. Symmetry is the recognition cue, so nothing here is jittered
	except the colour.

	RADIUS ARITHMETIC (declared 8.6). The plinth is the widest box,
	0.5*sqrt(2*11.6^2) = 8.20. A minaret stands at sqrt(2*4.6^2) = 6.51 with a
	half-diagonal of 0.57 => 7.08. So 8.20 <= 8.6.
	NO ACCENT: the marble is the brightest albedo in the palette already.
	"""
	const PLINTH := Vector3(11.6, 0.9, 11.6)
	const HALL := Vector3(6.0, 5.0, 6.0)
	const MINARET_OFF := 4.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var marble := _lm_shade(LM_MARBLE, rng, 0.02)

	terrain.create_box(center + Vector3(0.0, PLINTH.y / 2.0, 0.0), PLINTH, yaw, rng, block_batch, block_body, 0.0, marble)
	var hall_y := PLINTH.y
	terrain.create_box(center + Vector3(0.0, hall_y + HALL.y / 2.0, 0.0), HALL, yaw, rng, block_batch, block_body, 0.0, marble)

	# The iwan: a tall dark recess in the front (+Z) face. Trim only — it sits on
	# the hall's own collision volume, so collide = false keeps the wall solid.
	terrain.create_box(center + rot * Vector3(0.0, hall_y + 1.9, HALL.z / 2.0 - 0.05), Vector3(2.4, 3.4, 0.5),
			yaw, rng, block_batch, block_body, 0.0, LM_MARBLE.darkened(0.72), false)

	# The dome: three shrinking boxes plus a finial. Crude, and unmistakable.
	var y := hall_y + HALL.y
	for dims in [Vector3(3.6, 1.6, 3.6), Vector3(2.6, 1.2, 2.6), Vector3(1.6, 0.9, 1.6)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body, 0.0, marble)
		y += dims.y
	terrain.create_box(center + Vector3(0.0, y + 0.6, 0.0), Vector3(0.35, 1.2, 0.35), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))

	# Four minarets, one per plinth corner, each with a small cap.
	for corner in 4:
		var a := yaw + PI / 4.0 + PI / 2.0 * float(corner)
		var spot := center + Vector3(cos(a) * MINARET_OFF * sqrt(2.0), 0.0, sin(a) * MINARET_OFF * sqrt(2.0))
		terrain.create_box(spot + Vector3(0.0, PLINTH.y + 4.0, 0.0), Vector3(0.8, 8.0, 0.8), yaw, rng, block_batch, block_body, 0.0, marble)
		terrain.create_box(spot + Vector3(0.0, PLINTH.y + 8.35, 0.0), Vector3(1.1, 0.7, 1.1), yaw, rng, block_batch, block_body, 0.0, marble)

	return { "radius": 8.6, "top": y + 1.2 }

# ----------------------------------------------------------------------------
# WAVE 2 — TEN MORE PLACES
# ----------------------------------------------------------------------------
##
## Same four rules as the eight above (batched stone through create_box, collide =
## false for trim inside another box's volume, a declared radius that BOUNDS every
## emitted corner, at most ONE emissive accent and only where a real lamp belongs).
## Two of the ten spend their accent — Big Ben's Ayrton Light, which is a real lamp
## lit while Parliament sits, and the Great Wall's beacon tower, whose entire
## purpose was to be set on fire. The other eight spend none.
##
## RADIUS ARITHMETIC, once, because all ten comments use it: the self-check
## transforms the unit cube's corners by each box's real basis, which is
## Basis(UP, yaw) * Basis(RIGHT, tilt) scaled by the dimensions. Yaw only rotates
## within the XZ plane, so the horizontal half-extent of one box is
##     sqrt( (w/2)^2 + (h/2 * |sin tilt| + d/2 * |cos tilt|)^2 )
## which at tilt = 0 is the familiar half-diagonal 0.5 * sqrt(w^2 + d^2). Each
## comment gives the worst box as "centre offset + that", which is an upper bound
## on what the check measures (it assumes the offset and the corner point the same
## way). Over-declaring is SAFE — see the note at the end of the self-check's
## check 1 — and two entries here deliberately do it, for a reason that is about
## the TOAST rather than the stone: the card's trigger distance is the declared
## radius + APPROACH_PAD, so a tall thin tower declaring its true 3.1 m footprint
## would only announce itself once the player was already standing in it.

static func _landmark_colosseum(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 8 — COLOSSEUM: an elliptical ring of arcade piers carrying a lintel band,
	a second tier standing on part of it, and a stub of a third — the collapsed
	half is the recognition cue every bit as much as the arches are, because a
	complete ring reads as a fort.

	RADIUS ARITHMETIC (declared 8.6). The widest box is a first-tier LINTEL, which
	is the one that bridges two piers and is therefore much longer than a pier:
	half-extent 0.5*sqrt(2.7^2 + 1.3^2) = 1.50 at the ellipse's semi-major 6.9, so
	6.9 + 1.50 = 8.40 <= 8.6. A pier is 6.9 + 0.99 = 7.89, and the arena floor is
	one 9.0 x 7.2 slab at the centre, i.e. 0.5*sqrt(9.0^2 + 7.2^2) = 5.76.
	RING_A is 6.9 rather than the 7.6 the footprint would allow precisely because
	of that lintel term — the Stonehenge lesson, one landmark on.
	NO ACCENT.
	"""
	const PIERS := 16
	const RING_A := 6.9          # ellipse semi-major
	const RING_B := 5.5          # semi-minor
	const PIER := Vector3(1.5, 3.0, 1.3)
	const LINTEL := Vector3(2.7, 0.7, 1.3)
	const PIER2 := Vector3(1.3, 2.6, 1.1)
	const LINTEL2 := Vector3(2.5, 0.6, 1.1)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	# The arena floor, a shade darker so the ring reads as enclosing something.
	terrain.create_box(center + Vector3(0.0, 0.17, 0.0), Vector3(9.0, 0.35, 7.2), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng).darkened(0.25))

	# How much of the upper ring survives — 9 to 12 of 16 bays, which is what makes
	# one side a broken cliff and the other a wall.
	var standing := rng.randi_range(9, 12)
	var tier1_top := PIER.y + LINTEL.y
	var tier2_top := tier1_top + PIER2.y + LINTEL2.y

	for i in PIERS:
		var a := TAU * float(i) / float(PIERS)
		# Positions ride the ellipse; orientation uses the circle's tangent rule
		# (yaw + PI/2 - a, the same face-the-centre trick Stonehenge uses). A true
		# elliptical normal would differ by a few degrees, which is invisible in
		# boxes and would cost a second trig pair per pier.
		var spot: Vector3 = center + rot * Vector3(cos(a) * RING_A, 0.0, sin(a) * RING_B)
		var face := yaw + PI / 2.0 - a
		terrain.create_box(spot + Vector3(0.0, PIER.y / 2.0, 0.0), PIER, face, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		# The lintel bridging this bay to the next — trim, sitting on the piers'
		# own collision volumes, so collide = false keeps the arcade walkable.
		terrain.create_box(spot + Vector3(0.0, PIER.y + LINTEL.y / 2.0, 0.0), LINTEL, face,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)
		if i >= standing:
			continue
		terrain.create_box(spot + Vector3(0.0, tier1_top + PIER2.y / 2.0, 0.0), PIER2, face, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		terrain.create_box(spot + Vector3(0.0, tier1_top + PIER2.y + LINTEL2.y / 2.0, 0.0), LINTEL2, face,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)
		# The attic wall, on a shorter arc still, so the ruin steps down twice.
		if i < standing - 4:
			terrain.create_box(spot + Vector3(0.0, tier2_top + 1.0, 0.0), Vector3(1.2, 2.0, 0.9), face,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	return { "radius": 8.6, "top": tier2_top + 2.0 }

static func _landmark_big_ben(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 9 — BIG BEN (properly the Elizabeth Tower; Big Ben is the bell, which the
	fact says so the card teaches something): a square shaft, four pale clock faces
	under a parapet, a steep spire, and ONE emissive lamp at the very top.

	RADIUS ARITHMETIC (declared 4.4, honestly 3.11). The widest box is the base
	plinth, 0.5*sqrt(2 * 4.4^2) = 3.11 at the centre; the parapet is 2.76 and a
	clock face reaches 1.78 + 1.00 = 2.78. The declared 4.4 is DELIBERATELY LOOSE
	and the reason is the toast, not the stone: the card fires at radius +
	APPROACH_PAD (6), so a true 3.1 would only announce an 18 m tower from 9 m
	away, i.e. from inside its own shadow. Over-declaring costs a little reserved
	ground and nothing else (see the self-check's note).
	THE one accent: the Ayrton Light, lit above the clock while Parliament sits.
	"""
	const PLINTH := Vector3(4.4, 1.0, 4.4)
	const SHAFT := Vector3(3.0, 4.2, 3.0)
	const CLOCK_STAGE := Vector3(3.4, 3.0, 3.4)
	const PARAPET := Vector3(3.9, 0.55, 3.9)
	var yaw := rng.randf_range(0.0, TAU)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)

	terrain.create_box(center + Vector3(0.0, PLINTH.y / 2.0, 0.0), PLINTH, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	var y := PLINTH.y
	for i in 2:
		terrain.create_box(center + Vector3(0.0, y + SHAFT.y / 2.0, 0.0), SHAFT, yaw, rng, block_batch, block_body, 0.0, stone)
		y += SHAFT.y

	# The clock stage, and the four faces on it. The faces are trim on the stage's
	# own collision volume, so collide = false — and they are the brightest albedo
	# on the tower, because at 30 m the pale discs are what say "clock".
	terrain.create_box(center + Vector3(0.0, y + CLOCK_STAGE.y / 2.0, 0.0), CLOCK_STAGE, yaw, rng, block_batch, block_body, 0.0, stone)
	var dial := _lm_shade(LM_MARBLE, rng, 0.02)
	for side in 4:
		var face_yaw := yaw + PI / 2.0 * float(side)
		var out: Vector3 = Basis(Vector3.UP, face_yaw) * Vector3(0.0, 0.0, CLOCK_STAGE.z / 2.0 + 0.08)
		terrain.create_box(center + Vector3(0.0, y + CLOCK_STAGE.y / 2.0, 0.0) + out, Vector3(2.0, 2.0, 0.16),
				face_yaw, rng, block_batch, block_body, 0.0, dial, false)
	y += CLOCK_STAGE.y

	terrain.create_box(center + Vector3(0.0, y + PARAPET.y / 2.0, 0.0), PARAPET, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	y += PARAPET.y

	# The spire: four boxes narrowing to a point.
	for i in 4:
		var w: float = 3.0 - float(i) * 0.68
		var h := 1.3
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04))
		y += h
	terrain.create_box(center + Vector3(0.0, y + 0.35, 0.0), Vector3(0.25, 0.7, 0.25), yaw, rng, block_batch, block_body, 0.0, stone)
	y += 0.7
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 0.3, 0.0), Vector3(0.4, 0.5, 0.4), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 4.4, "top": y + 0.6 }

static func _landmark_pisa(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 10 — LEANING TOWER OF PISA: eight stacked drums with overhanging gallery
	lips, the whole stack tilted off vertical along one bearing.

	THE LEAN IS THE WHOLE LANDMARK, so it is built as a real tilted AXIS rather
	than as a stack of boxes each given a tilt: every drum's centre is placed at
	arc length `s` along a line leaning LEAN (0.10 rad, about 5.7 deg — the real
	tower is 4, exaggerated so it reads at 30 m) toward a rolled bearing, i.e.
	centre + lean_dir * (s * sin LEAN) + UP * (s * cos LEAN). A stack of tilted
	boxes at vertical offsets would shear apart at the joints.

	SIGN GOTCHA, the third instance of the one the Eiffel legs and Liberty's crown
	both record: create_box composes Basis(UP, yaw) * Basis(RIGHT, tilt), and
	Basis(RIGHT, t) tips local +Y toward local +Z, while yaw = PI/2 - a maps local
	+Z onto (cos a, sin a). So a POSITIVE tilt leans the drum's top toward bearing
	a — which is the direction the centres are being offset in, so the two agree
	and the drums stay stacked. Negate it and the stack scissors open.

	RADIUS ARITHMETIC (declared 4.4). The widest thing is a gallery LIP near the
	top of the stack, where the lean offset has grown: at s = 9.0 the offset is
	9.0 * sin(0.10) = 0.90 and a 4.5 x 0.25 lip tilted 0.10 has half-extent
	0.5*sqrt(4.5^2 + (0.25*0.0998 + 4.5*0.995)^2) = 3.18, so 4.08 <= 4.4. The base
	drum is 0.17 + 3.16 = 3.33; the belfry lip is 1.05 + 2.62 = 3.67.
	NO ACCENT.
	"""
	const LEAN := 0.10
	const BASE_DRUM := Vector3(4.4, 1.7, 4.4)
	const GALLERY := Vector3(4.0, 1.45, 4.0)
	const BELFRY := Vector3(3.2, 1.6, 3.2)
	const GALLERIES := 5
	var lean_a := rng.randf_range(0.0, TAU)
	var drum_yaw := PI / 2.0 - lean_a
	var lean_dir := Vector3(cos(lean_a), 0.0, sin(lean_a))
	var marble := _lm_shade(LM_MARBLE, rng, 0.03)

	# One helper closure would be tidier, but GDScript lambdas cannot be static-
	# friendly here; the two lines are cheaper than the indirection.
	var s := 0.0
	var tiers: Array = [BASE_DRUM]
	for i in GALLERIES:
		tiers.append(GALLERY)
	tiers.append(BELFRY)

	for tier_variant: Variant in tiers:
		var dims: Vector3 = tier_variant
		var mid := s + dims.y / 2.0
		var drum_pos := center + lean_dir * (mid * sin(LEAN)) + Vector3(0.0, mid * cos(LEAN), 0.0)
		terrain.create_box(drum_pos, dims, drum_yaw, rng, block_batch, block_body, LEAN, _lm_shade(marble, rng, 0.02))
		# The gallery lip capping this drum — pure overhang, sitting on the drum's
		# own collision volume, so collide = false. It is what makes the stack read
		# as a colonnaded tower rather than as a pile of blocks.
		var lip_s := s + dims.y
		var lip_pos := center + lean_dir * (lip_s * sin(LEAN)) + Vector3(0.0, lip_s * cos(LEAN), 0.0)
		terrain.create_box(lip_pos, Vector3(dims.x + 0.5, 0.25, dims.z + 0.5), drum_yaw,
				rng, block_batch, block_body, LEAN, _lm_shade(marble, rng, 0.02).darkened(0.12), false)
		s += dims.y

	return { "radius": 4.4, "top": s * cos(LEAN) }

static func _landmark_sphinx(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 11 — GREAT SPHINX OF GIZA: a long low recumbent body with two forepaws
	stretched out in front, a raised chest, and a small head under the striped
	nemes headdress. The proportion — a body five times the height of the head,
	with paws out front — is the whole recognition cue.

	It reuses LM_SANDSTONE deliberately: this IS Giza's limestone, and the two
	never appear in the same chunk.

	RADIUS ARITHMETIC (declared 7.6). The widest reach is a FOREPAW: centre at
	sqrt(4.9^2 + 1.05^2) = 5.01 with half-diagonal 0.5*sqrt(4.2^2 + 1.0^2) = 2.16,
	so 7.17 <= 7.6. The body slab is 0.8 + 0.5*sqrt(9.4^2 + 3.4^2) = 0.8 + 5.00 =
	5.80, and the headdress is 1.6 + 1.91 = 3.51.
	NO ACCENT: the Sphinx has no light and never had one.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.04)

	# The body, lying along local +X with its front end toward +X.
	const BODY := Vector3(9.4, 2.4, 3.4)
	terrain.create_box(center + rot * Vector3(-0.8, BODY.y / 2.0, 0.0), BODY, yaw, rng, block_batch, block_body, 0.0, stone)
	# The rear haunch, a little higher than the back.
	terrain.create_box(center + rot * Vector3(-3.6, BODY.y + 0.55, 0.0), Vector3(3.0, 1.1, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# The two forepaws. They collide — walking into a paw is the scale cue.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(4.9, 0.45, side * 1.05), Vector3(4.2, 0.9, 1.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# Chest and head.
	const CHEST := Vector3(2.6, 3.0, 3.0)
	var chest_y := BODY.y + CHEST.y / 2.0
	terrain.create_box(center + rot * Vector3(1.5, chest_y, 0.0), CHEST, yaw, rng, block_batch, block_body, 0.0, stone)
	var head_base := BODY.y + CHEST.y
	terrain.create_box(center + rot * Vector3(1.5, head_base + 0.9, 0.0), Vector3(2.0, 1.8, 2.0), yaw, rng, block_batch, block_body, 0.0, stone)
	# The nemes headdress — the flared cloth that makes the head read as a pharaoh
	# rather than as a lion's. Trim on the head's own volume.
	terrain.create_box(center + rot * Vector3(1.5, head_base + 1.5, 0.0), Vector3(2.8, 1.4, 2.6), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03).darkened(0.12), false)
	# The famous missing nose, as a shadowed recess.
	terrain.create_box(center + rot * Vector3(1.5 + 1.0, head_base + 0.85, 0.0), Vector3(0.35, 0.6, 0.5), yaw,
			rng, block_batch, block_body, 0.0, LM_SANDSTONE.darkened(0.6), false)

	return { "radius": 7.6, "top": head_base + 2.2 }

static func _landmark_redeemer(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 12 — CHRIST THE REDEEMER: a two-step pedestal, a robe tapering upward, a
	small head, and ONE horizontal box for the whole arm span. That single box is
	the landmark: a figure whose arms are wider than it is tall is unmistakable in
	silhouette and unrecoverable if the arms are built as two stepped limbs.

	RADIUS ARITHMETIC (declared 4.8). The arm span box is 8.4 x 0.85 at the centre,
	half-extent 0.5*sqrt(8.4^2 + 0.85^2) = 4.22; the drape blocks hanging at its
	ends reach 3.95 + 0.55 = 4.50; the pedestal is 0.5*sqrt(2 * 4.2^2) = 2.97.
	NO ACCENT: the floodlights are on the mountain, not on the statue.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var soapstone := _lm_shade(LM_STONE_GREY, rng, 0.03)

	var y := 0.0
	for dims in [Vector3(4.2, 1.2, 4.2), Vector3(3.0, 1.6, 3.0)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
		y += dims.y

	# The robe: three boxes narrowing as they rise, the house's cone.
	for i in 3:
		var w: float = 2.0 - float(i) * 0.2
		var h := 2.2
		terrain.create_box(center + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w * 0.8), yaw, rng, block_batch, block_body, 0.0, soapstone)
		y += h

	# THE ARMS — one box, and the reason this shape works at all.
	var shoulder_y := y - 1.1
	terrain.create_box(center + Vector3(0.0, shoulder_y, 0.0), Vector3(8.4, 0.75, 0.85), yaw, rng, block_batch, block_body, 0.0, soapstone)
	# The robe hanging off each hand, which is what stops the span reading as a
	# plank. Trim beside the arm rather than inside it, but small and high, so
	# collide = false keeps the arms a clean single collision box.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 3.95, shoulder_y - 0.75, 0.0), Vector3(0.75, 1.1, 0.8), yaw,
				rng, block_batch, block_body, 0.0, soapstone, false)

	# Head and shoulders above the arms.
	terrain.create_box(center + Vector3(0.0, y + 0.5, 0.0), Vector3(0.9, 1.0, 0.9), yaw, rng, block_batch, block_body, 0.0, soapstone)

	return { "radius": 4.8, "top": y + 1.0 }

static func _landmark_torii(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 13 — ITSUKUSHIMA TORII: two vermilion pillars on four splayed feet under
	TWO crossbeams — the upper one (kasagi) sweeping upward at its ends, the lower
	one (nuki) running straight through the pillars and out the far side. Two beams
	rather than one is what separates a torii from a goalpost.

	THE UPWARD SWEEP IS BUILT AS STEPS, not as a rotation. create_box offers yaw
	and a tilt about the box's local X; the kasagi's long axis IS local X, so no
	tilt available here can lift its ends. Five segments at rising heights give the
	curve in the house's own vocabulary, which is what every other curve in this
	file does too (the Golden Gate's cable, the Taj's dome).

	RADIUS ARITHMETIC (declared 5.6). The widest are the kasagi's end caps, at
	x = 4.5 with half-diagonal 0.5*sqrt(1.2^2 + 1.0^2) = 0.78, so 5.28 <= 5.6. The
	outer kasagi segments are 3.6 + 1.14 = 4.74 and the nuki is 0.5*sqrt(7.6^2 +
	0.9^2) = 3.83.
	NO ACCENT.
	"""
	const PILLAR := Vector3(0.95, 6.0, 0.95)
	const PILLAR_X := 2.8
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var lacquer := _lm_shade(LM_VERMILION, rng, 0.04)

	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * PILLAR_X, PILLAR.y / 2.0, 0.0), PILLAR, yaw, rng, block_batch, block_body, 0.0, lacquer)
		# The four splayed support legs that make this the ITSUKUSHIMA torii rather
		# than a plain one — the shrine's gate stands in the sea on exactly these.
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(side * (PILLAR_X + 0.15), 1.9, z_side * 1.5), Vector3(0.5, 3.8, 0.5),
					yaw, rng, block_batch, block_body, 0.0, _lm_shade(lacquer, rng, 0.03))

	# The nuki: straight, and deliberately longer than the pillar spacing so it
	# protrudes on both sides. Trim (it threads the pillars' own volumes).
	terrain.create_box(center + Vector3(0.0, 4.3, 0.0), Vector3(7.6, 0.6, 0.9), yaw, rng, block_batch, block_body, 0.0, lacquer, false)
	# The gakuzuka, the short strut standing on the nuki.
	terrain.create_box(center + Vector3(0.0, 5.35, 0.0), Vector3(0.5, 1.5, 0.5), yaw, rng, block_batch, block_body, 0.0, lacquer, false)

	# The shimaki (the flat second beam) and the kasagi above it, both stepped
	# upward toward the ends. All trim: a beam 6 m up is not something to stand on.
	var dark := _lm_shade(LM_VERMILION, rng, 0.03).darkened(0.2)
	terrain.create_box(center + Vector3(0.0, 6.1, 0.0), Vector3(7.4, 0.5, 1.0), yaw, rng, block_batch, block_body, 0.0, dark, false)
	const KASAGI_X: Array = [-3.6, -1.8, 0.0, 1.8, 3.6]
	const KASAGI_Y: Array = [6.78, 6.64, 6.58, 6.64, 6.78]
	for i in KASAGI_X.size():
		terrain.create_box(center + rot * Vector3(KASAGI_X[i], KASAGI_Y[i], 0.0), Vector3(2.0, 0.55, 1.1), yaw,
				rng, block_batch, block_body, 0.0, lacquer, false)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 4.5, 6.95, 0.0), Vector3(1.2, 0.5, 1.0), yaw,
				rng, block_batch, block_body, 0.0, lacquer, false)

	return { "radius": 5.6, "top": 7.2 }

static func _landmark_great_wall(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 14 — GREAT WALL OF CHINA: a battlemented wall running clean across the
	chunk with a square watchtower astride it, the wall's height stepping up and
	down so it reads as following a ridge rather than as a fence.

	FIVE SEGMENTS, NOT ONE WALL, and it is the Plaza Mayor's reason exactly: a
	single 17 m box has a half-diagonal of 8.6 which, added to nothing at all,
	already crowds the bound, and there is then no room for the watchtower. Five
	3.5 m bays put the outermost centre at 6.8 with a half-diagonal of 2.12.

	RADIUS ARITHMETIC (declared 9.4, honestly 8.92). The end bay is 6.8 + 2.12 =
	8.92; a merlon on the parapet reaches 8.0 + 0.47 = 8.47; the tower roof is
	0.5*sqrt(4.9^2 + 4.1^2) = 3.19. Declared loose for the toast's sake, like Big
	Ben — this landmark is 17 m long and a card that fired at 15 m would go off
	while the player was already walking along the parapet.
	THE one accent: the beacon fire on the watchtower. Signal fires are what these
	towers were FOR — the wall was a communication line before it was a barrier.
	"""
	const BAYS := 5
	const BAY_STEP := 3.4
	const BAY := Vector3(3.5, 0.0, 2.4)   # y filled in per bay
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var tallest := 0.0
	for i in BAYS:
		var along := (float(i) - float(BAYS - 1) / 2.0) * BAY_STEP
		var h := rng.randf_range(2.6, 3.6)
		tallest = maxf(tallest, h)
		terrain.create_box(center + rot * Vector3(along, h / 2.0, 0.0), Vector3(BAY.x, h, BAY.z), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		# The battlements: alternating merlons along the outer edge of this bay.
		# Trim on the wall's own volume — a 0.65 m block on a parapet is not a step.
		for m in 2:
			var mx := along + (float(m) - 0.5) * 1.7
			terrain.create_box(center + rot * Vector3(mx, h + 0.32, -BAY.z / 2.0 + 0.28), Vector3(0.75, 0.65, 0.55), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03), false)

	# The watchtower, astride the middle bay.
	var tower_h: float = tallest + 2.4
	terrain.create_box(center + Vector3(0.0, tower_h / 2.0, 0.0), Vector3(4.2, tower_h, 3.4), yaw, rng, block_batch, block_body, 0.0, stone)
	terrain.create_box(center + Vector3(0.0, tower_h + 0.25, 0.0), Vector3(4.9, 0.5, 4.1), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04), false)
	# Two dark window slots, so the tower reads as occupied.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 1.1, tower_h - 1.0, 1.68), Vector3(0.6, 1.0, 0.3), yaw,
				rng, block_batch, block_body, 0.0, LM_STONE_GREY.darkened(0.7), false)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, tower_h + 0.9, 0.0), Vector3(0.7, 0.7, 0.7), yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 9.4, "top": tower_h + 0.5 }

static func _landmark_brandenburg(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 15 — BRANDENBURG GATE (Brandenburger Tor): twelve Doric columns in two
	rows under a three-bay entablature, flanked by the two pavilion wings, with the
	copper Quadriga — a chariot and four horses — standing on the attic.

	The gate you can WALK THROUGH is the point: the columns collide and the bays
	between them do not, so the five passages are real.

	RADIUS ARITHMETIC (declared 8.4). The widest reach is a flanking WING: centre
	at 6.0 with half-diagonal 0.5*sqrt(1.8^2 + 3.8^2) = 2.10, so 8.10 <= 8.4. The
	plinth slab is 0.5*sqrt(12.6^2 + 4.8^2) = 6.74 at the centre, an architrave bay
	is 4.4 + 3.04 = 7.44, and a corner column is 5.23 + 0.64 = 5.87.
	NO ACCENT.
	"""
	const COL := Vector3(0.95, 6.0, 0.95)
	const COL_X: Array = [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]
	const COL_Z := 1.55
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.03)

	terrain.create_box(center + Vector3(0.0, 0.3, 0.0), Vector3(12.6, 0.6, 4.8), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng))
	var col_base := 0.6

	for cx_variant: Variant in COL_X:
		var cx: float = cx_variant
		for z_side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(cx, col_base + COL.y / 2.0, z_side * COL_Z), COL, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))

	# The entablature, in three bays for the Plaza Mayor's radius reason.
	var arch_y := col_base + COL.y
	for bx in [-4.4, 0.0, 4.4]:
		terrain.create_box(center + rot * Vector3(bx, arch_y + 0.5, 0.0), Vector3(4.4, 1.0, 4.2), yaw, rng, block_batch, block_body, 0.0, stone)
	# The attic block the Quadriga stands on.
	var attic_y := arch_y + 1.0
	terrain.create_box(center + Vector3(0.0, attic_y + 0.8, 0.0), Vector3(7.2, 1.6, 3.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))

	# The flanking pavilion wings.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 6.0, 2.2, 0.0), Vector3(1.8, 4.4, 3.8), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))

	# THE QUADRIGA — chariot plus four horses, in oxidised copper so it reads
	# against the sandstone. All trim: it is 11 m up and nothing may stand on it.
	var q_y := attic_y + 1.6
	var copper := _lm_shade(LM_COPPER, rng, 0.03)
	terrain.create_box(center + rot * Vector3(-1.2, q_y + 0.55, 0.0), Vector3(1.4, 1.1, 1.3), yaw, rng, block_batch, block_body, 0.0, copper, false)
	for h in 4:
		var hx: float = 0.2 + float(h) * 0.85
		terrain.create_box(center + rot * Vector3(hx, q_y + 0.6, (float(h) - 1.5) * 0.55), Vector3(1.6, 1.2, 0.55), yaw,
				rng, block_batch, block_body, 0.0, copper, false)
		terrain.create_box(center + rot * Vector3(hx + 0.85, q_y + 1.15, (float(h) - 1.5) * 0.55), Vector3(0.5, 0.5, 0.4), yaw,
				rng, block_batch, block_body, 0.0, copper, false)

	return { "radius": 8.4, "top": q_y + 1.4 }

static func _landmark_neuschwanstein(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 16 — NEUSCHWANSTEIN CASTLE: a white castle on a grey crag — a tall slender
	keep, a long palas beside it, a lower gatehouse, three corner turrets, and a
	blue-grey conical roof on every one of them. The BLUE ROOFS are the recognition
	cue and the reason LM_SLATE_BLUE is one of the two colours wave 2 added: the
	walls reuse the Taj's marble, so without them a distant white castle is a
	distant white mausoleum.

	RADIUS ARITHMETIC (declared 8.0). The widest reach is the GATEHOUSE, centre at
	sqrt(4.8^2 + 0.8^2) = 4.87 with half-diagonal 0.5*sqrt(3.2^2 + 3.4^2) = 2.33,
	so 7.20 <= 8.0. The crag slab is 0.5*sqrt(7.6^2 + 6.4^2) = 4.97, a turret's
	roof base reaches 5.2 + 1.27 = 6.47, and the keep is 4.05 + 1.56 = 5.61.
	NO ACCENT.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var wall := _lm_shade(LM_MARBLE, rng, 0.02)
	var roof := _lm_shade(LM_SLATE_BLUE, rng, 0.04)

	# The crag. Two grey slabs, so the castle stands on rock rather than on grass.
	terrain.create_box(center + Vector3(0.0, 0.5, 0.0), Vector3(7.6, 1.0, 6.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	terrain.create_box(center + rot * Vector3(-0.4, 1.7, 0.0), Vector3(5.4, 1.4, 5.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.05))
	const CRAG := 2.4

	# The palas, in two bays.
	for bx in [-2.2, 2.2]:
		terrain.create_box(center + rot * Vector3(bx, CRAG + 3.2, 0.0), Vector3(4.2, 6.4, 4.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
	# A gabled roof band over the palas — trim on the bays' own volumes.
	terrain.create_box(center + Vector3(0.0, CRAG + 6.8, 0.0), Vector3(8.8, 0.8, 4.6), yaw, rng, block_batch, block_body, 0.0, roof, false)

	# The gatehouse, lower and off to one side.
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 2.3, 0.8), Vector3(3.2, 4.6, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 4.9, 0.8), Vector3(3.6, 0.7, 3.8), yaw, rng, block_batch, block_body, 0.0, roof, false)
	# Its dark arched doorway.
	terrain.create_box(center + rot * Vector3(4.8, CRAG + 1.2, 2.55), Vector3(1.2, 2.2, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_MARBLE.darkened(0.72), false)

	# The keep — the tall slender one, and the tallest thing here.
	const KEEP := Vector3(2.2, 10.5, 2.2)
	var keep_spot := center + rot * Vector3(-3.8, 0.0, -1.4)
	terrain.create_box(keep_spot + Vector3(0.0, CRAG + KEEP.y / 2.0, 0.0), KEEP, yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
	var top := CRAG + KEEP.y
	# Its spire: three shrinking slabs to a point.
	for i in 3:
		var w: float = 2.7 - float(i) * 0.75
		terrain.create_box(keep_spot + Vector3(0.0, top + 0.6, 0.0), Vector3(w, 1.2, w), yaw, rng, block_batch, block_body, 0.0, roof, false)
		top += 1.2

	# Three corner turrets, each with its own cone.
	const TURRET_SPOTS: Array = [Vector2(-4.4, 2.6), Vector2(1.4, -3.4), Vector2(4.4, -2.4)]
	for spot_variant: Variant in TURRET_SPOTS:
		var spot: Vector2 = spot_variant
		var base := center + rot * Vector3(spot.x, 0.0, spot.y)
		var t_h := rng.randf_range(6.0, 7.4)
		terrain.create_box(base + Vector3(0.0, CRAG + t_h / 2.0, 0.0), Vector3(1.3, t_h, 1.3), yaw, rng, block_batch, block_body, 0.0, _lm_shade(wall, rng, 0.02))
		var ty := CRAG + t_h
		for i in 2:
			var w: float = 1.8 - float(i) * 0.7
			terrain.create_box(base + Vector3(0.0, ty + 0.45, 0.0), Vector3(w, 0.9, w), yaw, rng, block_batch, block_body, 0.0, roof, false)
			ty += 0.9

	return { "radius": 8.0, "top": top }

static func _landmark_cologne(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 17 — COLOGNE CATHEDRAL (Kölner Dom): TWIN openwork spires over a west
	front, a nave running back behind them under a steep ridge roof, and a small
	apse at the far end. Twin spires of equal height is the cue — one spire is a
	church, two is the Dom.

	It reuses LM_BASALT: Cologne's stone is near-black with centuries of soot, and
	nothing else in the registry is that dark except the Moai, whose silhouette
	could not be confused with this one at any distance.

	RADIUS ARITHMETIC (declared 8.6). The furthest box is the APSE at the far end
	of the nave: centre at 6.2 with half-diagonal 0.5*sqrt(3.6^2 + 2.2^2) = 2.11,
	so 8.31 <= 8.6. A nave bay is 4.0 + 3.28 = 7.28, the roof ridge is 2.3 + 4.47 =
	6.77, and a tower is sqrt(2.2^2 + 3.0^2) = 3.72 + 2.12 = 5.84.
	NO ACCENT: a Gothic cathedral lit from within would need windows, and windows
	are exactly the detail that vanishes at 30 m.
	"""
	const TOWER := Vector3(3.0, 13.0, 3.0)
	const TOWER_X := 2.2
	const TOWER_Z := -3.0
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_BASALT, rng, 0.03)

	# The nave, two bays, plus the ridge roof over them.
	for bz in [0.6, 4.0]:
		terrain.create_box(center + rot * Vector3(0.0, 3.6, bz), Vector3(5.6, 7.2, 3.4), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	terrain.create_box(center + rot * Vector3(0.0, 7.85, 2.3), Vector3(5.0, 1.3, 7.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02).darkened(0.2), false)
	# The apse closing the far end.
	terrain.create_box(center + rot * Vector3(0.0, 3.3, 6.2), Vector3(3.6, 6.6, 2.2), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	# Buttress stubs down the flanks — the ribs that say Gothic in four boxes.
	for bx in [-3.6, 3.6]:
		for bz in [1.0, 4.2]:
			terrain.create_box(center + rot * Vector3(bx, 2.6, bz), Vector3(0.9, 5.2, 0.9), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# The west front between the towers.
	terrain.create_box(center + rot * Vector3(0.0, 5.25, TOWER_Z), Vector3(1.8, 10.5, 3.0), yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	# The great west portal, dark and deep.
	terrain.create_box(center + rot * Vector3(0.0, 1.7, TOWER_Z - 1.6), Vector3(1.4, 3.4, 0.5), yaw,
			rng, block_batch, block_body, 0.0, LM_BASALT.darkened(0.6), false)

	# THE TWIN TOWERS and their spires — equal height, deliberately, because that
	# is the whole recognition cue.
	var tip := 0.0
	for side in [-1.0, 1.0]:
		var base := center + rot * Vector3(side * TOWER_X, 0.0, TOWER_Z)
		terrain.create_box(base + Vector3(0.0, TOWER.y / 2.0, 0.0), TOWER, yaw, rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
		var y := TOWER.y
		# Four shrinking slabs to a needle point. Trim: it is 13 m up.
		for i in 4:
			var w: float = 2.7 - float(i) * 0.6
			var h := 1.5
			terrain.create_box(base + Vector3(0.0, y + h / 2.0, 0.0), Vector3(w, h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
			y += h
		terrain.create_box(base + Vector3(0.0, y + 0.5, 0.0), Vector3(0.3, 1.0, 0.3), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
		tip = y + 1.0

	return { "radius": 8.6, "top": tip }

# ----------------------------------------------------------------------------
# WAVE 3
# ----------------------------------------------------------------------------

static func _lm_onion(terrain: Node3D, base: Vector3, width: float, color: Color, yaw: float, rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> float:
	"""
	ONE ONION DOME, and the middle box is the WIDEST — that is the entire trick. A
	stack that only ever narrows is a cone, and this file already has cones
	(Neuschwanstein's spires, Angkor's lotus towers taper the same way); the BULGE
	is what makes a dome an onion, so this goes drum -> bulge wider than the drum ->
	shoulder narrowing back in -> finial spike.

	Shared by St Basil's six ring towers and its centre spire's crown, which is why
	the six read as one building rather than as six separate experiments. Returns
	the height it added above `base` (which is the top of whatever it stands on).

	ALL OF IT IS collide = false: these sit 6-14 m up, on their own tower's
	collision volume, and a 2 m bulb is not a thing to stand on.
	"""
	var h := 0.0
	terrain.create_box(base + Vector3(0.0, 0.25, 0.0), Vector3(width * 0.78, 0.5, width * 0.78), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false)
	h += 0.5
	terrain.create_box(base + Vector3(0.0, h + width * 0.42, 0.0), Vector3(width, width * 0.84, width), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false)
	h += width * 0.84
	terrain.create_box(base + Vector3(0.0, h + 0.28, 0.0), Vector3(width * 0.52, 0.56, width * 0.52), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(color, rng, 0.03), false)
	h += 0.56
	terrain.create_box(base + Vector3(0.0, h + 0.55, 0.0), Vector3(0.18, 1.1, 0.18), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_SANDSTONE, rng, 0.02), false)
	return h + 1.1

static func _landmark_st_basil(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 18 — ST BASIL'S CATHEDRAL: a low white podium carrying a tall central tent
	spire ringed by six shorter towers, each capped with an ONION DOME in a
	different colour.

	THE ONLY LANDMARK IN THE REGISTRY WHOSE COLOURS DO THE RECOGNISING, which is
	precisely why the four it needs had to already exist — LM_VERMILION brick,
	LM_COPPER oxidised green, LM_MARBLE white and LM_SANDSTONE standing in for gold
	leaf. At the 30 m these shapes are judged from a warm tan reads as gold, and
	adding a fifth entry to the palette to be literal about it would have made every
	OTHER landmark one shade harder to tell apart (the wave-2 palette rule).

	The centre tower is a TENT ROOF rather than an onion, and that contrast is
	deliberate: the real cathedral's middle spire is the one thing on it that does
	not bulge, so making it bulge too would flatten nine domes into one texture.

	RADIUS ARITHMETIC (declared 6.4). The podium is the widest box, 8.0 square, so
	0.5*sqrt(2*8.0^2) = 5.66. A ring tower's dome bulge is 1.9 square (half-diagonal
	1.34) on the RING_R 3.6 ring => 4.94. So 5.66 <= 6.4.
	NO ACCENT: the domes are gilded, not lit.
	"""
	const RING_R := 3.6
	const TOWERS := 6
	const PODIUM := Vector3(8.0, 1.0, 8.0)
	# Cycled round the ring, and 4 into 6 does not divide — which is the point: no
	# two neighbours match and the pattern does not repeat on the far side either.
	var dome_colors: Array = [LM_VERMILION, LM_COPPER, LM_SANDSTONE, LM_MARBLE]
	var yaw := rng.randf_range(0.0, TAU)
	var brick := _lm_shade(LM_VERMILION, rng, 0.04).darkened(0.1)

	terrain.create_box(center + Vector3(0.0, PODIUM.y / 2.0, 0.0), PODIUM, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_MARBLE, rng, 0.03))

	# The six chapel towers. Heights step in threes so the ring reads as a crown
	# rather than as a fence of equal posts — no two of the real ones match either.
	var top := PODIUM.y
	for i in TOWERS:
		var a := yaw + TAU * float(i) / float(TOWERS)
		var spot := center + Vector3(cos(a) * RING_R, 0.0, sin(a) * RING_R)
		var shaft_h: float = 4.2 + float(i % 3) * 1.1
		terrain.create_box(spot + Vector3(0.0, PODIUM.y + shaft_h / 2.0, 0.0), Vector3(1.7, shaft_h, 1.7), yaw,
				rng, block_batch, block_body, 0.0, brick)
		var dome_h := _lm_onion(terrain, spot + Vector3(0.0, PODIUM.y + shaft_h, 0.0), 1.9,
				dome_colors[i % dome_colors.size()], yaw, rng, block_batch, block_body)
		top = maxf(top, PODIUM.y + shaft_h + dome_h)

	# The centre: an octagonal shaft (two boxes crossed at 45 degrees, which is as
	# octagonal as a box vocabulary gets) under a stepped tent roof.
	const SHAFT_H := 9.0
	for k in 2:
		terrain.create_box(center + Vector3(0.0, PODIUM.y + SHAFT_H / 2.0, 0.0), Vector3(2.9, SHAFT_H, 2.9),
				yaw + float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, _lm_shade(LM_MARBLE, rng, 0.03))
	var ty := PODIUM.y + SHAFT_H
	for i in 5:
		var w: float = 2.7 - float(i) * 0.46
		terrain.create_box(center + Vector3(0.0, ty + 0.55, 0.0), Vector3(w, 1.1, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_VERMILION, rng, 0.03), false)
		ty += 1.1
	var crown := _lm_onion(terrain, center + Vector3(0.0, ty, 0.0), 1.2, LM_SANDSTONE, yaw, rng, block_batch, block_body)

	return { "radius": 6.4, "top": maxf(top, ty + crown) }

static func _landmark_sydney_opera(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 19 — SYDNEY OPERA HOUSE: a low podium carrying three groups of white
	SHELLS, each shell a run of slabs that get shorter and narrower as they step
	away from its mouth — a sail seen edge on. Two big groups facing one way and a
	small third facing the other is the plan of the real building, and that
	asymmetric roofline is most of what a person actually recognises; three
	identical shells would read as a row of tents.

	SHELLS ARE STEPS, NOT ARCS, for the torii's reason exactly: create_box offers a
	yaw and a tilt about the box's own local X, and neither can sweep a box's TOP
	into a curve. Six stepped slabs give the sail in the house's own vocabulary.
	The shells COLLIDE — they are the building — and only the dark glass mouth,
	which sits inside a shell's own volume, does not.

	RADIUS ARITHMETIC (declared 8.2). The podium is the widest box, 14.0 x 6.0, so
	0.5*sqrt(14.0^2 + 6.0^2) = 7.62. The furthest shell slab is the small group's
	last, at sqrt(4.8^2 + 2.99^2) = 5.66 with a half-diagonal of 0.96 => 6.62; the
	big group's is 4.31 + 1.75 = 6.06. So 7.62 <= 8.2.
	NO ACCENT.
	"""
	const PODIUM := Vector3(14.0, 1.1, 6.0)
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var sail := _lm_shade(LM_MARBLE, rng, 0.02)

	terrain.create_box(center + Vector3(0.0, PODIUM.y / 2.0, 0.0), PODIUM, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.03))

	# x offset, z offset, which way the shell steps back, and how big it is.
	var groups: Array = [
		{ "x": -3.4, "z": -0.6, "dir": 1.0, "s": 1.0 },
		{ "x": 1.4, "z": 0.4, "dir": 1.0, "s": 0.82 },
		{ "x": 4.8, "z": -1.2, "dir": -1.0, "s": 0.55 },
	]
	var tallest := PODIUM.y
	for g in groups:
		var s: float = g.s
		var dir: float = g.dir
		for i in 6:
			var t := float(i) / 5.0
			var h: float = (7.6 - 5.6 * t) * s      # the tall slab is at the shell's MOUTH
			var w: float = (3.4 - 1.9 * t) * s
			var d: float = (0.85 - 0.28 * t) * s
			var z: float = float(g.z) + dir * (0.35 + t * 2.9) * s
			terrain.create_box(center + rot * Vector3(g.x, PODIUM.y + h / 2.0, z), Vector3(w, h, d), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(sail, rng, 0.02))
			tallest = maxf(tallest, PODIUM.y + h)

	# The glass wall closing each shell's mouth — the dark vertical face that stops
	# a shell reading as a solid white wedge. Trim on the shell's own volume.
	for g in groups:
		var s: float = g.s
		terrain.create_box(center + rot * Vector3(g.x, PODIUM.y + 2.4 * s, float(g.z) - float(g.dir) * 0.52 * s),
				Vector3(3.2 * s, 4.4 * s, 0.25), yaw, rng, block_batch, block_body, 0.0,
				LM_SLATE_BLUE.darkened(0.35), false)

	return { "radius": 8.2, "top": tallest }

static func _landmark_chichen_itza(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 20 — CHICHÉN ITZÁ: El Castillo — a nine-tier square step pyramid with ONE
	broad stairway climbing the front face and a small temple on the summit.

	THE STAIR AND THE TEMPLE ARE THE WHOLE REASON THIS IS NOT GIZA. Both landmarks
	are stepped pyramids of sandstone-coloured boxes, and the registry can put
	either in front of the player, so the two things that separate them get real
	geometry and the tiers get nothing else at all: Giza is a TRIO of smooth
	shrinking stacks, this is ONE stack with a stripe of treads up its face and a
	block on top.

	The treads COLLIDE and are untilted, so the stair is a real climb rather than a
	painted stripe — 0.92 m a step, comfortably inside the 3.6125 m jump apex.

	RADIUS ARITHMETIC (declared 8.4). The bottom tier is 11.0 square, so
	0.5*sqrt(2*11.0^2) = 7.78. Its tread sits at z = 5.95 with a half-diagonal of
	0.5*sqrt(3.6^2 + 1.0^2) = 1.87 => 7.82. So 7.82 <= 8.4.
	NO ACCENT: the serpent's shadow needs an equinox, not a lamp.
	"""
	const TIERS := 9
	const BASE_W := 11.0
	const TIER_H := 0.92
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var limestone := _lm_shade(LM_SANDSTONE, rng, 0.04)

	# Divided by TIERS + 3 rather than TIERS + 1 so the summit stays broad enough to
	# carry the temple — a pyramid that tapers to a point has nowhere to put one.
	var shrink := BASE_W / float(TIERS + 3)
	var y := 0.0
	for i in TIERS:
		var w: float = BASE_W - float(i) * shrink
		terrain.create_box(center + Vector3(0.0, y + TIER_H / 2.0, 0.0), Vector3(w, TIER_H, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.02))
		terrain.create_box(center + rot * Vector3(0.0, y + TIER_H / 2.0, w / 2.0 + 0.45), Vector3(3.6, TIER_H, 1.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.02))
		y += TIER_H

	# The temple: a squat block with a cornice and one dark doorway.
	const TEMPLE := Vector3(3.4, 2.6, 3.4)
	terrain.create_box(center + Vector3(0.0, y + TEMPLE.y / 2.0, 0.0), TEMPLE, yaw, rng, block_batch, block_body,
			0.0, _lm_shade(limestone, rng, 0.02))
	terrain.create_box(center + Vector3(0.0, y + TEMPLE.y + 0.2, 0.0), Vector3(3.9, 0.4, 3.9), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(limestone, rng, 0.03), false)
	terrain.create_box(center + rot * Vector3(0.0, y + 1.05, TEMPLE.z / 2.0 - 0.08), Vector3(1.3, 1.9, 0.35), yaw,
			rng, block_batch, block_body, 0.0, LM_SANDSTONE.darkened(0.75), false)

	return { "radius": 8.4, "top": y + TEMPLE.y + 0.4 }

static func _landmark_petra(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 21 — PETRA: Al-Khazneh, and the recognition cue is that the building is NOT
	a building — it is a facade cut INTO a cliff. So the cliff goes up first, at full
	width and with two ragged shoulders so it does not read as a wall somebody built,
	and everything else is carved out of its front face.

	THE SECOND STOREY IS WHAT MAKES IT PETRA. A row of columns under a triangular
	pediment is a temple, and this registry already has that silhouette twice (the
	Brandenburg Gate's colonnade, the Plaza's arcade). What nothing else has is the
	upper storey: a round drum with a conical cap standing BETWEEN two half-pediments,
	which is why the tholos gets its own crossed-box octagon rather than being
	simplified into another block.

	RADIUS ARITHMETIC (declared 8.0). The cliff slab is the widest box, 12.0 x 3.2,
	set back to z = -1.3: 1.3 + 0.5*sqrt(12.0^2 + 3.2^2) = 1.3 + 6.22 = 7.52. The
	entablature is 10.0 x 1.4 at z = 0.55 => 0.55 + 5.05 = 5.60; a shoulder is at
	sqrt(5.2^2 + 0.6^2) = 5.23 with half-diagonal 1.56 => 6.79. So 7.52 <= 8.0.
	NO ACCENT.
	"""
	const CLIFF := Vector3(12.0, 14.0, 3.2)
	const FACADE_Z := 0.35
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var rock := _lm_shade(LM_OCHRE, rng, 0.05)

	terrain.create_box(center + rot * Vector3(0.0, CLIFF.y / 2.0, -1.3), CLIFF, yaw, rng, block_batch, block_body, 0.0, rock)
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 5.2, 4.5, 0.6), Vector3(2.4, 9.0, 2.0),
				yaw + side * 0.12, rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.04))

	# LOWER STOREY: a plinth, six columns, an entablature, a stepped pediment.
	terrain.create_box(center + rot * Vector3(0.0, 0.35, FACADE_Z), Vector3(9.6, 0.7, 2.0), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 1.7, 3.3, FACADE_Z + 0.35), Vector3(0.7, 5.2, 0.7), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	terrain.create_box(center + rot * Vector3(0.0, 6.3, FACADE_Z + 0.2), Vector3(10.0, 1.0, 1.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	for i in 3:
		terrain.create_box(center + rot * Vector3(0.0, 7.1 + float(i) * 0.6, FACADE_Z + 0.1),
				Vector3(8.6 - float(i) * 2.6, 0.6, 1.1), yaw, rng, block_batch, block_body, 0.0,
				_lm_shade(rock, rng, 0.03), false)
	# The doorway — the one thing on the facade that is a hole rather than stone.
	terrain.create_box(center + rot * Vector3(0.0, 2.5, FACADE_Z - 0.5), Vector3(2.0, 4.0, 0.4), yaw,
			rng, block_batch, block_body, 0.0, LM_OCHRE.darkened(0.8), false)

	# UPPER STOREY: two flanking blocks with their broken cornices, and the tholos.
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 3.5, 10.2, FACADE_Z), Vector3(2.6, 5.0, 1.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
		terrain.create_box(center + rot * Vector3(side * 3.5, 12.9, FACADE_Z), Vector3(3.0, 0.5, 1.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false)
	for k in 2:
		terrain.create_box(center + rot * Vector3(0.0, 10.4, FACADE_Z + 0.1), Vector3(3.2, 4.6, 3.2),
				yaw + float(k) * PI / 4.0, rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03))
	for i in 3:
		var w: float = 2.6 - float(i) * 0.75
		terrain.create_box(center + rot * Vector3(0.0, 12.9 + float(i) * 0.55, FACADE_Z + 0.1), Vector3(w, 0.55, w), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false)
	terrain.create_box(center + rot * Vector3(0.0, 14.9, FACADE_Z + 0.1), Vector3(0.9, 1.0, 0.9), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(rock, rng, 0.03), false)

	return { "radius": 8.0, "top": 15.4 }

static func _landmark_rushmore(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 22 — MOUNT RUSHMORE: a granite bluff built from four jagged segments, with
	four heads in a row protruding from its front face and a talus of tumbled
	boulders at its foot.

	THE ROCK IS DELIBERATELY IRREGULAR and the heads are deliberately not. Four busts
	in a row on a tidy wall is a monument; four faces emerging from a mountain that
	clearly was not built is Rushmore, so the cliff segments jitter in height and yaw
	while the heads stay level, evenly spaced and identical in size.

	RADIUS ARITHMETIC (declared 8.6). The outermost cliff segment is at
	sqrt(5.4^2 + 1.0^2) = 5.49 with a half-diagonal of 0.5*sqrt(4.6^2 + 3.6^2) = 2.92
	=> 8.41 — and its yaw jitter is already inside that, because a half-diagonal
	bounds a box at ANY yaw. The furthest boulder is at sqrt(6.4^2 + 1.9^2) = 6.68
	with a tilted half-diagonal under 1.30 => 7.98; the outermost head's hair block is
	at 5.55 + 1.17 = 6.72. So 8.41 <= 8.6.
	NO ACCENT.
	"""
	const SEGMENTS := 4
	const SEG_STEP := 3.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var granite := _lm_shade(LM_GRANITE, rng, 0.05)

	var tallest := 0.0
	for i in SEGMENTS:
		var sx := (float(i) - float(SEGMENTS - 1) / 2.0) * SEG_STEP
		var h := rng.randf_range(8.0, 11.5)
		tallest = maxf(tallest, h)
		terrain.create_box(center + rot * Vector3(sx, h / 2.0, -1.0), Vector3(4.6, h, 3.6),
				yaw + rng.randf_range(-0.12, 0.12), rng, block_batch, block_body, 0.0, _lm_shade(granite, rng, 0.04))
		# One boulder off the talus slope every carved cliff has. Tilted, so it must
		# stay small: a tilt widens a box's horizontal reach as well as leaning it.
		terrain.create_box(center + rot * Vector3(sx + rng.randf_range(-1.0, 1.0), 0.7, 1.9), Vector3(1.8, 1.4, 1.5),
				yaw + rng.randf_range(0.0, TAU), rng, block_batch, block_body, rng.randf_range(-0.2, 0.2),
				_lm_shade(granite, rng, 0.05))

	# The four heads. Trim (brow, nose, hair) sits on the head's own volume, so
	# collide = false; the head itself collides like the rock it was cut from.
	const HEAD_Y := 6.6
	for i in 4:
		var hx := (float(i) - 1.5) * 3.4
		var face := _lm_shade(granite, rng, 0.03).lightened(0.06)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y, 2.2), Vector3(1.7, 2.2, 1.5), yaw,
				rng, block_batch, block_body, 0.0, face)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y + 0.45, 3.0), Vector3(1.5, 0.35, 0.35), yaw,
				rng, block_batch, block_body, 0.0, face, false)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y - 0.05, 3.05), Vector3(0.35, 0.7, 0.45), yaw,
				rng, block_batch, block_body, 0.0, face, false)
		terrain.create_box(center + rot * Vector3(hx, HEAD_Y + 1.35, 2.1), Vector3(1.8, 0.7, 1.5), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(granite, rng, 0.04), false)

	return { "radius": 8.6, "top": tallest }

static func _landmark_angkor_wat(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 23 — ANGKOR WAT: five lotus towers in a quincunx — four on the corners of a
	square, one taller in the middle — on two stepped terraces, with a causeway
	running out from one face.

	THE CAUSEWAY EXISTS TO MAKE THE QUINCUNX READ AS A PLAN. Five spires with nothing
	pointing at them is five spires; one walk approaching them from a single side is
	what tells the eye which way the temple faces, and a plan you can read from
	outside is the whole recognition cue.

	A LOTUS TOWER IS A CONE WITH A WAIST: four narrowing tiers, then one that goes
	WIDER again, then the finial. That small bulge two thirds up is what separates it
	from Neuschwanstein's plain cones and from El Castillo's even steps.

	RADIUS ARITHMETIC (declared 9.0). The lower terrace is 12.0 square, so
	0.5*sqrt(2*12.0^2) = 8.49. The causeway slab is 3.0 x 4.4 centred 5.4 out:
	5.4 + 0.5*sqrt(3.0^2 + 4.4^2) = 5.4 + 2.66 = 8.06. A corner tower's shaft is 2.4
	square (half-diagonal 1.70) on the (3.4, 3.4) corner (offset 4.81) => 6.51.
	So 8.49 <= 9.0.
	NO ACCENT.
	"""
	const TOWER_R := 3.4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var y := 0.0
	for dims in [Vector3(12.0, 0.9, 12.0), Vector3(9.4, 1.0, 9.4)]:
		terrain.create_box(center + Vector3(0.0, y + dims.y / 2.0, 0.0), dims, yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.03))
		y += dims.y

	terrain.create_box(center + rot * Vector3(0.0, 0.45, 5.4), Vector3(3.0, 0.9, 4.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	for side in [-1.0, 1.0]:
		terrain.create_box(center + rot * Vector3(side * 1.35, 1.25, 5.4), Vector3(0.4, 0.7, 4.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)

	var spots: Array = [
		Vector2(-TOWER_R, -TOWER_R), Vector2(TOWER_R, -TOWER_R),
		Vector2(-TOWER_R, TOWER_R), Vector2(TOWER_R, TOWER_R), Vector2(0.0, 0.0),
	]
	var tallest := y
	for i in spots.size():
		var p: Vector2 = spots[i]
		var f := 1.0 if i < 4 else 1.34   # the middle one is the tall one
		var spot := center + rot * Vector3(p.x, 0.0, p.y)
		var ty := y
		terrain.create_box(spot + Vector3(0.0, ty + 1.5 * f, 0.0), Vector3(2.4 * f, 3.0 * f, 2.4 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		ty += 3.0 * f
		for k in 4:
			var w: float = (2.2 - float(k) * 0.34) * f
			var h: float = 0.85 * f
			terrain.create_box(spot + Vector3(0.0, ty + h / 2.0, 0.0), Vector3(w, h, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
			ty += h
		# The waist that makes it a lotus rather than a cone.
		terrain.create_box(spot + Vector3(0.0, ty + 0.45 * f, 0.0), Vector3(1.5 * f, 0.9 * f, 1.5 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
		ty += 0.9 * f
		terrain.create_box(spot + Vector3(0.0, ty + 0.6 * f, 0.0), Vector3(0.5 * f, 1.2 * f, 0.5 * f), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
		tallest = maxf(tallest, ty + 1.2 * f)

	return { "radius": 9.0, "top": tallest }

static func _landmark_machu_picchu(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 24 — MACHU PICCHU: four broad agricultural terraces stepping up a slope, a
	scatter of small roofless stone houses on the flat above them, and one sharp
	peak leaning over the lot.

	THE PEAK IS THE RISK, NOT THE FEATURE. Huayna Picchu is what a photograph of
	Machu Picchu is framed by, but a lone rock spike is EXACTLY what a mountain
	massif already looks like in this world — so the terraces have to carry the
	recognition on their own: four wide, shallow, evenly stepped slabs (a rough
	slope would read as scenery) with a town standing on top of them. The peak is
	built last and leans, so it is clearly a backdrop rather than the subject.

	The terrace risers are 1.1 m, so the stack is climbable — which is the right
	reading for a hillside somebody farmed.

	RADIUS ARITHMETIC (declared 9.0). A terrace is 10.0 x 2.0 and the front one is at
	z = 3.6: 3.6 + 0.5*sqrt(10.0^2 + 2.0^2) = 3.6 + 5.10 = 8.70. The peak's base box
	is 3.4 square at z = -5.0 with up to 1.2 of x jitter (offset 5.14) and a tilt of
	up to 0.14, which widens its half-diagonal to 2.57 => 7.71. So 8.70 <= 9.0.
	NO ACCENT.
	"""
	const TERRACES := 4
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_STONE_GREY, rng, 0.04)

	var top_y := 0.0
	for i in TERRACES:
		var h: float = 1.1 * float(i + 1)
		terrain.create_box(center + rot * Vector3(0.0, h / 2.0, 3.6 - float(i) * 1.8), Vector3(10.0, h, 2.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		top_y = h

	# The town: shells rather than four-walled rooms (four thin walls would be four
	# times the boxes for the same 30 m silhouette), each with a dark doorway.
	# Jittered in place and yaw — an Inca town on a ridge is not a grid.
	for i in 6:
		var hx := rng.randf_range(-3.8, 3.8)
		var hz := rng.randf_range(-3.4, -0.6)
		var hh := rng.randf_range(1.5, 2.1)
		var hyaw := yaw + rng.randf_range(-0.4, 0.4)
		terrain.create_box(center + rot * Vector3(hx, top_y + hh / 2.0, hz), Vector3(1.9, hh, 1.6), hyaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.04))
		terrain.create_box(center + rot * Vector3(hx, top_y + 0.7, hz) + Basis(Vector3.UP, hyaw) * Vector3(0.0, 0.0, 0.85),
				Vector3(0.6, 1.2, 0.3), hyaw, rng, block_batch, block_body, 0.0, LM_STONE_GREY.darkened(0.75), false)

	# Huayna Picchu: three boxes each smaller than the last and each nudged the same
	# way, so the peak overhangs the town exactly as the real one does.
	var px := rng.randf_range(-1.2, 1.2)
	var py := top_y
	var lean := rng.randf_range(0.06, 0.14)
	var pw := 3.4
	for i in 3:
		var h: float = 3.4 - float(i) * 0.5
		terrain.create_box(center + rot * Vector3(px + float(i) * 0.5, py + h / 2.0, -5.0 + float(i) * 0.45),
				Vector3(pw, h, pw), yaw + float(i) * 0.3, rng, block_batch, block_body, lean,
				_lm_shade(stone, rng, 0.05))
		py += h
		pw -= 0.9

	return { "radius": 9.0, "top": py }

static func _landmark_pont_du_gard(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 25 — PONT DU GARD: three tiers of arches — three big ones at the bottom,
	five above them, and a run of small ones carrying the water channel across the
	top. Arches getting smaller and more numerous as they rise IS the recognition
	cue, and it is why every tier is built as PIERS AND LINTELS rather than as a wall
	with holes: an arch you can see daylight through is the difference between an
	aqueduct and a viaduct-shaped block.

	THE SECOND TIER'S PIERS DELIBERATELY DO NOT SIT OVER THE FIRST'S. A shifted
	rhythm is what an aqueduct looks like; a stacked one is what a modern bridge
	looks like, and the Golden Gate already owns "bridge" in this registry.

	BUILT AS BAYS, NOT AS SPANS — the Great Wall's lesson. A single 14 m lintel has a
	half-diagonal of 7.0 before anything else is added to it.

	RADIUS ARITHMETIC (declared 8.8). The outermost second-tier pier is at x = 7.0
	with a half-diagonal of 0.5*sqrt(1.2^2 + 2.2^2) = 1.25 => 8.25. A bottom pier is
	at 6.3 with 0.5*sqrt(1.8^2 + 2.6^2) = 1.58 => 7.88; the top deck's outermost
	segment is at 5.6 + 1.71 = 7.31. So 8.25 <= 8.8.
	NO ACCENT.
	"""
	const T1_H := 5.0
	const T2_H := 4.2
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)
	var stone := _lm_shade(LM_SANDSTONE, rng, 0.05)

	# TIER 1 — four heavy piers carrying three big arches.
	for i in 4:
		terrain.create_box(center + rot * Vector3((float(i) - 1.5) * 4.2, T1_H / 2.0, 0.0), Vector3(1.8, T1_H, 2.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	for i in 3:
		terrain.create_box(center + rot * Vector3((float(i) - 1.0) * 4.2, T1_H + 0.5, 0.0), Vector3(4.2, 1.0, 2.4), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# TIER 2 — six lighter piers over the same span, carrying five arches.
	var t2_y: float = T1_H + 1.0
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 2.8, t2_y + T2_H / 2.0, 0.0), Vector3(1.2, T2_H, 2.2), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
	for i in 5:
		terrain.create_box(center + rot * Vector3((float(i) - 2.0) * 2.8, t2_y + T2_H + 0.45, 0.0), Vector3(2.8, 0.9, 2.0), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))

	# TIER 3 — the channel, on a run of small arches. The deck collides (it is the
	# top of an aqueduct, and the one part of this shape a player could reach from a
	# hillside); the channel walls and the little piers are trim on its own volume.
	var t3_y: float = t2_y + T2_H + 0.9
	for i in 6:
		terrain.create_box(center + rot * Vector3((float(i) - 2.5) * 2.24, t3_y + 0.85, 0.0), Vector3(0.75, 1.7, 1.6), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)
	for i in 5:
		var dx := (float(i) - 2.0) * 2.8
		terrain.create_box(center + rot * Vector3(dx, t3_y + 2.0, 0.0), Vector3(2.9, 0.6, 1.8), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.03))
		for side in [-1.0, 1.0]:
			terrain.create_box(center + rot * Vector3(dx, t3_y + 2.65, side * 0.75), Vector3(2.9, 0.7, 0.35), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02), false)

	return { "radius": 8.8, "top": t3_y + 3.0 }

static func _landmark_kinderdijk(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, _parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 26 — KINDERDIJK WINDMILLS: three brick mills standing on a dyke, each a
	tapering body under a dark thatched cap carrying a cross of sails. THREE of them
	rather than one is the point — a lone windmill is a farm, a ROW of them on a
	dyke is Kinderdijk — and the dyke is what stops the row reading as three
	separate buildings that happen to be near each other.

	THE SAIL CROSS IS A PLUS, NOT AN X, and that is a vocabulary limit stated
	honestly rather than a shape preference. create_box offers a yaw (about world Y)
	and a tilt about the box's own local X; neither can roll a box about the axis a
	mill's sails turn on, so a diagonal arm is not expressible at all. A vertical bar
	crossed by a horizontal one is an ordinary resting position for a real mill,
	costs two boxes instead of a dozen stepped ones, and reads as sails at 30 m —
	the torii's stepped kasagi, one building over. Upgrade path if it ever grates:
	four arms of 3-4 stepped boxes each, i.e. 12 boxes per mill and 36 per landmark.

	RADIUS ARITHMETIC (declared 8.2). The outer mill's horizontal sail is 4.6 long,
	centred at (5.2, 1.75): offset 5.49 plus a half-diagonal of
	0.5*sqrt(4.6^2 + 0.22^2) = 2.30 => 7.79. The dyke slab is 13.0 x 3.4 =>
	0.5*sqrt(13.0^2 + 3.4^2) = 6.72; a mill body is 3.0 square at x = 5.2 => 7.32.
	So 7.79 <= 8.2. MILL_STEP (5.2) also has to exceed the 4.6 sail span, or two
	neighbouring mills' sails interpenetrate — 0.6 m of daylight, deliberately.
	NO ACCENT.
	"""
	const MILLS := 3
	const MILL_STEP := 5.2
	const SAIL_SPAN := 4.6
	var yaw := rng.randf_range(0.0, TAU)
	var rot := Basis(Vector3.UP, yaw)

	terrain.create_box(center + rot * Vector3(0.0, 0.3, 0.0), Vector3(13.0, 0.6, 3.4), yaw,
			rng, block_batch, block_body, 0.0, _lm_shade(LM_GRANITE, rng, 0.04))

	var tallest := 0.6
	for i in MILLS:
		var mx := (float(i) - float(MILLS - 1) / 2.0) * MILL_STEP
		var brick := _lm_shade(LM_OCHRE, rng, 0.05)
		var y := 0.6
		# The tapering body: three shrinking boxes, the octagonal brick tower in the
		# house's vocabulary.
		for k in 3:
			var w: float = 3.0 - float(k) * 0.42
			terrain.create_box(center + rot * Vector3(mx, y + 0.95, 0.0), Vector3(w, 1.9, w), yaw,
					rng, block_batch, block_body, 0.0, _lm_shade(brick, rng, 0.03))
			y += 1.9
		# The cap: dark thatch, and wider than the body it sits on.
		terrain.create_box(center + rot * Vector3(mx, y + 0.75, 0.0), Vector3(2.5, 1.5, 2.5), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_ROOF, rng, 0.04))
		y += 1.5
		var hub_y: float = y - 0.6
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.35), Vector3(0.4, 0.4, 0.9), yaw,
				rng, block_batch, block_body, 0.0, _lm_shade(LM_BASALT, rng, 0.03), false)
		# The sails. Trim: a sail 7 m up is not a floor.
		var canvas := _lm_shade(LM_MARBLE, rng, 0.03)
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.75), Vector3(0.3, SAIL_SPAN, 0.22), yaw,
				rng, block_batch, block_body, 0.0, canvas, false)
		terrain.create_box(center + rot * Vector3(mx, hub_y, 1.75), Vector3(SAIL_SPAN, 0.3, 0.22), yaw,
				rng, block_batch, block_body, 0.0, canvas, false)
		tallest = maxf(tallest, hub_y + SAIL_SPAN / 2.0)

	return { "radius": 8.2, "top": tallest }

static func _landmark_pharos(terrain: Node3D, center: Vector3, rng: RandomNumberGenerator, parent_chunk: MeshInstance3D, block_batch: Array, block_body: StaticBody3D) -> Dictionary:
	"""
	Kind 27 — LIGHTHOUSE OF ALEXANDRIA: the Pharos, in the three stages every
	surviving description gives it — a wide square base, a narrower octagonal
	middle, a slim cylindrical top — standing on its island quay with a FIRE burning
	on the platform.

	THE STEPPING-DOWN-IN-THREES PROFILE IS THE RECOGNITION CUE, and the fire is what
	makes it a lighthouse rather than a chimney, which is why this is one of the very
	few builders that spends the one permitted accent. The Great Wall's beacon and
	Liberty's torch are the precedent: an accent goes where a real light belongs, and
	nowhere else.

	The octagon is two boxes crossed at 45 degrees — the same trick St Basil's centre
	shaft uses, and the closest a box vocabulary gets to eight sides.

	RADIUS ARITHMETIC (declared 6.6). The quay is the widest box, 8.4 square, so
	0.5*sqrt(2*8.4^2) = 5.94. The base stage is 5.4 square => 3.82, and the octagon
	is 3.4 square => 2.40. So 5.94 <= 6.6.
	THE one accent: the signal fire.
	"""
	var yaw := rng.randf_range(0.0, TAU)
	var stone := _lm_shade(LM_MARBLE, rng, 0.03)
	var trim := _lm_shade(LM_SANDSTONE, rng, 0.04)

	terrain.create_box(center + Vector3(0.0, 0.35, 0.0), Vector3(8.4, 0.7, 8.4), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(LM_GRANITE, rng, 0.04))
	var y := 0.7

	# STAGE 1 — the square base, battered (two boxes, the upper one narrower).
	for k in 2:
		var w: float = 5.4 - float(k) * 0.6
		terrain.create_box(center + Vector3(0.0, y + 1.8, 0.0), Vector3(w, 3.6, w), yaw, rng, block_batch, block_body,
				0.0, _lm_shade(stone, rng, 0.02))
		y += 3.6
	terrain.create_box(center + Vector3(0.0, y + 0.2, 0.0), Vector3(5.2, 0.4, 5.2), yaw, rng, block_batch, block_body,
			0.0, trim, false)
	y += 0.4

	# STAGE 2 — the octagon.
	for k in 2:
		terrain.create_box(center + Vector3(0.0, y + 2.6, 0.0), Vector3(3.4, 5.2, 3.4), yaw + float(k) * PI / 4.0,
				rng, block_batch, block_body, 0.0, _lm_shade(stone, rng, 0.02))
	y += 5.2
	terrain.create_box(center + Vector3(0.0, y + 0.2, 0.0), Vector3(3.6, 0.4, 3.6), yaw, rng, block_batch, block_body,
			0.0, trim, false)
	y += 0.4

	# STAGE 3 — the slim top and the lantern platform over it.
	terrain.create_box(center + Vector3(0.0, y + 1.7, 0.0), Vector3(2.2, 3.4, 2.2), yaw, rng, block_batch, block_body,
			0.0, _lm_shade(stone, rng, 0.02))
	y += 3.4
	terrain.create_box(center + Vector3(0.0, y + 0.25, 0.0), Vector3(3.0, 0.5, 3.0), yaw, rng, block_batch, block_body,
			0.0, trim)
	y += 0.5
	# Four corner posts round the fire, so the flame reads as held rather than as
	# floating over a slab.
	for i in 4:
		var a := yaw + PI / 4.0 + TAU * float(i) / 4.0
		terrain.create_box(center + Vector3(cos(a) * 1.15, y + 0.7, sin(a) * 1.15), Vector3(0.3, 1.4, 0.3), yaw,
				rng, block_batch, block_body, 0.0, trim, false)
	terrain._spawn_artifact_accent(parent_chunk, center + Vector3(0.0, y + 0.8, 0.0), Vector3(1.1, 1.2, 1.1),
			yaw, 0.0, terrain._get_camp_ember_material())

	return { "radius": 6.6, "top": y + 1.6 }
