extends Control
## Teammate locator bar — a thin bearing strip along the bottom of the screen,
## in the spirit of Minecraft's locator bar: the CENTRE is straight ahead, and a
## teammate's marker slides left or right as you turn, so "where is everybody"
## is answered without opening the map.
##
## Drawn entirely in `_draw()` with no texture assets, exactly like
## `minimap_hud.gd`, `ability_hud.gd` and `lives_hud.gd` — this project ships a web
## build where every KB and every draw call is budgeted, so the HUD is code-built
## rectangles and lines.
##
## SOLO IT DOES NOT EXIST. `MpManager.peer_markers()` answers `null` whenever there
## is no room (the project's standard "null means fall through to solo behaviour"
## shape), so this control hides itself, draws nothing and scans nothing — the
## single-player HUD is byte-for-byte what it was. Discovery is the usual group
## lookup (`"mp"`, `"player"`) plus `has_method()` guards, with no hard references,
## so a scene run without the manager just shows nothing.
##
## HOW A BEARING BECOMES AN X.  The bar spans a full turn: bearing 0 (dead ahead)
## sits at the centre, +PI/2 (hard right) at three-quarters across, and ±PI
## (directly behind) at the two ends. So a teammate is ALWAYS somewhere on the bar
## and nothing needs clamping or hiding; the price is a seam directly behind you,
## where a marker crosses from one end to the other. That is the honest place for
## the discontinuity to be — it is the one bearing you cannot walk toward anyway.
##
## PERFORMANCE SHAPE — a deliberate split, not the minimap's flat 5 Hz:
##   * POSITIONS are re-read on a throttled TICK_INTERVAL tick (~5 Hz), because
##     that read crosses a system boundary and allocates (see
##     `MpManager.peer_markers()`), and a teammate 40 m away does not move a pixel
##     in 200 ms.
##   * BEARINGS are recomputed every frame from the live player facing, because
##     THAT is the thing the player is watching: at 5 Hz a mouse turn would step
##     the markers across the bar in visible jumps. It is three `atan2`s into
##     buffers that never resize — no allocation, no node lookups.
##   * A redraw is only queued when the facing actually moved (or the snapshot
##     refreshed), so standing still costs nothing at all.
##   * Two draw calls when visible: one backdrop rect, and ONE
##     `draw_multiline_colors()` carrying every marker AND the centre notch —
##     per-peer colours are exactly why it is the `_colors` variant rather than
##     the plain `draw_multiline()` the crocodile dots use.

# ============================================================================
# CONFIGURATION
# ============================================================================

## How often (seconds) teammate POSITIONS are re-read. Bearings are recomputed
## every frame regardless — see the performance note above.
const TICK_INTERVAL: float = 0.2

## Hard cap on markers, and the size of the buffers. The lobby caps a room at 4
## members (`server/room.go`), so 3 is the real number; this is a bound on
## peer-supplied data, in the same spirit as every other bound on the relay.
const MAX_MARKERS: int = 8

## Bar geometry, in pixels. The height is the drawn strip; the control's own rect
## is set in the scene and the bar is centred inside it.
const BAR_HEIGHT: float = 18.0

## Marker width in pixels, shared by the markers and the centre notch — one
## `draw_multiline_colors()` call carries a single width for the whole batch.
const MARKER_WIDTH: float = 3.0

## Marker height in pixels at the near and far ends of LOCATOR_RANGE. Distance
## modulates height and alpha together: a close teammate is a tall bright tick, a
## distant one a short faint one.
const MARKER_HEIGHT_NEAR: float = 14.0
const MARKER_HEIGHT_FAR: float = 6.0
const MARKER_ALPHA_NEAR: float = 1.0
const MARKER_ALPHA_FAR: float = 0.45

## Distance (metres) at which a marker reaches its far size and alpha. Past it a
## teammate keeps that minimum rather than disappearing: the direction of somebody
## 800 m away is still the most useful thing this bar can tell you.
const LOCATOR_RANGE: float = 250.0

## How far the facing may drift (radians) before a redraw is queued. Roughly a
## third of a degree — below one pixel of marker travel on any sane bar width, so
## standing still or nudging the mouse costs no redraw at all.
const YAW_REDRAW_EPSILON: float = 0.006

# --- Colours ----------------------------------------------------------------
const COLOR_BACKDROP := Color(0.0, 0.0, 0.0, 0.45)
## The centre notch: "this is ahead". Deliberately dim — it is a reference mark,
## not information, and it must never out-shout a teammate marker sitting on it.
const COLOR_CENTER := Color(1.0, 1.0, 1.0, 0.35)

# ============================================================================
# STATE
# ============================================================================

var _player: Node3D = null
var _mp: Node = null

## Seconds until the next POSITION re-read.
var _time_until_tick: float = 0.0

## Last snapshot from `MpManager.peer_markers()` — one dictionary per teammate,
## `{"id": String, "pos": Vector3, "color": Color}`. Empty means "nothing to draw",
## which is also what solo looks like.
var _markers: Array = []

## The facing this control last drew at, so `_process` can skip the redraw while
## the player is not turning.
var _last_drawn_yaw: float = INF

## Marker geometry for ONE `draw_multiline_colors()`: two points per segment and
## ONE COLOUR PER SEGMENT (`colors.size() * 2 == points.size()`, which is what
## that variant requires). Slot 0 is always the centre notch, so the buffers hold
## MAX_MARKERS + 1 segments. Sized once in `_ready()` and never resized — the
## unused tail is parked off-control and transparent, the same trick
## `minimap_hud.gd` parks its crocodile tail with.
var _points: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _count: int = 0

## Where unused segments are parked: well outside the control on both axes.
const PARKED_SEGMENT := Vector2(-4000.0, -4000.0)


func _ready() -> void:
	# Never let the bar eat clicks meant for the game or the touch UI.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Group registration so anything could find us later without a hard reference
	# (the convention `perf_overlay.gd` and `minimap_hud.gd` follow).
	add_to_group("teammate_locator")
	_points.resize((MAX_MARKERS + 1) * 2)
	_colors.resize(MAX_MARKERS + 1)
	# Hidden until a room says otherwise — solo must never flash a bar.
	visible = false


func _process(delta: float) -> void:
	# NOTE: unlike the minimap this does NOT early-return while hidden. Hidden is
	# how solo looks, and something has to notice the moment a room appears. The
	# cost of noticing is one cached-node call every 0.2 s, which is nothing.
	_time_until_tick -= delta
	if _time_until_tick <= 0.0:
		_time_until_tick = TICK_INTERVAL
		_refresh_markers()
	if not visible:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	# Godot's convention: -Z is a body's forward. Read off the basis rather than
	# rebuilt from rotation.y, so this stays correct whatever the controller does
	# with its transform — the same reasoning `minimap_hud._tick()` gives.
	var forward := -_player.global_transform.basis.z
	# World (x, z) maps to screen (x, y) — the minimap's north-up convention, in
	# which a positive angle turns toward the player's RIGHT.
	var yaw := atan2(forward.z, forward.x)
	# INF is the "never drawn / snapshot just changed" sentinel, and it has to be
	# tested for explicitly: `angle_difference(x, INF)` is NaN, and every NaN
	# comparison is false, so a plain threshold test would silently never fire.
	var stale := not is_finite(_last_drawn_yaw)
	if stale or absf(angle_difference(_last_drawn_yaw, yaw)) > YAW_REDRAW_EPSILON:
		_last_drawn_yaw = yaw
		_build_segments(yaw)
		queue_redraw()


func _refresh_markers() -> void:
	"""Re-read the room, on the throttled tick. Solo this is one cached-node call
	and one `== null` test."""
	if _mp == null or not is_instance_valid(_mp):
		_mp = get_tree().get_first_node_in_group("mp")
	var fresh: Array = []
	if _mp != null and _mp.has_method("peer_markers"):
		var markers: Variant = _mp.peer_markers()
		if markers is Array:
			fresh = markers
	_markers = fresh
	var want_visible := not _markers.is_empty()
	if want_visible != visible:
		visible = want_visible
	if want_visible:
		# Force a rebuild on the next frame. Without this the bar would only move
		# when the PLAYER turned — a teammate running past a standing player would
		# have their marker frozen wherever it was when we last turned.
		_last_drawn_yaw = INF


func _build_segments(yaw: float) -> void:
	"""Turn the snapshot plus the live facing into the draw buffers. Called from
	`_process`, never from `_draw()`: the buffers are permanently sized, so this
	allocates nothing, and `_draw()` stays a pure paint of what it is handed."""
	var bar_top := (size.y - BAR_HEIGHT) * 0.5
	var mid := bar_top + BAR_HEIGHT * 0.5
	var half_span := size.x * 0.5

	# Slot 0 is always the centre notch — "ahead is here".
	_points[0] = Vector2(half_span, bar_top)
	_points[1] = Vector2(half_span, bar_top + BAR_HEIGHT)
	_colors[0] = COLOR_CENTER
	_count = 1

	var player_pos := _player.global_position
	for entry: Variant in _markers:
		if _count > MAX_MARKERS:
			break
		if not (entry is Dictionary):
			continue
		var marker: Dictionary = entry
		var pos: Vector3 = marker.get("pos", Vector3.ZERO)
		var color: Color = marker.get("color", Color.WHITE)
		var to_peer := Vector2(pos.x - player_pos.x, pos.z - player_pos.z)
		# Bearing relative to the facing, wrapped into [-PI, PI] so the sign is
		# "left/right of ahead" and the magnitude is "how far round".
		var bearing := angle_difference(yaw, atan2(to_peer.y, to_peer.x))
		var x := half_span + (bearing / PI) * half_span
		# Distance modulates height AND alpha, so a near teammate reads instantly
		# and a far one is present without competing.
		var nearness := 1.0 - clampf(to_peer.length() / LOCATOR_RANGE, 0.0, 1.0)
		var height := lerpf(MARKER_HEIGHT_FAR, MARKER_HEIGHT_NEAR, nearness)
		color.a = lerpf(MARKER_ALPHA_FAR, MARKER_ALPHA_NEAR, nearness)
		_points[_count * 2] = Vector2(x, mid - height * 0.5)
		_points[_count * 2 + 1] = Vector2(x, mid + height * 0.5)
		_colors[_count] = color
		_count += 1

	# Park the unused tail: `draw_multiline_colors()` consumes the whole array, and
	# these buffers are permanently sized so the rebuild never allocates.
	for i in range(_count * 2, _points.size()):
		_points[i] = PARKED_SEGMENT
	for i in range(_count, _colors.size()):
		_colors[i] = Color(0, 0, 0, 0)


# ============================================================================
# DRAWING (snapshot only — no node lookups, no allocation)
# ============================================================================

func _draw() -> void:
	if _count <= 0:
		return
	var bar_top := (size.y - BAR_HEIGHT) * 0.5
	# 1. The strip itself, so the markers read against something at any time of day.
	draw_rect(Rect2(0.0, bar_top, size.x, BAR_HEIGHT), COLOR_BACKDROP)
	# 2. Every marker AND the centre notch, in ONE call — see the buffers above.
	draw_multiline_colors(_points, _colors, MARKER_WIDTH)
