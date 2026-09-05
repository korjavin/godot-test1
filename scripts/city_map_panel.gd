extends Control
## ============================================================================
## THE BUDAPEST MAP PANEL — B, the 22 places, and which of them you have found
## ============================================================================
##
## Bead `godot-test1-8gw.11`. The minimap (`minimap_hud.gd`) shows 130 m and caps
## its landmark layer at 12 marks; the win condition of this epic is walking into
## 18 of 22 places spread over 2.2 km. Those are not the same question, and no
## amount of zoom on a 202 px disc makes them one — so the city gets a MAP, opened
## on its own key, showing the whole plan at once.
##
## WHAT IS DRAWN, AND WHERE EACH LAYER COMES FROM:
##
##   * THE STATIC PLAN — the Danube, the four bridge decks, Margaret Island, the
##     two hills and their ramps, the street grid — is `budapest_plan.gd`, read
##     through its OWN pure helpers (`danube_wet`, `DRY_RECTS`, `PLATEAUS`), never
##     re-derived here. It is `const` data with no seed and no draw anywhere in it,
##     so it is the same picture in every run and on every peer.
##   * THE 22 ICONS, the player's dot and the teammates' dots are LIVE, and they
##     are the only live thing on this panel.
##
## ============================================================================
## THE PERFORMANCE SHAPE — the plan is BAKED, the marks are ticked
## ============================================================================
##
## The static plan costs a per-pixel `BudapestPlan.danube_wet()` sweep across the
## river's x-window (~30k calls). That is fine ONCE and unthinkable per frame, and
## the plan cannot change — so it is rasterized into an `Image`, wrapped in an
## `ImageTexture` and handed to a `TextureRect` the FIRST time the panel opens.
## `_base_texture` is then kept for the life of the node: a second open reuses it,
## and `city_map_selfcheck` check 3 asserts that (an unbaked rebuild-per-open would
## look identical and cost a visible hitch every press of B).
##
## The live marks follow `minimap_hud.gd`'s discipline exactly: they are computed
## on a 5 Hz TICK into flat buffers (`_icon_points` / `_icon_colors`, `_peer_*`)
## and `_draw()` only paints what the tick left there. Nothing is sampled inside
## `_draw()`, which is what lets the self-check read the buffers back and assert
## what the panel actually shows.
##
## ============================================================================
## THE PAUSE — solo yes, in a room NO (the `landmark_toast` precedent)
## ============================================================================
##
## `PauseHub.take()` / `PauseHub.release()`, never `get_tree().paused` — the one
## rule `pause_selfcheck` check 3 scans every script in this directory for. The
## POLICY stays here, with the feature, exactly as the hub's header says it must:
##
##   * IN A ROOM the panel opens and freezes NOTHING. `get_tree().paused` is local
##     and the simulation is not, so a peer reading the map while three teammates
##     run from a hunter would either desync itself or ask them to stand still.
##     Same decision, same reason, as `landmark_toast._take_pause`.
##   * OVER GAME OVER the panel opens and freezes nothing either: `GameOverUI` is
##     PAUSABLE, so a pause there kills its Play Again button — `pause_controller`,
##     `mp_ui`, `mobile_input` and the toast all carry this refusal.
##
## `_apply_pause()` is re-asserted from `_process` for `mp_ui`'s reason: the claim
## is taken lazily, so a Play Again pressed with the map up must not leave the
## world frozen behind it.
##
## ============================================================================
## LOCALIZATION
## ============================================================================
##
## RULE 1 for the title (a plain literal on a `Label`, translated by the engine);
## RULE 2 for the two COMPOSED lines — the progress line and the close hint — both
## of which run `tr()` on the FORMAT string. Both are rewritten on every tick while
## the panel is open, so a language switch under an open map needs no
## `NOTIFICATION_TRANSLATION_CHANGED` hook of its own.
##
## The landmark NAMES are deliberately not on the map: 22 of them over a 440 px
## square is unreadable, and `landmark_toast` already names a place the moment you
## reach it. The map answers "where have I not been", which is the question the
## minimap cannot.
## ponytail: no name legend and no touch opener — `M` has neither either. Add a
## legend column beside the map, and a button beside `Skills`, if playtests ask.

const BudapestPlan := preload("res://scripts/budapest_plan.gd")
## The win threshold is a DESIGN number and it lives on the player, next to the
## mask it counts. Read, never restated — a wave that changes 18 must change this
## line's meaning without anybody editing this file.
const PLAYER_SCRIPT: GDScript = preload("res://scripts/player_controller.gd")

# ============================================================================
# THE KEY
# ============================================================================

## The open/close key. A raw keycode OUTSIDE the input map, like `K`, `M` and `P`:
## a key that only opens a panel has nothing to rebind against (CLAUDE.md). `B`
## for Budapest, and it is free — nothing in `project.godot`'s input map and no
## other panel claims it, which `city_map_selfcheck` check 1 asserts against both
## sources rather than against a list written down here.
const TOGGLE_KEY: Key = KEY_B

# ============================================================================
# THE BAKED PLAN
# ============================================================================

## Side of the baked map, in pixels. The city rect is square (2200 x 2200 m), so
## one number covers both axes and the scale is 5 m per pixel — fine enough that
## the 240 m river is 48 px and a 32 m bridge deck is still 6, coarse enough that
## the bake is ~30k river tests and not half a million.
const MAP_PIXELS: int = 440

## Metres per baked pixel. DERIVED, so retuning `MAP_PIXELS` retunes everything
## that reads the map — the icon spacing included.
const METRES_PER_PIXEL: float = 2200.0 / MAP_PIXELS

## How wide, in metres, the river's x-window is padded past the polyline's own
## extremes before the per-pixel sweep. `DANUBE_HALF_WIDTH` plus a pixel of slack;
## outside it `danube_wet()` cannot be true, so the sweep skips it.
const RIVER_WINDOW_PAD: float = BudapestPlan.DANUBE_HALF_WIDTH + 8.0

# --- The baked palette ------------------------------------------------------
# Deliberately muted: the map's only bright ink is the landmark icons and the
# dots, because those are the two things a player opened this panel to read.
#
# NOT `HudTheme`'S, AND DELIBERATELY LEFT THAT WAY by the palette pass (bead
# `godot-test1-y1o.33`). This is CARTOGRAPHY — water, park, hill, deck — and it
# is the `minimap_hud` biome-RGB case one panel along: a map says what a thing IS
# and a green park may not become a khaki one because the HUD went monochrome.
# None of these is a colour `HudTheme` owns, so the "no second copy of a film
# hex" rule has nothing to say about them, and `city_map_selfcheck` samples four
# of them by name.
const COLOR_LAND: Color = Color(0.13, 0.14, 0.13, 1.0)
const COLOR_STREET: Color = Color(0.20, 0.21, 0.20, 1.0)
const COLOR_WATER: Color = Color(0.13, 0.28, 0.46, 1.0)
const COLOR_DECK: Color = Color(0.50, 0.47, 0.41, 1.0)
const COLOR_PARK: Color = Color(0.17, 0.31, 0.19, 1.0)
const COLOR_HILL: Color = Color(0.28, 0.25, 0.21, 1.0)
const COLOR_RAMP: Color = Color(0.40, 0.36, 0.29, 1.0)
const COLOR_BORDER: Color = Color(0.46, 0.49, 0.53, 1.0)

# --- The live palette, off `HudTheme` ---------------------------------------
## An explored landmark and an unexplored one. The whole panel turns on telling
## these two apart at a glance, so they differ in VALUE and in SHAPE, never in
## alpha — a dimmed mark reads as "far away" on a map, which is a different
## claim. BONE is the palette's own lettering value against STEEL's inactive
## one, and `_paint_marks` fills the first and hollows the second.
const COLOR_FOUND: Color = HudTheme.BONE
const COLOR_UNFOUND: Color = HudTheme.STEEL
## THE ONE AMBER on this panel: you are the focus, and the palette says focus is
## the accent. It also has to out-shout 22 marks and a teammate's identity dot,
## which on an INK/STEEL/BONE map only the accent does.
const COLOR_PLAYER: Color = HudTheme.VISOR_AMBER

## Side of a landmark icon and of the ring drawn round an explored one, in pixels.
const ICON_SIZE: float = 9.0
## Radius of the player's dot, and of a teammate's.
const DOT_RADIUS: float = 4.5
## Alpha a dot CLAMPED to the map's edge is drawn at — the same distinction, and
## the same reason, as `minimap_hud`'s rim ticks: off the map is less certain
## information and must not out-shout a dot standing where it says it stands.
const EDGE_ALPHA: float = 0.5

# ============================================================================
# LAYOUT
# ============================================================================

const TITLE_FONT_SIZE: int = 28
const LINE_FONT_SIZE: int = 18
const HINT_FONT_SIZE: int = 15
const CARD_PADDING: int = 18

## The card's chrome, off `HudTheme`: a BONE heading over a STEEL rule, BONE body
## and the corporation's khaki for fine print — the spec's three, and no hex here.
const COLOR_TITLE: Color = HudTheme.BONE
const COLOR_TEXT: Color = HudTheme.BONE
const COLOR_HINT: Color = HudTheme.UNIT_KHAKI
## The 1 px rule under a section heading. `HudTheme` has no `rule()` builder — a
## `ColorRect` is the whole of it — so it is one here and in `tower_lift_menu`;
## a third caller is the moment to lift it into the theme.
const RULE_PX: float = 1.0

## How often the live marks are recomputed while the panel is up. 5 Hz, the rate
## `mp_manager.peer_markers()` documents for its two HUD callers — it allocates,
## so it may not be asked per frame.
const REFRESH_INTERVAL: float = 0.2

# --- Composed strings (localization RULE 2 — `tr()` on the FORMAT) ----------
const PROGRESS_LINE: String = "Explored %d of %d — %d to vanish"
const CLOSE_HINT: String = "Press %s or Esc to close"

# ============================================================================
# STATE
# ============================================================================

var _panel_open: bool = false
## Whether the CURRENT tree pause is ours to release. "We hold A claim", not "we
## hold THE pause" — see `pause_hub.gd`'s header.
var _paused_by_us: bool = false
var _refresh_timer: float = 0.0

## The baked plan, built on first open and kept. Never rebuilt: the plan is const.
var _base_texture: ImageTexture = null

# --- Child nodes (built in `_ready`, not from a .tscn) ----------------------
var _card: PanelContainer = null
var _map_rect: TextureRect = null
var _marks: Control = null
var _progress_label: Label = null
var _hint_label: Label = null

# --- The tick's output, read by `_draw()` and by the self-check -------------
## One entry per `BudapestPlan.SLOTS` row, in slot order: where its icon sits in
## the map's own pixel space, and whether it is lit.
var _icon_points: PackedVector2Array = PackedVector2Array()
var _icon_colors: PackedColorArray = PackedColorArray()
## The local player's dot, or a negative point when there is no player at all.
var _player_point: Vector2 = Vector2(-1.0, -1.0)
var _player_color: Color = COLOR_PLAYER
var _player_shown: bool = false
## Teammates, in `peer_markers()` order. Empty solo — there is no room layer.
var _peer_points: PackedVector2Array = PackedVector2Array()
var _peer_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available HUD
	# piece (`skill_tree_ui`, `mp_ui`, `start_overlay`).
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("city_map_panel")
	_build_ui()


func _process(delta: float) -> void:
	# Re-assert the pause every frame while open, for `mp_ui`'s reason: the claim
	# is declined over Game Over and in a room, so a state change under an open
	# panel must not strand the world in the wrong one.
	_apply_pause(_panel_open)
	if not _panel_open:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	# Esc closes, and only while we are open — otherwise this eats the `ui_cancel`
	# `player_controller._input()` uses to release the mouse. `skill_tree_ui`'s
	# guard, for `skill_tree_ui`'s reason.
	if _panel_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_panel_open(false)
		return
	# Raw keycode, echo-filtered so holding B does not rapid-toggle.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		set_panel_open(not _panel_open)


func _exit_tree() -> void:
	# Never leave the world frozen behind a node that is going away.
	_apply_pause(false)


# ============================================================================
# OPEN / CLOSE
# ============================================================================

func is_panel_open() -> bool:
	return _panel_open


func set_panel_open(open: bool) -> void:
	"""Show or hide the map, baking the plan on the first open."""
	if open == _panel_open:
		return
	_panel_open = open
	if open:
		if _base_texture == null:
			_base_texture = _bake_plan()
		if _map_rect != null:
			_map_rect.texture = _base_texture
		_refresh_timer = REFRESH_INTERVAL
		_refresh()
	if _card != null:
		_card.visible = open
	_apply_pause(open)


func _apply_pause(open: bool) -> void:
	"""
	Take or give back the pause for the panel's current state, or decline it for
	one of the two reasons the header lists.
	"""
	if not open and not _paused_by_us:
		return  # The overwhelmingly common case: closed panel, nothing to undo.
	var tree := get_tree()
	if tree == null:
		return
	var want: bool = open and not _in_room() and not _game_over()
	if want and not _paused_by_us:
		PauseHub.take(self)
		_paused_by_us = true
	elif not want and _paused_by_us:
		_paused_by_us = false
		PauseHub.release(self)


func _in_room() -> bool:
	"""Is this peer engaged with the lobby at all? `is_busy()`, not `is_online()`:
	a join in flight is already a session somebody else's frames belong to."""
	var tree := get_tree()
	if tree == null:
		return false
	var mp: Node = tree.get_first_node_in_group("mp")
	return mp != null and mp.has_method("is_busy") and bool(mp.is_busy())


func _game_over() -> bool:
	# `"x" in node`, not `node.get("x")`: `get()` answers null for a missing
	# property and `bool(null)` is a hard error, so this is what lets a scene whose
	# player is a stand-in degrade instead of throwing.
	var tree := get_tree()
	if tree == null:
		return false
	var player: Node = tree.get_first_node_in_group("player")
	return player != null and "is_game_over" in player and bool(player.is_game_over)


# ============================================================================
# THE LIVE TICK — everything `_draw()` paints is computed here
# ============================================================================

func _refresh() -> void:
	"""Recompute the icons, the player's dot and the teammates' dots, then repaint
	the marks layer and rewrite the two composed lines."""
	var mask: int = 0
	var explored: int = 0
	var tree := get_tree()
	var player: Node = null if tree == null else tree.get_first_node_in_group("player")
	if player != null and "explored_mask" in player:
		mask = int(player.explored_mask)
	if player != null and player.has_method("explored_count"):
		explored = int(player.call("explored_count"))

	# --- The 22 icons ------------------------------------------------------
	var slots: Array = BudapestPlan.SLOTS
	_icon_points.resize(slots.size())
	_icon_colors.resize(slots.size())
	for i in range(slots.size()):
		var pos: Vector3 = slots[i]["pos"]
		_icon_points[i] = map_point(pos.x, pos.z)
		_icon_colors[i] = COLOR_FOUND if (mask & (1 << i)) != 0 else COLOR_UNFOUND

	# --- The player's dot --------------------------------------------------
	_player_shown = player != null and "global_position" in player
	if _player_shown:
		var origin: Vector3 = player.global_position
		_player_point = map_point(origin.x, origin.z)
		# Outside the city the dot is clamped to the edge and dimmed, so the map
		# says "somewhere out that way" rather than "standing on the gate".
		var inside: bool = BudapestPlan.contains(origin.x, origin.z)
		_player_point = _clamp_to_map(_player_point)
		_player_color = COLOR_PLAYER if inside else Color(COLOR_PLAYER, EDGE_ALPHA)

	# --- Teammates ---------------------------------------------------------
	_peer_points.resize(0)
	_peer_colors.resize(0)
	var mp: Node = null if tree == null else tree.get_first_node_in_group("mp")
	if mp != null and mp.has_method("peer_markers"):
		var markers: Variant = mp.call("peer_markers")
		# `null` means "no room" — the one `== null` test the API promises, and the
		# whole of "solo has no teammate layer".
		if markers is Array:
			for marker: Dictionary in markers:
				var mpos: Vector3 = marker["pos"]
				var point: Vector2 = map_point(mpos.x, mpos.z)
				var mate_inside: bool = BudapestPlan.contains(mpos.x, mpos.z)
				var colour: Color = marker["color"]
				_peer_points.append(_clamp_to_map(point))
				_peer_colors.append(colour if mate_inside else Color(colour, EDGE_ALPHA))

	if _progress_label != null:
		_progress_label.text = tr(PROGRESS_LINE) % [
			explored, slots.size(), PLAYER_SCRIPT.BUDAPEST_WIN_LANDMARKS,
		]
	if _hint_label != null:
		_hint_label.text = tr(CLOSE_HINT) % OS.get_keycode_string(TOGGLE_KEY)
	if _marks != null:
		_marks.queue_redraw()


static func map_point(x: float, z: float) -> Vector2:
	"""
	A world XZ as a point in the baked map's own pixel space.

	NORTH UP, the minimap's mapping and the plan's orientation: world +X (east) is
	screen right, world +Z (south) is screen down. Getting a sign wrong here
	mirrors the city, which looks entirely plausible and is useless to walk by —
	`minimap_selfcheck`'s lesson, and `city_map_selfcheck` check 2 is the alarm.
	"""
	var span: Vector2 = BudapestPlan.BUDAPEST_MAX - BudapestPlan.BUDAPEST_MIN
	return Vector2(
		(x - BudapestPlan.BUDAPEST_MIN.x) / span.x,
		(z - BudapestPlan.BUDAPEST_MIN.y) / span.y) * float(MAP_PIXELS)


static func _clamp_to_map(point: Vector2) -> Vector2:
	"""A dot pinned inside the map's rect, so an off-map body is drawn on the edge
	nearest it instead of outside the picture."""
	return Vector2(
		clampf(point.x, 0.0, float(MAP_PIXELS)),
		clampf(point.y, 0.0, float(MAP_PIXELS)))


# ============================================================================
# THE BAKE — the plan, rasterized once
# ============================================================================

func _bake_plan() -> ImageTexture:
	"""
	Rasterize `budapest_plan.gd` into one `ImageTexture`, bottom layer first.

	ORDER IS THE WHOLE ALGORITHM: land, then the street grid, then the river over
	the streets it crosses, then the dry rects (decks and the island) over the
	river, then the hills. Every shape is a `fill_rect` except the river, which is
	a per-row sweep asking `BudapestPlan.danube_wet()` — the SAME predicate the
	wade and the ground shader use, so the blue on this map is the water you slow
	down in. Restating the band's geometry here is how a map starts lying.
	"""
	var image := Image.create_empty(MAP_PIXELS, MAP_PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(COLOR_LAND)

	# --- The street grid ---------------------------------------------------
	# `street_x()` / `street_z()` off the plan, walked from the north-west corner's
	# own cell. NOT `STREET_PITCH` stepped off the map's corner: the grid is
	# anchored at the GATE (`street_x(0)` is the gate's meridian, and
	# `crowd_manager.snap_to_grid` reads the same origin), so pitching from
	# `BUDAPEST_MIN` puts every column 12 m off — and since bead .9 those lines are
	# real block edges, not decoration. Asking the plan is what stops a map from
	# drawing streets the city does not have.
	var cell: Vector2i = BudapestPlan.block_cell(
		BudapestPlan.BUDAPEST_MIN.x, BudapestPlan.BUDAPEST_MIN.y)
	var k: int = cell.x
	while BudapestPlan.street_x(k) <= BudapestPlan.BUDAPEST_MAX.x:
		var px: int = int(map_point(BudapestPlan.street_x(k), 0.0).x)
		if px >= 0 and px < MAP_PIXELS:
			image.fill_rect(Rect2i(px, 0, 1, MAP_PIXELS), COLOR_STREET)
		k += 1
	var m: int = cell.y
	while BudapestPlan.street_z(m) <= BudapestPlan.BUDAPEST_MAX.y:
		var pz: int = int(map_point(0.0, BudapestPlan.street_z(m)).y)
		if pz >= 0 and pz < MAP_PIXELS:
			image.fill_rect(Rect2i(0, pz, MAP_PIXELS, 1), COLOR_STREET)
		m += 1

	# --- The Danube --------------------------------------------------------
	# Only the x-window the polyline can reach is swept: outside it `danube_wet()`
	# cannot be true, and the window is ~15% of the map's width. ~30k predicate
	# calls, paid once for the life of the node.
	var west: float = INF
	var east: float = -INF
	for i in range(BudapestPlan.DANUBE.size()):
		var node: Vector2 = BudapestPlan.DANUBE[i]
		west = minf(west, node.x)
		east = maxf(east, node.x)
	var x_from: int = clampi(int(map_point(west - RIVER_WINDOW_PAD, 0.0).x), 0, MAP_PIXELS - 1)
	var x_to: int = clampi(int(map_point(east + RIVER_WINDOW_PAD, 0.0).x) + 1, 0, MAP_PIXELS)
	for row in range(MAP_PIXELS):
		var world_z: float = BudapestPlan.BUDAPEST_MIN.y + (float(row) + 0.5) * METRES_PER_PIXEL
		for col in range(x_from, x_to):
			var world_x: float = BudapestPlan.BUDAPEST_MIN.x + (float(col) + 0.5) * METRES_PER_PIXEL
			if BudapestPlan.danube_wet(world_x, world_z):
				image.set_pixel(col, row, COLOR_WATER)

	# --- The dry rects: the four decks, and Margaret Island -----------------
	# Which index is a DECK is the `BRIDGES` table's business, not a count written
	# down here — a fifth crossing lands as one row there and this stays right.
	var deck_rows := {}
	for i in range(BudapestPlan.BRIDGES.size()):
		deck_rows[int(BudapestPlan.BRIDGES[i]["dry"])] = true
	for i in range(BudapestPlan.DRY_RECTS.size()):
		_fill_world_rect(image, BudapestPlan.DRY_RECTS[i],
			COLOR_DECK if deck_rows.has(i) else COLOR_PARK)

	# --- The two hills, each with its one ramp -----------------------------
	for i in range(BudapestPlan.PLATEAUS.size()):
		var plateau: Dictionary = BudapestPlan.PLATEAUS[i]
		_fill_world_rect(image, plateau["rect"], COLOR_HILL)
		_fill_world_rect(image, plateau["ramp"], COLOR_RAMP)

	# --- The city's own edge ------------------------------------------------
	image.fill_rect(Rect2i(0, 0, MAP_PIXELS, 1), COLOR_BORDER)
	image.fill_rect(Rect2i(0, MAP_PIXELS - 1, MAP_PIXELS, 1), COLOR_BORDER)
	image.fill_rect(Rect2i(0, 0, 1, MAP_PIXELS), COLOR_BORDER)
	image.fill_rect(Rect2i(MAP_PIXELS - 1, 0, 1, MAP_PIXELS), COLOR_BORDER)

	return ImageTexture.create_from_image(image)


func _fill_world_rect(image: Image, world_rect: Rect2, colour: Color) -> void:
	"""Paint a world-XZ `Rect2` onto the baked image, clipped to it. `Rect2i`
	rounds toward zero, so a rect thinner than a pixel would vanish — every one of
	them is given at least one pixel of each side, because a 32 m bridge deck is
	6 px and a future 8 m one would otherwise silently stop being drawn."""
	var top_left: Vector2 = map_point(world_rect.position.x, world_rect.position.y)
	var bottom_right: Vector2 = map_point(
		world_rect.position.x + world_rect.size.x,
		world_rect.position.y + world_rect.size.y)
	var px: int = int(floorf(top_left.x))
	var py: int = int(floorf(top_left.y))
	var pixels := Rect2i(px, py,
		maxi(1, int(ceilf(bottom_right.x)) - px),
		maxi(1, int(ceilf(bottom_right.y)) - py))
	pixels = pixels.intersection(Rect2i(0, 0, MAP_PIXELS, MAP_PIXELS))
	if pixels.size.x > 0 and pixels.size.y > 0:
		image.fill_rect(pixels, colour)


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# THE HUD SKIN, on THIS ROOT and nowhere else (bead `godot-test1-y1o.33`).
	# The card's INK ground, its STEEL frame and its hard shadow all arrive with
	# it, which is why this panel has no `StyleBoxFlat` of its own.
	theme = HudTheme.theme()

	# A CenterContainer so the card sizes to its own content and stays centred at
	# any resolution — `start_overlay.gd`'s and `skill_tree_ui.gd`'s shape.
	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_card = PanelContainer.new()
	_card.name = "Card"
	# STOP: while the map is up it swallows clicks, so a click meant to dismiss it
	# does not fire the desktop-web click-to-capture through it.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	centre.add_child(_card)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CARD_PADDING)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)

	# RULE 1: a plain literal on a Label, translated by the engine for free.
	var title := Label.new()
	title.text = "MAP OF BUDAPEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HudTheme.heading_font())
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	column.add_child(title)
	# The spec's section heading: BONE caps with a STEEL rule under them. The caps
	# are the CSV row's own ("MAP OF BUDAPEST" / "KARTE VON BUDAPEST"), so no
	# `.to_upper()` — a `Label.text` IS the translation key, and upper-casing one
	# is a key in no table.
	column.add_child(_rule())

	_map_rect = TextureRect.new()
	_map_rect.name = "Plan"
	_map_rect.custom_minimum_size = Vector2(MAP_PIXELS, MAP_PIXELS)
	# SHRINK_CENTER pins it to exactly the baked size. Without it a long German
	# progress line widens the column, the TextureRect grows with it and centres a
	# 440 px texture inside a wider rect — while `_marks`, anchored to that rect,
	# keeps drawing from its left edge. Every icon would sit off its own building.
	_map_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_map_rect)

	# The live layer, as a CHILD of the plan: children paint after their parent, so
	# the marks land on top of the baked texture with no draw-order trickery.
	_marks = Control.new()
	_marks.name = "Marks"
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_paint_marks)
	_map_rect.add_child(_marks)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
	_progress_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_progress_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	column.add_child(_hint_label)


func _rule() -> ColorRect:
	"""The 1 px STEEL rule the spec puts under a section heading."""
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = HudTheme.STEEL
	rule.custom_minimum_size = Vector2(0.0, RULE_PX)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _paint_marks() -> void:
	"""
	Paint what `_refresh()` computed, and nothing else — no sampling, no group
	scans, no allocation. `minimap_hud`'s rule, and what lets the self-check assert
	the picture by reading the buffers.
	"""
	if _marks == null:
		return
	var half: float = ICON_SIZE * 0.5
	for i in range(_icon_points.size()):
		var point: Vector2 = _icon_points[i]
		var colour: Color = _icon_colors[i]
		# THE TWO STATES STILL DIFFER IN SHAPE, and since the palette pass they
		# differ in it MORE: explored is a filled BONE square inside a ring,
		# unexplored is a hollow STEEL outline. The map has to read for a
		# colour-blind player, and BONE against STEEL is one value step where the
		# retired gold-against-grey was two.
		var found: bool = colour.is_equal_approx(COLOR_FOUND)
		_marks.draw_rect(Rect2(point - Vector2(half, half),
			Vector2(ICON_SIZE, ICON_SIZE)), colour, found, 1.5)
		if found:
			_marks.draw_rect(Rect2(point - Vector2(half + 2.0, half + 2.0),
				Vector2(ICON_SIZE + 4.0, ICON_SIZE + 4.0)), colour, false, 1.5)
	for i in range(_peer_points.size()):
		_marks.draw_circle(_peer_points[i], DOT_RADIUS, _peer_colors[i])
	if _player_shown:
		_marks.draw_circle(_player_point, DOT_RADIUS + 1.5, Color(HudTheme.INK, 0.7))
		_marks.draw_circle(_player_point, DOT_RADIUS, _player_color)
