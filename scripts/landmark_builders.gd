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
const LM_MARBLE := Color(0.93, 0.91, 0.87)       # Taj Mahal marble

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
]

# ----------------------------------------------------------------------------
# THE EIGHT BUILDERS
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
