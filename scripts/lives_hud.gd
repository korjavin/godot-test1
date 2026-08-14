extends Control
## Lives HUD — a row of little red hearts in the top-left corner.
##
## Like the coin counter, this holds no hard reference to the player: it finds it
## through the "player" group and mirrors its `lives` count, so it keeps working
## across respawns and restarts. Remaining lives are drawn as solid red hearts;
## lost ones fade to a dim outline-coloured heart so you can still read the total.
##
## The hearts are drawn by hand in _draw() (two lobe circles + a triangle point)
## rather than using a font glyph or an image, so they render identically on every
## platform with no asset dependency — matching this project's "draw it in code"
## style (see the crocodile/player procedural animation).

## The pip total is read from the PLAYER each frame (max(MAX_LIVES, lives)),
## not duplicated here as a constant — extra lives earned from coins can push
## `lives` above MAX_LIVES (up to the player's LIVES_CAP), and a 4th/5th heart
## must render. Reading the single source of truth also kills the old
## keep-in-sync bug this file used to have.

## Size (roughly the height in pixels) of one heart, and the gap between hearts.
const HEART_SIZE: float = 32.0
const HEART_SPACING: float = 10.0

## Colours for a remaining life vs a spent one.
const FILLED_COLOR: Color = Color(0.9, 0.15, 0.2)
const EMPTY_COLOR: Color = Color(0.35, 0.14, 0.16, 0.55)

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Last values we drew, so we only repaint when either count actually changes.
var _drawn_lives: int = -1
var _drawn_total: int = -1


func _ready() -> void:
	add_to_group("lives_hud")
	# A HUD overlay must never eat clicks meant for the game / Game Over button.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")

	var lives: int = 0
	var total: int = 0
	if player and "lives" in player:
		lives = player.lives
		# Total pips = the run's starting hearts, plus any extra lives that
		# pushed `lives` above that (see EXTRA_LIFE_COINS in player_controller).
		total = maxi(player.MAX_LIVES, lives)

	# Repaint only on change — _draw is comparatively expensive to run every frame.
	if lives != _drawn_lives or total != _drawn_total:
		_drawn_lives = lives
		_drawn_total = total
		queue_redraw()


func _draw() -> void:
	for i in _drawn_total:
		var center := Vector2(
			HEART_SIZE * 0.5 + i * (HEART_SIZE + HEART_SPACING),
			HEART_SIZE * 0.5
		)
		var filled := i < _drawn_lives
		_draw_heart(center, HEART_SIZE, FILLED_COLOR if filled else EMPTY_COLOR)


func _draw_heart(center: Vector2, size: float, fill: Color) -> void:
	"""
	Draw one heart from convex pieces: two overlapping circles for the top lobes
	and a downward triangle for the point. Convex pieces avoid any concave-polygon
	fill quirks, so the shape renders correctly everywhere.

	@param center: Centre of the heart in this control's local pixels
	@param size: Overall heart size in pixels
	@param fill: Fill colour (solid for a life left, dim for a lost one)
	"""
	var lobe_radius := size * 0.28
	var lobe_dx := size * 0.26
	var lobe_dy := size * 0.16
	var left_lobe := center + Vector2(-lobe_dx, -lobe_dy)
	var right_lobe := center + Vector2(lobe_dx, -lobe_dy)
	var point := center + Vector2(0.0, size * 0.52)

	# Triangle from the lobes' outer edges down to the bottom point.
	var triangle := PackedVector2Array([
		left_lobe + Vector2(-lobe_radius, 0.0),
		right_lobe + Vector2(lobe_radius, 0.0),
		point,
	])
	draw_colored_polygon(triangle, fill)
	draw_circle(left_lobe, lobe_radius, fill)
	draw_circle(right_lobe, lobe_radius, fill)
