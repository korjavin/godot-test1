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
##   * The player as a triangle at the centre, rotated to the character's facing.
##   * The coin road centerline as a polyline, read straight out of the terrain's
##     existing station cache (see _gather_road below).
##   * Crocodiles within range as small red dots.
##   * World X / Z coordinates and the biome underfoot as text, with a "~ river ~"
##     marker while the player is standing in a wading band.
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
##     crocodile pack rather than one circle each, one two-line string rather than
##     two. Total cost of the map: +10 draw calls, no measurable CPU change.
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

## World radius (metres) from the centre of the map to its edge. 60 m comfortably
## covers the crocodile LOD sleep radius (45 m), so anything that could plausibly
## reach the player is on the map.
const VIEW_RADIUS: float = 60.0

## Radius of the drawn map disc, in pixels.
const MAP_RADIUS: float = 62.0

## Centre of the map disc within this control.
const MAP_CENTER := Vector2(70.0, 70.0)

## World radius (metres) within which crocodiles get a dot. Deliberately HALF the
## map's reach: the outer ring of the map is for the road, the inner disc is for
## threats. 30 m covers everything that can currently see the player (the ordinary
## DETECTION_RADIUS is 15 m, a boss's is 25 m), while VIEW_RADIUS-wide dots would
## be ~80 red specks far from the origin, where croc density scales up — noise,
## not information.
const CROC_VIEW_RADIUS: float = 30.0

## Hard cap on crocodile dots, and the size of the dot buffer. CROC_VIEW_RADIUS
## covers ~1.1 chunks of ground, which holds 10 crocodiles near the origin and ~20
## at the far end of the density gradient, so this is a genuine safety bound rather
## than a limit the game reaches: it matters because the group is in spawn order,
## not distance order, so a cap that actually bit could drop the croc standing next
## to the player in favour of one 30 m away.
const MAX_CROC_DOTS: int = 40

## Hard cap on road centerline points. The window is 2 * VIEW_RADIUS metres wide
## and stations sit road_coin_spacing (6 m) apart, so ~21 points is the real
## number — but road_coin_spacing is an @export a designer can shrink, and an
## unbounded walk over a 0.1 m spacing would be 1200 points, so the walk is capped.
const MAX_ROAD_POINTS: int = 96

## Player arrow size in pixels (half-length along the facing direction).
const ARROW_LENGTH: float = 9.0
const ARROW_HALF_WIDTH: float = 6.0

## Crocodile dot radius in pixels.
const CROC_DOT_RADIUS: float = 2.6

## Where unused crocodile dot slots are parked. Well outside the control on both
## axes, so the segments drawn there land off-screen no matter where the HUD puts
## this control (offsets only ever move it right and down from the viewport corner).
const PARKED_SEGMENT := Vector2(-4000.0, -4000.0)

## Road line width in pixels.
const ROAD_WIDTH: float = 2.5

## Text block: font size, and the gap from the bottom of the disc to its baseline.
const TEXT_SIZE: int = 15
const TEXT_TOP_GAP: float = 18.0

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
const COLOR_TEXT := Color(1, 1, 1, 0.95)
const COLOR_RIVER_TEXT := Color(0.45, 0.75, 1.0, 0.95)

## Biome tint of the map disc, indexed by endless_terrain's Biome enum
## (PLAINS, DESERT, FOREST, MOUNTAIN — the declaration order, which is what the
## int we get across the group boundary means). Muted on purpose: this is a
## backdrop for the road and the dots, not the subject.
const BIOME_TINTS: Array[Color] = [
	Color(0.30, 0.42, 0.24, 0.55),  # PLAINS   — green
	Color(0.55, 0.46, 0.26, 0.55),  # DESERT   — sand
	Color(0.16, 0.34, 0.20, 0.60),  # FOREST   — deep green
	Color(0.40, 0.40, 0.44, 0.55),  # MOUNTAIN — grey
]
const BIOME_NAMES: Array[String] = ["PLAINS", "DESERT", "FOREST", "MOUNTAIN"]

# ============================================================================
# STATE (written by the tick, read by _draw — they never disagree)
# ============================================================================

## Cached node references, re-fetched when they go away (respawn, restart, a scene
## run without one of them).
var _player: Node3D = null
var _terrain: Node = null

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


func _input(event: InputEvent) -> void:
	# Raw keycode read (not a named action) — see TOGGLE_KEYCODE.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEYCODE:
			visible = not visible
			if visible:
				# Refresh immediately so it reappears with live data, not the
				# snapshot from whenever it was hidden.
				_time_until_tick = 0.0


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
	_gather_road()
	_gather_crocodiles()

	_have_data = true
	queue_redraw()


func _gather_world() -> void:
	"""Biome + river underfoot: exactly TWO noise evaluations per tick.

	Both are pure functions of world position (endless_terrain documents them as
	safe to call every physics tick), so this is genuinely cheap. Sampling a GRID
	of is_river_at() to draw river BANDS on the map was deliberately skipped: even
	a coarse 9x9 grid is 81 noise evaluations per tick, a ~0.4 ms GDScript spike on
	desktop and worse in the browser, for decoration. ponytail: if river bands are
	wanted later, amortise them — sample a few grid cells per tick into a persistent
	buffer instead of the whole grid at once."""
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
	var k: int = _terrain._road_first_k_at_or_after_x(_player_pos.x - VIEW_RADIUS)
	# The helper returns k_max + 1 when the whole cache lies left of us; clamping
	# to k_min also covers the case where our window starts before the cache.
	k = maxi(k, k_min)
	var x_limit := _player_pos.x + VIEW_RADIUS
	var scale := MAP_RADIUS / VIEW_RADIUS
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
	var scale := MAP_RADIUS / VIEW_RADIUS
	var radius_sq := CROC_VIEW_RADIUS * CROC_VIEW_RADIUS
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


# ============================================================================
# DRAWING (snapshot only — no node lookups, no allocation)
# ============================================================================

func _draw() -> void:
	if not _have_data:
		return

	# 1. The backdrop, painted outside-in: rim ring, dark disc, biome tint. Three
	#    filled circles — see RIM_WIDTH for why the rim is not a draw_arc().
	draw_circle(MAP_CENTER, MAP_RADIUS + RIM_WIDTH, COLOR_RIM)
	draw_circle(MAP_CENTER, MAP_RADIUS, COLOR_BACKDROP)
	draw_circle(MAP_CENTER, MAP_RADIUS, BIOME_TINTS[_biome])

	# 2. The coin road: ONE polyline for the whole window. The per-segment
	#    draw_line() version this replaced cost ~20 draw calls on its own — the
	#    single biggest line item in the map's budget — because antialiased lines
	#    do not batch. The points are already absolute and rim-clamped.
	if _road_count >= 2:
		draw_polyline(_road_points, COLOR_ROAD, ROAD_WIDTH, true)

	# 3. Crocodiles — one draw call for the whole pack (see _gather_crocodiles).
	if _croc_count > 0:
		draw_multiline(_croc_points, COLOR_CROC, CROC_DOT_RADIUS * 2.0)

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
	var text := "X %d   Z %d\n%s" % [roundi(_player_pos.x), roundi(_player_pos.z), BIOME_NAMES[_biome]]
	var color := COLOR_TEXT
	if _in_river:
		text += "  ~ river ~"
		color = COLOR_RIVER_TEXT
	# draw_multiline_string* is what keeps this at 2 draw calls instead of 4: the
	# per-line draw_string()/draw_string_outline() pair it replaced cost one each.
	var font := get_theme_default_font()
	var pos := Vector2(0.0, MAP_CENTER.y + MAP_RADIUS + TEXT_TOP_GAP)
	font.draw_multiline_string_outline(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, 4, Color(0, 0, 0, 0.85))
	font.draw_multiline_string(get_canvas_item(), pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TEXT_SIZE, -1, color)
