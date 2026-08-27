extends Control
## Minimap HUD — where you are, which way you face, and where the coin road goes.
##
## Drawn entirely in _draw() with no texture assets, exactly like ability_hud.gd
## and lives_hud.gd: this project ships a web build where every KB and every draw
## call is budgeted, so the HUD is code-built circles, lines and text.
##
## Discovery is GROUP-BASED like the rest of the HUD — the player comes from the
## "player" group and the world from the "terrain" group, both re-fetched if they
## ever go away, both guarded with has_method() so this control still runs (blank)
## in a scene that has neither.
##
## WHAT IT SHOWS
##   * A north-up map: world +X is screen RIGHT, world +Z is screen DOWN. North-up
##     (rather than rotating the map under a fixed arrow) is deliberate: the coin
##     road always trends +X by construction, so a fixed frame makes "the road goes
##     that way" readable at a glance, and it costs no per-point rotation.
##   * The BIOME FIELD across the whole disc, as coloured bands — so the desert or
##     the snow you are walking toward is visible before you reach it, not just the
##     one you are standing in. The colours are copied from
##     assets/shaders/ground.gdshader and checked against it by minimap_selfcheck:
##     a map that disagrees with the ground about where a band sits is worse than a
##     map with no colour (see BIOME_TINTS and _gather_terrain).
##   * The player as a triangle at the centre, rotated to the character's facing.
##   * The coin road centerline as a polyline, read straight out of the terrain's
##     existing station cache (see _gather_road below).
##   * Crocodiles within range as small red dots.
##   * Geo landmarks (Stonehenge, Giza, the Eiffel Tower — see endless_terrain's
##     GEO LANDMARKS banner) as small violet X marks, clamped to the rim and
##     dimmed when they are off the map. They are destinations, so a rim hint is
##     the point: at the default zoom most loaded landmarks are past the disc.
##   * Multiplayer teammates as dots in their own stable per-peer colour, clamped
##     to the rim (as a radial tick, not a blob) when they are off the map. Solo,
##     there is no teammate layer at all and nothing is drawn or scanned.
##   * World X / Z coordinates and the biome underfoot as text, with a "~ river ~"
##     marker while the player is standing in a wading band.
##
## ZOOM. +/- step through ZOOM_RADII (raw keycodes outside the input map, like the
## M toggle). The WIDGET NEVER CHANGES SIZE — what changes is how many metres the
## disc covers, and EVERY layer derives from the one shared factor `_map_scale()`
## (or the `_view_radius()` behind it): the road window, the crocodile dot radius,
## the teammate dots and their rim clamp. There is deliberately no second constant
## anywhere that means "how far the map reaches" — see `_view_radius()`.
##
## PERFORMANCE SHAPE (this is a web-build feature, so it is the design)
##   * Everything is recomputed on a throttled TICK_INTERVAL tick (~5 Hz), never
##     per frame — the same discipline as crocodile_lod_manager.gd's 9 Hz scan and
##     perf_overlay.gd's 4 Hz refresh.
##   * _draw() reads only the snapshot the tick left behind; it fetches nothing,
##     allocates nothing, and runs at the TICK rate, not the frame rate (~5 redraws
##     a second of one small control). The point buffers are PackedVector2Array
##     members written in place; only the road buffer ever resizes, and only when
##     the number of stations in a fixed-width window changes.
##   * Every drawing primitive was picked for its DRAW CALL count, measured against
##     a frozen world with the same counters perf_overlay.gd (F3) reads: one
##     polyline for the road rather than ~20 lines, one multiline for the whole
##     crocodile pack rather than one circle each, ONE multiline for every landmark
##     X on screen rather than a polygon each, one two-line string rather than
##     two, ONE multiline of run-length bars for the entire terrain field rather
##     than a rect per cell. Total cost of the map: +10 draw calls, +1 more while
##     any landmark is loaded (0 when none is), no measurable CPU change.
##   * The terrain field is the one layer with a real CPU cost: TERRAIN_GRID^2
##     `biome_at()` samples per TICK, measured at ~0.24 ms on desktop and ~1 ms in
##     the browser — once every 200 ms, against a 33 ms spike threshold. It is
##     sampled in `_gather_terrain()` into the same kind of reusable buffer every
##     other layer uses; `_draw()` never calls `biome_at()`, and minimap_selfcheck
##     measures that it doesn't.
##
## Toggle with M (a raw keycode like perf_overlay's F3 and motion_debug's F4, so it
## stays outside the project input map and can't collide with a gameplay action).

# ============================================================================
# CONFIGURATION
# ============================================================================

## Key that shows/hides the map. Raw keycode on purpose — this is a HUD toggle,
## not a gameplay control, so it deliberately lives outside project.godot's map.
const TOGGLE_KEYCODE: Key = KEY_M

## How often (seconds) the map re-reads the world and redraws. ~5 Hz: fast enough
## that the player dot never looks frozen, slow enough that the crocodile group
## scan and the road walk are invisible in a frame budget.
const TICK_INTERVAL: float = 0.2

## Zoom steps, in world metres from the centre of the map to its edge. The widget
## keeps its pixel size at every step; only the metres-per-pixel change.
## `ZOOM_DEFAULT_INDEX` is the 60 m the map shipped with — it comfortably covers
## the crocodile LOD sleep radius (45 m), so at the default zoom anything that
## could plausibly reach the player is on the map. Five steps: two in for reading
## a crowded camp, two out for finding where the road went.
const ZOOM_RADII: Array[float] = [30.0, 45.0, 60.0, 90.0, 130.0]
const ZOOM_DEFAULT_INDEX: int = 2

## Keys that step the zoom. Raw keycodes for the same reason TOGGLE_KEYCODE is one
## — a HUD control has no business in project.godot's gameplay input map. Both the
## main row and the numpad are accepted, and KEY_EQUAL is included because "+" is
## shift-equals on most layouts and nobody holds shift to zoom a map.
const ZOOM_IN_KEYCODES: Array[Key] = [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]
const ZOOM_OUT_KEYCODES: Array[Key] = [KEY_MINUS, KEY_KP_SUBTRACT]

## Radius of the drawn map disc, in pixels — 1.5x the 62 px the map shipped with.
## PIXELS ONLY. How many METRES the disc reaches is `_view_radius()` and is
## deliberately unchanged at every zoom step: growing the widget makes the same
## world bigger on screen, it does not show more of it. The terrain layer below is
## why it grew — a 15-cell grid across 62 px is 8 px cells, which reads as noise.
const MAP_RADIUS: float = 93.0

## Centre of the map disc within this control. `scenes/main.tscn` sizes the
## MinimapHUD control from these two numbers — its WIDTH must stay MAP_CENTER.x * 2,
## because the caption below the disc is centred across `size.x` and would otherwise
## drift off the disc's axis. `minimap_selfcheck` asserts the rect still holds both.
const MAP_CENTER := Vector2(101.0, 101.0)

## Fraction of the map's reach within which crocodiles get a dot — a FRACTION, not
## a metre count, so it follows the zoom instead of needing its own step table.
## Deliberately HALF the map's reach: the outer ring of the map is for the road,
## the inner disc is for threats. At the default zoom that is the 30 m the map
## shipped with, which covers everything that can currently see the player (the
## ordinary DETECTION_RADIUS is 15 m, a boss's is 25 m), while dotting the full
## radius would be ~80 red specks far from the origin, where croc density scales
## up — noise, not information.
const CROC_VIEW_FRACTION: float = 0.5

## Hard cap on crocodile dots, and the size of the dot buffer. CROC_VIEW_RADIUS
## covers ~1.1 chunks of ground, which holds 10 crocodiles near the origin and ~20
## at the far end of the density gradient, so this is a genuine safety bound rather
## than a limit the game reaches: it matters because the group is in spawn order,
## not distance order, so a cap that actually bit could drop the croc standing next
## to the player in favour of one 30 m away.
const MAX_CROC_DOTS: int = 40

## Hard cap on road centerline points. The window is 2 * `_view_radius()` metres
## wide and stations sit road_coin_spacing (6 m) apart, so ~21 points at the
## default zoom and ~44 fully zoomed out — but road_coin_spacing is an @export a
## designer can shrink, and an unbounded walk over a 0.1 m spacing would be
## thousands of points, so the walk is capped.
const MAX_ROAD_POINTS: int = 96

## Player arrow size in pixels (half-length along the facing direction).
const ARROW_LENGTH: float = 9.0
const ARROW_HALF_WIDTH: float = 6.0

## Crocodile dot radius in pixels.
const CROC_DOT_RADIUS: float = 2.6

## Teammate dot radius in pixels — bigger than a crocodile's, because there are at
## most three of them and they are the thing you are looking for.
const PEER_DOT_RADIUS: float = 3.6

## Hard cap on teammate dots, and the size of the dot buffers. The lobby caps a
## room at 4 members (`server/room.go`), so 3 is the real number; this is a bound
## on peer-supplied data, in the same spirit as every other bound on the relay.
const MAX_PEER_DOTS: int = 8

## Geo-landmark marker: half-length of each arm of the X, and the width the two
## crossing segments are stroked at. An X rather than a dot or a diamond outline
## because SHAPE is what survives at this size: a 4 px diamond outline is
## indistinguishable from the square blobs the crocodile and teammate layers draw,
## while a cross reads as "a marked site" at a glance and costs two segments.
const LANDMARK_MARK_RADIUS: float = 3.4
const LANDMARK_MARK_WIDTH: float = 1.6

## How far an X reaches from its own centre: the arm's half-DIAGONAL (its corners
## sit at (±arm, ±arm), so the reach is arm * sqrt(2), not arm) plus half the
## stroke width. THIS, never LANDMARK_MARK_RADIUS, is what the rim inset below
## subtracts — inset by the arm length alone and a clamped X pokes its corners
## ~1.4 px past the ring, which is precisely the "does not poke past the ring"
## rule the crocodile and teammate dots get for free by being horizontal segments
## as long as they are wide. Written as a literal multiplier because GDScript
## cannot call sqrt() in a const expression.
const LANDMARK_MARK_REACH: float = LANDMARK_MARK_RADIUS * 1.4142136 + LANDMARK_MARK_WIDTH * 0.5

## Hard cap on landmark markers, and the size of the landmark buffers. Landmarks
## are ~1 per 46 chunks and only 49 (web) to 121 (desktop) chunks are ever active,
## so the group holds typically 0-3 nodes: this is a genuine bound on a group
## another script fills, never a limit play reaches.
const MAX_LANDMARK_DOTS: int = 12

## Alpha a rim-clamped (off-map) landmark X is drawn at, relative to one on the
## map — the teammate tick's rule, for the teammate tick's reason: off the map is
## less certain information and must not out-shout a landmark you can walk to.
const LANDMARK_EDGE_ALPHA: float = 0.7

## Length in pixels of the radial tick an OFF-MAP teammate is drawn as. A dot
## clamped to the rim would read as a teammate standing exactly at the map's edge;
## a tick pointing outward along their bearing reads as "further, that way".
const PEER_EDGE_TICK: float = 7.0

## Alpha a rim-clamped teammate tick is drawn at, relative to an on-map dot. Off
## the map is less certain information, and it should not out-shout a teammate you
## can actually walk to.
const PEER_EDGE_ALPHA: float = 0.75

## On-widget touch zoom buttons: size in pixels, and the gap between them. Built
## only in a touch session (see `_build_zoom_buttons`).
const ZOOM_BUTTON_SIZE: float = 30.0
const ZOOM_BUTTON_GAP: float = 4.0

## Where unused crocodile dot slots are parked. Well outside the control on both
## axes, so the segments drawn there land off-screen no matter where the HUD puts
## this control (offsets only ever move it right and down from the viewport corner).
const PARKED_SEGMENT := Vector2(-4000.0, -4000.0)

## Road line width in pixels.
const ROAD_WIDTH: float = 2.5

## Text block: font size, and the gap from the bottom of the disc to its baseline.
const TEXT_SIZE: int = 15
const TEXT_TOP_GAP: float = 18.0

## Terrain layer: biome samples per axis across the disc's bounding square.
##
## COARSE ON PURPOSE. The biome field has a 400 m wavelength (BIOME_CELL_SIZE, ~8
## chunks) while the disc reaches 30-130 m, so the whole map is a fraction of one
## noise cell: a fine grid resolves nothing a coarse one misses, it just costs
## samples. 15 is picked from the other end instead — it is the coarsest grid whose
## cells (2 * MAP_RADIUS / 15 = 12.4 px) still read as a band rather than as
## chequerboard — and being ODD puts a row and a column exactly on the centre, so
## the cell under the player arrow is a real sample and not an interpolation of two.
##
## MEASURED COST (desktop, Godot 4.5): 177 of the 225 cells fall inside the disc and
## `biome_at()` costs ~1.35 us, so a tick spends ~0.24 ms sampling — 1.2 ms per
## second at the 5 Hz tick rate. Web GDScript runs this maybe 2-4x slower, so
## ~0.5-1.0 ms once every 200 ms; the spike log's threshold is 33 ms.
const TERRAIN_GRID: int = 15

## Side of one terrain cell in pixels — DERIVED, never a second number: it is the
## disc's own diameter cut into TERRAIN_GRID. It is also the draw width of the
## horizontal bars the layer is painted with, which is what makes the rows tile.
const TERRAIN_CELL: float = MAP_RADIUS * 2.0 / TERRAIN_GRID

## Alpha every terrain cell is painted at. The RGB comes from the ground shader
## (see BIOME_TINTS); this is the map's own dimming, and the only part of the
## colour that is ours: the terrain is a BACKDROP for the road, the dots and the
## arrow, and it must never out-shout them. 0.55 is what the single whole-disc
## tint this layer replaced was already drawn at.
const TERRAIN_ALPHA: float = 0.55

# --- Colours ----------------------------------------------------------------
const COLOR_BACKDROP := Color(0.0, 0.0, 0.0, 0.5)   # dark disc under everything
const COLOR_RIM := Color(1, 1, 1, 0.35)              # thin ring round the disc

## Width of that ring in pixels. The rim is a slightly LARGER filled circle drawn
## underneath the disc rather than a draw_arc(): an antialiased arc cost 3 draw
## calls on its own where a plain filled circle costs 1, and at 1.5 px the two are
## indistinguishable.
const RIM_WIDTH: float = 1.5
const COLOR_ROAD := Color(1.0, 0.85, 0.15, 0.9)      # coin gold, matches the coins
const COLOR_CROC := Color(0.95, 0.25, 0.2, 0.95)     # threat red, matches the vignette
const COLOR_PLAYER := Color(0.4, 0.95, 1.0, 1.0)     # cyan, nothing else on the map is
## Violet, deliberately away from every other hue on the disc — the road's gold,
## the crocodiles' red, the player's cyan — and legible on all four biome tints.
const COLOR_LANDMARK := Color(0.85, 0.55, 1.0, 0.95)
const COLOR_TEXT := Color(1, 1, 1, 0.95)
const COLOR_RIVER_TEXT := Color(0.45, 0.75, 1.0, 0.95)

## The terrain palette, indexed by endless_terrain's Biome enum (PLAINS, DESERT,
## FOREST, MOUNTAIN, CITY, SNOW — the declaration order, which is what the int we
## get across the group boundary means).
##
## EVERY RGB HERE IS COPIED FROM assets/shaders/ground.gdshader AND IS NOT OURS TO
## RETUNE. The shader is where the ground's colour is decided; a map that invents
## its own greens tells the player the desert is somewhere it isn't, which is worse
## than a map with no colour at all. So this is a THIRD copy of the same parity
## discipline `_biome_noise` already carries (see the CPU/GPU parity contract in
## endless_terrain.gd): mirrored by hand, and checked by machine —
## `minimap_selfcheck.gd` parses the shader's uniform defaults and fails if any row
## here has drifted from them. PLAINS has no uniform of its own: the shader mottles
## between `green_a` and `green_b` per vertex, so the map uses their midpoint, which
## is what that mottle averages to.
##
## The ALPHA is ours (TERRAIN_ALPHA) — the shader paints the world, we paint a
## backdrop that the road, the dots and the arrow have to stay legible on top of.
const BIOME_TINTS: Array[Color] = [
	Color(0.31, 0.495, 0.25, TERRAIN_ALPHA),  # PLAINS   — midpoint of green_a/green_b
	Color(0.78, 0.68, 0.44, TERRAIN_ALPHA),   # DESERT   — desert_color
	Color(0.13, 0.30, 0.17, TERRAIN_ALPHA),   # FOREST   — forest_color
	Color(0.45, 0.43, 0.40, TERRAIN_ALPHA),   # MOUNTAIN — mountain_color
	Color(0.50, 0.48, 0.45, TERRAIN_ALPHA),   # CITY     — city_color
	Color(0.85, 0.89, 0.93, TERRAIN_ALPHA),   # SNOW     — snow_color
]
## Indexed by endless_terrain.Biome, so the ORDER here is the enum's integer
## order and NOT the order the bands sit in the noise field — CITY is appended
## because the enum appends it (its band lies between plains and forest), and SNOW
## is appended after it (its band is the topmost, above mountain).
const BIOME_NAMES: Array[String] = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN", "CITY", "SNOW"]

# ============================================================================
# STATE (written by the tick, read by _draw — they never disagree)
# ============================================================================

## Cached node references, re-fetched when they go away (respawn, restart, a scene
## run without one of them).
var _player: Node3D = null
var _terrain: Node = null
## The multiplayer manager, found in the "mp" group with a has_method() guard like
## every other reach across a system boundary here. Null in a scene without one,
## and `peer_markers()` answers null while offline — both mean "no teammate layer".
var _mp: Node = null

## Index into ZOOM_RADII. Session-only by design: a map zoom is a glance-scale
## preference, not a setting, and the project already has two ConfigFiles whose
## web persistence is documented as flaky. Nothing writes it to disk.
var _zoom_index: int = ZOOM_DEFAULT_INDEX

## Seconds until the next tick.
var _time_until_tick: float = 0.0

## False until the first successful read of the player — _draw() then renders
## nothing rather than leaving a stale map painted.
var _have_data: bool = false

## Snapshot of the player.
var _player_pos: Vector3 = Vector3.ZERO
## Player facing as a screen-space unit vector (+X right, +Z down), already mapped
## out of the 3D basis so _draw() does no trigonometry.
var _facing: Vector2 = Vector2(1.0, 0.0)

## Snapshot of the world under the player.
var _biome: int = 0
var _in_river: bool = false

## The terrain layer, in the same "segment pairs for ONE draw call" form the
## teammate and landmark buffers use: each entry is a HORIZONTAL BAR — a run of
## same-biome grid cells along one row, drawn through `draw_multiline_colors()` at
## a width of TERRAIN_CELL so consecutive rows tile into a solid field. One colour
## per SEGMENT, so `_terrain_colors` is half the length of `_terrain_points`.
##
## RUN-LENGTH IS WHAT KEEPS THIS ONE DRAW CALL AND CHEAP TO FILL: the biome field
## is smooth at this scale, so a row is normally one or two runs, not fifteen —
## but the buffers are sized for the worst case (every cell its own run) so the
## tick never allocates and there is no cap that could ever bite and silently drop
## part of the map. The unused tail is parked off-control and transparent, exactly
## like the crocodile, teammate and landmark tails.
var _terrain_points: PackedVector2Array = PackedVector2Array()
var _terrain_colors: PackedColorArray = PackedColorArray()
var _terrain_count: int = 0

## Road centerline in ABSOLUTE control-space pixels, already clamped inside the map
## disc, ready to hand straight to ONE draw_polyline(). It is resized only when the
## number of stations in the window changes (the window is a fixed width, so that
## settles within a tick or two and then never allocates again). The exact-length
## array is what buys the single draw call: draw_polyline() takes the whole array,
## so a spare-capacity buffer plus a count would need a slice — an allocation per
## draw — or N separate draw_line() calls, which is what this replaced.
var _road_points: PackedVector2Array = PackedVector2Array()
var _road_count: int = 0

## Crocodile dots as absolute-pixel LINE SEGMENT PAIRS (two entries per dot), for
## one draw_multiline(). Unlike the road buffer this one is permanently sized to
## MAX_CROC_DOTS and never resized — the dot count changes on most ticks, so a
## resize-to-fit would mean a reallocation on most ticks; the unused tail is parked
## off-control instead (see PARKED_SEGMENT).
var _croc_points: PackedVector2Array = PackedVector2Array()
var _croc_count: int = 0

## The player arrow's three corners, rewritten each _draw() rather than rebuilt —
## draw_colored_polygon() takes a PackedVector2Array, and constructing one per
## draw would be the feature's only steady-state allocation.
var _arrow_points: PackedVector2Array = PackedVector2Array()

## Teammate dots, in the same "segment pairs for ONE draw call" form the crocodile
## buffer uses — but through `draw_multiline_colors()`, because each teammate has
## its own stable colour and `draw_multiline()` takes exactly one. That variant
## wants ONE COLOUR PER SEGMENT (`colors.size() * 2 == points.size()`), which is
## why `_peer_colors` is half the length of `_peer_points`. Both are sized once to
## MAX_PEER_DOTS and never resized; the unused tail is parked off-control (and
## transparent) exactly like the crocodile tail.
var _peer_points: PackedVector2Array = PackedVector2Array()
var _peer_colors: PackedColorArray = PackedColorArray()
var _peer_count: int = 0

## Landmark X marks, in the teammate buffers' form with one difference: each marker
## is TWO segments (the crossing arms), so it is FOUR points and TWO colours, and
## `_landmark_colors` is again half the length of `_landmark_points` because
## `draw_multiline_colors()` wants one colour per SEGMENT. Both are sized once to
## MAX_LANDMARK_DOTS and never resized; the unused tail is parked off-control and
## transparent exactly like the crocodile and teammate tails. The per-segment
## colour is what carries the dimmed rim clamp through the SAME single draw call.
var _landmark_points: PackedVector2Array = PackedVector2Array()
var _landmark_colors: PackedColorArray = PackedColorArray()
var _landmark_count: int = 0


func _ready() -> void:
	# Never let the map eat clicks meant for the game or the touch UI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Group registration so anything could find/toggle us later without a hard
	# reference (same convention as perf_overlay.gd).
	add_to_group("minimap")
	# The arrow is always exactly three corners, so size it once and never again.
	_arrow_points.resize(3)
	# The crocodile buffer is sized ONCE to its hard cap and never resized: see
	# PARKED_SEGMENT for how the unused tail is kept out of the picture.
	_croc_points.resize(MAX_CROC_DOTS * 2)
	# Same discipline for the teammate buffers — two points and ONE colour per dot.
	_peer_points.resize(MAX_PEER_DOTS * 2)
	_peer_colors.resize(MAX_PEER_DOTS)
	# And for the landmarks — FOUR points and TWO colours per X (two segments).
	_landmark_points.resize(MAX_LANDMARK_DOTS * 4)
	_landmark_colors.resize(MAX_LANDMARK_DOTS * 2)
	# The terrain field: worst case is every cell its own run, i.e. one bar per
	# cell — two points and one colour each. Sized once here for that worst case so
	# the tick never allocates and no run is ever dropped (see _gather_terrain).
	_terrain_points.resize(TERRAIN_GRID * TERRAIN_GRID * 2)
	_terrain_colors.resize(TERRAIN_GRID * TERRAIN_GRID)
	_build_zoom_buttons()


func _input(event: InputEvent) -> void:
	# Raw keycode read (not a named action) — see TOGGLE_KEYCODE.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEYCODE:
			visible = not visible
			if visible:
				# Refresh immediately so it reappears with live data, not the
				# snapshot from whenever it was hidden.
				_time_until_tick = 0.0
			return
		# Zoom only while the map is up: with it hidden there is nothing to zoom,
		# and silently eating +/- from a hidden HUD is how a key ends up "not
		# working" somewhere else later.
		if not visible:
			return
		if ZOOM_IN_KEYCODES.has(event.keycode):
			_zoom_by(-1)
		elif ZOOM_OUT_KEYCODES.has(event.keycode):
			_zoom_by(1)


func _zoom_by(step: int) -> void:
	"""Step the zoom, clamped at both ends. `step` is a move through ZOOM_RADII, so
	-1 zooms IN (a smaller world radius) and +1 zooms out."""
	var next := clampi(_zoom_index + step, 0, ZOOM_RADII.size() - 1)
	if next == _zoom_index:
		return
	_zoom_index = next
	# Re-read on the next frame rather than at the tick's leisure: a zoom is a
	# deliberate press and a fifth of a second of the old scale reads as lag.
	_time_until_tick = 0.0


func _view_radius() -> float:
	"""World metres from the centre of the disc to its rim, at the current zoom.

	THIS AND `_map_scale()` ARE THE ONLY PLACES THE MAP'S REACH IS DEFINED. Every
	layer — the road window, the crocodile radius (a fraction of this), the
	teammate dots and their rim clamp — derives from one of the two. A layer that
	hardcodes a metre count instead is a layer that silently stops agreeing with
	the picture at every zoom but the default, which is exactly what
	`minimap_selfcheck.gd`'s zoom checks are written to catch."""
	return ZOOM_RADII[_zoom_index]


func _map_scale() -> float:
	"""Pixels per world metre at the current zoom."""
	return MAP_RADIUS / _view_radius()


func _croc_view_radius() -> float:
	"""World metres within which a crocodile gets a dot — a fraction of the map's
	reach, so it follows the zoom (see CROC_VIEW_FRACTION)."""
	return _view_radius() * CROC_VIEW_FRACTION


func _build_zoom_buttons() -> void:
	"""A small +/- pair on the widget, for a phone with no keyboard.

	Gated on `MobileSensors.is_touch_session()` exactly like the rest of the touch
	UI, so on desktop these are never created and the map is byte-for-byte the
	control it was. FOCUS_NONE is not cosmetic: `ui_accept` is Space, Space is
	jump, and a focused button would fire on every jump for the rest of the run —
	the same rule `mp_ui._make_button()` documents. The labels are "+" and "-",
	which are symbols in every locale, so there is no CSV row to add."""
	if not MobileSensors.is_touch_session():
		return
	# Bottom-right of the disc, stacked so a thumb can reach both without covering
	# the player arrow at the centre.
	var right := MAP_CENTER.x + MAP_RADIUS - ZOOM_BUTTON_SIZE * 0.5
	var top := MAP_CENTER.y + MAP_RADIUS - ZOOM_BUTTON_SIZE * 2.0 - ZOOM_BUTTON_GAP
	_add_zoom_button("+", Vector2(right, top), -1)
	_add_zoom_button("-", Vector2(right, top + ZOOM_BUTTON_SIZE + ZOOM_BUTTON_GAP), 1)


func _add_zoom_button(label: String, at: Vector2, step: int) -> void:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE  # see _build_zoom_buttons
	button.position = at
	button.size = Vector2(ZOOM_BUTTON_SIZE, ZOOM_BUTTON_SIZE)
	button.pressed.connect(_zoom_by.bind(step))
	add_child(button)


func _process(delta: float) -> void:
	# Hidden costs nothing at all.
	if not visible:
		return
	_time_until_tick -= delta
	if _time_until_tick > 0.0:
		return
	_time_until_tick = TICK_INTERVAL
	_tick()


func _tick() -> void:
	"""Re-read the world into the snapshot _draw() paints from. This is the only
	place that touches the scene tree; it runs ~5 times a second."""
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		# No player — clear the map once instead of leaving a stale one painted.
		if _have_data:
			_have_data = false
			queue_redraw()
		return

	_player_pos = _player.global_position
	# Godot's convention: -Z is a body's forward. Reading it off the basis rather
	# than rebuilding it from rotation.y keeps us correct whatever the controller
	# does with its transform, and costs no sin/cos.
	var forward := -_player.global_transform.basis.z
	# World (x, z) maps to screen (x, y): north-up, +X right, +Z down.
	var facing := Vector2(forward.x, forward.z)
	_facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector2(1.0, 0.0)

	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = get_tree().get_first_node_in_group("terrain")

	_gather_world()
	_gather_terrain()
	_gather_road()
	_gather_crocodiles()
	_gather_landmarks()
	_gather_peers()

	_have_data = true
	queue_redraw()


func _gather_world() -> void:
	"""Biome + river underfoot: exactly TWO noise evaluations per tick.

	Both are pure functions of world position (endless_terrain documents them as
	safe to call every physics tick), so this is genuinely cheap. `_biome` is still
	read here, and separately from the terrain grid `_gather_terrain()` samples,
	because the CAPTION must name the biome the player is actually standing in — a
	grid cell is 12 px of map and its centre is not the player.

	RIVER BANDS ARE STILL NOT DRAWN, and now for a sharper reason than cost. A river
	is a ~8 m contour of the same field, which is 12 px at the default zoom — one
	TERRAIN_CELL. Sampling it on the terrain grid would catch roughly every other
	cell a river crosses, i.e. paint blue confetti along a line that is not the
	line, and a map that puts the water in the wrong place is exactly the failure
	the CPU/GPU parity contract exists to prevent. So the river stays what it was:
	the honest "~ river ~" caption for the band you are standing in. ponytail: if
	river bands are ever wanted on the disc they need contour tracing off the raw
	field value, not a denser grid — a denser grid only makes the confetti finer."""
	_biome = 0
	_in_river = false
	if _terrain == null:
		return
	if _terrain.has_method("biome_at"):
		var b: int = _terrain.biome_at(_player_pos.x, _player_pos.z)
		# Defensive clamp: the enum arrives as a plain int across the group
		# boundary, and it indexes our colour/name tables.
		_biome = clampi(b, 0, BIOME_NAMES.size() - 1)
	if _terrain.has_method("is_river_at"):
		_in_river = _terrain.is_river_at(_player_pos)


func _gather_terrain() -> void:
	"""Paint the biome FIELD across the disc — the map's bottom layer.

	WHY A GRID AT ALL. The map used to tint the whole disc with the ONE biome under
	the player, which answers "what am I in" and nothing about "what am I walking
	toward". The field is what the player steers by, so the field is what gets drawn.

	SHAPE OF THE WORK, and why it fits the tick budget:
	  * TERRAIN_GRID x TERRAIN_GRID cells over the disc's bounding square, and only
	    the ~78% whose centre falls inside the disc are sampled at all — 177 of 225
	    `biome_at()` calls, ~0.24 ms (see TERRAIN_GRID for the measurement).
	  * Each ROW is emitted as RUN-LENGTH bars: consecutive cells of the same biome
	    become ONE horizontal segment. The field is smooth at this scale so a row is
	    normally one or two bars, and the whole layer is ONE
	    `draw_multiline_colors()` at TERRAIN_CELL width — the same draw-call
	    discipline as the crocodile pack and the landmark X marks, and exactly the
	    same cost as the single tinted circle it replaces.
	  * Each row is clipped to the disc by its own CHORD, so the layer keeps the
	    circular silhouette instead of painting a square. The steps that leaves at
	    the rim are one cell tall and sit inside the smooth dark backdrop circle
	    that is still drawn underneath.

	EVERYTHING GEOMETRIC HERE COMES FROM MAP_RADIUS AND `_map_scale()`. TERRAIN_CELL
	is the disc's own diameter cut into TERRAIN_GRID and the world extent of a cell
	is that over the shared scale, so the grid covers exactly the disc at every zoom
	and there is no second number meaning "how far the map reaches"."""
	_terrain_count = 0
	# A scene with no terrain (or an older one without the API) simply has no
	# terrain layer — the dark backdrop disc underneath is what shows through.
	if _terrain != null and _terrain.has_method("biome_at"):
		# World metres per pixel — the inverse of the ONE shared scale factor.
		var metres_per_px := 1.0 / _map_scale()
		var origin := MAP_CENTER - Vector2(MAP_RADIUS, MAP_RADIUS)
		var half_cell := TERRAIN_CELL * 0.5
		for j in range(TERRAIN_GRID):
			var py := origin.y + (float(j) + 0.5) * TERRAIN_CELL
			var dy := py - MAP_CENTER.y
			# The chord at the bar's OUTER EDGE, never at its centre line. A bar is
			# TERRAIN_CELL tall, so clipping it to the centre-line chord hangs its
			# outer corners several pixels past the ring — the same "the mark's ink,
			# not its anchor" rule LANDMARK_MARK_REACH states for the landmark X.
			# The price is that the outermost row of the grid always comes out empty
			# (its outer edge sits exactly on the rim), so the field has a one-cell
			# flat cap top and bottom, over the dark backdrop disc that is still a
			# true circle. A cap inside the ring beats ink outside it.
			var edge := absf(dy) + half_cell
			var chord_sq := MAP_RADIUS * MAP_RADIUS - edge * edge
			if chord_sq <= 0.0:
				continue  # row's bar would not fit inside the disc
			var chord := sqrt(chord_sq)
			var left_limit := MAP_CENTER.x - chord
			var right_limit := MAP_CENTER.x + chord
			# The cells whose CENTRE falls inside the chord, solved directly rather
			# than tested per cell: centre i sits at origin.x + (i + 0.5) * CELL.
			var i0 := maxi(int(ceil((left_limit - origin.x) / TERRAIN_CELL - 0.5)), 0)
			var i1 := mini(int(floor((right_limit - origin.x) / TERRAIN_CELL - 0.5)), TERRAIN_GRID - 1)
			if i0 > i1:
				continue
			var world_z := _player_pos.z + dy * metres_per_px
			var run_biome := -1
			var run_left := 0.0
			for i in range(i0, i1 + 1):
				var px := origin.x + (float(i) + 0.5) * TERRAIN_CELL
				# The enum arrives as a plain int across the group boundary and
				# indexes our palette, so it is clamped like `_gather_world` does.
				var b: int = clampi(_terrain.biome_at(_player_pos.x + (px - MAP_CENTER.x) * metres_per_px,
					world_z), 0, BIOME_TINTS.size() - 1)
				if b == run_biome:
					continue  # extend the open run; nothing to emit yet
				if run_biome >= 0:
					_push_terrain_bar(run_left, px - half_cell, py, run_biome)
				run_biome = b
				# The first run of the row starts at the chord, not at its cell edge.
				run_left = maxf(px - half_cell, left_limit)
			# Flush the open run, ended at the chord for the same reason.
			_push_terrain_bar(run_left,
				minf(origin.x + (float(i1) + 1.0) * TERRAIN_CELL, right_limit), py, run_biome)
	# Park the unused tail off-control and transparent, for the reason every other
	# layer here parks its tail: the buffers are permanently sized so the tick never
	# allocates, and `draw_multiline_colors()` consumes the whole array. Parking the
	# WHOLE tail rather than only the slots that just went out of use was measured
	# and kept: it is ~5% of this layer's tick, and it is one fewer piece of state
	# than a high-water mark that four sibling layers here manage to live without.
	for i in range(_terrain_count * 2, _terrain_points.size()):
		_terrain_points[i] = PARKED_SEGMENT
	for i in range(_terrain_count, _terrain_colors.size()):
		_terrain_colors[i] = Color(0, 0, 0, 0)


func _push_terrain_bar(x0: float, x1: float, y: float, biome: int) -> void:
	"""Emit one run of same-biome cells as a horizontal bar. Zero-width runs (a run
	whose whole cell was clipped away by the chord) are dropped rather than emitted
	as a degenerate segment. The buffers are sized for one bar per cell, so there is
	no bound to check here and no run that can ever be silently lost."""
	if x1 <= x0 or biome < 0:
		return
	var p := _terrain_count * 2
	_terrain_points[p] = Vector2(x0, y)
	_terrain_points[p + 1] = Vector2(x1, y)
	_terrain_colors[_terrain_count] = BIOME_TINTS[biome]
	_terrain_count += 1


func _gather_road() -> void:
	"""Walk the terrain's EXISTING coin-road station cache across the map window.

	No road maths is duplicated and no cache is extended: the stations covering the
	player's own chunk are already cached (spawn_coins_in_chunk built them when the
	chunk loaded, and the cache is contiguous and never reset within a run), and the
	binary search is the terrain's own O(log n) helper. Anything outside the cached
	range is simply not drawn — a soft, silent degradation rather than a hitch.

	Stations step _road_spacing() (6 m) apart, so a 120 m window is ~20 points."""
	_road_count = 0
	# _road_points IS the draw buffer, so an empty window has to empty it too —
	# leaving the last window's points in place would paint a stale road.
	if _terrain == null or not _terrain.has_method("_road_first_k_at_or_after_x"):
		_road_points.resize(0)
		return
	var stations: Dictionary = _terrain.road_stations
	if stations.is_empty():
		_road_points.resize(0)
		return
	var k_min: int = _terrain.road_k_min
	var k_max: int = _terrain.road_k_max
	# The window is the map's reach at the CURRENT zoom, in both directions —
	# never a hardcoded metre count. See `_view_radius()`.
	var view := _view_radius()
	var k: int = _terrain._road_first_k_at_or_after_x(_player_pos.x - view)
	# The helper returns k_max + 1 when the whole cache lies left of us; clamping
	# to k_min also covers the case where our window starts before the cache.
	k = maxi(k, k_min)
	var x_limit := _player_pos.x + view
	var scale := _map_scale()
	# The road runs far enough in X to fill the window, but its Z can wander well
	# outside the disc, so each point is clamped to the rim rather than clipped: a
	# clamped point still shows the direction the road leaves in, and keeping the
	# polyline unbroken is what keeps it ONE draw call.
	var rim := MAP_RADIUS - ROAD_WIDTH * 0.5
	# Count first, resize once (only when the count actually changed), then fill.
	var k_start := k
	while k <= k_max and _road_count < MAX_ROAD_POINTS:
		var center: Vector2 = stations[k].center
		if center.x > x_limit:
			break
		_road_count += 1
		k += 1
	if _road_points.size() != _road_count:
		_road_points.resize(_road_count)
	for i in range(_road_count):
		# Station centres are (x, z) in world space; the same north-up mapping the
		# player arrow uses.
		var c: Vector2 = stations[k_start + i].center
		var p := Vector2(c.x - _player_pos.x, c.y - _player_pos.z) * scale
		_road_points[i] = MAP_CENTER + p.limit_length(rim)


func _gather_crocodiles() -> void:
	"""Crocodile dots, on THIS control's ~5 Hz tick — never a per-frame scan.

	The "crocodile" group holds every spawned croc in the active chunk field (the
	LOD manager sleeps the distant ones but never removes them), so this is one
	group fetch plus a squared-distance compare each; no square roots, and the
	positions land in a reused buffer. Reading the LOD manager's own 9 Hz scan
	instead would save this pass, but it would also mean a new cross-file contract
	for something this cheap.

	Each dot is stored as a short LINE SEGMENT (two points), not a centre: _draw()
	hands the whole array to one draw_multiline(), which is the difference between
	one draw call and one per crocodile. Measured with the F3 counters, draw_circle()
	per dot cost exactly 1 draw call each — fine at the 6 near the spawn point,
	40 out where the density gradient has ramped up."""
	_croc_count = 0
	var scale := _map_scale()
	var croc_view := _croc_view_radius()
	var radius_sq := croc_view * croc_view
	# Segment length is set EQUAL to the draw width below, so each dot rasterises as
	# a square blob. Halving it (the obvious "short stub") drew tall thin bars.
	var half := CROC_DOT_RADIUS
	for node in get_tree().get_nodes_in_group("crocodile"):
		if _croc_count >= MAX_CROC_DOTS:
			break
		var croc := node as Node3D
		if croc == null:
			continue
		var pos := croc.global_position
		var dx := pos.x - _player_pos.x
		var dz := pos.z - _player_pos.z
		if dx * dx + dz * dz > radius_sq:
			continue
		# A segment as long as it is wide: a dot, for one draw call across the pack.
		var c := MAP_CENTER + Vector2(dx, dz) * scale
		_croc_points[_croc_count * 2] = c - Vector2(half, 0.0)
		_croc_points[_croc_count * 2 + 1] = c + Vector2(half, 0.0)
		_croc_count += 1
	# draw_multiline() consumes the WHOLE array, and this one is permanently sized to
	# MAX_CROC_DOTS so the tick never allocates — so the unused tail is parked far
	# outside the control instead of being truncated away. A resize-to-fit here would
	# realloc on every tick where the dot count changed, which is most of them.
	for i in range(_croc_count * 2, _croc_points.size()):
		_croc_points[i] = PARKED_SEGMENT


func _gather_landmarks() -> void:
	"""Geo landmarks, on the same ~5 Hz tick — the map's "where is there something
	worth walking to" layer.

	The draw set needs no bookkeeping at all: `spawn_landmark_in_chunk` parents a
	mesh-free, script-free marker Node3D to the chunk and puts it in the "landmark"
	group, so the group holds exactly the landmarks whose chunks are loaded and a
	landmark that streams back in re-registers itself. Reading position off the node
	is the whole contract used here — the `name_key` / `fact_key` / `radius` metas
	belong to landmark_toast.gd, and a marker is deliberately mute on the map (the
	toast already names it on approach), so nothing here reads a meta and nothing
	here adds a string.

	Each marker is an X: two crossing SEGMENTS, so the whole set is ONE
	`draw_multiline_colors()` — the crocodile pack's draw-call discipline, through
	the `_colors` variant for the same reason the teammate layer uses it, since the
	rim clamp needs a per-marker alpha and `draw_multiline()` takes exactly one
	colour.

	OFF-MAP LANDMARKS ARE CLAMPED TO THE RIM AND DIMMED, not dropped, and unlike a
	teammate they stay an X rather than becoming a radial tick. A landmark does not
	move, so "further, that way" is answered by walking toward the mark and watching
	it slide inward; what a tick WOULD cost is the shape that says "monument"
	instead of "peer". Dropping them was the other option and it is the wrong one:
	the group spans the whole loaded field (~150 m on web, ~250 m on desktop) while
	the disc reaches 30-130 m, so at the default zoom most loaded landmarks are off
	it and the layer would be blank almost all the time."""
	_landmark_count = 0
	var scale := _map_scale()
	var arm := LANDMARK_MARK_RADIUS
	for node in get_tree().get_nodes_in_group("landmark"):
		if _landmark_count >= MAX_LANDMARK_DOTS:
			break
		var marker := node as Node3D
		if marker == null:
			continue
		# Same north-up mapping as every other layer, off the SAME shared scale:
		# world (x, z) → screen (x, y). See `_view_radius()`.
		var offset := Vector2(marker.global_position.x - _player_pos.x,
			marker.global_position.z - _player_pos.z) * scale
		var color := COLOR_LANDMARK
		var center: Vector2
		var dist := offset.length()
		if dist > MAP_RADIUS:
			# OFF THE MAP — classified against the DISC EDGE itself, never against
			# the inset the mark is drawn at, for the reason `_gather_peers` spells
			# out: testing against the inset declares the outer band of the disc
			# off-map and dims a landmark you can actually see. The division is safe
			# — this branch needs dist > MAP_RADIUS > 0.
			center = MAP_CENTER + (offset / dist) * (MAP_RADIUS - LANDMARK_MARK_REACH)
			color.a *= LANDMARK_EDGE_ALPHA
		else:
			# ON the map, pulled in by the mark's own REACH (see LANDMARK_MARK_REACH
			# — the corner, not the arm) so an X at the very edge of the view does
			# not poke past the ring. That moves it by at most that reach and never
			# changes the classification above.
			center = MAP_CENTER + offset.limit_length(MAP_RADIUS - LANDMARK_MARK_REACH)
		var p := _landmark_count * 4
		_landmark_points[p] = center + Vector2(-arm, -arm)
		_landmark_points[p + 1] = center + Vector2(arm, arm)
		_landmark_points[p + 2] = center + Vector2(-arm, arm)
		_landmark_points[p + 3] = center + Vector2(arm, -arm)
		_landmark_colors[_landmark_count * 2] = color
		_landmark_colors[_landmark_count * 2 + 1] = color
		_landmark_count += 1
	# Park the unused tail off-control and transparent, for the reason the crocodile
	# and teammate tails are parked: the buffers are permanently sized so the tick
	# never allocates, and `draw_multiline_colors()` consumes the whole array.
	for i in range(_landmark_count * 4, _landmark_points.size()):
		_landmark_points[i] = PARKED_SEGMENT
	for i in range(_landmark_count * 2, _landmark_colors.size()):
		_landmark_colors[i] = Color(0, 0, 0, 0)


func _gather_peers() -> void:
	"""Multiplayer teammates, on the same ~5 Hz tick.

	Solo this is one group lookup and one `== null` test: `MpManager.peer_markers()`
	answers null whenever there is no room, so the whole layer costs nothing and
	draws nothing — the map is byte-for-byte what it was before multiplayer. The
	reach across the boundary is the project's standard group lookup plus a
	has_method() guard, so a scene without the manager (or an older build of it)
	simply has no teammate layer rather than erroring.

	Each teammate becomes one segment pair plus one colour, for a SINGLE
	`draw_multiline_colors()` across the whole room — the crocodile pack's
	draw-call discipline, with the per-peer colour that `draw_multiline()` cannot
	carry. Off-map teammates are CLAMPED to the rim rather than dropped, and
	drawn as an outward radial tick instead of a blob, so the map still answers
	"which way is my team" when they are a chunk away."""
	_peer_count = 0
	if _mp == null or not is_instance_valid(_mp):
		_mp = get_tree().get_first_node_in_group("mp")
	if _mp != null and _mp.has_method("peer_markers"):
		var markers: Variant = _mp.peer_markers()
		if markers is Array:
			var scale := _map_scale()
			# OFF-MAP IS CLASSIFIED AGAINST THE DISC EDGE ITSELF, never against an
			# inset. The two are easy to conflate — the tick has to START inset so
			# it does not poke past the ring — but using the inset as the TEST too
			# declares the outer band of the map off-map: at MAP_RADIUS 62 and a
			# PEER_EDGE_TICK 7 inset, a teammate anywhere in the outer 11% of the
			# disc (54-60 m at the default zoom) would be drawn as an outward "keep
			# going that way" tick while actually standing inside the view.
			for entry: Variant in markers:
				if _peer_count >= MAX_PEER_DOTS:
					break
				if not (entry is Dictionary):
					continue
				var marker: Dictionary = entry
				var pos: Vector3 = marker.get("pos", Vector3.ZERO)
				var color: Color = marker.get("color", COLOR_PLAYER)
				var offset := Vector2(pos.x - _player_pos.x, pos.z - _player_pos.z) * scale
				var a: Vector2
				var b: Vector2
				var dist := offset.length()
				if dist > MAP_RADIUS:
					# OFF THE MAP: a tick ending ON the rim and pointing out along
					# the bearing. Only the tick's own length is inset (the division
					# is safe — this branch needs dist > MAP_RADIUS > 0).
					var dir := offset / dist
					a = MAP_CENTER + dir * (MAP_RADIUS - PEER_EDGE_TICK)
					b = MAP_CENTER + dir * MAP_RADIUS
					color.a *= PEER_EDGE_ALPHA
				else:
					# ON the map: a segment as long as it is wide, i.e. a dot — the
					# same trick the crocodile dots use. The centre is pulled in by
					# the dot's own radius so a teammate right at the view's edge
					# does not have their blob poke past the ring; that moves the
					# dot by at most PEER_DOT_RADIUS and never changes the
					# on-map/off-map classification above.
					var c := MAP_CENTER + offset.limit_length(MAP_RADIUS - PEER_DOT_RADIUS)
					a = c - Vector2(PEER_DOT_RADIUS, 0.0)
					b = c + Vector2(PEER_DOT_RADIUS, 0.0)
				_peer_points[_peer_count * 2] = a
				_peer_points[_peer_count * 2 + 1] = b
				_peer_colors[_peer_count] = color
				_peer_count += 1
	# Park the unused tail off-control and transparent, for the reason the
	# crocodile tail is parked: the buffers are permanently sized so the tick never
	# allocates, and `draw_multiline_colors()` consumes the whole array.
	for i in range(_peer_count * 2, _peer_points.size()):
		_peer_points[i] = PARKED_SEGMENT
	for i in range(_peer_count, _peer_colors.size()):
		_peer_colors[i] = Color(0, 0, 0, 0)


# ============================================================================
# DRAWING (snapshot only — no node lookups, no allocation)
# ============================================================================

func _draw() -> void:
	if not _have_data:
		return

	# 1. The backdrop, painted outside-in: rim ring, dark disc, then the biome FIELD.
	#    Two filled circles — see RIM_WIDTH for why the rim is not a draw_arc() —
	#    plus ONE multiline for the whole terrain layer, which is the same draw-call
	#    cost as the single whole-disc tint circle it replaced. The dark disc stays
	#    underneath: it is what gives the map its smooth circular edge (the terrain
	#    rows are chord-clipped, so their own silhouette is stepped by one cell) and
	#    what shows through in a scene with no terrain at all.
	draw_circle(MAP_CENTER, MAP_RADIUS + RIM_WIDTH, COLOR_RIM)
	draw_circle(MAP_CENTER, MAP_RADIUS, COLOR_BACKDROP)
	if _terrain_count > 0:
		draw_multiline_colors(_terrain_points, _terrain_colors, TERRAIN_CELL)

	# 2. The coin road: ONE polyline for the whole window. The per-segment
	#    draw_line() version this replaced cost ~20 draw calls on its own — the
	#    single biggest line item in the map's budget — because antialiased lines
	#    do not batch. The points are already absolute and rim-clamped.
	if _road_count >= 2:
		draw_polyline(_road_points, COLOR_ROAD, ROAD_WIDTH, true)

	# 2b. Landmarks — ONE draw call for every X on screen (see _gather_landmarks),
	#     and ZERO while no landmark chunk is loaded. Under the crocodiles on
	#     purpose: a destination must never hide a threat.
	if _landmark_count > 0:
		draw_multiline_colors(_landmark_points, _landmark_colors, LANDMARK_MARK_WIDTH)

	# 3. Crocodiles — one draw call for the whole pack (see _gather_crocodiles).
	if _croc_count > 0:
		draw_multiline(_croc_points, COLOR_CROC, CROC_DOT_RADIUS * 2.0)

	# 3b. Teammates — ONE draw call for the whole room, in their own colours (see
	#     _gather_peers). Zero calls solo, where _peer_count is never above 0.
	if _peer_count > 0:
		draw_multiline_colors(_peer_points, _peer_colors, PEER_DOT_RADIUS * 2.0)

	# 4. The player: a triangle at the centre pointing the way the character faces.
	#    Built from the cached facing vector and its perpendicular — no trig here.
	var perp := Vector2(-_facing.y, _facing.x)
	var tail := MAP_CENTER - _facing * ARROW_LENGTH * 0.6
	_arrow_points[0] = MAP_CENTER + _facing * ARROW_LENGTH
	_arrow_points[1] = tail + perp * ARROW_HALF_WIDTH
	_arrow_points[2] = tail - perp * ARROW_HALF_WIDTH
	draw_colored_polygon(_arrow_points, COLOR_PLAYER)

	# 5. Coordinates + biome under the disc, as ONE two-line string. X is also the
	#    run's distance score (the coin road's X is strictly increasing by
	#    construction), so the number doubles as "how far have I got". The outline
	#    is not optional: this text sits outside the dark disc, over whatever the
	#    world happens to be, and the sky here is nearly white.
	#    The two words are `tr()`d individually: this caption is painted with
	#    `draw_multiline_string`, not assigned to a `Control.text`, so Godot's
	#    automatic Control translation never sees it. X and Z are axis letters and
	#    stay as they are. `_draw()` re-runs on the 0.2 s tick, so a language
	#    switched mid-run reaches this caption within one tick like everything else.
	var text := "X %d   Z %d\n%s" % [roundi(_player_pos.x), roundi(_player_pos.z),
		tr(BIOME_NAMES[_biome])]
	var color := COLOR_TEXT
	if _in_river:
		text += tr("  ~ river ~")
		color = COLOR_RIVER_TEXT
	# draw_multiline_string* is what keeps this at 2 draw calls instead of 4: the
	# per-line draw_string()/draw_string_outline() pair it replaced cost one each.
	var font := get_theme_default_font()
	var pos := Vector2(0.0, MAP_CENTER.y + MAP_RADIUS + TEXT_TOP_GAP)
	font.draw_multiline_string_outline(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, 4, Color(0, 0, 0, 0.85))
	font.draw_multiline_string(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, color)
