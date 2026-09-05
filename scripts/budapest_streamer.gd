class_name BudapestStreamer
extends RefCounted
## ============================================================================
## BUDAPEST, STREAMED THROUGH ORDINARY CHUNKS — the builder half
## ============================================================================
## Lifted out of `endless_terrain.gd` whole by bd `godot-test1-ftn.8`, in the
## idiom the six extractions before it settled (`terrain_props`,
## `terrain_structures`, `terrain_features`, `terrain_biomes`,
## `terrain_predators`, `coin_road`): a `class_name`d library of STATIC functions
## that RECEIVES the terrain as its first argument and calls
## `terrain.create_box` / `terrain.chunk_to_world` / `terrain._settle_coin_y`
## back through the reference. `extends RefCounted` and everything `static`: this
## is a namespace, not a node.
##
## THE CITY IS AUTHORED (`scripts/budapest_plan.gd`) AND STREAMED (here). Those
## two words are still the whole design, and this move changes neither: the plan
## is a `const` a designer typed, and every cell of it is emitted through the
## chunk's ONE `block_batch` and its single `BlockCollision`, chunk-parented and
## therefore freed by chunk unloading like any prop. The 2.2 x 2.2 km rect is
## 2,025 chunk cells against the web build's 49-chunk residency, which is why the
## city is NOT the tower's second lifetime exception.
##
## ----------------------------------------------------------------------------
## WHAT DID NOT COME WITH IT, AND WHY EACH ONE STAYED
## ----------------------------------------------------------------------------
## * **`in_budapest()`** — the public membership test, the way `tower_excludes()`
##   is the tower's. Seven spawners in the world engine ask it to decide their own
##   policy inside the rect, and it delegates to `BudapestPlan.contains()` so the
##   rect is never written down twice. It is the terrain's public API, not a
##   builder.
## * **`_settle_coin_y` / `_block_overlaps` / `_point_over_block`** — the FIELD's
##   coin perch-or-skip rule, shared by road coins, artifact reward coins and the
##   city's own deck line. It is one function so the spawners cannot drift apart;
##   moving it into the city would make the city the owner of a field rule.
## * **The `Biome` enum and `biome_at` / `is_river_at`** — the CPU half of the
##   parity contract, and an enum a `const` Dictionary in another file cannot name
##   (`terrain.Biome.X` resolves on an INSTANCE, which no const initialiser has).
## * **`_apply_biome_shader_params`'s PUSH.** The two array-uniform BUILDERS moved
##   (`_city_river_segments` / `_city_dry_rects`, at the bottom of this file); the
##   `set_shader_parameter` calls stayed with the other twenty uniforms they sit
##   among. Builder here, push there — the same split the bead names.
## * **`_approach_coin_line_cache` / `_approach_coin_east_end_cache`** — seeded
##   memo state beside the station cache, which is `coin_road.gd`'s own precedent
##   (bd ftn.7): the FUNCTIONS move, the seeded STATE stays with the seed write.
##   **Only the first is actually cleared**, and that is a PRE-EXISTING gap this
##   extraction neither introduces nor widens — `_drop_seeded_memos()` is byte
##   for byte master's, and `_approach_coin_east_end_cache` was already outside
##   it. The east end walks from `_road_station(_road_terminal_k())`, so it IS
##   seed-derived and a re-seed leaves it stale; that is a bug and therefore its
##   own bead, not a line of a mechanical move (the epic: "a bug found on the way
##   is a separate bead").
## * **`CITY_SHADER_SEG_MAX` / `CITY_SHADER_DRY_MAX`** — read by the push that
##   stayed as well as by the builders that left, so they stay where both can
##   reach them; and the ROOF / PLASTER / `PROP_CRATE` colours, which belong to
##   the props banner and are merely borrowed here.
##
## ----------------------------------------------------------------------------
## THE THREE RULES THIS FILE IS MEASURED ON ARE UNCHANGED
## ----------------------------------------------------------------------------
## A landmark bigger than a chunk is SLICED, not re-homed (the centre rule, plus
## `ChunkBatch.split_city_boxes_on_chunk_grid` for the oversized axis-aligned
## boxes); a bridge is TWO FILES joined at `BudapestPlan.BRIDGES`; and a city
## chunk builds exactly ONE `MultiMeshInstance3D` and CASTS NO SHADOW (owner
## ruling 2026-09-02 — 2,100+ tall casters cost 19 ms a frame in the shadow pass
## alone). `budapest_selfcheck` and `budapest_city_selfcheck` assert all three,
## and this move touched none of them.

# ----------------------------------------------------------------------------
# BUDAPEST — THE CITY STREAMER (bead godot-test1-8gw.3)
# ----------------------------------------------------------------------------
##
## What spawn_city_in_chunk needs that BudapestPlan does not carry. The plan is
## the DESIGN — where the hills are, how wide the avenue is, which liberties were
## taken with the map — and a designer edits it. These are the MATERIALS: how
## thick a slab is and what colour the stone is, which is this file's business,
## beside CITY_PLASTER_* and every other palette and thickness in it.

## The seed of the city streamer's PRIVATE RandomNumberGenerator, and it is a
## CONSTANT for two reasons that both matter.
##
## PRIVATE, because create_box draws four numbers per box for its colour ramp and
## one extra draw taken from the chunk's shared stream slides every crocodile in
## the world (see the determinism block in SECTION 1). The city is authored, so
## it has nothing to seed from anyway — this stream exists only to feed those
## discarded draws.
##
## THE CITY BUILDERS, REACHED AS A SCRIPT OBJECT AND NOT AS A CLASS (bd
## `godot-test1-ftn.17`). A `SLOTS` row names its builder with a METHOD-NAME
## STRING, so the call has to go through `.call(name, ...)` — and
## `CityBuilders.call(...)` on the `class_name` is a PARSE ERROR, exactly as
## `endless_terrain.gd` documents beside its own `_landmark_builders` preload.
## A `const` rather than that file's `var` because every function here is static
## and there is no instance to hang one on; `budapest_selfcheck` and
## `budapest_city_selfcheck` dispatch through THIS name, so the preload has one
## home and cannot drift from the one the game uses.
const CITY_BUILDERS: GDScript = preload("res://scripts/city_builders.gd")

## CONSTANT rather than per-chunk, because every box the streamer places passes
## an explicit color_override and a plateau whose slices each drew their own
## colour would be a different grey on either side of every chunk seam. One seed,
## one hill.
const CITY_STREAM_SEED: int = 0x8_6D4_9E51

## The plateau massifs' stone, and their ramps' — ONE colour for both, because
## they are the same hill. Deliberately duller and greyer than CITY_PLASTER_*:
## Castle Hill has to read as the rock the city stands ON rather than as another
## building on it.
const CITY_HILL_STONE := Color(0.47, 0.45, 0.41)

## A plateau ramp's slab thickness, metres. Thick enough to read as a viaduct
## from the side, thin enough that the head of the ramp never pokes up through
## the plateau's lid.
const CITY_RAMP_THICKNESS: float = 1.0

## A BRIDGE DECK's slab thickness, metres. Thicker than a ramp because it is read
## from BELOW as well — you wade under it — and because the Margaret Bridge's
## piers top out at y = 11 and its arches spring from there, so a 1.2 m slab hung
## off BudapestPlan.BRIDGE_DECK_TOP lands its underside exactly on them. The
## approach ramps stay CITY_RAMP_THICKNESS: they meet the deck at its TOP surface,
## which is the only place a step could appear.
const CITY_BRIDGE_DECK_THICKNESS: float = 1.2

## The avenue's pavement slab: 4 cm, straddling y = 0, and collide = FALSE.
##
## The avenue is a READ — the thing that says "this way into the city" — and not
## a corridor. The ground under it is already flat and walkable, so a COLLIDING
## lip would buy nothing and cost 900 m of kerb for a CharacterBody3D to catch its
## toe on. Same reasoning as the forest canopies' collide = false: pure decoration
## pays for its pixels and not for a collision shape.
##
## WHICH IS EXACTLY WHY IT MUST BE THIN AND CENTRED ON THE GROUND. Nothing stands
## ON this slab — the player walks the y = 0 plane straight through it, capsule
## bottom at y = 0 and the model's feet with it — so every centimetre of pavement
## above y = 0 is a centimetre of shin rendered inside opaque stone, for the whole
## 750 m of the one authored route out of the gate. A kerb-height 15 cm slab sunk
## its feet; 4 cm straddling zero leaves 2 cm proud (enough to read as pavement
## and to stay off the ground plane's own depth) and 2 cm buried out of sight.
const CITY_AVENUE_THICKNESS: float = 0.04
const CITY_AVENUE_STONE := Color(0.62, 0.60, 0.56)

## THE GATE DISTRICT'S STREET DRESSING (DEC-11) — where the jb7 city prop
## builders are called, and how big.
##
## The spots are DERIVED from DISTRICT_HOUSES rather than typed into a second
## table: one prop in each gap between neighbouring houses, alternating sides,
## cycling _prop_crate_stack / _prop_garden_wall / _prop_paving_stack. Seven
## props, no new plan data, and the dressing follows the houses if a designer
## moves them.
##
## Z IS THE LOAD-BEARING NUMBER. 14 m off the centreline puts the widest prop's
## own footprint (2.0 * PROP_RADIUS_FACTOR = 1.42) at 12.6 m, comfortably clear
## of the avenue's 8 m half-width — the corridor out of the gate has to stay
## walkable, and a crate stack standing in it is exactly the failure the .3
## acceptance walk looks for.
const CITY_DISTRICT_PROP_Z: float = 14.0
const CITY_DISTRICT_PROP_SIZE: float = 2.0

## ---------------------------------------------------------------------------
## THE CITY BLOCKS (bead godot-test1-8gw.9) — how a street wall is DRAWN
## ---------------------------------------------------------------------------
##
## The LAYOUT is BudapestPlan's (which cell, which wing, how deep, how many
## storeys); everything below is the PALETTE AND THE THICKNESSES, which is the
## same division of labour DISTRICT_HOUSES already runs under — the plan carries
## shade FACTORS and this file carries the colours they lerp between.
##
## ONE FACADE BOX PER BUILDING, NEVER ONE BOX PER WINDOW. A 46 m block side is
## two segments, each ONE colliding hull, and the articulation that makes it read
## as a street is VERTEX-COLOURED BANDS lying against it: a ground-floor
## shopfront, a balcony course, a roof cornice and one doorway. Seven boxes buy a
## whole side of a Budapest block; a window grid would buy a tenth of one and
## blow CITY_CHUNK_BOX_BUDGET on the first cell.
##
## THE STREAM IS PER-CELL AND FIXED-SALT — the tower furniture precedent
## (`TowerDressing.plan_dressing`'s FIXED salt, never run_seed). Budapest is authored, so the
## facade a player photographs has to be the same facade every run and for every
## peer; and a cell's stream must not depend on which chunk is asking, because a
## block straddles up to four of them. Both fall out of seeding one RNG off
## (cell.x, cell.y, CITY_BLOCK_SALT) and drawing every parameter ANYTHING READS
## before emitting anything — see _build_city_block for why that qualifier is
## exact, and why create_box's own ramp draws after it are padding that may
## legitimately differ between two chunks slicing one cell.
const CITY_BLOCK_SALT: int = 0x8_DA9E_571

## A storey, in metres. 4.2 is a tall Pest piano-nobile floor rather than a
## modern 3 m one, which is what makes a 5-storey block read as 21 m of eclectic
## facade instead of a suburban office.
const CITY_STOREY_HEIGHT: float = 4.2

## The bands. Each is a thin, NON-COLLIDING box lying against the hull and
## standing `*_PROUD` metres off its faces on the cross axis — the hull is the
## only thing with a collision shape, so a band can never be something to snag on.
## EVERY PROUD IS POSITIVE, and it has to be: the batch is opaque boxes with no
## cutouts, so a band set back INSIDE the hull is a band nobody can see — see
## CITY_WINDOW_PROUD, which is where that was learned the expensive way.
const CITY_SHOPFRONT_HEIGHT: float = 2.9    # ground floor, one storey of glass
const CITY_SHOPFRONT_PROUD: float = 0.16
const CITY_AWNING_THICKNESS: float = 0.22
const CITY_AWNING_PROUD: float = 0.62       # oversails the shopfront it shades
const CITY_BALCONY_THICKNESS: float = 0.26
const CITY_BALCONY_PROUD: float = 0.52
const CITY_CORNICE_THICKNESS: float = 0.55
const CITY_CORNICE_PROUD: float = 0.46
const CITY_DOOR_WIDTH: float = 1.5
const CITY_DOOR_HEIGHT: float = 2.4
const CITY_DOOR_PROUD: float = 0.10

## ONE WINDOW ROW PER STOREY, and it is a ROW and not a window.
##
## The owner asked for Google-Street-View Budapest and the first cut shipped
## blank slabs: a 21 m facade with a single cornice line on it reads as a wall,
## not as a building. What makes a real facade legible at 30 m is the HORIZONTAL
## RHYTHM of its window courses, so each storey above the shopfront gets one
## recessed dark band the full width of the facade. That is ONE box per storey
## against the ~30 a window grid would cost, and it is the same trade the
## shopfront and cornice already make.
##
## THE TWO-TONE IS FREE: the band's glass colour alternates by storey parity
## (CITY_WINDOW_DARK / CITY_WINDOW_LIT), so a five-storey facade reads as five
## distinct courses rather than one striped texture, and it costs no extra box.
##
## IT STANDS PROUD, AND IT HAS TO. The first cut RECESSED these bands into the
## wall, which is what a real window reveal does and which is invisible here: the
## batch is opaque boxes with no cutouts, so a band inside the hull is a band you
## cannot see, and all it actually produced was z-fighting where the two surfaces
## nearly met. 6 cm proud is flush to the eye at street distance and is the only
## thing that makes the course exist at all.
const CITY_WINDOW_HEIGHT: float = 1.60
const CITY_WINDOW_PROUD: float = 0.06
const CITY_WINDOW_SILL: float = 1.15        # sill height above the storey floor

## ...AND IT IS PULLED IN AT ITS ENDS, which is the OTHER half of the same lesson
## (bead godot-test1-8gw.19). A proud band was still drawn to the hull's exact
## length, so while its street face stood 6 cm clear its two END faces landed on
## the hull's end planes at a separation of EXACTLY zero — measured, 20.8 m² of
## shared face per pair, 37 hull/window pairs in a single chunk. Zero fights at
## any depth precision on any renderer, which is why raising the camera's near
## plane (bead 8gw.17) did nothing for it; and coplanar QUADS fight along their
## shared diagonal, which is why the owner saw "instead of rectangular i see
## triangle for a moment" rather than two colours swapping.
##
## It was visible on most of every other street wall, not in a corner: block_wing
## spans the north/south wings the full width of the ring and insets the side
## wings by BLOCK_WING_DEPTH, so a ±X street wall is end face, front face, end
## face — 26 of 43.6 m fighting — while the ±Z walls of the same block are clean,
## and vice versa.
##
## 4 cm, applied to the WHOLE building rect before _city_chunk_slice so that
## neighbouring chunks still cut one rect and still meet flush. It changes no box
## count, costs no RNG draw, and is invisible at street scale.
const CITY_BAND_END_INSET: float = 0.04

## The block palette. Walls reuse the CITY_PLASTER_A/B pair the gate district's
## houses lerp between, so Budapest is ONE city and not two; the rest is new
## because a 5-storey facade has parts a 2.5 m cottage does not.
const CITY_SHOPFRONT_GLASS := Color(0.20, 0.22, 0.25)   # dark glazing + signage
const CITY_BALCONY_IRON := Color(0.24, 0.24, 0.26)      # wrought-iron course
const CITY_DOOR_WOOD := Color(0.30, 0.20, 0.14)         # the carriage gateway
const CITY_WINDOW_DARK := Color(0.20, 0.23, 0.27)       # a shaded course
const CITY_WINDOW_LIT := Color(0.29, 0.33, 0.38)        # ...and a sunlit one
const CITY_AWNING_A := Color(0.60, 0.25, 0.22)          # shop canvas, red
const CITY_AWNING_B := Color(0.26, 0.42, 0.33)          # ...and green

## THE FACADE HUES, one array per bank of the river, and a building picks ONE.
##
## A block whose eight buildings are eight lerps along a single cream-to-grey
## ramp is a block of one building repeated. Pest is ECLECTIC — the real thing is
## cream beside ochre beside grey-green beside rose — and Buda under the castle
## is whitewash, ochre and brick red. The per-building tint below still runs, but
## it now varies a chosen hue instead of choosing the hue.
const CITY_FACADE_PEST: Array[Color] = [
	Color(0.90, 0.86, 0.75),   # cream
	Color(0.84, 0.70, 0.44),   # ochre
	Color(0.69, 0.73, 0.65),   # grey-green
	Color(0.84, 0.69, 0.67),   # rose
	Color(0.77, 0.75, 0.71),   # stone grey
]
const CITY_FACADE_BUDA: Array[Color] = [
	Color(0.93, 0.92, 0.87),   # whitewash
	Color(0.86, 0.73, 0.49),   # ochre
	Color(0.73, 0.44, 0.35),   # brick red
]

## How far a building's own draw may shade its chosen hue toward the weathered
## render, 0..1. Small: this is grime and sun, not a second colour choice.
const CITY_FACADE_TINT_MAX: float = 0.30

## The share of PEST buildings that carry a balcony course. Balconies everywhere
## are a texture; balconies on two facades of a block are a detail the eye
## lands on. Buda's 2-3 storey houses get none at all.
const CITY_BALCONY_CHANCE: float = 0.42

## How far a block's own facade stream may push a segment off the cell's base
## storey count, in storeys. +-1 is a stepped roofline; more and the block stops
## reading as one period.
const CITY_BLOCK_STOREY_JITTER: int = 1

## THE CITY'S PER-CHUNK CEILINGS — what a Budapest chunk is allowed to cost.
##
## A chunk in Pest is an ordinary chunk: ONE MultiMesh, ONE collision body, built
## in the same one-chunk-per-frame drain as a chunk of cactus. These three numbers
## are what says so, and `budapest_selfcheck` check 4 measures every chunk in the
## 2.2 km rect against them and prints the worst one it found beside each ceiling.
##
## MEASURED over the whole rect (2025 chunks, 2026-09-02, with ALL 22 landmark
## builders placed, the four bridge decks built and — since bead
## godot-test1-8gw.9 — every block of the street grid FILLED): worst 145 boxes,
## worst 15 collision shapes, worst 1.1 ms, over 96,770 boxes and 1,631 chunks
## with stone. The ms budget is deliberately loose because it is wall-clock on
## whatever machine CI happens to be — it is a runaway detector, not a benchmark.
##
## THE BOX BUDGET MOVED 120 -> 200 WHEN THE BLOCKS LANDED, and that is the one
## raise this file has taken. The history is worth keeping because it says what
## each number measures:
##
##   wave B, seven slots still reservations    69 boxes   15 shapes   7.4 ms
##   all 22 landmarks + the four decks         92 boxes   15 shapes   3.0 ms
##   ...and every block filled (bead .9)      145 boxes   15 shapes   1.1 ms
##
## The worst chunk is STILL a Parliament slice; the densest all-block chunk is
## 119. Collision is unmoved at 15 because a building's only colliding box is its
## hull — every band is decoration. Bead .9's own note said to raise this budget
## and the web residency proof TOGETHER if a dense chunk needed it, and this is
## that raise: see CITY_RESIDENCY_BOX_BUDGET in budapest_selfcheck.gd, which went
## 3000 -> 6000 against a measured 4,510 in the same pass.
##
## The box number is still the one to watch: a landmark builder that stopped
## being a pure function of (centre, rng) would emit its whole self into every
## chunk its disc touches instead of its own slice, and THAT is what this catches
## — 268 boxes of Parliament in one 50 m square instead of the dozen that stand
## in it.
const CITY_CHUNK_BOX_BUDGET: int = 200
const CITY_CHUNK_SHAPE_BUDGET: int = 40
const CITY_CHUNK_MS_BUDGET: float = 12.0


# ============================================================================
# SECTION — BUDAPEST, STREAMED THROUGH ORDINARY CHUNKS
# ============================================================================
#
# The city is AUTHORED (scripts/budapest_plan.gd) and STREAMED (here). Those two
# words are the whole design: every coordinate is a constant a designer typed,
# and every box those constants describe is emitted by the same create_chunk pass
# that emits a cactus — chunk-parented, into the chunk's ONE MultiMesh batch and
# ONE collision body, freed when the chunk unloads.
#
# THAT IS WHY THE CITY IS NOT A SECOND TOWER. The HQ is manager-parented and
# CLAUDE.md says it is the ONE exception and must stay one; a 2.2 km city held
# outside the chunk dictionary would be an exception 4,000 times its size, and
# the 49-chunk web residency ceiling is exactly what chunk streaming buys. So a
# thing 800 m long is not built by one chunk — it is SLICED, and every chunk
# builds the part of it that stands in its own square.
#
# NOTHING HERE DRAWS FROM THE SHARED CHUNK STREAM. create_box spends four random
# numbers per box on its colour ramp, and one extra draw taken from the chunk's
# RNG moves every block, crocodile and coin downstream of it. The streamer
# carries its own RandomNumberGenerator at a fixed seed (CITY_STREAM_SEED) whose
# draws are discarded padding, because every box passes a colour override.


static func city_chunk(terrain: Node3D, chunk_center: Vector3) -> bool:
	"""
	Does this chunk's SQUARE meet Budapest — i.e. is it a chunk that can build
	city stone?

	@param chunk_center: This chunk's centre, from chunk_to_world().

	ONE PREDICATE, TWO READERS, AND THAT IS THE WHOLE REASON IT EXISTS.
	spawn_city_in_chunk's cheap reject asks it to decide whether to build, and
	create_chunk asks it to decide whether the chunk's batch casts a shadow. Those
	two answers MUST be the same answer: the owner's no-shadow ruling is about the
	city, so a chunk that builds a slice of Budapest must not cast, and a chunk
	that builds none of it must.

	IT IS THE SQUARE, NOT THE CENTRE, and that distinction is a real bug that was
	shipped once. A chunk on the rect's edge can straddle the boundary — its
	square meets the city and it builds a sliced facade, while its CENTRE sits
	outside. Asked about its centre it kept its shadows and cast them off city
	stone; the mirror case (centre inside, a sliver of ordinary world outside)
	silently stripped shadows from that sliver's cactus. Both are one ring of
	chunks all the way round a 2.2 km rect. budapest_selfcheck check 4 now asserts
	the two readers agree, and names the edge chunks it found.
	"""
	return _city_chunk_slice(terrain, chunk_center, BudapestPlan.rect()).has_area()


static func _city_chunk_slice(terrain: Node3D, chunk_center: Vector3, area: Rect2) -> Rect2:
	"""
	This chunk's share of an authored city rect, in WORLD XZ.

	@param chunk_center: This chunk's centre, from chunk_to_world().
	@param area: The authored rect (a plateau, a ramp, the avenue), world XZ.
	@return: The intersection, or a zero-area Rect2 when the two do not meet —
	         test it with has_area() before building anything from it.

	ONE HELPER FOR EVERY SLICED RECT, and that is the point rather than a
	convenience. "Neighbouring chunks' slices meet flush" is the claim a plateau
	and a ramp both rest on, and routing both through the same intersection makes
	it true BY CONSTRUCTION instead of by review: adjacent chunk squares share an
	edge exactly, so their intersections with one rect share that edge exactly and
	the two boxes touch with no gap and no overlap.

	A slice that is exactly a line (a rect whose edge lies on a chunk seam) has no
	area, so has_area() drops it — the degenerate box is never built, and the
	chunk on the other side of the seam owns the whole thing.
	"""
	var half: float = terrain.chunk_size / 2.0
	var square: Rect2 = Rect2(chunk_center.x - half, chunk_center.z - half, terrain.chunk_size, terrain.chunk_size)
	return square.intersection(area)


static func _city_ramp_slice(terrain: Node3D, chunk_center: Vector3, ramp: Rect2, rise: float, dir: float,
		thickness: float, rng: RandomNumberGenerator, block_batch: Array,
		block_body: StaticBody3D, stone: Color) -> void:
	"""
	This chunk's slice of ONE tilted ramp, on the X axis. The city has two kinds
	and they are the same slab: a plateau's climb onto its lid, and a bridge's
	approach onto its deck.

	@param chunk_center: This chunk's centre, from chunk_to_world().
	@param ramp: The ramp's footprint in world XZ — `size.x` is the RUN, `size.y`
	             the width.
	@param rise: How far it climbs, in metres. The foot is at y = 0.
	@param dir: +1 if it climbs eastward (foot on the west end), -1 if westward.
	@param thickness: The slab's own thickness.

	A TILTED BOX, NEVER STEPS. CharacterBody3D cannot climb a step at all, and the
	HQ's rule — no traversal may demand a jump-height — is the same rule outdoors.
	The derivation is _city_cable's, read it there: create_box composes
	Basis(UP, yaw) * Basis(RIGHT, tilt), so a box long in LOCAL Z is tipped by
	`tilt` and then swung to its heading by `yaw`, and local +Z lands on
	(cos(tilt)*sin(yaw), -sin(tilt), cos(tilt)*cos(yaw)). A ramp on +X is therefore
	yaw = +PI/2 with tilt = -atan2(rise, run); a box long in local X could not be
	sloped at all, and yaw = -PI/2 mirrors the whole thing for a -X climb.

	NO FOOTPRINT, deliberately: a ramp is the one piece of city geometry you are
	MEANT to walk up, and an `obstacles` entry is a keep-out claim that would push
	crocodiles off it and drop every coin that crossed it.
	"""
	var slice := _city_chunk_slice(terrain, chunk_center, ramp)
	if not slice.has_area():
		return
	var run: float = ramp.size.x
	var mid := slice.get_center()
	# How far up the climb this slice's centre sits, 0 at the foot to 1 at the
	# head — measured from the rect's west edge and flipped for a -X ramp, so
	# `dir` is honoured rather than assumed.
	var climbed := clampf((mid.x - ramp.position.x) / run, 0.0, 1.0)
	if dir < 0.0:
		climbed = 1.0 - climbed
	# The slice is longer than its X width by exactly the slope's hypotenuse
	# ratio, which is what makes two neighbouring slices meet flush on the same
	# plane rather than leaving a lip at the seam.
	var slope_len := slice.size.x * sqrt(run * run + rise * rise) / run
	terrain.create_box(
			Vector3(mid.x - chunk_center.x,
					climbed * rise - thickness * 0.5,
					mid.y - chunk_center.z),
			Vector3(slice.size.y, thickness, slope_len),
			PI * 0.5 * dir, rng, block_batch, block_body, -atan2(rise, run), stone)


static func spawn_city_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's slice of Budapest (bead godot-test1-8gw.3).

	@param chunk_pos: Chunk coordinates being built.
	@param parent_chunk: The chunk mesh, for the parts of the city that are nodes
	                     rather than boxes (the landmark accents; nothing here
	                     needs it yet).
	@param obstacles: Out-param; the plateau massifs append their footprints here,
	                  so the crocodile spawner and the coin perch rule see them.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	ORDERING REQUIREMENT, the same one the artifact / camp / landmark / chest
	family carries: this runs AFTER every spawner that fills `obstacles` and
	BEFORE _build_block_multimesh and the block_body attach, so the city's stone
	joins the chunk's one draw call and its one collision body — and BEFORE the
	coin spawners, so the approach line's perch-or-skip rule can see a plateau.

	WHAT IT BUILDS, in this order:
	  1. the PLATEAU slice — one box, the chunk square meeting the hill's rect,
	     y = 0 to `top`, plus one footprint at climbable: false;
	  2. the RAMP slice — one TILTED box, the only way onto that lid;
	  3. the LANDMARK slices — _spawn_city_landmarks_in_chunk, this chunk's share
	     of every authored slot whose disc reaches into its square;
	  5. the AVENUE slice — a thin, non-colliding pavement slab out of the gate;
	  6. the four BRIDGE DECKS and their ramped approaches — bead .4's, and the
	     one step with a public entry point of its own so the self-check can walk
	     a deck without twenty landmark builders in the way.
	4 is the gate district and is its own task; the Danube's crocodiles are a
	spawner of their own, not city stone. The numbering is DEC-10's, kept as it
	is so the gap is visibly a slot rather than an omission.
	"""
	var chunk_center: Vector3 = terrain.chunk_to_world(chunk_pos)
	# Cheap rect reject: every chunk in the world that is not in the city pays one
	# intersection and nothing else.
	if not city_chunk(terrain, chunk_center):
		return

	# The private stream — see CITY_STREAM_SEED for why it is private and why it
	# is constant. Its draws are colour-ramp padding; every box below overrides.
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for i in range(BudapestPlan.PLATEAUS.size()):
		var row: Dictionary = BudapestPlan.PLATEAUS[i]
		var top: float = row["top"]

		# ---- 1. THE PLATEAU -------------------------------------------------
		# A hill in this game is a MASSIF WITH A WALKABLE LID, not raised terrain:
		# the ground is one flat plane at y = 0 and every coin height, gravity
		# settle and block base in the world depends on that. So the hill is one
		# box per chunk with cliffs on every side, and the footprint is
		# climbable: false — the mountain-massif convention, which is what tells
		# the coin road to SKIP a coin over it rather than perch one on a cliff.
		var slice := _city_chunk_slice(terrain, chunk_center, row["rect"])
		if slice.has_area():
			var mid := slice.get_center()
			var local := Vector3(mid.x - chunk_center.x, top * 0.5, mid.y - chunk_center.z)
			terrain.create_box(local, Vector3(slice.size.x, top, slice.size.y), 0.0,
					rng, block_batch, block_body, 0.0, CITY_HILL_STONE)
			obstacles.append({
				"pos": Vector3(local.x, 0.0, local.z),
				"radius": slice.size.length() * 0.5,   # the slice's circumscribing disc
				"top": top,
				"climbable": false,
			})

		# ---- 2. THE RAMP ----------------------------------------------------
		# One tilted slab, the only way onto the lid — see _city_ramp_slice, which
		# the bridges' approaches share.
		_city_ramp_slice(terrain, chunk_center, row["ramp"], top,
				signf(float(row["ramp_dir"])), CITY_RAMP_THICKNESS,
				rng, block_batch, block_body, CITY_HILL_STONE)

	# ---- 3. THE LANDMARK SLICES ---------------------------------------------
	# Its own function because it is the bead's keystone decision and wants the
	# whole docstring to itself. It gets the chunk centre rather than recomputing
	# it, and its own per-slot RNG rather than this one.
	_spawn_city_landmarks_in_chunk(terrain, chunk_center, parent_chunk, obstacles, block_batch, block_body)

	# ---- 4. THE GATE DISTRICT ------------------------------------------------
	_spawn_gate_district_in_chunk(terrain, chunk_center, obstacles, block_batch, block_body)

	# ---- 4b. THE CITY BLOCKS (bead godot-test1-8gw.9) ------------------------
	# Every block of the street grid the plan lays down, filled with a continuous
	# street wall around a hollow courtyard. It runs AFTER the landmarks and the
	# gate district for the same reason those run after the props: `obstacles` is
	# read to decide nothing here (a block is authored, not rolled), but the
	# ORDER the footprints land in is what every later spawner's candidate loop
	# sees, and the authored city has first claim on its own ground.
	_spawn_city_blocks_in_chunk(terrain, chunk_center, obstacles, block_batch, block_body)

	# ---- 5. THE AVENUE ------------------------------------------------------
	# The one street this bead draws: 16 m of pavement running east out of the
	# gate along z = 0, to the Danube's west bank. Bead godot-test1-8gw.9 owns the
	# rest of the grid; this file owns STREET_PITCH as a parameter and nothing more.
	#
	# The east end is _approach_coin_east_end() — the SAME west bank the approach
	# coin line stops at, asked once and answered from the river's own polyline, so
	# the pavement and the coins on it cannot end in different places.
	var avenue := Rect2(
			BudapestPlan.GATE.x,
			BudapestPlan.GATE.z - BudapestPlan.AVENUE_HALF_WIDTH,
			_approach_coin_east_end(terrain) - BudapestPlan.GATE.x,
			BudapestPlan.AVENUE_HALF_WIDTH * 2.0)
	var av := _city_chunk_slice(terrain, chunk_center, avenue)
	if av.has_area():
		var mid_a := av.get_center()
		terrain.create_box(
				Vector3(mid_a.x - chunk_center.x, 0.0, mid_a.y - chunk_center.z),
				Vector3(av.size.x, CITY_AVENUE_THICKNESS, av.size.y), 0.0,
				rng, block_batch, block_body, 0.0, CITY_AVENUE_STONE, false)

	# ---- 6. THE FOUR BRIDGE DECKS -------------------------------------------
	spawn_city_bridges_in_chunk(terrain, chunk_center, block_batch, block_body)


static func spawn_city_bridges_in_chunk(terrain: Node3D, chunk_center: Vector3, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Build this chunk's slice of the four Danube bridges' DECKS (bead
	godot-test1-8gw.4).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	PUBLIC, for the same reason ChunkBatch.split_city_boxes_on_chunk_grid is:
	budapest_selfcheck check 14 walks a bridge's chunks and measures the surface
	it can actually stand on, and it can only do that if the deck's boxes arrive
	on their own instead of mixed in with twenty landmark builders' piers and
	towers.

	WHAT IT BUILDS, per bridge, all of it sliced by _city_chunk_slice so
	neighbouring chunks meet flush: a flat colliding slab hung under
	BudapestPlan.BRIDGE_DECK_TOP across the middle, and one tilted ramp at each end
	climbing to it from y = 0. The ramp shares the plateaus' _city_ramp_slice, so
	"no traversal may demand a jump-height" is one piece of arithmetic in this file
	and not two.

	WHAT IT DOES NOT BUILD is the bridge: the towers, chains, trusses, cutwaters and
	lions belong to landmark_builders.gd's `_city_*_bridge` rows, which stand on the
	SLOTS entry of the same id. The deck is placed off the DRY_RECTS row the band is
	already punched out by, and check 14 asserts the two agree on where the bridge
	is — the ornament hangs its chains at exactly BRIDGE_DECK_TOP.

	ITS OWN PRIVATE STREAM, the gate district's precedent: create_box draws four
	numbers per box for a colour ramp this feature overrides anyway, and a draw
	taken from a stream somebody else reads slides every crocodile in the world.

	NO `obstacles` FOOTPRINT, deliberately, and for the ramp's reason one span
	along: a deck is MEANT to be walked. Nothing downstream wants one either —
	inside the rect the coin line stops at the west bank and the only predator is
	spawn_danube_crocodiles_in_chunk, which keeps clear of a deck through
	DANUBE_CROC_DECK_MARGIN off the same rect rather than through this list.

	# ponytail: THE STRIP UNDER A DECK IS DRY TOO, and that is DRY_RECTS being
	# XZ-only rather than an oversight — the same trade the plan's SECTION 3 makes
	# for Margaret Island. A player who ignores the ramps can walk the river bed
	# beneath a bridge without wading. Closing it means a Y-aware is_river_at(),
	# which every predator and the ground shader read per frame; the cheap half-fix
	# (a solid abutment wedge at each end) is worth doing the day somebody notices.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for row_v: Variant in BudapestPlan.BRIDGES:
		var row: Dictionary = row_v
		var deck: Rect2 = BudapestPlan.bridge_deck(row)
		# Cheap reject: a chunk nowhere near this bridge pays one intersection.
		if not _city_chunk_slice(terrain, chunk_center, deck).has_area():
			continue

		# The level span, hung UNDER its walking height so the ramps meet its top.
		var flat := _city_chunk_slice(terrain, chunk_center, BudapestPlan.bridge_flat(row))
		if flat.has_area():
			var mid := flat.get_center()
			terrain.create_box(
					Vector3(mid.x - chunk_center.x,
							BudapestPlan.BRIDGE_DECK_TOP - CITY_BRIDGE_DECK_THICKNESS * 0.5,
							mid.y - chunk_center.z),
					Vector3(flat.size.x, CITY_BRIDGE_DECK_THICKNESS, flat.size.y),
					0.0, rng, block_batch, block_body, 0.0, CITY_AVENUE_STONE)

		# ...and the two approaches. The east one climbs WESTWARD (dir -1), so its
		# foot is on the east bank — the same slab mirrored, not a second case.
		for east in [false, true]:
			_city_ramp_slice(terrain, chunk_center, BudapestPlan.bridge_ramp(row, east),
					BudapestPlan.BRIDGE_DECK_TOP, -1.0 if east else 1.0,
					CITY_RAMP_THICKNESS, rng, block_batch, block_body,
					CITY_AVENUE_STONE)


static func _spawn_city_landmarks_in_chunk(terrain: Node3D, chunk_center: Vector3, parent_chunk: MeshInstance3D, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's SHARE of every authored Budapest landmark whose disc reaches
	into its square (bead godot-test1-8gw.3).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param parent_chunk: The real chunk mesh — the accent nodes' final home, but
	                     only for the chunk holding a slot's CENTRE (see below).
	@param obstacles: Out-param; one round footprint per overlapping slot.
	@param block_batch: Out-param; the kept boxes join the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	================= THE DECISION, AND THE TWO IT BEAT =================

	The Parliament is 268 m long and Buda Castle's disc is 156 m across, while a
	chunk is 50 m and the web build keeps 49 of them resident. So a landmark
	CANNOT be emitted by "its own" chunk: walk to the far end of the Parliament and
	the chunk that would have built it has unloaded, and the building disappears
	while you are standing on it.

	THE ANSWER IS (a) PER-CHUNK SLICING. Every chunk whose square meets a slot's
	disc runs that slot's builder into a SCRATCH batch, a SCRATCH body and a
	SCRATCH chunk node, and keeps only the pieces whose CENTRE falls inside its own
	square. The two rejected answers, recorded here because this is exactly what a
	future reader will want to re-open:

	  (b) MANAGER-PARENT THE GIANTS, the way the HQ's shell is parented. Rejected
	      because CLAUDE.md says the tower is the ONE lifetime exception and must
	      stay one, and this would make a second one out of a dozen buildings —
	      each with its own "when does it get freed" question and no chunk to
	      answer it.
	  (c) A WIDER RESIDENCY RADIUS for city chunks. Rejected because the 49-chunk
	      web residency ceiling is the entire reason the city is chunk-streamed
	      instead of authored into the scene; widening it for the city spends the
	      budget the decision was made to protect.

	WHY (a) IS NEARLY FREE: the city builders are PURE FUNCTIONS OF (centre, rng)
	whose random stream touches COLOUR ONLY — landmark_builders.gd's own banner
	says so, and not one dimension, offset or count is drawn. Run the same builder
	from the same seed in a neighbouring chunk and it emits the SAME boxes at the
	SAME world positions, so clipping is a filter on the output and needs no edit
	to that file at all. The cost is measured: the Parliament is 122 boxes over
	~49 chunks, i.e. ~6,000 create_box calls spread one chunk per frame — about
	122 a frame, which is what one ordinary prop chunk already pays.

	================= THE FOUR RULES THAT MAKE IT CORRECT =================

	1. THE SEED IS THE SLOT INDEX AND NOTHING ELSE. No run_seed (the city is
	   authored — tower_site()'s ruling) and, far more sharply, NO CHUNK
	   COORDINATE: mix one in and every slice draws its own colours, and the
	   Parliament comes out tie-dyed along its chunk seams. The salt is wider than
	   an int32 and wraps into Vector3i's component; the wrap is silent but it is
	   deterministic and identical in every chunk, which is the only property this
	   seed needs.
	2. THE CLIP IS HALF-OPEN — `>= -half` and `< half` on both axes. A box centred
	   exactly on a chunk boundary then lands in exactly ONE chunk: never in both
	   (a doubled, z-fighting wall) and never in neither (a hole).
	   THE CENTRE RULE ONLY SLICES A LANDMARK; IT DOES NOT SLICE A BOX, and these
	   builders emit single boxes far bigger than a chunk (Buda Castle's terrace is
	   70 x 300, the Parliament's plinth 125 x 272, against a 50 m chunk). Handed
	   whole to the chunk holding its centre, such a box unloads with that chunk —
	   on the web build that is 150 m of Chebyshev residency against a 300 m
	   palace, i.e. the building vanishing while you walk its far end, which is the
	   exact failure this whole function exists to prevent. So
	   ChunkBatch.split_city_boxes_on_chunk_grid() cuts every oversized
	   AXIS-ALIGNED box on the world chunk grid FIRST; the centre rule then sees
	   only pieces that fit inside one cell and is correct again. Rotated boxes
	   cannot be cut into boxes and keep the centre rule — budapest_selfcheck
	   check 5 fails a rotated box
	   whose footprint exceeds a chunk, which is what keeps that safe.
	   ponytail: the test is on the CHUNK-LOCAL centre, and a local coordinate is
	   an f32 with the chunk's own origin already subtracted, so two neighbours
	   disagree about a seam-straddling box only if their f32 rounding disagrees —
	   sub-micron, and measured as zero over all 15 shipped buildings. If a box
	   ever does double, nudge the slot, not this test: an epsilon here reopens
	   the hole case on the other side.
	3. THE CLIP APPLIES TO BOTH HALVES. Batch entries are filtered on their
	   transform origin; collision shapes are filtered on the scratch body's own
	   CollisionShape3D transforms and REPARENTED rather than rebuilt. Do NOT try
	   to pair a shape with a batch entry by index — every `collide = false` box
	   (and these builders are full of them: domes, spires, cornices) makes the
	   two lists different lengths.
	4. THE ACCENT EXISTS EXACTLY ONCE. Ten of these builders hang a glowing
	   MeshInstance3D on parent_chunk, and under slicing that would give the
	   Parliament one beacon per overlapping chunk. So they are handed a scratch
	   node, and afterwards: if the slot's CENTRE is in this chunk the scratch's
	   children are reparented onto the real one, otherwise the scratch is freed
	   and takes them with it. One rule, no builder edit.

	THE FOOTPRINT is one disc per slot in EVERY chunk the slot touches, at
	climbable: false — the massif convention, so the coin rule skips a coin over a
	cathedral rather than perching it on the silhouette top of a hollow nave, and
	the crocodile spawner keeps out. It is per-chunk because `obstacles` is
	per-chunk, and it is the whole slot rather than this slice because a spawner
	200 m away in another chunk cannot see a neighbour's list anyway.

	AN EMPTY BUILDER IS SKIPPED — that is the whole of "leave the slot empty" for
	the seven wave-C reservations.
	"""
	var half: float = terrain.chunk_size / 2.0

	for i in range(BudapestPlan.SLOTS.size()):
		var slot: Dictionary = BudapestPlan.SLOTS[i]
		var builder: String = slot["builder"]
		if builder.is_empty():
			continue   # a wave-C reservation: a position and a radius, no stone yet

		var pos: Vector3 = slot["pos"]
		var radius: float = slot["radius"]

		# Exact disc-meets-square reject, via the square's closest point to the
		# centre. Every chunk in the city pays 22 of these and nothing else; the
		# rest of the world never gets here at all (spawn_city_in_chunk's own rect
		# reject returned first).
		var near := Vector2(
				clampf(pos.x, chunk_center.x - half, chunk_center.x + half),
				clampf(pos.z, chunk_center.z - half, chunk_center.z + half))
		if Vector2(pos.x - near.x, pos.z - near.y).length_squared() > radius * radius:
			continue

		# Rule 1. The seed carries the slot index and the salt; the chunk is
		# deliberately absent.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(i, BudapestPlan.CITY_LANDMARK_SALT, 0))

		# The scratch trio. None of the three is ever added to the scene tree:
		# the body and the chunk node are pure receptacles that get emptied and
		# freed below, and the batch is a plain Array.
		var scratch_batch: Array = []
		var scratch_body := StaticBody3D.new()
		var scratch_chunk := MeshInstance3D.new()

		# Builders take a CHUNK-LOCAL centre (the field landmarks' convention), so
		# the slot's world position is rebased here — and its authored y is passed
		# through unchanged, which is how the three slots on a plateau stand on the
		# lid instead of inside the hill.
		var center := Vector3(pos.x - chunk_center.x, pos.y, pos.z - chunk_center.z)
		var footprint: Dictionary = CITY_BUILDERS.call(
				builder, terrain, center, rng, scratch_chunk, scratch_batch, scratch_body)

		# Rule 2a: a box WIDER THAN A CHUNK is cut on the grid first (see the
		# helper). Without this the centre rule below hands a 300 m box to one
		# chunk whole, and that chunk unloads while you stand on the far end.
		ChunkBatch.split_city_boxes_on_chunk_grid(terrain, chunk_center, scratch_batch, scratch_body)

		# Rule 2 + 3a: the visual half, half-open on both axes.
		for entry in scratch_batch:
			var o: Vector3 = entry["transform"].origin
			if o.x >= -half and o.x < half and o.z >= -half and o.z < half:
				block_batch.append(entry)

		# Rule 3b: the collision half. get_children() hands back a copy, so
		# removing while iterating it is safe.
		for shape in scratch_body.get_children():
			var o: Vector3 = shape.transform.origin
			if o.x >= -half and o.x < half and o.z >= -half and o.z < half:
				scratch_body.remove_child(shape)
				block_body.add_child(shape)
		scratch_body.free()   # takes every shape this chunk did not claim with it

		# Rule 4: the accent, on the centre chunk only.
		if center.x >= -half and center.x < half and center.z >= -half and center.z < half:
			for accent in scratch_chunk.get_children():
				scratch_chunk.remove_child(accent)
				parent_chunk.add_child(accent)
		scratch_chunk.free()

		# `top` IS RELATIVE TO THE BUILDER'S CENTRE, and here that centre is not on
		# the ground: a builder accumulates its height from 0 and the field spawners
		# hand it center.y = 0, so there the two frames coincide and `footprint.top`
		# is read straight through. The three slots standing on a plateau lid get
		# center.y = pos.y (30, 30, 46), so the lid has to be added back or the
		# entry understates Buda Castle's roofline by the whole hill — and `top` is
		# the shared footprint currency every later spawner reads.
		obstacles.append({
			"pos": Vector3(center.x, 0.0, center.z),
			"radius": radius,
			"top": pos.y + float(footprint.get("top", 0.0)),
			"climbable": false,
		})


static func _spawn_gate_district_in_chunk(terrain: Node3D, chunk_center: Vector3, obstacles: Array, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Build this chunk's share of the GATE DISTRICT (DEC-11, bead godot-test1-8gw.3).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param obstacles: Out-param; one CLIMBABLE disc per house, one prop footprint
	                  per dressing piece.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	WHY THIS DISTRICT AND ONLY THIS DISTRICT. It is ~200 x 260 m immediately east
	of the gate — the SMALLEST slice that exercises every dangerous seam at once:
	authored buildings streamed through ordinary chunks, the city prop builders
	called on authored spots, the avenue running between them, a plateau ramp one
	chunk west and a dry bridge deck 900 m east. Bead godot-test1-8gw.7 owns the
	rest of the street grid; this file owns STREET_PITCH as a parameter and this
	one block as the proof.

	SLICED BY OWNERSHIP, NOT BY CLIPPING, and that is the difference between a
	house and the Parliament. A landmark is 268 m long and has to be cut across
	the chunks it stands on (see _spawn_city_landmarks_in_chunk); a house is 4 m,
	so the chunk containing its CENTRE builds the whole thing. The test is the
	same HALF-OPEN comparison for the same reason — a house centred exactly on a
	seam lands in exactly one chunk, never both and never neither. The couple of
	metres a house may overhang its own chunk are freed with it, 150 m away and
	three chunks behind the camera.

	THE RECIPE IS _spawn_city_content'S, COPIED AND NOT SHARED. Hull + eaves roof
	+ door + windows, with the dimensions AUTHORED (DISTRICT_HOUSES) instead of
	drawn. Refactoring the two to share would move code inside a hot deterministic
	path whose draw ORDER is load-bearing for every crocodile downstream of it;
	ten lines of create_box here is a smaller and far safer diff than proving a
	code motion changed no draw.

	EVERY HOUSE ROOF IS STILL A REST SPOT. The plan caps every authored `height`
	at PROP_MAX_STEP (2.6) and the footprint is climbable: true at the HULL top —
	which since bead godot-test1-y1o.36 is NO LONGER "exactly as the procedural
	city's is". Out in the band the roof is a solid WEDGE and the footprint names
	the RIDGE; here the roof is still a flat `CITY_ROOF_THICKNESS` CUBE film drawn
	`collide = false`, so the hull top IS the surface and the hero's feet are
	inside 0.14 m of trim. The owner's "make roofs standable" ruling was about the
	pitched roofs it is impossible to stand ON; a 0.14 m film is not that, and
	Budapest stays pure CUBE by the city's own rule — so this builder is
	deliberately untouched. A gate district whose roofs you could not reach would
	quietly be the one city block that is not a city block.
	"""
	var half: float = terrain.chunk_size / 2.0
	if not _city_chunk_slice(terrain, chunk_center, BudapestPlan.DISTRICT).has_area():
		return

	# The private stream. Its draws are create_box's colour-ramp padding: every
	# box below passes an explicit override off the plan's authored shades, so the
	# seed only has to be a constant, not a good one.
	var rng := RandomNumberGenerator.new()
	rng.seed = CITY_STREAM_SEED

	for row in BudapestPlan.DISTRICT_HOUSES:
		var pos: Vector3 = row["pos"]
		var local := Vector3(pos.x - chunk_center.x, 0.0, pos.z - chunk_center.z)
		if not (local.x >= -half and local.x < half and local.z >= -half and local.z < half):
			continue

		var size: Vector3 = row["size"]
		var width := size.x
		var height := size.y
		var depth := size.z
		# Both rows FACE THE AVENUE: yaw 0 puts `front` on +Z for the north side,
		# yaw PI turns the south side round. The plan carries no yaw column because
		# there is nothing to choose — a street is two facades looking at each other.
		var yaw := 0.0 if pos.z < 0.0 else PI
		var front := Vector3(-sin(yaw), 0.0, cos(yaw))
		var right := Vector3(cos(yaw), 0.0, sin(yaw))
		# The plan's shades are FACTORS between this file's palette entries, which
		# is what keeps budapest_plan.gd free of any dependency on it.
		var wall: Color = terrain.CITY_PLASTER_A.lerp(terrain.CITY_PLASTER_B, float(row["wall_shade"]))
		var roof: Color = terrain.CITY_ROOF_TILE.lerp(terrain.CITY_ROOF_SLATE, float(row["roof_shade"]))

		# Hull — the ONLY colliding box, and the one whose top face the footprint
		# names.
		terrain.create_box(
			local + Vector3(0.0, height * 0.5, 0.0), Vector3(width, height, depth),
			yaw, rng, block_batch, block_body, 0.0, wall
		)
		# Roof — a thin film over the hull top, collide = false, oversailing as
		# eaves. The player stands on the HULL, inside this film.
		terrain.create_box(
			local + Vector3(0.0, height + terrain.CITY_ROOF_THICKNESS * 0.5, 0.0),
			Vector3(width + terrain.CITY_ROOF_EAVES * 2.0, terrain.CITY_ROOF_THICKNESS, depth + terrain.CITY_ROOF_EAVES * 2.0),
			yaw, rng, block_batch, block_body, 0.0, roof, false
		)
		# Door and windows — trim, never solid: they sit inside the hull's own
		# collision box, so making them collide would buy nothing but a snag.
		var door_h := height * 0.62
		terrain.create_box(
			local + front * (depth * 0.5) + Vector3(0.0, door_h * 0.5, 0.0),
			Vector3(width * 0.24, door_h, 0.10), yaw,
			rng, block_batch, block_body, 0.0, terrain.PROP_CRATE, false
		)
		# Two windows, SYMMETRIC about the door and above its head — the same
		# arrangement (and the same two fixes) as `_spawn_city_content`'s houses,
		# which this recipe is copied from: no one-sided bias, and clear of the
		# door's box so the two never end up coplanar and z-fighting.
		for w in 2:
			var offset := (float(w) - 0.5) * width * 0.32
			terrain.create_box(
				local + front * (depth * 0.5) + right * offset
						+ Vector3(0.0, height * 0.78, 0.0),
				Vector3(width * 0.16, height * 0.22, 0.10), yaw,
				rng, block_batch, block_body, 0.0, terrain.CITY_ROOF_SLATE, false
			)

		obstacles.append({
			"pos": local,
			"radius": 0.5 * sqrt(pow(width + terrain.CITY_ROOF_EAVES * 2.0, 2.0) + pow(depth + terrain.CITY_ROOF_EAVES * 2.0, 2.0)),
			"top": height,
			"climbable": true,
		})

	# ---- STREET DRESSING ----------------------------------------------------
	# The three jb7 CITY prop builders, called DIRECTLY rather than through
	# TerrainProps.build_prop: that function's job is to pick a theme from biome_at, and here
	# the theme is not in question — this is Budapest, so it is the city arm or
	# nothing. One piece in each gap between neighbouring houses on the north row
	# (seven today), alternating sides and cycling the three builders. The row is
	# FILTERED out of the table rather than counted off the front of it: the south
	# houses share the table, so a ninth north house typed in would otherwise pair
	# a north house with a south one and drop the prop at a meaningless midpoint.
	#
	# The spots are DERIVED from the house table rather than typed into a second
	# one, so moving a house moves the crate stack beside it and there is no
	# second table to fall out of step. Each piece takes its OWN RNG seeded off
	# its index alone — the builders draw real dimensions, and one seeded off the
	# shared stream would make a prop's shape depend on how many boxes the chunk
	# happened to build before it.
	var north: Array = BudapestPlan.DISTRICT_HOUSES.filter(
			func(h: Dictionary) -> bool: return h["pos"].z < 0.0)
	for i in range(north.size() - 1):
		var a: Vector3 = north[i]["pos"]
		var b: Vector3 = north[i + 1]["pos"]
		var wx := (a.x + b.x) * 0.5
		var wz := -CITY_DISTRICT_PROP_Z if i % 2 == 0 else CITY_DISTRICT_PROP_Z
		var p_local := Vector3(wx - chunk_center.x, 0.0, wz - chunk_center.z)
		if not (p_local.x >= -half and p_local.x < half and p_local.z >= -half and p_local.z < half):
			continue

		var prng := RandomNumberGenerator.new()
		prng.seed = CITY_STREAM_SEED + i
		var foot: Dictionary
		match i % 3:
			0:
				foot = TerrainProps._prop_crate_stack(terrain, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
			1:
				foot = TerrainProps._prop_garden_wall(terrain, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
			_:
				foot = TerrainProps._prop_paving_stack(terrain, p_local, CITY_DISTRICT_PROP_SIZE, prng, block_batch, block_body)
		obstacles.append({
			"pos": p_local,
			"radius": foot["radius"],
			"top": foot["top"],
			"climbable": foot["climbable"],
		})


static func _spawn_city_blocks_in_chunk(terrain: Node3D, chunk_center: Vector3, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	Fill this chunk's share of every CITY BLOCK the plan's street grid bounds
	(bead godot-test1-8gw.9).

	@param chunk_center: This chunk's centre in world space, from chunk_to_world().
	@param obstacles: Out-param; one keep-out disc per few metres of street wall,
	                  so the hunters that DO spawn in the city are not wedged
	                  inside a facade and a coin over one is skipped, not buried.
	@param block_batch: Out-param; every box joins the chunk's ONE MultiMesh.
	@param block_body: The chunk's single shared collision body.

	WHAT THE OWNER ASKED FOR, verbatim: "budapest seems really empty, but it is
	full of multi story buildings in fact, make it so, make it like what we can see
	on google map walking mode". A street-view city is a CONTINUOUS STREET WALL,
	so every block of the grid that the city has not reserved for something else
	(BudapestPlan.block_buildable) gets four wings of contiguous facade around a
	hollow courtyard: 4-6 storeys of eclectic Pest, 2-3 of Buda hillside.

	AT MOST FOUR CELLS ARE EVER ASKED. A block is 62 m on the grid and a chunk is
	50 m, so a chunk square can straddle one grid line per axis and no more. The
	cheap rect reject in spawn_city_in_chunk has already turned away every chunk
	outside the rect, so the cost of this function for the whole rest of the world
	is zero.

	A BLOCK IS BUILT WHOLE BY EVERY CHUNK THAT TOUCHES IT, AND SLICED ON THE WAY
	OUT. That is the landmark builders' rule one scale down: the facade stream is
	seeded off the CELL, every parameter anything READS is drawn before anything
	is emitted, and only then is each rect intersected with this chunk's
	square. So two chunks slicing one block agree bit for bit on its heights and
	its colours, and the wall meets flush at the seam because _city_chunk_slice
	cuts both halves out of the same rect.
	"""
	var half: float = terrain.chunk_size / 2.0
	var square: Rect2 = Rect2(chunk_center.x - half, chunk_center.z - half, terrain.chunk_size, terrain.chunk_size)
	var lo: Vector2i = BudapestPlan.block_cell(square.position.x, square.position.y)
	var hi: Vector2i = BudapestPlan.block_cell(square.end.x, square.end.y)
	for k in range(lo.x, hi.x + 1):
		for m in range(lo.y, hi.y + 1):
			var cell := Vector2i(k, m)
			if BudapestPlan.block_buildable(cell):
				_build_city_block(terrain, cell, chunk_center, obstacles, block_batch, block_body)


static func _build_city_block(terrain: Node3D, cell: Vector2i, chunk_center: Vector3, obstacles: Array,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	One block of the city: eight buildings in a ring, and this chunk's slice of
	each of them.

	@param cell: The block's integer grid coordinates.

	THE STREAM IS THE WHOLE CORRECTNESS ARGUMENT. `rng` is seeded off (cell,
	CITY_BLOCK_SALT) and NOTHING ELSE — no run_seed (Budapest is authored, the
	tower-furniture precedent), no chunk coordinate (a block is built by up to
	four of them and they have to agree), no draw from anybody else's stream.

	AND EVERY DRAW ANYTHING READS IS TAKEN UP FRONT, before the first box is
	emitted. That is the exact claim, and the qualifier is load-bearing: create_box
	spends four more numbers per box on its curated colour ramp and its roughness,
	AFTER these, and a chunk that skips a box (its piece is in the chunk next door)
	does not spend them. So the streams of two chunks slicing one cell DO diverge —
	in create_box's ramp draws, and only there.

	That divergence is unobservable by construction, for the reason CITY_STREAM_SEED
	states one feature along: every box here passes an explicit `color_override`, so
	the ramp's output is discarded and its draws are pure padding. Nothing downstream
	reads this rng either — it is per-cell and dies with the call. What the two
	chunks must agree on is `storeys`, `walls`, `awnings`, `balconies` and `roof`,
	and those are all drawn above, in one fixed order, for all eight buildings,
	before any geometry exists to skip. budapest_selfcheck check 3 measures the
	result rather than the argument: a dense Pest block, byte-identical across two
	different run seeds.

	~TEN BOXES BUY A BUILDING: one colliding hull, a window course per storey, two
	shopfronts around a doorway gap, an awning, an optional balcony and the cornice.
	See _city_block_boxes and the CITY BLOCKS constants.
	"""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, CITY_BLOCK_SALT))

	var interior := BudapestPlan.block_rect(cell)
	var centre := interior.get_center()
	var band: Vector2i = BudapestPlan.BLOCK_STOREYS_BUDA \
			if BudapestPlan.is_buda(centre.x, centre.y) \
			else BudapestPlan.BLOCK_STOREYS_PEST

	# ---- EVERY DRAW, BEFORE ANY EMIT ---------------------------------------
	# A building's whole description is drawn here, in one fixed order, for all
	# eight of them — see the docstring. `hues` is the bank's own palette, so a
	# Pest block is cream beside ochre beside grey-green and not eight samples of
	# one ramp.
	var buda := BudapestPlan.is_buda(centre.x, centre.y)
	var hues: Array[Color] = CITY_FACADE_BUDA if buda else CITY_FACADE_PEST
	var base := rng.randi_range(band.x, band.y)
	var roof: Color = terrain.CITY_ROOF_TILE.lerp(terrain.CITY_ROOF_SLATE, rng.randf())
	var storeys: Array[int] = []
	var walls: Array[Color] = []
	var awnings: Array[Color] = []
	var balconies: Array[bool] = []
	for _i in range(4 * BudapestPlan.BLOCK_SEGMENTS):
		storeys.append(clampi(
				base + rng.randi_range(-CITY_BLOCK_STOREY_JITTER, CITY_BLOCK_STOREY_JITTER),
				band.x, band.y))
		walls.append((hues[rng.randi_range(0, hues.size() - 1)] as Color)
				.lerp(terrain.CITY_PLASTER_B, rng.randf() * CITY_FACADE_TINT_MAX))
		awnings.append(CITY_AWNING_A.lerp(CITY_AWNING_B, rng.randf()))
		# Buda's houses get no balcony at all, but the draw is taken either way:
		# a stream whose length depended on which bank it was on would be a
		# second thing to keep in step for nothing.
		balconies.append(rng.randf() < CITY_BALCONY_CHANCE and not buda)

	# ---- ...AND ONLY THEN, THIS CHUNK'S SLICE OF EACH ------------------------
	for side in 4:
		var wing: Rect2 = BudapestPlan.block_wing(cell, side)
		var outward: Vector2 = BudapestPlan.block_wing_outward(side)
		# A wing is long on X for the north/south walls and long on Z for the two
		# side walls; `along_x` is which axis it runs down, and the bands stand
		# proud on the other one.
		var along_x := absf(outward.y) > 0.5
		for seg in range(BudapestPlan.BLOCK_SEGMENTS):
			var idx := side * BudapestPlan.BLOCK_SEGMENTS + seg
			var height := float(storeys[idx]) * CITY_STOREY_HEIGHT
			var piece := _city_block_segment(terrain, wing, along_x, seg)
			_city_block_boxes(terrain, piece, along_x, storeys[idx], walls[idx], roof,
					awnings[idx], balconies[idx], chunk_center, rng,
					block_batch, block_body)
			_city_block_footprints(terrain, piece, height, chunk_center, obstacles)
			_city_block_door(terrain, piece, outward, chunk_center, rng, block_batch, block_body)


static func _city_block_segment(terrain: Node3D, wing: Rect2, along_x: bool, seg: int) -> Rect2:
	"""One building's footprint: the `seg`'th equal slice of a wing along its long
	axis. Equal slices and not jittered ones, because the ROOFLINE is where the
	variety lives — two neighbours of different heights read as two houses, and a
	jittered party wall would only cost a constant nobody can see."""
	var n := float(BudapestPlan.BLOCK_SEGMENTS)
	if along_x:
		var w := wing.size.x / n
		return Rect2(wing.position.x + float(seg) * w, wing.position.y, w, wing.size.y)
	var d := wing.size.y / n
	return Rect2(wing.position.x, wing.position.y + float(seg) * d, wing.size.x, d)


static func _city_block_boxes(terrain: Node3D, piece: Rect2, along_x: bool, storeys: int, wall: Color,
		roof: Color, awning: Color, balcony: bool, chunk_center: Vector3,
		rng: RandomNumberGenerator, block_batch: Array,
		block_body: StaticBody3D) -> void:
	"""
	Every SLICEABLE box of one building: the hull, a window course per storey, the
	two halves of its shopfront with the doorway gap between them, the awning over
	them, an optional balcony course and the roofline cornice.

	WHY A BAND AND NOT A WINDOW. A 21 m facade drawn as one plaster box with a
	cornice on top reads as a WALL — which is what the first cut of this bead
	shipped and what the owner's "like google map walking mode" is not. What makes
	a real street legible from across it is the HORIZONTAL RHYTHM of the window
	courses, and a band gets that for ONE box per storey where a window grid would
	cost thirty. `_city_band` is the whole vocabulary; everything here is a call
	to it with a height, a thickness, a proud distance and a colour.

	THE BANDS ARE GROWN BEFORE THEY ARE SLICED, never after, and that ordering is
	load-bearing at a chunk seam. Growing a slice would push a band across the
	seam and into the identical band its neighbour chunk grew the other way, so
	the two would overlap by twice the proud distance and z-fight for the length
	of the wall. Growing the WHOLE rect and then cutting it gives two pieces that
	meet exactly, which is the same argument _city_chunk_slice already makes for
	the hull.

	Only the HULL collides. A cornice you could stand on would be a 20 m ledge the
	whole way round every block in the city; a shopfront you could snag on would
	be 46 m of kerb per block face. Both are decoration, and decoration in this
	codebase pays for its pixels and not for a collision shape.
	"""
	var height := float(storeys) * CITY_STOREY_HEIGHT

	# The hull: the one box with a collision shape, floor to roofline.
	var hull := _city_chunk_slice(terrain, chunk_center, piece)
	if hull.has_area():
		var c := hull.get_center()
		terrain.create_box(Vector3(c.x - chunk_center.x, height * 0.5, c.y - chunk_center.z),
				Vector3(hull.size.x, height, hull.size.y), 0.0,
				rng, block_batch, block_body, 0.0, wall)

	# ---- THE WINDOW COURSES, one per storey above the shopfront -------------
	# 6 cm PROUD, which reads as flush at street distance and is the only way the
	# course exists at all — see CITY_WINDOW_PROUD for the recessed version that
	# did not. The glass tone alternates by storey parity, so five storeys read as
	# five courses and not as one striped texture.
	for s in range(1, storeys):
		_city_band(terrain, piece, along_x, CITY_WINDOW_PROUD,
				float(s) * CITY_STOREY_HEIGHT + CITY_WINDOW_SILL + CITY_WINDOW_HEIGHT * 0.5,
				CITY_WINDOW_HEIGHT,
				CITY_WINDOW_DARK if s % 2 == 0 else CITY_WINDOW_LIT,
				chunk_center, rng, block_batch, block_body)

	# ---- THE GROUND FLOOR: two shopfronts with the doorway between them ------
	# One band split around the door's own width is what turns a continuous dark
	# stripe into a row of SHOPS with an entrance, and it costs one extra box.
	# The door itself is _city_block_door's, placed by the chunk that owns it.
	var span := piece.size.x if along_x else piece.size.y
	var gap := (CITY_DOOR_WIDTH + 0.9) / span * 0.5   # half the gap, as a fraction
	for half in [Vector2(0.0, 0.5 - gap), Vector2(0.5 + gap, 1.0)]:
		_city_band(terrain, _city_sub_rect(terrain, piece, along_x, half.x, half.y), along_x,
				CITY_SHOPFRONT_PROUD, CITY_SHOPFRONT_HEIGHT * 0.5,
				CITY_SHOPFRONT_HEIGHT, CITY_SHOPFRONT_GLASS,
				chunk_center, rng, block_batch, block_body)
	# ...and the canvas awning over them, oversailing the pavement.
	_city_band(terrain, piece, along_x, CITY_AWNING_PROUD,
			CITY_SHOPFRONT_HEIGHT + CITY_AWNING_THICKNESS * 0.5,
			CITY_AWNING_THICKNESS, awning, chunk_center, rng, block_batch, block_body)

	# ---- THE BALCONY COURSE, on the Pest buildings that drew one ------------
	if balcony:
		_city_band(terrain, piece, along_x, CITY_BALCONY_PROUD, _city_balcony_y(terrain, height),
				CITY_BALCONY_THICKNESS, CITY_BALCONY_IRON,
				chunk_center, rng, block_batch, block_body)

	# ---- ...AND THE ROOFLINE ------------------------------------------------
	_city_band(terrain, piece, along_x, CITY_CORNICE_PROUD,
			height + CITY_CORNICE_THICKNESS * 0.25, CITY_CORNICE_THICKNESS, roof,
			chunk_center, rng, block_batch, block_body)


static func _city_band(terrain: Node3D, piece: Rect2, along_x: bool, proud: float, y: float, thickness: float,
		tone: Color, chunk_center: Vector3, rng: RandomNumberGenerator,
		block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	ONE horizontal band lying against a building's facade — the single vocabulary
	every piece of articulation in this city is spelled in.

	@param proud: how far it stands off the wall on the CROSS axis. NEGATIVE
	              recesses it INTO the wall, which is what a window course is.
	@param y: the band's centre height. @param thickness: its full height.

	Grown on the cross axis only, so it never lengthens into the building next
	door, and grown before it is sliced — see the caller for why that ordering is
	the difference between a flush seam and a z-fighting one. Never collides.
	"""
	# Cross axis stands PROUD; the long axis is pulled IN by CITY_BAND_END_INSET so
	# the band's end faces never land on the hull's own end planes — see that const.
	var grown: Rect2 = piece.grow_individual(-CITY_BAND_END_INSET, proud, -CITY_BAND_END_INSET, proud) if along_x \
			else piece.grow_individual(proud, -CITY_BAND_END_INSET, proud, -CITY_BAND_END_INSET)
	var slice := _city_chunk_slice(terrain, chunk_center, grown)
	if not slice.has_area():
		return
	var mid := slice.get_center()
	terrain.create_box(Vector3(mid.x - chunk_center.x, y, mid.y - chunk_center.z),
			Vector3(slice.size.x, thickness, slice.size.y), 0.0,
			rng, block_batch, block_body, 0.0, tone, false)


static func _city_sub_rect(terrain: Node3D, piece: Rect2, along_x: bool, from: float, to: float) -> Rect2:
	"""The `from`..`to` fraction of a building's rect along its LONG axis — how the
	shopfront is split around its doorway."""
	if along_x:
		return Rect2(piece.position.x + piece.size.x * from, piece.position.y,
				piece.size.x * (to - from), piece.size.y)
	return Rect2(piece.position.x, piece.position.y + piece.size.y * from,
			piece.size.x, piece.size.y * (to - from))


static func _city_balcony_y(terrain: Node3D, height: float) -> float:
	"""The height of a building's balcony course: the top of its SECOND storey, or
	of its first when it only has two. A course drawn above the roofline is a rail
	hanging in the sky, which is what a fixed 8.4 m would give every Buda house."""
	return minf(2.0 * CITY_STOREY_HEIGHT, height - CITY_STOREY_HEIGHT * 0.5)


static func _city_block_door(terrain: Node3D, piece: Rect2, outward: Vector2, chunk_center: Vector3,
		rng: RandomNumberGenerator, block_batch: Array, block_body: StaticBody3D) -> void:
	"""
	One carriage gateway on a building's street face — the piece of a Pest block
	that tells you the courtyard behind it is hollow.

	OWNER-CHUNK PLACED, NOT SLICED, and that is the difference between a POINT
	feature and a RECT one. A door is 1.5 m wide; slicing it would be pointless,
	and centring it on the SLICE rather than on the building would move it every
	time the chunk grid moved and would draw it twice on a building that straddles
	a seam. So the chunk containing the door's own anchor builds the whole thing,
	on the same half-open comparison the gate district's houses use.
	"""
	var c := piece.get_center()
	var face := c + outward * (0.5 * (absf(outward.x) * piece.size.x
			+ absf(outward.y) * piece.size.y) + CITY_DOOR_PROUD * 0.5)
	var half: float = terrain.chunk_size / 2.0
	var local := Vector3(face.x - chunk_center.x, 0.0, face.y - chunk_center.z)
	if not (local.x >= -half and local.x < half and local.z >= -half and local.z < half):
		return
	# Thin on the outward axis, CITY_DOOR_WIDTH across it.
	var size := Vector3(CITY_DOOR_PROUD, CITY_DOOR_HEIGHT, CITY_DOOR_WIDTH) \
			if absf(outward.x) > 0.5 \
			else Vector3(CITY_DOOR_WIDTH, CITY_DOOR_HEIGHT, CITY_DOOR_PROUD)
	terrain.create_box(local + Vector3(0.0, CITY_DOOR_HEIGHT * 0.5, 0.0), size, 0.0,
			rng, block_batch, block_body, 0.0, CITY_DOOR_WOOD, false)


static func _city_block_footprints(terrain: Node3D, piece: Rect2, height: float, chunk_center: Vector3,
		obstacles: Array) -> void:
	"""
	Claim one building's ground as `obstacles`, as a CHAIN OF DISCS rather than as
	one circumscribing circle.

	@param piece: the building's own rect, world XZ. The claim is made in this
	              chunk's local frame; a disc that falls outside the chunk is
	              simply never asked about.

	WHY NOT ONE DISC. `obstacles` is a list of circles, and the circle round a
	23 x 13 m building has a 13 m radius centred 6.5 m behind the facade — it
	would reach 6.5 m past the kerb into a 16 m street, and every coin on that
	avenue would be dropped by _settle_coin_y as "buried". A chain of discs one
	wing-depth apart covers the same rect and reaches only ~2.7 m into the street,
	which is inside the pavement the buildings stand on.

	climbable: FALSE, because these are 8 to 25 m tall. That is what makes a coin
	that lands on one SKIPPED rather than perched on a roof no one can reach, and
	it is the same mountain-massif convention the plateaus use.
	"""
	var r := BudapestPlan.BLOCK_WING_DEPTH * 0.5
	var along_x := piece.size.x >= piece.size.y
	var span := piece.size.x if along_x else piece.size.y
	var n := maxi(1, ceili(span / BudapestPlan.BLOCK_WING_DEPTH))
	for i in range(n):
		var t := (float(i) + 0.5) / float(n)
		var p := piece.position + Vector2(
				piece.size.x * (t if along_x else 0.5),
				piece.size.y * (0.5 if along_x else t))
		obstacles.append({
			"pos": Vector3(p.x - chunk_center.x, 0.0, p.y - chunk_center.z),
			# The disc that covers a wing-depth square of the wall, so the chain
			# leaves no gap between its links.
			"radius": r * sqrt(2.0),
			"top": height,
			"climbable": false,
		})


static func spawn_approach_coins_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Lay this chunk's slice of the APPROACH + AVENUE coin line: the trail that
	carries the player from the road's terminal station, through Budapest's gate,
	up the avenue to the Danube's west bank (bead godot-test1-8gw.3).

	@param chunk_pos: Chunk coordinates this body is laying coins for.
	@param parent_chunk: The chunk mesh the coins attach to (positions are stored
	                     chunk-LOCAL, exactly like the road's).
	@param obstacles: This chunk's block footprints, for the shared perch-or-skip
	                  rule in _settle_coin_y.

	WHY IT EXISTS AT ALL. _road_coins_at stops at the terminal station, and the
	terminal is ~900 m west of the Danube. Coins are the headline score since bead
	.1 retired distance, so without this line the score would sit frozen for the
	whole walk into the city — the road would read as "you have arrived nowhere".

	ZERO RNG, and that is the design and not an omission. Every coin is at a fixed
	CITY_COIN_SPACING pitch ALONG BudapestPlan.road_approach_point()'s centreline
	(BudapestPlan.approach_coin_line resamples it by arc length — a pitch stepped in
	X would open to 8 * sqrt(1 + slope^2) on a steep seed), so this line is AUTHORED
	like the rest of the city (the tower_site() ruling one scale up). There is no
	hash stream here to keep independent of the chunk's, no salt to pick and nothing
	for a determinism A/B to measure — the only run-varying input is the terminal
	station itself, which is where the road's own seed enters.

	SEAM-CORRECTNESS, the road's rule unchanged: a coin's position is fixed by its
	index in that one shared line, but it rides the corridor in BOTH axes, so a coin
	whose X is in this chunk's column can still belong to the chunk one row over.
	Every coin is therefore BUCKETED by `world_to_chunk(pos) == chunk_pos` — the
	chunk that owns it scans the same X window and picks it up, so there are no gaps
	and no duplicates. Coin identity is Coin.id_at(world) (quantized position), so
	multiplayer claims work with no mp_manager edit at all.

	Nothing here is a MeshInstance3D or a body of its own: coins are ordinary
	chunk-parented pickups that unload with the chunk, like every road coin.
	"""
	if not terrain.spawn_coins or terrain.coin_scene == null:
		return

	var line := _approach_coin_line(terrain)
	if line.is_empty():
		return

	var center: Vector3 = terrain.chunk_to_world(chunk_pos)
	var half_chunk: float = terrain.chunk_size / 2.0
	var x0 := center.x - half_chunk
	var x1 := center.x + half_chunk
	# The line is in increasing X, so a chunk column outside its span has nothing
	# to do at all — which is every chunk in the world bar the corridor's own few.
	if x1 < line[0].x or x0 > line[line.size() - 1].x:
		return

	for i in range(line.size()):
		var p: Vector2 = line[i]
		# Past this chunk's column — X only grows from here, so this is the end of
		# this chunk's work. (The west bank is where the LINE stops, not a per-coin
		# test: a chunk east of the river would answer "not wet" for every coin in
		# turn and pave the whole Pest side.)
		if p.x > x1:
			break
		if p.x < x0:
			continue

		var world: Vector3 = Vector3(p.x, terrain.COIN_GROUND_HEIGHT, p.y)
		# Bucket by final chunk — the seam rule, identical to the road's.
		if terrain.world_to_chunk(world) != chunk_pos:
			continue

		var local := Vector3(world.x - center.x, world.y, world.z - center.z)
		# The shared perch-or-skip rule: perch on a climbable top, drop the coin
		# where the corridor runs under something sheer (INF). The city's own
		# geometry is already in `obstacles` — spawn_city_in_chunk runs before the
		# coin spawners, like every other footprint producer.
		local.y = terrain._settle_coin_y(local.x, local.z, local.y, obstacles)
		if is_inf(local.y):
			continue
		# ...and the corridor's own bridges, the road line's rule one spawner
		# along (bead godot-test1-06o.2): a coin standing over a deck rides it,
		# instead of being buried in the slab that crosses the water here.
		#
		# BEHIND THE SAME FLAG as the road line's lift, and for a reason the road
		# line found first: `field_bridge_surface_y` answers off the PLAN, which
		# exists whether or not the builder was allowed to run, so an ungated lift
		# stands a coin 1.6 m over open water in every configuration that turns
		# the bridges off — the A/B in field_bridge_selfcheck check 6 among them.
		if terrain.spawn_field_bridges:
			var deck_y: float = terrain.field_bridge_surface_y(world)
			if deck_y > -INF:
				local.y = deck_y + terrain.COIN_GROUND_HEIGHT

		var coin = terrain.coin_scene.instantiate()
		coin.position = local
		parent_chunk.add_child(coin)

static func _approach_coin_line(terrain: Node3D) -> PackedVector2Array:
	"""
	The approach + avenue coin line for this run: every coin centre, in increasing
	X, at a uniform CITY_COIN_SPACING pitch ALONG the corridor.

	@return: The shared, memoized line. Callers must not mutate it.

	Memoized because every chunk in the world asks for it and it is a pure function
	of the terminal station — which is fixed for the run. `_drop_seeded_memos()`
	drops it beside _road_terminal_k_cache, the one seeded input it has.

	The resampling itself lives in BudapestPlan.approach_coin_line(), with the rest
	of the corridor's arithmetic, so the coins and the clearance swath keep reading
	one geometry.
	"""
	if terrain._approach_coin_line_cache.is_empty():
		# _road_terminal_k() has already extended the cache far enough to cover the
		# terminal — the ONE place the run's seed reaches this line.
		var terminal: Vector2 = terrain._road_station(terrain._road_terminal_k()).center
		terrain._approach_coin_line_cache = BudapestPlan.approach_coin_line(
				terminal, terrain.ROAD_TERMINAL_X, _approach_coin_east_end(terrain))
	return terrain._approach_coin_line_cache

static func spawn_city_coins_in_chunk(terrain: Node3D, chunk_pos: Vector2i, parent_chunk: MeshInstance3D, obstacles: Array) -> void:
	"""
	Lay this chunk's slice of the CITY's own coin routes (bead godot-test1-8gw.9):
	the avenues of the street grid, and every bridge across the Danube.

	@param chunk_pos: Chunk coordinates this body is laying coins for.
	@param parent_chunk: The chunk mesh the coins attach to (positions are stored
	                     chunk-LOCAL, exactly like the road's).
	@param obstacles: This chunk's block footprints, for the shared perch-or-skip
	                  rule in _settle_coin_y.

	WHY IT EXISTS. Coins are the headline score since bead .1 retired distance,
	and bead .3's approach line deliberately stops at the Danube's west bank — its
	own docstring says so and calls the 1.4 km of Pest east of it "no coin source
	at all". This is that source. `in_budapest()` turns every PROCEDURAL coin off
	inside the rect, so an authored city needs an authored reward line.

	ZERO RNG, exactly like its sibling above: a fixed pitch along authored lines,
	so there is no stream here to keep independent of the chunk's, nothing for a
	determinism A/B to measure, and the same coin stands in the same metre of
	Budapest in every run and for every peer. Coin identity is Coin.id_at(world)
	(quantized position), so multiplayer claims work with NO mp_manager edit.

	THREE RULES, and each one is a thing that would otherwise be a bug:
	  1. NOT ON THE APPROACH LINE. Street row 0 IS the avenue out of the gate, and
	     bead .3's corridor already paves it as far as the west bank. Coins west
	     of `_approach_coin_east_end()` inside the carriageway are therefore
	     skipped — the two lines are one trail and must not double up.
	  2. NOT UNDER A BRIDGE. A deck rect crosses the grid at 12 m, and an avenue
	     coin under one would sit at COIN_GROUND_HEIGHT with a colliding slab over
	     it (a deck takes no `obstacles` footprint, deliberately, so _settle_coin_y
	     cannot see it — the same reasoning `_approach_coin_east_end` is built on).
	     The bridge's OWN line, at deck height, replaces it.
	  3. GEMS AT THE SQUARES. Where two GEM avenues cross is a square, and a square
	     is worth stopping at — a gem is 10 coins, so the streak the player is
	     building has somewhere to pay off.

	AND THE PITCH IS THE CITY'S OWN, NOT THE CORRIDOR'S (bead godot-test1-1qm,
	owner: "coins should be really rare in Budapest"). Both loops below step
	CITY_STREET_COIN_SPACING (64 m) where they used to step CITY_COIN_SPACING
	(8 m) — one coin per city block along an avenue, and gems on a quarter of the
	squares. The APPROACH corridor above keeps the 8 m pitch untouched: it is the
	guide out of the field and has to read as a continuous trail, which is the
	whole reason the two pitches are two constants. Entity counts moved BY DESIGN
	here, which is the one reason the performance conventions allow them to move.
	"""
	if not terrain.spawn_coins or terrain.coin_scene == null:
		return
	var centre: Vector3 = terrain.chunk_to_world(chunk_pos)
	var half: float = terrain.chunk_size / 2.0
	var square: Rect2 = Rect2(centre.x - half, centre.z - half, terrain.chunk_size, terrain.chunk_size)
	if not square.intersects(BudapestPlan.rect()):
		return

	# ---- THE AVENUES --------------------------------------------------------
	# Both axes, one loop each: a NORTH-SOUTH avenue is a fixed X with coins
	# stepped in Z, and an EAST-WEST one is the transpose. The step is anchored on
	# the city rect's own corner rather than on the chunk, so a coin's position is
	# a function of the CITY and every chunk that could own it agrees on where it
	# is — the road's seam rule, one authored line along.
	for axis_x in [true, false]:
		var line_lo: int = ceili((square.position.x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH) \
				if axis_x else ceili((square.position.y - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
		var line_hi: int = floori((square.end.x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH) \
				if axis_x else floori((square.end.y - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
		for i in range(line_lo, line_hi + 1):
			if not BudapestPlan.is_avenue(i):
				continue
			var fixed: float = BudapestPlan.street_x(i) if axis_x else BudapestPlan.street_z(i)
			var run_min: float = BudapestPlan.BUDAPEST_MIN.y if axis_x else BudapestPlan.BUDAPEST_MIN.x
			var lo := maxf(square.position.y if axis_x else square.position.x, run_min)
			var hi := minf(square.end.y if axis_x else square.end.x,
					BudapestPlan.BUDAPEST_MAX.y if axis_x else BudapestPlan.BUDAPEST_MAX.x)
			var j := ceili((lo - run_min) / BudapestPlan.CITY_STREET_COIN_SPACING)
			var along := run_min + float(j) * BudapestPlan.CITY_STREET_COIN_SPACING
			while along <= hi:
				var world: Vector3 = Vector3(fixed if axis_x else along, terrain.COIN_GROUND_HEIGHT,
						along if axis_x else fixed)
				along += BudapestPlan.CITY_STREET_COIN_SPACING
				_place_city_coin(terrain, world, chunk_pos, centre, parent_chunk, obstacles,
						_city_square_here(terrain, world.x, world.z))

	# ---- AND EVERY BRIDGE ---------------------------------------------------
	# Down the middle of each deck, at the height the deck's own profile gives —
	# BudapestPlan.bridge_surface_y, the same expression the slabs are built from,
	# so the trail climbs each ramp with the stone instead of through it.
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if not square.intersects(deck):
			continue
		var z := deck.get_center().y
		var b := ceili((maxf(square.position.x, deck.position.x) - deck.position.x)
				/ BudapestPlan.CITY_STREET_COIN_SPACING)
		var x := deck.position.x + float(b) * BudapestPlan.CITY_STREET_COIN_SPACING
		while x <= minf(square.end.x, deck.end.x):
			var world: Vector3 = Vector3(x, BudapestPlan.bridge_surface_y(row_v, x) + terrain.COIN_GROUND_HEIGHT, z)
			x += BudapestPlan.CITY_STREET_COIN_SPACING
			if terrain.world_to_chunk(world) != chunk_pos:
				continue
			# NO _settle_coin_y HERE, and that is deliberate: a deck coin is 12 m
			# up, and the perch rule is about what stands on the GROUND under a
			# column. Asking it would drop every coin on the Chain Bridge for the
			# pier stone at its foot.
			var gem = terrain.coin_scene.instantiate()
			gem.position = Vector3(world.x - centre.x, world.y, world.z - centre.z)
			parent_chunk.add_child(gem)


static func _place_city_coin(terrain: Node3D, world: Vector3, chunk_pos: Vector2i, centre: Vector3,
		parent_chunk: MeshInstance3D, obstacles: Array, gem: bool) -> void:
	"""One avenue coin, through every rule the routes' docstring lists. Bucketed
	by `world_to_chunk` like the road's, so seams are gap-free and duplicate-free."""
	if terrain.world_to_chunk(world) != chunk_pos:
		return
	# Rule 1 — the gate avenue is already paved as far as the west bank.
	if absf(world.z - BudapestPlan.GATE.z) < BudapestPlan.AVENUE_HALF_WIDTH \
			and world.x < _approach_coin_east_end(terrain):
		return
	# Rule 2 — a bridge's own line owns the crossing, at deck height.
	for row_v: Variant in BudapestPlan.BRIDGES:
		if (BudapestPlan.bridge_deck(row_v) as Rect2).has_point(Vector2(world.x, world.z)):
			return
	var local := Vector3(world.x - centre.x, world.y, world.z - centre.z)
	local.y = terrain._settle_coin_y(local.x, local.z, local.y, obstacles)
	if is_inf(local.y):
		return
	var coin = terrain.coin_scene.instantiate()
	coin.position = local
	if gem:
		coin.make_gem()
	parent_chunk.add_child(coin)


static func _city_square_here(terrain: Node3D, x: float, z: float) -> bool:
	"""
	Is this coin standing at a SQUARE — the crossing of two GEM avenues? That is
	where the gems go, and it is the one place the grid's two axes have anything
	to say to each other.

	PURE GRID PARITY, and the distance test that used to be here is GONE rather
	than retuned (bead godot-test1-1qm). It asked whether the coin lay within half
	a COIN pitch of the crossing, which discriminated while that pitch was 8 m; at
	CITY_STREET_COIN_SPACING (64 m) it is wider than STREET_PITCH (62 m), so every
	coin is within half a pitch of its nearest crossing and the test answers true
	for all of them — a clause that cannot say no is worse than no clause, because
	it reads like one that can. What is left is the parity of the two NEAREST
	street lines, which is the rule the owner's "really rare" asked for: a gem at
	every fourth square instead of at every one.
	"""
	var k := roundi((x - BudapestPlan.GATE.x) / BudapestPlan.STREET_PITCH)
	var m := roundi((z - BudapestPlan.GATE.z) / BudapestPlan.STREET_PITCH)
	return BudapestPlan.is_gem_avenue(k) and BudapestPlan.is_gem_avenue(m)


static func _approach_coin_east_end(terrain: Node3D) -> float:
	"""
	The world X the approach + avenue coin line stops at: the Danube's WEST BANK on
	the avenue's own line at z = 0, or the western abutment of the bridge standing
	on that line, whichever comes first.

	@return: The first X at or east of the gate where the avenue is in the water or
	         is climbing a bridge.

	Asked of the river's own polyline rather than written down, so bead .4 can
	reshape the Danube and this line follows with no edit here — the same "one home
	for the rule" discipline _settle_coin_y gives the coin perch.

	IT IS THE BAND, NOT danube_wet(), AND THAT DISTINCTION IS THE WHOLE FUNCTION.
	The avenue runs east along z = 0, and the Danube's z = 0 crossing is exactly
	where the CHAIN BRIDGE stands — so its deck is a DRY_RECTS row and danube_wet()
	answers false for every metre of the crossing. A line that stopped at the first
	wet metre would therefore not stop at all: it would run the full 2.2 km of the
	rect and out the other side of the city, paving the bridge and all of Pest with
	the gate's coin trail. A BANK is where the water's edge is; a dry rect is a
	thing built ON the water and has nothing to say about where the river runs.

	ponytail: the line stops at the west bank, so the 1.4 km of Pest east of the
	Danube ships with no coin source at all (in_budapest() turns every procedural
	one off inside the rect). That is this bead's authored scope — the city's own
	reward line is bead .5's — not an oversight, and it is written down here
	because a corridor that simply ends reads like one.

	Memoized for the process, and it may be: east of the gate the corridor IS the
	avenue at z = 0, so this is a pure function of BudapestPlan's authored polyline
	with no run_seed in it anywhere. new_run() has nothing to reset. The scan is
	bounded by the city rect's east edge, so a plan whose river missed z = 0
	entirely would terminate with the line simply running the width of the city
	rather than looping.
	"""
	if not is_inf(terrain._approach_coin_east_end_cache):
		return terrain._approach_coin_east_end_cache
	var east := BudapestPlan.BUDAPEST_MAX.x
	var x := BudapestPlan.GATE.x
	while x < east:
		if BudapestPlan.danube_distance(x, BudapestPlan.GATE.z) < BudapestPlan.DANUBE_HALF_WIDTH:
			east = x
			break
		x += BudapestPlan.CITY_COIN_SPACING

	# ...OR AT THE BRIDGE'S ABUTMENT, WHICHEVER COMES FIRST (bead .4), which is the
	# reshaping this function's third paragraph was written to absorb.
	#
	# A deck rect deliberately OVERHANGS the band so its ramps' feet land on dry
	# ground, so the Chain Bridge's western approach begins ~22 m short of the bank
	# and climbs to 12 m across those metres. Everything the corridor puts on that
	# stretch is put UNDER a colliding ramp slab: the last coins would sit at
	# COIN_GROUND_HEIGHT with several metres of stone over them (a ramp takes no
	# `obstacles` footprint, deliberately, so _settle_coin_y cannot see it), and the
	# pavement would be buried with them. The corridor the city actually offers is
	# the gate to the bridge, and then up — so both stop where the bridge starts.
	for row_v: Variant in BudapestPlan.BRIDGES:
		var deck: Rect2 = BudapestPlan.bridge_deck(row_v)
		if deck.position.y <= BudapestPlan.GATE.z and deck.end.y >= BudapestPlan.GATE.z:
			east = minf(east, deck.position.x)

	terrain._approach_coin_east_end_cache = east
	return east


static func _city_river_segments(terrain: Node3D) -> PackedVector4Array:
	"""
	The Danube polyline as (x1, z1, x2, z2) segments, for ground.gdshader's
	`city_river` array uniform.

	Padded to CITY_SEG_MAX (8) because a GLSL array uniform is that size whatever
	the polyline's length is; the shader reads `city_river_count` of them and the
	padding is never touched. If a future author adds a sixth point to DANUBE, the
	assert below is what tells them the shader's array has to grow with it.
	"""
	var segs := PackedVector4Array()
	segs.resize(terrain.CITY_SHADER_SEG_MAX)
	assert(BudapestPlan.DANUBE.size() - 1 <= terrain.CITY_SHADER_SEG_MAX,
			"BudapestPlan.DANUBE has more segments than ground.gdshader's CITY_SEG_MAX")
	for i in range(mini(BudapestPlan.DANUBE.size() - 1, terrain.CITY_SHADER_SEG_MAX)):
		var a: Vector2 = BudapestPlan.DANUBE[i]
		var b: Vector2 = BudapestPlan.DANUBE[i + 1]
		segs[i] = Vector4(a.x, a.y, b.x, b.y)
	return segs


static func _city_dry_rects(terrain: Node3D) -> PackedVector4Array:
	"""
	The dry rects — bridge decks and Margaret Island — as (xmin, zmin, xmax, zmax)
	for ground.gdshader's `city_dry`, padded to CITY_DRY_MAX exactly like the
	segments above and read `city_dry_count` deep.
	"""
	var rects := PackedVector4Array()
	rects.resize(terrain.CITY_SHADER_DRY_MAX)
	assert(BudapestPlan.DRY_RECTS.size() <= terrain.CITY_SHADER_DRY_MAX,
			"BudapestPlan.DRY_RECTS has more rows than ground.gdshader's CITY_DRY_MAX")
	for i in range(mini(BudapestPlan.DRY_RECTS.size(), terrain.CITY_SHADER_DRY_MAX)):
		var r: Rect2 = BudapestPlan.DRY_RECTS[i]
		rects[i] = Vector4(r.position.x, r.position.y,
				r.position.x + r.size.x, r.position.y + r.size.y)
	return rects
