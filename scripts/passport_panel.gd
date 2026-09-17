extends Control
class_name PassportPanel
## ============================================================================
## THE DISCOVERY PASSPORT — J, the 48 field landmarks you have ever found
## ============================================================================
##
## Bead `godot-test1-0bnw.1`. The field landmarks (`LandmarkBuilders.LANDMARKS`)
## are the one thing that pays a detour with knowledge, and that knowledge used
## to evaporate with the run. The passport makes the collection outlive it: a
## HudTheme panel of all 48 kinds in registry order, each a card — a FOUND card
## carries the kind's silhouette, its name and its one-line stamp; an UNFOUND
## card is a dotted STEEL frame and nothing else (no name — a name answers the
## quiz). Above the grid a count line says how many strange places were found.
##
## WHAT IT SHOWS, AND WHERE EACH LAYER COMES FROM:
##
##   * THE FOUND SET is `BestRunStore.found_landmark_ids()` — the monotone union
##     the toast stamps on every run's first arrival. Read fresh on every open,
##     so a stamp earned while the panel is closed is there when it opens.
##   * NAMES are the registry's raw English keys on a Label, no `tr()` — the
##     toast's rule. STAMPS are `tr()` on the row's `stamp` key (English = key).
##   * SILHOUETTES are derived, not drawn by hand: on first open, for each found
##     kind the builder is called headless exactly as `landmark_selfcheck` calls
##     it — same arguments, same throwaway nodes — and the emitted boxes are
##     rasterized once into a 64×64 side elevation, cached per kind for the life
##     of this node. No terrain in the tree (a standalone scene) → cards show
##     name + stamp and no silhouette, and the panel never errors.
##
## ============================================================================
## THE PERFORMANCE SHAPE — silhouettes are BAKED, the grid is ticked never
## ============================================================================
##
## A bake walks every box of every found kind once (corner projections, one
## filled rect per box) and keeps an `ImageTexture` per kind: a second open
## reuses them, and `passport_selfcheck` check (e) asserts that (an unbaked
## rebuild-per-open would look identical and cost a visible hitch every press
## of J). Nothing here runs per frame — `_process` only re-asserts the pause —
## and nothing runs at all while the panel is closed.
##
## ============================================================================
## THE PAUSE — solo yes, in a room NO (the `city_map_panel` policy, verbatim)
## ============================================================================
##
## `PauseHub.take()` / `PauseHub.release()`, never `get_tree().paused` — the one
## rule `pause_selfcheck` scans every script in this directory for. Solo the
## panel pauses the world behind it; IN A ROOM it opens and freezes NOTHING (a
## peer reading stamps while three teammates run from a hunter desyncs nothing
## and asks nobody to stand still); OVER GAME OVER it freezes nothing either
## (`GameOverUI` is PAUSABLE, so a pause there kills its Play Again button).
## `_apply_pause()` is re-asserted from `_process` for `mp_ui`'s reason: the
## claim is declined over Game Over and in a room, so a state change under an
## open panel must not strand the world in the wrong one.
##
## ============================================================================
## LOCALIZATION
## ============================================================================
##
## RULE 1 for the title (a plain literal on a `Label`, translated by the engine)
## and for the 48 NAMES (raw registry keys, deliberately untranslated); RULE 2
## for the two COMPOSED lines — the count line and the close hint — both of
## which run `tr()` on the FORMAT string. Both are rewritten on every open, so
## a language switch under an open passport needs no
## `NOTIFICATION_TRANSLATION_CHANGED` hook of its own. The 48 stamps are `tr()`
## on their row keys, each with its own de row in `ui.csv`.

## Explicitly `GDScript`, not inferred: inference resolves the script's class_name,
## on which only static calls compile — while the silhouette bake dispatches by
## method-NAME String (`has_method` + `call`), which needs the resource. The
## `endless_terrain._landmark_builders` precedent, one file along.
const LandmarkBuildersScript: GDScript = preload("res://scripts/landmark_builders.gd")

# ============================================================================
# THE KEY
# ============================================================================

## The open/close key. A raw keycode OUTSIDE the input map, like B, K, M and P:
## a key that only opens a panel has nothing to rebind against (CLAUDE.md). `J`
## for the journey record, and it is free — nothing in `project.godot`'s input
## map and no other panel claims it, which `city_map_selfcheck`'s registry plus
## `passport_selfcheck` check (d) assert against both sources rather than
## against a list written down here.
const TOGGLE_KEY: Key = KEY_J

# ============================================================================
# LAYOUT
# ============================================================================

## Side of a baked silhouette, in pixels. A card's picture is a side elevation
## (world X → u, world Y → v) of the builder's emitted boxes, BONE on
## transparent — the whole landmark at a glance, at the price of one small
## texture per found kind.
const SILHOUETTE_PX: int = 64
## Quiet margin inside the silhouette frame, in pixels.
const SILHOUETTE_PAD: int = 4

## A card is fixed-size: the grid never reflows, whatever the names say.
const CARD_WIDTH: float = 360.0
const CARD_HEIGHT: float = 148.0
## What a stamp line may use: the card minus the found-card strip's own side
## margins (`HudTheme.strip()` pads `GRID` each side). Read off the theme, not
## retyped, so a theme retune retunes the gate `locale_selfcheck` measures.
const CARD_INNER_WIDTH: float = CARD_WIDTH - 2.0 * HudTheme.GRID
## Two cards across, at the grid separation below.
const GRID_COLUMNS: int = 2
const GRID_SEP: float = 12.0
## What the title, the count and the hint span: the grid's own width.
const PANEL_INNER_WIDTH: float = 2.0 * CARD_WIDTH + GRID_SEP
## How many rows of cards show without scrolling: three, against 720p.
const SCROLL_HEIGHT: float = 3.0 * CARD_HEIGHT + 2.0 * GRID_SEP

const TITLE_FONT_SIZE: int = 28
const COUNT_FONT_SIZE: int = 18
const HINT_FONT_SIZE: int = 15
const NAME_FONT_SIZE: int = 16
const STAMP_FONT_SIZE: int = 14

## The card's chrome, off `HudTheme`: a BONE heading over a STEEL rule, BONE
## body and the corporation's khaki for fine print — the spec's three, and no
## hex here. Unfound cards spend their ink on a dotted STEEL frame instead.
const COLOR_TITLE: Color = HudTheme.BONE
const COLOR_TEXT: Color = HudTheme.BONE
const COLOR_NAME: Color = HudTheme.BONE
const COLOR_STAMP: Color = HudTheme.UNIT_KHAKI
const COLOR_HINT: Color = HudTheme.UNIT_KHAKI
const COLOR_SILHOUETTE: Color = HudTheme.BONE
const COLOR_UNFOUND: Color = HudTheme.STEEL
const RULE_PX: float = 1.0

# --- Composed strings (localization RULE 2 — `tr()` on the FORMAT) ----------
## A COUNT, never a percentage and never "of 48": the passport records what the
## pointing bought, it does not grade the collection.
const COUNT_LINE: String = "%d strange places found"
const CLOSE_HINT: String = "Press %s or Esc to close the passport"
## The title, a RULE 1 literal — the caps are the CSV row's own, so no
## `.to_upper()` (a `Label.text` IS the translation key).
const TITLE_TEXT: String = "Discovery passport"

# ============================================================================
# STATE
# ============================================================================

var _panel_open: bool = false
## Whether the CURRENT tree pause is ours to release. "We hold A claim", not
## "we hold THE pause" — see `pause_hub.gd`'s header.
var _paused_by_us: bool = false

## The baked silhouettes, `passport id → ImageTexture`, kept for the life of
## this node. A second open reuses them; a kind found mid-session bakes on the
## next open and joins them.
var _silhouettes: Dictionary = {}

# --- Child nodes (built in `_ready`, not from a .tscn) ----------------------
var _centre: CenterContainer = null
var _card: PanelContainer = null
var _count_label: Label = null
var _hint_label: Label = null
var _grid: GridContainer = null
## One entry per `LandmarkBuilders.LANDMARKS` row, in registry order: the card
## whose face `_refresh()` repaints. Read back by `passport_selfcheck` the way
## `city_map_selfcheck` reads the city map's buffers.
var _cards: Array = []


## An unfound card's whole face: a dotted STEEL frame and nothing else. Drawn,
## not styled — a `StyleBoxFlat` border is solid or it is nothing, and the spec
## wants dots. One per unfound card, painting only its own rect.
class DottedFrame extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
		var c: Color = HudTheme.STEEL
		draw_dashed_line(r.position, Vector2(r.end.x, r.position.y), c, 2.0, 3.0)
		draw_dashed_line(Vector2(r.end.x, r.position.y), r.end, c, 2.0, 3.0)
		draw_dashed_line(r.end, Vector2(r.position.x, r.end.y), c, 2.0, 3.0)
		draw_dashed_line(Vector2(r.position.x, r.end.y), r.position, c, 2.0, 3.0)


func _ready() -> void:
	# Must keep running under its own pause, like every other always-available
	# HUD piece (`skill_tree_ui`, `mp_ui`, `start_overlay`, `city_map_panel`).
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("passport_panel")
	_build_ui()


func _process(_delta: float) -> void:
	# Re-assert the pause every frame while open, for `mp_ui`'s reason: the
	# claim is declined over Game Over and in a room, so a state change under
	# an open panel must not strand the world in the wrong one.
	_apply_pause(_panel_open)


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	# Esc closes, and only while we are open — otherwise this eats the
	# `ui_cancel` `player_controller._input()` uses to release the mouse.
	# `skill_tree_ui`'s guard, for `skill_tree_ui`'s reason.
	if _panel_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		set_panel_open(false)
		return
	# Raw keycode, echo-filtered so holding J does not rapid-toggle.
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
	"""Show or hide the passport, refreshing the cards on every open."""
	if open == _panel_open:
		return
	_panel_open = open
	if open:
		_refresh()
	if _card != null:
		_card.visible = open
	# The backdrop goes with the card: hidden it takes no clicks, shown it is
	# what a tap-to-close lands on.
	if _centre != null:
		_centre.visible = open
	_apply_pause(open)


func _on_backdrop_input(event: InputEvent) -> void:
	"""A tap anywhere outside the card closes the passport. The card itself is
	MOUSE_FILTER_STOP, so a tap ON it never reaches here."""
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_centre.accept_event()
		set_panel_open(false)


func _apply_pause(open: bool) -> void:
	"""
	Take or give back the pause for the panel's current state, or decline it
	for one of the two reasons the header lists.
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
	# property and `bool(null)` is a hard error, so this is what lets a scene
	# whose player is a stand-in degrade instead of throwing.
	var tree := get_tree()
	if tree == null:
		return false
	var player: Node = tree.get_first_node_in_group("player")
	return player != null and "is_game_over" in player and bool(player.is_game_over)


# ============================================================================
# THE REFRESH — what the grid shows, recomputed on every open
# ============================================================================

func _refresh() -> void:
	"""Repaint all 48 cards from the union store, baking the silhouettes the
	found kinds are still missing, then rewrite the two composed lines."""
	var found: Array[String] = BestRunStore.found_landmark_ids()
	var registry: Array = LandmarkBuildersScript.LANDMARKS
	for i in range(registry.size()):
		if i >= _cards.size():
			break
		var entry: Dictionary = registry[i]
		var id: String = String(String(entry["builder"]).trim_prefix("_landmark_"))
		_paint_card(_cards[i], entry, found.has(id), id, i)
	if _count_label != null:
		_count_label.text = tr(COUNT_LINE) % found.size()
	if _hint_label != null:
		_hint_label.text = tr(CLOSE_HINT) % OS.get_keycode_string(TOGGLE_KEY)


func _paint_card(card: Dictionary, entry: Dictionary, is_found: bool, id: String, kind: int) -> void:
	"""One card's face: silhouette + name + stamp, or the dotted frame."""
	var silhouette: TextureRect = card["silhouette"]
	var name_label: Label = card["name"]
	var stamp_label: Label = card["stamp"]
	var dotted: Control = card["dotted"]
	if not is_found:
		silhouette.visible = false
		name_label.visible = false
		stamp_label.visible = false
		dotted.visible = true
		return
	dotted.visible = false
	var texture: ImageTexture = _silhouette_for(id, kind)
	if texture != null:
		silhouette.texture = texture
		silhouette.visible = true
	else:
		# No terrain in the tree (a standalone scene): name + stamp, no picture,
		# and no error — the blank path the spec promises.
		silhouette.visible = false
	# The RAW registry key, no `tr()` — the toast's rule. A name answers the
	# quiz, which is why only a found card carries one.
	name_label.text = String(entry["name"])
	name_label.visible = true
	stamp_label.text = tr(String(entry["stamp"]))
	stamp_label.visible = true


func _silhouette_for(id: String, kind: int) -> ImageTexture:
	"""The cached silhouette for a found kind, baking it on first sight."""
	if _silhouettes.has(id):
		return _silhouettes[id] as ImageTexture
	var texture: ImageTexture = _bake_silhouette(kind)
	if texture != null:
		_silhouettes[id] = texture
	return texture


func _bake_silhouette(kind: int) -> ImageTexture:
	"""
	Call one builder headless and rasterize what it emitted, once per kind.

	The `landmark_selfcheck` call shape, term for term: the builder takes the
	live terrain (its `create_box` is the contract every builder is written
	against), a zero centre, an RNG seeded by KIND (deterministic per kind,
	nowhere near the chunk streams), and throwaway chunk/body/batch nodes that
	are freed with the bake. Landmarks with a parent_chunk accent (giza,
	liberty, eiffel, big_ben, great_wall, pharos, fernsehturm) put a mesh on
	the throwaway chunk — freed with it, so the silhouette is the boxes alone.
	Null when there is no terrain to build on, or the builder emitted nothing.
	"""
	var terrain := get_tree().get_first_node_in_group("terrain")
	if terrain == null or not terrain.has_method("create_box"):
		return null
	var registry: Array = LandmarkBuildersScript.LANDMARKS
	if kind < 0 or kind >= registry.size():
		return null
	var builder: String = String(registry[kind]["builder"])
	if not LandmarkBuildersScript.has_method(builder):
		return null
	var block_batch: Array = []
	var block_body := StaticBody3D.new()
	var chunk := MeshInstance3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = kind
	LandmarkBuildersScript.call(builder, terrain, Vector3.ZERO, rng, chunk, block_batch, block_body)
	var texture: ImageTexture = _rasterize(block_batch)
	block_body.free()
	chunk.free()
	return texture


static func _rasterize(block_batch: Array) -> ImageTexture:
	"""
	One side elevation of the emitted boxes: world X → u, world Y → v, each
	box's 8 corners → one filled BONE quad, on transparent. Two passes — the
	first finds the bounds so the kind fills the frame whatever its size, the
	second paints — because a silhouette must read at 64 px whether the place
	is a 4 m tower or an 18 m wall.
	"""
	var have := false
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for entry_variant: Variant in block_batch:
		if not (entry_variant is Dictionary):
			continue
		var xf: Transform3D = (entry_variant as Dictionary)["transform"]
		for corner in _unit_corners():
			var p: Vector3 = xf * corner
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			have = true
	if not have:
		return null
	var image := Image.create_empty(SILHOUETTE_PX, SILHOUETTE_PX, false, Image.FORMAT_RGBA8)
	var span_x: float = maxf(max_x - min_x, 0.001)
	var span_y: float = maxf(max_y - min_y, 0.001)
	var fit: float = minf((SILHOUETTE_PX - 2.0 * SILHOUETTE_PAD) / span_x,
			(SILHOUETTE_PX - 2.0 * SILHOUETTE_PAD) / span_y)
	var origin_u: float = SILHOUETTE_PX * 0.5 - (min_x + max_x) * 0.5 * fit
	var origin_v: float = SILHOUETTE_PX * 0.5 + (min_y + max_y) * 0.5 * fit
	for entry_variant: Variant in block_batch:
		if not (entry_variant is Dictionary):
			continue
		var xf: Transform3D = (entry_variant as Dictionary)["transform"]
		var low_u := INF
		var high_u := -INF
		var low_v := INF
		var high_v := -INF
		for corner in _unit_corners():
			var p: Vector3 = xf * corner
			low_u = minf(low_u, origin_u + p.x * fit)
			high_u = maxf(high_u, origin_u + p.x * fit)
			low_v = minf(low_v, origin_v - p.y * fit)
			high_v = maxf(high_v, origin_v - p.y * fit)
		var rect := Rect2i(int(floorf(low_u)), int(floorf(low_v)),
				maxi(1, int(ceilf(high_u)) - int(floorf(low_u))),
				maxi(1, int(ceilf(high_v)) - int(floorf(low_v))))
		rect = rect.intersection(Rect2i(0, 0, SILHOUETTE_PX, SILHOUETTE_PX))
		if rect.size.x > 0 and rect.size.y > 0:
			image.fill_rect(rect, COLOR_SILHOUETTE)
	return ImageTexture.create_from_image(image)


static func _unit_corners() -> Array:
	"""The 8 corners of the unit cube every box kind is inscribed in."""
	var corners: Array = []
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				corners.append(Vector3(x, y, z))
	return corners


# ============================================================================
# UI CONSTRUCTION
# ============================================================================

func _build_ui() -> void:
	# THE HUD SKIN, on THIS ROOT and nowhere else (bead `godot-test1-y1o.33`).
	theme = HudTheme.theme()

	# A CenterContainer so the card sizes to its own content and stays centred
	# at any resolution — `start_overlay.gd`'s and `skill_tree_ui.gd`'s shape.
	# HIDDEN while the passport is, and STOP while it is up: that is the
	# backdrop, and a tap on it closes the panel. A hidden Control receives no
	# input, so the closed panel still lets every click through to the world
	# beneath it.
	_centre = CenterContainer.new()
	_centre.name = "Centre"
	_centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_centre.mouse_filter = Control.MOUSE_FILTER_STOP
	_centre.visible = false
	_centre.gui_input.connect(_on_backdrop_input)
	add_child(_centre)

	_card = PanelContainer.new()
	_card.name = "Card"
	# STOP: while the passport is up it swallows clicks, so a click meant to
	# dismiss it does not fire the desktop-web click-to-capture through it.
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.visible = false
	_centre.add_child(_card)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, HudTheme.CARD_PADDING)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	margin.add_child(column)

	# RULE 1: a plain literal on a Label, translated by the engine for free.
	var title := Label.new()
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", HudTheme.heading_font())
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	column.add_child(title)
	column.add_child(_rule())

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	_count_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.name = "Cards"
	scroll.custom_minimum_size = Vector2(PANEL_INNER_WIDTH, SCROLL_HEIGHT)
	column.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", GRID_SEP)
	_grid.add_theme_constant_override("v_separation", GRID_SEP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	# All 48 cards, built once — structure here, faces in `_refresh()`.
	for i in range(LandmarkBuildersScript.LANDMARKS.size()):
		_grid.add_child(_make_card(i))

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	_hint_label.add_theme_color_override("font_color", COLOR_HINT)
	column.add_child(_hint_label)


func _make_card(kind: int) -> PanelContainer:
	"""One card's structure: a found face (silhouette + name + stamp) layered
	over an unfound dotted frame, exactly one of them visible at a time."""
	var card := PanelContainer.new()
	card.name = "Card%d" % kind
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# One ground in both states: the theme's raised strip, with the dotted frame
	# drawn over it while unfound.
	card.add_theme_stylebox_override("panel", HudTheme.strip())

	var silhouette := TextureRect.new()
	silhouette.custom_minimum_size = Vector2(SILHOUETTE_PX, SILHOUETTE_PX)
	silhouette.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	silhouette.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", COLOR_NAME)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var stamp_label := Label.new()
	stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp_label.add_theme_font_size_override("font_size", STAMP_FONT_SIZE)
	stamp_label.add_theme_color_override("font_color", COLOR_STAMP)
	stamp_label.clip_text = true
	stamp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var face := VBoxContainer.new()
	face.add_theme_constant_override("separation", 4)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(silhouette)
	face.add_child(name_label)
	face.add_child(stamp_label)
	card.add_child(face)

	var dotted := DottedFrame.new()
	dotted.set_anchors_preset(Control.PRESET_FULL_RECT)
	dotted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dotted)

	_cards.append({
		"silhouette": silhouette, "name": name_label, "stamp": stamp_label,
		"dotted": dotted,
	})
	return card


func _rule() -> ColorRect:
	"""The 1 px STEEL rule the spec puts under a section heading."""
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = HudTheme.STEEL
	rule.custom_minimum_size = Vector2(0.0, RULE_PX)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
