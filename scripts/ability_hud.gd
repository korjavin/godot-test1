extends Control
## Special-ability cooldown indicator (top-right of the screen, under the coins).
##
## Shows the current character's special ability (the F key) as a radial dial that
## empties as the ability cools down, plus the ability's name and the seconds left.
## When the power is ready, the ring turns bright green.
##
## Like the rest of the HUD it uses GROUP-BASED discovery — it finds the player via
## the "player" group rather than a hard reference — so it keeps working across
## respawns and character switches. It reads four small methods on the player:
##   get_ability_cooldown_ratio()  1.0 just-used → 0.0 ready (drives the dial)
##   get_ability_remaining()       seconds left (shown inside the dial)
##   get_ability_name()            label under the dial
##   is_ability_ready()            ready vs cooling colour
##
## It draws everything in _draw() (no texture assets needed), so it scales cleanly
## and stays asset-free, matching the project's lightweight web-build priorities.

## Cached player reference (re-fetched if it ever goes away).
var player: Node = null

## Snapshot of what the dial currently shows — written by _process, read by
## _draw, so the change-check and the drawing always agree. _have_data is false
## until the first successful read (and when the player goes away, so _draw
## clears the control instead of leaving a stale arc painted).
var _have_data: bool = false
var _ratio: float = 0.0
var _ability_ready: bool = false
var _ability_name: String = ""
var _secs: float = 0.0
## Quantized copies of ratio/secs used for the redraw change-check (see _process).
var _last_arc: int = -1
var _last_tenths: int = -1

# --- Layout / colours (tweak here) ------------------------------------------
const DIAL_RADIUS: float = 40.0
const RING_WIDTH: float = 6.0
## Vertical centre of the dial within this control.
const DIAL_CENTER_Y: float = 56.0
const COLOR_TRACK := Color(1, 1, 1, 0.16)         # faint full ring behind the arc
const COLOR_COOLING := Color(1.0, 0.62, 0.12, 0.95)  # amber arc while on cooldown
const COLOR_READY := Color(0.35, 1.0, 0.45, 0.95)    # bright green when ready
const COLOR_BACKDROP := Color(0.0, 0.0, 0.0, 0.45)   # dark disc for contrast


func _ready() -> void:
	# Never let this readout eat mouse clicks meant for the game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) \
			or not player.has_method("get_ability_cooldown_ratio"):
		# No player to read — clear the dial once rather than leaving the
		# last-drawn arc frozen on screen.
		if _have_data:
			_have_data = false
			queue_redraw()
		return
	var ratio: float = player.get_ability_cooldown_ratio()
	var ready: bool = player.is_ability_ready()
	var ability_name: String = player.get_ability_name()
	var secs: float = player.get_ability_remaining()
	# Redraw ONLY when what we would draw actually changed: ready flag, name,
	# the ratio quantized to arc-visible steps (1/128th of the ring — finer
	# changes don't move a pixel), and the seconds text at its displayed 0.1 s
	# precision. While the ability is READY and idle (the common case) nothing
	# changes, so the HUD costs zero redraws instead of one per frame.
	var arc := roundi(ratio * 128.0)
	var tenths := roundi(secs * 10.0)
	if _have_data and ready == _ability_ready and ability_name == _ability_name \
			and arc == _last_arc and tenths == _last_tenths:
		return
	_have_data = true
	_ratio = ratio
	_ability_ready = ready
	_ability_name = ability_name
	_secs = secs
	_last_arc = arc
	_last_tenths = tenths
	queue_redraw()


func _draw() -> void:
	# Draw from the _process snapshot (no player fetches here). _have_data false
	# means "nothing to show" — drawing nothing clears the control.
	if not _have_data:
		return
	var ratio := _ratio  # 1 = just used, 0 = ready
	var ready := _ability_ready
	var ability_name := _ability_name

	var font := get_theme_default_font()
	var center := Vector2(size.x * 0.5, DIAL_CENTER_Y)

	# Dark disc behind everything so the dial reads over the bright sky.
	draw_circle(center, DIAL_RADIUS + 8.0, COLOR_BACKDROP)
	# Faint full ring (the "track" the cooldown arc rides on).
	draw_arc(center, DIAL_RADIUS, 0.0, TAU, 48, COLOR_TRACK, RING_WIDTH, true)

	if ready:
		# Ready: a full, bright green ring.
		draw_arc(center, DIAL_RADIUS, 0.0, TAU, 48, COLOR_READY, RING_WIDTH, true)
	else:
		# Cooling: an amber arc that empties clockwise from the top as time passes.
		var start := -PI / 2.0
		var end := start + TAU * ratio
		draw_arc(center, DIAL_RADIUS, start, end, 48, COLOR_COOLING, RING_WIDTH, true)

	# Big "F" key hint in the centre of the dial.
	var key_size := 30
	var key_col := COLOR_READY if ready else Color(1, 1, 1, 0.95)
	_draw_centered(font, "F", center + Vector2(0.0, key_size * 0.36), key_size, key_col)

	# Ability name below the dial.
	var name_size := 18
	_draw_centered(font, ability_name, Vector2(center.x, center.y + DIAL_RADIUS + 24.0),
		name_size, Color(1, 1, 1, 0.97))

	# Seconds remaining inside the dial while cooling down.
	if not ready:
		_draw_centered(font, "%.1f" % _secs, Vector2(center.x, center.y + 22.0),
			14, Color(1, 0.85, 0.6, 0.95))


func _draw_centered(font: Font, text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	"""Draw `text` horizontally centred on `baseline_center` with a dark outline
	for legibility over any background."""
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(baseline_center.x - width * 0.5, baseline_center.y)
	# Outline first (drawn slightly thicker), then the fill on top.
	font.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, 4, Color(0, 0, 0, 0.85))
	font.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, color)
